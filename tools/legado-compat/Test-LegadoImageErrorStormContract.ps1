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
  $FixturePath = Join-Path $RepoRoot 'tools\legado-compat\fixtures\legado-image-error-storm.json'
}
if ([string]::IsNullOrWhiteSpace($ResultPath)) {
  $suffix = if ($ExpectPreFix) { 'pre-fix' } else { 'post-fix' }
  $ResultPath = Join-Path $RepoRoot ("tools\legado-compat\evidence\v2-image-error-storm-contract-20260808-{0}.json" -f $suffix)
}

function Read-Utf8Text {
  param([Parameter(Mandatory = $true)][string]$Path)
  return [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false, $true))
}

function Assert-Contract {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) {
    throw "IMAGE error-storm contract failed: $Message"
  }
  $script:assertions++
}

$assertions = 0
$fixture = $null
$result = $null
try {
  $fixture = (Read-Utf8Text -Path $FixturePath) | ConvertFrom-Json
  Assert-Contract ([string]$fixture.contract -eq 'legado_image_error_storm') 'fixture contract must be explicit'
  Assert-Contract ([string]$fixture.issueId -eq 'ISSUE-COMPAT-014') 'fixture must bind ISSUE-COMPAT-014'
  Assert-Contract ([int]$fixture.baseline.sourceCount -eq 458) 'fixture must bind the frozen source count'
  Assert-Contract ([string]$fixture.baseline.sourcePackageSha256 -eq '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67') 'fixture must bind the frozen source hash'
  Assert-Contract ([int]$fixture.observedEvidence.minimumObservedErrorRecords -ge 180) 'historical error storm must remain recorded'
  Assert-Contract ([int]$fixture.errorFileBudget.maxRetainedFiles -eq 20) 'error-file budget must be explicit and bounded'
  Assert-Contract ([string]$fixture.errorFileBudget.filePrefix -eq 'error_') 'error-file budget must identify the managed file prefix'
  Assert-Contract ([string]$fixture.errorFileBudget.fileSuffix -eq '.txt') 'error-file budget must identify the managed file suffix'
  Assert-Contract ([string]$fixture.errorFileBudget.cleanupPolicy -eq 'delete_oldest_when_count_exceeds_budget') 'error-file cleanup policy must be explicit'

  $coordinatorPath = Join-Path $RepoRoot 'entry\src\main\ets\Framework\Network\NetworkTransportFailureCoordinator.ets'
  $onlineLoaderPath = Join-Path $RepoRoot 'entry\src\main\ets\Framework\Cache\OnlineImageLoader.ets'
  $errorMonitorPath = Join-Path $RepoRoot 'entry\src\main\ets\Framework\Debug\ErrorMonitorService.ets'
  $errorRecordPath = Join-Path $RepoRoot 'entry\src\main\ets\Framework\Debug\ErrorRecordManager.ets'
  $downloadMonitorPath = Join-Path $RepoRoot 'entry\src\main\ets\Framework\Download\DownloadCacheFlowMonitor.ets'
  $readMonitorPath = Join-Path $RepoRoot 'entry\src\main\ets\Framework\Reader\MangaReadFlowMonitor.ets'
  $viewerPath = Join-Path $RepoRoot 'entry\src\main\ets\components\MangaViewer.ets'
  $coordinator = Read-Utf8Text -Path $coordinatorPath
  $onlineLoader = Read-Utf8Text -Path $onlineLoaderPath
  $errorMonitor = Read-Utf8Text -Path $errorMonitorPath
  $errorRecord = Read-Utf8Text -Path $errorRecordPath
  $downloadMonitor = Read-Utf8Text -Path $downloadMonitorPath
  $readMonitor = Read-Utf8Text -Path $readMonitorPath
  $viewer = Read-Utf8Text -Path $viewerPath

  foreach ($sourcePath in @($coordinatorPath, $onlineLoaderPath, $errorMonitorPath, $errorRecordPath, $downloadMonitorPath, $readMonitorPath, $viewerPath)) {
    Assert-Contract (Test-Path -LiteralPath $sourcePath) ("required source path is missing: {0}" -f $sourcePath)
  }
  Assert-Contract ($coordinator.Contains('public extractFingerprint(message: string): string')) 'coordinator must expose one fingerprint parser'
  Assert-Contract ($coordinator.Contains('network_transport|')) 'coordinator must use the URL-free fingerprint namespace'
  Assert-Contract ($coordinator.Contains('claimLedgerRecord')) 'coordinator must expose ledger dedupe'
  Assert-Contract ($coordinator.Contains('claimDiagnosticError')) 'coordinator must expose diagnostic dedupe'
  Assert-Contract ($coordinator.Contains('if (!backgroundRequest || userInitiated)')) 'visible and manual requests must bypass suppression'
  Assert-Contract ($coordinator.Contains('DNS_CIRCUIT_TTL_MS: number = 20 * 1000')) 'DNS circuit TTL must remain bounded'
  Assert-Contract ($coordinator.Contains('TLS_CIRCUIT_TTL_MS: number = 45 * 1000')) 'TLS circuit TTL must remain bounded'
  Assert-Contract ($onlineLoader.Contains('transportFailureCoordinator.shouldSuppress(')) 'online loader must consult the host circuit'
  Assert-Contract ($onlineLoader.Contains('request.options.legadoImageTrace')) 'suppressed background requests must remain traceable'
  Assert-Contract ($onlineLoader.Contains('transportFailure.canonicalMessage')) 'transport failures must propagate canonical marker messages'
  Assert-Contract ($errorMonitor.Contains('claimLedgerRecord(entry.message, now)')) 'error monitor must claim the canonical ledger window'
  Assert-Contract ($errorMonitor.Contains('private cleanOldErrorLogs(): void')) 'error monitor must own bounded error-file cleanup'
  Assert-Contract ($errorMonitor.Contains('if (errorFiles.length <= 20)')) 'error monitor must retain at most the fixture budget'
  Assert-Contract ($errorMonitor.Contains('errorFiles.slice(0, errorFiles.length - 20)')) 'error monitor must delete only files above the budget'
  Assert-Contract (($errorMonitor.Contains('SafeFileUtils.unlinkSync(`${directory}/${fileName}`)') -or $errorMonitor.Contains('SafeFileUtils.unlinkSync(`${this.errorLogsDir}/${fileName}`)'))) 'error monitor must remove oldest managed files from the selected bounded directory'
  Assert-Contract ($errorMonitor.Contains('this.cleanOldErrorLogs();')) 'error-file cleanup must run after a successful error-file write'
  Assert-Contract ($errorRecord.Contains('findRecentNetworkRecord(message, now)')) 'persistent network records must dedupe by fingerprint'
  Assert-Contract ($downloadMonitor.Contains('isRecognizedFailureMessage(event.errorMessage)')) 'download flow must avoid ERROR for recognized transport failures'
  Assert-Contract ($readMonitor.Contains('isRecognizedFailureMessage(event.errorMessage)')) 'read flow must avoid ERROR for recognized transport failures'
  Assert-Contract ($viewer.Contains('isPageCurrentlyVisible(page)')) 'automatic image retry must be visibility-aware'

  foreach ($scenario in @($fixture.failureScenarios)) {
    Assert-Contract ([string]$scenario.expectedFingerprint -match '^network_transport\|[a-z]+\|[^|]+\|[^|]+$') ("{0} expected fingerprint must be URL-free" -f $scenario.name)
    Assert-Contract (@($scenario.ledgerClaims).Count -eq 2) ("{0} must contain two ledger claims" -f $scenario.name)
    Assert-Contract ([bool]$scenario.ledgerClaims[0]) ("{0} first ledger claim must be accepted" -f $scenario.name)
    Assert-Contract (-not [bool]$scenario.ledgerClaims[1]) ("{0} second ledger claim must be deduped" -f $scenario.name)
  }

  # This is intentionally a source contract, not a runtime/device test. The
  # pre-fix run records the missing bare-fingerprint parser before the edit.
  $bareFingerprintProjection = $coordinator.Contains('const bareStart: number = message.indexOf(''network_transport|'')') -and
    $coordinator.Contains('const bareCandidate: string = message.substring(bareStart, bareEnd)')
  if ($ExpectPreFix) {
    Assert-Contract (-not $bareFingerprintProjection) 'pre-fix evidence must prove the bare-fingerprint parser was absent'
  } else {
    Assert-Contract $bareFingerprintProjection 'post-fix source must parse bare fingerprint log projections'
    Assert-Contract ($onlineLoader.Contains('请求最终失败（已按传输根因聚合）: ${transportFailure.canonicalMessage}')) 'final failure log must carry the canonical marker'
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
    contract = 'legado_image_error_storm'
    issueId = 'ISSUE-COMPAT-014'
    phase = if ($ExpectPreFix) { 'failure_contract_pre_fix' } else { 'source_closure_static_verified_pending_r4' }
    assertions = $assertions
    error = $_.Exception.Message
    observedEvidence = if ($null -ne $fixture) { $fixture.observedEvidence } else { $null }
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
