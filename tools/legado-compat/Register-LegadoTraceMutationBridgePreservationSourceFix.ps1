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

$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$sourceCount = 458
$sourceHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$issueId = 'ISSUE-COMPAT-242-TRACE-BRIDGE-PRESERVATION'
$taskId = 'COMPAT-006'
$revision = '2026-08-09-actual-docs-source-refactor-trace-bridge-preservation-242-result-boundary'
$runtimeRelative = 'entry/src/main/ets/Framework/Novel/LegadoWorkflowOrchestrator.ets'
$sourceScriptRuntimeRelative = 'entry/src/main/ets/Framework/Novel/LegadoSourceScriptRuntime.ets'
$analyzerRelative = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
$typesRelative = 'entry/src/main/ets/Framework/Novel/LegadoCompatibilityTypes.ets'
$fixtureRelative = 'tools/legado-compat/fixtures/legado-trace-mutation-bridge-preservation.json'
$contractRelative = 'tools/legado-compat/Test-LegadoV2TraceMutationBridgePreservationContract.ps1'
$contractEvidenceRelative = 'tools/legado-compat/evidence/contract-legado-trace-mutation-bridge-preservation-20260809.json'
$failureEvidenceRelative = 'tools/legado-compat/evidence/contract-legado-trace-mutation-bridge-preservation-pre-fix-20260809.json'
$timeoutFixtureRelative = 'tools/legado-compat/fixtures/legado-trace-timeout-bridge-preservation.json'
$timeoutContractRelative = 'tools/legado-compat/Test-LegadoV2TraceTimeoutBridgePreservationContract.ps1'
$timeoutContractEvidenceRelative = 'tools/legado-compat/evidence/contract-legado-trace-timeout-bridge-preservation-20260809.json'
$timeoutFailureEvidenceRelative = 'tools/legado-compat/evidence/contract-legado-trace-timeout-bridge-preservation-pre-fix-20260809.json'
$immutableFixtureRelative = 'tools/legado-compat/fixtures/legado-trace-immutable-array-preservation.json'
$immutableContractRelative = 'tools/legado-compat/Test-LegadoV2TraceImmutableArrayContract.ps1'
$immutablePreFixEvidenceRelative = 'tools/legado-compat/evidence/contract-legado-trace-immutable-array-preservation-pre-fix-20260809.json'
$immutableContractEvidenceRelative = 'tools/legado-compat/evidence/contract-legado-trace-immutable-array-preservation-20260809.json'
$nestedFixtureRelative = 'tools/legado-compat/fixtures/legado-trace-nested-array-preservation.json'
$nestedContractRelative = 'tools/legado-compat/Test-LegadoV2TraceNestedArrayContract.ps1'
$nestedPreFixEvidenceRelative = 'tools/legado-compat/evidence/contract-legado-trace-nested-array-preservation-pre-fix-20260809.json'
$nestedContractEvidenceRelative = 'tools/legado-compat/evidence/contract-legado-trace-nested-array-preservation-20260809.json'
$resultFixtureRelative = 'tools/legado-compat/fixtures/legado-source-script-result-array-preservation.json'
$resultPreFixEvidenceRelative = 'tools/legado-compat/evidence/contract-legado-source-script-result-array-preservation-pre-fix-20260809.json'
$resultContractRelative = 'tools/legado-compat/Test-LegadoSourceScriptResultArrayPreservationContract.ps1'
$resultContractEvidenceRelative = 'tools/legado-compat/evidence/contract-legado-source-script-result-array-preservation-20260809.json'
$sourceFixEvidenceRelative = 'tools/legado-compat/evidence/v2-trace-mutation-bridge-preservation-source-fix-20260809.json'
$registrationEvidenceRelative = 'tools/legado-compat/evidence/r3-trace-mutation-bridge-preservation-registration-20260809/registration.json'

