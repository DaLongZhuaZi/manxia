[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-terminal-text-projection-context.json',
  [string]$FailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-jsoup-terminal-text-projection-pre-fix-20260810.json',
  [string]$PostFixContractPath = 'tools/legado-compat/evidence/contract-legado-jsoup-terminal-text-projection-post-fix-20260811.json',
  [string]$SourceFixPath = 'tools/legado-compat/evidence/v2-jsoup-terminal-text-projection-source-fix-20260811.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
$taskId = 'COMPAT-006'
$baselineHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$revision = '2026-08-11-actual-docs-source-refactor-jsoup-terminal-text-projection-static-closure'

function Get-RepoPath {
  param([Parameter(Mandatory = $true)][string]$Path)
  if ([System.IO.Path]::IsPathRooted($Path)) {
    return $Path
  }
  return Join-Path $RepositoryRoot ($Path.Replace('/', '\'))
}

function Read-StrictText {
  param([Parameter(Mandatory = $true)][string]$Path)
  $resolved = Get-RepoPath -Path $Path
  if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
    throw "required file is missing: $Path"
  }
  $bytes = [System.IO.File]::ReadAllBytes($resolved)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and
    $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw "UTF-8 BOM is not allowed: $Path"
  }
  return $strictUtf8.GetString($bytes)
}

function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$Path)
  return Read-StrictText -Path $Path | ConvertFrom-Json -Depth 100
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
    [System.IO.File]::WriteAllText(
      $temporary,
      ($Value | ConvertTo-Json -Depth 100),
      $noBomUtf8
    )
    Move-Item -LiteralPath $temporary -Destination $resolved -Force
  } finally {
    if (Test-Path -LiteralPath $temporary) {
      [System.IO.File]::Delete($temporary)
    }
  }
}

function Assert-Gate {
  param(
    [Parameter(Mandatory = $true)][bool]$Condition,
    [Parameter(Mandatory = $true)][string]$Detail
  )
  if (-not $Condition) {
    throw "243 terminal text projection source-fix gate failed: $Detail"
  }
}

function Get-ContractHash {
  param(
    [Parameter(Mandatory = $true)][object]$Contract,
    [Parameter(Mandatory = $true)][string]$Path
  )
  foreach ($entry in @($Contract.currentHeadHashes)) {
    if ([string]$entry.path -eq $Path) {
      return [string]$entry.sha256
    }
  }
  return ''
}

$statePath = 'tools/legado-compat/state/full-source-validation-state.json'
$objectivePath = 'tools/legado-compat/state/refactor-objective.json'
$state = Read-StrictJson -Path $statePath
$objective = Read-StrictJson -Path $objectivePath
$fixture = Read-StrictJson -Path $FixturePath
$failure = Read-StrictJson -Path $FailureWitnessPath
$contract = Read-StrictJson -Path $PostFixContractPath
$issue = @(
  $state.governance.issues |
    Where-Object { [string]$_.id -eq $issueId }
)[0]

