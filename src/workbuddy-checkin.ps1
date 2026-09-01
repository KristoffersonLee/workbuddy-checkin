<#
.SYNOPSIS
    WorkBuddy 每日自动签到 + 智能自动退出（v2 优化版）

.DESCRIPTION
    自动打开 WorkBuddy 的「Buddy 加油站」入口，使用 Windows 自带 OCR 识别界面文字，
    定位「立即领取」按钮并模拟点击，完成每日签到领积分。

    v2 主要优化：
      - 已签到识别更可靠：打开加油站页面后若找不到领取按钮，判定为「今日已签到」
        并记录状态，杜绝"已签到却每小时反复打开 WorkBuddy"的问题
      - 领取点击后轮询验证（最多 20 秒），不再单次 3 秒误判
      - 点击坐标自动钳制到屏幕范围内；窗口最小化/异常时先恢复再测量
      - OCR 每次调用带 15 秒超时保护，避免挂死
      - 锁文件带时间戳自愈：卡死的旧实例超过 45 分钟后自动接管
      - 状态文件检查前置：已签到日零开销跳过（不初始化 OCR、不启动 WorkBuddy）
      - 失败时自动输出屏幕 OCR 文本前 15 行，方便诊断
      - 只有「本脚本启动的 WorkBuddy」或「实际执行了领取」才自动退出 WorkBuddy，
        用户自己打开的 WorkBuddy 不会被强关

.EXAMPLE
    # 只识别不点击（测试）
    powershell -NoProfile -ExecutionPolicy Bypass -File .\workbuddy-checkin.ps1 -DryRun

.EXAMPLE
    # 正常签到（签到后自动退出 WorkBuddy 与脚本）
    powershell -NoProfile -ExecutionPolicy Bypass -File .\workbuddy-checkin.ps1

.EXAMPLE
    # 校准头像坐标（按提示点击一次左下角头像）
    powershell -NoProfile -ExecutionPolicy Bypass -File .\workbuddy-checkin.ps1 -Calibrate

.NOTES
    依赖：Windows 10/11 + 简体中文 OCR 语言包 + Windows PowerShell 5.1（系统自带）
    注意：自动签到/自动退出属于个人自动化操作，请确认符合 WorkBuddy 服务条款。
#>
[CmdletBinding()]
param(
    # WorkBuddy 主程序路径（留空则自动检测）
    [string]$WorkBuddyExe = "",
    # 日志文件路径（默认 logs\checkin-yyyy-MM.log）
    [string]$LogFile = "",
    # 头像坐标配置文件（校准后保存，默认脚本同目录）
    [string]$ConfigFile = "",
    # 状态文件（记录最近一次成功签到日期，默认脚本同目录）
    [string]$StateFile = "",
    # 启动 WorkBuddy 后等待主窗口出现的秒数
    [int]$StartupTimeoutSec = 90,
    # 只识别不点击，用于测试
    [switch]$DryRun,
    # 保存调试截图到脚本同目录 debug\ 下
    [switch]$SaveScreens,
    # 校准模式：点击一次 WorkBuddy 左下角用户头像，保存坐标后退出
    [switch]$Calibrate,
    # 签到完成后不退出 WorkBuddy（调试用）
    [switch]$NoExit,
    # 不显示托盘气泡通知
    [switch]$NoNotify,
    # 严格模式：打开加油站页面后找不到领取按钮时不假设"已签到"（可能漏签当日）
    [switch]$NoAssumeDone,
    # 头像点击重试轮数（v2 默认 1 轮，头像不再是主要入口）
    [int]$MaxAvatarRounds = 1,
    # 检测到任务/用户使用时最多等待的分钟数，超时则保留 WorkBuddy 运行
    [int]$TaskWaitMin = 30,
    # WorkBuddy 进程 CPU 占用（占整机百分比）超过该值视为"正在执行任务"
    [int]$CpuBusyThreshold = 25,
    # 距上次键盘鼠标输入多少秒内、且 WorkBuddy 在前台，视为"用户正在使用"
    [int]$UserActiveSec = 180,
    # 日志保留天数
    [int]$LogKeepDays = 180,
    # 点击领取后的验证轮询总时长（秒）
    [int]$ClaimVerifySec = 20
)

$ErrorActionPreference = "Stop"

# ============================================================
# 0. 若运行在 PowerShell Core(pwsh) 下，自动切换到 Windows PowerShell 5.1
# ============================================================
if ($PSVersionTable.PSEdition -eq "Core") {
    $ps51 = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
    if (-not (Test-Path $ps51)) {
        Write-Host "错误：找不到 Windows PowerShell 5.1（$ps51），无法执行 OCR 签到。" -ForegroundColor Red
        exit 1
    }
    $innerArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $MyInvocation.MyCommand.Path)
    foreach ($k in $PSBoundParameters.Keys) {
        $v = $PSBoundParameters[$k]
        if ($v -is [switch]) {
            if ($v) { $innerArgs += "-$k" }
        }
        else {
            $innerArgs += "-$k"
            $innerArgs += [string]$v
        }
    }
    $p = Start-Process -FilePath $ps51 -ArgumentList $innerArgs -Wait -PassThru -WindowStyle Hidden
    exit $p.ExitCode
}

# ============================================================
# 1. 路径与日志
# ============================================================
if (-not $WorkBuddyExe) {
    $candidates = @(
        "D:\WorkBuddy\WorkBuddy.exe",
        (Join-Path $env:LOCALAPPDATA "Programs\WorkBuddy\WorkBuddy.exe"),
        (Join-Path $env:PROGRAMFILES "WorkBuddy\WorkBuddy.exe")
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { $WorkBuddyExe = $c; break }
    }
}

