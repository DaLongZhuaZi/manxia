[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-trace-immutable-array-preservation.json',
  [string]$OutputPath = 'tools/legado-compat/evidence/contract-legado-trace-immutable-array-preservation-pre-fix-20260809.json'
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

function Write-AtomicJson([string]$RelativePath, [object]$Value) {
  $path = Get-RepoPath $RelativePath
  $directory = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  }
  $temporary = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 50), $noBomUtf8)
    Move-Item -LiteralPath $temporary -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) }
  }
}

function Assert-Witness([bool]$Condition, [string]$Message) {
  if (-not $Condition) { throw "Trace immutable-array pre-fix witness failed: $Message" }
}

$state = Read-StrictText 'tools/legado-compat/state/full-source-validation-state.json' | ConvertFrom-Json
$fixture = Read-StrictText $FixturePath | ConvertFrom-Json
$runtime = Read-StrictText $fixture.runtimePath

Assert-Witness ([int]$state.baseline.sourceCount -eq $sourceCount -and
  [string]$state.baseline.sourcePackageSha256 -eq $sourceHash -and
  [string]$state.baseline.legadoCommit -eq $legadoCommit) 'frozen baseline drifted.'
Assert-Witness ([string]$state.governance.activeIssueId -eq $issueId) '242 must remain the active source-closure issue.'
Assert-Witness ([string]$fixture.contract -eq 'legado_trace_immutable_array_preservation') 'immutable-array fixture contract changed.'
foreach ($field in @($fixture.fields)) {
  $directAssignment = [string]$field.directAssignment
  $defensiveAssignment = [string]$field.defensiveAssignment
  Assert-Witness ($runtime.Contains($directAssignment)) ("pre-fix direct assignment missing for {0}." -f [string]$field.name)
  Assert-Witness (-not $runtime.Contains($defensiveAssignment)) ("pre-fix defensive copy unexpectedly exists for {0}." -f [string]$field.name)
}

$result = [ordered]@{
  schemaVersion = 1
  kind = 'legado_trace_immutable_array_preservation_pre_fix_contract'
  status = 'failed_static_only'
  issueId = $issueId
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [ordered]@{ sourceCount = $sourceCount; sourcePackageSha256 = $sourceHash; legadoCommit = $legadoCommit }
  runtimePath = [string]$fixture.runtimePath
  traceClass = [string]$fixture.traceClass
  constructorMethod = [string]$fixture.constructorMethod
  observedBeforeFix = [ordered]@{
    variableChangesAliasesProducer = $true
    bridgeTracesAliasesProducer = $true
    affectedPaths = @('recordExploreKindsScriptTrace', 'LegadoExecutionTrace constructor', 'trace summary persistence')
    consequence = 'A producer can mutate its source arrays after trace construction and silently change the immutable execution evidence.'
  }
  reproduction = 'Construct LegadoExecutionTrace with mutable variableChanges and bridgeTraces arrays, append to the producer arrays, and observe that the trace fields change because the constructor stores the same references.'
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  runtimeRegression = 'not_run'
  deviceRegression = 'not_run'
}
Write-AtomicJson $OutputPath $result
$result | ConvertTo-Json -Depth 30
