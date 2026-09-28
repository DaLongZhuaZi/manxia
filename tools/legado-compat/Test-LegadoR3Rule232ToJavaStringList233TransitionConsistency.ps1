[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$RunId = 'r3-rule-232-to-java-233-pre-transition-20260808',
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
$evidenceFullPath = [System.IO.Path]::GetFullPath($evidenceRoot).TrimEnd('\') + '\'
if (-not $outputFullPath.StartsWith($evidenceFullPath, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw 'transition evidence must remain under the evidence directory.'
}

$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$script:assertions = 0
$script:checks = New-Object 'System.Collections.Generic.List[object]'

function Assert-Gate {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "232 to 233 transition blocked: $Message" }
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
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "missing JSON: $Path" }
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $Path" }
  try { return ($strictUtf8.GetString($bytes) | ConvertFrom-Json) } catch { throw "invalid JSON: $Path; $($_.Exception.Message)" }
}

function Read-StrictText {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "missing text: $Path" }
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $Path" }
  return $strictUtf8.GetString($bytes)
}

function Get-Issue {
  param([object[]]$Issues, [string]$Id)
  foreach ($issue in $Issues) { if ([string]$issue.id -eq $Id) { return $issue } }
  return $null
}

function Contains-Evidence {
  param([object]$Issue, [string]$Path)
  foreach ($value in @($Issue.evidencePaths)) { if ([string]$value -eq $Path) { return $true } }
  return $false
}

function Write-AtomicJson {
  param([string]$Path, [object]$Value)
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporaryPath = "$Path.tmp-$PID"
  [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 28), [System.Text.UTF8Encoding]::new($false))
  Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
}