$LogDir = Join-Path $PSScriptRoot "logs"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
if (-not $LogFile) {
    $LogFile = Join-Path $LogDir ("checkin-{0}.log" -f (Get-Date -Format "yyyy-MM"))
}
if (-not $ConfigFile) {
    $ConfigFile = Join-Path $PSScriptRoot "workbuddy-config.json"
}
if (-not $StateFile) {
    $StateFile = Join-Path $PSScriptRoot "last-signin-date.txt"
}
$DebugDir = Join-Path $PSScriptRoot "debug"
if ($SaveScreens -and -not (Test-Path $DebugDir)) {
    New-Item -ItemType Directory -Path $DebugDir -Force | Out-Null
}
# 清理过期日志与调试截图
Get-ChildItem $LogDir -Filter "checkin-*.log" -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$LogKeepDays) } |
    Remove-Item -Force -ErrorAction SilentlyContinue
Get-ChildItem $DebugDir -Filter "*.png" -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } |
    Remove-Item -Force -ErrorAction SilentlyContinue
# 清理崩溃残留的临时截图
Get-ChildItem $env:TEMP -Filter "wb-checkin-*.png" -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-1) } |
    Remove-Item -Force -ErrorAction SilentlyContinue

# ============================================================
# 2. Win32 API
# ============================================================
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WbWin32 {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern int GetSystemMetrics(int nIndex);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, int dx, int dy, uint dwData, int dwExtraInfo);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT lpPoint);
    [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vKey);
    [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
    [DllImport("user32.dll")] public static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder lpString, int nMaxCount);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; }
    [StructLayout(LayoutKind.Sequential)] public struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
}
"@

[void][WbWin32]::SetProcessDPIAware()

# ============================================================
# 3. 通用工具
# ============================================================
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts][$Level] $Message"
    Write-Host $line
    try { Add-Content -Path $LogFile -Value $line -Encoding UTF8 } catch { }
}

function Show-Notification {
    param([string]$Title, [string]$Text)
    if ($NoNotify) { return }
    try {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        $ni = New-Object System.Windows.Forms.NotifyIcon
        $ni.Icon = [System.Drawing.SystemIcons]::Information
        $ni.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info
        $ni.BalloonTipTitle = $Title
        $ni.BalloonTipText = $Text
        $ni.Visible = $true
        $ni.ShowBalloonTip(5000)
        Start-Sleep -Seconds 5
        $ni.Dispose()
    } catch { }
}

function Write-Result {
    param([string]$Result, [string]$Detail = "")
    $txt = "{0}  {1}  {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Result, $Detail
    try {
        Set-Content -Path (Join-Path $PSScriptRoot "last-result.txt") -Value $txt -Encoding UTF8
    } catch { }
}

# ---------- 锁屏检测 ----------
function Test-ScreenLocked {
    return (Get-Process -Name "LogonUI" -ErrorAction SilentlyContinue) -ne $null
}

# ---------- 自上次输入以来的空闲秒数 ----------
function Get-IdleSeconds {
    $lii = New-Object WbWin32+LASTINPUTINFO
    $lii.cbSize = [System.Runtime.InteropServices.Marshal]::SizeOf($lii)
    [void][WbWin32]::GetLastInputInfo([ref]$lii)
    $idle = [Math]::Max(0, [Environment]::TickCount - $lii.dwTime)
    return [int]($idle / 1000)
}

# ---------- 屏幕尺寸 ----------
function Get-ScreenSize {
    return @{ W = [WbWin32]::GetSystemMetrics(0); H = [WbWin32]::GetSystemMetrics(1) }
}

# ---------- 状态文件 ----------
function Get-LastSigninDate {
    if (Test-Path $StateFile) {
        try { return (Get-Content $StateFile -Raw -ErrorAction Stop).Trim() } catch { }
    }
    return ""
}
function Set-LastSigninDate {
    (Get-Date -Format "yyyy-MM-dd") | Set-Content -Path $StateFile -Encoding ASCII
}

# ============================================================
# 4. 单实例锁（PID 存活检测自愈）
# ============================================================
$lockPath = Join-Path $PSScriptRoot ".checkin.lock"
$lockInfoPath = Join-Path $PSScriptRoot ".checkin.info"
$script:lockStream = $null

# 更新锁信息文件（供其他实例读取 PID 以判断存活）
function Update-LockInfo {
    $info = "{0}|{1}" -f $PID, (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    try { [System.IO.File]::WriteAllText($lockInfoPath, $info, (New-Object System.Text.UTF8Encoding($false))) } catch { }
}

function Acquire-Lock {
    try {
        $script:lockStream = [System.IO.File]::Open($lockPath,
            [System.IO.FileMode]::OpenOrCreate,
            [System.IO.FileAccess]::ReadWrite,
            [System.IO.FileShare]::None)
        Update-LockInfo
        return $true
    }
    catch {
        # 锁被占用：读取持有者 PID，判断其是否仍然存活
        $stale = $false
        try {
            $content = [System.IO.File]::ReadAllText($lockInfoPath, [System.Text.Encoding]::UTF8).Trim()
            if ($content -match '^(\d+)\|') {
                $holderPid = [int]$matches[1]
                $holderProc = Get-Process -Id $holderPid -ErrorAction SilentlyContinue
                if (-not $holderProc) { $stale = $true }
            }
            else {
                $stale = $true
            }
        }
        catch { $stale = $true }
        if ($stale) {
            try {
                Write-Log "检测到卡死的签到实例（锁无存活持有者），接管运行..." "WARN"
                Remove-Item $lockPath -Force -ErrorAction SilentlyContinue
                Remove-Item $lockInfoPath -Force -ErrorAction SilentlyContinue
            } catch { }
        }
        try {
            $script:lockStream = [System.IO.File]::Open($lockPath,
                [System.IO.FileMode]::OpenOrCreate,
                [System.IO.FileAccess]::ReadWrite,
                [System.IO.FileShare]::None)
            Update-LockInfo
            return $true
        }
        catch {
            return $false
        }
    }
}

# ============================================================
# 5. 屏幕截图 + Windows OCR（带超时保护）
# ============================================================
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
    $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
})[0]

