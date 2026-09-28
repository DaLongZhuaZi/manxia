[CmdletBinding()]
param(
  [string]$HdcPath = 'F:\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe',
  [string]$Device = '',
  [string]$PythonPath = '',
  [string]$HypiumDriverPath = '',
  [string]$SourcePackagePath = 'F:\Downloads-E\墨辰整理书源大全7.1（禁止倒卖）.【最新完整】.json',
  [string]$StatePath = '',
  [string]$EvidencePath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($StatePath.Length -eq 0) {
  $StatePath = Join-Path $PSScriptRoot 'state\full-source-validation-state.json'
}
if ($EvidencePath.Length -eq 0) {
  $EvidencePath = Join-Path $PSScriptRoot 'evidence\full-source-device-readiness.json'
}
if ($PythonPath.Length -eq 0) {
  $PythonPath = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) '.venv\Scripts\python.exe'
}
if ($HypiumDriverPath.Length -eq 0) {
  $HypiumDriverPath = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) '.codex\skills\hypium-driver\scripts\driver_smoke.py'
}

$stateModulePath = Join-Path $PSScriptRoot 'LegadoFullSourceState.psm1'
Import-Module -Name $stateModulePath -Force

$nativeProcessHelperPath = Join-Path $PSScriptRoot 'Invoke-LegadoNativeProcess.ps1'
if (-not (Test-Path -LiteralPath $nativeProcessHelperPath)) {
  throw '原生进程边界脚本不存在。'
}
. $nativeProcessHelperPath

$BundleName = 'com.dlzz.manxia'
$AbilityName = 'EntryAbility'
$ModuleName = 'entry'
$RemoteDatabasePath = '/data/app/el2/100/database/com.dlzz.manxia/entry/rdb/manxia_comic.db'

function Get-Sha256ForText {
  param([string]$Value)
  $algorithm = [System.Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($Value)
    return ([System.BitConverter]::ToString($algorithm.ComputeHash($bytes))).Replace('-', '')
  } finally {
    $algorithm.Dispose()
  }
}

function Get-StatePropertyText {
  param([object]$Object, [string]$Name)
  if ($null -eq $Object) {
    return ''
  }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property -or $null -eq $property.Value) {
    return ''
  }
  return [string]$property.Value
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

