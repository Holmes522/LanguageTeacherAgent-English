"""Sidecar 的启动配置：由主进程经 **stdin** 一次性下发。

为什么走 stdin，而不是命令行参数或环境变量：

* 命令行参数在进程列表里对同机其他进程可见（任务管理器就能看到）；
* 环境变量会被子进程继承，也更容易被顺手打日志；
* stdin 是一条只在父子之间存在的管道，读完即止，且**父进程一退出管道就关闭** ——
  这一点还被 `server.py` 用来做孤儿进程防护。

配置里可能带 API Key。因此本模块不容许把配置对象打印出来：
``__repr__`` 被显式覆盖为不含任何字段值的形式。
"""

from __future__ import annotations

import json
import sys
from typing import IO, Final

from pydantic import BaseModel, ConfigDict, Field, ValidationError
from pydantic.alias_generators import to_camel

from .envelope import describe_validation_error

#: B-1：只绑定回环地址。**不得**改成 0.0.0.0 或空字符串（那等于监听所有网卡）。
BIND_HOST: Final[str] = "127.0.0.1"

#: 本进程实现的契约大版本。与 packages/contracts/schema/v1 对应。
CONTRACT_VERSION: Final[str] = "v1"

#: token 长度下限。主进程生成 32 字节随机数的十六进制串（64 字符），
#: 这里卡 32 是为了不把"短到可暴力猜测的 token"放进来。
TOKEN_MIN_LENGTH: Final[int] = 32

MAX_TOKEN_LENGTH: Final[int] = 512
MAX_API_KEY_LENGTH: Final[int] = 512
MAX_BASE_URL_LENGTH: Final[int] = 200
MAX_MODEL_LENGTH: Final[int] = 100

#: 单行启动配置的大小上限。超长输入直接拒绝，不去解析。
MAX_CONFIG_LINE_BYTES: Final[int] = 16 * 1024


class StartupConfigError(RuntimeError):
    """启动配置缺失或不合法。启动阶段直接失败，不进入服务状态。"""


class StartupConfig(BaseModel):
    """主进程下发的一次性启动配置。

    线上格式是 **camelCase**（``apiKey`` / ``baseUrl``）—— 那是 Rust 侧写出来的形状，
    也是 JSON 侧的既成约定（信封与其余载荷全是 camelCase）。
    `populate_by_name=True` 让 Python 内也能用 snake_case 构造，测试读起来才不别扭。
    """

    model_config = ConfigDict(
        frozen=True,
        extra="forbid",
        alias_generator=to_camel,
        populate_by_name=True,
    )

    token: str = Field(min_length=TOKEN_MIN_LENGTH, max_length=MAX_TOKEN_LENGTH)
    #: 未配置凭据时为 None —— 这不是错误：健康检查仍然可用，
    #: 只有需要上云的请求会被拒绝。
    api_key: str | None = Field(default=None, max_length=MAX_API_KEY_LENGTH)
    base_url: str | None = Field(default=None, max_length=MAX_BASE_URL_LENGTH)
    model: str | None = Field(default=None, max_length=MAX_MODEL_LENGTH)

    def __repr__(self) -> str:
        """绝不把字段值放进 repr —— 里面有 token 与 API Key。"""
        return (
            "StartupConfig("
            f"token=<{len(self.token)} 字符，已隐去>, "
            f"api_key={'<已配置，已隐去>' if self.api_key else None}, "
            f"base_url={'<已配置>' if self.base_url else None}, "
            f"model={'<已配置>' if self.model else None})"
        )


def read_startup_config(stream: IO[str]) -> StartupConfig:
    """从 ``stream`` 读一行 JSON 并解析成配置。

    只读一行：主进程写完这一行就不再往 stdin 写东西，之后 stdin 被用作
    "父进程还活着吗"的信号（见 `server.py`）。
    """
    line = stream.readline(MAX_CONFIG_LINE_BYTES + 1)
    if line == "":
        raise StartupConfigError("stdin 已关闭，未收到启动配置")
    if len(line) > MAX_CONFIG_LINE_BYTES:
        raise StartupConfigError("启动配置超长，拒绝解析")
    if not line.strip():
        raise StartupConfigError("stdin 上收到的启动配置为空行")

    try:
        raw = json.loads(line)
    except json.JSONDecodeError as exc:
        # 只报位置，不回显内容 —— 这一行里可能有 API Key。
        raise StartupConfigError(f"启动配置不是合法 JSON（第 {exc.pos} 个字符处）") from exc

    try:
        return StartupConfig.model_validate(raw)
    except ValidationError as exc:
        raise StartupConfigError(
            f"启动配置不合契约：{describe_validation_error(exc)}"
        ) from exc


def read_startup_config_from_stdin() -> StartupConfig:
    return read_startup_config(sys.stdin)
