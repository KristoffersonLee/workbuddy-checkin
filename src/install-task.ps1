<#
.SYNOPSIS
    安装 WorkBuddy 每日自动签到（计划任务 + 开机自启，一次搞定）

.DESCRIPTION
    本脚本完成两件事：
      1. 注册 Windows 计划任务「WorkBuddy每日签到」：
         每天 $Time 起，每小时重复一次直到当天结束（错过也能补签；
         脚本内部有“今日已签到”状态判断，重复运行几乎零开销）
         自动检测权限：管理员时额外注册“登录时触发”；非管理员时使用 schtasks/XML。
      2. 在启动文件夹创建 VBS 自启项（登录时自动运行签到脚本）：
         电脑重启/开机后无需手动打开任何东西，登录即自动补签。
         与计划任务互为备份，配合脚本内单实例锁，重复运行无副作用。

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\install-task.ps1

.EXAMPLE
    # 指定每天 09:00 开始
    powershell -NoProfile -ExecutionPolicy Bypass -File .\install-task.ps1 -Time 09:00
#>
[CmdletBinding()]
param(
    # 每天开始签到的时间，24 小时制 HH:mm
    [string]$Time = "08:30",
    # 计划任务名称
    [string]$TaskName = "WorkBuddy每日签到",
    # 签到脚本路径（留空则自动定位到本脚本同目录）
    [string]$ScriptPath = "",
    # 从 $Time 起每小时重复的小时数（覆盖到当天结束）
    [int]$RepeatHours = 16,
    # 跳过创建启动文件夹自启项
    [switch]$SkipStartupVbs
)

$ErrorActionPreference = "Stop"

if (-not $ScriptPath) {
    $ScriptPath = Join-Path $PSScriptRoot "workbuddy-checkin.ps1"
}
if (-not (Test-Path $ScriptPath)) {
    throw "找不到签到脚本: $ScriptPath"
}

function Write-Step {
    param([string]$Msg)
    Write-Host ("  - " + $Msg) -ForegroundColor Cyan
}

Write-Host ""
Write-Host "=== WorkBuddy 每日自动签到 安装 ===" -ForegroundColor Green

# ============================================================
# 1. 计划任务
# ============================================================
Write-Host "1) 注册计划任务 [$TaskName]..." -ForegroundColor Yellow
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$taskOk = $false

if ($isAdmin) {
    # 管理员：使用 Register-ScheduledTask（可注册“登录时触发”）
    try {
        $action = New-ScheduledTaskAction -Execute "powershell.exe" `
            -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptPath`""
        $logon = New-ScheduledTaskTrigger -AtLogOn
        $daily = New-ScheduledTaskTrigger -Daily -At $Time
        $rep = New-ScheduledTaskTrigger -Once -At $Time `
            -RepetitionInterval (New-TimeSpan -Hours 1) `
            -RepetitionDuration (New-TimeSpan -Hours $RepeatHours)
        $daily.Repetition = $rep.Repetition
        $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -WakeToRun `
            -ExecutionTimeLimit (New-TimeSpan -Minutes 30) `
            -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew
        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger @($logon, $daily) `
            -Settings $settings -Description "WorkBuddy 每日自动签到（脚本: $ScriptPath）" -Force | Out-Null
        Write-Step "管理员模式注册成功（登录时触发 + 每天 $Time 起每小时重复 + 唤醒执行）"
        $taskOk = $true
    }
    catch {
        Write-Step ("Register-ScheduledTask 失败: " + $_.Exception.Message)
    }
}

if (-not $taskOk) {
    # 非管理员（或管理员注册失败）：schtasks + XML（每日 + 每小时重复）
    $user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $escapedPath = $ScriptPath.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;")
    $startBoundary = "{0:yyyy-MM-dd}T{1}:00" -f (Get-Date), $Time
    $xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>WorkBuddy 每日自动签到（每天 $Time 起每小时检查）</Description>
    <Author>$user</Author>
  </RegistrationInfo>
  <Triggers>
    <CalendarTrigger>
      <StartBoundary>$startBoundary</StartBoundary>
      <Enabled>true</Enabled>
      <ScheduleByDay>
        <DaysInterval>1</DaysInterval>
      </ScheduleByDay>
      <Repetition>
        <Interval>PT1H</Interval>
        <Duration>PT${RepeatHours}H</Duration>
        <StopAtDurationEnd>false</StopAtDurationEnd>
      </Repetition>
    </CalendarTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>$user</UserId>
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <ExecutionTimeLimit>PT30M</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>powershell.exe</Command>
      <Arguments>-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "$escapedPath"</Arguments>
    </Exec>
  </Actions>
</Task>
"@
    $xmlPath = Join-Path $PSScriptRoot "task-template.xml"
    [System.IO.File]::WriteAllText($xmlPath, $xml, (New-Object System.Text.UnicodeEncoding($false, $true)))
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    schtasks /Create /F /TN $TaskName /XML $xmlPath 2>&1 | Out-Null
    $taskCreateCode = $LASTEXITCODE
    $ErrorActionPreference = $prevEAP
    if ($taskCreateCode -eq 0) {
        Write-Step "计划任务注册成功（每天 $Time 起每小时重复 $RepeatHours 小时，错过自动补跑）"
        $taskOk = $true
    }
    else {
        Write-Step "计划任务注册失败（权限不足？），请尝试右键「以管理员身份运行」本安装脚本"
        Write-Step "提示：即使任务注册失败，启动文件夹自启项仍可保证登录时自动签到"
    }
}

# ============================================================
# 2. 启动文件夹自启项（登录时自动运行）
# ============================================================
if (-not $SkipStartupVbs) {
    Write-Host "2) 创建登录自启项..." -ForegroundColor Yellow
    $startupDir = [Environment]::GetFolderPath("Startup")
    $vbsPath = Join-Path $startupDir "WorkBuddy自动签到.vbs"
    $vbs = @"
' WorkBuddy 每日自动签到 - 登录时自动运行（隐藏窗口，无闪烁）
' 脚本内有单实例锁 + 今日已签到状态判断，重复运行零开销
On Error Resume Next
CreateObject("WScript.Shell").Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""$ScriptPath""", 0, False
"@
    [System.IO.File]::WriteAllText($vbsPath, $vbs, (New-Object System.Text.UTF8Encoding($false)))
    if (Test-Path $vbsPath) {
        Write-Step "已创建登录自启项: $vbsPath"
        Write-Step "效果：电脑重启后登录 Windows 即自动补签，无需手动打开任何东西"
    }
    else {
        Write-Step "创建自启项失败（无法写入启动文件夹？）"
    }
}
else {
    Write-Host "2) 跳过启动文件夹自启项（-SkipStartupVbs）" -ForegroundColor Yellow
}

# ============================================================
# 3. 总结
# ============================================================
Write-Host ""
Write-Host "✔ 安装完成" -ForegroundColor Green
Write-Host "  签到脚本 : $ScriptPath"
Write-Host "  计划任务 : [$TaskName]，每天 $Time 起，每小时重复 $RepeatHours 小时"
Write-Host "  登录自启 : 已配置（登录即自动补签）"
Write-Host ""
Write-Host "常用命令:" -ForegroundColor Cyan
Write-Host ("  查看任务     : schtasks /Query /TN `"{0}`" /V /FO LIST" -f $TaskName) -ForegroundColor Cyan
Write-Host ("  立即运行一次 : schtasks /Run /TN `"{0}`"" -f $TaskName) -ForegroundColor Cyan
Write-Host "  卸载         : powershell -NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $PSScriptRoot 'uninstall-task.ps1')`"" -ForegroundColor Cyan
Write-Host ""
