// EngMentor 桌面壳的可执行入口。
//
// 这里刻意保持极薄：全部逻辑在 engmentor_desktop 库里（见 lib.rs 的模块文档），
// 主进程只负责组装 Tauri、注入状态、注册白名单命令。
// 这样 `cargo test` / clippy 面对的是一个有真实调用方的库，而不是一个
// 除了 main() 没有任何外部调用方的可执行目标。

#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use engmentor_desktop::{app_state, commands};
use tauri::Manager;

fn main() {
    tauri::Builder::default()
        .setup(|app| {
            let roaming = app.path().data_dir()?;
            app.manage(app_state(&roaming));
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            commands::settings_read,
            commands::settings_write,
            commands::credential_set,
            commands::credential_clear,
            commands::sidecar_status,
            commands::chat_stream,
        ])
        .run(tauri::generate_context!())
        .expect("桌面壳启动失败");
}
