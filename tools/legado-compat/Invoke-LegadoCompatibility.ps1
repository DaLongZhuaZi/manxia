[CmdletBinding()]
param(
  [ValidateSet('all', 'stage0', 'stage1', 'stage2', 'stage3', 'stage4', 'stage5', 'stage6', 'stage7', 'stage7a', 'stage8')]
  [string]$OnlyStage = 'all',
  [switch]$SkipAndroid,
  [switch]$SkipHarmony,
  [switch]$RefreshDocumentsOnly,
  [switch]$HarmonyOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:NativeProcessHelperPath = Join-Path $PSScriptRoot 'Invoke-LegadoNativeProcess.ps1'
if (-not (Test-Path -LiteralPath $script:NativeProcessHelperPath)) {
  throw 'Legado native process helper is missing.'
}
. $script:NativeProcessHelperPath

$script:RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$script:LegadoRoot = Join-Path $script:RepoRoot 'legado'
$script:SourcePackage = 'F:\Downloads-E\墨辰整理书源大全7.1（禁止倒卖）.【最新完整】.json'
$script:ExpectedLegadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$script:FixturePort = 18765
$script:TlsFixturePort = 18766
$script:AndroidCommandlineToolsUrl = 'https://dl.google.com/android/repository/commandlinetools-win-13114758_latest.zip'
$script:StateDirectory = Join-Path $PSScriptRoot 'state'
$script:EvidenceDirectory = Join-Path $PSScriptRoot 'evidence'
$script:StatePath = Join-Path $script:StateDirectory 'legado-compatibility-state.json'
$script:FullSourceValidationStatePath = Join-Path $script:StateDirectory 'full-source-validation-state.json'
$script:ContinuousGovernanceTaskListPath = Join-Path $script:RepoRoot 'docs\analysis\Legado书源全量真机与小说UI持续治理任务清单.md'
$script:V2GovernanceTaskListPath = Join-Path $PSScriptRoot 'LEGADO_V2_GOVERNANCE_TASKS.md'
$script:FixtureScript = Join-Path $PSScriptRoot 'FixtureServer.ps1'
$script:TlsFixtureScript = Join-Path $PSScriptRoot 'FixtureTlsServer.mjs'
$script:TlsFixtureDirectory = Join-Path $script:StateDirectory 'tls-fixture'
$script:TlsFixtureCertificatePath = Join-Path $script:TlsFixtureDirectory 'fixture-cert.pem'
$script:TlsFixturePrivateKeyPath = Join-Path $script:TlsFixtureDirectory 'fixture-key.pem'
$script:Stage7RealUserFlowScript = Join-Path $PSScriptRoot 'Invoke-LegadoV2RealDeviceFlow.ps1'
$script:Stage7RealUserEvidencePath = Join-Path $script:EvidenceDirectory 'stage7-real-user-v2.json'
$script:Stage7DiagnosticEvidencePath = Join-Path $script:EvidenceDirectory 'stage7-real-user-v2-diagnostic.json'
$script:Stage7ALiveReferenceScript = Join-Path $PSScriptRoot 'Invoke-LegadoLiveReference.ps1'
$script:Stage7ALiveReferenceEvidencePath = Join-Path $script:EvidenceDirectory 'stage7a-legado-live-reference.json'
$script:LegadoReferenceGradleInitScript = Join-Path $PSScriptRoot 'legado-reference.init.gradle'
$script:ExecutionPlanRevision = '2026-07-30-v12-v2-search-detail-proof-and-card-scoping'
$script:ReportPath = Join-Path $script:RepoRoot 'docs\analysis\漫匣与Legado书源引擎实证对照调查报告.md'
$script:LedgerPath = Join-Path $script:RepoRoot 'docs\analysis\Legado书源引擎兼容推进台账.md'
$script:EvidenceIndexPath = Join-Path $script:RepoRoot 'docs\analysis\Legado书源引擎证据索引.md'
$script:DifferencePath = Join-Path $script:RepoRoot 'docs\analysis\Legado书源引擎差分摘要.md'
$script:FixtureProcess = $null
$script:TlsFixtureProcess = $null
$script:Toolchain = $null
$script:LastFailureEvidence = ''

function Write-Utf8Atomic {
  param([string]$Path, [string]$Content)
  $directory = Split-Path $Path -Parent
  if (-not (Test-Path -LiteralPath $directory)) {
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  }
  $temporaryPath = "$Path.tmp.$PID.$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  $encoding = [System.Text.UTF8Encoding]::new($false)
  [System.IO.File]::WriteAllText($temporaryPath, $Content, $encoding)
  Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
}

function Get-ExecutionTimestamp {
  return [DateTimeOffset]::UtcNow.ToString('o')
}

function New-StageState {
  param([string]$Name)
  [pscustomobject][ordered]@{
    name = $Name
    status = 'planned'
    startedAt = ''
    endedAt = ''
    message = ''
    checks = @()
  }
}

function New-CompatibilityState {
  [pscustomobject][ordered]@{
    schemaVersion = 5
    executionPlanRevision = $script:ExecutionPlanRevision
    baseline = [pscustomobject][ordered]@{
      sourcePackageSha256 = ''
      sourcePackageBytes = 0
      sourceCount = 0
      legadoCommit = ''
    }
    generatedAt = ''
    stages = [pscustomobject][ordered]@{
      stage0 = (New-StageState '阶段 0：基线与差分平台')
      stage1 = (New-StageState '阶段 1：无损导入与存储')
      stage2 = (New-StageState '阶段 2：规则编译器与请求内核')
      stage3 = (New-StageState '阶段 3：ArkWeb 统一传输')
      stage4 = (New-StageState '阶段 4：工作流与类型适配')
      stage5 = (New-StageState '阶段 5：JS API 契约')
      stage6 = (New-StageState '阶段 6：全局 V2 切换、界面与收敛')
      stage7 = (New-StageState '阶段 7：V2 全局路径封口与真机验收')
      stage7a = (New-StageState '阶段 7A：原版 Legado 同端点差分诊断')
      stage8 = (New-StageState '阶段 8：能力矩阵扩展与上线收敛')
    }
  }
}

function Read-CompatibilityState {
  if (-not (Test-Path -LiteralPath $script:StatePath)) {
    return New-CompatibilityState
  }
  $content = [System.IO.File]::ReadAllText($script:StatePath, [System.Text.UTF8Encoding]::new($false))
  try {
    return $content | ConvertFrom-Json
  } catch {
    return New-CompatibilityState
  }
}

$script:State = Read-CompatibilityState
$existingPlanRevision = ''
$revisionProperty = $script:State.PSObject.Properties['executionPlanRevision']
if ($null -ne $revisionProperty -and $null -ne $revisionProperty.Value) {
  $existingPlanRevision = [string]$revisionProperty.Value
}
if ($existingPlanRevision -ne $script:ExecutionPlanRevision) {
  # Earlier evidence was produced under a less strict device-page scope and
  # contains timestamps rendered in the device's local time zone.  It cannot
  # be combined with the revised, UTC-only evidence protocol.  Start a fresh
  # state machine; the frozen package and Legado commit are re-established by
  # stage 0 before any downstream stage may pass.
  $script:State = New-CompatibilityState
}
$script:State.schemaVersion = 5
$script:State.executionPlanRevision = $script:ExecutionPlanRevision
if (-not ($script:State.stages.PSObject.Properties.Name -contains 'stage7')) {
  $script:State.stages | Add-Member -NotePropertyName stage7 -NotePropertyValue (New-StageState '阶段 7：V2 全局路径封口与真机验收')
}
if (-not ($script:State.stages.PSObject.Properties.Name -contains 'stage7a')) {
  $script:State.stages | Add-Member -NotePropertyName stage7a -NotePropertyValue (New-StageState '阶段 7A：原版 Legado 同端点差分诊断')
}
if (-not ($script:State.stages.PSObject.Properties.Name -contains 'stage8')) {
  $script:State.stages | Add-Member -NotePropertyName stage8 -NotePropertyValue (New-StageState '阶段 8：能力矩阵扩展与上线收敛')
}
$script:State.stages.stage6.name = '阶段 6：全局 V2 切换、界面与收敛'
$script:State.stages.stage7.name = '阶段 7：V2 全局路径封口与真机验收'
$script:State.stages.stage7a.name = '阶段 7A：原版 Legado 同端点差分诊断'
$script:State.stages.stage8.name = '阶段 8：能力矩阵扩展与上线收敛'

function New-Check {
  param([string]$Name, [string]$Status, [string]$Detail, [string]$Evidence = '')
  [pscustomobject][ordered]@{
    name = $Name
    status = $Status
    detail = $Detail
    evidence = $Evidence
  }
}

function New-StageResult {
  param([string]$Message, [object[]]$Checks)
  [pscustomobject]@{ message = $Message; checks = @($Checks) }
}

function Throw-Blocked {
  param([string]$Message)
  throw "BLOCKED:$Message"
}

function Get-StageRows {
  $rows = @()
  foreach ($property in $script:State.stages.PSObject.Properties) {
    $stage = $property.Value
    $rows += "| $($stage.name) | $($stage.status) | $($stage.message) |"
  }
  return $rows
}

function Get-DocumentPropertyValue {
  param(
    [object]$Object,
    [string]$Name,
    [object]$DefaultValue = $null
  )

  if ($null -eq $Object) {
    return $DefaultValue
  }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property -or $null -eq $property.Value) {
    return $DefaultValue
  }
  return $property.Value
}

function Get-ContinuousGovernanceDocumentBlock {
  $intro = @(
    '## 持续真机治理状态',
    '',
    '该区块只读取 `tools/legado-compat/state/full-source-validation-state.json`，与阶段状态机分开呈现。它记录后续逐源真机治理与 UI 回归，**不会将阶段 7 的历史失败改写为通过**。',
    ''
  )
  if (-not (Test-Path -LiteralPath $script:FullSourceValidationStatePath)) {
    return $intro + @(
      '持续治理机器事实尚未初始化。'
    )
  }

  try {
    $content = [System.IO.File]::ReadAllText(
      $script:FullSourceValidationStatePath,
      [System.Text.UTF8Encoding]::new($false)
    )
    $fullState = $content | ConvertFrom-Json
  } catch {
    return $intro + @(
      '持续治理机器事实不可读取；自动文档未从损坏或不完整的状态文件推导结论。'
    )
  }

  $governance = Get-DocumentPropertyValue -Object $fullState -Name 'governance'
  $statusCounts = Get-DocumentPropertyValue -Object $fullState -Name 'statusCounts'
  $qualificationCounts = Get-DocumentPropertyValue -Object $fullState -Name 'qualificationCounts'
  $devicePersistedQualification = Get-DocumentPropertyValue -Object $fullState -Name 'devicePersistedQualification'
  $sources = @((Get-DocumentPropertyValue -Object $fullState -Name 'sources' -DefaultValue @()))
  $sourceSummary = New-Object 'System.Collections.Generic.List[string]'
  foreach ($status in @(
    'planned',
    'running',
    'verifying',
    'passed',
    'failed',
    'expected_external',
    'needs_interaction',
    'policy_blocked',
    'blocked'
  )) {
    $count = 0
    if ($null -ne $statusCounts) {
      $count = [int](Get-DocumentPropertyValue -Object $statusCounts -Name $status -DefaultValue 0)
    }
    $sourceSummary.Add(('{0}={1}' -f $status, $count)) | Out-Null
  }

  $qualificationSummary = New-Object 'System.Collections.Generic.List[string]'
  foreach ($qualification in @(
    'unverified',
    'execution_verified_no_reference',
    'semantic_match',
    'semantic_mismatch',
    'external_confirmed',
    'endpoint_unconfirmed',
    'needs_interaction',
    'policy_rejected',
    'engine_rejected',
    'arkweb_unconfirmed',
    'harness_or_engine_failure'
  )) {
    $count = 0
    if ($null -ne $qualificationCounts) {
      $count = [int](Get-DocumentPropertyValue -Object $qualificationCounts -Name $qualification -DefaultValue 0)
    }
    $qualificationSummary.Add(('{0}={1}' -f $qualification, $count)) | Out-Null
  }

  $issues = @((Get-DocumentPropertyValue -Object $governance -Name 'issues' -DefaultValue @()) | Where-Object { $null -ne $_ })
  $tasks = @((Get-DocumentPropertyValue -Object $governance -Name 'tasks' -DefaultValue @()) | Where-Object { $null -ne $_ })
  $issueStatusCounts = [ordered]@{}
  foreach ($status in @('planned', 'running', 'verifying', 'passed', 'failed', 'blocked')) {
    $issueStatusCounts[$status] = 0
  }
  foreach ($issue in $issues) {
    $status = [string](Get-DocumentPropertyValue -Object $issue -Name 'status' -DefaultValue 'planned')
    if (-not $issueStatusCounts.Contains($status)) {
      $issueStatusCounts[$status] = 0
    }
    $issueStatusCounts[$status] = [int]$issueStatusCounts[$status] + 1
  }
  $activeTaskIds = New-Object 'System.Collections.Generic.List[string]'
  foreach ($task in $tasks) {
    $status = [string](Get-DocumentPropertyValue -Object $task -Name 'status' -DefaultValue 'planned')
    if ($status -in @('running', 'verifying')) {
      $taskId = [string](Get-DocumentPropertyValue -Object $task -Name 'id' -DefaultValue '')
      if ($taskId.Length -gt 0) {
        $activeTaskIds.Add($taskId) | Out-Null
      }
    }
  }
  $issueSummary = New-Object 'System.Collections.Generic.List[string]'
  foreach ($property in $issueStatusCounts.GetEnumerator()) {
    $issueSummary.Add(('{0}={1}' -f $property.Key, $property.Value)) | Out-Null
  }
  $fullStatus = [string](Get-DocumentPropertyValue -Object $fullState -Name 'status' -DefaultValue 'planned')
  $governanceStatus = [string](Get-DocumentPropertyValue -Object $governance -Name 'status' -DefaultValue 'planned')
  $activeIssueId = [string](Get-DocumentPropertyValue -Object $governance -Name 'activeIssueId' -DefaultValue '')
  $activeIssue = @($issues | Where-Object { [string](Get-DocumentPropertyValue -Object $_ -Name 'id' -DefaultValue '') -eq $activeIssueId }) | Select-Object -First 1
  $activeIssueStatus = if ($null -eq $activeIssue) { 'unknown' } else { [string](Get-DocumentPropertyValue -Object $activeIssue -Name 'status' -DefaultValue 'unknown') }
  $activeIssueSummary = if ($null -eq $activeIssue) { '机器事实未找到活动议题记录' } else { [string](Get-DocumentPropertyValue -Object $activeIssue -Name 'summary' -DefaultValue '') }
  $activeTasks = if ($activeTaskIds.Count -eq 0) { '无' } else { [string]::Join('、', $activeTaskIds.ToArray()) }
  $deviceObservationStatus = [string](Get-DocumentPropertyValue -Object $devicePersistedQualification -Name 'observationStatus' -DefaultValue 'unobserved')
  $deviceVerifiedCount = [int](Get-DocumentPropertyValue -Object $devicePersistedQualification -Name 'completeVerificationCount' -DefaultValue 0)
  $deviceVerificationDenominator = [int](Get-DocumentPropertyValue -Object $devicePersistedQualification -Name 'verificationDenominator' -DefaultValue 0)
  $devicePolicy = [string](Get-DocumentPropertyValue -Object $devicePersistedQualification -Name 'executionPolicy' -DefaultValue 'unknown')
  $deviceEvidencePath = [string](Get-DocumentPropertyValue -Object $devicePersistedQualification -Name 'evidencePath' -DefaultValue '')
  $deviceEvidence = if ($deviceEvidencePath.Length -eq 0) { '无真机聚合证据' } else { "证据=$deviceEvidencePath" }

  return $intro + @(
    '| 范围 | 状态 | 脱敏摘要 |',
    '| --- | --- | --- |',
    ('| 真机持久化“完整验证”（唯一设备级口径） | {0} | 完整验证={1}/{2}；策略={3}；{4} |' -f $deviceObservationStatus, $deviceVerifiedCount, $deviceVerificationDenominator, $devicePolicy, $deviceEvidence),
    ('| Harness / 状态机逐源执行账本（不等同真机完整验证） | {0} | 总数={1}；{2} |' -f $fullStatus, $sources.Count, [string]::Join('；', $sourceSummary.ToArray())),
    ('| V2 语义资格（fixture、trace 与参考差分；不等同真机完整验证） | evidence | {0} |' -f [string]::Join('；', $qualificationSummary.ToArray())),
    ('| 持续治理台账 | {0} | 活跃任务：{1}；议题：{2} |' -f $governanceStatus, $activeTasks, [string]::Join('；', $issueSummary.ToArray())),
    ('| 当前机器活动源码议题 | {0} | {1}；{2} |' -f $activeIssueId, $activeIssueStatus, $activeIssueSummary),
    '',
    '详细治理问题、证据路径和状态转换以该机器事实源为准；原始书源、Cookie、账号、正文和密钥均不进入本区块。'
  )
}

function Convert-GovernanceDocumentCell {
  param([string]$Value)
  if ($null -eq $Value) {
    return ''
  }
  return $Value.Replace("`r", ' ').Replace("`n", ' ').Replace('|', '&#124;').Replace('`', '&#96;')
}

function Get-FullSourceValidationState {
  if (-not (Test-Path -LiteralPath $script:FullSourceValidationStatePath)) {
    return $null
  }
  try {
    $content = [System.IO.File]::ReadAllText(
      $script:FullSourceValidationStatePath,
      [System.Text.UTF8Encoding]::new($false)
    )
    return $content | ConvertFrom-Json
  } catch {
    return $null
  }
}

function Get-GovernanceEvidenceDocumentBlock {
  param([object]$FullState)

  $block = New-Object 'System.Collections.Generic.List[string]'
  $block.Add('## 持续治理议题证据') | Out-Null
  $block.Add('') | Out-Null
  $block.Add('以下路径由 `full-source-validation-state.json` 的 `governance.issues[].evidencePaths` 自动生成；同一议题的历史失败证据不被覆盖。') | Out-Null
  $block.Add('') | Out-Null
  $block.Add('| 议题 | 状态 | 摘要 | 证据路径 |') | Out-Null
  $block.Add('| --- | --- | --- | --- |') | Out-Null

  if ($null -eq $FullState) {
    $block.Add('| - | blocked | 持续治理事实源不可读取 | - |') | Out-Null
    return $block.ToArray()
  }

  $governance = Get-DocumentPropertyValue -Object $FullState -Name 'governance'
  $issues = @((Get-DocumentPropertyValue -Object $governance -Name 'issues' -DefaultValue @()) | Where-Object { $null -ne $_ })
  $emitted = 0
  foreach ($issue in $issues) {
    $evidencePaths = New-Object 'System.Collections.Generic.List[string]'
    foreach ($pathValue in @((Get-DocumentPropertyValue -Object $issue -Name 'evidencePaths' -DefaultValue @()))) {
      if ($null -eq $pathValue) { continue }
      $path = ([string]$pathValue).Trim()
      if ($path.Length -eq 0 -or $evidencePaths.Contains($path)) { continue }
      $evidencePaths.Add($path) | Out-Null
    }
    if ($evidencePaths.Count -eq 0) { continue }

    $issueId = Convert-GovernanceDocumentCell ([string](Get-DocumentPropertyValue -Object $issue -Name 'id' -DefaultValue ''))
    $status = Convert-GovernanceDocumentCell ([string](Get-DocumentPropertyValue -Object $issue -Name 'status' -DefaultValue 'planned'))
    $summary = Convert-GovernanceDocumentCell ([string](Get-DocumentPropertyValue -Object $issue -Name 'summary' -DefaultValue ''))
    $renderedPaths = New-Object 'System.Collections.Generic.List[string]'
    foreach ($path in $evidencePaths) {
      $renderedPaths.Add(('`{0}`' -f (Convert-GovernanceDocumentCell $path))) | Out-Null
    }
    $block.Add(('| `{0}` | `{1}` | {2} | {3} |' -f $issueId, $status, $summary, ([string]::Join('<br>', $renderedPaths.ToArray())))) | Out-Null
    $emitted++
  }
  if ($emitted -eq 0) {
    $block.Add('| - | - | 当前没有带证据路径的治理议题 | - |') | Out-Null
  }
  return $block.ToArray()
}

function Update-ContinuousGovernanceTaskList {
  if (-not (Test-Path -LiteralPath $script:ContinuousGovernanceTaskListPath)) {
    return
  }
  try {
    $stateText = [System.IO.File]::ReadAllText($script:FullSourceValidationStatePath, [System.Text.UTF8Encoding]::new($false))
    $fullState = $stateText | ConvertFrom-Json
  } catch {
    return
  }
  $governance = Get-DocumentPropertyValue -Object $fullState -Name 'governance'
  $tasks = @((Get-DocumentPropertyValue -Object $governance -Name 'tasks' -DefaultValue @()) | Where-Object { $null -ne $_ })
  $issues = @((Get-DocumentPropertyValue -Object $governance -Name 'issues' -DefaultValue @()) | Where-Object { $null -ne $_ })
  $block = New-Object 'System.Collections.Generic.List[string]'
  $block.Add('<!-- LEGADO_CONTINUOUS_GOVERNANCE_STATUS:START -->') | Out-Null
  $block.Add('## 自动化状态镜像') | Out-Null
  $block.Add('') | Out-Null
  $block.Add('本区块由 `full-source-validation-state.json` 自动生成；它覆盖下方历史叙述中的状态字段，不改写历史证据。') | Out-Null
  $block.Add('') | Out-Null
  $block.Add('| 项目 | 状态 | 尝试 |') | Out-Null
  $block.Add('| --- | --- | --- |') | Out-Null
  foreach ($task in $tasks) {
    $taskId = Convert-GovernanceDocumentCell ([string](Get-DocumentPropertyValue -Object $task -Name 'id' -DefaultValue ''))
    $status = Convert-GovernanceDocumentCell ([string](Get-DocumentPropertyValue -Object $task -Name 'status' -DefaultValue 'planned'))
    $attempts = [int](Get-DocumentPropertyValue -Object $task -Name 'attempts' -DefaultValue 0)
    $block.Add("| task:$taskId | $status | $attempts |") | Out-Null
  }
  foreach ($issue in $issues) {
    $issueId = Convert-GovernanceDocumentCell ([string](Get-DocumentPropertyValue -Object $issue -Name 'id' -DefaultValue ''))
    $status = Convert-GovernanceDocumentCell ([string](Get-DocumentPropertyValue -Object $issue -Name 'status' -DefaultValue 'planned'))
    $severity = Convert-GovernanceDocumentCell ([string](Get-DocumentPropertyValue -Object $issue -Name 'severity' -DefaultValue ''))
    $attempts = [int](Get-DocumentPropertyValue -Object $issue -Name 'attempts' -DefaultValue 0)
    $summary = Convert-GovernanceDocumentCell ([string](Get-DocumentPropertyValue -Object $issue -Name 'summary' -DefaultValue ''))
    $block.Add("| issue:$issueId ($severity) | $status | $attempts；$summary |") | Out-Null
  }
  $block.Add('<!-- LEGADO_CONTINUOUS_GOVERNANCE_STATUS:END -->') | Out-Null
  $document = [System.IO.File]::ReadAllText($script:ContinuousGovernanceTaskListPath, [System.Text.UTF8Encoding]::new($false))
  $replacement = [string]::Join("`r`n", $block.ToArray())
  $startMarker = '<!-- LEGADO_CONTINUOUS_GOVERNANCE_STATUS:START -->'
  $endMarker = '<!-- LEGADO_CONTINUOUS_GOVERNANCE_STATUS:END -->'
  $startIndex = $document.IndexOf($startMarker, [System.StringComparison]::Ordinal)
  $endIndex = $document.IndexOf($endMarker, [System.StringComparison]::Ordinal)
  if ($startIndex -ge 0 -and $endIndex -ge $startIndex) {
    $endIndex += $endMarker.Length
    $document = $document.Substring(0, $startIndex) + $replacement + $document.Substring($endIndex)
  } else {
    $firstLineEnd = $document.IndexOf("`n", [System.StringComparison]::Ordinal)
    if ($firstLineEnd -lt 0) {
      $document = $document + "`r`n`r`n" + $replacement + "`r`n"
    } else {
      $firstLineEnd++
      $document = $document.Substring(0, $firstLineEnd) + "`r`n" + $replacement + "`r`n" + $document.Substring($firstLineEnd)
    }
  }
  Write-Utf8Atomic -Path $script:ContinuousGovernanceTaskListPath -Content $document
}

