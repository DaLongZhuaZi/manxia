// 文件路径: entry/src/main/ets/Framework/Components/ReaderKitViewerComponent.ets
/**
 * Reader Kit 阅读器组件
 * 使用 HarmonyOS 官方 Reader Kit 的 readerCore 提供阅读功能
 * 支持格式：TXT、EPUB、MOBI、AZW、AZW3
 */

import { logger } from '../../Utils/Logger';
import { EBook, EBookChapter, EBookReadingSettings, EBookPageMode, DEFAULT_EBOOK_READING_SETTINGS } from '../../Models/EBookModels';
import { fileIo } from '@kit.CoreFileKit';
import { bookParser, readerCore, ReadPageComponent } from '@kit.ReaderKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { display, font } from '@kit.ArkUI';

const TAG = 'ReaderKitViewerComponent';

/**
 * Reader Kit 阅读器控制器接口
 * 用于外部控制阅读器
 */
export interface ReaderKitViewerController {
  goToChapter: (chapterIndex: number, domPos?: string) => Promise<void>;
  applyReadingSettings: (settings: EBookReadingSettings, force?: boolean) => void;
  isControllerReady: () => boolean;
}

/**
 * Reader Kit 阅读器参数接口
 */
export interface ReaderKitViewerParams {
  ebook: EBook; // 电子书对象
  currentChapterIndex: number; // 当前章节索引
  initialDomPos?: string; // 初始 DOM 位置（用于恢复阅读位置）
  readingSettings?: EBookReadingSettings; // 阅读设置
  onChapterChange?: (index: number) => void; // 章节切换回调
  onProgressChange?: (progress: number, domPos: string) => void; // 阅读进度回调（包含 domPos）
  onSettingsChange?: (settings: EBookReadingSettings) => void; // 设置变化回调
  onControllerReady?: (controller: ReaderKitViewerController) => void; // 控制器就绪回调
}

interface ReaderKitPageDataJson {
  resourceCount?: number;
  totalResourceCount?: number;
}

interface ReaderKitSavedPositionData {
  resourceIndex?: number;
  domPos?: string;
  startDomPos?: string;
  endDomPos?: string;
  pageOffset?: number;
  dataId?: string;
}

interface ReaderKitPersistedPositionData {
  resourceIndex: number;
  pageOffset: number;
  startDomPos: string;
  endDomPos: string;
  dataId: string;
  domPos: string;
  resourceCount?: number;
  totalResourceCount?: number;
}

interface ReaderKitRestoreAnchorCandidate {
  value: string;
  source: string;
}

interface ReaderKitPageAnchorSnapshot {
  resourceIndex: number;
  pageOffset: number;
  startDomPos: string;
  endDomPos: string;
  dataId: string;
}

/**
 * Reader Kit 阅读器组件
 */
@Component
export struct ReaderKitViewerComponent {
  @Prop ebook: EBook;
  @Prop currentChapterIndex: number = 0;
  @Prop initialDomPos: string = '';
  @Prop readingSettings: EBookReadingSettings | null = null;
  onChapterChange?: (index: number) => void;
  onProgressChange?: (progress: number, domPos: string) => void;
  onSettingsChange?: (settings: EBookReadingSettings) => void;
  onControllerReady?: (controller: ReaderKitViewerController) => void;
  
  @State isLoading: boolean = true;
  @State errorMessage: string = '';
  private readerController: readerCore.ReaderComponentController = new readerCore.ReaderComponentController();
  @State private controllerReady: boolean = false;
  private sandboxPath: string = '';
  
  // 当前页面数据（用于保存阅读进度）
  private currentPageData: readerCore.PageDataInfo | null = null;
  
  // Reader Kit 设置对象
  private readerSetting: readerCore.ReaderSetting | null = null;
  
  // 窗口尺寸（从 display API 获取）
  private windowWidth: number = 0;
  private windowHeight: number = 0;
  private pendingPageOffsetRecovery: number = -1;
  private pendingPageOffsetRecoveryChapterIndex: number = -1;
  private pendingPageOffsetRecoveryStepCount: number = 0;
  private startupRecoveryExpectedPageOffset: number = -1;
  private startupRecoveryExpectedResourceIndex: number = -1;
  private startupRecoveryDomPosCandidates: ReaderKitRestoreAnchorCandidate[] = [];
  private startupRecoveryCurrentCandidateIndex: number = -1;
  private startupRecoveryAllowFlipFallback: boolean = false;
  private startupRecoveryRetryInFlight: boolean = false;
  private suppressProgressSaveDuringStartupRecovery: boolean = false;
  private startupRecoveryWatchdogTimer: number = -1;
  private startupRecoveryRetryTimer: number = -1;
  private startupRecoveryStartedAt: number = 0;
  private lastPageAnchorSnapshot: ReaderKitPageAnchorSnapshot | null = null;

  aboutToAppear(): void {
    logger.info(TAG, `Reader Kit 阅读器组件初始化: ${this.ebook.metadata.title}`);
    this.initializeReaderSession();
  }

  aboutToDisappear(): void {
    logger.info(TAG, 'Reader Kit 阅读器组件销毁');
    this.resetPendingPageOffsetRecovery('component_disappear');
    this.resetStartupDirectRecovery('component_disappear');
    try {
      // 移除事件监听器
      this.readerController.off('pageShow');
      // 释放资源
      this.readerController.releaseBook();
    } catch (error) {
      logger.warn(TAG, `清理 Reader Kit 资源时出错: ${String(error)}`);
    }
  }

  // 上次应用设置的时间戳，用于防止频繁应用设置
  private lastSettingsApplyTime: number = 0;
  // 设置应用的最小间隔（毫秒）
  private static readonly SETTINGS_APPLY_INTERVAL: number = 1000;
  // pageOffset 恢复时单次最多翻页次数，避免异常循环
  private static readonly PAGE_OFFSET_RECOVERY_MAX_STEPS: number = 260;
  // pageOffset 恢复的单次翻页延迟，等待 ReaderKit 完成渲染后再翻下一页
  private static readonly PAGE_OFFSET_RECOVERY_FLIP_DELAY_MS: number = 90;
  private static readonly STARTUP_DIRECT_RECOVERY_RETRY_DELAY_MS: number = 80;
  private static readonly STARTUP_DIRECT_RECOVERY_WATCHDOG_MS: number = 1200;
  private static readonly STARTUP_DIRECT_RECOVERY_MAX_DURATION_MS: number = 7000;


