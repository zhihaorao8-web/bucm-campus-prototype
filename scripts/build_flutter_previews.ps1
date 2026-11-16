# Builds/verifies only. Never installs, signs with a new key, tags or publishes.
param(
    [string]$Flutter = 'flutter',
    [string]$ExpectedSourceSha = '',
    [ValidateSet('preview', 'release')][string]$Kind = 'preview',
    [string]$SignerSha256 = '',
    [long]$CiRunId = 0,
    [string]$BuildTools = ''
)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$projectRoot = Split-Path $PSScriptRoot -Parent
$sourceSha = (git -C $projectRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $sourceSha -notmatch '^[a-f0-9]{40}$') { throw 'Cannot identify source commit.' }
if (!$ExpectedSourceSha) { $ExpectedSourceSha = $sourceSha }
if ($ExpectedSourceSha -cne $sourceSha) { throw 'Checkout differs from expected source SHA.' }
if ($Kind -eq 'release') {
    if ($SignerSha256 -cnotmatch '^[a-f0-9]{64}$' -or $CiRunId -lt 1) { throw 'Release needs trusted signer SHA-256 and exact successful CI run ID.' }
    if (git -C $projectRoot status --porcelain) { throw 'Release requires a clean source checkout.' }
    python (Join-Path $PSScriptRoot 'verify_apks.py') ci --source $sourceSha --ci-run-id $CiRunId
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
$flutterPath = (Get-Command $Flutter -ErrorAction Stop).Source
$flutterSdk = Split-Path (Split-Path $flutterPath -Parent) -Parent
if (!$BuildTools) {
    $sdk = $env:ANDROID_SDK_ROOT
    if (!$sdk) { $sdk = $env:ANDROID_HOME }
    if (!$sdk) {
        $local = Get-Content (Join-Path $projectRoot 'mobile/android/local.properties') -ErrorAction SilentlyContinue
        $entry = $local | Where-Object { $_ -like 'sdk.dir=*' } | Select-Object -First 1
        if ($entry) { $sdk = $entry.Substring(8).Replace('\\', '\') }
    }
    if (!$sdk) { throw 'Provide -BuildTools or an Android SDK location.' }
    $BuildTools = (Get-ChildItem (Join-Path $sdk 'build-tools') -Directory |
        Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' } |
        Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1).FullName
}
foreach ($tool in @('aapt2.exe', 'apksigner.bat')) {
    if (!(Test-Path -LiteralPath (Join-Path $BuildTools $tool))) { throw "Missing Android build tool: $tool" }
}
[xml]$manifest = Get-Content (Join-Path $projectRoot 'AndroidManifest.xml') -Raw
$version = $manifest.manifest.GetAttribute('versionName', 'http://schemas.android.com/apk/res/android')
if ($version -notmatch '^\d+\.\d+(\.\d+)?$') { throw 'Invalid manifest version.' }
$runKey = $sourceSha.Substring(0, 8) + '-' + [guid]::NewGuid().ToString('N')
$outputDir = Join-Path $projectRoot "build/flutter-previews/$runKey"
$logDir = Join-Path $projectRoot 'build/flutter-preview-logs'
New-Item -ItemType Directory -Force $outputDir, $logDir | Out-Null
$apks = @{}
Push-Location (Join-Path $projectRoot 'mobile')
try {
    foreach ($mode in @('debug', 'release')) {
        $current = (git -C $projectRoot rev-parse HEAD).Trim()
        if ($LASTEXITCODE -ne 0 -or $current -cne $sourceSha) { throw 'Source changed during the build.' }
        if ($Kind -eq 'release' -and (git -C $projectRoot status --porcelain)) { throw 'Release checkout became dirty.' }
        $apk = [IO.Path]::GetFullPath((Join-Path $PWD "build/app/outputs/flutter-apk/app-$mode.apk"))
        $allowed = [IO.Path]::GetFullPath((Join-Path $PWD 'build/app/outputs/flutter-apk')) + [IO.Path]::DirectorySeparatorChar
        if (!$apk.StartsWith($allowed, [StringComparison]::OrdinalIgnoreCase)) { throw 'APK path escaped Flutter output.' }
        # A successful command must create a new APK; old outputs cannot count.
        if (Test-Path -LiteralPath $apk) { Remove-Item -LiteralPath $apk }
        $diagnostics = if ($mode -eq 'debug') { 'true' } else { 'false' }
        & $flutterPath build apk "--$mode" --dart-define=CAMPUS_DIRECT_CATALOG=true "--dart-define=CAMPUS_TEST_DIAGNOSTICS=$diagnostics" --verbose 2>&1 |
            Tee-Object -FilePath (Join-Path $logDir "$runKey-$mode.log")
        $buildExitCode = $LASTEXITCODE
        if ($buildExitCode -ne 0) { exit $buildExitCode }
        if (!(Test-Path -LiteralPath $apk)) { throw "Missing fresh $mode APK." }
        $name = "campus-schedule-$version-android-$mode.apk"
        $destination = Join-Path $outputDir $name
        Copy-Item -LiteralPath $apk -Destination $destination
        $apks[$mode] = $destination
    }
} finally { Pop-Location }
$current = (git -C $projectRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $current -cne $sourceSha) { throw 'Source changed before verification.' }
if ($Kind -eq 'release' -and (git -C $projectRoot status --porcelain)) { throw 'Release checkout became dirty.' }
$verifyArgs = @((Join-Path $PSScriptRoot 'verify_apks.py'), '--debug', $apks.debug, '--release', $apks.release,
    '--source', $sourceSha, '--kind', $Kind, '--build-tools', $BuildTools, '--flutter-sdk', $flutterSdk,
    '--output', (Join-Path $outputDir 'build-metadata.json'))
if ($SignerSha256) { $verifyArgs += @('--signer-sha256', $SignerSha256) }
if ($CiRunId -gt 0) { $verifyArgs += @('--ci-run-id', "$CiRunId") }
python @verifyArgs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$hashLines = @('debug', 'release') | ForEach-Object {
    $hash = (Get-FileHash -LiteralPath $apks[$_] -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  $([IO.Path]::GetFileName($apks[$_]))"
}
[IO.File]::WriteAllLines((Join-Path $outputDir 'SHA256SUMS.txt'), $hashLines)
Write-Output "Verified $Kind artifacts: $outputDir"
