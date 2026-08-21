[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$RunId = 'r3-jsoup-regex-234-to-text-pseudo-235-transition-20260809',
  [string]$OutputPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$evidenceRoot = Join-Path $RepositoryRoot 'tools\legado-compat\evidence'
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = Join-Path $evidenceRoot (Join-Path $RunId 'transition-consistency.json')
}
$outputFullPath = [System.IO.Path]::GetFullPath($OutputPath)
$evidencePrefix = [System.IO.Path]::GetFullPath($evidenceRoot).TrimEnd('\') + '\'
if (-not $outputFullPath.StartsWith($evidencePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw 'transition evidence must remain under the evidence directory.'
}

$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$script:assertions = 0
$script:checks = New-Object 'System.Collections.Generic.List[object]'

function Get-RepoPath {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Get-PropertyValue {
  param([object]$Object, [string]$Name, [object]$Default = $null)
  if ($null -eq $Object) { return $Default }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property -or $null -eq $property.Value) { return $Default }
  return $property.Value
}

function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  $path = Get-RepoPath -RelativePath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "required JSON is missing: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw "UTF-8 BOM is not allowed: $RelativePath"
  }
  try { return ($strictUtf8.GetString($bytes) | ConvertFrom-Json) }
  catch { throw "invalid JSON: $RelativePath; $($_.Exception.Message)" }
}

function Read-StrictText {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  $path = Get-RepoPath -RelativePath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "required text is missing: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw "UTF-8 BOM is not allowed: $RelativePath"
  }
  return $strictUtf8.GetString($bytes)
}

function Get-Issue {
  param([object[]]$Issues, [string]$Id)
  foreach ($issue in $Issues) {
    if ([string](Get-PropertyValue -Object $issue -Name 'id') -eq $Id) { return $issue }
  }
  return $null
}

function Contains-Evidence {
  param([object]$Issue, [string]$Path)
  foreach ($value in @((Get-PropertyValue -Object $Issue -Name 'evidencePaths' -Default @()))) {
    if ([string]$value -eq $Path) { return $true }
  }
  return $false
}

function Assert-Gate {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "234 to 235 transition blocked: $Message" }
  $script:assertions++
}

function Add-Check {
  param([string]$Id, [string]$Detail, [string[]]$Evidence = @())
  [void]$script:checks.Add([pscustomobject][ordered]@{
      id = $Id
      status = 'passed'
      detail = $Detail
      evidencePaths = @($Evidence)
    })
}

function Get-RelativeSha256 {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  $path = Get-RepoPath -RelativePath $RelativePath
  return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Write-AtomicJson {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value)
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporaryPath = "$Path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 40), [System.Text.UTF8Encoding]::new($false))
  Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
}

