//! Sidecar 进程的生命周期（SPEC-M00 §5.1 / B-1、B-2）。
//!
//! 主进程是唯一能拉起、也能唯一访问 Sidecar 的一方。这里管四件事：
//!
//! 1. **怎么起**：Windows 上直接执行 `services/ai-core/.venv/Scripts/python.exe -m english_teacher.sidecar`，
//!    **不经过 `uv run`**。多一层 uv 会让 `Child::kill` 只杀掉 uv 而留下真正的 Python 进程；
//!    直接起 venv 里的解释器，杀谁就是谁。
//! 2. **怎么把 token 与密钥交过去**：写在 stdin 的第一行。命令行参数与环境变量对同机
//!    其他进程可见，stdin 只在父子之间存在。
//! 3. **怎么确认它起来了**：读它 stdout 的第一行（端口 + 契约版本），并按 SPEC-M00 §5.3
//!    第 5 条做版本协商；不一致就拒绝服务，而不是带着不匹配的假设继续跑。
//! 4. **怎么收场**：`Drop` 里 kill。同时 stdin 保持打开 —— 那是"父进程还活着"的信号，
//!    主进程即使崩溃，管道关闭也会让 Sidecar 自己退出（Python 侧的同名机制见 `server.py`）。

use std::io::{BufRead, BufReader, Read, Write};
use std::path::{Path, PathBuf};
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::Mutex;

use serde::Deserialize;
use serde_json::{json, Value};

use crate::contracts::{self, ContractError};

/// Sidecar 的模块入口，对应 Python 侧的 `english_teacher/sidecar/__main__.py`。
const SIDECAR_MODULE: &str = "english_teacher.sidecar";

/// Sidecar 的 HTTP 路径。与 Python 侧 `server.py` 的常量一一对应，
/// 两侧各有一条断言钉住它们（Python 侧见 `test_http_paths_match_the_rust_side`）。
pub const HEALTH_PATH: &str = "/v1/health";
pub const CHAT_STREAM_PATH: &str = "/v1/chat/stream";

/// token 的随机字节数。32 字节 = 64 个十六进制字符，与 Python 侧的
/// `TOKEN_MIN_LENGTH = 32` 相容而远高于它。
const TOKEN_BYTES: usize = 32;

/// 指向 AI Core 服务目录的环境变量。开发期有内置默认值；发布构建**必须**显式给出。
pub const AI_CORE_DIR_ENV: &str = "ENGM_AI_CORE_DIR";

/// Windows 的 `CREATE_NO_WINDOW`：不要为子进程弹出控制台窗口。
#[cfg(windows)]
const CREATE_NO_WINDOW: u32 = 0x0800_0000;

#[derive(Debug, Clone)]
pub struct SidecarError {
    pub message: String,
}

impl SidecarError {
    fn new(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
        }
    }
}

impl std::fmt::Display for SidecarError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.message)
    }
}

impl From<ContractError> for SidecarError {
    fn from(error: ContractError) -> Self {
        Self::new(error.message)
    }
}

/// 决定 Sidecar 行为的三项配置。
///
/// 单独抽出来是因为它同时承担两个职责：作为启动参数下发，以及作为
/// "要不要重启 Sidecar" 的比较依据 —— 用户改了 API Key 或模型 id 之后，
/// 已经在跑的那个进程还持有旧值，必须重启才能生效。
#[derive(Clone, PartialEq, Eq)]
pub struct LaunchSpec {
    pub api_key: Option<String>,
    pub base_url: Option<String>,
    pub model: Option<String>,
}

/// 手写 `Debug`：`api_key` 是密钥，`{:?}` 是它会泄漏进日志的最短路径。
impl std::fmt::Debug for LaunchSpec {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("LaunchSpec")
            .field(
                "api_key",
                &self.api_key.as_ref().map(|_| "<已配置，已隐去>"),
            )
            .field("base_url", &self.base_url)
            .field("model", &self.model)
            .finish()
    }
}

impl LaunchSpec {
    /// 尚未配置凭据时也要能起 Sidecar：健康检查与不依赖云模型的功能不受影响。
    pub fn from_parts(api_key: Option<String>, base_url: String, model: String) -> Self {
        Self {
            api_key,
            base_url: Some(base_url),
            model: Some(model),
        }
    }
}

/// 一个活着的 Sidecar 进程。
pub struct SidecarHandle {
    port: u16,
    token: String,
    contract_version: String,
    child: Mutex<Child>,
    /// 保持打开。Drop 这一项会让 Sidecar 读到 EOF 并自行退出 ——
    /// 这是"主进程崩溃也不留孤儿进程"的机制本身，不是随手留着的句柄。
    _stdin: ChildStdin,
}

impl SidecarHandle {
    pub fn port(&self) -> u16 {
        self.port
    }

