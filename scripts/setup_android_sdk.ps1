# Installs Android SDK cmdline-tools, accepts licenses, installs Flutter Android deps.
# Run once: powershell -ExecutionPolicy Bypass -File scripts\setup_android_sdk.ps1

$ErrorActionPreference = "Stop"
$sdkRoot = "$env:LOCALAPPDATA\Android\sdk"
$licensesDir = Join-Path $sdkRoot "licenses"

Write-Host "Android SDK root: $sdkRoot"
New-Item -ItemType Directory -Force -Path $sdkRoot | Out-Null
New-Item -ItemType Directory -Force -Path $licensesDir | Out-Null

# Standard license hashes (Android SDK / NDK terms).
@{
    "android-sdk-license" = "24333f8a63b6825ea9c5514f83c2829b683f94b4"
    "android-sdk-preview-license" = "84831b9409646a918e3016f2cbb8c6a4c90ab5d36b195181ef907dc9a39f99be2"
    "android-ndk-license" = "8403addf88ab4874007e885c5d6d8328c6f3872"
    "mips-android-sysimage-license" = "e9acab5b34f334813d9488d9a85dc367f0742ba8"
} | ForEach-Object {
    $_.GetEnumerator() | ForEach-Object {
        Set-Content -Path (Join-Path $licensesDir $_.Key) -Value $_.Value -NoNewline
        Write-Host "Wrote license: $($_.Key)"
    }
}

$cmdlineRoot = Join-Path $sdkRoot "cmdline-tools"
$latestDir = Join-Path $cmdlineRoot "latest"
$sdkmanager = Join-Path $latestDir "bin\sdkmanager.bat"

if (-not (Test-Path $sdkmanager)) {
    Write-Host "Downloading Android command-line tools..."
    $zipUrl = "https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip"
    $zipPath = Join-Path $env:TEMP "cmdline-tools.zip"
    Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing
    $extractDir = Join-Path $env:TEMP "cmdline-tools-extract"
    if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force }
    Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force
    New-Item -ItemType Directory -Force -Path $cmdlineRoot | Out-Null
    if (Test-Path $latestDir) { Remove-Item $latestDir -Recurse -Force }
    Move-Item (Join-Path $extractDir "cmdline-tools") $latestDir
    Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
    Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Installed cmdline-tools to $latestDir"
}

$env:ANDROID_HOME = $sdkRoot
$env:ANDROID_SDK_ROOT = $sdkRoot

$packages = @(
    "platform-tools",
    "platforms;android-35",
    "build-tools;35.0.0",
    "ndk;28.2.13676358"
)

Write-Host "Installing SDK packages (may take several minutes)..."
& $sdkmanager --install $packages

Write-Host ""
Write-Host "Done. Run: flutter doctor -v"
Write-Host "Then: flutter run"
