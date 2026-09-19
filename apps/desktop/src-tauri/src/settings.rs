//! 非敏感设置的持久化（T012 最小版本）。
//!
//! 这里**只**放可以公开的配置：上云同意开关、模型 id、服务地址。
//! API Key 不在这里 —— 它唯一的合法位置是 OS 凭据存储（见 [`crate::secrets`]），
//! 本模块的测试会断言序列化结果里没有密钥字段。
//!
//! 文件位置按 SPEC-M00 §9.3 固定为 Windows 的 `%APPDATA%\EngMentor\settings.json`，
//! 在仓库之外，因此不会被误提交；`.gitignore` 另有兜底规则。
//!
//! 写入是「临时文件 + 重命名」：中途崩溃不会留下一个被截断的配置，
//! 否则下一次启动会因为 JSON 解析失败而丢掉用户设置。

use std::fs;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

/// 应用数据目录名（SPEC-M00 §9.3）。
pub const APP_DATA_DIR_NAME: &str = "EngMentor";
pub const SETTINGS_FILE_NAME: &str = "settings.json";

/// DeepSeek 官方服务地址。用户可改（例如走自建代理），但必须仍是 https。
pub const DEFAULT_BASE_URL: &str = "https://api.deepseek.com";
/// 公开调用名（统一方案 §项目技术栈：DeepSeek `deepseek-flash`）。
pub const DEFAULT_MODEL: &str = "deepseek-flash";

/// 模型 id 与 base URL 的长度上限。都是给不可信输入（WebView）用的边界，
/// 不是产品约束。
const MODEL_MAX_LEN: usize = 100;
const BASE_URL_MAX_LEN: usize = 200;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Settings {
    /// Q5：用户明确同意后才把最小内容上云；可随时关闭。
    pub cloud_consent_granted: bool,
    pub model: String,
    pub base_url: String,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            // 默认关闭：同意必须是用户主动做出的动作，不能是默认值。
            cloud_consent_granted: false,
            model: DEFAULT_MODEL.to_string(),
            base_url: DEFAULT_BASE_URL.to_string(),
        }
    }
}

impl Settings {
    /// 校验来自 WebView 的非敏感设置。
    ///
    /// `base_url` 必须仍是 https 且不带 userinfo：密钥会随请求发往这个地址，
    /// 明文 http 会让密钥在链路上裸奔，URL 内嵌凭据则会把凭据写进日志与错误信息。
    /// 这不能防住"被攻破的 WebView 改写地址"（见 PROJECT_STATUS 记录的残余风险），
    /// 但能挡住最直接的两类失误。
    pub fn validate(&self) -> Result<(), String> {
        if self.model.trim().is_empty() {
            return Err("模型 id 不能为空".to_string());
        }
        if self.model.len() > MODEL_MAX_LEN {
            return Err(format!("模型 id 不能超过 {MODEL_MAX_LEN} 个字符"));
        }
        if !self
            .model
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '_' | ':' | '-'))
        {
            return Err("模型 id 只允许字母、数字与 . _ : -".to_string());
        }

        validate_base_url(&self.base_url)
    }
}

/// 校验服务地址。单独抽出来是为了能被直接单测（它是唯一在安全边界上的校验）。
pub fn validate_base_url(base_url: &str) -> Result<(), String> {
    if base_url.len() > BASE_URL_MAX_LEN {
        return Err(format!("服务地址不能超过 {BASE_URL_MAX_LEN} 个字符"));
    }
    let Some(rest) = base_url.strip_prefix("https://") else {
        return Err("服务地址必须以 https:// 开头（明文 http 会让密钥在链路上暴露）".to_string());
    };
    let authority = rest.split(['/', '?', '#']).next().unwrap_or_default();
    if authority.is_empty() {
        return Err("服务地址缺少主机名".to_string());
    }
    if authority.contains('@') {
        return Err("服务地址不能内嵌用户名或密码".to_string());
    }
    Ok(())
}

/// 设置文件的读写。绑定到具体目录，便于测试注入临时目录。
pub struct SettingsStore {
    path: PathBuf,
}

impl SettingsStore {
    /// 绑定到 SPEC-M00 §9.3 约定的 `%APPDATA%\EngMentor\`。
    pub fn in_app_data_dir(roaming_app_data: &Path) -> Self {
        Self {
            path: roaming_app_data
                .join(APP_DATA_DIR_NAME)
                .join(SETTINGS_FILE_NAME),
        }
    }

    pub fn path(&self) -> &Path {
        &self.path
    }

    /// 读取设置。文件不存在 → 默认值（首次启动的正常路径）；
    /// 文件损坏 → 默认值，并把原文件改名保留为 `.corrupt` 以便诊断，而不是静默丢弃证据。
    pub fn load(&self) -> Settings {
        let Ok(raw) = fs::read_to_string(&self.path) else {
            return Settings::default();
        };
        match serde_json::from_str::<Settings>(&raw) {
            Ok(settings) if settings.validate().is_ok() => settings,
            _ => {
                let _ = fs::rename(&self.path, self.path.with_extension("json.corrupt"));
                Settings::default()
            }
        }
    }

