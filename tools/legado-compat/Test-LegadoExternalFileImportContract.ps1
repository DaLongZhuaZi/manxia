[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$OutputPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\external-file-import-contract.json'
}

function Read-Utf8Text {
  param([Parameter(Mandatory = $true)][string]$Path)

  $utf8 = [System.Text.UTF8Encoding]::new($false, $true)
  return [System.IO.File]::ReadAllText($Path, $utf8)
}

function Assert-Contract {
  param(
    [Parameter(Mandatory = $true)][bool]$Condition,
    [Parameter(Mandatory = $true)][string]$Message
  )

  if (-not $Condition) {
    throw "External file import contract failed: $Message"
  }
}

function Assert-Contains {
  param(
    [Parameter(Mandatory = $true)][string]$Text,
    [Parameter(Mandatory = $true)][string]$Token,
    [Parameter(Mandatory = $true)][string]$Message
  )

  Assert-Contract ($Text.Contains($Token)) $Message
}

function Assert-Ordered {
  param(
    [Parameter(Mandatory = $true)][string]$Text,
    [Parameter(Mandatory = $true)][string]$First,
    [Parameter(Mandatory = $true)][string]$Second,
    [Parameter(Mandatory = $true)][string]$Message
  )

  $firstIndex = $Text.IndexOf($First)
  $secondIndex = $Text.IndexOf($Second)
  Assert-Contract (($firstIndex -ge 0) -and ($secondIndex -ge 0) -and ($firstIndex -lt $secondIndex)) $Message
}

$externalPagePath = Join-Path $RepositoryRoot 'entry\src\main\ets\pages\ExternalFileTaskAbilityPage.ets'
$parserPath = Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Novel\LargeFileJSONParser.ets'
$dialogHarnessPath = Join-Path $RepositoryRoot 'tools\legado-compat\Resolve-HypiumSystemDialog.py'

Assert-Contract (Test-Path -LiteralPath $externalPagePath -PathType Leaf) 'ExternalFileTaskAbilityPage must exist.'
Assert-Contract (Test-Path -LiteralPath $parserPath -PathType Leaf) 'LargeFileJSONParser must exist.'
Assert-Contract (Test-Path -LiteralPath $dialogHarnessPath -PathType Leaf) 'system-dialog Harness must exist.'

$externalPage = Read-Utf8Text -Path $externalPagePath
$parser = Read-Utf8Text -Path $parserPath
$dialogHarness = Read-Utf8Text -Path $dialogHarnessPath

Assert-Contains $externalPage "@State private isNavigationDestinationActive: boolean = false;" 'status overlay state must be explicit.'
Assert-Contains $externalPage ".id('external_file_task_status')" 'first-frame task status requires a stable semantic id.'
Assert-Contains $externalPage 'if (!this.isNavigationDestinationActive)' 'status overlay must remain visible without a NavPathStack destination.'
Assert-Contains $externalPage 'this.isNavigationDestinationActive = true;' 'route transitions must explicitly dismiss the status overlay.'
Assert-Contains $externalPage 'private isGrantedExternalUri(value: string): boolean' 'external URI classification must be centralized.'
Assert-Ordered $externalPage "if (this.isGrantedExternalUri(trimmedUri))" 'new coreFileUri.FileUri(trimmedUri).path' 'granted URI must be preserved before file-path normalization.'
Assert-Contains $externalPage "if (this.isGrantedExternalUri(readablePath))" 'import preflight must branch for granted URIs.'
Assert-Contains $externalPage '正在打开授权书源文件' 'granted URI phase must be observable on device.'

Assert-Contains $parser "const isGrantedUri = filePath.includes('://');" 'parser must classify URI inputs.'
Assert-Contains $parser 'file = SafeFileUtils.openSyncStrict(filePath, fs.OpenMode.READ_ONLY);' 'parser must open a granted URI directly.'
Assert-Contains $parser '? SafeFileUtils.statSyncStrict(file.fd)' 'parser must read URI size from the already-open FD.'
Assert-Contains $parser 'if (file === null) {' 'path mode must be the only branch that opens after path stat.'

Assert-Contains $dialogHarness 'click_target.click()' 'system menu Harness must click the resolved Button owner.'
Assert-Contract (-not $dialogHarness.Contains('        target.click()')) 'system menu Harness must not click the non-clickable Text label.'
Assert-Contains $dialogHarness "'--post-click-component-id'" 'system menu Harness must accept a required post-click continuation probe.'
Assert-Contains $dialogHarness 'verify_post_click_app_continuation' 'system menu Harness must record verified app continuation after the click.'

$result = [PSCustomObject]@{
  status = 'passed'
  uriPreserved = $true
  uriSingleOpen = $true
  visibleExternalStatus = $true
  clickableSystemMenuOwner = $true
  postClickContinuationProbe = $true
}
$outputDirectory = Split-Path -Path $OutputPath -Parent
if (-not (Test-Path -LiteralPath $outputDirectory)) {
  [void][System.IO.Directory]::CreateDirectory($outputDirectory)
}
$temporaryPath = Join-Path $outputDirectory ('.' + [System.IO.Path]::GetFileName($OutputPath) + '.' + [Guid]::NewGuid().ToString('N') + '.tmp')
try {
  [System.IO.File]::WriteAllText(
    $temporaryPath,
    [string]($result | ConvertTo-Json -Depth 8),
    [System.Text.UTF8Encoding]::new($false)
  )
  Move-Item -LiteralPath $temporaryPath -Destination $OutputPath -Force
} finally {
  if (Test-Path -LiteralPath $temporaryPath) {
    Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
  }
}
Write-Output ($result | ConvertTo-Json -Compress -Depth 8)
