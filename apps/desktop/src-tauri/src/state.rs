//! 主进程的共享状态。
//!
//! 三件东西需要跨命令共享：非敏感设置、密钥存储、以及 Sidecar 的按需启动槽。
//!
//! 密钥存储与 Sidecar 槽都以 `Arc` 注入/持有，有两个刻意的理由：
//!   * 密钥存储抽成 trait 之后，单测可以换成内存实现 —— 测试不往开发者机器的
//!     凭据管理器里写东西（真实凭据存储另有专门的端到端用例）；
//!   * Sidecar 槽放进 `Arc` 是为了**离开借用**：流式命令要在阻塞线程里做网络 IO，
//!     而 `tauri::State` 的借用活不过那个边界。

use std::sync::Arc;

use crate::contracts::ContractError;
use crate::secrets::{SecretStore, DEEPSEEK_API_KEY};
use crate::settings::SettingsStore;
use crate::sidecar::{LaunchSpec, SidecarSlot};

pub struct AppState {
    pub settings: SettingsStore,
    pub secrets: Arc<dyn SecretStore>,
    pub sidecar: Arc<SidecarSlot>,
}

impl AppState {
    pub fn new(settings: SettingsStore, secrets: Arc<dyn SecretStore>) -> Self {
        Self {
            settings,
            secrets,
            sidecar: Arc::new(SidecarSlot::default()),
        }
    }

    /// 读取已保存的凭据。**只在主进程内部使用** —— 任何命令都不得把它回传给 WebView。
    ///
    /// 读失败（凭据存储不可用）时按"未配置"处理：这条路径上宁可让用户看到
    /// "未配置 API Key"，也不该把一次平台故障说成"没配过"却继续往下走 ——
    /// 所以返回 `Err` 由调用方决定怎么表达。
    pub fn credential(&self) -> Result<Option<String>, ContractError> {
        self.secrets.get(DEEPSEEK_API_KEY).map_err(|error| {
            ContractError::internal_error(format!("读取凭据失败：{}", error.message))
        })
    }

    pub fn sidecar_slot(&self) -> Arc<SidecarSlot> {
        Arc::clone(&self.sidecar)
    }

    /// 组装 Sidecar 的启动参数。
    ///
    /// 注意这里**没有**同意开关：同意是在发起请求前逐次判定的（见 `commands`），
    /// 而不是启动参数。Sidecar 先起着、凭据先拿着，与"这次要不要真的发出去"
    /// 是两件事 —— 混在一起会让"关掉同意后仍可用本地功能"变得难以实现。
    pub fn launch_spec(&self) -> Result<LaunchSpec, ContractError> {
        let settings = self.settings.load();
        Ok(LaunchSpec::from_parts(
            self.credential()?,
            settings.base_url,
            settings.model,
        ))
    }

    /// 用户是否已明确同意把内容发往云端模型（Q5）。
    pub fn cloud_consent_granted(&self) -> bool {
        self.settings.load().cloud_consent_granted
    }
}

/// 未授予上云同意时的失败。
///
/// 这是 Q5 的落点：同意关闭时对话请求根本不发往 Sidecar —— 门禁在主进程里，
/// 因为主进程才是知道这条策略的那一层。UI 也会拦，但那只是提示，不是保证。
pub fn consent_required() -> ContractError {
    ContractError::invalid_input(
        "尚未同意把内容发送给云端模型。请在「设置 → 内容上云」中勾选后再试。",
    )
}

/// 未配置凭据时的失败。
pub fn credential_required() -> ContractError {
    ContractError::invalid_input("尚未配置 DeepSeek API Key。请在「设置」中填写并保存。")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::secrets::InMemorySecretStore;
    use crate::settings::{Settings, SettingsStore};
    use std::path::PathBuf;

    fn temp_dir(tag: &str) -> PathBuf {
        let unique = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .expect("系统时间应晚于 UNIX 纪元")
            .as_nanos();
        let dir = std::env::temp_dir().join(format!("engm-state-{tag}-{unique}"));
        std::fs::create_dir_all(&dir).expect("无法创建临时目录");
        dir
    }

    #[test]
    fn launch_spec_carries_no_credential_until_one_is_stored() {
        let dir = temp_dir("no-credential");
        let state = AppState::new(
            SettingsStore::in_app_data_dir(&dir),
            Arc::new(InMemorySecretStore::new()),
        );

        let spec = state.launch_spec().expect("可以组装启动参数");
        assert_eq!(spec.api_key, None, "没存过凭据时不应凭空有值");
        assert_eq!(spec.model.as_deref(), Some(crate::settings::DEFAULT_MODEL));
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn launch_spec_reflects_consent_independently_of_the_credential() {
        let dir = temp_dir("consent");
        let store = SettingsStore::in_app_data_dir(&dir);
        let state = AppState::new(store, Arc::new(InMemorySecretStore::new()));

        assert!(!state.cloud_consent_granted(), "同意默认关闭");

        let settings = Settings {
            cloud_consent_granted: true,
            ..Settings::default()
        };
        state.settings.save(&settings).expect("保存应成功");

        assert!(state.cloud_consent_granted());
        assert_eq!(
            state.launch_spec().expect("可以组装启动参数").api_key,
            None,
            "同意上云不等于已经给了凭据 —— 两者互相独立"
        );
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn the_consent_and_credential_failures_use_distinct_actionable_messages() {
        use crate::contracts::CODE_INVALID_INPUT;

        assert!(consent_required().message.contains("设置"));
        assert!(credential_required().message.contains("API Key"));
        assert_eq!(consent_required().code, CODE_INVALID_INPUT);
        assert_eq!(credential_required().code, CODE_INVALID_INPUT);
    }
}
