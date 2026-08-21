[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-standard-pseudo-selector-direct-child-split-context.json',
  [string]$FailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-jsoup-standard-pseudo-selector-direct-child-split-context-pre-fix-20260809.json',
  [string]$PostFixContractPath = 'tools/legado-compat/evidence/contract-legado-jsoup-standard-pseudo-selector-direct-child-split-context-post-fix-20260809.json',
  [string]$CurrentHeadAuditPath = 'tools/legado-compat/evidence/v2-jsoup-standard-pseudo-selector-direct-child-split-context-current-head-audit-20260809.json',
  [string]$SourceFixPath = 'tools/legado-compat/evidence/v2-jsoup-standard-pseudo-selector-direct-child-split-context-source-fix-20260809.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
$taskId = 'COMPAT-006'
$baselineHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$analyzerRelativePath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
$script:assertions = 0

function Get-RepoPath {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictText {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  $path = Get-RepoPath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "required file is missing: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw "UTF-8 BOM is not allowed: $RelativePath"
  }
  return $strictUtf8.GetString($bytes)
}

function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  return (Read-StrictText -RelativePath $RelativePath | ConvertFrom-Json -Depth 100)
}

function Get-PropertyValue {
  param([object]$Object, [string]$Name, [object]$Default = $null)
  if ($null -eq $Object) { return $Default }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property -or $null -eq $property.Value) { return $Default }
  return $property.Value
}

function Set-PropertyValue {
  param([Parameter(Mandatory = $true)][object]$Object, [Parameter(Mandatory = $true)][string]$Name, [object]$Value)
  if ($null -eq $Object.PSObject.Properties[$Name]) {
    $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
  } else {
    $Object.$Name = $Value
  }
}

function Assert-Gate {
  param([bool]$Condition, [string]$Detail)
  if (-not $Condition) { throw "243 direct-child split source-fix gate failed: $Detail" }
  $script:assertions++
}

function Write-AtomicJson {
  param([Parameter(Mandatory = $true)][string]$RelativePath, [Parameter(Mandatory = $true)][object]$Value)
  $path = Get-RepoPath $RelativePath
  $directory = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporaryPath = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8)
    Move-Item -LiteralPath $temporaryPath -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

function Find-Issue {
  param([object[]]$Issues, [string]$Id)
  foreach ($candidate in @($Issues)) {
    if ([string](Get-PropertyValue $candidate 'id' '') -eq $Id) { return $candidate }
  }
  return $null
}

$stateRelativePath = 'tools/legado-compat/state/full-source-validation-state.json'
$objectiveRelativePath = 'tools/legado-compat/state/refactor-objective.json'
$state = Read-StrictJson $stateRelativePath
$fixture = Read-StrictJson $FixturePath
$failure = Read-StrictJson $FailureWitnessPath
$contract = Read-StrictJson $PostFixContractPath
$audit = Read-StrictJson $CurrentHeadAuditPath
$analyzer = Read-StrictText $analyzerRelativePath
$issue = Find-Issue @($state.governance.issues) $issueId

Assert-Gate ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'the frozen 458-source package and Legado commit remain unchanged.'
Assert-Gate ([string]$state.governance.status -eq 'running' -and [string]$state.governance.activeTaskId -eq $taskId -and [string]$state.governance.activeIssueId -eq $issueId -and -not [bool]$state.governance.semanticMatchAllowed) '243 is the sole active issue and semantic match remains disabled.'
Assert-Gate ($null -ne $issue -and [string]$issue.status -eq 'verifying') '243 must remain verifying before registration.'
Assert-Gate ([string]$failure.status -eq 'failed' -and -not [bool]$failure.semanticMatchAllowed -and @($failure.runtimeActionsPerformed).Count -eq 0) 'failure witness must remain failed and static-only.'
Assert-Gate ([string]$contract.status -eq 'passed' -and -not [bool]$contract.semanticMatchAllowed -and @($contract.runtimeActionsPerformed).Count -eq 0) 'post-fix contract must be a static-only pass.'
Assert-Gate ([string]$audit.status -eq 'passed' -and -not [bool]$audit.semanticMatchAllowed -and @($audit.runtimeActionsPerformed).Count -eq 0) 'current-head audit must be a static-only pass.'
Assert-Gate (@($fixture.cases).Count -eq 4) 'the split-context fixture must contain four cases.'
$helperStart = $analyzer.IndexOf('private splitTopLevelDirectChildSelectors(')
$helperEnd = $analyzer.IndexOf('private findElementsByDirectChildSelector(', $helperStart)
$directChildEnd = $analyzer.IndexOf('private getElementsByRegex(', $helperEnd)
Assert-Gate ($helperStart -ge 0 -and $helperEnd -gt $helperStart -and $directChildEnd -gt $helperEnd) 'the parser and direct-child function boundaries must be present.'
$directChildBody = $analyzer.Substring($helperEnd, $directChildEnd - $helperEnd)
Assert-Gate ($directChildBody.Contains('this.splitTopLevelDirectChildSelectors(selector)') -and -not $directChildBody.Contains("selector.split('>')")) 'the direct-child path must consume the top-level-aware splitter.'

