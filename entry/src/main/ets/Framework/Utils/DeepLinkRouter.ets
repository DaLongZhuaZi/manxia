/**
 * 深度链接路由器
 * 解析 manxia:// 协议的 URI 并执行导航
 * 支持漫画（SourceManager）和小说（NovelSourceManager）两个系统
 *
 * 漫画路由:
 *   manxia://search/{source}?type={type}&query={query}   搜索
 *   manxia://source/{source}?tab={tab}&q={keyword}       图源首页
 *   manxia://detail/{source}/{contentId}                  内容直达（searchById）
 *
 * 小说路由:
 *   manxia://novel/search/{source}?q={keyword}           小说搜索
 *   manxia://novel/source/{source}                        小说源首页
 *   manxia://novel/detail/{source}/{encodedBookUrl}       小说直达
 *
 * 通用路由:
 *   manxia://page/{pageName}                              页面跳转
 *   manxia://page/{pageName}?action={action}              页面动作跳转
 *
 * {source} 支持: 图源名称、图源ID、图源pkg、别名（jm/pica/pixiv）
 */

import { logger } from '../../Utils/Logger';
import { SourceManager, SourceInfo } from '../Source/SourceManager';
import { NovelSourceManager } from '../Novel/NovelSourceManager';
import { NovelSourceInfo } from '../../Models/NovelModels';

const TAG = 'DeepLinkRouter';

const SCHEME: string = 'manxia';
const WEB_DOMAIN: string = 'manxia.top';
const WWW_WEB_DOMAIN: string = 'www.manxia.top';

// ── 结果类型 ──

export type DeepLinkResult = DeepLinkSearchResult | DeepLinkSourceResult | DeepLinkDetailResult |
  DeepLinkNovelSearchResult | DeepLinkNovelSourceResult | DeepLinkNovelDetailResult |
  DeepLinkPageResult;

interface DeepLinkQueryParams {
  type: string;
  query: string;
  q: string;
  tab: string;
  s: string;
  b: string;
  action: string;
}

export interface DeepLinkSearchResult {
  route: 'search';
  sourceKey: string;
  searchType: string;
  query: string;
}

export interface DeepLinkSourceResult {
  route: 'source';
  sourceKey: string;
  tab: string;
  keyword: string;
}

export interface DeepLinkDetailResult {
  route: 'detail';
  sourceKey: string;
  contentId: string;
}

export interface DeepLinkNovelSearchResult {
  route: 'novelSearch';
  sourceKey: string;
  query: string;
}

export interface DeepLinkNovelSourceResult {
  route: 'novelSource';
  sourceKey: string;
}

export interface DeepLinkNovelDetailResult {
  route: 'novelDetail';
  sourceKey: string;
  bookUrl: string;
}

export interface DeepLinkPageResult {
  route: 'page';
  pageName: string;
  action: string;
}

// ── 路由器 ──

export class DeepLinkRouter {
  private static instance: DeepLinkRouter | null = null;

  private constructor() {}

  static getInstance(): DeepLinkRouter {
    if (!DeepLinkRouter.instance) {
      DeepLinkRouter.instance = new DeepLinkRouter();
    }
    return DeepLinkRouter.instance;
  }

  isManxiaUri(uri: string): boolean {
    return uri.startsWith(SCHEME + '://') ||
      uri.startsWith('https://' + WEB_DOMAIN + '/') ||
      uri.startsWith('https://' + WWW_WEB_DOMAIN + '/');
  }

