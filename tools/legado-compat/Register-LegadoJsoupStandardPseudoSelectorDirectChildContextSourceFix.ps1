[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-standard-pseudo-selector-direct-child-context.json',
  [string]$FailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-jsoup-standard-pseudo-selector-direct-child-context-pre-fix-20260809.json',
  [string]$PostFixContractPath = 'tools/legado-compat/evidence/contract-legado-jsoup-standard-pseudo-selector-direct-child-context-post-fix-20260809.json',
  [string]$PreviousPostFixContractPath = 'tools/legado-compat/evidence/contract-legado-jsoup-standard-pseudo-selectors-post-fix-20260809.json',
  [string]$CurrentHeadAuditPath = 'tools/legado-compat/evidence/v2-jsoup-standard-pseudo-selector-direct-child-context-current-head-audit-20260809.json',
  [string]$SourceFixPath = 'tools/legado-compat/evidence/v2-jsoup-standard-pseudo-selector-direct-child-context-source-fix-20260809.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$baselineHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
$taskId = 'COMPAT-006'
$script:assertions = 0
$script:checks = New-Object 'System.Collections.Generic.List[object]'

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
  if ($null -eq $Object.PSObject.Properties[$Name]) { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force }
  else { $Object.$Name = $Value }
}

function Assert-Gate {
  param([bool]$Condition, [string]$Id, [string]$Detail, [string[]]$Evidence = @())
  if (-not $Condition) { throw "243 direct-child source-fix gate failed: $Detail" }
  $script:assertions++
  [void]$script:checks.Add([pscustomobject][ordered]@{ id = $Id; status = 'passed'; detail = $Detail; evidencePaths = @($Evidence) })
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

function Write-AtomicText {
  param([Parameter(Mandatory = $true)][string]$RelativePath, [Parameter(Mandatory = $true)][string]$Value)
  $path = Get-RepoPath $RelativePath
  $directory = Split-Path -Parent $path
  $temporaryPath = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, $Value, $noBomUtf8)
    Move-Item -LiteralPath $temporaryPath -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

function Find-Issue {
  param([object[]]$Issues, [string]$Id)
  foreach ($issue in $Issues) {
    if ([string](Get-PropertyValue $issue 'id' '') -eq $Id) { return $issue }
  }
  return $null
}

function Update-ObjectivePointer {
  $relativePath = 'tools/legado-compat/state/refactor-objective.json'
  $objective = Read-StrictJson $relativePath
  $now = [DateTimeOffset]::UtcNow.ToString('o')
  Set-PropertyValue $objective 'lastReviewedAt' $now
  Set-PropertyValue $objective 'targetRevision' '2026-08-09-actual-docs-source-refactor-jsoup-standard-pseudo-243-direct-child-context-static-closure'
  Set-PropertyValue $objective 'continuationMode' 'R3_ISSUE_243_STANDARD_CSS_PSEUDO_STATIC_CLOSED_WAIT_R4'
  Set-PropertyValue $objective.authority 'activeIssueId' $issueId
  Set-PropertyValue $objective.authority 'activeIssueSelection' 'full-source-validation-state.json remains the only queue; 243 remains the sole active source-closure issue, with direct-child sibling-context evidence appended. Static closure never becomes semantic_match.'
  Set-PropertyValue $objective.objective 'activeIssue' $issueId
  Set-PropertyValue $objective.objective 'activeIssueRule' '243 标准 CSS child pseudo 的大文档字符串回退已补齐 direct-child scoped-parent 兄弟上下文；52 个规则字符串涉及 21 条书源，R4 deferred。'
  Set-PropertyValue $objective.executionTarget 'currentIssue' $issueId
  Set-PropertyValue $objective.executionTarget 'nextIssues' @()
  Set-PropertyValue $objective.executionTarget 'statement' '243 direct-child sibling-context source fix is statically closed and appended to the active issue; runtime, full Harness, Legado differential, build and device gates remain deferred.'
  Set-PropertyValue $objective.continuationTarget 'activeBoundary' '243 保持 verifying；直接子选择器的 scoped-parent 兄弟上下文、失败见证、post-fix/current-head/source-fix 证据已登记；242 保持 verifying 等待 R4。'
  Set-PropertyValue $objective.continuationTarget 'nextTransition' '继续审计 243 的多级链、重复兄弟和其他伪类组合；R4 运行时与差分保持延期。'
  Set-PropertyValue $objective 'nextAction' '243 direct-child sibling-context static closure is registered; continue one-root-cause source audit while R4 remains deferred.'
  Set-PropertyValue $objective.objective.queueSelectionGate 'candidateEvidencePath' $SourceFixPath
  Set-PropertyValue $objective.objective.queueSelectionGate 'candidateCurrentHeadAuditEvidencePath' $CurrentHeadAuditPath
  Set-PropertyValue $objective.objective.queueSelectionGate 'candidateSourceFixEvidencePath' $SourceFixPath
  Set-PropertyValue $objective.objective.queueSelectionGate 'evidencePath' $CurrentHeadAuditPath
  Write-AtomicJson $relativePath $objective
}

$stateRelativePath = 'tools/legado-compat/state/full-source-validation-state.json'
$state = Read-StrictJson $stateRelativePath
$fixture = Read-StrictJson $FixturePath
$failure = Read-StrictJson $FailureWitnessPath
$directContract = Read-StrictJson $PostFixContractPath
$previousContract = Read-StrictJson $PreviousPostFixContractPath
$analyzerRelativePath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
$elementRelativePath = 'entry/src/main/ets/libs/htmlparser/HTMLElement.ets'
$runtimeRelativePath = 'entry/src/main/resources/rawfile/legado_runtime.html'
$legadoRelativePath = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
$analyzer = Read-StrictText $analyzerRelativePath
$element = Read-StrictText $elementRelativePath
$runtime = Read-StrictText $runtimeRelativePath
$legado = Read-StrictText $legadoRelativePath

Assert-Gate ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'baseline' 'the frozen 458-source package and Legado commit remain unchanged.' @($stateRelativePath)
Assert-Gate ([string]$state.governance.status -eq 'running' -and [string]$state.governance.activeTaskId -eq $taskId -and [string]$state.governance.activeIssueId -eq $issueId -and -not [bool]$state.governance.semanticMatchAllowed) 'queue' '243 is the sole active issue and semantic match remains disabled.' @($stateRelativePath)
$record = Find-Issue @($state.governance.issues) $issueId
Assert-Gate ($null -ne $record -and [string]$record.status -eq 'verifying') 'issue_status' '243 remains verifying rather than being promoted by static evidence.' @($stateRelativePath)
Assert-Gate ([string]$failure.status -eq 'failed' -and -not [bool]$failure.semanticMatchAllowed -and @($failure.runtimeActionsPerformed).Count -eq 0) 'failure_witness' 'the direct-child pre-fix witness remains failed and static-only.' @($FailureWitnessPath)
Assert-Gate ([string]$directContract.status -eq 'passed' -and -not [bool]$directContract.semanticMatchAllowed -and @($directContract.runtimeActionsPerformed).Count -eq 0) 'direct_contract' 'the direct-child post-fix contract is a static-only pass.' @($PostFixContractPath)
Assert-Gate ([string]$previousContract.status -eq 'passed' -and -not [bool]$previousContract.semanticMatchAllowed -and @($previousContract.runtimeActionsPerformed).Count -eq 0) 'previous_contract' 'the six-case standard pseudo static contract remains preserved.' @($PreviousPostFixContractPath)
Assert-Gate ([string]$fixture.issueId -eq $issueId -and @($fixture.cases).Count -eq 4) 'fixture_shape' 'the direct-child fixture contains four cases bound to 243.' @($FixturePath)

$directChildStart = $analyzer.IndexOf('private findElementsByDirectChildSelector(')
$directChildEnd = $analyzer.IndexOf('private getElementsByRegex(', $directChildStart)
Assert-Gate ($directChildStart -ge 0 -and $directChildEnd -gt $directChildStart) 'direct_child_function' 'the direct-child string fallback path is present.' @($analyzerRelativePath)
$directChildBody = $analyzer.Substring($directChildStart, $directChildEnd - $directChildStart)
Assert-Gate ($directChildBody.Contains('findDirectChildOccurrences(innerHtml)') -and $directChildBody.Contains('const scopedParent = `<legado-direct-parent>${innerHtml}</legado-direct-parent>`')) 'scoped_parent' 'standard pseudo evaluation receives the complete sibling context.' @($analyzerRelativePath)
Assert-Gate ($directChildBody.Contains('mapStringElementOccurrences(scopedParent, matches)') -and $directChildBody.Contains('matchedRelativeStarts')) 'occurrence_projection' 'matches are projected by source offset so identical siblings remain distinct.' @($analyzerRelativePath)
Assert-Gate (-not $directChildBody.Contains('findElementsBySimpleSelector(child, childSelector)') -and $directChildBody.Contains('nextElements.push(childOccurrence.element)')) 'isolated_child_removed' 'the isolated-child evaluation path is removed.' @($analyzerRelativePath)
Assert-Gate ($analyzer.Contains('filterElementsByStandardChildPseudo(filtered, pseudo.name, contextHtml, argument)') -and $element.Contains("pseudo.name === 'first-child'") -and $runtime.Contains('root.querySelectorAll(browserSelector)') -and $legado.Contains('temp.select(ruleStr)')) 'consumer_paths' 'Analyzer, DOM matcher, ArkWeb and pinned Legado consumer paths remain bound.' @($analyzerRelativePath, $elementRelativePath, $runtimeRelativePath, $legadoRelativePath)

$hashes = [ordered]@{}
foreach ($path in @($analyzerRelativePath, $elementRelativePath, $runtimeRelativePath)) {
  $absolutePath = Get-RepoPath $path
  $bytes = [System.IO.File]::ReadAllBytes($absolutePath)
  Assert-Gate (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) ('no_bom_' + $path.Replace('/', '_')) ("source has no UTF-8 BOM: $path") @($path)
  $hashes[$path] = (Get-FileHash -Algorithm SHA256 -LiteralPath $absolutePath).Hash.ToUpperInvariant()
}

$currentHead = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'current_head_static_audit'
  issueId = $issueId
  status = 'passed'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  supersedes = 'tools/legado-compat/evidence/v2-jsoup-standard-pseudo-selector-current-head-audit-20260809.json'
  changedPaths = @($analyzerRelativePath, $elementRelativePath, $runtimeRelativePath)
  currentHeadHashes = $hashes
  consumerMatrix = @(
    [pscustomobject][ordered]@{ id = 'large_document_string_fallback_direct_child'; path = $analyzerRelativePath; status = 'supported_static'; semantics = @('scoped direct-child sibling context', 'first-child', 'last-child', 'nth-child 1-based an+b', 'only-child') },
    [pscustomobject][ordered]@{ id = 'dom_matcher'; path = $elementRelativePath; status = 'supported_static'; semantics = @('standard child pseudo classes') },
    [pscustomobject][ordered]@{ id = 'arkweb_native_selector'; path = $runtimeRelativePath; status = 'supported_static'; semantics = @('browser querySelectorAll standard CSS child pseudos') }
  )
  assertions = $script:assertions
  checks = $script:checks.ToArray()
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_current_head_static_audit_only;runtime_build_device_and_legado_diff_deferred_to_R4'
  nextGate = 'R4 must execute the direct-child fixture, all six standard pseudo cases, affected sources and fixed-Legado differential.'
}
Write-AtomicJson $CurrentHeadAuditPath $currentHead

