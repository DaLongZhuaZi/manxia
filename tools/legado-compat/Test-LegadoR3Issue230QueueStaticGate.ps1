[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$RunId = 'r3-issue230-queue-gate-20260808-r1',
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
  $OutputPath = Join-Path $runDirectory 'r3-issue230-queue-static-gate.json'
}
$outputFullPath = [System.IO.Path]::GetFullPath($OutputPath)
$evidencePrefix = $evidenceRoot.TrimEnd('\') + '\'
if (-not $outputFullPath.StartsWith($evidencePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw 'Issue-230 queue gate output must remain under the evidence directory.'
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
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $Path" }
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
  foreach ($issue in $Issues) { if ([string](Get-PropertyValue $issue 'id') -eq $Id) { return $issue } }
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
  [void]$script:checks.Add([pscustomobject][ordered]@{ id = $Id; status = 'passed'; detail = $Detail; evidencePaths = @($Evidence) })
}

$statePath = Join-Path $RepositoryRoot 'tools\legado-compat\state\full-source-validation-state.json'
$objectivePath = Join-Path $RepositoryRoot 'tools\legado-compat\state\refactor-objective.json'
$sourceFixPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\v2-explore-harness-serial-timeout-source-fix-20260808-r2.json'
$currentHeadAuditPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\v2-explore-harness-serial-timeout-current-head-hash-audit-20260808-r1.json'
$terminalFixturePath = Join-Path $RepositoryRoot 'tools\legado-compat\fixtures\legado-explore-harness-terminal-error.json'
$settlementFixturePath = Join-Path $RepositoryRoot 'tools\legado-compat\fixtures\hypium-terminal-workflow-settlement.json'
$terminalResultPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\contract-legado-explore-harness-terminal-error.json'
$settlementResultPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\v2-terminal-workflow-settlement-contract.json'
$navigationPath = Join-Path $RepositoryRoot 'tools\legado-compat\Invoke-LegadoV2HypiumNavigation.py'
$settlementPath = Join-Path $RepositoryRoot 'tools\legado-compat\LegadoHypiumWorkflowSettlement.psm1'
$runnerPath = Join-Path $RepositoryRoot 'tools\legado-compat\Invoke-LegadoV2HypiumFullSourceDeviceRunner.ps1'
$networkContractPath = Join-Path $RepositoryRoot 'tools\legado-compat\Test-LegadoDynamicExploreNetworkRouteContract.ps1'
$interactionContractPath = Join-Path $RepositoryRoot 'tools\legado-compat\Test-LegadoV2ExploreInteractionClassificationContract.ps1'
$objectiveDocumentPath = Join-Path $RepositoryRoot 'docs\analysis\Legado书源V2源码重构持续目标.md'
$governancePath = Join-Path $RepositoryRoot 'tools\legado-compat\LEGADO_V2_GOVERNANCE_TASKS.md'
$ledgerPath = Join-Path $RepositoryRoot 'docs\analysis\Legado书源引擎兼容推进台账.md'
$indexPath = Join-Path $RepositoryRoot 'docs\analysis\Legado书源引擎证据索引.md'
$diffPath = Join-Path $RepositoryRoot 'docs\analysis\Legado书源引擎差分摘要.md'
$packagePath = 'F:\Downloads-E\墨辰整理书源大全7.1（禁止倒卖）.【最新完整】.json'
$relativeOutputPath = 'tools/legado-compat/evidence/' + $RunId + '/r3-issue230-queue-static-gate.json'

$result = $null
$exitCode = 0
try {
  $state = Read-StrictJson -Path $statePath
  $objective = Read-StrictJson -Path $objectivePath
  $sourceFix = Read-StrictJson -Path $sourceFixPath
  $audit = Read-StrictJson -Path $currentHeadAuditPath
  $terminalFixture = Read-StrictJson -Path $terminalFixturePath
  $settlementFixture = Read-StrictJson -Path $settlementFixturePath
  $terminalResult = Read-StrictJson -Path $terminalResultPath
  $settlementResult = Read-StrictJson -Path $settlementResultPath
  $baseline = $state.baseline
  Assert-Gate ([int]$baseline.sourceCount -eq 458 -and [string]$baseline.sourcePackageSha256 -eq '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67' -and [string]$baseline.legadoCommit -eq '95973d186b147fb9ab43a9240021d688e4304fbd') 'machine baseline is not frozen.'
  Assert-Gate ((Get-Sha256 -Path $packagePath) -eq [string]$baseline.sourcePackageSha256) 'source package hash drifted.'
  Assert-Gate ((& git -C (Join-Path $RepositoryRoot 'legado') rev-parse HEAD 2>$null | Out-String).Trim() -eq [string]$baseline.legadoCommit) 'Legado checkout is not at the frozen commit.'
  Add-Check -Id 'baseline_binding' -Detail '230 evidence is bound to the frozen 458-source package and Legado commit.' -Evidence @('tools/legado-compat/state/full-source-validation-state.json')

  $governance = $state.governance
  $issues = @($governance.issues)
  $issue228 = Get-Issue -Issues $issues -Id 'ISSUE-COMPAT-228-JAVA-STRING-LIST-ANALYZER-JS'
  $issue230 = Get-Issue -Issues $issues -Id 'ISSUE-COMPAT-230-EXPLORE-HARNESS-SERIAL-TIMEOUT'
  Assert-Gate ([string]$governance.activeTaskId -eq 'COMPAT-006') 'active task drifted from COMPAT-006.'
  if ($RequireRegistration) { Assert-Gate ([string]$governance.activeIssueId -eq 'ISSUE-COMPAT-230-EXPLORE-HARNESS-SERIAL-TIMEOUT') 'post-transition active issue is not 230.' }
  else { Assert-Gate ([string]$governance.activeIssueId -eq 'ISSUE-COMPAT-228-JAVA-STRING-LIST-ANALYZER-JS') 'pre-transition active issue must remain 228.' }
  Assert-Gate ([string]$governance.status -eq 'running' -and $null -ne $issue228 -and [string]$issue228.status -eq 'verifying' -and $null -ne $issue230 -and [string]$issue230.status -eq 'verifying') '228/230 queue statuses are invalid.'
  Add-Check -Id 'queue_precondition' -Detail '228 remains deferred-R4 and 230 is the only next source-closure candidate.' -Evidence @('tools/legado-compat/state/full-source-validation-state.json')

  Assert-Gate ([string]$terminalResult.status -eq 'passed' -and [int]$terminalResult.assertions -eq 8) 'terminal-error contract is not the passed 8-assertion result.'
  Assert-Gate ([string]$settlementResult.status -eq 'passed' -and [int]$settlementResult.assertions -eq 26) 'workflow settlement contract is not the passed 26-assertion result.'
  Assert-Gate ([string]$terminalFixture.contract -eq 'legado_explore_harness_observes_terminal_error_without_serial_timeout' -and [string]$terminalFixture.requiredOutcome -eq 'no_executable_kind') 'terminal fixture semantics drifted.'
  Assert-Gate (@($settlementFixture.scenarios).Count -ge 2) 'settlement fixture scenarios are missing.'
  Assert-Gate ([string]$sourceFix.issueId -eq 'ISSUE-COMPAT-230-EXPLORE-HARNESS-SERIAL-TIMEOUT' -and [string]$sourceFix.status -eq 'source_closure_static_verified_pending_r4' -and -not [bool](Get-PropertyValue $sourceFix 'semanticMatchAllowed' $false)) '230 source-fix evidence contains an invalid status or semantic claim.'
  Assert-Gate ([string]$audit.status -eq 'current_head_bound_static_closure' -and -not [bool](Get-PropertyValue $audit 'semanticMatchAllowed' $false) -and @($audit.runtimeActionsPerformed).Count -eq 0) '230 current-head audit is not static-only.'
  Add-Check -Id 'failure_and_static_contract' -Detail '230 has bounded terminal-error and workflow-settlement contracts plus an explicit static-only source-fix record.' -Evidence @('tools/legado-compat/fixtures/legado-explore-harness-terminal-error.json','tools/legado-compat/evidence/contract-legado-explore-harness-terminal-error.json','tools/legado-compat/evidence/v2-terminal-workflow-settlement-contract.json','tools/legado-compat/evidence/v2-explore-harness-serial-timeout-source-fix-20260808-r2.json')

  $auditPaths = @($audit.currentHead.sourceFiles + $audit.currentHead.fixtureFiles + $audit.currentHead.contractFiles)
  foreach ($entry in @($audit.currentHead.sourceFiles)) { $path = Join-Path $RepositoryRoot ([string]$entry.path); Assert-Gate ((Get-Sha256 -Path $path) -eq [string]$entry.sha256) ("230 source hash drifted: {0}" -f $entry.path) }
  foreach ($entry in @($audit.currentHead.fixtureFiles)) { $path = Join-Path $RepositoryRoot ([string]$entry.path); Assert-Gate ((Get-Sha256 -Path $path) -eq [string]$entry.sha256) ("230 fixture hash drifted: {0}" -f $entry.path) }
  foreach ($entry in @($audit.currentHead.contractFiles)) { $path = Join-Path $RepositoryRoot ([string]$entry.path); Assert-Gate ((Get-Sha256 -Path $path) -eq [string]$entry.sha256) ("230 contract hash drifted: {0}" -f $entry.path); Assert-Gate ([string]$entry.status -eq 'passed') ("230 contract is not passed: {0}" -f $entry.path) }
  $navigation = Read-StrictUtf8Text -Path $navigationPath
  $settlement = Read-StrictUtf8Text -Path $settlementPath
  $runner = Read-StrictUtf8Text -Path $runnerPath
  $networkContract = Read-StrictUtf8Text -Path $networkContractPath
  $interactionContract = Read-StrictUtf8Text -Path $interactionContractPath
  Assert-Gate ($navigation.Contains('wait_for_explore_kind_or_error') -and $navigation.Contains('evidence["explore_outcome"] = "no_executable_kind"') -and $navigation.Contains('driver.wait(0.4)')) 'navigation bounded terminal polling path is missing.'
  Assert-Gate ($settlement.Contains('Get-LegadoHypiumExploreDependencySettlements') -and $runner.Contains('Get-LegadoHypiumExploreDependencySettlements')) 'workflow settlement consumer path is missing.'
  Assert-Gate ($networkContract.Contains("'eval('") -and $networkContract.Contains("'Function('") -and $interactionContract.Contains("needs_interaction")) 'dynamic network or interaction classification contract paths are missing.'
  Add-Check -Id 'implementation_hash_binding' -Detail 'Explore navigation, settlement, runner, fixtures and static contracts are bound to current HEAD and their semantic markers.' -Evidence @('tools/legado-compat/evidence/v2-explore-harness-serial-timeout-current-head-hash-audit-20260808-r1.json')

  $objective = Read-StrictJson -Path $objectivePath
  if ($RequireRegistration) { Assert-Gate ([string]$objective.authority.activeIssueId -eq 'ISSUE-COMPAT-230-EXPLORE-HARNESS-SERIAL-TIMEOUT' -and [string]$objective.objective.activeIssue -eq 'ISSUE-COMPAT-230-EXPLORE-HARNESS-SERIAL-TIMEOUT') 'post-transition objective does not select 230.' }
  else { Assert-Gate ([string]$objective.authority.activeIssueId -eq 'ISSUE-COMPAT-228-JAVA-STRING-LIST-ANALYZER-JS' -and [string]$objective.objective.activeIssue -eq 'ISSUE-COMPAT-228-JAVA-STRING-LIST-ANALYZER-JS') 'pre-transition objective must remain on 228.' }
  Assert-Gate (@($objective.executionTarget.nextIssues) -contains 'V2-GOV-004-DOCUMENT-TASK-MIRROR') 'next candidate 230 must preserve the following governance candidate.'
  $objectiveDocument = Read-StrictUtf8Text -Path $objectiveDocumentPath
  $governanceDocument = Read-StrictUtf8Text -Path $governancePath
  $ledgerDocument = Read-StrictUtf8Text -Path $ledgerPath
  $indexDocument = Read-StrictUtf8Text -Path $indexPath
  $diffDocument = Read-StrictUtf8Text -Path $diffPath
  if ($RequireRegistration) { Assert-Gate ($governanceDocument.Contains('activeIssue=`ISSUE-COMPAT-230-EXPLORE-HARNESS-SERIAL-TIMEOUT`') -and $objectiveDocument.Contains('当前唯一源码验证议题为 `ISSUE-COMPAT-230-EXPLORE-HARNESS-SERIAL-TIMEOUT`')) 'post-transition documents do not select 230.' }
  else { Assert-Gate ($governanceDocument.Contains('activeIssue=`ISSUE-COMPAT-228-JAVA-STRING-LIST-ANALYZER-JS`') -and $objectiveDocument.Contains('下一候选为 `ISSUE-COMPAT-230-EXPLORE-HARNESS-SERIAL-TIMEOUT`')) 'pre-transition documents do not retain 230 as candidate.' }
  Assert-Gate ($ledgerDocument.Contains('活跃任务：COMPAT-006') -and $indexDocument -match '\| `ISSUE-COMPAT-230-EXPLORE-HARNESS-SERIAL-TIMEOUT` \| `verifying` \|' -and $diffDocument -match '\| `ISSUE-COMPAT-230-EXPLORE-HARNESS-SERIAL-TIMEOUT` \| `verifying` \|') 'generated documents do not retain 230 evidence.'
  if ($RequireRegistration) { Assert-Gate ((@($issue230.evidencePaths | ForEach-Object {[string]$_}) -contains $relativeOutputPath) -and $indexDocument.Contains($relativeOutputPath) -and $diffDocument.Contains($relativeOutputPath)) '230 queue gate is not registered in machine state and generated documents.' }
  Add-Check -Id 'objective_document_binding' -Detail 'The objective and generated documents preserve one active issue, the next candidate and deferred R4 semantics.' -Evidence @('tools/legado-compat/state/refactor-objective.json','docs/analysis/Legado书源V2源码重构持续目标.md','tools/legado-compat/LEGADO_V2_GOVERNANCE_TASKS.md','docs/analysis/Legado书源引擎证据索引.md','docs/analysis/Legado书源引擎差分摘要.md')

  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_r3_issue230_queue_static_gate'
    status = 'passed'
    issueId = 'ISSUE-COMPAT-230-EXPLORE-HARNESS-SERIAL-TIMEOUT'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    transition = [pscustomobject][ordered]@{ fromIssue = 'ISSUE-COMPAT-228-JAVA-STRING-LIST-ANALYZER-JS'; fromStatus = 'verifying'; toIssue = 'ISSUE-COMPAT-230-EXPLORE-HARNESS-SERIAL-TIMEOUT'; toStatus = 'verifying'; nextCandidate = 'V2-GOV-004-DOCUMENT-TASK-MIRROR'; runtimeVerification = 'deferred_to_R4' }
    affectedScope = [pscustomobject][ordered]@{ kind = 'harness_workflow_scope'; sourceCount = 458; workflow = 'explore' }
    objectiveId = [string]$objective.objectiveId
    targetRevision = [string]$objective.targetRevision
    assertions = $script:assertions
    checks = $script:checks.ToArray()
    evidencePaths = @('tools/legado-compat/evidence/contract-legado-explore-harness-terminal-error.json','tools/legado-compat/evidence/v2-terminal-workflow-settlement-contract.json','tools/legado-compat/evidence/v2-explore-harness-serial-timeout-source-fix-20260808-r2.json','tools/legado-compat/evidence/v2-explore-harness-serial-timeout-current-head-hash-audit-20260808-r1.json','tools/legado-compat/fixtures/legado-explore-harness-terminal-error.json','tools/legado-compat/fixtures/hypium-terminal-workflow-settlement.json')
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_issue230_source_closure_static_only;R4_runtime_build_device_and_legado_diff_deferred'
    registrationRequired = [bool]$RequireRegistration
  }
} catch {
  $exitCode = 1
  $result = [pscustomobject][ordered]@{ schemaVersion = 1; kind = 'legado_r3_issue230_queue_static_gate'; status = 'failed'; issueId = 'ISSUE-COMPAT-230-EXPLORE-HARNESS-SERIAL-TIMEOUT'; generatedAt = [DateTimeOffset]::UtcNow.ToString('o'); failure = $_.Exception.Message; assertions = $script:assertions; checks = $script:checks.ToArray(); evidencePaths = @(); runtimeActionsPerformed = @(); semanticMatchAllowed = $false; verificationPolicy = 'r3_issue230_source_closure_static_only;R4_runtime_build_device_and_legado_diff_deferred'; registrationRequired = [bool]$RequireRegistration }
}

$temporaryPath = "$outputFullPath.tmp.$PID.$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
[System.IO.File]::WriteAllText($temporaryPath, ($result | ConvertTo-Json -Depth 24), [System.Text.UTF8Encoding]::new($false))
Move-Item -LiteralPath $temporaryPath -Destination $outputFullPath -Force
$result | ConvertTo-Json -Depth 24
if ($exitCode -ne 0) { exit $exitCode }
