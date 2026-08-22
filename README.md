# WorkBuddy 每日自动签到 / WorkBuddy Daily Auto Check-in

> 🇨🇳 [中文版](#中文版) ｜ 🇬🇧 [English Version](#english-version)

一个**完全免费、无需安装任何第三方库**的 Windows 自动化工具。每天自动打开 WorkBuddy，
完成「Buddy 加油站」每日签到领积分，签到完成后**自动退出 WorkBuddy 和脚本**；若检测到
WorkBuddy 正在执行任务或用户正在使用，则**不会强退**。

A **completely free, zero-dependency** Windows automation tool. It automatically opens
WorkBuddy daily, completes the "Buddy Gas Station" daily check-in to earn points, then
**automatically exits WorkBuddy and itself**; it **never force-quits** while a task is
running or the user is actively using it.

原理 / How it works：截屏 + Windows 自带中文 OCR 识别界面文字 + 模拟鼠标点击。
Screen capture + Windows built-in Chinese OCR + simulated mouse clicks.

---

# 中文版

## ⚠️ 重要提醒（请先阅读）

- 本工具通过**模拟鼠标点击**自动执行 WorkBuddy 的「每日签到领积分」操作，属于**个人自动化行为**。
  请在使用前自行确认该行为符合 WorkBuddy / CodeBuddy 的服务条款，因使用本工具产生的任何后果由使用者自行承担。
- 本工具**仅供学习与技术交流使用**，请勿滥用。签到规则、积分与奖励的最终解释权归官方所有。
- 本工具**不收集、不上传任何个人信息**，所有数据（状态、日志）仅保存在本地。
- 依赖环境：**Windows 10/11 + 简体中文 OCR 语言包 + Windows PowerShell 5.1**（系统自带）。
- 本工具会在签到时段**短暂将 WorkBuddy 窗口置于前台并移动鼠标**，请勿在此时操作电脑。

## ✨ 功能特性

| 功能 | 说明 |
| --- | --- |
| 全自动签到 | 自动启动 WorkBuddy → 识别「立即领取」→ 点击签到 → 轮询验证成功 |
| 已签到检测 | 界面显示「今日已签到」时不重复点击；状态文件记录，当日其余时间零开销跳过（约 0.7 秒） |
| 已签到判定兜底 | 打开加油站页面后找不到「立即领取」→ 判定今日已签到并更新状态，杜绝"已签到却每小时反复打开 WorkBuddy" |
| 自动退出 | 签到完成后自动关闭 WorkBuddy 并退出脚本（仅关闭本脚本启动的 WB 或执行了领取的情况；用户自己打开的 WB 不会强关） |
| 任务保护 | 检测到 WB 正在执行任务（界面关键词 + 窗口标题 + CPU 采样）→ 不退出，等待（默认最多 30 分钟），超时保留 WB 运行 |
| 用户保护 | 用户正在使用 WorkBuddy / 正在操作电脑时，不抢点、不强退 |
| 开机自启 | 重启电脑后登录即自动补签，无需手动打开任何东西 |
| 每日定时 | 每天 08:30 起每小时重试，错过（关机/睡眠/锁屏）自动补跑；**任务隐藏窗口运行，无黑框闪烁** |
| 锁屏保护 | 屏幕锁定时不模拟点击，避免误操作 |
| 单实例锁 | 重复触发时自动跳过；**锁带自愈**：卡死的旧实例超过 45 分钟会被自动终止并接管 |
| 防挂死 | 每次 OCR 调用带 15 秒超时保护，脚本不会无限卡住 |
| 完整日志 | 月度日志文件 + 最近结果文件；失败时自动输出屏幕 OCR 文本前 15 行方便诊断 |
| 托盘通知 | 签到成功/失败时系统托盘气泡提示（可 -NoNotify 关闭） |
| 头像校准 | 若入口识别不到，可用 -Calibrate 一键校准坐标 |
| 永不休眠 | 附带电源设置脚本，避免电脑睡眠导致错过签到 |

## 📁 目录结构

```
workbuddy-checkin/
├── src/
│   ├── workbuddy-checkin.ps1     # 核心签到脚本（全部逻辑）
│   ├── install-task.ps1          # 一键安装：计划任务 + 登录自启
│   ├── uninstall-task.ps1        # 一键卸载：支持彻底卸载与电源还原
│   └── set-never-sleep.ps1       # 电源设置：永不休眠/永不休眠
├── README.md                     # 双语文档（本文件）
└── LICENSE                       # MIT 许可证
```

运行后自动生成的文件（在脚本目录内）：

```
├── logs\                         # 月度日志 checkin-yyyy-MM.log（自动清理 180 天前的）
├── debug\                        # 调试截图（-SaveScreens 时生成）
├── task-template.xml             # 计划任务模板（安装时自动生成）
├── workbuddy-config.json         # 头像坐标（校准后生成）
├── last-signin-date.txt          # 最近成功签到日期（自动维护）
├── last-result.txt               # 最近一次运行结果
├── power-change-result.txt       # 电源设置脚本输出
└── .checkin.lock                 # 单实例锁（自动维护）
```

## 🚀 快速开始

### 1. 一键安装（只需一次）

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\path\to\workbuddy-checkin\src\install-task.ps1"
```

安装脚本自动完成两件事：

1. **注册计划任务「WorkBuddy每日签到」**：每天 08:30 起，每小时重复 16 小时；
   错过触发时间（关机/睡眠）后自动补跑（StartWhenAvailable）。
2. **创建登录自启项**（启动文件夹 VBS）：每次登录 Windows 自动补签，
   **重启后无需手动打开任何东西**。

> 若系统提示权限不足，右键"以管理员身份运行"PowerShell 再执行一次即可
> （管理员模式下会额外注册"登录时触发"，非管理员也能正常使用）。

### 2. 立即验证

```powershell
# 只识别不点击（安全测试，确认 OCR 与界面识别正常）
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\path\to\workbuddy-checkin\src\workbuddy-checkin.ps1" -DryRun

# 立即真实签到一次（当天未签时执行，签完自动退出 WorkBuddy）
schtasks /Run /TN "WorkBuddy每日签到"

# 查看最近一次结果
type "C:\path\to\workbuddy-checkin\last-result.txt"
```

### 3. 查看日志

```powershell
type "C:\path\to\workbuddy-checkin\logs\checkin-2026-08.log"
```

## 🔄 日常运行流程（自动）

1. 每天 08:30（及每小时重试）计划任务触发，或每次登录时自启项触发；
2. 脚本检查：若状态文件显示今日已签到 → 立即退出（约 0.7 秒，零开销）；
3. 屏幕锁定 → 跳过本次（避免误操作），下个整点自动重试；
4. 若用户正在操作电脑（键盘/鼠标活跃）→ 等待最多 5 分钟，仍活跃则本次跳过；
5. 启动 WorkBuddy（如未运行）→ 置前显示；
6. OCR 识别：找「立即领取」→ 点击 → 轮询验证（按钮消失/出现已签文案即成功）；
   或识别「今日已签到」→ 直接跳过；或点击「Buddy加油站」入口进入后再识别；
   打开加油站页面后仍找不到领取按钮 → 判定今日已签到；
7. 记录今日已签到 → 进入智能退出：
   - 仅当「本脚本启动了 WorkBuddy」或「实际执行了领取」时才考虑退出；
   - 检测任务（界面文字 + 窗口标题 + CPU 采样）与用户活动；
   - 无任务且无用户操作 → 自动关闭 WorkBuddy，脚本退出；
   - 有任务/用户在使用 → 等待（默认最多 30 分钟），超时保留 WB 运行、仅退出脚本。

## 🛠 常用命令速查

| 用途 | 命令 |
| --- | --- |
| 立即签到一次 | `schtasks /Run /TN "WorkBuddy每日签到"` |
| 查看任务详情 | `schtasks /Query /TN "WorkBuddy每日签到" /V /FO LIST` |
| 只识别不点击 | `workbuddy-checkin.ps1 -DryRun` |
| 签到但不退出 WB（调试） | `workbuddy-checkin.ps1 -NoExit` |
| 校准头像坐标 | `workbuddy-checkin.ps1 -Calibrate`（按提示点击一次左下角头像） |
| 保存调试截图 | `workbuddy-checkin.ps1 -SaveScreens`（截图存 debug\） |
| 严格模式（不自动判定已签到） | `workbuddy-checkin.ps1 -NoAssumeDone` |
| 调整签到时间 | `install-task.ps1 -Time 09:00` |
| 常规卸载（删任务+自启） | `uninstall-task.ps1` |
| 彻底卸载（连文件夹一起删） | `uninstall-task.ps1 -RemoveAll` |
| 卸载时还原电源设置 | `uninstall-task.ps1 -RemoveAll -RestorePower` |
| 卸载演练（不实际删除） | `uninstall-task.ps1 -RemoveAll -WhatIf` |

### 卸载说明

本程序产生的所有"痕迹"及其清理方式：

| 痕迹 | 位置 | 卸载程序会处理吗 |
| --- | --- | --- |
| 计划任务「WorkBuddy每日签到」 | 任务计划程序 | ✅ 自动删除（含系统注册表缓存） |
| 登录自启项 | 启动文件夹 VBS | ✅ 自动删除 |
| 注册表 Run 键 | 注册表 | 无需清理（本程序**从不写注册表**） |
| 项目文件夹（脚本/日志/结果/状态文件） | 脚本目录 | 加 `-RemoveAll` 后自动删除 |
| 电源设置（永不休眠） | 系统电源方案 | 加 `-RestorePower` 恢复默认（睡眠 15/10 分钟、休眠 3 小时） |

> 说明：自动签到积累的积分保存在 WorkBuddy 服务器端，卸载本程序不影响已获取的积分。

## ❓ 常见问题

**Q1：签到失败，日志提示"未识别到签到相关元素"？**
- 确认 WorkBuddy 已登录账号（未登录会提示）。
- 头像默认位置按窗口左下角计算，若界面布局不同，运行一次 `workbuddy-checkin.ps1 -Calibrate` 校准。
- 加 `-SaveScreens` 重跑，查看 debug\ 下的截图定位问题。
- 脚本失败时会自动在日志中输出屏幕 OCR 前 15 行文本，便于对照。

**Q2：提示"系统没有可用的简体中文 OCR 引擎"？**
Windows 设置 → 时间和语言 → 语言 → 添加"简体中文"语言包即可（重启生效）。

**Q3：WorkBuddy 升级后按钮文字变了？**
脚本顶部的 `$ClaimPattern` / `$DonePattern` / `$EntryPattern` 是正则关键词，按新界面文字修改即可；
OCR 无法识别时用 `-SaveScreens` 截图对照。

**Q4：担心重复签到/点错？**
- 「立即领取」按钮消失或出现「今日已签到」即不再点击；
- 已签到当日，后续所有触发都直接跳过（约 0.7 秒）；
- 单实例锁保证同一时刻只有一个签到进程。

**Q4b：明明已签到，却时不时弹出 WorkBuddy？**
这是 v1 的缺陷：打开加油站页面后找不到「立即领取」时被当作"失败"，状态文件不更新，
于是每小时都重新打开 WorkBuddy 反复尝试。**v2 已修复**：找不到领取按钮且界面为加油站/积分内容时，
判定「今日已签到」并立即更新状态文件，后续每小时触发直接跳过、不再打开 WorkBuddy。
若想保守处理（宁可漏签也不误判），可用 `-NoAssumeDone` 参数。

**Q5：电脑关机了一整天，还能补签吗？**
能。计划任务 `StartWhenAvailable` + 登录自启项双保险：开机登录后会自动补跑。

**Q6：电脑空闲太久会自动睡眠，导致错过签到？**
已处理：`set-never-sleep.ps1` 可将**所有电源方案**的「睡眠」和「休眠」都设为**从不**（交流/直流）。

**Q7：电脑有密码，锁屏时能签到吗？**
锁屏时脚本会**安全跳过**（不做任何点击，防止误操作），解锁后 1 小时内由每小时重试自动补签。
这是有意设计：模拟点击必须在不锁屏的桌面会话中进行。

**Q8：杀毒软件拦截？**
脚本是纯 PowerShell（系统自带），无第三方依赖；若被杀软误报，将脚本目录加入信任区即可。

---

# English Version

## ⚠️ Important Notice (Read First)

- This tool automates WorkBuddy's daily check-in by **simulating mouse clicks**. This is a
  **personal automation** behavior. Please confirm on your own that it complies with the
  WorkBuddy / CodeBuddy Terms of Service before using it. **Use at your own risk.**
- This tool is **for learning and personal use only**. Check-in rules, points, and rewards are
  subject to the official client.
- This tool **does NOT collect or upload any personal data** — all state and logs stay local.
- Requirements: **Windows 10/11 + Simplified Chinese OCR language pack + Windows PowerShell 5.1**
  (built into the system).
- During check-in, the tool will **briefly bring the WorkBuddy window to the foreground and
  move the mouse** — please do not use the computer at that moment.

## ✨ Features

| Feature | Description |
| --- | --- |
| Fully automatic check-in | Auto-starts WorkBuddy → finds "立即领取" (Claim Now) → clicks → polls to verify |
| Already-checked-in detection | Skips when the UI shows "今日已签到"; a state file makes all remaining runs ~0.7s no-ops |
| Done-state fallback | If the gas-station page has no claim button, it concludes "already checked in" and updates state — **no more opening WorkBuddy every hour after signing in** |
| Auto-exit | Closes WorkBuddy after check-in (only when WE started it or actually claimed; a WorkBuddy you opened yourself is never force-closed) |
| Task protection | Detects running tasks (UI keywords + window title + CPU sampling) → waits (default up to 30 min), then keeps WorkBuddy running |
| User protection | Never steals focus or force-quits while the user is actively using the PC / WorkBuddy |
| Auto-start on login | After a reboot, logs in and auto-catches-up — nothing to open manually |
| Daily schedule | Starts at 08:30 every day with hourly retries; missed triggers (off/sleep/locked) auto-run later; **runs with a hidden window, no console flash** |
| Locked-screen guard | Never clicks while the screen is locked |
| Single-instance lock | Duplicate triggers are skipped; the lock **self-heals** — a hung instance older than 45 min is killed and taken over |
| Hang protection | Every OCR call has a 15 s timeout, so the script can never hang forever |
| Full logging | Monthly logs + last-result file; on failure it dumps the first 15 OCR lines for diagnosis |
| Tray notifications | Balloon tips on success/failure (disable with -NoNotify) |
| Avatar calibration | -Calibrate to save exact avatar coordinates if the default position misses |
| Never-sleep helper | Bundled script sets all power plans to "never sleep" so the PC never misses a check-in |

## 📁 Repository Structure

```
workbuddy-checkin/
├── src/
│   ├── workbuddy-checkin.ps1     # Core check-in script (all logic)
│   ├── install-task.ps1          # One-click setup: scheduled task + startup entry
│   ├── uninstall-task.ps1        # Uninstall: supports full removal & power restore
│   └── set-never-sleep.ps1       # Power settings: never sleep / never hibernate
├── README.md                     # Bilingual docs (this file)
└── LICENSE                       # MIT License
```

Runtime files generated next to the scripts:

```
├── logs\                         # Monthly logs checkin-yyyy-MM.log (auto-cleaned after 180 days)
├── debug\                        # Debug screenshots (with -SaveScreens)
├── task-template.xml             # Scheduled-task template (generated by installer)
├── workbuddy-config.json         # Avatar coordinates (after calibration)
├── last-signin-date.txt          # Last successful check-in date (auto-maintained)
├── last-result.txt               # Last run result
├── power-change-result.txt       # Power script output
└── .checkin.lock                 # Single-instance lock (auto-maintained)
```

## 🚀 Quick Start

### 1. One-click install (once only)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\path\to\workbuddy-checkin\src\install-task.ps1"
```

The installer does two things:

1. **Registers scheduled task "WorkBuddy每日签到"**: every day from 08:30, repeating hourly
   for 16 hours; missed triggers (PC off / asleep) auto-run later (StartWhenAvailable).
2. **Creates a startup-folder VBS entry**: auto check-in at every login —
   **after a reboot you don't need to open anything**.

> If you get an "Access denied" error, run PowerShell "as administrator" once and re-run the
> installer (admin mode also registers an at-logon trigger; non-admin still works fine).

### 2. Verify immediately

```powershell
# Safety test: OCR only, no clicks
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\path\to\workbuddy-checkin\src\workbuddy-checkin.ps1" -DryRun

# Run a real check-in right now (claims today if not yet done, then auto-exits WorkBuddy)
schtasks /Run /TN "WorkBuddy每日签到"

# Show the latest result
type "C:\path\to\workbuddy-checkin\last-result.txt"
```

### 3. View logs

```powershell
type "C:\path\to\workbuddy-checkin\logs\checkin-2026-08.log"
```

## 🔄 Automatic Daily Flow

1. Triggered by the daily 08:30 scheduled task (plus hourly retries) or the login startup entry;
2. If the state file says "already checked in today" → exit immediately (~0.7 s, zero overhead);
3. Screen locked → skip safely, retried on the next full hour;
4. User actively typing/moving → wait up to 5 min, skip if still active;
5. Start WorkBuddy (if not running) → bring to foreground;
6. OCR: find "立即领取" → click → poll-verify (button gone or "claimed" text = success);
   or see "今日已签到" → skip; or click the "Buddy加油站" entry first, then check;
   if the gas-station page has no claim button → conclude already checked in;
7. Record "checked in today" → smart exit:
   - Only consider exiting when WE started WorkBuddy or actually claimed;
   - Detect tasks (UI text + window title + CPU) and user activity;
   - No task & no user activity → close WorkBuddy and exit;
   - Busy / in use → wait (default up to 30 min), then keep WorkBuddy running and exit the script.

## 🛠 Command Reference

| Purpose | Command |
| --- | --- |
| Run check-in now | `schtasks /Run /TN "WorkBuddy每日签到"` |
| Show task details | `schtasks /Query /TN "WorkBuddy每日签到" /V /FO LIST` |
| OCR only, no clicks | `workbuddy-checkin.ps1 -DryRun` |
| Check in but keep WB open (debug) | `workbuddy-checkin.ps1 -NoExit` |
| Calibrate avatar position | `workbuddy-checkin.ps1 -Calibrate` (click the bottom-left avatar when prompted) |
| Save debug screenshots | `workbuddy-checkin.ps1 -SaveScreens` (saved to debug\) |
| Strict mode (no done-fallback) | `workbuddy-checkin.ps1 -NoAssumeDone` |
| Change daily time | `install-task.ps1 -Time 09:00` |
| Regular uninstall (task + startup) | `uninstall-task.ps1` |
| Full uninstall (delete folder too) | `uninstall-task.ps1 -RemoveAll` |
| Restore power settings on uninstall | `uninstall-task.ps1 -RemoveAll -RestorePower` |
| Uninstall dry-run (no deletion) | `uninstall-task.ps1 -RemoveAll -WhatIf` |

### Uninstall Notes

Every trace this program leaves, and how the uninstaller handles it:

| Trace | Location | Handled by uninstaller? |
| --- | --- | --- |
| Scheduled task "WorkBuddy每日签到" | Task Scheduler | ✅ Auto-deleted (incl. registry cache) |
| Startup entry | Startup-folder VBS | ✅ Auto-deleted |
| Registry Run keys | Registry | Nothing to clean (this tool **never writes to the registry**) |
| Project folder (scripts/logs/state) | Script directory | Auto-deleted with `-RemoveAll` |
| Power settings (never sleep) | System power plans | Restored to defaults with `-RestorePower` (sleep 15/10 min, hibernate 3 h) |

> Note: points earned by the check-in live on the WorkBuddy server side; uninstalling this tool
> does not affect points you already earned.

## ❓ FAQ

**Q1: Check-in fails, log says "no check-in elements found"?**
- Make sure you are logged into WorkBuddy (it warns if not).
- The avatar default position is computed from the window bottom-left; if your layout differs,
  run `workbuddy-checkin.ps1 -Calibrate` once.
- Re-run with `-SaveScreens` and inspect debug\ for diagnosis.
- On failure the script dumps the first 15 OCR lines to the log automatically.

**Q2: "No Simplified Chinese OCR engine available"?**
Windows Settings → Time & Language → Language → add "简体中文" language pack (restart required).

**Q3: Button text changed after a WorkBuddy update?**
`$ClaimPattern` / `$DonePattern` / `$EntryPattern` at the top of the script are regex keywords —
edit them to match the new UI. Use `-SaveScreens` to capture what OCR sees.

**Q4: Worried about duplicate clicks?**
- Once "立即领取" is gone or "今日已签到" appears, it stops clicking;
- All remaining triggers on an already-signed day skip in ~0.7 s;
- The single-instance lock guarantees only one check-in process at a time.

**Q4b: Already signed in, but WorkBuddy keeps popping up?**
This was a v1 bug: when the gas-station page had no claim button it was treated as a "failure"
and the state file was never updated, so every hour it reopened WorkBuddy and tried again.
**Fixed in v2**: no claim button + gas-station content = "already checked in", and the state
file is updated immediately, so later hourly triggers skip without opening WorkBuddy. For a
conservative mode (risk missing a day rather than assume), use `-NoAssumeDone`.

**Q5: PC was off all day — can it catch up?**
Yes. Scheduled-task `StartWhenAvailable` + the login startup entry are a double guarantee.

**Q6: PC auto-sleeps after idle and misses check-ins?**
Handled: `set-never-sleep.ps1` sets "sleep" and "hibernate" to **Never** (AC/DC) on all power plans.

**Q7: PC has a password — can it check in while locked?**
While locked, the script **safely skips** (no clicks to avoid mis-operation); the hourly retry
catches up within an hour after you unlock. This is by design: simulated clicks need an
unlocked desktop session.

**Q8: Antivirus flags it?**
Pure PowerShell with zero third-party dependencies; if your AV false-positives, add the script
directory to the trust list.

---

## 📜 License / 开源许可

[MIT](LICENSE) © 2026 KristoffersonLee

Check-in approach inspired by the open-source projects
[dinosaurlab/workbuddy-checkin](https://github.com/dinosaurlab/workbuddy-checkin) (MIT) and
[cheyne2015/workbuddy-checkin](https://github.com/cheyne2015/workbuddy-checkin). Thanks!
签到思路参考了上述开源项目，在此致谢。

**再次提醒 / Reminder again**: 自动签到/自动退出属于个人自动化操作，请确认符合
WorkBuddy 服务条款后使用。Automated check-in / auto-exit is personal automation; make sure
it complies with the WorkBuddy Terms of Service before using it.
