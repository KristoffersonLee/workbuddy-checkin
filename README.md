# WorkBuddy 每日自动签到（全自动 · 含智能自动退出）

> **GitHub 开源地址（含中英双语文档与 Release）**：https://github.com/KristoffersonLee/workbuddy-checkin

一个**完全免费、无需安装任何第三方库**的 Windows 自动化方案：每天自动打开
WorkBuddy，完成「Buddy 加油站」每日签到领积分，签到完成后**自动退出 WorkBuddy 和脚本**；
若检测到 WorkBuddy 正在执行任务或用户正在使用，则**不会强退**。

实现原理：截屏 + Windows 自带中文 OCR 识别界面文字 + 模拟鼠标点击。

---

## 功能特性

| 功能 | 说明 |
| --- | --- |
| 全自动签到 | 自动启动 WorkBuddy → 识别「立即领取」→ 点击签到 → 轮询验证成功 |
| 已签到检测 | 界面显示「今日已签到」时不重复点击；状态文件记录，当日其余时间零开销跳过（约 0.7 秒） |
| 已签到判定兜底 | 打开加油站页面后找不到「立即领取」→ 判定今日已签到并更新状态，**杜绝"已签到却每小时反复打开 WorkBuddy"** |
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

---

## 目录结构

```
wb-checkin\
├── workbuddy-checkin.ps1     # 核心签到脚本（全部逻辑）
├── install-task.ps1          # 一键安装：计划任务 + 登录自启
├── uninstall-task.ps1        # 一键卸载：删除计划任务 + 自启项
├── set-never-sleep.ps1       # 电源设置：永不休眠/永不休眠（防睡眠错过签到）
├── task-template.xml         # 计划任务模板（安装时自动生成）
├── workbuddy-config.json     # 头像坐标（校准后生成）
├── last-signin-date.txt      # 最近成功签到日期（自动维护）
├── last-result.txt           # 最近一次运行结果（快速查看）
├── logs\                     # 月度日志 checkin-yyyy-MM.log（自动清理 180 天前的）
└── debug\                    # 调试截图（-SaveScreens 时生成）
```

---

## 快速开始

### 1. 一键安装（只需一次）

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\20183\Desktop\wb-checkin\install-task.ps1"
```

安装脚本自动完成两件事：

1. **注册计划任务「WorkBuddy每日签到」**：每天 08:30 起，每小时重复 16 小时；
   错过触发时间（关机/睡眠）后自动补跑（StartWhenAvailable）。
2. **创建登录自启项**（启动文件夹 VBS）：每次登录 Windows 自动补签，
   **重启后无需手动打开任何东西**。

> 若系统提示权限不足，右键“以管理员身份运行”PowerShell 再执行一次即可
> （管理员模式下会额外注册“登录时触发”，非管理员也能正常使用）。

### 2. 立即验证

```powershell
# 只识别不点击（安全测试，确认 OCR 与界面识别正常）
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\20183\Desktop\wb-checkin\workbuddy-checkin.ps1" -DryRun

# 立即真实签到一次（当天未签时执行，签完自动退出 WorkBuddy）
schtasks /Run /TN "WorkBuddy每日签到"

