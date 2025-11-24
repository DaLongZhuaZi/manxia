// 文件路径: entry/src/main/ets/Framework/Workflow/WorkflowCapabilities.ets
/**
 * 工作流能力系统
 * 允许图源通过JSON配置声明和使用各种能力
 */

import { logger } from '../../Utils/Logger';
import DynamicUrlResolver, { type UrlResolverConfig } from '../Utils/DynamicUrlResolver';
import ChineseConverter, { type ChineseConversionConfig } from '../Utils/ChineseConverter';
import PaginationHandler, { type PaginationConfig, type PaginationResult } from '../Utils/PaginationHandler';
import UserAgentManager, { type UserAgentRotationConfig } from '../Network/UserAgentManager';
import ErrorHandler, { type RetryConfig } from '../Network/ErrorHandler';
import SessionManager, { type SessionRefreshConfig } from '../Managers/SessionManager';

const TAG = 'WorkflowCapabilities';

/**
 * 能力类型
 */
export type CapabilityType = 
  | 'urlResolver'
  | 'chineseConverter'
  | 'pagination'
  | 'userAgentRotation'
  | 'errorRetry'
  | 'sessionManagement';

/**
 * 能力配置
 */
export interface CapabilityConfig {
  type: CapabilityType;
  enabled: boolean;
  config: Object;
}

/**
 * 工作流上下文
 */
export interface WorkflowContext {
  sourceId: number;
  variables: Record<string, string>;
  capabilities: Map<CapabilityType, Object>;
}

/**
 * 工作流能力管理器
 */
export class WorkflowCapabilities {
  private static instance: WorkflowCapabilities | null = null;
  
  // 能力实例缓存
  private urlResolver: DynamicUrlResolver;
  private chineseConverter: ChineseConverter;
  private paginationHandler: PaginationHandler;
  private userAgentManager: UserAgentManager;
  private errorHandler: ErrorHandler;
  private sessionManager: SessionManager;

  private constructor() {
    this.urlResolver = DynamicUrlResolver.getInstance();
    this.chineseConverter = ChineseConverter.getInstance();
    this.paginationHandler = PaginationHandler.getInstance();
    this.userAgentManager = UserAgentManager.getInstance();
    this.errorHandler = ErrorHandler.getInstance();
    this.sessionManager = SessionManager.getInstance();
  }

  static getInstance(): WorkflowCapabilities {
    if (!WorkflowCapabilities.instance) {
      WorkflowCapabilities.instance = new WorkflowCapabilities();
    }
    return WorkflowCapabilities.instance;
  }

  /**
   * 从JSON配置初始化能力
   */
  initializeCapabilities(sourceConfig: Record<string, Object>): Map<CapabilityType, Object> {
    const capabilities = new Map<CapabilityType, Object>();
    
    // 1. URL解析能力
    if (this.hasCapability(sourceConfig, 'metadata', 'alternativeUrls')) {
      const metadata = sourceConfig['metadata'] as Record<string, Object>;
      const urlConfig: UrlResolverConfig = {
        baseUrl: String(metadata['baseUrl'] || ''),
        alternativeUrls: metadata['alternativeUrls'] as Record<string, string>,
        variables: {}
      };
      capabilities.set('urlResolver', urlConfig);
      logger.info(TAG, '启用URL解析能力');
    }

    // 2. 简繁转换能力
    if (this.hasCapability(sourceConfig, 'textProcessing', 'chineseConversion')) {
      const textProcessing = sourceConfig['textProcessing'] as Record<string, Object>;
      const conversionConfig = textProcessing['chineseConversion'] as ChineseConversionConfig;
      if (conversionConfig.enabled) {
        capabilities.set('chineseConverter', conversionConfig);
        logger.info(TAG, '启用简繁转换能力');
      }
    }

    // 3. 分页能力
    if (this.hasCapability(sourceConfig, 'pagination')) {
      const paginationConfig = sourceConfig['pagination'] as PaginationConfig;
      capabilities.set('pagination', paginationConfig);
      logger.info(TAG, `启用分页能力: ${paginationConfig.type}`);
    }

    // 4. User-Agent轮换能力
    if (this.hasCapability(sourceConfig, 'network', 'userAgentRotation')) {
      const network = sourceConfig['network'] as Record<string, Object>;
      const uaConfig = network['userAgentRotation'] as UserAgentRotationConfig;
      if (uaConfig.enabled) {
        capabilities.set('userAgentRotation', uaConfig);
        logger.info(TAG, `启用UA轮换能力: ${uaConfig.strategy}`);
      }
    }

    // 5. 错误重试能力
    if (this.hasCapability(sourceConfig, 'errorHandling', 'retry')) {
      const errorHandling = sourceConfig['errorHandling'] as Record<string, Object>;
      const retryConfig = errorHandling['retry'] as RetryConfig;
      if (retryConfig.enabled) {
        capabilities.set('errorRetry', retryConfig);
        logger.info(TAG, `启用错误重试能力: ${retryConfig.strategy}`);
      }
    }

    // 6. 会话管理能力
    if (this.hasCapability(sourceConfig, 'authentication', 'sessionRefresh')) {
      const auth = sourceConfig['authentication'] as Record<string, Object>;
      const sessionConfig = auth['sessionRefresh'] as SessionRefreshConfig;
      if (sessionConfig.enabled) {
        capabilities.set('sessionManagement', sessionConfig);
        logger.info(TAG, '启用会话管理能力');
      }
    }

    return capabilities;
  }