$changedPaths = @(
  'entry/src/main/ets/libs/htmlparser/Matcher.ets',
  'entry/src/main/ets/libs/htmlparser/HTMLElement.ets',
  'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets',
  'entry/src/main/resources/rawfile/legado_runtime.html',
  'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
)
$result = $null
$exitCode = 0
try {
  $state = Read-StrictJson -RelativePath 'tools/legado-compat/state/full-source-validation-state.json'
  $objective = Read-StrictJson -RelativePath 'tools/legado-compat/state/refactor-objective.json'
  $target234 = Read-StrictJson -RelativePath 'tools/legado-compat/evidence/r3-actual-docs-source-refactor-target-20260809-234-nested-predicate/target.json'
  $contract234 = Read-StrictJson -RelativePath 'tools/legado-compat/evidence/contract-legado-jsoup-regex-attribute-nested-predicate-20260809.json'
  $sourceFix234 = Read-StrictJson -RelativePath 'tools/legado-compat/evidence/v2-jsoup-regex-attribute-nested-predicate-source-fix-20260809.json'
  $headContract234 = Read-StrictJson -RelativePath 'tools/legado-compat/evidence/r3-actual-docs-source-refactor-target-20260809-234-nested-predicate/current-head-static-contract-20260809.json'
  $fixture235 = Read-StrictJson -RelativePath 'tools/legado-compat/fixtures/legado-jsoup-text-pseudo-selectors.json'
  $contract235 = Read-StrictJson -RelativePath 'tools/legado-compat/evidence/contract-legado-jsoup-text-pseudo-selectors.json'
  $sourceFix235 = Read-StrictJson -RelativePath 'tools/legado-compat/evidence/v2-jsoup-text-pseudo-selectors-source-fix-20260807.json'

  $baseline = $state.baseline
  Assert-Gate ([int]$baseline.sourceCount -eq 458 -and
    [string]$baseline.sourcePackageSha256 -eq '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67' -and
    [string]$baseline.legadoCommit -eq '95973d186b147fb9ab43a9240021d688e4304fbd') 'machine baseline is not frozen.'
  Assert-Gate ([string]$state.governance.activeTaskId -eq 'COMPAT-006' -and [string]$state.governance.status -eq 'running') 'active governance task is not COMPAT-006/running.'

  $issues = @($state.governance.issues)
  $issue234 = Get-Issue -Issues $issues -Id 'ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR'
  $issue235 = Get-Issue -Issues $issues -Id 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS'
  $issue236 = Get-Issue -Issues $issues -Id 'ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR'
  Assert-Gate ($null -ne $issue234 -and [string]$issue234.status -eq 'verifying') '234 must remain verifying before transition.'
  Assert-Gate ($null -ne $issue235 -and [string]$issue235.status -eq 'verifying') '235 must be an existing static candidate.'
  Assert-Gate ($null -ne $issue236 -and [string]$issue236.status -eq 'verifying') '236 must remain the next ordered candidate.'
  Assert-Gate ([string]$state.governance.activeIssueId -eq 'ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR') '234 must remain the sole active issue before registration.'
  Add-Check -Id 'queue_precondition' -Detail '234 is the only active issue; 235 is the candidate and 236 remains ordered behind it.' -Evidence @('tools/legado-compat/state/full-source-validation-state.json','tools/legado-compat/state/refactor-objective.json')

  Assert-Gate ([string]$objective.targetRevision -eq '2026-08-09-actual-docs-source-refactor-continuation-jsoup-regex-234-nested-predicate-030') 'objective revision drifted from the current 234 closure target.'
  Assert-Gate ([string]$objective.objective.queueSelectionGate.status -eq 'issue_selected_r3_nested_predicate_boundary_closed') '234 boundary is not recorded as closed.'
  Assert-Gate ([string]$objective.objective.queueSelectionGate.currentAnchor -eq 'ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR' -and
    @($objective.objective.queueSelectionGate.candidateIssues) -contains 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS') 'objective queue does not preserve 234→235 ordering.'
  Assert-Gate ([string]$objective.continuationTarget.activeBoundary -match '234-NP-05.*已完成' -and [string]$objective.continuationTarget.nextTransition -match '234→235') 'objective does not record the completed 234 handoff.'

  Assert-Gate ([string]$target234.status -eq 'completed' -and [string]$target234.currentStage -match 'static_source_closure_complete') '234 target evidence is not statically complete.'
  Assert-Gate ([string]$contract234.status -eq 'passed' -and [int]$contract234.assertions -eq 38 -and -not [bool]$contract234.semanticMatchAllowed) '234 nested contract is not a 38-assertion static-only pass.'
  Assert-Gate ([string]$sourceFix234.status -eq 'passed' -and -not [bool]$sourceFix234.semanticMatchAllowed -and @($sourceFix234.runtimeActionsPerformed).Count -eq 0) '234 source-fix evidence is not static-only.'
  Assert-Gate ([string]$headContract234.status -eq 'passed' -and [int]$headContract234.assertions -eq 38 -and -not [bool]$headContract234.semanticMatchAllowed -and @($headContract234.runtimeActionsPerformed).Count -eq 0) '234 current-head static evidence is incomplete.'
  Add-Check -Id 'issue_234_closed_boundary' -Detail '234 nested predicate closure and document handoff are complete without runtime claims.' -Evidence @('tools/legado-compat/evidence/r3-actual-docs-source-refactor-target-20260809-234-nested-predicate/target.json','tools/legado-compat/evidence/contract-legado-jsoup-regex-attribute-nested-predicate-20260809.json','tools/legado-compat/evidence/v2-jsoup-regex-attribute-nested-predicate-source-fix-20260809.json','tools/legado-compat/evidence/r3-actual-docs-source-refactor-target-20260809-234-nested-predicate/current-head-static-contract-20260809.json')

  Assert-Gate ([string]$fixture235.contract -eq 'legado_jsoup_text_pseudo_selectors' -and @($fixture235.cases).Count -eq 8) '235 fixture contract or case count changed.'
  Assert-Gate (@($fixture235.cases | Where-Object { [string]$_.semantics -eq 'contains' }).Count -eq 2 -and
    @($fixture235.cases | Where-Object { [string]$_.semantics -eq 'containsOwn' }).Count -eq 1 -and
    @($fixture235.cases | Where-Object { [string]$_.semantics -eq 'matches' }).Count -eq 2 -and
    @($fixture235.cases | Where-Object { [string]$_.semantics -eq 'matchesOwn' }).Count -eq 1) '235 fixture does not cover the four Jsoup text pseudo families.'
  Assert-Gate ([string]$contract235.status -eq 'passed' -and [int]$contract235.assertions -eq 19 -and [string]$contract235.verification -match 'static_source_contract_only') '235 static contract is incomplete.'
  Assert-Gate ([string]$sourceFix235.status -eq 'verifying' -and [string]$sourceFix235.verification.staticContractStatus -eq 'passed' -and
    [string]$sourceFix235.verification.runtimeRegression -eq 'deferred_by_user' -and [string]$sourceFix235.verification.legadoDifferential -eq 'deferred_by_user') '235 source-fix evidence is not static-only verifying.'
  Assert-Gate ((Contains-Evidence -Issue $issue235 -Path 'tools/legado-compat/evidence/contract-legado-jsoup-text-pseudo-selectors.json') -and
    (Contains-Evidence -Issue $issue235 -Path 'tools/legado-compat/evidence/v2-jsoup-text-pseudo-selectors-source-fix-20260807.json')) '235 machine evidence registration is incomplete.'
  Add-Check -Id 'issue_235_candidate_contract' -Detail '235 has its independent fixture, 19-assertion contract and source-fix evidence; runtime remains deferred.' -Evidence @('tools/legado-compat/fixtures/legado-jsoup-text-pseudo-selectors.json','tools/legado-compat/evidence/contract-legado-jsoup-text-pseudo-selectors.json','tools/legado-compat/evidence/v2-jsoup-text-pseudo-selectors-source-fix-20260807.json')

  $sourceTexts = @{}
  foreach ($path in $changedPaths) { $sourceTexts[$path] = Read-StrictText -RelativePath $path }
  Assert-Gate ($sourceTexts['entry/src/main/ets/libs/htmlparser/Matcher.ets'].Contains('parsePseudoClass(selector, i)') -and
    $sourceTexts['entry/src/main/ets/libs/htmlparser/Matcher.ets'].Contains('characterClassDepth')) 'Matcher pseudo parser path is not current.'
  Assert-Gate ($sourceTexts['entry/src/main/ets/libs/htmlparser/HTMLElement.ets'].Contains("pseudo.name === 'contains'") -and
    $sourceTexts['entry/src/main/ets/libs/htmlparser/HTMLElement.ets'].Contains("pseudo.name === 'matchesown'")) 'DOM text pseudo implementation is not current.'
  Assert-Gate ($sourceTexts['entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'].Contains('parseLegadoPseudoSelectors') -and
    $sourceTexts['entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'].Contains('filterElementsByPseudoClasses')) 'string fallback text pseudo implementation is not current.'
  Assert-Gate ($sourceTexts['entry/src/main/resources/rawfile/legado_runtime.html'].Contains('legadoParseJsoupTextPseudos') -and
    $sourceTexts['entry/src/main/resources/rawfile/legado_runtime.html'].Contains('legadoMatchesJsoupPseudo') -and
    $sourceTexts['entry/src/main/resources/rawfile/legado_runtime.html'].Contains('legadoSplitSelectorGroups')) 'ArkWeb text pseudo implementation is not current.'
  Assert-Gate ($sourceTexts['legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'].Contains('element.select(ruleStrX.substring(0, lastIndex))')) 'fixed Legado selector handoff is not bound.'

  $currentHeadHashes = [ordered]@{}
  foreach ($path in $changedPaths) { $currentHeadHashes[$path] = Get-RelativeSha256 -RelativePath $path }
  $candidateHeadAudit = [pscustomobject][ordered]@{
    status = 'candidate_current_head_bound_static_closure'
    issueId = 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS'
    changedPaths = $changedPaths
    currentHeadHashes = $currentHeadHashes
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verification = 'current_head_hash_only;runtime_regression_and_legado_differential_deferred'
  }
  Add-Check -Id 'candidate_current_head_audit' -Detail 'All 235 consumer paths and the fixed Legado selector handoff are hash-bound at the current HEAD.' -Evidence $changedPaths

  $objectiveDocument = Read-StrictText -RelativePath 'docs/analysis/Legado书源V2源码重构持续目标.md'
  $governanceDocument = Read-StrictText -RelativePath 'tools/legado-compat/LEGADO_V2_GOVERNANCE_TASKS.md'
  Assert-Gate ($objectiveDocument.Contains([string]$objective.targetRevision) -and $objectiveDocument.Contains('234→235') -and $objectiveDocument.Contains('R4')) 'objective document is not bound to the current transition and deferred R4.'
  Assert-Gate ($governanceDocument.Contains('activeIssue=`ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR`') -and $governanceDocument.Contains('ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS')) 'governance document does not preserve the pre-registration queue.'
  Add-Check -Id 'document_binding' -Detail 'Objective and governance documents preserve the single active issue and deferred R4 boundary.' -Evidence @('docs/analysis/Legado书源V2源码重构持续目标.md','tools/legado-compat/LEGADO_V2_GOVERNANCE_TASKS.md')

  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_r3_jsoup_regex_234_to_text_pseudo_235_transition_consistency'
    status = 'passed'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    objectiveId = [string]$objective.objectiveId
    targetRevision = [string]$objective.targetRevision
    transition = [pscustomobject][ordered]@{
      fromIssue = 'ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR'
      fromStatus = 'verifying'
      toIssue = 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS'
      toStatus = 'verifying'
      currentActiveIssueBeforeRegistration = 'ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR'
      nextCandidateAfterRegistration = 'ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR'
      activation = 'registration_required_after_static_gate'
      runtimeVerification = 'deferred_to_R4'
    }
    baseline = [pscustomobject][ordered]@{
      sourceCount = [int]$baseline.sourceCount
      sourcePackageSha256 = [string]$baseline.sourcePackageSha256
      legadoCommit = [string]$baseline.legadoCommit
    }
    assertions = $script:assertions
    checks = $script:checks.ToArray()
    candidateCurrentHeadAudit = $candidateHeadAudit
    evidencePaths = @(
      'tools/legado-compat/state/full-source-validation-state.json',
      'tools/legado-compat/state/refactor-objective.json',
      'tools/legado-compat/evidence/r3-actual-docs-source-refactor-target-20260809-234-nested-predicate/target.json',
      'tools/legado-compat/evidence/contract-legado-jsoup-regex-attribute-nested-predicate-20260809.json',
      'tools/legado-compat/evidence/v2-jsoup-regex-attribute-nested-predicate-source-fix-20260809.json',
      'tools/legado-compat/evidence/r3-actual-docs-source-refactor-target-20260809-234-nested-predicate/current-head-static-contract-20260809.json',
      'tools/legado-compat/fixtures/legado-jsoup-text-pseudo-selectors.json',
      'tools/legado-compat/evidence/contract-legado-jsoup-text-pseudo-selectors.json',
      'tools/legado-compat/evidence/v2-jsoup-text-pseudo-selectors-source-fix-20260807.json'
    ) + $changedPaths
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_234_to_235_static_transition_only;235_not_activated_until_registration;R4_runtime_build_device_and_legado_diff_deferred'
    registrationRequired = $true
  }
} catch {
  $exitCode = 1
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_r3_jsoup_regex_234_to_text_pseudo_235_transition_consistency'
    status = 'failed'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    failure = $_.Exception.Message
    assertions = $script:assertions
    checks = $script:checks.ToArray()
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_234_to_235_static_transition_only;R4_runtime_build_device_and_legado_diff_deferred'
    registrationRequired = $true
  }
}

Write-AtomicJson -Path $outputFullPath -Value $result
$result | ConvertTo-Json -Depth 40
if ($exitCode -ne 0) { exit $exitCode }
