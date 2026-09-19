//! 密钥的读写边界（T012 最小版本；SPEC-M00 §9.2）。
//!
//! 全仓库只有这一处会碰真实密钥。围绕它有三条硬性规则，都在代码里体现：
//!
//!   1. **唯一合法位置是 OS 凭据存储**（Windows 上是凭据管理器）。密钥不写
//!      `settings.json`、不进 SQLite、不进日志、不进错误详情、不进 WebView 状态。
//!   2. **抽象成 trait**：生产用 OS 凭据存储，测试用内存实现。这样单测不依赖
//!      运行环境的凭据服务，也不会在开发者机器上留下垃圾条目。
//!   3. **错误信息绝不带密钥**。`keyring` 的部分错误变体（`BadEncoding`、
//!      `BadDataFormat`）把检索到的原始字节挂在载荷里 —— 那些字节可能就是密钥本身，
//!      因此对它们只给固定文案，不做任何格式化。
//!
//! 「UI 不能读取完整密钥」这条验收标准靠接口形状保证：本模块的读接口只暴露
//! [`SecretStore::get`]，而 Tauri 命令层只把它用来判断"是否已配置"，从不回传值。

use std::collections::HashMap;
use std::sync::Mutex;

/// 密钥存储不可用或操作失败。字段刻意只有「类别 + 固定文案」两级，
/// 因为任何携带原始载荷的错误都可能把密钥带出去（见模块文档第 3 条）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SecretStoreError {
    pub kind: SecretStoreErrorKind,
    pub message: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SecretStoreErrorKind {
    /// 本次操作失败（平台报错、权限、长度超限等）。
    Operation,
    /// 凭据存储本身在当前环境不可用（没有可用后端）。
    Unavailable,
}

impl SecretStoreError {
    fn operation(message: impl Into<String>) -> Self {
        Self {
            kind: SecretStoreErrorKind::Operation,
            message: message.into(),
        }
    }

    fn unavailable(message: impl Into<String>) -> Self {
        Self {
            kind: SecretStoreErrorKind::Unavailable,
            message: message.into(),
        }
    }
}

/// 密钥的存/取/删。`name` 是应用内的逻辑名（如 `deepseek.apiKey`），
/// 不是用户可见文本，因此可以出现在诊断里；值才是秘密。
pub trait SecretStore: Send + Sync {
    fn set(&self, name: &str, secret: &str) -> Result<(), SecretStoreError>;
    /// `Ok(None)` 表示"尚未配置"——这是正常状态，不是错误。
    fn get(&self, name: &str) -> Result<Option<String>, SecretStoreError>;
    /// 删除不存在的条目视为成功（幂等），这样"清除"按钮可以随便点。
    fn delete(&self, name: &str) -> Result<(), SecretStoreError>;
}

/// 密钥在应用内的逻辑名。
pub const DEEPSEEK_API_KEY: &str = "deepseek.apiKey";

/// 把 `keyring` 的错误压成不含载荷的文案。
///
/// 这是本模块最需要小心的一处：`BadEncoding` / `BadDataFormat` 的载荷是
/// **检索到的原始字节**，也就是密钥。它们必须走最后那条兜底分支，
/// 不能 `format!("{err}")` —— 那正是密钥泄漏进日志的最短路径。
fn describe(err: &keyring::Error) -> SecretStoreError {
    match err {
        keyring::Error::PlatformFailure(e) | keyring::Error::NoStorageAccess(e) => {
            SecretStoreError::operation(format!("凭据存储平台错误：{e}"))
        }
        keyring::Error::NoDefaultStore => {
            SecretStoreError::unavailable("当前环境没有可用的凭据存储后端")
        }
        keyring::Error::NotSupportedByStore(reason) => {
            SecretStoreError::operation(format!("凭据存储不支持该操作：{reason}"))
        }
        keyring::Error::Invalid(attribute, reason) => {
            SecretStoreError::operation(format!("凭据参数无效（{attribute}）：{reason}"))
        }
        keyring::Error::TooLong(attribute, limit) => {
            SecretStoreError::operation(format!("凭据字段 {attribute} 超出平台上限 {limit} 字节"))
        }
        keyring::Error::BadStoreFormat(reason) => {
            SecretStoreError::operation(format!("凭据存储格式异常：{reason}"))
        }
        keyring::Error::Ambiguous(_) => {
            SecretStoreError::operation("凭据存储里存在多个同名条目，无法确定使用哪一个")
        }
        // 载荷可能包含密钥本体的分支，一律固定文案。
        _ => SecretStoreError::operation("凭据存储返回了无法安全描述的响应（已省略详情）"),
    }
}

/// 生产实现：OS 凭据存储。
pub struct OsKeychainStore {
    service: String,
}

impl OsKeychainStore {
    /// `service` 是凭据管理器里显示的来源名。固定为应用标识，
    /// 让用户在系统的凭据管理器里能认出来源。
    pub fn new(service: impl Into<String>) -> Self {
        Self {
            service: service.into(),
        }
    }

    fn entry(&self, name: &str) -> Result<keyring::Entry, SecretStoreError> {
        keyring::Entry::new(&self.service, name).map_err(|e| describe(&e))
    }
}

