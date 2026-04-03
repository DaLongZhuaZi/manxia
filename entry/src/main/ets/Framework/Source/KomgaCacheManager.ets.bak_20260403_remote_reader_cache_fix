import fs from '@ohos.file.fs';
import { http } from '@kit.NetworkKit';
import { getContext } from '../../GlobalContext';
import { logger } from '../../Utils/Logger';

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
      fs.accessSync(cachePath);
      return cachePath;
    } catch (_error) {
      return null;
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

      const filePath = this.getCoverCachePath(itemKey, coverUrl);
      const file = fs.openSync(filePath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, response.result as ArrayBuffer);
      } finally {
        fs.closeSync(file.fd);
      }
      return filePath;
    } catch (error) {
      logger.error(TAG, `缓存 Komga 封面失败: ${String(error)}`);
      return null;
    } finally {
      request.destroy();
    }
  }

  public clearCoverCache(): boolean {
    try {
      const coverDir = this.getCoverCacheDir();
      const files = fs.listFileSync(coverDir);
      files.forEach(file => {
        try {
          fs.unlinkSync(`${coverDir}/${file}`);
        } catch (_error) {
        }
      });
      return true;
    } catch (error) {
      logger.error(TAG, `清理 Komga 封面缓存失败: ${String(error)}`);
      return false;
    }
  }

  public clearAllCache(): boolean {
    return this.clearCoverCache();
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

  private getBaseCacheDir(): string {
    const context = getContext();
    const filesDir = typeof context.filesDir === 'string' ? String(context.filesDir) : '';
    const cacheDir = typeof context.cacheDir === 'string' ? String(context.cacheDir) : '';
    const rootDir = filesDir.length > 0 ? filesDir : cacheDir;
    if (rootDir.length <= 0) {
      throw new Error('无法获取应用缓存目录');
    }

    const targetDir = `${rootDir}/komga_cache`;
    this.ensureDirectory(targetDir);
    return targetDir;
  }

  private ensureDirectory(path: string): void {
    try {
      fs.accessSync(path);
    } catch (_error) {
      fs.mkdirSync(path, true);
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
    return value
      .replace(/[\\/:*?"<>|]/g, '_')
      .replace(/\s+/g, '_')
      .trim()
      .substring(0, 120);
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