function Get-RepoPath([string]$RelativePath) {
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictJson([string]$RelativePath) {
  $path = Get-RepoPath $RelativePath
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw "UTF-8 BOM is not allowed: $RelativePath"
  }
  return $strictUtf8.GetString($bytes) | ConvertFrom-Json
}

function Set-PropertyValue([object]$Object, [string]$Name, [object]$Value) {
  if ($null -eq $Object.PSObject.Properties[$Name]) {
    $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
  } else {
    $Object.$Name = $Value
  }
}

function Write-AtomicJson([string]$RelativePath, [object]$Value) {
  $path = Get-RepoPath $RelativePath
  $directory = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  }
  $temporary = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 80), $noBomUtf8)
    Move-Item -LiteralPath $temporary -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) }
  }
}

function Invoke-StaticContract {
  $contractPath = Get-RepoPath $contractRelative
  $output = & pwsh -NoLogo -NoProfile -NonInteractive -File $contractPath -RepositoryRoot $RepositoryRoot 2>&1 | Out-String
  if ($LASTEXITCODE -ne 0) {
    throw "Trace mutation contract failed: $output"
  }
  return ($output.Trim() | ConvertFrom-Json)
}

function Invoke-TimeoutStaticContract {
  $contractPath = Get-RepoPath $timeoutContractRelative
  $output = & pwsh -NoLogo -NoProfile -NonInteractive -File $contractPath -RepositoryRoot $RepositoryRoot 2>&1 | Out-String
  if ($LASTEXITCODE -ne 0) {
    throw "Timeout bridge preservation contract failed: $output"
  }
  return ($output.Trim() | ConvertFrom-Json)
}

function Invoke-ImmutableArrayStaticContract {
  $contractPath = Get-RepoPath $immutableContractRelative
  $output = & pwsh -NoLogo -NoProfile -NonInteractive -File $contractPath -RepositoryRoot $RepositoryRoot 2>&1 | Out-String
  if ($LASTEXITCODE -ne 0) {
    throw "Trace immutable-array contract failed: $output"
  }
  return ($output.Trim() | ConvertFrom-Json)
}

function Invoke-NestedArrayStaticContract {
  $contractPath = Get-RepoPath $nestedContractRelative
  $output = & pwsh -NoLogo -NoProfile -NonInteractive -File $contractPath -RepositoryRoot $RepositoryRoot 2>&1 | Out-String
  if ($LASTEXITCODE -ne 0) {
    throw "Trace nested-array contract failed: $output"
  }
  return ($output.Trim() | ConvertFrom-Json)
}

function Invoke-SourceScriptResultStaticContract {
  $contractPath = Get-RepoPath $resultContractRelative
  $output = & pwsh -NoLogo -NoProfile -NonInteractive -File $contractPath -RepositoryRoot $RepositoryRoot 2>&1 | Out-String
  if ($LASTEXITCODE -ne 0) {
    throw "Source-script result array contract failed: $output"
  }
  return ($output.Trim() | ConvertFrom-Json)
}

function Get-Sha256([string]$RelativePath) {
  return (Get-FileHash -LiteralPath (Get-RepoPath $RelativePath) -Algorithm SHA256).Hash.ToUpperInvariant()
}

$stateRelative = 'tools/legado-compat/state/full-source-validation-state.json'
$objectiveRelative = 'tools/legado-compat/state/refactor-objective.json'
$state = Read-StrictJson $stateRelative
$objective = Read-StrictJson $objectiveRelative
if ([int]$state.baseline.sourceCount -ne $sourceCount -or [string]$state.baseline.sourcePackageSha256 -ne $sourceHash -or [string]$state.baseline.legadoCommit -ne $legadoCommit) {
  throw 'Machine baseline drifted.'
}
if ([int]$objective.baseline.sourceCount -ne $sourceCount -or [string]$objective.baseline.sourcePackageSha256 -ne $sourceHash -or [string]$objective.baseline.legadoCommit -ne $legadoCommit) {
  throw 'Objective baseline drifted.'
}

