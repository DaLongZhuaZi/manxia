/**
 * 全局任务协调器
 * 
 * 职责：
 * 1. 管理所有页面的生命周期管理器
 * 2. 提供全局任务监控和统计
 * 3. 内存压力时的紧急清理
 * 4. 调试和诊断支持
 * 
 * 文件路径: entry/src/main/ets/Framework/Lifecycle/GlobalTaskCoordinator.ets
 */

import { logger } from '../../Utils/Logger';

const TAG = 'GlobalTaskCoordinator';

/**
 * 页面统计信息
 */
export interface PageStats {
  pageId: string;
  timerCount: number;
  promiseCount: number;
  resourceCount: number;
  listenerCount: number;
  uptime: number;
}

/**
 * 全局统计信息
 */
export interface GlobalStats {
  totalPages: number;
  totalTimers: number;
  totalPromises: number;
  totalResources: number;
  totalListeners: number;
  memoryUsage?: number;
}

/**
 * 协调器配置
 */
interface CoordinatorConfig {
  enableAutoCleanup: boolean;
  memoryThreshold: number;
  maxPagesWarning: number;
  statsUpdateInterval: number;
}

/**
 * 任务转储信息
 */
export interface TaskDumpInfo {
  timestamp: number;
  pages: PageStats[];
  globalStats: GlobalStats;
}

/**
 * 全局任务协调器（单例）
 */
export class GlobalTaskCoordinator {
  private static instance: GlobalTaskCoordinator | null = null;
  
  // 页面管理器注册表
  private pageManagers: Map<string, ESObject> = new Map();
  
  // 统计数据
  private stats: GlobalStats = {
    totalPages: 0,
    totalTimers: 0,
    totalPromises: 0,
    totalResources: 0,
    totalListeners: 0
  };
  
  // 配置
  private config: CoordinatorConfig = {
    enableAutoCleanup: true,
    memoryThreshold: 0.8, // 80% 内存使用率触发清理
    maxPagesWarning: 20,  // 页面数量警告阈值
    statsUpdateInterval: 5000 // 统计更新间隔（毫秒）
  };
  
  // 定时器
  private statsUpdateTimer: number = -1;
  
  private constructor() {
    logger.info(TAG, '全局任务协调器初始化');
    this.startStatsUpdate();
  }
  
  /**
   * 获取单例实例
   */
  static getInstance(): GlobalTaskCoordinator {
    if (!GlobalTaskCoordinator.instance) {
      GlobalTaskCoordinator.instance = new GlobalTaskCoordinator();
    }
    return GlobalTaskCoordinator.instance;
  }
  
  /**
   * 注册页面管理器
   */
  registerPage(pageId: string, manager: ESObject): void {
    if (this.pageManagers.has(pageId)) {
      logger.warn(TAG, `页面已注册: ${pageId}`);
      return;
    }
    
    this.pageManagers.set(pageId, manager);
    this.updateStats();
    
    logger.info(TAG, `页面已注册: ${pageId}, 当前总数: ${this.pageManagers.size}`);
    
    // 检查页面数量
    if (this.pageManagers.size > this.config.maxPagesWarning) {
      logger.warn(TAG, `活跃页面数量过多: ${this.pageManagers.size}`);
    }
  }
  
  /**
   * 注销页面管理器
   */
  unregisterPage(pageId: string): void {
    if (this.pageManagers.delete(pageId)) {
      this.updateStats();
      logger.info(TAG, `页面已注销: ${pageId}, 剩余: ${this.pageManagers.size}`);
    }
  }
  
  /**
   * 获取页面管理器
   */
  getPageManager(pageId: string): ESObject | undefined {
    return this.pageManagers.get(pageId);
  }
  
  /**
   * 获取所有页面 ID
   */
  getAllPageIds(): string[] {
    return Array.from(this.pageManagers.keys());
  }
  
  /**
   * 获取活跃任务数量
   */
  getActiveTaskCount(): number {
    return this.stats.totalTimers + this.stats.totalPromises;
  }
  
