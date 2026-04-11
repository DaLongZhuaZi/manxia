/**
 * 小说书源校验器
 * 批量校验书源可用性
 * 参照Legado实现完整校验流程：搜索、发现、详情、目录、正文
 * 校验失败后自动添加错误分组
 * 
 * 文件路径: entry/src/main/ets/Framework/Novel/NovelSourceValidator.ets
 */

import { logger } from '../../Utils/Logger';
import { LegadoBookSource, LegadoBook, LegadoChapter, LegadoSearchBook, LegadoBookSourceType } from './LegadoSourceTypes';
import { NovelSourceExecutor, SearchErrorType } from './NovelSourceExecutor';
import { getNovelSourceManager, NovelSourceManager } from './NovelSourceManager';
import { AppNotificationManager } from '../Managers/NotificationManager';
import { SettingKeys, SettingsManager } from '../Managers/SettingsManager';
import { BackgroundTaskHelper } from '../Task/BackgroundTaskHelper';
import { common } from '@kit.AbilityKit';

const TAG = 'NovelSourceValidator';
type AudioValidationJsonValue = Object | string | number | boolean | null | undefined;

/**
 * 校验配置
 */
export interface ValidationConfig {
  timeout: number;           // 超时时间（毫秒）
  checkSearch: boolean;      // 校验搜索
  checkDiscovery: boolean;   // 校验发现
  checkInfo: boolean;        // 校验详情
  checkCategory: boolean;    // 校验目录
  checkContent: boolean;     // 校验正文
  keyword: string;           // 搜索关键词
  concurrency: number;       // 校验并发数
}

/**
 * 默认校验配置
 */
export const DEFAULT_VALIDATION_CONFIG: ValidationConfig = {
  timeout: 180000,
  checkSearch: true,
  checkDiscovery: true,
  checkInfo: true,
  checkCategory: true,
  checkContent: true,
  keyword: '我的',
  concurrency: 10
};

/**
 * 校验错误类型 - 参照Legado原版细化分组
 */
export enum ValidationErrorType {
  // 网络相关
  TIMEOUT = 'timeout',                    // 网络超时
  SSL_ERROR = 'ssl_error',                // SSL证书错误
  NETWORK_ERROR = 'network_error',        // 网络连接失败
  HTTP_404 = 'http_404',                  // HTTP 404 页面不存在
  HTTP_403 = 'http_403',                  // HTTP 403 禁止访问
  HTTP_5XX = 'http_5xx',                  // HTTP 5xx 服务器错误
  HTTP_OTHER = 'http_other',              // 其他HTTP错误
  
  // 搜索相关
  SEARCH_EMPTY = 'search_empty',          // 搜索链接规则为空
  SEARCH_FAILED = 'search_failed',        // 搜索失效（解析失败）
  SEARCH_PARSE_ERROR = 'search_parse',    // 搜索解析错误
  
  // 发现相关
  DISCOVERY_EMPTY = 'discovery_empty',    // 发现规则为空
  DISCOVERY_FAILED = 'discovery_failed',  // 发现失效
  
  // 详情/目录/正文
  INFO_FAILED = 'info_failed',            // 详情失效
  TOC_FAILED = 'toc_failed',              // 目录失效
  CONTENT_FAILED = 'content_failed',      // 正文失效
  
  // JS相关
  JS_ERROR = 'js_error',                  // JS脚本错误
  JS_SOURCE_UNDEFINED = 'js_source_undef',// JS中source未定义
  JS_FUNCTION_UNDEFINED = 'js_func_undef',// JS中函数未定义
  
  // URL解析
  URL_PARSE_ERROR = 'url_parse',          // URL解析失败
  
  // 其他
  UNKNOWN = 'unknown'                     // 未知错误
}

/**
 * 特殊分组名称接口
 */
export interface SpecialGroupNames {
  WORKING: string;      // 校验通过的书源
  UNGROUPED: string;    // 没有分组的书源（虚拟分组，不实际存储）
}

/**
 * 特殊分组名称常量
 */
export const SPECIAL_GROUP_NAMES: SpecialGroupNames = {
  WORKING: '✅工作正常',
  UNGROUPED: '📁未分组'
};

/**
 * 校验错误分组名称映射 - 参照Legado原版
 */
export const ERROR_GROUP_NAMES: Record<ValidationErrorType, string> = {
  // 网络相关
  [ValidationErrorType.TIMEOUT]: '⏱️网络超时',
  [ValidationErrorType.SSL_ERROR]: '🔒SSL证书错误',
  [ValidationErrorType.NETWORK_ERROR]: '🌐网络失效',
  [ValidationErrorType.HTTP_404]: '❌404页面不存在',
  [ValidationErrorType.HTTP_403]: '🚫403禁止访问',
  [ValidationErrorType.HTTP_5XX]: '💥服务器错误',
  [ValidationErrorType.HTTP_OTHER]: '⚠️HTTP错误',
  
  // 搜索相关
  [ValidationErrorType.SEARCH_EMPTY]: '搜索链接规则为空',
  [ValidationErrorType.SEARCH_FAILED]: '搜索失效',
  [ValidationErrorType.SEARCH_PARSE_ERROR]: '🔍搜索解析失败',
  
  // 发现相关
  [ValidationErrorType.DISCOVERY_EMPTY]: '发现规则为空',
  [ValidationErrorType.DISCOVERY_FAILED]: '发现失效',
  
  // 详情/目录/正文
  [ValidationErrorType.INFO_FAILED]: '详情失效',
  [ValidationErrorType.TOC_FAILED]: '目录失效',
  [ValidationErrorType.CONTENT_FAILED]: '正文失效',
  
  // JS相关
  [ValidationErrorType.JS_ERROR]: '📜JS脚本错误',
  [ValidationErrorType.JS_SOURCE_UNDEFINED]: '📜JS:source未定义',
  [ValidationErrorType.JS_FUNCTION_UNDEFINED]: '📜JS:函数未定义',
  
  // URL解析
  [ValidationErrorType.URL_PARSE_ERROR]: '🔗URL解析失败',
  
  // 其他
  [ValidationErrorType.UNKNOWN]: '校验失败'
};

