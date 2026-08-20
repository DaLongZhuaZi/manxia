/**
 * 页面生命周期管理器
 * 
 * 职责：
 * 1. 统一管理页面内的所有定时器（setTimeout/setInterval）
 * 2. 管理可取消的 Promise 操作
 * 3. 管理需要释放的资源（Disposable）
 * 4. 管理事件监听器
 * 5. 在页面销毁时自动清理所有资源
 * 
 * 使用方式：
 * ```typescript
 * class MyPage {
 *   private lifecycle = new PageLifecycleManager('MyPage')
 *   
 *   someMethod() {
 *     // 使用托管的定时器
 *     this.lifecycle.setTimeout(() => {...}, 1000)
 *     
 *     // 使用可取消的 Promise
 *     const promise = this.lifecycle.registerPromise(fetchData())
 *     
 *     // 注册资源
 *     this.lifecycle.registerResource(myResource)
 *   }
 *   
 *   aboutToDisappear() {
 *     this.lifecycle.destroy() // 自动清理所有资源
 *   }
 * }
 * ```
 * 
 * 文件路径: entry/src/main/ets/Framework/Lifecycle/PageLifecycleManager.ets
 */

import { logger } from '../../Utils/Logger';
import { CancellablePromise } from './CancellablePromise';
import { GlobalTaskCoordinator, PageStats } from './GlobalTaskCoordinator';

const TAG = 'PageLifecycleManager';

/**
 * 可释放资源接口
 */
export interface Disposable {
  dispose(): void | Promise<void>;
}

/**
 * 定时器信息
 */
interface TimerInfo {
  id: number;
  type: 'timeout' | 'interval';
  callback: Function;
  delay: number;
  createTime: number;
  createStack?: string;
}

/**
 * 事件监听器信息
 */
interface ListenerInfo {
  target: ESObject;
  event: string;
  handler: Function;
  createTime: number;
}

/**
 * 页面生命周期管理器配置
 */
export interface LifecycleManagerConfig {
  enableDebug?: boolean;           // 是否启用调试日志
  enableStackTrace?: boolean;       // 是否记录调用栈（性能影响）
  maxTimers?: number;               // 最大定时器数量（防止泄漏）
  maxPromises?: number;             // 最大 Promise 数量
  warnThreshold?: number;           // 资源数量警告阈值
}

/**
 * 页面生命周期管理器
 */
export class PageLifecycleManager {
  private pageId: string;
  private config: Required<LifecycleManagerConfig>;
  
  // 定时器管理
  private timers: Map<number, TimerInfo> = new Map();
  private timerIdCounter: number = 0;
  
  // Promise 管理
  private promises: Set<CancellablePromise<ESObject>> = new Set();
  
  // 资源管理
  private resources: Set<Disposable> = new Set();
  
  // 事件监听器管理
  private listeners: ListenerInfo[] = [];
  
  // 销毁回调
  private destroyCallbacks: Array<() => void> = [];
  
  // 状态
  private isDestroyed: boolean = false;
  private createTime: number = Date.now();
  
  /**
   * 构造函数
   * @param pageId 页面唯一标识符
   * @param config 配置选项
   */
  constructor(pageId: string, config?: LifecycleManagerConfig) {
    this.pageId = pageId;
    this.config = {
      enableDebug: config?.enableDebug ?? false,
      enableStackTrace: config?.enableStackTrace ?? false,
      maxTimers: config?.maxTimers ?? 100,
      maxPromises: config?.maxPromises ?? 50,
      warnThreshold: config?.warnThreshold ?? 20
    };
    
    // 注册到全局协调器
    GlobalTaskCoordinator.getInstance().registerPage(pageId, this);
    
    if (this.config.enableDebug) {
      logger.info(TAG, `[${this.pageId}] 生命周期管理器已创建`);
    }
  }
  
