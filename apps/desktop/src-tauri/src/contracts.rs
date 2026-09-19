//! 契约的运行时校验（SPEC-M00 §5.3）。
//!
//! TS 与 Python 侧由生成类型 + 校验库保证；Rust 侧不做类型生成，改为**按同一份 schema 运行时校验**，
//! 这样三条链路的口径来源一致。四条边界（WebView↔Rust、Rust↔Python）的入站与出站都经过这里。
//!
//! 三条硬性约束，都在代码里体现：
//!   1. schema 由 `include_str!` 在构建期嵌入，运行时不读仓库路径、不联网解析；
//!   2. 校验器首次使用时构建一次并缓存（`OnceLock`）；
//!   3. 校验失败返回 `ENGM.CONTRACT.SCHEMA_INVALID`，不 panic、不静默透传；错误详情只含
//!      schema $id、实例路径与失败关键字，**不含用户正文**。
//!
//! M00 阶段说明：`§5.2` 明确不定义业务命令字段，因此四条边界目前都只承载统一信封
//! （`LocalResponse`）。请求侧的具体 schema 随各业务模块（M03+）追加，届时在这里按边界分流。

use std::sync::OnceLock;

use serde_json::{json, Value};

/// 嵌入的契约来源。构建期读入，运行时不触碰文件系统。
pub const ENVELOPE_SCHEMA: &str =
    include_str!("../../../../packages/contracts/schema/v1/envelope.schema.json");
pub const ERROR_SCHEMA: &str =
    include_str!("../../../../packages/contracts/schema/v1/error.schema.json");
pub const CITATION_SCHEMA: &str =
    include_str!("../../../../packages/contracts/schema/v1/citation.schema.json");
pub const JOB_SCHEMA: &str =
    include_str!("../../../../packages/contracts/schema/v1/job.schema.json");
pub const VERSION_SCHEMA: &str =
    include_str!("../../../../packages/contracts/schema/v1/version.schema.json");
pub const ERROR_CODES_REGISTRY: &str =
    include_str!("../../../../packages/contracts/schema/v1/error-codes.json");

/// `(文件名, 内容)` 集合，供 AC-8 的嵌入完整性断言使用。
pub const EMBEDDED_CONTRACTS: &[(&str, &str)] = &[
    ("citation.schema.json", CITATION_SCHEMA),
    ("envelope.schema.json", ENVELOPE_SCHEMA),
    ("error-codes.json", ERROR_CODES_REGISTRY),
    ("error.schema.json", ERROR_SCHEMA),
    ("job.schema.json", JOB_SCHEMA),
    ("version.schema.json", VERSION_SCHEMA),
];

/// schema-manifest.json 也嵌入进来：断言的是"二进制里的东西与契约包一致"，
/// 而不是"磁盘上现在有什么"。
pub const SCHEMA_MANIFEST: &str =
    include_str!("../../../../packages/contracts/schema-manifest.json");

/// 本进程支持的契约版本。与 Sidecar 上报不一致时拒绝服务（§5.3 第 5 条）。
pub const CONTRACT_VERSION: &str = "v1";

/// 已注册的错误码。与 error-codes.json 一一对应，由
/// `registered_error_codes_match_the_registry` 断言，防止 Rust 侧与注册表漂移。
///
/// `#[allow(dead_code)]` 的理由：这里刻意列全 4 个码，而 M00 的运行时路径只用到 3 个
/// （`INVALID_INPUT` 要等到有业务入参校验的模块才用得上）。完整性是刻意的——
/// 让"允许出现的错误码"在 Rust 侧也有一个封闭集合，而不是让各模块自行拼字符串。
#[allow(dead_code)]
pub const CODE_INVALID_INPUT: &str = "ENGM.CONTRACT.INVALID_INPUT";
pub const CODE_SCHEMA_INVALID: &str = "ENGM.CONTRACT.SCHEMA_INVALID";
pub const CODE_VERSION_MISMATCH: &str = "ENGM.CONTRACT.VERSION_MISMATCH";
#[allow(dead_code)]
pub const CODE_INTERNAL_UNEXPECTED: &str = "ENGM.INTERNAL.UNEXPECTED";

