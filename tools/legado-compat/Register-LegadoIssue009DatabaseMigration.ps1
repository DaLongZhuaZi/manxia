[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$RegistrationEvidencePath = 'tools/legado-compat/evidence/r3-issue-009-database-migration/registration.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$sourceCount = 458
$sourceHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$issueId = 'ISSUE-COMPAT-009'
$taskId = 'COMPAT-009'
$parentTaskId = 'COMPAT-006'
$revision = '2026-08-09-actual-docs-source-refactor-issue009-database-migration-static-closed'
$fixturePath = 'tools/legado-compat/fixtures/legado-issue-009-database-migration-idempotency.json'
$failurePath = 'tools/legado-compat/evidence/contract-legado-issue-009-database-migration-pre-fix-20260809.json'
$postFixPath = 'tools/legado-compat/evidence/contract-legado-issue-009-database-migration-post-fix-20260809.json'
$witnessPath = 'tools/legado-compat/device-evidence/continuous-governance-20260730-image-sync-regression.json'
$databaseManagerPath = 'entry/src/main/ets/Framework/Database/DatabaseManager.ets'
$databaseSchemaPath = 'entry/src/main/ets/Framework/Database/DatabaseSchema.ets'
$novelDataManagerPath = 'entry/src/main/ets/Framework/Novel/NovelDataManager.ets'

function Get-RepositoryPath([string]$RelativePath) {
  if ([System.IO.Path]::IsPathRooted($RelativePath)) { return $RelativePath }
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictText([string]$RelativePath) {
  $path = Get-RepositoryPath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing input: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw "UTF-8 BOM is not allowed: $RelativePath"
  }
  return $strictUtf8.GetString($bytes)
}

function Read-StrictJson([string]$RelativePath) {
  return (Read-StrictText $RelativePath | ConvertFrom-Json)
}

function Get-FileSha256([string]$RelativePath) {
  return (Get-FileHash -LiteralPath (Get-RepositoryPath $RelativePath) -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Set-PropertyValue([object]$Object, [string]$Name, [object]$Value) {
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force }
  else { $property.Value = $Value }
}

function Get-PropertyValue([object]$Object, [string]$Name) {
  if ($null -eq $Object) { return $null }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { return $null }
  return $property.Value
}

function Write-AtomicJson([string]$RelativePath, [object]$Value) {
  $path = Get-RepositoryPath $RelativePath
  $directory = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  }
  $temporary = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 80), $noBomUtf8)
    Move-Item -LiteralPath $temporary -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) }
  }
}

function Write-AtomicText([string]$RelativePath, [string]$Value) {
  $path = Get-RepositoryPath $RelativePath
  $directory = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  }
  $temporary = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporary, $Value, $noBomUtf8)
    Move-Item -LiteralPath $temporary -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) }
  }
}

function Assert-Registration([bool]$Condition, [string]$Message) {
  if (-not $Condition) { throw "ISSUE009_REGISTRATION_BLOCKED:$Message" }
}

$statePath = 'tools/legado-compat/state/full-source-validation-state.json'
$objectivePath = 'tools/legado-compat/state/refactor-objective.json'
$state = Read-StrictJson $statePath
$objective = Read-StrictJson $objectivePath
$fixture = Read-StrictJson $fixturePath
$failure = Read-StrictJson $failurePath
$postFix = Read-StrictJson $postFixPath
$witness = Read-StrictJson $witnessPath

Assert-Registration ([int]$state.baseline.sourceCount -eq $sourceCount) 'machine source count drifted'
Assert-Registration ([string]$state.baseline.sourcePackageSha256 -eq $sourceHash) 'machine source hash drifted'
Assert-Registration ([string]$state.baseline.legadoCommit -eq $legadoCommit) 'machine Legado commit drifted'
Assert-Registration ([int]$objective.baseline.sourceCount -eq $sourceCount) 'objective source count drifted'
Assert-Registration ([string]$objective.baseline.sourcePackageSha256 -eq $sourceHash) 'objective source hash drifted'
Assert-Registration ([string]$objective.baseline.legadoCommit -eq $legadoCommit) 'objective Legado commit drifted'
Assert-Registration ([string]$state.governance.activeIssueId -eq 'ISSUE-COMPAT-011') '011 must remain the prior active issue before atomic 009 selection.'
Assert-Registration ([string]$state.governance.status -eq 'running') 'governance is not running'
Assert-Registration ([string]$failure.status -eq 'failed') '009 failure witness was overwritten'
Assert-Registration ([string]$postFix.status -eq 'passed_static_only') '009 post-fix contract is not static-passed'
Assert-Registration ([string]$postFix.baseline.sourcePackageSha256 -eq $sourceHash) '009 post-fix evidence hash drifted'
Assert-Registration ([string]$postFix.baseline.legadoCommit -eq $legadoCommit) '009 post-fix Legado commit drifted'
Assert-Registration ([int]$postFix.affectedSourceSet.sourceCount -eq $sourceCount) '009 affected source set is not bound to all 458 records'
Assert-Registration (@($postFix.runtimeActionsPerformed).Count -eq 0) 'runtime actions were performed before R4'
Assert-Registration ([string]$witness.separateFinding.issueId -eq $issueId) 'historical device witness is not for ISSUE-COMPAT-009'