$contract = Invoke-StaticContract
$timeoutContract = Invoke-TimeoutStaticContract
$immutableContract = Invoke-ImmutableArrayStaticContract
$nestedContract = Invoke-NestedArrayStaticContract
$resultContract = Invoke-SourceScriptResultStaticContract
$timeoutFailureWitness = Read-StrictJson $timeoutFailureEvidenceRelative
if ([string]$timeoutFailureWitness.status -ne 'failed_static_only' -or [string]$timeoutFailureWitness.issueId -ne $issueId) {
  throw 'Timeout bridge preservation failure witness is missing or has drifted.'
}
$now = [DateTimeOffset]::UtcNow.ToString('o')
$runtimeHash = Get-Sha256 $runtimeRelative
$analyzerHash = Get-Sha256 $analyzerRelative
$fixtureHash = Get-Sha256 $fixtureRelative
$contractHash = Get-Sha256 $contractRelative
$timeoutFixtureHash = Get-Sha256 $timeoutFixtureRelative
$timeoutContractHash = Get-Sha256 $timeoutContractRelative
$typesHash = Get-Sha256 $typesRelative
$immutableFixtureHash = Get-Sha256 $immutableFixtureRelative
$immutableContractHash = Get-Sha256 $immutableContractRelative
$nestedFixtureHash = Get-Sha256 $nestedFixtureRelative
$nestedContractHash = Get-Sha256 $nestedContractRelative
$resultFixtureHash = Get-Sha256 $resultFixtureRelative
$resultContractHash = Get-Sha256 $resultContractRelative
$sourceScriptRuntimeHash = Get-Sha256 $sourceScriptRuntimeRelative
$immutablePreFixEvidence = Read-StrictJson $immutablePreFixEvidenceRelative
if ([string]$immutablePreFixEvidence.status -ne 'failed_static_only' -or [string]$immutablePreFixEvidence.issueId -ne $issueId) {
  throw 'Immutable-array failure witness is missing or has drifted.'
}
$nestedPreFixEvidence = Read-StrictJson $nestedPreFixEvidenceRelative
if ([string]$nestedPreFixEvidence.status -ne 'failed_static_only' -or [string]$nestedPreFixEvidence.issueId -ne $issueId) {
  throw 'Nested-array failure witness is missing or has drifted.'
}
$resultPreFixEvidence = Read-StrictJson $resultPreFixEvidenceRelative
if ([string]$resultPreFixEvidence.status -ne 'failed_static_only' -or [string]$resultPreFixEvidence.issueId -ne $issueId) {
  throw 'Source-script result array failure witness is missing or has drifted.'
}

# This witness records the source inspection that preceded the fix. It is
# intentionally a structural witness: no runtime, network, response body or
# user data is needed to reproduce the loss of bridge evidence.
$failureWitness = [ordered]@{
  schemaVersion = 1
  kind = 'legado_trace_mutation_bridge_preservation_failure_witness'
  status = 'failed_static_only'
  issueId = $issueId
  generatedAt = $now
  baseline = [ordered]@{ sourceCount = $sourceCount; sourcePackageSha256 = $sourceHash; legadoCommit = $legadoCommit }
  runtimePath = $runtimeRelative
  analyzerPath = $analyzerRelative
  observedBeforeFix = [ordered]@{
    mutationMethods = @('markWorkflowException', 'syncVariables', 'refreshTraceOutput', 'blockProtectedResponse', 'markBookInfoRuleFailure')
    missingBridgeArgument = $true
    analyzerBridgeTraceConsumerMissing = $true
    consequence = 'a later output, variable or error rewrite replaced the trace with bridgeTraces defaulting to an empty list'
  }
  reproduction = 'Inspect LegadoRuleAnalyzer.ets to verify every JS bridge result is recorded in the analyzer bridgeTraces accumulator, then inspect each listed workflow mutation method and assert its reconstructed LegadoExecutionTrace call consumes the existing or merged trace.bridgeTraces value.'
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  runtimeRegression = 'not_run'
  deviceRegression = 'not_run'
}
Write-AtomicJson $failureEvidenceRelative $failureWitness