function Update-V2GovernanceTaskMirror {
  if (-not (Test-Path -LiteralPath $script:V2GovernanceTaskListPath)) {
    throw "V2 governance task ledger is missing: $script:V2GovernanceTaskListPath"
  }
  if (-not (Test-Path -LiteralPath $script:FullSourceValidationStatePath)) {
    throw "Full-source machine state is missing: $script:FullSourceValidationStatePath"
  }

  try {
    $stateText = [System.IO.File]::ReadAllText(
      $script:FullSourceValidationStatePath,
      [System.Text.UTF8Encoding]::new($false)
    )
    $fullState = $stateText | ConvertFrom-Json
  } catch {
    throw "Full-source machine state cannot be parsed: $($_.Exception.Message)"
  }

  $governance = Get-DocumentPropertyValue -Object $fullState -Name 'governance'
  if ($null -eq $governance) {
    throw 'Full-source machine state has no governance section.'
  }
  $tasks = @((Get-DocumentPropertyValue -Object $governance -Name 'tasks' -DefaultValue @()) | Where-Object { $null -ne $_ })
  $issues = @((Get-DocumentPropertyValue -Object $governance -Name 'issues' -DefaultValue @()) | Where-Object { $null -ne $_ })
  if ($tasks.Count -eq 0 -and $issues.Count -eq 0) {
    throw 'Full-source machine state has no governance tasks or issues to mirror.'
  }

  $block = New-Object 'System.Collections.Generic.List[string]'
  $block.Add('<!-- LEGADO_V2_GOVERNANCE_TASK_MIRROR:START -->') | Out-Null
  $block.Add('## 自动化状态镜像') | Out-Null
  $block.Add('') | Out-Null
  $block.Add('本区块只由 `full-source-validation-state.json` 生成；历史任务叙述、失败证据和关闭条件保留在镜像区块之外。') | Out-Null
  $baseline = Get-DocumentPropertyValue -Object $fullState -Name 'baseline'
  $sourceCount = [int](Get-DocumentPropertyValue -Object $baseline -Name 'sourceCount' -DefaultValue 0)
  $sourceHash = Convert-GovernanceDocumentCell ([string](Get-DocumentPropertyValue -Object $baseline -Name 'sourcePackageSha256' -DefaultValue ''))
  $legadoCommit = Convert-GovernanceDocumentCell ([string](Get-DocumentPropertyValue -Object $baseline -Name 'legadoCommit' -DefaultValue ''))
  $activeTaskId = Convert-GovernanceDocumentCell ([string](Get-DocumentPropertyValue -Object $governance -Name 'activeTaskId' -DefaultValue ''))
  $activeIssueId = Convert-GovernanceDocumentCell ([string](Get-DocumentPropertyValue -Object $governance -Name 'activeIssueId' -DefaultValue ''))
  $block.Add(('基线：书源数={0}；SHA-256=`{1}`；Legado=`{2}`；activeTask=`{3}`；activeIssue=`{4}`' -f $sourceCount, $sourceHash, $legadoCommit, $activeTaskId, $activeIssueId)) | Out-Null
  $block.Add('') | Out-Null
  $block.Add('| 类型 | ID | 状态 | 严重度 | 尝试 | 关联任务 | 摘要 |') | Out-Null
  $block.Add('| --- | --- | --- | --- | --- | --- | --- |') | Out-Null
  foreach ($task in $tasks) {
    $taskId = Convert-GovernanceDocumentCell ([string](Get-DocumentPropertyValue -Object $task -Name 'id' -DefaultValue ''))
    $status = Convert-GovernanceDocumentCell ([string](Get-DocumentPropertyValue -Object $task -Name 'status' -DefaultValue 'planned'))
    $attempts = [int](Get-DocumentPropertyValue -Object $task -Name 'attempts' -DefaultValue 0)
    $block.Add((('| task | {0} | {1} | - | {2} | - | machine task |' -f $taskId, $status, $attempts))) | Out-Null
  }
  foreach ($issue in $issues) {
    $issueId = Convert-GovernanceDocumentCell ([string](Get-DocumentPropertyValue -Object $issue -Name 'id' -DefaultValue ''))
    $status = Convert-GovernanceDocumentCell ([string](Get-DocumentPropertyValue -Object $issue -Name 'status' -DefaultValue 'planned'))
    $severity = Convert-GovernanceDocumentCell ([string](Get-DocumentPropertyValue -Object $issue -Name 'severity' -DefaultValue ''))
    $attempts = [int](Get-DocumentPropertyValue -Object $issue -Name 'attempts' -DefaultValue 0)
    $taskId = Convert-GovernanceDocumentCell ([string](Get-DocumentPropertyValue -Object $issue -Name 'taskId' -DefaultValue ''))
    $summary = Convert-GovernanceDocumentCell ([string](Get-DocumentPropertyValue -Object $issue -Name 'summary' -DefaultValue ''))
    $block.Add((('| issue | {0} | {1} | {2} | {3} | {4} | {5} |' -f $issueId, $status, $severity, $attempts, $taskId, $summary))) | Out-Null
  }
  $block.Add('<!-- LEGADO_V2_GOVERNANCE_TASK_MIRROR:END -->') | Out-Null

  try {
    $document = [System.IO.File]::ReadAllText(
      $script:V2GovernanceTaskListPath,
      [System.Text.UTF8Encoding]::new($false)
    )
  } catch {
    throw "V2 governance task ledger cannot be read: $($_.Exception.Message)"
  }
  $replacement = [string]::Join("`r`n", $block.ToArray())
  $startMarker = '<!-- LEGADO_V2_GOVERNANCE_TASK_MIRROR:START -->'
  $endMarker = '<!-- LEGADO_V2_GOVERNANCE_TASK_MIRROR:END -->'
  $startIndex = $document.IndexOf($startMarker, [System.StringComparison]::Ordinal)
  $endIndex = $document.IndexOf($endMarker, [System.StringComparison]::Ordinal)
  if ($startIndex -ge 0 -and $endIndex -ge $startIndex) {
    $endIndex += $endMarker.Length
    $document = $document.Substring(0, $startIndex) + $replacement + $document.Substring($endIndex)
  } else {
    $firstLineEnd = $document.IndexOf("`n", [System.StringComparison]::Ordinal)
    if ($firstLineEnd -lt 0) {
      throw 'V2 governance task ledger has no heading line for mirror insertion.'
    }
    $firstLineEnd++
    $document = $document.Substring(0, $firstLineEnd) + "`r`n" + $replacement + "`r`n" + $document.Substring($firstLineEnd)
  }
  Write-Utf8Atomic -Path $script:V2GovernanceTaskListPath -Content $document
}

function Update-CurrentSourceIssueSection {
  param([Parameter(Mandatory = $true)][object]$FullState)

  $governance = Get-DocumentPropertyValue -Object $FullState -Name 'governance'
  if ($null -eq $governance) {
    throw 'Full-source machine state has no governance section for current issue projection.'
  }
  $activeTaskId = [string](Get-DocumentPropertyValue -Object $governance -Name 'activeTaskId' -DefaultValue '')
  $activeIssueId = [string](Get-DocumentPropertyValue -Object $governance -Name 'activeIssueId' -DefaultValue '')
  if ($activeTaskId.Length -eq 0 -or $activeIssueId.Length -eq 0) {
    throw 'Full-source machine state has no active task or active issue for current issue projection.'
  }
  $issues = @((Get-DocumentPropertyValue -Object $governance -Name 'issues' -DefaultValue @()) | Where-Object { $null -ne $_ })
  $activeIssue = @($issues | Where-Object {
      [string](Get-DocumentPropertyValue -Object $_ -Name 'id' -DefaultValue '') -eq $activeIssueId
    }) | Select-Object -First 1
  if ($null -eq $activeIssue) {
    throw "Active issue is missing from machine governance state: $activeIssueId"
  }
  $activeStatus = [string](Get-DocumentPropertyValue -Object $activeIssue -Name 'status' -DefaultValue 'unknown')
  $summary = Convert-GovernanceDocumentCell ([string](Get-DocumentPropertyValue -Object $activeIssue -Name 'summary' -DefaultValue ''))
  $closeCondition = Convert-GovernanceDocumentCell ([string](Get-DocumentPropertyValue -Object $activeIssue -Name 'closeCondition' -DefaultValue ''))
  $semanticMatchAllowed = [bool](Get-DocumentPropertyValue -Object $governance -Name 'semanticMatchAllowed' -DefaultValue $false)
  $semanticMatchText = $semanticMatchAllowed.ToString().ToLowerInvariant()

  $block = New-Object 'System.Collections.Generic.List[string]'
  $block.Add('<!-- LEGADO_V2_CURRENT_SOURCE_ISSUE:START -->') | Out-Null
  $block.Add('## 当前源码重构活动议题') | Out-Null
  $block.Add('') | Out-Null
  $block.Add(('`{0}` 当前唯一活动源码议题为 `{1}`（{2}）。' -f
      (Convert-GovernanceDocumentCell $activeTaskId),
      (Convert-GovernanceDocumentCell $activeIssueId),
      (Convert-GovernanceDocumentCell $activeStatus))) | Out-Null
  $block.Add(('机器事实摘要：{0}' -f $summary)) | Out-Null
  $block.Add(('关闭条件：{0}' -f $closeCondition)) | Out-Null
  $block.Add(('`semanticMatchAllowed={0}`；R4 运行时、458 条 Harness、Legado 差分、构建和设备验证仍按当前执行策略延期。' -f $semanticMatchText)) | Out-Null
  $block.Add('<!-- LEGADO_V2_CURRENT_SOURCE_ISSUE:END -->') | Out-Null

  $document = [System.IO.File]::ReadAllText($script:V2GovernanceTaskListPath, [System.Text.UTF8Encoding]::new($false))
  $startMarker = '<!-- LEGADO_V2_CURRENT_SOURCE_ISSUE:START -->'
  $endMarker = '<!-- LEGADO_V2_CURRENT_SOURCE_ISSUE:END -->'
  $startIndex = $document.IndexOf($startMarker, [System.StringComparison]::Ordinal)
  $endIndex = $document.IndexOf($endMarker, [System.StringComparison]::Ordinal)
  if ($startIndex -lt 0 -or $endIndex -lt $startIndex) {
    throw 'V2 governance task ledger current issue markers are missing or out of order.'
  }
  $endIndex += $endMarker.Length
  $replacement = [string]::Join("`r`n", $block.ToArray())
  $document = $document.Substring(0, $startIndex) + $replacement + $document.Substring($endIndex)
  Write-Utf8Atomic -Path $script:V2GovernanceTaskListPath -Content $document
}

function Update-Documents {
  $rows = Get-StageRows
  $governanceBlock = Get-ContinuousGovernanceDocumentBlock
  $fullSourceValidationState = Get-FullSourceValidationState
  $governanceEvidenceBlock = Get-GovernanceEvidenceDocumentBlock -FullState $fullSourceValidationState
  $ledger = @(
    '# Legado 书源引擎兼容推进台账',
    '',
    "更新时间：$($script:State.generatedAt)",
    '',
    '| 阶段 | 状态 | 结论 |',
    '| --- | --- | --- |'
  ) + $rows + @(
    ''
  ) + $governanceBlock + @(
    '',
    '持续真机治理状态只来自 `tools/legado-compat/state/full-source-validation-state.json`；阶段历史状态仍由对应阶段事实文件保留。总控不会写入原始书源、Cookie、正文、账号或密钥。'
  )
  Write-Utf8Atomic -Path $script:LedgerPath -Content ($ledger -join "`r`n")

  $evidenceLines = @(
    '# Legado 书源引擎证据索引',
    '',
    "更新时间：$($script:State.generatedAt)",
    ''
  ) + $governanceBlock + @(
    ''
  ) + $governanceEvidenceBlock + @(
    ''
  )
  foreach ($property in $script:State.stages.PSObject.Properties) {
    $stage = $property.Value
    $evidenceLines += "## $($stage.name)"
    $evidenceLines += ''
    if (@($stage.checks).Count -eq 0) {
      $evidenceLines += '尚无执行证据。'
    } else {
      foreach ($check in @($stage.checks)) {
        $evidenceLines += ('- {0} `{1}`：{2}' -f $check.status, $check.name, $check.detail)
        if ($check.evidence) {
          $evidenceLines += ('  证据：`{0}`' -f $check.evidence)
        }
      }
    }
    $evidenceLines += ''
  }
  Write-Utf8Atomic -Path $script:EvidenceIndexPath -Content ($evidenceLines -join "`r`n")

  $documentBaseline = $script:State.baseline
  if ($null -ne $fullSourceValidationState) {
    $continuousBaseline = Get-DocumentPropertyValue -Object $fullSourceValidationState -Name 'baseline'
    $currentSourceCount = [int](Get-DocumentPropertyValue -Object $documentBaseline -Name 'sourceCount' -DefaultValue 0)
    $continuousSourceCount = [int](Get-DocumentPropertyValue -Object $continuousBaseline -Name 'sourceCount' -DefaultValue 0)
    if ($currentSourceCount -le 0 -and $continuousSourceCount -gt 0) {
      $documentBaseline = $continuousBaseline
    }
  }
  $difference = @(
    '# Legado 书源引擎差分摘要',
    '',
    ('Legado 基线提交：`{0}`' -f (Get-DocumentPropertyValue -Object $documentBaseline -Name 'legadoCommit' -DefaultValue '')),
    ('书源包 SHA-256：`{0}`' -f (Get-DocumentPropertyValue -Object $documentBaseline -Name 'sourcePackageSha256' -DefaultValue '')),
    ('书源数量：`{0}`' -f (Get-DocumentPropertyValue -Object $documentBaseline -Name 'sourceCount' -DefaultValue 0)),
    '',
    '仅比较脱敏 ExecutionTrace。HTTP 最终 URL 在 HarmonyOS NetStack 中可能不可观测，此情形会被明确标为 `unobservable`，不会被伪造为一致。',
    ''
  ) + $governanceEvidenceBlock + @(
    '',
    '治理议题证据只表示已产生的可复核输入，不等同于语义兼容通过；状态仍以机器事实源为准。'
  )
  Write-Utf8Atomic -Path $script:DifferencePath -Content ($difference -join "`r`n")

  $reportBlock = @(
    '<!-- LEGADO_COMPATIBILITY_EXECUTION_STATUS:START -->',
    '## 自动化执行状态',
    '',
    "最后刷新：$($script:State.generatedAt)",
    '',
    '| 阶段 | 状态 | 结论 |',
    '| --- | --- | --- |'
  ) + $rows + @(
    ''
  ) + $governanceBlock + @(
    '',
    '详细证据见 `docs/analysis/Legado书源引擎证据索引.md`。该区块由总控自动更新，不改写本报告的调查结论；持续治理证据也不会覆盖阶段 7 的历史状态。',
    '<!-- LEGADO_COMPATIBILITY_EXECUTION_STATUS:END -->'
  ) -join "`r`n"
  if (Test-Path -LiteralPath $script:ReportPath) {
    $report = [System.IO.File]::ReadAllText($script:ReportPath, [System.Text.UTF8Encoding]::new($false))
    $startMarker = '<!-- LEGADO_COMPATIBILITY_EXECUTION_STATUS:START -->'
    $endMarker = '<!-- LEGADO_COMPATIBILITY_EXECUTION_STATUS:END -->'
    $startIndex = $report.IndexOf($startMarker, [System.StringComparison]::Ordinal)
    $endIndex = $report.IndexOf($endMarker, [System.StringComparison]::Ordinal)
    if ($startIndex -ge 0 -and $endIndex -ge $startIndex) {
      $endIndex += $endMarker.Length
      $report = $report.Substring(0, $startIndex) + $reportBlock + $report.Substring($endIndex)
    } else {
      $report = $report.TrimEnd() + "`r`n`r`n" + $reportBlock + "`r`n"
    }
    Write-Utf8Atomic -Path $script:ReportPath -Content $report
  }
  Update-ContinuousGovernanceTaskList
  Update-V2GovernanceTaskMirror
  Update-CurrentSourceIssueSection -FullState $fullSourceValidationState
}

function Save-CompatibilityState {
  $script:State.generatedAt = Get-ExecutionTimestamp
  Write-Utf8Atomic -Path $script:StatePath -Content ($script:State | ConvertTo-Json -Depth 18)
  Update-Documents
}

function Set-StageState {
  param([string]$StageKey, [string]$Status, [string]$Message, [object[]]$Checks = @())
  $stage = $script:State.stages.$StageKey
  if ($Status -eq 'running') {
    $stage.startedAt = Get-ExecutionTimestamp
    $stage.endedAt = ''
  } else {
    if (-not $stage.startedAt) {
      $stage.startedAt = Get-ExecutionTimestamp
    }
    $stage.endedAt = Get-ExecutionTimestamp
  }
  $stage.status = $Status
  $stage.message = $Message
  $stage.checks = @($Checks)
  Save-CompatibilityState
}

function Recover-StaleCompatibilityStages {
  # A killed/closed PowerShell host cannot execute the normal finally block.
  # On the next controlled invocation, recover only stages whose runner has
  # been absent for at least ten minutes; never overwrite an actually running
  # sibling invocation.
  $siblings = @(
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
      Where-Object {
        [int]$_.ProcessId -ne $PID -and
        [string]$_.CommandLine -match '(?i)(?:^|\s)-File\s+[^\r\n]*Invoke-LegadoCompatibility\.ps1' -and
        [string]$_.CommandLine -notmatch '(?i)(?:^|\s)-Command\s'
      }
  )
  if ($siblings.Count -gt 0) { return }
  foreach ($property in $script:State.stages.PSObject.Properties) {
    $stage = $property.Value
    if ([string]$stage.status -ne 'running' -or -not $stage.startedAt) { continue }
    $started = $null
    try { $started = [DateTimeOffset]::Parse([string]$stage.startedAt) } catch { continue }
    if (([DateTimeOffset]::UtcNow - $started).TotalMinutes -lt 10) { continue }
    $reason = "检测到上次总控在 $($stage.startedAt) 后未执行 finally；已将 $($property.Name) 恢复为 blocked，保留可复核的中断状态。"
    Set-StageState -StageKey $property.Name -Status 'blocked' -Message $reason -Checks @(New-Check '中断恢复' 'blocked' $reason)
  }
}

function Get-FirstExistingPath {
  param([string[]]$Candidates)
  foreach ($candidate in $Candidates) {
    if ($candidate -and (Test-Path -LiteralPath $candidate)) {
      return $candidate
    }
  }
  return ''
}

function Find-AndroidSdk {
  $roots = @(
    'G:\Android\Sdk',
    'E:\Android_SDK',
    'F:\AndroidStudio\sdk',
    'F:\Android Studio\sdk',
    'E:\Android studio\sdk',
    'F:\.android\sdk',
    'F:\.android',
    'F:\AndroidStudio',
    'E:\Android studio'
  )
  foreach ($root in $roots) {
    if (Test-Path -LiteralPath (Join-Path $root 'platform-tools\adb.exe')) {
      return $root
    }
    $sdk = Join-Path $root 'sdk'
    if (Test-Path -LiteralPath (Join-Path $sdk 'platform-tools\adb.exe')) {
      return $sdk
    }
  }
  return ''
}

function Find-Jdk21Home {
  $explicit = @(
    'C:\Program Files\Eclipse Adoptium\jdk-21.0.7.6-hotspot',
    'C:\Program Files\Eclipse Adoptium\jdk-21',
    'C:\Program Files\Java\jdk-21'
  )
  $javaCandidateHome = Get-FirstExistingPath $explicit
  if ($javaCandidateHome) { return $javaCandidateHome }
  $adoptiumRoot = 'C:\Program Files\Eclipse Adoptium'
  if (Test-Path -LiteralPath $adoptiumRoot) {
    $candidates = Get-ChildItem -LiteralPath $adoptiumRoot -Directory -ErrorAction SilentlyContinue | Where-Object {
      $_.Name.StartsWith('jdk-21') -and (Test-Path -LiteralPath (Join-Path $_.FullName 'bin\java.exe'))
    } | Sort-Object Name -Descending
    if ($candidates.Count -gt 0) { return $candidates[0].FullName }
  }
  return ''
}

function Invoke-BoundedNativeCommand {
  param(
    [Parameter(Mandatory = $true)][string]$FilePath,
    [string[]]$ArgumentList = @(),
    [ValidateRange(1, 86400)][int]$TimeoutSeconds = 30,
    [string]$WorkingDirectory = '',
    [switch]$Batch,
    [AllowNull()][string]$StandardInput = $null
  )
  $result = if ($Batch) {
    Invoke-LegadoBatchProcess `
      -FilePath $FilePath `
      -ArgumentList $ArgumentList `
      -TimeoutSeconds $TimeoutSeconds `
      -WorkingDirectory $WorkingDirectory `
      -StandardInput $StandardInput
  } else {
    Invoke-LegadoNativeProcess `
      -FilePath $FilePath `
      -ArgumentList $ArgumentList `
      -TimeoutSeconds $TimeoutSeconds `
      -WorkingDirectory $WorkingDirectory `
      -StandardInput $StandardInput
  }
  if ($result.timedOut) {
    $commandName = [System.IO.Path]::GetFileName($FilePath)
    throw "原生命令执行超时：command=$commandName；classification=timeout；timeoutSeconds=$TimeoutSeconds"
  }
  return $result
}

function Get-JavaVersionOutput {
  param([string]$JavaExecutable)
  return (Invoke-BoundedNativeCommand -FilePath $JavaExecutable -ArgumentList @('-version') -TimeoutSeconds 15).output
}

