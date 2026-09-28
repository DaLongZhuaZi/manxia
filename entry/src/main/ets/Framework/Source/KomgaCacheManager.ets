import { SafeFileUtils } from 'manxia_core/src/main/ets/Utils/SafeFileUtils';
import fs from '@ohos.file.fs';
import { http } from '@kit.NetworkKit';
import { getContext } from 'manxia_core/src/main/ets/GlobalContext';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { getMangaLoadStageReporter, MangaLoadStage } from '../Reader/MangaLoadStageReporter';
import {
  DownloadCacheLimiterPermit,
  DownloadCacheSourceLimiter,
  getDownloadCacheSourceLimiter
} from 'manxia_network/src/main/ets/Framework/Download/DownloadCacheSourceLimiter';

const TAG = 'KomgaCacheManager';

/** 取页结果：必须区分"发过请求但失败"和"根本没发请求"，否则被丢弃的预取会被误记为失败。 */
interface KomgaPageFetchOutcome {
  path: string | null;
  attempted: boolean;
}

/** 取页请求的可选参数。用显式接口而不是位置参数，避免调用处出现一串含义不明的布尔值。 */
export interface KomgaPageFetchOptions {
  headers?: Record<string, string>;
  /** true = 用户可见页（独占通道、更长超时）；false/缺省 = 预加载。 */
  visible?: boolean;
  /** true = 用户主动刷新：跳过缓存与失败抑制。 */
  forceRefresh?: boolean;
}

/**
 * Komga 取页需要服务端解压漫画归档，实测远慢于普通图片。
 * 并发过高时所有请求会一起卡到 readTimeout（实测 9 页预加载会退化成全部 30s 超时），
 * 因此这里对同类型请求做并发上限，宁可排队也不要一起超时。
 */
const KOMGA_COVER_FETCH_KEY: string = 'komga_cover_fetch';
const KOMGA_COVER_MAX_CONCURRENT: number = 3;

/**
 * 取页分成两条互不干扰的通道：
 * - visible：用户当前真正要看的页，独占一条通道，永远不会被预加载堵在队列里；
 * - prefetch：预加载页，走另一条通道。
 * 两条通道各自并发 1，因此对服务端的总并发始终是 2，不会像以前那样一次轰 18 个请求。
 */
const KOMGA_PAGE_VISIBLE_KEY: string = 'komga_page_visible';
const KOMGA_PAGE_PREFETCH_KEY: string = 'komga_page_prefetch';
const KOMGA_PAGE_VISIBLE_MAX_CONCURRENT: number = 1;
const KOMGA_PAGE_PREFETCH_MAX_CONCURRENT: number = 1;

/** 预加载最多允许积压的页数，超出直接放弃（等它真正可见时再拉），避免开屏一次排队 9 页。 */
const KOMGA_PAGE_PREFETCH_MAX_PENDING: number = 2;

/** 单页失败后的抑制窗口：窗口内不再重试，避免每次翻页都重新拉同一张取不到的图。 */
const KOMGA_PAGE_FAILURE_TTL_MS: number = 30000;

/** 与长期可用的 KomgaImage 取值对齐：30s 连接。 */
const KOMGA_CONNECT_TIMEOUT_MS: number = 30000;
/** 可见页可以等更久（服务端要解压归档）；预加载页没必要占着通道，早点让位。 */
const KOMGA_VISIBLE_READ_TIMEOUT_MS: number = 60000;
const KOMGA_PREFETCH_READ_TIMEOUT_MS: number = 40000;

export class KomgaCacheManager {
  private static instance: KomgaCacheManager;
  private limiter: DownloadCacheSourceLimiter = getDownloadCacheSourceLimiter();
  /** 取页失败抑制表：key = 页标识，value = 允许再次尝试的时间戳。 */
  private pageFailureUntil: Map<string, number> = new Map<string, number>();

  private buildPageFailureKey(mangaKey: string, chapterKey: string, pageIndex: number): string {
    return `${mangaKey}|${chapterKey}|${pageIndex}`;
  }

  private constructor() {
  }

