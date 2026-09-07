@echo off
setlocal
title WorkBuddy 每日自动签到 - 卸载 v3.0.0

cd /d "%~dp0" 2>nul
if %errorlevel% neq 0 (
    echo [ERROR] 无法切换到脚本目录: %~dp0
    pause
    exit /b 1
)

echo ========================================
echo   WorkBuddy 每日自动签到 - 卸载程序
echo   版本: v3.0.0
echo ========================================
echo.

where powershell >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] 找不到 PowerShell。
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall-task.ps1"
set EXIT_CODE=%errorlevel%

echo.
if %EXIT_CODE% equ 0 (
    echo [完成] 卸载程序已成功执行。
) else (
    echo [信息] 退出代码: %EXIT_CODE%
)
echo.
pause
endlocal
