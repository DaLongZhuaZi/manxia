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
  MangaSourceError,
  MangaSourceErrorCode,
  AntiCrawlerConfig,
  Workflow,
  WorkflowType
} from './MangaSourceTypes';

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

/**
 * 漫画图源引擎
 */
export class MangaSourceEngine {
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

  constructor(engineConfig: EngineConfig) {
    this.engineConfig = engineConfig;
    this.actionEngine = new MangaSourceActionEngine(engineConfig.webViewController, engineConfig.antiCrawlerConfig);
    this.selectorEngine = new MangaSourceSelectorEngine();
    this.configParser = new MangaSourceConfigParser();
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
   * 加载配置文件
   */
  async loadConfig(jsonContent: string): Promise<ParseResult> {
    logger.info(TAG, '加载漫画图源配置');
    logger.debug(TAG, `接收到的JSON长度: ${jsonContent.length}`);
    
    // 保存原始JSON用于提取API配置
    this.rawConfigJson = jsonContent;
    
    const parseResult = this.configParser.parseConfig(jsonContent);
    
    if (parseResult.success && parseResult.config) {
      this.config = parseResult.config;
      const summary = this.configParser.getConfigSummary(this.config);
      logger.info(TAG, `配置加载成功: ${summary.name} v${summary.version}`);
      logger.debug(TAG, `工作流数量: ${summary.workflowCount}, 工作流列表: ${summary.workflows.join(', ')}`);
      
      if (parseResult.warnings && parseResult.warnings.length > 0) {
        logger.warn(TAG, `配置警告: ${parseResult.warnings.join('; ')}`);
      }

      // 自动执行初始化工作流（用于登录/Cookie预热）
      try {
        await this.runInitializeWorkflowIfPresent();
      } catch (e) {
        logger.warn(TAG, `初始化工作流执行失败: ${e instanceof Error ? e.message : String(e)}`);
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
              scriptData = JSON.parse(scriptData) as string;
            } catch (e) {
              logger.debug(TAG, `解除双重序列化失败: ${e}`);
            }
          }
          if (scriptData.startsWith('[')) {
            try {
              const parsed = JSON.parse(scriptData) as Array<Record<string, Object>>;
              if (Array.isArray(parsed) && parsed.length > 0 && parsed[0] && (parsed[0] as Record<string, Object>)['id'] !== undefined) {
                searchResults = parsed.map((item: Record<string, Object>) => this.transformToMangaInfo(item));
                logger.debug(TAG, `从脚本结果提取到 ${searchResults.length} 条漫画数据`);
              }
            } catch (e) {
              logger.debug(TAG, `脚本结果不是漫画列表格式: ${e}`);
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
              scriptData = JSON.parse(scriptData) as string;
              logger.debug(TAG, `脚本数据解除双重序列化后首字符: '${scriptData.charAt(0)}'`);
            } catch (e) {
              logger.debug(TAG, `解除双重序列化失败: ${e}`);
            }
          }
          // 检查是否是漫画列表格式的JSON（以 [ 开头）
          if (scriptData.startsWith('[')) {
            try {
              const parsed = JSON.parse(scriptData) as Array<Record<string, Object>>;
              logger.debug(TAG, `JSON解析成功，数组长度: ${parsed.length}`);
              // 验证是否是漫画列表格式（包含 id 字段）
              if (Array.isArray(parsed) && parsed.length > 0 && parsed[0] && (parsed[0] as Record<string, Object>)['id'] !== undefined) {
                results = parsed.map((item: Record<string, Object>) => this.transformToMangaInfo(item));
                logger.debug(TAG, `从脚本结果提取到 ${results.length} 条漫画数据`);
              }
            } catch (e) {
              logger.debug(TAG, `脚本结果JSON解析失败: ${e}`);
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
      context.variables['useCookies'] = 'false';
      context.variables['page'] = page.toString();
      context.variables['offset'] = ((page - 1) * 30).toString();
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
              scriptData = JSON.parse(scriptData) as string;
            } catch (e) {
              logger.debug(TAG, `解除双重序列化失败: ${e}`);
            }
          }
          if (scriptData.startsWith('[')) {
            try {
              const parsed = JSON.parse(scriptData) as Array<Record<string, Object>>;
              if (Array.isArray(parsed) && parsed.length > 0 && parsed[0] && (parsed[0] as Record<string, Object>)['id'] !== undefined) {
                results = parsed.map((item: Record<string, Object>) => this.transformToMangaInfo(item));
                logger.debug(TAG, `从脚本结果提取到 ${results.length} 条漫画数据`);
              }
            } catch (e) {
              logger.debug(TAG, `脚本结果不是漫画列表格式: ${e}`);
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
   */
  async getFiltered(page: number = 1, filterOrdering?: string, filterRegion?: string, filterTheme?: string): Promise<EngineResult<SearchResult>> {
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
      context.variables['filterOrdering'] = filterOrdering || '-datetime_updated';
      context.variables['filterRegion'] = filterRegion || 'all';
      context.variables['filterTheme'] = filterTheme || 'all';
      
      // PicaComic 等图源使用的参数名 - 从工作流配置中读取默认值
      let defaultSort: string = 'dd';  // PicaComic 默认排序
      let defaultCategory: string = '';  // 默认为空（全部分类）
      
      // 从原始JSON配置中读取默认值
      if (this.rawConfigJson) {
        try {
          const rawConfig = JSON.parse(this.rawConfigJson) as Record<string, Object>;
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
      
      logger.debug(TAG, `筛选参数: sort=${context.variables['sort']}, category=${context.variables['category']}`);
      
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
   */
  async getLeaderboard(page: number = 1): Promise<EngineResult<SearchResult>> {
    if (!this.config) {
      logger.error(TAG, '配置未加载，无法获取排行榜');
      throw new MangaSourceError(
        MangaSourceErrorCode.CONFIG_NOT_LOADED,
        '配置未加载'
      );
    }

    const startTime = Date.now();
    logger.info(TAG, `开始获取排行榜: 页码=${page}`);

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
      // 设置排行榜默认时间类型 (H24=24小时, D7=7天, D30=30天)
      if (!context.variables['timeType']) {
        context.variables['timeType'] = 'H24';
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
      // 添加mangaId变量到上下文
      context.variables['mangaId'] = mangaId;
      
      let mangaDetail: MangaInfo | undefined;
      
      for (const action of actions) {
        const result = await this.actionEngine.executeAction(action, context);
        
        if (!result.success) {
          throw new MangaSourceError(
            MangaSourceErrorCode.ACTION_FAILED,
            `获取详情操作失败: ${result.error}`
          );
        }

        if ((action.type === 'extract' || action.type === 'api' || action.type === 'script') && result.data) {
          // script操作返回的是JSON字符串，需要先解析
          let dataObj = result.data;
          if (action.type === 'script' && typeof result.data === 'string') {
            try {
              dataObj = JSON.parse(result.data as string);
              logger.debug(TAG, `第一次JSON解析完成，类型: ${typeof dataObj}`);
              
              // 检测双重字符串化：如果解析后仍是字符串，再解析一次
              if (typeof dataObj === 'string') {
                logger.debug(TAG, `检测到双重字符串化，进行第二次解析`);
                dataObj = JSON.parse(dataObj as string);
                logger.debug(TAG, `第二次JSON解析完成，类型: ${typeof dataObj}`);
              }
              
              logger.debug(TAG, `script返回数据已解析: ${JSON.stringify(dataObj).substring(0, 200)}`);
            } catch (e) {
              logger.error(TAG, `script返回数据JSON解析失败: ${e}`);
            }
          }
          mangaDetail = this.transformToMangaInfo(dataObj);
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
      // 添加mangaId变量到上下文
      context.variables['mangaId'] = mangaId;
      
      let chapters: ChapterInfo[] = [];
      this.lastChapterAccessDenied = false;
      
      for (const action of actions) {
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
              let parsed: Object = JSON.parse(scriptResult);
              logger.debug(TAG, `第一次JSON解析: 类型=${typeof parsed}, 是否数组=${Array.isArray(parsed)}`);
              
              // 如果解析后还是字符串且以[开头，说明被双重字符串化了，需要再解析一次
              if (typeof parsed === 'string' && (parsed as string).trim().startsWith('[')) {
                logger.debug(TAG, `检测到双重字符串化，进行第二次解析`);
                parsed = JSON.parse(parsed as string);
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

      // [修复] 根据 order 字段对章节进行升序排序（第一章在前）
      // PicaComic 等 API 返回的章节可能是降序排列的
      if (chapters.length > 0) {
        chapters.sort((a: ChapterInfo, b: ChapterInfo) => {
          // 优先使用 externalId 进行排序（对于 PicaComic，externalId 就是 order）
          const orderA = Number(a.externalId) || 0;
          const orderB = Number(b.externalId) || 0;
          return orderA - orderB;  // 升序排列
        });
        logger.debug(TAG, `章节已按 order 升序排序，第一章: ${chapters[0].title}, 最后一章: ${chapters[chapters.length - 1].title}`);
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
    const workflows = this.config.workflows as Workflow;
    const workflowActions: Action[] | undefined = (workflows as ESObject)['getMangaDetailWithChapters'] as Action[] | undefined;
    if (!workflowActions) {
      logger.info(TAG, '未找到合并工作流，使用独立调用');
      // 降级：分别调用
      const detailResult = await this.getMangaDetail(mangaId);
      const chapterResult = await this.getChapterList(mangaId);
      
      if (!detailResult.success || !chapterResult.success) {
        return {
          success: false,
          error: detailResult.error || chapterResult.error || '获取失败',
          duration: Date.now() - startTime,
          actionCount: 0
        };
      }
      
      const combinedData: MangaDetailWithChapters = {
        detail: detailResult.data!,
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
      const actions: Action[] = workflowActions || [];
      const context = this.createActionContext();
      await this.populateSourceSettings(context);
      context.variables['useCookies'] = 'true';
      context.variables['mangaId'] = mangaId;
      
      let mangaDetail: MangaInfo | undefined;
      let chapters: ChapterInfo[] = [];
      let detailActionIndex = -1;
      let chapterActionIndex = -1;
      
      for (let i = 0; i < actions.length; i++) {
        const action: Action = actions[i];
        const result = await this.actionEngine.executeAction(action, context);
        
        if (!result.success) {
          throw new MangaSourceError(
            MangaSourceErrorCode.ACTION_FAILED,
            `合并工作流操作失败: ${result.error}`
          );
        }

        // 提取详情（第一个返回数据的script）
        if (action.type === 'script' && result.data && !mangaDetail) {
          if (typeof result.data === 'string') {
            try {
              let dataObj: ESObject = JSON.parse(result.data as string) as ESObject;
              if (typeof dataObj === 'string') {
                dataObj = JSON.parse(dataObj as string);
              }
              
              // 判断是详情还是章节（详情有title字段，章节是数组）
              if (!Array.isArray(dataObj) && dataObj.title) {
                mangaDetail = this.transformToMangaInfo(dataObj);
                detailActionIndex = i;
                logger.debug(TAG, `合并工作流：提取到详情 (action ${i})`);
              }
            } catch (e) {
              logger.error(TAG, `合并工作流：解析详情失败 ${e}`);
            }
          }
        }
        
        // 提取章节（第二个返回数据的script，且是数组）
        if (action.type === 'script' && result.data && mangaDetail && chapters.length === 0) {
          if (typeof result.data === 'string') {
            try {
              let parsed: ESObject = JSON.parse(result.data as string) as ESObject;
              if (typeof parsed === 'string') {
                parsed = JSON.parse(parsed as string);
              }
              
              if (Array.isArray(parsed)) {
                chapters = (parsed as Array<Record<string, Object>>).map(item => 
                  this.transformToChapterInfo(item)
                );
                chapterActionIndex = i;
                logger.debug(TAG, `合并工作流：提取到 ${chapters.length} 个章节 (action ${i})`);
              }
            } catch (e) {
              logger.error(TAG, `合并工作流：解析章节失败 ${e}`);
            }
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
      const actions = this.configParser.buildPageListActions(this.config, chapterId);
      const context = this.createActionContext();
      await this.populateSourceSettings(context);
      context.variables['useCookies'] = 'true';
      // 添加mangaId和chapterId变量到上下文
      if (mangaId) {
        context.variables['mangaId'] = mangaId;
      }
      context.variables['chapterId'] = chapterId;
      
      let pages: PageInfo[] = [];
      
      for (const action of actions) {
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
              let parsed: Object = JSON.parse(scriptResult);
              logger.debug(TAG, `第一次JSON解析: 类型=${typeof parsed}, 是否数组=${Array.isArray(parsed)}`);
              
              // 如果解析后还是字符串且以[或{开头，说明被双重字符串化了，需要再解析一次
              if (typeof parsed === 'string' && ((parsed as string).trim().startsWith('[') || (parsed as string).trim().startsWith('{'))) {
                logger.debug(TAG, `检测到双重字符串化，进行第二次解析`);
                parsed = JSON.parse(parsed as string);
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
                  
                  // 如果有 totalPages 字段，记录日志并附加到pages数组
                  if (parsedObj['totalPages']) {
                    const total = Number(parsedObj['totalPages']);
                    logger.info(TAG, `script操作返回的总页数: ${total}`);
                    (pages as ESObject)['totalPages'] = total;
                    (pages as ESObject)['needsMorePages'] = total > pages.length;
                  }
                  
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
  async loadMorePages(chapterId: string, mangaId?: string): Promise<EngineResult<ESObject>> {
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
      if (mangaId) {
        context.variables['mangaId'] = mangaId;
      }
      context.variables['chapterId'] = chapterId;
      
      let resultData: ESObject = {};
      
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
            let parsed: Object = JSON.parse(scriptResult);
            logger.debug(TAG, `loadMorePages JSON解析: 类型=${typeof parsed}, 是否对象=${typeof parsed === 'object'}`);
            
            // 如果解析后还是字符串，说明被双重字符串化了，需要再解析一次
            if (typeof parsed === 'string' && ((parsed as string).trim().startsWith('{') || (parsed as string).trim().startsWith('['))) {
              logger.debug(TAG, `检测到双重字符串化，进行第二次解析`);
              parsed = JSON.parse(parsed as string);
              logger.debug(TAG, `第二次JSON解析: 类型=${typeof parsed}`);
            }
            
            if (typeof parsed === 'object' && parsed !== null) {
              resultData = parsed as ESObject;
              logger.debug(TAG, `loadMorePages解析结果: pages数量=${(resultData['pages'] as Array<Object>)?.length || 0}`);
            } else {
              logger.warn(TAG, `script返回的不是对象: ${typeof parsed}`);
              resultData = result.data as ESObject;
            }
          } catch (e) {
            logger.warn(TAG, `JSON解析失败，使用原始数据: ${e}`);
            resultData = result.data as ESObject;
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
      
      // 初始化API配置变量
      if (this.rawConfigJson) {
        try {
          const rawConfig = JSON.parse(this.rawConfigJson) as Record<string, Object>;
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

    // 处理标签 (合并 genres, categories, tags)
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
    
    return {
      page: index,
      imageUrl: imageUrl
    };
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
   * 填充源级设置与登录变量到上下文
   */
  private async populateSourceSettings(context: ActionContext): Promise<void> {
    const sidStr = this.engineConfig.sourceId !== undefined ? String(this.engineConfig.sourceId as number) : '';
    if (!sidStr) {
      return;
    }
    const sid: number = Number(sidStr);
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
}
