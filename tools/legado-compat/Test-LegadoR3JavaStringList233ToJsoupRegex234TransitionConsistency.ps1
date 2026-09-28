[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$RunId = 'r3-java-string-list-233-to-jsoup-regex-234-pre-transition-20260808',
  [string]$OutputPath = '',
  [switch]$RequireRegistration
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

function Get-PropertyValue {
  param([object]$Object, [string]$Name, [object]$Default = $null)
  if ($null -eq $Object) { return $Default }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property -or $null -eq $property.Value) { return $Default }
  return $property.Value
}

function Assert-Gate {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "233 to 234 transition blocked: $Message" }
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

function Read-StrictJson {
  param([string]$RelativePath)
  $path = Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "required JSON is missing: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw "UTF-8 BOM is not allowed: $RelativePath"
  }
  try { return ($strictUtf8.GetString($bytes) | ConvertFrom-Json) }
  catch { throw "invalid JSON: $RelativePath; $($_.Exception.Message)" }
}

function Read-StrictText {
  param([string]$RelativePath)
  $path = Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
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
    if ([string](Get-PropertyValue $issue 'id') -eq $Id) { return $issue }
  }
  return $null
}

function Contains-Evidence {
  param([object]$Issue, [string]$Path)
  foreach ($value in @((Get-PropertyValue $Issue 'evidencePaths' @()))) {
    if ([string]$value -eq $Path) { return $true }
  }
  return $false
}

function Write-AtomicJson {
  param([string]$Path, [object]$Value)
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporaryPath = "$Path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 32), [System.Text.UTF8Encoding]::new($false))
  Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
}

