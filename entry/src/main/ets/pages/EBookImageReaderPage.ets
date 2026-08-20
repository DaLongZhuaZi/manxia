import { SafeFileUtils } from 'manxia_core/src/main/ets/Utils/SafeFileUtils';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { ReaderSafeAreaUtils } from '../Utils/ReaderSafeAreaUtils';
import { common } from '@kit.AbilityKit';
import { display, promptAction, UIContext } from '@kit.ArkUI';
import fs from '@ohos.file.fs';
import { fileUri } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { KeyCode } from '@kit.InputKit';
import { WindowManager, DisplayMode } from '../Utils/WindowManager';
import { ReaderOrientationLockHelper } from 'manxia_core/src/main/ets/Utils/ReaderOrientationLockHelper';
import { PageWindowCoordinator } from '../Utils/PageWindowCoordinator';
import { ThemeManager } from 'manxia_theme/src/main/ets/Framework/Managers/ThemeManager';
import { getFontManager, FontScene } from '../Framework/Managers/FontManager';
import { EBookDataManager } from '../Framework/Data/EBookDataManager';
import { EBookParserFactory } from '../Framework/Parsers/EBookParser';
import { getUnifiedAnnotationManager } from '../Framework/Annotations/UnifiedAnnotationManager';
import { UnifiedContentType } from '../Models/UnifiedContentModels';
import { AnnotationAnchor, UnifiedAnnotationType } from '../Models/AnnotationModels';
import { AnnotationCenterPageParams } from './AnnotationCenterPage';
import {
  EBook,
  EBookChapter,
  EBookContentMode,
  EBookFormat,
  EBookReaderEngine,
  EBookReadingProgress
} from '../Models/EBookModels';
import {
  ReadingSettings as MangaReadingSettings,
  DEFAULT_READING_SETTINGS,
  ReadingMode,
  ReadingDirection,
  PageTurnAnimationType,
  MangaChapter
} from '../Models/MangaModels';
import {
  AutoPageTurnController,
  AutoPageTurnConfig,
  AutoPageTurnState
} from '../Framework/Utils/AutoPageTurnController';
import { MangaViewer } from '../components/MangaViewer';
import { MangaQuickSettings } from '../components/MangaQuickSettings';
import { MangaReaderSettings } from '../components/MangaReaderSettings';
import { MangaReaderChapterList } from '../components/MangaReaderChapterList';
import { MangaInteractionOverlay } from '../components/MangaInteractionOverlay';
import { PreloadDebugInfo, PreloadDebugOverlay } from '../components/PreloadDebugOverlay';
import {
  setReaderReady,
  setReaderLoadingProgress,
  startBookCloseTransitionWithComponentId,
  cancelTransition
} from '../components/BookTransitionOverlay';
import { eventBus, GameEvent, BasePayload } from '../Framework/EventBus';
import {
  buildEBookImageReaderRuntime,
  collectImageEntries,
  EBookImagePageEntry,
  EBookImageReaderRuntime,
  inspectEBookImagePageSignals,
  isImagePageEBook,
  resolveRuntimePageIndexByChapterId,
  shouldUseEBookImageReaderRoute
} from '../Framework/Adapters/EBookImageReaderAdapter';
import { EBookReaderParams } from './EBookReaderRouteTypes';
import { READER_ABILITY_HOST_MULTITON } from '../Framework/Reader/MangaReaderAbilityConstants';
import { distributedReadingService } from '../Framework/Distributed/DistributedReadingService';
import { distributedDataSyncManager, SyncReadingState } from '../Framework/Distributed/DistributedDataSyncManager';
import { MangaReadFlowMonitor } from '../Framework/Reader/MangaReadFlowMonitor';
import {
  MangaReadFlowEvent,
  MangaReadFlowEventType,
  MangaReadFlowModeKind,
  MangaReadFlowSessionInfo,
  MangaReadFlowSeverity,
  MangaReadFlowSourceKind,
  mapReadingModeToFlowMode
} from '../Framework/Reader/MangaReadFlowTypes';

const TAG = 'EBookImageReaderPage';

interface EBookBookmarkContext {
  chapterId: string;
  chapterTitle: string;
  chapterIndex: number;
  pageIndex: number;
  progress: number;
}

@Component
struct EBookImageReaderPage {
  private static readonly TOOLBAR_AUTO_HIDE_DELAY_MS: number = 2200;
  private static readonly PROGRESS_SAVE_INTERVAL_MS: number = 1200;
  private static readonly VIEWER_READY_DELAY_MS: number = 180;

  @State pathStack: NavPathStack = new NavPathStack();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;
  @StorageLink('preload_debug_mode') preloadDebugMode: string = 'off';
  @StorageProp('isInBackground') @Watch('onAppBackgroundStateChanged') appInBackground: boolean = false;

  @State ebook: EBook | null = null;
  @State runtimeChapter: MangaChapter | null = null;
  @State chapterListChapters: MangaChapter[] = [];
  private imageEntries: EBookImagePageEntry[] = [];
  private routerBackOnClose: boolean = false;
  private readerHostMode: string = '';
  private readerInstanceId: string = '';
  private originImportId: string = '';
  private originImportKind: string = '';

  @State readingSettings: MangaReadingSettings = DEFAULT_READING_SETTINGS;
  @State currentPageIndex: number = 0;
  @State viewerZoomScale: number = 1;
  @State preloadDebugInfo: PreloadDebugInfo = {
    currentPage: 0,
    totalPages: 0,
    preloadRange: 1,
    queueItems: [],
    completedCount: 0,
    failedCount: 0,
    memCacheHits: 0,
    diskCacheHits: 0,
    networkLoads: 0
  };

  @State isLoading: boolean = true;
  @State errorMessage: string = '';
  @State showTopToolbar: boolean = false;
  @State showBottomToolbar: boolean = false;
  @State toolbarOpacity: number = 0;
  @State showQuickSettings: boolean = false;
  @State showSettingsPanel: boolean = false;
  @State showMoreMenu: boolean = false;
  @State showChapterList: boolean = false;
  @State showAutoPageTurnSettings: boolean = false;
  @State showJumpToPageDialog: boolean = false;
  @State showPageTurnAnimationSettings: boolean = false;
  @State showInteractionOverlay: boolean = false;
  @State jumpToPageInput: string = '';
  @State settingsPanelOpacity: number = 0;
  @State settingsPanelScale: number = 0.95;
  @State settingsPanelTranslateY: number = 20;
  @State moreMenuOpacity: number = 0;
  @State moreMenuScale: number = 0.95;
  @State moreMenuTranslateY: number = -10;
  @State quickSettingsOpacity: number = 0;
  @State quickSettingsScale: number = 0.95;
  @State quickSettingsTranslateY: number = 20;
  @State autoPageTurnSettingsOpacity: number = 0;
  @State autoPageTurnSettingsScale: number = 0.95;
  @State autoPageTurnSettingsTranslateY: number = 20;
  @State autoPageTurnSettingsTranslateX: number = 320;
  @State pageTurnAnimationSettingsOpacity: number = 0;
  @State pageTurnAnimationSettingsScale: number = 0.95;
  @State pageTurnAnimationSettingsTranslateY: number = 20;
  @State pageTurnAnimationSettingsTranslateX: number = 320;
  @State jumpToPageDialogOpacity: number = 0;
  @State jumpToPageDialogScale: number = 0.9;
  @State autoPageTurnEnabled: boolean = false;
  @State autoPageTurnIntervalSeconds: number = 5;
  @State autoPageTurnState: AutoPageTurnState = AutoPageTurnState.STOPPED;
  @State isCurrentPageBookmarked: boolean = false;
  @State currentPageBookmarkId: string = '';
  @State componentWidth: number = 0;
  @State componentHeight: number = 0;
  @State screenWidth: number = 0;
  @State screenHeight: number = 0;
  @State isLandscapeMode: boolean = false;

  private uiContext: UIContext | undefined = undefined;
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private ebookDataManager: EBookDataManager = EBookDataManager.getInstance();
  private annotationManager = getUnifiedAnnotationManager();
  private autoPageTurnController: AutoPageTurnController | null = null;
  private mangaViewerComponent: MangaViewer | null = null;
  private toolbarAutoHideTimer: number = -1;
  private fullscreenRestoreTimer: number = -1;
  private interactionResumeTimer: number = -1;
  private sessionStartTimestamp: number = 0;
  private lastProgressSaveTime: number = 0;
  private lastSavedPageIndex: number = -1;
  private sourceCoverComponentId: string = '';
  private isCloseTransitionNavigating: boolean = false;
  private previousDisplayMode: DisplayMode = DisplayMode.DEFAULT;
  private orientationLockToken: string = '';
  private hasNotifiedTransitionReaderReady: boolean = false;
  private transitionLoadingProgress: number = 0;
  private isPageVisible: boolean = false;
  private isReaderInitialized: boolean = false;
  private initialViewerPageIndex: number = 0;
  private isSavingProgress: boolean = false;
  private pendingProgressSaveTrigger: string = '';
  private mangaReadFlowMonitor: MangaReadFlowMonitor = MangaReadFlowMonitor.getInstance();
  private mangaReadFlowSessionId: string = '';
  private mangaReadFlowLoadStartedAt: number = 0;
  private lastRemoteInstructionTimestamp: number = 0;
  private remoteCallbacksRegistered: boolean = false;
  private pendingContinuationPageIndex: number = -1;

  aboutToAppear(): void {
    this.isPageVisible = true;
    this.updateScreenMetrics();
    // [修复] 图片 EPUB 阅读器接入跨端接续状态机：前台标志 + 接续快照 + 遥控监听
    // （此前缺失导致 onContinue 读到旧书状态而拒绝流转 / 遥控指令无人响应）
    AppStorage.setOrCreate('currentReaderHostPage', 'EBookImageReaderPage');
    const continuationSessionId = AppStorage.get<string>('continuationSessionId');
    if (continuationSessionId && continuationSessionId.length > 0) {
      const snapshot = distributedReadingService.readContinuationSnapshot();
      if (snapshot && snapshot.pageIndex >= 0) {
        this.pendingContinuationPageIndex = snapshot.pageIndex;
        logger.info(TAG, `[Distributed] 图片电子书接续快照待应用: chapterIndex=${snapshot.chapterIndex}, pageIndex=${snapshot.pageIndex}`);
      }
      this.registerRemoteControlListener();
      // 图片路径为最终消费方：消费后清理接续标志，防止残留导致下次打开误触发
      distributedReadingService.clearContinuationFlags();
    }
  }

  aboutToDisappear(): void {
    this.isPageVisible = false;
    AppStorage.setOrCreate('currentReaderHostPage', '');
    this.unregisterRemoteControlListener();
    this.clearToolbarAutoHideTimer();
    this.clearFullscreenRestoreTimer();
    this.clearInteractionResumeTimer();
    if (this.autoPageTurnController) {
      this.autoPageTurnController.destroy();
      this.autoPageTurnController = null;
    }
    void this.persistImageReaderSettings('about_to_disappear');
    void this.saveReadingProgressInternal('about_to_disappear');
    this.orientationLockToken = ReaderOrientationLockHelper.release(this.orientationLockToken, this.uiContext);
    this.restoreNormalMode();
    eventBus.publish(GameEvent.EBOOK_UPDATED, new BasePayload());
    if (!this.isCloseTransitionNavigating) {
      cancelTransition();
    }
    if (this.mangaReadFlowSessionId.length > 0) {
      this.recordReadFlowEvent(
        MangaReadFlowEventType.CLEANUP,
        'about_to_disappear',
        this.currentPageIndex,
        'ebook_image_cleanup'
      );
      this.mangaReadFlowMonitor.endSession(this.mangaReadFlowSessionId, 'about_to_disappear');
      this.mangaReadFlowSessionId = '';
    }
  }

  onPageShow(): void {
    this.isPageVisible = true;
    if (this.shouldSkipFullscreenRestore('page_show')) {
      return;
    }
    this.setupFullscreenMode();
    PageWindowCoordinator.reapplyPagePolicy('EBookImageReaderPage', this.uiContext);
    WindowManager.reapplyCurrentDisplayMode(24);
    this.scheduleFullscreenRestore('page_show', 120);
    this.scheduleToolbarAutoHide('page_show');
    this.refreshCurrentEBookBookmarkState('page_show');
  }

  private onAppBackgroundStateChanged(): void {
    if (this.appInBackground || this.shouldSkipFullscreenRestore('app_foreground')) {
      return;
    }
    this.scheduleFullscreenRestore('app_foreground', 80);
  }

  private updateScreenMetrics(): void {
    try {
      const displayInfo = display.getDefaultDisplaySync();
      if (!displayInfo) {
        return;
      }
      const uiContext = this.uiContext ?? this.getUIContext();
      this.screenWidth = uiContext.px2vp(displayInfo.width);
      this.screenHeight = uiContext.px2vp(displayInfo.height);
      this.isLandscapeMode = this.screenWidth > this.screenHeight;
    } catch (error) {
      logger.warn(TAG, `更新屏幕尺寸失败: ${String(error)}`);
    }
  }

  private ensureReadFlowSession(bookId: string): void {
    if (this.mangaReadFlowSessionId.length > 0) {
      return;
    }
    const info: MangaReadFlowSessionInfo = new MangaReadFlowSessionInfo();
    info.sessionId = this.mangaReadFlowMonitor.createSessionId('ebook_image');
    info.sourceKind = MangaReadFlowSourceKind.EBOOK_IMAGE;
    info.modeKind = mapReadingModeToFlowMode(this.readingSettings.readingMode);
    info.contentId = bookId;
    info.contentTitle = this.ebook ? this.ebook.metadata.title : '';
    info.pageIndex = this.currentPageIndex;
    info.pageCount = this.getTotalPages();
    info.readerHostMode = this.readerHostMode;
    info.readerInstanceId = this.readerInstanceId;
    info.originImportId = this.originImportId;
    info.originImportKind = this.originImportKind;
    info.startedAt = Date.now();
    this.mangaReadFlowSessionId = this.mangaReadFlowMonitor.startSession(info);
    this.mangaReadFlowLoadStartedAt = info.startedAt;
  }

  private recordReadFlowEvent(
    eventType: MangaReadFlowEventType,
    reason: string,
    pageIndex: number,
    detail: string
  ): void {
    if (this.mangaReadFlowSessionId.length <= 0) {
      return;
    }
    const event: MangaReadFlowEvent = this.mangaReadFlowMonitor.createEvent(
      this.mangaReadFlowSessionId,
      eventType,
      this.ebook ? this.ebook.id : '',
      this.runtimeChapter ? this.runtimeChapter.id : '',
      pageIndex,
      reason
    );
    event.sourceKind = MangaReadFlowSourceKind.EBOOK_IMAGE;
    event.modeKind = mapReadingModeToFlowMode(this.readingSettings.readingMode);
    event.chapterTitle = this.runtimeChapter ? this.runtimeChapter.title : '';
    event.pageCount = this.getTotalPages();
    event.detail = detail;
    this.mangaReadFlowMonitor.record(event);
  }

  private recordReadFlowError(reason: string, errorMessage: string): void {
    if (this.mangaReadFlowSessionId.length <= 0) {
      return;
    }
    const event: MangaReadFlowEvent = this.mangaReadFlowMonitor.createEvent(
      this.mangaReadFlowSessionId,
      MangaReadFlowEventType.ERROR,
      this.ebook ? this.ebook.id : '',
      this.runtimeChapter ? this.runtimeChapter.id : '',
      this.currentPageIndex,
      reason
    );
    event.sourceKind = MangaReadFlowSourceKind.EBOOK_IMAGE;
    event.modeKind = MangaReadFlowModeKind.UNKNOWN;
    event.success = false;
    event.severity = MangaReadFlowSeverity.ERROR;
    event.errorMessage = errorMessage;
    this.mangaReadFlowMonitor.record(event);
  }

  private reportTransitionLoadingProgress(progress: number, reason: string): void {
    const normalized = Math.max(0, Math.min(1, progress > 1 ? progress / 100 : progress));
    if (normalized <= this.transitionLoadingProgress + 0.001) {
      return;
    }
    this.transitionLoadingProgress = normalized;
    setReaderLoadingProgress(normalized);
    logger.debug(TAG, `过渡加载进度: ${(normalized * 100).toFixed(1)}%, 原因=${reason}`);
  }

