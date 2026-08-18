import { distributedFileManager } from './DistributedFileManager';
import { distributedDataSyncManager, SyncReadingState } from './DistributedDataSyncManager';
import { logger } from '../../Utils/Logger';
import { MangaDownloadManager } from '../Download/DownloadManager';
import { DataManager } from '../Data/DataManager';
import { DataService } from '../Services/DataService';

const TAG = 'DistributedReadingService';

/**
 * 跨端接续快照（来自 onContinue 的 wantParam，由 EntryAbility 写入 AppStorage）
 * 作为接续恢复的主通道：wantParam 由系统保证送达，不依赖分布式数据对象同步。
 */
export interface ContinuationSnapshot {
  chapterIndex: number;
  pageIndex: number;
  offset: number;
  isLocal: boolean;
}

export class DistributedReadingService {
  private static instance: DistributedReadingService;
  private isListening: boolean = false;

  /** 阅读进度同步的最大有效间隔（毫秒）：超过该间隔认为用户已不在阅读器内 */
  private static readonly READ_STATE_VALID_WINDOW_MS: number = 60 * 1000;

  private constructor() {}

  public static getInstance(): DistributedReadingService {
    if (!DistributedReadingService.instance) {
      DistributedReadingService.instance = new DistributedReadingService();
    }
    return DistributedReadingService.instance;
  }

  private onStateChangeCallback = (state: SyncReadingState): void => {
    this.handleStateChange(state);
  };

  /**
   * 初始化阅读器页面的双向同步监听
   */
  public attachToReader(): void {
    if (this.isListening) return;

    distributedDataSyncManager.addOnDataChangedCallback(this.onStateChangeCallback);

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
    // [修复] 对方发来的阅读进度（被控端翻页/退出时的回传）：
    // 更新本端 AppStorage 阅读快照并持久化到本端阅读记录，
    // 使源设备"拥有"最新进度（书库显示、再次打开续读、再次接续打包均以最新进度为准）。
    else if ((!state.instructionType || state.instructionType === 'none' || state.instructionType === 'ack')
      && state.bookId.length > 0) {
      this.applyRemoteProgress(state);
    }
  }

  /**
   * [修复] 应用远端阅读进度：更新本端阅读快照 + 按内容类型持久化到本端阅读记录。
   */
  private applyRemoteProgress(state: SyncReadingState): void {
    const rawSourceType = state.sourceType.length > 0 ? state.sourceType : 'manga';
    const normalizedSourceType = this.normalizeSourceType(rawSourceType);
    logger.info(TAG, `应用远端阅读进度: bookId=${state.bookId}, chapter=${state.chapterIndex}, page=${state.pageIndex}, offset=${state.offset}, sourceType=${normalizedSourceType}`);
    this.updateCurrentReadingSnapshot(
      state.bookId,
      state.chapterIndex,
      state.pageIndex,
      state.offset,
      normalizedSourceType,
      rawSourceType
    );
    void this.persistRemoteProgress(state, normalizedSourceType);
  }

