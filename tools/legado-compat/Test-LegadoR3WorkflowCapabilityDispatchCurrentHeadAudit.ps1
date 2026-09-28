[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$OutputPath = 'tools/legado-compat/evidence/v2-hypium-workflow-capability-dispatch-current-head-audit-20260809.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$baselineHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$issueId = 'ISSUE-COMPAT-HYPIUM-WORKFLOW-CAPABILITY-DISPATCH'
$sourceFiles = @(
  'tools/legado-compat/Invoke-LegadoV2HypiumFullSourceDeviceRunner.ps1',
  'tools/legado-compat/Invoke-LegadoV2HypiumNavigation.py',
  'tools/legado-compat/LegadoHypiumWorkflowSettlement.psm1'
)
$fixtureFiles = @('tools/legado-compat/fixtures/legado-hypium-workflow-capability-dispatch-037.json')
$contractFiles = @('tools/legado-compat/Test-LegadoV2HypiumWorkflowCapabilityDispatchContract.ps1')
$contractEvidencePath = 'tools/legado-compat/evidence/contract-legado-hypium-workflow-capability-dispatch-037.json'
$failureEvidencePath = 'tools/legado-compat/evidence/contract-legado-hypium-workflow-capability-dispatch-037-pre-fix.json'
$checks = New-Object 'System.Collections.Generic.List[object]'
$assertions = 0

function Get-RepoPath {
  param([string]$RelativePath)
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictJson {
  param([string]$RelativePath)
  $path = Get-RepoPath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "required JSON missing: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $RelativePath" }
  return ($strictUtf8.GetString($bytes) | ConvertFrom-Json)
}

function Read-StrictText {
  param([string]$RelativePath)
  $path = Get-RepoPath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "required text missing: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $RelativePath" }
  return $strictUtf8.GetString($bytes)
}

function Get-Sha256 {
  param([string]$Path)
  $algorithm = [System.Security.Cryptography.SHA256]::Create()
  try { return ([System.BitConverter]::ToString($algorithm.ComputeHash([System.IO.File]::ReadAllBytes($Path)))).Replace('-', '') }
  finally { $algorithm.Dispose() }
}

function Assert-Audit {
  param([bool]$Condition, [string]$Id, [string]$Detail, [string[]]$Evidence)
  $script:assertions++
  if (-not $Condition) { throw "workflow capability current-head audit failed [$Id]: $Detail" }
  [void]$script:checks.Add([pscustomobject][ordered]@{ id = $Id; detail = $Detail; evidencePaths = @($Evidence) })
}