/**
 * 校验结果
 */
export interface SourceValidationResult {
  sourceId: string;
  sourceName: string;
  isValid: boolean;
  searchTime?: number;
  bookCount?: number;
  error?: string;
  errorType?: ValidationErrorType;
  errorGroups: string[];  // 错误分组列表
  checkedItems: string[]; // 已检查的项目
}

/**
 * 批量校验进度回调
 */
export type ValidationProgressCallback = (current: number, total: number, result: SourceValidationResult) => void;

/**
 * 批量校验结果
 */
export interface BatchValidationResult {
  total: number;
  valid: number;
  invalid: number;
  results: SourceValidationResult[];
}

/**
 * 书源校验器
 */
export class NovelSourceValidator {
  private static readonly DEFAULT_VALIDATION_CONCURRENCY = 10;
  private static readonly MIN_VALIDATION_CONCURRENCY = 1;
  private static readonly MAX_VALIDATION_CONCURRENCY = 50;
  private static readonly MAX_LIGHT_VALIDATION_CONCURRENCY = 16;
  private static readonly MAX_HEAVY_VALIDATION_CONCURRENCY = 8;
  private static readonly EVENT_LOOP_YIELD_INTERVAL = 2;
  private static readonly VALIDATION_SEARCH_MAX_RESULTS = 1;
  private static readonly VALIDATION_SEARCH_MAX_ELEMENT_SCAN = 300;
  private static readonly NON_FATAL_ERROR_GROUPS: string[] = [
    ERROR_GROUP_NAMES[ValidationErrorType.DISCOVERY_EMPTY],
    ERROR_GROUP_NAMES[ValidationErrorType.DISCOVERY_FAILED],
    ERROR_GROUP_NAMES[ValidationErrorType.TIMEOUT],
    ERROR_GROUP_NAMES[ValidationErrorType.SSL_ERROR],
    ERROR_GROUP_NAMES[ValidationErrorType.NETWORK_ERROR],
    ERROR_GROUP_NAMES[ValidationErrorType.HTTP_403],
    ERROR_GROUP_NAMES[ValidationErrorType.HTTP_5XX],
    ERROR_GROUP_NAMES[ValidationErrorType.HTTP_OTHER]
  ];

  private static instance: NovelSourceValidator | null = null;
  private isValidating: boolean = false;
  private shouldCancel: boolean = false;
  private config: ValidationConfig = this.createDefaultConfig();
  private notificationManager: AppNotificationManager = AppNotificationManager.getInstance();
  private currentValidationTaskId: string = '';
  private lastNotificationTime: number = 0;
  private notificationInterval: number = 1000; // 通知更新间隔（毫秒）
  /** UIAbility 上下文，用于申请后台长时任务 */
  private context: common.UIAbilityContext | null = null;

  private createDefaultConfig(): ValidationConfig {
    const cfg: ValidationConfig = {
      timeout: DEFAULT_VALIDATION_CONFIG.timeout,
      checkSearch: DEFAULT_VALIDATION_CONFIG.checkSearch,
      checkDiscovery: DEFAULT_VALIDATION_CONFIG.checkDiscovery,
      checkInfo: DEFAULT_VALIDATION_CONFIG.checkInfo,
      checkCategory: DEFAULT_VALIDATION_CONFIG.checkCategory,
      checkContent: DEFAULT_VALIDATION_CONFIG.checkContent,
      keyword: DEFAULT_VALIDATION_CONFIG.keyword,
      concurrency: this.getValidationConcurrencyFromSettings()
    };
    return cfg;
  }

  private mergeConfig(config?: Partial<ValidationConfig>): ValidationConfig {
    const settingsConcurrency = this.getValidationConcurrencyFromSettings();
    const result: ValidationConfig = {
      timeout: config?.timeout !== undefined ? config.timeout : this.config.timeout,
      checkSearch: config?.checkSearch !== undefined ? config.checkSearch : this.config.checkSearch,
      checkDiscovery: config?.checkDiscovery !== undefined ? config.checkDiscovery : this.config.checkDiscovery,
      checkInfo: config?.checkInfo !== undefined ? config.checkInfo : this.config.checkInfo,
      checkCategory: config?.checkCategory !== undefined ? config.checkCategory : this.config.checkCategory,
      checkContent: config?.checkContent !== undefined ? config.checkContent : this.config.checkContent,
      keyword: config?.keyword !== undefined ? config.keyword : this.config.keyword,
      concurrency: this.normalizeValidationConcurrency(
        config?.concurrency !== undefined ? config.concurrency : settingsConcurrency
      )
    };
    return result;
  }
  private sourceManager: NovelSourceManager = getNovelSourceManager();

  private constructor() {}

  static getInstance(): NovelSourceValidator {
    if (!NovelSourceValidator.instance) {
      NovelSourceValidator.instance = new NovelSourceValidator();
    }
    return NovelSourceValidator.instance;
  }

  /**
   * 设置 UIAbility 上下文
   * 设置后，批量校验时会自动申请 DATA_TRANSFER 后台长时任务
   * APP 被挂起后网络请求不会被中断
   */
  setContext(context: common.UIAbilityContext): void {
    this.context = context;
  }

  /**
   * 设置校验配置
   */
  setConfig(config: Partial<ValidationConfig>): void {
    if (config.timeout !== undefined) this.config.timeout = config.timeout;
    if (config.checkSearch !== undefined) this.config.checkSearch = config.checkSearch;
    if (config.checkDiscovery !== undefined) this.config.checkDiscovery = config.checkDiscovery;
    if (config.checkInfo !== undefined) this.config.checkInfo = config.checkInfo;
    if (config.checkCategory !== undefined) this.config.checkCategory = config.checkCategory;
    if (config.checkContent !== undefined) this.config.checkContent = config.checkContent;
    if (config.keyword !== undefined) this.config.keyword = config.keyword;
    if (config.concurrency !== undefined) {
      this.config.concurrency = this.normalizeValidationConcurrency(config.concurrency);
    }
  }

