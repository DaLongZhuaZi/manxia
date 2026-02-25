// 文件路径: entry/src/main/ets/Framework/Managers/AppInitializationManager.ets
/**
 * APP初始化状态管理器
 * 提供可监控的初始化流程，让SplashPage能够感知真实的初始化进度
 */

import { logger } from '../../Utils/Logger';

const TAG = 'AppInitializationManager';

/**
 * 初始化阶段枚举
 */
export enum InitPhase {
  NOT_STARTED = 'not_started',           // 未开始
  CONTEXT_SETUP = 'context_setup',       // 设置全局上下文
  DEVICE_ADAPTATION = 'device_adaptation', // 设备适配
  DATA_SYSTEM = 'data_system',           // 数据系统初始化
  SETTINGS = 'settings',                 // 设置管理器
  FONT_MANAGER = 'font_manager',         // 字体管理器
  PROXY_MANAGER = 'proxy_manager',       // 代理管理器
  DOWNLOAD_SYNC = 'download_sync',       // 下载同步管理器
  DOWNLOAD_MANAGER = 'download_manager', // 下载管理器
  AUTO_BACKUP = 'auto_backup',           // 自动备份调度器
  WIDGET_SYNC = 'widget_sync',           // 桌面卡片同步
  CHANGELOG = 'changelog',               // 更新日志管理器
  CRASH_RECORDER = 'crash_recorder',     // 闪退记录服务
  ERROR_MONITOR = 'error_monitor',       // 错误监控服务
  COMPLETED = 'completed',               // 全部完成
  FAILED = 'failed'                      // 初始化失败
}

/**
 * 初始化阶段信息
 */
export interface PhaseInfo {
  phase: InitPhase;
  displayName: string;      // 显示名称
  progress: number;         // 进度百分比 (0-100)
  isRequired: boolean;      // 是否为必需阶段（失败会阻止启动）
}

/**
 * 初始化阶段配置
 */
const PHASE_CONFIG: Record<InitPhase, PhaseInfo> = {
  [InitPhase.NOT_STARTED]: { phase: InitPhase.NOT_STARTED, displayName: '准备启动', progress: 0, isRequired: false },
  [InitPhase.CONTEXT_SETUP]: { phase: InitPhase.CONTEXT_SETUP, displayName: '初始化环境', progress: 5, isRequired: true },
  [InitPhase.DEVICE_ADAPTATION]: { phase: InitPhase.DEVICE_ADAPTATION, displayName: '设备适配', progress: 10, isRequired: false },
  [InitPhase.DATA_SYSTEM]: { phase: InitPhase.DATA_SYSTEM, displayName: '加载数据', progress: 25, isRequired: true },
  [InitPhase.SETTINGS]: { phase: InitPhase.SETTINGS, displayName: '加载设置', progress: 40, isRequired: true },
  [InitPhase.FONT_MANAGER]: { phase: InitPhase.FONT_MANAGER, displayName: '加载字体', progress: 55, isRequired: true },
  [InitPhase.PROXY_MANAGER]: { phase: InitPhase.PROXY_MANAGER, displayName: '网络配置', progress: 65, isRequired: false },
  [InitPhase.DOWNLOAD_SYNC]: { phase: InitPhase.DOWNLOAD_SYNC, displayName: '同步管理', progress: 72, isRequired: false },
  [InitPhase.DOWNLOAD_MANAGER]: { phase: InitPhase.DOWNLOAD_MANAGER, displayName: '下载服务', progress: 78, isRequired: false },
  [InitPhase.AUTO_BACKUP]: { phase: InitPhase.AUTO_BACKUP, displayName: '备份服务', progress: 84, isRequired: false },
  [InitPhase.WIDGET_SYNC]: { phase: InitPhase.WIDGET_SYNC, displayName: '卡片同步', progress: 90, isRequired: false },
  [InitPhase.CHANGELOG]: { phase: InitPhase.CHANGELOG, displayName: '版本检查', progress: 90, isRequired: false },
  [InitPhase.CRASH_RECORDER]: { phase: InitPhase.CRASH_RECORDER, displayName: '闪退记录', progress: 93, isRequired: false },
  [InitPhase.ERROR_MONITOR]: { phase: InitPhase.ERROR_MONITOR, displayName: '错误监控', progress: 96, isRequired: false },
  [InitPhase.COMPLETED]: { phase: InitPhase.COMPLETED, displayName: '启动完成', progress: 100, isRequired: false },
  [InitPhase.FAILED]: { phase: InitPhase.FAILED, displayName: '启动失败', progress: 0, isRequired: false }
};

