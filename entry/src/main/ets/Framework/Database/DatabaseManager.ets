// 文件路径: src/main/ets/Framework/Database/DatabaseManager.ets
/**
 * 数据库管理器
 * 基于HarmonyOS relationalStore实现
 * 符合ArkTS规范的类型安全设计
 */

import { relationalStore } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { logger } from '../../Utils/Logger';
import { 
  CREATE_TABLE_SQL, 
  CREATE_INDEX_SQL, 
  MIGRATION_SCRIPTS 
} from './DatabaseSchema';

// 导入新的类型定义
import { 
  DatabaseValue, 
  DatabaseRecord, 
  GenericQueryRecord,
  ComicSourceDatabaseRecord,
  ComicInfoDatabaseRecord,
  ChapterInfoDatabaseRecord,
  PageInfoDatabaseRecord,
  FavoriteInfoDatabaseRecord,
  ReadHistoryDatabaseRecord,
  DownloadTaskDatabaseRecord,
  UserSettingsDatabaseRecord,
  PluginDatabaseRecord,
  OnlineComicInfoDatabaseRecord,
  OnlineChapterInfoDatabaseRecord,
  OnlinePageInfoDatabaseRecord,
  convertComicSourceToDbFormat,
  convertComicInfoToDbFormat,
  convertChapterInfoToDbFormat,
  convertPageInfoToDbFormat,
  convertFavoriteInfoToDbFormat,
  convertReadHistoryToDbFormat,
  convertDownloadTaskToDbFormat,
  convertUserSettingsToDbFormat,
  convertPluginToDbFormat,
  convertOnlineComicInfoToDbFormat,
  convertOnlineChapterInfoToDbFormat,
  convertOnlinePageInfoToDbFormat,
  UpdateRecordData,
  ComicSourceUpdateData,
  DatabaseRecordType,
  DatabaseRecordFactory,
  AggregationQueryResult,
  CountQueryResult,
  SumQueryResult,
  AvgQueryResult,
  MinMaxQueryResult,
  CountResult,
  SumResult,
  AvgResult,
  MinMaxResult
} from './DatabaseTypes';

const TAG = 'DatabaseManager';

// 数据库配置接口
interface DatabaseConfigType {
  DATABASE_NAME: string;
  DATABASE_VERSION: number;
  ENCRYPT: boolean;
}

// 数据库配置常量
const DATABASE_CONFIG: DatabaseConfigType = {
  DATABASE_NAME: 'manxia_comic.db',
  DATABASE_VERSION: 10,
  ENCRYPT: false
};

/**
 * 数据库管理器类
 */
export class DatabaseManager {
  private static instance: DatabaseManager | null = null;
  private store: relationalStore.RdbStore | null = null;
  private isInitialized: boolean = false;

  private constructor() {}

  /**
   * 获取单例实例
   */
  public static getInstance(): DatabaseManager {
    if (!DatabaseManager.instance) {
      DatabaseManager.instance = new DatabaseManager();
    }
    return DatabaseManager.instance;
  }

  /**
   * 初始化数据库
   */
  public async initialize(context: common.UIAbilityContext): Promise<void> {
    if (this.isInitialized) {
      return;
    }

    try {
      logger.info(TAG, '开始初始化数据库');
      
      const config: relationalStore.StoreConfig = {
        name: DATABASE_CONFIG.DATABASE_NAME,
        securityLevel: relationalStore.SecurityLevel.S1,
        encrypt: DATABASE_CONFIG.ENCRYPT
      };

      this.store = await relationalStore.getRdbStore(context, config);
      
      // 创建表
      await this.createTables();
      
      // 创建索引
      await this.createIndexes();
      
      // 执行数据库迁移
      await this.runMigrations();
      
      this.isInitialized = true;
      logger.info(TAG, '数据库初始化完成');
    } catch (error) {
      logger.error(TAG, '数据库初始化失败: ' + String(error));
      throw new Error('数据库初始化失败: ' + String(error));
    }
  }

  /**
   * 获取数据库存储实例
   */
  private getStore(): relationalStore.RdbStore {
    if (!this.store) {
      throw new Error('数据库未初始化');
    }
    return this.store;
  }

  /**
   * 创建数据库表
   */
  private async createTables(): Promise<void> {
    const store = this.getStore();
    
    // 按顺序创建表，避免外键依赖问题
    const tableNames = [
      'COMIC_SOURCE',
      'TEMP_MANGA_INFO',
      'COMIC_INFO', 
      'CHAPTER',
      'PAGE',
      'FAVORITE',
      'READ_HISTORY',
      'DOWNLOAD_TASK',
      'CACHE_INFO',
      'USER_SETTINGS',
      'PLUGIN',
      'WEBVIEW_SOURCE_CONFIG',
      'WEBVIEW_IMAGE_METADATA',
      'WEBVIEW_REQUEST_STATS',
      'EBOOK_INFO',
      'EBOOK_CHAPTER',
      'EBOOK_READING_PROGRESS',
      'EBOOK_READING_SETTINGS',
      'ONLINE_COMIC_INFO',
      'ONLINE_CHAPTER',
      'ONLINE_PAGE'
      , 'ONLINE_READ_HISTORY'
    ];
    
    const tableCreationOrder = [
      CREATE_TABLE_SQL.COMIC_SOURCE,
      CREATE_TABLE_SQL.TEMP_MANGA_INFO,
      CREATE_TABLE_SQL.COMIC_INFO,
      CREATE_TABLE_SQL.CHAPTER,
      CREATE_TABLE_SQL.CHAPTER_UNIQUE_INDEX,
      CREATE_TABLE_SQL.PAGE,
      CREATE_TABLE_SQL.PAGE_UNIQUE_INDEX,
      CREATE_TABLE_SQL.FAVORITE,
      CREATE_TABLE_SQL.READ_HISTORY,
      CREATE_TABLE_SQL.DOWNLOAD_TASK,
      CREATE_TABLE_SQL.CACHE_INFO,
      CREATE_TABLE_SQL.USER_SETTINGS,
      CREATE_TABLE_SQL.PLUGIN,
      CREATE_TABLE_SQL.WEBVIEW_SOURCE_CONFIG,
      CREATE_TABLE_SQL.WEBVIEW_IMAGE_METADATA,
      CREATE_TABLE_SQL.WEBVIEW_REQUEST_STATS,
      CREATE_TABLE_SQL.EBOOK_INFO,
      CREATE_TABLE_SQL.EBOOK_CHAPTER,
      CREATE_TABLE_SQL.EBOOK_READING_PROGRESS,
      CREATE_TABLE_SQL.EBOOK_READING_SETTINGS,
      CREATE_TABLE_SQL.ONLINE_COMIC_INFO as string,
      CREATE_TABLE_SQL.ONLINE_COMIC_UNIQUE_INDEX as string,
      CREATE_TABLE_SQL.ONLINE_CHAPTER as string,
      CREATE_TABLE_SQL.ONLINE_CHAPTER_UNIQUE_INDEX as string,
      CREATE_TABLE_SQL.ONLINE_PAGE as string
      , CREATE_TABLE_SQL.ONLINE_READ_HISTORY as string
    ];
    
    for (let i = 0; i < tableCreationOrder.length; i++) {
      const sql = tableCreationOrder[i];
      const tableName = tableNames[i];
      try {
        logger.debug(TAG, `开始创建表/索引: ${tableName}`);
        logger.debug(TAG, `SQL语句: ${sql}`);
        await store.executeSql(sql);
        logger.debug(TAG, `创建表/索引成功: ${tableName}`);
      } catch (error) {
        logger.error(TAG, `创建表/索引失败: ${tableName}`);
        logger.error(TAG, `失败的SQL语句: ${sql}`);
        logger.error(TAG, `错误详情: ${JSON.stringify(error)}`);
        logger.error(TAG, `错误类型: ${typeof error}`);
        if (error instanceof Error) {
          logger.error(TAG, `错误消息: ${error.message}`);
          logger.error(TAG, `错误堆栈: ${error.stack}`);
        }
        throw error as Error;
      }
    }
    await this.ensureComicSourceCookiesColumn();
    await this.ensureComicSourcePkgColumn();
    await this.ensureComicSourcePreloadColumns();
    await this.ensureComicSourceTabsConfigColumn();
    await this.ensureEBookProgressColumns();
  }

