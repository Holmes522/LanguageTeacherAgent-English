"""Sidecar 的 HTTP 集成测试：真实起服务、真实发请求。

两组证据：

1. **进程内**：直接构造 `SidecarServer`，用它分配到的真实端口发 HTTP 请求，
   覆盖鉴权、路由、信封、SSE 流式。这里能断言"绑定的地址确实是 127.0.0.1"。
2. **子进程**：真的用 ``python -m english_teacher.sidecar`` 起一次，走完整的
   stdin 握手 —— 覆盖入口、握手协议、以及 B-2 要求的"token 不出现在输出里"。
   顺带验证 stdin 关闭后进程会自己退出（孤儿进程防护）。

这些用例都不联网：需要上云的路径只走到"未配置凭据"或请求校验为止。
"""

from __future__ import annotations

import http.client
import json
import socket
import subprocess
import sys
import threading
import time
from collections.abc import Iterator
from typing import Any

import pytest
from engm_contracts.v1.envelope import Failure, Success

from english_teacher.sidecar.config import BIND_HOST, StartupConfig
from english_teacher.sidecar.server import (
    CHAT_STREAM_PATH,
    HEALTH_PATH,
    MAX_REQUEST_BODY_BYTES,
    SidecarServer,
)

TOKEN = "b" * 64
API_KEY = "sk-live-SECRET-abcdef0123456789"


def user_turn(text: str = "hi", request_id: str = "req-1") -> dict[str, Any]:
    """一条最常见的对话请求：只有一条用户消息。"""
    return {
        "ok": True,
        "requestId": request_id,
        "data": {"messages": [{"role": "user", "content": text}]},
        "citations": [],
    }


def config(**overrides: Any) -> StartupConfig:
    base: dict[str, Any] = {
        "token": TOKEN,
        "api_key": API_KEY,
        "base_url": "https://api.deepseek.com",
        "model": "deepseek-flash",
    }
    base.update(overrides)
    return StartupConfig(**base)


class Client:
    """很小的 HTTP 客户端：只做这些测试需要的事。"""

    def __init__(self, port: int, token: str | None = TOKEN) -> None:
        self._connection = http.client.HTTPConnection(BIND_HOST, port, timeout=10)
        self._token = token

    def request(
        self,
        method: str,
        path: str,
        body: dict[str, Any] | None = None,
        *,
        token: str | None = "__default__",
    ) -> tuple[int, Any]:
        headers: dict[str, str] = {}
        effective_token = self._token if token == "__default__" else token
        if effective_token is not None:
            headers["Authorization"] = f"Bearer {effective_token}"
        payload = None
        if body is not None:
            payload = json.dumps(body).encode("utf-8")
            headers["Content-Type"] = "application/json"
            headers["Content-Length"] = str(len(payload))

        self._connection.request(method, path, body=payload, headers=headers)
        response = self._connection.getresponse()
        raw = response.read()
        try:
            return response.status, json.loads(raw)
        except json.JSONDecodeError:
            return response.status, raw

    def stream(self, body: dict[str, Any]) -> list[dict[str, Any]]:
        payload = json.dumps(body).encode("utf-8")
        self._connection.request(
            "POST",
            CHAT_STREAM_PATH,
            body=payload,
            headers={
                "Authorization": f"Bearer {self._token}",
                "Content-Type": "application/json",
                "Content-Length": str(len(payload)),
            },
        )
        response = self._connection.getresponse()
        assert response.status == 200, f"流式端点应返回 200，实际 {response.status}"
        frames: list[dict[str, Any]] = []
        for raw_line in response:
            line = raw_line.decode("utf-8").strip()
            if line.startswith("data:"):
                frames.append(json.loads(line[len("data:") :].strip()))
        return frames


@pytest.fixture
def server() -> Iterator[SidecarServer]:
    instance = SidecarServer(config())
    thread = threading.Thread(target=instance.serve_forever, daemon=True)
    thread.start()
    try:
        yield instance
    finally:
        instance.shutdown()
        instance.server_close()


@pytest.fixture
def client(server: SidecarServer) -> Client:
    return Client(server.port)


