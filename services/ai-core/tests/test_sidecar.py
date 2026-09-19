"""Sidecar 的单元测试：信封、启动配置、对话编排、DeepSeek 解析。

这些用例都不联网，也不起真实服务（那部分在 test_sidecar_http.py 里）。
"""

from __future__ import annotations

import io
import json
import urllib.error
from collections.abc import Iterator
from typing import Any

import pytest
from engm_contracts.v1.envelope import Success
from engm_contracts.v1.error_codes import ERROR_CODE_RETRYABLE
from pydantic import ValidationError

from english_teacher.sidecar import chat, deepseek, envelope
from english_teacher.sidecar.config import (
    BIND_HOST,
    CONTRACT_VERSION,
    StartupConfig,
    StartupConfigError,
    read_startup_config,
)

TOKEN = "a" * 64
# 刻意**不写成密钥的形态**（不是 `sk-...`、也不带高熵尾巴）。
# 理由：`pnpm check:secrets` 用 gitleaks 扫全量历史，像真凭据的字符串会被
# generic-api-key 命中，让这道门禁失败。正确做法是别写出像凭据的测试数据，
# 而不是给扫描器开例外 —— `.gitleaks.toml` 至今零例外，要保住这一点。
API_KEY = "engm-test-sentinel-not-a-credential"


def config(**overrides: Any) -> StartupConfig:
    base: dict[str, Any] = {
        "token": TOKEN,
        "api_key": API_KEY,
        "base_url": "https://api.deepseek.com",
        "model": "deepseek-flash",
    }
    base.update(overrides)
    return StartupConfig(**base)


# ---------------------------------------------------------------------------
# 信封
# ---------------------------------------------------------------------------


def test_success_envelope_keeps_null_data_but_drops_absent_usage() -> None:
    """两个方向的序列化都得对。

    `data: null` 是合法的（schema 里 data 是布尔 true），必须保留；
    `usage` 缺失时**不能**序列化成 `"usage": null` —— schema 只接受它缺失或是一个
    合法的 Usage 对象。用 exclude_none=True 会把两者一起丢掉，那会让成功信封
    因为"没有 data"而变得不合契约。
    """
    payload = envelope.success("req-1", None)
    assert payload["data"] is None
    assert "usage" not in payload
    # 用生成物自己的模型反校验一次：能建出来就说明形状合法。
    Success.model_validate(payload)


def test_success_envelope_carries_usage_when_present() -> None:
    from engm_contracts.v1.envelope import Usage

    payload = envelope.success(
        "req-1", {"x": 1}, usage=Usage(inputTokens=3, outputTokens=4, cached=False)
    )
    assert payload["usage"] == {"inputTokens": 3, "outputTokens": 4, "cached": False}
    Success.model_validate(payload)


def test_success_envelope_always_carries_citations() -> None:
    assert envelope.success("req-1", {"x": 1})["citations"] == []


@pytest.mark.parametrize("bad", ["", "x" * 129, None, 42, {"a": 1}])
def test_request_id_is_normalized_when_unusable(bad: object) -> None:
    assert envelope.safe_request_id(bad) == envelope.REQUEST_ID_FALLBACK


def test_request_id_is_preserved_when_usable() -> None:
    assert envelope.safe_request_id("req-1") == "req-1"


def test_failure_envelope_takes_retryable_from_the_registry() -> None:
    payload = envelope.failure("req-1", "ENGM.INTERNAL.UNEXPECTED", "出错了")
    assert payload["error"]["retryable"] is ERROR_CODE_RETRYABLE["ENGM.INTERNAL.UNEXPECTED"]
    assert payload["ok"] is False
    assert "data" not in payload


def test_failure_envelope_never_has_an_empty_message() -> None:
    """Error.message 的 min_length 是 1；空文案会被自己的校验拒掉，反而丢掉原因。"""
    payload = envelope.failure("req-1", "ENGM.INTERNAL.UNEXPECTED", "")
    assert payload["error"]["message"] == envelope.EMPTY_MESSAGE_FALLBACK


