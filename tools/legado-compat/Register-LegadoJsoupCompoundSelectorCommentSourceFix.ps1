param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-compound-selector-comment-context.json',
  [string]$FailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-jsoup-compound-selector-comment-pre-fix-20260810.json',
  [string]$PostFixContractPath = 'tools/legado-compat/evidence/contract-legado-jsoup-compound-selector-comment-post-fix-20260810.json',
  [string]$CurrentHeadAuditPath = 'tools/legado-compat/evidence/v2-jsoup-compound-selector-comment-current-head-audit-20260810.json',
  [string]$SourceFixPath = 'tools/legado-compat/evidence/v2-jsoup-compound-selector-comment-source-fix-20260810.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path }
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
$taskId = 'COMPAT-006'
$baselineHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$revision = '2026-08-10-actual-docs-source-refactor-jsoup-compound-selector-comment-static-closure'
$analyzerPath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'

function Get-RepoPath { param([Parameter(Mandatory = $true)][string]$Path); if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }; return Join-Path $RepositoryRoot ($Path.Replace('/', '\')) }
function Read-StrictText { param([Parameter(Mandatory = $true)][string]$Path); $resolved = Get-RepoPath $Path; if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "required file is missing: $Path" }; $bytes = [System.IO.File]::ReadAllBytes($resolved); if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $Path" }; return $strictUtf8.GetString($bytes) }
function Read-StrictJson { param([Parameter(Mandatory = $true)][string]$Path); return (Read-StrictText -Path $Path | ConvertFrom-Json -Depth 100) }
function Set-PropertyValue { param([Parameter(Mandatory = $true)][object]$Object, [Parameter(Mandatory = $true)][string]$Name, [object]$Value); if ($null -eq $Object.PSObject.Properties[$Name]) { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force } else { $Object.$Name = $Value } }
function Write-AtomicJson { param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value); $resolved = Get-RepoPath $Path; $directory = Split-Path -Parent $resolved; if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }; $temporary = "$resolved.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"; try { [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8); Move-Item -LiteralPath $temporary -Destination $resolved -Force } finally { if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) } } }
function Assert-Gate { param([bool]$Condition, [string]$Detail); if (-not $Condition) { throw "243 compound selector comment source-fix gate failed: $Detail" } }

$statePath = 'tools/legado-compat/state/full-source-validation-state.json'
$objectivePath = 'tools/legado-compat/state/refactor-objective.json'
$state = Read-StrictJson -Path $statePath
$objective = Read-StrictJson -Path $objectivePath
$fixture = Read-StrictJson -Path $FixturePath
$failure = Read-StrictJson -Path $FailureWitnessPath
$contract = Read-StrictJson -Path $PostFixContractPath
$audit = Read-StrictJson -Path $CurrentHeadAuditPath
$analyzer = Read-StrictText -Path $analyzerPath
$issue = @($state.governance.issues | Where-Object { [string]$_.id -eq $issueId })[0]

Assert-Gate ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'frozen baseline drifted.'
Assert-Gate ([string]$state.governance.status -eq 'running' -and [string]$state.governance.activeTaskId -eq $taskId -and [string]$state.governance.activeIssueId -eq $issueId -and -not [bool]$state.governance.semanticMatchAllowed) '243 must remain the active static issue.'
Assert-Gate ($null -ne $issue -and [string]$issue.status -eq 'verifying') '243 must remain verifying.'
Assert-Gate ([string]$failure.status -eq 'failed' -and [string]$contract.status -eq 'passed' -and [string]$audit.status -eq 'passed' -and -not [bool]$failure.semanticMatchAllowed -and -not [bool]$contract.semanticMatchAllowed -and -not [bool]$audit.semanticMatchAllowed) 'static evidence is incomplete or claims semantic match.'
Assert-Gate ([string]$fixture.issueId -eq $issueId -and @($fixture.cases).Count -eq 1) 'compound selector comment fixture drifted.'
Assert-Gate ($analyzer.Contains('const scan = this.scanNextHtmlTag(html, searchStart);') -and $analyzer.Contains('searchStart = scan.endIndex + 1;') -and -not $analyzer.Contains("const tagStartIndex = html.indexOf('<', searchStart);")) 'compound selector scanner source closure is missing.'

$existingSourceFixPath = Get-RepoPath $SourceFixPath
if ([string]$objective.targetRevision -eq $revision -and (Test-Path -LiteralPath $existingSourceFixPath -PathType Leaf)) {
  [pscustomobject][ordered]@{ status = 'already_registered'; issueId = $issueId; targetRevision = $revision; sourceFixEvidencePath = $SourceFixPath; runtimeActionsPerformed = @(); semanticMatchAllowed = $false; idempotent = $true } | ConvertTo-Json -Depth 100
  return
}

