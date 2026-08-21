[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-trace-nested-array-preservation.json',
  [string]$PreFixEvidencePath = 'tools/legado-compat/evidence/contract-legado-trace-nested-array-preservation-pre-fix-20260809.json'
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
  if (-not $Condition) { throw "Trace nested-array contract failed: $Message" }
}

function Get-ClassSegment([string]$Source, [string]$ClassName) {
  $start = $Source.IndexOf("export class $ClassName", [System.StringComparison]::Ordinal)
  if ($start -lt 0) { throw "Class not found: $ClassName" }
  $next = $Source.IndexOf("`nexport class ", $start + 1, [System.StringComparison]::Ordinal)
  if ($next -lt 0) { return $Source.Substring($start) }
  return $Source.Substring($start, $next - $start)
}

$state = Read-StrictText 'tools/legado-compat/state/full-source-validation-state.json' | ConvertFrom-Json
$fixture = Read-StrictText $FixturePath | ConvertFrom-Json
$runtimePath = [string]$fixture.runtimePath
$runtime = Read-StrictText $runtimePath
Assert-Contract ([int]$state.baseline.sourceCount -eq $sourceCount -and
  [string]$state.baseline.sourcePackageSha256 -eq $sourceHash -and
  [string]$state.baseline.legadoCommit -eq $legadoCommit) 'frozen baseline drifted.'
Assert-Contract ([string]$state.governance.activeIssueId -eq $issueId) '242 must remain the active source-closure issue.'
Assert-Contract ([string]$fixture.contract -eq 'legado_trace_nested_array_preservation') 'nested-array fixture contract changed.'

$assertionCount = 0
$fieldCount = 0
foreach ($class in @($fixture.classes)) {
  $segment = Get-ClassSegment $runtime ([string]$class.name)
  foreach ($field in @($class.fields)) {
    $directAssignment = [string]$field.directAssignment
    $defensiveAssignment = [string]$field.defensiveAssignment
    Assert-Contract ($segment.Contains($defensiveAssignment)) ("{0}.{1} must store a defensive snapshot." -f [string]$class.name, [string]$field.name)
    $assertionCount++
    Assert-Contract (-not $segment.Contains($directAssignment)) ("{0}.{1} must not retain the producer array reference." -f [string]$class.name, [string]$field.name)
    $assertionCount++
    $fieldCount++
  }
}

$runtimeFile = Get-RepoPath $runtimePath
$fixtureFile = Get-RepoPath $FixturePath
[pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_trace_nested_array_preservation_contract'
  status = 'passed_static_only'
  issueId = $issueId
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [ordered]@{ sourceCount = $sourceCount; sourcePackageSha256 = $sourceHash; legadoCommit = $legadoCommit }
  runtimePath = $runtimePath
  fixturePath = $FixturePath
  preFixEvidencePath = $PreFixEvidencePath
  fieldsChecked = $fieldCount
  assertionCount = $assertionCount
  runtimeSha256 = (Get-FileHash -LiteralPath $runtimeFile -Algorithm SHA256).Hash.ToUpperInvariant()
  fixtureSha256 = (Get-FileHash -LiteralPath $fixtureFile -Algorithm SHA256).Hash.ToUpperInvariant()
  semantics = [ordered]@{
    traceGraph = 'All mutable arrays reachable from a persisted execution trace are constructor-owned snapshots.'
    bridgeEvidence = 'Bridge header-name evidence is stable after construction.'
    requestEvidence = 'Request headers and URL-option disposition evidence are stable after planning.'
    responseEvidence = 'Response headers and redirect-chain evidence are stable after transport completion.'
  }
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  execution = 'static_source_contract_only'
  runtimeRegression = 'not_run'
  deviceRegression = 'not_run'
} | ConvertTo-Json -Depth 20 -Compress