  /**
   * 解析 manxia:// 或 https://manxia.top/ URI 为结构化结果（同步，不做源查找）
   */
  parse(uri: string): DeepLinkResult | null {
    try {
      // 将 https://manxia.top/ 链接转换为内部路径格式
      let pathPart: string = '';
      let queryPart: string = '';

      if (uri.startsWith(SCHEME + '://')) {
        const afterScheme: string = uri.substring(SCHEME.length + 3);
        const queryStart: number = afterScheme.indexOf('?');
        pathPart = queryStart === -1 ? afterScheme : afterScheme.substring(0, queryStart);
        queryPart = queryStart === -1 ? '' : afterScheme.substring(queryStart + 1);
      } else if (uri.startsWith('https://' + WEB_DOMAIN + '/') || uri.startsWith('https://' + WWW_WEB_DOMAIN + '/')) {
        const domainPrefix: string = uri.startsWith('https://' + WEB_DOMAIN + '/')
          ? 'https://' + WEB_DOMAIN + '/'
          : 'https://' + WWW_WEB_DOMAIN + '/';
        const afterDomain: string = uri.substring(domainPrefix.length);
        const queryStart: number = afterDomain.indexOf('?');
        pathPart = queryStart === -1 ? afterDomain : afterDomain.substring(0, queryStart);
        queryPart = queryStart === -1 ? '' : afterDomain.substring(queryStart + 1);
        // 将网页路径映射为内部路由
        pathPart = this.mapWebPathToRoute(pathPart);
      } else {
        logger.warn(TAG, `非 manxia 协议: ${uri}`);
        return null;
      }

      const queryParams: DeepLinkQueryParams = this.parseQueryString(queryPart);
      const pathSegments: string[] = pathPart.split('/').filter((s: string) => s.length > 0);

      if (pathSegments.length === 0) {
        logger.warn(TAG, `空路径: ${uri}`);
        return null;
      }

      const route: string = pathSegments[0];

      // 小说路由: manxia://novel/...
      if (route === 'novel') {
        return this.parseNovelRoute(pathSegments, queryParams);
      }

      if (route === 'search') {
        return this.parseSearchRoute(pathSegments, queryParams);
      }
      if (route === 'source') {
        return this.parseSourceRoute(pathSegments, queryParams);
      }
      if (route === 'detail') {
        return this.parseDetailRoute(pathSegments);
      }
      if (route === 'page') {
        return this.parsePageRoute(pathSegments, queryParams);
      }

      logger.warn(TAG, `未知路由: route=${route}`);
      return null;
    } catch (error) {
      logger.error(TAG, `解析失败: ${String(error)}`);
      return null;
    }
  }

  // ── 漫画源查找 ──

  /**
   * 异步查找漫画源（按名称、别名、pkg、或数字ID）
   */
  async resolveSource(sourceKey: string): Promise<SourceInfo | null> {
    try {
      const sm: SourceManager = SourceManager.getInstance();
      const allSources: SourceInfo[] = await sm.getAllSources();

      // 1. 名称精确匹配
      const byName: SourceInfo | undefined = allSources.find(
        (s: SourceInfo) => s.name === sourceKey
      );
      if (byName) {
        logger.info(TAG, `漫画源名称匹配: ${sourceKey} → ${byName.name} (ID: ${byName.id})`);
        return byName;
      }

      // 2. 别名匹配
      const aliasTarget: string = this.mapSourceAlias(sourceKey);
      if (aliasTarget.length > 0) {
        const byAlias: SourceInfo | undefined = allSources.find(
          (s: SourceInfo) => s.name === aliasTarget
        );
        if (byAlias) {
          logger.info(TAG, `漫画源别名匹配: ${sourceKey} → ${byAlias.name} (ID: ${byAlias.id})`);
          return byAlias;
        }
      }

      // 3. 名称忽略大小写
      const lowerKey: string = sourceKey.toLowerCase();
      const byNameLower: SourceInfo | undefined = allSources.find(
        (s: SourceInfo) => s.name.toLowerCase() === lowerKey
      );
      if (byNameLower) {
        logger.info(TAG, `漫画源名称匹配(忽略大小写): ${sourceKey} → ${byNameLower.name} (ID: ${byNameLower.id})`);
        return byNameLower;
      }

      // 4. pkg 匹配
      const byPkg: SourceInfo | undefined = allSources.find(
        (s: SourceInfo) => s.pkg !== undefined && (s.pkg === sourceKey || s.pkg.includes(sourceKey))
      );
      if (byPkg) {
        logger.info(TAG, `漫画源pkg匹配: ${sourceKey} → ${byPkg.name} (ID: ${byPkg.id})`);
        return byPkg;
      }

      // 5. 数字ID匹配
      const asNum: number = Number(sourceKey);
      if (!isNaN(asNum) && asNum > 0) {
        const byId: SourceInfo | undefined = allSources.find(
          (s: SourceInfo) => s.id === asNum
        );
        if (byId) {
          logger.info(TAG, `漫画源ID匹配: ${sourceKey} → ${byId.name} (ID: ${byId.id})`);
          return byId;
        }
      }

      logger.warn(TAG, `未找到漫画源: ${sourceKey}`);
      return null;
    } catch (error) {
      logger.error(TAG, `查找漫画源失败: ${String(error)}`);
      return null;
    }
  }

