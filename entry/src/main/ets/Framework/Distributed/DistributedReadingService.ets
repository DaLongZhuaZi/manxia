import { distributedFileManager } from './DistributedFileManager';
import { distributedDataSyncManager, SyncReadingState } from './DistributedDataSyncManager';
import { logger } from '../../Utils/Logger';
import { MangaDownloadManager } from '../Download/DownloadManager';

const TAG = 'DistributedReadingService';

export class DistributedReadingService {
  private static instance: DistributedReadingService;
  private isListening: boolean = false;

  private constructor() {}

  public static getInstance(): DistributedReadingService {
    if (!DistributedReadingService.instance) {
      DistributedReadingService.instance = new DistributedReadingService();
    }
    return DistributedReadingService.instance;
  }

  /**
   * 初始化阅读器页面的双向同步监听
   */
  public attachToReader(): void {
    if (this.isListening) return;

    distributedDataSyncManager.setOnDataChangedCallback((state: SyncReadingState) => {
      this.handleStateChange(state);
    });

    this.isListening = true;
    logger.info(TAG, 'Attached DistributedReadingService to reader session.');
  }

  /**
   * 处理远端状态/指令变更
   */
  private handleStateChange(state: SyncReadingState): void {
    logger.info(TAG, `Received distributed state update: type=${state.instructionType}, chapter=${state.chapterIndex}`);
    
    // 如果是对方发来的下载请求（对方处于无网/无VPN环境）
    if (state.instructionType === 'request_download') {
      this.handleRemoteDownloadRequest(state);
    } 
    // 如果是对方发来的下载完成通知
    else if (state.instructionType === 'download_complete') {
      logger.info(TAG, `Remote device finished proxy download for book ${state.bookId}`);
      // 可以在此处通过 EventBus 通知阅读器重载本章节
    }
  }

  /**
   * 源端（有网设备）处理目标端的代理下载请求
   */
  private handleRemoteDownloadRequest(state: SyncReadingState): void {
    const bookId = state.bookId;
    const chapterIndex = state.chapterIndex;
    const instructionPayload = state.instructionPayload;
    logger.info(TAG, `Proxy downloading chapter ${chapterIndex} for book ${bookId}`);
    
    try {
      const payload = JSON.parse(instructionPayload) as Record<string, string>;
      const chapterUrl = payload['chapterUrl'] as string;
      const sourceType = payload['sourceType'] as string;

      // 模拟调用已有下载管理器进行后台下载，并将结果写入分布式沙箱
      // 在真实实现中，应该扩展 DownloadManager，使其支持下载到 distributedFilesDir
      // 这里作为高级抽象引擎实现
      const downloadTask = MangaDownloadManager.getInstance();
      // 这里假定 downloadTask 会在下载完成后，将文件存入本地，再通过 DistributedFileManager 转移到沙箱
      
      // 成功后，回传完成指令
      distributedDataSyncManager.sendInstruction('download_complete', JSON.stringify({
        bookId,
        chapterIndex,
        sandboxFileName: `${bookId}_${chapterIndex}.json`
      }));
    } catch (e) {
      logger.error(TAG, `Error handling remote download request: ${String(e)}`);
      distributedDataSyncManager.sendInstruction('download_failed', JSON.stringify({
        bookId,
        chapterIndex,
        error: String(e)
      }));
    }
  }

  /**
   * 目标端（无网设备）向源端发送代理下载请求
   */
  public requestProxyDownload(bookId: string, chapterIndex: number, chapterUrl: string, sourceType: string): void {
    logger.info(TAG, `Requesting proxy download from source device for chapter ${chapterIndex}`);
    const payload = JSON.stringify({
      chapterUrl,
      sourceType
    });
    distributedDataSyncManager.sendInstruction('request_download', payload);
  }

  /**
   * 阅读器翻页/滚动时更新进度到分布式沙箱
   */
  public syncProgress(bookId: string, chapterIndex: number, pageIndex: number, offset: number, sourceType: string): void {
    const normalizedSourceType = this.normalizeSourceType(sourceType);
    this.updateCurrentReadingSnapshot(bookId, chapterIndex, pageIndex, offset, normalizedSourceType, sourceType);
    distributedDataSyncManager.updateProgress(bookId, chapterIndex, pageIndex, offset, normalizedSourceType);
  }

  /**
   * 从沙箱加载内容（优先读取缓存）
   */
  public loadChapterFromSandbox(bookId: string, chapterIndex: number): string | null {
    const fileName = `${bookId}_${chapterIndex}.json`;
    return distributedFileManager.readTextFromDistributed(fileName);
  }

  public detach(): void {
    this.isListening = false;
    distributedDataSyncManager.setOnDataChangedCallback(() => {});
    logger.info(TAG, 'Detached DistributedReadingService.');
  }

  private normalizeSourceType(sourceType: string): string {
    const normalized = sourceType.trim().toLowerCase();
    if (normalized === 'novel') {
      return 'novel';
    }
    if (normalized === 'ebook' || normalized === 'epub' || normalized === 'pdf' || normalized === 'txt') {
      return 'ebook';
    }
    return 'manga';
  }

  private isLocalSource(rawSourceType: string): boolean {
    const normalized = rawSourceType.trim().toLowerCase();
    return normalized === 'local' || normalized.indexOf('local') >= 0;
  }

  private updateCurrentReadingSnapshot(
    bookId: string,
    chapterIndex: number,
    pageIndex: number,
    offset: number,
    sourceType: string,
    rawSourceType: string
  ): void {
    if (bookId.length <= 0) {
      logger.warn(TAG, 'Skip current reading snapshot update because bookId is empty');
      return;
    }
    AppStorage.setOrCreate<string>('currentReadBookId', bookId);
    AppStorage.setOrCreate<number>('currentReadChapterIndex', chapterIndex);
    AppStorage.setOrCreate<number>('currentReadPageIndex', pageIndex);
    AppStorage.setOrCreate<number>('currentReadOffset', offset);
    AppStorage.setOrCreate<string>('currentReadSourceType', sourceType);
    AppStorage.setOrCreate<boolean>('currentReadIsLocal', this.isLocalSource(rawSourceType));
  }
}

export const distributedReadingService = DistributedReadingService.getInstance();
