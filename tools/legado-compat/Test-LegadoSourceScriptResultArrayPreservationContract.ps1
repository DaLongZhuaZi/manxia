[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-source-script-result-array-preservation.json',
  [string]$PreFixEvidencePath = 'tools/legado-compat/evidence/contract-legado-source-script-result-array-preservation-pre-fix-20260809.json'
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
  if (-not $Condition) { throw "Source-script result array contract failed: $Message" }
}

$state = Read-StrictText 'tools/legado-compat/state/full-source-validation-state.json' | ConvertFrom-Json
$fixture = Read-StrictText $FixturePath | ConvertFrom-Json
$runtime = Read-StrictText ([string]$fixture.runtimePath)
$orchestrator = Read-StrictText ([string]$fixture.orchestratorPath)
$runtimeFile = Get-RepoPath ([string]$fixture.runtimePath)
$orchestratorFile = Get-RepoPath ([string]$fixture.orchestratorPath)
$failure = Read-StrictText $PreFixEvidencePath | ConvertFrom-Json

Assert-Contract ([int]$state.baseline.sourceCount -eq $sourceCount -and
  [string]$state.baseline.sourcePackageSha256 -eq $sourceHash -and
  [string]$state.baseline.legadoCommit -eq $legadoCommit) 'frozen baseline drifted.'
Assert-Contract ([string]$state.governance.activeIssueId -eq $issueId) '242 must remain the active source-closure issue.'
Assert-Contract ([string]$fixture.contract -eq 'legado_source_script_result_array_boundary') 'result boundary fixture changed.'
Assert-Contract ([string]$failure.status -eq 'failed_static_only' -and [string]$failure.issueId -eq $issueId) 'pre-fix failure witness missing or drifted.'
Assert-Contract (([regex]::Matches($runtime, 'new LegadoSourceScriptResult\(')).Count -eq [int]$fixture.resultConstructorCount) 'result constructor count changed.'

$assertionCount = 0
foreach ($field in @($fixture.fields)) {
  $directAssignment = [string]$field.directAssignment
  $defensiveAssignment = [string]$field.defensiveAssignment
  Assert-Contract ($runtime.Contains($defensiveAssignment)) ("{0} must be defensively copied." -f [string]$field.name)
  Assert-Contract (-not $runtime.Contains($directAssignment)) ("{0} must not retain the producer array reference." -f [string]$field.name)
  $assertionCount += 2
}
Assert-Contract ($runtime.Contains('const variableChanges = this.collectVariableChanges(execution);')) 'variableChanges producer boundary missing.'
Assert-Contract ($runtime.Contains('const sourceEffectNames = this.persistSourceEffects(source, execution.sourceEffects);')) 'sourceEffectNames producer boundary missing.'
Assert-Contract ($runtime.Contains('execution.bridgeTraces || []')) 'bridgeTraces producer boundary missing.'
$assertionCount += 3
Assert-Contract ($orchestrator.Contains('execution.bridgeTraces')) 'bridgeTraces consumer missing.'
Assert-Contract ($orchestrator.Contains('new LegadoExecutionTrace(')) 'persisted trace consumer missing.'
Assert-Contract ($orchestrator.Contains('const variableChanges: string[] = [];')) 'trace variable snapshot consumer missing.'
$assertionCount += 3

[pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_source_script_result_array_preservation_contract'
  status = 'passed_static_only'
  issueId = $issueId
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [ordered]@{ sourceCount = $sourceCount; sourcePackageSha256 = $sourceHash; legadoCommit = $legadoCommit }
  fixturePath = $FixturePath
  runtimePath = [string]$fixture.runtimePath
  orchestratorPath = [string]$fixture.orchestratorPath
  resultClass = [string]$fixture.resultClass
  resultConstructorCount = [int]$fixture.resultConstructorCount
  preFixEvidencePath = $PreFixEvidencePath
  runtimeSha256 = (Get-FileHash -LiteralPath $runtimeFile -Algorithm SHA256).Hash.ToUpperInvariant()
  orchestratorSha256 = (Get-FileHash -LiteralPath $orchestratorFile -Algorithm SHA256).Hash.ToUpperInvariant()
  fixtureSha256 = (Get-FileHash -LiteralPath (Get-RepoPath $FixturePath) -Algorithm SHA256).Hash.ToUpperInvariant()
  assertionCount = $assertionCount
  semantics = $fixture.semantics
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  execution = 'static_source_contract_only'
  runtimeRegression = 'not_run'
  deviceRegression = 'not_run'
} | ConvertTo-Json -Depth 40 -Compress
