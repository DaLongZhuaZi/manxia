import { SafeFileUtils } from 'manxia_core/src/main/ets/Utils/SafeFileUtils';
import { SafeUtils } from 'manxia_core/src/main/ets/Utils/SafeUtils';
/**
 * 小说章节缓存管理器
 * 负责章节内容的缓存、下载和离线阅读支持
 * 
 * 缓存存储结构：
 * /files/novels/{bookId}/
 *   ├── metadata.json     # 书籍元数据
 *   ├── chapters/
 *   │   ├── 0001.txt      # 第1章内容
 *   │   ├── 0002.txt      # 第2章内容
 *   │   └── ...
 *   └── cache_info.json   # 缓存信息
 * 
 * 文件路径: entry/src/main/ets/Framework/Novel/NovelChapterCacheManager.ets
 */

import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { getNovelDataManager } from './NovelDataManager';
import { getNovelSourceManager } from './NovelSourceManager';
import { LegadoChapter, LegadoBookSourceType } from 'manxia_novel/src/main/ets/Framework/Novel/LegadoSourceTypes';
import { NovelDownloadTask, NovelCacheInfo, BookMetadata } from 'manxia_core/src/main/ets/Models/NovelModels';
import { ChapterOrderCacheRemapResult, ChapterOrderIndexRemap } from 'manxia_core/src/main/ets/Models/UnifiedContentModels';
import { AppNotificationManager } from 'manxia_core/src/main/ets/Framework/Managers/NotificationManager';
import { SandboxManager } from 'manxia_core/src/main/ets/Framework/Storage/SandboxManager';
import { fileIo } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';

const TAG = 'NovelChapterCacheManager';

/**
 * 下载任务状态
 */
export type DownloadTaskStatus = 'pending' | 'downloading' | 'paused' | 'completed' | 'failed';

/**
 * 下载进度回调
 */
export interface DownloadProgressCallback {
  onProgress: (current: number, total: number, chapterTitle: string) => void;
  onComplete: () => void;
  onError: (error: string) => void;
}

/**
 * 章节列表缓存数据结构
 */
interface ChapterListCacheData {
  updateTime: number;
  totalCount: number;
  chapters: LegadoChapter[];
}

interface AudioChapterCacheItem {
  chapterIndex: number;
  fileName: string;
  sourceUrl: string;
  mimeType: string;
  fileSize: number;
  updateTime: number;
}

interface AudioChapterCacheIndex {
  updateTime: number;
  items: AudioChapterCacheItem[];
}

interface ChapterCacheTempMove {
  stableKey: string;
  sourcePath: string;
  tempPath: string;
  targetPath: string;
}

type AudioJsonValue = string | number | boolean | Object | Array<Object> | null;
type AudioJsonRecord = Record<string, AudioJsonValue>;

/**
 * 小说章节缓存管理器类
 */
export class NovelChapterCacheManager {
  private static instance: NovelChapterCacheManager | null = null;
  private dataManager = getNovelDataManager();
  private sourceManager = getNovelSourceManager();
  private notificationManager = AppNotificationManager.getInstance();
  private sandboxManager = SandboxManager.getInstance();
  private downloadTasks: Map<string, NovelDownloadTask> = new Map();
  private activeDownloads: Set<string> = new Set();
  private maxConcurrentDownloads: number = 3;
  private downloadCallbacks: Map<string, DownloadProgressCallback> = new Map();
  
  // 小说缓存根目录
  private novelsCacheDir: string = '';
  private isInitialized: boolean = false;
  private initPromise: Promise<void> | null = null;
  // 标记是否使用Download目录
  private useDownloadDir: boolean = false;

  private constructor() {
    // 启动初始化但不等待
    this.initPromise = this.initCacheDir();
  }
  
  /**
   * 初始化缓存目录
   * [改进] 优先使用Download同步目录下的novel文件夹
   * 当Download目录未配置时，回退到沙箱目录
   */
  private async initCacheDir(): Promise<void> {
    if (this.isInitialized) return;
    
    try {
      // 优先检查Download同步目录是否已配置
      const downloadDirPath = AppStorage.get<string>('downloadSyncDirPath');
      
      if (downloadDirPath) {
        // 尝试使用Download目录下的novel文件夹
        const novelDir = `${downloadDirPath}/novel`;
        try {
          // 确保目录存在
          try {
            SafeFileUtils.accessSync(novelDir);
          } catch (e) {
            // 目录不存在，创建它
            SafeFileUtils.mkdirSync(novelDir);
          }
          
          // 创建.nomedia文件防止媒体扫描
          this.createNoMediaFile(novelDir);
          
          this.novelsCacheDir = novelDir;
          this.useDownloadDir = true;
          this.isInitialized = true;
          logger.info(TAG, `小说缓存目录初始化(Download目录): ${this.novelsCacheDir}`);
          return;
        } catch (error) {
          logger.warn(TAG, `无法使用Download目录，回退到沙箱目录: ${String(error)}`);
        }
      }
      
      // 回退到沙箱目录
      const filesDir = this.sandboxManager.getDirectory('files');
      this.novelsCacheDir = `${filesDir}/novels`;
      await this.sandboxManager.createDirectory(this.novelsCacheDir);
      this.useDownloadDir = false;
      this.isInitialized = true;
      logger.info(TAG, `小说缓存目录初始化(沙箱目录): ${this.novelsCacheDir}`);
    } catch (error) {
      logger.error(TAG, `初始化缓存目录失败: ${String(error)}`);
    }
  }
  
  /**
   * 创建.nomedia文件
   * 防止系统媒体扫描器将目录识别为媒体文件夹
   */
  private createNoMediaFile(folderPath: string): void {
    try {
      const nomediaPath = `${folderPath}/.nomedia`;
      try {
        SafeFileUtils.accessSync(nomediaPath);
      } catch (e) {
        // 文件不存在，创建它
        const file = SafeFileUtils.openSync(nomediaPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
        SafeFileUtils.closeSync(file);
        logger.debug(TAG, `.nomedia文件已创建: ${nomediaPath}`);
      }
    } catch (error) {
      logger.warn(TAG, `创建.nomedia文件失败: ${folderPath}, ${String(error)}`);
    }
  }
  
  /**
   * 确保缓存目录已初始化
   */
  private async ensureInitialized(): Promise<void> {
    if (this.isInitialized) return;
    if (this.initPromise) {
      await this.initPromise;
    } else {
      await this.initCacheDir();
    }
  }

  static getInstance(): NovelChapterCacheManager {
    if (!NovelChapterCacheManager.instance) {
      NovelChapterCacheManager.instance = new NovelChapterCacheManager();
    }
    return NovelChapterCacheManager.instance;
  }

  /**
   * 获取书籍缓存目录路径
   * 格式: Download/novel/{safeBookId}/ 或 /files/novels/{safeBookId}/
   */
  private getBookCacheDir(bookId: string): string {
    // 将bookId转换为安全的目录名（移除特殊字符）
    const safeBookId = this.sanitizeFileName(bookId);
    return `${this.novelsCacheDir}/${safeBookId}`;
  }
  
  /**
   * [新增] 检查是否使用Download目录
   */
  isUsingDownloadDir(): boolean {
    return this.useDownloadDir;
  }
  
  /**
   * 获取章节文件路径
   * 格式: /files/novels/{safeBookId}/chapters/{chapterIndex}.txt
   */
  private getChapterFilePath(bookId: string, chapterIndex: number): string {
    const bookDir = this.getBookCacheDir(bookId);
    // 使用4位数字格式化章节索引，如 0001.txt, 0002.txt
    const chapterFileName = String(chapterIndex + 1).padStart(4, '0') + '.txt';
    return `${bookDir}/chapters/${chapterFileName}`;
  }

  private getAudioCacheDir(bookId: string): string {
    return `${this.getBookCacheDir(bookId)}/audio`;
  }

  private getAudioCacheIndexPath(bookId: string): string {
    return `${this.getAudioCacheDir(bookId)}/audio_index.json`;
  }

  private getAudioCacheFileName(chapterIndex: number, extension: string): string {
    const safeExtension = this.normalizeAudioExtension(extension);
    const baseName = String(chapterIndex + 1).padStart(4, '0');
    return `${baseName}.${safeExtension}`;
  }

  private getAudioCacheFilePath(bookId: string, fileName: string): string {
    return `${this.getAudioCacheDir(bookId)}/${fileName}`;
  }

  private normalizeAudioExtension(extension: string): string {
    const normalized = extension.trim().replace(/^\./, '').toLowerCase();
    if (normalized.length <= 0) {
      return 'm4a';
    }
    if (/^[a-z0-9]{1,8}$/.test(normalized)) {
      return normalized;
    }
    return 'm4a';
  }

  private extractAudioExtensionFromUrl(url: string): string {
    const cleaned = url.trim();
    if (cleaned.length <= 0) {
      return 'm4a';
    }
    const urlNoQuery = cleaned.split('?')[0].split('#')[0];
    const slashIndex = urlNoQuery.lastIndexOf('/');
    const fileName = slashIndex >= 0 ? urlNoQuery.substring(slashIndex + 1) : urlNoQuery;
    const dotIndex = fileName.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex >= fileName.length - 1) {
      return 'm4a';
    }
    return this.normalizeAudioExtension(fileName.substring(dotIndex + 1));
  }

