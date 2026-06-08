// 文件路径: src/main/ets/Framework/Loading/LoadingStateManager.ets
/**
 * 加载状态管理器
 * 负责管理应用启动和初始化过程中的加载状态，与C++生命周期状态同步
 */

import { logger } from '../../Utils/Logger';
// 移除对Game目录的依赖，使用简单的事件系统
export interface EventPayload {
  timestamp: number;
  source: string;
}

export enum GameEvent {
  LOADING_STATE_CHANGED = 'LOADING_STATE_CHANGED',
  LOADING_PROGRESS_UPDATED = 'LOADING_PROGRESS_UPDATED'
}

export class EventBus {
  private static instance: EventBus;
  private listeners: Map<string, Function[]> = new Map();

  static getInstance(): EventBus {
    if (!EventBus.instance) {
      EventBus.instance = new EventBus();
    }
    return EventBus.instance;
  }

  subscribe(event: string, callback: Function): void {
    if (!this.listeners.has(event)) {
      this.listeners.set(event, []);
    }
    this.listeners.get(event)?.push(callback);
  }

  publish(event: string, payload: EventPayload): void {
    const callbacks = this.listeners.get(event);
    if (callbacks) {
      callbacks.forEach(callback => callback(payload));
    }
  }
}
import {
  LoadingPhase,
  LoadingState,
  ErrorSeverity,
  RecoveryStrategy,
  LoadingProgress,
  ErrorDetails,
  PerformanceMetrics,
  PhaseDetails,
  LoadingStateSnapshot,
  LoadingStateChangeEvent,
  RecoveryResult,
  LoadingConfiguration,
  LoadingStatistics,
  PropertyValue
} from './LoadingStateTypes';

/**
 * 加载状态变更事件载荷
 */
export class LoadingStateChangeEventPayload extends EventPayload {
  /** 状态变更事件 */
  event: LoadingStateChangeEvent;
  
  constructor(event: LoadingStateChangeEvent) {
    super();
    this.event = event;
  }
}

/**
 * 加载状态管理器
 */
export class LoadingStateManager {
  private static instance: LoadingStateManager;
  
  /** 当前阶段 */
  private currentPhase: LoadingPhase = LoadingPhase.UNINITIALIZED;
  
  /** 阶段详情映射 */
  private phases: Map<LoadingPhase, PhaseDetails> = new Map();
  
  /** 全局错误列表 */
  private globalErrors: ErrorDetails[] = [];
  
  /** 配置 */
  private config: LoadingConfiguration;
  
  /** 统计信息 */
  private statistics: LoadingStatistics;
  
  /** 性能监控定时器 */
  private performanceTimer: number | null = null;
  
  /** 状态变更监听器 */
  private stateChangeListeners: Array<(event: LoadingStateChangeEvent) => void> = [];
  
  private constructor() {
    this.config = this.getDefaultConfiguration();
    this.statistics = this.initializeStatistics();
    this.initializePhases();
    this.startPerformanceMonitoring();
    
    logger.lifecycle('LoadingStateManager', '加载状态管理器初始化完成');
  }
  
  public static getInstance(): LoadingStateManager {
    if (!LoadingStateManager.instance) {
      LoadingStateManager.instance = new LoadingStateManager();
    }
    return LoadingStateManager.instance;
  }
  
  /**
   * 获取默认配置
   */
  private getDefaultConfiguration(): LoadingConfiguration {
    return {
      enableVerboseLogging: true,
      enablePerformanceMonitoring: true,
      autoRetryConfig: {
        enabled: true,
        defaultMaxRetries: 3,
        retryDelay: 1000,
        backoffFactor: 2.0
      },
      timeoutConfig: {
        phaseTimeout: 30000, // 30秒
        overallTimeout: 120000 // 2分钟
      },
      performanceThresholds: {
        memoryWarning: 200 * 1024 * 1024, // 200MB
        cpuWarning: 80, // 80%
        minFpsThreshold: 30 // 30fps
      }
    };
  }
  
  /**
   * 初始化统计信息
   */
  private initializeStatistics(): LoadingStatistics {
    return {
      totalLoadingTime: 0,
      successfulPhases: 0,
      failedPhases: 0,
      skippedPhases: 0,
      totalRetries: 0,
      averagePhaseTime: 0,
      errorStatistics: {
        totalErrors: 0,
        errorsByPhase: new Map(),
        errorsBySeverity: new Map()
      },
      performanceStatistics: {
        peakMemoryUsage: 0,
        averageCpuUsage: 0,
        minFps: 60,
        maxRenderTime: 0
      }
    };
  }
  
