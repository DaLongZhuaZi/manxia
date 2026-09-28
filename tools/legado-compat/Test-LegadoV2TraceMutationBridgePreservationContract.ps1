[CmdletBinding()]
param(
  [string]$RepositoryRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

function Read-Utf8Text {
  param([Parameter(Mandatory = $true)][string]$Path)
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw "UTF-8 BOM is not allowed: $Path"
  }
  return [System.Text.UTF8Encoding]::new($false, $true).GetString($bytes)
}

function Assert-Contract {
  param(
    [Parameter(Mandatory = $true)][bool]$Condition,
    [Parameter(Mandatory = $true)][string]$Message
  )
  if (-not $Condition) {
    throw "V2 trace mutation bridge preservation contract failed: $Message"
  }
}

function Get-MethodSegment {
  param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$MethodName
  )
  $start = -1
  foreach ($signature in @(
    "private $MethodName(",
    "private async $MethodName(",
    "public $MethodName(",
    "public async $MethodName(",
    "$MethodName("
  )) {
    $start = $Source.IndexOf($signature, [System.StringComparison]::Ordinal)
    if ($start -ge 0) {
      break
    }
  }
  if ($start -lt 0) {
    throw "Method not found: $MethodName"
  }
  $next = $Source.IndexOf("`n  private ", $start + 1, [System.StringComparison]::Ordinal)
  if ($next -lt 0) {
    return $Source.Substring($start)
  }
  return $Source.Substring($start, $next - $start)
}

$runtimePath = Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Novel\LegadoWorkflowOrchestrator.ets'
$analyzerPath = Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Novel\LegadoRuleAnalyzer.ets'
$fixturePath = Join-Path $RepositoryRoot 'tools\legado-compat\fixtures\legado-trace-mutation-bridge-preservation.json'
$runtime = Read-Utf8Text -Path $runtimePath
$analyzer = Read-Utf8Text -Path $analyzerPath
$fixture = (Read-Utf8Text -Path $fixturePath | ConvertFrom-Json)

$assertionCount = 0
$traceFactoryMethod = [string]$fixture.traceFactoryMethod
Assert-Contract ($traceFactoryMethod.Trim().Length -gt 0) 'fixture must declare the trace replacement helper'
$traceFactory = Get-MethodSegment -Source $runtime -MethodName $traceFactoryMethod
Assert-Contract ($traceFactory.Contains('new LegadoExecutionTrace')) "$traceFactoryMethod must own immutable trace reconstruction"
$assertionCount++
Assert-Contract ($traceFactory.Contains('effectiveBridgeTraces.slice()')) "$traceFactoryMethod must copy bridgeTraces"
$assertionCount++

$analyzerBridgeTraceField = 'private bridgeTraces: LegadoBridgeTrace[]'
Assert-Contract ($analyzer.Contains($analyzerBridgeTraceField)) 'Analyzer must own a bridge trace accumulator'
$assertionCount++
$bridgeTraceAccessorMethod = [string]$fixture.bridgeTraceAccessorMethod
$bridgeTraceAccessor = Get-MethodSegment -Source $analyzer -MethodName $bridgeTraceAccessorMethod
Assert-Contract ($bridgeTraceAccessor.Contains('return this.bridgeTraces.slice()')) "$bridgeTraceAccessorMethod must expose a snapshot"
$assertionCount++
$bridgeTraceRecordMethod = [string]$fixture.bridgeTraceRecordMethod
$bridgeTraceRecord = Get-MethodSegment -Source $analyzer -MethodName $bridgeTraceRecordMethod
Assert-Contract ($bridgeTraceRecord.Contains('this.bridgeTraces.push(trace)')) "$bridgeTraceRecordMethod must retain observed bridge traces"
$assertionCount++
Assert-Contract ($analyzer.Contains('this.recordBridgeTraces(executeResult.bridgeTraces)')) 'all async Analyzer JS results must be recorded'
$assertionCount++
Assert-Contract ($analyzer.Contains('this.recordBridgeTraces(result.bridgeTraces)')) 'direct Analyzer JS results must be recorded'
$assertionCount++
$bridgeTraceConsumerMethod = [string]$fixture.bridgeTraceConsumerMethod
$bridgeTraceConsumer = Get-MethodSegment -Source $runtime -MethodName $bridgeTraceConsumerMethod
Assert-Contract ($bridgeTraceConsumer.Contains('analyzer.getBridgeTracesSnapshot()')) "$bridgeTraceConsumerMethod must consume Analyzer bridge traces"
$assertionCount++
Assert-Contract ($bridgeTraceConsumer.Contains('this.mergeBridgeTraces(')) "$bridgeTraceConsumerMethod must merge bridge traces without duplication"
$assertionCount++
Assert-Contract ($bridgeTraceConsumer.Contains('this.replaceTrace(')) "$bridgeTraceConsumerMethod must project bridge traces into the workflow trace"
$assertionCount++
foreach ($methodName in @($fixture.mutationMethods)) {
  $segment = Get-MethodSegment -Source $runtime -MethodName ([string]$methodName)
  Assert-Contract ($segment.Contains("this.$traceFactoryMethod(")) "$methodName must use the shared trace replacement helper"
  $assertionCount++
  Assert-Contract (-not $segment.Contains('new LegadoExecutionTrace')) "$methodName must not reconstruct traces outside the shared helper"
  $assertionCount++
}

$orchestratorMutations = @(
  @{ method = 'markWorkflowException'; token = 'trace.bridgeTraces' },
  @{ method = 'syncVariables'; token = 'this.lastTrace.bridgeTraces' },
  @{ method = 'refreshTraceOutput'; token = 'this.lastTrace.bridgeTraces' },
  @{ method = 'blockProtectedResponse'; token = 'trace.bridgeTraces' },
  @{ method = 'markBookInfoRuleFailure'; token = 'this.lastTrace.bridgeTraces' }
)
foreach ($mutation in $orchestratorMutations) {
  $segment = Get-MethodSegment -Source $runtime -MethodName ([string]$mutation.method)
  Assert-Contract ($segment.Contains("this.$traceFactoryMethod(")) "$($mutation.method) must use the shared trace replacement helper"
  $assertionCount++
}

[pscustomobject][ordered]@{
  status = 'passed_static_only'
  issueId = [string]$fixture.issueId
  runtimePath = 'entry/src/main/ets/Framework/Novel/LegadoWorkflowOrchestrator.ets'
  analyzerPath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
  assertionCount = $assertionCount
  mutationMethods = @($fixture.mutationMethods)
  traceFactoryMethod = $traceFactoryMethod
  bridgeTraceAccessorMethod = $bridgeTraceAccessorMethod
  bridgeTraceRecordMethod = $bridgeTraceRecordMethod
  bridgeTraceConsumerMethod = $bridgeTraceConsumerMethod
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  execution = 'static_source_contract_only'
  runtimeRegression = 'not_run'
  deviceRegression = 'not_run'
} | ConvertTo-Json -Depth 8 -Compress