/// 契约错误。`details` 只承载诊断坐标，不承载用户内容。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ContractError {
    pub code: &'static str,
    pub message: String,
    pub retryable: bool,
    pub details: Option<Value>,
}

impl ContractError {
    /// 负载未通过 schema 校验。
    fn schema_invalid(schema_id: &str, violations: Vec<Value>) -> Self {
        Self {
            code: CODE_SCHEMA_INVALID,
            message: format!("负载未通过 {schema_id} 校验"),
            retryable: false,
            details: Some(json!({ "schemaId": schema_id, "violations": violations })),
        }
    }

    /// 同 [`ContractError::schema_invalid`]，额外记录是哪条边界。
    fn schema_invalid_boundary(
        schema_id: &str,
        boundary: Boundary,
        violations: Vec<Value>,
    ) -> Self {
        Self {
            code: CODE_SCHEMA_INVALID,
            message: format!("负载未通过 {schema_id} 校验（边界 {}）", boundary.as_str()),
            retryable: false,
            details: Some(json!({
                "schemaId": schema_id,
                "boundary": boundary.as_str(),
                "violations": violations,
            })),
        }
    }

    /// 契约版本不一致：拒绝服务，而不是带着不匹配的假设继续跑。
    fn version_mismatch(remote: &str) -> Self {
        Self {
            code: CODE_VERSION_MISMATCH,
            message: format!("契约版本不一致：本进程 {CONTRACT_VERSION}，对端 {remote}"),
            retryable: false,
            details: Some(json!({ "expected": CONTRACT_VERSION, "actual": remote })),
        }
    }

    /// 契约自身有问题（schema 无法编译 / manifest 不可读）。属于内部错误，不是调用方的错。
    fn internal(message: impl Into<String>) -> Self {
        Self {
            code: CODE_INTERNAL_UNEXPECTED,
            message: message.into(),
            retryable: false,
            details: None,
        }
    }
}

/// 四条校验边界（SPEC-M00 §5.3 表格）。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Boundary {
    /// 入站：WebView 发来的 Tauri command 参数。
    WebviewToRust,
    /// 出站：返回给 WebView 的 `LocalResponse`。
    RustToWebview,
    /// 出站：发往 Python Sidecar 的请求体。
    RustToSidecar,
    /// 入站：Sidecar 返回、进入业务逻辑之前的响应。
    SidecarToRust,
}

impl Boundary {
    pub const ALL: [Boundary; 4] = [
        Boundary::WebviewToRust,
        Boundary::RustToWebview,
        Boundary::RustToSidecar,
        Boundary::SidecarToRust,
    ];

    pub fn as_str(self) -> &'static str {
        match self {
            Boundary::WebviewToRust => "webview->rust",
            Boundary::RustToWebview => "rust->webview",
            Boundary::RustToSidecar => "rust->sidecar",
            Boundary::SidecarToRust => "sidecar->rust",
        }
    }
}

// ---------------------------------------------------------------------------
// 校验器：首次使用构建一次并缓存
// ---------------------------------------------------------------------------

fn compile(source: &'static str) -> Result<jsonschema::Validator, ContractError> {
    let document: Value = serde_json::from_str(source)
        .map_err(|e| ContractError::internal(format!("嵌入的 schema 不是合法 JSON：{e}")))?;
    jsonschema::validator_for(&document)
        .map_err(|e| ContractError::internal(format!("嵌入的 schema 无法编译：{e}")))
}

fn envelope_validator() -> Result<&'static jsonschema::Validator, ContractError> {
    static VALIDATOR: OnceLock<Result<jsonschema::Validator, ContractError>> = OnceLock::new();
    match VALIDATOR.get_or_init(|| compile(ENVELOPE_SCHEMA)) {
        Ok(v) => Ok(v),
        Err(e) => Err(e.clone()),
    }
}

fn version_validator() -> Result<&'static jsonschema::Validator, ContractError> {
    static VALIDATOR: OnceLock<Result<jsonschema::Validator, ContractError>> = OnceLock::new();
    match VALIDATOR.get_or_init(|| compile(VERSION_SCHEMA)) {
        Ok(v) => Ok(v),
        Err(e) => Err(e.clone()),
    }
}

