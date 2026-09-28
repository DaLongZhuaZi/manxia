import { common } from '@kit.AbilityKit';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import {
  createAutoDownloadAction,
  createCheckAction,
  createConditionMatchModeCondition,
  createExcludeNsfwCondition,
  createMinNewItemsCondition,
  createNotifyAction,
  createOnlyFavoriteCondition,
  createSourceKeywordCondition,
  createTagKeywordCondition,
  createTitleKeywordCondition,
  DEFAULT_SUBSCRIPTION_CREATE_OPTIONS,
  SubscriptionAction,
  SubscriptionActionType,
  SubscriptionCheckpoint,
  SubscriptionCondition,
  SubscriptionConditionMatchMode,
  SubscriptionConditionType,
  SubscriptionContentType,
  SubscriptionExecutionRecord,
  SubscriptionExecutionStatus,
  SubscriptionProviderType,
  SubscriptionRule,
  SubscriptionRuleCreateOptions,
  SubscriptionRuleRunResult,
  SubscriptionTargetPreview,
  SubscriptionTargetPreviewCandidate,
  SubscriptionTargetPreviewCounter,
  SubscriptionTargetType
} from 'manxia_core/src/main/ets/Models/SubscriptionModels';
import { getSubscriptionDataManager, SubscriptionDataManager } from './SubscriptionDataManager';
import { getNovelInitializer } from '../Novel/NovelInitializer';
import { getNovelDataManager, NovelBook } from '../Novel/NovelDataManager';
import { getNovelSourceManager, NovelSourceManager } from '../Novel/NovelSourceManager';
import { LegadoBook, LegadoBookSource, LegadoBookSourceType, LegadoChapter } from 'manxia_novel/src/main/ets/Framework/Novel/LegadoSourceTypes';
import {
  getUnifiedDownloadManager,
  UnifiedDownloadManager,
  MangaChapterDownloadItem,
  MangaBatchDownloadResult
} from '../Download/UnifiedDownloadManager';
import { AppNotificationManager, NotificationType } from 'manxia_core/src/main/ets/Framework/Managers/NotificationManager';
import { Manga, MangaChapter, MangaPage } from 'manxia_core/src/main/ets/Models/MangaModels';
import { ParsedRemoteMangaId, RemoteLibraryMangaBridge } from '../Source/RemoteLibraryMangaBridge';
import { BookshelfCategoryManager, CategoryItem, ContentType } from '../Data/BookshelfCategoryManager';
import { DynamicMatchItem, DynamicShelfFilter, getTypeShelfManager, matchesDynamicFilter, ShelfContentType, ShelfType, TypeShelf, TypeShelfManager } from '../Data/TypeShelfManager';
import { SettingsManager } from 'manxia_core/src/main/ets/Framework/Managers/SettingsManager';
import { ComicInfo, DataManager, FavoriteInfo, OnlineChapterInfoInput } from '../Data/DataManager';
import { EBookDataManager } from 'manxia_core/src/main/ets/Framework/Data/EBookDataManager';
import { EBook } from 'manxia_core/src/main/ets/Models/EBookModels';
import { WebViewSourceManager } from '../WebView/WebViewSourceManager';
import { MangaSourceEngine } from '../WebView/MangaSourceEngine';
import { ChapterInfo as WebViewChapterInfo, PageInfo as WebViewPageInfo } from 'manxia_source_engine/src/main/ets/Framework/WebView/MangaSourceTypes';
import { eventBus, GameEvent, IEventPayload } from '../EventBus';

const TAG = 'SubscriptionManager';
const AUTO_RULE_SCAN_INTERVAL_MS = 60 * 1000;
const DEFAULT_USER_ID = 'default_user';

interface SubscriptionShelfCandidate {
  itemId: string;
  title: string;
  contentType: SubscriptionContentType;
  providerType: SubscriptionProviderType;
  sourceId: string;
  sourceName: string;
  isFavorite: boolean;
  authors: string[];
  tags: string[];
  isNSFW: boolean;
  localCount: number;
  latestItemTitle: string;
  novelBook: NovelBook | null;
  remoteManga: Manga | null;
  supported: boolean;
  unsupportedReason: string;
}

interface SubscriptionConditionSubject {
  title: string;
  tags: string[];
  sourceName: string;
  providerType: SubscriptionProviderType;
  isFavorite: boolean;
  isNSFW: boolean;
}

interface SubscriptionConditionEvaluation {
  label: string;
  matched: boolean;
  failureReason: string;
}

export class SubscriptionManager {
  private static instance: SubscriptionManager | null = null;

  private readonly dataManager: SubscriptionDataManager = getSubscriptionDataManager();
  private readonly appDataManager: DataManager = DataManager.getInstance();
  private readonly novelDataManager = getNovelDataManager();
  private readonly novelSourceManager: NovelSourceManager = getNovelSourceManager();
  private readonly remoteLibraryBridge: RemoteLibraryMangaBridge = RemoteLibraryMangaBridge.getInstance();
  private readonly unifiedDownloadManager: UnifiedDownloadManager = getUnifiedDownloadManager();
  private readonly notificationManager: AppNotificationManager = AppNotificationManager.getInstance();
  private readonly ebookDataManager: EBookDataManager = EBookDataManager.getInstance();
  private readonly settingsManager: SettingsManager = SettingsManager.getInstance();
  private readonly categoryManager: BookshelfCategoryManager = BookshelfCategoryManager.getInstance();
  private readonly typeShelfManager: TypeShelfManager = getTypeShelfManager();
  private readonly webViewSourceManager: WebViewSourceManager = WebViewSourceManager.getInstance();

  private isInitialized: boolean = false;
  private autoRunRegistered: boolean = false;
  private executionRunning: boolean = false;
  private lastAutoRunAt: number = 0;
  private context: common.UIAbilityContext | null = null;
  private readonly appEnterForegroundCallback = (_payload: IEventPayload): void => {
    void this.maybeRunDueRules('app_foreground');
  };

  private constructor() {
  }

  public static getInstance(): SubscriptionManager {
    if (SubscriptionManager.instance === null) {
      SubscriptionManager.instance = new SubscriptionManager();
    }
    return SubscriptionManager.instance;
  }

  public async initialize(context: common.UIAbilityContext): Promise<void> {
    if (this.isInitialized && this.dataManager.isReady()) {
      logger.debug(TAG, '统一内容跟踪模块已初始化，跳过重复初始化');
      return;
    }

    logger.info(TAG, '开始初始化统一内容跟踪模块');
    this.context = context;
    await this.dataManager.initialize(context);
    if (!getNovelInitializer().isReady()) {
      await getNovelInitializer().initialize(context);
    }
    this.unifiedDownloadManager.setContext(context);
    this.registerForegroundRunner();
    this.isInitialized = true;
    logger.info(TAG, '统一内容跟踪模块初始化完成');
  }

  public isReady(): boolean {
    return this.isInitialized && this.dataManager.isReady();
  }

  private ensureInitialized(): void {
    if (!this.isReady()) {
      throw new Error('更新提醒还没准备好');
    }
  }

  private registerForegroundRunner(): void {
    if (this.autoRunRegistered) {
      return;
    }

    try {
      eventBus.subscribe(GameEvent.APP_ENTER_FOREGROUND, this.appEnterForegroundCallback);
      this.autoRunRegistered = true;
      logger.info(TAG, '已注册前台内容跟踪到期检查事件');
    } catch (error) {
      logger.warn(TAG, `注册前台内容跟踪检查事件失败: ${String(error)}`);
    }
  }

  public async getAllRules(): Promise<SubscriptionRule[]> {
    this.ensureInitialized();
    return this.dataManager.getAllRules();
  }

  public async getRuleById(ruleId: string): Promise<SubscriptionRule | null> {
    this.ensureInitialized();
    return this.dataManager.getRuleById(ruleId);
  }

  public async getItemRule(
    contentType: SubscriptionContentType,
    targetId: string
  ): Promise<SubscriptionRule | null> {
    this.ensureInitialized();
    const rules = await this.dataManager.getRulesByTarget(
      SubscriptionTargetType.ITEM,
      contentType,
      targetId
    );
    if (rules.length <= 0) {
      return null;
    }
    return rules[0];
  }

  public async getExecutions(ruleId: string = '', limit: number = 50): Promise<SubscriptionExecutionRecord[]> {
    this.ensureInitialized();
    return this.dataManager.getExecutions(ruleId, limit);
  }

  public async getLatestExecution(ruleId: string): Promise<SubscriptionExecutionRecord | null> {
    this.ensureInitialized();
    return this.dataManager.getLatestExecution(ruleId);
  }

  public async saveRule(rule: SubscriptionRule): Promise<SubscriptionRule> {
    this.ensureInitialized();
    return this.dataManager.saveRule(this.normalizeRule(rule));
  }

  public async setRuleEnabled(ruleId: string, enabled: boolean): Promise<void> {
    this.ensureInitialized();
    await this.dataManager.setRuleEnabled(ruleId, enabled);
  }

  public async deleteRule(ruleId: string): Promise<void> {
    this.ensureInitialized();
    await this.dataManager.deleteRule(ruleId);
  }

  public async saveRuleWithCreateOptions(
    rule: SubscriptionRule,
    options?: Partial<SubscriptionRuleCreateOptions>
  ): Promise<SubscriptionRule> {
    this.ensureInitialized();
    const mergedOptions = this.mergeCreateOptions(options);
    const updatedRule: SubscriptionRule = {
      id: rule.id,
      name: mergedOptions.ruleName.length > 0 ? mergedOptions.ruleName : rule.name,
      enabled: rule.enabled,
      targetType: rule.targetType,
      contentType: rule.contentType,
      targetId: rule.targetId,
      targetTitle: rule.targetTitle,
      sourceId: rule.sourceId,
      sourceName: rule.sourceName,
      providerType: rule.providerType,
      checkIntervalMin: mergedOptions.checkIntervalMin,
      conditions: this.buildConditionsFromCreateOptions(mergedOptions),
      actions: this.buildActionsFromCreateOptions(mergedOptions),
      lastCheckTime: rule.lastCheckTime,
      lastSuccessTime: rule.lastSuccessTime,
      lastError: rule.lastError,
      lastTriggeredScene: rule.lastTriggeredScene,
      createTime: rule.createTime,
      updateTime: rule.updateTime
    };
    return this.saveRule(updatedRule);
  }

  private normalizeRule(rule: SubscriptionRule): SubscriptionRule {
    const now = Date.now();
    const normalizedConditions: SubscriptionCondition[] = [];
    for (let index = 0; index < rule.conditions.length; index++) {
      const item = rule.conditions[index];
      normalizedConditions.push({
        type: item.type,
        enabled: item.enabled === true,
        numericValue: item.numericValue > 0 ? Math.floor(item.numericValue) : 0,
        booleanValue: item.booleanValue === true,
        textValue: item.textValue ? item.textValue.trim() : ''
      });
    }

    const normalizedActions: SubscriptionAction[] = [];
    for (let index = 0; index < rule.actions.length; index++) {
      const item = rule.actions[index];
      normalizedActions.push({
        type: item.type,
        enabled: item.enabled === true,
        limitCount: item.limitCount > 0 ? Math.floor(item.limitCount) : 0,
      notifyTitle: item.notifyTitle ? item.notifyTitle.trim() : '',
      notifyText: item.notifyText ? item.notifyText.trim() : ''
      });
    }

    if (!this.hasActionType(normalizedActions, SubscriptionActionType.CHECK_UPDATE)) {
      normalizedActions.unshift(createCheckAction());
    }

    return {
      id: this.normalizeText(rule.id),
      name: this.normalizeText(rule.name),
      enabled: rule.enabled === true,
      targetType: rule.targetType,
      contentType: rule.contentType,
      targetId: this.normalizeText(rule.targetId),
      targetTitle: this.normalizeText(rule.targetTitle),
      sourceId: this.normalizeText(rule.sourceId),
      sourceName: this.normalizeText(rule.sourceName),
      providerType: rule.providerType,
      checkIntervalMin: rule.checkIntervalMin > 0 ? Math.floor(rule.checkIntervalMin) : 180,
      conditions: normalizedConditions,
      actions: normalizedActions,
      lastCheckTime: rule.lastCheckTime > 0 ? rule.lastCheckTime : 0,
      lastSuccessTime: rule.lastSuccessTime > 0 ? rule.lastSuccessTime : 0,
      lastError: rule.lastError ? rule.lastError.trim() : '',
      lastTriggeredScene: rule.lastTriggeredScene ? rule.lastTriggeredScene.trim() : '',
      createTime: rule.createTime > 0 ? rule.createTime : now,
      updateTime: now
    };
  }

  private normalizeText(value: string | undefined | null): string {
    if (value === undefined || value === null || typeof value !== 'string') {
      return '';
    }
    return value.trim();
  }

  private hasActionType(actions: SubscriptionAction[], actionType: SubscriptionActionType): boolean {
    for (let index = 0; index < actions.length; index++) {
      if (actions[index].type === actionType) {
        return true;
      }
    }
    return false;
  }