$result = $null
$exitCode = 0
try {
  $state = Read-StrictJson -Path (Join-Path $RepositoryRoot 'tools\legado-compat\state\full-source-validation-state.json')
  $objective = Read-StrictJson -Path (Join-Path $RepositoryRoot 'tools\legado-compat\state\refactor-objective.json')
  $transition012 = Read-StrictJson -Path (Join-Path $evidenceRoot 'r3-image-012-to-rule-232-post-transition-20260808\transition-consistency.json')
  $pre232 = Read-StrictJson -Path (Join-Path $evidenceRoot 'contract-legado-rule-composition-pre-fix-20260808.json')
  $source232 = Read-StrictJson -Path (Join-Path $evidenceRoot 'v2-rule-composition-first-operator-source-fix-20260807.json')
  $mixed232 = Read-StrictJson -Path (Join-Path $evidenceRoot 'contract-legado-rule-composition-mixed.json')
  $embedded232 = Read-StrictJson -Path (Join-Path $evidenceRoot 'legado-rule-composition-embedded-runtime-contract-20260807.json')
  $head232 = Read-StrictJson -Path (Join-Path $evidenceRoot 'v2-rule-composition-current-head-audit-20260808-r1.json')
  $pre233 = Read-StrictJson -Path (Join-Path $evidenceRoot 'contract-legado-java-string-list-css-composition-pre-fix-20260808.json')
  $source233 = Read-StrictJson -Path (Join-Path $evidenceRoot 'v2-java-string-list-css-composition-source-fix-20260807.json')
  $contract233 = Read-StrictJson -Path (Join-Path $evidenceRoot 'contract-legado-java-string-list-css-composition.json')
  $embedded233 = Read-StrictJson -Path (Join-Path $evidenceRoot 'legado-java-string-list-css-composition-embedded-runtime-contract-20260807.json')
  $replacementPre233 = Read-StrictJson -Path (Join-Path $evidenceRoot 'contract-legado-java-string-list-css-replacement-order-pre-fix-20260808.json')
  $replacementContract233 = Read-StrictJson -Path (Join-Path $evidenceRoot 'contract-legado-java-string-list-css-replacement-order-20260808.json')
  $replacementSource233 = Read-StrictJson -Path (Join-Path $evidenceRoot 'v2-java-string-list-css-replacement-order-source-fix-20260808.json')
  $replacementHead233 = Read-StrictJson -Path (Join-Path $evidenceRoot 'v2-java-string-list-css-replacement-order-current-head-audit-20260808.json')

  $baseline = $state.baseline
  Assert-Gate ([int]$baseline.sourceCount -eq 458 -and [string]$baseline.sourcePackageSha256 -eq '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67' -and [string]$baseline.legadoCommit -eq '95973d186b147fb9ab43a9240021d688e4304fbd') 'machine baseline is not frozen.'
  Assert-Gate ([string]$state.governance.activeTaskId -eq 'COMPAT-006' -and [string]$state.governance.status -eq 'running') 'active governance task is not COMPAT-006/running.'
  $issue232 = Get-Issue -Issues @($state.governance.issues) -Id 'ISSUE-COMPAT-232-RULE-COMPOSITION-FIRST-OPERATOR'
  $issue233 = Get-Issue -Issues @($state.governance.issues) -Id 'ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION'
  Assert-Gate ($null -ne $issue232 -and [string]$issue232.status -eq 'verifying') '232 must remain verifying.'
  Assert-Gate ($null -ne $issue233 -and [string]$issue233.status -eq 'verifying') '233 must remain verifying.'

  if ($RequireRegistration) {
    Assert-Gate ([string]$state.governance.activeIssueId -eq 'ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION') 'post-transition active issue is not 233.'
    Assert-Gate ([string]$objective.authority.activeIssueId -eq 'ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION' -and [string]$objective.objective.activeIssue -eq 'ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION') 'post-transition objective is not on 233.'
    Assert-Gate ([string]$objective.objective.queueSelectionGate.currentAnchor -eq 'ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION') 'post-transition objective anchor is not 233.'
    Assert-Gate (@($objective.objective.queueSelectionGate.candidateIssues) -contains 'ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR') '234 is not registered as the next candidate.'
  } else {
    Assert-Gate ([string]$state.governance.activeIssueId -eq 'ISSUE-COMPAT-232-RULE-COMPOSITION-FIRST-OPERATOR') 'pre-transition active issue must remain 232.'
    Assert-Gate ([string]$objective.authority.activeIssueId -eq 'ISSUE-COMPAT-232-RULE-COMPOSITION-FIRST-OPERATOR' -and [string]$objective.objective.activeIssue -eq 'ISSUE-COMPAT-232-RULE-COMPOSITION-FIRST-OPERATOR') 'pre-transition objective is not on 232.'
    Assert-Gate ([string]$objective.objective.queueSelectionGate.currentAnchor -eq 'ISSUE-COMPAT-232-RULE-COMPOSITION-FIRST-OPERATOR') 'pre-transition objective anchor is not 232.'
    Assert-Gate (@($objective.objective.queueSelectionGate.candidateIssues) -contains 'ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION') '233 is not registered as the next candidate.'
  }
  Add-Check -Id 'queue_precondition' -Detail '232 is the only active source issue before transition; 233 is the only selected candidate.' -Evidence @('tools/legado-compat/state/full-source-validation-state.json','tools/legado-compat/state/refactor-objective.json')

  Assert-Gate ([string]$transition012.status -eq 'passed' -and -not [bool]$transition012.semanticMatchAllowed -and @($transition012.runtimeActionsPerformed).Count -eq 0) '012→232 transition is not static-only passed.'
  Assert-Gate ([string]$pre232.status -eq 'failed' -and @($pre232.failingCases).Count -eq 5 -and -not [bool]$pre232.semanticMatchAllowed) '232 failed-before contract is incomplete.'
  Assert-Gate ([string]$source232.status -eq 'source_fix_applied_pending_verification' -and -not [bool]$source232.semanticMatchAllowed) '232 source-fix evidence is incomplete.'
  Assert-Gate ([string]$mixed232.status -eq 'passed' -and [int]$mixed232.assertions -eq 10) '232 mixed static contract is incomplete.'
  Assert-Gate ([string]$embedded232.status -eq 'passed' -and [int]$embedded232.assertions -eq 12) '232 embedded static contract is incomplete.'
  Assert-Gate ([string]$head232.status -eq 'passed' -and [int]$head232.assertions -eq 40 -and -not [bool]$head232.semanticMatchAllowed -and @($head232.runtimeActionsPerformed).Count -eq 0) '232 current-head audit is incomplete.'
  Add-Check -Id 'rule_232_static_closure' -Detail '232 has failure, source-fix, 10+12 contracts, 40-assertion current-head audit and the previous static transition gate.' -Evidence @('tools/legado-compat/evidence/contract-legado-rule-composition-pre-fix-20260808.json','tools/legado-compat/evidence/v2-rule-composition-first-operator-source-fix-20260807.json','tools/legado-compat/evidence/contract-legado-rule-composition-mixed.json','tools/legado-compat/evidence/legado-rule-composition-embedded-runtime-contract-20260807.json','tools/legado-compat/evidence/v2-rule-composition-current-head-audit-20260808-r1.json')

  Assert-Gate ([string]$pre233.status -eq 'failed' -and @($pre233.failingCases).Count -eq 5 -and -not [bool]$pre233.semanticMatchAllowed -and @($pre233.runtimeActionsPerformed).Count -eq 0) '233 failed-before contract is incomplete.'
  Assert-Gate ([string]$source233.status -eq 'source_fix_applied_pending_verification' -and -not [bool]$source233.semanticMatchAllowed) '233 source-fix evidence is incomplete.'
  Assert-Gate ([string]$contract233.status -eq 'passed' -and [int]$contract233.assertions -eq 12) '233 ArkWeb static contract is incomplete.'
  Assert-Gate ([string]$embedded233.status -eq 'passed' -and [int]$embedded233.assertions -eq 19) '233 embedded static contract is incomplete.'
  Assert-Gate ([string]$replacementPre233.status -eq 'failed' -and @($replacementPre233.mismatches).Count -eq 2 -and -not [bool]$replacementPre233.semanticMatchAllowed -and @($replacementPre233.runtimeActionsPerformed).Count -eq 0) '233 replacement-order failed-before witness is incomplete.'
  Assert-Gate ([string]$replacementContract233.status -eq 'passed' -and [int]$replacementContract233.assertions -eq 14 -and -not [bool]$replacementContract233.semanticMatchAllowed) '233 replacement-order static contract is incomplete.'
  Assert-Gate ([string]$replacementSource233.status -eq 'source_fix_applied_pending_verification' -and -not [bool]$replacementSource233.semanticMatchAllowed) '233 replacement-order source-fix evidence is incomplete.'
  Assert-Gate ([string]$replacementHead233.status -eq 'current_head_bound_static_closure' -and -not [bool]$replacementHead233.semanticMatchAllowed -and @($replacementHead233.runtimeActionsPerformed).Count -eq 0) '233 replacement-order current-head audit is incomplete.'
  foreach ($path in @(
      'tools/legado-compat/evidence/contract-legado-java-string-list-css-composition-pre-fix-20260808.json',
      'tools/legado-compat/evidence/v2-java-string-list-css-composition-source-fix-20260807.json',
      'tools/legado-compat/evidence/contract-legado-java-string-list-css-composition.json',
      'tools/legado-compat/evidence/legado-java-string-list-css-composition-embedded-runtime-contract-20260807.json',
      'tools/legado-compat/evidence/contract-legado-java-string-list-css-replacement-order-pre-fix-20260808.json',
      'tools/legado-compat/evidence/contract-legado-java-string-list-css-replacement-order-20260808.json',
      'tools/legado-compat/evidence/v2-java-string-list-css-replacement-order-source-fix-20260808.json',
      'tools/legado-compat/evidence/v2-java-string-list-css-replacement-order-current-head-audit-20260808.json')) {
    Assert-Gate (Contains-Evidence -Issue $issue233 -Path $path) ("233 evidence is not registered: {0}" -f $path)
  }
  Add-Check -Id 'rule_233_candidate_chain' -Detail '233 has composition and replacement-order failed-before witnesses, source-fix evidence and 12+19+14 static contracts; runtime remains deferred.' -Evidence @('tools/legado-compat/evidence/contract-legado-java-string-list-css-composition-pre-fix-20260808.json','tools/legado-compat/evidence/v2-java-string-list-css-composition-source-fix-20260807.json','tools/legado-compat/evidence/contract-legado-java-string-list-css-composition.json','tools/legado-compat/evidence/legado-java-string-list-css-composition-embedded-runtime-contract-20260807.json','tools/legado-compat/evidence/contract-legado-java-string-list-css-replacement-order-pre-fix-20260808.json','tools/legado-compat/evidence/contract-legado-java-string-list-css-replacement-order-20260808.json','tools/legado-compat/evidence/v2-java-string-list-css-replacement-order-source-fix-20260808.json','tools/legado-compat/evidence/v2-java-string-list-css-replacement-order-current-head-audit-20260808.json')

  $objectiveDocument = Read-StrictText -Path (Join-Path $RepositoryRoot 'docs\analysis\Legado书源V2源码重构持续目标.md')
  $governanceDocument = Read-StrictText -Path (Join-Path $RepositoryRoot 'tools\legado-compat\LEGADO_V2_GOVERNANCE_TASKS.md')
  Assert-Gate ($objectiveDocument.Contains('ISSUE-COMPAT-232-RULE-COMPOSITION-FIRST-OPERATOR') -and $objectiveDocument.Contains('ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION') -and $objectiveDocument.Contains('contract-legado-java-string-list-css-composition-pre-fix-20260808.json') -and $objectiveDocument.Contains('contract-legado-java-string-list-css-replacement-order-pre-fix-20260808.json')) 'objective document does not retain the 232/233 boundary and 233 failure evidence.'
  if ($RequireRegistration) {
    Assert-Gate ($governanceDocument.Contains('activeIssue=`ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION`')) 'governance mirror does not select 233 after registration.'
  } else {
    Assert-Gate ($governanceDocument.Contains('activeIssue=`ISSUE-COMPAT-232-RULE-COMPOSITION-FIRST-OPERATOR`')) 'governance mirror must keep 232 before registration.'
  }
  Add-Check -Id 'document_binding' -Detail 'Objective and governance mirror retain one active issue, the next candidate and static-only verification.' -Evidence @('docs/analysis/Legado书源V2源码重构持续目标.md','tools/legado-compat/LEGADO_V2_GOVERNANCE_TASKS.md')

  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_r3_rule_232_to_java_string_list_233_transition_consistency'
    status = 'passed'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    objectiveId = [string]$objective.objectiveId
    targetRevision = [string]$objective.targetRevision
    transition = [pscustomobject][ordered]@{
      fromIssue = 'ISSUE-COMPAT-232-RULE-COMPOSITION-FIRST-OPERATOR'
      fromStatus = 'verifying'
      toIssue = 'ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION'
      toStatus = 'verifying'
      nextCandidate = 'ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR'
      runtimeVerification = 'deferred_to_R4'
    }
    baseline = [pscustomobject][ordered]@{ sourceCount = [int]$baseline.sourceCount; sourcePackageSha256 = [string]$baseline.sourcePackageSha256; legadoCommit = [string]$baseline.legadoCommit }
    assertions = $script:assertions
    checks = $script:checks.ToArray()
    evidencePaths = @('tools/legado-compat/evidence/contract-legado-java-string-list-css-composition-pre-fix-20260808.json','tools/legado-compat/evidence/v2-java-string-list-css-composition-source-fix-20260807.json','tools/legado-compat/evidence/contract-legado-java-string-list-css-replacement-order-pre-fix-20260808.json','tools/legado-compat/evidence/contract-legado-java-string-list-css-replacement-order-20260808.json','tools/legado-compat/evidence/v2-java-string-list-css-replacement-order-source-fix-20260808.json','tools/legado-compat/evidence/v2-java-string-list-css-replacement-order-current-head-audit-20260808.json')
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_rule_232_to_233_static_transition_only;R4_runtime_build_device_and_legado_diff_deferred'
    registrationRequired = (-not $RequireRegistration)
  }
} catch {
  $exitCode = 1
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_r3_rule_232_to_java_string_list_233_transition_consistency'
    status = 'failed'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    failure = $_.Exception.Message
    assertions = $script:assertions
    checks = $script:checks.ToArray()
    evidencePaths = @()
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_rule_232_to_233_static_transition_only;R4_runtime_build_device_and_legado_diff_deferred'
    registrationRequired = (-not $RequireRegistration)
  }
}

Write-AtomicJson -Path $OutputPath -Value $result
$result | ConvertTo-Json -Depth 28
if ($exitCode -ne 0) { exit $exitCode }
