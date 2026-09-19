"""统一信封的构造（SPEC-M00 B-6：所有请求/响应使用统一信封）。

信封的**形状**不在这里定义 —— 它来自 `engm_contracts.v1.envelope`，也就是由
`packages/contracts/schema/v1/envelope.schema.json` 生成的那份 Pydantic 模型。
本模块只做两件生成物做不到的事：

1. **归一化 requestId**：契约要求它是 1..128 字符的字符串。对端给不出合法值时，
   用一个固定占位符，而不是猜、也不回显对方那个不合法的值。
2. **正确处理可选字段的序列化**：`usage` 在 schema 里是"可缺失"，而 Pydantic 的
   `None` 会序列化成 ``"usage": null``，那**不合契约**（schema 只接受缺失或合法对象）。
   见 `_dump`。
"""

from __future__ import annotations

from typing import Any

from engm_contracts.v1.envelope import Citation, Error, Failure, Success, Usage
from engm_contracts.v1.error_codes import ERROR_CODE_RETRYABLE, ErrorCode
from pydantic import ValidationError

#: 读不出对端 requestId 时使用的占位符。与 Rust 侧 `commands::accept` 的取值一致。
REQUEST_ID_FALLBACK = "unknown"

REQUEST_ID_MAX_LENGTH = 128
MESSAGE_MAX_LENGTH = 500

#: 文案为空时的兜底。Error.message 的 min_length 是 1，
#: 空文案会被自己的校验拒掉，反而丢掉真正的失败原因。
EMPTY_MESSAGE_FALLBACK = "未提供更多信息"


def safe_request_id(value: object) -> str:
    """把任意输入归一化成合法的 requestId。"""
    if isinstance(value, str) and 0 < len(value) <= REQUEST_ID_MAX_LENGTH:
        return value
    return REQUEST_ID_FALLBACK


def success(
    request_id: object,
    data: Any,
    *,
    citations: list[Citation] | None = None,
    usage: Usage | None = None,
) -> dict[str, Any]:
    """成功信封。``citations`` 缺省为空数组 —— 不能省略（见 envelope.schema.json）。"""
    envelope = Success(
        ok=True,
        requestId=safe_request_id(request_id),
        data=data,
        citations=list(citations) if citations else [],
        usage=usage,
    )
    return _dump(envelope, drop_usage=usage is None)


def failure(
    request_id: object,
    code: ErrorCode,
    message: str,
    *,
    details: Any = None,
) -> dict[str, Any]:
    """失败信封。

    ``retryable`` 取自错误码注册表，不由调用方指定 —— 同一个码在不同地方
    给出不同的可重试性，会让前端的重试逻辑变成猜谜。
    """
    error = Error(
        code=code,
        message=_clamp(message) or EMPTY_MESSAGE_FALLBACK,
        retryable=ERROR_CODE_RETRYABLE[code],
        details=details,
    )
    return Failure(
        ok=False, requestId=safe_request_id(request_id), error=error
    ).model_dump(mode="json")


def _clamp(message: str) -> str:
    return message[:MESSAGE_MAX_LENGTH]


def describe_validation_error(error: ValidationError) -> str:
    """把 Pydantic 校验错误压成"字段 + 原因"，**不回显收到的值**。

    `include_input=False` 是关键：Pydantic 默认会把出错的输入值挂进错误详情，
    而那些输入里有可能是 token、API Key 或用户正文。少了这个参数，一次普通的
    校验失败就会把秘密原文写进 stderr 或错误信封。
    """
    parts = []
    for item in error.errors(include_url=False, include_context=False, include_input=False):
        location = ".".join(str(part) for part in item["loc"]) or "<根>"
        parts.append(f"{location}: {item['msg']}")
    return "; ".join(parts)


def _dump(envelope: Success, *, drop_usage: bool) -> dict[str, Any]:
    # exclude={"usage"}：只在 usage 为 None 时丢掉这个键。
    # 不能用 exclude_none=True —— 那会连 data=None 一起丢掉，而 data 是必填项，
    # 丢掉之后信封反而变得不合契约（"成功但没带 data"）。
    return envelope.model_dump(
        mode="json", exclude={"usage"} if drop_usage else None
    )