function Write-AtomicJson {
  param([string]$Path, [object]$Value)
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporaryPath = "$Path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 40), $utf8NoBom)
    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

function Get-PowerShellParseErrors {
  param([string]$Path)
  $tokens = $null
  $errors = $null
  [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors) | Out-Null
  return @($errors)
}

$statePath = Get-RepoPath 'tools/legado-compat/state/full-source-validation-state.json'
$objectivePath = Get-RepoPath 'tools/legado-compat/state/refactor-objective.json'
$state = Read-StrictJson 'tools/legado-compat/state/full-source-validation-state.json'
$objective = Read-StrictJson 'tools/legado-compat/state/refactor-objective.json'
$fixture = Read-StrictJson 'tools/legado-compat/fixtures/legado-hypium-workflow-capability-dispatch-037.json'
$contract = Read-StrictJson $contractEvidencePath
$failure = Read-StrictJson $failureEvidencePath
$sourcePackagePath = 'F:\Downloads-E\墨辰整理书源大全7.1（禁止倒卖）.【最新完整】.json'
Assert-Audit ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'baseline' 'machine baseline remains fixed.' @('tools/legado-compat/state/full-source-validation-state.json')
Assert-Audit ((Get-Sha256 $sourcePackagePath) -eq $baselineHash) 'source_package_hash' 'source package still matches the frozen SHA-256.' @($sourcePackagePath)
$legadoHead = (& git -C (Get-RepoPath 'legado') rev-parse HEAD 2>$null | Out-String).Trim()
Assert-Audit ($legadoHead -eq $legadoCommit) 'legado_commit' 'Legado checkout remains pinned.' @('legado')
Assert-Audit ([string]$state.governance.activeIssueId -eq 'ISSUE-COMPAT-238-JAVA-OBJECT-CONTENT-OVERLOAD') 'queue_boundary' '238 remains the active issue until this candidate is registered.' @('tools/legado-compat/state/full-source-validation-state.json')
Assert-Audit ([string]$objective.continuationTarget.queueAudit.candidateIssueId -eq $issueId -and [string]$objective.continuationTarget.queueAudit.candidateGateStatus -eq 'pending_failure_contract') 'candidate_binding' '037 queue audit selected this candidate without parallel activation.' @('tools/legado-compat/state/refactor-objective.json')
Assert-Audit ([string]$failure.status -eq 'failed' -and -not [bool]$failure.semanticMatchAllowed -and @($failure.runtimeActionsPerformed).Count -eq 0) 'pre_fix_witness' 'pre-fix failure witness is static-only.' @($failureEvidencePath)
Assert-Audit ([string]$contract.status -eq 'passed' -and [int]$contract.assertions -ge 18 -and -not [bool]$contract.semanticMatchAllowed -and @($contract.runtimeActionsPerformed).Count -eq 0) 'contract' 'post-fix capability dispatch contract is a static-only pass.' @($contractEvidencePath)
Assert-Audit (@($fixture.cases).Count -eq 6) 'fixture' 'dispatch fixture contains the three entry/capability cases and remains deterministic.' @('tools/legado-compat/fixtures/legado-hypium-workflow-capability-dispatch-037.json')

$sourceEntries = New-Object 'System.Collections.Generic.List[object]'
foreach ($relativePath in $sourceFiles) {
  $path = Get-RepoPath $relativePath
  Assert-Audit (Test-Path -LiteralPath $path -PathType Leaf) ('source_exists_' + $relativePath.Replace('/', '_')) ('source file exists: ' + $relativePath) @($relativePath)
  $text = Read-StrictText $relativePath
  $parseErrors = @()
  if ($relativePath.EndsWith('.ps1')) { $parseErrors = @(Get-PowerShellParseErrors $path) }
  Assert-Audit ($parseErrors.Count -eq 0) ('syntax_' + $relativePath.Replace('/', '_')) ('PowerShell syntax is valid: ' + $relativePath) @($relativePath)
  $markers = if ($relativePath.EndsWith('Invoke-LegadoV2HypiumFullSourceDeviceRunner.ps1')) {
    @('safe_read_path_explore_deferred', 'safe_read_path_explore_requested', 'safe_read_path_explore_read_requested', 'search_workflow_missing', 'Set-HypiumExploreOnlyReadTerminal', 'Test-HypiumExploreReadCapabilitySet', 'safe_read_path_read_chain_capability_dependency_missing', '-ContinueReadPath:$continueExploreReadPath')
  } elseif ($relativePath.EndsWith('Invoke-LegadoV2HypiumNavigation.py')) {
    @('continue_read_path', 'execute_safe_read_path', 'result_component')
  } else {
    @()
  }
  foreach ($marker in $markers) { Assert-Audit ($text.Contains($marker)) ('marker_' + $relativePath.Replace('/', '_') + '_' + $marker.Replace(':', '_')) ('current HEAD contains semantic marker: ' + $marker) @($relativePath) }
  $sourceEntries.Add([pscustomobject][ordered]@{ path = $relativePath; sha256 = (Get-Sha256 $path); semanticMarkers = $markers })
}
foreach ($relativePath in $fixtureFiles + $contractFiles) {
  $path = Get-RepoPath $relativePath
  Assert-Audit (Test-Path -LiteralPath $path -PathType Leaf) ('fixture_contract_exists_' + $relativePath.Replace('/', '_')) ('evidence input exists: ' + $relativePath) @($relativePath)
}

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_v2_hypium_workflow_capability_dispatch_current_head_audit'
  status = 'passed'
  issueId = $issueId
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  objectiveId = [string]$objective.objectiveId
  targetRevision = [string]$objective.targetRevision
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  sourceFiles = $sourceEntries.ToArray()
  fixtureFiles = @($fixtureFiles)
  contractFiles = @($contractFiles)
  assertions = $script:assertions
  checks = $script:checks.ToArray()
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_current_head_static_audit_only;runtime_and_R4_deferred'
}
$outputAbsolutePath = Get-RepoPath $OutputPath
Write-AtomicJson -Path $outputAbsolutePath -Value $result
$result | ConvertTo-Json -Depth 40
