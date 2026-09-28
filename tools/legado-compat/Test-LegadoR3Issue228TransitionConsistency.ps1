[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$RunId = 'r3-issue228-transition-consistency-20260808-r1',
  [string]$OutputPath = '',
  [switch]$RequireRegistration
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($RepositoryRoot.Length -eq 0) {
  $RepositoryRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$evidenceRoot = (Resolve-Path -LiteralPath (Join-Path $RepositoryRoot 'tools\legado-compat\evidence')).Path
$runDirectory = Join-Path $evidenceRoot $RunId
if ($OutputPath.Length -eq 0) {
  $OutputPath = Join-Path $runDirectory 'transition-consistency.json'
}
$outputFullPath = [System.IO.Path]::GetFullPath($OutputPath)
$evidencePrefix = $evidenceRoot.TrimEnd('\') + '\'
if (-not $outputFullPath.StartsWith($evidencePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw 'Issue-228 transition evidence must remain under the evidence directory.'
}
if (-not (Test-Path -LiteralPath $runDirectory)) {
  [System.IO.Directory]::CreateDirectory($runDirectory) | Out-Null
}

$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$script:checks = New-Object 'System.Collections.Generic.List[object]'
$script:assertions = 0

function Read-StrictUtf8Text {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { throw "Required file is missing: $Path" }
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw "UTF-8 BOM is not allowed: $Path"
  }
  return $strictUtf8.GetString($bytes)
}

function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$Path)
  try { return (Read-StrictUtf8Text -Path $Path | ConvertFrom-Json) }
  catch { throw "Invalid JSON: $Path; $($_.Exception.Message)" }
}

function Get-PropertyValue {
  param([object]$Object, [string]$Name, [object]$Default = $null)
  if ($null -eq $Object) { return $Default }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property -or $null -eq $property.Value) { return $Default }
  return $property.Value
}

function Get-Issue {
  param([object[]]$Issues, [string]$Id)
  foreach ($issue in $Issues) {
    if ([string](Get-PropertyValue $issue 'id') -eq $Id) { return $issue }
  }
  return $null
}

function Get-Sha256 {
  param([Parameter(Mandatory = $true)][string]$Path)
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Assert-Gate {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw $Message }
  $script:assertions++
}

function Add-Check {
  param([string]$Id, [string]$Detail, [string[]]$Evidence = @())
  [void]$script:checks.Add([pscustomobject][ordered]@{
      id = $Id
      status = 'passed'
      detail = $Detail
      evidencePaths = @($Evidence)
    })
}

$statePath = Join-Path $RepositoryRoot 'tools\legado-compat\state\full-source-validation-state.json'
$objectivePath = Join-Path $RepositoryRoot 'tools\legado-compat\state\refactor-objective.json'
$queueGatePath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\r3-issue228-queue-gate-20260808-r3\r3-issue228-queue-static-gate.json'
$auditPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\v2-java-string-list-analyzer-js-source-fix-current-head-hash-audit-20260808-r1.json'
$objectiveDocumentPath = Join-Path $RepositoryRoot 'docs\analysis\Legado书源V2源码重构持续目标.md'
$governancePath = Join-Path $RepositoryRoot 'tools\legado-compat\LEGADO_V2_GOVERNANCE_TASKS.md'
$ledgerPath = Join-Path $RepositoryRoot 'docs\analysis\Legado书源引擎兼容推进台账.md'
$indexPath = Join-Path $RepositoryRoot 'docs\analysis\Legado书源引擎证据索引.md'
$diffPath = Join-Path $RepositoryRoot 'docs\analysis\Legado书源引擎差分摘要.md'
$packagePath = 'F:\Downloads-E\墨辰整理书源大全7.1（禁止倒卖）.【最新完整】.json'
$relativeOutputPath = 'tools/legado-compat/evidence/' + $RunId + '/transition-consistency.json'