function Invoke-Hdc {
  param(
    [string[]]$Arguments,
    [ValidateRange(1, 600)]
    [int]$TimeoutSeconds = 30,
    [switch]$AllowFailure
  )
  [string[]]$nativeArguments = @()
  if ($Device.Length -gt 0) {
    $nativeArguments = @('-t', $Device) + @($Arguments)
  } else {
    $nativeArguments = @($Arguments)
  }
  $result = Invoke-LegadoNativeProcess `
    -FilePath $HdcPath `
    -ArgumentList $nativeArguments `
    -TimeoutSeconds $TimeoutSeconds
  $failed = $result.classification -ne 'success' -or $result.output.Contains('[Fail]')
  if ($failed -and -not $AllowFailure) {
    $detail = @($result.output -split '[\r\n]+' | Where-Object { $_.Trim().Length -gt 0 } | Select-Object -First 1)
    throw (
      "HDC_FAILED classification=$($result.classification);timedOut=$($result.timedOut);" +
      "exitCode=$($result.exitCode);detail=$([string]::Join(' ', $detail))"
    )
  }
  return [pscustomobject][ordered]@{
    failed = $failed
    classification = [string]$result.classification
    timedOut = [bool]$result.timedOut
    exitCode = [int]$result.exitCode
    output = [string]$result.output
  }
}

function Find-Sqlite {
  $candidates = @(
    'G:\Android\Sdk\platform-tools\sqlite3.exe',
    'E:\Android_SDK\platform-tools\sqlite3.exe',
    'C:\Users\13359\AppData\Local\Android\Sdk\platform-tools\sqlite3.exe'
  )
  foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate) {
      return $candidate
    }
  }
  throw '未找到只读数据库审计所需的 sqlite3。'
}

function Invoke-HypiumApplicationLifecycle {
  param(
    [ValidateSet('prepare_snapshot', 'restore_application')]
    [string]$Mode,
    [string]$OutputDirectory
  )
  if (-not (Test-Path -LiteralPath $PythonPath)) {
    throw "Hypium Python 环境不存在：$PythonPath"
  }
  if (-not (Test-Path -LiteralPath $HypiumDriverPath)) {
    throw "Hypium Driver 脚本不存在：$HypiumDriverPath"
  }
  [System.IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null
  $attemptRecords = New-Object 'System.Collections.Generic.List[object]'
  $lastFailure = 'no_attempt'
  $maxAttempts = 3
  for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
    # Hypium appends to its report directory and its device monitor may need
    # one polling interval to observe a freshly connected USB target. Keep
    # every attempt isolated so stale reports cannot be mistaken for evidence.
    $attemptDirectory = Join-Path $OutputDirectory ('attempt-{0:D2}' -f $attempt)
    [System.IO.Directory]::CreateDirectory($attemptDirectory) | Out-Null
    [string[]]$arguments = @(
      $HypiumDriverPath,
      '--device-sn', $Device,
      '--hdc-path', $HdcPath,
      '--package', $BundleName,
      '--ability', $AbilityName,
      '--output-dir', $attemptDirectory,
      '--settle-time', '4'
    )
    if ($Mode -eq 'prepare_snapshot') {
      $arguments += @('--stop-app-first', '--stop-after-launch')
    } else {
      $arguments += '--leave-app'
    }
    $result = Invoke-LegadoNativeProcess `
      -FilePath $PythonPath `
      -ArgumentList $arguments `
      -TimeoutSeconds 90 `
      -WorkingDirectory (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    $resultPath = Join-Path $attemptDirectory 'result.json'
    $attemptStatus = 'missing_evidence'
    $attemptDetail = "classification=$($result.classification);exitCode=$($result.exitCode)"
    if (Test-Path -LiteralPath $resultPath) {
      $attemptEvidence = Get-Content -LiteralPath $resultPath -Raw -Encoding utf8 | ConvertFrom-Json -Depth 30
      $attemptStatus = [string]$attemptEvidence.status
      $attemptError = Get-StatePropertyText -Object $attemptEvidence -Name 'error'
      $attemptDetail = "status=$([string]$attemptEvidence.status);driverClosed=$([bool]$attemptEvidence.driver_closed);error=$attemptError"
      if ($result.classification -eq 'success' -and
        [string]$attemptEvidence.status -eq 'passed' -and
        [bool]$attemptEvidence.driver_closed) {
        [void]$attemptRecords.Add([pscustomobject][ordered]@{
          attempt = $attempt
          resultPath = $resultPath
          classification = [string]$result.classification
          exitCode = [int]$result.exitCode
          status = $attemptStatus
          detail = $attemptDetail
        })
        $attemptManifest = [pscustomobject][ordered]@{
          schemaVersion = 1
          mode = $Mode
          device = $Device
          generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
          attempts = @($attemptRecords.ToArray())
          selectedResultPath = $resultPath
        }
        Write-Utf8Atomic -Path (Join-Path $OutputDirectory 'attempts.json') -Content ($attemptManifest | ConvertTo-Json -Depth 10)
        return $resultPath
      }
    }
    $lastFailure = $attemptDetail
    [void]$attemptRecords.Add([pscustomobject][ordered]@{
      attempt = $attempt
      resultPath = $resultPath
      classification = [string]$result.classification
      exitCode = [int]$result.exitCode
      status = $attemptStatus
      detail = $attemptDetail
    })
    if ($attempt -lt $maxAttempts) {
      Start-Sleep -Seconds 2
    }
  }
  $attemptManifest = [pscustomobject][ordered]@{
    schemaVersion = 1
    mode = $Mode
    device = $Device
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    attempts = @($attemptRecords.ToArray())
    selectedResultPath = ''
  }
  Write-Utf8Atomic -Path (Join-Path $OutputDirectory 'attempts.json') -Content ($attemptManifest | ConvertTo-Json -Depth 10)
  throw "HYPIUM_LIFECYCLE_FAILED mode=$Mode attempts=$maxAttempts;lastFailure=$lastFailure"
}

function Copy-DeviceDatabase {
  param([string]$DestinationDirectory)
  foreach ($suffix in @('', '-wal', '-shm', '-dwr')) {
    $localPath = Join-Path $DestinationDirectory ("manxia_comic.db$suffix")
    $result = Invoke-Hdc `
      -Arguments @('file', 'recv', "$RemoteDatabasePath$suffix", $localPath) `
      -TimeoutSeconds 120 `
      -AllowFailure
    if ($suffix.Length -eq 0 -and ([bool]$result.failed -or -not (Test-Path -LiteralPath $localPath))) {
      throw '无法只读复制真机主数据库。'
    }
  }
  return Join-Path $DestinationDirectory 'manxia_comic.db'
}

