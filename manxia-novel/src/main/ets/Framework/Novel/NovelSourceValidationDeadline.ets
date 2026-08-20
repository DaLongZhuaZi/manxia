import {
  LegadoExecutionCancellationToken,
  createLegadoExecutionCancelledError
} from './LegadoExecutionCancellation';

const MAX_TIMER_DELAY_MS: number = 2147483647;

export type NovelSourceValidationTaskFactory = () => Promise<void>;

function normalizeValidationTimeout(timeoutMs: number): number {
  if (!Number.isFinite(timeoutMs) || timeoutMs <= 0) {
    return 1;
  }
  return Math.min(Math.floor(timeoutMs), MAX_TIMER_DELAY_MS);
}

/**
 * Runs one source validation behind a real cancellation boundary.
 *
 * The deadline is installed before the task starts, so a timeout can cancel
 * the same token used by the HTTP or ArkWeb transport. All listeners and
 * timers are released before the returned promise settles.
 */
export async function awaitNovelSourceValidationTask(
  taskFactory: NovelSourceValidationTaskFactory,
  timeoutMs: number,
  cancellationToken: LegadoExecutionCancellationToken,
  timeoutReason: string
): Promise<void> {
  let timerId: number = -1;
  let listenerId: number = 0;
  let settled: boolean = false;

  const clearResources = (): void => {
    if (timerId !== -1) {
      clearTimeout(timerId);
      timerId = -1;
    }
    if (listenerId > 0) {
      cancellationToken.unregister(listenerId);
      listenerId = 0;
    }
  };

  try {
    await new Promise<void>((resolve: () => void, reject: (error: Error) => void): void => {
      const finish = (error: Error | null): void => {
        if (settled) {
          return;
        }
        settled = true;
        clearResources();
        if (error === null) {
          resolve();
        } else {
          reject(error);
        }
      };

      listenerId = cancellationToken.register((reason: string): void => {
        finish(createLegadoExecutionCancelledError(reason));
      });
      if (settled) {
        return;
      }

      timerId = setTimeout((): void => {
        cancellationToken.cancel(timeoutReason);
      }, normalizeValidationTimeout(timeoutMs));

      let task: Promise<void>;
      try {
        task = taskFactory();
      } catch (error) {
        finish(new Error(String(error)));
        return;
      }
      task.then((): void => {
        finish(null);
      }).catch((error: Error): void => {
        finish(error);
      });
    });
  } finally {
    clearResources();
  }
}
