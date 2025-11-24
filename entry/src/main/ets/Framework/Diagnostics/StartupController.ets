// 文件路径: src/main/ets/Framework/Diagnostics/StartupController.ets
/**
 * 启动流程总控制器
 * 整合诊断、健康检查和恢复功能，提供统一的启动流程管理
 */

import { logger } from '../../Utils/Logger';
import { startupDiagnostics, StartupPhase } from './StartupDiagnostics';
import { startupRecovery, RecoveryStrategy, StartupFailureType } from './StartupRecovery';

/**
 * 启动阶段配置
 */
interface StartupPhaseConfig {
  phase: StartupPhase;
  name: string;
  description: string;
  timeout: number; // 超时时间（毫秒）
  retryable: boolean; // 是否可重试
  critical: boolean; // 是否为关键阶段
  recoveryStrategies: RecoveryStrategy[]; // 可用的恢复策略
}

/**
 * 启动执行结果
 */
interface StartupExecutionResult {
  success: boolean;
  phase: StartupPhase;
  duration: number;
  error?: string;
  recoveryAttempted?: boolean;
  recoverySuccess?: boolean;
}

/**
 * 启动流程状态
 */
enum StartupStatus {
  NOT_STARTED = 'NOT_STARTED',
  RUNNING = 'RUNNING',
  COMPLETED = 'COMPLETED',
  FAILED = 'FAILED',
  RECOVERING = 'RECOVERING'
}

/**
 * 启动流程总控制器
 */
interface RecoveryResult {
  success: boolean;
  message: string;
}

class StartupController {
  private static instance: StartupController;
  private status: StartupStatus = StartupStatus.NOT_STARTED;
  private currentPhase: StartupPhase | null = null;
  private startTime: number = 0;
  private phaseConfigs: Map<StartupPhase, StartupPhaseConfig> = new Map();
  private executionResults: StartupExecutionResult[] = [];
  private recoveryAttempts: number = 0;
  private readonly MAX_RECOVERY_ATTEMPTS = 3;

  private constructor() {
    this.initializePhaseConfigs();
  }

  static getInstance(): StartupController {
    if (!StartupController.instance) {
      StartupController.instance = new StartupController();
    }
    return StartupController.instance;
  }

