import { SafeUtils } from 'manxia_core/src/main/ets/Utils/SafeUtils';
import { common } from '@kit.AbilityKit';
import { http } from '@kit.NetworkKit';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import {
  RssFeedFormat,
  RssFeedItem,
  RssFetchResult,
  RssRefreshProgress,
  RssSubscriptionSource
} from 'manxia_core/src/main/ets/Models/RssSubscriptionModels';
import {
  getRssSubscriptionDataManager,
  RssItemQueryOptions,
  RssSourceFetchMeta,
  RssSubscriptionDataManager
} from 'manxia_novel/src/main/ets/Framework/Rss/RssSubscriptionDataManager';
import { ParsedRssFeed, RssFeedParser } from './RssFeedParser';
import { LegadoRuleAnalyzer } from '../Novel/LegadoRuleAnalyzer';
import { LegadoUrlAnalyzer, ParsedUrlRequest, RequestMethod } from '../Novel/LegadoUrlAnalyzer';

const TAG = 'RssSubscriptionManager';
const DEFAULT_TIMEOUT = 15000;
const URL_IMPORT_TIMEOUT = 20000;
const MAX_IMPORT_SOURCE_URL_DEPTH = 4;
const MAX_CONTENT_PAGE_COUNT = 5;
const LOGIN_CACHE_DURATION_MS = 30 * 60 * 1000;
const AUTO_DUE_REFRESH_INTERVAL_MS = 5 * 60 * 1000;

interface HeaderEntry {
  key: string;
  value: string;
}

interface RssImportRequestHeader {
  'Accept': string;
  'Cache-Control': string;
  'User-Agent': string;
}

interface ImportUrlRequestOption {
  url: string;
  requestWithoutUA: boolean;
}

interface ParsedItemContent {
  content: string;
  description: string;
}

interface ParsedPageContent {
  content: string;
  description: string;
  nextPageUrl: string;
}

interface ResolvedSourceRequestOption {
  requestUrl: string;
  requestMethod: http.RequestMethod;
  requestBody: string;
  headerEntries: HeaderEntry[];
}

interface ResolvedImportSourceUrl {
  selectedUrl: string;
  selectedFrom: string;
  rawUrl: string;
  rawFeedUrl: string;
  rawSourceUrl: string;
  rawSortUrl: string;
  rawSearchUrl: string;
}

type RssErrorValue = Object | string | number | boolean | null | undefined;

export interface RssSourceUpdatePayload {
  name?: string;
  url?: string;
  sourceComment?: string;
  groupName?: string;
  autoUpdate?: boolean;
  updateIntervalMin?: number;
  iconUrl?: string;
  enabled?: boolean;
  variableComment?: string;
  jsLib?: string;
  enabledCookieJar?: boolean;
  concurrentRate?: string;
  header?: string;
  loginUrl?: string;
  loginUi?: string;
  loginCheckJs?: string;
  coverDecodeJs?: string;
  sortUrl?: string;
  singleUrl?: boolean;
  articleStyle?: number;
  ruleArticles?: string;
  ruleNextPage?: string;
  ruleTitle?: string;
  rulePubDate?: string;
  ruleDescription?: string;
  ruleImage?: string;
  ruleLink?: string;
  ruleContent?: string;
  contentWhitelist?: string;
  contentBlacklist?: string;
  shouldOverrideUrlLoading?: string;
  style?: string;
  enableJs?: boolean;
  loadWithBaseUrl?: boolean;
  injectJs?: string;
  lastUpdateTime?: number;
  customOrder?: number;
}

export interface RssImportResult {
  total: number;
  success: number;
  failed: number;
  skipped: number;
  created: number;
  updated: number;
  errors: string[];
}

export type RssImportConflictPolicy = 'overwrite' | 'skip';

export interface RssRulePreviewItem {
  title: string;
  link: string;
  pubDate: number;
  description: string;
}

export interface RssRulePreviewResult {
  sourceId: string;
  sourceName: string;
  requestUrl: string;
  total: number;
  fetchedAt: number;
  warning: string;
  items: RssRulePreviewItem[];
}

export interface RssItemContentRefreshResult {
  success: boolean;
  itemId: string;
  sourceId: string;
  content: string;
  description: string;
  fetchedAt: number;
  error?: string;
}

export class RssSubscriptionManager {
  private static instance: RssSubscriptionManager | null = null;
  private readonly dataManager: RssSubscriptionDataManager = getRssSubscriptionDataManager();
  private readonly parser: RssFeedParser = new RssFeedParser();
  private isInitialized: boolean = false;
  private readonly sourceCookieJar: Map<string, string> = new Map();
  private readonly sourceLastLoginTime: Map<string, number> = new Map();
  private autoDueRefreshRunning: boolean = false;
  private lastAutoDueRefreshAt: number = 0;

  private constructor() {
  }

  static getInstance(): RssSubscriptionManager {
    if (!RssSubscriptionManager.instance) {
      RssSubscriptionManager.instance = new RssSubscriptionManager();
    }
    return RssSubscriptionManager.instance;
  }

  async initialize(context: common.UIAbilityContext): Promise<void> {
    if (this.isInitialized) {
      logger.debug(TAG, '订阅源管理器已初始化，跳过重复初始化');
      return;
    }
    logger.info(TAG, '开始初始化订阅源管理器');
    await this.dataManager.initialize(context);
    this.isInitialized = true;
    logger.info(TAG, '订阅源管理器初始化完成');
  }

  isReady(): boolean {
    return this.isInitialized && this.dataManager.isReady();
  }

  private ensureInitialized(): void {
    if (!this.isReady()) {
      throw new Error('订阅源管理器尚未初始化');
    }
  }

  private normalizeUrl(url: string): string {
    return url.trim();
  }

  private validateUrl(url: string): boolean {
    return /^https?:\/\/.+/i.test(url.trim());
  }

  private normalizeNumber(value: number | undefined, fallback: number, min: number = 0): number {
    if (value === undefined || value === null || Number.isNaN(value) || !Number.isFinite(value)) {
      return fallback;
    }
    const integer = Math.floor(value);
    if (integer < min) {
      return min;
    }
    return integer;
  }

  private normalizeString(value: string | undefined, fallback: string): string {
    if (value === undefined || value === null) {
      return fallback;
    }
    return value.trim();
  }

  private normalizeBoolean(value: boolean | undefined, fallback: boolean): boolean {
    if (value === undefined || value === null) {
      return fallback;
    }
    return value;
  }

  private resolveErrorText(error: RssErrorValue): string {
    if (error === undefined || error === null) {
      return '未知错误';
    }
    if (typeof error === 'string' || typeof error === 'number' || typeof error === 'boolean') {
      return String(error);
    }
    if (error instanceof Error) {
      const message = error.message ? error.message.trim() : '';
      if (message.length > 0) {
        return message;
      }
      return error.name ? error.name : 'Error';
    }

    const objectError = error as Object;
    const message = this.readStringValueByKeys(objectError, ['message', 'msg', 'error', 'detail', 'details', 'description']);
    const code = this.readStringValueByKeys(objectError, ['code', 'statusCode', 'status', 'errno']);
    const name = this.readStringValueByKeys(objectError, ['name']);

    if (message.length > 0 && code.length > 0) {
      return `${message} (code=${code})`;
    }
    if (message.length > 0) {
      return message;
    }
    if (name.length > 0 && code.length > 0) {
      return `${name} (code=${code})`;
    }
    if (code.length > 0) {
      return `错误码 ${code}`;
    }

    try {
      const fallbackJson = JSON.stringify(objectError);
      if (fallbackJson && fallbackJson.length > 0 && fallbackJson !== '{}') {
        return fallbackJson;
      }
    } catch (_error) {
    }
    return String(objectError);
  }

  async getAllSources(forDisplay: boolean = true): Promise<RssSubscriptionSource[]> {
    this.ensureInitialized();
    return this.dataManager.getAllSources(forDisplay);
  }

  async getEnabledSources(): Promise<RssSubscriptionSource[]> {
    this.ensureInitialized();
    return this.dataManager.getEnabledSources();
  }

  async getSourceById(sourceId: string): Promise<RssSubscriptionSource | null> {
    this.ensureInitialized();
    return this.dataManager.getSourceById(sourceId);
  }

  private buildDefaultSource(name: string, url: string, groupName: string, customOrder: number): RssSubscriptionSource {
    const now = Date.now();
    return {
      id: '',
      name: name.trim(),
      url: url.trim(),
      sourceComment: '',
      enabled: true,
      autoUpdate: true,
      updateIntervalMin: 180,
      variableComment: '',
      jsLib: '',
      enabledCookieJar: true,
      concurrentRate: '',
      header: '',
      loginUrl: '',
      loginUi: '',
      loginCheckJs: '',
      coverDecodeJs: '',
      sortUrl: '',
      singleUrl: false,
      articleStyle: 0,
      ruleArticles: '',
      ruleNextPage: '',
      ruleTitle: '',
      rulePubDate: '',
      ruleDescription: '',
      ruleImage: '',
      ruleLink: '',
      ruleContent: '',
      contentWhitelist: '',
      contentBlacklist: '',
      shouldOverrideUrlLoading: '',
      style: '',
      enableJs: true,
      loadWithBaseUrl: true,
      injectJs: '',
      lastUpdateTime: 0,
      customOrder,
      etag: '',
      lastModified: '',
      lastCheckTime: 0,
      lastSuccessTime: 0,
      lastError: '',
      iconUrl: '',
      groupName: groupName.trim(),
      createTime: now,
      updateTime: now
    } as RssSubscriptionSource;
  }

  private copySource(source: RssSubscriptionSource): RssSubscriptionSource {
    return {
      id: source.id,
      name: source.name,
      url: source.url,
      sourceComment: source.sourceComment || '',
      enabled: source.enabled,
      autoUpdate: source.autoUpdate,
      updateIntervalMin: source.updateIntervalMin,
      variableComment: source.variableComment || '',
      jsLib: source.jsLib || '',
      enabledCookieJar: source.enabledCookieJar,
      concurrentRate: source.concurrentRate || '',
      header: source.header || '',
      loginUrl: source.loginUrl || '',
      loginUi: source.loginUi || '',
      loginCheckJs: source.loginCheckJs || '',
      coverDecodeJs: source.coverDecodeJs || '',
      sortUrl: source.sortUrl || '',
      singleUrl: source.singleUrl,
      articleStyle: source.articleStyle,
      ruleArticles: source.ruleArticles || '',
      ruleNextPage: source.ruleNextPage || '',
      ruleTitle: source.ruleTitle || '',
      rulePubDate: source.rulePubDate || '',
      ruleDescription: source.ruleDescription || '',
      ruleImage: source.ruleImage || '',
      ruleLink: source.ruleLink || '',
      ruleContent: source.ruleContent || '',
      contentWhitelist: source.contentWhitelist || '',
      contentBlacklist: source.contentBlacklist || '',
      shouldOverrideUrlLoading: source.shouldOverrideUrlLoading || '',
      style: source.style || '',
      enableJs: source.enableJs,
      loadWithBaseUrl: source.loadWithBaseUrl,
      injectJs: source.injectJs || '',
      lastUpdateTime: source.lastUpdateTime,
      customOrder: source.customOrder,
      etag: source.etag || '',
      lastModified: source.lastModified || '',
      lastCheckTime: source.lastCheckTime,
      lastSuccessTime: source.lastSuccessTime,
      lastError: source.lastError || '',
      iconUrl: source.iconUrl || '',
      groupName: source.groupName || '',
      createTime: source.createTime,
      updateTime: source.updateTime
    } as RssSubscriptionSource;
  }

