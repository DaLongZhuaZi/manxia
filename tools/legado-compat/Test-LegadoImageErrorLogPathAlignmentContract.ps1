[CmdletBinding()]
param(
  [string]$RepoRoot = '',
  [string]$FixturePath = '',
  [string]$ResultPath = '',
  [switch]$ExpectPreFix
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
if ([string]::IsNullOrWhiteSpace($FixturePath)) {
  $FixturePath = Join-Path $RepoRoot 'tools\legado-compat\fixtures\legado-image-error-log-path-alignment.json'
}
if ([string]::IsNullOrWhiteSpace($ResultPath)) {
  $suffix = if ($ExpectPreFix) { 'pre-fix-r1' } else { 'post-fix-r1' }
  $ResultPath = Join-Path $RepoRoot ("tools\legado-compat\evidence\v2-image-error-log-path-alignment-contract-20260808-{0}.json" -f $suffix)
}

function Read-Utf8Text {
  param([Parameter(Mandatory = $true)][string]$Path)
  return [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false, $true))
}

function Assert-Contract {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) {
    throw "IMAGE error-log path alignment contract failed: $Message"
  }
  $script:assertions++
}

$assertions = 0
$fixture = $null
$result = $null
try {
  $fixture = (Read-Utf8Text -Path $FixturePath) | ConvertFrom-Json
  Assert-Contract ([string]$fixture.contract -eq 'legado_image_error_log_path_alignment') 'fixture contract must be explicit'
  Assert-Contract ([string]$fixture.issueId -eq 'ISSUE-COMPAT-014') 'fixture must bind ISSUE-COMPAT-014'
  Assert-Contract ([int]$fixture.baseline.sourceCount -eq 458) 'fixture must bind the frozen source count'
  Assert-Contract ([string]$fixture.baseline.sourcePackageSha256 -eq '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67') 'fixture must bind the frozen source hash'
  Assert-Contract ([string]$fixture.baseline.legadoCommit -eq '95973d186b147fb9ab43a9240021d688e4304fbd') 'fixture must bind the frozen Legado commit'
  Assert-Contract ([string]$fixture.producer.pathContract -eq 'DownloadDirManager.getManagedRootPath(false)/logs') 'producer path contract must remain explicit'
  Assert-Contract ([string]$fixture.consumer.requiredPathContract -eq 'DownloadDirManager.getManagedRootPath(false)/logs') 'consumer path contract must remain explicit'
  Assert-Contract ([bool]$fixture.failureScenario.mustNotUseRawPickerRoot) 'raw picker root must be rejected by the fixture'

  $sourcePath = Join-Path $RepoRoot 'entry\src\main\ets\pages\settings\ErrorManagementSubPage.ets'
  Assert-Contract (Test-Path -LiteralPath $sourcePath) 'ErrorManagementSubPage source must exist'
  $sourceRevision = ''
  if ($ExpectPreFix) {
    $sourceRevision = (& git -C $RepoRoot rev-parse HEAD | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $sourceRevision.Length -eq 0) {
      throw 'cannot resolve frozen HEAD for pre-fix contract'
    }
    $source = (& git -C $RepoRoot show 'HEAD:entry/src/main/ets/pages/settings/ErrorManagementSubPage.ets' | Out-String)
    if ($LASTEXITCODE -ne 0) {
      throw 'cannot read frozen HEAD source for pre-fix contract'
    }
  } else {
    $source = Read-Utf8Text -Path $sourcePath
  }
  $methodStart = $source.IndexOf('private resolveKnownLogDirs(): KnownLogDirs')
  $methodEnd = $source.IndexOf('private getSandboxFilesDir(): string', $methodStart)
  Assert-Contract ($methodStart -ge 0 -and $methodEnd -gt $methodStart) 'log directory resolver must be extractable'
  $method = $source.Substring($methodStart, $methodEnd - $methodStart)
  if ($ExpectPreFix) {
    Assert-Contract ($method.Contains('downloadDirManager.getPath()')) 'pre-fix HEAD must prove the raw picker root was used'
    Assert-Contract (-not $method.Contains('getManagedRootPath(false)')) 'pre-fix HEAD must lack the managed root projection'
  } else {
    Assert-Contract ($method.Contains('const downloadRoot = downloadDirManager.isReady() ? downloadDirManager.getManagedRootPath(false) : ')) 'consumer must resolve the managed Download root'
    Assert-Contract ($method.Contains('const downloadLogsDir = downloadRoot.length > 0 ? `${downloadRoot}/logs` : ')) 'consumer must append logs to the managed root'
    Assert-Contract (-not $method.Contains('`${downloadDirManager.getPath()}/logs`')) 'consumer must not use the raw picker root'
  }

  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    status = 'passed'
    contract = [string]$fixture.contract
    issueId = [string]$fixture.issueId
    phase = if ($ExpectPreFix) { 'failure_contract_pre_fix' } else { 'source_closure_static_verified_pending_r4' }
    assertions = $assertions
    sourceRevision = $sourceRevision
    sourceFix = if ($ExpectPreFix) { $null } else { [pscustomobject][ordered]@{
      path = 'entry/src/main/ets/pages/settings/ErrorManagementSubPage.ets'
      sha256 = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
    } }
    semanticMatchAllowed = $false
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  }
} catch {
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    status = 'failed'
    contract = 'legado_image_error_log_path_alignment'
    issueId = 'ISSUE-COMPAT-014'
    phase = if ($ExpectPreFix) { 'failure_contract_pre_fix' } else { 'source_closure_static_verified_pending_r4' }
    assertions = $assertions
    error = $_.Exception.Message
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  }
}

$resultDirectory = Split-Path -Parent $ResultPath
if (-not (Test-Path -LiteralPath $resultDirectory)) {
  [void][System.IO.Directory]::CreateDirectory($resultDirectory)
}
[System.IO.File]::WriteAllText($ResultPath, [string]($result | ConvertTo-Json -Depth 20), [System.Text.UTF8Encoding]::new($false))
$result | ConvertTo-Json -Compress
if ($result.status -ne 'passed') { exit 1 }
