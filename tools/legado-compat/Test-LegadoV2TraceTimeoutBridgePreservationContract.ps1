[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-trace-timeout-bridge-preservation.json',
  [string]$PreFixEvidencePath = 'tools/legado-compat/evidence/contract-legado-trace-timeout-bridge-preservation-pre-fix-20260809.json'
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

function Read-StrictJson([string]$RelativePath) {
  $path = Get-RepoPath $RelativePath
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw "UTF-8 BOM is not allowed: $RelativePath"
  }
  return $strictUtf8.GetString($bytes) | ConvertFrom-Json
}

function Read-SourceText([string]$RelativePath) {
  return [System.IO.File]::ReadAllText((Get-RepoPath $RelativePath), [System.Text.UTF8Encoding]::new($false, $true)).Replace("`r`n", "`n")
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

function Assert-Contract([bool]$Condition, [string]$Message) {
  if (-not $Condition) { throw "V2 timeout bridge preservation contract failed: $Message" }
}

$state = Read-StrictJson 'tools/legado-compat/state/full-source-validation-state.json'
$fixture = Read-StrictJson $FixturePath
$runtimePath = [string]$fixture.runtimePath
$managerPath = [string]$fixture.managerPath
$runtime = Read-SourceText $runtimePath
$manager = Read-SourceText $managerPath
$timeoutMethod = Get-MethodSegment $runtime ([string]$fixture.timeoutFactoryMethod)
$executeMethod = Get-MethodSegment $runtime ([string]$fixture.executionMethod)

Assert-Contract ([int]$state.baseline.sourceCount -eq $sourceCount -and
  [string]$state.baseline.sourcePackageSha256 -eq $sourceHash -and
  [string]$state.baseline.legadoCommit -eq $legadoCommit) 'frozen baseline drifted.'
Assert-Contract ([string]$state.governance.activeIssueId -eq $issueId) '242 must remain the active source-closure issue.'
Assert-Contract ([string]$fixture.contract -eq 'legado_trace_timeout_bridge_preservation') 'timeout fixture contract changed.'
Assert-Contract ($runtime.Contains("private $($fixture.activeTraceIdField): string = '';")) 'runtime must own an active trace lineage field.'
Assert-Contract ($executeMethod.Contains("this.$($fixture.activeTraceIdField) = '';")) 'execute must clear stale timeout lineage before planning.'
Assert-Contract ($executeMethod.Contains("this.$($fixture.activeTraceIdField) = request.traceId;")) 'execute must bind the planned request trace id.'
Assert-Contract ($timeoutMethod.Contains('const previousTrace = this.lastTrace;')) 'timeout factory must inspect the prior trace.'
Assert-Contract ($timeoutMethod.Contains('previousTrace.workflow === workflow')) 'timeout factory must guard workflow lineage.'
Assert-Contract ($timeoutMethod.Contains('previousTrace.traceId === this.activeWorkflowTraceId')) 'timeout factory must guard request lineage.'
Assert-Contract ($timeoutMethod.Contains('previousTrace.bridgeTraces.slice()')) 'timeout factory must copy preserved bridge traces.'
Assert-Contract ($timeoutMethod.Contains('preservedBridgeTraces')) 'timeout factory must project preserved bridge traces.'
Assert-Contract ($manager.Contains('createWorkflowTimeoutTrace(')) 'manager must keep the timeout handoff.'

$runtimeFile = Get-RepoPath $runtimePath
$managerFile = Get-RepoPath $managerPath
$fixtureFile = Get-RepoPath $FixturePath
[pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_trace_timeout_bridge_preservation_contract'
  status = 'passed_static_only'
  issueId = $issueId
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [ordered]@{ sourceCount = $sourceCount; sourcePackageSha256 = $sourceHash; legadoCommit = $legadoCommit }
  runtimePath = $runtimePath
  managerPath = $managerPath
  fixturePath = $FixturePath
  preFixEvidencePath = $PreFixEvidencePath
  runtimeSha256 = (Get-FileHash -LiteralPath $runtimeFile -Algorithm SHA256).Hash.ToUpperInvariant()
  managerSha256 = (Get-FileHash -LiteralPath $managerFile -Algorithm SHA256).Hash.ToUpperInvariant()
  fixtureSha256 = (Get-FileHash -LiteralPath $fixtureFile -Algorithm SHA256).Hash.ToUpperInvariant()
  timeoutFactoryMethod = [string]$fixture.timeoutFactoryMethod
  executionMethod = [string]$fixture.executionMethod
  assertionCount = 10
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  execution = 'static_source_contract_only'
  runtimeRegression = 'not_run'
  deviceRegression = 'not_run'
} | ConvertTo-Json -Depth 20 -Compress