  private notifyTransitionReaderReadyOnce(reason: string): void {
    if (this.hasNotifiedTransitionReaderReady) {
      return;
    }
    this.hasNotifiedTransitionReaderReady = true;
    this.reportTransitionLoadingProgress(1, `ready_${reason}`);
    setReaderReady();
  }

  private shouldSkipFullscreenRestore(reason: string): boolean {
    if (this.isCloseTransitionNavigating) {
      logger.debug(TAG, `跳过沉浸模式恢复: 页面正在关闭, 原因=${reason}`);
      return true;
    }
    if (!this.isPageVisible) {
      logger.debug(TAG, `跳过沉浸模式恢复: 页面不可见, 原因=${reason}`);
      return true;
    }
    return false;
  }

  private setupFullscreenMode(): void {
    try {
      if (this.shouldSkipFullscreenRestore('setup_fullscreen')) {
        return;
      }
      if (!this.uiContext) {
        this.uiContext = this.getUIContext();
      }
      if (!this.uiContext) {
        logger.warn(TAG, '进入沉浸模式失败：UIContext 为空');
        return;
      }
      const currentMode = WindowManager.getCurrentMode();
      if (currentMode !== DisplayMode.FULL_IMMERSIVE) {
        this.previousDisplayMode = currentMode;
      }
      WindowManager.setDisplayModeWithTransition(DisplayMode.FULL_IMMERSIVE, this.uiContext);
      PageWindowCoordinator.reapplyPagePolicy('EBookImageReaderPage', this.uiContext);
      WindowManager.reapplyCurrentDisplayMode(24);
      logger.info(TAG, '已进入全沉浸模式');
    } catch (error) {
      logger.warn(TAG, `进入沉浸模式失败: ${String(error)}`);
    }
  }

  private scheduleFullscreenRestore(reason: string, delayMs: number = 120): void {
    this.clearFullscreenRestoreTimer();
    if (this.shouldSkipFullscreenRestore(`schedule_${reason}`)) {
      return;
    }
    this.fullscreenRestoreTimer = setTimeout(() => {
      this.fullscreenRestoreTimer = -1;
      if (this.shouldSkipFullscreenRestore(`timer_${reason}`)) {
        return;
      }
      const uiContext = this.getUIContext() ?? this.uiContext;
      PageWindowCoordinator.reapplyPagePolicy('EBookImageReaderPage', uiContext);
      WindowManager.setDisplayMode(DisplayMode.FULL_IMMERSIVE, uiContext ?? undefined);
      WindowManager.reapplyCurrentDisplayMode(24);
      logger.debug(TAG, `已重新应用沉浸模式: ${reason}`);
      if (this.showTopToolbar || this.showBottomToolbar) {
        this.scheduleToolbarAutoHide(`fullscreen_restore_${reason}`);
      }
    }, delayMs);
  }

  private clearFullscreenRestoreTimer(): void {
    if (this.fullscreenRestoreTimer !== -1) {
      clearTimeout(this.fullscreenRestoreTimer);
      this.fullscreenRestoreTimer = -1;
    }
  }

  private restoreNormalMode(): void {
    try {
      const uiContext = this.getUIContext() ?? this.uiContext;
      if (!uiContext) {
        logger.warn(TAG, '恢复正常显示模式失败: UIContext 为空');
        return;
      }

      const targetMode = this.previousDisplayMode === DisplayMode.FULL_IMMERSIVE
        ? DisplayMode.DEFAULT
        : this.previousDisplayMode;
      WindowManager.setDisplayMode(targetMode, uiContext);
      WindowManager.reapplyCurrentDisplayMode(180);
      logger.info(TAG, `恢复显示模式: ${targetMode}`);
    } catch (error) {
      logger.error(TAG, `恢复正常模式失败: ${String(error)}`);
    }
  }

  private clearToolbarAutoHideTimer(): void {
    if (this.toolbarAutoHideTimer !== -1) {
      clearTimeout(this.toolbarAutoHideTimer);
      this.toolbarAutoHideTimer = -1;
    }
  }

  private clearInteractionResumeTimer(): void {
    if (this.interactionResumeTimer !== -1) {
      clearTimeout(this.interactionResumeTimer);
      this.interactionResumeTimer = -1;
    }
  }

  private async initializeWithParams(params: EBookReaderParams): Promise<void> {
    this.sourceCoverComponentId = params.coverComponentId || '';
    this.routerBackOnClose = params.routerBackOnClose === true;
    this.readerHostMode = params.readerHostMode || '';
    this.readerInstanceId = params.readerInstanceId || '';
    this.originImportId = params.originImportId || '';
    this.originImportKind = params.originImportKind || '';
    await this.loadEBook(params.bookId);
  }

  private ensureViewerReadFlowSession(): void {
    if (this.mangaReadFlowSessionId.length <= 0 && this.ebook) {
      this.ensureReadFlowSession(this.ebook.id);
    }
  }

  private shouldRepairImagePageBookData(ebook: EBook): boolean {
    if (ebook.format !== EBookFormat.EPUB) {
      return false;
    }
    if (!shouldUseEBookImageReaderRoute(ebook) && !isImagePageEBook(ebook)) {
      return false;
    }
    const chapters = ebook.chapters || [];
    if (chapters.length <= 0) {
      return true;
    }
    return chapters.some((chapter: EBookChapter) => {
      return (chapter.resourceImagePath || '').trim().length <= 0 &&
        (chapter.resourceImageRelativePath || '').trim().length <= 0;
    });
  }

  private buildReparsedChapterList(reparsed: EBook, targetBookId: string): EBookChapter[] {
    const now = Date.now();
    return reparsed.chapters.map((chapter: EBookChapter, index: number) => {
      const chapterTitle = chapter.title && chapter.title.trim().length > 0 ? chapter.title : `第${index + 1}页`;
      const chapterContent = chapter.content || '';
      const rebuiltChapter: EBookChapter = {
        id: `rk_${targetBookId}_${index}`,
        bookId: targetBookId,
        chapterNumber: index + 1,
        title: chapterTitle,
        content: chapterContent,
        startPosition: chapter.startPosition || 0,
        endPosition: chapter.endPosition || chapterContent.length,
        wordCount: chapter.wordCount || chapterContent.length,
        resourceHref: chapter.resourceHref || '',
        resourceFile: chapter.resourceFile || '',
        resourceMediaType: chapter.resourceMediaType || '',
        resourceLayoutType: chapter.resourceLayoutType || '',
        resourceImagePath: chapter.resourceImagePath || '',
        resourceImageRelativePath: chapter.resourceImageRelativePath || '',
        createTime: chapter.createTime || now
      };
      return rebuiltChapter;
    });
  }

  private mergeMetadataFromReparsed(ebook: EBook, reparsed: EBook): boolean {
    let changed = false;
    const current = ebook.metadata;
    const incoming = reparsed.metadata;

    if ((!current.title || current.title.trim().length <= 0) && incoming.title && incoming.title.trim().length > 0) {
      current.title = incoming.title;
      changed = true;
    }
    if ((!current.author || current.author.trim().length <= 0 || current.author === '未知作者') &&
      incoming.author && incoming.author.trim().length > 0 && incoming.author !== '未知作者') {
      current.author = incoming.author;
      changed = true;
    }
    if ((!current.publisher || current.publisher.trim().length <= 0) && incoming.publisher && incoming.publisher.trim().length > 0) {
      current.publisher = incoming.publisher;
      changed = true;
    }
    if ((!current.publishDate || current.publishDate.trim().length <= 0) && incoming.publishDate && incoming.publishDate.trim().length > 0) {
      current.publishDate = incoming.publishDate;
      changed = true;
    }
    if ((!current.isbn || current.isbn.trim().length <= 0) && incoming.isbn && incoming.isbn.trim().length > 0) {
      current.isbn = incoming.isbn;
      changed = true;
    }
    if ((!current.language || current.language.trim().length <= 0) && incoming.language && incoming.language.trim().length > 0) {
      current.language = incoming.language;
      changed = true;
    }
    if ((!current.description || current.description.trim().length <= 0) &&
      incoming.description && incoming.description.trim().length > 0) {
      current.description = incoming.description;
      changed = true;
    }
    if ((!current.coverImagePath || current.coverImagePath.trim().length <= 0) &&
      incoming.coverImagePath && incoming.coverImagePath.trim().length > 0) {
      current.coverImagePath = incoming.coverImagePath;
      changed = true;
    }
    if (incoming.tags && incoming.tags.length > 0) {
      const mergedTags = Array.from(new Set([...(current.tags || []), ...incoming.tags]));
      if (mergedTags.length !== (current.tags || []).length) {
        current.tags = mergedTags;
        changed = true;
      }
    }
    return changed;
  }

  private async tryRepairImagePageBookData(ebook: EBook): Promise<EBook> {
    if (!this.shouldRepairImagePageBookData(ebook)) {
      return ebook;
    }

    try {
      logger.info(TAG, `图片 EPUB 数据可能不完整，开始尝试修复: ${ebook.id}`);
      const parser = EBookParserFactory.createParser(ebook.filePath);
      if (!parser) {
        logger.warn(TAG, `无法为图片 EPUB 修复创建解析器: ${ebook.filePath}`);
        return ebook;
      }

      const reparsed = await parser.parse();
      const currentImageCount = collectImageEntries(ebook).length;
      const reparsedImageCount = collectImageEntries(reparsed).length;
      let changed = false;

      if (reparsed.contentMode === EBookContentMode.IMAGE_PAGE && reparsedImageCount > currentImageCount) {
        ebook.chapters = this.buildReparsedChapterList(reparsed, ebook.id);
        changed = true;
        logger.info(TAG, `图片 EPUB 章节修复成功: ${currentImageCount} -> ${reparsedImageCount}`);
      }

      if (this.mergeMetadataFromReparsed(ebook, reparsed)) {
        changed = true;
      }
      if (reparsed.contentMode && reparsed.contentMode !== ebook.contentMode) {
        ebook.contentMode = reparsed.contentMode;
        changed = true;
      }
      if (reparsed.preferredReaderEngine && reparsed.preferredReaderEngine !== ebook.preferredReaderEngine) {
        ebook.preferredReaderEngine = reparsed.preferredReaderEngine;
        changed = true;
      }
      if ((reparsed.extractedRootPath || '').length > 0 && reparsed.extractedRootPath !== ebook.extractedRootPath) {
        ebook.extractedRootPath = reparsed.extractedRootPath;
        changed = true;
      }

      if (changed) {
        ebook.lastUpdateTime = Date.now();
        if (ebook.chapters.length > 0) {
          const previousProgress = ebook.readingProgress;
          const safeIndex = Math.max(0, Math.min(previousProgress?.currentChapterIndex ?? 0, ebook.chapters.length - 1));
          ebook.readingProgress.currentChapterId = ebook.chapters[safeIndex].id;
        }
        await this.ebookDataManager.saveEBook(ebook, { skipReadingSettings: true });
        logger.info(TAG, `图片 EPUB 修复完成: ${ebook.metadata.title}`);
      }
    } catch (error) {
      logger.warn(TAG, `图片 EPUB 修复失败: ${String(error)}`);
    }

    return ebook;
  }

  private async loadEBook(bookId: string): Promise<void> {
    this.isLoading = true;
    this.errorMessage = '';
    this.hasNotifiedTransitionReaderReady = false;
    this.transitionLoadingProgress = 0;
    this.isReaderInitialized = false;
    this.ensureReadFlowSession(bookId);
    this.reportTransitionLoadingProgress(0.08, 'load_start');

    try {
      let ebook = await this.ebookDataManager.getEBookById(bookId);
      if (!ebook) {
        throw new Error('未找到电子书');
      }
      const initialSignalStats = inspectEBookImagePageSignals(ebook);
      const initialImageEntryCount = collectImageEntries(ebook).length;
      const shouldHandleAsImagePage = ebook.format === EBookFormat.EPUB &&
        (shouldUseEBookImageReaderRoute(ebook) || initialImageEntryCount > 0);
      logger.info(
        TAG,
        `图片阅读路由检查: bookId=${ebook.id}, format=${ebook.format}, contentMode=${ebook.contentMode}, ` +
          `preferredReaderEngine=${ebook.preferredReaderEngine}, chapters=${initialSignalStats.totalChapters}, ` +
          `imageEntries=${initialImageEntryCount}, strongSignalChapters=${initialSignalStats.strongSignalChapters}, ` +
          `sparsePageLikeChapters=${initialSignalStats.sparsePageLikeChapters}, shouldHandle=${shouldHandleAsImagePage}`
      );
      if (!shouldHandleAsImagePage) {
        throw new Error('当前电子书不是图片型 EPUB');
      }
      ebook = await this.tryRepairImagePageBookData(ebook);
      const repairedImageEntryCount = collectImageEntries(ebook).length;
      if (!isImagePageEBook(ebook) && repairedImageEntryCount <= 0) {
        throw new Error('当前图片 EPUB 没有可渲染的图片页');
      }
      logger.info(
        TAG,
        `图片阅读器已确认使用图片模式: bookId=${ebook.id}, contentMode=${ebook.contentMode}, ` +
          `preferredReaderEngine=${ebook.preferredReaderEngine}, imageEntries=${repairedImageEntryCount}`
      );

      const settings = await this.ebookDataManager.loadImageReaderSettings(ebook.id);
      logger.info(
        TAG,
        `图片电子书最终阅读设置已加载：书籍ID=${ebook.id}，阅读模式=${settings.readingMode}，阅读方向=${settings.readingDirection}，翻页动画=${settings.pageTurnAnimation}`
      );
      const runtime: EBookImageReaderRuntime = buildEBookImageReaderRuntime(ebook, settings);
      if (runtime.imageEntries.length <= 0) {
        throw new Error('未找到可渲染的图片页');
      }

      this.ebook = ebook;
      this.recordReadFlowEvent(
        MangaReadFlowEventType.CHAPTER_RESOLVED,
        'ebook_image_loaded',
        runtime.initialPageIndex,
        `title=${ebook.metadata.title}, entries=${runtime.imageEntries.length}`
      );
      this.imageEntries = runtime.imageEntries;
      this.runtimeChapter = runtime.runtimeChapter;
      this.chapterListChapters = runtime.chapterListChapters;
      this.readingSettings = this.cloneReadingSettings(settings);
      this.syncDeviceOrientationLock('settings_loaded');
      this.currentPageIndex = runtime.initialPageIndex;
      this.initialViewerPageIndex = runtime.initialPageIndex;
      // [修复] 跨端接续：用源端 wantParam 快照页索引覆盖本地进度（图片 EPUB 全局页索引）
      if (this.pendingContinuationPageIndex >= 0) {
        const totalPages = this.getTotalPages();
        const continuationPage = Math.max(0, Math.min(this.pendingContinuationPageIndex, Math.max(0, totalPages - 1)));
        this.currentPageIndex = continuationPage;
        this.initialViewerPageIndex = continuationPage;
        logger.info(TAG, `[Distributed] 已应用图片电子书接续快照: pageIndex=${continuationPage}, totalPages=${totalPages}`);
        this.pendingContinuationPageIndex = -1;
      }
      this.viewerZoomScale = 1;
      this.updatePreloadDebugInfo(runtime.initialPageIndex);
      this.sessionStartTimestamp = Date.now();
      this.lastProgressSaveTime = 0;
      this.lastSavedPageIndex = -1;
      this.syncAutoPageTurnStateFromSettings(false);
      // [修复] 加载完成立即同步一次阅读状态：打开书籍后未翻页就触发接续时，
      // onContinue 守卫依赖 currentRead*（此前该状态只随进度保存更新，会误判拒绝流转）
      const loadedPageEntry = this.getCurrentPageEntry();
      const loadedChapterIndex = loadedPageEntry ? loadedPageEntry.ebookChapterIndex : 0;
      distributedReadingService.syncProgress(ebook.id, loadedChapterIndex, this.currentPageIndex, 0, 'ebook');
      logger.info(TAG, `阅读状态已就绪: bookId=${ebook.id}, chapter=${loadedChapterIndex}, page=${this.currentPageIndex}`);
      this.refreshCurrentEBookBookmarkState('load_complete');
      this.isLoading = false;
      this.recordReadFlowEvent(
        MangaReadFlowEventType.PAGES_RESOLVED,
        'ebook_image_pages_ready',
        runtime.initialPageIndex,
        `pages=${runtime.imageEntries.length}, elapsed=${Date.now() - this.mangaReadFlowLoadStartedAt}`
      );
      this.reportTransitionLoadingProgress(0.84, 'view_ready');
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      this.errorMessage = message;
      this.isLoading = false;
      this.recordReadFlowError('ebook_image_load_failed', message);
      this.notifyTransitionReaderReadyOnce('load_failed');
    }
  }

