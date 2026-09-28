[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$OutputPath = 'tools/legado-compat/evidence/r3-java-object-237-to-238-transition-20260809/post-registration-consistency.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$script:checks = New-Object 'System.Collections.Generic.List[object]'
$script:assertions = 0

function Get-RepoPath {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  $path = Get-RepoPath -RelativePath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "required JSON is missing: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $RelativePath" }
  try { return ($strictUtf8.GetString($bytes) | ConvertFrom-Json) }
  catch { throw "invalid JSON: $RelativePath; $($_.Exception.Message)" }
}

function Read-StrictText {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  $path = Get-RepoPath -RelativePath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "required text is missing: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $RelativePath" }
  return $strictUtf8.GetString($bytes)
}

function Get-PropertyValue {
  param([object]$Object, [Parameter(Mandatory = $true)][string]$Name)
  if ($null -eq $Object) { return $null }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { return $null }
  return $property.Value
}

function Get-Issue {
  param([object[]]$Issues, [Parameter(Mandatory = $true)][string]$Id)
  foreach ($issue in $Issues) {
    if ([string](Get-PropertyValue -Object $issue -Name 'id') -eq $Id) { return $issue }
  }
  return $null
}

function Has-Evidence {
  param([object]$Issue, [Parameter(Mandatory = $true)][string]$Path)
  foreach ($value in @((Get-PropertyValue -Object $Issue -Name 'evidencePaths'))) {
    if ([string]$value -eq $Path) { return $true }
  }
  return $false
}

function Is-ExplicitEmptyArray {
  param([object]$Object, [Parameter(Mandatory = $true)][string]$Name)
  $property = if ($null -eq $Object) { $null } else { $Object.PSObject.Properties[$Name] }
  if ($null -eq $property) { return $false }
  if ($null -eq $property.Value) { return $true }
  return @($property.Value).Count -eq 0
}

function Assert-Check {
  param([bool]$Condition, [Parameter(Mandatory = $true)][string]$Id, [Parameter(Mandatory = $true)][string]$Detail, [string[]]$Evidence = @())
  if (-not $Condition) { throw "238 post-registration consistency blocked: $Detail" }
  $script:assertions++
  [void]$script:checks.Add([pscustomobject][ordered]@{ id = $Id; status = 'passed'; detail = $Detail; evidencePaths = @($Evidence) })
}

function Write-AtomicJson {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value)
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporaryPath = "$Path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 70), $utf8NoBom)
    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

