"""DeepSeek 的流式调用（M03 最小版本）。

只做一件事：把 OpenAI 兼容的 ``POST {base_url}/chat/completions``（``stream: true``）
的 SSE 响应转成一个个增量文本。**不做**重试、不做预算控制、不做结构化输出 ——
那些属于 M03 完整 Spec 的范围，现在做了也没有 Spec 可依据。

刻意只用标准库（`urllib.request`）：这是本仓库第一个真实的外呼，接口面很小，
而 `urllib` 默认就用系统 CA 校验证书。要引入 HTTP 客户端库应先在 Spec/ADR 里说明理由。

两条安全约束：

* **密钥不进日志**。`urllib` 不会打印请求头，本模块也不打印；错误信息在往外抛之前
  一律先过 `redact`，把密钥原文抹掉。
* **上游响应是不可信数据**。这里只取出文本增量，不执行、不解析成 HTML/路径/SQL。
"""

from __future__ import annotations

import json
import urllib.error
import urllib.request
from collections.abc import Iterator, Sequence
from dataclasses import dataclass
from typing import Any, Final

CHAT_COMPLETIONS_PATH: Final[str] = "/chat/completions"

#: 单次请求的总超时（连接与每次读取共用）。真实回答通常在数十秒内，
#: 给足余量，但不允许无限挂起。
DEFAULT_TIMEOUT_SECONDS: Final[float] = 60.0

#: 上游错误体最多取这么多字符再往外报。既避免把长 HTML 错误页塞给界面，
#: 也缩小"上游在错误体里回显了什么"的暴露面。
MAX_ERROR_BODY_CHARS: Final[int] = 300

#: 云端调用失败时替换密钥用的占位符。
REDACTED: Final[str] = "***已隐去***"


class ProviderError(RuntimeError):
    """上游模型服务返回了错误，或无法到达。

    `message` 已经脱敏（不含密钥）。`retryable` 描述的是"同样的请求稍后重试
    是否有意义"——限流与 5xx 是，401（凭据无效）与 400（请求本身有问题）不是。
    """

    def __init__(self, message: str, *, retryable: bool) -> None:
        super().__init__(message)
        self.retryable = retryable


@dataclass(frozen=True)
class Delta:
    """一段增量文本。"""

    text: str


@dataclass(frozen=True)
class Done:
    """上游明确结束（收到 ``[DONE]`` 或 usage 之后）。"""

    input_tokens: int
    output_tokens: int


Chunk = Delta | Done


def redact(text: str, *secrets: str | None) -> str:
    """把文本里出现的密钥替换掉。用于任何要往外抛的上游错误信息。"""
    redacted = text
    for secret in secrets:
        if secret:
            redacted = redacted.replace(secret, REDACTED)
    return redacted


def stream_completion(
    *,
    api_key: str,
    base_url: str,
    model: str,
    messages: Sequence[dict[str, str]],
    timeout_seconds: float = DEFAULT_TIMEOUT_SECONDS,
) -> Iterator[Chunk]:
    """向 DeepSeek 发起一次流式补全，逐个产出增量。

    迭代过程中抛出的 `ProviderError` 都由本函数抛出，且文案已脱敏。
    """
    url = f"{base_url.rstrip('/')}{CHAT_COMPLETIONS_PATH}"
    payload = {
        "model": model,
        "messages": list(messages),
        "stream": True,
        # 让上游在最后一帧带上 usage，否则我们只能报 0 —— 那是不实的数字。
        "stream_options": {"include_usage": True},
    }
    request = urllib.request.Request(
        url,
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
            "Accept": "text/event-stream",
        },
        method="POST",
    )

    try:
        # 注意：不要把 request 或它的 headers 交给任何日志/打印。
        with urllib.request.urlopen(request, timeout=timeout_seconds) as response:
            yield from _iter_sse(response, api_key)
    except urllib.error.HTTPError as exc:
        # 408/429 与 5xx 值得重试；4xx 里的其他码（尤其 401）重试没有意义。
        retryable = exc.code in (408, 429) or exc.code >= 500
        raise ProviderError(_describe_http_error(exc, api_key), retryable=retryable) from None
    except TimeoutError:
        # 读超时与连接超时都是它：3.10 起 socket.timeout 已并入内建 TimeoutError。
        raise ProviderError("模型服务响应超时（未在限定时间内返回）", retryable=True) from None
    except urllib.error.URLError as exc:
        raise ProviderError(
            f"无法连接到模型服务：{redact(str(exc.reason), api_key)}", retryable=True
        ) from None


def _describe_http_error(error: urllib.error.HTTPError, api_key: str) -> str:
    hint = {
        400: "请求本身被上游拒绝（模型 id 或请求格式可能不对）",
        401: "API Key 无效或已失效",
        402: "账户余额不足",
        403: "该 API Key 没有访问该模型的权限",
        404: "模型 id 或服务地址不存在",
        429: "触发上游限流，稍后再试",
    }.get(error.code, "")

    body = ""
    try:
        body = error.read(MAX_ERROR_BODY_CHARS).decode("utf-8", errors="replace").strip()
    except (OSError, ValueError):
        # 读错误体失败不应该掩盖原始的 HTTP 错误。
        body = ""

    parts = [f"模型服务返回 HTTP {error.code}"]
    if error.reason:
        parts.append(str(error.reason))
    if hint:
        parts.append(hint)
    if body:
        parts.append(redact(body, api_key))
    return "：".join(parts)


def _iter_sse(response: Any, api_key: str) -> Iterator[Chunk]:
    """解析 OpenAI 兼容的 SSE 流。

    SSE 允许出现注释行与 keep-alive，因此**不认识的帧被跳过而不是报错** ——
    上游加一个心跳不该让一次正常回答失败。
    """
    finished = False
    for raw_line in response:
        line = raw_line.decode("utf-8", errors="replace").strip()
        if not line or not line.startswith("data:"):
            continue
        data = line[len("data:") :].strip()
        if data == "[DONE]":
            return
        try:
            event = json.loads(data)
        except json.JSONDecodeError:
            continue
        if not isinstance(event, dict):
            continue

        for chunk in _chunks_of(event):
            if isinstance(chunk, Done):
                if finished:
                    continue
                finished = True
            yield chunk


def _chunks_of(event: dict[str, Any]) -> Iterator[Chunk]:
    choices = event.get("choices")
    if isinstance(choices, list) and choices:
        first = choices[0]
        if isinstance(first, dict):
            delta = first.get("delta")
            if isinstance(delta, dict):
                content = delta.get("content")
                if isinstance(content, str) and content:
                    yield Delta(text=content)

    usage = event.get("usage")
    if isinstance(usage, dict):
        prompt_tokens = usage.get("prompt_tokens")
        completion_tokens = usage.get("completion_tokens")
        if isinstance(prompt_tokens, int) and isinstance(completion_tokens, int):
            yield Done(input_tokens=prompt_tokens, output_tokens=completion_tokens)
