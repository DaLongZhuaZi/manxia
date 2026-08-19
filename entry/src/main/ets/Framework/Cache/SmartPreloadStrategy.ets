// 文件路径: src/main/ets/Framework/Cache/SmartPreloadStrategy.ets
/**
 * 智能预加载策略系统
 * 根据用户阅读行为动态调整预加载策略
 * 特性：
 * 1. 学习用户阅读速度
 * 2. 分析翻页方向偏好
 * 3. 根据网络状况调整
 * 4. WiFi环境下增加预加载
 */

import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { connection } from '@kit.NetworkKit';
import { CacheConfigManager } from './CacheConfigManager';

const TAG = 'SmartPreloadStrategy';

/**
 * 阅读行为数据
 */
interface ReadingBehavior {
  pageViewDuration: number;      // 页面停留时间（毫秒）
  direction: 'forward' | 'backward';  // 翻页方向
  timestamp: number;              // 时间戳
}

interface ReadingStats {
  totalPages: number;
  forwardPages: number;
  backwardPages: number;
  totalDuration: number;
}

/**
 * 预加载计划项
 */
export interface PreloadPlanItem {
  index: number;
  priority: number;
  direction: 'forward' | 'backward';
}

/**
 * 预加载策略
 */
export interface PreloadStrategy {
  forwardRange: number;           // 向前预加载范围
  backwardRange: number;          // 向后预加载范围
  priority: number;               // 优先级（1-10）
  reason: string;                 // 策略原因
}

/**
 * 统计数据
 */
export interface PreloadStats {
  totalPages: number;             // 总页数
  forwardPages: number;           // 向前翻页数
  backwardPages: number;          // 向后翻页数
  avgPageDuration: number;        // 平均页面停留时间
  forwardRatio: number;           // 向前翻页比例
  readingSpeed: 'slow' | 'normal' | 'fast';  // 阅读速度
  networkType: string;            // 网络类型
  currentStrategy: PreloadStrategy;  // 当前策略
}

/**
 * 智能预加载策略管理器
 */
export class SmartPreloadStrategy {
  private static instance: SmartPreloadStrategy | null = null;
  
  // 阅读行为历史（最近100条）
  private behaviorHistory: ReadingBehavior[] = [];
  private readonly MAX_HISTORY = 100;
  
  // 统计数据
  private stats: ReadingStats = {
    totalPages: 0,
    forwardPages: 0,
    backwardPages: 0,
    totalDuration: 0
  };

  // 当前策略
  private currentStrategy: PreloadStrategy = {
    forwardRange: 2,
    backwardRange: 1,
    priority: 5,
    reason: '默认策略'
  };
  
  // 网络状态
  private networkType: connection.NetBearType = connection.NetBearType.BEARER_CELLULAR;
  private isWiFi: boolean = false;
  
  // 配置管理器
  private configManager: CacheConfigManager;
  
  // 策略更新监听器
  private listeners: Array<(strategy: PreloadStrategy) => void> = [];

  private constructor() {
    this.configManager = CacheConfigManager.getInstance();
    logger.info(TAG, '智能预加载策略初始化');
  }

  /**
   * 获取单例实例
   */
  public static getInstance(): SmartPreloadStrategy {
    if (!SmartPreloadStrategy.instance) {
      SmartPreloadStrategy.instance = new SmartPreloadStrategy();
    }
    return SmartPreloadStrategy.instance;
  }

  /**
   * 初始化
   */
  public async initialize(): Promise<void> {
    try {
      // 检测网络状态
      await this.updateNetworkStatus();
      
      // 计算初始策略
      this.updateStrategy();
      
      logger.info(TAG, '智能预加载策略初始化完成');
    } catch (error) {
      logger.error(TAG, `初始化失败: ${String(error)}`);
    }
  }

  /**
   * 记录阅读行为
   */
  public recordBehavior(pageViewDuration: number, direction: 'forward' | 'backward'): void {
    const behavior: ReadingBehavior = {
      pageViewDuration,
      direction,
      timestamp: Date.now()
    };
    
    this.behaviorHistory.push(behavior);
    
    // 限制历史记录数量
    if (this.behaviorHistory.length > this.MAX_HISTORY) {
      this.behaviorHistory.shift();
    }
    
    // 更新统计
    this.stats.totalPages++;
    this.stats.totalDuration += pageViewDuration;
    if (direction === 'forward') {
      this.stats.forwardPages++;
    } else {
      this.stats.backwardPages++;
    }
    
    // 每10次行为更新一次策略
    if (this.stats.totalPages % 10 === 0) {
      this.updateStrategy();
    }
    
    logger.debug(TAG, `记录阅读行为: 停留${pageViewDuration}ms, 方向=${direction}`);
  }

