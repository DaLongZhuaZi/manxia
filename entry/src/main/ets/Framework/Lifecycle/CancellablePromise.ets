/**
 * 可取消的 Promise 包装器
 * 
 * 提供标准 Promise 的所有功能，同时支持取消操作
 * 
 * 使用方式：
 * ```typescript
 * const promise = new CancellablePromise((resolve, reject, signal) => {
 *   const timerId = setTimeout(() => {
 *     if (!signal.aborted) {
 *       resolve('完成')
 *     }
 *   }, 1000)
 *   
 *   signal.addEventListener('abort', () => {
 *     clearTimeout(timerId)
 *     reject(new Error('已取消'))
 *   })
 * })
 * 
 * // 取消操作
 * promise.cancel('用户取消')
 * ```
 * 
 * 文件路径: entry/src/main/ets/Framework/Lifecycle/CancellablePromise.ets
 */

import { logger } from '../../Utils/Logger';

const TAG = 'CancellablePromise';

/**
 * 取消原因
 */
export class CancellationError extends Error {
  constructor(reason: string = '操作已取消') {
    super(reason);
    this.name = 'CancellationError';
  }
}

/**
 * AbortSignal 简化实现
 */
class SimpleAbortSignal {
  private _aborted: boolean = false;
  private _reason: string = '';
  private listeners: Array<() => void> = [];
  
  get aborted(): boolean {
    return this._aborted;
  }
  
  get reason(): string {
    return this._reason;
  }
  
  addEventListener(type: string, listener: () => void): void {
    if (type === 'abort') {
      this.listeners.push(listener);
    }
  }
  
  removeEventListener(type: string, listener: () => void): void {
    if (type === 'abort') {
      const index = this.listeners.indexOf(listener);
      if (index !== -1) {
        this.listeners.splice(index, 1);
      }
    }
  }
  
  abort(reason: string): void {
    if (this._aborted) return;
    
    this._aborted = true;
    this._reason = reason;
    
    // 触发所有监听器
    this.listeners.forEach(listener => {
      try {
        listener();
      } catch (error) {
        logger.error(TAG, `abort 监听器执行失败: ${error}`);
      }
    });
  }
}

/**
 * 可取消的 Promise 执行器
 */
export type CancellableExecutor<T> = (
  resolve: (value: T | PromiseLike<T>) => void,
  reject: (reason?: ESObject) => void,
  signal: SimpleAbortSignal
) => void;

/**
 * 可取消的 Promise
 */
export class CancellablePromise<T> implements PromiseLike<T> {
  private promise: Promise<T>;
  private signal: SimpleAbortSignal;
  private _isCancelled: boolean = false;
  private _cancelReason: string = '';
  
  /**
   * 构造函数
   * @param executor 执行器函数
   */
  constructor(executor: CancellableExecutor<T>) {
    this.signal = new SimpleAbortSignal();
    
    this.promise = new Promise<T>((resolve, reject) => {
      // 如果已经取消，直接拒绝
      if (this.signal.aborted) {
        reject(new CancellationError(this.signal.reason));
        return;
      }
      
      try {
        executor(resolve, reject, this.signal);
      } catch (error) {
        reject(error);
      }
    });
  }
  
  /**
   * 取消 Promise
   * @param reason 取消原因
   */
  cancel(reason: string = '操作已取消'): void {
    if (this._isCancelled) {
      return;
    }
    
    this._isCancelled = true;
    this._cancelReason = reason;
    this.signal.abort(reason);
  }
  
  /**
   * 检查是否已取消
   */
  isCancelled(): boolean {
    return this._isCancelled;
  }
  
  /**
   * 获取取消原因
   */
  getCancelReason(): string {
    return this._cancelReason;
  }
  
  /**
   * then 方法
   */
  then<TResult1 = T, TResult2 = never>(
    onfulfilled?: ((value: T) => TResult1 | PromiseLike<TResult1>) | null,
    onrejected?: ((reason: ESObject) => TResult2 | PromiseLike<TResult2>) | null
  ): CancellablePromise<TResult1 | TResult2> {
    return new CancellablePromise<TResult1 | TResult2>((resolve, reject, signal) => {
      // 如果当前 Promise 被取消，新 Promise 也应该被取消
      if (this._isCancelled) {
        signal.abort(this._cancelReason);
        reject(new CancellationError(this._cancelReason));
        return;
      }
      
      // 监听当前 Promise 的取消事件
      this.signal.addEventListener('abort', () => {
        signal.abort(this.signal.reason);
        reject(new CancellationError(this.signal.reason));
      });
      
      this.promise.then(
        value => {
          if (!signal.aborted) {
            try {
              if (onfulfilled) {
                const result = onfulfilled(value);
                resolve(result);
              } else {
                resolve(value as TResult1 | PromiseLike<TResult1>);
              }
            } catch (error) {
              reject(error);
            }
          }
        },
        (reason: ESObject) => {
          if (!signal.aborted) {
            try {
              if (onrejected) {
                const result = onrejected(reason);
                resolve(result);
              } else {
                reject(reason);
              }
            } catch (error) {
              reject(error as ESObject);
            }
          }
        }
      );
    });
  }
  
