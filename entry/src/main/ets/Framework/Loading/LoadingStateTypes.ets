// 文件路径: src/main/ets/Framework/Loading/LoadingStateTypes.ets
/**
 * 加载状态相关的类型定义和接口
 * 定义了加载阶段、加载状态、错误严重程度、恢复策略以及加载进度信息等类型
 */

import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
// 移除对Game目录的依赖，使用简单的类型定义
export type PropertyValue = string | number | boolean;

/**
 * 加载阶段枚举 - 与C++生命周期状态同步
 */
export enum LoadingPhase {
  /** 未初始化 */
  UNINITIALIZED = 'UNINITIALIZED',
  /** 预初始化检查 */
  PRE_INIT_CHECK = 'PRE_INIT_CHECK',
  /** 全局上下文初始化 */
  GLOBAL_CONTEXT_INIT = 'GLOBAL_CONTEXT_INIT',
  /** 资源管理器初始化 */
  RESOURCE_MANAGER_INIT = 'RESOURCE_MANAGER_INIT',
  /** Surface创建 */
  SURFACE_CREATION = 'SURFACE_CREATION',
  /** OpenGL初始化 */
  OPENGL_INIT = 'OPENGL_INIT',
  /** 纹理加载 */
  TEXTURE_LOADING = 'TEXTURE_LOADING',
  /** 游戏系统注册 */
  GAME_SYSTEMS_REGISTRATION = 'GAME_SYSTEMS_REGISTRATION',
  /** 渲染循环启动 */
  RENDER_LOOP_START = 'RENDER_LOOP_START',
  /** 完成就绪 */
  READY = 'READY',
  /** 错误状态 */
  ERROR = 'ERROR',
  /** 恢复中 */
  RECOVERING = 'RECOVERING'
}

/**
 * 加载状态枚举
 */
export enum LoadingState {
  /** 等待中 */
  PENDING = 'PENDING',
  /** 进行中 */
  IN_PROGRESS = 'IN_PROGRESS',
  /** 已完成 */
  COMPLETED = 'COMPLETED',
  /** 失败 */
  FAILED = 'FAILED',
  /** 跳过 */
  SKIPPED = 'SKIPPED',
  /** 重试中 */
  RETRYING = 'RETRYING'
}

/**
 * 错误严重程度枚举
 */
export enum ErrorSeverity {
  /** 信息 */
  INFO = 'INFO',
  /** 警告 */
  WARNING = 'WARNING',
  /** 错误 */
  ERROR = 'ERROR',
  /** 致命错误 */
  CRITICAL = 'CRITICAL'
}

/**
 * 恢复策略枚举
 */
export enum RecoveryStrategy {
  /** 重试 */
  RETRY = 'RETRY',
  /** 跳过 */
  SKIP = 'SKIP',
  /** 重置 */
  RESET = 'RESET',
  /** 降级 */
  FALLBACK = 'FALLBACK',
  /** 手动干预 */
  MANUAL = 'MANUAL'
}

/**
 * 加载进度信息接口
 */
export interface LoadingProgress {
  /** 当前进度值 (0-100) */
  current: number;
  /** 总进度值 */
  total: number;
  /** 进度百分比 (0-100) */
  percentage: number;
  /** 预计剩余时间 (毫秒) */
  estimatedTimeRemaining?: number;
  /** 当前速度 (单位/秒) */
  currentSpeed?: number;
}

/**
 * 错误详情接口
 */
export interface ErrorDetails {
  /** 错误代码 */
  code: string;
  /** 错误消息 */
  message: string;
  /** 错误严重程度 */
  severity: ErrorSeverity;
  /** 错误堆栈 */
  stack?: string;
  /** 错误时间戳 */
  timestamp: number;
  /** 相关数据 */
  data?: Record<string, PropertyValue>;
  /** 建议的恢复策略 */
  suggestedRecovery?: RecoveryStrategy[];
}

/**
 * 性能指标接口
 */
export interface PerformanceMetrics {
  /** 内存使用量 (字节) */
  memoryUsage?: number;
  /** CPU使用率 (0-100) */
  cpuUsage?: number;
  /** 帧率 */
  fps?: number;
  /** 渲染时间 (毫秒) */
  renderTime?: number;
  /** 加载速度 (KB/s) */
  loadingSpeed?: number;
}

/**
 * 阶段详细信息接口
 */
