[CmdletBinding()]
param(
  [string]$AdbPath = 'G:\Android\Sdk\platform-tools\adb.exe',
  [string]$Serial = 'emulator-5560',
  [string]$SourcePackagePath = 'F:\Downloads-E\墨辰整理书源大全7.1（禁止倒卖）.【最新完整】.json',
  [Parameter(Mandatory = $true)]
  [ValidatePattern('^[A-F0-9]{64}$')]
  [string]$SourceHash,
  [string]$Keyword = '斗破苍穹',
  [string]$ExpectedSourcePackageSha256 = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67',
  [string]$LegadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd',
  [switch]$IncludeContentResponseProbe,
  [string]$EvidencePath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ReferenceUtcNow {
  $timestamp = [DateTimeOffset]::UtcNow
  return $timestamp.ToUniversalTime().ToString('o')
}

$nativeProcessHelperPath = Join-Path $PSScriptRoot 'Invoke-LegadoNativeProcess.ps1'
if (-not (Test-Path -LiteralPath $nativeProcessHelperPath)) {
  throw '原生进程边界脚本不存在。'
}
. $nativeProcessHelperPath
$referenceTraceParserPath = Join-Path $PSScriptRoot 'LegadoReferenceTraceParser.psm1'
if (-not (Test-Path -LiteralPath $referenceTraceParserPath)) {
  throw '原版 trace 分片解析模块不存在。'
}
Import-Module -Name $referenceTraceParserPath -Force -ErrorAction Stop

$DebugPackage = 'io.legado.app.debug'
$InstrumentationComponent = 'io.legado.app.debug.test/androidx.test.runner.AndroidJUnitRunner'
$ReferenceTestClass = 'io.legado.app.compat.LegadoLiveSourceReferenceTest'
$RemoteInputPath = ''
$PrivateInputFileName = ''
$script:ReferenceTraceFailureClassification = 'reference_trace_missing'
$TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
  "manxia-legado-single-reference-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
)

