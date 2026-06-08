import { logger } from '../../Utils/Logger';
import {
  MangaAssetLoadReason,
  MangaAssetLoadRequest,
  MangaAssetLoadResult,
  MangaAssetLoadSource
} from './MangaAssetTypes';

const TAG = 'MangaAssetMonitor';
const MAX_RECENT_SAMPLES: number = 80;

export class MangaAssetLoadSample {
  public requestKey: string = '';
  public pageId: string = '';
  public chapterId: string = '';
  public pageIndex: number = -1;
  public reason: MangaAssetLoadReason = MangaAssetLoadReason.PRELOAD;
  public source: MangaAssetLoadSource = MangaAssetLoadSource.UNSUPPORTED;
  public success: boolean = false;
  public elapsedMs: number = 0;
  public deduped: boolean = false;
  public errorMessage: string = '';
  public timestamp: number = 0;
}

export class MangaAssetMetricsSnapshot {
  public totalRequests: number = 0;
  public completedRequests: number = 0;
  public failedRequests: number = 0;
  public dedupedRequests: number = 0;
  public visibleRequests: number = 0;
  public preloadRequests: number = 0;
  public averageElapsedMs: number = 0;
  public recentSamples: MangaAssetLoadSample[] = [];
}

export class MangaAssetMonitor {
  private totalRequests: number = 0;
  private completedRequests: number = 0;
  private failedRequests: number = 0;
  private dedupedRequests: number = 0;
  private visibleRequests: number = 0;
  private preloadRequests: number = 0;
  private totalElapsedMs: number = 0;
  private recentSamples: MangaAssetLoadSample[] = [];

  public markStart(request: MangaAssetLoadRequest): void {
    this.totalRequests++;
    if (request.reason === MangaAssetLoadReason.VISIBLE ||
      request.reason === MangaAssetLoadReason.WEBTOON) {
      this.visibleRequests++;
    } else {
      this.preloadRequests++;
    }
  }

  public markDeduped(request: MangaAssetLoadRequest): void {
    this.dedupedRequests++;
    const sample: MangaAssetLoadSample = new MangaAssetLoadSample();
    sample.requestKey = request.requestKey;
    sample.pageId = request.pageId;
    sample.chapterId = request.chapterId;
    sample.pageIndex = request.pageIndex;
    sample.reason = request.reason;
    sample.deduped = true;
    sample.timestamp = Date.now();
    this.pushSample(sample);
  }

  public markFinish(request: MangaAssetLoadRequest, result: MangaAssetLoadResult): void {
    const sample: MangaAssetLoadSample = new MangaAssetLoadSample();
    sample.requestKey = request.requestKey;
    sample.pageId = request.pageId;
    sample.chapterId = request.chapterId;
    sample.pageIndex = request.pageIndex;
    sample.reason = request.reason;
    sample.source = result.source;
    sample.success = result.success;
    sample.elapsedMs = result.elapsedMs;
    sample.errorMessage = result.errorMessage;
    sample.timestamp = Date.now();

    if (result.success) {
      this.completedRequests++;
      this.totalElapsedMs += result.elapsedMs;
    } else {
      this.failedRequests++;
    }

    this.pushSample(sample);

    if (request.reason === MangaAssetLoadReason.VISIBLE && result.elapsedMs > 1200) {
      logger.warn(TAG, `可见页加载偏慢: page=${request.pageId}, elapsed=${result.elapsedMs}ms, source=${result.source}`);
    }
  }

  public createSnapshot(): MangaAssetMetricsSnapshot {
    const snapshot: MangaAssetMetricsSnapshot = new MangaAssetMetricsSnapshot();
    snapshot.totalRequests = this.totalRequests;
    snapshot.completedRequests = this.completedRequests;
    snapshot.failedRequests = this.failedRequests;
    snapshot.dedupedRequests = this.dedupedRequests;
    snapshot.visibleRequests = this.visibleRequests;
    snapshot.preloadRequests = this.preloadRequests;
    snapshot.averageElapsedMs = this.completedRequests > 0
      ? Math.round(this.totalElapsedMs / this.completedRequests)
      : 0;
    snapshot.recentSamples = this.recentSamples.slice();
    return snapshot;
  }

  public reset(): void {
    this.totalRequests = 0;
    this.completedRequests = 0;
    this.failedRequests = 0;
    this.dedupedRequests = 0;
    this.visibleRequests = 0;
    this.preloadRequests = 0;
    this.totalElapsedMs = 0;
    this.recentSamples = [];
  }

  private pushSample(sample: MangaAssetLoadSample): void {
    this.recentSamples.push(sample);
    while (this.recentSamples.length > MAX_RECENT_SAMPLES) {
      this.recentSamples.shift();
    }
  }
}
