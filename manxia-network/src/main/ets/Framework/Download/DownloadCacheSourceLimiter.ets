export class DownloadCacheLimiterPermit {
  public sourceKey: string = '';
  public acquiredAt: number = 0;
  public waitedMs: number = 0;
}

class DownloadCacheLimiterWaiter {
  public sourceKey: string = '';
  public requestedAt: number = 0;
  public resolve: ((permit: DownloadCacheLimiterPermit) => void) | null = null;
}

export class DownloadCacheSourceLimiter {
  private static instance: DownloadCacheSourceLimiter | null = null;
  private static readonly DEFAULT_SOURCE_CONCURRENCY: number = 1;
  private static readonly MAX_WAITERS: number = 256;
  private activeBySource: Map<string, number> = new Map<string, number>();
  private waitersBySource: Map<string, DownloadCacheLimiterWaiter[]> = new Map<string, DownloadCacheLimiterWaiter[]>();

  private constructor() {}

  public static getInstance(): DownloadCacheSourceLimiter {
    if (DownloadCacheSourceLimiter.instance === null) {
      DownloadCacheSourceLimiter.instance = new DownloadCacheSourceLimiter();
    }
    return DownloadCacheSourceLimiter.instance;
  }

  public acquire(sourceKey: string, maxConcurrent: number = DownloadCacheSourceLimiter.DEFAULT_SOURCE_CONCURRENCY): Promise<DownloadCacheLimiterPermit> {
    const normalizedSourceKey: string = this.normalizeSourceKey(sourceKey);
    const limit: number = Math.max(1, maxConcurrent);
    const activeCount: number = this.activeBySource.get(normalizedSourceKey) || 0;
    if (activeCount < limit) {
      this.activeBySource.set(normalizedSourceKey, activeCount + 1);
      return Promise.resolve(this.createPermit(normalizedSourceKey, 0));
    }

    return new Promise<DownloadCacheLimiterPermit>((resolve) => {
      const waiter: DownloadCacheLimiterWaiter = new DownloadCacheLimiterWaiter();
      waiter.sourceKey = normalizedSourceKey;
      waiter.requestedAt = Date.now();
      waiter.resolve = resolve;
      let waiters: DownloadCacheLimiterWaiter[] | undefined = this.waitersBySource.get(normalizedSourceKey);
      if (!waiters) {
        waiters = new Array<DownloadCacheLimiterWaiter>();
        this.waitersBySource.set(normalizedSourceKey, waiters);
      }
      waiters.push(waiter);
      this.trimWaiters(normalizedSourceKey);
    });
  }

  public release(permit: DownloadCacheLimiterPermit): void {
    const normalizedSourceKey: string = this.normalizeSourceKey(permit.sourceKey);
    const activeCount: number = this.activeBySource.get(normalizedSourceKey) || 0;
    if (activeCount <= 1) {
      this.activeBySource.delete(normalizedSourceKey);
    } else {
      this.activeBySource.set(normalizedSourceKey, activeCount - 1);
    }
    this.dispatchNext(normalizedSourceKey);
  }

  public getActiveCount(sourceKey: string): number {
    return this.activeBySource.get(this.normalizeSourceKey(sourceKey)) || 0;
  }

  public getQueueSize(sourceKey: string): number {
    const waiters: DownloadCacheLimiterWaiter[] | undefined = this.waitersBySource.get(this.normalizeSourceKey(sourceKey));
    return waiters ? waiters.length : 0;
  }

  public clear(): void {
    this.activeBySource.clear();
    this.waitersBySource.clear();
  }

  private dispatchNext(sourceKey: string): void {
    const waiters: DownloadCacheLimiterWaiter[] | undefined = this.waitersBySource.get(sourceKey);
    if (!waiters || waiters.length === 0) {
      return;
    }
    const waiter: DownloadCacheLimiterWaiter | undefined = waiters.shift();
    if (waiters.length === 0) {
      this.waitersBySource.delete(sourceKey);
    }
    if (!waiter || waiter.resolve === null) {
      return;
    }
    const activeCount: number = this.activeBySource.get(sourceKey) || 0;
    this.activeBySource.set(sourceKey, activeCount + 1);
    waiter.resolve(this.createPermit(sourceKey, Date.now() - waiter.requestedAt));
  }

  private createPermit(sourceKey: string, waitedMs: number): DownloadCacheLimiterPermit {
    const permit: DownloadCacheLimiterPermit = new DownloadCacheLimiterPermit();
    permit.sourceKey = sourceKey;
    permit.acquiredAt = Date.now();
    permit.waitedMs = waitedMs;
    return permit;
  }

  private normalizeSourceKey(sourceKey: string): string {
    const trimmed: string = sourceKey.trim().toLowerCase();
    return trimmed.length > 0 ? trimmed : 'default';
  }

  private trimWaiters(sourceKey: string): void {
    const waiters: DownloadCacheLimiterWaiter[] | undefined = this.waitersBySource.get(sourceKey);
    if (!waiters) {
      return;
    }
    while (waiters.length > DownloadCacheSourceLimiter.MAX_WAITERS) {
      waiters.shift();
    }
  }
}

export function getDownloadCacheSourceLimiter(): DownloadCacheSourceLimiter {
  return DownloadCacheSourceLimiter.getInstance();
}
