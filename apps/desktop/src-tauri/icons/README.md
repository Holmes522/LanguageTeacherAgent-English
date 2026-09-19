# src-tauri/icons — 应用图标

## `icon.ico` 是什么

**占位图标，不是品牌资产。** 32×32、32bpp 的合法 ICO（BMP 格式条目，BGRA + AND 掩码），
一个深蓝底 + 天蓝方块的简单图案。真实品牌图标由 **T050（Windows 发布门禁）** 替换。

## 为什么需要有这个文件

`tauri-build` 在 **Windows 上总会**生成一个资源文件（.rc），并因此要求 `icons/icon.ico` 存在
——即使 `tauri.conf.json` 里 `bundle.active` 是 `false`。缺少它时 `cargo build` 会直接失败：

```text
`icons/icon.ico` not found; required for generating a Windows Resource file during tauri-build
```

这个失败在 T010-A 第一次 `cargo build` 时真实发生过，记录在 PROJECT_STATUS 的交接记录里。

## 为什么提交生成器

`make_placeholder_icon.py` 用纯标准库（`struct`）写出这个 ICO，不依赖任何图像库：

- 让图标的来源可复核、可重现，而不是一个来历不明的二进制文件；
- 避免为了一个占位图引入 Pillow 之类的依赖。

注意：该脚本是一次性开发辅助工具，**不在** `services/ai-core` 的 ruff / mypy 检查范围内
（那些工具只覆盖 Python 包本身）。这是有意的取舍，不是遗漏；如果将来需要更多生成器，
应当把它们集中到一个受检查的 `tools/` 目录并纳入质量命令。

生成方式：

```powershell
python apps/desktop/src-tauri/icons/make_placeholder_icon.py
```

## 后续要补的（不属于 T010-A）

- 完整的图标集（各尺寸 PNG、`icon.icns`、Store 徽标），使用 `pnpm tauri icon <源图>` 生成；
- 启用 `bundle.active` 与代码签名（T050）。