function Find-Jdk17Home {
  $candidates = @(
    'E:\Android studio\jbr',
    'F:\AndroidStudio\jbr',
    'C:\Program Files\Eclipse Adoptium\jdk-17',
    'C:\Program Files\Java\jdk-17'
  )
  foreach ($candidate in $candidates) {
    $javac = Join-Path $candidate 'bin\javac.exe'
    if (-not (Test-Path -LiteralPath $javac)) { continue }
    $version = (Get-JavaVersionOutput -JavaExecutable $javac).Trim()
    if ($version -match '^javac 17\.') { return $candidate }
  }
  return ''
}

function Find-CmdlineTool {
  param([string]$AndroidSdk, [string]$Name)
  $latest = Join-Path $AndroidSdk "cmdline-tools\latest\bin\$Name"
  if (Test-Path -LiteralPath $latest) { return $latest }
  $root = Join-Path $AndroidSdk 'cmdline-tools'
  if (Test-Path -LiteralPath $root) {
    $match = Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | ForEach-Object {
      $candidate = Join-Path $_.FullName "bin\$Name"
      if (Test-Path -LiteralPath $candidate) { $candidate }
    } | Select-Object -First 1
    if ($match) { return [string]$match }
  }
  return ''
}

function Ensure-AndroidCommandlineTools {
  param([pscustomobject]$Toolchain)
  $existingAvdManager = Find-CmdlineTool -AndroidSdk $Toolchain.androidSdk -Name 'avdmanager.bat'
  $existingSdkManager = Find-CmdlineTool -AndroidSdk $Toolchain.androidSdk -Name 'sdkmanager.bat'
  if ($existingAvdManager -and $existingSdkManager) {
    $Toolchain.avdManager = $existingAvdManager
    $Toolchain.sdkManager = $existingSdkManager
    return
  }

  $commandlineToolsRoot = Join-Path $Toolchain.androidSdk 'cmdline-tools'
  $latestRoot = Join-Path $commandlineToolsRoot 'latest'
  if (Test-Path -LiteralPath $latestRoot) {
    Throw-Blocked 'Android cmdline-tools 存在但不完整，拒绝覆盖未知 SDK 内容。'
  }

  $temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("manxia-legado-cmdline-tools-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())")
  $archivePath = "$temporaryRoot.zip"
  try {
    [System.IO.Directory]::CreateDirectory($temporaryRoot) | Out-Null
    Invoke-WebRequest -Uri $script:AndroidCommandlineToolsUrl -OutFile $archivePath -UseBasicParsing -TimeoutSec 180
    Expand-Archive -LiteralPath $archivePath -DestinationPath $temporaryRoot -Force
    $extractedRoot = Join-Path $temporaryRoot 'cmdline-tools'
    $extractedAvdManager = Join-Path $extractedRoot 'bin\avdmanager.bat'
    $extractedSdkManager = Join-Path $extractedRoot 'bin\sdkmanager.bat'
    if (-not (Test-Path -LiteralPath $extractedAvdManager) -or -not (Test-Path -LiteralPath $extractedSdkManager)) {
      Throw-Blocked '下载的 Android command-line tools 不包含 avdmanager/sdmanager。'
    }
    [System.IO.Directory]::CreateDirectory($commandlineToolsRoot) | Out-Null
    Move-Item -LiteralPath $extractedRoot -Destination $latestRoot
    $Toolchain.avdManager = Find-CmdlineTool -AndroidSdk $Toolchain.androidSdk -Name 'avdmanager.bat'
    $Toolchain.sdkManager = Find-CmdlineTool -AndroidSdk $Toolchain.androidSdk -Name 'sdkmanager.bat'
    if (-not $Toolchain.avdManager -or -not $Toolchain.sdkManager) {
      Throw-Blocked 'Android command-line tools 安装后无法被发现。'
    }
  } catch {
    if ($_.Exception.Message -like 'BLOCKED:*') { throw }
    Throw-Blocked "无法自动准备 Android command-line tools：$($_.Exception.Message)"
  } finally {
    if (Test-Path -LiteralPath $archivePath) {
      Remove-Item -LiteralPath $archivePath -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $temporaryRoot) {
      Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
}

function Get-Toolchain {
  $androidSdk = Find-AndroidSdk
  $javaHome = Find-Jdk21Home
  $java17Home = Find-Jdk17Home
  $hdc = Get-FirstExistingPath @(
    'F:\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe',
    'F:\HarmonyOS\SDK\23\toolchains\hdc.exe'
  )
  $hvigor = Get-FirstExistingPath @('F:\DevEco Studio\tools\hvigor\bin\hvigorw.bat')
  [pscustomobject][ordered]@{
    androidSdk = $androidSdk
    javaHome = $javaHome
    java = if ($javaHome) { Join-Path $javaHome 'bin\java.exe' } else { '' }
    java17Home = $java17Home
    adb = if ($androidSdk) { Join-Path $androidSdk 'platform-tools\adb.exe' } else { '' }
    emulator = if ($androidSdk) { Join-Path $androidSdk 'emulator\emulator.exe' } else { '' }
    avdManager = if ($androidSdk) { Find-CmdlineTool -AndroidSdk $androidSdk -Name 'avdmanager.bat' } else { '' }
    sdkManager = if ($androidSdk) { Find-CmdlineTool -AndroidSdk $androidSdk -Name 'sdkmanager.bat' } else { '' }
    hdc = $hdc
    hvigor = $hvigor
  }
}

function Ensure-Toolchain {
  if ($null -eq $script:Toolchain) {
    $script:Toolchain = Get-Toolchain
  }
  $toolchain = $script:Toolchain
  $required = @($toolchain.java, $toolchain.adb, $toolchain.hdc, $toolchain.hvigor)
  foreach ($path in $required) {
    if (-not $path -or -not (Test-Path -LiteralPath $path)) {
      Throw-Blocked 'JDK 21、Android SDK/ADB、HDC 或 Hvigor 工具链不完整。'
    }
  }
  $javaVersion = Get-JavaVersionOutput -JavaExecutable $toolchain.java
  if ($javaVersion -notmatch 'version "21\.') {
    Throw-Blocked '发现的 Java 不是 JDK 21。'
  }
  return $toolchain
}

function Get-OptionalProperty {
  param([object]$Object, [string]$Name)
  if ($null -eq $Object) { return $null }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { return $null }
  return $property.Value
}

function Get-SourcePackageSummary {
  if (-not (Test-Path -LiteralPath $script:SourcePackage)) {
    Throw-Blocked "未找到书源包：$script:SourcePackage"
  }
  $hash = (Get-FileHash -LiteralPath $script:SourcePackage -Algorithm SHA256).Hash
  $bytes = (Get-Item -LiteralPath $script:SourcePackage).Length
  $raw = [System.IO.File]::ReadAllText($script:SourcePackage, [System.Text.UTF8Encoding]::new($false))
  # PowerShell 5.1 keeps a JSON top-level array as one pipeline object, while
  # PowerShell 7 enumerates it. Expand the parsed array explicitly so both
  # hosts retain every source.
  $parsedSources = ConvertFrom-Json -InputObject $raw
  $sources = @()
  foreach ($parsedSource in $parsedSources) {
    $sources += $parsedSource
  }
  $typeCounts = [ordered]@{}
  $capabilityCounts = [ordered]@{
    search = 0; explore = 0; bookInfo = 0; toc = 0; content = 0
    webView = 0; javaScript = 0; login = 0; review = 0; externalType = 0
  }
  foreach ($source in $sources) {
    $sourceType = Get-OptionalProperty -Object $source -Name 'bookSourceType'
    $type = [string]$sourceType
    if (-not $typeCounts.Contains($type)) { $typeCounts[$type] = 0 }
    $typeCounts[$type]++
    if (Get-OptionalProperty -Object $source -Name 'searchUrl') { $capabilityCounts.search++ }
    if (Get-OptionalProperty -Object $source -Name 'exploreUrl') { $capabilityCounts.explore++ }
    if (Get-OptionalProperty -Object $source -Name 'ruleBookInfo') { $capabilityCounts.bookInfo++ }
    if (Get-OptionalProperty -Object $source -Name 'ruleToc') { $capabilityCounts.toc++ }
    if (Get-OptionalProperty -Object $source -Name 'ruleContent') { $capabilityCounts.content++ }
    $sourceText = $source | ConvertTo-Json -Compress -Depth 12
    if ($sourceText -match '"webView"\s*:\s*true|"webJs"') { $capabilityCounts.webView++ }
    if ($sourceText -match '@js:|<js>|\{\{') { $capabilityCounts.javaScript++ }
    if ((Get-OptionalProperty -Object $source -Name 'loginUrl') -or
      (Get-OptionalProperty -Object $source -Name 'loginUi') -or
      (Get-OptionalProperty -Object $source -Name 'loginCheckJs')) { $capabilityCounts.login++ }
    if (Get-OptionalProperty -Object $source -Name 'ruleReview') { $capabilityCounts.review++ }
    if ([int]$sourceType -lt 0 -or [int]$sourceType -gt 3) { $capabilityCounts.externalType++ }
  }
  $summary = [pscustomobject][ordered]@{
    sourcePackageSha256 = $hash
    sourcePackageBytes = $bytes
    sourceCount = $sources.Count
    typeCounts = $typeCounts
    capabilityCounts = $capabilityCounts
    fixtures = @('header-post', 'redirect-cookie', 'workflow-json', 'html-content', 'webview-webjs', 'source-regex', 'unknown-js-api')
  }
  $summaryPath = Join-Path $script:EvidenceDirectory 'source-package-summary.json'
  Write-Utf8Atomic -Path $summaryPath -Content ($summary | ConvertTo-Json -Depth 8)
  return [pscustomobject]@{ summary = $summary; evidence = $summaryPath }
}

function Test-CapabilityMatrixClosure {
  $summaryResult = Get-SourcePackageSummary
  $summary = $summaryResult.summary
  if ($summary.sourceCount -ne 458) {
    throw "能力矩阵书源数量与固定基线不一致：$($summary.sourceCount)"
  }

  $typeTotal = 0
  foreach ($entry in $summary.typeCounts.GetEnumerator()) {
    $typeTotal += [int]$entry.Value
  }
  if ($typeTotal -ne $summary.sourceCount) {
    throw "能力矩阵类型计数不闭合：types=$typeTotal，sources=$($summary.sourceCount)"
  }

  $requiredTypes = @('0', '1', '2', '3', '4')
  foreach ($type in $requiredTypes) {
    if (-not $summary.typeCounts.Contains($type) -or [int]$summary.typeCounts[$type] -le 0) {
      throw "固定书源包缺少 bookSourceType=$type 的能力分类证据。"
    }
  }

  $requiredCapabilityKeys = @('search', 'explore', 'bookInfo', 'toc', 'content', 'javaScript', 'login', 'externalType')
  foreach ($key in $requiredCapabilityKeys) {
    if (-not $summary.capabilityCounts.Contains($key)) {
      throw "能力矩阵缺少 $key 统计项。"
    }
  }

  $closure = [pscustomobject][ordered]@{
    sourcePackageSha256 = $summary.sourcePackageSha256
    sourceCount = $summary.sourceCount
    typeCounts = $summary.typeCounts
    capabilityCounts = $summary.capabilityCounts
    routingDecision = [pscustomobject][ordered]@{
      ready = 'V2_FULL_CUTOVER 统一执行 V2'
      needsInteraction = '中央阻断，不回退旧内核'
      unsupported = '中央阻断，不回退旧内核'
      blocked = '中央阻断，不回退旧内核'
    }
    fixtureCoverage = @('ArkWeb/WebJs', '未知JS API', 'IMAGE正文', 'HTML正文', '分页替换', 'FILE阻断', 'Review阻断', '登录交互阻断')
  }
  $path = Join-Path $script:EvidenceDirectory 'capability-matrix-closure.json'
  Write-Utf8Atomic -Path $path -Content ($closure | ConvertTo-Json -Depth 10)
  return [pscustomobject]@{ summary = $summary; evidence = $path }
}

function Get-RawSourceDocuments {
  $raw = [System.IO.File]::ReadAllText($script:SourcePackage, [System.Text.UTF8Encoding]::new($false))
  $text = $raw.Trim()
  if (-not $text.StartsWith('[')) { return @($raw) }
  $documents = @()
  $inString = $false
  $escaped = $false
  $depth = 0
  $start = -1
  for ($index = 0; $index -lt $text.Length; $index++) {
    $char = $text[$index]
    if ($inString) {
      if ($escaped) { $escaped = $false }
      elseif ($char -eq '\') { $escaped = $true }
      elseif ($char -eq '"') { $inString = $false }
      continue
    }
    if ($char -eq '"') { $inString = $true }
    elseif ($char -eq '{') {
      if ($depth -eq 0) { $start = $index }
      $depth++
    } elseif ($char -eq '}') {
      $depth--
      if ($depth -eq 0 -and $start -ge 0) {
        $documents += $text.Substring($start, $index - $start + 1)
        $start = -1
      }
    }
  }
  if ($inString -or $depth -ne 0 -or $start -ne -1) {
    throw '书源包 JSON 边界扫描失败。'
  }
  return $documents
}

function Test-RawSourceRoundTrip {
  $documents = Get-RawSourceDocuments
  if ($documents.Count -ne 458) { throw "原始 JSON 文档数量错误：$($documents.Count)" }
  $totalLength = 0L
  for ($index = 0; $index -lt $documents.Count; $index++) {
    $document = [string]$documents[$index]
    $parsed = $document | ConvertFrom-Json
    if (-not $parsed.bookSourceUrl -or -not $parsed.bookSourceName) {
      throw "原始 JSON 文档 #$($index + 1) 缺少书源标识。"
    }
    $roundTripBytes = [System.Text.UTF8Encoding]::new($false).GetBytes($document)
    $totalLength += $roundTripBytes.Length
  }
  $audit = [pscustomobject][ordered]@{
    sourceCount = $documents.Count
    rawDocumentBytes = $totalLength
    documentBoundaryScan = 'passed'
    parsedIdentifierScan = 'passed'
  }
  $path = Join-Path $script:EvidenceDirectory 'raw-document-audit.json'
  Write-Utf8Atomic -Path $path -Content ($audit | ConvertTo-Json -Depth 4)
  return $path
}

function Start-Fixture {
  if ($null -ne $script:FixtureProcess -and -not $script:FixtureProcess.HasExited) { return }
  $hostExecutable = Join-Path $PSHOME 'pwsh.exe'
  if (-not (Test-Path -LiteralPath $hostExecutable)) {
    $hostExecutable = Join-Path $PSHOME 'powershell.exe'
  }
  if (-not (Test-Path -LiteralPath $hostExecutable)) {
    Throw-Blocked '无法定位用于启动 fixture 的 PowerShell 宿主。'
  }
  $script:FixtureProcess = Start-Process -FilePath $hostExecutable -ArgumentList @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script:FixtureScript, '-Port', $script:FixturePort
  ) -WindowStyle Hidden -PassThru
  for ($index = 0; $index -lt 12; $index++) {
    try {
      $response = Invoke-WebRequest -Uri "http://127.0.0.1:$script:FixturePort/health" -UseBasicParsing -TimeoutSec 2
      if ($response.StatusCode -eq 200 -and $response.Content -eq 'fixture-health') { return }
    } catch {
      Start-Sleep -Seconds 1
    }
  }
  Throw-Blocked '本地 fixture 服务未在预期时间内启动。'
}

function Stop-Fixture {
  if ($null -ne $script:FixtureProcess) {
    if (-not $script:FixtureProcess.HasExited) {
      Stop-Process -Id $script:FixtureProcess.Id -Force -ErrorAction SilentlyContinue
    }
    $script:FixtureProcess = $null
  }
}

function Start-TlsFixture {
  if ($null -ne $script:TlsFixtureProcess -and -not $script:TlsFixtureProcess.HasExited) { return }
  if (-not (Test-Path -LiteralPath $script:TlsFixtureScript)) {
    Throw-Blocked 'TLS fixture Node.js 脚本不存在。'
  }
  $nodeCommand = Get-Command 'node.exe' -ErrorAction SilentlyContinue
  if ($null -eq $nodeCommand) { Throw-Blocked 'TLS fixture 未找到 Node.js。' }
  $opensslCommand = Get-Command 'openssl.exe' -ErrorAction SilentlyContinue
  if ($null -eq $opensslCommand) { Throw-Blocked 'TLS fixture 未找到 OpenSSL。' }
  [System.IO.Directory]::CreateDirectory($script:TlsFixtureDirectory) | Out-Null
  $previousOpenSslConf = $env:OPENSSL_CONF
  try {
    # The locally installed Strawberry OpenSSL has an obsolete build-time
    # config path. The fixture uses explicit command arguments, so suppress
    # only that process-local lookup and immediately restore the environment.
    $env:OPENSSL_CONF = 'NUL'
    $certificateResult = Invoke-BoundedNativeCommand -FilePath $opensslCommand.Source -ArgumentList @(
      'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-sha256', '-days', '1',
      '-subj', '/CN=localhost', '-addext', 'subjectAltName=IP:127.0.0.1',
      '-keyout', $script:TlsFixturePrivateKeyPath, '-out', $script:TlsFixtureCertificatePath
    ) -TimeoutSeconds 30
  } finally {
    $env:OPENSSL_CONF = $previousOpenSslConf
  }
  if ($certificateResult.exitCode -ne 0 -or
    -not (Test-Path -LiteralPath $script:TlsFixtureCertificatePath) -or
    -not (Test-Path -LiteralPath $script:TlsFixturePrivateKeyPath)) {
    Throw-Blocked 'TLS fixture 自签名证书生成失败。'
  }
  $script:TlsFixtureProcess = Start-Process -FilePath $nodeCommand.Source -ArgumentList @(
    $script:TlsFixtureScript, $script:TlsFixturePort, $script:TlsFixtureCertificatePath, $script:TlsFixturePrivateKeyPath
  ) -WindowStyle Hidden -PassThru
  for ($index = 0; $index -lt 12; $index++) {
    try {
      $response = Invoke-WebRequest -Uri "https://127.0.0.1:$script:TlsFixturePort/tls-observation" -SkipCertificateCheck -UseBasicParsing -TimeoutSec 2
      $result = $response.Content | ConvertFrom-Json
      if ($response.StatusCode -eq 200 -and $result.marker -eq 'fixture-tls-observation-v1') { return }
    } catch {
      Start-Sleep -Seconds 1
    }
  }
  Throw-Blocked '本地 TLS fixture 未在预期时间内启动。'
}

function Stop-TlsFixture {
  if ($null -ne $script:TlsFixtureProcess) {
    if (-not $script:TlsFixtureProcess.HasExited) {
      Stop-Process -Id $script:TlsFixtureProcess.Id -Force -ErrorAction SilentlyContinue
    }
    $script:TlsFixtureProcess = $null
  }
  foreach ($path in @($script:TlsFixtureCertificatePath, $script:TlsFixturePrivateKeyPath)) {
    if (Test-Path -LiteralPath $path) { [System.IO.File]::Delete($path) }
  }
}

function Test-FixtureContract {
  $base = "http://127.0.0.1:$script:FixturePort"
  $post = Invoke-WebRequest -Uri "$base/header-post" -Method Post -Headers @{ 'X-Legado-Header' = 'fixture-header' } -ContentType 'application/x-www-form-urlencoded; charset=utf-8' -Body 'q=fixture' -UseBasicParsing -TimeoutSec 8
  $postResult = $post.Content | ConvertFrom-Json
  if ($postResult.marker -ne 'fixture-header-post' -or $postResult.method -ne 'POST' -or $postResult.header -ne 'fixture-header' -or $postResult.body -ne 'q=fixture') {
    throw 'fixture 未验证 Header/POST 请求语义。'
  }
  $wire = Invoke-WebRequest -Uri "$base/wire-observation" -Headers @{ 'X-Legado-Header' = 'fixture-wire-header' } -UseBasicParsing -TimeoutSec 8
  $wireResult = $wire.Content | ConvertFrom-Json
  $wireNames = @($wireResult.headers | ForEach-Object { [string]$_.name })
  if ($wireResult.marker -ne 'fixture-wire-observation-v1' -or $wireResult.method -ne 'GET' -or
    [string]::IsNullOrEmpty([string]$wireResult.protocol) -or -not $wireNames.Contains('x-legado-header') -or
    @($wireResult.headers | Where-Object { ([string]$_.valueSha256) -notmatch '^[0-9a-f]{64}$' }).Count -gt 0) {
    throw 'fixture 未验证脱敏 wire 观察语义。'
  }
  $connection = Invoke-WebRequest -Uri "$base/connection-observation" -UseBasicParsing -TimeoutSec 8
  $connectionResult = $connection.Content | ConvertFrom-Json
  if ($connectionResult.marker -ne 'fixture-connection-observation-v1' -or
    ([string]$connectionResult.connectionFingerprint) -notmatch '^[0-9a-f]{64}$' -or
    [string]::IsNullOrEmpty([string]$connectionResult.protocol)) {
    throw 'fixture 未验证脱敏连接观察语义。'
  }
  $compressed = Invoke-WebRequest -Uri "$base/compressed-observation" -UseBasicParsing -TimeoutSec 8
  $compressedResult = $compressed.Content | ConvertFrom-Json
  if ($compressedResult.marker -ne 'fixture-compressed-observation-v1' -or
    ([string]$compressedResult.payloadSha256) -notmatch '^[0-9a-f]{64}$') {
    throw 'fixture 未验证 gzip 响应交付语义。'
  }
  $cookies = [System.Net.CookieContainer]::new()
  $redirect = [System.Net.HttpWebRequest]::Create("$base/redirect")
  $redirect.AllowAutoRedirect = $true
  $redirect.CookieContainer = $cookies
  $redirect.Timeout = 8000
  $redirect.ReadWriteTimeout = 8000
  $response = $redirect.GetResponse()
  try {
    $reader = [System.IO.StreamReader]::new($response.GetResponseStream(), [System.Text.Encoding]::UTF8)
    try { $body = $reader.ReadToEnd() } finally { $reader.Dispose() }
  } finally {
    $response.Dispose()
  }
  if ($body -notmatch 'fixture-final\|cookie=true') {
    throw 'fixture 未验证 redirect/Cookie 语义。'
  }
  $workflow = Invoke-WebRequest -Uri "$base/search" -UseBasicParsing -TimeoutSec 8
  if ($workflow.Content -notmatch 'fixture-book') { throw 'fixture 工作流响应无效。' }
  $htmlContent = Invoke-WebRequest -Uri "$base/content/html" -UseBasicParsing -TimeoutSec 8
  if ($htmlContent.Content -notmatch 'fixture-html-content' -or $htmlContent.Content -notmatch '&nbsp;') {
    throw 'fixture 未验证 HTML 正文交付语义。'
  }
  $path = Join-Path $script:EvidenceDirectory 'fixture-contract.json'
  $evidence = [pscustomobject][ordered]@{
    headerPost = 'passed'
    wireObservation = 'passed'
    connectionObservation = 'passed'
    compressedObservation = 'passed'
    redirectCookie = 'passed'
    workflowJson = 'passed'
    htmlContent = 'passed'
    host = "127.0.0.1:$script:FixturePort"
  }
  Write-Utf8Atomic -Path $path -Content ($evidence | ConvertTo-Json -Depth 4)
  return $path
}

function Get-AndroidSerial {
  param([pscustomobject]$Toolchain)
  $deviceResult = Invoke-LegadoNativeProcess -FilePath $Toolchain.adb -ArgumentList @('devices') -TimeoutSeconds 15
  if ($deviceResult.timedOut) {
    throw 'ADB device discovery timed out after 15 seconds.'
  }
  if ($deviceResult.exitCode -ne 0) {
    return ''
  }
  $lines = @($deviceResult.stdout -split "`r?`n")
  foreach ($line in $lines) {
    if ($line -match '^([^\s]+)\s+device$') { return $Matches[1] }
  }
  return ''
}

function Get-AndroidDeviceStatus {
  param([pscustomobject]$Toolchain, [string]$Serial)
  $deviceResult = Invoke-LegadoNativeProcess -FilePath $Toolchain.adb -ArgumentList @('devices') -TimeoutSeconds 15
  if ($deviceResult.timedOut) {
    throw 'ADB device status query timed out after 15 seconds.'
  }
  if ($deviceResult.exitCode -ne 0) {
    return ''
  }
  $lines = @($deviceResult.stdout -split "`r?`n")
  $pattern = '^' + [regex]::Escape($Serial) + '\s+(\S+)$'
  foreach ($line in $lines) {
    if ($line -match $pattern) { return [string]$Matches[1] }
  }
  return ''
}

function Test-AndroidSystemImage {
  param([string]$ImageDirectory)
  if (-not (Test-Path -LiteralPath $ImageDirectory)) { return $false }
  $required = @('package.xml', 'source.properties', 'system.img', 'ramdisk.img')
  foreach ($name in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $ImageDirectory $name))) {
      return $false
    }
  }
  return $true
}

