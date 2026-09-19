"""Sidecar 的 HTTP 服务（SPEC-M00 §5.1 / B-1、B-2、B-8）。

协议刻意保持最小，好让主进程用标准库也能正确解析：

* 只监听 ``127.0.0.1``，端口由操作系统随机分配（B-1）；
* 每个请求都要带 ``Authorization: Bearer <token>``，token 只在内存里（B-2）；
* **非 200 响应**是一份 ``application/json`` 的统一信封；
* **200 响应**（只用于 ``/v1/chat/stream``）是 ``text/event-stream``，
  每帧一行 ``data: <信封>``，以连接关闭表示结束 —— 不用 chunked 编码，
  因为自定义解析方越简单越不容易出分歧。

访问日志**完全不输出**（B-8）：请求行里可能带查询串，而"谁在什么时候问了什么"
本来就不该落进日志文件。
"""

from __future__ import annotations

import hmac
import json
import os
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import IO, Any, Final
from urllib.parse import urlsplit

from engm_contracts.v1.error_codes import ErrorCode

from ..health import health
from .chat import stream_chat
from .config import BIND_HOST, CONTRACT_VERSION, StartupConfig
from .contracts_info import ContractManifestError, version_report_payload
from .envelope import failure, safe_request_id, success

HEALTH_PATH: Final[str] = "/v1/health"
CHAT_STREAM_PATH: Final[str] = "/v1/chat/stream"

#: 请求体上限。拒绝而不是截断 —— 截断后的 JSON 会变成一个更难理解的解析错误。
MAX_REQUEST_BODY_BYTES: Final[int] = 1024 * 1024

#: 连接空闲超时。没有它，一个声明了 Content-Length 却不发内容的客户端
#: 能把一个处理线程永久占住。
CONNECTION_TIMEOUT_SECONDS: Final[int] = 30

#: 主进程在这个头里带 requestId（只有无请求体的 GET 用得上）。
REQUEST_ID_HEADER: Final[str] = "X-Engm-Request-Id"

#: 当前固化的错误码里没有传输层/配置缺失域，因此这些情况统一用 INVALID_INPUT。
#: HTTP 状态码本身承载区分度；更细的错误码留给后续模块的 Spec。
CODE_TRANSPORT: Final[ErrorCode] = "ENGM.CONTRACT.INVALID_INPUT"
CODE_INTERNAL: Final[ErrorCode] = "ENGM.INTERNAL.UNEXPECTED"

#: `_read_json_body` 在"已经回过错误响应"时返回的哨兵。
#: 不能用 None —— JSON 的 `null` 是合法请求体。
_UNREADABLE: Final[object] = object()


class SidecarRuntime:
    """一个 Sidecar 进程生命周期内共享的运行期状态。"""

    def __init__(self, config: StartupConfig) -> None:
        self._config = config

    @property
    def config(self) -> StartupConfig:
        return self._config

    def authorize(self, header: str | None) -> bool:
        prefix = "Bearer "
        if header is None or not header.startswith(prefix):
            return False
        # 定长比较：普通字符串比较会在第一个不同字符处返回，理论上可被用来
        # 逐字节试探 token。本机场景下这近乎理论问题，但代价只是一次函数调用。
        return hmac.compare_digest(header[len(prefix) :], self._config.token)

    def health_payload(self) -> dict[str, Any]:
        """健康检查负载。

        `capabilities` 来自 `health()`，在第一个教学模块交付之前保持为空 ——
        这里不为了界面好看而声称任何教学能力。`contractVersion` 与
        `modelConfigured` 是工程事实，主进程用前者做请求期版本复核。
        """
        status = health()
        return {
            **status.model_dump(mode="json"),
            "contractVersion": CONTRACT_VERSION,
            "modelConfigured": self._config.api_key is not None,
        }


class _SidecarHttpServer(ThreadingHTTPServer):
    daemon_threads = True

    #: 端口由系统分配，不存在"上一次运行留下的端口"问题。
    #: 因此不开地址复用：让"端口真的被占用"这类问题尽早暴露，而不是被静默复用掩盖。
    allow_reuse_address = False

    runtime: SidecarRuntime


