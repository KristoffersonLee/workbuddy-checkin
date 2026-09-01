<#
.SYNOPSIS
    卸载 WorkBuddy 每日自动签到（v2：支持彻底卸载与电源还原）

.DESCRIPTION
    默认模式：删除计划任务「WorkBuddy每日签到」+ 启动文件夹自启项，保留脚本文件夹。

    彻底卸载（-RemoveAll）：
      删除计划任务 + 登录自启项 + 整个 wb-checkin 项目文件夹
      （脚本、日志、结果文件、状态文件、配置、锁文件、调试截图等全部删除）

    还原电源设置（-RestorePower）：
      把「睡眠/休眠」恢复为 Windows 默认值（睡眠 15分钟/10分钟、休眠 3小时），
      需要管理员权限（会自动弹出 UAC 授权，请点"是"）。

    本程序从不写入注册表（无 Run 键），因此没有注册表残留需要清理；
    删除计划任务会自动清理任务计划程序的存储与注册表缓存。

.EXAMPLE
    # 默认卸载（删任务 + 自启，保留文件夹）
    powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall-task.ps1

.EXAMPLE
    # 彻底卸载（删任务 + 自启 + 整个文件夹）
    powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall-task.ps1 -RemoveAll

.EXAMPLE
    # 彻底卸载 + 还原电源设置
    powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall-task.ps1 -RemoveAll -RestorePower

.EXAMPLE
    # 演练模式（只显示将要删除的内容，不实际删除）
    powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall-task.ps1 -RemoveAll -WhatIf
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$TaskName = "WorkBuddy每日签到",
    # 彻底卸载：同时删除整个项目文件夹
    [switch]$RemoveAll,
    # 还原电源设置（睡眠/休眠恢复默认，需要管理员）
    [switch]$RestorePower
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "=== WorkBuddy 自动签到 卸载 ===" -ForegroundColor Yellow
Write-Host ("  模式: {0}" -f ($(if ($RemoveAll) { "彻底卸载（含项目文件夹）" } else { "常规卸载（保留项目文件夹）" }))) -ForegroundColor Cyan