def test_http_paths_match_the_rust_side() -> None:
    """把 HTTP 路径钉死。

    这是与 Rust 侧的接口：Rust 按这些常量发请求（见 `apps/desktop/src-tauri/src/sidecar.rs`），
    Python 按这些常量路由。两侧各一条断言，任何一侧改名都会让另一侧失败 ——
    否则表现是一个很难定位的 404。
    """
    assert HEALTH_PATH == "/v1/health"
    assert CHAT_STREAM_PATH == "/v1/chat/stream"


# ---------------------------------------------------------------------------
# B-1：绑定
# ---------------------------------------------------------------------------


def test_server_binds_loopback_on_an_os_assigned_port(server: SidecarServer) -> None:
    """B-1：地址是回环，端口由操作系统随机分配（不是固定端口，也不是 0）。"""
    assert server.host == BIND_HOST
    assert server.port != 0
    assert server.port > 1023


def test_two_servers_get_different_ports() -> None:
    """端口随机分配的实测证据：同一时刻两个实例拿到不同端口。"""
    first = SidecarServer(config())
    second = SidecarServer(config())
    try:
        assert first.port != second.port
    finally:
        first.server_close()
        second.server_close()


# ---------------------------------------------------------------------------
# B-2：鉴权
# ---------------------------------------------------------------------------


def test_requests_without_a_token_are_rejected(client: Client) -> None:
    status, body = client.request("GET", HEALTH_PATH, token=None)
    assert status == 401
    assert body["ok"] is False
    Failure.model_validate(body)


def test_requests_with_a_wrong_token_are_rejected(client: Client) -> None:
    status, body = client.request("GET", HEALTH_PATH, token="b" * 63 + "c")
    assert status == 401
    assert body["ok"] is False


def test_rejection_never_echoes_the_presented_token(client: Client) -> None:
    presented = "wrong-token-" + "z" * 40
    status, body = client.request("GET", HEALTH_PATH, token=presented)
    assert status == 401
    assert presented not in json.dumps(body)
    # 响应里也不该出现真实 token。
    assert TOKEN not in json.dumps(body)


def test_health_requires_auth_before_routing(client: Client) -> None:
    """未鉴权时连"路径存不存在"都不该泄漏 —— 先鉴权再路由。"""
    status, _ = client.request("GET", "/v1/definitely-not-here", token=None)
    assert status == 401


# ---------------------------------------------------------------------------
# 路由与信封
# ---------------------------------------------------------------------------


def test_health_returns_a_success_envelope_with_the_contract_version(client: Client) -> None:
    status, body = client.request("GET", HEALTH_PATH)
    assert status == 200
    Success.model_validate(body)
    assert body["data"]["contractVersion"] == "v1"
    assert body["data"]["modelConfigured"] is True
    assert body["citations"] == []
    assert body["data"]["capabilities"] == [], "在第一个教学模块交付前不得声称任何教学能力"


def test_health_reports_missing_credential_honestly() -> None:
    instance = SidecarServer(config(api_key=None))
    thread = threading.Thread(target=instance.serve_forever, daemon=True)
    thread.start()
    try:
        status, body = Client(instance.port).request("GET", HEALTH_PATH)
        assert status == 200
        assert body["data"]["modelConfigured"] is False
    finally:
        instance.shutdown()
        instance.server_close()


def test_unknown_paths_return_an_envelope_404(client: Client) -> None:
    status, body = client.request("GET", "/v1/nope")
    assert status == 404
    assert body["ok"] is False
    Failure.model_validate(body)


def test_post_to_health_is_rejected(client: Client) -> None:
    status, body = client.request("POST", HEALTH_PATH, body={})
    assert status == 404
    assert body["ok"] is False


def test_rejections_still_read_the_request_body_first(client: Client) -> None:
    """拒绝一个带请求体的请求时，必须先读完请求体再回响应。

    否则客户端在写请求体时就被我们关掉连接，收到的是"连接被重置"而不是这个 404 信封 ——
    对它来说这是两种不同的结论。用一个 64 KiB 的请求体来测：这个大小超过典型的
    套接字缓冲区，因此"先回响应再关连接"的写法在这里必然表现为客户端写入失败。
    （这条用例最初就是失败后才发现服务端有这个问题的。）
    """
    payload = {"messages": [{"role": "user", "content": "x" * 64 * 1024}]}
    status, body = client.request("POST", HEALTH_PATH, body=payload)
    assert status == 404
    assert body["ok"] is False
    Failure.model_validate(body)