  async addSource(name: string, url: string, groupName: string = ''): Promise<RssSubscriptionSource> {
    this.ensureInitialized();
    const normalizedUrl = this.normalizeUrl(url);
    if (!this.validateUrl(normalizedUrl)) {
      throw new Error('订阅源 URL 必须以 http:// 或 https:// 开头');
    }
    const trimmedName = name.trim();
    if (trimmedName.length === 0) {
      throw new Error('订阅源名称不能为空');
    }

    logger.info(TAG, `开始新增订阅源: ${trimmedName}`);
    const existing = await this.dataManager.getSourceByUrl(normalizedUrl);
    if (existing) {
      logger.info(TAG, `检测到重复 URL，改为更新已有订阅源: ${existing.name}`);
      const updatedExisting = this.copySource(existing);
      updatedExisting.name = trimmedName;
      updatedExisting.url = normalizedUrl;
      updatedExisting.groupName = groupName.trim().length > 0 ? groupName.trim() : (existing.groupName || '');
      updatedExisting.updateTime = Date.now();
      const updated = await this.dataManager.saveSource(updatedExisting);
      return updated;
    }

    const maxOrder = await this.dataManager.getMaxSourceOrder();
    const source = this.buildDefaultSource(trimmedName, normalizedUrl, groupName, maxOrder + 1);
    const saved = await this.dataManager.saveSource(source);
    logger.info(TAG, `新增订阅源成功: ${saved.name}`);
    return saved;
  }

  async updateSource(sourceId: string, payload: RssSourceUpdatePayload): Promise<RssSubscriptionSource> {
    this.ensureInitialized();
    const current = await this.dataManager.getSourceById(sourceId);
    if (!current) {
      throw new Error('订阅源不存在');
    }

    const nextUrl = payload.url !== undefined ? this.normalizeUrl(payload.url) : current.url;
    if (!this.validateUrl(nextUrl)) {
      throw new Error('订阅源 URL 不合法');
    }
    if (payload.url !== undefined && payload.url.trim().length > 0 && payload.url.trim() !== current.url) {
      const urlConflict = await this.dataManager.getSourceByUrl(nextUrl);
      if (urlConflict && urlConflict.id !== sourceId) {
        throw new Error('该 URL 已存在');
      }
    }

    const nextName = payload.name !== undefined ? payload.name.trim() : current.name;
    if (nextName.length === 0) {
      throw new Error('订阅源名称不能为空');
    }

    logger.info(TAG, `开始更新订阅源: ${current.name}`);
    const next = this.copySource(current);
    next.name = nextName;
    next.url = nextUrl;
    next.sourceComment = this.normalizeString(payload.sourceComment, current.sourceComment || '');
    next.enabled = this.normalizeBoolean(payload.enabled, current.enabled);
    next.autoUpdate = this.normalizeBoolean(payload.autoUpdate, current.autoUpdate);
    next.updateIntervalMin = this.normalizeNumber(payload.updateIntervalMin, current.updateIntervalMin, 1);
    next.variableComment = this.normalizeString(payload.variableComment, current.variableComment || '');
    next.jsLib = this.normalizeString(payload.jsLib, current.jsLib || '');
    next.enabledCookieJar = this.normalizeBoolean(payload.enabledCookieJar, current.enabledCookieJar);
    next.concurrentRate = this.normalizeString(payload.concurrentRate, current.concurrentRate || '');
    next.header = this.normalizeString(payload.header, current.header || '');
    next.loginUrl = this.normalizeString(payload.loginUrl, current.loginUrl || '');
    next.loginUi = this.normalizeString(payload.loginUi, current.loginUi || '');
    next.loginCheckJs = this.normalizeString(payload.loginCheckJs, current.loginCheckJs || '');
    next.coverDecodeJs = this.normalizeString(payload.coverDecodeJs, current.coverDecodeJs || '');
    next.sortUrl = this.normalizeString(payload.sortUrl, current.sortUrl || '');
    next.singleUrl = this.normalizeBoolean(payload.singleUrl, current.singleUrl);
    next.articleStyle = this.normalizeNumber(payload.articleStyle, current.articleStyle, 0);
    next.ruleArticles = this.normalizeString(payload.ruleArticles, current.ruleArticles || '');
    next.ruleNextPage = this.normalizeString(payload.ruleNextPage, current.ruleNextPage || '');
    next.ruleTitle = this.normalizeString(payload.ruleTitle, current.ruleTitle || '');
    next.rulePubDate = this.normalizeString(payload.rulePubDate, current.rulePubDate || '');
    next.ruleDescription = this.normalizeString(payload.ruleDescription, current.ruleDescription || '');
    next.ruleImage = this.normalizeString(payload.ruleImage, current.ruleImage || '');
    next.ruleLink = this.normalizeString(payload.ruleLink, current.ruleLink || '');
    next.ruleContent = this.normalizeString(payload.ruleContent, current.ruleContent || '');
    next.contentWhitelist = this.normalizeString(payload.contentWhitelist, current.contentWhitelist || '');
    next.contentBlacklist = this.normalizeString(payload.contentBlacklist, current.contentBlacklist || '');
    next.shouldOverrideUrlLoading = this.normalizeString(payload.shouldOverrideUrlLoading, current.shouldOverrideUrlLoading || '');
    next.style = this.normalizeString(payload.style, current.style || '');
    next.enableJs = this.normalizeBoolean(payload.enableJs, current.enableJs);
    next.loadWithBaseUrl = this.normalizeBoolean(payload.loadWithBaseUrl, current.loadWithBaseUrl);
    next.injectJs = this.normalizeString(payload.injectJs, current.injectJs || '');
    next.lastUpdateTime = this.normalizeNumber(payload.lastUpdateTime, current.lastUpdateTime, 0);
    next.customOrder = payload.customOrder !== undefined ? this.normalizeNumber(payload.customOrder, current.customOrder, 0) : current.customOrder;
    next.iconUrl = this.normalizeString(payload.iconUrl, current.iconUrl || '');
    next.groupName = this.normalizeString(payload.groupName, current.groupName || '');
    next.updateTime = Date.now();

    const updated = await this.dataManager.saveSource(next);
    logger.info(TAG, `更新订阅源成功: ${updated.name}`);
    return updated;
  }

  async deleteSource(sourceId: string): Promise<void> {
    this.ensureInitialized();
    const source = await this.dataManager.getSourceById(sourceId);
    logger.info(TAG, `删除订阅源: ${source ? source.name : sourceId}`);
    await this.dataManager.deleteSource(sourceId);
  }

  async setSourceEnabled(sourceId: string, enabled: boolean): Promise<void> {
    this.ensureInitialized();
    logger.info(TAG, `设置订阅源启用状态: sourceId=${sourceId}, enabled=${enabled}`);
    await this.dataManager.setSourceEnabled(sourceId, enabled);
  }

  async moveSource(sourceId: string, direction: 'up' | 'down'): Promise<boolean> {
    this.ensureInitialized();
    const sources = await this.dataManager.getAllSources(false);
    const currentIndex = sources.findIndex((source: RssSubscriptionSource) => source.id === sourceId);
    if (currentIndex < 0) {
      logger.warn(TAG, `移动订阅源失败，未找到 sourceId=${sourceId}`);
      return false;
    }

    const targetIndex = direction === 'up' ? currentIndex - 1 : currentIndex + 1;
    if (targetIndex < 0 || targetIndex >= sources.length) {
      return false;
    }

    const current = sources[currentIndex];
    const target = sources[targetIndex];
    await this.dataManager.saveSourceOrder(current.id, target.customOrder);
    await this.dataManager.saveSourceOrder(target.id, current.customOrder);
    logger.info(TAG, `订阅源排序完成: ${current.name} ${direction === 'up' ? '上移' : '下移'}`);
    return true;
  }

  async queryItems(options?: RssItemQueryOptions): Promise<RssFeedItem[]> {
    this.ensureInitialized();
    return this.dataManager.queryItems(options);
  }

  async getItemById(itemId: string): Promise<RssFeedItem | null> {
    this.ensureInitialized();
    return this.dataManager.getItemById(itemId);
  }

  async setItemRead(itemId: string, isRead: boolean): Promise<void> {
    this.ensureInitialized();
    await this.dataManager.setItemRead(itemId, isRead);
  }

  async setItemStarred(itemId: string, isStarred: boolean): Promise<void> {
    this.ensureInitialized();
    await this.dataManager.setItemStarred(itemId, isStarred);
  }

  async markAllRead(sourceId?: string): Promise<void> {
    this.ensureInitialized();
    await this.dataManager.markAllRead(sourceId);
  }

  async clearReadItems(sourceId?: string): Promise<number> {
    this.ensureInitialized();
    const deleted = await this.dataManager.clearReadItems(sourceId);
    logger.info(TAG, `清理已读条目完成: sourceId=${sourceId || 'all'}, 删除=${deleted}`);
    return deleted;
  }

  async getUnreadCount(sourceId?: string): Promise<number> {
    this.ensureInitialized();
    return this.dataManager.getUnreadCount(sourceId);
  }

  private getHeaderIgnoreCase(headersObj: Object, headerName: string): string {
    const entries = Object.entries(headersObj) as [string, Object][];
    const targetName = headerName.toLowerCase();
    for (const entry of entries) {
      if (entry[0].toLowerCase() === targetName) {
        return String(entry[1]);
      }
    }
    return '';
  }

  private upsertHeaderEntry(entries: HeaderEntry[], key: string, value: string): void {
    const normalizedKey = key.trim();
    if (normalizedKey.length === 0) {
      return;
    }
    const normalizedValue = value.trim();
    for (let i = 0; i < entries.length; i++) {
      if (entries[i].key.toLowerCase() === normalizedKey.toLowerCase()) {
        entries[i] = {
          key: entries[i].key,
          value: normalizedValue
        } as HeaderEntry;
        return;
      }
    }
    entries.push({
      key: normalizedKey,
      value: normalizedValue
    } as HeaderEntry);
  }

