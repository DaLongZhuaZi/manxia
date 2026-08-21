[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$GateEvidencePath = 'tools/legado-compat/evidence/r3-jsoup-entity-243-to-244-transition-20260813/transition-consistency.json',
  [string]$RegistrationEvidencePath = 'tools/legado-compat/evidence/r3-jsoup-entity-243-to-244-transition-20260813/registration.json',
  [string]$TargetEvidencePath = 'tools/legado-compat/evidence/r3-jsoup-entity-244-target-20260813/target.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$issue243 = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
$issue244 = 'ISSUE-COMPAT-244-JSOUP-HTML-ENTITY-SEMANTICS'
$taskId = 'COMPAT-006'
$revision = '2026-08-13-actual-docs-source-refactor-jsoup-entity-244-active'
$baselineHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$script:assertions = 0
$script:checks = New-Object 'System.Collections.Generic.List[object]'

function Get-RepoPath {
  param([Parameter(Mandatory = $true)][string]$Path)
  if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }
  return Join-Path $RepositoryRoot ($Path.Replace('/', '\'))
}

function Read-StrictText {
  param([Parameter(Mandatory = $true)][string]$Path)
  $resolved = Get-RepoPath -Path $Path
  if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "required file is missing: $Path" }
  $bytes = [System.IO.File]::ReadAllBytes($resolved)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw "UTF-8 BOM is not allowed: $Path"
  }
  return $strictUtf8.GetString($bytes)
}

function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$Path)
  return Read-StrictText -Path $Path | ConvertFrom-Json -Depth 100
}

function Write-AtomicJson {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][object]$Value
  )
  $resolved = Get-RepoPath -Path $Path
  $directory = Split-Path -Parent $resolved
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  }
  $temporary = "$resolved.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8)
    Move-Item -LiteralPath $temporary -Destination $resolved -Force
  } finally {
    if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) }
  }
}

function Set-PropertyValue {
  param(
    [Parameter(Mandatory = $true)][object]$Object,
    [Parameter(Mandatory = $true)][string]$Name,
    [AllowNull()][object]$Value
  )
  if ($null -eq $Object.PSObject.Properties[$Name]) {
    $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
  } else {
    $Object.$Name = $Value
  }
}

function Add-Check {
  param(
    [Parameter(Mandatory = $true)][string]$Id,
    [Parameter(Mandatory = $true)][bool]$Passed,
    [Parameter(Mandatory = $true)][string]$Detail
  )
  [void]$script:checks.Add([pscustomobject][ordered]@{ id = $Id; passed = $Passed; detail = $Detail })
  $script:assertions++
  if (-not $Passed) { throw "243 to 244 static transition blocked: $Id; $Detail" }
}

function Get-Issue {
  param([Parameter(Mandatory = $true)][object[]]$Issues, [Parameter(Mandatory = $true)][string]$Id)
  return @($Issues | Where-Object { [string]$_.id -eq $Id }) | Select-Object -First 1
}

function Get-FileSha256 {
  param([Parameter(Mandatory = $true)][string]$Path)
  $resolved = Get-RepoPath -Path $Path
  if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { return '' }
  return (Get-FileHash -Algorithm SHA256 -LiteralPath $resolved).Hash.ToUpperInvariant()
}

