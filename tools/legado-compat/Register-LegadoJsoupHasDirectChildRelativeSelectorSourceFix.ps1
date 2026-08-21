[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-has-direct-child-relative-selector-context.json',
  [string]$FailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-jsoup-has-direct-child-relative-selector-pre-fix-20260810.json',
  [string]$PostFixContractPath = 'tools/legado-compat/evidence/contract-legado-jsoup-has-direct-child-relative-selector-post-fix-20260810.json',
  [string]$CurrentHeadAuditPath = 'tools/legado-compat/evidence/v2-jsoup-has-direct-child-relative-selector-current-head-audit-20260810.json',
  [string]$SourceFixPath = 'tools/legado-compat/evidence/v2-jsoup-has-direct-child-relative-selector-source-fix-20260810.json'
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
$analyzerPath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
$snapshotPath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets.bak_20260810_has_direct_child_relative_selector'
$legadoPath = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'

function Get-RepoPath { param([Parameter(Mandatory = $true)][string]$RelativePath); if ([System.IO.Path]::IsPathRooted($RelativePath)) { return $RelativePath }; return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\')) }
function Read-StrictText { param([Parameter(Mandatory = $true)][string]$RelativePath); $path = Get-RepoPath $RelativePath; if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing text: $RelativePath" }; return $strictUtf8.GetString([System.IO.File]::ReadAllBytes($path)) }
function Read-StrictJson { param([Parameter(Mandatory = $true)][string]$RelativePath); return (Read-StrictText $RelativePath | ConvertFrom-Json -Depth 100) }
function Get-PropertyValue { param([object]$Object, [string]$Name, [object]$Default = $null); if ($null -eq $Object) { return $Default }; $property = $Object.PSObject.Properties[$Name]; if ($null -eq $property -or $null -eq $property.Value) { return $Default }; return $property.Value }
function Set-PropertyValue { param([Parameter(Mandatory = $true)][object]$Object, [Parameter(Mandatory = $true)][string]$Name, [object]$Value); if ($null -eq $Object.PSObject.Properties[$Name]) { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force } else { $Object.$Name = $Value } }
function Assert-Gate { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw "243 :has direct-child relative selector source-fix gate failed: $Message" } }
function Get-TextHash { param([Parameter(Mandatory = $true)][string]$Text); $sha = [System.Security.Cryptography.SHA256]::Create(); try { return ([System.BitConverter]::ToString($sha.ComputeHash($strictUtf8.GetBytes($Text)))).Replace('-', '').ToUpperInvariant() } finally { $sha.Dispose() } }
function Write-AtomicJson { param([Parameter(Mandatory = $true)][string]$RelativePath, [Parameter(Mandatory = $true)][object]$Value); $path = Get-RepoPath $RelativePath; $directory = Split-Path -Parent $path; if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }; $temporary = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"; try { [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8); Move-Item -LiteralPath $temporary -Destination $path -Force } finally { if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) } } }

$statePath = 'tools/legado-compat/state/full-source-validation-state.json'
$objectivePath = 'tools/legado-compat/state/refactor-objective.json'
$state = Read-StrictJson $statePath
$objective = Read-StrictJson $objectivePath
$fixture = Read-StrictJson $FixturePath
$failure = Read-StrictJson $FailureWitnessPath
$contract = Read-StrictJson $PostFixContractPath
$audit = Read-StrictJson $CurrentHeadAuditPath
$issue = @($state.governance.issues | Where-Object { [string]$_.id -eq $issueId })[0]

Assert-Gate ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'frozen baseline drifted.'
Assert-Gate ([string]$state.governance.status -eq 'running' -and [string]$state.governance.activeTaskId -eq $taskId -and [string]$state.governance.activeIssueId -eq $issueId -and -not [bool]$state.governance.semanticMatchAllowed) '243 must remain the sole active static issue.'
Assert-Gate ($null -ne $issue -and [string]$issue.status -eq 'verifying') '243 must remain verifying; source closure cannot claim runtime completion.'
Assert-Gate ([string]$fixture.issueId -eq $issueId -and @($fixture.cases).Count -eq 4) 'direct-child relative selector fixture binding drifted.'
Assert-Gate ([string]$failure.status -eq 'failed' -and @($failure.runtimeActionsPerformed).Count -eq 0 -and -not [bool]$failure.semanticMatchAllowed) 'failure witness must remain failed and static-only.'
Assert-Gate ([string]$contract.status -eq 'passed' -and [int]$contract.assertions -ge 15 -and @($contract.runtimeActionsPerformed).Count -eq 0 -and -not [bool]$contract.semanticMatchAllowed) 'post-fix contract must remain static-only.'
Assert-Gate ([string]$audit.status -eq 'passed' -and [int]$audit.assertions -ge 8 -and @($audit.runtimeActionsPerformed).Count -eq 0 -and -not [bool]$audit.semanticMatchAllowed) 'current-head audit must remain static-only.'

$analyzer = Read-StrictText $analyzerPath
$snapshot = Read-StrictText $snapshotPath
$legado = Read-StrictText $legadoPath
$sourceFix = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'source_fix'
  issueId = $issueId
  status = 'source_closed_static_only'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  extends = 'tools/legado-compat/evidence/v2-jsoup-has-relative-selector-source-fix-20260809.json'
  rootCause = [pscustomobject][ordered]@{
    category = '规则解析或编译'
    originalSemantics = 'Legado AnalyzeByJSoup delegates the complete CSS rule to Jsoup Element.select; in a :has(>relative-selector) predicate the first selector compound must match a direct child, while later combinators may continue below that child.'
    v2BeforeFix = 'The string fallback queried each direct-child wrapper and accepted any non-wrapper result. A nested span.foo therefore satisfied >span.foo even when the direct child was a div.'
    v2AfterFix = 'The string fallback extracts the first top-level selector subject, verifies it matches the synthetic root child at its exact occurrence, then evaluates the complete relative selector so descendant continuation remains supported.'
    evidence = @($FailureWitnessPath, $PostFixContractPath, $CurrentHeadAuditPath, $FixturePath)
  }
  changedPaths = @($analyzerPath)
  consumerMatrix = [pscustomobject][ordered]@{ stringFallback = $analyzerPath; legado = $legadoPath }
  fixturePath = $FixturePath
  failureEvidence = @($FailureWitnessPath)
  staticContract = $PostFixContractPath
  currentHeadAudit = $CurrentHeadAuditPath
  currentHeadHashes = [pscustomobject][ordered]@{ $analyzerPath = Get-TextHash $analyzer; $snapshotPath = Get-TextHash $snapshot; $legadoPath = Get-TextHash $legado }
  assertions = [int]$contract.assertions + [int]$audit.assertions
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_243_direct_child_relative_selector_source_fix_static_only;R4_runtime_build_device_and_legado_diff_deferred'
  closeCondition = 'R4 must execute the four direct-child relative-selector cases together with the existing 243 :has descendant cases, the affected 243 rule/source set, deterministic 458-source Harness, fixed-Legado differential, build and device gates before 243 can leave verifying.'
}
Write-AtomicJson $SourceFixPath $sourceFix

$now = [DateTimeOffset]::UtcNow.ToString('o')
Set-PropertyValue $objective 'lastReviewedAt' $now
Set-PropertyValue $objective 'targetRevision' '2026-08-10-actual-docs-source-refactor-jsoup-has-direct-child-subject-static-closure'
Set-PropertyValue $objective 'continuationMode' 'R3_ISSUE_243_HAS_DIRECT_CHILD_SUBJECT_STATIC_CLOSED_WAIT_R4'
Set-PropertyValue $objective.authority 'activeIssueId' $issueId
Set-PropertyValue $objective.authority 'activeIssueSelection' 'full-source-validation-state.json remains the only queue; 243 remains the sole active source-closure issue. The :has(>) string fallback now verifies the first selector subject at the direct-child occurrence before allowing descendant continuation; semanticMatchAllowed remains false and R4 is deferred.'
Set-PropertyValue $objective.objective 'currentWorkstream' 'R3-ISSUE-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
Set-PropertyValue $objective.objective 'activeIssueRule' '243 standard CSS pseudo compatibility now verifies the first subject of :has(>) against the direct child while preserving descendant continuation for selectors such as >div span; runtime and R4 gates remain deferred.'
Set-PropertyValue $objective.executionTarget 'statement' '243 :has direct-child subject semantics are statically closed for the string fallback; runtime, full Harness, Legado differential, build and device gates remain deferred.'
Set-PropertyValue $objective 'nextAction' '243 :has direct-child subject static closure is registered; continue one-root-cause source audit while R4 remains deferred.'
$plan = @($objective.continuationPlan)
if (-not @($plan | Where-Object { [string]$_.id -eq '243-SP-35' })) {
  $plan += [pscustomobject][ordered]@{ id = '243-SP-35'; status = 'completed'; action = '修复字符串回退 :has(>) 对直接子节点主体的判定：先按顶层选择器主体校验直接子 occurrence，再保留直接子以下的后代组合器；登记直接子与嵌套子对照见证。'; evidence = @($FailureWitnessPath, $PostFixContractPath, $CurrentHeadAuditPath, $SourceFixPath) }
  $plan += [pscustomobject][ordered]@{ id = '243-SP-36'; status = 'deferred'; action = 'R4 执行 :has(>) 直接子主体/后代延续等价类、243 影响集合、458 条 Harness、Legado 差分、构建和真机验证。' }
  Set-PropertyValue $objective 'continuationPlan' $plan
}
Write-AtomicJson $objectivePath $objective

$updateScript = Get-RepoPath 'tools/legado-compat/Update-LegadoGovernanceState.ps1'
$evidence = @(
  $FixturePath,
  $FailureWitnessPath,
  $PostFixContractPath,
  $CurrentHeadAuditPath,
  $SourceFixPath,
  $snapshotPath,
  'tools/legado-compat/Test-LegadoJsoupHasDirectChildRelativeSelectorFailureWitness.ps1',
  'tools/legado-compat/Test-LegadoJsoupHasDirectChildRelativeSelectorPostFixContract.ps1',
  'tools/legado-compat/Test-LegadoJsoupHasDirectChildRelativeSelectorCurrentHeadAudit.ps1',
  'tools/legado-compat/Register-LegadoJsoupHasDirectChildRelativeSelectorSourceFix.ps1',
  $analyzerPath,
  $legadoPath
)
$summary = '243 :has(>) direct-child subject semantics are statically closed: the string fallback now verifies the first top-level selector subject at the exact direct-child occurrence before accepting descendant continuation. Direct, nested and deeper cases are registered; R4 remains deferred.'
$evidenceArgument = [string]::Join(',', $evidence)
$updateOutput = & (Get-Command pwsh).Source -NoLogo -NoProfile -NonInteractive -File $updateScript -IssueId $issueId -IssueStatus verifying -TaskId $taskId -TaskStatus running -Summary $summary -CloseCondition ([string]$sourceFix.closeCondition) -EvidencePath $evidenceArgument 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { throw "Update-LegadoGovernanceState failed:`n$updateOutput" }

[pscustomobject][ordered]@{
  status = 'registered'
  issueId = $issueId
  sourceFixEvidencePath = $SourceFixPath
  assertions = $sourceFix.assertions
  governanceUpdate = $updateOutput.Trim()
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
} | ConvertTo-Json -Depth 100