export interface PhaseDetails {
  /** 阶段名称 */
  name: string;
  /** 阶段描述 */
  description: string;
  /** 开始时间 */
  startTime: number;
  /** 结束时间 */
  endTime?: number;
  /** 持续时间 (毫秒) */
  duration?: number;
  /** 当前状态 */
  state: LoadingState;
  /** 进度信息 */
  progress: LoadingProgress;
  /** 错误信息 */
  error?: ErrorDetails;
  /** 性能指标 */
  metrics?: PerformanceMetrics;
  /** 重试次数 */
  retryCount: number;
  /** 最大重试次数 */
  maxRetries: number;
  /** 是否可跳过 */
  skippable: boolean;
  /** 依赖的阶段 */
  dependencies?: LoadingPhase[];
  /** 额外数据 */
  data?: Record<string, PropertyValue>;
}

/**
 * 加载状态快照接口
 */
export interface LoadingStateSnapshot {
  /** 快照时间戳 */
  timestamp: number;
  /** 当前阶段 */
  currentPhase: LoadingPhase;
  /** 整体进度 */
  overallProgress: LoadingProgress;
  /** 所有阶段详情 */
  phases: Map<LoadingPhase, PhaseDetails>;
  /** 全局错误列表 */
  globalErrors: ErrorDetails[];
  /** 系统性能指标 */
  systemMetrics: PerformanceMetrics;
  /** 是否处于错误状态 */
  hasErrors: boolean;
  /** 是否可以恢复 */
  canRecover: boolean;
  /** 建议的操作 */
  suggestedActions: string[];
}

/**
 * 状态变更事件接口
 */
export interface LoadingStateChangeEvent {
  /** 事件时间戳 */
  timestamp: number;
  /** 阶段 */
  phase: LoadingPhase;
  /** 之前状态 */
  previousState: LoadingState;
  /** 当前状态 */
  currentState: LoadingState;
  /** 进度变化 */
  progressDelta?: number;
  /** 错误信息 */
  error?: ErrorDetails;
  /** 性能指标变化 */
  metricsChange?: Partial<PerformanceMetrics>;
}

/**
 * 恢复操作结果接口
 */
export interface RecoveryResult {
  /** 是否成功 */
  success: boolean;
  /** 使用的策略 */
  strategy: RecoveryStrategy;
  /** 结果消息 */
  message: string;
  /** 恢复后的阶段 */
  recoveredPhase?: LoadingPhase;
  /** 恢复耗时 (毫秒) */
  duration: number;
  /** 额外信息 */
  details?: Record<string, PropertyValue>;
}

/**
 * 加载配置接口
 */
export interface LoadingConfiguration {
  /** 是否启用详细日志 */
  enableVerboseLogging: boolean;
  /** 是否启用性能监控 */
  enablePerformanceMonitoring: boolean;
  /** 自动重试配置 */
  autoRetryConfig: {
    /** 是否启用自动重试 */
    enabled: boolean;
    /** 默认最大重试次数 */
    defaultMaxRetries: number;
    /** 重试延迟 (毫秒) */
    retryDelay: number;
    /** 指数退避因子 */
    backoffFactor: number;
  };
  /** 超时配置 */
  timeoutConfig: {
    /** 单个阶段超时 (毫秒) */
    phaseTimeout: number;
    /** 整体加载超时 (毫秒) */
    overallTimeout: number;
  };
  /** 性能阈值 */
  performanceThresholds: {
    /** 内存警告阈值 (字节) */
    memoryWarning: number;
    /** CPU警告阈值 (0-100) */
    cpuWarning: number;
    /** 最低帧率阈值 */
    minFpsThreshold: number;
  };
}

/**
 * 加载统计信息接口
 */
export interface LoadingStatistics {
  /** 总加载时间 (毫秒) */
  totalLoadingTime: number;
  /** 成功阶段数 */
  successfulPhases: number;
  /** 失败阶段数 */
  failedPhases: number;
  /** 跳过阶段数 */
  skippedPhases: number;
  /** 总重试次数 */
  totalRetries: number;
  /** 平均阶段时间 (毫秒) */
  averagePhaseTime: number;
  /** 最慢阶段 */
  slowestPhase?: {
    phase: LoadingPhase;
    duration: number;
  };
  /** 错误统计 */
  errorStatistics: {
    totalErrors: number;
    errorsByPhase: Map<LoadingPhase, number>;
    errorsBySeverity: Map<ErrorSeverity, number>;
  };
  /** 性能统计 */
  performanceStatistics: {
    peakMemoryUsage: number;
    averageCpuUsage: number;
    minFps: number;
    maxRenderTime: number;
  };
}