  private mergeCreateOptions(options?: Partial<SubscriptionRuleCreateOptions>): SubscriptionRuleCreateOptions {
    return {
      ruleName: options?.ruleName !== undefined ? this.normalizeText(options.ruleName) : DEFAULT_SUBSCRIPTION_CREATE_OPTIONS.ruleName,
      checkIntervalMin: options?.checkIntervalMin !== undefined && options.checkIntervalMin > 0
        ? Math.floor(options.checkIntervalMin)
        : DEFAULT_SUBSCRIPTION_CREATE_OPTIONS.checkIntervalMin,
      enableNotify: options?.enableNotify !== undefined
        ? options.enableNotify
        : DEFAULT_SUBSCRIPTION_CREATE_OPTIONS.enableNotify,
      autoDownloadCount: options?.autoDownloadCount !== undefined && options.autoDownloadCount > 0
        ? Math.floor(options.autoDownloadCount)
        : DEFAULT_SUBSCRIPTION_CREATE_OPTIONS.autoDownloadCount,
      conditionMatchMode: options?.conditionMatchMode !== undefined
        ? options.conditionMatchMode
        : DEFAULT_SUBSCRIPTION_CREATE_OPTIONS.conditionMatchMode,
      requireFavorite: options?.requireFavorite !== undefined
        ? options.requireFavorite
        : DEFAULT_SUBSCRIPTION_CREATE_OPTIONS.requireFavorite,
      minNewItems: options?.minNewItems !== undefined && options.minNewItems > 0
        ? Math.floor(options.minNewItems)
        : DEFAULT_SUBSCRIPTION_CREATE_OPTIONS.minNewItems,
      excludeNSFW: options?.excludeNSFW !== undefined
        ? options.excludeNSFW
        : DEFAULT_SUBSCRIPTION_CREATE_OPTIONS.excludeNSFW,
      titleKeyword: options?.titleKeyword !== undefined
        ? this.normalizeText(options.titleKeyword)
        : DEFAULT_SUBSCRIPTION_CREATE_OPTIONS.titleKeyword,
      tagKeyword: options?.tagKeyword !== undefined
        ? this.normalizeText(options.tagKeyword)
        : DEFAULT_SUBSCRIPTION_CREATE_OPTIONS.tagKeyword,
      sourceKeyword: options?.sourceKeyword !== undefined
        ? this.normalizeText(options.sourceKeyword)
        : DEFAULT_SUBSCRIPTION_CREATE_OPTIONS.sourceKeyword
    };
  }

  public async createNovelItemRule(
    bookId: string,
    options?: Partial<SubscriptionRuleCreateOptions>
  ): Promise<SubscriptionRule> {
    this.ensureInitialized();
    const book = await this.novelDataManager.getBook(bookId);
    if (book === null) {
      throw new Error('找不到这本小说，不能创建提醒');
    }

    const mergedOptions = this.mergeCreateOptions(options);
    const actions = this.buildActionsFromCreateOptions(mergedOptions);
    const conditions = this.buildConditionsFromCreateOptions(mergedOptions);
    const source = this.novelSourceManager.getSource(book.sourceId);
    const rule: SubscriptionRule = {
      id: '',
      name: mergedOptions.ruleName.length > 0 ? mergedOptions.ruleName : `小说提醒 - ${book.name}`,
      enabled: true,
      targetType: SubscriptionTargetType.ITEM,
      contentType: SubscriptionContentType.NOVEL,
      targetId: book.id,
      targetTitle: book.name,
      sourceId: book.sourceId,
      sourceName: book.sourceName,
      providerType: SubscriptionProviderType.LEGADO,
      checkIntervalMin: mergedOptions.checkIntervalMin,
      conditions: conditions,
      actions: actions,
      lastCheckTime: 0,
      lastSuccessTime: 0,
      lastError: '',
      lastTriggeredScene: '',
      createTime: Date.now(),
      updateTime: Date.now()
    };

    const savedRule = await this.saveRule(rule);
    const baselineInfo = await this.loadNovelBaseline(book, source);
    await this.dataManager.upsertCheckpoint({
      ruleId: savedRule.id,
      targetId: savedRule.targetId,
      contentId: savedRule.targetId,
      contentType: savedRule.contentType,
      remoteFingerprint: this.buildCountFingerprint(baselineInfo.remoteCount, baselineInfo.latestItemTitle),
      remoteCount: baselineInfo.remoteCount,
      localCount: baselineInfo.localCount,
      latestItemTitle: baselineInfo.latestItemTitle,
      lastSeenTime: Date.now(),
      updateTime: Date.now()
    });
    logger.info(TAG, `已创建小说内容跟踪规则: ${savedRule.name}`);
    return savedRule;
  }

  public async createOrUpdateNovelItemRule(
    bookId: string,
    options?: Partial<SubscriptionRuleCreateOptions>
  ): Promise<SubscriptionRule> {
    this.ensureInitialized();
    const book = await this.novelDataManager.getBook(bookId);
    if (book === null) {
      throw new Error('找不到这本小说，不能创建提醒');
    }

    const existingRule = await this.getItemRule(SubscriptionContentType.NOVEL, book.id);
    if (existingRule !== null) {
      return this.saveRuleWithCreateOptions(existingRule, options);
    }
    return this.createNovelItemRule(book.id, options);
  }

  public async createRemoteMangaItemRule(
    mangaId: string,
    options?: Partial<SubscriptionRuleCreateOptions>
  ): Promise<SubscriptionRule> {
    this.ensureInitialized();
    const baselineManga = await this.remoteLibraryBridge.loadRemoteMangaDetail(null, mangaId);
    if (baselineManga === null) {
      throw new Error('找不到这部漫画，不能创建提醒');
    }

    const mergedOptions = this.mergeCreateOptions(options);
    const actions = this.buildActionsFromCreateOptions(mergedOptions);
    const conditions = this.buildConditionsFromCreateOptions(mergedOptions);
    const providerType = this.resolveMangaProviderType(baselineManga);
    const rule: SubscriptionRule = {
      id: '',
      name: mergedOptions.ruleName.length > 0 ? mergedOptions.ruleName : `漫画提醒 - ${baselineManga.title}`,
      enabled: true,
      targetType: SubscriptionTargetType.ITEM,
      contentType: SubscriptionContentType.MANGA,
      targetId: baselineManga.id,
      targetTitle: baselineManga.title,
      sourceId: baselineManga.sourceInfo?.sourceId || '',
      sourceName: baselineManga.sourceInfo?.sourceName || '',
      providerType: providerType,
      checkIntervalMin: mergedOptions.checkIntervalMin,
      conditions: conditions,
      actions: actions,
      lastCheckTime: 0,
      lastSuccessTime: 0,
      lastError: '',
      lastTriggeredScene: '',
      createTime: Date.now(),
      updateTime: Date.now()
    };

    const savedRule = await this.saveRule(rule);
    const latestTitle = baselineManga.chapters.length > 0
      ? baselineManga.chapters[baselineManga.chapters.length - 1].title
      : '';
    await this.dataManager.upsertCheckpoint({
      ruleId: savedRule.id,
      targetId: savedRule.targetId,
      contentId: savedRule.targetId,
      contentType: savedRule.contentType,
      remoteFingerprint: this.buildCountFingerprint(baselineManga.chapters.length, latestTitle),
      remoteCount: baselineManga.chapters.length,
      localCount: baselineManga.chapters.length,
      latestItemTitle: latestTitle,
      lastSeenTime: Date.now(),
      updateTime: Date.now()
    });
    logger.info(TAG, `已创建远程漫画内容跟踪规则: ${savedRule.name}`);
    return savedRule;
  }

  public async createOrUpdateRemoteMangaItemRule(
    mangaId: string,
    options?: Partial<SubscriptionRuleCreateOptions>
  ): Promise<SubscriptionRule> {
    this.ensureInitialized();
    const existingRule = await this.getItemRule(SubscriptionContentType.MANGA, mangaId);
    if (existingRule !== null) {
      return this.saveRuleWithCreateOptions(existingRule, options);
    }
    return this.createRemoteMangaItemRule(mangaId, options);
  }

  public async createOnlineMangaItemRule(
    comicId: string,
    options?: Partial<SubscriptionRuleCreateOptions>
  ): Promise<SubscriptionRule> {
    this.ensureInitialized();
    const comicInfo = await this.appDataManager.getComicById(comicId);
    if (comicInfo === null) {
      throw new Error('找不到这部漫画，不能创建提醒');
    }

    const externalId = comicInfo.externalId || '';
    if (externalId.length <= 0) {
      throw new Error('漫画缺少外部ID，不能创建提醒');
    }

    const mergedOptions = this.mergeCreateOptions(options);
    const actions = this.buildActionsFromCreateOptions(mergedOptions);
    const conditions = this.buildConditionsFromCreateOptions(mergedOptions);
    const sourceName = await this.resolveMangaSourceName(comicInfo);
    const rule: SubscriptionRule = {
      id: '',
      name: mergedOptions.ruleName.length > 0 ? mergedOptions.ruleName : `漫画提醒 - ${comicInfo.title}`,
      enabled: true,
      targetType: SubscriptionTargetType.ITEM,
      contentType: SubscriptionContentType.MANGA,
      targetId: comicInfo.id,
      targetTitle: comicInfo.title,
      sourceId: comicInfo.sourceId,
      sourceName: sourceName,
      providerType: SubscriptionProviderType.WEBVIEW,
      checkIntervalMin: mergedOptions.checkIntervalMin,
      conditions: conditions,
      actions: actions,
      lastCheckTime: 0,
      lastSuccessTime: 0,
      lastError: '',
      lastTriggeredScene: '',
      createTime: Date.now(),
      updateTime: Date.now()
    };

    const savedRule = await this.saveRule(rule);
    await this.dataManager.upsertCheckpoint({
      ruleId: savedRule.id,
      targetId: savedRule.targetId,
      contentId: savedRule.targetId,
      contentType: savedRule.contentType,
      remoteFingerprint: this.buildCountFingerprint(comicInfo.chapterCount, ''),
      remoteCount: comicInfo.chapterCount,
      localCount: comicInfo.chapterCount,
      latestItemTitle: '',
      lastSeenTime: Date.now(),
      updateTime: Date.now()
    });
    logger.info(TAG, `已创建在线漫画内容跟踪规则: ${savedRule.name}`);
    return savedRule;
  }

  public async createOrUpdateOnlineMangaItemRule(
    comicId: string,
    options?: Partial<SubscriptionRuleCreateOptions>
  ): Promise<SubscriptionRule> {
    this.ensureInitialized();
    const existingRule = await this.getItemRule(SubscriptionContentType.MANGA, comicId);
    if (existingRule !== null) {
      return this.saveRuleWithCreateOptions(existingRule, options);
    }
    return this.createOnlineMangaItemRule(comicId, options);
  }

  public async createShelfRule(
    shelfId: string,
    options?: Partial<SubscriptionRuleCreateOptions>
  ): Promise<SubscriptionRule> {
    this.ensureInitialized();
    const shelfReady = await this.ensureShelfManagersReady();
    if (!shelfReady) {
      throw new Error('书架还没准备好，暂时不能创建提醒');
    }

    const shelf = this.typeShelfManager.getShelf(shelfId);
    if (shelf === undefined) {
      throw new Error('找不到这个书架，不能创建提醒');
    }

    const mergedOptions = this.mergeCreateOptions(options);
    const rule: SubscriptionRule = {
      id: '',
      name: mergedOptions.ruleName.length > 0
        ? mergedOptions.ruleName
        : `${shelf.shelfType === ShelfType.DYNAMIC ? '动态书架提醒' : '书架提醒'} - ${shelf.name}`,
      enabled: true,
      targetType: shelf.shelfType === ShelfType.DYNAMIC
        ? SubscriptionTargetType.DYNAMIC_SHELF
        : SubscriptionTargetType.SHELF,
      contentType: this.resolveShelfContentType(shelf),
      targetId: shelf.id,
      targetTitle: shelf.name,
      sourceId: '',
      sourceName: '',
      providerType: SubscriptionProviderType.NONE,
      checkIntervalMin: mergedOptions.checkIntervalMin,
      conditions: this.buildConditionsFromCreateOptions(mergedOptions),
      actions: this.buildActionsFromCreateOptions(mergedOptions),
      lastCheckTime: 0,
      lastSuccessTime: 0,
      lastError: '',
      lastTriggeredScene: '',
      createTime: Date.now(),
      updateTime: Date.now()
    };

    const savedRule = await this.saveRule(rule);
    await this.seedShelfRuleCheckpoints(savedRule, shelf);
    logger.info(TAG, `已创建书架内容跟踪规则: ${savedRule.name}`);
    return savedRule;
  }

  public async createSuwayomiLibraryRule(
    options?: Partial<SubscriptionRuleCreateOptions>
  ): Promise<SubscriptionRule> {
    return this.createProviderLibraryRule(SubscriptionProviderType.SUWAYOMI, '', '', options);
  }

  public async createKomgaLibraryRule(
    instanceId: string = '',
    instanceTitle: string = '',
    options?: Partial<SubscriptionRuleCreateOptions>
  ): Promise<SubscriptionRule> {
    return this.createProviderLibraryRule(SubscriptionProviderType.KOMGA, instanceId, instanceTitle, options);
  }