  /**
   * 初始化所有阶段
   */
  private initializePhases(): void {
    const phaseConfigs: Array<{
      phase: LoadingPhase;
      description: string;
      expectedDuration: number;
      maxRetries: number;
      skippable: boolean;
      dependencies?: LoadingPhase[];
    }> = [
      {
        phase: LoadingPhase.UNINITIALIZED,
        description: '系统未初始化',
        expectedDuration: 0,
        maxRetries: 0,
        skippable: false
      },
      {
        phase: LoadingPhase.PRE_INIT_CHECK,
        description: '预初始化检查',
        expectedDuration: 500,
        maxRetries: 2,
        skippable: false
      },
      {
        phase: LoadingPhase.GLOBAL_CONTEXT_INIT,
        description: '全局上下文初始化',
        expectedDuration: 1000,
        maxRetries: 3,
        skippable: false,
        dependencies: [LoadingPhase.PRE_INIT_CHECK]
      },
      {
        phase: LoadingPhase.RESOURCE_MANAGER_INIT,
        description: '资源管理器初始化',
        expectedDuration: 1500,
        maxRetries: 3,
        skippable: false,
        dependencies: [LoadingPhase.GLOBAL_CONTEXT_INIT]
      },
      {
        phase: LoadingPhase.SURFACE_CREATION,
        description: 'Surface创建',
        expectedDuration: 1000,
        maxRetries: 5,
        skippable: false,
        dependencies: [LoadingPhase.RESOURCE_MANAGER_INIT]
      },
      {
        phase: LoadingPhase.OPENGL_INIT,
        description: 'OpenGL初始化',
        expectedDuration: 2000,
        maxRetries: 3,
        skippable: false,
        dependencies: [LoadingPhase.SURFACE_CREATION]
      },
      {
        phase: LoadingPhase.TEXTURE_LOADING,
        description: '纹理加载',
        expectedDuration: 3000,
        maxRetries: 2,
        skippable: true,
        dependencies: [LoadingPhase.OPENGL_INIT]
      },
      {
        phase: LoadingPhase.GAME_SYSTEMS_REGISTRATION,
        description: '游戏系统注册',
        expectedDuration: 1000,
        maxRetries: 3,
        skippable: false,
        dependencies: [LoadingPhase.TEXTURE_LOADING]
      },
      {
        phase: LoadingPhase.RENDER_LOOP_START,
        description: '渲染循环启动',
        expectedDuration: 500,
        maxRetries: 3,
        skippable: false,
        dependencies: [LoadingPhase.GAME_SYSTEMS_REGISTRATION]
      },
      {
        phase: LoadingPhase.READY,
        description: '系统就绪',
        expectedDuration: 0,
        maxRetries: 0,
        skippable: false,
        dependencies: [LoadingPhase.RENDER_LOOP_START]
      }
    ];
    
    phaseConfigs.forEach(config => {
      const phaseDetail: PhaseDetails = {
        name: config.phase,
        description: config.description,
        startTime: 0,
        state: LoadingState.PENDING,
        progress: {
          current: 0,
          total: 100,
          percentage: 0
        },
        retryCount: 0,
        maxRetries: config.maxRetries,
        skippable: config.skippable,
        dependencies: config.dependencies
      };
      
      this.phases.set(config.phase, phaseDetail);
    });
  }
  
  /**
   * 开始性能监控
   */
  private startPerformanceMonitoring(): void {
    if (!this.config.enablePerformanceMonitoring) {
      return;
    }
    
    this.performanceTimer = setInterval(() => {
      this.collectPerformanceMetrics();
    }, 1000); // 每秒收集一次
  }
  
  /**
   * 收集性能指标
   */
  private collectPerformanceMetrics(): void {
    try {
      // 这里可以集成实际的性能监控API
      const metrics: PerformanceMetrics = {
        memoryUsage: this.getMemoryUsage(),
        cpuUsage: this.getCpuUsage(),
        fps: this.getFps(),
        renderTime: this.getRenderTime()
      };
      
      // 更新统计信息
      this.updatePerformanceStatistics(metrics);
      
      // 检查性能阈值
      this.checkPerformanceThresholds(metrics);
      
    } catch (error) {
      logger.error('LoadingStateManager', `性能指标收集失败: ${error}`);
    }
  }
  
