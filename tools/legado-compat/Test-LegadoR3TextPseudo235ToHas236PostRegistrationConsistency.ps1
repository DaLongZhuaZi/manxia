[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$RunId = 'r3-jsoup-text-pseudo-235-to-has-236-post-registration-20260809',
  [string]$OutputPath = '',
  [string]$GateEvidencePath = 'tools/legado-compat/evidence/r3-jsoup-text-pseudo-235-to-has-236-transition-20260809/transition-consistency.json',
  [string]$RegistrationEvidencePath = 'tools/legado-compat/evidence/r3-jsoup-text-pseudo-235-to-has-236-transition-20260809/registration.json',
  [string]$Target235Path = 'tools/legado-compat/evidence/r3-actual-docs-source-refactor-target-20260809-235-text-whitespace/target.json',
  [string]$Target236Path = 'tools/legado-compat/evidence/r3-jsoup-has-236-target-20260809/target.json',
  [string]$CurrentSourceFixPath = 'tools/legado-compat/evidence/v2-jsoup-has-pseudo-selector-source-fix-20260809.json',
  [string]$CurrentHeadEvidencePath = 'tools/legado-compat/evidence/v2-jsoup-has-pseudo-selector-current-head-audit-20260809-r2.json',
  [string]$PreFixEvidencePath = 'tools/legado-compat/evidence/contract-legado-jsoup-has-pseudo-selector-pre-fix-20260809-r2.json',
  [string]$StaticContractPath = 'tools/legado-compat/evidence/contract-legado-jsoup-has-pseudo-selector.json',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-has-pseudo-selector.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$evidenceRoot = [System.IO.Path]::GetFullPath((Join-Path $RepositoryRoot 'tools\legado-compat\evidence')).TrimEnd('\') + '\'
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = Join-Path $evidenceRoot (Join-Path $RunId 'post-registration-consistency.json')
}
$outputFullPath = [System.IO.Path]::GetFullPath($OutputPath)
if (-not $outputFullPath.StartsWith($evidenceRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw 'post-registration evidence must remain under the evidence directory.'
}

$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$script:assertions = 0
$script:checks = New-Object 'System.Collections.Generic.List[object]'

function Get-RepoPath {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  $path = Get-RepoPath -RelativePath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "required JSON is missing: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw "UTF-8 BOM is not allowed: $RelativePath"
  }
  try { return ($strictUtf8.GetString($bytes) | ConvertFrom-Json) }
  catch { throw "invalid JSON: $RelativePath; $($_.Exception.Message)" }
}

function Read-StrictText {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  $path = Get-RepoPath -RelativePath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "required text is missing: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw "UTF-8 BOM is not allowed: $RelativePath"
  }
  return $strictUtf8.GetString($bytes)
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
    if ([string](Get-PropertyValue -Object $issue -Name 'id') -eq $Id) { return $issue }
  }
  return $null
}

function Contains-Evidence {
  param([object]$Issue, [string]$Path)
  foreach ($value in @((Get-PropertyValue -Object $Issue -Name 'evidencePaths' -Default @()))) {
    if ([string]$value -eq $Path) { return $true }
  }
  return $false
}

function Assert-Consistency {
  param([bool]$Condition, [string]$Id, [string]$Detail, [string[]]$Evidence = @())
  if (-not $Condition) { throw "post-registration consistency blocked: $Detail" }
  $script:assertions++
  [void]$script:checks.Add([pscustomobject][ordered]@{
      id = $Id
      status = 'passed'
      detail = $Detail
      evidencePaths = @($Evidence)
    })
}

function Write-AtomicJson {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value)
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  }
  $temporaryPath = "$Path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 50), $utf8NoBom)
    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