  /**
   * 获取全局统计信息
   */
  getGlobalStats(): GlobalStats {
    return {
      totalPages: this.stats.totalPages,
      totalTimers: this.stats.totalTimers,
      totalPromises: this.stats.totalPromises,
      totalResources: this.stats.totalResources,
      totalListeners: this.stats.totalListeners,
      memoryUsage: this.stats.memoryUsage
    };
  }
  
  /**
   * 更新统计信息
   */
  private updateStats(): void {
    const pages: ESObject[] = [];
    this.pageManagers.forEach((value: ESObject) => {
      pages.push(value);
    });
    let totalTimers = 0;
    let totalPromises = 0;
    let totalResources = 0;
    let totalListeners = 0;
    
    this.pageManagers.forEach((manager: ESObject) => {
      if (manager && typeof manager.getStats === 'function') {
        const stats = (manager.getStats?.() as PageStats) || { timerCount: 0, promiseCount: 0, resourceCount: 0, listenerCount: 0, uptime: 0 };
        totalTimers += stats.timerCount || 0;
        totalPromises += stats.promiseCount || 0;
        totalResources += stats.resourceCount || 0;
        totalListeners += stats.listenerCount || 0;
      }
    });
    
    this.stats = {
      totalPages: this.pageManagers.size,
      totalTimers,
      totalPromises,
      totalResources,
      totalListeners
    };
  }
  
  /**
   * 启动统计更新定时器
   */
  private startStatsUpdate(): void {
    if (this.statsUpdateTimer !== -1) {
      return;
    }
    
    this.statsUpdateTimer = setInterval(() => {
      this.updateStats();
      
      // 检查是否需要警告
      if (this.stats.totalTimers > 50) {
        logger.warn(TAG, `全局定时器数量较多: ${this.stats.totalTimers}`);
      }
      if (this.stats.totalPromises > 30) {
        logger.warn(TAG, `全局 Promise 数量较多: ${this.stats.totalPromises}`);
      }
    }, this.config.statsUpdateInterval) as number;
  }
  
  /**
   * 停止统计更新定时器
   */
  private stopStatsUpdate(): void {
    if (this.statsUpdateTimer !== -1) {
      clearInterval(this.statsUpdateTimer);
      this.statsUpdateTimer = -1;
    }
  }
  
  /**
   * 紧急清理（内存压力时）
   */
  async emergencyCleanup(): Promise<void> {
    logger.warn(TAG, '执行紧急清理...');
    
    const managers: ESObject[] = [];
    this.pageManagers.forEach((value: ESObject) => {
      managers.push(value);
    });
    let cleanedPages = 0;
    
    // 获取所有页面的运行时间
    interface PageUptimeInfo {
      pageId: string;
      uptime: number;
      manager: ESObject;
    }
    const pageUptimes: PageUptimeInfo[] = [];
    
    this.pageManagers.forEach((manager: ESObject, pageId: string) => {
      if (manager && typeof manager.getStats === 'function') {
        const stats = manager.getStats() as PageStats;
        pageUptimes.push({
          pageId,
          uptime: stats.uptime || 0,
          manager
        });
      }
    });
    
    // 按运行时间排序（最老的优先清理）
    pageUptimes.sort((a, b) => b.uptime - a.uptime);
    
    // 清理最老的 30% 页面
    const cleanupCount = Math.ceil(pageUptimes.length * 0.3);
    
    for (let i = 0; i < cleanupCount && i < pageUptimes.length; i++) {
      const item = pageUptimes[i];
      const pageId = item.pageId;
      const manager: ESObject = item.manager;
      try {
        if (manager && typeof manager.destroy === 'function') {
          await manager.destroy();
          cleanedPages++;
          logger.info(TAG, `紧急清理页面: ${pageId}`);
        }
      } catch (error) {
        logger.error(TAG, `清理页面失败: ${pageId}, ${error as ESObject}`);
      }
    }
    
    const duration = Date.now() - (pageUptimes[0].uptime || 0);
    logger.warn(TAG, `紧急清理完成: 清理了 ${cleanedPages} 个页面, 耗时: ${duration}ms`);
    
    this.updateStats();
  }
  