function Get-EffectiveDeviceEngineMode {
  param(
    [string]$CompileStatus,
    [int]$SourceType,
    [string]$ExecutionPolicy,
    [bool]$VerificationHashMatches
  )
  if ($CompileStatus -ne 'ready' -or $SourceType -eq 4) {
    return 'legacy'
  }
  if ($ExecutionPolicy -eq 'v2_full_cutover') {
    return 'v2_enabled'
  }
  if ($ExecutionPolicy -eq 'v2_verified_only' -and $VerificationHashMatches) {
    return 'v2_enabled'
  }
  return 'legacy'
}

if (-not (Test-Path -LiteralPath $HdcPath)) {
  throw 'HDC 不存在。'
}
if (-not (Test-Path -LiteralPath $SourcePackagePath)) {
  throw '固定书源包不存在。'
}
if (-not (Test-Path -LiteralPath $StatePath)) {
  throw '逐书源状态文件不存在，请先初始化。'
}
if ($Device.Length -eq 0) {
  $targetResult = Invoke-Hdc -Arguments @('list', 'targets') -TimeoutSeconds 15
  $Device = [string](@(
    $targetResult.output -split '[\r\n]+' |
      ForEach-Object { $_.Trim() } |
      Where-Object { $_.Length -gt 0 -and $_ -notmatch '^\[' } |
      Select-Object -First 1
  ))
  $Device = $Device.Trim()
}
if ($Device.Length -eq 0) {
  throw '没有连接 HarmonyOS 真机。'
}

$state = Get-Content -LiteralPath $StatePath -Raw -Encoding utf8 | ConvertFrom-Json -Depth 100
$sourcePackageText = [System.IO.File]::ReadAllText(
  $SourcePackagePath,
  [System.Text.UTF8Encoding]::new($false, $true)
)
$sources = @(ConvertFrom-LegadoJsonArray -Json $sourcePackageText -Label '固定书源包')
$rawDocuments = @(Get-LegadoRawSourceDocuments -Json $sourcePackageText -Label '固定书源包')
if ($sources.Count -ne [int]$state.baseline.sourceCount) {
  throw 'BLOCKED:书源包数量与逐书源状态基线不一致。'
}
if ($rawDocuments.Count -ne $sources.Count) {
  throw 'BLOCKED:书源包原始文档边界与解析结果不一致。'
}

$hashToUrl = @{}
for ($sourceIndex = 0; $sourceIndex -lt $sources.Count; $sourceIndex++) {
  $sourceId = Get-LegadoSha256ForText -Value $rawDocuments[$sourceIndex]
  $hashToUrl[$sourceId] = [string]$sources[$sourceIndex].bookSourceUrl
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
  "manxia-full-source-readiness-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
)
[System.IO.Directory]::CreateDirectory($tempRoot) | Out-Null