$sourceFixPath = 'tools/legado-compat/evidence/v2-issue-009-database-migration-source-fix-20260809.json'
$sourceFix = [ordered]@{
  schemaVersion = 1
  kind = 'legado_issue_009_database_migration_source_fix'
  status = 'passed_static_only'
  issueId = $issueId
  taskId = $taskId
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [ordered]@{ sourceCount = $sourceCount; sourcePackageSha256 = $sourceHash; legadoCommit = $legadoCommit }
  failureWitnessPath = $failurePath
  postFixContractPath = $postFixPath
  primaryCause = [ordered]@{
    classification = 'database_migration_idempotency_and_failure_propagation'
    statement = 'V2 previously defined versioned ALTER TABLE scripts without executing them and swallowed novel schema failures. The fix routes ADD COLUMN through PRAGMA table_info, advances PRAGMA user_version only after a version succeeds, removes destructive v5 drops, and propagates genuine table/index failures.'
  }
  affectedSourceSet = $postFix.affectedSourceSet
  changedFiles = @($databaseManagerPath, $databaseSchemaPath, $novelDataManagerPath)
  currentHeadHashes = [ordered]@{
    databaseManager = Get-FileSha256 $databaseManagerPath
    databaseSchema = Get-FileSha256 $databaseSchemaPath
    novelDataManager = Get-FileSha256 $novelDataManagerPath
  }
  v2Consumers = $postFix.v2Consumers
  scenarios = $postFix.scenarios
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_source_fix_static_only;009_verifying;final_build_and_cold_start_gate_after_source_queue'
  closeCondition = $postFix.closeCondition
  nextGate = 'source-queue-static-closure-then-final-hvigor-build-and-device-cold-start'
}
Write-AtomicJson $sourceFixPath $sourceFix

$issue = @($state.governance.issues | Where-Object { [string]$_.id -eq $issueId }) | Select-Object -First 1
Assert-Registration ($null -ne $issue) 'ISSUE-COMPAT-009 is missing from machine governance.'
Set-PropertyValue $issue 'taskId' $taskId
Set-PropertyValue $issue 'status' 'verifying'
Set-PropertyValue $issue 'severity' 'P1'
Set-PropertyValue $issue 'attempts' ([int](Get-PropertyValue $issue 'attempts') + 1)
Set-PropertyValue $issue 'summary' '数据库增量迁移已完成源码静态闭合：ADD COLUMN 先读取 PRAGMA table_info，版本脚本按 user_version 可重放，版本 5 不再删除用户表；小说表/索引错误不再被吞掉。R4 冷启动和构建验证仍待完成。'
Set-PropertyValue $issue 'closeCondition' '静态合同、失败见证、Legado Room migration 语义、458 条影响集合和 V2 消费者矩阵保持一致；最终构建与真机冷启动必须确认无重复列名错误且真实迁移失败会阻断初始化。'
Set-PropertyValue $issue 'evidencePaths' @($fixturePath, $witnessPath, $failurePath, $postFixPath, $sourceFixPath, $databaseManagerPath, $databaseSchemaPath, $novelDataManagerPath)
Set-PropertyValue $issue 'lastUpdatedAt' ([DateTimeOffset]::UtcNow.ToString('o'))
$task = @($state.governance.tasks | Where-Object { [string]$_.id -eq $taskId }) | Select-Object -First 1
Assert-Registration ($null -ne $task) 'COMPAT-009 task is missing from machine governance.'
Set-PropertyValue $task 'status' 'running'
Set-PropertyValue $task 'attempts' ([int](Get-PropertyValue $task 'attempts') + 1)
Set-PropertyValue $task 'lastUpdatedAt' ([DateTimeOffset]::UtcNow.ToString('o'))
Set-PropertyValue $state.governance 'activeIssueId' $issueId
Set-PropertyValue $state.governance 'activeTaskId' $parentTaskId
Set-PropertyValue $state.governance 'status' 'running'
Set-PropertyValue $state.governance 'currentSourceClosureBoundary' 'ISSUE-COMPAT-009'
Set-PropertyValue $state.governance 'semanticMatchAllowed' $false
Set-PropertyValue $state.governance 'runtimeActionsPerformed' @()