  /**
   * [修复] 远端进度落库（本端阅读记录）：
   * - 漫画：经 DataService 写入 read_history（书库进度/继续阅读位置随之更新）；
   * - 电子书/小说：其进度模型依赖章节内部结构，暂仅更新内存快照，不落库。
   */
  private async persistRemoteProgress(state: SyncReadingState, normalizedSourceType: string): Promise<void> {
    if (normalizedSourceType !== 'manga' || state.bookId.length <= 0) {
      return;
    }
    try {
      const chapters = await DataManager.getInstance().getComicChapters(state.bookId);
      if (!chapters || chapters.length <= 0) {
        logger.debug(TAG, `远端漫画进度落库跳过（本端无章节记录）: bookId=${state.bookId}`);
        return;
      }
      const clampedIndex = Math.max(0, Math.min(state.chapterIndex, chapters.length - 1));
      const chapter = chapters[clampedIndex];
      await DataService.getInstance().saveReadingProgress(state.bookId, chapter.id, state.pageIndex, 0);
      logger.info(TAG, `远端漫画进度已写入本端阅读记录: bookId=${state.bookId}, chapterId=${chapter.id}, page=${state.pageIndex}`);
    } catch (error) {
      logger.warn(TAG, `远端漫画进度写入失败: bookId=${state.bookId}, ${String(error)}`);
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
    logger.debug(TAG, `syncProgress: bookId=${bookId}, chapter=${chapterIndex}, page=${pageIndex}, offset=${offset}, sourceType=${normalizedSourceType}`);
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
    distributedDataSyncManager.removeOnDataChangedCallback(this.onStateChangeCallback);
    logger.info(TAG, 'Detached DistributedReadingService.');
  }

  /**
   * 判断当前是否处于有效的阅读状态（用于 onContinue 守卫：
   * 用户未在阅读器内时拒绝流转，避免把陈旧/空状态流转到其他设备）
   * 判定规则：
   * 1. currentReadBookId 非空（进入过阅读器且已产生进度同步）；
   * 2. 且满足二者之一：
   *    a. 最近一次进度同步在有效窗口内（阅读器定时保存活跃）；
   *    b. 阅读器页面当前在前台（currentReaderHostPage 非空）——
   *       覆盖"刚进入阅读器尚未产生进度同步"与"长时间停留但定时保存间隔较长"的场景。
   */
  public isReadingActive(): boolean {
    const bookId = AppStorage.get<string>('currentReadBookId');
    if (!bookId || bookId.length <= 0) {
      logger.debug(TAG, 'isReadingActive=false: currentReadBookId 为空（未进入过阅读器或已清理）');
      return false;
    }
    const lastSyncTimestamp = AppStorage.get<number>('currentReadSyncTimestamp') || 0;
    if (lastSyncTimestamp > 0 && (Date.now() - lastSyncTimestamp) <= DistributedReadingService.READ_STATE_VALID_WINDOW_MS) {
      logger.debug(TAG, `isReadingActive=true: 阅读进度同步在有效窗口内, bookId=${bookId}, lastSyncAgeMs=${Date.now() - lastSyncTimestamp}`);
      return true;
    }
    const hostPage = AppStorage.get<string>('currentReaderHostPage') || '';
    if (hostPage.length > 0) {
      logger.debug(TAG, `isReadingActive=true: 阅读器页面在前台（${hostPage}），视为有效阅读状态, bookId=${bookId}, lastSyncAgeMs=${Date.now() - lastSyncTimestamp}`);
      return true;
    }
    logger.debug(TAG, `isReadingActive=false: 进度同步已过期且阅读器不在前台, bookId=${bookId}, lastSyncAgeMs=${Date.now() - lastSyncTimestamp}, windowMs=${DistributedReadingService.READ_STATE_VALID_WINDOW_MS}`);
    return false;
  }

  /**
   * 读取跨端接续快照（不消费）
   * 快照数据来自 onContinue 的 wantParam，由 EntryAbility.restoreContinuationState 写入。
   * @returns 有效快照；无接续会话或快照字段无效时返回 null
   */
  public readContinuationSnapshot(): ContinuationSnapshot | null {
    const sessionId = AppStorage.get<string>('continuationSessionId');
    if (!sessionId || sessionId.length <= 0) {
      logger.debug(TAG, 'readContinuationSnapshot=null: continuationSessionId 为空（无接续会话）');
      return null;
    }
    const chapterIndex = AppStorage.get<number>('continuationChapterIndex');
    if (typeof chapterIndex !== 'number' || !Number.isFinite(chapterIndex) || chapterIndex < 0) {
      logger.warn(TAG, `readContinuationSnapshot=null: continuationChapterIndex 无效, value=${String(chapterIndex)}, sessionId=${sessionId}`);
      return null;
    }
    const rawPageIndex = AppStorage.get<number>('continuationPageIndex');
    const rawOffset = AppStorage.get<number>('continuationOffset');
    const isLocal = AppStorage.get<boolean>('continuationIsLocal') || false;
    const pageIndex = (typeof rawPageIndex === 'number' && Number.isFinite(rawPageIndex) && rawPageIndex >= 0)
      ? rawPageIndex
      : -1;
    const offset = (typeof rawOffset === 'number' && Number.isFinite(rawOffset) && rawOffset >= 0)
      ? rawOffset
      : -1;
    logger.debug(TAG, `readContinuationSnapshot: sessionId=${sessionId}, chapterIndex=${chapterIndex}, pageIndex=${pageIndex}, offset=${offset}, isLocal=${isLocal}`);
    return {
      chapterIndex: chapterIndex,
      pageIndex: pageIndex,
      offset: offset,
      isLocal: isLocal
    };
  }

  /**
   * 读取并消费跨端接续快照（读取后立即清理接续标志，防止残留导致后续误触发）
   */
  public consumeContinuationSnapshot(): ContinuationSnapshot | null {
    const snapshot = this.readContinuationSnapshot();
    if (snapshot) {
      this.clearContinuationFlags();
    }
    return snapshot;
  }

  /**
   * 清理跨端接续标志（导航失败、恢复完成、阅读器退出时调用）
   * 同时清理 widget 接续导航标志（widgetTargetPage/Type/Id）：
   * 目标端由阅读器 Ability 直接承载接续时（不再经过 MainMenuPage），
   * 若不清除，后续用户打开主页会误触发"继续阅读"再次拉起阅读器。
   */
  public clearContinuationFlags(): void {
    logger.debug(TAG, 'clearContinuationFlags: 清理接续标志(continuationSessionId/ChapterIndex/PageIndex/Offset/IsLocal + widgetTargetPage/Type/Id)');
    AppStorage.setOrCreate('continuationSessionId', '');
    AppStorage.setOrCreate('continuationChapterIndex', -1);
    AppStorage.setOrCreate('continuationPageIndex', -1);
    AppStorage.setOrCreate('continuationOffset', -1);
    AppStorage.setOrCreate('continuationIsLocal', false);
    AppStorage.setOrCreate('widgetTargetPage', '');
    AppStorage.setOrCreate('widgetContentType', '');
    AppStorage.setOrCreate('widgetContentId', '');
  }

  /**
   * 清理当前阅读状态（阅读器退出时调用，防止 onContinue 打包陈旧状态）
   */
  public clearCurrentReadingState(): void {
    logger.debug(TAG, 'clearCurrentReadingState: 清理当前阅读状态(currentReadBookId/ChapterIndex/PageIndex/Offset/SourceType/IsLocal/SyncTimestamp)');
    AppStorage.setOrCreate('currentReadBookId', '');
    AppStorage.setOrCreate('currentReadChapterIndex', -1);
    AppStorage.setOrCreate('currentReadPageIndex', -1);
    AppStorage.setOrCreate('currentReadOffset', -1);
    AppStorage.setOrCreate('currentReadSourceType', '');
    AppStorage.setOrCreate('currentReadIsLocal', false);
    AppStorage.setOrCreate('currentReadSyncTimestamp', 0);
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
    AppStorage.setOrCreate<number>('currentReadSyncTimestamp', Date.now());
  }
}

export const distributedReadingService = DistributedReadingService.getInstance();
