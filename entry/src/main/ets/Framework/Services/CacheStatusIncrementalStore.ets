export class CacheStatusIncrementalChapter {
  public chapterId: string = '';
  public chapterTitle: string = '';
  public chapterIndex: number = 0;
  public isCached: boolean = false;
  public isPartiallyCached: boolean = false;
  public cachedPageCount: number = 0;
  public totalPageCount: number = 0;
  public cacheSize: number = 0;
  public cachePath: string = '';
}

export class CacheStatusIncrementalStats {
  public contentId: string = '';
  public contentType: string = '';
  public title: string = '';
  public sourceId: number = 0;
  public cachedChapterCount: number = 0;
  public totalChapterCount: number = 0;
  public cachedPageCount: number = 0;
  public totalPageCount: number = 0;
  public cacheSize: number = 0;
  public downloadWhileReadingEnabled: boolean = false;
  public chapterStats: CacheStatusIncrementalChapter[] = new Array<CacheStatusIncrementalChapter>();
  public lastCacheTime: number = 0;
}

class CacheStatusIncrementalEntry {
  public key: string = '';
  public stats: CacheStatusIncrementalStats = new CacheStatusIncrementalStats();
  public createdAt: number = 0;
  public lastAccessAt: number = 0;
}

export class CacheStatusIncrementalStore {
  private static instance: CacheStatusIncrementalStore | null = null;
  private static readonly DEFAULT_TTL_MS: number = 8 * 1000;
  private static readonly MAX_ENTRIES: number = 96;
  private entries: Map<string, CacheStatusIncrementalEntry> = new Map<string, CacheStatusIncrementalEntry>();

  private constructor() {}

  public static getInstance(): CacheStatusIncrementalStore {
    if (CacheStatusIncrementalStore.instance === null) {
      CacheStatusIncrementalStore.instance = new CacheStatusIncrementalStore();
    }
    return CacheStatusIncrementalStore.instance;
  }

  public buildKey(contentType: string, sourceId: number, contentId: string): string {
    return `${contentType.trim().toLowerCase()}|${sourceId}|${contentId.trim()}`;
  }

  public get(contentType: string, sourceId: number, contentId: string): CacheStatusIncrementalStats | null {
    this.removeExpired();
    const key: string = this.buildKey(contentType, sourceId, contentId);
    const entry: CacheStatusIncrementalEntry | undefined = this.entries.get(key);
    if (!entry) {
      return null;
    }
    entry.lastAccessAt = Date.now();
    return this.cloneStats(entry.stats);
  }

  public set(contentType: string, sourceId: number, contentId: string, stats: CacheStatusIncrementalStats): void {
    this.removeExpired();
    const key: string = this.buildKey(contentType, sourceId, contentId);
    const entry: CacheStatusIncrementalEntry = new CacheStatusIncrementalEntry();
    entry.key = key;
    entry.stats = this.cloneStats(stats);
    entry.createdAt = Date.now();
    entry.lastAccessAt = entry.createdAt;
    this.entries.set(key, entry);
    this.trimToLimit();
  }

  public invalidate(contentType: string, sourceId: number, contentId: string): void {
    const key: string = this.buildKey(contentType, sourceId, contentId);
    this.entries.delete(key);
  }

  public invalidateSource(contentType: string, sourceId: number): void {
    const prefix: string = `${contentType.trim().toLowerCase()}|${sourceId}|`;
    const keys: string[] = Array.from(this.entries.keys());
    for (let i = 0; i < keys.length; i++) {
      if (keys[i].startsWith(prefix)) {
        this.entries.delete(keys[i]);
      }
    }
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
      const entry: CacheStatusIncrementalEntry | undefined = this.entries.get(key);
      if (entry && now - entry.createdAt > CacheStatusIncrementalStore.DEFAULT_TTL_MS) {
        this.entries.delete(key);
      }
    }
  }

  private trimToLimit(): void {
    while (this.entries.size > CacheStatusIncrementalStore.MAX_ENTRIES) {
      let oldestKey: string = '';
      let oldestAccessAt: number = 9007199254740991;
      const keys: string[] = Array.from(this.entries.keys());
      for (let i = 0; i < keys.length; i++) {
        const key: string = keys[i];
        const entry: CacheStatusIncrementalEntry | undefined = this.entries.get(key);
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

  private cloneStats(stats: CacheStatusIncrementalStats): CacheStatusIncrementalStats {
    const cloned: CacheStatusIncrementalStats = new CacheStatusIncrementalStats();
    cloned.contentId = stats.contentId;
    cloned.contentType = stats.contentType;
    cloned.title = stats.title;
    cloned.sourceId = stats.sourceId;
    cloned.cachedChapterCount = stats.cachedChapterCount;
    cloned.totalChapterCount = stats.totalChapterCount;
    cloned.cachedPageCount = stats.cachedPageCount;
    cloned.totalPageCount = stats.totalPageCount;
    cloned.cacheSize = stats.cacheSize;
    cloned.downloadWhileReadingEnabled = stats.downloadWhileReadingEnabled;
    cloned.lastCacheTime = stats.lastCacheTime;
    const chapters: CacheStatusIncrementalChapter[] = new Array<CacheStatusIncrementalChapter>();
    for (let i = 0; i < stats.chapterStats.length; i++) {
      const source: CacheStatusIncrementalChapter = stats.chapterStats[i];
      const chapter: CacheStatusIncrementalChapter = new CacheStatusIncrementalChapter();
      chapter.chapterId = source.chapterId;
      chapter.chapterTitle = source.chapterTitle;
      chapter.chapterIndex = source.chapterIndex;
      chapter.isCached = source.isCached;
      chapter.isPartiallyCached = source.isPartiallyCached;
      chapter.cachedPageCount = source.cachedPageCount;
      chapter.totalPageCount = source.totalPageCount;
      chapter.cacheSize = source.cacheSize;
      chapter.cachePath = source.cachePath;
      chapters.push(chapter);
    }
    cloned.chapterStats = chapters;
    return cloned;
  }
}

export function getCacheStatusIncrementalStore(): CacheStatusIncrementalStore {
  return CacheStatusIncrementalStore.getInstance();
}
