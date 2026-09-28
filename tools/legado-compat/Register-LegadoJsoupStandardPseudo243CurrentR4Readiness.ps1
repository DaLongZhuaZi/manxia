[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$ContractPath = 'tools/legado-compat/evidence/contract-legado-jsoup-standard-pseudo-243-current-r4-readiness-20260813.json',
  [string]$RegistrationEvidencePath = 'tools/legado-compat/evidence/v2-jsoup-standard-pseudo-243-current-r4-readiness-registration-20260813.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
$taskId = 'COMPAT-006'
$revision = '2026-08-13-issue-243-current-r4-readiness-ledger-79-41-38'

function Get-RepoPath {
  param([Parameter(Mandatory = $true)][string]$Path)
  if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }
  return Join-Path $RepositoryRoot ($Path.Replace('/', '\'))
}

function Read-StrictText {
  param([Parameter(Mandatory = $true)][string]$Path)
  $resolved = Get-RepoPath -Path $Path
  if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "required file is missing: $Path" }
  $bytes = [System.IO.File]::ReadAllBytes($resolved)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw "UTF-8 BOM is not allowed: $Path"
  }
  return $strictUtf8.GetString($bytes)
}

function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$Path)
  return Read-StrictText -Path $Path | ConvertFrom-Json -Depth 100
}

function Set-PropertyValue {
  param(
    [Parameter(Mandatory = $true)][object]$Object,
    [Parameter(Mandatory = $true)][string]$Name,
    [AllowNull()][object]$Value
  )
  if ($null -eq $Object.PSObject.Properties[$Name]) {
    $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
  } else {
    $Object.$Name = $Value
  }
}

function Write-AtomicJson {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][object]$Value
  )
  $resolved = Get-RepoPath -Path $Path
  $directory = Split-Path -Parent $resolved
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  }
  $temporary = "$resolved.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8)
    Move-Item -LiteralPath $temporary -Destination $resolved -Force
  } finally {
    if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) }
  }
}

function Assert-Gate {
  param(
    [Parameter(Mandatory = $true)][bool]$Condition,
    [Parameter(Mandatory = $true)][string]$Detail
  )
  if (-not $Condition) { throw "243 current readiness registration failed: $Detail" }
}

$statePath = 'tools/legado-compat/state/full-source-validation-state.json'
$objectivePath = 'tools/legado-compat/state/refactor-objective.json'
$contractScriptPath = 'tools/legado-compat/Test-LegadoJsoupStandardPseudo243CurrentR4ReadinessContract.ps1'
$registerScriptPath = 'tools/legado-compat/Register-LegadoJsoupStandardPseudo243CurrentR4Readiness.ps1'
$historicalScriptPath = 'tools/legado-compat/Test-LegadoJsoupStandardPseudo243R4ReadinessContract.ps1'
$historicalEvidencePath = 'tools/legado-compat/evidence/contract-legado-jsoup-standard-pseudo-243-r4-readiness-20260810.json'
$textProjectionEvidencePath = 'tools/legado-compat/evidence/v2-jsoup-terminal-text-projection-source-fix-20260811.json'
$state = Read-StrictJson -Path $statePath
$objective = Read-StrictJson -Path $objectivePath
$contract = Read-StrictJson -Path $ContractPath
$issue = @($state.governance.issues | Where-Object { [string]$_.id -eq $issueId }) | Select-Object -First 1

Assert-Gate (
  [string]$state.governance.status -eq 'running' -and
  [string]$state.governance.activeTaskId -eq $taskId -and
  [string]$state.governance.activeIssueId -eq $issueId -and
  $null -ne $issue -and [string]$issue.status -eq 'verifying'
) '243 is not the sole verifying issue under COMPAT-006.'
Assert-Gate (
  [string]$contract.status -eq 'passed_static_only' -and
  [int]$contract.currentLedger.subtaskCount -eq 79 -and
  [int]$contract.currentLedger.completedCount -eq 41 -and
  [int]$contract.currentLedger.deferredCount -eq 38 -and
  [int]$contract.currentLedger.completedEvidenceCount -eq 172
) 'current readiness contract is missing the 79/41/38 ledger or its 172 evidence bindings.'
Assert-Gate (
  -not [bool]$contract.semanticMatchAllowed -and
  @($contract.runtimeActionsPerformed).Count -eq 0 -and
  -not [bool]$state.governance.semanticMatchAllowed -and
  @($state.governance.runtimeActionsPerformed).Count -eq 0
) 'static readiness attempted to unlock runtime semantic qualification.'
Assert-Gate (
  [string]$contract.requiredBindings.terminalTextProjectionStatic -eq '243-SP-75' -and
  [string]$contract.requiredBindings.terminalTextProjectionR4 -eq '243-SP-76'
) 'terminal text projection readiness bindings are absent.'

