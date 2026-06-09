import { SafeUtils } from '../../Utils/SafeUtils';
/**
 * 图源详情搜索执行器
 * 将 SourceDetailPage 的完整搜索分支抽离为后台可调用能力，供图源详情页和全局搜索共用。
 */
import { BusinessError } from '@kit.BasicServicesKit';
import { webview } from '@kit.ArkWeb';
import { logger } from '../../Utils/Logger';
import { DataManager } from '../Data/DataManager';
import { ComicSourceDatabaseRecord } from '../Database/DatabaseTypes';
import { ComicInfo } from '../Source/SourceExecutor';
import { SourceManager } from '../Source/SourceManager';
import { SearchIntentParser } from '../Search/SearchIntentParser';
import { SearchIntent, SearchIntentType } from '../Search/SearchIntentTypes';
import { EngineResult, SearchResult } from '../WebView/MangaSourceEngine';
import { DirectSearchResult, MangaInfo } from '../WebView/MangaSourceTypes';
import { WebViewSourceManager } from '../WebView/WebViewSourceManager';
import CookieManager from '../Managers/CookieManager';
import { getLegadoMangaSourceBridge } from '../Novel/LegadoMangaSourceBridge';

const TAG = 'SourceDetailSearchExecutor';
const DEFAULT_MOBILE_USER_AGENT: string = 'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';
const WEBVIEW_PRELOAD_SETTLE_MS: number = 450;
const WEBVIEW_JS_PROBE_TIMEOUT_MS: number = 900;
const WEBVIEW_JS_PROBE_INTERVAL_MS: number = 120;
const WEBVIEW_JS_PROBE_ATTEMPTS: number = 8;
const DEFAULT_PAGE_SIZE: number = 20;

export enum SourceDetailSearchRoute {
  KEYWORD = 'keyword',
  TAG = 'tag',
  DIRECT = 'direct',
  ID = 'id',
  AUTHOR = 'author',
  SERIES = 'series',
  URL = 'url',
  HTTP = 'http'
}

export enum SourceDetailSearchResultKind {
  LIST = 'list',
  DETAIL = 'detail',
  REDIRECT = 'redirect',
  EMPTY = 'empty'
}

export interface SourceDetailSearchParams {
  sourceId: number;
  query: string;
  searchType?: string;
  page?: number;
}

export interface SourceDetailSearchResult {
  success: boolean;
  sourceId: number;
  sourceName: string;
  query: string;
  searchType: string;
  displayLabel: string;
  route: SourceDetailSearchRoute;
  resultKind: SourceDetailSearchResultKind;
  items: ComicInfo[];
  mangas: MangaInfo[];
  usedWebView: boolean;
  page: number;
  hasMore: boolean;
  total: number;
  duration: number;
  actionCount: number;
  directManga?: MangaInfo;
  redirectUrl?: string;
  fallbackReason?: string;
  errorMessage?: string;
}

interface SourceDetailSearchNetworkConfig {
  userAgent?: string;
}

interface SourceDetailSearchSettingsConfig {
  userAgent?: string;
}

interface SourceDetailSearchJsonConfig {
  network?: SourceDetailSearchNetworkConfig;
  settings?: SourceDetailSearchSettingsConfig;
}

interface SourceDetailSearchContext {
  sourceId: number;
  sourceName: string;
  query: string;
  searchType: string;
  page: number;
  usedWebView: boolean;
  webViewPrepared: boolean;
  sourceRecord: ComicSourceDatabaseRecord;
  startTime: number;
}

export class SourceDetailSearchExecutor {
  private static instance: SourceDetailSearchExecutor | null = null;

  private dataManager: DataManager = DataManager.getInstance();
  private sourceManager: SourceManager = SourceManager.getInstance();
  private webViewSourceManager: WebViewSourceManager = WebViewSourceManager.getInstance();
  private webViewController: webview.WebviewController | null = null;
  private webViewQueue: Promise<void> = Promise.resolve();

  private constructor() {}