function Ensure-AndroidDevice {
  param([pscustomobject]$Toolchain)
  $serial = Get-AndroidSerial $Toolchain
  if ($serial) { return $serial }
  if (-not $Toolchain.avdManager -or -not $Toolchain.sdkManager) {
    Ensure-AndroidCommandlineTools -Toolchain $Toolchain
  }
  if (-not (Test-Path -LiteralPath $Toolchain.emulator) -or -not (Test-Path -LiteralPath $Toolchain.avdManager)) {
    Throw-Blocked '没有 Android 设备，且 Android Emulator/AVD Manager 不完整。'
  }
  $avdName = 'legado_compat_api36'
  # Modern Emulator builds only guarantee automatic ADB registration for the
  # conventional even console ports in the 5554-5584 range.  The previous
  # 5686/5687 pair could start QEMU yet never expose an ADB transport after a
  # host reboot, making the reference gate appear to hang.
  $emulatorPort = 5560
  $emulatorSerial = "emulator-$emulatorPort"
  $imagePackage = 'system-images;android-36;google_apis;x86_64'
  $imageDirectory = Join-Path $Toolchain.androidSdk 'system-images\android-36\google_apis\x86_64'
  $isolatedAvdHome = Join-Path $script:StateDirectory 'android-avd'
  $isolatedAvdPath = Join-Path $isolatedAvdHome "$avdName.avd"
  $previousSdkRoot = $env:ANDROID_SDK_ROOT
  $previousAndroidHome = $env:ANDROID_HOME
  $previousAvdHome = $env:ANDROID_AVD_HOME
  $previousJavaHome = $env:JAVA_HOME
  try {
    $env:ANDROID_SDK_ROOT = $Toolchain.androidSdk
    $env:ANDROID_HOME = $Toolchain.androidSdk
    $env:ANDROID_AVD_HOME = $isolatedAvdHome
    $env:JAVA_HOME = $Toolchain.javaHome
    [System.IO.Directory]::CreateDirectory($isolatedAvdHome) | Out-Null
    if (-not (Test-AndroidSystemImage -ImageDirectory $imageDirectory)) {
      if (-not (Test-Path -LiteralPath $Toolchain.sdkManager)) {
        Throw-Blocked '缺少 Android API 36 系统镜像且没有 sdkmanager。'
      }
      $installResult = Invoke-BoundedNativeCommand `
        -FilePath $Toolchain.sdkManager `
        -ArgumentList @("--sdk_root=$($Toolchain.androidSdk)", '--install', $imagePackage) `
        -TimeoutSeconds 1800 `
        -Batch
      $installOutput = $installResult.output
      $installExitCode = $installResult.exitCode
      $installEvidence = Join-Path $script:EvidenceDirectory 'android-sdk-system-image-install.log'
      Write-Utf8Atomic -Path $installEvidence -Content $installOutput
      if ($installExitCode -ne 0 -or -not (Test-AndroidSystemImage -ImageDirectory $imageDirectory)) {
        Throw-Blocked '无法自动安装 Android API 36 隔离 AVD 系统镜像。'
      }
    }
    $avdListResult = Invoke-BoundedNativeCommand -FilePath $Toolchain.emulator -ArgumentList @('-list-avds') -TimeoutSeconds 30
    $avds = @($avdListResult.stdout -split "`r?`n" | Where-Object { $_.Trim().Length -gt 0 })
    if (-not ($avds -contains $avdName)) {
      $avdResult = Invoke-BoundedNativeCommand `
        -FilePath $Toolchain.avdManager `
        -ArgumentList @('create', 'avd', '-n', $avdName, '-k', $imagePackage, '-p', $isolatedAvdPath, '--force') `
        -TimeoutSeconds 300 `
        -Batch `
        -StandardInput "no`r`n"
      $avdOutput = $avdResult.output
      $avdExitCode = $avdResult.exitCode
      $avdEvidence = Join-Path $script:EvidenceDirectory 'android-avd-create.log'
      Write-Utf8Atomic -Path $avdEvidence -Content $avdOutput
      if ($avdExitCode -ne 0) { Throw-Blocked '无法创建隔离 Android AVD。' }
    }
    $emulatorProcess = $null
    $managedStatus = Get-AndroidDeviceStatus -Toolchain $Toolchain -Serial $emulatorSerial
    if (-not $managedStatus) {
      $lockPath = Join-Path $isolatedAvdPath 'multiinstance.lock'
      $runningEmulatorProcesses = @(Get-Process -Name 'emulator' -ErrorAction SilentlyContinue)
      $runningQemuProcesses = @(Get-Process -Name 'qemu-system-x86_64' -ErrorAction SilentlyContinue)
      if ($runningEmulatorProcesses.Count -eq 0 -and $runningQemuProcesses.Count -eq 0 -and (Test-Path -LiteralPath $lockPath)) {
        [System.IO.File]::Delete($lockPath)
      }
      $launchId = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
      $launchStdout = Join-Path $script:EvidenceDirectory "android-emulator-$launchId.stdout.log"
      $launchStderr = Join-Path $script:EvidenceDirectory "android-emulator-$launchId.stderr.log"
      $emulatorProcess = Start-Process -FilePath $Toolchain.emulator -ArgumentList @('-avd', $avdName, '-port', "$emulatorPort", '-no-snapshot', '-no-audio', '-no-boot-anim', '-no-window', '-gpu', 'swiftshader_indirect') -WindowStyle Hidden -PassThru -RedirectStandardOutput $launchStdout -RedirectStandardError $launchStderr
    }
    for ($index = 0; $index -lt 60; $index++) {
      Start-Sleep -Seconds 5
      if ($null -ne $emulatorProcess) {
        $emulatorProcess.Refresh()
        if ($emulatorProcess.HasExited) {
          Throw-Blocked "自动创建的 Android AVD 启动进程提前退出；证据：$launchStdout；$launchStderr"
        }
      }
      $managedStatus = Get-AndroidDeviceStatus -Toolchain $Toolchain -Serial $emulatorSerial
      if ($managedStatus -eq 'device') {
        $bootResult = Invoke-BoundedNativeCommand -FilePath $Toolchain.adb -ArgumentList @('-s', $emulatorSerial, 'shell', 'getprop', 'sys.boot_completed') -TimeoutSeconds 30
        if ($bootResult.stdout.Trim() -eq '1') { return $emulatorSerial }
      }
    }
    Throw-Blocked "自动创建的 Android AVD 未能在 300 秒内启动；最后 ADB 状态：$managedStatus"
  } finally {
    $env:ANDROID_SDK_ROOT = $previousSdkRoot
    $env:ANDROID_HOME = $previousAndroidHome
    $env:ANDROID_AVD_HOME = $previousAvdHome
    $env:JAVA_HOME = $previousJavaHome
  }
}

function Ensure-LegadoGradleDistribution {
  param([string]$Gradle, [string]$StageKey)
  $propertiesPath = Join-Path $script:LegadoRoot 'gradle\wrapper\gradle-wrapper.properties'
  if (-not (Test-Path -LiteralPath $propertiesPath)) {
    Throw-Blocked 'Legado Gradle wrapper properties 不存在。'
  }
  $properties = [System.IO.File]::ReadAllText($propertiesPath, [System.Text.UTF8Encoding]::new($false))
  $distributionMatch = [regex]::Match($properties, '(?m)^distributionUrl=(.+)$')
  if (-not $distributionMatch.Success) {
    Throw-Blocked 'Legado Gradle wrapper 未声明 distributionUrl。'
  }
  $distributionUrl = $distributionMatch.Groups[1].Value.Trim().Replace('\:', ':')
  $distributionFileName = Split-Path $distributionUrl -Leaf
  $distributionName = [System.IO.Path]::GetFileNameWithoutExtension($distributionFileName)
  $gradleHome = if ($env:GRADLE_USER_HOME) { $env:GRADLE_USER_HOME } else { Join-Path $env:USERPROFILE '.gradle' }
  $distributionRoot = Join-Path $gradleHome "wrapper\dists\$distributionName"
  $candidateDirectories = @(Get-ChildItem -LiteralPath $distributionRoot -Directory -ErrorAction SilentlyContinue)
  if ($candidateDirectories.Count -ne 1) {
    Throw-Blocked '无法唯一定位 Gradle wrapper 的本地分发缓存目录。'
  }
  $targetDirectory = $candidateDirectories[0].FullName
  $targetPath = Join-Path $targetDirectory $distributionFileName
  if (Test-Path -LiteralPath $targetPath) {
    return ''
  }
  $checksumResponse = Invoke-WebRequest -Uri "$distributionUrl.sha256" -UseBasicParsing -TimeoutSec 45
  $checksumBytes = [byte[]]$checksumResponse.Content
  $expectedHash = [System.Text.Encoding]::UTF8.GetString($checksumBytes).Trim().ToUpperInvariant()
  if ($expectedHash -notmatch '^[0-9A-F]{64}$') {
    Throw-Blocked 'Gradle 官方 SHA-256 响应格式无效。'
  }
  $temporaryPath = "$targetPath.download.$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  $evidencePath = Join-Path $script:EvidenceDirectory "android-gradle-wrapper-recovery-$StageKey.json"
  try {
    Invoke-WebRequest -Uri $distributionUrl -OutFile $temporaryPath -UseBasicParsing -TimeoutSec 600
    $actualHash = (Get-FileHash -LiteralPath $temporaryPath -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($actualHash -ne $expectedHash) {
      Throw-Blocked '下载的 Gradle 分发包 SHA-256 与官方校验和不一致。'
    }
    foreach ($staleName in @("$distributionFileName.lck", "$distributionFileName.part")) {
      $stalePath = Join-Path $targetDirectory $staleName
      if (Test-Path -LiteralPath $stalePath) {
        [System.IO.File]::Delete($stalePath)
      }
    }
    [System.IO.File]::Move($temporaryPath, $targetPath)
    $metadata = [pscustomobject][ordered]@{
      distribution = $distributionFileName
      source = $distributionUrl
      sha256 = $actualHash
      status = 'verified'
    }
    Write-Utf8Atomic -Path $evidencePath -Content ($metadata | ConvertTo-Json -Depth 4)
    return $evidencePath
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) {
      [System.IO.File]::Delete($temporaryPath)
    }
  }
}

function Get-JavaProxyOptions {
  $httpProxy = [string]$env:HTTP_PROXY
  $httpsProxy = [string]$env:HTTPS_PROXY
  if (-not $httpProxy -or -not $httpsProxy) {
    $internetSettings = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
    if ($null -ne $internetSettings -and $internetSettings.ProxyEnable -eq 1 -and $internetSettings.ProxyServer) {
      $proxyServer = [string]$internetSettings.ProxyServer
      if ($proxyServer -match '(^|;)http=([^;]+)') { $httpProxy = "http://$($Matches[2])" }
      if ($proxyServer -match '(^|;)https=([^;]+)') { $httpsProxy = "http://$($Matches[2])" }
      if ($proxyServer -notmatch '=') {
        if (-not $httpProxy) { $httpProxy = "http://$proxyServer" }
        if (-not $httpsProxy) { $httpsProxy = "http://$proxyServer" }
      }
    }
  }
  $options = @()
  foreach ($pair in @(
    [pscustomobject]@{ scheme = 'http'; value = $httpProxy },
    [pscustomobject]@{ scheme = 'https'; value = $httpsProxy }
  )) {
    if (-not $pair.value) { continue }
    try {
      $proxyUri = [uri]$pair.value
      if ($proxyUri.Host -and $proxyUri.Port -gt 0) {
        $options += "-D$($pair.scheme).proxyHost=$($proxyUri.Host)"
        $options += "-D$($pair.scheme).proxyPort=$($proxyUri.Port)"
      }
    } catch {
      continue
    }
  }
  return ($options -join ' ')
}

function Clear-IsolatedGradleTransformCache {
  param([string]$GradleHome, [string]$StageKey)
  $cachePath = Join-Path $GradleHome 'caches\8.13\transforms'
  if (-not (Test-Path -LiteralPath $cachePath)) { return '' }
  $rootPath = [System.IO.Path]::GetFullPath($GradleHome).TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
  $targetPath = [System.IO.Path]::GetFullPath($cachePath)
  if (-not $targetPath.StartsWith($rootPath, [System.StringComparison]::OrdinalIgnoreCase)) {
    Throw-Blocked '拒绝清理不在隔离 Gradle 主目录内的缓存路径。'
  }
  $runningGradle = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -match '^java(w)?\.exe$' -and $_.CommandLine -and $_.CommandLine.IndexOf($GradleHome, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
  })
  if ($runningGradle.Count -gt 0) {
    Throw-Blocked '隔离 Gradle 缓存仍被运行中的 Java 进程占用，拒绝清理。'
  }
  try {
    [System.IO.Directory]::Delete($targetPath, $true)
  } catch {
    Throw-Blocked "无法清理已验证的隔离 Gradle transforms 缓存：$($_.Exception.Message)"
  }
  $evidencePath = Join-Path $script:EvidenceDirectory "android-gradle-transform-recovery-$StageKey.json"
  $metadata = [pscustomobject][ordered]@{
    cache = 'caches/8.13/transforms'
    status = 'cleared'
  }
  Write-Utf8Atomic -Path $evidencePath -Content ($metadata | ConvertTo-Json -Depth 4)
  return $evidencePath
}

function Ensure-AndroidFixtureReverseForward {
  param(
    [pscustomobject]$Toolchain,
    [string]$Serial,
    [string]$StageKey,
    [int]$Port = $script:FixturePort,
    [string]$Scheme = 'http',
    [string]$EvidenceSuffix = ''
  )
  $portNode = "tcp:$Port"
  $forwardResult = Invoke-BoundedNativeCommand -FilePath $Toolchain.adb -ArgumentList @('-s', $Serial, 'reverse', $portNode, $portNode) -TimeoutSeconds 30
  $forwardOutput = $forwardResult.output
  $forwardExitCode = $forwardResult.exitCode
  $forwardListResult = Invoke-BoundedNativeCommand -FilePath $Toolchain.adb -ArgumentList @('-s', $Serial, 'reverse', '--list') -TimeoutSeconds 30
  $forwardList = $forwardListResult.output
  $expectedEntry = [regex]::Escape($portNode) + '\s+' + [regex]::Escape($portNode)
  if ($forwardExitCode -ne 0 -or $forwardList -notmatch $expectedEntry) {
    throw "Android fixture ADB 反向端口转发失败：$forwardOutput"
  }

  $evidencePath = Join-Path $script:EvidenceDirectory "android-fixture-reverse-forward-$StageKey$EvidenceSuffix.json"
  $evidence = [pscustomobject][ordered]@{
    serial = $Serial
    local = $portNode
    remote = $portNode
    fixtureUrl = "$Scheme`://127.0.0.1:$Port"
    transport = 'adb-reverse'
    status = 'passed'
  }
  Write-Utf8Atomic -Path $evidencePath -Content ($evidence | ConvertTo-Json -Depth 4)
  return [pscustomobject]@{ fixtureUrl = $evidence.fixtureUrl; evidence = $evidencePath }
}

function Get-AndroidReferenceTrace {
  param([pscustomobject]$Toolchain, [string]$Serial, [datetime]$TestStartedAt)
  $logcatResult = Invoke-BoundedNativeCommand -FilePath $Toolchain.adb -ArgumentList @('-s', $Serial, 'logcat', '-d', '-s', 'LegadoCompatTrace:I') -TimeoutSeconds 60
  $liveLines = @($logcatResult.stdout -split "`r?`n" | Where-Object {
    $_ -match 'LEGADO_TRACE:' -or $_ -match 'LEGADO_WIRE_TRACE:' -or
    $_ -match 'LEGADO_CONNECTION_TRACE:' -or $_ -match 'LEGADO_COMPRESSION_TRACE:' -or
    $_ -match 'LEGADO_TLS_TRACE:'
  })
  if ($liveLines.Count -gt 0) {
    return [pscustomobject]@{ lines = $liveLines; source = 'adb-logcat' }
  }

  $resultsRoot = Join-Path $script:LegadoRoot 'app\build\outputs\androidTest-results\connected'
  if (-not (Test-Path -LiteralPath $resultsRoot)) {
    return [pscustomobject]@{ lines = @(); source = 'none' }
  }

  $minimumWriteTime = $TestStartedAt.ToUniversalTime().AddSeconds(-5)
  $candidates = @(
    Get-ChildItem -LiteralPath $resultsRoot -Recurse -File -Filter 'logcat-*.txt' -ErrorAction SilentlyContinue |
      Where-Object { $_.LastWriteTimeUtc -ge $minimumWriteTime } |
      Sort-Object LastWriteTimeUtc -Descending
  )
  foreach ($candidate in $candidates) {
    $lines = @(
      Get-Content -LiteralPath $candidate.FullName -Encoding UTF8 |
        Where-Object {
          $_ -match 'LEGADO_TRACE:' -or $_ -match 'LEGADO_WIRE_TRACE:' -or
          $_ -match 'LEGADO_CONNECTION_TRACE:' -or $_ -match 'LEGADO_COMPRESSION_TRACE:' -or
          $_ -match 'LEGADO_TLS_TRACE:'
        }
    )
    if ($lines.Count -gt 0) {
      return [pscustomobject]@{ lines = $lines; source = $candidate.FullName }
    }
  }
  return [pscustomobject]@{ lines = @(); source = 'none' }
}

function Invoke-AndroidReference {
  param([pscustomobject]$Toolchain, [string]$StageKey)
  if ($SkipAndroid) { Throw-Blocked 'Android 对照被本次调用显式跳过。' }
  $serial = Ensure-AndroidDevice $Toolchain
  $gradle = Join-Path $script:LegadoRoot 'gradlew.bat'
  if (-not (Test-Path -LiteralPath $gradle)) { Throw-Blocked 'Legado Gradle wrapper 不存在。' }
  if (-not (Test-Path -LiteralPath $script:LegadoReferenceGradleInitScript)) {
    Throw-Blocked 'Legado reference Gradle plugin-resolution init script 不存在。'
  }
  if (-not $Toolchain.java17Home -or -not (Test-Path -LiteralPath (Join-Path $Toolchain.java17Home 'bin\javac.exe'))) {
    Throw-Blocked 'Legado Android reference 需要 Java 17 toolchain，但本机未发现可用 JDK 17。'
  }
  $previousJavaHome = $env:JAVA_HOME
  $previousPath = $env:PATH
  $previousGradleOpts = $env:GRADLE_OPTS
  $previousJavaToolOptions = $env:JAVA_TOOL_OPTIONS
  $previousGradleUserHome = $env:GRADLE_USER_HOME
  $previousAndroidHome = $env:ANDROID_HOME
  $previousAndroidSdkRoot = $env:ANDROID_SDK_ROOT
  $locationPushed = $false
  try {
    Push-Location -LiteralPath $script:LegadoRoot
    $locationPushed = $true
    # The pinned Legado Android instrumentation graph is compiled and launched
    # with its verified Java 17 toolchain, not the HarmonyOS JDK 21 toolchain.
    $env:JAVA_HOME = $Toolchain.java17Home
    $env:PATH = "$(Join-Path $Toolchain.java17Home 'bin');$previousPath"
    $env:ANDROID_HOME = $Toolchain.androidSdk
    $env:ANDROID_SDK_ROOT = $Toolchain.androidSdk
    # A failed Gradle transform can retain a workspace handle briefly on
    # Windows. Never require destructive cleanup of a prior run to recover:
    # each Android reference invocation receives its own bounded cache root.
    # Keep that root below the reference checkout. KSP resolves generated
    # inputs relative to the app source root; a system-temp Gradle cache on C:
    # together with this F: checkout reproduces its "different roots" crash.
    # The existing transform-cache recovery below still handles a transient
    # workspace-move failure without broad cleanup.
    $gradleRunId = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $gradleCacheBase = Join-Path $script:LegadoRoot '.manxia-gradle-harness'
    [System.IO.Directory]::CreateDirectory($gradleCacheBase) | Out-Null
    $isolatedGradleHome = Join-Path $gradleCacheBase ("android-gradle-home-$StageKey-$gradleRunId")
    [System.IO.Directory]::CreateDirectory($isolatedGradleHome) | Out-Null
    $env:GRADLE_USER_HOME = $isolatedGradleHome
    $isolatedGradleProperties = Join-Path $isolatedGradleHome 'gradle.properties'
    $java17PathForProperties = $Toolchain.java17Home.Replace('\', '/')
    Write-Utf8Atomic -Path $isolatedGradleProperties -Content (
      "org.gradle.java.installations.paths=$java17PathForProperties`r`n" +
      "org.gradle.workers.max=1`r`n" +
      "org.gradle.parallel=false`r`n" +
      "org.gradle.caching=false`r`n" +
      "org.gradle.vfs.watch=false`r`n" +
      "kotlin.incremental=false`r`n" +
      "ksp.incremental=false`r`n"
    )
    $proxyOptions = Get-JavaProxyOptions
    if ($proxyOptions) {
      $env:GRADLE_OPTS = "$previousGradleOpts $proxyOptions".Trim()
      $env:JAVA_TOOL_OPTIONS = "$previousJavaToolOptions $proxyOptions".Trim()
    }
    [void](Invoke-BoundedNativeCommand -FilePath $Toolchain.adb -ArgumentList @('-s', $serial, 'logcat', '-c') -TimeoutSeconds 30)
    $fixtureForward = Ensure-AndroidFixtureReverseForward -Toolchain $Toolchain -Serial $serial -StageKey $StageKey
    $fixtureUrl = [string]($fixtureForward.fixtureUrl)
    $tlsFixtureForward = Ensure-AndroidFixtureReverseForward -Toolchain $Toolchain -Serial $serial -StageKey $StageKey -Port $script:TlsFixturePort -Scheme 'https' -EvidenceSuffix '-tls'
    $tlsFixtureUrl = [string]($tlsFixtureForward.fixtureUrl)
    $testClassArgument = '-Pandroid.testInstrumentationRunnerArguments.class=io.legado.app.compat.LegadoCompatibilityTraceTest'
    $initialOutputPath = Join-Path $script:EvidenceDirectory "android-legado-gradle-$StageKey.initial.log"
    $retryOutputPath = ''
    $cacheRetryOutputPath = ''
    $crossRootRetryOutputPath = ''
    $testStartedAt = [DateTime]::UtcNow
    $gradleArguments = @(
      ':app:connectedAppDebugAndroidTest',
      $testClassArgument,
      "-Pandroid.testInstrumentationRunnerArguments.fixtureUrl=$fixtureUrl",
      "-Pandroid.testInstrumentationRunnerArguments.tlsFixtureUrl=$tlsFixtureUrl",
      '--no-daemon',
      '--no-parallel',
      '--max-workers=1',
      '--no-build-cache',
      '--init-script',
      $script:LegadoReferenceGradleInitScript
    )
    $gradleResult = Invoke-BoundedNativeCommand -FilePath $gradle -ArgumentList $gradleArguments -TimeoutSeconds 1800 -WorkingDirectory $script:LegadoRoot -Batch
    $output = $gradleResult.output
    $gradleExitCode = $gradleResult.exitCode
    Write-Utf8Atomic -Path $initialOutputPath -Content $output
    if ($gradleExitCode -ne 0 -and $output -match 'gradle-[0-9.]+-bin\.zip' -and $output -match 'ConnectException') {
      $recoveryEvidence = Ensure-LegadoGradleDistribution -Gradle $gradle -StageKey $StageKey
      $retryOutputPath = Join-Path $script:EvidenceDirectory "android-legado-gradle-$StageKey.retry.log"
      $gradleResult = Invoke-BoundedNativeCommand -FilePath $gradle -ArgumentList $gradleArguments -TimeoutSeconds 1800 -WorkingDirectory $script:LegadoRoot -Batch
      $output = $gradleResult.output
      $gradleExitCode = $gradleResult.exitCode
      Write-Utf8Atomic -Path $retryOutputPath -Content $output
      if ($recoveryEvidence) { $script:LastFailureEvidence = $recoveryEvidence }
    }
    if ($gradleExitCode -ne 0 -and $output -match 'Could not move temporary workspace') {
      $cacheRecoveryEvidence = Clear-IsolatedGradleTransformCache -GradleHome $isolatedGradleHome -StageKey $StageKey
      $cacheRetryOutputPath = Join-Path $script:EvidenceDirectory "android-legado-gradle-$StageKey.transform-retry.log"
      $gradleResult = Invoke-BoundedNativeCommand -FilePath $gradle -ArgumentList $gradleArguments -TimeoutSeconds 1800 -WorkingDirectory $script:LegadoRoot -Batch
      $output = $gradleResult.output
      $gradleExitCode = $gradleResult.exitCode
      Write-Utf8Atomic -Path $cacheRetryOutputPath -Content $output
      if ($cacheRecoveryEvidence) { $script:LastFailureEvidence = $cacheRecoveryEvidence }
    }
    if ($gradleExitCode -ne 0 -and $output -match 'Could not move temporary workspace') {
      # Gradle 8.13's artifact-transform workspace move can fail on the
      # project volume even after the precise transform cache cleanup. Retry
      # once in the system-temp cache, but keep incremental KSP disabled so
      # the earlier cross-root KSP failure cannot return silently.
      $crossRootBase = Join-Path ([System.IO.Path]::GetTempPath()) 'manxia-legado-gradle'
      [System.IO.Directory]::CreateDirectory($crossRootBase) | Out-Null
      $crossRootGradleHome = Join-Path $crossRootBase ("android-gradle-home-$StageKey-crossroot-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())")
      [System.IO.Directory]::CreateDirectory($crossRootGradleHome) | Out-Null
      $env:GRADLE_USER_HOME = $crossRootGradleHome
      $crossRootProperties = Join-Path $crossRootGradleHome 'gradle.properties'
      Write-Utf8Atomic -Path $crossRootProperties -Content (
        "org.gradle.java.installations.paths=$java17PathForProperties`r`n" +
        "org.gradle.workers.max=1`r`n" +
        "org.gradle.parallel=false`r`n" +
        "org.gradle.caching=false`r`n" +
        "org.gradle.vfs.watch=false`r`n" +
        "kotlin.incremental=false`r`n" +
        "ksp.incremental=false`r`n"
      )
      $crossRootRetryOutputPath = Join-Path $script:EvidenceDirectory "android-legado-gradle-$StageKey.cross-root-retry.log"
      $gradleResult = Invoke-BoundedNativeCommand -FilePath $gradle -ArgumentList $gradleArguments -TimeoutSeconds 1800 -WorkingDirectory $script:LegadoRoot -Batch
      $output = $gradleResult.output
      $gradleExitCode = $gradleResult.exitCode
      Write-Utf8Atomic -Path $crossRootRetryOutputPath -Content $output
    }
    if ($gradleExitCode -ne 0) {
      $script:LastFailureEvidence = if (Test-Path -LiteralPath $crossRootRetryOutputPath) { $crossRootRetryOutputPath } elseif (Test-Path -LiteralPath $cacheRetryOutputPath) { $cacheRetryOutputPath } elseif (Test-Path -LiteralPath $retryOutputPath) { $retryOutputPath } else { $initialOutputPath }
      $failureMatch = (($output -split "`r?`n") | Select-String -Pattern 'FAILURE:|error:|Exception|Could not' | Select-Object -First 1)
      $failureLine = if ($null -ne $failureMatch) { [string]$failureMatch.Line } else { '没有可识别的 Gradle 错误行。' }
      throw "Legado instrumentation 失败：$failureLine"
    }
    $traceResult = Get-AndroidReferenceTrace -Toolchain $Toolchain -Serial $serial -TestStartedAt $testStartedAt
    $traceLines = @($traceResult.lines)
    if ($traceLines.Count -eq 0) { throw 'Legado instrumentation 没有产生 LEGADO_TRACE。' }
    $tracePath = Join-Path $script:EvidenceDirectory "android-legado-trace-$StageKey.log"
    Write-Utf8Atomic -Path $tracePath -Content ($traceLines -join "`r`n")
    $traceMetadataPath = Join-Path $script:EvidenceDirectory "android-legado-trace-$StageKey.metadata.json"
    $traceMetadata = [pscustomobject][ordered]@{
      source = [string]$traceResult.source
      traceCount = $traceLines.Count
      fixtureUrl = $fixtureUrl
      tlsFixtureUrl = $tlsFixtureUrl
      capturedAfter = $testStartedAt.ToString('o')
    }
    Write-Utf8Atomic -Path $traceMetadataPath -Content ($traceMetadata | ConvertTo-Json -Depth 4)
    return [pscustomobject]@{ serial = $serial; evidence = $tracePath }
  } finally {
    if ($locationPushed) { Pop-Location }
    $env:JAVA_HOME = $previousJavaHome
    $env:PATH = $previousPath
    $env:GRADLE_OPTS = $previousGradleOpts
    $env:JAVA_TOOL_OPTIONS = $previousJavaToolOptions
    $env:GRADLE_USER_HOME = $previousGradleUserHome
    $env:ANDROID_HOME = $previousAndroidHome
    $env:ANDROID_SDK_ROOT = $previousAndroidSdkRoot
  }
}

function Get-HarmonyDevice {
  param([pscustomobject]$Toolchain)
  $deviceResult = Invoke-LegadoNativeProcess -FilePath $Toolchain.hdc -ArgumentList @('list', 'targets') -TimeoutSeconds 15
  if ($deviceResult.timedOut) {
    throw 'HDC device discovery timed out after 15 seconds.'
  }
  if ($deviceResult.exitCode -ne 0) {
    return ''
  }
  $lines = @($deviceResult.stdout -split "`r?`n")
  foreach ($line in $lines) {
    $candidate = ([string]$line).Trim()
    if ($candidate -and $candidate -notmatch '^\[') { return $candidate }
  }
  return ''
}

function Ensure-HarmonyFixtureReverseForward {
  param([pscustomobject]$Toolchain, [string]$Device, [int]$Port = $script:FixturePort)
  $portNode = "tcp:$Port"
  $forwardResult = Invoke-BoundedNativeCommand -FilePath $Toolchain.hdc -ArgumentList @('-t', $Device, 'rport', $portNode, $portNode) -TimeoutSeconds 30
  $forwardOutput = $forwardResult.output
  $forwardExitCode = $forwardResult.exitCode
  $forwardListResult = Invoke-BoundedNativeCommand -FilePath $Toolchain.hdc -ArgumentList @('-t', $Device, 'fport', 'ls') -TimeoutSeconds 30
  $forwardList = $forwardListResult.output
  $expectedEntry = [regex]::Escape($portNode) + '\s+' + [regex]::Escape($portNode) + '\s+\[Reverse\]'
  if ($forwardExitCode -ne 0 -or $forwardList -notmatch $expectedEntry) {
    throw "HarmonyOS fixture 反向端口转发失败：$forwardOutput"
  }
}

function Install-HarmonyHap {
  param(
    [pscustomobject]$Toolchain,
    [string]$Device,
    [string]$HapPath,
    [string]$EvidencePath
  )
  $installResult = Invoke-BoundedNativeCommand -FilePath $Toolchain.hdc -ArgumentList @('-t', $Device, 'install', '-r', $HapPath) -TimeoutSeconds 300
  $installOutput = $installResult.output
  $installExitCode = $installResult.exitCode
  Write-Utf8Atomic -Path $EvidencePath -Content $installOutput
  if ($installExitCode -ne 0 -or $installOutput -notmatch 'msg:install bundle successfully') {
    throw "HarmonyOS HAP 安装失败：$installOutput"
  }
}

function Get-HarmonyTestSourceSnapshot {
  $sourceRoot = Join-Path $script:RepoRoot 'entry\src\ohosTest'
  if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container)) {
    Throw-Blocked 'HarmonyOS ohosTest 源码目录不存在。'
  }
  $files = @(Get-ChildItem -LiteralPath $sourceRoot -Recurse -File | Sort-Object FullName)
  if ($files.Count -eq 0) {
    Throw-Blocked 'HarmonyOS ohosTest 源码目录为空。'
  }
  $latest = $files | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
  $lines = New-Object 'System.Collections.Generic.List[string]'
  foreach ($file in $files) {
    $relative = $file.FullName.Substring($sourceRoot.Length).TrimStart('\\').Replace('\\', '/')
    $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    [void]$lines.Add(('{0}|{1}|{2}' -f $relative, $file.Length, $hash))
  }
  $manifestText = [string]::Join("`n", $lines.ToArray())
  $manifestBytes = [System.Text.UTF8Encoding]::new($false).GetBytes($manifestText)
  $manifestHash = [System.Security.Cryptography.SHA256]::Create().ComputeHash($manifestBytes)
  [pscustomobject][ordered]@{
    root = $sourceRoot
    fileCount = $files.Count
    latestWriteTimeUtc = $latest.LastWriteTimeUtc.ToString('o')
    sha256 = ([System.BitConverter]::ToString($manifestHash).Replace('-', '')).ToLowerInvariant()
  }
}