function Test-CurrentTransitionState {
  param(
    [Parameter(Mandatory = $true)][object]$CurrentState,
    [Parameter(Mandatory = $true)][object]$CurrentObjective
  )
  $current243 = Get-Issue -Issues @($CurrentState.governance.issues) -Id $issue243
  $current244 = Get-Issue -Issues @($CurrentState.governance.issues) -Id $issue244
  $order = @($CurrentObjective.objective.sourceClosureOrder | ForEach-Object { [string]$_ })
  $queue = $CurrentState.governance.queuePreflight
  $selection = $CurrentObjective.objective.queueSelectionGate
  $audit = $CurrentObjective.continuationTarget.queueAudit
  $sync = $CurrentObjective.governanceSync
  return [string]$CurrentState.governance.activeIssueId -eq $issue244 -and
    [string]$CurrentState.governance.currentSourceClosureBoundary -eq $issue244 -and
    [string]$queue.status -eq 'passed_issue_selected' -and
    [string]$queue.activeIssueId -eq $issue244 -and
    [string]$queue.candidateGateStatus -eq 'independent_evidence_gate_passed' -and
    [string]$current243.status -eq 'verifying' -and
    [string]$current244.status -eq 'running' -and
    [string]$CurrentObjective.targetRevision -eq $revision -and
    [string]$CurrentObjective.authority.activeIssueId -eq $issue244 -and
    [string]$CurrentObjective.objective.activeIssue -eq $issue244 -and
    [string]$CurrentObjective.executionTarget.currentIssue -eq $issue244 -and
    [string]$selection.currentAnchor -eq $issue244 -and
    [string]$selection.selectedIssue -eq $issue244 -and
    [string]$audit.currentAnchor -eq $issue244 -and
    [string]$audit.selectedIssue -eq $issue244 -and
    [string]$audit.activeIssueId -eq $issue244 -and
    [string]$sync.activeIssueId -eq $issue244 -and
    [string]$sync.queueSelectionCurrentAnchor -eq $issue244 -and
    [string]$sync.queueAuditCurrentAnchor -eq $issue244 -and
    $order -contains $issue244 -and
    -not [bool]$CurrentState.governance.semanticMatchAllowed -and
    @($CurrentState.governance.runtimeActionsPerformed).Count -eq 0
}

function Get-OfficialSource {
  param([Parameter(Mandatory = $true)][string]$Url, [Parameter(Mandatory = $true)][string]$ExpectedSha256)
  $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
  $content = [string]$response.Content
  $sha256 = [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($content)))
  Add-Check ("official_source_{0}" -f $ExpectedSha256.Substring(0, 12)) (
    [int]$response.StatusCode -eq 200 -and $sha256 -eq $ExpectedSha256
  ) "official Jsoup source hash matches $ExpectedSha256."
  return $content
}

$statePath = 'tools/legado-compat/state/full-source-validation-state.json'
$objectivePath = 'tools/legado-compat/state/refactor-objective.json'
$fixturePath = 'tools/legado-compat/fixtures/legado-jsoup-html-entity-semantics-gap.json'
$discoveryPath = 'tools/legado-compat/evidence/v2-jsoup-html-entity-semantics-gap-discovery-20260811.json'
$readinessPath = 'tools/legado-compat/evidence/contract-legado-jsoup-standard-pseudo-243-current-r4-readiness-20260813.json'
$readinessRegistrationPath = 'tools/legado-compat/evidence/v2-jsoup-standard-pseudo-243-current-r4-readiness-registration-20260813.json'
$registerPath = 'tools/legado-compat/Register-LegadoR3JsoupEntity243To244Transition.ps1'
$state = Read-StrictJson -Path $statePath
$objective = Read-StrictJson -Path $objectivePath
$fixture = Read-StrictJson -Path $fixturePath
$discovery = Read-StrictJson -Path $discoveryPath
$readiness = Read-StrictJson -Path $readinessPath
$issues = @($state.governance.issues)
$record243 = Get-Issue -Issues $issues -Id $issue243
$record244 = Get-Issue -Issues $issues -Id $issue244