# ---------------------------------------------------------------------------
# 启动配置
# ---------------------------------------------------------------------------


def test_startup_config_reads_the_camel_case_wire_format() -> None:
    """线上格式是 camelCase —— 这是与 Rust 侧的实际约定，不是风格偏好。

    字段名写错时 extra="forbid" 会拒绝，因此这条断言能真的挡住
    "Rust 写 apiKey、Python 读 api_key"这类静默错配。
    """
    line = json.dumps({"token": TOKEN, "apiKey": API_KEY, "baseUrl": "https://x", "model": "m"})
    parsed = read_startup_config(io.StringIO(line + "\n"))
    assert parsed.token == TOKEN
    assert parsed.api_key == API_KEY
    assert parsed.base_url == "https://x"
    assert parsed.model == "m"


def test_startup_config_wire_names_are_camel_case() -> None:
    """把线上字段名钉死。

    这是与 Rust 侧的接口：Rust 按这些名字写，Python 按这些名字读。
    两侧各有一条断言（Rust 侧见 `sidecar::handshake_keys_are_camel_case`），
    任何一侧改名都会让另一侧失败，而不是静默地取到 None。

    注意 `populate_by_name=True` 让 Python 内可以用 snake_case 构造，
    因此"名字对不对"不能靠构造失败来测 —— 必须直接断言别名本身。
    """
    aliases = {name: field.alias for name, field in StartupConfig.model_fields.items()}
    assert aliases == {
        "token": "token",
        "api_key": "apiKey",
        "base_url": "baseUrl",
        "model": "model",
    }


def test_startup_config_allows_missing_credential() -> None:
    """没配凭据不是启动错误：健康检查仍要可用，只有上云请求会被拒。"""
    parsed = read_startup_config(io.StringIO(json.dumps({"token": TOKEN}) + "\n"))
    assert parsed.api_key is None


def test_startup_config_rejects_short_tokens_and_unknown_fields() -> None:
    for payload in [
        {"token": "too-short"},
        {"token": TOKEN, "extra": 1},
        {"token": TOKEN, "apiKey": 12345},
    ]:
        with pytest.raises(StartupConfigError):
            read_startup_config(io.StringIO(json.dumps(payload) + "\n"))


def test_startup_config_rejects_missing_or_oversized_input() -> None:
    with pytest.raises(StartupConfigError):
        read_startup_config(io.StringIO(""))
    with pytest.raises(StartupConfigError):
        read_startup_config(io.StringIO("\n"))
    with pytest.raises(StartupConfigError):
        read_startup_config(io.StringIO("x" * (16 * 1024 + 10) + "\n"))


def test_startup_config_errors_never_echo_the_secret_values() -> None:
    """校验失败时不能把收到的值带出来 —— 那一行里有 token 与 API Key。

    pydantic 默认会把出错的输入值放进 `errors()`，所以这条是真的会踩到的。
    """
    short_token = "SHORT-TOKEN-VALUE"
    wrong_type_key = "sk-WRONG-TYPE-0123456789"
    cases = [
        json.dumps({"token": short_token}),
        json.dumps({"token": TOKEN, "apiKey": 12345, "note": wrong_type_key}),
    ]
    for line in cases:
        with pytest.raises(StartupConfigError) as excinfo:
            read_startup_config(io.StringIO(line + "\n"))
        rendered = str(excinfo.value)
        assert short_token not in rendered
        assert wrong_type_key not in rendered


def test_startup_config_repr_hides_the_token_and_api_key() -> None:
    rendered = repr(config())
    assert TOKEN not in rendered
    assert API_KEY not in rendered
    assert "已隐去" in rendered


def test_bind_host_is_loopback() -> None:
    """B-1：绑定地址是回环。这条断言存在的意义是让"改成 0.0.0.0"必须显式改测试。"""
    assert BIND_HOST == "127.0.0.1"


