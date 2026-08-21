[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidatePattern('^[a-z0-9][a-z0-9\-]{1,80}$')]
  [string]$PageId,
  [string]$HdcPath = 'F:\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe',
  [string]$Device = '',
  [string]$OutputDirectory = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$nativeProcessHelperPath = Join-Path $PSScriptRoot 'Invoke-LegadoNativeProcess.ps1'
if (-not (Test-Path -LiteralPath $nativeProcessHelperPath)) {
  throw '原生进程边界脚本不存在。'
}
. $nativeProcessHelperPath

function Invoke-Hdc {
  param(
    [string[]]$Arguments,
    [ValidateRange(1, 600)]
    [int]$TimeoutSeconds = 30,
    [switch]$AllowFailure
  )
  [string[]]$nativeArguments = @()
  if ($Device.Length -gt 0) {
    $nativeArguments = @('-t', $Device) + @($Arguments)
  } else {
    $nativeArguments = @($Arguments)
  }
  $result = Invoke-LegadoNativeProcess `
    -FilePath $HdcPath `
    -ArgumentList $nativeArguments `
    -TimeoutSeconds $TimeoutSeconds
  $protocolFailure = $result.output.Contains('[Fail]') -or $result.output.Contains('error:')
  $failed = $result.classification -ne 'success' -or $protocolFailure
  if ($failed -and -not $AllowFailure) {
    $detail = @($result.output -split '[\r\n]+' | Where-Object { $_.Trim().Length -gt 0 } | Select-Object -First 1)
    throw (
      "HDC_FAILED classification=$($result.classification);timedOut=$($result.timedOut);" +
      "exitCode=$($result.exitCode);detail=$([string]::Join(' ', $detail))"
    )
  }
  return [pscustomobject][ordered]@{
    failed = $failed
    classification = [string]$result.classification
    timedOut = [bool]$result.timedOut
    exitCode = [int]$result.exitCode
    output = [string]$result.output
  }
}

if ($OutputDirectory.Length -eq 0) {
  $OutputDirectory = Join-Path $PSScriptRoot 'device-evidence\ui-audit'
}
if ($Device.Length -eq 0) {
  $targetResult = Invoke-Hdc -Arguments @('list', 'targets') -TimeoutSeconds 15
  $Device = [string](@(
    $targetResult.output -split '[\r\n]+' |
      ForEach-Object { $_.Trim() } |
      Where-Object { $_.Length -gt 0 -and $_ -notmatch '^\[' } |
      Select-Object -First 1
  ))
  $Device = $Device.Trim()
}
if ($Device.Length -eq 0) {
  throw '没有连接 HarmonyOS 真机。'
}

function Get-Sha256ForFile {
  param([string]$Path)
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Write-Utf8Atomic {
  param([string]$Path, [string]$Content)
  $temporaryPath = "$Path.tmp.$PID.$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  [System.IO.File]::WriteAllText($temporaryPath, $Content, [System.Text.UTF8Encoding]::new($false))
  Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
}

function Get-OptionalProperty {
  param([object]$Object, [string]$Name)
  if ($null -eq $Object) {
    return $null
  }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) {
    return $null
  }
  return $property.Value
}

[System.IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null
$remoteScreenshot = "/data/local/tmp/manxia-ui-audit-$PageId.jpeg"
$remoteLayout = "/data/local/tmp/manxia-ui-audit-$PageId.json"
$screenshotPath = Join-Path $OutputDirectory "$PageId.jpeg"
$metadataPath = Join-Path $OutputDirectory "$PageId.metadata.json"

$snapshotResult = Invoke-Hdc `
  -Arguments @('shell', 'snapshot_display', '-f', $remoteScreenshot) `
  -TimeoutSeconds 45
$recvResult = Invoke-Hdc `
  -Arguments @('file', 'recv', $remoteScreenshot, $screenshotPath) `
  -TimeoutSeconds 120 `
  -AllowFailure
if ([bool]$recvResult.failed -or -not (Test-Path -LiteralPath $screenshotPath)) {
  throw '真机截图拉取失败。'
}

$layoutResult = Invoke-Hdc `
  -Arguments @('shell', 'uitest', 'dumpLayout', '-p', $remoteLayout, '-b', 'com.dlzz.manxia') `
  -TimeoutSeconds 45
$layoutRaw = (Invoke-Hdc `
  -Arguments @('shell', 'cat', $remoteLayout) `
  -TimeoutSeconds 30).output
$layout = $layoutRaw | ConvertFrom-Json
$pagePaths = @()
function Collect-PagePaths {
  param([object]$Node)
  if ($null -eq $Node) {
    return
  }
  $attributes = Get-OptionalProperty -Object $Node -Name 'attributes'
  if ($null -ne $attributes) {
    $pagePathValue = Get-OptionalProperty -Object $attributes -Name 'pagePath'
    $pagePath = if ($null -eq $pagePathValue) { '' } else { [string]$pagePathValue }
    if ($pagePath.Length -gt 0 -and -not $pagePaths.Contains($pagePath)) {
      $script:pagePaths += $pagePath
    }
  }
  $children = Get-OptionalProperty -Object $Node -Name 'children'
  foreach ($child in @($children)) {
    Collect-PagePaths -Node $child
  }
}
Collect-PagePaths -Node $layout

$item = Get-Item -LiteralPath $screenshotPath
$metadata = [pscustomobject][ordered]@{
  schemaVersion = 1
  pageId = $PageId
  capturedAt = [DateTimeOffset]::UtcNow.ToString('o')
  deviceClass = 'harmony_real_device'
  pagePaths = $pagePaths
  screenshotSha256 = Get-Sha256ForFile -Path $screenshotPath
  screenshotBytes = $item.Length
}
Write-Utf8Atomic -Path $metadataPath -Content ($metadata | ConvertTo-Json -Depth 5)
Write-Output "UI_AUDIT_SCREENSHOT_READY pageId=$PageId bytes=$($item.Length)"
