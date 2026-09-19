"""EngMentor AI Core（M00 骨架）。

本包目前只提供健康检查，用于证明包可导入、依赖可解析、类型检查与测试链路可用。

尚未实现、且必须等各自模块 Spec 获批后才加入的能力：查词、语法诊断、写作评分、
检索与引用、文档解析、题库。不要在本包中提前放置任何业务逻辑。
"""

from english_teacher.health import HealthStatus, health

__all__ = ["HealthStatus", "health"]