  /**
   * 把 http 异常转成可读文本。
   *
   * 直接用 String(error) 对 @kit.NetworkKit 抛出的错误对象只会得到 "[object Object]"，
   * 真实错误码被吞掉，导致线上无法判断是超时、DNS 还是证书问题（此前正是这个问题）。
   */
  private formatError(error: Object): string {
    const record = error as Record<string, Object>;
    const codeValue: Object | undefined = record['code'];
    const messageValue: Object | undefined = record['message'];
    const codeText: string = codeValue !== undefined && codeValue !== null ? String(codeValue) : '';
    const messageText: string = messageValue !== undefined && messageValue !== null ? String(messageValue) : '';
    if (codeText.length > 0 || messageText.length > 0) {
      return `code=${codeText.length > 0 ? codeText : '-'}, message=${messageText.length > 0 ? messageText : '-'}`;
    }
    if (error instanceof Error) {
      return `${error.name}: ${error.message}`;
    }
    return String(error);
  }

  /**
   * 非 2xx 响应的可读描述，并给出常见成因提示（鉴权 / 协议跳转）。
   */
  private describeFailureResponse(statusCode: number, url: string): string {
    let hint: string = '';
    if (statusCode === 401 || statusCode === 403) {
      hint = '（鉴权失败，请检查该 Komga 实例的账号/API Key）';
    } else if (statusCode >= 300 && statusCode < 400) {
      hint = '（协议被重定向，建议把实例地址改为最终协议，例如 https）';
    } else if (statusCode === 404) {
      hint = '（资源不存在）';
    }
    return `响应码: ${statusCode}${hint}, url=${url}`;
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

    const permit: DownloadCacheLimiterPermit =
      await this.limiter.acquire(KOMGA_COVER_FETCH_KEY, KOMGA_COVER_MAX_CONCURRENT);
    try {
      return await this.fetchCoverToCache(itemKey, coverUrl, headers);
    } finally {
      this.limiter.release(permit);
    }
  }

