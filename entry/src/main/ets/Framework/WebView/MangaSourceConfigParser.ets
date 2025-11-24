// 文件路径: src/main/ets/Framework/WebView/MangaSourceConfigParser.ets
/**
 * 漫画图源配置解析器
 * 将JSON配置文件解析为可执行的操作序列
 */

import { logger } from '../../Utils/Logger';
import {
  MangaSourceConfig,
  MangaSourceMetadata,
  Workflow,
  Action,
  ActionType,
  MangaSourceError,
  MangaSourceErrorCode,
  MangaInfo,
  ChapterInfo,
  PageInfo,
  WorkflowType,
  MangaSourceSettings,
  NavigateAction,
  WaitAction,
  ClickAction,
  InputAction,
  ExtractAction,
  ConditionAction,
  ScriptAction,
  CloudflareBypassAction,
  CaptchaAction,
  IPBlockAction,
  APIRequestAction,
  HTTPRequestAction,
  ExtractConfig,
  BaseAction
} from './MangaSourceTypes';

const TAG = 'MangaSourceConfigParser';

/**
 * 解析结果
 */
export interface ParseResult {
  /** 解析是否成功 */
  success: boolean;
  /** 解析后的配置 */
  config?: MangaSourceConfig;
  /** 错误信息 */
  error?: string;
  /** 验证警告 */
  warnings?: string[];
}

/**
 * 变量映射接口（替代Map）
 */
export interface VariableMap {
  searchKeyword?: string;
  mangaId?: string;
  chapterId?: string;
  pageIndex?: string;
}

/**
 * 工作流执行上下文
 */
export interface WorkflowContext {
  /** 当前URL */
  currentUrl: string;
  /** 搜索关键词 */
  searchKeyword?: string;
  /** 漫画ID */
  mangaId?: string;
  /** 章节ID */
  chapterId?: string;
  /** 页面索引 */
  pageIndex?: number;
  /** 变量映射 */
  variables: VariableMap;
}

/**
 * 验证结果
 */
interface ValidateConfigResult {
  valid: boolean;
  error?: string;
}

/**
 * 验证工作流配置
 */
interface ValidateWorkflowsResult {
  valid: boolean;
  error?: string;
}

/**
 * 验证操作配置
 */
interface ValidateActionResult {
  valid: boolean;
  error?: string;
}

/**
 * 配置摘要设置信息
 */
export interface ConfigSummarySettings {
  timeout: number;
  retryCount: number;
  userAgent: string;
}

/**
 * 获取配置摘要信息
 */
export interface ConfigSummaryResult {
  name: string;
  version: string;
  baseUrl: string;
  author: string;
  description: string;
  workflowCount: number;
  workflows: string[];
  settings: ConfigSummarySettings;
}

/**
 * 默认设置配置
 */
interface DefaultSettings {
  timeout: number;
  retryCount: number;
  enableJavaScript: boolean;
  enableImages: boolean;
  enableCookies: boolean;
  bypassCloudflare: boolean;
  userAgent: string;
}

/**
 * 克隆操作基础接口
 */
interface ClonedActionBase {
  type: ActionType;
  description?: string;
  optional?: boolean;
  waitAfter?: number;
}

/**
 * 漫画图源配置解析器
 */
export class MangaSourceConfigParser {

  /**
   * 解析JSON配置文件
   */
  parseConfig(jsonContent: string): ParseResult {
    try {
      logger.info(TAG, '开始解析漫画图源配置');
      logger.debug(TAG, `JSON内容长度: ${jsonContent.length}`);
      
      const rawConfig: Record<string, Object> = JSON.parse(jsonContent) as Record<string, Object>;
      const warnings: string[] = [];
      logger.debug(TAG, `JSON解析成功，开始验证配置`);

      // 验证基础结构
      const validationResult = this.validateConfig(rawConfig);
      if (!validationResult.valid) {
        logger.error(TAG, `配置验证失败: ${validationResult.error}`);
        return {
          success: false,
          error: validationResult.error
        };
      }
      logger.debug(TAG, '基础配置验证通过');

      // 转换为类型化配置
      const config = this.transformConfig(rawConfig, warnings);
      logger.debug(TAG, `配置转换完成，警告数量: ${warnings.length}`);

      // 验证工作流
      const workflowValidation = this.validateWorkflows(config);
      if (!workflowValidation.valid) {
        logger.error(TAG, `工作流验证失败: ${workflowValidation.error}`);
        return {
          success: false,
          error: workflowValidation.error
        };
      }
      logger.debug(TAG, '工作流验证通过');

      logger.info(TAG, '漫画图源配置解析完成', 
        'name:' + config.metadata.name + ',' +
        'version:' + config.metadata.version + ',' +
        'workflows:' + this.getWorkflowCount(config.workflows)
      );

      return {
        success: true,
        config,
        warnings: warnings.length > 0 ? warnings : undefined
      };

    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      const errorStack = error instanceof Error ? error.stack : '';
      logger.error(TAG, `配置解析异常: ${errorMessage}`);
      logger.debug(TAG, `异常堆栈: ${errorStack}`);
      
      return {
        success: false,
        error: `JSON解析失败: ${errorMessage}`
      };
    }
  }

