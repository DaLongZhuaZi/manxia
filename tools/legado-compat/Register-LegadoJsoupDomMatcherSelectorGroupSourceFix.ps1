[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-dom-matcher-selector-group-context.json',
  [string]$FailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-jsoup-dom-matcher-selector-group-pre-fix-20260810.json',
  [string]$PostFixContractPath = 'tools/legado-compat/evidence/contract-legado-jsoup-dom-matcher-selector-group-post-fix-20260810.json',
  [string]$CurrentHeadAuditPath = 'tools/legado-compat/evidence/v2-jsoup-dom-matcher-selector-group-current-head-audit-20260810.json',
  [string]$SourceFixPath = 'tools/legado-compat/evidence/v2-jsoup-dom-matcher-selector-group-source-fix-20260810.json'
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
$revision = '2026-08-10-actual-docs-source-refactor-jsoup-dom-matcher-selector-group-static-closure'
$matcherPath = 'entry/src/main/ets/libs/htmlparser/Matcher.ets'

function Get-RepoPath {
  param([Parameter(Mandatory = $true)][string]$Path)
  if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }
  return Join-Path $RepositoryRoot ($Path.Replace('/', '\'))
}
function Read-StrictText {
  param([Parameter(Mandatory = $true)][string]$Path)
  $resolved = Get-RepoPath $Path
  if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "required file is missing: $Path" }
  $bytes = [System.IO.File]::ReadAllBytes($resolved)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $Path" }
  return $strictUtf8.GetString($bytes)
}
function Read-StrictJson { param([Parameter(Mandatory = $true)][string]$Path); return (Read-StrictText $Path | ConvertFrom-Json -Depth 100) }
function Set-PropertyValue {
  param([Parameter(Mandatory = $true)][object]$Object, [Parameter(Mandatory = $true)][string]$Name, [object]$Value)
  if ($null -eq $Object.PSObject.Properties[$Name]) { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force } else { $Object.$Name = $Value }
}
function Write-AtomicJson {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value)
  $resolved = Get-RepoPath $Path
  $directory = Split-Path -Parent $resolved
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporary = "$resolved.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8)
    Move-Item -LiteralPath $temporary -Destination $resolved -Force
  } finally {
    if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) }
  }
}
function Assert-Gate { param([bool]$Condition, [string]$Detail); if (-not $Condition) { throw "243 DOM Matcher selector-group source-fix gate failed: $Detail" } }

$statePath = 'tools/legado-compat/state/full-source-validation-state.json'
$objectivePath = 'tools/legado-compat/state/refactor-objective.json'
$state = Read-StrictJson $statePath
$objective = Read-StrictJson $objectivePath
$fixture = Read-StrictJson $FixturePath
$failure = Read-StrictJson $FailureWitnessPath
$contract = Read-StrictJson $PostFixContractPath
$audit = Read-StrictJson $CurrentHeadAuditPath
$matcher = Read-StrictText $matcherPath
$issue = @($state.governance.issues | Where-Object { [string]$_.id -eq $issueId })[0]

Assert-Gate ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'frozen baseline drifted.'
Assert-Gate ([string]$state.governance.status -eq 'running' -and [string]$state.governance.activeTaskId -eq $taskId -and [string]$state.governance.activeIssueId -eq $issueId -and -not [bool]$state.governance.semanticMatchAllowed) '243 must remain the active static issue.'
Assert-Gate ($null -ne $issue -and [string]$issue.status -eq 'verifying') '243 must remain verifying.'
Assert-Gate ([string]$failure.status -eq 'failed' -and [string]$contract.status -eq 'passed' -and [string]$audit.status -eq 'passed' -and -not [bool]$failure.semanticMatchAllowed -and -not [bool]$contract.semanticMatchAllowed -and -not [bool]$audit.semanticMatchAllowed) 'failure, post-fix and current-head evidence must remain static-only.'
Assert-Gate (@($fixture.cases).Count -eq 2 -and $matcher.Contains('let parenthesisDepth = 0') -and $matcher.Contains('let bracketDepth = 0') -and $matcher.Contains("if (char === ',' && parenthesisDepth === 0 && bracketDepth === 0)")) 'context-aware DOM group splitter fix is missing.'