  // ── 小说源查找 ──

  /**
   * 异步查找小说源（按名称、URL、或别名）
   * 小说源的 id = bookSourceUrl，name = bookSourceName
   */
  async resolveNovelSource(sourceKey: string): Promise<NovelSourceInfo | null> {
    try {
      const nsm: NovelSourceManager = NovelSourceManager.getInstance();
      const allSources: NovelSourceInfo[] = nsm.getAllSources();

      // 1. 名称精确匹配
      const byName: NovelSourceInfo | undefined = allSources.find(
        (s: NovelSourceInfo) => s.name === sourceKey
      );
      if (byName) {
        logger.info(TAG, `小说源名称匹配: ${sourceKey} → ${byName.name} (${byName.id})`);
        return byName;
      }

      // 2. 名称忽略大小写
      const lowerKey: string = sourceKey.toLowerCase();
      const byNameLower: NovelSourceInfo | undefined = allSources.find(
        (s: NovelSourceInfo) => s.name.toLowerCase() === lowerKey
      );
      if (byNameLower) {
        logger.info(TAG, `小说源名称匹配(忽略大小写): ${sourceKey} → ${byNameLower.name}`);
        return byNameLower;
      }

      // 3. URL 匹配（sourceId = bookSourceUrl）
      const byUrl: NovelSourceInfo | undefined = allSources.find(
        (s: NovelSourceInfo) => s.id === sourceKey || s.url === sourceKey
      );
      if (byUrl) {
        logger.info(TAG, `小说源URL匹配: ${sourceKey} → ${byUrl.name}`);
        return byUrl;
      }

      // 4. URL 包含匹配
      const byUrlContains: NovelSourceInfo | undefined = allSources.find(
        (s: NovelSourceInfo) => s.id.includes(sourceKey) || s.url.includes(sourceKey)
      );
      if (byUrlContains) {
        logger.info(TAG, `小说源URL包含匹配: ${sourceKey} → ${byUrlContains.name}`);
        return byUrlContains;
      }

      logger.warn(TAG, `未找到小说源: ${sourceKey}`);
      return null;
    } catch (error) {
      logger.error(TAG, `查找小说源失败: ${String(error)}`);
      return null;
    }
  }

  // ── 导航 ──