$baseline = $null
$result = $null
$exitCode = 0
try {
  $state = Read-StrictJson -RelativePath 'tools/legado-compat/state/full-source-validation-state.json'
  $objective = Read-StrictJson -RelativePath 'tools/legado-compat/state/refactor-objective.json'
  $gate = Read-StrictJson -RelativePath $GateEvidencePath
  $registration = Read-StrictJson -RelativePath $RegistrationEvidencePath
  $target235 = Read-StrictJson -RelativePath $Target235Path
  $target236 = Read-StrictJson -RelativePath $Target236Path
  $sourceFix = Read-StrictJson -RelativePath $CurrentSourceFixPath
  $currentHead = Read-StrictJson -RelativePath $CurrentHeadEvidencePath
  $preFix = Read-StrictJson -RelativePath $PreFixEvidencePath
  $staticContract = Read-StrictJson -RelativePath $StaticContractPath
  $fixture = Read-StrictJson -RelativePath $FixturePath
  $baseline = $state.baseline

  $baselineEvidence = @('tools/legado-compat/state/full-source-validation-state.json', 'tools/legado-compat/state/refactor-objective.json')
  Assert-Consistency ([int]$baseline.sourceCount -eq 458 -and [string]$baseline.sourcePackageSha256 -eq '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67' -and [string]$baseline.legadoCommit -eq '95973d186b147fb9ab43a9240021d688e4304fbd') 'baseline' 'fixed source and Legado baselines are unchanged.' $baselineEvidence
  Assert-Consistency ([string]$state.governance.activeTaskId -eq 'COMPAT-006' -and [string]$state.governance.activeIssueId -eq 'ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR' -and [string]$state.governance.status -eq 'running') 'machine_queue' 'machine queue points to 236 as the sole active issue.' $baselineEvidence
  Assert-Consistency ([string]$objective.authority.activeIssueId -eq 'ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR' -and [string]$objective.executionTarget.currentIssue -eq 'ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR' -and @($objective.executionTarget.nextIssues) -contains 'ISSUE-COMPAT-237-JSOUP-INDEX-PSEUDO-SELECTORS') 'objective_queue' 'objective queue agrees with the machine queue and 237 remains the next candidate.' @('tools/legado-compat/state/refactor-objective.json')
  Assert-Consistency ([string]$objective.targetRevision -eq '2026-08-09-actual-docs-source-refactor-continuation-jsoup-has-pseudo-236-033') 'objective_revision' 'objective revision is the registered 236 revision.' @('tools/legado-compat/state/refactor-objective.json')

  $issues = @($state.governance.issues)
  $issue235 = Get-Issue -Issues $issues -Id 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS'
  $issue236 = Get-Issue -Issues $issues -Id 'ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR'
  Assert-Consistency ($null -ne $issue235 -and [string]$issue235.status -eq 'verifying' -and $null -ne $issue236 -and [string]$issue236.status -eq 'verifying') 'issue_statuses' '235 and 236 remain verifying-only.' @('tools/legado-compat/state/full-source-validation-state.json')
  foreach ($path in @($GateEvidencePath, $RegistrationEvidencePath, 'tools/legado-compat/evidence/r3-jsoup-text-whitespace-235-static-audit-20260809/static-audit.json')) {
    Assert-Consistency (Contains-Evidence -Issue $issue235 -Path $path) ('issue235_evidence_' + $path.Replace('/', '_')) ('235 evidence is registered: ' + $path) @('tools/legado-compat/state/full-source-validation-state.json')
  }
  foreach ($path in @($GateEvidencePath, $RegistrationEvidencePath, $CurrentSourceFixPath, $CurrentHeadEvidencePath, $StaticContractPath, $FixturePath)) {
    Assert-Consistency (Contains-Evidence -Issue $issue236 -Path $path) ('issue236_evidence_' + $path.Replace('/', '_')) ('236 evidence is registered: ' + $path) @('tools/legado-compat/state/full-source-validation-state.json')
  }

  Assert-Consistency ([string]$gate.status -eq 'passed' -and [string]$gate.fromIssue -eq 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS' -and [string]$gate.toIssue -eq 'ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR' -and [string]$gate.nextCandidateAfterRegistration -eq 'ISSUE-COMPAT-237-JSOUP-INDEX-PSEUDO-SELECTORS' -and -not [bool]$gate.semanticMatchAllowed -and @($gate.runtimeActionsPerformed).Count -eq 0) 'transition_gate' '235 to 236 transition is static-only and names 237 as next candidate.' @($GateEvidencePath)
  Assert-Consistency ([string]$registration.status -eq 'registered' -and [string]$registration.previousIssueId -eq 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS' -and [string]$registration.issueId -eq 'ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR' -and [string]$registration.nextIssueId -eq 'ISSUE-COMPAT-237-JSOUP-INDEX-PSEUDO-SELECTORS' -and -not [bool]$registration.semanticMatchAllowed -and @($registration.runtimeActionsPerformed).Count -eq 0) 'registration' 'registration evidence is idempotent and contains no runtime claim.' @($RegistrationEvidencePath)
  Assert-Consistency ([string]$target235.nextIssueId -eq 'ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR' -and [string]$target235.status -eq 'completed_static_only') 'target235' '235 target is closed only for the static stage.' @($Target235Path)
  Assert-Consistency ([string]$target236.issueId -eq 'ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR' -and [string]$target236.currentStatus -eq 'source_closed_static_only' -and [string]$target236.currentSubstage -eq '236-WS-05') 'target236' '236 target keeps its R4 handoff deferred.' @($Target236Path)
  Assert-Consistency ([string]$sourceFix.issueId -eq 'ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR' -and [string]$sourceFix.status -eq 'source_closed_static_only' -and -not [bool]$sourceFix.semanticMatchAllowed -and @($sourceFix.runtimeActionsPerformed).Count -eq 0) 'source_fix' '236 source-fix evidence is static-only.' @($CurrentSourceFixPath)
  Assert-Consistency ([string]$preFix.issueId -eq 'ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR' -and [string]$preFix.status -eq 'failed' -and -not [bool]$preFix.semanticMatchAllowed -and @($preFix.runtimeActionsPerformed).Count -eq 0) 'failure_witness' '236 failure witness is preserved and static-only.' @($PreFixEvidencePath)
  Assert-Consistency ([string]$currentHead.status -eq 'passed' -and -not [bool]$currentHead.semanticMatchAllowed -and @($currentHead.runtimeActionsPerformed).Count -eq 0) 'current_head' '236 current-head audit is static-only.' @($CurrentHeadEvidencePath)
  Assert-Consistency ([string]$staticContract.status -eq 'passed' -and [int]$staticContract.assertions -eq 15) 'static_contract' '236 static contract has the expected 15 assertions.' @($StaticContractPath)
  Assert-Consistency ([int]$fixture.cases.Count -eq 5) 'fixture' '236 fixture retains its five cases.' @($FixturePath)

  $objectiveDocument = Read-StrictText -RelativePath 'docs/analysis/Legado书源V2源码重构持续目标.md'
  $governanceDocument = Read-StrictText -RelativePath 'tools/legado-compat/LEGADO_V2_GOVERNANCE_TASKS.md'
  Assert-Consistency ($objectiveDocument.Contains('当前唯一活动源码锚点为 `ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR`') -and $objectiveDocument.Contains('下一候选为 237') -and -not $objectiveDocument.Contains('235→236 前置门禁待执行') -and -not $objectiveDocument.Contains('236 尚未激活') -and -not $objectiveDocument.Contains('235 已通过独立失败合同、源码修复、静态合同和 234→235 转移门禁成为唯一活动议题')) 'objective_document' 'objective document has no stale pre-transition text.' @('docs/analysis/Legado书源V2源码重构持续目标.md')
  Assert-Consistency ($governanceDocument.Contains('当前唯一活动根因议题为 `ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR`') -and -not $governanceDocument.Contains('235→236 前置门禁待执行') -and -not $governanceDocument.Contains('235 原子成为唯一活动源码议题')) 'governance_document' 'governance mirror has no stale 235 queue claim.' @('tools/legado-compat/LEGADO_V2_GOVERNANCE_TASKS.md')

  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_r3_text_pseudo_235_to_has_236_post_registration_consistency'
    status = 'passed'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    runId = $RunId
    objectiveId = [string]$objective.objectiveId
    targetRevision = [string]$objective.targetRevision
    activeIssueId = 'ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR'
    nextIssueId = 'ISSUE-COMPAT-237-JSOUP-INDEX-PSEUDO-SELECTORS'
    baseline = [pscustomobject][ordered]@{ sourceCount = [int]$baseline.sourceCount; sourcePackageSha256 = [string]$baseline.sourcePackageSha256; legadoCommit = [string]$baseline.legadoCommit }
    assertions = $script:assertions
    checks = $script:checks.ToArray()
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_post_registration_static_consistency_only;R4_runtime_build_device_and_legado_diff_deferred'
  }
} catch {
  $exitCode = 1
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_r3_text_pseudo_235_to_has_236_post_registration_consistency'
    status = 'failed'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    runId = $RunId
    failure = $_.Exception.Message
    assertions = $script:assertions
    checks = $script:checks.ToArray()
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_post_registration_static_consistency_only;R4_runtime_build_device_and_legado_diff_deferred'
  }
}

Write-AtomicJson -Path $outputFullPath -Value $result
$result | ConvertTo-Json -Depth 50
if ($exitCode -ne 0) { exit $exitCode }