$registrationAbsolutePath = Get-RepoPath -Path $RegistrationEvidencePath
$alreadyRegistered = Test-CurrentTransitionState -CurrentState $state -CurrentObjective $objective
if ($alreadyRegistered) {
  $registration = Read-StrictJson -Path $RegistrationEvidencePath
  $gate = Read-StrictJson -Path $GateEvidencePath
  $target = Read-StrictJson -Path $TargetEvidencePath
  $expectedHashes = $registration.evidenceHashes
  Add-Check 'idempotent_registration_contract' (
    [string]$registration.status -eq 'registered' -and
    [string]$registration.issueId -eq $issue244 -and
    [string]$registration.targetRevision -eq $revision -and
    [string]$gate.status -eq 'passed_static_only' -and
    [string]$target.issueId -eq $issue244 -and
    [string]$expectedHashes.gate -eq (Get-FileSha256 -Path $GateEvidencePath) -and
    [string]$expectedHashes.target -eq (Get-FileSha256 -Path $TargetEvidencePath)
  ) 'idempotent replay validates the complete state and immutable evidence hashes.'
  [pscustomobject][ordered]@{
    status = 'already_registered'
    idempotent = $true
    previousIssueId = $issue243
    issueId = $issue244
    targetRevision = $revision
    gateEvidencePath = $GateEvidencePath
    registrationEvidencePath = $RegistrationEvidencePath
    gateSha256 = Get-FileSha256 -Path $GateEvidencePath
    targetSha256 = Get-FileSha256 -Path $TargetEvidencePath
    assertions = $script:assertions
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
  } | ConvertTo-Json -Depth 100
  return
}
$partialRegistration = [string]$state.governance.activeIssueId -eq $issue244 -and
  [string]$objective.authority.activeIssueId -eq $issue244 -and
  [string]$objective.executionTarget.currentIssue -eq $issue244 -and
  [string]$objective.targetRevision -eq $revision -and
  $null -ne $record243 -and [string]$record243.status -eq 'verifying' -and
  $null -ne $record244 -and [string]$record244.status -eq 'running' -and
  (Test-Path -LiteralPath $registrationAbsolutePath -PathType Leaf)