    pub fn contract_version(&self) -> &str {
        &self.contract_version
    }

    /// 只在本进程内使用，不对外暴露给 WebView（B-3）。
    pub fn client(&self) -> crate::http::LoopbackClient {
        crate::http::LoopbackClient::new(self.port, self.token.clone())
    }

    pub fn is_alive(&self) -> bool {
        let mut child = self.child.lock().expect("Sidecar 子进程锁不应中毒");
        matches!(child.try_wait(), Ok(None))
    }
}

impl Drop for SidecarHandle {
    fn drop(&mut self) {
        if let Ok(mut child) = self.child.lock() {
            // 先 kill 再 wait：kill 之后不等会留下僵尸进程。
            let _ = child.kill();
            let _ = child.wait();
        }
    }
}

/// Sidecar 的按需启动槽。
///
/// `Mutex<Option<...>>` 而不是常驻进程：用户可能整场不使用对话功能，
/// 那就没必要为了它一直占着一个 Python 解释器与一段内存里的密钥。
#[derive(Default)]
pub struct SidecarSlot {
    inner: Mutex<SlotInner>,
}

#[derive(Default)]
struct SlotInner {
    handle: Option<std::sync::Arc<SidecarHandle>>,
    spec: Option<LaunchSpec>,
}

impl SidecarSlot {
    /// 取得一个可用的 Sidecar；没有、已经退出、或配置变了就重新起一个。
    pub fn acquire(&self, spec: &LaunchSpec) -> Result<std::sync::Arc<SidecarHandle>, SidecarError> {
        let mut inner = self.inner.lock().expect("Sidecar 槽锁不应中毒");

        if let Some(handle) = inner.handle.take() {
            if handle.is_alive() && inner.spec.as_ref() == Some(spec) {
                inner.handle = Some(std::sync::Arc::clone(&handle));
                return Ok(handle);
            }
            // 配置变了或进程已经不在：丢掉旧句柄（Drop 会 kill），下面重新起。
            // 旧句柄若仍被某个在途请求持有，它的 Drop 会等到最后一个引用消失。
            inner.spec = None;
        }

        let handle = std::sync::Arc::new(launch(spec)?);
        inner.spec = Some(spec.clone());
        inner.handle = Some(std::sync::Arc::clone(&handle));
        Ok(handle)
    }

    /// 停止 Sidecar（下次 `acquire` 会重新拉起）。凭据变更后必须调用。
    pub fn stop(&self) {
        let mut inner = self.inner.lock().expect("Sidecar 槽锁不应中毒");
        inner.handle = None;
        inner.spec = None;
    }

    /// 当前是否有一个活着的实例。不做任何启动动作。
    pub fn running_port(&self) -> Option<u16> {
        let inner = self.inner.lock().expect("Sidecar 槽锁不应中毒");
        inner
            .handle
            .as_ref()
            .filter(|handle| handle.is_alive())
            .map(|handle| handle.port())
    }
}

/// 启动一个 Sidecar 进程并完成握手。
pub fn launch(spec: &LaunchSpec) -> Result<SidecarHandle, SidecarError> {
    let ai_core_dir = ai_core_dir()?;
    let program = python_executable(&ai_core_dir);
    if !program.is_file() {
        return Err(SidecarError::new(format!(
            "未找到 AI Core 的 Python 环境：{}\n\
             请先在仓库根目录执行 `uv sync --locked --project services/ai-core`。\n\
             （也可以用环境变量 {AI_CORE_DIR_ENV} 指向另一个 AI Core 目录。）",
            program.display()
        )));
    }

    let token = random_token()?;
    let handshake_line = serde_json::to_string(&handshake_payload(spec, &token))
        .map_err(|e| SidecarError::new(format!("启动配置无法序列化：{e}")))?;

    let mut command = Command::new(&program);
    command
        .arg("-m")
        .arg(SIDECAR_MODULE)
        .current_dir(&ai_core_dir)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        command.creation_flags(CREATE_NO_WINDOW);
    }

    let mut child = command
        .spawn()
        .map_err(|e| SidecarError::new(format!("无法启动 Sidecar 进程：{e}")))?;

    match handshake(&mut child, handshake_line) {
        Ok(handshake) => {
            forward_stderr(&mut child);
            Ok(SidecarHandle {
                port: handshake.port,
                token,
                contract_version: handshake.contract_version,
                child: Mutex::new(child),
                _stdin: handshake.stdin,
            })
        }
        Err(error) => {
            // 握手失败就把已经起来的进程收掉，不留一个状态不明的 Python 在后台。
            let _ = child.kill();
            let _ = child.wait();
            Err(error)
        }
    }
}

/// 握手成功后拿到的东西。`stdin` 会被移进 `SidecarHandle` 长期持有。
struct Handshake {
    port: u16,
    contract_version: String,
    stdin: ChildStdin,
}