def test_auth_rejection_also_reads_the_request_body_first(client: Client) -> None:
    payload = {"messages": [{"role": "user", "content": "x" * 64 * 1024}]}
    status, body = client.request("POST", CHAT_STREAM_PATH, body=payload, token=None)
    assert status == 401
    assert body["ok"] is False


def raw_request(port: int, head: str) -> tuple[str, str]:
    """发一个只有请求头、没有请求体的原始请求，返回 (状态行, 全部响应文本)。

    用裸 socket 而不是 http.client 是有意的：本用例要声明一个超大的 Content-Length
    却**不真的把那么多字节写出去**。用 http.client 的话，客户端会把整个 1 MiB 写完，
    而服务端早已拒绝并关闭，于是测试会随机地以"连接被重置"而不是 413 结束 ——
    那样测的就不是服务端行为，而是两个缓冲区的赛跑。
    """
    with socket.create_connection((BIND_HOST, port), timeout=10) as connection:
        connection.sendall(head.encode("utf-8"))
        connection.shutdown(socket.SHUT_WR)
        chunks: list[bytes] = []
        while True:
            chunk = connection.recv(4096)
            if not chunk:
                break
            chunks.append(chunk)
    text = b"".join(chunks).decode("utf-8", errors="replace")
    status_line = text.split("\r\n", 1)[0]
    return status_line, text


def test_oversized_bodies_are_rejected_not_truncated(client: Client) -> None:
    port = client._connection.port  # noqa: SLF001 - 测试需要复用同一个实例的端口
    status_line, text = raw_request(
        port,
        f"POST {CHAT_STREAM_PATH} HTTP/1.1\r\n"
        f"Host: {BIND_HOST}\r\n"
        f"Authorization: Bearer {TOKEN}\r\n"
        "Content-Type: application/json\r\n"
        f"Content-Length: {MAX_REQUEST_BODY_BYTES + 1}\r\n"
        "\r\n",
    )

    assert "413" in status_line, status_line
    body = json.loads(text.split("\r\n\r\n", 1)[1])
    assert body["ok"] is False
    assert "上限" in body["error"]["message"]


def test_a_rejected_request_leaves_the_server_serving(client: Client) -> None:
    """拒绝之后服务必须还活着 —— 一个坏请求不该让 Sidecar 退出。"""
    client.request("POST", CHAT_STREAM_PATH, body={"nonsense": True})
    status, body = client.request("GET", HEALTH_PATH)
    assert status == 200
    assert body["ok"] is True


def test_non_json_bodies_are_rejected_without_echoing_them(client: Client) -> None:
    connection = http.client.HTTPConnection(BIND_HOST, client._connection.port, timeout=10)  # noqa: SLF001
    secret_body = b'{"prompt": "sk-live-SHOULD-NOT-APPEAR"'
    connection.request(
        "POST",
        CHAT_STREAM_PATH,
        body=secret_body,
        headers={
            "Authorization": f"Bearer {TOKEN}",
            "Content-Type": "application/json",
            "Content-Length": str(len(secret_body)),
        },
    )
    response = connection.getresponse()
    body = response.read().decode("utf-8")
    assert response.status == 400
    assert "SHOULD-NOT-APPEAR" not in body
    connection.close()


# ---------------------------------------------------------------------------
# SSE 流式
# ---------------------------------------------------------------------------


def test_chat_stream_emits_a_failure_envelope_when_the_credential_is_missing() -> None:
    instance = SidecarServer(config(api_key=None))
    thread = threading.Thread(target=instance.serve_forever, daemon=True)
    thread.start()
    try:
        frames = Client(instance.port).stream(user_turn())
        assert len(frames) == 1
        assert frames[0]["ok"] is False
        assert frames[0]["requestId"] == "req-1"
    finally:
        instance.shutdown()
        instance.server_close()


def test_chat_stream_rejects_a_malformed_payload_as_a_streamed_envelope(client: Client) -> None:
    frames = client.stream({"ok": True, "requestId": "req-2", "data": {}, "citations": []})
    assert len(frames) == 1
    assert frames[0]["ok"] is False
    assert frames[0]["requestId"] == "req-2"


