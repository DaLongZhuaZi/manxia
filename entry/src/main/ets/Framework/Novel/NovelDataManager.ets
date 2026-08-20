import { SafeUtils } from 'manxia_core/src/main/ets/Utils/SafeUtils';
/**
 * 小说数据管理器
 * 独立管理小说相关数据，不影响现有数据库
 * 
 * 文件路径: entry/src/main/ets/Framework/Novel/NovelDataManager.ets
 */

import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { NOVEL_CREATE_TABLE_SQL, NOVEL_CREATE_INDEX_SQL } from 'manxia_novel/src/main/ets/Framework/Novel/NovelDatabaseSchema';
import { LegadoBookSource } from 'manxia_novel/src/main/ets/Framework/Novel/LegadoSourceTypes';
import {
  LegadoCompatibilityEngineMode,
  LegadoCompatibilityStatus,
  LegadoCompatibilityStorageRecord,
  LegadoContentTraceDiagnostics,
  LegadoExecutionErrorCode,
  LegadoNetworkTraceEvidence,
  LegadoExecutionTraceSummary,
  LegadoFinalUrlObservation,
  LegadoSourceVerificationRecord,
  LegadoTransportKind,
  LegadoWorkflowKind
} from 'manxia_novel/src/main/ets/Framework/Novel/LegadoCompatibilityTypes';
import { NovelBook, NovelChapter, NovelReadProgress, NovelReaderSettings, DEFAULT_NOVEL_READER_SETTINGS, NovelReadStatus } from 'manxia_core/src/main/ets/Models/NovelModels';
import { getNovelLoginManager } from './NovelLoginManager';
import { getNovelCoverGenerator } from 'manxia_novel/src/main/ets/Framework/Novel/NovelCoverGenerator';
import { LibraryCoverManager } from 'manxia_core/src/main/ets/Framework/Storage/LibraryCoverManager';
import { getUnifiedAnnotationManager } from '../Annotations/UnifiedAnnotationManager';
import { UnifiedContentType } from 'manxia_core/src/main/ets/Models/UnifiedContentModels';

const TAG = 'NovelDataManager';

/**
 * 表信息接口
 */
interface TableInfo {
  name: string;
  sql: string;
}

/**
 * 小说数据管理器类
 */
export class NovelDataManager {
  private static instance: NovelDataManager | null = null;
  private store: relationalStore.RdbStore | null = null;
  private isInitialized: boolean = false;
  private filesDir: string = '';

  private constructor() {}

  static getInstance(): NovelDataManager {
    if (!NovelDataManager.instance) {
      NovelDataManager.instance = new NovelDataManager();
    }
    return NovelDataManager.instance;
  }

  /**
   * 初始化数据库（使用现有数据库连接）
   */
  async initialize(context: common.UIAbilityContext): Promise<void> {
    if (this.isInitialized) {
      return;
    }

    try {
      logger.info(TAG, '开始初始化小说数据库表');
      
      const config: relationalStore.StoreConfig = {
        name: 'manxia_comic.db',
        securityLevel: relationalStore.SecurityLevel.S1,
        encrypt: false,
      };

      this.store = await relationalStore.getRdbStore(context, config);
      await this.store.executeSql('PRAGMA journal_mode=WAL');
      this.filesDir = context.filesDir;
      
      // 创建小说相关表（增量添加，不影响现有表）
      await this.createNovelTables();
      
      // 创建索引
      await this.createNovelIndexes();
      
      // 初始化登录管理器（加载持久化的Cookie）
      const loginManager = getNovelLoginManager();
      await loginManager.initialize(context);
      
      // 初始化封面生成器
      const coverGenerator = getNovelCoverGenerator();
      await coverGenerator.initialize(context.filesDir);
      
      this.isInitialized = true;
      logger.info(TAG, '小说数据库表初始化完成');
    } catch (error) {
      const errMsg = `小说数据库初始化失败: ${String(error)}`;
      logger.error(TAG, errMsg);
      throw new Error(errMsg);
    }
  }

  getStore(): relationalStore.RdbStore {
    if (!this.store) {
      throw new Error('小说数据库未初始化');
    }
    return this.store;
  }

  /**
   * Reads SQLite's schema metadata before running a compatibility ALTER TABLE.
   * This keeps existing installations quiet while still surfacing a genuine
   * migration failure for a column that cannot be created.
   */
  private async hasTableColumn(tableName: string, columnName: string): Promise<boolean> {
    const store: relationalStore.RdbStore = this.getStore();
    const resultSet: relationalStore.ResultSet = await store.querySql(`PRAGMA table_info(${tableName})`);
    try {
      const nameColumnIndex: number = resultSet.getColumnIndex('name');
      if (nameColumnIndex < 0) {
        throw new Error(`无法读取小说表结构字段: ${tableName}`);
      }
      while (resultSet.goToNextRow()) {
        if (resultSet.getString(nameColumnIndex) === columnName) {
          return true;
        }
      }
      return false;
    } finally {
      resultSet.close();
    }
  }

  private async ensureTableColumn(
    tableName: string,
    columnName: string,
    columnDefinition: string
  ): Promise<void> {
    if (await this.hasTableColumn(tableName, columnName)) {
      return;
    }
    const store: relationalStore.RdbStore = this.getStore();
    try {
      await store.executeSql(`ALTER TABLE ${tableName} ADD COLUMN ${columnName} ${columnDefinition}`);
    } catch {
      if (!await this.hasTableColumn(tableName, columnName)) {
        throw new Error(`新增小说数据库字段失败: ${tableName}.${columnName}`);
      }
    }
  }