  /**
   * 获取工作流
   */
  getWorkflow(config: MangaSourceConfig, workflowName: string): Action[] | undefined {
    const workflow = config.workflows;
    switch (workflowName) {
      case 'search':
        return this.getWorkflowByType(workflow, WorkflowType.SEARCH);
      case 'getMangaDetail':
        return this.getWorkflowByType(workflow, WorkflowType.GET_MANGA_DETAIL);
      case 'getChapterList':
        return this.getWorkflowByType(workflow, WorkflowType.GET_CHAPTER_LIST);
      case 'getPageList':
        return this.getWorkflowByType(workflow, WorkflowType.GET_PAGE_LIST);
      case 'loadMorePages':
        return this.getWorkflowByType(workflow, WorkflowType.LOAD_MORE_PAGES);
      case 'getImageUrl':
        return this.getWorkflowByType(workflow, WorkflowType.GET_IMAGE_URL);
      case 'popular':
        return this.getWorkflowByType(workflow, WorkflowType.POPULAR);
      case 'latest':
        return this.getWorkflowByType(workflow, WorkflowType.LATEST);
      case 'filter':
        return this.getWorkflowByType(workflow, WorkflowType.FILTER);
      case 'favorites':
        return this.getWorkflowByType(workflow, WorkflowType.FAVORITES);
      case 'history':
        return this.getWorkflowByType(workflow, WorkflowType.HISTORY);
      case 'initialize':
        return this.getWorkflowByType(workflow, WorkflowType.INITIALIZE);
      default:
        return undefined;
    }
  }

  /**
   * 根据工作流类型获取工作流
   */
  private getWorkflowByType(workflow: Workflow, type: WorkflowType): Action[] | undefined {
    switch (type) {
      case WorkflowType.SEARCH:
        return workflow.search;
      case WorkflowType.GET_MANGA_DETAIL:
        return workflow.getMangaDetail;
      case WorkflowType.GET_CHAPTER_LIST:
        return workflow.getChapterList;
      case WorkflowType.GET_PAGE_LIST:
        return workflow.getPageList;
      case WorkflowType.LOAD_MORE_PAGES:
        return workflow.loadMorePages;
      case WorkflowType.GET_IMAGE_URL:
        return workflow.getImageUrl;
      case WorkflowType.POPULAR:
        return workflow.popular;
      case WorkflowType.LATEST:
        return workflow.latest;
      case WorkflowType.FILTER:
        return workflow.filter;
      case WorkflowType.FAVORITES:
        return workflow.favorites;
      case WorkflowType.HISTORY:
        return workflow.history;
      case WorkflowType.INITIALIZE:
        return workflow.initialize;
      case WorkflowType.GET_MANGA_LIST:
        return workflow.getMangaList;
      default:
        return undefined;
    }
  }

  /**
   * 根据工作流类型设置工作流
   */
  private setWorkflowByType(workflow: Workflow, type: WorkflowType, actions: Action[]): void {
    switch (type) {
      case WorkflowType.SEARCH:
        workflow.search = actions;
        break;
      case WorkflowType.GET_MANGA_DETAIL:
        workflow.getMangaDetail = actions;
        break;
      case WorkflowType.GET_CHAPTER_LIST:
        workflow.getChapterList = actions;
        break;
      case WorkflowType.GET_PAGE_LIST:
        workflow.getPageList = actions;
        break;
      case WorkflowType.LOAD_MORE_PAGES:
        workflow.loadMorePages = actions;
        break;
      case WorkflowType.GET_IMAGE_URL:
        workflow.getImageUrl = actions;
        break;
      case WorkflowType.POPULAR:
        workflow.popular = actions;
        break;
      case WorkflowType.LATEST:
        workflow.latest = actions;
        break;
      case WorkflowType.FILTER:
        workflow.filter = actions;
        break;
      case WorkflowType.FAVORITES:
        workflow.favorites = actions;
        break;
      case WorkflowType.HISTORY:
        workflow.history = actions;
        break;
      case WorkflowType.INITIALIZE:
        workflow.initialize = actions;
        break;
      case WorkflowType.GET_MANGA_LIST:
        workflow.getMangaList = actions;
        break;
    }
  }

  /**
   * 构建搜索操作序列
   */
  buildSearchActions(config: MangaSourceConfig, keyword: string): Action[] {
    const workflow = this.getWorkflow(config, 'search');
    if (!workflow) {
      throw new MangaSourceError(
        MangaSourceErrorCode.INVALID_CONFIG,
        '缺少搜索工作流配置'
      );
    }

    return this.processActions(workflow, { searchKeyword: keyword });
  }

  /**
   * 构建漫画详情获取操作序列
   */
  buildMangaDetailActions(config: MangaSourceConfig, mangaId: string): Action[] {
    const workflow = this.getWorkflow(config, 'getMangaDetail');
    if (!workflow) {
      throw new MangaSourceError(
        MangaSourceErrorCode.INVALID_CONFIG,
        '缺少漫画详情工作流配置'
      );
    }

    return this.processActions(workflow, { mangaId });
  }

  /**
   * 构建章节列表获取操作序列
   */
  buildChapterListActions(config: MangaSourceConfig, mangaId: string): Action[] {
    const workflow = this.getWorkflow(config, 'getChapterList');
    if (!workflow) {
      throw new MangaSourceError(
        MangaSourceErrorCode.INVALID_CONFIG,
        '缺少章节列表工作流配置'
      );
    }

    return this.processActions(workflow, { mangaId });
  }

  /**
   * 构建页面列表获取操作序列
   */
  buildPageListActions(config: MangaSourceConfig, chapterId: string): Action[] {
    const workflow = this.getWorkflow(config, 'getPageList');
    if (!workflow) {
      throw new MangaSourceError(
        MangaSourceErrorCode.INVALID_CONFIG,
        '缺少页面列表工作流配置'
      );
    }

    return this.processActions(workflow, { chapterId });
  }

