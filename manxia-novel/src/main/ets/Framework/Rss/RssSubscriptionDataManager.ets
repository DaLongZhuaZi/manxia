import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { RssFeedItem, RssSubscriptionSource } from 'manxia_core/src/main/ets/Models/RssSubscriptionModels';
import {
  RSS_CREATE_INDEX_SQL,
  RSS_CREATE_TABLE_SQL,
  RSS_SOURCE_MIGRATION_SQL
} from './RssSubscriptionDatabaseSchema';

const TAG = 'RssSubscriptionDataManager';

const RSS_SOURCE_SELECT_COLUMNS = `
  id, name, url, sourceComment, enabled, autoUpdate, updateIntervalMin,
  variableComment, jsLib, enabledCookieJar, concurrentRate, header, loginUrl, loginUi,
  loginCheckJs, coverDecodeJs, sortUrl, singleUrl, articleStyle, ruleArticles, ruleNextPage,
  ruleTitle, rulePubDate, ruleDescription, ruleImage, ruleLink, ruleContent,
  contentWhitelist, contentBlacklist, shouldOverrideUrlLoading, style, enableJs,
  loadWithBaseUrl, injectJs, lastUpdateTime, customOrder, etag, lastModified, lastCheckTime,
  lastSuccessTime, lastError, iconUrl, groupName, createTime, updateTime
`;

const RSS_ITEM_SELECT_COLUMNS = `
  i.id, i.sourceId, i.sourceName, i.title, i.link, i.description, i.content, i.author,
  i.category, i.guid, i.pubDate, i.isRead, i.isStarred, i.createTime, i.updateTime
`;

interface TableInfo {
  name: string;
  sql: string;
}

interface ExistingRssItem {
  id: string;
  link: string;
}

export interface RssItemQueryOptions {
  sourceId?: string;
  unreadOnly?: boolean;
  starredOnly?: boolean;
  limit?: number;
}

export interface RssSourceFetchMeta {
  etag: string;
  lastModified: string;
  lastCheckTime: number;
  lastSuccessTime: number;
  lastError: string;
}

export class RssSubscriptionDataManager {
  private static instance: RssSubscriptionDataManager | null = null;
  private store: relationalStore.RdbStore | null = null;
  private isInitialized: boolean = false;

  private constructor() {
  }

  static getInstance(): RssSubscriptionDataManager {
    if (!RssSubscriptionDataManager.instance) {
      RssSubscriptionDataManager.instance = new RssSubscriptionDataManager();
    }
    return RssSubscriptionDataManager.instance;
  }

  async initialize(context: common.UIAbilityContext): Promise<void> {
    if (this.isInitialized) {
      logger.debug(TAG, '订阅源数据库已初始化，跳过重复初始化');
      return;
    }
    const config: relationalStore.StoreConfig = {
      name: 'manxia_comic.db',
      securityLevel: relationalStore.SecurityLevel.S1,
      encrypt: false,
    };

    logger.info(TAG, '开始初始化订阅源数据库');
    this.store = await relationalStore.getRdbStore(context, config);
    await this.store.executeSql('PRAGMA journal_mode=WAL');
    await this.createTables();
    await this.runSchemaMigrations();
    await this.migrateLegacyReadAndStarState();
    await this.createIndexes();
    this.isInitialized = true;
    logger.info(TAG, '订阅源数据库初始化完成');
  }

  isReady(): boolean {
    return this.isInitialized;
  }

  private getStore(): relationalStore.RdbStore {
    if (!this.store) {
      throw new Error('订阅源数据库尚未初始化');
    }
    return this.store;
  }

  private async createTables(): Promise<void> {
    const tables: TableInfo[] = [
      { name: 'rss_subscription_source', sql: RSS_CREATE_TABLE_SQL.RSS_SOURCE } as TableInfo,
      { name: 'rss_subscription_item', sql: RSS_CREATE_TABLE_SQL.RSS_ITEM } as TableInfo,
      { name: 'rss_subscription_read_record', sql: RSS_CREATE_TABLE_SQL.RSS_READ_RECORD } as TableInfo,
      { name: 'rss_subscription_star', sql: RSS_CREATE_TABLE_SQL.RSS_STAR } as TableInfo
    ];
    const store = this.getStore();
    for (const table of tables) {
      try {
        await store.executeSql(table.sql);
      } catch (error) {
        logger.warn(TAG, `创建数据表失败: ${table.name}, ${String(error)}`);
      }
    }
  }

  private async runSchemaMigrations(): Promise<void> {
    const store = this.getStore();
    for (const migration of RSS_SOURCE_MIGRATION_SQL) {
      try {
        await store.executeSql(migration.sql);
        logger.info(TAG, `订阅源表结构迁移完成: ${migration.name}`);
      } catch (_error) {
      }
    }
  }