  /**
   * 执行深度链接导航（异步）
   */
  async navigate(uri: string): Promise<boolean> {
    const result: DeepLinkResult | null = this.parse(uri);
    if (!result) {
      return false;
    }
    const routeName: string = result.route;

    this.clearStoredRoutePayload();

    // ── 漫画路由 ──

    if (result.route === 'search') {
      const r: DeepLinkSearchResult = result as DeepLinkSearchResult;
      AppStorage.setOrCreate('deepLinkSource', r.sourceKey);
      AppStorage.setOrCreate('deepLinkType', r.searchType);
      AppStorage.setOrCreate('deepLinkQuery', r.query);
      this.storeRouteMarker(r.route);
      logger.info(TAG, `漫画搜索路由: source=${r.sourceKey}, query=${r.query}`);
      return true;
    }

    if (result.route === 'source') {
      const r: DeepLinkSourceResult = result as DeepLinkSourceResult;
      const source: SourceInfo | null = await this.resolveSource(r.sourceKey);
      if (!source) {
        logger.warn(TAG, `漫画源未找到: ${r.sourceKey}`);
        return false;
      }
      AppStorage.setOrCreate('deepLinkSourceId', source.id);
      AppStorage.setOrCreate('deepLinkTab', r.tab);
      AppStorage.setOrCreate('deepLinkKeyword', r.keyword);
      this.storeRouteMarker(r.route);
      logger.info(TAG, `漫画源路由: ${source.name} (ID: ${source.id})`);
      return true;
    }

    if (result.route === 'detail') {
      const r: DeepLinkDetailResult = result as DeepLinkDetailResult;
      const source: SourceInfo | null = await this.resolveSource(r.sourceKey);
      if (!source) {
        logger.warn(TAG, `漫画源未找到: ${r.sourceKey}`);
        return false;
      }
      AppStorage.setOrCreate('deepLinkSourceId', source.id);
      AppStorage.setOrCreate('deepLinkContentId', r.contentId);
      this.storeRouteMarker(r.route);
      logger.info(TAG, `漫画内容直达: ${source.name}, contentId=${r.contentId}`);
      return true;
    }

    // ── 小说路由 ──

    if (result.route === 'novelSearch') {
      const r: DeepLinkNovelSearchResult = result as DeepLinkNovelSearchResult;
      const source: NovelSourceInfo | null = await this.resolveNovelSource(r.sourceKey);
      if (!source) {
        logger.warn(TAG, `小说源未找到: ${r.sourceKey}`);
        return false;
      }
      AppStorage.setOrCreate('deepLinkNovelSourceId', source.id);
      AppStorage.setOrCreate('deepLinkNovelSourceName', source.name);
      AppStorage.setOrCreate('deepLinkQuery', r.query);
      this.storeRouteMarker(r.route);
      logger.info(TAG, `小说搜索路由: ${source.name}, query=${r.query}`);
      return true;
    }

    if (result.route === 'novelSource') {
      const r: DeepLinkNovelSourceResult = result as DeepLinkNovelSourceResult;
      const source: NovelSourceInfo | null = await this.resolveNovelSource(r.sourceKey);
      if (!source) {
        logger.warn(TAG, `小说源未找到: ${r.sourceKey}`);
        return false;
      }
      AppStorage.setOrCreate('deepLinkNovelSourceId', source.id);
      AppStorage.setOrCreate('deepLinkNovelSourceName', source.name);
      this.storeRouteMarker(r.route);
      logger.info(TAG, `小说源路由: ${source.name}`);
      return true;
    }

    if (result.route === 'novelDetail') {
      const r: DeepLinkNovelDetailResult = result as DeepLinkNovelDetailResult;
      const source: NovelSourceInfo | null = await this.resolveNovelSource(r.sourceKey);
      if (!source) {
        logger.warn(TAG, `小说源未找到: ${r.sourceKey}`);
        return false;
      }
      AppStorage.setOrCreate('deepLinkNovelSourceId', source.id);
      AppStorage.setOrCreate('deepLinkNovelSourceName', source.name);
      AppStorage.setOrCreate('deepLinkNovelBookUrl', r.bookUrl);
      this.storeRouteMarker(r.route);
      logger.info(TAG, `小说内容直达: ${source.name}, bookUrl=${r.bookUrl}`);
      return true;
    }

    // ── 通用路由 ──

    if (result.route === 'page') {
      const r: DeepLinkPageResult = result as DeepLinkPageResult;
      if (r.action.length > 0) {
        this.storePageRouteForLater(r);
        logger.info(TAG, `页面动作路由已存储: page=${r.pageName}, action=${r.action}`);
        return true;
      }

      const stack: NavPathStack | undefined = AppStorage.get<NavPathStack>('GlobalNavStack');
      if (stack) {
        stack.pushPathByName(r.pageName, undefined);
        logger.info(TAG, `页面路由跳转: ${r.pageName}`);
        return true;
      }
      logger.warn(TAG, 'GlobalNavStack 不可用');
      return false;
    }

    logger.info(TAG, `通用路由暂不支持自动导航: ${routeName}`);
    return false;
  }

