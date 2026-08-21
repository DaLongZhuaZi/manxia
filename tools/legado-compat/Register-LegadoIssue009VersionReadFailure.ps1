param(
  [string]$RepositoryRoot = '',
  [string]$EvidencePath = 'tools/legado-compat/evidence/v2-issue-009-database-version-read-failure-source-fix-20260809.json'
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
$fixturePath = 'tools/legado-compat/fixtures/legado-issue-009-database-migration-idempotency.json'
$preFixPath = 'tools/legado-compat/evidence/contract-legado-issue-009-database-migration-pre-fix-20260809.json'
$postFixPath = 'tools/legado-compat/evidence/contract-legado-issue-009-database-migration-post-fix-20260809.json'
$databaseManagerPath = 'entry/src/main/ets/Framework/Database/DatabaseManager.ets'
$databaseSchemaPath = 'entry/src/main/ets/Framework/Database/DatabaseSchema.ets'
$novelDataManagerPath = 'entry/src/main/ets/Framework/Novel/NovelDataManager.ets'
$novelInitializerPath = 'entry/src/main/ets/Framework/Novel/NovelInitializer.ets'
$contractPath = 'tools/legado-compat/Test-LegadoIssue009DatabaseMigrationContract.ps1'

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

function Assert-Contract([bool]$Condition, [string]$Message) {
  if (-not $Condition) { throw "ISSUE009_VERSION_READ_CONTRACT_FAILED:$Message" }
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

$statePath = 'tools/legado-compat/state/full-source-validation-state.json'
$objectivePath = 'docs/analysis/Legado书源V2源码重构持续目标.md'
$state = Read-StrictJson $statePath
$fixture = Read-StrictJson $fixturePath
$preFix = Read-StrictJson $preFixPath
$postFix = Read-StrictJson $postFixPath
$databaseManager = Read-StrictText $databaseManagerPath
$novelInitializer = Read-StrictText $novelInitializerPath

Assert-Contract ([int]$state.baseline.sourceCount -eq $sourceCount) 'machine source count drifted'
Assert-Contract ([string]$state.baseline.sourcePackageSha256 -eq $sourceHash) 'machine source hash drifted'
Assert-Contract ([string]$state.baseline.legadoCommit -eq $legadoCommit) 'machine Legado commit drifted'
Assert-Contract ([int]$fixture.baseline.sourceCount -eq $sourceCount) 'fixture source count drifted'
Assert-Contract ([string]$fixture.baseline.sourcePackageSha256 -eq $sourceHash) 'fixture source hash drifted'
Assert-Contract ([string]$fixture.baseline.legadoCommit -eq $legadoCommit) 'fixture Legado commit drifted'
Assert-Contract ([string]$preFix.status -eq 'failed') 'pre-fix failure evidence was overwritten'
Assert-Contract ([string]$postFix.status -eq 'passed_static_only') 'post-fix contract is not static-passed'
Assert-Contract (@($fixture.scenarios | Where-Object { [string]$_.id -eq 'version_read_failure' }).Count -eq 1) 'version_read_failure scenario is missing'
Assert-Contract (@($preFix.assertions | Where-Object { [string]$_.id -eq 'pre_fix_manager_swallowed_version_read_failure' -and $_.passed }).Count -eq 1) 'version-read failure witness is missing'
Assert-Contract (@($postFix.assertions | Where-Object { [string]$_.id -eq 'post_fix_manager_propagates_version_read_failure' -and $_.passed }).Count -eq 1) 'post-fix propagation contract is missing'
Assert-Contract (@($postFix.assertions | Where-Object { [string]$_.id -eq 'post_fix_initializer_propagates_restore_failure' -and $_.passed }).Count -eq 1) 'post-fix restore propagation contract is missing'
Assert-Contract ([string]$databaseManager -match '(?s)private async getDatabaseVersion\(\): Promise<number>.*?let resultSet: relationalStore\.ResultSet \| null = null;.*?finally.*?resultSet !== null.*?resultSet\.close\(\);') 'current DatabaseManager does not close the version result set in finally'
Assert-Contract ([string]$databaseManager -match '(?s)private async getDatabaseVersion\(\): Promise<number>.*?catch \(error\).*?throw error as Error;') 'current DatabaseManager does not propagate version-read failures'
Assert-Contract ([string]$novelInitializer -match '(?s)private async loadSavedSources\(\): Promise<void>.*?catch \(error\).*?throw error as Error;') 'current NovelInitializer does not propagate restore failures'
$legadoHead = (& git -C (Get-RepositoryPath 'legado') rev-parse HEAD 2>$null | Out-String).Trim()
Assert-Contract ($legadoHead -eq $legadoCommit) 'Legado checkout is not pinned to the baseline commit'

$newAssertions = @(
  [pscustomobject][ordered]@{ id = 'version_read_failure_witness'; status = 'passed'; detail = 'Pre-fix contract records that a PRAGMA user_version failure returned 0 and could replay migrations from an unknown version.' },
  [pscustomobject][ordered]@{ id = 'version_read_failure_propagation'; status = 'passed_static_only'; detail = 'The fixed getDatabaseVersion path throws the original failure instead of returning 0.' },
  [pscustomobject][ordered]@{ id = 'version_result_set_cleanup'; status = 'passed_static_only'; detail = 'The fixed getDatabaseVersion path closes a result set in finally, including goToFirstRow/getLong failures.' },
  [pscustomobject][ordered]@{ id = 'database_index_failure_propagation'; status = 'passed_static_only'; detail = 'The fixed DatabaseManager path propagates a genuine CREATE INDEX schema failure instead of reporting initialization success.' },
  [pscustomobject][ordered]@{ id = 'saved_source_restore_failure_propagation'; status = 'passed_static_only'; detail = 'NovelInitializer now exposes persisted source and compatibility restore failures instead of marking the source manager ready.' }
)
$sourceFix = [ordered]@{
  schemaVersion = 1
  kind = 'legado_issue_009_database_version_read_failure_source_fix'
  status = 'passed_static_only'
  issueId = $issueId
  taskId = $taskId
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [ordered]@{ sourceCount = $sourceCount; sourcePackageSha256 = $sourceHash; legadoCommit = $legadoCommit }
  primaryCause = [ordered]@{
    classification = 'database_migration_initialization_failure_propagation'
    statement = 'DatabaseManager treated a failed or empty PRAGMA user_version query as version 0 and swallowed genuine index/schema failures, while NovelDataManager and NovelInitializer could hide persisted source restore failures. The fixed paths close ResultSets in finally, propagate all database and source initialization failures, and keep initialization blocked until the persisted state is coherent.'
  }
  failureWitnessPath = $preFixPath
  postFixContractPath = $postFixPath
  targetFixturePath = $fixturePath
  affectedSourceSet = $fixture.affectedSourceSet
  changedFiles = @($databaseManagerPath, $databaseSchemaPath, $novelDataManagerPath, $novelInitializerPath, $fixturePath, $contractPath)
  currentHeadHashes = [ordered]@{
    databaseManager = Get-FileSha256 $databaseManagerPath
    databaseSchema = Get-FileSha256 $databaseSchemaPath
    novelDataManager = Get-FileSha256 $novelDataManagerPath
    novelInitializer = Get-FileSha256 $novelInitializerPath
    fixture = Get-FileSha256 $fixturePath
    contract = Get-FileSha256 $contractPath
  }
  legadoSemantics = @(
    'Room opens a database only after the version-bounded migration chain is accepted.',
    'A migration boundary must never infer an older schema after metadata access fails.',
    'Migration failure remains visible to the caller so initialization can be blocked and retried.',
    'CREATE INDEX IF NOT EXISTS is idempotent only for an existing index; missing schema dependencies remain fatal.',
    'Persisted source restore failure remains visible to NovelInitializer; a partial source map is not reported as ready.'
  )
  scenarios = @($fixture.scenarios)
  assertions = $newAssertions
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_source_fix_static_only;009_verifying;final_build_and_cold_start_gate'
  closeCondition = 'Static contract remains green and a later device cold-start gate confirms no duplicate-column error; a deterministic fault-injection or equivalent runtime trace must still prove that version-read and persisted-source-restore failures block initialization.'
  nextGate = 'source-queue-static-closure-then-final-hvigor-build-and-device-cold-start'
}
Write-AtomicJson $EvidencePath $sourceFix

$updateScript = Get-RepositoryPath 'tools/legado-compat/Update-LegadoGovernanceState.ps1'
$evidenceArgument = @($EvidencePath, $fixturePath, $preFixPath, $postFixPath, $databaseManagerPath, $databaseSchemaPath, $novelDataManagerPath, $novelInitializerPath, $contractPath) -join ','
& pwsh -NoLogo -NoProfile -NonInteractive -File $updateScript `
  -StatePath (Get-RepositoryPath $statePath) `
  -IssueId $issueId `
  -IssueStatus verifying `
  -TaskId $taskId `
  -TaskStatus running `
  -Severity P1 `
  -Summary '009 源码治理追加完成：PRAGMA user_version 读取失败不再回退到版本 0；结果集在 finally 关闭，书源恢复失败也不再被 NovelInitializer 吞掉。静态失败/修复合同已通过，设备冷启动与最终运行时验证仍延期。' `
  -CloseCondition '静态合同、失败见证、Legado Room migration 语义、458 条影响集合和 V2 消费者矩阵保持一致；最终构建与真机冷启动必须确认无重复列名错误、版本读取失败和书源恢复失败真实阻断初始化。' `
  -EvidencePath $evidenceArgument `
  -IncrementAttempt
if ($LASTEXITCODE -ne 0) { throw 'Governance state update failed.' }

$objectiveDoc = Read-StrictText $objectivePath
$startMarker = '## 下一持续执行目标'
$endMarker = '## 持续目标'
$section = @"
## 下一持续执行目标

当前目标修订保持 ``2026-08-09-r4-device-241-verified-return-issue009``，唯一活动源码议题为 ``$issueId``，状态保持 ``verifying``。本轮追加闭合数据库初始化错误传播：旧实现将 ``PRAGMA user_version`` 查询异常转换为版本 0，且 ``NovelInitializer.loadSavedSources`` 吞掉持久化书源恢复异常；现实现对空结果显式失败、原始异常继续向初始化调用方传播，在 ``finally`` 关闭结果集，并保持书源管理器未就绪直到恢复完成。

009 的八项迁移/初始化场景（已有列、缺失列、部分升级重放、无关 SQL 失败、索引创建失败、版本读取失败、书源恢复失败、历史数据保留）均已绑定冻结 458 条书源、Legado 提交和新的静态失败/修复证据。该证据仍是源码闭合，不是书源运行时通过；真机迁移故障注入、最终构建和统一回归继续延期。

证据：``$EvidencePath``、``$fixturePath``、``$preFixPath``、``$postFixPath``。全部源码修复和逻辑优化完成后，统一执行静态门禁、JDK 21 Hvigor debug 构建、真机安装与冷启动验证，只有证据齐全才报告目标完成。

"@
$pattern = '(?s)' + [regex]::Escape($startMarker) + '.*?(?=' + [regex]::Escape($endMarker) + ')'
if (-not [regex]::IsMatch($objectiveDoc, $pattern)) { throw 'objective document target section marker missing.' }
$objectiveDoc = [regex]::Replace($objectiveDoc, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $section })
Write-AtomicText $objectivePath $objectiveDoc

$sourceFix | ConvertTo-Json -Depth 40