$contractEvidence = [ordered]@{
  schemaVersion = 1
  kind = 'legado_trace_mutation_bridge_preservation_contract'
  status = [string]$contract.status
  issueId = $issueId
  generatedAt = $now
  baseline = [ordered]@{ sourceCount = $sourceCount; sourcePackageSha256 = $sourceHash; legadoCommit = $legadoCommit }
  fixturePath = $fixtureRelative
  fixtureSha256 = $fixtureHash
  contractPath = $contractRelative
  contractSha256 = $contractHash
  analyzerPath = $analyzerRelative
  analyzerSha256 = $analyzerHash
  assertionCount = [int]$contract.assertionCount
  mutationMethods = @($contract.mutationMethods)
  traceFactoryMethod = [string]$contract.traceFactoryMethod
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  runtimeRegression = 'not_run'
  deviceRegression = 'not_run'
}
Write-AtomicJson $contractEvidenceRelative $contractEvidence

$timeoutContractEvidence = [ordered]@{
  schemaVersion = 1
  kind = 'legado_trace_timeout_bridge_preservation_contract'
  status = [string]$timeoutContract.status
  issueId = $issueId
  generatedAt = $now
  baseline = [ordered]@{ sourceCount = $sourceCount; sourcePackageSha256 = $sourceHash; legadoCommit = $legadoCommit }
  fixturePath = $timeoutFixtureRelative
  fixtureSha256 = $timeoutFixtureHash
  contractPath = $timeoutContractRelative
  contractSha256 = $timeoutContractHash
  preFixEvidencePath = $timeoutFailureEvidenceRelative
  runtimePath = [string]$timeoutContract.runtimePath
  managerPath = [string]$timeoutContract.managerPath
  runtimeSha256 = [string]$timeoutContract.runtimeSha256
  managerSha256 = [string]$timeoutContract.managerSha256
  assertionCount = [int]$timeoutContract.assertionCount
  timeoutFactoryMethod = [string]$timeoutContract.timeoutFactoryMethod
  executionMethod = [string]$timeoutContract.executionMethod
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  runtimeRegression = 'not_run'
  deviceRegression = 'not_run'
}
Write-AtomicJson $timeoutContractEvidenceRelative $timeoutContractEvidence

$immutableContractEvidence = [ordered]@{
  schemaVersion = 1
  kind = 'legado_trace_immutable_array_preservation_contract'
  status = [string]$immutableContract.status
  issueId = $issueId
  generatedAt = $now
  baseline = [ordered]@{ sourceCount = $sourceCount; sourcePackageSha256 = $sourceHash; legadoCommit = $legadoCommit }
  fixturePath = $immutableFixtureRelative
  fixtureSha256 = $immutableFixtureHash
  contractPath = $immutableContractRelative
  contractSha256 = $immutableContractHash
  preFixEvidencePath = $immutablePreFixEvidenceRelative
  runtimePath = [string]$immutableContract.runtimePath
  runtimeSha256 = [string]$immutableContract.runtimeSha256
  assertionCount = [int]$immutableContract.assertionCount
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  runtimeRegression = 'not_run'
  deviceRegression = 'not_run'
}
Write-AtomicJson $immutableContractEvidenceRelative $immutableContractEvidence

$nestedContractEvidence = [ordered]@{
  schemaVersion = 1
  kind = 'legado_trace_nested_array_preservation_contract'
  status = [string]$nestedContract.status
  issueId = $issueId
  generatedAt = $now
  baseline = [ordered]@{ sourceCount = $sourceCount; sourcePackageSha256 = $sourceHash; legadoCommit = $legadoCommit }
  fixturePath = $nestedFixtureRelative
  fixtureSha256 = $nestedFixtureHash
  contractPath = $nestedContractRelative
  contractSha256 = $nestedContractHash
  preFixEvidencePath = $nestedPreFixEvidenceRelative
  runtimePath = [string]$nestedContract.runtimePath
  runtimeSha256 = [string]$nestedContract.runtimeSha256
  fieldsChecked = [int]$nestedContract.fieldsChecked
  assertionCount = [int]$nestedContract.assertionCount
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  runtimeRegression = 'not_run'
  deviceRegression = 'not_run'
}
Write-AtomicJson $nestedContractEvidenceRelative $nestedContractEvidence

