# _route_a.ps1 —— 一次性完成：装回官方安装包 -> 只替换 Dart 层 -> 启动
# 由 run-route-a.ps1 以管理员身份调用，日志写到 route-a.log
param(
    [Parameter(Mandatory = $true)][string]$Setup,
    [Parameter(Mandatory = $true)][string]$SourceDir,
    [string]$InstallDir = 'C:\Program Files\Hiddify',
    [Parameter(Mandatory = $true)][string]$LogFile
)

$ErrorActionPreference = 'Continue'
function Log([string]$m) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $m
    Add-Content -LiteralPath $LogFile -Value $line -Encoding utf8
    Write-Host $line
}

Log "=== route A start (pid $PID) ==="
Log "setup: $Setup"
Log "source: $SourceDir"

# 1) 停掉可能残留的进程
Get-Process Hiddify, HiddifyCli, HiddifyAdmin -ErrorAction SilentlyContinue | ForEach-Object {
    try { Stop-Process -Id $_.Id -Force -ErrorAction Stop; Log "stopped $($_.ProcessName) $($_.Id)" } catch { Log "cannot stop $($_.Id): $($_.Exception.Message)" }
}
Start-Sleep -Seconds 2

# 2) 静默安装官方包
Log 'running installer (VERYSILENT)…'
$p = Start-Process -FilePath $Setup -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-' -PassThru -Wait
Log "installer exit=$($p.ExitCode)"

# 3) 等安装目录就位
$exe = Join-Path $InstallDir 'Hiddify.exe'
for ($i = 0; $i -lt 60; $i++) {
    if (Test-Path -LiteralPath $exe) { break }
    Start-Sleep -Seconds 2
}
if (-not (Test-Path -LiteralPath $exe)) { Log "FAILED: $exe 不存在，安装没成功"; exit 1 }
Log "installed: $exe ($((Get-Item $exe).Length) bytes, $((Get-Item $exe).LastWriteTime))"
Log "engine: flutter_windows.dll $((Get-Item (Join-Path $InstallDir 'flutter_windows.dll') -ErrorAction SilentlyContinue).Length) bytes"

# 4) 备份现有 Dart 层
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = Join-Path $env:USERPROFILE "HiddifyWallpaper\dart-backup\$stamp"
foreach ($rel in 'data\app.so', 'data\flutter_assets') {
    $src = Join-Path $InstallDir $rel
    if (-not (Test-Path -LiteralPath $src)) { continue }
    $dst = Join-Path $backup $rel
    New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
    Copy-Item -LiteralPath $src -Destination $dst -Recurse -Force
}
Log "backup: $backup"
Log ("official app.so: " + (Get-Item (Join-Path $InstallDir 'data\app.so')).Length + " bytes")

# 5) 替换 Dart 层
Get-Process Hiddify, HiddifyCli, HiddifyAdmin -ErrorAction SilentlyContinue | ForEach-Object {
    try { Stop-Process -Id $_.Id -Force -ErrorAction Stop } catch {}
}
Start-Sleep -Seconds 2
Copy-Item -LiteralPath (Join-Path $SourceDir 'data\app.so') -Destination (Join-Path $InstallDir 'data\app.so') -Force
$assetsDst = Join-Path $InstallDir 'data\flutter_assets'
if (Test-Path -LiteralPath $assetsDst) { Remove-Item -LiteralPath $assetsDst -Recurse -Force }
Copy-Item -LiteralPath (Join-Path $SourceDir 'data\flutter_assets') -Destination $assetsDst -Recurse -Force
Log ("new app.so: " + (Get-Item (Join-Path $InstallDir 'data\app.so')).Length + " bytes")

# 6) 启动
Start-Process -FilePath $exe
Start-Sleep -Seconds 12
$alive = Get-Process Hiddify -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne $PID }
if ($alive) { Log ("running: " + (($alive | ForEach-Object { $_.Id }) -join ',')) } else { Log 'WARN: 进程不在，可能崩了' }

$log = Join-Path $env:APPDATA 'Hiddify\hiddify\app.log'
if (Test-Path -LiteralPath $log) {
    Log '--- app.log tail ---'
    Get-Content -LiteralPath $log -Tail 15 | ForEach-Object { Log "    $_" }
} else { Log 'no app.log yet' }
Log '=== route A done ==='