  /**
   * 创建索引
   */
  private async createIndexes(): Promise<void> {
    const store = this.getStore();
    
    for (let i = 0; i < CREATE_INDEX_SQL.length; i++) {
      const sql = CREATE_INDEX_SQL[i];
      try {
        await store.executeSql(sql);
        logger.debug(TAG, `创建索引成功: ${sql}`);
      } catch (error) {
        logger.error(TAG, `创建索引失败: ${String(error)}`);
        // 索引创建失败不应该阻止数据库初始化
      }
    }
  }

  /**
   * 执行数据库迁移
   */
  private async runMigrations(): Promise<void> {
    // 获取当前数据库版本
    const currentVersion = await this.getDatabaseVersion();
    
    if (currentVersion < DATABASE_CONFIG.DATABASE_VERSION) {
      logger.info(TAG, `开始数据库迁移，从版本 ${currentVersion} 到 ${DATABASE_CONFIG.DATABASE_VERSION}`);
      
      for (let version = currentVersion + 1; version <= DATABASE_CONFIG.DATABASE_VERSION; version++) {
        await this.runMigrationForVersion(version);
      }
      
      await this.updateDatabaseVersion(DATABASE_CONFIG.DATABASE_VERSION);
      logger.info(TAG, '数据库迁移完成');
    }
  }

  private async ensureComicSourceCookiesColumn(): Promise<void> {
    try {
      const store = this.getStore();
      const rs = await store.querySql("PRAGMA table_info('comic_source')");
      let hasCookies: boolean = false;
      if (rs.goToFirstRow()) {
        do {
          const colName = rs.getString(1);
          if (colName === 'cookies') { hasCookies = true; break; }
        } while (rs.goToNextRow());
      }
      rs.close();
      if (!hasCookies) {
        await store.executeSql("ALTER TABLE comic_source ADD COLUMN cookies TEXT DEFAULT ''");
        logger.info(TAG, '已为comic_source添加cookies列');
      }
    } catch (error) {
      logger.error(TAG, `确保comic_source.cookies列失败: ${String(error)}`);
    }
  }

  private async ensureComicSourcePkgColumn(): Promise<void> {
    logger.info(TAG, '开始检查并确保comic_source表的pkg列存在');
    try {
      const store = this.getStore();
      const rs = await store.querySql("PRAGMA table_info('comic_source')");
      let hasPkg: boolean = false;
      if (rs.goToFirstRow()) {
        do {
          const colName = rs.getString(1);
          if (colName === 'pkg') { hasPkg = true; break; }
        } while (rs.goToNextRow());
      }
      rs.close();
      
      if (!hasPkg) {
        // 添加 pkg 列
        await store.executeSql("ALTER TABLE comic_source ADD COLUMN pkg TEXT");
        logger.info(TAG, '已为comic_source添加pkg列');
        
        // 为已存在的记录填充 pkg 值
        const sources = await store.querySql("SELECT id, configJson FROM comic_source WHERE pkg IS NULL OR pkg = ''");
        let updateCount = 0;
        
        if (sources.goToFirstRow()) {
          do {
            const id = sources.getLong(0);
            const configJson = sources.getString(1);
            
            try {
              const config: ESObject = JSON.parse(configJson) as ESObject;
              const metadata: ESObject = config.metadata as ESObject;
              if (metadata && metadata.id) {
                const pkg = metadata.id as string;
                await store.executeSql("UPDATE comic_source SET pkg = ? WHERE id = ?", [pkg, id]);
                updateCount++;
                logger.info(TAG, `已为图源 ID=${id} 填充 pkg=${pkg}`);
              }
            } catch (parseError) {
              logger.warn(TAG, `解析图源 ID=${id} 的 configJson 失败: ${String(parseError)}`);
            }
          } while (sources.goToNextRow());
        }
        sources.close();
        
        logger.info(TAG, `已为 ${updateCount} 个图源填充 pkg 值`);
        
        // 为 pkg 列添加唯一约束（如果可能）
        // 注意：SQLite 不支持直接添加唯一约束，需要重建表
      }
    } catch (error) {
      logger.error(TAG, `确保comic_source.pkg列失败: ${String(error)}`);
    }
  }

  /**
   * 确保comic_source表有预加载设置列
   */
  private async ensureComicSourcePreloadColumns(): Promise<void> {
    logger.info(TAG, '开始检查并确保comic_source表的预加载设置列存在');
    try {
      const store = this.getStore();
      const rs = await store.querySql("PRAGMA table_info('comic_source')");
      let hasPreloadCurrentChapter: boolean = false;
      let hasPreloadCurrentPages: boolean = false;
      let hasPreloadNextChapter: boolean = false;
      let hasPreloadNextPages: boolean = false;
      
      if (rs.goToFirstRow()) {
        do {
          const colName = rs.getString(1);
          if (colName === 'preloadCurrentChapter') { hasPreloadCurrentChapter = true; }
          if (colName === 'preloadCurrentPages') { hasPreloadCurrentPages = true; }
          if (colName === 'preloadNextChapter') { hasPreloadNextChapter = true; }
          if (colName === 'preloadNextPages') { hasPreloadNextPages = true; }
        } while (rs.goToNextRow());
      }
      rs.close();
      
      // 添加缺失的列
      if (!hasPreloadCurrentChapter) {
        await store.executeSql("ALTER TABLE comic_source ADD COLUMN preloadCurrentChapter INTEGER DEFAULT 1");
        logger.info(TAG, '已为comic_source添加preloadCurrentChapter列');
      }
      if (!hasPreloadCurrentPages) {
        await store.executeSql("ALTER TABLE comic_source ADD COLUMN preloadCurrentPages INTEGER DEFAULT 3");
        logger.info(TAG, '已为comic_source添加preloadCurrentPages列');
      }
      if (!hasPreloadNextChapter) {
        await store.executeSql("ALTER TABLE comic_source ADD COLUMN preloadNextChapter INTEGER DEFAULT 1");
        logger.info(TAG, '已为comic_source添加preloadNextChapter列');
      }
      if (!hasPreloadNextPages) {
        await store.executeSql("ALTER TABLE comic_source ADD COLUMN preloadNextPages INTEGER DEFAULT -1");
        logger.info(TAG, '已为comic_source添加preloadNextPages列');
      }
    } catch (error) {
      logger.error(TAG, `确保comic_source预加载设置列失败: ${String(error)}`);
    }
  }