  /**
   * 托管的 setTimeout
   * @param callback 回调函数
   * @param delay 延迟时间（毫秒）
   * @returns 定时器 ID
   */
  setTimeout(callback: Function, delay: number = 0): number {
    this.checkDestroyed('setTimeout');
    this.checkTimerLimit();
    
    const timerId = ++this.timerIdCounter;
    const actualTimerId = setTimeout(() => {
      this.timers.delete(timerId);
      if (!this.isDestroyed) {
        try {
          callback();
        } catch (error) {
          logger.error(TAG, `[${this.pageId}] setTimeout 回调执行失败: ${error}`);
        }
      }
    }, delay);
    
    const timerInfo: TimerInfo = {
      id: actualTimerId as number,
      type: 'timeout',
      callback,
      delay,
      createTime: Date.now(),
      createStack: this.config.enableStackTrace ? this.captureStack() : undefined
    };
    
    this.timers.set(timerId, timerInfo);
    
    if (this.config.enableDebug) {
      logger.debug(TAG, `[${this.pageId}] setTimeout 已注册: id=${timerId}, delay=${delay}ms`);
    }
    
    return timerId;
  }
  
  /**
   * 托管的 setInterval
   * @param callback 回调函数
   * @param delay 间隔时间（毫秒）
   * @returns 定时器 ID
   */
  setInterval(callback: Function, delay: number): number {
    this.checkDestroyed('setInterval');
    this.checkTimerLimit();
    
    const timerId = ++this.timerIdCounter;
    const actualTimerId = setInterval(() => {
      if (!this.isDestroyed) {
        try {
          callback();
        } catch (error) {
          logger.error(TAG, `[${this.pageId}] setInterval 回调执行失败: ${error}`);
        }
      }
    }, delay);
    
    const timerInfo: TimerInfo = {
      id: actualTimerId as number,
      type: 'interval',
      callback,
      delay,
      createTime: Date.now(),
      createStack: this.config.enableStackTrace ? this.captureStack() : undefined
    };
    
    this.timers.set(timerId, timerInfo);
    
    if (this.config.enableDebug) {
      logger.debug(TAG, `[${this.pageId}] setInterval 已注册: id=${timerId}, delay=${delay}ms`);
    }
    
    return timerId;
  }
  
  /**
   * 清除 setTimeout
   * @param timerId 定时器 ID
   */
  clearTimeout(timerId: number): void {
    const timerInfo = this.timers.get(timerId);
    if (timerInfo) {
      clearTimeout(timerInfo.id);
      this.timers.delete(timerId);
      
      if (this.config.enableDebug) {
        logger.debug(TAG, `[${this.pageId}] clearTimeout: id=${timerId}`);
      }
    }
  }
  
  /**
   * 清除 setInterval
   * @param timerId 定时器 ID
   */
  clearInterval(timerId: number): void {
    const timerInfo = this.timers.get(timerId);
    if (timerInfo) {
      clearInterval(timerInfo.id);
      this.timers.delete(timerId);
      
      if (this.config.enableDebug) {
        logger.debug(TAG, `[${this.pageId}] clearInterval: id=${timerId}`);
      }
    }
  }
  
  /**
   * 注册可取消的 Promise
   * @param promise 原始 Promise
   * @returns 可取消的 Promise
   */
  registerPromise<T>(promise: Promise<T>): CancellablePromise<T> {
    this.checkDestroyed('registerPromise');
    this.checkPromiseLimit();
    
    const cancellable = new CancellablePromise<T>((resolve, reject, signal) => {
      promise.then(
        value => {
          if (!signal.aborted) {
            resolve(value);
          }
        },
        (error: ESObject) => {
          if (!signal.aborted) {
            reject(error);
          }
        }
      );
    });
    
    this.promises.add(cancellable);
    
    // Promise 完成后自动移除
    cancellable.finally(() => {
      this.promises.delete(cancellable);
    });
    
    if (this.config.enableDebug) {
      logger.debug(TAG, `[${this.pageId}] Promise 已注册, 当前数量: ${this.promises.size}`);
    }
    
    return cancellable;
  }
  