#[derive(Deserialize)]
struct HandshakeLine {
    port: u16,
    version: Value,
}

fn handshake(child: &mut Child, config_line: String) -> Result<Handshake, SidecarError> {
    let mut stdin = child
        .stdin
        .take()
        .ok_or_else(|| SidecarError::new("Sidecar 的 stdin 不可用"))?;
    let stdout = child
        .stdout
        .take()
        .ok_or_else(|| SidecarError::new("Sidecar 的 stdout 不可用"))?;

    // 一次性下发启动配置。写失败通常意味着子进程已经退出（例如解释器都起不来）。
    stdin
        .write_all(config_line.as_bytes())
        .and_then(|()| stdin.write_all(b"\n"))
        .and_then(|()| stdin.flush())
        .map_err(|e| {
            SidecarError::new(format!(
                "无法向 Sidecar 下发启动配置（子进程可能已退出）：{e}"
            ))
        })?;

    let mut reader = BufReader::new(stdout);
    let mut line = String::new();
    reader
        .read_line(&mut line)
        .map_err(|e| SidecarError::new(format!("读取 Sidecar 握手信息失败：{e}")))?;
    if line.trim().is_empty() {
        return Err(SidecarError::new(
            "Sidecar 没有输出握手信息就退出了（请检查它的 stderr 输出）",
        ));
    }

    let parsed: HandshakeLine = serde_json::from_str(line.trim())
        .map_err(|e| SidecarError::new(format!("Sidecar 握手信息不是合法 JSON：{e}")))?;
    if parsed.port == 0 {
        return Err(SidecarError::new("Sidecar 上报的端口为 0，不可用"));
    }

    // SPEC-M00 §5.3 第 5 条：版本不一致就拒绝服务，不带着不匹配的假设继续跑。
    contracts::negotiate_contract_version(&parsed.version)?;

    // 握手之后不再需要 stdout 的内容，但必须继续把它排空：
    // 万一 Sidecar 往 stdout 写东西而没人读，管道写满会把子进程阻塞住。
    // 内容直接丢弃 —— 不落日志、不落盘。
    std::thread::spawn(move || {
        let mut reader = reader;
        let mut sink = [0u8; 1024];
        loop {
            match reader.read(&mut sink) {
                Ok(0) | Err(_) => break,
                Ok(_) => {}
            }
        }
    });

    Ok(Handshake {
        port: parsed.port,
        contract_version: parsed
            .version
            .get("contractVersion")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string(),
        stdin,
    })
}

/// 把 Sidecar 的 stderr 转到主进程的 stderr。
///
/// 这是开发期唯一的诊断通道。**前提是 Sidecar 的 stderr 里没有秘密与用户正文** ——
/// 那条不变量由 Python 侧的测试保证（`test_subprocess_entry_point_handshakes_and_serves_health`
/// 断言 token 与 API Key 不出现在 stderr 里）。若哪天 Sidecar 开始往 stderr 写请求内容，
/// 这里必须先改，而不是继续转发。
fn forward_stderr(child: &mut Child) {
    let Some(stderr) = child.stderr.take() else {
        return;
    };
    std::thread::spawn(move || {
        for line in BufReader::new(stderr).lines().map_while(Result::ok) {
            eprintln!("[sidecar] {line}");
        }
    });
}

/// 启动配置的线上形状。字段名与 Python 侧 `StartupConfig` 的别名一一对应
/// （Python 侧有 `test_startup_config_wire_names_are_camel_case` 钉住同一组名字）。
fn handshake_payload(spec: &LaunchSpec, token: &str) -> Value {
    json!({
        "token": token,
        "apiKey": spec.api_key,
        "baseUrl": spec.base_url,
        "model": spec.model,
    })
}

fn random_token() -> Result<String, SidecarError> {
    let mut bytes = [0u8; TOKEN_BYTES];
    getrandom::fill(&mut bytes)
        .map_err(|e| SidecarError::new(format!("无法获取随机数：{e}")))?;
    // 十六进制编码：交给子进程的是纯 ASCII，不涉及编码歧义。
    Ok(bytes.iter().map(|byte| format!("{byte:02x}")).collect())
}

/// AI Core 服务目录。
pub fn ai_core_dir() -> Result<PathBuf, SidecarError> {
    if let Some(dir) = std::env::var_os(AI_CORE_DIR_ENV) {
        let dir = PathBuf::from(dir);
        if dir.as_os_str().is_empty() {
            return Err(SidecarError::new(format!(
                "环境变量 {AI_CORE_DIR_ENV} 是空值"
            )));
        }
        return Ok(dir);
    }

    dev_ai_core_dir().ok_or_else(|| {
        SidecarError::new(format!(
            "发布构建没有内置 Sidecar 路径，且未设置环境变量 {AI_CORE_DIR_ENV}。\n\
             这正是 T001（把 Sidecar 打包进安装包）尚未完成所留下的缺口：\n\
             开发期可直接从源码树启动，分发给他人之前必须先完成打包。"
        ))
    })
}

