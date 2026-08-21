[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$OutputPath = 'tools/legado-compat/evidence/contract-legado-jsoup-standard-pseudo-243-r4-readiness-20260810.json'
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
$script:assertions = 0
$script:checks = New-Object 'System.Collections.Generic.List[object]'

function Get-RepoPath {
  param([Parameter(Mandatory = $true)][string]$Path)
  if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }
  return Join-Path $RepositoryRoot ($Path.Replace('/', '\'))
}

function Read-StrictText {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing file: $Path" }
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw "UTF-8 BOM is not allowed: $Path"
  }
  return $strictUtf8.GetString($bytes)
}

function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$Path)
  return (Read-StrictText -Path $Path | ConvertFrom-Json -Depth 100)
}

function Write-AtomicJson {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value)
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
  param([Parameter(Mandatory = $true)][string]$Id, [Parameter(Mandatory = $true)][bool]$Passed, [Parameter(Mandatory = $true)][string]$Detail)
  [void]$script:checks.Add([pscustomobject][ordered]@{ id = $Id; passed = $Passed; detail = $Detail })
  $script:assertions++
  if (-not $Passed) { throw "243 R4 readiness failed: $Id; $Detail" }
}

$outputFullPath = [System.IO.Path]::GetFullPath((Join-Path $RepositoryRoot ($OutputPath.Replace('/', '\'))))
$evidenceRoot = [System.IO.Path]::GetFullPath((Join-Path $RepositoryRoot 'tools\legado-compat\evidence')).TrimEnd('\') + '\'
if (-not $outputFullPath.StartsWith($evidenceRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw 'R4 readiness evidence must remain under the evidence directory.'
}

$result = $null
$exitCode = 0
try {
  $state = Read-StrictJson -Path (Get-RepoPath 'tools/legado-compat/state/full-source-validation-state.json')
  $objective = Read-StrictJson -Path (Get-RepoPath 'tools/legado-compat/state/refactor-objective.json')
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
    [string]$state.governance.activeIssueId -eq $issueId -and
    [string]$state.governance.status -eq 'running' -and
    [string]$objective.objective.activeIssue -eq $issueId
  ) '243 remains the sole active source issue.'
  Add-Check 'subtask_count' ($plan.Count -eq 71) 'all 71 registered 243 static subitems are present.'
  $ids = @($plan | ForEach-Object { [string]$_.id })
  Add-Check 'subtask_id_uniqueness' (@($ids | Sort-Object -Unique).Count -eq $ids.Count) '243 subitem IDs are unique.'
  Add-Check 'subtask_statuses' (@($plan | Where-Object { [string]$_.status -notin @('completed', 'deferred') }).Count -eq 0) 'every 243 subitem is completed or explicitly deferred.'

  $completed = @($plan | Where-Object { [string]$_.status -eq 'completed' })
  $deferred = @($plan | Where-Object { [string]$_.status -eq 'deferred' })
  Add-Check 'completed_count' ($completed.Count -eq 37) '37 completed subitems are expected from the static closure ledger.'
  Add-Check 'deferred_count' ($deferred.Count -eq 34) '34 subitems remain explicitly deferred to R4.'

  $completedEvidence = New-Object 'System.Collections.Generic.List[object]'
  foreach ($item in $completed) {
    $evidenceProperty = $item.PSObject.Properties['evidence']
    Add-Check ("completed_evidence_property_{0}" -f $item.id) ($null -ne $evidenceProperty -and $null -ne $evidenceProperty.Value -and @($evidenceProperty.Value).Count -gt 0) ("completed subitem '$($item.id)' has evidence paths.")
    foreach ($relative in @($evidenceProperty.Value)) {
      $path = [string]$relative
      [void]$completedEvidence.Add([pscustomobject][ordered]@{ id = [string]$item.id; path = $path; exists = (Test-Path -LiteralPath (Get-RepoPath $path) -PathType Leaf) })
      Add-Check ("completed_evidence_path_{0}_{1}" -f $item.id, ([Math]::Abs($path.GetHashCode()))) (Test-Path -LiteralPath (Get-RepoPath $path) -PathType Leaf) ("evidence '$path' for '$($item.id)' exists.")
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
  Add-Check 'combination_evidence_binding' ($null -ne $combination -and @($combination.evidence) -contains 'tools/legado-compat/evidence/contract-legado-jsoup-standard-pseudo-combination-r4-consumer-20260810.json' -and @($combination.evidence) -contains 'tools/legado-compat/evidence/contract-legado-jsoup-standard-pseudo-combination-r4-fixture-20260810.json') 'R4 combination fixture and consumer contracts are bound to the readiness ledger.'
  Add-Check 'runtime_gate_locked' (-not [bool]$state.governance.semanticMatchAllowed -and @($state.governance.runtimeActionsPerformed).Count -eq 0) 'the readiness contract does not authorize runtime qualification.'

  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    evidenceType = 'r4_static_readiness_contract'
    issueId = $issueId
    status = 'passed_static_only'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
    subtaskCount = $plan.Count
    completedCount = $completed.Count
    deferredCount = $deferred.Count
    completedEvidenceCount = $completedEvidence.Count
    completedSubtasks = @($completed | ForEach-Object { [string]$_.id })
    deferredSubtasks = @($deferredRecords.ToArray())
    assertions = $script:assertions
    checks = @($script:checks.ToArray())
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r4_readiness_inventory_static_only;runtime_build_device_and_legado_diff_deferred'
    nextGate = 'Use the deferredSubtasks inventory as the exact R4 execution queue; do not mark any subitem passed without runtime evidence.'
  }
} catch {
  $exitCode = 1
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    evidenceType = 'r4_static_readiness_contract'
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
