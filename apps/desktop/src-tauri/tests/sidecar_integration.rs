//! Rust ↔ Python Sidecar 的真实往返（集成测试）。
//!
//! 这组用例会**真的把 Sidecar 起起来**并走 HTTP，而不是打桩。它覆盖三件无法靠单测
//! 证明的事：
//!
//! 1. 握手协议两侧对得上（Rust 写的 camelCase 启动配置，Python 真的能读）；
//! 2. 契约版本协商在真实进程间成立；
//! 3. **B-1 的绑定地址**：从进程外看（`netstat`），这个端口确实只监听在 127.0.0.1，
//!    而不是 0.0.0.0。这一条只有从外部观察才能证明。
//!
//! 前置条件：已执行过 `uv sync --locked --project services/ai-core`。
//! CI 的 `rust` job 不准备 Python 环境（那是 `python` / `contracts` job 的事），
//! 因此这些用例默认 `#[ignore]`，按需运行：
//!
//! ```text
//! cargo test --manifest-path apps/desktop/src-tauri/Cargo.toml -- --ignored
//! ```

#![cfg(windows)]

use std::net::TcpStream;
use std::process::Command;
use std::time::Duration;

use engmentor_desktop::contracts::{validate_boundary, Boundary, CONTRACT_VERSION};
use engmentor_desktop::http::{LoopbackClient, Method};
use engmentor_desktop::sidecar::{launch, LaunchSpec, CHAT_STREAM_PATH, HEALTH_PATH};
use serde_json::{json, Value};

/// 只做形态占位，不是真实密钥：这些用例不联网（对话请求会因为"未配置凭据"被拒）。
const FAKE_KEY: &str = "sk-not-a-real-key-000000000000";

fn spec_without_credential() -> LaunchSpec {
    LaunchSpec::from_parts(
        None,
        "https://api.deepseek.com".to_string(),
        "deepseek-flash".to_string(),
    )
}

/// 从进程外确认某个端口的监听地址。
///
/// 返回 `Some(本地地址)` 表示处于 LISTENING；`None` 表示没有在监听。
fn listening_address(port: u16) -> Option<String> {
    let output = Command::new("netstat")
        .args(["-ano", "-p", "tcp"])
        .output()
        .expect("应能执行 netstat");
    let text = String::from_utf8_lossy(&output.stdout);
    for line in text.lines() {
        if !line.contains("LISTENING") {
            continue;
        }
        let mut fields = line.split_whitespace();
        let _proto = fields.next();
        let Some(local) = fields.next() else { continue };
        if local.ends_with(&format!(":{port}")) {
            return Some(local.to_string());
        }
    }
    None
}

fn user_turn(request_id: &str) -> Value {
    json!({
        "ok": true,
        "requestId": request_id,
        "data": { "messages": [{ "role": "user", "content": "你好" }] },
        "citations": [],
    })
}

#[test]
#[ignore = "需要 services/ai-core/.venv（uv sync）；CI 的 rust job 不准备 Python 环境"]
fn sidecar_launches_handshakes_and_answers_health() {
    let handle = launch(&spec_without_credential())
        .expect("Sidecar 应能启动（若失败，先运行 uv sync --locked --project services/ai-core）");

    assert!(handle.port() > 1023, "端口应由操作系统分配：{}", handle.port());
    assert_eq!(handle.contract_version(), CONTRACT_VERSION);
    assert!(handle.is_alive(), "握手成功后进程应当还活着");

    let mut response = handle
        .client()
        .send(Method::Get, HEALTH_PATH, None)
        .expect("健康检查请求应能发出");
    assert_eq!(response.status, 200);

    let body = response.read_json().expect("健康检查应返回 JSON");
    // 入站边界：Sidecar → Rust 的负载同样要过契约校验。
    validate_boundary(Boundary::SidecarToRust, &body).expect("健康检查负载应合契约");
    assert_eq!(body["data"]["contractVersion"], CONTRACT_VERSION);
    assert_eq!(
        body["data"]["modelConfigured"], false,
        "这次启动没有给凭据，健康检查必须如实上报"
    );
}

/// B-1：从进程外看，这个端口只监听在回环地址上。
#[test]
#[ignore = "需要 services/ai-core/.venv（uv sync）；CI 的 rust job 不准备 Python 环境"]
fn sidecar_listens_on_loopback_only() {
    let handle = launch(&spec_without_credential()).expect("Sidecar 应能启动");
    let port = handle.port();

    let address = listening_address(port)
        .unwrap_or_else(|| panic!("netstat 里找不到端口 {port} 的 LISTENING 记录"));

    assert!(
        address.starts_with("127.0.0.1:"),
        "Sidecar 必须只监听回环地址，实际为 {address}"
    );
    assert!(
        !address.starts_with("0.0.0.0:"),
        "Sidecar 不得监听所有网卡，实际为 {address}"
    );
}