$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Get-RepoPath $analyzerRelativePath)).Hash.ToUpperInvariant()
$sourceFix = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'source_fix'
  issueId = $issueId
  status = 'source_closed_static_only'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  supersedes = 'tools/legado-compat/evidence/v2-jsoup-standard-pseudo-selector-direct-child-context-source-fix-20260809.json'
  rootCause = [pscustomobject][ordered]@{
    category = '规则解析或编译'
    originalSemantics = 'Pinned Legado delegates CSS selection to Jsoup Element.select; a greater-than character inside pseudo arguments, attribute values, regex text, or quotes is not a top-level child combinator.'
    v2BeforeFix = "findElementsByDirectChildSelector used selector.split('>'), so nested greater-than characters corrupted selector parts before direct-child matching and could produce empty or malformed results in the large-document fallback."
    evidence = @($FailureWitnessPath, 'tools/legado-compat/fixtures/legado-jsoup-standard-pseudo-selector-direct-child-split-context.json')
  }
  changedPaths = @($analyzerRelativePath)
  change = 'Added a stateful top-level selector splitter that tracks parentheses, brackets, quotes, and escapes, then made the direct-child fallback use it. Nested greater-than text is preserved while only actual top-level child combinators create selector boundaries.'
  fixturePath = $FixturePath
  failureEvidence = @($FailureWitnessPath)
  staticContract = $PostFixContractPath
  currentHeadAudit = $CurrentHeadAuditPath
  currentHeadHashes = [pscustomobject][ordered]@{ $analyzerRelativePath = $hash }
  assertions = $script:assertions
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_source_fix_static_only;243_verifying;R4_runtime_build_device_and_legado_diff_deferred'
  closeCondition = 'R4 must execute nested pseudo, attribute, regex and top-level direct-child cases, the existing 52-rule/21-source set, deterministic 458-source Harness, fixed-Legado differential, build and device gates before 243 can leave verifying.'
}
Write-AtomicJson $SourceFixPath $sourceFix

$objective = Read-StrictJson $objectiveRelativePath
$now = [DateTimeOffset]::UtcNow.ToString('o')
Set-PropertyValue $objective 'lastReviewedAt' $now
Set-PropertyValue $objective 'targetRevision' '2026-08-09-actual-docs-source-refactor-jsoup-standard-pseudo-243-direct-child-split-static-closure'
Set-PropertyValue $objective 'continuationMode' 'R3_ISSUE_243_STANDARD_CSS_PSEUDO_STATIC_CLOSED_WAIT_R4'
Set-PropertyValue $objective.authority 'activeIssueId' $issueId
Set-PropertyValue $objective.authority 'activeIssueSelection' 'full-source-validation-state.json remains the only queue; 243 remains the sole active source-closure issue. The direct-child scoped sibling-context and top-level selector-split closures are static only; semantic_match remains disabled.'
Set-PropertyValue $objective.objective 'activeIssue' $issueId
Set-PropertyValue $objective.objective 'activeIssueRule' '243 标准 CSS child pseudo 的大文档字符串回退已补齐 scoped-parent 兄弟上下文和顶层 direct-child 选择器分割；嵌套 :has/:not、属性值、正则和引号中的 > 不再被误当作组合符；R4 deferred。'
Set-PropertyValue $objective.executionTarget 'currentIssue' $issueId
Set-PropertyValue $objective.executionTarget 'statement' '243 direct-child sibling context and top-level selector splitting are statically closed and registered; runtime, full Harness, Legado differential, build and device gates remain deferred.'
Set-PropertyValue $objective.continuationTarget 'activeBoundary' '243 保持 verifying；direct-child scoped-parent 兄弟上下文与顶层 > 分割、失败见证、post-fix/current-head/source-fix 证据已登记；242 保持 verifying 等待 R4。'
Set-PropertyValue $objective.continuationTarget 'nextTransition' '继续审计 243 的多级链、重复兄弟和其他伪类组合；R4 运行时与差分保持延期。'
Set-PropertyValue $objective 'nextAction' '243 top-level direct-child selector split static closure is registered; continue one-root-cause source audit while R4 remains deferred.'
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
  $SourceFixPath,
  'tools/legado-compat/Test-LegadoJsoupStandardPseudoSelectorDirectChildSplitFailureWitness.ps1',
  'tools/legado-compat/Test-LegadoJsoupStandardPseudoSelectorDirectChildSplitPostFixContract.ps1',
  'tools/legado-compat/Test-LegadoJsoupStandardPseudoSelectorDirectChildSplitCurrentHeadAudit.ps1',
  'tools/legado-compat/Register-LegadoJsoupStandardPseudoSelectorDirectChildSplitSourceFix.ps1',
  'tools/legado-compat/Apply-LegadoJsoupDirectChildSplitFix.ps1',
  $analyzerRelativePath,
  'entry/src/main/ets/libs/htmlparser/HTMLElement.ets',
  'entry/src/main/resources/rawfile/legado_runtime.html',
  'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
)
$summary = '243 direct-child selector splitting is statically closed: the large-document fallback now splits only top-level > and preserves nested pseudo, attribute, regex, quote and escape contexts; the scoped sibling-context closure remains preserved. R4 deferred.'
$evidenceArgument = [string]::Join(',', $evidence)
$updateOutput = & pwsh -NoLogo -NoProfile -NonInteractive -File $updateScript -IssueId $issueId -IssueStatus verifying -TaskId $taskId -TaskStatus running -Summary $summary -CloseCondition ([string]$sourceFix.closeCondition) -EvidencePath $evidenceArgument 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { throw "Update-LegadoGovernanceState failed:`n$updateOutput" }

$result = [pscustomobject][ordered]@{
  status = 'registered'
  issueId = $issueId
  sourceFixEvidencePath = $SourceFixPath
  currentHeadAuditPath = $CurrentHeadAuditPath
  splitContractPath = $PostFixContractPath
  assertions = $script:assertions
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  governanceUpdate = $updateOutput.Trim()
}
$result | ConvertTo-Json -Depth 80
