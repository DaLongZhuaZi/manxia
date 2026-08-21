[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$RunId = 'r3-image-012-to-rule-232-pre-transition-20260808',
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
if (-not $outputFullPath.StartsWith(([System.IO.Path]::GetFullPath($evidenceRoot).TrimEnd('\') + '\'), [System.StringComparison]::OrdinalIgnoreCase)) {
  throw 'transition evidence must remain under the evidence directory.'
}

$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$script:assertions = 0
$script:checks = New-Object 'System.Collections.Generic.List[object]'

function Assert-Gate {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "012 to 232 transition blocked: $Message" }
  $script:assertions++
}

function Add-Check {
  param([string]$Id, [string]$Detail, [string[]]$Evidence = @())
  [void]$script:checks.Add([pscustomobject][ordered]@{ id = $Id; status = 'passed'; detail = $Detail; evidencePaths = @($Evidence) })
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
  [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 24), [System.Text.UTF8Encoding]::new($false))
  Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
}

$result = $null
$exitCode = 0
try {
  $statePath = Join-Path $RepositoryRoot 'tools\legado-compat\state\full-source-validation-state.json'
  $objectivePath = Join-Path $RepositoryRoot 'tools\legado-compat\state\refactor-objective.json'
  $state = Read-StrictJson -Path $statePath
  $objective = Read-StrictJson -Path $objectivePath
  $transition012 = Read-StrictJson -Path (Join-Path $evidenceRoot 'r3-output-handoff-005-to-image-012-post-transition-20260808\transition-consistency.json')
  $preFix232 = Read-StrictJson -Path (Join-Path $evidenceRoot 'contract-legado-rule-composition-pre-fix-20260808.json')
  $mixed232 = Read-StrictJson -Path (Join-Path $evidenceRoot 'contract-legado-rule-composition-mixed.json')
  $embedded232 = Read-StrictJson -Path (Join-Path $evidenceRoot 'legado-rule-composition-embedded-runtime-contract-20260807.json')
  $head232 = Read-StrictJson -Path (Join-Path $evidenceRoot 'v2-rule-composition-current-head-audit-20260808-r1.json')
  $baseline = $state.baseline
  Assert-Gate ([int]$baseline.sourceCount -eq 458 -and [string]$baseline.sourcePackageSha256 -eq '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67' -and [string]$baseline.legadoCommit -eq '95973d186b147fb9ab43a9240021d688e4304fbd') 'machine baseline is not frozen.'
  Assert-Gate ([string]$state.governance.activeTaskId -eq 'COMPAT-006' -and [string]$state.governance.status -eq 'running') 'active governance task is not COMPAT-006/running.'
  $issue012 = Get-Issue -Issues @($state.governance.issues) -Id 'ISSUE-COMPAT-012'
  $issue232 = Get-Issue -Issues @($state.governance.issues) -Id 'ISSUE-COMPAT-232-RULE-COMPOSITION-FIRST-OPERATOR'
  Assert-Gate ($null -ne $issue012 -and [string]$issue012.status -eq 'verifying') '012 must remain verifying.'
  Assert-Gate ($null -ne $issue232 -and [string]$issue232.status -eq 'verifying') '232 must remain verifying.'

  if ($RequireRegistration) {
    Assert-Gate ([string]$state.governance.activeIssueId -eq 'ISSUE-COMPAT-232-RULE-COMPOSITION-FIRST-OPERATOR') 'post-transition active issue is not 232.'
    Assert-Gate ([string]$objective.authority.activeIssueId -eq 'ISSUE-COMPAT-232-RULE-COMPOSITION-FIRST-OPERATOR' -and [string]$objective.objective.activeIssue -eq 'ISSUE-COMPAT-232-RULE-COMPOSITION-FIRST-OPERATOR') 'post-transition objective is not on 232.'
  } else {
    Assert-Gate ([string]$state.governance.activeIssueId -eq 'ISSUE-COMPAT-012') 'pre-transition active issue must remain 012.'
    Assert-Gate ([string]$objective.authority.activeIssueId -eq 'ISSUE-COMPAT-012' -and [string]$objective.objective.activeIssue -eq 'ISSUE-COMPAT-012') 'pre-transition objective is not on 012.'
  }
  if ($RequireRegistration) {
    Assert-Gate ([string]$objective.objective.queueSelectionGate.currentAnchor -eq 'ISSUE-COMPAT-232-RULE-COMPOSITION-FIRST-OPERATOR') 'post-transition objective anchor is not 232.'
    Assert-Gate ([string]$objective.objective.queueSelectionGate.candidateIssues -contains 'ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION') '233 is not registered as the next candidate.'
  } else {
    Assert-Gate ([string]$objective.objective.queueSelectionGate.currentAnchor -eq 'ISSUE-COMPAT-012' -and [string]$objective.objective.queueSelectionGate.candidateIssues -contains 'ISSUE-COMPAT-232-RULE-COMPOSITION-FIRST-OPERATOR') '232 is not registered as the next candidate.'
  }
  Add-Check -Id 'queue_precondition' -Detail '012 remains static-only verifying and 232 is the only candidate under review.' -Evidence @('tools/legado-compat/state/full-source-validation-state.json','tools/legado-compat/state/refactor-objective.json')

  Assert-Gate ([string]$transition012.status -eq 'passed' -and -not [bool]$transition012.semanticMatchAllowed -and @($transition012.runtimeActionsPerformed).Count -eq 0) '012 transition evidence is not static-only passed.'
  Assert-Gate ([string]$preFix232.status -eq 'failed' -and [string]$preFix232.classification -eq 'historical_v2_fixed_priority_semantics' -and @($preFix232.failingCases).Count -eq 5) '232 failed-before contract is incomplete.'
  Assert-Gate ([string]$mixed232.status -eq 'passed' -and [int]$mixed232.assertions -eq 10) '232 mixed static contract is incomplete.'
  Assert-Gate ([string]$embedded232.status -eq 'passed' -and [int]$embedded232.assertions -eq 12) '232 embedded runtime contract is incomplete.'
  Assert-Gate ([string]$head232.status -eq 'passed' -and [int]$head232.assertions -eq 40 -and -not [bool]$head232.semanticMatchAllowed) '232 current-head audit is incomplete or claims semantic match.'
  foreach ($path in @(
      'tools/legado-compat/evidence/contract-legado-rule-composition-pre-fix-20260808.json',
      'tools/legado-compat/evidence/v2-rule-composition-first-operator-source-fix-20260807.json',
      'tools/legado-compat/evidence/v2-rule-composition-current-head-audit-20260808-r1.json',
      'tools/legado-compat/evidence/contract-legado-rule-composition-mixed.json')) {
    Assert-Gate (Contains-Evidence -Issue $issue232 -Path $path) ("232 evidence is not registered: {0}" -f $path)
  }
  Add-Check -Id 'failure_and_source_chain' -Detail '232 has a reproducible historical failure, fixed-source evidence, current static contracts and a current-head hash audit; R4 remains deferred.' -Evidence @('tools/legado-compat/evidence/contract-legado-rule-composition-pre-fix-20260808.json','tools/legado-compat/evidence/v2-rule-composition-first-operator-source-fix-20260807.json','tools/legado-compat/evidence/v2-rule-composition-current-head-audit-20260808-r1.json')

  $objectiveDocument = Read-StrictText -Path (Join-Path $RepositoryRoot 'docs\analysis\Legado书源V2源码重构持续目标.md')
  $governanceDocument = Read-StrictText -Path (Join-Path $RepositoryRoot 'tools\legado-compat\LEGADO_V2_GOVERNANCE_TASKS.md')
  Assert-Gate ($objectiveDocument.Contains('ISSUE-COMPAT-012') -and $objectiveDocument.Contains('ISSUE-COMPAT-232-RULE-COMPOSITION-FIRST-OPERATOR') -and $objectiveDocument.Contains('contract-legado-rule-composition-pre-fix-20260808.json')) 'objective document does not retain the 012/232 boundary and failure evidence.'
  if ($RequireRegistration) {
    Assert-Gate ($governanceDocument.Contains('activeIssue=`ISSUE-COMPAT-232-RULE-COMPOSITION-FIRST-OPERATOR`')) 'governance mirror does not select 232 after registration.'
  } else {
    Assert-Gate ($governanceDocument.Contains('activeIssue=`ISSUE-COMPAT-012`')) 'governance mirror must keep 012 as the active issue before registration.'
  }
  Add-Check -Id 'document_binding' -Detail 'Objective and governance mirror preserve one active issue, the 232 next candidate and static-only verification.' -Evidence @('docs/analysis/Legado书源V2源码重构持续目标.md','tools/legado-compat/LEGADO_V2_GOVERNANCE_TASKS.md')

  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_r3_image_012_to_rule_232_transition_consistency'
    status = 'passed'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    objectiveId = [string]$objective.objectiveId
    targetRevision = [string]$objective.targetRevision
    transition = [pscustomobject][ordered]@{
      fromIssue = 'ISSUE-COMPAT-012'
      fromStatus = 'verifying'
      toIssue = 'ISSUE-COMPAT-232-RULE-COMPOSITION-FIRST-OPERATOR'
      toStatus = 'verifying'
      nextCandidate = 'ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION'
      runtimeVerification = 'deferred_to_R4'
    }
    baseline = [pscustomobject][ordered]@{ sourceCount = [int]$baseline.sourceCount; sourcePackageSha256 = [string]$baseline.sourcePackageSha256; legadoCommit = [string]$baseline.legadoCommit }
    assertions = $script:assertions
    checks = $script:checks.ToArray()
    evidencePaths = @('tools/legado-compat/evidence/contract-legado-rule-composition-pre-fix-20260808.json','tools/legado-compat/evidence/v2-rule-composition-current-head-audit-20260808-r1.json')
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_012_to_232_static_transition_only;R4_runtime_build_device_and_legado_diff_deferred'
    registrationRequired = (-not $RequireRegistration)
  }
} catch {
  $exitCode = 1
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_r3_image_012_to_rule_232_transition_consistency'
    status = 'failed'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    failure = $_.Exception.Message
    assertions = $script:assertions
    checks = $script:checks.ToArray()
    evidencePaths = @()
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_012_to_232_static_transition_only;R4_runtime_build_device_and_legado_diff_deferred'
    registrationRequired = (-not $RequireRegistration)
  }
}

Write-AtomicJson -Path $OutputPath -Value $result
$result | ConvertTo-Json -Depth 24
if ($exitCode -ne 0) { exit $exitCode }