$result = $null
$exitCode = 0
try {
  $state = Read-StrictJson -RelativePath 'tools/legado-compat/state/full-source-validation-state.json'
  $objective = Read-StrictJson -RelativePath 'tools/legado-compat/state/refactor-objective.json'
  $previousTransition = Read-StrictJson -RelativePath 'tools/legado-compat/evidence/r3-rule-232-to-java-233-post-transition-20260808/transition-consistency.json'

  $pre233 = Read-StrictJson -RelativePath 'tools/legado-compat/evidence/contract-legado-java-string-list-css-composition-pre-fix-20260808.json'
  $source233 = Read-StrictJson -RelativePath 'tools/legado-compat/evidence/v2-java-string-list-css-composition-source-fix-20260807.json'
  $contract233 = Read-StrictJson -RelativePath 'tools/legado-compat/evidence/contract-legado-java-string-list-css-composition.json'
  $embedded233 = Read-StrictJson -RelativePath 'tools/legado-compat/evidence/legado-java-string-list-css-composition-embedded-runtime-contract-20260807.json'
  $replacementPre233 = Read-StrictJson -RelativePath 'tools/legado-compat/evidence/contract-legado-java-string-list-css-replacement-order-pre-fix-20260808.json'
  $replacementContract233 = Read-StrictJson -RelativePath 'tools/legado-compat/evidence/contract-legado-java-string-list-css-replacement-order-20260808.json'
  $replacementSource233 = Read-StrictJson -RelativePath 'tools/legado-compat/evidence/v2-java-string-list-css-replacement-order-source-fix-20260808.json'
  $replacementHead233 = Read-StrictJson -RelativePath 'tools/legado-compat/evidence/v2-java-string-list-css-replacement-order-current-head-audit-20260808.json'

  $pre234 = Read-StrictJson -RelativePath 'tools/legado-compat/evidence/contract-legado-jsoup-regex-attribute-selector-pre-fix-20260808.json'
  $source234 = Read-StrictJson -RelativePath 'tools/legado-compat/evidence/v2-jsoup-regex-attribute-selector-source-fix-20260807.json'
  $contract234 = Read-StrictJson -RelativePath 'tools/legado-compat/evidence/contract-legado-jsoup-regex-attribute-selector.json'
  $head234 = Read-StrictJson -RelativePath 'tools/legado-compat/evidence/v2-jsoup-regex-attribute-selector-current-head-audit-20260808.json'
  $fixture234 = Read-StrictJson -RelativePath 'tools/legado-compat/fixtures/legado-jsoup-regex-attribute-selector.json'

  $baseline = $state.baseline
  Assert-Gate ([int]$baseline.sourceCount -eq 458 -and
    [string]$baseline.sourcePackageSha256 -eq '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67' -and
    [string]$baseline.legadoCommit -eq '95973d186b147fb9ab43a9240021d688e4304fbd') 'machine baseline is not frozen.'
  Assert-Gate ([string]$state.governance.activeTaskId -eq 'COMPAT-006' -and [string]$state.governance.status -eq 'running') 'active governance task is not COMPAT-006/running.'

  $issue233 = Get-Issue -Issues @($state.governance.issues) -Id 'ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION'
  $issue234 = Get-Issue -Issues @($state.governance.issues) -Id 'ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR'
  $issue235 = Get-Issue -Issues @($state.governance.issues) -Id 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS'
  Assert-Gate ($null -ne $issue233 -and [string]$issue233.status -eq 'verifying') '233 must remain verifying.'
  Assert-Gate ($null -ne $issue234 -and [string]$issue234.status -eq 'verifying') '234 must remain verifying during static transition.'
  Assert-Gate ($null -ne $issue235 -and [string]$issue235.status -eq 'verifying') '235 must be available as the next candidate.'

  $activeIssue = [string]$state.governance.activeIssueId
  if ($RequireRegistration) {
    Assert-Gate ($activeIssue -eq 'ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR') 'post-registration active issue is not 234.'
    Assert-Gate ([string]$objective.authority.activeIssueId -eq $activeIssue -and [string]$objective.objective.activeIssue -eq $activeIssue -and [string]$objective.executionTarget.currentIssue -eq $activeIssue) 'post-registration objective is not on 234.'
    Assert-Gate (@($objective.objective.queueSelectionGate.candidateIssues) -contains 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS' -and @($objective.executionTarget.nextIssues) -contains 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS') '235 is not the post-registration candidate.'
  } else {
    Assert-Gate ($activeIssue -eq 'ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION') 'pre-registration active issue must remain 233.'
    Assert-Gate ([string]$objective.authority.activeIssueId -eq $activeIssue -and [string]$objective.objective.activeIssue -eq $activeIssue -and [string]$objective.executionTarget.currentIssue -eq $activeIssue) 'pre-registration objective is not on 233.'
    Assert-Gate (@($objective.objective.queueSelectionGate.candidateIssues) -contains 'ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR' -and @($objective.executionTarget.nextIssues) -contains 'ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR') '234 is not the pre-registration candidate.'
  }
  Add-Check -Id 'queue_precondition' -Detail 'The machine queue contains one active issue; 233 remains verifying and 234/235 are ordered candidates.' -Evidence @('tools/legado-compat/state/full-source-validation-state.json','tools/legado-compat/state/refactor-objective.json')

  Assert-Gate ([string]$previousTransition.status -eq 'passed' -and [int]$previousTransition.assertions -eq 32 -and
    [string]$previousTransition.transition.toIssue -eq 'ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION' -and
    [string]$previousTransition.transition.nextCandidate -eq 'ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR' -and
    -not [bool]$previousTransition.semanticMatchAllowed -and @($previousTransition.runtimeActionsPerformed).Count -eq 0) '232→233 predecessor gate is not a 32-assertion static-only pass.'

  Assert-Gate ([string]$pre233.status -eq 'failed' -and @($pre233.failingCases).Count -eq 5 -and -not [bool]$pre233.semanticMatchAllowed -and @($pre233.runtimeActionsPerformed).Count -eq 0) '233 composition failed-before evidence is incomplete.'
  Assert-Gate ([string]$source233.status -eq 'source_fix_applied_pending_verification' -and -not [bool]$source233.semanticMatchAllowed) '233 composition source-fix evidence is incomplete.'
  Assert-Gate ([string]$contract233.status -eq 'passed' -and [int]$contract233.assertions -eq 12) '233 composition static contract is incomplete.'
  Assert-Gate ([string]$embedded233.status -eq 'passed' -and [int]$embedded233.assertions -eq 19) '233 embedded runtime contract is incomplete.'
  Assert-Gate ([string]$replacementPre233.status -eq 'failed' -and @($replacementPre233.mismatches).Count -eq 2 -and -not [bool]$replacementPre233.semanticMatchAllowed -and @($replacementPre233.runtimeActionsPerformed).Count -eq 0) '233 replacement-order failed-before evidence is incomplete.'
  Assert-Gate ([string]$replacementContract233.status -eq 'passed' -and [int]$replacementContract233.assertions -eq 14 -and -not [bool]$replacementContract233.semanticMatchAllowed) '233 replacement-order contract is incomplete.'
  Assert-Gate ([string]$replacementSource233.status -eq 'source_fix_applied_pending_verification' -and -not [bool]$replacementSource233.semanticMatchAllowed) '233 replacement-order source-fix evidence is incomplete.'
  Assert-Gate ([string]$replacementHead233.status -eq 'current_head_bound_static_closure' -and -not [bool]$replacementHead233.semanticMatchAllowed -and @($replacementHead233.runtimeActionsPerformed).Count -eq 0) '233 replacement-order current-head audit is incomplete.'
  Add-Check -Id 'issue_233_static_closure' -Detail '233 retains both failed-before witnesses, source-fix evidence, 12+19+14 static contracts and current-head binding.' -Evidence @('tools/legado-compat/evidence/contract-legado-java-string-list-css-composition-pre-fix-20260808.json','tools/legado-compat/evidence/v2-java-string-list-css-composition-source-fix-20260807.json','tools/legado-compat/evidence/contract-legado-java-string-list-css-composition.json','tools/legado-compat/evidence/legado-java-string-list-css-composition-embedded-runtime-contract-20260807.json','tools/legado-compat/evidence/contract-legado-java-string-list-css-replacement-order-pre-fix-20260808.json','tools/legado-compat/evidence/contract-legado-java-string-list-css-replacement-order-20260808.json','tools/legado-compat/evidence/v2-java-string-list-css-replacement-order-source-fix-20260808.json','tools/legado-compat/evidence/v2-java-string-list-css-replacement-order-current-head-audit-20260808.json')

  Assert-Gate ([string]$pre234.status -eq 'failed' -and @($pre234.failingCases).Count -eq 5 -and -not [bool]$pre234.semanticMatchAllowed -and @($pre234.runtimeActionsPerformed).Count -eq 0) '234 failed-before evidence is incomplete.'
  Assert-Gate ([string]$source234.status -eq 'verifying' -and [string]$source234.verification.staticContractStatus -eq 'passed' -and [int]$source234.verification.staticContractAssertions -eq 13 -and [string]$source234.verification.runtimeRegression -eq 'deferred_by_user' -and [string]$source234.verification.legadoDifferential -eq 'deferred_by_user') '234 source-fix evidence is not static-only verifying.'
  Assert-Gate ([string]$contract234.status -eq 'passed' -and [int]$contract234.assertions -eq 13 -and [string]$contract234.verification -match 'static_source_contract_only') '234 static contract is incomplete or lacks deferred-runtime declaration.'
  Assert-Gate ([string]$head234.status -eq 'current_head_bound_static_closure' -and -not [bool]$head234.semanticMatchAllowed -and @($head234.runtimeActionsPerformed).Count -eq 0) '234 current-head audit is incomplete.'
  Assert-Gate ([int]$head234.impact.attributeRegexRuleStringCount -eq 139 -and [int]$head234.impact.affectedSourceCountLowerBound -eq 51 -and [int]$head234.impact.javaInlineRegexFlagRuleValueCount -eq 4 -and [int]$head234.impact.javaInlineRegexFlagAffectedSourceCount -eq 2) '234 impact matrix is not bound to 139/51/4/2.'
  Assert-Gate (@($fixture234.cases).Count -eq 7) '234 fixture does not contain seven deterministic cases.'
  Add-Check -Id 'issue_234_static_readiness' -Detail '234 has a failed-before witness, verifying source-fix, 13-assertion contract, 139/51/4/2 impact and current-head static audit.' -Evidence @('tools/legado-compat/evidence/contract-legado-jsoup-regex-attribute-selector-pre-fix-20260808.json','tools/legado-compat/evidence/v2-jsoup-regex-attribute-selector-source-fix-20260807.json','tools/legado-compat/evidence/contract-legado-jsoup-regex-attribute-selector.json','tools/legado-compat/evidence/v2-jsoup-regex-attribute-selector-current-head-audit-20260808.json','tools/legado-compat/fixtures/legado-jsoup-regex-attribute-selector.json')

  $objectiveText = Read-StrictText -RelativePath 'docs/analysis/Legado书源V2源码重构持续目标.md'
  $governanceText = Read-StrictText -RelativePath 'tools/legado-compat/LEGADO_V2_GOVERNANCE_TASKS.md'
  Assert-Gate ($objectiveText.Contains([string]$objective.targetRevision) -and $objectiveText.Contains('ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION') -and $objectiveText.Contains('ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR') -and $objectiveText.Contains('R4')) 'objective document is not bound to the current queue and deferred R4.'
  if ($RequireRegistration) {
    Assert-Gate ($governanceText.Contains('activeIssue=`ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR`') -and $governanceText.Contains('| issue | ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR | verifying |')) 'post-registration governance mirror does not select 234.'
  } else {
    Assert-Gate ($governanceText.Contains('activeIssue=`ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION`') -and $governanceText.Contains('| issue | ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR | verifying |')) 'pre-registration governance mirror does not retain 233→234.'
  }
  Add-Check -Id 'document_binding' -Detail 'Objective and governance documents preserve the one-issue queue and static-only R4 boundary.' -Evidence @('docs/analysis/Legado书源V2源码重构持续目标.md','tools/legado-compat/LEGADO_V2_GOVERNANCE_TASKS.md')

  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_r3_java_string_list_233_to_jsoup_regex_234_transition_consistency'
    status = 'passed'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    objectiveId = [string]$objective.objectiveId
    targetRevision = [string]$objective.targetRevision
    transition = [pscustomobject][ordered]@{
      fromIssue = 'ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION'
      fromStatus = 'verifying'
      toIssue = 'ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR'
      toStatus = 'verifying'
      nextCandidate = 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS'
      runtimeVerification = 'deferred_to_R4'
    }
    baseline = [pscustomobject][ordered]@{ sourceCount = [int]$baseline.sourceCount; sourcePackageSha256 = [string]$baseline.sourcePackageSha256; legadoCommit = [string]$baseline.legadoCommit }
    assertions = $script:assertions
    checks = $script:checks.ToArray()
    evidencePaths = @('tools/legado-compat/evidence/r3-rule-232-to-java-233-post-transition-20260808/transition-consistency.json','tools/legado-compat/evidence/contract-legado-java-string-list-css-composition-pre-fix-20260808.json','tools/legado-compat/evidence/v2-java-string-list-css-composition-source-fix-20260807.json','tools/legado-compat/evidence/contract-legado-java-string-list-css-composition.json','tools/legado-compat/evidence/legado-java-string-list-css-composition-embedded-runtime-contract-20260807.json','tools/legado-compat/evidence/contract-legado-java-string-list-css-replacement-order-pre-fix-20260808.json','tools/legado-compat/evidence/contract-legado-java-string-list-css-replacement-order-20260808.json','tools/legado-compat/evidence/v2-java-string-list-css-replacement-order-source-fix-20260808.json','tools/legado-compat/evidence/v2-java-string-list-css-replacement-order-current-head-audit-20260808.json','tools/legado-compat/evidence/contract-legado-jsoup-regex-attribute-selector-pre-fix-20260808.json','tools/legado-compat/evidence/v2-jsoup-regex-attribute-selector-source-fix-20260807.json','tools/legado-compat/evidence/contract-legado-jsoup-regex-attribute-selector.json','tools/legado-compat/evidence/v2-jsoup-regex-attribute-selector-current-head-audit-20260808.json')
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_233_to_234_static_transition_only;R4_runtime_build_device_and_legado_diff_deferred'
    registrationRequired = (-not $RequireRegistration)
  }
} catch {
  $exitCode = 1
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_r3_java_string_list_233_to_jsoup_regex_234_transition_consistency'
    status = 'failed'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    failure = $_.Exception.Message
    assertions = $script:assertions
    checks = $script:checks.ToArray()
    evidencePaths = @()
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_233_to_234_static_transition_only;R4_runtime_build_device_and_legado_diff_deferred'
    registrationRequired = (-not $RequireRegistration)
  }
}

Write-AtomicJson -Path $OutputPath -Value $result
$result | ConvertTo-Json -Depth 32
if ($exitCode -ne 0) { exit $exitCode }