function Get-HarmonyMainSourceLatestWriteTime {
  $sourceRoot = Join-Path $script:RepoRoot 'entry\src\main'
  $latest = Get-ChildItem -LiteralPath $sourceRoot -Recurse -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
  if ($null -eq $latest) { return [DateTimeOffset]::MinValue }
  return [DateTimeOffset]$latest.LastWriteTimeUtc
}

function Get-HarmonyTestHapIntegrity {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    return [pscustomobject][ordered]@{ valid = $false; reason = 'missing'; path = $Path; sha256 = ''; lastWriteTimeUtc = ''; length = 0; requiredEntries = @() }
  }
  $file = Get-Item -LiteralPath $Path
  $requiredEntries = @('module.json', 'pack.info', 'resources.index', 'ets/modules.abc')
  $archive = $null
  try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($file.FullName)
    $entryNames = @($archive.Entries | ForEach-Object { $_.FullName })
    $missing = @($requiredEntries | Where-Object { $entryNames -notcontains $_ })
    $valid = $file.Length -gt 0 -and $missing.Count -eq 0
    $reason = if ($valid) { 'ok' } else { 'missing_required_entries' }
    return [pscustomobject][ordered]@{
      valid = $valid
      reason = $reason
      path = $file.FullName
      sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
      lastWriteTimeUtc = $file.LastWriteTimeUtc.ToString('o')
      length = $file.Length
      requiredEntries = @($requiredEntries | Where-Object { $entryNames -contains $_ })
      missingEntries = $missing
    }
  } catch {
    return [pscustomobject][ordered]@{ valid = $false; reason = 'invalid_zip'; path = $file.FullName; sha256 = ''; lastWriteTimeUtc = $file.LastWriteTimeUtc.ToString('o'); length = $file.Length; requiredEntries = @(); missingEntries = $requiredEntries; error = $_.Exception.Message }
  } finally {
    if ($null -ne $archive) { $archive.Dispose() }
  }
}

function Assert-HarmonyTestHapFresh {
  param(
    [string]$Path,
    [pscustomobject]$SourceSnapshot,
    [DateTimeOffset]$BuildStartedAt,
    [pscustomobject]$PreviousArtifact
  )
  $integrity = Get-HarmonyTestHapIntegrity -Path $Path
  if (-not [bool]$integrity.valid) { throw "HarmonyOS ohosTest HAP 完整性校验失败：$($integrity.reason)" }
  $hapTime = [DateTimeOffset]::Parse([string]$integrity.lastWriteTimeUtc)
  $sourceTime = [DateTimeOffset]::Parse([string]$SourceSnapshot.latestWriteTimeUtc)
  if ($hapTime -lt $sourceTime) {
    throw "HarmonyOS ohosTest HAP 早于当前测试源码：hap=$($integrity.lastWriteTimeUtc);source=$($SourceSnapshot.latestWriteTimeUtc)"
  }
  $wasStale = $null -ne $PreviousArtifact -and ([DateTimeOffset]::Parse([string]$PreviousArtifact.lastWriteTimeUtc) -lt $sourceTime)
  if ($wasStale -and $hapTime -lt $BuildStartedAt) {
    throw "HarmonyOS ohosTest HAP 未在源码变更后的受控构建中生成：buildStartedAt=$BuildStartedAt;hap=$($integrity.lastWriteTimeUtc)"
  }
  return $integrity
}

function Test-HarmonyArkWebSuccessTrace {
  param([string]$TraceText)
  $requiredMarkers = @(
    '(?i)MANXIA_LEGADO_TRACE_STATUS:fixture-arkweb-webjs-cookie\|ark_web\|none\|true',
    '(?i)MANXIA_LEGADO_TRACE_STATUS:fixture-arkweb-source-regex\|ark_web\|none\|(true|false)',
    '(?i)MANXIA_LEGADO_TRACE_STATUS:fixture-arkweb-cookie-roundtrip\|ark_web\|none\|(true|false)',
    '(?i)MANXIA_LEGADO_TRACE_STATUS:fixture-runtime-scope-replay-isolation\|passed\|900150983cd24fb0d6963f7d28e17f72',
    '(?i)MANXIA_LEGADO_TRACE_STATUS:fixture-runtime-workflow-binding-contract\|passed\|source-book-chapter-key-page-variable',
    '(?i)MANXIA_LEGADO_TRACE_STATUS:fixture-runtime-java-api-contract\|passed\|get-encodeURI-md5-source-fields-time-format-uuid',
    '(?i)MANXIA_LEGADO_TRACE_STATUS:fixture-runtime-high-frequency-api-contract\|passed\|t2s-hexDecodeToString-getStringList',
    '(?i)MANXIA_LEGADO_TRACE_STATUS:fixture-runtime-context-api-contract\|passed\|setContent-getWebViewUA',
    '(?i)MANXIA_LEGADO_TRACE_STATUS:fixture-runtime-nested-webview-contract\|passed\|explicit-unsupported-no-empty-fallback',
    '(?i)MANXIA_LEGADO_TRACE_STATUS:fixture-runtime-symmetric-crypto-contract\|passed\|aes-des-3des-legacy-wrapper',
    '(?i)MANXIA_LEGADO_TRACE_STATUS:fixture-runtime-hmac-contract\|passed\|hmac-md5-sha256-structured-failure',
    '(?i)MANXIA_LEGADO_TRACE_STATUS:fixture-runtime-postfix-js-contract\|passed\|json-postfix-top-level-search',
    '(?i)MANXIA_LEGADO_TRACE_STATUS:fixture-runtime-json-prefix-js-contract\|passed\|json-prefix-result-and-put',
    '(?i)MANXIA_LEGADO_TRACE_STATUS:fixture-runtime-top-level-js-boolean-contract\|passed\|template-boolean-url-option',
    '(?i)MANXIA_LEGADO_TRACE_STATUS:fixture-runtime-dynamic-eval-probe\|passed\|direct-source-binding-source-comment',
    '(?i)MANXIA_LEGADO_TRACE_STATUS:fixture-runtime-toc-js-object-projection\|passed\|elements=2;namePresent=true;urlPresent=true;infoPresent=false',
    '(?i)MANXIA_LEGADO_TRACE_STATUS:fixture-book-info-init-content-transition\|passed\|inner-document-visible'
  )
  foreach ($marker in $requiredMarkers) {
    if ($TraceText -notmatch $marker) {
      return $false
    }
  }
  return $true
}

function Invoke-HarmonyArkWebFixture {
  param([pscustomobject]$Toolchain, [string]$Device, [string]$StageKey)
  $startEvidencePath = Join-Path $script:EvidenceDirectory "harmony-arkweb-fixture-start-$StageKey.log"
  $traceEvidencePath = Join-Path $script:EvidenceDirectory "harmony-arkweb-fixture-$StageKey.log"
  $startResult = Invoke-BoundedNativeCommand -FilePath $Toolchain.hdc -ArgumentList @('-t', $Device, 'shell', 'aa', 'start', '-a', 'LegadoArkWebConformanceAbility', '-b', 'com.dlzz.manxia', '-m', 'entry') -TimeoutSeconds 30
  $startOutput = $startResult.output
  $startExitCode = $startResult.exitCode
  Write-Utf8Atomic -Path $startEvidencePath -Content $startOutput
  if ($startOutput -match 'Error Code:\s*10106102' -or $startOutput -match '(?i)device screen is locked') {
    $script:LastFailureEvidence = $startEvidencePath
    Throw-Blocked 'HarmonyOS 设备屏幕被锁定；解锁设备后可自动继续执行 ArkWeb fixture。'
  }
  if ($startExitCode -ne 0 -or $startOutput -match '(?i)failed to start ability') {
    $script:LastFailureEvidence = $startEvidencePath
    throw "HarmonyOS ArkWeb fixture 启动失败：$($startOutput | Select-Object -First 1)"
  }

  $deadline = [DateTimeOffset]::UtcNow.AddSeconds(40)
  $lastSnapshot = ''
  while ([DateTimeOffset]::UtcNow -lt $deadline) {
    $hilogResult = Invoke-BoundedNativeCommand -FilePath $Toolchain.hdc -ArgumentList @('-t', $Device, 'shell', 'hilog', '-x') -TimeoutSeconds 30
    $lastSnapshot = [string]$hilogResult.stdout
    if ($lastSnapshot -match 'MANXIA_LEGADO_ARKWEB_FIXTURE_FAILED:') {
      Write-Utf8Atomic -Path $traceEvidencePath -Content $lastSnapshot
      $script:LastFailureEvidence = $traceEvidencePath
      throw 'HarmonyOS ArkWeb fixture 报告了执行失败。'
    }
    if (Test-HarmonyArkWebSuccessTrace -TraceText $lastSnapshot) {
      Write-Utf8Atomic -Path $traceEvidencePath -Content $lastSnapshot
      return $traceEvidencePath
    }
    Start-Sleep -Milliseconds 500
  }

  Write-Utf8Atomic -Path $traceEvidencePath -Content $lastSnapshot
  $script:LastFailureEvidence = $traceEvidencePath
  throw 'HarmonyOS ArkWeb fixture 未在 40 秒内产生成功 trace。'
}