# ---------------------------------------------------------------------------
# 对话编排
# ---------------------------------------------------------------------------


def request_envelope(data: Any, request_id: str = "req-1") -> dict[str, Any]:
    return {"ok": True, "requestId": request_id, "data": data, "citations": []}


def user_turn(text: str = "hi", request_id: str = "req-1") -> dict[str, Any]:
    """一条最常见的对话请求：只有一条用户消息。"""
    return request_envelope({"messages": [{"role": "user", "content": text}]}, request_id)


def test_chat_rejects_a_non_success_envelope() -> None:
    events = list(chat.stream_chat(config(), {"ok": False, "requestId": "r", "error": {}}))
    assert len(events) == 1
    assert events[0]["ok"] is False
    assert events[0]["requestId"] == "r"


def test_chat_rejects_a_malformed_payload() -> None:
    for bad in [{}, {"messages": []}, {"messages": [{"role": "robot", "content": "x"}]}]:
        events = list(chat.stream_chat(config(), request_envelope(bad)))
        assert events[0]["ok"] is False, f"{bad} 应被拒绝"


def test_chat_refuses_to_call_the_cloud_without_a_configured_credential() -> None:
    """主进程本该先拦住；这里挡第二道，让手工起 Sidecar 也拿不到上云路径。"""
    events = list(chat.stream_chat(config(api_key=None), user_turn()))
    assert events[0]["ok"] is False
    assert "凭据" in events[0]["error"]["message"]


def test_chat_streams_deltas_then_done_with_usage(monkeypatch: pytest.MonkeyPatch) -> None:
    def fake_stream(**kwargs: Any) -> Iterator[deepseek.Chunk]:
        yield deepseek.Delta(text="Hello")
        yield deepseek.Delta(text=" world")
        yield deepseek.Done(input_tokens=7, output_tokens=2)

    monkeypatch.setattr(chat, "stream_completion", fake_stream)

    events = list(chat.stream_chat(config(), user_turn()))

    assert [e["data"]["type"] for e in events] == ["delta", "delta", "done"]
    text = "".join(e["data"]["text"] for e in events if e["data"]["type"] == "delta")
    assert text == "Hello world"
    assert events[-1]["usage"] == {"inputTokens": 7, "outputTokens": 2, "cached": False}
    # 每一帧都必须是合法信封，主进程才能用同一套校验器处理它们。
    for event in events:
        Success.model_validate(event)