  /**
   * 创建小说相关表
   */
  private async createNovelTables(): Promise<void> {
    const store = this.getStore();
    const tables: TableInfo[] = [
      { name: 'novel_source', sql: NOVEL_CREATE_TABLE_SQL.NOVEL_SOURCE } as TableInfo,
      { name: 'novel_source_compatibility', sql: NOVEL_CREATE_TABLE_SQL.NOVEL_SOURCE_COMPATIBILITY } as TableInfo,
      { name: 'novel_source_compatibility_verification', sql: NOVEL_CREATE_TABLE_SQL.NOVEL_SOURCE_COMPATIBILITY_VERIFICATION } as TableInfo,
      { name: 'novel_source_compatibility_trace', sql: NOVEL_CREATE_TABLE_SQL.NOVEL_SOURCE_COMPATIBILITY_TRACE } as TableInfo,
      { name: 'novel_source_compatibility_trace_workflow', sql: NOVEL_CREATE_TABLE_SQL.NOVEL_SOURCE_COMPATIBILITY_TRACE_WORKFLOW } as TableInfo,
      { name: 'novel_book', sql: NOVEL_CREATE_TABLE_SQL.NOVEL_BOOK } as TableInfo,
      { name: 'novel_chapter', sql: NOVEL_CREATE_TABLE_SQL.NOVEL_CHAPTER } as TableInfo,
      { name: 'novel_content_cache', sql: NOVEL_CREATE_TABLE_SQL.NOVEL_CONTENT_CACHE } as TableInfo,
      { name: 'novel_read_progress', sql: NOVEL_CREATE_TABLE_SQL.NOVEL_READ_PROGRESS } as TableInfo,
      { name: 'novel_reader_settings', sql: NOVEL_CREATE_TABLE_SQL.NOVEL_READER_SETTINGS } as TableInfo,
      { name: 'novel_replace_rule', sql: NOVEL_CREATE_TABLE_SQL.NOVEL_REPLACE_RULE } as TableInfo,
      { name: 'novel_search_history', sql: NOVEL_CREATE_TABLE_SQL.NOVEL_SEARCH_HISTORY } as TableInfo,
      { name: 'novel_txt_toc_rule', sql: NOVEL_CREATE_TABLE_SQL.NOVEL_TXT_TOC_RULE } as TableInfo,
      { name: 'novel_dict_rule', sql: NOVEL_CREATE_TABLE_SQL.NOVEL_DICT_RULE } as TableInfo
    ];

    for (const table of tables) {
      try {
        await store.executeSql(table.sql);
        logger.debug(TAG, `创建表成功: ${table.name}`);
        
        // 为 novel_source 表添加可能缺失的 isNSFW 列
        if (table.name === 'novel_source') {
          await this.ensureTableColumn('novel_source', 'isNSFW', 'INTEGER DEFAULT 0');
          await store.executeSql('UPDATE novel_source SET isNSFW = 0 WHERE isNSFW IS NULL');
          logger.info(TAG, '✅ [NOVEL_SOURCE] isNSFW列添加完成');
        }

        if (table.name === 'novel_source_compatibility_trace' ||
          table.name === 'novel_source_compatibility_trace_workflow') {
          await this.ensureTableColumn(table.name, 'requestTargetSha256', "TEXT NOT NULL DEFAULT ''");
          await this.ensureTableColumn(table.name, 'requestUserAgentSha256', "TEXT NOT NULL DEFAULT ''");
          await this.ensureTableColumn(table.name, 'responseContentType', "TEXT NOT NULL DEFAULT ''");
          await this.ensureTableColumn(table.name, 'redirectCount', 'INTEGER NOT NULL DEFAULT 0');
          await this.ensureTableColumn(table.name, 'contentDiagnosticStatus', "TEXT NOT NULL DEFAULT ''");
          await this.ensureTableColumn(table.name, 'contentCharacterCount', 'INTEGER NOT NULL DEFAULT 0');
          await this.ensureTableColumn(table.name, 'contentBridgeStatus', "TEXT NOT NULL DEFAULT ''");
          await this.ensureTableColumn(table.name, 'contentBridgeCharacterCount', 'INTEGER NOT NULL DEFAULT 0');
          await this.ensureTableColumn(table.name, 'contentBridgeFingerprint', "TEXT NOT NULL DEFAULT ''");
          await this.ensureTableColumn(table.name, 'contentFingerprint', "TEXT NOT NULL DEFAULT ''");
        }
        
        // 为 novel_book 表添加可能缺失的列
        if (table.name === 'novel_book') {
          logger.info(TAG, '🔧 [NOVEL_BOOK] 添加隐私列');
          await this.ensureTableColumn('novel_book', 'isPrivate', 'INTEGER DEFAULT 0');
          await this.ensureTableColumn('novel_book', 'isNSFW', 'INTEGER DEFAULT 0');
          await store.executeSql('UPDATE novel_book SET isPrivate = 0 WHERE isPrivate IS NULL');
          await store.executeSql('UPDATE novel_book SET isNSFW = 0 WHERE isNSFW IS NULL');
          logger.info(TAG, '✅ [NOVEL_BOOK] 列添加完成');
        }
      } catch (error) {
        logger.error(TAG, `创建表失败: ${table.name}, ${String(error)}`);
        // Do not report a successful novel/source initialization after a
        // schema migration failure. Callers must surface a blocked database
        // state and retry after the underlying issue is fixed.
        throw error as Error;
      }
    }
  }

  /**
   * 创建索引
   */
  private async createNovelIndexes(): Promise<void> {
    const store = this.getStore();
    for (const sql of NOVEL_CREATE_INDEX_SQL) {
      try {
        await store.executeSql(sql);
      } catch (error) {
        logger.error(TAG, `创建小说索引失败: ${sql}, ${String(error)}`);
        throw error as Error;
      }
    }
  }

  // ==================== 书源操作 ====================

  /**
   * 保存书源
   */
  async saveSource(source: LegadoBookSource): Promise<string> {
    const store = this.getStore();
    const id = this.generateId();
    const now = Date.now();

    const sql = `INSERT OR REPLACE INTO novel_source 
      (id, bookSourceUrl, bookSourceName, bookSourceGroup, bookSourceType, 
       enabled, weight, lastUpdateTime, respondTime, configJson, isNSFW, createTime, updateTime)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`;

    await store.executeSql(sql, [
      id,
      source.bookSourceUrl,
      source.bookSourceName,
      source.bookSourceGroup || '',
      source.bookSourceType,
      source.enabled !== false ? 1 : 0,
      source.weight || 0,
      source.lastUpdateTime || now,
      source.respondTime || 180000,
      JSON.stringify(source),
      source.isNSFW ? 1 : 0,
      now,
      now
    ]);

    return id;
  }

  /**
   * Commits the legacy-normalized row and V2's verbatim document as one
   * database transaction.  A source must never appear in novel_source while
   * its raw JSON/hash evidence is absent: otherwise a restart turns a claimed
   * V2 import back into an unverifiable legacy record.
   *
   * Use the supported RdbStore transaction lifecycle exposed by the Stage model.
   * The transaction-id overloads (`beginTrans`/`execute(..., txId)`) are
   * declared in the SDK but return capability-not-supported on the real
   * HarmonyOS device used by this app. The beginTransaction/executeSql/
   * commit/rollBack contract is the supported path and remains atomic.
   */
  async saveSourceWithCompatibilityRecord(
    source: LegadoBookSource,
    compatibilityRecord: LegadoCompatibilityStorageRecord
  ): Promise<string> {
    const store = this.getStore();
    const id = this.generateId();
    const now = Date.now();
    store.beginTransaction();
    let committed = false;

    try {
      const sourceSql = `INSERT OR REPLACE INTO novel_source
        (id, bookSourceUrl, bookSourceName, bookSourceGroup, bookSourceType,
         enabled, weight, lastUpdateTime, respondTime, configJson, isNSFW, createTime, updateTime)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`;
      await store.executeSql(sourceSql, [
        id,
        source.bookSourceUrl,
        source.bookSourceName,
        source.bookSourceGroup || '',
        source.bookSourceType,
        source.enabled !== false ? 1 : 0,
        source.weight || 0,
        source.lastUpdateTime || now,
        source.respondTime || 180000,
        JSON.stringify(source),
        source.isNSFW ? 1 : 0,
        now,
        now
      ]);

      const compatibilitySql = `INSERT OR REPLACE INTO novel_source_compatibility
        (sourceUrl, rawJson, rawSha256, compilerVersion, compileStatus, engineMode,
         capabilityJson, diagnosticsJson, compiledAt, updateTime)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`;
      await store.executeSql(compatibilitySql, [
        compatibilityRecord.sourceUrl,
        compatibilityRecord.rawJson,
        compatibilityRecord.rawSha256,
        compatibilityRecord.compilerVersion,
        compatibilityRecord.status,
        compatibilityRecord.engineMode,
        compatibilityRecord.capabilityJson,
        compatibilityRecord.diagnosticsJson,
        compatibilityRecord.compiledAt,
        compatibilityRecord.updatedAt
      ]);

      // Evidence belongs to a specific raw document. Keeping it after the JSON
      // changes would falsely qualify an untested source after a restart.
      await store.executeSql(
        'DELETE FROM novel_source_compatibility_verification WHERE sourceUrl = ? AND rawSha256 <> ?',
        [source.bookSourceUrl, compatibilityRecord.rawSha256]
      );
      await store.executeSql(
        'DELETE FROM novel_source_compatibility_trace WHERE sourceUrl = ? AND rawSha256 <> ?',
        [source.bookSourceUrl, compatibilityRecord.rawSha256]
      );
      await store.executeSql(
        'DELETE FROM novel_source_compatibility_trace_workflow WHERE sourceUrl = ? AND rawSha256 <> ?',
        [source.bookSourceUrl, compatibilityRecord.rawSha256]
      );

      store.commit();
      committed = true;
      return id;
    } catch (error) {
      if (!committed) {
        try {
          store.rollBack();
        } catch (rollbackError) {
          logger.error(TAG, `V2 无损导入事务回滚失败: ${String(rollbackError)}`);
        }
      }
      const errorMessage = String(error);
      logger.error(TAG, `V2 无损导入事务失败: ${errorMessage}`);
      throw new Error(errorMessage);
    }
  }

