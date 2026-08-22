<#
.SYNOPSIS
    将 Windows 电源设置改为「永不休眠、永不休眠」（所有电源方案）

.DESCRIPTION
    遍历所有电源方案，将「在此时间后睡眠」和「在此时间后休眠」的
    交流/直流值全部设为 0（从不），保证 WorkBuddy 每日自动签到不会因
    电脑睡眠而错过触发时间。

    需要管理员权限运行（本脚本会以管理员方式自动运行，出现 UAC 提示时请点“是”）。

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\set-never-sleep.ps1
#>
$ErrorActionPreference = "Stop"

$resultFile = Join-Path $PSScriptRoot "power-change-result.txt"
$out = New-Object System.Collections.ArrayList
function Log {
    param([string]$Msg)
    [void]$out.Add($Msg)
    Write-Host $Msg
}

# ---------- 检查管理员权限 ----------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    # 以管理员方式重新启动自己
    try {
        Start-Process -FilePath "powershell.exe" -Verb RunAs `
            -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$($MyInvocation.MyCommand.Path)`"") -Wait
        exit 0
    }
    catch {
        Write-Host "需要管理员权限，但 UAC 授权被取消或失败: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

Log "=== 修改电源设置：永不休眠 / 永不休眠 ==="

# ---------- 获取所有电源方案 GUID ----------
$list = powercfg /list
$guids = @()
$activeGuid = ""
foreach ($line in $list) {
    if ($line -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') {
        $guids += $matches[1]
        if ($line -match '\*') { $activeGuid = $matches[1] }
    }
}

if ($guids.Count -eq 0) {
    Log "错误：未找到任何电源方案！"
    $out | Set-Content -Path $resultFile -Encoding UTF8
    exit 1
}

foreach ($guid in $guids) {
    Log "处理电源方案: $guid"
    powercfg /setacvalueindex $guid SUB_SLEEP STANDBYIDLE 0 | Out-Null
    powercfg /setdcvalueindex $guid SUB_SLEEP STANDBYIDLE 0 | Out-Null
    powercfg /setacvalueindex $guid SUB_SLEEP HIBERNATEIDLE 0 | Out-Null
    powercfg /setdcvalueindex $guid SUB_SLEEP HIBERNATEIDLE 0 | Out-Null
}

# 重新应用当前方案，使设置立即生效
if ($activeGuid) {
    powercfg /S $activeGuid | Out-Null
    Log "已重新应用当前电源方案: $activeGuid"
}

# ---------- 验证 ----------
Log ""
Log "=== 验证结果 ==="
foreach ($guid in $guids) {
    $q = powercfg /q $guid SUB_SLEEP STANDBYIDLE
    $q2 = powercfg /q $guid SUB_SLEEP HIBERNATEIDLE
    $acSleep = ($q | Select-String "当前交流电源设置索引").ToString().Trim()
    $dcSleep = ($q | Select-String "当前直流电源设置索引").ToString().Trim()
    $acHib = ($q2 | Select-String "当前交流电源设置索引").ToString().Trim()
    $dcHib = ($q2 | Select-String "当前直流电源设置索引").ToString().Trim()
    Log "方案 $guid :"
    Log "  $acSleep"
    Log "  $dcSleep"
    Log "  $acHib"
    Log "  $dcHib"
}

$ok = $true
foreach ($guid in $guids) {
    foreach ($pair in @(@("$guid", "SUB_SLEEP", "STANDBYIDLE"), @("$guid", "SUB_SLEEP", "HIBERNATEIDLE"))) {
        $q = powercfg /q $pair[0] $pair[1] $pair[2]
        foreach ($idx in ($q | Select-String "当前.*电源设置索引")) {
            if ($idx.ToString() -notmatch "0x00000000") { $ok = $false }
        }
    }
}

Log ""
if ($ok) {
    Log "✔ 设置成功：所有电源方案均为「永不休眠、永不休眠」（交流/直流）"
    Log "  现在电脑将一直保持运行状态，WorkBuddy 每日签到可按时自动执行。"
}
else {
    Log "✘ 仍有部分设置不为 0，请检查上方输出。"
}

$out | Set-Content -Path $resultFile -Encoding UTF8
exit 0
