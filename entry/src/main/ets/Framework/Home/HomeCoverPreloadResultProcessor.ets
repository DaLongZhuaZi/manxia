import { CoverPreloadResult } from '../Image/CoverImageManager';
import { HomeCoverFailureTtlCache } from './HomeCoverFailureTtlCache';

export class HomeCoverPreloadBatchSummary {
  public succeededCount: number = 0;
  public failedCount: number = 0;

  constructor(succeededCount: number, failedCount: number) {
    this.succeededCount = succeededCount;
    this.failedCount = failedCount;
  }
}

export class HomeCoverPreloadResultProcessor {
  public process(
    results: CoverPreloadResult[],
    failureKeysByUrl: Map<string, string[]>,
    failureCache: HomeCoverFailureTtlCache,
    nowMs: number = Date.now()
  ): HomeCoverPreloadBatchSummary {
    let succeededCount: number = 0;
    let failedCount: number = 0;
    for (const result of results) {
      const failureKeys: string[] | undefined = failureKeysByUrl.get(result.url);
      if (result.succeeded) {
        succeededCount++;
        if (failureKeys) {
          for (const failureKey of failureKeys) {
            failureCache.clearKey(failureKey);
          }
        }
      } else {
        failedCount++;
        if (failureKeys) {
          for (const failureKey of failureKeys) {
            failureCache.recordFailure(failureKey, '预加载未返回 PixelMap', nowMs);
          }
        }
      }
    }
    return new HomeCoverPreloadBatchSummary(succeededCount, failedCount);
  }
}