  /**
   * 确保comic_source表有tabs_config列
   */
  private async ensureComicSourceTabsConfigColumn(): Promise<void> {
    try {
      const store = this.getStore();
      const rs = await store.querySql("PRAGMA table_info(comic_source)");
      
      let hasTabsConfig = false;
      
      while (rs.goToNextRow()) {
        const columnName = rs.getString(1);
        if (columnName === 'tabs_config') {
          hasTabsConfig = true;
        }
      }
      rs.close();
      
      if (!hasTabsConfig) {
        await store.executeSql("ALTER TABLE comic_source ADD COLUMN tabs_config TEXT");
        logger.info(TAG, '已为comic_source添加tabs_config列');
      }
    } catch (error) {
      logger.error(TAG, `确保comic_source tabs_config列失败: ${String(error)}`);
    }
  }

  /**
   * 确保ebook_reading_progress表有domPos和currentChapterIndex列
   */
  private async ensureEBookProgressColumns(): Promise<void> {
    logger.info(TAG, '开始检查并确保ebook_reading_progress表的domPos和currentChapterIndex列存在');
    try {
      const store = this.getStore();
      const rs = await store.querySql("PRAGMA table_info('ebook_reading_progress')");
      let hasDomPos: boolean = false;
      let hasCurrentChapterIndex: boolean = false;
      
      if (rs.goToFirstRow()) {
        do {
          const colName = rs.getString(1);
          if (colName === 'domPos') { hasDomPos = true; }
          if (colName === 'currentChapterIndex') { hasCurrentChapterIndex = true; }
        } while (rs.goToNextRow());
      }
      rs.close();
      
      logger.info(TAG, `ebook_reading_progress表列检查结果: hasDomPos=${hasDomPos}, hasCurrentChapterIndex=${hasCurrentChapterIndex}`);
      
      if (!hasCurrentChapterIndex) {
        try {
          await store.executeSql("ALTER TABLE ebook_reading_progress ADD COLUMN currentChapterIndex INTEGER DEFAULT 0");
          logger.info(TAG, '已为ebook_reading_progress添加currentChapterIndex列');
        } catch (alterError) {
          logger.warn(TAG, `添加currentChapterIndex列失败（可能已存在）: ${String(alterError)}`);
        }
      }
      
      if (!hasDomPos) {
        try {
          await store.executeSql("ALTER TABLE ebook_reading_progress ADD COLUMN domPos TEXT DEFAULT ''");
          logger.info(TAG, '已为ebook_reading_progress添加domPos列');
        } catch (alterError) {
          logger.warn(TAG, `添加domPos列失败（可能已存在）: ${String(alterError)}`);
        }
      }
    } catch (error) {
      logger.error(TAG, `确保ebook_reading_progress列失败: ${String(error)}`);
    }
  }

  /**
   * 获取数据库版本
   */
  private async getDatabaseVersion(): Promise<number> {
    try {
      const store = this.getStore();
      const resultSet = await store.querySql('PRAGMA user_version');
      
      if (resultSet.goToFirstRow()) {
        const version = resultSet.getLong(0);
        resultSet.close();
        return version;
      }
      
      resultSet.close();
      return 0;
    } catch (error) {
      logger.error(TAG, `获取数据库版本失败: ${String(error)}`);
      return 0;
    }
  }

  /**
   * 更新数据库版本
   */
  private async updateDatabaseVersion(version: number): Promise<void> {
    try {
      const store = this.getStore();
      await store.executeSql(`PRAGMA user_version = ${version}`);
    } catch (error) {
      logger.error(TAG, `更新数据库版本失败: ${String(error)}`);
      throw error as Error;
    }
  }

  /**
   * 执行特定版本的迁移脚本
   */
  private async runMigrationForVersion(version: number): Promise<void> {
    const scripts = MIGRATION_SCRIPTS[version];
    if (!scripts || scripts.length === 0) {
      return;
    }

    const store = this.getStore();
    
    for (let i = 0; i < scripts.length; i++) {
      const script = scripts[i];
      try {
        await store.executeSql(script);
        logger.debug(TAG, `执行迁移脚本成功: ${script}`);
      } catch (error) {
        // 记录错误但不中断迁移，允许重复执行 ADD COLUMN 等操作
        logger.warn(TAG, `执行迁移脚本失败 (可能是列已存在，将继续执行): ${String(error)}`);
      }
    }
  }

  // ==================== CRUD 操作方法 ====================

  /**
   * 插入记录（自动处理重复）
   */
  public async insert<T extends DatabaseRecord>(tableName: string, record: T): Promise<number> {
    try {
      const store = this.getStore();
      const dbRecord = this.convertRecordToDbFormat(tableName, record);
      
      logger.debug(TAG, `准备插入记录到表: ${tableName}`);
      
      // 使用 INSERT OR REPLACE 来自动处理重复记录
      const columns = Object.keys(dbRecord);
      const placeholders = columns.map(() => '?').join(', ');
      const sql = `INSERT OR REPLACE INTO ${tableName} (${columns.join(', ')}) VALUES (${placeholders})`;
      const values = Object.values(dbRecord);
      
      await store.executeSql(sql, values);
      logger.debug(TAG, `插入/更新记录成功，表: ${tableName}`);
      return 0; // executeSql不返回rowId
    } catch (error) {
      logger.error(TAG, `插入记录失败，表: ${tableName}`);
      logger.error(TAG, `错误详情: ${String(error)}`);
      throw error as Error;
    }
  }