  private async fetchCoverToCache(itemKey: string, coverUrl: string, headers?: Record<string, string>): Promise<string | null> {
    const request = http.createHttp();
    try {
      const response = await request.request(coverUrl, {
        method: http.RequestMethod.GET,
        header: this.getRequestHeaders(headers),
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: KOMGA_CONNECT_TIMEOUT_MS,
        // 封面是用户可见内容，且 Komga 对缩略图有预生成，直接复用可见页的 60s 读取超时
        readTimeout: KOMGA_VISIBLE_READ_TIMEOUT_MS
      });

      if (response.responseCode < 200 || response.responseCode >= 300 || !response.result) {
        logger.warn(TAG, `缓存封面失败，${this.describeFailureResponse(response.responseCode, coverUrl)}`);
        return null;
      }

      const imageData = response.result as ArrayBuffer;
      if (imageData.byteLength <= 0) {
        logger.warn(TAG, `缓存封面失败，响应内容为空, url=${coverUrl}`);
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
      logger.error(TAG, `缓存 Komga 封面失败: ${this.formatError(error as Object)}, url=${coverUrl}`);
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
    fetchOptions?: KomgaPageFetchOptions
  ): Promise<string | null> {
    if (!pageUrl || pageUrl.trim().length <= 0) {
      return null;
    }

    const cachedPath = this.getCachedPagePath(mangaKey, chapterKey, pageIndex);
    if (cachedPath) {
      return cachedPath;
    }

    const visible: boolean = fetchOptions?.visible === true;
    const failureKey: string = this.buildPageFailureKey(mangaKey, chapterKey, pageIndex);

    if (fetchOptions?.forceRefresh === true) {
      this.pageFailureUntil.delete(failureKey);
    } else {
      const retryAt: number = this.pageFailureUntil.get(failureKey) || 0;
      if (retryAt > Date.now()) {
        // 刚失败过的页不再立刻重试：同一份数据重试只会再浪费一次几十秒的往返。
        logger.debug(TAG, `Komga 取页处于失败抑制期，跳过: pageIndex=${pageIndex + 1}, 剩余=${retryAt - Date.now()}ms`);
        getMangaLoadStageReporter().report(pageUrl, MangaLoadStage.FAILED, '刚刚取页失败，暂停重试');
        return null;
      }
    }

    const limiterKey: string = visible ? KOMGA_PAGE_VISIBLE_KEY : KOMGA_PAGE_PREFETCH_KEY;
    const maxConcurrent: number = visible ? KOMGA_PAGE_VISIBLE_MAX_CONCURRENT : KOMGA_PAGE_PREFETCH_MAX_CONCURRENT;

    if (!visible) {
      const pending: number = this.limiter.getActiveCount(limiterKey) + this.limiter.getQueueSize(limiterKey);
      if (pending >= KOMGA_PAGE_PREFETCH_MAX_PENDING) {
        // 预加载积压过多时直接放弃：这一页真正被看到时会以可见页身份重新请求，
        // 现在排队只会拖慢用户当前要看的页。
        logger.debug(TAG, `预加载积压已满，放弃本次预取: pageIndex=${pageIndex + 1}, pending=${pending}`);
        return null;
      }
    }

    if (visible) {
      getMangaLoadStageReporter().report(pageUrl, MangaLoadStage.QUEUED, '等待取页通道');
    }

    const permit: DownloadCacheLimiterPermit = await this.limiter.acquire(limiterKey, maxConcurrent);
    try {
      const outcome: KomgaPageFetchOutcome =
        await this.fetchPageToCache(mangaKey, chapterKey, pageIndex, pageUrl, fetchOptions?.headers, visible);
      if (outcome.path === null && outcome.attempted) {
        // 只有真正发过请求且失败的页才进入抑制窗口；
        // 被并发上限丢弃的预取不算失败，绝不能连累同一页的可见请求。
        this.pageFailureUntil.set(failureKey, Date.now() + KOMGA_PAGE_FAILURE_TTL_MS);
      }
      return outcome.path;
    } finally {
      this.limiter.release(permit);
    }
  }

  private async fetchPageToCache(
    mangaKey: string,
    chapterKey: string,
    pageIndex: number,
    pageUrl: string,
    headers: Record<string, string> | undefined,
    visible: boolean
  ): Promise<KomgaPageFetchOutcome> {
    const readTimeout: number = visible ? KOMGA_VISIBLE_READ_TIMEOUT_MS : KOMGA_PREFETCH_READ_TIMEOUT_MS;
    const request = http.createHttp();
    const startedAt: number = Date.now();
    try {
      logger.debug(TAG, `Komga 取页开始: pageIndex=${pageIndex + 1}, 通道=${visible ? 'visible' : 'prefetch'}, url=${pageUrl}`);
      getMangaLoadStageReporter().report(pageUrl, MangaLoadStage.DOWNLOADING, '正在从服务器取页');
      const response = await request.request(pageUrl, {
        method: http.RequestMethod.GET,
        header: this.getRequestHeaders(headers),
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: KOMGA_CONNECT_TIMEOUT_MS,
        readTimeout: readTimeout
      });

      if (response.responseCode < 200 || response.responseCode >= 300 || !response.result) {
        logger.warn(TAG, `缓存 Komga 章节页失败，${this.describeFailureResponse(response.responseCode, pageUrl)}, pageIndex=${pageIndex + 1}, 耗时=${Date.now() - startedAt}ms`);
        getMangaLoadStageReporter().report(pageUrl, MangaLoadStage.FAILED, `服务器返回 ${response.responseCode}`);
        return { path: null, attempted: true };
      }

      const imageData = response.result as ArrayBuffer;
      if (imageData.byteLength <= 0) {
        logger.warn(TAG, `缓存 Komga 章节页失败，响应内容为空, url=${pageUrl}, pageIndex=${pageIndex + 1}`);
        getMangaLoadStageReporter().report(pageUrl, MangaLoadStage.FAILED, '服务器返回空内容');
        return { path: null, attempted: true };
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
        return { path: null, attempted: true };
      }
      logger.info(TAG, `Komga 章节页缓存成功: pageIndex=${pageIndex + 1}, bytes=${imageData.byteLength}, 耗时=${Date.now() - startedAt}ms`);
      return { path: filePath, attempted: true };
    } catch (error) {
      logger.error(TAG, `缓存 Komga 章节页失败: ${this.formatError(error as Object)}, url=${pageUrl}, pageIndex=${pageIndex + 1}, 耗时=${Date.now() - startedAt}ms`);
      getMangaLoadStageReporter().report(pageUrl, MangaLoadStage.FAILED, this.formatError(error as Object));
      return { path: null, attempted: true };
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