Add-Check 'frozen_baseline' (
  [int]$state.baseline.sourceCount -eq 458 -and
  [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and
  [string]$state.baseline.legadoCommit -eq $legadoCommit -and
  [string]$fixture.baseline.jsoupVersion -eq '1.16.2'
) 'machine and fixture baselines are frozen.'
Add-Check 'pre_transition_queue' (
  [string]$state.governance.status -eq 'running' -and
  [string]$state.governance.activeTaskId -eq $taskId -and
  ((
      [string]$state.governance.activeIssueId -eq $issue243 -and
      $null -ne $record243 -and [string]$record243.status -eq 'verifying' -and
      $null -ne $record244 -and [string]$record244.status -eq 'planned'
    ) -or $partialRegistration)
) 'the queue is either at the clean 243 pre-transition boundary or the recognized partial 244 registration recovery boundary.'
Add-Check 'transition_mode' $true $(if ($partialRegistration) { 'partial_registration_recovery' } else { 'initial_transition' })
Add-Check 'runtime_gate_locked' (
  -not [bool]$state.governance.semanticMatchAllowed -and
  @($state.governance.runtimeActionsPerformed).Count -eq 0
) 'no runtime or semantic-match gate is open.'
Add-Check 'current_243_readiness' (
  [string]$readiness.status -eq 'passed_static_only' -and
  [int]$readiness.currentLedger.subtaskCount -eq 79 -and
  [int]$readiness.currentLedger.completedCount -eq 41 -and
  [int]$readiness.currentLedger.deferredCount -eq 38 -and
  [int]$readiness.currentLedger.completedEvidenceCount -eq 172
) '243 has an authoritative 79/41/38 current readiness inventory before handoff.'
Add-Check 'failure_fixture' (
  [string]$fixture.contract -eq 'legado_jsoup_html_entity_semantic_gap' -and
  [string]$fixture.issueId -eq $issue244 -and
  @($fixture.cases).Count -eq 5 -and
  [string]$discovery.status -eq 'failed' -and
  [string]$discovery.issueId -eq $issue244
) '244 has five deterministic failing semantic cases.'
Add-Check 'dynamic_impact_boundary' (
  [string]$fixture.impactScope.classification -eq 'dynamic_response_dependent' -and
  @($fixture.impactScope.affectedExecutionPaths).Count -eq 4
) 'response-dependent impact is explicit and is not fabricated from source JSON.'

$legadoHead = (& git -C (Get-RepoPath -Path 'legado') rev-parse HEAD 2>$null | Out-String).Trim()
$versionCatalog = Read-StrictText -Path 'legado/gradle/libs.versions.toml'
Add-Check 'fixed_legado_reference' (
  $legadoHead -eq $legadoCommit -and $versionCatalog -match '(?m)^jsoup\s*=\s*"1\.16\.2"\s*$'
) 'the fixed Legado checkout resolves Jsoup 1.16.2.'

$entitiesSource = Get-OfficialSource -Url ([string]$fixture.officialReference.entitiesSourceUrl) -ExpectedSha256 ([string]$fixture.officialReference.entitiesSourceSha256)
$entitiesDataSource = Get-OfficialSource -Url ([string]$fixture.officialReference.entitiesDataSourceUrl) -ExpectedSha256 ([string]$fixture.officialReference.entitiesDataSourceSha256)
Add-Check 'official_entity_semantics' (
  $entitiesSource.Contains('extended(EntitiesData.fullPoints, 2125)') -and
  $entitiesSource.Contains('multipoints.put(name') -and
  $entitiesDataSource.Contains('NotEqualTilde=6rm,mw') -and
  $entitiesDataSource.Contains('CounterClockwiseContourIntegral=6r7') -and
  $entitiesDataSource.Contains('Afr=2kn8') -and
  $entitiesDataSource.Contains('fjlig=2u,2y')
) 'official Jsoup data proves extended, multipoint, long-name and non-BMP semantics.'

$consumerPaths = @(
  'entry/src/main/ets/libs/htmlparser/HtmlEntities.ets',
  'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets',
  'entry/src/main/ets/Framework/Novel/LegadoJsEngine.ets',
  'entry/src/main/resources/rawfile/rhino_sandbox/jsoup_impl.js'
)
$consumerHashes = New-Object 'System.Collections.Generic.List[object]'
foreach ($consumerPath in $consumerPaths) {
  $absolute = Get-RepoPath -Path $consumerPath
  Add-Check ("consumer_exists_{0}" -f ([IO.Path]::GetFileName($consumerPath))) (Test-Path -LiteralPath $absolute -PathType Leaf) "consumer exists: $consumerPath"
  [void]$consumerHashes.Add([pscustomobject][ordered]@{
      path = $consumerPath
      sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $absolute).Hash.ToUpperInvariant()
    })
}
Add-Check 'consumer_matrix' (
  [int]$discovery.localObservedLimits.typedHtmlEntitiesNamedEntries -eq 122 -and
  [int]$discovery.localObservedLimits.analyzerFastNamedEntries -eq 6 -and
  [int]$discovery.localObservedLimits.generatedJsvmNamedEntries -eq 6 -and
  [int]$discovery.localObservedLimits.rhinoStandaloneFallbackNamedEntries -eq 33
) 'all four deficient V2 entity consumers are quantified.'

$gate = [pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_r3_jsoup_entity_243_to_244_transition_consistency'
  status = 'passed_static_only'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  fromIssue = $issue243
  toIssue = $issue244
  fromStatus = 'verifying'
  toStatus = 'running'
  targetRevision = $revision
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit; jsoupVersion = '1.16.2' }
  evidenceGate = [pscustomobject][ordered]@{
    fixedLegadoImplementation = 'passed'
    affectedScope = 'dynamic_response_dependent_all_html_entity_consumers'
    reproducibleFailureFixture = 'passed_5_cases'
    v2ConsumerMatrix = 'passed_4_paths'
    closeCondition = 'present'
  }
  consumerHashes = $consumerHashes.ToArray()
  assertions = $script:assertions
  checks = $script:checks.ToArray()
  evidencePaths = @($readinessPath, $readinessRegistrationPath, $fixturePath, $discoveryPath, 'legado/gradle/libs.versions.toml') + $consumerPaths
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_static_transition_only;244_becomes_running_source_anchor;243_and_R4_runtime_build_device_harness_legado_diff_deferred'
}
Write-AtomicJson -Path $GateEvidencePath -Value $gate

