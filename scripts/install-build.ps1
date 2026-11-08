# install-build.ps1 —— 把 GitHub Actions 编出来的 Release 树盖到已安装的 Hiddify 上
#
#   .\install-build.ps1 -Zip C:\Users\me\Downloads\Hiddify-Windows-Release.zip
#   .\install-build.ps1 -SourceDir C:\Users\me\Downloads\Release
#   .\install-build.ps1 -SourceDir ... -DryRun
#
# 做的事：
#   1) 停掉 Hiddify（含后台服务进程）
#   2) 把安装目录里将被覆盖的文件备份到 %USERPROFILE%\HiddifyWallpaper\install-backup\<时间戳>\
#   3) 覆盖 exe / dll / data\（保留 unins000.* 卸载信息）
#   4) 解除网络标记（从 zip 下来的 exe 会被 SmartScreen 拦）并重启
param(
    [string]$Zip,
    [string]$SourceDir,
    [string]$InstallDir = 'C:\Program Files\Hiddify',
    [switch]$DryRun,
    [switch]$EnsureElevated
)

$ErrorActionPreference = 'Stop'

# ---- 提权：写 Program Files 需要管理员 ----
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and -not $DryRun -and -not $EnsureElevated) {
    $shell = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
    if (-not $shell) { $shell = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" }
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-InstallDir', "`"$InstallDir`"", '-EnsureElevated')
    if ($Zip) { $a += @('-Zip', "`"$Zip`"") }
    if ($SourceDir) { $a += @('-SourceDir', "`"$SourceDir`"") }
    Write-Host '需要管理员权限，正在提权…'
    Start-Process -FilePath $shell -Verb RunAs -Wait -ArgumentList $a | Out-Null
    exit 0
}

# ---- 取源 ----
$work = Join-Path $env:TEMP ("hiddify-build-" + [guid]::NewGuid().ToString('N'))
if ($Zip) {
    if (-not (Test-Path -LiteralPath $Zip)) { throw "找不到 zip: $Zip" }
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    Write-Host "解压 $Zip"
    Expand-Archive -LiteralPath $Zip -DestinationPath $work -Force
    Get-ChildItem $work -Recurse -File | ForEach-Object { Unblock-File -LiteralPath $_.FullName -ErrorAction SilentlyContinue }
    $SourceDir = $work
}
if (-not $SourceDir -or -not (Test-Path -LiteralPath (Join-Path $SourceDir 'Hiddify.exe'))) {
    throw '源目录里没有 Hiddify.exe，给 -Zip 或 -SourceDir（指向 Release 目录）'
}

$source = (Resolve-Path -LiteralPath $SourceDir).Path
if (-not (Test-Path -LiteralPath $InstallDir)) { throw "安装目录不存在: $InstallDir" }

$rel = Get-ChildItem -LiteralPath $source -Recurse -File | ForEach-Object { $_.FullName.Substring($source.Length + 1) }
Write-Host ("将覆盖 {0} 个文件" -f $rel.Count)
if ($DryRun) { $rel | Select-Object -First 20 | ForEach-Object { "  $_" }; "…（DryRun，未改动）"; exit 0 }

# ---- 停进程 ----
Get-Process Hiddify, HiddifyCli, HiddifyAdmin -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host "停止 $($_.ProcessName) ($($_.Id))"
    Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Milliseconds 1200

# ---- 备份 ----
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = Join-Path $env:USERPROFILE "HiddifyWallpaper\install-backup\$stamp"
foreach ($r in $rel) {
    $dst = Join-Path $InstallDir $r
    if (Test-Path -LiteralPath $dst -PathType Leaf) {
        $b = Join-Path $backup $r
        New-Item -ItemType Directory -Force -Path (Split-Path $b) | Out-Null
        Copy-Item -LiteralPath $dst -Destination $b -Force
    }
}
Write-Host "旧文件已备份到: $backup"

# ---- 覆盖 ----
foreach ($r in $rel) {
    $src = Join-Path $source $r
    $dst = Join-Path $InstallDir $r
    New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
    Copy-Item -LiteralPath $src -Destination $dst -Force
}
Write-Host '覆盖完成'

# ---- 启动 ----
Start-Process -FilePath (Join-Path $InstallDir 'Hiddify.exe')
Write-Host 'Hiddify 已重启'
if ($work -and (Test-Path -LiteralPath $work)) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