  /**
   * 注册需要释放的资源
   * @param resource 可释放资源
   */
  registerResource(resource: Disposable): void {
    this.checkDestroyed('registerResource');
    this.resources.add(resource);
    
    if (this.config.enableDebug) {
      logger.debug(TAG, `[${this.pageId}] 资源已注册, 当前数量: ${this.resources.size}`);
    }
  }
  
  /**
   * 取消注册资源
   * @param resource 可释放资源
   */
  unregisterResource(resource: Disposable): void {
    this.resources.delete(resource);
  }
  
  /**
   * 添加事件监听器（自动管理）
   * @param target 目标对象
   * @param event 事件名称
   * @param handler 处理函数
   */
  addEventListener(target: ESObject, event: string, handler: Function): void {
    this.checkDestroyed('addEventListener');
    
    if (target && typeof target.addEventListener === 'function') {
      target.addEventListener(event, handler);
      
      this.listeners.push({
        target,
        event,
        handler,
        createTime: Date.now()
      });
      
      if (this.config.enableDebug) {
        logger.debug(TAG, `[${this.pageId}] 事件监听器已添加: ${event}`);
      }
    } else {
      logger.warn(TAG, `[${this.pageId}] 目标对象不支持 addEventListener`);
    }
  }
  
  /**
   * 移除事件监听器
   * @param target 目标对象
   * @param event 事件名称
   * @param handler 处理函数
   */
  removeEventListener(target: ESObject, event: string, handler: Function): void {
    const index = this.listeners.findIndex(
      l => l.target === target && l.event === event && l.handler === handler
    );
    
    if (index !== -1) {
      const listener = this.listeners[index];
      if (listener.target && typeof listener.target.removeEventListener === 'function') {
        listener.target.removeEventListener(listener.event, listener.handler);
      }
      this.listeners.splice(index, 1);
      
      if (this.config.enableDebug) {
        logger.debug(TAG, `[${this.pageId}] 事件监听器已移除: ${event}`);
      }
    }
  }
  
  /**
   * 注册销毁回调
   * @param callback 回调函数
   */
  onDestroy(callback: () => void): void {
    this.checkDestroyed('onDestroy');
    this.destroyCallbacks.push(callback);
  }
  
  /**
   * 销毁管理器，清理所有资源
   */
  async destroy(): Promise<void> {
    if (this.isDestroyed) {
      logger.warn(TAG, `[${this.pageId}] 重复调用 destroy()`);
      return;
    }
    
    this.isDestroyed = true;
    const startTime = Date.now();
    
    logger.info(TAG, `[${this.pageId}] 开始清理资源...`);
    
    // 1. 清理所有定时器
    const timerCount = this.timers.size;
    this.timers.forEach((timerInfo, timerId) => {
      if (timerInfo.type === 'timeout') {
        clearTimeout(timerInfo.id);
      } else {
        clearInterval(timerInfo.id);
      }
    });
    this.timers.clear();
    
    if (timerCount > 0) {
      logger.info(TAG, `[${this.pageId}] 已清理 ${timerCount} 个定时器`);
    }
    
    // 2. 取消所有 Promise
    const promiseCount = this.promises.size;
    this.promises.forEach((promise: CancellablePromise<ESObject>) => {
      promise.cancel('页面销毁');
    });
    this.promises.clear();
    
    if (promiseCount > 0) {
      logger.info(TAG, `[${this.pageId}] 已取消 ${promiseCount} 个 Promise`);
    }
    
    // 3. 释放所有资源
    const resourceCount = this.resources.size;
    const disposePromises: Promise<void>[] = [];
    
    this.resources.forEach(resource => {
      try {
        const result = resource.dispose();
        if (result instanceof Promise) {
          disposePromises.push(result);
        }
      } catch (error) {
        logger.error(TAG, `[${this.pageId}] 资源释放失败: ${error}`);
      }
    });
    
    if (disposePromises.length > 0) {
      await Promise.allSettled(disposePromises);
    }
    this.resources.clear();
    
    if (resourceCount > 0) {
      logger.info(TAG, `[${this.pageId}] 已释放 ${resourceCount} 个资源`);
    }
    
    // 4. 移除所有事件监听器
    const listenerCount = this.listeners.length;
    this.listeners.forEach(listener => {
      try {
        if (listener.target && typeof listener.target.removeEventListener === 'function') {
          listener.target.removeEventListener(listener.event, listener.handler);
        }
      } catch (error) {
        logger.error(TAG, `[${this.pageId}] 移除事件监听器失败: ${error}`);
      }
    });
    this.listeners = [];
    
    if (listenerCount > 0) {
      logger.info(TAG, `[${this.pageId}] 已移除 ${listenerCount} 个事件监听器`);
    }
    
    // 5. 执行销毁回调
    const callbackCount = this.destroyCallbacks.length;
    this.destroyCallbacks.forEach(callback => {
      try {
        callback();
      } catch (error) {
        logger.error(TAG, `[${this.pageId}] 销毁回调执行失败: ${error}`);
      }
    });
    this.destroyCallbacks = [];
    
    // 6. 从全局协调器注销
    GlobalTaskCoordinator.getInstance().unregisterPage(this.pageId);
    
    const duration = Date.now() - startTime;
    logger.info(TAG, `[${this.pageId}] 资源清理完成, 耗时: ${duration}ms`);
  }
  