  private cloneReadingSettings(settings: MangaReadingSettings): MangaReadingSettings {
    return {
      readingMode: settings.readingMode,
      readingDirection: settings.readingDirection,
      brightness: settings.brightness,
      keepScreenOn: settings.keepScreenOn,
      lockDeviceOrientation: settings.lockDeviceOrientation ?? DEFAULT_READING_SETTINGS.lockDeviceOrientation ?? false,
      lockMode: settings.lockMode ?? settings.lockOrientation ?? DEFAULT_READING_SETTINGS.lockMode ?? false,
      lockOrientation: settings.lockMode ?? settings.lockOrientation ?? DEFAULT_READING_SETTINGS.lockMode ?? false,
      pageSpacing: settings.pageSpacing,
      showPageInfo: settings.showPageInfo,
      showPageIndicator: settings.showPageIndicator,
      fitMode: settings.fitMode,
      autoPageTurnInterval: settings.autoPageTurnInterval,
      skipIntroPages: settings.skipIntroPages,
      pageTurnAnimation: settings.pageTurnAnimation,
      doublePagePortraitLayout: settings.doublePagePortraitLayout,
      doublePageVerticalDirection: settings.doublePageVerticalDirection ?? DEFAULT_READING_SETTINGS.doublePageVerticalDirection,
      filterSettings: {
        enabled: settings.filterSettings.enabled,
        brightness: settings.filterSettings.brightness,
        contrast: settings.filterSettings.contrast,
        saturation: settings.filterSettings.saturation,
        hue: settings.filterSettings.hue,
        gamma: settings.filterSettings.gamma,
        sepia: settings.filterSettings.sepia,
        invert: settings.filterSettings.invert,
        grayscale: settings.filterSettings.grayscale,
        blur: settings.filterSettings.blur
      },
      volumeKeyNavigation: settings.volumeKeyNavigation,
      curlBackOpacity: settings.curlBackOpacity ?? DEFAULT_READING_SETTINGS.curlBackOpacity,
      webtoonLeftMargin: settings.webtoonLeftMargin ?? DEFAULT_READING_SETTINGS.webtoonLeftMargin,
      webtoonRightMargin: settings.webtoonRightMargin ?? DEFAULT_READING_SETTINGS.webtoonRightMargin,
      webtoonMarginSync: settings.webtoonMarginSync ?? DEFAULT_READING_SETTINGS.webtoonMarginSync
    };
  }

  private syncDeviceOrientationLock(reason: string): void {
    if (!this.uiContext) {
      this.uiContext = this.getUIContext();
    }
    const enabled: boolean = this.readingSettings.lockDeviceOrientation ??
      DEFAULT_READING_SETTINGS.lockDeviceOrientation ??
      false;
    this.orientationLockToken = ReaderOrientationLockHelper.syncCurrentOrientationLock(
      'EBookImageReaderPage',
      this.orientationLockToken,
      enabled,
      this.uiContext
    );
    logger.info(TAG, `设备方向锁同步完成: enabled=${enabled}, reason=${reason}`);
  }

  private getTotalPages(): number {
    return this.runtimeChapter?.pages.length || this.imageEntries.length || 0;
  }

  private updatePreloadDebugInfo(currentPageIndex: number): void {
    this.preloadDebugInfo = {
      currentPage: currentPageIndex,
      totalPages: this.getTotalPages(),
      preloadRange: 1,
      queueItems: this.preloadDebugInfo.queueItems,
      completedCount: this.preloadDebugInfo.completedCount,
      failedCount: this.preloadDebugInfo.failedCount,
      memCacheHits: this.preloadDebugInfo.memCacheHits,
      diskCacheHits: this.preloadDebugInfo.diskCacheHits,
      networkLoads: this.preloadDebugInfo.networkLoads
    };
  }

  private getCurrentPageEntry(): EBookImagePageEntry | null {
    if (this.imageEntries.length <= 0) {
      return null;
    }
    const safeIndex = Math.max(0, Math.min(this.currentPageIndex, this.imageEntries.length - 1));
    return this.imageEntries[safeIndex];
  }

  private getCurrentChapterListId(): string {
    return this.getCurrentPageEntry()?.ebookChapter.id || this.runtimeChapter?.id || '';
  }

  private buildEBookBookmarkTitle(context: EBookBookmarkContext): string {
    return `${context.chapterTitle} · 第${context.pageIndex + 1}页`;
  }

  private buildCurrentEBookBookmarkAnchor(context: EBookBookmarkContext): AnnotationAnchor {
    return {
      chapterId: context.chapterId,
      chapterTitle: context.chapterTitle,
      chapterIndex: context.chapterIndex,
      pageIndex: context.pageIndex,
      progress: context.progress,
      startOffset: -1,
      endOffset: -1
    };
  }

  private getCurrentEBookBookmarkContext(): EBookBookmarkContext | null {
    const entry = this.getCurrentPageEntry();
    if (!entry) {
      return null;
    }
    const totalPages = this.getTotalPages();
    return {
      chapterId: entry.ebookChapter.id,
      chapterTitle: entry.title,
      chapterIndex: entry.ebookChapterIndex,
      pageIndex: this.currentPageIndex,
      progress: totalPages > 0 ? Math.max(0, Math.min(1, (this.currentPageIndex + 1) / totalPages)) : 0
    };
  }

  private refreshCurrentEBookBookmarkState(trigger: string): void {
    void this.refreshCurrentEBookBookmarkStateInternal(trigger);
  }

  private async refreshCurrentEBookBookmarkStateInternal(trigger: string): Promise<void> {
    if (!this.ebook) {
      this.currentPageBookmarkId = '';
      this.isCurrentPageBookmarked = false;
      return;
    }
    const context = this.getCurrentEBookBookmarkContext();
    if (!context) {
      this.currentPageBookmarkId = '';
      this.isCurrentPageBookmarked = false;
      return;
    }

    try {
      const bookmarks = await this.annotationManager.getContentAnnotations(
        UnifiedContentType.EBOOK,
        this.ebook.id,
        UnifiedAnnotationType.BOOKMARK,
        context.chapterId,
        context.chapterIndex
      );
      let matchedId = '';
      for (let index = 0; index < bookmarks.length; index++) {
        const item = bookmarks[index];
        if (item.pageIndex >= 0 && item.pageIndex === context.pageIndex) {
          matchedId = item.id;
          break;
        }
      }
      this.currentPageBookmarkId = matchedId;
      this.isCurrentPageBookmarked = matchedId.length > 0;
      logger.debug(TAG, `已刷新图片 EPUB 书签状态: 触发源=${trigger}, 页索引=${context.pageIndex}`);
    } catch (error) {
      logger.error(TAG, `刷新图片 EPUB 书签状态失败: ${String(error)}`);
      this.currentPageBookmarkId = '';
      this.isCurrentPageBookmarked = false;
    }
  }

