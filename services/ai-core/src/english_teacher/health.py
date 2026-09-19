"""最小健康检查。

用途：让"包可导入、依赖可解析、Pydantic 校验链路可用、类型检查可运行"这四件事
在 CI 中被真正验证。它**不**代表产品能力——`capabilities` 为空元组就是刻意的。
"""

from typing import Literal

from pydantic import BaseModel, ConfigDict

Stage = Literal["pre-alpha"]


class HealthStatus(BaseModel):
    """AI Core 的自述状态。字段只描述工程骨架，不承诺任何产品能力。"""

    model_config = ConfigDict(frozen=True, extra="forbid")

    package: str
    version: str
    stage: Stage
    capabilities: tuple[str, ...]


def health() -> HealthStatus:
    """返回当前 AI Core 的真实状态。

    ``capabilities`` 保持为空：在第一个教学模块交付之前，声称任何能力都是不实陈述。
    """
    return HealthStatus(
        package="engm-ai-core",
        version="0.0.0",
        stage="pre-alpha",
        capabilities=(),
    )