  private extractChapterIndexFromCacheFileName(fileName: string): number {
    const nameOnly = fileName.includes('.') ? fileName.substring(0, fileName.indexOf('.')) : fileName;
    const parsed = parseInt(nameOnly, 10);
    if (isNaN(parsed)) {
      return -1;
    }
    return parsed - 1;
  }
  
  /**
   * 将字符串转换为安全的文件名
   */
  private sanitizeFileName(name: string): string {
    // 移除或替换不安全的字符
    return name
      .replace(/[<>:"/\\|?*]/g, '_')
      .replace(/%/g, '_')
      .replace(/\s+/g, '_')
      .substring(0, 100); // 限制长度
  }

  private decodeLegacyBookUrlFromCompositeId(bookId: string): string {
    const separatorIndex = bookId.indexOf('_');
    if (separatorIndex <= 0 || separatorIndex >= bookId.length - 1) {
      return '';
    }
    const encodedBookUrl = bookId.substring(separatorIndex + 1).trim();
    if (encodedBookUrl.length <= 0) {
      return '';
    }
    let decodedBookUrl = '';
    try {
      decodedBookUrl = decodeURIComponent(encodedBookUrl);
    } catch (_error) {
      return '';
    }
    const normalized = decodedBookUrl.trim();
    if (
      normalized.length <= 0 ||
      normalized === bookId ||
      (!normalized.startsWith('http://') && !normalized.startsWith('https://') && !normalized.startsWith('file://'))
    ) {
      return '';
    }
    return normalized;
  }

  private getCompatibleBookIds(bookId: string): string[] {
    const ids: string[] = [bookId];
    const legacyBookUrl = this.decodeLegacyBookUrlFromCompositeId(bookId);
    if (legacyBookUrl.length > 0 && legacyBookUrl !== bookId) {
      ids.push(legacyBookUrl);
    }
    return ids;
  }

  private getSourceType(sourceId: string): LegadoBookSourceType {
    const source = this.sourceManager.getSource(sourceId);
    if (!source) {
      return LegadoBookSourceType.TEXT;
    }
    return source.bookSourceType;
  }

  private looksLikeAudioUrlCandidate(raw: string): boolean {
    const value = raw.trim();
    if (value.length <= 0) {
      return false;
    }
    if (
      value.startsWith('http://') ||
      value.startsWith('https://') ||
      value.startsWith('file://') ||
      value.startsWith('data:audio/') ||
      value.startsWith('//')
    ) {
      return true;
    }
    if (value.indexOf('://') > 0 && value.indexOf(' ') < 0) {
      return true;
    }
    const lower = value.toLowerCase();
    return lower.indexOf('.mp3') >= 0 ||
      lower.indexOf('.m4a') >= 0 ||
      lower.indexOf('.aac') >= 0 ||
      lower.indexOf('.wav') >= 0 ||
      lower.indexOf('.ogg') >= 0 ||
      lower.indexOf('.flac') >= 0 ||
      lower.indexOf('.m3u8') >= 0;
  }

  private resolveAudioUrlCandidate(raw: string, baseUrl: string): string {
    const trimmed = raw.trim();
    if (trimmed.length <= 0) {
      return '';
    }
    if (
      trimmed.startsWith('http://') ||
      trimmed.startsWith('https://') ||
      trimmed.startsWith('file://') ||
      trimmed.startsWith('data:audio/')
    ) {
      return trimmed;
    }
    const baseMatch = /^(https?:\/\/[^/]+)(\/.*)?$/i.exec(baseUrl);
    if (trimmed.startsWith('//')) {
      const protocol = baseMatch && baseMatch.length > 1 && baseMatch[1].startsWith('http://')
        ? 'http:'
        : 'https:';
      return `${protocol}${trimmed}`;
    }
    if (!baseMatch || baseMatch.length <= 1) {
      return trimmed;
    }
    const host = baseMatch[1];
    const path = baseMatch.length > 2 && baseMatch[2] ? baseMatch[2] : '/';
    if (trimmed.startsWith('/')) {
      return `${host}${trimmed}`;
    }
    const slashIndex = path.lastIndexOf('/');
    const parentPath = slashIndex >= 0 ? path.substring(0, slashIndex + 1) : '/';
    return `${host}${parentPath}${trimmed}`;
  }

  private collectAudioUrlHints(payload: AudioJsonValue, urlHints: string[]): void {
    if (payload === null || payload === undefined) {
      return;
    }
    if (Array.isArray(payload)) {
      const payloadArray = payload as Array<Object>;
      for (let index = 0; index < payloadArray.length; index++) {
        this.collectAudioUrlHints(payloadArray[index] as AudioJsonValue, urlHints);
      }
      return;
    }
    if (typeof payload === 'string') {
      const text = payload.trim();
      if (text.length > 0 && this.looksLikeAudioUrlCandidate(text)) {
        urlHints.push(text);
      }
      return;
    }
    if (typeof payload !== 'object') {
      return;
    }

    const record = payload as AudioJsonRecord;
    const keys = Object.keys(record);
    for (let index = 0; index < keys.length; index++) {
      const key = keys[index];
      const value = record[key];
      if (typeof value === 'string') {
        const text = value.trim();
        const lowerKey = key.toLowerCase();
        if (text.length > 0) {
          if (
            lowerKey === 'url' ||
            lowerKey === 'audio' ||
            lowerKey === 'audio_url' ||
            lowerKey === 'playurl' ||
            lowerKey === 'play_url' ||
            lowerKey.endsWith('_url') ||
            lowerKey.indexOf('audio') >= 0 ||
            lowerKey.indexOf('play') >= 0
          ) {
            urlHints.push(text);
          } else if (this.looksLikeAudioUrlCandidate(text)) {
            urlHints.push(text);
          }
        }
      }
      this.collectAudioUrlHints(value, urlHints);
    }
  }

  private tryExtractAudioUrlFromJson(rawContent: string, baseUrl: string): string {
    if (!rawContent || rawContent.trim().length <= 0) {
      return '';
    }
    try {
      const parsed = SafeUtils.parseObj(rawContent) as AudioJsonValue;
      const urlHints: string[] = [];
      this.collectAudioUrlHints(parsed, urlHints);
      for (let index = 0; index < urlHints.length; index++) {
        const resolved = this.resolveAudioUrlCandidate(urlHints[index], baseUrl);
        if (resolved.length > 0) {
          return resolved;
        }
      }
    } catch {
      return '';
    }
    return '';
  }

  private resolveAudioSourceUrl(rawContent: string, baseUrl: string): string {
    const text = rawContent ? rawContent.trim() : '';
    if (text.length <= 0) {
      return '';
    }

    const fromJson = this.tryExtractAudioUrlFromJson(text, baseUrl);
    if (fromJson.length > 0) {
      return fromJson;
    }

    const urlMatch = /(https?:\/\/[^\s"'<>]+)/i.exec(text);
    if (urlMatch && urlMatch.length > 1) {
      return this.resolveAudioUrlCandidate(urlMatch[1], baseUrl);
    }

    const lines = text.split('\n');
    for (let index = 0; index < lines.length; index++) {
      const line = lines[index].trim();
      if (this.looksLikeAudioUrlCandidate(line)) {
        return this.resolveAudioUrlCandidate(line, baseUrl);
      }
    }

    if (this.looksLikeAudioUrlCandidate(text)) {
      return this.resolveAudioUrlCandidate(text, baseUrl);
    }

    return '';
  }

  private buildAudioRequestHeaders(sourceId: string, audioUrl: string): Record<string, string> {
    const headers: Record<string, string> = {};
    headers['User-Agent'] = 'Mozilla/5.0 (Linux; Android 11; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/110.0.0.0 Mobile Safari/537.36';

    const source = this.sourceManager.getSource(sourceId);
    if (source && source.header && source.header.trim().length > 0) {
      try {
        const parsed = SafeUtils.parseObj(source.header) as Record<string, string>;
        const keys = Object.keys(parsed);
        for (let index = 0; index < keys.length; index++) {
          const key = keys[index];
          const value = parsed[key];
          if (value && String(value).trim().length > 0) {
            headers[key] = String(value);
          }
        }
      } catch (error) {
        logger.warn(TAG, `解析书源请求头失败，使用默认请求头: ${String(error)}`);
      }
    }

    if (!Object.keys(headers).includes('Referer') && source?.bookSourceUrl) {
      headers['Referer'] = source.bookSourceUrl;
    }
    if (!Object.keys(headers).includes('Accept')) {
      headers['Accept'] = '*/*';
    }
    if (audioUrl.startsWith('https://') && !Object.keys(headers).includes('Origin')) {
      const match = /^(https?:\/\/[^/]+)/i.exec(audioUrl);
      if (match && match.length > 1) {
        headers['Origin'] = match[1];
      }
    }
    return headers;
  }

  private async downloadAudioBuffer(audioUrl: string, headers: Record<string, string>): Promise<ArrayBuffer | null> {
    const request = http.createHttp();
    try {
      const response = await request.request(audioUrl, {
        method: http.RequestMethod.GET,
        header: headers,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 20000,
        readTimeout: 120000
      });
      if (response.responseCode < 200 || response.responseCode >= 300 || !response.result) {
        logger.warn(TAG, `音频下载失败: code=${response.responseCode}, url=${audioUrl}`);
        return null;
      }
      if (response.result instanceof ArrayBuffer) {
        return response.result;
      }
      if (typeof response.result === 'string') {
        const encoder = new util.TextEncoder();
        const encoded = encoder.encodeInto(response.result);
        return encoded.buffer;
      }
      logger.warn(TAG, `音频下载返回了非ArrayBuffer结果: ${typeof response.result}`);
      return null;
    } catch (error) {
      logger.error(TAG, `音频下载异常: ${String(error)}, url=${audioUrl}`);
      return null;
    } finally {
      request.destroy();
    }
  }

  private async loadAudioCacheIndex(bookId: string): Promise<AudioChapterCacheIndex> {
    const emptyIndex: AudioChapterCacheIndex = {
      updateTime: 0,
      items: []
    };
    try {
      await this.ensureInitialized();
      const indexPath = this.getAudioCacheIndexPath(bookId);
      if (!await this.sandboxManager.exists(indexPath)) {
        return emptyIndex;
      }
      const rawText = await this.sandboxManager.readTextFile(indexPath);
      if (!rawText || rawText.trim().length <= 0) {
        return emptyIndex;
      }
      const parsed = SafeUtils.parseObj(rawText) as Record<string, Object>;
      const updateTime = Number(parsed['updateTime']) || 0;
      const itemsRaw = parsed['items'];
      const items: AudioChapterCacheItem[] = [];
      if (Array.isArray(itemsRaw)) {
        const itemArray = itemsRaw as Array<Object>;
        for (let index = 0; index < itemArray.length; index++) {
          const itemRaw = itemArray[index];
          if (!itemRaw || typeof itemRaw !== 'object') {
            continue;
          }
          const itemRecord = itemRaw as Record<string, Object>;
          const chapterIndex = Number(itemRecord['chapterIndex']);
          const fileName = String(itemRecord['fileName'] ?? '');
          if (isNaN(chapterIndex) || chapterIndex < 0 || fileName.trim().length <= 0) {
            continue;
          }
          items.push({
            chapterIndex: chapterIndex,
            fileName: fileName.trim(),
            sourceUrl: String(itemRecord['sourceUrl'] ?? ''),
            mimeType: String(itemRecord['mimeType'] ?? ''),
            fileSize: Number(itemRecord['fileSize']) || 0,
            updateTime: Number(itemRecord['updateTime']) || 0
          });
        }
      }
      return {
        updateTime,
        items
      };
    } catch (error) {
      logger.warn(TAG, `读取音频缓存索引失败: ${String(error)}`);
      return emptyIndex;
    }
  }

  private async saveAudioCacheIndex(bookId: string, cacheIndex: AudioChapterCacheIndex): Promise<void> {
    try {
      await this.ensureInitialized();
      const audioDir = this.getAudioCacheDir(bookId);
      await this.sandboxManager.createDirectory(audioDir);
      const indexPath = this.getAudioCacheIndexPath(bookId);
      await this.sandboxManager.writeFile(indexPath, JSON.stringify(cacheIndex));
    } catch (error) {
      logger.warn(TAG, `保存音频缓存索引失败: ${String(error)}`);
    }
  }

  private async resolveAudioCachePathByIndex(bookId: string, chapterIndex: number): Promise<string | null> {
    const indexData = await this.loadAudioCacheIndex(bookId);
    for (let i = 0; i < indexData.items.length; i++) {
      const item = indexData.items[i];
      if (item.chapterIndex === chapterIndex) {
        const path = this.getAudioCacheFilePath(bookId, item.fileName);
        if (await this.sandboxManager.exists(path)) {
          return path;
        }
      }
    }

    const audioDir = this.getAudioCacheDir(bookId);
    if (!await this.sandboxManager.exists(audioDir)) {
      return null;
    }
    const expectedPrefix = `${String(chapterIndex + 1).padStart(4, '0')}.`;
    const files = await fileIo.listFile(audioDir);
    for (let fileIndex = 0; fileIndex < files.length; fileIndex++) {
      const fileName = files[fileIndex];
      if (!fileName.startsWith(expectedPrefix)) {
        continue;
      }
      if (fileName.endsWith('.json')) {
        continue;
      }
      const filePath = this.getAudioCacheFilePath(bookId, fileName);
      if (await this.sandboxManager.exists(filePath)) {
        return filePath;
      }
    }
    return null;
  }

  async getChapterAudioCachePath(bookId: string, chapterIndex: number): Promise<string | null> {
    try {
      await this.ensureInitialized();
      const candidateBookIds = this.getCompatibleBookIds(bookId);
      for (let i = 0; i < candidateBookIds.length; i++) {
        const candidateBookId = candidateBookIds[i];
        const path = await this.resolveAudioCachePathByIndex(candidateBookId, chapterIndex);
        if (path && path.length > 0) {
          if (candidateBookId !== bookId) {
            logger.debug(
              TAG,
              `音频缓存命中兼容路径: compositeBookId=${bookId}, legacyBookUrl=${candidateBookId}, chapter=${chapterIndex + 1}`
            );
          }
          return path;
        }
      }
      return null;
    } catch (error) {
      logger.warn(TAG, `获取音频缓存路径失败: ${String(error)}`);
      return null;
    }
  }

  async isAudioChapterCached(bookId: string, chapterIndex: number): Promise<boolean> {
    const path = await this.getChapterAudioCachePath(bookId, chapterIndex);
    return !!path && path.length > 0;
  }

  private async cacheAudioChapter(
    sourceId: string,
    bookId: string,
    chapter: LegadoChapter
  ): Promise<boolean> {
    try {
      const cachedPath = await this.getChapterAudioCachePath(bookId, chapter.index);
      if (cachedPath && cachedPath.length > 0) {
        logger.debug(TAG, `音频章节已缓存: ${chapter.title}`);
        return true;
      }

      const content = await this.sourceManager.getContent(sourceId, chapter);
      let audioUrl = this.resolveAudioSourceUrl(content, chapter.url);
      if (audioUrl.length <= 0 && this.looksLikeAudioUrlCandidate(chapter.url)) {
        audioUrl = this.resolveAudioUrlCandidate(chapter.url, chapter.url);
      }
      if (audioUrl.length <= 0) {
        logger.warn(TAG, `未解析到可缓存的音频URL: ${chapter.title}`);
        return false;
      }

      const extension = this.extractAudioExtensionFromUrl(audioUrl);
      const fileName = this.getAudioCacheFileName(chapter.index, extension);
      const targetPath = this.getAudioCacheFilePath(bookId, fileName);
      const headers = this.buildAudioRequestHeaders(sourceId, audioUrl);
      const audioBuffer = await this.downloadAudioBuffer(audioUrl, headers);
      if (!audioBuffer || audioBuffer.byteLength <= 0) {
        logger.warn(TAG, `音频下载结果为空: ${chapter.title}`);
        return false;
      }
      await this.sandboxManager.writeFile(targetPath, audioBuffer);

      const currentIndex = await this.loadAudioCacheIndex(bookId);
      const nextItems: AudioChapterCacheItem[] = [];
      for (let i = 0; i < currentIndex.items.length; i++) {
        const item = currentIndex.items[i];
        if (item.chapterIndex !== chapter.index) {
          nextItems.push(item);
        }
      }
      nextItems.push({
        chapterIndex: chapter.index,
        fileName: fileName,
        sourceUrl: audioUrl,
        mimeType: extension === 'm3u8' ? 'application/vnd.apple.mpegurl' : `audio/${extension}`,
        fileSize: audioBuffer.byteLength,
        updateTime: Date.now()
      });
      await this.saveAudioCacheIndex(bookId, {
        updateTime: Date.now(),
        items: nextItems
      });

      logger.info(TAG, `音频章节缓存成功: ${chapter.title}, size=${audioBuffer.byteLength}`);
      return true;
    } catch (error) {
      logger.error(TAG, `缓存音频章节失败: ${chapter.title}, ${String(error)}`);
      return false;
    }
  }

  /**
   * 缓存单个章节内容（保存为txt文件）
   */
  async cacheChapter(
    sourceId: string,
    bookId: string,
    chapter: LegadoChapter
  ): Promise<boolean> {
    try {
      // 确保缓存目录已初始化
      await this.ensureInitialized();

      if (this.getSourceType(sourceId) === LegadoBookSourceType.AUDIO) {
        return await this.cacheAudioChapter(sourceId, bookId, chapter);
      }

      // 检查是否已缓存
      const cached = await this.getChapterCache(bookId, chapter.index);
      if (cached) {
        logger.debug(TAG, `章节已缓存: ${chapter.title}`);
        return true;
      }

      // 获取章节内容
      const content = await this.sourceManager.getContent(sourceId, chapter);
      if (!content) {
        logger.warn(TAG, `获取章节内容失败: ${chapter.title}`);
        return false;
      }

      // 保存到txt文件
      await this.saveChapterToFile(bookId, chapter.index, chapter.title, content);

      logger.info(TAG, `章节缓存成功: ${chapter.title}`);
      return true;
    } catch (error) {
      logger.error(TAG, `缓存章节失败: ${chapter.title}, ${String(error)}`);
      return false;
    }
  }

  /**
   * 检查章节是否已缓存（检查txt文件是否存在）
   */
  async isChapterCached(bookId: string, chapterIndex: number): Promise<boolean> {
    try {
      const filePath = this.getChapterFilePath(bookId, chapterIndex);
      if (await this.sandboxManager.exists(filePath)) {
        return true;
      }
      return await this.isAudioChapterCached(bookId, chapterIndex);
    } catch (error) {
      return false;
    }
  }

  /**
   * 获取已缓存的章节索引列表（扫描chapters目录）
   */
  async getCachedChapterIndexes(bookId: string, totalChapters: number): Promise<Set<number>> {
    const cachedIndexes = new Set<number>();
    try {
      // 确保缓存目录已初始化
      await this.ensureInitialized();
      const maxIndex = totalChapters > 0 ? totalChapters : Number.MAX_SAFE_INTEGER;

      const candidateBookIds = this.getCompatibleBookIds(bookId);
      for (let i = 0; i < candidateBookIds.length; i++) {
        const candidateBookId = candidateBookIds[i];
        const bookDir = this.getBookCacheDir(candidateBookId);
        const chaptersDir = `${bookDir}/chapters`;

        // 检查目录是否存在
        if (await this.sandboxManager.exists(chaptersDir)) {
          // 列出目录中的所有txt文件
          const files = await fileIo.listFile(chaptersDir);
          for (let fileIndex = 0; fileIndex < files.length; fileIndex++) {
            const fileName = files[fileIndex];
            if (!fileName.endsWith('.txt')) {
              continue;
            }
            // 从文件名提取章节索引（0001.txt -> 0）
            const index = this.extractChapterIndexFromCacheFileName(fileName);
            if (!isNaN(index) && index >= 0 && index < maxIndex) {
              cachedIndexes.add(index);
            }
          }
        }

        const audioDir = this.getAudioCacheDir(candidateBookId);
        if (await this.sandboxManager.exists(audioDir)) {
          const audioFiles = await fileIo.listFile(audioDir);
          for (let fileIndex = 0; fileIndex < audioFiles.length; fileIndex++) {
            const fileName = audioFiles[fileIndex];
            if (fileName.endsWith('.json')) {
              continue;
            }
            const index = this.extractChapterIndexFromCacheFileName(fileName);
            if (!isNaN(index) && index >= 0 && index < maxIndex) {
              cachedIndexes.add(index);
            }
          }
        }
      }
      
      logger.debug(TAG, `书籍 ${bookId} 已缓存 ${cachedIndexes.size} 章`);
    } catch (error) {
      logger.error(TAG, `获取缓存章节列表失败: ${String(error)}`);
    }
    return cachedIndexes;
  }

  /**
   * 获取章节缓存内容（从txt文件读取）
   * @param bookIdOrChapterId 可以是bookId或旧格式的chapterId
   * @param chapterIndex 章节索引（如果第一个参数是bookId）
   */
  async getChapterCache(bookIdOrChapterId: string, chapterIndex?: number): Promise<string | null> {
    try {
      // 确保缓存目录已初始化
      await this.ensureInitialized();
      
      let bookId: string;
      let index: number;
      
      if (chapterIndex !== undefined) {
        // 新格式：bookId + chapterIndex
        bookId = bookIdOrChapterId;
        index = chapterIndex;
      } else {
        // 旧格式兼容：chapterId = bookId_chapterIndex
        const parts = bookIdOrChapterId.split('_');
        if (parts.length < 2) {
          logger.warn(TAG, `无效的chapterId格式: ${bookIdOrChapterId}`);
          return null;
        }
        index = parseInt(parts[parts.length - 1], 10);
        bookId = parts.slice(0, -1).join('_');
      }

      const candidateBookIds = this.getCompatibleBookIds(bookId);
      for (let i = 0; i < candidateBookIds.length; i++) {
        const candidateBookId = candidateBookIds[i];
        const filePath = this.getChapterFilePath(candidateBookId, index);

        // 检查文件是否存在
        if (!await this.sandboxManager.exists(filePath)) {
          continue;
        }

        // 读取txt文件内容
        const content = await this.sandboxManager.readTextFile(filePath);
        if (candidateBookId !== bookId) {
          logger.info(
            TAG,
            `章节缓存命中兼容路径: compositeBookId=${bookId}, legacyBookUrl=${candidateBookId}, chapter=${index + 1}`
          );
        } else {
          logger.info(TAG, `✅ 缓存命中: ${filePath}, 内容长度=${content?.length || 0}`);
        }
        return content;
      }

      const missPath = this.getChapterFilePath(bookId, index);
      logger.debug(TAG, `缓存未命中: ${missPath}`);
      return null;
    } catch (error) {
      logger.error(TAG, `获取章节缓存失败: ${String(error)}`);
      return null;
    }
  }

  /**
   * 保存章节内容到txt文件
   */
  private async saveChapterToFile(
    bookId: string,
    chapterIndex: number,
    chapterTitle: string,
    content: string
  ): Promise<void> {
    try {
      const bookDir = this.getBookCacheDir(bookId);
      const chaptersDir = `${bookDir}/chapters`;
      
      // 确保目录存在
      await this.sandboxManager.createDirectory(chaptersDir);
      
      // 构建文件内容（包含章节标题）
      const fileContent = `${chapterTitle}\n\n${content}`;
      
      // 写入txt文件
      const filePath = this.getChapterFilePath(bookId, chapterIndex);
      await this.sandboxManager.writeFile(filePath, fileContent);
      
      logger.debug(TAG, `章节保存成功: ${filePath}`);
    } catch (error) {
      logger.error(TAG, `保存章节文件失败: ${String(error)}`);
      throw error as Error;
    }
  }

  /**
   * 创建下载任务
   */
  createDownloadTask(
    bookId: string,
    bookName: string,
    startIndex: number,
    endIndex: number
  ): string {
    const taskId = `download_${Date.now()}_${Math.random().toString(36).substring(2, 9)}`;
    const now = Date.now();

    const task: NovelDownloadTask = {
      id: taskId,
      bookId: bookId,
      bookName: bookName,
      startChapterIndex: startIndex,
      endChapterIndex: endIndex,
      currentChapterIndex: startIndex,
      status: 'pending',
      progress: 0,
      createTime: now,
      updateTime: now
    };

    this.downloadTasks.set(taskId, task);
    logger.info(TAG, `创建下载任务: ${bookName}, 章节 ${startIndex}-${endIndex}`);
    return taskId;
  }

  /**
   * 开始下载任务
   * @param taskId 任务ID
   * @param sourceId 书源ID
   * @param chapters 要下载的章节列表（已筛选的章节）
   * @param callback 进度回调
   */
  async startDownload(
    taskId: string,
    sourceId: string,
    chapters: LegadoChapter[],
    callback?: DownloadProgressCallback
  ): Promise<void> {
    const task = this.downloadTasks.get(taskId);
    if (!task) {
      logger.error(TAG, `下载任务不存在: ${taskId}`);
      return;
    }

    if (this.activeDownloads.has(taskId)) {
      logger.warn(TAG, `下载任务已在进行中: ${taskId}`);
      return;
    }

    if (callback) {
      this.downloadCallbacks.set(taskId, callback);
    }

    task.status = 'downloading';
    this.activeDownloads.add(taskId);

    try {
      // 直接使用传入的 chapters 数组，它已经是筛选后的章节列表
      const total = chapters.length;
      let successCount = 0;
      let failCount = 0;

      for (let i = 0; i < chapters.length; i++) {
        // 检查任务是否被暂停或取消
        const currentTask = this.downloadTasks.get(taskId);
        if (!currentTask || currentTask.status === 'paused') {
          logger.info(TAG, `下载任务已暂停: ${taskId}`);
          break;
        }

        const chapter = chapters[i];
        if (!chapter) continue;

        // 下载章节
        const success = await this.cacheChapter(sourceId, task.bookId, chapter);
        
        task.currentChapterIndex = chapter.index; // 使用章节自身的索引
        task.progress = ((i + 1) / total) * 100;
        task.updateTime = Date.now();

        if (success) {
          successCount++;
          // 回调进度
          const cb = this.downloadCallbacks.get(taskId);
          if (cb) {
            cb.onProgress(i + 1, total, chapter.title);
          }
        } else {
          failCount++;
          logger.warn(TAG, `章节下载失败: ${chapter.title} (${failCount}/${total})`);
        }

        // 添加延迟避免请求过快
        await this.delay(500);
      }

      // 完成下载（即使有部分失败也标记为完成）
      if (failCount > 0 && failCount === total) {
        // 全部失败
        task.status = 'failed';
        task.errorMessage = `全部 ${failCount} 章下载失败`;
        logger.error(TAG, `下载任务失败: ${task.bookName}, 全部 ${failCount} 章下载失败`);
        
        // 发送详细失败通知
        this.notificationManager.sendDetailedDownloadCompleteNotification(
          taskId, 
          task.bookName,
          'novel',
          successCount,
          failCount,
          task.startChapterIndex,
          task.endChapterIndex
        );
        
        const cb = this.downloadCallbacks.get(taskId);
        if (cb) {
          cb.onError(`全部 ${failCount} 章下载失败`);
        }
      } else if (failCount > 0) {
        // 部分失败
        task.status = 'completed';
        task.progress = 100;
        task.errorMessage = `${failCount} 章下载失败`;
        logger.warn(TAG, `下载任务完成（部分失败）: ${task.bookName}, 成功 ${successCount}/${total}, 失败 ${failCount}`);
        
        // 发送详细完成通知（带警告）
        this.notificationManager.sendDetailedDownloadCompleteNotification(
          taskId, 
          task.bookName,
          'novel',
          successCount,
          failCount,
          task.startChapterIndex,
          task.endChapterIndex
        );
        
        const cb = this.downloadCallbacks.get(taskId);
        if (cb) {
          cb.onComplete();
        }
      } else {
        // 全部成功
        task.status = 'completed';
        task.progress = 100;
        logger.info(TAG, `下载任务完成: ${task.bookName}, 成功 ${successCount}/${total}`);
        
        // 发送详细完成通知
        this.notificationManager.sendDetailedDownloadCompleteNotification(
          taskId, 
          task.bookName,
          'novel',
          successCount,
          failCount,
          task.startChapterIndex,
          task.endChapterIndex
        );
        
        const cb = this.downloadCallbacks.get(taskId);
        if (cb) {
          cb.onComplete();
        }
      }
      task.updateTime = Date.now();
    } catch (error) {
      task.status = 'failed';
      task.errorMessage = String(error);
      task.updateTime = Date.now();

      // 发送失败通知
      this.notificationManager.sendDownloadFailedNotification(taskId, task.bookName, String(error));

      const cb = this.downloadCallbacks.get(taskId);
      if (cb) {
        cb.onError(String(error));
      }

      logger.error(TAG, `下载任务失败: ${String(error)}`);
    } finally {
      this.activeDownloads.delete(taskId);
    }
  }

  /**
   * 暂停下载任务
   */
  pauseDownload(taskId: string): void {
    const task = this.downloadTasks.get(taskId);
    if (task && task.status === 'downloading') {
      task.status = 'paused';
      task.updateTime = Date.now();
      logger.info(TAG, `下载任务已暂停: ${taskId}`);
    }
  }

  /**
   * 取消下载任务
   */
  cancelDownload(taskId: string): void {
    const task = this.downloadTasks.get(taskId);
    if (task) {
      task.status = 'failed';
      task.errorMessage = '用户取消';
      task.updateTime = Date.now();
      this.activeDownloads.delete(taskId);
      this.downloadCallbacks.delete(taskId);
      logger.info(TAG, `下载任务已取消: ${taskId}`);
    }
  }

  /**
   * 获取下载任务状态
   */
  getDownloadTask(taskId: string): NovelDownloadTask | undefined {
    return this.downloadTasks.get(taskId);
  }

  /**
   * 获取所有下载任务
   */
  getAllDownloadTasks(): NovelDownloadTask[] {
    return Array.from(this.downloadTasks.values());
  }

  /**
   * 获取书籍缓存信息（从文件系统读取）
   */
  async getBookCacheInfo(bookId: string): Promise<NovelCacheInfo> {
    try {
      await this.ensureInitialized();
      const bookDir = this.getBookCacheDir(bookId);
      const chaptersDir = `${bookDir}/chapters`;
      const audioDir = this.getAudioCacheDir(bookId);

      const cachedTextIndexes = new Set<number>();
      const cachedAudioIndexes = new Set<number>();
      let textCacheSize = 0;
      let audioCacheSize = 0;
      let lastCacheTime = 0;

      if (await this.sandboxManager.exists(chaptersDir)) {
        const textFiles = await fileIo.listFile(chaptersDir);
        for (let fileIndex = 0; fileIndex < textFiles.length; fileIndex++) {
          const fileName = textFiles[fileIndex];
          if (!fileName.endsWith('.txt')) {
            continue;
          }
          const chapterIndex = this.extractChapterIndexFromCacheFileName(fileName);
          if (chapterIndex >= 0) {
            cachedTextIndexes.add(chapterIndex);
          }
          const filePath = `${chaptersDir}/${fileName}`;
          try {
            const stat = await fileIo.stat(filePath);
            textCacheSize += stat.size;
            if (stat.mtime > lastCacheTime) {
              lastCacheTime = stat.mtime;
            }
          } catch (_error) {
          }
        }
      }

      if (await this.sandboxManager.exists(audioDir)) {
        const audioFiles = await fileIo.listFile(audioDir);
        for (let fileIndex = 0; fileIndex < audioFiles.length; fileIndex++) {
          const fileName = audioFiles[fileIndex];
          if (fileName.endsWith('.json')) {
            continue;
          }
          const chapterIndex = this.extractChapterIndexFromCacheFileName(fileName);
          if (chapterIndex >= 0) {
            cachedAudioIndexes.add(chapterIndex);
          }
          const filePath = `${audioDir}/${fileName}`;
          try {
            const stat = await fileIo.stat(filePath);
            audioCacheSize += stat.size;
            if (stat.mtime > lastCacheTime) {
              lastCacheTime = stat.mtime;
            }
          } catch (_error) {
          }
        }
      }

      const audioIndexPath = this.getAudioCacheIndexPath(bookId);
      if (await this.sandboxManager.exists(audioIndexPath)) {
        try {
          const stat = await fileIo.stat(audioIndexPath);
          if (stat.mtime > lastCacheTime) {
            lastCacheTime = stat.mtime;
          }
        } catch (_error) {
        }
      }

      const mergedIndexes = new Set<number>();
      cachedTextIndexes.forEach((index: number) => mergedIndexes.add(index));
      cachedAudioIndexes.forEach((index: number) => mergedIndexes.add(index));

      let cacheKind: 'text' | 'audio' | 'mixed' | undefined = undefined;
      if (cachedTextIndexes.size > 0 && cachedAudioIndexes.size > 0) {
        cacheKind = 'mixed';
      } else if (cachedAudioIndexes.size > 0) {
        cacheKind = 'audio';
      } else if (cachedTextIndexes.size > 0) {
        cacheKind = 'text';
      }

      return {
        bookId: bookId,
        cachedChapterCount: mergedIndexes.size,
        totalChapterCount: 0,
        cacheSize: textCacheSize + audioCacheSize,
        lastCacheTime: lastCacheTime,
        cachedTextChapterCount: cachedTextIndexes.size,
        cachedAudioChapterCount: cachedAudioIndexes.size,
        textCacheSize: textCacheSize,
        audioCacheSize: audioCacheSize,
        cacheKind: cacheKind
      };
    } catch (error) {
      logger.error(TAG, `获取缓存信息失败: ${String(error)}`);
      return {
        bookId: bookId,
        cachedChapterCount: 0,
        totalChapterCount: 0,
        cacheSize: 0,
        lastCacheTime: 0,
        cachedTextChapterCount: 0,
        cachedAudioChapterCount: 0,
        textCacheSize: 0,
        audioCacheSize: 0
      };
    }
  }

  /**
   * 清理过期缓存（基于文件修改时间）
   * 默认清理30天未访问的缓存
   */
  async cleanExpiredCache(maxAgeDays: number = 30): Promise<number> {
    try {
      await this.ensureInitialized();
      const expireTime = Date.now() - maxAgeDays * 24 * 60 * 60 * 1000;
      let count = 0;
      
      // 检查novels目录是否存在
      if (!await this.sandboxManager.exists(this.novelsCacheDir)) {
        return 0;
      }
      
      // 遍历所有书籍目录
      const bookDirs = await fileIo.listFile(this.novelsCacheDir);
      for (let bookDirIndex = 0; bookDirIndex < bookDirs.length; bookDirIndex++) {
        const bookDir = bookDirs[bookDirIndex];
        const baseDir = `${this.novelsCacheDir}/${bookDir}`;
        const chaptersDir = `${baseDir}/chapters`;
        if (await this.sandboxManager.exists(chaptersDir)) {
          const files = await fileIo.listFile(chaptersDir);
          for (let fileIndex = 0; fileIndex < files.length; fileIndex++) {
            const file = files[fileIndex];
            if (file.endsWith('.txt')) {
              const filePath = `${chaptersDir}/${file}`;
              try {
                const stat = await fileIo.stat(filePath);
                if (stat.mtime < expireTime) {
                  await fileIo.unlink(filePath);
                  count++;
                }
              } catch (_error) {
              }
            }
          }
        }

        const audioDir = `${baseDir}/audio`;
        if (await this.sandboxManager.exists(audioDir)) {
          const audioFiles = await fileIo.listFile(audioDir);
          for (let fileIndex = 0; fileIndex < audioFiles.length; fileIndex++) {
            const fileName = audioFiles[fileIndex];
            if (fileName.endsWith('.json')) {
              continue;
            }
            const filePath = `${audioDir}/${fileName}`;
            try {
              const stat = await fileIo.stat(filePath);
              if (stat.mtime < expireTime) {
                await fileIo.unlink(filePath);
                count++;
              }
            } catch (_error) {
            }
          }

          const audioIndexPath = `${audioDir}/audio_index.json`;
          if (await this.sandboxManager.exists(audioIndexPath)) {
            try {
              const rawIndexText = await this.sandboxManager.readTextFile(audioIndexPath);
              if (rawIndexText && rawIndexText.trim().length > 0) {
                const parsed = SafeUtils.parseObj(rawIndexText) as Record<string, Object>;
                const itemsValue = parsed['items'];
                const filteredItems: AudioChapterCacheItem[] = [];
                let changed = false;
                if (Array.isArray(itemsValue)) {
                  const itemArray = itemsValue as Array<Object>;
                  for (let itemIndex = 0; itemIndex < itemArray.length; itemIndex++) {
                    const itemRaw = itemArray[itemIndex];
                    if (!itemRaw || typeof itemRaw !== 'object') {
                      changed = true;
                      continue;
                    }
                    const itemRecord = itemRaw as Record<string, Object>;
                    const chapterIndex = Number(itemRecord['chapterIndex']);
                    const fileName = String(itemRecord['fileName'] ?? '').trim();
                    if (isNaN(chapterIndex) || chapterIndex < 0 || fileName.length <= 0) {
                      changed = true;
                      continue;
                    }
                    const filePath = `${audioDir}/${fileName}`;
                    if (!await this.sandboxManager.exists(filePath)) {
                      changed = true;
                      continue;
                    }
                    filteredItems.push({
                      chapterIndex: chapterIndex,
                      fileName: fileName,
                      sourceUrl: String(itemRecord['sourceUrl'] ?? ''),
                      mimeType: String(itemRecord['mimeType'] ?? ''),
                      fileSize: Number(itemRecord['fileSize']) || 0,
                      updateTime: Number(itemRecord['updateTime']) || 0
                    });
                  }
                } else {
                  changed = true;
                }

                if (changed) {
                  if (filteredItems.length <= 0) {
                    const indexStat = await fileIo.stat(audioIndexPath);
                    if (indexStat.mtime < expireTime) {
                      await fileIo.unlink(audioIndexPath);
                      count++;
                    } else {
                      await this.sandboxManager.writeFile(audioIndexPath, JSON.stringify({
                        updateTime: Date.now(),
                        items: filteredItems
                      }));
                    }
                  } else {
                    await this.sandboxManager.writeFile(audioIndexPath, JSON.stringify({
                      updateTime: Date.now(),
                      items: filteredItems
                    }));
                  }
                }
              }
            } catch (error) {
              logger.warn(TAG, `整理音频缓存索引失败: ${audioIndexPath}, ${String(error)}`);
            }
          }
        }
      }

      logger.info(TAG, `清理过期缓存: ${count} 个文件`);
      return count;
    } catch (error) {
      logger.error(TAG, `清理过期缓存失败: ${String(error)}`);
      return 0;
    }
  }

  /**
   * 清理指定书籍的缓存（删除整个书籍目录）
   */
  async clearBookCache(bookId: string): Promise<void> {
    try {
      await this.ensureInitialized();
      const bookDir = this.getBookCacheDir(bookId);
      
      // 检查目录是否存在
      if (await this.sandboxManager.exists(bookDir)) {
        await this.sandboxManager.deleteDirectory(bookDir);
        logger.info(TAG, `清理书籍缓存: ${bookDir}`);
      }
    } catch (error) {
      logger.error(TAG, `清理书籍缓存失败: ${String(error)}`);
    }
  }

  /**
   * 清理章节列表缓存（不删除章节正文缓存）
   */
  async clearChapterListCache(bookId: string): Promise<void> {
    try {
      await this.ensureInitialized();
      const chapterListPath = `${this.getBookCacheDir(bookId)}/chapters_list.json`;
      if (await this.sandboxManager.exists(chapterListPath)) {
        await this.sandboxManager.deleteFile(chapterListPath);
        logger.info(TAG, `清理章节列表缓存: ${chapterListPath}`);
      }
    } catch (error) {
      logger.warn(TAG, `清理章节列表缓存失败: ${String(error)}`);
    }
  }

  async remapChapterIndexCaches(bookIds: string[], remaps: ChapterOrderIndexRemap[]): Promise<ChapterOrderCacheRemapResult> {
    const result: ChapterOrderCacheRemapResult = {
      textCacheMoved: 0,
      audioCacheMoved: 0,
      remoteReadAloudCacheMoved: 0,
      failedKeys: [],
      warnings: []
    };
    try {
      await this.ensureInitialized();
      const normalizedBookIds = this.normalizeBookIdList(bookIds);
      for (let index = 0; index < normalizedBookIds.length; index++) {
        const bookId = normalizedBookIds[index];
        await this.remapTextChapterFiles(bookId, remaps, result);
        await this.remapAudioChapterFiles(bookId, remaps, result);
      }
    } catch (error) {
      result.warnings.push(`小说缓存迁移入口失败: ${String(error)}`);
      logger.warn(TAG, `小说缓存迁移入口失败: ${String(error)}`);
    }
    return result;
  }

  private normalizeBookIdList(bookIds: string[]): string[] {
    const result: string[] = [];
    for (let index = 0; index < bookIds.length; index++) {
      const bookId = bookIds[index].trim();
      if (bookId.length <= 0) {
        continue;
      }
      if (!result.includes(bookId)) {
        result.push(bookId);
      }
    }
    return result;
  }

  private async remapTextChapterFiles(
    bookId: string,
    remaps: ChapterOrderIndexRemap[],
    result: ChapterOrderCacheRemapResult
  ): Promise<void> {
    const tempMoves: ChapterCacheTempMove[] = [];
    const now = Date.now();
    for (let index = 0; index < remaps.length; index++) {
      const remap = remaps[index];
      if (remap.oldIndex === remap.newIndex) {
        continue;
      }
      const sourcePath = this.getChapterFilePath(bookId, remap.oldIndex);
      if (!await this.sandboxManager.exists(sourcePath)) {
        continue;
      }
      const tempPath = `${sourcePath}.order_tmp_${now}_${index}`;
      const targetPath = this.getChapterFilePath(bookId, remap.newIndex);
      try {
        await this.sandboxManager.moveFile(sourcePath, tempPath);
        tempMoves.push({
          stableKey: remap.stableKey,
          sourcePath,
          tempPath,
          targetPath
        } as ChapterCacheTempMove);
      } catch (error) {
        this.appendUniqueFailure(result, remap.stableKey);
        result.warnings.push(`TXT缓存临时迁移失败: ${remap.title}, ${String(error)}`);
      }
    }

    for (let index = 0; index < tempMoves.length; index++) {
      const move = tempMoves[index];
      try {
        if (await this.sandboxManager.exists(move.targetPath)) {
          await this.sandboxManager.deleteFile(move.targetPath);
        }
        await this.sandboxManager.moveFile(move.tempPath, move.targetPath);
        result.textCacheMoved++;
      } catch (error) {
        this.appendUniqueFailure(result, move.stableKey);
        result.warnings.push(`TXT缓存落位失败: ${move.sourcePath} -> ${move.targetPath}, ${String(error)}`);
      }
    }
  }

  private async remapAudioChapterFiles(
    bookId: string,
    remaps: ChapterOrderIndexRemap[],
    result: ChapterOrderCacheRemapResult
  ): Promise<void> {
    const audioDir = this.getAudioCacheDir(bookId);
    if (!await this.sandboxManager.exists(audioDir)) {
      return;
    }
    const tempMoves: ChapterCacheTempMove[] = [];
    const movedSourcePaths = new Set<string>();
    const now = Date.now();
    const cacheIndex = await this.loadAudioCacheIndex(bookId);
    const nextItems: AudioChapterCacheItem[] = [];

    for (let itemIndex = 0; itemIndex < cacheIndex.items.length; itemIndex++) {
      const item = cacheIndex.items[itemIndex];
      const remap = this.findRemapByOldIndex(remaps, item.chapterIndex);
      if (!remap || remap.oldIndex === remap.newIndex) {
        nextItems.push(item);
        continue;
      }
      const sourcePath = this.getAudioCacheFilePath(bookId, item.fileName);
      const extension = this.extractAudioExtensionFromFileName(item.fileName);
      const nextFileName = this.getAudioCacheFileName(remap.newIndex, extension);
      const targetPath = this.getAudioCacheFilePath(bookId, nextFileName);
      const tempPath = `${sourcePath}.order_tmp_${now}_${itemIndex}`;
      if (await this.sandboxManager.exists(sourcePath)) {
        try {
          await this.sandboxManager.moveFile(sourcePath, tempPath);
          movedSourcePaths.add(sourcePath);
          tempMoves.push({
            stableKey: remap.stableKey,
            sourcePath,
            tempPath,
            targetPath
          } as ChapterCacheTempMove);
        } catch (error) {
          this.appendUniqueFailure(result, remap.stableKey);
          result.warnings.push(`音频缓存临时迁移失败: ${remap.title}, ${String(error)}`);
        }
      }
      nextItems.push({
        chapterIndex: remap.newIndex,
        fileName: nextFileName,
        sourceUrl: item.sourceUrl,
        mimeType: item.mimeType,
        fileSize: item.fileSize,
        updateTime: Date.now()
      } as AudioChapterCacheItem);
    }

    await this.collectFallbackAudioFileMoves(bookId, remaps, movedSourcePaths, tempMoves, now, result);
    for (let index = 0; index < tempMoves.length; index++) {
      const move = tempMoves[index];
      try {
        if (await this.sandboxManager.exists(move.targetPath)) {
          await this.sandboxManager.deleteFile(move.targetPath);
        }
        await this.sandboxManager.moveFile(move.tempPath, move.targetPath);
        result.audioCacheMoved++;
      } catch (error) {
        this.appendUniqueFailure(result, move.stableKey);
        result.warnings.push(`音频缓存落位失败: ${move.sourcePath} -> ${move.targetPath}, ${String(error)}`);
      }
    }

    nextItems.sort((left: AudioChapterCacheItem, right: AudioChapterCacheItem) => left.chapterIndex - right.chapterIndex);
    await this.saveAudioCacheIndex(bookId, {
      updateTime: Date.now(),
      items: nextItems
    } as AudioChapterCacheIndex);
  }

  private async collectFallbackAudioFileMoves(
    bookId: string,
    remaps: ChapterOrderIndexRemap[],
    movedSourcePaths: Set<string>,
    tempMoves: ChapterCacheTempMove[],
    now: number,
    result: ChapterOrderCacheRemapResult
  ): Promise<void> {
    const audioDir = this.getAudioCacheDir(bookId);
    const files = await this.sandboxManager.listDirectory(audioDir);
    for (let remapIndex = 0; remapIndex < remaps.length; remapIndex++) {
      const remap = remaps[remapIndex];
      if (remap.oldIndex === remap.newIndex) {
        continue;
      }
      const oldPrefix = `${String(remap.oldIndex + 1).padStart(4, '0')}.`;
      const newPrefix = `${String(remap.newIndex + 1).padStart(4, '0')}.`;
      for (let fileIndex = 0; fileIndex < files.length; fileIndex++) {
        const fileName = files[fileIndex];
        if (!fileName.startsWith(oldPrefix) || fileName.endsWith('.json')) {
          continue;
        }
        const sourcePath = this.getAudioCacheFilePath(bookId, fileName);
        if (movedSourcePaths.has(sourcePath)) {
          continue;
        }
        const suffix = fileName.substring(oldPrefix.length);
        const targetPath = this.getAudioCacheFilePath(bookId, `${newPrefix}${suffix}`);
        const tempPath = `${sourcePath}.order_tmp_${now}_${remapIndex}_${fileIndex}`;
        try {
          await this.sandboxManager.moveFile(sourcePath, tempPath);
          movedSourcePaths.add(sourcePath);
          tempMoves.push({
            stableKey: remap.stableKey,
            sourcePath,
            tempPath,
            targetPath
          } as ChapterCacheTempMove);
        } catch (error) {
          this.appendUniqueFailure(result, remap.stableKey);
          result.warnings.push(`兜底音频缓存临时迁移失败: ${remap.title}, ${String(error)}`);
        }
      }
    }
  }

  private findRemapByOldIndex(remaps: ChapterOrderIndexRemap[], oldIndex: number): ChapterOrderIndexRemap | null {
    for (let index = 0; index < remaps.length; index++) {
      const remap = remaps[index];
      if (remap.oldIndex === oldIndex) {
        return remap;
      }
    }
    return null;
  }

  private extractAudioExtensionFromFileName(fileName: string): string {
    const dotIndex = fileName.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex >= fileName.length - 1) {
      return 'mp3';
    }
    return fileName.substring(dotIndex + 1);
  }

  private appendUniqueFailure(result: ChapterOrderCacheRemapResult, stableKey: string): void {
    if (!result.failedKeys.includes(stableKey)) {
      result.failedKeys.push(stableKey);
    }
  }
  
  /**
   * 保存书籍元数据
   */
  async saveBookMetadata(bookId: string, bookName: string, author: string, coverUrl: string): Promise<void> {
    try {
      // 确保缓存目录已初始化
      await this.ensureInitialized();
      
      const bookDir = this.getBookCacheDir(bookId);
      await this.sandboxManager.createDirectory(bookDir);
      
      const metadata: BookMetadata = {
        bookId: bookId,
        bookName: bookName,
        author: author,
        coverUrl: coverUrl,
        createTime: Date.now(),
        updateTime: Date.now()
      };
      
      const metadataPath = `${bookDir}/metadata.json`;
      await this.sandboxManager.writeFile(metadataPath, JSON.stringify(metadata, null, 2));
      logger.debug(TAG, `保存书籍元数据: ${metadataPath}`);
    } catch (error) {
      logger.error(TAG, `保存书籍元数据失败: ${String(error)}`);
    }
  }
  
  /**
   * 保存章节列表到缓存
   * 用于避免每次都从网络加载章节列表
   */
  async saveChapterList(bookId: string, chapters: LegadoChapter[]): Promise<void> {
    try {
      await this.ensureInitialized();
      
      const bookDir = this.getBookCacheDir(bookId);
      await this.sandboxManager.createDirectory(bookDir);
      
      const chapterListPath = `${bookDir}/chapters_list.json`;
      
      // 构建章节列表数据
      const chaptersArray: LegadoChapter[] = [];
      for (const ch of chapters) {
        const chapterItem: LegadoChapter = {
          id: ch.id || '',
          bookUrl: ch.bookUrl || '',
          url: ch.url || '',
          title: ch.title || '',
          index: ch.index,
          isVolume: ch.isVolume || false,
          isVip: ch.isVip || false,
          isPay: ch.isPay || false,
          updateTime: ch.updateTime,
          variable: ch.variable,
          tag: ch.tag
        };
        chaptersArray.push(chapterItem);
      }
      
      const chapterData: ChapterListCacheData = {
        updateTime: Date.now(),
        totalCount: chapters.length,
        chapters: chaptersArray
      };
      
      await this.sandboxManager.writeFile(chapterListPath, JSON.stringify(chapterData));
      logger.info(TAG, `保存章节列表缓存: ${bookId}, ${chapters.length}章`);
    } catch (error) {
      logger.error(TAG, `保存章节列表失败: ${String(error)}`);
    }
  }
  
  /**
   * 从缓存获取章节列表
   * @param bookId 书籍ID
   * @param maxAgeHours 缓存最大有效时长（小时）
   * @returns 章节列表，如果缓存不存在则返回null
   */
  async getCachedChapterList(bookId: string, maxAgeHours: number = 24): Promise<LegadoChapter[] | null> {
    try {
      await this.ensureInitialized();
      const normalizedMaxAgeHours = Number.isFinite(maxAgeHours) ? Math.max(0, maxAgeHours) : 24;
      const maxAgeMs = normalizedMaxAgeHours * 60 * 60 * 1000;

      const candidateBookIds = this.getCompatibleBookIds(bookId);
      for (let i = 0; i < candidateBookIds.length; i++) {
        const candidateBookId = candidateBookIds[i];
        const bookDir = this.getBookCacheDir(candidateBookId);
        const chapterListPath = `${bookDir}/chapters_list.json`;

        // 检查文件是否存在
        if (!await this.sandboxManager.exists(chapterListPath)) {
          continue;
        }

        try {
          // 读取文件
          const contentBuffer: string | ArrayBuffer = await this.sandboxManager.readFile(chapterListPath);
          let contentStr: string;
          if (typeof contentBuffer === 'string') {
            contentStr = contentBuffer;
          } else {
            contentStr = new util.TextDecoder().decodeToString(new Uint8Array(contentBuffer));
          }
          const chapterData = SafeUtils.parseObj(contentStr) as ChapterListCacheData;
          const cacheAgeMs = Date.now() - chapterData.updateTime;
          if (cacheAgeMs > maxAgeMs) {
            logger.info(
              TAG,
              `章节列表缓存过期: ${candidateBookId}, ageMs=${cacheAgeMs}, maxAgeMs=${maxAgeMs}`
            );
            continue;
          }

          if (candidateBookId !== bookId) {
            logger.info(
              TAG,
              `从兼容路径加载章节列表缓存: compositeBookId=${bookId}, legacyBookUrl=${candidateBookId}, count=${chapterData.totalCount}`
            );
          } else {
            logger.info(TAG, `从缓存加载章节列表: ${candidateBookId}, ${chapterData.totalCount}章`);
          }
          return chapterData.chapters;
        } catch (singleError) {
          logger.warn(TAG, `读取章节列表缓存文件失败: ${chapterListPath}, ${String(singleError)}`);
        }
      }
      return null;
    } catch (error) {
      logger.warn(TAG, `获取缓存章节列表失败: ${String(error)}`);
      return null;
    }
  }
  
  /**
   * 获取缓存目录路径（供外部使用）
   */
  getCacheDirectory(): string {
    return this.novelsCacheDir;
  }

  private delay(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }
}

export function getNovelChapterCacheManager(): NovelChapterCacheManager {
  return NovelChapterCacheManager.getInstance();
}