  /**
   * 同步存储解析结果到 AppStorage（不执行异步源查找）
   * 用于冷启动场景：先存储，等初始化完成后再由 MainMenuPage 解析源并跳转
   */
  storeForLater(uri: string): boolean {
    const result: DeepLinkResult | null = this.parse(uri);
    if (!result) {
      return false;
    }

    this.clearStoredRoutePayload();

    if (result.route === 'search') {
      const r: DeepLinkSearchResult = result as DeepLinkSearchResult;
      AppStorage.setOrCreate('deepLinkSource', r.sourceKey);
      AppStorage.setOrCreate('deepLinkType', r.searchType);
      AppStorage.setOrCreate('deepLinkQuery', r.query);
      this.storeRouteMarker(r.route);
      logger.info(TAG, `同步存储搜索路由: source=${r.sourceKey}`);
      return true;
    }

    if (result.route === 'source') {
      const r: DeepLinkSourceResult = result as DeepLinkSourceResult;
      AppStorage.setOrCreate('deepLinkSource', r.sourceKey);
      AppStorage.setOrCreate('deepLinkTab', r.tab);
      AppStorage.setOrCreate('deepLinkKeyword', r.keyword);
      this.storeRouteMarker(r.route);
      logger.info(TAG, `同步存储图源路由: source=${r.sourceKey}`);
      return true;
    }

    if (result.route === 'detail') {
      const r: DeepLinkDetailResult = result as DeepLinkDetailResult;
      AppStorage.setOrCreate('deepLinkSource', r.sourceKey);
      AppStorage.setOrCreate('deepLinkContentId', r.contentId);
      this.storeRouteMarker(r.route);
      logger.info(TAG, `同步存储漫画直达: source=${r.sourceKey}, contentId=${r.contentId}`);
      return true;
    }

    if (result.route === 'novelSearch') {
      const r: DeepLinkNovelSearchResult = result as DeepLinkNovelSearchResult;
      AppStorage.setOrCreate('deepLinkSource', r.sourceKey);
      AppStorage.setOrCreate('deepLinkQuery', r.query);
      this.storeRouteMarker(r.route);
      logger.info(TAG, `同步存储小说搜索: source=${r.sourceKey}`);
      return true;
    }

    if (result.route === 'novelSource') {
      const r: DeepLinkNovelSourceResult = result as DeepLinkNovelSourceResult;
      AppStorage.setOrCreate('deepLinkSource', r.sourceKey);
      this.storeRouteMarker(r.route);
      logger.info(TAG, `同步存储小说源: source=${r.sourceKey}`);
      return true;
    }

    if (result.route === 'novelDetail') {
      const r: DeepLinkNovelDetailResult = result as DeepLinkNovelDetailResult;
      AppStorage.setOrCreate('deepLinkSource', r.sourceKey);
      AppStorage.setOrCreate('deepLinkNovelBookUrl', r.bookUrl);
      this.storeRouteMarker(r.route);
      logger.info(TAG, `同步存储小说直达: source=${r.sourceKey}`);
      return true;
    }

    if (result.route === 'page') {
      const r: DeepLinkPageResult = result as DeepLinkPageResult;
      this.storePageRouteForLater(r);
      logger.info(TAG, `同步存储页面路由: page=${r.pageName}, action=${r.action}`);
      return true;
    }

    return false;
  }

