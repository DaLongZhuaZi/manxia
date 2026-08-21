[CmdletBinding()]
param(
  [ValidateSet('PreFix', 'PostFix')]
  [string]$Phase = 'PostFix',
  [string]$RepositoryRoot = '',
  [string]$OutputPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$sourceHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$sourceCount = 458
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$fixtureRelative = 'tools/legado-compat/fixtures/legado-issue-009-database-migration-idempotency.json'
$databaseManagerRelative = 'entry/src/main/ets/Framework/Database/DatabaseManager.ets'
$databaseSchemaRelative = 'entry/src/main/ets/Framework/Database/DatabaseSchema.ets'
$novelDataManagerRelative = 'entry/src/main/ets/Framework/Novel/NovelDataManager.ets'
$novelInitializerRelative = 'entry/src/main/ets/Framework/Novel/NovelInitializer.ets'

function Get-RepoPath {
  param([string]$RelativePath)
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictText {
  param([string]$Path, [switch]$AllowBom)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing file: $Path" }
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  $offset = 0
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    if (-not $AllowBom) { throw "UTF-8 BOM is not allowed: $Path" }
    $offset = 3
  }
  return $strictUtf8.GetString($bytes, $offset, $bytes.Length - $offset)
}

function Read-Json {
  param([string]$Path)
  return (Read-StrictText -Path $Path | ConvertFrom-Json)
}

function Assert-Contract {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "CONTRACT_FAILED: $Message" }
}

function Write-AtomicJson {
  param([string]$Path, [object]$Value)
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  }
  $temporaryPath = "$Path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 30), $noBomUtf8)
    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

