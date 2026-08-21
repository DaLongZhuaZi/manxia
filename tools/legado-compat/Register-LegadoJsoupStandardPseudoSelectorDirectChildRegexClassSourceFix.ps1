[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-standard-pseudo-selector-direct-child-regex-class-context.json',
  [string]$FailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-jsoup-standard-pseudo-selector-direct-child-regex-class-context-pre-fix-20260809.json',
  [string]$PostFixContractPath = 'tools/legado-compat/evidence/contract-legado-jsoup-standard-pseudo-selector-direct-child-regex-class-context-post-fix-20260809.json',
  [string]$CurrentHeadAuditPath = 'tools/legado-compat/evidence/v2-jsoup-standard-pseudo-selector-direct-child-regex-class-context-current-head-audit-20260809.json',
  [string]$PreviousSplitContractPath = 'tools/legado-compat/evidence/contract-legado-jsoup-standard-pseudo-selector-direct-child-split-context-post-fix-20260809.json',
  [string]$SourceFixPath = 'tools/legado-compat/evidence/v2-jsoup-standard-pseudo-selector-direct-child-regex-class-context-source-fix-20260809.json'
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
$analyzerRelativePath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
$script:assertions = 0

function Get-RepoPath { param([Parameter(Mandatory = $true)][string]$RelativePath); return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\')) }
function Read-StrictText {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  $path = Get-RepoPath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "required file is missing: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $RelativePath" }
  return $strictUtf8.GetString($bytes)
}
function Read-StrictJson { param([Parameter(Mandatory = $true)][string]$RelativePath); return (Read-StrictText -RelativePath $RelativePath | ConvertFrom-Json -Depth 100) }
function Get-PropertyValue { param([object]$Object, [string]$Name, [object]$Default = $null); if ($null -eq $Object) { return $Default }; $property = $Object.PSObject.Properties[$Name]; if ($null -eq $property -or $null -eq $property.Value) { return $Default }; return $property.Value }
function Set-PropertyValue { param([Parameter(Mandatory = $true)][object]$Object, [Parameter(Mandatory = $true)][string]$Name, [object]$Value); if ($null -eq $Object.PSObject.Properties[$Name]) { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force } else { $Object.$Name = $Value } }
function Assert-Gate { param([bool]$Condition, [string]$Detail); if (-not $Condition) { throw "243 regex-class source-fix gate failed: $Detail" }; $script:assertions++ }
function Write-AtomicJson {
  param([Parameter(Mandatory = $true)][string]$RelativePath, [Parameter(Mandatory = $true)][object]$Value)
  $path = Get-RepoPath $RelativePath
  $directory = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporaryPath = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try { [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8); Move-Item -LiteralPath $temporaryPath -Destination $path -Force }
  finally { if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) } }
}