  private storeRouteMarker(route: string): void {
    AppStorage.setOrCreate('deepLinkRoute', route);
    AppStorage.setOrCreate('hasDeepLink', true);
    AppStorage.setOrCreate('deepLinkTrigger', Date.now());
  }

  private storePageRouteForLater(result: DeepLinkPageResult): void {
    AppStorage.setOrCreate('deepLinkPageName', result.pageName);
    if (result.action.length > 0) {
      AppStorage.setOrCreate('deepLinkPageAction', result.action);
    } else {
      AppStorage.delete('deepLinkPageAction');
    }
    this.storeRouteMarker(result.route);
  }

  private clearStoredRoutePayload(): void {
    AppStorage.setOrCreate('hasDeepLink', false);
    AppStorage.delete('deepLinkRoute');
    AppStorage.delete('deepLinkSource');
    AppStorage.delete('deepLinkSourceId');
    AppStorage.delete('deepLinkNovelSourceId');
    AppStorage.delete('deepLinkNovelSourceName');
    AppStorage.delete('deepLinkType');
    AppStorage.delete('deepLinkQuery');
    AppStorage.delete('deepLinkTab');
    AppStorage.delete('deepLinkKeyword');
    AppStorage.delete('deepLinkContentId');
    AppStorage.delete('deepLinkNovelBookUrl');
    AppStorage.delete('deepLinkPageName');
    AppStorage.delete('deepLinkPageAction');
  }

  // ── 格式化预览 ──

  formatResult(result: DeepLinkResult): string {
    const routeName: string = result.route;

    if (result.route === 'search') {
      const r: DeepLinkSearchResult = result as DeepLinkSearchResult;
      return `[漫画] 搜索图源: ${r.sourceKey}\n搜索类型: ${r.searchType}\n搜索内容: ${r.query}`;
    }
    if (result.route === 'source') {
      const r: DeepLinkSourceResult = result as DeepLinkSourceResult;
      const tabInfo: string = r.tab ? `\n标签: ${r.tab}` : '';
      const kwInfo: string = r.keyword ? `\n搜索: ${r.keyword}` : '';
      return `[漫画] 打开图源: ${r.sourceKey}${tabInfo}${kwInfo}`;
    }
    if (result.route === 'detail') {
      const r: DeepLinkDetailResult = result as DeepLinkDetailResult;
      return `[漫画] 直达内容: ${r.sourceKey}\n内容ID: ${r.contentId}`;
    }
    if (result.route === 'novelSearch') {
      const r: DeepLinkNovelSearchResult = result as DeepLinkNovelSearchResult;
      return `[小说] 搜索书源: ${r.sourceKey}\n搜索内容: ${r.query}`;
    }
    if (result.route === 'novelSource') {
      const r: DeepLinkNovelSourceResult = result as DeepLinkNovelSourceResult;
      return `[小说] 打开书源: ${r.sourceKey}`;
    }
    if (result.route === 'novelDetail') {
      const r: DeepLinkNovelDetailResult = result as DeepLinkNovelDetailResult;
      return `[小说] 直达书籍\n书源: ${r.sourceKey}\n地址: ${r.bookUrl}`;
    }
    if (result.route === 'page') {
      const r: DeepLinkPageResult = result as DeepLinkPageResult;
      if (r.action.length > 0) {
        return `跳转页面: ${r.pageName}\n动作: ${r.action}`;
      }
      return `跳转页面: ${r.pageName}`;
    }
    return `路由: ${routeName}`;
  }

  // ── 内部解析方法 ──