  private parseSourceHeaderEntries(rawHeader: string): HeaderEntry[] {
    const text = rawHeader.trim();
    if (text.length === 0) {
      return [];
    }

    const parsedEntries: HeaderEntry[] = [];
    if (text.startsWith('{') && text.endsWith('}')) {
      try {
        const headerObj = SafeUtils.parseObj(text) as Object;
        const entries = Object.entries(headerObj) as [string, Object][];
        for (let i = 0; i < entries.length; i++) {
          const key = entries[i][0].trim();
          const value = String(entries[i][1]).trim();
          if (key.length === 0 || value.length === 0) {
            continue;
          }
          this.upsertHeaderEntry(parsedEntries, key, value);
        }
        return parsedEntries;
      } catch (_error) {
        logger.warn(TAG, '订阅源 header 不是合法 JSON，降级按文本头解析');
      }
    }

    const lines = text.split(/\r?\n|&&/g);
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim();
      if (line.length === 0) {
        continue;
      }
      let separatorIndex = line.indexOf(':');
      if (separatorIndex < 0) {
        separatorIndex = line.indexOf('=');
      }
      if (separatorIndex <= 0) {
        continue;
      }
      const key = line.substring(0, separatorIndex).trim();
      const value = line.substring(separatorIndex + 1).trim();
      if (key.length === 0 || value.length === 0) {
        continue;
      }
      this.upsertHeaderEntry(parsedEntries, key, value);
    }
    return parsedEntries;
  }

  private mergeHeaderEntries(baseEntries: HeaderEntry[], overrideEntries: HeaderEntry[]): HeaderEntry[] {
    const merged: HeaderEntry[] = [];
    for (let i = 0; i < baseEntries.length; i++) {
      merged.push({
        key: baseEntries[i].key,
        value: baseEntries[i].value
      } as HeaderEntry);
    }
    for (let i = 0; i < overrideEntries.length; i++) {
      this.upsertHeaderEntry(merged, overrideEntries[i].key, overrideEntries[i].value);
    }
    return merged;
  }

  private escapeJsonText(rawText: string): string {
    return rawText
      .replace(/\\/g, '\\\\')
      .replace(/"/g, '\\"')
      .replace(/\r/g, '\\r')
      .replace(/\n/g, '\\n')
      .replace(/\t/g, '\\t');
  }

  private toHeaderObject(entries: HeaderEntry[]): Object {
    const fragments: string[] = [];
    for (let i = 0; i < entries.length; i++) {
      const key = this.escapeJsonText(entries[i].key);
      const value = this.escapeJsonText(entries[i].value);
      fragments.push(`"${key}":"${value}"`);
    }
    const jsonText = `{${fragments.join(',')}}`;
    try {
      return SafeUtils.parseObj(jsonText) as Object;
    } catch (_error) {
      return SafeUtils.parseObj('{}') as Object;
    }
  }

  private splitSetCookieHeader(rawSetCookie: string): string[] {
    if (rawSetCookie.indexOf('\n') >= 0) {
      return rawSetCookie
        .split(/\r?\n/g)
        .map((line: string) => line.trim())
        .filter((line: string) => line.length > 0);
    }
    return rawSetCookie
      .split(/,(?=\s*[A-Za-z0-9_\-]+=)/g)
      .map((line: string) => line.trim())
      .filter((line: string) => line.length > 0);
  }

  private parseCookiePairs(cookieText: string): HeaderEntry[] {
    const pairs: HeaderEntry[] = [];
    const chunks = cookieText
      .split(';')
      .map((item: string) => item.trim())
      .filter((item: string) => item.length > 0);
    for (let i = 0; i < chunks.length; i++) {
      const chunk = chunks[i];
      const separatorIndex = chunk.indexOf('=');
      if (separatorIndex <= 0) {
        continue;
      }
      const name = chunk.substring(0, separatorIndex).trim();
      const value = chunk.substring(separatorIndex + 1).trim();
      if (name.length === 0) {
        continue;
      }
      this.upsertHeaderEntry(pairs, name, value);
    }
    return pairs;
  }

  private mergeCookieText(existingCookie: string, newCookiePairs: string[]): string {
    const mergedPairs = this.parseCookiePairs(existingCookie);
    for (let i = 0; i < newCookiePairs.length; i++) {
      const pair = newCookiePairs[i];
      const separatorIndex = pair.indexOf('=');
      if (separatorIndex <= 0) {
        continue;
      }
      const name = pair.substring(0, separatorIndex).trim();
      const value = pair.substring(separatorIndex + 1).trim();
      if (name.length === 0) {
        continue;
      }
      this.upsertHeaderEntry(mergedPairs, name, value);
    }
    const parts: string[] = [];
    for (let i = 0; i < mergedPairs.length; i++) {
      parts.push(`${mergedPairs[i].key}=${mergedPairs[i].value}`);
    }
    return parts.join('; ');
  }

  private updateSourceCookieFromResponse(source: RssSubscriptionSource, responseHeaders: Object): void {
    if (!source.enabledCookieJar) {
      return;
    }
    const rawSetCookie = this.getHeaderIgnoreCase(responseHeaders, 'set-cookie').trim();
    if (rawSetCookie.length === 0) {
      return;
    }

    const setCookieLines = this.splitSetCookieHeader(rawSetCookie);
    const cookiePairs: string[] = [];
    for (let i = 0; i < setCookieLines.length; i++) {
      const line = setCookieLines[i];
      const firstToken = line.split(';')[0].trim();
      if (firstToken.length === 0 || firstToken.indexOf('=') <= 0) {
        continue;
      }
      cookiePairs.push(firstToken);
    }
    if (cookiePairs.length === 0) {
      return;
    }

    const existingCookie = this.sourceCookieJar.get(source.id) || '';
    const mergedCookie = this.mergeCookieText(existingCookie, cookiePairs);
    if (mergedCookie.length > 0) {
      this.sourceCookieJar.set(source.id, mergedCookie);
      logger.debug(TAG, `订阅源 CookieJar 已更新: source=${source.name}, cookieLength=${mergedCookie.length}`);
    }
  }

  private evaluateLoginCheck(source: RssSubscriptionSource): boolean {
    const cookieText = this.sourceCookieJar.get(source.id) || '';
    const hasCookie = cookieText.trim().length > 0;
    const checkScript = (source.loginCheckJs || '').trim();
    if (checkScript.length === 0) {
      return hasCookie;
    }

    const lower = checkScript.toLowerCase();
    if (lower === 'true') {
      return true;
    }
    if (lower === 'false') {
      return false;
    }

    const literalMatch = checkScript.match(/['"]([^'"]+)['"]/);
    if (literalMatch && literalMatch[1]) {
      return cookieText.includes(literalMatch[1]);
    }
    return hasCookie;
  }

  private buildSourceRequestHeaderEntries(
    source: RssSubscriptionSource,
    acceptValue: string,
    includeConditionalCache: boolean
  ): HeaderEntry[] {
    const baseEntries: HeaderEntry[] = [
      { key: 'User-Agent', value: 'Mozilla/5.0 (HarmonyOS; RSSSubscription)' } as HeaderEntry,
      { key: 'Accept', value: acceptValue } as HeaderEntry,
      { key: 'Cache-Control', value: 'no-cache' } as HeaderEntry
    ];

    if (includeConditionalCache) {
      if ((source.etag || '').trim().length > 0) {
        baseEntries.push({
          key: 'If-None-Match',
          value: source.etag || ''
        } as HeaderEntry);
      }
      if ((source.lastModified || '').trim().length > 0) {
        baseEntries.push({
          key: 'If-Modified-Since',
          value: source.lastModified || ''
        } as HeaderEntry);
      }
    }

    const sourceHeaderEntries = this.parseSourceHeaderEntries(source.header || '');
    const mergedEntries = this.mergeHeaderEntries(baseEntries, sourceHeaderEntries);
    if (source.enabledCookieJar) {
      const cookieText = this.sourceCookieJar.get(source.id) || '';
      if (cookieText.trim().length > 0) {
        this.upsertHeaderEntry(mergedEntries, 'Cookie', cookieText);
      }
    }
    return mergedEntries;
  }

  private async ensureSourceLogin(source: RssSubscriptionSource): Promise<void> {
    const loginUrlText = (source.loginUrl || '').trim();
    if (loginUrlText.length === 0) {
      return;
    }
    const loginUrl = this.toAbsoluteUrl(source.url, loginUrlText);
    if (!this.validateUrl(loginUrl)) {
      logger.warn(TAG, `订阅源登录地址不合法，跳过登录流程: ${source.name}, loginUrl=${loginUrlText}`);
      return;
    }

    const lastLogin = this.sourceLastLoginTime.get(source.id) || 0;
    const loginValid = source.enabledCookieJar ? this.evaluateLoginCheck(source) : lastLogin > 0;
    const loginNotExpired = lastLogin > 0 && (Date.now() - lastLogin < LOGIN_CACHE_DURATION_MS);
    if (loginValid && loginNotExpired) {
      return;
    }

    let request: http.HttpRequest | null = null;
    try {
      logger.info(TAG, `开始执行订阅源登录请求: source=${source.name}, url=${loginUrl}`);
      const headerEntries = this.buildSourceRequestHeaderEntries(
        source,
        'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        false
      );
      request = http.createHttp();
      const response = await request.request(loginUrl, {
        method: http.RequestMethod.GET,
        header: this.toHeaderObject(headerEntries),
        connectTimeout: DEFAULT_TIMEOUT,
        readTimeout: DEFAULT_TIMEOUT,
        expectDataType: http.HttpDataType.STRING
      });
      const statusCode = response.responseCode;
      const responseHeaders = (response.header || {}) as Object;
      this.updateSourceCookieFromResponse(source, responseHeaders);
      this.sourceLastLoginTime.set(source.id, Date.now());
      if (statusCode < 200 || statusCode >= 400) {
        logger.warn(TAG, `订阅源登录请求返回异常状态码: source=${source.name}, statusCode=${statusCode}`);
      } else {
        logger.info(TAG, `订阅源登录请求完成: source=${source.name}, statusCode=${statusCode}`);
      }
    } catch (error) {
      logger.warn(TAG, `订阅源登录请求失败，继续执行主流程: source=${source.name}, error=${String(error)}`);
    } finally {
      if (request) {
        request.destroy();
      }
    }
  }

  private buildSourceMetaOnSuccess(source: RssSubscriptionSource, etag: string, lastModified: string): RssSourceFetchMeta {
    const now = Date.now();
    return {
      etag,
      lastModified,
      lastCheckTime: now,
      lastSuccessTime: now,
      lastError: ''
    } as RssSourceFetchMeta;
  }

  private buildSourceMetaOnError(source: RssSubscriptionSource, error: string): RssSourceFetchMeta {
    return {
      etag: source.etag || '',
      lastModified: source.lastModified || '',
      lastCheckTime: Date.now(),
      lastSuccessTime: source.lastSuccessTime || 0,
      lastError: error
    } as RssSourceFetchMeta;
  }

  private toAbsoluteUrl(baseUrl: string, urlText: string): string {
    const text = urlText.trim();
    if (text.length === 0) {
      return '';
    }
    if (/^https?:\/\//i.test(text)) {
      return text;
    }
    const base = baseUrl.trim();
    if (!/^https?:\/\//i.test(base)) {
      return text;
    }
    const protocolMatch = base.match(/^(https?:)\/\//i);
    const hostMatch = base.match(/^(https?:\/\/[^/]+)/i);
    const protocol = protocolMatch && protocolMatch[1] ? protocolMatch[1] : 'https:';
    const host = hostMatch && hostMatch[1] ? hostMatch[1] : '';
    if (text.startsWith('//')) {
      return `${protocol}${text}`;
    }
    if (text.startsWith('/')) {
      return `${host}${text}`;
    }
    let baseDir = base;
    if (!base.endsWith('/')) {
      const lastSlash = base.lastIndexOf('/');
      if (host.length > 0 && lastSlash <= host.length - 1) {
        baseDir = `${host}/`;
      } else if (lastSlash > 0) {
        baseDir = base.substring(0, lastSlash + 1);
      } else {
        baseDir = `${host}/`;
      }
    }
    return `${baseDir}${text}`;
  }

  private resolveSourceFetchUrl(source: RssSubscriptionSource): string {
    const hasRuleArticles = source.ruleArticles !== undefined
      && source.ruleArticles !== null
      && source.ruleArticles.trim().length > 0;
    const sortUrl = source.sortUrl ? source.sortUrl.trim() : '';
    if (hasRuleArticles && sortUrl.length > 0) {
      const resolvedSortUrl = this.extractUrlFromSortUrl(sortUrl, source.url, true);
      if (resolvedSortUrl.length > 0) {
        return resolvedSortUrl;
      }
      const absoluteSortUrl = this.toAbsoluteUrl(source.url, sortUrl);
      if (this.validateUrl(absoluteSortUrl)) {
        return absoluteSortUrl;
      }
      logger.warn(TAG, `规则模式 sortUrl 未解析出可用链接，回退 source.url: source=${source.name}`);
    }
    return source.url;
  }

  async refreshSource(sourceId: string): Promise<RssFetchResult> {
    this.ensureInitialized();
    const source = await this.dataManager.getSourceById(sourceId);
    if (!source) {
      return {
        success: false,
        sourceId,
        sourceName: '未知订阅源',
        format: RssFeedFormat.UNKNOWN,
        itemCount: 0,
        insertedCount: 0,
        statusCode: 0,
        error: '订阅源不存在',
        durationMs: 0
      } as RssFetchResult;
    }
    return this.refreshSingleSource(source);
  }

  private async refreshSingleSource(source: RssSubscriptionSource): Promise<RssFetchResult> {
    const startedAt = Date.now();
    let request: http.HttpRequest | null = null;
    let statusCode = 0;
    let format = RssFeedFormat.UNKNOWN;
    let itemCount = 0;
    let insertedCount = 0;
    let errorMessage = '';

    logger.info(TAG, `开始刷新订阅源: ${source.name}`);
    try {
      await this.ensureSourceLogin(source);
      const sourceFetchUrl = this.resolveSourceFetchUrl(source);
      const requestOption = await this.resolveSourceRequestOption(
        source,
        sourceFetchUrl,
        'application/rss+xml, application/atom+xml, application/xml, text/xml, */*',
        true
      );
      logger.info(
        TAG,
        `订阅源抓取地址: ${requestOption.requestUrl}, method=${requestOption.requestMethod === http.RequestMethod.POST ? 'POST' : 'GET'}`
      );

      request = http.createHttp();
      const response = await request.request(requestOption.requestUrl, {
        method: requestOption.requestMethod,
        header: this.toHeaderObject(requestOption.headerEntries),
        connectTimeout: DEFAULT_TIMEOUT,
        readTimeout: DEFAULT_TIMEOUT,
        expectDataType: http.HttpDataType.STRING,
        extraData: requestOption.requestMethod === http.RequestMethod.POST ? requestOption.requestBody : ''
      });
      statusCode = response.responseCode;
      const responseHeaders: Object = (response.header || {}) as Object;
      this.updateSourceCookieFromResponse(source, responseHeaders);
      const responseEtag = this.getHeaderIgnoreCase(responseHeaders, 'etag');
      const responseLastModified = this.getHeaderIgnoreCase(responseHeaders, 'last-modified');

      if (statusCode === 304) {
        await this.dataManager.updateSourceFetchMeta(
          source.id,
          this.buildSourceMetaOnSuccess(
            source,
            responseEtag.length > 0 ? responseEtag : (source.etag || ''),
            responseLastModified.length > 0 ? responseLastModified : (source.lastModified || '')
          )
        );
        logger.info(TAG, `订阅源无更新: ${source.name}`);
        return {
          success: true,
          sourceId: source.id,
          sourceName: source.name,
          format,
          itemCount: 0,
          insertedCount: 0,
          statusCode,
          durationMs: Date.now() - startedAt
        } as RssFetchResult;
      }

      if (statusCode < 200 || statusCode >= 300) {
        errorMessage = `HTTP ${statusCode}`;
        await this.dataManager.updateSourceFetchMeta(
          source.id,
          this.buildSourceMetaOnError(source, errorMessage)
        );
        logger.warn(TAG, `刷新订阅源失败: ${source.name}, ${errorMessage}`);
        return {
          success: false,
          sourceId: source.id,
          sourceName: source.name,
          format,
          itemCount,
          insertedCount,
          statusCode,
          error: errorMessage,
          durationMs: Date.now() - startedAt
        } as RssFetchResult;
      }

      const xmlText = typeof response.result === 'string'
        ? response.result
        : (response.result ? String(response.result) : '');
      if (xmlText.trim().length === 0) {
        throw new Error('订阅源响应为空');
      }
      const hasRuleArticles = source.ruleArticles !== undefined
        && source.ruleArticles !== null
        && source.ruleArticles.trim().length > 0;
      if (hasRuleArticles) {
        logger.info(TAG, `订阅源启用规则解析模式: ${source.name}`);
      }
      const parserSource = this.copySource(source);
      parserSource.url = requestOption.requestUrl;
      const parsed: ParsedRssFeed = hasRuleArticles
        ? await this.parser.parseByRulesAsync(xmlText, parserSource)
        : this.parser.parse(xmlText, parserSource);
      format = parsed.format;
      itemCount = parsed.items.length;
      insertedCount = await this.dataManager.upsertFeedItems(source, parsed.items);
      await this.dataManager.trimItemsForSource(source.id, 600);

      await this.dataManager.updateSourceFetchMeta(
        source.id,
        this.buildSourceMetaOnSuccess(
          source,
          responseEtag.length > 0 ? responseEtag : (source.etag || ''),
          responseLastModified.length > 0 ? responseLastModified : (source.lastModified || '')
        )
      );

      logger.info(TAG, `刷新订阅源成功: ${source.name}, 条目=${itemCount}, 新增=${insertedCount}`);
      return {
        success: true,
        sourceId: source.id,
        sourceName: source.name,
        format,
        itemCount,
        insertedCount,
        statusCode,
        durationMs: Date.now() - startedAt
      } as RssFetchResult;
    } catch (error) {
      errorMessage = this.resolveErrorText(error as RssErrorValue);
      await this.dataManager.updateSourceFetchMeta(
        source.id,
        this.buildSourceMetaOnError(source, errorMessage)
      );
      logger.warn(TAG, `刷新订阅源异常: ${source.name}, ${errorMessage}`);
      return {
        success: false,
        sourceId: source.id,
        sourceName: source.name,
        format,
        itemCount,
        insertedCount,
        statusCode,
        error: errorMessage,
        durationMs: Date.now() - startedAt
      } as RssFetchResult;
    } finally {
      if (request) {
        request.destroy();
      }
    }
  }

  async refreshAll(onProgress?: (progress: RssRefreshProgress) => void): Promise<RssFetchResult[]> {
    this.ensureInitialized();
    const sources = await this.dataManager.getEnabledSources();
    logger.info(TAG, `开始批量刷新订阅源，总数=${sources.length}`);
    const results: RssFetchResult[] = [];
    for (let i = 0; i < sources.length; i++) {
      const source = sources[i];
      const result = await this.refreshSingleSource(source);
      results.push(result);
      if (onProgress) {
        onProgress({
          current: i + 1,
          total: sources.length,
          sourceName: source.name,
          success: result.success,
          itemCount: result.itemCount,
          insertedCount: result.insertedCount,
          durationMs: result.durationMs,
          error: result.error || ''
        } as RssRefreshProgress);
      }
    }
    const successCount = results.filter((item: RssFetchResult) => item.success).length;
    logger.info(TAG, `批量刷新完成: 成功=${successCount}, 失败=${results.length - successCount}`);
    return results;
  }

  private getSourceNextRefreshTimestamp(source: RssSubscriptionSource): number {
    const intervalMin = source.updateIntervalMin > 0 ? source.updateIntervalMin : 180;
    const baseTimestamp = source.lastSuccessTime > 0
      ? source.lastSuccessTime
      : source.lastCheckTime;
    if (baseTimestamp <= 0) {
      return 0;
    }
    return baseTimestamp + intervalMin * 60 * 1000;
  }

  private isSourceDueForRefresh(source: RssSubscriptionSource, now: number): boolean {
    if (!source.enabled || !source.autoUpdate) {
      return false;
    }
    const nextRefreshTimestamp = this.getSourceNextRefreshTimestamp(source);
    if (nextRefreshTimestamp <= 0) {
      return true;
    }
    return now >= nextRefreshTimestamp;
  }

  async refreshDueSources(onProgress?: (progress: RssRefreshProgress) => void): Promise<RssFetchResult[]> {
    this.ensureInitialized();
    const enabledSources = await this.dataManager.getEnabledSources();
    const now = Date.now();
    const dueSources: RssSubscriptionSource[] = [];
    for (let i = 0; i < enabledSources.length; i++) {
      const source = enabledSources[i];
      if (this.isSourceDueForRefresh(source, now)) {
        dueSources.push(source);
      }
    }

    logger.info(TAG, `开始刷新到期订阅源: 启用源=${enabledSources.length}, 到期源=${dueSources.length}`);
    if (dueSources.length === 0) {
      return [];
    }

    const results: RssFetchResult[] = [];
    for (let i = 0; i < dueSources.length; i++) {
      const source = dueSources[i];
      const result = await this.refreshSingleSource(source);
      results.push(result);
      if (onProgress) {
        onProgress({
          current: i + 1,
          total: dueSources.length,
          sourceName: source.name,
          success: result.success,
          itemCount: result.itemCount,
          insertedCount: result.insertedCount,
          durationMs: result.durationMs,
          error: result.error || ''
        } as RssRefreshProgress);
      }
    }

    const successCount = results.filter((item: RssFetchResult) => item.success).length;
    logger.info(TAG, `刷新到期订阅源完成: 总数=${results.length}, 成功=${successCount}, 失败=${results.length - successCount}`);
    return results;
  }

  async maybeRefreshDueSources(scene: string): Promise<RssFetchResult[]> {
    this.ensureInitialized();
    const now = Date.now();
    if (this.autoDueRefreshRunning) {
      logger.debug(TAG, `自动到期刷新已在执行中，跳过: 场景=${scene}`);
      return [];
    }
    if (this.lastAutoDueRefreshAt > 0 && (now - this.lastAutoDueRefreshAt) < AUTO_DUE_REFRESH_INTERVAL_MS) {
      logger.debug(TAG, `自动到期刷新触发过于频繁，已跳过: 场景=${scene}`);
      return [];
    }

    this.autoDueRefreshRunning = true;
    this.lastAutoDueRefreshAt = now;
    try {
      logger.info(TAG, `触发自动到期刷新: 场景=${scene}`);
      const results = await this.refreshDueSources();
      if (results.length === 0) {
        logger.info(TAG, `自动到期刷新完成: 场景=${scene}, 无到期源`);
      } else {
        const successCount = results.filter((item: RssFetchResult) => item.success).length;
        logger.info(TAG, `自动到期刷新完成: 场景=${scene}, 总数=${results.length}, 成功=${successCount}, 失败=${results.length - successCount}`);
      }
      return results;
    } catch (error) {
      logger.warn(TAG, `自动到期刷新失败: 场景=${scene}, ${String(error)}`);
      return [];
    } finally {
      this.autoDueRefreshRunning = false;
    }
  }

  private normalizeContentText(text: string, maxLength: number = 60000): string {
    const normalized = text
      .replace(/\r/g, '\n')
      .replace(/\t/g, ' ')
      .replace(/\u00A0/g, ' ')
      .replace(/[ ]{2,}/g, ' ')
      .replace(/\n{3,}/g, '\n\n')
      .trim();
    if (normalized.length <= maxLength) {
      return normalized;
    }
    return normalized.substring(0, maxLength);
  }

  private stripHtmlToText(html: string): string {
    return this.normalizeContentText(
      html
        .replace(/<script\b[\s\S]*?<\/script>/gi, ' ')
        .replace(/<style\b[\s\S]*?<\/style>/gi, ' ')
        .replace(/<br\s*\/?>/gi, '\n')
        .replace(/<\/p>/gi, '\n')
        .replace(/<\/div>/gi, '\n')
        .replace(/<\/h[1-6]>/gi, '\n')
        .replace(/<\/li>/gi, '\n')
        .replace(/<[^>]+>/g, ' ')
    );
  }

  private toDescription(content: string, fallbackDescription: string): string {
    const trimmedFallback = fallbackDescription.trim();
    if (trimmedFallback.length > 0) {
      return trimmedFallback.length > 500 ? trimmedFallback.substring(0, 500) : trimmedFallback;
    }
    const normalized = content.replace(/\n/g, ' ').replace(/[ ]{2,}/g, ' ').trim();
    if (normalized.length <= 500) {
      return normalized;
    }
    return normalized.substring(0, 500);
  }

  private parsePubDate(pubDateText: string): number {
    const text = pubDateText.trim();
    if (text.length === 0) {
      return 0;
    }
    const num = Number(text);
    if (!Number.isNaN(num) && Number.isFinite(num) && num > 0) {
      return num < 1_000_000_000_000 ? num * 1000 : num;
    }
    const parsed = Date.parse(text);
    if (!Number.isNaN(parsed)) {
      return parsed;
    }
    return 0;
  }

  private parseContentFilterRules(rawRules: string): string[] {
    const text = rawRules.trim();
    if (text.length === 0) {
      return [];
    }
    return text
      .split(/\r?\n|&&/g)
      .map((item: string) => item.trim())
      .filter((item: string) => item.length > 0);
  }

  private matchesTextRule(text: string, rule: string): boolean {
    const trimmedRule = rule.trim();
    if (trimmedRule.length === 0) {
      return false;
    }
    if (trimmedRule.startsWith('re:')) {
      try {
        const regex = new RegExp(trimmedRule.substring(3), 'i');
        return regex.test(text);
      } catch (error) {
        logger.warn(TAG, `内容过滤正则不合法，已忽略: ${trimmedRule}, error=${String(error)}`);
        return false;
      }
    }
    return text.includes(trimmedRule);
  }

  private applyContentWhitelist(text: string, whitelistRaw: string): string {
    const rules = this.parseContentFilterRules(whitelistRaw);
    if (rules.length === 0) {
      return text;
    }
    const lines = text.split('\n');
    const keptLines: string[] = [];
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      for (let j = 0; j < rules.length; j++) {
        if (this.matchesTextRule(line, rules[j])) {
          keptLines.push(line);
          break;
        }
      }
    }
    if (keptLines.length === 0) {
      return text;
    }
    return keptLines.join('\n');
  }

  private applyContentBlacklist(text: string, blacklistRaw: string): string {
    const rules = this.parseContentFilterRules(blacklistRaw);
    if (rules.length === 0) {
      return text;
    }
    let filteredText = text;
    for (let i = 0; i < rules.length; i++) {
      const rule = rules[i];
      if (rule.startsWith('re:')) {
        try {
          const regex = new RegExp(rule.substring(3), 'ig');
          filteredText = filteredText.replace(regex, ' ');
        } catch (error) {
          logger.warn(TAG, `内容黑名单正则不合法，已忽略: ${rule}, error=${String(error)}`);
        }
        continue;
      }
      filteredText = filteredText.split(rule).join(' ');
    }
    return filteredText;
  }

  private applySourceContentFilters(text: string, source: RssSubscriptionSource): string {
    const whitelist = source.contentWhitelist || '';
    const blacklist = source.contentBlacklist || '';
    const whitelisted = this.applyContentWhitelist(text, whitelist);
    const blacklisted = this.applyContentBlacklist(whitelisted, blacklist);
    return this.normalizeContentText(blacklisted);
  }

  private async parseSinglePageContent(
    htmlText: string,
    pageUrl: string,
    source: RssSubscriptionSource,
    fallbackDescription: string
  ): Promise<ParsedPageContent> {
    const analyzer = new LegadoRuleAnalyzer();
    analyzer.setJsLib(source.jsLib || '');
    analyzer.setContent(htmlText, pageUrl, false);

    const ruleContent = source.ruleContent ? source.ruleContent.trim() : '';
    const ruleDescription = source.ruleDescription ? source.ruleDescription.trim() : '';
    const ruleNextPage = source.ruleNextPage ? source.ruleNextPage.trim() : '';
    let contentText = '';
    let descriptionText = '';
    let nextPageUrl = '';

    if (ruleContent.length > 0) {
      try {
        contentText = await analyzer.getStringAsync(ruleContent);
      } catch (error) {
        logger.warn(TAG, `正文规则解析失败，降级到HTML文本提取: ${String(error)}`);
      }
    }

    if (ruleDescription.length > 0) {
      try {
        descriptionText = await analyzer.getStringAsync(ruleDescription);
      } catch (error) {
        logger.warn(TAG, `摘要规则解析失败，降级到正文摘要: ${String(error)}`);
      }
    }

    if (ruleNextPage.length > 0) {
      try {
        nextPageUrl = await analyzer.getStringAsync(ruleNextPage);
      } catch (error) {
        logger.warn(TAG, `下一页规则解析失败，已忽略: ${String(error)}`);
      }
    }

    const normalizedContent = contentText.trim().length > 0
      ? this.normalizeContentText(contentText)
      : this.stripHtmlToText(htmlText);
    const normalizedDescription = descriptionText.trim().length > 0
      ? this.normalizeContentText(descriptionText, 500)
      : this.toDescription(normalizedContent, fallbackDescription);

    return {
      content: normalizedContent,
      description: normalizedDescription,
      nextPageUrl: nextPageUrl.trim()
    } as ParsedPageContent;
  }

  private async fetchTextBySource(
    source: RssSubscriptionSource,
    requestUrl: string,
    timeoutMs: number,
    acceptValue: string
  ): Promise<string> {
    await this.ensureSourceLogin(source);

    let request: http.HttpRequest | null = null;
    try {
      const requestOption = await this.resolveSourceRequestOption(source, requestUrl, acceptValue, false);
      request = http.createHttp();
      const response = await request.request(requestOption.requestUrl, {
        method: requestOption.requestMethod,
        header: this.toHeaderObject(requestOption.headerEntries),
        connectTimeout: timeoutMs,
        readTimeout: timeoutMs,
        expectDataType: http.HttpDataType.STRING,
        extraData: requestOption.requestMethod === http.RequestMethod.POST ? requestOption.requestBody : ''
      });
      const statusCode = response.responseCode;
      const responseHeaders = (response.header || {}) as Object;
      this.updateSourceCookieFromResponse(source, responseHeaders);
      if (statusCode < 200 || statusCode >= 300) {
        throw new Error(`HTTP 状态码 ${statusCode}`);
      }

      const responseText = typeof response.result === 'string'
        ? response.result
        : (response.result ? String(response.result) : '');
      if (responseText.trim().length === 0) {
        throw new Error('响应内容为空');
      }
      return responseText;
    } catch (error) {
      const errorText = this.resolveErrorText(error as RssErrorValue);
      throw new Error(errorText);
    } finally {
      if (request) {
        request.destroy();
      }
    }
  }

  private async parseItemContentFromPage(
    htmlText: string,
    pageUrl: string,
    source: RssSubscriptionSource,
    fallbackDescription: string
  ): Promise<ParsedItemContent> {
    const contentParts: string[] = [];
    let currentUrl = pageUrl;
    let currentHtml = htmlText;
    let description = fallbackDescription;
    const visitedUrls: Set<string> = new Set();
    visitedUrls.add(currentUrl);

    const hasNextPageRule = (source.ruleNextPage || '').trim().length > 0;
    for (let pageIndex = 0; pageIndex < MAX_CONTENT_PAGE_COUNT; pageIndex++) {
      const pageResult = await this.parseSinglePageContent(
        currentHtml,
        currentUrl,
        source,
        description
      );

      if (pageResult.content.trim().length > 0) {
        contentParts.push(pageResult.content);
      }
      if (pageIndex === 0 && pageResult.description.trim().length > 0) {
        description = pageResult.description;
      }
      if (!hasNextPageRule) {
        break;
      }

      const nextPageRaw = pageResult.nextPageUrl.trim();
      if (nextPageRaw.length === 0) {
        break;
      }
      const nextUrl = this.toAbsoluteUrl(currentUrl, nextPageRaw);
      if (!this.validateUrl(nextUrl)) {
        logger.warn(TAG, `检测到不合法的正文下一页地址，已停止翻页: ${nextPageRaw}`);
        break;
      }
      if (visitedUrls.has(nextUrl)) {
        logger.warn(TAG, `检测到重复正文分页地址，已停止翻页: ${nextUrl}`);
        break;
      }
      if (pageIndex >= MAX_CONTENT_PAGE_COUNT - 1) {
        break;
      }

      visitedUrls.add(nextUrl);
      logger.info(TAG, `开始抓取正文下一页: ${nextUrl}`);
      currentUrl = nextUrl;
      currentHtml = await this.fetchTextBySource(
        source,
        nextUrl,
        DEFAULT_TIMEOUT,
        'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
      );
    }

    let mergedContent = contentParts.join('\n\n');
    if (mergedContent.trim().length === 0) {
      mergedContent = this.stripHtmlToText(htmlText);
    }
    const filteredContent = this.applySourceContentFilters(mergedContent, source);
    const normalizedContent = this.normalizeContentText(filteredContent);
    const normalizedDescription = this.toDescription(normalizedContent, description);
    return {
      content: normalizedContent,
      description: normalizedDescription
    } as ParsedItemContent;
  }

  async refreshItemContent(itemId: string): Promise<RssItemContentRefreshResult> {
    this.ensureInitialized();
    const item = await this.dataManager.getItemById(itemId);
    if (!item) {
      return {
        success: false,
        itemId,
        sourceId: '',
        content: '',
        description: '',
        fetchedAt: Date.now(),
        error: '订阅条目不存在'
      } as RssItemContentRefreshResult;
    }
    const source = await this.dataManager.getSourceById(item.sourceId);
    if (!source) {
      return {
        success: false,
        itemId,
        sourceId: item.sourceId,
        content: '',
        description: '',
        fetchedAt: Date.now(),
        error: '订阅源不存在'
      } as RssItemContentRefreshResult;
    }
    if (!item.link || item.link.trim().length === 0) {
      return {
        success: false,
        itemId,
        sourceId: item.sourceId,
        content: '',
        description: '',
        fetchedAt: Date.now(),
        error: '条目链接为空，无法抓取正文'
      } as RssItemContentRefreshResult;
    }

    const requestUrl = this.toAbsoluteUrl(source.url, item.link);
    if (!this.validateUrl(requestUrl)) {
      return {
        success: false,
        itemId,
        sourceId: item.sourceId,
        content: '',
        description: '',
        fetchedAt: Date.now(),
        error: `条目链接不合法: ${item.link}`
      } as RssItemContentRefreshResult;
    }

    try {
      logger.info(TAG, `开始抓取订阅条目正文: source=${source.name}, itemId=${item.id}`);
      const htmlText = await this.fetchTextBySource(
        source,
        requestUrl,
        DEFAULT_TIMEOUT,
        'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
      );
      const parsed = await this.parseItemContentFromPage(htmlText, requestUrl, source, item.description || '');
      if (parsed.content.length === 0) {
        throw new Error('正文解析结果为空');
      }
      await this.dataManager.updateItemContent(item.id, parsed.content, parsed.description);
      logger.info(TAG, `订阅条目正文抓取完成: itemId=${item.id}, contentLen=${parsed.content.length}`);
      return {
        success: true,
        itemId: item.id,
        sourceId: item.sourceId,
        content: parsed.content,
        description: parsed.description,
        fetchedAt: Date.now()
      } as RssItemContentRefreshResult;
    } catch (error) {
      const errorText = this.resolveErrorText(error as RssErrorValue);
      logger.error(TAG, `订阅条目正文抓取失败: itemId=${item.id}, ${errorText}`);
      return {
        success: false,
        itemId: item.id,
        sourceId: item.sourceId,
        content: '',
        description: '',
        fetchedAt: Date.now(),
        error: errorText
      } as RssItemContentRefreshResult;
    }
  }

  async previewSourceRules(sourceId: string, limit: number = 12): Promise<RssRulePreviewResult> {
    this.ensureInitialized();
    const source = await this.dataManager.getSourceById(sourceId);
    if (!source) {
      throw new Error('订阅源不存在');
    }
    const ruleArticles = source.ruleArticles ? source.ruleArticles.trim() : '';
    if (ruleArticles.length === 0) {
      throw new Error('当前订阅源未配置 ruleArticles，无法预览规则');
    }

    const requestUrl = this.resolveSourceFetchUrl(source);
    if (!this.validateUrl(requestUrl)) {
      throw new Error(`预览地址不合法: ${requestUrl}`);
    }
    logger.info(TAG, `开始规则预览: source=${source.name}, requestUrl=${requestUrl}`);

    const content = await this.fetchTextBySource(
      source,
      requestUrl,
      DEFAULT_TIMEOUT,
      'application/rss+xml, application/atom+xml, application/xml, text/xml, */*'
    );
    const analyzer = new LegadoRuleAnalyzer();
    analyzer.setJsLib(source.jsLib || '');
    analyzer.setContent(content, requestUrl, false);

    let selector = ruleArticles;
    let reverse = false;
    if (selector.startsWith('-')) {
      reverse = true;
      selector = selector.substring(1).trim();
    }
    if (selector.length === 0) {
      throw new Error('ruleArticles 规则无效');
    }

    const blocks = await analyzer.getElementsAsync(selector);
    if (blocks.length === 0) {
      throw new Error('规则未命中任何条目');
    }

    const previewItems: RssRulePreviewItem[] = [];
    const previewLimit = limit > 0 ? limit : 12;
    const titleRule = source.ruleTitle ? source.ruleTitle.trim() : '';
    const linkRule = source.ruleLink ? source.ruleLink.trim() : '';
    const pubDateRule = source.rulePubDate ? source.rulePubDate.trim() : '';
    const descriptionRule = source.ruleDescription ? source.ruleDescription.trim() : '';
    const warning = titleRule.length === 0 && linkRule.length === 0
      ? '未配置 ruleTitle/ruleLink，预览结果可能不完整'
      : '';

    const startIndex = reverse ? blocks.length - 1 : 0;
    const step = reverse ? -1 : 1;
    for (
      let index = startIndex;
      index >= 0 && index < blocks.length && previewItems.length < previewLimit;
      index += step
    ) {
      try {
        const block = blocks[index];
        const itemAnalyzer = new LegadoRuleAnalyzer();
        itemAnalyzer.setJsLib(source.jsLib || '');
        itemAnalyzer.setContent(block, requestUrl, false);
        const titleRaw = titleRule.length > 0 ? await itemAnalyzer.getStringAsync(titleRule) : '';
        const linkRaw = linkRule.length > 0 ? await itemAnalyzer.getStringAsync(linkRule) : '';
        const pubDateRaw = pubDateRule.length > 0 ? await itemAnalyzer.getStringAsync(pubDateRule) : '';
        const descriptionRaw = descriptionRule.length > 0 ? await itemAnalyzer.getStringAsync(descriptionRule) : '';

        const title = this.normalizeContentText(titleRaw, 240);
        const link = this.toAbsoluteUrl(requestUrl, this.normalizeContentText(linkRaw, 2048));
        const pubDate = this.parsePubDate(pubDateRaw);
        const description = this.normalizeContentText(descriptionRaw, 320);
        const previewItem: RssRulePreviewItem = {
          title: title.length > 0 ? title : `未命名条目 ${previewItems.length + 1}`,
          link,
          pubDate,
          description
        };
        previewItems.push(previewItem);
      } catch (error) {
        logger.warn(TAG, `规则预览条目解析失败，已跳过: ${String(error)}`);
      }

      if (previewItems.length % 40 === 0) {
        await new Promise<void>((resolve: () => void) => setTimeout((): void => resolve(), 0));
      }
    }

    logger.info(TAG, `规则预览完成: source=${source.name}, 命中=${blocks.length}, 返回=${previewItems.length}`);
    return {
      sourceId: source.id,
      sourceName: source.name,
      requestUrl,
      total: blocks.length,
      fetchedAt: Date.now(),
      warning,
      items: previewItems
    } as RssRulePreviewResult;
  }

  private isObjectLike(value: Object | undefined | null): boolean {
    return value !== undefined && value !== null && typeof value === 'object';
  }

  private getFieldValue(data: Object, key: string): Object | undefined {
    const entries = Object.entries(data) as [string, Object][];
    for (const entry of entries) {
      if (entry[0] === key) {
        return entry[1];
      }
    }
    return undefined;
  }

  private readStringValue(data: Object, key: string): string {
    const value = this.getFieldValue(data, key);
    if (value === undefined || value === null) {
      return '';
    }
    if (typeof value === 'string') {
      return value.trim();
    }
    if (typeof value === 'number' || typeof value === 'boolean') {
      return String(value).trim();
    }
    try {
      return JSON.stringify(value).trim();
    } catch (_error) {
      return String(value).trim();
    }
  }

  private readStringValueByKeys(data: Object, keys: string[]): string {
    for (const key of keys) {
      const text = this.readStringValue(data, key);
      if (text.length > 0) {
        return text;
      }
    }
    return '';
  }

  private readBooleanValue(data: Object, key: string): boolean | undefined {
    const value = this.getFieldValue(data, key);
    if (value === undefined || value === null) {
      return undefined;
    }
    if (typeof value === 'boolean') {
      return value;
    }
    const str = String(value).toLowerCase().trim();
    if (str === '1' || str === 'true' || str === 'yes') {
      return true;
    }
    if (str === '0' || str === 'false' || str === 'no') {
      return false;
    }
    return undefined;
  }

  private readBooleanValueByKeys(data: Object, keys: string[]): boolean | undefined {
    for (const key of keys) {
      const boolValue = this.readBooleanValue(data, key);
      if (boolValue !== undefined) {
        return boolValue;
      }
    }
    return undefined;
  }

  private readNumberValue(data: Object, key: string): number | undefined {
    const value = this.getFieldValue(data, key);
    if (value === undefined || value === null) {
      return undefined;
    }
    const num = Number(value);
    if (Number.isNaN(num) || !Number.isFinite(num)) {
      return undefined;
    }
    return Math.floor(num);
  }

  private readNumberValueByKeys(data: Object, keys: string[]): number | undefined {
    for (const key of keys) {
      const num = this.readNumberValue(data, key);
      if (num !== undefined) {
        return num;
      }
    }
    return undefined;
  }

  private readStringArrayValue(data: Object, key: string): string[] {
    const value = this.getFieldValue(data, key);
    if (!value) {
      return [];
    }
    if (Array.isArray(value)) {
      const urls: string[] = [];
      const valueList = value as Object[];
      for (let i = 0; i < valueList.length; i++) {
        const rawItem: Object = valueList[i];
        const text = String(rawItem).trim();
        if (text.length > 0) {
          urls.push(text);
        }
      }
      return urls;
    }
    const text = String(value).trim();
    if (text.length === 0) {
      return [];
    }
    return text
      .split(/[\n,]/g)
      .map((item: string) => item.trim())
      .filter((item: string) => item.length > 0);
  }

  private extractUrlOptionSuffix(urlText: string): string {
    const text = this.normalizeUrl(urlText);
    if (text.length === 0) {
      return '';
    }
    const match = text.match(/,\s*\{[\s\S]*\}\s*$/);
    if (!match || match.index === undefined || match.index <= 0) {
      return '';
    }
    return text.substring(match.index).trim();
  }

  private stripUrlOptionSuffix(urlText: string): string {
    const text = this.normalizeUrl(urlText);
    if (text.length === 0) {
      return '';
    }
    const match = text.match(/,\s*\{[\s\S]*\}\s*$/);
    if (!match || match.index === undefined || match.index <= 0) {
      return text;
    }
    const pureUrl = text.substring(0, match.index).trim();
    return pureUrl.length > 0 ? pureUrl : text;
  }

  private tryPickImportUrlCandidate(rawUrl: string, baseUrl: string): string {
    const text = this.normalizeUrl(rawUrl);
    if (text.length === 0) {
      return '';
    }
    if (text.startsWith('<js>') || text.startsWith('@js:') || text.startsWith('{{')) {
      return '';
    }
    const normalizedText = this.stripUrlOptionSuffix(text);
    if (this.validateUrl(normalizedText)) {
      return normalizedText;
    }
    if (baseUrl.length > 0) {
      const absoluteUrl = this.toAbsoluteUrl(baseUrl, normalizedText);
      if (this.validateUrl(absoluteUrl)) {
        return absoluteUrl;
      }
    }
    return '';
  }

  private resolveSortUrlCandidate(candidate: string, baseUrl: string, keepOptionSuffix: boolean): string {
    const resolvedBaseUrl = this.tryPickImportUrlCandidate(candidate, baseUrl);
    if (resolvedBaseUrl.length === 0) {
      return '';
    }
    if (!keepOptionSuffix) {
      return resolvedBaseUrl;
    }
    const optionSuffix = this.extractUrlOptionSuffix(candidate);
    if (optionSuffix.length > 0) {
      return `${resolvedBaseUrl}${optionSuffix}`;
    }
    return resolvedBaseUrl;
  }

  private extractUrlFromSortUrl(sortUrlText: string, baseUrl: string, keepOptionSuffix: boolean = false): string {
    const text = sortUrlText.trim();
    if (text.length === 0) {
      return '';
    }
    if (text.startsWith('<js>') || text.startsWith('@js:')) {
      return '';
    }

    const lines = text.split(/\r?\n|&&/g);
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim();
      if (line.length === 0) {
        continue;
      }
      let candidate = line;
      const splitIndex = line.indexOf('::');
      if (splitIndex >= 0) {
        candidate = line.substring(splitIndex + 2).trim();
      }
      const resolved = this.resolveSortUrlCandidate(candidate, baseUrl, keepOptionSuffix);
      if (resolved.length > 0) {
        return resolved;
      }
      const httpStartIndex = line.search(/https?:\/\//i);
      if (httpStartIndex >= 0) {
        const fallbackCandidate = line.substring(httpStartIndex).trim();
        const fallbackResolved = this.resolveSortUrlCandidate(fallbackCandidate, baseUrl, keepOptionSuffix);
        if (fallbackResolved.length > 0) {
          return fallbackResolved;
        }
      }
    }
    return '';
  }

  private resolveImportSourceUrl(sourceObj: Object): ResolvedImportSourceUrl {
    const rawUrl = this.readStringValueByKeys(sourceObj, ['url']);
    const rawFeedUrl = this.readStringValueByKeys(sourceObj, ['feedUrl']);
    const rawSourceUrl = this.readStringValueByKeys(sourceObj, ['sourceUrl']);
    const rawSortUrl = this.readStringValueByKeys(sourceObj, ['sortUrl']);
    const rawSearchUrl = this.readStringValueByKeys(sourceObj, ['searchUrl']);

    const baseCandidates = [rawUrl, rawFeedUrl, rawSourceUrl];
    let baseUrl = '';
    for (let i = 0; i < baseCandidates.length; i++) {
      const candidate = this.tryPickImportUrlCandidate(baseCandidates[i], '');
      if (candidate.length > 0) {
        baseUrl = candidate;
        break;
      }
    }

    let selectedUrl = this.tryPickImportUrlCandidate(rawUrl, '');
    let selectedFrom = 'url';

    if (selectedUrl.length === 0) {
      selectedUrl = this.tryPickImportUrlCandidate(rawFeedUrl, '');
      selectedFrom = selectedUrl.length > 0 ? 'feedUrl' : selectedFrom;
    }

    if (selectedUrl.length === 0) {
      selectedUrl = this.tryPickImportUrlCandidate(rawSourceUrl, '');
      selectedFrom = selectedUrl.length > 0 ? 'sourceUrl' : selectedFrom;
    }

    if (selectedUrl.length === 0) {
      selectedUrl = this.extractUrlFromSortUrl(rawSortUrl, baseUrl);
      selectedFrom = selectedUrl.length > 0 ? 'sortUrl' : selectedFrom;
    }

    if (selectedUrl.length === 0) {
      selectedUrl = this.tryPickImportUrlCandidate(rawSearchUrl, baseUrl);
      selectedFrom = selectedUrl.length > 0 ? 'searchUrl' : selectedFrom;
    }

    return {
      selectedUrl,
      selectedFrom,
      rawUrl,
      rawFeedUrl,
      rawSourceUrl,
      rawSortUrl,
      rawSearchUrl
    } as ResolvedImportSourceUrl;
  }

  private parseHeaderEntriesFromRecord(headerRecord: Record<string, string>): HeaderEntry[] {
    const entries: HeaderEntry[] = [];
    const headerPairs = Object.entries(headerRecord) as [string, string][];
    for (let i = 0; i < headerPairs.length; i++) {
      const key = String(headerPairs[i][0]).trim();
      const value = String(headerPairs[i][1]).trim();
      if (key.length === 0 || value.length === 0) {
        continue;
      }
      entries.push({ key, value } as HeaderEntry);
    }
    return entries;
  }

  private async resolveSourceRequestOption(
    source: RssSubscriptionSource,
    rawRequestUrl: string,
    acceptValue: string,
    includeConditionalCache: boolean
  ): Promise<ResolvedSourceRequestOption> {
    const analyzer = new LegadoUrlAnalyzer(source.url, source.url, source.jsLib || '');
    let parsedRequest: ParsedUrlRequest;
    try {
      parsedRequest = await analyzer.analyzeUrlAsync(rawRequestUrl, '', 1);
    } catch (error) {
      const errorText = this.resolveErrorText(error as RssErrorValue);
      throw new Error(`请求地址解析失败: ${errorText}`);
    }

    const resolvedRequestUrl = this.normalizeUrl(encodeURI(parsedRequest.url || ''));
    if (!this.validateUrl(resolvedRequestUrl)) {
      throw new Error(`链接不合法: ${resolvedRequestUrl.length > 0 ? resolvedRequestUrl : rawRequestUrl}`);
    }

    const requestMethod = parsedRequest.method === RequestMethod.POST
      ? http.RequestMethod.POST
      : http.RequestMethod.GET;
    const requestBody = parsedRequest.body ? parsedRequest.body : '';
    const baseHeaderEntries = this.buildSourceRequestHeaderEntries(source, acceptValue, includeConditionalCache);
    const requestHeaderEntries = parsedRequest.headers
      ? this.parseHeaderEntriesFromRecord(parsedRequest.headers)
      : [];
    const mergedHeaderEntries = this.mergeHeaderEntries(baseHeaderEntries, requestHeaderEntries);

    return {
      requestUrl: resolvedRequestUrl,
      requestMethod,
      requestBody,
      headerEntries: mergedHeaderEntries
    } as ResolvedSourceRequestOption;
  }

  private looksLikeSourceEntry(sourceObj: Object): boolean {
    const resolved = this.resolveImportSourceUrl(sourceObj);
    if (resolved.selectedUrl.length > 0) {
      return true;
    }
    const hasRuleArticles = this.readStringValueByKeys(sourceObj, ['ruleArticles']).length > 0;
    if (!hasRuleArticles) {
      return false;
    }
    return resolved.rawSortUrl.length > 0 || resolved.rawSearchUrl.length > 0 || resolved.rawSourceUrl.length > 0;
  }

  private parseImportUrlRequestOption(rawUrl: string): ImportUrlRequestOption {
    const trimmed = rawUrl.trim();
    if (trimmed.endsWith('#requestWithoutUA')) {
      return {
        url: trimmed.substring(0, trimmed.length - '#requestWithoutUA'.length),
        requestWithoutUA: true
      } as ImportUrlRequestOption;
    }
    return {
      url: trimmed,
      requestWithoutUA: false
    } as ImportUrlRequestOption;
  }

  private async fetchTextByUrl(rawUrl: string, timeoutMs: number): Promise<string> {
    const option = this.parseImportUrlRequestOption(rawUrl);
    if (!this.validateUrl(option.url)) {
      throw new Error(`导入链接不合法: ${rawUrl}`);
    }

    let request: http.HttpRequest | null = null;
    try {
      const header: RssImportRequestHeader = {
        'Accept': 'application/json, text/plain, */*',
        'Cache-Control': 'no-cache',
        'User-Agent': option.requestWithoutUA ? 'null' : 'Mozilla/5.0 (HarmonyOS; RSSSubscription)'
      };
      request = http.createHttp();
      const response = await request.request(option.url, {
        method: http.RequestMethod.GET,
        header: header as Object,
        connectTimeout: timeoutMs,
        readTimeout: timeoutMs,
        expectDataType: http.HttpDataType.STRING
      });
      const statusCode = response.responseCode;
      if (statusCode < 200 || statusCode >= 300) {
        throw new Error(`HTTP 状态码 ${statusCode}`);
      }
      const responseText = typeof response.result === 'string'
        ? response.result
        : (response.result ? String(response.result) : '');
      if (responseText.trim().length === 0) {
        throw new Error('响应内容为空');
      }
      return responseText;
    } catch (error) {
      const errorText = this.resolveErrorText(error as RssErrorValue);
      throw new Error(errorText);
    } finally {
      if (request) {
        request.destroy();
      }
    }
  }

  private async resolveImportList(data: Object | Object[], visitedUrls: Set<string>, depth: number): Promise<Object[]> {
    if (depth > MAX_IMPORT_SOURCE_URL_DEPTH) {
      logger.warn(TAG, `检测到过深 sourceUrls 递归层级，已截断: depth=${depth}`);
      return [];
    }
    if (Array.isArray(data)) {
      const list: Object[] = [];
      const inputList = data as Object[];
      for (let i = 0; i < inputList.length; i++) {
        const item: Object = inputList[i];
        if (!this.isObjectLike(item)) {
          continue;
        }
        if (Array.isArray(item)) {
          const nested = await this.resolveImportList(item as Object[], visitedUrls, depth + 1);
          for (const nestedItem of nested) {
            list.push(nestedItem);
          }
          continue;
        }
        list.push(item as Object);
      }
      return list;
    }

    const container = data as Object;
    const resolvedList: Object[] = [];

    const sourceUrls = this.readStringArrayValue(container, 'sourceUrls');
    if (sourceUrls.length > 0) {
      logger.info(TAG, `检测到 sourceUrls 远程导入入口，数量=${sourceUrls.length}`);
      for (const sourceUrl of sourceUrls) {
        const normalizedUrl = this.normalizeUrl(sourceUrl);
        if (!this.validateUrl(normalizedUrl)) {
          logger.warn(TAG, `忽略非法 sourceUrls 链接: ${normalizedUrl}`);
          continue;
        }
        if (visitedUrls.has(normalizedUrl)) {
          logger.info(TAG, `跳过重复 sourceUrls 链接: ${normalizedUrl}`);
          continue;
        }
        visitedUrls.add(normalizedUrl);
        try {
          logger.info(TAG, `开始拉取 sourceUrls 远程内容: ${normalizedUrl}`);
          const text = await this.fetchTextByUrl(normalizedUrl, URL_IMPORT_TIMEOUT);
          const parsed = SafeUtils.parseArr(text) as Object | Object[];
          const nested = await this.resolveImportList(parsed, visitedUrls, depth + 1);
          for (const nestedItem of nested) {
            resolvedList.push(nestedItem);
          }
        } catch (error) {
          const errorText = this.resolveErrorText(error as RssErrorValue);
          logger.warn(TAG, `拉取 sourceUrls 失败: ${normalizedUrl}, ${errorText}`);
        }
      }
    }

    const listKeys = ['sources', 'sourceList', 'rssSources', 'subscriptionSources', 'data', 'items'];
    for (const key of listKeys) {
      const value = this.getFieldValue(container, key);
      if (!Array.isArray(value)) {
        continue;
      }
      const nested = await this.resolveImportList(value as Object[], visitedUrls, depth + 1);
      for (const nestedItem of nested) {
        resolvedList.push(nestedItem);
      }
    }

    if (this.looksLikeSourceEntry(container)) {
      resolvedList.push(data);
    }
    return resolvedList;
  }

  private buildImportPayload(sourceObj: Object, source: RssSubscriptionSource): RssSourceUpdatePayload {
    const payload: RssSourceUpdatePayload = {
      name: source.name,
      url: source.url,
      groupName: this.readStringValueByKeys(sourceObj, ['groupName', 'sourceGroup']) || (source.groupName || ''),
      iconUrl: this.readStringValueByKeys(sourceObj, ['iconUrl', 'sourceIcon']) || (source.iconUrl || ''),
      sourceComment: this.readStringValueByKeys(sourceObj, ['sourceComment', 'comment']) || (source.sourceComment || ''),
      enabled: this.readBooleanValueByKeys(sourceObj, ['enabled']),
      autoUpdate: this.readBooleanValueByKeys(sourceObj, ['autoUpdate']),
      updateIntervalMin: this.readNumberValueByKeys(sourceObj, ['updateIntervalMin', 'updateInterval']),
      variableComment: this.readStringValueByKeys(sourceObj, ['variableComment']) || (source.variableComment || ''),
      jsLib: this.readStringValueByKeys(sourceObj, ['jsLib']) || (source.jsLib || ''),
      enabledCookieJar: this.readBooleanValueByKeys(sourceObj, ['enabledCookieJar']),
      concurrentRate: this.readStringValueByKeys(sourceObj, ['concurrentRate']) || (source.concurrentRate || ''),
      header: this.readStringValueByKeys(sourceObj, ['header']) || (source.header || ''),
      loginUrl: this.readStringValueByKeys(sourceObj, ['loginUrl']) || (source.loginUrl || ''),
      loginUi: this.readStringValueByKeys(sourceObj, ['loginUi']) || (source.loginUi || ''),
      loginCheckJs: this.readStringValueByKeys(sourceObj, ['loginCheckJs']) || (source.loginCheckJs || ''),
      coverDecodeJs: this.readStringValueByKeys(sourceObj, ['coverDecodeJs']) || (source.coverDecodeJs || ''),
      sortUrl: this.readStringValueByKeys(sourceObj, ['sortUrl']) || (source.sortUrl || ''),
      singleUrl: this.readBooleanValueByKeys(sourceObj, ['singleUrl']),
      articleStyle: this.readNumberValueByKeys(sourceObj, ['articleStyle']),
      ruleArticles: this.readStringValueByKeys(sourceObj, ['ruleArticles']) || (source.ruleArticles || ''),
      ruleNextPage: this.readStringValueByKeys(sourceObj, ['ruleNextPage']) || (source.ruleNextPage || ''),
      ruleTitle: this.readStringValueByKeys(sourceObj, ['ruleTitle']) || (source.ruleTitle || ''),
      rulePubDate: this.readStringValueByKeys(sourceObj, ['rulePubDate']) || (source.rulePubDate || ''),
      ruleDescription: this.readStringValueByKeys(sourceObj, ['ruleDescription']) || (source.ruleDescription || ''),
      ruleImage: this.readStringValueByKeys(sourceObj, ['ruleImage']) || (source.ruleImage || ''),
      ruleLink: this.readStringValueByKeys(sourceObj, ['ruleLink']) || (source.ruleLink || ''),
      ruleContent: this.readStringValueByKeys(sourceObj, ['ruleContent']) || (source.ruleContent || ''),
      contentWhitelist: this.readStringValueByKeys(sourceObj, ['contentWhitelist']) || (source.contentWhitelist || ''),
      contentBlacklist: this.readStringValueByKeys(sourceObj, ['contentBlacklist']) || (source.contentBlacklist || ''),
      shouldOverrideUrlLoading: this.readStringValueByKeys(sourceObj, ['shouldOverrideUrlLoading']) || (source.shouldOverrideUrlLoading || ''),
      style: this.readStringValueByKeys(sourceObj, ['style']) || (source.style || ''),
      enableJs: this.readBooleanValueByKeys(sourceObj, ['enableJs']),
      loadWithBaseUrl: this.readBooleanValueByKeys(sourceObj, ['loadWithBaseUrl']),
      injectJs: this.readStringValueByKeys(sourceObj, ['injectJs']) || (source.injectJs || ''),
      lastUpdateTime: this.readNumberValueByKeys(sourceObj, ['lastUpdateTime']),
      customOrder: this.readNumberValueByKeys(sourceObj, ['customOrder'])
    };
    return payload;
  }

  async importSourcesFromJson(
    jsonText: string,
    conflictPolicy: RssImportConflictPolicy = 'overwrite'
  ): Promise<RssImportResult> {
    this.ensureInitialized();
    const text = jsonText.trim();
    if (text.length === 0) {
      throw new Error('导入内容不能为空');
    }
    logger.info(TAG, `开始 JSON 导入订阅源: 策略=${conflictPolicy}, 内容长度=${text.length}`);

    let data: Object | Object[];
    try {
      data = SafeUtils.parseArr(text) as Object | Object[];
    } catch (error) {
      const errorText = this.resolveErrorText(error as RssErrorValue);
      logger.error(TAG, `JSON 解析失败: ${errorText}`);
      throw new Error(`JSON 解析失败: ${errorText}`);
    }

    const visitedUrls: Set<string> = new Set();
    const list = await this.resolveImportList(data, visitedUrls, 0);
    logger.info(TAG, `导入对象解析完成: 策略=${conflictPolicy}, 待处理条目=${list.length}`);

    let success = 0;
    let failed = 0;
    let skipped = 0;
    let created = 0;
    let updated = 0;
    const errors: string[] = [];
    const importSeenUrls: Set<string> = new Set();

    for (let i = 0; i < list.length; i++) {
      const raw = list[i];
      const sourceObj = raw as Object;
      const resolvedUrl = this.resolveImportSourceUrl(sourceObj);
      const name = this.readStringValueByKeys(sourceObj, ['name', 'sourceName']);
      const groupName = this.readStringValueByKeys(sourceObj, ['groupName', 'sourceGroup']);

      if (resolvedUrl.selectedUrl.length === 0) {
        failed++;
        errors.push(`第 ${i + 1} 项缺少可用 URL（url/feedUrl/sourceUrl/sortUrl/searchUrl）`);
        logger.warn(
          TAG,
          `导入条目无效: index=${i + 1}, 原因=缺少可用URL, sourceUrl=${resolvedUrl.rawSourceUrl}, sortUrl长度=${resolvedUrl.rawSortUrl.length}`
        );
        continue;
      }

      try {
        const normalizedUrl = this.normalizeUrl(resolvedUrl.selectedUrl);
        const normalizedSourceUrl = this.normalizeUrl(resolvedUrl.rawSourceUrl);
        if (resolvedUrl.selectedFrom !== 'sourceUrl'
          && normalizedSourceUrl.length > 0
          && !this.validateUrl(normalizedSourceUrl)) {
          logger.info(
            TAG,
            `导入条目URL修正: index=${i + 1}, sourceUrl无效=${resolvedUrl.rawSourceUrl}, 已使用${resolvedUrl.selectedFrom}=${normalizedUrl}`
          );
        }
        if (!this.validateUrl(normalizedUrl)) {
          failed++;
          const message = `第 ${i + 1} 项 URL 不合法: ${resolvedUrl.selectedUrl}`;
          errors.push(message);
          logger.warn(
            TAG,
            `导入条目跳过: index=${i + 1}, 原因=URL不合法, 来源=${resolvedUrl.selectedFrom}, url=${resolvedUrl.selectedUrl}`
          );
          continue;
        }
        if (importSeenUrls.has(normalizedUrl)) {
          skipped++;
          logger.info(TAG, `导入条目跳过: index=${i + 1}, 原因=本次导入重复URL, url=${normalizedUrl}`);
          continue;
        }
        importSeenUrls.add(normalizedUrl);

        const existing = await this.dataManager.getSourceByUrl(normalizedUrl);
        if (existing && conflictPolicy === 'skip') {
          skipped++;
          logger.info(TAG, `导入条目跳过: index=${i + 1}, 策略=skip, 已存在源=${existing.name}, url=${normalizedUrl}`);
          continue;
        }

        const sourceName = name.length > 0 ? name : normalizedUrl;
        const source = await this.addSource(sourceName, normalizedUrl, groupName);
        const payload = this.buildImportPayload(sourceObj, source);
        await this.updateSource(source.id, payload);
        success++;
        if (existing) {
          updated++;
        } else {
          created++;
        }
        logger.debug(TAG, `导入条目成功: index=${i + 1}, sourceId=${source.id}, url=${normalizedUrl}`);
      } catch (error) {
        const errorText = this.resolveErrorText(error as RssErrorValue);
        failed++;
        errors.push(`第 ${i + 1} 项导入失败: ${errorText}`);
        logger.warn(TAG, `导入条目失败: index=${i + 1}, 原因=${errorText}`);
      }
    }

    logger.info(
      TAG,
      `JSON 导入完成: 策略=${conflictPolicy}, 总计=${list.length}, 成功=${success}, 新增=${created}, 更新=${updated}, 失败=${failed}, 跳过=${skipped}`
    );
    return {
      total: list.length,
      success,
      failed,
      skipped,
      created,
      updated,
      errors
    } as RssImportResult;
  }

  async importSourcesFromUrl(
    url: string,
    conflictPolicy: RssImportConflictPolicy = 'overwrite'
  ): Promise<RssImportResult> {
    this.ensureInitialized();
    const normalizedUrl = this.normalizeUrl(url);
    if (!this.validateUrl(normalizedUrl)) {
      throw new Error('网络导入链接不合法，请输入 http:// 或 https:// 地址');
    }

    logger.info(TAG, `开始网络导入订阅源: url=${normalizedUrl}, 策略=${conflictPolicy}`);
    try {
      const responseText = await this.fetchTextByUrl(normalizedUrl, URL_IMPORT_TIMEOUT);
      const result = await this.importSourcesFromJson(responseText, conflictPolicy);
      logger.info(
        TAG,
        `网络导入完成: url=${normalizedUrl}, 策略=${conflictPolicy}, 总计=${result.total}, 成功=${result.success}, 新增=${result.created}, 更新=${result.updated}, 失败=${result.failed}, 跳过=${result.skipped}`
      );
      return result;
    } catch (error) {
      const errorText = this.resolveErrorText(error as RssErrorValue);
      logger.error(TAG, `网络导入订阅源失败: url=${normalizedUrl}, ${errorText}`);
      throw new Error(errorText);
    }
  }
}

export function getRssSubscriptionManager(): RssSubscriptionManager {
  return RssSubscriptionManager.getInstance();
}
