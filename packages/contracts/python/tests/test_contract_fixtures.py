"""三方一致性测试（Python 侧，SPEC-M00 §5.3 第 7 条 / AC-4）。

判据用的是 **schema 本身**（jsonschema 的 Draft202012Validator），而不是生成的 Pydantic 模型：
TS 侧用 ajv、Rust 侧用 jsonschema crate，三者必须对同一份 schema 得出同样的结论。
若这里改用 Pydantic 模型判定，比较的就成了"生成器对 schema 的解释"，而不是"schema 的语义"，
偏差会被生成器的口径掩盖掉。

判定结果同时写入 tmp/contracts-verdicts/py.json，供 pnpm test:contracts 与另外两方逐条比对。
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import pytest
from jsonschema import Draft202012Validator

TESTS_DIR = Path(__file__).resolve().parent
CONTRACTS_ROOT = TESTS_DIR.parent.parent  # packages/contracts
SCHEMA_DIR = CONTRACTS_ROOT / "schema" / "v1"
FIXTURES_FILE = CONTRACTS_ROOT / "tests" / "fixtures" / "contract-cases.json"
REPO_ROOT = CONTRACTS_ROOT.parent.parent
VERDICT_FILE = REPO_ROOT / "tmp" / "contracts-verdicts" / "py.json"


def _load_cases() -> list[dict[str, Any]]:
    document = json.loads(FIXTURES_FILE.read_text(encoding="utf-8"))
    cases: list[dict[str, Any]] = document["cases"]
    return cases


CASES = _load_cases()


def _validator(schema_file: str) -> Draft202012Validator:
    document = json.loads((SCHEMA_DIR / schema_file).read_text(encoding="utf-8"))
    return Draft202012Validator(document)


_VERDICTS: dict[str, str] = {}


@pytest.mark.parametrize("case", CASES, ids=[case["name"] for case in CASES])
def test_fixture_verdict_matches_expectation(case: dict[str, Any]) -> None:
    """每个用例的判定必须与 fixtures 中声明的 expect 一致。"""
    validator = _validator(case["schema"])
    errors = list(validator.iter_errors(case["instance"]))
    verdict = "invalid" if errors else "valid"

    _VERDICTS[case["name"]] = verdict
    assert verdict == case["expect"], (
        f"{case['name']}（{case['why']}）: 期望 {case['expect']}，实际 {verdict}；"
        f"诊断={[e.message for e in errors][:3]}"
    )


def test_generated_pydantic_models_import_and_accept_a_valid_envelope() -> None:
    """生成物本身可用：至少能导入并对一个合法信封建模。

    这一条只证明"生成器产出了可用的模型"，不承担三方一致性判定——后者由上面按 schema 判定的用例负责。
    """
    from engm_contracts.v1.envelope import LocalResponse

    envelope = {
        "ok": True,
        "requestId": "req-smoke",
        "data": None,
        "citations": [],
    }
    model = LocalResponse.model_validate(envelope)
    assert model.root.ok is True  # type: ignore[union-attr]


def test_registry_and_schema_error_codes_agree() -> None:
    """注册表与 schema 的错误码集合必须一致（生成阶段已断言，这里在运行期再压一次）。"""
    from engm_contracts.v1.error_codes import ERROR_CODES

    registry_codes = sorted(ERROR_CODES)
    error_schema = json.loads((SCHEMA_DIR / "error.schema.json").read_text(encoding="utf-8"))
    assert registry_codes == sorted(error_schema["properties"]["code"]["enum"])


def test_write_verdicts_for_three_way_comparison() -> None:
    """把本次判定写到 tmp/，供 pnpm test:contracts 比对三方结果。

    先保证前面每个用例都跑过了：无论 pytest 的收集顺序如何，这里都基于模块级的 _VERDICTS。
    """
    missing = [case["name"] for case in CASES if case["name"] not in _VERDICTS]
    assert missing == [], f"以下用例没有产生判定，verdict 文件会不完整：{missing}"

    VERDICT_FILE.parent.mkdir(parents=True, exist_ok=True)
    VERDICT_FILE.write_text(
        json.dumps({"language": "python", "verdicts": _VERDICTS}, ensure_ascii=False, indent=2, sort_keys=True)
        + "\n",
        encoding="utf-8",
    )
