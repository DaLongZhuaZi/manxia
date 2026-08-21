[CmdletBinding()]
param(
  [string]$RepositoryRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$sourceCount = 458
$sourceHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$issueId = 'ISSUE-COMPAT-242-TRACE-BRIDGE-PRESERVATION'
$taskId = 'COMPAT-006'
$contractRelative = 'tools/legado-compat/Test-LegadoTraceGraphConstructionAudit.ps1'
$evidenceRelative = 'tools/legado-compat/evidence/v2-trace-graph-construction-audit-20260809.json'
$stateRelative = 'tools/legado-compat/state/full-source-validation-state.json'
$objectiveRelative = 'tools/legado-compat/state/refactor-objective.json'

function Get-RepoPath([string]$RelativePath) {
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Write-AtomicJson([string]$RelativePath, [object]$Value) {
  $path = Get-RepoPath $RelativePath
  $directory = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  }
  $temporary = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 40), $utf8NoBom)
    Move-Item -LiteralPath $temporary -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) }
  }
}

function Set-PropertyValue([object]$Object, [string]$Name, [object]$Value) {
  if ($null -eq $Object.PSObject.Properties[$Name]) {
    $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
  } else {
    $Object.$Name = $Value
  }
}

$contractPath = Get-RepoPath $contractRelative
$output = & pwsh -NoLogo -NoProfile -NonInteractive -File $contractPath -RepositoryRoot $RepositoryRoot 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
  throw "Trace graph construction audit failed: $output"
}
$contract = $output.Trim() | ConvertFrom-Json
$runtimeRelative = 'entry/src/main/ets/Framework/Novel/LegadoWorkflowOrchestrator.ets'
$typesRelative = 'entry/src/main/ets/Framework/Novel/LegadoCompatibilityTypes.ets'
$analyzerRelative = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
$runtimeV2Relative = 'entry/src/main/ets/Framework/Novel/LegadoRuntimeV2.ets'
$sourceScriptRuntimeRelative = 'entry/src/main/ets/Framework/Novel/LegadoSourceScriptRuntime.ets'
$serializerRelative = 'entry/src/main/ets/Framework/Novel/LegadoTraceSerializer.ets'
$testOnlyConformancePageRelative = 'entry/src/main/ets/pages/LegadoArkWebConformancePage.ets'
$testOnlyConformanceAbilityRelative = 'entry/src/main/ets/LegadoArkWebConformanceAbility.ets'
$now = [DateTimeOffset]::UtcNow.ToString('o')
$evidence = [ordered]@{
  schemaVersion = 1
  kind = 'legado_trace_graph_construction_audit'
  status = [string]$contract.status
  issueId = $issueId
  generatedAt = $now
  baseline = [ordered]@{ sourceCount = $sourceCount; sourcePackageSha256 = $sourceHash; legadoCommit = $legadoCommit }
  contractPath = $contractRelative
  contractSha256 = (Get-FileHash -LiteralPath $contractPath -Algorithm SHA256).Hash.ToUpperInvariant()
  sourceFixPaths = @($runtimeRelative, $typesRelative, $analyzerRelative, $runtimeV2Relative, $sourceScriptRuntimeRelative, $serializerRelative)
  testOnlyPaths = @($testOnlyConformancePageRelative, $testOnlyConformanceAbilityRelative)
  sourceFixHashes = [ordered]@{
    runtime = (Get-FileHash -LiteralPath (Get-RepoPath $runtimeRelative) -Algorithm SHA256).Hash.ToUpperInvariant()
    types = (Get-FileHash -LiteralPath (Get-RepoPath $typesRelative) -Algorithm SHA256).Hash.ToUpperInvariant()
    analyzer = (Get-FileHash -LiteralPath (Get-RepoPath $analyzerRelative) -Algorithm SHA256).Hash.ToUpperInvariant()
    runtimeV2 = (Get-FileHash -LiteralPath (Get-RepoPath $runtimeV2Relative) -Algorithm SHA256).Hash.ToUpperInvariant()
    sourceScriptRuntime = (Get-FileHash -LiteralPath (Get-RepoPath $sourceScriptRuntimeRelative) -Algorithm SHA256).Hash.ToUpperInvariant()
    serializer = (Get-FileHash -LiteralPath (Get-RepoPath $serializerRelative) -Algorithm SHA256).Hash.ToUpperInvariant()
  }
  traceConstructionCount = [int]$contract.traceConstructionCount
  testOnlyTraceConstructionCount = [int]$contract.testOnlyTraceConstructionCount
  assertionCount = [int]$contract.assertionCount
  sameTraceMutationMethods = @($contract.sameTraceMutationMethods)
  newTraceMethods = @($contract.newTraceMethods)
  bridgeProducingTraceMethods = @($contract.bridgeProducingTraceMethods)
  testOnlyTraceMethods = @($contract.testOnlyTraceMethods)
  testOnlyConformancePageSha256 = (Get-FileHash -LiteralPath (Get-RepoPath $testOnlyConformancePageRelative) -Algorithm SHA256).Hash.ToUpperInvariant()
  testOnlyConformanceAbilitySha256 = (Get-FileHash -LiteralPath (Get-RepoPath $testOnlyConformanceAbilityRelative) -Algorithm SHA256).Hash.ToUpperInvariant()
  conclusion = 'All production LegadoExecutionTrace construction sites and the dedicated test-only conformance construction are classified. Existing-trace mutations use replaceTrace; pre-request failures are explicit fresh traces; script-produced bridge evidence is passed into the immutable constructor. The conformance page is excluded from normal source workflows and consumes only local deterministic fixtures.'
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  execution = 'static_source_graph_contract_only'
  runtimeRegression = 'not_run'
  deviceRegression = 'not_run'
  verificationPolicy = 'r3_242_static_audit_only;R4_runtime_build_device_and_legado_diff_deferred'
  closeCondition = 'R4 must execute the affected ordinal 3 Content/timeout equivalence class, deterministic full Harness, same-input Legado differential, build and device gates; static graph closure is not semantic compatibility.'
}
Write-AtomicJson $evidenceRelative $evidence