Assert-Gate (
  [int]$state.baseline.sourceCount -eq 458 -and
  [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and
  [string]$state.baseline.legadoCommit -eq $legadoCommit
) 'frozen machine baseline drifted.'
Assert-Gate (
  [string]$state.governance.status -eq 'running' -and
  [string]$state.governance.activeTaskId -eq $taskId -and
  [string]$state.governance.activeIssueId -eq $issueId -and
  -not [bool]$state.governance.semanticMatchAllowed
) '243 is not the sole active static issue.'
Assert-Gate (
  $null -ne $issue -and [string]$issue.status -eq 'verifying'
) '243 must remain verifying.'
Assert-Gate (
  [string]$failure.status -eq 'failed' -and
  [string]$contract.status -eq 'passed' -and
  -not [bool]$failure.semanticMatchAllowed -and
  -not [bool]$contract.semanticMatchAllowed -and
  @($failure.runtimeActionsPerformed).Count -eq 0 -and
  @($contract.runtimeActionsPerformed).Count -eq 0
) 'pre-fix and post-fix evidence is incomplete or claims runtime semantic match.'
Assert-Gate (
  [string]$fixture.contract -eq 'legado_jsoup_terminal_text_projection' -and
  @($fixture.cases).Count -eq 6 -and
  [int]$contract.deterministicProjection.pathCount -eq 4 -and
  [int]$contract.deterministicProjection.fieldChecks -eq 72
) 'fixture or deterministic projection matrix drifted.'
Assert-Gate (
  [int]$contract.sourceUsage.textNodes.occurrences -eq 104 -and
  [int]$contract.sourceUsage.textNodes.sourceCount -eq 67 -and
  [int]$contract.sourceUsage.ownText.occurrences -eq 42 -and
  [int]$contract.sourceUsage.ownText.sourceCount -eq 25 -and
  [int]$contract.sourceUsage.jsOwnText.occurrences -eq 1 -and
  [int]$contract.sourceUsage.jsOwnText.sourceCount -eq 1
) 'frozen terminal projection usage matrix drifted.'

$changedPaths = @($contract.changedPaths | ForEach-Object { [string]$_ })
$currentHeadHashes = New-Object 'System.Collections.Generic.List[object]'
foreach ($changedPath in $changedPaths) {
  $resolved = Get-RepoPath -Path $changedPath
  Assert-Gate (
    Test-Path -LiteralPath $resolved -PathType Leaf
  ) "changed path is missing: $changedPath"
  $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $resolved).Hash.ToUpperInvariant()
  $expectedHash = Get-ContractHash -Contract $contract -Path $changedPath
  Assert-Gate (
    $expectedHash.Length -eq 64 -and $actualHash -eq $expectedHash
  ) "current-head hash drifted after post-fix contract: $changedPath"
  [void]$currentHeadHashes.Add([pscustomobject][ordered]@{
      path = $changedPath
      sha256 = $actualHash
    })
}

$existingSourceFixPath = Get-RepoPath -Path $SourceFixPath
if ([string]$objective.targetRevision -eq $revision -and
  (Test-Path -LiteralPath $existingSourceFixPath -PathType Leaf)) {
  [pscustomobject][ordered]@{
    status = 'already_registered'
    issueId = $issueId
    targetRevision = $revision
    sourceFixEvidencePath = $SourceFixPath
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    idempotent = $true
  } | ConvertTo-Json -Depth 100
  return
}

$backupPaths = @(
  'entry/src/main/ets/Framework/Novel/LegadoJsEngine.ets.bak_20260810_issue243_text_projection',
  'entry/src/main/ets/Framework/Novel/RhinoWasmExecutor.ets.bak_20260810_issue243_text_projection',
  'entry/src/main/resources/rawfile/rhino_sandbox/jsoup_impl.js.bak_20260810_issue243_text_projection'
)
foreach ($backupPath in $backupPaths) {
  Assert-Gate (
    Test-Path -LiteralPath (Get-RepoPath -Path $backupPath) -PathType Leaf
  ) "historical backup is missing: $backupPath"
}