  /**
   * 获取校验配置
   */
  getConfig(): ValidationConfig {
    const cfg: ValidationConfig = {
      timeout: this.config.timeout,
      checkSearch: this.config.checkSearch,
      checkDiscovery: this.config.checkDiscovery,
      checkInfo: this.config.checkInfo,
      checkCategory: this.config.checkCategory,
      checkContent: this.config.checkContent,
      keyword: this.config.keyword,
      concurrency: this.config.concurrency
    };
    return cfg;
  }

  /**
   * 校验单个书源（完整流程）
   */
  async validateSource(source: LegadoBookSource, config?: Partial<ValidationConfig>): Promise<SourceValidationResult> {
    const validationConfig = this.mergeConfig(config);
    const result: SourceValidationResult = {
      sourceId: source.bookSourceUrl,
      sourceName: source.bookSourceName,
      isValid: false,
      errorGroups: [],
      checkedItems: []
    };

    const startTime = Date.now();

    try {
      // 使用Promise.race实现超时控制
      await Promise.race([
        this.doValidateSource(source, validationConfig, result),
        this.timeoutPromise(validationConfig.timeout, result)
      ]);
    } catch (error) {
      const errorStr = String(error);
      result.error = errorStr;
      
      // 判断错误类型
      if (errorStr.includes('timeout') || errorStr.includes('超时')) {
        result.errorType = ValidationErrorType.TIMEOUT;
        this.addErrorGroup(result, ValidationErrorType.TIMEOUT);
      } else if (errorStr.includes('script') || errorStr.includes('js') || errorStr.includes('JavaScript')) {
        result.errorType = ValidationErrorType.JS_ERROR;
        this.addErrorGroup(result, ValidationErrorType.JS_ERROR);
      } else if (errorStr.includes('network') || errorStr.includes('网络') || errorStr.includes('connect')) {
        result.errorType = ValidationErrorType.NETWORK_ERROR;
        this.addErrorGroup(result, ValidationErrorType.NETWORK_ERROR);
      } else {
        result.errorType = ValidationErrorType.UNKNOWN;
        this.addErrorGroup(result, ValidationErrorType.UNKNOWN);
      }
      
      logger.warn(TAG, `校验书源失败 [${source.bookSourceName}]: ${result.error}`);
    }

    result.searchTime = Date.now() - startTime;
    result.isValid = !this.hasFatalErrorGroup(result.errorGroups);
    if (result.isValid && result.errorGroups.length > 0) {
      logger.info(
        TAG,
        `校验通过（非致命问题） [${source.bookSourceName}]: ${result.errorGroups.join(',')}`
      );
    }
    
    return result;
  }

  /**
   * 超时Promise
   */
  private timeoutPromise(timeout: number, result: SourceValidationResult): Promise<void> {
    return new Promise((_, reject) => {
      setTimeout(() => {
        this.addErrorGroup(result, ValidationErrorType.TIMEOUT);
        reject(new Error('校验超时'));
      }, timeout);
    });
  }

  /**
   * 添加错误分组
   */
  private addErrorGroup(result: SourceValidationResult, errorType: ValidationErrorType): void {
    const groupName = ERROR_GROUP_NAMES[errorType];
    if (!result.errorGroups.includes(groupName)) {
      result.errorGroups.push(groupName);
    }
  }

  /**
   * 移除错误分组
   */
  private removeErrorGroup(result: SourceValidationResult, errorType: ValidationErrorType): void {
    const groupName = ERROR_GROUP_NAMES[errorType];
    const index = result.errorGroups.indexOf(groupName);
    if (index !== -1) {
      result.errorGroups.splice(index, 1);
    }
  }

  /**
   * 判断错误分组中是否包含致命错误
   */
  private hasFatalErrorGroup(errorGroups: string[]): boolean {
    for (let i = 0; i < errorGroups.length; i++) {
      if (!NovelSourceValidator.NON_FATAL_ERROR_GROUPS.includes(errorGroups[i])) {
        return true;
      }
    }
    return false;
  }

  /**
   * 解析用于发现校验的首个可用URL
   */
  private resolveDiscoveryValidationUrl(source: LegadoBookSource, executor: NovelSourceExecutor): string | null {
    if (!source.exploreUrl) {
      return null;
    }

    const trimmedExploreUrl = source.exploreUrl.trim();
    const lowerExploreUrl = trimmedExploreUrl.toLowerCase();
    if (
      lowerExploreUrl.startsWith('@js:') ||
      lowerExploreUrl.startsWith('@js：') ||
      lowerExploreUrl.startsWith('＠js:') ||
      lowerExploreUrl.startsWith('＠js：') ||
      lowerExploreUrl.startsWith('<js>')
    ) {
      return null;
    }

    const exploreKinds = executor.getExploreKinds();
    for (let i = 0; i < exploreKinds.length; i++) {
      const kindUrl = exploreKinds[i].url ? exploreKinds[i].url.trim() : '';
      if (kindUrl.length > 0 && !this.isDynamicRuleUrl(kindUrl)) {
        return kindUrl;
      }
    }

    const lines = source.exploreUrl.split('\n');
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim();
      if (line.length === 0) {
        continue;
      }
      if (line.startsWith('[') || line.startsWith('{')) {
        continue;
      }
      if (this.isDynamicRuleUrl(line)) {
        continue;
      }

      const parts = line.split('::');
      if (parts.length >= 2) {
        const urlPart = parts.slice(1).join('::').trim();
        if (urlPart.length > 0 && !this.isDynamicRuleUrl(urlPart)) {
          return urlPart;
        }
      }

      if (!this.isDynamicRuleUrl(line)) {
        return line;
      }
    }

