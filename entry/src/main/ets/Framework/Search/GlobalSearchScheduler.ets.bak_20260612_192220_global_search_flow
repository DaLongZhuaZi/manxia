/**
 * 全局搜索调度器
 * 按任务类型分队列执行，统一处理并发、超时、取消检查和时间片让渡。
 */

import { logger } from '../../Utils/Logger';
import {
  GlobalSearchCancelSignal,
  GlobalSearchTaskKind,
  GlobalSearchTimeoutResult
} from './GlobalSearchSessionTypes';

const TAG = 'GlobalSearchScheduler';
const DEFAULT_YIELD_MS: number = 10;

export interface GlobalSearchSchedulerConfig {
  localConcurrency: number;
  networkConcurrency: number;
  webViewConcurrency: number;
  suwayomiConcurrency: number;
}

export interface GlobalSearchQueuedTask {
  taskId: string;
  taskName: string;
  kind: GlobalSearchTaskKind;
  run: () => Promise<void>;
}

interface GlobalSearchTaskQueues {
  local: GlobalSearchQueuedTask[];
  mangaHttp: GlobalSearchQueuedTask[];
  mangaWebView: GlobalSearchQueuedTask[];
  novel: GlobalSearchQueuedTask[];
  suwayomi: GlobalSearchQueuedTask[];
}

export class GlobalSearchScheduler {
  private config: GlobalSearchSchedulerConfig;

  constructor(config: GlobalSearchSchedulerConfig) {
    this.config = config;
  }

  async run(tasks: GlobalSearchQueuedTask[], signal: GlobalSearchCancelSignal): Promise<void> {
    const queues: GlobalSearchTaskQueues = this.classify(tasks);
    const networkTasks: GlobalSearchQueuedTask[] = [];
    for (const task of queues.mangaHttp) {
      networkTasks.push(task);
    }
    for (const task of queues.novel) {
      networkTasks.push(task);
    }

    logger.info(
      TAG,
      `搜索任务入队: local=${queues.local.length}, network=${networkTasks.length}, webView=${queues.mangaWebView.length}, suwayomi=${queues.suwayomi.length}`
    );

    await Promise.all([
      this.runQueue(queues.local, this.config.localConcurrency, signal),
      this.runQueue(networkTasks, this.config.networkConcurrency, signal),
      this.runQueue(queues.mangaWebView, this.config.webViewConcurrency, signal),
      this.runQueue(queues.suwayomi, this.config.suwayomiConcurrency, signal)
    ]);
  }

  async waitWithTimeout<T>(
    work: Promise<T>,
    timeoutMs: number,
    signal: GlobalSearchCancelSignal
  ): Promise<GlobalSearchTimeoutResult<T>> {
    return new Promise<GlobalSearchTimeoutResult<T>>((resolve) => {
      let settled: boolean = false;
      const timerId: number = setTimeout(() => {
        if (settled) {
          return;
        }
        settled = true;
        const timeoutResult: GlobalSearchTimeoutResult<T> = {
          completed: false,
          timedOut: true,
          errorMessage: `timeout ${timeoutMs}ms`
        };
        resolve(timeoutResult);
      }, timeoutMs);

      work.then((value: T) => {
        if (settled) {
          return;
        }
        settled = true;
        clearTimeout(timerId);
        if (signal.isCancelled()) {
          const cancelledResult: GlobalSearchTimeoutResult<T> = {
            completed: false,
            timedOut: false,
            errorMessage: signal.getReason()
          };
          resolve(cancelledResult);
          return;
        }
        const successResult: GlobalSearchTimeoutResult<T> = {
          completed: true,
          timedOut: false,
          value: value,
          errorMessage: ''
        };
        resolve(successResult);
      }).catch((error: Error) => {
        if (settled) {
          return;
        }
        settled = true;
        clearTimeout(timerId);
        const failureResult: GlobalSearchTimeoutResult<T> = {
          completed: false,
          timedOut: false,
          errorMessage: error instanceof Error ? error.message : String(error)
        };
        resolve(failureResult);
      });
    });
  }

  private classify(tasks: GlobalSearchQueuedTask[]): GlobalSearchTaskQueues {
    const queues: GlobalSearchTaskQueues = {
      local: [],
      mangaHttp: [],
      mangaWebView: [],
      novel: [],
      suwayomi: []
    };

    for (const task of tasks) {
      if (task.kind === GlobalSearchTaskKind.LOCAL) {
        queues.local.push(task);
      } else if (task.kind === GlobalSearchTaskKind.MANGA_HTTP) {
        queues.mangaHttp.push(task);
      } else if (task.kind === GlobalSearchTaskKind.MANGA_WEBVIEW) {
        queues.mangaWebView.push(task);
      } else if (task.kind === GlobalSearchTaskKind.NOVEL) {
        queues.novel.push(task);
      } else if (task.kind === GlobalSearchTaskKind.SUWAYOMI) {
        queues.suwayomi.push(task);
      }
    }

    return queues;
  }

  private async runQueue(
    tasks: GlobalSearchQueuedTask[],
    concurrency: number,
    signal: GlobalSearchCancelSignal
  ): Promise<void> {
    if (tasks.length === 0) {
      return;
    }
    const safeConcurrency: number = Math.max(1, concurrency);
    const executing: Promise<void>[] = [];

    for (const task of tasks) {
      if (signal.isCancelled()) {
        logger.debug(TAG, `搜索队列已取消，跳过任务: ${task.taskName}`);
        break;
      }

      await this.sleep(DEFAULT_YIELD_MS);

      const promise: Promise<void> = task.run().catch((error: Error) => {
        logger.warn(TAG, `搜索任务执行失败: ${task.taskName}, error=${String(error)}`);
      }).then(() => {
        const index: number = executing.indexOf(promise);
        if (index >= 0) {
          executing.splice(index, 1);
        }
      });
      executing.push(promise);

      if (executing.length >= safeConcurrency) {
        await Promise.race(executing);
      }
    }

    await Promise.all(executing);
  }

  private async sleep(durationMs: number): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout(resolve, durationMs);
    });
  }
}