# 带超时的 WinRT 等待（默认 15 秒），避免 OCR 挂死整个脚本
function Await-WinRt {
    param($WinRtTask, $ResultType, [int]$TimeoutMs = 15000)
    $asTask = $asTaskGeneric.MakeGenericMethod($ResultType)
    $netTask = $asTask.Invoke($null, @($WinRtTask))
    if (-not $netTask.Wait($TimeoutMs)) {
        throw "OCR 操作超时（${TimeoutMs}ms）"
    }
    return $netTask.Result
}

$null = [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]
$null = [Windows.Storage.FileAccessMode, Windows.Storage, ContentType = WindowsRuntime]
$null = [Windows.Storage.Streams.IRandomAccessStream, Windows.Storage.Streams, ContentType = WindowsRuntime]
$null = [Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics, ContentType = WindowsRuntime]
$null = [Windows.Graphics.Imaging.SoftwareBitmap, Windows.Graphics, ContentType = WindowsRuntime]
$null = [Windows.Graphics.Imaging.BitmapPixelFormat, Windows.Graphics, ContentType = WindowsRuntime]
$null = [Windows.Graphics.Imaging.BitmapAlphaMode, Windows.Graphics, ContentType = WindowsRuntime]
$null = [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime]
$null = [Windows.Globalization.Language, Windows.Globalization, ContentType = WindowsRuntime]

function Test-OcrAvailable {
    try {
        $eng = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage([Windows.Globalization.Language]::new("zh-Hans-CN"))
        return ($null -ne $eng)
    }
    catch { return $false }
}

function Get-OcrLines {
    param([string]$ImagePath)
    $file = Await-WinRt ([Windows.Storage.StorageFile]::GetFileFromPathAsync($ImagePath)) ([Windows.Storage.StorageFile])
    $stream = Await-WinRt ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
    $decoder = Await-WinRt ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
    $bitmap = Await-WinRt ($decoder.GetSoftwareBitmapAsync([Windows.Graphics.Imaging.BitmapPixelFormat]::Bgra8, [Windows.Graphics.Imaging.BitmapAlphaMode]::Premultiplied)) ([Windows.Graphics.Imaging.SoftwareBitmap])
    $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage([Windows.Globalization.Language]::new("zh-Hans-CN"))
    if (-not $engine) {
        throw "系统没有可用的简体中文 OCR 引擎，请安装简体中文语言包"
    }
    $result = Await-WinRt ($engine.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])
    $lines = New-Object System.Collections.ArrayList
    foreach ($line in $result.Lines) {
        $minX = [double]::MaxValue; $minY = [double]::MaxValue
        $maxX = [double]::MinValue; $maxY = [double]::MinValue
        foreach ($w in $line.Words) {
            $r = $w.BoundingRect
            if ($r.X -lt $minX) { $minX = $r.X }
            if ($r.Y -lt $minY) { $minY = $r.Y }
            if (($r.X + $r.Width) -gt $maxX) { $maxX = $r.X + $r.Width }
            if (($r.Y + $r.Height) -gt $maxY) { $maxY = $r.Y + $r.Height }
        }
        [void]$lines.Add([pscustomobject]@{
            Text = ($line.Text -replace "\s+", "")
            X = [math]::Round($minX)
            Y = [math]::Round($minY)
            W = [math]::Round($maxX - $minX)
            H = [math]::Round($maxY - $minY)
        })
    }
    return ,$lines
}

function Save-Screenshot {
    param([string]$Path)
    $sw = [WbWin32]::GetSystemMetrics(0)
    $sh = [WbWin32]::GetSystemMetrics(1)
    Add-Type -AssemblyName System.Drawing
    $bmp = New-Object System.Drawing.Bitmap($sw, $sh)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen(0, 0, 0, 0, $bmp.Size)
    $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose()
    $bmp.Dispose()
    return $Path
}

function Get-ScreenOcrLines {
    $shot = Join-Path $env:TEMP ("wb-checkin-{0}.png" -f (Get-Date -Format "yyyyMMddHHmmssfff"))
    Save-Screenshot $shot | Out-Null
    try {
        $lines = Get-OcrLines $shot
        if ($SaveScreens) {
            Copy-Item $shot (Join-Path $DebugDir (Split-Path $shot -Leaf)) -Force
        }
        return ,$lines
    }
    finally {
        Remove-Item $shot -Force -ErrorAction SilentlyContinue
    }
}

function Find-OcrLine {
    param($Lines, [string]$Pattern)
    foreach ($line in $Lines) {
        if ($line.Text -match $Pattern) {
            return $line
        }
    }
    return $null
}