  public async createProviderLibraryRule(
    providerType: SubscriptionProviderType,
    instanceId: string = '',
    instanceTitle: string = '',
    options?: Partial<SubscriptionRuleCreateOptions>
  ): Promise<SubscriptionRule> {
    this.ensureInitialized();
    if (providerType !== SubscriptionProviderType.SUWAYOMI && providerType !== SubscriptionProviderType.KOMGA) {
      throw new Error('目前只支持给 Suwayomi 或 Komga 远程库创建提醒');
    }

    const normalizedInstanceId = this.normalizeProviderLibraryInstanceId(providerType, instanceId);
    const targetId = this.buildProviderLibraryTargetId(providerType, normalizedInstanceId);
    const targetTitle = this.buildProviderLibraryTitle(providerType, normalizedInstanceId, instanceTitle);
    const mergedOptions = this.mergeCreateOptions(options);
    const rule: SubscriptionRule = {
      id: '',
      name: mergedOptions.ruleName.length > 0
        ? mergedOptions.ruleName
        : `远程库提醒 - ${targetTitle}`,
      enabled: true,
      targetType: SubscriptionTargetType.PROVIDER_LIBRARY,
      contentType: SubscriptionContentType.MANGA,
      targetId: targetId,
      targetTitle: targetTitle,
      sourceId: '',
      sourceName: targetTitle,
      providerType: providerType,
      checkIntervalMin: mergedOptions.checkIntervalMin,
      conditions: this.buildConditionsFromCreateOptions(mergedOptions),
      actions: this.buildActionsFromCreateOptions(mergedOptions),
      lastCheckTime: 0,
      lastSuccessTime: 0,
      lastError: '',
      lastTriggeredScene: '',
      createTime: Date.now(),
      updateTime: Date.now()
    };

    const savedRule = await this.saveRule(rule);
    const candidates = await this.resolveProviderLibraryCandidates(providerType, normalizedInstanceId, false);
    await this.seedCandidateCheckpoints(savedRule, candidates);
    logger.info(TAG, `已创建远程库内容跟踪规则: ${savedRule.name}`);
    return savedRule;
  }

  public async previewShelfTarget(shelfId: string): Promise<SubscriptionTargetPreview> {
    this.ensureInitialized();
    const shelfReady = await this.ensureShelfManagersReady();
    if (!shelfReady) {
      throw new Error('书架还没准备好，暂时不能查看包含内容');
    }

    const shelf = this.typeShelfManager.getShelf(shelfId);
    if (shelf === undefined) {
      throw new Error('找不到这个书架，暂时不能查看包含内容');
    }

    const targetType = shelf.shelfType === ShelfType.DYNAMIC
      ? SubscriptionTargetType.DYNAMIC_SHELF
      : SubscriptionTargetType.SHELF;
    const candidates = await this.resolveShelfCandidates(shelf, true);
    return this.buildTargetPreview(
      targetType,
      shelf.id,
      shelf.name,
      this.resolveShelfContentType(shelf),
      candidates
    );
  }

  public async previewProviderLibraryTarget(
    providerType: SubscriptionProviderType,
    instanceId: string = '',
    instanceTitle: string = ''
  ): Promise<SubscriptionTargetPreview> {
    this.ensureInitialized();
    if (providerType !== SubscriptionProviderType.SUWAYOMI && providerType !== SubscriptionProviderType.KOMGA) {
      throw new Error('目前只能查看 Suwayomi 或 Komga 远程库会包含哪些内容');
    }

    const normalizedInstanceId = this.normalizeProviderLibraryInstanceId(providerType, instanceId);
    const candidates = await this.resolveProviderLibraryCandidates(providerType, normalizedInstanceId, true);
    return this.buildTargetPreview(
      SubscriptionTargetType.PROVIDER_LIBRARY,
      this.buildProviderLibraryTargetId(providerType, normalizedInstanceId),
      this.buildProviderLibraryTitle(providerType, normalizedInstanceId, instanceTitle),
      SubscriptionContentType.MANGA,
      candidates
    );
  }

  public async previewRuleTarget(ruleId: string): Promise<SubscriptionTargetPreview> {
    this.ensureInitialized();
    const rule = await this.dataManager.getRuleById(ruleId);
    if (rule === null) {
      throw new Error('找不到这条提醒，暂时不能查看包含内容');
    }

    if (rule.targetType === SubscriptionTargetType.SHELF || rule.targetType === SubscriptionTargetType.DYNAMIC_SHELF) {
      const shelfReady = await this.ensureShelfManagersReady();
      if (!shelfReady) {
        throw new Error('书架还没准备好，暂时不能查看包含内容');
      }
      const shelf = this.typeShelfManager.getShelf(rule.targetId);
      if (shelf === undefined) {
        throw new Error('找不到这个书架，暂时不能查看包含内容');
      }
      const candidates = await this.resolveShelfCandidates(shelf, true);
      return this.buildTargetPreview(
        rule.targetType,
        rule.targetId,
        rule.targetTitle,
        this.resolveShelfContentType(shelf),
        candidates,
        rule
      );
    }
    if (rule.targetType === SubscriptionTargetType.PROVIDER_LIBRARY) {
      const candidates = await this.resolveProviderLibraryCandidates(
        rule.providerType,
        this.normalizeProviderLibraryInstanceId(rule.providerType, rule.targetId),
        true
      );
      return this.buildTargetPreview(
        SubscriptionTargetType.PROVIDER_LIBRARY,
        rule.targetId,
        rule.targetTitle,
        SubscriptionContentType.MANGA,
        candidates,
        rule
      );
    }

    const candidates = await this.resolveItemPreviewCandidates(rule);
    return this.buildTargetPreview(
      SubscriptionTargetType.ITEM,
      rule.targetId,
      rule.targetTitle,
      rule.contentType,
      candidates,
      rule
    );
  }

  private resolveShelfContentType(shelf: TypeShelf): SubscriptionContentType {
    if (shelf.contentTypes.length !== 1) {
      return SubscriptionContentType.MIXED;
    }

    const contentType = shelf.contentTypes[0];
    if (contentType === ShelfContentType.NOVEL) {
      return SubscriptionContentType.NOVEL;
    }
    if (contentType === ShelfContentType.EBOOK) {
      return SubscriptionContentType.EBOOK;
    }
    return SubscriptionContentType.MANGA;
  }

  private async seedShelfRuleCheckpoints(rule: SubscriptionRule, shelf: TypeShelf): Promise<void> {
    const candidates = await this.resolveShelfCandidates(shelf, false);
    await this.seedCandidateCheckpoints(rule, candidates);
  }

  private async seedCandidateCheckpoints(
    rule: SubscriptionRule,
    candidates: SubscriptionShelfCandidate[]
  ): Promise<void> {
    for (let index = 0; index < candidates.length; index++) {
      const checkpoint = this.buildBaselineCheckpointFromCandidate(rule, candidates[index]);
      if (checkpoint !== null) {
        await this.dataManager.upsertCheckpoint(checkpoint);
      }
    }
  }

  private async resolveItemPreviewCandidates(rule: SubscriptionRule): Promise<SubscriptionShelfCandidate[]> {
    if (rule.contentType === SubscriptionContentType.NOVEL) {
      const candidate = await this.resolveNovelCandidateById(rule.targetId);
      return candidate !== null ? [candidate] : [];
    }
    if (rule.contentType === SubscriptionContentType.EBOOK) {
      const candidate = await this.resolveEBookCandidateById(rule.targetId);
      return candidate !== null ? [candidate] : [];
    }
    if (rule.contentType === SubscriptionContentType.MANGA) {
      const favoriteMap = await this.loadFavoriteInfoMap();
      const candidate = await this.resolveMangaCandidateById(
        rule.targetId,
        true,
        favoriteMap.get(rule.targetId) || null
      );
      return candidate !== null ? [candidate] : [];
    }
    return [];
  }

  private buildBaselineCheckpointFromCandidate(
    rule: SubscriptionRule,
    candidate: SubscriptionShelfCandidate
  ): SubscriptionCheckpoint | null {
    if (!candidate.supported) {
      return null;
    }

    const now = Date.now();
    return {
      ruleId: rule.id,
      targetId: candidate.itemId,
      contentId: candidate.itemId,
      contentType: candidate.contentType,
      remoteFingerprint: this.buildCountFingerprint(candidate.localCount, candidate.latestItemTitle),
      remoteCount: candidate.localCount,
      localCount: candidate.localCount,
      latestItemTitle: candidate.latestItemTitle,
      lastSeenTime: now,
      updateTime: now
    };
  }

  private async loadNovelBaseline(book: NovelBook, source: LegadoBookSource | null): Promise<SubscriptionCheckpoint> {
    const now = Date.now();
    let remoteCount = book.chapterCount;
    let latestItemTitle = book.latestChapterTitle || '';
    try {
      const remoteBook = this.buildLegadoBook(book, source);
      const chapters = await this.novelSourceManager.getChapterList(book.sourceId, remoteBook);
      if (chapters.length > 0) {
        remoteCount = chapters.length;
        latestItemTitle = chapters[chapters.length - 1].title;
      }
    } catch (error) {
      logger.warn(TAG, `加载小说内容跟踪基线失败，回退本地章节数: ${String(error)}`);
    }

    return {
      ruleId: '',
      targetId: book.id,
      contentId: book.id,
      contentType: SubscriptionContentType.NOVEL,
      remoteFingerprint: this.buildCountFingerprint(remoteCount, latestItemTitle),
      remoteCount: remoteCount,
      localCount: book.chapterCount,
      latestItemTitle: latestItemTitle,
      lastSeenTime: now,
      updateTime: now
    };
  }

  private buildActionsFromCreateOptions(options: SubscriptionRuleCreateOptions): SubscriptionAction[] {
    const actions: SubscriptionAction[] = [createCheckAction()];
    if (options.enableNotify) {
      actions.push(createNotifyAction());
    }
    if (options.autoDownloadCount > 0) {
      actions.push(createAutoDownloadAction(options.autoDownloadCount));
    }
    return actions;
  }

  private buildConditionsFromCreateOptions(options: SubscriptionRuleCreateOptions): SubscriptionCondition[] {
    const conditions: SubscriptionCondition[] = [
      createMinNewItemsCondition(options.minNewItems),
      createConditionMatchModeCondition(options.conditionMatchMode)
    ];
    if (options.requireFavorite) {
      conditions.push(createOnlyFavoriteCondition(true));
    }
    if (options.excludeNSFW) {
      conditions.push(createExcludeNsfwCondition(true));
    }
    if (options.titleKeyword.trim().length > 0) {
      conditions.push(createTitleKeywordCondition(options.titleKeyword));
    }
    if (options.tagKeyword.trim().length > 0) {
      conditions.push(createTagKeywordCondition(options.tagKeyword));
    }
    if (options.sourceKeyword.trim().length > 0) {
      conditions.push(createSourceKeywordCondition(options.sourceKeyword));
    }
    return conditions;
  }

  public async maybeRunDueRules(scene: string): Promise<SubscriptionRuleRunResult[]> {
    this.ensureInitialized();
    const now = Date.now();
    if (this.executionRunning) {
      logger.debug(TAG, `内容跟踪规则检查已在执行中，跳过: scene=${scene}`);
      return [];
    }
    if (scene !== 'manual' && this.lastAutoRunAt > 0 && (now - this.lastAutoRunAt) < AUTO_RULE_SCAN_INTERVAL_MS) {
      logger.debug(TAG, `内容跟踪规则自动检查触发过于频繁，已跳过: scene=${scene}`);
      return [];
    }

    const enabledRules = await this.dataManager.getEnabledRules();
    const dueRules: SubscriptionRule[] = [];
    for (let index = 0; index < enabledRules.length; index++) {
      const rule = enabledRules[index];
      if (this.isRuleDue(rule, now)) {
        dueRules.push(rule);
      }
    }

    if (scene !== 'manual') {
      this.lastAutoRunAt = now;
    }

    if (dueRules.length === 0) {
      logger.info(TAG, `无到期内容跟踪规则: scene=${scene}`);
      return [];
    }

    logger.info(TAG, `开始执行到期内容跟踪规则: scene=${scene}, 总数=${dueRules.length}`);
    this.executionRunning = true;
    const results: SubscriptionRuleRunResult[] = [];
    try {
      for (let index = 0; index < dueRules.length; index++) {
        const result = await this.executeRuleInternal(dueRules[index], scene);
        results.push(result);
      }
    } finally {
      this.executionRunning = false;
    }
    return results;
  }

  public async runRuleNow(ruleId: string, scene: string = 'manual'): Promise<SubscriptionRuleRunResult> {
    this.ensureInitialized();
    const rule = await this.dataManager.getRuleById(ruleId);
    if (rule === null) {
      throw new Error('找不到这条提醒');
    }
    return this.executeRuleInternal(rule, scene);
  }

  private isRuleDue(rule: SubscriptionRule, now: number): boolean {
    if (!rule.enabled) {
      return false;
    }
    const baseTimestamp = rule.lastSuccessTime > 0 ? rule.lastSuccessTime : rule.lastCheckTime;
    if (baseTimestamp <= 0) {
      return true;
    }
    const intervalMin = rule.checkIntervalMin > 0 ? rule.checkIntervalMin : 180;
    return now >= (baseTimestamp + intervalMin * 60 * 1000);
  }

