[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-source-script-result-array-preservation.json',
  [string]$OutputPath = 'tools/legado-compat/evidence/contract-legado-source-script-result-array-preservation-pre-fix-20260809.json'
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
    [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 40), $noBomUtf8)
    Move-Item -LiteralPath $temporary -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) }
  }
}

function Assert-Witness([bool]$Condition, [string]$Message) {
  if (-not $Condition) { throw "Source-script result pre-fix witness failed: $Message" }
}

$state = Read-StrictText 'tools/legado-compat/state/full-source-validation-state.json' | ConvertFrom-Json
$fixture = Read-StrictText $FixturePath | ConvertFrom-Json
$runtime = Read-StrictText ([string]$fixture.runtimePath)
$orchestrator = Read-StrictText ([string]$fixture.orchestratorPath)

Assert-Witness ([int]$state.baseline.sourceCount -eq $sourceCount -and
  [string]$state.baseline.sourcePackageSha256 -eq $sourceHash -and
  [string]$state.baseline.legadoCommit -eq $legadoCommit) 'frozen baseline drifted.'
Assert-Witness ([string]$state.governance.activeIssueId -eq $issueId) '242 must remain the active source-closure issue.'
Assert-Witness ([string]$fixture.contract -eq 'legado_source_script_result_array_boundary') 'result boundary fixture changed.'
Assert-Witness (([regex]::Matches($runtime, 'new LegadoSourceScriptResult\(')).Count -eq [int]$fixture.resultConstructorCount) 'result constructor count changed.'
foreach ($field in @($fixture.fields)) {
  $directAssignment = [string]$field.directAssignment
  $defensiveAssignment = [string]$field.defensiveAssignment
  Assert-Witness ($runtime.Contains($directAssignment)) ("pre-fix direct assignment missing for {0}." -f [string]$field.name)
  Assert-Witness (-not $runtime.Contains($defensiveAssignment)) ("pre-fix defensive copy unexpectedly exists for {0}." -f [string]$field.name)
}
Assert-Witness ($runtime.Contains('const variableChanges = this.collectVariableChanges(execution);')) 'variableChanges producer boundary missing.'
Assert-Witness ($runtime.Contains('const sourceEffectNames = this.persistSourceEffects(source, execution.sourceEffects);')) 'sourceEffectNames producer boundary missing.'
Assert-Witness ($runtime.Contains('execution.bridgeTraces || []')) 'bridgeTraces producer boundary missing.'
Assert-Witness ($orchestrator.Contains('execution.bridgeTraces')) 'bridgeTraces consumer missing.'
Assert-Witness ($orchestrator.Contains('new LegadoExecutionTrace(')) 'persisted trace consumer missing.'

$result = [ordered]@{
  schemaVersion = 1
  kind = 'legado_source_script_result_array_preservation_pre_fix_contract'
  status = 'failed_static_only'
  issueId = $issueId
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [ordered]@{ sourceCount = $sourceCount; sourcePackageSha256 = $sourceHash; legadoCommit = $legadoCommit }
  runtimePath = [string]$fixture.runtimePath
  orchestratorPath = [string]$fixture.orchestratorPath
  resultClass = [string]$fixture.resultClass
  observedBeforeFix = [ordered]@{
    aliasedFields = @('variableChanges', 'sourceEffectNames', 'bridgeTraces')
    producerArraysRemainMutable = $true
    consequence = 'A caller holding the script result can mutate a producer-owned array after the async handoff. The persisted trace currently snapshots bridge evidence later, but the result boundary itself is not stable and can feed altered variables or bridge diagnostics to subsequent consumers.'
  }
  reproduction = 'Construct a LegadoSourceScriptResult with mutable arrays, append or remove an item through the producer arrays after construction, and observe that the result fields change because the constructor stores the same references.'
  consumerEvidence = @('applySourceScriptVariables reads variableChanges', 'recordExploreKindsScriptTrace reads variableChanges and sourceEffectNames', 'recordExploreKindsScriptTrace passes bridgeTraces to LegadoExecutionTrace')
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  execution = 'static_source_contract_only'
  runtimeRegression = 'not_run'
  deviceRegression = 'not_run'
}
Write-AtomicJson $OutputPath $result
$result | ConvertTo-Json -Depth 40
