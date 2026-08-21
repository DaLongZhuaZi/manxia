[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$OutputPath = 'tools/legado-compat/evidence/r3-jsoup-has-236-to-index-237-transition-20260809/post-registration-consistency.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$outputFullPath = [System.IO.Path]::GetFullPath((Join-Path $RepositoryRoot ($OutputPath.Replace('/', '\'))))
$evidenceRoot = [System.IO.Path]::GetFullPath((Join-Path $RepositoryRoot 'tools\legado-compat\evidence')).TrimEnd('\') + '\'
if (-not $outputFullPath.StartsWith($evidenceRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw 'post-registration evidence must remain under the evidence directory.'
}

$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$script:assertions = 0
$script:checks = New-Object 'System.Collections.Generic.List[object]'

function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  $path = Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "required JSON is missing: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $RelativePath" }
  try { return ($strictUtf8.GetString($bytes) | ConvertFrom-Json) }
  catch { throw "invalid JSON: $RelativePath; $($_.Exception.Message)" }
}

function Read-StrictText {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  $path = Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "required text is missing: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $RelativePath" }
  return $strictUtf8.GetString($bytes)
}

function Get-PropertyValue {
  param([object]$Object, [string]$Name)
  if ($null -eq $Object) { return $null }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { return $null }
  return $property.Value
}

function Get-Issue {
  param([object[]]$Issues, [string]$Id)
  foreach ($issue in $Issues) {
    if ([string](Get-PropertyValue -Object $issue -Name 'id') -eq $Id) { return $issue }
  }
  return $null
}

function Has-Evidence {
  param([object]$Issue, [string]$Path)
  foreach ($value in @((Get-PropertyValue -Object $Issue -Name 'evidencePaths'))) {
    if ([string]$value -eq $Path) { return $true }
  }
  return $false
}

function Has-ExplicitEmptyArray {
  param([object]$Object, [string]$Name)
  $property = if ($null -eq $Object) { $null } else { $Object.PSObject.Properties[$Name] }
  if ($null -eq $property) { return $false }
  if ($null -eq $property.Value) { return $true }
  return @($property.Value).Count -eq 0
}

function Assert-Consistency {
  param([bool]$Condition, [string]$Id, [string]$Detail, [string[]]$Evidence = @())
  if (-not $Condition) { throw "237 post-registration consistency blocked: $Detail" }
  $script:assertions++
  [void]$script:checks.Add([pscustomobject][ordered]@{ id = $Id; status = 'passed'; detail = $Detail; evidencePaths = @($Evidence) })
}

function Write-AtomicJson {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value)
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporaryPath = "$Path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 60), $utf8NoBom)
    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

