## 🌐 Language / 语言

[**English**](#english) | [**中文**](#zh-cn)

---

<a id="english"></a>

### v4.0.0 — Architecture Refactoring & Consistency Convergence

---

#### What's New

| Category | Details |
| --- | --- |
| Architecture | Removed legacy `src/` directory (containing v2 duplicate code); unified to single-source root structure |
| Architecture | All project files unified to UTF-8 encoding; PS1 scripts ensured UTF-8 with BOM |
| Refactor | Uninstall self-deletion logic rewritten: uses independent cmd file with retry loop, fixing broken command-line concatenation |
| Refactor | Installer VBS file encoding changed from `Default` (ANSI) to UTF-8, preventing Chinese path corruption |
| Fix | Fixed duplicate text "永不睡眠、永不休眠" in `set-never-sleep.ps1` (v2 legacy bug) |
| Fix | Corrected state filenames in `.gitignore` (`.last-signin-date.txt` → `last-signin-date.txt`) |
| Consistency | Global version bumped to **v4.0.0** across all scripts, launchers, and documentation |
| Consistency | Full-project convergence: version, product name, encoding, path rules all aligned |

---

#### Package Contents

```
workbuddy-checkin-v4.0.0.zip
├── workbuddy-checkin.ps1     # Core check-in script
├── install-task.ps1          # One-click installer: scheduled task + startup auto-run
├── uninstall-task.ps1        # One-click uninstaller: removes task, startup, power settings
├── uninstall.bat             # Double-click uninstaller (calls uninstall-task.ps1)
├── set-never-sleep.ps1       # Power settings: never sleep / never hibernate
└── LICENSE                   # MIT License
```

---

#### Quick Start

```powershell
# 1. Download and extract the zip
# 2. Right-click PowerShell → "Run as administrator", then execute:
powershell -NoProfile -ExecutionPolicy Bypass -File ".\install-task.ps1"

# Verify without clicking (safe test)
powershell -NoProfile -ExecutionPolicy Bypass -File ".\workbuddy-checkin.ps1" -DryRun
```

---

#### System Requirements

- Windows 10 / 11
- Simplified Chinese OCR language pack
- Windows PowerShell 5.1 (built-in)

---

#### SHA-256 Checksum

| File | SHA-256 |
| --- | --- |
| workbuddy-checkin-v4.0.0.zip | `9AB33D6E607BCF749CEFF15BA72A1542DFB1EA415F64B538AEC0FCCF76888F59` |

---

<a id="zh-cn"></a>

### v4.0.0 — 架构重构与一致性收敛

---

#### 变更亮点

| 类别 | 说明 |
| --- | --- |
| 架构 | 删除遗留 `src/` 目录（含 v2 旧版重复代码），统一为根目录单源结构 |
| 架构 | 全项目文件编码统一为 UTF-8，PS1 脚本文件确保 with BOM |
| 重构 | 卸载脚本自删除逻辑重写：使用独立 cmd 文件 + 循环重试，修复原生命行拼接错误 |
| 重构 | 安装脚本 VBS 文件编码从 `Default`（ANSI）改为 UTF-8，避免中文路径乱码 |
| 修复 | `set-never-sleep.ps1` 中「永不睡眠、永不休眠」重复文本修复（原 v2 遗留错误） |
| 修复 | `.gitignore` 中状态文件名修正（`.last-signin-date.txt` → `last-signin-date.txt`） |
| 一致性 | 全项目版本标识统一升级至 **v4.0.0**，所有脚本、启动器、文档完全一致 |
| 一致性 | 全项目收敛：版本号、产品名、编码、路径规则全面对齐 |

---

#### 资源包内容

```
workbuddy-checkin-v4.0.0.zip
├── workbuddy-checkin.ps1     # 核心签到脚本
├── install-task.ps1          # 一键安装：计划任务 + 登录自启
├── uninstall-task.ps1        # 一键卸载：删除计划任务 + 自启项 + 电源还原
├── uninstall.bat             # 双击即可卸载（调用 uninstall-task.ps1）
├── set-never-sleep.ps1       # 电源设置：永不睡眠 / 永不休眠
└── LICENSE                   # MIT 许可证
```

---

#### 快速开始

```powershell
# 1. 下载并解压压缩包
# 2. 右键 PowerShell →「以管理员身份运行」，执行：
powershell -NoProfile -ExecutionPolicy Bypass -File ".\install-task.ps1"

# 立即验证（只识别不点击，安全测试）
powershell -NoProfile -ExecutionPolicy Bypass -File ".\workbuddy-checkin.ps1" -DryRun
```

---

#### 系统要求

- Windows 10 / 11
- 简体中文 OCR 语言包
- Windows PowerShell 5.1（系统自带）

---

#### SHA-256 校验

| 文件 | SHA-256 |
| --- | --- |
| workbuddy-checkin-v4.0.0.zip | `9AB33D6E607BCF749CEFF15BA72A1542DFB1EA415F64B538AEC0FCCF76888F59` |