$existingSourceFixPath = Get-RepoPath $SourceFixPath
if ([string]$objective.targetRevision -eq $revision -and (Test-Path -LiteralPath $existingSourceFixPath -PathType Leaf)) {
  [pscustomobject][ordered]@{
    status = 'already_registered'
    issueId = $issueId
    targetRevision = $revision
    sourceFixEvidencePath = $SourceFixPath
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    idempotent = $true
  } | ConvertTo-Json -Depth 100
  return
}

$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Get-RepoPath $matcherPath)).Hash.ToUpperInvariant()
$sourceFix = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'source_fix'
  issueId = $issueId
  status = 'source_closed_static_only'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  extends = 'tools/legado-compat/evidence/v2-jsoup-regex-class-parenthesis-source-fix-20260810.json'
  failureEvidence = @($FailureWitnessPath)
  staticContract = $PostFixContractPath
  currentHeadAudit = $CurrentHeadAuditPath
  changedPaths = @($matcherPath)
  currentHeadHashes = [pscustomobject][ordered]@{ $matcherPath = $hash }
  affectedCases = @($fixture.cases | ForEach-Object { [string]$_.id })
  representativeSourceSet = $fixture.representativeSourceSet
  rootCause = [pscustomobject][ordered]@{
    category = '规则解析或编译'
    before = 'Matcher.splitByComma used one depth counter for both parentheses and brackets. A literal ) inside a regex character class such as [)] decremented the outer pseudo depth and exposed an inner comma as a top-level selector-group delimiter.'
    after = 'Matcher.splitByComma tracks parenthesis depth, bracket depth, quotes and escapes independently. Parentheses are opaque while bracketDepth is nonzero, and only commas at zero bracket and pseudo depth split groups.'
    legadoReference = 'Pinned Legado AnalyzeByJSoup delegates CSS groups to Jsoup Element.select; Jsoup QueryParser preserves regex, attribute, quoted and nested pseudo contexts before group union.'
  }
  consumerMatrix = [pscustomobject][ordered]@{
    domMatcher = $matcherPath
    domBridge = 'entry/src/main/ets/libs/htmlparser/LegadoHtmlBridge.ets'
    v2Analyzer = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
    representativeSource = '$[356].ruleContent.nextContentUrl (ordinal 357)'
    legado = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt; legado/app/src/main/java/io/legado/app/model/analyzeRule/RuleAnalyzer.kt'
  }
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_243_dom_matcher_selector_group_source_fix_static_only;R4_runtime_build_device_and_legado_diff_deferred'
  closeCondition = 'R4 must execute both DOM Matcher selector-group cases through V2, the representative frozen source, affected 243 sources, deterministic 458-source Harness, fixed-Legado differential, build and device gates before 243 can leave verifying.'
}
Write-AtomicJson $SourceFixPath $sourceFix