$resultContractEvidence = [ordered]@{
  schemaVersion = 1
  kind = 'legado_source_script_result_array_preservation_contract'
  status = [string]$resultContract.status
  issueId = $issueId
  generatedAt = $now
  baseline = [ordered]@{ sourceCount = $sourceCount; sourcePackageSha256 = $sourceHash; legadoCommit = $legadoCommit }
  fixturePath = $resultFixtureRelative
  fixtureSha256 = $resultFixtureHash
  contractPath = $resultContractRelative
  contractSha256 = $resultContractHash
  preFixEvidencePath = $resultPreFixEvidenceRelative
  runtimePath = [string]$resultContract.runtimePath
  orchestratorPath = [string]$resultContract.orchestratorPath
  runtimeSha256 = [string]$resultContract.runtimeSha256
  orchestratorSha256 = [string]$resultContract.orchestratorSha256
  resultClass = [string]$resultContract.resultClass
  resultConstructorCount = [int]$resultContract.resultConstructorCount
  assertionCount = [int]$resultContract.assertionCount
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  runtimeRegression = 'not_run'
  deviceRegression = 'not_run'
}
Write-AtomicJson $resultContractEvidenceRelative $resultContractEvidence

$sourceFix = [ordered]@{
  schemaVersion = 1
  kind = 'legado_trace_mutation_bridge_preservation_source_fix'
  status = 'passed_static_only'
  issueId = $issueId
  generatedAt = $now
  baseline = [ordered]@{ sourceCount = $sourceCount; sourcePackageSha256 = $sourceHash; legadoCommit = $legadoCommit }
  failureWitnessPath = $failureEvidenceRelative
  contractEvidencePath = $contractEvidenceRelative
  primaryCause = [ordered]@{
    classification = 'trace_projection'
    statement = 'LegadoExecutionTrace and the transient LegadoSourceScriptResult handoff are immutable at their array boundaries; constructor-owned variableChanges, sourceEffectNames and bridgeTraces plus nested request/response/bridge arrays are defensive snapshots, Analyzer JS bridge results must be collected, every V2 workflow mutation must copy the merged bridgeTraces when replacing outputSummary, variableChanges or the response envelope, and timeout traces must preserve only the active same-workflow request lineage.'
  }
  changedFiles = @($runtimeRelative, $analyzerRelative, $typesRelative, $sourceScriptRuntimeRelative)
  sourceFixHashes = [ordered]@{ runtime = $runtimeHash; analyzer = $analyzerHash; types = $typesHash; sourceScriptRuntime = $sourceScriptRuntimeHash; fixture = $fixtureHash; contract = $contractHash; timeoutFixture = $timeoutFixtureHash; timeoutContract = $timeoutContractHash; immutableFixture = $immutableFixtureHash; immutableContract = $immutableContractHash; nestedFixture = $nestedFixtureHash; nestedContract = $nestedContractHash; resultFixture = $resultFixtureHash; resultContract = $resultContractHash }
  affectedSourceOrdinal = 3
  affectedSourceId = 'F4FED60D32DD390B8F21FDA90B2435A614A7970C16E038D6A4D0242783E1B45C'
  timeoutFailureWitnessPath = $timeoutFailureEvidenceRelative
  timeoutContractEvidencePath = $timeoutContractEvidenceRelative
  immutablePreFixEvidencePath = $immutablePreFixEvidenceRelative
  immutableContractEvidencePath = $immutableContractEvidenceRelative
  nestedPreFixEvidencePath = $nestedPreFixEvidenceRelative
  nestedContractEvidencePath = $nestedContractEvidenceRelative
  resultPreFixEvidencePath = $resultPreFixEvidenceRelative
  resultContractEvidencePath = $resultContractEvidenceRelative
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_source_fix_static_only;242_verifying;R4_runtime_build_device_and_legado_diff_deferred'
  reproductionCommands = @(
    "pwsh -NoLogo -NoProfile -NonInteractive -File $contractRelative",
    "pwsh -NoLogo -NoProfile -NonInteractive -File $timeoutContractRelative",
    "pwsh -NoLogo -NoProfile -NonInteractive -File $immutableContractRelative",
    "pwsh -NoLogo -NoProfile -NonInteractive -File $nestedContractRelative",
    "pwsh -NoLogo -NoProfile -NonInteractive -File $resultContractRelative",
    "pwsh -NoLogo -NoProfile -NonInteractive -File tools/legado-compat/Register-LegadoTraceMutationBridgePreservationSourceFix.ps1"
  )
  closeCondition = 'R4 must execute the ordinal 3 content equivalence class including timeout cancellation and bridge preservation, the deterministic full Harness, same-input Legado differential, build and device gates; only then may 242 become passed or semantic_match.'
}
Write-AtomicJson $sourceFixEvidenceRelative $sourceFix