  private async createCurrentEBookBookmark(): Promise<void> {
    if (!this.ebook) {
      this.getUIContext().getPromptAction().showToast({ message: '电子书尚未就绪' });
      return;
    }
    const context = this.getCurrentEBookBookmarkContext();
    if (!context) {
      this.getUIContext().getPromptAction().showToast({ message: '当前页面无法添加书签' });
      return;
    }
    try {
      const bookmark = await this.annotationManager.createBookmark({
        contentType: UnifiedContentType.EBOOK,
        contentId: this.ebook.id,
        title: this.buildEBookBookmarkTitle(context),
        anchor: this.buildCurrentEBookBookmarkAnchor(context)
      });
      this.currentPageBookmarkId = bookmark.id;
      this.isCurrentPageBookmarked = true;
      this.getUIContext().getPromptAction().showToast({ message: '书签已添加' });
    } catch (error) {
      logger.error(TAG, `添加图片 EPUB 书签失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: '添加书签失败' });
    }
  }

  private async removeCurrentEBookBookmark(): Promise<void> {
    let bookmarkId = this.currentPageBookmarkId;
    if (!bookmarkId || bookmarkId.trim().length <= 0) {
      await this.refreshCurrentEBookBookmarkStateInternal('remove_before_refresh');
      bookmarkId = this.currentPageBookmarkId;
    }
    if (!bookmarkId || bookmarkId.trim().length <= 0) {
      this.getUIContext().getPromptAction().showToast({ message: '当前页面暂无书签' });
      return;
    }
    try {
      await this.annotationManager.deleteAnnotation(bookmarkId);
      this.currentPageBookmarkId = '';
      this.isCurrentPageBookmarked = false;
      this.getUIContext().getPromptAction().showToast({ message: '书签已移除' });
    } catch (error) {
      logger.error(TAG, `移除图片 EPUB 书签失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: '移除书签失败' });
    }
  }

  private toggleCurrentEBookBookmark(): void {
    if (this.isCurrentPageBookmarked) {
      void this.removeCurrentEBookBookmark();
      return;
    }
    void this.createCurrentEBookBookmark();
  }

  private openCurrentEBookAnnotationCenter(): void {
    if (!this.ebook) {
      this.getUIContext().getPromptAction().showToast({ message: '电子书尚未就绪' });
      return;
    }
    const context = this.getCurrentEBookBookmarkContext();
    const params: AnnotationCenterPageParams = {
      contentType: UnifiedContentType.EBOOK,
      contentId: this.ebook.id,
      contentTitle: this.ebook.metadata.title || '',
      readerContext: {
        ebook: {
          chapterIndex: context?.chapterIndex ?? 0,
          pageIndex: context?.pageIndex ?? this.currentPageIndex
        }
      }
    };
    try {
      PageWindowCoordinator.navigateWithManagedTransition(
        'EBookImageReaderPage',
        'AnnotationCenterPage',
        () => {
          this.pathStack.pushPathByName('AnnotationCenterPage', params);
        },
        this.getUIContext()
      );
    } catch (error) {
      logger.error(TAG, `打开批注中心失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: '打开批注中心失败' });
    }
  }

  private buildReadingProgress(totalReadingTime: number, now: number): EBookReadingProgress | null {
    const ebook = this.ebook;
    const entry = this.getCurrentPageEntry();
    const totalPages = this.getTotalPages();
    if (!ebook || !entry || totalPages <= 0) {
      return null;
    }

    return {
      bookId: ebook.id,
      currentChapterId: entry.ebookChapter.id,
      currentChapterIndex: entry.ebookChapterIndex,
      currentPosition: this.currentPageIndex,
      domPos: `image-page:${this.currentPageIndex}`,
      progress: Math.max(0, Math.min(100, ((this.currentPageIndex + 1) / totalPages) * 100)),
      lastReadTime: now,
      totalReadingTime: totalReadingTime
    };
  }

  private async performReadingProgressSave(trigger: string): Promise<void> {
    const ebook = this.ebook;
    if (!ebook || this.imageEntries.length <= 0) {
      return;
    }

    const now = Date.now();
    if (
      trigger !== 'about_to_disappear' &&
      this.lastSavedPageIndex === this.currentPageIndex &&
      (now - this.lastProgressSaveTime) < EBookImageReaderPage.PROGRESS_SAVE_INTERVAL_MS
    ) {
      return;
    }

    const baseTotalReadingTime = ebook.readingProgress?.totalReadingTime || 0;
    const sessionSeconds = this.sessionStartTimestamp > 0 ? Math.max(0, (now - this.sessionStartTimestamp) / 1000) : 0;
    const progress = this.buildReadingProgress(baseTotalReadingTime + sessionSeconds, now);
    if (!progress) {
      return;
    }

    await this.ebookDataManager.saveReadingProgress(progress);
    ebook.readingProgress = progress;
    // [修复] 同步跨端接续阅读状态（currentRead* + 独立通道推送），
    // 图片 EPUB 阅读器此前缺失该调用，导致 onContinue 打包旧书状态被拒绝
    distributedReadingService.syncProgress(ebook.id, progress.currentChapterIndex, progress.currentPosition, 0, 'ebook');
    this.recordReadFlowEvent(
      MangaReadFlowEventType.PROGRESS_SAVED,
      trigger,
      this.currentPageIndex,
      `progress=${progress.progress}`
    );
    this.lastProgressSaveTime = now;
    this.lastSavedPageIndex = this.currentPageIndex;
    this.sessionStartTimestamp = now;
  }

  private async saveReadingProgressInternal(trigger: string): Promise<void> {
    if (this.isSavingProgress) {
      this.pendingProgressSaveTrigger = trigger;
      logger.debug(TAG, `阅读进度正在保存，已记录最新触发源: ${trigger}`);
      return;
    }

    this.isSavingProgress = true;
    let nextTrigger = trigger;
    try {
      while (nextTrigger.length > 0) {
        const currentTrigger = nextTrigger;
        this.pendingProgressSaveTrigger = '';
        await this.performReadingProgressSave(currentTrigger);
        nextTrigger = this.pendingProgressSaveTrigger;
      }
    } finally {
      this.pendingProgressSaveTrigger = '';
      this.isSavingProgress = false;
    }
  }

  private saveReadingProgress(trigger: string): void {
    void this.saveReadingProgressInternal(trigger).catch((error: Error) => {
      logger.error(TAG, `保存图片阅读进度失败[${trigger}]: ${error.message}`);
    });
  }

  /**
   * [修复] 图片 EPUB 被控端遥控指令监听（与文本阅读器一致）：
   * 翻页/章节切换/自动翻页开关，执行后回 ack。
   */
  private onRemoteDataChanged = (state: SyncReadingState) => {
    if (!state.instructionType || state.instructionType === 'none' || state.instructionType === 'ack') {
      return;
    }
    if (state.timestamp <= this.lastRemoteInstructionTimestamp) {
      return;
    }
    this.lastRemoteInstructionTimestamp = state.timestamp;
    logger.info(TAG, `[RemoteControl] 收到图片电子书遥控指令: ${state.instructionType}`);
    switch (state.instructionType) {
      case 'cmd:next_page':
        this.jumpToPage(this.currentPageIndex + 1, 'remote_next_page');
        break;
      case 'cmd:prev_page':
        this.jumpToPage(this.currentPageIndex - 1, 'remote_prev_page');
        break;
      case 'cmd:next_chapter':
        this.jumpToImageChapterRelative(1, 'remote_next_chapter');
        break;
      case 'cmd:prev_chapter':
        this.jumpToImageChapterRelative(-1, 'remote_prev_chapter');
        break;
      case 'cmd:toggle_auto_read':
        this.setAutoPageTurnEnabled(!this.autoPageTurnEnabled);
        break;
      default:
        logger.warn(TAG, `[RemoteControl] 未知图片电子书指令: ${state.instructionType}`);
        break;
    }
    distributedDataSyncManager.sendInstruction('ack', '');
  };

  private onRemoteStatusChanged = (status: 'online' | 'offline' | 'restored' | 'error', message?: string) => {
    if (status === 'offline') {
      logger.info(TAG, '[RemoteControl] 遥控器已断开');
      if (this.remoteCallbacksRegistered) {
        this.getUIContext().getPromptAction().showToast({ message: '遥控器已断开' });
      }
    }
  };

  private registerRemoteControlListener(): void {
    if (this.remoteCallbacksRegistered) {
      return;
    }
    logger.info(TAG, '[RemoteControl] 图片电子书被控端已注册遥控器指令监听');
    this.remoteCallbacksRegistered = true;
    this.getUIContext().getPromptAction().showToast({ message: '遥控已连接' });
    distributedDataSyncManager.addOnDataChangedCallback(this.onRemoteDataChanged);
    distributedDataSyncManager.addOnStatusChangedCallback(this.onRemoteStatusChanged);
    distributedDataSyncManager.diagnoseSession('图片电子书被控端注册');
  }

  private unregisterRemoteControlListener(): void {
    if (!this.remoteCallbacksRegistered) {
      return;
    }
    this.remoteCallbacksRegistered = false;
    distributedDataSyncManager.removeOnDataChangedCallback(this.onRemoteDataChanged);
    distributedDataSyncManager.removeOnStatusChangedCallback(this.onRemoteStatusChanged);
  }

  private jumpToImageChapterRelative(delta: number, trigger: string): void {
    const entry = this.getCurrentPageEntry();
    if (!entry) {
      return;
    }
    const targetChapter = Math.max(0, entry.ebookChapterIndex + delta);
    if (targetChapter === entry.ebookChapterIndex) {
      return;
    }
    for (let index = 0; index < this.imageEntries.length; index++) {
      const candidate = this.imageEntries[index];
      if (candidate.ebookChapterIndex === targetChapter) {
        this.jumpToPage(index, trigger);
        return;
      }
    }
    logger.warn(TAG, `[RemoteControl] 未找到目标章节起始页: chapter=${targetChapter}`);
  }

  private clampAutoPageTurnInterval(value: number): number {
    if (!Number.isFinite(value)) {
      return 0;
    }
    return Math.max(0, Math.min(120, Math.round(value)));
  }

  private syncAutoPageTurnStateFromSettings(startImmediately: boolean): void {
    const interval = this.clampAutoPageTurnInterval(this.readingSettings.autoPageTurnInterval);
    this.autoPageTurnIntervalSeconds = interval > 0 ? interval : Math.max(1, this.autoPageTurnIntervalSeconds);
    this.autoPageTurnEnabled = interval > 0;
    this.configureAutoPageTurnController();
    if (!this.autoPageTurnEnabled) {
      this.stopAutoPageTurn();
      return;
    }
    if (startImmediately && !this.areMenusVisible() && this.isReaderInitialized) {
      this.startAutoPageTurn();
    }
  }

  private configureAutoPageTurnController(): void {
    const config: AutoPageTurnConfig = {
      interval: this.autoPageTurnEnabled ? this.autoPageTurnIntervalSeconds : 0,
      skipIntro: this.readingSettings.skipIntroPages > 0,
      skipIntroPages: this.readingSettings.skipIntroPages,
      autoSwitchChapter: true
    };
    if (!this.autoPageTurnController) {
      this.autoPageTurnController = new AutoPageTurnController(config);
      this.autoPageTurnController.setCallbacks(
        () => {
          this.goToNextPage(true);
        },
        () => this.currentPageIndex,
        () => this.getTotalPages()
      );
      this.autoPageTurnController.setChapterEndCallback((): boolean => this.handleAutoPageTurnChapterEnd());
    } else {
      this.autoPageTurnController.setConfig(config);
      this.autoPageTurnController.setChapterEndCallback((): boolean => this.handleAutoPageTurnChapterEnd());
    }
  }

  private handleAutoPageTurnChapterEnd(): boolean {
    const nextChapterPageIndex = this.findNextImageChapterPageIndex();
    if (nextChapterPageIndex < 0) {
      this.stopAutoPageTurn();
      this.getUIContext().getPromptAction().showToast({ message: '已到最后一章，自动翻页已停止' });
      return false;
    }

    this.saveReadingProgress('auto_page_turn_chapter_end');
    this.jumpToPage(nextChapterPageIndex, 'auto_page_turn_next_chapter');
    this.getUIContext().getPromptAction().showToast({ message: '已自动进入下一章' });
    return true;
  }

  private findNextImageChapterPageIndex(): number {
    const currentEntry = this.getCurrentPageEntry();
    if (!currentEntry) {
      return -1;
    }
    const currentChapterIndex = currentEntry.ebookChapterIndex;
    for (let index = this.currentPageIndex + 1; index < this.imageEntries.length; index++) {
      const entry = this.imageEntries[index];
      if (entry.ebookChapterIndex > currentChapterIndex) {
        return entry.runtimePageIndex;
      }
    }
    return -1;
  }

  private startAutoPageTurn(): void {
    if (!this.autoPageTurnEnabled) {
      return;
    }
    this.configureAutoPageTurnController();
    if (!this.autoPageTurnController) {
      return;
    }
    this.autoPageTurnController.start();
    this.autoPageTurnState = this.autoPageTurnController.getState();
  }

  private stopAutoPageTurn(): void {
    if (!this.autoPageTurnController) {
      this.autoPageTurnState = AutoPageTurnState.STOPPED;
      return;
    }
    this.autoPageTurnController.stop();
    this.autoPageTurnState = AutoPageTurnState.STOPPED;
  }

  private pauseAutoPageTurn(): void {
    if (!this.autoPageTurnController) {
      return;
    }
    if (this.autoPageTurnController.getState() === AutoPageTurnState.RUNNING) {
      this.autoPageTurnController.pause();
      this.autoPageTurnState = AutoPageTurnState.PAUSED;
    }
  }

  private resumeAutoPageTurnIfNeeded(): void {
    if (!this.autoPageTurnEnabled || !this.autoPageTurnController) {
      return;
    }
    const currentState = this.autoPageTurnController.getState();
    if (currentState === AutoPageTurnState.PAUSED) {
      this.autoPageTurnController.resume();
      this.autoPageTurnState = AutoPageTurnState.RUNNING;
    } else if (currentState === AutoPageTurnState.STOPPED && this.isReaderInitialized) {
      this.autoPageTurnController.start();
      this.autoPageTurnState = AutoPageTurnState.RUNNING;
    }
  }

  private async persistImageReaderSettings(trigger: string = 'unknown'): Promise<void> {
    if (!this.ebook) {
      return;
    }
    try {
      await this.ebookDataManager.saveImageReaderSettings(this.ebook.id, this.cloneReadingSettings(this.readingSettings));
    } catch (error) {
      logger.error(TAG, `保存图片阅读设置失败: 触发源=${trigger}, 错误=${String(error)}`);
    }
  }

  private isReaderProgressRtl(): boolean {
    if (this.readingSettings.readingDirection !== ReadingDirection.RIGHT_TO_LEFT) {
      return false;
    }
    const mode = this.readingSettings.readingMode;
    return mode === ReadingMode.SINGLE_PAGE ||
      mode === ReadingMode.SINGLE_PAGE_RTL ||
      mode === ReadingMode.DOUBLE_PAGE ||
      mode === ReadingMode.CONTINUOUS_SCROLL;
  }

  private getToolbarTotalPageCount(): number {
    return this.getTotalPages();
  }

  private getAutoPageTurnIconResource() {
    return this.autoPageTurnEnabled ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill');
  }

  private setAutoPageTurnIntervalSeconds(value: number): void {
    const clamped = Math.max(1, Math.min(30, value));
    this.autoPageTurnIntervalSeconds = clamped;
    this.readingSettings.autoPageTurnInterval = this.autoPageTurnEnabled ? clamped : 0;
    void this.persistImageReaderSettings('update_auto_page_turn_interval');
    this.syncAutoPageTurnStateFromSettings(this.autoPageTurnEnabled);
    logger.info(TAG, `自动翻页间隔已更新: ${clamped}秒`);
  }

  private setAutoPageTurnEnabled(enabled: boolean): void {
    this.autoPageTurnEnabled = enabled;
    this.readingSettings.autoPageTurnInterval = enabled ? this.autoPageTurnIntervalSeconds : 0;
    void this.persistImageReaderSettings('toggle_auto_page_turn');
    if (enabled) {
      this.configureAutoPageTurnController();
      if (!this.areMenusVisible() && this.isReaderInitialized) {
        this.startAutoPageTurn();
      } else {
        this.autoPageTurnState = this.autoPageTurnController?.getState() ?? AutoPageTurnState.STOPPED;
      }
      logger.info(TAG, '自动翻页已开启');
      return;
    }
    this.stopAutoPageTurn();
    this.clearInteractionResumeTimer();
    logger.info(TAG, '自动翻页已关闭');
  }

  private isLandscapeScreen(): boolean {
    return this.isLandscapeMode;
  }

  private isCurlAnimationSupported(): boolean {
    const mode = this.readingSettings.readingMode;
    const direction = this.readingSettings.readingDirection;
    if (mode === ReadingMode.SINGLE_PAGE_RTL) {
      return true;
    }
    if (mode === ReadingMode.SINGLE_PAGE) {
      return direction === ReadingDirection.LEFT_TO_RIGHT || direction === ReadingDirection.RIGHT_TO_LEFT;
    }
    if (mode === ReadingMode.DOUBLE_PAGE && this.isLandscapeScreen()) {
      return true;
    }
    return false;
  }

  private openTableOfContents(): void {
    this.showChapterList = true;
    this.handleMenusVisibilityChange();
  }

  private showQuickSettingsWithAnimation(): void {
    this.showSettingsPanel = false;
    this.showMoreMenu = false;
    this.showChapterList = false;
    this.showAutoPageTurnSettings = false;
    this.showJumpToPageDialog = false;
    this.showPageTurnAnimationSettings = false;
    this.handleMenusVisibilityChange();

    this.quickSettingsOpacity = 0;
    this.quickSettingsScale = 0.95;
    this.quickSettingsTranslateY = 20;
    this.showQuickSettings = true;
    this.handleMenusVisibilityChange();

    if (this.uiContext) {
      setTimeout(() => {
        this.uiContext!.animateTo({
          duration: 200,
          curve: Curve.EaseOut
        }, () => {
          this.quickSettingsOpacity = 1;
          this.quickSettingsScale = 1;
          this.quickSettingsTranslateY = 0;
        });
      }, 0);
    } else {
      this.quickSettingsOpacity = 1;
      this.quickSettingsScale = 1;
      this.quickSettingsTranslateY = 0;
    }
    logger.info(TAG, '显示快速设置面板');
  }

  private hideQuickSettingsWithAnimation(): void {
    if (this.uiContext) {
      this.uiContext.animateTo({
        duration: 160,
        curve: Curve.EaseIn,
        onFinish: () => {
          this.showQuickSettings = false;
          this.handleMenusVisibilityChange();
        }
      }, () => {
        this.quickSettingsOpacity = 0;
        this.quickSettingsScale = 0.95;
        this.quickSettingsTranslateY = 20;
      });
    } else {
      this.quickSettingsOpacity = 0;
      this.quickSettingsScale = 0.95;
      this.quickSettingsTranslateY = 20;
      this.showQuickSettings = false;
      this.handleMenusVisibilityChange();
    }
    logger.info(TAG, '隐藏快速设置面板');
  }

  private showSettingsPanelWithAnimation(): void {
    this.showQuickSettings = false;
    this.showMoreMenu = false;
    this.showChapterList = false;
    this.showAutoPageTurnSettings = false;
    this.showJumpToPageDialog = false;
    this.showPageTurnAnimationSettings = false;
    this.handleMenusVisibilityChange();

    this.settingsPanelOpacity = 0;
    this.settingsPanelScale = 0.95;
    this.settingsPanelTranslateY = 20;
    this.showSettingsPanel = true;
    this.handleMenusVisibilityChange();

    if (this.uiContext) {
      setTimeout(() => {
        this.uiContext!.animateTo({
          duration: 250,
          curve: Curve.EaseOut
        }, () => {
          this.settingsPanelOpacity = 1;
          this.settingsPanelScale = 1;
          this.settingsPanelTranslateY = 0;
        });
      }, 0);
    } else {
      this.settingsPanelOpacity = 1;
      this.settingsPanelScale = 1;
      this.settingsPanelTranslateY = 0;
    }
    logger.info(TAG, '显示完整设置面板');
  }

  private hideSettingsPanelWithAnimation(): void {
    if (this.uiContext) {
      this.uiContext.animateTo({
        duration: 180,
        curve: Curve.EaseIn,
        onFinish: () => {
          this.showSettingsPanel = false;
          this.handleMenusVisibilityChange();
        }
      }, () => {
        this.settingsPanelOpacity = 0;
        this.settingsPanelScale = 0.95;
        this.settingsPanelTranslateY = 20;
      });
    } else {
      this.settingsPanelOpacity = 0;
      this.settingsPanelScale = 0.95;
      this.settingsPanelTranslateY = 20;
      this.showSettingsPanel = false;
      this.handleMenusVisibilityChange();
    }
    logger.info(TAG, '隐藏完整设置面板');
  }

  private showMoreMenuWithAnimation(): void {
    this.showQuickSettings = false;
    this.showSettingsPanel = false;
    this.showChapterList = false;
    this.showAutoPageTurnSettings = false;
    this.showJumpToPageDialog = false;
    this.showPageTurnAnimationSettings = false;
    this.handleMenusVisibilityChange();

    this.moreMenuOpacity = 0;
    this.moreMenuScale = 0.95;
    this.moreMenuTranslateY = -10;
    this.showMoreMenu = true;
    this.handleMenusVisibilityChange();

    if (this.uiContext) {
      setTimeout(() => {
        this.uiContext!.animateTo({
          duration: 200,
          curve: Curve.EaseOut
        }, () => {
          this.moreMenuOpacity = 1;
          this.moreMenuScale = 1;
          this.moreMenuTranslateY = 0;
        });
      }, 0);
    } else {
      this.moreMenuOpacity = 1;
      this.moreMenuScale = 1;
      this.moreMenuTranslateY = 0;
    }
    logger.info(TAG, '显示更多菜单');
  }

  private hideMoreMenuWithAnimation(): void {
    if (this.uiContext) {
      this.uiContext.animateTo({
        duration: 160,
        curve: Curve.EaseIn,
        onFinish: () => {
          this.showMoreMenu = false;
          this.handleMenusVisibilityChange();
        }
      }, () => {
        this.moreMenuOpacity = 0;
        this.moreMenuScale = 0.95;
        this.moreMenuTranslateY = -10;
      });
    } else {
      this.moreMenuOpacity = 0;
      this.moreMenuScale = 0.95;
      this.moreMenuTranslateY = -10;
      this.showMoreMenu = false;
      this.handleMenusVisibilityChange();
    }
    logger.info(TAG, '隐藏更多菜单');
  }

  private toggleAutoPageTurnSettings(): void {
    if (this.showAutoPageTurnSettings) {
      this.hideAutoPageTurnSettingsWithAnimation();
    } else {
      this.showAutoPageTurnSettingsWithAnimation();
    }
  }

  private refreshAppFontFamilyForDialog(source: string): void {
    let resolvedFontFamily = (this.appFontFamily ?? '').trim();
    try {
      const managerFontFamily = getFontManager().getFontFamily(FontScene.APP_UI).trim();
      if (managerFontFamily.length > 0 && managerFontFamily !== 'HarmonyOS Sans') {
        resolvedFontFamily = managerFontFamily;
      } else if (resolvedFontFamily.length <= 0 && managerFontFamily.length > 0) {
        resolvedFontFamily = managerFontFamily;
      }
    } catch (error) {
      logger.warn(TAG, `刷新阅读器弹窗全局字体失败: source=${source}, error=${String(error)}`);
    }
    if (resolvedFontFamily.length <= 0) {
      resolvedFontFamily = 'HarmonyOS Sans';
    }
    if (resolvedFontFamily !== this.appFontFamily) {
      this.appFontFamily = resolvedFontFamily;
      logger.info(TAG, `阅读器弹窗全局字体已刷新: source=${source}, font=${resolvedFontFamily}`);
    }
  }

  private showAutoPageTurnSettingsWithAnimation(): void {
    this.refreshAppFontFamilyForDialog('auto_page_turn_settings_open');
    this.showQuickSettings = false;
    this.showSettingsPanel = false;
    this.showMoreMenu = false;
    this.showChapterList = false;
    this.showJumpToPageDialog = false;
    this.showPageTurnAnimationSettings = false;
    this.handleMenusVisibilityChange();

    this.autoPageTurnSettingsOpacity = 0;
    this.autoPageTurnSettingsScale = 0.95;
    this.autoPageTurnSettingsTranslateY = 20;
    this.autoPageTurnSettingsTranslateX = 320;
    this.showAutoPageTurnSettings = true;
    this.handleMenusVisibilityChange();

    if (this.uiContext) {
      setTimeout(() => {
        this.uiContext!.animateTo({
          duration: 250,
          curve: Curve.EaseOut
        }, () => {
          this.autoPageTurnSettingsOpacity = 1;
          this.autoPageTurnSettingsScale = 1;
          this.autoPageTurnSettingsTranslateY = 0;
          this.autoPageTurnSettingsTranslateX = 0;
        });
      }, 0);
    } else {
      this.autoPageTurnSettingsOpacity = 1;
      this.autoPageTurnSettingsScale = 1;
      this.autoPageTurnSettingsTranslateY = 0;
      this.autoPageTurnSettingsTranslateX = 0;
    }
    logger.info(TAG, '显示自动翻页设置面板');
  }

  private hideAutoPageTurnSettingsWithAnimation(): void {
    if (this.uiContext) {
      this.uiContext.animateTo({
        duration: 200,
        curve: Curve.EaseIn,
        onFinish: () => {
          this.showAutoPageTurnSettings = false;
          this.handleMenusVisibilityChange();
        }
      }, () => {
        this.autoPageTurnSettingsOpacity = 0;
        this.autoPageTurnSettingsScale = 0.95;
        this.autoPageTurnSettingsTranslateY = 20;
        this.autoPageTurnSettingsTranslateX = 320;
      });
    } else {
      this.autoPageTurnSettingsOpacity = 0;
      this.autoPageTurnSettingsScale = 0.95;
      this.autoPageTurnSettingsTranslateY = 20;
      this.autoPageTurnSettingsTranslateX = 320;
      this.showAutoPageTurnSettings = false;
      this.handleMenusVisibilityChange();
    }
    logger.info(TAG, '隐藏自动翻页设置面板');
  }

  private showJumpToPageDialogWithAnimation(): void {
    this.showQuickSettings = false;
    this.showSettingsPanel = false;
    this.showMoreMenu = false;
    this.showChapterList = false;
    this.showAutoPageTurnSettings = false;
    this.showPageTurnAnimationSettings = false;
    this.handleMenusVisibilityChange();

    this.showJumpToPageDialog = true;
    this.jumpToPageInput = `${this.currentPageIndex + 1}`;
    this.jumpToPageDialogOpacity = 0;
    this.jumpToPageDialogScale = 0.9;
    this.handleMenusVisibilityChange();

    if (this.uiContext) {
      setTimeout(() => {
        this.uiContext!.animateTo({
          duration: 200,
          curve: Curve.EaseOut
        }, () => {
          this.jumpToPageDialogOpacity = 1;
          this.jumpToPageDialogScale = 1;
        });
      }, 0);
    } else {
      this.jumpToPageDialogOpacity = 1;
      this.jumpToPageDialogScale = 1;
    }
    logger.info(TAG, '显示跳页对话框');
  }

  private hideJumpToPageDialogWithAnimation(): void {
    if (this.uiContext) {
      this.uiContext.animateTo({
        duration: 150,
        curve: Curve.EaseIn,
        onFinish: () => {
          this.showJumpToPageDialog = false;
          this.jumpToPageInput = '';
          this.handleMenusVisibilityChange();
        }
      }, () => {
        this.jumpToPageDialogOpacity = 0;
        this.jumpToPageDialogScale = 0.9;
      });
    } else {
      this.jumpToPageDialogOpacity = 0;
      this.jumpToPageDialogScale = 0.9;
      this.showJumpToPageDialog = false;
      this.jumpToPageInput = '';
      this.handleMenusVisibilityChange();
    }
    logger.info(TAG, '隐藏跳页对话框');
  }

  private showPageTurnAnimationSettingsWithAnimation(): void {
    this.refreshAppFontFamilyForDialog('page_turn_settings_open');
    this.showQuickSettings = false;
    this.showSettingsPanel = false;
    this.showMoreMenu = false;
    this.showChapterList = false;
    this.showAutoPageTurnSettings = false;
    this.showJumpToPageDialog = false;
    this.handleMenusVisibilityChange();

    this.pageTurnAnimationSettingsOpacity = 0;
    this.pageTurnAnimationSettingsScale = 0.95;
    this.pageTurnAnimationSettingsTranslateY = 20;
    this.pageTurnAnimationSettingsTranslateX = 320;
    this.showPageTurnAnimationSettings = true;
    this.handleMenusVisibilityChange();

    if (this.uiContext) {
      setTimeout(() => {
        this.uiContext!.animateTo({
          duration: 250,
          curve: Curve.EaseOut
        }, () => {
          this.pageTurnAnimationSettingsOpacity = 1;
          this.pageTurnAnimationSettingsScale = 1;
          this.pageTurnAnimationSettingsTranslateY = 0;
          this.pageTurnAnimationSettingsTranslateX = 0;
        });
      }, 0);
    } else {
      this.pageTurnAnimationSettingsOpacity = 1;
      this.pageTurnAnimationSettingsScale = 1;
      this.pageTurnAnimationSettingsTranslateY = 0;
      this.pageTurnAnimationSettingsTranslateX = 0;
    }
    logger.info(TAG, '显示翻页动画设置面板');
  }

  private hidePageTurnAnimationSettingsWithAnimation(): void {
    if (this.uiContext) {
      this.uiContext.animateTo({
        duration: 200,
        curve: Curve.EaseIn,
        onFinish: () => {
          this.showPageTurnAnimationSettings = false;
          this.handleMenusVisibilityChange();
        }
      }, () => {
        this.pageTurnAnimationSettingsOpacity = 0;
        this.pageTurnAnimationSettingsScale = 0.95;
        this.pageTurnAnimationSettingsTranslateY = 20;
        this.pageTurnAnimationSettingsTranslateX = 320;
      });
    } else {
      this.pageTurnAnimationSettingsOpacity = 0;
      this.pageTurnAnimationSettingsScale = 0.95;
      this.pageTurnAnimationSettingsTranslateY = 20;
      this.pageTurnAnimationSettingsTranslateX = 320;
      this.showPageTurnAnimationSettings = false;
      this.handleMenusVisibilityChange();
    }
    logger.info(TAG, '隐藏翻页动画设置面板');
  }

  @Builder
  private buildAnimButton(label: string, type: PageTurnAnimationType) {
    Column() {
      Text(label)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(this.readingSettings.pageTurnAnimation === type ?
          $r('app.color.accent') : $r('app.color.text_secondary'))
    }
    .width('31%')
    .padding(10)
    .backgroundColor(this.readingSettings.pageTurnAnimation === type ?
      $r('app.color.accent_background') : Color.Transparent)
    .borderRadius(8)
    .onClick(() => {
      this.readingSettings.pageTurnAnimation = type;
      this.handleSettingsChange(this.readingSettings);
      logger.info(TAG, `翻页动画已切换为: ${this.getPageTurnAnimationLabel(type)}`);
    })
  }

  private areMenusVisible(): boolean {
    return this.showQuickSettings ||
      this.showSettingsPanel ||
      this.showMoreMenu ||
      this.showChapterList ||
      this.showAutoPageTurnSettings ||
      this.showJumpToPageDialog ||
      this.showPageTurnAnimationSettings ||
      this.showInteractionOverlay;
  }

  private closeAllMenus(): void {
    this.showQuickSettings = false;
    this.showSettingsPanel = false;
    this.showMoreMenu = false;
    this.showChapterList = false;
    this.showAutoPageTurnSettings = false;
    this.showJumpToPageDialog = false;
    this.showPageTurnAnimationSettings = false;
    this.showInteractionOverlay = false;
    this.handleMenusVisibilityChange();
    this.scheduleToolbarAutoHide('close_all_menus');
  }

  private handleMenusVisibilityChange(): void {
    if (this.areMenusVisible()) {
      this.clearToolbarAutoHideTimer();
      this.clearInteractionResumeTimer();
      this.pauseAutoPageTurn();
      return;
    }
    this.resumeAutoPageTurnIfNeeded();
    this.scheduleFullscreenRestore('menus_closed', 80);
    this.scheduleToolbarAutoHide('menus_closed');
  }

  private showToolbars(): void {
    this.showTopToolbar = true;
    this.showBottomToolbar = true;
    this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
      this.toolbarOpacity = 1;
    });
    this.handleMenusVisibilityChange();
    this.scheduleToolbarAutoHide('show_toolbars');
  }

  private hideToolbars(): void {
    this.clearToolbarAutoHideTimer();
    this.getUIContext().animateTo({ duration: 160, curve: Curve.EaseIn }, () => {
      this.toolbarOpacity = 0;
    });
    setTimeout(() => {
      this.showTopToolbar = false;
      this.showBottomToolbar = false;
      this.scheduleFullscreenRestore('hide_toolbars', 80);
    }, 160);
  }

  private scheduleToolbarAutoHide(reason: string): void {
    if (!this.showTopToolbar && !this.showBottomToolbar) {
      return;
    }
    if (this.areMenusVisible()) {
      return;
    }
    this.clearToolbarAutoHideTimer();
    this.toolbarAutoHideTimer = setTimeout(() => {
      this.toolbarAutoHideTimer = -1;
      this.hideToolbars();
      logger.debug(TAG, `工具栏已自动隐藏: ${reason}`);
    }, EBookImageReaderPage.TOOLBAR_AUTO_HIDE_DELAY_MS);
  }

  private toggleToolbars(): void {
    if (this.areMenusVisible()) {
      this.closeAllMenus();
      return;
    }
    if (this.showTopToolbar || this.showBottomToolbar) {
      this.hideToolbars();
    } else {
      this.showToolbars();
    }
  }

  private delayAutoPageTurnForInteraction(delayMs: number = 2500): void {
    this.pauseAutoPageTurn();
    this.clearInteractionResumeTimer();
    if (!this.autoPageTurnEnabled) {
      return;
    }
    this.interactionResumeTimer = setTimeout(() => {
      this.interactionResumeTimer = -1;
      if (!this.areMenusVisible()) {
        this.resumeAutoPageTurnIfNeeded();
      }
    }, delayMs);
  }

  private getEffectiveComponentWidth(): number {
    return this.componentWidth > 0 ? this.componentWidth : (this.screenWidth > 0 ? this.screenWidth : 360);
  }

  private getEffectiveComponentHeight(): number {
    return this.componentHeight > 0 ? this.componentHeight : (this.screenHeight > 0 ? this.screenHeight : 640);
  }

  private handlePageTap(event: ClickEvent): void {
    this.processSingleTap(event);
    this.delayAutoPageTurnForInteraction();
  }

  private processSingleTap(event: ClickEvent): void {
    const clickX = event.displayX;
    const clickY = event.displayY;
    this.handleReadingModeTap(
      clickX,
      clickY,
      this.getDeviceOrientation(),
      this.getEffectiveComponentWidth(),
      this.getEffectiveComponentHeight()
    );
  }

  private handleReadingModeTap(
    clickX: number,
    clickY: number,
    deviceOrientation: 'portrait' | 'landscape' | 'square',
    displayWidth: number,
    displayHeight: number
  ): void {
    if (this.isScrollableReaderMode()) {
      this.toggleToolbars();
      return;
    }

    if (this.readingSettings.readingMode === ReadingMode.DOUBLE_PAGE) {
      this.handleDoublePageTap(clickX, clickY, displayWidth, displayHeight);
      return;
    }

    this.handleSinglePageTap(clickX, clickY, deviceOrientation, displayWidth, displayHeight);
  }

  private handleDoublePageTap(
    clickX: number,
    clickY: number,
    displayWidth: number,
    displayHeight: number
  ): void {
    const centerAreaRatio = 0.4;
    const sideAreaRatio = (1 - centerAreaRatio) / 2;
    const isTopToBottom = this.readingSettings.readingDirection === ReadingDirection.TOP_TO_BOTTOM;

    if (isTopToBottom) {
      const topZoneEnd = displayHeight * sideAreaRatio;
      const bottomZoneStart = displayHeight * (1 - sideAreaRatio);
      if (clickY < topZoneEnd) {
        this.goToPreviousPage();
      } else if (clickY > bottomZoneStart) {
        this.goToNextPage();
      } else {
        this.toggleToolbars();
      }
      return;
    }

    const leftZoneEnd = displayWidth * sideAreaRatio;
    const rightZoneStart = displayWidth * (1 - sideAreaRatio);
    const isRtl = this.readingSettings.readingDirection === ReadingDirection.RIGHT_TO_LEFT;
    if (clickX < leftZoneEnd) {
      if (isRtl) {
        this.goToNextPage();
      } else {
        this.goToPreviousPage();
      }
    } else if (clickX > rightZoneStart) {
      if (isRtl) {
        this.goToPreviousPage();
      } else {
        this.goToNextPage();
      }
    } else {
      this.toggleToolbars();
    }
  }

  private handleSinglePageTap(
    clickX: number,
    clickY: number,
    deviceOrientation: 'portrait' | 'landscape' | 'square',
    displayWidth: number,
    displayHeight: number
  ): void {
    const isTopToBottom = this.readingSettings.readingMode === ReadingMode.SINGLE_PAGE_TTB ||
      this.readingSettings.readingDirection === ReadingDirection.TOP_TO_BOTTOM;
    if (isTopToBottom) {
      const centerAreaRatio = 0.4;
      const sideAreaRatio = (1 - centerAreaRatio) / 2;
      const topZoneEnd = displayHeight * sideAreaRatio;
      const bottomZoneStart = displayHeight * (1 - sideAreaRatio);
      if (clickY < topZoneEnd) {
        this.goToPreviousPage();
      } else if (clickY > bottomZoneStart) {
        this.goToNextPage();
      } else {
        this.toggleToolbars();
      }
      return;
    }

    this.handleHorizontalTap(clickX, deviceOrientation, displayWidth, displayHeight);
  }

  private handleHorizontalTap(
    clickX: number,
    deviceOrientation: 'portrait' | 'landscape' | 'square',
    displayWidth: number,
    displayHeight: number
  ): void {
    const centerAreaRatio = 0.4;
    const sideAreaRatio = (1 - centerAreaRatio) / 2;
    let effectiveWidth = displayWidth;
    if (deviceOrientation === 'landscape' && this.componentWidth <= 0) {
      effectiveWidth = displayHeight;
    } else if (deviceOrientation === 'square') {
      effectiveWidth = Math.min(displayWidth, displayHeight);
    }

    const leftZoneEnd = effectiveWidth * sideAreaRatio;
    const rightZoneStart = effectiveWidth * (1 - sideAreaRatio);
    const isRtl = this.readingSettings.readingMode === ReadingMode.SINGLE_PAGE_RTL ||
      this.readingSettings.readingDirection === ReadingDirection.RIGHT_TO_LEFT;

    if (clickX < leftZoneEnd) {
      if (isRtl) {
        this.goToNextPage();
      } else {
        this.goToPreviousPage();
      }
    } else if (clickX > rightZoneStart) {
      if (isRtl) {
        this.goToPreviousPage();
      } else {
        this.goToNextPage();
      }
    } else {
      this.toggleToolbars();
    }
  }

  private handleDoubleTap(_event: ClickEvent): void {
    this.viewerZoomScale = this.viewerZoomScale > 1 ? 1 : 2;
    this.delayAutoPageTurnForInteraction();
  }

  private applyCurrentPageIndex(pageIndex: number, trigger: string, shouldPersist: boolean = true): void {
    const totalPages = this.getTotalPages();
    if (totalPages <= 0) {
      return;
    }
    const safePageIndex = Math.max(0, Math.min(Math.floor(pageIndex), totalPages - 1));
    this.currentPageIndex = safePageIndex;
    this.updatePreloadDebugInfo(safePageIndex);
    this.refreshCurrentEBookBookmarkState(`page_${trigger}`);
    if (!this.isReaderInitialized) {
      return;
    }
    this.scheduleToolbarAutoHide(trigger);
    if (shouldPersist) {
      this.saveReadingProgress(trigger);
    }
  }

  private jumpToPage(pageIndex: number, trigger: string): void {
    const totalPages = this.getTotalPages();
    if (totalPages <= 0) {
      return;
    }
    const safePageIndex = Math.max(0, Math.min(Math.floor(pageIndex), totalPages - 1));
    if (this.mangaViewerComponent) {
      const jumped = this.mangaViewerComponent.jumpToPageImmediate(safePageIndex);
      if (!jumped) {
        this.mangaViewerComponent.setPageIndex(safePageIndex);
      }
    }
    this.applyCurrentPageIndex(safePageIndex, trigger);
  }

  private isScrollableReaderMode(): boolean {
    return this.readingSettings.readingMode === ReadingMode.CONTINUOUS_SCROLL ||
      this.readingSettings.readingMode === ReadingMode.CONTINUOUS_VERTICAL ||
      this.readingSettings.readingMode === ReadingMode.WEBTOON ||
      this.readingSettings.readingMode === ReadingMode.WEBTOON_WITH_GAP;
  }

  private goToPreviousPage(isAutoScroll: boolean = false): void {
    if (this.currentPageIndex <= 0) {
      if (isAutoScroll) {
        this.stopAutoPageTurn();
      }
      return;
    }
    if (this.mangaViewerComponent && this.isScrollableReaderMode()) {
      const success = this.mangaViewerComponent.smoothScrollToPreviousPage(1, 'page');
      if (success) {
        return;
      }
    }
    this.jumpToPage(this.currentPageIndex - 1, 'prev_page');
  }

  private goToNextPage(isAutoScroll: boolean = false): void {
    if (this.currentPageIndex >= this.getTotalPages() - 1) {
      if (isAutoScroll) {
        this.stopAutoPageTurn();
      }
      return;
    }
    if (this.mangaViewerComponent && this.isScrollableReaderMode()) {
      const success = this.mangaViewerComponent.smoothScrollToNextPage(1, 'page');
      if (success) {
        return;
      }
    }
    this.jumpToPage(this.currentPageIndex + 1, 'next_page');
  }

  private handleViewerPageChange(pageIndex: number): void {
    if (!this.isReaderInitialized) {
      return;
    }
    this.recordReadFlowEvent(
      MangaReadFlowEventType.PAGE_CHANGED,
      'viewer_page_change',
      pageIndex,
      `previous=${this.currentPageIndex}`
    );
    this.applyCurrentPageIndex(pageIndex, 'viewer_page_change');
  }

  private handleSettingsChange(settings: MangaReadingSettings): void {
    const readingModeChanged = this.readingSettings.readingMode !== settings.readingMode ||
      this.readingSettings.readingDirection !== settings.readingDirection;
    this.readingSettings = this.cloneReadingSettings(settings);
    this.syncDeviceOrientationLock('settings_change');
    void this.persistImageReaderSettings('handle_settings_change');
    this.syncAutoPageTurnStateFromSettings(true);
    if (readingModeChanged) {
      this.showInteractionOverlay = true;
    }
    this.handleMenusVisibilityChange();
  }

  private handleChapterListSelect(chapterId: string): void {
    if (!this.ebook) {
      return;
    }
    const targetPageIndex = resolveRuntimePageIndexByChapterId(this.ebook, chapterId);
    if (targetPageIndex >= 0) {
      this.jumpToPage(targetPageIndex, 'chapter_select');
    }
    this.showChapterList = false;
    this.handleMenusVisibilityChange();
  }

  private handleVolumeKeyPageTurn(keyCode: number): boolean {
    if (!this.readingSettings.volumeKeyNavigation) {
      return false;
    }
    if (keyCode === KeyCode.KEYCODE_VOLUME_UP) {
      this.goToPreviousPage();
      return true;
    }
    if (keyCode === KeyCode.KEYCODE_VOLUME_DOWN) {
      this.goToNextPage();
      return true;
    }
    return false;
  }

  private async saveCurrentPageToGallery(): Promise<void> {
    const entry = this.getCurrentPageEntry();
    if (!entry || !entry.imagePath.startsWith('/')) {
      this.getUIContext().getPromptAction().showToast({ message: '当前页面无法保存' });
      return;
    }
    try {
      const context = (this.getUIContext().getHostContext() as common.UIAbilityContext) as common.UIAbilityContext;
      const extensionIndex = entry.imagePath.lastIndexOf('.');
      const extension = extensionIndex > 0 ? entry.imagePath.substring(extensionIndex + 1) : 'jpg';
      const sandboxUri = fileUri.getUriFromPath(entry.imagePath);
      const helper = photoAccessHelper.getPhotoAccessHelper(context);
      const targetUris = await helper.showAssetsCreationDialog(
        [sandboxUri],
        [{
          title: `${this.ebook?.metadata.title || '电子书'}_${this.currentPageIndex + 1}`,
          fileNameExtension: extension,
          photoType: photoAccessHelper.PhotoType.IMAGE,
          subtype: photoAccessHelper.PhotoSubtype.DEFAULT
        }]
      );
      if (targetUris.length <= 0) {
        return;
      }
      const destFile = await fs.open(targetUris[0], fs.OpenMode.WRITE_ONLY);
      const srcFile = await fs.open(sandboxUri, fs.OpenMode.READ_ONLY);
      await fs.copyFile(srcFile.fd, destFile.fd);
      SafeFileUtils.closeSync(destFile);
      SafeFileUtils.closeSync(srcFile);
      this.getUIContext().getPromptAction().showToast({ message: '当前页面已保存到图库' });
    } catch (error) {
      logger.error(TAG, `保存页面失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: '保存页面失败' });
    }
  }

  private async shareCurrentPageImage(): Promise<void> {
    const entry = this.getCurrentPageEntry();
    if (!entry || !entry.imagePath.startsWith('/')) {
      this.getUIContext().getPromptAction().showToast({ message: '当前页面无法分享' });
      return;
    }
    try {
      const context = (this.getUIContext().getHostContext() as common.UIAbilityContext) as common.UIAbilityContext;
      const shareUri = fileUri.getUriFromPath(entry.imagePath);
      const title = `${this.ebook?.metadata.title || '电子书'} - 第${this.currentPageIndex + 1}页`;
      const shareData: systemShare.SharedData = new systemShare.SharedData({
        utd: utd.UniformDataType.JPEG,
        uri: shareUri,
        title,
        description: title
      });
      const controller: systemShare.ShareController = new systemShare.ShareController(shareData);
      await controller.show(context, {
        previewMode: systemShare.SharePreviewMode.DETAIL,
        selectionMode: systemShare.SelectionMode.SINGLE
      });
    } catch (error) {
      logger.error(TAG, `分享页面失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: '分享页面失败' });
    }
  }

  private async goBack(): Promise<void> {
    if (this.areMenusVisible()) {
      this.closeAllMenus();
      return;
    }
    this.isCloseTransitionNavigating = true;
    this.clearToolbarAutoHideTimer();
    this.clearFullscreenRestoreTimer();
    this.clearInteractionResumeTimer();
    try {
      await this.persistImageReaderSettings('go_back');
    } catch (_error) {}

    try {
      await this.saveReadingProgressInternal('go_back');
    } catch (_error) {}

    try {
      const ebookId = this.ebook?.id || '';
      const coverComponentId = this.sourceCoverComponentId || (ebookId ? `cover_ebook_lib_${ebookId}` : '');
      if (this.isHostedByIsolatedReaderAbility()) {
        logger.info(TAG, `独立图片电子书阅读器退出不挂载关闭动画层，封面组件ID: ${coverComponentId}`);
        cancelTransition();
        await this.terminateIsolatedReaderAbility('go_back_isolated_reader');
        return;
      }
      await startBookCloseTransitionWithComponentId('ebook_image_reader_root', coverComponentId);
      this.closeReaderRoute();
    } catch (error) {
      logger.error(TAG, `关闭图片阅读器失败: ${String(error)}`);
      this.isCloseTransitionNavigating = false;
      cancelTransition();
      if (this.isHostedByIsolatedReaderAbility()) {
        await this.terminateIsolatedReaderAbility('go_back_error');
      } else {
        this.closeReaderRoute();
      }
    }
  }

  private isHostedByIsolatedReaderAbility(): boolean {
    return this.readerHostMode === READER_ABILITY_HOST_MULTITON;
  }

  private async terminateIsolatedReaderAbility(reason: string): Promise<void> {
    try {
      const hostContext = this.getUIContext()?.getHostContext() as common.UIAbilityContext;
      if (!hostContext) {
        logger.warn(TAG, `独立图片电子书阅读器退出失败，回退页面栈: reason=${reason}`);
        this.pathStack.pop();
        return;
      }
      logger.info(TAG, `独立图片电子书阅读器实例退出: reason=${reason}, instanceId=${this.readerInstanceId}`);
      await hostContext.terminateSelf();
    } catch (error) {
      logger.error(TAG, `独立图片电子书阅读器实例退出异常: ${String(error)}`);
      this.pathStack.pop();
    }
  }

  private closeReaderRoute(): void {
    if (this.isHostedByIsolatedReaderAbility()) {
      void this.terminateIsolatedReaderAbility('close_reader_route');
      return;
    }
    if (this.routerBackOnClose) {
      const router = this.getUIContext()?.getRouter();
      if (router) {
        router.back();
        return;
      }
      logger.warn(TAG, 'Router 返回不可用，回退到 NavPathStack.pop');
    }
    this.pathStack.pop();
  }

  private getDeviceOrientation(): 'portrait' | 'landscape' | 'square' {
    if (Math.abs(this.screenWidth - this.screenHeight) < 1) {
      return 'square';
    }
    return this.screenWidth > this.screenHeight ? 'landscape' : 'portrait';
  }

  private getPageTurnAnimationLabel(type: PageTurnAnimationType): string {
    switch (type) {
      case PageTurnAnimationType.NONE:
        return '无';
      case PageTurnAnimationType.SLIDE:
        return '滑动';
      case PageTurnAnimationType.FADE:
        return '淡入淡出';
      case PageTurnAnimationType.CURL:
        return '卷页';
      case PageTurnAnimationType.CUBE:
        return '立方体';
      case PageTurnAnimationType.COVER:
        return '覆盖';
      case PageTurnAnimationType.DEPTH:
        return '景深';
      default:
        return String(type);
    }
  }

  @Builder
  private buildLoadingView() {
    Column({ space: 12 }) {
      LoadingProgress().width(40).height(40)
      Text('正在加载图片电子书...')
        .fontSize(16)
        .fontColor(Color.White)
        .fontFamily(this.appFontFamily)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private buildErrorView() {
    Column({ space: 12 }) {
      Text('图片阅读器加载失败')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .fontFamily(this.appFontFamily)
      Text(this.errorMessage || '未知错误')
        .fontSize(14)
        .fontColor('#D0D0D0')
        .textAlign(TextAlign.Center)
        .fontFamily(this.appFontFamily)
      Button('返回').onClick(() => { void this.goBack(); })
    }
    .width('100%')
    .height('100%')
    .padding(24)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  private getToolbarIconColor(isActive: boolean = false) {
    if (this.themeManager.isDarkThemeSync()) {
      return Color.White;
    }
    return isActive ? $r('app.color.accent_primary') : $r('app.color.text_primary');
  }

  @Builder
  private buildTopToolbar() {
    Row() {
      Button() {
        SymbolGlyph($r('sys.symbol.arrow_left'))
          .fontColor([this.getToolbarIconColor()])
      }
        .width(48).height(48).backgroundColor(Color.Transparent)
        .onClick(() => { void this.goBack(); })

      Column() {
        Text(this.ebook?.metadata.title || '图片 EPUB 阅读器')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontFamily(this.appFontFamily)

        if (this.getCurrentPageEntry()) {
          Text(this.getCurrentPageEntry()?.title || '当前页面')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .fontFamily(this.appFontFamily)
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })

      Button() {
        SymbolGlyph(this.isCurrentPageBookmarked ? $r('sys.symbol.bookmark_fill') : $r('sys.symbol.bookmark'))
          .fontColor([this.getToolbarIconColor(this.isCurrentPageBookmarked)])
      }
        .width(48).height(48).backgroundColor(Color.Transparent)
        .onClick(() => { this.toggleCurrentEBookBookmark(); })
      Button() {
        SymbolGlyph($r('sys.symbol.highlighter_line'))
          .fontColor([this.getToolbarIconColor()])
      }
        .width(48).height(48).backgroundColor(Color.Transparent)
        .onClick(() => { this.openCurrentEBookAnnotationCenter(); })
      Button() {
        SymbolGlyph($r('sys.symbol.more'))
          .fontColor([this.getToolbarIconColor()])
      }
        .width(48).height(48).backgroundColor(Color.Transparent)
        .onClick(() => {
          this.showMoreMenuWithAnimation();
        })
    }
    .width('100%')
    .height(ReaderSafeAreaUtils.getTopToolbarHeight(this.statusBarHeight))
    .padding({ left: 8, right: 8, top: ReaderSafeAreaUtils.getStatusBarInset(this.statusBarHeight) })
    .backgroundColor(this.themeManager.getGlassBackgroundResource())
    .backgroundBlurStyle(this.themeManager.getGlassBlurStyle())
    .shadow({ radius: this.themeManager.getGlassRadius(), color: this.themeManager.getGlassShadowColor(), offsetX: 0, offsetY: 4 })
    .opacity(this.toolbarOpacity)
    .id('' as string)
  }

  @Builder
  private buildBottomToolbar() {
    Column() {
      Row() {
        if (this.isReaderProgressRtl()) {
          Text(`${this.getToolbarTotalPageCount()}`)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .width(40)
            .fontFamily(this.appFontFamily)
            .textAlign(TextAlign.Center)
        } else {
          Text(`${this.currentPageIndex + 1}`)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .width(40)
            .fontFamily(this.appFontFamily)
            .textAlign(TextAlign.Center)
        }

        Slider({ value: this.currentPageIndex, min: 0, max: Math.max(0, this.getTotalPages() - 1), step: 1 })
          .layoutWeight(1)
          .trackColor($r('app.color.divider_primary'))
          .selectedColor($r('app.color.accent_primary'))
          .scale({ x: this.isReaderProgressRtl() ? -1 : 1, y: 1 })
          .onChange((value: number) => {
            const targetPage = Math.round(value);
            if (this.isScrollableReaderMode() && this.mangaViewerComponent) {
              this.currentPageIndex = targetPage;
              this.updatePreloadDebugInfo(targetPage);
              this.refreshCurrentEBookBookmarkState('toolbar_slider_change');
              this.mangaViewerComponent.smoothScrollToPage(targetPage, 1.5);
              this.scheduleToolbarAutoHide('slider_change');
              this.saveReadingProgress('slider_change');
              return;
            }
            this.jumpToPage(targetPage, 'bottom_slider');
          })

        if (this.isReaderProgressRtl()) {
          Text(`${this.currentPageIndex + 1}`)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .width(40)
            .fontFamily(this.appFontFamily)
            .textAlign(TextAlign.Center)
        } else {
          Text(`${this.getToolbarTotalPageCount()}`)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .width(40)
            .fontFamily(this.appFontFamily)
            .textAlign(TextAlign.Center)
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16 })

      Row() {
        Button() {
          SymbolGlyph($r('sys.symbol.list_bullet'))
            .fontColor([this.getToolbarIconColor()])
        }
          .width(48).height(48).backgroundColor(Color.Transparent)
          .onClick(() => {
            this.openTableOfContents();
          })
        Blank()
        Button() {
          SymbolGlyph($r('sys.symbol.gearshape'))
            .fontColor([this.getToolbarIconColor()])
        }
          .width(48).height(48).backgroundColor(Color.Transparent)
          .onClick(() => {
            this.showQuickSettingsWithAnimation();
          })
        Blank()
        Button() {
          SymbolGlyph($r('sys.symbol.page_turning'))
            .fontColor([this.getToolbarIconColor()])
        }
          .width(48).height(48).backgroundColor(Color.Transparent)
          .onClick(() => {
            this.showPageTurnAnimationSettingsWithAnimation();
          })
        Blank()
        Button() {
          SymbolGlyph($r('sys.symbol.eye'))
            .fontColor([this.getToolbarIconColor()])
        }
          .width(48).height(48).backgroundColor(Color.Transparent)
          .onClick(() => {
            this.showSettingsPanelWithAnimation();
          })
        Blank()
        Button() {
          SymbolGlyph(this.getAutoPageTurnIconResource())
            .fontColor([this.getToolbarIconColor()])
        }
          .width(48).height(48).backgroundColor(Color.Transparent)
          .onClick(() => {
            this.toggleAutoPageTurnSettings();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: this.navigationBarHeight })
    }
    .width('100%')
    .backgroundColor(this.themeManager.getGlassBackgroundResource())
    .backgroundBlurStyle(this.themeManager.getGlassBlurStyle())
    .shadow({ radius: this.themeManager.getGlassRadius(), color: this.themeManager.getGlassShadowColor(), offsetX: 0, offsetY: -2 })
    .opacity(this.toolbarOpacity)
    .id('' as string)
  }

  @Builder
  private buildMoreMenu() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.isLandscapeMode ? $r('app.color.background_overlay') : Color.Transparent)
        .opacity(this.isLandscapeMode ? 0.5 : 1)
        .onClick(() => {
          this.hideMoreMenuWithAnimation();
        })

      if (this.isLandscapeMode) {
        Row() {
          Column()
            .layoutWeight(1)
            .height('100%')
            .onClick(() => {
              this.hideMoreMenuWithAnimation();
            })

          Column() {
            Row() {
              Text('更多选项')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
                .layoutWeight(1)
                .fontFamily(this.appFontFamily)

              Button() {
                Image($r('app.media.ic_close'))
                  .width(18)
                  .height(18)
                  .fillColor($r('app.color.text_secondary'))
              }
              .width(32)
              .height(32)
              .backgroundColor(Color.Transparent)
              .onClick(() => {
                this.hideMoreMenuWithAnimation();
              })
            }
            .width('100%')
            .margin({ bottom: 16 })

            Row() {
              Text('跳转页面')
                .fontColor($r('app.color.text_primary'))
                .fontSize(14)
                .fontFamily(this.appFontFamily)
              Blank().layoutWeight(1)
              Text(`${this.currentPageIndex + 1}/${this.getTotalPages()}`)
                .fontColor($r('app.color.text_secondary'))
                .fontSize(12)
                .fontFamily(this.appFontFamily)
            }
            .height(44)
            .width('100%')
            .onClick(() => {
              logger.info(TAG, '更多菜单：打开跳页对话框');
              this.hideMoreMenuWithAnimation();
              setTimeout(() => {
                this.showJumpToPageDialogWithAnimation();
              }, 200);
            })

            Divider().color($r('app.color.divider'))

            Row() {
              Text('保存本张到图库')
                .fontColor($r('app.color.text_primary'))
                .fontSize(14)
                .fontFamily(this.appFontFamily)
              Blank().layoutWeight(1)
            }
            .height(44)
            .width('100%')
            .onClick(() => {
              logger.info(TAG, '更多菜单：保存当前页到图库');
              this.hideMoreMenuWithAnimation();
              void this.saveCurrentPageToGallery();
            })

            Divider().color($r('app.color.divider'))

            Row() {
              Text('分享本张图片')
                .fontColor($r('app.color.text_primary'))
                .fontSize(14)
                .fontFamily(this.appFontFamily)
              Blank().layoutWeight(1)
            }
            .height(44)
            .width('100%')
            .onClick(() => {
              logger.info(TAG, '更多菜单：分享当前页图片');
              this.hideMoreMenuWithAnimation();
              void this.shareCurrentPageImage();
            })
          }
          .width(320)
          .height('100%')
          .padding(16)
          .backgroundColor(this.themeManager.getGlassBackgroundResource())
          .backgroundBlurStyle(this.themeManager.getGlassBlurStyle())
          .borderRadius({ topLeft: 16, bottomLeft: 16 })
          .opacity(this.moreMenuOpacity)
          .hitTestBehavior(HitTestMode.Default)
        }
        .width('100%')
        .height('100%')
      } else {
        Column() {
          Row() {
            Text('跳转页面')
              .fontColor($r('app.color.text_primary'))
              .fontSize(16)
              .fontFamily(this.appFontFamily)
            Blank().layoutWeight(1)
            Text(`${this.currentPageIndex + 1}/${this.getTotalPages()}`)
              .fontColor($r('app.color.text_secondary'))
              .fontSize(14)
              .fontFamily(this.appFontFamily)
          }
          .height(44)
          .padding({ left: 16, right: 16 })
          .onClick(() => {
            logger.info(TAG, '更多菜单：打开跳页对话框');
            this.hideMoreMenuWithAnimation();
            setTimeout(() => {
              this.showJumpToPageDialogWithAnimation();
            }, 200);
          })

          Divider().color($r('app.color.divider'))

          Row() {
            Text('保存本张到图库')
              .fontColor($r('app.color.text_primary'))
              .fontSize(16)
              .fontFamily(this.appFontFamily)
            Blank().layoutWeight(1)
          }
          .height(44)
          .padding({ left: 16, right: 16 })
          .onClick(() => {
            logger.info(TAG, '更多菜单：保存当前页到图库');
            this.hideMoreMenuWithAnimation();
            void this.saveCurrentPageToGallery();
          })

          Divider().color($r('app.color.divider'))

          Row() {
            Text('分享本张图片')
              .fontColor($r('app.color.text_primary'))
              .fontSize(16)
              .fontFamily(this.appFontFamily)
            Blank().layoutWeight(1)
          }
          .height(44)
          .padding({ left: 16, right: 16 })
          .onClick(() => {
            logger.info(TAG, '更多菜单：分享当前页图片');
            this.hideMoreMenuWithAnimation();
            void this.shareCurrentPageImage();
          })
        }
        .backgroundColor(this.themeManager.getGlassBackgroundResource())
        .backgroundBlurStyle(this.themeManager.getGlassBlurStyle())
        .borderRadius(16)
        .shadow({ radius: this.themeManager.getGlassRadius(), color: this.themeManager.getGlassShadowColor(), offsetX: 0, offsetY: 4 })
        .opacity(this.moreMenuOpacity)
        .scale({ x: this.moreMenuScale, y: this.moreMenuScale })
        .translate({ y: this.moreMenuTranslateY })
        .align(Alignment.TopEnd)
        .margin({ top: ReaderSafeAreaUtils.getTopToolbarHeight(this.statusBarHeight) + 8, right: 12 })
        .constraintSize({ maxWidth: 260 })
        .zIndex(1100)
      }
    }
    .width('100%')
    .height('100%')
    .zIndex(1100)
  }

  @Builder
  private buildAutoPageTurnSettings() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.background_overlay'))
        .opacity(0.5)
        .onClick(() => {
          this.hideAutoPageTurnSettingsWithAnimation();
        })

      if (this.isLandscapeMode) {
        Row() {
          Column()
            .layoutWeight(1)
            .height('100%')
            .onClick(() => {
              this.hideAutoPageTurnSettingsWithAnimation();
            })

          Column() {
            Row() {
              Text('自动翻页设置')
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
                .layoutWeight(1)
                .fontFamily(this.appFontFamily)

              Button() {
                Image($r('app.media.ic_close'))
                  .width(20)
                  .height(20)
                  .fillColor($r('app.color.text_secondary'))
              }
              .width(36)
              .height(36)
              .backgroundColor(Color.Transparent)
              .onClick(() => {
                this.hideAutoPageTurnSettingsWithAnimation();
              })
            }
            .width('100%')
            .margin({ bottom: 16 })

            Text('翻页间隔')
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
              .margin({ bottom: 8 })
              .fontFamily(this.appFontFamily)

            Row() {
              Text(`${this.autoPageTurnIntervalSeconds}s`)
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.accent'))
                .width(50)
                .fontFamily(this.appFontFamily)

              Slider({
                value: this.autoPageTurnIntervalSeconds,
                min: 1,
                max: 30,
                step: 1
              })
                .layoutWeight(1)
                .trackColor($r('app.color.divider'))
                .selectedColor($r('app.color.accent'))
                .onChange((v: number) => {
                  this.setAutoPageTurnIntervalSeconds(Math.round(v));
                })
            }
            .width('100%')
            .margin({ bottom: 16 })

            Row() {
              Text('启用自动翻页')
                .fontSize(14)
                .fontColor($r('app.color.text_primary'))
                .layoutWeight(1)
                .fontFamily(this.appFontFamily)

              Toggle({ type: ToggleType.Switch, isOn: this.autoPageTurnEnabled })
                .selectedColor($r('app.color.accent'))
                .onChange((isOn: boolean) => {
                  this.setAutoPageTurnEnabled(isOn);
                })
            }
            .width('100%')
          }
          .width(320)
          .height('100%')
          .padding(16)
          .backgroundColor(this.themeManager.getGlassBackgroundResource())
          .backgroundBlurStyle(this.themeManager.getGlassBlurStyle())
          .borderRadius({ topLeft: 16, bottomLeft: 16 })
          .opacity(this.autoPageTurnSettingsOpacity)
          .translate({ x: this.autoPageTurnSettingsTranslateX })
          .hitTestBehavior(HitTestMode.Default)
        }
        .width('100%')
        .height('100%')
      } else {
        Column() {
          Row() {
            Text('自动翻页设置')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
              .layoutWeight(1)
              .fontFamily(this.appFontFamily)

            Button() {
              Image($r('app.media.ic_close'))
                .width(20)
                .height(20)
                .fillColor($r('app.color.text_secondary'))
            }
            .width(36)
            .height(36)
            .backgroundColor(Color.Transparent)
            .onClick(() => {
              this.hideAutoPageTurnSettingsWithAnimation();
            })
          }
          .width('100%')
          .margin({ bottom: 16 })

          Text('翻页间隔')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .margin({ bottom: 8 })
            .fontFamily(this.appFontFamily)

          Row() {
            Text(`${this.autoPageTurnIntervalSeconds}s`)
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.accent'))
              .width(50)
              .fontFamily(this.appFontFamily)

            Slider({
              value: this.autoPageTurnIntervalSeconds,
              min: 1,
              max: 30,
              step: 1
            })
              .layoutWeight(1)
              .trackColor($r('app.color.divider'))
              .selectedColor($r('app.color.accent'))
              .onChange((v: number) => {
                this.setAutoPageTurnIntervalSeconds(Math.round(v));
              })
          }
          .width('100%')
          .margin({ bottom: 16 })

          Row() {
            Text('启用自动翻页')
              .fontSize(14)
              .fontColor($r('app.color.text_primary'))
              .layoutWeight(1)
              .fontFamily(this.appFontFamily)

            Toggle({ type: ToggleType.Switch, isOn: this.autoPageTurnEnabled })
              .selectedColor($r('app.color.accent'))
              .onChange((isOn: boolean) => {
                this.setAutoPageTurnEnabled(isOn);
              })
          }
          .width('100%')
        }
        .width('90%')
        .constraintSize({ maxWidth: 400 })
        .padding(20)
        .backgroundColor(this.themeManager.getGlassBackgroundResource())
        .backgroundBlurStyle(this.themeManager.getGlassBlurStyle())
        .borderRadius(16)
        .opacity(this.autoPageTurnSettingsOpacity)
        .scale({ x: this.autoPageTurnSettingsScale, y: this.autoPageTurnSettingsScale })
        .translate({ y: this.autoPageTurnSettingsTranslateY })
      }
    }
    .width('100%')
    .height('100%')
    .zIndex(1200)
  }

  @Builder
  private buildJumpToPageDialog() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#80000000')
        .opacity(this.jumpToPageDialogOpacity)
        .onClick(() => {
          this.hideJumpToPageDialogWithAnimation();
        })

      if (this.isLandscapeMode) {
        Row() {
          Column()
            .layoutWeight(1)
            .height('100%')
            .onClick(() => {
              this.hideJumpToPageDialogWithAnimation();
            })

          Column() {
            Row() {
              Text('跳转到指定页')
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
                .layoutWeight(1)
                .fontFamily(this.appFontFamily)

              Button() {
                Image($r('app.media.ic_close'))
                  .width(20)
                  .height(20)
                  .fillColor($r('app.color.text_secondary'))
              }
              .width(36)
              .height(36)
              .backgroundColor(Color.Transparent)
              .onClick(() => {
                this.hideJumpToPageDialogWithAnimation();
              })
            }
            .width('100%')
            .margin({ bottom: 16 })

            Text(`当前: ${this.currentPageIndex + 1} / ${this.getTotalPages()}`)
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .fontFamily(this.appFontFamily)
              .margin({ bottom: 16 })

            TextInput({ placeholder: '输入页码', text: this.jumpToPageInput })
              .type(InputType.Number)
              .width('100%')
              .height(44)
              .fontSize(16)
              .onChange((value: string) => {
                this.jumpToPageInput = value;
              })
              .margin({ bottom: 16 })

            Row({ space: 12 }) {
              Button('取消')
                .layoutWeight(1)
                .height(40)
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontColor($r('app.color.text_secondary'))
                .backgroundColor($r('app.color.background_secondary'))
                .onClick(() => {
                  this.hideJumpToPageDialogWithAnimation();
                })

              Button('跳转')
                .layoutWeight(1)
                .height(40)
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontColor($r('app.color.text_on_accent'))
                .backgroundColor($r('app.color.accent'))
                .onClick(() => {
                  const pageNum = parseInt(this.jumpToPageInput);
                  if (isNaN(pageNum) || pageNum <= 0 || pageNum > this.getTotalPages()) {
                    this.getUIContext().getPromptAction().showToast({ message: '请输入有效页码' });
                    return;
                  }
                  this.jumpToPage(pageNum - 1, 'jump_dialog');
                  this.hideJumpToPageDialogWithAnimation();
                })
            }
            .width('100%')
          }
          .width(320)
          .height('100%')
          .padding(16)
          .backgroundColor(this.themeManager.getGlassBackgroundResource())
          .backgroundBlurStyle(this.themeManager.getGlassBlurStyle())
          .borderRadius({ topLeft: 16, bottomLeft: 16 })
          .opacity(this.jumpToPageDialogOpacity)
          .hitTestBehavior(HitTestMode.Default)
        }
        .width('100%')
        .height('100%')
      } else {
        Column({ space: 16 }) {
          Text('跳转到指定页面')
            .fontSize(18)
            .fontFamily(this.appFontFamily)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))

          Text(`当前: ${this.currentPageIndex + 1} / ${this.getTotalPages()}`)
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .fontFamily(this.appFontFamily)

          TextInput({ placeholder: '输入页码', text: this.jumpToPageInput })
            .type(InputType.Number)
            .width('100%')
            .height(44)
            .fontSize(16)
            .onChange((value: string) => {
              this.jumpToPageInput = value;
            })

          Row({ space: 12 }) {
            Button('取消')
              .layoutWeight(1)
              .height(40)
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor($r('app.color.text_secondary'))
              .backgroundColor($r('app.color.background_secondary'))
              .onClick(() => {
                this.hideJumpToPageDialogWithAnimation();
              })

            Button('跳转')
              .layoutWeight(1)
              .height(40)
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor($r('app.color.text_on_accent'))
              .backgroundColor($r('app.color.accent'))
              .onClick(() => {
                const pageNum = parseInt(this.jumpToPageInput);
                if (isNaN(pageNum) || pageNum <= 0 || pageNum > this.getTotalPages()) {
                  this.getUIContext().getPromptAction().showToast({ message: '请输入有效页码' });
                  return;
                }
                this.jumpToPage(pageNum - 1, 'jump_dialog');
                this.hideJumpToPageDialogWithAnimation();
              })
          }
          .width('100%')
        }
        .width('80%')
        .constraintSize({ maxWidth: 320 })
        .padding(20)
        .backgroundColor(this.themeManager.getGlassBackgroundResource())
        .backgroundBlurStyle(this.themeManager.getGlassBlurStyle())
        .borderRadius(16)
        .opacity(this.jumpToPageDialogOpacity)
        .scale({ x: this.jumpToPageDialogScale, y: this.jumpToPageDialogScale })
      }
    }
    .width('100%')
    .height('100%')
    .zIndex(1200)
  }

  @Builder
  private buildPageTurnAnimationSettings() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.background_overlay'))
        .opacity(0.5)
        .onClick(() => {
          this.hidePageTurnAnimationSettingsWithAnimation();
        })

      if (this.isLandscapeMode) {
        Row() {
          Column()
            .layoutWeight(1)
            .height('100%')
            .onClick(() => {
              this.hidePageTurnAnimationSettingsWithAnimation();
            })

          Column() {
            Row() {
              Text('翻页动画设置')
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
                .layoutWeight(1)
                .fontFamily(this.appFontFamily)

              Button() {
                Image($r('app.media.ic_close'))
                  .width(20)
                  .height(20)
                  .fillColor($r('app.color.text_secondary'))
              }
              .width(36)
              .height(36)
              .backgroundColor(Color.Transparent)
              .onClick(() => {
                this.hidePageTurnAnimationSettingsWithAnimation();
              })
            }
            .width('100%')
            .margin({ bottom: 16 })

            Scroll() {
              Column() {
                Text('选择翻页动画')
                  .fontSize(14)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')
                  .margin({ bottom: 8 })
                  .fontFamily(this.appFontFamily)

                Row() {
                  this.buildAnimButton('无', PageTurnAnimationType.NONE)
                  this.buildAnimButton('滑动', PageTurnAnimationType.SLIDE)
                  this.buildAnimButton('淡入淡出', PageTurnAnimationType.FADE)
                }
                .width('100%')
                .justifyContent(FlexAlign.SpaceBetween)
                .margin({ bottom: 8 })

                Row() {
                  this.buildAnimButton('立方体', PageTurnAnimationType.CUBE)
                  this.buildAnimButton('覆盖', PageTurnAnimationType.COVER)
                  this.buildAnimButton('景深', PageTurnAnimationType.DEPTH)
                }
                .width('100%')
                .justifyContent(FlexAlign.SpaceBetween)
                .margin({ bottom: 16 })

                Text('卷页参数')
                  .fontSize(14)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')
                  .margin({ bottom: 8 })
                  .fontFamily(this.appFontFamily)

                Row() {
                  if (this.isCurlAnimationSupported()) {
                    this.buildAnimButton('卷页', PageTurnAnimationType.CURL)
                  } else {
                    Column() {
                      Text('卷页模式')
                        .fontSize(13)
                        .fontColor($r('app.color.text_secondary'))
                        .fontFamily(this.appFontFamily)
                      Text('设备不支持')
                        .fontSize(10)
                        .fontColor($r('app.color.text_secondary'))
                        .margin({ top: 2 })
                        .fontFamily(this.appFontFamily)
                    }
                    .width(100)
                    .height(50)
                    .backgroundColor($r('app.color.background_secondary'))
                    .borderRadius(8)
                    .justifyContent(FlexAlign.Center)
                    .opacity(0.5)
                  }
                }
                .width('100%')
                .justifyContent(FlexAlign.Start)

                if (this.readingSettings.pageTurnAnimation === PageTurnAnimationType.CURL && this.isCurlAnimationSupported()) {
                  Column() {
                    Row() {
                      Text('卷页不透明度')
                        .fontSize(14)
                        .fontColor($r('app.color.text_secondary'))
                        .fontFamily(this.appFontFamily)
                      Text(`${this.readingSettings.curlBackOpacity ?? 90}%`)
                        .fontSize(14)
                        .fontColor($r('app.color.accent'))
                        .fontFamily(this.appFontFamily)
                    }
                    .width('100%')
                    .justifyContent(FlexAlign.SpaceBetween)
                    .margin({ top: 16, bottom: 8 })

                    Slider({
                      value: this.readingSettings.curlBackOpacity ?? 90,
                      min: 0,
                      max: 100,
                      step: 5,
                      style: SliderStyle.OutSet
                    })
                      .blockColor($r('app.color.accent'))
                      .trackColor($r('app.color.background_secondary'))
                      .selectedColor($r('app.color.accent'))
                      .onChange((value: number) => {
                        this.readingSettings.curlBackOpacity = value;
                        this.handleSettingsChange(this.readingSettings);
                      })
                  }
                  .width('100%')
                }
              }
              .width('100%')
            }
            .layoutWeight(1)
            .scrollBar(BarState.Off)
          }
          .width(320)
          .height('100%')
          .padding(16)
          .backgroundColor(this.themeManager.getGlassBackgroundResource())
          .backgroundBlurStyle(this.themeManager.getGlassBlurStyle())
          .borderRadius({ topLeft: 16, bottomLeft: 16 })
          .opacity(this.pageTurnAnimationSettingsOpacity)
          .translate({ x: this.pageTurnAnimationSettingsTranslateX })
          .hitTestBehavior(HitTestMode.Default)
        }
        .width('100%')
        .height('100%')
      } else {
        Column() {
          Row() {
            Text('翻页动画设置')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
              .layoutWeight(1)
              .fontFamily(this.appFontFamily)

            Button() {
              Image($r('app.media.ic_close'))
                .width(20)
                .height(20)
                .fillColor($r('app.color.text_secondary'))
            }
            .width(36)
            .height(36)
            .backgroundColor(Color.Transparent)
            .onClick(() => {
              this.hidePageTurnAnimationSettingsWithAnimation();
            })
          }
          .width('100%')
          .margin({ bottom: 16 })

          Text('选择翻页动画')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .margin({ bottom: 8 })
            .fontFamily(this.appFontFamily)

          Row() {
            this.buildAnimButton('无', PageTurnAnimationType.NONE)
            this.buildAnimButton('滑动', PageTurnAnimationType.SLIDE)
            this.buildAnimButton('淡入淡出', PageTurnAnimationType.FADE)
          }
          .width('100%')
          .justifyContent(FlexAlign.SpaceBetween)
          .margin({ bottom: 8 })

          Row() {
            this.buildAnimButton('立方体', PageTurnAnimationType.CUBE)
            this.buildAnimButton('覆盖', PageTurnAnimationType.COVER)
            this.buildAnimButton('景深', PageTurnAnimationType.DEPTH)
          }
          .width('100%')
          .justifyContent(FlexAlign.SpaceBetween)
          .margin({ bottom: 16 })

          Text('卷页参数')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .margin({ bottom: 8 })
            .fontFamily(this.appFontFamily)

          Row() {
            if (this.isCurlAnimationSupported()) {
              this.buildAnimButton('卷页', PageTurnAnimationType.CURL)
            } else {
              Column() {
                Text('卷页模式')
                  .fontSize(13)
                  .fontColor($r('app.color.text_secondary'))
                  .fontFamily(this.appFontFamily)
                Text('设备不支持')
                  .fontSize(10)
                  .fontColor($r('app.color.text_secondary'))
                  .margin({ top: 2 })
                  .fontFamily(this.appFontFamily)
              }
              .width(100)
              .height(50)
              .backgroundColor($r('app.color.background_secondary'))
              .borderRadius(8)
              .justifyContent(FlexAlign.Center)
              .opacity(0.5)
            }
          }
          .width('100%')
          .justifyContent(FlexAlign.Start)

          if (this.readingSettings.pageTurnAnimation === PageTurnAnimationType.CURL && this.isCurlAnimationSupported()) {
            Column() {
              Row() {
                Text('卷页背面透明度')
                  .fontSize(14)
                  .fontColor($r('app.color.text_secondary'))
                  .fontFamily(this.appFontFamily)
                Text(`${this.readingSettings.curlBackOpacity ?? 90}%`)
                  .fontSize(14)
                  .fontColor($r('app.color.accent'))
                  .fontFamily(this.appFontFamily)
              }
              .width('100%')
              .justifyContent(FlexAlign.SpaceBetween)
              .margin({ top: 16, bottom: 8 })

              Slider({
                value: this.readingSettings.curlBackOpacity ?? 90,
                min: 0,
                max: 100,
                step: 5,
                style: SliderStyle.OutSet
              })
                .blockColor($r('app.color.accent'))
                .trackColor($r('app.color.background_secondary'))
                .selectedColor($r('app.color.accent'))
                .onChange((value: number) => {
                  this.readingSettings.curlBackOpacity = value;
                  this.handleSettingsChange(this.readingSettings);
                })
            }
            .width('100%')
          }
        }
        .width('90%')
        .constraintSize({ maxWidth: 400 })
        .padding(20)
        .backgroundColor(this.themeManager.getGlassBackgroundResource())
        .backgroundBlurStyle(this.themeManager.getGlassBlurStyle())
        .borderRadius(16)
        .opacity(this.pageTurnAnimationSettingsOpacity)
        .scale({ x: this.pageTurnAnimationSettingsScale, y: this.pageTurnAnimationSettingsScale })
        .translate({ y: this.pageTurnAnimationSettingsTranslateY })
      }
    }
    .width('100%')
    .height('100%')
    .zIndex(1200)
  }

  build() {
    NavDestination() {
      Stack() {
        if (this.isLoading) {
          this.buildLoadingView()
        } else if (this.errorMessage.trim().length > 0) {
          this.buildErrorView()
        } else if (this.runtimeChapter) {
          Column() {
            MangaViewer({
              chapter: this.runtimeChapter,
              currentPageIndex: this.currentPageIndex,
              readingSettings: this.readingSettings,
              zoomScale: this.viewerZoomScale,
              toolbarsVisible: this.showTopToolbar || this.showBottomToolbar,
              chapterTick: 0,
              readFlowSessionId: this.mangaReadFlowSessionId,
              preloadCurrentPages: 1,
              preloadNextPages: 1,
              contentType: 'ebook',
              preloadDebugInfo: $preloadDebugInfo,
              isFirstChapter: true,
              isLastChapter: true,
              callbacks: {
                onPageChange: (pageIndex: number) => { this.handleViewerPageChange(pageIndex); },
                onChapterChange: (_direction: 'prev' | 'next') => {},
                onZoomChange: (scale: number) => { this.viewerZoomScale = scale; },
                onSingleTap: (event: ClickEvent) => { this.handlePageTap(event); },
                onDoubleTap: (event: ClickEvent) => { this.handleDoubleTap(event); },
                onComponentReady: (component: MangaViewer) => {
                  this.mangaViewerComponent = component;
                  setTimeout(() => {
                    component.kickstartLoading();
                    component.setPageIndex(this.initialViewerPageIndex);
                    this.isReaderInitialized = true;
                    this.applyCurrentPageIndex(this.initialViewerPageIndex, 'component_ready', false);
                    this.notifyTransitionReaderReadyOnce('viewer_ready');
                    this.syncAutoPageTurnStateFromSettings(true);
                  }, EBookImageReaderPage.VIEWER_READY_DELAY_MS);
                }
              }
            })
              .width('100%')
              .height('100%')
              .backgroundColor(Color.Black)
          }
          .width('100%')
          .height('100%')
          .onClick((event: ClickEvent) => {
            this.handlePageTap(event);
          })
          .onAreaChange((_oldArea: Area, newArea: Area) => {
            const widthVp = Number(newArea.width);
            const heightVp = Number(newArea.height);
            if (widthVp > 0 && heightVp > 0) {
              const widthChanged = Math.abs(widthVp - this.componentWidth) > 1;
              const heightChanged = Math.abs(heightVp - this.componentHeight) > 1;
              this.componentWidth = widthVp;
              this.componentHeight = heightVp;
              this.isLandscapeMode = widthVp > heightVp;
              if ((widthChanged || heightChanged) && !this.shouldSkipFullscreenRestore('area_change')) {
                this.scheduleFullscreenRestore('area_change', 120);
              }
            }
          })
        }

        if (this.preloadDebugMode === 'always' || (this.preloadDebugMode === 'on' && (this.showTopToolbar || this.showBottomToolbar))) {
          Column() {
            Blank()
            PreloadDebugOverlay({ debugInfo: $preloadDebugInfo, visible: true })
              .margin({ left: 16, right: 16, bottom: 80 })
          }
          .width('100%')
          .height('100%')
          .hitTestBehavior(HitTestMode.Transparent)
          .zIndex(90)
        }

        if (this.showTopToolbar) {
          Column() {
            this.buildTopToolbar()
          }
          .width('100%')
          .align(Alignment.TopStart)
          .position({ x: 0, y: 0 })
          .zIndex(100)
        }
        if (this.showBottomToolbar) {
          Column() {
            this.buildBottomToolbar()
          }
          .width('100%')
          .position({ x: 0, y: '100%' })
          .translate({ x: 0, y: '-100%' })
          .zIndex(100)
        }
        if (this.showMoreMenu) { this.buildMoreMenu() }
        if (this.showQuickSettings) {
          MangaQuickSettings({
            readingSettings: this.readingSettings,
            isVisible: this.showQuickSettings,
            callbacks: {
              onSettingsChange: (settings: MangaReadingSettings) => { this.handleSettingsChange(settings); },
              onClose: () => { this.hideQuickSettingsWithAnimation(); },
              onOpenFullSettings: () => {
                this.showQuickSettings = false;
                this.showSettingsPanelWithAnimation();
              }
            }
          })
            .opacity(this.quickSettingsOpacity)
            .scale({ x: this.quickSettingsScale, y: this.quickSettingsScale })
            .translate({ y: this.quickSettingsTranslateY })
            .zIndex(1000)
        }
        if (this.showSettingsPanel) {
          MangaReaderSettings({
            readingSettings: this.readingSettings,
            isVisible: this.showSettingsPanel,
            callbacks: {
              onSettingsChange: (settings: MangaReadingSettings) => { this.handleSettingsChange(settings); },
              onClose: () => { this.hideSettingsPanelWithAnimation(); }
            }
          })
            .opacity(this.settingsPanelOpacity)
            .scale({ x: this.settingsPanelScale, y: this.settingsPanelScale })
            .translate({ y: this.settingsPanelTranslateY })
            .zIndex(1000)
        }
        if (this.showChapterList) {
          MangaReaderChapterList({
            chapters: this.chapterListChapters,
            currentChapterId: this.getCurrentChapterListId(),
            isVisible: this.showChapterList,
            callbacks: {
              onChapterSelect: (chapterId: string) => { this.handleChapterListSelect(chapterId); },
              onClose: () => { this.showChapterList = false; this.handleMenusVisibilityChange(); }
            }
          }).zIndex(1000)
        }
        if (this.showAutoPageTurnSettings) { this.buildAutoPageTurnSettings() }
        if (this.showJumpToPageDialog) { this.buildJumpToPageDialog() }
        if (this.showPageTurnAnimationSettings) { this.buildPageTurnAnimationSettings() }
        if (this.showInteractionOverlay) {
          MangaInteractionOverlay({
            params: {
              readingMode: this.readingSettings.readingMode,
              readingDirection: this.readingSettings.readingDirection,
              componentWidth: this.componentWidth > 0 ? this.componentWidth : this.screenWidth,
              componentHeight: this.componentHeight > 0 ? this.componentHeight : this.screenHeight,
              deviceOrientation: this.getDeviceOrientation(),
              statusBarHeight: this.statusBarHeight,
              navigationBarHeight: this.navigationBarHeight,
              onDismiss: () => {
                this.showInteractionOverlay = false;
                this.handleMenusVisibilityChange();
              }
            }
          }).width('100%').height('100%').zIndex(1200)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Black)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
      .focusable(true)
      .defaultFocus(true)
      .id('' as string)
      .onKeyEvent((event: KeyEvent) => {
        if (event.type === KeyType.Up) {
          const consumed = this.handleVolumeKeyPageTurn(event.keyCode);
          if (consumed) {
            event.stopPropagation();
          }
        }
      })
    }
    .title('')
    .hideTitleBar(true)
    .onBackPressed(() => {
      if (this.areMenusVisible()) {
        this.closeAllMenus();
        return true;
      }
      void this.goBack();
      return true;
    })
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      this.uiContext = this.getUIContext();
      PageWindowCoordinator.applyPagePolicy('EBookImageReaderPage', this.uiContext);
      WindowManager.setDisplayMode(DisplayMode.FULL_IMMERSIVE, this.uiContext);
      WindowManager.reapplyCurrentDisplayMode(24);
      const params = context.pathInfo.param as EBookReaderParams;
      if (params) {
        void this.initializeWithParams(params);
      } else {
        this.errorMessage = '缺少阅读器参数';
        this.isLoading = false;
      }
    })
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
  }
}

export { EBookImageReaderPage };