  /**
   * 更新网络状态
   */
  private async updateNetworkStatus(): Promise<void> {
    try {
      const netHandle = await connection.getDefaultNet();
      const netCapabilities = await connection.getNetCapabilities(netHandle);
      
      if (netCapabilities.bearerTypes.includes(connection.NetBearType.BEARER_WIFI)) {
        this.networkType = connection.NetBearType.BEARER_WIFI;
        this.isWiFi = true;
      } else if (netCapabilities.bearerTypes.includes(connection.NetBearType.BEARER_CELLULAR)) {
        this.networkType = connection.NetBearType.BEARER_CELLULAR;
        this.isWiFi = false;
      }
      
      logger.debug(TAG, `网络状态: ${this.isWiFi ? 'WiFi' : '移动网络'}`);
    } catch (error) {
      logger.warn(TAG, `获取网络状态失败: ${String(error)}`);
      this.isWiFi = false;
    }
  }

  /**
   * 更新预加载策略
   */
  private updateStrategy(): void {
    const config = this.configManager.getPreloadConfig();
    
    if (!config.enabled) {
      this.currentStrategy = {
        forwardRange: 0,
        backwardRange: 0,
        priority: 0,
        reason: '预加载已禁用'
      };
      this.notifyListeners();
      return;
    }
    
    // 分析阅读速度
    const readingSpeed = this.analyzeReadingSpeed();
    
    // 分析翻页方向偏好
    const forwardRatio = this.analyzeDirectionPreference();
    
    // 基础范围（从配置获取）
    let forwardRange = config.rangeNormal;
    let backwardRange = Math.max(1, Math.floor(config.rangeNormal / 2));
    
    // 根据阅读速度调整
    if (readingSpeed === 'fast') {
      forwardRange += 2;
      backwardRange += 1;
    } else if (readingSpeed === 'slow') {
      forwardRange = Math.max(1, forwardRange - 1);
      backwardRange = Math.max(0, backwardRange - 1);
    }
    
    // 根据翻页方向偏好调整
    if (forwardRatio > 0.8) {
      // 主要向前翻页
      forwardRange += 1;
      backwardRange = Math.max(0, backwardRange - 1);
    } else if (forwardRatio < 0.5) {
      // 经常向后翻页
      backwardRange += 1;
    }
    
    // WiFi环境下增加预加载
    if (this.isWiFi) {
      forwardRange += 2;
      backwardRange += 1;
    }
    
    // 限制最大范围
    forwardRange = Math.min(forwardRange, 10);
    backwardRange = Math.min(backwardRange, 5);
    
    // 计算优先级
    const priority = this.calculatePriority(readingSpeed, forwardRatio);
    
    // 生成策略原因
    const reason = this.generateStrategyReason(readingSpeed, forwardRatio, this.isWiFi);
    
    this.currentStrategy = {
      forwardRange,
      backwardRange,
      priority,
      reason
    };
    
    logger.info(TAG, `策略更新: 向前${forwardRange}页, 向后${backwardRange}页, 原因: ${reason}`);
    
    this.notifyListeners();
  }

  /**
   * 分析阅读速度
   */
  private analyzeReadingSpeed(): 'slow' | 'normal' | 'fast' {
    if (this.behaviorHistory.length < 5) {
      return 'normal';
    }
    
    const recentBehaviors = this.behaviorHistory.slice(-20);
    const avgDuration = recentBehaviors.reduce((sum, b) => sum + b.pageViewDuration, 0) / recentBehaviors.length;
    
    if (avgDuration < 3000) {
      return 'fast';  // 快速翻页（<3秒/页）
    } else if (avgDuration > 10000) {
      return 'slow';  // 慢速阅读（>10秒/页）
    } else {
      return 'normal';
    }
  }

  /**
   * 分析翻页方向偏好
   */
  private analyzeDirectionPreference(): number {
    if (this.stats.totalPages === 0) {
      return 0.8;  // 默认假设主要向前翻页
    }
    
    return this.stats.forwardPages / this.stats.totalPages;
  }

  /**
   * 计算优先级
   */
  private calculatePriority(readingSpeed: string, forwardRatio: number): number {
    let priority = 5;
    
    if (readingSpeed === 'fast') {
      priority += 2;
    } else if (readingSpeed === 'slow') {
      priority -= 1;
    }
    
    if (forwardRatio > 0.8) {
      priority += 1;
    }
    
    if (this.isWiFi) {
      priority += 1;
    }
    
    return Math.min(10, Math.max(1, priority));
  }

