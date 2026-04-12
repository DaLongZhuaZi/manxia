/**
 * 小说源执行器
 * 负责执行书源的搜索、获取详情、目录、正文等操作
 * 
 * 文件路径: entry/src/main/ets/Framework/Novel/NovelSourceExecutor.ets
 */

import { logger } from '../../Utils/Logger';
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import {
  LegadoBookSource,
  LegadoSearchBook,
  LegadoBook,
  LegadoChapter,
  LegadoExploreKind,
  LegadoBookSourceType
} from './LegadoSourceTypes';
import { LegadoSourceParser } from './LegadoSourceParser';
import { LegadoRuleAnalyzer } from './LegadoRuleAnalyzer';
import { LegadoUrlAnalyzer, ParsedUrlRequest, RequestMethod } from './LegadoUrlAnalyzer';
import { getNovelReplaceRuleManager, ReplaceScope } from './NovelReplaceRuleManager';
import { getNovelLoginManager } from './NovelLoginManager';
import { HtmlFormatter } from './HtmlFormatter';
import { ProxyManager } from '../Network/ProxyManager';

const TAG = 'NovelSourceExecutor';
const REQUEST_TIMEOUT_MS = 15000;

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
    this.urlAnalyzer
      .setVariable('__source_bookSourceName', source.bookSourceName || '')
      .setVariable('__source_bookSourceGroup', source.bookSourceGroup || '')
      .setVariable('__source_bookSourceComment', source.bookSourceComment || '')
      .setVariable('__source_header', source.header || '')
      .setVariable('__source_loginUrl', source.loginUrl || '')
      .setVariable('__source_loginUi', source.loginUi || '')
      .setVariable('__source_loginCheckJs', source.loginCheckJs || '')
      .setVariable('__source_variableComment', source.variableComment || '');
  }
  
  /**
   * 确保当前执行器使用当前书源的jsLib快照
   */
  private ensureJsLib(): void {
    // 仅更新当前执行器的URL解析器快照，避免并发校验时污染全局jsLib
    this.urlAnalyzer.setJsLib(this.source.jsLib || '');
  }

  private createRuleAnalyzer(): LegadoRuleAnalyzer {
    const analyzer = new LegadoRuleAnalyzer();
    analyzer.setJsLib(this.source.jsLib || '');
    return analyzer;
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
    return normalized;
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
      if (this.shouldAnalyzeUrlAsync(urlTemplate)) {
        this.ensureJsLib();
        return await this.urlAnalyzer.analyzeUrlAsync(urlTemplate, key, page);
      }

      const request = this.urlAnalyzer.analyzeUrl(urlTemplate, key, page);
      if (this.hasUnresolvedRuleTokens(request.url)) {
        this.ensureJsLib();
        return await this.urlAnalyzer.analyzeUrlAsync(urlTemplate, key, page);
      }
      return request;
    } finally {
      if (hasRuntimeBaseUrl) {
        this.urlAnalyzer.setBaseUrl(originalBaseUrl);
      }
    }
  }
  async getBookInfo(bookUrl: string): Promise<LegadoBook | null> {
    this.ensureJsLib();
    try {
      const request = await this.analyzeRequestUrl(bookUrl);
      const response = await this.executeRequest(request);

      if (!response) {
        return null;
      }

      return this.parseBookInfo(response, request.url, request.url);
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
    let pageCount = 0;
    const maxPages = 20;

    try {
      await this.prepareContentRuleVariables(chapter);
      while (currentUrl && pageCount < maxPages) {
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

        if (contentResult.nextUrl && contentResult.nextUrl !== currentUrl) {
          currentUrl = contentResult.nextUrl;
          pageCount++;
          logger.debug(TAG, `正文分页 ${pageCount}: ${contentResult.nextUrl}`);
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
        const parsed = JSON.parse(trimmedText) as Record<string, string | number | boolean | null>;
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

      const parsedBook = this.parseBookInfo(response, request.url, normalizedBookUrl);
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

      return this.parseExploreResult(response, request.url);
    } catch (error) {
      logger.error(TAG, `发现页获取失败: ${String(error)}`);
      return [];
    }
  }
  private parseExploreResult(html: string, baseUrl: string): LegadoSearchBook[] {
    const results: LegadoSearchBook[] = [];
    const rule = this.source.ruleExplore;
    
    if (!rule || !rule.bookList) {
      return results;
    }

    const analyzer = this.createRuleAnalyzer();
    analyzer.setContent(html, baseUrl);

    const bookElements = analyzer.getElements(rule.bookList);
    
    for (let i = 0; i < bookElements.length; i++) {
      const itemAnalyzer = this.createRuleAnalyzer();
      itemAnalyzer.setContent(bookElements[i], baseUrl);

      const name = itemAnalyzer.getString(rule.name);
      if (!name) {
        continue;
      }

      const searchBook: LegadoSearchBook = {
        origin: this.source.bookSourceUrl,
        originName: this.source.bookSourceName,
        bookUrl: itemAnalyzer.getString(rule.bookUrl) || baseUrl,
        name: name,
        author: itemAnalyzer.getString(rule.author) || '',
        kind: itemAnalyzer.getString(rule.kind),
        intro: itemAnalyzer.getString(rule.intro),
        coverUrl: itemAnalyzer.getString(rule.coverUrl),
        latestChapterTitle: itemAnalyzer.getString(rule.lastChapter),
        wordCount: itemAnalyzer.getString(rule.wordCount),
        type: this.source.bookSourceType
      };

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

      if (this.hasUnresolvedRuleTokens(request.url)) {
        logger.error(TAG, `URL包含未解析的规则: ${request.url.substring(0, 100)}...`);
        logger.warn(TAG, '请检查JS引擎是否正常工作');
        return null;
      }

      if (request.url.startsWith('data:')) {
        const dataPayload = this.parseDataUrl(request.url);
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

      logger.debug(TAG, `请求: ${request.method} ${request.url}`);
      if (request.body) {
        logger.debug(TAG, `请求Body: ${request.body}`);
      }

      const httpRequest = http.createHttp();
      const needCustomDecode: boolean = !!request.charset &&
        request.charset.toLowerCase() !== 'utf-8' &&
        request.charset.toLowerCase() !== 'utf8';

      const options: http.HttpRequestOptions = {
        method: request.method === RequestMethod.POST ? http.RequestMethod.POST : http.RequestMethod.GET,
        header: this.buildHeaders(request.headers),
        connectTimeout: REQUEST_TIMEOUT_MS,
        readTimeout: REQUEST_TIMEOUT_MS,
        expectDataType: needCustomDecode ? http.HttpDataType.ARRAY_BUFFER : http.HttpDataType.STRING
      };

      const proxyManager = ProxyManager.getInstance();
      if (proxyManager.isEnabled()) {
        options.usingProxy = true;
        logger.debug(TAG, `使用代理请求: ${request.url}`);
      }

      if (request.method === RequestMethod.POST) {
        const header = options.header as Record<string, string>;
        if (!header['Content-Type']) {
          if (request.body && (request.body.trim().startsWith('{') || request.body.trim().startsWith('['))) {
            header['Content-Type'] = 'application/json; charset=utf-8';
          } else {
            header['Content-Type'] = 'application/x-www-form-urlencoded; charset=utf-8';
          }
        }
        if (request.body) {
          options.extraData = request.body;
        }
        logger.debug(TAG, `POST Content-Type: ${header['Content-Type']}`);
      }

      const response = await httpRequest.request(request.url, options);
      httpRequest.destroy();

      if (response.responseCode >= 200 && response.responseCode < 300) {
        if (needCustomDecode && response.result instanceof ArrayBuffer) {
          try {
            const decoder = new util.TextDecoder(request.charset);
            const result = decoder.decodeToString(new Uint8Array(response.result));
            logger.debug(TAG, `使用${request.charset}解码响应，长度: ${result.length}`);
            return result;
          } catch (decodeError) {
            logger.warn(TAG, `使用${request.charset}解码失败，尝试UTF-8: ${String(decodeError)}`);
            const decoder = new util.TextDecoder('utf-8');
            return decoder.decodeToString(new Uint8Array(response.result));
          }
        }
        return typeof response.result === 'string' ? response.result : String(response.result);
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
  private parseDataUrl(url: string): string {
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

        const decodedContent = this.tryDecodeBase64DataUrlPayload(content);
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

  private tryDecodeBase64DataUrlPayload(payload: string): string | null {
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
      const decodedBytes: Uint8Array = base64Helper.decodeSync(normalized);
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
        const dataPayload = this.parseDataUrl(request.url);
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

      logger.debug(TAG, `请求: ${request.method} ${request.url}`);
      if (request.body) {
        logger.debug(TAG, `请求Body: ${request.body}`);
      }

      const httpRequest = http.createHttp();
      const needCustomDecode: boolean = !!request.charset &&
        request.charset.toLowerCase() !== 'utf-8' &&
        request.charset.toLowerCase() !== 'utf8';

      const options: http.HttpRequestOptions = {
        method: request.method === RequestMethod.POST ? http.RequestMethod.POST : http.RequestMethod.GET,
        header: this.buildHeaders(request.headers),
        connectTimeout: REQUEST_TIMEOUT_MS,
        readTimeout: REQUEST_TIMEOUT_MS,
        expectDataType: needCustomDecode ? http.HttpDataType.ARRAY_BUFFER : http.HttpDataType.STRING
      };

      const proxyMgr = ProxyManager.getInstance();
      if (proxyMgr.isEnabled()) {
        options.usingProxy = true;
      }

      if (request.method === RequestMethod.POST) {
        const header = options.header as Record<string, string>;
        if (!header['Content-Type']) {
          if (request.body && (request.body.trim().startsWith('{') || request.body.trim().startsWith('['))) {
            header['Content-Type'] = 'application/json; charset=utf-8';
          } else {
            header['Content-Type'] = 'application/x-www-form-urlencoded; charset=utf-8';
          }
        }
        if (request.body) {
          options.extraData = request.body;
        }
        logger.debug(TAG, `POST Content-Type: ${header['Content-Type']}`);
      }

      const response = await httpRequest.request(request.url, options);
      httpRequest.destroy();

      if (response.responseCode >= 200 && response.responseCode < 300) {
        let responseStr: string;
        if (needCustomDecode && response.result instanceof ArrayBuffer) {
          try {
            const decoder = new util.TextDecoder(request.charset);
            responseStr = decoder.decodeToString(new Uint8Array(response.result));
            logger.debug(TAG, `使用${request.charset}解码响应，长度: ${responseStr.length}`);
          } catch (decodeError) {
            logger.warn(TAG, `使用${request.charset}解码失败，尝试UTF-8: ${String(decodeError)}`);
            const decoder = new util.TextDecoder('utf-8');
            responseStr = decoder.decodeToString(new Uint8Array(response.result));
          }
        } else {
          responseStr = typeof response.result === 'string' ? response.result : String(response.result);
        }
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
  private buildHeaders(customHeaders: Record<string, string>): Record<string, string> {
    const headers: Record<string, string> = {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 11) AppleWebKit/537.36 Chrome/91.0.4472.120 Mobile Safari/537.36'
    };

    // 合并书源配置的请求头
    if (this.source.header) {
      try {
        const sourceHeaders = JSON.parse(this.source.header) as Record<string, string>;
        Object.keys(sourceHeaders).forEach(key => {
          headers[key] = sourceHeaders[key];
        });
      } catch (e) {
        // 忽略解析错误
      }
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
    const shouldUseAsyncRule = (ruleText?: string): boolean => {
      if (!ruleText) {
        return false;
      }
      const lowerRule = ruleText.toLowerCase();
      return lowerRule.includes('<js>') ||
        lowerRule.includes('@js:') ||
        lowerRule.includes('@js：') ||
        lowerRule.includes('＠js:') ||
        lowerRule.includes('＠js：') ||
        lowerRule.startsWith('js:') ||
        lowerRule.startsWith('js：');
    };
    const nameUseAsync = shouldUseAsyncRule(rule.name);
    const bookUrlUseAsync = shouldUseAsyncRule(rule.bookUrl);
    const authorUseAsync = shouldUseAsyncRule(rule.author);
    const kindUseAsync = shouldUseAsyncRule(rule.kind);
    const introUseAsync = shouldUseAsyncRule(rule.intro);
    const coverUrlUseAsync = shouldUseAsyncRule(rule.coverUrl);
    const latestChapterUseAsync = shouldUseAsyncRule(rule.lastChapter);
    const wordCountUseAsync = shouldUseAsyncRule(rule.wordCount);
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
      const bookUrl = bookUrlRaw || baseUrl;
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
      const coverUrl = typeof coverRuleValue === 'string' ? coverRuleValue : await coverRuleValue;
      await maybeYield();
      const chapterRuleValue = readRuleValue(rule.lastChapter, latestChapterUseAsync);
      const latestChapterTitle = typeof chapterRuleValue === 'string' ? chapterRuleValue : await chapterRuleValue;
      await maybeYield();
      const wordCountRuleValue = readRuleValue(rule.wordCount, wordCountUseAsync);
      const wordCount = typeof wordCountRuleValue === 'string' ? wordCountRuleValue : await wordCountRuleValue;
      await maybeYield();
      
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

  /**
   * 解析书籍详情
   * 注意：即使name规则为空，也会尝试解析其他字段（如tocUrl），返回部分结果
   * 调用方可以使用fallback信息补充缺失的字段
   */
  private parseBookInfo(html: string, baseUrl: string, bookUrl: string): LegadoBook | null {
    const rule = this.source.ruleBookInfo;

    const analyzer = this.createRuleAnalyzer();

    let contentToAnalyze = html;
    if (rule && rule.init) {
      const initAnalyzer = this.createRuleAnalyzer();
      initAnalyzer.setContent(html, baseUrl);
      const initData = initAnalyzer.getString(rule.init);
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

    const name = rule?.name ? analyzer.getString(rule.name) : '';
    const fallbackName = this.extractFallbackBookName(contentToAnalyze);
    const resolvedName = name || fallbackName;
    if (contentToAnalyze.length < 50000) {
      logger.debug(TAG, `解析书名结果: "${resolvedName}", 规则: ${rule?.name}`);
    }

    const tocUrl = rule?.tocUrl ? analyzer.getString(rule.tocUrl) : '';
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

    if (contentToAnalyze.length < 50000) {
      logger.debug(TAG, `解析书籍详情: name=${resolvedName}, bookUrl=${bookUrl}, tocUrl=${tocUrl}`);
    }

    const book: LegadoBook = {
      id: this.generateId(),
      origin: this.source.bookSourceUrl,
      originName: this.source.bookSourceName,
      bookUrl: bookUrl,
      name: resolvedName,
      author: rule?.author ? analyzer.getString(rule.author) : '',
      kind: rule?.kind ? analyzer.getString(rule.kind) : undefined,
      intro: rule?.intro ? analyzer.getString(rule.intro) : undefined,
      coverUrl: rule?.coverUrl ? analyzer.getString(rule.coverUrl) : undefined,
      tocUrl: tocUrl || bookUrl,
      latestChapterTitle: rule?.lastChapter ? analyzer.getString(rule.lastChapter) : undefined,
      wordCount: rule?.wordCount ? analyzer.getString(rule.wordCount) : undefined,
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
      // ignore
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
    const normalizedUrl = rawUrl.trim();
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

  private extractFirstNonEmptyLine(input: string): string | null {
    if (!input || input.trim().length <= 0) {
      return null;
    }
    const urls = input.split('\n').filter((item: string): boolean => item.trim().length > 0);
    if (urls.length <= 0) {
      return null;
    }
    return urls[0].trim();
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
      const nextUrlStr = await analyzer.getStringAsync(rule.nextTocUrl);
      nextUrl = this.extractFirstNonEmptyLine(nextUrlStr);
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
      const fallbackContent = this.resolveContentFallbackWhenRuleMissing(chapter);
      const fallbackResult: ContentParseResult = { content: fallbackContent, nextUrl: null };
      return fallbackResult;
    }

    const analyzer = this.createRuleAnalyzer();
    analyzer.setContent(html, baseUrl);

    let content = await analyzer.getStringAsync(rule.content);
    if (!content) {
      const emptyResult: ContentParseResult = { content: '', nextUrl: null };
      return emptyResult;
    }

    if (this.source.bookSourceType === LegadoBookSourceType.AUDIO) {
      let audioContent = content.trim();
      if (audioContent.indexOf('&') > -1) {
        audioContent = HtmlFormatter.unescapeHtml(audioContent);
      }
      let nextUrl: string | null = null;
      if (rule.nextContentUrl) {
        const nextUrlStr = await analyzer.getStringAsync(rule.nextContentUrl);
        nextUrl = this.extractFirstNonEmptyLine(nextUrlStr);
      }
      logger.debug(TAG, `听书源正文保持原始模式: chapter=${chapter.title}, contentLength=${audioContent.length}`);
      const audioResult: ContentParseResult = { content: audioContent, nextUrl: nextUrl };
      return audioResult;
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
    if (rule.nextContentUrl) {
      const nextUrlStr = await analyzer.getStringAsync(rule.nextContentUrl);
      nextUrl = this.extractFirstNonEmptyLine(nextUrlStr);
    }

    const result: ContentParseResult = { content: content, nextUrl: nextUrl };
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