function Get-FileSha256 {
  param([string]$Path)
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Get-RelativePath {
  param([string]$Path)
  return ([System.IO.Path]::GetRelativePath($RepositoryRoot, $Path)).Replace('\', '/')
}

$fixturePath = Get-RepoPath $fixtureRelative
$fixture = Read-Json $fixturePath
Assert-Contract ([int]$fixture.baseline.sourceCount -eq $sourceCount) 'Fixture source count drifted.'
Assert-Contract ([string]$fixture.baseline.sourcePackageSha256 -eq $sourceHash) 'Fixture source hash drifted.'
Assert-Contract ([string]$fixture.baseline.legadoCommit -eq $legadoCommit) 'Fixture Legado commit drifted.'

$packagePath = 'F:\Downloads-E\墨辰整理书源大全7.1（禁止倒卖）.【最新完整】.json'
Assert-Contract (Test-Path -LiteralPath $packagePath -PathType Leaf) 'Frozen source package is missing.'
Assert-Contract ((Get-FileSha256 $packagePath) -eq $sourceHash) 'Frozen source package hash drifted.'
$sourceDocuments = Get-Content -LiteralPath $packagePath -Encoding UTF8 -Raw | ConvertFrom-Json
Assert-Contract (@($sourceDocuments).Count -eq $sourceCount) 'Frozen source package count drifted.'
$legadoHead = (& git -C (Get-RepoPath 'legado') rev-parse HEAD 2>$null | Out-String).Trim()
Assert-Contract ($legadoHead -eq $legadoCommit) 'Legado checkout is not pinned to the baseline commit.'

$legadoMigration = Read-StrictText (Get-RepoPath 'legado/app/src/main/java/io/legado/app/data/DatabaseMigrations.kt')
$legadoDatabase = Read-StrictText (Get-RepoPath 'legado/app/src/main/java/io/legado/app/data/AppDatabase.kt')
$legadoBookSource = Read-StrictText (Get-RepoPath 'legado/app/src/main/java/io/legado/app/data/entities/BookSource.kt')
Assert-Contract ($legadoDatabase -match 'addMigrations\(\*DatabaseMigrations\.migrations\)') 'Legado Room migration registration missing.'
Assert-Contract ($legadoMigration -match 'migration_19_20') 'Legado version-bounded book source migration missing.'
Assert-Contract ($legadoMigration -match 'ALTER TABLE book_sources ADD bookSourceComment') 'Legado source table migration semantic witness missing.'
Assert-Contract ($legadoBookSource -match '@Entity\(\s*tableName = "book_sources"') 'Legado BookSource persistence table witness missing.'

$currentFiles = @(
  (Get-RepoPath $databaseManagerRelative),
  (Get-RepoPath $databaseSchemaRelative),
  (Get-RepoPath $novelDataManagerRelative),
  (Get-RepoPath $novelInitializerRelative)
)
foreach ($path in $currentFiles) { [void](Read-StrictText $path) }

$currentDatabaseManager = Read-StrictText (Get-RepoPath $databaseManagerRelative)
$currentDatabaseSchema = Read-StrictText (Get-RepoPath $databaseSchemaRelative)
$currentNovelDataManager = Read-StrictText (Get-RepoPath $novelDataManagerRelative)
$currentNovelInitializer = Read-StrictText (Get-RepoPath $novelInitializerRelative)
$preFixManagerPath = Get-RepoPath ($databaseManagerRelative + '.bak_20260809_issue009_pre_fix')
$preFixSchemaPath = Get-RepoPath ($databaseSchemaRelative + '.bak_20260809_issue009_pre_fix')
$preFixNovelDataPath = Get-RepoPath ($novelDataManagerRelative + '.bak_20260809_issue009_pre_fix')
$preFixNovelInitializerPath = Get-RepoPath ($novelInitializerRelative + '.bak_20260809_issue009_pre_fix')

$assertions = New-Object 'System.Collections.Generic.List[object]'
function Add-Assertion {
  param([string]$Id, [bool]$Passed, [string]$Detail)
  [void]$assertions.Add([pscustomobject][ordered]@{ id = $Id; passed = $Passed; detail = $Detail })
  Assert-Contract $Passed $Detail
}

if ($Phase -eq 'PreFix') {
  $oldManager = Read-StrictText -Path $preFixManagerPath -AllowBom
  $oldSchema = Read-StrictText -Path $preFixSchemaPath -AllowBom
  $oldNovelData = Read-StrictText -Path $preFixNovelDataPath -AllowBom
  $oldNovelInitializer = Read-StrictText -Path $preFixNovelInitializerPath -AllowBom
  Add-Assertion 'pre_fix_manager_did_not_run_versioned_migrations' ($oldManager -notmatch 'applyVersionedMigrations') 'Pre-fix manager did not execute the versioned migration table.'
  Add-Assertion 'pre_fix_schema_contained_destructive_v5' ($oldSchema -match 'DROP TABLE IF EXISTS page') 'Pre-fix version 5 migration still dropped user tables.'
  Add-Assertion 'pre_fix_novel_manager_swallowed_schema_error' ($oldNovelData -notmatch 'throw error as Error;') 'Pre-fix novel manager swallowed a schema error and could report success.'
  Add-Assertion 'pre_fix_manager_swallowed_version_read_failure' ($oldManager -match '(?s)private async getDatabaseVersion\(\): Promise<number>.*?catch \(error\).*?return 0;') 'Pre-fix DatabaseManager converted a PRAGMA user_version failure into version 0.'
  Add-Assertion 'pre_fix_manager_swallowed_index_failure' ($oldManager -match '(?s)private async createIndexes\(\): Promise<void>.*?catch \(error\).*?索引创建失败不应该阻止数据库初始化') 'Pre-fix DatabaseManager swallowed an index/schema failure and could report database initialization success.'
  Add-Assertion 'pre_fix_initializer_swallowed_restore_failure' ($oldNovelInitializer -match '(?s)private async loadSavedSources\(\): Promise<void>.*?catch \(error\).*?加载已保存书源失败.*?\}') 'Pre-fix NovelInitializer swallowed persisted source restore failures.'
  Add-Assertion 'pre_fix_novel_manager_skipped_source_parse_failure' ($oldNovelData -match '(?s)async getAllSources\(\): Promise<LegadoBookSource\[\]>.*?catch \(e\).*?忽略解析错误') 'Pre-fix getAllSources silently skipped malformed persisted source JSON.'
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_issue_009_database_migration_contract'
    phase = 'pre_fix'
    status = 'failed'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    baseline = [pscustomobject][ordered]@{ sourceCount = $sourceCount; sourcePackageSha256 = $sourceHash; legadoCommit = $legadoCommit }
    failureWitness = $fixture.failureWitness
    assertions = $assertions.ToArray()
    runtimeActionsPerformed = @()
  }
} else {
  Add-Assertion 'post_fix_manager_runs_versioned_migrations' ($currentDatabaseManager -match 'await this\.applyVersionedMigrations\(\);') 'DatabaseManager must execute versioned migrations during initialization.'
  Add-Assertion 'post_fix_manager_inspects_add_column' ($currentDatabaseManager -match 'executeIdempotentMigration' -and $currentDatabaseManager -match 'ensureTableColumn') 'ADD COLUMN migrations must use schema inspection.'
  Add-Assertion 'post_fix_manager_replays_by_user_version' ($currentDatabaseManager -match 'getDatabaseVersion' -and $currentDatabaseManager -match 'MIGRATION_SCRIPTS\[version\]') 'Migrations must be bounded by PRAGMA user_version.'
  Add-Assertion 'post_fix_manager_propagates_version_read_failure' ($currentDatabaseManager -match '(?s)private async getDatabaseVersion\(\): Promise<number>.*?let resultSet: relationalStore\.ResultSet \| null = null;.*?resultSet = await store\.querySql\([^)]*PRAGMA user_version.*?catch \(error\).*?throw error as Error;') 'DatabaseManager must not restart migration from version 0 when PRAGMA user_version fails.'
  Add-Assertion 'post_fix_manager_closes_version_result_set' ($currentDatabaseManager -match '(?s)private async getDatabaseVersion\(\): Promise<number>.*?finally.*?resultSet !== null.*?resultSet\.close\(\);') 'DatabaseManager must close the PRAGMA user_version result set on every path.'
  Add-Assertion 'post_fix_manager_propagates_index_failure' ($currentDatabaseManager -match '(?s)private async createIndexes\(\): Promise<void>.*?catch \(error\).*?创建索引失败:[^\n]*[\s\S]{0,500}throw error as Error;') 'DatabaseManager must propagate genuine index/schema failures.'
  Add-Assertion 'post_fix_manager_keeps_index_idempotency_explicit' ($currentDatabaseSchema -match 'CREATE INDEX IF NOT EXISTS') 'Index creation remains idempotent for an already-present index while genuine errors propagate.'
  Add-Assertion 'post_fix_initializer_propagates_restore_failure' ($currentNovelInitializer -match '(?s)private async loadSavedSources\(\): Promise<void>.*?catch \(error\).*?加载已保存书源失败.*?throw error as Error;') 'NovelInitializer must propagate persisted source restore failures to its initialization result.'
  Add-Assertion 'post_fix_initializer_keeps_manager_unready_on_restore_failure' ($currentNovelInitializer -match '(?s)await this\.loadSavedSources\(\);\s*\}\s*sourceManagerInitialized = true;') 'NovelInitializer must only mark the source manager initialized after restore succeeds.'
  Add-Assertion 'post_fix_novel_manager_propagates_source_parse_failure' ($currentNovelDataManager -match '(?s)async getAllSources\(\): Promise<LegadoBookSource\[\]>.*?catch \(error\).*?throw new Error\(') 'getAllSources must expose malformed persisted source JSON.'
  Add-Assertion 'post_fix_novel_manager_closes_source_result_set' ($currentNovelDataManager -match '(?s)async getAllSources\(\): Promise<LegadoBookSource\[\]>.*?finally.*?rs\.close\(\);') 'getAllSources must close its result set on every path.'
  Add-Assertion 'post_fix_v5_preserves_data' ($currentDatabaseSchema -notmatch 'DROP TABLE IF EXISTS page' -and $currentDatabaseSchema -notmatch 'DROP TABLE IF EXISTS chapter') 'Version 5 must not drop user data tables.'
  Add-Assertion 'post_fix_novel_manager_propagates_table_failure' ($currentNovelDataManager -match '创建表失败:[^\n]*[\s\S]{0,500}throw error as Error;') 'NovelDataManager must propagate table migration failures.'
  Add-Assertion 'post_fix_novel_manager_propagates_index_failure' ($currentNovelDataManager -match '创建小说索引失败:[^\n]*[\s\S]{0,500}throw error as Error;') 'NovelDataManager must propagate index failures.'
  Add-Assertion 'post_fix_no_legacy_swallow_comment' ($currentNovelDataManager -notmatch '索引可能已存在，忽略错误') 'The old blanket index-error swallow must be removed.'
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_issue_009_database_migration_contract'
    phase = 'post_fix'
    status = 'passed_static_only'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    baseline = [pscustomobject][ordered]@{ sourceCount = $sourceCount; sourcePackageSha256 = $sourceHash; legadoCommit = $legadoCommit }
    fixedLegadoSemantics = @(
      'Room registers version-bounded migrations before opening the source database.',
      'BookSource is persisted by bookSourceUrl and bookSourceType; incremental schema changes must preserve that identity.',
      'V2 applies the same version boundary without destructive fallback.'
    )
    affectedSourceSet = $fixture.affectedSourceSet
    v2Consumers = $fixture.v2Consumers
    scenarios = $fixture.scenarios
    assertions = $assertions.ToArray()
    sourceHashes = [pscustomobject][ordered]@{
      databaseManager = Get-FileSha256 (Get-RepoPath $databaseManagerRelative)
      databaseSchema = Get-FileSha256 (Get-RepoPath $databaseSchemaRelative)
      novelDataManager = Get-FileSha256 (Get-RepoPath $novelDataManagerRelative)
      novelInitializer = Get-FileSha256 (Get-RepoPath $novelInitializerRelative)
    }
    closeCondition = $fixture.closeCondition
    runtimeActionsPerformed = @()
  }
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $suffix = if ($Phase -eq 'PreFix') { 'pre-fix' } else { 'post-fix' }
  $OutputPath = "tools/legado-compat/evidence/contract-legado-issue-009-database-migration-$suffix-20260809.json"
}
Write-AtomicJson (Get-RepoPath $OutputPath) $result
$result | ConvertTo-Json -Depth 30