$outputFullPath = [System.IO.Path]::GetFullPath((Get-RepoPath -RelativePath $OutputPath))
$evidenceRoot = [System.IO.Path]::GetFullPath((Get-RepoPath -RelativePath 'tools/legado-compat/evidence')).TrimEnd('\') + '\'
if (-not $outputFullPath.StartsWith($evidenceRoot, [System.StringComparison]::OrdinalIgnoreCase)) { throw 'audit output must remain under evidence.' }

$result = $null
$exitCode = 0
try {
  $statePath = 'tools/legado-compat/state/full-source-validation-state.json'
  $objectivePath = 'tools/legado-compat/state/refactor-objective.json'
  $gatePath = 'tools/legado-compat/evidence/r3-java-object-237-to-238-transition-20260809/transition-consistency.json'
  $registrationPath = 'tools/legado-compat/evidence/r3-java-object-237-to-238-transition-20260809/registration.json'
  $targetPath = 'tools/legado-compat/evidence/r3-java-object-content-overload-238-target-20260809/target.json'
  $failurePath = 'tools/legado-compat/evidence/contract-legado-java-object-content-overload-pre-fix-20260809-r2.json'
  $contractPath = 'tools/legado-compat/evidence/contract-legado-java-object-content-overload.json'
  $headPath = 'tools/legado-compat/evidence/v2-java-object-content-overload-current-head-audit-20260809-r2.json'
  $fixPath = 'tools/legado-compat/evidence/v2-java-object-content-overload-source-fix-20260809-r2.json'
  $fixturePath = 'tools/legado-compat/fixtures/legado-java-object-content-overload-r2.json'

  $state = Read-StrictJson -RelativePath $statePath
  $objective = Read-StrictJson -RelativePath $objectivePath
  $gate = Read-StrictJson -RelativePath $gatePath
  $registration = Read-StrictJson -RelativePath $registrationPath
  $target = Read-StrictJson -RelativePath $targetPath
  $failure = Read-StrictJson -RelativePath $failurePath
  $contract = Read-StrictJson -RelativePath $contractPath
  $head = Read-StrictJson -RelativePath $headPath
  $fix = Read-StrictJson -RelativePath $fixPath
  $fixture = Read-StrictJson -RelativePath $fixturePath

  $baseline = $state.baseline
  Assert-Check ([int]$baseline.sourceCount -eq 458 -and [string]$baseline.sourcePackageSha256 -eq '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67' -and [string]$baseline.legadoCommit -eq '95973d186b147fb9ab43a9240021d688e4304fbd') 'baseline' 'fixed source and Legado baselines are unchanged.' @($statePath)
  Assert-Check ([string]$state.governance.activeTaskId -eq 'COMPAT-006' -and [string]$state.governance.activeIssueId -eq 'ISSUE-COMPAT-238-JAVA-OBJECT-CONTENT-OVERLOAD' -and [string]$state.governance.status -eq 'running') 'machine_queue' '238 is the sole active machine queue anchor.' @($statePath)
  Assert-Check ([string]$objective.authority.activeIssueId -eq 'ISSUE-COMPAT-238-JAVA-OBJECT-CONTENT-OVERLOAD' -and [string]$objective.executionTarget.currentIssue -eq 'ISSUE-COMPAT-238-JAVA-OBJECT-CONTENT-OVERLOAD' -and @($objective.executionTarget.nextIssues).Count -eq 0 -and [string]$objective.targetRevision -eq '2026-08-09-actual-docs-source-refactor-continuation-java-object-238-037' -and [string]$objective.continuationTarget.queueAudit.id -eq 'R3-SOURCE-QUEUE-CONTINUATION-037' -and [string]$objective.continuationTarget.queueAudit.status -eq 'planned') 'objective_queue' 'objective and machine queue name 238 with no parallel next issue; queue continuation 037 is planned.' @($objectivePath)

  $issues = @($state.governance.issues)
  $issue237 = Get-Issue -Issues $issues -Id 'ISSUE-COMPAT-237-JSOUP-INDEX-PSEUDO-SELECTORS'
  $issue238 = Get-Issue -Issues $issues -Id 'ISSUE-COMPAT-238-JAVA-OBJECT-CONTENT-OVERLOAD'
  Assert-Check ($null -ne $issue237 -and [string]$issue237.status -eq 'verifying' -and $null -ne $issue238 -and [string]$issue238.status -eq 'verifying') 'issue_statuses' '237 and 238 remain verifying-only; no runtime pass is inferred.' @($statePath)
  foreach ($path in @($gatePath, $registrationPath, $targetPath, $failurePath, $contractPath, $headPath, $fixPath, $fixturePath)) {
    Assert-Check (Has-Evidence -Issue $issue238 -Path $path) ('registered_' + $path.Replace('/', '_')) ('238 evidence is registered: ' + $path) @($statePath)
  }
  Assert-Check ([string]$gate.status -eq 'passed' -and [string]$gate.fromIssue -eq 'ISSUE-COMPAT-237-JSOUP-INDEX-PSEUDO-SELECTORS' -and [string]$gate.toIssue -eq 'ISSUE-COMPAT-238-JAVA-OBJECT-CONTENT-OVERLOAD' -and -not [bool]$gate.semanticMatchAllowed -and (Is-ExplicitEmptyArray -Object $gate -Name 'runtimeActionsPerformed')) 'transition_gate' '237→238 gate is static-only.' @($gatePath)
  Assert-Check ([string]$registration.status -eq 'registered' -and [string]$registration.previousIssueId -eq 'ISSUE-COMPAT-237-JSOUP-INDEX-PSEUDO-SELECTORS' -and [string]$registration.issueId -eq 'ISSUE-COMPAT-238-JAVA-OBJECT-CONTENT-OVERLOAD' -and [string]$registration.nextIssueId -eq '' -and -not [bool]$registration.semanticMatchAllowed -and (Is-ExplicitEmptyArray -Object $registration -Name 'runtimeActionsPerformed')) 'registration' '238 registration contains no runtime claim or next issue.' @($registrationPath)
  Assert-Check ([string]$target.status -eq 'active' -and [string]$target.currentSubstage -eq '238-OC-06' -and [string]$target.currentStatus -eq 'source_closed_static_only') 'target' '238 target is active at the deferred R4 handoff.' @($targetPath)
  Assert-Check ([string]$failure.status -eq 'failed' -and [string]$failure.issueId -eq 'ISSUE-COMPAT-238-JAVA-OBJECT-CONTENT-OVERLOAD' -and -not [bool]$failure.semanticMatchAllowed -and (Is-ExplicitEmptyArray -Object $failure -Name 'runtimeActionsPerformed')) 'failure_witness' '238 pre-fix failure witness remains static-only.' @($failurePath)
  Assert-Check ([string]$contract.status -eq 'passed' -and [int]$contract.assertions -eq 20) 'static_contract' '238 base contract retains 20 assertions.' @($contractPath)
  Assert-Check ([string]$head.status -eq 'passed' -and [int]$head.assertions -ge 13 -and -not [bool]$head.semanticMatchAllowed -and (Is-ExplicitEmptyArray -Object $head -Name 'runtimeActionsPerformed')) 'current_head' '238 current-head audit is static-only.' @($headPath)
  Assert-Check ([string]$fix.status -eq 'source_closed_static_only' -and -not [bool]$fix.semanticMatchAllowed) 'source_fix' '238 source-fix evidence is static-only.' @($fixPath)
  Assert-Check (@($fixture.cases).Count -eq 7) 'fixture' '238 fixture retains seven deterministic cases.' @($fixturePath)

  $objectiveDocument = Read-StrictText -RelativePath 'docs/analysis/Legado书源V2源码重构持续目标.md'
  $governanceDocument = Read-StrictText -RelativePath 'tools/legado-compat/LEGADO_V2_GOVERNANCE_TASKS.md'
  $evidenceIndex = Read-StrictText -RelativePath 'docs/analysis/Legado书源引擎证据索引.md'
  $differenceSummary = Read-StrictText -RelativePath 'docs/analysis/Legado书源引擎差分摘要.md'
  Assert-Check ($objectiveDocument.Contains('当前唯一活动源码锚点为 `ISSUE-COMPAT-238-JAVA-OBJECT-CONTENT-OVERLOAD`') -and $objectiveDocument.Contains('238-OC-06') -and -not $objectiveDocument.Contains('238 尚未激活')) 'objective_document' 'objective document reflects the active 238 boundary and deferred R4 handoff.' @('docs/analysis/Legado书源V2源码重构持续目标.md')
  Assert-Check ($governanceDocument.Contains('当前唯一活动根因议题为 `ISSUE-COMPAT-238-JAVA-OBJECT-CONTENT-OVERLOAD`') -and $governanceDocument.Contains('238-OC-06') -and -not $governanceDocument.Contains('238 尚未激活')) 'governance_document' 'governance task mirror reflects the active 238 boundary.' @('tools/legado-compat/LEGADO_V2_GOVERNANCE_TASKS.md')
  Assert-Check ($evidenceIndex.Contains($gatePath) -and $evidenceIndex.Contains($registrationPath) -and $differenceSummary.Contains($gatePath) -and $differenceSummary.Contains($registrationPath)) 'document_indexes' 'evidence index and difference summary include both 237→238 registration artifacts.' @('docs/analysis/Legado书源引擎证据索引.md', 'docs/analysis/Legado书源引擎差分摘要.md')

  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_r3_java_object_237_to_238_post_registration_consistency'
    status = 'passed'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    objectiveId = [string]$objective.objectiveId
    targetRevision = [string]$objective.targetRevision
    activeIssueId = 'ISSUE-COMPAT-238-JAVA-OBJECT-CONTENT-OVERLOAD'
    previousIssueId = 'ISSUE-COMPAT-237-JSOUP-INDEX-PSEUDO-SELECTORS'
    baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = [string]$baseline.sourcePackageSha256; legadoCommit = [string]$baseline.legadoCommit }
    assertions = $script:assertions
    checks = $script:checks.ToArray()
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_post_registration_static_consistency_only;238_verifying;R4_runtime_build_device_and_legado_diff_deferred'
  }
} catch {
  $exitCode = 1
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_r3_java_object_237_to_238_post_registration_consistency'
    status = 'failed'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    failure = $_.Exception.Message
    assertions = $script:assertions
    checks = $script:checks.ToArray()
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_post_registration_static_consistency_only;238_verifying;R4_runtime_build_device_and_legado_diff_deferred'
  }
}

Write-AtomicJson -Path $outputFullPath -Value $result
$result | ConvertTo-Json -Depth 70
if ($exitCode -ne 0) { exit $exitCode }
