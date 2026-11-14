# run-route-a.ps1 —— 提权执行 route A（装回官方包 -> 只换 Dart 层 -> 启动）
#
#   .\run-route-a.ps1
#   .\run-route-a.ps1 -SourceDir "C:\Users\me\Downloads\Hiddify-Windows-Release"
param(
    [string]$Setup = 'D:\Users\宋留洋\Downloads\Programs\Hiddify-Windows-Setup-x64.exe',
    [string]$SourceDir = 'C:\Users\宋留洋\Apps\Hiddify',
    [string]$InstallDir = 'C:\Program Files\Hiddify'
)

$ErrorActionPreference = 'Stop'
$log = Join-Path $PSScriptRoot 'route-a.log'
Remove-Item -LiteralPath $log -ErrorAction SilentlyContinue

if (-not (Test-Path -LiteralPath $Setup)) { throw "找不到安装包: $Setup" }
if (-not (Test-Path -LiteralPath (Join-Path $SourceDir 'data\app.so'))) { throw "源目录里没有 data\app.so: $SourceDir" }

$inner = Join-Path $PSScriptRoot '_route_a.ps1'
$shell = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
if (-not $shell) { $shell = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" }

Write-Host '需要管理员权限（装安装包 + 写 Program Files），正在提权…'
$p = Start-Process -FilePath $shell -Verb RunAs -PassThru -Wait -ArgumentList @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$inner`"",
    '-Setup', "`"$Setup`"", '-SourceDir', "`"$SourceDir`"",
    '-InstallDir', "`"$InstallDir`"", '-LogFile', "`"$log`""
)
Write-Host "elevated exit=$($p.ExitCode)"
if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log }
