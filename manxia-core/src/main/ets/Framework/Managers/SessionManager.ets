// 文件路径: entry/src/main/ets/Framework/Managers/SessionManager.ets
/**
 * 会话管理器
 * 负责会话的自动刷新、过期检测和管理
 */

import { logger } from '../../Utils/Logger';
import CookieManager from './CookieManager';

const TAG = 'SessionManager';

/**
 * 会话刷新配置
 */
export interface SessionRefreshConfig {
  enabled: boolean;
  interval: number;
  workflow: string;
  checkExpiry: boolean;
  expiryIndicators?: ExpiryIndicator[];
}

/**
 * 过期指示器
 */
export interface ExpiryIndicator {
  type: 'cookie' | 'response' | 'time';
  name?: string;
  statusCode?: number;
  maxAge?: number;
}

/**
 * 会话状态
 */
export interface SessionState {
  sourceId: number;
  isActive: boolean;
  lastRefreshTime: number;
  nextRefreshTime: number;
  refreshCount: number;
  failureCount: number;
}

/**
 * 会话管理器（单例）
 */
export class SessionManager {
  private static instance: SessionManager | null = null;
  
  // 刷新定时器
  private refreshTimers: Map<number, number> = new Map();
  
  // 会话状态
  private sessionStates: Map<number, SessionState> = new Map();
  
  // 刷新回调函数
  private refreshCallbacks: Map<number, () => Promise<void>> = new Map();

  private constructor() {}

  static getInstance(): SessionManager {
    if (!SessionManager.instance) {
      SessionManager.instance = new SessionManager();
    }
    return SessionManager.instance;
  }

  /**
   * 启动会话自动刷新
   */
  async startSessionRefresh(
    sourceId: number,
    config: SessionRefreshConfig,
    refreshCallback: () => Promise<void>
  ): Promise<void> {
    if (!config.enabled) {
      logger.info(TAG, `会话自动刷新未启用: sourceId=${sourceId}`);
      return;
    }

    // 停止已存在的刷新任务
    this.stopSessionRefresh(sourceId);

    // 保存刷新回调
    this.refreshCallbacks.set(sourceId, refreshCallback);

    // 初始化会话状态
    const now = Date.now();
    const state: SessionState = {
      sourceId: sourceId,
      isActive: true,
      lastRefreshTime: now,
      nextRefreshTime: now + config.interval,
      refreshCount: 0,
      failureCount: 0
    };
    this.sessionStates.set(sourceId, state);

    // 设置定时刷新
    const timerId = setInterval(async () => {
      await this.performRefresh(sourceId, config);
    }, config.interval);

    this.refreshTimers.set(sourceId, timerId);

    logger.info(TAG, `启动会话自动刷新: sourceId=${sourceId}, interval=${config.interval}ms`);
  }

  /**
   * 停止会话刷新
   */
  stopSessionRefresh(sourceId: number): void {
    const timerId = this.refreshTimers.get(sourceId);
    if (timerId) {
      clearInterval(timerId);
      this.refreshTimers.delete(sourceId);
      logger.info(TAG, `停止会话刷新: sourceId=${sourceId}`);
    }

    // 更新状态
    const state = this.sessionStates.get(sourceId);
    if (state) {
      state.isActive = false;
    }
  }

  /**
   * 执行刷新
   */
  private async performRefresh(sourceId: number, config: SessionRefreshConfig): Promise<void> {
    const state = this.sessionStates.get(sourceId);
    if (!state) {
      logger.warn(TAG, `会话状态不存在: sourceId=${sourceId}`);
      return;
    }

    try {
      logger.info(TAG, `开始刷新会话: sourceId=${sourceId}, count=${state.refreshCount + 1}`);

      // 检查会话是否过期
      if (config.checkExpiry) {
        const isExpired = await this.isSessionExpired(sourceId, config.expiryIndicators || []);
        if (!isExpired) {
          logger.debug(TAG, `会话未过期，跳过刷新: sourceId=${sourceId}`);
          return;
        }
      }

      // 执行刷新回调
      const refreshCallback = this.refreshCallbacks.get(sourceId);
      if (refreshCallback) {
        await refreshCallback();
      }

      // 更新状态
      const now = Date.now();
      state.lastRefreshTime = now;
      state.nextRefreshTime = now + config.interval;
      state.refreshCount++;
      state.failureCount = 0;

      logger.info(TAG, `会话刷新成功: sourceId=${sourceId}, count=${state.refreshCount}`);
    } catch (error) {
      state.failureCount++;
      logger.error(TAG, `会话刷新失败: sourceId=${sourceId}, error=${error}, failures=${state.failureCount}`);

      // 如果连续失败次数过多，停止刷新
      if (state.failureCount >= 3) {
        logger.error(TAG, `会话刷新连续失败${state.failureCount}次，停止自动刷新: sourceId=${sourceId}`);
        this.stopSessionRefresh(sourceId);
      }
    }
  }