$stateRelativePath = 'tools/legado-compat/state/full-source-validation-state.json'
$objectiveRelativePath = 'tools/legado-compat/state/refactor-objective.json'
$state = Read-StrictJson $stateRelativePath
$objective = Read-StrictJson $objectiveRelativePath
$fixture = Read-StrictJson $FixturePath
$failure = Read-StrictJson $FailureWitnessPath
$contract = Read-StrictJson $PostFixContractPath
$audit = Read-StrictJson $CurrentHeadAuditPath
$previousSplitContract = Read-StrictJson $PreviousSplitContractPath
$analyzer = Read-StrictText $analyzerRelativePath
$issue = @($state.governance.issues | Where-Object { [string]$_.id -eq $issueId })[0]
Assert-Gate ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'the frozen 458-source package and Legado commit remain unchanged.'
Assert-Gate ([string]$state.governance.status -eq 'running' -and [string]$state.governance.activeTaskId -eq $taskId -and [string]$state.governance.activeIssueId -eq $issueId -and -not [bool]$state.governance.semanticMatchAllowed) '243 is the sole active issue and semantic match remains disabled.'
Assert-Gate ($null -ne $issue -and [string]$issue.status -eq 'verifying') '243 must remain verifying.'
Assert-Gate ([string]$failure.status -eq 'failed' -and -not [bool]$failure.semanticMatchAllowed -and @($failure.runtimeActionsPerformed).Count -eq 0) 'regex-class failure witness must remain failed and static-only.'
Assert-Gate ([string]$contract.status -eq 'passed' -and -not [bool]$contract.semanticMatchAllowed -and @($contract.runtimeActionsPerformed).Count -eq 0) 'regex-class post-fix contract must be static-only.'
Assert-Gate ([string]$audit.status -eq 'passed' -and -not [bool]$audit.semanticMatchAllowed) 'regex-class current-head audit must be static-only.'
Assert-Gate ([string]$previousSplitContract.status -eq 'passed' -and -not [bool]$previousSplitContract.semanticMatchAllowed) 'the previous top-level split contract must remain preserved.'
Assert-Gate (@($fixture.cases).Count -eq 2) 'regex-class fixture must contain two cases.'
$helperStart = $analyzer.IndexOf('private splitTopLevelDirectChildSelectors(')
$helperEnd = $analyzer.IndexOf('private findElementsByDirectChildSelector(', $helperStart)
Assert-Gate ($helperStart -ge 0 -and $helperEnd -gt $helperStart) 'splitter boundary must be present.'
$helperBody = $analyzer.Substring($helperStart, $helperEnd - $helperStart)
Assert-Gate ($helperBody.Contains("if (character === '(' && bracketDepth === 0) {") -and $helperBody.Contains("else if (character === ')' && parenthesisDepth > 0 && bracketDepth === 0) {")) 'regex-class parenthesis guards must be present.'

$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Get-RepoPath $analyzerRelativePath)).Hash.ToUpperInvariant()
$sourceFix = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'source_fix'
  issueId = $issueId
  status = 'source_closed_static_only'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  supersedes = 'tools/legado-compat/evidence/v2-jsoup-standard-pseudo-selector-direct-child-split-context-source-fix-20260809.json'
  rootCause = [pscustomobject][ordered]@{
    category = '规则解析或编译'
    originalSemantics = 'Jsoup keeps regex character classes opaque while parsing pseudo arguments; a greater-than inside :matches(...) is data until the outer pseudo closes.'
    v2BeforeFix = 'The top-level direct-child splitter tracked bracketDepth but still decremented parenthesisDepth for a closing parenthesis inside a bracket, so a later greater-than in the open regex pseudo argument was emitted as a direct-child boundary.'
    evidence = @($FailureWitnessPath, $FixturePath)
  }
  changedPaths = @($analyzerRelativePath)
  change = 'Guard both opening and closing pseudo-parenthesis depth transitions with bracketDepth == 0. Regex and attribute brackets are now opaque to pseudo nesting, while the existing quote and escape handling remains unchanged.'
  fixturePath = $FixturePath
  failureEvidence = @($FailureWitnessPath)
  staticContract = $PostFixContractPath
  currentHeadAudit = $CurrentHeadAuditPath
  currentHeadHashes = [pscustomobject][ordered]@{ $analyzerRelativePath = $hash }
  assertions = $script:assertions
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_source_fix_static_only;243_verifying;R4_runtime_build_device_and_legado_diff_deferred'
  closeCondition = 'R4 must execute regex character-class, nested pseudo and all existing 243 direct-child cases, the 52-rule/21-source set, deterministic 458-source Harness, fixed-Legado differential, build and device gates before 243 can leave verifying.'
}
Write-AtomicJson $SourceFixPath $sourceFix

