import { SafeFileUtils } from 'manxia_core/src/main/ets/Utils/SafeFileUtils';
import fs from '@ohos.file.fs';
import { http } from '@kit.NetworkKit';
import { getContext } from 'manxia_theme/src/main/ets/GlobalContext';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';

const TAG = 'KomgaCacheManager';

export class KomgaCacheManager {
  private static instance: KomgaCacheManager;

  private constructor() {
  }

  public static getInstance(): KomgaCacheManager {
    if (!KomgaCacheManager.instance) {
      KomgaCacheManager.instance = new KomgaCacheManager();
    }
    return KomgaCacheManager.instance;
  }

  public getCachedCoverPath(itemKey: string, coverUrl: string): string | null {
    try {
      const cachePath = this.getCoverCachePath(itemKey, coverUrl);
      if (!this.isReadableFile(cachePath)) {
        return null;
      }
      return cachePath;
    } catch (_error) {
      return null;
    }
  }

  public invalidateCoverCache(itemKey: string, coverUrl: string): boolean {
    try {
      const cachePath: string = this.getCoverCachePath(itemKey, coverUrl);
      if (!SafeFileUtils.accessSync(cachePath)) {
        return true;
      }
      SafeFileUtils.unlinkSync(cachePath);
      logger.info(TAG, `Komga 单图缓存已失效: key=${itemKey}, path=${cachePath}`);
      return true;
    } catch (error) {
      logger.warn(TAG, `Komga 单图缓存失效失败: key=${itemKey}, error=${String(error)}`);
      return false;
    }
  }

  public getCachedPagePath(mangaKey: string, chapterKey: string, pageIndex: number): string | null {
    try {
      const cachePath = this.getPageCachePath(mangaKey, chapterKey, pageIndex);
      if (!this.isReadableFile(cachePath)) {
        return null;
      }
      return cachePath;
    } catch (_error) {
      return null;
    }
  }

  public invalidatePageCache(mangaKey: string, chapterKey: string, pageIndex: number): boolean {
    try {
      const pagePath: string = this.getPageCachePath(mangaKey, chapterKey, pageIndex);
      if (!SafeFileUtils.accessSync(pagePath)) {
        return true;
      }
      SafeFileUtils.unlinkSync(pagePath);
      logger.info(TAG, `Komga 单页缓存已失效: page=${pageIndex + 1}, path=${pagePath}`);
      return true;
    } catch (error) {
      logger.warn(TAG, `Komga 单页缓存失效失败: page=${pageIndex + 1}, error=${String(error)}`);
      return false;
    }
  }

