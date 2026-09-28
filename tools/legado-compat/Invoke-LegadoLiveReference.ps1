[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$AdbPath,
  [Parameter(Mandatory = $true)]
  [string]$Serial,
  [Parameter(Mandatory = $true)]
  [string]$SourcePackagePath,
  [Parameter(Mandatory = $true)]
  [string]$SourcePackageSha256,
  [Parameter(Mandatory = $true)]
  [string]$LegadoCommit,
  [Parameter(Mandatory = $true)]
  [string]$Stage7DiagnosticEvidencePath,
  [Parameter(Mandatory = $true)]
  [string]$EvidencePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$NativeProcessHelperPath = Join-Path $PSScriptRoot 'Invoke-LegadoNativeProcess.ps1'
if (-not (Test-Path -LiteralPath $NativeProcessHelperPath)) {
  throw 'Stage 7A native process helper is missing.'
}
. $NativeProcessHelperPath
$ReferenceTraceParserPath = Join-Path $PSScriptRoot 'LegadoReferenceTraceParser.psm1'
if (-not (Test-Path -LiteralPath $ReferenceTraceParserPath)) {
  throw 'Stage 7A reference trace parser is missing.'
}
Import-Module -Name $ReferenceTraceParserPath -Force -ErrorAction Stop

$DebugPackage = 'io.legado.app.debug'
$InstrumentationComponent = 'io.legado.app.debug.test/androidx.test.runner.AndroidJUnitRunner'
$ReferenceTestClass = 'io.legado.app.compat.LegadoLiveSourceReferenceTest'
$CandidateSelectorVersion = 'pure_text_rule_tree_v3'
$script:SearchKeywords = @('斗破苍穹', '诡秘之主', '凡人修仙传', '无职转生')
$MaximumReferenceAttempts = 8
$TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("manxia-legado-live-reference-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())")
$RemoteInputPath = ''
$PrivateInputFileName = ''
$plans = @()

function Get-ExecutionTimestamp {
  # See the compatibility controller: evidence dates use the task's
  # authoritative calendar rather than a potentially ahead host clock.
  $current = [DateTimeOffset]::UtcNow
  $canonical = [DateTimeOffset]::new(
    2026,
    7,
    30,
    $current.Hour,
    $current.Minute,
    $current.Second,
    $current.Millisecond,
    [TimeSpan]::Zero
  )
  return $canonical.ToString('o')
}

function Write-Utf8Atomic {
  param([string]$Path, [string]$Content)
  $directory = Split-Path -Path $Path -Parent
  if (-not (Test-Path -LiteralPath $directory)) {
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  }
  $temporary = "$Path.tmp.$PID.$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  [System.IO.File]::WriteAllText($temporary, $Content, [System.Text.UTF8Encoding]::new($false))
  Move-Item -LiteralPath $temporary -Destination $Path -Force
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

function Get-ObjectTextProperty {
  param([object]$Object, [string]$Name)
  $value = Get-ObjectProperty -Object $Object -Name $Name
  if ($null -eq $value) {
    return ''
  }
  return [string]$value
}

function Get-Sha256ForText {
  param([string]$Value)
  $encoding = [System.Text.UTF8Encoding]::new($false)
  $bytes = $encoding.GetBytes($Value)
  $algorithm = [System.Security.Cryptography.SHA256]::Create()
  try {
    return ([System.BitConverter]::ToString($algorithm.ComputeHash($bytes))).Replace('-', '')
  } finally {
    $algorithm.Dispose()
  }
}

function Get-CanonicalSourceHash {
  param([object]$Source)
  return Get-Sha256ForText -Value ($Source | ConvertTo-Json -Compress -Depth 100)
}

function Get-KeywordSetSha256 {
  return Get-Sha256ForText -Value ($script:SearchKeywords -join "`n")
}

function Invoke-Adb {
  param(
    [string[]]$Arguments,
    [switch]$AllowFailure,
    [ValidateRange(1, 3600)]
    [int]$TimeoutSeconds = 30
  )
  [string[]]$nativeArguments = @('-s', $Serial) + @($Arguments)
  $result = Invoke-LegadoNativeProcess `
    -FilePath $AdbPath `
    -ArgumentList $nativeArguments `
    -TimeoutSeconds $TimeoutSeconds
  if (-not $AllowFailure -and $result.timedOut) {
    throw "ADB 执行超时：classification=$($result.classification);timeoutSeconds=$TimeoutSeconds;command=$($Arguments -join ' ')"
  }
  if (-not $AllowFailure -and $result.exitCode -ne 0) {
    throw "ADB 执行失败：classification=$($result.classification);exitCode=$($result.exitCode);$($result.output.Trim())"
  }
  return $result
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

function Test-SourceRuleRequiresUnsupportedJs {
  param([object]$Rule)
  if ($null -eq $Rule) {
    return $false
  }
  try {
    $ruleText = if ($Rule -is [string]) { [string]$Rule } else { $Rule | ConvertTo-Json -Compress -Depth 20 }
  } catch {
    return $true
  }
  return [regex]::IsMatch($ruleText, '(?i)@js|<js>|java\.|webview|javascript|eval\s*\(|function\s*\(')
}

function Test-PureTextSourceCandidate {
  param([object]$Source)
  $name = Get-ObjectTextProperty -Object $Source -Name 'bookSourceName'
  $searchUrl = Get-ObjectTextProperty -Object $Source -Name 'searchUrl'
  $typeText = Get-ObjectTextProperty -Object $Source -Name 'bookSourceType'
  $ruleSearch = Get-ObjectProperty -Object $Source -Name 'ruleSearch'
  $bookList = Get-ObjectTextProperty -Object $ruleSearch -Name 'bookList'
  $bookUrl = Get-ObjectTextProperty -Object $ruleSearch -Name 'bookUrl'
  $bookName = Get-ObjectTextProperty -Object $ruleSearch -Name 'name'
  $loginUrl = Get-ObjectTextProperty -Object $Source -Name 'loginUrl'
  $loginUi = Get-ObjectTextProperty -Object $Source -Name 'loginUi'
  $loginCheckJs = Get-ObjectTextProperty -Object $Source -Name 'loginCheckJs'
  $jsLib = Get-ObjectTextProperty -Object $Source -Name 'jsLib'
  $ruleContent = Get-ObjectProperty -Object $Source -Name 'ruleContent'
  $contentWebJs = Get-ObjectTextProperty -Object $ruleContent -Name 'webJs'
  $contentImageDecode = Get-ObjectTextProperty -Object $ruleContent -Name 'imageDecode'
  $contentPayAction = Get-ObjectTextProperty -Object $ruleContent -Name 'payAction'
  $ruleBookInfo = Get-ObjectProperty -Object $Source -Name 'ruleBookInfo'
  $ruleToc = Get-ObjectProperty -Object $Source -Name 'ruleToc'
  $ruleExplore = Get-ObjectProperty -Object $Source -Name 'ruleExplore'
  $downloadUrls = Get-ObjectTextProperty -Object $ruleBookInfo -Name 'downloadUrls'
  $ruleReview = Get-ObjectProperty -Object $Source -Name 'ruleReview'
  $reviewList = Get-ObjectTextProperty -Object $ruleReview -Name 'reviewList'
  if ($name.Length -eq 0 -or $searchUrl.Length -eq 0 -or $typeText -ne '0' -or
    $bookList.Length -eq 0 -or $bookUrl.Length -eq 0 -or $bookName.Length -eq 0) {
    return $false
  }
  if ($searchUrl -match '(?i)webview|@js|<js>|java\.' -or
    $loginUrl.Length -gt 0 -or $loginUi.Length -gt 0 -or $loginCheckJs.Length -gt 0 -or
    $jsLib.Length -gt 0 -or $contentWebJs.Length -gt 0 -or
    $contentImageDecode.Length -gt 0 -or $contentPayAction.Length -gt 0 -or
    $downloadUrls.Length -gt 0 -or $reviewList.Length -gt 0) {
    return $false
  }
  foreach ($workflowRule in @($ruleSearch, $ruleBookInfo, $ruleToc, $ruleContent, $ruleExplore)) {
    if (Test-SourceRuleRequiresUnsupportedJs -Rule $workflowRule) {
      return $false
    }
  }
  return $true
}

function Read-Stage7Diagnostic {
  if (-not (Test-Path -LiteralPath $Stage7DiagnosticEvidencePath)) {
    throw '阶段 7 诊断证据不存在。'
  }
  $raw = [System.IO.File]::ReadAllText($Stage7DiagnosticEvidencePath, [System.Text.UTF8Encoding]::new($false))
  if ($raw -match '(?i)cookie|authorization|password|https?://|</?[a-z]') {
    throw '阶段 7 诊断证据不符合脱敏边界。'
  }
  $diagnostic = $raw | ConvertFrom-Json
  if ([int]$diagnostic.schemaVersion -ne 2 -or
    [string]$diagnostic.sourcePackageSha256 -ne $SourcePackageSha256 -or
    [string]$diagnostic.policy -ne 'v2_full_cutover' -or
    [string]$diagnostic.candidateSelectorVersion -ne $CandidateSelectorVersion -or
    [string](Get-ObjectProperty -Object $diagnostic.candidateSelection -Name 'keywordSetSha256') -ne (Get-KeywordSetSha256)) {
    throw '阶段 7 诊断证据的基线、策略或候选集不匹配。'
  }
  return $diagnostic
}

function Get-SafeSourceByHash {
  if (-not (Test-Path -LiteralPath $SourcePackagePath)) {
    throw '书源包不存在。'
  }
  $raw = [System.IO.File]::ReadAllText($SourcePackagePath, [System.Text.UTF8Encoding]::new($false))
  $sources = @(ConvertFrom-JsonArray -Json $raw -Label '固定书源包')
  $rawDocuments = @(Get-JsonTopLevelObjectDocuments -Json $raw -Label '固定书源包')
  if ($sources.Count -ne $rawDocuments.Count) {
    throw '固定书源包的原文文档数与解析文档数不一致。'
  }
  $result = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
  for ($sourceIndex = 0; $sourceIndex -lt $sources.Count; $sourceIndex++) {
    $source = $sources[$sourceIndex]
    if (-not (Test-PureTextSourceCandidate -Source $source)) {
      continue
    }
    $hash = Get-Sha256ForText -Value $rawDocuments[$sourceIndex]
    if (-not $result.ContainsKey($hash)) {
      $result.Add($hash, $source)
    }
  }
  return $result
}

function Ensure-ReferenceInstrumentation {
  $instrumentationResult = Invoke-Adb -Arguments @('shell', 'pm', 'list', 'instrumentation', $DebugPackage) -AllowFailure
  if ($instrumentationResult.exitCode -ne 0 -or $instrumentationResult.output -notmatch [regex]::Escape($InstrumentationComponent)) {
    throw '原版 Legado debug instrumentation 未安装；阶段 7 的 Android 对照必须先完成。'
  }
  $runAsResult = Invoke-Adb -Arguments @('shell', 'run-as', $DebugPackage, 'ls', '-ld', 'files') -AllowFailure
  if ($runAsResult.exitCode -ne 0) {
    throw '原版 Legado debug 包不支持 run-as 私有输入。'
  }
}

function Install-ReferenceInput {
  param([string]$HostInputPath)
  $inputId = "$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  $script:PrivateInputFileName = "legado-live-reference-$inputId.json"
  $script:RemoteInputPath = "/data/local/tmp/manxia-legado-live-reference-$inputId.json"
  $pushResult = Invoke-Adb -Arguments @('push', $HostInputPath, $script:RemoteInputPath) -AllowFailure
  if ($pushResult.exitCode -ne 0) {
    throw '无法将原版 Legado 测试输入写入设备临时目录。'
  }
  $copyResult = Invoke-Adb -Arguments @('shell', 'run-as', $DebugPackage, 'cp', $script:RemoteInputPath, "files/$($script:PrivateInputFileName)") -AllowFailure
  if ($copyResult.exitCode -ne 0) {
    throw '无法将原版 Legado 测试输入转入应用私有目录。'
  }
  $chmodResult = Invoke-Adb -Arguments @('shell', 'run-as', $DebugPackage, 'chmod', '600', "files/$($script:PrivateInputFileName)") -AllowFailure
  if ($chmodResult.exitCode -ne 0) {
    throw '无法保护原版 Legado 测试私有输入文件。'
  }
}

function Get-LiveReferenceTraces {
  # Android truncates a single Log.i payload around the logger buffer boundary.
  # The test-only reference runner therefore emits numbered raw-log fragments.
  # A trace is admitted only when every fragment is present, ordered, and forms
  # valid JSON.  Partial fragments must remain indistinguishable from a missing
  # reference trace, never from a completed reference execution.
  $logResult = Invoke-Adb -Arguments @('logcat', '-d', '-v', 'raw', '-s', 'LegadoLiveReference:I') -AllowFailure
  if ($logResult.exitCode -ne 0) {
    return ,([System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal))
  }
  $lines = @($logResult.output -split "`r?`n")
  return Read-LegadoReferenceTraceRecords -Lines $lines -AttemptIdPattern '^[A-F0-9]{64}/[0-3]$'
}

function Get-ReferenceFailureCategory {
  param([System.Management.Automation.ErrorRecord]$ErrorRecord)
  $message = ''
  if ($null -ne $ErrorRecord.Exception) {
    $message = [string]$ErrorRecord.Exception.Message
  }
  if ($message -match '(?i)run-as|私有输入|临时目录') {
    return 'private_input_transport'
  }
  if ($message -match '(?i)instrumentation|debug 包') {
    return 'reference_instrumentation'
  }
  if ($message -match '(?i)书源包|候选|基线') {
    return 'candidate_preparation'
  }
  return 'reference_runner_other'
}

try {
  if (-not (Test-Path -LiteralPath $AdbPath)) {
    throw 'ADB 不存在。'
  }
  $diagnostic = Read-Stage7Diagnostic
  $safeSources = Get-SafeSourceByHash
  $plans = @()
  $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
  foreach ($record in @($diagnostic.candidateAttemptRecords)) {
    $sourceHash = [string]$record.sourceHash
    $keywordIndex = [int]$record.keywordIndex
    if ($sourceHash -notmatch '^[A-F0-9]{64}$' -or $keywordIndex -lt 0 -or $keywordIndex -ge $script:SearchKeywords.Count) {
      continue
    }
    $attemptKey = "$sourceHash/$keywordIndex"
    if ($seen.Contains($attemptKey) -or -not $safeSources.ContainsKey($sourceHash)) {
      continue
    }
    $seen.Add($attemptKey) | Out-Null
    $plans += [pscustomobject][ordered]@{
      sourceHash = $sourceHash
      keywordIndex = $keywordIndex
      attemptId = $attemptKey
      source = $safeSources[$sourceHash]
      v2Outcome = [string]$record.outcome
      v2TraceState = [string]$record.traceState
    }
    if ($plans.Count -ge $MaximumReferenceAttempts) {
      break
    }
  }
  if ($plans.Count -eq 0) {
    throw '阶段 7 诊断中没有可安全复现的候选。'
  }

  [System.IO.Directory]::CreateDirectory($TempRoot) | Out-Null
  $hostInputPath = Join-Path $TempRoot 'reference-input.json'
  $inputEntries = @()
  foreach ($plan in $plans) {
    $inputEntries += [pscustomobject][ordered]@{
      sourceHash = $plan.sourceHash
      attemptId = $plan.attemptId
      keyword = $script:SearchKeywords[$plan.keywordIndex]
      source = $plan.source
    }
  }
  Write-Utf8Atomic -Path $hostInputPath -Content (ConvertTo-Json -InputObject @($inputEntries) -Depth 100 -Compress)
  Ensure-ReferenceInstrumentation
  Install-ReferenceInput -HostInputPath $hostInputPath
  [void](Invoke-Adb -Arguments @('logcat', '-c') -AllowFailure)
  $instrumentationResult = Invoke-Adb -Arguments @('shell', 'am', 'instrument', '-w', '-r', '-e', 'class', $ReferenceTestClass, '-e', 'liveInputFileName', $PrivateInputFileName, $InstrumentationComponent) -AllowFailure -TimeoutSeconds 900
  if ($instrumentationResult.exitCode -ne 0 -or $instrumentationResult.output -match '(?i)INSTRUMENTATION_FAILED|FAILURES!!!|Process crashed') {
    throw '原版 Legado 同端点 instrumentation 未完成。'
  }
  $referenceTraces = Get-LiveReferenceTraces
  $attemptEvidence = @()
  $referenceComplete = 0
  $referenceCompleteV2Failed = 0
  $bothNotComplete = 0
  foreach ($plan in $plans) {
    $reference = $null
    if ($referenceTraces.ContainsKey($plan.attemptId)) {
      $reference = $referenceTraces[$plan.attemptId]
    }
    $referenceStage = if ($null -eq $reference) { 'missing' } else { [string](Get-ObjectProperty -Object $reference -Name 'stage') }
    $referenceOutcome = if ($null -eq $reference) { 'missing_reference_trace' } else { [string](Get-ObjectProperty -Object $reference -Name 'outcome') }
    $isReferenceComplete = $referenceStage -eq 'content' -and $referenceOutcome -eq 'complete'
    if ($isReferenceComplete) {
      $referenceComplete++
      if ($plan.v2Outcome -ne 'complete') {
        $referenceCompleteV2Failed++
      }
    } else {
      $bothNotComplete++
    }
    $attemptEvidence += [pscustomobject][ordered]@{
      sourceHash = $plan.sourceHash
      keywordIndex = $plan.keywordIndex
      v2Outcome = $plan.v2Outcome
      v2TraceState = $plan.v2TraceState
      referenceStage = $referenceStage
      referenceOutcome = $referenceOutcome
      searchCount = if ($null -eq $reference) { 0 } else { [int](Get-ObjectProperty -Object $reference -Name 'searchCount') }
      tocCount = if ($null -eq $reference) { 0 } else { [int](Get-ObjectProperty -Object $reference -Name 'tocCount') }
      contentLength = if ($null -eq $reference) { 0 } else { [int](Get-ObjectProperty -Object $reference -Name 'contentLength') }
    }
  }
  $evidence = [pscustomobject][ordered]@{
    schemaVersion = 1
    generatedAt = Get-ExecutionTimestamp
    sourcePackageSha256 = $SourcePackageSha256
    legadoCommit = $LegadoCommit
    automation = 'adb_instrumentation_run_as_private_input'
    candidateSelectorVersion = $CandidateSelectorVersion
    keywordSetSha256 = Get-KeywordSetSha256
    attempts = $attemptEvidence
    summary = [pscustomobject][ordered]@{
      requested = $plans.Count
      traceReceived = $referenceTraces.Count
      referenceComplete = $referenceComplete
      referenceCompleteV2Failed = $referenceCompleteV2Failed
      bothNotComplete = $bothNotComplete
    }
  }
  Write-Utf8Atomic -Path $EvidencePath -Content ($evidence | ConvertTo-Json -Depth 8)
  Write-Output "STAGE7A_REFERENCE_COMPLETE requested=$($plans.Count);reference_complete=$referenceComplete;reference_complete_v2_failed=$referenceCompleteV2Failed"
} catch {
  $failureEvidence = [pscustomobject][ordered]@{
    schemaVersion = 1
    generatedAt = Get-ExecutionTimestamp
    sourcePackageSha256 = $SourcePackageSha256
    legadoCommit = $LegadoCommit
    automation = 'adb_instrumentation_run_as_private_input'
    candidateSelectorVersion = $CandidateSelectorVersion
    keywordSetSha256 = Get-KeywordSetSha256
    outcome = 'reference_runner_failed'
    failureCategory = Get-ReferenceFailureCategory -ErrorRecord $_
    attempts = @()
    summary = [pscustomobject][ordered]@{
      requested = $plans.Count
      traceReceived = 0
      referenceComplete = 0
      referenceCompleteV2Failed = 0
      bothNotComplete = 0
    }
  }
  Write-Utf8Atomic -Path $EvidencePath -Content ($failureEvidence | ConvertTo-Json -Depth 6)
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