  /**
   * 批量插入记录
   * @param tableName 表名
   * @param records 记录数组
   * @param conflictResolution 冲突解决策略：'REPLACE'=替换, 'IGNORE'=忽略, 'FAIL'=失败（默认）
   */
  public async batchInsert<T extends DatabaseRecord>(
    tableName: string, 
    records: T[], 
    conflictResolution: 'REPLACE' | 'IGNORE' | 'FAIL' = 'FAIL'
  ): Promise<number[]> {
    const store = this.getStore();
    const rowIds: number[] = [];
    
    try {
      store.beginTransaction();
      
      for (let i = 0; i < records.length; i++) {
        const record = records[i];
        const dbRecord = this.convertRecordToDbFormat(tableName, record);
        
        if (conflictResolution === 'REPLACE' || conflictResolution === 'IGNORE') {
          // 使用INSERT OR REPLACE/IGNORE来处理唯一性约束冲突
          const columns = Object.keys(dbRecord);
          const placeholders = columns.map(() => '?').join(', ');
          const conflictClause = conflictResolution === 'REPLACE' ? 'OR REPLACE' : 'OR IGNORE';
          const sql = `INSERT ${conflictClause} INTO ${tableName} (${columns.join(', ')}) VALUES (${placeholders})`;
          const values = Object.values(dbRecord);
          
          await store.executeSql(sql, values);
          rowIds.push(0); // executeSql不返回rowId，使用0占位
          
          if (conflictResolution === 'IGNORE') {
            logger.debug(TAG, `记录 ${i + 1}/${records.length} 已存在，已忽略`);
          } else {
            logger.debug(TAG, `记录 ${i + 1}/${records.length} 已替换或插入`);
          }
        } else {
          // 默认行为：遇到冲突抛出异常
          const rowId = await store.insert(tableName, dbRecord);
          rowIds.push(rowId);
        }
      }
      
      store.commit();
      logger.debug(TAG, `批量插入记录成功，表: ${tableName}, 数量: ${records.length}, 冲突策略: ${conflictResolution}`);
      return rowIds;
    } catch (error) {
      store.rollBack();
      logger.error(TAG, `批量插入记录失败: ${String(error)}`);
      throw error as Error;
    }
  }



  /**
   * 更新记录 - 使用统一的更新接口
   */
  public async update(
    tableName: string, 
    record: UpdateRecordData, 
    whereClause: string, 
    whereArgs: DatabaseValue[]
  ): Promise<number> {
    try {
      const store = this.getStore();
      const dbRecord = this.convertRecordToDbFormat(tableName, record);
      
      // 排除id字段，因为id是主键不应该被更新
      const updateKeys = Object.keys(dbRecord).filter(key => key !== 'id');
      if (updateKeys.length === 0) {
        logger.warn(TAG, `没有需要更新的字段，表: ${tableName}`);
        return 0;
      }
      
      // 使用executeSql执行更新操作，因为RdbPredicates不支持复杂的whereClause
      const setClause = updateKeys.map(key => `${key} = ?`).join(', ');
      const sql = `UPDATE ${tableName} SET ${setClause} WHERE ${whereClause}`;
      const updateValues: DatabaseValue[] = [];
      for (const key of updateKeys) {
        updateValues.push(dbRecord[key]);
      }
      const bindArgs = [...updateValues, ...whereArgs];
      
      logger.debug(TAG, `执行更新SQL: ${sql}, 参数数量: ${bindArgs.length}`);
      await store.executeSql(sql, bindArgs);
      
      // 由于executeSql不返回影响行数，我们返回1表示执行成功
      logger.debug(TAG, `更新记录成功，表: ${tableName}`);
      return 1;
    } catch (error) {
      logger.error(TAG, `更新记录失败: ${String(error)}`);
      throw error as Error;
    }
  }

  /**
   * 删除记录
   */
  public async delete(tableName: string, whereClause: string, whereArgs: DatabaseValue[]): Promise<number> {
    try {
      const store = this.getStore();
      
      // 使用executeSql执行删除操作，因为RdbPredicates不支持复杂的whereClause
      const sql = `DELETE FROM ${tableName} WHERE ${whereClause}`;
      
      await store.executeSql(sql, whereArgs);
      
      // 由于executeSql不返回影响行数，我们返回1表示执行成功
      logger.debug(TAG, `删除记录成功，表: ${tableName}`);
      return 1;
    } catch (error) {
      logger.error(TAG, `删除记录失败: ${String(error)}`);
      throw error as Error;
    }
  }

  /**
   * 查询记录
   */
  public async query<T extends DatabaseRecord>(
    tableName: string,
    columns?: string[],
    whereClause?: string,
    whereArgs?: DatabaseValue[],
    orderBy?: string,
    limit?: number
  ): Promise<T[]> {
    try {
      const store = this.getStore();
      
      // 构建SQL查询语句
      let sql = `SELECT ${columns ? columns.join(', ') : '*'} FROM ${tableName}`;
      let bindArgs: DatabaseValue[] = [];
      
      if (whereClause && whereArgs) {
        sql += ` WHERE ${whereClause}`;
        bindArgs = [...whereArgs];
      }
      
      if (orderBy) {
        sql += ` ORDER BY ${orderBy}`;
      }
      
      if (limit) {
        sql += ` LIMIT ${limit}`;
      }
      
      const resultSet = await store.querySql(sql, bindArgs);
      const results: T[] = [];
      
      while (resultSet.goToNextRow()) {
        const record = await this.createRecordFromResultSet(tableName, resultSet);
        if (record) {
          results.push(record as T);
        }
      }
      
      resultSet.close();
      logger.debug(TAG, `查询记录成功，表: ${tableName}, 结果数量: ${results.length}`);
      return results;
    } catch (error) {
      logger.error(TAG, `查询记录失败: ${String(error)}`);
      throw error as Error;
    }
  }

  /**
   * 执行聚合查询（COUNT、SUM、AVG、MIN、MAX等）
   * 专门处理聚合函数查询，返回类型安全的结果
   */
  public async queryAggregation<T extends AggregationQueryResult>(
    sql: string, 
    args?: DatabaseValue[]
  ): Promise<T | null> {
    try {
      const store = this.getStore();
      const resultSet = await store.querySql(sql, args);
      
      if (!resultSet.goToNextRow()) {
        resultSet.close();
        logger.warn(TAG, '聚合查询无结果');
        return null;
      }
      
      const result = await this.createAggregationResultFromResultSet<T>(resultSet);
      resultSet.close();
      
      logger.debug(TAG, `聚合查询成功: ${JSON.stringify(result)}`);
      return result;
    } catch (error) {
      logger.error(TAG, `聚合查询失败: ${String(error)}`);
      throw error as Error;
    }
  }

  /**
   * 执行SQL查询
   */
  public async querySql(sql: string, args?: DatabaseValue[]): Promise<DatabaseRecord[]> {
    try {
      const store = this.getStore();
      const resultSet = await store.querySql(sql, args);
      const results: DatabaseRecord[] = [];
      
      while (resultSet.goToNextRow()) {
        // 对于原生SQL查询，我们创建一个通用的记录对象
        const record = await this.createGenericRecordFromResultSet(resultSet);
        results.push(record);
      }
      
      resultSet.close();
      logger.debug(TAG, `SQL查询成功，结果数量: ${results.length}`);
      return results;
    } catch (error) {
      logger.error(TAG, `SQL查询失败: ${String(error)}`);
      throw error as Error;
    }
  }