  public async cacheCover(itemKey: string, coverUrl: string, headers?: Record<string, string>): Promise<string | null> {
    if (!coverUrl || coverUrl.trim().length <= 0) {
      return null;
    }

    const cachedPath = this.getCachedCoverPath(itemKey, coverUrl);
    if (cachedPath) {
      return cachedPath;
    }

    const request = http.createHttp();
    try {
      const response = await request.request(coverUrl, {
        method: http.RequestMethod.GET,
        header: this.getRequestHeaders(headers),
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 20000,
        readTimeout: 30000
      });

      if (response.responseCode < 200 || response.responseCode >= 300 || !response.result) {
        logger.warn(TAG, `缓存封面失败，响应码: ${response.responseCode}`);
        return null;
      }

      const imageData = response.result as ArrayBuffer;
      if (imageData.byteLength <= 0) {
        logger.warn(TAG, '缓存封面失败，响应内容为空');
        return null;
      }

      const filePath = this.getCoverCachePath(itemKey, coverUrl);
      const file = fs.openSync(filePath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, imageData);
      } finally {
        fs.closeSync(file);
      }
      if (!this.isReadableFile(filePath)) {
        logger.warn(TAG, `缓存封面写入后校验失败: ${filePath}`);
        return null;
      }
      return filePath;
    } catch (error) {
      logger.error(TAG, `缓存 Komga 封面失败: ${String(error)}`);
      return null;
    } finally {
      request.destroy();
    }
  }

  public async cachePage(
    mangaKey: string,
    chapterKey: string,
    pageIndex: number,
    pageUrl: string,
    headers?: Record<string, string>
  ): Promise<string | null> {
    if (!pageUrl || pageUrl.trim().length <= 0) {
      return null;
    }

    const cachedPath = this.getCachedPagePath(mangaKey, chapterKey, pageIndex);
    if (cachedPath) {
      return cachedPath;
    }

    const request = http.createHttp();
    try {
      const response = await request.request(pageUrl, {
        method: http.RequestMethod.GET,
        header: this.getRequestHeaders(headers),
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 20000,
        readTimeout: 30000
      });

      if (response.responseCode < 200 || response.responseCode >= 300 || !response.result) {
        logger.warn(TAG, `缓存 Komga 章节页失败，响应码: ${response.responseCode}, pageIndex=${pageIndex + 1}`);
        return null;
      }

      const imageData = response.result as ArrayBuffer;
      if (imageData.byteLength <= 0) {
        logger.warn(TAG, `缓存 Komga 章节页失败，响应内容为空, pageIndex=${pageIndex + 1}`);
        return null;
      }

      const filePath = this.getPageCachePath(mangaKey, chapterKey, pageIndex);
      const file = fs.openSync(filePath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, imageData);
      } finally {
        fs.closeSync(file);
      }
      if (!this.isReadableFile(filePath)) {
        logger.warn(TAG, `缓存 Komga 章节页写入后校验失败: ${filePath}`);
        return null;
      }
      return filePath;
    } catch (error) {
      logger.error(TAG, `缓存 Komga 章节页失败: ${String(error)}`);
      return null;
    } finally {
      request.destroy();
    }
  }

  public clearCoverCache(): boolean {
    try {
      const coverDir = this.getCoverCacheDir();
      this.clearDirectoryContents(coverDir);
      return true;
    } catch (error) {
      logger.error(TAG, `清理 Komga 封面缓存失败: ${String(error)}`);
      return false;
    }
  }

  public clearChapterCache(): boolean {
    try {
      const chapterDir = this.getChapterCacheDir();
      this.clearDirectoryContents(chapterDir);
      return true;
    } catch (error) {
      logger.error(TAG, `清理 Komga 章节缓存失败: ${String(error)}`);
      return false;
    }
  }

  public clearAllCache(): boolean {
    const coverResult = this.clearCoverCache();
    const chapterResult = this.clearChapterCache();
    return coverResult && chapterResult;
  }

  private getCoverCachePath(itemKey: string, coverUrl: string): string {
    const cacheDir = this.getCoverCacheDir();
    const safeKey = this.sanitizeKey(itemKey);
    const ext = this.getExtensionFromUrl(coverUrl);
    const hash = this.hashString(coverUrl);
    return `${cacheDir}/${safeKey}_${hash}.${ext}`;
  }

  private getCoverCacheDir(): string {
    const baseDir = this.getBaseCacheDir();
    const coverDir = `${baseDir}/covers`;
    this.ensureDirectory(coverDir);
    return coverDir;
  }

  private getChapterCacheDir(): string {
    const baseDir = this.getBaseCacheDir();
    const chapterDir = `${baseDir}/chapters`;
    this.ensureDirectory(chapterDir);
    return chapterDir;
  }

  private getMangaChapterCacheDir(mangaKey: string, chapterKey: string): string {
    const chapterRoot = this.getChapterCacheDir();
    const safeMangaKey = this.sanitizeKey(mangaKey);
    const safeChapterKey = this.sanitizeKey(chapterKey);
    const mangaDir = `${chapterRoot}/${safeMangaKey}`;
    const chapterDir = `${mangaDir}/${safeChapterKey}`;
    this.ensureDirectory(mangaDir);
    this.ensureDirectory(chapterDir);
    return chapterDir;
  }

  private getPageCachePath(mangaKey: string, chapterKey: string, pageIndex: number): string {
    const chapterDir = this.getMangaChapterCacheDir(mangaKey, chapterKey);
    return `${chapterDir}/page_${String(pageIndex + 1).padStart(4, '0')}.img`;
  }

  private getBaseCacheDir(): string {
    let filesDir = '';
    let cacheDir = '';
    try {
      const context = getContext();
      filesDir = typeof context.filesDir === 'string' ? String(context.filesDir) : '';
      cacheDir = typeof context.cacheDir === 'string' ? String(context.cacheDir) : '';
    } catch (error) {
      throw new Error(`无法获取应用上下文: ${String(error)}`);
    }
    const rootDir = filesDir.length > 0 ? filesDir : cacheDir;
    if (rootDir.length <= 0) {
      throw new Error('无法获取应用缓存目录');
    }

    const targetDir = `${rootDir}/komga_cache`;
    this.ensureDirectory(targetDir);
    return targetDir;
  }

  private ensureDirectory(path: string): void {
    if (!SafeFileUtils.accessSync(path)) {
      SafeFileUtils.mkdirSync(path, true);
    }
  }

  private isReadableFile(path: string): boolean {
    if (!SafeFileUtils.accessSync(path)) {
      return false;
    }
    try {
      const stat = fs.statSync(path);
      return !stat.isDirectory() && stat.size > 0;
    } catch (_error) {
      return false;
    }
  }

  private getRequestHeaders(headers?: Record<string, string>): Record<string, string> {
    if (headers) {
      return headers;
    }

    const defaultHeaders: Record<string, string> = {
      'User-Agent': 'ManXiaKomga/1.0'
    };
    return defaultHeaders;
  }

  private sanitizeKey(value: string): string {
    const sanitized = value
      .replace(/[\\/:*?"<>|]/g, '_')
      .replace(/\s+/g, '_')
      .trim()
      .substring(0, 120);
    return sanitized.length > 0 ? sanitized : 'unknown';
  }

  private clearDirectoryContents(path: string): void {
    const entries: string[] = SafeFileUtils.listFileSync(path);
    for (let index = 0; index < entries.length; index++) {
      const entry = entries[index];
      const entryPath = `${path}/${entry}`;
      try {
        const stat = SafeFileUtils.statSync(entryPath);
        if (stat.isDirectory()) {
          this.clearDirectoryContents(entryPath);
          SafeFileUtils.rmdirSync(entryPath);
        } else {
          SafeFileUtils.unlinkSync(entryPath);
        }
      } catch (_error) {
      }
    }
  }

  private getExtensionFromUrl(url: string): string {
    const normalized = url.toLowerCase();
    if (normalized.includes('convert=png')) {
      return 'png';
    }

    const matched = normalized.match(/\.([a-z0-9]{2,5})(?:$|[?#])/);
    if (!matched || !matched[1]) {
      return 'jpg';
    }

    const ext = matched[1];
    return ext === 'jpeg' ? 'jpg' : ext;
  }

  private hashString(value: string): string {
    let hash = 0;
    for (let index = 0; index < value.length; index++) {
      hash = ((hash << 5) - hash) + value.charCodeAt(index);
      hash |= 0;
    }
    return Math.abs(hash).toString(16);
  }
}

export default KomgaCacheManager.getInstance();