# 查看最近一次结果
type "C:\Users\20183\Desktop\wb-checkin\last-result.txt"
```

### 3. 查看日志

```powershell
type "C:\Users\20183\Desktop\wb-checkin\logs\checkin-2026-08.log"
```

---

## 日常运行流程（自动）

1. 每天 08:30（及每小时重试）计划任务触发，或每次登录时自启项触发；
2. 脚本检查：若状态文件显示今日已签到 → 立即退出（零开销）；
3. 屏幕锁定 → 跳过本次（避免误操作），下个整点自动重试；
4. 若用户正在操作电脑（键盘/鼠标活跃）→ 等待最多 5 分钟，仍活跃则本次跳过；
5. 启动 WorkBuddy（如未运行）→ 置前显示；
6. OCR 识别：找「立即领取」→ 点击 → 验证「领取成功/按钮消失」；
   或识别「今日已签到」→ 直接跳过；或点击「Buddy加油站」入口进入后再识别；
7. 记录今日已签到 → 进入智能退出：
   - 检测任务（界面文字「正在执行/生成中/运行中…」+ 窗口标题 + CPU 采样）
   - 检测用户活动（WorkBuddy 在前台且有近期输入）
   - 无任务且无用户操作 → **自动关闭 WorkBuddy，脚本退出**
   - 有任务/用户在使用 → 等待（默认最多 30 分钟），超时保留 WB 运行、仅退出脚本

---

## 常用命令速查

| 用途 | 命令 |
| --- | --- |
| 立即签到一次 | `schtasks /Run /TN "WorkBuddy每日签到"` |
| 查看任务详情 | `schtasks /Query /TN "WorkBuddy每日签到" /V /FO LIST` |
| 只识别不点击 | `workbuddy-checkin.ps1 -DryRun` |
| 签到但不退出 WB（调试） | `workbuddy-checkin.ps1 -NoExit` |
| 校准头像坐标 | `workbuddy-checkin.ps1 -Calibrate`（按提示点击一次左下角头像） |
| 保存调试截图 | `workbuddy-checkin.ps1 -SaveScreens`（截图存 debug\） |
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
| 项目文件夹（脚本/日志/结果/状态文件） | `wb-checkin\` | 加 `-RemoveAll` 后自动删除 |
| 电源设置（永不休眠） | 系统电源方案 | 加 `-RestorePower` 恢复默认（睡眠 15/10 分钟、休眠 3 小时） |

> 说明：自动签到积累的积分保存在 WorkBuddy 服务器端，卸载本程序不影响已获取的积分。

---

## 常见问题

**Q1：签到失败，日志提示“未识别到签到相关元素”？**
- 确认 WorkBuddy 已登录账号（未登录会提示）。
- 头像默认位置按窗口左下角计算，若界面布局不同，运行一次
  `workbuddy-checkin.ps1 -Calibrate` 校准。
- 加 `-SaveScreens` 重跑，查看 debug\ 下的截图定位问题。

**Q2：提示“系统没有可用的简体中文 OCR 引擎”？**
Windows 设置 → 时间和语言 → 语言 → 添加“简体中文”语言包即可（重启生效）。

**Q3：WorkBuddy 升级后按钮文字变了？**
脚本顶部的 `$ClaimPattern` / `$DonePattern` / `$EntryPattern` 是正则关键词，
按新界面文字修改即可；OCR 无法识别时用 `-SaveScreens` 截图对照。

**Q4：担心重复签到/点错？**
- 「立即领取」按钮消失或出现「今日已签到」即不再点击；
- 已签到当日，后续所有触发都直接跳过（约 0.7 秒）；
- 单实例锁保证同一时刻只有一个签到进程。

**Q4b：明明已签到，却时不时弹出 WorkBuddy？**
这是 v1 的一个缺陷：打开加油站页面后找不到「立即领取」时被当作"失败"，
状态文件不更新，于是每小时都重新打开 WorkBuddy 反复尝试。
v2 已修复：找不到领取按钮且界面为加油站/积分内容时，判定「今日已签到」
并立即更新状态文件，后续每小时触发直接跳过、不再打开 WorkBuddy。
若想保守处理（宁可漏签也不误判），可用 `-NoAssumeDone` 参数。

**Q5：电脑关机了一整天，还能补签吗？**
能。计划任务 `StartWhenAvailable` + 登录自启项双保险：开机登录后会自动补跑。

**Q6：电脑空闲太久会自动睡眠，导致错过签到？**
已处理：`set-never-sleep.ps1` 已将**所有电源方案**的「睡眠」和「休眠」都设为
**从不**（交流/直流），电脑会保持运行状态。若日后发现设置被还原，重新运行：
`powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\20183\Desktop\wb-checkin\set-never-sleep.ps1"`
（会弹出 UAC 授权窗口，点“是”即可）。

**Q7：电脑有密码，锁屏时能签到吗？**
锁屏时脚本会**安全跳过**（不做任何点击，防止误操作），解锁后 1 小时内由
每小时重试自动补签。这是有意设计：模拟点击必须在不锁屏的桌面会话中进行。

**Q8：杀毒软件拦截？**
脚本是纯 PowerShell（系统自带），无第三方依赖；若被杀软误报，将
`wb-checkin` 目录加入信任区即可。

---

## 注意事项

- 自动签到/自动退出属于个人自动化操作，请确认符合 WorkBuddy 服务条款后使用；
- 脚本会模拟鼠标点击并可能短暂将 WorkBuddy 窗口置于前台；
- 锁屏/睡眠期间不会执行点击（安全设计）；
- 用户正在使用电脑或 WorkBuddy 有任务时，脚本宁可跳过也**不会强退**。

---

## 技术要点

- 仅依赖：Windows 10/11 + 简体中文 OCR 语言包 + Windows PowerShell 5.1（系统自带）；
- 脚本自动检测：若用 PowerShell Core(pwsh) 运行会自动切换到 Windows PowerShell 5.1；
- 关键文件编码为 **UTF-8 with BOM**（PowerShell 5.1 依赖 BOM 正确解析中文，请勿改成无 BOM）；
- 日志按月度轮转，180 天前的自动清理；
- 计划任务以**隐藏窗口**运行（`-WindowStyle Hidden`），每小时触发不再有黑框闪烁；
- 单实例锁带时间戳自愈：正常流程严格小于 45 分钟（启动 90s + 空闲等待 300s + 领取验证 60s + 繁忙等待 30min），
  因此持有锁超过 45 分钟的实例必为卡死，会被自动终止并接管，不会阻塞后续签到。

## v2 变更记录

- 修复：已签到状态识别（找不到领取按钮 → 判定已签到并更新状态），停止每小时反复打开 WorkBuddy
- 修复：领取点击验证改为轮询（最多 20 秒 × 3 次点击），消除"点击成功却误判失败"
- 修复：DryRun 模式不再执行任何点击
- 优化：状态文件检查前置，已签到日零开销（不再初始化 OCR / 启动 WorkBuddy）
- 优化：任务隐藏窗口运行，无控制台闪烁
- 优化：点击坐标自动钳制到屏幕内，窗口最小化/异常时先恢复再测量
- 优化：失败时输出屏幕 OCR 前 15 行文本，便于定位问题
- 优化：不再强关用户自己打开的 WorkBuddy（仅关闭本脚本启动的或执行了领取的）
- 新增：OCR 超时保护（15 秒/次），防止脚本挂死
- 新增：锁文件自愈（终止卡死实例并接管）
