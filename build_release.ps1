# Builds the downloadable Vortex packages into dist\: Vortex-Windows.zip and Vortex.apk.
$ErrorActionPreference = 'Continue'
$base = $PSScriptRoot
$app = Join-Path $base 'app'
$work = Join-Path $base '.build'
$dist = Join-Path $base 'dist'
$flutter = "$env:USERPROFILE\Documents\Codex\flutter-sdk-clean\flutter\bin\flutter.bat"
$env:JAVA_HOME = "$env:ProgramFiles\Android\Android Studio\jbr"
$env:ANDROID_HOME = "C:\Android\Sdk"

# Set VORTEX_SERVER to the hosted address so installed apps connect with no setup.
$notes = Get-Content (Join-Path $base 'CHANGELOG.json') -Raw | ConvertFrom-Json
$latest = @($notes)[0]
$server = @("--build-name=$($latest.version)", "--build-number=$($latest.build)", "--dart-define=VORTEX_VERSION=$($latest.version)")
if ($env:VORTEX_SERVER) { $server += "--dart-define=VORTEX_SERVER=$env:VORTEX_SERVER" }

# Split builds add 2000 to the arm64 version code. Taking it off here gives both
# Android files the same code, so the update popup installs over either one.
$phone = @($server | Where-Object { $_ -notlike '--build-number=*' }) + "--build-number=$($latest.build - 2000)"

function Check($step) {
    if ($LASTEXITCODE -ne 0) { Write-Output "FAILED: $step (exit $LASTEXITCODE)"; exit 1 }
    Write-Output "OK: $step"
}

New-Item -ItemType Directory -Force $work, $dist | Out-Null

Set-Location $app
& $flutter build web --release --no-pub --pwa-strategy=none @server 2>&1 | Select-Object -Last 1 | ForEach-Object { "$_" }
Check 'web build'
& $flutter build windows --release --no-pub @server 2>&1 | Select-Object -Last 1 | ForEach-Object { "$_" }
Check 'windows build'
& $flutter build apk --release --no-pub @server 2>&1 | Select-Object -Last 1 | ForEach-Object { "$_" }
Check 'apk build'
Copy-Item "$app\build\app\outputs\flutter-apk\app-release.apk" "$work\universal.apk" -Force
& $flutter build apk --release --no-pub --split-per-abi @phone 2>&1 | Select-Object -Last 1 | ForEach-Object { "$_" }
Check 'phone apk build'
Copy-Item "$app\build\app\outputs\flutter-apk\app-arm64-v8a-release.apk" "$dist\Vortex-Phone.apk" -Force

Get-CimInstance Win32_Process -Filter "Name='java.exe'" | Where-Object { $_.CommandLine -match 'gradle|kotlin' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -Confirm:$false -ErrorAction SilentlyContinue }

$venv = Join-Path $work 'venv'
if (-not (Test-Path "$venv\Scripts\python.exe")) {
    & python -m venv --system-site-packages $venv
    Check 'build venv'
    & "$venv\Scripts\python.exe" -m pip install --quiet pyinstaller 2>&1 | Select-Object -Last 1 | ForEach-Object { "$_" }
    Check 'pyinstaller install'
}

Set-Location $base
& "$venv\Scripts\python.exe" -m PyInstaller --noconfirm --noconsole --onedir --name VortexServer `
    --icon "$app\windows\runner\resources\app_icon.ico" `
    --collect-all ytmusicapi --collect-all yt_dlp --collect-submodules uvicorn `
    --distpath "$work\pyi" --workpath "$work\pyi_work" --specpath $work main.py 2>&1 | Select-Object -Last 1 | ForEach-Object { "$_" }
Check 'server package'

$stage = Join-Path $work 'stage\Vortex'
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage -Confirm:$false }
New-Item -ItemType Directory -Force $stage | Out-Null
Copy-Item "$app\build\windows\x64\runner\Release\*" $stage -Recurse
Copy-Item "$work\pyi\VortexServer" "$stage\server" -Recurse
foreach ($dll in 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll') { Copy-Item "$env:WINDIR\System32\$dll" $stage }
Copy-Item "$work\universal.apk" "$stage\Vortex.apk"
Copy-Item "$stage\Vortex.apk" "$dist\Vortex.apk" -Force

$zip = Join-Path $dist 'Vortex-Windows.zip'
if (Test-Path $zip) { Remove-Item -Force $zip -Confirm:$false }
& tar -a -c -f $zip -C (Split-Path $stage) Vortex
Check 'windows zip'

function Package($file) { $path = Join-Path $dist $file; [ordered]@{ file = $file; sha256 = (Get-FileHash $path -Algorithm SHA256).Hash.ToLower(); size = (Get-Item $path).Length } }
$release = [ordered]@{ version = $latest.version; notes = @($notes); android = Package 'Vortex.apk'; windows = Package 'Vortex-Windows.zip' }
[IO.File]::WriteAllText((Join-Path $dist 'release.json'), ($release | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding $false))
Write-Output "OK: release $($latest.version)"
Get-ChildItem $dist | ForEach-Object { "$($_.FullName) $([math]::Round($_.Length / 1MB, 1)) MB" }