$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Get-RepoPath $analyzerPath)).Hash.ToUpperInvariant()
$backupPath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets.bak_20260810_attribute_and_tag_token'
$backupHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Get-RepoPath $backupPath)).Hash.ToUpperInvariant()
$sourceFix = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'source_fix'
  issueId = $issueId
  status = 'source_closed_static_only'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  extends = 'tools/legado-compat/evidence/v2-jsoup-attribute-and-tag-token-source-fix-20260810.json'
  failureEvidence = @($FailureWitnessPath)
  staticContract = $PostFixContractPath
  currentHeadAudit = $CurrentHeadAuditPath
  changedPaths = @($analyzerPath)
  backupPath = $backupPath
  backupSha256 = $backupHash
  currentHeadHashes = [pscustomobject][ordered]@{ $analyzerPath = $hash }
  affectedCases = @($fixture.cases | ForEach-Object { [string]$_.id })
  selectionPaths = @($fixture.selectionPaths)
  rootCause = [pscustomobject][ordered]@{
    category = '规则解析或编译'
    before = 'The compound selector fallback advanced one character after a comment or closing-tag branch. It could therefore re-enter a comment and treat markup-like text as a candidate element.'
    after = 'Compound selector discovery consumes every special, closing and opening node through the shared HtmlTagScan and resumes only after scan.endIndex.'
    legadoReference = 'Pinned Legado AnalyzeByJSoup evaluates parsed Jsoup elements; comments and closing nodes are never CSS candidates.'
  }
  consumerMatrix = [pscustomobject][ordered]@{
    compoundSelector = $analyzerPath
    classAndIdProjection = $analyzerPath
    occurrenceProjection = $analyzerPath
    legado = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
  }
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_243_compound_selector_comment_source_fix_static_only;R4_runtime_build_device_and_legado_diff_deferred'
  closeCondition = 'R4 must execute the compound comment case, the affected source set, deterministic 458-source Harness, fixed-Legado differential, build and device gates before 243 can leave verifying.'
}
Write-AtomicJson -Path $SourceFixPath -Value $sourceFix

$now = [DateTimeOffset]::UtcNow.ToString('o')
Set-PropertyValue $objective 'lastReviewedAt' $now
Set-PropertyValue $objective 'targetRevision' $revision
Set-PropertyValue $objective 'continuationMode' 'R3_ISSUE_243_COMPOUND_SELECTOR_COMMENT_STATIC_CLOSED_WAIT_R4'
Set-PropertyValue $objective.authority 'activeIssueId' $issueId
Set-PropertyValue $objective.authority 'activeIssueSelection' 'full-source-validation-state.json remains the only queue; 243 remains the sole active source-closure issue. Compound selector discovery now consumes comments and closing tags through the shared scanner; semanticMatchAllowed remains false and R4 is deferred.'
Set-PropertyValue $objective.objective 'activeIssueRule' '243 compound CSS selection must consume complete Jsoup node boundaries; comment and closing-tag content cannot be re-entered as candidate elements.'
Set-PropertyValue $objective 'nextAction' '243 compound selector comment static closure is registered; continue one-root-cause source audit while R4 remains deferred.'
$plan = @($objective.continuationPlan)
if (-not @($plan | Where-Object { [string]$_.id -eq '243-SP-45' })) {
  $plan += [pscustomobject][ordered]@{ id = '243-SP-45'; status = 'completed'; action = '将复合选择器的原始 < 扫描改为共享 HtmlTagScan，注释、结束标签和属性值中的伪标签均在完整边界内消费。'; evidence = @($FixturePath, $FailureWitnessPath, $PostFixContractPath, $CurrentHeadAuditPath, $SourceFixPath) }
  $plan += [pscustomobject][ordered]@{ id = '243-SP-46'; status = 'deferred'; action = 'R4 执行复合选择器注释 fixture、影响源集合、458 条 Harness、Legado 差分、构建和真机验证。' }
  Set-PropertyValue $objective 'continuationPlan' $plan
}
Write-AtomicJson -Path $objectivePath -Value $objective

$updateScript = Get-RepoPath 'tools/legado-compat/Update-LegadoGovernanceState.ps1'
$evidence = @($FixturePath, $FailureWitnessPath, $PostFixContractPath, $CurrentHeadAuditPath, $SourceFixPath, $analyzerPath, $backupPath, 'tools/legado-compat/Test-LegadoJsoupCompoundSelectorCommentFailureWitness.ps1', 'tools/legado-compat/Test-LegadoJsoupCompoundSelectorCommentPostFixContract.ps1', 'tools/legado-compat/Test-LegadoJsoupCompoundSelectorCommentCurrentHeadAudit.ps1', 'tools/legado-compat/Register-LegadoJsoupCompoundSelectorCommentSourceFix.ps1', 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt')
$summary = '243 compound selector discovery now consumes comments, closing tags and opening tags through the shared scanner; comment markup cannot become a false CSS result. Runtime, full Harness, Legado differential, build and device validation remain deferred.'
$closeCondition = [string]$sourceFix.closeCondition
$pwsh = (Get-Command pwsh -ErrorAction Stop).Source
$updateOutput = & $pwsh -NoLogo -NoProfile -NonInteractive -File $updateScript -IssueId $issueId -IssueStatus verifying -TaskId $taskId -TaskStatus running -Summary $summary -CloseCondition $closeCondition -EvidencePath ([string]::Join(',', $evidence)) 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { throw "Update-LegadoGovernanceState failed:`n$updateOutput" }
[pscustomobject][ordered]@{ status = 'registered'; issueId = $issueId; sourceFixEvidencePath = $SourceFixPath; currentHeadAuditPath = $CurrentHeadAuditPath; postFixContractPath = $PostFixContractPath; governanceUpdate = $updateOutput.Trim(); runtimeActionsPerformed = @(); semanticMatchAllowed = $false } | ConvertTo-Json -Depth 100