# Keep the execution policy pointer truthful after the audit.  The objective
# is not a second status ledger, but stale next-action text can still dispatch
# an already-completed static step or accidentally suggest R4.
$objectivePath = Get-RepoPath $objectiveRelative
$objective = [System.IO.File]::ReadAllText($objectivePath, [System.Text.UTF8Encoding]::new($false, $true)) | ConvertFrom-Json
if ([int]$objective.baseline.sourceCount -ne $sourceCount -or
  [string]$objective.baseline.sourcePackageSha256 -ne $sourceHash -or
  [string]$objective.baseline.legadoCommit -ne $legadoCommit) {
  throw 'Refactor objective baseline drifted.'
}
$objective.lastReviewedAt = $now
Set-PropertyValue $objective 'continuationMode' 'R3_ISSUE_242_TRACE_GRAPH_AUDIT_STATIC_CLOSED_WAIT_R4'
Set-PropertyValue $objective 'nextAction' '242 trace graph construction audit 已完成且已区分生产入口与 test-only conformance 入口；继续保持 242 verifying，R4 运行时、Legado 差分、构建和设备验证仍延期。'
Set-PropertyValue $objective.objective 'currentWorkstream' 'R3-ISSUE-242-TRACE-MUTATION-BRIDGE-PRESERVATION'
Set-PropertyValue $objective.executionTarget 'statement' '在固定 458 条基线下，242 的 Analyzer bridgeTraces 链路、五个普通 mutation、同一活动请求 timeout lineage、request/response/bridge 嵌套数组快照、7 个生产 LegadoExecutionTrace 构造入口和 1 个 test-only conformance 构造入口均已通过静态证据审计；状态保持 verifying，R4 运行时、Legado 差分、构建和设备验证延期。'
Set-PropertyValue $objective.continuationTarget 'activeBoundary' 'ISSUE-COMPAT-242 保持 verifying：生产 trace graph 与 test-only conformance trace 构造入口均已分类，既有 trace mutation 使用 replaceTrace，预请求失败使用显式新 trace，脚本桥接证据进入不可变构造函数；R4 deferred。'
$queueAudit = $objective.continuationTarget.queueAudit
Set-PropertyValue $queueAudit 'traceGraphAuditEvidencePath' $evidenceRelative
Set-PropertyValue $queueAudit 'status' 'trace_graph_static_audit_closed_wait_r4'
Write-AtomicJson $objectiveRelative $objective

$updateScript = Get-RepoPath 'tools/legado-compat/Update-LegadoGovernanceState.ps1'
& pwsh -NoLogo -NoProfile -NonInteractive -File $updateScript `
  -StatePath (Get-RepoPath $stateRelative) `
  -IssueId $issueId `
  -IssueStatus verifying `
  -TaskId $taskId `
  -TaskStatus running `
  -Severity P0 `
  -Summary '242 trace graph construction audit passed static-only: all production LegadoExecutionTrace construction sites and the dedicated test-only conformance construction are classified; existing-trace mutations use replaceTrace, pre-request failures are explicit fresh traces, and script-produced bridge evidence enters the immutable constructor. R4 deferred.' `
  -CloseCondition 'R4 完成 ordinal 3 Content/timeout 等价类、458 条 Harness、Legado 差分、构建和真机门禁后，才允许 242 passed/semantic_match。' `
  -EvidencePath $evidenceRelative `
  -SourceOrdinal 3 `
  -SourceId 'F4FED60D32DD390B8F21FDA90B2435A614A7970C16E038D6A4D0242783E1B45C' `
  -AppendSourceIssue | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Governance state update failed.' }

$attachScript = Get-RepoPath 'tools/legado-compat/Set-LegadoRefactorObjective.ps1'
& pwsh -NoLogo -NoProfile -NonInteractive -File $attachScript `
  -StatePath (Get-RepoPath $stateRelative) `
  -ObjectivePath (Get-RepoPath $objectiveRelative) `
  -ActiveIssueId $issueId | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Objective attachment failed.' }

Write-Output ('TRACE_GRAPH_AUDIT_REGISTERED issue={0} status=verifying evidence={1}' -f $issueId, $evidenceRelative)
