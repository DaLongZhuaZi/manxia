/**
 * 小说源执行器
 * 负责执行书源的搜索、获取详情、目录、正文等操作
 * 
 * 文件路径: entry/src/main/ets/Framework/Novel/NovelSourceExecutor.ets
 */

import { logger } from '../../Utils/Logger';
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { LegadoBookSource, LegadoSearchBook, LegadoBook, LegadoChapter, LegadoExploreKind } from './LegadoSourceTypes';
import { LegadoSourceParser } from './LegadoSourceParser';
import { LegadoRuleAnalyzer } from './LegadoRuleAnalyzer';
import { LegadoUrlAnalyzer, ParsedUrlRequest, RequestMethod } from './LegadoUrlAnalyzer';
import { getNovelReplaceRuleManager, ReplaceScope } from './NovelReplaceRuleManager';
import { getNovelLoginManager } from './NovelLoginManager';
import { HtmlFormatter } from './HtmlFormatter';
import { getLegadoJsEngine } from './LegadoJsEngine';
import { ProxyManager } from '../Network/ProxyManager';

const TAG = 'NovelSourceExecutor';

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
interface SearchParseOptions {
  /** 最多保留多少条搜索结果（<=0 时表示不限制） */
  maxResults?: number;
  /** 最多扫描多少个候选元素（<=0 时表示不限制） */
  maxElementScan?: number;
  /** 是否禁用 item 级 DOM bridge（改用字符串解析） */
  disableItemDomBridge?: boolean;
}

/**
 * 小说源执行器类
 */
export class NovelSourceExecutor {
  private source: LegadoBookSource;
  private urlAnalyzer: LegadoUrlAnalyzer;

  constructor(source: LegadoBookSource) {
    this.source = source;
    // 传入baseUrl和sourceUrl，支持JS中的source.getKey()
    this.urlAnalyzer = new LegadoUrlAnalyzer(
      LegadoSourceParser.getBaseUrl(source),
      source.bookSourceUrl
    );
  }
  
  /**
   * 确保JS引擎使用当前书源的jsLib
   * 由于JS引擎是单例，多个书源并发使用时需要在每次操作前设置
   */
  private ensureJsLib(): void {
    if (this.source.jsLib) {
      getLegadoJsEngine().setJsLib(this.source.jsLib);
    }
  }

  /**
   * 搜索书籍
   */
  async search(keyword: string, page: number = 1): Promise<LegadoSearchBook[]> {
    const result = await this.searchWithError(keyword, page);
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
      
      // 检查搜索URL是否包含JS规则，使用异步方法处理
      const hasJsRule = searchUrl.includes('<js>') || searchUrl.includes('@js:') || 
                        (searchUrl.includes('{{') && this.containsJsExpression(searchUrl));
      
      let request: ParsedUrlRequest;
      if (hasJsRule) {
        // 确保在执行JS前设置当前书源的jsLib
        this.ensureJsLib();
        // 使用异步方法处理JS规则
        logger.debug(TAG, `[书源:${this.source.bookSourceName}] 使用异步JS解析搜索URL`);
        request = await this.urlAnalyzer.analyzeUrlAsync(searchUrl, keyword, page);
      } else {
        // 普通URL，使用同步方法
        request = this.urlAnalyzer.analyzeUrl(searchUrl, keyword, page);
      }
      
      // 检查解析后的URL是否有效
      if (!request.url || request.url.includes('{{') || request.url.includes('<js>')) {
        const urlSnippet = request.url ? request.url.substring(0, 100) : '';
        logger.warn(TAG, `[书源:${this.source.bookSourceName}] URL解析不完整: ${urlSnippet}`);
        
        // 分析JS错误类型
        const errorType = this.analyzeJsError(urlSnippet);
        return { books: [], errorType, errorMessage: `URL解析不完整: ${urlSnippet}` };
      }
      
      const requestResult = await this.executeRequestWithError(request);
      
      if (requestResult.errorType && requestResult.errorType !== SearchErrorType.NONE) {
        logger.warn(TAG, `[书源:${this.source.bookSourceName}] 搜索请求失败: ${requestResult.errorMessage}`);
        return { books: [], errorType: requestResult.errorType, errorMessage: requestResult.errorMessage || '' };
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
      return { books: [], errorType, errorMessage: errorMsg };
    }
  }
  