$result = $null
$exitCode = 0
try {
  $state = Read-StrictJson -Path $statePath
  $objective = Read-StrictJson -Path $objectivePath
  $queueGate = Read-StrictJson -Path $queueGatePath
  $audit = Read-StrictJson -Path $auditPath
  $baseline = $state.baseline
  Assert-Gate ([int]$baseline.sourceCount -eq 458) 'machine baseline source count is not 458.'
  Assert-Gate ([string]$baseline.sourcePackageSha256 -eq '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67') 'machine source hash is not frozen.'
  Assert-Gate ((Get-Sha256 -Path $packagePath) -eq [string]$baseline.sourcePackageSha256) 'source package hash drifted.'
  Assert-Gate ([string]$baseline.legadoCommit -eq '95973d186b147fb9ab43a9240021d688e4304fbd') 'machine Legado commit is not frozen.'
  Assert-Gate ((& git -C (Join-Path $RepositoryRoot 'legado') rev-parse HEAD 2>$null | Out-String).Trim() -eq [string]$baseline.legadoCommit) 'Legado checkout is not at the frozen commit.'
  Assert-Gate ([string]$objective.baseline.sourcePackageSha256 -eq [string]$baseline.sourcePackageSha256 -and [int]$objective.baseline.sourceCount -eq [int]$baseline.sourceCount -and [string]$objective.baseline.legadoCommit -eq [string]$baseline.legadoCommit) 'objective baseline differs from machine baseline.'
  Add-Check -Id 'baseline_binding' -Detail 'State, objective, package and Legado checkout remain bound to the frozen baseline.' -Evidence @('tools/legado-compat/state/full-source-validation-state.json', 'tools/legado-compat/state/refactor-objective.json')

  $governance = $state.governance
  $issues = @($governance.issues)
  Assert-Gate ([string]$governance.activeTaskId -eq 'COMPAT-006' -and [string]$governance.activeIssueId -eq 'ISSUE-COMPAT-228-JAVA-STRING-LIST-ANALYZER-JS' -and [string]$governance.status -eq 'running') 'machine governance queue is not registered on 228.'
  foreach ($id in @('ISSUE-COMPAT-014','ISSUE-COMPAT-015','V2-HARNESS-023','ISSUE-COMPAT-228-JAVA-STRING-LIST-ANALYZER-JS')) {
    $issue = Get-Issue -Issues $issues -Id $id
    Assert-Gate ($null -ne $issue -and [string]$issue.status -eq 'verifying') ("{0} must remain verifying for deferred R4." -f $id)
  }
  $issue228 = Get-Issue -Issues $issues -Id 'ISSUE-COMPAT-228-JAVA-STRING-LIST-ANALYZER-JS'
  $evidence = @($issue228.evidencePaths | ForEach-Object { [string]$_ })
  Assert-Gate ($evidence -contains 'tools/legado-compat/evidence/r3-issue228-queue-gate-20260808-r3/r3-issue228-queue-static-gate.json' -and $evidence -contains 'tools/legado-compat/evidence/v2-java-string-list-analyzer-js-source-fix-current-head-hash-audit-20260808-r1.json') '228 evidence registration is incomplete.'
  Add-Check -Id 'machine_queue' -Detail 'The unique source queue is atomically registered on 228; prior verifying issues remain deferred to R4.' -Evidence @('tools/legado-compat/state/full-source-validation-state.json')

  Assert-Gate ([string]$objective.authority.activeIssueId -eq 'ISSUE-COMPAT-228-JAVA-STRING-LIST-ANALYZER-JS' -and [string]$objective.objective.activeIssue -eq 'ISSUE-COMPAT-228-JAVA-STRING-LIST-ANALYZER-JS') 'objective active issue is not 228.'
  Assert-Gate ([string]$objective.objective.queueSelectionGate.selectedIssue -eq 'ISSUE-COMPAT-228-JAVA-STRING-LIST-ANALYZER-JS' -and @($objective.objective.queueSelectionGate.candidateIssues) -contains 'ISSUE-COMPAT-230-EXPLORE-HARNESS-SERIAL-TIMEOUT') 'objective queue selection is not 228 -> 230.'
  Assert-Gate ([string]$objective.executionTarget.currentIssue -eq 'ISSUE-COMPAT-228-JAVA-STRING-LIST-ANALYZER-JS' -and @($objective.executionTarget.nextIssues) -contains 'ISSUE-COMPAT-230-EXPLORE-HARNESS-SERIAL-TIMEOUT') 'objective execution target is not 228 -> 230.'
  Assert-Gate (-not [bool]$queueGate.semanticMatchAllowed -and @($queueGate.runtimeActionsPerformed).Count -eq 0 -and [string]$queueGate.status -eq 'passed') '228 queue gate contains runtime or semantic-match claims.'
  Assert-Gate ([string]$queueGate.transition.fromIssue -eq 'V2-HARNESS-023' -and [string]$queueGate.transition.toIssue -eq 'ISSUE-COMPAT-228-JAVA-STRING-LIST-ANALYZER-JS' -and [string]$queueGate.transition.nextCandidate -eq 'ISSUE-COMPAT-230-EXPLORE-HARNESS-SERIAL-TIMEOUT') '228 queue gate transition is not registered.'
  Assert-Gate ([string]$audit.status -eq 'current_head_bound_with_historical_superseded_evidence' -and -not [bool]$audit.semanticMatchAllowed -and [string]$audit.baseline.sourcePackageSha256 -eq [string]$baseline.sourcePackageSha256) '228 current-head audit is not a static-only bound.'
  Add-Check -Id 'objective_and_evidence_binding' -Detail 'Objective, queue gate and current-head audit agree on 228 as the sole active source-closure issue and defer R4.' -Evidence @('tools/legado-compat/state/refactor-objective.json', 'tools/legado-compat/evidence/r3-issue228-queue-gate-20260808-r3/r3-issue228-queue-static-gate.json', 'tools/legado-compat/evidence/v2-java-string-list-analyzer-js-source-fix-current-head-hash-audit-20260808-r1.json')

  $objectiveDocument = Read-StrictUtf8Text -Path $objectiveDocumentPath
  $governanceDocument = Read-StrictUtf8Text -Path $governancePath
  $ledgerDocument = Read-StrictUtf8Text -Path $ledgerPath
  $indexDocument = Read-StrictUtf8Text -Path $indexPath
  $diffDocument = Read-StrictUtf8Text -Path $diffPath
  Assert-Gate ($objectiveDocument.Contains([string]$objective.targetRevision) -and $objectiveDocument.Contains('当前唯一源码验证议题为 `ISSUE-COMPAT-228-JAVA-STRING-LIST-ANALYZER-JS`') -and $objectiveDocument.Contains('下一候选为 `ISSUE-COMPAT-230-EXPLORE-HARNESS-SERIAL-TIMEOUT`')) 'objective Markdown does not describe the registered 228 queue.'
  Assert-Gate ($governanceDocument.Contains('activeIssue=`ISSUE-COMPAT-228-JAVA-STRING-LIST-ANALYZER-JS`') -and $governanceDocument -match '\| issue \| ISSUE-COMPAT-228-JAVA-STRING-LIST-ANALYZER-JS \| verifying \|') 'governance mirror does not describe active 228.'
  Assert-Gate ($ledgerDocument.Contains('活跃任务：COMPAT-006') -and $indexDocument.Contains('r3-issue228-queue-gate-20260808-r3/r3-issue228-queue-static-gate.json') -and $diffDocument.Contains('r3-issue228-queue-gate-20260808-r3/r3-issue228-queue-static-gate.json')) 'generated documents do not retain the 228 queue evidence.'
  if ($RequireRegistration) {
    Assert-Gate ($indexDocument.Contains($relativeOutputPath) -and $diffDocument.Contains($relativeOutputPath)) 'registered 228 transition evidence is missing from generated documents.'
  }
  Add-Check -Id 'document_mirror' -Detail 'Objective Markdown, governance mirror, ledger, evidence index and diff summary agree on 228 and retain the historical boundary.' -Evidence @('docs/analysis/Legado书源V2源码重构持续目标.md', 'tools/legado-compat/LEGADO_V2_GOVERNANCE_TASKS.md', 'docs/analysis/Legado书源引擎兼容推进台账.md', 'docs/analysis/Legado书源引擎证据索引.md', 'docs/analysis/Legado书源引擎差分摘要.md')

  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_r3_issue228_transition_consistency'
    status = 'passed'
    issueId = 'ISSUE-COMPAT-228-JAVA-STRING-LIST-ANALYZER-JS'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    objectiveId = [string]$objective.objectiveId
    targetRevision = [string]$objective.targetRevision
    transition = [pscustomobject][ordered]@{ fromIssue = 'V2-HARNESS-023'; toIssue = 'ISSUE-COMPAT-228-JAVA-STRING-LIST-ANALYZER-JS'; toStatus = 'verifying'; nextCandidate = 'ISSUE-COMPAT-230-EXPLORE-HARNESS-SERIAL-TIMEOUT'; runtimeVerification = 'deferred_to_R4' }
    baseline = [pscustomobject][ordered]@{ sourceCount = [int]$baseline.sourceCount; sourcePackageSha256 = [string]$baseline.sourcePackageSha256; legadoCommit = [string]$baseline.legadoCommit }
    assertions = $script:assertions
    checks = $script:checks.ToArray()
    evidencePaths = @('tools/legado-compat/state/refactor-objective.json', 'tools/legado-compat/state/full-source-validation-state.json', 'tools/legado-compat/evidence/r3-issue228-queue-gate-20260808-r3/r3-issue228-queue-static-gate.json', 'tools/legado-compat/evidence/v2-java-string-list-analyzer-js-source-fix-current-head-hash-audit-20260808-r1.json')
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_issue228_transition_consistency_read_only;R4_runtime_build_device_and_legado_diff_deferred'
    registrationRequired = [bool]$RequireRegistration
  }
} catch {
  $exitCode = 1
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_r3_issue228_transition_consistency'
    status = 'failed'
    issueId = 'ISSUE-COMPAT-228-JAVA-STRING-LIST-ANALYZER-JS'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    failure = $_.Exception.Message
    assertions = $script:assertions
    checks = $script:checks.ToArray()
    evidencePaths = @()
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_issue228_transition_consistency_read_only;R4_runtime_build_device_and_legado_diff_deferred'
    registrationRequired = [bool]$RequireRegistration
  }
}

$temporaryPath = "$outputFullPath.tmp.$PID.$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
[System.IO.File]::WriteAllText($temporaryPath, ($result | ConvertTo-Json -Depth 24), [System.Text.UTF8Encoding]::new($false))
Move-Item -LiteralPath $temporaryPath -Destination $outputFullPath -Force
$result | ConvertTo-Json -Depth 24
if ($exitCode -ne 0) { exit $exitCode }
