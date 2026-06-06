import { SafeUtils } from '../../Utils/SafeUtils';
// 文件路径: src/main/ets/Framework/WebView/MangaSourceEngine.ets
/**
 * 漫画图源引擎主控制器
 * 整合操作引擎、选择器引擎和配置解析器，提供统一的接口
 */

import { webview } from '@kit.ArkWeb';
import { logger } from '../../Utils/Logger';
import { MangaSourceActionEngine, ActionContext } from './MangaSourceActionEngine';
import { MangaSourceSelectorEngine, SelectorContext } from './MangaSourceSelectorEngine';
import { MangaSourceConfigParser, ParseResult, WorkflowContext, ConfigSummaryResult, ConfigSummarySettings } from './MangaSourceConfigParser';
import { DataManager, UserSettingsDatabaseRecord } from '../Data/DataManager';
import { FilterParams } from './TabConfig';
import {
  MangaSourceConfig,
  Action,
  ActionResult,
  ActionType,
  WaitCondition,
  MangaInfo,
  ChapterInfo,
  PageInfo,
  PageRequestHeader,
  MangaSourceError,
  MangaSourceErrorCode,
  AntiCrawlerConfig,
  TaskDefinition,
  TaskResult,
  DirectSearchResult,
  DirectSearchResultType,
  APIRequestAction
} from './MangaSourceTypes';
import { TaskExecutor, TaskExecutorConfig } from './TaskExecutor';

const TAG = 'MangaSourceEngine';



/**
 * 引擎执行结果
 */
export interface EngineResult<T = Object> {
  /** 执行是否成功 */
  success: boolean;
  /** 结果数据 */
  data?: T;
  /** 错误信息 */
  error?: string;
  /** 执行时长 */
  duration: number;
  /** 执行的操作数量 */
  actionCount: number;
}

/**
 * 合并获取详情和章节的结果数据
 */
export interface MangaDetailWithChapters {
  /** 漫画详情 */
  detail: MangaInfo;
  /** 章节列表 */
  chapters: ChapterInfo[];
}

/**
 * 引擎配置
 */
export interface EngineConfig {
  /** WebView控制器 */
  webViewController: webview.WebviewController;
  /** 反爬虫配置 */
  antiCrawlerConfig: AntiCrawlerConfig;
  /** 调试模式 */
  debug: boolean;
  /** 默认超时时间 */
  timeout: number;
  /** 是否区分大小写 */
  caseSensitive: boolean;
  /** 图源ID（可选，用于从数据库加载源级设置） */
  sourceId?: number;
}

/**
 * 搜索结果
 */
export interface SearchResult {
  /** 漫画列表 */
  mangas: MangaInfo[];
  /** 总数量 */
  total: number;
  /** 当前页 */
  page: number;
  /** 是否有下一页 */
  hasNext: boolean;
}

/**
 * 测试结果
 */
export interface TestResults {
  config: Record<string, Object>;
  tests: Record<string, Object>;
}

/**
 * 导航测试结果
 */
export interface NavigationTestResult {
  success: boolean;
  duration: number;
  error?: string;
}

/**
 * 测试结果记录接口
 */
interface TestResultsRecord extends Record<string, Object> {
  config: Record<string, Object>;
  tests: Record<string, Object>;
}

/**
 * 配置摘要记录接口
 */
interface ConfigSummaryRecord extends Record<string, Object> {
  name: string;
  version: string;
  baseUrl: string;
  author: string;
  description: string;
  workflowCount: number;
  workflows: Array<Object>;
  settings: ConfigSummarySettings;
}

/** [优化] 预取页面缓存条目 */
interface PrefetchCacheEntry {
  data: PageInfo[];
  timestamp: number;
}

/** [优化] 源设置缓存条目 */
interface SourceSettingsCacheEntry {
  variables: Record<string, string>;
  timestamp: number;
}

/**
 * 漫画图源引擎
 */
export class MangaSourceEngine {
  // [优化] 跨页面预取缓存：MangaDetailPage 预取页面列表，MangaReaderPage 直接使用
  private static prefetchedPageLists: Map<string, PrefetchCacheEntry> = new Map();
  private static readonly PREFETCH_CACHE_TTL_MS: number = 120000; // 2 分钟

  /**
   * [优化] 存储预取的页面列表（供 MangaDetailPage 调用）
   */
  static setPrefetchedPages(sourceId: number, chapterId: string, pages: PageInfo[]): void {
    const key = `${sourceId}_${chapterId}`;
    const entry: PrefetchCacheEntry = { data: pages, timestamp: Date.now() };
    MangaSourceEngine.prefetchedPageLists.set(key, entry);
    logger.info(TAG, `[预取] 已缓存页面列表: key=${key}, pages=${pages.length}`);
  }

  /**
   * [优化] 获取预取的页面列表（供 MangaReaderPage 调用）
   */
  static getPrefetchedPages(sourceId: number, chapterId: string): PageInfo[] | null {
    const key = `${sourceId}_${chapterId}`;
    const cached = MangaSourceEngine.prefetchedPageLists.get(key);
    if (cached && (Date.now() - cached.timestamp) < MangaSourceEngine.PREFETCH_CACHE_TTL_MS) {
      MangaSourceEngine.prefetchedPageLists.delete(key); // 一次性消费
      logger.info(TAG, `[预取] 命中预取缓存: key=${key}, pages=${cached.data.length}`);
      return cached.data;
    }
    return null;
  }

  private actionEngine: MangaSourceActionEngine;
  private selectorEngine: MangaSourceSelectorEngine;
  private configParser: MangaSourceConfigParser;
  private config: MangaSourceConfig | undefined;
  private rawConfigJson: string = '';
  private engineConfig: EngineConfig;
  private dataManager: DataManager = DataManager.getInstance();
  private lastChapterAccessDenied: boolean = false;
  // [修复] 存储当前会话的 Token，登录成功后立即可用
  private currentToken: string | undefined = undefined;
  // 任务执行器
  private taskExecutor: TaskExecutor | null = null;
  // [优化] 缓存 populateSourceSettings 结果，避免重复 DB 查询和 JSON.parse
  private sourceSettingsCache: Map<string, SourceSettingsCacheEntry> = new Map();
  private static readonly SOURCE_SETTINGS_CACHE_TTL_MS: number = 60000; // 60s TTL
  // [优化] 缓存 rawConfigJson 解析结果，避免重复 JSON.parse
  private parsedConfigCache: Record<string, Object> | null = null;

  constructor(engineConfig: EngineConfig) {
    this.engineConfig = engineConfig;
    this.actionEngine = new MangaSourceActionEngine(engineConfig.webViewController, engineConfig.antiCrawlerConfig);
    this.selectorEngine = new MangaSourceSelectorEngine();
    this.configParser = new MangaSourceConfigParser();
    
    // 初始化任务执行器
    const taskConfig: TaskExecutorConfig = {
      webViewController: engineConfig.webViewController,
      antiCrawlerConfig: engineConfig.antiCrawlerConfig,
      debug: engineConfig.debug,
      defaultTimeout: engineConfig.timeout
    };
    this.taskExecutor = new TaskExecutor(taskConfig);
  }

  /**
   * 更新WebView控制器（修复：页面返回后WebView失效）
   */
  updateWebViewController(controller: webview.WebviewController): void {
    this.engineConfig.webViewController = controller;
    this.actionEngine.updateWebViewController(controller);
    logger.debug(TAG, 'WebView控制器已更新');
  }

  /**
   * 设置CF验证需要用户交互时的回调
   */
  setOnNeedCfVerify(callback: () => void): void {
    this.actionEngine.setOnNeedCfVerify(callback);
  }

  /**
   * 加载配置文件
   * @param jsonContent JSON配置内容
   * @param skipInitialize 是否跳过初始化工作流（默认false）
   */
  async loadConfig(jsonContent: string, skipInitialize: boolean = false): Promise<ParseResult> {
    logger.info(TAG, `加载漫画图源配置, skipInitialize=${skipInitialize}`);
    logger.debug(TAG, `接收到的JSON长度: ${jsonContent.length}`);
    
    // 保存原始JSON用于提取API配置
    this.rawConfigJson = jsonContent;
    // [优化] 配置变更时清除缓存
    this.clearEngineCache();

    const parseResult = this.configParser.parseConfig(jsonContent);
    
    if (parseResult.success && parseResult.config) {
      this.config = parseResult.config;
      const summary = this.configParser.getConfigSummary(this.config);
      logger.info(TAG, `配置加载成功: ${summary.name} v${summary.version}`);
      logger.debug(TAG, `工作流数量: ${summary.workflowCount}, 工作流列表: ${summary.workflows.join(', ')}`);
      
      if (parseResult.warnings && parseResult.warnings.length > 0) {
        logger.warn(TAG, `配置警告: ${parseResult.warnings.join('; ')}`);
      }

      // 自动执行初始化工作流（用于登录/Cookie预热），除非明确跳过
      if (!skipInitialize) {
        try {
          await this.runInitializeWorkflowIfPresent();
        } catch (e) {
          logger.warn(TAG, `初始化工作流执行失败: ${e instanceof Error ? e.message : String(e)}`);
        }
      } else {
        logger.info(TAG, '跳过初始化工作流');
      }
    } else {
      logger.error(TAG, `配置加载失败: ${parseResult.error || '未知错误'}`);
      if (parseResult.warnings && parseResult.warnings.length > 0) {
        logger.warn(TAG, `配置警告: ${parseResult.warnings.join('; ')}`);
      }
    }

    return parseResult;
  }

  /**
   * 搜索漫画
   */
  async searchManga(keyword: string, page: number = 1): Promise<EngineResult<SearchResult>> {
    if (!this.config) {
      logger.error(TAG, '配置未加载，无法执行搜索');
      throw new MangaSourceError(
        MangaSourceErrorCode.CONFIG_NOT_LOADED,
        '配置未加载'
      );
    }

    const startTime = Date.now();
    logger.info(TAG, `开始搜索漫画: 关键词="${keyword}", 页码=${page}`);

    try {
      // 构建搜索操作序列
      logger.debug(TAG, '构建搜索操作序列');
      const actions = this.configParser.buildSearchActions(this.config, keyword);
      logger.debug(TAG, `搜索操作序列包含 ${actions.length} 个操作`);
      
      // 执行操作序列
      const context = this.createActionContext();
      await this.populateSourceSettings(context);
      context.variables['useCookies'] = 'false';
      context.variables['searchKeyword'] = keyword;
      context.variables['keyword'] = keyword; // 兼容性别名
      context.variables['query'] = keyword; // 用于URL模板
      context.variables['page'] = page.toString();
      // 根据源设置计算offset
      const pageSize: number = Number(context.variables['pageSize'] || '30');
      context.variables['offset'] = ((page - 1) * pageSize).toString();
      logger.debug(TAG, `执行上下文变量: ${JSON.stringify(context.variables)}`);
      
      let searchResults: MangaInfo[] = [];
      
      for (let i = 0; i < actions.length; i++) {
        const action = actions[i];
        logger.debug(TAG, `执行操作 ${i + 1}/${actions.length}: ${action.type}`);
        
        const result = await this.actionEngine.executeAction(action, context);
        
        logger.debug(TAG, `操作 ${i + 1} 结果: success=${result.success}, hasData=${!!result.data}`);
        
        if (!result.success) {
          logger.error(TAG, `操作 ${i + 1} 失败: ${result.error}`);
          throw new MangaSourceError(
            MangaSourceErrorCode.ACTION_FAILED,
            `搜索操作失败: ${result.error}`
          );
        }

        // 如果是提取操作或API请求，收集结果
        if ((action.type === 'extract' || action.type === 'api') && result.data) {
          const resultData = result.data as Record<string, Object> | Array<Record<string, Object>>;
          const extractedData = Array.isArray(resultData) ? resultData : [resultData];
          searchResults = extractedData.map((item: Record<string, Object>) => this.transformToMangaInfo(item));
          logger.debug(TAG, `提取到 ${searchResults.length} 条漫画数据`);
        }
        
        // 支持 script 操作直接返回漫画列表
        if (action.type === 'script' && result.data) {
          let scriptData = String(result.data).trim();
          // WebView runJavaScript 会对返回值进行双重序列化，需要先解析一次
          if (scriptData.startsWith('"') && scriptData.endsWith('"')) {
            try {
              scriptData = SafeUtils.parseStr(scriptData) as string;
            } catch (e) {
              logger.debug(TAG, `解除双重序列化失败: ${e}`);
            }
          }
          // 处理直接返回数组的情况: [...]
          if (scriptData.startsWith('[')) {
            try {
              const parsed = SafeUtils.parseArr(scriptData) as Array<Record<string, Object>>;
              if (Array.isArray(parsed) && parsed.length > 0 && parsed[0] && (parsed[0] as Record<string, Object>)['id'] !== undefined) {
                searchResults = parsed.map((item: Record<string, Object>) => this.transformToMangaInfo(item));
                logger.debug(TAG, `从脚本结果提取到 ${searchResults.length} 条漫画数据`);
              }
            } catch (e) {
              logger.debug(TAG, `脚本结果不是漫画列表格式: ${e}`);
            }
          }
          // 处理返回对象包含 mangas 数组的情况: {"mangas":[...]}
          else if (scriptData.startsWith('{')) {
            try {
              const parsed = SafeUtils.parseObj(scriptData) as Record<string, Object>;
              const mangasArray = parsed['mangas'] as Array<Record<string, Object>> | undefined;
              if (Array.isArray(mangasArray) && mangasArray.length > 0) {
                searchResults = mangasArray.map((item: Record<string, Object>) => this.transformToMangaInfo(item));
                logger.debug(TAG, `从脚本结果(mangas字段)提取到 ${searchResults.length} 条漫画数据`);
              }
            } catch (e) {
              logger.debug(TAG, `脚本结果对象解析失败: ${e}`);
            }
          }
        }
      }

      const duration = Date.now() - startTime;
      
      logger.info(TAG, `搜索完成，找到 ${searchResults.length} 个结果，耗时 ${duration}ms`);

      return {
        success: true,
        data: {
          mangas: searchResults,
          total: searchResults.length,
          page,
          hasNext: searchResults.length >= 20 // 简化判断
        },
        duration,
        actionCount: actions.length
      };

    } catch (error) {
      const duration = Date.now() - startTime;
      const errorMessage = error instanceof Error ? error.message : String(error);
      const errorStack = error instanceof Error ? error.stack : '';
      
      logger.error(TAG, `搜索失败: ${errorMessage}`);
      logger.debug(TAG, `错误堆栈: ${errorStack}`);
      
      return {
        success: false,
        error: errorMessage,
        duration,
        actionCount: 0
      };
    }
  }

  // ==================== 搜索增强方法 ====================