if ($EvidencePath.Length -eq 0) {
  # Reference evidence is selected by raw source identity. A shared filename
  # lets a later source overwrite the only witness and makes the V2 runner
  # correctly reject an otherwise valid empty result as unreferenced.
  $EvidencePath = Join-Path $PSScriptRoot ("evidence\single-source-reference-{0}-{1}.json" -f $SourceHash, [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())
}

function Get-Sha256ForBytes {
  param([byte[]]$Bytes)
  $algorithm = [System.Security.Cryptography.SHA256]::Create()
  try {
    return ([System.BitConverter]::ToString($algorithm.ComputeHash($Bytes))).Replace('-', '')
  } finally {
    $algorithm.Dispose()
  }
}

function Get-Sha256ForText {
  param([string]$Value)
  return Get-Sha256ForBytes -Bytes ([System.Text.UTF8Encoding]::new($false).GetBytes($Value))
}

function Invoke-Adb {
  param(
    [string[]]$Arguments,
    [ValidateRange(1, 1800)]
    [int]$TimeoutSeconds = 30,
    [switch]$AllowFailure
  )
  [string[]]$nativeArguments = @('-s', $Serial) + @($Arguments)
  $result = Invoke-LegadoNativeProcess `
    -FilePath $AdbPath `
    -ArgumentList $nativeArguments `
    -TimeoutSeconds $TimeoutSeconds
  if (-not $AllowFailure -and $result.classification -ne 'success') {
    $detail = @($result.output -split '[\r\n]+' | Where-Object { $_.Trim().Length -gt 0 } | Select-Object -First 1)
    throw (
      "ADB_FAILED classification=$($result.classification);timedOut=$($result.timedOut);" +
      "exitCode=$($result.exitCode);detail=$([string]::Join(' ', $detail))"
    )
  }
  return [pscustomobject][ordered]@{
    output = [string]$result.output
    exitCode = [int]$result.exitCode
    timedOut = [bool]$result.timedOut
    classification = [string]$result.classification
  }
}

function Get-AdbFailureSummary {
  param([object]$Result)
  return (
    "classification={0};timedOut={1};exitCode={2}"
  ) -f @(
    [string]$Result.classification,
    [bool]$Result.timedOut,
    [int]$Result.exitCode
  )
}

function ConvertFrom-JsonArray {
  param([string]$Json, [string]$Label)
  $parsed = ConvertFrom-Json -InputObject $Json
  if ($parsed -isnot [System.Array]) {
    throw "$Label 必须是顶层 JSON 数组。"
  }
  $items = New-Object 'System.Collections.Generic.List[object]'
  foreach ($item in $parsed) {
    [void]$items.Add($item)
  }
  return $items.ToArray()
}

function Get-JsonTopLevelObjectDocuments {
  param([string]$Json, [string]$Label)
  $text = $Json.Trim()
  if (-not $text.StartsWith('[')) {
    throw "$Label 必须是顶层 JSON 数组。"
  }
  $documents = New-Object 'System.Collections.Generic.List[string]'
  $inString = $false
  $escaped = $false
  $depth = 0
  $start = -1
  for ($index = 0; $index -lt $text.Length; $index++) {
    $char = $text[$index]
    if ($inString) {
      if ($escaped) {
        $escaped = $false
      } elseif ($char -eq '\') {
        $escaped = $true
      } elseif ($char -eq '"') {
        $inString = $false
      }
      continue
    }
    if ($char -eq '"') {
      $inString = $true
    } elseif ($char -eq '{') {
      if ($depth -eq 0) {
        $start = $index
      }
      $depth = $depth + 1
    } elseif ($char -eq '}') {
      $depth = $depth - 1
      if ($depth -eq 0 -and $start -ge 0) {
        [void]$documents.Add($text.Substring($start, $index - $start + 1))
        $start = -1
      }
    }
  }
  if ($inString -or $depth -ne 0 -or $documents.Count -le 0) {
    throw "$Label 不是完整的顶层 JSON 对象数组。"
  }
  return $documents.ToArray()
}

function Write-Utf8Atomic {
  param([string]$Path, [string]$Content)
  $directory = Split-Path -Path $Path -Parent
  if (-not (Test-Path -LiteralPath $directory)) {
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  }
  $temporaryPath = "$Path.tmp.$PID.$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  [System.IO.File]::WriteAllText($temporaryPath, $Content, [System.Text.UTF8Encoding]::new($false))
  Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
}

function Get-ObjectProperty {
  param([object]$Object, [string]$Name)
  if ($null -eq $Object) {
    return $null
  }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) {
    return $null
  }
  return $property.Value
}

function Get-TraceNumber {
  param([object]$Trace, [string]$Name)
  $value = Get-ObjectProperty -Object $Trace -Name $Name
  if ($null -eq $value) {
    return 0
  }
  $number = 0
  if ([int]::TryParse([string]$value, [ref]$number)) {
    return $number
  }
  return 0
}

function Get-TraceText {
  param([object]$Trace, [string]$Name)
  $value = Get-ObjectProperty -Object $Trace -Name $Name
  if ($null -eq $value) {
    return ''
  }
  return [string]$value
}

function Get-TraceHeaderNames {
  param([object]$Trace, [string]$Name)
  $value = Get-ObjectProperty -Object $Trace -Name $Name
  if ($null -eq $value) {
    return @()
  }
  $names = New-Object 'System.Collections.Generic.List[string]'
  foreach ($entry in @($value)) {
    $headerName = ([string]$entry).Trim().ToLowerInvariant()
    if ($headerName -match '^[a-z0-9-]{1,64}$' -and -not $names.Contains($headerName)) {
      [void]$names.Add($headerName)
    }
  }
  return $names.ToArray()
}

function Get-TraceTargetSequence {
  param([object]$Trace, [string]$Name)
  $value = Get-ObjectProperty -Object $Trace -Name $Name
  if ($null -eq $value) { return @() }
  $targets = New-Object 'System.Collections.Generic.List[string]'
  foreach ($entry in @($value)) {
    $target = ([string]$entry).Trim().ToLowerInvariant()
    # Keep the host boundary value-free even if an instrumentation build is
    # changed incorrectly. The only permitted records are the fixed markers
    # and one-way SHA-256 target digests produced by the test runner.
    if ($target -match '^(empty|digest_error|[0-9a-f]{64})$' -and $targets.Count -lt 8) {
      [void]$targets.Add($target)
    }
  }
  return $targets.ToArray()
}

function Get-ReferenceFailureCategory {
  param([System.Management.Automation.ErrorRecord]$ErrorRecord)
  $message = ''
  if ($null -ne $ErrorRecord.Exception) {
    $message = [string]$ErrorRecord.Exception.Message
  }
  if ($message -match '(?i)device_lease|设备租约') {
    return 'device_lease_conflict'
  }
  if ($message -match '(?i)instrumentation|debug 包') {
    return 'reference_instrumentation'
  }
  if ($message -match '(?i)run-as|私有输入|临时目录') {
    return 'private_input_transport'
  }
  if ($message -match '(?i)书源包|SHA-256|哈希') {
    return 'baseline_or_source_input'
  }
  return 'reference_runner_other'
}

function Get-ReferenceNativeFailureClassification {
  param([System.Management.Automation.ErrorRecord]$ErrorRecord)
  $message = ''
  if ($null -ne $ErrorRecord.Exception) {
    $message = [string]$ErrorRecord.Exception.Message
  }
  $match = [regex]::Match($message, '(?i)classification=([a-z0-9_]+)')
  if ($match.Success) {
    return $match.Groups[1].Value.ToLowerInvariant()
  }
  return ''
}

function Get-ReferenceTrace {
  param([string]$ExpectedAttemptId)
  # Android splits a long Log.i message at the logger buffer boundary. The
  # original reference trace deliberately includes several digest-only
  # workflow witnesses and therefore can span multiple raw log records. Read
  # raw messages and reassemble in memory; neither the fragments nor the
  # completed payload are persisted outside the existing sanitized evidence.
  $logResult = Invoke-Adb -Arguments @('logcat', '-d', '-v', 'raw', '-s', 'LegadoLiveReference:I') -AllowFailure
  if ($logResult.exitCode -ne 0) {
    $script:ReferenceTraceFailureClassification = 'reference_trace_log_read_failed'
    return $null
  }
  $lines = @($logResult.output -split "`r?`n")
  $records = Read-LegadoReferenceTraceRecords -Lines $lines -AttemptIdPattern '^[A-F0-9]{64}/[0-9]{1,2}$'
  if ($records.ContainsKey($ExpectedAttemptId)) {
    $script:ReferenceTraceFailureClassification = ''
    return $records[$ExpectedAttemptId]
  }
  $hasFragmentMarker = @($lines | Where-Object { [string]$_ -match 'LEGADO_LIVE_TRACE_PART:' }).Count -gt 0
  $hasLegacyMarker = @($lines | Where-Object { [string]$_ -match 'LEGADO_LIVE_TRACE:' }).Count -gt 0
  # Legacy APKs emit a single Log.i payload. Android's logger truncates it at
  # roughly 4 KiB, so a marker-bearing, unparseable record at that boundary is
  # not a source failure and must not be interpreted as absent execution.
  if ($hasLegacyMarker -and -not $hasFragmentMarker -and $logResult.output.Length -ge 4000) {
    $script:ReferenceTraceFailureClassification = 'reference_trace_legacy_log_truncated'
  } else {
    $script:ReferenceTraceFailureClassification = 'reference_trace_missing'
  }
  return $null
}

$sourceType = -1
$trace = $null
$attemptId = "$SourceHash/9"
$sourcePackageSha256 = ''

try {
  if (-not (Test-Path -LiteralPath $AdbPath)) {
    throw 'ADB 不存在。'
  }
  if (-not (Test-Path -LiteralPath $SourcePackagePath)) {
    throw '固定书源包不存在。'
  }

  $packageBytes = [System.IO.File]::ReadAllBytes($SourcePackagePath)
  $sourcePackageSha256 = Get-Sha256ForBytes -Bytes $packageBytes
  if ($sourcePackageSha256 -ne $ExpectedSourcePackageSha256) {
    throw '书源包 SHA-256 不匹配，禁止与既有基线混合。'
  }
  $sourcePackageText = [System.Text.UTF8Encoding]::new($false).GetString($packageBytes)
  $sourceDocuments = @(ConvertFrom-JsonArray -Json $sourcePackageText -Label '固定书源包')
  $rawDocuments = @(Get-JsonTopLevelObjectDocuments -Json $sourcePackageText -Label '固定书源包')
  if ($sourceDocuments.Count -ne $rawDocuments.Count) {
    throw '固定书源包的原文文档数与解析文档数不一致。'
  }
  $selectedSource = $null
  for ($sourceIndex = 0; $sourceIndex -lt $sourceDocuments.Count; $sourceIndex++) {
    if ((Get-Sha256ForText -Value $rawDocuments[$sourceIndex]) -eq $SourceHash) {
      $selectedSource = $sourceDocuments[$sourceIndex]
      break
    }
  }
  if ($null -eq $selectedSource) {
    throw '固定书源包中不存在目标原始文档 SHA-256。'
  }
  $sourceTypeText = [string](Get-ObjectProperty -Object $selectedSource -Name 'bookSourceType')
  if (-not [int]::TryParse($sourceTypeText, [ref]$sourceType)) {
    $sourceType = -1
  }
  if ($Keyword.Trim().Length -eq 0) {
    throw '测试关键字不能为空。'
  }

  $instrumentationResult = Invoke-Adb -Arguments @('shell', 'pm', 'list', 'instrumentation', $DebugPackage) -AllowFailure
  if ($instrumentationResult.exitCode -ne 0 -or $instrumentationResult.output -notmatch [regex]::Escape($InstrumentationComponent)) {
    throw "原版 Legado debug instrumentation 未安装；$(Get-AdbFailureSummary -Result $instrumentationResult)"
  }
  $runAsResult = Invoke-Adb -Arguments @('shell', 'run-as', $DebugPackage, 'ls', '-ld', 'files') -AllowFailure
  if ($runAsResult.exitCode -ne 0) {
    throw "原版 Legado debug 包不支持 run-as 私有输入；$(Get-AdbFailureSummary -Result $runAsResult)"
  }

  [System.IO.Directory]::CreateDirectory($TempRoot) | Out-Null
  $hostInputPath = Join-Path $TempRoot 'reference-input.json'
  $inputEntry = [pscustomobject][ordered]@{
    sourceHash = $SourceHash
    attemptId = $attemptId
    keyword = $Keyword
    includeDiagnosticFingerprints = $true
    includeContentResponseProbe = [bool]$IncludeContentResponseProbe
    source = $selectedSource
  }
  # ConvertTo-Json receives a single pipeline item as an object. Preserve the
  # envelope's array contract explicitly because the Android test uses JSONArray.
  # Keep one entry wrapped in a real CLR array. PowerShell otherwise enumerates
  # a one-item collection during parameter binding and serializes a JSONObject,
  # while the test-only Android entry point deliberately requires a JSONArray.
  [object[]]$inputEnvelope = @($inputEntry)
  $inputJson = ConvertTo-Json -InputObject $inputEnvelope -Depth 100 -Compress
  Write-Utf8Atomic -Path $hostInputPath -Content $inputJson

  $inputId = "$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  $PrivateInputFileName = "legado-single-reference-$inputId.json"
  $RemoteInputPath = "/data/local/tmp/manxia-legado-single-reference-$inputId.json"
  $pushResult = Invoke-Adb `
    -Arguments @('push', $hostInputPath, $RemoteInputPath) `
    -TimeoutSeconds 120 `
    -AllowFailure
  if ($pushResult.exitCode -ne 0) {
    throw "无法将原版测试输入写入模拟器临时目录；$(Get-AdbFailureSummary -Result $pushResult)"
  }
  $copyResult = Invoke-Adb -Arguments @('shell', 'run-as', $DebugPackage, 'cp', $RemoteInputPath, "files/$PrivateInputFileName") -AllowFailure
  if ($copyResult.exitCode -ne 0) {
    throw "无法将原版测试输入写入应用私有目录；$(Get-AdbFailureSummary -Result $copyResult)"
  }
  $chmodResult = Invoke-Adb -Arguments @('shell', 'run-as', $DebugPackage, 'chmod', '600', "files/$PrivateInputFileName") -AllowFailure
  if ($chmodResult.exitCode -ne 0) {
    throw "无法保护原版测试私有输入文件；$(Get-AdbFailureSummary -Result $chmodResult)"
  }

  [void](Invoke-Adb -Arguments @('logcat', '-c') -AllowFailure)
  $instrumentationResult = Invoke-Adb `
    -Arguments @(
      'shell', 'am', 'instrument', '-w', '-r',
      '-e', 'class', $ReferenceTestClass,
      '-e', 'liveInputFileName', $PrivateInputFileName,
      $InstrumentationComponent
    ) `
    -TimeoutSeconds 1200 `
    -AllowFailure
  if ($instrumentationResult.exitCode -ne 0 -or $instrumentationResult.output -match '(?i)INSTRUMENTATION_FAILED|FAILURES!!!|Process crashed') {
    throw "原版 Legado 单书源 instrumentation 未完成；$(Get-AdbFailureSummary -Result $instrumentationResult)"
  }
  $trace = Get-ReferenceTrace -ExpectedAttemptId $attemptId
  if ($null -eq $trace) {
    throw "原版 Legado 未产生可匹配的脱敏 trace；classification=$script:ReferenceTraceFailureClassification"
  }
  $contentProbeOutcome = Get-TraceText -Trace $trace -Name 'contentProbeOutcome'
  $contentProbeAvailable = -not $IncludeContentResponseProbe -or $contentProbeOutcome -eq 'complete'

  $evidence = [pscustomobject][ordered]@{
    schemaVersion = 6
    generatedAt = Get-ReferenceUtcNow
    sourcePackageSha256 = $sourcePackageSha256
    legadoCommit = $LegadoCommit
    sourceHash = $SourceHash
    sourceType = $sourceType
    keywordSha256 = Get-Sha256ForText -Value $Keyword
    automation = 'adb_instrumentation_run_as_private_single_source'
    reference = [pscustomobject][ordered]@{
      traceReceived = $true
      stage = [string](Get-ObjectProperty -Object $trace -Name 'stage')
      outcome = [string](Get-ObjectProperty -Object $trace -Name 'outcome')
      contentProbeRequested = [bool]$IncludeContentResponseProbe
      contentProbeAvailable = $contentProbeAvailable
      searchCount = Get-TraceNumber -Trace $trace -Name 'searchCount'
      bookInfoReady = [bool](Get-ObjectProperty -Object $trace -Name 'bookInfoReady')
      tocCount = Get-TraceNumber -Trace $trace -Name 'tocCount'
      contentLength = Get-TraceNumber -Trace $trace -Name 'contentLength'
      contentFingerprint = Get-TraceText -Trace $trace -Name 'contentSha256'
      contentLineFeedCount = Get-TraceNumber -Trace $trace -Name 'contentLineFeedCount'
      contentCarriageReturnCount = Get-TraceNumber -Trace $trace -Name 'contentCarriageReturnCount'
      contentLeadingWhitespaceCount = Get-TraceNumber -Trace $trace -Name 'contentLeadingWhitespaceCount'
      contentTrailingWhitespaceCount = Get-TraceNumber -Trace $trace -Name 'contentTrailingWhitespaceCount'
      image = [pscustomobject][ordered]@{
        protocol = Get-TraceText -Trace $trace -Name 'firstImageProtocol'
        requestTargetSha256 = Get-TraceText -Trace $trace -Name 'firstImageTargetSha256'
        requestHeaderNames = @(Get-TraceHeaderNames -Trace $trace -Name 'firstImageRequestHeaderNames')
        requestUserAgentSha256 = Get-TraceText -Trace $trace -Name 'firstImageRequestUserAgentSha256'
        outcome = Get-TraceText -Trace $trace -Name 'firstImageProbeOutcome'
        statusCode = Get-TraceNumber -Trace $trace -Name 'firstImageProbeStatusCode'
        finalTargetSha256 = Get-TraceText -Trace $trace -Name 'firstImageFinalTargetSha256'
        responseContentType = Get-TraceText -Trace $trace -Name 'firstImageProbeContentType'
        byteLength = Get-TraceNumber -Trace $trace -Name 'firstImageProbeByteLength'
        decodeOutcome = Get-TraceText -Trace $trace -Name 'firstImageDecodeOutcome'
      }
      diagnostic = [pscustomobject][ordered]@{
        sourceBaseTargetSha256 = Get-TraceText -Trace $trace -Name 'sourceBaseTargetSha256'
        sourceEffectiveUserAgentSha256 = Get-TraceText -Trace $trace -Name 'sourceEffectiveUserAgentSha256'
        searchProbePlannedTargetSha256 = Get-TraceText -Trace $trace -Name 'searchProbePlannedTargetSha256'
        searchProbeOutcome = Get-TraceText -Trace $trace -Name 'searchProbeOutcome'
        searchProbeStatusCode = Get-TraceNumber -Trace $trace -Name 'searchProbeStatusCode'
        searchProbeFinalTargetSha256 = Get-TraceText -Trace $trace -Name 'searchProbeFinalTargetSha256'
        searchProbeRequestUserAgentSha256 = Get-TraceText -Trace $trace -Name 'searchProbeRequestUserAgentSha256'
        searchProbeRequestMethod = Get-TraceText -Trace $trace -Name 'searchProbeRequestMethod'
        searchProbeRequestHeaderCount = Get-TraceNumber -Trace $trace -Name 'searchProbeRequestHeaderCount'
        searchProbeRequestHeaderNames = @(Get-TraceHeaderNames -Trace $trace -Name 'searchProbeRequestHeaderNames')
        searchProbeRequestHeaderFingerprint = Get-TraceText -Trace $trace -Name 'searchProbeRequestHeaderFingerprint'
        searchProbeContentType = Get-TraceText -Trace $trace -Name 'searchProbeContentType'
        searchProbeBodyLength = Get-TraceNumber -Trace $trace -Name 'searchProbeBodyLength'
        searchProbeBodyFingerprint = Get-TraceText -Trace $trace -Name 'searchProbeBodyFingerprint'
        searchProbeResponseClass = Get-TraceText -Trace $trace -Name 'searchProbeResponseClass'
        firstSearchBookTargetSha256 = Get-TraceText -Trace $trace -Name 'firstSearchBookTargetSha256'
        searchBookTargetSequenceSha256 = @(Get-TraceTargetSequence -Trace $trace -Name 'searchBookTargetSequenceSha256')
        searchBookTargetSequenceDistinctCount = Get-TraceNumber -Trace $trace -Name 'searchBookTargetSequenceDistinctCount'
        searchBookTargetSequenceEmptyCount = Get-TraceNumber -Trace $trace -Name 'searchBookTargetSequenceEmptyCount'
        firstSearchBookHeadersVariableFingerprint = Get-TraceText -Trace $trace -Name 'firstSearchBookHeadersVariableFingerprint'
        bookInfoBookTargetSha256 = Get-TraceText -Trace $trace -Name 'bookInfoBookTargetSha256'
        tocTargetSha256 = Get-TraceText -Trace $trace -Name 'tocTargetSha256'
        tocPlannedRequestUrlFingerprint = Get-TraceText -Trace $trace -Name 'tocPlannedRequestUrlFingerprint'
        bookInfoHeadersVariableFingerprint = Get-TraceText -Trace $trace -Name 'bookInfoHeadersVariableFingerprint'
        firstChapterTargetSha256 = Get-TraceText -Trace $trace -Name 'firstChapterTargetSha256'
        contentProbeOutcome = $contentProbeOutcome
        contentProbeStatusCode = Get-TraceNumber -Trace $trace -Name 'contentProbeStatusCode'
        contentProbePlannedTargetSha256 = Get-TraceText -Trace $trace -Name 'contentProbePlannedTargetSha256'
        contentProbeFinalTargetSha256 = Get-TraceText -Trace $trace -Name 'contentProbeFinalTargetSha256'
        contentProbeRequestUserAgentSha256 = Get-TraceText -Trace $trace -Name 'contentProbeRequestUserAgentSha256'
        contentProbeRequestMethod = Get-TraceText -Trace $trace -Name 'contentProbeRequestMethod'
        contentProbeRequestHeaderCount = Get-TraceNumber -Trace $trace -Name 'contentProbeRequestHeaderCount'
        contentProbeRequestHeaderNames = @(Get-TraceHeaderNames -Trace $trace -Name 'contentProbeRequestHeaderNames')
        contentProbeRequestHeaderFingerprint = Get-TraceText -Trace $trace -Name 'contentProbeRequestHeaderFingerprint'
        contentProbeContentType = Get-TraceText -Trace $trace -Name 'contentProbeContentType'
        contentProbeBodyLength = Get-TraceNumber -Trace $trace -Name 'contentProbeBodyLength'
        contentProbeBodyFingerprint = Get-TraceText -Trace $trace -Name 'contentProbeBodyFingerprint'
        contentProbeResponseClass = Get-TraceText -Trace $trace -Name 'contentProbeResponseClass'
        bookInfoProbeOutcome = Get-TraceText -Trace $trace -Name 'bookInfoProbeOutcome'
        bookInfoProbeStatusCode = Get-TraceNumber -Trace $trace -Name 'bookInfoProbeStatusCode'
        bookInfoProbePlannedTargetSha256 = Get-TraceText -Trace $trace -Name 'bookInfoProbePlannedTargetSha256'
        bookInfoProbeFinalTargetSha256 = Get-TraceText -Trace $trace -Name 'bookInfoProbeFinalTargetSha256'
        bookInfoProbeRequestUserAgentSha256 = Get-TraceText -Trace $trace -Name 'bookInfoProbeRequestUserAgentSha256'
        bookInfoProbeRequestMethod = Get-TraceText -Trace $trace -Name 'bookInfoProbeRequestMethod'
        bookInfoProbeRequestHeaderCount = Get-TraceNumber -Trace $trace -Name 'bookInfoProbeRequestHeaderCount'
        bookInfoProbeRequestHeaderNames = @(Get-TraceHeaderNames -Trace $trace -Name 'bookInfoProbeRequestHeaderNames')
        bookInfoProbeRequestHeaderFingerprint = Get-TraceText -Trace $trace -Name 'bookInfoProbeRequestHeaderFingerprint'
        bookInfoProbeContentType = Get-TraceText -Trace $trace -Name 'bookInfoProbeContentType'
        bookInfoProbeBodyLength = Get-TraceNumber -Trace $trace -Name 'bookInfoProbeBodyLength'
        bookInfoProbeBodyFingerprint = Get-TraceText -Trace $trace -Name 'bookInfoProbeBodyFingerprint'
        bookInfoProbeResponseClass = Get-TraceText -Trace $trace -Name 'bookInfoProbeResponseClass'
        workflowErrorClass = Get-TraceText -Trace $trace -Name 'workflowErrorClass'
        workflowErrorMessageSha256 = Get-TraceText -Trace $trace -Name 'workflowErrorMessageSha256'
        workflowErrorLine = Get-TraceNumber -Trace $trace -Name 'workflowErrorLine'
        workflowErrorColumn = Get-TraceNumber -Trace $trace -Name 'workflowErrorColumn'
        workflowErrorFileNameSha256 = Get-TraceText -Trace $trace -Name 'workflowErrorFileNameSha256'
        workflowErrorCauseClass = Get-TraceText -Trace $trace -Name 'workflowErrorCauseClass'
        workflowErrorCauseMessageSha256 = Get-TraceText -Trace $trace -Name 'workflowErrorCauseMessageSha256'
        bookInfoProbeErrorClass = Get-TraceText -Trace $trace -Name 'bookInfoProbeErrorClass'
        bookInfoProbeErrorMessageSha256 = Get-TraceText -Trace $trace -Name 'bookInfoProbeErrorMessageSha256'
        tocErrorClass = Get-TraceText -Trace $trace -Name 'tocErrorClass'
        tocErrorMessageSha256 = Get-TraceText -Trace $trace -Name 'tocErrorMessageSha256'
      }
    }
  }
  Write-Utf8Atomic -Path $EvidencePath -Content ($evidence | ConvertTo-Json -Depth 8)
  Write-Output (
    "SINGLE_REFERENCE_COMPLETE type=$sourceType stage=$($evidence.reference.stage) " +
    "outcome=$($evidence.reference.outcome) search=$($evidence.reference.searchCount) " +
    "toc=$($evidence.reference.tocCount) content=$($evidence.reference.contentLength) " +
    "contentProbe=$(if ($evidence.reference.contentProbeAvailable) { 'available' } else { 'unavailable' })"
  )
} catch {
  $failureEvidence = [pscustomobject][ordered]@{
    schemaVersion = 6
    generatedAt = Get-ReferenceUtcNow
    sourcePackageSha256 = $sourcePackageSha256
    legadoCommit = $LegadoCommit
    sourceHash = $SourceHash
    sourceType = $sourceType
    keywordSha256 = Get-Sha256ForText -Value $Keyword
    automation = 'adb_instrumentation_run_as_private_single_source'
    outcome = 'reference_runner_failed'
    failureCategory = Get-ReferenceFailureCategory -ErrorRecord $_
    nativeFailureClassification = Get-ReferenceNativeFailureClassification -ErrorRecord $_
    reference = [pscustomobject][ordered]@{
      traceReceived = $false
      stage = 'missing'
      outcome = 'missing_reference_trace'
      contentProbeRequested = [bool]$IncludeContentResponseProbe
      contentProbeAvailable = $false
      searchCount = 0
      bookInfoReady = $false
      tocCount = 0
      contentLength = 0
      contentFingerprint = ''
      contentLineFeedCount = 0
      contentCarriageReturnCount = 0
      contentLeadingWhitespaceCount = 0
      contentTrailingWhitespaceCount = 0
      image = [pscustomobject][ordered]@{
        protocol = ''
        requestTargetSha256 = ''
        requestHeaderNames = @()
        requestUserAgentSha256 = ''
        outcome = ''
        statusCode = 0
        finalTargetSha256 = ''
        responseContentType = ''
        byteLength = 0
        decodeOutcome = ''
      }
      diagnostic = [pscustomobject][ordered]@{
        sourceBaseTargetSha256 = ''
        sourceEffectiveUserAgentSha256 = ''
        firstSearchBookTargetSha256 = ''
        firstSearchBookHeadersVariableFingerprint = ''
        bookInfoBookTargetSha256 = ''
        tocTargetSha256 = ''
        bookInfoHeadersVariableFingerprint = ''
        firstChapterTargetSha256 = ''
        contentProbeOutcome = ''
        contentProbeStatusCode = 0
        contentProbePlannedTargetSha256 = ''
        contentProbeFinalTargetSha256 = ''
        contentProbeRequestUserAgentSha256 = ''
        contentProbeRequestMethod = ''
        contentProbeRequestHeaderCount = 0
        contentProbeRequestHeaderNames = @()
        contentProbeRequestHeaderFingerprint = ''
        contentProbeContentType = ''
        contentProbeBodyLength = 0
        contentProbeBodyFingerprint = ''
        contentProbeResponseClass = ''
        bookInfoProbeOutcome = ''
        bookInfoProbeStatusCode = 0
        bookInfoProbePlannedTargetSha256 = ''
        bookInfoProbeFinalTargetSha256 = ''
        bookInfoProbeRequestUserAgentSha256 = ''
        bookInfoProbeRequestMethod = ''
        bookInfoProbeRequestHeaderCount = 0
        bookInfoProbeRequestHeaderNames = @()
        bookInfoProbeRequestHeaderFingerprint = ''
        bookInfoProbeContentType = ''
        bookInfoProbeBodyLength = 0
        bookInfoProbeBodyFingerprint = ''
      }
    }
  }
  Write-Utf8Atomic -Path $EvidencePath -Content ($failureEvidence | ConvertTo-Json -Depth 8)
  throw
} finally {
  if ($PrivateInputFileName.Length -gt 0 -and (Test-Path -LiteralPath $AdbPath)) {
    [void](Invoke-Adb -Arguments @('shell', 'run-as', $DebugPackage, 'rm', '-f', "files/$PrivateInputFileName") -AllowFailure)
  }
  if ($RemoteInputPath.Length -gt 0 -and (Test-Path -LiteralPath $AdbPath)) {
    [void](Invoke-Adb -Arguments @('shell', 'rm', '-f', $RemoteInputPath) -AllowFailure)
  }
  if (Test-Path -LiteralPath $TempRoot) {
    $tempBase = [System.IO.Path]::GetTempPath()
    if ($TempRoot.StartsWith($tempBase, [System.StringComparison]::OrdinalIgnoreCase)) {
      Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
}