  /**
   * 执行SQL语句
   */
  public async executeSql(sql: string, args?: DatabaseValue[]): Promise<void> {
    try {
      const store = this.getStore();
      await store.executeSql(sql, args);
      logger.debug(TAG, `SQL执行成功: ${sql}`);
    } catch (error) {
      logger.error(TAG, `SQL执行失败: ${String(error)}`);
      throw error as Error;
    }
  }

  /**
   * 获取表记录数量（类型安全的聚合查询）
   */
  public async getTableCount(tableName: string): Promise<number> {
    try {
      const sql = `SELECT COUNT(*) as count FROM ${tableName}`;
      const result = await this.queryAggregation<CountQueryResult>(sql);
      
      if (!result) {
        logger.warn(TAG, `表 ${tableName} 计数查询无结果`);
        return 0;
      }
      
      return result.count;
    } catch (error) {
      logger.error(TAG, `获取表 ${tableName} 记录数量失败: ${String(error)}`);
      throw error as Error;
    }
  }

  /**
   * 获取表字段总和（类型安全的聚合查询）
   */
  public async getTableSum(tableName: string, columnName: string): Promise<number> {
    try {
      const sql = `SELECT SUM(${columnName}) as sum FROM ${tableName}`;
      const result = await this.queryAggregation<SumQueryResult>(sql);
      
      if (!result) {
        logger.warn(TAG, `表 ${tableName} 字段 ${columnName} 求和查询无结果`);
        return 0;
      }
      
      return result.sum;
    } catch (error) {
      logger.error(TAG, `获取表 ${tableName} 字段 ${columnName} 总和失败: ${String(error)}`);
      throw error as Error;
    }
  }

  /**
   * 获取表字段平均值（类型安全的聚合查询）
   */
  public async getTableAverage(tableName: string, columnName: string): Promise<number> {
    try {
      const sql = `SELECT AVG(${columnName}) as avg FROM ${tableName}`;
      const result = await this.queryAggregation<AvgQueryResult>(sql);
      
      if (!result) {
        logger.warn(TAG, `表 ${tableName} 字段 ${columnName} 平均值查询无结果`);
        return 0;
      }
      
      return result.avg;
    } catch (error) {
      logger.error(TAG, `获取表 ${tableName} 字段 ${columnName} 平均值失败: ${String(error)}`);
      throw error as Error;
    }
  }

  // ==================== 事务管理 ====================

  /**
   * 开始事务
   */
  public async beginTransaction(): Promise<void> {
    try {
      const store = this.getStore();
      store.beginTransaction();
      logger.debug(TAG, '开始事务');
    } catch (error) {
      logger.error(TAG, `开始事务失败: ${String(error)}`);
      throw error as Error;
    }
  }

  /**
   * 提交事务
   */
  public async commit(): Promise<void> {
    try {
      const store = this.getStore();
      store.commit();
      logger.debug(TAG, '提交事务');
    } catch (error) {
      logger.error(TAG, `提交事务失败: ${String(error)}`);
      throw error as Error;
    }
  }

  /**
   * 回滚事务
   */
  public async rollBack(): Promise<void> {
    try {
      const store = this.getStore();
      store.rollBack();
      logger.debug(TAG, '回滚事务');
    } catch (error) {
      logger.error(TAG, `回滚事务失败: ${String(error)}`);
      throw error as Error;
    }
  }

  // ==================== 私有辅助方法 ====================

  /**
   * 从ResultSet创建记录对象
   */
  private async createRecordFromResultSet(tableName: string, resultSet: relationalStore.ResultSet): Promise<DatabaseRecord | null> {
    try {
      const recordType = this.getRecordTypeFromTableName(tableName);
      if (!recordType) {
        logger.error(TAG, `未知的表名: ${tableName}`);
        return null;
      }
      
      let record: DatabaseRecord;
      switch (recordType) {
        case DatabaseRecordType.COMIC_SOURCE:
          record = DatabaseRecordFactory.createComicSourceRecord();
          break;
        case DatabaseRecordType.COMIC_INFO:
          record = DatabaseRecordFactory.createComicInfoRecord();
          break;
        case DatabaseRecordType.CHAPTER_INFO:
          record = DatabaseRecordFactory.createChapterInfoRecord();
          break;
        case DatabaseRecordType.PAGE_INFO:
          record = DatabaseRecordFactory.createPageInfoRecord();
          break;
        case DatabaseRecordType.FAVORITE_INFO:
          record = DatabaseRecordFactory.createFavoriteInfoRecord();
          break;
        case DatabaseRecordType.read_HISTORY:
          // 支持 read_history 记录的创建
          record = DatabaseRecordFactory.createReadHistoryRecord();
          break;
        default:
          logger.error(TAG, `不支持的记录类型: ${recordType}`);
          return null;
      }
      
      await this.fillRecordFromResultSet(record, resultSet);
      return record;
    } catch (error) {
      logger.error(TAG, `从ResultSet创建记录失败: ${String(error)}`);
      return null;
    }
  }

  /**
   * 从ResultSet创建聚合查询结果对象
   */
  private async createAggregationResultFromResultSet<T extends AggregationQueryResult>(
    resultSet: relationalStore.ResultSet
  ): Promise<T> {
    const columnNames = resultSet.columnNames;
    
    // 根据聚合查询的特点，创建类型安全的结果对象
    if (columnNames.length === 1) {
      const columnName = columnNames[0];
      const columnType = await resultSet.getColumnType(0);
      let value: number;
      
      switch (columnType) {
        case relationalStore.ColumnType.INTEGER:
          value = resultSet.getLong(0);
          break;
        case relationalStore.ColumnType.REAL:
          value = resultSet.getDouble(0);
          break;
        case relationalStore.ColumnType.TEXT:
          const stringValue = resultSet.getString(0);
          value = parseFloat(stringValue) || 0;
          break;
        default:
          value = 0;
          break;
      }
      
      // 根据列名创建对应的结果对象
      if (columnName.toLowerCase() === 'count') {
        return new CountResult(Math.floor(value)) as T;
      } else if (columnName.toLowerCase() === 'sum') {
        return new SumResult(value) as T;
      } else if (columnName.toLowerCase() === 'avg') {
        return new AvgResult(value) as T;
      } else if (columnName.toLowerCase() === 'min') {
        return new MinMaxResult(value, undefined) as T;
      } else if (columnName.toLowerCase() === 'max') {
        return new MinMaxResult(undefined, value) as T;
      }
    }
    
    // 处理多列聚合查询（如MIN和MAX同时查询）
    let minValue: number | undefined = undefined;
    let maxValue: number | undefined = undefined;
    
    for (let i = 0; i < columnNames.length; i++) {
      const columnName = columnNames[i];
      const columnType = await resultSet.getColumnType(i);
      let value: number;
      
      switch (columnType) {
        case relationalStore.ColumnType.INTEGER:
          value = resultSet.getLong(i);
          break;
        case relationalStore.ColumnType.REAL:
          value = resultSet.getDouble(i);
          break;
        case relationalStore.ColumnType.TEXT:
          const stringValue = resultSet.getString(i);
          value = parseFloat(stringValue) || 0;
          break;
        default:
          value = 0;
          break;
      }
      
      if (columnName.toLowerCase() === 'min') {
        minValue = value;
      } else if (columnName.toLowerCase() === 'max') {
        maxValue = value;
      }
    }
    
    // 返回MinMaxResult实例
    return new MinMaxResult(minValue, maxValue) as T;
  }