Import-Module -Name (Get-RepositoryPath 'tools/legado-compat/LegadoFullSourceState.psm1') -Force
Sync-LegadoStateDerivedFields -State $state
Write-LegadoStateCheckpoint -Path (Get-RepositoryPath $statePath) -State $state -Depth 80

$objective.targetRevision = $revision
Set-PropertyValue $objective 'lastReviewedAt' ([DateTimeOffset]::UtcNow.ToString('o'))
Set-PropertyValue $objective 'continuationMode' 'R3_ISSUE_009_DATABASE_MIGRATION_STATIC_CLOSED_WAIT_SOURCE_QUEUE'
Set-PropertyValue $objective 'nextAction' '继续按单议题协议补齐下一个源码根因；009 保持 verifying，任何静态证据不得直接改写为 passed 或 semantic_match。源码队列收敛后统一执行最终构建和真机冷启动门禁。'
Set-PropertyValue $objective.authority 'activeIssueId' $issueId
Set-PropertyValue $objective.authority 'activeIssueSelection' 'full-source-validation-state.json 是唯一队列事实源；ISSUE-COMPAT-009 已通过五项静态证据门禁并成为唯一活动源码议题，011 与历史闭合保持 verifying 等待最终 R4。'
Set-PropertyValue $objective.objective 'statement' '在固定 458 条书源、源包哈希和 Legado 提交下，持续完成 V2 兼容层源码级根因治理，直至所有已发现源码缺陷闭合并通过最终 Hvigor 构建和真机冷启动验证。静态闭合不等同运行时兼容，禁止旧执行器回退和静默空值。'
Set-PropertyValue $objective.objective 'currentWorkstream' 'R3-ISSUE-009-DATABASE-MIGRATION-STATIC-CLOSED'
Set-PropertyValue $objective.objective 'activeIssue' $issueId
Set-PropertyValue $objective.objective 'activeIssueRule' 'ISSUE-COMPAT-009 保持 verifying；先完成源码队列和证据闭环，最后统一执行构建、安装、真机冷启动、确定性 Harness 和 Legado 差分。'
Set-PropertyValue $objective.executionTarget 'currentIssue' $issueId
Set-PropertyValue $objective.executionTarget 'nextIssues' @()
Set-PropertyValue $objective.executionTarget 'statement' '围绕当前文档已确认的问题持续做源码级根因修复；每个议题先失败见证再修复，状态和证据原子登记。所有源码议题闭合后统一进行最终编译验证，再向用户报告完成。'
Set-PropertyValue $objective.executionTarget 'forbiddenActions' @(
  '通过旧 NovelSourceExecutor、缓存、空结果或未执行流程掩盖 V2 差异',
  '在源码队列闭合前启动 458 条全量运行时批次或真实网络回归',
  '把静态证据写成 passed 或 semantic_match',
  '绕过登录、验证码、付费和设备交互策略'
)
Set-PropertyValue $objective.executionTarget 'finalValidation' @(
  '源码队列所有 P0/P1 根因均有失败前、修复后和 current-head 证据',
  '静态检查、ArkTS 类型检查和确定性合同通过',
  '使用 JDK 21 与已验证 Hvigor 入口完成 debug 构建',
  '构建产物安装到真机并完成冷启动/书源管理 smoke，迁移错误真实阻断且无重复列名噪声',
  '最终验收前才允许更新目标为 complete'
)
Set-PropertyValue $objective.continuationTarget 'activeBoundary' 'ISSUE-COMPAT-009 保持 verifying：数据库迁移幂等和错误传播源码已静态闭合；011 与历史源码议题继续等待最终验证。'
Set-PropertyValue $objective.continuationTarget 'nextTransition' '补齐下一个源码根因的五项证据；源码队列完成后进入统一最终构建/真机冷启动门禁。'
$queueAudit = $objective.continuationTarget.queueAudit
Set-PropertyValue $queueAudit 'status' 'source_fix_static_closed_wait_source_queue'
Set-PropertyValue $queueAudit 'currentAnchor' $issueId
Set-PropertyValue $queueAudit 'selectedIssue' $issueId
Set-PropertyValue $queueAudit 'candidateStatus' 'source_fix_static_closed'
Set-PropertyValue $queueAudit 'candidateGateStatus' 'source_fix_registered_static_only'
Set-PropertyValue $queueAudit 'candidateTargetEvidencePath' $fixturePath
Set-PropertyValue $queueAudit 'candidateFailureWitnessPath' $failurePath
Set-PropertyValue $queueAudit 'candidateCurrentHeadAuditEvidencePath' $postFixPath
Set-PropertyValue $queueAudit 'candidateSourceFixEvidencePath' $sourceFixPath
Set-PropertyValue $queueAudit 'nextRequired' '继续补齐下一个源码议题的五项证据；R4/最终构建和设备门禁统一留到源码队列收敛后。'
Set-PropertyValue $objective 'completionGate' @(
  '458 条固定基线、源包 SHA-256 和 Legado commit 不漂移',
  '所有已发现源码根因均有可复现失败见证、修复证据、消费者矩阵和关闭条件',
  '所有静态合同、UTF-8/JSON/哈希检查和文档一致性门禁通过',
  '最终使用 JDK 21 和已验证 Hvigor 入口完成 debug 构建，构建失败不得宣称完成',
  '真机安装和冷启动验证无闪退、无重复列名错误，书源管理页面可启动且 V2 路径没有隐藏旧执行器回退',
  '只有上述证据全部存在时才把持续目标写成 complete'
)
foreach ($phase in @($objective.phases)) {
  if ([string]$phase.id -eq 'R3') {
    $issues = @($phase.issues | ForEach-Object { [string]$_ })
    if ($issues -notcontains $issueId) { Set-PropertyValue $phase 'issues' (@($issues) + @($issueId)) }
  }
}
Write-AtomicJson $objectivePath $objective

