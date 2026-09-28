[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-trace-immutable-array-preservation.json',
  [string]$PreFixEvidencePath = 'tools/legado-compat/evidence/contract-legado-trace-immutable-array-preservation-pre-fix-20260809.json'
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
  return $strictUtf8.GetString($bytes)
}

function Assert-Contract([bool]$Condition, [string]$Message) {
  if (-not $Condition) { throw "Trace immutable-array contract failed: $Message" }
}

$state = Read-StrictText 'tools/legado-compat/state/full-source-validation-state.json' | ConvertFrom-Json
$fixture = Read-StrictText $FixturePath | ConvertFrom-Json
$runtimePath = [string]$fixture.runtimePath
$runtime = Read-StrictText $runtimePath

Assert-Contract ([int]$state.baseline.sourceCount -eq $sourceCount -and
  [string]$state.baseline.sourcePackageSha256 -eq $sourceHash -and
  [string]$state.baseline.legadoCommit -eq $legadoCommit) 'frozen baseline drifted.'
Assert-Contract ([string]$state.governance.activeIssueId -eq $issueId) '242 must remain the active source-closure issue.'
Assert-Contract ([string]$fixture.contract -eq 'legado_trace_immutable_array_preservation') 'immutable-array fixture contract changed.'
Assert-Contract ($runtime.Contains('this.variableChanges = variableChanges.slice();')) 'variableChanges must be defensively copied.'
Assert-Contract ($runtime.Contains('this.bridgeTraces = bridgeTraces.slice();')) 'bridgeTraces must be defensively copied.'
Assert-Contract (-not $runtime.Contains('this.variableChanges = variableChanges;')) 'variableChanges must not retain the producer array reference.'
Assert-Contract (-not $runtime.Contains('this.bridgeTraces = bridgeTraces;')) 'bridgeTraces must not retain the producer array reference.'

$runtimeFile = Get-RepoPath $runtimePath
$fixtureFile = Get-RepoPath $FixturePath
[pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_trace_immutable_array_preservation_contract'
  status = 'passed_static_only'
  issueId = $issueId
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [ordered]@{ sourceCount = $sourceCount; sourcePackageSha256 = $sourceHash; legadoCommit = $legadoCommit }
  runtimePath = $runtimePath
  traceClass = [string]$fixture.traceClass
  constructorMethod = [string]$fixture.constructorMethod
  preFixEvidencePath = $PreFixEvidencePath
  runtimeSha256 = (Get-FileHash -LiteralPath $runtimeFile -Algorithm SHA256).Hash.ToUpperInvariant()
  fixtureSha256 = (Get-FileHash -LiteralPath $fixtureFile -Algorithm SHA256).Hash.ToUpperInvariant()
  assertionCount = 6
  semantics = [ordered]@{
    variableChanges = 'constructor stores a snapshot independent of the producer array'
    bridgeTraces = 'constructor stores a snapshot independent of the producer array'
  }
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  execution = 'static_source_contract_only'
  runtimeRegression = 'not_run'
  deviceRegression = 'not_run'
} | ConvertTo-Json -Depth 20 -Compress
