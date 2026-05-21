// 文件路径: src/main/ets/Framework/Diagnostics/StartupDiagnostics.ets
/**
 * 启动诊断工具
 * 用于在应用启动阶段进行诊断和监控，提供性能分析、健康检查和问题定位功能。
 */

import { logger } from '../../Utils/Logger';
import { isInitialized as isGlobalContextInitialized } from '../../GlobalContext';

/**
 * 启动阶段枚举
 */
export enum StartupPhase {
  ABILITY_STAGE_CREATE = 'ABILITY_STAGE_CREATE',
  ENTRY_ABILITY_CREATE = 'ENTRY_ABILITY_CREATE',
  GLOBAL_CONTEXT_INIT = 'GLOBAL_CONTEXT_INIT',
  WINDOW_STAGE_CREATE = 'WINDOW_STAGE_CREATE',
  PERMISSION_REQUEST = 'PERMISSION_REQUEST',
  LOADING_PAGE_START = 'LOADING_PAGE_START',
  STARTUP_HEALTH_CHECK = 'STARTUP_HEALTH_CHECK',
  RESOURCE_MANAGER_INIT = 'RESOURCE_MANAGER_INIT',
  RESOURCE_LOADING = 'RESOURCE_LOADING',
  CORE_SYSTEMS_INIT = 'CORE_SYSTEMS_INIT',
  SYSTEM_REGISTRATION = 'SYSTEM_REGISTRATION',
  POST_STARTUP_HEALTH_CHECK = 'POST_STARTUP_HEALTH_CHECK',
  MAIN_MENU_READY = 'MAIN_MENU_READY'
}

/**
 * 阶段详细信息接口
 */
interface PhaseDetails extends Record<string, string | number | boolean | undefined> {
  memoryUsage?: number;
  resourceCount?: number;
  errorCode?: string;
  retryCount?: number;
}

/**
 * 启动阶段信息接口
 */
interface StartupPhaseInfo {
  phase: StartupPhase;
  startTime: number;
  endTime?: number;
  duration?: number;
  success?: boolean;
  errorMessage?: string;
  details?: PhaseDetails;
}

/**
 * 全局上下文状态接口
 */
interface GlobalContextStatus extends Record<string, string | number | boolean | undefined> {
  isInitialized: boolean;
  initTime?: number;
  version?: string;
}

/**
 * 内存使用状态接口
 */
interface MemoryUsageStatus extends Record<string, number | undefined> {
  totalMemory?: number;
  usedMemory?: number;
  freeMemory?: number;
  heapSize?: number;
}

/**
 * 系统健康状态接口
 */
interface SystemHealthStatus {
  globalContextInitialized: boolean;
  globalContextStatus: GlobalContextStatus;
  memoryUsage?: MemoryUsageStatus;
  timestamp: number;
}

/**
 * 启动诊断报告接口
 */
interface StartupDiagnosticsReport {
  totalStartupTime: number;
  phases: StartupPhaseInfo[];
  systemHealth: SystemHealthStatus;
  issues: string[];
  recommendations: string[];
  timestamp: number;
}

/**
 * 启动流程诊断和监控工具
 */
interface MonitoringStatus {
  isMonitoring: boolean;
  startTime: number;
  phases: StartupPhaseInfo[];
}

export class StartupDiagnostics {
  private static instance: StartupDiagnostics;
  private phases: Map<StartupPhase, StartupPhaseInfo> = new Map();
  private startupStartTime: number = 0;
  private isMonitoring: boolean = false;

  private constructor() {
    // 私有构造函数，确保单例模式
  }

  public static getInstance(): StartupDiagnostics {
    if (!StartupDiagnostics.instance) {
      StartupDiagnostics.instance = new StartupDiagnostics();
    }
    return StartupDiagnostics.instance;
  }

  /**
   * 开始监控启动流程
   */
  public startMonitoring(): void {
    if (this.isMonitoring) {
      logger.warn('StartupDiagnostics', '⚠️ 启动监控已在进行中');
      return;
    }

    this.isMonitoring = true;
    this.startupStartTime = Date.now();
    this.phases.clear();
    
    logger.startup('StartupDiagnostics', '开始监控应用启动流程');
    logger.performance('StartupDiagnostics', 'startup_monitoring_start', this.startupStartTime, 'timestamp');
  }

  /**
   * 记录启动阶段开始
   */
  public recordPhaseStart(phase: StartupPhase, details?: PhaseDetails): void {
    if (!this.isMonitoring) {
      logger.warn('StartupDiagnostics', '⚠️ 启动监控未开启，无法记录阶段信息');
      return;
    }

    const phaseInfo: StartupPhaseInfo = {
      phase,
      startTime: Date.now(),
      success: false,
      details
    };

    this.phases.set(phase, phaseInfo);
    logger.info('StartupDiagnostics', `📍 启动阶段开始: ${phase}`);
    
    if (details) {
      logger.debug('StartupDiagnostics', `📋 阶段详情: ${JSON.stringify(details)}`);
    }
  }