  /**
   * 构建加载更多页面操作序列
   */
  buildLoadMorePagesActions(config: MangaSourceConfig, chapterId: string): Action[] {
    const workflow = this.getWorkflow(config, 'loadMorePages');
    if (!workflow) {
      throw new MangaSourceError(
        MangaSourceErrorCode.INVALID_CONFIG,
        '缺少加载更多页面工作流配置'
      );
    }

    return this.processActions(workflow, { chapterId });
  }

  /**
   * 构建热门漫画获取操作序列
   */
  buildPopularActions(config: MangaSourceConfig): Action[] {
    const workflow = this.getWorkflow(config, 'popular');
    if (!workflow) {
      throw new MangaSourceError(
        MangaSourceErrorCode.INVALID_CONFIG,
        '缺少热门漫画工作流配置'
      );
    }

    return this.processActions(workflow, {});
  }

  /**
   * 构建最新更新获取操作序列
   */
  buildLatestActions(config: MangaSourceConfig): Action[] {
    const workflow = this.getWorkflow(config, 'latest');
    if (!workflow) {
      throw new MangaSourceError(
        MangaSourceErrorCode.INVALID_CONFIG,
        '缺少最新更新工作流配置'
      );
    }

    return this.processActions(workflow, {});
  }

  /**
   * 构建筛选漫画操作序列
   */
  buildFilterActions(config: MangaSourceConfig): Action[] {
    const workflow = this.getWorkflow(config, 'filter');
    if (!workflow) {
      throw new MangaSourceError(
        MangaSourceErrorCode.INVALID_CONFIG,
        '缺少筛选工作流配置'
      );
    }

    return this.processActions(workflow, {});
  }

  /**
   * 构建收藏获取操作序列
   */
  buildFavoritesActions(config: MangaSourceConfig): Action[] {
    const workflow = this.getWorkflow(config, 'favorites');
    if (!workflow) {
      throw new MangaSourceError(
        MangaSourceErrorCode.INVALID_CONFIG,
        '缺少收藏工作流配置'
      );
    }

    return this.processActions(workflow, {});
  }

  /**
   * 构建浏览记录获取操作序列
   */
  buildHistoryActions(config: MangaSourceConfig): Action[] {
    const workflow = this.getWorkflow(config, 'history');
    if (!workflow) {
      throw new MangaSourceError(
        MangaSourceErrorCode.INVALID_CONFIG,
        '缺少浏览记录工作流配置'
      );
    }

    return this.processActions(workflow, {});
  }

  /**
   * 构建图片URL获取操作序列
   */
  buildImageUrlActions(config: MangaSourceConfig, pageIndex: number): Action[] {
    const workflow = this.getWorkflow(config, 'getImageUrl');
    if (!workflow) {
      throw new MangaSourceError(
        MangaSourceErrorCode.INVALID_CONFIG,
        '缺少图片URL工作流配置'
      );
    }

    return this.processActions(workflow, { pageIndex });
  }

  /**
   * 处理操作序列，替换变量
   */
  private processActions(actions: Action[], context: Partial<WorkflowContext>): Action[] {
    const variables: VariableMap = {};
    
    // 设置上下文变量
    if (context.searchKeyword) {
      variables.searchKeyword = context.searchKeyword;
    }
    if (context.mangaId) {
      variables.mangaId = context.mangaId;
    }
    if (context.chapterId) {
      variables.chapterId = context.chapterId;
    }
    if (context.pageIndex !== undefined) {
      variables.pageIndex = context.pageIndex.toString();
    }

    const processedActions: Action[] = [];
    for (let i = 0; i < actions.length; i++) {
      processedActions.push(this.processAction(actions[i], variables));
    }
    return processedActions;
  }

  /**
   * 处理单个操作，替换变量
   */
  private processAction(action: Action, variables: VariableMap): Action {
    const processedAction = this.cloneAction(action);
  
    // 替换字符串字段中的变量
    if (this.hasUrlProperty(processedAction) && (processedAction as NavigateAction).url) {
      (processedAction as NavigateAction).url = this.replaceVariables((processedAction as NavigateAction).url, variables);
    }
    if (this.hasSelectorProperty(processedAction) && this.getSelectorFromAction(processedAction)) {
      const selector = this.getSelectorFromAction(processedAction);
      if (selector) {
        this.setSelectorToAction(processedAction, this.replaceVariables(selector, variables));
      }
    }
    if (this.hasValueProperty(processedAction) && (processedAction as InputAction).value) {
      (processedAction as InputAction).value = this.replaceVariables((processedAction as InputAction).value, variables);
    }
    if (this.hasTextProperty(processedAction)) {
      const conditionAction = processedAction as ConditionAction;
      if (conditionAction.text !== undefined && conditionAction.text !== null) {
        conditionAction.text = this.replaceVariables(conditionAction.text, variables);
      }
    }
    
    // 处理API请求的body字段
    if (action.type === ActionType.API_REQUEST) {
      const apiAction = processedAction as APIRequestAction;
      if (apiAction.body) {
        apiAction.body = this.replaceObjectVariables(apiAction.body, variables);
      }
    }
    
    // 处理HTTP请求的body字段
    if (action.type === ActionType.HTTP_REQUEST) {
      const httpAction = processedAction as HTTPRequestAction;
      if (httpAction.body) {
        httpAction.body = this.replaceObjectVariables(httpAction.body, variables);
      }
    }
  
    // 处理条件操作的子操作
    if (action.type === ActionType.CONDITION) {
      const conditionAction = processedAction as ConditionAction;
      if (conditionAction.then) {
        const processedThen: Action[] = [];
        for (let i = 0; i < conditionAction.then.length; i++) {
          processedThen.push(this.processAction(conditionAction.then[i], variables));
        }
        conditionAction.then = processedThen;
      }
      if (conditionAction.else) {
        const processedElse: Action[] = [];
        for (let i = 0; i < conditionAction.else.length; i++) {
          processedElse.push(this.processAction(conditionAction.else[i], variables));
        }
        conditionAction.else = processedElse;
      }
    }
  
    return processedAction;
  }

