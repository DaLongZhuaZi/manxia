[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$RunId = 'r3-issue-011-document-consistency-20260809',
  [string]$OutputPath = '',
  [string]$ExpectedIssueId = 'ISSUE-COMPAT-009',
  [string]$ExpectedTargetRevision = '2026-08-09-r4-device-241-verified-return-issue009',
  [string]$ExpectedContinuationMode = 'R3_ISSUE_009_DATABASE_MIGRATION_STATIC_CLOSED_WAIT_SOURCE_QUEUE'
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
$issueId = $ExpectedIssueId
$targetRevision = $ExpectedTargetRevision

function Get-RepoPath([string]$RelativePath) {
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictText([string]$RelativePath) {
  $path = Get-RepoPath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "Missing document: $RelativePath"
  }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw "UTF-8 BOM is not allowed: $RelativePath"
  }
  return $strictUtf8.GetString($bytes)
}

function Read-StrictJson([string]$RelativePath) {
  return (Read-StrictText $RelativePath | ConvertFrom-Json)
}

function Get-Sha256([string]$RelativePath) {
  return (Get-FileHash -LiteralPath (Get-RepoPath $RelativePath) -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Assert-Check([bool]$Condition, [string]$Message) {
  if (-not $Condition) {
    throw "DOCUMENT_CONSISTENCY_FAILED:$Message"
  }
}

function Get-Issue([object[]]$Issues, [string]$Id) {
  foreach ($issue in $Issues) {
    if ([string]$issue.id -eq $Id) { return $issue }
  }
  return $null
}

function Test-ActiveIssueAnchor([string]$Text, [string]$Id) {
  $shortPlainAnchor = "当前活动源码议题为 $Id"
  $uniquePlainAnchor = "当前唯一活动源码议题为 $Id"
  $shortAnchor = "当前活动源码议题为 ``$Id``"
  $uniqueAnchor = "当前唯一活动源码议题为 ``$Id``"
  return $Text.Contains($shortPlainAnchor) -or $Text.Contains($uniquePlainAnchor) -or
    $Text.Contains($shortAnchor) -or $Text.Contains($uniqueAnchor)
}

function Write-AtomicJson([string]$RelativePath, [object]$Value) {
  $path = Get-RepoPath $RelativePath
  $directory = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  }
  $temporaryPath = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 30), $noBomUtf8)
    Move-Item -LiteralPath $temporaryPath -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