/// 开发期的默认位置：从编译期记录的本 crate 路径推回仓库根。
///
/// `release` 构建下返回 `None`，且因为 `cfg` 在编译期生效，
/// 该路径**根本不会出现在发布二进制里**（否则会把开发机的目录结构带出去）。
#[cfg(debug_assertions)]
fn dev_ai_core_dir() -> Option<PathBuf> {
    let repo_root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()?
        .parent()?
        .parent()?;
    let dir = repo_root.join("services").join("ai-core");
    dir.is_dir().then_some(dir)
}

#[cfg(not(debug_assertions))]
fn dev_ai_core_dir() -> Option<PathBuf> {
    None
}

fn python_executable(ai_core_dir: &Path) -> PathBuf {
    if cfg!(windows) {
        ai_core_dir.join(".venv").join("Scripts").join("python.exe")
    } else {
        ai_core_dir.join(".venv").join("bin").join("python")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn launch_spec_debug_never_prints_the_api_key() {
        let spec = LaunchSpec::from_parts(
            Some("sk-live-SECRET-0123456789".to_string()),
            "https://api.deepseek.com".to_string(),
            "deepseek-flash".to_string(),
        );
        let rendered = format!("{spec:?}");
        assert!(!rendered.contains("sk-live-SECRET-0123456789"), "{rendered}");
        assert!(rendered.contains("已隐去"));
    }

    #[test]
    fn handshake_keys_match_the_python_side() {
        // 与 Python 侧 StartupConfig 的别名集合逐字对应
        // （那一侧有 test_startup_config_wire_names_are_camel_case）。
        // 两侧各一条，任何一侧改名都会让另一侧失败。
        let payload = handshake_payload(&LaunchSpec::from_parts(None, "u".into(), "m".into()), "tok");
        let object = payload.as_object().expect("握手负载是对象");
        let mut keys: Vec<&str> = object.keys().map(String::as_str).collect();
        keys.sort_unstable();
        assert_eq!(keys, ["apiKey", "baseUrl", "model", "token"]);
    }

    #[test]
    fn token_is_64_hex_characters_and_unique() {
        let first = random_token().expect("可以取随机数");
        let second = random_token().expect("可以取随机数");
        assert_eq!(first.len(), 64);
        assert!(first.chars().all(|c| c.is_ascii_hexdigit()));
        assert_ne!(first, second);
    }

    #[test]
    fn launch_spec_from_parts_keeps_the_cloud_configuration() {
        let spec = LaunchSpec::from_parts(
            Some("k".to_string()),
            "https://api.deepseek.com".to_string(),
            "deepseek-flash".to_string(),
        );
        assert_eq!(spec.base_url.as_deref(), Some("https://api.deepseek.com"));
        assert_eq!(spec.model.as_deref(), Some("deepseek-flash"));
        assert_eq!(spec.api_key.as_deref(), Some("k"));
    }

    #[test]
    fn ai_core_dir_honours_the_environment_override() {
        // 这条用例只在没有别人并发改环境变量时稳定；测试进程内由我们自己设置与恢复。
        let previous = std::env::var_os(AI_CORE_DIR_ENV);
        std::env::set_var(AI_CORE_DIR_ENV, "C:/custom/ai-core");
        let resolved = ai_core_dir().expect("环境变量覆盖应生效");
        match previous {
            Some(value) => std::env::set_var(AI_CORE_DIR_ENV, value),
            None => std::env::remove_var(AI_CORE_DIR_ENV),
        }
        assert_eq!(resolved, PathBuf::from("C:/custom/ai-core"));
    }

    #[test]
    fn dev_ai_core_dir_points_at_the_repository_service() {
        let dir = dev_ai_core_dir().expect("debug 构建应能定位到 development 目录");
        assert!(
            dir.join("pyproject.toml").is_file(),
            "开发期默认目录应包含 pyproject.toml：{}",
            dir.display()
        );
    }

    #[test]
    fn python_executable_matches_the_platform_layout() {
        let path = python_executable(Path::new("X:/ai-core"));
        let rendered = path.to_string_lossy().replace('\\', "/");
        if cfg!(windows) {
            assert_eq!(rendered, "X:/ai-core/.venv/Scripts/python.exe");
        } else {
            assert_eq!(rendered, "X:/ai-core/.venv/bin/python");
        }
    }

    #[test]
    fn a_slot_without_a_launch_reports_no_running_port() {
        let slot = SidecarSlot::default();
        assert_eq!(slot.running_port(), None);
        slot.stop();
        assert_eq!(slot.running_port(), None);
    }
}
