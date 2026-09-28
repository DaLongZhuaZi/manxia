[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-text-own-context.json',
  [string]$FailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-jsoup-text-own-context-pre-fix-20260810.json',
  [string]$PostFixContractPath = 'tools/legado-compat/evidence/contract-legado-jsoup-text-own-context-post-fix-20260810.json',
  [string]$CurrentHeadAuditPath = 'tools/legado-compat/evidence/v2-jsoup-text-own-context-current-head-audit-20260810.json',
  [string]$SourceFixPath = 'tools/legado-compat/evidence/v2-jsoup-text-own-context-source-fix-20260810.json'
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
$revision = '2026-08-10-actual-docs-source-refactor-jsoup-combination-r4-readiness-static-closure'
$bridgePath = 'entry/src/main/ets/libs/htmlparser/LegadoHtmlBridge.ets'
$bridgeBackupPath = 'entry/src/main/ets/libs/htmlparser/LegadoHtmlBridge.ets.bak_20260810_issue243_text_own_context'

function Get-RepoPath { param([Parameter(Mandatory = $true)][string]$Path); if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }; return Join-Path $RepositoryRoot ($Path.Replace('/', '\')) }
function Read-StrictText { param([Parameter(Mandatory = $true)][string]$Path); $resolved = Get-RepoPath $Path; if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "required file is missing: $Path" }; $bytes = [System.IO.File]::ReadAllBytes($resolved); if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $Path" }; return $strictUtf8.GetString($bytes) }
function Read-StrictJson { param([Parameter(Mandatory = $true)][string]$Path); return (Read-StrictText -Path $Path | ConvertFrom-Json -Depth 100) }
function Set-PropertyValue { param([Parameter(Mandatory = $true)][object]$Object, [Parameter(Mandatory = $true)][string]$Name, [object]$Value); if ($null -eq $Object.PSObject.Properties[$Name]) { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force } else { $Object.$Name = $Value } }
function Write-AtomicJson { param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value); $resolved = Get-RepoPath $Path; $directory = Split-Path -Parent $resolved; if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }; $temporary = "$resolved.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"; try { [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8); Move-Item -LiteralPath $temporary -Destination $resolved -Force } finally { if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) } } }
function Assert-Gate { param([bool]$Condition, [string]$Detail); if (-not $Condition) { throw "243 text own-context source-fix gate failed: $Detail" } }

$statePath = 'tools/legado-compat/state/full-source-validation-state.json'
$objectivePath = 'tools/legado-compat/state/refactor-objective.json'
$state = Read-StrictJson $statePath
$objective = Read-StrictJson $objectivePath
$fixture = Read-StrictJson $FixturePath
$failure = Read-StrictJson $FailureWitnessPath
$contract = Read-StrictJson $PostFixContractPath
$audit = Read-StrictJson $CurrentHeadAuditPath
$bridge = Read-StrictText $bridgePath
$issue = @($state.governance.issues | Where-Object { [string]$_.id -eq $issueId })[0]

Assert-Gate ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'frozen machine baseline drifted.'
Assert-Gate ([string]$state.governance.status -eq 'running' -and [string]$state.governance.activeTaskId -eq $taskId -and [string]$state.governance.activeIssueId -eq $issueId -and -not [bool]$state.governance.semanticMatchAllowed) '243 is not the sole active static issue.'
Assert-Gate ($null -ne $issue -and [string]$issue.status -eq 'verifying') '243 must remain verifying.'
Assert-Gate ([string]$failure.status -eq 'failed' -and [string]$contract.status -eq 'passed' -and [string]$audit.status -eq 'passed' -and -not [bool]$failure.semanticMatchAllowed -and -not [bool]$contract.semanticMatchAllowed -and -not [bool]$audit.semanticMatchAllowed) 'failure, post-fix and current-head evidence must remain static-only.'
Assert-Gate ([string]$fixture.contract -eq 'legado_jsoup_text_rule_own_context' -and [int]$fixture.affectedSourceSet.ruleOccurrenceCount -eq 144 -and [int]$fixture.affectedSourceSet.sourceCount -eq 96) 'text-own-context fixture or frozen capability matrix drifted.'
Assert-Gate ($bridge.Contains("const allElements = context.select('*');") -and $bridge.Contains('if (elem.ownText.includes(searchText))') -and (Test-Path -LiteralPath (Get-RepoPath $bridgeBackupPath) -PathType Leaf)) 'text own-context repair or backup is missing.'

$sourceFix = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'source_fix'
  issueId = $issueId
  status = 'source_closed_static_only'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  targetRevision = $revision
  extends = 'tools/legado-compat/evidence/v2-jsoup-element-select-context-self-source-fix-20260810.json'
  failureEvidence = @($FailureWitnessPath)
  staticContract = $PostFixContractPath
  currentHeadAudit = $CurrentHeadAuditPath
  changedPaths = @($bridgePath)
  backupPath = $bridgeBackupPath
  currentHeadHashes = [pscustomobject][ordered]@{ $bridgePath = (Get-FileHash -Algorithm SHA256 -LiteralPath (Get-RepoPath $bridgePath)).Hash.ToUpperInvariant() }
  affectedCases = @($fixture.cases | ForEach-Object { [string]$_.id })
  affectedSourceSet = $fixture.affectedSourceSet
  rootCause = [pscustomobject][ordered]@{
    category = '规则解析或编译'
    legadoSemantics = 'Pinned Legado maps text.xxx to getElementsContainingOwnText, whose collector evaluates the current Element and descendants using own text.'
    v2BeforeFix = 'LegadoHtmlBridge scanned descendants with elem.text, so nested text promoted ancestors and a matching current context element was omitted.'
    v2AfterFix = 'The bridge delegates root and chained text lookup to context.select("*") and filters the typed HTMLElement.ownText projection. The synthetic Document root remains excluded by select.'
  }
  consumerMatrix = [pscustomobject][ordered]@{
    analyzer = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets -> getElementsByCSSWithBridge'
    bridge = $bridgePath + ' -> findByText/findByTextInContext'
    matcher = 'entry/src/main/ets/libs/htmlparser/HTMLElement.ets -> select and ownText'
    workflows = 'Search/Explore/BookInfo/Toc/Content/DownloadUrls text.xxx chain projections'
    sourceCoverage = '144 rule occurrences across 96 frozen sources and 48 unique rule shapes'
    legado = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt -> getElementsContainingOwnText'
  }
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_243_text_own_context_source_fix_static_only;R4_runtime_build_device_and_legado_diff_deferred'
  closeCondition = 'R4 must execute all four text-own-context cases, the 96-source/144-occurrence matrix, deterministic 458-source Harness, fixed-Legado differential, build and device gates before 243 can leave verifying.'
}
Write-AtomicJson -Path $SourceFixPath -Value $sourceFix

