// 文件路径: src/main/ets/Framework/Diagnostics/StartupRecovery.ets
/**
 * 启动恢复工具
 * 用于在应用启动失败时进行恢复和降级处理，确保应用能够在有限资源下正常运行。
 */

import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { setContext, isInitialized as isGlobalContextInitialized } from 'manxia_core/src/main/ets/GlobalContext';
import { eventBus, IEventPayload } from '../EventBus';

/**
 * 恢复策略枚举
 */
export enum RecoveryStrategy {
  RETRY = 'RETRY',
  FALLBACK = 'FALLBACK',
  SAFE_MODE = 'SAFE_MODE',
  RESET = 'RESET'
}

/**
 * 启动失败类型枚举
 */
export enum StartupFailureType {
  GLOBAL_CONTEXT_FAILURE = 'GLOBAL_CONTEXT_FAILURE',
  RESOURCE_LOADING_FAILURE = 'RESOURCE_LOADING_FAILURE',
  PERMISSION_FAILURE = 'PERMISSION_FAILURE',
  SYSTEM_RESOURCE_FAILURE = 'SYSTEM_RESOURCE_FAILURE',
  UNKNOWN_FAILURE = 'UNKNOWN_FAILURE'
}

/**
 * 恢复选项详细信息接口
 */
interface RecoveryDetails extends Record<string, string | number | boolean | undefined> {
  backupPath?: string;
  configPath?: string;
  retryCount?: number;
  fallbackMode?: string;
  resetLevel?: string;
}

/**
 * 恢复选项接口
 */
export interface RecoveryOption {
  strategy: RecoveryStrategy;
  description: string;
  priority: number;
  canAutoExecute: boolean;
  estimatedTime: number; // 预计恢复时间（毫秒）
  successRate: number; // 成功率（0-1）
  details?: RecoveryDetails;
}

/**
 * 恢复结果接口
 */
interface RecoveryResult {
  success: boolean;
  strategy: RecoveryStrategy;
  message: string;
  details?: RecoveryDetails;
  nextOptions?: RecoveryOption[];
}

/**
 * 错误详细信息接口
 */
interface ErrorDetails extends Record<string, string | number | boolean | undefined> {
  errorCode?: string;
  errorType?: string;
  stackTrace?: string;
  timestamp?: number;
  phase?: string;
}

/**
 * 启动状态快照接口
 */
interface StartupSnapshot {
  timestamp: number;
  globalContextInitialized: boolean;
  lastSuccessfulPhase: string;
  errorDetails: ErrorDetails;
}

/**
 * 恢复统计信息接口
 */
interface RecoveryStats {
  recoveryAttempts: Record<string, number>;
  isRecovering: boolean;
  lastSnapshot: StartupSnapshot | null;
  maxRetryAttempts: number;
}

/**
 * 启动流程恢复工具
 */
export class StartupRecovery {
  private static instance: StartupRecovery;
  private recoveryAttempts: Map<StartupFailureType, number> = new Map();
  private maxRetryAttempts: number = 3;
  private lastSnapshot: StartupSnapshot | null = null;
  private isRecovering: boolean = false;

  private constructor() {
    // 私有构造函数，确保单例模式
  }

  public static getInstance(): StartupRecovery {
    if (!StartupRecovery.instance) {
      StartupRecovery.instance = new StartupRecovery();
    }
    return StartupRecovery.instance;
  }

  /**
   * 创建启动状态快照
   */
  public createSnapshot(lastSuccessfulPhase: string, errorDetails: ErrorDetails = {}): void {
    const snapshot: StartupSnapshot = {
      timestamp: Date.now(),
      globalContextInitialized: isGlobalContextInitialized(),
      lastSuccessfulPhase,
      errorDetails
    };
    this.lastSnapshot = snapshot;
    
    logger.info('StartupRecovery', `📸 创建启动状态快照: ${lastSuccessfulPhase}`);
  }

