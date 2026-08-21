[CmdletBinding()]
param([string]$RepoRoot = '', [string]$ResultPath = '')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:AssertionCount = 0

function Assert-Contract {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "V2 Hypium full-source runner contract failed: $Message" }
  $script:AssertionCount++
}

function Read-Utf8Script {
  param([string]$Path)
  Assert-Contract (Test-Path -LiteralPath $Path -PathType Leaf) "missing script: $Path"
  return [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false, $true))
}

function Assert-ParserClean {
  param([string]$Path)
  $tokens = $null
  $errors = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
  Assert-Contract ($errors.Count -eq 0) "PowerShell parse error in $Path"
}

if ($RepoRoot.Length -eq 0) { $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path } else { $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path }
if ($ResultPath.Length -eq 0) { $ResultPath = Join-Path $RepoRoot 'tools\legado-compat\evidence\v2-hypium-full-source-runner-contract.json' }

$legacyEntry = Join-Path $RepoRoot 'tools\legado-compat\Invoke-LegadoV2FullSourceDeviceRunner.ps1'
$compatibilityRunner = Join-Path $RepoRoot 'tools\legado-compat\Invoke-LegadoCompatibility.ps1'
$implementation = Join-Path $RepoRoot 'tools\legado-compat\Invoke-LegadoV2HypiumFullSourceDeviceRunner.ps1'
$evidencePathsModule = Join-Path $RepoRoot 'tools\legado-compat\LegadoHypiumEvidencePaths.psm1'
$detachedStarter = Join-Path $RepoRoot 'tools\legado-compat\Start-LegadoV2HypiumFullSourceDeviceRunner.ps1'
$runMonitor = Join-Path $RepoRoot 'tools\legado-compat\Get-LegadoV2HypiumFullSourceDeviceRun.ps1'
$driver = Join-Path $RepoRoot 'tools\legado-compat\Invoke-LegadoV2HypiumNavigation.py'
$stateModule = Join-Path $RepoRoot 'tools\legado-compat\LegadoFullSourceState.psm1'
$webViewExecutor = Join-Path $RepoRoot 'entry\src\main\ets\Framework\Novel\LegadoWebViewExecutor.ets'
$webViewComponent = Join-Path $RepoRoot 'entry\src\main\ets\Framework\Novel\LegadoWebViewComponent.ets'
$requestPipeline = Join-Path $RepoRoot 'entry\src\main\ets\Framework\Novel\LegadoRequestPipeline.ets'
$ruleAnalyzer = Join-Path $RepoRoot 'entry\src\main\ets\Framework\Novel\LegadoRuleAnalyzer.ets'
$htmlBridge = Join-Path $RepoRoot 'entry\src\main\ets\libs\htmlparser\LegadoHtmlBridge.ets'
$compatibilityTypes = Join-Path $RepoRoot 'entry\src\main\ets\Framework\Novel\LegadoCompatibilityTypes.ets'
$workflowOrchestrator = Join-Path $RepoRoot 'entry\src\main\ets\Framework\Novel\LegadoWorkflowOrchestrator.ets'
$sourceManager = Join-Path $RepoRoot 'entry\src\main\ets\Framework\Novel\NovelSourceManager.ets'
$dataManager = Join-Path $RepoRoot 'entry\src\main\ets\Framework\Novel\NovelDataManager.ets'
$automationIdentity = Join-Path $RepoRoot 'entry\src\main\ets\Framework\Novel\LegadoSourceAutomationIdentity.ets'
$sourceManagementPage = Join-Path $RepoRoot 'entry\src\main\ets\pages\NovelSourceManagementPage.ets'
$bookSourceTabContent = Join-Path $RepoRoot 'entry\src\main\ets\Framework\Components\BookSourceTabContent.ets'
$exploreDetailNavigator = Join-Path $RepoRoot 'entry\src\main\ets\Framework\Novel\LegadoExploreDetailNavigator.ets'
$searchPage = Join-Path $RepoRoot 'entry\src\main\ets\pages\NovelSearchPage.ets'
$unifiedDetailPage = Join-Path $RepoRoot 'entry\src\main\ets\pages\UnifiedDetailPage.ets'
$novelDetailPage = Join-Path $RepoRoot 'entry\src\main\ets\pages\NovelDetailPage.ets'
$unifiedContentModels = Join-Path $RepoRoot 'entry\src\main\ets\Models\UnifiedContentModels.ets'
$novelBookshelfPage = Join-Path $RepoRoot 'entry\src\main\ets\pages\NovelBookshelfPage.ets'
$novelReaderPage = Join-Path $RepoRoot 'entry\src\main\ets\pages\NovelReaderPage.ets'
$novelReaderAbilityPage = Join-Path $RepoRoot 'entry\src\main\ets\pages\NovelReaderAbilityPage.ets'
$novelExplorePage = Join-Path $RepoRoot 'entry\src\main\ets\pages\NovelExplorePage.ets'
$globalSearchPage = Join-Path $RepoRoot 'entry\src\main\ets\pages\GlobalSearchPage.ets'
$ohosConformanceTest = Join-Path $RepoRoot 'entry\src\ohosTest\ets\test\LegadoCompatibilityConformance.test.ets'
$referenceInstrumentationTest = Join-Path $RepoRoot 'legado\app\src\androidTest\java\io\legado\app\compat\LegadoLiveSourceReferenceTest.kt'
$managementStateProbe = Join-Path $RepoRoot 'tools\legado-compat\Inspect-BookSourceManagementState.py'