$registrationPath = Get-RepoPath -Path $RegistrationEvidencePath
if ([string]$objective.targetRevision -eq $revision -and (Test-Path -LiteralPath $registrationPath -PathType Leaf)) {
  [pscustomobject][ordered]@{
    status = 'already_registered'
    issueId = $issueId
    targetRevision = $revision
    contractPath = $ContractPath
    registrationEvidencePath = $RegistrationEvidencePath
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    idempotent = $true
  } | ConvertTo-Json -Depth 100
  return
}

$registration = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'static_readiness_ledger_registration'
  issueId = $issueId
  status = 'registered_static_only'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  targetRevision = $revision
  contractPath = $ContractPath
  contractSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath (Get-RepoPath -Path $ContractPath)).Hash.ToUpperInvariant()
  currentLedger = $contract.currentLedger
  requiredBindings = $contract.requiredBindings
  historicalSnapshot = $contract.historicalSnapshot
  correction = [pscustomobject][ordered]@{
    problem = 'The immutable 2026-08-10 readiness snapshot still represented 71/37/34 after four later static source-closure pairs extended the authoritative continuation plan.'
    resolution = 'Keep the historical snapshot unchanged and register a separate current pointer bound to the authoritative 79/41/38 ledger, including 243-SP-75/76.'
    historicalSnapshotOverwritten = $false
  }
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'static_readiness_ledger_only;R4_runtime_build_device_harness_and_legado_diff_remain_deferred'
}
Write-AtomicJson -Path $RegistrationEvidencePath -Value $registration

$now = [DateTimeOffset]::UtcNow.ToString('o')
Set-PropertyValue -Object $objective -Name 'lastReviewedAt' -Value $now
Set-PropertyValue -Object $objective -Name 'targetRevision' -Value $revision
Set-PropertyValue -Object $objective -Name 'continuationMode' -Value 'R3_ISSUE_243_CURRENT_R4_READINESS_LEDGER_REGISTERED_WAIT_R4'
Set-PropertyValue -Object $objective.authority -Name 'activeIssueId' -Value $issueId
Set-PropertyValue -Object $objective.authority -Name 'activeIssueSelection' -Value 'full-source-validation-state.json remains authoritative. 243 is the sole verifying source issue; current R4 readiness is 79/41/38 and does not authorize runtime semantic qualification.'
Set-PropertyValue -Object $objective.executionTarget -Name 'statement' -Value 'The authoritative 243 static queue is 79 total, 41 completed and 38 explicitly deferred to R4. The 2026-08-10 71/37/34 evidence remains an immutable historical snapshot.'
Set-PropertyValue -Object $objective -Name 'nextAction' -Value 'Keep 243 as the sole active issue and use its 38 deferred subitems as the exact future R4 queue; continue source-only governance without activating 244 until the queue transition is explicitly recorded.'
Set-PropertyValue -Object $objective -Name 'currentR4Readiness' -Value ([pscustomobject][ordered]@{
    status = 'passed_static_only'
    evidencePath = $ContractPath
    registrationEvidencePath = $RegistrationEvidencePath
    subtaskCount = 79
    completedCount = 41
    deferredCount = 38
    completedEvidenceCount = 172
    historicalEvidencePath = $historicalEvidencePath
    historicalDisposition = 'immutable_historical_snapshot'
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    updatedAt = $now
  })
Write-AtomicJson -Path $objectivePath -Value $objective

$evidence = @(
  $ContractPath,
  $RegistrationEvidencePath,
  $contractScriptPath,
  $registerScriptPath,
  $historicalScriptPath,
  $historicalEvidencePath,
  $textProjectionEvidencePath
)
$summary = 'ISSUE-COMPAT-243 current static R4 readiness is reconciled to the authoritative 79-subitem ledger: 41 source-closed items, 38 explicit R4 deferrals and 172 existing evidence bindings. The immutable 2026-08-10 snapshot remains 71/37/34; semanticMatchAllowed stays false.'
$closeCondition = 'Execute the 38 deferred R4 subitems with their exact fixtures and affected-source sets through app runtime, deterministic 458-source Harness, fixed-Legado differential, build and device gates; no static readiness evidence alone may close 243.'
$updateScript = Get-RepoPath -Path 'tools/legado-compat/Update-LegadoGovernanceState.ps1'
$updateOutput = & (Get-Command pwsh).Source -NoLogo -NoProfile -NonInteractive -File $updateScript -StatePath (Get-RepoPath -Path $statePath) -IssueId $issueId -IssueStatus verifying -TaskId $taskId -TaskStatus running -Summary $summary -CloseCondition $closeCondition -EvidencePath ([string]::Join(',', $evidence)) 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
  throw ('Update-LegadoGovernanceState failed:' + [Environment]::NewLine + $updateOutput)
}

[pscustomobject][ordered]@{
  status = 'registered'
  issueId = $issueId
  targetRevision = $revision
  contractPath = $ContractPath
  registrationEvidencePath = $RegistrationEvidencePath
  currentLedger = $contract.currentLedger
  governanceUpdate = $updateOutput.Trim()
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
} | ConvertTo-Json -Depth 100
