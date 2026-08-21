[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-arkweb-jsoup-dom-document-root-child-pseudo.json',
  [string]$FailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-arkweb-jsoup-dom-document-root-child-pseudo-pre-fix-20260810.json',
  [string]$PostFixContractPath = 'tools/legado-compat/evidence/contract-legado-arkweb-jsoup-dom-document-root-child-pseudo-post-fix-20260810.json',
  [string]$SourceFixPath = 'tools/legado-compat/evidence/v2-arkweb-jsoup-dom-document-root-child-pseudo-source-fix-20260810.json'
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
$runtimePath = 'entry/src/main/resources/rawfile/legado_runtime.html'
$legadoPath = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'

function Get-RepoPath { param([Parameter(Mandatory = $true)][string]$Path); return Join-Path $RepositoryRoot ($Path.Replace('/', '\')) }
function Read-StrictText { param([Parameter(Mandatory = $true)][string]$Path); $resolved = Get-RepoPath $Path; $bytes = [System.IO.File]::ReadAllBytes($resolved); if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $Path" }; return $strictUtf8.GetString($bytes) }
function Read-StrictJson { param([Parameter(Mandatory = $true)][string]$Path); return (Read-StrictText $Path | ConvertFrom-Json -Depth 100) }
function Set-PropertyValue { param([Parameter(Mandatory = $true)][object]$Object, [Parameter(Mandatory = $true)][string]$Name, [object]$Value); if ($null -eq $Object.PSObject.Properties[$Name]) { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force } else { $Object.$Name = $Value } }
function Assert-Gate { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw "ArkWeb 243 source-fix gate failed: $Message" } }
function Write-AtomicJson { param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value); $resolved = Get-RepoPath $Path; $directory = Split-Path -Parent $resolved; if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }; $temporary = "$resolved.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"; try { [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8); Move-Item -LiteralPath $temporary -Destination $resolved -Force } finally { if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) } } }

$statePath = 'tools/legado-compat/state/full-source-validation-state.json'
$objectivePath = 'tools/legado-compat/state/refactor-objective.json'
$state = Read-StrictJson $statePath
$objective = Read-StrictJson $objectivePath
$fixture = Read-StrictJson $FixturePath
$failure = Read-StrictJson $FailureWitnessPath
$contract = Read-StrictJson $PostFixContractPath
$runtime = Read-StrictText $runtimePath
$legado = Read-StrictText $legadoPath
$issue = @($state.governance.issues | Where-Object { [string]$_.id -eq $issueId })[0]

Assert-Gate ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'frozen baseline drifted.'
Assert-Gate ([string]$state.governance.status -eq 'running' -and [string]$state.governance.activeTaskId -eq $taskId -and [string]$state.governance.activeIssueId -eq $issueId -and -not [bool]$state.governance.semanticMatchAllowed) '243 must remain the sole active static issue.'
Assert-Gate ($null -ne $issue -and [string]$issue.status -eq 'verifying') '243 must remain verifying.'
Assert-Gate ([string]$failure.status -eq 'failed' -and [string]$contract.status -eq 'passed' -and @($failure.runtimeActionsPerformed).Count -eq 0 -and @($contract.runtimeActionsPerformed).Count -eq 0 -and -not [bool]$contract.semanticMatchAllowed) 'failure witness and post-fix contract must remain static-only.'
Assert-Gate ($runtime.Contains("holder.setAttribute('data-legado-document-root', '1');") -and $runtime.Contains('legadoStandardDocumentPseudoNames') -and $runtime.Contains('selectionDocumentRoot') -and $runtime.Contains('predicateNode')) 'ArkWeb source fix is missing.'
Assert-Gate ($legado.Contains('temp.select(ruleStr)')) 'pinned Legado selector consumer is missing.'

$closeCondition = 'R4 must execute all ArkWeb root/context cases, the affected 243 source set, deterministic 458-source Harness, fixed-Legado differential, build and device gates before 243 can leave verifying.'
$hashes = [ordered]@{}
foreach ($path in @($runtimePath, $legadoPath)) { $hashes[$path] = (Get-FileHash -Algorithm SHA256 -LiteralPath (Get-RepoPath $path)).Hash.ToUpperInvariant() }
$sourceFix = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'source_fix'
  issueId = $issueId
  status = 'source_closed_static_only'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  extends = 'tools/legado-compat/evidence/v2-jsoup-dom-document-root-child-pseudo-source-fix-20260810.json'
  failureEvidence = @($FailureWitnessPath)
  staticContract = $PostFixContractPath
  changedPaths = @($runtimePath)
  currentHeadHashes = $hashes
  affectedSourceOrdinals = @($fixture.affectedSourceOrdinals)
  rootCause = [pscustomobject][ordered]@{
    category = '规则解析或编译'
    before = 'ArkWeb parsed response fragments below a detached div and allowed native querySelectorAll to treat that wrapper as a normal element parent. Top-level child/of-type pseudos diverged from the pinned Jsoup Document boundary.'
    after = 'The holder is marked as a synthetic Document; standard child/of-type pseudos are extracted for manual evaluation only in that context, direct holder children fail closed, and :has/:not preserve their intended context.'
    legadoReference = 'Pinned Legado AnalyzeByJSoup delegates terminal selection to Jsoup Element.select; Jsoup child/of-type evaluators reject nodes whose parent is Document.'
  }
  consumerMatrix = [pscustomobject][ordered]@{ arkWeb = $runtimePath; legado = $legadoPath; stringFallback = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'; dom = 'entry/src/main/ets/libs/htmlparser/HTMLElement.ets' }
  assertions = [int]$contract.assertions
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_243_arkweb_document_root_source_fix_static_only;R4_runtime_build_device_and_legado_diff_deferred'
  closeCondition = $closeCondition
}
Write-AtomicJson $SourceFixPath $sourceFix

