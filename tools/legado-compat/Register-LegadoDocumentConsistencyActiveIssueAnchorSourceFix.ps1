[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-document-consistency-active-issue-anchor.json',
  [string]$FailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-document-consistency-active-issue-anchor-pre-fix-20260810.json',
  [string]$PostFixContractPath = 'tools/legado-compat/evidence/contract-legado-document-consistency-active-issue-anchor-post-fix-20260810.json',
  [string]$ReproductionFixturePath = 'tools/legado-compat/fixtures/legado-document-consistency-reproduction-command.json',
  [string]$ReproductionFailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-document-consistency-reproduction-command-pre-fix-20260810.json',
  [string]$CurrentHeadAuditPath = 'tools/legado-compat/evidence/v2-document-consistency-active-issue-anchor-current-head-audit-20260810.json',
  [string]$SourceFixPath = 'tools/legado-compat/evidence/v2-document-consistency-active-issue-anchor-source-fix-20260810.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path }
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$issueId = 'ISSUE-AUTO-046-DOCUMENT-ACTIVE-ANCHOR'
$taskId = 'COMPAT-006'
$baselineHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$scriptPath = 'tools/legado-compat/Test-LegadoIssue011DocumentConsistency.ps1'

function Get-RepoPath { param([Parameter(Mandatory = $true)][string]$Path); if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }; return Join-Path $RepositoryRoot ($Path.Replace('/', '\')) }
function Read-StrictText { param([Parameter(Mandatory = $true)][string]$Path); $resolved = Get-RepoPath $Path; if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "Missing text: $Path" }; $bytes = [System.IO.File]::ReadAllBytes($resolved); if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $Path" }; return $strictUtf8.GetString($bytes) }
function Read-StrictJson { param([Parameter(Mandatory = $true)][string]$Path); return (Read-StrictText $Path | ConvertFrom-Json -Depth 100) }
function Set-PropertyValue { param([Parameter(Mandatory = $true)][object]$Object, [Parameter(Mandatory = $true)][string]$Name, [object]$Value); if ($null -eq $Object.PSObject.Properties[$Name]) { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force } else { $Object.$Name = $Value } }
function Write-AtomicJson { param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value); $resolved = Get-RepoPath $Path; $directory = Split-Path -Parent $resolved; if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }; $temporary = "$resolved.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"; try { [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8); Move-Item -LiteralPath $temporary -Destination $resolved -Force } finally { if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) } } }
function Assert-Gate { param([bool]$Condition, [string]$Detail); if (-not $Condition) { throw "AUTO-046 document anchor source-fix gate failed: $Detail" } }

$statePath = 'tools/legado-compat/state/full-source-validation-state.json'
$objectivePath = 'tools/legado-compat/state/refactor-objective.json'
$state = Read-StrictJson $statePath
$objective = Read-StrictJson $objectivePath
$fixture = Read-StrictJson $FixturePath
$failure = Read-StrictJson $FailureWitnessPath
$contract = Read-StrictJson $PostFixContractPath
$reproductionFixture = Read-StrictJson $ReproductionFixturePath
$reproductionFailure = Read-StrictJson $ReproductionFailureWitnessPath
$audit = Read-StrictJson $CurrentHeadAuditPath
$scriptText = Read-StrictText $scriptPath