impl SecretStore for OsKeychainStore {
    fn set(&self, name: &str, secret: &str) -> Result<(), SecretStoreError> {
        self.entry(name)?
            .set_password(secret)
            .map_err(|e| describe(&e))
    }

    fn get(&self, name: &str) -> Result<Option<String>, SecretStoreError> {
        match self.entry(name)?.get_password() {
            Ok(value) => Ok(Some(value)),
            Err(keyring::Error::NoEntry) => Ok(None),
            Err(e) => Err(describe(&e)),
        }
    }

    fn delete(&self, name: &str) -> Result<(), SecretStoreError> {
        match self.entry(name)?.delete_credential() {
            Ok(()) | Err(keyring::Error::NoEntry) => Ok(()),
            Err(e) => Err(describe(&e)),
        }
    }
}

/// 测试用内存实现。不用 OS 凭据存储是有意的：单测不该往开发者机器的
/// 凭据管理器里写东西（真实凭据存储另有单独的端到端用例）。
#[derive(Default)]
pub struct InMemorySecretStore {
    entries: Mutex<HashMap<String, String>>,
}

impl InMemorySecretStore {
    pub fn new() -> Self {
        Self::default()
    }
}

impl SecretStore for InMemorySecretStore {
    fn set(&self, name: &str, secret: &str) -> Result<(), SecretStoreError> {
        self.entries
            .lock()
            .expect("内存凭据存储的锁不应中毒")
            .insert(name.to_string(), secret.to_string());
        Ok(())
    }

    fn get(&self, name: &str) -> Result<Option<String>, SecretStoreError> {
        Ok(self
            .entries
            .lock()
            .expect("内存凭据存储的锁不应中毒")
            .get(name)
            .cloned())
    }

    fn delete(&self, name: &str) -> Result<(), SecretStoreError> {
        self.entries
            .lock()
            .expect("内存凭据存储的锁不应中毒")
            .remove(name);
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn in_memory_store_round_trips_and_deletes_idempotently() {
        let store = InMemorySecretStore::new();
        assert_eq!(store.get(DEEPSEEK_API_KEY).unwrap(), None);

        store.set(DEEPSEEK_API_KEY, "sk-not-a-real-key").unwrap();
        assert_eq!(
            store.get(DEEPSEEK_API_KEY).unwrap().as_deref(),
            Some("sk-not-a-real-key")
        );

        store.delete(DEEPSEEK_API_KEY).unwrap();
        assert_eq!(store.get(DEEPSEEK_API_KEY).unwrap(), None);
        // 重复删除必须成功，"清除"按钮不该因为没配过就报错。
        store.delete(DEEPSEEK_API_KEY).unwrap();
    }

    /// 错误文案里绝不能带上密钥。这条是 §9.2 的直接断言，不是形式检查：
    /// `describe` 里若有人改回 `format!("{err}")`，把密钥塞进 `BadDataFormat`
    /// 载荷就会立刻失败。
    #[test]
    fn error_descriptions_never_leak_the_secret_payload() {
        let secret = "sk-live-SECRET-0123456789";
        let errors = [
            keyring::Error::BadEncoding(secret.as_bytes().to_vec()),
            keyring::Error::BadDataFormat(
                secret.as_bytes().to_vec(),
                Box::new(std::io::Error::other("x")),
            ),
        ];
        for err in errors {
            let described = describe(&err);
            let rendered = format!("{} {}", described.message, described.kind as u8);
            assert!(
                !rendered.contains(secret),
                "错误文案泄漏了密钥载荷：{rendered}"
            );
        }
    }

    /// 真实 OS 凭据存储的端到端往返（写 → 读 → 删），用完即清。
    ///
    /// 用带进程号与纳秒的唯一 service 名，避免与开发机上真实的
    /// `com.engmentor.desktop` 条目互相干扰；清理靠 `Drop`，即使断言
    /// 中途 panic 也会执行（唯一残留情形是进程被强杀，残留的也是一条
    /// 名字里带 `engmentor-selftest` 的空条目，不影响应用功能）。
    #[test]
    fn os_keychain_round_trips_through_the_real_platform_store() {
        struct Cleanup<'a>(&'a OsKeychainStore);
        impl Drop for Cleanup<'_> {
            fn drop(&mut self) {
                let _ = self.0.delete("selftest.apiKey");
            }
        }

        let unique = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .expect("系统时间应晚于 UNIX 纪元")
            .as_nanos();
        let store = OsKeychainStore::new(format!("engmentor-selftest-{}-{unique}", std::process::id()));
        let _cleanup = Cleanup(&store);

        store
            .set("selftest.apiKey", "sk-selftest-value")
            .expect("写入 OS 凭据存储应成功（若失败，说明该环境没有可用的凭据后端）");
        assert_eq!(
            store.get("selftest.apiKey").unwrap().as_deref(),
            Some("sk-selftest-value"),
            "从 OS 凭据存储读回的值应与写入一致"
        );

        store.delete("selftest.apiKey").unwrap();
        assert_eq!(
            store.get("selftest.apiKey").unwrap(),
            None,
            "删除后应回到未配置状态"
        );
    }
}
