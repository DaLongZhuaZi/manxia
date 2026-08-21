[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$OutputPath = 'tools/legado-compat/evidence/r3-issue-244-document-consistency-20260814/document-consistency.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$sourceHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$issueId = 'ISSUE-COMPAT-244-JSOUP-HTML-ENTITY-SEMANTICS'

function Get-RepoPath([string]$RelativePath) {
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictText([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing file: $Path" }
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $Path" }
  return $strictUtf8.GetString($bytes)
}

function Read-Json([string]$Path) {
  return (Read-StrictText $Path | ConvertFrom-Json)
}

function Get-Hash([string]$Path) {
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

$checks = New-Object 'System.Collections.Generic.List[object]'
function Add-Check([string]$Id, [bool]$Passed, [string]$Detail) {
  [void]$checks.Add([pscustomobject][ordered]@{ id = $Id; passed = $Passed; detail = $Detail })
  if (-not $Passed) { throw "DOC_CONSISTENCY_FAILED:${Id}:$Detail" }
}

$statePath = Get-RepoPath 'tools/legado-compat/state/full-source-validation-state.json'
$objectivePath = Get-RepoPath 'tools/legado-compat/state/refactor-objective.json'
$governanceDocPath = Get-RepoPath 'tools/legado-compat/LEGADO_V2_GOVERNANCE_TASKS.md'
$objectiveDocPath = Get-RepoPath 'docs/analysis/Legado书源V2源码重构持续目标.md'
$ledgerPath = Get-RepoPath 'docs/analysis/Legado书源引擎兼容推进台账.md'
$evidenceIndexPath = Get-RepoPath 'docs/analysis/Legado书源引擎证据索引.md'
$diffPath = Get-RepoPath 'docs/analysis/Legado书源引擎差分摘要.md'
$investigationPath = Get-RepoPath 'docs/analysis/漫匣与Legado书源引擎实证对照调查报告.md'

$state = Read-Json $statePath
$objective = Read-Json $objectivePath

Add-Check 'frozen_baseline' (
  [int]$state.baseline.sourceCount -eq 458 -and
  [string]$state.baseline.sourcePackageSha256 -eq $sourceHash -and
  [string]$state.baseline.legadoCommit -eq $legadoCommit -and
  [int]$objective.baseline.sourceCount -eq 458 -and
  [string]$objective.baseline.sourcePackageSha256 -eq $sourceHash -and
  [string]$objective.baseline.legadoCommit -eq $legadoCommit
) 'machine state and objective agree on the frozen 458-source baseline'

$governance = $state.governance
Add-Check 'active_issue_binding' (
  [string]$governance.activeIssueId -eq $issueId -and
  [string]$objective.authority.activeIssueId -eq $issueId -and
  [string]$objective.objective.activeIssue -eq $issueId -and
  [string]$governance.currentSourceClosureBoundary -eq $issueId
) 'state, objective authority and objective root all bind to ISSUE-COMPAT-244'

$stateRevision = [string]$governance.refactorObjective.targetRevision
$objectiveRevision = [string]$objective.targetRevision
Add-Check 'objective_revision_binding' (
  $stateRevision.Length -gt 0 -and $stateRevision -eq $objectiveRevision
) "state=$stateRevision objective=$objectiveRevision"

$objectiveDocText = Read-StrictText $objectiveDocPath
Add-Check 'objective_document_top_anchor' ($objectiveDocText.Contains($issueId)) 'continuous objective document carries the 244 anchor'

$governanceDocText = Read-StrictText $governanceDocPath
$mirrorStart = $governanceDocText.IndexOf('LEGADO_V2_GOVERNANCE_TASK_MIRROR:START')
$mirrorText = if ($mirrorStart -ge 0) { $governanceDocText.Substring($mirrorStart) } else { $governanceDocText }
Add-Check 'governance_document_top_anchor' ($mirrorText.Contains($issueId) -and $mirrorText.Contains('ISSUE-COMPAT-244-JSOUP-HTML-ENTITY-SEMANTICS | verifying')) 'governance mirror block binds activeIssue and status verifying to 244'

Add-Check 'derived_ledger_anchor' ((Read-StrictText $ledgerPath).Contains($issueId)) '推进台账 carries the 244 anchor'
Add-Check 'derived_evidence_index_anchor' ((Read-StrictText $evidenceIndexPath).Contains($issueId)) '证据索引 carries the 244 anchor'
Add-Check 'derived_diff_anchor' ((Read-StrictText $diffPath).Contains($issueId)) '差分摘要 carries the 244 anchor'
Add-Check 'investigation_report_execution_block' ((Read-StrictText $investigationPath).Contains($issueId)) '调查报告执行区块 carries the 244 anchor'

$documentHashes = [ordered]@{
  'tools/legado-compat/state/full-source-validation-state.json' = Get-Hash $statePath
  'tools/legado-compat/state/refactor-objective.json' = Get-Hash $objectivePath
  'tools/legado-compat/LEGADO_V2_GOVERNANCE_TASKS.md' = Get-Hash $governanceDocPath
  'docs/analysis/Legado书源V2源码重构持续目标.md' = Get-Hash $objectiveDocPath
  'docs/analysis/Legado书源引擎兼容推进台账.md' = Get-Hash $ledgerPath
  'docs/analysis/Legado书源引擎证据索引.md' = Get-Hash $evidenceIndexPath
  'docs/analysis/Legado书源引擎差分摘要.md' = Get-Hash $diffPath
  'docs/analysis/漫匣与Legado书源引擎实证对照调查报告.md' = Get-Hash $investigationPath
}

$result = [ordered]@{
  schemaVersion = 1
  kind = 'legado_active_issue_document_consistency'
  status = 'passed_static_only'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  objectiveId = 'LEGADO-V2-SOURCE-CLOSURE-R3-20260808'
  targetRevision = $objectiveRevision
  issueId = $issueId
  baseline = [ordered]@{
    sourceCount = 458
    sourcePackageSha256 = $sourceHash
    legadoCommit = $legadoCommit
  }
  assertions = $checks.Count
  checks = $checks.ToArray()
  documentHashes = $documentHashes
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
}

$outputFullPath = [System.IO.Path]::GetFullPath((Get-RepoPath $OutputPath))
$directory = Split-Path -Parent $outputFullPath
if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
  [System.IO.Directory]::CreateDirectory($directory) | Out-Null
}
$temporary = "$outputFullPath.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
try {
  [System.IO.File]::WriteAllText($temporary, ($result | ConvertTo-Json -Depth 20), $noBomUtf8)
  Move-Item -LiteralPath $temporary -Destination $outputFullPath -Force
} finally {
  if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) }
}
$result | ConvertTo-Json -Depth 20