def test_chat_stream_uses_the_fallback_request_id_when_it_is_missing(client: Client) -> None:
    frames = client.stream({"ok": True, "data": {}})
    assert frames[0]["requestId"] == "unknown"


# ---------------------------------------------------------------------------
# 子进程端到端：入口、握手、B-2、孤儿进程防护
# ---------------------------------------------------------------------------


class SidecarProcess:
    def __init__(self) -> None:
        self.process = subprocess.Popen(
            [sys.executable, "-m", "english_teacher.sidecar"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
        )
        assert self.process.stdin is not None

    def handshake(self, payload: dict[str, Any]) -> dict[str, Any]:
        assert self.process.stdin is not None
        assert self.process.stdout is not None
        self.process.stdin.write(json.dumps(payload) + "\n")
        self.process.stdin.flush()
        line = self.process.stdout.readline()
        assert line.strip(), "Sidecar 没有输出握手行"
        handshake: dict[str, Any] = json.loads(line)
        return handshake

    def close(self) -> tuple[str, str]:
        """关掉 stdin（= 主进程退出），等进程自己结束，返回 (stdout, stderr)。"""
        assert self.process.stdin is not None
        assert self.process.stdout is not None
        assert self.process.stderr is not None
        self.process.stdin.close()
        stdout = self.process.stdout.read()
        stderr = self.process.stderr.read()
        self.process.wait(timeout=15)
        self.process.stdout.close()
        self.process.stderr.close()
        return stdout, stderr


def test_subprocess_entry_point_handshakes_and_serves_health() -> None:
    sidecar = SidecarProcess()
    try:
        handshake = sidecar.handshake({"token": TOKEN, "apiKey": API_KEY})
        assert handshake["port"] > 1023
        assert handshake["version"]["contractVersion"] == "v1"
        assert len(handshake["version"]["schemaIds"]) >= 1

        status, body = Client(handshake["port"]).request("GET", HEALTH_PATH)
        assert status == 200
        assert body["data"]["contractVersion"] == "v1"
    finally:
        stdout, stderr = sidecar.close()

    # B-2：token 与 API Key 都不能出现在进程的任何输出里。
    assert TOKEN not in stdout
    assert TOKEN not in stderr
    assert API_KEY not in stdout
    assert API_KEY not in stderr


def test_subprocess_exits_when_its_stdin_closes() -> None:
    """孤儿进程防护：主进程一退出（管道关闭），Sidecar 必须自己结束。"""
    sidecar = SidecarProcess()
    handshake = sidecar.handshake({"token": TOKEN})
    assert handshake["port"] > 1023

    # 关掉 stdin 后，进程应在几秒内自行退出；不 kill 它。
    assert sidecar.process.stdin is not None
    sidecar.process.stdin.close()
    deadline = time.monotonic() + 15
    while sidecar.process.poll() is None and time.monotonic() < deadline:
        time.sleep(0.1)

    assert sidecar.process.poll() is not None, "stdin 关闭后 Sidecar 仍在运行（会变成孤儿进程）"
    assert sidecar.process.returncode == 0
    assert sidecar.process.stdout is not None
    assert sidecar.process.stderr is not None
    sidecar.process.stdout.close()
    sidecar.process.stderr.close()


def test_subprocess_reports_a_config_failure_without_leaking_the_input() -> None:
    sidecar = SidecarProcess()
    assert sidecar.process.stdin is not None
    assert sidecar.process.stderr is not None
    # token 太短：应在启动阶段失败，不监听任何端口。
    sidecar.process.stdin.write(json.dumps({"token": "SHORT-TOKEN-VALUE"}) + "\n")
    sidecar.process.stdin.close()
    stderr = sidecar.process.stderr.read()
    sidecar.process.wait(timeout=15)
    assert sidecar.process.returncode == 2
    assert "SHORT-TOKEN-VALUE" not in stderr
    assert sidecar.process.stdout is not None
    assert sidecar.process.stdout.read() == "", "启动失败时不应输出握手行"
    sidecar.process.stdout.close()
    sidecar.process.stderr.close()