  /**
   * 分析JS错误类型
   */
  private analyzeJsError(urlOrError: string): SearchErrorType {
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
    
    return SearchErrorType.UNKNOWN;
  }
  
  /**
   * 检查字符串是否包含JS表达式（而不仅仅是简单变量）
   */
  private containsJsExpression(str: string): boolean {
    // 匹配 {{...}} 中包含非简单变量的内容
    const matches = str.match(/\{\{([^}]+)\}\}/g);
    if (!matches) return false;
    
    for (const match of matches) {
      const expr = match.slice(2, -2).trim();
      // 简单变量: key, page, encodedKey
      if (expr === 'key' || expr === 'page' || expr === 'encodedKey') {
        continue;
      }
      // 包含函数调用、运算符等，认为是JS表达式
      if (expr.includes('(') || expr.includes('.') || expr.includes('+') || 
          expr.includes('var ') || expr.includes('function')) {
        return true;
      }
    }
    return false;
  }

  /**
   * 获取书籍详情
   */
  async getBookInfo(bookUrl: string): Promise<LegadoBook | null> {
    // 确保JS引擎使用当前书源的jsLib
    this.ensureJsLib();
    try {
      const request = this.urlAnalyzer.analyzeUrl(bookUrl);
      const response = await this.executeRequest(request);
      
      if (!response) {
        return null;
      }

      return this.parseBookInfo(response, request.url, bookUrl);
    } catch (error) {
      logger.error(TAG, `获取书籍详情失败: ${String(error)}`);
      return null;
    }
  }

  /**
   * 获取章节列表（支持分页）
   */
  async getChapterList(book: LegadoBook): Promise<LegadoChapter[]> {
    // 确保JS引擎使用当前书源的jsLib
    this.ensureJsLib();
    const tocUrl = book.tocUrl || book.bookUrl;
    const allChapters: LegadoChapter[] = [];
    let currentUrl: string | null = tocUrl;
    let pageCount = 0;
    const maxPages = 50; // 防止无限循环
    
    try {
      while (currentUrl && pageCount < maxPages) {
        const request = this.urlAnalyzer.analyzeUrl(currentUrl);
        const response = await this.executeRequest(request);
        
        if (!response) {
          break;
        }

        const parseResult = this.parseChapterListWithNext(response, request.url, book, allChapters.length);
        const chapters = parseResult.chapters;
        const nextUrl = parseResult.nextUrl;
        for (let j = 0; j < chapters.length; j++) {
          allChapters.push(chapters[j]);
        }
        
        // 检查是否有下一页
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

  /**
   * 获取章节正文（支持分页）
   */
  async getContent(chapter: LegadoChapter): Promise<string> {
    // 确保JS引擎使用当前书源的jsLib
    this.ensureJsLib();
    const allContent: string[] = [];
    let currentUrl: string | null = chapter.url;
    let pageCount = 0;
    const maxPages = 20; // 防止无限循环
    
    try {
      while (currentUrl && pageCount < maxPages) {
        const request = this.urlAnalyzer.analyzeUrl(currentUrl);
        const response = await this.executeRequest(request);
        
        if (!response) {
          break;
        }

        const contentResult = this.parseContentWithNext(response, request.url, chapter);
        if (contentResult.content) {
          allContent.push(contentResult.content);
        }
        
        // 检查是否有下一页
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
    // 确保JS引擎使用当前书源的jsLib
    this.ensureJsLib();
    if (!this.source.ruleExplore) {
      logger.warn(TAG, '书源没有配置发现规则');
      return [];
    }

    try {
      const request = this.urlAnalyzer.analyzeUrl(exploreUrl, '', page);
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

  /**
   * 解析发现页结果
   */
  private parseExploreResult(html: string, baseUrl: string): LegadoSearchBook[] {
    const results: LegadoSearchBook[] = [];
    const rule = this.source.ruleExplore;
    
    if (!rule || !rule.bookList) {
      return results;
    }

    const analyzer = new LegadoRuleAnalyzer();
    analyzer.setContent(html, baseUrl);

    const bookElements = analyzer.getElements(rule.bookList);
    
    for (let i = 0; i < bookElements.length; i++) {
      const itemAnalyzer = new LegadoRuleAnalyzer();
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
      // 检查URL是否包含未解析的JS规则（说明JS执行失败）
      if (request.url.includes('<js>') || request.url.includes('@js:') || request.url.includes('{{')) {
        logger.error(TAG, `URL包含未解析的规则: ${request.url.substring(0, 100)}...`);
        logger.warn(TAG, '请检查JS引擎是否正常工作');
        return null;
      }
      
      // 处理data:协议的URL（用于传递数据，不需要HTTP请求）
      if (request.url.startsWith('data:')) {
        return this.parseDataUrl(request.url);
      }
      
      // 检查URL是否有效
      if (!request.url.startsWith('http://') && !request.url.startsWith('https://')) {
        logger.error(TAG, `无效的URL: ${request.url}`);
        return null;
      }
      
      logger.debug(TAG, `请求: ${request.method} ${request.url}`);
      if (request.body) {
        logger.debug(TAG, `请求Body: ${request.body}`);
      }

      const httpRequest = http.createHttp();
      
      // 如果指定了charset且不是utf-8，使用ArrayBuffer获取原始数据
      const needCustomDecode = request.charset && 
        request.charset.toLowerCase() !== 'utf-8' && 
        request.charset.toLowerCase() !== 'utf8';
      
      const options: http.HttpRequestOptions = {
        method: request.method === RequestMethod.POST ? http.RequestMethod.POST : http.RequestMethod.GET,
        header: this.buildHeaders(request.headers),
        connectTimeout: 10000,
        readTimeout: 10000,
        expectDataType: needCustomDecode ? http.HttpDataType.ARRAY_BUFFER : http.HttpDataType.STRING
      };
      
      // 应用代理配置
      const proxyManager = ProxyManager.getInstance();
      if (proxyManager.isEnabled()) {
        options.usingProxy = true;
        logger.debug(TAG, `使用代理请求: ${request.url}`);
      }

      if (request.method === RequestMethod.POST) {
        // POST请求需要设置Content-Type
        const header = options.header as Record<string, string>;
        if (!header['Content-Type']) {
          // 检查body是否是JSON格式
          if (request.body && (request.body.trim().startsWith('{') || request.body.trim().startsWith('['))) {
            header['Content-Type'] = 'application/json; charset=utf-8';
          } else {
            // 默认使用表单格式
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
        // 根据charset解码响应
        if (needCustomDecode && response.result instanceof ArrayBuffer) {
          try {
            const decoder = new util.TextDecoder(request.charset);
            const result = decoder.decodeToString(new Uint8Array(response.result));
            logger.debug(TAG, `使用${request.charset}解码响应，长度: ${result.length}`);
            return result;
          } catch (decodeError) {
            logger.warn(TAG, `使用${request.charset}解码失败，尝试UTF-8: ${String(decodeError)}`);
            // 降级到UTF-8
            const decoder = new util.TextDecoder('utf-8');
            return decoder.decodeToString(new Uint8Array(response.result));
          }
        }
        return typeof response.result === 'string' ? response.result : String(response.result);
      }

      // 详细的错误日志
      const responseBody = typeof response.result === 'string' ? response.result : String(response.result);
      const truncatedBody = responseBody.length > 200 ? responseBody.substring(0, 200) + '...' : responseBody;
      logger.warn(TAG, `请求失败: HTTP ${response.responseCode}`);
      logger.debug(TAG, `失败URL: ${request.url}`);
      logger.debug(TAG, `响应内容: ${truncatedBody}`);
      return null;
    } catch (error) {
      // 详细的异常日志
      const errorMsg = this.formatError(error);
      logger.error(TAG, `HTTP请求异常: ${errorMsg}`);
      logger.debug(TAG, `失败URL: ${request.url}`);
      return null;
    }
  }
  
  /**
   * 解析data:协议的URL
   * 格式: data:;base64,{json_data},{extra_data}
   * 这种URL用于传递书籍信息，不需要HTTP请求
   * 
   * 注意：这里的"base64"是书源的命名约定，实际数据可能是JSON而非真正的base64编码
   */
  private parseDataUrl(url: string): string {
    try {
      logger.debug(TAG, `解析data:URL: ${url.substring(0, Math.min(200, url.length))}...`);
      
      // 格式: data:;base64,{json1},{json2}
      // 例如: data:;base64,{"book_id":"xxx","sources":"番茄","tab":"小说","url":""},{"type":"qingtian"}
      // 这里的数据实际上是JSON格式，不是真正的base64编码
      
      // 提取逗号后面的内容（第一个逗号之后的所有内容）
      const firstCommaIndex = url.indexOf(',');
      if (firstCommaIndex > 0) {
        const content = url.substring(firstCommaIndex + 1);
        logger.debug(TAG, `data:URL内容: ${content.substring(0, Math.min(200, content.length))}...`);
        
        // 内容格式: {json1},{json2}
        // 需要提取第一个JSON对象作为主要数据
        if (content.startsWith('{')) {
          // 找到第一个完整的JSON对象
          let braceCount = 0;
          let endIndex = 0;
          for (let i = 0; i < content.length; i++) {
            if (content[i] === '{') braceCount++;
            else if (content[i] === '}') braceCount--;
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
        
        return content;
      }
      
      return url;
    } catch (error) {
      logger.error(TAG, `解析data:URL失败: ${String(error)}`);
      return url;
    }
  }
  
  /**
   * 执行HTTP请求（带详细错误信息）
   */
  private async executeRequestWithError(request: ParsedUrlRequest): Promise<HttpRequestResult> {
    try {
      // 检查URL是否包含未解析的JS规则
      if (request.url.includes('<js>') || request.url.includes('@js:') || request.url.includes('{{')) {
        const errorType = this.analyzeJsError(request.url);
        const result: HttpRequestResult = { response: null, errorType: errorType, errorMessage: 'URL包含未解析的规则' };
        return result;
      }
      
      // 处理data:协议的URL
      if (request.url.startsWith('data:')) {
        const response = this.parseDataUrl(request.url);
        return { response: response } as HttpRequestResult;
      }
      
      // 检查URL是否有效
      if (!request.url.startsWith('http://') && !request.url.startsWith('https://')) {
        const result: HttpRequestResult = { response: null, errorType: SearchErrorType.URL_PARSE_ERROR, errorMessage: '无效的URL' };
        return result;
      }
      
      logger.debug(TAG, `请求: ${request.method} ${request.url}`);
      if (request.body) {
        logger.debug(TAG, `请求Body: ${request.body}`);
      }

      const httpRequest = http.createHttp();
      
      // 如果指定了charset且不是utf-8，使用ArrayBuffer获取原始数据
      const needCustomDecode = request.charset && 
        request.charset.toLowerCase() !== 'utf-8' && 
        request.charset.toLowerCase() !== 'utf8';
      
      const options: http.HttpRequestOptions = {
        method: request.method === RequestMethod.POST ? http.RequestMethod.POST : http.RequestMethod.GET,
        header: this.buildHeaders(request.headers),
        connectTimeout: 10000,
        readTimeout: 10000,
        expectDataType: needCustomDecode ? http.HttpDataType.ARRAY_BUFFER : http.HttpDataType.STRING
      };
      
      // 应用代理配置
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
        // 根据charset解码响应
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
        const successResult: HttpRequestResult = { response: responseStr, errorType: SearchErrorType.NONE, errorMessage: '' };
        return successResult;
      }

      // HTTP错误分类
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
      const httpErrorResult: HttpRequestResult = { response: null, errorType: errorType, errorMessage: `HTTP ${responseCode}` };
      return httpErrorResult;
    } catch (error) {
      const errorMsg = this.formatError(error);
      logger.error(TAG, `HTTP请求异常: ${errorMsg}`);
      logger.debug(TAG, `失败URL: ${request.url}`);
      
      // 分析异常类型
      const errorType = this.analyzeErrorType(errorMsg);
      const exceptionResult: HttpRequestResult = { response: null, errorType: errorType, errorMessage: errorMsg };
      return exceptionResult;
    }
  }
  
  /**
   * 格式化错误信息
   */
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
      logger.debug(TAG, `[书源:${this.source.bookSourceName}] 搜索规则为空或缺少bookList`);
      return results;
    }

    // 性能优化：减少日志输出，仅在小型响应时输出调试信息
    if (html.length < 50000) {
      const htmlSnippet = html.length > 500 ? html.substring(0, 500) + '...' : html;
      logger.debug(TAG, `[书源:${this.source.bookSourceName}] 响应长度=${html.length}, bookList规则=${rule.bookList}`);
      logger.debug(TAG, `[书源:${this.source.bookSourceName}] 响应片段: ${htmlSnippet}`);
    }

    const maxResults = parseOptions?.maxResults && parseOptions.maxResults > 0
      ? Math.floor(parseOptions.maxResults)
      : Number.MAX_SAFE_INTEGER;
    const maxElementScan = parseOptions?.maxElementScan && parseOptions.maxElementScan > 0
      ? Math.floor(parseOptions.maxElementScan)
      : Number.MAX_SAFE_INTEGER;
    const disableItemDomBridge = parseOptions?.disableItemDomBridge === true;

    const analyzer = new LegadoRuleAnalyzer();
    analyzer.setContent(html, baseUrl);

    // 使用异步方法获取元素，支持JS规则
    const bookElements = await analyzer.getElementsAsync(rule.bookList);
    logger.debug(TAG, `[书源:${this.source.bookSourceName}] bookList解析结果: ${bookElements.length} 个元素`);

    const scanLimit = Math.min(bookElements.length, maxElementScan);
    for (let i = 0; i < scanLimit && results.length < maxResults; i++) {
      const itemAnalyzer = new LegadoRuleAnalyzer();
      itemAnalyzer.setContent(bookElements[i], baseUrl, disableItemDomBridge);

      const name = itemAnalyzer.getString(rule.name);
      // 性能优化：仅在第一个元素时输出调试信息
      if (i === 0 && html.length < 50000) {
        const elementSnippet = bookElements[i].length > 200 ? bookElements[i].substring(0, 200) + '...' : bookElements[i];
        logger.debug(TAG, `[书源:${this.source.bookSourceName}] 元素[0]片段: ${elementSnippet}`);
        logger.debug(TAG, `[书源:${this.source.bookSourceName}] 元素[0] name规则=${rule.name}, 解析结果="${name}"`);
      }
      if (!name) {
        continue;
      }

      // 解析bookUrl（使用异步方法支持JS规则）
      const bookUrlRaw = await itemAnalyzer.getStringAsync(rule.bookUrl);
      const bookUrl = bookUrlRaw || baseUrl;
      
      // 始终输出第一个元素的bookUrl解析信息（用于调试）
      if (i === 0) {
        logger.debug(TAG, `搜索结果解析: bookUrl规则=${rule.bookUrl}, 解析结果=${bookUrlRaw}, 最终URL=${bookUrl}`);
        logger.debug(TAG, `元素内容: ${bookElements[i].substring(0, 300)}`);
      }

      const searchBook: LegadoSearchBook = {
        origin: this.source.bookSourceUrl,
        originName: this.source.bookSourceName,
        bookUrl: bookUrl,
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

      // 分段让出事件循环，避免在大量结果时长时间占用主线程
      if ((i + 1) % 20 === 0) {
        await this.yieldToEventLoop();
      }
    }

    if (scanLimit < bookElements.length) {
      logger.debug(TAG, `[书源:${this.source.bookSourceName}] 搜索元素扫描已截断: ${scanLimit}/${bookElements.length}`);
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
    
    const analyzer = new LegadoRuleAnalyzer();
    
    // 处理init规则：先从响应中提取指定字段作为初始数据
    let contentToAnalyze = html;
    if (rule?.init) {
      const initAnalyzer = new LegadoRuleAnalyzer();
      initAnalyzer.setContent(html, baseUrl);
      const initData = initAnalyzer.getString(rule.init);
      if (initData) {
        contentToAnalyze = initData;
        logger.debug(TAG, `应用init规则: ${rule.init}, 提取数据长度: ${initData.length}`);
      }
    }
    
    analyzer.setContent(contentToAnalyze, baseUrl);

    // 性能优化：减少大型内容时的日志输出
    if (contentToAnalyze.length < 50000) {
      logger.debug(TAG, `书籍详情规则 name: ${rule?.name}`);
      logger.debug(TAG, `HTML长度: ${contentToAnalyze.length}, 前500字符: ${contentToAnalyze.substring(0, 500)}`);
    }
    
    // 解析书名，如果规则为空则使用空字符串（后续由调用方用fallback补充）
    const name = rule?.name ? analyzer.getString(rule.name) : '';
    if (contentToAnalyze.length < 50000) {
      logger.debug(TAG, `解析书名结果: "${name}", 规则: ${rule?.name}`);
    }
    
    // 解析tocUrl，这是关键字段，即使name为空也要尝试解析
    const tocUrl = rule?.tocUrl ? analyzer.getString(rule.tocUrl) : '';
    
    // 如果name和tocUrl都为空，说明解析完全失败
    if (!name && !tocUrl) {
      logger.warn(TAG, '无法解析书名和目录URL，详情页解析失败');
      logger.warn(TAG, `详情页规则: name=${rule?.name}, tocUrl=${rule?.tocUrl}`);
      logger.warn(TAG, `响应内容前500字符: ${contentToAnalyze.substring(0, 500)}`);
      return null;
    }
    
    // 性能优化：减少日志输出
    if (contentToAnalyze.length < 50000) {
      logger.debug(TAG, `解析书籍详情: name=${name}, bookUrl=${bookUrl}, tocUrl=${tocUrl}`);
    }
    
    const book: LegadoBook = {
      id: this.generateId(),
      origin: this.source.bookSourceUrl,
      originName: this.source.bookSourceName,
      bookUrl: bookUrl,
      name: name, // 可能为空，调用方需要用fallback补充
      author: rule?.author ? analyzer.getString(rule.author) : '',
      kind: rule?.kind ? analyzer.getString(rule.kind) : undefined,
      intro: rule?.intro ? analyzer.getString(rule.intro) : undefined,
      coverUrl: rule?.coverUrl ? analyzer.getString(rule.coverUrl) : undefined,
      tocUrl: tocUrl || bookUrl, // 如果tocUrl为空，使用bookUrl作为默认值
      latestChapterTitle: rule?.lastChapter ? analyzer.getString(rule.lastChapter) : undefined,
      wordCount: rule?.wordCount ? analyzer.getString(rule.wordCount) : undefined,
      type: this.source.bookSourceType
    };

    return book;
  }

  /**
   * 解析章节列表（带分页支持）
   */
  private parseChapterListWithNext(html: string, baseUrl: string, book: LegadoBook, startIndex: number): ChapterListParseResult {
    const chapters: LegadoChapter[] = [];
    const rule = this.source.ruleToc;
    
    if (!rule || !rule.chapterList) {
      const emptyResult: ChapterListParseResult = { chapters: chapters, nextUrl: null };
      return emptyResult;
    }

    const analyzer = new LegadoRuleAnalyzer();
    analyzer.setContent(html, baseUrl);

    const chapterElements = analyzer.getElements(rule.chapterList);
    
    for (let i = 0; i < chapterElements.length; i++) {
      const itemAnalyzer = new LegadoRuleAnalyzer();
      itemAnalyzer.setContent(chapterElements[i], baseUrl);

      const title = itemAnalyzer.getString(rule.chapterName);
      const url = itemAnalyzer.getString(rule.chapterUrl);
      
      if (!title || !url) {
        continue;
      }

      const chapter: LegadoChapter = {
        id: this.generateId(),
        bookUrl: book.bookUrl,
        url: url,
        title: title,
        index: startIndex + i,
        isVolume: rule.isVolume ? itemAnalyzer.getString(rule.isVolume) === 'true' : false,
        isVip: rule.isVip ? itemAnalyzer.getString(rule.isVip) === 'true' : false,
        isPay: rule.isPay ? itemAnalyzer.getString(rule.isPay) === 'true' : false
      };

      chapters.push(chapter);
    }

    // 解析下一页URL
    // 参考Kotlin原版：只取第一个有效URL，避免多个URL被拼接
    let nextUrl: string | null = null;
    if (rule.nextTocUrl) {
      const nextUrlStr = analyzer.getString(rule.nextTocUrl);
      if (nextUrlStr && nextUrlStr.trim()) {
        // 如果返回多个URL（用换行符分隔），只取第一个
        const urls = nextUrlStr.split('\n').filter((u: string) => u.trim().length > 0);
        if (urls.length > 0) {
          nextUrl = urls[0].trim();
        }
      }
    }

    const result: ChapterListParseResult = { chapters: chapters, nextUrl: nextUrl };
    return result;
  }

  /**
   * 解析章节列表（兼容旧方法）
   */
  private parseChapterList(html: string, baseUrl: string, book: LegadoBook): LegadoChapter[] {
    const parseResult = this.parseChapterListWithNext(html, baseUrl, book, 0);
    const chapters = parseResult.chapters;
    logger.info(TAG, `章节列表: ${chapters.length} 章`);
    return chapters;
  }

  /**
   * 解析正文内容（带分页支持）
   * 参考Kotlin原版Legado的BookContent.analyzeContent实现
   */
  private parseContentWithNext(html: string, baseUrl: string, chapter: LegadoChapter): ContentParseResult {
    const rule = this.source.ruleContent;
    
    if (!rule || !rule.content) {
      const emptyResult: ContentParseResult = { content: '', nextUrl: null };
      return emptyResult;
    }

    const analyzer = new LegadoRuleAnalyzer();
    analyzer.setContent(html, baseUrl);

    // 步骤1: 使用规则提取正文内容
    let content = analyzer.getString(rule.content);
    
    if (!content) {
      const emptyResult: ContentParseResult = { content: '', nextUrl: null };
      return emptyResult;
    }

    // 步骤2: 使用HtmlFormatter格式化内容（参考Kotlin原版）
    // 对于小说正文，不保留img标签，因为Text组件无法渲染图片
    // 如果保留img标签，会被当作文本显示，占用大量宽度
    content = HtmlFormatter.format(content, false);
    
    // 步骤3: 处理HTML实体（参考Kotlin原版的StringEscapeUtils.unescapeHtml4）
    if (content.indexOf('&') > -1) {
      content = HtmlFormatter.unescapeHtml(content);
    }

    // 步骤4: 应用书源内置替换规则
    // 注意：不在这里添加段落缩进，缩进由NovelContentProcessor或TextReaderComponent统一处理
    if (rule.replaceRegex && content) {
      content = this.applyReplaceRules(content, rule.replaceRegex);
    }

    // 步骤5: 应用全局替换规则
    const replaceManager = getNovelReplaceRuleManager();
    content = replaceManager.applyRules(content, ReplaceScope.CONTENT, this.source.bookSourceUrl);

    // 步骤6: 清理广告等无关内容
    content = HtmlFormatter.cleanContent(content);

    // 解析下一页URL
    // 参考Kotlin原版：使用getStringList获取URL列表，只取第一个有效URL
    // 避免多个URL被拼接在一起导致404错误
    let nextUrl: string | null = null;
    if (rule.nextContentUrl) {
      const nextUrlStr = analyzer.getString(rule.nextContentUrl);
      if (nextUrlStr && nextUrlStr.trim()) {
        // 如果返回多个URL（用换行符分隔），只取第一个
        const urls = nextUrlStr.split('\n').filter((u: string) => u.trim().length > 0);
        if (urls.length > 0) {
          nextUrl = urls[0].trim();
        }
      }
    }

    const result: ContentParseResult = { content: content, nextUrl: nextUrl };
    return result;
  }

  /**
   * 解析正文内容（兼容旧方法）
   */
  private parseContent(html: string, baseUrl: string, chapter: LegadoChapter): string {
    const parseResult = this.parseContentWithNext(html, baseUrl, chapter);
    const content = parseResult.content;
    return content;
  }

  /**
   * 应用替换规则
   * 参考Kotlin原版AnalyzeRule.replaceRegex实现
   * 格式: pattern##replacement 或 pattern##replacement### (只替换第一个)
   */
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