# Keep the objective attached to the single active source-closure issue while
# retaining the existing R4 deferral policy.
$objective.targetRevision = $revision
Set-PropertyValue $objective 'lastReviewedAt' $now
Set-PropertyValue $objective 'continuationMode' 'R3_ISSUE_242_TRACE_MUTATION_STATIC_CLOSED_WAIT_R4'
Set-PropertyValue $objective.authority 'activeIssueId' $issueId
Set-PropertyValue $objective.authority 'activeIssueSelection' 'ISSUE-COMPAT-242 已通过失败见证、V2 trace 消费者审计和静态修复合同，作为唯一活动源码议题；R4 继续延期。'
Set-PropertyValue $objective.objective 'currentWorkstream' 'R3-ISSUE-242-TRACE-MUTATION-BRIDGE-PRESERVATION'
Set-PropertyValue $objective.objective 'activeIssue' $issueId
Set-PropertyValue $objective.objective 'activeIssueRule' '242 统一修复 Analyzer JS bridgeTraces 的生产者到工作流 Trace 消费者链路，保证普通 trace mutation 和同一活动请求的 timeout trace 重建时不丢失桥接证据；静态闭合不能提升为运行时兼容，R4 统一验证后才可关闭。'
Set-PropertyValue $objective.executionTarget 'currentIssue' $issueId
Set-PropertyValue $objective.executionTarget 'statement' '在固定 458 条基线下，242 的 Analyzer JS bridgeTraces 生产者/消费者链路、LegadoSourceScriptResult 三个数组边界、五个普通 trace mutation 路径、同一活动请求的 timeout trace 路径和 request/response/bridge 嵌套数组快照均已静态保留桥接证据；状态保持 verifying，R4 运行时、Legado 差分、构建和设备验证延期。'
Set-PropertyValue $objective 'nextAction' '242 transient script-result 数组边界、trace 不可变数组、timeout trace 和普通 mutation 的静态证据已登记；当前静态候选门禁已评估 227 个 P0/P1 条目且合格候选为 0，保持 242 verifying，所有运行时回归、构建和真机验证保留到统一 R4。'
Set-PropertyValue $objective.continuationTarget 'activeBoundary' 'ISSUE-COMPAT-242 保持 verifying：Analyzer 到工作流 Trace 的 bridgeTraces 链路、LegadoSourceScriptResult 三个数组边界、五个普通 mutation 路径、timeout lineage 路径和 request/response/bridge 嵌套数组快照均已静态闭合；R4 deferred。'
Set-PropertyValue $objective.continuationTarget 'nextTransition' '当前静态候选门禁 227/0 已完成且无合格第二议题；保持 242 verifying，R4 前不得选择第二根因或宣称语义通过。'
$queueAudit = $objective.continuationTarget.queueAudit
Set-PropertyValue $queueAudit 'id' 'R3-ISSUE-242-TRACE-MUTATION-R4-GATE'
Set-PropertyValue $queueAudit 'activeIssueId' $issueId
Set-PropertyValue $queueAudit 'status' 'source_fix_static_closed_wait_r4'
Set-PropertyValue $queueAudit 'candidateGateStatus' 'source_fix_static_closed_wait_r4'
Set-PropertyValue $queueAudit 'candidateStatus' 'source_fix_static_closed'
Set-PropertyValue $queueAudit 'selectionPolicy' '只读枚举 full-source-validation-state.json；ISSUE-COMPAT-242 是当前唯一活动源码锚点并保持 verifying；其它历史议题只等待 R4，不选择第二根因。'
Set-PropertyValue $queueAudit 'sourceFixEvidencePath' $sourceFixEvidenceRelative
Set-PropertyValue $queueAudit 'postFixContractEvidencePath' "$contractEvidenceRelative,$timeoutContractEvidenceRelative,$immutableContractEvidenceRelative,$nestedContractEvidenceRelative,$resultContractEvidenceRelative"
$deferred = @($objective.objective.deferredVerificationIssues | ForEach-Object { [string]$_ })
if ($deferred -notcontains $issueId) {
  Set-PropertyValue $objective.objective 'deferredVerificationIssues' (@($deferred) + @($issueId))
}
$exitCriteria = @($objective.executionTarget.exitCriteria | ForEach-Object { [string]$_ })
for ($index = 0; $index -lt $exitCriteria.Count; $index++) {
  if ($exitCriteria[$index].Contains('ISSUE-COMPAT-011')) {
    $exitCriteria[$index] = $exitCriteria[$index].Replace('ISSUE-COMPAT-011', $issueId)
  }
}
Set-PropertyValue $objective.executionTarget 'exitCriteria' $exitCriteria
Write-AtomicJson $objectiveRelative $objective