#[test]
#[ignore = "需要 services/ai-core/.venv（uv sync）；CI 的 rust job 不准备 Python 环境"]
fn sidecar_rejects_a_wrong_token_with_a_valid_envelope() {
    let handle = launch(&spec_without_credential()).expect("Sidecar 应能启动");
    let impostor = LoopbackClient::new(handle.port(), "b".repeat(64));

    let mut response = impostor
        .send(Method::Get, HEALTH_PATH, None)
        .expect("请求应能发出");
    assert_eq!(response.status, 401, "token 不对必须被拒");

    let body = response.read_json().expect("401 也应当是 JSON 信封");
    validate_boundary(Boundary::SidecarToRust, &body).expect("401 的正文也必须合契约");
    assert_eq!(body["ok"], false);
    // B-2：响应里不能出现任何 token 形态的东西。
    let rendered = serde_json::to_string(&body).expect("可序列化");
    assert!(!rendered.contains(&"b".repeat(64)));
}

#[test]
#[ignore = "需要 services/ai-core/.venv（uv sync）；CI 的 rust job 不准备 Python 环境"]
fn sidecar_streams_a_failure_envelope_when_no_credential_was_provided() {
    let handle = launch(&spec_without_credential()).expect("Sidecar 应能启动");

    let mut response = handle
        .client()
        .send(Method::Post, CHAT_STREAM_PATH, Some(&user_turn("req-e2e-1")))
        .expect("对话请求应能发出");
    assert_eq!(response.status, 200, "流式端点以 200 + SSE 回应");

    let mut frames = Vec::new();
    while let Some(line) = response.next_line().expect("读取帧不应失败") {
        let Some(payload) = line.strip_prefix("data:") else {
            continue;
        };
        frames.push(serde_json::from_str::<Value>(payload.trim()).expect("每帧都应是 JSON"));
    }

    assert!(!frames.is_empty(), "至少应有一帧");
    for frame in &frames {
        validate_boundary(Boundary::SidecarToRust, frame).expect("每一帧都必须合契约");
    }
    assert_eq!(frames[0]["ok"], false, "没有凭据时必须失败");
    assert_eq!(frames[0]["requestId"], "req-e2e-1");
}

/// 有凭据但地址不可达时，失败必须是**一帧信封**，而不是把连接挂死。
///
/// 这条用例的价值在于它验证了错误路径的形状（用户可以据以判断"是网络问题"），
/// 而且用了一个必然连不上的回环端口，不会真的访问外网。
#[test]
#[ignore = "需要 services/ai-core/.venv（uv sync）；CI 的 rust job 不准备 Python 环境"]
fn sidecar_reports_an_unreachable_provider_as_a_failure_envelope() {
    // RFC 5737 的 TEST-NET 地址在这里用不上（那会真的尝试外连），
    // 改用回环上的一个几乎不可能被占用的端口：连接必然被拒。
    let spec = LaunchSpec::from_parts(
        Some(FAKE_KEY.to_string()),
        "https://127.0.0.1:1".to_string(),
        "deepseek-flash".to_string(),
    );
    let handle = launch(&spec).expect("Sidecar 应能启动");

    let mut response = handle
        .client()
        .send(Method::Post, CHAT_STREAM_PATH, Some(&user_turn("req-e2e-2")))
        .expect("对话请求应能发出");

    let mut frames = Vec::new();
    while let Some(line) = response.next_line().expect("读取帧不应失败") {
        if let Some(payload) = line.strip_prefix("data:") {
            frames.push(serde_json::from_str::<Value>(payload.trim()).expect("每帧都应是 JSON"));
        }
    }

    assert!(!frames.is_empty(), "上游不可达时也必须给出帧");
    validate_boundary(Boundary::SidecarToRust, &frames[0]).expect("失败帧必须合契约");
    assert_eq!(frames[0]["ok"], false);
    let message = frames[0]["error"]["message"].as_str().unwrap_or_default();
    assert!(message.contains("无法连接") || message.contains("超时"), "实际文案：{message}");
    // §9.2：失败信息里不能带出密钥。
    assert!(!message.contains(FAKE_KEY));
}

#[test]
#[ignore = "需要 services/ai-core/.venv（uv sync）；CI 的 rust job 不准备 Python 环境"]
fn dropping_the_handle_stops_the_sidecar() {
    let handle = launch(&spec_without_credential()).expect("Sidecar 应能启动");
    let port = handle.port();
    assert!(listening_address(port).is_some());

    drop(handle);

    // 进程退出后端口不再监听；给一小段时间让 OS 收尾。
    let deadline = std::time::Instant::now() + Duration::from_secs(10);
    let mut still_listening = listening_address(port).is_some();
    while still_listening && std::time::Instant::now() < deadline {
        std::thread::sleep(Duration::from_millis(100));
        still_listening = listening_address(port).is_some();
    }
    assert!(!still_listening, "句柄释放后 Sidecar 不应继续监听端口 {port}");

    // 连接也必须失败（没有进程在 accept）。
    assert!(
        TcpStream::connect(("127.0.0.1", port)).is_err(),
        "端口 {port} 仍可连接，说明进程没退干净"
    );
}