  private async executeRuleInternal(rule: SubscriptionRule, scene: string): Promise<SubscriptionRuleRunResult> {
    const startedAt = Date.now();
    let result: SubscriptionRuleRunResult;
    try {
      if (rule.targetType === SubscriptionTargetType.SHELF || rule.targetType === SubscriptionTargetType.DYNAMIC_SHELF) {
        result = await this.executeShelfRule(rule, scene);
      } else if (rule.targetType === SubscriptionTargetType.PROVIDER_LIBRARY) {
        result = await this.executeProviderLibraryRule(rule, scene);
      } else if (rule.targetType !== SubscriptionTargetType.ITEM) {
        result = this.buildSimpleResult(
          rule,
          SubscriptionExecutionStatus.UNSUPPORTED,
          '这种对象暂时还不能自动检查'
        );
      } else if (rule.contentType === SubscriptionContentType.NOVEL) {
        result = await this.executeNovelRule(rule, scene);
      } else if (rule.contentType === SubscriptionContentType.MANGA) {
        result = await this.executeMangaRule(rule, scene);
      } else {
        result = this.buildSimpleResult(
          rule,
          SubscriptionExecutionStatus.UNSUPPORTED,
          '这类内容暂时还不能自动检查'
        );
      }
    } catch (error) {
      const errorMessage = `检查失败: ${String(error)}`;
      logger.error(TAG, `${rule.name} 执行异常: ${errorMessage}`);
      result = this.buildSimpleResult(rule, SubscriptionExecutionStatus.FAILED, errorMessage);
    }

    const lastSuccessTime = result.status === SubscriptionExecutionStatus.FAILED ? rule.lastSuccessTime : startedAt;
    const lastError = result.status === SubscriptionExecutionStatus.FAILED ? result.message : '';
    await this.dataManager.updateRuleRuntimeState(rule.id, startedAt, lastSuccessTime, lastError, scene);
    await this.dataManager.saveExecution({
      id: '',
      ruleId: rule.id,
      status: result.status,
      triggerScene: scene,
      targetId: rule.targetId,
      targetTitle: rule.targetTitle,
      contentType: rule.contentType,
      checkedAt: startedAt,
      localCount: result.localCount,
      remoteCount: result.remoteCount,
      deltaCount: result.deltaCount,
      downloadedCount: result.downloadedCount,
      message: result.message,
      actionSummary: result.actionSummary,
      createTime: startedAt
    });
    await this.dataManager.trimExecutions(rule.id);
    if (result.checkpoint !== null) {
      await this.dataManager.upsertCheckpoint(result.checkpoint);
    }
    if (result.checkpoints !== undefined && result.checkpoints.length > 0) {
      for (let index = 0; index < result.checkpoints.length; index++) {
        await this.dataManager.upsertCheckpoint(result.checkpoints[index]);
      }
    }
    return result;
  }

  private buildSimpleResult(
    rule: SubscriptionRule,
    status: SubscriptionExecutionStatus,
    message: string
  ): SubscriptionRuleRunResult {
    return {
      rule: rule,
      status: status,
      hasUpdate: false,
      localCount: 0,
      remoteCount: 0,
      deltaCount: 0,
      downloadedCount: 0,
      message: message,
      actionSummary: '',
      latestItemTitle: '',
      checkpoint: null
    };
  }

  private async executeNovelRule(rule: SubscriptionRule, scene: string): Promise<SubscriptionRuleRunResult> {
    const book = await this.novelDataManager.getBook(rule.targetId);
    if (book === null) {
      return this.buildSimpleResult(rule, SubscriptionExecutionStatus.FAILED, '这本小说已经不存在了');
    }

    const conditionSubject = this.buildConditionSubjectFromNovel(book);
    const conditionSkipReason = this.resolveConditionSkipReason(rule.conditions, conditionSubject);
    if (conditionSkipReason.length > 0) {
      return this.buildSimpleResult(rule, SubscriptionExecutionStatus.SKIPPED, conditionSkipReason);
    }

    const checkpoint = await this.dataManager.getCheckpoint(rule.id, rule.targetId, rule.targetId);
    const source = this.novelSourceManager.getSource(book.sourceId);
    const remoteBook = this.buildLegadoBook(book, source);
    const chapters = await this.novelSourceManager.getChapterList(book.sourceId, remoteBook);
    if (chapters.length <= 0) {
      return this.buildSimpleResult(rule, SubscriptionExecutionStatus.FAILED, '没拿到章节列表');
    }

    const localCount = book.chapterCount;
    const remoteCount = chapters.length;
    const latestItemTitle = chapters[chapters.length - 1].title;
    const seenCount = this.resolveSeenCount(localCount, checkpoint);
    const deltaCount = remoteCount > seenCount ? (remoteCount - seenCount) : 0;
    const minNewItems = this.resolveMinNewItems(rule.conditions);

    if (deltaCount < minNewItems) {
      const status = deltaCount > 0 ? SubscriptionExecutionStatus.NO_UPDATE : SubscriptionExecutionStatus.NO_UPDATE;
      const message = deltaCount > 0
        ? `发现 ${deltaCount} 个新章节，但还没达到你设定的 ${minNewItems}`
        : '这本小说还没有新章节';
      return {
        rule: rule,
        status: status,
        hasUpdate: false,
        localCount: localCount,
        remoteCount: remoteCount,
        deltaCount: deltaCount,
        downloadedCount: 0,
        message: message,
        actionSummary: '',
        latestItemTitle: latestItemTitle,
        checkpoint: deltaCount > 0 ? null : this.buildCheckpoint(rule, localCount, remoteCount, latestItemTitle)
      };
    }

    let downloadedCount = 0;
    const actionSummaryParts: string[] = [];
    if (deltaCount > 0) {
      if (this.isActionEnabled(rule.actions, SubscriptionActionType.NOTIFY)) {
        await this.sendUpdateNotification(rule, deltaCount, latestItemTitle);
        actionSummaryParts.push('notify');
      }
      const downloadAction = this.getAction(rule.actions, SubscriptionActionType.AUTO_DOWNLOAD_NEW);
      if (downloadAction !== null && downloadAction.enabled) {
        downloadedCount = await this.triggerNovelAutoDownload(book, chapters, seenCount, downloadAction.limitCount);
        if (downloadedCount > 0) {
          actionSummaryParts.push(`auto_download:${downloadedCount}`);
        }
      }
      return {
        rule: rule,
        status: SubscriptionExecutionStatus.SUCCESS,
        hasUpdate: true,
        localCount: localCount,
        remoteCount: remoteCount,
        deltaCount: deltaCount,
        downloadedCount: downloadedCount,
        message: `发现 ${deltaCount} 个新章节`,
        actionSummary: this.joinSummaryParts(actionSummaryParts),
        latestItemTitle: latestItemTitle,
        checkpoint: this.buildCheckpoint(rule, localCount, remoteCount, latestItemTitle)
      };
    }

    return {
      rule: rule,
      status: SubscriptionExecutionStatus.NO_UPDATE,
      hasUpdate: false,
      localCount: localCount,
      remoteCount: remoteCount,
      deltaCount: 0,
      downloadedCount: 0,
      message: '这本小说还没有新章节',
      actionSummary: '',
      latestItemTitle: latestItemTitle,
      checkpoint: this.buildCheckpoint(rule, localCount, remoteCount, latestItemTitle)
    };
  }

  private async executeMangaRule(rule: SubscriptionRule, scene: string): Promise<SubscriptionRuleRunResult> {
    if (rule.providerType === SubscriptionProviderType.WEBVIEW) {
      return await this.executeOnlineMangaRule(rule, scene);
    }

    const cachedManga = await this.remoteLibraryBridge.getCachedMangaById(rule.targetId);
    const remoteManga = await this.remoteLibraryBridge.loadRemoteMangaDetail(cachedManga, rule.targetId);
    if (remoteManga === null) {
      return this.buildSimpleResult(rule, SubscriptionExecutionStatus.FAILED, '没拿到漫画详情');
    }

    const conditionSubject = this.buildConditionSubjectFromManga(remoteManga);
    const conditionSkipReason = this.resolveConditionSkipReason(rule.conditions, conditionSubject);
    if (conditionSkipReason.length > 0) {
      return this.buildSimpleResult(rule, SubscriptionExecutionStatus.SKIPPED, conditionSkipReason);
    }

    const checkpoint = await this.dataManager.getCheckpoint(rule.id, rule.targetId, rule.targetId);
    const localCount = cachedManga !== null ? cachedManga.chapters.length : 0;
    const remoteCount = remoteManga.chapters.length;
    const latestItemTitle = remoteCount > 0 ? remoteManga.chapters[remoteCount - 1].title : '';
    const seenCount = this.resolveSeenCount(localCount, checkpoint);
    const deltaCount = remoteCount > seenCount ? (remoteCount - seenCount) : 0;
    const minNewItems = this.resolveMinNewItems(rule.conditions);

    if (deltaCount < minNewItems) {
      const message = deltaCount > 0
        ? `发现 ${deltaCount} 个新章节，但还没达到你设定的 ${minNewItems}`
        : '这部漫画还没有新章节';
      return {
        rule: rule,
        status: SubscriptionExecutionStatus.NO_UPDATE,
        hasUpdate: false,
        localCount: localCount,
        remoteCount: remoteCount,
        deltaCount: deltaCount,
        downloadedCount: 0,
        message: message,
        actionSummary: '',
        latestItemTitle: latestItemTitle,
        checkpoint: deltaCount > 0 ? null : this.buildCheckpoint(rule, localCount, remoteCount, latestItemTitle)
      };
    }

    let downloadedCount = 0;
    const actionSummaryParts: string[] = [];
    if (deltaCount > 0) {
      if (this.isActionEnabled(rule.actions, SubscriptionActionType.NOTIFY)) {
        await this.sendUpdateNotification(rule, deltaCount, latestItemTitle);
        actionSummaryParts.push('notify');
      }
      const downloadAction = this.getAction(rule.actions, SubscriptionActionType.AUTO_DOWNLOAD_NEW);
      if (downloadAction !== null && downloadAction.enabled) {
        downloadedCount = await this.triggerRemoteMangaAutoDownload(remoteManga, seenCount, downloadAction.limitCount);
        if (downloadedCount > 0) {
          actionSummaryParts.push(`auto_download:${downloadedCount}`);
        }
      }
      return {
        rule: rule,
        status: SubscriptionExecutionStatus.SUCCESS,
        hasUpdate: true,
        localCount: localCount,
        remoteCount: remoteCount,
        deltaCount: deltaCount,
        downloadedCount: downloadedCount,
        message: `发现 ${deltaCount} 个新章节`,
        actionSummary: this.joinSummaryParts(actionSummaryParts),
        latestItemTitle: latestItemTitle,
        checkpoint: this.buildCheckpoint(rule, localCount, remoteCount, latestItemTitle)
      };
    }

    return {
      rule: rule,
      status: SubscriptionExecutionStatus.NO_UPDATE,
      hasUpdate: false,
      localCount: localCount,
      remoteCount: remoteCount,
      deltaCount: 0,
      downloadedCount: 0,
      message: '这部漫画还没有新章节',
      actionSummary: '',
      latestItemTitle: latestItemTitle,
      checkpoint: this.buildCheckpoint(rule, localCount, remoteCount, latestItemTitle)
    };
  }

  private async executeOnlineMangaRule(rule: SubscriptionRule, scene: string): Promise<SubscriptionRuleRunResult> {
    const comicInfo = await this.appDataManager.getComicById(rule.targetId);
    if (comicInfo === null) {
      return this.buildSimpleResult(rule, SubscriptionExecutionStatus.FAILED, '找不到这部漫画');
    }

    const externalId = comicInfo.externalId || '';
    if (externalId.length <= 0) {
      return this.buildSimpleResult(rule, SubscriptionExecutionStatus.FAILED, '漫画缺少外部ID');
    }

    const sourceIdText = comicInfo.sourceId.trim();
    const sourceId = Number(sourceIdText);
    if (Number.isNaN(sourceId) || sourceId <= 0) {
      return this.buildSimpleResult(rule, SubscriptionExecutionStatus.FAILED, '漫画缺少图源ID');
    }

    const sourceName = await this.resolveMangaSourceName(comicInfo);

    let engine: MangaSourceEngine;
    try {
      engine = await this.webViewSourceManager.getMangaEngine(sourceId, sourceName);
    } catch (error) {
      logger.warn(TAG, `获取在线漫画引擎失败: ${rule.targetTitle}, ${String(error)}`);
      return this.buildSimpleResult(rule, SubscriptionExecutionStatus.FAILED, '获取图源引擎失败，可能需要先打开一次漫画详情页');
    }

    const chaptersResult = await engine.getChapterList(externalId);
    if (!chaptersResult.success || !chaptersResult.data || chaptersResult.data.length <= 0) {
      return this.buildSimpleResult(
        rule,
        SubscriptionExecutionStatus.FAILED,
        chaptersResult.error || '没拿到远程章节列表'
      );
    }

    const remoteChapters: WebViewChapterInfo[] = chaptersResult.data;
    await this.updateOnlineChaptersToDatabase(comicInfo.id, remoteChapters);

    const localChapters = await this.appDataManager.getOnlineComicChapters(comicInfo.id);
    const localCount = localChapters.length;
    const remoteCount = remoteChapters.length;
    const latestItemTitle = remoteCount > 0 ? remoteChapters[remoteCount - 1].title : '';

    const conditionSubject: SubscriptionConditionSubject = {
      title: comicInfo.title,
      tags: comicInfo.tags ? comicInfo.tags.concat() : [],
      sourceName: sourceName,
      providerType: SubscriptionProviderType.WEBVIEW,
      isFavorite: true,
      isNSFW: comicInfo.isNSFW === true || comicInfo.isNSFW === 1
    };
    const conditionSkipReason = this.resolveConditionSkipReason(rule.conditions, conditionSubject);
    if (conditionSkipReason.length > 0) {
      return this.buildSimpleResult(rule, SubscriptionExecutionStatus.SKIPPED, conditionSkipReason);
    }

    const checkpoint = await this.dataManager.getCheckpoint(rule.id, rule.targetId, rule.targetId);
    const seenCount = this.resolveSeenCount(localCount, checkpoint);
    const deltaCount = remoteCount > seenCount ? (remoteCount - seenCount) : 0;
    const minNewItems = this.resolveMinNewItems(rule.conditions);

    if (deltaCount < minNewItems) {
      const message = deltaCount > 0
        ? `发现 ${deltaCount} 个新章节，但还没达到你设定的 ${minNewItems}`
        : '这部漫画还没有新章节';
      return {
        rule: rule,
        status: SubscriptionExecutionStatus.NO_UPDATE,
        hasUpdate: false,
        localCount: localCount,
        remoteCount: remoteCount,
        deltaCount: deltaCount,
        downloadedCount: 0,
        message: message,
        actionSummary: '',
        latestItemTitle: latestItemTitle,
        checkpoint: deltaCount > 0 ? null : this.buildCheckpoint(rule, localCount, remoteCount, latestItemTitle)
      };
    }

    let downloadedCount = 0;
    const actionSummaryParts: string[] = [];
    if (deltaCount > 0) {
      if (this.isActionEnabled(rule.actions, SubscriptionActionType.NOTIFY)) {
        await this.sendUpdateNotification(rule, deltaCount, latestItemTitle);
        actionSummaryParts.push('notify');
      }
      const downloadAction = this.getAction(rule.actions, SubscriptionActionType.AUTO_DOWNLOAD_NEW);
      if (downloadAction !== null && downloadAction.enabled) {
        downloadedCount = await this.triggerOnlineMangaAutoDownload(comicInfo, remoteChapters, seenCount, downloadAction.limitCount);
        if (downloadedCount > 0) {
          actionSummaryParts.push(`auto_download:${downloadedCount}`);
        }
      }
      return {
        rule: rule,
        status: SubscriptionExecutionStatus.SUCCESS,
        hasUpdate: true,
        localCount: localCount,
        remoteCount: remoteCount,
        deltaCount: deltaCount,
        downloadedCount: downloadedCount,
        message: `发现 ${deltaCount} 个新章节`,
        actionSummary: this.joinSummaryParts(actionSummaryParts),
        latestItemTitle: latestItemTitle,
        checkpoint: this.buildCheckpoint(rule, localCount, remoteCount, latestItemTitle)
      };
    }

    return {
      rule: rule,
      status: SubscriptionExecutionStatus.NO_UPDATE,
      hasUpdate: false,
      localCount: localCount,
      remoteCount: remoteCount,
      deltaCount: 0,
      downloadedCount: 0,
      message: '这部漫画还没有新章节',
      actionSummary: '',
      latestItemTitle: latestItemTitle,
      checkpoint: this.buildCheckpoint(rule, localCount, remoteCount, latestItemTitle)
    };
  }