$now = [DateTimeOffset]::UtcNow.ToString('o')
Set-PropertyValue -Object $state.governance -Name 'activeIssueId' -Value $issue244
Set-PropertyValue -Object $state.governance -Name 'currentSourceClosureBoundary' -Value $issue244
Set-PropertyValue -Object $state.governance -Name 'semanticMatchAllowed' -Value $false
Set-PropertyValue -Object $state.governance -Name 'runtimeActionsPerformed' -Value @()
Set-PropertyValue -Object $state.governance -Name 'queuePreflight' -Value ([pscustomobject][ordered]@{
    status = 'passed_issue_selected'
    evidencePath = $GateEvidencePath
    reproductionCommand = 'pwsh -NoLogo -NoProfile -NonInteractive -File tools/legado-compat/Register-LegadoR3JsoupEntity243To244Transition.ps1'
    evaluatedCount = 1
    candidateCount = 1
    activeIssueId = $issue244
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    candidateGateStatus = 'independent_evidence_gate_passed'
    updatedAt = $now
  })
Set-PropertyValue -Object $record243 -Name 'status' -Value 'verifying'
Set-PropertyValue -Object $record243 -Name 'lastUpdatedAt' -Value $now
Set-PropertyValue -Object $record244 -Name 'status' -Value 'running'
Set-PropertyValue -Object $record244 -Name 'summary' -Value '244 is the sole active source issue. Fixed Jsoup 1.16.2 exposes 2125 extended entities with multipoint and non-BMP values; V2 has four divergent subset decoders. Impact is response-dependent across all HTML entity consumers and is not fabricated from source JSON.'
Set-PropertyValue -Object $record244 -Name 'closeCondition' -Value 'Generate one pinned Jsoup 1.16.2 entity data source and shared decoder contract; consume it in typed DOM, Analyzer, generated JSVM and Rhino paths; prove all five fixtures and full 2125-entry integrity statically. R4 runtime, fixed-Legado differential, affected responses, 458-source Harness, build and device gates remain required before passed or semantic_match.'
Set-PropertyValue -Object $record244 -Name 'lastUpdatedAt' -Value $now

$existingEvidence = @($record244.evidencePaths | ForEach-Object { [string]$_ })
$transitionEvidence = @($GateEvidencePath, $RegistrationEvidencePath, $TargetEvidencePath, $registerPath, $readinessPath, $readinessRegistrationPath)
Set-PropertyValue -Object $record244 -Name 'evidencePaths' -Value @($existingEvidence + $transitionEvidence | Select-Object -Unique)

$target = [pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_r3_jsoup_html_entity_semantics_target'
  status = 'active'
  generatedAt = $now
  issueId = $issue244
  taskId = $taskId
  targetRevision = $revision
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit; jsoupVersion = '1.16.2' }
  reasonForTarget = 'All five static evidence gates are satisfied. The defect is a shared parser semantic gap, not a source-specific rule exception.'
  plan = @(
    [pscustomobject][ordered]@{ id = '244-ENTITY-01'; status = 'completed'; action = '固定官方 Jsoup 1.16.2 Entities/EntitiesData 哈希、2125 项声明和五个失败案例。'; evidence = @($fixturePath, $discoveryPath, $GateEvidencePath) },
    [pscustomobject][ordered]@{ id = '244-ENTITY-02'; status = 'running'; action = '生成单一实体数据源和共享解码契约，替换 typed DOM、Analyzer、JSVM 与 Rhino 的子集实现。'; evidence = @($GateEvidencePath) },
    [pscustomobject][ordered]@{ id = '244-ENTITY-03'; status = 'planned'; action = '执行完整 2125 项数据完整性、五个语义案例、UTF-8、源码哈希和所有消费者静态合同。' },
    [pscustomobject][ordered]@{ id = '244-ENTITY-04'; status = 'deferred'; action = 'R4 执行响应 fixture、固定 Legado 差分、458 条 Harness、构建和真机验证。' }
  )
  currentSubstage = '244-ENTITY-02'
  constraints = [pscustomobject][ordered]@{ runtimeActionsPerformed = @(); semanticMatchAllowed = $false; impactScope = 'dynamic_response_dependent' }
  closeCondition = [string]$record244.closeCondition
}
Write-AtomicJson -Path $TargetEvidencePath -Value $target

