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
  $FixturePath = Join-Path $RepoRoot 'tools\legado-compat\fixtures\legado-image-error-file-cleanup.json'
}
if ([string]::IsNullOrWhiteSpace($ResultPath)) {
  $suffix = if ($ExpectPreFix) { 'pre-fix' } else { 'post-fix' }
  $ResultPath = Join-Path $RepoRoot ("tools\legado-compat\evidence\v2-image-error-file-cleanup-contract-20260808-{0}-r1.json" -f $suffix)
}

function Read-Utf8Text {
  param([Parameter(Mandatory = $true)][string]$Path)
  return [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false, $true))
}

function Assert-Contract {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) {
    throw "IMAGE error-file cleanup contract failed: $Message"
  }
  $script:assertions++
}

$assertions = 0
$fixture = $null
$result = $null
try {
  $fixture = (Read-Utf8Text -Path $FixturePath) | ConvertFrom-Json
  Assert-Contract ([string]$fixture.contract -eq 'legado_image_error_file_cleanup') 'fixture contract must be explicit'
  Assert-Contract ([string]$fixture.issueId -eq 'ISSUE-COMPAT-014') 'fixture must bind ISSUE-COMPAT-014'
  Assert-Contract ([int]$fixture.baseline.sourceCount -eq 458) 'fixture must bind the frozen source count'
  Assert-Contract ([string]$fixture.baseline.sourcePackageSha256 -eq '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67') 'fixture must bind the frozen source hash'
  Assert-Contract ([string]$fixture.baseline.legadoCommit -eq '95973d186b147fb9ab43a9240021d688e4304fbd') 'fixture must bind the frozen Legado commit'
  Assert-Contract ([int]$fixture.observedEvidence.historicalErrorFiles -ge 78) 'historical error-file storm must remain recorded'
  Assert-Contract ([int]$fixture.errorFileBudget.maxRetainedFiles -eq 20) 'file budget must be explicit'
  Assert-Contract ([string]$fixture.errorFileBudget.filePrefix -eq 'error_') 'managed file prefix must be explicit'
  Assert-Contract ([string]$fixture.errorFileBudget.fileSuffix -eq '.txt') 'managed file suffix must be explicit'
  Assert-Contract ([string]$fixture.errorFileBudget.requiredFailurePhase -eq 'finally') 'failure cleanup phase must be finally'
  Assert-Contract ([string]$fixture.failureScenario.boundary -eq 'writeFileWithRetry') 'failure scenario must bind the write retry boundary'

  $sourcePath = Join-Path $RepoRoot 'entry\src\main\ets\Framework\Debug\ErrorMonitorService.ets'
  $source = Read-Utf8Text -Path $sourcePath
  Assert-Contract (Test-Path -LiteralPath $sourcePath) 'ErrorMonitorService source must exist'
  $methodStart = $source.IndexOf('private writeErrorLogFile(')
  $methodEnd = $source.IndexOf('private tryCopyToDownload(', $methodStart)
  Assert-Contract ($methodStart -ge 0 -and $methodEnd -gt $methodStart) 'writeErrorLogFile method must be extractable'
  $method = $source.Substring($methodStart, $methodEnd - $methodStart)
  Assert-Contract ($method.Contains('this.writeFileWithRetry(sandboxPath, content);')) 'write failure boundary must remain covered'
  Assert-Contract ($source.Contains('const errorFiles = files.filter((f: string) => f.startsWith(''error_'') && f.endsWith(''.txt''))')) 'cleanup must target only managed error files'
  Assert-Contract ($source.Contains('errorFiles.slice(0, errorFiles.length - 20)')) 'cleanup must preserve the file budget'

  $cleanupInFinally = [regex]::IsMatch($method, '(?s)\}\s*finally\s*\{\s*this\.cleanOldErrorLogs\(\);')
  if ($ExpectPreFix) {
    Assert-Contract (-not $cleanupInFinally) 'pre-fix source must lack finally cleanup after a write failure'
  } else {
    Assert-Contract $cleanupInFinally 'post-fix source must clean managed files from finally'
    Assert-Contract ([regex]::IsMatch($method, '(?s)\}\s*catch \(error\).*?\}\s*finally\s*\{') ) 'cleanup finally must follow the write-error catch'
  }

  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    status = 'passed'
    contract = [string]$fixture.contract
    issueId = [string]$fixture.issueId
    phase = if ($ExpectPreFix) { 'failure_contract_pre_fix' } else { 'source_closure_static_verified_pending_r4' }
    assertions = $assertions
    observedEvidence = $fixture.observedEvidence
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  }
} catch {
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    status = 'failed'
    contract = 'legado_image_error_file_cleanup'
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