$now = [DateTimeOffset]::UtcNow.ToString('o')
Set-PropertyValue $objective 'lastReviewedAt' $now
Set-PropertyValue $objective 'targetRevision' $revision
Set-PropertyValue $objective 'continuationMode' 'R3_ISSUE_243_STANDARD_CSS_PSEUDO_STATIC_CLOSED_WAIT_R4'
Set-PropertyValue $objective.authority 'activeIssueId' $issueId
Set-PropertyValue $objective.authority 'activeIssueSelection' 'full-source-validation-state.json remains the only queue; 243 remains the sole active source-closure issue. DOM Matcher selector-group splitting now preserves regex-character-class parentheses, quotes and escapes; semanticMatchAllowed remains false and R4 is deferred.'
Set-PropertyValue $objective.objective 'activeIssueRule' '243 标准 CSS 选择器的 DOM Matcher、字符串回退、索引预检和 legacy @ 链分割统一使用带括号、属性、引号、转义、正则字符类和 <js> 状态的顶层扫描；伪类参数或属性值中的空格、>、@、逗号和括号不再改变外层组合器或 @ 链语义。'
Set-PropertyValue $objective.executionTarget 'statement' '243 direct-child context, top-level split, regex-class pseudo nesting, DOM Matcher selector-group splitting, :has relative-selector context, :not ancestor context, duplicate occurrence identity, bulk offset projection, sibling combinators, of-type position semantics, selector-group occurrence identity, nested marker restoration, direct-child marker lifetime, synthetic Document-root child pseudo semantics, descendant whitespace/pseudo argument context, top-level @ delimiter context and legacy chain regex-character-class @ context are statically closed and registered; runtime, full Harness, Legado differential, build and device gates remain deferred.'
Set-PropertyValue $objective 'nextAction' '243 DOM Matcher selector-group regex-character-class context static closure is registered; continue one-root-cause source audit while R4 remains deferred.'
$plan = @($objective.continuationPlan)
if (-not @($plan | Where-Object { [string]$_.id -eq '243-SP-33' })) {
  $plan += [pscustomobject][ordered]@{ id = '243-SP-33'; status = 'completed'; action = '修复 DOM Matcher.splitByComma 对正则字符类、括号、引号和转义的上下文泄漏；伪类参数内逗号不再被误判为选择器组边界。'; evidence = @($FixturePath, $FailureWitnessPath, $PostFixContractPath, $CurrentHeadAuditPath, $SourceFixPath) }
  $plan += [pscustomobject][ordered]@{ id = '243-SP-34'; status = 'deferred'; action = 'R4 执行 DOM Matcher 选择器组场景、代表性冻结书源、243 影响集合、458 条 Harness、Legado 差分、构建和真机验证。' }
  Set-PropertyValue $objective 'continuationPlan' $plan
}
Write-AtomicJson $objectivePath $objective

$updateScript = Get-RepoPath 'tools/legado-compat/Update-LegadoGovernanceState.ps1'
$evidence = @($FixturePath, $FailureWitnessPath, $PostFixContractPath, $CurrentHeadAuditPath, $SourceFixPath, $matcherPath, 'tools/legado-compat/Test-LegadoJsoupDomMatcherSelectorGroupFailureWitness.ps1', 'tools/legado-compat/Test-LegadoJsoupDomMatcherSelectorGroupPostFixContract.ps1', 'tools/legado-compat/Test-LegadoJsoupDomMatcherSelectorGroupCurrentHeadAudit.ps1', 'tools/legado-compat/Register-LegadoJsoupDomMatcherSelectorGroupSourceFix.ps1', 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets', 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt', 'legado/app/src/main/java/io/legado/app/model/analyzeRule/RuleAnalyzer.kt')
$summary = '243 DOM Matcher.splitByComma now preserves commas inside regex character classes and nested Jsoup pseudo arguments by tracking parentheses, brackets, quotes and escapes independently. Runtime, full Harness, Legado differential, build and device validation remain deferred.'
$closeCondition = [string]$sourceFix.closeCondition
$pwsh = (Get-Command pwsh -ErrorAction Stop).Source
$updateOutput = & $pwsh -NoLogo -NoProfile -NonInteractive -File $updateScript -IssueId $issueId -IssueStatus verifying -TaskId $taskId -TaskStatus running -Summary $summary -CloseCondition $closeCondition -EvidencePath ([string]::Join(',', $evidence)) 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { throw "Update-LegadoGovernanceState failed:`n$updateOutput" }
[pscustomobject][ordered]@{ status = 'registered'; issueId = $issueId; sourceFixEvidencePath = $SourceFixPath; currentHeadAuditPath = $CurrentHeadAuditPath; postFixContractPath = $PostFixContractPath; governanceUpdate = $updateOutput.Trim(); runtimeActionsPerformed = @(); semanticMatchAllowed = $false } | ConvertTo-Json -Depth 100