    pub fn save(&self, settings: &Settings) -> Result<(), String> {
        settings.validate()?;
        if let Some(parent) = self.path.parent() {
            fs::create_dir_all(parent)
                .map_err(|e| format!("无法创建设置目录 {}：{e}", parent.display()))?;
        }
        let body = serde_json::to_string_pretty(settings)
            .map_err(|e| format!("设置无法序列化：{e}"))?;
        let tmp = self.path.with_extension("json.tmp");
        fs::write(&tmp, format!("{body}\n"))
            .map_err(|e| format!("无法写入设置文件：{e}"))?;
        // Windows 上 std::fs::rename 会替换已存在的目标（MoveFileEx + REPLACE_EXISTING），
        // 因此这里不需要先删旧文件。
        fs::rename(&tmp, &self.path).map_err(|e| format!("无法提交设置文件：{e}"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_dir(tag: &str) -> PathBuf {
        let unique = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .expect("系统时间应晚于 UNIX 纪元")
            .as_nanos();
        let dir = std::env::temp_dir().join(format!("engm-settings-{tag}-{unique}"));
        fs::create_dir_all(&dir).expect("无法创建临时目录");
        dir
    }

    #[test]
    fn defaults_are_consent_off() {
        let settings = Settings::default();
        assert!(
            !settings.cloud_consent_granted,
            "上云同意必须默认关闭 —— 同意是用户主动动作，不能是默认值"
        );
        assert_eq!(settings.model, DEFAULT_MODEL);
        assert_eq!(settings.base_url, DEFAULT_BASE_URL);
    }

    #[test]
    fn missing_file_loads_defaults_and_round_trips() {
        let dir = temp_dir("roundtrip");
        let store = SettingsStore::in_app_data_dir(&dir);
        assert_eq!(store.load(), Settings::default());

        let settings = Settings {
            cloud_consent_granted: true,
            model: "deepseek-chat".to_string(),
            base_url: "https://api.deepseek.com/v1".to_string(),
        };
        store.save(&settings).expect("保存应成功");
        assert_eq!(store.load(), settings);

        fs::remove_dir_all(&dir).ok();
    }

    /// 设置文件里只能有这三个键 —— 尤其是不能出现密钥字段。
    /// §9.2 要求密钥不进任何文件，这条断言让"某天顺手加个 apiKey 字段"会立刻失败。
    #[test]
    fn serialized_settings_contain_exactly_the_non_secret_keys() {
        let json = serde_json::to_string(&Settings::default()).expect("可序列化");
        let value: serde_json::Value = serde_json::from_str(&json).expect("可解析");
        let mut keys: Vec<&str> = value
            .as_object()
            .expect("设置必须是对象")
            .keys()
            .map(String::as_str)
            .collect();
        keys.sort();
        assert_eq!(keys, ["baseUrl", "cloudConsentGranted", "model"]);
        assert!(
            !json.to_lowercase().contains("key"),
            "设置文件里不得出现任何 'key' 字段：{json}"
        );
    }

    #[test]
    fn corrupt_file_falls_back_to_defaults_and_is_kept_for_diagnosis() {
        let dir = temp_dir("corrupt");
        let store = SettingsStore::in_app_data_dir(&dir);
        fs::create_dir_all(store.path().parent().expect("有父目录")).unwrap();
        fs::write(store.path(), "{ this is not json").unwrap();

        assert_eq!(store.load(), Settings::default());
        assert!(
            store.path().with_extension("json.corrupt").exists(),
            "损坏的设置文件应被改名保留，而不是静默删除"
        );
        fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn base_url_must_be_https_with_a_host_and_no_userinfo() {
        for good in [
            "https://api.deepseek.com",
            "https://api.deepseek.com/v1",
            "https://127.0.0.1:8443/v1",
        ] {
            assert!(validate_base_url(good).is_ok(), "{good} 应被接受");
        }
        for bad in [
            "",
            "http://api.deepseek.com",
            "https://",
            "https:///v1",
            "https://user:pass@api.deepseek.com",
            "ftp://api.deepseek.com",
            "api.deepseek.com",
        ] {
            assert!(validate_base_url(bad).is_err(), "{bad} 应被拒绝");
        }
    }

    #[test]
    fn model_id_charset_is_restricted() {
        let with_space = Settings {
            model: "deepseek chat".to_string(),
            ..Settings::default()
        };
        assert!(with_space.validate().is_err(), "模型 id 不允许空格");

        let empty = Settings {
            model: String::new(),
            ..Settings::default()
        };
        assert!(empty.validate().is_err(), "模型 id 不允许为空");

        assert!(Settings::default().validate().is_ok());
    }

    #[test]
    fn save_rejects_invalid_settings_instead_of_persisting_them() {
        let dir = temp_dir("invalid");
        let store = SettingsStore::in_app_data_dir(&dir);
        let bad = Settings {
            cloud_consent_granted: true,
            model: "deepseek-flash".to_string(),
            base_url: "http://api.deepseek.com".to_string(),
        };
        assert!(store.save(&bad).is_err());
        assert!(
            !store.path().exists(),
            "校验失败时不应写出任何文件（否则下次启动会加载到一个非法配置）"
        );
        fs::remove_dir_all(&dir).ok();
    }
}
