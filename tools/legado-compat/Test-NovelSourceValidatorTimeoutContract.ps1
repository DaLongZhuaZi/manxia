[CmdletBinding()]
param(
  [string]$RepositoryRoot = ''
)

$ErrorActionPreference = 'Stop'

function Resolve-RepositoryRoot {
  param([string]$RequestedRoot)

  if (-not [string]::IsNullOrWhiteSpace($RequestedRoot)) {
    return (Resolve-Path -LiteralPath $RequestedRoot).Path
  }
  return (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}

function Read-Utf8Text {
  param(
    [string]$Root,
    [string]$RelativePath
  )

  $path = Join-Path $Root $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "Novel source validator timeout contract failed: missing file $RelativePath"
  }
  return [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
}

function Assert-Contract {
  param(
    [bool]$Condition,
    [string]$Message
  )

  if (-not $Condition) {
    throw "Novel source validator timeout contract failed: $Message"
  }
}

function Assert-Contains {
  param(
    [string]$Text,
    [string]$Expected,
    [string]$Scope
  )

  Assert-Contract ($Text.Contains($Expected)) "$Scope is missing '$Expected'"
}

$root = Resolve-RepositoryRoot -RequestedRoot $RepositoryRoot
$validatorText = Read-Utf8Text -Root $root -RelativePath 'entry\src\main\ets\Framework\Novel\NovelSourceValidator.ets'
$deadlineText = Read-Utf8Text -Root $root -RelativePath 'entry\src\main\ets\Framework\Novel\NovelSourceValidationDeadline.ets'
$tokenText = Read-Utf8Text -Root $root -RelativePath 'entry\src\main\ets\Framework\Novel\LegadoExecutionCancellation.ets'
$pipelineText = Read-Utf8Text -Root $root -RelativePath 'entry\src\main\ets\Framework\Novel\LegadoRequestPipeline.ets'
$webViewText = Read-Utf8Text -Root $root -RelativePath 'entry\src\main\ets\Framework\Novel\LegadoWebViewExecutor.ets'
$managerText = Read-Utf8Text -Root $root -RelativePath 'entry\src\main\ets\Framework\Novel\NovelSourceManager.ets'
$testText = Read-Utf8Text -Root $root -RelativePath 'entry\src\ohosTest\ets\test\LegadoCancellationConformance.test.ets'
$testListText = Read-Utf8Text -Root $root -RelativePath 'entry\src\ohosTest\ets\test\List.test.ets'

Assert-Contains $validatorText "import { awaitNovelSourceValidationTask } from './NovelSourceValidationDeadline';" 'validator wiring'
Assert-Contains $validatorText 'await awaitNovelSourceValidationTask(' 'validator wiring'
Assert-Contains $validatorText '(): Promise<void> => this.doValidateSource(' 'validator task factory'
Assert-Contains $validatorText 'NovelSourceValidator.SOURCE_TIMEOUT_REASON' 'validator timeout classification'
Assert-Contract (-not $validatorText.Contains('Promise.race')) 'validator still uses Promise.race'

Assert-Contains $deadlineText 'export type NovelSourceValidationTaskFactory = () => Promise<void>;' 'deadline task factory'
Assert-Contains $deadlineText 'listenerId = cancellationToken.register' 'deadline cancellation listener'
Assert-Contains $deadlineText 'timerId = setTimeout' 'deadline timer'
Assert-Contains $deadlineText 'cancellationToken.cancel(timeoutReason);' 'deadline cancellation propagation'
Assert-Contains $deadlineText 'clearTimeout(timerId);' 'deadline timer cleanup'
Assert-Contains $deadlineText 'cancellationToken.unregister(listenerId);' 'deadline listener cleanup'
Assert-Contains $deadlineText 'clearResources();' 'deadline synchronous cleanup'
Assert-Contains $deadlineText 'MAX_TIMER_DELAY_MS' 'deadline overflow guard'

$listenerPosition = $deadlineText.IndexOf('listenerId = cancellationToken.register', [System.StringComparison]::Ordinal)
$timerPosition = $deadlineText.IndexOf('timerId = setTimeout', [System.StringComparison]::Ordinal)
$taskPosition = $deadlineText.IndexOf('task = taskFactory();', [System.StringComparison]::Ordinal)
Assert-Contract ($listenerPosition -ge 0 -and $listenerPosition -lt $taskPosition) 'cancellation listener is not installed before task start'
Assert-Contract ($timerPosition -ge 0 -and $timerPosition -lt $taskPosition) 'deadline timer is not installed before task start'
Assert-Contract (-not [regex]::IsMatch($deadlineText, '\b(any|unknown|ESObject)\b')) 'deadline helper violates strict ArkTS type rules'

Assert-Contains $tokenText 'const callbacks: LegadoCancellationListener[] = [];' 'token listener snapshot'
Assert-Contains $tokenText 'this.listeners.clear();' 'token listener release'
Assert-Contains $pipelineText 'cancellationListenerId = cancellationToken.register' 'HTTP transport cancellation listener'
Assert-Contains $pipelineText 'request.destroy();' 'HTTP transport request abort'
Assert-Contains $pipelineText 'cancellationToken.unregister(cancellationListenerId);' 'HTTP transport listener cleanup'
Assert-Contains $webViewText 'options.cancellationToken.register' 'ArkWeb cancellation listener'
Assert-Contains $webViewText 'this.webviewController.stop();' 'ArkWeb request abort'
Assert-Contains $webViewText 'clearTimeout(task.timeoutId);' 'ArkWeb timer cleanup'
Assert-Contains $webViewText 'task.options.cancellationToken.unregister(task.cancellationListenerId);' 'ArkWeb listener cleanup'

foreach ($workflowMethod in @(
  'v2Executor.search(keyword, page, cancellationToken)',
  'v2Executor.getBookInfo(bookUrl, cancellationToken)',
  'v2Executor.getChapterList(book, cancellationToken)',
  'v2Executor.getContent(chapter, cancellationToken)',
  'v2Executor.getExploreKindsAsync(cancellationToken)',
  'v2Executor.explore(exploreUrl, page, cancellationToken)'
)) {
  Assert-Contains $managerText $workflowMethod 'V2 manager cancellation propagation'
}

foreach ($testName in @(
  'clearsValidationDeadlineAfterSuccess',
  'clearsValidationDeadlineAfterFailure',
  'cancelsActiveValidationTaskWhenDeadlineExpires',
  'doesNotStartValidationTaskAfterPreCancellation'
)) {
  Assert-Contains $testText $testName 'device timeout conformance'
}
Assert-Contains $testListText 'legadoCancellationConformanceTest();' 'device conformance registration'

$result = [ordered]@{
  status = 'passed'
  validatorUsesTaskFactory = $true
  promiseRaceRemoved = $true
  successTimerCleanupCovered = $true
  failureTimerCleanupCovered = $true
  timeoutCancelsTransportToken = $true
  preCancelledTaskBlocked = $true
  httpRequestDestroyWired = $true
  arkWebAbortWired = $true
  strictArkTsDeadlineHelper = $true
}

$result | ConvertTo-Json -Depth 4
