[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$OutputPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\r3-jsapi-s2t-default-runtime-target-20260809.json'
}

$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$sourceHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$issueId = 'ISSUE-COMPAT-JSAPI-JAVA-S2T-DEFAULT-RUNTIME'
$activeIssueId = 'ISSUE-COMPAT-HYPIUM-WORKFLOW-CAPABILITY-DISPATCH'
$targetRevision = '2026-08-09-actual-docs-source-refactor-js-api-s2t-default-runtime'
$assertions = 0
$failures = New-Object 'System.Collections.Generic.List[string]'

function Get-RepoPath {
  param([string]$RelativePath)
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-Json {
  param([string]$RelativePath)
  $path = Get-RepoPath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing JSON: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $RelativePath" }
  return $strictUtf8.GetString($bytes) | ConvertFrom-Json
}

function Assert-Gate {
  param([bool]$Condition, [string]$Id, [string]$Message)
  $script:assertions++
  if (-not $Condition) { [void]$script:failures.Add("${Id}: $Message") }
}

function Write-AtomicJson {
  param([string]$Path, [object]$Value)
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporaryPath = "$Path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 40), [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

$settlement = Read-Json 'tools/legado-compat/evidence/r3-js-api-capability-settlement-preflight-20260809/semantic-settlement.json'
$semanticContract = Read-Json 'tools/legado-compat/evidence/r3-js-api-capability-settlement-preflight-20260809/semantic-contract.json'
$mapping = Read-Json 'tools/legado-compat/evidence/r3-js-api-capability-settlement-preflight-20260809/reference-mapping.json'
$fixture = Read-Json 'tools/legado-compat/fixtures/legado-jsapi-s2t-default-runtime.json'
$failureWitness = Read-Json 'tools/legado-compat/evidence/contract-legado-jsapi-s2t-default-runtime-pre-fix-20260809.json'
$currentHeadAudit = Read-Json 'tools/legado-compat/evidence/v2-jsapi-s2t-default-runtime-current-head-audit-20260809.json'
$state = Read-Json 'tools/legado-compat/state/full-source-validation-state.json'
$objective = Read-Json 'tools/legado-compat/state/refactor-objective.json'

Assert-Gate ([string]$settlement.status -eq 'passed_static_only' -and [string]$semanticContract.status -eq 'passed') 'settlement' 'the 44-token settlement and its static contract must pass.'
Assert-Gate ([int]$settlement.summary.apiCount -eq 44 -and [int]$settlement.summary.occurrenceCount -eq 140 -and [int]$settlement.summary.unsupportedApiCount -eq 24) 'settlement_counts' 'settlement counts drifted.'
Assert-Gate ([string]$settlement.baseline.sourcePackageSha256 -eq $sourceHash -and [string]$settlement.baseline.legadoCommit -eq $legadoCommit) 'settlement_baseline' 'settlement baseline drifted.'
Assert-Gate ([string]$mapping.status -eq 'passed' -and @($mapping.unmappedApis).Count -eq 0 -and [int]$mapping.mappedApiCount -eq 44 -and [int]$mapping.apiMappings.'java.s2t'.occurrenceCount -eq 4) 'mapping' 'java.s2t is not completely mapped.'
Assert-Gate ([string]$failureWitness.status -eq 'failed' -and [string]$failureWitness.issueId -eq $issueId -and -not [bool]$failureWitness.semanticMatchAllowed) 'failure_witness' 's2t failure witness is missing or not static-only.'
Assert-Gate ([string]$currentHeadAudit.status -eq 'passed_static_only' -and [int]$currentHeadAudit.assertions -ge 17) 'current_head' 'current-head consumer audit is incomplete.'
Assert-Gate ([string]$fixture.primaryCause -eq 'default_arkweb_runtime_capability_injection_missing_java_s2t' -and [string]$fixture.classification -eq 'UNSUPPORTED_API') 'cause' 'candidate primary cause/classification drifted.'
Assert-Gate (@($fixture.api.affectedSourceOrdinals).Count -eq 4 -and @($fixture.consumerMatrix).Count -eq 6) 'affected_set_and_consumers' 'affected source set or consumer matrix is incomplete.'
Assert-Gate ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $sourceHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'state_baseline' 'machine state baseline drifted.'
Assert-Gate ([string]$state.governance.activeIssueId -eq $activeIssueId) 'active_issue' '037 must remain the active issue until this target is atomically registered.'
Assert-Gate ([string]$objective.authority.activeIssueId -eq $activeIssueId) 'objective_active_issue' 'objective must still point to 037 before candidate registration.'
Assert-Gate (@($fixture.runtimeActionsPerformed).Count -eq 0 -and -not [bool]$fixture.semanticMatchAllowed) 'static_only' 'candidate gate cannot perform runtime actions or authorize semantic match.'

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_r3_jsapi_s2t_default_runtime_candidate_target'
  status = if ($script:failures.Count -eq 0) { 'candidate_gate_ready' } else { 'blocked' }
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  targetRevision = $targetRevision
  objectiveId = [string]$objective.objectiveId
  taskId = 'COMPAT-006'
  activeIssueId = $activeIssueId
  candidateIssueId = $issueId
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $sourceHash; legadoCommit = $legadoCommit }
  primaryCause = [string]$fixture.primaryCause
  classification = [string]$fixture.classification
  affectedSourceOrdinals = @($fixture.api.affectedSourceOrdinals)
  affectedSourceHashPrefixes = @($fixture.api.affectedSourceHashPrefixes)
  affectedRuleFamilies = @($fixture.api.ruleFamilies)
  fixedLegado = [pscustomobject][ordered]@{
    file = [string]$fixture.legadoReference.file
    lines = [string]$fixture.legadoReference.lines
    declaration = [string]$fixture.legadoReference.declaration
    semantic = [string]$fixture.legadoReference.semantic
  }
  v2ConsumerMatrix = @($fixture.consumerMatrix)
  evidencePaths = @(
    'tools/legado-compat/evidence/r3-js-api-capability-settlement-preflight-20260809/semantic-settlement.json',
    'tools/legado-compat/evidence/r3-js-api-capability-settlement-preflight-20260809/semantic-contract.json',
    'tools/legado-compat/evidence/r3-js-api-capability-settlement-preflight-20260809/reference-mapping.json',
    'tools/legado-compat/fixtures/legado-jsapi-s2t-default-runtime.json',
    'tools/legado-compat/evidence/contract-legado-jsapi-s2t-default-runtime-pre-fix-20260809.json',
    'tools/legado-compat/evidence/v2-jsapi-s2t-default-runtime-current-head-audit-20260809.json'
  )
  failureMode = 'default_arkweb_java_member_missing;diagnostic_native_shim_is_not_default'
  repairBoundary = @(
    'entry/src/main/resources/rawfile/legado_runtime.html',
    'entry/src/main/ets/Framework/Novel/LegadoRuntimeV2.ets',
    'entry/src/main/ets/Framework/Novel/LegadoJsApiContractRegistry.ets'
  )
  structuredDisposition = 'unsupported_api_until_default_runtime_and_registry_are_closed'
  closeCondition = [string]$fixture.closeCondition
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_candidate_gate_static_only;registration_and_source_fix_before_R4_runtime_differential_build_and_device'
  assertions = $script:assertions
  failures = @($script:failures.ToArray())
  nextAction = '原子登记 ISSUE-COMPAT-JSAPI-JAVA-S2T-DEFAULT-RUNTIME 为唯一活动源码议题，然后先写 post-fix failure-preserving contract，再修改默认 ArkWeb runtime。'
}
Write-AtomicJson -Path $OutputPath -Value $result
$result | ConvertTo-Json -Depth 40
if ([string]$result.status -ne 'candidate_gate_ready') { exit 1 }