  /**
   * 初始化阶段配置
   */
  private initializePhaseConfigs(): void {
    const configs: StartupPhaseConfig[] = [
      {
        phase: StartupPhase.ABILITY_STAGE_CREATE,
        name: 'AbilityStage创建',
        description: '应用生命周期初始化',
        timeout: 5000,
        retryable: false,
        critical: true,
        recoveryStrategies: [RecoveryStrategy.RESET]
      },
      {
        phase: StartupPhase.ENTRY_ABILITY_CREATE,
        name: 'EntryAbility创建',
        description: '主能力组件初始化',
        timeout: 5000,
        retryable: false,
        critical: true,
        recoveryStrategies: [RecoveryStrategy.RESET]
      },
      {
        phase: StartupPhase.GLOBAL_CONTEXT_INIT,
        name: 'GlobalContext初始化',
        description: '全局上下文设置',
        timeout: 10000,
        retryable: true,
        critical: true,
        recoveryStrategies: [RecoveryStrategy.RETRY, RecoveryStrategy.RESET]
      },
      {
        phase: StartupPhase.WINDOW_STAGE_CREATE,
        name: '窗口阶段创建',
        description: '应用窗口初始化',
        timeout: 8000,
        retryable: true,
        critical: true,
        recoveryStrategies: [RecoveryStrategy.RETRY, RecoveryStrategy.SAFE_MODE]
      },
      {
        phase: StartupPhase.PERMISSION_REQUEST,
        name: '权限请求',
        description: '应用权限获取',
        timeout: 15000,
        retryable: true,
        critical: false,
        recoveryStrategies: [RecoveryStrategy.RETRY, RecoveryStrategy.FALLBACK]
      },
      {
        phase: StartupPhase.LOADING_PAGE_START,
        name: '加载页面启动',
        description: '加载界面初始化',
        timeout: 5000,
        retryable: true,
        critical: true,
        recoveryStrategies: [RecoveryStrategy.RETRY, RecoveryStrategy.SAFE_MODE]
      },
      {
        phase: StartupPhase.STARTUP_HEALTH_CHECK,
        name: '启动前健康检查',
        description: '系统状态预检',
        timeout: 8000,
        retryable: true,
        critical: false,
        recoveryStrategies: [RecoveryStrategy.RETRY, RecoveryStrategy.FALLBACK]
      },
      {
        phase: StartupPhase.RESOURCE_MANAGER_INIT,
        name: '资源管理器初始化',
        description: '资源管理系统启动',
        timeout: 15000,
        retryable: true,
        critical: true,
        recoveryStrategies: [RecoveryStrategy.RETRY, RecoveryStrategy.FALLBACK, RecoveryStrategy.SAFE_MODE]
      },
      {
        phase: StartupPhase.RESOURCE_LOADING,
        name: '游戏资源加载',
        description: '游戏资源文件加载',
        timeout: 20000,
        retryable: true,
        critical: false,
        recoveryStrategies: [RecoveryStrategy.RETRY, RecoveryStrategy.FALLBACK]
      },
      {
        phase: StartupPhase.CORE_SYSTEMS_INIT,
        name: '核心系统初始化',
        description: '游戏核心系统初始化',
        timeout: 15000,
        retryable: true,
        critical: true,
        recoveryStrategies: [RecoveryStrategy.RETRY, RecoveryStrategy.SAFE_MODE, RecoveryStrategy.FALLBACK]
      },
      {
        phase: StartupPhase.SYSTEM_REGISTRATION,
        name: '核心系统注册',
        description: '游戏核心系统注册',
        timeout: 15000,
        retryable: true,
        critical: true,
        recoveryStrategies: [RecoveryStrategy.RETRY, RecoveryStrategy.SAFE_MODE, RecoveryStrategy.FALLBACK]
      },
      {
        phase: StartupPhase.POST_STARTUP_HEALTH_CHECK,
        name: '启动后健康检查',
        description: '系统状态后检',
        timeout: 8000,
        retryable: true,
        critical: false,
        recoveryStrategies: [RecoveryStrategy.RETRY, RecoveryStrategy.FALLBACK]
      },
      {
        phase: StartupPhase.MAIN_MENU_READY,
        name: '主菜单就绪',
        description: '主界面准备完成',
        timeout: 5000,
        retryable: true,
        critical: true,
        recoveryStrategies: [RecoveryStrategy.RETRY, RecoveryStrategy.SAFE_MODE]
      }
    ];

    configs.forEach(config => {
      this.phaseConfigs.set(config.phase, config);
    });
  }

  /**
   * 开始启动流程监控
   */
  startMonitoring(): void {
    if (this.status !== StartupStatus.NOT_STARTED) {
      logger.warn('StartupController', '⚠️ 启动监控已经开始，忽略重复调用');
      return;
    }

    this.status = StartupStatus.RUNNING;
    this.startTime = Date.now();
    this.executionResults = [];
    this.recoveryAttempts = 0;

    logger.warn('StartupController', '🚀 启动流程监控开始');
    startupDiagnostics.startMonitoring();
  }