class _RequestHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "EngMentorSidecar"
    sys_version = ""

    #: 单条连接的空闲超时（见 CONNECTION_TIMEOUT_SECONDS）。
    timeout = CONNECTION_TIMEOUT_SECONDS

    def __init__(self, *args: Any, **kwargs: Any) -> None:
        # 请求体是否已经被读过。`_send_json` 靠它决定"还要不要排空残留的请求体"。
        self._body_consumed = False
        super().__init__(*args, **kwargs)

    # ------------------------------------------------------------------
    # 日志：全部关闭（B-8）
    # ------------------------------------------------------------------

    def log_message(self, format_str: str, *args: Any) -> None:
        """刻意留空。默认实现会把请求行写进 stderr。"""

    def log_error(self, format_str: str, *args: Any) -> None:
        """同上。默认实现会转调 `log_message`，显式覆盖以免日后被改回去。

        副作用是"连接被对端重置"这类噪声也不再打印 —— 那正是我们想要的：
        用户在主进程里关掉窗口是正常操作，不该在日志里留下堆栈。
        """

    # ------------------------------------------------------------------
    # 路由
    # ------------------------------------------------------------------

    def do_GET(self) -> None:  # noqa: N802 - 标准库约定的方法名
        if not self._authorize():
            return
        if urlsplit(self.path).path != HEALTH_PATH:
            self._send_json(404, self._transport_failure("未知路径"))
            return
        self._send_json(200, success(self._header_request_id(), self._runtime.health_payload()))

    def do_POST(self) -> None:  # noqa: N802 - 标准库约定的方法名
        if not self._authorize():
            return
        if urlsplit(self.path).path != CHAT_STREAM_PATH:
            self._send_json(404, self._transport_failure("未知路径"))
            return

        body = self._read_json_body()
        if body is _UNREADABLE:
            return

        request_id = safe_request_id(body.get("requestId") if isinstance(body, dict) else None)
        if not isinstance(body, dict):
            self._send_json(400, self._transport_failure("请求信封必须是 JSON 对象", request_id))
            return

        self._stream_chat(body, request_id)

    # ------------------------------------------------------------------
    # 鉴权
    # ------------------------------------------------------------------

    @property
    def _runtime(self) -> SidecarRuntime:
        server = self.server
        assert isinstance(server, _SidecarHttpServer)
        return server.runtime

    def _authorize(self) -> bool:
        if self._runtime.authorize(self.headers.get("Authorization")):
            return True
        # 401 也回信封，让主进程只走一条解析路径。
        # 响应里绝不回显收到的 Authorization 值。
        self._send_json(401, self._transport_failure("Sidecar 鉴权失败"))
        return False

    def _header_request_id(self) -> str | None:
        return self.headers.get(REQUEST_ID_HEADER)

    def _transport_failure(self, message: str, request_id: object = None) -> dict[str, Any]:
        return failure(safe_request_id(request_id), CODE_TRANSPORT, message)

    # ------------------------------------------------------------------
    # 请求体
    # ------------------------------------------------------------------

    def _read_json_body(self) -> Any:
        raw_length = self.headers.get("Content-Length")
        if raw_length is None:
            self._send_json(411, self._transport_failure("缺少 Content-Length"))
            return _UNREADABLE
        try:
            length = int(raw_length)
        except ValueError:
            self._send_json(400, self._transport_failure("Content-Length 不是整数"))
            return _UNREADABLE
        if length < 0 or length > MAX_REQUEST_BODY_BYTES:
            self._send_json(
                413,
                self._transport_failure(f"请求体超出上限（{MAX_REQUEST_BODY_BYTES} 字节）"),
            )
            return _UNREADABLE

        raw = self.rfile.read(length)
        self._body_consumed = True
        if len(raw) != length:
            self._send_json(400, self._transport_failure("请求体不完整"))
            return _UNREADABLE
        try:
            return json.loads(raw)
        except json.JSONDecodeError:
            # 只报位置，不回显内容：请求体里是用户正文。
            self._send_json(400, self._transport_failure("请求体不是合法 JSON"))
            return _UNREADABLE

    def _discard_request_body(self) -> None:
        """回响应之前把还没读的请求体读掉并丢弃。

        为什么需要：如果在客户端还在写请求体时就关闭连接，它收到的是"连接被重置"，
        而不是我们精心构造的那个 404/401 信封 —— 对它来说这是两种完全不同的结论
        （"服务端拒绝了这次请求" vs "服务端坏了"）。所以先读干净，再回响应。

        两种情况不排空，直接关连接反而是对的：
          * 请求体已读过（`_read_json_body` 读过之后 stream 已经到底了，
            再按 Content-Length 去读会一直等到超时）；
          * 声明的长度超出上限 —— 那种情况我们本来就在回 413，关连接就是正确行为，
            而且不该为了一个超大请求体把整个连接阻塞住。
        """
        if self._body_consumed:
            return
        raw_length = self.headers.get("Content-Length")
        if raw_length is None:
            return
        try:
            remaining = int(raw_length)
        except ValueError:
            return
        if remaining <= 0 or remaining > MAX_REQUEST_BODY_BYTES:
            return

        while remaining > 0:
            chunk = self.rfile.read(min(remaining, 64 * 1024))
            if not chunk:
                # 对端没把声明的量发完就断了。没什么可做的，交给后面的关闭流程。
                return
            remaining -= len(chunk)
        self._body_consumed = True

    # ------------------------------------------------------------------
    # 流式回答
    # ------------------------------------------------------------------

    def _stream_chat(self, request: dict[str, Any], request_id: str) -> None:
        self._begin_stream()
        try:
            for envelope in stream_chat(self._runtime.config, request):
                self._write_event(envelope)
        except (BrokenPipeError, ConnectionResetError):
            # 主进程断开了：用户取消或应用退出。正常路径，不记堆栈。
            pass
        except Exception as exc:  # noqa: BLE001 - 兜底，见下
            # 任何未预期的故障都要变成一条可读的失败事件，而不是让连接无疾而终
            # （那样前端只会停在"生成中"）。只打印异常**类型名**，不打印消息：
            # 异常消息里可能带着用户正文。
            print(
                f"[sidecar] 对话流处理中断（requestId={request_id}）：{type(exc).__name__}",
                file=sys.stderr,
            )
            self._write_event(
                failure(request_id, CODE_INTERNAL, "Sidecar 内部错误，本次回答已中断")
            )
        finally:
            self.close_connection = True

    # ------------------------------------------------------------------
    # 响应写出
    # ------------------------------------------------------------------

    def _send_json(self, status: int, payload: dict[str, Any]) -> None:
        # 先排空请求体再回响应，理由见 `_discard_request_body`。
        self._discard_request_body()
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(body)
        self.close_connection = True

    def _begin_stream(self) -> None:
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        # 不发 Content-Length，也不分块：消息边界就是连接关闭。
        self.send_header("Connection", "close")
        self.end_headers()
        self.close_connection = True

    def _write_event(self, payload: dict[str, Any]) -> None:
        # json.dumps 会把字符串里的换行转义掉，因此一帧必然只有一行。
        frame = f"data: {json.dumps(payload, ensure_ascii=False)}\n\n"
        self.wfile.write(frame.encode("utf-8"))
        self.wfile.flush()