Set-PropertyValue -Object $objective -Name 'lastReviewedAt' -Value $now
Set-PropertyValue -Object $objective -Name 'targetRevision' -Value $revision
Set-PropertyValue -Object $objective -Name 'continuationMode' -Value 'R3_ISSUE_244_JSOUP_HTML_ENTITY_SOURCE_GOVERNANCE'
Set-PropertyValue -Object $objective.authority -Name 'activeIssueId' -Value $issue244
Set-PropertyValue -Object $objective.authority -Name 'activeIssueSelection' -Value '244 is the sole active source issue after the five static evidence gates passed. 243 remains verifying with 38 R4 deferrals; semanticMatchAllowed remains false.'
Set-PropertyValue -Object $objective.objective -Name 'activeIssue' -Value $issue244
Set-PropertyValue -Object $objective.objective -Name 'activeIssueRule' -Value 'Implement complete pinned Jsoup 1.16.2 character-reference semantics from one generated data source across every V2 HTML entity consumer; do not add per-source exceptions or duplicate subset maps.'
Set-PropertyValue -Object $objective.objective -Name 'currentWorkstream' -Value 'R3-ISSUE-244-JSOUP-HTML-ENTITY-SEMANTICS'
Set-PropertyValue -Object $objective.objective.queueSelectionGate -Name 'status' -Value 'issue_selected_r3_jsoup_entity_244'
Set-PropertyValue -Object $objective.objective.queueSelectionGate -Name 'currentAnchor' -Value $issue244
Set-PropertyValue -Object $objective.objective.queueSelectionGate -Name 'selectedIssue' -Value $issue244
Set-PropertyValue -Object $objective.objective.queueSelectionGate -Name 'candidateIssues' -Value @()
Set-PropertyValue -Object $objective.objective.queueSelectionGate -Name 'evidencePath' -Value $GateEvidencePath
Set-PropertyValue -Object $objective.objective.queueSelectionGate -Name 'candidateEvidencePath' -Value $discoveryPath
Set-PropertyValue -Object $objective.objective.queueSelectionGate -Name 'candidateCurrentHeadAuditEvidencePath' -Value $GateEvidencePath
Set-PropertyValue -Object $objective.objective.queueSelectionGate -Name 'candidateAuditStatus' -Value 'active_244_source_repair_running_r4_deferred'
Set-PropertyValue -Object $objective.objective.queueSelectionGate -Name 'candidateStatus' -Value 'running'
Set-PropertyValue -Object $objective.objective.queueSelectionGate -Name 'candidateGateStatus' -Value 'independent_evidence_gate_passed'
Set-PropertyValue -Object $objective.objective.queueSelectionGate -Name 'postTransitionEvidencePath' -Value $GateEvidencePath
Set-PropertyValue -Object $objective.objective.queueSelectionGate -Name 'selectionRule' -Value '244 is selected only by its independent fixed-Jsoup reference, five-case failure fixture, dynamic-response impact boundary, four-consumer matrix and explicit close condition. No second source issue is active and static evidence cannot become semantic_match.'
$sourceOrder = @($objective.objective.sourceClosureOrder | ForEach-Object { [string]$_ })
if ($sourceOrder -notcontains $issue244) { $sourceOrder += $issue244 }
Set-PropertyValue -Object $objective.objective -Name 'sourceClosureOrder' -Value $sourceOrder
Set-PropertyValue -Object $objective.executionTarget -Name 'currentIssue' -Value $issue244
Set-PropertyValue -Object $objective.executionTarget -Name 'nextIssues' -Value @()
Set-PropertyValue -Object $objective.executionTarget -Name 'statement' -Value '244 is active for source-only governance. The response-dependent entity gap spans typed DOM, Analyzer, generated JSVM and Rhino; R4 runtime and semantic qualification remain deferred.'
Set-PropertyValue -Object $objective.continuationTarget -Name 'activeBoundary' -Value '243 is statically inventoried at 79/41/38 and remains verifying. 244 is the sole active source issue with a five-case failing fixture and four-path consumer matrix.'
Set-PropertyValue -Object $objective.continuationTarget -Name 'nextTransition' -Value 'Complete 244 source repair and static contracts before selecting any later root cause; R4 remains deferred.'
Set-PropertyValue -Object $objective.continuationTarget.queueAudit -Name 'id' -Value 'R3-ISSUE-244-JSOUP-HTML-ENTITY-SOURCE-GATE'
Set-PropertyValue -Object $objective.continuationTarget.queueAudit -Name 'status' -Value 'candidate_activated_running'
Set-PropertyValue -Object $objective.continuationTarget.queueAudit -Name 'selectionPolicy' -Value '244 is the sole running source issue. 243 and earlier issues remain verifying for deferred R4; no second root cause may be activated before 244 source closure.'
Set-PropertyValue -Object $objective.continuationTarget.queueAudit -Name 'auditEvidencePath' -Value $GateEvidencePath
Set-PropertyValue -Object $objective.continuationTarget.queueAudit -Name 'candidateIssueId' -Value $issue244
Set-PropertyValue -Object $objective.continuationTarget.queueAudit -Name 'candidateIssues' -Value @()
Set-PropertyValue -Object $objective.continuationTarget.queueAudit -Name 'candidateGateStatus' -Value 'independent_evidence_gate_passed'
Set-PropertyValue -Object $objective.continuationTarget.queueAudit -Name 'candidateStatus' -Value 'running'
Set-PropertyValue -Object $objective.continuationTarget.queueAudit -Name 'currentAnchor' -Value $issue244
Set-PropertyValue -Object $objective.continuationTarget.queueAudit -Name 'selectedIssue' -Value $issue244
Set-PropertyValue -Object $objective.continuationTarget.queueAudit -Name 'activeIssueId' -Value $issue244
Set-PropertyValue -Object $objective.continuationTarget.queueAudit -Name 'failureWitnessPath' -Value $discoveryPath
Set-PropertyValue -Object $objective.continuationTarget.queueAudit -Name 'transitionEvidencePath' -Value $GateEvidencePath
Set-PropertyValue -Object $objective.continuationTarget.queueAudit -Name 'candidateTargetEvidencePath' -Value $TargetEvidencePath
Set-PropertyValue -Object $objective.continuationTarget.queueAudit -Name 'nextRequired' -Value 'Complete the shared generated entity data and all consumer bindings, then register static source closure while leaving R4 deferred.'
Set-PropertyValue -Object $objective -Name 'governanceSync' -Value ([pscustomobject][ordered]@{
    activeIssueId = $issue244
    queueSelectionCurrentAnchor = $issue244
    queueAuditCurrentAnchor = $issue244
    evidencePath = $GateEvidencePath
    updatedAt = $now
  })
