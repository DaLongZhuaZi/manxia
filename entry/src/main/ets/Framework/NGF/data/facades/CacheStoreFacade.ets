import { ICacheStore } from '../contracts/ICacheStore';

class NGFCacheEntry {
  value: string;
  expiresAt: number;

  constructor(value: string, expiresAt: number) {
    this.value = value;
    this.expiresAt = expiresAt;
  }

  isExpired(now: number): boolean {
    if (this.expiresAt <= 0) {
      return false;
    }
    return now >= this.expiresAt;
  }
}

export class CacheStoreFacade implements ICacheStore {
  private readonly cacheEntries: Map<string, NGFCacheEntry> = new Map<string, NGFCacheEntry>();

  put(key: string, value: string, ttlMs: number): void {
    const now = Date.now();
    const expiresAt = ttlMs > 0 ? now + ttlMs : 0;
    const entry = new NGFCacheEntry(value, expiresAt);
    this.cacheEntries.set(key, entry);
  }

  get(key: string): string {
    const entry = this.cacheEntries.get(key);
    if (!entry) {
      return '';
    }

    const now = Date.now();
    if (entry.isExpired(now)) {
      this.cacheEntries.delete(key);
      return '';
    }

    return entry.value;
  }

  has(key: string): boolean {
    const entry = this.cacheEntries.get(key);
    if (!entry) {
      return false;
    }

    const now = Date.now();
    if (entry.isExpired(now)) {
      this.cacheEntries.delete(key);
      return false;
    }

    return true;
  }

  remove(key: string): void {
    this.cacheEntries.delete(key);
  }

  clear(): void {
    this.cacheEntries.clear();
  }
}

export const ngfCacheStoreFacade = new CacheStoreFacade();