function Invoke-HarmonyConformance {
  param([pscustomobject]$Toolchain, [string]$StageKey)
  if ($SkipHarmony) { Throw-Blocked 'HarmonyOS 对照被本次调用显式跳过。' }
  $device = Get-HarmonyDevice $Toolchain
  if (-not $device) { Throw-Blocked '未检测到 HarmonyOS 设备。' }
  Ensure-HarmonyFixtureReverseForward -Toolchain $Toolchain -Device $device
  Ensure-HarmonyFixtureReverseForward -Toolchain $Toolchain -Device $device -Port $script:TlsFixturePort
  $previousSdk = $env:DEVECO_SDK_HOME
  try {
    $env:DEVECO_SDK_HOME = 'F:\DevEco Studio\sdk'
    $mainHap = Get-ChildItem -LiteralPath (Join-Path $script:RepoRoot 'entry\build') -Recurse -Filter 'entry-default-signed.hap' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $mainSourceLatestWriteTime = Get-HarmonyMainSourceLatestWriteTime
    # Stage0 is the device-facing baseline. It must package the current V2
    # sources before installing, otherwise a freshly built ohosTest HAP can be
    # paired with a stale main HAP and produce invalid conformance evidence.
    $mainHapIsStale = $false
    if ($null -ne $mainHap) {
      $mainHapIsStale = ([DateTimeOffset]$mainHap.LastWriteTimeUtc) -lt $mainSourceLatestWriteTime
    }
    $requireFullMainBuild = $mainHapIsStale -or $StageKey -eq 'stage0' -or $StageKey -eq 'stage6' -or $StageKey -eq 'stage7' -or $StageKey -eq 'stage8'
    if ($null -eq $mainHap -or $requireFullMainBuild) {
      $mainBuildArguments = @('assembleApp', '-p', 'product=default', '-p', 'buildMode=debug', '--no-daemon', '--stacktrace')
      $mainBuildResult = Invoke-BoundedNativeCommand -FilePath $Toolchain.hvigor -ArgumentList $mainBuildArguments -TimeoutSeconds 1800 -WorkingDirectory $script:RepoRoot -Batch
      $mainBuildOutput = $mainBuildResult.output
      $mainBuildExitCode = $mainBuildResult.exitCode
      if ($mainBuildExitCode -ne 0 -and $mainBuildOutput -match 'EBUSY: resource busy or locked.*build\.log') {
        # Hvigor's rolling build log can briefly remain open after another
        # no-daemon invocation.  This is an environment race, not an ArkTS
        # conformance result.  Stop only the exact Hvigor daemon scope and
        # retry once before reporting a real build failure.
        [void](Invoke-BoundedNativeCommand -FilePath $Toolchain.hvigor -ArgumentList @('--stop-daemon-all') -TimeoutSeconds 60 -WorkingDirectory $script:RepoRoot -Batch)
        Start-Sleep -Seconds 2
        $mainRetryResult = Invoke-BoundedNativeCommand -FilePath $Toolchain.hvigor -ArgumentList $mainBuildArguments -TimeoutSeconds 1800 -WorkingDirectory $script:RepoRoot -Batch
        $mainRetryOutput = $mainRetryResult.output
        $mainBuildOutput = "检测到 Hvigor build.log 短暂占用，已自动重试一次。`r`n$mainRetryOutput"
        $mainBuildExitCode = $mainRetryResult.exitCode
      }
      if ($mainBuildExitCode -ne 0) {
        throw "HarmonyOS 主应用构建失败：$($mainBuildOutput | Select-String -Pattern 'ERROR|Error|FAILURE' | Select-Object -First 1)"
      }
      $mainHap = Get-ChildItem -LiteralPath (Join-Path $script:RepoRoot 'entry\build') -Recurse -Filter 'entry-default-signed.hap' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    }
    if ($null -eq $mainHap) { Throw-Blocked '未找到主应用 signed HAP。' }
    $testSourceSnapshot = Get-HarmonyTestSourceSnapshot
    $testHapBefore = Get-ChildItem -LiteralPath (Join-Path $script:RepoRoot 'entry\build') -Recurse -Filter '*ohosTest-signed.hap' -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    $testArtifactBefore = $null
    if ($null -ne $testHapBefore) {
      $candidateArtifactBefore = Get-HarmonyTestHapIntegrity -Path $testHapBefore.FullName
      if ([bool]$candidateArtifactBefore.valid) {
        $testArtifactBefore = $candidateArtifactBefore
      }
    }
    $testBuildStartedAt = [DateTimeOffset]::UtcNow
    $testBuildArguments = @('assembleHap', '-p', 'module=entry@ohosTest', '-p', 'product=default', '-p', 'buildMode=debug', '--no-daemon', '--stacktrace')
    # Hvigor has been observed to package the test HAP and then remain silent.
    # Keep a bounded wait; a timed-out wrapper is accepted only when the
    # resulting archive is structurally valid and fresh against the source.
    $testBuildResult = Invoke-BoundedNativeCommand -FilePath $Toolchain.hvigor -ArgumentList $testBuildArguments -TimeoutSeconds 600 -WorkingDirectory $script:RepoRoot -Batch
    $testBuildOutput = $testBuildResult.output
    $testBuildExitCode = $testBuildResult.exitCode
    if ($testBuildExitCode -ne 0 -and $testBuildOutput -match 'EBUSY: resource busy or locked.*build\.log') {
      [void](Invoke-BoundedNativeCommand -FilePath $Toolchain.hvigor -ArgumentList @('--stop-daemon-all') -TimeoutSeconds 60 -WorkingDirectory $script:RepoRoot -Batch)
      Start-Sleep -Seconds 2
      $testRetryResult = Invoke-BoundedNativeCommand -FilePath $Toolchain.hvigor -ArgumentList $testBuildArguments -TimeoutSeconds 600 -WorkingDirectory $script:RepoRoot -Batch
      $testRetryOutput = $testRetryResult.output
      $testBuildOutput = "检测到 Hvigor build.log 短暂占用，已自动重试一次。`r`n$testRetryOutput"
      $testBuildExitCode = $testRetryResult.exitCode
      $testBuildResult = $testRetryResult
    }
    if ($testBuildExitCode -ne 0 -and -not [bool]$testBuildResult.timedOut) {
      throw "HarmonyOS ohosTest 构建失败：$($testBuildOutput | Select-String -Pattern 'ERROR|Error|FAILURE' | Select-Object -First 1)"
    }
    $testHap = Get-ChildItem -LiteralPath (Join-Path $script:RepoRoot 'entry\build') -Recurse -Filter '*ohosTest-signed.hap' -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    if ($null -eq $testHap) { Throw-Blocked '未找到 ohosTest HAP；测试目标尚未接入构建产物。' }
    $testArtifact = Assert-HarmonyTestHapFresh -Path $testHap.FullName -SourceSnapshot $testSourceSnapshot -BuildStartedAt $testBuildStartedAt -PreviousArtifact $testArtifactBefore
    $testBuildTerminal = if ([bool]$testBuildResult.timedOut) { 'artifact_complete_after_wrapper_timeout' } else { 'process_exit' }
    $artifactEvidencePath = Join-Path $script:EvidenceDirectory "harmony-hap-artifacts-$StageKey.json"
    $artifactEvidence = [pscustomobject][ordered]@{
      schemaVersion = 1
      stage = $StageKey
      build = [pscustomobject][ordered]@{
        startedAtUtc = $testBuildStartedAt.ToString('o')
        terminal = $testBuildTerminal
        timedOut = [bool]$testBuildResult.timedOut
        timeoutSeconds = 600
      }
      ohosTestSource = $testSourceSnapshot
      mainHap = [pscustomobject][ordered]@{
        fileName = $mainHap.Name
        sha256 = (Get-FileHash -LiteralPath $mainHap.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        lastWriteTimeUtc = $mainHap.LastWriteTimeUtc.ToString('o')
        sourceLatestWriteTimeUtc = $mainSourceLatestWriteTime.ToString('o')
        freshAgainstSource = ([DateTimeOffset]$mainHap.LastWriteTimeUtc) -ge $mainSourceLatestWriteTime
      }
      ohosTestHap = [pscustomobject][ordered]@{
        fileName = $testHap.Name
        sha256 = $testArtifact.sha256
        lastWriteTimeUtc = $testHap.LastWriteTimeUtc.ToString('o')
        length = $testArtifact.length
        integrity = $testArtifact.reason
        freshAgainstSource = $true
      }
    }
    Write-Utf8Atomic -Path $artifactEvidencePath -Content ($artifactEvidence | ConvertTo-Json -Depth 5)
    Install-HarmonyHap -Toolchain $Toolchain -Device $device -HapPath $mainHap.FullName -EvidencePath (Join-Path $script:EvidenceDirectory "harmony-main-install-$StageKey.log")
    Install-HarmonyHap -Toolchain $Toolchain -Device $device -HapPath $testHap.FullName -EvidencePath (Join-Path $script:EvidenceDirectory "harmony-ohosTest-install-$StageKey.log")
    [void](Invoke-BoundedNativeCommand -FilePath $Toolchain.hdc -ArgumentList @('-t', $device, 'shell', 'hilog', '-r') -TimeoutSeconds 30)
    $testResult = Invoke-BoundedNativeCommand -FilePath $Toolchain.hdc -ArgumentList @('-t', $device, 'shell', 'aa', 'test', '-b', 'com.dlzz.manxia', '-m', 'entry_test') -TimeoutSeconds 900
    $testOutput = $testResult.output
    $testExitCode = $testResult.exitCode
    $testOutputPath = Join-Path $script:EvidenceDirectory "harmony-ohosTest-result-$StageKey.log"
    Write-Utf8Atomic -Path $testOutputPath -Content $testOutput
    $isScreenLocked = $testOutput -match 'Error Code:\s*10106102' -or
      $testOutput -match '(?i)device screen is locked'
    if ($isScreenLocked) {
      $script:LastFailureEvidence = $testOutputPath
      Throw-Blocked 'HarmonyOS 设备屏幕被锁定；解锁设备后可自动继续执行测试。'
    }
    $hasTestFailure = $testOutput -match 'TestFinished-ResultCode:\s*-[1-9][0-9]*' -or
      $testOutput -match 'OHOS_REPORT_CODE:\s*-[1-9][0-9]*' -or
      $testOutput -match 'Failure:\s*[1-9][0-9]*' -or
      $testOutput -match 'Error:\s*[1-9][0-9]*'
    if ($testExitCode -ne 0 -or $hasTestFailure) {
      $script:LastFailureEvidence = $testOutputPath
      throw "HarmonyOS aa test 失败：$($testOutput | Select-Object -First 1)"
    }
    if ($StageKey -eq 'stage3') {
      Invoke-HarmonyArkWebFixture -Toolchain $Toolchain -Device $device -StageKey $StageKey | Out-Null
    }
    $hilogResult = Invoke-BoundedNativeCommand -FilePath $Toolchain.hdc -ArgumentList @('-t', $device, 'shell', 'hilog', '-x') -TimeoutSeconds 60
    $hilog = [string]$hilogResult.stdout
    $traceLines = @(
      $hilog -split "`r?`n" |
      Where-Object {
        $_ -match 'MANXIA_LEGADO_TRACE:' -or $_ -match 'MANXIA_LEGADO_TRACE_STATUS:' -or
        $_ -match 'MANXIA_LEGADO_WIRE_TRACE:' -or $_ -match 'MANXIA_LEGADO_CONNECTION_TRACE:' -or
        $_ -match 'MANXIA_LEGADO_COMPRESSION_TRACE:' -or $_ -match 'MANXIA_LEGADO_TLS_TRACE:'
      }
    )
    if ($traceLines.Count -eq 0) { throw 'HarmonyOS conformance 没有产生 MANXIA_LEGADO_TRACE。' }
    $tracePath = Join-Path $script:EvidenceDirectory "harmony-ohos-trace-$StageKey.log"
    Write-Utf8Atomic -Path $tracePath -Content (($testOutput + "`r`n" + ($traceLines -join "`r`n")))
    return [pscustomobject]@{ device = $device; evidence = $tracePath; artifactEvidence = $artifactEvidencePath }
  } finally {
    $env:DEVECO_SDK_HOME = $previousSdk
  }
}

function Invoke-DeviceGate {
  param([string]$StageKey)
  $toolchain = Ensure-Toolchain
  Start-TlsFixture
  $android = Invoke-AndroidReference -Toolchain $toolchain -StageKey $StageKey
  $harmony = Invoke-HarmonyConformance -Toolchain $toolchain -StageKey $StageKey
  return @(
    (New-Check 'Legado Android instrumentation trace' 'passed' "设备=$($android.serial)" $android.evidence),
    (New-Check 'HarmonyOS HAP artifact binding' 'passed' "主 HAP 与 ohosTest HAP 的 SHA-256 已记录并随本阶段安装。" $harmony.artifactEvidence),
    (New-Check 'HarmonyOS ohosTest trace' 'passed' "设备=$($harmony.device)" $harmony.evidence)
  )
}

function Test-Stage7RealUserEvidence {
  if (-not (Test-Path -LiteralPath $script:Stage7RealUserEvidencePath)) {
    Throw-Blocked '缺少脱敏的真实 V2 用户路径证据；阶段 7 不得仅凭构建与 fixture 通过。'
  }
  $raw = [System.IO.File]::ReadAllText($script:Stage7RealUserEvidencePath, [System.Text.UTF8Encoding]::new($false))
  if ($raw -match '(?i)cookie|authorization|password|https?://|<\/?[a-z]') {
    Throw-Blocked '真实 V2 用户路径证据包含可能敏感的 URL、正文或凭据，已拒绝作为阶段证据。'
  }
  try {
    $evidence = $raw | ConvertFrom-Json
  } catch {
    Throw-Blocked '真实 V2 用户路径证据不是有效 JSON。'
  }
  if ([int]$evidence.schemaVersion -ne 4) {
    Throw-Blocked '真实 V2 用户路径证据版本不匹配，拒绝复用旧证据。'
  }
  if ([string]$evidence.sourcePackageSha256 -ne [string]$script:State.baseline.sourcePackageSha256) {
    Throw-Blocked '真实 V2 用户路径证据与当前书源包 SHA-256 不匹配。'
  }
  if ([string]$evidence.policy -ne 'v2_full_cutover') {
    Throw-Blocked '真实 V2 用户路径未在 V2_FULL_CUTOVER 策略下执行。'
  }
  if ([string]$evidence.uiScope -ne 'explicit_page_marker_and_header_scope') {
    Throw-Blocked '真实 V2 用户路径没有证明当前页面标识和标题栏作用域，不能排除导航栈历史节点误判。'
  }
  $candidateSelection = Get-OptionalProperty -Object $evidence -Name 'candidateSelection'
  $candidateFailures = Get-OptionalProperty -Object $evidence -Name 'candidateFailures'
  $ruleTreeSafe = Get-OptionalProperty -Object $candidateSelection -Name 'ruleTreeSafe'
  $selectedCandidates = Get-OptionalProperty -Object $candidateSelection -Name 'selected'
  if ($null -eq $candidateSelection -or
    [int]$ruleTreeSafe -le 0 -or
    [int]$selectedCandidates -le 0 -or
    [int]$selectedCandidates -gt [int]$ruleTreeSafe) {
    Throw-Blocked '真实 V2 用户路径没有证明候选书源经过完整规则树的安全筛选。'
  }
  if ($null -eq $candidateFailures) {
    Throw-Blocked '真实 V2 用户路径缺少脱敏候选失败分类。'
  }
  if ([string]$evidence.traceEvidence -ne 'persisted_workflow_summary') {
    Throw-Blocked '真实 V2 用户路径没有使用按工作流持久化的脱敏 trace 证据。'
  }
  if ([string]$evidence.readerPresentation -ne 'readable') {
    Throw-Blocked '真实 V2 用户路径未证明正文已按阅读器语义交付。'
  }
  if ($evidence.tracePersistence -eq $null -or $evidence.tracePersistence.beforeRestart -ne $true -or $evidence.tracePersistence.afterRestart -ne $true) {
    Throw-Blocked '真实 V2 用户路径未证明 trace 摘要可在应用重启后恢复。'
  }
  $requiredWorkflows = @('search', 'book_info', 'toc', 'content')
  $records = @($evidence.workflows)
  foreach ($workflow in $requiredWorkflows) {
    $record = @($records | Where-Object { [string]$_.workflow -eq $workflow } | Select-Object -First 1)
    if ($record.Count -ne 1) {
      Throw-Blocked "真实 V2 用户路径缺少 $workflow workflow 证据。"
    }
    if ([string]$record[0].errorCode -ne 'none' -or [int]$record[0].statusCode -lt 200 -or [int]$record[0].statusCode -ge 400) {
      Throw-Blocked "真实 V2 用户路径的 $workflow 没有成功完成。"
    }
    if ([string]$record[0].outputKind -ne 'ui_and_trace_verified') {
      Throw-Blocked "真实 V2 用户路径的 $workflow 没有经界面和 V2 trace 双重验证的输出摘要。"
    }
  }
  return New-Check '真实书源 V2 普通用户连续路径' 'passed' '全局 V2 默认策略下已验证搜索、详情、目录、正文、阅读器交付和重启后的脱敏 trace。' $script:Stage7RealUserEvidencePath
}

function Test-Stage7DiagnosticEvidence {
  if (-not (Test-Path -LiteralPath $script:Stage7DiagnosticEvidencePath)) {
    Throw-Blocked '阶段 7 失败后没有生成脱敏诊断；无法执行原版 Legado 同端点差分。'
  }
  $raw = [System.IO.File]::ReadAllText($script:Stage7DiagnosticEvidencePath, [System.Text.UTF8Encoding]::new($false))
  if ($raw -match '(?i)cookie|authorization|password|https?://|</?[a-z]') {
    Throw-Blocked '阶段 7 脱敏诊断包含可能敏感的 URL、正文或凭据，已拒绝执行对照。'
  }
  try {
    $diagnostic = $raw | ConvertFrom-Json
  } catch {
    Throw-Blocked '阶段 7 脱敏诊断不是有效 JSON。'
  }
  if ([int]$diagnostic.schemaVersion -ne 2) {
    Throw-Blocked '阶段 7 脱敏诊断版本不匹配，拒绝复用旧诊断。'
  }
  if ([string]$diagnostic.sourcePackageSha256 -ne [string]$script:State.baseline.sourcePackageSha256) {
    Throw-Blocked '阶段 7 脱敏诊断与当前书源包 SHA-256 不匹配。'
  }
  if ([string]$diagnostic.policy -ne 'v2_full_cutover' -or
    [string]$diagnostic.candidateSelectorVersion -ne 'pure_text_rule_tree_v3') {
    Throw-Blocked '阶段 7 脱敏诊断未证明其来自全量 V2 与完整规则树安全筛选。'
  }
  $records = @($diagnostic.candidateAttemptRecords)
  if ($records.Count -le 0) {
    Throw-Blocked '阶段 7 脱敏诊断缺少可复核的候选尝试记录。'
  }
  foreach ($record in $records) {
    if ([string]$record.sourceHash -notmatch '^[A-F0-9]{64}$' -or
      [int]$record.keywordIndex -lt 0 -or [int]$record.keywordIndex -gt 3 -or
      [string]$record.outcome.Length -eq 0) {
      Throw-Blocked '阶段 7 脱敏诊断包含无效候选标识或结果分类。'
    }
  }
  return $diagnostic
}

function Test-Stage7ALiveReferenceEvidence {
  if (-not (Test-Path -LiteralPath $script:Stage7ALiveReferenceEvidencePath)) {
    Throw-Blocked '原版 Legado 同端点差分没有生成证据。'
  }
  $raw = [System.IO.File]::ReadAllText($script:Stage7ALiveReferenceEvidencePath, [System.Text.UTF8Encoding]::new($false))
  if ($raw -match '(?i)cookie|authorization|password|https?://|</?[a-z]') {
    Throw-Blocked '原版 Legado 同端点差分证据包含可能敏感的 URL、正文或凭据，已拒绝使用。'
  }
  try {
    $evidence = $raw | ConvertFrom-Json
  } catch {
    Throw-Blocked '原版 Legado 同端点差分证据不是有效 JSON。'
  }
  if ([int]$evidence.schemaVersion -ne 1 -or
    [string]$evidence.sourcePackageSha256 -ne [string]$script:State.baseline.sourcePackageSha256 -or
    [string]$evidence.legadoCommit -ne [string]$script:State.baseline.legadoCommit) {
    Throw-Blocked '原版 Legado 同端点差分证据的基线不匹配。'
  }
  $attempts = @($evidence.attempts)
  if ($attempts.Count -le 0) {
    Throw-Blocked '原版 Legado 同端点差分没有可复核的候选结果。'
  }
  foreach ($attempt in $attempts) {
    if ([string]$attempt.sourceHash -notmatch '^[A-F0-9]{64}$' -or
      [int]$attempt.keywordIndex -lt 0 -or [int]$attempt.keywordIndex -gt 3 -or
      [string]$attempt.referenceOutcome.Length -eq 0 -or [string]$attempt.v2Outcome.Length -eq 0) {
      Throw-Blocked '原版 Legado 同端点差分包含无效的脱敏记录。'
    }
  }
  return $evidence
}

function Invoke-Stage7RealUserFlow {
  param([pscustomobject]$Toolchain)
  if (-not (Test-Path -LiteralPath $script:Stage7RealUserFlowScript)) {
    Throw-Blocked '缺少阶段 7 真机 V2 用户路径自动化脚本。'
  }
  $device = Get-HarmonyDevice $Toolchain
  if (-not $device) {
    Throw-Blocked '未检测到用于阶段 7 的 HarmonyOS 真机。'
  }
  # A failed run must never allow a prior successful evidence file to be
  # mistaken for the current build. The exact generated artifact is safe to
  # replace on every attempt.
  if (Test-Path -LiteralPath $script:Stage7RealUserEvidencePath) {
    Remove-Item -LiteralPath $script:Stage7RealUserEvidencePath -Force
  }
  if (Test-Path -LiteralPath $script:Stage7DiagnosticEvidencePath) {
    Remove-Item -LiteralPath $script:Stage7DiagnosticEvidencePath -Force
  }
  $powerShellHost = Get-LegadoNativeHostExecutable
  [string[]]$flowArguments = @(
    '-NoProfile',
    '-NonInteractive',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    $script:Stage7RealUserFlowScript,
    '-HdcPath',
    $Toolchain.hdc,
    '-Device',
    $device,
    '-EvidencePath',
    $script:Stage7RealUserEvidencePath,
    '-DiagnosticEvidencePath',
    $script:Stage7DiagnosticEvidencePath,
    '-SourcePackageSha256',
    [string]$script:State.baseline.sourcePackageSha256,
    '-SourcePackagePath',
    $script:SourcePackage
  )
  $flowResult = Invoke-LegadoNativeProcess `
    -FilePath $powerShellHost `
    -ArgumentList $flowArguments `
    -TimeoutSeconds 2700 `
    -WorkingDirectory $script:RepoRoot
  $output = $flowResult.output
  if ($flowResult.timedOut) {
    $script:LastFailureEvidence = if (Test-Path -LiteralPath $script:Stage7DiagnosticEvidencePath) { $script:Stage7DiagnosticEvidencePath } else { $script:Stage7RealUserEvidencePath }
    throw '真实 V2 用户路径自动化超过 2700 秒，已终止其完整进程树（classification=timeout）。'
  }
  if ($flowResult.exitCode -ne 0) {
    $script:LastFailureEvidence = if (Test-Path -LiteralPath $script:Stage7DiagnosticEvidencePath) { $script:Stage7DiagnosticEvidencePath } else { $script:Stage7RealUserEvidencePath }
    throw "真实 V2 用户路径自动化失败：$($output.Trim())"
  }
  return Test-Stage7RealUserEvidence
}

function Invoke-Stage7ALiveReference {
  param([pscustomobject]$Toolchain)
  if (-not (Test-Path -LiteralPath $script:Stage7ALiveReferenceScript)) {
    Throw-Blocked '缺少阶段 7A 原版 Legado 同端点差分脚本。'
  }
  $diagnostic = Test-Stage7DiagnosticEvidence
  $serial = Ensure-AndroidDevice $Toolchain
  if (Test-Path -LiteralPath $script:Stage7ALiveReferenceEvidencePath) {
    Remove-Item -LiteralPath $script:Stage7ALiveReferenceEvidencePath -Force
  }
  $powerShellHost = Get-LegadoNativeHostExecutable
  [string[]]$referenceArguments = @(
    '-NoProfile',
    '-NonInteractive',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    $script:Stage7ALiveReferenceScript,
    '-AdbPath',
    $Toolchain.adb,
    '-Serial',
    $serial,
    '-SourcePackagePath',
    $script:SourcePackage,
    '-SourcePackageSha256',
    [string]$script:State.baseline.sourcePackageSha256,
    '-LegadoCommit',
    [string]$script:State.baseline.legadoCommit,
    '-Stage7DiagnosticEvidencePath',
    $script:Stage7DiagnosticEvidencePath,
    '-EvidencePath',
    $script:Stage7ALiveReferenceEvidencePath
  )
  $referenceResult = Invoke-LegadoNativeProcess `
    -FilePath $powerShellHost `
    -ArgumentList $referenceArguments `
    -TimeoutSeconds 1200 `
    -WorkingDirectory $script:RepoRoot
  $output = $referenceResult.output
  if ($referenceResult.timedOut) {
    $script:LastFailureEvidence = if (Test-Path -LiteralPath $script:Stage7ALiveReferenceEvidencePath) { $script:Stage7ALiveReferenceEvidencePath } else { $script:Stage7DiagnosticEvidencePath }
    throw '原版 Legado 同端点差分超过 1200 秒，已终止其完整进程树（classification=timeout）。'
  }
  if ($referenceResult.exitCode -ne 0) {
    $script:LastFailureEvidence = if (Test-Path -LiteralPath $script:Stage7ALiveReferenceEvidencePath) { $script:Stage7ALiveReferenceEvidencePath } else { $script:Stage7DiagnosticEvidencePath }
    throw "原版 Legado 同端点差分自动化失败：$($output.Trim())"
  }
  $evidence = Test-Stage7ALiveReferenceEvidence
  $summary = Get-OptionalProperty -Object $evidence -Name 'summary'
  $referenceComplete = [int](Get-OptionalProperty -Object $summary -Name 'referenceComplete')
  $v2Differential = [int](Get-OptionalProperty -Object $summary -Name 'referenceCompleteV2Failed')
  return New-Check '原版 Legado 同端点差分诊断' 'passed' "已对同一安全候选完成原版对照：原版完整路径=$referenceComplete；原版成功且 V2 失败=$v2Differential。" $script:Stage7ALiveReferenceEvidencePath
}

function Assert-FileContains {
  param([string]$RelativePath, [string[]]$Patterns, [string]$Label)
  $path = Join-Path $script:RepoRoot $RelativePath
  if (-not (Test-Path -LiteralPath $path)) { throw "$Label 缺失文件：$RelativePath" }
  $content = [System.IO.File]::ReadAllText($path, [System.Text.UTF8Encoding]::new($false))
  foreach ($pattern in $Patterns) {
    if ($content.IndexOf($pattern, [System.StringComparison]::Ordinal) -lt 0) {
      throw "$Label 缺少契约标识：$pattern"
    }
  }
}

function Assert-FileDoesNotContain {
  param([string]$RelativePath, [string[]]$Patterns, [string]$Label)
  $path = Join-Path $script:RepoRoot $RelativePath
  if (-not (Test-Path -LiteralPath $path)) { throw "$Label 缺失文件：$RelativePath" }
  $content = [System.IO.File]::ReadAllText($path, [System.Text.UTF8Encoding]::new($false))
  foreach ($pattern in $Patterns) {
    if ($content.IndexOf($pattern, [System.StringComparison]::Ordinal) -ge 0) {
      throw "$Label 仍存在禁止旁路：$pattern"
    }
  }
}

function Invoke-PowerShellContract {
  param(
    [Parameter(Mandatory = $true)][string]$RelativePath,
    [Parameter(Mandatory = $true)][string]$EvidenceName,
    [ValidateRange(1, 1800)][int]$TimeoutSeconds = 180
  )
  $contractPath = Join-Path $script:RepoRoot $RelativePath
  if (-not (Test-Path -LiteralPath $contractPath)) {
    throw "自动契约缺失文件：$RelativePath"
  }
  $powerShellHost = Get-LegadoNativeHostExecutable
  $contractResult = Invoke-LegadoNativeProcess `
    -FilePath $powerShellHost `
    -ArgumentList @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $contractPath, '-RepositoryRoot', $script:RepoRoot) `
    -TimeoutSeconds $TimeoutSeconds `
    -WorkingDirectory $script:RepoRoot
  if ($contractResult.timedOut) {
    throw "自动契约执行超时：$RelativePath；classification=timeout；timeoutSeconds=$TimeoutSeconds"
  }
  if ($contractResult.exitCode -ne 0) {
    throw "自动契约执行失败：$RelativePath；classification=$($contractResult.classification)；exitCode=$($contractResult.exitCode)；$($contractResult.output.Trim())"
  }
  $contractText = ([string]$contractResult.stdout).Trim()
  if ([string]::IsNullOrWhiteSpace($contractText)) {
    throw "自动契约没有产生结果：$RelativePath"
  }
  $evidencePath = Join-Path $script:EvidenceDirectory $EvidenceName
  Write-Utf8Atomic -Path $evidencePath -Content $contractText
  return $evidencePath
}

