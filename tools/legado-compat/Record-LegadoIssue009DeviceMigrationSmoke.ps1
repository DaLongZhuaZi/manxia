[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$HdcPath = 'F:\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe',
  [string]$Device = '',
  [int]$StartupWaitSeconds = 5,
  [string]$EvidencePath = 'tools/legado-compat/evidence/r4-build-device-20260809-r3/issue-009-migration-smoke.json',
  [string]$FilteredLogPath = 'tools/legado-compat/evidence/r4-build-device-20260809-r3/issue-009-migration-smoke-filtered.log'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$sourceCount = 458
$sourceHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$stateRelativePath = 'tools/legado-compat/state/full-source-validation-state.json'
$issueId = 'ISSUE-COMPAT-009'

function Get-RepositoryPath([string]$RelativePath) {
  if ([System.IO.Path]::IsPathRooted($RelativePath)) { return $RelativePath }
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictJson([string]$RelativePath) {
  $path = Get-RepositoryPath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing JSON: $RelativePath" }
  return ($strictUtf8.GetString([System.IO.File]::ReadAllBytes($path)) | ConvertFrom-Json)
}

function Set-PropertyValue([object]$Object, [string]$Name, [object]$Value) {
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force }
  else { $property.Value = $Value }
}

function Add-UniqueEvidence([object]$Issue, [string[]]$Paths) {
  $values = New-Object 'System.Collections.Generic.List[string]'
  $property = $Issue.PSObject.Properties['evidencePaths']
  if ($null -ne $property -and $null -ne $property.Value) {
    foreach ($value in @($property.Value)) {
      $normalized = ([string]$value).Replace('/', '\')
      if ($normalized.Length -gt 0 -and -not $values.Contains($normalized)) { [void]$values.Add($normalized) }
    }
  }
  foreach ($value in $Paths) {
    $normalized = ([string]$value).Replace('/', '\')
    if ($normalized.Length -gt 0 -and -not $values.Contains($normalized)) { [void]$values.Add($normalized) }
  }
  Set-PropertyValue $Issue 'evidencePaths' @($values.ToArray())
}

function Write-AtomicText([string]$RelativePath, [string]$Content) {
  $path = Get-RepositoryPath $RelativePath
  [System.IO.Directory]::CreateDirectory((Split-Path -Parent $path)) | Out-Null
  $temporary = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporary, $Content, $noBomUtf8)
    Move-Item -LiteralPath $temporary -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) }
  }
}

function Write-AtomicJson([string]$RelativePath, [object]$Value) {
  Write-AtomicText -RelativePath $RelativePath -Content ($Value | ConvertTo-Json -Depth 60)
}

function Invoke-Hdc([string[]]$Arguments, [int]$TimeoutSeconds = 30, [switch]$AllowFailure) {
  $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
  $startInfo.FileName = $HdcPath
  $startInfo.UseShellExecute = $false
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  foreach ($argument in $Arguments) { [void]$startInfo.ArgumentList.Add($argument) }
  $process = [System.Diagnostics.Process]::new()
  $process.StartInfo = $startInfo
  if (-not $process.Start()) { throw 'HDC_PROCESS_START_FAILED' }
  try {
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
      try { $process.Kill() } catch { }
      if (-not $AllowFailure) { throw "HDC_TIMEOUT:$([string]::Join(' ', $Arguments))" }
      return [pscustomobject][ordered]@{ exitCode = -1; output = ''; timedOut = $true }
    }
    $output = $process.StandardOutput.ReadToEnd() + $process.StandardError.ReadToEnd()
    if ($process.ExitCode -ne 0 -and -not $AllowFailure) {
      throw "HDC_FAILED exit=$($process.ExitCode):$output"
    }
    return [pscustomobject][ordered]@{ exitCode = $process.ExitCode; output = $output; timedOut = $false }
  } finally {
    $process.Dispose()
  }
}

function Redact-HilogLine([string]$Line) {
  $redacted = $Line
  $redacted = [regex]::Replace($redacted, '(?i)https?://[^\s]+', '[URL]')
  $redacted = [regex]::Replace($redacted, '(?i)(cookie|authorization|set-cookie|token|password|账号|密码)\s*[:=][^,;\s]+', '$1=[REDACTED]')
  $redacted = [regex]::Replace($redacted, 'id_[A-Za-z0-9_]+', '[ID]')
  return $redacted
}

if (-not (Test-Path -LiteralPath $HdcPath -PathType Leaf)) { throw 'HDC_PATH_MISSING' }
$state = Read-StrictJson $stateRelativePath
if ([int]$state.baseline.sourceCount -ne $sourceCount -or
    [string]$state.baseline.sourcePackageSha256 -ne $sourceHash -or
    [string]$state.baseline.legadoCommit -ne $legadoCommit) {
  throw 'ISSUE009_DEVICE_SMOKE_BLOCKED: frozen baseline drifted.'
}
if ($Device.Length -eq 0) {
  $targets = Invoke-Hdc -Arguments @('list', 'targets') -TimeoutSeconds 15
  $Device = [string](@($targets.output -split '[\r\n]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^[^\s]+$' } | Select-Object -First 1))
}
if ([string]::IsNullOrWhiteSpace($Device)) { throw 'ISSUE009_DEVICE_SMOKE_BLOCKED: no connected device.' }

