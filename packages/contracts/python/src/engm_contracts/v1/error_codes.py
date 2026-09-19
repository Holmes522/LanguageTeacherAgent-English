# 本文件由 packages/contracts/scripts/generate.mjs 生成 —— 请勿手工编辑。
# 来源：packages/contracts/schema/v1/error-codes.json

"""已注册的契约错误码（ENGM.<DOMAIN>.<REASON>）。"""

from typing import Final, Literal

ErrorCode = Literal[
    "ENGM.CONTRACT.INVALID_INPUT",
    "ENGM.CONTRACT.SCHEMA_INVALID",
    "ENGM.CONTRACT.VERSION_MISMATCH",
    "ENGM.INTERNAL.UNEXPECTED",
]

# 错误码 → 是否可重试；由注册表生成，不要手写第二份。
ERROR_CODE_RETRYABLE: Final[dict[ErrorCode, bool]] = {
    "ENGM.CONTRACT.INVALID_INPUT": False,
    "ENGM.CONTRACT.SCHEMA_INVALID": False,
    "ENGM.CONTRACT.VERSION_MISMATCH": False,
    "ENGM.INTERNAL.UNEXPECTED": False,
}

ERROR_CODES: Final[tuple[ErrorCode, ...]] = (
    "ENGM.CONTRACT.INVALID_INPUT",
    "ENGM.CONTRACT.SCHEMA_INVALID",
    "ENGM.CONTRACT.VERSION_MISMATCH",
    "ENGM.INTERNAL.UNEXPECTED",
)
