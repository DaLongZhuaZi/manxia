export class HomeCoverFailureCacheEntry {
  public key: string = '';
  public failedAt: number = 0;
  public message: string = '';
}

export class HomeCoverFailureTtlCache {
  private static instance: HomeCoverFailureTtlCache | null = null;
  private static readonly DEFAULT_TTL_MS: number = 5 * 60 * 1000;
  private static readonly DEFAULT_MAX_ENTRIES: number = 256;

  private entries: Map<string, HomeCoverFailureCacheEntry> = new Map<string, HomeCoverFailureCacheEntry>();

  private constructor() {}

  public static getInstance(): HomeCoverFailureTtlCache {
    if (HomeCoverFailureTtlCache.instance === null) {
      HomeCoverFailureTtlCache.instance = new HomeCoverFailureTtlCache();
    }
    return HomeCoverFailureTtlCache.instance;
  }

  public shouldSkipBackground(key: string, userExplicitRequest: boolean = false, nowMs: number = Date.now()): boolean {
    if (userExplicitRequest || key.length <= 0) {
      return false;
    }
    const entry: HomeCoverFailureCacheEntry | undefined = this.entries.get(key);
    if (!entry) {
      return false;
    }
    if (nowMs - entry.failedAt >= HomeCoverFailureTtlCache.DEFAULT_TTL_MS) {
      this.entries.delete(key);
      return false;
    }
    return true;
  }

  public recordFailure(key: string, message: string = '', nowMs: number = Date.now()): void {
    if (key.length <= 0) {
      return;
    }
    const entry: HomeCoverFailureCacheEntry = new HomeCoverFailureCacheEntry();
    entry.key = key;
    entry.failedAt = nowMs;
    entry.message = message;
    this.entries.set(key, entry);
    this.trimToCapacity();
  }

  public clearKey(key: string): void {
    if (key.length <= 0) {
      return;
    }
    this.entries.delete(key);
  }

  public clear(): void {
    this.entries.clear();
  }

  public size(): number {
    return this.entries.size;
  }

  public getMessage(key: string): string {
    const entry: HomeCoverFailureCacheEntry | undefined = this.entries.get(key);
    return entry ? entry.message : '';
  }

  private trimToCapacity(): void {
    while (this.entries.size > HomeCoverFailureTtlCache.DEFAULT_MAX_ENTRIES) {
      const keys: string[] = Array.from(this.entries.keys());
      if (keys.length === 0) {
        return;
      }
      this.entries.delete(keys[0]);
    }
  }
}

export function getHomeCoverFailureTtlCache(): HomeCoverFailureTtlCache {
  return HomeCoverFailureTtlCache.getInstance();
}
