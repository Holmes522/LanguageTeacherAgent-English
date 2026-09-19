"""EngMentor 本地 Sidecar（SPEC-M00 §5.1 / B-1、B-2）。

Sidecar 是数据与 AI 运行时，**只由 Rust 主进程访问**：

    [Rust 主进程] --HTTP 127.0.0.1:<随机端口> + 内存 Bearer token--> [本进程]

两条边界约束是这套设计的全部意义，改动前请先读 `config.py` 与 `envelope.py`
的模块文档：

* **B-1**：只绑定 ``127.0.0.1``，端口由操作系统随机分配；生产路径禁止 ``0.0.0.0``。
* **B-2**：鉴权 token 每次启动随机生成，只存在于主进程与本进程的内存中 ——
  不落盘、不进日志、不进 WebView。
"""

from .config import BIND_HOST, CONTRACT_VERSION, StartupConfig
from .envelope import failure, safe_request_id, success
from .server import SidecarServer, serve

__all__ = [
    "BIND_HOST",
    "CONTRACT_VERSION",
    "SidecarServer",
    "StartupConfig",
    "failure",
    "safe_request_id",
    "serve",
    "success",
]