Set-PropertyValue -Object $objective -Name 'nextAction' -Value 'Execute 244-ENTITY-02: generate the pinned Jsoup 1.16.2 entity dataset and route every V2 HTML entity consumer through the shared decoder contract. Do not run build, device, network, Harness or Legado runtime differential.'
Set-PropertyValue -Object $objective -Name 'activeTransition' -Value ([pscustomobject][ordered]@{
    fromIssue = $issue243
    toIssue = $issue244
    status = 'registered_static_only'
    evidencePath = $GateEvidencePath
    registrationEvidencePath = $RegistrationEvidencePath
    targetEvidencePath = $TargetEvidencePath
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    updatedAt = $now
  })
Write-AtomicJson -Path $objectivePath -Value $objective

Write-AtomicJson -Path $statePath -Value $state
$setObjectiveScript = Get-RepoPath -Path 'tools/legado-compat/Set-LegadoRefactorObjective.ps1'
$setObjectiveOutput = & (Get-Command pwsh).Source -NoLogo -NoProfile -NonInteractive -File $setObjectiveScript -StatePath (Get-RepoPath -Path $statePath) -ObjectivePath (Get-RepoPath -Path $objectivePath) -ActiveIssueId $issue244 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { throw ('Set-LegadoRefactorObjective failed:' + [Environment]::NewLine + $setObjectiveOutput) }
$updateScript = Get-RepoPath -Path 'tools/legado-compat/Update-LegadoGovernanceState.ps1'
$updateOutput = & (Get-Command pwsh).Source -NoLogo -NoProfile -NonInteractive -File $updateScript -StatePath (Get-RepoPath -Path $statePath) -IssueId $issue244 -IssueStatus running -TaskId $taskId -TaskStatus running -Summary ([string]$record244.summary) -CloseCondition ([string]$record244.closeCondition) -EvidencePath ([string]::Join(',', $transitionEvidence)) 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { throw ('Update-LegadoGovernanceState failed:' + [Environment]::NewLine + $updateOutput) }