  private async updateOnlineChaptersToDatabase(comicId: string, remoteChapters: WebViewChapterInfo[]): Promise<void> {
    try {
      for (let index = 0; index < remoteChapters.length; index++) {
        const chapter = remoteChapters[index];
        const chapterExternalId = chapter.id || `chapter_${index}`;
        const existing = await this.appDataManager.getOnlineChapterByExternalId(comicId, chapterExternalId);
        if (!existing) {
          let chapterNumber = index;
          if (chapter.number !== undefined && chapter.number !== null && !isNaN(chapter.number)) {
            chapterNumber = chapter.number;
          }
          const chapterInput: OnlineChapterInfoInput = {
            comicId: comicId,
            externalId: chapterExternalId,
            title: chapter.title || `第${index + 1}章`,
            chapterNumber: chapterNumber,
            url: '',
            pageCount: 0,
            publishTime: chapter.publishTime ? new Date(chapter.publishTime).getTime() : Date.now(),
            isDownloaded: false,
            index: chapterNumber
          };
          await this.appDataManager.addOnlineChapterInfo(chapterInput);
        }
      }
    } catch (error) {
      logger.warn(TAG, `更新在线漫画章节到数据库失败: ${String(error)}`);
    }
  }

  private async triggerOnlineMangaAutoDownload(
    comicInfo: ComicInfo,
    remoteChapters: WebViewChapterInfo[],
    seenCount: number,
    limitCount: number
  ): Promise<number> {
    const sourceId = Number(comicInfo.sourceId);
    if (Number.isNaN(sourceId) || sourceId <= 0) {
      return 0;
    }

    let engine: MangaSourceEngine;
    try {
      const sourceName = await this.resolveMangaSourceName(comicInfo);
      engine = await this.webViewSourceManager.getMangaEngine(sourceId, sourceName);
    } catch (error) {
      logger.warn(TAG, `获取在线漫画引擎失败（自动下载）: ${String(error)}`);
      return 0;
    }

    const items: MangaChapterDownloadItem[] = [];
    const maxCount = limitCount > 0 ? limitCount : remoteChapters.length;
    for (let index = seenCount; index < remoteChapters.length && items.length < maxCount; index++) {
      const chapter = remoteChapters[index];
      const chapterExternalId = chapter.id || `chapter_${index}`;
      items.push({
        chapterId: chapterExternalId,
        chapterTitle: chapter.title || `第${index + 1}章`,
        chapterIndex: chapter.number !== undefined ? chapter.number : index,
        pageListFetcher: async (_chapterId: string, _mangaId: string): Promise<string[]> => {
          const pagesResult = await engine.getPageList(chapterExternalId);
          if (pagesResult.success && pagesResult.data) {
            const pages: WebViewPageInfo[] = pagesResult.data;
            const urls: string[] = [];
            for (let pageIndex = 0; pageIndex < pages.length; pageIndex++) {
              const page: WebViewPageInfo = pages[pageIndex];
              if (page.imageUrl && page.imageUrl.length > 0) {
                urls.push(page.imageUrl);
              }
            }
            return urls;
          }
          return [];
        }
      });
    }

    if (items.length <= 0) {
      return 0;
    }

    const batchResult: MangaBatchDownloadResult = await this.unifiedDownloadManager.downloadMangaChapters(comicInfo.id, comicInfo.title, 0, items);
    logger.info(
      TAG,
      `已触发在线漫画自动下载: ${comicInfo.title}, requested=${items.length}, created=${batchResult.createdCount}, failed=${batchResult.failedCount}`
    );
    return batchResult.createdCount;
  }

  private async ensureShelfManagersReady(): Promise<boolean> {
    if (!this.settingsManager.isInitialized()) {
      logger.warn(TAG, '设置管理器尚未初始化，暂时无法执行书架内容跟踪规则');
      return false;
    }

    try {
      await this.categoryManager.initialize();
      await this.typeShelfManager.initialize();
      return true;
    } catch (error) {
      logger.warn(TAG, `初始化书架管理器失败: ${String(error)}`);
      return false;
    }
  }

  private async executeShelfRule(rule: SubscriptionRule, scene: string): Promise<SubscriptionRuleRunResult> {
    const shelfReady = await this.ensureShelfManagersReady();
    if (!shelfReady) {
      return this.buildSimpleResult(rule, SubscriptionExecutionStatus.FAILED, '书架还没准备好');
    }

    const shelf = this.typeShelfManager.getShelf(rule.targetId);
    if (shelf === undefined) {
      return this.buildSimpleResult(rule, SubscriptionExecutionStatus.FAILED, '找不到这个书架');
    }

    const candidates = await this.resolveShelfCandidates(shelf, true);
    return this.executeAggregateCandidatesRule(
      rule,
      candidates,
      scene,
      '这个书架里暂时没有可检查的内容',
      '书架有更新'
    );
  }

  private async executeProviderLibraryRule(rule: SubscriptionRule, scene: string): Promise<SubscriptionRuleRunResult> {
    if (rule.providerType !== SubscriptionProviderType.SUWAYOMI && rule.providerType !== SubscriptionProviderType.KOMGA) {
      return this.buildSimpleResult(rule, SubscriptionExecutionStatus.UNSUPPORTED, '目前只支持检查 Suwayomi 或 Komga 远程库');
    }

    const instanceId = this.normalizeProviderLibraryInstanceId(rule.providerType, rule.targetId);
    const candidates = await this.resolveProviderLibraryCandidates(rule.providerType, instanceId, true);
    return this.executeAggregateCandidatesRule(
      rule,
      candidates,
      scene,
      '这个远程库里暂时没有可检查的内容',
      '远程库有更新'
    );
  }

  private async executeAggregateCandidatesRule(
    rule: SubscriptionRule,
    candidates: SubscriptionShelfCandidate[],
    scene: string,
    emptyMessage: string,
    notificationTitlePrefix: string
  ): Promise<SubscriptionRuleRunResult> {
    if (candidates.length <= 0) {
      return this.buildEmptyAggregateResult(rule, emptyMessage);
    }

    let totalLocalCount = 0;
    let totalRemoteCount = 0;
    let totalDeltaCount = 0;
    let totalDownloadedCount = 0;
    let supportedTargetCount = 0;
    let updatedTargetCount = 0;
    let skippedTargetCount = 0;
    let failedTargetCount = 0;
    let unsupportedTargetCount = 0;
    let latestItemTitle = '';
    const checkpoints: SubscriptionCheckpoint[] = [];

    for (let index = 0; index < candidates.length; index++) {
      const candidate = candidates[index];
      if (!candidate.supported) {
        unsupportedTargetCount++;
        continue;
      }

      const conditionSkipReason = this.resolveConditionSkipReason(
        rule.conditions,
        this.buildConditionSubjectFromCandidate(candidate)
      );
      if (conditionSkipReason.length > 0) {
        skippedTargetCount++;
        continue;
      }

      supportedTargetCount++;
      const memberResult = await this.executeAggregateMemberCandidate(rule, candidate, scene);
      if (memberResult.status === SubscriptionExecutionStatus.UNSUPPORTED) {
        supportedTargetCount--;
        unsupportedTargetCount++;
        continue;
      }

      totalLocalCount += memberResult.localCount;
      totalRemoteCount += memberResult.remoteCount;
      totalDeltaCount += memberResult.deltaCount;
      totalDownloadedCount += memberResult.downloadedCount;

      if (memberResult.checkpoint !== null) {
        checkpoints.push(memberResult.checkpoint);
      }

      if (memberResult.status === SubscriptionExecutionStatus.SUCCESS) {
        updatedTargetCount++;
        if (latestItemTitle.length <= 0) {
          latestItemTitle = memberResult.latestItemTitle.length > 0
            ? memberResult.latestItemTitle
            : candidate.title;
        }
      } else if (memberResult.status === SubscriptionExecutionStatus.SKIPPED) {
        skippedTargetCount++;
      } else if (memberResult.status === SubscriptionExecutionStatus.FAILED) {
        failedTargetCount++;
      }
    }

    if (updatedTargetCount > 0 && this.isActionEnabled(rule.actions, SubscriptionActionType.NOTIFY)) {
      await this.sendAggregateUpdateNotification(
        rule,
        notificationTitlePrefix,
        updatedTargetCount,
        totalDeltaCount,
        latestItemTitle
      );
    }

    let status = SubscriptionExecutionStatus.NO_UPDATE;
    if (updatedTargetCount > 0) {
      status = SubscriptionExecutionStatus.SUCCESS;
    } else if (supportedTargetCount <= 0 && skippedTargetCount > 0) {
      status = SubscriptionExecutionStatus.SKIPPED;
    } else if (supportedTargetCount <= 0 && unsupportedTargetCount > 0) {
      status = SubscriptionExecutionStatus.UNSUPPORTED;
    } else if (supportedTargetCount > 0 && failedTargetCount >= supportedTargetCount) {
      status = SubscriptionExecutionStatus.FAILED;
    } else if (supportedTargetCount > 0 && skippedTargetCount >= supportedTargetCount) {
      status = SubscriptionExecutionStatus.SKIPPED;
    }

    const actionSummaryParts: string[] = [];
    if (updatedTargetCount > 0 && this.isActionEnabled(rule.actions, SubscriptionActionType.NOTIFY)) {
      actionSummaryParts.push('notify');
    }
    if (totalDownloadedCount > 0) {
      actionSummaryParts.push(`auto_download:${totalDownloadedCount}`);
    }
    if (updatedTargetCount > 0) {
      actionSummaryParts.push(`items_updated:${updatedTargetCount}`);
    }

    return {
      rule: rule,
      status: status,
      hasUpdate: updatedTargetCount > 0,
      localCount: totalLocalCount,
      remoteCount: totalRemoteCount,
      deltaCount: totalDeltaCount,
      downloadedCount: totalDownloadedCount,
      message: this.buildAggregateExecutionMessage(
        candidates.length,
        updatedTargetCount,
        totalDeltaCount,
        totalDownloadedCount,
        skippedTargetCount,
        failedTargetCount,
        unsupportedTargetCount
      ),
      actionSummary: this.joinSummaryParts(actionSummaryParts),
      latestItemTitle: latestItemTitle,
      checkpoint: null,
      checkpoints: checkpoints,
      processedTargetCount: candidates.length,
      updatedTargetCount: updatedTargetCount,
      skippedTargetCount: skippedTargetCount,
      failedTargetCount: failedTargetCount,
      unsupportedTargetCount: unsupportedTargetCount
    };
  }

  private buildEmptyAggregateResult(rule: SubscriptionRule, message: string): SubscriptionRuleRunResult {
    return {
      rule: rule,
      status: SubscriptionExecutionStatus.NO_UPDATE,
      hasUpdate: false,
      localCount: 0,
      remoteCount: 0,
      deltaCount: 0,
      downloadedCount: 0,
      message: message,
      actionSummary: '',
      latestItemTitle: '',
      checkpoint: null,
      checkpoints: [],
      processedTargetCount: 0,
      updatedTargetCount: 0,
      skippedTargetCount: 0,
      failedTargetCount: 0,
      unsupportedTargetCount: 0
    };
  }

  private async executeAggregateMemberCandidate(
    rule: SubscriptionRule,
    candidate: SubscriptionShelfCandidate,
    scene: string
  ): Promise<SubscriptionRuleRunResult> {
    const memberRule = this.buildMemberRuleFromAggregateRule(rule, candidate);
    const memberScene = `${scene}:aggregate_member`;
    if (candidate.contentType === SubscriptionContentType.NOVEL) {
      return this.executeNovelRule(memberRule, memberScene);
    }
    if (candidate.contentType === SubscriptionContentType.MANGA) {
      return this.executeMangaRule(memberRule, memberScene);
    }
    return this.buildSimpleResult(memberRule, SubscriptionExecutionStatus.UNSUPPORTED, candidate.unsupportedReason);
  }

