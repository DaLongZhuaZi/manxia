// 文件路径: src/main/ets/Framework/Core/ErrorHandler.ets
/**
 * 错误处理系统
 * 提供游戏错误的捕获、记录、分类和恢复机制
 */

import { logger } from '../../Utils/Logger';
import { eventBus, GameEvent, IEventPayload } from '../EventBus';

const ERROR_HANDLER_TAG = 'ErrorHandler';

/**
 * 错误严重程度
 */
export enum ErrorSeverity {
  LOW = 'low',
  MEDIUM = 'medium',
  HIGH = 'high',
  CRITICAL = 'critical'
}

/**
 * 错误类别
 */
export enum ErrorCategory {
  SYSTEM = 'system',
  NETWORK = 'network',
  RESOURCE = 'resource',
  VALIDATION = 'validation',
  BUSINESS_LOGIC = 'business_logic',
  UI = 'ui',
  PERFORMANCE = 'performance',
  SECURITY = 'security',
  COMPONENT = 'component'
}

/**
 * 错误上下文信息
 */
export interface ErrorContext {
  component?: string;
  method?: string;
  userId?: string;
  sessionId?: string;
  timestamp: number;
  stackTrace?: string;
  additionalData?: Record<string, string | number | boolean>;
}

/**
 * 游戏错误类
 */
export class GameError extends Error {
  public readonly severity: ErrorSeverity;
  public readonly category: ErrorCategory;
  public readonly context: ErrorContext;
  public readonly code: string;
  public readonly isRecoverable: boolean;

  constructor(
    message: string,
    severity: ErrorSeverity = ErrorSeverity.MEDIUM,
    category: ErrorCategory = ErrorCategory.SYSTEM,
    context: Partial<ErrorContext> = {},
    code: string = 'UNKNOWN_ERROR',
    isRecoverable: boolean = true
  ) {
    super(message);
    this.name = 'GameError';
    this.severity = severity;
    this.category = category;
    this.code = code;
    this.isRecoverable = isRecoverable;
    this.context = {
      timestamp: Date.now(),
      stackTrace: this.stack,
      component: context.component,
      method: context.method,
      userId: context.userId,
      sessionId: context.sessionId,
      additionalData: context.additionalData
    };
  }
}

/**
 * 错误恢复策略
 */
export interface ErrorRecoveryStrategy {
  canHandle(error: GameError): boolean;
  recover(error: GameError): Promise<boolean>;
  getDescription(): string;
}

/**
 * 错误统计信息
 */
export interface ErrorStatistics {
  totalErrors: number;
  errorsByCategory: Record<ErrorCategory, number>;
  errorsBySeverity: Record<ErrorSeverity, number>;
  recentErrors: GameError[];
  recoverySuccessRate: number;
}

/**
 * 错误事件载荷
 */
export class ErrorEventPayload implements IEventPayload {
  public error: GameError;
  public wasRecovered: boolean;

  constructor(error: GameError, wasRecovered: boolean = false) {
    this.error = error;
    this.wasRecovered = wasRecovered;
  }
}

/**
 * 全局错误处理器
 */
export class ErrorHandler {
  private static instance: ErrorHandler;
  private recoveryStrategies: ErrorRecoveryStrategy[] = [];
  private errorHistory: GameError[] = [];
  private maxHistorySize: number = 100;
  private statistics: ErrorStatistics;
  private isEnabled: boolean = true;

  private constructor() {
    this.statistics = {
      totalErrors: 0,
      errorsByCategory: {} as Record<ErrorCategory, number>,
      errorsBySeverity: {} as Record<ErrorSeverity, number>,
      recentErrors: [],
      recoverySuccessRate: 0
    };

    this.initializeDefaultStrategies();
    this.setupGlobalErrorHandling();
  }

  public static getInstance(): ErrorHandler {
    try {
      if (!ErrorHandler.instance) {
        ErrorHandler.instance = new ErrorHandler();
        try {
          logger.info(ERROR_HANDLER_TAG, 'ErrorHandler 实例已创建');
        } catch {
          // 如果logger未初始化，使用console作为后备
          console.log('[NGF] ErrorHandler: ErrorHandler 实例已创建');
        }
      }
      return ErrorHandler.instance;
    } catch (error) {
      try {
        logger.error(ERROR_HANDLER_TAG, `ErrorHandler.getInstance() 失败: ${error instanceof Error ? error.message : String(error)}`);
      } catch {
        // 如果logger未初始化，使用console作为后备
        console.error('[NGF] ErrorHandler: ErrorHandler.getInstance() 失败:', error);
      }
      throw new Error(error instanceof Error ? error.message : String(error));
    }
  }