  static getInstance(): SourceDetailSearchExecutor {
    if (!SourceDetailSearchExecutor.instance) {
      SourceDetailSearchExecutor.instance = new SourceDetailSearchExecutor();
    }
    return SourceDetailSearchExecutor.instance;
  }

  attachWebViewController(controller: webview.WebviewController): void {
    this.webViewController = controller;
    this.webViewSourceManager.setGlobalWebViewController(controller);
    logger.info(TAG, '后台图源搜索 WebView 控制器已附加');
  }

  hasWebViewController(): boolean {
    return this.resolveWebViewController() !== null;
  }

  async search(params: SourceDetailSearchParams): Promise<SourceDetailSearchResult> {
    const query: string = params.query.trim();
    const searchType: string = params.searchType && params.searchType.trim().length > 0 ? params.searchType.trim() : 'search';
    const page: number = params.page && params.page > 0 ? params.page : 1;
    const sourceRecord: ComicSourceDatabaseRecord | null = await this.dataManager.getComicSourceById(params.sourceId);
    if (!sourceRecord) {
      return this.buildFailureResult(params.sourceId, `图源${params.sourceId}`, query, searchType, page, false, SourceDetailSearchRoute.KEYWORD, Date.now(), `图源不存在: ${params.sourceId}`);
    }

    const usedWebView: boolean = await this.webViewSourceManager.isWebViewSource(params.sourceId);
    const context: SourceDetailSearchContext = {
      sourceId: params.sourceId,
      sourceName: sourceRecord.name || `图源${params.sourceId}`,
      query: query,
      searchType: searchType,
      page: page,
      usedWebView: usedWebView,
      webViewPrepared: false,
      sourceRecord: sourceRecord,
      startTime: Date.now()
    };

    if (query.length === 0) {
      return this.buildFailureFromContext(context, SourceDetailSearchRoute.KEYWORD, '搜索关键词为空');
    }

    if (getLegadoMangaSourceBridge().isLegadoMangaRecord(sourceRecord)) {
      return await this.executeLegadoMangaSearch(context, query);
    }

    if (usedWebView) {
      return await this.runWebViewExclusive<SourceDetailSearchResult>(async (): Promise<SourceDetailSearchResult> => {
        return await this.executeSearch(context);
      });
    }
    return await this.executeSearch(context);
  }

  private async executeLegadoMangaSearch(
    context: SourceDetailSearchContext,
    keyword: string
  ): Promise<SourceDetailSearchResult> {
    logger.info(TAG, `使用 Legado IMAGE 桥接搜索: source=${context.sourceName}, keyword="${keyword}"`);
    const comics: ComicInfo[] = await getLegadoMangaSourceBridge().search(context.sourceId, keyword, context.page);
    return this.buildHttpListResult(context, keyword, comics, comics.length >= DEFAULT_PAGE_SIZE, 'Legado IMAGE bridge');
  }

