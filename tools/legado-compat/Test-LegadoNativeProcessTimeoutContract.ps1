[CmdletBinding()]
param(
  [Alias('RepositoryRoot')]
  [string]$RepoRoot = '',
  [switch]$SkipWindowsPowerShellChild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($RepoRoot.Length -eq 0) {
  $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

$helperPath = Join-Path $RepoRoot 'tools\legado-compat\Invoke-LegadoNativeProcess.ps1'
$controllerPath = Join-Path $RepoRoot 'tools\legado-compat\Invoke-LegadoCompatibility.ps1'
$flowPath = Join-Path $RepoRoot 'tools\legado-compat\Invoke-LegadoV2RealDeviceFlow.ps1'
$referencePath = Join-Path $RepoRoot 'tools\legado-compat\Invoke-LegadoLiveReference.ps1'

function Assert-Contract {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) {
    throw "Native process timeout contract failed: $Message"
  }
}

function Get-ScriptAst {
  param([string]$Path)
  Assert-Contract (Test-Path -LiteralPath $Path) "missing script: $Path"
  $tokens = $null
  $errors = $null
  $ast = [System.Management.Automation.Language.Parser]::ParseFile(
    $Path,
    [ref]$tokens,
    [ref]$errors
  )
  Assert-Contract ($errors.Count -eq 0) "parser errors in $Path"
  return $ast
}

function Get-FunctionText {
  param(
    [System.Management.Automation.Language.ScriptBlockAst]$Ast,
    [string]$Name
  )
  $match = $Ast.Find(
    {
      param($node)
      return $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -eq $Name
    },
    $true
  )
  Assert-Contract ($null -ne $match) "missing function: $Name"
  return $match.Extent.Text
}

function Assert-Contains {
  param([string]$Text, [string]$Expected, [string]$Label)
  Assert-Contract (
    $Text.IndexOf($Expected, [System.StringComparison]::Ordinal) -ge 0
  ) "$Label missing marker: $Expected"
}

$helperAst = Get-ScriptAst -Path $helperPath
$controllerAst = Get-ScriptAst -Path $controllerPath
$flowAst = Get-ScriptAst -Path $flowPath
$referenceAst = Get-ScriptAst -Path $referencePath
$helperText = Get-FunctionText -Ast $helperAst -Name 'Invoke-LegadoNativeProcess'
$treeKillText = Get-FunctionText -Ast $helperAst -Name 'Stop-LegadoNativeProcessTree'
$flowHdcText = Get-FunctionText -Ast $flowAst -Name 'Invoke-Hdc'
$referenceAdbText = Get-FunctionText -Ast $referenceAst -Name 'Invoke-Adb'
$stage7Text = Get-FunctionText -Ast $controllerAst -Name 'Invoke-Stage7RealUserFlow'
$stage7AText = Get-FunctionText -Ast $controllerAst -Name 'Invoke-Stage7ALiveReference'
$boundedControllerText = Get-FunctionText -Ast $controllerAst -Name 'Invoke-BoundedNativeCommand'
$harmonyConformanceText = Get-FunctionText -Ast $controllerAst -Name 'Invoke-HarmonyConformance'
$androidReferenceText = Get-FunctionText -Ast $controllerAst -Name 'Invoke-AndroidReference'

Assert-Contains $helperText 'RedirectStandardOutput = $true' 'helper'
Assert-Contains $helperText 'RedirectStandardError = $true' 'helper'
Assert-Contains $helperText 'ReadToEndAsync()' 'helper'
Assert-Contains $helperText 'WaitForExit($TimeoutSeconds * 1000)' 'helper'
Assert-Contains $helperText 'Stop-LegadoNativeProcessTree' 'helper'
Assert-Contains $helperText '$processJob.Terminate(124)' 'job process tree termination'
Assert-Contains $helperText "classification = if (`$timedOut) { 'timeout' }" 'helper'
Assert-Contains $treeKillText '/T /F' 'process tree termination'
Assert-Contains $flowHdcText 'Invoke-LegadoNativeProcess' 'Stage 7 HDC wrapper'
Assert-Contains $flowHdcText '$result.timedOut' 'Stage 7 HDC wrapper'
Assert-Contains $referenceAdbText 'Invoke-LegadoNativeProcess' 'Stage 7A ADB wrapper'
Assert-Contains $referenceAdbText '$result.timedOut' 'Stage 7A ADB wrapper'
Assert-Contains $stage7Text '-TimeoutSeconds 2700' 'Stage 7 process boundary'
Assert-Contains $stage7Text '$flowResult.timedOut' 'Stage 7 process boundary'
Assert-Contains $stage7AText '-TimeoutSeconds 1200' 'Stage 7A process boundary'
Assert-Contains $stage7AText '$referenceResult.timedOut' 'Stage 7A process boundary'
Assert-Contains $boundedControllerText 'Invoke-LegadoBatchProcess' 'controller batch boundary'
Assert-Contains $boundedControllerText 'Invoke-LegadoNativeProcess' 'controller executable boundary'
Assert-Contains $boundedControllerText '$result.timedOut' 'controller timeout classification'
Assert-Contains $harmonyConformanceText "'aa', 'test'" 'Harmony aa test boundary'
Assert-Contains $harmonyConformanceText '-TimeoutSeconds 900' 'Harmony aa test boundary'
Assert-Contains $harmonyConformanceText '-TimeoutSeconds 1800' 'Hvigor build boundary'
Assert-Contains $androidReferenceText '-TimeoutSeconds 1800' 'Android Gradle boundary'
Assert-Contains $androidReferenceText 'LegadoReferenceGradleInitScript' 'Android reference plugin-resolution bootstrap'
Assert-Contains $androidReferenceText "'--init-script'" 'Android reference Gradle init-script argument'
Assert-Contains $androidReferenceText '$env:JAVA_HOME = $Toolchain.java17Home' 'Android reference Java 17 runtime selection'
Assert-Contains $androidReferenceText 'Join-Path $Toolchain.java17Home' 'Android reference Java 17 PATH selection'
Assert-Contains $androidReferenceText 'android-gradle-home-$StageKey-$gradleRunId' 'Android reference must isolate each Gradle cache run rather than deleting a locked previous transform workspace'
Assert-Contains $androidReferenceText "[System.IO.Path]::GetTempPath()" 'Android reference Gradle transforms must run outside the workspace volume that is subject to project-cache locking'
Assert-Contains $androidReferenceText 'org.gradle.workers.max=1' 'Android reference must cap Gradle workers for deterministic artifact transforms'
Assert-Contains $androidReferenceText "'--max-workers=1'" 'Android reference must pass the single-worker constraint to Gradle'
Assert-Contains $androidReferenceText "'--no-parallel'" 'Android reference must disable parallel project execution for artifact-transform stability'

$flowSource = [System.IO.File]::ReadAllText($flowPath, [System.Text.UTF8Encoding]::new($false))
$referenceSource = [System.IO.File]::ReadAllText($referencePath, [System.Text.UTF8Encoding]::new($false))
$controllerSource = [System.IO.File]::ReadAllText($controllerPath, [System.Text.UTF8Encoding]::new($false))
Assert-Contract (([regex]::Matches($flowSource, '& \$HdcPath')).Count -eq 0) `
  'Stage 7 contains an unbounded direct HDC invocation'
Assert-Contract (([regex]::Matches($referenceSource, '& \$AdbPath')).Count -eq 0) `
  'Stage 7A contains an unbounded direct ADB invocation'
Assert-Contract (([regex]::Matches($controllerSource, '& \$Toolchain\.(adb|hdc|hvigor)')).Count -eq 0) `
  'controller contains an unbounded direct ADB, HDC, or Hvigor invocation'
Assert-Contract ($controllerSource.IndexOf('Invoke-NativeCommandCapture', [System.StringComparison]::Ordinal) -lt 0) `
  'controller still contains the unbounded legacy native capture helper'

. $helperPath

$fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) `
  ("manxia native timeout contract $PID $([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())")
$fixturePath = Join-Path $fixtureRoot 'native-fixture.ps1'
$batchFixturePath = Join-Path $fixtureRoot 'batch fixture.cmd'
$childPidPath = Join-Path $fixtureRoot 'child.pid'
$fixtureBody = @'
param(
  [string]$Mode,
  [string]$EchoValue,
  [string]$ChildPidPath
)
[Console]::Out.WriteLine("stdout-$Mode-$EchoValue")
[Console]::Error.WriteLine("stderr-$Mode")
[Console]::Out.Flush()
[Console]::Error.Flush()
if ($Mode -eq 'failure') {
  exit 23
}
if ($Mode -eq 'timeout') {
  $child = Start-Process -FilePath $env:ComSpec -ArgumentList @('/d', '/c', 'ping -n 60 127.0.0.1 > nul') -WindowStyle Hidden -PassThru
  [System.IO.File]::WriteAllText($ChildPidPath, [string]$child.Id, [System.Text.Encoding]::ASCII)
  Start-Sleep -Seconds 60
}
exit 0
'@
[System.IO.Directory]::CreateDirectory($fixtureRoot) | Out-Null
[System.IO.File]::WriteAllText($fixturePath, $fixtureBody, [System.Text.Encoding]::ASCII)
$batchFixtureBody = @'
@echo off
set /p contractInput=
echo batch-arg=%~1
echo batch-input=%contractInput%
1>&2 echo batch-stderr
exit /b 19
'@
[System.IO.File]::WriteAllText($batchFixturePath, $batchFixtureBody, [System.Text.Encoding]::ASCII)

$hostExecutable = Get-LegadoNativeHostExecutable
$echoValue = 'value with spaces (contract)'
try {
  $success = Invoke-LegadoNativeProcess `
    -FilePath $hostExecutable `
    -ArgumentList @('-NoProfile', '-NonInteractive', '-File', $fixturePath, '-Mode', 'success', '-EchoValue', $echoValue, '-ChildPidPath', $childPidPath) `
    -TimeoutSeconds 10
  Assert-Contract (-not $success.timedOut) 'success command timed out'
  Assert-Contract ($success.classification -eq 'success') 'success classification changed'
  Assert-Contract ($success.exitCode -eq 0) 'success exit code changed'
  Assert-Contract ($success.stdout -match [regex]::Escape("stdout-success-$echoValue")) `
    'stdout or a spaced argument was not preserved'
  Assert-Contract ($success.stderr -match 'stderr-success') 'success stderr was not captured'

  $failure = Invoke-LegadoNativeProcess `
    -FilePath $hostExecutable `
    -ArgumentList @('-NoProfile', '-NonInteractive', '-File', $fixturePath, '-Mode', 'failure', '-EchoValue', $echoValue, '-ChildPidPath', $childPidPath) `
    -TimeoutSeconds 10
  Assert-Contract (-not $failure.timedOut) 'failure command timed out'
  Assert-Contract ($failure.classification -eq 'nonzero_exit') 'nonzero exit classification changed'
  Assert-Contract ($failure.exitCode -eq 23) 'nonzero exit code was not captured'
  Assert-Contract ($failure.stderr -match 'stderr-failure') 'failure stderr was not captured'

  $batch = Invoke-LegadoBatchProcess `
    -FilePath $batchFixturePath `
    -ArgumentList @($echoValue) `
    -StandardInput "contract-stdin`r`n" `
    -TimeoutSeconds 10
  Assert-Contract (-not $batch.timedOut) 'batch command timed out'
  Assert-Contract ($batch.exitCode -eq 19) 'batch exit code was not captured'
  Assert-Contract ($batch.stdout -match [regex]::Escape("batch-arg=$echoValue")) `
    'batch argument with spaces was not preserved'
  Assert-Contract ($batch.stdout -match 'batch-input=contract-stdin') `
    'batch standard input was not preserved'
  Assert-Contract ($batch.stderr -match 'batch-stderr') 'batch stderr was not captured'

  $timeout = Invoke-LegadoNativeProcess `
    -FilePath $hostExecutable `
    -ArgumentList @('-NoProfile', '-NonInteractive', '-File', $fixturePath, '-Mode', 'timeout', '-EchoValue', $echoValue, '-ChildPidPath', $childPidPath) `
    -TimeoutSeconds 1
  Assert-Contract $timeout.timedOut 'timeout command was not classified as timed out'
  Assert-Contract ($timeout.classification -eq 'timeout') 'timeout classification changed'
  Assert-Contract $timeout.processTreeIsolated 'timeout process could not be assigned to a Windows Job Object'
  Assert-Contract ($timeout.durationMs -lt 10000) 'timeout boundary did not return promptly'
  Assert-Contract ($timeout.stdout -match 'stdout-timeout') 'stdout emitted before timeout was lost'
  Assert-Contract (Test-Path -LiteralPath $childPidPath) 'timeout fixture did not create its child process'
  $childPid = [int]([System.IO.File]::ReadAllText($childPidPath, [System.Text.Encoding]::ASCII))
  Start-Sleep -Milliseconds 250
  $childProcess = Get-Process -Id $childPid -ErrorAction SilentlyContinue
  Assert-Contract ($null -eq $childProcess) 'timeout did not terminate the descendant process'

  $windowsPowerShell51Version = ''
  if ($PSVersionTable.PSVersion.Major -eq 5) {
    $windowsPowerShell51Version = $PSVersionTable.PSVersion.ToString()
  } elseif (-not $SkipWindowsPowerShellChild) {
    $windowsPowerShellPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    Assert-Contract (Test-Path -LiteralPath $windowsPowerShellPath) `
      'Windows PowerShell 5.1 executable is missing'
    $childContract = Invoke-LegadoNativeProcess `
      -FilePath $windowsPowerShellPath `
      -ArgumentList @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, '-RepoRoot', $RepoRoot, '-SkipWindowsPowerShellChild') `
      -TimeoutSeconds 120
    Assert-Contract (-not $childContract.timedOut) 'Windows PowerShell 5.1 child contract timed out'
    Assert-Contract ($childContract.exitCode -eq 0) `
      "Windows PowerShell 5.1 child contract failed: $($childContract.output.Trim())"
    $jsonLines = @(
      $childContract.stdout -split '[\r\n]+' | Where-Object {
        $_.Trim().StartsWith('{') -and $_.Trim().EndsWith('}')
      }
    )
    Assert-Contract ($jsonLines.Count -gt 0) 'Windows PowerShell 5.1 child produced no evidence'
    $childEvidence = ConvertFrom-Json -InputObject $jsonLines[$jsonLines.Count - 1]
    $windowsPowerShell51Version = [string]$childEvidence.powershellVersion
    Assert-Contract ($windowsPowerShell51Version.StartsWith('5.1.')) `
      'timeout contract did not execute under Windows PowerShell 5.1'
  }

  [pscustomobject][ordered]@{
    status = 'passed'
    powershellVersion = $PSVersionTable.PSVersion.ToString()
    windowsPowerShell51Version = $windowsPowerShell51Version
    successExitCode = [int]$success.exitCode
    failureExitCode = [int]$failure.exitCode
    batchExitCode = [int]$batch.exitCode
    timeoutClassified = [bool]$timeout.timedOut
    timeoutDurationMs = [int]$timeout.durationMs
    descendantTerminated = $true
    directStage7HdcInvocations = ([regex]::Matches($flowSource, '& \$HdcPath')).Count
    directStage7AAdbInvocations = ([regex]::Matches($referenceSource, '& \$AdbPath')).Count
    directControllerDeviceToolInvocations = ([regex]::Matches($controllerSource, '& \$Toolchain\.(adb|hdc|hvigor)')).Count
  } | ConvertTo-Json -Compress
} finally {
  if (Test-Path -LiteralPath $fixtureRoot) {
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
}