  /**
   * catch 方法
   */
  catch<TResult = never>(
    onrejected?: ((reason: ESObject) => TResult | PromiseLike<TResult>) | null
  ): CancellablePromise<T | TResult> {
    return this.then(null, onrejected);
  }
  
  /**
   * finally 方法
   */
  finally(onfinally?: (() => void) | null): CancellablePromise<T> {
    return new CancellablePromise<T>((resolve, reject, signal) => {
      if (this._isCancelled) {
        signal.abort(this._cancelReason);
        reject(new CancellationError(this._cancelReason));
        return;
      }
      
      this.signal.addEventListener('abort', () => {
        signal.abort(this.signal.reason);
        reject(new CancellationError(this.signal.reason));
      });
      
      this.promise.finally(onfinally as (() => void)).then(resolve, reject);
    });
  }
  
  /**
   * 将普通 Promise 包装为 CancellablePromise
   */
  static from<T>(promise: Promise<T>): CancellablePromise<T> {
    return new CancellablePromise<T>((resolve, reject, signal) => {
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
  }
  
  /**
   * 创建已解决的 CancellablePromise
   */
  static resolve<T>(value: T): CancellablePromise<T> {
    return new CancellablePromise<T>((resolve) => {
      resolve(value);
    });
  }
  
  /**
   * 创建已拒绝的 CancellablePromise
   */
  static reject<T = never>(reason?: ESObject): CancellablePromise<T> {
    return new CancellablePromise<T>((_, reject) => {
      reject(reason);
    });
  }
  
  /**
   * 等待所有 Promise 完成（支持取消）
   */
  static all<T>(promises: CancellablePromise<T>[]): CancellablePromise<T[]> {
    return new CancellablePromise<T[]>((resolve, reject, signal) => {
      // 如果信号已中止，直接拒绝
      if (signal.aborted) {
        reject(new CancellationError(signal.reason));
        return;
      }
      
      // 监听取消事件
      signal.addEventListener('abort', () => {
        // 取消所有子 Promise
        promises.forEach(p => p.cancel(signal.reason));
        reject(new CancellationError(signal.reason));
      });
      
      // 执行所有 Promise
      Promise.all(promises.map(p => p.promise))
        .then(values => {
          if (!signal.aborted) {
            resolve(values);
          }
        })
        .catch((error: ESObject) => {
          if (!signal.aborted) {
            reject(error);
          }
        });
    });
  }
  
  /**
   * 等待任一 Promise 完成（支持取消）
   */
  static race<T>(promises: Array<CancellablePromise<T>>): CancellablePromise<T> {
    return new CancellablePromise<T>((resolve, reject, signal) => {
      if (signal.aborted) {
        reject(new CancellationError(signal.reason));
        return;
      }
      
      signal.addEventListener('abort', () => {
        promises.forEach(p => p.cancel(signal.reason));
        reject(new CancellationError(signal.reason));
      });
      
      Promise.race(promises.map(p => p.promise))
        .then(value => {
          if (!signal.aborted) {
            resolve(value);
          }
        })
        .catch((error: ESObject) => {
          if (!signal.aborted) {
            reject(error);
          }
        });
    });
  }
  
  /**
   * 创建带超时的 CancellablePromise
   */
  static withTimeout<T>(
    promise: CancellablePromise<T>,
    timeoutMs: number,
    timeoutMessage: string = '操作超时'
  ): CancellablePromise<T> {
    return new CancellablePromise<T>((resolve, reject, signal) => {
      const timerId = setTimeout(() => {
        promise.cancel(timeoutMessage);
        reject(new Error(timeoutMessage));
      }, timeoutMs);
      
      signal.addEventListener('abort', () => {
        clearTimeout(timerId);
        promise.cancel(signal.reason);
      });
      
      promise.then(
        value => {
          clearTimeout(timerId);
          if (!signal.aborted) {
            resolve(value);
          }
        },
        (error: ESObject) => {
          clearTimeout(timerId);
          if (!signal.aborted) {
            reject(error);
          }
        }
      );
    });
  }
  
  /**
   * 延迟执行（可取消）
   */
  static delay(ms: number): CancellablePromise<void> {
    return new CancellablePromise<void>((resolve, reject, signal) => {
      const timerId = setTimeout(() => {
        if (!signal.aborted) {
          resolve();
        }
      }, ms);
      
      signal.addEventListener('abort', () => {
        clearTimeout(timerId);
        reject(new CancellationError(signal.reason));
      });
    });
  }
}