$now = [DateTimeOffset]::UtcNow.ToString('o')
Set-PropertyValue $objective 'lastReviewedAt' $now
Set-PropertyValue $objective 'targetRevision' $revision
Set-PropertyValue $objective 'continuationMode' 'R3_ISSUE_243_STANDARD_CSS_PSEUDO_STATIC_CLOSED_WAIT_R4'
Set-PropertyValue $objective.authority 'activeIssueId' $issueId
Set-PropertyValue $objective.authority 'activeIssueSelection' 'full-source-validation-state.json remains the only queue; 243 remains the sole active source-closure issue. text.xxx now follows Jsoup own-text collector semantics; semanticMatchAllowed remains false and R4 is deferred.'
Set-PropertyValue $objective.objective 'activeIssueRule' '243 selector semantics require text.xxx to evaluate current and descendant Elements by ownText, not aggregate descendant text, while retaining the Jsoup Document boundary.'
Set-PropertyValue $objective.executionTarget 'statement' '243 direct-child context, top-level split, regex-class pseudo nesting, DOM Matcher selector-group splitting and document order, Element.select context self-selection, text.xxx own-text selection, :has relative-selector context, :not ancestor context, duplicate occurrence identity, bulk offset projection, sibling combinators, of-type position semantics, nested marker restoration, direct-child marker lifetime, synthetic Document-root child pseudo semantics, descendant whitespace/pseudo argument context, top-level @ delimiter context and legacy chain regex-character-class @ context are statically closed and registered; runtime, full Harness, Legado differential, build and device gates remain deferred.'
Set-PropertyValue $objective 'nextAction' '243 text.xxx own-context source closure is registered; continue one-root-cause source audit while R4 remains deferred.'
$plan = @($objective.continuationPlan)
if (-not @($plan | Where-Object { [string]$_.id -eq '243-SP-73' })) {
  $plan += [pscustomobject][ordered]@{ id = '243-SP-73'; status = 'completed'; action = '修复 text.xxx 从后代 aggregate text 改为 Jsoup getElementsContainingOwnText 语义，保留当前上下文元素并绑定冻结包 144 处规则、96 条书源和 48 种形态。'; evidence = @($FixturePath, $FailureWitnessPath, $PostFixContractPath, $CurrentHeadAuditPath, $SourceFixPath) }
  $plan += [pscustomobject][ordered]@{ id = '243-SP-74'; status = 'deferred'; action = 'R4 执行四个 text-own-context 案例、144 处规则/96 条书源矩阵、243 影响集合、458 条 Harness、Legado 差分、构建和真机验证。' }
  Set-PropertyValue $objective 'continuationPlan' $plan
}
Write-AtomicJson -Path $objectivePath -Value $objective

$evidence = @($FixturePath, $FailureWitnessPath, $PostFixContractPath, $CurrentHeadAuditPath, $SourceFixPath, $bridgePath, $bridgeBackupPath, 'tools/legado-compat/Test-LegadoJsoupTextOwnContextFailureWitness.ps1', 'tools/legado-compat/Test-LegadoJsoupTextOwnContextPostFixContract.ps1', 'tools/legado-compat/Test-LegadoJsoupTextOwnContextCurrentHeadAudit.ps1', 'tools/legado-compat/Register-LegadoJsoupTextOwnContextSourceFix.ps1', 'entry/src/main/ets/libs/htmlparser/HTMLElement.ets', 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets', 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt')
$summary = '243 text.xxx now follows Jsoup getElementsContainingOwnText: current contexts are candidates and nested text no longer promotes ancestors. The frozen package matrix is 144 occurrences across 96 sources and 48 unique shapes. Runtime, full Harness, Legado differential, build and device validation remain deferred.'
$updateScript = Get-RepoPath 'tools/legado-compat/Update-LegadoGovernanceState.ps1'
$updateOutput = & (Get-Command pwsh).Source -NoLogo -NoProfile -NonInteractive -File $updateScript -StatePath (Get-RepoPath $statePath) -IssueId $issueId -IssueStatus verifying -TaskId $taskId -TaskStatus running -Summary $summary -CloseCondition ([string]$sourceFix.closeCondition) -EvidencePath ([string]::Join(',', $evidence)) 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { throw "Update-LegadoGovernanceState failed:`n$updateOutput" }
[pscustomobject][ordered]@{ status = 'registered'; issueId = $issueId; sourceFixEvidencePath = $SourceFixPath; currentHeadAuditPath = $CurrentHeadAuditPath; governanceUpdate = $updateOutput.Trim(); runtimeActionsPerformed = @(); semanticMatchAllowed = $false } | ConvertTo-Json -Depth 100