function Click-OcrLine {
    param($Line)
    $cx = [int]($Line.X + $Line.W / 2)
    $cy = [int]($Line.Y + $Line.H / 2)
    Write-Log "点击 ($cx, $cy) <- $($Line.Text)"
    Click-Point $cx $cy
}

function Click-Point {
    param([int]$X, [int]$Y)
    # 坐标钳制到屏幕范围内，防止点击落空
    $sz = Get-ScreenSize
    $X = [Math]::Max(0, [Math]::Min($X, $sz.W - 1))
    $Y = [Math]::Max(0, [Math]::Min($Y, $sz.H - 1))
    [void][WbWin32]::SetCursorPos($X, $Y)
    Start-Sleep -Milliseconds 150
    [WbWin32]::mouse_event(0x0002, 0, 0, 0, 0)  # LEFT DOWN
    Start-Sleep -Milliseconds 80
    [WbWin32]::mouse_event(0x0004, 0, 0, 0, 0)  # LEFT UP
    Start-Sleep -Milliseconds 200
}

function Test-PointOnScreen {
    param([int]$X, [int]$Y)
    $sz = Get-ScreenSize
    return ($X -ge 0 -and $X -lt $sz.W -and $Y -ge 0 -and $Y -lt $sz.H)
}

# ============================================================
# 6. WorkBuddy 窗口管理
# ============================================================
$script:wbStartedByUs = $false

function Assert-WorkBuddyWindow {
    $proc = Get-Process -Name "WorkBuddy" -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne 0 } |
        Select-Object -First 1

    if (-not $proc) {
        if ($DryRun) {
            throw "WorkBuddy 没有主窗口（请先手动打开），DryRun 模式下不会自动启动"
        }
        if (-not $WorkBuddyExe -or -not (Test-Path $WorkBuddyExe)) {
            throw "找不到 WorkBuddy 程序（当前尝试路径: $WorkBuddyExe），请用 -WorkBuddyExe 指定路径"
        }
        Write-Log "启动 WorkBuddy: $WorkBuddyExe"
        Start-Process -FilePath $WorkBuddyExe | Out-Null
        $script:wbStartedByUs = $true
        $deadline = (Get-Date).AddSeconds($StartupTimeoutSec)
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 1
            $proc = Get-Process -Name "WorkBuddy" -ErrorAction SilentlyContinue |
                Where-Object { $_.MainWindowHandle -ne 0 } |
                Select-Object -First 1
            if ($proc) { break }
        }
        if (-not $proc) {
            throw "WorkBuddy 启动后 $StartupTimeoutSec 秒内没有出现主窗口"
        }
    }

    $hwnd = $proc.MainWindowHandle
    if ([WbWin32]::IsIconic($hwnd)) {
        [void][WbWin32]::ShowWindow($hwnd, 9)  # SW_RESTORE
        Start-Sleep -Milliseconds 500
    }
    [void][WbWin32]::ShowWindow($hwnd, 3)      # SW_MAXIMIZE
    Start-Sleep -Milliseconds 800
    [void](Assert-Foreground $hwnd)
    return $hwnd
}

function Assert-Foreground {
    param($Hwnd)
    for ($i = 1; $i -le 4; $i++) {
        if ([WbWin32]::GetForegroundWindow() -eq $Hwnd) { return $true }
        [void][WbWin32]::BringWindowToTop($Hwnd)
        [WbWin32]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero)   # Alt down（解除前台锁定）
        Start-Sleep -Milliseconds 60
        [WbWin32]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero)   # Alt up
        Start-Sleep -Milliseconds 60
        [void][WbWin32]::SetForegroundWindow($Hwnd)
        Start-Sleep -Milliseconds 500
    }
    return ([WbWin32]::GetForegroundWindow() -eq $Hwnd)
}

# ============================================================
# 7. 头像坐标（校准文件优先；坐标必须落在屏幕内才使用）
# ============================================================
function Get-AvatarPoint {
    param($Hwnd)
    if (Test-Path $ConfigFile) {
        try {
            $cfg = Get-Content $ConfigFile -Raw | ConvertFrom-Json
            if ($cfg.avatarX -and $cfg.avatarY) {
                $p = @{ X = [int]$cfg.avatarX; Y = [int]$cfg.avatarY }
                if (Test-PointOnScreen $p.X $p.Y) { return $p }
                Write-Log "校准坐标 ($($p.X), $($p.Y)) 不在屏幕内，忽略" "WARN"
            }
        }
        catch {
            Write-Log "读取配置失败，改用默认位置: $_" "WARN"
        }
    }
    $r = New-Object WbWin32+RECT
    [void][WbWin32]::GetWindowRect($Hwnd, [ref]$r)
    $p = @{ X = $r.Left + 111; Y = $r.Bottom - 69 }
    if (-not (Test-PointOnScreen $p.X $p.Y)) {
        Write-Log "默认头像坐标 ($($p.X), $($p.Y)) 不在屏幕内（窗口可能最小化/异常），本次跳过头像点击" "WARN"
        return $null
    }
    return $p
}

function Save-CalibrationPoint {
    param([int]$X, [int]$Y)
    $cfg = @{ avatarX = $X; avatarY = $Y }
    $cfg | ConvertTo-Json | Set-Content -Path $ConfigFile -Encoding UTF8
    Write-Log "已保存头像坐标 ($X, $Y) -> $ConfigFile" "OK"
}