$now = [DateTimeOffset]::UtcNow.ToString('o')
Set-PropertyValue $objective 'lastReviewedAt' $now
Set-PropertyValue $objective 'targetRevision' '2026-08-10-actual-docs-source-refactor-arkweb-jsoup-document-root-static-closure'
Set-PropertyValue $objective 'continuationMode' 'R3_ISSUE_243_ARKWEB_DOCUMENT_ROOT_STATIC_CLOSED_WAIT_R4'
Set-PropertyValue $objective.authority 'activeIssueId' $issueId
Set-PropertyValue $objective.authority 'activeIssueSelection' 'full-source-validation-state.json remains the only queue; 243 remains the sole active source-closure issue. DOM and ArkWeb synthetic Document-root child/of-type semantics are statically closed; semanticMatchAllowed remains false and R4 is deferred.'
Set-PropertyValue $objective.objective 'activeIssueRule' '243 standard CSS pseudo compatibility covers string fallback, DOM Matcher and ArkWeb: synthetic Document roots must fail closed for child/of-type pseudos, real-element and :has contexts retain their own positions, and no native-selector shortcut may hide the boundary.'
Set-PropertyValue $objective.executionTarget 'statement' '243 direct-child context, top-level split, regex-class pseudo nesting, :has relative-selector context, :not ancestor context, duplicate occurrence identity, bulk offset projection, sibling combinators, of-type position semantics, selector-group occurrence identity, nested marker restoration, direct-child marker lifetime, synthetic DOM roots in the DOM parser, ArkWeb holder Document-root child/of-type semantics and ArkWeb :has/:not context propagation are statically closed and registered; runtime, full Harness, Legado differential, build and device gates remain deferred.'
Set-PropertyValue $objective 'nextAction' '243 ArkWeb synthetic Document-root pseudo source closure is registered; continue one-root-cause source audit while R4 remains deferred.'
$plan = @($objective.continuationPlan)
if (-not @($plan | Where-Object { [string]$_.id -eq '243-SP-53' })) {
  $plan += [pscustomobject][ordered]@{ id = '243-SP-53'; status = 'completed'; action = '修复 ArkWeb legadoGetStringListSingle 的 holder 与 Jsoup Document 根边界：合成根标记、标准 child/of-type 手动判定、:has 相对根和 :not 继承上下文。'; evidence = @($FailureWitnessPath, $PostFixContractPath, $SourceFixPath) }
  $plan += [pscustomobject][ordered]@{ id = '243-SP-54'; status = 'deferred'; action = 'R4 执行 ArkWeb 根边界与嵌套上下文案例、243 影响集合、458 条 Harness、Legado 差分、构建和真机验证。' }
  Set-PropertyValue $objective 'continuationPlan' $plan
}
Write-AtomicJson $objectivePath $objective

$updateScript = Get-RepoPath 'tools/legado-compat/Update-LegadoGovernanceState.ps1'
$evidence = @($FixturePath, $FailureWitnessPath, $PostFixContractPath, $SourceFixPath, $runtimePath, $legadoPath, 'tools/legado-compat/Test-LegadoArkWebJsoupDocumentRootChildPseudoFailureWitness.ps1', 'tools/legado-compat/Test-LegadoArkWebJsoupDocumentRootChildPseudoPostFixContract.ps1', 'tools/legado-compat/Register-LegadoArkWebJsoupDocumentRootChildPseudoSourceFix.ps1')
$summary = '243 ArkWeb synthetic Document-root semantics are statically closed: legadoGetStringListSingle marks its holder, standard child/of-type pseudos are manually evaluated only in that context, direct holder children fail closed, and :has/:not preserve their intended contexts. Runtime, full Harness, Legado differential, build and device validation remain deferred.'
$updateOutput = & (Get-Command pwsh).Source -NoLogo -NoProfile -NonInteractive -File $updateScript -IssueId $issueId -IssueStatus verifying -TaskId $taskId -TaskStatus running -Summary $summary -CloseCondition $closeCondition -EvidencePath ([string]::Join(',', $evidence)) 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { throw "Update-LegadoGovernanceState failed:`n$updateOutput" }
[pscustomobject][ordered]@{ status = 'registered'; issueId = $issueId; sourceFixEvidencePath = $SourceFixPath; assertions = [int]$contract.assertions; governanceUpdate = $updateOutput.Trim(); runtimeActionsPerformed = @(); semanticMatchAllowed = $false } | ConvertTo-Json -Depth 100