  /**
   * 手动刷新会话
   */
  async manualRefresh(sourceId: number): Promise<boolean> {
    const refreshCallback = this.refreshCallbacks.get(sourceId);
    if (!refreshCallback) {
      logger.warn(TAG, `未找到刷新回调: sourceId=${sourceId}`);
      return false;
    }

    try {
      await refreshCallback();
      
      // 更新状态
      const state = this.sessionStates.get(sourceId);
      if (state) {
        state.lastRefreshTime = Date.now();
        state.refreshCount++;
        state.failureCount = 0;
      }

      logger.info(TAG, `手动刷新会话成功: sourceId=${sourceId}`);
      return true;
    } catch (error) {
      logger.error(TAG, `手动刷新会话失败: sourceId=${sourceId}, error=${error}`);
      return false;
    }
  }

  /**
   * 检查会话是否过期
   */
  async isSessionExpired(sourceId: number, indicators: ExpiryIndicator[]): Promise<boolean> {
    if (!indicators || indicators.length === 0) {
      return false;
    }

    for (const indicator of indicators) {
      switch (indicator.type) {
        case 'cookie':
          const hasCookie = await this.checkCookieExpiry(sourceId, indicator);
          if (!hasCookie) {
            logger.info(TAG, `Cookie已过期: sourceId=${sourceId}, name=${indicator.name}`);
            return true;
          }
          break;

        case 'time':
          const isTimeExpired = this.checkTimeExpiry(sourceId, indicator);
          if (isTimeExpired) {
            logger.info(TAG, `会话时间已过期: sourceId=${sourceId}`);
            return true;
          }
          break;

        case 'response':
          // 响应状态码检查需要在实际请求时进行
          break;
      }
    }

    return false;
  }

  /**
   * 检查Cookie是否过期
   */
  private async checkCookieExpiry(sourceId: number, indicator: ExpiryIndicator): Promise<boolean> {
    try {
      const cookieManager = CookieManager.getInstance();
      const cookieInfo = await cookieManager.getCookieInfo(sourceId);
      
      if (!cookieInfo.hasCookie) {
        return false;
      }

      // 如果指定了Cookie名称，检查特定Cookie
      if (indicator.name) {
        const cookieString = await cookieManager.getCookieString(sourceId);
        return cookieString.includes(indicator.name);
      }

      return true;
    } catch (error) {
      logger.error(TAG, `检查Cookie过期失败: ${error}`);
      return false;
    }
  }

  /**
   * 检查时间是否过期
   */
  private checkTimeExpiry(sourceId: number, indicator: ExpiryIndicator): boolean {
    const state = this.sessionStates.get(sourceId);
    if (!state || !indicator.maxAge) {
      return false;
    }

    const now = Date.now();
    const age = now - state.lastRefreshTime;
    
    return age > indicator.maxAge;
  }

  /**
   * 获取会话状态
   */
  getSessionState(sourceId: number): SessionState | null {
    return this.sessionStates.get(sourceId) || null;
  }

  /**
   * 获取所有活跃会话
   */
  getActiveSessions(): SessionState[] {
    const sessions: SessionState[] = [];
    this.sessionStates.forEach(state => {
      if (state.isActive) {
        sessions.push(state);
      }
    });
    return sessions;
  }

  /**
   * 是否正在刷新
   */
  isRefreshing(sourceId: number): boolean {
    return this.refreshTimers.has(sourceId);
  }

  /**
   * 获取下次刷新时间
   */
  getNextRefreshTime(sourceId: number): number | null {
    const state = this.sessionStates.get(sourceId);
    return state ? state.nextRefreshTime : null;
  }

  /**
   * 获取刷新统计
   */
  getRefreshStatistics(sourceId: number): string {
    const state = this.sessionStates.get(sourceId);
    if (!state) {
      return '无会话状态';
    }

    const lastRefresh = new Date(state.lastRefreshTime).toLocaleString();
    const nextRefresh = new Date(state.nextRefreshTime).toLocaleString();
    
    return `活跃: ${state.isActive}, 刷新次数: ${state.refreshCount}, 失败次数: ${state.failureCount}, 上次刷新: ${lastRefresh}, 下次刷新: ${nextRefresh}`;
  }

  /**
   * 停止所有会话刷新
   */
  stopAll(): void {
    this.refreshTimers.forEach((timerId, sourceId) => {
      clearInterval(timerId);
      logger.info(TAG, `停止会话刷新: sourceId=${sourceId}`);
    });
    
    this.refreshTimers.clear();
    this.sessionStates.forEach(state => {
      state.isActive = false;
    });
    
    logger.info(TAG, '停止所有会话刷新');
  }

  /**
   * 清理过期状态
   */
  cleanup(): void {
    const now = Date.now();
    const expiredSources: number[] = [];

    this.sessionStates.forEach((state, sourceId) => {
      // 清理超过24小时未刷新的非活跃会话
      if (!state.isActive && (now - state.lastRefreshTime) > 24 * 60 * 60 * 1000) {
        expiredSources.push(sourceId);
      }
    });

    expiredSources.forEach(sourceId => {
      this.sessionStates.delete(sourceId);
      this.refreshCallbacks.delete(sourceId);
    });

    if (expiredSources.length > 0) {
      logger.info(TAG, `清理过期会话状态: ${expiredSources.length}个`);
    }
  }
}

export default SessionManager;