  /**
   * 创建通用记录对象（用于原生SQL查询）
   */
  private async createGenericRecordFromResultSet(resultSet: relationalStore.ResultSet): Promise<DatabaseRecord> {
    // 创建一个GenericQueryRecord对象，动态填充所有列
    const record: GenericQueryRecord = {};
    
    // 直接从ResultSet填充GenericQueryRecord，不使用fillRecordFromResultSet
    const columnNames = resultSet.columnNames;
    
    for (let i = 0; i < columnNames.length; i++) {
      const columnName = columnNames[i];
      const columnType = await resultSet.getColumnType(i);
      let value: DatabaseValue = null;
      
      switch (columnType) {
        case relationalStore.ColumnType.INTEGER:
          value = resultSet.getLong(i);
          break;
        case relationalStore.ColumnType.REAL:
          value = resultSet.getDouble(i);
          break;
        case relationalStore.ColumnType.TEXT:
          value = resultSet.getString(i);
          break;
        case relationalStore.ColumnType.BLOB:
          value = resultSet.getBlob(i);
          break;
        default:
          value = null;
          break;
      }
      
      // 直接设置属性，绕过setRecordProperty的类型转换问题
      if (columnName === 'id') {
        record.id = value;
      } else if (columnName === 'comicId') {
        record.comicId = value;
      } else if (columnName === 'externalId') {
        record.externalId = value;
      } else if (columnName === 'chapterId') {
        record.chapterId = value;
      } else if (columnName === 'userId') {
        record.userId = value;
      } else if (columnName === 'pageNumber') {
        record.pageNumber = value;
      } else if (columnName === 'readTime') {
        record.readTime = value;
      } else if (columnName === 'duration') {
        record.duration = value;
      } else if (columnName === 'createTime') {
        record.createTime = value;
      } else if (columnName === 'settingKey') {
        record.settingKey = value;
      } else if (columnName === 'settingValue') {
        record.settingValue = value;
      } else if (columnName === 'settingType') {
        record.settingType = value;
      } else if (columnName === 'updateTime') {
        record.updateTime = value;
      } else if (columnName === 'title') {
        record.title = value;
      } else if (columnName === 'author') {
        record.author = value;
      } else if (columnName === 'description') {
        record.description = value;
      } else if (columnName === 'coverUrl') {
        record.coverUrl = value;
      } else if (columnName === 'sourceId') {
        record.sourceId = value;
      } else if (columnName === 'status') {
        record.status = value;
      } else if (columnName === 'tags') {
        record.tags = value;
      } else if (columnName === 'rating') {
        record.rating = value;
      } else if (columnName === 'chapterCount') {
        record.chapterCount = value;
      } else if (columnName === 'lastUpdateTime') {
        record.lastUpdateTime = value;
      } else if (columnName === 'addTime') {
        record.addTime = value;
      } else if (columnName === 'chapterIndex') {
        record.chapterIndex = value;
      } else if (columnName === 'pageCount') {
        record.pageCount = value;
      } else if (columnName === 'isDownloaded') {
        record.isDownloaded = value;
      } else if (columnName === 'downloadPath') {
        record.downloadPath = value;
      } else if (columnName === 'publishTime') {
        record.publishTime = value;
      } else if (columnName === 'index') {
        record.index = value;
      } else if (columnName === 'imageUrl') {
        record.imageUrl = value;
      } else if (columnName === 'localPath') {
        record.localPath = value;
      } else if (columnName === 'width') {
        record.width = value;
      } else if (columnName === 'height') {
        record.height = value;
      } else if (columnName === 'fileSize') {
        record.fileSize = value;
      } else if (columnName === 'name') {
        record.name = value;
      } else if (columnName === 'baseUrl') {
        record.baseUrl = value;
      } else if (columnName === 'pluginId') {
        record.pluginId = value;
      } else if (columnName === 'isEnabled') {
        record.isEnabled = value;
      } else if (columnName === 'priority') {
        record.priority = value;
      } else if (columnName === 'config') {
        record.config = value;
      } else if (columnName === 'configJson') {
        record.configJson = value;
      } else if (columnName === 'userAgent') {
        record.userAgent = value;
      } else if (columnName === 'enableJavaScript') {
        record.enableJavaScript = value;
      } else if (columnName === 'enableImages') {
        record.enableImages = value;
      } else if (columnName === 'timeout') {
        record.timeout = value;
      } else if (columnName === 'cookies') {
        record.cookies = value;
      } else if (columnName === 'content') {
        record.content = value;
      } else if (columnName === 'bookId') {
        record.bookId = value;
      } else if (columnName === 'chapterNumber') {
        record.chapterNumber = value;
      } else if (columnName === 'startPosition') {
        record.startPosition = value;
      } else if (columnName === 'endPosition') {
        record.endPosition = value;
      } else if (columnName === 'wordCount') {
        record.wordCount = value;
      } else if (columnName === 'format') {
        record.format = value;
      } else if (columnName === 'filePath') {
        record.filePath = value;
      } else if (columnName === 'publisher') {
        record.publisher = value;
      } else if (columnName === 'publishDate') {
        record.publishDate = value;
      } else if (columnName === 'isbn') {
        record.isbn = value;
      } else if (columnName === 'language') {
        record.language = value;
      } else if (columnName === 'coverImagePath') {
        record.coverImagePath = value;
      } else if (columnName === 'isFavorite') {
        record.isFavorite = value;
      } else if (columnName === 'totalWordCount') {
        record.totalWordCount = value;
      } else if (columnName === 'currentChapterId') {
        record.currentChapterId = value;
      } else if (columnName === 'currentPosition') {
        record.currentPosition = value;
      } else if (columnName === 'progress') {
        record.progress = value;
      } else if (columnName === 'lastReadTime') {
        record.lastReadTime = value;
      } else if (columnName === 'totalReadingTime') {
        record.totalReadingTime = value;
      } else if (columnName === 'fontSize') {
        record.fontSize = value;
      } else if (columnName === 'lineHeight') {
        record.lineHeight = value;
      } else if (columnName === 'fontFamily') {
        record.fontFamily = value;
      } else if (columnName === 'backgroundColor') {
        record.backgroundColor = value;
      } else if (columnName === 'textColor') {
        record.textColor = value;
      } else if (columnName === 'pageMargin') {
        record.pageMargin = value;
      } else if (columnName === 'pageMode') {
        record.pageMode = value;
      } else if (columnName === 'brightness') {
        record.brightness = value;
      } else if (columnName === 'autoSave') {
        record.autoSave = value;
      } else if (columnName === 'saveInterval') {
        record.saveInterval = value;
      } else if (columnName === 'currentChapterIndex') {
        record.currentChapterIndex = value;
      } else if (columnName === 'domPos') {
        record.domPos = value;
      } else if (columnName === 'fontPath') {
        record.fontPath = value;
      } else if (columnName === 'fontWeight') {
        record.fontWeight = value;
      } else if (columnName === 'themeBgImage') {
        record.themeBgImage = value;
      } else if (columnName === 'nightMode') {
        record.nightMode = value;
      } else if (columnName === 'followSystemTheme') {
        record.followSystemTheme = value;
      }
      // 其他字段可以根据需要继续添加
    }
    
    return record;
  }

