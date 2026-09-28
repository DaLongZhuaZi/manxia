[CmdletBinding()]
param(
  [Alias('RepositoryRoot')]
  [string]$RepoRoot = '',
  [string]$HdcPath = '',
  [string]$HvigorPath = '',
  [string]$EvidenceRoot = '',
  [ValidateRange(60, 3600)]
  [int]$BuildTimeoutSeconds = 1800,
  [ValidateRange(60, 900)]
  [int]$TestTimeoutSeconds = 300,
  [ValidateRange(1, 60)]
  [int]$LeaseTimeoutSeconds = 15
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ExpectedSuite = 'LegadoCancellationConformance'
$script:ExpectedCases = @(
  'clearsValidationDeadlineAfterSuccess',
  'clearsValidationDeadlineAfterFailure',
  'cancelsActiveValidationTaskWhenDeadlineExpires',
  'doesNotStartValidationTaskAfterPreCancellation'
)
$script:BundleName = 'com.dlzz.manxia'
$script:TestModuleName = 'entry_test'
$script:MainModuleName = 'entry'
$script:EntryAbilityName = 'EntryAbility'

function Assert-RunnerCondition {
  param(
    [bool]$Condition,
    [string]$Message
  )

  if (-not $Condition) {
    throw "Targeted cancellation conformance failed: $Message"
  }
}

function Resolve-RunnerPath {
  param(
    [string]$RequestedPath,
    [string[]]$Candidates,
    [string]$Label
  )

  if ($RequestedPath.Length -gt 0) {
    Assert-RunnerCondition (Test-Path -LiteralPath $RequestedPath -PathType Leaf) `
      "$Label does not exist: $RequestedPath"
    return (Resolve-Path -LiteralPath $RequestedPath).Path
  }
  foreach ($candidate in $Candidates) {
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
      return (Resolve-Path -LiteralPath $candidate).Path
    }
  }
  throw "Targeted cancellation conformance failed: unable to locate $Label"
}

function Write-Utf8Atomic {
  param(
    [string]$Path,
    [string]$Content
  )

  $directory = Split-Path -Path $Path -Parent
  if (-not (Test-Path -LiteralPath $directory)) {
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  }
  $temporaryPath = "$Path.tmp.$PID.$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  $encoding = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($temporaryPath, $Content, $encoding)
  Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
}

function Get-Sha256ForText {
  param([string]$Value)

  $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $hashBytes = $sha.ComputeHash($bytes)
    return ([System.BitConverter]::ToString($hashBytes)).Replace('-', '').ToLowerInvariant()
  } finally {
    $sha.Dispose()
  }
}

function Get-SignedHapMetadata {
  param(
    [string]$Path,
    [string]$ExpectedLeafName
  )

  Assert-RunnerCondition (Test-Path -LiteralPath $Path -PathType Leaf) `
    "signed HAP does not exist: $ExpectedLeafName"
  $item = Get-Item -LiteralPath $Path -ErrorAction Stop
  Assert-RunnerCondition ($item.Name -eq $ExpectedLeafName) `
    "unexpected HAP selected: $($item.Name)"
  Assert-RunnerCondition ($item.Name.EndsWith('-signed.hap', [System.StringComparison]::Ordinal)) `
    "HAP is not signed: $($item.Name)"
  $hash = Get-FileHash -Algorithm SHA256 -LiteralPath $item.FullName
  return [ordered]@{
    fileName = $item.Name
    relativePath = "entry\\build\\default\\outputs\\$($item.Directory.Name)\\$($item.Name)"
    bytes = [Int64]$item.Length
    sha256 = [string]$hash.Hash
    lastWriteUtc = $item.LastWriteTimeUtc.ToString('o')
  }
}

function Protect-LegadoEvidenceText {
  param(
    [AllowNull()][string]$Text,
    [string]$Device = ''
  )

  if ($null -eq $Text) {
    return ''
  }
  $result = [string]$Text
  if ($Device.Length -gt 0) {
    $deviceAlias = 'device-' + (Get-Sha256ForText -Value $Device).Substring(0, 12)
    $result = $result.Replace($Device, $deviceAlias)
  }
  $result = [regex]::Replace(
    $result,
    '(?im)(authorization\s*[:=]\s*)([^\r\n]+)',
    '$1[REDACTED]'
  )
  $result = [regex]::Replace(
    $result,
    '(?im)((?:set-cookie|cookie)\s*[:=]\s*)([^\r\n]+)',
    '$1[REDACTED]'
  )
  $result = [regex]::Replace(
    $result,
    '(?i)(bearer\s+)[A-Za-z0-9._~+/-]+=*',
    '$1[REDACTED]'
  )
  $result = [regex]::Replace(
    $result,
    '(?i)([?&](?:access_token|authorization|cookie|key|password|passwd|secret|token)=)[^&\s]+',
    '$1[REDACTED]'
  )
  return $result
}

function Write-NativeCommandEvidence {
  param(
    [string]$Path,
    [string]$Label,
    [object]$Result,
    [string]$Device = ''
  )

  $content = @(
    "label=$Label",
    "exitCode=$([int]$Result.exitCode)",
    "classification=$([string]$Result.classification)",
    "timedOut=$([bool]$Result.timedOut)",
    "termination=$([string]$Result.termination)",
    "durationMs=$([int]$Result.durationMs)",
    '',
    (Protect-LegadoEvidenceText -Text ([string]$Result.output) -Device $Device)
  ) -join "`r`n"
  Write-Utf8Atomic -Path $Path -Content $content
}

function Invoke-CheckedBatchBuild {
  param(
    [string]$BuildTool,
    [string[]]$Arguments,
    [string]$Label,
    [string]$EvidencePath,
    [string]$WorkingDirectory,
    [int]$TimeoutSeconds
  )

  $result = Invoke-LegadoBatchProcess `
    -FilePath $BuildTool `
    -ArgumentList $Arguments `
    -TimeoutSeconds $TimeoutSeconds `
    -WorkingDirectory $WorkingDirectory
  Write-NativeCommandEvidence -Path $EvidencePath -Label $Label -Result $result
  Assert-RunnerCondition (-not [bool]$result.timedOut) "$Label timed out"
  Assert-RunnerCondition ([int]$result.exitCode -eq 0) "$Label returned exit code $($result.exitCode)"
  return $result
}

function Invoke-CheckedHdc {
  param(
    [string]$ResolvedHdcPath,
    [string[]]$Arguments,
    [string]$Label,
    [string]$EvidencePath,
    [string]$Device = '',
    [int]$TimeoutSeconds = 30,
    [switch]$WriteEvidence
  )

  $result = Invoke-LegadoNativeProcess `
    -FilePath $ResolvedHdcPath `
    -ArgumentList $Arguments `
    -TimeoutSeconds $TimeoutSeconds
  if ($WriteEvidence) {
    Write-NativeCommandEvidence -Path $EvidencePath -Label $Label -Result $result -Device $Device
  }
  Assert-RunnerCondition (-not [bool]$result.timedOut) "$Label timed out"
  Assert-RunnerCondition ([int]$result.exitCode -eq 0) "$Label returned exit code $($result.exitCode)"
  return $result
}

function Get-ConnectedHarmonyDevice {
  param([string]$ResolvedHdcPath)

  $result = Invoke-CheckedHdc `
    -ResolvedHdcPath $ResolvedHdcPath `
    -Arguments @('list', 'targets') `
    -Label 'hdc list targets' `
    -EvidencePath ''
  $devices = New-Object 'System.Collections.Generic.List[string]'
  foreach ($line in ($result.stdout -split "`r?`n")) {
    $trimmed = $line.Trim()
    if ($trimmed.Length -eq 0) {
      continue
    }
    if ($trimmed -match '^(?i)(list|targets|connected|device|offline|unauthorized)') {
      continue
    }
    $firstToken = ($trimmed -split '\s+')[0]
    if ($firstToken -match '^[A-Za-z0-9._:-]+$') {
      [void]$devices.Add($firstToken)
    }
  }
  $distinct = @($devices | Select-Object -Unique)
  Assert-RunnerCondition ($distinct.Count -eq 1) `
    "expected exactly one connected HarmonyOS device, found $($distinct.Count)"
  return [string]$distinct[0]
}

function Assert-TargetedHypiumResult {
  param([string]$Output)

  Assert-RunnerCondition (
    [regex]::IsMatch($Output, '(?m)^TestFinished-ResultCode:\s*0\s*$')
  ) 'aa test did not report TestFinished-ResultCode: 0'
  Assert-RunnerCondition (
    [regex]::IsMatch($Output, '(?m)^OHOS_REPORT_CODE:\s*0\s*$')
  ) 'aa test did not report OHOS_REPORT_CODE: 0'
  Assert-RunnerCondition (
    [regex]::IsMatch(
      $Output,
      '(?m)^OHOS_REPORT_RESULT:\s*stream=Tests run:\s*4,\s*Failure:\s*0,\s*Error:\s*0,\s*Pass:\s*4,\s*Ignore:\s*0\s*$'
    )
  ) 'aa test result is not exactly 4 passing tests'

  $reportedTests = @(
    [regex]::Matches($Output, '(?m)^OHOS_REPORT_STATUS:\s*test=(.+?)\s*$') |
      ForEach-Object { $_.Groups[1].Value.Trim() } |
      Select-Object -Unique
  )
  $reportedClasses = @(
    [regex]::Matches($Output, '(?m)^OHOS_REPORT_STATUS:\s*class=(.+?)\s*$') |
      ForEach-Object { $_.Groups[1].Value.Trim() } |
      Select-Object -Unique
  )
  $numTestValues = @(
    [regex]::Matches($Output, '(?m)^OHOS_REPORT_STATUS:\s*numtests=(\d+)\s*$') |
      ForEach-Object { [int]$_.Groups[1].Value } |
      Select-Object -Unique
  )
  $unexpectedTests = @($reportedTests | Where-Object { $script:ExpectedCases -notcontains $_ })
  $unexpectedClasses = @($reportedClasses | Where-Object { $_ -ne $script:ExpectedSuite })

  Assert-RunnerCondition ($reportedTests.Count -eq $script:ExpectedCases.Count) `
    "aa test reported $($reportedTests.Count) distinct cases instead of four"
  Assert-RunnerCondition ($unexpectedTests.Count -eq 0) `
    "aa test ran an unrequested case: $($unexpectedTests -join ',')"
  Assert-RunnerCondition ($reportedClasses.Count -eq 1 -and $reportedClasses[0] -eq $script:ExpectedSuite) `
    'aa test ran an unrequested suite'
  Assert-RunnerCondition ($unexpectedClasses.Count -eq 0) 'aa test ran an unrequested suite'
  Assert-RunnerCondition ($numTestValues.Count -eq 1 -and $numTestValues[0] -eq 4) `
    'aa test did not consistently report numtests=4'

  foreach ($caseName in $script:ExpectedCases) {
    Assert-RunnerCondition ($reportedTests -contains $caseName) "aa test did not report $caseName"
    $endPattern = '(?ms)^OHOS_REPORT_STATUS:\s*test=' +
      [regex]::Escape($caseName) + '\s*\r?$\r?\nOHOS_REPORT_STATUS_CODE:\s*0\s*$'
    Assert-RunnerCondition ([regex]::IsMatch($Output, $endPattern)) `
      "aa test did not report a passing result for $caseName"
  }

  return [ordered]@{
    reportedCases = @($reportedTests)
    reportedSuite = $reportedClasses[0]
    numtests = $numTestValues[0]
  }
}

function Get-TargetedHilogSummary {
  param(
    [string]$ResolvedHdcPath,
    [string]$Device,
    [string]$EvidencePath
  )

  $result = Invoke-CheckedHdc `
    -ResolvedHdcPath $ResolvedHdcPath `
    -Arguments @('-t', $Device, 'shell', 'hilog', '-x') `
    -Label 'targeted cancellation hilog export' `
    -EvidencePath '' `
    -Device $Device `
    -TimeoutSeconds 60
  $summaryLines = @(
    $result.stdout -split "`r?`n" | Where-Object {
      $_ -match '(?i)(hypium|OHOS_REPORT|LegadoCancellationConformance|clearsValidationDeadline|cancelsActiveValidationTaskWhenDeadlineExpires|doesNotStartValidationTaskAfterPreCancellation)'
    }
  )
  $summary = if ($summaryLines.Count -eq 0) {
    'No targeted Hypium hilog records were returned after the test run.'
  } else {
    $summaryLines -join "`r`n"
  }
  Write-Utf8Atomic -Path $EvidencePath -Content (Protect-LegadoEvidenceText -Text $summary -Device $Device)
  return $summaryLines.Count
}

function Restore-MainApplication {
  param(
    [string]$ResolvedHdcPath,
    [string]$Device,
    [string]$EvidenceDirectory
  )

  $forceStopEvidence = Join-Path $EvidenceDirectory 'restore-force-stop.log'
  [void](Invoke-CheckedHdc `
    -ResolvedHdcPath $ResolvedHdcPath `
    -Arguments @('-t', $Device, 'shell', 'aa', 'force-stop', $script:BundleName) `
    -Label 'restore force-stop main application' `
    -EvidencePath $forceStopEvidence `
    -Device $Device `
    -WriteEvidence)
  $startEvidence = Join-Path $EvidenceDirectory 'restore-start.log'
  [void](Invoke-CheckedHdc `
    -ResolvedHdcPath $ResolvedHdcPath `
    -Arguments @('-t', $Device, 'shell', 'aa', 'start', '-a', $script:EntryAbilityName, '-b', $script:BundleName, '-m', $script:MainModuleName) `
    -Label 'restore start main application' `
    -EvidencePath $startEvidence `
    -Device $Device `
    -WriteEvidence)

  $deadline = [DateTimeOffset]::UtcNow.AddSeconds(10)
  while ([DateTimeOffset]::UtcNow -lt $deadline) {
    Start-Sleep -Milliseconds 500
    $pidResult = Invoke-CheckedHdc `
      -ResolvedHdcPath $ResolvedHdcPath `
      -Arguments @('-t', $Device, 'shell', 'pidof', $script:BundleName) `
      -Label 'restore verify main application process' `
      -EvidencePath '' `
      -Device $Device
    if ($pidResult.stdout.Trim().Length -gt 0) {
      Write-Utf8Atomic -Path (Join-Path $EvidenceDirectory 'restore-verification.log') -Content 'mainApplicationRunning=true'
      return $true
    }
  }
  Write-Utf8Atomic -Path (Join-Path $EvidenceDirectory 'restore-verification.log') -Content 'mainApplicationRunning=false'
  throw 'Targeted cancellation conformance failed: main application did not restart after the test run'
}

if ($RepoRoot.Length -eq 0) {
  $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
} else {
  $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
}

$nativeHelperPath = Join-Path $RepoRoot 'tools\legado-compat\Invoke-LegadoNativeProcess.ps1'
$leaseModulePath = Join-Path $RepoRoot 'tools\legado-compat\LegadoDeviceLease.psm1'
$testFilePath = Join-Path $RepoRoot 'entry\src\ohosTest\ets\test\LegadoCancellationConformance.test.ets'
Assert-RunnerCondition (Test-Path -LiteralPath $nativeHelperPath -PathType Leaf) 'native process helper is missing'
Assert-RunnerCondition (Test-Path -LiteralPath $leaseModulePath -PathType Leaf) 'device lease module is missing'
Assert-RunnerCondition (Test-Path -LiteralPath $testFilePath -PathType Leaf) 'targeted ohosTest source is missing'
. $nativeHelperPath
Import-Module -Name $leaseModulePath -Force -ErrorAction Stop

$defaultHdcCandidates = @(
  'F:\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe',
  'F:\HarmonyOS\SDK\23\toolchains\hdc.exe',
  'F:\HarmonyOS\SDK\20\toolchains\hdc.exe',
  'F:\HarmonyOS\SDK\18\toolchains\hdc.exe'
)
$defaultHvigorCandidates = @(
  'F:\DevEco Studio\tools\hvigor\bin\hvigorw.bat'
)
$resolvedHdcPath = Resolve-RunnerPath -RequestedPath $HdcPath -Candidates $defaultHdcCandidates -Label 'HDC'
$resolvedHvigorPath = Resolve-RunnerPath -RequestedPath $HvigorPath -Candidates $defaultHvigorCandidates -Label 'Hvigor'
$env:DEVECO_SDK_HOME = 'F:\DevEco Studio\sdk'

if ($EvidenceRoot.Length -eq 0) {
  $EvidenceRoot = Join-Path $RepoRoot 'tools\legado-compat\evidence\targeted-cancellation-conformance'
}
$runId = [DateTimeOffset]::UtcNow.ToString('yyyyMMddTHHmmssfffZ')
$evidenceDirectory = Join-Path $EvidenceRoot $runId
[System.IO.Directory]::CreateDirectory($evidenceDirectory) | Out-Null
$metadataPath = Join-Path $evidenceDirectory 'metadata.json'
$mainHapPath = Join-Path $RepoRoot 'entry\build\default\outputs\default\entry-default-signed.hap'
$testHapPath = Join-Path $RepoRoot 'entry\build\default\outputs\ohosTest\entry-ohosTest-signed.hap'
$caseFilter = @(
  $script:ExpectedCases | ForEach-Object {
    $script:ExpectedSuite + '#' + $_
  }
) -join ','

$metadata = [ordered]@{
  schemaVersion = 1
  status = 'running'
  startedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
  completedAtUtc = ''
  runner = 'Invoke-LegadoTargetedCancellationConformance.ps1'
  suite = $script:ExpectedSuite
  cases = @($script:ExpectedCases)
  artifacts = [ordered]@{}
  device = [ordered]@{}
  checks = [ordered]@{}
  restoration = [ordered]@{ attempted = $false; succeeded = $false }
  failure = ''
}
Write-Utf8Atomic -Path $metadataPath -Content ($metadata | ConvertTo-Json -Depth 10)

$device = ''
$manualLeaseAcquired = $false
$primaryFailure = $null
$restorationFailure = ''

try {
  [void](Invoke-CheckedBatchBuild `
    -BuildTool $resolvedHvigorPath `
    -Arguments @('assembleApp', '-p', 'product=default', '-p', 'buildMode=debug', '--no-daemon', '--stacktrace') `
    -Label 'build main signed HAP' `
    -EvidencePath (Join-Path $evidenceDirectory 'build-main.log') `
    -WorkingDirectory $RepoRoot `
    -TimeoutSeconds $BuildTimeoutSeconds)
  [void](Invoke-CheckedBatchBuild `
    -BuildTool $resolvedHvigorPath `
    -Arguments @('assembleHap', '-p', 'module=entry@ohosTest', '-p', 'product=default', '-p', 'buildMode=debug', '--no-daemon', '--stacktrace') `
    -Label 'build ohosTest signed HAP' `
    -EvidencePath (Join-Path $evidenceDirectory 'build-ohosTest.log') `
    -WorkingDirectory $RepoRoot `
    -TimeoutSeconds $BuildTimeoutSeconds)
  $metadata['artifacts']['main'] = Get-SignedHapMetadata -Path $mainHapPath -ExpectedLeafName 'entry-default-signed.hap'
  $metadata['artifacts']['ohosTest'] = Get-SignedHapMetadata -Path $testHapPath -ExpectedLeafName 'entry-ohosTest-signed.hap'
  Write-Utf8Atomic -Path $metadataPath -Content ($metadata | ConvertTo-Json -Depth 10)

  $device = Get-ConnectedHarmonyDevice -ResolvedHdcPath $resolvedHdcPath
  $metadata['device']['sha256'] = Get-Sha256ForText -Value $device
  $metadata['device']['selectedTargetCount'] = 1
  $manualLease = Enter-LegadoNativeDeviceLease `
    -FilePath $resolvedHdcPath `
    -ArgumentList @('-t', $device, 'shell', 'aa', 'test') `
    -TimeoutSeconds $LeaseTimeoutSeconds `
    -Purpose 'harmony_targeted_cancellation_conformance'
  Assert-RunnerCondition ([bool]$manualLease.acquired) `
    "device lease was not acquired: $($manualLease.classification)"
  $manualLeaseAcquired = $true
  $metadata['device']['leaseClassification'] = [string]$manualLease.classification
  $metadata['device']['leaseOwnership'] = [string]$manualLease.ownership
  $metadata['device']['leasePurpose'] = [string]$manualLease.purpose

  $pidBeforeResult = Invoke-CheckedHdc `
    -ResolvedHdcPath $resolvedHdcPath `
    -Arguments @('-t', $device, 'shell', 'pidof', $script:BundleName) `
    -Label 'inspect manual application session' `
    -EvidencePath '' `
    -Device $device
  $metadata['device']['mainApplicationWasRunning'] = ($pidBeforeResult.stdout.Trim().Length -gt 0)
  [void](Invoke-CheckedHdc `
    -ResolvedHdcPath $resolvedHdcPath `
    -Arguments @('-t', $device, 'shell', 'aa', 'force-stop', $script:BundleName) `
    -Label 'stop manual application session' `
    -EvidencePath (Join-Path $evidenceDirectory 'pretest-force-stop.log') `
    -Device $device `
    -WriteEvidence)
  $pidAfterStopResult = Invoke-CheckedHdc `
    -ResolvedHdcPath $resolvedHdcPath `
    -Arguments @('-t', $device, 'shell', 'pidof', $script:BundleName) `
    -Label 'verify manual application session stopped' `
    -EvidencePath '' `
    -Device $device
  Assert-RunnerCondition ($pidAfterStopResult.stdout.Trim().Length -eq 0) `
    'main application process remained alive after force-stop'

  [void](Invoke-CheckedHdc `
    -ResolvedHdcPath $resolvedHdcPath `
    -Arguments @('-t', $device, 'install', '-r', $mainHapPath) `
    -Label 'install rebuilt main signed HAP' `
    -EvidencePath (Join-Path $evidenceDirectory 'install-main.log') `
    -Device $device `
    -TimeoutSeconds 180 `
    -WriteEvidence)
  [void](Invoke-CheckedHdc `
    -ResolvedHdcPath $resolvedHdcPath `
    -Arguments @('-t', $device, 'install', '-r', $testHapPath) `
    -Label 'install rebuilt ohosTest signed HAP' `
    -EvidencePath (Join-Path $evidenceDirectory 'install-ohosTest.log') `
    -Device $device `
    -TimeoutSeconds 180 `
    -WriteEvidence)
  [void](Invoke-CheckedHdc `
    -ResolvedHdcPath $resolvedHdcPath `
    -Arguments @('-t', $device, 'shell', 'hilog', '-r') `
    -Label 'clear hilog before targeted test' `
    -EvidencePath (Join-Path $evidenceDirectory 'pretest-hilog-reset.log') `
    -Device $device `
    -WriteEvidence)

  $testResult = Invoke-CheckedHdc `
    -ResolvedHdcPath $resolvedHdcPath `
    -Arguments @('-t', $device, 'shell', 'aa', 'test', '-b', $script:BundleName, '-m', $script:TestModuleName, '-s', 'class', $caseFilter) `
    -Label 'run four targeted cancellation conformance cases' `
    -EvidencePath (Join-Path $evidenceDirectory 'aa-test-result.log') `
    -Device $device `
    -TimeoutSeconds $TestTimeoutSeconds `
    -WriteEvidence
  $testSummary = Assert-TargetedHypiumResult -Output ([string]$testResult.output)
  $metadata['checks']['testExitCode'] = [int]$testResult.exitCode
  $metadata['checks']['reportedCases'] = @($testSummary.reportedCases)
  $metadata['checks']['reportedSuite'] = [string]$testSummary.reportedSuite
  $metadata['checks']['numtests'] = [int]$testSummary.numtests
  $metadata['checks']['hilogSummaryLineCount'] = Get-TargetedHilogSummary `
    -ResolvedHdcPath $resolvedHdcPath `
    -Device $device `
    -EvidencePath (Join-Path $evidenceDirectory 'hilog-summary.log')
  $metadata['status'] = 'passed'
} catch {
  $primaryFailure = $_
  $metadata['status'] = 'failed'
  $metadata['failure'] = Protect-LegadoEvidenceText -Text $_.Exception.Message -Device $device
} finally {
  if ($manualLeaseAcquired) {
    $metadata['restoration']['attempted'] = $true
    try {
      $metadata['restoration']['succeeded'] = Restore-MainApplication `
        -ResolvedHdcPath $resolvedHdcPath `
        -Device $device `
        -EvidenceDirectory $evidenceDirectory
    } catch {
      $restorationFailure = Protect-LegadoEvidenceText -Text $_.Exception.Message -Device $device
      $metadata['restoration']['succeeded'] = $false
      if ($metadata['failure'].Length -eq 0) {
        $metadata['failure'] = $restorationFailure
      } else {
        $metadata['failure'] = $metadata['failure'] + '; restoration: ' + $restorationFailure
      }
      $metadata['status'] = 'failed'
    }
  }
  try {
    Exit-LegadoNativeDeviceLeases
  } catch {
    $leaseReleaseFailure = Protect-LegadoEvidenceText -Text $_.Exception.Message -Device $device
    if ($metadata['failure'].Length -eq 0) {
      $metadata['failure'] = 'device lease release: ' + $leaseReleaseFailure
    } else {
      $metadata['failure'] = $metadata['failure'] + '; device lease release: ' + $leaseReleaseFailure
    }
    $metadata['status'] = 'failed'
  }
  $metadata['completedAtUtc'] = [DateTimeOffset]::UtcNow.ToString('o')
  Write-Utf8Atomic -Path $metadataPath -Content ($metadata | ConvertTo-Json -Depth 10)
}

if ($null -ne $primaryFailure) {
  throw $primaryFailure
}
if ($restorationFailure.Length -gt 0) {
  throw "Targeted cancellation conformance failed during application restoration: $restorationFailure"
}
Assert-RunnerCondition ($metadata['status'] -eq 'passed') 'runner completed without a passing status'
Write-Output (
  'TARGETED_CANCELLATION_CONFORMANCE_PASSED evidence=' + $evidenceDirectory +
  ' cases=4 suite=' + $script:ExpectedSuite
)