  /**
   * 克隆操作对象（符合ArkTS规范的实现）
   */
  private cloneAction(action: Action): Action {
    // 创建基础克隆对象
    const baseCloned: ClonedActionBase = {
      type: action.type,
      description: action.description,
      optional: action.optional,
      waitAfter: action.waitAfter
    };

    // 根据操作类型创建具体的克隆对象
    switch (action.type) {
      case ActionType.NAVIGATE:
        const navigateAction = action as NavigateAction;
        const clonedNavigate: NavigateAction = {
          type: navigateAction.type,
          description: navigateAction.description,
          optional: navigateAction.optional,
          waitAfter: navigateAction.waitAfter,
          url: navigateAction.url,
          waitFor: navigateAction.waitFor
        };
        return clonedNavigate;

      case ActionType.WAIT:
        const waitAction = action as WaitAction;
        const clonedWait: WaitAction = {
          type: waitAction.type,
          description: waitAction.description,
          optional: waitAction.optional,
          waitAfter: waitAction.waitAfter,
          condition: waitAction.condition,
          selector: waitAction.selector,
          duration: waitAction.duration,
          timeout: waitAction.timeout
        };
        return clonedWait;

      case ActionType.CLICK:
        const clickAction = action as ClickAction;
        const clonedClick: ClickAction = {
          type: clickAction.type,
          description: clickAction.description,
          optional: clickAction.optional,
          waitAfter: clickAction.waitAfter,
          selector: clickAction.selector
        };
        return clonedClick;

      case ActionType.INPUT:
        const inputAction = action as InputAction;
        const clonedInput: InputAction = {
          type: inputAction.type,
          description: inputAction.description,
          optional: inputAction.optional,
          waitAfter: inputAction.waitAfter,
          selector: inputAction.selector,
          value: inputAction.value,
          clear: inputAction.clear
        };
        return clonedInput;

      case ActionType.EXTRACT:
        const extractAction = action as ExtractAction;
        const clonedExtract: ExtractAction = {
          type: extractAction.type,
          description: extractAction.description,
          optional: extractAction.optional,
          waitAfter: extractAction.waitAfter,
          selector: extractAction.selector,
          multiple: extractAction.multiple,
          fields: extractAction.fields
        };
        return clonedExtract;

      case ActionType.CONDITION:
        const conditionAction = action as ConditionAction;
        const clonedCondition: ConditionAction = {
          type: conditionAction.type,
          description: conditionAction.description,
          optional: conditionAction.optional,
          waitAfter: conditionAction.waitAfter,
          selector: conditionAction.selector,
          exists: conditionAction.exists,
          text: conditionAction.text,
          then: conditionAction.then,
          else: conditionAction.else
        };
        return clonedCondition;

      case ActionType.SCRIPT:
        const scriptAction = action as ScriptAction;
        const clonedScript: ScriptAction = {
          type: scriptAction.type,
          description: scriptAction.description,
          optional: scriptAction.optional,
          waitAfter: scriptAction.waitAfter,
          code: scriptAction.code
        };
        return clonedScript;

      case ActionType.CLOUDFLARE_BYPASS:
        const cloudflareAction = action as CloudflareBypassAction;
        const clonedCloudflare: CloudflareBypassAction = {
          type: cloudflareAction.type,
          description: cloudflareAction.description,
          optional: cloudflareAction.optional,
          waitAfter: cloudflareAction.waitAfter,
          maxWaitTime: cloudflareAction.maxWaitTime,
          indicators: cloudflareAction.indicators,
          method: 'wait'
        };
        return clonedCloudflare;

      case ActionType.CAPTCHA:
        const captchaAction = action as CaptchaAction;
        const clonedCaptcha: CaptchaAction = {
          type: captchaAction.type,
          description: captchaAction.description,
          optional: captchaAction.optional,
          waitAfter: captchaAction.waitAfter,
          selector: captchaAction.selector,
          method: captchaAction.method,
          timeout: captchaAction.timeout
        };
        return clonedCaptcha;

      case ActionType.IP_BLOCK:
        const ipBlockAction = action as IPBlockAction;
        const clonedIPBlock: IPBlockAction = {
          type: ipBlockAction.type,
          description: ipBlockAction.description,
          optional: ipBlockAction.optional,
          waitAfter: ipBlockAction.waitAfter,
          indicators: ipBlockAction.indicators,
          action: ipBlockAction.action,
          delay: ipBlockAction.delay
        };
        return clonedIPBlock;

      case ActionType.API_REQUEST:
        const apiAction = action as APIRequestAction;
        const clonedAPI: APIRequestAction = {
          type: apiAction.type,
          description: apiAction.description,
          optional: apiAction.optional,
          waitAfter: apiAction.waitAfter,
          method: apiAction.method,
          url: apiAction.url,
          params: apiAction.params,
          headers: apiAction.headers,
          body: apiAction.body,
          extract: apiAction.extract
        };
        return clonedAPI;

      case ActionType.HTTP_REQUEST:
        const httpAction = action as HTTPRequestAction;
        const clonedHTTP: HTTPRequestAction = {
          type: httpAction.type,
          description: httpAction.description,
          optional: httpAction.optional,
          waitAfter: httpAction.waitAfter,
          method: httpAction.method,
          url: httpAction.url,
          headers: httpAction.headers,
          body: httpAction.body
        };
        return clonedHTTP;

      default:
        // 默认情况下返回基础克隆（不应该到达这里）
        return baseCloned as Action;
    }
  }