  /**
   * 转储所有活跃任务信息
   */
  dumpActiveTasks(): TaskDumpInfo {
    const pages: PageStats[] = [];
    this.pageManagers.forEach((manager: ESObject, pageId: string) => {
      if (manager && typeof manager.getStats === 'function') {
        const stats = manager.getStats() as PageStats;
        pages.push({
          pageId: stats.pageId || pageId,
          timerCount: stats.timerCount || 0,
          promiseCount: stats.promiseCount || 0,
          resourceCount: stats.resourceCount || 0,
          listenerCount: stats.listenerCount || 0,
          uptime: stats.uptime || 0
        });
      }
    });
    
    // 按任务数量排序
    pages.sort((a, b) => {
      const aTotal = a.timerCount + a.promiseCount + a.resourceCount;
      const bTotal = b.timerCount + b.promiseCount + b.resourceCount;
      return bTotal - aTotal;
    });
    
    const dumpInfo: TaskDumpInfo = {
      timestamp: Date.now(),
      pages,
      globalStats: this.stats
    };
    return dumpInfo;
  }
  
  /**
   * 打印调试信息
   */
  printDebugInfo(): void {
    const dump = this.dumpActiveTasks();
    
    logger.info(TAG, '========== 全局任务状态 ==========');
    logger.info(TAG, `活跃页面: ${dump.globalStats.totalPages}`);
    logger.info(TAG, `总定时器: ${dump.globalStats.totalTimers}`);
    logger.info(TAG, `总 Promise: ${dump.globalStats.totalPromises}`);
    logger.info(TAG, `总资源: ${dump.globalStats.totalResources}`);
    logger.info(TAG, `总监听器: ${dump.globalStats.totalListeners}`);
    logger.info(TAG, '');
    
    if (dump.pages.length > 0) {
      logger.info(TAG, '页面详情:');
      dump.pages.forEach(page => {
        const total = page.timerCount + page.promiseCount + page.resourceCount;
        logger.info(TAG, `  ${page.pageId}:`);
        logger.info(TAG, `    定时器: ${page.timerCount}, Promise: ${page.promiseCount}, 资源: ${page.resourceCount}`);
        logger.info(TAG, `    监听器: ${page.listenerCount}, 运行时间: ${page.uptime}ms, 总任务: ${total}`);
      });
    }
    
    logger.info(TAG, '===================================');
  }
  
  /**
   * 获取详细的调试信息字符串
   */
  getDebugInfoString(): string {
    const dump = this.dumpActiveTasks();
    const lines: string[] = [
      '========== 全局任务状态 ==========',
      `时间: ${new Date(dump.timestamp).toLocaleString()}`,
      `活跃页面: ${dump.globalStats.totalPages}`,
      `总定时器: ${dump.globalStats.totalTimers}`,
      `总 Promise: ${dump.globalStats.totalPromises}`,
      `总资源: ${dump.globalStats.totalResources}`,
      `总监听器: ${dump.globalStats.totalListeners}`,
      ''
    ];
    
    if (dump.pages.length > 0) {
      lines.push('页面详情:');
      dump.pages.forEach(page => {
        const total = page.timerCount + page.promiseCount + page.resourceCount;
        lines.push(`  ${page.pageId}:`);
        lines.push(`    定时器: ${page.timerCount}, Promise: ${page.promiseCount}, 资源: ${page.resourceCount}`);
        lines.push(`    监听器: ${page.listenerCount}, 运行时间: ${page.uptime}ms, 总任务: ${total}`);
      });
    } else {
      lines.push('无活跃页面');
    }
    
    lines.push('===================================');
    
    return lines.join('\n');
  }
  
  /**
   * 销毁协调器（通常不需要调用）
   */
  destroy(): void {
    this.stopStatsUpdate();
    this.pageManagers.clear();
    logger.info(TAG, '全局任务协调器已销毁');
  }
}