& pwsh -NoLogo -NoProfile -NonInteractive -File (Get-RepositoryPath 'tools/legado-compat/Set-LegadoRefactorObjective.ps1') `
  -StatePath (Get-RepositoryPath $statePath) `
  -ObjectivePath (Get-RepositoryPath $objectivePath) `
  -ActiveIssueId $issueId | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Refactor objective attachment failed.' }

& pwsh -NoLogo -NoProfile -NonInteractive -File (Get-RepositoryPath 'tools/legado-compat/Invoke-LegadoCompatibility.ps1') -RefreshDocumentsOnly | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Compatibility document refresh failed.' }

$objectiveDocPath = 'docs/analysis/Legado书源V2源码重构持续目标.md'
$objectiveDoc = Read-StrictText $objectiveDocPath
$startMarker = '## 下一持续执行目标'
$endMarker = '## 持续目标'
$section = @"
## 下一持续执行目标

当前目标修订为 ``$revision``，唯一活动源码议题为 ``$issueId``，状态保持 ``verifying``。本轮针对文档已确认的数据库迁移缺陷完成源码静态闭合：版本迁移按 ``PRAGMA user_version`` 重放，``ADD COLUMN`` 先查 ``PRAGMA table_info``，版本 5 不再删除用户数据表，小说表与索引错误不再被吞掉。

固定 Legado 语义证据来自 ``AppDatabase.kt`` 的迁移注册、``DatabaseMigrations.kt`` 的版本边界和 ``BookSource.kt`` 的持久化实体；影响范围绑定冻结 458 条书源，但不把数据库静态证据写成书源运行时通过。

证据：``$fixturePath``、``$failurePath``、``$postFixPath``、``$sourceFixPath``、``$witnessPath``。011 及历史源码议题保持 ``verifying``，不得覆盖失败前证据。

下一步继续补齐源码队列中的单一根因；全部源码修复和逻辑优化完成后，统一执行静态门禁、JDK 21 Hvigor debug 构建、真机安装与冷启动验证，只有证据齐全才报告目标完成。

"@
$pattern = '(?s)' + [regex]::Escape($startMarker) + '.*?(?=' + [regex]::Escape($endMarker) + ')'
if (-not [regex]::IsMatch($objectiveDoc, $pattern)) { throw 'objective document target section marker missing.' }
$objectiveDoc = [regex]::Replace($objectiveDoc, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $section })
Write-AtomicText $objectiveDocPath $objectiveDoc

$registration = [ordered]@{
  schemaVersion = 1
  kind = 'legado_issue_009_database_migration_registration'
  status = 'registered_verifying'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  objectiveRevision = $revision
  issueId = $issueId
  taskId = $taskId
  parentTaskId = $parentTaskId
  baseline = [ordered]@{ sourceCount = $sourceCount; sourcePackageSha256 = $sourceHash; legadoCommit = $legadoCommit }
  failureWitnessPath = $failurePath
  postFixContractPath = $postFixPath
  sourceFixEvidencePath = $sourceFixPath
  preFixWitnessPreserved = $true
  machineIssueStatus = 'verifying'
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  nextGate = 'next-source-root-cause-static-evidence-then-final-build-and-device-cold-start'
}
Write-AtomicJson $RegistrationEvidencePath $registration

$registration | ConvertTo-Json -Depth 20