  /**
   * 直达搜索 - 根据搜索类型和原始查询执行直达访问
   * 不进行URL规范化，直接使用原始输入值
   * @param searchType 搜索类型ID（对应searchConfig中的type.id）
   * @param query 原始查询值
   * @returns 直达搜索结果
   */
  async directSearch(searchType: string, query: string): Promise<EngineResult<DirectSearchResult>> {
    if (!this.config) {
      logger.error(TAG, '配置未加载，无法执行直达搜索');
      throw new MangaSourceError(
        MangaSourceErrorCode.CONFIG_NOT_LOADED,
        '配置未加载'
      );
    }

    const startTime = Date.now();
    logger.info(TAG, `开始直达搜索: 类型="${searchType}", 查询="${query}"`);

    try {
      // 构建直达搜索操作序列
      const actions = this.configParser.buildDirectSearchActions(this.config, searchType, query);
      logger.debug(TAG, `直达搜索操作序列包含 ${actions.length} 个操作`);

      // 执行操作序列
      const context = this.createActionContext();
      await this.populateSourceSettings(context);
      context.variables['useCookies'] = 'true';
      // 直达搜索专用变量（不进行URL规范化）
      context.variables['searchType'] = searchType;
      context.variables['query'] = query;
      context.variables['rawQuery'] = query;

      let resultData: DirectSearchResult = {
        type: 'detail' as DirectSearchResultType,
        manga: undefined,
        mangas: []
      };

      for (let i = 0; i < actions.length; i++) {
        const action = actions[i];
        logger.debug(TAG, `执行直达搜索操作 ${i + 1}/${actions.length}: ${action.type}`);

        const result = await this.actionEngine.executeAction(action, context);

        if (!result.success) {
          logger.error(TAG, `直达搜索操作 ${i + 1} 失败: ${result.error}`);
          throw new MangaSourceError(
            MangaSourceErrorCode.ACTION_FAILED,
            `直达搜索操作失败: ${result.error}`
          );
        }

        // 处理脚本返回的结果
        if (action.type === 'script' && result.data) {
          let scriptData = String(result.data).trim();
          // 解除双重序列化
          if (scriptData.startsWith('"') && scriptData.endsWith('"')) {
            try {
              scriptData = SafeUtils.parseStr(scriptData) as string;
            } catch (e) {
              logger.debug(TAG, `解除双重序列化失败: ${e}`);
            }
          }

          if (scriptData.startsWith('{')) {
            try {
              const parsed = SafeUtils.parseObj(scriptData) as Record<string, Object>;
              
              // 解析结果类型
              const resultType = String(parsed['type'] || 'detail') as DirectSearchResultType;
              resultData.type = resultType;

              // 解析单个作品
              if (parsed['manga']) {
                resultData.manga = this.transformToMangaInfo(parsed['manga'] as Record<string, Object>);
              }

              // 解析作品列表
              if (parsed['mangas'] && Array.isArray(parsed['mangas'])) {
                resultData.mangas = (parsed['mangas'] as Array<Record<string, Object>>)
                  .map((item: Record<string, Object>) => this.transformToMangaInfo(item));
              }

              // 解析重定向URL
              if (parsed['redirectUrl']) {
                resultData.redirectUrl = String(parsed['redirectUrl']);
              }

              // 解析分页信息
              if (parsed['hasNext'] !== undefined) {
                resultData.hasNext = Boolean(parsed['hasNext']);
              }
              if (parsed['total'] !== undefined) {
                resultData.total = Number(parsed['total']);
              }

              logger.debug(TAG, `直达搜索结果: type=${resultData.type}, manga=${!!resultData.manga}, mangas=${resultData.mangas?.length || 0}`);
            } catch (e) {
              logger.error(TAG, `解析直达搜索结果失败: ${e}`);
            }
          }
        }
      }

      const duration = Date.now() - startTime;
      logger.info(TAG, `直达搜索完成，耗时 ${duration}ms`);

      return {
        success: true,
        data: resultData,
        duration,
        actionCount: actions.length
      };

    } catch (error) {
      const duration = Date.now() - startTime;
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `直达搜索失败: ${errorMessage}`);

      return {
        success: false,
        error: errorMessage,
        duration,
        actionCount: 0
      };
    }
  }

  /**
   * 检查是否支持直达搜索
   */
  supportsDirectSearch(): boolean {
    if (!this.config || !this.config.workflows) {
      return false;
    }
    // 使用configParser检查是否有directSearch工作流
    try {
      const workflow = this.configParser.getWorkflow(this.config, 'directSearch');
      return !!workflow;
    } catch (e) {
      return false;
    }
  }

  /**
   * 通过ID搜索/获取单个作品
   * @param illustId 作品ID
   * @returns 搜索结果（单个作品包装为列表）
   */
  async searchById(illustId: string): Promise<EngineResult<SearchResult>> {
    if (!this.config) {
      logger.error(TAG, '配置未加载，无法执行ID搜索');
      throw new MangaSourceError(
        MangaSourceErrorCode.CONFIG_NOT_LOADED,
        '配置未加载'
      );
    }

    const startTime = Date.now();
    logger.info(TAG, `开始ID直达搜索: illustId="${illustId}"`);

    try {
      // 检查是否有专用工作流
      const hasSearchById = this.configParser.hasWorkflow(this.config, 'searchById');

      if (hasSearchById) {
        // 使用专用工作流
        const actions = this.configParser.buildSearchByIdActions(this.config, illustId);
        if (actions.length === 0) {
          logger.warn(TAG, 'searchById工作流返回空操作序列');
        }

        const context = this.createActionContext();
        await this.populateSourceSettings(context);
        context.variables['illustId'] = illustId;
        context.variables['mangaId'] = illustId;

        let results: MangaInfo[] = [];
        for (let i = 0; i < actions.length; i++) {
          const action = actions[i];
          const result = await this.actionEngine.executeAction(action, context);
          if (!result.success && !action.optional) {
            throw new MangaSourceError(MangaSourceErrorCode.ACTION_FAILED, result.error || '操作失败');
          }
          if ((action.type === 'extract' || action.type === 'api' || action.type === 'script') && result.data) {
            results = this.extractMangaResults(result.data);
          }
        }

        const duration = Date.now() - startTime;
        logger.info(TAG, `ID搜索完成，找到 ${results.length} 个结果，耗时 ${duration}ms`);

        return {
          success: true,
          data: {
            mangas: results,
            total: results.length,
            page: 1,
            hasNext: false
          },
          duration,
          actionCount: actions.length
        };
      } else {
        // 降级：使用 getMangaDetail 获取详情，包装为搜索结果
        logger.info(TAG, '图源未实现searchById，使用getMangaDetail降级');
        const detailResult = await this.getMangaDetail(illustId);
        const duration = Date.now() - startTime;

        if (detailResult.success && detailResult.data) {
          const manga: MangaInfo = detailResult.data;
          return {
            success: true,
            data: {
              mangas: [manga],
              total: 1,
              page: 1,
              hasNext: false
            },
            duration,
            actionCount: 1
          };
        }

        return {
          success: false,
          error: detailResult.error || 'ID搜索失败',
          duration,
          actionCount: 0
        };
      }
    } catch (error) {
      const duration = Date.now() - startTime;
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `ID搜索失败: ${errorMessage}`);
      return {
        success: false,
        error: errorMessage,
        duration,
        actionCount: 0
      };
    }
  }

  /**
   * 通过作者ID搜索作品列表
   * @param authorId 作者ID
   * @param page 页码
   * @returns 搜索结果
   */
  async searchByAuthor(authorId: string, page: number = 1): Promise<EngineResult<SearchResult>> {
    if (!this.config) {
      logger.error(TAG, '配置未加载，无法执行作者搜索');
      throw new MangaSourceError(
        MangaSourceErrorCode.CONFIG_NOT_LOADED,
        '配置未加载'
      );
    }

    const startTime = Date.now();
    logger.info(TAG, `开始作者搜索: authorId="${authorId}", page=${page}`);

    // 检查是否支持作者搜索
    const hasSearchByAuthor = this.configParser.hasWorkflow(this.config, 'searchByAuthor');
    if (!hasSearchByAuthor) {
      logger.warn(TAG, '图源未实现searchByAuthor工作流');
      return {
        success: false,
        error: '该图源不支持作者ID搜索',
        duration: Date.now() - startTime,
        actionCount: 0
      };
    }

    try {
      const actions = this.configParser.buildSearchByAuthorActions(this.config, authorId);
      const context = this.createActionContext();
      await this.populateSourceSettings(context);
      context.variables['authorId'] = authorId;
      context.variables['userId'] = authorId;
      context.variables['page'] = page.toString();
      const pageSize: number = Number(context.variables['pageSize'] || '30');
      context.variables['offset'] = ((page - 1) * pageSize).toString();

      let results: MangaInfo[] = [];
      for (let i = 0; i < actions.length; i++) {
        const action = actions[i];
        const result = await this.actionEngine.executeAction(action, context);
        if (!result.success && !action.optional) {
          throw new MangaSourceError(MangaSourceErrorCode.ACTION_FAILED, result.error || '操作失败');
        }
        if ((action.type === 'extract' || action.type === 'api' || action.type === 'script') && result.data) {
          results = this.extractMangaResults(result.data);
        }
      }

      const duration = Date.now() - startTime;
      logger.info(TAG, `作者搜索完成，找到 ${results.length} 个结果，耗时 ${duration}ms`);

      return {
        success: true,
        data: {
          mangas: results,
          total: results.length,
          page: page,
          hasNext: results.length >= 20
        },
        duration,
        actionCount: actions.length
      };
    } catch (error) {
      const duration = Date.now() - startTime;
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `作者搜索失败: ${errorMessage}`);
      return {
        success: false,
        error: errorMessage,
        duration,
        actionCount: 0
      };
    }
  }

  /**
   * 通过系列ID搜索作品列表
   * @param seriesId 系列ID
   * @param page 页码
   * @returns 搜索结果
   */
  async searchBySeries(seriesId: string, page: number = 1): Promise<EngineResult<SearchResult>> {
    if (!this.config) {
      logger.error(TAG, '配置未加载，无法执行系列搜索');
      throw new MangaSourceError(
        MangaSourceErrorCode.CONFIG_NOT_LOADED,
        '配置未加载'
      );
    }

    const startTime = Date.now();
    logger.info(TAG, `开始系列搜索: seriesId="${seriesId}", page=${page}`);

    // 检查是否支持系列搜索
    const hasSearchBySeries = this.configParser.hasWorkflow(this.config, 'searchBySeries');
    if (!hasSearchBySeries) {
      logger.warn(TAG, '图源未实现searchBySeries工作流');
      return {
        success: false,
        error: '该图源不支持系列ID搜索',
        duration: Date.now() - startTime,
        actionCount: 0
      };
    }

    try {
      const actions = this.configParser.buildSearchBySeriesActions(this.config, seriesId);
      const context = this.createActionContext();
      await this.populateSourceSettings(context);
      context.variables['seriesId'] = seriesId;
      context.variables['page'] = page.toString();
      const pageSize: number = Number(context.variables['pageSize'] || '30');
      context.variables['offset'] = ((page - 1) * pageSize).toString();

      let results: MangaInfo[] = [];
      for (let i = 0; i < actions.length; i++) {
        const action = actions[i];
        const result = await this.actionEngine.executeAction(action, context);
        if (!result.success && !action.optional) {
          throw new MangaSourceError(MangaSourceErrorCode.ACTION_FAILED, result.error || '操作失败');
        }
        if ((action.type === 'extract' || action.type === 'api' || action.type === 'script') && result.data) {
          results = this.extractMangaResults(result.data);
        }
      }

      const duration = Date.now() - startTime;
      logger.info(TAG, `系列搜索完成，找到 ${results.length} 个结果，耗时 ${duration}ms`);

      return {
        success: true,
        data: {
          mangas: results,
          total: results.length,
          page: page,
          hasNext: results.length >= 20
        },
        duration,
        actionCount: actions.length
      };
    } catch (error) {
      const duration = Date.now() - startTime;
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `系列搜索失败: ${errorMessage}`);
      return {
        success: false,
        error: errorMessage,
        duration,
        actionCount: 0
      };
    }
  }

  /**
   * 通过标签/分类搜索作品列表
   * @param tagId 标签ID或标签名称
   * @param page 页码
   * @returns 搜索结果
   */
  async searchByTag(tagId: string, page: number = 1): Promise<EngineResult<SearchResult>> {
    if (!this.config) {
      logger.error(TAG, '配置未加载，无法执行标签搜索');
      throw new MangaSourceError(
        MangaSourceErrorCode.CONFIG_NOT_LOADED,
        '配置未加载'
      );
    }

    const startTime = Date.now();
    logger.info(TAG, `开始标签搜索: tagId="${tagId}", page=${page}`);

    // 检查是否支持标签搜索
    const hasSearchByTag = this.configParser.hasWorkflow(this.config, 'searchByTag');
    if (!hasSearchByTag) {
      logger.warn(TAG, '图源未实现searchByTag工作流');
      return {
        success: false,
        error: '该图源不支持标签搜索',
        duration: Date.now() - startTime,
        actionCount: 0
      };
    }

    try {
      const actions = this.configParser.buildSearchByTagActions(this.config, tagId);
      const context = this.createActionContext();
      await this.populateSourceSettings(context);
      context.variables['tagId'] = tagId;
      context.variables['tag'] = tagId;
      context.variables['category'] = tagId;
      context.variables['genre'] = tagId;
      context.variables['page'] = page.toString();
      const pageSize: number = Number(context.variables['pageSize'] || '30');
      context.variables['offset'] = ((page - 1) * pageSize).toString();

      let results: MangaInfo[] = [];
      for (let i = 0; i < actions.length; i++) {
        const action = actions[i];
        const result = await this.actionEngine.executeAction(action, context);
        if (!result.success && !action.optional) {
          throw new MangaSourceError(MangaSourceErrorCode.ACTION_FAILED, result.error || '操作失败');
        }
        if ((action.type === 'extract' || action.type === 'api' || action.type === 'script') && result.data) {
          results = this.extractMangaResults(result.data);
        }
      }

      const duration = Date.now() - startTime;
      logger.info(TAG, `标签搜索完成，找到 ${results.length} 个结果，耗时 ${duration}ms`);

      return {
        success: true,
        data: {
          mangas: results,
          total: results.length,
          page: page,
          hasNext: results.length >= 20
        },
        duration,
        actionCount: actions.length
      };
    } catch (error) {
      const duration = Date.now() - startTime;
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `标签搜索失败: ${errorMessage}`);
      return {
        success: false,
        error: errorMessage,
        duration,
        actionCount: 0
      };
    }
  }

  /**
   * 检查图源是否支持指定能力
   * @param capability 能力名称（工作流名称）
   * @returns 是否支持
   */
  supportsCapability(capability: string): boolean {
    if (!this.config) return false;
    return this.configParser.hasWorkflow(this.config, capability);
  }

  /**
   * 从结果数据中提取漫画列表（辅助方法）
   */
  private extractMangaResults(data: Object): MangaInfo[] {
    // 处理数组类型
    if (Array.isArray(data)) {
      return (data as Array<Record<string, Object>>).map((item: Record<string, Object>) => this.transformToMangaInfo(item));
    }

    // 处理字符串类型（可能是JSON）
    if (typeof data === 'string') {
      let scriptData = (data as string).trim();
      // 解除双重序列化
      if (scriptData.startsWith('"') && scriptData.endsWith('"')) {
        try {
          scriptData = SafeUtils.parseStr(scriptData) as string;
        } catch (e) {
          logger.debug(TAG, `解除双重序列化失败: ${e}`);
        }
      }

      // 尝试解析为数组
      if (scriptData.startsWith('[')) {
        try {
          const parsed = SafeUtils.parseArr(scriptData) as Array<Record<string, Object>>;
          if (Array.isArray(parsed)) {
            return parsed.map((item: Record<string, Object>) => this.transformToMangaInfo(item));
          }
        } catch (e) {
          logger.debug(TAG, `JSON数组解析失败: ${e}`);
        }
      }

      // 尝试解析为包含mangas字段的对象
      if (scriptData.startsWith('{')) {
        try {
          const parsed = SafeUtils.parseObj(scriptData) as Record<string, Object>;
          const mangasArray = parsed['mangas'] as Array<Record<string, Object>> | undefined;
          if (Array.isArray(mangasArray)) {
            return mangasArray.map((item: Record<string, Object>) => this.transformToMangaInfo(item));
          }
        } catch (e) {
          logger.debug(TAG, `JSON对象解析失败: ${e}`);
        }
      }
    }

    return [];
  }

  /**
   * 解析脚本返回的数据，兼容普通 JSON 与双重字符串化 JSON
   */
  private parseStructuredScriptResult(scriptData: string): string | Object | undefined {
    const trimmedData = scriptData.trim();
    if (!trimmedData) {
      logger.debug(TAG, 'script返回空字符串，跳过JSON解析');
      return undefined;
    }

    const looksLikeJsonObject = trimmedData.startsWith('{') && trimmedData.endsWith('}');
    const looksLikeJsonArray = trimmedData.startsWith('[') && trimmedData.endsWith(']');
    const looksLikeJsonString = trimmedData.startsWith('"') && trimmedData.endsWith('"');
    if (!looksLikeJsonObject && !looksLikeJsonArray && !looksLikeJsonString) {
      logger.debug(TAG, `script返回原始字符串，跳过JSON解析: ${trimmedData.substring(0, 120)}`);
      return trimmedData;
    }

    try {
      let parsedResult: string | Object = SafeUtils.parseObj(trimmedData) as string | Object;
      logger.debug(TAG, `第一次JSON解析完成，类型: ${typeof parsedResult}`);

      if (typeof parsedResult === 'string') {
        const nestedData = parsedResult.trim();
        const nestedLooksLikeJsonObject = nestedData.startsWith('{') && nestedData.endsWith('}');
        const nestedLooksLikeJsonArray = nestedData.startsWith('[') && nestedData.endsWith(']');
        if (nestedLooksLikeJsonObject || nestedLooksLikeJsonArray) {
          logger.debug(TAG, '检测到双重字符串化，进行第二次解析');
          parsedResult = SafeUtils.parseObj(parsedResult) as Object;
          logger.debug(TAG, `第二次JSON解析完成，类型: ${typeof parsedResult}`);
        }
      }

      return parsedResult;
    } catch (e) {
      logger.error(TAG, `script返回数据JSON解析失败: ${e}`);
      return undefined;
    }
  }

  /**
   * 判断脚本结果是否为漫画详情对象
   */
  private isMangaDetailPayload(data: Object): boolean {
    if (Array.isArray(data) || typeof data !== 'object') {
      return false;
    }

    const item = data as Record<string, Object>;
    const itemKeys = Object.keys(item);
    const detailKeys: string[] = [
      'id',
      'title',
      'url',
      'cover',
      'author',
      'description',
      'status',
      'genre',
      'genres',
      'updated'
    ];

    for (let i = 0; i < detailKeys.length; i++) {
      if (itemKeys.includes(detailKeys[i])) {
        return true;
      }
    }

    return false;
  }

  /**
   * 从脚本结果中提取漫画详情
   */
  private extractMangaDetailFromScriptResult(scriptResult: string | Object): MangaInfo | undefined {
    let parsedResult: string | Object | undefined = scriptResult;
    if (typeof scriptResult === 'string') {
      parsedResult = this.parseStructuredScriptResult(scriptResult);
    }

    if (!parsedResult || typeof parsedResult === 'string') {
      return undefined;
    }

    if (!this.isMangaDetailPayload(parsedResult)) {
      logger.debug(TAG, 'script返回数据不是漫画详情对象，跳过详情转换');
      return undefined;
    }

    logger.debug(TAG, `script返回数据已解析: ${JSON.stringify(parsedResult).substring(0, 200)}`);
    return this.transformToMangaInfo(parsedResult);
  }

  /**
   * 从脚本结果中提取章节列表
   */
  private extractChapterListFromScriptResult(scriptResult: string | Object): ChapterInfo[] {
    let parsedResult: string | Object | undefined = scriptResult;
    if (typeof scriptResult === 'string') {
      parsedResult = this.parseStructuredScriptResult(scriptResult);
    }

    if (!parsedResult || typeof parsedResult === 'string' || !Array.isArray(parsedResult)) {
      return [];
    }

    return (parsedResult as Array<Record<string, Object>>).map((item: Record<string, Object>) =>
      this.transformToChapterInfo(item)
    );
  }

  /**
   * 获取热门漫画
   */
  async getPopular(page: number = 1): Promise<EngineResult<SearchResult>> {
    if (!this.config) {
      logger.error(TAG, '配置未加载，无法获取热门漫画');
      throw new MangaSourceError(
        MangaSourceErrorCode.CONFIG_NOT_LOADED,
        '配置未加载'
      );
    }

    const startTime = Date.now();
    logger.info(TAG, `开始获取热门漫画: 页码=${page}`);

    try {
      // 构建热门操作序列
      logger.debug(TAG, '构建热门漫画操作序列');
      const actions = this.configParser.buildPopularActions(this.config);
      logger.debug(TAG, `热门操作序列包含 ${actions.length} 个操作`);
      
      // 执行操作序列
      const context = this.createActionContext();
      await this.populateSourceSettings(context);
      context.variables['useCookies'] = 'false';
      context.variables['page'] = page.toString();
      const pageSize: number = Number(context.variables['pageSize'] || '30');
      context.variables['offset'] = ((page - 1) * pageSize).toString();
      logger.debug(TAG, `执行上下文变量: ${JSON.stringify(context.variables)}`);
      
      let results: MangaInfo[] = [];
      
      for (let i = 0; i < actions.length; i++) {
        const action = actions[i];
        logger.debug(TAG, `执行操作 ${i + 1}/${actions.length}: ${action.type}`);
        
        const result = await this.actionEngine.executeAction(action, context);
        
        logger.debug(TAG, `操作 ${i + 1} 结果: success=${result.success}, hasData=${!!result.data}`);
        
        if (!result.success) {
          logger.error(TAG, `操作 ${i + 1} 失败: ${result.error}`);
          throw new MangaSourceError(
            MangaSourceErrorCode.ACTION_FAILED,
            `热门操作失败: ${result.error}`
          );
        }

        if ((action.type === 'extract' || action.type === 'api') && result.data) {
          const resultData = result.data as Record<string, Object> | Array<Record<string, Object>>;
          const extractedData = Array.isArray(resultData) ? resultData : [resultData];
          results = extractedData.map((item: Record<string, Object>) => this.transformToMangaInfo(item));
          logger.debug(TAG, `提取到 ${results.length} 条漫画数据`);
        }
        
        // 支持 script 操作直接返回漫画列表（用于复杂提取场景）
        if (action.type === 'script' && result.data) {
          let scriptData = String(result.data).trim();
          // WebView runJavaScript 会对返回值进行双重序列化，需要先解析一次
          if (scriptData.startsWith('"') && scriptData.endsWith('"')) {
            try {
              scriptData = SafeUtils.parseStr(scriptData) as string;
              logger.debug(TAG, `脚本数据解除双重序列化后首字符: '${scriptData.charAt(0)}'`);
            } catch (e) {
              logger.debug(TAG, `解除双重序列化失败: ${e}`);
            }
          }
          // 情况1: 脚本返回数组格式 [{id, title, ...}, ...]
          if (scriptData.startsWith('[')) {
            try {
              const parsed = SafeUtils.parseArr(scriptData) as Array<Record<string, Object>>;
              logger.debug(TAG, `JSON解析成功，数组长度: ${parsed.length}`);
              // 验证是否是漫画列表格式（包含 id 字段）
              if (Array.isArray(parsed) && parsed.length > 0 && parsed[0] && (parsed[0] as Record<string, Object>)['id'] !== undefined) {
                results = parsed.map((item: Record<string, Object>) => this.transformToMangaInfo(item));
                logger.debug(TAG, `从脚本结果提取到 ${results.length} 条漫画数据(数组格式)`);
              }
            } catch (e) {
              logger.debug(TAG, `脚本结果JSON解析失败: ${e}`);
            }
          }
          // 情况2: 脚本返回对象格式 {mangas: [...], hasNextPage: bool}
          else if (scriptData.startsWith('{')) {
            try {
              const parsed = SafeUtils.parseObj(scriptData) as Record<string, Object>;
              const mangasArray = parsed['mangas'] as Array<Record<string, Object>> | undefined;
              if (mangasArray && Array.isArray(mangasArray) && mangasArray.length > 0) {
                results = mangasArray.map((item: Record<string, Object>) => this.transformToMangaInfo(item));
                logger.debug(TAG, `从脚本结果提取到 ${results.length} 条漫画数据(对象格式)`);
              }
            } catch (e) {
              logger.debug(TAG, `脚本结果不是漫画对象格式: ${e}`);
            }
          }
        }
      }

      const duration = Date.now() - startTime;
      
      logger.info(TAG, `获取热门漫画完成，找到 ${results.length} 个结果，耗时 ${duration}ms`);

      return {
        success: true,
        data: {
          mangas: results,
          total: results.length,
          page,
          hasNext: results.length >= 20
        },
        duration,
        actionCount: actions.length
      };

    } catch (error) {
      const duration = Date.now() - startTime;
      const errorMessage = error instanceof Error ? error.message : String(error);
      const errorStack = error instanceof Error ? error.stack : '';
      
      logger.error(TAG, `获取热门漫画失败: ${errorMessage}`);
      logger.debug(TAG, `错误堆栈: ${errorStack}`);
      
      return {
        success: false,
        error: errorMessage,
        duration,
        actionCount: 0
      };
    }
  }

  /**
   * 获取最新更新
   */
  async getLatest(page: number = 1): Promise<EngineResult<SearchResult>> {
    if (!this.config) {
      logger.error(TAG, '配置未加载，无法获取最新更新');
      throw new MangaSourceError(
        MangaSourceErrorCode.CONFIG_NOT_LOADED,
        '配置未加载'
      );
    }

    const startTime = Date.now();
    logger.info(TAG, `开始获取最新更新: 页码=${page}`);

    try {
      // 构建最新更新操作序列
      logger.debug(TAG, '构建最新更新操作序列');
      const actions = this.configParser.buildLatestActions(this.config);
      logger.debug(TAG, `最新更新操作序列包含 ${actions.length} 个操作`);
      
      // 执行操作序列
      const context = this.createActionContext();
      await this.populateSourceSettings(context);
      context.variables['useCookies'] = 'false';
      context.variables['page'] = page.toString();
      const pageSize: number = Number(context.variables['pageSize'] || '21');
      context.variables['offset'] = ((page - 1) * pageSize).toString();
      logger.debug(TAG, `执行上下文变量: ${JSON.stringify(context.variables)}`);
      
      let results: MangaInfo[] = [];
      
      for (let i = 0; i < actions.length; i++) {
        const action = actions[i];
        logger.debug(TAG, `执行操作 ${i + 1}/${actions.length}: ${action.type}`);
        
        const result = await this.actionEngine.executeAction(action, context);
        
        logger.debug(TAG, `操作 ${i + 1} 结果: success=${result.success}, hasData=${!!result.data}`);
        
        if (!result.success) {
          logger.error(TAG, `操作 ${i + 1} 失败: ${result.error}`);
          throw new MangaSourceError(
            MangaSourceErrorCode.ACTION_FAILED,
            `最新更新操作失败: ${result.error}`
          );
        }

        if ((action.type === 'extract' || action.type === 'api') && result.data) {
          const resultData = result.data as Record<string, Object> | Array<Record<string, Object>>;
          const extractedData = Array.isArray(resultData) ? resultData : [resultData];
          results = extractedData.map((item: Record<string, Object>) => this.transformToMangaInfo(item));
          logger.debug(TAG, `提取到 ${results.length} 条漫画数据`);
        }
        
        // 支持 script 操作直接返回漫画列表
        if (action.type === 'script' && result.data) {
          let scriptData = String(result.data).trim();
          // WebView runJavaScript 会对返回值进行双重序列化，需要先解析一次
          if (scriptData.startsWith('"') && scriptData.endsWith('"')) {
            try {
              scriptData = SafeUtils.parseStr(scriptData) as string;
            } catch (e) {
              logger.debug(TAG, `解除双重序列化失败: ${e}`);
            }
          }
          // 情况1: 脚本返回数组格式 [{id, title, ...}, ...]
          if (scriptData.startsWith('[')) {
            try {
              const parsed = SafeUtils.parseArr(scriptData) as Array<Record<string, Object>>;
              if (Array.isArray(parsed) && parsed.length > 0 && parsed[0] && (parsed[0] as Record<string, Object>)['id'] !== undefined) {
                results = parsed.map((item: Record<string, Object>) => this.transformToMangaInfo(item));
                logger.debug(TAG, `从脚本结果提取到 ${results.length} 条漫画数据(数组格式)`);
              }
            } catch (e) {
              logger.debug(TAG, `脚本结果不是漫画列表格式: ${e}`);
            }
          }
          // 情况2: 脚本返回对象格式 {mangas: [...], hasNextPage: bool}
          else if (scriptData.startsWith('{')) {
            try {
              const parsed = SafeUtils.parseObj(scriptData) as Record<string, Object>;
              const mangasArray = parsed['mangas'] as Array<Record<string, Object>> | undefined;
              if (mangasArray && Array.isArray(mangasArray) && mangasArray.length > 0) {
                results = mangasArray.map((item: Record<string, Object>) => this.transformToMangaInfo(item));
                logger.debug(TAG, `从脚本结果提取到 ${results.length} 条漫画数据(对象格式)`);
              }
            } catch (e) {
              logger.debug(TAG, `脚本结果不是漫画对象格式: ${e}`);
            }
          }
        }
      }

      const duration = Date.now() - startTime;
      
      logger.info(TAG, `获取最新更新完成，找到 ${results.length} 个结果，耗时 ${duration}ms`);

      return {
        success: true,
        data: {
          mangas: results,
          total: results.length,
          page,
          hasNext: results.length >= 20
        },
        duration,
        actionCount: actions.length
      };

    } catch (error) {
      const duration = Date.now() - startTime;
      const errorMessage = error instanceof Error ? error.message : String(error);
      const errorStack = error instanceof Error ? error.stack : '';
      
      logger.error(TAG, `获取最新更新失败: ${errorMessage}`);
      logger.debug(TAG, `错误堆栈: ${errorStack}`);
      
      return {
        success: false,
        error: errorMessage,
        duration,
        actionCount: 0
      };
    }
  }

  /**
   * 筛选漫画
   * @param page 页码
   * @param filterOrdering 排序方式（旧版参数）
   * @param filterRegion 地区筛选（旧版参数）
   * @param filterTheme 题材筛选（旧版参数）
   * @param dynamicFilters 动态筛选参数Map（新版参数，支持任意筛选组）
   */
  async getFiltered(page: number = 1, filterOrdering?: string, filterRegion?: string, filterTheme?: string, dynamicFilters?: Map<string, string>): Promise<EngineResult<SearchResult>> {
    if (!this.config) {
      logger.error(TAG, '配置未加载，无法筛选漫画');
      throw new MangaSourceError(
        MangaSourceErrorCode.CONFIG_NOT_LOADED,
        '配置未加载'
      );
    }

    const startTime = Date.now();
    logger.info(TAG, `开始筛选漫画: 页码=${page}`);

    try {
      // 构建筛选操作序列
      logger.debug(TAG, '构建筛选操作序列');
      const actions = this.configParser.buildFilterActions(this.config);
      logger.debug(TAG, `筛选操作序列包含 ${actions.length} 个操作`);
      
      // 执行操作序列
      const context = this.createActionContext();
      await this.populateSourceSettings(context);
      context.variables['useCookies'] = 'false';
      context.variables['page'] = page.toString();
      context.variables['offset'] = ((page - 1) * 30).toString();
      
      // 设置筛选参数 - 支持多种参数名称
      // 通用参数名
      // [修复] 使用 ?? 运算符，空字符串不会被替换（空字符串表示"全部"，引擎会跳过该参数）
      context.variables['filterOrdering'] = filterOrdering ?? '-datetime_updated';
      context.variables['filterRegion'] = filterRegion ?? '';
      context.variables['filterTheme'] = filterTheme ?? '';
      
      // 从原始JSON配置中读取默认值和filters配置
      let defaultSort: string = 'dd';  // PicaComic 默认排序
      let defaultCategory: string = '';  // 默认为空（全部分类）
      let filtersConfig: Record<string, Object> | undefined = undefined;
      
      if (this.rawConfigJson) {
        try {
          const rawConfig = SafeUtils.parseObj(this.rawConfigJson) as Record<string, Object>;
          
          // 读取 filters 配置，用于变量映射
          filtersConfig = rawConfig['filters'] as Record<string, Object> | undefined;
          
          const workflows = rawConfig['workflows'] as Record<string, Object> | undefined;
          if (workflows) {
            const filterWorkflow = workflows['filter'] as Record<string, Object> | undefined;
            if (filterWorkflow) {
              const defaults = filterWorkflow['defaults'] as Record<string, string> | undefined;
              if (defaults) {
                if (defaults['sort']) {
                  defaultSort = defaults['sort'];
                }
                if (defaults['category'] !== undefined) {
                  defaultCategory = defaults['category'];
                }
              }
            }
          }
        } catch (e) {
          logger.warn(TAG, `解析筛选默认值失败: ${e}`);
        }
      }
      
      // 设置 sort 参数：只有当 filterOrdering 是 PicaComic 的有效值时才使用
      // PicaComic 有效的 sort 值: UA, CA, da, dd, ld, vd
      const validPicaSortValues = ['UA', 'CA', 'da', 'dd', 'ld', 'vd'];
      const isValidSort = filterOrdering && validPicaSortValues.indexOf(filterOrdering) >= 0;
      if (isValidSort) {
        context.variables['sort'] = filterOrdering;
      } else {
        context.variables['sort'] = defaultSort;
      }
      
      // 设置 category 参数：优先使用传入的 filterTheme，否则使用配置的默认值
      if (filterTheme && filterTheme !== 'all') {
        context.variables['category'] = filterTheme;
      } else {
        context.variables['category'] = defaultCategory;
      }
      
      // 设置额外的变量名映射，支持不同图源使用的变量名
      // 紳士漫畫 使用 filter_category 和 filter_tag
      context.variables['filter_category'] = filterTheme || '';
      context.variables['filter_tag'] = '';  // 标签筛选暂时为空，后续可扩展
      
      // 包子漫画 使用 type, region, state, filter
      // [修复] 包子漫画需要 'all'，但拷贝漫画需要空字符串，这里保持原样
      context.variables['type'] = filterTheme ?? 'all';
      context.variables['region'] = filterRegion ?? 'all';
      context.variables['state'] = 'all';  // 进度筛选
      context.variables['filter'] = '*';   // 标题开头筛选
      
      // 从filters配置读取所有key，并设置对应的默认值
      if (filtersConfig) {
        const filterKeys = Object.keys(filtersConfig);
        for (let i = 0; i < filterKeys.length; i++) {
          const key = filterKeys[i];
          const filterDef = filtersConfig[key] as Record<string, Object>;
          if (filterDef) {
            // 如果变量未设置，使用配置的默认值
            if (!context.variables[key]) {
              const defaultValue = filterDef['default'] as string | undefined;
              context.variables[key] = defaultValue || '';
            }
          }
        }
      }
      
      // 应用动态筛选参数（优先级最高，会覆盖前面设置的值）
      if (dynamicFilters && dynamicFilters.size > 0) {
        dynamicFilters.forEach((value: string, key: string) => {
          context.variables[key] = value;
          logger.debug(TAG, `应用动态筛选参数: ${key}=${value}`);
        });
      }
      
      logger.debug(TAG, `筛选参数: sort=${context.variables['sort']}, category=${context.variables['category']}, filter_category=${context.variables['filter_category']}`);
      
      logger.debug(TAG, `执行上下文变量: ${JSON.stringify(context.variables)}`);
      
      let results: MangaInfo[] = [];
      
      for (let i = 0; i < actions.length; i++) {
        const action = actions[i];
        logger.debug(TAG, `执行操作 ${i + 1}/${actions.length}: ${action.type}`);
        
        const result = await this.actionEngine.executeAction(action, context);
        
        logger.debug(TAG, `操作 ${i + 1} 结果: success=${result.success}, hasData=${!!result.data}`);
        
        if (!result.success) {
          logger.error(TAG, `操作 ${i + 1} 失败: ${result.error}`);
          throw new MangaSourceError(
            MangaSourceErrorCode.ACTION_FAILED,
            `筛选操作失败: ${result.error}`
          );
        }

        if ((action.type === 'extract' || action.type === 'api') && result.data) {
          const resultData = result.data as Record<string, Object> | Array<Record<string, Object>>;
          const extractedData = Array.isArray(resultData) ? resultData : [resultData];
          results = extractedData.map((item: Record<string, Object>) => this.transformToMangaInfo(item));
          logger.debug(TAG, `提取到 ${results.length} 条漫画数据`);
        }
        
        // 支持 script 操作直接返回列表
        if (action.type === 'script' && result.data) {
          let scriptData = String(result.data).trim();
          // WebView runJavaScript 会对返回值进行双重序列化，需要先解析一次
          if (scriptData.startsWith('"') && scriptData.endsWith('"')) {
            try {
              scriptData = SafeUtils.parseStr(scriptData) as string;
            } catch (e) {
              logger.debug(TAG, `解除双重序列化失败: ${e}`);
            }
          }
          // 情况1: 脚本返回数组格式 [{id, title, ...}, ...]
          if (scriptData.startsWith('[')) {
            try {
              const parsed = SafeUtils.parseArr(scriptData) as Array<Record<string, Object>>;
              if (Array.isArray(parsed) && parsed.length > 0 && parsed[0] && (parsed[0] as Record<string, Object>)['id'] !== undefined) {
                results = parsed.map((item: Record<string, Object>) => this.transformToMangaInfo(item));
                logger.debug(TAG, `从脚本结果提取到 ${results.length} 条筛选数据(数组格式)`);
              }
            } catch (e) {
              logger.debug(TAG, `脚本结果不是列表格式: ${e}`);
            }
          }
          // 情况2: 脚本返回对象格式 {mangas: [...], hasNextPage: bool}
          else if (scriptData.startsWith('{')) {
            try {
              const parsed = SafeUtils.parseObj(scriptData) as Record<string, Object>;
              const mangasArray = parsed['mangas'] as Array<Record<string, Object>> | undefined;
              if (mangasArray && Array.isArray(mangasArray) && mangasArray.length > 0) {
                results = mangasArray.map((item: Record<string, Object>) => this.transformToMangaInfo(item));
                logger.debug(TAG, `从脚本结果提取到 ${results.length} 条筛选数据(对象格式)`);
              }
            } catch (e) {
              logger.debug(TAG, `脚本结果不是对象格式: ${e}`);
            }
          }
        }
      }

      const duration = Date.now() - startTime;
      
      logger.info(TAG, `筛选漫画完成，找到 ${results.length} 个结果，耗时 ${duration}ms`);

      return {
        success: true,
        data: {
          mangas: results,
          total: results.length,
          page,
          hasNext: results.length >= 20
        },
        duration,
        actionCount: actions.length
      };

    } catch (error) {
      const duration = Date.now() - startTime;
      const errorMessage = error instanceof Error ? error.message : String(error);
      const errorStack = error instanceof Error ? error.stack : '';
      
      logger.error(TAG, `筛选漫画失败: ${errorMessage}`);
      logger.debug(TAG, `错误堆栈: ${errorStack}`);
      
      return {
        success: false,
        error: errorMessage,
        duration,
        actionCount: 0
      };
    }
  }

  /**
   * 获取分类页面内容（电子书等）
   */
  async getCategory(categoryUrl: string, page: number = 1): Promise<EngineResult<SearchResult>> {
    if (!this.config) {
      logger.error(TAG, '配置未加载，无法获取分类内容');
      throw new MangaSourceError(
        MangaSourceErrorCode.CONFIG_NOT_LOADED,
        '配置未加载'
      );
    }

    const startTime = Date.now();
    logger.info(TAG, `开始获取分类内容: url=${categoryUrl}, 页码=${page}`);

    try {
      // 构建分类操作序列
      logger.debug(TAG, '构建分类操作序列');
      const actions = this.configParser.buildCategoryActions(this.config);
      logger.debug(TAG, `分类操作序列包含 ${actions.length} 个操作`);
      
      // 执行操作序列
      const context = this.createActionContext();
      await this.populateSourceSettings(context);
      context.variables['useCookies'] = 'false';
      context.variables['page'] = page.toString();
      context.variables['offset'] = ((page - 1) * 30).toString();
      context.variables['categoryUrl'] = categoryUrl;
      logger.debug(TAG, `执行上下文变量: ${JSON.stringify(context.variables)}`);
      
      let results: MangaInfo[] = [];
      
      for (let i = 0; i < actions.length; i++) {
        const action = actions[i];
        logger.debug(TAG, `执行操作 ${i + 1}/${actions.length}: ${action.type}`);
        
        const result = await this.actionEngine.executeAction(action, context);
        
        logger.debug(TAG, `操作 ${i + 1} 结果: success=${result.success}, hasData=${!!result.data}`);
        
        if (!result.success) {
          logger.error(TAG, `操作 ${i + 1} 失败: ${result.error}`);
          throw new MangaSourceError(
            MangaSourceErrorCode.ACTION_FAILED,
            `分类操作失败: ${result.error}`
          );
        }

        if ((action.type === 'extract' || action.type === 'api') && result.data) {
          const resultData = result.data as Record<string, Object> | Array<Record<string, Object>>;
          const extractedData = Array.isArray(resultData) ? resultData : [resultData];
          results = extractedData.map((item: Record<string, Object>) => this.transformToMangaInfo(item));
          logger.debug(TAG, `提取到 ${results.length} 条数据`);
        }
        
        // 支持 script 操作直接返回列表
        if (action.type === 'script' && result.data) {
          let scriptData = String(result.data).trim();
          // WebView runJavaScript 会对返回值进行双重序列化，需要先解析一次
          if (scriptData.startsWith('"') && scriptData.endsWith('"')) {
            try {
              scriptData = SafeUtils.parseStr(scriptData) as string;
            } catch (e) {
              logger.debug(TAG, `解除双重序列化失败: ${e}`);
            }
          }
          // 情况1: 脚本返回数组格式 [{id, title, ...}, ...]
          if (scriptData.startsWith('[')) {
            try {
              const parsed = SafeUtils.parseArr(scriptData) as Array<Record<string, Object>>;
              if (Array.isArray(parsed) && parsed.length > 0 && parsed[0] && (parsed[0] as Record<string, Object>)['id'] !== undefined) {
                results = parsed.map((item: Record<string, Object>) => this.transformToMangaInfo(item));
                logger.debug(TAG, `从脚本结果提取到 ${results.length} 条数据(数组格式)`);
              }
            } catch (e) {
              logger.debug(TAG, `脚本结果不是列表格式: ${e}`);
            }
          }
          // 情况2: 脚本返回对象格式 {mangas: [...], hasNextPage: bool}
          else if (scriptData.startsWith('{')) {
            try {
              const parsed = SafeUtils.parseObj(scriptData) as Record<string, Object>;
              const mangasArray = parsed['mangas'] as Array<Record<string, Object>> | undefined;
              if (mangasArray && Array.isArray(mangasArray) && mangasArray.length > 0) {
                results = mangasArray.map((item: Record<string, Object>) => this.transformToMangaInfo(item));
                logger.debug(TAG, `从脚本结果提取到 ${results.length} 条数据(对象格式)`);
              }
            } catch (e) {
              logger.debug(TAG, `脚本结果不是对象格式: ${e}`);
            }
          }
        }
      }

      const duration = Date.now() - startTime;
      
      logger.info(TAG, `获取分类内容完成，找到 ${results.length} 个结果，耗时 ${duration}ms`);

      return {
        success: true,
        data: {
          mangas: results,
          total: results.length,
          page,
          hasNext: results.length >= 20
        },
        duration,
        actionCount: actions.length
      };

    } catch (error) {
      const duration = Date.now() - startTime;
      const errorMessage = error instanceof Error ? error.message : String(error);
      const errorStack = error instanceof Error ? error.stack : '';
      
      logger.error(TAG, `获取分类内容失败: ${errorMessage}`);
      logger.debug(TAG, `错误堆栈: ${errorStack}`);
      
      return {
        success: false,
        error: errorMessage,
        duration,
        actionCount: 0
      };
    }
  }

  /**
   * 获取电子书详情
   */
  async getBookDetail(bookId: string): Promise<EngineResult<Record<string, Object>>> {
    if (!this.config) {
      logger.error(TAG, '配置未加载，无法获取电子书详情');
      throw new MangaSourceError(
        MangaSourceErrorCode.CONFIG_NOT_LOADED,
        '配置未加载'
      );
    }

    const startTime = Date.now();
    logger.info(TAG, `开始获取电子书详情: bookId=${bookId}`);

    try {
      // 构建电子书详情操作序列
      logger.debug(TAG, '构建电子书详情操作序列');
      const actions = this.configParser.buildBookDetailActions(this.config);
      logger.debug(TAG, `电子书详情操作序列包含 ${actions.length} 个操作`);
      
      // 执行操作序列
      const context = this.createActionContext();
      await this.populateSourceSettings(context);
      context.variables['useCookies'] = 'false';
      context.variables['bookId'] = bookId;
      context.variables['mangaUrl'] = bookId;  // 兼容使用{{mangaUrl}}的工作流
      logger.debug(TAG, `执行上下文变量: ${JSON.stringify(context.variables)}`);
      
      let bookDetail: Record<string, Object> = {};
      
      for (let i = 0; i < actions.length; i++) {
        const action = actions[i];
        logger.debug(TAG, `执行操作 ${i + 1}/${actions.length}: ${action.type}`);
        
        const result = await this.actionEngine.executeAction(action, context);
        
        logger.debug(TAG, `操作 ${i + 1} 结果: success=${result.success}, hasData=${!!result.data}`);
        
        if (!result.success) {
          logger.error(TAG, `操作 ${i + 1} 失败: ${result.error}`);
          throw new MangaSourceError(
            MangaSourceErrorCode.ACTION_FAILED,
            `电子书详情操作失败: ${result.error}`
          );
        }

        // 支持 script 操作直接返回详情对象
        if (action.type === 'script' && result.data) {
          let scriptData = String(result.data).trim();
          // WebView runJavaScript 会对返回值进行双重序列化，需要先解析一次
          if (scriptData.startsWith('"') && scriptData.endsWith('"')) {
            try {
              scriptData = SafeUtils.parseStr(scriptData) as string;
            } catch (e) {
              logger.debug(TAG, `解除双重序列化失败: ${e}`);
            }
          }
          if (scriptData.startsWith('{')) {
            try {
              bookDetail = SafeUtils.parseObj(scriptData) as Record<string, Object>;
              logger.debug(TAG, `从脚本结果提取到电子书详情: ${bookDetail['title']}`);
            } catch (e) {
              logger.debug(TAG, `脚本结果不是对象格式: ${e}`);
            }
          }
        }
      }

      const duration = Date.now() - startTime;
      
      logger.info(TAG, `获取电子书详情完成，耗时 ${duration}ms`);

      return {
        success: true,
        data: bookDetail,
        duration,
        actionCount: actions.length
      };

    } catch (error) {
      const duration = Date.now() - startTime;
      const errorMessage = error instanceof Error ? error.message : String(error);
      const errorStack = error instanceof Error ? error.stack : '';
      
      logger.error(TAG, `获取电子书详情失败: ${errorMessage}`);
      logger.debug(TAG, `错误堆栈: ${errorStack}`);
      
      return {
        success: false,
        error: errorMessage,
        duration,
        actionCount: 0
      };
    }
  }

  /**
   * 获取用户收藏（需要登录）
   */
  async getFavorites(page: number = 1): Promise<EngineResult<SearchResult>> {
    if (!this.config) {
      logger.error(TAG, '配置未加载，无法获取收藏');
      throw new MangaSourceError(
        MangaSourceErrorCode.CONFIG_NOT_LOADED,
        '配置未加载'
      );
    }

    const startTime = Date.now();
    logger.info(TAG, `开始获取收藏: 页码=${page}`);

    try {
      // 构建收藏操作序列
      logger.debug(TAG, '构建收藏操作序列');
      const actions = this.configParser.buildFavoritesActions(this.config);
      logger.debug(TAG, `收藏操作序列包含 ${actions.length} 个操作`);
      
      // 执行操作序列
      const context = this.createActionContext();
      await this.populateSourceSettings(context);
      context.variables['useCookies'] = 'true';  // 收藏需要登录
      context.variables['page'] = page.toString();
      const pageSize: number = Number(context.variables['pageSize'] || '30');
      context.variables['offset'] = ((page - 1) * pageSize).toString();
      logger.debug(TAG, `执行上下文变量: ${JSON.stringify(context.variables)}`);
      
      let favoritesResults: MangaInfo[] = [];
      
      for (let i = 0; i < actions.length; i++) {
        const action = actions[i];
        logger.debug(TAG, `执行操作 ${i + 1}/${actions.length}: ${action.type}`);
        
        const result = await this.actionEngine.executeAction(action, context);
        
        logger.debug(TAG, `操作 ${i + 1} 结果: success=${result.success}, hasData=${!!result.data}`);
        
        if (!result.success) {
          logger.error(TAG, `操作 ${i + 1} 失败: ${result.error}`);
          throw new MangaSourceError(
            MangaSourceErrorCode.ACTION_FAILED,
            `收藏操作失败: ${result.error}`
          );
        }

        if ((action.type === 'extract' || action.type === 'api') && result.data) {
          if (Array.isArray(result.data)) {
            favoritesResults = result.data.map((item: Record<string, Object>) => this.transformToMangaInfo(item));
          }
        }
      }

      logger.debug(TAG, `提取到 ${favoritesResults.length} 条收藏数据`);

      const duration = Date.now() - startTime;
      logger.info(TAG, `获取收藏完成，找到 ${favoritesResults.length} 个结果，耗时 ${duration}ms`);

      return {
        success: true,
        data: {
          mangas: favoritesResults,
          total: favoritesResults.length,
          page: page,
          hasNext: favoritesResults.length >= pageSize
        },
        duration,
        actionCount: actions.length
      };

    } catch (error) {
      const duration = Date.now() - startTime;
      const errorMessage = error instanceof Error ? error.message : String(error);
      const errorStack = error instanceof Error ? error.stack : '';
      
      logger.error(TAG, `获取收藏失败: ${errorMessage}`);
      logger.debug(TAG, `错误堆栈: ${errorStack}`);
      
      return {
        success: false,
        error: errorMessage,
        duration,
        actionCount: 0
      };
    }
  }

  /**
   * 获取浏览记录（需要登录）
   */
  async getHistory(page: number = 1): Promise<EngineResult<SearchResult>> {
    if (!this.config) {
      logger.error(TAG, '配置未加载，无法获取浏览记录');
      throw new MangaSourceError(
        MangaSourceErrorCode.CONFIG_NOT_LOADED,
        '配置未加载'
      );
    }

    const startTime = Date.now();
    logger.info(TAG, `开始获取浏览记录: 页码=${page}`);

    try {
      // 构建浏览记录操作序列
      logger.debug(TAG, '构建浏览记录操作序列');
      const actions = this.configParser.buildHistoryActions(this.config);
      logger.debug(TAG, `浏览记录操作序列包含 ${actions.length} 个操作`);
      
      // 执行操作序列
      const context = this.createActionContext();
      await this.populateSourceSettings(context);
      context.variables['useCookies'] = 'true';  // 浏览记录需要登录
      context.variables['page'] = page.toString();
      const pageSize: number = Number(context.variables['pageSize'] || '30');
      context.variables['offset'] = ((page - 1) * pageSize).toString();
      logger.debug(TAG, `执行上下文变量: ${JSON.stringify(context.variables)}`);
      
      let historyResults: MangaInfo[] = [];
      
      for (let i = 0; i < actions.length; i++) {
        const action = actions[i];
        logger.debug(TAG, `执行操作 ${i + 1}/${actions.length}: ${action.type}`);
        
        const result = await this.actionEngine.executeAction(action, context);
        
        logger.debug(TAG, `操作 ${i + 1} 结果: success=${result.success}, hasData=${!!result.data}`);
        
        if (!result.success) {
          logger.error(TAG, `操作 ${i + 1} 失败: ${result.error}`);
          throw new MangaSourceError(
            MangaSourceErrorCode.ACTION_FAILED,
            `浏览记录操作失败: ${result.error}`
          );
        }

        if ((action.type === 'extract' || action.type === 'api') && result.data) {
          if (Array.isArray(result.data)) {
            historyResults = result.data.map((item: Record<string, Object>) => this.transformToMangaInfo(item));
          }
        }
      }

      logger.debug(TAG, `提取到 ${historyResults.length} 条浏览记录数据`);

      const duration = Date.now() - startTime;
      logger.info(TAG, `获取浏览记录完成，找到 ${historyResults.length} 个结果，耗时 ${duration}ms`);

      return {
        success: true,
        data: {
          mangas: historyResults,
          total: historyResults.length,
          page: page,
          hasNext: historyResults.length >= pageSize
        },
        duration,
        actionCount: actions.length
      };

    } catch (error) {
      const duration = Date.now() - startTime;
      const errorMessage = error instanceof Error ? error.message : String(error);
      const errorStack = error instanceof Error ? error.stack : '';
      
      logger.error(TAG, `获取浏览记录失败: ${errorMessage}`);
      logger.debug(TAG, `错误堆栈: ${errorStack}`);
      
      return {
        success: false,
        error: errorMessage,
        duration,
        actionCount: 0
      };
    }
  }

  /**
   * 获取排行榜
   * @param page 页码
   * @param dynamicFilters 动态筛选参数（如timeType）
   */
  async getLeaderboard(page: number = 1, dynamicFilters?: Map<string, string>): Promise<EngineResult<SearchResult>> {
    if (!this.config) {
      logger.error(TAG, '配置未加载，无法获取排行榜');
      throw new MangaSourceError(
        MangaSourceErrorCode.CONFIG_NOT_LOADED,
        '配置未加载'
      );
    }

    const startTime = Date.now();
    // 输出 dynamicFilters 的内容用于调试
    if (dynamicFilters && dynamicFilters.size > 0) {
      const entries: string[] = [];
      dynamicFilters.forEach((value, key) => {
        entries.push(`${key}=${value}`);
      });
      logger.info(TAG, `开始获取排行榜: 页码=${page}, 动态筛选参数=[${entries.join(', ')}]`);
    } else {
      logger.info(TAG, `开始获取排行榜: 页码=${page}, 动态筛选参数=[空]`);
    }

    try {
      // 构建排行榜操作序列
      logger.debug(TAG, '构建排行榜操作序列');
      const actions = this.configParser.buildLeaderboardActions(this.config);
      logger.debug(TAG, `排行榜操作序列包含 ${actions.length} 个操作`);
      
      // 执行操作序列
      const context = this.createActionContext();
      await this.populateSourceSettings(context);
      context.variables['page'] = page.toString();
      const pageSize: number = Number(context.variables['pageSize'] || '30');
      context.variables['offset'] = ((page - 1) * pageSize).toString();
      
      // 设置排行榜时间类型
      // 优先使用动态筛选参数，其次使用workflow默认值
      if (dynamicFilters && dynamicFilters.has('timeType')) {
        context.variables['timeType'] = dynamicFilters.get('timeType') || 'a';
      } else if (!context.variables['timeType']) {
        // 从workflow defaults中读取默认值
        let defaultTimeType = 'a';
        if (this.rawConfigJson) {
          try {
            const rawConfig = SafeUtils.parseObj(this.rawConfigJson) as Record<string, Object>;
            const workflows = rawConfig['workflows'] as Record<string, Object> | undefined;
            if (workflows) {
              const leaderboardWorkflow = workflows['getLeaderboard'] as Record<string, Object> | undefined;
              if (leaderboardWorkflow) {
                const defaults = leaderboardWorkflow['defaults'] as Record<string, string> | undefined;
                if (defaults && defaults['timeType']) {
                  defaultTimeType = defaults['timeType'];
                }
              }
            }
          } catch (e) {
            logger.warn(TAG, `解析排行榜默认值失败: ${e}`);
          }
        }
        context.variables['timeType'] = defaultTimeType;
      }
      
      // 将所有动态筛选参数添加到上下文
      if (dynamicFilters) {
        dynamicFilters.forEach((value, key) => {
          context.variables[key] = value;
        });
      }
      
      logger.debug(TAG, `执行上下文变量: ${JSON.stringify(context.variables)}`);
      
      let leaderboardResults: MangaInfo[] = [];
      
      for (let i = 0; i < actions.length; i++) {
        const action = actions[i];
        logger.debug(TAG, `执行操作 ${i + 1}/${actions.length}: ${action.type}`);
        
        const result = await this.actionEngine.executeAction(action, context);
        
        logger.debug(TAG, `操作 ${i + 1} 结果: success=${result.success}, hasData=${!!result.data}`);
        
        if (!result.success) {
          logger.error(TAG, `操作 ${i + 1} 失败: ${result.error}`);
          throw new MangaSourceError(
            MangaSourceErrorCode.ACTION_FAILED,
            `排行榜操作失败: ${result.error}`
          );
        }

        if ((action.type === 'extract' || action.type === 'api') && result.data) {
          if (Array.isArray(result.data)) {
            leaderboardResults = result.data.map((item: Record<string, Object>) => this.transformToMangaInfo(item));
          }
        }
        
        // 支持 script 操作直接返回列表
        if (action.type === 'script' && result.data) {
          let scriptData = String(result.data).trim();
          // WebView runJavaScript 会对返回值进行双重序列化，需要先解析一次
          if (scriptData.startsWith('"') && scriptData.endsWith('"')) {
            try {
              scriptData = SafeUtils.parseStr(scriptData) as string;
            } catch (e) {
              logger.debug(TAG, `解除双重序列化失败: ${e}`);
            }
          }
          // 情况1: 脚本返回数组格式 [{id, title, ...}, ...]
          if (scriptData.startsWith('[')) {
            try {
              const parsed = SafeUtils.parseArr(scriptData) as Array<Record<string, Object>>;
              if (Array.isArray(parsed) && parsed.length > 0 && parsed[0] && (parsed[0] as Record<string, Object>)['id'] !== undefined) {
                leaderboardResults = parsed.map((item: Record<string, Object>) => this.transformToMangaInfo(item));
                logger.debug(TAG, `从脚本结果提取到 ${leaderboardResults.length} 条排行榜数据(数组格式)`);
              }
            } catch (e) {
              logger.debug(TAG, `脚本结果不是列表格式: ${e}`);
            }
          }
          // 情况2: 脚本返回对象格式 {mangas: [...], hasNextPage: bool}
          else if (scriptData.startsWith('{')) {
            try {
              const parsed = SafeUtils.parseObj(scriptData) as Record<string, Object>;
              const mangasArray = parsed['mangas'] as Array<Record<string, Object>> | undefined;
              if (mangasArray && Array.isArray(mangasArray) && mangasArray.length > 0) {
                leaderboardResults = mangasArray.map((item: Record<string, Object>) => this.transformToMangaInfo(item));
                logger.debug(TAG, `从脚本结果提取到 ${leaderboardResults.length} 条排行榜数据(对象格式)`);
              }
            } catch (e) {
              logger.debug(TAG, `脚本结果不是对象格式: ${e}`);
            }
          }
        }
      }

      logger.debug(TAG, `提取到 ${leaderboardResults.length} 条排行榜数据`);

      const duration = Date.now() - startTime;
      logger.info(TAG, `获取排行榜完成，找到 ${leaderboardResults.length} 个结果，耗时 ${duration}ms`);

      return {
        success: true,
        data: {
          mangas: leaderboardResults,
          total: leaderboardResults.length,
          page: page,
          hasNext: leaderboardResults.length >= pageSize
        },
        duration,
        actionCount: actions.length
      };

    } catch (error) {
      const duration = Date.now() - startTime;
      const errorMessage = error instanceof Error ? error.message : String(error);
      const errorStack = error instanceof Error ? error.stack : '';
      
      logger.error(TAG, `获取排行榜失败: ${errorMessage}`);
      logger.debug(TAG, `错误堆栈: ${errorStack}`);
      
      return {
        success: false,
        error: errorMessage,
        duration,
        actionCount: 0
      };
    }
  }

  /**
   * 执行自定义工作流
   * @param workflowName 工作流名称
   * @param page 页码
   * @param params 额外参数
   */
  async executeCustomWorkflow(
    workflowName: string, 
    page: number = 1, 
    params?: FilterParams
  ): Promise<EngineResult<SearchResult>> {
    if (!this.config) {
      logger.error(TAG, '配置未加载，无法执行自定义工作流');
      throw new MangaSourceError(
        MangaSourceErrorCode.CONFIG_NOT_LOADED,
        '配置未加载'
      );
    }

    const startTime = Date.now();
    logger.info(TAG, `开始执行自定义工作流: ${workflowName}, 页码=${page}`);

    try {
      // 获取工作流
      const actions = this.configParser.getWorkflow(this.config, workflowName);
      if (!actions || actions.length === 0) {
        throw new MangaSourceError(
          MangaSourceErrorCode.WORKFLOW_NOT_FOUND,
          `未找到工作流: ${workflowName}`
        );
      }
      logger.debug(TAG, `自定义工作流 ${workflowName} 包含 ${actions.length} 个操作`);
      
      // 执行操作序列
      const context = this.createActionContext();
      await this.populateSourceSettings(context);
      context.variables['page'] = page.toString();
      const pageSize: number = Number(context.variables['pageSize'] || '30');
      context.variables['offset'] = ((page - 1) * pageSize).toString();
      
      // 添加额外参数
      if (params) {
        if (params.ordering) context.variables['ordering'] = params.ordering;
        if (params.region) context.variables['region'] = params.region;
        if (params.theme) context.variables['theme'] = params.theme;
        if (params.sort) context.variables['sort'] = params.sort;
        if (params.category) context.variables['category'] = params.category;
        if (params.rank) context.variables['rank'] = params.rank;
      }
      
      logger.debug(TAG, `执行上下文变量: ${JSON.stringify(context.variables)}`);
      
      let results: MangaInfo[] = [];
      
      for (let i = 0; i < actions.length; i++) {
        const action = actions[i];
        logger.debug(TAG, `执行操作 ${i + 1}/${actions.length}: ${action.type}`);
        
        const result = await this.actionEngine.executeAction(action, context);
        
        logger.debug(TAG, `操作 ${i + 1} 结果: success=${result.success}, hasData=${!!result.data}`);
        
        if (!result.success) {
          logger.error(TAG, `操作 ${i + 1} 失败: ${result.error}`);
          throw new MangaSourceError(
            MangaSourceErrorCode.ACTION_FAILED,
            `自定义工作流操作失败: ${result.error}`
          );
        }

        if ((action.type === 'extract' || action.type === 'api') && result.data) {
          if (Array.isArray(result.data)) {
            results = result.data.map((item: Record<string, Object>) => this.transformToMangaInfo(item));
          }
        }
      }

      logger.debug(TAG, `提取到 ${results.length} 条数据`);

      const duration = Date.now() - startTime;
      logger.info(TAG, `自定义工作流 ${workflowName} 完成，找到 ${results.length} 个结果，耗时 ${duration}ms`);

      return {
        success: true,
        data: {
          mangas: results,
          total: results.length,
          page: page,
          hasNext: results.length >= pageSize
        },
        duration,
        actionCount: actions.length
      };

    } catch (error) {
      const duration = Date.now() - startTime;
      const errorMessage = error instanceof Error ? error.message : String(error);
      const errorStack = error instanceof Error ? error.stack : '';
      
      logger.error(TAG, `自定义工作流 ${workflowName} 失败: ${errorMessage}`);
      logger.debug(TAG, `错误堆栈: ${errorStack}`);
      
      return {
        success: false,
        error: errorMessage,
        duration,
        actionCount: 0
      };
    }
  }

  /**
   * 获取用户头像
   */
  async getUserAvatar(): Promise<EngineResult<string>> {
    const startTime = Date.now();
    
    try {
      if (!this.config) {
        logger.error(TAG, '配置未加载，无法获取用户头像');
        return {
          success: false,
          error: '配置未加载',
          duration: Date.now() - startTime,
          actionCount: 0
        };
      }
      
      const actions = this.configParser.getWorkflow(this.config, 'getUserAvatar');
      
      if (!actions || actions.length === 0) {
        logger.warn(TAG, '未配置getUserAvatar工作流');
        return {
          success: false,
          error: '未配置getUserAvatar工作流',
          duration: Date.now() - startTime,
          actionCount: 0
        };
      }
      
      logger.info(TAG, `开始获取用户头像，actions数量: ${actions.length}`);
      
      // 创建执行上下文
      const context = this.createActionContext();
      await this.populateSourceSettings(context);
      context.variables['useCookies'] = 'true';  // 获取头像需要登录
      
      // 执行工作流
      let avatarUrl = '';
      for (let i = 0; i < actions.length; i++) {
        const action = actions[i];
        logger.debug(TAG, `执行操作 ${i + 1}/${actions.length}: ${action.type}`);
        
        const result = await this.actionEngine.executeAction(action, context);
        
        if (!result.success) {
          logger.error(TAG, `操作 ${i + 1} 失败: ${result.error}`);
          throw new Error(`获取用户头像失败: ${result.error}`);
        }
        
        // 从结果中提取头像URL
        if (result.data) {
          if (typeof result.data === 'string') {
            avatarUrl = result.data;
          } else if (typeof result.data === 'object') {
            const dataObj = result.data as Record<string, Object>;
            if (dataObj['avatarUrl']) {
              avatarUrl = String(dataObj['avatarUrl']);
            } else if (dataObj['avatar']) {
              avatarUrl = String(dataObj['avatar']);
            } else if (dataObj['url']) {
              avatarUrl = String(dataObj['url']);
            }
          }
        }
      }
      
      if (!avatarUrl) {
        logger.warn(TAG, '未能从结果中提取头像URL');
        return {
          success: false,
          error: '未能提取头像URL',
          duration: Date.now() - startTime,
          actionCount: actions.length
        };
      }
      
      logger.info(TAG, `获取用户头像成功: ${avatarUrl}`);
      
      return {
        success: true,
        data: avatarUrl,
        duration: Date.now() - startTime,
        actionCount: actions.length
      };
      
    } catch (error) {
      const duration = Date.now() - startTime;
      const errorMessage = error instanceof Error ? error.message : String(error);
      
      logger.error(TAG, `获取用户头像失败: ${errorMessage}`);
      
      return {
        success: false,
        error: errorMessage,
        duration,
        actionCount: 0
      };
    }
  }

  /**
   * 获取漫画详情
   */
  async getMangaDetail(mangaId: string): Promise<EngineResult<MangaInfo>> {
    if (!this.config) {
      throw new MangaSourceError(
        MangaSourceErrorCode.CONFIG_NOT_LOADED,
        '配置未加载'
      );
    }

    const startTime = Date.now();
    logger.info(TAG, `获取漫画详情: ${mangaId}`);

    try {
      const actions = this.configParser.buildMangaDetailActions(this.config, mangaId);
      const context = this.createActionContext();
      await this.populateSourceSettings(context);
      context.variables['useCookies'] = 'true';
      // 添加mangaId变量到上下文（规范化URL）
      context.variables['mangaId'] = this.normalizeUrl(mangaId);
      
      let mangaDetail: MangaInfo | undefined;
      
      for (const action of actions) {
        const result = await this.actionEngine.executeAction(action, context);
        
        if (!result.success) {
          throw new MangaSourceError(
            MangaSourceErrorCode.ACTION_FAILED,
            `获取详情操作失败: ${result.error}`
          );
        }

        if ((action.type === 'extract' || action.type === 'api') && result.data) {
          const dataObj = result.data as Record<string, Object>;
          mangaDetail = this.transformToMangaInfo(dataObj);
        }

        if (action.type === 'script' && result.data) {
          const detailFromScript = this.extractMangaDetailFromScriptResult(result.data as string | Object);
          if (detailFromScript) {
            mangaDetail = detailFromScript;
          }
        }
      }

      if (!mangaDetail) {
        throw new MangaSourceError(
          MangaSourceErrorCode.DATA_NOT_FOUND,
          '未找到漫画详情'
        );
      }

      const duration = Date.now() - startTime;
      
      logger.info(TAG, `获取漫画详情完成，耗时 ${duration}ms`);

      return {
        success: true,
        data: mangaDetail,
        duration,
        actionCount: actions.length
      };

    } catch (error) {
      const duration = Date.now() - startTime;
      const errorMessage = error instanceof Error ? error.message : String(error);
      
      logger.error(TAG, '获取漫画详情失败' + error);
      
      return {
        success: false,
        error: errorMessage,
        duration,
        actionCount: 0
      };
    }
  }

  /**
   * 获取章节列表
   */
  async getChapterList(mangaId: string): Promise<EngineResult<ChapterInfo[]>> {
    if (!this.config) {
      throw new MangaSourceError(
        MangaSourceErrorCode.CONFIG_NOT_LOADED,
        '配置未加载'
      );
    }

    const startTime = Date.now();
    logger.info(TAG, `获取章节列表: ${mangaId}`);

    try {
      const actions = this.configParser.buildChapterListActions(this.config, mangaId);
      const context = this.createActionContext();
      await this.populateSourceSettings(context);
      context.variables['useCookies'] = 'true';
      // 添加mangaId变量到上下文（规范化URL）
      context.variables['mangaId'] = this.normalizeUrl(mangaId);
      // 设置分页参数（章节列表默认从offset=0开始获取全部）
      context.variables['page'] = '1';
      context.variables['offset'] = '0';
      
      let chapters: ChapterInfo[] = [];
      this.lastChapterAccessDenied = false;
      
      for (const action of actions) {
        // [修复] 检测 API 操作的分页配置，自动循环获取所有章节
        if (action.type === 'api') {
          const apiAction = action as APIRequestAction;
          const paginationConfig = apiAction.pagination;
          
          if (paginationConfig && paginationConfig.enabled) {
            // 带分页的 API 请求 - 循环获取所有章节
            const pageParam: string = paginationConfig.pageParam || 'page';
            const maxPages: number = 50;
            
            logger.info(TAG, `检测到章节列表API分页配置: pageParam=${pageParam}, 开始分页加载`);
            
            for (let pageNum = 1; pageNum <= maxPages; pageNum++) {
              if (apiAction.params) {
                apiAction.params[pageParam] = String(pageNum);
              }
              
              logger.info(TAG, `分页加载章节列表: 第${pageNum}页`);
              
              const result = await this.actionEngine.executeAction(action, context);
              
              if (!result.success) {
                if (pageNum === 1) {
                  throw new MangaSourceError(
                    MangaSourceErrorCode.ACTION_FAILED,
                    `获取章节列表操作失败: ${result.error}`
                  );
                }
                logger.warn(TAG, `分页加载第${pageNum}页失败，停止分页: ${result.error}`);
                break;
              }
              
              if (!result.data) {
                logger.info(TAG, `分页加载: 第${pageNum}页无数据，分页完成`);
                break;
              }
              
              const resultData = result.data as Record<string, Object> | Array<Record<string, Object>>;
              const extractedData = Array.isArray(resultData) ? resultData : [resultData];
              const newChapters: ChapterInfo[] = extractedData.map((item: Record<string, Object>) => this.transformToChapterInfo(item));
              
              if (newChapters.length === 0) {
                logger.info(TAG, `分页加载: 第${pageNum}页返回空数据，分页完成`);
                break;
              }
              
              for (let ci = 0; ci < newChapters.length; ci++) {
                chapters.push(newChapters[ci]);
              }
              logger.info(TAG, `分页加载: 第${pageNum}页获取到${newChapters.length}个章节，累计${chapters.length}个`);
            }
            
            continue;
          }
        }
        
        // 非分页的普通执行逻辑
        const result = await this.actionEngine.executeAction(action, context);
        
        if (!result.success) {
          throw new MangaSourceError(
            MangaSourceErrorCode.ACTION_FAILED,
            `获取章节列表操作失败: ${result.error}`
          );
        }

        if ((action.type === 'extract' || action.type === 'api') && result.data) {
          const resultData = result.data as Record<string, Object> | Array<Record<string, Object>>;
          const extractedData = Array.isArray(resultData) ? resultData : [resultData];
          chapters = extractedData.map((item: Record<string, Object>) => this.transformToChapterInfo(item));
        }
        
        // 支持script操作返回JSON字符串数组
        if (action.type === 'script' && result.data) {
          logger.debug(TAG, `script操作返回数据类型: ${typeof result.data}`);
          logger.debug(TAG, `script操作返回数据内容: ${String(result.data).substring(0, 200)}`);
          
          if (typeof result.data === 'string') {
            try {
              let scriptResult = result.data as string;
              
              // 尝试第一次解析
              let parsed: Object = SafeUtils.parseObj(scriptResult);
              logger.debug(TAG, `第一次JSON解析: 类型=${typeof parsed}, 是否数组=${Array.isArray(parsed)}`);
              
              // 如果解析后还是字符串且以[开头，说明被双重字符串化了，需要再解析一次
              if (typeof parsed === 'string' && (parsed as string).trim().startsWith('[')) {
                logger.debug(TAG, `检测到双重字符串化，进行第二次解析`);
                parsed = SafeUtils.parseObj(parsed as string);
                logger.debug(TAG, `第二次JSON解析: 类型=${typeof parsed}, 是否数组=${Array.isArray(parsed)}`);
              }
              
              if (Array.isArray(parsed)) {
                const parsedArray = parsed as Array<Record<string, Object>>;
                chapters = parsedArray.map((item: Record<string, Object>) => this.transformToChapterInfo(item));
                logger.info(TAG, `script操作返回了 ${chapters.length} 个章节`);
              } else {
                logger.warn(TAG, `script返回的不是数组: ${typeof parsed}`);
              }
            } catch (e) {
              const errorMsg = e instanceof Error ? e.message : String(e);
              logger.error(TAG, `JSON解析失败: ${errorMsg}`);
            }
          } else {
            logger.warn(TAG, `script返回的不是字符串，无法解析为章节列表`);
          }
        }

        // 访问权限检测：HTTP 或 API 响应中出现 errno=0 且 errmsg=""
        if (action.type === 'http' && result.data && typeof result.data === 'string') {
          const s: string = result.data as string;
          if (s.indexOf('"errno":0,"errmsg":""') >= 0) {
            this.lastChapterAccessDenied = true;
          }
        }
        if (action.type === 'api' && result.data && typeof result.data === 'object') {
          const obj: Record<string, Object> = (result.data as Record<string, Object>);
          const keys: string[] = Object.keys(obj);
          if (keys.includes('errno') && keys.includes('errmsg')) {
            const errnoVal = Number(obj['errno']);
            const errmsgVal = String(obj['errmsg']);
            if (errnoVal === 0 && errmsgVal === '') {
              this.lastChapterAccessDenied = true;
            }
          }
        }
      }

      // [修复] 智能章节排序：支持多种排序依据
      // 优先级：number字段 > externalId数字 > 标题中提取的数字 > 原始顺序
      if (chapters.length > 0) {
        chapters = this.sortChaptersIntelligently(chapters);
        logger.debug(TAG, `章节已智能排序，第一章: ${chapters[0].title}, 最后一章: ${chapters[chapters.length - 1].title}`);
      }

      const duration = Date.now() - startTime;
      
      logger.info(TAG, `获取章节列表完成，共 ${chapters.length} 章，耗时 ${duration}ms`);

      return {
        success: true,
        data: chapters,
        duration,
        actionCount: actions.length
      };

    } catch (error) {
      const duration = Date.now() - startTime;
      const errorMessage = error instanceof Error ? error.message : String(error);
      
      logger.error(TAG, '获取章节列表失败' + error);
      
      return {
        success: false,
        error: errorMessage,
        duration,
        actionCount: 0
      };
    }
  }

  isLastChapterAccessDenied(): boolean {
    return this.lastChapterAccessDenied;
  }

  /**
   * 一次性获取漫画详情和章节列表（优化：避免重复导航）
   */
  async getMangaDetailWithChapters(mangaId: string): Promise<EngineResult<MangaDetailWithChapters>> {
    if (!this.config) {
      throw new MangaSourceError(
        MangaSourceErrorCode.CONFIG_NOT_LOADED,
        '配置未加载'
      );
    }

    const startTime = Date.now();
    
    // 检查是否有合并工作流
    const workflowActions = this.configParser.getWorkflow(this.config, 'getMangaDetailWithChapters');
    if (!workflowActions) {
      logger.info(TAG, '未找到合并工作流，使用独立调用');
      // 降级：分别调用
      const detailResult = await this.getMangaDetail(mangaId);
      const chapterResult = await this.getChapterList(mangaId);
      
      // [修复] 即使详情获取失败，只要章节获取成功，也返回部分成功的结果
      // MangaDetailPage 可以使用缓存的标题和封面来显示页面
      if (!chapterResult.success) {
        // 章节获取失败才是真正的失败
        return {
          success: false,
          error: chapterResult.error || '获取章节列表失败',
          duration: Date.now() - startTime,
          actionCount: 0
        };
      }
      
      // 构建返回数据，详情可能为空（使用空对象作为占位符）
      let detailData: MangaInfo;
      if (detailResult.success && detailResult.data) {
        detailData = detailResult.data;
      } else {
        // 创建空的占位符对象
        const emptyDetail: MangaInfo = {
          id: mangaId,
          title: '',
          url: '',
          cover: '',
          author: '',
          description: '',
          status: '',
          genres: []
        };
        detailData = emptyDetail;
      }
      
      if (!detailResult.success) {
        logger.warn(TAG, `详情获取失败但章节成功，使用空详情占位符: ${detailResult.error}`);
      }
      
      const combinedData: MangaDetailWithChapters = {
        detail: detailData,
        chapters: chapterResult.data!
      };
      return {
        success: true,
        data: combinedData,
        duration: Date.now() - startTime,
        actionCount: (detailResult.actionCount || 0) + (chapterResult.actionCount || 0)
      };
    }

    logger.info(TAG, `使用合并工作流获取详情和章节: ${mangaId}`);

    try {
      // 使用configParser处理actions，替换变量
      const actions: Action[] = this.configParser.buildMangaDetailWithChaptersActions(this.config, mangaId);
      const context = this.createActionContext();
      await this.populateSourceSettings(context);
      context.variables['useCookies'] = 'true';
      // 规范化mangaId URL
      context.variables['mangaId'] = this.normalizeUrl(mangaId);
      
      let mangaDetail: MangaInfo | undefined;
      let chapters: ChapterInfo[] = [];
      let detailActionIndex = -1;
      let chapterActionIndex = -1;
      
      for (let i = 0; i < actions.length; i++) {
        const action: Action = actions[i];
        const result = await this.actionEngine.executeAction(action, context);
        
        if (result.success && (action.type === 'extract' || action.type === 'api') && result.data) {
          const resultData = result.data as Record<string, Object> | Array<Record<string, Object>>;
          if (!Array.isArray(resultData) && !mangaDetail) {
            mangaDetail = this.transformToMangaInfo(resultData);
            detailActionIndex = i;
            logger.debug(TAG, `combined workflow extracted detail from ${action.type} (action ${i})`);
          }

          if (Array.isArray(resultData) && resultData.length > 0 && chapters.length === 0) {
            chapters = resultData.map((item: Record<string, Object>) => this.transformToChapterInfo(item));
            chapterActionIndex = i;
            logger.debug(TAG, `combined workflow extracted ${chapters.length} chapters from ${action.type} (action ${i})`);
          }
        }
        
        if (!result.success) {
          throw new MangaSourceError(
            MangaSourceErrorCode.ACTION_FAILED,
            `合并工作流操作失败: ${result.error}`
          );
        }

        // 提取详情（第一个返回数据的script）
        if (action.type === 'script' && result.data && !mangaDetail) {
          const detailFromScript = this.extractMangaDetailFromScriptResult(result.data as string | Object);
          if (detailFromScript) {
            mangaDetail = detailFromScript;
            detailActionIndex = i;
            logger.debug(TAG, `合并工作流：提取到详情 (action ${i})`);
          }
        }
        
        // 提取章节（第二个返回数据的script，且是数组）
        if (action.type === 'script' && result.data && mangaDetail && chapters.length === 0) {
          const chapterListFromScript = this.extractChapterListFromScriptResult(result.data as string | Object);
          if (chapterListFromScript.length > 0) {
            chapters = chapterListFromScript;
            chapterActionIndex = i;
            logger.debug(TAG, `合并工作流：提取到 ${chapters.length} 个章节 (action ${i})`);
          }
        }
      }

      if (!mangaDetail) {
        throw new MangaSourceError(
          MangaSourceErrorCode.DATA_NOT_FOUND,
          '合并工作流未找到漫画详情'
        );
      }

      const duration = Date.now() - startTime;
      logger.info(TAG, `合并工作流完成: 详情+${chapters.length}章节，耗时 ${duration}ms`);

      const resultData: MangaDetailWithChapters = {
        detail: mangaDetail,
        chapters: chapters
      };
      return {
        success: true,
        data: resultData,
        duration,
        actionCount: actions.length
      };

    } catch (error) {
      const duration = Date.now() - startTime;
      const errorMessage = error instanceof Error ? error.message : String(error);
      
      logger.error(TAG, '合并工作流失败' + error);
      
      return {
        success: false,
        error: errorMessage,
        duration,
        actionCount: 0
      };
    }
  }

  /**
   * 获取页面列表
   */
  async getPageList(chapterId: string, mangaId?: string): Promise<EngineResult<PageInfo[]>> {
    if (!this.config) {
      throw new MangaSourceError(
        MangaSourceErrorCode.CONFIG_NOT_LOADED,
        '配置未加载'
      );
    }

    const startTime = Date.now();
    logger.info(TAG, `获取页面列表: ${chapterId}`);

    try {
      const actions = this.configParser.buildPageListActions(this.config, chapterId, mangaId);
      const context = this.createActionContext();
      await this.populateSourceSettings(context);
      context.variables['useCookies'] = 'true';
      // 添加mangaId和chapterId变量到上下文（规范化URL）
      if (mangaId) {
        context.variables['mangaId'] = this.normalizeUrl(mangaId);
      }
      context.variables['chapterId'] = this.normalizeUrl(chapterId);
      
      let pages: PageInfo[] = [];
      
      for (const action of actions) {
        // [修复] 检测 API 操作的分页配置，自动循环获取所有页面
        if (action.type === 'api') {
          const apiAction = action as APIRequestAction;
          const paginationConfig = apiAction.pagination;
          
          if (paginationConfig && paginationConfig.enabled) {
            // 带分页的 API 请求 - 循环获取所有页面
            const pageParam: string = paginationConfig.pageParam || 'page';
            const maxPages: number = 50; // 安全上限，防止无限循环
            
            logger.info(TAG, `检测到API分页配置: pageParam=${pageParam}, 开始分页加载`);
            
            for (let pageNum = 1; pageNum <= maxPages; pageNum++) {
              // 更新页码参数
              if (apiAction.params) {
                apiAction.params[pageParam] = String(pageNum);
              }
              
              logger.info(TAG, `分页加载图片列表: 第${pageNum}页`);
              
              const result = await this.actionEngine.executeAction(action, context);
              
              if (!result.success) {
                if (pageNum === 1) {
                  // 第一页失败，抛出错误
                  throw new MangaSourceError(
                    MangaSourceErrorCode.ACTION_FAILED,
                    `获取页面列表操作失败: ${result.error}`
                  );
                }
                // 后续页失败，停止但保留已获取的数据
                logger.warn(TAG, `分页加载第${pageNum}页失败，停止分页: ${result.error}`);
                break;
              }
              
              if (!result.data) {
                logger.info(TAG, `分页加载: 第${pageNum}页无数据，分页完成`);
                break;
              }
              
              // 从当前页结果提取页面信息
              const resultData = result.data as Record<string, Object> | Array<Record<string, Object>>;
              const extractedData = Array.isArray(resultData) ? resultData : [resultData];
              const newPages: PageInfo[] = extractedData.map((item: Record<string, Object>, index: number) =>
                this.transformToPageInfo(item, pages.length + index)
              );
              
              if (newPages.length === 0) {
                logger.info(TAG, `分页加载: 第${pageNum}页返回空数据，分页完成`);
                break;
              }
              
              for (let pi = 0; pi < newPages.length; pi++) {
                pages.push(newPages[pi]);
              }
              logger.info(TAG, `分页加载: 第${pageNum}页获取到${newPages.length}个页面，累计${pages.length}个`);
            }
            
            // 分页处理完成，跳到下一个 action
            continue;
          }
        }
        
        // 非分页的普通执行逻辑
        const result = await this.actionEngine.executeAction(action, context);
        
        if (!result.success) {
          throw new MangaSourceError(
            MangaSourceErrorCode.ACTION_FAILED,
            `获取页面列表操作失败: ${result.error}`
          );
        }

        // 支持 script 操作返回 JSON 字符串（数组或对象）
        if (action.type === 'script' && result.data) {
          logger.debug(TAG, `script操作返回数据类型: ${typeof result.data}`);
          logger.debug(TAG, `script操作返回数据内容: ${String(result.data).substring(0, 200)}`);
          
          if (typeof result.data === 'string') {
            try {
              let scriptResult = result.data as string;
              
              // 尝试第一次解析
              let parsed: Object = SafeUtils.parseObj(scriptResult);
              logger.debug(TAG, `第一次JSON解析: 类型=${typeof parsed}, 是否数组=${Array.isArray(parsed)}`);
              
              // 如果解析后还是字符串且以[或{开头，说明被双重字符串化了，需要再解析一次
              if (typeof parsed === 'string' && ((parsed as string).trim().startsWith('[') || (parsed as string).trim().startsWith('{'))) {
                logger.debug(TAG, `检测到双重字符串化，进行第二次解析`);
                parsed = SafeUtils.parseObj(parsed as string);
                logger.debug(TAG, `第二次JSON解析: 类型=${typeof parsed}, 是否数组=${Array.isArray(parsed)}`);
              }
              
              if (Array.isArray(parsed)) {
                // 直接返回数组
                const parsedArray = parsed as Array<Record<string, Object>>;
                pages = parsedArray.map((item: Record<string, Object>, index: number) => this.transformToPageInfo(item, index));
                logger.info(TAG, `script操作返回了 ${pages.length} 个页面`);
                logger.info(TAG, `📊 [MangaSourceEngine] 脚本返回的页面详情:`);
                pages.forEach((page, idx) => {
                  if (idx < 5) {
                    logger.info(TAG, `  - 页面${idx}: imageUrl=${page.imageUrl?.substring(0, 80)}, page=${page.page}`);
                  }
                });
              } else if (typeof parsed === 'object' && parsed !== null) {
                // 返回对象，检查是否包含 pages 字段
                const parsedObj = parsed as Record<string, Object>;
                if (parsedObj['pages'] && Array.isArray(parsedObj['pages'])) {
                  const pagesArray = parsedObj['pages'] as Array<Record<string, Object>>;
                  pages = pagesArray.map((item: Record<string, Object>, index: number) => this.transformToPageInfo(item, index));
                  logger.info(TAG, `script操作返回了对象，包含 ${pages.length} 个页面`);
                  
                  // 已移除非法的数组属性附加
                  
                  logger.info(TAG, `📊 [MangaSourceEngine] 脚本返回的页面详情:`);
                  pages.forEach((page, idx) => {
                    if (idx < 5) {
                      logger.info(TAG, `  - 页面${idx}: imageUrl=${page.imageUrl?.substring(0, 80)}, page=${page.page}`);
                    }
                  });
                } else {
                  logger.warn(TAG, `script返回的对象不包含有效的pages数组`);
                }
              } else {
                logger.warn(TAG, `script返回的不是数组或对象: ${typeof parsed}`);
              }
            } catch (e) {
              const errorMsg = e instanceof Error ? e.message : String(e);
              logger.error(TAG, `JSON解析失败: ${errorMsg}`);
            }
          } else {
            logger.warn(TAG, `script返回的不是字符串，无法解析为页面列表`);
          }
        }
        // 支持 extract 和 api 操作
        else if ((action.type === 'extract' || action.type === 'api') && result.data) {
          const resultData = result.data as Record<string, Object> | Array<Record<string, Object>>;
          const extractedData = Array.isArray(resultData) ? resultData : [resultData];
          pages = extractedData.map((item: Record<string, Object>, index: number) => this.transformToPageInfo(item, index));
        }
      }

      const duration = Date.now() - startTime;
      
      logger.info(TAG, `获取页面列表完成，共 ${pages.length} 页，耗时 ${duration}ms`);

      return {
        success: true,
        data: pages,
        duration,
        actionCount: actions.length
      };

    } catch (error) {
      const duration = Date.now() - startTime;
      const errorMessage = error instanceof Error ? error.message : String(error);
      
      logger.error(TAG, '获取页面列表失败' + error);
      
      return {
        success: false,
        error: errorMessage,
        duration,
        actionCount: 0
      };
    }
  }

  /**
   * 加载更多页面（用于动态翻页）
   */
  async loadMorePages(chapterId: string, mangaId?: string): Promise<EngineResult<Record<string, Object | undefined>>> {
    if (!this.config) {
      throw new MangaSourceError(
        MangaSourceErrorCode.CONFIG_NOT_LOADED,
        '配置未加载'
      );
    }

    const startTime = Date.now();
    logger.info(TAG, `加载更多页面: ${chapterId}`);

    try {
      const actions = this.configParser.buildLoadMorePagesActions(this.config, chapterId);
      const context = this.createActionContext();
      await this.populateSourceSettings(context);
      context.variables['useCookies'] = 'true';
      // 规范化URL
      if (mangaId) {
        context.variables['mangaId'] = this.normalizeUrl(mangaId);
      }
      context.variables['chapterId'] = this.normalizeUrl(chapterId);
      
      let resultData: Record<string, Object | undefined> = {};
      
      for (const action of actions) {
        logger.debug(TAG, `[loadMorePages] 执行操作: ${action.type}${action.type === 'script' ? ', code长度=' + (action.code?.length || 0) : ''}`);
        const result = await this.actionEngine.executeAction(action, context);
        
        if (!result.success) {
          throw new MangaSourceError(
            MangaSourceErrorCode.ACTION_FAILED,
            `加载更多页面操作失败: ${result.error}`
          );
        }

        // 保存最后一个script操作的结果，并解析JSON
        if (action.type === 'script' && result.data) {
          const scriptResult = result.data as string;
          logger.debug(TAG, `[loadMorePages] script返回数据类型=${typeof scriptResult}, 长度=${scriptResult.length}, 前100字符=${scriptResult.substring(0, 100)}`);
          
          // 尝试解析JSON字符串
          try {
            let parsed: Object = SafeUtils.parseObj(scriptResult);
            logger.debug(TAG, `loadMorePages JSON解析: 类型=${typeof parsed}, 是否对象=${typeof parsed === 'object'}`);
            
            // 如果解析后还是字符串，说明被双重字符串化了，需要再解析一次
            if (typeof parsed === 'string' && ((parsed as string).trim().startsWith('{') || (parsed as string).trim().startsWith('['))) {
              logger.debug(TAG, `检测到双重字符串化，进行第二次解析`);
              parsed = SafeUtils.parseObj(parsed as string);
              logger.debug(TAG, `第二次JSON解析: 类型=${typeof parsed}`);
            }
            
            if (typeof parsed === 'object' && parsed !== null) {
              resultData = parsed as Record<string, Object | undefined>;
              logger.debug(TAG, `loadMorePages解析结果: pages数量=${(resultData['pages'] as Array<Object>)?.length || 0}`);
            } else {
              logger.warn(TAG, `script返回的不是对象: ${typeof parsed}`);
              resultData = result.data as Record<string, Object | undefined>;
            }
          } catch (e) {
            logger.warn(TAG, `JSON解析失败，使用原始数据: ${e}`);
            resultData = result.data as Record<string, Object | undefined>;
          }
        }
      }

      const duration = Date.now() - startTime;
      logger.info(TAG, `加载更多页面完成，耗时 ${duration}ms`);

      return {
        success: true,
        data: resultData,
        duration,
        actionCount: actions.length
      };

    } catch (error) {
      const duration = Date.now() - startTime;
      const errorMessage = error instanceof Error ? error.message : String(error);
      
      logger.error(TAG, '加载更多页面失败: ' + error);
      
      return {
        success: false,
        error: errorMessage,
        duration,
        actionCount: 0
      };
    }
  }

  /**
   * 获取图片URL
   */
  async getImageUrl(pageIndex: number): Promise<EngineResult<string>> {
    if (!this.config) {
      throw new MangaSourceError(
        MangaSourceErrorCode.CONFIG_NOT_LOADED,
        '配置未加载'
      );
    }

    const startTime = Date.now();
    logger.info(TAG, `获取图片URL: 页面 ${pageIndex}`);

    try {
      const actions = this.configParser.buildImageUrlActions(this.config, pageIndex);
      const context = this.createActionContext();
      
      let imageUrl: string | undefined;
      
      for (const action of actions) {
        const result = await this.actionEngine.executeAction(action, context);
        
        if (!result.success) {
          throw new MangaSourceError(
            MangaSourceErrorCode.ACTION_FAILED,
            `获取图片URL操作失败: ${result.error}`
          );
        }

        if ((action.type === 'extract' || action.type === 'api') && result.data) {
          imageUrl = this.extractImageUrl(result.data);
        }
      }

      if (!imageUrl) {
        throw new MangaSourceError(
          MangaSourceErrorCode.DATA_NOT_FOUND,
          '未找到图片URL'
        );
      }

      const duration = Date.now() - startTime;
      
      logger.info(TAG, `获取图片URL完成: ${imageUrl}，耗时 ${duration}ms`);

      return {
        success: true,
        data: imageUrl,
        duration,
        actionCount: actions.length
      };

    } catch (error) {
      const duration = Date.now() - startTime;
      const errorMessage = error instanceof Error ? error.message : String(error);
      
      logger.error(TAG, '获取图片URL失败' + error);
      
      return {
        success: false,
        error: errorMessage,
        duration,
        actionCount: 0
      };
    }
  }

  /**
   * 测试配置
   */
  async testConfig(): Promise<EngineResult<Record<string, Object>>> {
    if (!this.config) {
      throw new MangaSourceError(
        MangaSourceErrorCode.CONFIG_NOT_LOADED,
        '配置未加载'
      );
    }

    const startTime = Date.now();
    logger.info(TAG, '开始测试配置');

    const testResults: TestResults = {
      config: this.convertConfigSummaryToRecord(this.configParser.getConfigSummary(this.config)),
      tests: {}
    };

    try {
      // 测试基础连接
      const context = this.createActionContext();
      const navigateAction: Action = {
        type: ActionType.NAVIGATE,
        url: this.config.metadata.baseUrl,
        waitFor: WaitCondition.LOAD,
        timeout: 10000
      };

      const navigateResult = await this.actionEngine.executeAction(navigateAction, context);
      const navigationResult: NavigationTestResult = {
        success: navigateResult.success,
        duration: navigateResult.duration,
        error: navigateResult.error
      };
      (testResults.tests as Record<string, Object>)['navigation'] = navigationResult;

      const duration = Date.now() - startTime;
      
      logger.info(TAG, `配置测试完成，耗时 ${duration}ms`);

      return {
        success: true,
        data: this.convertTestResultsToRecord(testResults),
        duration,
        actionCount: 1
      };

    } catch (error) {
      const duration = Date.now() - startTime;
      const errorMessage = error instanceof Error ? error.message : String(error);
      
      logger.error(TAG, '配置测试失败' + error);
      
      return {
        success: false,
        error: errorMessage,
        duration,
        actionCount: 0
      };
    }
  }

  /**
   * 转换TestResults为Record类型
   */
  private convertTestResultsToRecord(testResults: TestResults): TestResultsRecord {
    return {
      config: testResults.config,
      tests: testResults.tests
    };
  }

  /**
   * 转换ConfigSummaryResult为Record类型
   */
  private convertConfigSummaryToRecord(summary: ConfigSummaryResult | undefined): ConfigSummaryRecord {
    if (!summary) {
      return {
        name: '',
        version: '',
        baseUrl: '',
        author: '',
        description: '',
        workflowCount: 0,
        workflows: [],
        settings: {
          timeout: 30000,
          retryCount: 3,
          userAgent: 'MangaReader/1.0'
        }
      };
    }
    
    return {
      name: summary.name,
      version: summary.version,
      baseUrl: summary.baseUrl,
      author: summary.author,
      description: summary.description,
      workflowCount: summary.workflowCount,
      workflows: summary.workflows,
      settings: summary.settings
    };
  }

  /**
   * 创建操作上下文
   */
  private createActionContext(): ActionContext {
    const variables: Record<string, string> = {};
    
    // 从配置中初始化基础变量
    if (this.config) {
      variables['baseUrl'] = this.config.metadata.baseUrl;
      logger.debug(TAG, `初始化baseUrl变量: ${variables['baseUrl']}`);

      // [优化] 使用缓存的 parsed config
      const rawConfig = this.getParsedConfig();
      if (rawConfig) {
        try {
          if (rawConfig['api']) {
            const apiConfig = rawConfig['api'] as Record<string, Object>;
            if (apiConfig['endpoint']) {
              variables['api.endpoint'] = apiConfig['endpoint'] as string;
              logger.debug(TAG, `初始化api.endpoint变量: ${variables['api.endpoint']}`);
            }
          if (apiConfig['headers']) {
              variables['api.headers'] = JSON.stringify(apiConfig['headers']);
              logger.debug(TAG, `初始化api.headers变量`);
            }
          }
          // [修复] 读取 network.headers 配置，传递给 ActionEngine
          if (rawConfig['network']) {
            const networkConfig = rawConfig['network'] as Record<string, Object>;
            if (networkConfig['headers']) {
              variables['__networkHeaders__'] = JSON.stringify(networkConfig['headers']);
              logger.debug(TAG, `初始化network.headers变量: ${variables['__networkHeaders__']}`);
            }
            if (networkConfig['userAgent']) {
              variables['__networkUserAgent__'] = networkConfig['userAgent'] as string;
              logger.debug(TAG, `初始化network.userAgent变量`);
            }
          }
        } catch (e) {
          logger.warn(TAG, `解析API配置失败: ${e}`);
        }
      }
      
      // 如果配置中定义了自定义变量，也添加进来
      if (this.config.variables) {
        const varKeys = Object.keys(this.config.variables);
        for (let i = 0; i < varKeys.length; i++) {
          const key = varKeys[i];
          variables[key] = this.config.variables[key];
        }
        logger.debug(TAG, `加载了 ${varKeys.length} 个自定义变量`);
      }
    }

    // 注入源级设置与登录信息（如果提供了sourceId）
    if (this.engineConfig.sourceId !== undefined) {
      const sid: number = this.engineConfig.sourceId as number;
      variables['sourceId'] = String(sid);
    }
    
    return {
      webViewController: this.engineConfig.webViewController,
      variables: variables
    };
  }

  /**
   * 规范化URL - 确保URL是完整的绝对URL
   * 如果传入的是相对路径，则拼接baseUrl
   * 如果已经是完整URL，则直接返回
   */
  private normalizeUrl(url: string): string {
    if (!url) {
      return url;
    }
    
    // 如果已经是完整URL（以http://或https://开头），直接返回
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    
    // 获取baseUrl
    const baseUrl = this.config?.metadata?.baseUrl || '';
    if (!baseUrl) {
      logger.warn(TAG, `无法规范化URL，baseUrl为空: ${url}`);
      return url;
    }
    
    // 拼接baseUrl和相对路径
    // 确保不会出现双斜杠
    if (url.startsWith('/')) {
      // 相对路径以/开头，直接拼接
      const normalizedUrl = baseUrl.replace(/\/$/, '') + url;
      logger.debug(TAG, `URL规范化: ${url} -> ${normalizedUrl}`);
      return normalizedUrl;
    } else {
      // 相对路径不以/开头，添加/
      const normalizedUrl = baseUrl.replace(/\/$/, '') + '/' + url;
      logger.debug(TAG, `URL规范化: ${url} -> ${normalizedUrl}`);
      return normalizedUrl;
    }
  }

  /**
   * 转换为漫画信息
   */
  private transformToMangaInfo(data: Object): MangaInfo {
    const item = data as Record<string, Object>;
    
    // 输出提取到的字段以便调试
    const keys = Object.keys(item);
    logger.debug(TAG, `提取到的字段: ${keys.join(', ')}`);
    logger.debug(TAG, `原始id值: ${item.id}, 类型: ${typeof item.id}`);
    
    // 输出图片调试信息（如果有）
    if (item._imgDebug) {
      logger.info(TAG, `🖼️ 图片提取调试信息: ${item._imgDebug}`);
    }
    
    // 特殊处理 PicaComic 的 thumb 对象
    // PicaComic API 返回 thumb: { fileServer: "...", path: "...", originalName: "..." }
    let coverUrl = String(item.cover || '');
    if (!coverUrl && item.thumb && typeof item.thumb === 'object') {
      const thumb = item.thumb as Record<string, string>;
      if (thumb.fileServer && thumb.path) {
        coverUrl = `${thumb.fileServer}/static/${thumb.path}`;
        logger.debug(TAG, `生成 PicaComic 封面: ${coverUrl}`);
      }
    }

    // 处理状态 (PicaComic finished 是 boolean)
    let status = String(item.status || '');
    if (item.finished !== undefined) {
      status = item.finished ? 'completed' : 'ongoing';
    }

    // 处理标签 (合并 genres, categories, tags, genre)
    let genres: string[] = [];
    if (item.genres && Array.isArray(item.genres)) {
      genres = item.genres as string[];
    }
    if (item.categories && Array.isArray(item.categories)) {
      genres = genres.concat(item.categories as string[]);
    }
    if (item.tags && Array.isArray(item.tags)) {
      genres = genres.concat(item.tags as string[]);
    }
    // 支持 genre 字符串（逗号分隔），如 Manwa 返回的格式
    if (item.genre && typeof item.genre === 'string') {
      const genreStr = item.genre as string;
      const genreArr = genreStr.split(',').map((s: string) => s.trim()).filter((s: string) => s.length > 0);
      genres = genres.concat(genreArr);
    }
    // 去重
    if (genres.length > 0) {
      genres = Array.from(new Set(genres));
    }
    
    const manga: MangaInfo = {
      id: String(item.id || ''),
      title: String(item.title || ''),
      author: String(item.author || ''),
      description: String(item.description || ''),
      cover: coverUrl,
      status: status,
      url: String(item.url || item.id || ''),  // 如果没有url，使用id
      genres: genres.length > 0 ? genres : undefined,
      updated: item.updated ? String(item.updated) : undefined
    };
    
    logger.debug(TAG, `转换MangaInfo: id="${manga.id}", title="${manga.title}", cover="${manga.cover}"`);
    
    return manga;
  }

  /**
   * 转换为章节信息
   */
  private transformToChapterInfo(data: Object): ChapterInfo {
    const item = data as Record<string, Object>;
    
    // 输出提取到的字段以便调试
    const keys = Object.keys(item);
    logger.debug(TAG, `章节提取到的字段: ${keys.join(', ')}`);
    
    // [关键修复] 提取外部ID - 这是从API返回的原始章节ID
    const externalId = String(item.id || '');
    if (!externalId) {
      logger.error(TAG, `❌ 严重错误：章节数据缺少id字段！数据: ${JSON.stringify(item)}`);
      throw new Error('章节数据必须包含id字段作为外部ID');
    }
    
    // 支持多种时间字段名称: publishTime, updateTime, updated_at
    const timeValue = item.publishTime || item.updateTime || item.updated_at;
    logger.debug(TAG, `📋 章节原始数据: externalId=${externalId}, title=${item.title}, timeValue=${timeValue}`);
    
    // 转换时间戳：如果是Unix时间戳（秒），需要乘以1000转换为毫秒
    let publishTimeStr = '';
    if (timeValue) {
      const raw = String(timeValue);
      const num = Number(raw);
      if (!Number.isNaN(num)) {
        if (num > 0 && num < 10000000000) {
          publishTimeStr = String(num * 1000);
        } else {
          publishTimeStr = String(num);
        }
      } else {
        const parsed = Date.parse(raw);
        if (!Number.isNaN(parsed)) {
          publishTimeStr = String(parsed);
        }
      }
    }

    let pageCountVal: number | undefined = undefined;
    if (item.size) {
      const sz = Number(item.size);
      if (!Number.isNaN(sz) && sz > 0) {
        pageCountVal = sz;
      }
    }
    
    // [关键修复] 章节信息结构：
    // - id: 暂时使用externalId，稍后在存储到数据库时会被替换为内部ID
    // - externalId: 保存原始的外部ID（从API获取的ID）
    const chapter: ChapterInfo = {
      id: externalId,  // 临时使用外部ID，存储时会生成新的内部ID
      title: String(item.title || ''),
      url: String(item.url || item.id || ''),
      publishTime: publishTimeStr,
      externalId: externalId  // [关键] 保存外部ID
    } as ChapterInfo;
    
    if (pageCountVal !== undefined) {
      chapter.pageCount = pageCountVal;
    }
    
    logger.info(TAG, `✅ 章节转换完成: title="${chapter.title}", externalId=${chapter.externalId}`);
    
    return chapter;
  }

  /**
   * 转换为页面信息
   */
  private transformToPageInfo(data: Object, index: number): PageInfo {
    const item = data as Record<string, Object>;
    
    // 如果有kid字段但没有imageUrl，构建完整的图片URL（用于Komiic API等）
    let imageUrl = String(item.imageUrl || item.url || '');
    if (!imageUrl && item.kid) {
      imageUrl = `https://komiic.com/api/image/${item.kid}`;
    }
    
    // 特殊处理 PicaComic 的 media 对象
    // PicaComic API 返回 media: { fileServer: "...", path: "...", originalName: "..." }
    if (!imageUrl && item.media && typeof item.media === 'object') {
      const media = item.media as Record<string, string>;
      if (media.fileServer && media.path) {
        imageUrl = `${media.fileServer}/static/${media.path}`;
        logger.debug(TAG, `生成 PicaComic 图片URL: ${imageUrl}`);
      }
    }

    const pageInfo: PageInfo = {
      page: index,
      imageUrl: imageUrl
    };

    const widthValue: number = Number(item.width);
    if (!Number.isNaN(widthValue) && widthValue > 0) {
      pageInfo.width = widthValue;
    }

    const heightValue: number = Number(item.height);
    if (!Number.isNaN(heightValue) && heightValue > 0) {
      pageInfo.height = heightValue;
    }

    const imageTicket: string = item.ticket ? String(item.ticket) : '';
    if (imageTicket.length > 0) {
      const headers: PageRequestHeader[] = [];
      headers.push({
        name: 'X-Image-Ticket',
        value: imageTicket
      } as PageRequestHeader);
      pageInfo.requestHeaders = headers;
      logger.debug(TAG, `页面 ${index} 添加 X-Image-Ticket 请求头`);
    }

    return pageInfo;
  }

  /**
   * 提取图片URL
   */
  private extractImageUrl(data: Object): string {
    if (typeof data === 'string') {
      return data;
    }
    
    const item = data as Record<string, Object>;
    return String(item.imageUrl || item.url || item.src || '');
  }

  /**
   * [优化] 获取解析后的 rawConfigJson，带缓存
   */
  private getParsedConfig(): Record<string, Object> | null {
    if (this.parsedConfigCache) {
      return this.parsedConfigCache;
    }
    if (!this.rawConfigJson) {
      return null;
    }
    try {
      this.parsedConfigCache = SafeUtils.parseObj(this.rawConfigJson) as Record<string, Object>;
      return this.parsedConfigCache;
    } catch (e) {
      logger.warn(TAG, `解析 rawConfigJson 失败: ${e}`);
      return null;
    }
  }

  /**
   * [优化] 清除引擎内部缓存（在源配置更新时调用）
   */
  clearEngineCache(): void {
    this.sourceSettingsCache.clear();
    this.parsedConfigCache = null;
    logger.debug(TAG, '引擎内部缓存已清除');
  }

  /**
   * 填充源级设置与登录变量到上下文
   */
  private async populateSourceSettings(context: ActionContext): Promise<void> {
    const sidStr = this.engineConfig.sourceId !== undefined ? String(this.engineConfig.sourceId as number) : '';
    if (!sidStr) {
      return;
    }
    const sid: number = Number(sidStr);

    // [优化] 检查缓存
    const cached = this.sourceSettingsCache.get(sidStr);
    if (cached && (Date.now() - cached.timestamp) < MangaSourceEngine.SOURCE_SETTINGS_CACHE_TTL_MS) {
      const cachedKeys = Object.keys(cached.variables);
      for (let i = 0; i < cachedKeys.length; i++) {
        context.variables[cachedKeys[i]] = cached.variables[cachedKeys[i]];
      }
      logger.debug(TAG, `populateSourceSettings 缓存命中，注入 ${cachedKeys.length} 个变量`);
      // Token 和 credentials 仍需每次注入（可能在会话中变化）
      if (this.currentToken) {
        context.variables['token'] = this.currentToken;
      }
      return;
    }

    // 缓存未命中，执行完整加载
    const variablesSnapshot: Record<string, string> = {};
    try {
      const creds = await this.dataManager.getSourceCredentials(sid);
      if (creds) {
        context.variables['login.username'] = creds.username;
        context.variables['login.password'] = creds.password;
      }
      const s1: UserSettingsDatabaseRecord | null = await this.dataManager.getSourceUserSetting(sid, 'homeItemsPerPage');
      const s2: UserSettingsDatabaseRecord | null = await this.dataManager.getSourceUserSetting(sid, 'readerPreloadCount');
      const s3: UserSettingsDatabaseRecord | null = await this.dataManager.getSourceUserSetting(sid, 'preloadCurrentChapter');
      const s4: UserSettingsDatabaseRecord | null = await this.dataManager.getSourceUserSetting(sid, 'preloadNextChapter');
      const s5: UserSettingsDatabaseRecord | null = await this.dataManager.getSourceUserSetting(sid, 'downloadWhileReading');
      if (s1 && s1.settingValue) { context.variables['pageSize'] = String(s1.settingValue); }
      if (s2 && s2.settingValue) { context.variables['reader.preloadCount'] = String(s2.settingValue); }
      if (s3 && s3.settingValue) { context.variables['reader.preloadCurrent'] = s3.settingValue; }
      if (s4 && s4.settingValue) { context.variables['reader.preloadNext'] = s4.settingValue; }
      if (s5 && s5.settingValue) { context.variables['reader.downloadWhileReading'] = s5.settingValue; }

      // [修复] 加载图源特定设置（如哔咔漫画的 appChannel 和 imageQuality）
      const appChannelSetting: UserSettingsDatabaseRecord | null = await this.dataManager.getSourceUserSetting(sid, 'appChannel');
      const imageQualitySetting: UserSettingsDatabaseRecord | null = await this.dataManager.getSourceUserSetting(sid, 'imageQuality');
      
      // 设置默认值，确保即使用户未配置也能正常工作
      context.variables['appChannel'] = (appChannelSetting && appChannelSetting.settingValue) ? String(appChannelSetting.settingValue) : '2';
      context.variables['imageQuality'] = (imageQualitySetting && imageQualitySetting.settingValue) ? String(imageQualitySetting.settingValue) : 'high';
      
      logger.debug(TAG, `图源设置: appChannel=${context.variables['appChannel']}, imageQuality=${context.variables['imageQuality']}`);

      // [修复] 加载图源自定义设置（如 domain、API选项等）
      // 首先从 source.json 中加载设置的默认值
      const rawConfig1 = this.getParsedConfig();
      if (rawConfig1) {
        try {
          if (rawConfig1['settings']) {
            const settingsConfig = rawConfig1['settings'] as Record<string, Object>;
            const settingKeys = Object.keys(settingsConfig);
            for (let i = 0; i < settingKeys.length; i++) {
              const settingKey = settingKeys[i];
              const settingDef = settingsConfig[settingKey] as Record<string, Object>;
              if (settingDef && settingDef['default'] !== undefined) {
                // 设置默认值，稍后会被用户保存的值覆盖
                context.variables[settingKey] = String(settingDef['default']);
                logger.debug(TAG, `设置默认值: ${settingKey}=${settingDef['default']}`);
              }
            }
          }
        } catch (e) {
          logger.warn(TAG, `解析设置默认值失败: ${e}`);
        }
      }
      
      // 然后加载用户保存的自定义设置（覆盖默认值）
      const customSettings = await this.dataManager.getSourceCustomSettings(sid);
      if (customSettings.size > 0) {
        customSettings.forEach((value: string, key: string) => {
          context.variables[key] = value;
          logger.debug(TAG, `注入自定义设置: ${key}=${value}`);
        });
        logger.info(TAG, `已加载 ${customSettings.size} 个自定义设置到上下文`);
      }

      // [修复] 解析 apiDomain 设置键到实际的 domain URL
      // apiDomain 可能存储的是:
      // 1. 键名如 "copy20", "mangacopy" - 需要从 alternativeUrls 查找
      // 2. 直接的 URL 如 "https://api.manga2025.com" - 直接使用
      const rawConfig2 = this.getParsedConfig();
      if (rawConfig2 && context.variables['apiDomain']) {
        try {
          const metadata = rawConfig2['metadata'] as Record<string, Object>;
          const apiDomainValue = context.variables['apiDomain'];
          let resolvedDomain: string = '';
          
          // 首先检查是否已经是完整的 URL
          if (apiDomainValue.startsWith('http://') || apiDomainValue.startsWith('https://')) {
            resolvedDomain = apiDomainValue;
            // 移除末尾的斜杠
            if (resolvedDomain.endsWith('/')) {
              resolvedDomain = resolvedDomain.slice(0, -1);
            }
            logger.info(TAG, `apiDomain 已是完整URL: ${resolvedDomain}`);
          } else {
            // 尝试从 alternativeUrls 查找
            if (metadata && metadata['alternativeUrls']) {
              const altUrls = metadata['alternativeUrls'] as Record<string, string>;
              if (altUrls[apiDomainValue]) {
                resolvedDomain = altUrls[apiDomainValue];
                logger.info(TAG, `解析 apiDomain: ${apiDomainValue} -> ${resolvedDomain}`);
              }
            }
          }
          
          // 如果没找到，使用 baseUrl 作为 fallback
          if (!resolvedDomain && metadata && metadata['baseUrl']) {
            resolvedDomain = String(metadata['baseUrl']);
            // 移除末尾的斜杠
            if (resolvedDomain.endsWith('/')) {
              resolvedDomain = resolvedDomain.slice(0, -1);
            }
            logger.info(TAG, `apiDomain 未匹配，使用 baseUrl: ${resolvedDomain}`);
          }
          
          // 设置 domain 变量（用于 URL 模板替换）
          if (resolvedDomain) {
            context.variables['domain'] = resolvedDomain;
            logger.info(TAG, `设置 domain 变量: ${resolvedDomain}`);
          }
        } catch (e) {
          logger.warn(TAG, `解析 apiDomain 失败: ${e}`);
        }
      } else if (rawConfig2 && !context.variables['domain']) {
        // 如果没有 apiDomain 设置但也没有 domain，使用 baseUrl
        try {
          const metadata = rawConfig2['metadata'] as Record<string, Object>;
          if (metadata && metadata['baseUrl']) {
            let baseUrl = String(metadata['baseUrl']);
            if (baseUrl.endsWith('/')) {
              baseUrl = baseUrl.slice(0, -1);
            }
            context.variables['domain'] = baseUrl;
            logger.info(TAG, `使用 baseUrl 作为 domain: ${baseUrl}`);
          }
        } catch (e) {
          logger.warn(TAG, `解析 baseUrl 失败: ${e}`);
        }
      }

      // [修复] 优先使用当前会话的 Token（登录成功后立即可用）
      if (this.currentToken) {
        context.variables['token'] = this.currentToken;
        logger.info(TAG, `使用当前会话Token: length=${this.currentToken.length}`);
      } else if (this.config && this.config.authentication && this.config.authentication.type === 'jwt' && this.config.authentication.tokenStorageKey) {
        // 如果当前会话没有 Token，尝试从数据库加载
        const tokenKey: string = this.config.authentication.tokenStorageKey;
        // 使用 sourceId + tokenKey 作为唯一的存储键
        const storageKey: string = `source:${String(sid)}:${tokenKey}`;
        
        // 使用username作为userId，如果未登录则使用default_user
        let userId: string = 'default_user';
        if (creds && creds.username) {
          userId = creds.username;
        }
        
        const savedToken = await this.dataManager.getUserSetting(userId, storageKey);
        if (savedToken) {
          // 移除可能存在的引号
          let cleanToken: string = savedToken;
          if (cleanToken.startsWith('"') && cleanToken.endsWith('"')) {
            cleanToken = cleanToken.substring(1, cleanToken.length - 1);
          }
          context.variables['token'] = cleanToken;
          // 同时设置到当前会话，避免重复加载
          this.currentToken = cleanToken;
          logger.info(TAG, `已加载保存的Token: key=${storageKey}, length=${cleanToken.length}`);
        } else {
          logger.debug(TAG, `未找到保存的Token: key=${storageKey}`);
        }
      }

      // [优化] 将结果存入缓存（排除会话级变量 token 和 credentials）
      const cacheVars: Record<string, string> = {};
      const varKeys = Object.keys(context.variables);
      for (let i = 0; i < varKeys.length; i++) {
        const k = varKeys[i];
        if (k !== 'token' && k !== 'login.username' && k !== 'login.password') {
          cacheVars[k] = context.variables[k];
        }
      }
      const settingsEntry: SourceSettingsCacheEntry = { variables: cacheVars, timestamp: Date.now() };
      this.sourceSettingsCache.set(sidStr, settingsEntry);
      logger.debug(TAG, `populateSourceSettings 结果已缓存，${Object.keys(cacheVars).length} 个变量`);
    } catch (error) {
      logger.warn(TAG, `填充源设置失败: ${String(error)}`);
    }
  }

  /**
   * 获取WebView的UserAgent
   */
  private async getUserAgent(): Promise<string> {
    return new Promise<string>((resolve, reject) => {
      try {
        // [修复] 添加超时机制，防止WebView未就绪时无限等待
        const timeout = setTimeout(() => {
          reject(new Error('WebView UserAgent获取超时'));
        }, 3000); // 3秒超时
        
        this.engineConfig.webViewController.runJavaScript(
          'navigator.userAgent',
          (error, result) => {
            clearTimeout(timeout);
            if (error) {
              reject(new Error(`获取UserAgent失败: ${error.message}`));
              return;
            }
            resolve(result as string);
          }
        );
      } catch (error) {
        reject(error);
      }
    });
  }

  public async getWebViewUserAgent(): Promise<string> {
    try {
      const ua: string = await this.getUserAgent();
      return ua;
    } catch (error) {
      // [修复] 如果WebView获取失败，返回默认UserAgent
      logger.warn(TAG, `WebView UserAgent获取失败，使用默认值: ${error}`);
      return 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36';
    }
  }

  /**
   * 获取WebView当前URL
   */
  public async getCurrentUrl(): Promise<string> {
    return new Promise<string>((resolve, reject) => {
      try {
        const timeout = setTimeout(() => {
          reject(new Error('WebView URL获取超时'));
        }, 3000);
        
        this.engineConfig.webViewController.runJavaScript(
          'location.href',
          (error, result) => {
            clearTimeout(timeout);
            if (error) {
              reject(new Error(`获取URL失败: ${error.message}`));
              return;
            }
            // 结果可能带引号，需要去掉
            let url = String(result);
            if (url.startsWith('"') && url.endsWith('"')) {
              url = url.slice(1, -1);
            }
            resolve(url);
          }
        );
      } catch (error) {
        reject(error);
      }
    });
  }

  /**
   * 获取当前配置
   */
  getConfig(): MangaSourceConfig | undefined {
    return this.config;
  }

  /**
   * 获取配置摘要
   */
  getConfigSummary(): ConfigSummaryResult | undefined {
    return this.config ? this.configParser.getConfigSummary(this.config) : undefined;
  }

  /**
   * 执行初始化工作流（如果存在）
   */
  private async runInitializeWorkflowIfPresent(): Promise<void> {
    if (!this.config) {
      return;
    }
    const actions = this.configParser.getWorkflow(this.config, 'initialize');
    if (!actions || actions.length === 0) {
      return;
    }
    logger.info(TAG, `检测到initialize工作流，开始执行，共 ${actions.length} 个操作`);
    const context = this.createActionContext();
    await this.populateSourceSettings(context);
    context.variables['useCookies'] = 'true';
    for (let i = 0; i < actions.length; i++) {
      const action = actions[i];
      const result = await this.actionEngine.executeAction(action, context);
      if (!result.success) {
        throw new MangaSourceError(
          MangaSourceErrorCode.ACTION_FAILED,
          `初始化操作失败: ${result.error}`
        );
      }
    }
    logger.info(TAG, 'initialize工作流执行完成');
  }

  /**
   * 执行登录工作流
   */
  async executeLogin(username: string, password: string): Promise<EngineResult<string>> {
    if (!this.config) {
      logger.error(TAG, '配置未加载，无法执行登录');
      throw new MangaSourceError(
        MangaSourceErrorCode.CONFIG_NOT_LOADED,
        '配置未加载'
      );
    }

    const startTime = Date.now();
    logger.info(TAG, `开始执行登录工作流: username=${username}`);

    try {
      // 获取login工作流
      const actions = this.configParser.getWorkflow(this.config, 'login');
      if (!actions || actions.length === 0) {
        logger.warn(TAG, '未找到login工作流');
        return {
          success: false,
          error: '图源不支持login工作流',
          duration: Date.now() - startTime,
          actionCount: 0
        };
      }

      logger.debug(TAG, `login工作流包含 ${actions.length} 个操作`);

      // 创建执行上下文
      const context = this.createActionContext();
      await this.populateSourceSettings(context);
      context.variables['username'] = username;
      context.variables['password'] = password;
      context.variables['useCookies'] = 'false';
      logger.debug(TAG, `执行上下文变量: ${JSON.stringify(context.variables)}`);

      let tokenData: string | undefined = undefined;

      // 执行login操作序列
      for (let i = 0; i < actions.length; i++) {
        const action = actions[i];
        logger.debug(TAG, `执行登录操作 ${i + 1}/${actions.length}: ${action.type}`);

        const result = await this.actionEngine.executeAction(action, context);

        logger.debug(TAG, `登录操作 ${i + 1} 结果: success=${result.success}, hasData=${!!result.data}`);

        if (!result.success) {
          logger.error(TAG, `登录操作 ${i + 1} 失败: ${result.error}`);
          throw new MangaSourceError(
            MangaSourceErrorCode.ACTION_FAILED,
            `登录操作失败: ${result.error}`
          );
        }

        // 如果操作返回了数据（token），保存它
        if (result.data && typeof result.data === 'string') {
          tokenData = result.data;
          logger.debug(TAG, `获取到token数据，长度: ${tokenData.length}`);
          
          // [修复] 立即设置当前会话的 Token，确保后续请求能立即使用
          this.currentToken = tokenData;
          logger.info(TAG, `Token已设置到当前会话: length=${tokenData.length}`);
          
          // [修复] 自动保存Token到数据库
          if (this.config && this.config.authentication && this.config.authentication.type === 'jwt' && this.config.authentication.tokenStorageKey) {
            const tokenKey: string = this.config.authentication.tokenStorageKey;
            const sidStr: string = this.engineConfig.sourceId !== undefined ? String(this.engineConfig.sourceId) : '';
            
            if (sidStr.length > 0) {
              const storageKey: string = `source:${sidStr}:${tokenKey}`;
              const userId: string = username || 'default_user';
              
              try {
                // 注意：DataManager的saveUserSetting是异步的，这里await确保保存完成
                await this.dataManager.saveUserSetting(userId, storageKey, tokenData);
                logger.info(TAG, `Token已保存到数据库: key=${storageKey}`);
              } catch (saveErr) {
                logger.error(TAG, `保存Token失败: ${saveErr}`);
              }
            }
          }
        }
      }

      const duration = Date.now() - startTime;
      logger.info(TAG, `登录工作流执行完成，耗时 ${duration}ms`);

      return {
        success: true,
        data: tokenData,
        duration,
        actionCount: actions.length
      };

    } catch (error) {
      const duration = Date.now() - startTime;
      const errorMessage = error instanceof Error ? error.message : String(error);
      const errorStack = error instanceof Error ? error.stack : '';

      logger.error(TAG, `登录工作流执行失败: ${errorMessage}`);
      logger.debug(TAG, `错误堆栈: ${errorStack}`);

      return {
        success: false,
        error: errorMessage,
        duration,
        actionCount: 0
      };
    }
  }

  // ==================== 任务系统方法 ====================

  /**
   * 注册任务和工作流（从配置JSON中解析）
   */
  registerTasksFromConfig(): void {
    if (!this.rawConfigJson || !this.taskExecutor) {
      logger.warn(TAG, '无法注册任务：配置或任务执行器未初始化');
      return;
    }

    try {
      const configObj = SafeUtils.parseObj(this.rawConfigJson) as Record<string, Object | undefined>;
      
      // 注册工作流
      const workflows = configObj['workflows'] as Record<string, Object | undefined> | undefined;
      if (workflows) {
        const workflowNames = Object.keys(workflows);
        for (let i = 0; i < workflowNames.length; i++) {
          const name = workflowNames[i];
          const workflow: Object | undefined = workflows[name];
          if (workflow && typeof workflow === 'object') {
            const workflowObj = workflow as Record<string, Object | undefined>;
            const actions = workflowObj['actions'] as Action[] | undefined;
            if (actions && Array.isArray(actions)) {
              this.taskExecutor.registerWorkflow(name, actions);
            }
          }
        }
      }

      // 注册任务
      const tasks = configObj['tasks'] as Record<string, TaskDefinition> | undefined;
      if (tasks) {
        this.taskExecutor.registerTasks(tasks);
        logger.info(TAG, `已注册 ${Object.keys(tasks).length} 个任务`);
      }

    } catch (error) {
      logger.error(TAG, `注册任务失败: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  /**
   * 执行任务
   * @param taskId 任务ID
   * @param params 初始参数
   */
  async executeTask(taskId: string, params?: Record<string, Object | undefined>): Promise<TaskResult> {
    if (!this.taskExecutor) {
      return {
        taskId,
        success: false,
        error: '任务执行器未初始化',
        duration: 0,
        stepResults: {}
      };
    }

    // 确保任务已注册
    this.registerTasksFromConfig();

    // 添加基础变量
    const fullParams: Record<string, Object | undefined> = {};
    fullParams['baseUrl'] = this.config?.metadata?.baseUrl || '';
    fullParams['sourceId'] = String(this.engineConfig.sourceId || '');
    if (params) {
      const paramKeys = Object.keys(params);
      for (let i = 0; i < paramKeys.length; i++) {
        const key = paramKeys[i];
        fullParams[key] = params[key];
      }
    }

    logger.info(TAG, `执行任务: ${taskId}, 参数: ${JSON.stringify(fullParams)}`);
    return await this.taskExecutor.executeTask(taskId, fullParams);
  }

  /**
   * 获取下载源列表（电子书专用）
   * @param bookId 书籍ID
   */
  async getDownloadSources(bookId: string): Promise<EngineResult<Object[]>> {
    const startTime = Date.now();
    
    try {
      const taskParams: Record<string, Object | undefined> = {};
      taskParams['bookId'] = bookId;
      const result = await this.executeTask('getDownloadSources', taskParams);
      
      if (result.success && result.data) {
        let sources: Object[] = [];
        if (typeof result.data === 'string') {
          const parsed: Object = SafeUtils.parseObj(result.data) as Object;
          if (Array.isArray(parsed)) {
            sources = parsed as Object[];
          } else if (parsed && typeof parsed === 'object') {
            const parsedRecord: Record<string, Object | undefined> = parsed as Record<string, Object | undefined>;
            if (Array.isArray(parsedRecord['sources'])) {
              sources = parsedRecord['sources'] as Object[];
            }
          }
        } else if (Array.isArray(result.data)) {
          sources = result.data;
        } else if (result.data && typeof result.data === 'object') {
          const dataRecord: Record<string, Object | undefined> = result.data as Record<string, Object | undefined>;
          if (Array.isArray(dataRecord['sources'])) {
            sources = dataRecord['sources'] as Object[];
          }
        }

        return {
          success: true,
          data: sources,
          duration: Date.now() - startTime,
          actionCount: Object.keys(result.stepResults).length
        };
      }

      return {
        success: false,
        error: result.error || '获取下载源失败',
        duration: Date.now() - startTime,
        actionCount: 0
      };

    } catch (error) {
      return {
        success: false,
        error: error instanceof Error ? error.message : String(error),
        duration: Date.now() - startTime,
        actionCount: 0
      };
    }
  }

  /**
   * 从下载源获取文件列表（电子书专用）
   * @param sourceUrl 下载源URL
   */
  async getFileListFromSource(sourceUrl: string): Promise<EngineResult<Object[]>> {
    const startTime = Date.now();
    
    try {
      const taskParams: Record<string, Object | undefined> = {};
      taskParams['sourceUrl'] = sourceUrl;
      const result = await this.executeTask('getFileListFromSource', taskParams);
      
      if (result.success && result.data) {
        let files: Object[] = [];
        if (typeof result.data === 'string') {
          const parsed: Object = SafeUtils.parseObj(result.data) as Object;
          if (Array.isArray(parsed)) {
            files = parsed as Object[];
          } else if (parsed && typeof parsed === 'object') {
            const parsedRecord: Record<string, Object | undefined> = parsed as Record<string, Object | undefined>;
            if (Array.isArray(parsedRecord['files'])) {
              files = parsedRecord['files'] as Object[];
            }
          }
        } else if (Array.isArray(result.data)) {
          files = result.data;
        } else if (result.data && typeof result.data === 'object') {
          const dataRecord: Record<string, Object | undefined> = result.data as Record<string, Object | undefined>;
          if (Array.isArray(dataRecord['files'])) {
            files = dataRecord['files'] as Object[];
          }
        }

        return {
          success: true,
          data: files,
          duration: Date.now() - startTime,
          actionCount: Object.keys(result.stepResults).length
        };
      }

      return {
        success: false,
        error: result.error || '获取文件列表失败',
        duration: Date.now() - startTime,
        actionCount: 0
      };

    } catch (error) {
      return {
        success: false,
        error: error instanceof Error ? error.message : String(error),
        duration: Date.now() - startTime,
        actionCount: 0
      };
    }
  }

  /**
   * 取消正在执行的任务
   * @param taskId 任务ID
   */
  cancelTask(taskId: string): boolean {
    if (!this.taskExecutor) {
      return false;
    }
    return this.taskExecutor.cancelTask(taskId);
  }

  /**
   * 恢复等待中的任务（用户交互完成后）
   * @param taskId 任务ID
   * @param userInput 用户输入的数据
   */
  async resumeTask(taskId: string, userInput?: Record<string, Object | undefined>): Promise<void> {
    if (this.taskExecutor) {
      await this.taskExecutor.resumeTask(taskId, userInput);
    }
  }

  /**
   * 获取任务执行器（供外部直接使用）
   */
  getTaskExecutor(): TaskExecutor | null {
    return this.taskExecutor;
  }

  /**
   * 智能章节排序
   * 优先级：number字段 > externalId数字 > 标题中提取的数字 > 原始顺序
   * @param chapters 待排序的章节列表
   * @returns 排序后的章节列表
   */
  private sortChaptersIntelligently(chapters: ChapterInfo[]): ChapterInfo[] {
    if (chapters.length <= 1) {
      return chapters;
    }

    // 为每个章节计算排序权重
    interface ChapterWithWeight {
      chapter: ChapterInfo;
      weight: number;
      originalIndex: number;
    }

    const chaptersWithWeight: ChapterWithWeight[] = chapters.map((ch, index) => {
      let weight = this.extractChapterSortWeight(ch, index);
      return { chapter: ch, weight: weight, originalIndex: index } as ChapterWithWeight;
    });

    // 按权重升序排序
    chaptersWithWeight.sort((a: ChapterWithWeight, b: ChapterWithWeight) => {
      return a.weight - b.weight;
    });

    // 检查排序是否有效（权重是否有差异）
    const hasValidWeights = chaptersWithWeight.some((item, idx) => {
      if (idx === 0) return false;
      return item.weight !== chaptersWithWeight[idx - 1].weight;
    });

    if (!hasValidWeights) {
      // 所有权重相同，保持原始顺序
      logger.warn(TAG, '章节排序：无法提取有效排序信息，保持原始顺序');
      return chapters;
    }

    // 返回排序后的章节
    return chaptersWithWeight.map(item => item.chapter);
  }

  /**
   * 提取章节的排序权重
   * @param chapter 章节信息
   * @param originalIndex 原始索引
   * @returns 排序权重（数字越小越靠前）
   * 
   * [优化] 排序优先级调整：
   * 1. number字段（API明确提供的章节号，最可靠）
   * 2. 标题提取（大多数图源的章节标题都包含章节号）
   * 3. externalId数字（降低优先级，因为混合显示时externalId可能无效）
   * 4. 原始顺序（最后手段）
   */
  private extractChapterSortWeight(chapter: ChapterInfo, originalIndex: number): number {
    // 1. 优先使用 number 字段（API明确提供的章节号）
    if (chapter.number !== undefined && chapter.number !== null && !isNaN(chapter.number)) {
      return chapter.number;
    }

    // 2. [优化] 优先从标题中提取章节号（比externalId更可靠）
    const titleNum = this.extractNumberFromTitle(chapter.title);
    if (titleNum !== null) {
      return titleNum;
    }

    // 3. [降级] 尝试从 externalId 提取数字（仅作为备选）
    // 注意：很多图源的externalId是混合格式或无序的，不可靠
    if (chapter.externalId) {
      // 只有当externalId是纯数字时才使用
      const trimmedId = chapter.externalId.trim();
      if (/^\d+$/.test(trimmedId)) {
        const externalNum = Number(trimmedId);
        if (!isNaN(externalNum) && externalNum > 0 && externalNum < 10000) {
          return externalNum;
        }
      }
    }

    // 4. 使用原始索引作为最后手段（加大偏移避免与提取的数字冲突）
    return 100000 + originalIndex;
  }

  /**
   * 从章节标题中提取章节号
   * [增强] 支持多种语言、符号格式，提高准确性和兼容性
   * @param title 章节标题
   * @returns 提取的章节号，无法提取返回null
   */
  private extractNumberFromTitle(title: string): number | null {
    if (!title) return null;

    // 预处理：去除首尾空格
    const cleanTitle = title.trim();

    // 中文数字映射（扩展支持）
    const chineseNumMap: Record<string, number> = {
      '零': 0, '〇': 0,
      '一': 1, '壹': 1,
      '二': 2, '贰': 2, '两': 2,
      '三': 3, '叁': 3,
      '四': 4, '肆': 4,
      '五': 5, '伍': 5,
      '六': 6, '陆': 6,
      '七': 7, '柒': 7,
      '八': 8, '捌': 8,
      '九': 9, '玖': 9,
      '十': 10, '拾': 10,
      '百': 100, '佰': 100,
      '千': 1000, '仟': 1000
    };

    // ========== 高优先级：明确的章节标识格式 ==========

    // 格式1: 中文格式 - 第X章/话/回/集/卷/篇/幕/节 (阿拉伯数字)
    let match = cleanTitle.match(/第\s*(\d+(?:\.\d+)?)\s*[章话回集卷篇幕节]/);
    if (match) {
      return parseFloat(match[1]);
    }

    // 格式2: 中文格式 - 第X章/话/回/集 (中文数字)
    match = cleanTitle.match(/第\s*([零〇一二三四五六七八九十百千壹贰叁肆伍陆柒捌玖拾佰仟两]+)\s*[章话回集卷篇幕节]/);
    if (match) {
      const chineseNum = this.parseChineseNumber(match[1], chineseNumMap);
      if (chineseNum !== null) return chineseNum;
    }

    // 格式3: 英文格式 - Chapter/Ch./Ch/Chap/Chpt X
    match = cleanTitle.match(/(?:Chapter|Chap(?:ter)?|Chpt|Ch\.?)\s*[:\-]?\s*(\d+(?:\.\d+)?)/i);
    if (match) {
      return parseFloat(match[1]);
    }

    // 格式4: 英文格式 - Episode/EP./Ep X
    match = cleanTitle.match(/(?:Episode|Ep\.?)\s*[:\-]?\s*(\d+(?:\.\d+)?)/i);
    if (match) {
      return parseFloat(match[1]);
    }

    // 格式5: 日文格式 - 第X話/回/巻
    match = cleanTitle.match(/第\s*(\d+(?:\.\d+)?)\s*[話巻]/);
    if (match) {
      return parseFloat(match[1]);
    }

    // 格式6: 韩文格式 - X화/회/장
    match = cleanTitle.match(/(\d+(?:\.\d+)?)\s*[화회장]/);
    if (match) {
      return parseFloat(match[1]);
    }

    // 格式7: 符号格式 - #X, No.X, No X, Vol.X, Volume X
    match = cleanTitle.match(/(?:#|No\.?|Vol(?:ume)?\.?)\s*(\d+(?:\.\d+)?)/i);
    if (match) {
      return parseFloat(match[1]);
    }

    // 格式8: 括号格式 - (X), [X], 【X】, 「X」
    match = cleanTitle.match(/[(\[【「]\s*(\d+(?:\.\d+)?)\s*[)\]】」]/);
    if (match) {
      return parseFloat(match[1]);
    }

    // 格式9: 连字符/冒号格式 - X - Title, X: Title, X. Title
    match = cleanTitle.match(/^(\d+(?:\.\d+)?)\s*[:\-\.]\s*\S/);
    if (match) {
      return parseFloat(match[1]);
    }

    // 格式10: 数字+单位格式 - X话/章/回/集 (数字在前，无"第"字)
    match = cleanTitle.match(/^(\d+(?:\.\d+)?)\s*[话章回集卷篇話巻]/);
    if (match) {
      return parseFloat(match[1]);
    }

    // ========== 中优先级：数字开头格式 ==========

    // 格式11: 纯数字开头 (如 "001", "1", "1.5", "001 标题")
    match = cleanTitle.match(/^(\d+(?:\.\d+)?)\s/);
    if (match) {
      return parseFloat(match[1]);
    }

    // 格式12: 纯数字标题 (如 "001", "1", "1.5")
    match = cleanTitle.match(/^(\d+(?:\.\d+)?)$/);
    if (match) {
      return parseFloat(match[1]);
    }

    // ========== 低优先级：标题中的数字 ==========

    // 格式13: 标题末尾的数字 (如 "番外1", "特别篇2")
    match = cleanTitle.match(/[^\d](\d+(?:\.\d+)?)$/);
    if (match) {
      return parseFloat(match[1]);
    }

    // 格式14: 标题中包含的第一个数字（最后手段）
    // 排除年份格式（4位数字且在1900-2100范围）
    const allNumbers = cleanTitle.match(/\d+(?:\.\d+)?/g);
    if (allNumbers) {
      for (const numStr of allNumbers) {
        const num = parseFloat(numStr);
        // 排除可能是年份的数字
        if (num >= 1900 && num <= 2100 && numStr.length === 4) {
          continue;
        }
        // 排除过大的数字（可能是日期、ID等）
        if (num < 10000) {
          return num;
        }
      }
    }

    return null;
  }

  /**
   * 解析中文数字
   * @param chineseStr 中文数字字符串
   * @param numMap 中文数字映射表
   * @returns 解析后的数字，无法解析返回null
   */
  private parseChineseNumber(chineseStr: string, numMap: Record<string, number>): number | null {
    if (!chineseStr) return null;

    let result = 0;
    let temp = 0;
    let prevUnit = 1;

    for (let i = 0; i < chineseStr.length; i++) {
      const char = chineseStr[i];
      const num = numMap[char];

      if (num === undefined) {
        return null; // 包含无法识别的字符
      }

      if (num >= 10) {
        // 是单位（十、百、千）
        if (temp === 0) temp = 1;
        temp *= num;
        result += temp;
        temp = 0;
        prevUnit = num;
      } else {
        // 是数字
        temp = num;
      }
    }

    result += temp;
    return result > 0 ? result : null;
  }
}
