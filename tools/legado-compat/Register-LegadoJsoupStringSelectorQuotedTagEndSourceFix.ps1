param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-string-selector-quoted-tag-end-context.json',
  [string]$FailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-jsoup-string-selector-quoted-tag-end-pre-fix-20260810.json',
  [string]$PostFixContractPath = 'tools/legado-compat/evidence/contract-legado-jsoup-string-selector-quoted-tag-end-post-fix-20260810.json',
  [string]$CurrentHeadAuditPath = 'tools/legado-compat/evidence/v2-jsoup-string-selector-quoted-tag-end-current-head-audit-20260810.json',
  [string]$SourceFixPath = 'tools/legado-compat/evidence/v2-jsoup-string-selector-quoted-tag-end-source-fix-20260810.json'
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
$revision = '2026-08-10-actual-docs-source-refactor-string-selector-quoted-tag-boundary'
$analyzerPath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'

function Get-RepoPath { param([Parameter(Mandatory = $true)][string]$Path); if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }; return Join-Path $RepositoryRoot ($Path.Replace('/', '\')) }
function Read-StrictText { param([Parameter(Mandatory = $true)][string]$Path); $resolved = Get-RepoPath $Path; if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "required file is missing: $Path" }; $bytes = [System.IO.File]::ReadAllBytes($resolved); if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $Path" }; return $strictUtf8.GetString($bytes) }
function Read-StrictJson { param([Parameter(Mandatory = $true)][string]$Path); return (Read-StrictText $Path | ConvertFrom-Json -Depth 100) }
function Set-PropertyValue { param([Parameter(Mandatory = $true)][object]$Object, [Parameter(Mandatory = $true)][string]$Name, [object]$Value); if ($null -eq $Object.PSObject.Properties[$Name]) { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force } else { $Object.$Name = $Value } }
function Write-AtomicJson { param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value); $resolved = Get-RepoPath $Path; $directory = Split-Path -Parent $resolved; if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }; $temporary = "$resolved.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"; try { [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8); Move-Item -LiteralPath $temporary -Destination $resolved -Force } finally { if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) } } }
function Assert-Gate { param([bool]$Condition, [string]$Detail); if (-not $Condition) { throw "243 quoted tag-boundary source-fix gate failed: $Detail" } }

$statePath = 'tools/legado-compat/state/full-source-validation-state.json'
$objectivePath = 'tools/legado-compat/state/refactor-objective.json'
$state = Read-StrictJson $statePath
$objective = Read-StrictJson $objectivePath
$fixture = Read-StrictJson $FixturePath
$failure = Read-StrictJson $FailureWitnessPath
$contract = Read-StrictJson $PostFixContractPath
$audit = Read-StrictJson $CurrentHeadAuditPath
$analyzer = Read-StrictText $analyzerPath
$issue = @($state.governance.issues | Where-Object { [string]$_.id -eq $issueId })[0]

Assert-Gate ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'frozen baseline drifted.'
Assert-Gate ([string]$state.governance.status -eq 'running' -and [string]$state.governance.activeTaskId -eq $taskId -and [string]$state.governance.activeIssueId -eq $issueId -and -not [bool]$state.governance.semanticMatchAllowed) '243 must remain the active static issue.'
Assert-Gate ($null -ne $issue -and [string]$issue.status -eq 'verifying') '243 must remain verifying.'
Assert-Gate ([string]$failure.status -eq 'failed' -and [string]$contract.status -eq 'passed' -and [string]$audit.status -eq 'passed' -and -not [bool]$failure.semanticMatchAllowed -and -not [bool]$contract.semanticMatchAllowed -and -not [bool]$audit.semanticMatchAllowed) 'static evidence is incomplete or claims semantic match.'
Assert-Gate ([string]$fixture.issueId -eq $issueId -and @($fixture.cases).Count -eq 2) 'quoted tag-boundary fixture drifted.'
Assert-Gate ($analyzer.Contains('private findHtmlTagEnd(html: string, start: number): number') -and -not [regex]::IsMatch($analyzer, "indexOf\('>'")) 'quote-aware tag-boundary fix is missing.'