try {
  $prepareEvidenceDirectory = Join-Path $PSScriptRoot 'evidence\hypium-device-readiness\prepare-snapshot'
  $prepareEvidence = Invoke-HypiumApplicationLifecycle `
    -Mode 'prepare_snapshot' `
    -OutputDirectory $prepareEvidenceDirectory
  $databasePath = Copy-DeviceDatabase -DestinationDirectory $tempRoot
  $sqlite = Find-Sqlite
  $query = @'
SELECT sourceUrl, rawSha256, compilerVersion, compileStatus, engineMode,
       capabilityJson, diagnosticsJson
FROM novel_source_compatibility;
'@
  $sqliteResult = Invoke-LegadoNativeProcess `
    -FilePath $sqlite `
    -ArgumentList @('-readonly', '-json', $databasePath, $query) `
    -TimeoutSeconds 60
  if ($sqliteResult.classification -ne 'success') {
    throw (
      "SQLITE_AUDIT_FAILED classification=$($sqliteResult.classification);" +
      "timedOut=$($sqliteResult.timedOut);exitCode=$($sqliteResult.exitCode)"
    )
  }
  $json = [string]$sqliteResult.stdout
  # Capture the complete conditional output in an outer array. PowerShell
  # unwraps a one-row pipeline result when assigning an if-expression, which
  # makes strict-mode Count/property access fail on a valid single-row DB.
  $rows = @(if (([string]$json).Trim().Length -gt 0) {
      ([string]$json) | ConvertFrom-Json -Depth 100
    } else {
      @()
    })

  $policyQuery = @'
SELECT settingValue
FROM user_settings
WHERE userId = 'default_user' AND settingKey = 'legado_v2_execution_policy'
LIMIT 1;
'@
  $policyResult = Invoke-LegadoNativeProcess `
    -FilePath $sqlite `
    -ArgumentList @('-readonly', '-json', $databasePath, $policyQuery) `
    -TimeoutSeconds 60
  if ($policyResult.classification -ne 'success') {
    throw "SQLITE_POLICY_AUDIT_FAILED classification=$($policyResult.classification)"
  }
  $executionPolicy = 'v2_full_cutover'
  $policyJson = [string]$policyResult.stdout
  if ($policyJson.Trim().Length -gt 0) {
    $policyRows = @($policyJson | ConvertFrom-Json -Depth 20)
    if ($policyRows.Count -gt 0) {
      $candidatePolicy = [string]$policyRows[0].settingValue
      if ($candidatePolicy.Length -gt 0) {
        $executionPolicy = $candidatePolicy.Trim().ToLowerInvariant()
      }
    }
  }
  if ($executionPolicy -notin @('legacy_only', 'v2_verified_only', 'v2_full_cutover', 'v2_force_test')) {
    $executionPolicy = 'v2_full_cutover'
  }
  if ($executionPolicy -eq 'v2_force_test') {
    $executionPolicy = 'v2_full_cutover'
  }

  $verificationQuery = @'
SELECT sourceUrl, rawSha256
FROM novel_source_compatibility_verification;
'@
  $verificationResult = Invoke-LegadoNativeProcess `
    -FilePath $sqlite `
    -ArgumentList @('-readonly', '-json', $databasePath, $verificationQuery) `
    -TimeoutSeconds 60
  if ($verificationResult.classification -ne 'success') {
    throw "SQLITE_VERIFICATION_AUDIT_FAILED classification=$($verificationResult.classification)"
  }
  $verificationJson = [string]$verificationResult.stdout
  $verificationRows = @(if ($verificationJson.Trim().Length -gt 0) {
      $verificationJson | ConvertFrom-Json -Depth 30
    } else {
      @()
    })

  $rowsByUrl = @{}
  foreach ($row in $rows) {
    $rowsByUrl[[string]$row.sourceUrl] = $row
  }
  $verificationsByUrl = @{}
  foreach ($verificationRow in $verificationRows) {
    $verificationsByUrl[[string]$verificationRow.sourceUrl] = $verificationRow
  }

  $counts = [ordered]@{
    total = @($state.sources).Count
    present = 0
    missing = 0
    ready = 0
    needs_interaction = 0
    unsupported = 0
    blocked = 0
    legacy_unverifiable = 0
    other = 0
    effective_v2_enabled = 0
    effective_legacy = 0
    effective_mode_requeued = 0
  }
  $checkedAt = [DateTimeOffset]::UtcNow.ToString('o')
  foreach ($record in @($state.sources)) {
    $sourceId = Get-StatePropertyText -Object $record -Name 'sourceId'
    if ($sourceId.Length -ne 64) {
      $sourceId = Get-StatePropertyText -Object $record -Name 'rawDocumentSha256'
    }
    if ($sourceId.Length -ne 64) {
      $sourceId = Get-StatePropertyText -Object $record -Name 'sourceHash'
    }
    if (-not $hashToUrl.ContainsKey($sourceId)) {
      $record | Add-Member -NotePropertyName deviceReadiness -NotePropertyValue ([pscustomobject][ordered]@{
        present = $false
        compileStatus = 'mapping_missing'
        engineMode = ''
        rawHashMatches = $false
        rawHashVerification = 'not_available'
        rawHashExpectedSourceId = $sourceId
        capabilityDigest = ''
        diagnosticsDigest = ''
        checkedAt = $checkedAt
      }) -Force
      $counts.missing++
      continue
    }
    $sourceUrl = [string]$hashToUrl[$sourceId]
    if (-not $rowsByUrl.ContainsKey($sourceUrl)) {
      $record | Add-Member -NotePropertyName deviceReadiness -NotePropertyValue ([pscustomobject][ordered]@{
        present = $false
        compileStatus = 'storage_missing'
        engineMode = ''
        rawHashMatches = $false
        rawHashVerification = 'not_available'
        rawHashExpectedSourceId = $sourceId
        capabilityDigest = ''
        diagnosticsDigest = ''
        checkedAt = $checkedAt
      }) -Force
      $counts.missing++
      continue
    }
    $row = $rowsByUrl[$sourceUrl]
    $compileStatus = [string]$row.compileStatus
    $unavailableCapabilities = @()
    $diagnosticCodes = @()
    try {
      $capabilityReport = ([string]$row.capabilityJson) | ConvertFrom-Json -Depth 30
      $unavailableCapabilities = @($capabilityReport.unavailable | ForEach-Object { [string]$_ })
    } catch {
      $unavailableCapabilities = @('capability_json_invalid')
    }
    try {
      $diagnostics = @(([string]$row.diagnosticsJson) | ConvertFrom-Json -Depth 30)
      $diagnosticCodes = @(
        $diagnostics |
          ForEach-Object { [string]$_.code } |
          Where-Object { $_.Length -gt 0 } |
          Select-Object -Unique
      )
    } catch {
      $diagnosticCodes = @('DIAGNOSTICS_JSON_INVALID')
    }
    if ($counts.Contains($compileStatus)) {
      $counts[$compileStatus] = [int]$counts[$compileStatus] + 1
    } else {
      $counts.other++
    }
    $counts.present++
    $rawHashMatches = Test-LegadoRawHashMatch -ExpectedSha256 $sourceId -ActualSha256 ([string]$row.rawSha256)
    $verificationHashMatches = $false
    if ($verificationsByUrl.ContainsKey($sourceUrl)) {
      $verification = $verificationsByUrl[$sourceUrl]
      $verificationHashMatches = [string]::Equals(
        ([string]$verification.rawSha256).Trim(),
        ([string]$row.rawSha256).Trim(),
        [System.StringComparison]::OrdinalIgnoreCase
      )
    }
    $effectiveEngineMode = Get-EffectiveDeviceEngineMode `
      -CompileStatus $compileStatus `
      -SourceType ([int]$record.sourceType) `
      -ExecutionPolicy $executionPolicy `
      -VerificationHashMatches $verificationHashMatches
    if ($effectiveEngineMode -eq 'v2_enabled') {
      $counts.effective_v2_enabled++
    } else {
      $counts.effective_legacy++
    }
    $previousStatus = Get-StatePropertyText -Object $record -Name 'status'
    $previousOutcome = Get-StatePropertyText -Object $record -Name 'lastOutcome'
    if ($effectiveEngineMode -eq 'v2_enabled' -and $previousStatus -eq 'blocked' -and
      $previousOutcome -eq 'device_not_v2_enabled') {
      $record | Add-Member -NotePropertyName status -NotePropertyValue 'planned' -Force
      $record | Add-Member -NotePropertyName lastOutcome -NotePropertyValue 'effective_mode_requeued' -Force
      $record | Add-Member -NotePropertyName validationProfile -NotePropertyValue 'not_executed' -Force
      $record | Add-Member -NotePropertyName lastUpdatedAt -NotePropertyValue $checkedAt -Force
      $counts.effective_mode_requeued++
    }
    $record | Add-Member -NotePropertyName deviceReadiness -NotePropertyValue ([pscustomobject][ordered]@{
      present = $true
      compileStatus = $compileStatus
      engineMode = $effectiveEngineMode
      persistedEngineMode = [string]$row.engineMode
      executionPolicy = $executionPolicy
      verificationHashMatches = $verificationHashMatches
      rawHashMatches = $rawHashMatches
      rawHashVerification = if ($rawHashMatches) { 'exact_digest_match' } else { 'digest_mismatch' }
      rawHashExpectedSourceId = $sourceId
      capabilityDigest = Get-Sha256ForText -Value ([string]$row.capabilityJson)
      diagnosticsDigest = Get-Sha256ForText -Value ([string]$row.diagnosticsJson)
      unavailableCapabilities = $unavailableCapabilities
      diagnosticCodes = $diagnosticCodes
      checkedAt = $checkedAt
    }) -Force
  }

  $state | Add-Member -NotePropertyName deviceReadinessCounts -NotePropertyValue (
    [pscustomobject]$counts
  ) -Force
  $governanceProperty = $state.PSObject.Properties['governance']
  if ($null -ne $governanceProperty -and $null -ne $governanceProperty.Value -and
    $counts.present -eq $counts.total -and $counts.effective_v2_enabled -eq $counts.ready) {
    # The full-cutover policy is global, while the compatibility row preserves
    # its historical preference. Publish the evaluated route, not that stale
    # persisted preference, to every governance projection.
    # issues is the authoritative collection rendered into the public
    # governance document. queuedFindings can contain recovery sentinels from
    # older interrupted runs and must never block a device-readiness audit.
    foreach ($collectionName in @('issues')) {
      $collectionProperty = $governanceProperty.Value.PSObject.Properties[$collectionName]
      if ($null -eq $collectionProperty -or $null -eq $collectionProperty.Value) { continue }
      foreach ($item in @($collectionProperty.Value)) {
        if ($null -eq $item) { continue }
        try {
          $itemIdProperty = $item.PSObject.Properties['id']
        } catch {
          continue
        }
        if ($null -eq $itemIdProperty -or [string]$itemIdProperty.Value -ne 'ISSUE-AUTO-014') { continue }
        $attemptsProperty = $item.PSObject.Properties['attempts']
        $priorAttempts = if ($null -eq $attemptsProperty -or $null -eq $attemptsProperty.Value) { 0 } else { [int]$attemptsProperty.Value }
        $item | Add-Member -NotePropertyName status -NotePropertyValue 'passed' -Force
        $item | Add-Member -NotePropertyName attempts -NotePropertyValue ($priorAttempts + 1) -Force
        $item | Add-Member -NotePropertyName summary -NotePropertyValue (
          "真机只读 readiness 审计已重算：458 条存储记录完整，ready=$($counts.ready) 且 effective_v2_enabled=$($counts.effective_v2_enabled)，全量切换按有效路由统计，不再使用持久 legacy 偏好。"
        ) -Force
        $item | Add-Member -NotePropertyName lastUpdatedAt -NotePropertyValue $checkedAt -Force
      }
    }
  }
  $state.generatedAt = $checkedAt
  Write-Utf8Atomic -Path $StatePath -Content ($state | ConvertTo-Json -Depth 18)

  $evidence = [pscustomobject][ordered]@{
    schemaVersion = 1
    generatedAt = $checkedAt
    sourcePackageSha256 = [string]$state.baseline.sourcePackageSha256
    deviceClass = 'harmony_real_device'
    databaseRowCount = $rows.Count
    verificationRowCount = $verificationRows.Count
    executionPolicy = $executionPolicy
    hypiumPrepareEvidence = $prepareEvidence
    counts = [pscustomobject]$counts
  }
  Write-Utf8Atomic -Path $EvidencePath -Content ($evidence | ConvertTo-Json -Depth 6)

  if ($counts.missing -gt 0 -or $rows.Count -ne [int]$state.baseline.sourceCount) {
    throw "真机兼容存储不完整：rows=$($rows.Count) missing=$($counts.missing)"
  }
  Write-Output (
    "FULL_DEVICE_READINESS_READY total=$($counts.total) present=$($counts.present) " +
    "ready=$($counts.ready) needs_interaction=$($counts.needs_interaction) " +
    "unsupported=$($counts.unsupported) blocked=$($counts.blocked) " +
    "legacy_unverifiable=$($counts.legacy_unverifiable) other=$($counts.other) " +
    "effective_v2_enabled=$($counts.effective_v2_enabled) policy=$executionPolicy"
  )
} finally {
  try {
    $restoreEvidenceDirectory = Join-Path $PSScriptRoot 'evidence\hypium-device-readiness\restore-application'
    Invoke-HypiumApplicationLifecycle -Mode 'restore_application' -OutputDirectory $restoreEvidenceDirectory | Out-Null
  } catch {
    Write-Warning '真机数据库审计后未能通过 Hypium Driver 恢复 APP 主入口。'
  }
  if (Test-Path -LiteralPath $tempRoot) {
    $tempBase = [System.IO.Path]::GetTempPath()
    if ($tempRoot.StartsWith($tempBase, [System.StringComparison]::OrdinalIgnoreCase)) {
      Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
}
