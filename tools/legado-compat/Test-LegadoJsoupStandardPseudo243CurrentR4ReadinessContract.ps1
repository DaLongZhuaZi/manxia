[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$OutputPath = 'tools/legado-compat/evidence/contract-legado-jsoup-standard-pseudo-243-current-r4-readiness-20260813.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$baselineHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
$taskId = 'COMPAT-006'
$historicalScriptPath = 'tools/legado-compat/Test-LegadoJsoupStandardPseudo243R4ReadinessContract.ps1'
$historicalEvidencePath = 'tools/legado-compat/evidence/contract-legado-jsoup-standard-pseudo-243-r4-readiness-20260810.json'
$historicalScriptHash = 'D0BEE7051D7A310026D054397A7997FBB2AD8C27C82ACC798A8A5FFD72E50C8A'
$historicalEvidenceHash = '4A256474431C8F6AC4CB52F578FA5F2C6ED5F10436FD2FD61330214BAADF7B62'
$script:assertions = 0
$script:checks = New-Object 'System.Collections.Generic.List[object]'

function Get-RepoPath {
  param([Parameter(Mandatory = $true)][string]$Path)
  if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }
  return Join-Path $RepositoryRoot ($Path.Replace('/', '\'))
}

function Read-StrictText {
  param([Parameter(Mandatory = $true)][string]$Path)
  $resolved = Get-RepoPath -Path $Path
  if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "Missing file: $Path" }
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

function Write-AtomicJson {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][object]$Value
  )
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  }
  $temporary = "$Path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8)
    Move-Item -LiteralPath $temporary -Destination $Path -Force
  } finally {
    if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) }
  }
}

function Add-Check {
  param(
    [Parameter(Mandatory = $true)][string]$Id,
    [Parameter(Mandatory = $true)][bool]$Passed,
    [Parameter(Mandatory = $true)][string]$Detail
  )
  [void]$script:checks.Add([pscustomobject][ordered]@{ id = $Id; passed = $Passed; detail = $Detail })
  $script:assertions++
  if (-not $Passed) { throw "243 current R4 readiness failed: $Id; $Detail" }
}

function Get-Sha256 {
  param([Parameter(Mandatory = $true)][string]$Path)
  return (Get-FileHash -Algorithm SHA256 -LiteralPath (Get-RepoPath -Path $Path)).Hash.ToUpperInvariant()
}

