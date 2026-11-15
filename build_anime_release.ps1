# Builds Vortex Anime into dist\: VortexAnime.apk, VortexAnime-Windows.zip and anime_release.json, plus the web copy.
$ErrorActionPreference = 'Continue'
$base = $PSScriptRoot
$app = Join-Path $base 'anime_app'
$work = Join-Path $base '.build'
$dist = Join-Path $base 'dist'
$flutter = "$env:USERPROFILE\Documents\Codex\flutter-sdk-clean\flutter\bin\flutter.bat"
$env:JAVA_HOME = "$env:ProgramFiles\Android\Android Studio\jbr"
$env:ANDROID_HOME = "C:\Android\Sdk"

$notes = Get-Content (Join-Path $app 'CHANGELOG.json') -Raw | ConvertFrom-Json
$latest = @($notes)[0]
$args2 = @("--build-name=$($latest.version)", "--build-number=$($latest.build)", "--dart-define=VORTEX_VERSION=$($latest.version)")
if ($env:VORTEX_SERVER) { $args2 += "--dart-define=VORTEX_SERVER=$env:VORTEX_SERVER" }

function Check($step) {
    if ($LASTEXITCODE -ne 0) { Write-Output "FAILED: $step (exit $LASTEXITCODE)"; exit 1 }
    Write-Output "OK: $step"
}

New-Item -ItemType Directory -Force $work, $dist | Out-Null
Set-Location $app
& $flutter build web --release --no-pub --pwa-strategy=none --base-href /anime/ @args2 2>&1 | Select-Object -Last 1 | ForEach-Object { "$_" }
Check 'web build'
& $flutter build windows --release --no-pub @args2 2>&1 | Select-Object -Last 1 | ForEach-Object { "$_" }
Check 'windows build'
& $flutter build apk --release --no-pub @args2 2>&1 | Select-Object -Last 1 | ForEach-Object { "$_" }
Check 'apk build'
Copy-Item "$app\build\app\outputs\flutter-apk\app-release.apk" "$dist\VortexAnime.apk" -Force

$stage = Join-Path $work 'anime_stage\VortexAnime'
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage -Confirm:$false }
New-Item -ItemType Directory -Force $stage | Out-Null
Copy-Item "$app\build\windows\x64\runner\Release\*" $stage -Recurse
foreach ($dll in 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll') { Copy-Item "$env:WINDIR\System32\$dll" $stage }
$zip = Join-Path $dist 'VortexAnime-Windows.zip'
if (Test-Path $zip) { Remove-Item -Force $zip -Confirm:$false }
& tar -a -c -f $zip -C (Split-Path $stage) VortexAnime
Check 'windows zip'

function Package($file) { $path = Join-Path $dist $file; [ordered]@{ file = $file; sha256 = (Get-FileHash $path -Algorithm SHA256).Hash.ToLower(); size = (Get-Item $path).Length } }
$release = [ordered]@{ version = $latest.version; notes = @($notes); android = Package 'VortexAnime.apk'; windows = Package 'VortexAnime-Windows.zip' }
[IO.File]::WriteAllText((Join-Path $dist 'anime_release.json'), ($release | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding $false))
Write-Output "OK: release $($latest.version)"
Set-Location $base