  /**
   * 获取当前状态统计
   */
  getStats(): PageStats {
    const stats: PageStats = {
      pageId: this.pageId,
      timerCount: this.timers.size,
      promiseCount: this.promises.size,
      resourceCount: this.resources.size,
      listenerCount: this.listeners.length,
      uptime: Date.now() - this.createTime
    };
    return stats;
  }
  
  /**
   * 导出详细信息（用于调试）
   */
  dumpInfo(): string {
    const stats = this.getStats();
    const lines: string[] = [
      `=== PageLifecycleManager [${this.pageId}] ===`,
      `状态: ${this.isDestroyed ? '已销毁' : '活跃'}`,
      `运行时间: ${stats.uptime}ms`,
      `定时器: ${stats.timerCount}`,
      `Promise: ${stats.promiseCount}`,
      `资源: ${stats.resourceCount}`,
      `监听器: ${stats.listenerCount}`,
      ''
    ];
    
    if (this.timers.size > 0) {
      lines.push('定时器详情:');
      this.timers.forEach((timer, id) => {
        const age = Date.now() - timer.createTime;
        lines.push(`  - ID=${id}, 类型=${timer.type}, 延迟=${timer.delay}ms, 存活=${age}ms`);
      });
      lines.push('');
    }
    
    return lines.join('\n');
  }
  
  // ========== 私有辅助方法 ==========
  
  private checkDestroyed(method: string): void {
    if (this.isDestroyed) {
      throw new Error(`[${this.pageId}] 生命周期管理器已销毁，无法调用 ${method}()`);
    }
  }
  
  private checkTimerLimit(): void {
    if (this.timers.size >= this.config.maxTimers) {
      logger.error(TAG, `[${this.pageId}] 定时器数量超过限制: ${this.timers.size}/${this.config.maxTimers}`);
      throw new Error(`定时器数量超过限制: ${this.config.maxTimers}`);
    }
    
    if (this.timers.size >= this.config.warnThreshold) {
      logger.warn(TAG, `[${this.pageId}] 定时器数量较多: ${this.timers.size}`);
    }
  }
  
  private checkPromiseLimit(): void {
    if (this.promises.size >= this.config.maxPromises) {
      logger.error(TAG, `[${this.pageId}] Promise 数量超过限制: ${this.promises.size}/${this.config.maxPromises}`);
      throw new Error(`Promise 数量超过限制: ${this.config.maxPromises}`);
    }
    
    if (this.promises.size >= this.config.warnThreshold) {
      logger.warn(TAG, `[${this.pageId}] Promise 数量较多: ${this.promises.size}`);
    }
  }
  
  private captureStack(): string {
    try {
      throw new Error();
    } catch (e) {
      return (e as Error).stack || '';
    }
  }
}
