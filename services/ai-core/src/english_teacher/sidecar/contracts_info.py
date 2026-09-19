"""本进程构建所依据的契约清单（SPEC-M00 §5.3 第 5、6 条）。

主进程在 Sidecar 启动时按 `version.schema.json` 收一次版本上报，不一致就拒绝服务。
上报的内容是**从生成物读出来的**，不是手抄的清单：

* 手抄的清单永远发现不了自己落后于契约包，而"某一侧落后"正是这条检查要暴露的问题；
* `schema-manifest.json` 由 `packages/contracts/scripts/generate.mjs` 生成，
  并且被复制进 `engm_contracts` 包内，因此这里读到的一定是"这个 venv 里实际装着的那一份"。
"""

from __future__ import annotations

import json
from importlib.resources import files
from typing import Any, Final

from engm_contracts.v1.version import ContractVersion

from .config import CONTRACT_VERSION

MANIFEST_RESOURCE: Final[str] = "schema-manifest.json"


class ContractManifestError(RuntimeError):
    """契约包内的 manifest 缺失或不可用。启动阶段失败，不进入服务状态。"""


def _load_manifest() -> dict[str, Any]:
    try:
        raw = (
            files("engm_contracts")
            .joinpath(MANIFEST_RESOURCE)
            .read_text(encoding="utf-8")
        )
    except (FileNotFoundError, ModuleNotFoundError) as exc:
        raise ContractManifestError(
            f"契约包内找不到 {MANIFEST_RESOURCE}；"
            "请先运行 `pnpm contracts:generate` 并重新 `uv sync`"
        ) from exc
    manifest: dict[str, Any] = json.loads(raw)
    return manifest


def schema_ids() -> tuple[str, ...]:
    """manifest 里所有带 ``$id`` 的 schema 标识。

    `error-codes.json` 是注册表而不是 schema，没有 ``$id``，因此它的 id 为 null ——
    这里按契约的 `schemaIds` 约束（每项必须是 ``https://engmentor.local/contracts/v1/...``）
    把它排除，而不是塞一个空值进去。
    """
    manifest = _load_manifest()
    entries = manifest.get("entries")
    if not isinstance(entries, list) or not entries:
        raise ContractManifestError("schema-manifest.json 的 entries 为空")
    ids = [
        entry["id"]
        for entry in entries
        if isinstance(entry, dict) and isinstance(entry.get("id"), str)
    ]
    if not ids:
        raise ContractManifestError("schema-manifest.json 里没有任何 schema $id")
    return tuple(ids)


def version_report() -> ContractVersion:
    """构造要通过主线程序列化发给主进程的版本上报。

    先断言"装着的契约包"与"本进程实现的契约版本"一致：如果在同一个 venv 里
    Python 契约包与 Sidecar 是不同的大版本，那是环境问题，应该在启动时就说清楚，
    而不是让主进程把它读成一次普通的版本不匹配。
    """
    manifest = _load_manifest()
    declared = manifest.get("contractVersion")
    if declared != CONTRACT_VERSION:
        raise ContractManifestError(
            f"契约包版本为 {declared!r}，而本进程实现的是 {CONTRACT_VERSION!r}；"
            "请重新 `uv sync --locked`"
        )
    return ContractVersion(contractVersion=CONTRACT_VERSION, schemaIds=list(schema_ids()))


def version_report_payload() -> dict[str, Any]:
    """可 JSON 序列化的版本上报。"""
    return version_report().model_dump(mode="json")
