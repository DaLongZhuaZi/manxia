[CmdletBinding()]
param(
  [Alias('RepositoryRoot')]
  [string]$RepoRoot = '',
  [switch]$SkipWindowsPowerShellChild,
  [switch]$SkipPowerShell7Child
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Contract {
  param(
    [bool]$Condition,
    [string]$Message
  )

  if (-not $Condition) {
    throw "Targeted cancellation runner contract failed: $Message"
  }
}

function Read-AsciiScript {
  param([string]$Path)

  Assert-Contract (Test-Path -LiteralPath $Path -PathType Leaf) "missing script: $Path"
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  Assert-Contract ($bytes.Length -gt 0) "empty script: $Path"
  foreach ($byte in $bytes) {
    Assert-Contract ($byte -lt 128) "script must remain ASCII for Windows PowerShell 5.1: $Path"
  }
  return [System.Text.Encoding]::ASCII.GetString($bytes)
}

function Get-ScriptAst {
  param([string]$Path)

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

function Assert-Contains {
  param(
    [string]$Text,
    [string]$Expected,
    [string]$Label
  )

  Assert-Contract (
    $Text.IndexOf($Expected, [System.StringComparison]::Ordinal) -ge 0
  ) "$Label is missing marker: $Expected"
}

function Assert-NotContains {
  param(
    [string]$Text,
    [string]$Forbidden,
    [string]$Label
  )

  Assert-Contract (
    $Text.IndexOf($Forbidden, [System.StringComparison]::Ordinal) -lt 0
  ) "$Label contains forbidden marker: $Forbidden"
}

function Invoke-ChildContract {
  param(
    [string]$PowerShellPath,
    [string[]]$Arguments,
    [string]$Label
  )

  $previousErrorActionPreference = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    $childOutput = & $PowerShellPath @Arguments 2>&1
    $childExitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previousErrorActionPreference
  }
  Assert-Contract ($childExitCode -eq 0) "$Label failed: $($childOutput -join "`n")"
  $jsonLines = @(
    $childOutput | Where-Object {
      ([string]$_).Trim().StartsWith('{') -and ([string]$_).Trim().EndsWith('}')
    }
  )
  Assert-Contract ($jsonLines.Count -gt 0) "$Label emitted no JSON result"
  $result = ConvertFrom-Json -InputObject ([string]$jsonLines[$jsonLines.Count - 1])
  Assert-Contract ([string]$result.status -eq 'passed') "$Label did not report passed"
  return [string]$result.powershellVersion
}

if ($RepoRoot.Length -eq 0) {
  $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
} else {
  $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
}

$runnerPath = Join-Path $RepoRoot 'tools\legado-compat\Invoke-LegadoTargetedCancellationConformance.ps1'
$nativeHelperPath = Join-Path $RepoRoot 'tools\legado-compat\Invoke-LegadoNativeProcess.ps1'
$testPath = Join-Path $RepoRoot 'entry\src\ohosTest\ets\test\LegadoCancellationConformance.test.ets'
$runnerText = Read-AsciiScript -Path $runnerPath
$testText = [System.IO.File]::ReadAllText($testPath, [System.Text.Encoding]::UTF8)
[void](Get-ScriptAst -Path $runnerPath)
[void](Get-ScriptAst -Path $PSCommandPath)

Assert-Contains $runnerText 'Enter-LegadoNativeDeviceLease' 'device lease acquisition'
Assert-Contains $runnerText 'Exit-LegadoNativeDeviceLeases' 'device lease release'
Assert-Contains $runnerText 'finally {' 'failure-safe cleanup'
Assert-Contains $runnerText "-Purpose 'harmony_targeted_cancellation_conformance'" 'device lease purpose'
Assert-Contains $runnerText 'Invoke-LegadoBatchProcess' 'bounded main and test builds'
Assert-Contains $runnerText "'entry-default-signed.hap'" 'main signed HAP'
Assert-Contains $runnerText "'entry-ohosTest-signed.hap'" 'ohosTest signed HAP'
Assert-Contains $runnerText "'-s', 'class', `$caseFilter" 'Hypium class filter'
Assert-Contains $runnerText '$script:ExpectedSuite + ''#'' + $_' 'suite-qualified Hypium cases'
Assert-Contains $runnerText 'Assert-TargetedHypiumResult' 'exact result validator'
Assert-Contains $runnerText '$unexpectedTests.Count -eq 0' 'unexpected test rejection'
Assert-Contains $runnerText '$unexpectedClasses.Count -eq 0' 'unexpected suite rejection'
Assert-Contains $runnerText '$numTestValues.Count -eq 1 -and $numTestValues[0] -eq 4' 'exact numtests validation'
Assert-Contains $runnerText 'Protect-LegadoEvidenceText' 'evidence redaction'
Assert-Contains $runnerText "'metadata.json'" 'machine-readable evidence'
Assert-Contains $runnerText 'Restore-MainApplication' 'finally application restoration'
Assert-Contains $runnerText 'throw $primaryFailure' 'nonzero failure path'
Assert-NotContains $runnerText '& $resolvedHdcPath' 'direct HDC execution'
Assert-NotContains $runnerText '& $HdcPath' 'direct HDC execution'

$expectedCases = @(
  'clearsValidationDeadlineAfterSuccess',
  'clearsValidationDeadlineAfterFailure',
  'cancelsActiveValidationTaskWhenDeadlineExpires',
  'doesNotStartValidationTaskAfterPreCancellation'
)
$expectedCasesStart = $runnerText.IndexOf('$script:ExpectedCases = @(', [System.StringComparison]::Ordinal)
Assert-Contract ($expectedCasesStart -ge 0) 'runner has no ExpectedCases declaration'
$expectedCasesEnd = $runnerText.IndexOf(')', $expectedCasesStart)
Assert-Contract ($expectedCasesEnd -gt $expectedCasesStart) 'runner ExpectedCases declaration is not closed'
$expectedCasesDeclaration = $runnerText.Substring(
  $expectedCasesStart,
  $expectedCasesEnd - $expectedCasesStart + 1
)
foreach ($caseName in $expectedCases) {
  Assert-Contract (([regex]::Matches($expectedCasesDeclaration, [regex]::Escape($caseName))).Count -eq 1) `
    "runner ExpectedCases must list $caseName exactly once"
  Assert-Contains $testText $caseName 'targeted ohosTest source'
}
Assert-NotContains $runnerText 'notifiesActiveListenersExactlyOnceAndHonorsUnregister' 'case filter scope'
Assert-NotContains $runnerText 'blocksTransportBeforeARequestCanBeDispatched' 'case filter scope'

$gitCommand = Get-Command git -ErrorAction SilentlyContinue
Assert-Contract ($null -ne $gitCommand) 'git is required for git diff --check'
$previousErrorActionPreference = $ErrorActionPreference
try {
  $ErrorActionPreference = 'Continue'
  $gitDiffOutput = & $gitCommand.Source -C $RepoRoot diff --check 2>&1
  $gitDiffExitCode = $LASTEXITCODE
} finally {
  $ErrorActionPreference = $previousErrorActionPreference
}
Assert-Contract ($gitDiffExitCode -eq 0) "git diff --check failed: $($gitDiffOutput -join "`n")"

$windowsPowerShellVersion = ''
$powerShell7Version = ''
$windowsPowerShellPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if ($PSVersionTable.PSVersion.Major -eq 5) {
  $windowsPowerShellVersion = $PSVersionTable.PSVersion.ToString()
} elseif (-not $SkipWindowsPowerShellChild) {
  Assert-Contract (Test-Path -LiteralPath $windowsPowerShellPath) 'Windows PowerShell 5.1 is missing'
  $windowsPowerShellVersion = Invoke-ChildContract `
    -PowerShellPath $windowsPowerShellPath `
    -Arguments @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, '-RepoRoot', $RepoRoot, '-SkipWindowsPowerShellChild', '-SkipPowerShell7Child') `
    -Label 'Windows PowerShell 5.1 child contract'
}

$pwshCommand = Get-Command pwsh -ErrorAction SilentlyContinue
if ($PSVersionTable.PSVersion.Major -ge 7) {
  $powerShell7Version = $PSVersionTable.PSVersion.ToString()
} elseif (-not $SkipPowerShell7Child) {
  Assert-Contract ($null -ne $pwshCommand) 'PowerShell 7 is missing'
  $powerShell7Version = Invoke-ChildContract `
    -PowerShellPath $pwshCommand.Source `
    -Arguments @('-NoProfile', '-NonInteractive', '-File', $PSCommandPath, '-RepoRoot', $RepoRoot, '-SkipWindowsPowerShellChild', '-SkipPowerShell7Child') `
    -Label 'PowerShell 7 child contract'
}

[pscustomobject][ordered]@{
  status = 'passed'
  powershellVersion = $PSVersionTable.PSVersion.ToString()
  windowsPowerShell51Version = $windowsPowerShellVersion
  powerShell7Version = $powerShell7Version
  exactCases = $expectedCases.Count
  exactSuite = 'LegadoCancellationConformance'
  signedArtifacts = 2
  isolatedClassFilter = $true
  redactedEvidence = $true
  finallyRestoration = $true
} | ConvertTo-Json -Compress
