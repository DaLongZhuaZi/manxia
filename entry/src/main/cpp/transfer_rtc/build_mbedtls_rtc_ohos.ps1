param(
  [string]$OhosNdk = "",
  [string]$Arch = "arm64-v8a",
  [string]$PlatformLevel = "23",
  [switch]$SkipRuntimeCopy
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$CppRoot = Resolve-Path (Join-Path $ScriptDir "..")
$EntryRoot = Resolve-Path (Join-Path $CppRoot "..\..\..")
$RuntimeLibDir = Join-Path $EntryRoot "libs\$Arch"
$Version = "3.5.1"
$WebDavSourceDir = Join-Path $CppRoot "webdav\mbedtls-$Version"
$ThirdPartyDir = Join-Path $ScriptDir "third_party"
$FallbackSourceDir = Join-Path $ThirdPartyDir "mbedtls-$Version"
$BuildDir = Join-Path $ScriptDir "build-mbedtls-rtc-arm64"
$InstallDir = Join-Path $ScriptDir "install-mbedtls-rtc-arm64"
$ConfigHeader = Join-Path $ScriptDir "mbedtls_rtc_config.h"

function Resolve-OhosNdk {
  param([string]$Requested)
  $candidates = @()
  if ($Requested.Trim().Length -gt 0) {
    $candidates += $Requested
  }
  if ($env:OHOS_NDK -and $env:OHOS_NDK.Trim().Length -gt 0) {
    $candidates += $env:OHOS_NDK
  }
  $candidates += "F:\HarmonyOS\SDK\23\native"
  $candidates += "F:\DevEco Studio\sdk\default\openharmony\native"

  foreach ($candidate in $candidates) {
    $toolchain = Join-Path $candidate "build\cmake\ohos.toolchain.cmake"
    if (Test-Path -LiteralPath $toolchain) {
      return (Resolve-Path $candidate).Path
    }
  }
  throw "HarmonyOS Native SDK not found. Set -OhosNdk or OHOS_NDK to the native SDK directory."
}

function Convert-ToCMakePath {
  param([string]$Path)
  return $Path.Replace('\', '/')
}

function Assert-ChildPath {
  param([string]$Path, [string]$Parent)
  $parentFull = [System.IO.Path]::GetFullPath($Parent)
  $pathFull = [System.IO.Path]::GetFullPath($Path)
  if (!$pathFull.StartsWith($parentFull, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to operate outside transfer_rtc: $pathFull"
  }
}

function Invoke-Checked {
  param([string]$FilePath, [string[]]$Arguments)
  & $FilePath @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "Command failed with exit code ${LASTEXITCODE}: $FilePath"
  }
}

function Set-Utf8Text {
  param([string]$Path, [string]$Text)
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $Text, $utf8NoBom)
}

function Ensure-MbedTlsSource {
  if (Test-Path -LiteralPath (Join-Path $WebDavSourceDir "CMakeLists.txt")) {
    return (Resolve-Path $WebDavSourceDir).Path
  }

  if (Test-Path -LiteralPath (Join-Path $FallbackSourceDir "CMakeLists.txt")) {
    return (Resolve-Path $FallbackSourceDir).Path
  }

  if (!(Test-Path -LiteralPath $ThirdPartyDir)) {
    New-Item -ItemType Directory -Path $ThirdPartyDir | Out-Null
  }

  git clone --depth 1 --branch "v$Version" https://github.com/Mbed-TLS/mbedtls.git $FallbackSourceDir
  return (Resolve-Path $FallbackSourceDir).Path
}

$ResolvedOhosNdk = Resolve-OhosNdk $OhosNdk
$CMakeExe = Join-Path $ResolvedOhosNdk "build-tools\cmake\bin\cmake.exe"
$NinjaExe = Join-Path $ResolvedOhosNdk "build-tools\cmake\bin\ninja.exe"
$ToolchainFile = Join-Path $ResolvedOhosNdk "build\cmake\ohos.toolchain.cmake"
$SourceDir = Ensure-MbedTlsSource

if (!(Test-Path -LiteralPath $ConfigHeader)) {
  throw "RTC mbedTLS config header is missing: $ConfigHeader"
}

if (Test-Path -LiteralPath $BuildDir) {
  Assert-ChildPath $BuildDir $ScriptDir
  Remove-Item -LiteralPath $BuildDir -Recurse -Force
}
if (Test-Path -LiteralPath $InstallDir) {
  Assert-ChildPath $InstallDir $ScriptDir
  Remove-Item -LiteralPath $InstallDir -Recurse -Force
}
New-Item -ItemType Directory -Path $BuildDir | Out-Null
New-Item -ItemType Directory -Path $InstallDir | Out-Null

$ConfigHeaderCMake = Convert-ToCMakePath ((Resolve-Path $ConfigHeader).Path)

$ConfigureArgs = @(
  "-S", $SourceDir,
  "-B", $BuildDir,
  "-G", "Ninja",
  "-DCMAKE_TOOLCHAIN_FILE=$(Convert-ToCMakePath $ToolchainFile)",
  "-DCMAKE_MAKE_PROGRAM=$(Convert-ToCMakePath $NinjaExe)",
  "-DOHOS_ARCH=$Arch",
  "-DOHOS_PLATFORM_LEVEL=$PlatformLevel",
  "-DOHOS_STL=c++_shared",
  "-DCMAKE_BUILD_TYPE=Release",
  "-DENABLE_PROGRAMS=OFF",
  "-DENABLE_TESTING=OFF",
  "-DUSE_SHARED_MBEDTLS_LIBRARY=ON",
  "-DUSE_STATIC_MBEDTLS_LIBRARY=OFF",
  "-DMBEDTLS_FATAL_WARNINGS=OFF",
  "-DMBEDTLS_USER_CONFIG_FILE=$ConfigHeaderCMake",
  "-DCMAKE_C_FLAGS=-D_GNU_SOURCE -Wno-error -Wno-unused-command-line-argument",
  "-DCMAKE_INSTALL_PREFIX=$(Convert-ToCMakePath $InstallDir)"
)
Invoke-Checked $CMakeExe $ConfigureArgs
Invoke-Checked $CMakeExe @("--build", $BuildDir, "--parallel", "$env:NUMBER_OF_PROCESSORS")
Invoke-Checked $CMakeExe @("--build", $BuildDir, "--target", "install")

$InstalledConfigPath = Join-Path $InstallDir "include\mbedtls\mbedtls_config.h"
$InstalledConfigText = [System.IO.File]::ReadAllText($InstalledConfigPath, [System.Text.Encoding]::UTF8)
$InstalledConfigText = $InstalledConfigText.Replace("//#define MBEDTLS_SSL_DTLS_SRTP", "#define MBEDTLS_SSL_DTLS_SRTP")
Set-Utf8Text $InstalledConfigPath $InstalledConfigText

if (!$SkipRuntimeCopy) {
  if (!(Test-Path -LiteralPath $RuntimeLibDir)) {
    New-Item -ItemType Directory -Path $RuntimeLibDir | Out-Null
  }
  Copy-Item -LiteralPath (Join-Path $InstallDir "lib\libmbedtls.so.3.5.1") -Destination (Join-Path $RuntimeLibDir "libmbedtls.so") -Force
  Copy-Item -LiteralPath (Join-Path $InstallDir "lib\libmbedtls.so.3.5.1") -Destination (Join-Path $RuntimeLibDir "libmbedtls.so.20") -Force
  Copy-Item -LiteralPath (Join-Path $InstallDir "lib\libmbedx509.so.3.5.1") -Destination (Join-Path $RuntimeLibDir "libmbedx509.so") -Force
  Copy-Item -LiteralPath (Join-Path $InstallDir "lib\libmbedx509.so.3.5.1") -Destination (Join-Path $RuntimeLibDir "libmbedx509.so.6") -Force
  Copy-Item -LiteralPath (Join-Path $InstallDir "lib\libmbedcrypto.so.3.5.1") -Destination (Join-Path $RuntimeLibDir "libmbedcrypto.so") -Force
  Copy-Item -LiteralPath (Join-Path $InstallDir "lib\libmbedcrypto.so.3.5.1") -Destination (Join-Path $RuntimeLibDir "libmbedcrypto.so.15") -Force
}

Write-Host "RTC mbedTLS build complete: $InstallDir"