  /**
   * 生成策略原因
   */
  private generateStrategyReason(readingSpeed: string, forwardRatio: number, isWiFi: boolean): string {
    const reasons: string[] = [];
    
    if (readingSpeed === 'fast') {
      reasons.push('快速阅读');
    } else if (readingSpeed === 'slow') {
      reasons.push('慢速阅读');
    }
    
    if (forwardRatio > 0.8) {
      reasons.push('主要向前翻页');
    } else if (forwardRatio < 0.5) {
      reasons.push('经常回翻');
    }
    
    if (isWiFi) {
      reasons.push('WiFi环境');
    } else {
      reasons.push('移动网络');
    }
    
    return reasons.length > 0 ? reasons.join(', ') : '标准策略';
  }

  /**
   * 获取当前策略
   */
  public getCurrentStrategy(): PreloadStrategy {
    const strategy: PreloadStrategy = {
      forwardRange: this.currentStrategy.forwardRange,
      backwardRange: this.currentStrategy.backwardRange,
      priority: this.currentStrategy.priority,
      reason: this.currentStrategy.reason
    };
    return strategy;
  }

  /**
   * 获取统计数据
   */
  public getStats(): PreloadStats {
    const avgPageDuration = this.stats.totalPages > 0 
      ? this.stats.totalDuration / this.stats.totalPages 
      : 0;
    
    const forwardRatio = this.stats.totalPages > 0
      ? this.stats.forwardPages / this.stats.totalPages
      : 0.8;
    
    const readingSpeed = this.analyzeReadingSpeed();
    
    return {
      totalPages: this.stats.totalPages,
      forwardPages: this.stats.forwardPages,
      backwardPages: this.stats.backwardPages,
      avgPageDuration,
      forwardRatio,
      readingSpeed,
      networkType: this.isWiFi ? 'WiFi' : '移动网络',
      currentStrategy: this.getCurrentStrategy()
    };
  }

  /**
   * 重置统计数据
   */
  public resetStats(): void {
    this.behaviorHistory = [];
    this.stats = {
      totalPages: 0,
      forwardPages: 0,
      backwardPages: 0,
      totalDuration: 0
    };
    this.updateStrategy();
    logger.info(TAG, '统计数据已重置');
  }

  /**
   * 添加策略更新监听器
   */
  public addListener(listener: (strategy: PreloadStrategy) => void): void {
    this.listeners.push(listener);
  }

  /**
   * 移除策略更新监听器
   */
  public removeListener(listener: (strategy: PreloadStrategy) => void): void {
    const index = this.listeners.indexOf(listener);
    if (index > -1) {
      this.listeners.splice(index, 1);
    }
  }

  /**
   * 通知所有监听器
   */
  private notifyListeners(): void {
    const strategy = this.getCurrentStrategy();
    for (const listener of this.listeners) {
      try {
        listener(strategy);
      } catch (error) {
        logger.error(TAG, `监听器执行失败: ${String(error)}`);
      }
    }
  }

  /**
   * 手动触发策略更新
   */
  public async refreshStrategy(): Promise<void> {
    await this.updateNetworkStatus();
    this.updateStrategy();
  }

  /**
   * 获取预加载范围（供MangaViewer使用）
   */
  public getPreloadRange(isWebtoon: boolean): number {
    const config = this.configManager.getPreloadConfig();
    
    if (!config.enabled) {
      return 0;
    }
    
    // 条漫模式使用配置的条漫范围
    if (isWebtoon) {
      return config.rangeWebtoon;
    }
    
    // 普通模式使用智能策略的向前范围
    return this.currentStrategy.forwardRange;
  }

  /**
   * 获取详细的预加载计划
   */
  public getPreloadPlan(currentIndex: number, totalPages: number): Array<PreloadPlanItem> {
    const plan: Array<PreloadPlanItem> = [];
    const strategy = this.currentStrategy;
    
    // 向前预加载
    for (let i = 1; i <= strategy.forwardRange; i++) {
      const index = currentIndex + i;
      if (index < totalPages) {
        const item: PreloadPlanItem = {
          index: index,
          priority: Math.max(1, 10 - i),
          direction: 'forward'
        };
        plan.push(item);
      }
    }
    
    // 向后预加载
    for (let i = 1; i <= strategy.backwardRange; i++) {
      const index = currentIndex - i;
      if (index >= 0) {
        const item: PreloadPlanItem = {
          index: index,
          priority: Math.max(1, 10 - i - 1),
          direction: 'backward'
        };
        plan.push(item);
      }
    }
    
    return plan;
  }
}
