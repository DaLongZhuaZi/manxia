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
  $FixturePath = Join-Path $RepoRoot 'tools\legado-compat\fixtures\legado-image-error-copied-file-cleanup.json'
}
if ([string]::IsNullOrWhiteSpace($ResultPath)) {
  $suffix = if ($ExpectPreFix) { 'pre-fix-r1' } else { 'post-fix-r1' }
  $ResultPath = Join-Path $RepoRoot ("tools\legado-compat\evidence\v2-image-error-copied-file-cleanup-contract-20260808-{0}.json" -f $suffix)
}

function Read-Utf8Text {
  param([Parameter(Mandatory = $true)][string]$Path)
  return [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false, $true))
}

function Assert-Contract {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) {
    throw "IMAGE copied-file cleanup contract failed: $Message"
  }
  $script:assertions++
}

$assertions = 0
$fixture = $null
$result = $null
try {
  $fixture = (Read-Utf8Text -Path $FixturePath) | ConvertFrom-Json
  Assert-Contract ([string]$fixture.contract -eq 'legado_image_error_copied_file_cleanup') 'fixture contract must be explicit'
  Assert-Contract ([string]$fixture.issueId -eq 'ISSUE-COMPAT-014') 'fixture must bind ISSUE-COMPAT-014'
  Assert-Contract ([int]$fixture.baseline.sourceCount -eq 458) 'fixture must bind the frozen source count'
  Assert-Contract ([string]$fixture.baseline.sourcePackageSha256 -eq '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67') 'fixture must bind the frozen source hash'
  Assert-Contract ([string]$fixture.baseline.legadoCommit -eq '95973d186b147fb9ab43a9240021d688e4304fbd') 'fixture must bind the frozen Legado commit'
  Assert-Contract ([int]$fixture.observedEvidence.historicalErrorFiles -ge 78) 'historical copied-file storm must remain recorded'
  Assert-Contract ([string]$fixture.observedEvidence.copySink -eq 'Download/logs') 'copy sink must remain explicit'
  Assert-Contract ([int]$fixture.errorFileBudget.maxRetainedFiles -eq 20) 'file budget must be explicit'
  Assert-Contract ([string]$fixture.errorFileBudget.filePrefix -eq 'error_') 'managed file prefix must be explicit'
  Assert-Contract ([string]$fixture.errorFileBudget.fileSuffix -eq '.txt') 'managed file suffix must be explicit'
  Assert-Contract ([string]$fixture.errorFileBudget.cleanupPhase -eq 'tryCopyToDownload.finally') 'copy cleanup phase must be finally'
  Assert-Contract ([string]$fixture.failureScenario.boundary -eq 'tryCopyToDownload') 'failure scenario must bind the copy boundary'
  Assert-Contract ([int]$fixture.failureScenario.expectedAfterCleanup -eq 20) 'failure scenario must preserve the bounded result'

  $sourcePath = Join-Path $RepoRoot 'entry\src\main\ets\Framework\Debug\ErrorMonitorService.ets'
  Assert-Contract (Test-Path -LiteralPath $sourcePath) 'ErrorMonitorService source must exist'
  $sourceRevision = ''
  if ($ExpectPreFix) {
    $sourceRevision = (& git -C $RepoRoot rev-parse HEAD | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $sourceRevision.Length -eq 0) {
      throw 'cannot resolve frozen HEAD for pre-fix contract'
    }
    $source = (& git -C $RepoRoot show 'HEAD:entry/src/main/ets/Framework/Debug/ErrorMonitorService.ets' | Out-String)
    if ($LASTEXITCODE -ne 0) {
      throw 'cannot read frozen HEAD source for pre-fix contract'
    }
  } else {
    $source = Read-Utf8Text -Path $sourcePath
  }
  $methodStart = $source.IndexOf('private tryCopyToDownload(')
  $methodEnd = $source.IndexOf('private cleanOldErrorLogs()', $methodStart)
  Assert-Contract ($methodStart -ge 0 -and $methodEnd -gt $methodStart) 'copy method must be extractable'
  $method = $source.Substring($methodStart, $methodEnd - $methodStart)
  if ($ExpectPreFix) {
    Assert-Contract (-not $method.Contains('cleanManagedErrorLogs(logsDir)')) 'pre-fix HEAD must prove copied-file finally cleanup was absent'
    Assert-Contract (-not $source.Contains('private cleanManagedErrorLogs(directory: string): void')) 'pre-fix HEAD must prove the shared sink helper was absent'
    Assert-Contract (-not $source.Contains("!f.startsWith('error_detail_')")) 'pre-fix HEAD must prove manual detail reports were not excluded'
    Assert-Contract (-not $source.Contains("!f.startsWith('error_report_')")) 'pre-fix HEAD must prove manual report exports were not excluded'
    Assert-Contract (-not $source.Contains("!f.startsWith('error_logs_')")) 'pre-fix HEAD must prove console log exports were not excluded'
  } else {
    Assert-Contract ($method.Contains("let logsDir: string = ''")) 'copy method must retain the directory for finally cleanup'
    Assert-Contract ($method.Contains("logsDir = downloadDirManager.ensureDirectory('logs')")) 'copy method must bind the managed logs directory'
    Assert-Contract ([regex]::IsMatch($method, '(?s)\}\s*finally\s*\{\s*this\.cleanManagedErrorLogs\(logsDir\);')) 'copy method must clean the sink from finally'
    Assert-Contract ($source.Contains('private cleanManagedErrorLogs(directory: string): void')) 'shared bounded cleanup helper must exist'
    Assert-Contract ($source.Contains("files.filter((f: string) => f.startsWith('error_') && f.endsWith('.txt'))")) 'cleanup must target only managed error files'
    Assert-Contract ($source.Contains("!f.startsWith('error_detail_')")) 'cleanup must preserve manually exported detail reports'
    Assert-Contract ($source.Contains("!f.startsWith('error_report_')")) 'cleanup must preserve manually exported report files'
    Assert-Contract ($source.Contains("!f.startsWith('error_logs_')")) 'cleanup must preserve console log exports'
    Assert-Contract ($source.Contains('if (errorFiles.length <= 20)')) 'cleanup must retain at most the fixture budget'
    Assert-Contract ($source.Contains('errorFiles.slice(0, errorFiles.length - 20)')) 'cleanup must delete only files above the budget'
    Assert-Contract ($source.Contains('SafeFileUtils.unlinkSync(`${directory}/${fileName}`)')) 'cleanup must delete from the selected sink directory'
    Assert-Contract ($source.Contains('private cleanOldErrorLogs(): void')) 'sandbox cleanup wrapper must remain available'
  }

  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    status = 'passed'
    contract = [string]$fixture.contract
    issueId = [string]$fixture.issueId
    phase = if ($ExpectPreFix) { 'failure_contract_pre_fix' } else { 'source_closure_static_verified_pending_r4' }
    assertions = $assertions
    observedEvidence = $fixture.observedEvidence
    sourceRevision = $sourceRevision
    sourceFix = if ($ExpectPreFix) { $null } else { [pscustomobject][ordered]@{
      path = 'entry/src/main/ets/Framework/Debug/ErrorMonitorService.ets'
      sha256 = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
    } }
    semanticMatchAllowed = $false
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  }
} catch {
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    status = 'failed'
    contract = 'legado_image_error_copied_file_cleanup'
    issueId = 'ISSUE-COMPAT-014'
    phase = 'source_closure_static_verified_pending_r4'
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