$updateScript = Get-RepoPath 'tools/legado-compat/Update-LegadoGovernanceState.ps1'
& pwsh -NoLogo -NoProfile -NonInteractive -File $updateScript `
  -StatePath (Get-RepoPath $stateRelative) `
  -IssueId $issueId `
  -IssueStatus verifying `
  -TaskId $taskId `
  -TaskStatus running `
  -Severity P0 `
  -Summary 'LegadoExecutionTrace 与 LegadoSourceScriptResult 对 variableChanges/sourceEffectNames/bridgeTraces 及 request/response/bridge 嵌套数组做防御性复制；Analyzer 现收集 JS bridgeTraces，syncVariables 将快照交给工作流；五个 V2 trace 重建路径和同一活动请求的 timeout trace 均保留已有或合并后的 bridgeTraces，静态合同通过，R4 deferred。' `
  -CloseCondition 'R4 完成 Analyzer 到工作流消费者的 ordinal 3 Content 等价类、timeout cancellation 等价类、受影响等价类、458 条 Harness、Legado 差分、构建和真机门禁后，才允许 242 passed/semantic_match。' `
  -EvidencePath "$failureEvidenceRelative,$contractEvidenceRelative,$timeoutFailureEvidenceRelative,$timeoutContractEvidenceRelative,$immutablePreFixEvidenceRelative,$immutableContractEvidenceRelative,$nestedPreFixEvidenceRelative,$nestedContractEvidenceRelative,$resultPreFixEvidenceRelative,$resultContractEvidenceRelative,$sourceFixEvidenceRelative" `
  -SourceOrdinal 3 `
  -SourceId 'F4FED60D32DD390B8F21FDA90B2435A614A7970C16E038D6A4D0242783E1B45C' `
  -AppendSourceIssue `
  -CreateIfMissing | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Governance state update failed.' }

# The historical queue-preflight record remains useful as evidence, but its
# active issue pointer must follow the current machine fact after a new source
# closure is registered. Keep the candidate count and evidence binding intact
# while moving the queue anchor atomically to 242.
$state = Read-StrictJson $stateRelative
$queuePreflight = $state.governance.queuePreflight
Set-PropertyValue $queuePreflight 'status' 'passed_source_fix_static_closed_wait_r4'
Set-PropertyValue $queuePreflight 'activeIssueId' $issueId
Set-PropertyValue $queuePreflight 'candidateGateStatus' 'source_fix_static_closed_wait_r4'
Set-PropertyValue $queuePreflight 'candidateCount' 0
Set-PropertyValue $queuePreflight 'runtimeActionsPerformed' @()
Set-PropertyValue $queuePreflight 'semanticMatchAllowed' $false
Set-PropertyValue $queuePreflight 'evidencePath' $contractEvidenceRelative
Set-PropertyValue $queuePreflight 'timeoutContractEvidencePath' $timeoutContractEvidenceRelative
Set-PropertyValue $queuePreflight 'immutableArrayContractEvidencePath' $immutableContractEvidenceRelative
Set-PropertyValue $queuePreflight 'nestedArrayContractEvidencePath' $nestedContractEvidenceRelative
Set-PropertyValue $queuePreflight 'sourceScriptResultArrayContractEvidencePath' $resultContractEvidenceRelative
Set-PropertyValue $queuePreflight 'updatedAt' ([DateTimeOffset]::UtcNow.ToString('o'))
Set-PropertyValue $state.governance 'currentSourceClosureBoundary' $issueId
Write-AtomicJson $stateRelative $state

$attachScript = Get-RepoPath 'tools/legado-compat/Set-LegadoRefactorObjective.ps1'
& pwsh -NoLogo -NoProfile -NonInteractive -File $attachScript `
  -StatePath (Get-RepoPath $stateRelative) `
  -ObjectivePath (Get-RepoPath $objectiveRelative) `
  -ActiveIssueId $issueId | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Objective attachment failed.' }

