[CmdletBinding()]
param(
  [string]$RepositoryRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

function Read-Utf8Text {
  param([Parameter(Mandatory = $true)][string]$Path)
  $utf8 = New-Object System.Text.UTF8Encoding($false, $true)
  return [System.IO.File]::ReadAllText($Path, $utf8)
}

function Assert-Contract {
  param(
    [Parameter(Mandatory = $true)][bool]$Condition,
    [Parameter(Mandatory = $true)][string]$Message
  )
  if (-not $Condition) {
    throw "Logger contract failed: $Message"
  }
}

$loggerPath = Join-Path $RepositoryRoot 'entry\src\main\ets\Utils\Logger.ets'
$tracePath = Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Network\LegadoImageTransportTrace.ets'
$monitorPath = Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Debug\ErrorMonitorService.ets'
$testPath = Join-Path $RepositoryRoot 'entry\src\ohosTest\ets\test\LoggerBackgroundOutputConformance.test.ets'

$loggerText = Read-Utf8Text -Path $loggerPath
$traceText = Read-Utf8Text -Path $tracePath
$monitorText = Read-Utf8Text -Path $monitorPath
$testText = Read-Utf8Text -Path $testPath

Assert-Contract ($loggerText.Contains('public warnForEvidence(')) 'Logger must expose the evidence WARN entry point.'

$ordinaryWarnStart = $loggerText.IndexOf('public warn(')
$evidenceWarnStart = $loggerText.IndexOf('public warnForEvidence(', $ordinaryWarnStart + 1)
Assert-Contract ($ordinaryWarnStart -ge 0) 'Logger must retain the ordinary WARN entry point.'
Assert-Contract ($evidenceWarnStart -gt $ordinaryWarnStart) 'The evidence WARN entry point must follow ordinary WARN.'
$ordinaryWarnText = $loggerText.Substring($ordinaryWarnStart, $evidenceWarnStart - $ordinaryWarnStart)
Assert-Contract ($ordinaryWarnText.Contains('this.currentLevel <= LogLevel.WARN')) 'Ordinary WARN must retain current-level filtering.'
Assert-Contract ($ordinaryWarnText.Contains('this.shouldSkipForBackgroundPause(LogLevel.WARN)')) 'Ordinary WARN must retain background pause filtering.'
Assert-Contract ($ordinaryWarnText.Contains('this.outputWarn(tag, message, args, false);')) 'Ordinary WARN must use the filtered hilog path.'

$outputWarnStart = $loggerText.IndexOf('private outputWarn(')
Assert-Contract ($outputWarnStart -gt $evidenceWarnStart) 'Logger must retain the shared WARN output implementation.'
$evidenceWarnText = $loggerText.Substring($evidenceWarnStart, $outputWarnStart - $evidenceWarnStart)
Assert-Contract ($evidenceWarnText.Contains('this.outputWarn(tag, message, args, true);')) 'Evidence WARN must force hilog output.'
Assert-Contract (-not $evidenceWarnText.Contains('currentLevel')) 'Evidence WARN must not use current-level filtering.'
Assert-Contract (-not $evidenceWarnText.Contains('shouldOutputToHilog')) 'Evidence WARN must not use hilog-level filtering.'
Assert-Contract (-not $evidenceWarnText.Contains('shouldSkipForBackgroundPause')) 'Evidence WARN must not use background pause filtering.'

$outputWarnEnd = $loggerText.IndexOf('/**', $outputWarnStart + 1)
Assert-Contract ($outputWarnEnd -gt $outputWarnStart) 'The WARN output implementation boundary must be detectable.'
$outputWarnText = $loggerText.Substring($outputWarnStart, $outputWarnEnd - $outputWarnStart)
Assert-Contract ($outputWarnText.Contains('forceHilogOutput || this.shouldOutputToHilog(LogLevel.WARN)')) 'Evidence WARN must bypass OFF hilog configuration.'
Assert-Contract ($outputWarnText.Contains('hilog.warn(LOG_DOMAIN, Flag')) 'Evidence WARN must retain WARN hilog semantics.'
Assert-Contract ($outputWarnText.Contains('logCollector.addLog(LogLevel.WARN')) 'Evidence WARN must remain WARN in the unified collector.'
Assert-Contract (-not $outputWarnText.Contains('this.currentLevel')) 'Shared WARN output must not filter forced evidence by current level.'
Assert-Contract (-not $outputWarnText.Contains('shouldSkipForBackgroundPause')) 'Shared WARN output must not filter forced evidence by background pause.'

$evidenceCallCount = ([regex]::Matches($traceText, 'logger\.warnForEvidence\(')).Count
Assert-Contract ($evidenceCallCount -eq 2) 'IMAGE trace payload and serialization fallback must both use evidence WARN.'
Assert-Contract (-not $traceText.Contains('logger.warn(')) 'IMAGE trace must not fall back to pause-sensitive WARN.'
Assert-Contract (-not $traceText.Contains('logger.error(')) 'IMAGE evidence must not be promoted to ERROR.'
Assert-Contract ($monitorText.Contains('if (entry.level < LogLevel.ERROR)')) 'ErrorMonitor must continue ignoring WARN entries.'
Assert-Contract ($testText.Contains('logger.setLevel(LogLevel.FATAL);')) 'Device conformance must cover FATAL current-level filtering.'
Assert-Contract ($testText.Contains('logger.setHilogOutputLevel(LogLevel.OFF);')) 'Device conformance must cover OFF hilog filtering.'
Assert-Contract ($testText.Contains("logger.warn(tag, 'ordinary-warning-must-remain-filtered');")) 'Device conformance must prove ordinary WARN remains filtered.'
Assert-Contract ($testText.Contains("logger.warnForEvidence(tag, 'evidence-warning-must-remain-visible');")) 'Device conformance must prove evidence WARN remains visible.'
Assert-Contract ($testText.Contains('expect(entries[0].level).assertEqual(LogLevel.WARN);')) 'Device conformance must preserve WARN severity.'

[PSCustomObject]@{
  status = 'passed'
  evidenceWarnCalls = $evidenceCallCount
  collectorLevel = 'WARN'
  errorMonitorThreshold = 'ERROR'
  bypassedEvidenceFilters = @('currentLevel', 'hilogOutputLevel', 'backgroundPause')
} | ConvertTo-Json -Compress
