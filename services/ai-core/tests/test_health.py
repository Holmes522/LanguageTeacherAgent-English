"""健康检查与结构化输出链路的测试。"""

import pytest
from pydantic import ValidationError

from english_teacher import HealthStatus, health


def test_health_claims_no_capabilities_yet() -> None:
    """骨架阶段必须如实声称"没有任何能力"，而不是返回一个好看的清单。"""
    status = health()

    assert status.stage == "pre-alpha"
    assert status.capabilities == ()
    assert status.package == "engm-ai-core"


def test_health_status_is_frozen() -> None:
    """状态对象不可变：避免调用方就地改写共享状态。

    这里刻意使用普通的属性赋值，而不是 setattr：赋值形式才是调用方真正会写的代码，
    也正是这个测试要证明会被拒绝的写法。mypy 会在静态层面就拦下它（frozen 模型应有的
    行为），所以需要就地忽略该条诊断——忽略的是"静态检查已提前发现"，不是"运行期不会报错"。
    """
    status = health()

    with pytest.raises(ValidationError):
        status.version = "9.9.9"  # type: ignore[misc]


def test_health_status_rejects_unknown_fields() -> None:
    """契约是封闭的：多出的字段会被拒绝，而不是被静默忽略。

    这条保证了 Pydantic 校验链路（后续 M03 结构化输出所依赖的同一套机制）真的在工作。
    """
    with pytest.raises(ValidationError):
        HealthStatus.model_validate(
            {
                "package": "engm-ai-core",
                "version": "0.0.0",
                "stage": "pre-alpha",
                "capabilities": [],
                "unexpected": True,
            }
        )
