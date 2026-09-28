[CmdletBinding()]
param(
  [string]$HdcPath = 'F:\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe',
  [string]$Device = '',
  [ValidateSet('safe_search_only', 'safe_read_path', 'full_workflow')]
  [string]$ExecutionProfile = 'safe_search_only',
  [ValidateRange(1, 458)]
  [int]$MaxSources = 458,
  [ValidateRange(-1, 457)]
  [int]$OnlyOrdinal = -1,
  [ValidateRange(1, 60)]
  [int]$MinRequestIntervalSeconds = 2,
  [ValidateRange(45, 120)]
  [int]$UiTimeoutSeconds = 105,
  [switch]$RevalidateTerminalSources
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$runnerPath = Join-Path $PSScriptRoot 'Invoke-LegadoV2HypiumFullSourceDeviceRunner.ps1'
$evidencePathsModulePath = Join-Path $PSScriptRoot 'LegadoHypiumEvidencePaths.psm1'
if (-not (Test-Path -LiteralPath $evidencePathsModulePath)) {
  throw "HYPIUM_EVIDENCE_PATHS_MODULE_MISSING:$evidencePathsModulePath"
}
Import-Module -Name $evidencePathsModulePath -Force -ErrorAction Stop
$baselineEvidenceDirectory = Get-LegadoHypiumCanonicalEvidenceDirectory -ScriptRoot $PSScriptRoot
$controlDirectory = Join-Path (Get-LegadoHypiumEvidenceRoot -ScriptRoot $PSScriptRoot) 'full-source-v2-hypium-device-control'
$manifestPath = Join-Path $controlDirectory 'detached-run.json'

if (-not (Test-Path -LiteralPath $runnerPath)) {
  throw "RUNNER_MISSING:$runnerPath"
}
New-Item -ItemType Directory -Path $controlDirectory -Force | Out-Null

if (Test-Path -LiteralPath $manifestPath) {
  $existingText = [System.IO.File]::ReadAllText($manifestPath, [System.Text.UTF8Encoding]::new($false, $true))
  $existing = $existingText | ConvertFrom-Json
  $existingPidProperty = $existing.PSObject.Properties['processId']
  if ($null -ne $existingPidProperty) {
    $existingProcess = Get-Process -Id ([int]$existingPidProperty.Value) -ErrorAction SilentlyContinue
    if ($null -ne $existingProcess) {
      $expectedStartedAt = ''
      $recordedProcessStartedAt = $existing.PSObject.Properties['processStartedAt']
      if ($null -ne $recordedProcessStartedAt -and $null -ne $recordedProcessStartedAt.Value) {
        $expectedStartedAt = [string]$recordedProcessStartedAt.Value
      } else {
        # Compatibility with manifests written before processStartedAt existed.
        # The detached process is launched immediately before startedAt is
        # recorded, so a small bounded window distinguishes it from a recycled
        # PID without trusting the PID alone.
        $legacyStartedAt = $existing.PSObject.Properties['startedAt']
        if ($null -ne $legacyStartedAt -and $null -ne $legacyStartedAt.Value) {
          $expectedStartedAt = [string]$legacyStartedAt.Value
        }
      }
      $isSameDetachedProcess = $false
      if ($expectedStartedAt.Length -gt 0) {
        try {
          $expectedStart = [DateTimeOffset]::Parse($expectedStartedAt)
          $actualStart = [DateTimeOffset]$existingProcess.StartTime.ToUniversalTime()
          $startDeltaSeconds = [Math]::Abs(($actualStart - $expectedStart).TotalSeconds)
          $allowedStartDeltaSeconds = if ($null -ne $recordedProcessStartedAt) { 1.0 } else { 120.0 }
          $isSameDetachedProcess = $startDeltaSeconds -le $allowedStartDeltaSeconds
        } catch {
          $isSameDetachedProcess = $false
        }
      }
      if ($isSameDetachedProcess) {
        throw "RUNNER_ALREADY_ACTIVE:pid=$($existingProcess.Id)"
      }
      Write-Warning "STALE_RUNNER_MANIFEST_PID_REUSED: pid=$($existingProcess.Id); recordedStart=$expectedStartedAt; actualStart=$($existingProcess.StartTime.ToUniversalTime().ToString('o'))"
    }
  }
}

$evidenceDirectory = New-LegadoHypiumRunEvidenceDirectory -ScriptRoot $PSScriptRoot
$stdoutPath = Join-Path $evidenceDirectory 'detached-run.stdout.log'
$stderrPath = Join-Path $evidenceDirectory 'detached-run.stderr.log'
New-Item -ItemType Directory -Path $evidenceDirectory -Force | Out-Null

function ConvertTo-DetachedSingleQuotedLiteral {
  param([string]$Value)
  return "'" + $Value.Replace("'", "''") + "'"
}

# Start-Process flattens ArgumentList on Windows. A raw `-File` invocation
# would split SDK paths such as `F:\DevEco Studio\...` at the space and cause
# a false REQUIRED_PATH_MISSING preflight. Use an explicit encoded PowerShell
# command so every forwarded argument remains one literal value.
$commandParts = [System.Collections.Generic.List[string]]::new()
[void]$commandParts.Add("`$ErrorActionPreference = 'Stop';")
[void]$commandParts.Add('& ' + (ConvertTo-DetachedSingleQuotedLiteral -Value $runnerPath))
foreach ($argumentPair in @(
  @('-HdcPath', $HdcPath),
  @('-ExecutionProfile', $ExecutionProfile),
  @('-EvidenceDirectory', $evidenceDirectory),
  @('-MaxSources', [string]$MaxSources),
  @('-OnlyOrdinal', [string]$OnlyOrdinal),
  @('-MinRequestIntervalSeconds', [string]$MinRequestIntervalSeconds),
  @('-UiTimeoutSeconds', [string]$UiTimeoutSeconds)
)) {
  [void]$commandParts.Add([string]$argumentPair[0])
  [void]$commandParts.Add((ConvertTo-DetachedSingleQuotedLiteral -Value ([string]$argumentPair[1])))
}
if ($Device.Length -gt 0) {
  [void]$commandParts.Add('-Device')
  [void]$commandParts.Add((ConvertTo-DetachedSingleQuotedLiteral -Value $Device))
}
if ($RevalidateTerminalSources) {
  [void]$commandParts.Add('-RevalidateTerminalSources')
}
$encodedCommand = [Convert]::ToBase64String([System.Text.UnicodeEncoding]::new().GetBytes(($commandParts -join ' ')))

Remove-Item -LiteralPath $stdoutPath -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $stderrPath -Force -ErrorAction SilentlyContinue
$process = Start-Process -FilePath 'pwsh.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encodedCommand) -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -PassThru
$manifest = [pscustomobject][ordered]@{
  schemaVersion = 1
  startedAt = [DateTimeOffset]::UtcNow.ToString('o')
  processId = $process.Id
  processStartedAt = ([DateTimeOffset]$process.StartTime.ToUniversalTime()).ToString('o')
  executionProfile = $ExecutionProfile
  onlyOrdinal = $OnlyOrdinal
  maxSources = $MaxSources
  revalidateTerminalSources = [bool]$RevalidateTerminalSources
  baselineEvidenceDirectory = (ConvertTo-LegadoHypiumEvidenceRelativePath -ScriptRoot $PSScriptRoot -Path $baselineEvidenceDirectory)
  controlDirectory = (ConvertTo-LegadoHypiumEvidenceRelativePath -ScriptRoot $PSScriptRoot -Path $controlDirectory)
  runEvidenceDirectory = (ConvertTo-LegadoHypiumEvidenceRelativePath -ScriptRoot $PSScriptRoot -Path $evidenceDirectory)
  runActivityPath = (ConvertTo-LegadoHypiumEvidenceRelativePath -ScriptRoot $PSScriptRoot -Path (Join-Path $evidenceDirectory 'run-activity.json'))
  stdoutPath = (ConvertTo-LegadoHypiumEvidenceRelativePath -ScriptRoot $PSScriptRoot -Path $stdoutPath)
  stderrPath = (ConvertTo-LegadoHypiumEvidenceRelativePath -ScriptRoot $PSScriptRoot -Path $stderrPath)
}
$temporaryPath = "$manifestPath.tmp-$PID"
[System.IO.File]::WriteAllText($temporaryPath, ($manifest | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($false))
Move-Item -LiteralPath $temporaryPath -Destination $manifestPath -Force
$manifest | ConvertTo-Json -Depth 8
