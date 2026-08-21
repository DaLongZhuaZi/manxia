[CmdletBinding()]
param(
  [string]$HdcPath = 'F:\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe',
  [string]$Device = '',
  [string]$PythonPath = '.venv\Scripts\python.exe',
  [string]$MainHapPath = 'entry\build\default\outputs\default\entry-default-signed.hap',
  [string]$TestHapPath = 'entry\build\default\outputs\ohosTest\entry-ohosTest-signed.hap',
  [string]$EvidencePath = 'tools\legado-compat\evidence\harmony-wire-value-fingerprint-stage0.log',
  [switch]$RunArkWebConformance
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-HarmonyDevice {
  param([string]$ToolPath, [string]$RequestedDevice)
  if ($RequestedDevice.Length -gt 0) {
    return $RequestedDevice
  }
  $targets = @(& $ToolPath list targets | Where-Object {
    $candidate = ([string]$_).Trim()
    $candidate.Length -gt 0 -and -not $candidate.StartsWith('[')
  })
  if ($LASTEXITCODE -ne 0 -or $targets.Count -ne 1) {
    throw "HARMONY_DEVICE_AUTO_DISCOVERY_EXPECTED_ONE_FOUND_$($targets.Count)"
  }
  return ([string]$targets[0]).Trim()
}

function Wait-FixtureReady {
  param([string]$HttpUrl, [string]$TlsUrl)
  for ($attempt = 0; $attempt -lt 16; $attempt++) {
    $httpReady = $false
    $tlsReady = $false
    try { $httpReady = (Invoke-WebRequest -Uri $HttpUrl -UseBasicParsing -TimeoutSec 2).StatusCode -eq 200 } catch { $httpReady = $false }
    try { $tlsReady = (Invoke-WebRequest -Uri $TlsUrl -SkipCertificateCheck -UseBasicParsing -TimeoutSec 2).StatusCode -eq 200 } catch { $tlsReady = $false }
    if ($httpReady -and $tlsReady) {
      return
    }
    Start-Sleep -Milliseconds 500
  }
  throw 'HARMONY_WIRE_FIXTURE_NOT_READY'
}

function Test-ArkWebConformanceTrace {
  param([string]$TraceText)
  $requiredMarkers = @(
    '(?i)MANXIA_LEGADO_TRACE_STATUS:fixture-arkweb-webjs-cookie\|ark_web\|none\|true',
    '(?i)MANXIA_LEGADO_TRACE_STATUS:fixture-arkweb-source-regex\|ark_web\|none\|(true|false)',
    '(?i)MANXIA_LEGADO_TRACE_STATUS:fixture-arkweb-cookie-roundtrip\|ark_web\|none\|(true|false)',
    '(?i)MANXIA_LEGADO_TRACE_STATUS:fixture-runtime-scope-replay-isolation\|passed\|900150983cd24fb0d6963f7d28e17f72',
    '(?i)MANXIA_LEGADO_TRACE_STATUS:fixture-runtime-workflow-binding-contract\|passed\|source-book-chapter-key-page-variable',
    '(?i)MANXIA_LEGADO_TRACE_STATUS:fixture-runtime-java-api-contract\|passed\|get-encodeURI-md5-source-fields',
    '(?i)MANXIA_LEGADO_TRACE_STATUS:fixture-runtime-hmac-contract\|passed\|hmac-md5-sha256-structured-failure',
    '(?i)MANXIA_LEGADO_TRACE_STATUS:fixture-runtime-postfix-js-contract\|passed\|json-postfix-top-level-search',
    '(?i)MANXIA_LEGADO_TRACE_STATUS:fixture-runtime-json-prefix-js-contract\|passed\|json-prefix-result-and-put',
    '(?i)MANXIA_LEGADO_TRACE_STATUS:fixture-runtime-top-level-js-boolean-contract\|passed\|template-boolean-url-option',
    '(?i)MANXIA_LEGADO_TRACE_STATUS:fixture-runtime-toc-js-object-projection\|passed\|elements=2;namePresent=true;urlPresent=true;infoPresent=false',
    '(?i)MANXIA_LEGADO_TRACE_STATUS:fixture-book-info-init-content-transition\|passed\|inner-document-visible'
  )
  foreach ($marker in $requiredMarkers) {
    if ($TraceText -notmatch $marker) { return $false }
  }
  return $true
}

if (-not (Test-Path -LiteralPath $HdcPath)) {
  throw 'HDC_NOT_FOUND'
}
$mainHap = (Resolve-Path -LiteralPath $MainHapPath).Path
$testHap = (Resolve-Path -LiteralPath $TestHapPath).Path
$fixtureScript = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot 'FixtureServer.ps1')).Path
$tlsScript = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot 'FixtureTlsServer.mjs')).Path
$powerShell = (Get-Command pwsh.exe -ErrorAction Stop).Source
$node = (Get-Command node.exe -ErrorAction Stop).Source
$openssl = (Get-Command openssl.exe -ErrorAction Stop).Source
$resolvedDevice = Resolve-HarmonyDevice -ToolPath $HdcPath -RequestedDevice $Device
$evidenceFullPath = if ([System.IO.Path]::IsPathRooted($EvidencePath)) {
  [System.IO.Path]::GetFullPath($EvidencePath)
} else {
  [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $EvidencePath))
}
$evidenceDirectory = Split-Path -Path $evidenceFullPath -Parent
[System.IO.Directory]::CreateDirectory($evidenceDirectory) | Out-Null

