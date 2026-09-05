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

# ============================================================
# 交互式选择卸载模式（仅在未显式传入 -RemoveAll 时弹出）
# ============================================================
if (-not $PSBoundParameters.ContainsKey('RemoveAll')) {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing

        $font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10)
        $fontBold = New-Object System.Drawing.Font('Microsoft YaHei UI', 10, [System.Drawing.FontStyle]::Bold)

        $form = New-Object System.Windows.Forms.Form
        $form.Text = '选择卸载模式'
        $form.Size = New-Object System.Drawing.Size(480, 320)
        $form.StartPosition = 'CenterScreen'
        $form.FormBorderStyle = 'FixedDialog'
        $form.MaximizeBox = $false
        $form.MinimizeBox = $false
        $form.Font = $font
        $form.BackColor = [System.Drawing.Color]::White

        $lblTitle = New-Object System.Windows.Forms.Label
        $lblTitle.Text = '请选择卸载方式'
        $lblTitle.Font = $fontBold
        $lblTitle.AutoSize = $true
        $lblTitle.Location = New-Object System.Drawing.Point(20, 18)
        $form.Controls.Add($lblTitle)

        $lblDesc = New-Object System.Windows.Forms.Label
        $lblDesc.Text = '常规卸载仅删除计划任务和登录自启项，脚本文件保留。'
        $lblDesc.AutoSize = $true
        $lblDesc.Location = New-Object System.Drawing.Point(20, 50)
        $lblDesc.ForeColor = [System.Drawing.Color]::Gray
        $form.Controls.Add($lblDesc)

        $rbRegular = New-Object System.Windows.Forms.RadioButton
        $rbRegular.Text = '常规卸载（保留脚本文件夹）'
        $rbRegular.Location = New-Object System.Drawing.Point(30, 85)
        $rbRegular.Size = New-Object System.Drawing.Size(400, 26)
        $rbRegular.Checked = $true
        $form.Controls.Add($rbRegular)

        $lblRegular = New-Object System.Windows.Forms.Label
        $lblRegular.Text = '仅删除计划任务与启动项，脚本/日志/结果文件保留在本地。'
        $lblRegular.AutoSize = $true
        $lblRegular.Location = New-Object System.Drawing.Point(50, 112)
        $lblRegular.ForeColor = [System.Drawing.Color]::Gray
        $lblRegular.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
        $form.Controls.Add($lblRegular)

        $rbFull = New-Object System.Windows.Forms.RadioButton
        $rbFull.Text = '完整卸载（删除脚本文件夹及所有文件）'
        $rbFull.Location = New-Object System.Drawing.Point(30, 145)
        $rbFull.Size = New-Object System.Drawing.Size(400, 26)
        $form.Controls.Add($rbFull)

        $lblFull = New-Object System.Windows.Forms.Label
        $lblFull.Text = '彻底删除整个项目文件夹（脚本、日志、结果、配置等全部清除）。'
        $lblFull.AutoSize = $true
        $lblFull.Location = New-Object System.Drawing.Point(50, 172)
        $lblFull.ForeColor = [System.Drawing.Color]::Gray
        $lblFull.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
        $form.Controls.Add($lblFull)

        $btnOk = New-Object System.Windows.Forms.Button
        $btnOk.Text = '确认卸载'
        $btnOk.Size = New-Object System.Drawing.Size(120, 36)
        $btnOk.Location = New-Object System.Drawing.Point(210, 220)
        $btnOk.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 212)
        $btnOk.ForeColor = [System.Drawing.Color]::White
        $btnOk.FlatStyle = 'Flat'
        $btnOk.Font = $fontBold
        $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $form.AcceptButton = $btnOk
        $form.Controls.Add($btnOk)

        $btnCancel = New-Object System.Windows.Forms.Button
        $btnCancel.Text = '取消'
        $btnCancel.Size = New-Object System.Drawing.Size(100, 36)
        $btnCancel.Location = New-Object System.Drawing.Point(340, 220)
        $btnCancel.FlatStyle = 'Flat'
        $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $form.CancelButton = $btnCancel
        $form.Controls.Add($btnCancel)

        $result = $form.ShowDialog()
        $form.Dispose()

        if ($result -ne [System.Windows.Forms.DialogResult]::OK) {
            Write-Host ""
            Write-Host "已取消卸载。" -ForegroundColor Yellow
            exit 0
        }

        $RemoveAll = $rbFull.Checked
        $font.Dispose()
        $fontBold.Dispose()
    }
    catch {
        # 对话框失败时回退到命令行选择
        Write-Host ""
        Write-Host "请选择卸载模式:" -ForegroundColor Yellow
        Write-Host "  1) 常规卸载（保留脚本文件夹）" -ForegroundColor Cyan
        Write-Host "  2) 完整卸载（删除脚本文件夹及所有文件）" -ForegroundColor Cyan
        $choice = Read-Host "请输入数字 (1 或 2，默认 1)"
        if ($choice -eq '2') { $RemoveAll = $true }
    }
}

# 选择是否还原电源设置（仅在完整卸载且未显式指定 -RestorePower 时询问）
if ($RemoveAll -and -not $PSBoundParameters.ContainsKey('RestorePower')) {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $result = [System.Windows.Forms.MessageBox]::Show(
            '是否同时还原电源设置？' + "`n`n" +
            '点击「是」：恢复 Windows 默认睡眠/休眠设置（睡眠 15/10 分钟、休眠 3 小时）' + "`n" +
            '点击「否」：保持当前的「永不休眠」设置',
            '还原电源设置',
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($result -eq [System.Windows.Forms.DialogResult]::Yes) { $RestorePower = $true }
    }
    catch {
        Write-Host ""
        $choice = Read-Host "是否还原电源设置（恢复自动睡眠）？(y/N)"
        if ($choice -match '^[yY]') { $RestorePower = $true }
    }
}

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