  /**
   * 执行启动阶段
   */
  async executePhase<T>(phase: StartupPhase, executor: () => Promise<T>): Promise<T> {
    const config = this.phaseConfigs.get(phase);
    if (!config) {
      throw new Error(`未知的启动阶段: ${phase}`);
    }

    this.currentPhase = phase;
    const phaseStartTime = Date.now();

    logger.info('StartupController', `📋 开始执行阶段: ${config.name}`);
    startupDiagnostics.recordPhaseStart(phase);

    try {
      // 设置超时
      const timeoutPromise = new Promise<never>((_, reject) => {
        setTimeout(() => {
          reject(new Error(`阶段执行超时: ${config.name} (${config.timeout}ms)`));
        }, config.timeout);
      });

      // 执行阶段任务
      const result = await Promise.race([executor(), timeoutPromise]);
      
      const duration = Date.now() - phaseStartTime;
      logger.info('StartupController', `✅ 阶段执行成功: ${config.name} (${duration}ms)`);
      
      startupDiagnostics.recordPhaseEnd(phase, true);
      this.recordExecutionResult({
        success: true,
        phase,
        duration
      });

      return result;

    } catch (error) {
      const duration = Date.now() - phaseStartTime;
      const errorMessage = error instanceof Error ? error.message : String(error);
      
      logger.error('StartupController', `❌ 阶段执行失败: ${config.name} - ${errorMessage}`);
      startupDiagnostics.recordPhaseEnd(phase, false, errorMessage);

      // 尝试恢复
      if (config.retryable && this.recoveryAttempts < this.MAX_RECOVERY_ATTEMPTS) {
        const recoveryResult = await this.attemptRecovery(phase, error as Error, config);
        
        this.recordExecutionResult({
          success: false,
          phase,
          duration,
          error: errorMessage,
          recoveryAttempted: true,
          recoverySuccess: recoveryResult.success
        });

        if (recoveryResult.success) {
          // 恢复成功，重新执行
          return this.executePhase(phase, executor);
        }
      } else {
        this.recordExecutionResult({
          success: false,
          phase,
          duration,
          error: errorMessage,
          recoveryAttempted: false
        });
      }

      // 如果是关键阶段失败，标记整个启动失败
      if (config.critical) {
        this.status = StartupStatus.FAILED;
        logger.error('StartupController', `💥 关键阶段失败，启动流程终止: ${config.name}`);
      }

      throw new Error(errorMessage);
    }
  }

  /**
   * 尝试恢复
   */
  private async attemptRecovery(phase: StartupPhase, error: Error, config: StartupPhaseConfig): Promise<RecoveryResult> {
    this.status = StartupStatus.RECOVERING;
    this.recoveryAttempts++;

    logger.info('StartupController', `🔧 尝试恢复阶段: ${config.name} (第${this.recoveryAttempts}次尝试)`);

    // 分类失败类型
    const failureType = this.classifyFailureType(error, phase);

    // 尝试每个可用的恢复策略
    for (const strategy of config.recoveryStrategies) {
      try {
        logger.info('StartupController', `🛠️ 尝试恢复策略: ${strategy}`);
        const result = await startupRecovery.executeRecovery(strategy, failureType);
        
        if (result.success) {
          logger.info('StartupController', `✅ 恢复成功: ${strategy} - ${result.message}`);
          this.status = StartupStatus.RUNNING;
          return { success: true, message: result.message };
        } else {
          logger.warn('StartupController', `⚠️ 恢复策略失败: ${strategy} - ${result.message}`);
        }
      } catch (recoveryError) {
        logger.error('StartupController', `❌ 恢复策略异常: ${strategy} - ${recoveryError instanceof Error ? recoveryError.message : String(recoveryError)}`);
      }
    }

    this.status = StartupStatus.RUNNING;
    return { success: false, message: '所有恢复策略都失败了' };
  }

