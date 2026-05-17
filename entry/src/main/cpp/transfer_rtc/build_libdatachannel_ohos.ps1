param(
  [string]$OhosNdk = "",
  [string]$Arch = "arm64-v8a",
  [string]$PlatformLevel = "23",
  [string]$LibDataChannelVersion = "v0.22.6",
  [switch]$SkipMbedTlsBuild,
  [switch]$SkipRuntimeCopy
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$CppRoot = Resolve-Path (Join-Path $ScriptDir "..")
$EntryRoot = Resolve-Path (Join-Path $CppRoot "..\..\..")
$RuntimeLibDir = Join-Path $EntryRoot "libs\$Arch"
$ThirdPartyDir = Join-Path $ScriptDir "third_party"
$SourceDir = Join-Path $ThirdPartyDir "libdatachannel"
$BuildDir = Join-Path $ScriptDir "build-libdatachannel-arm64"
$InstallDir = Join-Path $ScriptDir "install-libdatachannel-arm64"
$MbedTlsInstallDir = Join-Path $ScriptDir "install-mbedtls-rtc-arm64"
$MbedTlsIncludeDir = Join-Path $MbedTlsInstallDir "include"
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

function Ensure-LibDataChannelSource {
  if (Test-Path -LiteralPath (Join-Path $SourceDir "CMakeLists.txt")) {
    Push-Location $SourceDir
    git submodule update --init --recursive --depth 1
    Pop-Location
    return
  }

  if (!(Test-Path -LiteralPath $ThirdPartyDir)) {
    New-Item -ItemType Directory -Path $ThirdPartyDir | Out-Null
  }

  git clone --depth 1 --branch $LibDataChannelVersion --recurse-submodules --shallow-submodules `
    https://github.com/paullouisageneau/libdatachannel.git $SourceDir
}

$ResolvedOhosNdk = Resolve-OhosNdk $OhosNdk
$CMakeExe = Join-Path $ResolvedOhosNdk "build-tools\cmake\bin\cmake.exe"
$NinjaExe = Join-Path $ResolvedOhosNdk "build-tools\cmake\bin\ninja.exe"
$ToolchainFile = Join-Path $ResolvedOhosNdk "build\cmake\ohos.toolchain.cmake"

if (!$SkipMbedTlsBuild) {
  & (Join-Path $ScriptDir "build_mbedtls_rtc_ohos.ps1") -OhosNdk $ResolvedOhosNdk -Arch $Arch -PlatformLevel $PlatformLevel -SkipRuntimeCopy:$SkipRuntimeCopy
}

Ensure-LibDataChannelSource

if (!(Test-Path -LiteralPath (Join-Path $MbedTlsInstallDir "lib\libmbedtls.so.3.5.1"))) {
  throw "RTC mbedTLS outputs are missing. Run build_mbedtls_rtc_ohos.ps1 first."
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
  "-DCMAKE_C_FLAGS=-D_GNU_SOURCE",
  "-DCMAKE_CXX_FLAGS=-D_GNU_SOURCE",
  "-DBUILD_SHARED_LIBS=ON",
  "-DBUILD_SHARED_DEPS_LIBS=OFF",
  "-DUSE_MBEDTLS=ON",
  "-DNO_MEDIA=ON",
  "-DNO_WEBSOCKET=ON",
  "-DNO_EXAMPLES=ON",
  "-DNO_TESTS=ON",
  "-DMbedTLS_INCLUDE_DIR=$(Convert-ToCMakePath $MbedTlsIncludeDir)",
  "-DMbedTLS_LIBRARY=$(Convert-ToCMakePath (Join-Path $MbedTlsInstallDir "lib\libmbedtls.so.3.5.1"))",
  "-DMbedCrypto_LIBRARY=$(Convert-ToCMakePath (Join-Path $MbedTlsInstallDir "lib\libmbedcrypto.so.3.5.1"))",
  "-DMbedX509_LIBRARY=$(Convert-ToCMakePath (Join-Path $MbedTlsInstallDir "lib\libmbedx509.so.3.5.1"))",
  "-DCMAKE_INSTALL_PREFIX=$(Convert-ToCMakePath $InstallDir)"
)

Invoke-Checked $CMakeExe $ConfigureArgs
Invoke-Checked $CMakeExe @("--build", $BuildDir, "--target", "datachannel", "--parallel", "$env:NUMBER_OF_PROCESSORS")
Invoke-Checked $CMakeExe @("--build", $BuildDir, "--target", "install")

if (!$SkipRuntimeCopy) {
  if (!(Test-Path -LiteralPath $RuntimeLibDir)) {
    New-Item -ItemType Directory -Path $RuntimeLibDir | Out-Null
  }
  $BuiltLibrary = Join-Path $BuildDir "libdatachannel.so.0.22.6"
  Copy-Item -LiteralPath $BuiltLibrary -Destination (Join-Path $RuntimeLibDir "libdatachannel.so") -Force
  Copy-Item -LiteralPath $BuiltLibrary -Destination (Join-Path $RuntimeLibDir "libdatachannel.so.0.22") -Force
  Copy-Item -LiteralPath $BuiltLibrary -Destination (Join-Path $RuntimeLibDir "libdatachannel.so.0.22.6") -Force
}

Write-Host "libdatachannel HarmonyOS build complete: $InstallDir"
