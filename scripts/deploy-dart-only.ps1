# deploy-dart-only.ps1 —— 只替换 Dart 层（app.so + flutter_assets），引擎/插件/运行库全部保留安装版
#
# 为什么这么干：整套 Release 树覆盖会把 flutter_windows.dll（引擎）一起换掉，
# 一旦引擎在你的机器上初始化失败，就是 flutter_windows.dll 里 0xc0000409 的静默崩溃，
# 连 app.log 都写不出来。只换 app.so + flutter_assets 的话，引擎是官方安装包带的那个，
# 风险面小得多；代价是 app.so 必须和安装版引擎的 Dart 版本兼容，不兼容会直接报
# "Wrong full snapshot version" 之类的明确错误，而不是静默崩。
#
#   .\deploy-dart-only.ps1 -SourceDir "C:\Users\me\Downloads\Hiddify-Windows-Release"
#   .\deploy-dart-only.ps1 -Zip     "C:\Users\me\Downloads\Hiddify-Windows-Release.zip"
#   .\deploy-dart-only.ps1 -Restore            # 回滚到上一次备份
param(
    [string]$Zip,
    [string]$SourceDir,
    [switch]$Restore,
    [string]$InstallDir = 'C:\Program Files\Hiddify',
    [switch]$DryRun,
    [switch]$EnsureElevated
)

$ErrorActionPreference = 'Stop'
$backupRoot = Join-Path $env:USERPROFILE 'HiddifyWallpaper\dart-backup'

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and -not $DryRun -and -not $EnsureElevated) {
    $shell = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
    if (-not $shell) { $shell = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" }
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-InstallDir', "`"$InstallDir`"", '-EnsureElevated')
    if ($Zip) { $a += @('-Zip', "`"$Zip`"") }
    if ($SourceDir) { $a += @('-SourceDir', "`"$SourceDir`"") }
    if ($Restore) { $a += '-Restore' }
    Write-Host '需要管理员权限，正在提权…'
    Start-Process -FilePath $shell -Verb RunAs -Wait -ArgumentList $a | Out-Null
    exit 0
}

if (-not (Test-Path -LiteralPath (Join-Path $InstallDir 'Hiddify.exe'))) {
    throw "安装目录里没有 Hiddify.exe：$InstallDir（先装回官方安装包）"
}

# ---- 回滚 ----
if ($Restore) {
    $last = Get-ChildItem $backupRoot -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $last) { throw "没有可回滚的备份：$backupRoot" }
    Write-Host "从备份回滚：$($last.FullName)"
    Get-Process Hiddify -ErrorAction SilentlyContinue | ForEach-Object { try { Stop-Process -Id $_.Id -Force -ErrorAction Stop } catch {} }
    Start-Sleep -Milliseconds 1200
    foreach ($rel in 'data\app.so', 'data\flutter_assets') {
        $src = Join-Path $last.FullName $rel
        if (-not (Test-Path -LiteralPath $src)) { continue }
        $dst = Join-Path $InstallDir $rel
        if (Test-Path -LiteralPath $dst -PathType Container) { Remove-Item -LiteralPath $dst -Recurse -Force }
        Copy-Item -LiteralPath $src -Destination $dst -Recurse -Force
        "回滚: $rel"
    }
    Start-Process -FilePath (Join-Path $InstallDir 'Hiddify.exe')
    exit 0
}

# ---- 取源 ----
$work = Join-Path $env:TEMP ("hid-dart-" + [guid]::NewGuid().ToString('N'))
if ($Zip) {
    if (-not (Test-Path -LiteralPath $Zip)) { throw "找不到 zip: $Zip" }
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    Expand-Archive -LiteralPath $Zip -DestinationPath $work -Force
    $SourceDir = $work
}
if (-not $SourceDir -or -not (Test-Path -LiteralPath (Join-Path $SourceDir 'data\app.so'))) {
    throw '源目录里没有 data\app.so，给 -Zip 或 -SourceDir'
}
$source = (Resolve-Path -LiteralPath $SourceDir).Path

if ($DryRun) {
    "将替换："
    "  data\app.so            <- " + (Get-Item (Join-Path $source 'data\app.so')).Length + " 字节"
    "  data\flutter_assets\   <- " + (Get-ChildItem (Join-Path $source 'data\flutter_assets') -Recurse -File).Count + " 个文件"
    "备份到：$backupRoot\<时间戳>\"
    exit 0
}

# ---- 停进程 ----
Get-Process Hiddify, HiddifyCli, HiddifyAdmin -ErrorAction SilentlyContinue | ForEach-Object {
    try { Stop-Process -Id $_.Id -Force -ErrorAction Stop; "停止 $($_.ProcessName) $($_.Id)" } catch { "杀不掉 $($_.Id)（提权）" }
}
Start-Sleep -Milliseconds 1500

# ---- 备份当前 Dart 层 ----
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = Join-Path $backupRoot $stamp
foreach ($rel in 'data\app.so', 'data\flutter_assets') {
    $src = Join-Path $InstallDir $rel
    if (-not (Test-Path -LiteralPath $src)) { continue }
    $dst = Join-Path $backup $rel
    New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
    Copy-Item -LiteralPath $src -Destination $dst -Recurse -Force
}
Write-Host "已备份到：$backup"

# ---- 只覆盖 Dart 层 ----
Copy-Item -LiteralPath (Join-Path $source 'data\app.so') -Destination (Join-Path $InstallDir 'data\app.so') -Force
$assetsDst = Join-Path $InstallDir 'data\flutter_assets'
if (Test-Path -LiteralPath $assetsDst) { Remove-Item -LiteralPath $assetsDst -Recurse -Force }
Copy-Item -LiteralPath (Join-Path $source 'data\flutter_assets') -Destination $assetsDst -Recurse -Force
Write-Host '已替换 data\app.so + data\flutter_assets（引擎/插件/运行库未动）'

Start-Process -FilePath (Join-Path $InstallDir 'Hiddify.exe')
Write-Host 'Hiddify 已启动'
if ($work -and (Test-Path -LiteralPath $work)) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