  private async migrateLegacyReadAndStarState(): Promise<void> {
    const store = this.getStore();
    const now = Date.now();
    try {
      await store.executeSql(
        `INSERT OR IGNORE INTO rss_subscription_read_record (itemId, sourceId, readTime)
         SELECT id, sourceId, COALESCE(updateTime, createTime, ?) FROM rss_subscription_item WHERE isRead = 1`,
        [now]
      );
      await store.executeSql(
        `INSERT OR IGNORE INTO rss_subscription_star (itemId, sourceId, starTime)
         SELECT id, sourceId, COALESCE(updateTime, createTime, ?) FROM rss_subscription_item WHERE isStarred = 1`,
        [now]
      );
      logger.info(TAG, '历史订阅条目已读/收藏状态迁移完成');
    } catch (error) {
      logger.warn(TAG, `迁移历史已读/收藏状态失败: ${String(error)}`);
    }
  }

  private async createIndexes(): Promise<void> {
    const store = this.getStore();
    for (const sql of RSS_CREATE_INDEX_SQL) {
      try {
        await store.executeSql(sql);
      } catch (_error) {
      }
    }
  }

  private generateId(): string {
    return `${Date.now()}_${Math.random().toString(36).substring(2, 9)}`;
  }

  private getColumnIndex(rs: relationalStore.ResultSet, columnName: string): number {
    try {
      return rs.getColumnIndex(columnName);
    } catch (_error) {
      return -1;
    }
  }

  private getStringValue(rs: relationalStore.ResultSet, columnName: string, defaultValue: string = ''): string {
    const index = this.getColumnIndex(rs, columnName);
    if (index < 0) {
      return defaultValue;
    }
    try {
      const value = rs.getString(index);
      return value !== undefined && value !== null ? value : defaultValue;
    } catch (_error) {
      return defaultValue;
    }
  }

  private getLongValue(rs: relationalStore.ResultSet, columnName: string, defaultValue: number = 0): number {
    const index = this.getColumnIndex(rs, columnName);
    if (index < 0) {
      return defaultValue;
    }
    try {
      return rs.getLong(index);
    } catch (_error) {
      return defaultValue;
    }
  }

  private getBoolValue(rs: relationalStore.ResultSet, columnName: string, defaultValue: boolean = false): boolean {
    return this.getLongValue(rs, columnName, defaultValue ? 1 : 0) === 1;
  }

  private toSourceFromRow(rs: relationalStore.ResultSet): RssSubscriptionSource {
    return {
      id: this.getStringValue(rs, 'id'),
      name: this.getStringValue(rs, 'name'),
      url: this.getStringValue(rs, 'url'),
      sourceComment: this.getStringValue(rs, 'sourceComment'),
      enabled: this.getBoolValue(rs, 'enabled', true),
      autoUpdate: this.getBoolValue(rs, 'autoUpdate', true),
      updateIntervalMin: this.getLongValue(rs, 'updateIntervalMin', 180),
      variableComment: this.getStringValue(rs, 'variableComment'),
      jsLib: this.getStringValue(rs, 'jsLib'),
      enabledCookieJar: this.getBoolValue(rs, 'enabledCookieJar', true),
      concurrentRate: this.getStringValue(rs, 'concurrentRate'),
      header: this.getStringValue(rs, 'header'),
      loginUrl: this.getStringValue(rs, 'loginUrl'),
      loginUi: this.getStringValue(rs, 'loginUi'),
      loginCheckJs: this.getStringValue(rs, 'loginCheckJs'),
      coverDecodeJs: this.getStringValue(rs, 'coverDecodeJs'),
      sortUrl: this.getStringValue(rs, 'sortUrl'),
      singleUrl: this.getBoolValue(rs, 'singleUrl', false),
      articleStyle: this.getLongValue(rs, 'articleStyle', 0),
      ruleArticles: this.getStringValue(rs, 'ruleArticles'),
      ruleNextPage: this.getStringValue(rs, 'ruleNextPage'),
      ruleTitle: this.getStringValue(rs, 'ruleTitle'),
      rulePubDate: this.getStringValue(rs, 'rulePubDate'),
      ruleDescription: this.getStringValue(rs, 'ruleDescription'),
      ruleImage: this.getStringValue(rs, 'ruleImage'),
      ruleLink: this.getStringValue(rs, 'ruleLink'),
      ruleContent: this.getStringValue(rs, 'ruleContent'),
      contentWhitelist: this.getStringValue(rs, 'contentWhitelist'),
      contentBlacklist: this.getStringValue(rs, 'contentBlacklist'),
      shouldOverrideUrlLoading: this.getStringValue(rs, 'shouldOverrideUrlLoading'),
      style: this.getStringValue(rs, 'style'),
      enableJs: this.getBoolValue(rs, 'enableJs', true),
      loadWithBaseUrl: this.getBoolValue(rs, 'loadWithBaseUrl', true),
      injectJs: this.getStringValue(rs, 'injectJs'),
      lastUpdateTime: this.getLongValue(rs, 'lastUpdateTime', 0),
      customOrder: this.getLongValue(rs, 'customOrder', 0),
      etag: this.getStringValue(rs, 'etag'),
      lastModified: this.getStringValue(rs, 'lastModified'),
      lastCheckTime: this.getLongValue(rs, 'lastCheckTime', 0),
      lastSuccessTime: this.getLongValue(rs, 'lastSuccessTime', 0),
      lastError: this.getStringValue(rs, 'lastError'),
      iconUrl: this.getStringValue(rs, 'iconUrl'),
      groupName: this.getStringValue(rs, 'groupName'),
      createTime: this.getLongValue(rs, 'createTime', 0),
      updateTime: this.getLongValue(rs, 'updateTime', 0)
    } as RssSubscriptionSource;
  }

