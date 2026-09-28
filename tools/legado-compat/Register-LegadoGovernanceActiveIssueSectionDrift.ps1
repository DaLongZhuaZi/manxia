[CmdletBinding()]
param([string]$RepositoryRoot = '')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$evidenceRelative = 'tools/legado-compat/evidence/contract-legado-governance-active-issue-section-20260809.json'
$sourceFixRelative = 'tools/legado-compat/evidence/v2-governance-active-issue-section-source-fix-20260809.json'
$testScript = Join-Path $PSScriptRoot 'Test-LegadoGovernanceActiveIssueSectionContract.ps1'
$updateScript = Join-Path $PSScriptRoot 'Update-LegadoGovernanceState.ps1'

function Get-RepoPath([string]$RelativePath) { return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\')) }
function Write-AtomicJson([string]$RelativePath, [object]$Value) {
  $path = Get-RepoPath $RelativePath
  $directory = Split-Path -Parent $path
  [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  $temporary = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 30), $utf8NoBom)
    Move-Item -LiteralPath $temporary -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) }
  }
}

$testOutput = & pwsh -NoLogo -NoProfile -NonInteractive -File $testScript -RepositoryRoot $RepositoryRoot -OutputPath $evidenceRelative 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { throw "Active issue section static contract failed: $testOutput" }
$contract = $testOutput.Trim() | ConvertFrom-Json
$state = Get-Content -Raw -Encoding UTF8 (Get-RepoPath 'tools/legado-compat/state/full-source-validation-state.json') | ConvertFrom-Json
$sourceFix = [ordered]@{
  schemaVersion = 1
  kind = 'legado_governance_active_issue_section_source_fix'
  status = 'passed_static_only'
  issueId = 'ISSUE-AUTO-047-GOVERNANCE-ACTIVE-ISSUE-SECTION-DRIFT'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [ordered]@{
    sourceCount = [int]$state.baseline.sourceCount
    sourcePackageSha256 = [string]$state.baseline.sourcePackageSha256
    legadoCommit = [string]$state.baseline.legadoCommit
  }
  failureWitnessPath = 'tools/legado-compat/evidence/contract-legado-governance-active-issue-section-drift-pre-fix-20260809.json'
  contractEvidencePath = $evidenceRelative
  changedFiles = @(
    'tools/legado-compat/Invoke-LegadoCompatibility.ps1',
    'tools/legado-compat/LEGADO_V2_GOVERNANCE_TASKS.md',
    'tools/legado-compat/fixtures/legado-governance-active-issue-section-drift.json',
    'tools/legado-compat/Test-LegadoGovernanceActiveIssueSectionContract.ps1'
  )
  activeIssueIdAfterFix = [string]$state.governance.activeIssueId
  statement = 'Current source issue text is generated from full-source-validation-state.json and historical queue prose remains outside the generated marker block.'
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  closeCondition = 'Static contract, source-fix evidence, atomic state update and derived-document refresh remain green; this governance issue does not establish book-source semantic compatibility.'
}
Write-AtomicJson $sourceFixRelative $sourceFix
& pwsh -NoLogo -NoProfile -NonInteractive -File $updateScript `
  -StatePath (Get-RepoPath 'tools/legado-compat/state/full-source-validation-state.json') `
  -IssueId 'ISSUE-AUTO-047-GOVERNANCE-ACTIVE-ISSUE-SECTION-DRIFT' `
  -IssueStatus passed `
  -TaskId 'COMPAT-006' `
  -TaskStatus running `
  -Severity P1 `
  -Summary '治理台账当前源码活动段落曾残留 037，已改为由 full-source-validation-state.json 驱动的原子镜像；历史队列叙述保留在生成区块之外。' `
  -CloseCondition '静态合同、失败见证、source-fix 证据、机器状态和全部派生文档保持一致；不得据此宣称书源语义兼容。' `
  -EvidencePath "tools/legado-compat/evidence/contract-legado-governance-active-issue-section-drift-pre-fix-20260809.json,$evidenceRelative,$sourceFixRelative" `
  -CreateIfMissing | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Governance state update failed.' }
$contract | ConvertTo-Json -Depth 30