$start = [DateTimeOffset]::UtcNow
$startResult = $null
$pidOutput = ''
$hilogPidFilter = ''
$logOutput = ''
$cleanupError = ''
try {
  [void](Invoke-Hdc -Arguments @('-t', $Device, 'shell', 'aa', 'force-stop', 'com.dlzz.manxia') -TimeoutSeconds 30 -AllowFailure)
  [void](Invoke-Hdc -Arguments @('-t', $Device, 'shell', 'hilog', '-r') -TimeoutSeconds 30)
  $startResult = Invoke-Hdc -Arguments @('-t', $Device, 'shell', 'aa', 'start', '-a', 'EntryAbility', '-b', 'com.dlzz.manxia', '-m', 'entry') -TimeoutSeconds 30
  Start-Sleep -Seconds $StartupWaitSeconds
  $pidOutput = (Invoke-Hdc -Arguments @('-t', $Device, 'shell', 'pidof', 'com.dlzz.manxia') -TimeoutSeconds 15 -AllowFailure).output.Trim()
  $pidTokens = @(
    $pidOutput -split '\s+' |
      Where-Object { $_ -match '^\d+$' } |
      Select-Object -First 5
  )
  $hilogPidFilter = $pidTokens -join ','
  if ($hilogPidFilter.Length -gt 0) {
    # A full hilog snapshot can exceed the synchronous process pipe and make
    # WaitForExit block until the harness kills it.  Query only the app PIDs
    # and the initialization/migration terms needed by this smoke gate.
    $hilogPattern = '数据库初始化\|小说数据库初始化\|duplicate\|重复列\|migration\|迁移'
    $logOutput = (Invoke-Hdc -Arguments @(
        '-t', $Device, 'shell', 'hilog', '-x', '-P', $hilogPidFilter, '-e', $hilogPattern
      ) -TimeoutSeconds 60 -AllowFailure).output
  }
} finally {
  try { [void](Invoke-Hdc -Arguments @('-t', $Device, 'shell', 'aa', 'force-stop', 'com.dlzz.manxia') -TimeoutSeconds 30 -AllowFailure) }
  catch { $cleanupError = $_.Exception.Message }
}

