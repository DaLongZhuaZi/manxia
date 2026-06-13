import { ExistingMangaCandidate } from '../Components/MangaImportDialog';

class ImportDuplicateDetectionCacheEntry {
  public key: string = '';
  public candidates: ExistingMangaCandidate[] = new Array<ExistingMangaCandidate>();
  public createdAt: number = 0;
  public lastAccessAt: number = 0;
}

export class ImportDuplicateDetectionCache {
  private static instance: ImportDuplicateDetectionCache | null = null;
  private static readonly TTL_MS: number = 5 * 60 * 1000;
  private static readonly MAX_ENTRIES: number = 64;
  private entries: Map<string, ImportDuplicateDetectionCacheEntry> = new Map<string, ImportDuplicateDetectionCacheEntry>();

  private constructor() {}

  public static getInstance(): ImportDuplicateDetectionCache {
    if (ImportDuplicateDetectionCache.instance === null) {
      ImportDuplicateDetectionCache.instance = new ImportDuplicateDetectionCache();
    }
    return ImportDuplicateDetectionCache.instance;
  }

  public buildKey(sessionId: string, title: string, contentType: string, source: string): string {
    const normalizedSession: string = sessionId.trim().length > 0 ? sessionId.trim() : 'global';
    const normalizedTitle: string = title.trim().toLowerCase();
    const normalizedType: string = contentType.trim().toLowerCase();
    const normalizedSource: string = source.trim().toLowerCase();
    return `${normalizedSession}|${normalizedType}|${normalizedSource}|${normalizedTitle}`;
  }

  public get(sessionId: string, title: string, contentType: string, source: string): ExistingMangaCandidate[] | null {
    this.removeExpired();
    const key: string = this.buildKey(sessionId, title, contentType, source);
    const entry: ImportDuplicateDetectionCacheEntry | undefined = this.entries.get(key);
    if (!entry) {
      return null;
    }
    entry.lastAccessAt = Date.now();
    return entry.candidates.slice();
  }

  public set(
    sessionId: string,
    title: string,
    contentType: string,
    source: string,
    candidates: ExistingMangaCandidate[]
  ): void {
    this.removeExpired();
    const key: string = this.buildKey(sessionId, title, contentType, source);
    const entry: ImportDuplicateDetectionCacheEntry = new ImportDuplicateDetectionCacheEntry();
    entry.key = key;
    entry.candidates = candidates.slice();
    entry.createdAt = Date.now();
    entry.lastAccessAt = entry.createdAt;
    this.entries.set(key, entry);
    this.trimToLimit();
  }

  public clearSession(sessionId: string): void {
    const normalizedSession: string = sessionId.trim().length > 0 ? sessionId.trim() : 'global';
    const keys: string[] = Array.from(this.entries.keys());
    for (let i = 0; i < keys.length; i++) {
      const key: string = keys[i];
      if (key.startsWith(`${normalizedSession}|`)) {
        this.entries.delete(key);
      }
    }
  }

  public clear(): void {
    this.entries.clear();
  }

  private removeExpired(): void {
    const now: number = Date.now();
    const keys: string[] = Array.from(this.entries.keys());
    for (let i = 0; i < keys.length; i++) {
      const key: string = keys[i];
      const entry: ImportDuplicateDetectionCacheEntry | undefined = this.entries.get(key);
      if (entry && now - entry.createdAt > ImportDuplicateDetectionCache.TTL_MS) {
        this.entries.delete(key);
      }
    }
  }

  private trimToLimit(): void {
    while (this.entries.size > ImportDuplicateDetectionCache.MAX_ENTRIES) {
      let oldestKey: string = '';
      let oldestAccessAt: number = 9007199254740991;
      const keys: string[] = Array.from(this.entries.keys());
      for (let i = 0; i < keys.length; i++) {
        const key: string = keys[i];
        const entry: ImportDuplicateDetectionCacheEntry | undefined = this.entries.get(key);
        if (entry && entry.lastAccessAt < oldestAccessAt) {
          oldestKey = key;
          oldestAccessAt = entry.lastAccessAt;
        }
      }
      if (oldestKey.length <= 0) {
        return;
      }
      this.entries.delete(oldestKey);
    }
  }
}

export function getImportDuplicateDetectionCache(): ImportDuplicateDetectionCache {
  return ImportDuplicateDetectionCache.getInstance();
}