$temporaryDirectory = Join-Path ([System.IO.Path]::GetTempPath()) "manxia-harmony-wire-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
[System.IO.Directory]::CreateDirectory($temporaryDirectory) | Out-Null
$certificatePath = Join-Path $temporaryDirectory 'fixture-cert.pem'
$privateKeyPath = Join-Path $temporaryDirectory 'fixture-key.pem'
$fixtureOutput = Join-Path $temporaryDirectory 'fixture.stdout.log'
$fixtureError = Join-Path $temporaryDirectory 'fixture.stderr.log'
$tlsOutput = Join-Path $temporaryDirectory 'tls.stdout.log'
$tlsError = Join-Path $temporaryDirectory 'tls.stderr.log'
$fixtureProcess = $null
$tlsProcess = $null

try {
  $fixtureProcess = Start-Process -FilePath $powerShell -ArgumentList @('-NoProfile', '-File', $fixtureScript, '-Port', '18765') -WindowStyle Hidden -RedirectStandardOutput $fixtureOutput -RedirectStandardError $fixtureError -PassThru
  $previousOpenSslConf = $env:OPENSSL_CONF
  try {
    $env:OPENSSL_CONF = 'NUL'
    & $openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 1 -subj '/CN=localhost' -addext 'subjectAltName=IP:127.0.0.1' -keyout $privateKeyPath -out $certificatePath 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
      throw 'HARMONY_WIRE_TLS_CERTIFICATE_GENERATION_FAILED'
    }
  } finally {
    $env:OPENSSL_CONF = $previousOpenSslConf
  }
  $tlsProcess = Start-Process -FilePath $node -ArgumentList @($tlsScript, '18766', $certificatePath, $privateKeyPath) -WindowStyle Hidden -RedirectStandardOutput $tlsOutput -RedirectStandardError $tlsError -PassThru
  Wait-FixtureReady -HttpUrl 'http://127.0.0.1:18765/health' -TlsUrl 'https://127.0.0.1:18766/tls-observation'

  & $HdcPath -t $resolvedDevice rport 'tcp:18765' 'tcp:18765' | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'HARMONY_WIRE_HTTP_RPORT_FAILED' }
  & $HdcPath -t $resolvedDevice rport 'tcp:18766' 'tcp:18766' | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'HARMONY_WIRE_TLS_RPORT_FAILED' }
  $mainInstall = @(& $HdcPath -t $resolvedDevice install -r $mainHap)
  if ($LASTEXITCODE -ne 0 -or ($mainInstall -join "`n") -notmatch 'msg:install bundle successfully') { throw 'HARMONY_WIRE_MAIN_INSTALL_FAILED' }
  $testInstall = @(& $HdcPath -t $resolvedDevice install -r $testHap)
  if ($LASTEXITCODE -ne 0 -or ($testInstall -join "`n") -notmatch 'msg:install bundle successfully') { throw 'HARMONY_WIRE_TEST_INSTALL_FAILED' }
  [void](& $HdcPath -t $resolvedDevice shell hilog -r)
  $testOutput = @(& $HdcPath -t $resolvedDevice shell aa test -b com.dlzz.manxia -m entry_test)
  $testExitCode = $LASTEXITCODE
  $hasTestFailure = ($testOutput -join "`n") -match 'TestFinished-ResultCode:\s*-[1-9][0-9]*|OHOS_REPORT_CODE:\s*-[1-9][0-9]*|Failure:\s*[1-9][0-9]*|Error:\s*[1-9][0-9]*'
  $hilog = @(& $HdcPath -t $resolvedDevice shell hilog -x)
  if ($LASTEXITCODE -ne 0) { throw 'HARMONY_WIRE_HILOG_FAILED' }
  $wireLines = @($hilog | Where-Object { $_ -match 'MANXIA_LEGADO_WIRE_TRACE:' })
  $arkWebLines = @()
  $arkWebPassed = $false
  if ($RunArkWebConformance -and -not $hasTestFailure -and $testExitCode -eq 0) {
    $resolvedPython = (Resolve-Path -LiteralPath $PythonPath).Path
    $arkWebScript = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot 'Invoke-LegadoArkWebHypiumConformance.py')).Path
    $arkWebOutputDirectory = Join-Path $temporaryDirectory 'arkweb-hypium'
    [void](& $HdcPath -t $resolvedDevice shell hilog -r)
    & $resolvedPython $arkWebScript --device-sn $resolvedDevice --hdc-path $HdcPath --output-dir $arkWebOutputDirectory --settle-seconds 3
    if ($LASTEXITCODE -ne 0) { throw 'HARMONY_ARKWEB_HYPIUM_LAUNCH_FAILED' }
    $driverResultPath = Join-Path $arkWebOutputDirectory 'result.json'
    if (-not (Test-Path -LiteralPath $driverResultPath)) { throw 'HARMONY_ARKWEB_HYPIUM_RESULT_MISSING' }
    $driverResult = Get-Content -LiteralPath $driverResultPath -Raw -Encoding utf8 | ConvertFrom-Json
    if ([string]$driverResult.status -ne 'started' -or -not [bool]$driverResult.driver_closed) {
      throw 'HARMONY_ARKWEB_HYPIUM_RELEASE_OR_START_FAILED'
    }
    $deadline = [DateTimeOffset]::UtcNow.AddSeconds(40)
    $latestArkWebTrace = ''
    while ([DateTimeOffset]::UtcNow -lt $deadline) {
      $arkWebHilog = @(& $HdcPath -t $resolvedDevice shell hilog -x)
      if ($LASTEXITCODE -ne 0) { throw 'HARMONY_ARKWEB_HILOG_FAILED' }
      $latestArkWebTrace = $arkWebHilog -join "`r`n"
      $arkWebLines = @($arkWebHilog | Where-Object {
        $_ -match 'MANXIA_LEGADO_TRACE_STATUS:' -or $_ -match 'MANXIA_LEGADO_ARKWEB_FIXTURE_FAILED:'
      })
      if ($latestArkWebTrace -match 'MANXIA_LEGADO_ARKWEB_FIXTURE_FAILED:') { break }
      if (Test-ArkWebConformanceTrace -TraceText $latestArkWebTrace) {
        $arkWebPassed = $true
        break
      }
      Start-Sleep -Milliseconds 500
    }
  }
  # Preserve only suite-level totals and deterministic test identifiers.  The
  # conformance fixtures never contain production source URLs, cookies,
  # headers or content, so this makes a failure actionable without widening
  # the evidence privacy boundary.
  $testLines = @($testOutput | Where-Object {
    $_ -match 'TestFinished-ResultCode:|OHOS_REPORT_CODE:|Failure:|Error:|OHOS_REPORT_STATUS: stream=Error in '
  })
  [System.IO.File]::WriteAllText($evidenceFullPath, (($testLines + $wireLines + $arkWebLines) -join "`r`n"), [System.Text.UTF8Encoding]::new($false))
  if ($testExitCode -ne 0 -or $hasTestFailure) { throw 'HARMONY_WIRE_AA_TEST_FAILED' }
  if ($RunArkWebConformance -and -not $arkWebPassed) { throw 'HARMONY_ARKWEB_CONFORMANCE_FAILED' }
  if ($wireLines.Count -ne 1) { throw "HARMONY_WIRE_TRACE_EXPECTED_ONE_FOUND_$($wireLines.Count)" }
  $wireTrace = [string]$wireLines[0]
  foreach ($field in @('userAgentSha256', 'keepAliveSha256', 'connectionSha256', 'cacheControlSha256', 'acceptEncodingSha256')) {
    if ($wireTrace -notmatch ($field + '=[0-9a-f]{64}')) { throw "HARMONY_WIRE_DIGEST_MISSING_$field" }
  }
  $arkWebState = if ($RunArkWebConformance) { 'passed' } else { 'not_requested' }
  Write-Output "HARMONY_WIRE_VALUE_FINGERPRINT_PASSED device=$resolvedDevice arkWeb=$arkWebState evidence=$evidenceFullPath"
} finally {
  if ($null -ne $tlsProcess -and -not $tlsProcess.HasExited) { Stop-Process -Id $tlsProcess.Id -Force }
  if ($null -ne $fixtureProcess -and -not $fixtureProcess.HasExited) { Stop-Process -Id $fixtureProcess.Id -Force }
  if (Test-Path -LiteralPath $temporaryDirectory) { Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force }
}