  private async executeSearch(context: SourceDetailSearchContext): Promise<SourceDetailSearchResult> {
    logger.info(TAG, `执行图源详情后台搜索: source=${context.sourceName}(${context.sourceId}), type=${context.searchType}, query="${context.query}", webView=${context.usedWebView}`);

    try {
      if (context.searchType === 'search') {
        const intent: SearchIntent = SearchIntentParser.parse(context.query);
        if (intent.type === SearchIntentType.URL) {
          return await this.executeUrlDirectAccess(context, intent);
        }
        const intentId: string = intent.id || '';
        if (intent.type === SearchIntentType.MANGA_ID && intentId.length > 0) {
          return this.executeIdDirectAccess(context, intentId);
        }
        if (intent.type === SearchIntentType.CHAPTER_ID && intentId.length > 0) {
          return this.executeIdDirectAccess(context, intentId);
        }
        if (intent.type === SearchIntentType.AUTHOR_ID && intentId.length > 0) {
          return await this.executeAuthorSearch(context, intentId);
        }
        if (intent.type === SearchIntentType.SERIES_ID && intentId.length > 0) {
          return await this.executeSeriesSearch(context, intentId);
        }
        return await this.executeKeywordSearch(context, context.query, undefined);
      }

      if (context.searchType === 'searchByTag') {
        return await this.executeTagSearch(context, context.query);
      }

      return await this.executeDirectSearch(context, context.searchType, context.query);
    } catch (error) {
      const message: string = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `图源详情后台搜索失败: ${message}`);
      return this.buildFailureFromContext(context, SourceDetailSearchRoute.KEYWORD, message);
    }
  }

  private async executeKeywordSearch(
    context: SourceDetailSearchContext,
    keyword: string,
    fallbackReason?: string
  ): Promise<SourceDetailSearchResult> {
    if (context.usedWebView) {
      await this.prepareWebViewSource(context);
      const engine = await this.webViewSourceManager.getMangaEngine(context.sourceId, context.sourceName);
      const controller = this.resolveRequiredWebViewController();
      engine.updateWebViewController(controller);

      logger.info(TAG, `使用 SourceDetail WebView 搜索流程: source=${context.sourceName}, keyword="${keyword}"`);
      const result: EngineResult<SearchResult> = await engine.searchManga(keyword, context.page);
      if (!result.success || !result.data) {
        return this.buildFailureFromContext(context, SourceDetailSearchRoute.KEYWORD, result.error || '搜索失败');
      }
      return this.buildListResult(
        context,
        SourceDetailSearchRoute.KEYWORD,
        keyword,
        result.data.mangas,
        result.data.hasNext,
        result.data.total,
        result.actionCount,
        fallbackReason
      );
    }

    logger.info(TAG, `使用 SourceDetail HTTP 搜索流程: source=${context.sourceName}, keyword="${keyword}"`);
    const comics: ComicInfo[] = await this.sourceManager.search(context.sourceId, keyword, context.page, DEFAULT_PAGE_SIZE);
    return this.buildHttpListResult(context, keyword, comics, comics.length >= DEFAULT_PAGE_SIZE, fallbackReason);
  }

  private async executeTagSearch(context: SourceDetailSearchContext, tagId: string): Promise<SourceDetailSearchResult> {
    if (!context.usedWebView) {
      logger.warn(TAG, '非WebView图源不支持searchByTag，降级为关键词搜索');
      return await this.executeKeywordSearch(context, tagId, '非WebView图源不支持标签搜索，已按关键词搜索');
    }

    await this.prepareWebViewSource(context);
    const engine = await this.webViewSourceManager.getMangaEngine(context.sourceId, context.sourceName);
    const controller = this.resolveRequiredWebViewController();
    engine.updateWebViewController(controller);

    if (!engine.supportsCapability('searchByTag')) {
      logger.warn(TAG, '图源不支持searchByTag工作流，降级为关键词搜索');
      return await this.executeKeywordSearch(context, tagId, '图源不支持标签搜索，已按关键词搜索');
    }

    logger.info(TAG, `执行 SourceDetail 标签搜索流程: source=${context.sourceName}, tagId=${tagId}`);
    const result: EngineResult<SearchResult> = await engine.searchByTag(tagId, context.page);
    if (!result.success || !result.data) {
      return this.buildFailureFromContext(context, SourceDetailSearchRoute.TAG, result.error || '标签搜索失败');
    }

    return this.buildListResult(
      context,
      SourceDetailSearchRoute.TAG,
      tagId,
      result.data.mangas,
      result.data.hasNext,
      result.data.total,
      result.actionCount
    );
  }

  private async executeDirectSearch(
    context: SourceDetailSearchContext,
    searchType: string,
    query: string
  ): Promise<SourceDetailSearchResult> {
    if (!context.usedWebView) {
      logger.warn(TAG, '非WebView图源不支持directSearch，降级为关键词搜索');
      return await this.executeKeywordSearch(context, query, '非WebView图源不支持直达搜索，已按关键词搜索');
    }

    await this.prepareWebViewSource(context);
    const engine = await this.webViewSourceManager.getMangaEngine(context.sourceId, context.sourceName);
    const controller = this.resolveRequiredWebViewController();
    engine.updateWebViewController(controller);

    if (engine.supportsDirectSearch()) {
      logger.info(TAG, `执行 SourceDetail 直达搜索流程: source=${context.sourceName}, type=${searchType}, query=${query}`);
      const result: EngineResult<DirectSearchResult> = await engine.directSearch(searchType, query);
      if (!result.success || !result.data) {
        return this.buildFailureFromContext(context, SourceDetailSearchRoute.DIRECT, result.error || '直达搜索失败');
      }
      return this.buildDirectResult(context, query, result.data, result.actionCount);
    }

    if (searchType === 'searchById' && engine.supportsCapability('searchById')) {
      logger.info(TAG, `执行 SourceDetail searchById 流程: source=${context.sourceName}, query=${query}`);
      const result: EngineResult<SearchResult> = await engine.searchById(query);
      if (result.success && result.data && result.data.mangas.length > 0) {
        return this.buildDetailResult(context, query, result.data.mangas[0], result.actionCount);
      }
      return this.buildFailureFromContext(context, SourceDetailSearchRoute.ID, result.error || '未找到该ID对应的作品');
    }

    logger.warn(TAG, '图源不支持directSearch/searchById工作流，降级为关键词搜索');
    return await this.executeKeywordSearch(context, query, '图源不支持直达搜索，已按关键词搜索');
  }

  private executeIdDirectAccess(context: SourceDetailSearchContext, id: string): SourceDetailSearchResult {
    logger.info(TAG, `执行 SourceDetail ID直达流程: source=${context.sourceName}, id=${id}`);
    const manga: MangaInfo = {
      id: id,
      title: `作品 ${id}`,
      url: '',
      cover: ''
    };
    return this.buildDetailResult(context, id, manga, 0);
  }

  private async executeAuthorSearch(context: SourceDetailSearchContext, authorId: string): Promise<SourceDetailSearchResult> {
    if (!context.usedWebView) {
      return await this.executeKeywordSearch(context, authorId, '非WebView图源不支持作者ID搜索，已按关键词搜索');
    }

    await this.prepareWebViewSource(context);
    const engine = await this.webViewSourceManager.getMangaEngine(context.sourceId, context.sourceName);
    const controller = this.resolveRequiredWebViewController();
    engine.updateWebViewController(controller);

    if (engine.supportsCapability('searchByAuthor')) {
      logger.info(TAG, `执行 SourceDetail 作者搜索流程: source=${context.sourceName}, authorId=${authorId}`);
      const result: EngineResult<SearchResult> = await engine.searchByAuthor(authorId, context.page);
      if (result.success && result.data) {
        return this.buildListResult(
          context,
          SourceDetailSearchRoute.AUTHOR,
          authorId,
          result.data.mangas,
          result.data.hasNext,
          result.data.total,
          result.actionCount
        );
      }
    }

    logger.warn(TAG, '图源不支持作者ID搜索或作者搜索失败，降级为关键词搜索');
    return await this.executeKeywordSearch(context, authorId, '图源不支持作者ID搜索，已按关键词搜索');
  }

  private async executeSeriesSearch(context: SourceDetailSearchContext, seriesId: string): Promise<SourceDetailSearchResult> {
    if (!context.usedWebView) {
      return await this.executeKeywordSearch(context, seriesId, '非WebView图源不支持系列ID搜索，已按关键词搜索');
    }

    await this.prepareWebViewSource(context);
    const engine = await this.webViewSourceManager.getMangaEngine(context.sourceId, context.sourceName);
    const controller = this.resolveRequiredWebViewController();
    engine.updateWebViewController(controller);

    if (engine.supportsCapability('searchBySeries')) {
      logger.info(TAG, `执行 SourceDetail 系列搜索流程: source=${context.sourceName}, seriesId=${seriesId}`);
      const result: EngineResult<SearchResult> = await engine.searchBySeries(seriesId, context.page);
      if (result.success && result.data) {
        return this.buildListResult(
          context,
          SourceDetailSearchRoute.SERIES,
          seriesId,
          result.data.mangas,
          result.data.hasNext,
          result.data.total,
          result.actionCount
        );
      }
    }

    logger.warn(TAG, '图源不支持系列ID搜索或系列搜索失败，降级为关键词搜索');
    return await this.executeKeywordSearch(context, seriesId, '图源不支持系列ID搜索，已按关键词搜索');
  }

  private async executeUrlDirectAccess(
    context: SourceDetailSearchContext,
    intent: SearchIntent
  ): Promise<SourceDetailSearchResult> {
    const urlInfo = intent.urlParsedInfo;
    const extractedId: string = urlInfo && urlInfo.extractedId ? urlInfo.extractedId : '';
    if (urlInfo && extractedId.length > 0) {
      if (urlInfo.pathType === 'artwork') {
        return this.executeIdDirectAccess(context, extractedId);
      }
      if (urlInfo.pathType === 'user') {
        return await this.executeAuthorSearch(context, extractedId);
      }
      if (urlInfo.pathType === 'series') {
        return await this.executeSeriesSearch(context, extractedId);
      }
    }

    logger.warn(TAG, 'URL无法解析，降级为关键词搜索');
    return await this.executeKeywordSearch(context, intent.rawQuery, 'URL无法解析，已按关键词搜索');
  }

  private buildDirectResult(
    context: SourceDetailSearchContext,
    query: string,
    directResult: DirectSearchResult,
    actionCount: number
  ): SourceDetailSearchResult {
    if (directResult.type === 'detail' && directResult.manga) {
      return this.buildDetailResult(context, query, directResult.manga, actionCount);
    }

    if (directResult.type === 'list' && directResult.mangas && directResult.mangas.length > 0) {
      return this.buildListResult(
        context,
        SourceDetailSearchRoute.DIRECT,
        query,
        directResult.mangas,
        directResult.hasNext || false,
        directResult.total || directResult.mangas.length,
        actionCount
      );
    }

    if (directResult.type === 'redirect' && directResult.redirectUrl) {
      const manga: MangaInfo = {
        id: query,
        title: `作品 ${query}`,
        url: directResult.redirectUrl,
        cover: ''
      };
      return this.buildRedirectResult(context, query, manga, directResult.redirectUrl, actionCount);
    }

    return this.buildEmptyResult(context, SourceDetailSearchRoute.DIRECT, query, actionCount);
  }

  private async prepareWebViewSource(context: SourceDetailSearchContext): Promise<void> {
    if (context.webViewPrepared) {
      return;
    }

    const controller = this.resolveRequiredWebViewController();
    this.webViewSourceManager.setGlobalWebViewController(controller);

    const config: SourceDetailSearchJsonConfig | null = this.parseSourceJsonConfig(context.sourceRecord);
    const sourceUserAgent: string = this.resolveSourceUserAgent(config);
    if (sourceUserAgent.length > 0) {
      try {
        controller.setCustomUserAgent(sourceUserAgent);
        logger.info(TAG, `SourceDetail 后台搜索 WebView UA 已同步: source=${context.sourceName}, length=${sourceUserAgent.length}`);
      } catch (error) {
        logger.warn(TAG, `SourceDetail 后台搜索 WebView UA 同步失败: source=${context.sourceName}, error=${String(error)}`);
      }
    }

    const baseUrl: string = context.sourceRecord.baseUrl ? context.sourceRecord.baseUrl.trim() : '';
    if (baseUrl.length > 0) {
      controller.loadUrl(baseUrl);
      logger.info(TAG, `SourceDetail 后台搜索已预加载图源站点: ${baseUrl}`);
      await this.sleep(WEBVIEW_PRELOAD_SETTLE_MS);
      const ready: boolean = await this.waitForExecutableJavaScript(controller, context.sourceName);
      if (!ready) {
        logger.warn(TAG, `预加载站点后JS上下文未就绪，切换到about:blank承接搜索脚本: source=${context.sourceName}`);
        controller.loadUrl('about:blank');
        await this.sleep(WEBVIEW_PRELOAD_SETTLE_MS);
        const blankReady: boolean = await this.waitForExecutableJavaScript(controller, context.sourceName);
        if (!blankReady) {
          throw new Error(`WebView JavaScript上下文未就绪: ${context.sourceName}`);
        }
      }
      context.webViewPrepared = true;
      setTimeout(() => {
        void this.refreshCookiesLater(context.sourceId, context.sourceName, controller, baseUrl);
      }, 800);
    } else {
      const ready: boolean = await this.waitForExecutableJavaScript(controller, context.sourceName);
      if (!ready) {
        throw new Error(`WebView JavaScript上下文未就绪: ${context.sourceName}`);
      }
      context.webViewPrepared = true;
      logger.warn(TAG, `图源BaseUrl为空，仅使用当前WebView上下文执行搜索: ${context.sourceName}`);
    }
  }

  private async refreshCookiesLater(
    sourceId: number,
    sourceName: string,
    controller: webview.WebviewController,
    baseUrl: string
  ): Promise<void> {
    try {
      const ok: boolean = await CookieManager.getInstance().refreshCookiesIfNeeded(sourceId, controller, baseUrl);
      logger.debug(TAG, `SourceDetail 后台搜索预加载后Cookie刷新结果: source=${sourceName}, ok=${ok}`);
    } catch (error) {
      logger.warn(TAG, `SourceDetail 后台搜索预加载后Cookie刷新失败: source=${sourceName}, error=${String(error)}`);
    }
  }

  private parseSourceJsonConfig(sourceRecord: ComicSourceDatabaseRecord): SourceDetailSearchJsonConfig | null {
    const configJson: string = sourceRecord.configJson ? sourceRecord.configJson.trim() : '';
    if (configJson.length === 0) {
      return null;
    }

    try {
      return SafeUtils.parseObj(configJson) as SourceDetailSearchJsonConfig;
    } catch (error) {
      logger.warn(TAG, `解析图源配置失败: sourceId=${sourceRecord.id}, error=${String(error)}`);
      return null;
    }
  }

  private resolveSourceUserAgent(config: SourceDetailSearchJsonConfig | null): string {
    if (config && config.network && config.network.userAgent && config.network.userAgent.trim().length > 0) {
      return config.network.userAgent.trim();
    }
    if (config && config.settings && config.settings.userAgent && config.settings.userAgent.trim().length > 0) {
      return config.settings.userAgent.trim();
    }
    return DEFAULT_MOBILE_USER_AGENT;
  }

  private resolveWebViewController(): webview.WebviewController | null {
    if (this.webViewController) {
      return this.webViewController;
    }
    const controller: webview.WebviewController | null = this.webViewSourceManager.getGlobalWebViewController();
    if (controller) {
      this.webViewController = controller;
    }
    return controller;
  }

  private resolveRequiredWebViewController(): webview.WebviewController {
    const controller = this.resolveWebViewController();
    if (!controller) {
      throw new Error('WebView控制器未设置，无法执行WebView图源搜索');
    }
    return controller;
  }

  private async waitForExecutableJavaScript(controller: webview.WebviewController, sourceName: string): Promise<boolean> {
    for (let attempt = 1; attempt <= WEBVIEW_JS_PROBE_ATTEMPTS; attempt++) {
      const ok: boolean = await this.runJavaScriptProbe(controller);
      if (ok) {
        if (attempt > 1) {
          logger.info(TAG, `SourceDetail 后台搜索 WebView JS 已就绪: source=${sourceName}, attempts=${attempt}`);
        }
        return true;
      }
      await this.sleep(WEBVIEW_JS_PROBE_INTERVAL_MS);
    }
    return false;
  }

  private async runJavaScriptProbe(controller: webview.WebviewController): Promise<boolean> {
    return new Promise<boolean>((resolve) => {
      let finished: boolean = false;
      const timerId: number = setTimeout(() => {
        if (!finished) {
          finished = true;
          resolve(false);
        }
      }, WEBVIEW_JS_PROBE_TIMEOUT_MS);

      try {
        controller.runJavaScript('(() => "manxia-source-detail-ready")();', (error: BusinessError | null, result: string) => {
          if (finished) {
            return;
          }
          finished = true;
          clearTimeout(timerId);
          if (error) {
            logger.debug(TAG, `SourceDetail 后台搜索 WebView JS 探测失败: ${error.message}`);
            resolve(false);
            return;
          }
          resolve(result === 'manxia-source-detail-ready' || result === '"manxia-source-detail-ready"');
        });
      } catch (error) {
        if (!finished) {
          finished = true;
          clearTimeout(timerId);
          logger.debug(TAG, `SourceDetail 后台搜索 WebView JS 探测调用失败: ${String(error)}`);
          resolve(false);
        }
      }
    });
  }

  private async runWebViewExclusive<T>(task: () => Promise<T>): Promise<T> {
    const previous: Promise<void> = this.webViewQueue;
    let release: () => void = (): void => {};
    this.webViewQueue = new Promise<void>((resolve) => {
      release = (): void => {
        resolve();
      };
    });

    await previous;
    try {
      return await task();
    } finally {
      release();
    }
  }

  private buildListResult(
    context: SourceDetailSearchContext,
    route: SourceDetailSearchRoute,
    labelQuery: string,
    mangas: MangaInfo[],
    hasMore: boolean,
    total: number,
    actionCount: number,
    fallbackReason?: string
  ): SourceDetailSearchResult {
    const items: ComicInfo[] = this.convertMangaInfoToComicInfo(mangas);
    return {
      success: true,
      sourceId: context.sourceId,
      sourceName: context.sourceName,
      query: context.query,
      searchType: context.searchType,
      displayLabel: this.buildDisplayLabel(context.searchType, route, labelQuery),
      route: route,
      resultKind: items.length > 0 ? SourceDetailSearchResultKind.LIST : SourceDetailSearchResultKind.EMPTY,
      items: items,
      mangas: mangas,
      usedWebView: context.usedWebView,
      page: context.page,
      hasMore: hasMore,
      total: total,
      duration: Date.now() - context.startTime,
      actionCount: actionCount,
      fallbackReason: fallbackReason
    };
  }

  private buildHttpListResult(
    context: SourceDetailSearchContext,
    labelQuery: string,
    items: ComicInfo[],
    hasMore: boolean,
    fallbackReason?: string
  ): SourceDetailSearchResult {
    return {
      success: true,
      sourceId: context.sourceId,
      sourceName: context.sourceName,
      query: context.query,
      searchType: context.searchType,
      displayLabel: this.buildDisplayLabel(context.searchType, SourceDetailSearchRoute.HTTP, labelQuery),
      route: SourceDetailSearchRoute.HTTP,
      resultKind: items.length > 0 ? SourceDetailSearchResultKind.LIST : SourceDetailSearchResultKind.EMPTY,
      items: items,
      mangas: [],
      usedWebView: false,
      page: context.page,
      hasMore: hasMore,
      total: items.length,
      duration: Date.now() - context.startTime,
      actionCount: 0,
      fallbackReason: fallbackReason
    };
  }

  private buildDetailResult(
    context: SourceDetailSearchContext,
    labelQuery: string,
    manga: MangaInfo,
    actionCount: number
  ): SourceDetailSearchResult {
    return {
      success: true,
      sourceId: context.sourceId,
      sourceName: context.sourceName,
      query: context.query,
      searchType: context.searchType,
      displayLabel: this.buildDisplayLabel(context.searchType, SourceDetailSearchRoute.ID, labelQuery),
      route: SourceDetailSearchRoute.ID,
      resultKind: SourceDetailSearchResultKind.DETAIL,
      items: this.convertMangaInfoToComicInfo([manga]),
      mangas: [manga],
      usedWebView: context.usedWebView,
      page: context.page,
      hasMore: false,
      total: 1,
      duration: Date.now() - context.startTime,
      actionCount: actionCount,
      directManga: manga
    };
  }

  private buildRedirectResult(
    context: SourceDetailSearchContext,
    labelQuery: string,
    manga: MangaInfo,
    redirectUrl: string,
    actionCount: number
  ): SourceDetailSearchResult {
    return {
      success: true,
      sourceId: context.sourceId,
      sourceName: context.sourceName,
      query: context.query,
      searchType: context.searchType,
      displayLabel: this.buildDisplayLabel(context.searchType, SourceDetailSearchRoute.DIRECT, labelQuery),
      route: SourceDetailSearchRoute.DIRECT,
      resultKind: SourceDetailSearchResultKind.REDIRECT,
      items: this.convertMangaInfoToComicInfo([manga]),
      mangas: [manga],
      usedWebView: context.usedWebView,
      page: context.page,
      hasMore: false,
      total: 1,
      duration: Date.now() - context.startTime,
      actionCount: actionCount,
      directManga: manga,
      redirectUrl: redirectUrl
    };
  }

  private buildEmptyResult(
    context: SourceDetailSearchContext,
    route: SourceDetailSearchRoute,
    labelQuery: string,
    actionCount: number
  ): SourceDetailSearchResult {
    return {
      success: true,
      sourceId: context.sourceId,
      sourceName: context.sourceName,
      query: context.query,
      searchType: context.searchType,
      displayLabel: this.buildDisplayLabel(context.searchType, route, labelQuery),
      route: route,
      resultKind: SourceDetailSearchResultKind.EMPTY,
      items: [],
      mangas: [],
      usedWebView: context.usedWebView,
      page: context.page,
      hasMore: false,
      total: 0,
      duration: Date.now() - context.startTime,
      actionCount: actionCount
    };
  }

  private buildFailureFromContext(
    context: SourceDetailSearchContext,
    route: SourceDetailSearchRoute,
    message: string
  ): SourceDetailSearchResult {
    return this.buildFailureResult(
      context.sourceId,
      context.sourceName,
      context.query,
      context.searchType,
      context.page,
      context.usedWebView,
      route,
      context.startTime,
      message
    );
  }

  private buildFailureResult(
    sourceId: number,
    sourceName: string,
    query: string,
    searchType: string,
    page: number,
    usedWebView: boolean,
    route: SourceDetailSearchRoute,
    startTime: number,
    message: string
  ): SourceDetailSearchResult {
    return {
      success: false,
      sourceId: sourceId,
      sourceName: sourceName,
      query: query,
      searchType: searchType,
      displayLabel: query,
      route: route,
      resultKind: SourceDetailSearchResultKind.EMPTY,
      items: [],
      mangas: [],
      usedWebView: usedWebView,
      page: page,
      hasMore: false,
      total: 0,
      duration: Date.now() - startTime,
      actionCount: 0,
      errorMessage: message
    };
  }

  private buildDisplayLabel(searchType: string, route: SourceDetailSearchRoute, query: string): string {
    if (searchType === 'searchByTag' || route === SourceDetailSearchRoute.TAG) {
      return `标签: ${query}`;
    }
    if (route === SourceDetailSearchRoute.AUTHOR) {
      return `作者: ${query}`;
    }
    if (route === SourceDetailSearchRoute.SERIES) {
      return `系列: ${query}`;
    }
    return query;
  }

  private convertMangaInfoToComicInfo(mangas: MangaInfo[]): ComicInfo[] {
    const comics: ComicInfo[] = [];
    for (const manga of mangas) {
      let comicId: string = manga.id || '';
      if (comicId.startsWith('/')) {
        const parts: string[] = comicId.split('/').filter((part: string): boolean => part.length > 0);
        comicId = parts.length > 0 ? parts[parts.length - 1] : manga.id || '';
      }

      const comic: ComicInfo = {
        id: comicId,
        title: manga.title || '',
        author: manga.author || '',
        coverUrl: manga.cover || '',
        description: manga.description || '',
        tags: manga.genres || [],
        status: manga.status || '',
        url: manga.url || '',
        updateTime: 0
      };
      comics.push(comic);
    }
    return comics;
  }

  private async sleep(durationMs: number): Promise<void> {
    await new Promise<void>((resolve) => setTimeout(resolve, durationMs));
  }
}

export function getSourceDetailSearchExecutor(): SourceDetailSearchExecutor {
  return SourceDetailSearchExecutor.getInstance();
}
