class DownloadCacheFailureEntry {
  public key: string = '';
  public failureKind: string = '';
  public errorMessage: string = '';
  public createdAt: number = 0;
  public expiresAt: number = 0;
  public hitCount: number = 0;
}

export class DownloadCacheFailureTtlCache {
  private static instance: DownloadCacheFailureTtlCache | null = null;
  private static readonly DEFAULT_TTL_MS: number = 2 * 60 * 1000;
  private static readonly MAX_ENTRIES: number = 128;
  private entries: Map<string, DownloadCacheFailureEntry> = new Map<string, DownloadCacheFailureEntry>();

  private constructor() {}

  public static getInstance(): DownloadCacheFailureTtlCache {
    if (DownloadCacheFailureTtlCache.instance === null) {
      DownloadCacheFailureTtlCache.instance = new DownloadCacheFailureTtlCache();
    }
    return DownloadCacheFailureTtlCache.instance;
  }

  public buildKey(sourceId: number, sourceKey: string, cacheKey: string, failureKind: string): string {
    const normalizedSourceId: string = sourceId > 0 ? `${sourceId}` : '0';
    const normalizedSourceKey: string = sourceKey.trim().toLowerCase();
    const normalizedCacheKey: string = cacheKey.trim();
    const normalizedFailureKind: string = failureKind.trim().toLowerCase();
    return `${normalizedSourceId}|${normalizedSourceKey}|${normalizedFailureKind}|${normalizedCacheKey}`;
  }

  public recordFailure(
    sourceId: number,
    sourceKey: string,
    cacheKey: string,
    failureKind: string,
    errorMessage: string,
    ttlMs: number = DownloadCacheFailureTtlCache.DEFAULT_TTL_MS
  ): string {
    this.removeExpired();
    const key: string = this.buildKey(sourceId, sourceKey, cacheKey, failureKind);
    const now: number = Date.now();
    const entry: DownloadCacheFailureEntry = new DownloadCacheFailureEntry();
    entry.key = key;
    entry.failureKind = failureKind;
    entry.errorMessage = errorMessage;
    entry.createdAt = now;
    entry.expiresAt = now + Math.max(1000, ttlMs);
    this.entries.set(key, entry);
    this.trimToLimit();
    return key;
  }

  public shouldSkip(
    sourceId: number,
    sourceKey: string,
    cacheKey: string,
    failureKind: string,
    allowSkip: boolean
  ): boolean {
    if (!allowSkip) {
      return false;
    }
    this.removeExpired();
    const key: string = this.buildKey(sourceId, sourceKey, cacheKey, failureKind);
    const entry: DownloadCacheFailureEntry | undefined = this.entries.get(key);
    if (!entry) {
      return false;
    }
    entry.hitCount = entry.hitCount + 1;
    return true;
  }

  public getErrorMessage(sourceId: number, sourceKey: string, cacheKey: string, failureKind: string): string {
    this.removeExpired();
    const key: string = this.buildKey(sourceId, sourceKey, cacheKey, failureKind);
    const entry: DownloadCacheFailureEntry | undefined = this.entries.get(key);
    return entry ? entry.errorMessage : '';
  }

  public clear(): void {
    this.entries.clear();
  }

  public size(): number {
    this.removeExpired();
    return this.entries.size;
  }

  private removeExpired(): void {
    const now: number = Date.now();
    const keys: string[] = Array.from(this.entries.keys());
    for (let i = 0; i < keys.length; i++) {
      const key: string = keys[i];
      const entry: DownloadCacheFailureEntry | undefined = this.entries.get(key);
      if (entry && entry.expiresAt <= now) {
        this.entries.delete(key);
      }
    }
  }

  private trimToLimit(): void {
    while (this.entries.size > DownloadCacheFailureTtlCache.MAX_ENTRIES) {
      let oldestKey: string = '';
      let oldestCreatedAt: number = 9007199254740991;
      const keys: string[] = Array.from(this.entries.keys());
      for (let i = 0; i < keys.length; i++) {
        const key: string = keys[i];
        const entry: DownloadCacheFailureEntry | undefined = this.entries.get(key);
        if (entry && entry.createdAt < oldestCreatedAt) {
          oldestKey = key;
          oldestCreatedAt = entry.createdAt;
        }
      }
      if (oldestKey.length <= 0) {
        return;
      }
      this.entries.delete(oldestKey);
    }
  }
}

export function getDownloadCacheFailureTtlCache(): DownloadCacheFailureTtlCache {
  return DownloadCacheFailureTtlCache.getInstance();
}