$sourceFix = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'source_fix'
  issueId = $issueId
  status = 'source_closed_static_only'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{
    sourceCount = 458
    sourcePackageSha256 = $baselineHash
    legadoCommit = $legadoCommit
    jsoupVersion = '1.16.2'
  }
  targetRevision = $revision
  extends = 'tools/legado-compat/evidence/v2-jsoup-text-own-context-source-fix-20260810.json'
  failureEvidence = @($FailureWitnessPath)
  staticContract = $PostFixContractPath
  changedPaths = $changedPaths
  backupPaths = $backupPaths
  currentHeadHashes = $currentHeadHashes.ToArray()
  affectedCases = @($fixture.cases | ForEach-Object { [string]$_.id })
  affectedSourceSet = $contract.sourceUsage
  rootCause = [pscustomobject][ordered]@{
    category = '规则结果投影'
    legadoSemantics = 'Pinned Legado keeps Element.text(), Element.ownText(), and direct TextNode.text() projections distinct; textNodes values are Java-trimmed independently and joined with LF.'
    v2BeforeFix = 'Generated JSVM collapsed textNodes into text/eachText, ownText was absent on some shims, DOM textContent and regex tag stripping changed Jsoup whitespace, and parserless Rhino had no direct TextNode projection.'
    v2AfterFix = 'Typed DOM, Analyzer, ArkWeb, generated JSVM, Rhino inline, and Rhino standalone share explicit text/ownText/textNodes consumers. Block and br boundaries use ASCII space, direct TextNodes are normalized independently, and parserless Rhino uses a structured fallback tree.'
    defectCaughtByContract = 'The first deterministic post-fix run exposed an undefined legadoIsPreserveWhitespaceTag call in parserless Rhino; the shared preserve-tag primitive was then added before registration.'
  }
  consumerMatrix = [pscustomobject][ordered]@{
    analyzer = 'LegadoRuleAnalyzer -> parsed text/textNodes/ownText terminal projection'
    typedDom = 'HTMLElement + LegadoTextNormalization + LegadoHtmlBridge'
    arkWeb = 'legado_runtime.html terminal rules and direct JS wrappers'
    jsvm = 'LegadoJsEngine generated compatibility prelude and all rule consumers'
    rhinoInline = 'RhinoWasmExecutor inline sandbox compatibility layer'
    rhinoStandalone = 'rhino_sandbox/jsoup_impl.js DOM and parserless branches'
    workflows = 'Search/Explore/BookInfo/Toc/Content/File/Review rules that terminate in text, textNodes, or ownText'
    sourceCoverage = '104 @textNodes occurrences across 67 sources; 42 @ownText occurrences across 25 sources; one direct JS ownText call'
    legado = 'AnalyzeByJSoup.getResultLast at fixed commit'
  }
  supersededHistoricalFixture = [pscustomobject][ordered]@{
    path = 'tools/legado-compat/fixtures/legado-jsoup-text-whitespace.json'
    reason = 'Its historical br-as-LF expectation contradicts Jsoup 1.16.2 Element.text()/ownText() and is retained only as historical evidence.'
  }
  knownDeferredGap = [pscustomobject][ordered]@{
    capability = 'complete Jsoup HTML named-entity set and HTML5 entity edge semantics'
    disposition = 'register as a separate planned root cause; do not claim entity-wide compatibility from the six basic cases'
  }
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_243_terminal_text_projection_source_fix_static_only;R4_app_runtime_build_device_harness_and_legado_diff_deferred'
  closeCondition = 'R4 must execute the six terminal projection cases and affected source sets through typed Analyzer, ArkWeb, JSVM, Rhino, deterministic 458-source Harness, fixed-Legado differential, build and device gates before 243 can leave verifying.'
}
Write-AtomicJson -Path $SourceFixPath -Value $sourceFix

