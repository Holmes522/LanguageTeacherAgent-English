"""Sidecar 进程入口：``python -m english_teacher.sidecar``。

由 Rust 主进程以子进程方式拉起，**不由用户直接启动**。

协议（全部在 stdin/stdout 上，各一行 JSON）::

    主进程 → Sidecar（stdin 第一行）：
        {"token": "...", "apiKey": "...", "baseUrl": "...", "model": "..."}

    Sidecar → 主进程（stdout 第一行，且只有这一行）：
        {"port": 51234, "version": {"contractVersion": "v1", "schemaIds": [...]}}

之后主进程保持 stdin 打开作为"父进程还活着"的信号（见 `server.py` 的 watchdog），
所有业务通信都走 ``127.0.0.1:<port>`` 上的 HTTP。

退出码：0 正常结束；2 启动配置或契约清单有问题（此时没有监听任何端口）。
"""

from __future__ import annotations

import sys

from .config import StartupConfigError, read_startup_config_from_stdin
from .server import serve


def main() -> int:
    try:
        config = read_startup_config_from_stdin()
    except StartupConfigError as exc:
        # 异常文案已保证不含 token / API Key（见 config.py）。
        print(f"[sidecar] 启动失败：{exc}", file=sys.stderr)
        return 2
    return serve(config)


if __name__ == "__main__":
    raise SystemExit(main())