$sourceFix = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'source_fix'
  issueId = $issueId
  status = 'source_closed_static_only'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  supersedes = 'tools/legado-compat/evidence/v2-jsoup-standard-pseudo-selector-source-fix-20260809.json'
  rootCause = [pscustomobject][ordered]@{ category = '规则解析或编译'; originalSemantics = 'Pinned Legado AnalyzeByJSoup delegates CSS selection to Jsoup Element.select; direct child selectors and standard child pseudos share the parent element sibling context.'; v2BeforeFix = 'The string fallback evaluated each direct child in isolation, so filterElementsByStandardChildPseudo could not recover its parent or sibling position and returned no standard-pseudo matches.'; evidence = @($FailureWitnessPath, $PreviousPostFixContractPath) }
  changedPaths = @($analyzerRelativePath)
  change = 'Evaluate direct-child selectors inside a synthetic scoped parent, map matched elements by occurrence offset, and project only direct-child occurrences. This preserves sibling context and duplicate sibling identity without changing DOM or ArkWeb paths.'
  fixturePath = $FixturePath
  failureEvidence = @($FailureWitnessPath)
  staticContract = $PostFixContractPath
  currentHeadAudit = $CurrentHeadAuditPath
  currentHeadHashes = $hashes
  assertions = $script:assertions
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_source_fix_static_only;243_verifying;R4_runtime_build_device_and_legado_diff_deferred'
  closeCondition = 'R4 must execute all six standard-pseudo cases, the four direct-child context cases, the 52-rule/21-source affected set, deterministic 458-source Harness, fixed-Legado differential, build and device gates before 243 can leave verifying.'
}
Write-AtomicJson $SourceFixPath $sourceFix