    return null;
  }

  /**
   * 解析用于书源校验的搜索关键词
   * 优先使用书源自带 checkKeyWord 的首个候选词，避免固定关键词导致误判
   */
  private resolveValidationKeyword(source: LegadoBookSource, fallbackKeyword: string): string {
    const defaultKeyword = fallbackKeyword.trim();
    const checkKeyword = source.ruleSearch?.checkKeyWord ? source.ruleSearch.checkKeyWord.trim() : '';
    if (checkKeyword.length <= 0) {
      return defaultKeyword;
    }

    const candidates = checkKeyword
      .split(/[|｜,\n，、]/)
      .map((item: string): string => item.trim())
      .filter((item: string): boolean => item.length > 0);
    if (candidates.length <= 0) {
      return defaultKeyword;
    }

    return candidates[0];
  }

  private isDynamicRuleUrl(url: string): boolean {
    const trimmed = url.trim();
    if (trimmed.length <= 0) {
      return false;
    }
    const lower = trimmed.toLowerCase();
    return lower.startsWith('@js:') ||
      lower.startsWith('<js>') ||
      lower.includes('{{') ||
      lower.includes('}}');
  }
  
  /**
   * 将搜索错误类型映射到校验错误类型
   */
  private mapSearchErrorToValidation(searchError: SearchErrorType): ValidationErrorType {
    switch (searchError) {
      case SearchErrorType.TIMEOUT:
        return ValidationErrorType.TIMEOUT;
      case SearchErrorType.SSL_ERROR:
        return ValidationErrorType.SSL_ERROR;
      case SearchErrorType.NETWORK_ERROR:
        return ValidationErrorType.NETWORK_ERROR;
      case SearchErrorType.HTTP_404:
        return ValidationErrorType.HTTP_404;
      case SearchErrorType.HTTP_403:
        return ValidationErrorType.HTTP_403;
      case SearchErrorType.HTTP_5XX:
        return ValidationErrorType.HTTP_5XX;
      case SearchErrorType.HTTP_OTHER:
        return ValidationErrorType.HTTP_OTHER;
      case SearchErrorType.JS_SOURCE_UNDEFINED:
        return ValidationErrorType.JS_SOURCE_UNDEFINED;
      case SearchErrorType.JS_FUNCTION_UNDEFINED:
        return ValidationErrorType.JS_FUNCTION_UNDEFINED;
      case SearchErrorType.JS_ERROR:
        return ValidationErrorType.JS_ERROR;
      case SearchErrorType.URL_PARSE_ERROR:
        return ValidationErrorType.URL_PARSE_ERROR;
      case SearchErrorType.PARSE_ERROR:
        return ValidationErrorType.SEARCH_PARSE_ERROR;
      case SearchErrorType.NONE:
        return ValidationErrorType.SEARCH_FAILED;
      default:
        return ValidationErrorType.SEARCH_FAILED;
    }
  }

  /**
   * 执行完整校验流程
   */
  private async doValidateSource(
    source: LegadoBookSource,
    config: ValidationConfig,
    result: SourceValidationResult
  ): Promise<void> {
    const executor = new NovelSourceExecutor(source);
    const isAudioSource = this.isAudioSource(source);
    const validationKeyword = this.resolveValidationKeyword(source, config.keyword);
    if (validationKeyword !== config.keyword) {
      logger.debug(
        TAG,
        `校验关键词已切换 [${source.bookSourceName}]: ${config.keyword} -> ${validationKeyword}`
      );
    }
    let searchBook: LegadoBook | null = null;
    let exploreBook: LegadoBook | null = null;

    // 检查是否已取消
    if (this.shouldCancel) {
      result.error = '校验已取消';
      return;
    }

    // 1. 校验搜索
    if (config.checkSearch) {
      result.checkedItems.push('搜索');
      if (!source.searchUrl) {
        if (isAudioSource && executor.hasExplore()) {
          logger.debug(TAG, `听书书源无搜索入口，跳过搜索校验并使用发现兜底 [${source.bookSourceName}]`);
        } else {
          this.addErrorGroup(result, ValidationErrorType.SEARCH_EMPTY);
        }
      } else {
        this.removeErrorGroup(result, ValidationErrorType.SEARCH_EMPTY);
        try {
          const searchResult = await executor.searchWithError(validationKeyword, 1, {
            maxResults: NovelSourceValidator.VALIDATION_SEARCH_MAX_RESULTS,
            maxElementScan: NovelSourceValidator.VALIDATION_SEARCH_MAX_ELEMENT_SCAN,
            disableItemDomBridge: true
          });
          result.bookCount = searchResult.books.length;
          
          if (searchResult.books.length === 0) {
            // 根据详细错误类型添加分组
            const errorType = this.mapSearchErrorToValidation(searchResult.errorType);
            this.addErrorGroup(result, errorType);
            logger.debug(TAG, `搜索失败 [${source.bookSourceName}]: ${searchResult.errorType} - ${searchResult.errorMessage}`);
          } else {
            this.removeErrorGroup(result, ValidationErrorType.SEARCH_FAILED);
            this.removeErrorGroup(result, ValidationErrorType.SEARCH_PARSE_ERROR);
            this.removeErrorGroup(result, ValidationErrorType.SEARCH_EMPTY);
            // 使用第一个搜索结果进行后续校验
            const firstResult = searchResult.books[0];
            searchBook = this.searchBookToBook(firstResult);
          }
        } catch (error) {
          this.addErrorGroup(result, ValidationErrorType.SEARCH_FAILED);
          logger.warn(TAG, `搜索校验失败 [${source.bookSourceName}]: ${String(error)}`);
        }
      }
    }

    // 检查是否已取消
    if (this.shouldCancel) {
      result.error = '校验已取消';
      return;
    }

    // 2. 校验发现
    if (config.checkDiscovery && executor.hasExplore()) {
      result.checkedItems.push('发现');
      try {
        // 解析发现URL获取第一个分类
        const discoveryUrl = this.resolveDiscoveryValidationUrl(source, executor);
        if (!discoveryUrl) {
          if (isAudioSource) {
            this.removeErrorGroup(result, ValidationErrorType.DISCOVERY_EMPTY);
            logger.debug(TAG, `听书书源发现校验跳过 [${source.bookSourceName}]: 发现URL为动态脚本或不可直接校验`);
          } else {
            this.addErrorGroup(result, ValidationErrorType.DISCOVERY_EMPTY);
            logger.debug(TAG, `发现校验跳过 [${source.bookSourceName}]: 未找到可用发现URL`);
          }
        } else {
          const exploreResults = await executor.explore(discoveryUrl, 1);
          if (exploreResults.length === 0) {
            this.addErrorGroup(result, ValidationErrorType.DISCOVERY_FAILED);
          } else {
            this.removeErrorGroup(result, ValidationErrorType.DISCOVERY_FAILED);
            this.removeErrorGroup(result, ValidationErrorType.DISCOVERY_EMPTY);
            if (!searchBook) {
              const firstExplore = exploreResults[0];
              exploreBook = this.searchBookToBook(firstExplore);
            }
          }
        }
      } catch (error) {
        if (isAudioSource) {
          logger.warn(TAG, `听书书源发现校验已跳过 [${source.bookSourceName}]: ${String(error)}`);
        } else {
          this.addErrorGroup(result, ValidationErrorType.DISCOVERY_FAILED);
          logger.warn(TAG, `发现校验失败 [${source.bookSourceName}]: ${String(error)}`);
        }
      }
    }

    // 选择用于后续校验的书籍
    const bookToCheck = searchBook || exploreBook;
    if (!bookToCheck) {
      if (!this.hasFatalErrorGroup(result.errorGroups)) {
        this.addErrorGroup(result, ValidationErrorType.SEARCH_FAILED);
      }
      if (!result.error || result.error.trim().length <= 0) {
        result.error = '未获取到可校验书籍';
      }
      logger.warn(TAG, `未获取到可校验书籍 [${source.bookSourceName}]`);
      return;
    }

    // 检查是否已取消
    if (this.shouldCancel) {
      result.error = '校验已取消';
      return;
    }

    // 3. 校验详情
    if (config.checkInfo) {
      result.checkedItems.push('详情');
      try {
        const bookInfo = await executor.getBookInfo(bookToCheck.bookUrl);
        if (!bookInfo) {
          this.addErrorGroup(result, ValidationErrorType.INFO_FAILED);
          logger.warn(TAG, `详情校验失败 [${source.bookSourceName}]: 未解析到详情信息`);
          return; // 详情失败则无法继续校验目录和正文
        }
        bookToCheck.tocUrl = bookInfo.tocUrl || bookToCheck.bookUrl;
        bookToCheck.name = bookInfo.name || bookToCheck.name;
        bookToCheck.author = bookInfo.author || bookToCheck.author;
        this.removeErrorGroup(result, ValidationErrorType.INFO_FAILED);
      } catch (error) {
        this.addErrorGroup(result, ValidationErrorType.INFO_FAILED);
        logger.warn(TAG, `详情校验失败 [${source.bookSourceName}]: ${String(error)}`);
        return; // 详情失败则无法继续校验目录和正文
      }
    }

    // 检查是否已取消
    if (this.shouldCancel) {
      result.error = '校验已取消';
      return;
    }

    // 4. 校验目录
    if (config.checkCategory) {
      result.checkedItems.push('目录');
      try {
        const chapters = await executor.getChapterList(bookToCheck);
        if (chapters.length === 0) {
          this.addErrorGroup(result, ValidationErrorType.TOC_FAILED);
        } else {
          this.removeErrorGroup(result, ValidationErrorType.TOC_FAILED);
          
          // 检查是否已取消
          if (this.shouldCancel) {
            result.error = '校验已取消';
            return;
          }
          
          // 5. 校验正文
          if (config.checkContent && chapters.length > 0) {
            result.checkedItems.push(isAudioSource ? '音频' : '正文');
            try {
              const firstChapter = chapters[0];
              const content = await executor.getContent(firstChapter);
              if (isAudioSource) {
                const resolvedAudioUrl = this.resolveAudioSourceUrl(content, firstChapter.url);
                if (resolvedAudioUrl.length <= 0) {
                  this.addErrorGroup(result, ValidationErrorType.CONTENT_FAILED);
                  logger.warn(TAG, `音频校验失败 [${source.bookSourceName}]: 未解析到可播放音频URL`);
                } else {
                  this.removeErrorGroup(result, ValidationErrorType.CONTENT_FAILED);
                }
              } else {
                if (!content || content.length < 100) {
                  this.addErrorGroup(result, ValidationErrorType.CONTENT_FAILED);
                } else {
                  this.removeErrorGroup(result, ValidationErrorType.CONTENT_FAILED);
                }
              }
            } catch (error) {
              this.addErrorGroup(result, ValidationErrorType.CONTENT_FAILED);
              logger.warn(TAG, `${isAudioSource ? '音频' : '正文'}校验失败 [${source.bookSourceName}]: ${String(error)}`);
            }
          }
        }
      } catch (error) {
        this.addErrorGroup(result, ValidationErrorType.TOC_FAILED);
        logger.warn(TAG, `目录校验失败 [${source.bookSourceName}]: ${String(error)}`);
      }
    }
  }

  private isAudioSource(source: LegadoBookSource): boolean {
    return source.bookSourceType === LegadoBookSourceType.AUDIO;
  }

  private looksLikeAudioUrlCandidate(raw: string): boolean {
    const value = raw.trim();
    if (value.length <= 0) {
      return false;
    }
    if (
      value.startsWith('http://') ||
      value.startsWith('https://') ||
      value.startsWith('file://') ||
      value.startsWith('data:audio/') ||
      value.startsWith('//')
    ) {
      return true;
    }
    if (value.indexOf('://') > 0 && value.indexOf(' ') < 0) {
      return true;
    }
    const lower = value.toLowerCase();
    return lower.indexOf('.mp3') >= 0 ||
      lower.indexOf('.m4a') >= 0 ||
      lower.indexOf('.aac') >= 0 ||
      lower.indexOf('.wav') >= 0 ||
      lower.indexOf('.ogg') >= 0 ||
      lower.indexOf('.flac') >= 0 ||
      lower.indexOf('.m3u8') >= 0;
  }

  private resolveAudioUrlCandidate(raw: string, baseUrl: string): string {
    const trimmed = raw.trim();
    if (trimmed.length <= 0) {
      return '';
    }
    if (
      trimmed.startsWith('http://') ||
      trimmed.startsWith('https://') ||
      trimmed.startsWith('file://') ||
      trimmed.startsWith('data:audio/')
    ) {
      return trimmed;
    }
    const baseMatch = /^(https?:\/\/[^/]+)(\/.*)?$/i.exec(baseUrl);
    if (trimmed.startsWith('//')) {
      const protocol = baseMatch && baseMatch.length > 1 && baseMatch[1].startsWith('http://')
        ? 'http:'
        : 'https:';
      return `${protocol}${trimmed}`;
    }
    if (!baseMatch || baseMatch.length <= 1) {
      return trimmed;
    }
    const host = baseMatch[1];
    const path = baseMatch.length > 2 && baseMatch[2] ? baseMatch[2] : '/';
    if (trimmed.startsWith('/')) {
      return `${host}${trimmed}`;
    }
    const slashIndex = path.lastIndexOf('/');
    const parentPath = slashIndex >= 0 ? path.substring(0, slashIndex + 1) : '/';
    return `${host}${parentPath}${trimmed}`;
  }

  private collectAudioUrlHints(payload: AudioValidationJsonValue, urlHints: string[]): void {
    if (payload === null || payload === undefined) {
      return;
    }
    if (Array.isArray(payload)) {
      const payloadArray = payload as AudioValidationJsonValue[];
      for (let index = 0; index < payloadArray.length; index++) {
        this.collectAudioUrlHints(payloadArray[index], urlHints);
      }
      return;
    }
    if (typeof payload === 'string') {
      const text = payload.trim();
      if (text.length > 0 && this.looksLikeAudioUrlCandidate(text)) {
        urlHints.push(text);
      }
      return;
    }
    if (typeof payload !== 'object') {
      return;
    }

    const record = payload as Record<string, AudioValidationJsonValue>;
    const keys = Object.keys(record);
    for (let index = 0; index < keys.length; index++) {
      const key = keys[index];
      const value = record[key];
      if (typeof value === 'string') {
        const text = value.trim();
        const lowerKey = key.toLowerCase();
        if (text.length > 0) {
          if (
            lowerKey === 'url' ||
            lowerKey === 'audio' ||
            lowerKey === 'audio_url' ||
            lowerKey === 'playurl' ||
            lowerKey === 'play_url' ||
            lowerKey.endsWith('_url') ||
            lowerKey.indexOf('audio') >= 0 ||
            lowerKey.indexOf('play') >= 0
          ) {
            urlHints.push(text);
          } else if (this.looksLikeAudioUrlCandidate(text)) {
            urlHints.push(text);
          }
        }
      }
      this.collectAudioUrlHints(value, urlHints);
    }
  }

  private tryExtractAudioUrlFromJson(rawContent: string, baseUrl: string): string {
    if (!rawContent || rawContent.trim().length <= 0) {
      return '';
    }
    try {
      const parsed = JSON.parse(rawContent) as AudioValidationJsonValue;
      const urlHints: string[] = [];
      this.collectAudioUrlHints(parsed, urlHints);
      for (let index = 0; index < urlHints.length; index++) {
        const resolved = this.resolveAudioUrlCandidate(urlHints[index], baseUrl);
        if (resolved.length > 0) {
          return resolved;
        }
      }
    } catch {
      return '';
    }
    return '';
  }

  private resolveAudioSourceUrl(rawContent: string, baseUrl: string): string {
    const text = rawContent ? rawContent.trim() : '';
    if (text.length <= 0) {
      return '';
    }

    const fromJson = this.tryExtractAudioUrlFromJson(text, baseUrl);
    if (fromJson.length > 0) {
      return fromJson;
    }

    const urlMatch = /(https?:\/\/[^\s"'<>]+)/i.exec(text);
    if (urlMatch && urlMatch.length > 1) {
      return this.resolveAudioUrlCandidate(urlMatch[1], baseUrl);
    }

    const lines = text.split('\n');
    for (let index = 0; index < lines.length; index++) {
      const line = lines[index].trim();
      if (this.looksLikeAudioUrlCandidate(line)) {
        return this.resolveAudioUrlCandidate(line, baseUrl);
      }
    }

    if (this.looksLikeAudioUrlCandidate(text)) {
      return this.resolveAudioUrlCandidate(text, baseUrl);
    }

    return '';
  }

  /**
   * 简单校验（仅搜索）- 兼容旧接口
   */
  async validateSourceSimple(source: LegadoBookSource, testKeyword: string = '斗罗'): Promise<SourceValidationResult> {
    return this.validateSource(source, {
      checkSearch: true,
      checkDiscovery: false,
      checkInfo: false,
      checkCategory: false,
      checkContent: false,
      keyword: testKeyword,
      concurrency: this.getValidationConcurrencyFromSettings()
    });
  }

  /**
   * 批量校验书源
   * @param sourceIds 要校验的书源ID列表
   * @param config 校验配置（可选）
   * @param onProgress 进度回调
   * @param autoUpdateGroups 是否自动更新书源分组（默认true）
   * @param showNotification 是否显示通知（默认true）
   */
  async validateSources(
    sourceIds: string[],
    config?: Partial<ValidationConfig>,
    onProgress?: ValidationProgressCallback,
    autoUpdateGroups: boolean = true,
    showNotification: boolean = true
  ): Promise<BatchValidationResult> {
    if (this.isValidating) {
      throw new Error('正在进行校验，请等待完成');
    }

    this.isValidating = true;
    this.shouldCancel = false;
    
    // 生成唯一的校验任务ID
    this.currentValidationTaskId = `validation_${Date.now()}`;
    this.lastNotificationTime = 0;

    const validationConfig = this.mergeConfig(config);
    const resultsByIndex: Array<SourceValidationResult | undefined> = new Array(sourceIds.length);
    let valid = 0;
    let invalid = 0;
    let completedCount = 0;
    let nextIndex = 0;
    const workerCount = this.calculateRuntimeConcurrency(validationConfig, sourceIds.length);

    // 有上下文时申请 DATA_TRANSFER 后台长时任务
    if (this.context) {
      await BackgroundTaskHelper.startDataTransferTask(this.context, this.currentValidationTaskId);
    }

    // 发送开始通知
    if (showNotification) {
      await this.sendProgressNotification(0, sourceIds.length, 0, 0);
    }

    try {
      const worker = async (): Promise<void> => {
        while (true) {
          if (this.shouldCancel) {
            return;
          }

          const currentIndex = nextIndex;
          nextIndex++;
          if (currentIndex >= sourceIds.length) {
            return;
          }

          const result = await this.validateSourceById(
            sourceIds[currentIndex],
            validationConfig,
            autoUpdateGroups
          );
          resultsByIndex[currentIndex] = result;
          completedCount++;

          if (result.isValid) {
            valid++;
          } else {
            invalid++;
          }

          onProgress?.(completedCount, sourceIds.length, result);

          if (showNotification) {
            await this.sendProgressNotification(completedCount, sourceIds.length, valid, invalid);
          }

          // 主动让出事件循环，避免并发校验导致主线程长期饥饿
          if (completedCount % NovelSourceValidator.EVENT_LOOP_YIELD_INTERVAL === 0) {
            await this.delay(0);
          }
        }
      };

      const workers: Promise<void>[] = [];
      for (let i = 0; i < workerCount; i++) {
        workers.push(worker());
      }
      await Promise.all(workers);

      if (this.shouldCancel) {
        logger.info(TAG, '校验已取消');
        if (showNotification) {
          await this.notificationManager.sendValidationCancelledNotification(
            this.currentValidationTaskId,
            completedCount,
            sourceIds.length
          );
        }
      }
    } finally {
      this.isValidating = false;
      // 校验完成（无论正常结束还是异常）后停止后台长时任务
      if (this.context) {
        await BackgroundTaskHelper.stopDataTransferTask(this.context, this.currentValidationTaskId);
      }
    }

    const results: SourceValidationResult[] = [];
    for (const item of resultsByIndex) {
      if (item !== undefined) {
        results.push(item);
      }
    }

    const batchResult: BatchValidationResult = {
      total: sourceIds.length,
      valid,
      invalid,
      results
    };

    // 发送完成通知（如果没有被取消）
    if (showNotification && !this.shouldCancel) {
      await this.notificationManager.sendValidationCompleteNotification(
        this.currentValidationTaskId,
        sourceIds.length,
        valid,
        invalid
      );
    }

    logger.info(
      TAG,
      `批量校验完成: ${valid}/${sourceIds.length} 有效, 并发数(请求/运行): ${validationConfig.concurrency}/${workerCount}`
    );
    return batchResult;
  }

  private async validateSourceById(
    sourceId: string,
    config: ValidationConfig,
    autoUpdateGroups: boolean
  ): Promise<SourceValidationResult> {
    const source = this.sourceManager.getSource(sourceId);
    if (!source) {
      return {
        sourceId,
        sourceName: '未知书源',
        isValid: false,
        error: '书源不存在',
        errorGroups: ['书源不存在'],
        checkedItems: []
      };
    }

    const result = await this.validateSource(source, config);

    if (result.isValid) {
      if (autoUpdateGroups) {
        if (result.errorGroups.length === 0) {
          await this.removeAllErrorGroups(source);
        } else {
          await this.updateSourceWarningGroups(source, result.errorGroups);
        }
      }
    } else {
      if (autoUpdateGroups) {
        await this.updateSourceErrorGroups(source, result.errorGroups);
      }
    }

    if (result.searchTime !== undefined) {
      await this.sourceManager.updateSourceRespondTime(sourceId, result.searchTime);
    }

    return result;
  }
  
  /**
   * 发送进度通知（限制更新频率）
   */
  private async sendProgressNotification(
    current: number,
    total: number,
    validCount: number,
    invalidCount: number
  ): Promise<void> {
    const now = Date.now();
    // 限制通知更新频率，避免过于频繁
    if (now - this.lastNotificationTime < this.notificationInterval && current !== 0 && current !== total) {
      return;
    }
    this.lastNotificationTime = now;
    
    await this.notificationManager.sendValidationProgressNotification(
      this.currentValidationTaskId,
      current,
      total,
      validCount,
      invalidCount
    );
  }

  /**
   * 更新书源的错误分组
   */
  private async updateSourceErrorGroups(source: LegadoBookSource, errorGroups: string[]): Promise<void> {
    try {
      // 获取当前分组
      const currentGroups = source.bookSourceGroup ? source.bookSourceGroup.split(',').map(g => g.trim()) : [];
      
      // 移除所有已知的错误分组和"工作正常"分组
      const knownErrorGroups = Object.values(ERROR_GROUP_NAMES);
      const cleanedGroups = currentGroups.filter(g => 
        !knownErrorGroups.includes(g) && g !== SPECIAL_GROUP_NAMES.WORKING
      );
      
      // 添加新的错误分组
      const newGroups: string[] = [];
      for (let i = 0; i < cleanedGroups.length; i++) {
        newGroups.push(cleanedGroups[i]);
      }
      for (let i = 0; i < errorGroups.length; i++) {
        newGroups.push(errorGroups[i]);
      }
      const newGroupStr = newGroups.join(',');
      
      // 更新书源分组
      await this.sourceManager.updateSourceGroup(source.bookSourceUrl, newGroupStr);
      logger.debug(TAG, `更新书源分组 [${source.bookSourceName}]: ${newGroupStr}`);
    } catch (error) {
      logger.warn(TAG, `更新书源分组失败 [${source.bookSourceName}]: ${String(error)}`);
    }
  }

  /**
   * 移除书源的所有错误分组，并添加"工作正常"分组
   */
  private async removeAllErrorGroups(source: LegadoBookSource): Promise<void> {
    try {
      const currentGroups = source.bookSourceGroup ? source.bookSourceGroup.split(',').map(g => g.trim()) : [];
      const knownErrorGroups = Object.values(ERROR_GROUP_NAMES);
      // 移除所有错误分组
      let cleanedGroups = currentGroups.filter(g => !knownErrorGroups.includes(g));
      
      // 添加"工作正常"分组（如果不存在）
      if (!cleanedGroups.includes(SPECIAL_GROUP_NAMES.WORKING)) {
        cleanedGroups.push(SPECIAL_GROUP_NAMES.WORKING);
      }
      
      const newGroupStr = cleanedGroups.filter(g => g).join(',');
      await this.sourceManager.updateSourceGroup(source.bookSourceUrl, newGroupStr);
      logger.debug(TAG, `清除书源错误分组并标记工作正常 [${source.bookSourceName}]: ${newGroupStr}`);
    } catch (error) {
      logger.warn(TAG, `清除书源错误分组失败 [${source.bookSourceName}]: ${String(error)}`);
    }
  }

  /**
   * 获取所有错误分组名称
   */
  static getErrorGroupNames(): string[] {
    return Object.values(ERROR_GROUP_NAMES);
  }

  /**
   * 校验所有书源
   */
  async validateAllSources(
    config?: Partial<ValidationConfig>,
    onProgress?: ValidationProgressCallback,
    autoUpdateGroups: boolean = true,
    showNotification: boolean = true
  ): Promise<BatchValidationResult> {
    const allSources = this.sourceManager.getAllSources();
    const sourceIds = allSources.map(s => s.id);
    return this.validateSources(sourceIds, config, onProgress, autoUpdateGroups, showNotification);
  }
  
  /**
   * 获取当前校验任务的通知ID
   * 用于外部取消通知
   */
  getValidationNotificationId(): number {
    if (!this.currentValidationTaskId) {
      return 0;
    }
    // 使用与NotificationManager相同的哈希算法
    let hash = 0;
    for (let i = 0; i < this.currentValidationTaskId.length; i++) {
      const char = this.currentValidationTaskId.charCodeAt(i);
      hash = ((hash << 5) - hash) + char;
      hash = hash & hash;
    }
    return Math.abs(hash) % 100000 + 1000;
  }

  /**
   * 取消校验
   */
  cancelValidation(): void {
    if (this.isValidating) {
      this.shouldCancel = true;
      logger.info(TAG, '请求取消校验');
    }
  }

  /**
   * 是否正在校验
   */
  isRunning(): boolean {
    return this.isValidating;
  }

  /**
   * 延迟
   */
  private delay(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  /**
   * 更新书源的非致命问题分组
   */
  private async updateSourceWarningGroups(source: LegadoBookSource, warningGroups: string[]): Promise<void> {
    try {
      await this.updateSourceErrorGroups(source, warningGroups);
      logger.debug(TAG, `更新书源非致命问题分组 [${source.bookSourceName}]: ${warningGroups.join(',')}`);
    } catch (error) {
      logger.warn(TAG, `更新书源非致命问题分组失败 [${source.bookSourceName}]: ${String(error)}`);
    }
  }

  private normalizeValidationConcurrency(value: number): number {
    if (!Number.isFinite(value)) {
      return NovelSourceValidator.DEFAULT_VALIDATION_CONCURRENCY;
    }
    const roundedValue = Math.floor(value);
    return Math.max(
      NovelSourceValidator.MIN_VALIDATION_CONCURRENCY,
      Math.min(NovelSourceValidator.MAX_VALIDATION_CONCURRENCY, roundedValue)
    );
  }

  private calculateRuntimeConcurrency(config: ValidationConfig, totalSources: number): number {
    const requested = this.normalizeValidationConcurrency(config.concurrency);
    const hasHeavySteps = config.checkInfo || config.checkCategory || config.checkContent;
    const runtimeCap = hasHeavySteps
      ? NovelSourceValidator.MAX_HEAVY_VALIDATION_CONCURRENCY
      : NovelSourceValidator.MAX_LIGHT_VALIDATION_CONCURRENCY;

    const capped = Math.min(requested, runtimeCap);
    const safeTotal = totalSources > 0 ? totalSources : 1;
    return Math.max(
      NovelSourceValidator.MIN_VALIDATION_CONCURRENCY,
      Math.min(capped, safeTotal)
    );
  }

  private getValidationConcurrencyFromSettings(): number {
    const configured = SettingsManager.getInstance().getNumber(
      SettingKeys.NOVEL_SOURCE_VALIDATION_CONCURRENCY,
      NovelSourceValidator.DEFAULT_VALIDATION_CONCURRENCY
    );
    return this.normalizeValidationConcurrency(configured);
  }

  /**
   * 将LegadoSearchBook转换为LegadoBook
   */
  private searchBookToBook(searchBook: LegadoSearchBook): LegadoBook {
    const book: LegadoBook = {
      id: `${searchBook.origin}_${searchBook.bookUrl}`,
      origin: searchBook.origin,
      originName: searchBook.originName,
      bookUrl: searchBook.bookUrl,
      name: searchBook.name,
      author: searchBook.author,
      kind: searchBook.kind,
      intro: searchBook.intro,
      coverUrl: searchBook.coverUrl,
      latestChapterTitle: searchBook.latestChapterTitle,
      wordCount: searchBook.wordCount,
      type: searchBook.type,
      variable: searchBook.variable,
      infoHtml: searchBook.infoHtml
    };
    return book;
  }
}

/**
 * 获取书源校验器实例
 */
export function getNovelSourceValidator(): NovelSourceValidator {
  return NovelSourceValidator.getInstance();
}