$now = [DateTimeOffset]::UtcNow.ToString('o')
Set-PropertyValue -Object $objective -Name 'lastReviewedAt' -Value $now
Set-PropertyValue -Object $objective -Name 'targetRevision' -Value $revision
Set-PropertyValue -Object $objective -Name 'continuationMode' -Value 'R3_ISSUE_243_TERMINAL_TEXT_PROJECTION_STATIC_CLOSED_WAIT_R4'
Set-PropertyValue -Object $objective.authority -Name 'activeIssueId' -Value $issueId
Set-PropertyValue -Object $objective.authority -Name 'activeIssueSelection' -Value 'full-source-validation-state.json remains authoritative; 243 remains the sole active source-closure issue. Terminal text projection has static source closure only, semanticMatchAllowed remains false, and R4 is deferred.'
Set-PropertyValue -Object $objective.objective -Name 'activeIssueRule' -Value 'All V2 execution paths must preserve Jsoup 1.16.2 text, ownText, and direct textNodes as separate APIs with explicit terminal consumers; basic entity cases do not prove complete entity compatibility.'
Set-PropertyValue -Object $objective.executionTarget -Name 'statement' -Value '243 terminal text projection is statically closed across typed DOM, Analyzer string projection, ArkWeb, generated JSVM, Rhino inline and Rhino standalone. Runtime, full Harness, Legado differential, build and device gates remain deferred.'
Set-PropertyValue -Object $objective -Name 'nextAction' -Value 'Register the separate complete HTML entity semantic gap as planned, then continue the sole 243 source audit without activating a second issue.'
$plan = @($objective.continuationPlan)
if (-not @($plan | Where-Object { [string]$_.id -eq '243-SP-75' })) {
  $plan += [pscustomobject][ordered]@{
    id = '243-SP-75'
    status = 'completed'
    action = '统一 typed DOM、Analyzer、ArkWeb、JSVM、Rhino inline 与 standalone 的 text/ownText/textNodes 投影，修复生成脚本 LF 转义和 parserless Rhino 结构化 fallback；固定包影响为 67/25/1 条书源集合。'
    evidence = @($FixturePath, $FailureWitnessPath, $PostFixContractPath, $SourceFixPath)
  }
  $plan += [pscustomobject][ordered]@{
    id = '243-SP-76'
    status = 'deferred'
    action = 'R4 执行六个文本投影案例、67 条 textNodes 与 25 条 ownText 书源集合、458 条 Harness、固定 Legado 差分、构建和真机验证。'
  }
  Set-PropertyValue -Object $objective -Name 'continuationPlan' -Value $plan
}
Write-AtomicJson -Path $objectivePath -Value $objective

$registerPath = 'tools/legado-compat/Register-LegadoJsoupTerminalTextProjectionSourceFix.ps1'
$preFixScriptPath = 'tools/legado-compat/Test-LegadoJsoupTerminalTextProjectionPreFixContract.ps1'
$postFixScriptPath = 'tools/legado-compat/Test-LegadoJsoupTerminalTextProjectionPostFixContract.ps1'
$evidence = @(
  $FixturePath,
  $FailureWitnessPath,
  $PostFixContractPath,
  $SourceFixPath,
  $preFixScriptPath,
  $postFixScriptPath,
  $registerPath,
  'tools/legado-compat/fixtures/legado-jsoup-text-whitespace.json',
  'entry/src/main/ets/libs/htmlparser/LegadoTextNormalization.ets',
  'entry/src/main/ets/libs/htmlparser/HTMLElement.ets',
  'entry/src/main/ets/libs/htmlparser/LegadoHtmlBridge.ets',
  'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets',
  'entry/src/main/resources/rawfile/legado_runtime.html',
  'entry/src/main/ets/Framework/Novel/LegadoJsEngine.ets',
  'entry/src/main/ets/Framework/Novel/RhinoWasmExecutor.ets',
  'entry/src/main/resources/rawfile/rhino_sandbox/jsoup_impl.js',
  'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
) + $backupPaths
$summary = '243 terminal text projection now keeps Jsoup text, ownText and direct textNodes distinct across typed DOM, Analyzer, ArkWeb, JSVM and both Rhino paths. Frozen usage is 104 textNodes occurrences/67 sources, 42 ownText occurrences/25 sources, and one direct JS ownText source. Static deterministic matrix is 72/72; runtime, full Harness, Legado differential, build and device validation remain deferred.'
$updateScript = Get-RepoPath -Path 'tools/legado-compat/Update-LegadoGovernanceState.ps1'
$updateOutput = & (Get-Command pwsh).Source -NoLogo -NoProfile -NonInteractive -File $updateScript -StatePath (Get-RepoPath -Path $statePath) -IssueId $issueId -IssueStatus verifying -TaskId $taskId -TaskStatus running -Summary $summary -CloseCondition ([string]$sourceFix.closeCondition) -EvidencePath ([string]::Join(',', $evidence)) 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
  throw ('Update-LegadoGovernanceState failed:' + [Environment]::NewLine + $updateOutput)
}

[pscustomobject][ordered]@{
  status = 'registered'
  issueId = $issueId
  targetRevision = $revision
  sourceFixEvidencePath = $SourceFixPath
  governanceUpdate = $updateOutput.Trim()
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
} | ConvertTo-Json -Depth 100