  // 属性检查方法（使用instanceof和as替代is类型守卫）
  private hasUrlProperty(action: Action): boolean {
    return Object.keys(action).includes('url');
  }
  
  private hasSelectorProperty(action: Action): boolean {
    return Object.keys(action).includes('selector');
  }
  
  private hasValueProperty(action: Action): boolean {
    return Object.keys(action).includes('value');
  }
  
  private hasTextProperty(action: Action): boolean {
    return Object.keys(action).includes('text');
  }
  
  private hasConditionProperty(action: Action): boolean {
    return Object.keys(action).includes('condition');
  }
  
  private hasThenProperty(action: Action): boolean {
    return Object.keys(action).includes('then');
  }
  
  private hasElseProperty(action: Action): boolean {
    return Object.keys(action).includes('else');
  }
  
  private hasClearProperty(action: Action): boolean {
    return Object.keys(action).includes('clear');
  }
  
  private hasMultipleProperty(action: Action): boolean {
    return Object.keys(action).includes('multiple');
  }
  
  private hasFieldsProperty(action: Action): boolean {
    return Object.keys(action).includes('fields');
  }
  
  private hasExistsProperty(action: Action): boolean {
    return Object.keys(action).includes('exists');
  }
  
  private hasCodeProperty(action: Action): boolean {
    return Object.keys(action).includes('code');
  }

  /**
   * 从操作中获取选择器
   */
  private getSelectorFromAction(action: Action): string | undefined {
    switch (action.type) {
      case ActionType.WAIT:
        return (action as WaitAction).selector;
      case ActionType.CLICK:
        return (action as ClickAction).selector;
      case ActionType.INPUT:
        return (action as InputAction).selector;
      case ActionType.EXTRACT:
        return (action as ExtractAction).selector;
      case ActionType.CONDITION:
        return (action as ConditionAction).selector;
      case ActionType.CAPTCHA:
        return (action as CaptchaAction).selector;
      default:
        return undefined;
    }
  }

  /**
   * 设置操作的选择器
   */
  private setSelectorToAction(action: Action, selector: string): void {
    switch (action.type) {
      case ActionType.WAIT:
        (action as WaitAction).selector = selector;
        break;
      case ActionType.CLICK:
        (action as ClickAction).selector = selector;
        break;
      case ActionType.INPUT:
        (action as InputAction).selector = selector;
        break;
      case ActionType.EXTRACT:
        (action as ExtractAction).selector = selector;
        break;
      case ActionType.CONDITION:
        (action as ConditionAction).selector = selector;
        break;
      case ActionType.CAPTCHA:
        (action as CaptchaAction).selector = selector;
        break;
    }
  }

  /**
   * 替换字符串中的变量
   */
  private replaceVariables(text: string, variables: VariableMap): string {
    let result = text;
    
    if (variables.searchKeyword) {
      result = result.replace(/\{\{searchKeyword\}\}/g, variables.searchKeyword);
    }
    if (variables.mangaId) {
      result = result.replace(/\{\{mangaId\}\}/g, variables.mangaId);
    }
    if (variables.chapterId) {
      result = result.replace(/\{\{chapterId\}\}/g, variables.chapterId);
    }
    if (variables.pageIndex) {
      result = result.replace(/\{\{pageIndex\}\}/g, variables.pageIndex);
    }
    
    return result;
  }

  /**
   * 递归替换对象中的变量
   */
  private replaceObjectVariables(obj: ESObject, variables: VariableMap): ESObject {
    const result: ESObject = {};
    const keys = Object.keys(obj);
    
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i];
      const value: ESObject | ESObject[] | string | number | boolean = obj[key];
      