$now = [DateTimeOffset]::UtcNow.ToString('o')
Set-PropertyValue $objective 'lastReviewedAt' $now
Set-PropertyValue $objective 'targetRevision' '2026-08-09-actual-docs-source-refactor-jsoup-standard-pseudo-243-direct-child-regex-class-static-closure'
Set-PropertyValue $objective 'continuationMode' 'R3_ISSUE_243_STANDARD_CSS_PSEUDO_STATIC_CLOSED_WAIT_R4'
Set-PropertyValue $objective.authority 'activeIssueId' $issueId
Set-PropertyValue $objective.authority 'activeIssueSelection' 'full-source-validation-state.json remains the only queue; 243 remains the sole active source-closure issue. Direct-child sibling context, top-level splitting, and regex-class pseudo nesting are static only; semantic_match remains disabled.'
Set-PropertyValue $objective.objective 'activeIssue' $issueId
Set-PropertyValue $objective.objective 'activeIssueRule' '243 标准 CSS child pseudo 的大文档字符串回退已补齐 scoped-parent 兄弟上下文、顶层 > 分割和正则字符类圆括号隔离；R4 deferred。'
Set-PropertyValue $objective.executionTarget 'currentIssue' $issueId
Set-PropertyValue $objective.executionTarget 'statement' '243 direct-child context, top-level split and regex-class pseudo nesting are statically closed and registered; runtime, full Harness, Legado differential, build and device gates remain deferred.'
Set-PropertyValue $objective.continuationTarget 'activeBoundary' '243 保持 verifying；direct-child scoped-parent、顶层 > 分割、regex-class 伪类嵌套及其失败见证/post-fix/current-head/source-fix 证据已登记；242 保持 verifying 等待 R4。'
Set-PropertyValue $objective.continuationTarget 'nextTransition' '继续审计 243 的多级链、重复兄弟和其他伪类组合；R4 运行时与差分保持延期。'
Set-PropertyValue $objective 'nextAction' '243 regex-class pseudo nesting static closure is registered; continue one-root-cause source audit while R4 remains deferred.'
Set-PropertyValue $objective.objective.queueSelectionGate 'evidencePath' $CurrentHeadAuditPath
Set-PropertyValue $objective.objective.queueSelectionGate 'candidateEvidencePath' $SourceFixPath
Set-PropertyValue $objective.objective.queueSelectionGate 'candidateCurrentHeadAuditEvidencePath' $CurrentHeadAuditPath
Set-PropertyValue $objective.objective.queueSelectionGate 'candidateSourceFixEvidencePath' $SourceFixPath
Write-AtomicJson $objectiveRelativePath $objective

$updateScript = Get-RepoPath 'tools/legado-compat/Update-LegadoGovernanceState.ps1'
$evidence = @(
  $FixturePath,
  $FailureWitnessPath,
  $PostFixContractPath,
  $CurrentHeadAuditPath,
  $PreviousSplitContractPath,
  $SourceFixPath,
  'tools/legado-compat/Test-LegadoJsoupStandardPseudoSelectorDirectChildRegexClassFailureWitness.ps1',
  'tools/legado-compat/Test-LegadoJsoupStandardPseudoSelectorDirectChildRegexClassPostFixContract.ps1',
  'tools/legado-compat/Test-LegadoJsoupStandardPseudoSelectorDirectChildRegexClassCurrentHeadAudit.ps1',
  'tools/legado-compat/Register-LegadoJsoupStandardPseudoSelectorDirectChildRegexClassSourceFix.ps1',
  'tools/legado-compat/Apply-LegadoJsoupDirectChildRegexClassFix.ps1',
  $analyzerRelativePath,
  'entry/src/main/ets/libs/htmlparser/HTMLElement.ets',
  'entry/src/main/resources/rawfile/legado_runtime.html',
  'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
)
$summary = '243 regex-class pseudo nesting is statically closed: direct-child splitting now keeps parenthesis depth opaque inside regex/attribute brackets, so > inside :matches(...) cannot become a false top-level combinator; prior scoped-context and top-level split closures remain preserved. R4 deferred.'
$evidenceArgument = [string]::Join(',', $evidence)
$updateOutput = & pwsh -NoLogo -NoProfile -NonInteractive -File $updateScript -IssueId $issueId -IssueStatus verifying -TaskId $taskId -TaskStatus running -Summary $summary -CloseCondition ([string]$sourceFix.closeCondition) -EvidencePath $evidenceArgument 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { throw "Update-LegadoGovernanceState failed:`n$updateOutput" }

[pscustomobject][ordered]@{
  status = 'registered'
  issueId = $issueId
  sourceFixEvidencePath = $SourceFixPath
  currentHeadAuditPath = $CurrentHeadAuditPath
  regexClassContractPath = $PostFixContractPath
  assertions = $script:assertions
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  governanceUpdate = $updateOutput.Trim()
} | ConvertTo-Json -Depth 80