$existingSourceFixPath = Get-RepoPath $SourceFixPath
if ([string]$objective.targetRevision -eq $revision -and (Test-Path -LiteralPath $existingSourceFixPath -PathType Leaf)) {
  [pscustomobject][ordered]@{ status = 'already_registered'; issueId = $issueId; targetRevision = $revision; sourceFixEvidencePath = $SourceFixPath; runtimeActionsPerformed = @(); semanticMatchAllowed = $false; idempotent = $true } | ConvertTo-Json -Depth 100
  return
}

$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Get-RepoPath $analyzerPath)).Hash.ToUpperInvariant()
$sourceFix = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'source_fix'
  issueId = $issueId
  status = 'source_closed_static_only'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  extends = 'tools/legado-compat/evidence/v2-jsoup-dom-matcher-selector-group-source-fix-20260810.json'
  failureEvidence = @($FailureWitnessPath)
  staticContract = $PostFixContractPath
  currentHeadAudit = $CurrentHeadAuditPath
  changedPaths = @($analyzerPath)
  currentHeadHashes = [pscustomobject][ordered]@{ $analyzerPath = $hash }
  affectedCases = @($fixture.cases | ForEach-Object { [string]$_.id })
  representativeSourceSet = $fixture.representativeSourceSet
  rootCause = [pscustomobject][ordered]@{
    category = '规则解析或编译'
    before = "The string selector fallback duplicated raw indexOf('>') scans for class, id, text, compound selector, occurrence-marker and element extraction paths. A > inside a quoted HTML attribute ended the start tag early."
    after = 'All affected paths use the shared quote-aware findHtmlTagEnd scanner, so only an unquoted > closes an HTML start tag.'
    legadoReference = 'Pinned Legado AnalyzeByJSoup evaluates a parsed Jsoup DOM; quoted attribute data cannot become a DOM tag boundary.'
  }
  consumerMatrix = [pscustomobject][ordered]@{
    stringFallback = $analyzerPath
    selectorGroupProjection = 'LegadoRuleAnalyzer.mergeSelectorGroupResultsByOccurrence / annotateStringSelectorHtml'
    representativeSource = '$[277].ruleExplore.bookList and $[277].ruleExplore.coverUrl (ordinal 278)'
    legado = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
  }
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_243_string_selector_tag_boundary_source_fix_static_only;R4_runtime_build_device_and_legado_diff_deferred'
  closeCondition = 'R4 must execute both quoted-greater selector cases through V2, the representative frozen source, affected 243 sources, deterministic 458-source Harness, fixed-Legado differential, build and device gates before 243 can leave verifying.'
}
Write-AtomicJson $SourceFixPath $sourceFix