  /**
   * 从ResultSet填充记录对象
   */
  private async fillRecordFromResultSet(record: DatabaseRecord, resultSet: relationalStore.ResultSet): Promise<void> {
    const columnNames = resultSet.columnNames;
    
    for (let i = 0; i < columnNames.length; i++) {
      const columnName = columnNames[i];
      const columnType = await resultSet.getColumnType(i);
      let value: DatabaseValue = null;
      
      switch (columnType) {
        case relationalStore.ColumnType.INTEGER:
          value = resultSet.getLong(i);
          break;
        case relationalStore.ColumnType.REAL:
          value = resultSet.getDouble(i);
          break;
        case relationalStore.ColumnType.TEXT:
          value = resultSet.getString(i);
          break;
        case relationalStore.ColumnType.BLOB:
          value = resultSet.getBlob(i);
          break;
        default:
          value = null;
          break;
      }
      
      // 使用显式属性赋值而不是索引访问
      this.setRecordProperty(record, columnName, value);
    }
  }

  /**
   * 设置记录属性（避免索引访问）
   */
  private setRecordProperty(record: DatabaseRecord, propertyName: string, value: DatabaseValue): void {
    // 根据属性名设置对应的属性值
    switch (propertyName) {
      case 'id':
        if (typeof value === 'string' || typeof value === 'number') {
          (record as ComicSourceDatabaseRecord).id = String(value);
        }
        break;
      case 'name':
        if (typeof value === 'string') {
          (record as ComicSourceDatabaseRecord).name = value;
        }
        break;
      case 'baseUrl':
        if (typeof value === 'string') {
          (record as ComicSourceDatabaseRecord).baseUrl = value;
        }
        break;
      // 可以根据需要添加更多属性的处理
      default:
        // 对于未明确处理的属性，使用类型检查替代in操作符
        const recordKeys = Object.keys(record);
        if (recordKeys.includes('id') && recordKeys.includes('name') && recordKeys.includes('baseUrl')) {
          // 这是ComicSourceDatabaseRecord类型
          const comicSourceRecord = record as ComicSourceDatabaseRecord;
          switch (propertyName) {
            case 'pluginId':
              if (typeof value === 'string') {
                comicSourceRecord.pluginId = value;
              }
              break;
            case 'isEnabled':
              if (typeof value === 'boolean') {
                comicSourceRecord.isEnabled = value;
              }
              break;
            case 'priority':
              if (typeof value === 'number') {
                comicSourceRecord.priority = value;
              }
              break;
            case 'lastUpdateTime':
              if (typeof value === 'number') {
                comicSourceRecord.lastUpdateTime = value;
              }
              break;
            case 'config':
              if (typeof value === 'string') {
                comicSourceRecord.configJson = value;
              }
              break;
            case 'addTime':
              if (typeof value === 'number') {
                comicSourceRecord.addTime = value;
              }
              break;
            case 'cookies':
              if (typeof value === 'string') {
                comicSourceRecord.cookies = value;
              }
              break;
          }
        } else if (recordKeys.includes('id') && recordKeys.includes('title')) {
          // 这是ComicInfoDatabaseRecord类型
          const comicInfoRecord = record as ComicInfoDatabaseRecord;
          switch (propertyName) {
            case 'title':
              if (typeof value === 'string') {
                comicInfoRecord.title = value;
              }
              break;
            case 'author':
              if (typeof value === 'string') {
                comicInfoRecord.author = value;
              }
              break;
            case 'description':
              if (typeof value === 'string') {
                comicInfoRecord.description = value;
              }
              break;
            case 'coverUrl':
              if (typeof value === 'string') {
                comicInfoRecord.coverUrl = value;
              }
              break;
            case 'sourceId':
              if (typeof value === 'string') {
                comicInfoRecord.sourceId = value;
              }
              break;
            case 'status':
              if (typeof value === 'string') {
                comicInfoRecord.status = value;
              }
              break;
            case 'tags':
              if (typeof value === 'string') {
                comicInfoRecord.tags = value;
              }
              break;
            case 'rating':
              if (typeof value === 'number') {
                comicInfoRecord.rating = value;
              }
              break;
            case 'chapterCount':
              if (typeof value === 'number') {
                comicInfoRecord.chapterCount = value;
              }
              break;
            case 'lastUpdateTime':
              if (typeof value === 'number') {
                comicInfoRecord.lastUpdateTime = value;
              }
              break;
            case 'addTime':
              if (typeof value === 'number') {
                comicInfoRecord.addTime = value;
              }
              break;
          }
        } else if (recordKeys.includes('id') && recordKeys.includes('chapterId') && recordKeys.includes('imageUrl')) {
          // 这是PageInfoDatabaseRecord类型
          const pageInfoRecord = record as PageInfoDatabaseRecord;
          switch (propertyName) {
            case 'chapterId':
              if (typeof value === 'string') {
                pageInfoRecord.chapterId = value;
              }
              break;
            case 'pageNumber':
              if (typeof value === 'number') {
                pageInfoRecord.index = value;
              }
              break;
            case 'imageUrl':
              if (typeof value === 'string') {
                pageInfoRecord.imageUrl = value;
              }
              break;
            case 'localPath':
              if (typeof value === 'string') {
                pageInfoRecord.localPath = value;
              }
              break;
            case 'width':
              if (typeof value === 'number') {
                pageInfoRecord.width = value;
              }
              break;
            case 'height':
              if (typeof value === 'number') {
                pageInfoRecord.height = value;
              }
              break;
            case 'fileSize':
              if (typeof value === 'number') {
                pageInfoRecord.fileSize = value;
              }
              break;
          }
        } else if (recordKeys.includes('id') && recordKeys.includes('comicId') && recordKeys.includes('userId') && recordKeys.includes('tags')) {
          // 这是FavoriteInfoDatabaseRecord类型
          const favoriteRecord = record as FavoriteInfoDatabaseRecord;
          switch (propertyName) {
            case 'comicId':
              if (typeof value === 'string') {
                favoriteRecord.comicId = value;
              }
              break;
            case 'userId':
              if (typeof value === 'string') {
                favoriteRecord.userId = value;
              }
              break;
            case 'addTime':
              if (typeof value === 'number') {
                favoriteRecord.addTime = value;
              }
              break;
            case 'lastReadChapterId':
              if (typeof value === 'string') {
                favoriteRecord.lastReadChapterId = value;
              }
              break;
            case 'lastReadTime':
              if (typeof value === 'number') {
                favoriteRecord.lastReadTime = value;
              }
              break;
            // 数据库中的其他字段（folderName、lastReadPageNumber、readProgress）当前记录类型未使用，忽略
          }
        } else if (recordKeys.includes('id') && recordKeys.includes('comicId') && recordKeys.includes('chapterId') && recordKeys.includes('pageNumber') && recordKeys.includes('userId') && recordKeys.includes('duration')) {
          // 这是 ReadHistoryDatabaseRecord 类型
          const historyRecord = record as ReadHistoryDatabaseRecord;
          switch (propertyName) {
            case 'comicId':
              if (typeof value === 'string') {
                historyRecord.comicId = value;
              }
              break;
            case 'chapterId':
              if (typeof value === 'string') {
                historyRecord.chapterId = value;
              }
              break;
            case 'userId':
              if (typeof value === 'string') {
                historyRecord.userId = value;
              }
              break;
            case 'pageNumber':
              if (typeof value === 'number') {
                historyRecord.pageNumber = value;
              }
              break;
            case 'readTime':
              if (typeof value === 'number') {
                historyRecord.readTime = value;
              }
              break;
            case 'duration':
              if (typeof value === 'number') {
                historyRecord.duration = value;
              }
              break;
            case 'id':
              if (typeof value === 'string' || typeof value === 'number') {
                historyRecord.id = String(value);
              }
              break;
            // createTime 不在 ReadHistoryDatabaseRecord 中，忽略
          }
        }
        break;
    }
  }