  private buildAggregateExecutionMessage(
    processedTargetCount: number,
    updatedTargetCount: number,
    totalDeltaCount: number,
    totalDownloadedCount: number,
    skippedTargetCount: number,
    failedTargetCount: number,
    unsupportedTargetCount: number
  ): string {
    const parts: string[] = [`检查了 ${processedTargetCount} 项`];
    if (updatedTargetCount > 0) {
      parts.push(`${updatedTargetCount} 项有更新`);
    }
    if (totalDeltaCount > 0) {
      parts.push(`共发现 ${totalDeltaCount} 个新内容`);
    }
    if (totalDownloadedCount > 0) {
      parts.push(`已开始下载 ${totalDownloadedCount} 项`);
    }
    if (skippedTargetCount > 0) {
      parts.push(`跳过 ${skippedTargetCount} 项`);
    }
    if (failedTargetCount > 0) {
      parts.push(`失败 ${failedTargetCount} 项`);
    }
    if (unsupportedTargetCount > 0) {
      parts.push(`暂不支持 ${unsupportedTargetCount} 项`);
    }
    return parts.join('，');
  }

  private buildMemberRuleFromAggregateRule(rule: SubscriptionRule, candidate: SubscriptionShelfCandidate): SubscriptionRule {
    return {
      id: rule.id,
      name: rule.name,
      enabled: rule.enabled,
      targetType: SubscriptionTargetType.ITEM,
      contentType: candidate.contentType,
      targetId: candidate.itemId,
      targetTitle: candidate.title,
      sourceId: candidate.sourceId,
      sourceName: candidate.sourceName,
      providerType: candidate.providerType,
      checkIntervalMin: rule.checkIntervalMin,
      conditions: this.cloneConditions(rule.conditions),
      actions: this.cloneActionsWithoutNotify(rule.actions),
      lastCheckTime: rule.lastCheckTime,
      lastSuccessTime: rule.lastSuccessTime,
      lastError: rule.lastError,
      lastTriggeredScene: rule.lastTriggeredScene,
      createTime: rule.createTime,
      updateTime: rule.updateTime
    };
  }

  private cloneConditions(conditions: SubscriptionCondition[]): SubscriptionCondition[] {
    const result: SubscriptionCondition[] = [];
    for (let index = 0; index < conditions.length; index++) {
      const condition = conditions[index];
      result.push({
        type: condition.type,
        enabled: condition.enabled,
        numericValue: condition.numericValue,
        booleanValue: condition.booleanValue,
        textValue: condition.textValue
      });
    }
    return result;
  }

  private cloneActionsWithoutNotify(actions: SubscriptionAction[]): SubscriptionAction[] {
    const result: SubscriptionAction[] = [];
    for (let index = 0; index < actions.length; index++) {
      const action = actions[index];
      if (action.type === SubscriptionActionType.NOTIFY) {
        continue;
      }
      result.push({
        type: action.type,
        enabled: action.enabled,
        limitCount: action.limitCount,
        notifyTitle: action.notifyTitle,
        notifyText: action.notifyText
      });
    }
    if (!this.hasActionType(result, SubscriptionActionType.CHECK_UPDATE)) {
      result.unshift(createCheckAction());
    }
    return result;
  }

  private async resolveShelfCandidates(shelf: TypeShelf, requireMetadata: boolean): Promise<SubscriptionShelfCandidate[]> {
    if (shelf.shelfType === ShelfType.DYNAMIC) {
      return this.resolveDynamicShelfCandidates(shelf);
    }
    if (shelf.isSystem) {
      return this.resolveSystemShelfCandidates(shelf, requireMetadata);
    }
    return this.resolveCustomShelfCandidates(shelf, requireMetadata);
  }

  private async resolveProviderLibraryCandidates(
    providerType: SubscriptionProviderType,
    instanceId: string,
    requireMetadata: boolean
  ): Promise<SubscriptionShelfCandidate[]> {
    const favorites = await this.loadFavoriteMangaCandidates(requireMetadata);
    const result: SubscriptionShelfCandidate[] = [];
    for (let index = 0; index < favorites.length; index++) {
      const candidate = favorites[index];
      if (this.matchesProviderLibraryCandidate(candidate, providerType, instanceId)) {
        result.push(candidate);
      }
    }
    return this.dedupeShelfCandidates(result);
  }

  private matchesProviderLibraryCandidate(
    candidate: SubscriptionShelfCandidate,
    providerType: SubscriptionProviderType,
    instanceId: string
  ): boolean {
    if (candidate.contentType !== SubscriptionContentType.MANGA) {
      return false;
    }
    if (candidate.providerType !== providerType) {
      return false;
    }
    if (providerType !== SubscriptionProviderType.KOMGA || instanceId.length <= 0) {
      return true;
    }
    return this.resolveKomgaInstanceIdForCandidate(candidate) === instanceId;
  }

  private resolveKomgaInstanceIdForCandidate(candidate: SubscriptionShelfCandidate): string {
    const remoteInstanceId = candidate.remoteManga?.sourceInfo?.providerInstanceId;
    if (remoteInstanceId && remoteInstanceId.trim().length > 0) {
      return remoteInstanceId.trim();
    }

    const parsed = RemoteLibraryMangaBridge.parseProviderMangaId(candidate.itemId);
    if (parsed !== null && parsed.providerType === 'komga' && parsed.instanceId && parsed.instanceId.length > 0) {
      return parsed.instanceId;
    }
    return '';
  }

  private normalizeProviderLibraryInstanceId(providerType: SubscriptionProviderType, targetId: string): string {
    const normalizedTargetId = targetId.trim();
    if (providerType !== SubscriptionProviderType.KOMGA) {
      return '';
    }
    if (normalizedTargetId.length <= 0 || normalizedTargetId === SubscriptionProviderType.KOMGA) {
      return '';
    }
    return normalizedTargetId;
  }

  private buildProviderLibraryTargetId(providerType: SubscriptionProviderType, instanceId: string): string {
    if (providerType === SubscriptionProviderType.KOMGA && instanceId.length > 0) {
      return instanceId;
    }
    return providerType;
  }

  private buildProviderLibraryTitle(
    providerType: SubscriptionProviderType,
    instanceId: string,
    instanceTitle: string
  ): string {
    if (providerType === SubscriptionProviderType.SUWAYOMI) {
      return 'Suwayomi 收藏库';
    }

    if (instanceId.length <= 0) {
      return 'Komga 收藏库';
    }

    const normalizedTitle = instanceTitle.trim();
    if (normalizedTitle.length > 0) {
      return `Komga 收藏库 - ${normalizedTitle}`;
    }
    return `Komga 收藏库 - ${instanceId}`;
  }

  private async resolveSystemShelfCandidates(shelf: TypeShelf, requireMetadata: boolean): Promise<SubscriptionShelfCandidate[]> {
    const result: SubscriptionShelfCandidate[] = [];
    for (let index = 0; index < shelf.contentTypes.length; index++) {
      const contentType = shelf.contentTypes[index];
      if (contentType === ShelfContentType.NOVEL) {
        const novels = await this.loadFavoriteNovelCandidates();
        for (let novelIndex = 0; novelIndex < novels.length; novelIndex++) {
          result.push(novels[novelIndex]);
        }
      } else if (contentType === ShelfContentType.MANGA) {
        const mangas = await this.loadFavoriteMangaCandidates(requireMetadata);
        for (let mangaIndex = 0; mangaIndex < mangas.length; mangaIndex++) {
          result.push(mangas[mangaIndex]);
        }
      } else if (contentType === ShelfContentType.EBOOK) {
        const ebooks = await this.loadFavoriteEBookCandidates();
        for (let ebookIndex = 0; ebookIndex < ebooks.length; ebookIndex++) {
          result.push(ebooks[ebookIndex]);
        }
      }
    }
    return this.dedupeShelfCandidates(result);
  }

  private async resolveCustomShelfCandidates(shelf: TypeShelf, requireMetadata: boolean): Promise<SubscriptionShelfCandidate[]> {
    const items = this.typeShelfManager.getShelfItems(shelf.id);
    const favoriteMap = await this.loadFavoriteInfoMap();
    const result: SubscriptionShelfCandidate[] = [];
    for (let index = 0; index < items.length; index++) {
      const candidate = await this.resolveCategoryItemCandidate(items[index], requireMetadata, favoriteMap);
      if (candidate !== null) {
        result.push(candidate);
      }
    }
    return this.dedupeShelfCandidates(result);
  }

  private async resolveDynamicShelfCandidates(shelf: TypeShelf): Promise<SubscriptionShelfCandidate[]> {
    if (shelf.dynamicFilter === undefined) {
      return [];
    }

    const result: SubscriptionShelfCandidate[] = [];
    for (let index = 0; index < shelf.contentTypes.length; index++) {
      const shelfContentType = shelf.contentTypes[index];
      if (shelfContentType === ShelfContentType.NOVEL) {
        const novels = await this.loadFavoriteNovelCandidates();
        for (let novelIndex = 0; novelIndex < novels.length; novelIndex++) {
          if (this.matchesDynamicShelfCandidate(novels[novelIndex], shelf.dynamicFilter)) {
            result.push(novels[novelIndex]);
          }
        }
      } else if (shelfContentType === ShelfContentType.MANGA) {
        const mangas = await this.loadFavoriteMangaCandidates(true);
        for (let mangaIndex = 0; mangaIndex < mangas.length; mangaIndex++) {
          if (this.matchesDynamicShelfCandidate(mangas[mangaIndex], shelf.dynamicFilter)) {
            result.push(mangas[mangaIndex]);
          }
        }
      } else if (shelfContentType === ShelfContentType.EBOOK) {
        const ebooks = await this.loadFavoriteEBookCandidates();
        for (let ebookIndex = 0; ebookIndex < ebooks.length; ebookIndex++) {
          if (this.matchesDynamicShelfCandidate(ebooks[ebookIndex], shelf.dynamicFilter)) {
            result.push(ebooks[ebookIndex]);
          }
        }
      }
    }
    return this.dedupeShelfCandidates(result);
  }

  private matchesDynamicShelfCandidate(
    candidate: SubscriptionShelfCandidate,
    filter: DynamicShelfFilter | undefined
  ): boolean {
    if (filter === undefined) {
      return false;
    }

    const matchItem: DynamicMatchItem = {
      title: candidate.title,
      authors: candidate.authors,
      tags: candidate.tags,
      sourceName: candidate.sourceName,
      isNSFW: candidate.isNSFW
    };
    return matchesDynamicFilter(matchItem, filter);
  }

  private async resolveCategoryItemCandidate(
    item: CategoryItem,
    requireMetadata: boolean,
    favoriteMap: Map<string, FavoriteInfo>
  ): Promise<SubscriptionShelfCandidate | null> {
    if (item.contentType === ContentType.NOVEL) {
      return this.resolveNovelCandidateById(item.itemId);
    }
    if (item.contentType === ContentType.MANGA) {
      const favorite = favoriteMap.get(item.itemId) || null;
      return this.resolveMangaCandidateById(item.itemId, requireMetadata, favorite);
    }
    if (item.contentType === ContentType.EBOOK) {
      return this.resolveEBookCandidateById(item.itemId);
    }
    return null;
  }

  private async loadFavoriteInfoMap(): Promise<Map<string, FavoriteInfo>> {
    const favorites = await this.appDataManager.getUserFavorites(DEFAULT_USER_ID);
    const result = new Map<string, FavoriteInfo>();
    for (let index = 0; index < favorites.length; index++) {
      result.set(favorites[index].comicId, favorites[index]);
    }
    return result;
  }

  private async loadFavoriteNovelCandidates(): Promise<SubscriptionShelfCandidate[]> {
    const books = await this.novelDataManager.getFavoriteBooks();
    const result: SubscriptionShelfCandidate[] = [];
    for (let index = 0; index < books.length; index++) {
      result.push(this.buildNovelCandidate(books[index]));
    }
    return result;
  }

  private async loadFavoriteMangaCandidates(requireMetadata: boolean): Promise<SubscriptionShelfCandidate[]> {
    const favorites = await this.appDataManager.getUserFavorites(DEFAULT_USER_ID);
    const result: SubscriptionShelfCandidate[] = [];
    for (let index = 0; index < favorites.length; index++) {
      const favorite = favorites[index];
      const candidate = await this.resolveMangaCandidateById(favorite.comicId, requireMetadata, favorite);
      if (candidate !== null) {
        result.push(candidate);
      }
    }
    return this.dedupeShelfCandidates(result);
  }

  private async loadFavoriteEBookCandidates(): Promise<SubscriptionShelfCandidate[]> {
    const ebooks = await this.ebookDataManager.getEBookList();
    const result: SubscriptionShelfCandidate[] = [];
    for (let index = 0; index < ebooks.length; index++) {
      if (ebooks[index].isFavorite) {
        result.push(this.buildEBookCandidate(ebooks[index]));
      }
    }
    return result;
  }

  private async resolveNovelCandidateById(bookId: string): Promise<SubscriptionShelfCandidate | null> {
    const book = await this.novelDataManager.getBook(bookId);
    if (book === null) {
      return null;
    }
    return this.buildNovelCandidate(book);
  }

  private async resolveEBookCandidateById(bookId: string): Promise<SubscriptionShelfCandidate | null> {
    const ebook = await this.ebookDataManager.getEBookById(bookId);
    if (ebook === null) {
      return null;
    }
    return this.buildEBookCandidate(ebook);
  }

