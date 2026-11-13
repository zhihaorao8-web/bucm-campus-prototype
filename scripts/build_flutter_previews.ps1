# CI preview artifacts use the runner's temporary development signer.
# Published upgrade APKs must be rebuilt/verified with the trusted local signer.
param([string]$Flutter = 'flutter')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$outputDir = Join-Path $projectRoot 'build/flutter-previews'
$logDir = Join-Path $projectRoot 'build/flutter-preview-logs'
New-Item -ItemType Directory -Force $outputDir, $logDir | Out-Null
[xml]$manifest = Get-Content (Join-Path $projectRoot 'AndroidManifest.xml') -Raw
$version = $manifest.manifest.GetAttribute('versionName', 'http://schemas.android.com/apk/res/android')
if ($version -notmatch '^\d+\.\d+(\.\d+)?$') { throw 'Invalid manifest version.' }
$sourceSha = git -C $projectRoot rev-parse HEAD
if ($LASTEXITCODE -ne 0) { throw 'Cannot identify source commit.' }
$hashLines = @()
Push-Location (Join-Path $projectRoot 'mobile')
try {
    # Do not parallelize: each Flutter build regenerates plugin registration.
    foreach ($mode in @('debug', 'release')) {
        $diagnostics = if ($mode -eq 'debug') { 'true' } else { 'false' }
        & $Flutter build apk "--$mode" --dart-define=CAMPUS_DIRECT_CATALOG=true "--dart-define=CAMPUS_TEST_DIAGNOSTICS=$diagnostics" --verbose 2>&1 |
            Tee-Object -FilePath (Join-Path $logDir "$mode.log")
        $buildExitCode = $LASTEXITCODE
        if ($buildExitCode -ne 0) { exit $buildExitCode }
        $apk = Join-Path $PWD "build/app/outputs/flutter-apk/app-$mode.apk"
        if (!(Test-Path -LiteralPath $apk)) { throw "Missing $mode APK." }
        $name = "campus-schedule-$version-android-$mode.apk"
        Copy-Item -LiteralPath $apk -Destination (Join-Path $outputDir $name)
        $hash = (Get-FileHash -LiteralPath (Join-Path $outputDir $name) -Algorithm SHA256).Hash.ToLowerInvariant()
        $hashLines += "$hash  $name"
    }
} finally { Pop-Location }
[IO.File]::WriteAllLines((Join-Path $outputDir 'SHA256SUMS.txt'), $hashLines)
@{
    sourceSha = $sourceSha.Trim()
    version = $version
    directCatalog = $true
    diagnostics = @{ debug = $true; release = $false }
    signing = 'CI temporary development signer; not a published upgrade artifact'
} | ConvertTo-Json -Depth 3 | Set-Content (Join-Path $outputDir 'build-metadata.json') -Encoding utf8