  /**
   * 解析小说路由: manxia://novel/{subRoute}/...
   */
  private parseNovelRoute(pathSegments: string[], queryParams: DeepLinkQueryParams): DeepLinkResult | null {
    if (pathSegments.length < 2) {
      logger.warn(TAG, '小说路由缺少子路由');
      return null;
    }

    const subRoute: string = pathSegments[1];

    // manxia://novel/search/{source}?q={keyword}
    if (subRoute === 'search') {
      if (pathSegments.length < 3) {
        logger.warn(TAG, '小说搜索路由缺少 source');
        return null;
      }
      const result: DeepLinkNovelSearchResult = {
        route: 'novelSearch',
        sourceKey: decodeURIComponent(pathSegments[2]),
        query: queryParams.q
      };
      if (!result.query) {
        logger.warn(TAG, '小说搜索路由缺少 q 参数');
        return null;
      }
      logger.info(TAG, `小说搜索解析: source=${result.sourceKey}, query=${result.query}`);
      return result;
    }

    // manxia://novel/source/{source}
    if (subRoute === 'source') {
      if (pathSegments.length < 3) {
        logger.warn(TAG, '小说源路由缺少 source');
        return null;
      }
      const result: DeepLinkNovelSourceResult = {
        route: 'novelSource',
        sourceKey: decodeURIComponent(pathSegments[2])
      };
      logger.info(TAG, `小说源解析: source=${result.sourceKey}`);
      return result;
    }

    // manxia://novel/detail?s={sourceId}&b={bookUrl}（推荐，支持含斜杠的URL）
    // manxia://novel/detail/{source}/{encodedBookUrl}（兼容旧格式）
    if (subRoute === 'detail') {
      // 优先从查询参数读取（新格式）
      const qs: string = queryParams.s;
      const qb: string = queryParams.b;
      if (qs && qb) {
        const result: DeepLinkNovelDetailResult = {
          route: 'novelDetail',
          sourceKey: qs,
          bookUrl: qb
        };
        logger.info(TAG, `小说直达解析(查询参数): source=${result.sourceKey}, bookUrl=${result.bookUrl}`);
        return result;
      }
      // fallback 到路径格式（旧格式兼容）
      if (pathSegments.length >= 4) {
        const result: DeepLinkNovelDetailResult = {
          route: 'novelDetail',
          sourceKey: decodeURIComponent(pathSegments[2]),
          bookUrl: decodeURIComponent(pathSegments.slice(3).join('/'))
        };
        logger.info(TAG, `小说直达解析(路径): source=${result.sourceKey}, bookUrl=${result.bookUrl}`);
        return result;
      }
      logger.warn(TAG, '小说直达路由缺少参数，需要 s(sourceId) 和 b(bookUrl)');
      return null;
    }

    logger.warn(TAG, `未知的小说子路由: ${subRoute}`);
    return null;
  }

  private parseSearchRoute(pathSegments: string[], queryParams: DeepLinkQueryParams): DeepLinkSearchResult | null {
    if (pathSegments.length < 2) {
      logger.warn(TAG, '搜索路由缺少 source 参数');
      return null;
    }

    const sourceKey: string = decodeURIComponent(pathSegments[1]);
    const rawType: string = queryParams.type || 'search';
    const mappedSearchType: string = this.mapSearchType(rawType);
    const query: string = queryParams.query;

    if (!query) {
      logger.warn(TAG, '搜索路由缺少 query 参数');
      return null;
    }

    const result: DeepLinkSearchResult = {
      route: 'search',
      sourceKey: sourceKey,
      searchType: mappedSearchType,
      query: query
    };
    logger.info(TAG, `漫画搜索解析: source=${sourceKey}, type=${mappedSearchType}, query=${result.query}`);
    return result;
  }

  private parseSourceRoute(pathSegments: string[], queryParams: DeepLinkQueryParams): DeepLinkSourceResult | null {
    if (pathSegments.length < 2) {
      logger.warn(TAG, '图源路由缺少 source 参数');
      return null;
    }
    const result: DeepLinkSourceResult = {
      route: 'source',
      sourceKey: decodeURIComponent(pathSegments[1]),
      tab: queryParams.tab,
      keyword: queryParams.q
    };
    logger.info(TAG, `漫画源解析: source=${result.sourceKey}, tab=${result.tab}`);
    return result;
  }