/**
 * 初始化状态
 */
export interface InitializationState {
  currentPhase: InitPhase;
  progress: number;           // 0-100
  displayText: string;        // 显示文本
  isCompleted: boolean;       // 是否完成
  isFailed: boolean;          // 是否失败
  failedPhase?: InitPhase;    // 失败的阶段
  errorMessage?: string;      // 错误信息
  startTime: number;          // 开始时间
  completedPhases: InitPhase[]; // 已完成的阶段
}

/**
 * 进度回调类型
 */
export type InitProgressCallback = (state: InitializationState) => void;

/**
 * APP初始化状态管理器
 */
export class AppInitializationManager {
  private static instance: AppInitializationManager | null = null;
  
  private state: InitializationState;
  private callbacks: Set<InitProgressCallback> = new Set();
  private completionPromise: Promise<boolean> | null = null;
  private completionResolve: ((success: boolean) => void) | null = null;
  
  private constructor() {
    this.state = this.createInitialState();
  }
  
  static getInstance(): AppInitializationManager {
    if (!AppInitializationManager.instance) {
      AppInitializationManager.instance = new AppInitializationManager();
    }
    return AppInitializationManager.instance;
  }
  
  /**
   * 创建初始状态
   */
  private createInitialState(): InitializationState {
    return {
      currentPhase: InitPhase.NOT_STARTED,
      progress: 0,
      displayText: '准备启动...',
      isCompleted: false,
      isFailed: false,
      startTime: 0,
      completedPhases: []
    };
  }
  
  /**
   * 获取当前状态（返回副本）
   */
  getState(): InitializationState {
    return {
      currentPhase: this.state.currentPhase,
      progress: this.state.progress,
      displayText: this.state.displayText,
      isCompleted: this.state.isCompleted,
      isFailed: this.state.isFailed,
      failedPhase: this.state.failedPhase,
      errorMessage: this.state.errorMessage,
      startTime: this.state.startTime,
      completedPhases: this.state.completedPhases.slice()
    };
  }
  
  /**
   * 获取完成Promise
   * SplashPage可以await这个Promise来等待初始化完成
   */
  getCompletionPromise(): Promise<boolean> {
    if (!this.completionPromise) {
      this.completionPromise = new Promise<boolean>((resolve) => {
        this.completionResolve = resolve;
        
        // 如果已经完成，立即resolve
        if (this.state.isCompleted) {
          resolve(true);
        } else if (this.state.isFailed) {
          resolve(false);
        }
      });
    }
    return this.completionPromise;
  }
  
  /**
   * 注册进度回调
   */
  addProgressListener(callback: InitProgressCallback): void {
    this.callbacks.add(callback);
    // 立即通知当前状态
    callback(this.getState());
  }
  
  /**
   * 移除进度回调
   */
  removeProgressListener(callback: InitProgressCallback): void {
    this.callbacks.delete(callback);
  }
  
  /**
   * 通知所有监听器
   */
  private notifyListeners(): void {
    const currentState = this.getState();
    this.callbacks.forEach(callback => {
      try {
        callback(currentState);
      } catch (error) {
        logger.error(TAG, `进度回调执行失败: ${String(error)}`);
      }
    });
    
    // 同步到AppStorage供UI绑定
    AppStorage.setOrCreate('app_init_phase', this.state.currentPhase);
    AppStorage.setOrCreate('app_init_progress', this.state.progress);
    AppStorage.setOrCreate('app_init_text', this.state.displayText);
    AppStorage.setOrCreate('app_init_completed', this.state.isCompleted);
  }
  