/// 把校验诊断压缩成"坐标"：schema $id、实例路径、失败关键字（schemaPath 的末段）。
/// 刻意不带上实例值本身——那会把用户正文写进错误里。
fn diagnostics(errors: jsonschema::ErrorIterator<'_>) -> Vec<Value> {
    errors
        .map(|error| {
            let schema_path = error.schema_path().to_string();
            let keyword = schema_path
                .rsplit('/')
                .next()
                .unwrap_or_default()
                .to_string();
            json!({
                "instancePath": error.instance_path().to_string(),
                "keyword": keyword,
                "schemaPath": schema_path,
            })
        })
        .collect()
}

/// 边界校验入口：任一边界的入站/出站负载都必须先过这里。
pub fn validate_boundary(boundary: Boundary, payload: &Value) -> Result<(), ContractError> {
    // M00 四条边界共用同一信封（§5.2 不定义业务命令字段）；boundary 记进诊断，
    // 让失败信息能直接指出是哪条边界出的问题，而不是一个无用的参数。
    let validator = envelope_validator()?;
    let violations = diagnostics(validator.iter_errors(payload));
    if violations.is_empty() {
        return Ok(());
    }
    Err(ContractError::schema_invalid_boundary(
        "envelope.schema.json",
        boundary,
        violations,
    ))
}