  private async resolveMangaCandidateById(
    mangaId: string,
    requireMetadata: boolean,
    favorite: FavoriteInfo | null
  ): Promise<SubscriptionShelfCandidate | null> {
    let cachedManga = await this.remoteLibraryBridge.getCachedMangaById(mangaId);
    const parsedProvider = RemoteLibraryMangaBridge.parseProviderMangaId(mangaId);
    if (cachedManga === null && requireMetadata && parsedProvider !== null) {
      try {
        cachedManga = await this.remoteLibraryBridge.loadRemoteMangaDetail(null, mangaId);
      } catch (error) {
        logger.warn(TAG, `加载远程漫画候选信息失败: ${mangaId}, ${String(error)}`);
      }
    }

    if (cachedManga !== null) {
      return this.buildMangaCandidateFromRemoteManga(cachedManga);
    }

    const comicInfo = await this.appDataManager.getComicById(mangaId);
    if (comicInfo !== null) {
      return await this.buildMangaCandidateFromComicInfo(comicInfo, parsedProvider, favorite);
    }

    if (parsedProvider !== null) {
      return this.buildRemoteProviderFallbackCandidate(mangaId, parsedProvider.providerType, favorite);
    }

    return null;
  }

  private buildNovelCandidate(book: NovelBook): SubscriptionShelfCandidate {
    return {
      itemId: book.id,
      title: book.name,
      contentType: SubscriptionContentType.NOVEL,
      providerType: SubscriptionProviderType.LEGADO,
      sourceId: book.sourceId,
      sourceName: book.sourceName,
      isFavorite: book.isFavorite,
      authors: book.author.length > 0 ? [book.author] : [],
      tags: this.splitNovelTags(book.kind),
      isNSFW: book.isNSFW === true,
      localCount: book.chapterCount,
      latestItemTitle: book.latestChapterTitle || '',
      novelBook: book,
      remoteManga: null,
      supported: true,
      unsupportedReason: ''
    };
  }

  private buildEBookCandidate(ebook: EBook): SubscriptionShelfCandidate {
    const authors: string[] = [];
    if (ebook.metadata.author && ebook.metadata.author.trim().length > 0) {
      authors.push(ebook.metadata.author.trim());
    }

    return {
      itemId: ebook.id,
      title: ebook.metadata.title,
      contentType: SubscriptionContentType.EBOOK,
      providerType: SubscriptionProviderType.NONE,
      sourceId: '',
      sourceName: '',
      isFavorite: ebook.isFavorite,
      authors: authors,
      tags: ebook.metadata.tags ? ebook.metadata.tags.concat() : [],
      isNSFW: ebook.isNSFW === true,
      localCount: ebook.chapters.length,
      latestItemTitle: ebook.chapters.length > 0 ? ebook.chapters[ebook.chapters.length - 1].title : '',
      novelBook: null,
      remoteManga: null,
      supported: false,
      unsupportedReason: '电子书的更新提醒还在准备中'
    };
  }

  private collectMangaTags(manga: Manga): string[] {
    const tags: string[] = [];
    if (manga.metadata.genres) {
      for (let index = 0; index < manga.metadata.genres.length; index++) {
        tags.push(manga.metadata.genres[index]);
      }
    }
    if (manga.metadata.themes) {
      for (let index = 0; index < manga.metadata.themes.length; index++) {
        tags.push(manga.metadata.themes[index]);
      }
    }
    return tags;
  }

  private buildMangaCandidateFromRemoteManga(manga: Manga): SubscriptionShelfCandidate {
    const providerType = this.resolveMangaProviderType(manga);
    const isRemoteProvider = this.remoteLibraryBridge.isRemoteProviderManga(manga);
    const hasSourceInfo = providerType === SubscriptionProviderType.WEBVIEW &&
      manga.sourceInfo !== undefined &&
      manga.sourceInfo.sourceId !== undefined &&
      String(manga.sourceInfo.sourceId).length > 0 &&
      manga.sourceInfo.externalId !== undefined &&
      String(manga.sourceInfo.externalId).length > 0;
    const isSupported = isRemoteProvider || hasSourceInfo;
    return {
      itemId: manga.id,
      title: manga.title,
      contentType: SubscriptionContentType.MANGA,
      providerType: providerType,
      sourceId: manga.sourceInfo?.sourceId || '',
      sourceName: manga.sourceInfo?.sourceName || '',
      isFavorite: manga.isFavorite,
      authors: manga.metadata.authors ? manga.metadata.authors.concat() : [],
      tags: this.collectMangaTags(manga),
      isNSFW: manga.isNSFW === true || manga.sourceInfo?.isNSFW === true,
      localCount: manga.chapters.length,
      latestItemTitle: manga.chapters.length > 0 ? manga.chapters[manga.chapters.length - 1].title : '',
      novelBook: null,
      remoteManga: isRemoteProvider ? manga : null,
      supported: isSupported,
      unsupportedReason: isSupported ? '' : '这类漫画暂时还不能用于书架提醒'
    };
  }

  private async buildMangaCandidateFromComicInfo(
    comicInfo: ComicInfo,
    parsedProvider: ParsedRemoteMangaId | null,
    favorite: FavoriteInfo | null
  ): Promise<SubscriptionShelfCandidate> {
    const providerType = parsedProvider !== null
      ? this.resolveRemoteProviderType(parsedProvider.providerType)
      : SubscriptionProviderType.WEBVIEW;
    const sourceName = await this.resolveMangaSourceName(comicInfo);
    const hasOnlineSourceInfo = providerType === SubscriptionProviderType.WEBVIEW &&
      comicInfo.sourceId !== undefined &&
      String(comicInfo.sourceId).trim().length > 0 &&
      comicInfo.externalId !== undefined &&
      String(comicInfo.externalId).trim().length > 0;
    const isSupported = parsedProvider !== null || hasOnlineSourceInfo;
    return {
      itemId: comicInfo.id,
      title: comicInfo.title,
      contentType: SubscriptionContentType.MANGA,
      providerType: providerType,
      sourceId: comicInfo.sourceId,
      sourceName: sourceName,
      isFavorite: favorite !== null,
      authors: comicInfo.author.length > 0 ? [comicInfo.author] : [],
      tags: comicInfo.tags ? comicInfo.tags.concat() : (favorite ? favorite.tags.concat() : []),
      isNSFW: comicInfo.isNSFW === true || comicInfo.isNSFW === 1,
      localCount: comicInfo.chapterCount,
      latestItemTitle: '',
      novelBook: null,
      remoteManga: null,
      supported: isSupported,
      unsupportedReason: isSupported ? '' : '这类漫画暂时还不能用于书架提醒'
    };
  }

  private buildRemoteProviderFallbackCandidate(
    mangaId: string,
    provider: 'suwayomi' | 'komga',
    favorite: FavoriteInfo | null
  ): SubscriptionShelfCandidate {
    return {
      itemId: mangaId,
      title: mangaId,
      contentType: SubscriptionContentType.MANGA,
      providerType: this.resolveRemoteProviderType(provider),
      sourceId: '',
      sourceName: provider === 'suwayomi' ? 'Suwayomi' : 'Komga',
      isFavorite: favorite !== null,
      authors: [],
      tags: favorite ? favorite.tags.concat() : [],
      isNSFW: false,
      localCount: 0,
      latestItemTitle: '',
      novelBook: null,
      remoteManga: null,
      supported: true,
      unsupportedReason: ''
    };
  }

  private resolveRemoteProviderType(provider: 'suwayomi' | 'komga'): SubscriptionProviderType {
    if (provider === 'suwayomi') {
      return SubscriptionProviderType.SUWAYOMI;
    }
    return SubscriptionProviderType.KOMGA;
  }

  private async resolveMangaSourceName(comicInfo: ComicInfo): Promise<string> {
    const sourceIdText = comicInfo.sourceId.trim();
    const sourceIdNumber = Number(sourceIdText);
    if (!Number.isNaN(sourceIdNumber) && sourceIdNumber > 0) {
      const sourceRecord = await this.appDataManager.getComicSourceById(sourceIdNumber);
      if (sourceRecord !== null) {
        return String(sourceRecord.name || '').trim();
      }
    }
    return '';
  }

  private splitNovelTags(kindText?: string): string[] {
    if (!kindText || kindText.trim().length <= 0) {
      return [];
    }
    return kindText
      .split(/[,，、]/)
      .map((item: string) => item.trim())
      .filter((item: string) => item.length > 0);
  }

  private dedupeShelfCandidates(candidates: SubscriptionShelfCandidate[]): SubscriptionShelfCandidate[] {
    const result: SubscriptionShelfCandidate[] = [];
    const keys = new Set<string>();
    for (let index = 0; index < candidates.length; index++) {
      const candidate = candidates[index];
      const key = `${candidate.contentType}:${candidate.itemId}`;
      if (!keys.has(key)) {
        keys.add(key);
        result.push(candidate);
      }
    }
    return result;
  }

  private buildTargetPreview(
    targetType: SubscriptionTargetType,
    targetId: string,
    targetTitle: string,
    contentType: SubscriptionContentType,
    candidates: SubscriptionShelfCandidate[],
    rule?: SubscriptionRule
  ): SubscriptionTargetPreview {
    const previewCandidates: SubscriptionTargetPreviewCandidate[] = [];
    const contentTypeBreakdown: SubscriptionTargetPreviewCounter[] = [];
    const providerTypeBreakdown: SubscriptionTargetPreviewCounter[] = [];
    let supportedCandidateCount = 0;
    let unsupportedCandidateCount = 0;
    let matchedCandidateCount = 0;
    let filteredCandidateCount = 0;

    for (let index = 0; index < candidates.length; index++) {
      const candidate = candidates[index];
      const conditionReason = rule !== undefined
        ? this.resolveConditionSkipReason(rule.conditions, this.buildConditionSubjectFromCandidate(candidate))
        : '';
      const conditionMatched = candidate.supported && conditionReason.length <= 0;
      previewCandidates.push({
        itemId: candidate.itemId,
        title: candidate.title,
        contentType: candidate.contentType,
        providerType: candidate.providerType,
        sourceId: candidate.sourceId,
        sourceName: candidate.sourceName,
        isFavorite: candidate.isFavorite,
        supported: candidate.supported,
        unsupportedReason: candidate.unsupportedReason,
        conditionMatched: conditionMatched,
        conditionReason: conditionReason,
        localCount: candidate.localCount,
        latestItemTitle: candidate.latestItemTitle
      });
      if (candidate.supported) {
        supportedCandidateCount++;
        if (conditionMatched) {
          matchedCandidateCount++;
        } else if (rule !== undefined) {
          filteredCandidateCount++;
        }
      } else {
        unsupportedCandidateCount++;
      }
      this.increasePreviewCounter(contentTypeBreakdown, candidate.contentType);
      this.increasePreviewCounter(providerTypeBreakdown, candidate.providerType);
    }

    return {
      targetType: targetType,
      targetId: targetId,
      targetTitle: targetTitle,
      contentType: contentType,
      totalCandidateCount: candidates.length,
      supportedCandidateCount: supportedCandidateCount,
      unsupportedCandidateCount: unsupportedCandidateCount,
      matchedCandidateCount: matchedCandidateCount,
      filteredCandidateCount: filteredCandidateCount,
      contentTypeBreakdown: contentTypeBreakdown,
      providerTypeBreakdown: providerTypeBreakdown,
      candidates: previewCandidates
    };
  }

  private increasePreviewCounter(counters: SubscriptionTargetPreviewCounter[], key: string): void {
    for (let index = 0; index < counters.length; index++) {
      if (counters[index].key === key) {
        counters[index].count++;
        return;
      }
    }
    counters.push({
      key: key,
      count: 1
    });
  }

  private async sendAggregateUpdateNotification(
    rule: SubscriptionRule,
    titlePrefix: string,
    updatedTargetCount: number,
    deltaCount: number,
    latestItemTitle: string
  ): Promise<void> {
    await this.notificationManager.sendNotification({
      id: this.buildNotificationId(rule.id, updatedTargetCount + deltaCount),
      title: `${titlePrefix}: ${rule.targetTitle.length > 0 ? rule.targetTitle : rule.name}`,
      text: `发现 ${updatedTargetCount} 个作品有更新`,
      additionalText: latestItemTitle.length > 0 ? latestItemTitle : `一共新增 ${deltaCount} 个内容`,
      type: NotificationType.UPDATE_AVAILABLE
    });
  }

  private buildLegadoBook(book: NovelBook, source: LegadoBookSource | null): LegadoBook {
    const sourceType = source && source.bookSourceType !== undefined
      ? source.bookSourceType as LegadoBookSourceType
      : LegadoBookSourceType.TEXT;

    return {
      id: book.id,
      origin: book.sourceId,
      originName: book.sourceName,
      bookUrl: book.bookUrl,
      name: book.name,
      author: book.author,
      kind: book.kind,
      intro: book.intro,
      coverUrl: book.coverUrl,
      coverLocalPath: book.coverLocalPath,
      tocUrl: book.tocUrl,
      latestChapterTitle: book.latestChapterTitle,
      wordCount: book.wordCount,
      updateTime: book.updateTime,
      type: sourceType,
      isPrivate: book.isPrivate,
      isNSFW: book.isNSFW
    };
  }

  private resolveSeenCount(localCount: number, checkpoint: SubscriptionCheckpoint | null): number {
    if (checkpoint === null) {
      return localCount;
    }
    return checkpoint.remoteCount > localCount ? checkpoint.remoteCount : localCount;
  }

  private buildConditionSubjectFromCandidate(candidate: SubscriptionShelfCandidate): SubscriptionConditionSubject {
    return {
      title: candidate.title,
      tags: candidate.tags.concat(),
      sourceName: candidate.sourceName,
      providerType: candidate.providerType,
      isFavorite: candidate.isFavorite,
      isNSFW: candidate.isNSFW
    };
  }

