"""M03 最小版本：一次真实的流式回答。

范围刻意压到最小：把用户输入发给 DeepSeek，把增量原样转成信封推回去。
**没有**检索、没有引用、没有 Token 预算、没有结构化输出 —— 那些需要 M03/M06
的 Spec，现在做等于在没有规范的情况下先定形状。

.. warning::

   下面 `ChatRequest` / `ChatMessage`（以及推给前端的 ``{"type": "delta"|"done"}``
   载荷）是**临时的**：SPEC-M00 §5.2 明确 M00 不定义业务命令字段，而这些字段的
   归属是 M03 的 Spec。因此本文件与前端 `apps/desktop/src/lib/chat.ts` 目前各写了
   一份等价定义 —— 这是已知的临时重复，已登记在 PROJECT_STATUS.md，
   到期条件：M03 的 Spec 落地时把它们写进 `packages/contracts/schema/v1/`，
   由生成链路产出两侧类型，并纳入三方一致性用例。
"""

from __future__ import annotations

from collections.abc import Iterator, Mapping, Sequence
from typing import Any, Final, Literal

from engm_contracts.v1.envelope import Usage
from engm_contracts.v1.error_codes import ErrorCode
from pydantic import BaseModel, ConfigDict, Field, ValidationError

from .config import StartupConfig
from .deepseek import DEFAULT_TIMEOUT_SECONDS, Delta, Done, ProviderError, stream_completion
from .envelope import describe_validation_error, failure, safe_request_id, success

#: 当前固化的错误码里没有「配置缺失」或「上游故障」域，因此这两类先用
#: INVALID_INPUT（调用方不该发这个请求）与 INTERNAL_UNEXPECTED（我们没能完成）。
#: 更精确的 `ENGM.LLM.*` 域应在 M03 的 Spec 里定义后替换（已在 PROJECT_STATUS 登记）。
CODE_NOT_CONFIGURED: Final[ErrorCode] = "ENGM.CONTRACT.INVALID_INPUT"
CODE_PROVIDER_FAILED: Final[ErrorCode] = "ENGM.INTERNAL.UNEXPECTED"

MAX_MESSAGES: Final[int] = 50
MAX_MESSAGE_CHARS: Final[int] = 8000

ChatRole = Literal["system", "user", "assistant"]


class ChatMessage(BaseModel):
    model_config = ConfigDict(frozen=True, extra="forbid")

    role: ChatRole
    content: str = Field(min_length=1, max_length=MAX_MESSAGE_CHARS)


class ChatRequest(BaseModel):
    model_config = ConfigDict(frozen=True, extra="forbid")

    messages: list[ChatMessage] = Field(min_length=1, max_length=MAX_MESSAGES)


class DeltaEvent(BaseModel):
    """增量事件：`data` 载荷里的一段新文本。"""

    model_config = ConfigDict(frozen=True)

    type: Literal["delta"] = "delta"
    text: str


class DoneEvent(BaseModel):
    """结束事件。用量在信封的 `usage` 字段里，不重复放进 `data`。"""

    model_config = ConfigDict(frozen=True)

    type: Literal["done"] = "done"


def stream_chat(
    config: StartupConfig,
    request: Mapping[str, Any],
    *,
    timeout_seconds: float = DEFAULT_TIMEOUT_SECONDS,
) -> Iterator[dict[str, Any]]:
    """处理一次对话请求，逐个产出**信封**。

    每个产出的字典都可以直接写进 SSE 的 ``data:`` 行；前端与主进程都按
    同一个信封形状解析，不需要为流式另立一套协议。
    """
    request_id = safe_request_id(request.get("requestId"))

    if request.get("ok") is not True:
        yield failure(
            request_id, CODE_NOT_CONFIGURED, "Sidecar 只接受成功形态的请求信封"
        )
        return

    try:
        chat = ChatRequest.model_validate(request.get("data"))
    except ValidationError as exc:
        yield failure(
            request_id,
            CODE_NOT_CONFIGURED,
            f"对话请求不合契约：{describe_validation_error(exc)}",
        )
        return

    if config.api_key is None or config.base_url is None or config.model is None:
        # 主进程本该在调用前就拦住这种情况（它知道自己有没有凭据）。
        # 这里再挡一次，是为了让"单独手工起 Sidecar"也拿不到任何上云路径。
        yield failure(
            request_id,
            CODE_NOT_CONFIGURED,
            "本进程启动时未获得模型凭据，无法发起上云请求",
        )
        return

    messages: Sequence[dict[str, str]] = [
        {"role": message.role, "content": message.content} for message in chat.messages
    ]

    try:
        for chunk in stream_completion(
            api_key=config.api_key,
            base_url=config.base_url,
            model=config.model,
            messages=messages,
            timeout_seconds=timeout_seconds,
        ):
            if isinstance(chunk, Delta):
                yield success(request_id, DeltaEvent(text=chunk.text).model_dump(mode="json"))
            elif isinstance(chunk, Done):
                yield success(
                    request_id,
                    DoneEvent().model_dump(mode="json"),
                    usage=Usage(
                        inputTokens=chunk.input_tokens,
                        outputTokens=chunk.output_tokens,
                        # DeepSeek 的 OpenAI 兼容接口不上报缓存命中；报 false 是
                        # 如实的"未使用缓存"，不是"没查"。
                        cached=False,
                    ),
                )
                return
    except ProviderError as exc:
        yield failure(request_id, CODE_PROVIDER_FAILED, str(exc))
        return

    # 上游没给 usage 就结束了连接（例如对端在最后断开）。仍然发一个 done：
    # 否则前端会一直停在"生成中"，用户只能靠猜。
    yield success(request_id, DoneEvent().model_dump(mode="json"))