Update-ObjectivePointer
$updateScript = Get-RepoPath 'tools/legado-compat/Update-LegadoGovernanceState.ps1'
$evidence = @($FixturePath, $FailureWitnessPath, $PostFixContractPath, $CurrentHeadAuditPath, $SourceFixPath, $analyzerRelativePath, $elementRelativePath, $runtimeRelativePath, $legadoRelativePath)
$summary = '243 direct-child CSS pseudo sibling context is statically closed: the large-document fallback now evaluates child selectors in a scoped parent and projects occurrence offsets; the previous 52-rule/21-source static closure remains preserved. R4 deferred.'
$closeCondition = [string]$sourceFix.closeCondition
$evidenceArgument = [string]::Join(',', $evidence)
$updateOutput = & pwsh -NoLogo -NoProfile -NonInteractive -File $updateScript -IssueId $issueId -IssueStatus verifying -TaskId $taskId -TaskStatus running -Summary $summary -CloseCondition $closeCondition -EvidencePath $evidenceArgument 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { throw "Update-LegadoGovernanceState failed:`n$updateOutput" }

$result = [pscustomobject][ordered]@{
  status = 'registered'
  issueId = $issueId
  sourceFixEvidencePath = $SourceFixPath
  currentHeadAuditPath = $CurrentHeadAuditPath
  directChildContractPath = $PostFixContractPath
  assertions = $script:assertions
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  governanceUpdate = $updateOutput.Trim()
}
$result | ConvertTo-Json -Depth 80