  /**
   * 处理错误
   */
  public async handleError(error: Error | GameError, context?: Partial<ErrorContext>): Promise<boolean> {
    if (!this.isEnabled) {
      return false;
    }

    let gameError: GameError;
    
    if (error instanceof GameError) {
      gameError = error;
      // 合并额外的上下文信息
      if (context) {
        if (context.component !== undefined) gameError.context.component = context.component;
        if (context.method !== undefined) gameError.context.method = context.method;
        if (context.userId !== undefined) gameError.context.userId = context.userId;
        if (context.sessionId !== undefined) gameError.context.sessionId = context.sessionId;
        if (context.additionalData !== undefined) gameError.context.additionalData = context.additionalData;
      }
    } else {
      // 将普通错误转换为GameError
      gameError = new GameError(
        error.message,
        ErrorSeverity.MEDIUM,
        ErrorCategory.SYSTEM,
        {
          timestamp: Date.now(),
          stackTrace: error.stack,
          component: context?.component,
          method: context?.method,
          userId: context?.userId,
          sessionId: context?.sessionId,
          additionalData: context?.additionalData
        } as ErrorContext,
        'CONVERTED_ERROR'
      );
    }

    // 记录错误
    this.recordError(gameError);

    // 尝试恢复
    const wasRecovered = await this.attemptRecovery(gameError);

    // 发布错误事件
    eventBus.publish(GameEvent.ERROR_OCCURRED, new ErrorEventPayload(gameError, wasRecovered));

    return wasRecovered;
  }

  /**
   * 注册错误恢复策略
   */
  public registerRecoveryStrategy(strategy: ErrorRecoveryStrategy): void {
    this.recoveryStrategies.push(strategy);
    logger.debug(ERROR_HANDLER_TAG, `🔧 错误恢复策略已注册: ${strategy.getDescription()}`);
  }

  /**
   * 创建游戏错误
   */
  public createError(
    message: string,
    severity: ErrorSeverity = ErrorSeverity.MEDIUM,
    category: ErrorCategory = ErrorCategory.SYSTEM,
    context: Partial<ErrorContext> = {},
    code: string = 'CUSTOM_ERROR',
    isRecoverable: boolean = true
  ): GameError {
    return new GameError(message, severity, category, context, code, isRecoverable);
  }

  /**
   * 获取错误统计信息
   */
  public getStatistics(): ErrorStatistics {
    const statisticsCopy: ErrorStatistics = {
      totalErrors: this.statistics.totalErrors,
      errorsByCategory: this.statistics.errorsByCategory,
      errorsBySeverity: this.statistics.errorsBySeverity,
      recentErrors: this.statistics.recentErrors,
      recoverySuccessRate: this.statistics.recoverySuccessRate
    };
    return statisticsCopy;
  }

  /**
   * 清理错误历史
   */
  public clearHistory(): void {
    this.errorHistory = [];
    this.statistics.recentErrors = [];
    this.statistics.totalErrors = 0;
    this.statistics.errorsByCategory = {} as Record<ErrorCategory, number>;
    this.statistics.errorsBySeverity = {} as Record<ErrorSeverity, number>;
    logger.info(ERROR_HANDLER_TAG, '🧹 错误历史已清理');
  }

  /**
   * 启用/禁用错误处理
   */
  public setEnabled(enabled: boolean): void {
    this.isEnabled = enabled;
    logger.info(ERROR_HANDLER_TAG, `🔄 错误处理已${enabled ? '启用' : '禁用'}`);
  }

  /**
   * 记录错误
   */
  private recordError(error: GameError): void {
    // 添加到历史记录
    this.errorHistory.push(error);
    if (this.errorHistory.length > this.maxHistorySize) {
      this.errorHistory.shift();
    }

    // 更新统计信息
    this.statistics.totalErrors++;
    this.statistics.errorsByCategory[error.category] = 
      (this.statistics.errorsByCategory[error.category] || 0) + 1;
    this.statistics.errorsBySeverity[error.severity] = 
      (this.statistics.errorsBySeverity[error.severity] || 0) + 1;
    this.statistics.recentErrors = this.errorHistory.slice(-10);

    // 记录日志
    const logMessage = `${error.code}: ${error.message}`;
    switch (error.severity) {
      case ErrorSeverity.LOW:
        logger.debug(ERROR_HANDLER_TAG, logMessage);
        break;
      case ErrorSeverity.MEDIUM:
        logger.warn(ERROR_HANDLER_TAG, logMessage);
        break;
      case ErrorSeverity.HIGH:
        logger.error(ERROR_HANDLER_TAG, logMessage);
        break;
      case ErrorSeverity.CRITICAL:
        logger.error(ERROR_HANDLER_TAG, `🚨 CRITICAL: ${logMessage}`);
        break;
    }
  }