function Invoke-Stage0Work {
  $checks = @()
  $summaryResult = Get-SourcePackageSummary
  $summary = $summaryResult.summary
  if ($summary.sourceCount -ne 458) { Throw-Blocked "书源包数量不符合固定基线：$($summary.sourceCount)" }
  $commit = (& git -C $script:LegadoRoot rev-parse HEAD 2>$null | Out-String).Trim()
  if ($commit -ne $script:ExpectedLegadoCommit) { Throw-Blocked "Legado 提交不匹配：$commit" }
  if ($script:State.baseline.sourcePackageSha256 -and (
      $script:State.baseline.sourcePackageSha256 -ne $summary.sourcePackageSha256 -or
      $script:State.baseline.legadoCommit -ne $commit)) {
    Throw-Blocked '基线输入已变化，禁止与既有 trace 混合比较。'
  }
  $script:State.baseline.sourcePackageSha256 = $summary.sourcePackageSha256
  $script:State.baseline.sourcePackageBytes = $summary.sourcePackageBytes
  $script:State.baseline.sourceCount = $summary.sourceCount
  $script:State.baseline.legadoCommit = $commit
  $checks += New-Check '书源包哈希、数量与能力矩阵' 'passed' "SHA-256=$($summary.sourcePackageSha256)，数量=$($summary.sourceCount)" $summaryResult.evidence
  $toolchain = Ensure-Toolchain
  $checks += New-Check '工具链探测' 'passed' "JDK 21=$($toolchain.javaHome)，Legado Java 17 toolchain=$($toolchain.java17Home)，Android SDK=$($toolchain.androidSdk)，HDC/Hvigor 已定位。"
  Start-Fixture
  $fixtureEvidence = Test-FixtureContract
  $checks += New-Check '确定性 HTTP/重定向/Cookie fixture' 'passed' "127.0.0.1:$script:FixturePort 可达。" $fixtureEvidence
  $parserContractResult = Invoke-BoundedNativeCommand -FilePath (Join-Path $script:RepoRoot '.venv\Scripts\python.exe') -ArgumentList @('tools\legado-compat\Invoke-LegadoV2HypiumNavigation.py', '--parser-self-test') -TimeoutSeconds 30 -WorkingDirectory $script:RepoRoot
  if ($parserContractResult.exitCode -ne 0 -or $parserContractResult.output -notmatch '"status": "passed"') {
    throw 'V2 Hypium BookInfo 脱敏响应分类解析契约失败。'
  }
  $parserContractEvidence = Join-Path $script:EvidenceDirectory 'v2-book-info-response-class-parser-contract-stage0.json'
  Write-Utf8Atomic -Path $parserContractEvidence -Content $parserContractResult.output
  $checks += New-Check 'V2 BookInfo 脱敏响应分类解析契约' 'passed' '无设备回归已验证规则数量、解析数量、响应长度、指纹和响应分类均可落盘。' $parserContractEvidence
  $checks += Invoke-DeviceGate -StageKey 'stage0'
  return New-StageResult -Message '工具链、fixture、Android 原版与 HarmonyOS 基线 trace 已通过。' -Checks $checks
}

function Invoke-Stage1Work {
  $checks = @()
  $rawAudit = Test-RawSourceRoundTrip
  $checks += New-Check '458 条原始文档边界与标识审计' 'passed' '逐文档 UTF-8 边界扫描与标识解析通过；原始文本不写入证据目录。' $rawAudit
  Assert-FileContains 'entry\src\main\ets\Framework\Novel\LegadoCompatibilityTypes.ets' @('RawBookSourceDocument', 'CompiledBookSource', 'ImportReport', 'LegadoSourceVerificationRecord') 'V2 无损导入模型'
  Assert-FileContains 'entry\src\main\ets\Framework\Novel\NovelDatabaseSchema.ets' @('novel_source_compatibility', 'novel_source_compatibility_verification') '独立兼容存储'
  Assert-FileContains 'entry\src\main\ets\Framework\Novel\LargeFileJSONParser.ets' @(
    'util.TextDecoder.create',
    'onDocumentParsed',
    'parseUtf8ChunksForConformance',
    'isTopLevelWhitespace'
  ) 'V2 UTF-8 流式解析器'
  Assert-FileDoesNotContain 'entry\src\main\ets\Framework\Novel\LargeFileJSONParser.ets' @('onObjectParsed', 'String.fromCharCode(...slice)') 'V2 UTF-8 流式解析器'
  Assert-FileContains 'entry\src\main\ets\Framework\Novel\NovelDataManager.ets' @(
    'saveSourceWithCompatibilityRecord',
    'store.beginTransaction()',
    'store.executeSql(compatibilitySql',
    'store.rollBack()',
    'store.commit()'
  ) 'V2 原子存储事务'
  Assert-FileDoesNotContain 'entry\src\main\ets\Framework\Novel\NovelDataManager.ets' @(
    'beginTrans()',
    'transactionId',
    'store.execute(compatibilitySql'
  ) 'V2 真机兼容事务 API'
  Assert-FileContains 'entry\src\main\ets\Framework\Novel\NovelSourceManager.ets' @(
    'createCompatibilityRecord',
    'saveSourceWithCompatibilityRecord(source, compatibilityRecord)',
    'compileOne(rawDocument)',
    'discardStaleVerification',
    'LEGACY_UNVERIFIABLE'
  ) '迁移、原子写入与类型保护'
  Assert-FileContains 'entry\src\main\ets\Framework\Novel\LegadoCompatibilityCompiler.ets' @('EXTERNAL_TYPE_PLUGIN_CANDIDATE', 'UNKNOWN_FIELDS_PRESERVED') '扩展字段和外部类型保护'
  Assert-FileContains 'entry\src\main\ets\pages\NovelSourceManagementPage.ets' @('importFromLargeFile(fileUri', '正在无损写入文件') '主书源管理文件导入收口'
  Assert-FileDoesNotContain 'entry\src\main\ets\pages\NovelSourceManagementPage.ets' @('maxBufferSize', '只读取了 ${readLen}/${fileSize} 字节') '主书源管理文件导入收口'
  Assert-FileContains 'entry\src\main\ets\pages\BookSourceManagementPage.ets' @('importFileThroughV2Pipeline', 'importFromLargeFile(filePath') '备用书源管理文件导入收口'
  Assert-FileDoesNotContain 'entry\src\main\ets\pages\BookSourceManagementPage.ets' @('importSmallFile', 'String.fromCharCode(...slice)', 'LARGE_FILE_THRESHOLD') '备用书源管理文件导入收口'
  Assert-FileContains 'entry\src\main\ets\pages\MainMenuPage.ets' @('importFromLargeFile(readablePath') '主菜单文件导入收口'
  Assert-FileContains 'entry\src\main\ets\pages\ExternalFileTaskAbilityPage.ets' @('importFromLargeFile(readablePath') '外部文件任务导入收口'
  Assert-FileContains 'entry\src\ohosTest\ets\test\LegadoCompatibilityConformance.test.ets' @('preservesUtf8RawDocumentsAcrossOneByteChunks', 'parseUtf8ChunksForConformance') 'V2 UTF-8 跨块 conformance'
  $checks += New-Check '无损存储、UTF-8 跨块与全入口收口契约' 'passed' '原始 JSON、哈希、原子写入、UTF-8 跨块 fixture 与所有本地书源文件入口均进入同一 V2 管线。'
  $checks += Invoke-DeviceGate -StageKey 'stage1'
  return New-StageResult -Message '无损导入、事务化存储、UTF-8 跨块解析和双端 conformance 已通过。' -Checks $checks
}

function Invoke-Stage2Work {
  $checks = @()
  Start-Fixture
  $fixtureEvidence = Test-FixtureContract
  Assert-FileContains 'entry\src\main\ets\Framework\Novel\LegadoCompatibilityCompiler.ets' @('LegadoRuleIrNode', 'VARIABLE_PUT', 'COMPOSE_AND', 'URL_OPTION') '规则 IR 编译器'
  Assert-FileContains 'entry\src\main\ets\Framework\Novel\LegadoRequestPipeline.ets' @('class LegadoRequestPlanner', 'class LegadoHttpTransport', 'RequestSpec', 'ResponseEnvelope', 'webViewDelayTime', "remoteValidation: 'skip'") '请求规划与 HTTP 传输'
  Assert-FileContains 'entry\src\main\ets\Framework\Novel\LegadoTraceSerializer.ets' @('toRedactedJson', '[REDACTED]', 'bodyLength') '脱敏 ExecutionTrace'
  Assert-FileContains 'entry\src\main\ets\Framework\Reader\MangaRequestHeaderContract.ets' @('class MangaRequestHeaderContract', "case 'user-agent'", "case 'referer'", "case 'origin'", "case 'cookie'", 'upsertExtra') 'IMAGE 页面请求头契约'
  Assert-FileContains 'entry\src\main\ets\components\MangaAssetLoadContextResolver.ets' @('MangaRequestHeaderContract.clone', 'MangaRequestHeaderContract.apply') 'IMAGE V2 资产加载交接'
  Assert-FileContains 'entry\src\ohosTest\ets\test\LegadoCompatibilityConformance.test.ets' @('mapsImagePageHeadersIntoTypedTransportFields') 'IMAGE 页面请求头 conformance'
  $transportGovernanceEvidence = Invoke-PowerShellContract `
    -RelativePath 'tools\legado-compat\Test-NetworkTransportFailureGovernanceContract.ps1' `
    -EvidenceName 'network-transport-failure-governance-contract-stage2.json'
  $legadoHttpHeaderEvidence = Invoke-PowerShellContract `
    -RelativePath 'tools\legado-compat\Test-LegadoHttpTransportHeaderContract.ps1' `
    -EvidenceName 'legado-http-transport-header-contract-stage2.json'
  $sourceHeaderAjaxEvidence = Invoke-PowerShellContract `
    -RelativePath 'tools\legado-compat\Test-LegadoV2SourceHeaderAjaxContract.ps1' `
    -EvidenceName 'legado-v2-source-header-ajax-contract-stage2.json'
  $sourceIdentityEvidence = Invoke-PowerShellContract `
    -RelativePath 'tools\legado-compat\Test-MangaReaderSourceIdentityContract.ps1' `
    -EvidenceName 'manga-reader-source-identity-contract-stage2.json'
  $checks += New-Check '规则编译、RequestSpec 与 Trace 契约' 'passed' 'CSS/XPath/JSONPath/Regex/变量/JS/URL option 均在 IR 或请求计划中有来源节点。'
  $checks += New-Check 'V2 动态 source.header 与 java.ajax 契约' 'passed' '动态书源 Header 在 ArkWeb runtime workflow 内解析并进入 java.ajax/connect/post/head；URL option 显式 Header 覆盖源 Header，且有确定性桥接重放 fixture。' $sourceHeaderAjaxEvidence
  $checks += New-Check 'IMAGE 页面请求头语义交接' 'passed' '页面级 User-Agent、Referer、Origin、Cookie 和定制 Header 均被映射到图片传输契约，并由真机 conformance 覆盖。'
  $checks += New-Check 'IMAGE 传输失败聚合与预加载熔断契约' 'passed' '失败指纹不含 URL 路径；DNS/TLS 熔断仅抑制后台预加载，可见页与手动重试保持可用。' $transportGovernanceEvidence
  $checks += New-Check 'IMAGE 三入口书源身份契约' 'passed' 'Router、NavStack 与独立 Ability 均保留 sourceId/sourcePkg/contentType，并继续进入 V2/raw SHA 链路。' $sourceIdentityEvidence
  $checks += New-Check 'Header/POST/redirect/Cookie fixture' 'passed' '本地 fixture 已验证真实请求行为。' $fixtureEvidence
  $checks += Invoke-DeviceGate -StageKey 'stage2'
  return New-StageResult -Message '规则编译与 HTTP 请求内核已通过静态和双端 conformance 门禁。' -Checks $checks
}

function Invoke-Stage3Work {
  $checks = @()
  Assert-FileContains 'entry\src\main\ets\Framework\Novel\LegadoRequestPipeline.ets' @('class LegadoArkWebTransport', 'sourceRegex', 'webJs', 'WEBVIEW_NOT_READY') 'ArkWeb 传输契约'
  Assert-FileContains 'entry\src\main\ets\Framework\Novel\LegadoWebViewExecutor.ets' @('onResourceRequest', 'getCookies', 'completeTask', 'loadUrl') 'ArkWeb 生命周期契约'
  $hostWindowCleanupEvidence = Invoke-PowerShellContract `
    -RelativePath 'tools\legado-compat\Test-LegadoArkWebHostWindowCleanupContract.ps1' `
    -EvidenceName 'arkweb-host-window-cleanup-contract-stage3.json'
  $dynamicExploreSourceEvidence = Invoke-PowerShellContract `
    -RelativePath 'tools\legado-compat\Test-LegadoDynamicExploreOnehuFailureContract.ps1' `
    -EvidenceName 'dynamic-explore-onehu-source-contract-stage3.json'
  $dynamicEvalProbeEvidence = Invoke-PowerShellContract `
    -RelativePath 'tools\legado-compat\Test-LegadoDynamicEvalArkWebProbeContract.ps1' `
    -EvidenceName 'dynamic-eval-arkweb-probe-contract-stage3.json'
  $scopeReplayEvidence = Invoke-PowerShellContract `
    -RelativePath 'tools\legado-compat\Test-LegadoRuntimeScopeReplayContract.ps1' `
    -EvidenceName 'runtime-scope-replay-contract-stage3.json'
  $jsonPathBridgeEvidence = Invoke-PowerShellContract `
    -RelativePath 'tools\legado-compat\Test-LegadoJsonPathBridgeContract.ps1' `
    -EvidenceName 'legado-jsonpath-bridge-contract-stage3.json'
  $jsonPathRuntimeEvidence = Invoke-PowerShellContract `
    -RelativePath 'tools\legado-compat\Test-LegadoJsonPathRuntimeFixture.ps1' `
    -EvidenceName 'legado-jsonpath-runtime-contract-stage3.json'
  $jsonPathExtendedEvidence = Invoke-PowerShellContract `
    -RelativePath 'tools\legado-compat\Test-LegadoJsonPathRuntimeExtendedFixture.ps1' `
    -EvidenceName 'legado-jsonpath-runtime-extended-contract-stage3.json'
  $jsonPathMatrixEvidence = Invoke-PowerShellContract `
    -RelativePath 'tools\legado-compat\Invoke-LegadoJsonPathRuntimeEquivalenceMatrix.ps1' `
    -EvidenceName 'legado-jsonpath-runtime-equivalence-matrix-stage3.json'
  $checks += New-Check 'ArkWeb 请求/资源/Cookie/回收契约' 'passed' 'Planner 路由、sourceRegex、Cookie 回写、超时和任务收敛均有明确实现。'
  $checks += New-Check 'ArkWeb 宿主 window 清理兼容契约' 'passed' '不再假设 window 是普通可枚举数组对象；脚本 finally 清理在宿主对象上安全降级，不会掩盖已成功的规则结果。' $hostWindowCleanupEvidence
  $checks += New-Check '动态 Explore 精确书源 fixture' 'passed' 'onehu 动态分类脚本的 eval、Jsoup、for-in、attr 与 fenl 输出在确定性 runtime 中保持可执行。' $dynamicExploreSourceEvidence
  $checks += New-Check 'ArkWeb 动态 eval 分层探针' 'passed' '真机 conformance 分别验证 direct eval、source 绑定和 source.bookSourceComment 动态 eval，失败仅输出脱敏诊断。' $dynamicEvalProbeEvidence
  $checks += New-Check '规则局部变量隔离契约' 'passed' '未声明规则变量写入 source-scoped 绑定，不泄漏到 ArkWeb 宿主全局或后续工作流。' $scopeReplayEvidence
  $checks += New-Check 'Legado JSONPath Runtime 语法等价类契约' 'passed' 'Runtime 已回归 scalar、wildcard、index、slice、recursive、&&/||/%% 与 ##；60 条受影响源仅登记为确定性语法覆盖，原版逐字段差分仍由 reference gate 决定。' $jsonPathMatrixEvidence
  $checks += Invoke-DeviceGate -StageKey 'stage3'
  $harmonyTracePath = Join-Path $script:EvidenceDirectory 'harmony-ohos-trace-stage3.log'
  $harmonyTrace = ''
  if (Test-Path -LiteralPath $harmonyTracePath) {
    $harmonyTrace = [System.IO.File]::ReadAllText($harmonyTracePath, [System.Text.UTF8Encoding]::new($false))
  }
  $hasSuccessfulArkWebTrace = Test-HarmonyArkWebSuccessTrace -TraceText $harmonyTrace
  if (-not (Test-Path -LiteralPath $harmonyTracePath) -or -not $hasSuccessfulArkWebTrace) {
    Throw-Blocked 'ArkWeb fixture 尚未产生可复核的成功 transport=ark_web trace；V2 不会切换。'
  }
  $checks += New-Check 'ArkWeb fixture trace 差分' 'passed' 'Android 与 HarmonyOS 的 ArkWeb trace 已可复核。' $harmonyTracePath
  return New-StageResult -Message 'ArkWeb 统一传输已通过双端 trace 对照。' -Checks $checks
}

function Invoke-Stage4Work {
  $checks = @()
  Assert-FileContains 'entry\src\main\ets\Framework\Novel\LegadoWorkflowOrchestrator.ets' @('preUpdateJs', 'formatJs', 'downloadUrls', 'nextTocUrl', 'nextContentUrl', 'rule.title', 'blockProtectedResponse', 'PROTECTED_RESPONSE') 'V2 工作流编排'
  Assert-FileContains 'entry\src\main\ets\Framework\Novel\LegadoCompatibilityCompiler.ets' @('PAY_ACTION', 'IMAGE_DECODE', 'REVIEW', 'EXTERNAL_TYPE') '工作流能力诊断'
  Assert-FileContains 'tools\legado-compat\FixtureServer.ps1' @('/protected-login', 'Login required') '受保护响应 fixture'
  Assert-FileContains 'entry\src\ohosTest\ets\test\LegadoCompatibilityConformance.test.ets' @('blocksProtectedHtmlBeforeRuleParsing', 'protected_response:html_login') '受保护响应 conformance'
  $checks += New-Check 'Search/Explore/Info/Toc/Content/File/Review 消费者契约' 'passed' '已消费字段有编排器或显式结构化拒绝，未把登录页、Review、付费或图片解码伪报为可读内容。'
  $checks += Invoke-DeviceGate -StageKey 'stage4'
  return New-StageResult -Message '工作流类型适配通过消费者与双端 conformance 门禁。' -Checks $checks
}

function Invoke-Stage5Work {
  $checks = @()
  Assert-FileContains 'entry\src\main\ets\Framework\Novel\LegadoJsApiContractRegistry.ets' @('SUPPORTED', 'UNSUPPORTED_API', 'NEEDS_INTERACTION', 'POLICY_BLOCKED', 'appendUnknownNamespaceApis') 'JS API 契约注册表'
  Assert-FileContains 'entry\src\main\ets\Framework\Novel\LegadoWorkflowOrchestrator.ets' @('blockForJsContracts', 'UNSUPPORTED_API', 'NEEDS_INTERACTION', 'POLICY_BLOCKED') 'JS 错误分类'
  $checks += New-Check 'JS API 状态与未知 API 分类' 'passed' '登录、验证码、付费和未知 API 都会产生可定位的拒绝，而非静默空值。'
  $checks += Invoke-DeviceGate -StageKey 'stage5'
  return New-StageResult -Message 'JS API 契约与双端 conformance 门禁通过。' -Checks $checks
}