function Wait-CalibrationClick {
    Write-Log "请把鼠标移到 WorkBuddy「左下角用户头像」上并点击（15 秒内）"
    Write-Host "等待点击... (15 秒超时)" -ForegroundColor Yellow
    $deadline = (Get-Date).AddSeconds(15)
    while ((Get-Date) -lt $deadline) {
        if (([WbWin32]::GetAsyncKeyState(0x01) -band 0x8000) -ne 0) {
            while ((([WbWin32]::GetAsyncKeyState(0x01) -band 0x8000) -ne 0) -and ((Get-Date) -lt $deadline)) {
                Start-Sleep -Milliseconds 50
            }
            Start-Sleep -Milliseconds 120
            $pt = New-Object WbWin32+POINT
            [void][WbWin32]::GetCursorPos([ref]$pt)
            return @{ X = $pt.X; Y = $pt.Y }
        }
        Start-Sleep -Milliseconds 100
    }
    return $null
}

# ============================================================
# 8. 签到状态识别与执行（v2 核心逻辑）
# ============================================================
# 签到按钮
$ClaimPattern = '立即[领領]取|马上[领領]取|去[领領]取|待[领領]取|[领領]取\s*[\d,，]+\s*积分|[领領]取积分'
# 已签到（注意：不要匹配"已领N天"这类连续签到天数文案，它不是"今日已签"的证据）
$DonePattern = '今日已签到|今日已[领領]取|签到成功|[领領]取成功|明日再来|明天再来|明日可再[领領]|^已[领領]取$|^已签到$|已连续签到|连续签到.*天'
# 签到入口
$EntryPattern = '签到[领領]积分|去签到|每日签到|签到有礼|加油站|[领領]积分'
# 登录界面
$LoginPattern = '^登录$|^微信登录$|^扫码登录$|^手机号登录$|^手机验证码登录$|^其他登录方式$|^邮箱登录$'
# 加油站页面佐证（只用强标识词：侧边栏「暂无任务」等泛化词已排除，避免误判「已签到」）
$GasStationPattern = '加油站|积分|已[领領]取|签到成功|明日再来|明天再来|已连续签到|连续签到'

function Get-CheckinState {
    param($Lines)
    $login = Find-OcrLine $Lines $LoginPattern
    if ($login) { return @{ Status = "login"; Line = $login } }
    $claim = Find-OcrLine $Lines $ClaimPattern
    if ($claim) { return @{ Status = "claim"; Line = $claim } }
    $done = Find-OcrLine $Lines $DonePattern
    if ($done) { return @{ Status = "done"; Line = $done } }
    $entry = Find-OcrLine $Lines $EntryPattern
    if ($entry) { return @{ Status = "entry"; Line = $entry } }
    return @{ Status = "none"; Line = $null }
}

function Test-GasStationText {
    param($Lines)
    return (Find-OcrLine $Lines $GasStationPattern) -ne $null
}

# 失败诊断：输出屏幕 OCR 前 N 行文本
function Write-OcrDiagnostic {
    try {
        $lines = Get-ScreenOcrLines
        $n = [Math]::Min(15, $lines.Count)
        Write-Log "--- 当前屏幕 OCR 文本（前 $n 行）---" "WARN"
        for ($i = 0; $i -lt $n; $i++) {
            Write-Log ("  [{0},{1}] {2}" -f $lines[$i].X, $lines[$i].Y, $lines[$i].Text) "WARN"
        }
    } catch { }
}

# 点击「立即领取」并轮询验证。返回: success / fail
function Invoke-ClaimClick {
    param($Line)
    if ($DryRun) {
        Write-Log "检测到可签到按钮「$($Line.Text)」（DryRun，不点击）" "OK"
        return "success"
    }
    $current = $Line
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        Write-Log "找到签到按钮「$($current.Text)」，第 $attempt/3 次点击..."
        Click-OcrLine $current
        $deadline = (Get-Date).AddSeconds($ClaimVerifySec)
        $verified = $false
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 2
            $lines = Get-ScreenOcrLines
            if (Find-OcrLine $lines $DonePattern) { $verified = $true; break }
            if (-not (Find-OcrLine $lines $ClaimPattern)) { $verified = $true; break }
        }
        if ($verified) {
            Write-Log "点击后「立即领取」按钮已消失或出现已签文案，视为签到成功" "OK"
            return "success"
        }
        Write-Log "第 $attempt 次点击后验证未通过（按钮仍在），重新定位按钮后重试..." "WARN"
        Start-Sleep -Seconds 2
        $lines = Get-ScreenOcrLines
        $nl = Find-OcrLine $lines $ClaimPattern
        if (-not $nl) {
            Write-Log "领取按钮已消失（界面变化），视为签到成功" "OK"
            return "success"
        }
        $current = $nl
    }
    return "fail"
}