Assert-Gate ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'frozen baseline drifted.'
Assert-Gate ([string]$state.governance.activeTaskId -eq $taskId -and [string]$state.governance.activeIssueId -eq 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS' -and -not [bool]$state.governance.semanticMatchAllowed) 'source queue must remain on 243.'
Assert-Gate ([string]$failure.status -eq 'failed' -and [string]$contract.status -eq 'passed' -and [string]$audit.status -eq 'passed' -and [string]$reproductionFailure.status -eq 'failed' -and -not [bool]$contract.semanticMatchAllowed -and -not [bool]$audit.semanticMatchAllowed) 'AUTO-046 evidence chain must remain static-only.'
Assert-Gate ([string]$fixture.issueId -eq $issueId -and $scriptText.Contains('function Test-ActiveIssueAnchor(') -and $scriptText.Contains('shortAnchor') -and $scriptText.Contains('uniqueAnchor')) 'active anchor helper is missing.'

$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Get-RepoPath $scriptPath)).Hash.ToUpperInvariant()
$sourceFix = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'source_fix'
  issueId = $issueId
  status = 'passed_static_only'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  failureEvidence = @($FailureWitnessPath, $ReproductionFailureWitnessPath)
  staticContract = $PostFixContractPath
  currentHeadAudit = $CurrentHeadAuditPath
  changedPaths = @($scriptPath)
  currentHeadHashes = [pscustomobject][ordered]@{ $scriptPath = $hash }
  rootCause = [pscustomobject][ordered]@{
    category = '治理自动化/文档一致性'
    before = 'Document consistency accepted only one literal wording for the active issue anchor and emitted a stale hard-coded reproductionCommand even when callers supplied a different issue and revision.'
    after = 'A helper validates the active issue ID token with plain or Markdown-marked short/unique anchor forms, and reproductionCommand is generated from the actual invocation parameters; machine state, objective and derived mirror IDs remain mandatory.'
    affectedWorkflow = 'Test-LegadoIssue011DocumentConsistency.ps1 invoked with the current machine issue parameters.'
  }
  consumerMatrix = [pscustomobject][ordered]@{ machineState = 'tools/legado-compat/state/full-source-validation-state.json'; objective = 'tools/legado-compat/state/refactor-objective.json'; derivedDocuments = 'LEGADO_V2_GOVERNANCE_TASKS.md;推进台账;证据索引;差分摘要;调查报告'; evidenceProjection = 'document-consistency.json.reproductionCommand' }
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_governance_document_consistency_static_only;no_runtime_build_device_or_legado_diff'
  closeCondition = 'The active issue ID must remain bound across machine state, objective authority and all generated document anchors; no runtime validation is required for this tooling-only contract.'
}
Write-AtomicJson $SourceFixPath $sourceFix

$now = [DateTimeOffset]::UtcNow.ToString('o')
Set-PropertyValue $objective 'lastReviewedAt' $now
$plan = @($objective.continuationPlan)
if (-not @($plan | Where-Object { [string]$_.id -eq 'AUTO-046' })) {
  $plan += [pscustomobject][ordered]@{ id = 'AUTO-046'; status = 'completed'; action = '修复活动源码议题文档一致性检查对“当前活动/当前唯一活动”两种生成锚点的误报；保留机器 issue ID、基线和镜像一致性门禁。'; evidence = @($FixturePath, $FailureWitnessPath, $PostFixContractPath, $CurrentHeadAuditPath, $SourceFixPath) }
  Set-PropertyValue $objective 'continuationPlan' $plan
}
Write-AtomicJson $objectivePath $objective

$updateScript = Get-RepoPath 'tools/legado-compat/Update-LegadoGovernanceState.ps1'
$evidence = @($FixturePath, $FailureWitnessPath, $PostFixContractPath, $ReproductionFixturePath, $ReproductionFailureWitnessPath, $CurrentHeadAuditPath, $SourceFixPath, $scriptPath, 'tools/legado-compat/Test-LegadoDocumentConsistencyActiveIssueAnchorFailureWitness.ps1', 'tools/legado-compat/Test-LegadoDocumentConsistencyActiveIssueAnchorPostFixContract.ps1', 'tools/legado-compat/Test-LegadoDocumentConsistencyActiveIssueAnchorCurrentHeadAudit.ps1', 'tools/legado-compat/Test-LegadoDocumentConsistencyReproductionCommandFailureWitness.ps1', 'tools/legado-compat/Register-LegadoDocumentConsistencyActiveIssueAnchorSourceFix.ps1')
$summary = '治理文档一致性检查已改为校验活动 issue ID 并接受生成器的纯文本/Markdown 标记、“当前活动/当前唯一活动”锚点表述；证据 reproductionCommand 也由实际调用参数生成。机器状态、目标 authority、镜像 ID 和固定基线门禁保持不变。'
$closeCondition = [string]$sourceFix.closeCondition
$pwsh = (Get-Command pwsh -ErrorAction Stop).Source
$updateOutput = & $pwsh -NoLogo -NoProfile -NonInteractive -File $updateScript -IssueId $issueId -IssueStatus passed -TaskId $taskId -TaskStatus running -Severity P1 -Summary $summary -CloseCondition $closeCondition -EvidencePath ([string]::Join(',', $evidence)) -CreateIfMissing 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { throw "Update-LegadoGovernanceState failed:`n$updateOutput" }
[pscustomobject][ordered]@{ status = 'registered'; issueId = $issueId; sourceFixEvidencePath = $SourceFixPath; governanceUpdate = $updateOutput.Trim(); runtimeActionsPerformed = @(); semanticMatchAllowed = $false } | ConvertTo-Json -Depth 100