  /**
   * 获取默认屏幕密度
   */
  private getDefaultScaledDensity(): number {
    try {
      const displaySync = display.getDefaultDisplaySync();
      return displaySync.scaledDensity > 0 ? displaySync.scaledDensity : 1;
    } catch (error) {
      logger.warn(TAG, `获取屏幕密度失败: ${String(error)}`);
      return 1;
    }
  }

  /**
   * 初始化 Reader Kit 设置对象
   * 使用 DEFAULT_EBOOK_READING_SETTINGS 作为默认值
   */
  private initReaderSetting(): readerCore.ReaderSetting {
    const settings = this.readingSettings || this.ebook.readingSettings || DEFAULT_EBOOK_READING_SETTINGS;
    
    // 从 display API 获取屏幕尺寸和密度
    try {
      const displaySync = display.getDefaultDisplaySync();
      this.windowWidth = displaySync.width;
      this.windowHeight = displaySync.height;
      logger.info(TAG, `屏幕尺寸: ${this.windowWidth}x${this.windowHeight}, densityDPI=${displaySync.densityDPI}, scaledDensity=${displaySync.scaledDensity}`);
    } catch (error) {
      // 使用默认值
      this.windowWidth = 1080;
      this.windowHeight = 2340;
      logger.warn(TAG, `获取屏幕尺寸失败，使用默认值: ${this.windowWidth}x${this.windowHeight}`);
    }
    
    // 获取屏幕密度，Reader Kit 需要使用 scaledDensity
    const scaledDensity = this.getDefaultScaledDensity();
    
    logger.info(TAG, `Reader Kit 设置: fontSize=${settings.fontSize}, fontFamily=${settings.fontFamily}, fontPath=${settings.fontPath}, scaledDensity=${scaledDensity}, viewPort=${this.windowWidth}x${this.windowHeight}`);
    
    // 如果有自定义字体路径，先注册字体
    const fontPath = settings.fontPath || '';
    if (fontPath && fontPath.length > 0) {
      try {
        const fontUri = fontPath.startsWith('file://') ? fontPath : `file://${fontPath}`;
        font.registerFont({
          familyName: settings.fontFamily,
          familySrc: fontUri
        });
        logger.info(TAG, `初始化时注册自定义字体: ${settings.fontFamily}, 路径: ${fontUri}`);
      } catch (fontError) {
        logger.warn(TAG, `初始化时注册自定义字体失败: ${String(fontError)}`);
      }
    }
    
    return {
      fontName: settings.fontFamily || DEFAULT_EBOOK_READING_SETTINGS.fontFamily,
      fontPath: fontPath,
      fontSize: settings.fontSize || DEFAULT_EBOOK_READING_SETTINGS.fontSize,
      fontColor: settings.textColor || DEFAULT_EBOOK_READING_SETTINGS.textColor,
      fontWeight: settings.fontWeight || DEFAULT_EBOOK_READING_SETTINGS.fontWeight,
      lineHeight: settings.lineHeight || DEFAULT_EBOOK_READING_SETTINGS.lineHeight,
      nightMode: settings.nightMode || false,
      themeColor: settings.backgroundColor || DEFAULT_EBOOK_READING_SETTINGS.backgroundColor,
      themeBgImg: settings.themeBgImage || '',
      flipMode: settings.pageMode || DEFAULT_EBOOK_READING_SETTINGS.pageMode,
      scaledDensity: scaledDensity,
      viewPortWidth: this.windowWidth,
      viewPortHeight: this.windowHeight
    };
  }

  /**
   * 应用阅读设置到 Reader Kit（带防抖）
   * 注意：setPageConfig 会导致页面重新渲染，因此需要防止频繁调用
   */
  public applyReadingSettings(settings: EBookReadingSettings, force: boolean = false): void {
    if (!this.controllerReady || !this.readerSetting) {
      logger.warn(TAG, '阅读器未就绪，无法应用设置');
      return;
    }

    // 防抖：检查距离上次应用设置的时间间隔
    const now = Date.now();
    if (!force && (now - this.lastSettingsApplyTime) < ReaderKitViewerComponent.SETTINGS_APPLY_INTERVAL) {
      return;
    }
    this.lastSettingsApplyTime = now;

    try {
      // 如果有自定义字体路径，先注册字体
      const fontPath = settings.fontPath || '';
      if (fontPath && fontPath.length > 0) {
        try {
          const fontUri = fontPath.startsWith('file://') ? fontPath : `file://${fontPath}`;
          font.registerFont({
            familyName: settings.fontFamily,
            familySrc: fontUri
          });
          logger.info(TAG, `自定义字体已注册: ${settings.fontFamily}, 路径: ${fontUri}`);
        } catch (fontError) {
          logger.warn(TAG, `注册自定义字体失败: ${String(fontError)}`);
        }
      }

      // 更新设置对象
      this.readerSetting.fontName = settings.fontFamily;
      this.readerSetting.fontPath = fontPath;
      this.readerSetting.fontSize = settings.fontSize;
      this.readerSetting.fontColor = settings.textColor;
      this.readerSetting.fontWeight = settings.fontWeight || 400;
      this.readerSetting.lineHeight = settings.lineHeight;
      this.readerSetting.nightMode = settings.nightMode;
      this.readerSetting.themeColor = settings.backgroundColor;
      this.readerSetting.themeBgImg = settings.themeBgImage || '';
      this.readerSetting.flipMode = settings.pageMode;
      this.readerSetting.scaledDensity = this.getDefaultScaledDensity();

      logger.info(TAG, `应用阅读设置: fontName=${this.readerSetting.fontName}, fontPath=${this.readerSetting.fontPath}, fontSize=${this.readerSetting.fontSize}`);

      // 应用设置 - 注意：这会触发页面重新渲染
      this.readerController.setPageConfig(this.readerSetting);
      logger.info(TAG, '阅读设置已应用');
    } catch (error) {
      logger.error(TAG, `应用阅读设置失败: ${String(error)}`);
    }
  }