$refreshedState = Read-StrictJson -Path $statePath
$refreshedObjective = Read-StrictJson -Path $objectivePath
$refreshed243 = Get-Issue -Issues @($refreshedState.governance.issues) -Id $issue243
$refreshed244 = Get-Issue -Issues @($refreshedState.governance.issues) -Id $issue244
Add-Check 'post_transition_queue' (
  [string]$refreshedState.governance.activeIssueId -eq $issue244 -and
  [string]$refreshedState.governance.currentSourceClosureBoundary -eq $issue244 -and
  [string]$refreshed243.status -eq 'verifying' -and
  [string]$refreshed244.status -eq 'running' -and
  [string]$refreshedObjective.authority.activeIssueId -eq $issue244 -and
  [string]$refreshedObjective.executionTarget.currentIssue -eq $issue244 -and
  [string]$refreshedState.governance.queuePreflight.activeIssueId -eq $issue244 -and
  [string]$refreshedObjective.objective.queueSelectionGate.currentAnchor -eq $issue244 -and
  [string]$refreshedObjective.continuationTarget.queueAudit.currentAnchor -eq $issue244 -and
  [string]$refreshedState.governance.refactorObjective.targetRevision -eq $revision -and
  -not [bool]$refreshedState.governance.semanticMatchAllowed
) 'machine state and objective atomically select 244 while 243 remains verifying.'

$gate.assertions = $script:assertions
$gate.checks = $script:checks.ToArray()
Write-AtomicJson -Path $GateEvidencePath -Value $gate
$registration = [pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_r3_jsoup_entity_243_to_244_transition_registration'
  status = 'registered'
  generatedAt = $now
  previousIssueId = $issue243
  issueId = $issue244
  targetRevision = $revision
  gateEvidencePath = $GateEvidencePath
  targetEvidencePath = $TargetEvidencePath
  fixturePath = $fixturePath
  failureWitnessPath = $discoveryPath
  impactClassification = 'dynamic_response_dependent'
  evidenceHashes = [pscustomobject][ordered]@{
    gate = Get-FileSha256 -Path $GateEvidencePath
    target = Get-FileSha256 -Path $TargetEvidencePath
  }
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  idempotent = $true
}
Write-AtomicJson -Path $RegistrationEvidencePath -Value $registration

[pscustomobject][ordered]@{
  status = 'registered'
  idempotent = $true
  previousIssueId = $issue243
  issueId = $issue244
  targetRevision = $revision
  gateEvidencePath = $GateEvidencePath
  registrationEvidencePath = $RegistrationEvidencePath
  targetEvidencePath = $TargetEvidencePath
  assertions = $script:assertions
  governanceUpdate = $updateOutput.Trim()
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
} | ConvertTo-Json -Depth 100