$statePath = 'tools/legado-compat/state/full-source-validation-state.json'
$objectivePath = 'tools/legado-compat/state/refactor-objective.json'
$governancePath = 'tools/legado-compat/LEGADO_V2_GOVERNANCE_TASKS.md'
$objectiveDocumentPath = 'docs/analysis/Legado书源V2源码重构持续目标.md'
$ledgerPath = 'docs/analysis/Legado书源引擎兼容推进台账.md'
$indexPath = 'docs/analysis/Legado书源引擎证据索引.md'
$diffPath = 'docs/analysis/Legado书源引擎差分摘要.md'
$reportPath = 'docs/analysis/漫匣与Legado书源引擎实证对照调查报告.md'
$evidenceRelative = "tools/legado-compat/evidence/$RunId/document-consistency.json"
if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
  $fullOutput = [System.IO.Path]::GetFullPath($OutputPath)
  $evidenceRoot = [System.IO.Path]::GetFullPath((Get-RepoPath 'tools/legado-compat/evidence'))
  if (-not $fullOutput.StartsWith($evidenceRoot + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Document consistency evidence must remain under tools/legado-compat/evidence.'
  }
  $evidenceRelative = $fullOutput.Substring($RepositoryRoot.Length + 1).Replace('\', '/')
}

$state = Read-StrictJson $statePath
$objective = Read-StrictJson $objectivePath
$governanceText = Read-StrictText $governancePath
$objectiveDocumentText = Read-StrictText $objectiveDocumentPath
$ledgerText = Read-StrictText $ledgerPath
$indexText = Read-StrictText $indexPath
$diffText = Read-StrictText $diffPath
$reportText = Read-StrictText $reportPath

Assert-Check ([int]$state.baseline.sourceCount -eq $sourceCount) 'machine source count drifted'
Assert-Check ([string]$state.baseline.sourcePackageSha256 -eq $sourceHash) 'machine source hash drifted'
Assert-Check ([string]$state.baseline.legadoCommit -eq $legadoCommit) 'machine Legado commit drifted'
Assert-Check ([int]$objective.baseline.sourceCount -eq $sourceCount) 'objective source count drifted'
Assert-Check ([string]$objective.baseline.sourcePackageSha256 -eq $sourceHash) 'objective source hash drifted'
Assert-Check ([string]$objective.baseline.legadoCommit -eq $legadoCommit) 'objective Legado commit drifted'
Assert-Check ([string]$state.governance.activeTaskId -eq 'COMPAT-006') 'active task drifted'
Assert-Check ([string]$state.governance.activeIssueId -eq $issueId) 'active machine issue drifted'
Assert-Check ([string]$objective.authority.activeIssueId -eq $issueId) 'active objective issue drifted'
Assert-Check ([string]$objective.targetRevision -eq $targetRevision) 'objective revision drifted'
Assert-Check ([string]$objective.continuationMode -eq $ExpectedContinuationMode) 'continuation mode drifted'
$issue = Get-Issue -Issues @($state.governance.issues) -Id $issueId
Assert-Check ($null -ne $issue -and [string]$issue.status -eq 'verifying') 'expected active issue must remain verifying'
Assert-Check (-not [bool]$objective.objective.apiCapabilitySettlement.semanticMatchAllowed) 'semantic match was enabled'

$objectiveCurrentSection = $objectiveDocumentText.Substring(0, $objectiveDocumentText.IndexOf('## 持续目标', [System.StringComparison]::Ordinal))
$governanceCurrentSection = $governanceText.Substring(0, $governanceText.IndexOf('<!-- LEGADO_V2_GOVERNANCE_TASK_MIRROR:START -->', [System.StringComparison]::Ordinal))
Assert-Check (Test-ActiveIssueAnchor $objectiveCurrentSection $issueId) 'objective document top anchor does not match the machine issue'
Assert-Check (Test-ActiveIssueAnchor $governanceCurrentSection $issueId) 'governance document top anchor does not match the machine issue'
Assert-Check ($ledgerText.Contains("| 当前机器活动源码议题 | $issueId |")) 'ledger active issue does not match the machine issue'
Assert-Check ($indexText.Contains("| 当前机器活动源码议题 | $issueId |")) 'evidence index active issue does not match the machine issue'
Assert-Check ($diffText.Contains("| ``$issueId`` | ``verifying`` |")) 'diff summary active issue does not match the machine issue'
Assert-Check ($reportText.Contains('<!-- LEGADO_COMPATIBILITY_EXECUTION_STATUS:START -->')) 'investigation report execution block is missing'
Assert-Check ($reportText.Contains("| 当前机器活动源码议题 | $issueId |")) 'investigation report active issue does not match the machine issue'

$checks = @(
  'frozen_baseline',
  'active_issue_binding',
  'objective_revision_binding',
  'objective_document_top_anchor',
  'governance_document_top_anchor',
  'derived_ledger_anchor',
  'derived_evidence_index_anchor',
  'derived_diff_anchor',
  'investigation_report_execution_block'
)
$hashes = [ordered]@{}
foreach ($path in @($statePath, $objectivePath, $governancePath, $objectiveDocumentPath, $ledgerPath, $indexPath, $diffPath, $reportPath)) {
  $hashes[$path] = Get-Sha256 $path
}
$evidence = [ordered]@{
  schemaVersion = 1
  kind = 'legado_active_issue_document_consistency'
  status = 'passed_static_only'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  objectiveId = [string]$objective.objectiveId
  targetRevision = $targetRevision
  issueId = $issueId
  baseline = [ordered]@{ sourceCount = $sourceCount; sourcePackageSha256 = $sourceHash; legadoCommit = $legadoCommit }
  assertions = $checks.Count
  checks = $checks
  documentHashes = $hashes
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = "r3_document_consistency_only;$issueId`_verifying;R4_runtime_build_device_and_legado_diff_deferred"
  nextGate = "R4_$issueId`_affected_equivalence_full_harness_legado_diff_build_device"
  reproductionCommand = ('pwsh -NoLogo -NoProfile -NonInteractive -File tools/legado-compat/Test-LegadoIssue011DocumentConsistency.ps1 -ExpectedIssueId {0} -ExpectedTargetRevision {1} -ExpectedContinuationMode {2}' -f $ExpectedIssueId, $ExpectedTargetRevision, $ExpectedContinuationMode)
}
Write-AtomicJson $evidenceRelative $evidence
Write-Output ($evidence | ConvertTo-Json -Depth 12)
