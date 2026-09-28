[CmdletBinding()]
param(
  [string]$RepoRoot = '',
  [string]$FixturePath = '',
  [string]$ResultPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path }
if ([string]::IsNullOrWhiteSpace($FixturePath)) { $FixturePath = Join-Path $RepoRoot 'tools\legado-compat\fixtures\hypium-source-workflow-evidence-projection.json' }
if ([string]::IsNullOrWhiteSpace($ResultPath)) { $ResultPath = Join-Path $RepoRoot 'tools\legado-compat\evidence\v2-source-workflow-evidence-projection-contract.json' }
$assertions = 0
function Assert-Contract {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "Source workflow evidence projection contract failed: $Message" }
  $script:assertions++
}
function Write-ContractJson {
  param([string]$Path, [object]$Value)
  [System.IO.File]::WriteAllText($Path, [string]($Value | ConvertTo-Json -Depth 32), [System.Text.UTF8Encoding]::new($false))
}
try {
  $runnerPath = Join-Path $RepoRoot 'tools\legado-compat\Invoke-LegadoV2HypiumFullSourceDeviceRunner.ps1'
  $auditPath = Join-Path $RepoRoot 'tools\legado-compat\Test-LegadoV2HypiumFullSourceEvidence.ps1'
  $runnerText = [System.IO.File]::ReadAllText($runnerPath, [System.Text.UTF8Encoding]::new($false, $true))
  $auditText = [System.IO.File]::ReadAllText($auditPath, [System.Text.UTF8Encoding]::new($false, $true))
  $fixture = [System.IO.File]::ReadAllText($FixturePath, [System.Text.UTF8Encoding]::new($false, $true)) | ConvertFrom-Json
  $writerStart = $runnerText.IndexOf('function Write-HypiumSourceEvidence', [System.StringComparison]::Ordinal)
  $writerEnd = $runnerText.IndexOf('function Invoke-HypiumRecord', [System.StringComparison]::Ordinal)
  $writerText = if ($writerStart -ge 0 -and $writerEnd -gt $writerStart) { $runnerText.Substring($writerStart, $writerEnd - $writerStart) } else { '' }
  Assert-Contract $runnerText.Contains('workflowEvidence') 'runner must persist structured workflowEvidence'
  Assert-Contract $runnerText.Contains('sourceAttempt') 'source evidence must persist source attempt binding'
  Assert-Contract $runnerText.Contains('workflowAttempts') 'source evidence must persist per-workflow attempt bindings'
  Assert-Contract $runnerText.Contains('Get-HypiumWorkflowEvidence') 'structured projection must be generated from workflow matrix'
  Assert-Contract $runnerText.Contains('traceDigest') 'workflow projection must retain the digest of the actual trace'
  Assert-Contract $runnerText.Contains('Get-LegadoSha256ForText -Value $outputSummary') 'empty Explore output must still receive a SHA-256 witness'
  Assert-Contract $runnerText.Contains('if ($sourceAttempts -ne $maximumWorkflowAttempt)') 'source attempt reconciliation must handle both greater-than and less-than stale values'
  Assert-Contract $runnerText.Contains('Set-HypiumProperty -Object $Record -Name ''attempts'' -Value $maximumWorkflowAttempt') 'source attempt must be reconciled in both directions'
  Assert-Contract $writerText.Contains('Sync-HypiumSourceAttempt -State $State -Record $Record') 'every evidence emission path must reconcile source attempt before projection'
  foreach ($requiredFailureCode in @(
    'SOURCE_ATTEMPT_NOT_EQUAL_WORKFLOW_MAX',
    'WORKFLOW_ATTEMPT_BINDING_MISMATCH',
    'WORKFLOW_TRACE_DIGEST_INVALID',
    'WORKFLOW_DIGEST_WITHOUT_TRACE',
    'WORKFLOW_EVIDENCE_TRACE_PRESENCE_MISMATCH',
    'WORKFLOW_EVIDENCE_DIGEST_MISMATCH'
  )) {
    Assert-Contract $auditText.Contains($requiredFailureCode) "evidence audit must reject $requiredFailureCode"
  }
  $names = @($fixture.workflows.PSObject.Properties.Name)
  Assert-Contract ($names.Count -eq 7) 'fixture must cover seven workflows'
  Assert-Contract ([int]$fixture.sourceAttempt -eq 1) 'fixture source attempt must be explicit'
  $attemptEvidence = $fixture.sourceAttemptEvidence
  Assert-Contract ([int]$attemptEvidence.sourceAttempt -eq [int]$fixture.sourceAttempt) 'source attempt evidence must bind the source attempt'
  Assert-Contract ([int]$attemptEvidence.searchAttempt -eq [int]$fixture.workflows.search.attempts) 'legacy searchAttempt must remain bound to search'
  $attemptNames = @($attemptEvidence.workflowAttempts.PSObject.Properties.Name)
  Assert-Contract ($attemptNames.Count -eq 7) 'workflow attempt evidence must cover seven workflows'
  Assert-Contract (@($names | Where-Object { $attemptNames -notcontains $_ }).Count -eq 0) 'workflow attempt evidence must contain every workflow name'
  Assert-Contract (@($attemptNames | Where-Object { $names -notcontains $_ }).Count -eq 0) 'workflow attempt evidence must not contain an unowned workflow name'
  $maximumAttempt = 0
  foreach ($name in $names) {
    $item = $fixture.workflows.PSObject.Properties[$name].Value
    Assert-Contract (-not [string]::IsNullOrWhiteSpace([string]$item.status)) "$name status required"
    Assert-Contract (-not [string]::IsNullOrWhiteSpace([string]$item.outcome)) "$name outcome required"
    Assert-Contract ([int]$item.attempts -ge 0) "$name attempts required"
    if ([int]$item.attempts -gt $maximumAttempt) { $maximumAttempt = [int]$item.attempts }
    Assert-Contract (-not [string]::IsNullOrWhiteSpace([string]$item.result)) "$name result required"
    Assert-Contract ([int]$attemptEvidence.workflowAttempts.PSObject.Properties[$name].Value -eq [int]$item.attempts) "$name attempt binding required"
    $digest = [string]$item.evidenceDigest
    $traceDigest = [string]$item.traceDigest
    if ([bool]$item.tracePresent) {
      Assert-Contract ($digest -match '^[0-9a-fA-F]{64}$') "$name trace requires evidence SHA-256"
      Assert-Contract ($traceDigest -match '^[0-9a-fA-F]{64}$') "$name trace requires trace SHA-256"
      Assert-Contract ($digest -eq $traceDigest) "$name evidence and trace digests must match"
    } else {
      Assert-Contract ([string]::IsNullOrWhiteSpace($digest)) "$name without trace must not retain evidence digest"
      Assert-Contract ([string]::IsNullOrWhiteSpace($traceDigest)) "$name without trace must not retain trace digest"
    }
  }
  Assert-Contract ([int]$fixture.sourceAttempt -eq $maximumAttempt) 'source attempt must equal maximum workflow attempt'
  foreach ($scenarioName in @('sourceAttemptLessThanWorkflowMax', 'sourceAttemptGreaterThanWorkflowMax')) {
    $scenario = $fixture.sourceAttemptScenarios.PSObject.Properties[$scenarioName].Value
    Assert-Contract ([int]$scenario.expectedReconciledSourceAttempt -eq [int]$scenario.workflowMaximumAttempt) "$scenarioName must reconcile to workflow maximum"
    Assert-Contract ([int]$scenario.sourceAttemptBefore -ne [int]$scenario.expectedReconciledSourceAttempt) "$scenarioName must exercise reconciliation"
  }
  Assert-Contract ([bool]$fixture.workflows.search.tracePresent) 'search trace witness must be present'
  Assert-Contract (-not [bool]$fixture.workflows.explore.tracePresent) 'unexecuted explore must not inherit search trace'
  Assert-Contract ([string]$fixture.trace.workflow -eq 'search') 'top-level trace must identify its workflow'
  Assert-Contract ([string]$fixture.trace.outputSummarySha256 -match '^[0-9a-fA-F]{64}$') 'top-level trace must carry a SHA-256 digest'
  Assert-Contract ([string]$fixture.trace.outputSummarySha256 -eq [string]$fixture.workflows.search.traceDigest) 'top-level trace must bind to search trace digest'
  $missingDigest = $fixture.digestScenarios.tracePresentWithoutDigest
  Assert-Contract ([bool]$missingDigest.tracePresent -and [string]::IsNullOrWhiteSpace([string]$missingDigest.traceDigest)) 'negative trace-without-digest scenario must remain invalid'
  $orphanDigest = $fixture.digestScenarios.digestWithoutTrace
  Assert-Contract (-not [bool]$orphanDigest.tracePresent -and -not [string]::IsNullOrWhiteSpace([string]$orphanDigest.evidenceDigest)) 'negative digest-without-trace scenario must remain invalid'

  $workflowResults = [ordered]@{}
  $workflowEvidence = [ordered]@{}
  foreach ($name in $names) {
    $item = $fixture.workflows.PSObject.Properties[$name].Value
    $workflowResults[$name] = [string]$item.result
    $workflowEvidence[$name] = $item
  }
  $validEvidence = [pscustomobject][ordered]@{
    schemaVersion = 2
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    runId = 'fixture-run'
    sourcePackageSha256 = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
    legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
    sourceId = 'fixture-source'
    ordinal = 0
    status = 'blocked'
    outcome = 'empty_without_reference'
    driverClosed = $true
    runnerStatus = 'passed'
    trace = $fixture.trace
    sourceAttempt = [int]$fixture.sourceAttempt
    sourceAttemptEvidence = $attemptEvidence
    workflowResults = [pscustomobject]$workflowResults
    workflowStatusMatrix = $fixture.workflows
    workflowEvidence = [pscustomobject]$workflowEvidence
  }
  $temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('legado-v2-harness-contract-' + [Guid]::NewGuid().ToString('N'))
  $temporaryEvidenceDirectory = Join-Path $temporaryRoot 'evidence'
  $temporaryStatePath = Join-Path $temporaryRoot 'state.json'
  $validResultPath = Join-Path $temporaryRoot 'valid-result.json'
  $invalidResultPath = Join-Path $temporaryRoot 'invalid-result.json'
  [void][System.IO.Directory]::CreateDirectory($temporaryEvidenceDirectory)
  try {
    Write-ContractJson -Path (Join-Path $temporaryEvidenceDirectory 'source-fixture-source.json') -Value $validEvidence
    Write-ContractJson -Path $temporaryStatePath -Value ([pscustomobject][ordered]@{
      sources = @([pscustomobject][ordered]@{ ordinal = 0; sourceId = 'fixture-source'; status = 'blocked' })
    })
    & pwsh -NoLogo -NoProfile -File $auditPath `
      -EvidenceDirectory $temporaryEvidenceDirectory `
      -StatePath $temporaryStatePath `
      -ExpectedSourceCount 1 `
      -ResultPath $validResultPath `
      -DisableEvidenceOverlay | Out-Null
    $validExitCode = $LASTEXITCODE
    $validAudit = Get-Content -Raw -Encoding UTF8 $validResultPath | ConvertFrom-Json
    Assert-Contract ($validExitCode -eq 0 -and [string]$validAudit.status -eq 'passed') 'valid fixture must pass the full evidence audit'

    $invalidEvidence = Get-Content -Raw -Encoding UTF8 (Join-Path $temporaryEvidenceDirectory 'source-fixture-source.json') | ConvertFrom-Json
    $invalidEvidence.workflowStatusMatrix.search.traceDigest = ''
    $invalidEvidence.workflowEvidence.search.traceDigest = ''
    $invalidEvidence.sourceAttempt = 7
    $invalidEvidence.sourceAttemptEvidence.sourceAttempt = 7
    Write-ContractJson -Path (Join-Path $temporaryEvidenceDirectory 'source-fixture-source.json') -Value $invalidEvidence
    & pwsh -NoLogo -NoProfile -File $auditPath `
      -EvidenceDirectory $temporaryEvidenceDirectory `
      -StatePath $temporaryStatePath `
      -ExpectedSourceCount 1 `
      -ResultPath $invalidResultPath `
      -DisableEvidenceOverlay | Out-Null
    $invalidExitCode = $LASTEXITCODE
    $invalidAudit = Get-Content -Raw -Encoding UTF8 $invalidResultPath | ConvertFrom-Json
    $invalidCodes = @($invalidAudit.failures | ForEach-Object { [string]$_.code })
    Assert-Contract ($invalidExitCode -ne 0 -and [string]$invalidAudit.status -eq 'failed') 'invalid fixture must fail the full evidence audit'
    Assert-Contract ($invalidCodes -contains 'WORKFLOW_TRACE_DIGEST_INVALID') 'invalid trace digest must be reported by the audit'
    Assert-Contract ($invalidCodes -contains 'SOURCE_ATTEMPT_NOT_EQUAL_WORKFLOW_MAX') 'stale source attempt must be rejected by the audit'
  } finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
      Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
  }
  $result = [pscustomobject][ordered]@{ schemaVersion = 1; status = 'passed'; contract = [string]$fixture.contract; assertions = $assertions; generatedAt = [DateTimeOffset]::UtcNow.ToString('o') }
} catch {
  $result = [pscustomobject][ordered]@{ schemaVersion = 1; status = 'failed'; contract = 'source_workflow_evidence_projection_closed_matrix'; assertions = $assertions; error = $_.Exception.Message; generatedAt = [DateTimeOffset]::UtcNow.ToString('o') }
}
$directory = Split-Path -Parent $ResultPath
if (-not (Test-Path -LiteralPath $directory)) { [void][System.IO.Directory]::CreateDirectory($directory) }
[System.IO.File]::WriteAllText($ResultPath, [string]($result | ConvertTo-Json -Depth 12), [System.Text.UTF8Encoding]::new($false))
$result | ConvertTo-Json -Compress
if ($result.status -ne 'passed') { exit 1 }