# 打开签到面板并处理。返回: success / done / fail / login
function Open-GasStationAndCheckin {
    param($EntryLine)
    if ($DryRun) {
        Write-Log "检测到签到入口「$($EntryLine.Text)」（DryRun，不点击；真实运行将点击该入口）" "OK"
        return "done"
    }
    Write-Log "点击签到入口「$($EntryLine.Text)」..."
    Click-OcrLine $EntryLine
    Start-Sleep -Seconds 4
    # 面板可能还在加载，先看一次
    $state = Get-CheckinState (Get-ScreenOcrLines)
    if ($state.Status -eq "claim") {
        $rc = Invoke-ClaimClick $state.Line
        if ($rc -eq "success") { return "success" }
        return "fail"
    }
    if ($state.Status -eq "done") { return "done" }
    if ($state.Status -eq "login") { return "login" }
    # 再等 2 秒重扫一次
    Start-Sleep -Seconds 2
    $state = Get-CheckinState (Get-ScreenOcrLines)
    if ($state.Status -eq "claim") {
        $rc = Invoke-ClaimClick $state.Line
        if ($rc -eq "success") { return "success" }
        return "fail"
    }
    if ($state.Status -eq "done") { return "done" }
    if ($state.Status -eq "login") { return "login" }
    # 面板打开但找不到领取按钮：若界面仍是加油站/积分相关内容 → 判定今日已签到
    if (Test-GasStationText (Get-ScreenOcrLines)) {
        if ($NoAssumeDone) {
            Write-Log "严格模式（-NoAssumeDone）：面板无领取按钮，但界面为加油站内容，按失败处理" "WARN"
            return "fail"
        }
        Write-Log "加油站页面已打开但未发现「立即领取」按钮 → 判定今日已签到" "WARN"
        return "done"
    }
    Write-Log "打开签到面板后未识别到签到相关元素" "WARN"
    return "fail"
}

# ============================================================
# 9. 智能退出
# ============================================================
$OcrBusyKeywords = @(
    '正在思考','正在生成','正在回复','正在回答','正在执行','正在处理','正在分析','正在编写','正在修改','正在运行',
    '生成中','思考中','回复中','执行任务','运行任务','任务进行中','停止生成','停止运行','停止执行',
    '编译中','构建中','测试中','生成内容','生成代码'
)
$TitleBusyKeywords = @('任务','运行','执行','生成','进度','停止')

function Get-WorkBuddyCpuPercent {
    $procs = Get-Process -Name "WorkBuddy" -ErrorAction SilentlyContinue
    if (-not $procs) { return 0 }
    $t1 = ($procs | Measure-Object -Property CPU -Sum).Sum
    $cpuCount = [Environment]::ProcessorCount
    Start-Sleep -Seconds 2
    $procs = Get-Process -Name "WorkBuddy" -ErrorAction SilentlyContinue
    if (-not $procs) { return 0 }
    $t2 = ($procs | Measure-Object -Property CPU -Sum).Sum
    $delta = [Math]::Max(0, $t2 - $t1)
    $percent = ($delta / 2) / $cpuCount * 100
    return [math]::Round($percent, 1)
}

function Test-WorkBuddyBusy {
    param($Hwnd)
    # 1) 窗口标题关键词
    $sb = New-Object System.Text.StringBuilder 512
    if ([WbWin32]::GetWindowText($Hwnd, $sb, $sb.Capacity) -gt 0) {
        $title = $sb.ToString()
        foreach ($kw in $TitleBusyKeywords) {
            if ($title -match $kw) {
                return @{ Busy = $true; Reason = "窗口标题:$kw" }
            }
        }
    }
    # 2) CPU 采样
    $cpu = Get-WorkBuddyCpuPercent
    if ($cpu -ge $CpuBusyThreshold) {
        return @{ Busy = $true; Reason = "CPU占用:${cpu}%" }
    }
    return @{ Busy = $false; Reason = "" }
}

# 重型检测：包含界面 OCR 关键词（截图 + 识别，开销大，仅在轻型检测通过后每 N 分钟执行一次）
function Test-WorkBuddyBusyWithOcr {
    param($Hwnd)
    $light = Test-WorkBuddyBusy $Hwnd
    if ($light.Busy) { return $light }
    try {
        $lines = Get-ScreenOcrLines
        foreach ($kw in $OcrBusyKeywords) {
            $hit = Find-OcrLine $lines $kw
            if ($hit) {
                return @{ Busy = $true; Reason = "界面文字:$($hit.Text)" }
            }
        }
    } catch { }
    return @{ Busy = $false; Reason = "" }
}

function Test-UserActive {
    param($Hwnd)
    if ([WbWin32]::GetForegroundWindow() -eq $Hwnd) {
        $idle = Get-IdleSeconds
        if ($idle -lt $UserActiveSec) {
            return $true
        }
    }
    return $false
}

# 点击前保护：等用户停止操作再执行模拟点击
function Wait-UserIdleBeforeClick {
    param([int]$MinIdleSec = 10, [int]$MaxWaitSec = 300)
    $deadline = (Get-Date).AddSeconds($MaxWaitSec)
    while ((Get-Date) -lt $deadline) {
        if ((Get-IdleSeconds) -ge $MinIdleSec) { return $true }
        Start-Sleep -Seconds 5
    }
    return $false
}

function Stop-WorkBuddyGracefully {
    Write-Log "关闭 WorkBuddy..." "INFO"
    $procs = Get-Process -Name "WorkBuddy" -ErrorAction SilentlyContinue
    foreach ($p in $procs) {
        try {
            if (-not $p.HasExited) { $p.CloseMainWindow() | Out-Null }
        } catch { }
    }
    $deadline = (Get-Date).AddSeconds(30)
    while ((Get-Date) -lt $deadline) {
        if (-not (Get-Process -Name "WorkBuddy" -ErrorAction SilentlyContinue)) { break }
        Start-Sleep -Seconds 1
    }
    $left = Get-Process -Name "WorkBuddy" -ErrorAction SilentlyContinue
    if ($left) {
        Write-Log "WorkBuddy 未在 30 秒内正常退出，发送退出信号后强制执行" "WARN"
        foreach ($p in $left) {
            try { taskkill.exe /PID $p.Id /T 2>&1 | Out-Null } catch { }
        }
        Start-Sleep -Seconds 5
        $left = Get-Process -Name "WorkBuddy" -ErrorAction SilentlyContinue
        if ($left) {
            Write-Log "WorkBuddy 仍不退出生，强制执行关闭" "WARN"
            $left | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
        }
    }
    if (Get-Process -Name "WorkBuddy" -ErrorAction SilentlyContinue) {
        Write-Log "WorkBuddy 仍有进程残留（可能有子进程），已尽力关闭" "WARN"
        return $false
    }
    Write-Log "WorkBuddy 已退出" "OK"
    return $true
}