$outputFullPath = [System.IO.Path]::GetFullPath((Get-RepoPath -Path $OutputPath))
$evidenceRoot = [System.IO.Path]::GetFullPath((Get-RepoPath -Path 'tools/legado-compat/evidence')).TrimEnd('\') + '\'
if (-not $outputFullPath.StartsWith($evidenceRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw 'Current R4 readiness evidence must remain under the evidence directory.'
}

$result = $null
$exitCode = 0
try {
  $state = Read-StrictJson -Path 'tools/legado-compat/state/full-source-validation-state.json'
  $objective = Read-StrictJson -Path 'tools/legado-compat/state/refactor-objective.json'
  $plan = @($objective.continuationPlan | Where-Object { [string]$_.id -like '243-*' })

  Add-Check 'baseline' (
    [int]$state.baseline.sourceCount -eq 458 -and
    [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and
    [string]$state.baseline.legadoCommit -eq $legadoCommit -and
    [int]$objective.baseline.sourceCount -eq 458 -and
    [string]$objective.baseline.sourcePackageSha256 -eq $baselineHash -and
    [string]$objective.baseline.legadoCommit -eq $legadoCommit
  ) 'machine state and objective share the frozen baseline.'
  Add-Check 'active_issue' (
    [string]$state.governance.status -eq 'running' -and
    [string]$state.governance.activeTaskId -eq $taskId -and
    [string]$state.governance.activeIssueId -eq $issueId -and
    [string]$objective.objective.activeIssue -eq $issueId
  ) '243 remains the sole active source issue.'
  Add-Check 'subtask_count' ($plan.Count -eq 79) 'all 79 currently registered 243 static subitems are present.'
  $ids = @($plan | ForEach-Object { [string]$_.id })
  Add-Check 'subtask_id_uniqueness' (@($ids | Sort-Object -Unique).Count -eq $ids.Count) '243 subitem IDs are unique.'
  Add-Check 'subtask_statuses' (@($plan | Where-Object { [string]$_.status -notin @('completed', 'deferred') }).Count -eq 0) 'every 243 subitem is completed or explicitly deferred.'

  $completed = @($plan | Where-Object { [string]$_.status -eq 'completed' })
  $deferred = @($plan | Where-Object { [string]$_.status -eq 'deferred' })
  Add-Check 'completed_count' ($completed.Count -eq 41) '41 completed subitems are expected from the current static closure ledger.'
  Add-Check 'deferred_count' ($deferred.Count -eq 38) '38 subitems remain explicitly deferred to R4.'

  $completedEvidence = New-Object 'System.Collections.Generic.List[object]'
  foreach ($item in $completed) {
    $evidenceProperty = $item.PSObject.Properties['evidence']
    $hasEvidence = $null -ne $evidenceProperty -and $null -ne $evidenceProperty.Value -and @($evidenceProperty.Value).Count -gt 0
    Add-Check ("completed_evidence_property_{0}" -f $item.id) $hasEvidence ("completed subitem '$($item.id)' has evidence paths.")
    foreach ($relative in @($evidenceProperty.Value)) {
      $path = [string]$relative
      $exists = Test-Path -LiteralPath (Get-RepoPath -Path $path) -PathType Leaf
      [void]$completedEvidence.Add([pscustomobject][ordered]@{ id = [string]$item.id; path = $path; exists = $exists })
      $safePathId = [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($path))).Substring(0, 12)
      Add-Check ("completed_evidence_path_{0}_{1}" -f $item.id, $safePathId) $exists ("evidence '$path' for '$($item.id)' exists.")
    }
  }

  $deferredRecords = New-Object 'System.Collections.Generic.List[object]'
  foreach ($item in $deferred) {
    $action = [string]$item.action
    $hasR4 = $action -match '(?i)\bR4\b'
    Add-Check ("deferred_r4_marker_{0}" -f $item.id) $hasR4 ("deferred subitem '$($item.id)' names the R4 handoff.")
    [void]$deferredRecords.Add([pscustomobject][ordered]@{
        id = [string]$item.id
        status = 'deferred'
        action = $action
        runtimeQualification = 'deferred_to_R4'
      })
  }

  $combination = @($plan | Where-Object { [string]$_.id -eq '243-SP-COMBINATION-R4' }) | Select-Object -First 1
  Add-Check 'combination_evidence_binding' (
    $null -ne $combination -and
    @($combination.evidence) -contains 'tools/legado-compat/evidence/contract-legado-jsoup-standard-pseudo-combination-r4-consumer-20260810.json' -and
    @($combination.evidence) -contains 'tools/legado-compat/evidence/contract-legado-jsoup-standard-pseudo-combination-r4-fixture-20260810.json'
  ) 'R4 combination fixture and consumer contracts remain bound to the readiness ledger.'

  $textProjection = @($plan | Where-Object { [string]$_.id -eq '243-SP-75' }) | Select-Object -First 1
  $textProjectionR4 = @($plan | Where-Object { [string]$_.id -eq '243-SP-76' }) | Select-Object -First 1
  $textProjectionEvidence = @(
    'tools/legado-compat/fixtures/legado-jsoup-terminal-text-projection-context.json',
    'tools/legado-compat/evidence/contract-legado-jsoup-terminal-text-projection-pre-fix-20260810.json',
    'tools/legado-compat/evidence/contract-legado-jsoup-terminal-text-projection-post-fix-20260811.json',
    'tools/legado-compat/evidence/v2-jsoup-terminal-text-projection-source-fix-20260811.json'
  )
  $textProjectionBound = $null -ne $textProjection -and [string]$textProjection.status -eq 'completed'
  foreach ($path in $textProjectionEvidence) {
    $textProjectionBound = $textProjectionBound -and @($textProjection.evidence) -contains $path -and (Test-Path -LiteralPath (Get-RepoPath -Path $path) -PathType Leaf)
  }
  Add-Check 'terminal_text_projection_evidence_binding' $textProjectionBound '243-SP-75 binds all terminal text projection fixture, pre-fix, post-fix and source-fix evidence.'
  Add-Check 'terminal_text_projection_r4_binding' (
    $null -ne $textProjectionR4 -and
    [string]$textProjectionR4.status -eq 'deferred' -and
    [string]$textProjectionR4.action -match '(?i)\bR4\b' -and
    [string]$textProjectionR4.action -match '67' -and
    [string]$textProjectionR4.action -match '25'
  ) '243-SP-76 retains the R4 handoff for the affected 67 textNodes and 25 ownText source sets.'

  $historicalEvidence = Read-StrictJson -Path $historicalEvidencePath
  Add-Check 'historical_snapshot_immutable' (
    (Get-Sha256 -Path $historicalScriptPath) -eq $historicalScriptHash -and
    (Get-Sha256 -Path $historicalEvidencePath) -eq $historicalEvidenceHash -and
    [int]$historicalEvidence.subtaskCount -eq 71 -and
    [int]$historicalEvidence.completedCount -eq 37 -and
    [int]$historicalEvidence.deferredCount -eq 34
  ) 'the 2026-08-10 readiness script and evidence remain an immutable 71/37/34 historical snapshot.'
  Add-Check 'runtime_gate_locked' (
    -not [bool]$state.governance.semanticMatchAllowed -and
    @($state.governance.runtimeActionsPerformed).Count -eq 0
  ) 'the current readiness contract does not authorize runtime qualification.'

  $result = [pscustomobject][ordered]@{
    schemaVersion = 2
    evidenceType = 'r4_current_static_readiness_contract'
    issueId = $issueId
    status = 'passed_static_only'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
    historicalSnapshot = [pscustomobject][ordered]@{
      scriptPath = $historicalScriptPath
      scriptSha256 = $historicalScriptHash
      evidencePath = $historicalEvidencePath
      evidenceSha256 = $historicalEvidenceHash
      subtaskCount = 71
      completedCount = 37
      deferredCount = 34
      disposition = 'immutable_historical_snapshot'
    }
    currentLedger = [pscustomobject][ordered]@{
      subtaskCount = $plan.Count
      completedCount = $completed.Count
      deferredCount = $deferred.Count
      completedEvidenceCount = $completedEvidence.Count
      completedSubtasks = @($completed | ForEach-Object { [string]$_.id })
      deferredSubtasks = @($deferredRecords.ToArray())
    }
    requiredBindings = [pscustomobject][ordered]@{
      combinationR4 = '243-SP-COMBINATION-R4'
      terminalTextProjectionStatic = '243-SP-75'
      terminalTextProjectionR4 = '243-SP-76'
    }
    assertions = $script:assertions
    checks = @($script:checks.ToArray())
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'current_r4_readiness_inventory_static_only;runtime_build_device_harness_and_legado_diff_deferred'
    nextGate = 'Use the 38 current deferredSubtasks as the exact R4 queue. Do not treat the 2026-08-10 historical snapshot or this static readiness evidence as runtime semantic qualification.'
  }
} catch {
  $exitCode = 1
  $result = [pscustomobject][ordered]@{
    schemaVersion = 2
    evidenceType = 'r4_current_static_readiness_contract'
    issueId = $issueId
    status = 'failed'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    failure = $_.Exception.Message
    assertions = $script:assertions
    checks = @($script:checks.ToArray())
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
  }
}

Write-AtomicJson -Path $outputFullPath -Value $result
$result | ConvertTo-Json -Depth 100
if ($exitCode -ne 0) { exit $exitCode }