  /**
   * 分类失败类型
   */
  private classifyFailureType(error: Error, phase: StartupPhase): StartupFailureType {
    const errorMessage = error.message.toLowerCase();
    
    if (phase === StartupPhase.GLOBAL_CONTEXT_INIT || errorMessage.includes('globalcontext')) {
      return StartupFailureType.GLOBAL_CONTEXT_FAILURE;
    }
    
    if (phase === StartupPhase.RESOURCE_LOADING || errorMessage.includes('resource') || errorMessage.includes('资源')) {
      return StartupFailureType.RESOURCE_LOADING_FAILURE;
    }
    
    if (phase === StartupPhase.PERMISSION_REQUEST || errorMessage.includes('permission') || errorMessage.includes('权限')) {
      return StartupFailureType.PERMISSION_FAILURE;
    }
    
    if (errorMessage.includes('memory') || errorMessage.includes('内存') || errorMessage.includes('timeout') || errorMessage.includes('超时')) {
      return StartupFailureType.SYSTEM_RESOURCE_FAILURE;
    }
    
    return StartupFailureType.UNKNOWN_FAILURE;
  }

  /**
   * 记录执行结果
   */
  private recordExecutionResult(result: StartupExecutionResult): void {
    this.executionResults.push(result);
  }

  /**
   * 完成启动流程
   */
  completeStartup(): void {
    if (this.status === StartupStatus.RUNNING) {
      this.status = StartupStatus.COMPLETED;
      const totalDuration = Date.now() - this.startTime;
      
      logger.warn('StartupController', `🎉 启动流程完成报告 (总耗时: ${totalDuration}ms)`);
      startupDiagnostics.completeStartupMonitoring();
      
      // 生成启动报告
      this.generateStartupReport();
    }
  }

  /**
   * 生成启动报告
   */
  private generateStartupReport(): void {
    const totalDuration = Date.now() - this.startTime;
    const successfulPhases = this.executionResults.filter(r => r.success).length;
    const failedPhases = this.executionResults.filter(r => !r.success).length;
    const recoveryAttempts = this.executionResults.filter(r => r.recoveryAttempted).length;
    const successfulRecoveries = this.executionResults.filter(r => r.recoveryAttempted && r.recoverySuccess).length;

    // 构建完整的报告内容
    const reportLines: string[] = [];
    reportLines.push('📊 ========== 启动流程报告 ==========');
    reportLines.push(`⏱️ 总耗时: ${totalDuration}ms`);
    reportLines.push(`📈 统计信息: 成功${successfulPhases}个, 失败${failedPhases}个, 恢复尝试${recoveryAttempts}次, 恢复成功${successfulRecoveries}次`);
    reportLines.push(`🎯 最终状态: ${this.status}`);
    
    // 添加详细的阶段信息
    if (this.executionResults.length > 0) {
      reportLines.push('📋 阶段执行详情:');
      this.executionResults.forEach(result => {
        const config = this.phaseConfigs.get(result.phase);
        const status = result.success ? '✅' : '❌';
        const recovery = result.recoveryAttempted ? (result.recoverySuccess ? ' (恢复成功)' : ' (恢复失败)') : '';
        
        reportLines.push(`   ${status} ${config?.name}: ${result.duration}ms${recovery}`);
        if (result.error) {
          reportLines.push(`      ❌ 错误: ${result.error}`);
        }
      });
    }
    
    reportLines.push('📊 ========== 报告结束 ==========');

    // 使用warn级别输出完整报告
    logger.warn('StartupController', reportLines.join('\n'));
  }

  /**
   * 获取当前状态
   */
  getStatus(): StartupStatus {
    return this.status;
  }

  /**
   * 获取当前阶段
   */
  getCurrentPhase(): StartupPhase | null {
    return this.currentPhase;
  }

  /**
   * 获取执行结果
   */
  getExecutionResults(): StartupExecutionResult[] {
    return [...this.executionResults];
  }

  /**
   * 重置控制器状态
   */
  reset(): void {
    this.status = StartupStatus.NOT_STARTED;
    this.currentPhase = null;
    this.startTime = 0;
    this.executionResults = [];
    this.recoveryAttempts = 0;
    
    logger.info('StartupController', '🔄 启动控制器已重置');
  }
}

// 导出单例实例
export const startupController = StartupController.getInstance();

export { StartupStatus, StartupExecutionResult, StartupPhaseConfig, StartupPhase };