  /**
   * 开始初始化流程
   */
  startInitialization(): void {
    if (this.state.startTime > 0) {
      logger.warn(TAG, '初始化已经开始，忽略重复调用');
      return;
    }
    
    this.state = this.createInitialState();
    this.state.startTime = Date.now();
    
    // 重置completionPromise
    this.completionPromise = null;
    this.completionResolve = null;
    
    logger.info(TAG, '🚀 初始化流程开始');
    this.notifyListeners();
  }
  
  /**
   * 开始某个阶段
   */
  beginPhase(phase: InitPhase): void {
    const phaseInfo = PHASE_CONFIG[phase];
    
    this.state.currentPhase = phase;
    this.state.progress = phaseInfo.progress;
    this.state.displayText = phaseInfo.displayName + '...';
    
    logger.info(TAG, `📍 开始阶段: ${phaseInfo.displayName} (${phaseInfo.progress}%)`);
    this.notifyListeners();
  }
  
  /**
   * 完成某个阶段
   */
  completePhase(phase: InitPhase): void {
    if (!this.state.completedPhases.includes(phase)) {
      this.state.completedPhases.push(phase);
    }
    
    const phaseInfo = PHASE_CONFIG[phase];
    logger.info(TAG, `✅ 完成阶段: ${phaseInfo.displayName}`);
  }
  
  /**
   * 阶段失败
   */
  failPhase(phase: InitPhase, error: string): void {
    const phaseInfo = PHASE_CONFIG[phase];
    
    if (phaseInfo.isRequired) {
      // 必需阶段失败，标记整体失败
      this.state.isFailed = true;
      this.state.failedPhase = phase;
      this.state.errorMessage = error;
      this.state.currentPhase = InitPhase.FAILED;
      this.state.displayText = `${phaseInfo.displayName}失败`;
      
      logger.error(TAG, `❌ 关键阶段失败: ${phaseInfo.displayName} - ${error}`);
      
      // 通知completionPromise
      if (this.completionResolve) {
        this.completionResolve(false);
      }
    } else {
      // 非必需阶段失败，记录警告但继续
      logger.warn(TAG, `⚠️ 非关键阶段失败: ${phaseInfo.displayName} - ${error}`);
    }
    
    this.notifyListeners();
  }
  
  /**
   * 标记初始化完成
   */
  markCompleted(): void {
    const duration = Date.now() - this.state.startTime;
    
    this.state.currentPhase = InitPhase.COMPLETED;
    this.state.progress = 100;
    this.state.displayText = '启动完成';
    this.state.isCompleted = true;
    
    logger.info(TAG, `🎉 初始化全部完成，总耗时: ${duration}ms`);
    logger.info(TAG, `📊 完成阶段: ${this.state.completedPhases.join(', ')}`);
    
    this.notifyListeners();
    
    // 通知completionPromise
    if (this.completionResolve) {
      this.completionResolve(true);
    }
  }
  
  /**
   * 检查是否已完成
   */
  isCompleted(): boolean {
    return this.state.isCompleted;
  }
  
  /**
   * 检查是否失败
   */
  isFailed(): boolean {
    return this.state.isFailed;
  }
  
  /**
   * 获取初始化耗时
   */
  getDuration(): number {
    if (this.state.startTime === 0) return 0;
    return Date.now() - this.state.startTime;
  }
  
  /**
   * 重置状态（用于测试或重启）
   */
  reset(): void {
    this.state = this.createInitialState();
    this.completionPromise = null;
    this.completionResolve = null;
    logger.info(TAG, '初始化状态已重置');
    this.notifyListeners();
  }
}

// 导出单例获取函数
export function getAppInitializationManager(): AppInitializationManager {
  return AppInitializationManager.getInstance();
}