  private toItemFromRow(rs: relationalStore.ResultSet): RssFeedItem {
    const readFlag = this.getLongValue(
      rs,
      'computedIsRead',
      this.getLongValue(rs, 'isRead', 0)
    ) === 1;
    const starFlag = this.getLongValue(
      rs,
      'computedIsStarred',
      this.getLongValue(rs, 'isStarred', 0)
    ) === 1;

    return {
      id: this.getStringValue(rs, 'id'),
      sourceId: this.getStringValue(rs, 'sourceId'),
      sourceName: this.getStringValue(rs, 'sourceName'),
      title: this.getStringValue(rs, 'title'),
      link: this.getStringValue(rs, 'link'),
      description: this.getStringValue(rs, 'description'),
      content: this.getStringValue(rs, 'content'),
      author: this.getStringValue(rs, 'author'),
      category: this.getStringValue(rs, 'category'),
      guid: this.getStringValue(rs, 'guid'),
      pubDate: this.getLongValue(rs, 'pubDate', 0),
      isRead: readFlag,
      isStarred: starFlag,
      createTime: this.getLongValue(rs, 'createTime', 0),
      updateTime: this.getLongValue(rs, 'updateTime', 0)
    };
  }

  private pickStringValue(value: string | undefined, fallback: string): string {
    if (value === undefined || value === null) {
      return fallback;
    }
    return value.trim();
  }

  private pickBooleanValue(value: boolean | undefined, fallback: boolean): boolean {
    if (value === undefined || value === null) {
      return fallback;
    }
    return value;
  }

  private pickNumberValue(value: number | undefined, fallback: number, min: number = 0): number {
    if (value === undefined || value === null || Number.isNaN(value) || !Number.isFinite(value)) {
      return fallback;
    }
    const integer = Math.floor(value);
    if (integer < min) {
      return min;
    }
    return integer;
  }

  async getSourceById(sourceId: string): Promise<RssSubscriptionSource | null> {
    const store = this.getStore();
    const rs = await store.querySql(
      `SELECT ${RSS_SOURCE_SELECT_COLUMNS} FROM rss_subscription_source WHERE id = ? LIMIT 1`,
      [sourceId]
    );
    if (!rs.goToFirstRow()) {
      rs.close();
      return null;
    }
    const source = this.toSourceFromRow(rs);
    rs.close();
    return source;
  }

  async getSourceByUrl(url: string): Promise<RssSubscriptionSource | null> {
    const store = this.getStore();
    const rs = await store.querySql(
      `SELECT ${RSS_SOURCE_SELECT_COLUMNS} FROM rss_subscription_source WHERE url = ? LIMIT 1`,
      [url]
    );
    if (!rs.goToFirstRow()) {
      rs.close();
      return null;
    }
    const source = this.toSourceFromRow(rs);
    rs.close();
    return source;
  }

  async getMaxSourceOrder(): Promise<number> {
    const store = this.getStore();
    const rs = await store.querySql('SELECT COALESCE(MAX(customOrder), 0) AS maxOrder FROM rss_subscription_source');
    let maxOrder = 0;
    if (rs.goToFirstRow()) {
      maxOrder = rs.getLong(0);
    }
    rs.close();
    return maxOrder;
  }