try {
  $legacyText = Read-Utf8Script -Path $legacyEntry
  $compatibilityRunnerText = Read-Utf8Script -Path $compatibilityRunner
  $implementationText = Read-Utf8Script -Path $implementation
  $evidencePathsModuleText = Read-Utf8Script -Path $evidencePathsModule
  $detachedStarterText = Read-Utf8Script -Path $detachedStarter
  $runMonitorText = Read-Utf8Script -Path $runMonitor
  $driverText = Read-Utf8Script -Path $driver
  $stateModuleText = Read-Utf8Script -Path $stateModule
  $managementStateProbeText = Read-Utf8Script -Path $managementStateProbe
  Assert-ParserClean -Path $legacyEntry
  Assert-ParserClean -Path $compatibilityRunner
  Assert-ParserClean -Path $implementation
  Assert-ParserClean -Path $evidencePathsModule
  Assert-ParserClean -Path $detachedStarter
  Assert-ParserClean -Path $runMonitor
  Assert-Contract ($implementationText.Contains('New-LegadoHypiumRunEvidenceDirectory -ScriptRoot $PSScriptRoot') -and
    $implementationText.Contains('Assert-LegadoHypiumRunEvidenceDirectory -ScriptRoot $PSScriptRoot') -and
    $implementationText.Contains('Assert-LegadoHypiumRunActivityPath -EvidenceDirectory $EvidenceDirectory')) 'source evidence must use a guarded run-scoped directory and activity path'
  Assert-Contract ($evidencePathsModuleText.Contains("throw 'BASELINE_EVIDENCE_WRITE_FORBIDDEN'") -and
    $evidencePathsModuleText.Contains("throw 'RUN_ACTIVITY_PATH_OUTSIDE_RUN_DIRECTORY'")) 'evidence path module must reject baseline and activity path escapes'
  Assert-Contract ($detachedStarterText.Contains('full-source-v2-hypium-device-control') -and
    $detachedStarterText.Contains('@(''-EvidenceDirectory'', $evidenceDirectory)')) 'detached launcher must isolate control artifacts and pass the run directory'
  Assert-Contract ($runMonitorText.Contains('[string]$ControlDirectory =') -and $runMonitorText.Contains('legacyManifestPath')) 'run monitor must follow the isolated control manifest with a legacy read-only fallback'
  Assert-ParserClean -Path $stateModule
  Assert-Contract ($implementationText.Contains("[string]`$RunActivityPath = ''")) 'runner must expose an explicit activity artifact path'
  Assert-Contract ($implementationText.Contains('function Write-HypiumRunActivity')) 'runner must publish a dedicated run activity artifact'
  Assert-Contract ($implementationText.Contains("-Phase 'source_dispatched'") -and $implementationText.Contains("-Phase 'source_settled'")) 'runner activity must bracket each source dispatch with an observable terminal checkpoint'
  Assert-Contract ($implementationText.Contains("-Phase 'document_refresh'") -and $implementationText.Contains("-Status 'passed' -Phase 'completed'")) 'runner activity must distinguish evidence completion from document refresh and terminal success'
  Assert-Contract ($implementationText.Contains("-Status 'failed' -Phase 'failed'")) 'runner activity must classify outer-run failure without suppressing the terminal artifact'
  Assert-Contract ($implementationText.Contains("'.replace-backup-'")) 'activity writer must provide a non-empty replace backup path under PowerShell-hosted .NET'
  Assert-Contract (-not $implementationText.Contains('[System.IO.File]::Replace($temporaryPath, $Path, $null)')) 'activity writer must not pass a null replace backup path'
  Assert-Contract ($implementationText.Contains('[System.IO.File]::Delete($backupPath)') -and $implementationText.Contains('[System.IO.File]::Delete($temporaryPath)')) 'activity writer must clean temporary and backup artifacts in finally'
  Assert-Contract ($implementationText.Contains("[string]`$SourcePackagePath = ''")) 'runner must not depend on a locale-decoded default source filename'
  Assert-Contract ($implementationText.Contains('function Resolve-HypiumSourcePackagePath') -and $implementationText.Contains('Get-FileHash -LiteralPath $candidate.FullName -Algorithm SHA256')) 'runner must resolve its default package by pinned SHA-256'
  Assert-Contract ($implementationText.Contains('PINNED_SOURCE_PACKAGE_EXPECTED_ONE_FOUND_')) 'runner must reject ambiguous or missing pinned packages'
  Assert-Contract ($compatibilityRunnerText.Contains('$requireFullMainBuild = $mainHapIsStale -or $StageKey -eq ''stage0'' -or $StageKey -eq ''stage6'' -or $StageKey -eq ''stage7'' -or $StageKey -eq ''stage8''') -and
    $compatibilityRunnerText.Contains('$null -eq $mainHap -or $requireFullMainBuild')) 'device gate must rebuild the main HAP for baseline and acceptance stages instead of reusing a stale artifact'
  Assert-Contract ($compatibilityRunnerText.Contains('harmony-hap-artifacts-$StageKey.json') -and
    $compatibilityRunnerText.Contains('Get-FileHash -LiteralPath $mainHap.FullName -Algorithm SHA256') -and
    $compatibilityRunnerText.Contains('Assert-HarmonyTestHapFresh -Path $testHap.FullName') -and
    $compatibilityRunnerText.Contains('sha256 = $testArtifact.sha256')) 'device gate must persist main/test HAP hashes with the conformance evidence'
  Assert-Contract ($implementationText.Contains('function Clear-HypiumRunActivityArtifacts')) 'runner must expose narrowly scoped stale activity-artifact cleanup'
  Assert-Contract ($implementationText.Contains("`$temporaryPrefix = `$activityFileName + '.tmp-'" ) -and $implementationText.Contains("`$backupPrefix = `$activityFileName + '.replace-backup-'")) 'stale activity cleanup must be constrained to the current activity-file namespace'
  Assert-Contract ($implementationText.Contains('Clear-HypiumRunActivityArtifacts') -and $implementationText.Contains("Write-HypiumRunActivity -Status 'starting' -Phase 'preflight'")) 'runner must clean stale activity artifacts before publishing a new preflight heartbeat'
  Assert-Contract (Test-Path -LiteralPath $stateModule -PathType Leaf) 'missing canonical state module'
  $webViewExecutorText = Read-Utf8Script -Path $webViewExecutor
  $requestPipelineText = Read-Utf8Script -Path $requestPipeline
  $ruleAnalyzerText = Read-Utf8Script -Path $ruleAnalyzer
  $htmlBridgeText = Read-Utf8Script -Path $htmlBridge
  $compatibilityTypesText = Read-Utf8Script -Path $compatibilityTypes
  $workflowOrchestratorText = Read-Utf8Script -Path $workflowOrchestrator
  $sourceManagerText = Read-Utf8Script -Path $sourceManager
  $bookSourceTabContentText = Read-Utf8Script -Path $bookSourceTabContent
  $exploreDetailNavigatorText = Read-Utf8Script -Path $exploreDetailNavigator
  $dataManagerText = Read-Utf8Script -Path $dataManager
  $unifiedDetailText = Read-Utf8Script -Path $unifiedDetailPage
  $novelDetailText = Read-Utf8Script -Path $novelDetailPage
  $unifiedContentModelsText = Read-Utf8Script -Path $unifiedContentModels
  $novelBookshelfText = Read-Utf8Script -Path $novelBookshelfPage
  $novelReaderText = Read-Utf8Script -Path $novelReaderPage
  $novelReaderAbilityPageText = Read-Utf8Script -Path $novelReaderAbilityPage
  $novelSearchPageText = Read-Utf8Script -Path $searchPage
  $novelExplorePageText = Read-Utf8Script -Path $novelExplorePage
  $globalSearchPageText = Read-Utf8Script -Path $globalSearchPage
  $ohosTestText = Read-Utf8Script -Path $ohosConformanceTest
  $referenceInstrumentationTestText = Read-Utf8Script -Path $referenceInstrumentationTest
  Assert-Contract ($referenceInstrumentationTestText.Contains('ErrorLine') -and $referenceInstrumentationTestText.Contains('ErrorColumn') -and $referenceInstrumentationTestText.Contains('ErrorFileNameSha256') -and $referenceInstrumentationTestText.Contains('ErrorCauseClass')) 'test-only original reference instrumentation must retain safe ScriptException location and cause metadata'
  Assert-Contract ($sourceManagerText.Contains('REQUEST_CARRIER_UNAVAILABLE:identity_mismatch') -and $sourceManagerText.Contains('REQUEST_CARRIER_UNAVAILABLE:template_missing')) 'an explicit V2 request carrier must fail structurally instead of silently dispatching a bare URL'
  Assert-Contract ($exploreDetailNavigatorText.Contains('novelRequestCarrierKey: book.requestCarrierKey') -and $exploreDetailNavigatorText.Contains('requestCarrierKey: book.requestCarrierKey')) 'shared Explore novel detail navigation must preserve the opaque V2 request carrier key'
  Assert-Contract ($exploreDetailNavigatorText.Contains('novelBookVariable: book.variable') -and $exploreDetailNavigatorText.Contains('bookVariable: book.variable')) 'shared Explore novel detail navigation must preserve the selected V2 book variable snapshot'
  Assert-Contract ($novelSearchPageText.Contains('novelRequestCarrierKey: book.requestCarrierKey') -and $novelSearchPageText.Contains('novelBookVariable: book.variable') -and $novelSearchPageText.Contains('requestCarrierKey: book.requestCarrierKey') -and $novelSearchPageText.Contains('bookVariable: book.variable')) 'NovelSearch navigation must preserve the V2 request carrier and selected variable for both detail page types'
  $bookSourceExploreRoute = $bookSourceTabContentText.Contains('openLegadoExploreDetail(this.pathStack, this.selectedBookSourceId, book)')
  $novelExploreRoute = $novelExplorePageText.Contains('openLegadoExploreDetail(this.pathStack, this.selectedSourceId, book)') -or
    $novelExplorePageText.Contains('openLegadoExploreDetail(this.pathStack, selectedSourceIdAtOpen, book)')
  Assert-Contract ($bookSourceExploreRoute -and $novelExploreRoute) 'both Explore UI entries must route through the shared detail navigator'
  Assert-Contract ($globalSearchPageText.Contains('const rawNovelSearch = item.rawNovelSearch;') -and $globalSearchPageText.Contains('novelRequestCarrierKey: rawNovelSearch.requestCarrierKey') -and $globalSearchPageText.Contains('novelBookVariable: rawNovelSearch.variable') -and $globalSearchPageText.Contains('requestCarrierKey: rawNovelSearch.requestCarrierKey') -and $globalSearchPageText.Contains('bookVariable: rawNovelSearch.variable')) 'GlobalSearch online-novel navigation must preserve the V2 request carrier and selected variable for both detail page types'
  Assert-Contract ($unifiedContentModelsText.Contains('novelBookVariable?: string') -and $novelBookshelfText.Contains('bookVariable?: string')) 'both detail navigation parameter contracts must declare an in-memory V2 book variable snapshot'
  Assert-Contract ($unifiedDetailText.Contains('this.pageParams?.novelBookVariable') -and $novelDetailText.Contains('this.bookVariable.length > 0 ? this.bookVariable : undefined')) 'both detail pages must dispatch the explicit V2 book variable snapshot into BookInfo'
  Assert-Contract ($ohosTestText.Contains('rehydratesSearchBookVariableInFreshExecutorForBookInfo') -and $ohosTestText.Contains('new LegadoV2SourceExecutor(compiled)')) 'Harmony conformance must prove a fresh V2 executor restores the selected SearchBook variable without implicit workflow state'
  Assert-Contract ($ohosTestText.Contains('isolatesSearchBookVariablesAcrossFreshExecutorsForBookInfo') -and $ohosTestText.Contains('/toc/isolation/alpha') -and $ohosTestText.Contains('/toc/isolation/beta')) 'Harmony conformance must prove selected SearchBook variable snapshots do not cross-contaminate fresh V2 executors'
  Assert-Contract ($workflowOrchestratorText.Contains('blockProtectedResponse(LegadoWorkflowKind.SEARCH') -and
    $workflowOrchestratorText.Contains('blockProtectedResponse(LegadoWorkflowKind.EXPLORE') -and
    $workflowOrchestratorText.Contains('blockProtectedResponse(LegadoWorkflowKind.BOOK_INFO') -and
    $workflowOrchestratorText.Contains('blockProtectedResponse(LegadoWorkflowKind.TOC') -and
    $workflowOrchestratorText.Contains('blockProtectedResponse(LegadoWorkflowKind.CONTENT')) 'all V2 rule workflows must gate protected HTML before parsing'
  Assert-Contract ($workflowOrchestratorText.Contains('PROTECTED_RESPONSE:${responseClass}') -and
    $workflowOrchestratorText.Contains('LegadoExecutionErrorCode.NEEDS_INTERACTION')) 'protected-response gating must preserve a classified trace and interaction-required error'
  Assert-Contract ($implementationText.Contains("Get-HypiumTextProperty -Object `$trace -Name 'responseClass'") -and
    $implementationText.Contains("Get-HypiumTextProperty -Object `$trace -Name 'contentResponseClass'")) 'detail trace parser must read the generic responseClass and retain a dedicated-field fallback'
  Assert-Contract ($compatibilityRunnerText.Contains('持续真机治理状态只来自 `tools/legado-compat/state/full-source-validation-state.json`') -and -not $compatibilityRunnerText.Contains('状态只来自 `tools/legado-compat/state/legado-compatibility-state.json`')) 'document generator must keep device-persisted governance facts separate from legacy stage state'
  Assert-Contract ($implementationText.Contains("contentProbeRequestMethod').ToUpperInvariant()")) 'content parity must compare request methods case-insensitively'
  Assert-Contract ($implementationText.Contains("contentProbeResponseClass') -eq (Get-HypiumTextProperty -Object `$ContentTrace -Name 'responseClass')")) 'content parity must compare the raw detail trace response class'
  Assert-Contract ($implementationText.Contains('protected_response_requires_interaction') -and $implementationText.Contains("-Status 'needs_interaction' -Outcome 'protected_response_requires_interaction'")) 'protected reference responses must be classified as interaction-required instead of semantic mismatch'
  Assert-Contract ($implementationText.Contains("[string]`$attempt.trace.errorCode -eq 'needs_interaction'") -and
    $implementationText.Contains("'html_login', 'html_challenge")) 'V2 login/challenge responses must remain interaction-required even without a reference trace'
  $sourceHeaderStart = $requestPipelineText.IndexOf('  private appendSourceHeader(')
  $sourceHeaderEnd = $requestPipelineText.IndexOf('  private putHeader(', $sourceHeaderStart)
  Assert-Contract ($sourceHeaderStart -ge 0 -and $sourceHeaderEnd -gt $sourceHeaderStart) 'source-header planner must remain independently inspectable'
  $sourceHeaderText = $requestPipelineText.Substring($sourceHeaderStart, $sourceHeaderEnd - $sourceHeaderStart)
  Assert-Contract ($sourceHeaderText.Contains('BaseSource.getHeaderMap()') -and -not $sourceHeaderText.Contains('normalized.split(/\\r?\\n/)')) 'source.header must follow original Legado JSON-only semantics rather than reinterpret legacy Name: Value text'
  Assert-Contract ($webViewExecutorText.Contains("this.currentTask.lifecycleStage = 'redirect_navigation_started'")) 'ArkWeb must accept the first non-runtime redirect navigation after dispatch'
  Assert-Contract ($webViewExecutorText.Contains('this.isRuntimeOrBlankNavigation(url)')) 'ArkWeb redirect acceptance must retain runtime and blank-navigation exclusion'
  Assert-Contract ($webViewExecutorText.Contains('this.applyRequestUserAgent(options.headers)')) 'ArkWeb must apply the planner-resolved User-Agent before source navigation'
  Assert-Contract ($webViewExecutorText.Contains('this.webviewController.setCustomUserAgent(userAgent)')) 'ArkWeb must not let a component-wide User-Agent override a source request'
  Assert-Contract ($webViewExecutorText.Contains('hasSourceUserAgent = true')) 'a declared empty User-Agent must remain an explicit source-level request choice'
  Assert-Contract ($webViewExecutorText.Contains("'explicit_empty'") -and $webViewExecutorText.Contains("'explicit_value'")) 'ArkWeb evidence logging must distinguish explicit empty User-Agent from a nonempty override without exposing its value'
  Assert-Contract ($webViewExecutorText.Contains('this.restorePlatformUserAgent()')) 'a shared ArkWeb controller must reset its User-Agent between sources'
  Assert-Contract ($webViewExecutorText.Contains('DOM_STATE;ready=') -and $webViewExecutorText.Contains('htmlLength')) 'ArkWeb must emit fixed-grammar DOM structure evidence without serializing page content'
  Assert-Contract ($webViewExecutorText.Contains('JSON.parse(result) as string')) 'ArkWeb must JSON-decode quoted JavaScript string results before HTML rule analysis'
  Assert-Contract ($implementationText.Contains('Get-HypiumTextProperty -Object $attempt.trace -Name')) 'runner must preserve optional sanitized trace extensions'
  Assert-Contract ($driverText.Contains('domReady=(loading|interactive|complete)')) 'Hypium parser must retain DOM structure diagnostics without changing search classification'
  Assert-Contract ($webViewExecutorText.Contains('await this.waitForPageContent(task, options.postLoadDelayTime || 0)')) 'ArkWeb must wait after page completion before extracting dynamic DOM content'
  Assert-Contract ($webViewExecutorText.Contains('const delayTime: number = 1000 + Math.max(0, configuredDelayTime)')) 'ArkWeb post-load delay must retain Legado baseline timing'
  Assert-Contract ($requestPipelineText.Contains('postLoadDelayTime: spec.webViewDelayTime')) 'URL webViewDelayTime must be forwarded to the post-load ArkWeb wait'
  Assert-Contract ($ruleAnalyzerText.Contains('getElementsWithPureCssIndexDiagnosticsAsync')) 'pure CSS indexed rules must expose a redacted base-match diagnostic'
  Assert-Contract ($ruleAnalyzerText.Contains('hasLegacyIndexInCssChain')) 'indexed CSS chains must use the canonical Legado index grammar instead of the limited bridge grammar'
  Assert-Contract ($ruleAnalyzerText.Contains("'html_bridge_available'")) 'selector diagnostics must distinguish bridge availability without serializing HTML'
  Assert-Contract ($compatibilityTypesText.Contains('hasRuleReadableBody')) 'response semantics must distinguish a received rule-readable error document from a missing transport body'
  Assert-Contract ($workflowOrchestratorText.Contains('response.hasRuleReadableBody()')) 'V2 workflows must pass received HTTP error documents to Legado rules'
  Assert-Contract ($sourceManagerText.Contains('trace.response.hasRuleReadableBody()')) 'the V2 manager must not reject a rule-readable HTTP error document before workflow classification'
  Assert-Contract ($legacyText.Contains('Invoke-LegadoV2HypiumFullSourceDeviceRunner.ps1')) 'legacy entry must delegate to Hypium implementation'
  Assert-Contract ($implementationText.Contains('Invoke-LegadoNativeProcess')) 'implementation must use bounded Python invocation'
  Assert-Contract ($implementationText.Contains('Read-LegadoJsonFile')) 'implementation must consume persisted Hypium evidence'
  Assert-Contract ($implementationText.Contains("Get-HypiumTextProperty -Object `$evidence -Name 'search_outcome'")) 'partial Hypium result JSON must be classified without a StrictMode property failure'
  Assert-Contract ($implementationText.Contains('Write-LegadoStateCheckpoint')) 'implementation must atomically update canonical state'
  Assert-Contract ($implementationText.Contains('Refresh-HypiumGovernanceDocuments')) 'a completed source run must refresh the generated governance documents'
  Assert-Contract ($implementationText.Contains('semanticQualification')) 'runner must distinguish execution evidence from semantic parity'
  Assert-Contract ($implementationText.Contains('execution_verified_no_reference')) 'unreferenced executions must not be reported as semantic matches'
  Assert-Contract ($implementationText.Contains('semantic_match')) 'reference-backed executions must publish a semantic-match qualification'
  Assert-Contract ($implementationText.Contains('Get-HypiumSafeReadSemanticQualification')) 'safe-read parity must qualify content independently of search parity'
  Assert-Contract ($implementationText.Contains('Get-HypiumContentResponseParityQualification')) 'content-length comparison must be gated by a dedicated original/V2 content request-response parity check'
  Assert-Contract ($implementationText.Contains('content_response_parity_unavailable')) 'a stale original test APK without a content response probe must keep content parity explicitly unconfirmed'
  Assert-Contract ($implementationText.Contains('content_request_response_parity_mismatch')) 'different content request or response fingerprints must be classified before any reader-text mismatch'
  Assert-Contract ($implementationText.Contains('search_semantic_match')) 'search parity alone must not be published as full workflow parity'
  Assert-Contract ($implementationText.Contains('content_fingerprint_missing')) 'missing original content fingerprints must remain a planned evidence gap'
  Assert-Contract ($implementationText.Contains('content_fingerprint_mismatch')) 'different content fingerprints must be reported as semantic mismatches'
  Assert-Contract ($implementationText.Contains("`$referenceOutcome -notin @('complete', 'empty')")) 'an original reference exception must remain non-comparable rather than being converted into a zero-result semantic mismatch'
  Assert-Contract ($implementationText.Contains("[int]`$Attempt.trace.statusCode -eq 0 -and [string]`$Attempt.trace.errorCode -eq 'network'")) 'a V2 pre-response network failure must remain a transport classification rather than a semantic search mismatch'
  Assert-Contract ($driverText.Contains('CONTENT_TRACE_AFTER_READER_MISSING')) 'the Driver must require a post-reader Content trace before passing a read workflow'
  Assert-Contract ($implementationText.Contains('[Math]::Abs($postReaderTraceAt - $readerTraceAt) -gt 5000')) 'safe-read verification must associate occurrence and persistence timestamps by a bounded window rather than an invalid strict ordering'
  Assert-Contract ($driverText.Contains('wait_for_readable_content_trace_records')) 'the Driver must wait for a readable post-reader trace rather than accepting an asynchronously stale trace'
  Assert-Contract ($driverText.Contains('previous_content_trace_at') -and $driverText.Contains('traceOccurredAt')) 'the Driver must reject a readable Content trace that predates the current reader action'
  Assert-Contract ($driverText.Contains('READER_V2_CONTENT_TRACE_NOT_FRESH') -and $driverText.Contains('CONTENT_TRACE_NOT_ASSOCIATED_WITH_READER_ACTION')) 'the Driver must bind both reader and detail Content traces to the same post-action execution window'
  Assert-Contract ($implementationText.Contains('previousContentTraceAt') -and $implementationText.Contains('traceOccurredAt = [Int64]')) 'source evidence must retain the redacted post-reader timestamp gate'
  Assert-Contract ($implementationText.Contains('readerContentTraceAt') -and $implementationText.Contains('contentBridgeReaderFingerprint')) 'source evidence must retain reader-action freshness and bridge-reader candidate diagnostics'
  Assert-Contract ($implementationText.Contains("`$Record.PSObject.Properties['issueIds']")) 'a successful semantic retest must close legacy source findings as well as the current Hypium finding'
  Assert-Contract ($driverText.Contains('CONTENT_TRACE_TIMESTAMP_NOT_ADVANCED')) 'the Driver must fail rather than publish a stale post-reader content trace'
  Assert-Contract ($driverText.Contains('content_record = max(') -and $driverText.Contains('key=lambda record: int(record.get("traceOccurredAt", 0))')) 'the Driver must select the newest Content trace rather than relying on diagnostic storage order'
  Assert-Contract ($implementationText.Contains('contentTraceAfterReaderAt')) 'source evidence must retain the independently captured post-reader timestamp'
  Assert-Contract ($unifiedDetailText.Contains('forceNetworkContentRefresh: this.pageParams?.forceNovelNetworkRefresh === true')) 'a forced V2 search/detail flow must pass its fresh-content intent to the reader'
  Assert-Contract ($unifiedDetailText.Contains('await this.novelSourceManager.refreshExecutionTraceSummaries(true);')) 'the detail page must replace its pre-reader snapshot from persisted V2 evidence after returning from the isolated reader'
  Assert-Contract ($unifiedDetailText.Contains('getPersistedExecutionTraceWorkflowSummaries(sourceId)') -and $unifiedDetailText.Contains('novelV2TraceRehydrationGeneration') -and $unifiedDetailText.Contains('novelV2TraceSnapshotRequestGeneration')) 'the detail page must project cross-Ability evidence from a versioned persistence snapshot rather than a racing singleton map'
  Assert-Contract ($sourceManagerText.Contains('async refreshExecutionTraceSummaries(replaceFromPersistence: boolean = false)') -and $sourceManagerText.Contains('if (replaceFromPersistence)')) 'the source manager must support an explicit persistence-authoritative trace refresh for isolated reader return'
  Assert-Contract ($sourceManagerText.Contains('executionTraceRefreshGeneration') -and $sourceManagerText.Contains('async getPersistedExecutionTraceWorkflowSummaries(sourceId: string)')) 'the source manager must reject stale persistence refreshes and expose a raw-hash-bound workflow snapshot'
  Assert-Contract ($unifiedDetailText.Contains('onPageShow(): void') -and $unifiedDetailText.Contains('this.scheduleNovelV2TraceRehydration();')) 'the detail page must rehydrate V2 evidence when the isolated reader restores its host window'
  Assert-Contract ($unifiedDetailText.Contains('const delays: number[] = [0, 800, 2500, 6000, 12000];') -and $unifiedDetailText.Contains('this.clearNovelV2TraceRehydration();')) 'cross-window trace rehydration must retry through the observed RDB visibility window within a bounded lifecycle-managed interval'
  Assert-Contract ($novelReaderAbilityPageText.Contains('forceNetworkContentRefresh: source.forceNetworkContentRefresh === true')) 'the isolated reader Ability must preserve the forced V2 content-refresh intent'
  Assert-Contract ($novelReaderText.Contains('this.forceNetworkContentRefresh') -and $novelReaderText.Contains('await this.sourceManager.getContent')) 'the reader must bypass stale chapter text cache for an explicitly forced V2 content refresh'
  Assert-Contract ($novelReaderText.Contains("skip cross-chapter prefetch for V2 source-scoped execution") -and $novelReaderText.Contains('contentEngine === LegadoCompatibilityEngineMode.V2_ENABLED')) 'V2 reader opens must not issue background Content prefetches that can mutate source-scoped variables or overwrite the foreground trace'
  Assert-Contract ($novelReaderText.Contains(".id('novel_reader_v2_content_refresh_diagnostic')")) 'the reader must expose a redacted V2 Content-origin diagnostic to the device harness'
  Assert-Contract ($novelReaderText.Contains('sha256Hash(rawContent)') -and $novelReaderText.Contains('digest=${contentDigest}')) 'the reader diagnostic must fingerprint the raw Content result before reader presentation transforms it'
  Assert-Contract ($novelReaderText.Contains('getRedactedContentStructure') -and $novelReaderText.Contains('lf=${contentStructure.lineFeedCount}') -and $novelReaderText.Contains('trailingWs=${contentStructure.trailingWhitespaceCount}')) 'the reader diagnostic must retain redacted newline and boundary-whitespace structure without serializing chapter text'
  Assert-Contract ($driverText.Contains('READER_V2_CONTENT_EXECUTION_PATTERN') -and $driverText.Contains('v2_content_execution_evidence')) 'the Hypium driver must serialize a typed, redacted reader-content witness'
  Assert-Contract ($driverText.Contains('contentLineFeedCount') -and $driverText.Contains('contentCarriageReturnCount') -and $driverText.Contains('contentLeadingWhitespaceCount') -and $driverText.Contains('contentTrailingWhitespaceCount')) 'the Hypium driver must deserialize each redacted reader-content structure count'
  Assert-Contract ($implementationText.Contains('Get-HypiumReaderContentEvidence') -and $implementationText.Contains('reader_content_fingerprint_missing')) 'the source runner must qualify content parity from the reader raw-content witness rather than presentation trace text'
  Assert-Contract ($sourceManagerText.Contains('isCompatibilityTraceWorkflowSummaryPersisted(summary)') -and $sourceManagerText.Contains('workflow_trace_read_back_not_visible') -and $dataManagerText.Contains('async isCompatibilityTraceWorkflowSummaryPersisted(')) 'reader trace persistence must be read-back verified through the detail-page workflow-summary query contract'
  Assert-Contract ($implementationText.Contains('content_structure_reference_missing') -and $implementationText.Contains('content_line_feed_count_mismatch') -and $implementationText.Contains('content_trailing_whitespace_count_mismatch')) 'the source runner must classify missing or divergent original/V2 content structure separately from digest parity'
  $referenceRunner = Join-Path $RepoRoot 'tools\legado-compat\Invoke-LegadoSingleSourceReference.ps1'
  $referenceTraceParser = Join-Path $RepoRoot 'tools\legado-compat\LegadoReferenceTraceParser.psm1'
  $referenceTest = Join-Path $RepoRoot 'legado\app\src\androidTest\java\io\legado\app\compat\LegadoLiveSourceReferenceTest.kt'
  $referenceRunnerText = Read-Utf8Script -Path $referenceRunner
  $referenceTraceParserText = Read-Utf8Script -Path $referenceTraceParser
  $referenceTestText = Read-Utf8Script -Path $referenceTest
  Assert-Contract ($referenceRunnerText.Contains('contentLineFeedCount') -and $referenceRunnerText.Contains('contentTrailingWhitespaceCount')) 'the original-reference host evidence must persist redacted content structure counts'
  Assert-Contract ($referenceTestText.Contains('searchBookTargetSequenceSha256') -and $referenceRunnerText.Contains('Get-TraceTargetSequence')) 'original Legado target-prefix evidence must remain bounded and host-sanitized'
  Assert-Contract ($driverText.Contains('SEARCH_TARGET_SEQUENCE_PATTERN') -and $driverText.Contains('searchBookTargetSequenceSha256')) 'Hypium must parse bounded digest-only Search target sequences'
  Assert-Contract ($implementationText.Contains('Get-HypiumSearchTargetSequenceDifference') -and $implementationText.Contains('search_result_target_sequence_mismatch')) 'same-response Search target-order drift must be classified before downstream workflow diagnosis'
  Assert-Contract ($implementationText.Contains('searchBookTargetSequenceSha256 = @(Get-HypiumTargetDigestArrayProperty -Object $Attempt.trace')) 'source evidence must persist the bounded V2 target sequence after host-side validation'
  Assert-Contract ($implementationText.Contains("searchBookDeduplicatedCount = [int](Get-HypiumTextProperty -Object `$Attempt.trace -Name 'searchBookDeduplicatedCount')") -and $implementationText.Contains("searchBookReversed = Get-HypiumBooleanProperty -Object `$Attempt.trace -Name 'searchBookReversed'") -and $implementationText.Contains(".Trim().ToLowerInvariant() -eq 'true'")) 'source evidence must preserve finalized-search deduplication and reversal semantics without treating the string false as true'
  Assert-Contract ($stateModuleText.Contains('ConvertFrom-Json -InputObject $text -DateKind String')) 'state reload must preserve UTC evidence timestamps as strings instead of converting them to local wall-clock values'
  Assert-Contract ($workflowOrchestratorText.Contains('bookTargetSequence=${bookTargetSequence.length') -and $workflowOrchestratorText.Contains('bookTargetSequenceDistinct=')) 'V2 Search must publish a bounded digest-only target sequence'
  Assert-Contract ($referenceTestText.Contains('content.count { it ==') -and $referenceTestText.Contains('content.takeWhile { it.isWhitespace() }')) 'the original Legado test-only reference must emit newline and boundary-whitespace counts without serializing content'
  Assert-Contract ($referenceTestText.Contains('captureContentResponseProbe') -and $referenceTestText.Contains('includeContentResponseProbe')) 'the original Legado reference must expose an explicit opt-in content response probe using production AnalyzeUrl semantics'
  Assert-Contract ($implementationText.Contains("'recovery-ordinal-*-reference-run-*'") -and $implementationText.Contains('raw-document identity')) 'the runner must discover recovery reference traces while still binding them to the exact raw source digest'
  Assert-Contract ($implementationText.Contains('$itemId = (Get-HypiumTextProperty -Object $item -Name ''id'').Trim()') -and $implementationText.Contains('$findingIds.Contains($itemId)')) 'legacy issue IDs must preserve uppercase source-hash prefixes before a semantic retest resolves their status'
  Assert-Contract ($implementationText.Contains("Get-HypiumTextProperty -Object `$Attempt -Name 'processClassification'") -and $implementationText.Contains("-Fallback 'not_executed'")) 'policy and interaction rejections must persist source evidence even when no native process classification exists'
  Assert-Contract ($implementationText.Contains('function Get-HypiumArrayProperty') -and $implementationText.Contains("Get-HypiumArrayProperty -Object `$attempt -Name 'compileDiagnosticCodes'")) 'optional compile diagnostic arrays must not make a partial Harness result fail under StrictMode'
  Assert-Contract ($driverText.Contains('READER_FORCED_CONTENT_NETWORK_BYPASS_NOT_OBSERVED')) 'the driver must fail when a forced V2 reader open uses a cache-origin Content result'
  Assert-Contract ($driverText.Contains('component.getId() == READER_V2_CONTENT_REFRESH_DIAGNOSTIC_ID')) 'the reader-content probe must not mistake the hidden diagnostic for chapter content'
  Assert-Contract ($driverText.Contains('[0-9A-Fa-f]{16}')) 'the Driver must accept either hex case for ArkTS content fingerprints'
  Assert-Contract ($implementationText.Contains('search_verified_read_harness_failed')) 'downstream safe-read harness failures must not be misclassified as search-network failures'
  $safeReadHarnessIndex = $implementationText.IndexOf("elseif (`$safeReadPath -and `$attempt.runnerStatus -ne 'passed'")
  $semanticDifferenceIndex = $implementationText.IndexOf('elseif ($null -ne $semanticDifference)')
  Assert-Contract ($safeReadHarnessIndex -ge 0 -and $semanticDifferenceIndex -gt $safeReadHarnessIndex) 'safe-read harness failure classification must precede semantic-difference classification'
  Assert-Contract ($driverText.Contains('CONTENT_BRIDGE_PROBE_PATTERN')) 'the Driver must retain sanitized DOM bridge candidate diagnostics'
  Assert-Contract ($driverText.Contains('CONTENT_BRIDGE_READER_PROBE_PATTERN')) 'the Driver must retain sanitized reader-normalized DOM bridge candidate diagnostics'
  Assert-Contract ($driverText.Contains('CONTENT_STAGE_DIAGNOSTICS_PATTERN')) 'the Driver must retain extraction and normalization stage counts without serializing chapter text'
  Assert-Contract ($driverText.Contains('stop_app_settled')) 'the Driver must settle a stopped application before starting a newly installed HAP'
  Assert-Contract ($sourceManagerText.Contains('digest=([a-z0-9_]+)(?:;[A-Za-z0-9_:=./,\-]+)*$')) 'persisted content diagnostics must accept versioned redacted trace fields and comma-separated redacted header names'
  Assert-Contract ($htmlBridgeText.Contains("return this.removeScriptAndStyleElements(elem.outerHTML);")) 'the DOM bridge must return outer HTML for Legado @html semantics'
  Assert-Contract ($ruleAnalyzerText.Contains("result.attr === 'html' || result.attr === 'all' || result.attr === 'outerhtml'")) 'CSS @html and @all must aggregate every selected outer HTML node'
  Assert-Contract ($ruleAnalyzerText.Contains('? this.getElementsByCSSForOuterHtml(result.sel)')) 'CSS @html must resolve selected elements through the outer-HTML serialization path'
  Assert-Contract ($ruleAnalyzerText.Contains('parseChainRuleToHtmlList(selector)')) 'CSS @html must preserve standard-CSS selected outer elements through the DOM bridge'
  Assert-Contract ($ruleAnalyzerText.Contains("case 'textnodes':") -and
    $ruleAnalyzerText.Contains("case 'owntext':") -and
    $ruleAnalyzerText.Contains('extractDirectTextNodes(element)') -and
    $ruleAnalyzerText.Contains('toTrimmedString()')) 'CSS-chain textNodes/ownText must mirror JSoup direct child extraction and shared Java-whitespace trimming rather than recursively collecting descendant text'
  Assert-Contract (-not $ruleAnalyzerText.Contains('const textNodeRegex = />([^<]+)</g;')) 'textNodes must not use the former descendant-text regex implementation'
  Assert-Contract ($ohosTestText.Contains('keepsOnlyDirectTextNodesForLegacyContentChains') -and $ohosTestText.Contains('id.fixture-textnodes@textNodes')) 'Harmony conformance must exercise direct-child textNodes semantics with nested and self-closing descendants'
  Assert-Contract ($workflowOrchestratorText.Contains('extractChars=${extractedCharacterCount};') -and $workflowOrchestratorText.Contains('normalizeDelta=${normalizationDelta};') -and $workflowOrchestratorText.Contains('bridgeDigest=${bridgeFingerprint};bridgeReaderChars=${bridgeReaderLength};') -and $workflowOrchestratorText.Contains('bridgeReaderDigest=${bridgeReaderFingerprint};') -and $workflowOrchestratorText.Contains('digest=${contentFingerprint}')) 'Content traces must distinguish extraction, bridge-reader normalization and active reader normalization without serializing extracted text'
  Assert-Contract ($workflowOrchestratorText.Contains('firstBlock=${firstExtractStartsWithBlockTag};firstIndent=${firstNormalizeStartsWithReaderIndent}')) 'Content traces must expose first-fragment structural shape without serializing content'
  Assert-Contract ($sourceManagerText.Contains('(?:bridgeReaderChars=\d+;bridgeReaderLf=\d+;bridgeReaderDigest=[a-z0-9_]+;)?digest=')) 'persisted Content diagnostics must accept optional bridge-reader evidence before the active-content digest'
  Assert-Contract ($workflowOrchestratorText.Contains('firstResponseEvidence = await this.buildSearchNetworkDiagnostic(response)')) 'Content traces must retain a redacted first-response witness before selector evaluation'
  Assert-Contract ($implementationText.Contains('reference_nonempty_v2_search_uncompleted')) 'a reference-backed nonempty search must classify V2 incomplete traces as semantic mismatches'
  Assert-Contract ($implementationText.Contains('reference_success_v2_http_error')) 'an original success plus a V2 HTTP error must be classified as a semantic mismatch even when rules yield candidates'
  Assert-Contract ($implementationText.Contains('Test-HypiumSearchHttpResponseParity')) 'an HTTP response can qualify only after a same-response original-Legado witness'
  $expectedExternalStart = $implementationText.IndexOf('function Test-HypiumExpectedExternal')
  $expectedExternalEnd = $implementationText.IndexOf('function Get-HypiumReferenceSearchEvidence', $expectedExternalStart)
  Assert-Contract ($expectedExternalStart -ge 0 -and $expectedExternalEnd -gt $expectedExternalStart) 'expected-external classification must remain independently inspectable'
  $expectedExternalText = $implementationText.Substring($expectedExternalStart, $expectedExternalEnd - $expectedExternalStart)
  Assert-Contract ($expectedExternalText.Contains('Test-HypiumSearchHttpResponseParity')) 'expected-external classification must require exact original/V2 request-response parity'
  Assert-Contract ($expectedExternalText.Contains("'reference_exception'") -and $expectedExternalText.Contains('SocketTimeoutException') -and $expectedExternalText.Contains("[string]`$Attempt.trace.errorCode -eq 'network'")) 'simultaneous original/V2 pre-response socket failures must be classified as external only through a narrow network-only rule'
  Assert-Contract ($implementationText.Contains('searchProbeBodyFingerprint') -and $implementationText.Contains('searchProbeRequestHeaderFingerprint')) 'HTTP parity must require both response and effective-header fingerprints'
  Assert-Contract ($implementationText.Contains('Get-HypiumHeaderNames') -and $implementationText.Contains('requestHeaderNames')) 'the full-source runner must preserve a value-free request-header-name witness from Hypium traces'
  Assert-Contract ($referenceRunnerText.Contains('searchProbeRequestHeaderNames') -and $referenceRunnerText.Contains('contentProbeRequestHeaderNames')) 'original reference evidence must persist only normalized request header names alongside its fingerprints'
  Assert-Contract ($referenceRunnerText.Contains('workflowErrorLine') -and $referenceRunnerText.Contains('workflowErrorColumn') -and $referenceRunnerText.Contains('workflowErrorFileNameSha256') -and $referenceRunnerText.Contains('workflowErrorCauseClass')) 'original reference evidence must retain only safe ScriptException location and cause metadata when a workflow fails before HTTP'
  Assert-Contract ($implementationText.Contains("referenceSourceHash.Equals(`$expectedSourceHash")) 'reference evidence must prove the same raw source before semantic classification'
  Assert-Contract ($implementationText.Contains('Sort-Object -Property generatedAt -Descending')) 'the latest same-source original trace must supersede stale partial reference evidence'
  Assert-Contract ($implementationText.Contains("'single-source-reference-' + `$sourceId + '-*.json'")) 'timestamped original-reference retries must be discovered and raw-hash verified before selecting the latest witness'
  Assert-Contract ($referenceRunnerText.Contains('single-source-reference-{0}-{1}.json') -and $referenceRunnerText.Contains('$SourceHash')) 'single-source reference defaults must be source-scoped and timestamped so a later source cannot overwrite the witness'
  Assert-Contract ($referenceRunnerText.Contains("'logcat', '-d', '-v', 'raw'") -and $referenceRunnerText.Contains('LegadoReferenceTraceParser.psm1') -and $referenceRunnerText.Contains('Read-LegadoReferenceTraceRecords') -and $referenceTraceParserText.Contains('LEGADO_LIVE_TRACE_PART:') -and $referenceTraceParserText.Contains('builder.Length -le 98304') -and $referenceTraceParserText.Contains('LEGADO_LIVE_TRACE:')) 'long original-reference traces must be reassembled from bounded raw-log fragments before JSON parsing'
  $utcTimestampExpression = '$timestamp.ToUniversalTime().ToString(''o'')'
  Assert-Contract ($implementationText.Contains('[DateTime]::UtcNow.ToString(') -and $implementationText.Contains("'Z'") -and $referenceRunnerText.Contains($utcTimestampExpression)) 'V2 and original-reference evidence timestamps must be explicit UTC instants for freshness ordering'
  Assert-Contract ($implementationText.Contains('arkweb_execution_unconfirmed')) 'ArkWeb HTTP 0 traces must not collapse into generic execution failures'
  Assert-Contract ($implementationText.Contains('arkweb_endpoint_unconfirmed')) 'ArkWeb connection-refused evidence must be isolated from lifecycle defects pending reference comparison'
  Assert-Contract ($implementationText.Contains("Get-HypiumTextProperty -Object `$attempt.trace -Name 'webViewLifecycle'")) 'optional ArkWeb lifecycle evidence must not break non-ArkWeb trace classification under strict mode'
  Assert-Contract ($implementationText.Contains('Write-HypiumMissingResult')) 'missing Hypium result must be recovered into structured evidence'
  Assert-Contract ($implementationText.Contains('safe_read_path_harness_incomplete')) 'a safe-read driver failure must settle every previously running workflow'
  Assert-Contract ($implementationText.Contains('safe_read_path_not_executed_after_search_terminal')) 'every terminal safe-read source state must settle unexecuted downstream workflows'
  Assert-Contract ($implementationText.Contains('Resolve-HypiumTocPartialOutcome')) 'safe-read evidence must classify an empty or unconfirmed toc from the actual V2 TOC trace'
  Assert-Contract ($implementationText.Contains('Resolve-HypiumBookInfoTerminalOutcome')) 'safe-read evidence must classify a terminal book-info trace before a TOC is started'
  Assert-Contract ($implementationText.Contains('Resolve-HypiumBookInfoTerminalOutcome -Record $Record')) 'terminal BookInfo classification must receive original-reference evidence rather than discarding it'
  Assert-Contract ($implementationText.Contains("`$BookInfoResult -notin @('terminal_trace_observed', 'metadata_empty_http_error')")) 'terminal BookInfo classification must accept an observed HTTP-error terminal trace rather than downgrading it to execution-unconfirmed'
  Assert-Contract ($implementationText.Contains('Resolve-HypiumBookInfoPartialOutcome')) 'safe-read evidence must classify an HTTP-error book-info response separately from a completed metadata workflow'
  Assert-Contract ($implementationText.Contains('book_info_reference_response_mismatch')) 'a comparable original BookInfo response plus V2 zero-resolution must remain a structured mismatch, not a passed book-info workflow'
  Assert-Contract ($implementationText.Contains('book_info_reference_insufficient') -and $implementationText.Contains('book_info_reference_endpoint_unconfirmed')) 'BookInfo reference readiness alone must not create a semantic mismatch when the original probe is absent, failed or access-denied, including terminal HTTP-error paths'
  Assert-Contract ($implementationText.Contains("`$probeOutcome -ne 'complete'") -and $implementationText.Contains("`$probeStatusCode -ge 400") -and $implementationText.Contains('bookInfoProbeResponseClass')) 'BookInfo mismatch classification must require a completed non-error original probe rather than using bookUrl presence as success'
  Assert-Contract ($driverText.Contains('metadata_empty_http_error')) 'driver workflow output must distinguish a completed HTTP error response with zero metadata from book-info success'
  Assert-Contract ($implementationText.Contains('toc_reference_exception_unresolved')) 'an original TOC exception and a V2 empty TOC must remain distinct until their difference is explained'
  Assert-Contract ($implementationText.Contains("Set-HypiumSemanticQualification -Record `$Record -Qualification 'endpoint_unconfirmed'")) 'a source with only partial workflow evidence must not retain a full semantic-match qualification'
  Assert-Contract ($driverText.Contains('empty_or_non_positive')) 'driver must publish a nonpositive chapter count as a structured toc outcome'
  Assert-Contract ($driverText.Contains('not_started_book_info_terminal')) 'driver must preserve a terminal book-info result when no TOC is scheduled'
  Assert-Contract ($driverText.Contains('BOOK_INFO_TRACE_PATTERN')) 'driver must extract fixed BookInfo response diagnostics without persisting a response body'
  Assert-Contract ($driverText.Contains('run_trace_parser_contract')) 'driver must expose a deterministic sanitized BookInfo parser contract'
  Assert-Contract ($driverText.Contains('--parser-self-test')) 'driver parser contract must run without device control'
  Assert-Contract ($driverText.Contains('toc_rule_exception')) 'driver must classify the fixed V2 TOC rule-exception token without persisting rule content'
  Assert-Contract ($driverText.Contains('TOC_TRACE_PATTERN')) 'driver must parse a TOC count before the redacted network-evidence suffix'
  Assert-Contract ($driverText.Contains('NETWORK_EVIDENCE_PATTERN')) 'driver must parse target-hash network evidence for every workflow without retaining URLs'
  Assert-Contract ($driverText.Contains('BOOK_INFO_TOC_URL_PATTERN')) 'driver must retain the post-rule tocUrl fingerprint before request planning'
  Assert-Contract ($implementationText.Contains('bookInfoTocUrlFingerprint')) 'runner evidence must retain the safe BookInfo tocUrl fingerprint'
  Assert-Contract ($driverText.Contains('TOC_COUNTS_PATTERN')) 'driver must parse fixed TOC selector and accepted-chapter counts without retaining chapter data'
  Assert-Contract ($implementationText.Contains('tocMatchedElementCount') -and $implementationText.Contains('tocMissingChapterUrlCount')) 'runner evidence must retain safe TOC decomposition counts'
  Assert-Contract ($driverText.Contains('get_safe_output_summary_shape')) 'driver must retain only a fixed grammar shape when a workflow summary is not yet recognized'
  Assert-Contract ($implementationText.Contains('outputSummaryShape') -and $implementationText.Contains('outputSummaryLength')) 'runner evidence must persist safe trace shape diagnostics without storing the summary text'
  Assert-Contract ($implementationText.Contains('contentBridgeStatus') -and $implementationText.Contains('contentBridgeFingerprint')) 'runner evidence must preserve sanitized DOM bridge diagnostics'
  Assert-Contract ($implementationText.Contains("bridgeStatus -ne 'available'") -and $implementationText.Contains('contentBridgeCharacterCount')) 'safe-read success must reject incomplete declared bridge evidence'
  Assert-Contract ($driverText.Contains('responseClass') -and $driverText.Contains('responseBodyLength')) 'driver must retain the response class and fixed body evidence together'
  Assert-Contract ($driverText.Contains('BOOK_INFO_REQUEST_EVIDENCE_PATTERN')) 'driver must parse the fixed effective-request fingerprint without storing headers'
  Assert-Contract ($driverText.Contains('reqHeaderFingerprint=(empty|digest_error|[0-9a-f]{16})')) 'driver must parse redacted search request header evidence'
  Assert-Contract ($implementationText.Contains('requestHeaderFingerprint')) 'persisted device evidence must retain the effective-request fingerprint for original/V2 comparison'
  Assert-Contract ($implementationText.Contains('Get-HypiumProcessTimeoutSeconds') -and $implementationText.Contains('($UiTimeoutSeconds * 8) + 120')) 'safe-read driver timeout must cover the multi-phase workflow instead of killing Python before its finally block'
  Assert-Contract ($implementationText.Contains('responseBodyFingerprint')) 'persisted detail evidence must retain the fixed body fingerprint for original/V2 comparison'
  Assert-Contract ($implementationText.Contains('contentResponseBodyFingerprint') -and $implementationText.Contains('contentResponseRequestHeaderFingerprint')) 'persisted content evidence must retain its independent redacted response witness'
  Assert-Contract ($implementationText.Contains('Get-HypiumDeviceProcessState')) 'timeout recovery must probe the application process state'
  Assert-Contract ($implementationText.Contains("'app_exited'")) 'application exit must have an explicit source-state category'
  Assert-Contract ($implementationText.Contains('rawDocumentSha256') -or $implementationText.Contains('RAW_SOURCE_IDENTITY_MISMATCH')) 'implementation must validate immutable raw-document identity'
  Assert-Contract (-not $implementationText.Contains("outcome = 'device_not_v2_enabled'")) 'runtime V2 routing must be proven by the device trace, not a stale database engine-mode snapshot'
  Assert-Contract ($implementationText.Contains('v2_full_cutover_blocked')) 'explicit V2 full-cutover rejections must not be reported as trace mismatches'
  Assert-Contract ((Read-Utf8Script -Path $automationIdentity).Contains('getLegadoSourceAutomationToken')) 'source automation identity must use a safe reversible token'
  Assert-Contract ((Read-Utf8Script -Path $sourceManagementPage).Contains('novel_source_card_${getLegadoSourceAutomationToken(source.id)}')) 'source cards must not expose raw URLs as Hypium selectors'
  Assert-Contract ((Read-Utf8Script -Path $searchPage).Contains('novel_search_single_source_${getLegadoSourceAutomationToken(this.singleSourceId)}')) 'single-source search must expose the selected source identity'
  Assert-Contract ($driverText.Contains('source_automation_token')) 'driver must derive the same source automation token'
  Assert-Contract ($driverText.Contains('SOURCE_FILTER_NO_MATCH')) 'source-name filtering must reject only an actual zero/unparseable result, not a legitimate duplicate-name result'
  Assert-Contract ($driverText.Contains('source_filter_count_ambiguous')) 'duplicate display-name matches must remain visible as structured evidence'
  Assert-Contract (-not $driverText.Contains('SOURCE_FILTER_EXACT_MATCH_COUNT_MISMATCH')) 'duplicate display-name matches must not be rejected by an exact-count runtime gate'
  Assert-Contract ($driverText.Contains('novel_source_card_{source_token}')) 'source filtering must verify the immutable source-card token after a non-unique display-name match'
  Assert-Contract ($driverText.Contains('def wait_for_clickable_with_bounded_scroll') -and $driverText.Contains('scroll_to_target')) 'virtualized source lists must use a bounded semantic scroll helper before declaring a filtered source card or picker item missing'
  Assert-Contract ($implementationText.Contains("`$ExecutionProfile -eq 'safe_read_path'") -and $implementationText.Contains("explore_only_path") -and $implementationText.Contains("Get-HypiumTextProperty -Object `$Source -Name 'exploreUrl'")) 'safe-read dispatch must allow Explore-only sources with no searchUrl instead of policy-blocking every workflow'
  Assert-Contract ($driverText.Contains('single_source_result_container')) 'Hypium evidence must record the result viewport bounds for UI audits'
  Assert-Contract ($driverText.Contains('single_source_trace')) 'Hypium evidence must record the V2 trace bounds for UI audits'
  Assert-Contract ($driverText.Contains('scroll_target=by.type("Scroll")')) 'Explore trace lookup must scroll the result viewport because the trace disclosure is rendered below the result cards'
  Assert-Contract ($driverText.Contains('driver.swipe(UiParam.UP')) 'Explore trace lookup must have a bounded small-step swipe fallback when Hypium scrollSearch rejects the ArkUI viewport'
  Assert-Contract ($driverText.Contains('output=([A-Za-z0-9_:=./,;-]+)$')) 'Explore trace parser must accept semicolon-delimited redacted output subfields'
  Assert-Contract ($driverText.Contains('indexBase=(\d+);resolver=(html_bridge_available|string_fallback)')) 'Hypium parser must retain redacted CSS-index diagnostics without changing search classification'
  Assert-Contract ($driverText.Contains('bookUrlEmpty=(\d+)(?:;bookUrlRule=') -and $driverText.Contains('bookUrlRulePostfixJs=(?:true|false)')) 'Hypium parser must retain redacted search-detail target and V2 rule-provenance evidence'
  Assert-Contract ($driverText.Contains('bookUrlJsMainRuleEmpty') -and $driverText.Contains('bookUrlJsInputJson')) 'Hypium parser must distinguish a missing JS main-rule value from a JS bridge failure'
  Assert-Contract ($driverText.Contains('wait_for_sanitized_workflow_trace_records') -and $driverText.Contains('required_workflow')) 'Hypium safe-read path must wait for TOC after a completed BookInfo trace'
  Assert-Contract ($driverText.Contains('observed_disabled') -and $driverText.Contains('stale proxy is not a product-level disabled state')) 'Hypium must retry a reactive detail control before classifying it as disabled'
  Assert-Contract ($driverText.Contains('DETAIL_TRACE_REHYDRATION_MAX_ATTEMPTS = 3') -and $driverText.Contains('retry_expand_detail_trace_after_rehydration') -and $driverText.Contains('DETAIL_TRACE_REHYDRATION_TOGGLE')) 'Hypium detail diagnostics must retry across the persisted-trace rehydration boundary before classifying a missing disclosure'
  Assert-Contract ($workflowOrchestratorText.Contains('getTraceTargetFingerprint(firstResolvedBookUrl)')) 'V2 search must publish a redacted first detail-target fingerprint'
  Assert-Contract ($driverText.Contains('checkpoint.json')) 'driver must persist a crash-resilient checkpoint'
  Assert-Contract ($driverText.Contains('current_bundle_name')) 'driver must detect foreground-window loss during a workflow'
  Assert-Contract ($driverText.Contains('APP_EXITED_AFTER_SEARCH')) 'driver must classify a post-submit application exit'
  Assert-Contract ($driverText.Contains('UiDriver.connect')) 'driver must use standalone Hypium UiDriver'
  Assert-Contract ($driverText.Contains('driver.close()')) 'driver must release UiDriver in finally'
  Assert-Contract ($driverText.Contains('title_action_back')) 'driver must use semantic back navigation'
  Assert-Contract ((Read-Utf8Script -Path $sourceManagementPage).Contains("novel_source_policy_summary")) 'management page must expose the V2 policy summary through a stable semantic id'
  Assert-Contract ($managementStateProbeText.Contains("parser.add_argument('--hdc-path', required=True)") -and $managementStateProbeText.Contains('def configure_hdc(') -and $managementStateProbeText.Contains("os.environ['PATH']")) 'management aggregate probe must receive an explicit HDC path rather than relying on an ambient shell environment'
  Assert-Contract ($managementStateProbeText.Contains('install_high_forward_port_policy()') -and $managementStateProbeText.Contains('UiDriver.connect(device_sn=args.device_sn)')) 'management aggregate probe must use the repository high-port Hypium policy and an explicit device serial'
  Assert-Contract ($managementStateProbeText.Contains("TOTAL_COUNT_ID = 'novel_source_total_count'") -and $managementStateProbeText.Contains("VERIFIED_COUNT_ID = 'novel_source_v2_verified_count'") -and $managementStateProbeText.Contains("POLICY_SUMMARY_ID = 'novel_source_policy_summary'")) 'management aggregate probe must read only stable aggregate accessibility identities'
  Assert-Contract ($managementStateProbeText.Contains('filter_count = get_optional_text') -and $managementStateProbeText.Contains("result['filter_count_visible']")) 'management aggregate probe must treat conditional filter counts as optional observations'
  Assert-Contract ($managementStateProbeText.Contains('driver.go_home()') -and $managementStateProbeText.Contains('driver.close()') -and $managementStateProbeText.Contains("result['driver_closed'] = True")) 'management aggregate probe must release the driver in its finally path'
  Assert-Contract (-not $managementStateProbeText.Contains('BY.coords') -and -not $managementStateProbeText.Contains('click_by_coordinate')) 'management aggregate probe must not use coordinate-based device control'
  Assert-Contract ((Read-Utf8Script -Path $sourceManagementPage).Contains("novel_source_policy_detail_content")) 'management page must expose expanded V2 policy details through a stable semantic id'
  $sourceManagementText = Read-Utf8Script -Path $sourceManagementPage
  Assert-Contract ($sourceManagementText.Contains("novel_source_management_empty_message")) 'management page must expose an empty-filter anchor without relying on source-card content'
  Assert-Contract ($sourceManagementText.Contains('getFocusController().clearFocus()')) 'management filter submit must dismiss the keyboard through the UIContext focus controller'
  $emptyBuilderStart = $sourceManagementText.IndexOf('  buildEmpty()')
  $emptyBuilderEnd = $sourceManagementText.IndexOf('  buildSourceList()', $emptyBuilderStart)
  Assert-Contract ($emptyBuilderStart -ge 0 -and $emptyBuilderEnd -gt $emptyBuilderStart) 'management empty-state builder must remain independently inspectable'
  $emptyBuilderText = $sourceManagementText.Substring($emptyBuilderStart, $emptyBuilderEnd - $emptyBuilderStart)
  Assert-Contract ($emptyBuilderText.Contains('.justifyContent(FlexAlign.Start)') -and $emptyBuilderText.Contains('.padding({ top: 48 })') -and -not $emptyBuilderText.Contains(".height('100%')")) 'empty management state must start below the filter result instead of centering across the full page'
  Assert-Contract ($driverText.Contains('--safe-ui-audit')) 'driver must support a source-card-free UI evidence mode'
  Assert-Contract ($driverText.Contains('filter_management_to_empty_state')) 'safe UI audit must explicitly filter to the empty management state before capture'
  Assert-Contract ($driverText.Contains('KeyCode.ENTER')) 'safe UI audit must submit the filter and dismiss the keyboard before capture'
  Assert-Contract ($driverText.Contains('if args.capture_visual_evidence and not args.safe_ui_audit:') -and $driverText.Contains('"failure.jpeg"')) 'safe UI audit must never capture a failure screenshot that can contain source cards'
  Assert-Contract ($driverText.Contains('--capture-visual-evidence')) 'source conformance screenshots must require an explicit visual-audit opt-in'
  Assert-Contract (-not $driverText.Contains('06-book-detail.jpeg') -and -not $driverText.Contains('07-reader.jpeg')) 'safe-read conformance must never persist detail or reader screenshots'
  Assert-Contract ($driverText.Contains('evidence["first_search_result"] = component_record(result, redact_source_identity=True)')) 'safe-read evidence must redact search-result ids that can encode book targets'
  $searchPageText = Read-Utf8Script -Path $searchPage
  Assert-Contract ($searchPageText.Contains('novel_search_v2_trace_toggle') -and $searchPageText.Contains('novel_search_v2_trace_detail')) 'single-source outcomes must expose the redacted V2 trace through the stable diagnostic disclosure'
  Assert-Contract ($driverText.Contains('image_trace_event_key') -and $driverText.Contains('post_reader_delta')) 'IMAGE evidence must be delimited to the fresh post-reader HILOG delta'
  Assert-Contract ($driverText.Contains('summarize_image_trace') -and $driverText.Contains('missing_after_image_wait')) 'IMAGE Harness must distinguish a delayed detail disclosure from asset-transport evidence'
  Assert-Contract ($driverText.Contains('if detail_trace_toggle is not None:') -and $driverText.Contains('DETAIL_TRACE_TOGGLE_COLLAPSE')) 'IMAGE detail must collapse its expanded diagnostic before resolving the reader action'
  Assert-Contract ($driverText.Contains('wait_for_positive_detail_chapter_count') -and $driverText.Contains('positive_after_toc_trace')) 'IMAGE Harness must wait for the staged detail projection after a nonempty V2 TOC trace'
  Assert-Contract ($implementationText.Contains('Test-HypiumImageTraceDnsOnly') -and $implementationText.Contains('image_asset_transport_network_dns')) 'IMAGE DNS-only asset failures must be classified as an external endpoint boundary rather than a generic Harness gap'
  $imageTraceResolverStart = $unifiedDetailText.IndexOf('  private getCurrentLegadoV2TraceSourceId()')
  $imageTraceResolverEnd = $unifiedDetailText.IndexOf('  private refreshNovelV2TraceSummary', $imageTraceResolverStart)
  Assert-Contract ($imageTraceResolverStart -ge 0 -and $imageTraceResolverEnd -gt $imageTraceResolverStart) 'Unified detail must expose an independently inspectable V2 trace-key resolver'
  $imageTraceResolverText = $unifiedDetailText.Substring($imageTraceResolverStart, $imageTraceResolverEnd - $imageTraceResolverStart)
  Assert-Contract ($imageTraceResolverText.Contains('UnifiedContentType.MANGA') -and $imageTraceResolverText.Contains('LegadoMangaSourceBridge.isLegadoMangaPkg') -and $imageTraceResolverText.Contains('this.content.sourceUrl')) 'IMAGE detail trace lookup must use the original Legado bookSourceUrl instead of the numeric comic source id'
  Assert-Contract ($unifiedDetailText.Contains('this.refreshNovelV2TraceSummary();') -and $unifiedDetailText.Contains('this.scheduleNovelV2TraceRehydration();')) 'IMAGE bridge completion must refresh persisted BookInfo/TOC evidence into the shared detail disclosure'
  $webViewComponentText = Read-Utf8Script -Path $webViewComponent
  Assert-Contract (-not $webViewComponentText.Contains('Pixel 5) AppleWebKit')) 'ArkWeb component must not globally override the platform User-Agent for empty Legado source headers'
  foreach ($forbidden in @('uitest', 'uiInput', 'snapshot_display', 'aa start', 'shell aa')) {
    Assert-Contract (-not $legacyText.Contains($forbidden)) "legacy entry contains forbidden UI control token: $forbidden"
    Assert-Contract (-not $implementationText.Contains($forbidden)) "implementation contains forbidden UI control token: $forbidden"
    Assert-Contract (-not $driverText.Contains($forbidden)) "driver contains forbidden UI control token: $forbidden"
  }
  $result = [pscustomobject][ordered]@{ status = 'passed'; runner = 'Invoke-LegadoV2HypiumFullSourceDeviceRunner.ps1'; deviceControl = 'hypium_standalone_uidriver'; assertions = $script:AssertionCount; generatedAt = [DateTimeOffset]::UtcNow.ToString('o') }
} catch {
  $result = [pscustomobject][ordered]@{ status = 'failed'; error = $_.Exception.Message; generatedAt = [DateTimeOffset]::UtcNow.ToString('o') }
}

$directory = Split-Path -Parent $ResultPath
if (-not (Test-Path -LiteralPath $directory)) { [void][System.IO.Directory]::CreateDirectory($directory) }
[System.IO.File]::WriteAllText($ResultPath, [string]($result | ConvertTo-Json -Depth 10), [System.Text.UTF8Encoding]::new($false))
$result | ConvertTo-Json -Depth 10
if ($result.status -ne 'passed') { exit 1 }
