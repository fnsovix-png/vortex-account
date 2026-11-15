# Builds dist_helper\VortexHelper.zip. The zip holds the helper secret, so never publish it.
$ErrorActionPreference = 'Continue'
$base = $PSScriptRoot
$work = Join-Path $base '.build'
$out = Join-Path $base 'dist_helper'
$server = $env:VORTEX_SERVER
$secret = $env:VORTEX_HELPER_SECRET
if (-not $server -or -not $secret) { Write-Output 'Set VORTEX_SERVER and VORTEX_HELPER_SECRET'; exit 1 }
New-Item -ItemType Directory -Force $out | Out-Null
Set-Location $base
& "$work\venv\Scripts\python.exe" -m PyInstaller --noconfirm --noconsole --onedir --name VortexHelper --collect-all yt_dlp --collect-submodules uvicorn --distpath "$work\helper_dist" --workpath "$work\helper_work" --specpath $work helper.py 2>&1 | Select-Object -Last 1 | ForEach-Object { "$_" }
if ($LASTEXITCODE -ne 0) { Write-Output "FAILED: helper package ($LASTEXITCODE)"; exit 1 }
$bundle = "$work\helper_dist\VortexHelper"
Copy-Item "$env:LOCALAPPDATA\Vortex\cloudflared.exe" $bundle -Force
$config = @{ server = $server; secret = $secret } | ConvertTo-Json -Compress
[IO.File]::WriteAllText("$bundle\helper_config.json", $config, (New-Object Text.UTF8Encoding $false))
$zip = "$out\VortexHelper.zip"
& tar -a -c -f $zip -C "$work\helper_dist" VortexHelper
if ($LASTEXITCODE -ne 0) { Write-Output 'FAILED: helper zip'; exit 1 }
Write-Output "OK: helper $([math]::Round((Get-Item $zip).Length / 1MB, 1)) MB"