$result = $null
$exitCode = 0
try {
  $state = Read-StrictJson -RelativePath 'tools/legado-compat/state/full-source-validation-state.json'
  $objective = Read-StrictJson -RelativePath 'tools/legado-compat/state/refactor-objective.json'
  $gatePath = 'tools/legado-compat/evidence/r3-jsoup-has-236-to-index-237-transition-20260809/transition-consistency.json'
  $registrationPath = 'tools/legado-compat/evidence/r3-jsoup-has-236-to-index-237-transition-20260809/registration.json'
  $targetPath = 'tools/legado-compat/evidence/r3-jsoup-index-237-target-20260809/target.json'
  $preFixPath = 'tools/legado-compat/evidence/contract-legado-jsoup-index-pseudo-selectors-pre-fix-20260809.json'
  $currentHeadPath = 'tools/legado-compat/evidence/v2-jsoup-index-pseudo-selector-current-head-audit-20260809.json'
  $sourceFixPath = 'tools/legado-compat/evidence/v2-jsoup-index-pseudo-selector-source-fix-20260809.json'
  $contractPath = 'tools/legado-compat/evidence/contract-legado-jsoup-index-pseudo-selectors.json'
  $fixturePath = 'tools/legado-compat/fixtures/legado-jsoup-index-pseudo-selectors.json'
  $gate = Read-StrictJson -RelativePath $gatePath
  $registration = Read-StrictJson -RelativePath $registrationPath
  $target = Read-StrictJson -RelativePath $targetPath
  $preFix = Read-StrictJson -RelativePath $preFixPath
  $currentHead = Read-StrictJson -RelativePath $currentHeadPath
  $sourceFix = Read-StrictJson -RelativePath $sourceFixPath
  $contract = Read-StrictJson -RelativePath $contractPath
  $fixture = Read-StrictJson -RelativePath $fixturePath
  $baseline = $state.baseline

  Assert-Consistency ([int]$baseline.sourceCount -eq 458 -and [string]$baseline.sourcePackageSha256 -eq '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67' -and [string]$baseline.legadoCommit -eq '95973d186b147fb9ab43a9240021d688e4304fbd') 'baseline' 'fixed source and Legado baselines are unchanged.' @('tools/legado-compat/state/full-source-validation-state.json')
  Assert-Consistency ([string]$state.governance.activeTaskId -eq 'COMPAT-006' -and [string]$state.governance.activeIssueId -eq 'ISSUE-COMPAT-237-JSOUP-INDEX-PSEUDO-SELECTORS' -and [string]$state.governance.status -eq 'running') 'machine_queue' 'machine queue points to 237 as the sole active issue.' @('tools/legado-compat/state/full-source-validation-state.json')
  Assert-Consistency ([string]$objective.authority.activeIssueId -eq 'ISSUE-COMPAT-237-JSOUP-INDEX-PSEUDO-SELECTORS' -and [string]$objective.executionTarget.currentIssue -eq 'ISSUE-COMPAT-237-JSOUP-INDEX-PSEUDO-SELECTORS' -and @($objective.executionTarget.nextIssues) -contains 'ISSUE-COMPAT-238-JAVA-OBJECT-CONTENT-OVERLOAD' -and [string]$objective.targetRevision -eq '2026-08-09-actual-docs-source-refactor-continuation-jsoup-index-237-034') 'objective_queue' 'objective queue names 237 and 238 at revision 034.' @('tools/legado-compat/state/refactor-objective.json')

  $issues = @($state.governance.issues)
  $issue236 = Get-Issue -Issues $issues -Id 'ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR'
  $issue237 = Get-Issue -Issues $issues -Id 'ISSUE-COMPAT-237-JSOUP-INDEX-PSEUDO-SELECTORS'
  Assert-Consistency ($null -ne $issue236 -and [string]$issue236.status -eq 'verifying' -and $null -ne $issue237 -and [string]$issue237.status -eq 'verifying') 'issue_statuses' '236 and 237 remain verifying-only; no runtime pass is inferred.' @('tools/legado-compat/state/full-source-validation-state.json')
  foreach ($path in @($gatePath, $registrationPath, $targetPath, $preFixPath, $currentHeadPath, $sourceFixPath)) {
    Assert-Consistency (Has-Evidence -Issue $issue237 -Path $path) ('registered_' + $path.Replace('/', '_')) ('237 evidence is registered: ' + $path) @('tools/legado-compat/state/full-source-validation-state.json')
  }

  Assert-Consistency ([string]$gate.status -eq 'passed' -and [string]$gate.fromIssue -eq 'ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR' -and [string]$gate.toIssue -eq 'ISSUE-COMPAT-237-JSOUP-INDEX-PSEUDO-SELECTORS' -and [string]$gate.nextCandidateAfterRegistration -eq 'ISSUE-COMPAT-238-JAVA-OBJECT-CONTENT-OVERLOAD' -and -not [bool]$gate.semanticMatchAllowed -and (Has-ExplicitEmptyArray -Object $gate -Name 'runtimeActionsPerformed')) 'transition_gate' '236→237 gate is static-only and names 238 as next candidate.' @($gatePath)
  Assert-Consistency ([string]$registration.status -eq 'registered' -and [string]$registration.previousIssueId -eq 'ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR' -and [string]$registration.issueId -eq 'ISSUE-COMPAT-237-JSOUP-INDEX-PSEUDO-SELECTORS' -and [string]$registration.nextIssueId -eq 'ISSUE-COMPAT-238-JAVA-OBJECT-CONTENT-OVERLOAD' -and -not [bool]$registration.semanticMatchAllowed -and (Has-ExplicitEmptyArray -Object $registration -Name 'runtimeActionsPerformed')) 'registration' '237 registration contains no runtime claim.' @($registrationPath)
  Assert-Consistency ([string]$target.issueId -eq 'ISSUE-COMPAT-237-JSOUP-INDEX-PSEUDO-SELECTORS' -and [string]$target.currentStatus -eq 'source_closed_static_only' -and [string]$target.currentSubstage -eq '237-IP-05' -and -not [bool]$target.constraints.semanticMatchAllowed) 'target' '237 target remains static-closed with R4 deferred.' @($targetPath)
  Assert-Consistency ([string]$preFix.status -eq 'failed' -and [string]$preFix.issueId -eq 'ISSUE-COMPAT-237-JSOUP-INDEX-PSEUDO-SELECTORS' -and [int]$preFix.assertions -eq 7 -and -not [bool]$preFix.semanticMatchAllowed -and (Has-ExplicitEmptyArray -Object $preFix -Name 'runtimeActionsPerformed')) 'failure_witness' 'independent 237 failure witness is preserved.' @($preFixPath)
  Assert-Consistency ([string]$currentHead.status -eq 'passed' -and [int]$currentHead.assertions -eq 16 -and -not [bool]$currentHead.semanticMatchAllowed -and (Has-ExplicitEmptyArray -Object $currentHead -Name 'runtimeActionsPerformed')) 'current_head' 'current-head consumer audit is static-only.' @($currentHeadPath)
  Assert-Consistency ([string]$sourceFix.status -eq 'source_closed_static_only' -and [string]$sourceFix.issueId -eq 'ISSUE-COMPAT-237-JSOUP-INDEX-PSEUDO-SELECTORS' -and [int]$sourceFix.assertions -eq 5 -and [int]$sourceFix.staticImpact.ruleStringCount -eq 16 -and [int]$sourceFix.staticImpact.affectedSourceCount -eq 9 -and -not [bool]$sourceFix.semanticMatchAllowed -and (Has-ExplicitEmptyArray -Object $sourceFix -Name 'runtimeActionsPerformed')) 'source_fix' 'source-fix evidence covers 16 rules and 9 sources without a runtime claim.' @($sourceFixPath)
  Assert-Consistency ([string]$contract.status -eq 'passed' -and [int]$contract.assertions -eq 20 -and [int]$contract.impact.ruleStringCount -eq 16 -and [int]$contract.impact.affectedSourceCount -eq 9) 'static_contract' '237 static contract retains 20 assertions and impact counts.' @($contractPath)
  Assert-Consistency (@($fixture.cases).Count -eq 6) 'fixture' '237 fixture retains six deterministic cases.' @($fixturePath)

  $objectiveDocument = Read-StrictText -RelativePath 'docs/analysis/Legado书源V2源码重构持续目标.md'
  $governanceDocument = Read-StrictText -RelativePath 'tools/legado-compat/LEGADO_V2_GOVERNANCE_TASKS.md'
  Assert-Consistency ($objectiveDocument.Contains('当前唯一活动源码锚点为 `ISSUE-COMPAT-237-JSOUP-INDEX-PSEUDO-SELECTORS`') -and $objectiveDocument.Contains('238 是下一候选且尚未激活') -and -not $objectiveDocument.Contains('236 成为当前唯一活动源码议题')) 'objective_document' 'objective document reflects the 237 active boundary.' @('docs/analysis/Legado书源V2源码重构持续目标.md')
  Assert-Consistency ($governanceDocument.Contains('当前唯一活动根因议题为 `ISSUE-COMPAT-237-JSOUP-INDEX-PSEUDO-SELECTORS`') -and $governanceDocument.Contains('238 尚未激活')) 'governance_document' 'governance mirror reflects the 237 queue.' @('tools/legado-compat/LEGADO_V2_GOVERNANCE_TASKS.md')

  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_r3_jsoup_has_236_to_index_237_post_registration_consistency'
    status = 'passed'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    objectiveId = [string]$objective.objectiveId
    targetRevision = [string]$objective.targetRevision
    activeIssueId = 'ISSUE-COMPAT-237-JSOUP-INDEX-PSEUDO-SELECTORS'
    nextIssueId = 'ISSUE-COMPAT-238-JAVA-OBJECT-CONTENT-OVERLOAD'
    baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'; legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd' }
    assertions = $script:assertions
    checks = $script:checks.ToArray()
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_post_registration_static_consistency_only;R4_runtime_build_device_and_legado_diff_deferred'
  }
} catch {
  $exitCode = 1
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_r3_jsoup_has_236_to_index_237_post_registration_consistency'
    status = 'failed'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    failure = $_.Exception.Message
    assertions = $script:assertions
    checks = $script:checks.ToArray()
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_post_registration_static_consistency_only;R4_runtime_build_device_and_legado_diff_deferred'
  }
}

Write-AtomicJson -Path $outputFullPath -Value $result
$result | ConvertTo-Json -Depth 60
if ($exitCode -ne 0) { exit $exitCode }