  /**
   * 获取内存使用量
   */
  private getMemoryUsage(): number {
    return 0;
  }
  
  /**
   * 获取CPU使用率
   */
  private getCpuUsage(): number {
    return 0;
  }
  
  /**
   * 获取帧率
   */
  private getFps(): number {
    return 0;
  }
  
  /**
   * 获取渲染时间
   */
  private getRenderTime(): number {
    return 0;
  }
  
  /**
   * 更新性能统计信息
   */
  private updatePerformanceStatistics(metrics: PerformanceMetrics): void {
    const stats = this.statistics.performanceStatistics;
    
    if (metrics.memoryUsage && metrics.memoryUsage > stats.peakMemoryUsage) {
      stats.peakMemoryUsage = metrics.memoryUsage;
    }
    
    if (metrics.cpuUsage) {
      stats.averageCpuUsage = (stats.averageCpuUsage + metrics.cpuUsage) / 2;
    }
    
    if (metrics.fps && metrics.fps < stats.minFps) {
      stats.minFps = metrics.fps;
    }
    
    if (metrics.renderTime && metrics.renderTime > stats.maxRenderTime) {
      stats.maxRenderTime = metrics.renderTime;
    }
  }
  
  /**
   * 检查性能阈值
   */
  private checkPerformanceThresholds(metrics: PerformanceMetrics): void {
    const thresholds = this.config.performanceThresholds;
    
    if (metrics.memoryUsage && metrics.memoryUsage > thresholds.memoryWarning) {
      this.reportError({
        code: 'MEMORY_WARNING',
        message: `内存使用量过高: ${Math.round(metrics.memoryUsage / 1024 / 1024)}MB`,
        severity: ErrorSeverity.WARNING,
        timestamp: Date.now(),
        data: { memoryUsage: metrics.memoryUsage }
      });
    }
    
    if (metrics.cpuUsage && metrics.cpuUsage > thresholds.cpuWarning) {
      this.reportError({
        code: 'CPU_WARNING',
        message: `CPU使用率过高: ${Math.round(metrics.cpuUsage)}%`,
        severity: ErrorSeverity.WARNING,
        timestamp: Date.now(),
        data: { cpuUsage: metrics.cpuUsage }
      });
    }
    
    if (metrics.fps && metrics.fps < thresholds.minFpsThreshold) {
      this.reportError({
        code: 'FPS_WARNING',
        message: `帧率过低: ${Math.round(metrics.fps)}fps`,
        severity: ErrorSeverity.WARNING,
        timestamp: Date.now(),
        data: { fps: metrics.fps }
      });
    }
  }
  
  /**
   * 转换到新阶段
   */
  public transitionToPhase(newPhase: LoadingPhase, data?: Record<string, PropertyValue>): void {
    const previousPhase = this.currentPhase;
    const previousState = this.phases.get(previousPhase)?.state || LoadingState.PENDING;
    
    // 完成当前阶段
    if (previousPhase !== LoadingPhase.UNINITIALIZED) {
      this.completePhase(previousPhase, true);
    }
    
    // 开始新阶段
    this.currentPhase = newPhase;
    this.startPhase(newPhase, data);
    
    // 发送状态变更事件
    const changeEvent: LoadingStateChangeEvent = {
      timestamp: Date.now(),
      phase: newPhase,
      previousState: previousState,
      currentState: LoadingState.IN_PROGRESS
    };
    
    this.notifyStateChange(changeEvent);
    
    logger.stateChange('LoadingStateManager', 
      `阶段转换: ${previousPhase} -> ${newPhase}`);
  }
  
  /**
   * 开始阶段
   */
  private startPhase(phase: LoadingPhase, data?: Record<string, PropertyValue>): void {
    const phaseDetail = this.phases.get(phase);
    if (!phaseDetail) {
      logger.error('LoadingStateManager', `未找到阶段详情: ${phase}`);
      return;
    }
    
    phaseDetail.startTime = Date.now();
    phaseDetail.state = LoadingState.IN_PROGRESS;
    phaseDetail.progress.current = 0;
    phaseDetail.progress.percentage = 0;
    
    if (data) {
      phaseDetail.data = { ...phaseDetail.data, ...data };
    }
    
    logger.lifecycle('LoadingStateManager', 
      `开始阶段: ${phase} - ${phaseDetail.description}`);
  }
  
