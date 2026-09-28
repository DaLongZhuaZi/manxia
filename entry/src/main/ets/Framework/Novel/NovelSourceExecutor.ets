import { SafeUtils } from 'manxia_core/src/main/ets/Utils/SafeUtils';
/**
 * 小说源执行器
 * 负责执行书源的搜索、获取详情、目录、正文等操作
 * 
 * 文件路径: entry/src/main/ets/Framework/Novel/NovelSourceExecutor.ets
 */

import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import {
  LegadoBookSource,
  LegadoSearchBook,
  LegadoBook,
  LegadoChapter,
  LegadoExploreKind,
  LegadoBookSourceType
} from 'manxia_novel/src/main/ets/Framework/Novel/LegadoSourceTypes';
import { LegadoSourceParser } from 'manxia_novel/src/main/ets/Framework/Novel/LegadoSourceParser';
import { LegadoRuleAnalyzer } from './LegadoRuleAnalyzer';
import { LegadoUrlAnalyzer, ParsedUrlRequest, RequestMethod } from './LegadoUrlAnalyzer';
import { getLegadoJsEngine, JsContext, LegadoJsSourceEffects } from './LegadoJsEngine';
import { getNovelReplaceRuleManager, ReplaceScope } from './NovelReplaceRuleManager';
import { getNovelLoginManager } from './NovelLoginManager';
import { HtmlFormatter } from 'manxia_novel/src/main/ets/Framework/Novel/HtmlFormatter';
import { ProxyManager } from 'manxia_network/src/main/ets/Framework/Network/ProxyManager';
import { LegadoMangaExtractedImage, LegadoMangaImageExtractor } from 'manxia_novel/src/main/ets/Framework/Novel/LegadoMangaImageExtractor';

const TAG = 'NovelSourceExecutor';
const REQUEST_TIMEOUT_MS = 15000;
const EXPLORE_KIND_JS_RETRY_DELAYS_MS: number[] = [120, 260, 500, 900];

/**
 * 章节列表解析结果
 */
interface ChapterListParseResult {
  chapters: LegadoChapter[];
  nextUrl: string | null;
}

/**
 * 正文解析结果
 */
interface ContentParseResult {
  content: string;
  nextUrl: string | null;
  nextUrls?: string[];
}

/**
 * 搜索错误类型 - 用于细化校验分组
 */
export enum SearchErrorType {
  NONE = 'none',                          // 无错误
  TIMEOUT = 'timeout',                    // 网络超时
  SSL_ERROR = 'ssl_error',                // SSL证书错误
  NETWORK_ERROR = 'network_error',        // 网络连接失败
  HTTP_404 = 'http_404',                  // HTTP 404
  HTTP_403 = 'http_403',                  // HTTP 403
  HTTP_5XX = 'http_5xx',                  // HTTP 5xx
  HTTP_OTHER = 'http_other',              // 其他HTTP错误
  JS_SOURCE_UNDEFINED = 'js_source_undef',// JS中source未定义
  JS_FUNCTION_UNDEFINED = 'js_func_undef',// JS中函数未定义
  JS_ERROR = 'js_error',                  // 其他JS错误
  URL_PARSE_ERROR = 'url_parse',          // URL解析失败
  PARSE_ERROR = 'parse_error',            // 解析规则错误
  UNKNOWN = 'unknown'                     // 未知错误
}

/**
 * 搜索结果（带错误信息）
 */
export interface SearchResultWithError {
  books: LegadoSearchBook[];
  errorType: SearchErrorType;
  errorMessage: string;
}

/**
 * HTTP请求结果（带错误信息）
 */
interface HttpRequestResult {
  response: string | null;
  errorType?: SearchErrorType;
  errorMessage?: string;
}

/**
 * 搜索解析选项
 * 用于在高并发校验场景下降低主线程解析压力
 */
export interface SearchParseOptions {
  /** 最多保留多少条搜索结果（<=0 时表示不限制） */
  maxResults?: number;
  /** 最多扫描多少个候选元素（<=0 时表示不限制） */
  maxElementScan?: number;
  /** 是否禁用 item 级 DOM bridge（改用字符串解析） */
  disableItemDomBridge?: boolean;
  forceFullExecution?: boolean;
  yieldSliceMs?: number;
}

/**
 * 小说源执行器类
 */
export class NovelSourceExecutor {
  private static readonly ENABLE_SEARCH_PARSE_TRACE: boolean = false;
  private static readonly JS_RULE_TOKEN_PATTERN: RegExp = /<js>|(?:@|＠)js(?:\:|：)/i;
  private static readonly UNRESOLVED_RULE_TOKEN_PATTERN: RegExp = /(?:@|＠)js(?:\:|：)|<js>|\{\{|\}\}|｛｛|｝｝/i;
  private source: LegadoBookSource;
  private urlAnalyzer: LegadoUrlAnalyzer;
  private contentVariableWarmupTriedBookUrls: Set<string> = new Set();
  private contentVariableWarmupReadyBookUrls: Set<string> = new Set();

  constructor(source: LegadoBookSource) {
    this.source = source;
    // 传入baseUrl和sourceUrl，支持JS中的source.getKey()
    this.urlAnalyzer = new LegadoUrlAnalyzer(
      LegadoSourceParser.getBaseUrl(source),
      source.bookSourceUrl,
      source.jsLib || ''
    );
    this.injectSourceContextToUrlAnalyzer();
  }
  
  /**
   * 确保当前执行器使用当前书源的jsLib快照
   */
  private ensureJsLib(): void {
    // 仅更新当前执行器的URL解析器快照，避免并发校验时污染全局jsLib
    this.urlAnalyzer.setJsLib(this.source.jsLib || '');
    this.injectSourceContextToUrlAnalyzer();
  }