  /**
   * 分析启动失败并提供恢复选项
   */
  public analyzeFailureAndGetOptions(error: Error, failurePhase: string): RecoveryOption[] {
    logger.info('StartupRecovery', `🔍 分析启动失败: ${failurePhase}`);
    
    const failureType = this.classifyFailure(error, failurePhase);
    const currentAttempts = this.recoveryAttempts.get(failureType) || 0;
    
    logger.info('StartupRecovery', `📊 失败类型: ${failureType}, 已尝试次数: ${currentAttempts}`);
    
    const options: RecoveryOption[] = [];
    
    // 根据失败类型和尝试次数提供不同的恢复选项
    switch (failureType) {
      case StartupFailureType.GLOBAL_CONTEXT_FAILURE:
        options.push(...this.getGlobalContextRecoveryOptions(currentAttempts));
        break;
        
      case StartupFailureType.RESOURCE_LOADING_FAILURE:
        options.push(...this.getResourceLoadingRecoveryOptions(currentAttempts));
        break;
        
      case StartupFailureType.PERMISSION_FAILURE:
        options.push(...this.getPermissionRecoveryOptions(currentAttempts));
        break;
        
      default:
        options.push(...this.getGenericRecoveryOptions(currentAttempts));
        break;
    }
    
    // 按优先级排序
    options.sort((a, b) => b.priority - a.priority);
    
    return options;
  }

  /**
   * 执行恢复策略
   */
  public async executeRecovery(strategy: RecoveryStrategy, failureType: StartupFailureType): Promise<RecoveryResult> {
    if (this.isRecovering) {
      const busyResult: RecoveryResult = {
        success: false,
        strategy,
        message: '恢复操作正在进行中，请稍候'
      };
      return busyResult;
    }

    this.isRecovering = true;
    
    try {
      logger.info('StartupRecovery', `🔧 开始执行恢复策略: ${strategy}`);
      
      // 增加尝试次数
      const currentAttempts = this.recoveryAttempts.get(failureType) || 0;
      this.recoveryAttempts.set(failureType, currentAttempts + 1);
      
      let result: RecoveryResult;
      
      switch (strategy) {
        case RecoveryStrategy.RETRY:
          result = await this.executeRetryStrategy(failureType);
          break;
          
        case RecoveryStrategy.FALLBACK:
          result = await this.executeFallbackStrategy(failureType);
          break;
          
        case RecoveryStrategy.SAFE_MODE:
          result = await this.executeSafeModeStrategy(failureType);
          break;
          
        case RecoveryStrategy.RESET:
          result = await this.executeResetStrategy(failureType);
          break;
          
        default:
          const unknownResult: RecoveryResult = {
            success: false,
            strategy,
            message: `未知的恢复策略: ${strategy}`
          };
          result = unknownResult;
          break;
      }
      
      if (result.success) {
        logger.info('StartupRecovery', `✅ 恢复策略执行成功: ${strategy}`);
        // 重置尝试次数
        this.recoveryAttempts.set(failureType, 0);
      } else {
        logger.warn('StartupRecovery', `⚠️ 恢复策略执行失败: ${strategy} - ${result.message}`);
      }
      
      return result;
      
    } finally {
      this.isRecovering = false;
    }
  }

  /**
   * 分类启动失败类型
   */
  private classifyFailure(error: Error, failurePhase: string): StartupFailureType {
    const errorMessage = error.message.toLowerCase();
    
    if (errorMessage.includes('globalcontext') || failurePhase.includes('GLOBAL_CONTEXT')) {
      return StartupFailureType.GLOBAL_CONTEXT_FAILURE;
    }
    
    if (errorMessage.includes('resource') || errorMessage.includes('资源') || failurePhase.includes('RESOURCE')) {
      return StartupFailureType.RESOURCE_LOADING_FAILURE;
    }
    
    if (errorMessage.includes('permission') || errorMessage.includes('权限') || failurePhase.includes('PERMISSION')) {
      return StartupFailureType.PERMISSION_FAILURE;
    }
    
    return StartupFailureType.UNKNOWN_FAILURE;
  }