      if (typeof value === 'string') {
        result[key] = this.replaceVariables(value, variables);
      } else if (typeof value === 'object' && value !== null && !Array.isArray(value)) {
        result[key] = this.replaceObjectVariables(value as ESObject, variables);
      } else if (Array.isArray(value)) {
        const arr: (string | ESObject | number | boolean)[] = [];
        for (let j = 0; j < value.length; j++) {
          const item: ESObject | string | number | boolean = value[j];
          if (typeof item === 'string') {
            arr.push(this.replaceVariables(item, variables));
          } else if (typeof item === 'object' && item !== null) {
            arr.push(this.replaceObjectVariables(item as ESObject, variables));
          } else {
            arr.push(item);
          }
        }
        result[key] = arr;
      } else {
        result[key] = value;
      }
    }
    
    return result;
  }

  /**
   * 验证配置基础结构
   */
  private validateConfig(config: Record<string, Object>): ValidateConfigResult {
    if (!config || typeof config !== 'object') {
      return { valid: false, error: '配置必须是一个对象' };
    }

    const configObj = config as Record<string, Object>;

    // 验证元数据
    if (!configObj.metadata || typeof configObj.metadata !== 'object') {
      return { valid: false, error: '缺少metadata配置' };
    }

    const metadata = configObj.metadata as Record<string, Object>;
    if (!metadata.name || typeof metadata.name !== 'string') {
      return { valid: false, error: 'metadata.name必须是字符串' };
    }
    if (!metadata.version || typeof metadata.version !== 'string') {
      return { valid: false, error: 'metadata.version必须是字符串' };
    }
    if (!metadata.baseUrl || typeof metadata.baseUrl !== 'string') {
      return { valid: false, error: 'metadata.baseUrl必须是字符串' };
    }

    // 验证工作流
    if (!configObj.workflows || typeof configObj.workflows !== 'object') {
      return { valid: false, error: '缺少workflows配置' };
    }

    return { valid: true };
  }

  /**
   * 转换配置为类型化对象
   */
  private transformConfig(rawConfig: Record<string, Object>, warnings: string[]): MangaSourceConfig {
    const defaultSettings: DefaultSettings = {
      timeout: 30000,
      retryCount: 3,
      enableJavaScript: true,
      enableImages: true,
      enableCookies: true,
      bypassCloudflare: false,
      userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
    };
  
    const config: MangaSourceConfig = {
      metadata: rawConfig.metadata as MangaSourceMetadata,
      settings: rawConfig.settings as MangaSourceSettings || defaultSettings,
      workflows: {} as Workflow
    };
  
    // 转换工作流
    const workflows = rawConfig.workflows as Record<string, Object>;
    const workflowKeys = Object.keys(workflows);
    logger.debug(TAG, `解析工作流，数量: ${workflowKeys.length}, 名称: ${workflowKeys.join(', ')}`);
    
    for (let i = 0; i < workflowKeys.length; i++) {
      const name = workflowKeys[i];
      const workflow = workflows[name];
      
      if (workflow && typeof workflow === 'object') {
        let actions: Action[] = [];
        
        // 支持三种格式：
        // 1. 直接是数组: "search": [action1, action2, ...]
        // 2. 对象格式: "search": { "actions": [action1, action2, ...] }
        // 3. API格式: "search": { "type": "api", "method": "POST", ... }
        if (Array.isArray(workflow)) {
          // 格式1：直接是数组（WebView模式）
          actions = workflow as Action[];
          logger.debug(TAG, `工作流 ${name} 使用数组格式，操作数量: ${actions.length}`);
        } else {
          // 格式2或3：对象格式
          const workflowObj = workflow as Record<string, Object>;
          
          // 检查是否是API/HTTP模式
          if (workflowObj.type === 'api') {
            const apiAction = this.parseAPIWorkflow(workflowObj);
            actions = [apiAction];
          } else if (workflowObj.type === 'http') {
            const httpAction = this.parseHTTPWorkflow(workflowObj);
            actions = [httpAction];
          } else if (workflowObj.type === 'direct') {
            // 直接URL模式（用于getImageUrl等简单场景）
            logger.info(TAG, `工作流 ${name} 使用直接URL模式`);
            const directAction = this.parseDirectWorkflow(workflowObj);
            actions = [directAction];
          } else if (workflowObj.actions) {
            // 格式2：对象格式（WebView模式）
            actions = workflowObj.actions as Action[] || [];
            logger.debug(TAG, `工作流 ${name} 使用对象格式，操作数量: ${actions.length}`);
          } else {
            logger.warn(TAG, `工作流 ${name} 格式无法识别`);
          }
        }
        
        // 根据工作流名称设置到正确的类型
        switch (name) {
          case 'search':
            this.setWorkflowByType(config.workflows, WorkflowType.SEARCH, actions);
            break;
          case 'searchById':
            this.setWorkflowByType(config.workflows, WorkflowType.SEARCH_BY_ID, actions);
            break;
          case 'filter':
            this.setWorkflowByType(config.workflows, WorkflowType.FILTER, actions);
            break;
          case 'getMangaDetail':
            this.setWorkflowByType(config.workflows, WorkflowType.GET_MANGA_DETAIL, actions);
            break;
          case 'getChapterList':
            this.setWorkflowByType(config.workflows, WorkflowType.GET_CHAPTER_LIST, actions);
            break;
          case 'getPageList':
            this.setWorkflowByType(config.workflows, WorkflowType.GET_PAGE_LIST, actions);
            break;
          case 'loadMorePages':
            this.setWorkflowByType(config.workflows, WorkflowType.LOAD_MORE_PAGES, actions);
            break;
          case 'getImageUrl':
            this.setWorkflowByType(config.workflows, WorkflowType.GET_IMAGE_URL, actions);
            break;
          case 'popular':
            this.setWorkflowByType(config.workflows, WorkflowType.POPULAR, actions);
            break;
          case 'latest':
            this.setWorkflowByType(config.workflows, WorkflowType.LATEST, actions);
            break;
          case 'initialize':
            this.setWorkflowByType(config.workflows, WorkflowType.INITIALIZE, actions);
            break;
          default:
            warnings.push(`未知的工作流类型: ${name}`);
            logger.warn(TAG, `未知的工作流类型: ${name}`);
            break;
        }
      }
    }
  
    return config;
  }

  /**
   * 验证工作流配置
   */
  private validateWorkflows(config: MangaSourceConfig): ValidateWorkflowsResult {
    const requiredWorkflows: string[] = ['search', 'getMangaDetail', 'getChapterList', 'getPageList', 'getImageUrl'];
    
    for (let i = 0; i < requiredWorkflows.length; i++) {
      const workflowName = requiredWorkflows[i];
      const workflow = this.getWorkflow(config, workflowName);
      
      if (!workflow) {
        return { 
          valid: false, 
          error: `缺少必需的工作流: ${workflowName}` 
        };
      }

      if (!workflow || workflow.length === 0) {
        return { 
          valid: false, 
          error: `工作流 ${workflowName} 缺少操作序列` 
        };
      }

      // 验证操作序列
      for (let j = 0; j < workflow.length; j++) {
        const action = workflow[j];
        const validation = this.validateAction(action, j, workflowName);
        if (!validation.valid) {
          return validation;
        }
      }
    }

    return { valid: true };
  }

  /**
   * 验证单个操作
   */
  private validateAction(action: Action, index: number, workflowName: string): ValidateActionResult {
    // 验证基本字段
    if (!action.type) {
      return { 
        valid: false, 
        error: `工作流 ${workflowName} 第 ${index + 1} 个操作缺少type字段` 
      };
    }

    // 根据操作类型验证特定字段
    switch (action.type) {
      case ActionType.NAVIGATE:
        if (!this.hasUrlProperty(action) || !action.url) {
          return { 
            valid: false, 
            error: `工作流 ${workflowName} 第 ${index + 1} 个导航操作缺少url字段` 
          };
        }
        break;
      case ActionType.CLICK:
      case ActionType.INPUT:
        if (!this.hasSelectorProperty(action) || !action.selector) {
          return { 
            valid: false, 
            error: `工作流 ${workflowName} 第 ${index + 1} 个操作缺少selector字段` 
          };
        }
        break;
      case ActionType.EXTRACT:
        // extract操作支持多种数据源：
        // 1. selector: 从DOM元素提取
        // 2. source: "variable" - 从变量提取
        // 3. source: "script" - 从脚本结果提取
        const extractAction = action as ExtractAction;
        if (extractAction.source) {
          // 有source字段，验证对应的必需字段
          if (extractAction.source === 'variable' && !extractAction.variable) {
            return {
              valid: false,
              error: `工作流 ${workflowName} 第 ${index + 1} 个提取操作使用variable源但缺少variable字段`
            };
          }
          // source为script时，selector字段可选（可以是"script"或其他）
        } else {
          // 没有source字段，默认从DOM提取，需要selector
          if (!extractAction.selector) {
            return {
              valid: false,
              error: `工作流 ${workflowName} 第 ${index + 1} 个提取操作缺少selector字段`
            };
          }
        }
        // 验证必须有fields字段
        if (!extractAction.fields || Object.keys(extractAction.fields).length === 0) {
          return {
            valid: false,
            error: `工作流 ${workflowName} 第 ${index + 1} 个提取操作缺少fields字段或fields为空`
          };
        }
        break;
      case ActionType.WAIT:
        // wait操作支持多种等待条件：
        // 1. time: 等待固定时间 (需要duration或timeout字段)
        // 2. element: 等待元素出现 (需要selector字段)
        // 3. networkIdle: 等待网络空闲
        // 4. domReady: 等待DOM就绪
        const waitAction = action as WaitAction;
        if (waitAction.condition) {
          // 有condition字段，验证对应的必需字段
          if (waitAction.condition === 'element' && !waitAction.selector) {
            return {
              valid: false,
              error: `工作流 ${workflowName} 第 ${index + 1} 个等待操作使用element条件但缺少selector字段`
            };
          }
          if (waitAction.condition === 'time' && !waitAction.duration && !waitAction.timeout) {
            return {
              valid: false,
              error: `工作流 ${workflowName} 第 ${index + 1} 个等待操作使用time条件但缺少duration或timeout字段`
            };
          }
        } else {
          // 没有condition字段，检查是否有selector或duration/timeout
          if (!waitAction.selector && !waitAction.duration && !waitAction.timeout) {
            return {
              valid: false,
              error: `工作流 ${workflowName} 第 ${index + 1} 个等待操作缺少必需字段（selector、duration或timeout）`
            };
          }
        }
        break;
      case ActionType.CONDITION:
        if (!this.hasThenProperty(action) || !action.then) {
          return { 
            valid: false, 
            error: `工作流 ${workflowName} 第 ${index + 1} 个条件操作缺少then字段` 
          };
        }
        break;
      case ActionType.API_REQUEST:
        if (!this.hasUrlProperty(action) || !(action as APIRequestAction).url) {
          return {
            valid: false,
            error: `工作流 ${workflowName} 第 ${index + 1} 个API请求缺少url字段`
          };
        }
        break;
      case ActionType.HTTP_REQUEST:
        if (!this.hasUrlProperty(action) || !(action as HTTPRequestAction).url) {
          return {
            valid: false,
            error: `工作流 ${workflowName} 第 ${index + 1} 个HTTP请求缺少url字段`
          };
        }
        break;
    }

    return { valid: true };
  }

  /**
   * 获取工作流数量
   */
  private getWorkflowCount(workflows: Workflow): number {
    let count = 0;
    if (this.getWorkflowByType(workflows, WorkflowType.SEARCH)) count++;
    if (this.getWorkflowByType(workflows, WorkflowType.GET_MANGA_DETAIL)) count++;
    if (this.getWorkflowByType(workflows, WorkflowType.GET_CHAPTER_LIST)) count++;
    if (this.getWorkflowByType(workflows, WorkflowType.GET_PAGE_LIST)) count++;
    if (this.getWorkflowByType(workflows, WorkflowType.LOAD_MORE_PAGES)) count++;
    if (this.getWorkflowByType(workflows, WorkflowType.GET_IMAGE_URL)) count++;
    if (this.getWorkflowByType(workflows, WorkflowType.POPULAR)) count++;
    if (this.getWorkflowByType(workflows, WorkflowType.LATEST)) count++;
    if (this.getWorkflowByType(workflows, WorkflowType.FILTER)) count++;
    if (this.getWorkflowByType(workflows, WorkflowType.FAVORITES)) count++;
    if (this.getWorkflowByType(workflows, WorkflowType.HISTORY)) count++;
    if (this.getWorkflowByType(workflows, WorkflowType.INITIALIZE)) count++;
    if (this.getWorkflowByType(workflows, WorkflowType.GET_MANGA_LIST)) count++;
    return count;
  }

  /**
   * 获取工作流名称列表
   */
  private getWorkflowNames(workflows: Workflow): string[] {
    const names: string[] = [];
    if (this.getWorkflowByType(workflows, WorkflowType.SEARCH)) names.push('search');
    if (this.getWorkflowByType(workflows, WorkflowType.GET_MANGA_DETAIL)) names.push('getMangaDetail');
    if (this.getWorkflowByType(workflows, WorkflowType.GET_CHAPTER_LIST)) names.push('getChapterList');
    if (this.getWorkflowByType(workflows, WorkflowType.GET_PAGE_LIST)) names.push('getPageList');
    if (this.getWorkflowByType(workflows, WorkflowType.LOAD_MORE_PAGES)) names.push('loadMorePages');
    if (this.getWorkflowByType(workflows, WorkflowType.GET_IMAGE_URL)) names.push('getImageUrl');
    if (this.getWorkflowByType(workflows, WorkflowType.POPULAR)) names.push('popular');
    if (this.getWorkflowByType(workflows, WorkflowType.LATEST)) names.push('latest');
    if (this.getWorkflowByType(workflows, WorkflowType.FAVORITES)) names.push('favorites');
    if (this.getWorkflowByType(workflows, WorkflowType.HISTORY)) names.push('history');
    if (this.getWorkflowByType(workflows, WorkflowType.FILTER)) names.push('filter');
    if (this.getWorkflowByType(workflows, WorkflowType.INITIALIZE)) names.push('initialize');
    if (this.getWorkflowByType(workflows, WorkflowType.GET_MANGA_LIST)) names.push('getMangaList');
    return names;
  }

  /**
   * 解析API工作流
   */
  private parseAPIWorkflow(workflowObj: Record<string, Object>): Action {
    logger.debug(TAG, '解析API工作流');
    logger.debug(TAG, `API工作流字段: method=${workflowObj.method}, url=${workflowObj.url}, hasBody=${!!workflowObj.body}, hasExtract=${!!workflowObj.extract}`);
    
    const method = (workflowObj.method as string) || 'POST';
    const url = workflowObj.url as string || '';
    
    // 处理headers：可能是对象或字符串模板
    let headers: Record<string, string> | undefined = undefined;
    if (workflowObj.headers) {
      if (typeof workflowObj.headers === 'string') {
        // 如果是字符串模板（如"{{api.headers}}"），创建一个特殊的标记对象
        headers = { '__template__': workflowObj.headers as string };
      } else {
        headers = workflowObj.headers as Record<string, string>;
      }
    }
    
    const apiAction: APIRequestAction = {
      type: ActionType.API_REQUEST,
      method: method as 'GET' | 'POST' | 'PUT' | 'DELETE',
      url: url,
      params: workflowObj.params as Record<string, string>,
      headers: headers,
      body: workflowObj.body as ESObject,
      extract: workflowObj.extract as ExtractConfig,
      description: (workflowObj.description as string) || 'API请求'
    };
    
    logger.debug(TAG, `解析后的API操作: method=${apiAction.method}, url=${apiAction.url}, hasParams=${!!apiAction.params}`);
    return apiAction;
  }

  private parseHTTPWorkflow(workflowObj: Record<string, Object>): Action {
    const method = (workflowObj.method as string) || 'GET';
    const url = workflowObj.url as string || '';
    let headers: Record<string, string> | undefined = undefined;
    if (workflowObj.headers) {
      if (typeof workflowObj.headers === 'string') {
        headers = { '__template__': workflowObj.headers as string };
      } else {
        headers = workflowObj.headers as Record<string, string>;
      }
    }
    const httpAction: HTTPRequestAction = {
      type: ActionType.HTTP_REQUEST,
      method: method as 'GET' | 'POST' | 'PUT' | 'DELETE',
      url: url,
      headers: headers,
      body: workflowObj.body as ESObject,
      description: (workflowObj.description as string) || 'HTTP请求'
    };
    return httpAction;
  }

  /**
   * 解析直接URL工作流（用于getImageUrl等简单场景）
   */
  private parseDirectWorkflow(workflowObj: Record<string, Object>): Action {
    logger.debug(TAG, '解析直接URL工作流');
    
    // 直接URL模式转换为Script操作，返回URL字符串
    const scriptAction: ScriptAction = {
      type: ActionType.SCRIPT,
      code: `return "${workflowObj.url as string}";`,
      description: '直接返回URL'
    };
    
    return scriptAction;
  }

  /**
   * 获取配置摘要信息
   */
  getConfigSummary(config: MangaSourceConfig): ConfigSummaryResult {
    const userAgentSummary = config.settings.userAgent ? 
      config.settings.userAgent.substring(0, 50) + '...' : 
      'Default User Agent';

    return {
      name: config.metadata.name,
      version: config.metadata.version,
      baseUrl: config.metadata.baseUrl,
      author: config.metadata.author,
      description: config.metadata.description,
      workflowCount: this.getWorkflowCount(config.workflows),
      workflows: this.getWorkflowNames(config.workflows),
      settings: {
        timeout: config.settings.timeout,
        retryCount: config.settings.retryCount,
        userAgent: userAgentSummary
      }
    };
  }
}
