[CmdletBinding()]
param(
  [string]$EvidenceDirectory = '',
  [string]$OutputPath = '',
  [string]$ExpectedSourceRawSha256 = 'C37C70C8CAEF443BDC3D5E889BAD907A63A028970446353BF19609146EAE72E7'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Utf8Atomic {
  param(
    [string]$Path,
    [string]$Content
  )
  $parent = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $parent)) {
    [System.IO.Directory]::CreateDirectory($parent) | Out-Null
  }
  $temporaryPath = Join-Path $parent ('.' + [System.IO.Path]::GetFileName($Path) + '.' + [guid]::NewGuid().ToString('N') + '.tmp')
  try {
    [System.IO.File]::WriteAllText($temporaryPath, $Content, [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) {
      Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
    }
  }
}

function Read-ImageTraceEvents {
  param([string]$Path)
  $events = New-Object System.Collections.Generic.List[object]
  foreach ($line in [System.IO.File]::ReadAllLines($Path, [System.Text.UTF8Encoding]::new($false))) {
    $marker = 'MANXIA_LEGADO_IMAGE_TRACE:'
    $markerIndex = $line.IndexOf($marker, [System.StringComparison]::Ordinal)
    if ($markerIndex -lt 0) {
      continue
    }
    $json = $line.Substring($markerIndex + $marker.Length).Trim()
    try {
      $events.Add(($json | ConvertFrom-Json)) | Out-Null
    } catch {
      throw "Image trace JSON is invalid: $Path"
    }
  }
  return @($events.ToArray())
}

function Get-Count {
  param(
    [string]$Text,
    [string]$Pattern
  )
  return [regex]::Matches($Text, $Pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase).Count
}

if ($EvidenceDirectory.Length -eq 0) {
  $EvidenceDirectory = Join-Path $PSScriptRoot 'device-evidence'
}
if ($OutputPath.Length -eq 0) {
  $OutputPath = Join-Path $PSScriptRoot 'evidence\compat-013-frameidle-device-gate.json'
}

$samples = @(
  [pscustomobject]@{
    name = 'initial'
    expectedRequests = 18
    logPath = Join-Path $EvidenceDirectory 'frameidle-image-reader-initial-20260731.hilog.log'
  },
  [pscustomobject]@{
    name = 'retry_1'
    expectedRequests = 21
    logPath = Join-Path $EvidenceDirectory 'frameidle-image-reader-retry1-20260731.hilog.log'
  },
  [pscustomobject]@{
    name = 'retry_2'
    expectedRequests = 24
    logPath = Join-Path $EvidenceDirectory 'frameidle-image-reader-retry2-20260731.hilog.log'
  }
)

$resultSamples = New-Object System.Collections.Generic.List[object]
$previousRequestCount = -1
foreach ($sample in $samples) {
  if (-not (Test-Path -LiteralPath $sample.logPath)) {
    throw "Required device evidence is missing: $($sample.logPath)"
  }
  $text = [System.IO.File]::ReadAllText($sample.logPath, [System.Text.UTF8Encoding]::new($false))
  $events = @(Read-ImageTraceEvents -Path $sample.logPath)
  $requests = @($events | Where-Object { [string]$_.outcome -eq 'request_started' })
  $sourceRawHashes = @(
    $events |
      ForEach-Object { [string]$_.sourceRawSha256 } |
      Where-Object { $_.Length -gt 0 } |
      Sort-Object -Unique
  )
  $traceProcessIds = @(
    [regex]::Matches($text, '(?m)^\d\d-\d\d\s+\d\d:\d\d:\d\d\.\d+\s+(\d+)\s+\d+\s+[WEID]\s+.*MANXIA_LEGADO_IMAGE_TRACE') |
      ForEach-Object { [int]$_.Groups[1].Value } |
      Sort-Object -Unique
  )
  $pathStackDuringRender = Get-Count -Text $text -Pattern "State variable 'pathStack' has changed during render"
  $testInterference = Get-Count -Text $text -Pattern 'TestAbility|entry_test|aa test'
  $appFatal = Get-Count -Text $text -Pattern '(?s)com\.dlzz\.manxia.{0,240}(?:FATAL|Fatal signal|Killing|has died)|(?:FATAL|Fatal signal|Killing|has died).{0,240}com\.dlzz\.manxia'
  $requestCount = $requests.Count
  if ($requestCount -ne [int]$sample.expectedRequests) {
    throw "Unexpected request_started count for $($sample.name): expected=$($sample.expectedRequests), actual=$requestCount"
  }
  if ($sourceRawHashes.Count -ne 1 -or $sourceRawHashes[0] -ne $ExpectedSourceRawSha256) {
    throw "Image trace raw source identity mismatch for $($sample.name)."
  }
  if ($pathStackDuringRender -ne 0 -or $testInterference -ne 0 -or $appFatal -ne 0) {
    throw "Frame-idle gate failed for $($sample.name): pathStack=$pathStackDuringRender test=$testInterference fatal=$appFatal"
  }
  $increment = if ($previousRequestCount -lt 0) { 0 } else { $requestCount - $previousRequestCount }
  if ($previousRequestCount -ge 0 -and $increment -ne 3) {
    throw "Retry request increment is not bounded to three for $($sample.name): actual=$increment"
  }
  $resultSamples.Add([pscustomobject][ordered]@{
    name = [string]$sample.name
    evidenceFile = [System.IO.Path]::GetFileName($sample.logPath)
    requestStarted = $requestCount
    requestIncrement = $increment
    traceEventCount = $events.Count
    traceProcessIds = @($traceProcessIds)
    sourceRawSha256 = $sourceRawHashes[0]
    pathStackChangedDuringRender = $pathStackDuringRender
    testInterference = $testInterference
    appFatalOrKill = $appFatal
  }) | Out-Null
  $previousRequestCount = $requestCount
}

$requiredScreenshots = @(
  (Join-Path $EvidenceDirectory 'ui-audit\frameidle-image-reader-stable-20260731.jpeg'),
  (Join-Path $EvidenceDirectory 'ui-audit\frameidle-image-reader-retry2-20260731.jpeg')
)
foreach ($screenshot in $requiredScreenshots) {
  if (-not (Test-Path -LiteralPath $screenshot)) {
    throw "Required UI screenshot is missing: $screenshot"
  }
}

$evidence = [pscustomobject][ordered]@{
  schemaVersion = 1
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  issueId = 'ISSUE-COMPAT-013'
  verdict = 'passed'
  navigationCommitBoundary = 'UIContext.postFrameCallback + FrameCallback.onIdle'
  sourceRawSha256 = $ExpectedSourceRawSha256
  workflow = 'IMAGE search -> detail -> toc -> reader -> retry -> retry'
  samples = @($resultSamples.ToArray())
  screenshotFiles = @(
    'ui-audit\frameidle-image-reader-stable-20260731.jpeg',
    'ui-audit\frameidle-image-reader-retry2-20260731.jpeg'
  )
}
Write-Utf8Atomic -Path $OutputPath -Content ($evidence | ConvertTo-Json -Depth 12)
Write-Output ('FRAMEIDLE_DEVICE_GATE_PASSED samples={0} requests={1}/{2}/{3}' -f
  $resultSamples.Count,
  [int]$resultSamples[0].requestStarted,
  [int]$resultSamples[1].requestStarted,
  [int]$resultSamples[2].requestStarted)
