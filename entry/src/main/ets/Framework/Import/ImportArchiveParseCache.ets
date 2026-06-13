import { ParsedArchiveStructure as CompressionParsedArchiveStructure } from '../../Utils/CompressionUtils';

class ImportArchiveParseCacheEntry {
  public key: string = '';
  public fileUri: string = '';
  public versionToken: string = '';
  public parsedStructure: CompressionParsedArchiveStructure | null = null;
  public createdAt: number = 0;
  public lastAccessAt: number = 0;
}

export class ImportArchiveParseCache {
  private static instance: ImportArchiveParseCache | null = null;
  private static readonly TTL_MS: number = 10 * 60 * 1000;
  private static readonly MAX_ENTRIES: number = 32;
  private entries: Map<string, ImportArchiveParseCacheEntry> = new Map<string, ImportArchiveParseCacheEntry>();

  private constructor() {}

  public static getInstance(): ImportArchiveParseCache {
    if (ImportArchiveParseCache.instance === null) {
      ImportArchiveParseCache.instance = new ImportArchiveParseCache();
    }
    return ImportArchiveParseCache.instance;
  }

  public buildKey(fileUri: string, versionToken: string = ''): string {
    const normalizedUri: string = this.normalizeFileUri(fileUri);
    const normalizedVersion: string = versionToken.trim();
    if (normalizedVersion.length > 0) {
      return `${normalizedUri}|${normalizedVersion}`;
    }
    return normalizedUri;
  }

  public get(fileUri: string, versionToken: string = ''): CompressionParsedArchiveStructure | null {
    this.removeExpired();
    const key: string = this.buildKey(fileUri, versionToken);
    const entry: ImportArchiveParseCacheEntry | undefined = this.entries.get(key);
    if (!entry || entry.parsedStructure === null) {
      return null;
    }
    entry.lastAccessAt = Date.now();
    return entry.parsedStructure;
  }

  public set(
    fileUri: string,
    parsedStructure: CompressionParsedArchiveStructure,
    versionToken: string = ''
  ): void {
    this.removeExpired();
    const key: string = this.buildKey(fileUri, versionToken);
    const entry: ImportArchiveParseCacheEntry = new ImportArchiveParseCacheEntry();
    entry.key = key;
    entry.fileUri = this.normalizeFileUri(fileUri);
    entry.versionToken = versionToken.trim();
    entry.parsedStructure = parsedStructure;
    entry.createdAt = Date.now();
    entry.lastAccessAt = entry.createdAt;
    this.entries.set(key, entry);
    this.trimToLimit();
  }

  public delete(fileUri: string, versionToken: string = ''): void {
    const key: string = this.buildKey(fileUri, versionToken);
    this.entries.delete(key);
  }

  public clear(): void {
    this.entries.clear();
  }

  private normalizeFileUri(fileUri: string): string {
    return fileUri.trim().replace(/\\/g, '/');
  }

  private removeExpired(): void {
    const now: number = Date.now();
    const keys: string[] = Array.from(this.entries.keys());
    for (let i = 0; i < keys.length; i++) {
      const key: string = keys[i];
      const entry: ImportArchiveParseCacheEntry | undefined = this.entries.get(key);
      if (entry && now - entry.createdAt > ImportArchiveParseCache.TTL_MS) {
        this.entries.delete(key);
      }
    }
  }

  private trimToLimit(): void {
    while (this.entries.size > ImportArchiveParseCache.MAX_ENTRIES) {
      let oldestKey: string = '';
      let oldestAccessAt: number = 9007199254740991;
      const keys: string[] = Array.from(this.entries.keys());
      for (let i = 0; i < keys.length; i++) {
        const key: string = keys[i];
        const entry: ImportArchiveParseCacheEntry | undefined = this.entries.get(key);
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

export function getImportArchiveParseCache(): ImportArchiveParseCache {
  return ImportArchiveParseCache.getInstance();
}
