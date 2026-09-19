// EngMentor 桌面壳的 Rust 主进程（M00 骨架）。
//
// 本文件刻意不注册任何 Tauri command：特权操作（密钥、文件路径、Sidecar 生命周期）
// 尚未实现，等各自模块的 Spec 获批后再加入（SPEC-M00 §2 非目标、§5.1 边界规则）。

#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

// 契约的运行时校验层（SPEC-M00 §5.3）。四条边界的入口在这里定义、由单元测试实际驱动，
// 但 M00 的桌面壳刻意**不注册任何 Tauri command**（§2 非目标），所以二进制目标里暂时没有调用方。
// 因此这里显式允许 dead_code —— 这是对"尚未接线"的登记，不是放宽正确性检查：
// 首个 IPC 命令落地（M01/M03）后必须删掉这个注解，让 clippy 重新把未使用的边界当问题报出来。
#[allow(dead_code)]
mod contracts;

fn main() {
    tauri::Builder::default()
        .run(tauri::generate_context!())
        .expect("桌面壳启动失败");
}

#[cfg(test)]
mod tests {
    // 与前端同名测试对称：把 tauri.conf.json 的范围约束钉在测试里，
    // 让"提前开启打包"或"改 identifier"这类改动会直接失败。
    const TAURI_CONF: &str = include_str!("../tauri.conf.json");

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
}
