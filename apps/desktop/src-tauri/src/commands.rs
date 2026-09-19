//! Tauri 命令层：WebView 与主进程之间唯一的入口（SPEC-M00 §5.1 边界规则）。
//!
//! 三条贯穿全层的约定：
//!
//!   1. **每个命令都收发统一信封**（B-6）。参数是 `Value` 而不是强类型的
//!      `struct`，这样"参数不合契约"这件事由 [`contracts::validate_boundary`]
//!      按 schema 判定并给出稳定错误码，而不是变成 Tauri 自己的反序列化报错 ——
//!      后者会绕过信封、也无法被契约测试覆盖。
//!   2. **命令永不返回 `Err`**。失败也是 `envelope{ok:false}`。若用 `Result`，
//!      JS 侧会收到一个 reject，前端就得分两条路径处理错误，信封也就白定了。
//!   3. **响应里没有密钥**。凭据命令只回一个布尔值；`settings_read` 也只回
//!      「是否已配置」。这条由 `responses_never_contain_the_api_key` 断言。
//!
//! 每个命令体都写成一个接收 `&AppState` 的自由函数，`#[tauri::command]` 只做转发。
//! 这样单测调的就是生产代码本身，而不是一份抄过来的副本 —— 后者会在真实命令
//! 悄悄改动时继续通过。`State<'_, T>` 在单测里也确实不好构造。

use serde::Deserialize;
use serde_json::{json, Value};
use tauri::ipc::Channel;
use tauri::State;

use crate::contracts::{
    success_envelope, validate_boundary, Boundary, ContractError, CODE_INTERNAL_UNEXPECTED,
};
use crate::http::Method;
use crate::secrets::{SecretStoreError, DEEPSEEK_API_KEY};
use crate::sidecar::{LaunchSpec, SidecarSlot, CHAT_STREAM_PATH, HEALTH_PATH};
use crate::state::AppState;

/// 入站请求被接受后的样子。
struct Incoming {
    request_id: String,
    data: Value,
}

/// 从请求里取出可用的 requestId；取不到时用固定占位符。
///
/// 占位符而不是回显：回显会把一个未经校验的字符串放进我们的响应里。
fn fallback_request_id(request: &Value) -> String {
    request
        .get("requestId")
        .and_then(Value::as_str)
        .filter(|s| !s.is_empty() && s.len() <= 128)
        .unwrap_or("unknown")
        .to_string()
}

/// 校验入站信封并取出 `requestId` 与 `data`。
///
/// 失败时返回一个**已经可以直接下发**的失败信封：即便调用方连
/// `requestId` 都没给对，也要能拿到一个结构合法的失败响应。
fn accept(request: &Value) -> Result<Incoming, Value> {
    if let Err(error) = validate_boundary(Boundary::WebviewToRust, request) {
        let request_id = fallback_request_id(request);
        return Err(error.to_envelope(&request_id));
    }

    let request_id = request["requestId"]
        .as_str()
        .expect("已通过 schema 校验的请求必有 requestId")
        .to_string();
    Ok(Incoming {
        request_id,
        // data 在 schema 里是布尔 true（任意 JSON 值），这里取不到就是 null，
        // 由各命令自己的载荷解析去拒绝。
        data: request.get("data").cloned().unwrap_or(Value::Null),
    })
}

/// 把 `data` 反序列化成具体载荷；失败即 `INVALID_INPUT`。
///
/// `deny_unknown_fields` 是有意的：多出来的字段会被拒绝，而不是被静默忽略 ——
/// 否则前端以为设置生效了、主进程其实没读，这类偏差在界面上极难发现。
fn parse_payload<T: for<'de> Deserialize<'de>>(
    incoming: &Incoming,
    what: &str,
) -> Result<T, ContractError> {
    serde_json::from_value(incoming.data.clone())
        .map_err(|e| ContractError::invalid_input(format!("{what}载荷不合法：{e}")))
}