  /**
   * 尝试错误恢复
   */
  private async attemptRecovery(error: GameError): Promise<boolean> {
    if (!error.isRecoverable) {
      logger.warn(ERROR_HANDLER_TAG, `❌ 错误不可恢复: ${error.code}`);
      return false;
    }

    for (const strategy of this.recoveryStrategies) {
      if (strategy.canHandle(error)) {
        try {
          logger.info(ERROR_HANDLER_TAG, `🔄 尝试恢复策略: ${strategy.getDescription()}`);
          const success = await strategy.recover(error);
          if (success) {
            logger.info(ERROR_HANDLER_TAG, `✅ 错误恢复成功: ${error.code}`);
            this.updateRecoverySuccessRate(true);
            return true;
          }
        } catch (recoveryError) {
          logger.error(ERROR_HANDLER_TAG, `恢复策略失败: ${strategy.getDescription()}`, recoveryError);
        }
      }
    }

    this.updateRecoverySuccessRate(false);
    logger.warn(ERROR_HANDLER_TAG, `❌ 所有恢复策略都失败了: ${error.code}`);
    return false;
  }

  /**
   * 更新恢复成功率
   */
  private updateRecoverySuccessRate(success: boolean): void {
    const recentAttempts = this.errorHistory.slice(-20);
    const successCount = recentAttempts.filter(e => e.isRecoverable).length;
    this.statistics.recoverySuccessRate = recentAttempts.length > 0 
      ? (successCount / recentAttempts.length) * 100 
      : 0;
  }

  /**
   * 初始化默认恢复策略
   */
  private initializeDefaultStrategies(): void {
    // 资源加载失败恢复策略
class ResourceRecoveryStrategy implements ErrorRecoveryStrategy {
  canHandle(error: GameError): boolean {
    return error.category === ErrorCategory.RESOURCE;
  }

  async recover(error: GameError): Promise<boolean> {
    logger.info(ERROR_HANDLER_TAG, '🔄 尝试重新加载资源');
    // 这里可以实现资源重新加载逻辑
    return true;
  }

  getDescription(): string {
    return '资源重新加载策略';
  }
}

const resourceRecoveryStrategy: ErrorRecoveryStrategy = new ResourceRecoveryStrategy();
    this.registerRecoveryStrategy(resourceRecoveryStrategy);

    // 网络错误恢复策略
    class NetworkRecoveryStrategy implements ErrorRecoveryStrategy {
      canHandle(error: GameError): boolean {
        return error.category === ErrorCategory.NETWORK;
      }

      async recover(error: GameError): Promise<boolean> {
        logger.info(ERROR_HANDLER_TAG, '🔄 尝试重新连接网络');
        // 这里可以实现网络重连逻辑
        return false; // 暂时返回false，需要具体实现
      }

      getDescription(): string {
        return '网络重连策略';
      }
    }

    const networkRecoveryStrategy: ErrorRecoveryStrategy = new NetworkRecoveryStrategy();
        this.registerRecoveryStrategy(networkRecoveryStrategy);

        // UI错误恢复策略
    class UIRecoveryStrategy implements ErrorRecoveryStrategy {
      canHandle(error: GameError): boolean {
        return error.category === ErrorCategory.UI;
      }

      async recover(error: GameError): Promise<boolean> {
        logger.info(ERROR_HANDLER_TAG, '🔄 尝试重置UI状态');
        // 这里可以实现UI重置逻辑
        return true;
      }

      getDescription(): string {
        return 'UI状态重置策略';
      }
    }

    const uiRecoveryStrategy: ErrorRecoveryStrategy = new UIRecoveryStrategy();
        this.registerRecoveryStrategy(uiRecoveryStrategy);
      }

  /**
   * 设置全局错误处理
   */
  private setupGlobalErrorHandling(): void {
    // 这里可以设置全局的未捕获异常处理
    // 注意：HarmonyOS可能有特定的全局错误处理机制
    logger.info(ERROR_HANDLER_TAG, '🛡️ 全局错误处理已设置');
  }

  /**
   * 释放资源
   */
  public dispose(): void {
    this.clearHistory();
    this.recoveryStrategies = [];
    this.isEnabled = false;
    logger.info(ERROR_HANDLER_TAG, '🗑️ 错误处理器已释放');
  }
}

// 导出全局错误处理器实例
export const errorHandler = ErrorHandler.getInstance();

// 便捷的错误处理函数
export function handleError(error: Error | GameError, context?: Partial<ErrorContext>): Promise<boolean> {
  return errorHandler.handleError(error, context);
}

export function createGameError(
  message: string,
  severity: ErrorSeverity = ErrorSeverity.MEDIUM,
  category: ErrorCategory = ErrorCategory.SYSTEM,
  context: Partial<ErrorContext> = {},
  code: string = 'CUSTOM_ERROR',
  isRecoverable: boolean = true
): GameError {
  return errorHandler.createError(message, severity, category, context, code, isRecoverable);
}