function Invoke-Stage6Work {
  $checks = @()
  Assert-V2GlobalRoutingBoundary
  Assert-V2FullCutoverFallbackBoundary
  Assert-FileContains 'entry\src\main\ets\Framework\Novel\NovelSourceManager.ets' @(
    'V2_FULL_CUTOVER',
    'normalizeV2ExecutionPolicy',
    'getEffectiveCompatibilityEngineMode',
    'isV2FullCutoverBlocked',
    'return compiled.status === LegadoCompatibilityStatus.READY',
    'logV2FullCutoverBlock'
  ) 'V2 全局中央路由'
  Assert-FileContains 'entry\src\main\ets\Framework\Managers\SettingsManager.ets' @(
    "getString(SettingKeys.LEGADO_V2_EXECUTION_POLICY, 'v2_full_cutover')"
  ) 'V2 默认全量策略'
  Assert-FileContains 'entry\src\main\ets\pages\NovelSourceManagementPage.ets' @(
    'Legado V2 全局执行',
    'V2 全量切换',
    'V2 全量执行（无旧内核回退）',
    'V2 全量切换受阻'
  ) '全局切换与受阻状态展示'
  Assert-FileContains 'entry\src\main\ets\Framework\Novel\LegadoCompatibilityCompiler.ets' @(
    'case LegadoCapability.FILE:',
    'case LegadoCapability.REVIEW:',
    'case LegadoCapability.IMAGE_DECODE:'
  ) 'V2 未接管能力的显式阻断'
  $checks += New-Check '全局 V2 路由与显式回退' 'passed' '默认策略为 V2_FULL_CUTOVER；旧内核只有用户显式切回 LEGACY_ONLY 才可执行。'
  $checks += New-Check '非 READY 能力封口' 'passed' '登录/付费交互、文件下载器、Review、imageDecode 与外部类型均在中央边界可见阻断，不会半执行或静默回退。'
  $checks += Invoke-DeviceGate -StageKey 'stage6'
  if ($script:State.stages.stage3.status -ne 'passed') {
    Throw-Blocked '阶段 3 ArkWeb 语义对照未通过，阶段 6 不允许启用 V2。'
  }
  $checks += New-Check '最终构建与回退门禁' 'passed' '完整 debug 构建和双端测试均通过。'
  return New-StageResult -Message 'V2 全局默认切换、显式阻断、界面状态与构建回归均已通过。' -Checks $checks
}

function Assert-V2GlobalRoutingBoundary {
  $sourceRoot = Join-Path $script:RepoRoot 'entry\src\main\ets'
  # Backups intentionally retain historical source text. Only compiled ArkTS
  # source files participate in the routing boundary assertion.
  $rgCommand = Get-Command 'rg' -CommandType Application -ErrorAction SilentlyContinue
  if ($null -eq $rgCommand) {
    throw 'V2 全局路由旁路检查缺少 rg。'
  }
  $rgResult = Invoke-BoundedNativeCommand -FilePath $rgCommand.Source -ArgumentList @('-n', '--encoding', 'UTF-8', '--glob', '*.ets', 'new NovelSourceExecutor', $sourceRoot) -TimeoutSeconds 30
  if ($rgResult.exitCode -ne 0 -and $rgResult.exitCode -ne 1) {
    throw "V2 全局路由旁路检查执行失败：exitCode=$($rgResult.exitCode)；$($rgResult.stderr.Trim())"
  }
  $matches = @($rgResult.stdout -split "`r?`n" | Where-Object { $_.Trim().Length -gt 0 })
  if ($matches.Count -ne 1 -or $matches[0] -notmatch 'Framework[\\/]Novel[\\/]NovelSourceManager\.ets') {
    $observed = if ($matches.Count -eq 0) { 'none' } else { $matches -join ' | ' }
    throw "V2 全局路由旁路检查失败：旧执行器只能由 NovelSourceManager 构造，实际=$observed"
  }
}

function Assert-V2FullCutoverFallbackBoundary {
  Assert-FileContains 'entry\src\main\ets\Framework\Novel\NovelSourceManager.ets' @(
    'shouldBlockLegacyFallback',
    'V2_FULL_CUTOVER'
  ) 'V2 降级封口中央语义'
  Assert-FileContains 'entry\src\main\ets\pages\NovelDetailPage.ets' @(
    'shouldBlockLegacyFallback(this.sourceId)',
    '拒绝搜索结果 fallback'
  ) '小说详情 V2 降级封口'
  Assert-FileContains 'entry\src\main\ets\Framework\Novel\LegadoMangaSourceBridge.ets' @(
    'isV2LegacyFallbackBlocked',
    '拒绝 IMAGE 桥接 fallback',
    '拒绝 IMAGE 章节解析 fallback',
    '拒绝 IMAGE 缓存章节 fallback'
  ) 'IMAGE 桥接 V2 降级封口'
}

function Invoke-Stage7Work {
  $checks = @()
  Assert-V2GlobalRoutingBoundary
  Assert-V2FullCutoverFallbackBoundary
  Assert-FileContains 'entry\src\main\ets\Framework\Novel\NovelSourceManager.ets' @(
    'LegadoV2ExecutionPolicy',
    'V2_FULL_CUTOVER',
    'normalizeV2ExecutionPolicy',
    'getEffectiveCompatibilityEngineMode',
    'isV2FullCutoverBlocked',
    'getLastExecutionTraceSummary',
    'getExecutionTraceWorkflowSummaries',
    'refreshExecutionTraceSummaries',
    'restoreExecutionTraceWorkflowSummaries',
    'saveCompatibilityTraceWorkflowSummary',
    'await this.persistExecutionTraceSummary'
  ) 'V2 全局策略与持久化 trace'
  Assert-FileContains 'entry\src\main\ets\Framework\Managers\SettingsManager.ets' @(
    "getString(SettingKeys.LEGADO_V2_EXECUTION_POLICY, 'v2_full_cutover')"
  ) 'V2 默认全量策略'
  Assert-FileContains 'entry\src\main\ets\Framework\Novel\LegadoCompatibilityTypes.ets' @(
    'V2_FULL_CUTOVER',
    'V2_FORCE_TEST'
  ) 'V2 全量切换与历史设置迁移'
  Assert-FileContains 'entry\src\main\ets\Framework\Novel\LegadoMangaSourceBridge.ets' @(
    'getNovelSourceManager',
    'sourceManager.search',
    'sourceManager.getContent'
  ) 'Legado IMAGE 桥接中央路由'
  Assert-FileContains 'entry\src\main\ets\Framework\Novel\NovelSourceValidator.ets' @(
    'sourceManager.search',
    'mapLastTraceToValidation',
    '拒绝使用旧执行器校验'
  ) '书源校验中央路由'
  Assert-FileContains 'entry\src\main\ets\pages\NovelSourceDebugPage.ets' @(
    'sourceManager.search',
    'sourceManager.getBookInfo',
    'toLegadoSearchBooks'
  ) '调试页中央路由'
  Assert-FileContains 'entry\src\main\ets\pages\NovelSourceManagementPage.ets' @(
    'V2 全量切换',
    'V2_FULL_CUTOVER',
    'refreshV2TraceSummaries',
    'getExecutionTraceWorkflowSummaries',
    'V2 trace：${summary.workflow}',
    '尚未获得可复核的用户路径证据'
  ) 'V2 全局切换界面与 trace 回显'
  Assert-FileContains 'entry\src\main\ets\Framework\Novel\NovelDatabaseSchema.ets' @(
    'novel_source_compatibility_trace',
    'novel_source_compatibility_trace_workflow',
    'rawSha256',
    'finalUrlObservation'
  ) 'V2 trace 摘要隔离存储'
  Assert-FileContains 'entry\src\main\ets\Framework\Novel\NovelInitializer.ets' @(
    'getAllCompatibilityTraceSummaries',
    'restoreExecutionTraceSummaries',
    'getAllCompatibilityTraceWorkflowSummaries',
    'restoreExecutionTraceWorkflowSummaries'
  ) 'V2 trace 摘要重启恢复'
  Assert-FileContains 'tools\legado-compat\Invoke-LegadoV2RealDeviceFlow.ps1' @(
    'isActiveRoute',
    'Get-V2TraceRecordsFromLayout',
    'Return-ToSourceManagement',
    'Test-SourceRuleRequiresUnsupportedJs',
    'Close-ExistingSourceManagementFilter',
    'candidateFailureCounts',
    'candidateAttemptRecords',
    'candidateSelectorVersion',
    'DiagnosticEvidencePath',
    'Get-CandidateTraceSnapshot',
    'Add-CandidateTraceFailureCounts',
    "Click-UiText -Text '搜索'",
    '重启前缺少成功的 V2',
    'STAGE7_UI_TRACE_AFTER_RESTART'
  ) '真机可见页面与按工作流 trace 门禁'
  Assert-FileContains 'tools\legado-compat\Invoke-LegadoLiveReference.ps1' @(
    'LegadoLiveSourceReferenceTest',
    'run-as',
    'candidateSelectorVersion',
    'referenceCompleteV2Failed',
    'missing_reference_trace'
  ) '阶段 7A 原版同端点脱敏差分'
  Assert-FileContains 'legado\app\src\androidTest\java\io\legado\app\compat\LegadoLiveSourceReferenceTest.kt' @(
    'attemptId',
    'WebBook.searchBookAwait',
    'WebBook.getBookInfoAwait',
    'WebBook.getChapterListAwait',
    'WebBook.getContentAwait'
  ) '原版 Legado test-only 真实端点参考执行器'
  Assert-FileContains 'entry\src\main\ets\pages\settings\SettingsImmersiveTitleBar.ets' @(
    'accessibilityLabel',
    '.accessibilityText(this.accessibilityLabel)',
    "accessibilityLabel: '更多操作'"
  ) '标题栏语义化自动化定位'
  Assert-FileContains 'entry\src\main\ets\Framework\Novel\LegadoContentSemantics.ets' @(
    'normalizePageContent',
    'joinNormalizedPages',
    'assessReaderPayload',
    'RAW_HTML',
    'normalizeImagePage'
  ) 'V2 正文交付语义内核'
  Assert-FileContains 'entry\src\main\ets\Framework\Novel\LegadoWorkflowOrchestrator.ets' @(
    'LegadoContentSemantics',
    'normalizePageContent',
    'presentation=',
    'getContentNextUrls',
    'applyFinalContentReplacement'
  ) 'V2 正文规则到阅读器的中央交接'
  Assert-FileContains 'entry\src\main\ets\Framework\Novel\LegadoCompatibilityCompiler.ets' @(
    'ruleContent.replaceRegex',
    'LegadoCapability.IMAGE_DECODE'
  ) 'V2 正文替换与图片解码能力边界'
  Assert-FileContains 'entry\src\main\ets\Framework\Novel\LegadoV2QualificationRunner.ets' @(
    'assessReaderPayload',
    'presentation=${presentation.status}'
  ) '正文非空之外的资格验收'
  Assert-FileContains 'tools\legado-compat\FixtureServer.ps1' @('/content/html', 'fixture-html-content', '/content/multipage/one', 'REMOVE_MARKER') 'HTML 正文 fixture'
  Assert-FileContains 'entry\src\ohosTest\ets\test\LegadoCompatibilityConformance.test.ets' @(
    'normalizesHtmlSelectorOutputBeforeReaderDelivery',
    'presentation=readable',
    'aggregatesAllContentPagesBeforeApplyingReplaceRegex',
    'turnsImageUrlListsIntoReaderImageNodes',
    'blocksUnimplementedImageDecodeInsteadOfSilentlyIgnoringIt'
  ) 'HTML 正文端到端 conformance'
  $powerShell51Evidence = Invoke-PowerShellContract `
    -RelativePath 'tools\legado-compat\Test-LegadoStage7PowerShell51Contract.ps1' `
    -EvidenceName 'stage7-powershell51-contract.json'
  $nativeTimeoutEvidence = Invoke-PowerShellContract `
    -RelativePath 'tools\legado-compat\Test-LegadoNativeProcessTimeoutContract.ps1' `
    -EvidenceName 'stage7-native-process-timeout-contract.json' `
    -TimeoutSeconds 240
  $runtimeFailureDiagnosticEvidence = Invoke-PowerShellContract `
    -RelativePath 'tools\legado-compat\Test-LegadoRuntimeFailureDiagnosticContract.ps1' `
    -EvidenceName 'stage7-runtime-failure-diagnostic-contract.json'
  $checks += New-Check '全局 V2 路由旁路审计' 'passed' '旧执行器唯一构造点为 NovelSourceManager；普通路径、IMAGE 桥接、校验与调试入口均回到中央策略。'
  $checks += New-Check 'V2 全量切换与 trace 持久化' 'passed' 'V2_FULL_CUTOVER 禁止旧内核回退；每个工作流的脱敏摘要在用户路径返回前落库，并按原始书源 SHA-256 恢复。'
  $checks += New-Check '真机页面作用域与 trace 证据门禁' 'passed' '自动化以当前页面精确标识和标题栏作用域定位控件，并在重启前后分别验证四个工作流的脱敏 V2 trace。'
  $checks += New-Check '阶段 7A 自动差分分支' 'passed' '阶段 7 失败后会自动将同一安全候选 SHA 与关键字序号交给原版 Legado test-only runner；诊断不能覆盖阶段 7 的失败状态。'
  $checks += New-Check '正文交付语义门禁' 'passed' 'TEXT/IMAGE 正文在进入阅读器前完成标准化；分页后全文替换只执行一次，无法执行的图片解密会明确阻断。'
  $checks += New-Check 'Windows PowerShell 5.1 自动化契约' 'passed' 'Stage 7 的 UTF-8、顶层 JSON 数组、原生命令 stderr、退出码和调用链已通过双 PowerShell 运行门禁。' $powerShell51Evidence
  $checks += New-Check '原生命令进程级超时契约' 'passed' 'Stage 7/7A 的 HDC、ADB 与子脚本均有可终止的进程边界；stdout、stderr、退出码和 timeout 分类已在 PowerShell 5.1 下验证。' $nativeTimeoutEvidence
  $checks += New-Check 'JS 运行时失败结构化诊断契约' 'passed' '脚本失败只保留操作、错误类型、摘要哈希、脚本长度和 sourceComment/DOMParser 能力状态，不写入脚本、URL、Cookie 或正文。' $runtimeFailureDiagnosticEvidence
  $checks += Invoke-DeviceGate -StageKey 'stage7'
  if ($script:State.stages.stage3.status -ne 'passed') {
    Throw-Blocked '阶段 3 ArkWeb 语义对照未通过，阶段 7 不允许进行真机 V2 验收。'
  }
  try {
    $checks += Invoke-Stage7RealUserFlow -Toolchain (Ensure-Toolchain)
  } catch {
    if (Test-Path -LiteralPath $script:Stage7DiagnosticEvidencePath) {
      $script:LastFailureEvidence = $script:Stage7DiagnosticEvidencePath
    }
    throw
  }
  return New-StageResult -Message 'V2 已作为全局默认内核；自动真机普通用户路径、重启 trace 恢复和双端门禁均已通过。' -Checks $checks
}

function Invoke-Stage7AWork {
  $checks = @()
  $checks += Invoke-Stage7ALiveReference -Toolchain (Ensure-Toolchain)
  return New-StageResult -Message '阶段 7 失败后的原版 Legado 同端点差分已完成；结果只用于归因，不会把阶段 7 的失败伪装为通过。' -Checks $checks
}

function Invoke-Stage8Work {
  $checks = @()
  $matrix = Test-CapabilityMatrixClosure
  Assert-FileContains 'entry\src\main\ets\Framework\Novel\LegadoCompatibilityCompiler.ets' @(
    'LegadoCapability.AUDIO',
    'LegadoCapability.IMAGE',
    'LegadoCapability.FILE',
    'LegadoCapability.REVIEW',
    'LegadoCapability.PAY_ACTION',
    'LegadoCapability.IMAGE_DECODE',
    'LegadoCapability.EXTERNAL_TYPE'
  ) '458 条书源能力分类器'
  Assert-FileContains 'entry\src\main\ets\Framework\Novel\NovelSourceManager.ets' @(
    'return compiled.status === LegadoCompatibilityStatus.READY',
    '需要登录、验证码或人工交互',
    '外部或插件书源类型尚无 V2 执行器'
  ) '全量切换阻断分类'
  Assert-FileContains 'entry\src\ohosTest\ets\test\LegadoCompatibilityConformance.test.ets' @(
    'blocksFileSourceWithoutV2DownloaderHandoff',
    'classifiesLoginAndReviewAsExplicitNonRunnableCapabilities',
    'blocksUnimplementedImageDecodeInsteadOfSilentlyIgnoringIt',
    'turnsImageUrlListsIntoReaderImageNodes'
  ) '非文本类型与结构化失败 conformance'
  $checks += New-Check '458 条书源能力矩阵闭合' 'passed' 'TEXT、AUDIO、IMAGE、FILE、外部类型及登录/JS 分类均与固定包统计闭合。' $matrix.evidence
  $checks += New-Check '未接管功能的 V2 失败语义' 'passed' 'FILE、Review、imageDecode、登录/付费交互和插件类型均产生结构化阻断，绝不借文本成功误报为可用。'
  $checks += Invoke-DeviceGate -StageKey 'stage8'
  return New-StageResult -Message '能力矩阵、结构化失败语义与双端 conformance 均已通过；上线说明不会扩大为“全部书源已兼容”。' -Checks $checks
}

function Invoke-Stage {
  param([string]$StageKey, [scriptblock]$Work)
  $script:LastFailureEvidence = ''
  Set-StageState -StageKey $StageKey -Status 'running' -Message '正在执行自动检查。'
  try {
    $result = & $Work
    Set-StageState -StageKey $StageKey -Status 'passed' -Message $result.message -Checks $result.checks
    return $true
  } catch {
    $message = $_.Exception.Message
    $status = if ($message.StartsWith('BLOCKED:')) { 'blocked' } else { 'failed' }
    $detail = if ($status -eq 'blocked') { $message.Substring('BLOCKED:'.Length) } else { $message }
    Set-StageState -StageKey $StageKey -Status $status -Message $detail -Checks @(New-Check '阶段门禁' $status $detail $script:LastFailureEvidence)
    return $false
  }
}

function Block-RemainingStages {
  param([string[]]$StageKeys, [string]$Reason)
  foreach ($stageKey in $StageKeys) {
    Set-StageState -StageKey $stageKey -Status 'blocked' -Message $Reason -Checks @(New-Check '前置门禁' 'blocked' $Reason)
  }
}

if ($RefreshDocumentsOnly) {
  Recover-StaleCompatibilityStages
  Save-CompatibilityState
  Write-Output 'LEGADO_COMPATIBILITY_DOCUMENTS_REFRESHED'
  exit 0
}

if ($HarmonyOnly) {
  $harmonyOnlyToolchain = $null
  try {
    $harmonyOnlyToolchain = Ensure-Toolchain
    # Harmony-only conformance still exercises both the plain HTTP and TLS
    # fixture contracts.  Starting only TLS leaves the HTTP endpoints
    # unreachable and turns transport assertions into misleading empty-result
    # failures.  Keep startup symmetric with the full stage pipeline.
    Start-Fixture
    Start-TlsFixture
    $harmonyOnlyResult = Invoke-HarmonyConformance -Toolchain $harmonyOnlyToolchain -StageKey 'stage3'
    Write-Output ($harmonyOnlyResult | ConvertTo-Json -Depth 12)
    exit 0
  } catch {
    Write-Error $_.Exception.Message
    exit 1
  } finally {
    Stop-TlsFixture
    Stop-Fixture
  }
}

$stageOrder = @('stage0', 'stage1', 'stage2', 'stage3', 'stage4', 'stage5', 'stage6', 'stage7', 'stage7a', 'stage8')
$stageWork = @{
  stage0 = { Invoke-Stage0Work }
  stage1 = { Invoke-Stage1Work }
  stage2 = { Invoke-Stage2Work }
  stage3 = { Invoke-Stage3Work }
  stage4 = { Invoke-Stage4Work }
  stage5 = { Invoke-Stage5Work }
  stage6 = { Invoke-Stage6Work }
  stage7 = { Invoke-Stage7Work }
  stage7a = { Invoke-Stage7AWork }
  stage8 = { Invoke-Stage8Work }
}

try {
  $stageIndex = [System.Array]::IndexOf([string[]]$stageOrder, $OnlyStage)
  [string[]]$selected = @()
  if ($OnlyStage -eq 'all') {
    $selected = [string[]]$stageOrder
  } else {
    $selected = [string[]]$stageOrder[0..$stageIndex]
  }
  for ($index = 0; $index -lt $selected.Count; $index++) {
    $stageKey = $selected[$index]
    if ($stageKey -eq 'stage7a' -and $script:State.stages.stage7.status -eq 'passed') {
      # 7A is a diagnostic branch, not a second success gate.  It must only
      # run after the normal V2 user path has produced a V7 diagnostic.
      continue
    }
    if ($OnlyStage -ne 'all' -and $stageKey -ne 'stage0' -and $stageKey -ne $OnlyStage -and $script:State.stages.$stageKey.status -eq 'passed') {
      continue
    }
    $passed = Invoke-Stage -StageKey $stageKey -Work $stageWork[$stageKey]
    if (-not $passed) {
      if ($stageKey -eq 'stage7') {
        # A failed normal user path is not yet an engine verdict.  Preserve
        # its V2 diagnostic and immediately execute the isolated, reference
        # Legado branch on the same safe candidate hashes before blocking
        # later capability work.
        $stage7aPassed = Invoke-Stage -StageKey 'stage7a' -Work $stageWork.stage7a
        $remainingAfterDiagnostic = @()
        for ($rest = $index + 1; $rest -lt $selected.Count; $rest++) {
          if ($selected[$rest] -ne 'stage7a') {
            $remainingAfterDiagnostic += $selected[$rest]
          }
        }
        if ($remainingAfterDiagnostic.Count -gt 0) {
          $reason = if ($stage7aPassed) {
            "等待 stage7 真机路径通过；阶段 7A 已完成差分归因：$($script:State.stages.stage7a.message)"
          } else {
            "等待 stage7 真机路径通过；阶段 7A 也未完成：$($script:State.stages.stage7a.message)"
          }
          Block-RemainingStages -StageKeys $remainingAfterDiagnostic -Reason $reason
        }
        exit 1
      }
      $remaining = @()
      for ($rest = $index + 1; $rest -lt $selected.Count; $rest++) { $remaining += $selected[$rest] }
      if ($remaining.Count -gt 0) { Block-RemainingStages -StageKeys $remaining -Reason "等待 $stageKey 门禁：$($script:State.stages.$stageKey.message)" }
      exit 1
    }
  }
} finally {
  Stop-TlsFixture
  Stop-Fixture
  Save-CompatibilityState
}