$relevant = @(
  $logOutput -split '[\r\n]+' |
    Where-Object { $_ -match '(?i)com\.dlzz\.manxia' -and $_ -match '(?i)DatabaseManager|NovelDataManager|AbsResultSet|AbsSharedResultSet|duplicate\s+column|重复列|数据库初始化|小说数据库初始化|migration|迁移|SQLite|RdbStore' } |
    ForEach-Object { Redact-HilogLine -Line ([string]$_) }
)
$duplicateMatches = @($relevant | Where-Object { $_ -match '(?i)duplicate\s+column|duplicate-column|重复列' })
$migrationFailureMatches = @($relevant | Where-Object { $_ -match '(?i)数据库初始化失败|小说数据库初始化失败|migration.{0,20}(fail|error)|迁移.{0,20}(失败|错误)' })
$frameworkErrorMatches = @($relevant | Where-Object { $_ -match '(?i)\sE\s.*(AbsResultSet|AbsSharedResultSet|RdbStore)' })
$rawLogLineCount = @($logOutput -split '[\r\n]+' | Where-Object { $_.Trim().Length -gt 0 }).Count
$packageLogLineCount = @($logOutput -split '[\r\n]+' | Where-Object { $_ -match '(?i)com\.dlzz\.manxia' }).Count
$sanitizedLog = [string]::Join([Environment]::NewLine, $relevant)
if ($sanitizedLog.Length -gt 0) { $sanitizedLog += [Environment]::NewLine }
Write-AtomicText -RelativePath $FilteredLogPath -Content $sanitizedLog
$logSha256 = (Get-FileHash -LiteralPath (Get-RepositoryPath $FilteredLogPath) -Algorithm SHA256).Hash.ToUpperInvariant()
$logVisible = $relevant.Count -gt 0
$frameworkStatement = if ($frameworkErrorMatches.Count -gt 0) {
  "观察到 $($frameworkErrorMatches.Count) 条 AbsResultSet/框架数据库错误并单独计数"
} else {
  '未观察到 AbsResultSet/框架数据库错误'
}
$status = if ($startResult.exitCode -eq 0 -and $pidOutput.Length -gt 0 -and $logVisible -and $duplicateMatches.Count -eq 0 -and $migrationFailureMatches.Count -eq 0 -and $cleanupError.Length -eq 0) { 'passed' } else { 'blocked' }
$evidence = [ordered]@{
  schemaVersion = 1
  kind = 'legado_issue_009_device_migration_smoke'
  status = $status
  issueId = $issueId
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [ordered]@{ sourceCount = $sourceCount; sourcePackageSha256 = $sourceHash; legadoCommit = $legadoCommit }
  device = [ordered]@{ deviceSn = $Device; package = 'com.dlzz.manxia'; ability = 'EntryAbility' }
  actions = @('force_stop_before_start', 'hilog_reset', 'aa_start', "wait_${StartupWaitSeconds}s", 'pidof', 'hilog_export_pid_filtered', 'force_stop_after_capture')
  observations = [ordered]@{
    startExitCode = [int]$startResult.exitCode
    processObserved = $pidOutput.Length -gt 0
    hilogCaptureMode = if ($hilogPidFilter.Length -gt 0) { 'pid_filtered_keyword_query' } else { 'not_attempted_without_pid' }
    hilogPidFilter = $hilogPidFilter
    hilogQuery = '数据库初始化|小说数据库初始化|duplicate|重复列|migration|迁移'
    rawHilogLineCount = $rawLogLineCount
    packageHilogLineCount = $packageLogLineCount
    logVisibility = if ($logVisible) { 'relevant_lines_observed' } else { 'no_relevant_lines_observed' }
    duplicateColumnMatchCount = $duplicateMatches.Count
    migrationFailureMatchCount = $migrationFailureMatches.Count
    frameworkDatabaseErrorMatchCount = $frameworkErrorMatches.Count
    relevantSanitizedLineCount = $relevant.Count
    filteredLogPath = $FilteredLogPath
    filteredLogSha256 = $logSha256
    cleanupError = $cleanupError
  }
  semanticMatchAllowed = $false
  runtimeActionsPerformed = @('device_startup_smoke_only')
  statement = if ($logVisible) { "受控健康重启观察到进程存活且可定位日志中没有 duplicate-column、数据库初始化失败或迁移失败匹配；$frameworkStatement，不能作为迁移失败或语义兼容通过。" } else { '受控健康重启观察到进程存活，但本次导出的 hilog 没有可定位的漫匣数据库/迁移行；日志可见性不足，不能判定没有 duplicate-column 或迁移失败。' }
  nextAction = if ($logVisible) { '009 仍保持 verifying；还需确定性验证真实迁移失败会阻断初始化，且不得把健康重启扩大为 458 条语义通过。' } else { '009 仍保持 verifying；先修复/扩大受控日志采集的可见性，再验证迁移失败传播；不得用空日志关闭问题。' }
}
$issue = @($state.governance.issues | Where-Object { [string]$_.id -eq $issueId }) | Select-Object -First 1
if ($null -eq $issue) { throw 'ISSUE009_DEVICE_SMOKE_BLOCKED: issue missing.' }
Add-UniqueEvidence -Issue $issue -Paths @($EvidencePath, $FilteredLogPath)
Set-PropertyValue $issue 'status' 'verifying'
$issueSummary = if ($logVisible) {
  "数据库迁移源码静态闭合；241 通用设备门禁已通过。受控健康重启进程存活且可定位日志未出现 duplicate-column/数据库初始化失败/迁移失败匹配；$frameworkStatement，真实迁移失败传播仍未证明，保持 verifying。"
} else {
  '数据库迁移源码静态闭合；241 通用设备门禁已通过。受控健康重启进程存活，但本次 hilog 没有可定位的漫匣数据库/迁移行，不能把空日志当作无错误证据，保持 verifying。'
}
Set-PropertyValue $issue 'summary' $issueSummary
Set-PropertyValue $issue 'lastUpdatedAt' $evidence.generatedAt
Set-PropertyValue $state.governance 'activeIssueId' $issueId
Set-PropertyValue $state.governance 'currentSourceClosureBoundary' $issueId
Set-PropertyValue $state.governance 'semanticMatchAllowed' $false
Set-PropertyValue $state.governance 'lastIssue009DeviceSmokeEvidencePath' $EvidencePath
Set-PropertyValue $state 'updatedAt' $evidence.generatedAt
Import-Module -Name (Get-RepositoryPath 'tools/legado-compat/LegadoFullSourceState.psm1') -Force
Sync-LegadoStateDerivedFields -State $state
Write-LegadoStateCheckpoint -Path (Get-RepositoryPath $stateRelativePath) -State $state -Depth 80
Write-AtomicJson -RelativePath $EvidencePath -Value $evidence

$refreshScript = Get-RepositoryPath 'tools/legado-compat/Invoke-LegadoCompatibility.ps1'
& pwsh -NoLogo -NoProfile -NonInteractive -File $refreshScript -RefreshDocumentsOnly | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'ISSUE009_DEVICE_SMOKE_BLOCKED: document refresh failed.' }

$evidence | ConvertTo-Json -Depth 20