function Invoke-SmartExit {
    param($Hwnd)
    if ($DryRun) {
        Write-Log "DryRun 模式：跳过退出逻辑" "INFO"
        return
    }
    $shouldClose = $script:wbStartedByUs -or $script:didClaim
    if (-not $shouldClose) {
        Write-Log "本次仅确认「今日已签到」（WorkBuddy 非本脚本启动、未执行领取），保留 WorkBuddy 运行" "INFO"
        Write-Result "OK" "今日已签到（未改动 WorkBuddy 状态）"
        return
    }
    Write-Log "签到完成，进入智能退出检测（任务检测 + 用户活动检测）..." "INFO"
    $deadline = (Get-Date).AddMinutes($TaskWaitMin)
    $checked = $false
    $tick = 0
    while ($true) {
        # 轻型检测（标题 + CPU）每秒都可做；重型 OCR 检测每 3 分钟做一次
        if ($tick % 3 -eq 0) {
            $busy = Test-WorkBuddyBusyWithOcr $Hwnd
        }
        else {
            $busy = Test-WorkBuddyBusy $Hwnd
        }
        $active = Test-UserActive $Hwnd
        if (-not $busy.Busy -and -not $active) {
            if ($checked) {
                Write-Log "任务/用户活动已结束，准备退出 WorkBuddy" "INFO"
            }
            break
        }
        $reasons = @()
        if ($busy.Busy) { $reasons += "任务检测($($busy.Reason))" }
        if ($active) { $reasons += "用户正在使用 WorkBuddy" }
        Write-Log "检测到 WorkBuddy 繁忙：$($reasons -join '；')，等待 60 秒后重新检测..." "INFO"
        if ((Get-Date) -ge $deadline) {
            Write-Log "等待 $TaskWaitMin 分钟后仍繁忙，保持 WorkBuddy 运行，本脚本退出（下次运行再处理）" "WARN"
            Write-Result "OK-BUSY" "签到成功，但 WorkBuddy 有任务/被使用，未退出"
            return
        }
        $checked = $true
        $tick++
        Start-Sleep -Seconds 60
    }
    $ok = Stop-WorkBuddyGracefully
    if ($ok) {
        Write-Result "OK" "签到成功，WorkBuddy 已自动退出"
        Show-Notification "WorkBuddy 签到" "签到成功，WorkBuddy 已自动退出"
    }
    else {
        Write-Result "OK-PARTIAL" "签到成功，但 WorkBuddy 退出不完全"
        Show-Notification "WorkBuddy 签到" "签到成功（WorkBuddy 退出不完全）"
    }
}