  async updateBookCoverLocalPath(bookId: string, coverLocalPath: string): Promise<void> {
    const store = this.getStore();
    await store.executeSql(
      'UPDATE novel_book SET coverLocalPath = ?, updateTime = ? WHERE id = ?',
      [coverLocalPath, Date.now(), bookId]
    );
    logger.info(TAG, `已更新小说本地封面路径: ${bookId} -> ${coverLocalPath}`);
  }

  /**
   * 获取所有书源
   */
  async getAllSources(): Promise<LegadoBookSource[]> {
    const store = this.getStore();
    const rs: relationalStore.ResultSet = await store.querySql('SELECT configJson FROM novel_source ORDER BY weight DESC');
    const sources: LegadoBookSource[] = [];

    let rowIndex: number = 0;
    try {
      if (rs.goToFirstRow()) {
        do {
          rowIndex += 1;
          try {
            const json = rs.getString(0);
            sources.push(SafeUtils.parseObj(json) as LegadoBookSource);
          } catch (error) {
            throw new Error(`持久化书源 JSON 解析失败: row=${rowIndex}; ${String(error)}`);
          }
        } while (rs.goToNextRow());
      }
      return sources;
    } finally {
      rs.close();
    }
  }

  /**
   * V2 persistence is intentionally separate from novel_source.configJson so a
   * failed compiler rollout cannot overwrite a user's legacy configuration.
   */
  async saveCompatibilityRecord(record: LegadoCompatibilityStorageRecord): Promise<void> {
    const store = this.getStore();
    await store.executeSql(
      `INSERT OR REPLACE INTO novel_source_compatibility
        (sourceUrl, rawJson, rawSha256, compilerVersion, compileStatus, engineMode,
         capabilityJson, diagnosticsJson, compiledAt, updateTime)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        record.sourceUrl,
        record.rawJson,
        record.rawSha256,
        record.compilerVersion,
        record.status,
        record.engineMode,
        record.capabilityJson,
        record.diagnosticsJson,
        record.compiledAt,
        record.updatedAt
      ]
    );
  }

  async getCompatibilityRecord(sourceUrl: string): Promise<LegadoCompatibilityStorageRecord | null> {
    const store = this.getStore();
    const result = await store.querySql(
      `SELECT sourceUrl, rawJson, rawSha256, compilerVersion, compileStatus, engineMode,
              capabilityJson, diagnosticsJson, compiledAt, updateTime
       FROM novel_source_compatibility WHERE sourceUrl = ?`,
      [sourceUrl]
    );
    if (!result.goToFirstRow()) {
      result.close();
      return null;
    }
    const record = new LegadoCompatibilityStorageRecord(
      result.getString(result.getColumnIndex('sourceUrl')),
      result.getString(result.getColumnIndex('rawJson')),
      result.getString(result.getColumnIndex('rawSha256')),
      result.getLong(result.getColumnIndex('compilerVersion')),
      result.getString(result.getColumnIndex('compileStatus')) as LegadoCompatibilityStatus,
      result.getString(result.getColumnIndex('engineMode')) as LegadoCompatibilityEngineMode,
      result.getString(result.getColumnIndex('capabilityJson')),
      result.getString(result.getColumnIndex('diagnosticsJson')),
      result.getLong(result.getColumnIndex('compiledAt')),
      result.getLong(result.getColumnIndex('updateTime'))
    );
    result.close();
    return record;
  }

  async getAllCompatibilityRecords(): Promise<LegadoCompatibilityStorageRecord[]> {
    const store = this.getStore();
    const result = await store.querySql(
      `SELECT sourceUrl, rawJson, rawSha256, compilerVersion, compileStatus, engineMode,
              capabilityJson, diagnosticsJson, compiledAt, updateTime
       FROM novel_source_compatibility ORDER BY updateTime DESC`
    );
    const records: LegadoCompatibilityStorageRecord[] = [];
    if (result.goToFirstRow()) {
      do {
        records.push(new LegadoCompatibilityStorageRecord(
          result.getString(result.getColumnIndex('sourceUrl')),
          result.getString(result.getColumnIndex('rawJson')),
          result.getString(result.getColumnIndex('rawSha256')),
          result.getLong(result.getColumnIndex('compilerVersion')),
          result.getString(result.getColumnIndex('compileStatus')) as LegadoCompatibilityStatus,
          result.getString(result.getColumnIndex('engineMode')) as LegadoCompatibilityEngineMode,
          result.getString(result.getColumnIndex('capabilityJson')),
          result.getString(result.getColumnIndex('diagnosticsJson')),
          result.getLong(result.getColumnIndex('compiledAt')),
          result.getLong(result.getColumnIndex('updateTime'))
        ));
      } while (result.goToNextRow());
    }
    result.close();
    return records;
  }

  async updateCompatibilityEngineMode(sourceUrl: string, mode: LegadoCompatibilityEngineMode): Promise<void> {
    const store = this.getStore();
    await store.executeSql(
      'UPDATE novel_source_compatibility SET engineMode = ?, updateTime = ? WHERE sourceUrl = ?',
      [mode, Date.now(), sourceUrl]
    );
  }

  async deleteCompatibilityRecord(sourceUrl: string): Promise<void> {
    const store = this.getStore();
    await store.executeSql('DELETE FROM novel_source_compatibility WHERE sourceUrl = ?', [sourceUrl]);
    await store.executeSql('DELETE FROM novel_source_compatibility_verification WHERE sourceUrl = ?', [sourceUrl]);
  }

  async saveCompatibilityVerification(record: LegadoSourceVerificationRecord): Promise<void> {
    const store = this.getStore();
    await store.executeSql(
      `INSERT OR REPLACE INTO novel_source_compatibility_verification
        (sourceUrl, rawSha256, workflows, evidenceDigest, verifiedAt, updateTime)
       VALUES (?, ?, ?, ?, ?, ?)`,
      [
        record.sourceUrl,
        record.rawSha256,
        record.workflows.join('|'),
        record.evidenceDigest,
        record.verifiedAt,
        record.updatedAt
      ]
    );
  }

  async getAllCompatibilityVerifications(): Promise<LegadoSourceVerificationRecord[]> {
    const store = this.getStore();
    const result = await store.querySql(
      `SELECT sourceUrl, rawSha256, workflows, evidenceDigest, verifiedAt, updateTime
       FROM novel_source_compatibility_verification ORDER BY updateTime DESC`
    );
    const records: LegadoSourceVerificationRecord[] = [];
    if (result.goToFirstRow()) {
      do {
        records.push(new LegadoSourceVerificationRecord(
          result.getString(result.getColumnIndex('sourceUrl')),
          result.getString(result.getColumnIndex('rawSha256')),
          this.decodeVerifiedWorkflows(result.getString(result.getColumnIndex('workflows'))),
          result.getString(result.getColumnIndex('evidenceDigest')),
          result.getLong(result.getColumnIndex('verifiedAt')),
          result.getLong(result.getColumnIndex('updateTime'))
        ));
      } while (result.goToNextRow());
    }
    result.close();
    return records;
  }

  async deleteCompatibilityVerification(sourceUrl: string): Promise<void> {
    const store = this.getStore();
    await store.executeSql('DELETE FROM novel_source_compatibility_verification WHERE sourceUrl = ?', [sourceUrl]);
  }

  /**
   * Persist only the last redacted V2 trace summary for a source. The full
   * trace remains in memory for instrumentation and is never written here.
   */
  async saveCompatibilityTraceSummary(summary: LegadoExecutionTraceSummary): Promise<void> {
    const store = this.getStore();
    await store.executeSql(
      `INSERT OR REPLACE INTO novel_source_compatibility_trace
        (sourceUrl, rawSha256, workflow, transport, statusCode, finalUrlObservation,
         errorCode, outputSummary, optionCount, variableCount, requestTargetSha256,
         requestUserAgentSha256, responseContentType, redirectCount, contentDiagnosticStatus,
         contentCharacterCount, contentBridgeStatus, contentBridgeCharacterCount,
         contentBridgeFingerprint, contentFingerprint, occurredAt, updateTime)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)` ,
      [
        summary.sourceUrl,
        summary.rawSha256,
        summary.workflow,
        summary.transport,
        summary.statusCode,
        summary.finalUrlObservation,
        summary.errorCode,
        summary.outputSummary,
        summary.optionCount,
        summary.variableCount,
        summary.networkEvidence.requestTargetSha256,
        summary.networkEvidence.requestUserAgentSha256,
        summary.networkEvidence.responseContentType,
        summary.networkEvidence.redirectCount,
        summary.contentDiagnostics.status,
        summary.contentDiagnostics.characterCount,
        summary.contentDiagnostics.bridgeStatus,
        summary.contentDiagnostics.bridgeCharacterCount,
        summary.contentDiagnostics.bridgeFingerprint,
        summary.contentDiagnostics.contentFingerprint,
        summary.occurredAt,
        summary.updatedAt
      ]
    );
  }

  /**
   * Keep one redacted result per workflow so a normal search → reader path can
   * be audited after process recreation without storing raw trace payloads.
   */
  async saveCompatibilityTraceWorkflowSummary(summary: LegadoExecutionTraceSummary): Promise<void> {
    const store = this.getStore();
    await store.executeSql(
      `INSERT OR REPLACE INTO novel_source_compatibility_trace_workflow
        (sourceUrl, rawSha256, workflow, transport, statusCode, finalUrlObservation,
         errorCode, outputSummary, optionCount, variableCount, requestTargetSha256,
         requestUserAgentSha256, responseContentType, redirectCount, contentDiagnosticStatus,
         contentCharacterCount, contentBridgeStatus, contentBridgeCharacterCount,
         contentBridgeFingerprint, contentFingerprint, occurredAt, updateTime)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)` ,
      [
        summary.sourceUrl,
        summary.rawSha256,
        summary.workflow,
        summary.transport,
        summary.statusCode,
        summary.finalUrlObservation,
        summary.errorCode,
        summary.outputSummary,
        summary.optionCount,
        summary.variableCount,
        summary.networkEvidence.requestTargetSha256,
        summary.networkEvidence.requestUserAgentSha256,
        summary.networkEvidence.responseContentType,
        summary.networkEvidence.redirectCount,
        summary.contentDiagnostics.status,
        summary.contentDiagnostics.characterCount,
        summary.contentDiagnostics.bridgeStatus,
        summary.contentDiagnostics.bridgeCharacterCount,
        summary.contentDiagnostics.bridgeFingerprint,
        summary.contentDiagnostics.contentFingerprint,
        summary.occurredAt,
        summary.updatedAt
      ]
    );
  }

  /**
   * Verifies that a just-written workflow trace is visible through the same
   * durable query contract used by a returning detail page. This deliberately
   * proves RDB visibility, not merely that executeSql resolved successfully.
   */
  async isCompatibilityTraceWorkflowSummaryPersisted(
    summary: LegadoExecutionTraceSummary
  ): Promise<boolean> {
    const store = this.getStore();
    const result = await store.querySql(
      `SELECT occurredAt, updateTime
       FROM novel_source_compatibility_trace_workflow
       WHERE sourceUrl = ? AND rawSha256 = ? AND workflow = ?
       ORDER BY updateTime DESC LIMIT 1`,
      [summary.sourceUrl, summary.rawSha256, summary.workflow]
    );
    try {
      if (!result.goToFirstRow()) {
        return false;
      }
      const occurredAt = result.getLong(result.getColumnIndex('occurredAt'));
      const updatedAt = result.getLong(result.getColumnIndex('updateTime'));
      return occurredAt === summary.occurredAt && updatedAt >= summary.updatedAt;
    } finally {
      result.close();
    }
  }

  async getAllCompatibilityTraceSummaries(): Promise<LegadoExecutionTraceSummary[]> {
    const store = this.getStore();
    const result = await store.querySql(
      `SELECT sourceUrl, rawSha256, workflow, transport, statusCode, finalUrlObservation,
              errorCode, outputSummary, optionCount, variableCount, requestTargetSha256,
              requestUserAgentSha256, responseContentType, redirectCount, contentDiagnosticStatus,
              contentCharacterCount, contentBridgeStatus, contentBridgeCharacterCount,
              contentBridgeFingerprint, contentFingerprint, occurredAt, updateTime
       FROM novel_source_compatibility_trace ORDER BY updateTime DESC`
    );
    const summaries: LegadoExecutionTraceSummary[] = [];
    if (result.goToFirstRow()) {
      do {
        summaries.push(new LegadoExecutionTraceSummary(
          result.getString(result.getColumnIndex('sourceUrl')),
          result.getString(result.getColumnIndex('rawSha256')),
          result.getString(result.getColumnIndex('workflow')) as LegadoWorkflowKind,
          result.getString(result.getColumnIndex('transport')) as LegadoTransportKind,
          result.getLong(result.getColumnIndex('statusCode')),
          result.getString(result.getColumnIndex('finalUrlObservation')) as LegadoFinalUrlObservation,
          result.getString(result.getColumnIndex('errorCode')) as LegadoExecutionErrorCode,
          result.getString(result.getColumnIndex('outputSummary')),
          result.getLong(result.getColumnIndex('optionCount')),
          result.getLong(result.getColumnIndex('variableCount')),
          result.getLong(result.getColumnIndex('occurredAt')),
          result.getLong(result.getColumnIndex('updateTime')),
          new LegadoNetworkTraceEvidence(
            result.getString(result.getColumnIndex('requestTargetSha256')),
            result.getString(result.getColumnIndex('requestUserAgentSha256')),
            result.getString(result.getColumnIndex('responseContentType')),
            result.getLong(result.getColumnIndex('redirectCount'))
          ),
          new LegadoContentTraceDiagnostics(
            result.getString(result.getColumnIndex('contentDiagnosticStatus')),
            result.getLong(result.getColumnIndex('contentCharacterCount')),
            result.getString(result.getColumnIndex('contentBridgeStatus')),
            result.getLong(result.getColumnIndex('contentBridgeCharacterCount')),
            result.getString(result.getColumnIndex('contentBridgeFingerprint')),
            result.getString(result.getColumnIndex('contentFingerprint'))
          )
        ));
      } while (result.goToNextRow());
    }
    result.close();
    return summaries;
  }

  /** Returns the latest redacted trace for each workflow of every source. */
  async getAllCompatibilityTraceWorkflowSummaries(): Promise<LegadoExecutionTraceSummary[]> {
    const store = this.getStore();
    const result = await store.querySql(
      `SELECT sourceUrl, rawSha256, workflow, transport, statusCode, finalUrlObservation,
              errorCode, outputSummary, optionCount, variableCount, requestTargetSha256,
              requestUserAgentSha256, responseContentType, redirectCount, contentDiagnosticStatus,
              contentCharacterCount, contentBridgeStatus, contentBridgeCharacterCount,
              contentBridgeFingerprint, contentFingerprint, occurredAt, updateTime
       FROM novel_source_compatibility_trace_workflow ORDER BY updateTime DESC`
    );
    const summaries: LegadoExecutionTraceSummary[] = [];
    if (result.goToFirstRow()) {
      do {
        summaries.push(new LegadoExecutionTraceSummary(
          result.getString(result.getColumnIndex('sourceUrl')),
          result.getString(result.getColumnIndex('rawSha256')),
          result.getString(result.getColumnIndex('workflow')) as LegadoWorkflowKind,
          result.getString(result.getColumnIndex('transport')) as LegadoTransportKind,
          result.getLong(result.getColumnIndex('statusCode')),
          result.getString(result.getColumnIndex('finalUrlObservation')) as LegadoFinalUrlObservation,
          result.getString(result.getColumnIndex('errorCode')) as LegadoExecutionErrorCode,
          result.getString(result.getColumnIndex('outputSummary')),
          result.getLong(result.getColumnIndex('optionCount')),
          result.getLong(result.getColumnIndex('variableCount')),
          result.getLong(result.getColumnIndex('occurredAt')),
          result.getLong(result.getColumnIndex('updateTime')),
          new LegadoNetworkTraceEvidence(
            result.getString(result.getColumnIndex('requestTargetSha256')),
            result.getString(result.getColumnIndex('requestUserAgentSha256')),
            result.getString(result.getColumnIndex('responseContentType')),
            result.getLong(result.getColumnIndex('redirectCount'))
          ),
          new LegadoContentTraceDiagnostics(
            result.getString(result.getColumnIndex('contentDiagnosticStatus')),
            result.getLong(result.getColumnIndex('contentCharacterCount')),
            result.getString(result.getColumnIndex('contentBridgeStatus')),
            result.getLong(result.getColumnIndex('contentBridgeCharacterCount')),
            result.getString(result.getColumnIndex('contentBridgeFingerprint')),
            result.getString(result.getColumnIndex('contentFingerprint'))
          )
        ));
      } while (result.goToNextRow());
    }
    result.close();
    return summaries;
  }

  async deleteCompatibilityTraceSummary(sourceUrl: string): Promise<void> {
    const store = this.getStore();
    await store.executeSql('DELETE FROM novel_source_compatibility_trace WHERE sourceUrl = ?', [sourceUrl]);
  }

  async deleteCompatibilityTraceWorkflowSummaries(sourceUrl: string): Promise<void> {
    const store = this.getStore();
    await store.executeSql('DELETE FROM novel_source_compatibility_trace_workflow WHERE sourceUrl = ?', [sourceUrl]);
  }

  private decodeVerifiedWorkflows(value: string): LegadoWorkflowKind[] {
    const values = value.split('|');
    const workflows: LegadoWorkflowKind[] = [];
    for (let i = 0; i < values.length; i++) {
      const workflow = values[i] as LegadoWorkflowKind;
      if (this.isKnownWorkflow(workflow) && !workflows.includes(workflow)) {
        workflows.push(workflow);
      }
    }
    return workflows;
  }

  private isKnownWorkflow(value: LegadoWorkflowKind): boolean {
    return value === LegadoWorkflowKind.SEARCH ||
      value === LegadoWorkflowKind.EXPLORE ||
      value === LegadoWorkflowKind.BOOK_INFO ||
      value === LegadoWorkflowKind.TOC ||
      value === LegadoWorkflowKind.CONTENT ||
      value === LegadoWorkflowKind.FILE ||
      value === LegadoWorkflowKind.REVIEW;
  }

  /**
   * 删除书源
   */
  async deleteSource(bookSourceUrl: string): Promise<void> {
    const store = this.getStore();
    await store.executeSql('DELETE FROM novel_source WHERE bookSourceUrl = ?', [bookSourceUrl]);
    await store.executeSql('DELETE FROM novel_source_compatibility WHERE sourceUrl = ?', [bookSourceUrl]);
    await store.executeSql('DELETE FROM novel_source_compatibility_verification WHERE sourceUrl = ?', [bookSourceUrl]);
    await store.executeSql('DELETE FROM novel_source_compatibility_trace WHERE sourceUrl = ?', [bookSourceUrl]);
    await store.executeSql('DELETE FROM novel_source_compatibility_trace_workflow WHERE sourceUrl = ?', [bookSourceUrl]);
  }

  // ==================== 书籍操作 ====================

  /**
   * 保存书籍
   */
  async saveBook(book: NovelBook): Promise<string> {
    const store = this.getStore();
    const now = Date.now();
    const id = book.id || this.generateId();

    // 【NSFW作用域】从书源继承NSFW状态（受作用域开关控制）
    let isNSFWVal = book.isNSFW ? 1 : 0;
    if (isNSFWVal === 0 && book.isNSFW === undefined && book.sourceId) {
      try {
        const sourceNsfwRs = await store.querySql(
          'SELECT isNSFW FROM novel_source WHERE bookSourceUrl = ? OR id = ?',
          [book.sourceId, book.sourceId]
        );
        if (sourceNsfwRs.goToFirstRow()) {
          const sourceIsNSFW = sourceNsfwRs.getLong(0);
          if (sourceIsNSFW === 1) {
            // 检查书源NSFW作用域开关
            let scopeEnabled = true;
            try {
              const cfmModule = await import('../Managers/ContentFilterManager');
              scopeEnabled = cfmModule.ContentFilterManager.getInstance().isNsfwScopeBookSourceEnabled();
            } catch (_e) {
              // ContentFilterManager未初始化时默认启用
            }
            if (scopeEnabled) {
              isNSFWVal = 1;
              logger.debug(TAG, `【NSFW作用域】小说从书源继承NSFW标记: ${book.name}`);
            }
          }
          sourceNsfwRs.close();
        } else {
          sourceNsfwRs.close();
        }
      } catch (e) {
        logger.warn(TAG, `查询书源NSFW状态失败: ${e}`);
      }
    }

    const sql = `INSERT OR REPLACE INTO novel_book 
      (id, sourceId, sourceName, bookUrl, name, author, kind, intro, coverUrl, 
       coverLocalPath, tocUrl, latestChapterTitle, wordCount, chapterCount,
       readStatus, lastReadChapterId, lastReadChapterIndex, lastReadPosition,
       lastReadTime, isFavorite, isPrivate, isNSFW, createTime, updateTime)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`;

    await store.executeSql(sql, [
      id, book.sourceId, book.sourceName, book.bookUrl, book.name,
      book.author || '', book.kind || '', book.intro || '', book.coverUrl || '',
      book.coverLocalPath || '', book.tocUrl || '', book.latestChapterTitle || '',
      book.wordCount || '', book.chapterCount || 0, book.readStatus || 'unread',
      book.lastReadChapterId ?? '', book.lastReadChapterIndex ?? -1,
      book.lastReadPosition ?? 0, book.lastReadTime ?? 0,
      book.isFavorite ? 1 : 0,
      book.isPrivate ? 1 : 0,  // isPrivate默认为0（普通内容）
      isNSFWVal,                // isNSFW：支持从书源自动继承
      book.createTime || now, now
    ]);

    return id;
  }

  /**
   * 获取收藏的书籍
   */
  async getFavoriteBooks(): Promise<NovelBook[]> {
    const store = this.getStore();
    const rs = await store.querySql(
      'SELECT * FROM novel_book WHERE isFavorite = 1 ORDER BY lastReadTime DESC'
    );
    return this.parseBookResults(rs);
  }

  /**
   * 获取最近阅读的书籍
   */
  async getRecentBooks(limit: number = 20): Promise<NovelBook[]> {
    const store = this.getStore();
    const rs = await store.querySql(
      `SELECT * FROM novel_book WHERE lastReadTime > 0 ORDER BY lastReadTime DESC LIMIT ?`,
      [limit]
    );
    return this.parseBookResults(rs);
  }

  /**
   * 搜索书库中的小说
   */
  async searchBooks(keyword: string): Promise<NovelBook[]> {
    const store = this.getStore();
    const searchPattern = `%${keyword}%`;
    const rs = await store.querySql(
      `SELECT * FROM novel_book WHERE isFavorite = 1 AND (name LIKE ? OR author LIKE ?) ORDER BY lastReadTime DESC`,
      [searchPattern, searchPattern]
    );
    return this.parseBookResults(rs);
  }

  /**
   * [新增] 获取隐私小说列表
   * @returns Promise<NovelBook[]> 隐私小说列表
   */
  async getPrivateBooks(): Promise<NovelBook[]> {
    const store = this.getStore();
    const rs = await store.querySql(
      'SELECT * FROM novel_book WHERE isPrivate = 1 ORDER BY lastReadTime DESC'
    );
    return this.parseBookResults(rs);
  }

  /**
   * [新增] 获取非隐私小说列表
   * @returns Promise<NovelBook[]> 非隐私小说列表
   */
  async getNonPrivateBooks(): Promise<NovelBook[]> {
    const store = this.getStore();
    const rs = await store.querySql(
      'SELECT * FROM novel_book WHERE (isPrivate = 0 OR isPrivate IS NULL) ORDER BY lastReadTime DESC'
    );
    return this.parseBookResults(rs);
  }

  /**
   * [新增] 获取SFW（非NSFW）小说列表
   * @returns Promise<NovelBook[]> SFW小说列表
   */
  async getSFWBooks(): Promise<NovelBook[]> {
    const store = this.getStore();
    const rs = await store.querySql(
      'SELECT * FROM novel_book WHERE (isNSFW = 0 OR isNSFW IS NULL) ORDER BY lastReadTime DESC'
    );
    return this.parseBookResults(rs);
  }

  /**
   * [新增] 获取NSFW小说列表
   * @returns Promise<NovelBook[]> NSFW小说列表
   */
  async getNSFWBooks(): Promise<NovelBook[]> {
    const store = this.getStore();
    const rs = await store.querySql(
      'SELECT * FROM novel_book WHERE isNSFW = 1 ORDER BY lastReadTime DESC'
    );
    return this.parseBookResults(rs);
  }

  /**
   * 解析书籍查询结果
   */
  private parseBookResults(rs: relationalStore.ResultSet): NovelBook[] {
    const books: NovelBook[] = [];
    if (rs.goToFirstRow()) {
      do {
        books.push({
          id: rs.getString(rs.getColumnIndex('id')),
          sourceId: rs.getString(rs.getColumnIndex('sourceId')),
          sourceName: rs.getString(rs.getColumnIndex('sourceName')),
          bookUrl: rs.getString(rs.getColumnIndex('bookUrl')),
          name: rs.getString(rs.getColumnIndex('name')),
          author: rs.getString(rs.getColumnIndex('author')),
          kind: rs.getString(rs.getColumnIndex('kind')),
          intro: rs.getString(rs.getColumnIndex('intro')),
          coverUrl: rs.getString(rs.getColumnIndex('coverUrl')),
          coverLocalPath: rs.getString(rs.getColumnIndex('coverLocalPath')),
          tocUrl: rs.getString(rs.getColumnIndex('tocUrl')),
          latestChapterTitle: rs.getString(rs.getColumnIndex('latestChapterTitle')),
          wordCount: rs.getString(rs.getColumnIndex('wordCount')),
          chapterCount: rs.getLong(rs.getColumnIndex('chapterCount')),
          readStatus: rs.getString(rs.getColumnIndex('readStatus')) as NovelReadStatus,
          lastReadChapterId: rs.getString(rs.getColumnIndex('lastReadChapterId')),
          lastReadChapterIndex: rs.getLong(rs.getColumnIndex('lastReadChapterIndex')),
          lastReadPosition: rs.getLong(rs.getColumnIndex('lastReadPosition')),
          lastReadTime: rs.getLong(rs.getColumnIndex('lastReadTime')),
          totalReadingTime: rs.getLong(rs.getColumnIndex('totalReadingTime')),
          isFavorite: rs.getLong(rs.getColumnIndex('isFavorite')) === 1,
          isPrivate: rs.getLong(rs.getColumnIndex('isPrivate')) === 1,  // 读取隐私状态
          isNSFW: rs.getLong(rs.getColumnIndex('isNSFW')) === 1,        // 读取NSFW状态
          createTime: rs.getLong(rs.getColumnIndex('createTime')),
          updateDbTime: rs.getLong(rs.getColumnIndex('updateTime'))
        });
      } while (rs.goToNextRow());
    }
    rs.close();
    return books;
  }

  // ==================== 阅读进度 ====================

  /**
   * 保存阅读进度
   */
  async saveReadProgress(progress: NovelReadProgress): Promise<void> {
    const store = this.getStore();
    const now = Date.now();
    const id = this.generateId();

    // 使用 readTime 保护的更新/插入策略，避免乱序写入覆盖新进度
    const safeReadTime = progress.readTime > 0 ? progress.readTime : now;
    
    const updateProgressSql = `UPDATE novel_read_progress SET
      chapterId = ?, chapterIndex = ?, position = ?, progress = ?, readTime = ?, updateTime = ?
      WHERE bookId = ? AND readTime <= ?`;
    await store.executeSql(updateProgressSql, [
      progress.chapterId, progress.chapterIndex, progress.position, progress.progress, safeReadTime, now,
      progress.bookId, safeReadTime
    ]);

    const insertProgressSql = `INSERT OR IGNORE INTO novel_read_progress
      (id, bookId, chapterId, chapterIndex, position, progress, readTime, createTime, updateTime)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`;
    await store.executeSql(insertProgressSql, [
      id, progress.bookId, progress.chapterId, progress.chapterIndex,
      progress.position, progress.progress, safeReadTime, now, now
    ]);

    // 同时更新书籍表的阅读进度
    await store.executeSql(
      `UPDATE novel_book SET lastReadChapterId = ?, lastReadChapterIndex = ?, 
       lastReadPosition = ?, lastReadTime = ?, readStatus = 'reading', updateTime = ?
       WHERE id = ? AND (lastReadTime IS NULL OR lastReadTime <= ?)`,
      [progress.chapterId, progress.chapterIndex, progress.position, safeReadTime, now, progress.bookId, safeReadTime]
    );
    await store.executeSql(
      `UPDATE novel_book SET lastReadChapterId = ?, lastReadChapterIndex = ?,
       lastReadPosition = ?, lastReadTime = ?, readStatus = 'reading', updateTime = ?
       WHERE sourceId = (SELECT sourceId FROM novel_book WHERE id = ?)
         AND bookUrl = (SELECT bookUrl FROM novel_book WHERE id = ?)
         AND (lastReadTime IS NULL OR lastReadTime <= ?)`,
      [progress.chapterId, progress.chapterIndex, progress.position, safeReadTime, now, progress.bookId, progress.bookId, safeReadTime]
    );
  }

  /**
   * 获取阅读进度
   */
  async getReadProgress(bookId: string): Promise<NovelReadProgress | null> {
    const store = this.getStore();
    const rs = await store.querySql(
      'SELECT * FROM novel_read_progress WHERE bookId = ?', [bookId]
    );

    if (rs.goToFirstRow()) {
      const progress: NovelReadProgress = {
        bookId: rs.getString(rs.getColumnIndex('bookId')),
        chapterId: rs.getString(rs.getColumnIndex('chapterId')),
        chapterIndex: rs.getLong(rs.getColumnIndex('chapterIndex')),
        position: rs.getLong(rs.getColumnIndex('position')),
        progress: rs.getDouble(rs.getColumnIndex('progress')),
        readTime: rs.getLong(rs.getColumnIndex('readTime'))
      };
      rs.close();
      return progress;
    }
    rs.close();
    return null;
  }

  // ==================== 阅读设置 ====================

  /**
   * 获取阅读设置
   */
  async getReaderSettings(userId: string = 'default'): Promise<NovelReaderSettings> {
    const store = this.getStore();
    const rs = await store.querySql(
      'SELECT * FROM novel_reader_settings WHERE userId = ?', [userId]
    );

    if (rs.goToFirstRow()) {
      const settings: NovelReaderSettings = {
        fontSize: rs.getLong(rs.getColumnIndex('fontSize')),
        lineHeight: rs.getDouble(rs.getColumnIndex('lineHeight')),
        letterSpacing: rs.getLong(rs.getColumnIndex('letterSpacing')),
        paragraphSpacing: rs.getLong(rs.getColumnIndex('paragraphSpacing')),
        fontFamily: rs.getString(rs.getColumnIndex('fontFamily')),
        textColor: rs.getString(rs.getColumnIndex('textColor')),
        backgroundColor: rs.getString(rs.getColumnIndex('backgroundColor')),
        brightness: rs.getDouble(rs.getColumnIndex('brightness')),
        keepScreenOn: rs.getLong(rs.getColumnIndex('keepScreenOn')) === 1,
        volumeKeyTurn: rs.getLong(rs.getColumnIndex('volumeKeyTurn')) === 1,
        clickTurn: rs.getLong(rs.getColumnIndex('clickTurn')) === 1,
        autoScroll: rs.getLong(rs.getColumnIndex('autoScroll')) === 1,
        autoScrollSpeed: rs.getLong(rs.getColumnIndex('autoScrollSpeed'))
      };
      rs.close();
      return settings;
    }
    rs.close();
    return DEFAULT_NOVEL_READER_SETTINGS;
  }

  /**
   * 保存阅读设置
   */
  async saveReaderSettings(settings: NovelReaderSettings, userId: string = 'default'): Promise<void> {
    const store = this.getStore();
    const now = Date.now();
    const id = this.generateId();

    await store.executeSql('DELETE FROM novel_reader_settings WHERE userId = ?', [userId]);

    const sql = `INSERT INTO novel_reader_settings 
      (id, userId, fontSize, lineHeight, letterSpacing, paragraphSpacing, fontFamily,
       textColor, backgroundColor, brightness, keepScreenOn, volumeKeyTurn, clickTurn,
       autoScroll, autoScrollSpeed, createTime, updateTime)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`;

    await store.executeSql(sql, [
      id, userId, settings.fontSize, settings.lineHeight, settings.letterSpacing,
      settings.paragraphSpacing, settings.fontFamily, settings.textColor,
      settings.backgroundColor, settings.brightness,
      settings.keepScreenOn ? 1 : 0, settings.volumeKeyTurn ? 1 : 0,
      settings.clickTurn ? 1 : 0, settings.autoScroll ? 1 : 0,
      settings.autoScrollSpeed, now, now
    ]);
  }

  // ==================== 书架管理 ====================

  /**
   * 获取所有书架分组
   */
  async getBookGroups(): Promise<string[]> {
    const store = this.getStore();
    const rs = await store.querySql(
      'SELECT DISTINCT groupName FROM novel_book WHERE isFavorite = 1 AND groupName != "" ORDER BY groupName'
    );
    const groups: string[] = [];
    if (rs.goToFirstRow()) {
      do {
        groups.push(rs.getString(0));
      } while (rs.goToNextRow());
    }
    rs.close();
    return groups;
  }

  /**
   * 获取指定分组的书籍
   */
  async getBooksByGroup(groupName: string): Promise<NovelBook[]> {
    const store = this.getStore();
    const rs = await store.querySql(
      'SELECT * FROM novel_book WHERE isFavorite = 1 AND groupName = ? ORDER BY sortOrder ASC, lastReadTime DESC',
      [groupName]
    );
    return this.parseBookResults(rs);
  }

  /**
   * 设置书籍分组
   */
  async setBookGroup(bookId: string, groupName: string): Promise<void> {
    const store = this.getStore();
    await store.executeSql(
      'UPDATE novel_book SET groupName = ?, updateTime = ? WHERE id = ?',
      [groupName, Date.now(), bookId]
    );
  }

  /**
   * 批量设置书籍分组
   */
  async setBookGroupBatch(bookIds: string[], groupName: string): Promise<void> {
    const store = this.getStore();
    const now = Date.now();
    for (const bookId of bookIds) {
      await store.executeSql(
        'UPDATE novel_book SET groupName = ?, updateTime = ? WHERE id = ?',
        [groupName, now, bookId]
      );
    }
  }

  /**
   * 设置书籍排序顺序
   */
  async setBookSortOrder(bookId: string, sortOrder: number): Promise<void> {
    const store = this.getStore();
    await store.executeSql(
      'UPDATE novel_book SET sortOrder = ?, updateTime = ? WHERE id = ?',
      [sortOrder, Date.now(), bookId]
    );
  }

  /**
   * 获取收藏书籍（支持排序）
   */
  async getFavoriteBooksSorted(sortType: string = 'lastRead', ascending: boolean = false): Promise<NovelBook[]> {
    const store = this.getStore();
    let orderBy = 'lastReadTime DESC';
    
    switch (sortType) {
      case 'lastRead':
        orderBy = ascending ? 'lastReadTime ASC' : 'lastReadTime DESC';
        break;
      case 'name':
        orderBy = ascending ? 'name ASC' : 'name DESC';
        break;
      case 'author':
        orderBy = ascending ? 'author ASC' : 'author DESC';
        break;
      case 'addTime':
        orderBy = ascending ? 'createTime ASC' : 'createTime DESC';
        break;
      case 'updateTime':
        orderBy = ascending ? 'updateTime ASC' : 'updateTime DESC';
        break;
      case 'custom':
        orderBy = ascending ? 'sortOrder ASC' : 'sortOrder DESC';
        break;
    }
    
    const rs = await store.querySql(
      `SELECT * FROM novel_book WHERE isFavorite = 1 ORDER BY ${orderBy}`
    );
    return this.parseBookResults(rs);
  }

  /**
   * 删除书籍
   */
  async deleteBook(bookId: string): Promise<void> {
    const store = this.getStore();
    const book = await this.getBook(bookId);
    // 删除相关章节缓存
    await store.executeSql(
      'DELETE FROM novel_content_cache WHERE chapterId IN (SELECT id FROM novel_chapter WHERE bookId = ?)',
      [bookId]
    );
    // 删除章节
    await store.executeSql('DELETE FROM novel_chapter WHERE bookId = ?', [bookId]);
    // 删除阅读进度
    await store.executeSql('DELETE FROM novel_read_progress WHERE bookId = ?', [bookId]);
    // 删除书籍
    await store.executeSql('DELETE FROM novel_book WHERE id = ?', [bookId]);
    // 删除统一标注，避免书籍删除后灵感页仍保留该书记录。
    await getUnifiedAnnotationManager().deleteContentAnnotations(UnifiedContentType.NOVEL, bookId);
    if (book && this.filesDir) {
      const coverCandidates = [book.coverLocalPath || '', book.coverUrl || ''];
      for (const coverPath of coverCandidates) {
        if (LibraryCoverManager.deleteManagedCoverIfExists(coverPath, this.filesDir)) {
          logger.debug(TAG, `删除小说封面文件: ${coverPath}`);
        }
      }
    }
    logger.info(TAG, `删除书籍: ${bookId}`);
  }

  /**
   * 批量删除书籍
   */
  async deleteBooksBatch(bookIds: string[]): Promise<void> {
    for (const bookId of bookIds) {
      await this.deleteBook(bookId);
    }
  }

  /**
   * 取消收藏
   */
  async unfavoriteBook(bookId: string): Promise<void> {
    const store = this.getStore();
    await store.executeSql(
      'UPDATE novel_book SET isFavorite = 0, updateTime = ? WHERE id = ?',
      [Date.now(), bookId]
    );
  }

  /**
   * 获取书籍详情
   */
  async getBook(bookId: string): Promise<NovelBook | null> {
    const store = this.getStore();
    const rs = await store.querySql('SELECT * FROM novel_book WHERE id = ?', [bookId]);
    const books = this.parseBookResults(rs);
    return books.length > 0 ? books[0] : null;
  }

  /**
   * 通过URL获取书籍
   */
  async getBookByUrl(sourceId: string, bookUrl: string): Promise<NovelBook | null> {
    const store = this.getStore();
    const rs = await store.querySql(
      'SELECT * FROM novel_book WHERE sourceId = ? AND bookUrl = ? ORDER BY lastReadTime DESC, updateTime DESC',
      [sourceId, bookUrl]
    );
    const books = this.parseBookResults(rs);
    return books.length > 0 ? books[0] : null;
  }

  /**
   * 根据书籍ID与章节索引获取章节信息
   */
  async getChapterByIndex(bookId: string, chapterIndex: number): Promise<NovelChapter | null> {
    const store = this.getStore();
    if (!bookId || bookId.trim().length <= 0) {
      return null;
    }
    const safeIndex = Math.max(0, Math.floor(chapterIndex));
    const rs = await store.querySql(
      'SELECT * FROM novel_chapter WHERE bookId = ? AND chapterIndex = ? LIMIT 1',
      [bookId, safeIndex]
    );
    if (!rs.goToFirstRow()) {
      rs.close();
      return null;
    }
    const chapter: NovelChapter = {
      id: rs.getString(rs.getColumnIndex('id')),
      bookId: rs.getString(rs.getColumnIndex('bookId')),
      url: rs.getString(rs.getColumnIndex('url')),
      title: rs.getString(rs.getColumnIndex('title')),
      index: rs.getLong(rs.getColumnIndex('chapterIndex')),
      isVolume: rs.getLong(rs.getColumnIndex('isVolume')) === 1,
      isVip: rs.getLong(rs.getColumnIndex('isVip')) === 1,
      isPay: rs.getLong(rs.getColumnIndex('isPay')) === 1,
      isDownloaded: rs.getLong(rs.getColumnIndex('isDownloaded')) === 1,
      contentPath: rs.getString(rs.getColumnIndex('contentPath')),
      wordCount: rs.getLong(rs.getColumnIndex('wordCount')),
      updateTime: rs.getLong(rs.getColumnIndex('updateTime')),
      createTime: rs.getLong(rs.getColumnIndex('createTime'))
    };
    rs.close();
    return chapter;
  }

  /**
   * 更新书籍阅读时长
   * @param bookId 书籍ID
   * @param additionalTime 新增阅读时长（秒）
   */
  async updateReadingTime(bookId: string, additionalTime: number): Promise<void> {
    const store = this.getStore();
    const now = Date.now();
    await store.executeSql(
      'UPDATE novel_book SET totalReadingTime = totalReadingTime + ?, updateTime = ? WHERE id = ?',
      [additionalTime, now, bookId]
    );
    await store.executeSql(
      `UPDATE novel_book SET totalReadingTime = totalReadingTime + ?, updateTime = ?
       WHERE sourceId = (SELECT sourceId FROM novel_book WHERE id = ?)
         AND bookUrl = (SELECT bookUrl FROM novel_book WHERE id = ?)`,
      [additionalTime, now, bookId, bookId]
    );
    logger.debug(TAG, `更新书籍阅读时长: ${bookId}, 新增 ${additionalTime} 秒`);
  }

  /**
   * 获取所有有阅读记录的书籍（用于阅读统计）
   */
  async getBooksWithReadingTime(): Promise<NovelBook[]> {
    const store = this.getStore();
    const rs = await store.querySql(
      'SELECT * FROM novel_book WHERE totalReadingTime > 0 OR lastReadTime > 0 ORDER BY lastReadTime DESC'
    );
    return this.parseBookResults(rs);
  }

  // ==================== 工具方法 ====================

  private generateId(): string {
    return `${Date.now()}_${Math.random().toString(36).substring(2, 9)}`;
  }
}

export function getNovelDataManager(): NovelDataManager {
  return NovelDataManager.getInstance();
}

export { NovelBook };
