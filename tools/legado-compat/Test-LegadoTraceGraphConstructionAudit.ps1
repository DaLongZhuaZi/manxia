[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-trace-graph-construction-audit.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$sourceCount = 458
$sourceHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$issueId = 'ISSUE-COMPAT-242-TRACE-BRIDGE-PRESERVATION'

function Get-RepoPath([string]$RelativePath) {
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictText([string]$RelativePath) {
  $path = Get-RepoPath $RelativePath
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw "UTF-8 BOM is not allowed: $RelativePath"
  }
  return $strictUtf8.GetString($bytes).Replace("`r`n", "`n")
}

function Assert-Contract([bool]$Condition, [string]$Message) {
  if (-not $Condition) { throw "Trace graph construction audit failed: $Message" }
}

function Get-MethodSegment([string]$Source, [string]$MethodName) {
  $start = -1
  foreach ($signature in @(
    "private $MethodName(",
    "private async $MethodName(",
    "public $MethodName(",
    "public async $MethodName(",
    "$MethodName("
  )) {
    $start = $Source.IndexOf($signature, [System.StringComparison]::Ordinal)
    if ($start -ge 0) { break }
  }
  if ($start -lt 0) { throw "Method not found: $MethodName" }
  $next = $Source.IndexOf("`n  private ", $start + 1, [System.StringComparison]::Ordinal)
  if ($next -lt 0) { return $Source.Substring($start) }
  return $Source.Substring($start, $next - $start)
}

$fixture = Read-StrictText $FixturePath | ConvertFrom-Json
$state = Read-StrictText 'tools/legado-compat/state/full-source-validation-state.json' | ConvertFrom-Json
$runtime = Read-StrictText ([string]$fixture.runtimePath)
$types = Read-StrictText ([string]$fixture.typesPath)
$analyzer = Read-StrictText ([string]$fixture.analyzerPath)
$runtimeV2 = Read-StrictText ([string]$fixture.runtimeV2Path)
$sourceScriptRuntime = Read-StrictText ([string]$fixture.sourceScriptRuntimePath)
$serializer = Read-StrictText ([string]$fixture.serializerPath)
$testOnlyPage = Read-StrictText ([string]$fixture.testOnlyConformancePagePath)
$testOnlyAbility = Read-StrictText ([string]$fixture.testOnlyConformanceAbilityPath)

Assert-Contract ([string]$fixture.contract -eq 'legado_trace_graph_construction_audit') 'fixture contract changed.'
Assert-Contract ([string]$fixture.issueId -eq $issueId) 'fixture issue changed.'
Assert-Contract ([int]$state.baseline.sourceCount -eq $sourceCount -and
  [string]$state.baseline.sourcePackageSha256 -eq $sourceHash -and
  [string]$state.baseline.legadoCommit -eq $legadoCommit) 'frozen baseline drifted.'
Assert-Contract ([string]$state.governance.activeIssueId -eq $issueId) '242 must remain the active source-closure issue.'

$assertionCount = 0
$typesChecks = @(
  'this.headerNames = headerNames.slice();',
  'this.headers = headers.slice();',
  'this.optionTrace = optionTrace.slice();',
  'this.requestHeaders = requestHeaders.slice();',
  'this.responseHeaders = responseHeaders.slice();',
  'this.redirectChain = redirectChain.slice();',
  'this.variableChanges = variableChanges.slice();',
  'this.bridgeTraces = bridgeTraces.slice();'
)
foreach ($token in $typesChecks) {
  Assert-Contract $types.Contains($token) "trace graph type snapshot missing: $token"
  $assertionCount++
}

$constructionCount = ([regex]::Matches($runtime, 'new LegadoExecutionTrace\(')).Count
Assert-Contract ($constructionCount -eq [int]$fixture.traceConstructionCount) "unexpected orchestrator trace constructor count: $constructionCount"
$assertionCount++

$testOnlyConstructionCount = ([regex]::Matches($testOnlyPage, 'new LegadoExecutionTrace\(')).Count
Assert-Contract ($testOnlyConstructionCount -eq [int]$fixture.testOnlyTraceConstructionCount) "unexpected test-only conformance trace constructor count: $testOnlyConstructionCount"
Assert-Contract ($testOnlyAbility.Contains('仅由自动兼容性总控显式启动的 ArkWeb 宿主。')) 'conformance Ability scope marker missing.'
Assert-Contract ($testOnlyAbility.Contains('它不参与正常导航，也不处理任何真实书源或用户数据。')) 'conformance Ability must remain outside normal source workflows.'
$assertionCount += 3

foreach ($methodName in @($fixture.sameTraceMutationMethods)) {
  $segment = Get-MethodSegment $runtime ([string]$methodName)
  Assert-Contract ($segment.Contains('this.replaceTrace(')) "$methodName must use replaceTrace."
  Assert-Contract (-not $segment.Contains('new LegadoExecutionTrace(')) "$methodName must not create a second trace path."
  $assertionCount += 2
}

$replaceTrace = Get-MethodSegment $runtime 'replaceTrace'
Assert-Contract ($replaceTrace.Contains('effectiveBridgeTraces')) 'replaceTrace must select existing or supplied bridge evidence.'
Assert-Contract ($replaceTrace.Contains('effectiveBridgeTraces.slice()')) 'replaceTrace must pass a snapshot to the trace constructor.'
$assertionCount += 2

$timeout = Get-MethodSegment $runtime 'createWorkflowTimeoutTrace'
Assert-Contract ($timeout.Contains('previousTrace.workflow === workflow')) 'timeout must guard workflow lineage.'
Assert-Contract ($timeout.Contains('previousTrace.traceId === this.activeWorkflowTraceId')) 'timeout must guard request lineage.'
Assert-Contract ($timeout.Contains('previousTrace.bridgeTraces.slice()')) 'timeout must copy preserved bridge evidence.'
$assertionCount += 3

$exploreTrace = Get-MethodSegment $runtime 'recordExploreKindsScriptTrace'
Assert-Contract ($exploreTrace.Contains('execution.bridgeTraces')) 'script trace must pass bridge evidence to the immutable trace.'
$assertionCount++

$block = Get-MethodSegment $runtime 'blockForJsContracts'
Assert-Contract ($block.Contains('new LegadoExecutionTrace(')) 'pre-request JS contract block must emit a trace.'
Assert-Contract (-not $block.Contains('this.lastTrace.bridgeTraces')) 'pre-request JS contract block must not inherit a prior request trace.'
$assertionCount += 2

foreach ($methodName in @($fixture.newTraceMethods)) {
  $segment = Get-MethodSegment $runtime ([string]$methodName)
  Assert-Contract ($segment.Contains('new LegadoExecutionTrace(')) "$methodName must have an explicit fresh trace path."
  $assertionCount++
}

Assert-Contract ($analyzer.Contains('private bridgeTraces: LegadoBridgeTrace[]')) 'analyzer bridge accumulator missing.'
Assert-Contract ($analyzer.Contains('return this.bridgeTraces.slice()')) 'analyzer snapshot accessor missing.'
Assert-Contract ($analyzer.Contains('this.recordBridgeTraces(executeResult.bridgeTraces)')) 'async JS bridge results are not recorded.'
Assert-Contract ($analyzer.Contains('this.recordBridgeTraces(result.bridgeTraces)')) 'direct JS bridge results are not recorded.'
$assertionCount += 4

Assert-Contract ($runtimeV2.Contains('traces.push(new LegadoBridgeTrace(')) 'RuntimeV2 must materialize bridge evidence as typed traces.'
Assert-Contract ($sourceScriptRuntime.Contains('execution.bridgeTraces || []')) 'source-script runtime must carry bridge evidence into its result.'
$assertionCount += 2

Assert-Contract (-not $runtime.Contains('this.lastTrace.bridgeTraces.push(')) 'orchestrator must not mutate a persisted trace array in place.'
Assert-Contract (-not $runtime.Contains('this.lastTrace.bridgeTraces =')) 'orchestrator must not assign a persisted trace array in place.'
Assert-Contract (-not $serializer.Contains('.sort(')) 'serializer must not reorder the persisted trace graph in place.'
Assert-Contract (-not $serializer.Contains('.splice(')) 'serializer must not remove items from the persisted trace graph.'
$assertionCount += 4

[pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_trace_graph_construction_audit'
  status = 'passed_static_only'
  issueId = $issueId
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [ordered]@{ sourceCount = $sourceCount; sourcePackageSha256 = $sourceHash; legadoCommit = $legadoCommit }
  runtimePath = [string]$fixture.runtimePath
  typesPath = [string]$fixture.typesPath
  analyzerPath = [string]$fixture.analyzerPath
  runtimeV2Path = [string]$fixture.runtimeV2Path
  sourceScriptRuntimePath = [string]$fixture.sourceScriptRuntimePath
  serializerPath = [string]$fixture.serializerPath
  testOnlyConformancePagePath = [string]$fixture.testOnlyConformancePagePath
  testOnlyConformanceAbilityPath = [string]$fixture.testOnlyConformanceAbilityPath
  traceConstructionCount = $constructionCount
  testOnlyTraceConstructionCount = $testOnlyConstructionCount
  assertionCount = $assertionCount
  sameTraceMutationMethods = @($fixture.sameTraceMutationMethods)
  newTraceMethods = @($fixture.newTraceMethods)
  bridgeProducingTraceMethods = @($fixture.bridgeProducingTraceMethods)
  testOnlyTraceMethods = @($fixture.testOnlyTraceMethods)
  semantics = $fixture.semantics
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  execution = 'static_source_graph_contract_only'
  runtimeRegression = 'not_run'
  deviceRegression = 'not_run'
  closeCondition = 'R4 must execute the affected ordinal 3 Content/timeout equivalence class, deterministic full Harness, same-input Legado differential, build and device gates; static graph closure is not semantic compatibility.'
} | ConvertTo-Json -Depth 20 -Compress