  async saveSource(source: RssSubscriptionSource): Promise<RssSubscriptionSource> {
    const store = this.getStore();
    const now = Date.now();
    const existing = source.id ? await this.getSourceById(source.id) : await this.getSourceByUrl(source.url);
    const id = source.id || existing?.id || this.generateId();
    const createTime = existing?.createTime || source.createTime || now;
    const maxOrder = await this.getMaxSourceOrder();
    const customOrder = source.customOrder > 0 ? source.customOrder : (existing?.customOrder || maxOrder + 1);
    const updateIntervalMin = this.pickNumberValue(
      source.updateIntervalMin,
      existing?.updateIntervalMin || 180,
      1
    );
    const articleStyle = this.pickNumberValue(source.articleStyle, existing?.articleStyle || 0, 0);

    await store.executeSql(
      `INSERT OR REPLACE INTO rss_subscription_source
      (id, name, url, sourceComment, enabled, autoUpdate, updateIntervalMin, variableComment, jsLib,
       enabledCookieJar, concurrentRate, header, loginUrl, loginUi, loginCheckJs, coverDecodeJs, sortUrl,
       singleUrl, articleStyle, ruleArticles, ruleNextPage, ruleTitle, rulePubDate, ruleDescription,
       ruleImage, ruleLink, ruleContent, contentWhitelist, contentBlacklist, shouldOverrideUrlLoading,
       style, enableJs, loadWithBaseUrl, injectJs, lastUpdateTime, customOrder, etag, lastModified,
       lastCheckTime, lastSuccessTime, lastError, iconUrl, groupName, createTime, updateTime)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        id,
        this.pickStringValue(source.name, existing?.name || ''),
        this.pickStringValue(source.url, existing?.url || ''),
        this.pickStringValue(source.sourceComment, existing?.sourceComment || ''),
        this.pickBooleanValue(source.enabled, existing?.enabled !== undefined ? existing.enabled : true) ? 1 : 0,
        this.pickBooleanValue(source.autoUpdate, existing?.autoUpdate !== undefined ? existing.autoUpdate : true) ? 1 : 0,
        updateIntervalMin,
        this.pickStringValue(source.variableComment, existing?.variableComment || ''),
        this.pickStringValue(source.jsLib, existing?.jsLib || ''),
        this.pickBooleanValue(
          source.enabledCookieJar,
          existing?.enabledCookieJar !== undefined ? existing.enabledCookieJar : true
        ) ? 1 : 0,
        this.pickStringValue(source.concurrentRate, existing?.concurrentRate || ''),
        this.pickStringValue(source.header, existing?.header || ''),
        this.pickStringValue(source.loginUrl, existing?.loginUrl || ''),
        this.pickStringValue(source.loginUi, existing?.loginUi || ''),
        this.pickStringValue(source.loginCheckJs, existing?.loginCheckJs || ''),
        this.pickStringValue(source.coverDecodeJs, existing?.coverDecodeJs || ''),
        this.pickStringValue(source.sortUrl, existing?.sortUrl || ''),
        this.pickBooleanValue(source.singleUrl, existing?.singleUrl !== undefined ? existing.singleUrl : false) ? 1 : 0,
        articleStyle,
        this.pickStringValue(source.ruleArticles, existing?.ruleArticles || ''),
        this.pickStringValue(source.ruleNextPage, existing?.ruleNextPage || ''),
        this.pickStringValue(source.ruleTitle, existing?.ruleTitle || ''),
        this.pickStringValue(source.rulePubDate, existing?.rulePubDate || ''),
        this.pickStringValue(source.ruleDescription, existing?.ruleDescription || ''),
        this.pickStringValue(source.ruleImage, existing?.ruleImage || ''),
        this.pickStringValue(source.ruleLink, existing?.ruleLink || ''),
        this.pickStringValue(source.ruleContent, existing?.ruleContent || ''),
        this.pickStringValue(source.contentWhitelist, existing?.contentWhitelist || ''),
        this.pickStringValue(source.contentBlacklist, existing?.contentBlacklist || ''),
        this.pickStringValue(source.shouldOverrideUrlLoading, existing?.shouldOverrideUrlLoading || ''),
        this.pickStringValue(source.style, existing?.style || ''),
        this.pickBooleanValue(source.enableJs, existing?.enableJs !== undefined ? existing.enableJs : true) ? 1 : 0,
        this.pickBooleanValue(
          source.loadWithBaseUrl,
          existing?.loadWithBaseUrl !== undefined ? existing.loadWithBaseUrl : true
        ) ? 1 : 0,
        this.pickStringValue(source.injectJs, existing?.injectJs || ''),
        this.pickNumberValue(source.lastUpdateTime, existing?.lastUpdateTime || 0),
        customOrder,
        this.pickStringValue(source.etag, existing?.etag || ''),
        this.pickStringValue(source.lastModified, existing?.lastModified || ''),
        this.pickNumberValue(source.lastCheckTime, existing?.lastCheckTime || 0),
        this.pickNumberValue(source.lastSuccessTime, existing?.lastSuccessTime || 0),
        this.pickStringValue(source.lastError, existing?.lastError || ''),
        this.pickStringValue(source.iconUrl, existing?.iconUrl || ''),
        this.pickStringValue(source.groupName, existing?.groupName || ''),
        createTime,
        now
      ]
    );

    const saved = await this.getSourceById(id);
    if (!saved) {
      throw new Error('保存订阅源失败');
    }
    logger.info(TAG, `保存订阅源成功: ${saved.name}`);
    return saved;
  }

  async updateSourceBasic(
    sourceId: string,
    name: string,
    url: string,
    groupName: string,
    autoUpdate: boolean,
    updateIntervalMin: number,
    iconUrl: string
  ): Promise<void> {
    const current = await this.getSourceById(sourceId);
    if (!current) {
      throw new Error('订阅源不存在');
    }
    const now = Date.now();
    const next: RssSubscriptionSource = {
      id: current.id,
      name: name.trim(),
      url: url.trim(),
      sourceComment: current.sourceComment || '',
      enabled: current.enabled,
      autoUpdate,
      updateIntervalMin: updateIntervalMin > 0 ? updateIntervalMin : 180,
      variableComment: current.variableComment || '',
      jsLib: current.jsLib || '',
      enabledCookieJar: current.enabledCookieJar,
      concurrentRate: current.concurrentRate || '',
      header: current.header || '',
      loginUrl: current.loginUrl || '',
      loginUi: current.loginUi || '',
      loginCheckJs: current.loginCheckJs || '',
      coverDecodeJs: current.coverDecodeJs || '',
      sortUrl: current.sortUrl || '',
      singleUrl: current.singleUrl,
      articleStyle: current.articleStyle,
      ruleArticles: current.ruleArticles || '',
      ruleNextPage: current.ruleNextPage || '',
      ruleTitle: current.ruleTitle || '',
      rulePubDate: current.rulePubDate || '',
      ruleDescription: current.ruleDescription || '',
      ruleImage: current.ruleImage || '',
      ruleLink: current.ruleLink || '',
      ruleContent: current.ruleContent || '',
      contentWhitelist: current.contentWhitelist || '',
      contentBlacklist: current.contentBlacklist || '',
      shouldOverrideUrlLoading: current.shouldOverrideUrlLoading || '',
      style: current.style || '',
      enableJs: current.enableJs,
      loadWithBaseUrl: current.loadWithBaseUrl,
      injectJs: current.injectJs || '',
      lastUpdateTime: current.lastUpdateTime,
      customOrder: current.customOrder,
      etag: current.etag || '',
      lastModified: current.lastModified || '',
      lastCheckTime: current.lastCheckTime,
      lastSuccessTime: current.lastSuccessTime,
      lastError: current.lastError || '',
      iconUrl: iconUrl.trim(),
      groupName: groupName.trim(),
      createTime: current.createTime,
      updateTime: now
    };
    await this.saveSource(next);
  }

  async updateSourceFetchMeta(sourceId: string, meta: RssSourceFetchMeta): Promise<void> {
    const store = this.getStore();
    await store.executeSql(
      `UPDATE rss_subscription_source
      SET etag = ?, lastModified = ?, lastCheckTime = ?, lastSuccessTime = ?, lastError = ?, updateTime = ?
      WHERE id = ?`,
      [
        meta.etag,
        meta.lastModified,
        meta.lastCheckTime,
        meta.lastSuccessTime,
        meta.lastError,
        Date.now(),
        sourceId
      ]
    );
  }

  async setSourceEnabled(sourceId: string, enabled: boolean): Promise<void> {
    const store = this.getStore();
    await store.executeSql(
      'UPDATE rss_subscription_source SET enabled = ?, updateTime = ? WHERE id = ?',
      [enabled ? 1 : 0, Date.now(), sourceId]
    );
  }

  async saveSourceOrder(sourceId: string, customOrder: number): Promise<void> {
    const store = this.getStore();
    await store.executeSql(
      'UPDATE rss_subscription_source SET customOrder = ?, updateTime = ? WHERE id = ?',
      [customOrder, Date.now(), sourceId]
    );
  }

  async getAllSources(orderByEnabled: boolean = false): Promise<RssSubscriptionSource[]> {
    const store = this.getStore();
    const orderSql = orderByEnabled
      ? 'ORDER BY enabled DESC, customOrder ASC, createTime ASC'
      : 'ORDER BY customOrder ASC, createTime ASC';
    const rs = await store.querySql(`SELECT ${RSS_SOURCE_SELECT_COLUMNS} FROM rss_subscription_source ${orderSql}`);
    const list: RssSubscriptionSource[] = [];
    if (rs.goToFirstRow()) {
      do {
        list.push(this.toSourceFromRow(rs));
      } while (rs.goToNextRow());
    }
    rs.close();
    return list;
  }

  async getEnabledSources(): Promise<RssSubscriptionSource[]> {
    const store = this.getStore();
    const rs = await store.querySql(
      `SELECT ${RSS_SOURCE_SELECT_COLUMNS}
       FROM rss_subscription_source
       WHERE enabled = 1
       ORDER BY customOrder ASC, createTime ASC`
    );
    const list: RssSubscriptionSource[] = [];
    if (rs.goToFirstRow()) {
      do {
        list.push(this.toSourceFromRow(rs));
      } while (rs.goToNextRow());
    }
    rs.close();
    return list;
  }

  async deleteSource(sourceId: string): Promise<void> {
    const store = this.getStore();
    logger.info(TAG, `删除订阅源及条目: sourceId=${sourceId}`);
    await store.executeSql('DELETE FROM rss_subscription_read_record WHERE sourceId = ?', [sourceId]);
    await store.executeSql('DELETE FROM rss_subscription_star WHERE sourceId = ?', [sourceId]);
    await store.executeSql('DELETE FROM rss_subscription_item WHERE sourceId = ?', [sourceId]);
    await store.executeSql('DELETE FROM rss_subscription_source WHERE id = ?', [sourceId]);
  }

  private normalizeItemLink(link: string, guid?: string): string {
    const normalizedLink = link.trim();
    if (normalizedLink.length > 0) {
      return normalizedLink;
    }
    if (guid) {
      return guid.trim();
    }
    return '';
  }

  async upsertFeedItems(source: RssSubscriptionSource, items: RssFeedItem[]): Promise<number> {
    if (items.length === 0) {
      logger.debug(TAG, `订阅源无可写入条目: ${source.name}`);
      return 0;
    }

    const store = this.getStore();
    const existingMap: Map<string, ExistingRssItem> = new Map();
    const existingRs = await store.querySql(
      'SELECT id, link FROM rss_subscription_item WHERE sourceId = ?',
      [source.id]
    );
    if (existingRs.goToFirstRow()) {
      do {
        const link = existingRs.getString(existingRs.getColumnIndex('link'));
        if (link.length > 0) {
          existingMap.set(link, {
            id: existingRs.getString(existingRs.getColumnIndex('id')),
            link
          } as ExistingRssItem);
        }
      } while (existingRs.goToNextRow());
    }
    existingRs.close();

    let insertedCount = 0;
    const now = Date.now();
    const seenLinks: Set<string> = new Set();
    for (const item of items) {
      const normalizedLink = this.normalizeItemLink(item.link, item.guid);
      if (normalizedLink.length === 0) {
        continue;
      }
      if (seenLinks.has(normalizedLink)) {
        continue;
      }
      seenLinks.add(normalizedLink);
      const existing = existingMap.get(normalizedLink);
      const pubDate = item.pubDate > 0 ? item.pubDate : now;
      const title = item.title.trim().length > 0 ? item.title.trim() : normalizedLink;
      const guid = item.guid || '';
      const description = item.description || '';
      const content = item.content || '';
      const author = item.author || '';
      const category = item.category || '';

      if (existing) {
        await store.executeSql(
          `UPDATE rss_subscription_item
          SET sourceName = ?, title = ?, description = ?, content = ?, author = ?, category = ?, guid = ?, pubDate = ?, updateTime = ?
          WHERE id = ?`,
          [
            source.name,
            title,
            description,
            content,
            author,
            category,
            guid,
            pubDate,
            now,
            existing.id
          ]
        );
      } else {
        const itemId = item.id || this.generateId();
        await store.executeSql(
          `INSERT OR IGNORE INTO rss_subscription_item
          (id, sourceId, sourceName, title, link, description, content, author, category, guid, pubDate, isRead, isStarred, createTime, updateTime)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
          [
            itemId,
            source.id,
            source.name,
            title,
            normalizedLink,
            description,
            content,
            author,
            category,
            guid,
            pubDate,
            item.isRead ? 1 : 0,
            item.isStarred ? 1 : 0,
            now,
            now
          ]
        );
        insertedCount++;
      }
    }
    logger.info(TAG, `写入订阅条目完成: ${source.name}, 总条目=${items.length}, 新增=${insertedCount}`);
    return insertedCount;
  }

  async trimItemsForSource(sourceId: string, maxItems: number = 600): Promise<void> {
    if (maxItems <= 0) {
      return;
    }
    const store = this.getStore();
    const rs = await store.querySql(
      `SELECT id FROM rss_subscription_item
       WHERE sourceId = ?
       ORDER BY pubDate DESC, createTime DESC
       LIMIT -1 OFFSET ?`,
      [sourceId, maxItems]
    );
    const toDelete: string[] = [];
    if (rs.goToFirstRow()) {
      do {
        toDelete.push(rs.getString(0));
      } while (rs.goToNextRow());
    }
    rs.close();

    for (const id of toDelete) {
      await store.executeSql('DELETE FROM rss_subscription_read_record WHERE itemId = ?', [id]);
      await store.executeSql('DELETE FROM rss_subscription_star WHERE itemId = ?', [id]);
      await store.executeSql('DELETE FROM rss_subscription_item WHERE id = ?', [id]);
    }
    if (toDelete.length > 0) {
      logger.info(TAG, `清理旧订阅条目完成: sourceId=${sourceId}, 删除=${toDelete.length}`);
    }
  }

  async queryItems(options?: RssItemQueryOptions): Promise<RssFeedItem[]> {
    const store = this.getStore();
    const conditions: string[] = ['1=1'];
    const args: (string | number)[] = [];
    if (options?.sourceId && options.sourceId.length > 0) {
      conditions.push('i.sourceId = ?');
      args.push(options.sourceId);
    }
    if (options?.unreadOnly) {
      conditions.push('(rr.itemId IS NULL AND i.isRead = 0)');
    }
    if (options?.starredOnly) {
      conditions.push('(st.itemId IS NOT NULL OR i.isStarred = 1)');
    }
    const limit = options?.limit && options.limit > 0 ? options.limit : 300;
    args.push(limit);

    const rs = await store.querySql(
      `SELECT ${RSS_ITEM_SELECT_COLUMNS},
        CASE WHEN rr.itemId IS NOT NULL OR i.isRead = 1 THEN 1 ELSE 0 END AS computedIsRead,
        CASE WHEN st.itemId IS NOT NULL OR i.isStarred = 1 THEN 1 ELSE 0 END AS computedIsStarred
       FROM rss_subscription_item i
       LEFT JOIN rss_subscription_read_record rr ON rr.itemId = i.id
       LEFT JOIN rss_subscription_star st ON st.itemId = i.id
       WHERE ${conditions.join(' AND ')}
       ORDER BY i.pubDate DESC, i.createTime DESC
       LIMIT ?`,
      args
    );

    const list: RssFeedItem[] = [];
    if (rs.goToFirstRow()) {
      do {
        list.push(this.toItemFromRow(rs));
      } while (rs.goToNextRow());
    }
    rs.close();
    return list;
  }

  async getItemById(itemId: string): Promise<RssFeedItem | null> {
    const store = this.getStore();
    const rs = await store.querySql(
      `SELECT ${RSS_ITEM_SELECT_COLUMNS},
        CASE WHEN rr.itemId IS NOT NULL OR i.isRead = 1 THEN 1 ELSE 0 END AS computedIsRead,
        CASE WHEN st.itemId IS NOT NULL OR i.isStarred = 1 THEN 1 ELSE 0 END AS computedIsStarred
       FROM rss_subscription_item i
       LEFT JOIN rss_subscription_read_record rr ON rr.itemId = i.id
       LEFT JOIN rss_subscription_star st ON st.itemId = i.id
       WHERE i.id = ?
       LIMIT 1`,
      [itemId]
    );

    if (!rs.goToFirstRow()) {
      rs.close();
      return null;
    }
    const item = this.toItemFromRow(rs);
    rs.close();
    return item;
  }

  async updateItemContent(itemId: string, content: string, description: string = ''): Promise<void> {
    const store = this.getStore();
    const normalizedContent = content.trim();
    const normalizedDescription = description.trim();
    await store.executeSql(
      `UPDATE rss_subscription_item
       SET content = ?, description = CASE WHEN ? <> '' THEN ? ELSE description END, updateTime = ?
       WHERE id = ?`,
      [normalizedContent, normalizedDescription, normalizedDescription, Date.now(), itemId]
    );
    logger.info(TAG, `更新订阅条目正文完成: itemId=${itemId}, contentLen=${normalizedContent.length}`);
  }

  async getUnreadCount(sourceId?: string): Promise<number> {
    const store = this.getStore();
    if (sourceId && sourceId.length > 0) {
      const rs = await store.querySql(
        `SELECT COUNT(1)
         FROM rss_subscription_item i
         LEFT JOIN rss_subscription_read_record rr ON rr.itemId = i.id
         WHERE i.sourceId = ? AND rr.itemId IS NULL AND i.isRead = 0`,
        [sourceId]
      );
      let count = 0;
      if (rs.goToFirstRow()) {
        count = rs.getLong(0);
      }
      rs.close();
      return count;
    }

    const rs = await store.querySql(
      `SELECT COUNT(1)
       FROM rss_subscription_item i
       LEFT JOIN rss_subscription_read_record rr ON rr.itemId = i.id
       WHERE rr.itemId IS NULL AND i.isRead = 0`
    );
    let count = 0;
    if (rs.goToFirstRow()) {
      count = rs.getLong(0);
    }
    rs.close();
    return count;
  }

  private async getSourceIdByItemId(itemId: string): Promise<string> {
    const store = this.getStore();
    const rs = await store.querySql(
      'SELECT sourceId FROM rss_subscription_item WHERE id = ? LIMIT 1',
      [itemId]
    );
    let sourceId = '';
    if (rs.goToFirstRow()) {
      sourceId = rs.getString(0);
    }
    rs.close();
    return sourceId;
  }

  async setItemRead(itemId: string, isRead: boolean): Promise<void> {
    const store = this.getStore();
    const sourceId = await this.getSourceIdByItemId(itemId);
    if (sourceId.length === 0) {
      logger.warn(TAG, `设置已读状态失败，条目不存在: itemId=${itemId}`);
      return;
    }
    const now = Date.now();
    if (isRead) {
      await store.executeSql(
        'INSERT OR REPLACE INTO rss_subscription_read_record (itemId, sourceId, readTime) VALUES (?, ?, ?)',
        [itemId, sourceId, now]
      );
    } else {
      await store.executeSql('DELETE FROM rss_subscription_read_record WHERE itemId = ?', [itemId]);
    }
    await store.executeSql(
      'UPDATE rss_subscription_item SET isRead = ?, updateTime = ? WHERE id = ?',
      [isRead ? 1 : 0, now, itemId]
    );
    logger.info(TAG, `设置条目已读状态完成: itemId=${itemId}, isRead=${isRead}`);
  }

  async setItemStarred(itemId: string, isStarred: boolean): Promise<void> {
    const store = this.getStore();
    const sourceId = await this.getSourceIdByItemId(itemId);
    if (sourceId.length === 0) {
      logger.warn(TAG, `设置收藏状态失败，条目不存在: itemId=${itemId}`);
      return;
    }
    const now = Date.now();
    if (isStarred) {
      await store.executeSql(
        'INSERT OR REPLACE INTO rss_subscription_star (itemId, sourceId, starTime) VALUES (?, ?, ?)',
        [itemId, sourceId, now]
      );
    } else {
      await store.executeSql('DELETE FROM rss_subscription_star WHERE itemId = ?', [itemId]);
    }
    await store.executeSql(
      'UPDATE rss_subscription_item SET isStarred = ?, updateTime = ? WHERE id = ?',
      [isStarred ? 1 : 0, now, itemId]
    );
    logger.info(TAG, `设置条目收藏状态完成: itemId=${itemId}, isStarred=${isStarred}`);
  }

  async markAllRead(sourceId?: string): Promise<void> {
    const store = this.getStore();
    const now = Date.now();
    if (sourceId && sourceId.length > 0) {
      await store.executeSql(
        `INSERT OR IGNORE INTO rss_subscription_read_record (itemId, sourceId, readTime)
         SELECT id, sourceId, ? FROM rss_subscription_item WHERE sourceId = ?`,
        [now, sourceId]
      );
      await store.executeSql(
        'UPDATE rss_subscription_item SET isRead = 1, updateTime = ? WHERE sourceId = ?',
        [now, sourceId]
      );
      logger.info(TAG, `按来源标记全部已读完成: sourceId=${sourceId}`);
      return;
    }

    await store.executeSql(
      `INSERT OR IGNORE INTO rss_subscription_read_record (itemId, sourceId, readTime)
       SELECT id, sourceId, ? FROM rss_subscription_item`,
      [now]
    );
    await store.executeSql(
      'UPDATE rss_subscription_item SET isRead = 1, updateTime = ?',
      [now]
    );
    logger.info(TAG, '已标记全部订阅条目为已读');
  }

  async clearReadItems(sourceId?: string): Promise<number> {
    const store = this.getStore();
    if (sourceId && sourceId.length > 0) {
      const scopedReadCondition = 'i.sourceId = ? AND (rr.itemId IS NOT NULL OR i.isRead = 1)';
      const countRs = await store.querySql(
        `SELECT COUNT(1)
         FROM rss_subscription_item i
         LEFT JOIN rss_subscription_read_record rr ON rr.itemId = i.id
         WHERE ${scopedReadCondition}`,
        [sourceId]
      );
      let deleteCount = 0;
      if (countRs.goToFirstRow()) {
        deleteCount = countRs.getLong(0);
      }
      countRs.close();

      if (deleteCount <= 0) {
        logger.info(TAG, `按来源清理已读条目完成：无需删除 sourceId=${sourceId}`);
        return 0;
      }

      await store.executeSql(
        `DELETE FROM rss_subscription_star
         WHERE itemId IN (
           SELECT i.id
           FROM rss_subscription_item i
           LEFT JOIN rss_subscription_read_record rr ON rr.itemId = i.id
           WHERE ${scopedReadCondition}
         )`,
        [sourceId]
      );
      await store.executeSql(
        `DELETE FROM rss_subscription_read_record
         WHERE itemId IN (
           SELECT i.id
           FROM rss_subscription_item i
           LEFT JOIN rss_subscription_read_record rr ON rr.itemId = i.id
           WHERE ${scopedReadCondition}
         )`,
        [sourceId]
      );
      await store.executeSql(
        `DELETE FROM rss_subscription_item
         WHERE id IN (
           SELECT i.id
           FROM rss_subscription_item i
           LEFT JOIN rss_subscription_read_record rr ON rr.itemId = i.id
           WHERE ${scopedReadCondition}
         )`,
        [sourceId]
      );

      logger.info(TAG, `按来源清理已读条目完成：sourceId=${sourceId}, 删除=${deleteCount}`);
      return deleteCount;
    }

    const globalReadCondition = 'rr.itemId IS NOT NULL OR i.isRead = 1';
    const countRs = await store.querySql(
      `SELECT COUNT(1)
       FROM rss_subscription_item i
       LEFT JOIN rss_subscription_read_record rr ON rr.itemId = i.id
       WHERE ${globalReadCondition}`
    );
    let deleteCount = 0;
    if (countRs.goToFirstRow()) {
      deleteCount = countRs.getLong(0);
    }
    countRs.close();

    if (deleteCount <= 0) {
      logger.info(TAG, '全部清理已读条目完成：无需删除');
      return 0;
    }

    await store.executeSql(
      `DELETE FROM rss_subscription_star
       WHERE itemId IN (
         SELECT i.id
         FROM rss_subscription_item i
         LEFT JOIN rss_subscription_read_record rr ON rr.itemId = i.id
         WHERE ${globalReadCondition}
       )`
    );
    await store.executeSql(
      `DELETE FROM rss_subscription_read_record
       WHERE itemId IN (
         SELECT i.id
         FROM rss_subscription_item i
         LEFT JOIN rss_subscription_read_record rr ON rr.itemId = i.id
         WHERE ${globalReadCondition}
       )`
    );
    await store.executeSql(
      `DELETE FROM rss_subscription_item
       WHERE id IN (
         SELECT i.id
         FROM rss_subscription_item i
         LEFT JOIN rss_subscription_read_record rr ON rr.itemId = i.id
         WHERE ${globalReadCondition}
       )`
    );

    logger.info(TAG, `全部清理已读条目完成：删除=${deleteCount}`);
    return deleteCount;
  }
}

export function getRssSubscriptionDataManager(): RssSubscriptionDataManager {
  return RssSubscriptionDataManager.getInstance();
}