  /**
   * 完成阶段
   */
  private completePhase(phase: LoadingPhase, success: boolean, error?: ErrorDetails): void {
    const phaseDetail = this.phases.get(phase);
    if (!phaseDetail) {
      return;
    }
    
    phaseDetail.endTime = Date.now();
    phaseDetail.duration = phaseDetail.endTime - phaseDetail.startTime;
    phaseDetail.state = success ? LoadingState.COMPLETED : LoadingState.FAILED;
    phaseDetail.progress.current = phaseDetail.progress.total;
    phaseDetail.progress.percentage = 100;
    
    if (error) {
      phaseDetail.error = error;
    }
    
    // 更新统计信息
    if (success) {
      this.statistics.successfulPhases++;
    } else {
      this.statistics.failedPhases++;
    }
    
    logger.lifecycle('LoadingStateManager', 
      `完成阶段: ${phase} - ${success ? '成功' : '失败'} (${phaseDetail.duration}ms)`);
  }
  
  /**
   * 报告错误
   */
  public reportError(error: ErrorDetails): void {
    this.globalErrors.push(error);
    
    // 更新错误统计
    this.statistics.errorStatistics.totalErrors++;
    
    const phaseErrorCount = this.statistics.errorStatistics.errorsByPhase.get(this.currentPhase) || 0;
    this.statistics.errorStatistics.errorsByPhase.set(this.currentPhase, phaseErrorCount + 1);
    
    const severityErrorCount = this.statistics.errorStatistics.errorsBySeverity.get(error.severity) || 0;
    this.statistics.errorStatistics.errorsBySeverity.set(error.severity, severityErrorCount + 1);
    
    logger.error('LoadingStateManager', 
      `错误报告 [${error.severity}] ${error.code}: ${error.message}`);
    
    // 发送错误事件
    const changeEvent: LoadingStateChangeEvent = {
      timestamp: Date.now(),
      phase: this.currentPhase,
      previousState: LoadingState.IN_PROGRESS,
      currentState: LoadingState.FAILED,
      error: error
    };
    
    this.notifyStateChange(changeEvent);
    
    // 如果是致命错误，尝试恢复
    if (error.severity === ErrorSeverity.CRITICAL) {
      this.attemptRecovery(error);
    }
  }
  
  /**
   * 尝试恢复
   */
  private attemptRecovery(error: ErrorDetails): void {
    const strategies = error.suggestedRecovery || [RecoveryStrategy.RETRY];
    
    for (const strategy of strategies) {
      const result = this.executeRecoveryStrategy(strategy, error);
      if (result.success) {
        logger.lifecycle('LoadingStateManager', 
          `恢复成功: ${strategy} - ${result.message}`);
        return;
      }
    }
    
    logger.error('LoadingStateManager', '所有恢复策略都失败了');
  }
  
  /**
   * 执行恢复策略
   */
  private executeRecoveryStrategy(strategy: RecoveryStrategy, error: ErrorDetails): RecoveryResult {
    const startTime = Date.now();
    
    try {
      switch (strategy) {
        case RecoveryStrategy.RETRY:
          return this.retryCurrentPhase();
        case RecoveryStrategy.SKIP:
          return this.skipCurrentPhase();
        case RecoveryStrategy.RESET:
          return this.resetToPhase(LoadingPhase.UNINITIALIZED);
        case RecoveryStrategy.FALLBACK:
          return this.fallbackToPreviousPhase();
        default:
          return {
            success: false,
            strategy: strategy,
            message: `不支持的恢复策略: ${strategy}`,
            duration: Date.now() - startTime
          };
      }
    } catch (recoveryError) {
      return {
        success: false,
        strategy: strategy,
        message: `恢复策略执行失败: ${recoveryError}`,
        duration: Date.now() - startTime
      };
    }
  }
  