  /**
   * 记录启动阶段完成
   */
  public recordPhaseEnd(phase: StartupPhase, success: boolean = true, errorMessage?: string): void {
    if (!this.isMonitoring) {
      return;
    }

    const phaseInfo = this.phases.get(phase);
    if (!phaseInfo) {
      logger.warn('StartupDiagnostics', `⚠️ 未找到启动阶段信息: ${phase}`);
      return;
    }

    const endTime = Date.now();
    phaseInfo.endTime = endTime;
    phaseInfo.duration = endTime - phaseInfo.startTime;
    phaseInfo.success = success;
    phaseInfo.errorMessage = errorMessage;

    const statusIcon = success ? '✅' : '❌';
    logger.info('StartupDiagnostics', `${statusIcon} 启动阶段完成: ${phase}，耗时: ${phaseInfo.duration}ms`);
    
    if (!success && errorMessage) {
      logger.error('StartupDiagnostics', `❌ 阶段失败原因: ${errorMessage}`);
    }

    logger.performance('StartupDiagnostics', `phase_${phase.toLowerCase()}_duration`, phaseInfo.duration, 'ms');
  }

  /**
   * 完成启动监控
   */
  public completeStartupMonitoring(): void {
    if (!this.isMonitoring) {
      logger.warn('StartupDiagnostics', '⚠️ 启动监控未开启');
      return;
    }

    this.isMonitoring = false;
    const totalTime = Date.now() - this.startupStartTime;
    
    logger.startup('StartupDiagnostics', '启动流程监控完成', `总耗时: ${totalTime}ms`);
    logger.performance('StartupDiagnostics', 'total_startup_time', totalTime, 'ms');

    // 生成诊断报告
    const report = this.generateDiagnosticsReport();
    this.logDiagnosticsReport(report);
  }

  /**
   * 获取系统健康状态
   */
  private getSystemHealthStatus(): SystemHealthStatus {
    return {
      globalContextInitialized: isGlobalContextInitialized(),
      globalContextStatus: { isInitialized: isGlobalContextInitialized() },
      timestamp: Date.now()
    };
  }

  /**
   * 生成诊断报告
   */
  private generateDiagnosticsReport(): StartupDiagnosticsReport {
    const phases = Array.from(this.phases.values());
    const totalStartupTime = Date.now() - this.startupStartTime;
    const systemHealth = this.getSystemHealthStatus();
    const issues: string[] = [];
    const recommendations: string[] = [];

    // 分析启动阶段问题
    phases.forEach(phase => {
      if (!phase.success) {
        issues.push(`${phase.phase} 阶段失败: ${phase.errorMessage || '未知错误'}`);
      }
      
      if (phase.duration && phase.duration > 5000) {
        issues.push(`${phase.phase} 阶段耗时过长: ${phase.duration}ms`);
        recommendations.push(`优化 ${phase.phase} 阶段的性能`);
      }
    });

    // 分析系统健康状态
    if (!systemHealth.globalContextInitialized) {
      issues.push('GlobalContext未正确初始化');
      recommendations.push('检查EntryAbility.onCreate中的setContext调用');
    }

    // 分析总启动时间
    if (totalStartupTime > 10000) {
      issues.push(`总启动时间过长: ${totalStartupTime}ms`);
      recommendations.push('优化启动流程，减少不必要的同步操作');
    }

    return {
      totalStartupTime,
      phases,
      systemHealth,
      issues,
      recommendations,
      timestamp: Date.now()
    };
  }

  /**
   * 输出诊断报告
   */
  private logDiagnosticsReport(report: StartupDiagnosticsReport): void {
    // 构建完整的诊断报告
    const reportLines: string[] = [];
    reportLines.push('📊 ========== 启动诊断报告 ==========');
    reportLines.push(`⏱️ 总启动时间: ${report.totalStartupTime}ms`);
    
    // 添加各阶段信息
    if (report.phases.length > 0) {
      reportLines.push('📋 启动阶段详情:');
      report.phases.forEach(phase => {
        const statusIcon = phase.success ? '✅' : '❌';
        const duration = phase.duration ? `${phase.duration}ms` : '未完成';
        reportLines.push(`  ${statusIcon} ${phase.phase}: ${duration}`);
      });
    }

    // 添加系统健康状态
    reportLines.push('🏥 系统健康状态:');
    reportLines.push(`  GlobalContext初始化: ${report.systemHealth.globalContextInitialized ? '✅' : '❌'}`);
    
    // 添加问题和建议
    if (report.issues.length > 0) {
      reportLines.push('⚠️ 发现的问题:');
      report.issues.forEach(issue => {
        reportLines.push(`  • ${issue}`);
      });
    }

    if (report.recommendations.length > 0) {
      reportLines.push('💡 优化建议:');
      report.recommendations.forEach(recommendation => {
        reportLines.push(`  • ${recommendation}`);
      });
    }

    reportLines.push('📊 ========== 报告结束 ==========');

    if (report.issues.length > 0) {
      logger.warn('StartupDiagnostics', reportLines.join('\n'));
    } else {
      logger.info('StartupDiagnostics', reportLines.join('\n'));
    }
  }

  /**
   * 获取当前监控状态
   */
  public getMonitoringStatus(): MonitoringStatus {
    return {
      isMonitoring: this.isMonitoring,
      startTime: this.startupStartTime,
      phases: Array.from(this.phases.values())
    };
  }

  /**
   * 重置监控状态
   */
  public reset(): void {
    this.isMonitoring = false;
    this.phases.clear();
    this.startupStartTime = 0;
    logger.info('StartupDiagnostics', '🔄 启动诊断状态已重置');
  }
}

// 导出单例实例
export const startupDiagnostics = StartupDiagnostics.getInstance();
