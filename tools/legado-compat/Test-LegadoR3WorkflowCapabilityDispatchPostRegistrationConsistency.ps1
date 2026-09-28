[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$OutputPath = 'tools/legado-compat/evidence/r3-workflow-capability-dispatch-037-transition-20260809/post-registration-consistency.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$script:checks = New-Object 'System.Collections.Generic.List[object]'
$script:assertions = 0

function Get-RepoPath {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictBytes {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  $path = Get-RepoPath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "required file is missing: $RelativePath"
  }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw "UTF-8 BOM is not allowed: $RelativePath"
  }
  return $bytes
}

function Read-StrictText {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  return $strictUtf8.GetString((Read-StrictBytes -RelativePath $RelativePath))
}

function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  $text = Read-StrictText -RelativePath $RelativePath
  try { return ($text | ConvertFrom-Json) }
  catch { throw "invalid JSON: $RelativePath; $($_.Exception.Message)" }
}

function Get-PropertyValue {
  param([object]$Object, [Parameter(Mandatory = $true)][string]$Name)
  if ($null -eq $Object) { return $null }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { return $null }
  return $property.Value
}

function Get-Issue {
  param([object[]]$Issues, [Parameter(Mandatory = $true)][string]$Id)
  foreach ($issue in $Issues) {
    if ([string](Get-PropertyValue -Object $issue -Name 'id') -eq $Id) { return $issue }
  }
  return $null
}

function Has-Value {
  param([object]$Object, [Parameter(Mandatory = $true)][string]$Name, [Parameter(Mandatory = $true)][string]$Expected)
  foreach ($value in @((Get-PropertyValue -Object $Object -Name $Name))) {
    if ([string]$value -eq $Expected) { return $true }
  }
  return $false
}

function Is-EmptyArray {
  param([object]$Object, [Parameter(Mandatory = $true)][string]$Name)
  $property = if ($null -eq $Object) { $null } else { $Object.PSObject.Properties[$Name] }
  if ($null -eq $property -or $null -eq $property.Value) { return $true }
  return @($property.Value).Count -eq 0
}

function Assert-Check {
  param(
    [bool]$Condition,
    [Parameter(Mandatory = $true)][string]$Id,
    [Parameter(Mandatory = $true)][string]$Detail,
    [string[]]$Evidence = @()
  )
  $script:assertions++
  if (-not $Condition) { throw "037 post-registration consistency failed [$Id]: $Detail" }
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
    [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 60), $utf8NoBom)
    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