  /**
   * 重试当前阶段
   */
  private retryCurrentPhase(): RecoveryResult {
    const phaseDetail = this.phases.get(this.currentPhase);
    if (!phaseDetail) {
      return {
        success: false,
        strategy: RecoveryStrategy.RETRY,
        message: '未找到当前阶段详情',
        duration: 0
      };
    }
    
    if (phaseDetail.retryCount >= phaseDetail.maxRetries) {
      return {
        success: false,
        strategy: RecoveryStrategy.RETRY,
        message: `已达到最大重试次数: ${phaseDetail.maxRetries}`,
        duration: 0
      };
    }
    
    phaseDetail.retryCount++;
    phaseDetail.state = LoadingState.RETRYING;
    this.statistics.totalRetries++;
    
    // 延迟后重新开始阶段
    setTimeout(() => {
      this.startPhase(this.currentPhase);
    }, this.config.autoRetryConfig.retryDelay * Math.pow(this.config.autoRetryConfig.backoffFactor, phaseDetail.retryCount - 1));
    
    return {
      success: true,
      strategy: RecoveryStrategy.RETRY,
      message: `重试阶段 ${this.currentPhase} (第${phaseDetail.retryCount}次)`,
      duration: 0
    };
  }
  
  /**
   * 跳过当前阶段
   */
  private skipCurrentPhase(): RecoveryResult {
    const phaseDetail = this.phases.get(this.currentPhase);
    if (!phaseDetail || !phaseDetail.skippable) {
      return {
        success: false,
        strategy: RecoveryStrategy.SKIP,
        message: '当前阶段不可跳过',
        duration: 0
      };
    }
    
    phaseDetail.state = LoadingState.SKIPPED;
    this.statistics.skippedPhases++;
    
    // 转到下一个阶段
    const nextPhase = this.getNextPhase(this.currentPhase);
    if (nextPhase) {
      this.transitionToPhase(nextPhase);
    }
    
    return {
      success: true,
      strategy: RecoveryStrategy.SKIP,
      message: `跳过阶段 ${this.currentPhase}`,
      duration: 0
    };
  }
  
  /**
   * 重置到指定阶段
   */
  private resetToPhase(targetPhase: LoadingPhase): RecoveryResult {
    this.currentPhase = targetPhase;
    
    // 重置所有后续阶段
    const phaseEntries = Array.from(this.phases.entries());
    for (let i = 0; i < phaseEntries.length; i++) {
      const phase = phaseEntries[i][0];
      const detail = phaseEntries[i][1];
      if (this.isPhaseAfter(phase, targetPhase)) {
        detail.state = LoadingState.PENDING;
        detail.progress.current = 0;
        detail.progress.percentage = 0;
        detail.retryCount = 0;
        detail.error = undefined;
      }
    }
    
    this.startPhase(targetPhase);
    
    return {
      success: true,
      strategy: RecoveryStrategy.RESET,
      message: `重置到阶段 ${targetPhase}`,
      recoveredPhase: targetPhase,
      duration: 0
    };
  }
  
  /**
   * 回退到上一个阶段
   */
  private fallbackToPreviousPhase(): RecoveryResult {
    const previousPhase = this.getPreviousPhase(this.currentPhase);
    if (!previousPhase) {
      return {
        success: false,
        strategy: RecoveryStrategy.FALLBACK,
        message: '没有可回退的阶段',
        duration: 0
      };
    }
    
    return this.resetToPhase(previousPhase);
  }
  
  /**
   * 获取下一个阶段
   */
  private getNextPhase(currentPhase: LoadingPhase): LoadingPhase | null {
    const phases = Object.values(LoadingPhase);
    const currentIndex = phases.indexOf(currentPhase);
    return currentIndex < phases.length - 1 ? phases[currentIndex + 1] : null;
  }
  
  /**
   * 获取上一个阶段
   */
  private getPreviousPhase(currentPhase: LoadingPhase): LoadingPhase | null {
    const phases = Object.values(LoadingPhase);
    const currentIndex = phases.indexOf(currentPhase);
    return currentIndex > 0 ? phases[currentIndex - 1] : null;
  }
  
  /**
   * 判断阶段是否在目标阶段之后
   */
  private isPhaseAfter(phase: LoadingPhase, targetPhase: LoadingPhase): boolean {
    const phases = Object.values(LoadingPhase);
    return phases.indexOf(phase) > phases.indexOf(targetPhase);
  }
  
  /**
   * 通知状态变更
   */
  private notifyStateChange(event: LoadingStateChangeEvent): void {
    // 通知内部监听器
    const listenersSnapshot: Array<(event: LoadingStateChangeEvent) => void> = this.stateChangeListeners.slice();
    listenersSnapshot.forEach(listener => {
      try {
        listener(event);
      } catch (error) {
        logger.error('LoadingStateManager', `状态变更监听器执行失败: ${error}`);
      }
    });
    
    // 发送全局事件
    EventBus.getInstance().publish(GameEvent.LOADING_STATE_CHANGE, 
      new LoadingStateChangeEventPayload(event));
  }
  