  private buildConditionSubjectFromNovel(book: NovelBook): SubscriptionConditionSubject {
    return {
      title: book.name,
      tags: this.splitNovelTags(book.kind),
      sourceName: book.sourceName,
      providerType: SubscriptionProviderType.LEGADO,
      isFavorite: book.isFavorite,
      isNSFW: book.isNSFW === true
    };
  }

  private buildConditionSubjectFromManga(manga: Manga): SubscriptionConditionSubject {
    const providerType = this.resolveMangaProviderType(manga);
    return {
      title: manga.title,
      tags: this.collectMangaTags(manga),
      sourceName: manga.sourceInfo?.sourceName || this.getProviderDisplayName(providerType),
      providerType: providerType,
      isFavorite: manga.isFavorite,
      isNSFW: manga.isNSFW === true || manga.sourceInfo?.isNSFW === true
    };
  }

  private getProviderDisplayName(providerType: SubscriptionProviderType): string {
    if (providerType === SubscriptionProviderType.SUWAYOMI) {
      return 'Suwayomi';
    }
    if (providerType === SubscriptionProviderType.KOMGA) {
      return 'Komga';
    }
    if (providerType === SubscriptionProviderType.LEGADO) {
      return 'Legado';
    }
    if (providerType === SubscriptionProviderType.WEBVIEW) {
      return 'WebView';
    }
    return '通用';
  }

  private normalizeConditionTextValue(value: string): string {
    return value.trim().toLowerCase();
  }

  private splitConditionKeywords(keywordText: string): string[] {
    return keywordText
      .split(/[\n,，、]+/)
      .map((item: string) => this.normalizeConditionTextValue(item))
      .filter((item: string) => item.length > 0);
  }

  private matchesKeywordCondition(text: string, keywordText: string): boolean {
    const keywords = this.splitConditionKeywords(keywordText);
    if (keywords.length <= 0) {
      return true;
    }
    const normalizedText = this.normalizeConditionTextValue(text);
    for (let index = 0; index < keywords.length; index++) {
      if (normalizedText.includes(keywords[index])) {
        return true;
      }
    }
    return false;
  }

  private resolveConditionMatchMode(conditions: SubscriptionCondition[]): SubscriptionConditionMatchMode {
    for (let index = 0; index < conditions.length; index++) {
      const condition = conditions[index];
      if (condition.type === SubscriptionConditionType.MATCH_MODE && condition.enabled) {
        return condition.textValue === SubscriptionConditionMatchMode.ANY
          ? SubscriptionConditionMatchMode.ANY
          : SubscriptionConditionMatchMode.ALL;
      }
    }
    return SubscriptionConditionMatchMode.ALL;
  }

  private matchesKeywordListCondition(values: string[], keywordText: string): boolean {
    const keywords = this.splitConditionKeywords(keywordText);
    if (keywords.length <= 0) {
      return true;
    }
    for (let valueIndex = 0; valueIndex < values.length; valueIndex++) {
      const normalizedValue = this.normalizeConditionTextValue(values[valueIndex]);
      for (let keywordIndex = 0; keywordIndex < keywords.length; keywordIndex++) {
        if (normalizedValue.includes(keywords[keywordIndex])) {
          return true;
        }
      }
    }
    return false;
  }

  private resolveMinNewItems(conditions: SubscriptionCondition[]): number {
    for (let index = 0; index < conditions.length; index++) {
      const condition = conditions[index];
      if (condition.type === SubscriptionConditionType.MIN_NEW_ITEMS && condition.enabled) {
        return condition.numericValue > 0 ? condition.numericValue : 1;
      }
    }
    return 1;
  }

  private shouldSkipByExcludeNsfwCondition(conditions: SubscriptionCondition[], isNSFW: boolean): boolean {
    for (let index = 0; index < conditions.length; index++) {
      const condition = conditions[index];
      if (condition.type === SubscriptionConditionType.EXCLUDE_NSFW && condition.enabled) {
        return isNSFW;
      }
    }
    return false;
  }

  private resolveConditionText(conditions: SubscriptionCondition[], conditionType: SubscriptionConditionType): string {
    for (let index = 0; index < conditions.length; index++) {
      const condition = conditions[index];
      if (condition.type === conditionType && condition.enabled && condition.textValue.trim().length > 0) {
        return condition.textValue.trim();
      }
    }
    return '';
  }

  private resolveConditionSkipReason(
    conditions: SubscriptionCondition[],
    subject: SubscriptionConditionSubject
  ): string {
    if (this.shouldSkipByExcludeNsfwCondition(conditions, subject.isNSFW)) {
      return '因为开启了跳过 NSFW，这次没有检查';
    }

    const evaluations = this.buildPositiveConditionEvaluations(conditions, subject);
    if (evaluations.length <= 0) {
      return '';
    }

    const matchMode = this.resolveConditionMatchMode(conditions);
    if (matchMode === SubscriptionConditionMatchMode.ANY) {
      for (let index = 0; index < evaluations.length; index++) {
        if (evaluations[index].matched) {
          return '';
        }
      }
      if (evaluations.length === 1) {
        return evaluations[0].failureReason;
      }
      return `这些条件都没满足（${this.joinConditionEvaluationLabels(evaluations)}）`;
    }

    for (let index = 0; index < evaluations.length; index++) {
      if (!evaluations[index].matched) {
        return evaluations[index].failureReason;
      }
    }
    return '';
  }

  private buildPositiveConditionEvaluations(
    conditions: SubscriptionCondition[],
    subject: SubscriptionConditionSubject
  ): SubscriptionConditionEvaluation[] {
    const evaluations: SubscriptionConditionEvaluation[] = [];
    if (this.hasEnabledCondition(conditions, SubscriptionConditionType.ONLY_IF_FAVORITE)) {
      evaluations.push({
        label: '已收藏',
        matched: subject.isFavorite,
        failureReason: '这条提醒只检查已收藏的内容'
      });
    }

    const titleKeyword = this.resolveConditionText(conditions, SubscriptionConditionType.TITLE_KEYWORD);
    if (titleKeyword.length > 0) {
      evaluations.push({
        label: '标题',
        matched: this.matchesKeywordCondition(subject.title, titleKeyword),
        failureReason: `标题里没有匹配到「${titleKeyword}」`
      });
    }

    const tagKeyword = this.resolveConditionText(conditions, SubscriptionConditionType.TAG_KEYWORD);
    if (tagKeyword.length > 0) {
      evaluations.push({
        label: '标签',
        matched: this.matchesKeywordListCondition(subject.tags, tagKeyword),
        failureReason: `标签里没有匹配到「${tagKeyword}」`
      });
    }

    const sourceKeyword = this.resolveConditionText(conditions, SubscriptionConditionType.SOURCE_KEYWORD);
    if (sourceKeyword.length > 0) {
      const sourceValues: string[] = [subject.sourceName, this.getProviderDisplayName(subject.providerType)];
      evaluations.push({
        label: '来源',
        matched: this.matchesKeywordListCondition(sourceValues, sourceKeyword),
        failureReason: `来源里没有匹配到「${sourceKeyword}」`
      });
    }
    return evaluations;
  }

  private hasEnabledCondition(conditions: SubscriptionCondition[], conditionType: SubscriptionConditionType): boolean {
    for (let index = 0; index < conditions.length; index++) {
      if (conditions[index].type === conditionType && conditions[index].enabled) {
        return true;
      }
    }
    return false;
  }

  private joinConditionEvaluationLabels(evaluations: SubscriptionConditionEvaluation[]): string {
    if (evaluations.length <= 0) {
      return '';
    }
    let result = evaluations[0].label;
    for (let index = 1; index < evaluations.length; index++) {
      result += ` / ${evaluations[index].label}`;
    }
    return result;
  }

  private getAction(actions: SubscriptionAction[], actionType: SubscriptionActionType): SubscriptionAction | null {
    for (let index = 0; index < actions.length; index++) {
      if (actions[index].type === actionType) {
        return actions[index];
      }
    }
    return null;
  }

  private isActionEnabled(actions: SubscriptionAction[], actionType: SubscriptionActionType): boolean {
    const action = this.getAction(actions, actionType);
    return action !== null && action.enabled;
  }

  private async triggerNovelAutoDownload(
    book: NovelBook,
    chapters: LegadoChapter[],
    seenCount: number,
    limitCount: number
  ): Promise<number> {
    const selectedChapters: LegadoChapter[] = [];
    const maxCount = limitCount > 0 ? limitCount : chapters.length;
    for (let index = seenCount; index < chapters.length && selectedChapters.length < maxCount; index++) {
      selectedChapters.push(chapters[index]);
    }
    if (selectedChapters.length <= 0) {
      return 0;
    }

    const startIndex = selectedChapters[0].index;
    const endIndex = selectedChapters[selectedChapters.length - 1].index;
    await this.unifiedDownloadManager.downloadNovelChapters({
      bookId: book.id,
      bookTitle: book.name,
      sourceId: book.sourceId,
      chapters: selectedChapters,
      startIndex: startIndex,
      endIndex: endIndex
    });
    logger.info(TAG, `已触发小说自动下载: ${book.name}, 数量=${selectedChapters.length}`);
    return selectedChapters.length;
  }

  private async triggerRemoteMangaAutoDownload(
    manga: Manga,
    seenCount: number,
    limitCount: number
  ): Promise<number> {
    const items: MangaChapterDownloadItem[] = [];
    const maxCount = limitCount > 0 ? limitCount : manga.chapters.length;
    for (let index = seenCount; index < manga.chapters.length && items.length < maxCount; index++) {
      const chapter = manga.chapters[index];
      if (chapter.isDownloaded) {
        continue;
      }
      items.push({
        chapterId: chapter.id,
        chapterTitle: chapter.title,
        chapterIndex: Math.floor(chapter.chapterNumber),
        pageListFetcher: async (_chapterId: string, _mangaId: string): Promise<string[]> => {
          const pages = await this.remoteLibraryBridge.loadChapterPages(manga, chapter);
          return this.extractPageUrls(pages);
        }
      });
    }

    if (items.length <= 0) {
      return 0;
    }

    const batchResult: MangaBatchDownloadResult = await this.unifiedDownloadManager.downloadMangaChapters(manga.id, manga.title, 0, items);
    logger.info(
      TAG,
      `已触发远程漫画自动下载: ${manga.title}, requested=${items.length}, created=${batchResult.createdCount}, failed=${batchResult.failedCount}`
    );
    return batchResult.createdCount;
  }

  private extractPageUrls(pages: MangaPage[]): string[] {
    const urls: string[] = [];
    for (let index = 0; index < pages.length; index++) {
      const page = pages[index];
      if (page.imageUrl && page.imageUrl.length > 0) {
        urls.push(page.imageUrl);
      } else if (page.imagePath && page.imagePath.length > 0) {
        urls.push(page.imagePath);
      }
    }
    return urls;
  }

  private async sendUpdateNotification(rule: SubscriptionRule, deltaCount: number, latestItemTitle: string): Promise<void> {
    const safeTitle = rule.targetTitle.length > 0 ? rule.targetTitle : rule.name;
    const latestText = latestItemTitle.length > 0 ? latestItemTitle : '有新内容了';
    await this.notificationManager.sendNotification({
      id: this.buildNotificationId(rule.id, deltaCount),
      title: `更新提醒: ${safeTitle}`,
      text: `发现 ${deltaCount} 个新内容`,
      additionalText: latestText,
      type: NotificationType.UPDATE_AVAILABLE
    });
  }

  private buildNotificationId(ruleId: string, deltaCount: number): number {
    let hashValue = 0;
    for (let index = 0; index < ruleId.length; index++) {
      hashValue = (hashValue * 33 + ruleId.charCodeAt(index)) % 1000000;
    }
    return 200000 + hashValue + deltaCount;
  }

  private buildCheckpoint(
    rule: SubscriptionRule,
    localCount: number,
    remoteCount: number,
    latestItemTitle: string
  ): SubscriptionCheckpoint {
    const now = Date.now();
    return {
      ruleId: rule.id,
      targetId: rule.targetId,
      contentId: rule.targetId,
      contentType: rule.contentType,
      remoteFingerprint: this.buildCountFingerprint(remoteCount, latestItemTitle),
      remoteCount: remoteCount,
      localCount: localCount,
      latestItemTitle: latestItemTitle,
      lastSeenTime: now,
      updateTime: now
    };
  }

  private buildCountFingerprint(remoteCount: number, latestItemTitle: string): string {
    const safeTitle = latestItemTitle.trim();
    return `${remoteCount}:${safeTitle}`;
  }

  private resolveMangaProviderType(manga: Manga): SubscriptionProviderType {
    if (manga.sourceInfo?.providerType === 'suwayomi') {
      return SubscriptionProviderType.SUWAYOMI;
    }
    if (manga.sourceInfo?.providerType === 'komga') {
      return SubscriptionProviderType.KOMGA;
    }
    const parsed = RemoteLibraryMangaBridge.parseProviderMangaId(manga.id);
    if (parsed !== null) {
      if (parsed.providerType === 'suwayomi') {
        return SubscriptionProviderType.SUWAYOMI;
      }
      if (parsed.providerType === 'komga') {
        return SubscriptionProviderType.KOMGA;
      }
    }
    return SubscriptionProviderType.WEBVIEW;
  }

  private joinSummaryParts(parts: string[]): string {
    if (parts.length <= 0) {
      return '';
    }
    let result = parts[0];
    for (let index = 1; index < parts.length; index++) {
      result += `, ${parts[index]}`;
    }
    return result;
  }
}

export function getSubscriptionManager(): SubscriptionManager {
  return SubscriptionManager.getInstance();
}