$outputFullPath = [System.IO.Path]::GetFullPath((Get-RepoPath -RelativePath $OutputPath))
$evidenceRoot = [System.IO.Path]::GetFullPath((Get-RepoPath -RelativePath 'tools/legado-compat/evidence')).TrimEnd('\') + '\'
if (-not $outputFullPath.StartsWith($evidenceRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw 'audit output must remain under the evidence directory.'
}

$issueId = 'ISSUE-COMPAT-HYPIUM-WORKFLOW-CAPABILITY-DISPATCH'
$previousIssueId = 'ISSUE-COMPAT-238-JAVA-OBJECT-CONTENT-OVERLOAD'
$baselineHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$statePath = 'tools/legado-compat/state/full-source-validation-state.json'
$objectivePath = 'tools/legado-compat/state/refactor-objective.json'
$transitionPath = 'tools/legado-compat/evidence/r3-workflow-capability-dispatch-037-transition-20260809/transition-consistency.json'
$registrationPath = 'tools/legado-compat/evidence/r3-workflow-capability-dispatch-037-transition-20260809/registration.json'
$failurePath = 'tools/legado-compat/evidence/contract-legado-hypium-workflow-capability-dispatch-037-pre-fix.json'
$fixturePath = 'tools/legado-compat/fixtures/legado-hypium-workflow-capability-dispatch-037.json'
$contractPath = 'tools/legado-compat/evidence/contract-legado-hypium-workflow-capability-dispatch-037.json'
$headPath = 'tools/legado-compat/evidence/v2-hypium-workflow-capability-dispatch-current-head-audit-20260809.json'
$fixPath = 'tools/legado-compat/evidence/v2-hypium-workflow-capability-dispatch-source-fix-20260809.json'
$objectiveDocumentPath = 'docs/analysis/Legado书源V2源码重构持续目标.md'
$governanceDocumentPath = 'tools/legado-compat/LEGADO_V2_GOVERNANCE_TASKS.md'

$result = $null
$exitCode = 0
try {
  $state = Read-StrictJson -RelativePath $statePath
  $objective = Read-StrictJson -RelativePath $objectivePath
  $transition = Read-StrictJson -RelativePath $transitionPath
  $registration = Read-StrictJson -RelativePath $registrationPath
  $failure = Read-StrictJson -RelativePath $failurePath
  $fixture = Read-StrictJson -RelativePath $fixturePath
  $contract = Read-StrictJson -RelativePath $contractPath
  $head = Read-StrictJson -RelativePath $headPath
  $fix = Read-StrictJson -RelativePath $fixPath
  $objectiveDocument = Read-StrictText -RelativePath $objectiveDocumentPath
  $governanceDocument = Read-StrictText -RelativePath $governanceDocumentPath

  $baseline = $state.baseline
  Assert-Check ([int]$baseline.sourceCount -eq 458 -and [string]$baseline.sourcePackageSha256 -eq $baselineHash -and [string]$baseline.legadoCommit -eq $legadoCommit) 'baseline' 'state retains the frozen source and Legado baseline.' @($statePath)
  Assert-Check ([string]$state.governance.activeTaskId -eq 'COMPAT-006' -and [string]$state.governance.activeIssueId -eq $issueId -and [string]$state.governance.status -eq 'running') 'machine_queue' '037 is the only active machine queue anchor.' @($statePath)

  $issues = @($state.governance.issues)
  $issue = Get-Issue -Issues $issues -Id $issueId
  $previous = Get-Issue -Issues $issues -Id $previousIssueId
  Assert-Check ($null -ne $issue -and [string]$issue.status -eq 'verifying') 'active_issue_status' '037 remains verifying after static closure.' @($statePath)
  Assert-Check ($null -ne $previous -and [string]$previous.status -eq 'verifying') 'previous_issue_status' '238 remains verifying and is not reopened or overwritten.' @($statePath)
  foreach ($path in @($transitionPath, $registrationPath, $failurePath, $fixturePath, $contractPath, $headPath, $fixPath)) {
    Assert-Check (Has-Value -Object $issue -Name 'evidencePaths' -Expected $path) ('registered_' + $path.Replace('/', '_')) ('037 evidence is registered: ' + $path) @($statePath)
  }

  $objectiveAuthority = $objective.authority
  $objectiveBody = $objective.objective
  $executionTarget = $objective.executionTarget
  $queueAudit = $objective.continuationTarget.queueAudit
  Assert-Check ([string]$objectiveAuthority.activeIssueId -eq $issueId -and [string]$objectiveBody.activeIssue -eq $issueId -and [string]$executionTarget.currentIssue -eq $issueId) 'objective_queue' 'objective authority, body and execution target all point to 037.' @($objectivePath)
  Assert-Check ([string]$queueAudit.status -in @('post_registration_passed_queue_preflight_pending', 'preflight_passed_no_candidate') -and [string]$queueAudit.candidateIssueId -eq $issueId -and @($queueAudit.candidateIssues).Count -eq 0) 'queue_audit_state' '037 remains active with no parallel candidate after the post-registration audit.' @($objectivePath)
  Assert-Check (([string]$objective.nextAction -like '*只读核对未闭合 P0/P1 候选*' -and [string]$objective.nextAction -like '*否则保持 ISSUE-COMPAT-HYPIUM-WORKFLOW-CAPABILITY-DISPATCH verifying*') -or ([string]$objective.nextAction -like '*当前文档队列前置审计已完成*' -and [string]$objective.nextAction -like '*保持 ISSUE-COMPAT-HYPIUM-WORKFLOW-CAPABILITY-DISPATCH verifying*')) 'objective_next_action' 'objective records the bounded queue preflight and no speculative issue selection.' @($objectivePath)

  Assert-Check ([string]$transition.status -eq 'passed' -and [string]$transition.fromIssue -eq $previousIssueId -and [string]$transition.toIssue -eq $issueId -and -not [bool]$transition.semanticMatchAllowed -and (Is-EmptyArray -Object $transition -Name 'runtimeActionsPerformed')) 'transition_static_only' '238→037 transition is static-only.' @($transitionPath)
  Assert-Check ([string]$registration.status -eq 'registered' -and [string]$registration.previousIssueId -eq $previousIssueId -and [string]$registration.issueId -eq $issueId -and [string]$registration.nextIssueId -eq '' -and -not [bool]$registration.semanticMatchAllowed -and (Is-EmptyArray -Object $registration -Name 'runtimeActionsPerformed')) 'registration_static_only' '037 registration is atomic, idempotent and has no runtime claim.' @($registrationPath)
  Assert-Check ([string]$failure.status -eq 'failed' -and -not [bool]$failure.semanticMatchAllowed -and (Is-EmptyArray -Object $failure -Name 'runtimeActionsPerformed')) 'failure_witness_static_only' '037 failure witness remains a static contract.' @($failurePath)
  Assert-Check (@($fixture.cases).Count -eq 6 -and [string]$contract.status -eq 'passed' -and [int]$contract.assertions -ge 29 -and [string]$head.status -eq 'passed' -and [int]$head.assertions -ge 27 -and [string]$fix.status -eq 'source_closed_static_only') 'source_evidence' '037 fixture, contract, current-head and source-fix evidence are complete.' @($fixturePath, $contractPath, $headPath, $fixPath)
  Assert-Check (-not [bool]$contract.semanticMatchAllowed -and -not [bool]$head.semanticMatchAllowed -and -not [bool]$fix.semanticMatchAllowed) 'semantic_gate' 'static evidence cannot produce semantic_match.' @($contractPath, $headPath, $fixPath)

  Assert-Check ($objectiveDocument.Contains('当前唯一活动源码锚点为 `ISSUE-COMPAT-HYPIUM-WORKFLOW-CAPABILITY-DISPATCH`') -and -not $objectiveDocument.Contains('当前唯一活动源码锚点为 `ISSUE-COMPAT-238-JAVA-OBJECT-CONTENT-OVERLOAD`')) 'objective_document' 'objective document names 037 as current and does not retain the stale 238 current-anchor claim.' @($objectiveDocumentPath)
  Assert-Check ($governanceDocument.Contains('当前唯一活动根因议题为 `ISSUE-COMPAT-HYPIUM-WORKFLOW-CAPABILITY-DISPATCH`') -and -not $governanceDocument.Contains('当前唯一活动根因议题为 `ISSUE-COMPAT-238-JAVA-OBJECT-CONTENT-OVERLOAD`')) 'governance_document' 'governance narrative names 037 as current and preserves 238 as verifying history.' @($governanceDocumentPath)

  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_r3_workflow_capability_dispatch_037_post_registration_consistency'
    status = 'passed'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    objectiveId = [string]$objective.objectiveId
    targetRevision = [string]$objective.targetRevision
    activeIssueId = $issueId
    previousIssueId = $previousIssueId
    baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
    assertions = $script:assertions
    checks = $script:checks.ToArray()
    evidencePaths = @($statePath, $objectivePath, $transitionPath, $registrationPath, $failurePath, $fixturePath, $contractPath, $headPath, $fixPath, $objectiveDocumentPath, $governanceDocumentPath)
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_post_registration_static_consistency_only;037_verifying;R4_runtime_build_device_and_legado_diff_deferred'
  }
} catch {
  $exitCode = 1
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_r3_workflow_capability_dispatch_037_post_registration_consistency'
    status = 'failed'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    failure = $_.Exception.Message
    assertions = $script:assertions
    checks = $script:checks.ToArray()
    evidencePaths = @()
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_post_registration_static_consistency_only;037_verifying;R4_runtime_build_device_and_legado_diff_deferred'
  }
}

Write-AtomicJson -Path $outputFullPath -Value $result
$result | ConvertTo-Json -Depth 60
if ($exitCode -ne 0) { exit $exitCode }