/// 契约版本协商：先按 `version.schema.json` 校验上报内容，再比对版本号。
///
/// 顺序是刻意的：一个连版本上报本身都不合契约的对端，不应该被当成"版本不匹配"来处理，
/// 它应当得到 SCHEMA_INVALID —— 那是更准确的诊断。
pub fn negotiate_contract_version(reported: &Value) -> Result<(), ContractError> {
    let validator = version_validator()?;
    let violations = diagnostics(validator.iter_errors(reported));
    if !violations.is_empty() {
        return Err(ContractError::schema_invalid(
            "version.schema.json",
            violations,
        ));
    }

    let remote = reported
        .get("contractVersion")
        .and_then(Value::as_str)
        .ok_or_else(|| ContractError::internal("version.schema.json 未约束到 contractVersion"))?;

    if remote != CONTRACT_VERSION {
        return Err(ContractError::version_mismatch(remote));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn valid_success() -> Value {
        json!({ "ok": true, "requestId": "req-1", "data": null, "citations": [] })
    }

    /// 四条边界的入站与出站都必须拒绝畸形负载，且错误码为 SCHEMA_INVALID、不 panic。
    #[test]
    fn all_four_boundaries_reject_malformed_payloads() {
        let malformed = json!({ "ok": true, "data": null, "citations": [] }); // 缺 requestId

        for boundary in Boundary::ALL {
            let result = validate_boundary(boundary, &malformed);
            let error = result.expect_err("畸形负载必须被拒绝");
            assert_eq!(
                error.code,
                CODE_SCHEMA_INVALID,
                "边界 {} 的错误码应为 SCHEMA_INVALID",
                boundary.as_str()
            );
            assert!(!error.retryable, "契约校验失败不应可重试");
        }
    }

    #[test]
    fn all_four_boundaries_accept_a_valid_envelope() {
        for boundary in Boundary::ALL {
            assert!(
                validate_boundary(boundary, &valid_success()).is_ok(),
                "边界 {} 应接受合法信封",
                boundary.as_str()
            );
        }
    }

    #[test]
    fn error_details_carry_coordinates_but_not_payload_content() {
        let secret = "SUPER-SECRET-USER-TEXT-0123456789";
        let malformed = json!({
            "ok": true,
            "requestId": secret,
            "data": null,
            "citations": [],
            "extra": secret
        });

        let error =
            validate_boundary(Boundary::RustToWebview, &malformed).expect_err("越界字段必须被拒绝");
        let rendered = serde_json::to_string(&error.details).expect("details 可序列化");

        assert!(
            !rendered.contains(secret),
            "错误详情不得包含用户正文，实际为：{rendered}"
        );
        assert_eq!(
            error.details.as_ref().unwrap()["schemaId"],
            "envelope.schema.json"
        );
    }

    #[test]
    fn malformed_payload_type_does_not_panic() {
        // 各种"不是信封"的输入都不能 panic，只能返回错误。
        for payload in [json!(null), json!([]), json!("text"), json!(42)] {
            let error = validate_boundary(Boundary::SidecarToRust, &payload)
                .expect_err("非对象负载必须被拒绝");
            assert_eq!(error.code, CODE_SCHEMA_INVALID);
        }
    }

    #[test]
    fn version_negotiation_accepts_the_current_version() {
        let reported = json!({
            "contractVersion": CONTRACT_VERSION,
            "schemaIds": ["https://engmentor.local/contracts/v1/envelope.schema.json"]
        });
        assert!(negotiate_contract_version(&reported).is_ok());
    }

    #[test]
    fn version_negotiation_reports_mismatch_and_refuses_to_serve() {
        let reported = json!({
            "contractVersion": "v2",
            "schemaIds": ["https://engmentor.local/contracts/v1/envelope.schema.json"]
        });
        let error = negotiate_contract_version(&reported).expect_err("版本不一致必须被拒绝");
        assert_eq!(error.code, CODE_VERSION_MISMATCH);
    }

    #[test]
    fn version_negotiation_rejects_a_non_conforming_report_as_schema_invalid() {
        // 连版本上报本身都不合契约时，SCHEMA_INVALID 比 VERSION_MISMATCH 更准确。
        let reported = json!({ "contractVersion": "1.0", "schemaIds": [] });
        let error = negotiate_contract_version(&reported).expect_err("不合契约的上报必须被拒绝");
        assert_eq!(error.code, CODE_SCHEMA_INVALID);
    }

    #[test]
    fn envelope_rejects_unknown_error_code_and_payload_mismatch() {
        let cases = [
            json!({
                "ok": false, "requestId": "r",
                "error": { "code": "ENGM.CONTRACT.NOT_REGISTERED", "message": "x", "retryable": false }
            }),
            json!({
                "ok": true, "requestId": "r",
                "error": { "code": "ENGM.CONTRACT.INVALID_INPUT", "message": "x", "retryable": false }
            }),
            json!({
                "ok": false, "requestId": "r", "data": null,
                "error": { "code": "ENGM.CONTRACT.INVALID_INPUT", "message": "x", "retryable": false }
            }),
        ];
        for case in cases {
            let error = validate_boundary(Boundary::WebviewToRust, &case).expect_err("必须被拒绝");
            assert_eq!(error.code, CODE_SCHEMA_INVALID);
        }
    }

    // -----------------------------------------------------------------------
    // 嵌入完整性（AC-8）与三方一致性（AC-4）
    // -----------------------------------------------------------------------

    /// 三方一致性用的用例集与判定结果路径。
    /// fixtures 同样以 include_str! 嵌入：断言的是"二进制里的 schema"，不是磁盘上的文件。
    const FIXTURE_CASES: &str =
        include_str!("../../../../packages/contracts/tests/fixtures/contract-cases.json");

    /// 每个 schema 只编译一次（SPEC-M00 §5.3 第 3 条）。这里覆盖 fixtures 用到的全部 5 个 schema。
    macro_rules! cached_validator {
        ($fn_name:ident, $source:expr) => {
            fn $fn_name() -> Result<&'static jsonschema::Validator, ContractError> {
                static VALIDATOR: OnceLock<Result<jsonschema::Validator, ContractError>> =
                    OnceLock::new();
                match VALIDATOR.get_or_init(|| compile($source)) {
                    Ok(v) => Ok(v),
                    Err(e) => Err(e.clone()),
                }
            }
        };
    }

    cached_validator!(error_validator, ERROR_SCHEMA);
    cached_validator!(citation_validator, CITATION_SCHEMA);
    cached_validator!(job_validator, JOB_SCHEMA);

    fn validator_for_file(file: &str) -> Result<&'static jsonschema::Validator, ContractError> {
        match file {
            "citation.schema.json" => citation_validator(),
            "envelope.schema.json" => envelope_validator(),
            "error.schema.json" => error_validator(),
            "job.schema.json" => job_validator(),
            "version.schema.json" => version_validator(),
            other => Err(ContractError::internal(format!("未嵌入的 schema：{other}"))),
        }
    }

    /// Rust 侧的错误码常量必须与 error-codes.json 注册表逐字一致。
    #[test]
    fn registered_error_codes_match_the_registry() {
        let registry: Value =
            serde_json::from_str(ERROR_CODES_REGISTRY).expect("error-codes.json 必须是合法 JSON");
        let mut registered: Vec<String> = registry["codes"]
            .as_object()
            .expect("codes 必须是对象")
            .keys()
            .cloned()
            .collect();
        registered.sort();

        let mut rust_side = vec![
            CODE_INVALID_INPUT.to_string(),
            CODE_SCHEMA_INVALID.to_string(),
            CODE_VERSION_MISMATCH.to_string(),
            CODE_INTERNAL_UNEXPECTED.to_string(),
        ];
        rust_side.sort();

        assert_eq!(rust_side, registered);
    }

    /// AC-8：`include_str!` 嵌入的集合必须与 schema-manifest.json 完全一致
    /// （文件名、字节长度、SHA-256），否则说明 Rust 侧落后于契约包。
    #[test]
    fn embedded_contract_set_matches_schema_manifest() {
        use sha2::{Digest, Sha256};

        let manifest: Value =
            serde_json::from_str(SCHEMA_MANIFEST).expect("schema-manifest.json 必须是合法 JSON");
        let entries = manifest["entries"]
            .as_array()
            .expect("manifest.entries 必须是数组");

        assert_eq!(
            entries.len(),
            EMBEDDED_CONTRACTS.len(),
            "嵌入的契约数量与 manifest 不一致（Rust 侧落后于契约包）"
        );

        for entry in entries {
            let file = entry["file"].as_str().expect("manifest 条目缺少 file");
            let embedded = EMBEDDED_CONTRACTS
                .iter()
                .find(|(name, _)| *name == file)
                .map(|(_, source)| *source)
                .unwrap_or_else(|| panic!("manifest 列出的 {file} 没有嵌入到 Rust 二进制里"));

            let expected_len = entry["bytes"].as_u64().expect("manifest 条目缺少 bytes") as usize;
            assert_eq!(
                embedded.len(),
                expected_len,
                "{file} 的字节长度与 manifest 不一致"
            );

            let expected_sha = entry["sha256"].as_str().expect("manifest 条目缺少 sha256");
            let actual_sha = format!("{:x}", Sha256::digest(embedded.as_bytes()));
            assert_eq!(
                actual_sha, expected_sha,
                "{file} 的 SHA-256 与 manifest 不一致"
            );
        }
    }

    /// AC-4：Rust 侧对同一批 fixtures 的判定必须与 fixtures 声明的期望一致，
    /// 并把判定写入 tmp/contracts-verdicts/rust.json 供三方比对。
    #[test]
    fn fixtures_verdicts_match_expectations_and_are_written_out() {
        let document: Value =
            serde_json::from_str(FIXTURE_CASES).expect("fixtures 必须是合法 JSON");
        let cases = document["cases"].as_array().expect("cases 必须是数组");
        assert!(cases.len() > 20, "用例数量异常，可能在生成 fixtures 时出错");

        let mut verdicts = serde_json::Map::new();
        for case in cases {
            let name = case["name"].as_str().expect("用例缺少 name").to_string();
            let schema_file = case["schema"].as_str().expect("用例缺少 schema");
            let expect = case["expect"].as_str().expect("用例缺少 expect");
            let instance = &case["instance"];

            let validator = validator_for_file(schema_file).expect("schema 应已嵌入");
            let verdict = if validator.is_valid(instance) {
                "valid"
            } else {
                "invalid"
            };

            assert_eq!(
                verdict, expect,
                "用例 {name} 的判定与期望不符（schema={schema_file}）"
            );
            verdicts.insert(name, Value::String(verdict.to_string()));
        }

        let out_dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("..")
            .join("..")
            .join("..")
            .join("tmp")
            .join("contracts-verdicts");
        std::fs::create_dir_all(&out_dir).expect("无法创建 verdict 输出目录");
        let payload = json!({ "language": "rust", "verdicts": Value::Object(verdicts) });
        std::fs::write(
            out_dir.join("rust.json"),
            format!(
                "{}\n",
                serde_json::to_string_pretty(&payload).expect("verdict 可序列化")
            ),
        )
        .expect("无法写入 rust verdict 文件");
    }
}