$refreshScript = Get-RepoPath 'tools/legado-compat/Invoke-LegadoCompatibility.ps1'
& pwsh -NoLogo -NoProfile -NonInteractive -File $refreshScript -RefreshDocumentsOnly | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Derived document refresh failed.' }

$registration = [ordered]@{
  schemaVersion = 1
  kind = 'legado_trace_mutation_bridge_preservation_registration'
  status = 'registered_verifying'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  objectiveRevision = $revision
  issueId = $issueId
  taskId = $taskId
  baseline = [ordered]@{ sourceCount = $sourceCount; sourcePackageSha256 = $sourceHash; legadoCommit = $legadoCommit }
  failureWitnessPath = $failureEvidenceRelative
  contractEvidencePath = $contractEvidenceRelative
  sourceFixEvidencePath = $sourceFixEvidenceRelative
  machineIssueStatus = 'verifying'
  affectedSourceOrdinal = 3
  affectedSourceId = 'F4FED60D32DD390B8F21FDA90B2435A614A7970C16E038D6A4D0242783E1B45C'
  runtimeActionsPerformed = @()
  timeoutFailureWitnessPath = $timeoutFailureEvidenceRelative
  timeoutContractEvidencePath = $timeoutContractEvidenceRelative
  immutablePreFixEvidencePath = $immutablePreFixEvidenceRelative
  immutableContractEvidencePath = $immutableContractEvidenceRelative
  nestedPreFixEvidencePath = $nestedPreFixEvidenceRelative
  nestedContractEvidencePath = $nestedContractEvidenceRelative
  resultPreFixEvidencePath = $resultPreFixEvidenceRelative
  resultContractEvidencePath = $resultContractEvidenceRelative
  semanticMatchAllowed = $false
  r4Deferred = $true
}
Write-AtomicJson $registrationEvidenceRelative $registration
Write-Output ('TRACE_MUTATION_SOURCE_FIX_REGISTERED issue={0} status=verifying' -f $issueId)