class SidecarServer:
    """绑定 + 握手 + 服务的组合。"""

    def __init__(self, config: StartupConfig) -> None:
        runtime = SidecarRuntime(config)
        # B-1：地址写死回环；端口 0 = 让操作系统分配一个空闲端口。
        # 构造时即完成 bind + listen，因此 `port` 在握手之前就是真实可用的。
        self._server = _SidecarHttpServer((BIND_HOST, 0), _RequestHandler)
        self._server.runtime = runtime

    @property
    def host(self) -> str:
        return str(self._server.server_address[0])

    @property
    def port(self) -> int:
        return int(self._server.server_address[1])

    def serve_forever(self) -> None:
        self._server.serve_forever()

    def server_close(self) -> None:
        self._server.server_close()

    def shutdown(self) -> None:
        self._server.shutdown()


def _start_parent_watchdog(stream: IO[str]) -> None:
    """主进程一退出就结束本进程。

    这是不依赖 Windows 作业对象的孤儿进程防护：Rust 侧持有子进程 stdin 的写端，
    主进程无论是正常退出还是崩溃，管道都会关闭，这里的 ``readline`` 随即返回空串。
    没有它，主进程崩溃后就会留下一个占着端口、还持有 API Key 的 Python 进程。
    """

    def watch() -> None:
        while stream.readline():
            # 协议上主进程不会再往 stdin 写东西；真收到了也只是忽略。
            # 这里等的是 EOF。
            pass
        # 用 os._exit：此刻 HTTP 服务线程仍在 serve_forever 里，
        # 正常返回无法结束进程，而这个退出路径本来也不需要清理。
        os._exit(0)

    threading.Thread(target=watch, name="parent-watchdog", daemon=True).start()


def _announce_handshake(port: int, report: dict[str, Any]) -> None:
    """向主进程回报端口与契约版本（stdout 的第一行，也是唯一一行）。"""
    sys.stdout.write(json.dumps({"port": port, "version": report}, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def serve(config: StartupConfig) -> int:
    """启动服务并阻塞，直到进程结束。返回进程退出码。"""
    try:
        report = version_report_payload()
    except ContractManifestError as exc:
        print(f"[sidecar] 启动失败：{exc}", file=sys.stderr)
        return 2

    server = SidecarServer(config)
    _start_parent_watchdog(sys.stdin)
    _announce_handshake(server.port, report)

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        return 0
    finally:
        server.server_close()
    return 0