# ============================================================
# 1. 删除计划任务
# ============================================================
Write-Host "1) 删除计划任务 [$TaskName]..." -ForegroundColor Yellow
if ($PSCmdlet.ShouldProcess($TaskName, "删除计划任务")) {
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($task) {
        try {
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Stop
            Write-Host "  - 已删除计划任务 [$TaskName]" -ForegroundColor Green
        }
        catch {
            schtasks /Delete /F /TN $TaskName 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  - 已删除计划任务 [$TaskName]（schtasks）" -ForegroundColor Green
            }
            else {
                Write-Host "  - 删除计划任务失败: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }
    else {
        Write-Host "  - 计划任务不存在，跳过" -ForegroundColor DarkGray
    }

    # 删除锁文件
    @(".checkin.lock", ".checkin.info") | ForEach-Object {
        $p = Join-Path $PSScriptRoot $_
        if (Test-Path $p) {
            Remove-Item $p -Force -ErrorAction SilentlyContinue
        }
    }
}

# ============================================================
# 2. 删除登录自启项
# ============================================================
Write-Host "2) 删除登录自启项..." -ForegroundColor Yellow
if ($PSCmdlet.ShouldProcess("启动文件夹 VBS", "删除登录自启项")) {
    $startupDir = [Environment]::GetFolderPath("Startup")
    $vbsPath = Join-Path $startupDir "WorkBuddy自动签到.vbs"
    if (Test-Path $vbsPath) {
        Remove-Item $vbsPath -Force
        Write-Host "  - 已删除登录自启项: $vbsPath" -ForegroundColor Green
    }
    else {
        Write-Host "  - 登录自启项不存在，跳过" -ForegroundColor DarkGray
    }
}

# ============================================================
# 3. 还原电源设置（可选）
# ============================================================
if ($RestorePower) {
    Write-Host "3) 还原电源设置（睡眠/休眠恢复默认）..." -ForegroundColor Yellow
    if ($PSCmdlet.ShouldProcess("电源方案", "还原睡眠/休眠设置")) {
        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        # 还原逻辑：所有电源方案恢复 Windows 默认值（睡眠 交流900s/电池600s，休眠 10800s）
        $restoreBody = @'
$list = powercfg /list
foreach ($l in $list) {
    if ($l -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') {
        $g = $matches[1]
        powercfg /setacvalueindex $g SUB_SLEEP STANDBYIDLE 900 | Out-Null
        powercfg /setdcvalueindex $g SUB_SLEEP STANDBYIDLE 600 | Out-Null
        powercfg /setacvalueindex $g SUB_SLEEP HIBERNATEIDLE 10800 | Out-Null
        powercfg /setdcvalueindex $g SUB_SLEEP HIBERNATEIDLE 10800 | Out-Null
    }
}
powercfg /S SCHEME_CURRENT | Out-Null
'@
        $tmpScript = Join-Path $env:TEMP "wb-restore-power.ps1"
        try {
            Set-Content -Path $tmpScript -Value $restoreBody -Encoding UTF8
            if ($isAdmin) {
                & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $tmpScript
            }
            else {
                Write-Host "  - 需要管理员权限，正在请求 UAC 授权..." -ForegroundColor Yellow
                Start-Process -FilePath "powershell.exe" -Verb RunAs -Wait `
                    -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $tmpScript) | Out-Null
            }
            Write-Host "  - 已还原电源设置（睡眠: 交流15分钟/电池10分钟，休眠: 3小时）" -ForegroundColor Green
        }
        catch {
            Write-Host "  - 还原电源设置失败或 UAC 被取消: $($_.Exception.Message)" -ForegroundColor Red
        }
        finally {
            Remove-Item $tmpScript -Force -ErrorAction SilentlyContinue
        }
    }
}

# ============================================================
# 4. 彻底删除项目文件夹（可选）
# ============================================================
if ($RemoveAll) {
    Write-Host "4) 删除项目文件夹..." -ForegroundColor Yellow
    $dir = $PSScriptRoot
    if ($PSCmdlet.ShouldProcess($dir, "彻底删除项目文件夹")) {
        # 先删除文件夹内除本脚本外的所有内容
        Get-ChildItem $dir -Force | Where-Object { $_.Name -ne "uninstall-task.ps1" } | ForEach-Object {
            try {
                Remove-Item $_.FullName -Recurse -Force -ErrorAction Stop
                Write-Host "  - 已删除: $($_.Name)" -ForegroundColor Green
            }
            catch {
                Write-Host "  - 删除失败（可能被占用）: $($_.Name) - $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        # 延迟删除自身与文件夹（等本 PowerShell 进程退出后，cmd 循环重试直到成功）
        if (Test-Path $dir) {
            $file = Join-Path $dir "uninstall-task.ps1"
            $cmdLine = 'timeout /t 3 /nobreak >nul 2>&1 & ":loop" & del "' + $file + '" >nul 2>&1 & if exist "' + $file + '" (timeout /t 1 & goto loop) & rd /s /q "' + $dir + '"'
            Start-Process cmd.exe -ArgumentList "/c", $cmdLine -WindowStyle Hidden | Out-Null
            Write-Host "  - 项目文件夹将在进程退出后自动删除: $dir" -ForegroundColor Green
        }
        Write-Host ""
        Write-Host "✔ 彻底卸载完成：计划任务、登录自启、项目文件夹均已清除。" -ForegroundColor Green
        Write-Host "  注：自动签到的每日记录（积分）在 WorkBuddy 服务器端，卸载本程序不影响已获取的积分。" -ForegroundColor DarkGray
    }
}
else {
    Write-Host ""
    Write-Host "✔ 卸载完成。签到脚本与日志保留在: $PSScriptRoot" -ForegroundColor Green
    Write-Host "  如需彻底删除（含脚本、日志、结果文件等），请运行:" -ForegroundColor Cyan
    Write-Host ("    powershell -NoProfile -ExecutionPolicy Bypass -File `"{0}`" -RemoveAll" -f (Join-Path $PSScriptRoot 'uninstall-task.ps1')) -ForegroundColor Cyan
    if (-not $RestorePower) {
        Write-Host "  如需同时还原电源设置（恢复自动睡眠），请加 -RestorePower 参数" -ForegroundColor Cyan
    }
}
Write-Host ""