$now = [DateTimeOffset]::UtcNow.ToString('o')
Set-PropertyValue $objective 'lastReviewedAt' $now
Set-PropertyValue $objective 'targetRevision' $revision
Set-PropertyValue $objective 'continuationMode' 'R3_ISSUE_243_STRING_SELECTOR_TAG_BOUNDARY_STATIC_CLOSED_WAIT_R4'
Set-PropertyValue $objective.authority 'activeIssueId' $issueId
Set-PropertyValue $objective.authority 'activeIssueSelection' 'full-source-validation-state.json remains the only queue; 243 remains the sole active source-closure issue. The string fallback now uses the same quote-aware HTML tag-boundary scanner as the DOM bridge; semanticMatchAllowed remains false and R4 is deferred.'
Set-PropertyValue $objective.objective 'activeIssueRule' '243 标准 CSS 选择器的 DOM Matcher、字符串回退、索引预检和 legacy @ 链分割统一使用带括号、属性、引号、转义、正则字符类和 HTML 引号状态的顶层扫描；伪类参数、属性值、HTML 属性值中的空格、>、@、逗号和括号不再改变外层组合器或 @ 链语义。'
Set-PropertyValue $objective.executionTarget 'statement' '243 direct-child context, top-level split, regex-class pseudo nesting, DOM Matcher selector-group splitting, :has relative-selector context, :not ancestor context, duplicate occurrence identity, bulk offset projection, sibling combinators, of-type position semantics, selector-group occurrence identity, nested marker restoration, direct-child marker lifetime, synthetic Document-root child pseudo semantics, descendant whitespace/pseudo argument context, top-level @ delimiter context, legacy chain regex-character-class @ context and quote-aware HTML tag-boundary scanning are statically closed and registered; runtime, full Harness, Legado differential, build and device gates remain deferred.'
Set-PropertyValue $objective 'nextAction' '243 quote-aware string-selector HTML tag-boundary static closure is registered; continue one-root-cause source audit while R4 remains deferred.'
$plan = @($objective.continuationPlan)
if (-not @($plan | Where-Object { [string]$_.id -eq '243-SP-34' })) {
  $plan += [pscustomobject][ordered]@{ id = '243-SP-34'; status = 'completed'; action = '统一字符串选择器回退、发生位置标记和元素提取的 HTML 开始标签边界扫描，属性值内的 > 不再截断标签。'; evidence = @($FixturePath, $FailureWitnessPath, $PostFixContractPath, $CurrentHeadAuditPath, $SourceFixPath) }
  $plan += [pscustomobject][ordered]@{ id = '243-SP-35'; status = 'deferred'; action = 'R4 执行带引号 > 的字符串选择器场景、代表性冻结书源、243 影响集合、458 条 Harness、Legado 差分、构建和真机验证。' }
  Set-PropertyValue $objective 'continuationPlan' $plan
}
Write-AtomicJson $objectivePath $objective

$updateScript = Get-RepoPath 'tools/legado-compat/Update-LegadoGovernanceState.ps1'
$evidence = @($FixturePath, $FailureWitnessPath, $PostFixContractPath, $CurrentHeadAuditPath, $SourceFixPath, $analyzerPath, 'tools/legado-compat/Test-LegadoJsoupStringSelectorQuotedTagEndFailureWitness.ps1', 'tools/legado-compat/Test-LegadoJsoupStringSelectorQuotedTagEndPostFixContract.ps1', 'tools/legado-compat/Test-LegadoJsoupStringSelectorQuotedTagEndCurrentHeadAudit.ps1', 'tools/legado-compat/Register-LegadoJsoupStringSelectorQuotedTagEndSourceFix.ps1', 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt')
$summary = '243 string-selector fallback now uses the shared quote-aware HTML tag-boundary scanner across class/id/text lookup, simple selectors, occurrence markers and element extraction. Runtime, full Harness, Legado differential, build and device validation remain deferred.'
$closeCondition = [string]$sourceFix.closeCondition
$pwsh = (Get-Command pwsh -ErrorAction Stop).Source
$updateOutput = & $pwsh -NoLogo -NoProfile -NonInteractive -File $updateScript -IssueId $issueId -IssueStatus verifying -TaskId $taskId -TaskStatus running -Summary $summary -CloseCondition $closeCondition -EvidencePath ([string]::Join(',', $evidence)) 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { throw "Update-LegadoGovernanceState failed:`n$updateOutput" }
[pscustomobject][ordered]@{ status = 'registered'; issueId = $issueId; sourceFixEvidencePath = $SourceFixPath; currentHeadAuditPath = $CurrentHeadAuditPath; postFixContractPath = $PostFixContractPath; governanceUpdate = $updateOutput.Trim(); runtimeActionsPerformed = @(); semanticMatchAllowed = $false } | ConvertTo-Json -Depth 100
