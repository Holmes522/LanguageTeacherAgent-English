//! EngMentor 桌面壳的 Rust 主进程。
//!
//! 主进程是唯一的特权层（SPEC-M00 §5.1）：密钥、文件路径、进程与 Sidecar 生命周期
//! 都在这里。WebView 只能通过 [`commands`] 里注册的白名单命令触达它，
//! 没有任意 fs / shell / http 能力。
//!
//! 拆成 lib + 极薄的 bin 有两个实际原因，都不是风格问题：
//!
//!   1. **让 clippy 的 `dead_code` 保持有意义**。可执行目标的 `pub` 项对编译器来说
//!      没有任何外部调用方，于是"只有测试和后续步骤会用到的公开接口"会被报成 dead_code，
//!      逼我们在生产代码里撒 `#[allow(dead_code)]` —— 那正好会掩盖真正的未接线代码。
//!      作为库，这些公开接口是真实 API 面。
//!   2. 集成测试可以像用普通库一样驱动这套代码，而不必绕过二进制目标。

pub mod commands;
pub mod contracts;
pub mod http;
pub mod secrets;
pub mod settings;
pub mod sidecar;
pub mod state;

use std::path::Path;
use std::sync::Arc;

use secrets::OsKeychainStore;
use settings::SettingsStore;
use state::AppState;

/// OS 凭据存储里的来源名。与 `tauri.conf.json` 的 identifier 一致，
/// 让用户在系统的凭据管理器里能认出这条记录属于谁。
pub const KEYCHAIN_SERVICE: &str = "com.engmentor.desktop";

/// Tauri 配置在编译期嵌入，供测试断言范围约束（打包开关、identifier 等）。
pub const TAURI_CONF: &str = include_str!("../tauri.conf.json");

/// 组装主进程状态。
///
/// `roaming_app_data` 由 Tauri 的路径解析器注入（Windows 上是 `%APPDATA%`），
/// 这里再按 SPEC-M00 §9.3 拼上应用目录名 —— 不用 `app_data_dir()`，因为那会按
/// identifier 生成 `com.engmentor.desktop` 目录，与 Spec 约定的 `EngMentor` 不符。
pub fn app_state(roaming_app_data: &Path) -> AppState {
    AppState::new(
        SettingsStore::in_app_data_dir(roaming_app_data),
        Arc::new(OsKeychainStore::new(KEYCHAIN_SERVICE)),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    fn conf() -> serde_json::Value {
        serde_json::from_str(TAURI_CONF).expect("tauri.conf.json 必须是合法 JSON")
    }

    #[test]
    fn identifier_matches_frontend_expectation() {
        assert_eq!(conf()["identifier"].as_str(), Some("com.engmentor.desktop"));
    }

    #[test]
    fn bundling_is_disabled_until_t050() {
        assert_eq!(conf()["bundle"]["active"].as_bool(), Some(false));
    }

    /// 凭据存储的来源名必须与 identifier 一致，否则用户在凭据管理器里
    /// 看到的名字和应用对不上。
    #[test]
    fn keychain_service_matches_the_identifier() {
        assert_eq!(conf()["identifier"].as_str(), Some(KEYCHAIN_SERVICE));
    }

    /// 应用数据目录按 SPEC-M00 §9.3 落在 roaming AppData 下的 EngMentor，
    /// 而不是按 identifier 命名的目录。
    #[test]
    fn app_state_places_settings_under_the_engmentor_directory() {
        let state = app_state(Path::new("C:/Users/example/AppData/Roaming"));
        let path = state.settings.path().to_string_lossy().replace('\\', "/");
        assert_eq!(
            path,
            "C:/Users/example/AppData/Roaming/EngMentor/settings.json"
        );
    }
}