  private parseDetailRoute(pathSegments: string[]): DeepLinkDetailResult | null {
    if (pathSegments.length < 3) {
      logger.warn(TAG, '内容直达路由格式错误，需要: detail/{source}/{contentId}');
      return null;
    }
    const result: DeepLinkDetailResult = {
      route: 'detail',
      sourceKey: decodeURIComponent(pathSegments[1]),
      contentId: decodeURIComponent(pathSegments.slice(2).join('/'))
    };
    logger.info(TAG, `漫画内容直达解析: source=${result.sourceKey}, contentId=${result.contentId}`);
    return result;
  }

  private parsePageRoute(pathSegments: string[], queryParams: DeepLinkQueryParams): DeepLinkPageResult | null {
    if (pathSegments.length < 2) {
      logger.warn(TAG, '页面路由缺少 pageName');
      return null;
    }
    const result: DeepLinkPageResult = {
      route: 'page',
      pageName: decodeURIComponent(pathSegments[1]),
      action: queryParams.action
    };
    logger.info(TAG, `页面路由解析: page=${result.pageName}, action=${result.action}`);
    return result;
  }

  private parseQueryString(queryPart: string): DeepLinkQueryParams {
    const params: DeepLinkQueryParams = {
      type: '',
      query: '',
      q: '',
      tab: '',
      s: '',
      b: '',
      action: ''
    };
    if (!queryPart) {
      return params;
    }
    const pairs: string[] = queryPart.split('&');
    for (const pair of pairs) {
      const eqIndex: number = pair.indexOf('=');
      if (eqIndex > 0) {
        this.assignQueryParam(params, pair.substring(0, eqIndex), decodeURIComponent(pair.substring(eqIndex + 1)));
      } else if (pair.length > 0) {
        this.assignQueryParam(params, pair, '');
      }
    }
    return params;
  }

  private assignQueryParam(params: DeepLinkQueryParams, key: string, value: string): void {
    if (key === 'type') {
      params.type = value;
    } else if (key === 'query') {
      params.query = value;
    } else if (key === 'q') {
      params.q = value;
    } else if (key === 'tab') {
      params.tab = value;
    } else if (key === 's') {
      params.s = value;
    } else if (key === 'b') {
      params.b = value;
    } else if (key === 'action') {
      params.action = value;
    }
  }

  private mapSourceAlias(sourceKey: string): string {
    const key: string = sourceKey.toLowerCase();
    if (key === 'jm') {
      return '禁漫天堂';
    }
    if (key === 'pica' || key === 'bika' || key === 'picacomic') {
      return '哔咔漫画';
    }
    if (key === 'pixiv') {
      return 'Pixiv';
    }
    return '';
  }

  private mapSearchType(rawType: string): string {
    const key: string = rawType.toLowerCase();
    if (key === 'id') {
      return 'searchById';
    }
    if (key === 'user' || key === 'author' || key === 'uid') {
      return 'searchByAuthor';
    }
    return rawType;
  }

  /**
   * 将网页路径映射为内部路由路径
   * /d/{source}/{contentId}  → detail/{source}/{contentId}
   * /n                       → novel/detail
   * /s/{source}              → search/{source}
   * /transfer                → page/TransferPage
   */
  private mapWebPathToRoute(webPath: string): string {
    const segments: string[] = webPath.split('/').filter((s: string) => s.length > 0);
    if (segments.length === 0) {
      return '';
    }

    const prefix: string = segments[0];

    // /d/{source}/{contentId} → detail/{source}/{contentId}
    if (prefix === 'd' && segments.length >= 3) {
      return `detail/${segments[1]}/${segments.slice(2).join('/')}`;
    }

    // /n → novel/detail
    if (prefix === 'n') {
      return 'novel/detail';
    }

    // /s/{source} → search/{source}
    if (prefix === 's' && segments.length >= 2) {
      return `search/${segments[1]}`;
    }

    if (prefix === 'transfer') {
      return 'page/TransferPage';
    }

    return webPath;
  }
}