  /**
   * 初始化 Reader Kit 会话
   * 
   * 注意：这是框架代码，实际的 Reader Kit API 需要根据官方文档调整
   */
  private async initializeReaderSession(): Promise<void> {
    try {
      this.isLoading = true;
      this.errorMessage = '';

      logger.info(TAG, `初始化 Reader Kit 会话，格式: ${this.ebook.format}`);

      // 读取电子书文件
      const fileBuffer = await this.readFileBuffer(this.ebook.filePath);
      this.sandboxPath = await this.copyToSandbox(this.ebook.filePath, fileBuffer);

      await this.tryStartReading();

    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `Reader Kit 会话初始化失败: ${errorMsg}`);
      this.errorMessage = errorMsg;
      this.isLoading = false;
    }
  }

  /**
   * 关闭 Reader Kit 会话
   */
  

  /**
   * 读取文件二进制数据
   */
  private async readFileBuffer(filePath: string): Promise<ArrayBuffer> {
    try {
      let openTarget: string = filePath;
      if (!filePath.startsWith('file://') && !filePath.startsWith('/')) {
        openTarget = `/${filePath}`;
      }

      let file = fileIo.openSync(openTarget, fileIo.OpenMode.READ_ONLY);
      let stat = fileIo.statSync(file.fd);
      let buffer = new ArrayBuffer(stat.size);
      let readLen = fileIo.readSync(file.fd, buffer);
      fileIo.closeSync(file);

      if (readLen !== stat.size) {
        throw new Error(`读取长度不一致: 期望 ${stat.size} 实际 ${readLen}`);
      }

      logger.debug(TAG, `文件读取成功，大小: ${stat.size} 字节`);
      return buffer;
    } catch (firstError) {
      const firstMsg = firstError instanceof Error ? firstError.message : String(firstError);

      try {
        if (filePath.startsWith('file://')) {
          const stripped = filePath.substring(7);
          const candidate = stripped.startsWith('/') ? stripped : `/${stripped}`;
          const file = fileIo.openSync(candidate, fileIo.OpenMode.READ_ONLY);
          const stat = fileIo.statSync(file.fd);
          const buffer = new ArrayBuffer(stat.size);
          const readLen = fileIo.readSync(file.fd, buffer);
          fileIo.closeSync(file);

          if (readLen !== stat.size) {
            throw new Error(`读取长度不一致: 期望 ${stat.size} 实际 ${readLen}`);
          }
          logger.debug(TAG, `文件读取成功（备用路径），大小: ${stat.size} 字节`);
          return buffer;
        }
        throw new Error(firstMsg);
      } catch (error) {
        const errorMsg = error instanceof Error ? error.message : String(error);
        throw new Error(`文件读取失败: ${errorMsg}`);
      }
    }
  }

  private async copyToSandbox(filePath: string, fileBuffer: ArrayBuffer): Promise<string> {
    const context = this.getUIContext()?.getHostContext() as common.UIAbilityContext;
    const fileName = this.getFileName(filePath);
    const target = `${context.filesDir}/${fileName}`;
    const file = fileIo.openSync(target, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
    fileIo.writeSync(file.fd, fileBuffer);
    fileIo.closeSync(file.fd);
    return target;
  }

  private getFileName(path: string): string {
    const parts = path.split('/');
    const name = parts[parts.length - 1] || 'unknown_file';
    try { return decodeURIComponent(name); } catch { return name; }
  }

  private isFiniteNumber(value: number): boolean {
    return value === value && value !== Infinity && value !== -Infinity;
  }

  private extractResourceCountFromPageDataJson(pageDataJson: string): number {
    if (pageDataJson.length <= 0) {
      return -1;
    }
    try {
      const parsedData = JSON.parse(pageDataJson) as ReaderKitPageDataJson;
      if (!parsedData) {
        return -1;
      }
      const resourceCountValue = parsedData.resourceCount;
      if (typeof resourceCountValue === 'number' && this.isFiniteNumber(resourceCountValue) && resourceCountValue > 0) {
        return Math.floor(resourceCountValue);
      }
      const totalResourceCountValue = parsedData.totalResourceCount;
      if (typeof totalResourceCountValue === 'number' && this.isFiniteNumber(totalResourceCountValue) && totalResourceCountValue > 0) {
        return Math.floor(totalResourceCountValue);
      }
    } catch (_ignored) {
      return -1;
    }
    return -1;
  }

  private normalizeResourceIndex(value: number): number {
    if (typeof value === 'number' && this.isFiniteNumber(value) && value >= 0) {
      return Math.floor(value);
    }
    return 0;
  }

  private normalizePageOffset(value: number): number {
    if (typeof value === 'number' && this.isFiniteNumber(value) && value >= 0) {
      return Math.floor(value);
    }
    return 0;
  }

  private normalizeAnchorValue(value?: string): string {
    if (typeof value !== 'string') {
      return '';
    }
    return value.trim();
  }

  private updateLastPageAnchorSnapshot(
    data: readerCore.PageDataInfo,
    resourceIndex: number,
    pageOffset: number
  ): void {
    const currentStartDomPos = this.normalizeAnchorValue(data.startDomPos);
    const currentEndDomPos = this.normalizeAnchorValue(data.endDomPos);
    const currentDataId = this.normalizeAnchorValue(data.dataId);
    const previousSnapshot = this.lastPageAnchorSnapshot &&
      this.lastPageAnchorSnapshot.resourceIndex === resourceIndex &&
      this.lastPageAnchorSnapshot.pageOffset === pageOffset
      ? this.lastPageAnchorSnapshot
      : null;
    const startDomPos = currentStartDomPos.length > 0
      ? currentStartDomPos
      : (previousSnapshot ? previousSnapshot.startDomPos : '');
    const endDomPos = currentEndDomPos.length > 0
      ? currentEndDomPos
      : (previousSnapshot ? previousSnapshot.endDomPos : '');
    const dataId = currentDataId.length > 0
      ? currentDataId
      : (previousSnapshot ? previousSnapshot.dataId : '');
    if (startDomPos.length <= 0 && endDomPos.length <= 0 && dataId.length <= 0) {
      return;
    }
    this.lastPageAnchorSnapshot = {
      resourceIndex: resourceIndex,
      pageOffset: pageOffset,
      startDomPos: startDomPos,
      endDomPos: endDomPos,
      dataId: dataId
    };
  }

  private resolvePersistedPageAnchors(
    data: readerCore.PageDataInfo,
    resourceIndex: number,
    pageOffset: number
  ): ReaderKitPageAnchorSnapshot {
    const currentStartDomPos = this.normalizeAnchorValue(data.startDomPos);
    const currentEndDomPos = this.normalizeAnchorValue(data.endDomPos);
    const currentDataId = this.normalizeAnchorValue(data.dataId);
    const snapshot = this.lastPageAnchorSnapshot &&
      this.lastPageAnchorSnapshot.resourceIndex === resourceIndex &&
      this.lastPageAnchorSnapshot.pageOffset === pageOffset
      ? this.lastPageAnchorSnapshot
      : null;
    return {
      resourceIndex: resourceIndex,
      pageOffset: pageOffset,
      startDomPos: currentStartDomPos.length > 0
        ? currentStartDomPos
        : (snapshot ? snapshot.startDomPos : ''),
      endDomPos: currentEndDomPos.length > 0
        ? currentEndDomPos
        : (snapshot ? snapshot.endDomPos : ''),
      dataId: currentDataId.length > 0
        ? currentDataId
        : (snapshot ? snapshot.dataId : '')
    };
  }

  private buildPersistedPositionData(data: readerCore.PageDataInfo, resourceCount: number): string {
    const resourceIndex = this.normalizeResourceIndex(data.resourceIndex);
    const pageOffset = this.normalizePageOffset(data.pageOffset);
    const anchors = this.resolvePersistedPageAnchors(data, resourceIndex, pageOffset);
    const startDomPos = anchors.startDomPos;
    const endDomPos = anchors.endDomPos;
    const dataId = anchors.dataId;
    const domPos = dataId.length > 0
      ? dataId
      : (startDomPos.length > 0 ? startDomPos : endDomPos);
    const payload: ReaderKitPersistedPositionData = {
      resourceIndex: resourceIndex,
      pageOffset: pageOffset,
      startDomPos: startDomPos,
      endDomPos: endDomPos,
      dataId: dataId,
      domPos: domPos
    };
    if (resourceCount > 0) {
      payload.resourceCount = resourceCount;
      payload.totalResourceCount = resourceCount;
    }
    return JSON.stringify(payload);
  }

  private appendUniqueDomPosCandidate(
    candidates: ReaderKitRestoreAnchorCandidate[],
    domPos: string,
    source: string
  ): void {
    const normalized = domPos.trim();
    if (normalized.length <= 0) {
      return;
    }
    if (candidates.some((candidate: ReaderKitRestoreAnchorCandidate): boolean => candidate.value === normalized)) {
      return;
    }
    candidates.push({
      value: normalized,
      source: source
    });
  }

  private getCurrentStartupRecoveryCandidate(): ReaderKitRestoreAnchorCandidate | null {
    if (this.startupRecoveryCurrentCandidateIndex < 0) {
      return null;
    }
    if (this.startupRecoveryCurrentCandidateIndex >= this.startupRecoveryDomPosCandidates.length) {
      return null;
    }
    return this.startupRecoveryDomPosCandidates[this.startupRecoveryCurrentCandidateIndex];
  }

  private getCurrentPageOffsetSnapshot(): number {
    const rawOffset = this.currentPageData?.pageOffset;
    if (typeof rawOffset === 'number' && this.isFiniteNumber(rawOffset) && rawOffset >= 0) {
      return Math.floor(rawOffset);
    }
    return 0;
  }

  private clearStartupRecoveryWatchdog(): void {
    if (this.startupRecoveryWatchdogTimer >= 0) {
      clearTimeout(this.startupRecoveryWatchdogTimer);
      this.startupRecoveryWatchdogTimer = -1;
    }
  }

  private clearStartupRecoveryRetryTimer(): void {
    if (this.startupRecoveryRetryTimer >= 0) {
      clearTimeout(this.startupRecoveryRetryTimer);
      this.startupRecoveryRetryTimer = -1;
    }
  }

  private scheduleStartupRecoveryWatchdog(reason: string): void {
    this.clearStartupRecoveryWatchdog();
    if (this.startupRecoveryExpectedPageOffset <= 0 || this.startupRecoveryExpectedResourceIndex < 0) {
      return;
    }
    const expectedCandidateIndex = this.startupRecoveryCurrentCandidateIndex;
    const expectedCandidate = this.getCurrentStartupRecoveryCandidate();
    this.startupRecoveryWatchdogTimer = setTimeout((): void => {
      this.startupRecoveryWatchdogTimer = -1;
      if (this.startupRecoveryExpectedPageOffset <= 0 || this.startupRecoveryExpectedResourceIndex < 0) {
        return;
      }
      if (expectedCandidateIndex !== this.startupRecoveryCurrentCandidateIndex) {
        return;
      }
      const elapsedMs = this.startupRecoveryStartedAt > 0 ? Date.now() - this.startupRecoveryStartedAt : -1;
      logger.debug(
        TAG,
        `启动直达恢复看门狗: reason=${reason}, elapsedMs=${elapsedMs}, candidateIndex=${expectedCandidateIndex}, source=${expectedCandidate ? expectedCandidate.source : 'none'}`
      );
      logger.warn(
        TAG,
        `启动直达恢复等待超时: reason=${reason}, elapsedMs=${elapsedMs}, candidateIndex=${expectedCandidateIndex}`
      );
      if (this.startupRecoveryAllowFlipFallback && this.startupRecoveryExpectedPageOffset > 0) {
        this.preparePageOffsetRecovery(this.startupRecoveryExpectedResourceIndex, this.startupRecoveryExpectedPageOffset);
        this.startupRecoveryAllowFlipFallback = false;
        this.suppressProgressSaveDuringStartupRecovery = false;
        this.tryRecoverPageOffsetByFlip(this.startupRecoveryExpectedResourceIndex, this.getCurrentPageOffsetSnapshot());
        return;
      }
      this.resetStartupDirectRecovery('watchdog_timeout');
    }, ReaderKitViewerComponent.STARTUP_DIRECT_RECOVERY_WATCHDOG_MS);
  }

  private resetStartupDirectRecovery(reason: string): void {
    this.clearStartupRecoveryWatchdog();
    this.clearStartupRecoveryRetryTimer();
    if (this.startupRecoveryExpectedPageOffset > 0) {
      logger.info(
        TAG,
        `启动直达恢复结束: reason=${reason}, target=${this.startupRecoveryExpectedPageOffset}, chapter=${this.startupRecoveryExpectedResourceIndex}, candidates=${this.startupRecoveryDomPosCandidates.length}`
      );
    }
    this.startupRecoveryExpectedPageOffset = -1;
    this.startupRecoveryExpectedResourceIndex = -1;
    this.startupRecoveryDomPosCandidates = [];
    this.startupRecoveryCurrentCandidateIndex = -1;
    this.startupRecoveryAllowFlipFallback = false;
    this.startupRecoveryRetryInFlight = false;
    this.suppressProgressSaveDuringStartupRecovery = false;
    this.startupRecoveryStartedAt = 0;
  }

  private configureStartupDirectRecovery(
    resourceIndex: number,
    pageOffset: number,
    domPosCandidates: ReaderKitRestoreAnchorCandidate[],
    allowFlipFallback: boolean
  ): void {
    this.resetStartupDirectRecovery('reconfigure');
    if (!this.isFiniteNumber(pageOffset) || pageOffset <= 0) {
      return;
    }
    this.startupRecoveryExpectedPageOffset = Math.floor(pageOffset);
    this.startupRecoveryExpectedResourceIndex = Math.max(0, Math.floor(resourceIndex));
    this.startupRecoveryDomPosCandidates = domPosCandidates;
    this.startupRecoveryCurrentCandidateIndex = domPosCandidates.length > 0 ? 0 : -1;
    this.startupRecoveryAllowFlipFallback = allowFlipFallback;
    this.suppressProgressSaveDuringStartupRecovery = true;
    this.startupRecoveryStartedAt = Date.now();
    this.scheduleStartupRecoveryWatchdog('configure');
    const candidateSources = domPosCandidates
      .map((candidate: ReaderKitRestoreAnchorCandidate): string => candidate.source)
      .join('>');
    logger.debug(
      TAG,
      `启动直达恢复候选顺序: ${candidateSources || 'none'}`
    );
    logger.info(
      TAG,
      `配置启动直达恢复: chapter=${this.startupRecoveryExpectedResourceIndex}, targetOffset=${this.startupRecoveryExpectedPageOffset}, directCandidates=${domPosCandidates.length}, allowFlipFallback=${allowFlipFallback}`
    );
  }

  private triggerNextStartupDomPosCandidate(reason: string): boolean {
    if (this.startupRecoveryRetryInFlight) {
      return true;
    }
    if (this.startupRecoveryExpectedPageOffset <= 0 || this.startupRecoveryExpectedResourceIndex < 0) {
      return false;
    }
    const elapsedMs = this.startupRecoveryStartedAt > 0 ? Date.now() - this.startupRecoveryStartedAt : 0;
    if (elapsedMs > ReaderKitViewerComponent.STARTUP_DIRECT_RECOVERY_MAX_DURATION_MS) {
      logger.warn(TAG, `启动直达恢复超时，终止后续重试: reason=${reason}, elapsedMs=${elapsedMs}`);
      return false;
    }
    const nextIndex = this.startupRecoveryCurrentCandidateIndex + 1;
    if (nextIndex >= this.startupRecoveryDomPosCandidates.length) {
      return false;
    }
    const nextCandidate = this.startupRecoveryDomPosCandidates[nextIndex];
    const nextDomPos = nextCandidate.value;
    this.startupRecoveryCurrentCandidateIndex = nextIndex;
    this.startupRecoveryRetryInFlight = true;
    this.scheduleStartupRecoveryWatchdog(`candidate_${nextIndex}`);
    logger.debug(
      TAG,
      `启动直达恢复切换锚点: index=${nextIndex}, source=${nextCandidate.source}, domPos=${nextDomPos}`
    );
    logger.warn(
      TAG,
      `启动直达恢复重试: reason=${reason}, candidateIndex=${nextIndex}, domPos=${nextDomPos}`
    );
    this.clearStartupRecoveryRetryTimer();
    this.startupRecoveryRetryTimer = setTimeout((): void => {
      this.startupRecoveryRetryTimer = -1;
      if (this.startupRecoveryExpectedPageOffset <= 0 || this.startupRecoveryExpectedResourceIndex < 0) {
        this.startupRecoveryRetryInFlight = false;
        return;
      }
      if (nextIndex !== this.startupRecoveryCurrentCandidateIndex) {
        this.startupRecoveryRetryInFlight = false;
        return;
      }
      this.readerController.startPlay(this.startupRecoveryExpectedResourceIndex, nextDomPos)
        .then((): void => {
          this.startupRecoveryRetryInFlight = false;
        })
        .catch((error: Object): void => {
          this.startupRecoveryRetryInFlight = false;
          logger.debug(
            TAG,
            `启动直达恢复候选失败详情: index=${nextIndex}, source=${nextCandidate.source}, error=${String(error)}`
          );
          logger.warn(
            TAG,
            `启动直达恢复候选失败: index=${nextIndex}, error=${String(error)}`
          );
          const chained = this.triggerNextStartupDomPosCandidate(`candidate_error_${nextIndex}`);
          if (!chained && this.startupRecoveryAllowFlipFallback && this.startupRecoveryExpectedPageOffset > 0) {
            this.preparePageOffsetRecovery(this.startupRecoveryExpectedResourceIndex, this.startupRecoveryExpectedPageOffset);
          }
        });
    }, ReaderKitViewerComponent.STARTUP_DIRECT_RECOVERY_RETRY_DELAY_MS);
    return true;
  }

  private processStartupDirectRecovery(currentResourceIndex: number, currentPageOffset: number): boolean {
    if (this.startupRecoveryExpectedPageOffset <= 0 || this.startupRecoveryExpectedResourceIndex < 0) {
      return false;
    }
    if (currentResourceIndex !== this.startupRecoveryExpectedResourceIndex) {
      this.resetStartupDirectRecovery(`chapter_changed_${currentResourceIndex}`);
      return false;
    }
    if (currentPageOffset >= this.startupRecoveryExpectedPageOffset) {
      logger.info(
        TAG,
        `启动直达恢复成功: currentOffset=${currentPageOffset}, targetOffset=${this.startupRecoveryExpectedPageOffset}`
      );
      this.resetPendingPageOffsetRecovery('direct_recovery_success');
      this.resetStartupDirectRecovery('direct_recovery_success');
      return false;
    }
    const retried = this.triggerNextStartupDomPosCandidate(`page_offset_${currentPageOffset}`);
    if (retried) {
      return true;
    }
    if (this.startupRecoveryAllowFlipFallback) {
      this.preparePageOffsetRecovery(this.startupRecoveryExpectedResourceIndex, this.startupRecoveryExpectedPageOffset);
      this.startupRecoveryAllowFlipFallback = false;
      return true;
    }
    logger.warn(
      TAG,
      `启动直达恢复未命中目标且无更多候选: currentOffset=${currentPageOffset}, targetOffset=${this.startupRecoveryExpectedPageOffset}`
    );
    this.resetStartupDirectRecovery('direct_recovery_exhausted');
    return false;
  }

  private resetPendingPageOffsetRecovery(reason: string): void {
    if (this.pendingPageOffsetRecovery >= 0) {
      logger.info(
        TAG,
        `pageOffset恢复结束: reason=${reason}, target=${this.pendingPageOffsetRecovery}, steps=${this.pendingPageOffsetRecoveryStepCount}`
      );
    }
    this.pendingPageOffsetRecovery = -1;
    this.pendingPageOffsetRecoveryChapterIndex = -1;
    this.pendingPageOffsetRecoveryStepCount = 0;
  }

  private preparePageOffsetRecovery(chapterIndex: number, pageOffset: number): void {
    if (!this.isFiniteNumber(pageOffset) || pageOffset <= 0) {
      this.resetPendingPageOffsetRecovery('invalid_target');
      return;
    }
    const safeChapterIndex = Math.max(0, Math.floor(chapterIndex));
    const safePageOffset = Math.max(0, Math.floor(pageOffset));
    this.pendingPageOffsetRecovery = safePageOffset;
    this.pendingPageOffsetRecoveryChapterIndex = safeChapterIndex;
    this.pendingPageOffsetRecoveryStepCount = 0;
    logger.info(TAG, `准备 pageOffset 恢复: chapter=${safeChapterIndex}, targetOffset=${safePageOffset}`);
  }

  private tryRecoverPageOffsetByFlip(currentResourceIndex: number, currentPageOffset: number): void {
    if (this.pendingPageOffsetRecovery <= 0 || this.pendingPageOffsetRecoveryChapterIndex < 0) {
      return;
    }
    if (currentResourceIndex !== this.pendingPageOffsetRecoveryChapterIndex) {
      this.resetPendingPageOffsetRecovery(`resource_mismatch_${currentResourceIndex}`);
      return;
    }
    const safeCurrentOffset = Math.max(0, Math.floor(currentPageOffset));
    const delta = this.pendingPageOffsetRecovery - safeCurrentOffset;
    if (delta === 0) {
      this.resetPendingPageOffsetRecovery('target_reached');
      return;
    }
    if (this.pendingPageOffsetRecoveryStepCount >= ReaderKitViewerComponent.PAGE_OFFSET_RECOVERY_MAX_STEPS) {
      logger.warn(
        TAG,
        `pageOffset恢复超过最大步数: current=${safeCurrentOffset}, target=${this.pendingPageOffsetRecovery}, maxSteps=${ReaderKitViewerComponent.PAGE_OFFSET_RECOVERY_MAX_STEPS}`
      );
      this.resetPendingPageOffsetRecovery('exceed_max_steps');
      return;
    }
    const flipNext = delta > 0;
    this.pendingPageOffsetRecoveryStepCount += 1;
    logger.debug(
      TAG,
      `pageOffset恢复翻页: current=${safeCurrentOffset}, target=${this.pendingPageOffsetRecovery}, direction=${flipNext ? 'next' : 'prev'}, step=${this.pendingPageOffsetRecoveryStepCount}`
    );
    setTimeout((): void => {
      try {
        this.readerController.flipPage(flipNext);
      } catch (error) {
        logger.warn(TAG, `pageOffset恢复翻页失败: ${String(error)}`);
        this.resetPendingPageOffsetRecovery('flip_failed');
      }
    }, ReaderKitViewerComponent.PAGE_OFFSET_RECOVERY_FLIP_DELAY_MS);
  }

  /**
   * 获取 Reader Kit 文件类型
   */
  private getReaderKitFileType(): string {
    // TODO: 根据实际 Reader Kit API 返回正确的文件类型枚举
    return this.ebook.format;
  }

  /**
   * 跳转到指定章节
   */
  private async jumpToChapter(chapterIndex: number): Promise<void> {
    try {
      if (!this.controllerReady) {
        logger.warn(TAG, 'Reader Kit 控制器未就绪');
        return;
      }
      await this.readerController.startPlay(chapterIndex, '');

      if (this.onChapterChange) {
        this.onChapterChange(chapterIndex);
      }

      logger.info(TAG, `已跳转到章节: ${chapterIndex}`);
    } catch (error) {
      logger.error(TAG, `跳转章节失败: ${String(error)}`);
    }
  }

  /**
   * 尝试启动 Reader Kit 阅读器
   */
  private async tryStartReading(): Promise<void> {
    if (!this.controllerReady || this.sandboxPath.length === 0) {
      return;
    }
    try {
      const context = this.getUIContext()?.getHostContext() as common.UIAbilityContext;
      await this.readerController.init(context);
      const parserHandler: bookParser.BookParserHandler = await bookParser.getDefaultHandler(this.sandboxPath);
      this.readerController.registerBookParser(parserHandler);
      
      // 初始化并应用阅读设置
      this.readerSetting = this.initReaderSetting();
      this.readerController.setPageConfig(this.readerSetting);
      logger.info(TAG, `阅读设置已初始化: fontSize=${this.readerSetting.fontSize}, themeColor=${this.readerSetting.themeColor}`);
      this.lastPageAnchorSnapshot = null;

      // 注册 pageShow 事件监听器，用于获取当前阅读位置
      this.readerController.on('pageShow', (data: readerCore.PageDataInfo): void => {
        // PageDataInfo 包含 resourceIndex 和其他位置信息
        // 使用 JSON.stringify 获取完整数据用于调试
        const dataStr = JSON.stringify(data);
        logger.debug(TAG, `pageShow 事件: ${dataStr}`);
        this.currentPageData = data;
        const resourceIndex = this.normalizeResourceIndex(data.resourceIndex);
        const pageOffset = this.normalizePageOffset(data.pageOffset);
        this.updateLastPageAnchorSnapshot(data, resourceIndex, pageOffset);

        // 当页面显示完成时，通知外部保存进度
        if (data.state === readerCore.PageState.PAGE_ON_SHOW) {
          if (this.isLoading) {
            logger.info(TAG, '页面加载完成，隐藏加载状态');
          }
          this.isLoading = false;

          // 获取资源索引（章节索引）
          const activeRecoveryCandidate = this.getCurrentStartupRecoveryCandidate();
          if (this.startupRecoveryExpectedPageOffset > 0 && resourceIndex === this.startupRecoveryExpectedResourceIndex) {
            logger.debug(
              TAG,
              `启动直达恢复命中检查: source=${activeRecoveryCandidate ? activeRecoveryCandidate.source : 'none'}, currentOffset=${pageOffset}, targetOffset=${this.startupRecoveryExpectedPageOffset}, eventDataId=${this.normalizeAnchorValue(data.dataId)}, eventStartDomPos=${this.normalizeAnchorValue(data.startDomPos)}`
            );
          }
          const directRecoveryHandled = this.processStartupDirectRecovery(resourceIndex, pageOffset);
          this.tryRecoverPageOffsetByFlip(resourceIndex, pageOffset);
          const shouldSuppressProgress = directRecoveryHandled ||
            this.suppressProgressSaveDuringStartupRecovery ||
            (this.pendingPageOffsetRecovery > 0 &&
              resourceIndex === this.pendingPageOffsetRecoveryChapterIndex &&
              pageOffset < this.pendingPageOffsetRecovery);
          if (shouldSuppressProgress) {
            logger.debug(
              TAG,
              `恢复进行中，暂不回传进度: chapter=${resourceIndex}, pageOffset=${pageOffset}, target=${this.startupRecoveryExpectedPageOffset >= 0 ? this.startupRecoveryExpectedPageOffset : this.pendingPageOffsetRecovery}`
            );
            return;
          }
          const rawResourceCount = this.extractResourceCountFromPageDataJson(dataStr);

          // 计算阅读进度百分比
          const totalChapters = this.ebook.chapters.length || 0;
          let progress = -1;
          if (rawResourceCount > 0) {
            progress = ((resourceIndex + 1) / rawResourceCount) * 100;
          } else if (totalChapters > 1 && resourceIndex < totalChapters) {
            progress = ((resourceIndex + 1) / totalChapters) * 100;
          }

          // 将完整的页面数据作为位置信息保存（用于精确恢复）
          // PAGE_ON_SHOW 可能出现空锚点，这里回填最近一次非空锚点，保证 startPlay 可直达
          const positionData = this.buildPersistedPositionData(data, rawResourceCount);

          // 通知外部进度变化
          if (this.onProgressChange) {
            this.onProgressChange(progress, positionData);
          }

          // 通知章节变化
          if (this.onChapterChange && resourceIndex !== this.currentChapterIndex) {
            this.onChapterChange(resourceIndex);
          }
        }
      });

      // 使用保存的阅读位置启动阅读器
      // 注意：Reader Kit 的 resourceIndex 与 ebook_chapter 索引不是同一概念。
      // 恢复时优先使用 domPos(JSON) 里的 resourceIndex/startDomPos。
      let startIndex = this.currentChapterIndex || 0;
      let startDomPos = '';
      let startPageOffset = -1;
      let shouldRecoverByPageOffset = false;
      const startupDomPosCandidates: ReaderKitRestoreAnchorCandidate[] = [];
      if (this.initialDomPos && this.initialDomPos.length > 0) {
        try {
          // 如果保存的是 JSON 格式的 PageDataInfo，尝试解析
          if (this.initialDomPos.startsWith('{')) {
            const savedData = JSON.parse(this.initialDomPos) as ReaderKitSavedPositionData;
            const resourceIndex = savedData.resourceIndex;
            if (typeof resourceIndex === 'number' && this.isFiniteNumber(resourceIndex) && resourceIndex >= 0) {
              startIndex = Math.floor(resourceIndex);
            }
            const pageOffset = savedData.pageOffset;
            if (typeof pageOffset === 'number' && this.isFiniteNumber(pageOffset) && pageOffset >= 0) {
              startPageOffset = Math.floor(pageOffset);
            }

            let hasStructuredDomAnchor = false;
            const dataIdValue = savedData.dataId;
            if (typeof dataIdValue === 'string' && dataIdValue.length > 0) {
              this.appendUniqueDomPosCandidate(startupDomPosCandidates, dataIdValue, 'dataId');
              hasStructuredDomAnchor = true;
            }
            const domPosValue = savedData.domPos;
            if (typeof domPosValue === 'string' && domPosValue.length > 0) {
              this.appendUniqueDomPosCandidate(startupDomPosCandidates, domPosValue, 'domPos');
              hasStructuredDomAnchor = true;
            }
            const startDomPosValue = savedData.startDomPos;
            if (typeof startDomPosValue === 'string' && startDomPosValue.length > 0) {
              this.appendUniqueDomPosCandidate(startupDomPosCandidates, startDomPosValue, 'startDomPos');
              hasStructuredDomAnchor = true;
            }
            const endDomPosValue = savedData.endDomPos;
            if (typeof endDomPosValue === 'string' &&
              endDomPosValue.length > 0) {
              this.appendUniqueDomPosCandidate(startupDomPosCandidates, endDomPosValue, 'endDomPos');
              hasStructuredDomAnchor = true;
            }
            if (startupDomPosCandidates.length > 0) {
              startDomPos = startupDomPosCandidates[0].value;
            }
            if (!hasStructuredDomAnchor && startPageOffset <= 0) {
              logger.warn(TAG, '保存位置无可用 DOM 锚点且 pageOffset 无效，将回退到章节起始位置');
            }
            // 主路径优先直接使用多锚点 startPlay 直达；仅在无可用锚点时才预置翻页兜底。
            shouldRecoverByPageOffset = startupDomPosCandidates.length <= 0 && startPageOffset > 0;
          } else {
            // 直接使用字符串作为 domPos
            startDomPos = this.initialDomPos;
            this.appendUniqueDomPosCandidate(startupDomPosCandidates, this.initialDomPos, 'raw');
          }
        } catch (parseError) {
          logger.warn(TAG, `解析保存的位置数据失败: ${String(parseError)}`);
          startDomPos = '';
        }
      }


      this.configureStartupDirectRecovery(startIndex, startPageOffset, startupDomPosCandidates, startPageOffset > 0);
      this.resetPendingPageOffsetRecovery('before_start_play');
      if (shouldRecoverByPageOffset) {
        this.preparePageOffsetRecovery(startIndex, startPageOffset);
      }
      const initialRecoveryCandidate = this.getCurrentStartupRecoveryCandidate();
      logger.debug(
        TAG,
        `启动阅读器恢复锚点: source=${initialRecoveryCandidate ? initialRecoveryCandidate.source : (startDomPos.length > 0 ? 'manual' : 'none')}, domPos=${startDomPos}`
      );
      logger.info(TAG, `启动阅读器: resourceIndex=${startIndex}, domPos=${startDomPos}, pageOffset=${startPageOffset}`);
      try {
        await this.readerController.startPlay(startIndex, startDomPos);
      } catch (startError) {
        if (startDomPos.length > 0) {
          logger.debug(
            TAG,
            `启动阅读器首个锚点失败: source=${initialRecoveryCandidate ? initialRecoveryCandidate.source : 'unknown'}, error=${String(startError)}`
          );
          logger.warn(TAG, `带 domPos 启动失败，尝试切换下一个锚点: ${String(startError)}`);
          const retried = this.triggerNextStartupDomPosCandidate('initial_start_error');
          if (!retried) {
            startDomPos = '';
            await this.readerController.startPlay(startIndex, startDomPos);
          }
        } else {
          throw startError as Error;
        }
      }
      
      logger.info(TAG, 'Reader Kit 阅读器已初始化');
      
      // 通知外部控制器已就绪
      if (this.onControllerReady) {
        const controller: ReaderKitViewerController = {
          goToChapter: (chapterIndex: number, domPos?: string) => this.goToChapter(chapterIndex, domPos || ''),
          applyReadingSettings: (settings: EBookReadingSettings, force?: boolean) => this.applyReadingSettings(settings, force || false),
          isControllerReady: () => this.controllerReady
        };
        this.onControllerReady(controller);
        logger.info(TAG, '已通知外部控制器就绪');
      }
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `Reader Kit 阅读器初始化失败: ${errorMsg}`);
      this.errorMessage = errorMsg;
      this.isLoading = false;
    }
  }
  
  /**
   * 获取当前阅读位置信息
   */
  public getCurrentPageData(): readerCore.PageDataInfo | null {
    return this.currentPageData;
  }
  
  /**
   * 跳转到指定章节（公开方法，供外部调用）
   * @param chapterIndex 章节索引
   * @param domPos 可选的 DOM 位置
   */
  public async goToChapter(chapterIndex: number, domPos: string = ''): Promise<void> {
    try {
      if (!this.controllerReady) {
        logger.warn(TAG, 'Reader Kit 控制器未就绪，无法跳转章节');
        return;
      }
      
      logger.info(TAG, `跳转到章节: ${chapterIndex}, domPos=${domPos}`);
      this.resetPendingPageOffsetRecovery('manual_chapter_jump');
      this.resetStartupDirectRecovery('manual_chapter_jump');
      await this.readerController.startPlay(chapterIndex, domPos);
      
      if (this.onChapterChange) {
        this.onChapterChange(chapterIndex);
      }
    } catch (error) {
      logger.error(TAG, `跳转章节失败: ${String(error)}`);
    }
  }
  
  /**
   * 获取 Reader Kit 控制器（供外部直接操作）
   */
  public getReaderController(): readerCore.ReaderComponentController {
    return this.readerController;
  }
  
  /**
   * 检查控制器是否就绪
   */
  public isControllerReady(): boolean {
    return this.controllerReady;
  }

  build() {
    Stack() {
      // 1. 阅读器组件 - 始终渲染，使用 zIndex 控制层级
      ReadPageComponent({
        controller: this.readerController,
        readerCallback: (err: BusinessError, data: readerCore.ReaderComponentController) => {
          if (err) {
            logger.error(TAG, `ReadPageComponent init failed: ${err.code} ${err.message}`);
            this.errorMessage = `组件初始化失败: ${err.message}`;
            this.isLoading = false;
            return;
          }
          logger.info(TAG, 'ReadPageComponent 初始化成功');
          this.readerController = data;
          this.controllerReady = true;
          this.tryStartReading();
        }
      })
      .zIndex(1)

      // 2. 加载状态 - 使用 Visibility 控制显示/隐藏，而不是条件渲染
      Row() {
        Column({ space: 16 }) {
          LoadingProgress()
            .width(60)
            .height(60)
            .color(Color.Blue)
          
          Text('正在加载电子书...')
            .fontSize(14)
            .fontColor(Color.Gray)
        }
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .backgroundColor(Color.White)
      .zIndex(3)
      .visibility(this.isLoading ? Visibility.Visible : Visibility.None) 
      
      // 3. 错误状态 - 使用 Visibility 控制
      Column({ space: 16 }) {
        Image($r('sys.symbol.exclamationmark_circle_fill'))
          .width(80)
          .height(80)
          .fillColor(Color.Red)
        
        Text('加载失败')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.Red)
        
        Text(this.errorMessage)
          .fontSize(14)
          .fontColor(Color.Gray)
          .maxLines(3)
          .textAlign(TextAlign.Center)
          .width('80%')
        
        Button('重试')
          .fontSize(14)
          .onClick(() => {
            this.errorMessage = '';
            this.isLoading = true;
            this.initializeReaderSession();
          })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(Color.White)
      .padding(20)
      .zIndex(4)
      .visibility(this.errorMessage.length > 0 ? Visibility.Visible : Visibility.None)
    }
    .width('100%')
    .height('100%')
  }

  /**
   * 构建降级阅读器视图（当 Reader Kit 不可用时）
   */
  @Builder
  buildFallbackReaderView() {
    Scroll() {
      Column({ space: 16 }) {
        Text('Reader Kit 阅读器（待集成）')
          .fontSize(16)
          .fontColor(Color.Gray)
          .textAlign(TextAlign.Center)
          .padding(20)
        
        Text(`当前正在阅读：${this.ebook.metadata.title}`)
          .fontSize(14)
          .fontColor(Color.Gray)
          .textAlign(TextAlign.Center)
        
        // 章节内容区域
        this.buildChapterContent()
        
        // 章节导航
        Row({ space: 20 }) {
          Button('上一章')
            .fontSize(14)
            .height(40)
            .enabled(this.currentChapterIndex > 0)
            .onClick(() => {
              if (this.currentChapterIndex > 0) {
                this.jumpToChapter(this.currentChapterIndex - 1);
              }
            })
          
          Text(`${this.currentChapterIndex + 1} / ${this.ebook.chapters.length}`)
            .fontSize(14)
            .fontColor(this.ebook.readingSettings?.textColor || '#000000')
          
          Button('下一章')
            .fontSize(14)
            .height(40)
            .enabled(this.currentChapterIndex < this.ebook.chapters.length - 1)
            .onClick(() => {
              if (this.currentChapterIndex < this.ebook.chapters.length - 1) {
                this.jumpToChapter(this.currentChapterIndex + 1);
              }
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceEvenly)
        .padding({ top: 40, bottom: 40 })
      }
      .width('100%')
      .padding({ left: this.ebook.readingSettings?.pageMargin || 20, right: this.ebook.readingSettings?.pageMargin || 20 })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring)
  }

  /**
   * 构建章节内容
   */
  @Builder
  buildChapterContent() {
    if (this.ebook.chapters && this.ebook.chapters.length > 0 && 
        this.currentChapterIndex < this.ebook.chapters.length) {
      Column() {
        Text(this.ebook.chapters[this.currentChapterIndex].title)
          .fontSize((this.ebook.readingSettings?.fontSize || 18) + 2)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.ebook.readingSettings?.textColor || '#000000')
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 20, bottom: 10 })
        
        Text(this.ebook.chapters[this.currentChapterIndex].content)
          .fontSize(this.ebook.readingSettings?.fontSize || 18)
          .lineHeight((this.ebook.readingSettings?.fontSize || 18) * (this.ebook.readingSettings?.lineHeight || 1.9))
          .fontColor(this.ebook.readingSettings?.textColor || '#000000')
          .width('100%')
          .textAlign(TextAlign.Start)
      }
    }
  }
}