  /**
   * 添加状态变更监听器
   */
  public addStateChangeListener(listener: (event: LoadingStateChangeEvent) => void): void {
    if (this.stateChangeListeners.includes(listener)) {
      return;
    }
    this.stateChangeListeners.push(listener);
  }
  
  /**
   * 移除状态变更监听器
   */
  public removeStateChangeListener(listener: (event: LoadingStateChangeEvent) => void): void {
    const index = this.stateChangeListeners.indexOf(listener);
    if (index > -1) {
      this.stateChangeListeners.splice(index, 1);
    }
  }
  
  /**
   * 获取当前状态快照
   */
  public getStateSnapshot(): LoadingStateSnapshot {
    const overallProgress = this.calculateOverallProgress();
    
    return {
      timestamp: Date.now(),
      currentPhase: this.currentPhase,
      overallProgress: overallProgress,
      phases: new Map(this.phases),
      globalErrors: [...this.globalErrors],
      systemMetrics: this.getCurrentMetrics(),
      hasErrors: this.globalErrors.length > 0,
      canRecover: this.canRecover(),
      suggestedActions: this.getSuggestedActions()
    };
  }
  
  /**
   * 计算整体进度
   */
  private calculateOverallProgress(): LoadingProgress {
    const totalPhases = this.phases.size;
    let completedPhases = 0;
    let totalProgress = 0;
    
    for (const detail of this.phases.values()) {
      if (detail.state === LoadingState.COMPLETED) {
        completedPhases++;
        totalProgress += 100;
      } else if (detail.state === LoadingState.IN_PROGRESS) {
        totalProgress += detail.progress.percentage;
      }
    }
    
    const percentage = totalPhases > 0 ? totalProgress / totalPhases : 0;
    
    return {
      current: completedPhases,
      total: totalPhases,
      percentage: Math.round(percentage * 100) / 100
    };
  }
  
  /**
   * 获取当前性能指标
   */
  private getCurrentMetrics(): PerformanceMetrics {
    return {
      memoryUsage: this.getMemoryUsage(),
      cpuUsage: this.getCpuUsage(),
      fps: this.getFps(),
      renderTime: this.getRenderTime()
    };
  }
  
  /**
   * 判断是否可以恢复
   */
  private canRecover(): boolean {
    const currentPhaseDetail = this.phases.get(this.currentPhase);
    if (!currentPhaseDetail) {
      return false;
    }
    
    // 如果当前阶段还有重试机会
    if (currentPhaseDetail.retryCount < currentPhaseDetail.maxRetries) {
      return true;
    }
    
    // 如果当前阶段可跳过
    if (currentPhaseDetail.skippable) {
      return true;
    }
    
    // 如果有严重错误但不是致命的
    const criticalErrors = this.globalErrors.filter(e => e.severity === ErrorSeverity.CRITICAL);
    return criticalErrors.length === 0;
  }
  
  /**
   * 获取建议的操作
   */
  private getSuggestedActions(): string[] {
    const actions: string[] = [];
    const currentPhaseDetail = this.phases.get(this.currentPhase);
    
    if (!currentPhaseDetail) {
      return ['重新初始化系统'];
    }
    
    if (currentPhaseDetail.state === LoadingState.FAILED) {
      if (currentPhaseDetail.retryCount < currentPhaseDetail.maxRetries) {
        actions.push('重试当前阶段');
      }
      
      if (currentPhaseDetail.skippable) {
        actions.push('跳过当前阶段');
      }
      
      actions.push('重置到初始状态');
    }
    
    if (this.globalErrors.length > 0) {
      actions.push('查看错误详情');
      actions.push('清除错误记录');
    }
    
    return actions;
  }
  
  /**
   * 获取统计信息
   */
  public getStatistics(): LoadingStatistics {
    return { ...this.statistics };
  }
  
  /**
   * 清理资源
   */
  public cleanup(): void {
    if (this.performanceTimer) {
      clearInterval(this.performanceTimer);
      this.performanceTimer = null;
    }
    
    this.stateChangeListeners.length = 0;
    this.globalErrors.length = 0;
    
    logger.lifecycle('LoadingStateManager', '加载状态管理器已清理');
  }
}