/// 设置快照：发给 WebView 的全部设置信息。**不含密钥**，只含"是否已配置"。
fn settings_snapshot(state: &AppState) -> Value {
    let settings = state.settings.load();
    let credential_configured = matches!(state.secrets.get(DEEPSEEK_API_KEY), Ok(Some(_)));
    json!({
        "cloudConsentGranted": settings.cloud_consent_granted,
        "model": settings.model,
        "baseUrl": settings.base_url,
        "credentialConfigured": credential_configured,
    })
}

/// 凭据存储的失败。只透出固定文案，不透出任何载荷 —— 见 `secrets.rs` 的模块文档。
fn secret_store_failure(error: &SecretStoreError) -> ContractError {
    ContractError::internal_error(format!("凭据存储操作失败：{}", error.message))
}

// ---------------------------------------------------------------------------
// 命令体
// ---------------------------------------------------------------------------

/// 读取设置与凭据状态。WebView 只能知道"配没配"，拿不到值。
fn handle_settings_read(state: &AppState, request: &Value) -> Value {
    let incoming = match accept(request) {
        Ok(v) => v,
        Err(envelope) => return envelope,
    };
    success_envelope(&incoming.request_id, settings_snapshot(state), vec![])
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct SettingsPatch {
    cloud_consent_granted: Option<bool>,
    model: Option<String>,
    base_url: Option<String>,
}

/// 写入非敏感设置。**不接受密钥字段** —— 密钥只走 `credential_set`。
fn handle_settings_write(state: &AppState, request: &Value) -> Value {
    let incoming = match accept(request) {
        Ok(v) => v,
        Err(envelope) => return envelope,
    };
    let patch: SettingsPatch = match parse_payload(&incoming, "设置") {
        Ok(v) => v,
        Err(error) => return error.to_envelope(&incoming.request_id),
    };

    let mut settings = state.settings.load();
    if let Some(consent) = patch.cloud_consent_granted {
        settings.cloud_consent_granted = consent;
    }
    if let Some(model) = patch.model {
        settings.model = model;
    }
    if let Some(base_url) = patch.base_url {
        settings.base_url = base_url;
    }

    match state.settings.save(&settings) {
        Ok(()) => success_envelope(&incoming.request_id, settings_snapshot(state), vec![]),
        Err(message) => ContractError::invalid_input(message).to_envelope(&incoming.request_id),
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct CredentialPayload {
    api_key: String,
}

/// 保存 DeepSeek 凭据到 OS 凭据存储。响应只有"已配置"这一个布尔值。
fn handle_credential_set(state: &AppState, request: &Value) -> Value {
    let incoming = match accept(request) {
        Ok(v) => v,
        Err(envelope) => return envelope,
    };
    let payload: CredentialPayload = match parse_payload(&incoming, "凭据") {
        Ok(v) => v,
        Err(error) => return error.to_envelope(&incoming.request_id),
    };

    // 只做形态检查，不判断密钥"对不对" —— 那要靠一次真实调用才知道，
    // 而且不该把候选密钥发给任何服务去试。
    let key = payload.api_key.trim();
    if key.is_empty() {
        return ContractError::invalid_input("API Key 不能为空").to_envelope(&incoming.request_id);
    }
    if key.chars().any(char::is_whitespace) {
        return ContractError::invalid_input("API Key 不能包含空白字符（请检查是否复制时带了换行）")
            .to_envelope(&incoming.request_id);
    }
    if key.len() > 512 {
        return ContractError::invalid_input("API Key 长度超出预期上限")
            .to_envelope(&incoming.request_id);
    }

    match state.secrets.set(DEEPSEEK_API_KEY, key) {
        Ok(()) => {
            // 已经在跑的 Sidecar 手里握着**旧**密钥（它是启动时经 stdin 拿到的内存副本），
            // 必须让它退场，否则"换了密钥却还在用旧的"会成为一类极难排查的问题。
            // 下一次请求会按新配置重新拉起。
            state.sidecar.stop();
            success_envelope(
                &incoming.request_id,
                json!({ "credentialConfigured": true }),
                vec![],
            )
        }
        Err(error) => secret_store_failure(&error).to_envelope(&incoming.request_id),
    }
}

/// 清除已保存的 DeepSeek 凭据（幂等）。
fn handle_credential_clear(state: &AppState, request: &Value) -> Value {
    let incoming = match accept(request) {
        Ok(v) => v,
        Err(envelope) => return envelope,
    };
    match state.secrets.delete(DEEPSEEK_API_KEY) {
        Ok(()) => {
            // 同上，而且这里更硬：用户刚删掉密钥，不能还留一个持有它内存副本的进程。
            state.sidecar.stop();
            success_envelope(
                &incoming.request_id,
                json!({ "credentialConfigured": false }),
                vec![],
            )
        }
        Err(error) => secret_store_failure(&error).to_envelope(&incoming.request_id),
    }
}

// ---------------------------------------------------------------------------
// Sidecar 代理（Rust ↔ Python 的两条边界，SPEC-M00 §5.3）
// ---------------------------------------------------------------------------

/// 单次流式回答最多转发多少帧。纯粹的防御上界：连接关闭本来就会终止循环，
/// 这里只是不给"某个上游永远发不完"留下无限循环的可能。
const MAX_STREAM_FRAMES: usize = 100_000;

/// 把 Sidecar 回来的信封改写成"以本进程的 requestId 出口"的形状。
///
/// 为什么每一帧都要改写而不是原样透传：出口信封必须只有一个 requestId 来源，
/// 否则日志配对、界面去重都要去猜哪个 id 才是这次的。改写只做两件事 ——
/// 换 id、丢掉契约不允许的字段（后者靠随后的 `RustToWebview` 校验兜住）。
fn relay_envelope(body: &Value, request_id: &str) -> Value {
    if body.get("ok").and_then(Value::as_bool) == Some(true) {
        let mut envelope = json!({
            "ok": true,
            "requestId": request_id,
            "data": body.get("data").cloned().unwrap_or(Value::Null),
            "citations": body.get("citations").cloned().unwrap_or_else(|| json!([])),
        });
        if let Some(usage) = body.get("usage") {
            envelope["usage"] = usage.clone();
        }
        return envelope;
    }

    // 对端给了失败形态，但错误详情不成形时也要能给出可读的东西，
    // 而不是一个没有 error 字段的"失败"（那不合契约）。
    let error = body.get("error").cloned().unwrap_or_else(|| {
        json!({
            "code": CODE_INTERNAL_UNEXPECTED,
            "message": "Sidecar 报告了失败，但没有给出错误详情",
            "retryable": false,
        })
    });
    json!({ "ok": false, "requestId": request_id, "error": error })
}

/// 校验一次入站的 Sidecar 负载，再按出站契约改写并校验。
///
/// 两次校验对应 SPEC-M00 §5.3 表格里的 `sidecar->rust` 与 `rust->webview` 两条边界：
/// 前者防"畸形结果进入业务逻辑"，后者防"畸形结果被透传给界面"。两者都不是多余的 ——
/// 改写本身也可能引入不合契约的形状（例如对端成功了却没带 citations）。
fn relay_and_validate(body: &Value, request_id: &str) -> Result<Value, Value> {
    if let Err(error) = validate_boundary(Boundary::SidecarToRust, body) {
        return Err(error.to_envelope(request_id));
    }
    let relayed = relay_envelope(body, request_id);
    if let Err(error) = validate_boundary(Boundary::RustToWebview, &relayed) {
        return Err(error.to_envelope(request_id));
    }
    Ok(relayed)
}

/// 起（或复用）Sidecar 并读一次健康检查。
///
/// 这是"凭据配好之后到底能不能用"的自检入口：它真的把 Sidecar 拉起来并走一次
/// HTTP 往返，而不是只看配置文件。
///
/// 只依赖 `SidecarSlot` 而不是整个 `AppState`，是为了能原样搬进阻塞线程 ——
/// `tauri::State` 的借用活不过 `spawn_blocking` 那个边界。
fn handle_sidecar_status(slot: &SidecarSlot, spec: &LaunchSpec, request_id: &str) -> Value {
    let handle = match slot.acquire(spec) {
        Ok(handle) => handle,
        Err(error) => {
            // Sidecar 起不来最常见的两个原因（没装依赖、发布构建没有打包路径）
            // 都已经写在 error.message 里，这里原样带给界面。
            return ContractError::internal_error(error.message).to_envelope(request_id);
        }
    };

    let mut response = match handle.client().send(Method::Get, HEALTH_PATH, None) {
        Ok(response) => response,
        Err(error) => {
            return ContractError::internal_error(format!("无法连接 Sidecar：{error}"))
                .to_envelope(request_id)
        }
    };
    let body = match response.read_json() {
        Ok(body) => body,
        Err(error) => {
            return ContractError::internal_error(error.message).to_envelope(request_id);
        }
    };

    let relayed = match relay_and_validate(&body, request_id) {
        Ok(envelope) => envelope,
        Err(envelope) => return envelope,
    };

    // 请求期也复核一次契约版本：启动时协商过，但 Sidecar 可能在此期间被换掉
    // （例如用户手工替换了 venv）。不一致就拒绝服务，不带着不匹配的假设继续跑。
    if relayed.get("ok").and_then(Value::as_bool) == Some(true) {
        let reported = relayed["data"]["contractVersion"].as_str().unwrap_or_default();
        if reported != crate::contracts::CONTRACT_VERSION {
            return ContractError::version_mismatch_reported(reported).to_envelope(request_id);
        }
    }
    relayed
}

/// 把一次对话请求代理到 Sidecar，并把流式回答逐帧推给 WebView。
///
/// 这是全仓库第一条真正的 IPC 命令，也是 SPEC-M00 §5.3 四条边界同时被走一遍的地方：
///
/// ```text
/// WebView --①--> Rust --②--> Sidecar --③--> DeepSeek
///         <--④--     <--⑤--
/// ```
///
/// ① `WebviewToRust`（`accept`）② `RustToSidecar`（发出去之前）⑤ `SidecarToRust`
/// （每一帧进来时）④ `RustToWebview`（每一帧出去之前）。
///
/// 权限门禁（同意、凭据）刻意只在主进程里判：那是唯一知道这两项策略的一层。
/// 界面也会拦，但界面上的拦截是提示，不是保证。
fn handle_chat_stream(
    slot: &SidecarSlot,
    spec: &LaunchSpec,
    consent_granted: bool,
    request: &Value,
    channel: &Channel<Value>,
) -> Value {
    let incoming = match accept(request) {
        Ok(v) => v,
        Err(envelope) => return envelope,
    };
    let request_id = incoming.request_id;

    if !consent_granted {
        return crate::state::consent_required().to_envelope(&request_id);
    }
    if spec.api_key.is_none() {
        return crate::state::credential_required().to_envelope(&request_id);
    }

    let handle = match slot.acquire(spec) {
        Ok(handle) => handle,
        Err(error) => {
            return ContractError::internal_error(error.message).to_envelope(&request_id);
        }
    };

    // 出站边界：发往 Sidecar 的请求体在序列化后、发送前校验。
    if let Err(error) = validate_boundary(Boundary::RustToSidecar, request) {
        return error.to_envelope(&request_id);
    }

    let mut response = match handle
        .client()
        .send(Method::Post, CHAT_STREAM_PATH, Some(request))
    {
        Ok(response) => response,
        Err(error) => {
            return ContractError::internal_error(format!("无法连接 Sidecar：{error}"))
                .to_envelope(&request_id);
        }
    };

    // 非 200：按协议，正文是一份单帧信封（鉴权失败、请求体过大、路径不对等）。
    if response.status != 200 {
        let body = match response.read_json() {
            Ok(body) => body,
            Err(error) => {
                return ContractError::internal_error(format!(
                    "Sidecar 返回 HTTP {}：{}",
                    response.status, error.message
                ))
                .to_envelope(&request_id);
            }
        };
        return match relay_and_validate(&body, &request_id) {
            Ok(envelope) => envelope,
            Err(envelope) => envelope,
        };
    }

    let mut last: Option<Value> = None;
    for _ in 0..MAX_STREAM_FRAMES {
        let line = match response.next_line() {
            Ok(Some(line)) => line,
            Ok(None) => break,
            Err(error) => {
                let envelope = ContractError::internal_error(format!("读取回答流失败：{error}"))
                    .to_envelope(&request_id);
                let _ = channel.send(envelope.clone());
                return envelope;
            }
        };

        let Some(payload) = line.strip_prefix("data:") else {
            // SSE 里允许出现注释与心跳帧，跳过它们而不是报错。
            continue;
        };
        let Ok(frame) = serde_json::from_str::<Value>(payload.trim()) else {
            continue;
        };

        let relayed = match relay_and_validate(&frame, &request_id) {
            Ok(envelope) => envelope,
            Err(envelope) => {
                // 一帧不合契约就中止本次回答：继续转发等于把未经校验的内容渲染出去。
                let _ = channel.send(envelope.clone());
                return envelope;
            }
        };

        let terminal = relayed.get("ok").and_then(Value::as_bool) == Some(false)
            || relayed["data"]["type"].as_str() == Some("done");

        // 前端可能已经不再监听（组件卸载、窗口关闭）。发送失败就停止转发，
        // 也停止从 Sidecar 读取 —— 丢掉 response 会关闭 TCP 连接，Sidecar 随即收手。
        if channel.send(relayed.clone()).is_err() {
            return relayed;
        }
        last = Some(relayed);
        if terminal {
            break;
        }
    }

    last.unwrap_or_else(|| {
        ContractError::internal_error("Sidecar 没有返回任何回答内容").to_envelope(&request_id)
    })
}

// ---------------------------------------------------------------------------
// Tauri 入口（只做转发）
// ---------------------------------------------------------------------------

#[tauri::command]
pub fn settings_read(state: State<'_, AppState>, request: Value) -> Value {
    handle_settings_read(&state, &request)
}

#[tauri::command]
pub fn settings_write(state: State<'_, AppState>, request: Value) -> Value {
    handle_settings_write(&state, &request)
}

#[tauri::command]
pub fn credential_set(state: State<'_, AppState>, request: Value) -> Value {
    handle_credential_set(&state, &request)
}

#[tauri::command]
pub fn credential_clear(state: State<'_, AppState>, request: Value) -> Value {
    handle_credential_clear(&state, &request)
}

/// 自检：拉起 Sidecar 并读一次健康检查。
///
/// 走 `spawn_blocking`：这里会真的起进程 + 做一次 HTTP 往返（常常几百毫秒），
/// 同步命令跑在主线程上会卡住界面。
///
/// 返回类型写成 `Result` 是**Tauri 宏的要求**（带借用参数的 async 命令必须返回
/// `Result`），不是本仓库的接口设计：这些命令永远返回 `Ok(信封)`，从不 `Err`。
/// 理由见本模块顶部第 2 条 —— 失败必须是信封，前端才只有一条错误路径。
#[tauri::command]
pub async fn sidecar_status(state: State<'_, AppState>, request: Value) -> Result<Value, String> {
    let request_id = fallback_request_id(&request);
    // `State` 的借用不能跨过 spawn_blocking，所以先把要用的东西取出来。
    // 入站校验在这里做掉：放进阻塞线程会让"参数不合契约"和"后台故障"混在一起。
    if let Err(envelope) = accept(&request) {
        return Ok(envelope);
    }
    let spec = match state.launch_spec() {
        Ok(spec) => spec,
        Err(error) => return Ok(error.to_envelope(&request_id)),
    };
    let slot = state.sidecar_slot();
    // 闭包按值拿走 request_id，错误分支还要用，所以留一份。
    let request_id_for_error = request_id.clone();

    match tauri::async_runtime::spawn_blocking(move || {
        handle_sidecar_status(&slot, &spec, &request_id)
    })
    .await
    {
        Ok(envelope) => Ok(envelope),
        Err(error) => Ok(ContractError::internal_error(format!("后台任务失败：{error}"))
            .to_envelope(&request_id_for_error)),
    }
}

/// 一次真实的流式回答：Rust 只做校验与转发，不理解 `data` 的业务形状。
///
/// 与 `sidecar_status` 同理：`Result` 是 Tauri 宏对"带借用参数的 async 命令"的要求，
/// 这里永远返回 `Ok(信封)`。
#[tauri::command]
pub async fn chat_stream(
    state: State<'_, AppState>,
    channel: Channel<Value>,
    request: Value,
) -> Result<Value, String> {
    let request_id = fallback_request_id(&request);
    let consent_granted = state.cloud_consent_granted();
    let spec = match state.launch_spec() {
        Ok(spec) => spec,
        Err(error) => return Ok(error.to_envelope(&request_id)),
    };
    let slot = state.sidecar_slot();
    let request_id_for_error = request_id.clone();

    match tauri::async_runtime::spawn_blocking(move || {
        handle_chat_stream(&slot, &spec, consent_granted, &request, &channel)
    })
    .await
    {
        Ok(envelope) => Ok(envelope),
        Err(error) => Ok(ContractError::internal_error(format!("后台任务失败：{error}"))
            .to_envelope(&request_id_for_error)),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::contracts::{CODE_INVALID_INPUT, CODE_SCHEMA_INVALID};
    use crate::secrets::InMemorySecretStore;
    use crate::settings::SettingsStore;
    use std::sync::Arc;

    const TEST_KEY: &str = "sk-live-SECRET-abcdef0123456789";

    fn temp_dir(tag: &str) -> std::path::PathBuf {
        let unique = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .expect("系统时间应晚于 UNIX 纪元")
            .as_nanos();
        let dir = std::env::temp_dir().join(format!("engm-commands-{tag}-{unique}"));
        std::fs::create_dir_all(&dir).expect("无法创建临时目录");
        dir
    }

    fn state_in(dir: &std::path::Path) -> AppState {
        AppState::new(
            SettingsStore::in_app_data_dir(dir),
            Arc::new(InMemorySecretStore::new()),
        )
    }

    fn envelope(request_id: &str, data: Value) -> Value {
        json!({ "ok": true, "requestId": request_id, "data": data, "citations": [] })
    }

    #[test]
    fn settings_read_reports_unconfigured_without_a_credential() {
        let dir = temp_dir("unconfigured");
        let state = state_in(&dir);

        let response = handle_settings_read(&state, &envelope("req-1", json!({})));
        assert_eq!(response["ok"], true);
        assert_eq!(response["requestId"], "req-1");
        assert_eq!(response["data"]["credentialConfigured"], false);
        assert_eq!(
            response["data"]["cloudConsentGranted"], false,
            "同意必须默认关闭"
        );
        // 无来源时必须是空数组，不能省略（envelope.schema.json 的必填项）。
        assert_eq!(response["citations"], json!([]));
        std::fs::remove_dir_all(&dir).ok();
    }

    /// §9.2 / T012 验收：任何命令的响应体都不得包含密钥。
    #[test]
    fn responses_never_contain_the_api_key() {
        let dir = temp_dir("no-key-leak");
        let state = state_in(&dir);

        let stored = handle_credential_set(&state, &envelope("req-2", json!({ "apiKey": TEST_KEY })));
        assert_eq!(stored["ok"], true);
        assert_eq!(stored["data"]["credentialConfigured"], true);
        assert_eq!(
            state.secrets.get(DEEPSEEK_API_KEY).unwrap().as_deref(),
            Some(TEST_KEY),
            "密钥应真的进了存储"
        );

        let read_back = handle_settings_read(&state, &envelope("req-3", json!({})));
        assert_eq!(read_back["data"]["credentialConfigured"], true);

        for response in [&stored, &read_back] {
            let rendered = serde_json::to_string(response).expect("可序列化");
            assert!(
                !rendered.contains(TEST_KEY),
                "命令响应里出现了密钥：{rendered}"
            );
        }
        std::fs::remove_dir_all(&dir).ok();
    }

    /// 密钥也不能被写进设置文件。
    #[test]
    fn the_api_key_never_reaches_the_settings_file() {
        let dir = temp_dir("no-key-on-disk");
        let state = state_in(&dir);
        handle_credential_set(&state, &envelope("req-4", json!({ "apiKey": TEST_KEY })));

        let settings_file = state.settings.path();
        if settings_file.exists() {
            let content = std::fs::read_to_string(settings_file).expect("可读");
            assert!(!content.contains(TEST_KEY), "设置文件里出现了密钥：{content}");
        }
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn malformed_requests_get_a_valid_failure_envelope() {
        let dir = temp_dir("malformed");
        let state = state_in(&dir);

        // 缺 requestId：连 id 都读不出来时，响应仍必须是合法信封，
        // 且错误码是 SCHEMA_INVALID（连信封都不合契约），不是 INVALID_INPUT。
        let response =
            handle_settings_read(&state, &json!({ "ok": true, "data": null, "citations": [] }));
        assert_eq!(response["ok"], false);
        assert_eq!(response["error"]["code"], CODE_SCHEMA_INVALID);
        assert_eq!(
            response["requestId"], "unknown",
            "读不出 id 时应使用固定占位符，而不是回显对方给的字符串"
        );
        validate_boundary(Boundary::RustToWebview, &response)
            .expect("失败响应本身必须过契约校验");

        // 信封合法但载荷不合法：这时才是 INVALID_INPUT。
        let bad_payload = handle_settings_write(
            &state,
            &envelope("req-invalid", json!({ "model": 12345 })),
        );
        assert_eq!(bad_payload["ok"], false);
        assert_eq!(bad_payload["error"]["code"], CODE_INVALID_INPUT);
        assert_eq!(
            bad_payload["requestId"], "req-invalid",
            "信封合法时应回显调用方的 requestId，便于日志配对"
        );
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn credential_set_rejects_blank_and_multiline_keys() {
        let dir = temp_dir("blank-key");
        let state = state_in(&dir);
        for bad in ["", "   ", "sk-abc\ndef"] {
            let response = handle_credential_set(&state, &envelope("req-5", json!({ "apiKey": bad })));
            assert_eq!(response["ok"], false, "空/含空白的密钥应被拒绝：{bad:?}");
        }
        assert_eq!(
            state.secrets.get(DEEPSEEK_API_KEY).unwrap(),
            None,
            "被拒绝的密钥不应进入凭据存储"
        );
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn credential_clear_is_idempotent_and_does_not_touch_other_state() {
        let dir = temp_dir("clear");
        let state = state_in(&dir);
        handle_credential_set(&state, &envelope("req-6", json!({ "apiKey": TEST_KEY })));

        for _ in 0..2 {
            let response = handle_credential_clear(&state, &envelope("req-7", json!({})));
            assert_eq!(response["ok"], true);
            assert_eq!(response["data"]["credentialConfigured"], false);
        }
        assert_eq!(state.secrets.get(DEEPSEEK_API_KEY).unwrap(), None);
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn settings_write_updates_only_the_fields_it_was_given() {
        let dir = temp_dir("patch");
        let state = state_in(&dir);

        let response = handle_settings_write(
            &state,
            &envelope("req-8", json!({ "cloudConsentGranted": true })),
        );
        assert_eq!(response["ok"], true);
        assert_eq!(response["data"]["cloudConsentGranted"], true);
        assert_eq!(
            response["data"]["model"], crate::settings::DEFAULT_MODEL,
            "未提供的字段应保持原值"
        );

        // 落盘后再读，确认不是只在内存里改了。
        let reloaded = handle_settings_read(&state, &envelope("req-9", json!({})));
        assert_eq!(reloaded["data"]["cloudConsentGranted"], true);
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn settings_write_rejects_unknown_fields_and_bad_urls() {
        let dir = temp_dir("reject");
        let state = state_in(&dir);

        let unknown = handle_settings_write(
            &state,
            &envelope("req-a", json!({ "apiKey": TEST_KEY })),
        );
        assert_eq!(unknown["ok"], false, "设置命令不得接受密钥字段");

        let bad_url = handle_settings_write(
            &state,
            &envelope("req-b", json!({ "baseUrl": "http://api.deepseek.com" })),
        );
        assert_eq!(bad_url["ok"], false, "明文 http 的服务地址应被拒绝");
        std::fs::remove_dir_all(&dir).ok();
    }
}