# ============================================================
# 10. 主流程
# ============================================================
function Main {
    # ---------- 单实例锁（带自愈） ----------
    if (-not (Acquire-Lock)) {
        Write-Log "另一个签到实例正在运行，本次跳过" "WARN"
        return 0
    }

    try {
        # ---------- 状态文件快速跳过（今日已签到） ----------
        $today = Get-Date -Format "yyyy-MM-dd"
        if (-not $DryRun -and -not $Calibrate -and (Get-LastSigninDate) -eq $today) {
            Write-Log "状态文件显示今日（$today）已完成签到，跳过。" "INFO"
            return 0
        }

        # ---------- 锁屏检测 ----------
        if (Test-ScreenLocked) {
            Write-Log "屏幕当前处于锁定/登录界面，跳过本次签到（避免误操作）" "WARN"
            return 0
        }

        # ---------- OCR 可用性 ----------
        if (-not (Test-OcrAvailable)) {
            Write-Log "系统没有简体中文 OCR 引擎，无法签到。" "ERROR"
            Write-Log "请安装简体中文语言包：设置 -> 时间和语言 -> 语言 -> 添加简体中文" "ERROR"
            Write-Result "FAIL" "缺少中文 OCR 引擎"
            return 1
        }

        # ---------- 校准模式 ----------
        if ($Calibrate) {
            Write-Log "=== WorkBuddy 桌面端头像坐标校准 ==="
            $hwnd = Assert-WorkBuddyWindow
            $pt = Wait-CalibrationClick
            if ($pt) {
                Save-CalibrationPoint -X $pt.X -Y $pt.Y
                Write-Log "=== 校准结束 ===" "OK"
                return 0
            }
            Write-Log "校准超时，未获取到点击" "WARN"
            return 1
        }

        Write-Log "=== WorkBuddy 自动签到开始（桌面端）==="

        # ---------- 主窗口 ----------
        $hwnd = Assert-WorkBuddyWindow
        Write-Log "WorkBuddy 窗口已就绪" "INFO"

        # ---------- 点击前保护 ----------
        if (-not $DryRun -and -not (Wait-UserIdleBeforeClick)) {
            Write-Log "检测到用户正在操作电脑，5 分钟内未空闲，本次跳过（计划任务每小时会自动重试）" "WARN"
            Write-Result "SKIP" "用户正在使用电脑，本次跳过"
            return 0
        }

        # ---------- 识别当前状态 ----------
        $state = Get-CheckinState (Get-ScreenOcrLines)

        # ---------- 状态机 ----------
        # 若主界面未识别到任何签到元素，先尝试点击头像展开菜单
        if ($state.Status -eq "none" -and -not $DryRun) {
            for ($round = 1; $round -le $MaxAvatarRounds; $round++) {
                $pt = Get-AvatarPoint $hwnd
                if (-not $pt) { break }
                for ($attempt = 1; $attempt -le 2; $attempt++) {
                    Write-Log "第 $round 轮：尝试 $attempt/2 点击用户头像 ($($pt.X), $($pt.Y))..."
                    [void](Assert-Foreground $hwnd)
                    Click-Point $pt.X $pt.Y
                    Start-Sleep -Seconds 2
                    $state = Get-CheckinState (Get-ScreenOcrLines)
                    if ($state.Status -ne "none") { break }
                }
                if ($state.Status -ne "none") { break }
            }
        }

        if ($state.Status -eq "login") {
            Write-Log "检测到登录界面，请先在 WorkBuddy 客户端登录后再签到" "WARN"
            Write-Result "FAIL" "未登录"
            Show-Notification "WorkBuddy 签到" "未登录，请先登录 WorkBuddy 客户端"
            return 2
        }

        $script:didClaim = $false
        if ($state.Status -eq "claim") {
            $rc = Invoke-ClaimClick $state.Line
            if ($rc -eq "success") {
                $script:didClaim = $true
                Write-Log "=== 结果: [桌面端] 签到成功 ===" "OK"
            }
            else {
                Write-Log "=== 结果: [桌面端] 签到失败（领取验证未通过）===" "WARN"
                Write-OcrDiagnostic
                Write-Result "FAIL" "领取验证未通过"
                Show-Notification "WorkBuddy 签到" "签到失败，请查看日志"
                return 1
            }
        }
        elseif ($state.Status -eq "done") {
            Write-Log "检测到「$($state.Line.Text)」，今日已完成签到" "OK"
            Write-Log "=== 结果: [桌面端] 今日已签到 ===" "OK"
        }
        elseif ($state.Status -eq "entry") {
            $result = Open-GasStationAndCheckin $state.Line
            if ($result -eq "success") {
                $script:didClaim = $true
                Write-Log "=== 结果: [桌面端] 签到成功 ===" "OK"
            }
            elseif ($result -eq "done") {
                Write-Log "=== 结果: [桌面端] 今日已签到 ===" "OK"
            }
            elseif ($result -eq "login") {
                Write-Result "FAIL" "未登录"
                Show-Notification "WorkBuddy 签到" "未登录，请先登录 WorkBuddy 客户端"
                return 2
            }
            else {
                Write-Log "=== 结果: [桌面端] 签到失败 ===" "WARN"
                Write-OcrDiagnostic
                Write-Result "FAIL" "签到失败"
                Show-Notification "WorkBuddy 签到" "签到失败，请查看日志"
                return 1
            }
        }
        else {
            # 头像尝试后仍无签到元素：若界面为加油站/积分内容 → 判定已签到
            Start-Sleep -Seconds 2
            $lines = Get-ScreenOcrLines
            if (Test-GasStationText $lines) {
                if ($NoAssumeDone) {
                    Write-Log "严格模式（-NoAssumeDone）：未识别到签到元素且无法确认，按失败处理" "WARN"
                    Write-OcrDiagnostic
                    Write-Result "FAIL" "无法确认签到状态"
                    return 1
                }
                Write-Log "未识别到「立即领取」，界面为加油站/积分内容 → 判定今日已签到" "WARN"
                Write-Log "=== 结果: [桌面端] 今日已签到 ===" "OK"
            }
            else {
                Write-Log "未识别到签到相关元素，请确认 WorkBuddy 已登录、窗口未被遮挡" "WARN"
                Write-Log "若头像位置不对，可先运行: .\workbuddy-checkin.ps1 -Calibrate" "WARN"
                Write-OcrDiagnostic
                Write-Result "FAIL" "未找到签到入口"
                Show-Notification "WorkBuddy 签到" "签到失败：未找到签到入口"
                return 1
            }
        }

        # ---------- 记录今日已签到 ----------
        if (-not $DryRun) {
            Set-LastSigninDate
            Write-Log "已更新状态文件：今日（$today）签到完成" "INFO"
        }

        # ---------- 智能退出 ----------
        if ($NoExit) {
            Write-Log "-NoExit 已指定：保留 WorkBuddy 运行，本脚本退出" "INFO"
            Write-Result "OK-NOEXIT" "签到成功（调试模式，未退出 WorkBuddy）"
            return 0
        }
        Invoke-SmartExit $hwnd
        return 0
    }
    catch {
        Write-Log "执行失败: $_" "ERROR"
        try { Write-Result "FAIL" ("异常: " + $_.Exception.Message) } catch { }
        return 1
    }
    finally {
        if ($script:lockStream) {
            try { $script:lockStream.Close() } catch { }
            $script:lockStream = $null
        }
        try { Remove-Item $lockInfoPath -Force -ErrorAction SilentlyContinue } catch { }
    }
}

exit (Main)
