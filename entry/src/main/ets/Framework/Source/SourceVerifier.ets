/**
 * 书源快速可达性校验器（场景 A）
 *
 * 适用场景：批量快速探测大量书源 URL 的 HTTP 可达性
 * （区别于 NovelSourceValidator 的完整功能校验流程）
 *
 * 技术方案：
 *   - DATA_TRANSFER 后台长时任务：APP 挂起后网络请求仍可进行
 *   - @Concurrent + TaskPool：并发执行多个 HTTP 探测，不阻塞主线程
 *   - 批次控制：分批并发，避免瞬间大量连接耗尽系统资源
 *
 * 文件路径: entry/src/main/ets/Framework/Source/SourceVerifier.ets
 */

import { taskpool } from '@kit.ArkTS';
import { http } from '@kit.NetworkKit';
import { common } from '@kit.AbilityKit';
import { BackgroundTaskHelper } from '../Task/BackgroundTaskHelper';
import { logger } from '../../Utils/Logger';

const TAG = 'SourceVerifier';

// ─────────────────────────────────────────────────────────────────────────────
// TaskPool 并发任务函数（必须是顶层函数，@Concurrent 装饰）
// 限制：不能捕获外部作用域变量，所有数据通过参数传入
// ─────────────────────────────────────────────────────────────────────────────

/**
 * 单个书源 HTTP 可达性探测
 * 在独立的 TaskPool 工作线程中执行，不占用主线程
 */
@Concurrent
async function verifySingleSource(sourceUrl: string, timeout: number): Promise<boolean> {
  const httpRequest = http.createHttp();
  try {
    const response = await httpRequest.request(sourceUrl, {
      method: http.RequestMethod.GET,
      connectTimeout: timeout,
      readTimeout: timeout
    });
    // 2xx / 3xx 视为可达
    return response.responseCode >= 200 && response.responseCode < 400;
  } catch {
    return false;
  } finally {
    httpRequest.destroy();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 校验结果类型
// ─────────────────────────────────────────────────────────────────────────────

/** 单个书源校验结果 */
export interface SourceProbeResult {
  url: string;
  available: boolean;
}

/** 批量校验汇总结果 */
export interface BatchProbeResult {
  total: number;
  available: number;
  unavailable: number;
  results: SourceProbeResult[];
  durationMs: number;
}

// ─────────────────────────────────────────────────────────────────────────────
// SourceVerifier 主体
// ─────────────────────────────────────────────────────────────────────────────

/**
 * 书源快速可达性校验器
 *
 * 使用示例：
 * ```typescript
 * const result = await SourceVerifier.batchVerify(this.context, sourceUrls, {
 *   timeout: 10000,
 *   concurrency: 5,
 *   onProgress: (done, total) => console.log(`${done}/${total}`)
 * });
 * ```
 */
export class SourceVerifier {
  /**
   * 批量校验书源 HTTP 可达性
   *
   * @param context   UIAbility 上下文（用于申请后台长时任务）
   * @param sourceUrls 书源 URL 列表
   * @param options   校验选项
   * @returns 批量校验结果（含每个书源的可达状态）
   */
  static async batchVerify(
    context: common.UIAbilityContext,
    sourceUrls: string[],
    options?: {
      /** 单个请求超时（ms），默认 10 秒 */
      timeout?: number;
      /** 并发数，默认 5 */
      concurrency?: number;
      /** 进度回调：(已完成数, 总数) */
      onProgress?: (completed: number, total: number) => void;
    }
  ): Promise<BatchProbeResult> {
    const timeout = options?.timeout ?? 10000;
    const concurrency = options?.concurrency ?? 5;
    const onProgress = options?.onProgress;

    logger.info(TAG, `开始批量校验 ${sourceUrls.length} 个书源，并发数: ${concurrency}，超时: ${timeout}ms`);
    const startTime = Date.now();

    // 申请 DATA_TRANSFER 后台长时任务，APP 进入后台时网络不中断
    await BackgroundTaskHelper.startDataTransferTask(context);

    const probeResults: SourceProbeResult[] = [];
    const chunks = SourceVerifier.chunkArray(sourceUrls, concurrency);
    let completedCount = 0;

    try {
      for (const chunk of chunks) {
        // 并发执行一批探测任务，使用 TaskPool 在子线程中运行，不阻塞 UI
        const taskPromises = chunk.map(url => {
          const task = new taskpool.Task(verifySingleSource, url, timeout);
          return taskpool.execute(task);
        });

        const batchSettled = await Promise.allSettled(taskPromises);

        batchSettled.forEach((settled, idx) => {
          const url = chunk[idx];
          const available = settled.status === 'fulfilled'
            ? (settled.value as boolean)
            : false;
          probeResults.push({ url, available });
          completedCount++;
        });

        onProgress?.(completedCount, sourceUrls.length);
        logger.debug(TAG, `校验进度: ${completedCount}/${sourceUrls.length}`);
      }
    } finally {
      // 校验完成后立即停止后台长时任务，释放系统资源
      await BackgroundTaskHelper.stopDataTransferTask(context);
    }

    const availableCount = probeResults.filter(r => r.available).length;
    const durationMs = Date.now() - startTime;

    logger.info(TAG, `批量校验完成: ${availableCount}/${sourceUrls.length} 可达，耗时 ${durationMs}ms`);

    return {
      total: sourceUrls.length,
      available: availableCount,
      unavailable: sourceUrls.length - availableCount,
      results: probeResults,
      durationMs
    };
  }

  /**
   * 快速校验单个书源
   * @param sourceUrl 书源 URL
   * @param timeout   超时（ms），默认 10 秒
   */
  static async verifySingle(sourceUrl: string, timeout: number = 10000): Promise<boolean> {
    const task = new taskpool.Task(verifySingleSource, sourceUrl, timeout);
    try {
      return (await taskpool.execute(task)) as boolean;
    } catch {
      return false;
    }
  }

  // ─── 私有工具方法 ───────────────────────────────────────────────────────────

  private static chunkArray<T>(arr: T[], size: number): T[][] {
    const chunks: T[][] = [];
    for (let i = 0; i < arr.length; i += size) {
      chunks.push(arr.slice(i, i + size));
    }
    return chunks;
  }
}