def test_chat_still_sends_done_when_the_provider_omits_usage(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """上游没给 usage 就结束连接时也要发 done，否则界面永远停在"生成中"。"""

    def fake_stream(**kwargs: Any) -> Iterator[deepseek.Chunk]:
        yield deepseek.Delta(text="hi")

    monkeypatch.setattr(chat, "stream_completion", fake_stream)

    events = list(chat.stream_chat(config(), user_turn()))
    assert events[-1]["data"]["type"] == "done"
    assert "usage" not in events[-1], "没有真实用量时不应凭空报一个 0"


def test_chat_turns_provider_failures_into_a_failure_envelope(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    def fake_stream(**kwargs: Any) -> Iterator[deepseek.Chunk]:
        raise deepseek.ProviderError("模型服务返回 HTTP 401：API Key 无效或已失效", retryable=False)
        yield  # pragma: no cover - 让函数成为生成器

    monkeypatch.setattr(chat, "stream_completion", fake_stream)

    events = list(chat.stream_chat(config(), user_turn()))
    assert events[0]["ok"] is False
    assert "401" in events[0]["error"]["message"]
    # 密钥绝不能出现在任何一帧里。
    assert API_KEY not in json.dumps(events, ensure_ascii=False)


# ---------------------------------------------------------------------------
# DeepSeek 客户端
# ---------------------------------------------------------------------------


def test_redact_removes_every_secret_it_is_given() -> None:
    text = f"failed for {API_KEY} and {TOKEN}"
    redacted = deepseek.redact(text, API_KEY, TOKEN)
    assert API_KEY not in redacted
    assert TOKEN not in redacted
    assert redacted.count(deepseek.REDACTED) == 2


def test_redact_tolerates_missing_secrets() -> None:
    assert deepseek.redact("plain text", None) == "plain text"


class FakeResponse:
    """把若干行按 SSE 帧喂给 `_iter_sse`，模拟 urllib 的响应对象。"""

    def __init__(self, lines: list[bytes]) -> None:
        self._lines = lines

    def __iter__(self) -> Iterator[bytes]:
        return iter(self._lines)


def test_sse_parsing_extracts_deltas_and_usage() -> None:
    lines = [
        b": keep-alive\n",
        b"\n",
        b'data: {"choices":[{"delta":{"content":"Hel"}}]}\n',
        b'data: {"choices":[{"delta":{"content":"lo"}}]}\n',
        b'data: {"choices":[{"delta":{}}]}\n',
        b'data: {"choices":[],"usage":{"prompt_tokens":5,"completion_tokens":2}}\n',
        b"data: [DONE]\n",
    ]
    chunks = list(deepseek._iter_sse(FakeResponse(lines), API_KEY))  # noqa: SLF001 - 直接测解析核心

    assert [c for c in chunks if isinstance(c, deepseek.Delta)] == [
        deepseek.Delta(text="Hel"),
        deepseek.Delta(text="lo"),
    ]
    done = [c for c in chunks if isinstance(c, deepseek.Done)]
    assert done == [deepseek.Done(input_tokens=5, output_tokens=2)]


def test_sse_parsing_ignores_unknown_and_malformed_frames() -> None:
    """上游加一个心跳不该让一次正常回答失败。"""
    lines = [
        b"event: ping\n",
        b"data: not-json\n",
        b'data: {"choices":"nope"}\n',
        b'data: {"choices":[{"delta":{"content":"ok"}}]}\n',
        b"data: [DONE]\n",
    ]
    chunks = list(deepseek._iter_sse(FakeResponse(lines), API_KEY))  # noqa: SLF001
    assert chunks == [deepseek.Delta(text="ok")]


def test_http_error_descriptions_are_redacted_and_actionable() -> None:
    error = urllib.error.HTTPError(
        url="https://api.deepseek.com/chat/completions",
        code=401,
        msg="Unauthorized",
        hdrs=None,  # type: ignore[arg-type]
        fp=io.BytesIO(f'{{"error":"bad key {API_KEY}"}}'.encode()),
    )
    described = deepseek._describe_http_error(error, API_KEY)  # noqa: SLF001
    assert "401" in described
    assert "API Key 无效或已失效" in described
    assert API_KEY not in described
    assert deepseek.REDACTED in described


def test_http_error_description_survives_an_unreadable_body() -> None:
    error = urllib.error.HTTPError(
        url="https://api.deepseek.com/chat/completions",
        code=429,
        msg="Too Many Requests",
        hdrs=None,  # type: ignore[arg-type]
        fp=None,
    )
    described = deepseek._describe_http_error(error, API_KEY)  # noqa: SLF001
    assert "429" in described
    assert "限流" in described


def test_contract_version_is_the_one_this_package_was_built_for() -> None:
    assert CONTRACT_VERSION == "v1"


def test_validation_error_description_does_not_echo_input() -> None:
    """错误描述只给字段坐标，不回显值 —— 值里有可能是用户正文或密钥。"""
    with pytest.raises(ValidationError) as excinfo:
        chat.ChatRequest.model_validate({"messages": [{"role": API_KEY, "content": "x"}]})

    rendered = envelope.describe_validation_error(excinfo.value)
    assert API_KEY not in rendered
    assert "messages.0.role" in rendered