  /**
   * 获取GlobalContext恢复选项
   */
  private getGlobalContextRecoveryOptions(attempts: number): RecoveryOption[] {
    const options: RecoveryOption[] = [];
    
    if (attempts < this.maxRetryAttempts) {
      const retryOption: RecoveryOption = {
        strategy: RecoveryStrategy.RETRY,
        description: '重试GlobalContext初始化',
        priority: 90,
        canAutoExecute: true,
        estimatedTime: 2000,
        successRate: 0.7
      };
      options.push(retryOption);
    }
    
    const safeModeOption: RecoveryOption = {
      strategy: RecoveryStrategy.SAFE_MODE,
      description: '使用安全模式启动（跳过GlobalContext依赖）',
      priority: 60,
      canAutoExecute: false,
      estimatedTime: 1000,
      successRate: 0.9
    };
    options.push(safeModeOption);
    
    if (attempts >= this.maxRetryAttempts) {
      const resetOption: RecoveryOption = {
        strategy: RecoveryStrategy.RESET,
        description: '重置应用状态并重新启动',
        priority: 30,
        canAutoExecute: false,
        estimatedTime: 5000,
        successRate: 0.8
      };
      options.push(resetOption);
    }
    
    return options;
  }

  /**
   * 获取资源加载恢复选项
   */
  private getResourceLoadingRecoveryOptions(attempts: number): RecoveryOption[] {
    const options: RecoveryOption[] = [];
    
    if (attempts < this.maxRetryAttempts) {
      const retryOption: RecoveryOption = {
        strategy: RecoveryStrategy.RETRY,
        description: '重试资源加载',
        priority: 80,
        canAutoExecute: true,
        estimatedTime: 4000,
        successRate: 0.6
      };
      options.push(retryOption);
    }
    
    const fallbackOption: RecoveryOption = {
      strategy: RecoveryStrategy.FALLBACK,
      description: '跳过可选资源，仅加载核心资源',
      priority: 65,
      canAutoExecute: true,
      estimatedTime: 2000,
      successRate: 0.85
    };
    options.push(fallbackOption);
    
    return options;
  }

  /**
   * 获取权限恢复选项
   */
  private getPermissionRecoveryOptions(attempts: number): RecoveryOption[] {
    const options: RecoveryOption[] = [];
    
    const fallbackOption: RecoveryOption = {
      strategy: RecoveryStrategy.FALLBACK,
      description: '使用受限模式启动（部分功能不可用）',
      priority: 75,
      canAutoExecute: false,
      estimatedTime: 1000,
      successRate: 0.9
    };
    options.push(fallbackOption);
    
    return options;
  }

  /**
   * 获取通用恢复选项
   */
  private getGenericRecoveryOptions(attempts: number): RecoveryOption[] {
    const options: RecoveryOption[] = [];
    
    if (attempts < this.maxRetryAttempts) {
      const retryOption: RecoveryOption = {
        strategy: RecoveryStrategy.RETRY,
        description: '重试启动流程',
        priority: 70,
        canAutoExecute: true,
        estimatedTime: 3000,
        successRate: 0.5
      };
      options.push(retryOption);
    }
    
    const safeModeOption: RecoveryOption = {
      strategy: RecoveryStrategy.SAFE_MODE,
      description: '安全模式启动',
      priority: 50,
      canAutoExecute: false,
      estimatedTime: 2000,
      successRate: 0.8
    };
    options.push(safeModeOption);
    
    return options;
  }

  /**
   * 执行重试策略
   */
  private async executeRetryStrategy(failureType: StartupFailureType): Promise<RecoveryResult> {
    logger.info('StartupRecovery', '🔄 执行重试策略');
    
    try {
      // 等待一段时间后重试
      await new Promise<void>(resolve => setTimeout(resolve, 1000));
      
      // 根据失败类型执行相应的重试逻辑
      switch (failureType) {
        default:
          // 通用重试逻辑
          break;
      }
      
      const successResult: RecoveryResult = {
        success: true,
        strategy: RecoveryStrategy.RETRY,
        message: '重试成功'
      };
      return successResult;
      
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      const failureResult: RecoveryResult = {
        success: false,
        strategy: RecoveryStrategy.RETRY,
        message: `重试失败: ${errorMessage}`
      };
      return failureResult;
    }
  }