  /**
   * 根据表名获取记录类型
   */
  private getRecordTypeFromTableName(tableName: string): DatabaseRecordType | null {
    switch (tableName) {
      case 'comic_source':
        return DatabaseRecordType.COMIC_SOURCE;
      case 'comic_info':
        return DatabaseRecordType.COMIC_INFO;
      case 'chapter':
        return DatabaseRecordType.CHAPTER_INFO;
      case 'page':
        return DatabaseRecordType.PAGE_INFO;
      case 'favorite':
        return DatabaseRecordType.FAVORITE_INFO;
      case 'read_history':
        return DatabaseRecordType.read_HISTORY;
      case 'download_task':
        return DatabaseRecordType.DOWNLOAD_TASK;
      case 'user_settings':
        return DatabaseRecordType.USER_SETTINGS;
      case 'plugin':
        return DatabaseRecordType.PLUGIN;
      case 'online_comic_info':
        return DatabaseRecordType.COMIC_INFO;
      case 'online_chapter':
        return DatabaseRecordType.CHAPTER_INFO;
      case 'online_page':
        return DatabaseRecordType.PAGE_INFO;
      case 'online_read_history':
        return DatabaseRecordType.read_HISTORY;
      default:
        return null;
    }
  }

  /**
   * 将记录转换为数据库格式 - 支持UpdateRecordData接口
   */
  private convertRecordToDbFormat(tableName: string, record: DatabaseRecord | UpdateRecordData): Record<string, DatabaseValue> {
    // 更精确的UpdateRecordData类型判断：检查是否只包含更新相关的字段
    // UpdateRecordData通常只包含少数几个字段，而DatabaseRecord包含完整的数据结构
    const recordKeys = Object.keys(record);
    // 增加字段数量限制到10，因为刮削结果可能包含多个字段（id, updatedAt, title, description, author, tags等）
    const isUpdateRecord = recordKeys.includes('id') && 
                          typeof (record as UpdateRecordData).id === 'string' &&
                          recordKeys.length <= 10 && // UpdateRecordData通常字段较少，但刮削可能有6-8个字段
                          !recordKeys.includes('imageUrl') && // PageInfoDatabaseRecord特有字段
                          !recordKeys.includes('pageNumber') && // PageInfoDatabaseRecord特有字段
                          !recordKeys.includes('chapters'); // ComicInfoDatabaseRecord特有字段（章节数组）
    
    if (isUpdateRecord) {
      const result: Record<string, DatabaseValue> = {};
      const entries: [string, DatabaseValue | undefined][] = Object.entries(record) as [string, DatabaseValue | undefined][];
      for (let i = 0; i < entries.length; i++) {
        const key: string = entries[i][0];
        const value: DatabaseValue | undefined = entries[i][1];
        if (value !== undefined) {
          result[key] = value;
        }
      }
      return result;
    }
    
    // 原有的DatabaseRecord类型转换逻辑
    switch (tableName) {
      case 'comic_source':
        return convertComicSourceToDbFormat(record as ComicSourceDatabaseRecord);
      case 'comic_info':
        return convertComicInfoToDbFormat(record as ComicInfoDatabaseRecord);
      case 'chapter':
        return convertChapterInfoToDbFormat(record as ChapterInfoDatabaseRecord);
      case 'page':
        return convertPageInfoToDbFormat(record as PageInfoDatabaseRecord);
      case 'favorite':
        return convertFavoriteInfoToDbFormat(record as FavoriteInfoDatabaseRecord);
      case 'read_history':
        return convertReadHistoryToDbFormat(record as ReadHistoryDatabaseRecord);
      case 'download_task':
        return convertDownloadTaskToDbFormat(record as DownloadTaskDatabaseRecord);
      case 'user_settings':
        return convertUserSettingsToDbFormat(record as UserSettingsDatabaseRecord);
      case 'plugin':
        return convertPluginToDbFormat(record as PluginDatabaseRecord);
      case 'online_comic_info':
        return convertOnlineComicInfoToDbFormat(record as OnlineComicInfoDatabaseRecord);
      case 'online_chapter':
        return convertOnlineChapterInfoToDbFormat(record as OnlineChapterInfoDatabaseRecord);
      case 'online_page':
        return convertOnlinePageInfoToDbFormat(record as OnlinePageInfoDatabaseRecord);
      case 'online_read_history':
        return convertReadHistoryToDbFormat(record as ReadHistoryDatabaseRecord);
      default:
        throw new Error(`未知的表名: ${tableName}`);
    }
  }

  /**
   * 关闭数据库
   */
  public async close(): Promise<void> {
    if (this.store) {
      try {
        await this.store.close();
        this.store = null;
        this.isInitialized = false;
        logger.info(TAG, '数据库已关闭');
      } catch (error) {
        logger.error(TAG, `关闭数据库失败: ${String(error)}`);
        throw error as Error;
      }
    }
  }

  /**
   * 销毁单例实例
   */
  public static async destroyInstance(): Promise<void> {
    if (DatabaseManager.instance) {
      await DatabaseManager.instance.close();
      DatabaseManager.instance = null;
    }
  }
}
