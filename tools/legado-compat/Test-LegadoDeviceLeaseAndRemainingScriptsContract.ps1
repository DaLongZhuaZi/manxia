[CmdletBinding()]
param(
  [Alias('RepositoryRoot')]
  [string]$RepoRoot = '',
  [switch]$SkipWindowsPowerShellChild,
  [switch]$SkipDynamicLease
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($RepoRoot.Length -eq 0) {
  $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

function Assert-Contract {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) {
    throw "Device lease contract failed: $Message"
  }
}

function Read-Utf8Text {
  param([string]$Path)
  return [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false))
}

function Get-ScriptAst {
  param([string]$Path)
  Assert-Contract (Test-Path -LiteralPath $Path) "missing script: $Path"
  $tokens = $null
  $errors = $null
  $source = Read-Utf8Text -Path $Path
  $ast = [System.Management.Automation.Language.Parser]::ParseInput(
    $source,
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

$modulePath = Join-Path $RepoRoot 'tools\legado-compat\LegadoDeviceLease.psm1'
$helperPath = Join-Path $RepoRoot 'tools\legado-compat\Invoke-LegadoNativeProcess.ps1'
$capturePath = Join-Path $RepoRoot 'tools\legado-compat\Capture-LegadoUiAuditScreenshot.ps1'
$readinessPath = Join-Path $RepoRoot 'tools\legado-compat\Invoke-LegadoFullDeviceReadinessAudit.ps1'
$singleReferencePath = Join-Path $RepoRoot 'tools\legado-compat\Invoke-LegadoSingleSourceReference.ps1'

$moduleText = Read-Utf8Text -Path $modulePath
$helperText = Read-Utf8Text -Path $helperPath
$captureText = Read-Utf8Text -Path $capturePath
$readinessText = Read-Utf8Text -Path $readinessPath
$singleReferenceText = Read-Utf8Text -Path $singleReferencePath

Assert-Contains $moduleText 'FileShare]::None' 'device lease exclusivity'
Assert-Contains $moduleText 'MANXIA_LEGADO_DEVICE_LEASE_' 'device lease inheritance'
Assert-Contains $moduleText 'device_lease_conflict' 'device lease conflict classification'
Assert-Contains $moduleText "-Ownership 'inherited'" 'child-process lease inheritance'
Assert-Contains $helperText 'Enter-LegadoNativeDeviceLease' 'native helper lease boundary'
Assert-Contains $helperText 'DeviceLeaseTimeoutSeconds' 'native helper lease timeout'
Assert-Contains $helperText 'deviceLease = $deviceLease' 'native helper lease trace'
Assert-Contains $captureText '. $nativeProcessHelperPath' 'UI audit helper import'
Assert-Contains $readinessText '. $nativeProcessHelperPath' 'readiness helper import'
Assert-Contains $singleReferenceText '. $nativeProcessHelperPath' 'reference helper import'

$captureAst = Get-ScriptAst -Path $capturePath
$readinessAst = Get-ScriptAst -Path $readinessPath
$singleReferenceAst = Get-ScriptAst -Path $singleReferencePath
$captureHdcText = Get-FunctionText -Ast $captureAst -Name 'Invoke-Hdc'
$readinessHdcText = Get-FunctionText -Ast $readinessAst -Name 'Invoke-Hdc'
$singleReferenceAdbText = Get-FunctionText -Ast $singleReferenceAst -Name 'Invoke-Adb'
Assert-Contains $captureHdcText 'Invoke-LegadoNativeProcess' 'UI audit HDC wrapper'
Assert-Contains $captureHdcText '-TimeoutSeconds $TimeoutSeconds' 'UI audit HDC timeout'
Assert-Contains $readinessHdcText 'Invoke-LegadoNativeProcess' 'readiness HDC wrapper'
Assert-Contains $readinessHdcText '-TimeoutSeconds $TimeoutSeconds' 'readiness HDC timeout'
Assert-Contains $singleReferenceAdbText 'Invoke-LegadoNativeProcess' 'reference ADB wrapper'
Assert-Contains $singleReferenceAdbText '-TimeoutSeconds $TimeoutSeconds' 'reference ADB timeout'
Assert-Contains $singleReferenceText '-TimeoutSeconds 1200' 'reference instrumentation timeout'
Assert-Contains $singleReferenceText 'nativeFailureClassification' 'reference structured failure evidence'
Assert-Contains $singleReferenceText 'Get-AdbFailureSummary' 'reference structured failure propagation'
Assert-Contains $readinessText 'Invoke-LegadoNativeProcess' 'sqlite audit timeout boundary'

Assert-Contract (
  $captureText -notmatch '(?m)^\s*&\s*\$HdcPath\b'
) 'UI audit contains an unbounded direct HDC invocation'
Assert-Contract (
  $readinessText -notmatch '(?m)^\s*&\s*\$HdcPath\b'
) 'readiness audit contains an unbounded direct HDC invocation'
Assert-Contract (
  $readinessText -notmatch '(?m)^\s*&\s*\$sqlite\b'
) 'readiness audit contains an unbounded direct sqlite invocation'
Assert-Contract (
  $singleReferenceText -notmatch '(?m)^\s*&\s*\$AdbPath\b'
) 'single-source reference contains an unbounded direct ADB invocation'

if (-not $SkipDynamicLease) {
  $fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    "manxia-device-lease-contract-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  )
  $holderPath = Join-Path $fixtureRoot 'holder.ps1'
  $childPath = Join-Path $fixtureRoot 'inherited-child.ps1'
  $readyPath = Join-Path $fixtureRoot 'holder.ready.json'
  $childResultPath = Join-Path $fixtureRoot 'child.result.json'
  [System.IO.Directory]::CreateDirectory($fixtureRoot) | Out-Null

  $childBody = @'
param(
  [string]$ModulePath,
  [string]$LeaseRoot,
  [string]$ResultPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$env:MANXIA_LEGADO_DEVICE_LEASE_ROOT = $LeaseRoot
Import-Module -Name $ModulePath -Force
$result = Enter-LegadoNativeDeviceLease `
  -FilePath 'C:\fixture\hdc.exe' `
  -ArgumentList @('-t', 'contract-device', 'shell', 'snapshot_display') `
  -TimeoutSeconds 2 `
  -Purpose 'harmony_v2_child'
[System.IO.File]::WriteAllText(
  $ResultPath,
  [string]($result | ConvertTo-Json -Depth 5 -Compress),
  [System.Text.UTF8Encoding]::new($false)
)
if (-not [bool]$result.acquired -or [string]$result.ownership -ne 'inherited') {
  exit 31
}
exit 0
'@
  $holderBody = @'
param(
  [string]$ModulePath,
  [string]$LeaseRoot,
  [string]$ReadyPath,
  [string]$ChildPath,
  [string]$ChildResultPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$env:MANXIA_LEGADO_DEVICE_LEASE_ROOT = $LeaseRoot
Import-Module -Name $ModulePath -Force
$result = Enter-LegadoNativeDeviceLease `
  -FilePath 'C:\fixture\hdc.exe' `
  -ArgumentList @('-t', 'contract-device', 'shell', 'aa', 'force-stop') `
  -TimeoutSeconds 2 `
  -Purpose 'harmony_v2_real_device_flow'
[System.IO.File]::WriteAllText(
  $ReadyPath,
  [string]($result | ConvertTo-Json -Depth 5 -Compress),
  [System.Text.UTF8Encoding]::new($false)
)
if (-not [bool]$result.acquired) {
  exit 32
}
$hostPath = if ($PSVersionTable.PSEdition -eq 'Core') {
  Join-Path $PSHOME 'pwsh.exe'
} else {
  Join-Path $PSHOME 'powershell.exe'
}
$child = Start-Process `
  -FilePath $hostPath `
  -ArgumentList @(
    '-NoProfile', '-NonInteractive',
    '-ExecutionPolicy', 'Bypass',
    '-File', $ChildPath,
    '-ModulePath', $ModulePath,
    '-LeaseRoot', $LeaseRoot,
    '-ResultPath', $ChildResultPath
  ) `
  -WindowStyle Hidden `
  -PassThru
[void]$child.WaitForExit(10000)
if (-not $child.HasExited -or $child.ExitCode -ne 0) {
  exit 33
}
Start-Sleep -Seconds 60
exit 0
'@
  [System.IO.File]::WriteAllText($childPath, $childBody, [System.Text.UTF8Encoding]::new($false))
  [System.IO.File]::WriteAllText($holderPath, $holderBody, [System.Text.UTF8Encoding]::new($false))

  $env:MANXIA_LEGADO_DEVICE_LEASE_ROOT = $fixtureRoot
  $moduleImport = Import-Module -Name $modulePath -Force -PassThru
  try {
    $hostPath = if ($PSVersionTable.PSEdition -eq 'Core') {
      Join-Path $PSHOME 'pwsh.exe'
    } else {
      Join-Path $PSHOME 'powershell.exe'
    }
    $holder = Start-Process `
      -FilePath $hostPath `
      -ArgumentList @(
        '-NoProfile', '-NonInteractive',
        '-ExecutionPolicy', 'Bypass',
        '-File', $holderPath,
        '-ModulePath', $modulePath,
        '-LeaseRoot', $fixtureRoot,
        '-ReadyPath', $readyPath,
        '-ChildPath', $childPath,
        '-ChildResultPath', $childResultPath
      ) `
      -WindowStyle Hidden `
      -PassThru
    $readyDeadline = [DateTimeOffset]::UtcNow.AddSeconds(10)
    while (-not (Test-Path -LiteralPath $readyPath) -and [DateTimeOffset]::UtcNow -lt $readyDeadline) {
      Start-Sleep -Milliseconds 100
    }
    Assert-Contract (Test-Path -LiteralPath $readyPath) 'lease holder did not publish readiness'
    $holderEvidence = Read-Utf8Text -Path $readyPath | ConvertFrom-Json
    Assert-Contract ([bool]$holderEvidence.acquired) 'lease holder did not acquire the device'
    Assert-Contract ([string]$holderEvidence.ownership -eq 'process') 'lease holder ownership changed'
    Assert-Contract ([string]$holderEvidence.purpose -eq 'harmony_v2_real_device_flow') 'holder purpose was not recorded'

    $inheritedDeadline = [DateTimeOffset]::UtcNow.AddSeconds(10)
    while (-not (Test-Path -LiteralPath $childResultPath) -and [DateTimeOffset]::UtcNow -lt $inheritedDeadline) {
      Start-Sleep -Milliseconds 100
    }
    Assert-Contract (Test-Path -LiteralPath $childResultPath) 'inherited child did not publish a result'
    $inheritedEvidence = Read-Utf8Text -Path $childResultPath | ConvertFrom-Json
    Assert-Contract ([bool]$inheritedEvidence.acquired) 'inherited child could not use the parent lease'
    Assert-Contract ([string]$inheritedEvidence.ownership -eq 'inherited') 'child lease was not marked inherited'

    $contender = Enter-LegadoNativeDeviceLease `
      -FilePath 'C:\fixture\hdc.exe' `
      -ArgumentList @('-t', 'contract-device', 'shell', 'aa', 'test') `
      -TimeoutSeconds 1 `
      -Purpose 'harmony_aa_test'
    Assert-Contract (-not [bool]$contender.acquired) 'aa test contender acquired a busy device'
    Assert-Contract ([string]$contender.classification -eq 'device_lease_conflict') 'busy device classification changed'
    Assert-Contract ([string]$contender.ownerPurpose -eq 'harmony_v2_real_device_flow') 'busy owner purpose was not exposed'

    $fakeHdcPath = Join-Path $fixtureRoot 'hdc.exe'
    [System.IO.File]::WriteAllBytes($fakeHdcPath, [byte[]]@(0))
    . $helperPath
    $nativeConflict = Invoke-LegadoNativeProcess `
      -FilePath $fakeHdcPath `
      -ArgumentList @('-t', 'contract-device', 'shell', 'aa', 'test') `
      -TimeoutSeconds 10 `
      -DeviceLeaseTimeoutSeconds 1
    Assert-Contract (
      [string]$nativeConflict.classification -eq 'device_lease_conflict'
    ) 'native helper did not return a structured lease conflict'
    Assert-Contract (
      [string]$nativeConflict.termination -eq 'not_started_device_lease_failure'
    ) 'native helper started an executable after a lease conflict'
    Assert-Contract (
      [string]$nativeConflict.output -match '^DEVICE_LEASE_FAILURE '
    ) 'native helper lease failure is not machine-readable'
  } finally {
    if ($null -ne $holder) {
      try {
        if (-not $holder.HasExited) {
          Stop-Process -Id $holder.Id -Force -ErrorAction SilentlyContinue
        }
        [void]$holder.WaitForExit(5000)
      } catch {
      }
    }
    Exit-LegadoNativeDeviceLeases
    Remove-Module -Name $moduleImport.Name -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $fixtureRoot) {
      Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    [Environment]::SetEnvironmentVariable(
      'MANXIA_LEGADO_DEVICE_LEASE_ROOT',
      $null,
      [EnvironmentVariableTarget]::Process
    )
  }
}

$windowsPowerShell51Version = ''
if ($PSVersionTable.PSVersion.Major -eq 5) {
  $windowsPowerShell51Version = $PSVersionTable.PSVersion.ToString()
} elseif (-not $SkipWindowsPowerShellChild) {
  $windowsPowerShellPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  Assert-Contract (Test-Path -LiteralPath $windowsPowerShellPath) `
    'Windows PowerShell 5.1 executable is missing'
  . $helperPath
  $childContract = Invoke-LegadoNativeProcess `
    -FilePath $windowsPowerShellPath `
    -ArgumentList @(
      '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
      '-File', $PSCommandPath,
      '-RepoRoot', $RepoRoot,
      '-SkipWindowsPowerShellChild'
    ) `
    -TimeoutSeconds 120
  Assert-Contract (-not $childContract.timedOut) 'Windows PowerShell 5.1 child contract timed out'
  Assert-Contract ($childContract.exitCode -eq 0) `
    "Windows PowerShell 5.1 child contract failed: $($childContract.output.Trim())"
  $jsonLines = @(
    $childContract.stdout -split '[\r\n]+' | Where-Object {
      $_ -match '^DEVICE_LEASE_CONTRACT_COMPLETE '
    }
  )
  Assert-Contract ($jsonLines.Count -eq 1) 'Windows PowerShell 5.1 child did not publish completion'
  $windowsPowerShell51Version = (($jsonLines[0] -split ' ', 2)[1] | ConvertFrom-Json).powershellVersion
}

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  powershellVersion = $PSVersionTable.PSVersion.ToString()
  windowsPowerShell51Version = $windowsPowerShell51Version
  dynamicLease = if ($SkipDynamicLease) { 'skipped' } else { 'passed' }
  directNativeInvocations = 'none'
}
Write-Output ("DEVICE_LEASE_CONTRACT_COMPLETE " + ($result | ConvertTo-Json -Compress))