  /**
   * 检查是否有某个能力
   */
  private hasCapability(config: Record<string, Object>, ...path: string[]): boolean {
    let current: Object = config;
    
    for (const key of path) {
      if (current && typeof current === 'object') {
        const record = current as Record<string, Object>;
        if (key in record) {
          current = record[key];
        } else {
          return false;
        }
      } else {
        return false;
      }
    }
    
    return current !== undefined && current !== null;
  }

  /**
   * 应用URL解析能力
   */
  applyUrlResolver(
    template: string,
    context: WorkflowContext
  ): string {
    const capability = context.capabilities.get('urlResolver');
    if (!capability) {
      return template;
    }

    const config = capability as UrlResolverConfig;
    config.variables = context.variables;
    
    return this.urlResolver.resolveUrl(template, config);
  }

  /**
   * 应用简繁转换能力
   */
  applyChineseConverter(
    data: Record<string, Object>,
    context: WorkflowContext
  ): Record<string, Object> {
    const capability = context.capabilities.get('chineseConverter');
    if (!capability) {
      return data;
    }

    const config = capability as ChineseConversionConfig;
    return this.chineseConverter.convertObject(data, config);
  }

  /**
   * 应用分页能力
   */
  applyPagination(
    context: WorkflowContext,
    response?: Object
  ): PaginationResult | null {
    const capability = context.capabilities.get('pagination');
    if (!capability) {
      return null;
    }

    const config = capability as PaginationConfig;
    const sourceKey = `source_${context.sourceId}`;

    // 初始化分页状态（如果还没有）
    if (!this.paginationHandler.getPaginationState(sourceKey)) {
      this.paginationHandler.initializePagination(sourceKey, config);
    }

    // 根据分页类型处理
    switch (config.type) {
      case 'offset':
        return this.paginationHandler.handleOffsetPagination(sourceKey, config);
      case 'page':
        return this.paginationHandler.handlePagePagination(sourceKey, config);
      case 'cursor':
        if (response) {
          return this.paginationHandler.handleCursorPagination(sourceKey, response, config);
        }
        return null;
      default:
        return null;
    }
  }

  /**
   * 获取分页参数
   */
  getPaginationParams(context: WorkflowContext): Record<string, string> {
    const capability = context.capabilities.get('pagination');
    if (!capability) {
      return {};
    }

    const config = capability as PaginationConfig;
    const sourceKey = `source_${context.sourceId}`;
    
    return this.paginationHandler.buildPaginationParams(sourceKey, config);
  }

  /**
   * 获取User-Agent
   */
  getUserAgent(context: WorkflowContext): string | null {
    const capability = context.capabilities.get('userAgentRotation');
    if (!capability) {
      return null;
    }

    const config = capability as UserAgentRotationConfig;
    return this.userAgentManager.getUserAgent(context.sourceId, config);
  }

  /**
   * 获取重试配置
   */
  getRetryConfig(context: WorkflowContext): RetryConfig | null {
    const capability = context.capabilities.get('errorRetry');
    if (!capability) {
      return null;
    }

    return capability as RetryConfig;
  }

  /**
   * 启动会话管理
   */
  async startSessionManagement(
    context: WorkflowContext,
    refreshCallback: () => Promise<void>
  ): Promise<void> {
    const capability = context.capabilities.get('sessionManagement');
    if (!capability) {
      return;
    }

    const config = capability as SessionRefreshConfig;
    await this.sessionManager.startSessionRefresh(context.sourceId, config, refreshCallback);
  }

  /**
   * 停止会话管理
   */
  stopSessionManagement(sourceId: number): void {
    this.sessionManager.stopSessionRefresh(sourceId);
  }

  /**
   * 创建工作流上下文
   */
  createContext(
    sourceId: number,
    sourceConfig: Record<string, Object>,
    variables?: Record<string, string>
  ): WorkflowContext {
    const capabilities = this.initializeCapabilities(sourceConfig);
    
    const context: WorkflowContext = {
      sourceId: sourceId,
      variables: variables || {},
      capabilities: capabilities
    };

    logger.info(TAG, `创建工作流上下文: sourceId=${sourceId}, capabilities=${capabilities.size}`);
    return context;
  }

  /**
   * 检查上下文是否有某个能力
   */
  hasCapabilityInContext(context: WorkflowContext, type: CapabilityType): boolean {
    return context.capabilities.has(type);
  }

  /**
   * 获取能力统计
   */
  getCapabilityStats(context: WorkflowContext): string {
    const stats: string[] = [];
    
    context.capabilities.forEach((config, type) => {
      stats.push(type);
    });

    return `启用的能力 (${stats.length}): ${stats.join(', ')}`;
  }

  /**
   * 重置分页状态
   */
  resetPagination(sourceId: number): void {
    const sourceKey = `source_${sourceId}`;
    this.paginationHandler.resetPagination(sourceKey);
  }

  /**
   * 清理资源
   */
  cleanup(sourceId: number): void {
    this.resetPagination(sourceId);
    this.stopSessionManagement(sourceId);
    this.userAgentManager.clearSessionUA(sourceId);
    logger.info(TAG, `清理资源: sourceId=${sourceId}`);
  }
}

export default WorkflowCapabilities;