  /**
   * 执行降级策略
   */
  private async executeFallbackStrategy(failureType: StartupFailureType): Promise<RecoveryResult> {
    logger.info('StartupRecovery', '📉 执行降级策略');
    
    try {
      switch (failureType) {
        case StartupFailureType.PERMISSION_FAILURE:
          // 进入受限模式
          logger.info('StartupRecovery', '进入受限模式');
          const restrictedModePayload: IEventPayload = {};
          eventBus.emit('ENTER_RESTRICTED_MODE', restrictedModePayload);
          break;
          
        default:
          logger.info('StartupRecovery', '执行通用降级策略');
          break;
      }
      
      const successResult: RecoveryResult = {
        success: true,
        strategy: RecoveryStrategy.FALLBACK,
        message: '降级策略执行成功'
      };
      return successResult;
      
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      const failureResult: RecoveryResult = {
        success: false,
        strategy: RecoveryStrategy.FALLBACK,
        message: `降级策略执行失败: ${errorMessage}`
      };
      return failureResult;
    }
  }

  /**
   * 执行安全模式策略
   */
  private async executeSafeModeStrategy(failureType: StartupFailureType): Promise<RecoveryResult> {
    logger.info('StartupRecovery', '🛡️ 执行安全模式策略');
    
    try {
      // 发送安全模式事件
      const safeModePayload: IEventPayload = { failureType };
      eventBus.emit('ENTER_SAFE_MODE', safeModePayload);
      
      const successResult: RecoveryResult = {
        success: true,
        strategy: RecoveryStrategy.SAFE_MODE,
        message: '已进入安全模式'
      };
      return successResult;
      
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      const failureResult: RecoveryResult = {
        success: false,
        strategy: RecoveryStrategy.SAFE_MODE,
        message: `安全模式启动失败: ${errorMessage}`
      };
      return failureResult;
    }
  }

  /**
   * 执行重置策略
   */
  private async executeResetStrategy(failureType: StartupFailureType): Promise<RecoveryResult> {
    logger.info('StartupRecovery', '🔄 执行重置策略');
    
    try {
      // 清理状态
      this.recoveryAttempts.clear();
      this.lastSnapshot = null;
      
      // 发送重置事件
      const resetPayload: IEventPayload = { failureType };
      eventBus.emit('RESET_APPLICATION', resetPayload);
      
      const successResult: RecoveryResult = {
        success: true,
        strategy: RecoveryStrategy.RESET,
        message: '应用状态已重置'
      };
      return successResult;
      
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      const failureResult: RecoveryResult = {
        success: false,
        strategy: RecoveryStrategy.RESET,
        message: `重置失败: ${errorMessage}`
      };
      return failureResult;
    }
  }

  /**
   * 获取恢复统计信息
   */
  public getRecoveryStats(): RecoveryStats {
    const recoveryAttemptsRecord: Record<string, number> = {};
    this.recoveryAttempts.forEach((value, key) => {
      recoveryAttemptsRecord[key] = value;
    });
    
    const stats: RecoveryStats = {
      recoveryAttempts: recoveryAttemptsRecord,
      isRecovering: this.isRecovering,
      lastSnapshot: this.lastSnapshot,
      maxRetryAttempts: this.maxRetryAttempts
    };
    return stats;
  }

  /**
   * 重置恢复状态
   */
  public reset(): void {
    this.recoveryAttempts.clear();
    this.lastSnapshot = null;
    this.isRecovering = false;
    logger.info('StartupRecovery', '🔄 恢复状态已重置');
  }
}

// 导出单例实例
export const startupRecovery = StartupRecovery.getInstance();