  private createRuleAnalyzer(): LegadoRuleAnalyzer {
    const analyzer = new LegadoRuleAnalyzer();
    analyzer.setJsLib(this.source.jsLib || '');
    const contextVariables = this.buildRuleAnalyzerContextVariables();
    const keys = Object.keys(contextVariables);
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i];
      analyzer.put(key, contextVariables[key]);
    }
    return analyzer;
  }

  private buildRuleAnalyzerContextVariables(): Record<string, string> {
    const sourceVariables = this.buildSourceContextVariables();
    const urlVariables = this.urlAnalyzer.getVariablesSnapshot();
    const merged: Record<string, string> = {};

    const sourceKeys = Object.keys(sourceVariables);
    for (let i = 0; i < sourceKeys.length; i++) {
      const key = sourceKeys[i];
      merged[key] = sourceVariables[key];
    }

    const urlKeys = Object.keys(urlVariables);
    for (let i = 0; i < urlKeys.length; i++) {
      const key = urlKeys[i];
      merged[key] = urlVariables[key];
    }
    return merged;
  }

  private injectSourceContextToUrlAnalyzer(): void {
    this.urlAnalyzer.setVariables(this.buildSourceContextVariables());
  }

  private buildSourceContextVariables(): Record<string, string> {
    const loginManager = getNovelLoginManager();
    const sourceId = this.source.bookSourceUrl || '';
    const sourceData = loginManager.getSourceDataSnapshot(sourceId);
    const variables: Record<string, string> = {};
    variables['sourceUrl'] = sourceId;
    variables['__source_bookSourceName'] = this.source.bookSourceName || '';
    variables['__source_bookSourceGroup'] = this.source.bookSourceGroup || '';
    variables['__source_bookSourceComment'] = this.source.bookSourceComment || '';
    variables['__source_header'] = this.source.header || '';
    variables['__source_loginUrl'] = this.source.loginUrl || '';
    variables['__source_loginUi'] = this.source.loginUi || '';
    variables['__source_loginCheckJs'] = this.source.loginCheckJs || '';
    variables['__source_variableComment'] = this.source.variableComment || '';
    variables['__loginInfo'] = loginManager.getLoginInfo(sourceId);
    variables['__loginHeader'] = loginManager.getLoginHeader(sourceId);
    variables['__sourceVariable'] = loginManager.getSourceVariable(sourceId);
    variables['__sourceData'] = JSON.stringify(sourceData);
    variables['cookie'] = loginManager.getCookieString(sourceId);
    return variables;
  }

  private persistSourceEffects(effects?: LegadoJsSourceEffects): void {
    if (!effects) {
      return;
    }

    const sourceId = this.source.bookSourceUrl || '';
    if (sourceId.length <= 0) {
      return;
    }

    const loginManager = getNovelLoginManager();
    if (effects.loginInfo !== undefined) {
      loginManager.putLoginInfo(sourceId, effects.loginInfo);
    }
    if (effects.removeLoginHeader === true) {
      loginManager.removeLoginHeader(sourceId);
    }
    if (effects.loginHeader !== undefined) {
      loginManager.putLoginHeader(sourceId, effects.loginHeader);
    }
    if (effects.sourceVariable !== undefined) {
      loginManager.setSourceVariable(sourceId, effects.sourceVariable);
    }
    if (effects.data && effects.data.length > 0) {
      for (let i = 0; i < effects.data.length; i++) {
        const item = effects.data[i];
        if (!item || item.key.length <= 0) {
          continue;
        }
        loginManager.putSourceData(sourceId, item.key, item.value);
      }
    }

    this.injectSourceContextToUrlAnalyzer();
  }

  private searchParseTrace(messageBuilder: () => string): void {
    if (!NovelSourceExecutor.ENABLE_SEARCH_PARSE_TRACE) {
      return;
    }
    logger.debug(TAG, messageBuilder());
  }

  /**
   * 搜索书籍
   */
  async search(
    keyword: string,
    page: number = 1,
    parseOptions?: SearchParseOptions
  ): Promise<LegadoSearchBook[]> {
    const result = await this.searchWithError(keyword, page, parseOptions);
    return result.books;
  }
  
  /**
   * 搜索书籍（带详细错误信息）
   * 用于校验时获取详细的错误类型
   */
  async searchWithError(
    keyword: string,
    page: number = 1,
    parseOptions?: SearchParseOptions
  ): Promise<SearchResultWithError> {
    if (!this.source.searchUrl) {
      logger.warn(TAG, `[书源:${this.source.bookSourceName}] 没有配置搜索URL`);
      return { books: [], errorType: SearchErrorType.NONE, errorMessage: '搜索链接规则为空' };
    }

    try {
      const searchUrl = this.source.searchUrl;
      if (this.shouldAnalyzeUrlAsync(searchUrl) ||
        (searchUrl.includes('{{') && this.containsJsExpression(searchUrl))) {
        logger.debug(TAG, `[书源:${this.source.bookSourceName}] 使用异步JS解析搜索URL`);
      }

      const request = await this.analyzeRequestUrl(searchUrl, keyword, page);
      if (!request.url || this.hasUnresolvedRuleTokens(request.url) || this.isLikelyJsFragmentUrl(request.url)) {
        const urlSnippet = request.url ? request.url.substring(0, 100) : '';
        logger.warn(TAG, `[书源:${this.source.bookSourceName}] URL解析不完整: ${urlSnippet}`);
        const errorType = this.analyzeJsError(urlSnippet);
        return { books: [], errorType: errorType, errorMessage: `URL解析不完整: ${urlSnippet}` };
      }

      const requestResult = await this.executeRequestWithError(request);
      if (requestResult.errorType && requestResult.errorType !== SearchErrorType.NONE) {
        logger.warn(TAG, `[书源:${this.source.bookSourceName}] 搜索请求失败: ${requestResult.errorMessage}`);
        return {
          books: [],
          errorType: requestResult.errorType,
          errorMessage: requestResult.errorMessage || ''
        };
      }

      if (!requestResult.response) {
        logger.warn(TAG, `[书源:${this.source.bookSourceName}] 搜索请求失败，无响应数据`);
        return { books: [], errorType: SearchErrorType.NETWORK_ERROR, errorMessage: '无响应数据' };
      }

      const results = await this.parseSearchResultAsync(requestResult.response, request.url, parseOptions);
      if (results.length === 0) {
        logger.debug(TAG, `[书源:${this.source.bookSourceName}] 搜索结果为空，可能是解析规则不匹配`);
        return { books: [], errorType: SearchErrorType.PARSE_ERROR, errorMessage: '解析规则不匹配' };
      }
      return { books: results, errorType: SearchErrorType.NONE, errorMessage: '' };
    } catch (error) {
      const errorMsg = this.formatError(error);
      logger.error(TAG, `[书源:${this.source.bookSourceName}] 搜索失败: ${errorMsg}`);
      const errorType = this.analyzeErrorType(errorMsg);
      return { books: [], errorType: errorType, errorMessage: errorMsg };
    }
  }
  private analyzeJsError(urlOrError: string): SearchErrorType {
    if (this.isLikelyJsFragmentUrl(urlOrError)) {
      return SearchErrorType.JS_ERROR;
    }
    if (urlOrError.includes('source is not defined') || urlOrError.includes('sourceisnotdefined')) {
      return SearchErrorType.JS_SOURCE_UNDEFINED;
    }
    if (urlOrError.includes('is not defined') || urlOrError.includes('isnotdefined')) {
      return SearchErrorType.JS_FUNCTION_UNDEFINED;
    }
    if (urlOrError.includes('ERROR:')) {
      return SearchErrorType.JS_ERROR;
    }
    return SearchErrorType.URL_PARSE_ERROR;
  }
  
  /**
   * 分析错误类型
   */
  private analyzeErrorType(errorMsg: string): SearchErrorType {
    const lowerMsg = errorMsg.toLowerCase();

    if (lowerMsg.includes('timeout') || lowerMsg.includes('超时')) {
      return SearchErrorType.TIMEOUT;
    }
    if (lowerMsg.includes('ssl') || lowerMsg.includes('certificate')) {
      return SearchErrorType.SSL_ERROR;
    }
    if (lowerMsg.includes('source is not defined') || lowerMsg.includes('sourceisnotdefined')) {
      return SearchErrorType.JS_SOURCE_UNDEFINED;
    }
    if (lowerMsg.includes('is not defined') || lowerMsg.includes('isnotdefined')) {
      return SearchErrorType.JS_FUNCTION_UNDEFINED;
    }
    if (lowerMsg.includes('network') || lowerMsg.includes('connect') || lowerMsg.includes('网络')) {
      return SearchErrorType.NETWORK_ERROR;
    }
    if (lowerMsg.includes('invalid url') || lowerMsg.includes('missing url') || lowerMsg.includes('url format')) {
      return SearchErrorType.URL_PARSE_ERROR;
    }

    return SearchErrorType.UNKNOWN;
  }
  private containsJsExpression(str: string): boolean {
    const matches = str.match(/\{\{([^}]+)\}\}/g);
    if (!matches) {
      return false;
    }

    for (const match of matches) {
      const expr = match.slice(2, -2).trim();
      if (expr === 'key' || expr === 'page' || expr === 'encodedKey') {
        continue;
      }
      if (expr.includes('(') || expr.includes('.') || expr.includes('+') ||
        expr.includes('var ') || expr.includes('function')) {
        return true;
      }
    }
    return false;
  }

  private shouldReadRuleAsync(ruleText?: string): boolean {
    if (!ruleText) {
      return false;
    }
    const lowerRule = ruleText.toLowerCase();
    return lowerRule.includes('<js>') ||
      lowerRule.includes('@js:') ||
      lowerRule.includes('@js：') ||
      lowerRule.includes('＠js:') ||
      lowerRule.includes('＠js：') ||
      lowerRule.includes('@put:{') ||
      lowerRule.includes('@get:{') ||
      lowerRule.startsWith('js:') ||
      lowerRule.startsWith('js：') ||
      (ruleText.includes('{{') && this.containsJsExpression(ruleText));
  }

  private async readRuleString(analyzer: LegadoRuleAnalyzer, ruleText?: string): Promise<string> {
    if (!ruleText) {
      return '';
    }
    if (this.shouldReadRuleAsync(ruleText)) {
      return await analyzer.getStringAsync(ruleText);
    }
    return analyzer.getString(ruleText);
  }

  /**
   * 判断URL模板是否需要异步JS解析
   */
  private shouldAnalyzeUrlAsync(urlTemplate: string): boolean {
    if (!urlTemplate) {
      return false;
    }
    if (NovelSourceExecutor.JS_RULE_TOKEN_PATTERN.test(urlTemplate)) {
      return true;
    }
    if (/(?:^|[,{\s])["']?js["']?\s*:/i.test(urlTemplate)) {
      return true;
    }
    return urlTemplate.includes('{{') && urlTemplate.includes('}}');
  }

  /**
   * 检查URL中是否仍包含未解析模板
   */
  private hasUnresolvedRuleTokens(url: string): boolean {
    if (!url) {
      return false;
    }
    return NovelSourceExecutor.UNRESOLVED_RULE_TOKEN_PATTERN.test(url);
  }

  private isLikelyJsFragmentUrl(url: string): boolean {
    if (!url) {
      return false;
    }

    const trimmedUrl = url.trim();
    if (trimmedUrl.length === 0) {
      return false;
    }

    const lowerUrl = trimmedUrl.toLowerCase();
    if (lowerUrl.includes('date.now(') || lowerUrl.includes('javascript:')) {
      return true;
    }

    const pathStart = trimmedUrl.startsWith('https://') ? 8 : (trimmedUrl.startsWith('http://') ? 7 : 0);
    const slashIndex = trimmedUrl.indexOf('/', pathStart);
    const inspectSegment = slashIndex >= 0 ? trimmedUrl.substring(slashIndex) : trimmedUrl;

    if (inspectSegment.includes('\n') || inspectSegment.includes('\r')) {
      return true;
    }

    if (inspectSegment.includes('{') || inspectSegment.includes('}')) {
      return true;
    }

    if (inspectSegment.includes(';')) {
      const semicolonScriptPattern = /(?:^|;)\s*(?:var|let|const|function|return)\b/i;
      if (semicolonScriptPattern.test(inspectSegment)) {
        return true;
      }
    }

    const jsKeywordPattern = /\b(var|let|const|function|return)\b/i;
    return jsKeywordPattern.test(inspectSegment);
  }

  private normalizeRequestUrl(rawUrl: string): string {
    if (!rawUrl) {
      return rawUrl;
    }
    let normalized = rawUrl.trim();
    normalized = normalized
      .replace(/&amp;/gi, '&')
      .replace(/&#38;/gi, '&')
      .replace(/&#x26;/gi, '&');
    normalized = this.stripRequestSourceMarker(normalized);
    normalized = this.pickEmbeddedAbsoluteRequestUrl(normalized);
    return normalized;
  }

  private stripRequestSourceMarker(url: string): string {
    const markerMatch = url.match(/^(https?:\/\/[^\/?#]+)(##[^\/?#]*|#[^\/?#]*)(?=\/)/i);
    if (!markerMatch || markerMatch.length < 3) {
      return url;
    }
    return `${markerMatch[1]}${url.substring(markerMatch[1].length + markerMatch[2].length)}`;
  }

  private pickEmbeddedAbsoluteRequestUrl(url: string): string {
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      return url;
    }
    const secondHttp = url.indexOf('http://', 8);
    const secondHttps = url.indexOf('https://', 8);
    let secondIndex = -1;
    if (secondHttp >= 0 && secondHttps >= 0) {
      secondIndex = Math.min(secondHttp, secondHttps);
    } else if (secondHttp >= 0) {
      secondIndex = secondHttp;
    } else if (secondHttps >= 0) {
      secondIndex = secondHttps;
    }
    if (secondIndex <= 0) {
      return url;
    }
    const beforeSecond = url.substring(0, secondIndex);
    if (beforeSecond.includes('?') || beforeSecond.includes('&')) {
      return url;
    }
    return url.substring(secondIndex);
  }

  private normalizeParsedUrl(rawUrl: string | undefined, baseUrl: string, fallbackUrl: string = ''): string {
    const normalizedRawUrl = this.normalizeRequestUrl(rawUrl || '');
    const trimmedUrl = normalizedRawUrl.trim();
    if (trimmedUrl.length <= 0) {
      return fallbackUrl;
    }
    if (trimmedUrl.startsWith('http://') || trimmedUrl.startsWith('https://')) {
      return trimmedUrl;
    }
    if (trimmedUrl.startsWith('//')) {
      const baseScheme = baseUrl.startsWith('http://') ? 'http:' : 'https:';
      return `${baseScheme}${trimmedUrl}`;
    }
    if (trimmedUrl.startsWith('data:') || trimmedUrl.startsWith('javascript:')) {
      return trimmedUrl;
    }
    if (!baseUrl || baseUrl.trim().length <= 0) {
      return trimmedUrl;
    }

    try {
      const normalizedBaseUrl = this.normalizeRequestUrl(baseUrl);
      const originMatch = normalizedBaseUrl.match(/^(https?:\/\/[^\/?#]+)/i);
      if (trimmedUrl.startsWith('/')) {
        return originMatch ? `${originMatch[1]}${trimmedUrl}` : trimmedUrl;
      }

      const hashIndex = normalizedBaseUrl.indexOf('#');
      const withoutHash = hashIndex >= 0 ? normalizedBaseUrl.substring(0, hashIndex) : normalizedBaseUrl;
      const queryIndex = withoutHash.indexOf('?');
      let basePath = queryIndex >= 0 ? withoutHash.substring(0, queryIndex) : withoutHash;
      if (!basePath.endsWith('/')) {
        const slashIndex = basePath.lastIndexOf('/');
        if (slashIndex >= 0) {
          basePath = basePath.substring(0, slashIndex + 1);
        } else {
          basePath = `${basePath}/`;
        }
      }
      return `${basePath}${trimmedUrl}`;
    } catch (error) {
      logger.warn(TAG, `规则URL绝对化失败: raw=${trimmedUrl}, base=${baseUrl}, error=${String(error)}`);
      return trimmedUrl;
    }
  }

  /**
   * 智能解析URL：包含JS规则时使用异步解析，其他情况优先同步并兜底异步
   */
  private async analyzeRequestUrl(
    urlTemplate: string,
    key?: string,
    page?: number,
    runtimeBaseUrl?: string
  ): Promise<ParsedUrlRequest> {
    const runtimeBaseUrlValue = runtimeBaseUrl !== undefined ? runtimeBaseUrl.trim() : '';
    const hasRuntimeBaseUrl = runtimeBaseUrlValue.length > 0;
    const originalBaseUrl = this.urlAnalyzer.getBaseUrl();

    if (hasRuntimeBaseUrl) {
      this.urlAnalyzer.setBaseUrl(runtimeBaseUrlValue);
    }

    try {
      let request: ParsedUrlRequest;
      if (this.shouldAnalyzeUrlAsync(urlTemplate)) {
        this.ensureJsLib();
        request = await this.urlAnalyzer.analyzeUrlAsync(urlTemplate, key, page);
      } else {
        request = this.urlAnalyzer.analyzeUrl(urlTemplate, key, page);
        if (this.hasUnresolvedRuleTokens(request.url)) {
          this.ensureJsLib();
          request = await this.urlAnalyzer.analyzeUrlAsync(urlTemplate, key, page);
        }
      }
      this.persistUrlAnalyzerSourceEffects();
      return request;
    } finally {
      if (hasRuntimeBaseUrl) {
        this.urlAnalyzer.setBaseUrl(originalBaseUrl);
      }
    }
  }

  private persistUrlAnalyzerSourceEffects(): void {
    this.persistSourceEffects(this.urlAnalyzer.getSourceEffectsSnapshot());
    this.urlAnalyzer.clearSourceEffects();
  }

  private persistRuleAnalyzerSourceEffects(analyzer: LegadoRuleAnalyzer): void {
    this.persistSourceEffects(analyzer.getSourceEffectsSnapshot());
    analyzer.clearSourceEffects();
  }
  async getBookInfo(bookUrl: string): Promise<LegadoBook | null> {
    this.ensureJsLib();
    try {
      const request = await this.analyzeRequestUrl(bookUrl);
      const response = await this.executeRequest(request);

      if (!response) {
        return null;
      }

      return await this.parseBookInfoAsync(response, request.url, request.url);
    } catch (error) {
      logger.error(TAG, `获取书籍详情失败: ${String(error)}`);
      return null;
    }
  }
  async getChapterList(book: LegadoBook): Promise<LegadoChapter[]> {
    this.ensureJsLib();
    const tocUrl = book.tocUrl || book.bookUrl;
    const allChapters: LegadoChapter[] = [];
    let currentUrl: string | null = tocUrl;
    let pageCount = 0;
    const maxPages = 50;

    try {
      while (currentUrl && pageCount < maxPages) {
        const request = await this.analyzeRequestUrl(currentUrl);
        const response = await this.executeRequest(request);

        if (!response) {
          break;
        }

        const parseResult: ChapterListParseResult =
          await this.parseChapterListWithNext(response, request.url, book, allChapters.length);
        const chapters: LegadoChapter[] = parseResult.chapters;
        const nextUrl: string | null = parseResult.nextUrl;
        for (let j = 0; j < chapters.length; j++) {
          allChapters.push(chapters[j]);
        }

        if (nextUrl && nextUrl !== currentUrl) {
          currentUrl = nextUrl;
          pageCount++;
          logger.debug(TAG, `章节列表分页 ${pageCount}: ${nextUrl}`);
        } else {
          currentUrl = null;
        }
      }

      logger.info(TAG, `章节列表: ${allChapters.length} 章 (${pageCount + 1} 页)`);
      return allChapters;
    } catch (error) {
      logger.error(TAG, `获取章节列表失败: ${String(error)}`);
      return allChapters;
    }
  }
  async getContent(chapter: LegadoChapter): Promise<string> {
    this.ensureJsLib();
    const allContent: string[] = [];
    let currentUrl: string | null = chapter.url;
    const pendingUrls: string[] = [];
    const visitedUrls: Set<string> = new Set<string>();
    let pageCount = 0;
    const maxPages = 20;

    try {
      await this.prepareContentRuleVariables(chapter);
      while (currentUrl && pageCount < maxPages) {
        visitedUrls.add(currentUrl);
        const request = await this.analyzeRequestUrl(currentUrl, undefined, undefined, chapter.bookUrl);
        const response = await this.executeRequest(request);

        if (!response) {
          break;
        }

        const contentResult: ContentParseResult =
          await this.parseContentWithNext(response, request.url, chapter);
        if (contentResult.content) {
          allContent.push(contentResult.content);
        }

        const nextUrls = this.normalizeNextContentUrls(contentResult, request.url, visitedUrls, pendingUrls);
        if (nextUrls.length > 0) {
          for (let i = 0; i < nextUrls.length; i++) {
            pendingUrls.push(nextUrls[i]);
          }
        }

        if (pendingUrls.length > 0) {
          currentUrl = pendingUrls.shift() || null;
          pageCount++;
          logger.debug(TAG, `正文分页 ${pageCount}: ${currentUrl}`);
        } else {
          currentUrl = null;
        }
      }

      return allContent.join('\n\n');
    } catch (error) {
      logger.error(TAG, `获取正文失败: ${String(error)}`);
      return allContent.join('\n\n');
    }
  }
  // ==================== 发现页功能 ====================

  /**
   * 获取发现分类列表
   */
  private hasRuleVariableToken(template: string, variableName: string): boolean {
    if (!template || !variableName) {
      return false;
    }
    const escapedVariable = this.escapeRegexLiteral(variableName);
    const javaGetPattern = new RegExp(`java\\.get\\s*\\(\\s*["']${escapedVariable}["']\\s*\\)`, 'i');
    if (javaGetPattern.test(template)) {
      return true;
    }
    const directPattern = new RegExp(`\\{\\{\\s*${escapedVariable}\\s*\\}\\}`, 'i');
    return directPattern.test(template);
  }

  private escapeRegexLiteral(input: string): string {
    return input.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  }

  private parseChapterVariablePayload(variableText: string): Record<string, string> {
    const result: Record<string, string> = {};
    const trimmedText = variableText.trim();
    if (trimmedText.length <= 0) {
      return result;
    }

    const assignValue = (rawKey: string, rawValue: string): void => {
      const key = rawKey.trim();
      const value = rawValue.trim();
      if (key.length <= 0 || value.length <= 0 || value.length > 512) {
        return;
      }
      result[key] = value;
    };

    if (trimmedText.startsWith('{') && trimmedText.endsWith('}')) {
      try {
        const parsed = SafeUtils.parseObj(trimmedText) as Record<string, string | number | boolean | null>;
        const keys = Object.keys(parsed);
        for (let i = 0; i < keys.length; i++) {
          const key = keys[i];
          const parsedValue = parsed[key];
          if (parsedValue === null || parsedValue === undefined) {
            continue;
          }
          assignValue(key, String(parsedValue));
        }
      } catch (_error) {
        // 继续尝试 key=value 解析
      }
    }

    if (Object.keys(result).length > 0) {
      return result;
    }

    const pairs = trimmedText.split(/[&;\n]/);
    for (let i = 0; i < pairs.length; i++) {
      const pair = pairs[i].trim();
      if (pair.length <= 0) {
        continue;
      }
      const separatorIndex = pair.indexOf('=');
      if (separatorIndex <= 0 || separatorIndex >= pair.length - 1) {
        continue;
      }
      const key = pair.substring(0, separatorIndex);
      const value = pair.substring(separatorIndex + 1);
      assignValue(key, value);
    }

    return result;
  }

  private mergeRuleVariables(target: Record<string, string>, source: Record<string, string>): void {
    const keys = Object.keys(source);
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i];
      const value = source[key];
      if (!key || !value) {
        continue;
      }
      target[key] = value;
    }
  }

  private applyVariablesToUrlAnalyzer(variables: Record<string, string>, reason: string): void {
    const keys = Object.keys(variables);
    let applied = 0;
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i];
      const value = variables[key];
      if (!key || !value || value.length > 1024) {
        continue;
      }
      this.urlAnalyzer.setVariable(key, value);
      applied++;
    }
    if (applied > 0) {
      logger.debug(TAG, `同步正文规则变量成功(${reason}): ${applied} 项`);
    }
  }

  private resolveEntityTypeFallback(chapter: LegadoChapter, variables: Record<string, string>): string {
    const candidateKeys: string[] = ['entityType', 'baseEntityType', 'entity_type'];
    for (let i = 0; i < candidateKeys.length; i++) {
      const candidateKey = candidateKeys[i];
      if (Object.keys(variables).includes(candidateKey)) {
        const value = (variables[candidateKey] || '').trim();
        if (value.length > 0) {
          return value;
        }
      }
    }

    const chapterUrl = (chapter.url || '').trim();
    const urlMatch = chapterUrl.match(/(?:\?|&)entityType=(\d+)/i);
    if (urlMatch && urlMatch.length > 1) {
      return urlMatch[1];
    }

    const chapterTag = (chapter.tag || '').trim();
    const tagMatch = chapterTag.match(/(?:entityType|entity_type)\s*[:=]\s*(\d+)/i);
    if (tagMatch && tagMatch.length > 1) {
      return tagMatch[1];
    }

    if (this.source.bookSourceUrl.indexOf('lrts.me') >= 0) {
      return '1';
    }

    if (this.source.bookSourceType === LegadoBookSourceType.AUDIO) {
      return '1';
    }
    return '';
  }

  private collectChapterRuleVariables(chapter: LegadoChapter): Record<string, string> {
    const variables: Record<string, string> = {};
    const chapterVariable = (chapter.variable || '').trim();
    if (chapterVariable.length > 0) {
      const parsedVariables = this.parseChapterVariablePayload(chapterVariable);
      this.mergeRuleVariables(variables, parsedVariables);
    }

    const chapterUrl = (chapter.url || '').trim();
    const sectionNumber = String(Math.max(1, chapter.index + 1));

    if (this.hasRuleVariableToken(chapterUrl, 'n')) {
      variables['n'] = sectionNumber;
    }
    if (this.hasRuleVariableToken(chapterUrl, 'section')) {
      variables['section'] = sectionNumber;
    }
    if (this.hasRuleVariableToken(chapterUrl, 'sections')) {
      variables['sections'] = `[${sectionNumber}]`;
    }
    if (this.hasRuleVariableToken(chapterUrl, 'entityType')) {
      variables['entityType'] = this.resolveEntityTypeFallback(chapter, variables);
    }

    return variables;
  }

  private needsContentRuleVariableWarmup(chapterUrl: string): boolean {
    if (!chapterUrl || chapterUrl.trim().length <= 0) {
      return false;
    }
    if (this.hasRuleVariableToken(chapterUrl, 'entityType')) {
      return true;
    }
    return /\{\{\s*java\.get\s*\(/i.test(chapterUrl);
  }

  private async warmupVariablesFromBookInfo(bookUrl: string): Promise<void> {
    const normalizedBookUrl = bookUrl.trim();
    if (normalizedBookUrl.length <= 0) {
      return;
    }
    if (this.contentVariableWarmupReadyBookUrls.has(normalizedBookUrl)) {
      return;
    }
    if (this.contentVariableWarmupTriedBookUrls.has(normalizedBookUrl)) {
      return;
    }
    this.contentVariableWarmupTriedBookUrls.add(normalizedBookUrl);

    try {
      const request = await this.analyzeRequestUrl(normalizedBookUrl);
      const response = await this.executeRequest(request);
      if (!response) {
        logger.warn(TAG, `正文变量预热失败: 书籍详情请求无响应, bookUrl=${normalizedBookUrl}`);
        return;
      }

      const parsedBook = await this.parseBookInfoAsync(response, request.url, normalizedBookUrl);
      if (!parsedBook) {
        logger.warn(TAG, `正文变量预热失败: 详情解析为空, bookUrl=${normalizedBookUrl}`);
        return;
      }

      this.contentVariableWarmupReadyBookUrls.add(normalizedBookUrl);
      logger.info(TAG, `正文变量预热完成: ${parsedBook.name || normalizedBookUrl}`);
    } catch (error) {
      logger.warn(TAG, `正文变量预热异常: ${String(error)}`);
    }
  }

  private async prepareContentRuleVariables(chapter: LegadoChapter): Promise<void> {
    const chapterVariables = this.collectChapterRuleVariables(chapter);
    this.applyVariablesToUrlAnalyzer(chapterVariables, '章节上下文');

    const chapterUrl = (chapter.url || '').trim();
    if (!this.needsContentRuleVariableWarmup(chapterUrl)) {
      return;
    }

    const chapterBookUrl = (chapter.bookUrl || '').trim();
    if (chapterBookUrl.length > 0) {
      await this.warmupVariablesFromBookInfo(chapterBookUrl);
      // 书籍详情中的变量同步后，再次应用章节变量兜底，避免被覆盖
      this.applyVariablesToUrlAnalyzer(chapterVariables, '章节兜底');
    }
  }

  // ==================== 发现页功能 ====================
  getExploreKinds(): LegadoExploreKind[] {
    if (!this.source.exploreUrl) {
      return [];
    }
    
    const parser = new LegadoSourceParser();
    return parser.parseExploreKinds(this.source.exploreUrl);
  }

  async getExploreKindsAsync(): Promise<LegadoExploreKind[]> {
    if (!this.source.exploreUrl) {
      return [];
    }

    this.ensureJsLib();
    const exploreUrl = this.source.exploreUrl.trim();
    const lowerExploreUrl = exploreUrl.toLowerCase();
    if (
      lowerExploreUrl.startsWith('@js:') ||
      lowerExploreUrl.startsWith('@js：') ||
      lowerExploreUrl.startsWith('＠js:') ||
      lowerExploreUrl.startsWith('＠js：') ||
      lowerExploreUrl.startsWith('<js>')
    ) {
      const evaluated = await this.evaluateExploreKindsScript(exploreUrl);
      if (evaluated.trim().length <= 0) {
        return [];
      }
      const parser = new LegadoSourceParser();
      return parser.parseExploreKinds(evaluated);
    }

    return this.getExploreKinds();
  }

  private async evaluateExploreKindsScript(exploreUrl: string): Promise<string> {
    const jsCode = this.extractExploreKindsJsCode(exploreUrl);
    if (jsCode.trim().length <= 0) {
      return '';
    }
    const context: JsContext = {
      result: '',
      src: '',
      baseUrl: LegadoSourceParser.getBaseUrl(this.source),
      key: '',
      page: 1,
      variables: this.buildRuleAnalyzerContextVariables(),
      jsLib: this.source.jsLib || '',
      source: this.source
    };

    for (let attempt = 0; attempt <= EXPLORE_KIND_JS_RETRY_DELAYS_MS.length; attempt++) {
      try {
        const executeResult = await getLegadoJsEngine().execute(jsCode, context);
        this.persistSourceEffects(executeResult.sourceEffects);
        if (!executeResult.success) {
          const errorMessage = executeResult.error || '';
          if (errorMessage === 'WEBVIEW_NOT_READY' && attempt < EXPLORE_KIND_JS_RETRY_DELAYS_MS.length) {
            const delayMs = EXPLORE_KIND_JS_RETRY_DELAYS_MS[attempt];
            logger.warn(TAG, `发现分类JS等待WebView就绪后重试 [${this.source.bookSourceName}]: attempt=${attempt + 1}, delay=${delayMs}ms`);
            await this.sleep(delayMs);
            continue;
          }
          logger.warn(TAG, `发现分类JS执行失败 [${this.source.bookSourceName}]: ${executeResult.error || ''}`);
          return '';
        }
        return String(executeResult.result || '').trim();
      } catch (error) {
        if (attempt < EXPLORE_KIND_JS_RETRY_DELAYS_MS.length) {
          const delayMs = EXPLORE_KIND_JS_RETRY_DELAYS_MS[attempt];
          logger.warn(TAG, `发现分类JS执行异常，等待后重试 [${this.source.bookSourceName}]: attempt=${attempt + 1}, delay=${delayMs}ms, ${String(error)}`);
          await this.sleep(delayMs);
          continue;
        }
        logger.warn(TAG, `发现分类JS执行异常 [${this.source.bookSourceName}]: ${String(error)}`);
        return '';
      }
    }
    return '';
  }

  private extractExploreKindsJsCode(exploreUrl: string): string {
    const trimmed = exploreUrl.trim();
    const lower = trimmed.toLowerCase();
    if (lower.startsWith('@js:') || lower.startsWith('@js：')) {
      return trimmed.substring(4);
    }
    if (lower.startsWith('＠js:') || lower.startsWith('＠js：')) {
      return trimmed.substring(4);
    }
    if (lower.startsWith('<js>')) {
      const endIndex = lower.lastIndexOf('</js>');
      if (endIndex > 4) {
        return trimmed.substring(4, endIndex);
      }
      return trimmed.substring(4);
    }
    return trimmed;
  }

  /**
   * 是否有发现功能
   */
  hasExplore(): boolean {
    return !!this.source.exploreUrl && this.source.enabledExplore !== false;
  }

  /**
   * 获取发现页书籍列表
   */
  async explore(exploreUrl: string, page: number = 1): Promise<LegadoSearchBook[]> {
    this.ensureJsLib();
    if (!this.source.ruleExplore) {
      logger.warn(TAG, '书源没有配置发现规则');
      return [];
    }

    try {
      const request = await this.analyzeRequestUrl(exploreUrl, '', page);
      const response = await this.executeRequest(request);

      if (!response) {
        return [];
      }

      return await this.parseExploreResultAsync(response, request.url);
    } catch (error) {
      logger.error(TAG, `发现页获取失败: ${String(error)}`);
      return [];
    }
  }
  private async parseExploreResultAsync(html: string, baseUrl: string): Promise<LegadoSearchBook[]> {
    const results: LegadoSearchBook[] = [];
    const rule = this.source.ruleExplore;
    
    if (!rule || !rule.bookList) {
      return results;
    }

    const analyzer = this.createRuleAnalyzer();
    analyzer.setContent(html, baseUrl);

    const bookElements = await analyzer.getElementsAsync(rule.bookList);
    this.persistRuleAnalyzerSourceEffects(analyzer);
    
    for (let i = 0; i < bookElements.length; i++) {
      const itemAnalyzer = this.createRuleAnalyzer();
      itemAnalyzer.setContent(bookElements[i], baseUrl);

      const name = await this.readRuleString(itemAnalyzer, rule.name);
      if (!name) {
        continue;
      }

      const searchBook: LegadoSearchBook = {
        origin: this.source.bookSourceUrl,
        originName: this.source.bookSourceName,
        bookUrl: this.normalizeParsedUrl(await this.readRuleString(itemAnalyzer, rule.bookUrl), baseUrl, baseUrl),
        name: name,
        author: await this.readRuleString(itemAnalyzer, rule.author) || '',
        kind: await this.readRuleString(itemAnalyzer, rule.kind),
        intro: await this.readRuleString(itemAnalyzer, rule.intro),
        coverUrl: this.normalizeParsedUrl(await this.readRuleString(itemAnalyzer, rule.coverUrl), baseUrl),
        latestChapterTitle: await this.readRuleString(itemAnalyzer, rule.lastChapter),
        wordCount: await this.readRuleString(itemAnalyzer, rule.wordCount),
        type: this.source.bookSourceType
      };

      this.syncRuleVariablesToUrlAnalyzer(itemAnalyzer.getVariablesSnapshot());
      this.persistRuleAnalyzerSourceEffects(itemAnalyzer);
      results.push(searchBook);
    }

    logger.info(TAG, `发现页结果: ${results.length} 本书`);
    return results;
  }

  /**
   * 执行HTTP请求
   */
  private async executeRequest(request: ParsedUrlRequest): Promise<string | null> {
    try {
      request.url = this.normalizeRequestUrl(request.url);
      if (request.requestUrl && request.requestUrl.length > 0) {
        request.requestUrl = this.normalizeRequestUrl(request.requestUrl);
      }

      if (this.hasUnresolvedRuleTokens(request.url)) {
        logger.error(TAG, `URL包含未解析的规则: ${request.url.substring(0, 100)}...`);
        logger.warn(TAG, '请检查JS引擎是否正常工作');
        return null;
      }

      if (request.url.startsWith('data:')) {
        const dataPayload = await this.parseDataUrl(request.url);
        if (this.isLikelyRedirectUrl(dataPayload)) {
          const redirectRequest = await this.analyzeRequestUrl(dataPayload);
          if (!redirectRequest.url.startsWith('data:')) {
            logger.debug(TAG, `data:URL解析为跳转请求: ${redirectRequest.url}`);
            return await this.executeRequest(redirectRequest);
          }
        }
        return dataPayload;
      }

      if (this.isLikelyJsFragmentUrl(request.url)) {
        logger.error(TAG, `URL疑似包含未执行的JS片段: ${request.url.substring(0, 100)}...`);
        return null;
      }

      if (request.url.startsWith('ERROR:')) {
        logger.error(TAG, `JS执行返回错误: ${request.url}`);
        logger.warn(TAG, '请检查JS规则或JS引擎状态');
        return null;
      }

      if (!request.url.startsWith('http://') && !request.url.startsWith('https://')) {
        logger.error(TAG, `无效的URL: ${request.url}`);
        return null;
      }

      const httpUrl = request.requestUrl && request.requestUrl.length > 0 ? request.requestUrl : request.url;
      logger.debug(TAG, `请求: ${request.method} ${request.url}`);
      if (request.body) {
        logger.debug(TAG, `请求Body: ${request.body}`);
      }

      const httpRequest = http.createHttp();
      const options: http.HttpRequestOptions = {
        method: request.method === RequestMethod.POST ? http.RequestMethod.POST : http.RequestMethod.GET,
        header: await this.buildHeaders(request.headers),
        connectTimeout: REQUEST_TIMEOUT_MS,
        readTimeout: REQUEST_TIMEOUT_MS,
        expectDataType: http.HttpDataType.ARRAY_BUFFER
      };

      const proxyManager = ProxyManager.getInstance();
      if (proxyManager.isEnabled()) {
        await proxyManager.applyToHttpOptions(options, httpUrl);
        logger.debug(TAG, `使用代理请求: ${request.url}`);
      }

      if (request.method === RequestMethod.POST) {
        const header = options.header as Record<string, string>;
        if (!this.hasHeader(header, 'Content-Type')) {
          if (request.body && (request.body.trim().startsWith('{') || request.body.trim().startsWith('['))) {
            header['Content-Type'] = 'application/json; charset=utf-8';
          } else {
            header['Content-Type'] = 'application/x-www-form-urlencoded; charset=utf-8';
          }
        }
        if (request.body) {
          options.extraData = request.encodedBody !== undefined ? request.encodedBody : request.body;
        }
        logger.debug(TAG, `POST Content-Type: ${this.getHeaderValue(header, 'Content-Type')}`);
      }

      const response = await httpRequest.request(httpUrl, options);
      httpRequest.destroy();

      if (response.responseCode >= 200 && response.responseCode < 300) {
        return this.decodeHttpResponseBody(response, request.charset);
      }

      const responseBody = typeof response.result === 'string' ? response.result : String(response.result);
      const truncatedBody = responseBody.length > 200 ? responseBody.substring(0, 200) + '...' : responseBody;
      logger.warn(TAG, `请求失败: HTTP ${response.responseCode}`);
      logger.debug(TAG, `失败URL: ${request.url}`);
      logger.debug(TAG, `响应内容: ${truncatedBody}`);
      return null;
    } catch (error) {
      const errorMsg = this.formatError(error);
      logger.error(TAG, `HTTP请求异常: ${errorMsg}`);
      logger.debug(TAG, `失败URL: ${request.url}`);
      return null;
    }
  }

  private normalizeNextContentUrls(
    contentResult: ContentParseResult,
    currentUrl: string,
    visitedUrls: Set<string>,
    pendingUrls: string[]
  ): string[] {
    const result: string[] = [];
    const candidates = contentResult.nextUrls && contentResult.nextUrls.length > 0
      ? contentResult.nextUrls
      : (contentResult.nextUrl ? [contentResult.nextUrl] : []);
    for (let i = 0; i < candidates.length; i++) {
      const candidate = (candidates[i] || '').trim();
      if (candidate.length <= 0 || candidate === currentUrl) {
        continue;
      }
      if (visitedUrls.has(candidate) || pendingUrls.includes(candidate) || result.includes(candidate)) {
        continue;
      }
      result.push(candidate);
    }
    return result;
  }

  private decodeHttpResponseBody(response: http.HttpResponse, explicitCharset?: string): string {
    const bytes = this.getResponseBytes(response.result);
    if (bytes === null) {
      if (typeof response.result === 'string') {
        return this.stripTextBom(response.result);
      }
      return this.stripTextBom(String(response.result));
    }

    const sourceCharset = this.normalizeCharsetName(explicitCharset);
    if (sourceCharset.length > 0) {
      return this.stripTextBom(this.decodeBytesWithCharset(bytes, sourceCharset));
    }

    const contentType = this.getResponseHeaderValue(response.header, 'content-type');
    const headerCharset = this.extractCharsetFromText(contentType);
    if (headerCharset.length > 0) {
      return this.stripTextBom(this.decodeBytesWithCharset(bytes, headerCharset));
    }

    const utf8Text = this.stripTextBom(this.decodeBytesWithCharset(bytes, 'utf-8'));
    const metaCharset = this.extractHtmlMetaCharset(utf8Text);
    if (metaCharset.length > 0 && metaCharset.toLowerCase() !== 'utf-8') {
      return this.stripTextBom(this.decodeBytesWithCharset(bytes, metaCharset));
    }
    return utf8Text;
  }

  private getResponseBytes(result: string | Object | ArrayBuffer): Uint8Array | null {
    if (result instanceof ArrayBuffer) {
      return new Uint8Array(result);
    }
    return null;
  }

  private decodeBytesWithCharset(bytes: Uint8Array, charset: string): string {
    const normalizedCharset = this.normalizeCharsetName(charset);
    const decoderCharset = normalizedCharset.length > 0 ? normalizedCharset : 'utf-8';
    try {
      const decoder = util.TextDecoder.create(decoderCharset, { ignoreBOM: true });
      return decoder.decodeToString(bytes);
    } catch (error) {
      if (decoderCharset.toLowerCase() !== 'utf-8') {
        logger.warn(TAG, `响应按${decoderCharset}解码失败，回退UTF-8: ${this.formatError(error as Object)}`);
        const fallbackDecoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });
        return fallbackDecoder.decodeToString(bytes);
      }
      logger.warn(TAG, `响应按UTF-8解码失败: ${this.formatError(error as Object)}`);
      return '';
    }
  }

  private getResponseHeaderValue(headerObject: Object, name: string): string {
    const targetName = name.toLowerCase();
    const headers = headerObject as Record<string, Object>;
    const keys = Object.keys(headers);
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i];
      if (key.toLowerCase() === targetName) {
        return this.headerValueToString(headers[key]);
      }
    }
    return '';
  }

  private headerValueToString(value: Object): string {
    if (Array.isArray(value)) {
      const values = value as Object[];
      const parts: string[] = [];
      for (let i = 0; i < values.length; i++) {
        parts.push(String(values[i]));
      }
      return parts.join('; ');
    }
    return String(value);
  }

  private extractCharsetFromText(text: string): string {
    if (text.length === 0) {
      return '';
    }
    const charsetMatch = text.match(/charset\s*=\s*["']?\s*([^"';,\s>]+)/i);
    if (!charsetMatch || charsetMatch.length < 2) {
      return '';
    }
    return this.normalizeCharsetName(charsetMatch[1]);
  }

  private extractHtmlMetaCharset(html: string): string {
    if (html.length === 0) {
      return '';
    }
    const preview = html.length > 8192 ? html.substring(0, 8192) : html;
    const directMetaMatch = preview.match(/<meta[^>]+charset\s*=\s*["']?\s*([^"'\s/>;]+)/i);
    if (directMetaMatch && directMetaMatch.length >= 2) {
      return this.normalizeCharsetName(directMetaMatch[1]);
    }
    const contentMetaMatch = preview.match(/<meta[^>]+content\s*=\s*["'][^"']*charset\s*=\s*([^"';,\s>]+)/i);
    if (contentMetaMatch && contentMetaMatch.length >= 2) {
      return this.normalizeCharsetName(contentMetaMatch[1]);
    }
    return '';
  }

  private normalizeCharsetName(charset?: string): string {
    if (!charset) {
      return '';
    }
    let normalized = charset.trim();
    while (normalized.startsWith('"') || normalized.startsWith("'") || normalized.startsWith('`')) {
      normalized = normalized.substring(1);
    }
    while (normalized.endsWith('"') || normalized.endsWith("'") || normalized.endsWith('`') ||
      normalized.endsWith(';') || normalized.endsWith(',')) {
      normalized = normalized.substring(0, normalized.length - 1).trim();
    }
    const lower = normalized.toLowerCase();
    if (lower === 'utf8') {
      return 'utf-8';
    }
    if (lower === 'utf16') {
      return 'utf-16';
    }
    if (lower === 'unicode') {
      return 'utf-16';
    }
    if (lower === 'escape') {
      return '';
    }
    return normalized;
  }

  private stripTextBom(text: string): string {
    if (text.length > 0 && text.charCodeAt(0) === 0xFEFF) {
      return text.substring(1);
    }
    return text;
  }

  private async parseDataUrl(url: string): Promise<string> {
    try {
      logger.debug(TAG, `解析data:URL: ${url.substring(0, Math.min(200, url.length))}...`);

      const firstCommaIndex = url.indexOf(',');
      if (firstCommaIndex > 0) {
        const content = url.substring(firstCommaIndex + 1);
        logger.debug(TAG, `data:URL内容: ${content.substring(0, Math.min(200, content.length))}...`);

        if (content.startsWith('{')) {
          let braceCount = 0;
          let endIndex = 0;
          for (let i = 0; i < content.length; i++) {
            if (content[i] === '{') {
              braceCount++;
            } else if (content[i] === '}') {
              braceCount--;
            }
            if (braceCount === 0) {
              endIndex = i + 1;
              break;
            }
          }
          if (endIndex > 0) {
            const jsonContent = content.substring(0, endIndex);
            logger.debug(TAG, `提取的JSON: ${jsonContent.substring(0, Math.min(200, jsonContent.length))}...`);
            return jsonContent;
          }
        }

        const decodedContent = await this.tryDecodeBase64DataUrlPayload(content);
        if (decodedContent !== null) {
          logger.debug(TAG, `data:URL Base64解码成功: ${decodedContent.substring(0, Math.min(200, decodedContent.length))}...`);
          return decodedContent;
        }

        return content;
      }

      return url;
    } catch (error) {
      logger.error(TAG, `解析data:URL失败: ${String(error)}`);
      return url;
    }
  }

  private async tryDecodeBase64DataUrlPayload(payload: string): Promise<string | null> {
    const trimmedPayload = payload.trim();
    if (!this.isLikelyBase64Payload(trimmedPayload)) {
      return null;
    }

    try {
      let normalized = trimmedPayload.replace(/-/g, '+').replace(/_/g, '/');
      const paddingLength = normalized.length % 4;
      if (paddingLength > 0) {
        normalized += '='.repeat(4 - paddingLength);
      }

      const base64Helper: util.Base64Helper = new util.Base64Helper();
      const decodedBytes: Uint8Array = await base64Helper.decode(normalized);
      const decoder = new util.TextDecoder('utf-8');
      const decodedText = decoder.decodeToString(decodedBytes).trim();
      if (!this.isUsableDecodedDataPayload(decodedText)) {
        return null;
      }
      return decodedText.length > 0 ? decodedText : null;
    } catch (error) {
      logger.debug(TAG, `data:URL Base64解码失败，按原文处理: ${String(error)}`);
      return null;
    }
  }

  private isLikelyBase64Payload(value: string): boolean {
    if (value.length < 8 || value.length > 8192) {
      return false;
    }
    const base64Pattern = /^[A-Za-z0-9+/=_-]+$/;
    return base64Pattern.test(value);
  }

  private isLikelyRedirectUrl(value: string): boolean {
    const trimmedValue = value.trim();
    if (trimmedValue.length === 0) {
      return false;
    }
    if (!this.isUsableDecodedDataPayload(trimmedValue)) {
      return false;
    }
    if (trimmedValue.startsWith('{') || trimmedValue.startsWith('[') || trimmedValue.startsWith('<')) {
      return false;
    }
    if (/[<>"'`{}|\\^]/.test(trimmedValue) || /\s/.test(trimmedValue)) {
      return false;
    }
    return trimmedValue.startsWith('http://') || trimmedValue.startsWith('https://') || trimmedValue.startsWith('/');
  }

  private isUsableDecodedDataPayload(value: string): boolean {
    if (value.length === 0 || value.includes('\uFFFD')) {
      return false;
    }

    for (let i = 0; i < value.length; i++) {
      const code = value.charCodeAt(i);
      const isControl = code < 0x20 && code !== 0x09 && code !== 0x0A && code !== 0x0D;
      if (isControl || code === 0x7F) {
        return false;
      }
    }

    return true;
  }
  private async executeRequestWithError(request: ParsedUrlRequest): Promise<HttpRequestResult> {
    try {
      request.url = this.normalizeRequestUrl(request.url);
      if (request.requestUrl && request.requestUrl.length > 0) {
        request.requestUrl = this.normalizeRequestUrl(request.requestUrl);
      }

      if (this.hasUnresolvedRuleTokens(request.url)) {
        const errorType = this.analyzeJsError(request.url);
        const result: HttpRequestResult = {
          response: null,
          errorType: errorType,
          errorMessage: 'URL包含未解析的规则'
        };
        return result;
      }

      if (request.url.startsWith('data:')) {
        const dataPayload = await this.parseDataUrl(request.url);
        if (this.isLikelyRedirectUrl(dataPayload)) {
          const redirectRequest = await this.analyzeRequestUrl(dataPayload);
          if (!redirectRequest.url.startsWith('data:')) {
            logger.debug(TAG, `data:URL解析为跳转请求: ${redirectRequest.url}`);
            return await this.executeRequestWithError(redirectRequest);
          }
        }
        return { response: dataPayload } as HttpRequestResult;
      }

      if (this.isLikelyJsFragmentUrl(request.url)) {
        return {
          response: null,
          errorType: SearchErrorType.URL_PARSE_ERROR,
          errorMessage: 'URL疑似包含未执行的JS片段'
        } as HttpRequestResult;
      }

      if (request.url.startsWith('ERROR:')) {
        const jsErrorType = this.analyzeJsError(request.url);
        return {
          response: null,
          errorType: jsErrorType,
          errorMessage: request.url
        } as HttpRequestResult;
      }

      if (!request.url.startsWith('http://') && !request.url.startsWith('https://')) {
        const result: HttpRequestResult = {
          response: null,
          errorType: SearchErrorType.URL_PARSE_ERROR,
          errorMessage: '无效的URL'
        };
        return result;
      }

      const httpUrl = request.requestUrl && request.requestUrl.length > 0 ? request.requestUrl : request.url;
      logger.debug(TAG, `请求: ${request.method} ${request.url}`);
      if (request.body) {
        logger.debug(TAG, `请求Body: ${request.body}`);
      }

      const httpRequest = http.createHttp();
      const options: http.HttpRequestOptions = {
        method: request.method === RequestMethod.POST ? http.RequestMethod.POST : http.RequestMethod.GET,
        header: await this.buildHeaders(request.headers),
        connectTimeout: REQUEST_TIMEOUT_MS,
        readTimeout: REQUEST_TIMEOUT_MS,
        expectDataType: http.HttpDataType.ARRAY_BUFFER
      };

      const proxyMgr = ProxyManager.getInstance();
      if (proxyMgr.isEnabled()) {
        await proxyMgr.applyToHttpOptions(options, httpUrl);
      }

      if (request.method === RequestMethod.POST) {
        const header = options.header as Record<string, string>;
        if (!this.hasHeader(header, 'Content-Type')) {
          if (request.body && (request.body.trim().startsWith('{') || request.body.trim().startsWith('['))) {
            header['Content-Type'] = 'application/json; charset=utf-8';
          } else {
            header['Content-Type'] = 'application/x-www-form-urlencoded; charset=utf-8';
          }
        }
        if (request.body) {
          options.extraData = request.encodedBody !== undefined ? request.encodedBody : request.body;
        }
        logger.debug(TAG, `POST Content-Type: ${this.getHeaderValue(header, 'Content-Type')}`);
      }

      const response = await httpRequest.request(httpUrl, options);
      httpRequest.destroy();

      if (response.responseCode >= 200 && response.responseCode < 300) {
        const responseStr: string = this.decodeHttpResponseBody(response, request.charset);
        const successResult: HttpRequestResult = {
          response: responseStr,
          errorType: SearchErrorType.NONE,
          errorMessage: ''
        };
        return successResult;
      }

      const responseCode = response.responseCode;
      let errorType: SearchErrorType;
      if (responseCode === 404) {
        errorType = SearchErrorType.HTTP_404;
      } else if (responseCode === 403) {
        errorType = SearchErrorType.HTTP_403;
      } else if (responseCode >= 500) {
        errorType = SearchErrorType.HTTP_5XX;
      } else {
        errorType = SearchErrorType.HTTP_OTHER;
      }

      logger.warn(TAG, `请求失败: HTTP ${responseCode}`);
      logger.debug(TAG, `失败URL: ${request.url}`);
      const httpErrorResult: HttpRequestResult = {
        response: null,
        errorType: errorType,
        errorMessage: `HTTP ${responseCode}`
      };
      return httpErrorResult;
    } catch (error) {
      const errorMsg = this.formatError(error);
      logger.error(TAG, `HTTP请求异常: ${errorMsg}`);
      logger.debug(TAG, `失败URL: ${request.url}`);

      const errorType = this.analyzeErrorType(errorMsg);
      const exceptionResult: HttpRequestResult = {
        response: null,
        errorType: errorType,
        errorMessage: errorMsg
      };
      return exceptionResult;
    }
  }
  private formatError(error: Object | null | undefined): string {
    if (error === null || error === undefined) {
      return '未知错误';
    }
    
    // 尝试获取错误对象的各种属性
    const err = error as Record<string, Object>;
    
    // 常见的错误属性
    if (err['message']) {
      return String(err['message']);
    }
    if (err['code'] !== undefined) {
      const code = err['code'];
      const msg = err['message'] || err['msg'] || '';
      return `错误码: ${code}${msg ? ', ' + msg : ''}`;
    }
    if (err['errMsg']) {
      return String(err['errMsg']);
    }
    if (err['errorMessage']) {
      return String(err['errorMessage']);
    }
    
    // 尝试JSON序列化
    try {
      const jsonStr = JSON.stringify(error);
      if (jsonStr !== '{}') {
        return jsonStr;
      }
    } catch {
      // 忽略序列化错误
    }
    
    return String(error);
  }

  /**
   * 构建请求头
   */
  private async buildHeaders(customHeaders: Record<string, string>): Promise<Record<string, string>> {
    const headers: Record<string, string> = {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 11) AppleWebKit/537.36 Chrome/91.0.4472.120 Mobile Safari/537.36'
    };

    // 合并书源配置的请求头
    if (this.source.header) {
      const sourceHeaders = await this.resolveSourceHeaders(this.source.header);
      Object.keys(sourceHeaders).forEach(key => {
        headers[key] = sourceHeaders[key];
      });
    }

    // 添加登录Cookie
    const loginManager = getNovelLoginManager();
    const sourceUrl = this.source.bookSourceUrl;
    const cookieString = loginManager.getCookieString(sourceUrl);
    logger.debug(TAG, `查找Cookie: sourceUrl=${sourceUrl}, found=${cookieString ? 'yes' : 'no'}`);
    if (cookieString) {
      headers['Cookie'] = cookieString;
      logger.debug(TAG, `添加Cookie到请求: ${cookieString.substring(0, 50)}...`);
    }

    // 合并自定义请求头
    Object.keys(customHeaders).forEach(key => {
      headers[key] = customHeaders[key];
    });

    return headers;
  }

  private async resolveSourceHeaders(headerText: string): Promise<Record<string, string>> {
    const jsCode = this.extractHeaderJsCode(headerText);
    if (jsCode.length > 0) {
      const jsHeaders = await this.evaluateHeaderScript(jsCode);
      if (Object.keys(jsHeaders).length > 0) {
        return jsHeaders;
      }
    }

    const parsed = this.parseHeaderText(headerText);
    if (parsed) {
      return parsed;
    }
    return {};
  }

  private extractHeaderJsCode(headerText: string): string {
    const trimmed = headerText.trim();
    if (trimmed.length <= 0) {
      return '';
    }

    const lower = trimmed.toLowerCase();
    if (lower.startsWith('<js>')) {
      const endIndex = lower.lastIndexOf('</js>');
      if (endIndex > 4) {
        return trimmed.substring(4, endIndex).trim();
      }
      return trimmed.substring(4).trim();
    }

    const jsPrefixPattern: RegExp = /^(?:@|＠)\s*js(?:\:|：)\s*/i;
    if (jsPrefixPattern.test(trimmed)) {
      return trimmed.replace(jsPrefixPattern, '').trim();
    }
    return '';
  }

  private async evaluateHeaderScript(jsCode: string): Promise<Record<string, string>> {
    try {
      const context: JsContext = {
        result: '',
        src: '',
        baseUrl: LegadoSourceParser.getBaseUrl(this.source),
        key: '',
        page: 1,
        variables: this.buildRuleAnalyzerContextVariables(),
        jsLib: this.source.jsLib || '',
        source: this.source
      };
      const executeResult = await getLegadoJsEngine().execute(jsCode, context);
      this.persistSourceEffects(executeResult.sourceEffects);
      if (!executeResult.success) {
        logger.warn(TAG, `书源Header JS执行失败 [${this.source.bookSourceName}]: ${executeResult.error || ''}`);
        return {};
      }
      const parsed = this.parseHeaderText(String(executeResult.result || ''));
      return parsed || {};
    } catch (error) {
      logger.warn(TAG, `书源Header JS执行异常 [${this.source.bookSourceName}]: ${String(error)}`);
      return {};
    }
  }

  private parseHeaderText(headerText: string): Record<string, string> | null {
    const trimmed = headerText.trim();
    if (trimmed.length <= 0) {
      return null;
    }
    if (this.extractHeaderJsCode(trimmed).length > 0) {
      return null;
    }

    const strictParsed = this.tryParseHeaderJson(trimmed);
    if (strictParsed) {
      return strictParsed;
    }

    const fixedHeader = trimmed
      .replace(/([{,]\s*)([a-zA-Z_$][a-zA-Z0-9_$-]*)\s*:/g, '$1"$2":')
      .replace(/([{,]\s*)'([^']+)'\s*:/g, '$1"$2":')
      .replace(/:\s*'([^'\\]*(?:\\.[^'\\]*)*)'/g, (match: string, value: string): string => {
        const escapedValue = value.replace(/"/g, '\\"');
        return `:"${escapedValue}"`;
      });
    const fixedParsed = this.tryParseHeaderJson(fixedHeader);
    if (fixedParsed) {
      return fixedParsed;
    }

    return this.parseHeaderPairs(trimmed);
  }

  private tryParseHeaderJson(headerJson: string): Record<string, string> | null {
    try {
      const parsed = JSON.parse(headerJson) as Object;
      if (parsed === null || parsed === undefined || typeof parsed !== 'object' || Array.isArray(parsed)) {
        return null;
      }
      return this.normalizeHeaderRecord(parsed as Record<string, Object>);
    } catch (_error) {
      return null;
    }
  }

  private normalizeHeaderRecord(record: Record<string, Object>): Record<string, string> | null {
    const headers: Record<string, string> = {};
    const keys = Object.keys(record);
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i].trim();
      const value = record[key];
      if (key.length > 0 && value !== undefined && value !== null) {
        headers[key] = String(value);
      }
    }
    return Object.keys(headers).length > 0 ? headers : null;
  }

  private parseHeaderPairs(headerText: string): Record<string, string> | null {
    let body = headerText.trim();
    if (body.startsWith('{') && body.endsWith('}')) {
      body = body.substring(1, body.length - 1);
    }
    const headers: Record<string, string> = {};
    const pairs = body.split(',');
    for (let i = 0; i < pairs.length; i++) {
      const pair = pairs[i].trim();
      const splitIndex = pair.indexOf(':');
      if (splitIndex <= 0) {
        continue;
      }
      const key = this.trimHeaderToken(pair.substring(0, splitIndex));
      const value = this.trimHeaderToken(pair.substring(splitIndex + 1));
      if (key.length > 0 && value.length > 0) {
        headers[key] = value;
      }
    }
    return Object.keys(headers).length > 0 ? headers : null;
  }

  private trimHeaderToken(value: string): string {
    let result = value.trim();
    if (result.length >= 2) {
      const first = result.charAt(0);
      const last = result.charAt(result.length - 1);
      if ((first === '"' && last === '"') || (first === '\'' && last === '\'')) {
        result = result.substring(1, result.length - 1).trim();
      }
    }
    return result;
  }

  private hasHeader(headers: Record<string, string>, name: string): boolean {
    return this.getHeaderValue(headers, name).length > 0;
  }

  private getHeaderValue(headers: Record<string, string>, name: string): string {
    const target = name.toLowerCase();
    const keys = Object.keys(headers);
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i];
      if (key.toLowerCase() === target) {
        return String(headers[key] || '');
      }
    }
    return '';
  }

  /**
   * 解析搜索结果（异步版本，支持JS规则）
   */
  private async parseSearchResultAsync(
    html: string,
    baseUrl: string,
    parseOptions?: SearchParseOptions
  ): Promise<LegadoSearchBook[]> {
    const results: LegadoSearchBook[] = [];
    const rule = this.source.ruleSearch;
    
    if (!rule || !rule.bookList) {
      this.searchParseTrace((): string => `[书源:${this.source.bookSourceName}] 搜索规则为空或缺少bookList`);
      return results;
    }

    // 性能优化：减少日志输出，仅在小型响应时输出调试信息
    if (html.length < 50000) {
      this.searchParseTrace((): string => `[书源:${this.source.bookSourceName}] 响应长度=${html.length}, bookList规则=${rule.bookList}`);
      this.searchParseTrace((): string => {
        const htmlSnippet = html.length > 500 ? html.substring(0, 500) + '...' : html;
        return `[书源:${this.source.bookSourceName}] 响应片段: ${htmlSnippet}`;
      });
    }

    const forceFullExecution = parseOptions?.forceFullExecution === true;
    const maxResults = !forceFullExecution && parseOptions?.maxResults && parseOptions.maxResults > 0
      ? Math.floor(parseOptions.maxResults)
      : Number.MAX_SAFE_INTEGER;
    const maxElementScan = !forceFullExecution && parseOptions?.maxElementScan && parseOptions.maxElementScan > 0
      ? Math.floor(parseOptions.maxElementScan)
      : Number.MAX_SAFE_INTEGER;
    const disableItemDomBridge = parseOptions?.disableItemDomBridge === true;
    const configuredYieldSlice = parseOptions?.yieldSliceMs && parseOptions.yieldSliceMs > 0
      ? Math.floor(parseOptions.yieldSliceMs)
      : 8;
    const yieldSliceMs = Math.max(4, Math.min(20, configuredYieldSlice));
    let rootElementLimit = 0;
    if (!forceFullExecution && ((parseOptions?.maxResults && parseOptions.maxResults > 0) ||
      (parseOptions?.maxElementScan && parseOptions.maxElementScan > 0))) {
      const limitByResults = maxResults === Number.MAX_SAFE_INTEGER ? Number.MAX_SAFE_INTEGER : maxResults * 2;
      const limitByScan = maxElementScan === Number.MAX_SAFE_INTEGER ? Number.MAX_SAFE_INTEGER : maxElementScan * 2;
      rootElementLimit = Math.max(20, Math.min(limitByResults, limitByScan, 240));
    }

    const analyzer = this.createRuleAnalyzer();
    if (rootElementLimit > 0) {
      analyzer.setMaxElementsLimit(rootElementLimit);
    }
    analyzer.setContent(html, baseUrl, disableItemDomBridge);

    // 使用异步方法获取元素，支持JS规则
    const bookElements = await analyzer.getElementsAsync(rule.bookList);
    this.persistRuleAnalyzerSourceEffects(analyzer);
    this.searchParseTrace((): string => `[书源:${this.source.bookSourceName}] bookList解析结果: ${bookElements.length} 个元素`);

    const scanLimit = Math.min(bookElements.length, maxElementScan);
    const YIELD_SLICE_MS = yieldSliceMs;
    let lastYieldTime = Date.now();
    const maybeYield = async (): Promise<void> => {
      const now = Date.now();
      if (now - lastYieldTime >= YIELD_SLICE_MS) {
        await this.yieldToEventLoop();
        lastYieldTime = Date.now();
      }
    };
    const nameUseAsync = this.shouldReadRuleAsync(rule.name);
    const bookUrlUseAsync = this.shouldReadRuleAsync(rule.bookUrl);
    const authorUseAsync = this.shouldReadRuleAsync(rule.author);
    const kindUseAsync = this.shouldReadRuleAsync(rule.kind);
    const introUseAsync = this.shouldReadRuleAsync(rule.intro);
    const coverUrlUseAsync = this.shouldReadRuleAsync(rule.coverUrl);
    const latestChapterUseAsync = this.shouldReadRuleAsync(rule.lastChapter);
    const wordCountUseAsync = this.shouldReadRuleAsync(rule.wordCount);
    const shouldDisableItemDomBridge = disableItemDomBridge || scanLimit > 40;
    const itemAnalyzer = this.createRuleAnalyzer();
    if (shouldDisableItemDomBridge) {
      // item级规则只用于提取单条字段，不需要放开到全局上限，限制可显著降低异常规则卡顿风险
      itemAnalyzer.setMaxElementsLimit(768);
    }
    const syncRuleCache: Map<string, string> = new Map();
    const asyncRuleCache: Map<string, Promise<string>> = new Map();

    const readRuleValue = (
      ruleText: string | undefined,
      useAsync: boolean
    ): string | Promise<string> => {
      if (!ruleText) {
        return '';
      }
      if (useAsync) {
        const cachedAsync = asyncRuleCache.get(ruleText);
        if (cachedAsync !== undefined) {
          return cachedAsync;
        }
        const asyncValue = itemAnalyzer.getStringAsync(ruleText);
        asyncRuleCache.set(ruleText, asyncValue);
        return asyncValue;
      }

      const cachedSync = syncRuleCache.get(ruleText);
      if (cachedSync !== undefined) {
        return cachedSync; 
      }
      const syncValue = itemAnalyzer.getString(ruleText);
      syncRuleCache.set(ruleText, syncValue);
      return syncValue;
    };
    for (let i = 0; i < scanLimit && results.length < maxResults; i++) {
      const loopStart = Date.now();
      if (loopStart - lastYieldTime >= YIELD_SLICE_MS) {
        await this.yieldToEventLoop();
        lastYieldTime = Date.now();
      }
      syncRuleCache.clear();
      asyncRuleCache.clear();
      itemAnalyzer.setContent(bookElements[i], baseUrl, shouldDisableItemDomBridge);

      const nameRuleValue = readRuleValue(rule.name, nameUseAsync);
      const name = typeof nameRuleValue === 'string' ? nameRuleValue : await nameRuleValue;
      await maybeYield();
      // 性能优化：仅在第一个元素时输出调试信息
      if (i === 0 && html.length < 50000) {
        this.searchParseTrace((): string => {
          const elementSnippet = bookElements[i].length > 200 ? bookElements[i].substring(0, 200) + '...' : bookElements[i];
          return `[书源:${this.source.bookSourceName}] 元素[0]片段: ${elementSnippet}`;
        });
        this.searchParseTrace((): string => `[书源:${this.source.bookSourceName}] 元素[0] name规则=${rule.name}, 解析结果="${name}"`);
      }
      if (!name) {
        continue;
      }

      // 解析bookUrl（使用异步方法支持JS规则）
      const bookUrlRuleValue = readRuleValue(rule.bookUrl, bookUrlUseAsync);
      const bookUrlRaw = typeof bookUrlRuleValue === 'string' ? bookUrlRuleValue : await bookUrlRuleValue;
      const bookUrl = this.normalizeParsedUrl(bookUrlRaw, baseUrl, baseUrl);
      await maybeYield();

      const authorRuleValue = readRuleValue(rule.author, authorUseAsync);
      const author = typeof authorRuleValue === 'string' ? authorRuleValue : await authorRuleValue;
      await maybeYield();
      const kindRuleValue = readRuleValue(rule.kind, kindUseAsync);
      const kind = typeof kindRuleValue === 'string' ? kindRuleValue : await kindRuleValue;
      await maybeYield();
      const introRuleValue = readRuleValue(rule.intro, introUseAsync);
      const intro = typeof introRuleValue === 'string' ? introRuleValue : await introRuleValue;
      await maybeYield();
      const coverRuleValue = readRuleValue(rule.coverUrl, coverUrlUseAsync);
      const coverUrlRaw = typeof coverRuleValue === 'string' ? coverRuleValue : await coverRuleValue;
      const coverUrl = this.normalizeParsedUrl(coverUrlRaw, baseUrl);
      await maybeYield();
      const chapterRuleValue = readRuleValue(rule.lastChapter, latestChapterUseAsync);
      const latestChapterTitle = typeof chapterRuleValue === 'string' ? chapterRuleValue : await chapterRuleValue;
      await maybeYield();
      const wordCountRuleValue = readRuleValue(rule.wordCount, wordCountUseAsync);
      const wordCount = typeof wordCountRuleValue === 'string' ? wordCountRuleValue : await wordCountRuleValue;
      await maybeYield();
      this.persistRuleAnalyzerSourceEffects(itemAnalyzer);
      
      // 始终输出第一个元素的bookUrl解析信息（用于调试）
      if (i === 0) {
        this.searchParseTrace((): string => `搜索结果解析: bookUrl规则=${rule.bookUrl}, 解析结果=${bookUrlRaw}, 最终URL=${bookUrl}`);
        this.searchParseTrace((): string => `元素内容: ${bookElements[i].substring(0, 300)}`);
      }

      const searchBook: LegadoSearchBook = {
        origin: this.source.bookSourceUrl,
        originName: this.source.bookSourceName,
        bookUrl: bookUrl,
        name: name,
        author: author || '',
        kind: kind,
        intro: intro,
        coverUrl: coverUrl,
        latestChapterTitle: latestChapterTitle,
        wordCount: wordCount,
        type: this.source.bookSourceType
      };

      results.push(searchBook);

      // 单条解析后再次判断时间片，降低重规则场景下的主线程阻塞概率
      const loopEnd = Date.now();
      if (loopEnd - lastYieldTime >= YIELD_SLICE_MS) {
        await this.yieldToEventLoop();
        lastYieldTime = Date.now();
      }
    }

    if (scanLimit < bookElements.length) {
      this.searchParseTrace((): string => `[书源:${this.source.bookSourceName}] 搜索元素扫描已截断: ${scanLimit}/${bookElements.length}`);
    }

    logger.info(TAG, `搜索结果: ${results.length} 本书`);
    return results;
  }

  /**
   * 主动让出事件循环，降低长任务阻塞风险
   */
  private async yieldToEventLoop(): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, 0));
  }

  private async sleep(milliseconds: number): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout((): void => {
        resolve();
      }, milliseconds);
    });
  }

  /**
   * 解析书籍详情
   * 注意：即使name规则为空，也会尝试解析其他字段（如tocUrl），返回部分结果
   * 调用方可以使用fallback信息补充缺失的字段
   */
  private async parseBookInfoAsync(html: string, baseUrl: string, bookUrl: string): Promise<LegadoBook | null> {
    const rule = this.source.ruleBookInfo;

    const analyzer = this.createRuleAnalyzer();

    let contentToAnalyze = html;
    if (rule && rule.init) {
      const initAnalyzer = this.createRuleAnalyzer();
      initAnalyzer.setContent(html, baseUrl);
      const initData = await this.readRuleString(initAnalyzer, rule.init);
      this.syncRuleVariablesToUrlAnalyzer(initAnalyzer.getVariablesSnapshot());
      this.persistRuleAnalyzerSourceEffects(initAnalyzer);
      if (initData) {
        contentToAnalyze = initData;
        logger.debug(TAG, `应用init规则: ${rule.init}, 提取数据长度: ${initData.length}`);
      }
    }

    analyzer.setContent(contentToAnalyze, baseUrl);

    if (contentToAnalyze.length < 50000) {
      logger.debug(TAG, `书籍详情规则 name: ${rule?.name}`);
      logger.debug(TAG, `HTML长度: ${contentToAnalyze.length}, 前500字符: ${contentToAnalyze.substring(0, 500)}`);
    }

    const name = rule?.name ? await this.readRuleString(analyzer, rule.name) : '';
    const fallbackName = this.extractFallbackBookName(contentToAnalyze);
    const resolvedName = name || fallbackName;
    if (contentToAnalyze.length < 50000) {
      logger.debug(TAG, `解析书名结果: "${resolvedName}", 规则: ${rule?.name}`);
    }

    const tocUrl = rule?.tocUrl ? this.normalizeParsedUrl(await this.readRuleString(analyzer, rule.tocUrl), baseUrl) : '';
    if (this.isInvalidParsedTocUrl(tocUrl)) {
      logger.warn(TAG, `目录URL疑似缺少关键参数，详情解析失败: ${tocUrl}`);
      return null;
    }

    if (!resolvedName && !tocUrl && !bookUrl) {
      logger.warn(TAG, '无法解析书名和目录URL，详情页解析失败');
      logger.warn(TAG, `详情页规则: name=${rule?.name}, tocUrl=${rule?.tocUrl}`);
      logger.warn(TAG, `响应内容前500字符: ${contentToAnalyze.substring(0, 500)}`);
      return null;
    }

    this.syncRuleVariablesToUrlAnalyzer(analyzer.getVariablesSnapshot());
    this.persistRuleAnalyzerSourceEffects(analyzer);

    if (contentToAnalyze.length < 50000) {
      logger.debug(TAG, `解析书籍详情: name=${resolvedName}, bookUrl=${bookUrl}, tocUrl=${tocUrl}`);
    }

    const book: LegadoBook = {
      id: this.generateId(),
      origin: this.source.bookSourceUrl,
      originName: this.source.bookSourceName,
      bookUrl: bookUrl,
      name: resolvedName,
      author: rule?.author ? await this.readRuleString(analyzer, rule.author) : '',
      kind: rule?.kind ? await this.readRuleString(analyzer, rule.kind) : undefined,
      intro: rule?.intro ? await this.readRuleString(analyzer, rule.intro) : undefined,
      coverUrl: rule?.coverUrl ? this.normalizeParsedUrl(await this.readRuleString(analyzer, rule.coverUrl), baseUrl) : undefined,
      tocUrl: tocUrl || bookUrl,
      latestChapterTitle: rule?.lastChapter ? await this.readRuleString(analyzer, rule.lastChapter) : undefined,
      wordCount: rule?.wordCount ? await this.readRuleString(analyzer, rule.wordCount) : undefined,
      type: this.source.bookSourceType
    };

    return book;
  }

  private syncRuleVariablesToUrlAnalyzer(variables: Record<string, string>): void {
    const keys = Object.keys(variables);
    if (keys.length <= 0) {
      return;
    }

    for (let i = 0; i < keys.length; i++) {
      const key = keys[i];
      const value = variables[key];
      if (!key || value === undefined || value === null) {
        continue;
      }
      if (value.length > 4096) {
        continue;
      }
      this.urlAnalyzer.setVariable(key, value);
    }
  }

  private buildChapterVariablePayload(variables: Record<string, string>): string {
    const keys = Object.keys(variables);
    if (keys.length <= 0) {
      return '';
    }
    const payload: Record<string, string> = {};
    let payloadCount = 0;
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i];
      const value = variables[key];
      if (!key || !value) {
        continue;
      }
      const trimmedKey = key.trim();
      const trimmedValue = value.trim();
      if (trimmedKey.length <= 0 || trimmedValue.length <= 0) {
        continue;
      }
      if (trimmedKey.startsWith('__') || trimmedValue.length > 512) {
        continue;
      }
      payload[trimmedKey] = trimmedValue;
      payloadCount++;
      if (payloadCount >= 24) {
        break;
      }
    }
    if (payloadCount <= 0) {
      return '';
    }
    return JSON.stringify(payload);
  }

  private extractFallbackBookName(content: string): string {
    const trimmedContent = content.trim();
    if (!trimmedContent) {
      return '';
    }

    const firstChar = trimmedContent.charAt(0);
    if (firstChar === '{' || firstChar === '[') {
      try {
        const parsed = JSON.parse(trimmedContent) as Object;
        const directName = this.readObjectStringField(parsed, ['name', 'title', 'book_name', 'bookTitle']);
        if (directName) {
          return directName;
        }

        const nestedData = this.readObjectField(parsed, 'data');
        const nestedName = this.readObjectStringField(nestedData, ['name', 'title', 'book_name', 'bookTitle']);
        if (nestedName) {
          return nestedName;
        }
      } catch {
        // 非标准 JSON 时继续尝试 HTML title。
      }
    }

    const titleMatch = trimmedContent.match(/<title[^>]*>([\s\S]*?)<\/title>/i);
    if (titleMatch && titleMatch[1]) {
      return titleMatch[1].trim();
    }
    return '';
  }

  private readObjectStringField(obj: Object | null, fieldCandidates: string[]): string {
    if (!obj || typeof obj !== 'object') {
      return '';
    }
    const record = obj as Record<string, Object>;
    for (let i = 0; i < fieldCandidates.length; i++) {
      const field = fieldCandidates[i];
      const keys = Object.keys(record);
      if (!keys.includes(field)) {
        continue;
      }
      const value = record[field];
      if (typeof value === 'string' && value.trim().length > 0) {
        return value.trim();
      }
    }
    return '';
  }

  private readObjectField(obj: Object | null, field: string): Object | null {
    if (!obj || typeof obj !== 'object') {
      return null;
    }
    const record = obj as Record<string, Object>;
    const keys = Object.keys(record);
    if (!keys.includes(field)) {
      return null;
    }
    const value = record[field];
    if (!value || typeof value !== 'object') {
      return null;
    }
    return value;
  }

  private isInvalidParsedTocUrl(tocUrl: string): boolean {
    const trimmedUrl = tocUrl.trim();
    if (!trimmedUrl) {
      return false;
    }

    if (trimmedUrl.startsWith('//')) {
      return false;
    }

    if (trimmedUrl.startsWith('http://') || trimmedUrl.startsWith('https://')) {
      const withoutScheme = trimmedUrl.replace(/^https?:\/\//i, '');
      const firstSlash = withoutScheme.indexOf('/');
      if (firstSlash < 0) {
        return false;
      }
      const pathPart = withoutScheme.substring(firstSlash);
      return pathPart.includes('//');
    }

    return trimmedUrl.includes('//');
  }

  private parseTruthyFlag(flagValue: string): boolean {
    const normalized = flagValue.trim().toLowerCase();
    if (normalized.length <= 0) {
      return false;
    }
    return normalized === 'true' ||
      normalized === '1' ||
      normalized === 'yes' ||
      normalized === 'y' ||
      normalized === 'on';
  }

  private resolveChapterUrlWithFallback(
    rawUrl: string,
    title: string,
    isVolume: boolean,
    index: number,
    baseUrl: string
  ): string {
    const normalizedUrl = this.normalizeParsedUrl(rawUrl, baseUrl);
    if (normalizedUrl.length > 0) {
      return normalizedUrl;
    }
    if (isVolume) {
      logger.debug(TAG, `目录${index}未解析到URL，按legado兼容策略回退卷标识URL`);
      return `${title}${index}`;
    }
    logger.debug(TAG, `目录${index}未解析到URL，按legado兼容策略回退baseUrl`);
    return baseUrl;
  }

  private extractParsedUrlList(inputs: string[], baseUrl: string): string[] {
    const result: string[] = [];
    for (let i = 0; i < inputs.length; i++) {
      const rawInput = inputs[i];
      if (!rawInput || rawInput.trim().length <= 0) {
        continue;
      }
      const pieces = rawInput.split('\n');
      for (let j = 0; j < pieces.length; j++) {
        const rawUrl = pieces[j].trim();
        if (rawUrl.length <= 0) {
          continue;
        }
        const parsedUrl = this.normalizeParsedUrl(rawUrl, baseUrl);
        if (parsedUrl.length > 0 && !result.includes(parsedUrl)) {
          result.push(parsedUrl);
        }
      }
    }
    return result;
  }

  private async extractParsedUrlListFromRule(
    analyzer: LegadoRuleAnalyzer,
    ruleText: string | undefined,
    baseUrl: string
  ): Promise<string[]> {
    if (!ruleText || ruleText.trim().length <= 0) {
      return [];
    }
    if (this.shouldReadRuleAsync(ruleText)) {
      const value = await analyzer.getStringAsync(ruleText);
      this.syncRuleVariablesToUrlAnalyzer(analyzer.getVariablesSnapshot());
      this.persistRuleAnalyzerSourceEffects(analyzer);
      return this.extractParsedUrlList([value], baseUrl);
    }
    const values = analyzer.getStringList(ruleText);
    this.syncRuleVariablesToUrlAnalyzer(analyzer.getVariablesSnapshot());
    this.persistRuleAnalyzerSourceEffects(analyzer);
    return this.extractParsedUrlList(values, baseUrl);
  }

  private async extractFirstParsedUrlFromRule(
    analyzer: LegadoRuleAnalyzer,
    ruleText: string | undefined,
    baseUrl: string
  ): Promise<string | null> {
    const urls = await this.extractParsedUrlListFromRule(analyzer, ruleText, baseUrl);
    return urls.length > 0 ? urls[0] : null;
  }

  private buildImageContentFromParsedUrls(urls: string[], baseUrl: string): string {
    const result: string[] = [];
    const seen: Set<string> = new Set<string>();
    for (let i = 0; i < urls.length; i++) {
      const rawUrl = urls[i] ? urls[i].trim() : '';
      if (rawUrl.length <= 0) {
        continue;
      }
      const resolvedUrl = HtmlFormatter.resolveUrlForImage(rawUrl, baseUrl);
      const imageUrl = HtmlFormatter.getUrlWithoutLegadoOption(resolvedUrl);
      if (!this.isUsableParsedImageUrl(imageUrl) || seen.has(resolvedUrl)) {
        continue;
      }
      seen.add(resolvedUrl);
      result.push(`<img src="${this.escapeHtmlAttribute(resolvedUrl)}">`);
    }
    return result.join('\n');
  }

  private buildImageContentFromRawHtml(html: string, baseUrl: string): string {
    const images: LegadoMangaExtractedImage[] = LegadoMangaImageExtractor.extractImages(html, baseUrl);
    if (images.length <= 0) {
      return '';
    }
    const urls: string[] = [];
    for (let i = 0; i < images.length; i++) {
      const image = images[i];
      const requestUrl = image.requestUrl && image.requestUrl.trim().length > 0 ? image.requestUrl : image.imageUrl;
      if (requestUrl && requestUrl.trim().length > 0) {
        urls.push(requestUrl);
      }
    }
    return this.buildImageContentFromParsedUrls(urls, baseUrl);
  }

  private hasUnresolvedImageRuleToken(content: string): boolean {
    if (!content || content.trim().length <= 0) {
      return false;
    }
    const normalized = content.trim().toLowerCase();
    if (normalized.indexOf('img@src') >= 0 || normalized.indexOf('img@data-src') >= 0 ||
      normalized.indexOf('img@data-original') >= 0) {
      return true;
    }
    return /(?:^|[\/\s"'(])(?:img|image|picture)@(?:src|data-src|data-original|href)(?:$|[\s"'?#),])/i.test(normalized);
  }

  private hasExtractableImageContent(content: string, baseUrl: string): boolean {
    if (!content || content.trim().length <= 0) {
      return false;
    }
    const images: LegadoMangaExtractedImage[] = LegadoMangaImageExtractor.extractImages(content, baseUrl);
    return images.length > 0;
  }

  private shouldSkipImageNextContentUrl(baseUrl: string, content: string): boolean {
    if (!baseUrl || !content) {
      return false;
    }
    const normalizedBaseUrl = baseUrl.toLowerCase();
    const isAllPagesUrl = normalizedBaseUrl.indexOf('?page=all') >= 0 ||
      normalizedBaseUrl.indexOf('&page=all') >= 0;
    return isAllPagesUrl && this.hasExtractableImageContent(content, baseUrl);
  }

  private isUsableParsedImageUrl(url: string): boolean {
    if (!url || url.trim().length <= 0) {
      return false;
    }
    const normalized = url.trim().toLowerCase();
    if (normalized === '#' || normalized === 'about:blank' || normalized.startsWith('javascript:')) {
      return false;
    }
    if (normalized.indexOf('<') >= 0 || normalized.indexOf('>') >= 0 || normalized.indexOf('"') >= 0) {
      return false;
    }
    if (normalized.startsWith('data:') && normalized.indexOf('data:image/') !== 0) {
      return false;
    }
    if (normalized.indexOf('@') >= 0 && !/\.(?:jpg|jpeg|png|webp|gif|bmp|avif)(?:[?#,@]|$)/i.test(normalized)) {
      return false;
    }
    if (normalized.indexOf('placeholder') >= 0 || normalized.indexOf('blank.gif') >= 0 ||
      normalized.indexOf('spacer.gif') >= 0 || normalized.indexOf('transparent.gif') >= 0) {
      return false;
    }
    return true;
  }

  private escapeHtmlAttribute(value: string): string {
    return value
      .replace(/&/g, '&amp;')
      .replace(/"/g, '&quot;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;');
  }

  private resolveContentFallbackWhenRuleMissing(chapter: LegadoChapter): string {
    const chapterUrl = chapter.url.trim();
    if (chapterUrl.length > 0) {
      logger.debug(TAG, `正文规则为空，按legado兼容策略返回章节URL: ${chapterUrl}`);
      return chapterUrl;
    }
    return '';
  }

  private async parseChapterListWithNext(
    html: string,
    baseUrl: string,
    book: LegadoBook,
    startIndex: number
  ): Promise<ChapterListParseResult> {
    const chapters: LegadoChapter[] = [];
    const rule = this.source.ruleToc;

    if (!rule || !rule.chapterList) {
      const emptyResult: ChapterListParseResult = { chapters: chapters, nextUrl: null };
      return emptyResult;
    }

    const analyzer = this.createRuleAnalyzer();
    analyzer.setContent(html, baseUrl);

    const chapterElements = await analyzer.getElementsAsync(rule.chapterList);
    this.persistRuleAnalyzerSourceEffects(analyzer);

    for (let i = 0; i < chapterElements.length; i++) {
      const itemAnalyzer = this.createRuleAnalyzer();
      itemAnalyzer.setContent(chapterElements[i], baseUrl);

      const title = (await itemAnalyzer.getStringAsync(rule.chapterName)).trim();
      if (!title) {
        continue;
      }

      const isVolumeRaw = rule.isVolume ? await itemAnalyzer.getStringAsync(rule.isVolume) : '';
      const isVipRaw = rule.isVip ? await itemAnalyzer.getStringAsync(rule.isVip) : '';
      const isPayRaw = rule.isPay ? await itemAnalyzer.getStringAsync(rule.isPay) : '';
      const isVolume = this.parseTruthyFlag(isVolumeRaw);
      const chapterUrlRule = rule.chapterUrl ?? '';
      const url = chapterUrlRule.length > 0 ? await itemAnalyzer.getStringAsync(chapterUrlRule) : '';
      const fallbackUrl = this.resolveChapterUrlWithFallback(url, title, isVolume, startIndex + i, baseUrl);
      const updateTag = rule.updateTime ? await itemAnalyzer.getStringAsync(rule.updateTime) : '';
      const chapterVariable = this.buildChapterVariablePayload(itemAnalyzer.getVariablesSnapshot());
      this.persistRuleAnalyzerSourceEffects(itemAnalyzer);

      const chapter: LegadoChapter = {
        id: this.generateId(),
        bookUrl: book.bookUrl,
        url: fallbackUrl,
        title: title,
        index: startIndex + chapters.length,
        isVolume: isVolume,
        isVip: this.parseTruthyFlag(isVipRaw),
        isPay: this.parseTruthyFlag(isPayRaw),
        variable: chapterVariable.length > 0 ? chapterVariable : undefined,
        tag: updateTag
      };

      chapters.push(chapter);
    }

    let nextUrl: string | null = null;
    if (rule.nextTocUrl) {
      nextUrl = await this.extractFirstParsedUrlFromRule(analyzer, rule.nextTocUrl, baseUrl);
    }

    const result: ChapterListParseResult = { chapters: chapters, nextUrl: nextUrl };
    return result;
  }
  private async parseChapterList(html: string, baseUrl: string, book: LegadoBook): Promise<LegadoChapter[]> {
    const parseResult = await this.parseChapterListWithNext(html, baseUrl, book, 0);
    const chapters = parseResult.chapters;
    logger.info(TAG, `章节列表: ${chapters.length} 章`);
    return chapters;
  }
  private async parseContentWithNext(html: string, baseUrl: string, chapter: LegadoChapter): Promise<ContentParseResult> {
    const rule = this.source.ruleContent;

    if (!rule || !rule.content) {
      if (this.source.bookSourceType === LegadoBookSourceType.IMAGE) {
        const imageFallbackContent = this.buildImageContentFromRawHtml(html, baseUrl);
        if (imageFallbackContent.length > 0) {
          const imageFallbackResult: ContentParseResult = { content: imageFallbackContent, nextUrl: null };
          return imageFallbackResult;
        }
      }
      const fallbackContent = this.resolveContentFallbackWhenRuleMissing(chapter);
      const fallbackResult: ContentParseResult = { content: fallbackContent, nextUrl: null };
      return fallbackResult;
    }

    const analyzer = this.createRuleAnalyzer();
    analyzer.setContent(html, baseUrl);

    let content = '';
    let contentBuiltFromParsedImageUrls = false;

    if (this.source.bookSourceType === LegadoBookSourceType.IMAGE && !this.shouldReadRuleAsync(rule.content)) {
      const parsedImageUrls = await this.extractParsedUrlListFromRule(analyzer, rule.content, baseUrl);
      content = this.buildImageContentFromParsedUrls(parsedImageUrls, baseUrl);
      contentBuiltFromParsedImageUrls = content.length > 0;
    }

    if (content.length <= 0) {
      content = await analyzer.getStringAsync(rule.content);
      this.persistRuleAnalyzerSourceEffects(analyzer);
      if (!content) {
        if (this.source.bookSourceType === LegadoBookSourceType.IMAGE) {
          content = this.buildImageContentFromRawHtml(html, baseUrl);
          contentBuiltFromParsedImageUrls = content.length > 0;
        }
        if (!content) {
          const emptyResult: ContentParseResult = { content: '', nextUrl: null };
          return emptyResult;
        }
      }
    }

    if (this.source.bookSourceType === LegadoBookSourceType.AUDIO) {
      let audioContent = content.trim();
      if (audioContent.indexOf('&') > -1) {
        audioContent = HtmlFormatter.unescapeHtml(audioContent);
      }
      let nextUrl: string | null = null;
      let nextUrls: string[] = [];
      if (rule.nextContentUrl) {
        nextUrls = await this.extractParsedUrlListFromRule(analyzer, rule.nextContentUrl, baseUrl);
        nextUrl = nextUrls.length > 0 ? nextUrls[0] : null;
      }
      logger.debug(TAG, `听书源正文保持原始模式: chapter=${chapter.title}, contentLength=${audioContent.length}`);
      const audioResult: ContentParseResult = { content: audioContent, nextUrl: nextUrl, nextUrls: nextUrls };
      return audioResult;
    }

    if (this.source.bookSourceType === LegadoBookSourceType.IMAGE) {
      if (!contentBuiltFromParsedImageUrls) {
        content = HtmlFormatter.formatKeepImg(content, baseUrl);
      }
      const shouldUseRawHtmlFallback: boolean = content.length <= 0 ||
        this.hasUnresolvedImageRuleToken(content) ||
        !this.hasExtractableImageContent(content, baseUrl);
      if (shouldUseRawHtmlFallback) {
        const imageFallbackContent = this.buildImageContentFromRawHtml(html, baseUrl);
        if (imageFallbackContent.length > 0) {
          logger.warn(TAG, `漫画书源正文规则未产出有效图片，回退原始HTML图片解析: chapter=${chapter.title}, ruleContentLength=${content.length}, fallbackLength=${imageFallbackContent.length}`);
          content = imageFallbackContent;
        }
      }
      if (content.indexOf('&') > -1) {
        content = HtmlFormatter.unescapeHtml(content);
      }

      if (rule.replaceRegex && content) {
        content = this.applyReplaceRules(content, rule.replaceRegex);
      }

      let nextUrl: string | null = null;
      let nextUrls: string[] = [];
      if (rule.nextContentUrl && !this.shouldSkipImageNextContentUrl(baseUrl, content)) {
        nextUrls = await this.extractParsedUrlListFromRule(analyzer, rule.nextContentUrl, baseUrl);
        nextUrl = nextUrls.length > 0 ? nextUrls[0] : null;
      } else if (rule.nextContentUrl) {
        logger.info(TAG, `漫画书源当前URL已包含全部页面，跳过正文下一页规则: chapter=${chapter.title}, url=${baseUrl}`);
      }

      logger.debug(TAG, `漫画书源正文保持图片模式: chapter=${chapter.title}, contentLength=${content.length}`);
      const imageResult: ContentParseResult = { content: content, nextUrl: nextUrl, nextUrls: nextUrls };
      return imageResult;
    }

    content = HtmlFormatter.format(content, false);
    if (content.indexOf('&') > -1) {
      content = HtmlFormatter.unescapeHtml(content);
    }

    if (rule.replaceRegex && content) {
      content = this.applyReplaceRules(content, rule.replaceRegex);
    }

    const replaceManager = getNovelReplaceRuleManager();
    content = replaceManager.applyRules(content, ReplaceScope.CONTENT, this.source.bookSourceUrl);

    content = HtmlFormatter.cleanContent(content);

    let nextUrl: string | null = null;
    let nextUrls: string[] = [];
    if (rule.nextContentUrl) {
      nextUrls = await this.extractParsedUrlListFromRule(analyzer, rule.nextContentUrl, baseUrl);
      nextUrl = nextUrls.length > 0 ? nextUrls[0] : null;
    }

    const result: ContentParseResult = { content: content, nextUrl: nextUrl, nextUrls: nextUrls };
    return result;
  }
  private async parseContent(html: string, baseUrl: string, chapter: LegadoChapter): Promise<string> {
    const parseResult = await this.parseContentWithNext(html, baseUrl, chapter);
    const content = parseResult.content;
    return content;
  }
  private applyReplaceRules(content: string, replaceRegex: string): string {
    if (!replaceRegex || !content) {
      return content;
    }
    
    // 按换行分割多条规则
    const replaceRules = replaceRegex.split('\n');
    let result = content;
    
    for (const replaceRule of replaceRules) {
      if (!replaceRule.trim()) {
        continue;
      }
      
      // 使用##分割: pattern##replacement##replaceFirst
      const parts = replaceRule.split('##');
      if (parts.length < 1 || !parts[0].trim()) {
        continue;
      }
      
      const pattern = parts[0];
      const replacement = parts.length > 1 ? parts[1] : '';
      // 如果有第三个部分，表示只替换第一个匹配
      const replaceFirst = parts.length > 2;
      
      try {
        const regex = new RegExp(pattern, replaceFirst ? '' : 'g');
        if (replaceFirst) {
          // 只替换第一个匹配
          result = result.replace(regex, replacement);
        } else {
          // 替换所有匹配
          result = result.replace(regex, replacement);
        }
      } catch (e) {
        // 正则表达式无效，尝试作为普通字符串替换
        try {
          if (replaceFirst) {
            const index = result.indexOf(pattern);
            if (index !== -1) {
              result = result.substring(0, index) + replacement + result.substring(index + pattern.length);
            }
          } else {
            result = result.split(pattern).join(replacement);
          }
        } catch (e2) {
          // 忽略错误
        }
      }
    }
    return result;
  }

  /**
   * 生成唯一ID
   */
  private generateId(): string {
    return `${Date.now()}_${Math.random().toString(36).substring(2, 9)}`;
  }
}
