[CmdletBinding()]
param([string]$RepoRoot = '', [string]$ResultPath = '')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Contract {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "ArkWeb lifecycle diagnostic contract failed: $Message" }
}

function Read-Utf8Text {
  param([string]$Path)
  Assert-Contract (Test-Path -LiteralPath $Path -PathType Leaf) "missing file: $Path"
  return [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false, $true))
}

if ($RepoRoot.Length -eq 0) {
  $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
} else {
  $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
}
if ($ResultPath.Length -eq 0) {
  $ResultPath = Join-Path $RepoRoot 'tools\legado-compat\evidence\arkweb-lifecycle-diagnostic-contract.json'
}

$executorPath = Join-Path $RepoRoot 'entry\src\main\ets\Framework\Novel\LegadoWebViewExecutor.ets'
$pipelinePath = Join-Path $RepoRoot 'entry\src\main\ets\Framework\Novel\LegadoRequestPipeline.ets'
$workflowPath = Join-Path $RepoRoot 'entry\src\main\ets\Framework\Novel\LegadoWorkflowOrchestrator.ets'
$driverPath = Join-Path $RepoRoot 'tools\legado-compat\Invoke-LegadoV2HypiumNavigation.py'

try {
  $executor = Read-Utf8Text -Path $executorPath
  $pipeline = Read-Utf8Text -Path $pipelinePath
  $workflow = Read-Utf8Text -Path $workflowPath
  $driver = Read-Utf8Text -Path $driverPath
  foreach ($marker in @(
    'lifecycleStage: string;',
    'pageBeginCount: number;',
    'targetNavigationBeginCount: number;',
    'runtimePageBeginCount: number;',
    'nonRuntimePageBeginCount: number;',
    'pageEndCount: number;',
    'mainFrameErrorCount: number;',
    'lastMainFrameStatusCode: number;',
    'buildTimeoutDiagnostic(task: WebViewTask)',
    'buildPageErrorDiagnostic(task: WebViewTask, errorCode: number)',
    'WEBVIEW_TIMEOUT;ownership=',
    'target_navigation_started',
    'target_navigation_finished',
    'main_frame_error'
  )) {
    Assert-Contract ($executor.Contains($marker)) "missing lifecycle marker: $marker"
  }
  Assert-Contract ($executor.Contains('this.abortTask(task, new Error(this.buildTimeoutDiagnostic(task)));')) 'timeout must emit the lifecycle diagnostic'
  Assert-Contract ($executor.Contains('error: this.buildPageErrorDiagnostic(this.currentTask, errorCode)')) 'main-frame errors must expose only the fixed URL-free diagnostic'
  Assert-Contract ($executor.Contains('runtimeBegin=${task.runtimePageBeginCount};nonRuntimeBegin=${task.nonRuntimePageBeginCount}')) 'timeout must distinguish runtime-page events from non-runtime events without exposing URLs'
  Assert-Contract ($executor.Contains('lastMainFrameStatusCode = errorCode >= 400 ? errorCode : 0;')) 'HTTP status must be recorded without response content'
  Assert-Contract ($pipeline.Contains('result.error ||')) 'ArkWeb transport must propagate the redacted-safe executor failure reason'
  Assert-Contract ($workflow.Contains('getSearchFailureSummary(response)')) 'search failure summary must consume a safe ArkWeb lifecycle diagnostic'
  Assert-Contract ($workflow.Contains('WEBVIEW_TIMEOUT;') -and $workflow.Contains('WEBVIEW_ERROR;')) 'workflow must require the fixed ArkWeb lifecycle markers'
  Assert-Contract ($workflow.Contains('runtimeBegin=\d+;nonRuntimeBegin=\d+')) 'workflow must preserve the URL-free event-class counters'
  Assert-Contract ($driver.Contains('WEBVIEW_TIMEOUT_PATTERN')) 'Hypium driver must validate lifecycle evidence before persisting it'
  Assert-Contract ($driver.Contains('webViewLifecycle')) 'Hypium driver must emit the validated lifecycle evidence'
  $result = [pscustomobject][ordered]@{ status = 'passed'; assertions = 18; generatedAt = [DateTimeOffset]::UtcNow.ToString('o') }
} catch {
  $result = [pscustomobject][ordered]@{ status = 'failed'; error = $_.Exception.Message; generatedAt = [DateTimeOffset]::UtcNow.ToString('o') }
}

$directory = Split-Path -Parent $ResultPath
if (-not (Test-Path -LiteralPath $directory)) { [void][System.IO.Directory]::CreateDirectory($directory) }
[System.IO.File]::WriteAllText($ResultPath, [string]($result | ConvertTo-Json -Depth 5), [System.Text.UTF8Encoding]::new($false))
$result | ConvertTo-Json -Depth 5
if ($result.status -ne 'passed') { exit 1 }
