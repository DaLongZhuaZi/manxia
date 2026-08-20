import { ISettingsManagerFacade, SettingsManagerHolder } from 'manxia_core/src/main/ets/Framework/Contracts/ISettingsManagerFacade';
import { SafeUtils } from 'manxia_core/src/main/ets/Utils/SafeUtils';
// 文件路径: entry/src/main/ets/pages/EBookReaderPage.ets
/**
 * 电子书阅读器页面
 * 支持TXT、EPUB等格式的电子书阅读
 * 采用与漫画阅读器一致的沉浸式设计风格
  */

import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { common } from '@kit.AbilityKit';
import { ReaderSafeAreaUtils } from '../Utils/ReaderSafeAreaUtils';
import { ThemeAwareState, ThemeAwareHelper } from 'manxia_theme/src/main/ets/Framework/Components/ThemeAware';
import { ThemeManager, ThemeType, GlassEffectContext } from 'manxia_theme/src/main/ets/Framework/Managers/ThemeManager';
import { FontAwareHelper, FontAwareState } from 'manxia_theme/src/main/ets/Framework/Components/FontAware';
import { PageLifecycleManager } from 'manxia_core/src/main/ets/Framework/Lifecycle/index';
import { WindowManager, DisplayMode } from 'manxia_theme/src/main/ets/Utils/WindowManager';
import { ReaderOrientationLockHelper } from 'manxia_core/src/main/ets/Utils/ReaderOrientationLockHelper';
import { PageWindowCoordinator } from 'manxia_theme/src/main/ets/Utils/PageWindowCoordinator';
import {
  EBook,
  EBookChapter,
  EBookReadingProgress,
  EBookReadingSettings,
  EBookPageMode,
  EBookFormat,
  EBookContentMode,
  DEFAULT_EBOOK_READING_SETTINGS
} from 'manxia_core/src/main/ets/Models/EBookModels';
import { SettingKeys } from 'manxia_core/src/main/ets/Framework/Contracts/SettingKeys';
import { EBookDataManager } from '../Framework/Data/EBookDataManager';
import { PdfViewerComponent } from '../Framework/Components/PdfViewerComponent';
import { PdfKitViewerComponent, PdfViewerCallbacks, PdfViewerController } from '../Framework/Components/PdfKitViewerComponent';
import { ReaderKitViewerComponent, ReaderKitViewerController } from '../Framework/Components/ReaderKitViewerComponent';
import { isReaderKitEnabled } from '../Framework/Initialization/ReaderKitFeatureGate';
import { EBookParserFactory } from '../Framework/Parsers/EBookParser';
import { EBookReaderParams } from './EBookReaderRouteTypes';
import { READER_ABILITY_HOST_MULTITON } from 'manxia_reader_ui/src/main/ets/Framework/Reader/MangaReaderAbilityConstants';
import { EBookReadingSettingsPanel } from '../Framework/Components/EBookReadingSettingsPanel';
import { curves, UIContext } from '@kit.ArkUI';
import { display } from '@kit.ArkUI';
import { TextReaderComponent, PaginationMode } from '../components/TextReaderComponent';
import {
  MarkdownViewerComponent,
  MarkdownTheme,
  MarkdownViewerController,
  MarkdownReaderStyle,
  MarkdownProgressSnapshot,
  MarkdownPageTurnResult
} from 'manxia_features_ui/src/main/ets/components/editor/MarkdownViewerComponent';
import { MangaViewer } from '../components/MangaViewer';
import { PreloadDebugInfo } from '../components/PreloadDebugOverlay';
import { TextReaderSettingsPanel } from '../components/TextReaderSettingsPanel';
import { TextReaderInteractionOverlay } from '../components/TextReaderInteractionOverlay';
import {
  MangaChapter,
  MangaPage,
  ImageSourceType,
  ReadingSettings as MangaReadingSettings,
  DEFAULT_READING_SETTINGS
} from 'manxia_core/src/main/ets/Models/MangaModels';
import { DownloadStatus } from 'manxia_core/src/main/ets/Framework/Types/StatusEnums';
import {
  TextReaderSettings,
  TextReadingMode,
  TextReadingDirection,
  TextPageTurnAnimation,
  BackgroundType,
  DEFAULT_TEXT_READER_SETTINGS,
  DEFAULT_READ_ALOUD_SETTINGS,
  ReadAloudEngineType,
  ReadAloudSettings,
  mergeRemoteReadAloudSettings,
  normalizeReadAloudSettings,
  TEXT_READER_FONT_SIZE_MIN,
  TEXT_READER_FONT_SIZE_MAX,
  clampTextReaderFontSize,
  isTextFile,
  TextAlignment,
  SavedBackgroundImage,
  TextChapter,
  PRESET_BACKGROUNDS,
  PresetBackground
} from 'manxia_core/src/main/ets/Models/TextReaderModels';
import { eventBus, GameEvent, BasePayload, IEventPayload, ReadAloudStatePayload } from '../Framework/EventBus';
import { KeyCode, inputConsumer } from '@kit.InputKit';
import type { KeyEvent as InputKeyEvent } from '@kit.InputKit';
import { setReaderReady, setReaderLoadingProgress, startBookCloseTransitionWithComponentId, CoverPosition, cancelTransition } from '../components/BookTransitionOverlay';
import { ReadAloudController } from '../Framework/ReadAloud/ReadAloudController';
import { ReadAloudPlaybackState, ReadAloudVoiceOption } from '../Framework/ReadAloud/ReadAloudTypes';
import { ReadAloudAvailability, ReadAloudEngineAvailabilityMap } from '../Framework/ReadAloud/ReadAloudAvailability';
import {
  loadGlobalReadAloudSettings as loadStoredGlobalReadAloudSettings,
  persistGlobalReadAloudSettings as persistStoredGlobalReadAloudSettings
} from '../Framework/ReadAloud/ReadAloudSettingsStore';
import { ReadAloudSettingsInfoPanel } from '../components/ReadAloudSettingsInfoPanel';
import { UnifiedContentType } from 'manxia_core/src/main/ets/Models/UnifiedContentModels';
import { getUnifiedAnnotationManager } from 'manxia_core/src/main/ets/Framework/Annotations/UnifiedAnnotationManager';
import { AnnotationAnchor, UnifiedAnnotationType } from 'manxia_core/src/main/ets/Models/AnnotationModels';
import { MangaReadFlowMonitor } from 'manxia_reader_ui/src/main/ets/Framework/Reader/MangaReadFlowMonitor';
import {
  MangaReadFlowEvent,
  MangaReadFlowEventType,
  MangaReadFlowModeKind,
  MangaReadFlowSessionInfo,
  MangaReadFlowSeverity,
  MangaReadFlowSourceKind
} from 'manxia_reader_ui/src/main/ets/Framework/Reader/MangaReadFlowTypes';
import { AnnotationCenterPageParams } from './AnnotationCenterPage';
import { AppGuideOverlay, GuideHighlightRect } from '../Framework/Components/AppGuideOverlay';
import { resolveGuideHighlightRectInRoot } from '../Framework/Components/AppGuideSupport';
import { AppGuideManager, AppGuidePageId, AppGuideStep } from '../Framework/Managers/AppGuideManager';
import { distributedReadingService } from '../Framework/Distributed/DistributedReadingService';
import { distributedDataSyncManager, SyncReadingState } from '../Framework/Distributed/DistributedDataSyncManager';
import { distributedPermissionManager } from '../Framework/Distributed/DistributedPermissionManager';
import { continuationStateHelper } from '../Framework/Distributed/ContinuationStateHelper';

const TAG = 'EBookReaderPage';

interface EBookBookmarkContext {
  chapterId: string;
  chapterTitle: string;
  chapterIndex: number;
  pageIndex: number;
  progress: number;
  startOffset: number;
  endOffset: number;
  isTextMode: boolean;
}

interface ReaderKitPositionSnapshot {
  resourceIndex: number;
  resourceCount: number;
  pageOffset: number;
  startDomPos: string;
  endDomPos: string;
  dataId: string;
}

@Component
struct EBookReaderPage {
  private static readonly TOOLBAR_AUTO_HIDE_DELAY_MS: number = 2200;
  private static readonly GUIDE_LAYOUT_STABILIZE_DELAY_MS: number = 140;
  private static readonly INTERACTION_HINT_READER_SCOPE: string = 'ebook';
  private static hasShownInteractionHint: boolean = false;
  private static lastShownInteractionHintKey: string = '';
  @State pathStack: NavPathStack = new NavPathStack();
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State isRemoteControlled: boolean = false;
  @State fontState: FontAwareState = new FontAwareState();
  @State private appGuideStep: AppGuideStep | null = null;
  @State private appGuideHighlightRect: GuideHighlightRect | null = null;
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @StorageProp('isInBackground') @Watch('onAppBackgroundStateChanged') appInBackground: boolean = false;
  private componentId: string = 'EBookReaderPage';
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private lifecycle = new PageLifecycleManager('EBookReaderPage', { enableDebug: true });
  private routerBackOnClose: boolean = false;
  private forceReaderKit: boolean = false;
  private readerHostMode: string = '';
  private readerInstanceId: string = '';
  private originImportId: string = '';
  private originImportKind: string = '';

  // 电子书数据
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;

  // 电子书数据
  @State ebook: EBook | null = null;
  @State currentChapter: EBookChapter | null = null;
  @State currentChapterIndex: number = 0;
  @State private imagePageChapterTick: number = 0;
  @State private imagePageReaderSettings: MangaReadingSettings = DEFAULT_READING_SETTINGS;
  @State private imagePagePreloadDebugInfo: PreloadDebugInfo = {
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

  // 阅读设置
  @State fontSize: number = 18;
  @State lineHeight: number = 1.8;
  @State bgColor: string = '#FFFFFF';
  @State textColor: string = '#333333';
  @State pageMargin: number = 20;
  @State bgImagePath: string = '';  // 背景图片路径
  @State bgImageOpacity: number = 0.3;// 背景图片透明度

  // UI控制状态 - 默认隐藏工具栏实现完全沉浸式体验
  @State showTopToolbar: boolean = false;
  @State showBottomToolbar: boolean = false;
  @State toolbarOpacity: number = 0.0;
  @State private stableToolbarStatusBarHeight: number = -1;
  @State showSettingsPanel: boolean = false;
  @State showChapterList: boolean = false;
  @State showMoreMenu: boolean = false;
  
  // 动画状态
  @State settingsPanelOpacity: number = 0;
  @State settingsPanelScale: number = 0.95;
  @State settingsPanelTranslateY: number = 20;
  @State moreMenuOpacity: number = 0;
  @State moreMenuScale: number = 0.95;
  @State moreMenuTranslateY: number = -10;
  @State chapterListOpacity: number = 0;
  
  // 书籍信息弹窗状态
  private chapterListScroller: Scroller = new Scroller();
  
  // 字体设置面板状态
  @State showBookInfoDialog: boolean = false;
  @State bookInfoDialogOpacity: number = 0;
  private toolbarAutoHideTimer: number = -1;
  private fullscreenRestoreTimer: number = -1;

  // 阅读设置面板状态（主题、翻页等）
  @State showFontSettingsPanel: boolean = false;
  @State fontSettingsPanelOpacity: number = 0;
  @State fontSettingsPanelScale: number = 0.95;
  
  // 横屏检测状态
  @State showReadingOptionsPanel: boolean = false;
  @State readingOptionsPanelOpacity: number = 0;
  @State readingOptionsPanelScale: number = 0.95;

  // 文本阅读器状态（用于 TXT 等纯文本格式）
  @State isLandscape: boolean = false;
  @State screenWidth: number = 0;

  // 文本阅读器状态（用于 TXT 等纯文本格式）
  @State textReaderSettings: TextReaderSettings = DEFAULT_TEXT_READER_SETTINGS;
  @State textCurrentPageIndex: number = 0;
  // [修复] 跨端接续恢复的待应用状态（onReady 读取 wantParam 快照，loadEBook 恢复进度后应用）
  private pendingContinuationChapterIndex: number = -1;
  private pendingContinuationPageIndex: number = -1;
  @State textContent: string = '';
  @State textCurrentPageStartCharIndex: number = 0;
  @State textCurrentPageEndCharIndex: number = 0;
  @State textReadAloudPlaying: boolean = false;
  @State textReadAloudCurrentCharIndex: number = -1;
  @State showTextInteractionOverlay: boolean = false;
  @State isCurrentPageBookmarked: boolean = false;
  @State currentPageBookmarkId: string = '';
  private previousDisplayMode: DisplayMode = DisplayMode.DEFAULT;
  @State showReadAloudPanel: boolean = false;
  @State readAloudPanelSettings: ReadAloudSettings = DEFAULT_READ_ALOUD_SETTINGS;
  @State readAloudAvailability: ReadAloudEngineAvailabilityMap = ReadAloudAvailability.getCachedOrDefault();
  @State readAloudVoiceOptions: ReadAloudVoiceOption[] = [];
  @State readAloudStatusMessage: string = '';
  // 听书进度持久化节流，避免高频写库
  private latestTextProgress: number = 0;
  // 听书进度持久化节流，避免高频写库
  private lastReadAloudProgressSaveTime: number = 0;
  private lastReadAloudPanelCloseTime: number = 0;
  private static readonly READ_ALOUD_PANEL_REOPEN_GUARD_MS: number = 320;
  private static readonly READ_ALOUD_PROGRESS_SAVE_INTERVAL_MS: number = 3000;
  private isPageVisible: boolean = false;
  @State showTextReaderSettings: boolean = false;
  @State textReaderSettingsOpacity: number = 0;
  @State textReaderSettingsScale: number = 0.95;
  @State private readerViewportWidth: number = 0;
  @State private readerViewportHeight: number = 0;
  @State private markdownContent: string = '';
  @State private markdownChapterProgress: number = 0;
  @State private markdownOverallProgress: number = 0;
  @State private markdownCurrentPage: number = 1;
  @State private markdownPageCount: number = 1;
  private pendingInteractionHintKey: string = '';
  private interactionOverlayDismissTimer: number = -1;

  // UI上下文（用于设置沉浸式模式）
  private settingsManager: ISettingsManagerFacade = SettingsManagerHolder.get();
  private ebookDataManager: EBookDataManager = EBookDataManager.getInstance();
  private annotationManager = getUnifiedAnnotationManager();
  private readAloudController: ReadAloudController = ReadAloudController.getInstance();
  private appGuideManager: AppGuideManager = AppGuideManager.getInstance();
  
  // Reader Kit 阅读器控制器（用于实时应用设置和跳转章节）
  private uiContext: UIContext | undefined = undefined;
  private sourceCoverComponentId: string = '';
  private hasNotifiedTransitionReaderReady: boolean = false;
  private transitionLoadingProgress: number = 0;
  private isCloseTransitionNavigating: boolean = false;
  private orientationLockToken: string = '';
  
  // 阅读时间记录相关
  private readerKitController: ReaderKitViewerController | null = null;
  private markdownController: MarkdownViewerController | null = null;
  private pendingMarkdownRestoreProgress: number = -1;
  private pendingMarkdownHeadingId: string = '';
  private pendingMarkdownSaveAfterRender: boolean = false;
  private pdfViewerController: PdfViewerController | null = null;
  private readerKitStartupGuardActive: boolean = false;
  private readerKitStartupGuardStartTime: number = 0;
  private readerKitStartupExpectedChapterIndex: number = -1;
  private readerKitStartupExpectedPageOffset: number = -1;
  private static readonly READERKIT_STARTUP_GUARD_WINDOW_MS: number = 6000;
  private mangaReadFlowMonitor: MangaReadFlowMonitor = MangaReadFlowMonitor.getInstance();
  private pdfReadFlowSessionId: string = '';

  // 音量键翻页相关
  private readingSessionStartTime: number = 0;// 阅读会话开始时间
  private accumulatedReadingTime: number = 0;// 累计阅读时间（分钟）
  private readingTimeTimer: number = -1;// 阅读时间定时器
  private static readonly READING_TIME_INTERVAL: number = 1000;// 阅读时间记录间隔（1秒）

  // 音量键翻页相关
  private isVolumeKeyListenerRegistered: boolean = false;
  private volumeUpCallback: ((event: InputKeyEvent) => void) | null = null;
  private volumeDownCallback: ((event: InputKeyEvent) => void) | null = null;
  private onReadAloudStateChanged: (payload: IEventPayload) => void = (payload: IEventPayload): void => {
    const ebook = this.ebook;
    if (!ebook || !this.isTextReaderFormat(ebook.format)) {
      return;
    }
    const statePayload = payload as ReadAloudStatePayload;
    const payloadBookId = statePayload.bookId ?? '';
    if (!payloadBookId || payloadBookId !== ebook.id) {
      return;
    }
    if (!this.shouldHandleReadAloudUiEvents()) {
      return;
    }

    this.textReadAloudPlaying = statePayload.playbackState === ReadAloudPlaybackState.PLAYING;
    this.applyTextReadAloudProgress(statePayload);
    if (
      statePayload.playbackState !== ReadAloudPlaybackState.PLAYING &&
      statePayload.reason !== 'progress_updated'
    ) {
      this.saveReadingProgress();
    }
  };

  aboutToAppear(): void {
    this.isPageVisible = true;
    distributedReadingService.attachToReader();
    // [修复] 阅读器进入是窗口就绪的可靠时机：稳定提起分布式数据同步权限请求
    // （管理器内部节流；未授权且满足间隔时会再次弹窗，被打断会在下次进入时重试）
    this.requestDistributedDataSyncPermission();
    // [修复] 权限前置激活系统接续入口（覆盖 NavPath 宿主场景下主页的 INACTIVE；权限未授权时不进入接续状态）
    this.applyMissionContinueStateWithPermission();
    // [修复] 标记阅读器页面在前台（供 onContinue 守卫判定有效阅读状态）
    AppStorage.setOrCreate('currentReaderHostPage', 'EBookReaderPage');
    eventBus.subscribe(GameEvent.READ_ALOUD_STATE_CHANGED, this.onReadAloudStateChanged);
    AppStorage.setOrCreate('ReadAloudCurrentHostPage', 'EBookReaderPage');
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (theme: ThemeType) => {
      logger.info(TAG, `主题切换到: ${theme}`);
      if (this.ebook && this.ebook.readingSettings && this.ebook.readingSettings.followSystemTheme === true) {
        this.applySystemThemeToSettings(this.ebook);
        this.bgColor = this.ebook.readingSettings.backgroundColor;
        this.textColor = this.ebook.readingSettings.textColor;
        logger.info(TAG, '已根据系统主题更新阅读背景');
        return;
      }
      logger.info(TAG, '当前阅读背景为固定主题，不跟随系统主题');
    });
    // 初始化横屏检测
    // 初始化阅读时间记录
    
    // 初始化阅读时间记录
    this.updateScreenOrientation();
    
    // 注册音量键翻页监听
    this.startReadingTimeTracking();
    
    // 注册音量键翻页监听
    this.updateVolumeKeyListener();
    void this.refreshPageGuide('aboutToAppear');
  }

  /**
   * [修复] 稳定提起分布式数据同步权限请求（阅读器检查点）
   * 窗口已完全就绪，弹窗不会被启动时序打断；未授权且满足间隔时会再次弹出
   */
  private requestDistributedDataSyncPermission(): void {
    try {
      const hostContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (!hostContext) {
        logger.warn(TAG, '分布式权限请求跳过：无法获取 UIAbilityContext');
        return;
      }
      setTimeout(() => {
        void distributedPermissionManager.ensurePermission(hostContext);
      }, 800);
    } catch (error) {
      logger.warn(TAG, `分布式权限请求异常: ${String(error)}`);
    }
  }

  /**
   * [修复] 应用当前 mission 的接续状态（ACTIVE=显示系统接续入口）
   * 独立阅读器 Ability 宿主时由 Ability 自身设置；NavPath 宿主（EntryAbility）时由页面设置
   */
  private applyMissionContinueState(active: boolean): void {
    try {
      const hostContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (!hostContext) {
        return;
      }
      continuationStateHelper.setMissionContinueState(hostContext, active);
    } catch (error) {
      logger.warn(TAG, `设置接续状态失败: ${String(error)}`);
    }
  }

  /**
   * [修复] 激活接续入口（页面检查点）：
   * 入口按场景无条件显示；权限在触发接续时校验，此处异步确保权限就绪
   */
  private applyMissionContinueStateWithPermission(): void {
    try {
      const hostContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (!hostContext) {
        return;
      }
      continuationStateHelper.activateMissionContinueEntry(hostContext);
    } catch (error) {
      logger.warn(TAG, `设置接续状态失败: ${String(error)}`);
    }
  }

  private areReaderMenusVisible(): boolean {
    return this.showTopToolbar || this.showBottomToolbar || this.hasReaderOverlayVisible();
  }

  private turnEBookPageByVolume(forward: boolean): boolean {
    if (!this.ebook) {
      return false;
    }

    if (this.isUsingImagePageReader()) {
      if (forward) {
        this.nextChapter();
      } else {
        this.previousChapter();
      }
      return true;
    }

    if (this.ebook.format === EBookFormat.PDF) {
      if (!this.pdfViewerController || !this.pdfViewerController.isControllerReady()) {
        logger.warn(TAG, 'PDF viewer controller not ready for volume page turn');
        return false;
      }
      return forward ? this.pdfViewerController.goToNextPage() : this.pdfViewerController.goToPreviousPage();
    }

    if (this.isUsingMarkdownReader()) {
      return this.turnMarkdownPage(forward);
    }

    if (!this.isUsingTextReader()) {
      if (!this.readerKitController || !this.readerKitController.isControllerReady()) {
        logger.warn(TAG, 'ReaderKit controller not ready for volume page turn');
        return false;
      }
      return this.readerKitController.flipPage(forward);
    }

    if (forward) {
      this.textCurrentPageIndex++;
      return true;
    }

    if (this.textCurrentPageIndex <= 0) {
      return false;
    }
    this.textCurrentPageIndex--;
    return true;
  }

  private ensurePdfReadFlowSession(): void {
    if (!this.ebook || this.ebook.format !== EBookFormat.PDF || this.pdfReadFlowSessionId.length > 0) {
      return;
    }
    const info: MangaReadFlowSessionInfo = new MangaReadFlowSessionInfo();
    info.sessionId = this.mangaReadFlowMonitor.createSessionId('pdf');
    info.sourceKind = MangaReadFlowSourceKind.PDF;
    info.modeKind = MangaReadFlowModeKind.PDF_KIT;
    info.contentId = this.ebook.id;
    info.contentTitle = this.ebook.metadata.title;
    info.chapterId = this.currentChapter?.id || '';
    info.chapterTitle = this.currentChapter?.title || '';
    info.pageIndex = Math.max(0, this.currentChapterIndex);
    info.pageCount = this.ebook.chapters.length;
    info.readerHostMode = this.readerHostMode;
    info.readerInstanceId = this.readerInstanceId;
    info.originImportId = this.originImportId;
    info.originImportKind = this.originImportKind;
    info.startedAt = Date.now();
    this.pdfReadFlowSessionId = this.mangaReadFlowMonitor.startSession(info);
  }

  private recordPdfReadFlowEvent(
    eventType: MangaReadFlowEventType,
    reason: string,
    pageIndex: number,
    pageCount: number,
    detail: string
  ): void {
    this.ensurePdfReadFlowSession();
    if (this.pdfReadFlowSessionId.length <= 0 || !this.ebook) {
      return;
    }
    const event: MangaReadFlowEvent = this.mangaReadFlowMonitor.createEvent(
      this.pdfReadFlowSessionId,
      eventType,
      this.ebook.id,
      this.currentChapter?.id || '',
      pageIndex,
      reason
    );
    event.sourceKind = MangaReadFlowSourceKind.PDF;
    event.modeKind = MangaReadFlowModeKind.PDF_KIT;
    event.chapterTitle = this.currentChapter?.title || '';
    event.pageCount = pageCount;
    event.detail = detail;
    this.mangaReadFlowMonitor.record(event);
  }

  private recordPdfReadFlowError(reason: string, errorMessage: string): void {
    this.ensurePdfReadFlowSession();
    if (this.pdfReadFlowSessionId.length <= 0 || !this.ebook) {
      return;
    }
    const event: MangaReadFlowEvent = this.mangaReadFlowMonitor.createEvent(
      this.pdfReadFlowSessionId,
      MangaReadFlowEventType.ERROR,
      this.ebook.id,
      this.currentChapter?.id || '',
      this.currentChapterIndex,
      reason
    );
    event.sourceKind = MangaReadFlowSourceKind.PDF;
    event.modeKind = MangaReadFlowModeKind.PDF_KIT;
    event.success = false;
    event.severity = MangaReadFlowSeverity.ERROR;
    event.errorMessage = errorMessage;
    this.mangaReadFlowMonitor.record(event);
  }

  private recordPdfReadFlowGuardRejected(reason: string, pageIndex: number, pageCount: number, detail: string): void {
    this.ensurePdfReadFlowSession();
    if (this.pdfReadFlowSessionId.length <= 0 || !this.ebook) {
      return;
    }
    const event: MangaReadFlowEvent = this.mangaReadFlowMonitor.createEvent(
      this.pdfReadFlowSessionId,
      MangaReadFlowEventType.FLOW_GUARD_REJECTED,
      this.ebook.id,
      this.currentChapter?.id || '',
      pageIndex,
      reason
    );
    event.sourceKind = MangaReadFlowSourceKind.PDF;
    event.modeKind = MangaReadFlowModeKind.PDF_KIT;
    event.chapterTitle = this.currentChapter?.title || '';
    event.pageCount = pageCount;
    event.success = true;
    event.severity = MangaReadFlowSeverity.WARN;
    event.detail = detail;
    this.mangaReadFlowMonitor.record(event);
  }

  private lastRemoteInstructionTimestamp: number = 0;

  private onRemoteDataChanged = (state: SyncReadingState) => {
    if (!state.instructionType || state.instructionType === 'none' || state.instructionType === 'ack') {
      return;
    }
    if (state.timestamp <= this.lastRemoteInstructionTimestamp) {
      return;
    }
    this.lastRemoteInstructionTimestamp = state.timestamp;

    logger.info(TAG, `[RemoteControl] 收到电子书遥控指令: ${state.instructionType}`);
    switch (state.instructionType) {
      case 'cmd:next_page':
        this.turnEBookPageByVolume(true);
        break;
      case 'cmd:prev_page':
        this.turnEBookPageByVolume(false);
        break;
      case 'cmd:next_chapter':
        this.nextChapter();
        break;
      case 'cmd:prev_chapter':
        this.previousChapter();
        break;
      case 'cmd:toggle_auto_read':
        if (!this.isUsingTextReader()) {
          const unsupportedFormat = this.ebook ? String(this.ebook.format) : 'unknown';
          logger.warn(TAG, `[RemoteControl] 当前书籍格式不支持自动朗读，回执遥控端: format=${unsupportedFormat}`);
          distributedDataSyncManager.sendInstruction('ack_toggle_auto_read_unsupported', unsupportedFormat);
          return;
        }
        this.toggleTextReadAloud();
        break;
      default:
        logger.warn(TAG, `[RemoteControl] 未知电子书指令: ${state.instructionType}`);
        break;
    }
    distributedDataSyncManager.sendInstruction('ack', '');
  };

  private onRemoteStatusChanged = (status: 'online' | 'offline' | 'restored' | 'error', message?: string) => {
    if (status === 'offline') {
      logger.info(TAG, '[RemoteControl] 遥控器已断开');
      if (this.isRemoteControlled) {
        this.isRemoteControlled = false;
        this.getUIContext().getPromptAction().showToast({ message: '遥控器已断开' });
      }
    }
  };

  private registerRemoteControlListener(): void {
    logger.info(TAG, '[RemoteControl] 电子书被控端已注册遥控器指令监听');
    this.isRemoteControlled = true;
    this.getUIContext().getPromptAction().showToast({ message: '遥控已连接' });
    distributedDataSyncManager.addOnDataChangedCallback(this.onRemoteDataChanged);
    distributedDataSyncManager.addOnStatusChangedCallback(this.onRemoteStatusChanged);
    // [诊断] 被控端输出会话状态：确认目标端是否已加入分布式会话并收到过设备状态事件
    distributedDataSyncManager.diagnoseSession('电子书被控端注册');
  }

  private handleVolumeKeyPageTurn(keyCode: number): boolean {
    const volumeKeyEnabled = this.textReaderSettings.volumeKeyNavigation ?? true;
    logger.debug(TAG, `Volume key event: keyCode=${keyCode}, volumeKeyNavigation=${volumeKeyEnabled}`);

    if (!volumeKeyEnabled || this.isLoading || this.errorMessage.length > 0) {
      return false;
    }

    if (this.areReaderMenusVisible()) {
      logger.debug(TAG, 'Reader overlays visible, skip volume page turn');
      return false;
    }

    if (keyCode === KeyCode.KEYCODE_VOLUME_UP || keyCode === 16) {
      logger.info(TAG, 'Volume key page turn: previous');
      return this.turnEBookPageByVolume(false);
    }

    if (keyCode === KeyCode.KEYCODE_VOLUME_DOWN || keyCode === 17) {
      logger.info(TAG, 'Volume key page turn: next');
      return this.turnEBookPageByVolume(true);
    }

    return false;
  }

  /**
  * 更新屏幕方向状态
  */
  private updateScreenOrientation(): void {
    try {
      const displayInfo = display.getDefaultDisplaySync();
      const uiContext = this.uiContext ?? this.getUIContext();
      this.screenWidth = uiContext.px2vp(displayInfo.width);
      const screenHeight = uiContext.px2vp(displayInfo.height);
      this.isLandscape = this.screenWidth > screenHeight;
      logger.info(TAG, `屏幕方向: ${this.isLandscape ? '横屏' : '竖屏'}, 宽度=${this.screenWidth}vp`);
    } catch (error) {
      logger.error(TAG, `获取屏幕方向失败: ${String(error)}`);
    }
  }

  aboutToDisappear(): void {
    this.isPageVisible = false;
    distributedReadingService.detach();
    // [修复] 退出阅读器时清理当前阅读状态与接续标志：
    // 1) 防止陈旧 currentRead* 被 onContinue 打包流转（未阅读却显示接续状态）
    // 2) 防止未消费的 continuation* 残留导致下次打开阅读器误触发接续
    distributedReadingService.clearCurrentReadingState();
    distributedReadingService.clearContinuationFlags();
    this.pendingContinuationChapterIndex = -1;
    this.pendingContinuationPageIndex = -1;
    // [修复] 阅读器退出时关闭系统接续入口
    this.applyMissionContinueState(false);
    // [修复] 清理阅读器前台标志（防止守卫误判有效阅读状态）
    AppStorage.setOrCreate('currentReaderHostPage', '');
    // 断开遥控器监听，避免内存泄漏和回调冲突
    distributedDataSyncManager.removeOnDataChangedCallback(this.onRemoteDataChanged);
    distributedDataSyncManager.removeOnStatusChangedCallback(this.onRemoteStatusChanged);
    const isOpeningReadAloudPlayer = this.isReadAloudPlayerOpeningSoon();
    eventBus.unsubscribe(GameEvent.READ_ALOUD_STATE_CHANGED, this.onReadAloudStateChanged);
    this.clearToolbarAutoHideTimer();
    this.clearFullscreenRestoreTimer();
    this.hideInteractionOverlay();
    const readAloudSettings = this.getSafeReadAloudSettings(this.textReaderSettings.readAloud);
    const readAloudSnapshot = this.readAloudController.getSnapshot();
    const keepReadAloudAliveOnExit = isOpeningReadAloudPlayer || (
      readAloudSettings.continueInBackground &&
      (
        readAloudSnapshot.playbackState === ReadAloudPlaybackState.PLAYING ||
        readAloudSnapshot.playbackState === ReadAloudPlaybackState.PAUSED
      )
    );
    if (keepReadAloudAliveOnExit) {
      this.textReadAloudPlaying = readAloudSnapshot.playbackState === ReadAloudPlaybackState.PLAYING;
      if (isOpeningReadAloudPlayer) {
        logger.info(TAG, '离开电子书阅读器并进入听书独立页：已保持听书会话继续播放');
      } else {
        logger.info(TAG, '离开电子书阅读器：已保持听书后台继续播放');
      }
    } else {
      this.readAloudController.release();
      this.textReadAloudPlaying = false;
    }
    this.lifecycle.destroy();
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    // 保存阅读进度（包含累计阅读时间）
    this.unregisterVolumeKeyListener();
    // 恢复正常显示模式
    this.stopReadingTimeTracking();
    // [修复] 发布阅读进度更新事件，通知书库页面刷新
    this.saveReadingProgress();
    this.orientationLockToken = ReaderOrientationLockHelper.release(this.orientationLockToken, this.uiContext);
    // [修复] 安全清理过渡动画状态，防止页面销毁后覆盖层仍然阻止交互
    if (isOpeningReadAloudPlayer) {
      logger.info(TAG, '电子书阅读器即将进入听书独立页，aboutToDisappear 保留沉浸模式');
    }
    // [修复] 安全清理过渡动画状态，防止页面销毁后覆盖层仍然阻止交互
    if (!isOpeningReadAloudPlayer) {
      this.restoreNormalMode();
    }
    eventBus.publish(GameEvent.EBOOK_UPDATED, new BasePayload());
    // [修复] 安全清理过渡动画状态，防止页面销毁后覆盖层仍然阻止交互
    if (!this.isCloseTransitionNavigating) {
      cancelTransition();
    } else {
      logger.info(TAG, 'aboutToDisappear：关闭过渡动画进行中，跳过 cancelTransition');
    }
    if (this.pdfReadFlowSessionId.length > 0) {
      this.recordPdfReadFlowEvent(
        MangaReadFlowEventType.CLEANUP,
        'about_to_disappear',
        this.currentChapterIndex,
        this.ebook ? this.ebook.chapters.length : 0,
        'pdf_reader_cleanup'
      );
      this.mangaReadFlowMonitor.endSession(this.pdfReadFlowSessionId, 'about_to_disappear');
      this.pdfReadFlowSessionId = '';
    }
  }

  onPageShow(): void {
    this.isPageVisible = true;
    // [修复] 页面重新显示时按权限条件保持接续入口（覆盖主页/回前台时的 INACTIVE）
    this.applyMissionContinueStateWithPermission();
    this.setupFullscreenMode();
    this.scheduleFullscreenRestore('page_show');
    this.tryShowQueuedInteractionHint('page_show', 260);
    AppStorage.setOrCreate('ReadAloudCurrentHostPage', 'EBookReaderPage');
    this.syncTextReadAloudUiFromController();
    this.readAloudController.refreshMediaSession();
    this.refreshCurrentEBookBookmarkState('on_page_show');
    this.syncDeviceOrientationLock('page_show');
    this.scheduleToolbarAutoHide('page_show');
    void this.refreshPageGuide('onPageShow');
  }

  private onAppBackgroundStateChanged(): void {
    if (this.appInBackground || !this.isPageVisible) {
      return;
    }
    this.scheduleFullscreenRestore('app_foreground', 80);
    this.tryShowQueuedInteractionHint('app_foreground', 260);
  }

  private getInteractionHintKey(settings: TextReaderSettings = this.textReaderSettings): string {
    const tapToTurnFlag = settings.tapToTurn ? '1' : '0';
    return `mode=${settings.readingMode}|direction=${settings.readingDirection}|tap=${tapToTurnFlag}`;
  }

  private getInteractionHintSeenSettingKey(hintKey: string): string {
    const encodedKey = encodeURIComponent(hintKey);
    return `${SettingKeys.TEXT_READER_INTERACTION_HINT_SEEN_PREFIX}${EBookReaderPage.INTERACTION_HINT_READER_SCOPE}_${encodedKey}`;
  }

  private hasSeenInteractionHint(hintKey: string): boolean {
    if (EBookReaderPage.hasShownInteractionHint && EBookReaderPage.lastShownInteractionHintKey === hintKey) {
      return true;
    }
    return this.settingsManager.getBoolean(this.getInteractionHintSeenSettingKey(hintKey), false);
  }

  private markInteractionHintSeen(hintKey: string): void {
    EBookReaderPage.lastShownInteractionHintKey = hintKey;
    EBookReaderPage.hasShownInteractionHint = true;
    if (this.settingsManager.getBoolean(this.getInteractionHintSeenSettingKey(hintKey), false)) {
      return;
    }
    void this.persistInteractionHintSeen(hintKey);
  }

  private async persistInteractionHintSeen(hintKey: string): Promise<void> {
    try {
      await this.settingsManager.setBoolean(this.getInteractionHintSeenSettingKey(hintKey), true);
      logger.debug(TAG, `已持久化文本阅读交互提示标记: key=${hintKey}`);
    } catch (error) {
      logger.warn(TAG, `保存文本阅读交互提示标记失败: ${String(error)}`);
    }
  }

  private queueInteractionHintIfNeeded(settings: TextReaderSettings = this.textReaderSettings): void {
    const nextKey = this.getInteractionHintKey(settings);
    if (!this.hasSeenInteractionHint(nextKey)) {
      this.pendingInteractionHintKey = nextKey;
      return;
    }
    this.pendingInteractionHintKey = '';
  }

  private canShowInteractionOverlay(): boolean {
    return this.isPageVisible &&
      this.isUsingTextReader() &&
      !this.isLoading &&
      !this.errorMessage &&
      this.textContent.length > 0 &&
      this.readerViewportWidth > 0 &&
      this.readerViewportHeight > 0 &&
      !this.hasReaderOverlayVisible();
  }

  private clearInteractionOverlayTimer(): void {
    if (this.interactionOverlayDismissTimer >= 0) {
      clearTimeout(this.interactionOverlayDismissTimer);
      this.interactionOverlayDismissTimer = -1;
    }
  }

  private hideInteractionOverlay(): void {
    this.clearInteractionOverlayTimer();
    this.showTextInteractionOverlay = false;
  }

  private tryShowQueuedInteractionHint(reason: string, delayMs: number = 0): void {
    const showOverlay = (): void => {
      if (!this.pendingInteractionHintKey || !this.canShowInteractionOverlay()) {
        return;
      }
      const shownHintKey = this.pendingInteractionHintKey;
      this.showTextInteractionOverlay = true;
      this.markInteractionHintSeen(shownHintKey);
      this.pendingInteractionHintKey = '';
      this.clearInteractionOverlayTimer();
      this.interactionOverlayDismissTimer = setTimeout(() => {
        this.hideInteractionOverlay();
      }, 6000);
      logger.info(TAG, `显示交互引导遮罩: 原因=${reason}, 标识=${shownHintKey}`);
    };

    if (delayMs > 0) {
      setTimeout(() => {
        showOverlay();
      }, delayMs);
      return;
    }
    showOverlay();
  }

  private resolveGuideHighlightRect(anchorId?: string, borderRadius: number = 18): GuideHighlightRect | null {
    if (!anchorId || anchorId.length <= 0) {
      return null;
    }
    try {
      return resolveGuideHighlightRectInRoot(this.getUIContext(), anchorId, borderRadius, 'guide_ebook_reader_root');
    } catch (error) {
      logger.warn(TAG, `获取电子书阅读器引导锚点失败: ${String(error)}`);
      return null;
    }
  }

  private async waitForGuideLayout(delayMs: number = EBookReaderPage.GUIDE_LAYOUT_STABILIZE_DELAY_MS): Promise<void> {
    await new Promise<void>((resolve) => {
      setTimeout(() => {
        resolve();
      }, delayMs);
    });
  }

  private async prepareGuidePresentation(anchorId?: string): Promise<void> {
    if (!anchorId || anchorId.length <= 0) {
      return;
    }
    let changed: boolean = false;
    this.clearToolbarAutoHideTimer();
    switch (anchorId) {
      case 'guide_ebook_reader_top_toolbar':
      case 'guide_ebook_reader_bottom_toolbar':
        changed = !this.showTopToolbar || !this.showBottomToolbar || this.showSettingsPanel ||
          this.showChapterList || this.showMoreMenu || this.showBookInfoDialog ||
          this.showFontSettingsPanel || this.showReadingOptionsPanel || this.showTextReaderSettings ||
          this.showReadAloudPanel || this.toolbarOpacity < 0.99;
        this.showSettingsPanel = false;
        this.showChapterList = false;
        this.chapterListOpacity = 0;
        this.showMoreMenu = false;
        this.showBookInfoDialog = false;
        this.showFontSettingsPanel = false;
        this.showReadingOptionsPanel = false;
        this.showTextReaderSettings = false;
        this.showReadAloudPanel = false;
        this.showTopToolbar = true;
        this.showBottomToolbar = true;
        this.toolbarOpacity = 1;
        break;
      case 'guide_ebook_reader_chapter_list':
        changed = this.showTopToolbar || this.showBottomToolbar || !this.showChapterList ||
          this.showSettingsPanel || this.showMoreMenu || this.showBookInfoDialog ||
          this.showFontSettingsPanel || this.showReadingOptionsPanel || this.showTextReaderSettings ||
          this.showReadAloudPanel || this.toolbarOpacity > 0.01 || this.chapterListOpacity < 0.99;
        this.showTopToolbar = false;
        this.showBottomToolbar = false;
        this.toolbarOpacity = 0;
        this.showSettingsPanel = false;
        this.showMoreMenu = false;
        this.showBookInfoDialog = false;
        this.showFontSettingsPanel = false;
        this.showReadingOptionsPanel = false;
        this.showTextReaderSettings = false;
        this.showReadAloudPanel = false;
        this.showChapterList = true;
        this.chapterListOpacity = 1;
        setTimeout(() => {
          try {
            const maxIndex = Math.max(0, (this.ebook?.chapters.length || 1) - 1);
            const safeIndex = Math.max(0, Math.min(this.currentChapterIndex, maxIndex));
            this.chapterListScroller.scrollToIndex(safeIndex, true, ScrollAlign.CENTER);
          } catch (error) {
            logger.warn(TAG, `引导滚动电子书目录失败: ${String(error)}`);
          }
        }, 60);
        break;
      default:
        changed = this.showTopToolbar || this.showBottomToolbar || this.showSettingsPanel ||
          this.showChapterList || this.showMoreMenu || this.showBookInfoDialog ||
          this.showFontSettingsPanel || this.showReadingOptionsPanel || this.showTextReaderSettings ||
          this.showReadAloudPanel || this.toolbarOpacity > 0.01 || this.chapterListOpacity > 0.01;
        this.showTopToolbar = false;
        this.showBottomToolbar = false;
        this.toolbarOpacity = 0;
        this.showSettingsPanel = false;
        this.showChapterList = false;
        this.chapterListOpacity = 0;
        this.showMoreMenu = false;
        this.showBookInfoDialog = false;
        this.showFontSettingsPanel = false;
        this.showReadingOptionsPanel = false;
        this.showTextReaderSettings = false;
        this.showReadAloudPanel = false;
        break;
    }
    if (changed) {
      await this.waitForGuideLayout();
    }
  }

  private async refreshPageGuide(trigger: string): Promise<void> {
    await this.appGuideManager.initialize();
    if (!this.appGuideManager.getCurrentStep()) {
      await this.appGuideManager.tryAutoStartFlowByPage(AppGuidePageId.EBOOK_READER);
    }
    const step = this.appGuideManager.getCurrentStep();
    if (!step || step.pageId !== AppGuidePageId.EBOOK_READER) {
      this.appGuideStep = null;
      this.appGuideHighlightRect = null;
      return;
    }
    await this.prepareGuidePresentation(step.anchorId);
    this.appGuideStep = step;
    this.appGuideHighlightRect = this.resolveGuideHighlightRect(step.anchorId, step.borderRadius ?? 18);
    if (!this.appGuideHighlightRect && trigger !== 'retry_layout') {
      setTimeout(() => {
        void this.refreshPageGuide('retry_layout');
      }, 120);
    }
    logger.debug(TAG, `电子书阅读器引导已刷新: 触发源=${trigger}, 步骤=${step.id}`);
  }

  private handlePageGuideNext(): void {
    void this.appGuideManager.nextStep().then(() => {
      void this.refreshPageGuide('next');
    });
  }

  private handlePageGuideSkip(): void {
    void this.appGuideManager.skipCurrentFlow().then(() => {
      void this.refreshPageGuide('skip');
    });
  }

  onPageHide(): void {
    this.isPageVisible = false;
    this.clearToolbarAutoHideTimer();
    this.clearFullscreenRestoreTimer();
    this.hideInteractionOverlay();
    const isOpeningReadAloudPlayer = this.isReadAloudPlayerOpeningSoon();
    if (isOpeningReadAloudPlayer) {
      logger.info(TAG, '电子书阅读器进入听书独立页，保留当前沉浸模式');
    }
    logger.lifecycle(TAG, '电子书阅读器页面隐藏（进入后台）');
    this.readAloudController.handlePageHide();
    this.textReadAloudPlaying = this.readAloudController.getSnapshot().playbackState === ReadAloudPlaybackState.PLAYING;
    // 立即保存阅读进度，确保 Home → 杀进程场景下进度不丢失
    this.accumulateReadingTime();
    // 立即保存阅读进度，确保 Home → 杀进程场景下进度不丢失
    this.saveReadingProgress();
  }

  /**
  * 开始阅读时间追踪
  * 使用定时器每1秒累加一次阅读时间
  */
  private startReadingTimeTracking(): void {
    this.readingSessionStartTime = Date.now();
    this.accumulatedReadingTime = 0;
    
    // 每1秒累加一次阅读时间
    if (this.readingTimeTimer !== -1) {
      clearInterval(this.readingTimeTimer);
    }
    
    // 每1秒累加一次阅读时间
    this.readingTimeTimer = setInterval(() => {
      this.accumulateReadingTime();
    }, EBookReaderPage.READING_TIME_INTERVAL);
    
    logger.info(TAG, '电子书阅读页初始化完成');
  }

  /**
  * 停止阅读时间追踪
  */
  private stopReadingTimeTracking(): void {
    // 清除定时器
    this.accumulateReadingTime();
    
    // 清除定时器
    if (this.readingTimeTimer !== -1) {
      clearInterval(this.readingTimeTimer);
      this.readingTimeTimer = -1;
    }
    
    logger.info(TAG, `阅读时间追踪已停止，本次累计: ${this.accumulatedReadingTime.toFixed(2)} 分钟`);
  }

  /**
  * 累加阅读时间
  */
  private accumulateReadingTime(): void {
    const now = Date.now();
    const elapsed = now - this.readingSessionStartTime;
    // 重置会话开始时间
    const elapsedMinutes = elapsed / 1000 / 60;
    this.accumulatedReadingTime += elapsedMinutes;
    // 重置会话开始时间
    this.readingSessionStartTime = now;
    
    logger.debug(TAG, `累加阅读时间: +${elapsedMinutes.toFixed(2)} 分钟，总计: ${this.accumulatedReadingTime.toFixed(2)} 分钟`);
  }

  /**
  * 注册音量键翻页监听
  * 使用 inputConsumer API 拦截音量键事件，防止系统调整音量
  */
  private registerVolumeKeyListener(): void {
    if (this.isVolumeKeyListenerRegistered) {
      logger.debug(TAG, '音量键监听已注册，跳过重复注册');
      return;
    }

    // 检查是否启用了音量键翻页（默认启用）
    const volumeKeyEnabled = this.textReaderSettings.volumeKeyNavigation ?? true;
    if (!volumeKeyEnabled) {
      logger.info(TAG, '音量键翻页未启用，不注册监听');
      return;
    }

    try {
      // 音量下键配置
      const volumeUpConfig: inputConsumer.KeyPressedConfig = {
        key: KeyCode.KEYCODE_VOLUME_UP,
        action: 1,// 按下按键的行为
        isRepeat: false// 不重复触发
      };

      // 音量上键回调 - 上一页
      const volumeDownConfig: inputConsumer.KeyPressedConfig = {
        key: KeyCode.KEYCODE_VOLUME_DOWN,
        action: 1,
        isRepeat: false
      };

        // 只在 TXT 格式时处理
      this.volumeUpCallback = (_event: InputKeyEvent) => {
        logger.info(TAG, '音量键翻页: 上一页 (inputConsumer)');
        // 只在 TXT 格式时处理
        if (!this.isUsingTextReader()) {
          this.handleVolumeKeyPageTurn(KeyCode.KEYCODE_VOLUME_UP);
        }
      };

        // 只在 TXT 格式时处理
      this.volumeDownCallback = (_event: InputKeyEvent) => {
        logger.info(TAG, '音量键翻页: 下一页 (inputConsumer)');
      // 注册监听
        if (!this.isUsingTextReader()) {
          this.handleVolumeKeyPageTurn(KeyCode.KEYCODE_VOLUME_DOWN);
        }
      };

      // 注册监听
      inputConsumer.on('keyPressed', volumeUpConfig, this.volumeUpCallback);
      inputConsumer.on('keyPressed', volumeDownConfig, this.volumeDownCallback);

      this.isVolumeKeyListenerRegistered = true;
      logger.info(TAG, '✅ 音量键翻页监听已注册');
    } catch (error) {
      logger.error(TAG, `注册音量键监听失败: ${JSON.stringify(error)}`);
    }
  }

  /**
  * 注销音量键翻页监听
  */
  private unregisterVolumeKeyListener(): void {
    if (!this.isVolumeKeyListenerRegistered) {
      return;
    }

    try {
      if (this.volumeUpCallback) {
        inputConsumer.off('keyPressed', this.volumeUpCallback);
        this.volumeUpCallback = null;
      }
      if (this.volumeDownCallback) {
        inputConsumer.off('keyPressed', this.volumeDownCallback);
        this.volumeDownCallback = null;
      }

      this.isVolumeKeyListenerRegistered = false;
      logger.info(TAG, '✅ 音量键翻页监听已注销');
    } catch (error) {
      logger.error(TAG, `注销音量键监听失败: ${JSON.stringify(error)}`);
    }
  }

  /**
  * 更新音量键监听状态（根据设置启用/禁用）
  */
  private updateVolumeKeyListener(): void {
    if (this.isUsingTextReader()) {
      if (this.isVolumeKeyListenerRegistered) {
        this.unregisterVolumeKeyListener();
      }
      return;
    }

    const volumeKeyEnabled = this.textReaderSettings.volumeKeyNavigation ?? true;
    
    if (volumeKeyEnabled && !this.isVolumeKeyListenerRegistered) {
      this.registerVolumeKeyListener();
    } else if (!volumeKeyEnabled && this.isVolumeKeyListenerRegistered) {
      this.unregisterVolumeKeyListener();
    }
  }

  /**
  * 设置完全沉浸式模式
  */
  private setupFullscreenMode(): void {
    try {
      if (!this.uiContext) {
        this.uiContext = this.getUIContext();
      }
      if (!this.uiContext) {
        logger.error(TAG, '进入沉浸模式失败：UIContext 为空');
        return;
      }
      
      const currentMode = WindowManager.getCurrentMode();
      if (currentMode !== DisplayMode.FULL_IMMERSIVE) {
        this.previousDisplayMode = currentMode;
      }
      WindowManager.setDisplayModeWithTransition(DisplayMode.FULL_IMMERSIVE, this.uiContext);
      if (this.isHostedByIsolatedReaderAbility()) {
        PageWindowCoordinator.reapplyPagePolicy('EBookReaderPage', this.uiContext);
        WindowManager.setDisplayMode(DisplayMode.FULL_IMMERSIVE, this.uiContext);
      }
      logger.info(TAG, '已进入全沉浸模式');
    } catch (error) {
      logger.error(TAG, `设置全屏模式失败: ${String(error)}`);
    }
  }

  /**
  * 恢复正常显示模式
  */
  private restoreNormalMode(): void {
    try {
      if (!this.uiContext) {
        this.uiContext = this.getUIContext();
      }
      if (!this.uiContext) {
        logger.error(TAG, '退出沉浸模式失败：UIContext 为空');
        return;
      }
      
      const targetMode = this.previousDisplayMode === DisplayMode.FULL_IMMERSIVE
        ? DisplayMode.DEFAULT
        : this.previousDisplayMode;
      if (WindowManager.getCurrentMode() === targetMode) {
        WindowManager.reapplyCurrentDisplayMode(180);
        return;
      }
      WindowManager.setDisplayMode(targetMode, this.uiContext);
      WindowManager.reapplyCurrentDisplayMode(180);
      logger.info(TAG, `恢复显示模式: ${targetMode}`);
    } catch (error) {
      logger.error(TAG, `恢复正常模式失败: ${String(error)}`);
    }
  }

  private isReadAloudPlayerOpeningSoon(): boolean {
    const openingAt = AppStorage.get<number>('ReadAloudPlayerOpeningAt') ?? 0;
    if (openingAt <= 0) {
      return false;
    }
    return Math.abs(Date.now() - openingAt) <= 2000;
  }

  private shouldHandleReadAloudUiEvents(): boolean {
    if (!this.isPageVisible) {
      return false;
    }
    const currentHostPage = (AppStorage.get<string>('ReadAloudCurrentHostPage') ?? '').trim();
    return currentHostPage === 'EBookReaderPage';
  }

  private isKindleFormat(format: EBookFormat): boolean {
    return format === EBookFormat.MOBI || format === EBookFormat.AZW || format === EBookFormat.AZW3;
  }

  private shouldRedirectKindleToWebViewReader(ebook: EBook): boolean {
    return !this.forceReaderKit && this.isKindleFormat(ebook.format);
  }

  private replaceKindleWithWebViewReader(ebook: EBook): void {
    const params: EBookReaderParams = {
      bookId: ebook.id,
      coverComponentId: this.sourceCoverComponentId,
      routerBackOnClose: this.routerBackOnClose,
      readerHostMode: this.readerHostMode,
      readerInstanceId: this.readerInstanceId,
      readerTitle: ebook.metadata.title
    };
    logger.info(
      TAG,
      `Kindle 电子书进入旧阅读页，已切换到 WebView 阅读器: bookId=${ebook.id}, format=${ebook.format}, engine=${ebook.preferredReaderEngine}, extractedRootPath=${ebook.extractedRootPath || ''}`
    );
    try {
      this.pathStack.replacePathByName('EpubWebViewReaderPage', params, false);
    } catch (error) {
      logger.error(TAG, `切换到 WebView 阅读器失败: ${String(error)}`);
      this.errorMessage = 'Kindle 格式请使用新版 WebView 阅读器打开';
      this.isLoading = false;
    }
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
      logger.debug(TAG, `过渡动画就绪已通知，忽略重复触发: ${reason}`);
      return;
    }
    this.hasNotifiedTransitionReaderReady = true;
    this.reportTransitionLoadingProgress(1, `ready_${reason}`);
    setReaderReady();
    logger.info(TAG, `📤 已通知过渡动画阅读器就绪: ${reason}`);
  }

  /**
  * 加载电子书
  */
  private isUnknownAuthorValue(author: string): boolean {
    const normalized = author.trim();
    return normalized.length <= 0 || normalized === '未知作者' || normalized.toLowerCase() === 'unknown author';
  }

  private isGenericDescriptionValue(description: string): boolean {
    const normalized = description.trim();
    return normalized.length <= 0 || normalized.includes('格式电子书');
  }

  private shouldRepairReaderKitBookData(ebook: EBook): boolean {
    if (this.forceReaderKit) {
      return false;
    }
    if (!this.isReaderKitSupported(ebook.format)) {
      return false;
    }
    if (ebook.contentMode === EBookContentMode.IMAGE_PAGE) {
      const missingImagePath = ebook.chapters.some((chapter: EBookChapter) => {
        return ((chapter.resourceImagePath || '').length <= 0) && ((chapter.resourceImageRelativePath || '').length <= 0);
      });
      if (!missingImagePath) {
        return false;
      }
    }
    const chapterCount = ebook.chapters?.length || 0;
    return chapterCount <= 1 ||
      ebook.contentMode === EBookContentMode.UNKNOWN ||
      this.isUnknownAuthorValue(ebook.metadata.author || '') ||
      this.isGenericDescriptionValue(ebook.metadata.description || '');
  }

  private buildReparsedChapterList(reparsed: EBook, targetBookId: string): EBookChapter[] {
    const now = Date.now();
    return reparsed.chapters.map((chapter: EBookChapter, index: number) => {
      const chapterTitle = chapter.title && chapter.title.trim().length > 0 ? chapter.title : `第${index + 1}章`;
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

    if ((!current.title || current.title.trim().length <= 0 || /^\d+_/.test(current.title)) && incoming.title && incoming.title.trim().length > 0) {
      current.title = incoming.title;
      changed = true;
    }
    if (this.isUnknownAuthorValue(current.author || '') && incoming.author && !this.isUnknownAuthorValue(incoming.author)) {
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
    if (this.isGenericDescriptionValue(current.description || '') && incoming.description && !this.isGenericDescriptionValue(incoming.description)) {
      current.description = incoming.description;
      changed = true;
    }
    if ((!current.coverImagePath || current.coverImagePath.trim().length <= 0) && incoming.coverImagePath && incoming.coverImagePath.trim().length > 0) {
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

  private async tryRepairReaderKitBookData(ebook: EBook): Promise<void> {
    if (!this.shouldRepairReaderKitBookData(ebook)) {
      return;
    }
    try {
      logger.info(TAG, `检测到电子书解析数据可能不完整，尝试修复: ${ebook.id}`);
      const parser = EBookParserFactory.createParser(ebook.filePath);
      if (!parser) {
        logger.warn(TAG, `修复失败：无法为文件创建解析器: ${ebook.filePath}`);
        return;
      }
      const reparsed = await parser.parse();
      let changed = false;
      const oldChapterCount = ebook.chapters?.length || 0;
      const currentHasImagePath = ebook.chapters.some((chapter: EBookChapter) => {
        return ((chapter.resourceImagePath || '').length > 0) || ((chapter.resourceImageRelativePath || '').length > 0);
      });
      const reparsedHasImagePath = reparsed.chapters.some((chapter: EBookChapter) => {
        return ((chapter.resourceImagePath || '').length > 0) || ((chapter.resourceImageRelativePath || '').length > 0);
      });
      if ((oldChapterCount <= 1 && reparsed.chapters.length > 1) ||
        (reparsedHasImagePath && !currentHasImagePath) ||
        (ebook.contentMode === EBookContentMode.UNKNOWN && reparsed.contentMode !== EBookContentMode.UNKNOWN)) {
        ebook.chapters = this.buildReparsedChapterList(reparsed, ebook.id);
        changed = true;
        logger.info(TAG, `修复目录成功: ${oldChapterCount} -> ${ebook.chapters.length}`);
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
          const safeIndex = Math.max(0, Math.min(ebook.readingProgress.currentChapterIndex, ebook.chapters.length - 1));
          ebook.readingProgress.currentChapterId = ebook.chapters[safeIndex].id;
        }
        await this.ebookDataManager.saveEBook(ebook, { skipReadingSettings: true });
        logger.info(TAG, `电子书解析数据修复完成: ${ebook.metadata.title}`);
      } else {
        logger.info(TAG, `电子书解析数据无需更新: ${ebook.id}`);
      }
    } catch (error) {
      logger.warn(TAG, `修复电子书解析数据失败: ${String(error)}`);
    }
  }

  private clearToolbarAutoHideTimer(): void {
    if (this.toolbarAutoHideTimer >= 0) {
      clearTimeout(this.toolbarAutoHideTimer);
      this.toolbarAutoHideTimer = -1;
    }
  }

  private hasReaderOverlayVisible(): boolean {
    return this.showSettingsPanel ||
      this.showChapterList ||
      this.showMoreMenu ||
      this.showBookInfoDialog ||
      this.showFontSettingsPanel ||
      this.showReadingOptionsPanel ||
      this.showTextReaderSettings ||
      this.showReadAloudPanel;
  }

  private scheduleToolbarAutoHide(reason: string): void {
    this.clearToolbarAutoHideTimer();
    if (!this.showTopToolbar && !this.showBottomToolbar) {
      return;
    }
    if (this.hasReaderOverlayVisible()) {
      return;
    }
    this.toolbarAutoHideTimer = setTimeout(() => {
      this.toolbarAutoHideTimer = -1;
      if (this.hasReaderOverlayVisible()) {
        return;
      }
      if (this.showTopToolbar || this.showBottomToolbar) {
        logger.debug(TAG, `工具栏自动隐藏: 原因=${reason}`);
        this.hideToolbarWithAnimation();
      }
    }, EBookReaderPage.TOOLBAR_AUTO_HIDE_DELAY_MS);
  }

  private clearFullscreenRestoreTimer(): void {
    if (this.fullscreenRestoreTimer >= 0) {
      clearTimeout(this.fullscreenRestoreTimer);
      this.fullscreenRestoreTimer = -1;
    }
  }

  private captureToolbarSafeArea(_reason: string): void {
    const nextHeight = this.statusBarHeight > 0
      ? this.statusBarHeight
      : ReaderSafeAreaUtils.DEFAULT_STATUS_BAR_INSET;
    if (Math.abs(this.stableToolbarStatusBarHeight - nextHeight) > 0.5) {
      this.stableToolbarStatusBarHeight = nextHeight;
    }
  }

  private getToolbarStatusBarHeight(): number {
    return this.stableToolbarStatusBarHeight > 0
      ? this.stableToolbarStatusBarHeight
      : this.statusBarHeight;
  }

  private getStableTopToolbarHeight(): number {
    return ReaderSafeAreaUtils.getTopToolbarHeight(this.getToolbarStatusBarHeight());
  }

  private getStableTopToolbarInset(): number {
    return ReaderSafeAreaUtils.getStatusBarInset(this.getToolbarStatusBarHeight());
  }

  private handleReaderOverlayOpening(reason: string): void {
    this.captureToolbarSafeArea(reason);
    this.clearToolbarAutoHideTimer();
    this.clearFullscreenRestoreTimer();
  }

  private scheduleFullscreenRestore(reason: string, delayMs: number = 120): void {
    this.clearFullscreenRestoreTimer();
    this.fullscreenRestoreTimer = setTimeout(() => {
      this.fullscreenRestoreTimer = -1;
      logger.debug(TAG, `重新应用沉浸模式: 原因=${reason}`);
      if (this.isHostedByIsolatedReaderAbility()) {
        PageWindowCoordinator.reapplyPagePolicy('EBookReaderPage', this.uiContext ?? undefined);
      }
      WindowManager.setDisplayMode(DisplayMode.FULL_IMMERSIVE, this.uiContext ?? undefined);
      WindowManager.reapplyCurrentDisplayMode(24);
      if (this.showTopToolbar || this.showBottomToolbar) {
        this.scheduleToolbarAutoHide(`fullscreen_restore_${reason}`);
      }
    }, delayMs);
  }

  private handleReaderOverlayClosed(reason: string): void {
    this.clearFullscreenRestoreTimer();
    this.scheduleToolbarAutoHide(reason);
    this.tryShowQueuedInteractionHint(reason, 220);
  }

  private async loadEBook(bookId: string): Promise<void> {
    try {
      this.hasNotifiedTransitionReaderReady = false;
      this.transitionLoadingProgress = 0;
      this.isLoading = true;
      this.errorMessage = '';
      this.isCurrentPageBookmarked = false;
      this.currentPageBookmarkId = '';
      this.imagePageChapterTick = 0;
      this.clearReaderKitStartupGuard('load_start');
      this.reportTransitionLoadingProgress(0.06, 'load_start');

      logger.info(TAG, `开始加载电子书: ${bookId}`);
      
      // 从数据库加载电子书
      const ebook = await this.ebookDataManager.getEBookById(bookId);
      
      if (!ebook) {
        throw new Error('电子书不存在');
      }

      if (this.shouldRedirectKindleToWebViewReader(ebook)) {
        this.replaceKindleWithWebViewReader(ebook);
        return;
      }

      await this.tryRepairReaderKitBookData(ebook);
      this.ebook = ebook;
      this.reportTransitionLoadingProgress(0.24, 'ebook_loaded');
      if (this.isUsingMarkdownReader()) {
        this.markdownChapterProgress = 0;
        this.markdownOverallProgress = 0;
        this.markdownCurrentPage = 1;
        this.markdownPageCount = 1;
        this.pendingMarkdownRestoreProgress = 0;
        this.currentDomPos = '';
      }
      
      if (ebook.format !== EBookFormat.TXT) {
        const effectiveSettings = await this.ebookDataManager.resolveEffectiveEBookReadingSettings(
          ebook.id,
          ebook.readingSettings
        );
        ebook.readingSettings = effectiveSettings;
        if (ebook.readingSettings.followSystemTheme !== false) {
          this.applySystemThemeToSettings(ebook);
        }
        this.fontSize = ebook.readingSettings.fontSize;
        this.lineHeight = ebook.readingSettings.lineHeight;
        this.bgColor = ebook.readingSettings.backgroundColor;
        this.textColor = ebook.readingSettings.textColor;
        this.pageMargin = ebook.readingSettings.pageMargin;
        logger.info(
          TAG,
          `恢复电子书阅读设置: fontSize=${this.fontSize}, lineHeight=${this.lineHeight}, pageMargin=${this.pageMargin}, followSystemTheme=${ebook.readingSettings.followSystemTheme}`
        );
      }

        // 优先使用保存的章节索引
      this.syncImagePageReaderSettings();
      if (ebook.readingProgress) {
          // 兼容旧数据：通过章节ID查找索引
        if (typeof ebook.readingProgress.currentChapterIndex === 'number' && ebook.readingProgress.currentChapterIndex >= 0) {
          this.currentChapterIndex = ebook.readingProgress.currentChapterIndex;
          logger.info(TAG, `恢复阅读位置: 章节索引=${this.currentChapterIndex}`);
        } else if (ebook.readingProgress.currentChapterId) {
          // 兼容旧数据：通过章节ID查找索引
          const chapterIndex = ebook.chapters.findIndex(
            (ch: EBookChapter) => ch.id === ebook.readingProgress.currentChapterId
          );
          if (chapterIndex >= 0) {
            this.currentChapterIndex = chapterIndex;
          logger.info(TAG, `恢复 DOM 位置: ${this.currentDomPos}`);
          }
        }
        
        // 备用：从 currentPosition 恢复页码
        if (ebook.readingProgress.domPos) {
          this.currentDomPos = ebook.readingProgress.domPos;
          logger.info(TAG, `从 currentPosition 恢复页码: ${this.textCurrentPageIndex}`);
          if (this.isUsingTextReader()) {
            this.restoreTextReadAloudFromDomPos(ebook.readingProgress.domPos);
          } else if (this.isUsingMarkdownReader()) {
            this.restoreMarkdownProgressFromDomPos(ebook.readingProgress.domPos);
          }
        }
        
      // 加载当前章节
        if (this.isUsingTextReader() && this.textCurrentPageIndex === 0 && ebook.readingProgress.currentPosition > 0) {
          this.textCurrentPageIndex = ebook.readingProgress.currentPosition;
          logger.info(TAG, `从 currentPosition 恢复页码: ${this.textCurrentPageIndex}`);
        }
        this.initReaderKitStartupGuard(ebook.readingProgress.currentPosition);
      } else {
        this.clearReaderKitStartupGuard('no_saved_progress');
      }

      // [修复] 跨端接续：在本地进度恢复后，用源端快照位置覆盖（wantParam 优先）
      this.applyPendingEBookContinuation();

      // [修复] 内容就绪后立即同步一次阅读进度（确保 currentRead* 状态与时间戳就绪，
      // 避免进入阅读器早期触发接续时守卫误判或打包空状态）
      distributedReadingService.syncProgress(ebook.id, this.currentChapterIndex, this.textCurrentPageIndex, 0, 'ebook');

      // 调试日志：检查章节内容
      this.reportTransitionLoadingProgress(0.48, 'settings_restored');
      if (!this.isUsingTextReader()) {
        this.syncDeviceOrientationLock('ebook_settings_loaded');
      }
      const chapterCount = ebook.chapters?.length || 0;
      if (chapterCount <= 0) {
        throw new Error('电子书中没有可用章节');
      }
      const safeChapterIndex = Math.max(0, Math.min(this.currentChapterIndex, chapterCount - 1));
      if (safeChapterIndex !== this.currentChapterIndex) {
        logger.warn(TAG, `恢复阅读位置越界，已修正: originalIndex=${this.currentChapterIndex}, safeIndex=${safeChapterIndex}, chapterCount=${chapterCount}`);
        this.currentChapterIndex = safeChapterIndex;
      }
      this.currentChapter = ebook.chapters[this.currentChapterIndex] || ebook.chapters[0];
      if (!this.currentChapter) {
        throw new Error(`无法定位章节，索引=${this.currentChapterIndex}`);
      }
      this.updateImagePagePreloadDebugInfo();
      
      // 调试日志：检查章节内容
        logger.info(TAG, `当前章节内容前100字: ${this.currentChapter.content?.substring(0, 100) || '(空)'}`);
      if (this.currentChapter) {
        logger.info(TAG, `当前章节内容前100字: ${this.currentChapter.content?.substring(0, 100) || '(空)'}`);
        logger.info(TAG, `当前章节内容前100字: ${this.currentChapter.content?.substring(0, 100) || '(空)'}`);
        logger.info(TAG, `当前章节内容前100字: ${this.currentChapter.content?.substring(0, 100) || '(空)'}`);
      } else {
        logger.warn(TAG, '当前章节为空');
      }

      // 初始化文本内容（用于纯文本阅读器）
      if (this.isUsingTextReader()) {
        this.loadTextReaderSettingsWithGlobalDefaults(ebook);
      }
      
      // 初始化文本内容（用于文本阅读器）
      if (this.isUsingTextReader()) {
        this.textContent = this.getTextContent();
        logger.info(TAG, `电子书加载完成: ${ebook.metadata.title}`);
        this.syncTextReadAloudContext();
      } else if (this.isUsingMarkdownReader()) {
        this.markdownContent = this.getTextContent();
        this.markdownOverallProgress = this.calculateMarkdownOverallProgress(this.markdownChapterProgress);
        logger.info(TAG, `Markdown 电子书加载完成: ${ebook.metadata.title}, contentLength=${this.markdownContent.length}`);
      }

      this.reportTransitionLoadingProgress(0.72, 'reader_data_prepared');
      this.isLoading = false;
      this.reportTransitionLoadingProgress(0.84, 'reader_view_shown');
      logger.info(TAG, '📤 已进入阅读器就绪等待阶段，等待具体组件回调');
      
      // ReaderKit占位: buildReaderKitView.onAppear
      // TXT: TextReaderComponent.onReady
      // PDF: PdfKitViewerComponent.onLoadComplete/onLoadError
      // 设置沉浸式模式
      logger.info(TAG, 'ReaderKit 视图已出现，开始加载章节内容');
      
      // 设置沉浸式模式
      this.setupFullscreenMode();
      this.refreshCurrentEBookBookmarkState('load_ebook_success');
      
    } catch (error) {
      this.errorMessage = `加载章节失败: ${String(error instanceof Error ? error.message : error)}`;
      this.isLoading = false;
      this.isCurrentPageBookmarked = false;
      this.currentPageBookmarkId = '';
      logger.error(TAG, '加载章节内容失败', String(error instanceof Error ? error.message : error));
      this.notifyTransitionReaderReadyOnce('ebook_load_failed');
    }
  }

  /**
   * [修复] 跨端接续恢复：在本地进度恢复后应用源端快照位置
   * 源端 syncProgress 打包的 chapterIndex 即阅读器 currentChapterIndex（图片模式为页），
   * pageIndex 即 currentPosition / 文本页码，语义自洽可直接回放。
   */
  private applyPendingEBookContinuation(): void {
    if (this.pendingContinuationChapterIndex < 0) {
      // [日志完善] 无待应用接续状态（无接续会话或快照已消费），记录以确认恢复链路是否进入
      logger.debug(TAG, '[Distributed] 接续恢复: 无待应用快照（跳过），pendingChapterIndex=-1');
      this.clearPendingEBookContinuation();
      return;
    }
    const chapterCount = this.ebook?.chapters?.length || 0;
    const safeChapterIndex = chapterCount > 0
      ? Math.max(0, Math.min(this.pendingContinuationChapterIndex, chapterCount - 1))
      : this.pendingContinuationChapterIndex;
    this.currentChapterIndex = safeChapterIndex;
    // 文本阅读器：页码语义一致，直接回放
    if (this.isUsingTextReader() && this.pendingContinuationPageIndex >= 0) {
      this.textCurrentPageIndex = this.pendingContinuationPageIndex;
    }
    this.getUIContext().getPromptAction().showToast({ message: '已从其他设备接续阅读' });
    logger.info(TAG, `[Distributed] 接续阅读命中(快照): chapterIndex=${safeChapterIndex}, pageIndex=${this.pendingContinuationPageIndex}`);
    this.clearPendingEBookContinuation();
  }

  /**
   * [修复] 跨端接续兜底：wantParam 快照缺失时，等待分布式数据对象把源端进度同步过来
   */
  private async tryRestoreEBookFromDistributedObject(): Promise<void> {
    const distributedState = await distributedDataSyncManager.waitForRemoteState(4000);
    if (distributedState && distributedState.bookId.length > 0) {
      if (this.ebook && distributedState.bookId === this.ebook.id) {
        if (distributedState.chapterIndex >= 0) {
          const chapterCount = this.ebook.chapters?.length || 0;
          this.currentChapterIndex = chapterCount > 0
            ? Math.max(0, Math.min(distributedState.chapterIndex, chapterCount - 1))
            : distributedState.chapterIndex;
          if (this.isUsingTextReader() && distributedState.pageIndex >= 0) {
            this.textCurrentPageIndex = distributedState.pageIndex;
          }
          this.getUIContext().getPromptAction().showToast({ message: '已从其他设备接续阅读' });
          logger.info(TAG, `[Distributed] 接续阅读命中(分布式对象): chapterIndex=${distributedState.chapterIndex}, pageIndex=${distributedState.pageIndex}`);
        }
      } else if (!this.ebook) {
        // 电子书尚未加载完成：存入待应用状态，由 loadEBook 恢复段应用
        this.pendingContinuationChapterIndex = distributedState.chapterIndex;
        this.pendingContinuationPageIndex = distributedState.pageIndex;
        logger.info(TAG, `[Distributed] 分布式对象状态存入待应用: chapterIndex=${distributedState.chapterIndex}, pageIndex=${distributedState.pageIndex}`);
        return;
      } else {
        logger.warn(TAG, `[Distributed] 分布式对象 bookId 不匹配: remote=${distributedState.bookId}, local=${this.ebook.id}`);
      }
    } else {
      logger.warn(TAG, '[Distributed] 电子书接续恢复未命中（分布式对象未同步到数据）');
    }
    this.clearPendingEBookContinuation();
  }

  private clearPendingEBookContinuation(): void {
    this.pendingContinuationChapterIndex = -1;
    this.pendingContinuationPageIndex = -1;
    // 无论是否命中都清理接续标志，防止残留导致后续误触发
    distributedReadingService.clearContinuationFlags();
  }

  /**
  * 加载纯文本阅读器设置（带全局默认设置支持）
  * 用于 TXT 格式电子书，优先使用全局设置，除非用户已修改
  */
  private loadTextReaderSettingsWithGlobalDefaults(ebook: EBook): void {
    const settingsManager: ISettingsManagerFacade = SettingsManagerHolder.get();
    
    // 获取全局纯文本阅读器设置
    const globalFontSize = clampTextReaderFontSize(settingsManager.getNumber(SettingKeys.GLOBAL_TEXT_FONT_SIZE, DEFAULT_TEXT_READER_SETTINGS.textStyle.fontSize));
    const globalFontFamily = settingsManager.getString(SettingKeys.GLOBAL_TEXT_FONT_FAMILY, DEFAULT_TEXT_READER_SETTINGS.textStyle.fontFamily);
    const globalFontWeight = settingsManager.getNumber(SettingKeys.GLOBAL_TEXT_FONT_WEIGHT, DEFAULT_TEXT_READER_SETTINGS.textStyle.fontWeight);
    const globalLineHeight = settingsManager.getNumber(SettingKeys.GLOBAL_TEXT_LINE_HEIGHT, DEFAULT_TEXT_READER_SETTINGS.textStyle.lineHeight);
    const globalParagraphSpacing = settingsManager.getNumber(SettingKeys.GLOBAL_TEXT_PARAGRAPH_SPACING, DEFAULT_TEXT_READER_SETTINGS.textStyle.paragraphSpacing);
    const globalFirstLineIndent = settingsManager.getNumber(SettingKeys.GLOBAL_TEXT_FIRST_LINE_INDENT, DEFAULT_TEXT_READER_SETTINGS.textStyle.firstLineIndent);
    const globalPageMargin = settingsManager.getNumber(SettingKeys.GLOBAL_TEXT_PAGE_MARGIN, DEFAULT_TEXT_READER_SETTINGS.pageMargins.left);
    const globalBgColorIndex = settingsManager.getNumber(SettingKeys.GLOBAL_TEXT_BG_COLOR, 0);
    const globalUseBgImage = settingsManager.getBoolean(SettingKeys.GLOBAL_TEXT_USE_BG_IMAGE, false);
    const globalBgImagePath = settingsManager.getString(SettingKeys.GLOBAL_TEXT_BG_IMAGE_PATH, '');
    const globalBgImageOpacity = settingsManager.getNumber(SettingKeys.GLOBAL_TEXT_BG_IMAGE_OPACITY, 0.3);
    const globalPageTurnAnimation = settingsManager.getString(SettingKeys.GLOBAL_TEXT_PAGE_TURN_ANIMATION, TextPageTurnAnimation.SLIDE) as TextPageTurnAnimation;
    const globalKeepScreenOn = settingsManager.getBoolean(SettingKeys.GLOBAL_TEXT_KEEP_SCREEN_ON, true);
    const globalLockDeviceOrientation = settingsManager.getBoolean(
      SettingKeys.GLOBAL_TEXT_LOCK_DEVICE_ORIENTATION,
      DEFAULT_TEXT_READER_SETTINGS.lockDeviceOrientation ?? false
    );
    const globalVolumeKeyNav = settingsManager.getBoolean(SettingKeys.GLOBAL_TEXT_VOLUME_KEY_NAV, true);
    const globalTapToTurn = settingsManager.getBoolean(SettingKeys.GLOBAL_TEXT_TAP_TO_TURN, true);
    
      // [修复] 简化判断逻辑：只依赖 followSystemTheme 标志
    const globalBgPreset = PRESET_BACKGROUNDS[globalBgColorIndex] || PRESET_BACKGROUNDS[0];
    
    if (ebook.readingSettings) {
      // followSystemTheme=false 表示用户已自定义设置，应使用保存的设置
        // 使用全局设置
        // 使用全局设置
      const isDefaultSettings = ebook.readingSettings.followSystemTheme === true;
      
      if (isDefaultSettings) {
        // [修复] 应用全局设置后，设置 followSystemTheme=false，表示已初始化，下次使用保存的设置
        logger.info(TAG, `纯文本阅读器检测到默认设置，应用全局设置: 字体大小=${globalFontSize}, 字体=${globalFontFamily}, 背景色=${globalBgPreset.backgroundColor}`);
        this.loadTextReaderSettingsFromGlobal(globalFontSize, globalFontFamily, globalFontWeight, globalLineHeight, globalParagraphSpacing, 
          globalFirstLineIndent, globalPageMargin, globalBgPreset, globalUseBgImage, globalBgImagePath, 
          globalBgImageOpacity, globalPageTurnAnimation, globalKeepScreenOn, globalLockDeviceOrientation,
          globalVolumeKeyNav, globalTapToTurn);
        // 用户已修改过设置，使用保存的设置
        ebook.readingSettings.followSystemTheme = false;
        // 用户已修改过设置，使用保存的设置
        this.queueTextReaderSettingsSave();
      } else {
      // 没有保存的设置，使用全局设置
      logger.info(TAG, `纯文本阅读器无保存设置，应用全局设置: 字体大小=${globalFontSize}, 字体=${globalFontFamily}, 背景色=${globalBgPreset.backgroundColor}`);
        this.loadTextReaderSettingsFromEBook(ebook.readingSettings);
      }
    } else {
      // 没有保存的设置，使用全局设置
      logger.info(TAG, `纯文本阅读器无保存设置，应用全局设置: 字体大小=${globalFontSize}, 字体=${globalFontFamily}, 背景色=${globalBgPreset.backgroundColor}`);
      this.loadTextReaderSettingsFromGlobal(globalFontSize, globalFontFamily, globalFontWeight, globalLineHeight, globalParagraphSpacing, 
        globalFirstLineIndent, globalPageMargin, globalBgPreset, globalUseBgImage, globalBgImagePath, 
        globalBgImageOpacity, globalPageTurnAnimation, globalKeepScreenOn, globalLockDeviceOrientation,
        globalVolumeKeyNav, globalTapToTurn);
    }
    this.syncDeviceOrientationLock('text_settings_loaded');
  }

  /**
  * 从全局设置加载纯文本阅读器设置
  */
  private loadTextReaderSettingsFromGlobal(
    fontSize: number, fontFamily: string, fontWeight: number, lineHeight: number, paragraphSpacing: number, firstLineIndent: number,
    pageMargin: number, bgPreset: PresetBackground, useBgImage: boolean, bgImagePath: string,
    bgImageOpacity: number, pageTurnAnimation: TextPageTurnAnimation, keepScreenOn: boolean,
    lockDeviceOrientation: boolean, volumeKeyNav: boolean, tapToTurn: boolean
  ): void {
    const savedImages: SavedBackgroundImage[] = [];
    if (useBgImage && bgImagePath && bgImagePath.length > 0) {
      savedImages.push({ path: bgImagePath, addTime: Date.now() });
    }
    
    this.textReaderSettings = {
      readingMode: TextReadingMode.PAGE,
      readingDirection: DEFAULT_TEXT_READER_SETTINGS.readingDirection,
      pageTurnAnimation: pageTurnAnimation,
      background: {
        type: useBgImage ? BackgroundType.IMAGE : BackgroundType.COLOR,
        color: bgPreset.backgroundColor,
        imagePath: bgImagePath,
        imageOpacity: bgImageOpacity
      },
      savedBackgroundImages: savedImages,
      textStyle: {
        fontSize: clampTextReaderFontSize(fontSize),
        lineHeight: lineHeight,
        paragraphSpacing: paragraphSpacing,
        firstLineIndent: firstLineIndent,
        letterSpacing: DEFAULT_TEXT_READER_SETTINGS.textStyle.letterSpacing,
        textColor: bgPreset.textColor,
        fontWeight: fontWeight,
        fontFamily: fontFamily,
        fontPath: '',  // 全局设置暂不支持自定义字体路径
        textAlignment: DEFAULT_TEXT_READER_SETTINGS.textStyle.textAlignment
      },
      pageMargins: {
        top: pageMargin + 24,
        bottom: pageMargin + 24,
        left: pageMargin,
        right: pageMargin
      },
      keepScreenOn: keepScreenOn,
      lockDeviceOrientation: lockDeviceOrientation,
      showPageNumber: true,
      showProgress: false,
      showTime: true,
      showBattery: false,
      tapToTurn: tapToTurn,
      volumeKeyNavigation: volumeKeyNav,
      autoScrollSpeed: 50,
      curlBackOpacity: 90,
      readAloud: this.loadGlobalReadAloudSettings()
    };
    
    // 同步背景图片设置
    this.fontSize = clampTextReaderFontSize(fontSize);
    this.lineHeight = lineHeight;
    this.bgColor = bgPreset.backgroundColor;
    this.textColor = bgPreset.textColor;
    this.pageMargin = pageMargin;
    // 同步背景图片设置
    this.bgImagePath = useBgImage ? bgImagePath : '';
    this.bgImageOpacity = bgImageOpacity;
    this.updateVolumeKeyListener();
  }

  /**
  * 从 EBookReadingSettings 加载 TextReaderSettings
  * 用于 TXT 格式电子书恢复阅读设置
  */
  private loadTextReaderSettingsFromEBook(settings: EBookReadingSettings): void {
    // 如果有保存的背景图片路径，自动添加到 savedBackgroundImages 列表
    const savedImages: SavedBackgroundImage[] = [];
    if (settings.backgroundImagePath && settings.backgroundImagePath.length > 0) {
      savedImages.push({
        path: settings.backgroundImagePath,
        addTime: Date.now()
      });
    }

    // 创建新的 TextReaderSettings 对象
    this.textReaderSettings = {
      readingMode: TextReadingMode.PAGE,
      readingDirection: DEFAULT_TEXT_READER_SETTINGS.readingDirection,
      pageTurnAnimation: this.convertPageTurnAnimation(settings.pageTurnAnimation),
      background: {
        type: this.convertBackgroundType(settings.backgroundType),
        color: settings.backgroundColor || '#F5F0E1',
        imagePath: settings.backgroundImagePath || '',
        imageOpacity: settings.backgroundImageOpacity ?? 1.0
      },
      savedBackgroundImages: savedImages,
      textStyle: {
        fontSize: clampTextReaderFontSize(settings.fontSize),
        lineHeight: settings.lineHeight,
        paragraphSpacing: settings.paragraphSpacing ?? 16,
        firstLineIndent: settings.firstLineIndent ?? 2,
        letterSpacing: settings.letterSpacing ?? 0.5,
        textColor: settings.textColor,
        fontWeight: settings.fontWeight || 400,
        fontFamily: settings.fontFamily || 'HarmonyOS Sans',
        fontPath: settings.fontPath || '',
        textAlignment: this.convertTextAlignment(settings.textAlignment)
      },
      pageMargins: {
        top: (settings.pageMargin || 24) + 24,
        bottom: (settings.pageMargin || 24) + 24,
        left: settings.pageMargin || 24,
        right: settings.pageMargin || 24
      },
      keepScreenOn: settings.keepScreenOn ?? true,
      lockDeviceOrientation: settings.lockDeviceOrientation ?? false,
      showPageNumber: settings.showPageNumber ?? true,
      showProgress: settings.showProgress ?? false,
      showTime: settings.showTime ?? true,
      showBattery: settings.showBattery ?? false,
      tapToTurn: settings.tapToTurn ?? true,
      volumeKeyNavigation: settings.volumeKeyNavigation ?? true,
      autoScrollSpeed: 50,
      curlBackOpacity: 90,
      readAloud: this.loadGlobalReadAloudSettings()
    };
    this.updateVolumeKeyListener();
    
    // 同步背景图片设置到页面状态
    if (settings.backgroundType === 'IMAGE' && settings.backgroundImagePath && settings.backgroundImagePath.length > 0) {
      this.bgImagePath = settings.backgroundImagePath;
      this.bgImageOpacity = settings.backgroundImageOpacity ?? 0.3;
    } else {
      this.bgImagePath = '';
    }

    logger.info(TAG, `从数据库加载文本阅读器设置: volumeKeyNavigation=${this.textReaderSettings.volumeKeyNavigation}, fontSize=${this.textReaderSettings.textStyle.fontSize}, bgType=${this.textReaderSettings.background.type}, bgColor=${this.textReaderSettings.background.color}, textColor=${this.textReaderSettings.textStyle.textColor}, bgImagePath=${this.textReaderSettings.background.imagePath}`);
  }
  private getSafeReadAloudSettings(settings?: ReadAloudSettings): ReadAloudSettings {
    const globalDefaults = this.loadGlobalReadAloudSettings();
    if (!settings) {
      return normalizeReadAloudSettings(globalDefaults);
    }
    return this.mergeReadAloudSettings(globalDefaults, settings);
  }

  private syncDeviceOrientationLock(reason: string): void {
    if (!this.uiContext) {
      this.uiContext = this.getUIContext();
    }
    let enabled: boolean = false;
    if (this.isUsingTextReader()) {
      enabled = this.textReaderSettings.lockDeviceOrientation ?? false;
    } else {
      enabled = this.ebook?.readingSettings?.lockDeviceOrientation ?? false;
    }
    this.orientationLockToken = ReaderOrientationLockHelper.syncCurrentOrientationLock(
      'EBookReaderPage',
      this.orientationLockToken,
      enabled,
      this.uiContext
    );
    logger.info(TAG, `设备方向锁同步完成: enabled=${enabled}, reason=${reason}`);
  }

  private mergeReadAloudSettings(current: ReadAloudSettings, partial: Partial<ReadAloudSettings>): ReadAloudSettings {
    const currentRemote = current.remote;
    const partialRemote = partial.remote;
    let mergedRemote = currentRemote;
    if (partialRemote && currentRemote) {
      mergedRemote = mergeRemoteReadAloudSettings(currentRemote, partialRemote);
    }
    return normalizeReadAloudSettings({
      enabled: partial.enabled ?? current.enabled,
      engineType: partial.engineType ?? current.engineType,
      speed: partial.speed ?? current.speed,
      pitch: partial.pitch ?? current.pitch,
      volume: partial.volume ?? current.volume,
      continueInBackground: partial.continueInBackground ?? current.continueInBackground,
      autoPlayNextChapter: partial.autoPlayNextChapter ?? current.autoPlayNextChapter,
      pauseOnManualPageTurn: partial.pauseOnManualPageTurn ?? current.pauseOnManualPageTurn,
      voiceLanguage: partial.voiceLanguage ?? current.voiceLanguage,
      voicePerson: partial.voicePerson ?? current.voicePerson,
      voiceOnline: partial.voiceOnline ?? current.voiceOnline,
      remote: mergedRemote
    });
  }

  private loadGlobalReadAloudSettings(): ReadAloudSettings {
    return loadStoredGlobalReadAloudSettings(this.settingsManager);
  }

  private async persistGlobalReadAloudSettings(settings: ReadAloudSettings): Promise<void> {
    try {
      await persistStoredGlobalReadAloudSettings(this.settingsManager, normalizeReadAloudSettings(settings));
    } catch (error) {
      logger.warn(TAG, `保存全局听书设置失败: ${String(error)}`);
    }
  }

  private syncTextReadAloudContext(): void {
    if (!this.isUsingTextReader()) {
      return;
    }
    const readAloudSettings = this.getSafeReadAloudSettings(this.textReaderSettings.readAloud);
    this.textReaderSettings.readAloud = readAloudSettings;
    this.readAloudController.updateSettings(readAloudSettings);
    this.updateTextReadAloudContextByPosition();
    this.textReadAloudPlaying = this.readAloudController.getSnapshot().playbackState === ReadAloudPlaybackState.PLAYING;
  }

  private getCurrentTextResumeCharIndex(): number {
    if (this.textReadAloudCurrentCharIndex >= 0) {
      return this.textReadAloudCurrentCharIndex;
    }
    if (this.textCurrentPageEndCharIndex > this.textCurrentPageStartCharIndex) {
      return this.textCurrentPageStartCharIndex;
    }
    return 0;
  }

  private calculateTextOverallProgressByChar(
    charIndex: number,
    currentPositionMs: number = -1,
    totalDurationMs: number = -1
  ): number {
    if (!this.ebook || this.ebook.chapters.length === 0) {
      return 0;
    }

    const totalChapters = this.ebook.chapters.length;
    const chapterLength = this.textContent.length;
    let chapterProgress = 0;
    if (totalDurationMs > 0 && currentPositionMs >= 0) {
      const safeCurrentPositionMs = Math.max(0, Math.min(currentPositionMs, totalDurationMs));
      chapterProgress = safeCurrentPositionMs / Math.max(1, totalDurationMs);
    } else if (chapterLength > 0) {
      const safeCharIndex = Math.max(0, Math.min(charIndex, chapterLength));
      chapterProgress = safeCharIndex / chapterLength;
    } else {
      const baseProgress = (this.currentChapterIndex / totalChapters) * 100;
      return Math.max(0, Math.min(100, baseProgress));
    }
    const overallProgress = ((this.currentChapterIndex + chapterProgress) / totalChapters) * 100;
    return Math.max(0, Math.min(100, overallProgress));
  }

  private tryPersistTextReadAloudProgress(): void {
    if (!this.isUsingTextReader()) {
      return;
    }
    if (this.textReadAloudCurrentCharIndex < 0) {
      return;
    }

    const now = Date.now();
    if ((now - this.lastReadAloudProgressSaveTime) < EBookReaderPage.READ_ALOUD_PROGRESS_SAVE_INTERVAL_MS) {
      return;
    }
    this.lastReadAloudProgressSaveTime = now;

    const snapshot = this.readAloudController.getSnapshot();
    const overallProgress = this.calculateTextOverallProgressByChar(
      this.textReadAloudCurrentCharIndex,
      snapshot.currentPositionMs,
      snapshot.totalDurationMs
    );
    this.latestTextProgress = overallProgress;
    this.saveTextReadingProgressWithPage(overallProgress, this.textCurrentPageIndex);
  }

  private updateTextReadAloudContextByPosition(): void {
    const ebook = this.ebook;
    if (!ebook || !this.isTextReaderFormat(ebook.format)) {
      return;
    }
    this.readAloudController.updateContext({
      bookId: ebook.id,
      bookTitle: ebook.metadata.title || '电子书',
      chapterIndex: this.currentChapterIndex,
      chapterTitle: this.currentChapter?.title || '',
      coverUrl: ebook.metadata.coverImagePath || '',
      content: this.textContent,
      pageIndex: this.textCurrentPageIndex,
      resumeCharIndex: this.getCurrentTextResumeCharIndex()
    });
  }

  private applyTextReadAloudProgress(payload: ReadAloudStatePayload): void {
    const payloadCharIndex = payload.currentCharIndex >= 0 ? payload.currentCharIndex : payload.chunkStartCharIndex;
    if (payloadCharIndex < 0) {
      return;
    }

    const maxCharIndex = Math.max(0, this.textContent.length);
    this.textReadAloudCurrentCharIndex = Math.max(0, Math.min(payloadCharIndex, maxCharIndex));
    if (payload.reason === 'progress_updated') {
      logger.debug(
        TAG,
        `Read-aloud chunk update: char=${this.textReadAloudCurrentCharIndex}, chunk=[${payload.chunkStartCharIndex}, ${payload.chunkEndCharIndex}]`
      );
    }
    this.latestTextProgress = this.calculateTextOverallProgressByChar(
      this.textReadAloudCurrentCharIndex,
      payload.currentPositionMs,
      payload.totalDurationMs
    );
    this.updateTextReadAloudContextByPosition();
    if (
      payload.reason === 'progress_updated' ||
      payload.playbackState === ReadAloudPlaybackState.PLAYING
    ) {
      this.tryPersistTextReadAloudProgress();
    }
  }

  private onTextPageCharRangeChange(startCharIndex: number, endCharIndex: number): void {
    this.textCurrentPageStartCharIndex = Math.max(0, startCharIndex);
    this.textCurrentPageEndCharIndex = Math.max(this.textCurrentPageStartCharIndex, endCharIndex);
    if (this.textReadAloudCurrentCharIndex < 0) {
      this.textReadAloudCurrentCharIndex = this.textCurrentPageStartCharIndex;
    } else {
      const isPlaying = this.readAloudController.getSnapshot().playbackState === ReadAloudPlaybackState.PLAYING;
      if (!isPlaying) {
        const inCurrentPage = this.textReadAloudCurrentCharIndex >= this.textCurrentPageStartCharIndex &&
          this.textReadAloudCurrentCharIndex < this.textCurrentPageEndCharIndex;
        if (!inCurrentPage) {
          // 非播放状态下翻页时，将恢复点对齐到当前页，避免再次从旧位置或开头开始。
          this.textReadAloudCurrentCharIndex = this.textCurrentPageStartCharIndex;
        }
      }
    }
    this.updateTextReadAloudContextByPosition();
    this.refreshCurrentEBookBookmarkState('text_page_char_range_change');
  }

  private onTextUserPageTurnStart(): void {
    if (!this.isUsingTextReader()) {
      return;
    }
    const readAloudSettings = this.getSafeReadAloudSettings(this.textReaderSettings.readAloud);
    if (!readAloudSettings.pauseOnManualPageTurn) {
      return;
    }
    const isPlaying = this.readAloudController.getSnapshot().playbackState === ReadAloudPlaybackState.PLAYING;
    if (!isPlaying) {
      return;
    }
    this.readAloudController.pause('manual_page_turn');
    this.updateTextReadAloudContextByPosition();
    this.textReadAloudPlaying = false;
    this.saveReadingProgress();
    logger.info(TAG, 'Read-aloud panel state updated and persisted');
  }

  private toggleTextReadAloud(): void {
    if (!this.isUsingTextReader()) {
      return;
    }

    const currentReadAloud = this.getSafeReadAloudSettings(this.textReaderSettings.readAloud);
    const nextReadAloud: ReadAloudSettings = normalizeReadAloudSettings(currentReadAloud);

    if (!nextReadAloud.enabled) {
      nextReadAloud.enabled = true;
      this.textReaderSettings.readAloud = nextReadAloud;
      this.queueTextReaderSettingsSave();
      this.persistGlobalReadAloudSettings(nextReadAloud);
    }

    this.readAloudController.updateSettings(nextReadAloud);
    this.updateTextReadAloudContextByPosition();
    if (this.readAloudController.getSnapshot().playbackState === ReadAloudPlaybackState.PLAYING) {
      this.readAloudController.pause('toolbar_toggle');
    } else {
      this.readAloudController.start('toolbar_toggle');
    }
    this.textReadAloudPlaying = this.readAloudController.getSnapshot().playbackState === ReadAloudPlaybackState.PLAYING;
  }

  private openReadAloudSettingsPanel(): void {
    if (!this.isUsingTextReader()) {
      return;
    }
    const now = Date.now();
    if ((now - this.lastReadAloudPanelCloseTime) < EBookReaderPage.READ_ALOUD_PANEL_REOPEN_GUARD_MS) {
      logger.debug(
        TAG,
        `Read-aloud panel close debounce hit, delta=${now - this.lastReadAloudPanelCloseTime}ms`
      );
      return;
    }
    this.handleReaderOverlayOpening('read_aloud_panel_open');
    this.showReadAloudPanel = true;
    this.readAloudPanelSettings = this.getSafeReadAloudSettings(this.textReaderSettings.readAloud);
    logger.info(TAG, 'Read-aloud settings refreshed');
    this.refreshReadAloudAvailability();
  }

  private updateReadAloudSettings(partial: Partial<ReadAloudSettings>): void {
    if (!this.isUsingTextReader()) {
      return;
    }
    logger.debug(TAG, `应用听书设置变更: ${JSON.stringify(partial)}`);
    const current = this.getSafeReadAloudSettings(this.textReaderSettings.readAloud);
    const nextReadAloud: ReadAloudSettings = this.mergeReadAloudSettings(current, partial);
    this.readAloudPanelSettings = nextReadAloud;
    this.textReaderSettings.readAloud = nextReadAloud;
    this.queueTextReaderSettingsSave();
    this.persistGlobalReadAloudSettings(nextReadAloud);
    this.syncTextReadAloudContext();

    const shouldRefreshAvailability = partial.engineType !== undefined || partial.remote !== undefined;
    if (shouldRefreshAvailability) {
      this.refreshReadAloudAvailability();
      return;
    }
    if (
      partial.voiceLanguage !== undefined ||
      partial.voicePerson !== undefined ||
      partial.voiceOnline !== undefined
    ) {
      this.refreshReadAloudVoices();
    }
  }

  private syncTextReadAloudUiFromController(): void {
    const ebook = this.ebook;
    if (!ebook || !this.isTextReaderFormat(ebook.format)) {
      return;
    }
    const context = this.readAloudController.getContextSnapshot();
    const snapshot = this.readAloudController.getSnapshot();
    if (!context || !snapshot.hasContext || context.bookId !== ebook.id) {
      return;
    }
    this.textReadAloudPlaying = snapshot.playbackState === ReadAloudPlaybackState.PLAYING;
    const payloadCharIndex = snapshot.currentCharIndex >= 0 ? snapshot.currentCharIndex : snapshot.chunkStartCharIndex;
    if (payloadCharIndex < 0) {
      return;
    }
    const maxCharIndex = Math.max(0, this.textContent.length);
    this.textReadAloudCurrentCharIndex = Math.max(0, Math.min(payloadCharIndex, maxCharIndex));
    this.latestTextProgress = this.calculateTextOverallProgressByChar(
      this.textReadAloudCurrentCharIndex,
      snapshot.currentPositionMs,
      snapshot.totalDurationMs
    );
  }

  private refreshReadAloudAvailability(): void {
    ReadAloudAvailability.refresh(false, this.getSafeReadAloudSettings(this.textReaderSettings.readAloud)).then((map: ReadAloudEngineAvailabilityMap) => {
      this.readAloudAvailability = map;
      if (!map.SYSTEM) {
        const probeError = ReadAloudAvailability.getLastSystemProbeErrorMessage();
        if (probeError.length > 0) {
          this.readAloudStatusMessage = `System TTS probe failed: ${probeError}`;
        }
      }
      if (!map.REMOTE && this.getSafeReadAloudSettings(this.textReaderSettings.readAloud).engineType === ReadAloudEngineType.REMOTE) {
        const probeError = ReadAloudAvailability.getLastRemoteProbeErrorMessage();
        if (probeError.length > 0) {
          this.readAloudStatusMessage = `Remote TTS unavailable: ${probeError}`;
        }
      }
      this.refreshReadAloudVoices();
    }).catch((error: Object | string) => {
      const errorText = this.formatReadAloudError(error);
      logger.warn(TAG, `刷新听书引擎可用性失败: ${errorText}`);
      this.readAloudStatusMessage = `Read-aloud initialization failed: ${errorText}`;
    });
  }

  private isReadAloudEngineAvailable(engineType: ReadAloudEngineType): boolean {
    if (engineType === ReadAloudEngineType.SYSTEM) {
      return this.readAloudAvailability.SYSTEM === true;
    }
    if (engineType === ReadAloudEngineType.LEGADO_COMPAT) {
      return this.readAloudAvailability.LEGADO_COMPAT === true;
    }
    if (engineType === ReadAloudEngineType.REMOTE) {
      return this.readAloudAvailability.REMOTE === true;
    }
    return false;
  }

  private refreshReadAloudVoices(): void {
    const engineType = this.getSafeReadAloudSettings(this.textReaderSettings.readAloud).engineType;
    if (!this.isReadAloudEngineAvailable(engineType)) {
      this.readAloudVoiceOptions = [];
      if (engineType === ReadAloudEngineType.SYSTEM) {
        const probeError = ReadAloudAvailability.getLastSystemProbeErrorMessage();
        if (probeError.length > 0) {
          this.readAloudStatusMessage = `System TTS probe failed: ${probeError}`;
        } else {
          this.readAloudStatusMessage = 'System TTS is unavailable, please check device settings';
        }
      } else if (engineType === ReadAloudEngineType.REMOTE) {
        const probeError = ReadAloudAvailability.getLastRemoteProbeErrorMessage();
        if (probeError.length > 0) {
          this.readAloudStatusMessage = `Remote TTS unavailable: ${probeError}`;
        } else {
        this.readAloudStatusMessage = 'Remote TTS unavailable, please check endpoint/model/voice/apiKey settings';
        }
      } else {
        this.readAloudStatusMessage = 'Current read-aloud engine is unavailable';
      }
      return;
    }
    this.readAloudController.listVoices(engineType).then((voices: ReadAloudVoiceOption[]) => {
      this.readAloudVoiceOptions = voices;
      if (voices.length > 0) {
        this.readAloudStatusMessage = '';
      } else if (engineType === ReadAloudEngineType.SYSTEM) {
        this.readAloudStatusMessage = 'System TTS engine initialization failed, trying fallback';
      } else {
        this.readAloudStatusMessage = 'System TTS engine initialization failed';
      }
    }).catch((error: Object | string) => {
      const errorText = this.formatReadAloudError(error);
      logger.warn(TAG, `刷新听书音色列表失败: ${errorText}`);
      this.readAloudVoiceOptions = [];
      this.readAloudStatusMessage = `Read-aloud startup failed: ${errorText}`;
    });
  }

  private formatReadAloudError(error: Object | string): string {
    if (typeof error === 'string') {
      return error;
    }
    const errorObj = error as Error;
    if (errorObj.message && errorObj.message.length > 0) {
      return errorObj.message;
    }
    try {
      const jsonText = JSON.stringify(error);
      if (jsonText && jsonText.length > 0 && jsonText !== '{}') {
        return jsonText;
      }
    } catch (_ignored) {
    }
    return String(error);
  }

  private buildTextDomPos(pageIndex: number): string {
    const safePageIndex = Math.max(0, pageIndex);
    if (this.textReadAloudCurrentCharIndex < 0) {
      return `page:${safePageIndex}`;
    }
    return `page:${safePageIndex};char:${Math.max(0, this.textReadAloudCurrentCharIndex)}`;
  }

  private buildMarkdownDomPos(progress: number): string {
    const safeProgress = Math.max(0, Math.min(100, progress));
    return `markdown:${safeProgress.toFixed(2)}`;
  }

  private parseMarkdownProgressFromDomPos(domPos: string): number {
    if (!domPos || !domPos.startsWith('markdown:')) {
      return -1;
    }
    const progressText = domPos.substring('markdown:'.length);
    const progress = Number(progressText);
    if (!Number.isFinite(progress)) {
      return -1;
    }
    return Math.max(0, Math.min(100, progress));
  }

  private restoreMarkdownProgressFromDomPos(domPos: string): void {
    const progress = this.parseMarkdownProgressFromDomPos(domPos);
    if (progress < 0) {
      return;
    }
    this.markdownChapterProgress = progress;
    this.pendingMarkdownRestoreProgress = progress;
    logger.info(TAG, `恢复 Markdown 章节进度: ${progress.toFixed(1)}%`);
  }

  private calculateMarkdownOverallProgress(chapterProgress: number): number {
    if (!this.ebook || this.ebook.chapters.length <= 0) {
      return 0;
    }
    const safeChapterProgress = Math.max(0, Math.min(100, chapterProgress));
    const totalChapters = this.ebook.chapters.length;
    const overallProgress = ((this.currentChapterIndex + safeChapterProgress / 100) / totalChapters) * 100;
    return Math.max(0, Math.min(100, overallProgress));
  }

  private createMarkdownProgressSnapshotFromState(): MarkdownProgressSnapshot {
    const snapshot: MarkdownProgressSnapshot = {
      progress: Math.max(0, Math.min(100, this.markdownChapterProgress)),
      scrollTop: 0,
      maxScrollTop: 0,
      currentPage: Math.max(1, this.markdownCurrentPage),
      pageCount: Math.max(1, this.markdownPageCount)
    };
    return snapshot;
  }

  private restoreTextReadAloudFromDomPos(domPos: string): void {
    if (!domPos || !domPos.startsWith('page:')) {
      return;
    }
    const parts = domPos.split(';');
    const pagePart = parts.length > 0 ? parts[0] : '';
    const pageIndex = parseInt(pagePart.substring(5), 10);
    if (!isNaN(pageIndex) && pageIndex >= 0) {
      this.textCurrentPageIndex = pageIndex;
      logger.info(TAG, `恢复文本阅读器页码: ${pageIndex}`);
    }

    for (const part of parts) {
      if (part.startsWith('char:')) {
        const charIndex = parseInt(part.substring(5), 10);
        if (!isNaN(charIndex) && charIndex >= 0) {
          this.textReadAloudCurrentCharIndex = charIndex;
        }
        break;
      }
    }
  }

  /**
  * 转换翻页动画类型
  */
  private convertPageTurnAnimation(animation?: string): TextPageTurnAnimation {
    switch (animation) {
      case 'SLIDE': return TextPageTurnAnimation.SLIDE;
      case 'CURL': return TextPageTurnAnimation.CURL;
      case 'FADE': return TextPageTurnAnimation.FADE;
      case 'NONE': return TextPageTurnAnimation.NONE;
      default: return TextPageTurnAnimation.SLIDE;
    }
  }

  /**
  * 转换背景类型
  */
  private convertBackgroundType(type?: string): BackgroundType {
    switch (type) {
      case 'IMAGE': return BackgroundType.IMAGE;
      case 'GRADIENT': return BackgroundType.GRADIENT;
      default: return BackgroundType.COLOR;
    }
  }

  /**
  * 转换文字对齐方式
  */
  private convertTextAlignment(alignment?: string): TextAlignment {
    switch (alignment) {
      case 'LEFT': return TextAlignment.LEFT;
      case 'CENTER': return TextAlignment.CENTER;
      case 'RIGHT': return TextAlignment.RIGHT;
      case 'JUSTIFY': return TextAlignment.JUSTIFY;
      default: return TextAlignment.JUSTIFY;
    }
  }

  /**
  * 根据系统主题应用阅读设置
  * 当 followSystemTheme 为 true 时，根据当前 App 全局主题自动切换白天/夜间模式
  */
  private applySystemThemeToSettings(ebook: EBook): void {
    if (!ebook.readingSettings) {
      return;
    }
    
      // 夜间模式
    const currentTheme = this.themeState.currentTheme;
    const isDarkMode = currentTheme === ThemeType.DARK;
    
    logger.info(TAG, `应用系统主题: currentTheme=${currentTheme}, isDarkMode=${isDarkMode}`);
    
    if (isDarkMode) {
      // 白天模式
      ebook.readingSettings.backgroundColor = '#1E1E1E';
      ebook.readingSettings.textColor = '#D4D4D4';
      ebook.readingSettings.nightMode = true;
    } else {
      // 白天模式
      ebook.readingSettings.backgroundColor = '#FFFFFF';
      ebook.readingSettings.textColor = '#000000';
      ebook.readingSettings.nightMode = false;
    }
  }

  /**
  * 切换到上一章
  */
  private previousChapter(): void {
    if (!this.ebook || this.currentChapterIndex <= 0) {
      logger.warn(TAG, 'Already at first chapter');
      return;
    }

    let wasPlaying = false;
    let readAloudSettings: ReadAloudSettings = this.getSafeReadAloudSettings(this.textReaderSettings.readAloud);
    if (this.isUsingTextReader()) {
      readAloudSettings = this.getSafeReadAloudSettings(this.textReaderSettings.readAloud);
      wasPlaying = this.readAloudController.getSnapshot().playbackState === ReadAloudPlaybackState.PLAYING;
      if (wasPlaying && !readAloudSettings.autoPlayNextChapter) {
        this.readAloudController.pause('chapter_switch');
      }
    }

    this.currentChapterIndex--;
    this.currentChapter = this.ebook.chapters[this.currentChapterIndex];
    if (this.isUsingImagePageReader()) {
      this.imagePageChapterTick++;
      this.updateImagePagePreloadDebugInfo();
      this.refreshCurrentEBookBookmarkState('image_page_previous_chapter');
    }
    if (this.isUsingMarkdownReader()) {
      this.resetMarkdownChapterContent(0, '', true);
      this.refreshCurrentEBookBookmarkState('markdown_previous_chapter');
      logger.info(TAG, `切换到上一章 Markdown: ${this.currentChapter?.title}`);
      return;
    }
    // TXT格式使用页码进度保存，其他格式使用通用方法
    if (this.isUsingTextReader()) {
      this.textCurrentPageIndex = 0;
      this.textContent = this.getTextContent();
      this.textCurrentPageStartCharIndex = 0;
      this.textCurrentPageEndCharIndex = 0;
      this.textReadAloudCurrentCharIndex = 0;
      this.updateTextReadAloudContextByPosition();
      // 计算全书进度：当前章节索引 / 总章节数 * 100
      const totalChapters = this.ebook.chapters?.length || 1;
      const overallProgress = (this.currentChapterIndex / totalChapters) * 100;
      this.saveTextReadingProgressWithPage(overallProgress, 0);
      if (wasPlaying && readAloudSettings.enabled && readAloudSettings.autoPlayNextChapter) {
        this.readAloudController.start('chapter_switch');
      }
      this.textReadAloudPlaying = this.readAloudController.getSnapshot().playbackState === ReadAloudPlaybackState.PLAYING;
    } else {
      this.saveReadingProgress();
    }
    logger.info(TAG, `切换到上一章: ${this.currentChapter?.title}`);
  }

  /**
  * 切换到下一章
  */
  private nextChapter(): void {
    if (!this.ebook || this.currentChapterIndex >= this.ebook.chapters.length - 1) {
      logger.warn(TAG, 'Already at last chapter');
      return;
    }

    let wasPlaying = false;
    let readAloudSettings: ReadAloudSettings = this.getSafeReadAloudSettings(this.textReaderSettings.readAloud);
    if (this.isUsingTextReader()) {
      readAloudSettings = this.getSafeReadAloudSettings(this.textReaderSettings.readAloud);
      wasPlaying = this.readAloudController.getSnapshot().playbackState === ReadAloudPlaybackState.PLAYING;
      if (wasPlaying && !readAloudSettings.autoPlayNextChapter) {
        this.readAloudController.pause('chapter_switch');
      }
    }

    this.currentChapterIndex++;
    this.currentChapter = this.ebook.chapters[this.currentChapterIndex];
    if (this.isUsingImagePageReader()) {
      this.imagePageChapterTick++;
      this.updateImagePagePreloadDebugInfo();
      this.refreshCurrentEBookBookmarkState('image_page_next_chapter');
    }
    if (this.isUsingMarkdownReader()) {
      this.resetMarkdownChapterContent(0, '', true);
      this.refreshCurrentEBookBookmarkState('markdown_next_chapter');
      logger.info(TAG, `切换到下一章 Markdown: ${this.currentChapter?.title}`);
      return;
    }
    // TXT格式使用页码进度保存，其他格式使用通用方法
    if (this.isUsingTextReader()) {
      this.textCurrentPageIndex = 0;
      this.textContent = this.getTextContent();
      this.textCurrentPageStartCharIndex = 0;
      this.textCurrentPageEndCharIndex = 0;
      this.textReadAloudCurrentCharIndex = 0;
      this.updateTextReadAloudContextByPosition();
      // 计算全书进度：当前章节索引 / 总章节数 * 100
      const totalChapters = this.ebook.chapters?.length || 1;
      const overallProgress = (this.currentChapterIndex / totalChapters) * 100;
      this.saveTextReadingProgressWithPage(overallProgress, 0);
      if (wasPlaying && readAloudSettings.enabled && readAloudSettings.autoPlayNextChapter) {
        this.readAloudController.start('chapter_switch');
      }
      this.textReadAloudPlaying = this.readAloudController.getSnapshot().playbackState === ReadAloudPlaybackState.PLAYING;
    } else {
      this.saveReadingProgress();
    }
    logger.info(TAG, `切换到下一章: ${this.currentChapter?.title}`);
  }

  private ebookSettingsSaveTimeoutId: number = -1;

  private queueEBookSettingsSave(): void {
    if (this.ebookSettingsSaveTimeoutId !== -1) {
      clearTimeout(this.ebookSettingsSaveTimeoutId);
    }
    this.ebookSettingsSaveTimeoutId = setTimeout(() => {
      this.ebookSettingsSaveTimeoutId = -1;
      if (this.ebook && this.ebook.readingSettings) {
        this.ebookDataManager.saveReadingSettings(this.ebook.id, this.ebook.readingSettings)
          .then(() => {
            logger.info(TAG, 'Reading settings saved');
          })
          .catch((error: Error) => {
            logger.error(TAG, `Failed to save reading settings: ${error.message}`);
          });
      }
    }, 500);
  }

  /**
  * 更新阅读设置（立即生效）
  */
  private async updateReadingSettings(settings: EBookReadingSettings): Promise<void> {
    if (!this.ebook) {
      return;
    }

    try {
      // 更新电子书设置
      this.fontSize = settings.fontSize;
      this.lineHeight = settings.lineHeight;
      this.bgColor = settings.backgroundColor;
      this.textColor = settings.textColor;
      this.pageMargin = settings.pageMargin;

      const nextSettings: EBookReadingSettings = JSON.parse(JSON.stringify(settings));
      this.ebook.readingSettings = nextSettings;
      this.syncImagePageReaderSettings();
      this.syncDeviceOrientationLock('ebook_settings_change');

      // 保存到数据库
      if (this.readerKitController && this.readerKitController.isControllerReady()) {
        this.readerKitController.applyReadingSettings(settings, true);
        logger.info(TAG, '阅读设置已应用');
      }
      this.applyMarkdownReaderStyle();

      // 延迟保存到数据库
      this.queueEBookSettingsSave();
    } catch (error) {
      logger.error(TAG, `应用阅读设置失败: ${String(error)}`);
    }
  }

  private saveSettings(): void {
    if (!this.ebook || !this.ebook.readingSettings) {
      return;
    }

    // 立即应用到 Reader Kit
    const nextSettings: EBookReadingSettings = JSON.parse(JSON.stringify(this.ebook.readingSettings));
    nextSettings.fontSize = this.fontSize;
    nextSettings.lineHeight = this.lineHeight;
    nextSettings.backgroundColor = this.bgColor;
    nextSettings.textColor = this.textColor;
    nextSettings.pageMargin = this.pageMargin;
    this.ebook.readingSettings = nextSettings;
    const isNightMode = this.bgColor === '#1E1E1E' || this.bgColor === '#1B3B2F';
    this.ebook.readingSettings.nightMode = isNightMode;
    this.syncImagePageReaderSettings();

    // 异步保存到数据库
    if (this.readerKitController && this.readerKitController.isControllerReady()) {
      this.readerKitController.applyReadingSettings(this.ebook.readingSettings, true);
    }
    this.applyMarkdownReaderStyle();

  // 当前 DOM 位置（用于 Reader Kit 精确恢复阅读位置）
    this.queueEBookSettingsSave();
  }

  private applyReadingThemePreset(backgroundColor: string, textColor: string): void {
    this.bgColor = backgroundColor;
    this.textColor = textColor;
    if (this.ebook && this.ebook.readingSettings) {
      this.ebook.readingSettings.followSystemTheme = false;
      this.ebook.readingSettings.nightMode = backgroundColor === '#1E1E1E' || backgroundColor === '#1B3B2F';
    }
    this.saveSettings();
  }

  // 当前 DOM 位置（用于 Reader Kit 精确恢复阅读位置）
  @State currentDomPos: string = '';

  /**
  * 保存阅读进度
  */
  private async saveReadingProgress(): Promise<void> {
    if (!this.ebook) {
      return;
    }
    
    // 互斥锁：如果正在保存，跳过本次请求
    if (this.isSavingProgress) {
      logger.debug(TAG, 'Progress save in progress, skip duplicate request');
      return;
    }
    
    this.isSavingProgress = true;

    try {
      // 对于 TXT 格式，使用页码信息
      let domPos = this.currentDomPos;
      let currentPosition = 0;
      let chapterId = '';
      let progressPercent = 0;
      let chapterIndexToSave = Math.max(0, this.currentChapterIndex);
      
      if (this.isUsingTextReader()) {
        domPos = this.buildTextDomPos(this.textCurrentPageIndex);
        currentPosition = this.textCurrentPageIndex;
        chapterId = this.currentChapter?.id || '';
        progressPercent = this.textReadAloudCurrentCharIndex >= 0
          ? this.latestTextProgress
          : (this.ebook.readingProgress?.progress || 0);
      } else if (this.isUsingMarkdownReader()) {
        const snapshot = await this.getMarkdownProgressSnapshotForSave();
        this.applyMarkdownProgressSnapshot(snapshot, 'save_progress');
        currentPosition = Math.max(0, snapshot.currentPage - 1);
        domPos = this.buildMarkdownDomPos(snapshot.progress);
        chapterId = this.currentChapter?.id || '';
        progressPercent = this.calculateMarkdownOverallProgress(snapshot.progress);
      } else if (this.isUsingImagePageReader()) {
        chapterIndexToSave = Math.max(0, Math.min(this.currentChapterIndex, (this.ebook.chapters?.length || 1) - 1));
        currentPosition = 0;
        domPos = '';
        chapterId = this.ebook.chapters[chapterIndexToSave]?.id || `resource_${chapterIndexToSave}`;
        const total = this.ebook.chapters?.length || 0;
        progressPercent = total > 0 ? (((chapterIndexToSave + 1) / total) * 100) : 0;
      } else {
        const snapshot = this.parseReaderKitPositionSnapshot();
        if (snapshot && snapshot.resourceIndex >= 0) {
          chapterIndexToSave = snapshot.resourceIndex;
        }
        if (snapshot && snapshot.pageOffset >= 0) {
          currentPosition = snapshot.pageOffset;
        }
        chapterId = chapterIndexToSave < (this.ebook.chapters?.length || 0)
          ? (this.ebook.chapters[chapterIndexToSave]?.id || `resource_${chapterIndexToSave}`)
          : `resource_${chapterIndexToSave}`;

        const readerKitProgress = this.getCurrentEBookProgressPercent();
        const persistedProgress = this.ebook.readingProgress?.progress;
        progressPercent = readerKitProgress >= 0
          ? readerKitProgress
          : ((typeof persistedProgress === 'number' && Number.isFinite(persistedProgress)) ? persistedProgress : 0);

        if (!domPos || domPos.length <= 0) {
          domPos = this.ebook.readingProgress?.domPos || '';
        }
      }
      
      // 获取已有的阅读时间并累加本次阅读时间
      let existingReadingTime = 0;
      if (this.ebook.readingProgress && this.ebook.readingProgress.totalReadingTime > 0) {
        existingReadingTime = this.ebook.readingProgress.totalReadingTime;
      }
      const totalReadingTime = existingReadingTime + this.accumulatedReadingTime;
      
      const progress: EBookReadingProgress = {
        bookId: this.ebook.id,
        currentChapterId: chapterId,
        currentChapterIndex: chapterIndexToSave,
        currentPosition: currentPosition,
        domPos: domPos,
        progress: progressPercent,
        lastReadTime: Date.now(),
        totalReadingTime: totalReadingTime
      };

      await this.ebookDataManager.saveReadingProgress(progress);
      
      // 更新内存中的阅读进度
      if (this.ebook.readingProgress) {
        this.ebook.readingProgress.currentChapterId = progress.currentChapterId;
        this.ebook.readingProgress.currentChapterIndex = progress.currentChapterIndex;
        this.ebook.readingProgress.currentPosition = progress.currentPosition;
        this.ebook.readingProgress.domPos = progress.domPos;
        this.ebook.readingProgress.progress = progress.progress;
        this.ebook.readingProgress.lastReadTime = progress.lastReadTime;
        this.ebook.readingProgress.totalReadingTime = totalReadingTime;
      }

      distributedReadingService.syncProgress(
        this.ebook.id,
        progress.currentChapterIndex,
        progress.currentPosition,
        0,
        'ebook'
      );
      
      logger.info(TAG, `阅读进度已保存: 章节=${chapterIndexToSave}, 页=${currentPosition}, domPos长度=${domPos.length}, 累计阅读时间=${totalReadingTime.toFixed(2)}分钟`);
    } catch (error) {
      logger.error(TAG, '保存阅读进度失败', String(error instanceof Error ? error.message : error));
    } finally {
      this.isSavingProgress = false;
    }
  }

  // 互斥锁：防止并发保存导致 SQLite 约束违反
  private lastProgressSaveTime: number = 0;
  // 互斥锁：防止并发保存导致 SQLite 约束违反
  private static readonly PROGRESS_SAVE_INTERVAL: number = 2000;
  // 互斥锁：防止并发保存导致 SQLite 约束违反
  private isSavingProgress: boolean = false;

  /**
  * 处理 Reader Kit 进度变化回调（带防抖）
  */
  private handleProgressChange(progress: number, domPos: string): void {
    const incomingSnapshot = this.parseReaderKitPositionSnapshotFromDomPos(domPos);
    if (this.shouldSkipReaderKitStartupRegression(incomingSnapshot)) {
      return;
    }

    this.currentDomPos = domPos;
    if (this.ebook?.readingProgress) {
      this.ebook.readingProgress.domPos = domPos;
      this.ebook.readingProgress.progress = Number.isFinite(progress) ? progress : -1;
      const snapshot = incomingSnapshot || this.parseReaderKitPositionSnapshot();
      if (snapshot && snapshot.resourceIndex >= 0) {
        this.ebook.readingProgress.currentChapterIndex = snapshot.resourceIndex;
        this.ebook.readingProgress.currentChapterId = `resource_${snapshot.resourceIndex}`;
      }
      if (snapshot && snapshot.pageOffset >= 0) {
        this.ebook.readingProgress.currentPosition = snapshot.pageOffset;
      }
    }
    
    // 自动保存进度
    const now = Date.now();
    if ((now - this.lastProgressSaveTime) < EBookReaderPage.PROGRESS_SAVE_INTERVAL) {
      return;
    }
    this.lastProgressSaveTime = now;
    
    // 自动保存进度
    this.saveReadingProgress();
  }

  /**
  * 跳转到指定章节
  * 同时更新本地状态和 Reader Kit 控制器
  */
  private async jumpToChapter(chapterIndex: number): Promise<void> {
    if (!this.ebook || chapterIndex < 0) {
      logger.warn(TAG, `无效的章节索引: ${chapterIndex}`);
      return;
    }
    const chapterCount = this.ebook.chapters.length;
    const readerKitNavigable = !this.isUsingTextReader() &&
      !this.isUsingMarkdownReader() &&
      this.isReaderKitSupported(this.ebook.format) &&
      this.readerKitController !== null &&
      this.readerKitController.isControllerReady();
    if (!readerKitNavigable && chapterIndex >= chapterCount) {
      logger.warn(TAG, `无效的章节索引: ${chapterIndex}, chapterCount=${chapterCount}`);
      return;
    }
    
    let wasPlaying = false;
    let readAloudSettings: ReadAloudSettings = this.getSafeReadAloudSettings(this.textReaderSettings.readAloud);
    if (this.isUsingTextReader()) {
      readAloudSettings = this.getSafeReadAloudSettings(this.textReaderSettings.readAloud);
      wasPlaying = this.readAloudController.getSnapshot().playbackState === ReadAloudPlaybackState.PLAYING;
      if (wasPlaying && !readAloudSettings.autoPlayNextChapter) {
        this.readAloudController.pause('chapter_switch');
      }
    }

    logger.info(TAG, `跳转到章节: ${chapterIndex}`);
    
    // 根据电子书格式处理跳转
    this.currentChapterIndex = chapterIndex;
    if (chapterCount > 0) {
      const safeIndex = Math.max(0, Math.min(chapterIndex, chapterCount - 1));
      this.currentChapter = this.ebook.chapters[safeIndex];
    } else {
      this.currentChapter = null;
    }
    this.currentDomPos = ''; // 清空 DOM 位置，从章节开头开始
    if (this.isUsingImagePageReader()) {
      this.imagePageChapterTick++;
      this.updateImagePagePreloadDebugInfo();
      this.refreshCurrentEBookBookmarkState('jump_to_chapter_image_page');
      this.saveReadingProgress();
      return;
    }

    if (this.isUsingMarkdownReader()) {
      this.resetMarkdownChapterContent(0, '', true);
      this.refreshCurrentEBookBookmarkState('jump_to_chapter_markdown');
      logger.info(TAG, `Markdown 阅读器跳转到章节 ${chapterIndex}，内容长度: ${this.markdownContent.length}`);
      return;
    }
    
      // 纯文本阅读器：重置页码到第一页，并更新文本内容
    if (this.isUsingTextReader()) {
      // 更新文本内容（触发 TextReaderComponent 重新分页）
      this.textCurrentPageIndex = 0;
      this.textCurrentPageStartCharIndex = 0;
      this.textCurrentPageEndCharIndex = 0;
      this.textReadAloudCurrentCharIndex = 0;
      this.refreshCurrentEBookBookmarkState('jump_to_chapter_text');
      // 计算全书进度：当前章节索引 / 总章节数 * 100
      this.textContent = this.getTextContent();
      this.updateTextReadAloudContextByPosition();
      logger.info(TAG, `纯文本阅读器跳转到章节 ${chapterIndex}，内容长度: ${this.textContent.length}`);
      // 计算全书进度：当前章节索引 / 总章节数 * 100
      const totalChapters = this.ebook.chapters?.length || 1;
      const overallProgress = (chapterIndex / totalChapters) * 100;
      this.saveTextReadingProgressWithPage(overallProgress, 0);
      if (wasPlaying && readAloudSettings.enabled && readAloudSettings.autoPlayNextChapter) {
        this.readAloudController.start('chapter_switch');
      }
      this.textReadAloudPlaying = this.readAloudController.getSnapshot().playbackState === ReadAloudPlaybackState.PLAYING;
    } else if (this.readerKitController && this.readerKitController.isControllerReady()) {
      // 其他格式：保存阅读进度
      await this.readerKitController.goToChapter(chapterIndex, '');
      this.refreshCurrentEBookBookmarkState('jump_to_chapter_readerkit');
      // 其他格式：保存阅读进度
      this.saveReadingProgress();
    } else {
      this.refreshCurrentEBookBookmarkState('jump_to_chapter_fallback');
      // 其他格式：保存阅读进度
      this.saveReadingProgress();
    }
  }

  /**
  * 调整字体大小
  * 实时更新UI、应用到阅读器并保存到数据库
  */
  private adjustFontSize(delta: number): void {
    const newSize = clampTextReaderFontSize(this.fontSize + delta);
    if (newSize === this.fontSize) {
      return;// 没有变化，不需要更新
    }
    
    this.fontSize = newSize;
    logger.debug(TAG, `字体大小调整为: ${this.fontSize}`);
    
      // 触发 UI 更新
    if (this.textReaderSettings) {
      this.textReaderSettings.textStyle.fontSize = this.fontSize;
      // 触发 UI 更新
      this.textReaderSettings = {
        readingMode: this.textReaderSettings.readingMode,
        readingDirection: this.textReaderSettings.readingDirection,
        pageTurnAnimation: this.textReaderSettings.pageTurnAnimation,
        background: this.textReaderSettings.background,
        savedBackgroundImages: this.textReaderSettings.savedBackgroundImages,
        textStyle: {
          fontSize: this.fontSize,
          lineHeight: this.textReaderSettings.textStyle.lineHeight,
          paragraphSpacing: this.textReaderSettings.textStyle.paragraphSpacing,
          firstLineIndent: this.textReaderSettings.textStyle.firstLineIndent,
          letterSpacing: this.textReaderSettings.textStyle.letterSpacing,
          textColor: this.textReaderSettings.textStyle.textColor,
          fontWeight: this.textReaderSettings.textStyle.fontWeight,
          fontFamily: this.textReaderSettings.textStyle.fontFamily,
          textAlignment: this.textReaderSettings.textStyle.textAlignment
        },
        pageMargins: this.textReaderSettings.pageMargins,
        keepScreenOn: this.textReaderSettings.keepScreenOn,
        lockDeviceOrientation: this.textReaderSettings.lockDeviceOrientation ?? false,
        showPageNumber: this.textReaderSettings.showPageNumber,
        showProgress: this.textReaderSettings.showProgress,
        showTime: this.textReaderSettings.showTime,
        showBattery: this.textReaderSettings.showBattery,
        tapToTurn: this.textReaderSettings.tapToTurn,
        volumeKeyNavigation: this.textReaderSettings.volumeKeyNavigation,
        autoScrollSpeed: this.textReaderSettings.autoScrollSpeed,
        curlBackOpacity: this.textReaderSettings.curlBackOpacity,
        readAloud: this.textReaderSettings.readAloud
      };
    }
    
    // 保存设置到数据库
    this.saveSettings();
  }

  /**
  * 切换工具栏显示状态
  */
  private toggleToolbar(): void {
    if (this.showSettingsPanel || this.showChapterList || this.showMoreMenu) {
      return;
    }
    
    if (this.showTopToolbar) {
      this.hideToolbarWithAnimation();
    } else {
      this.showToolbarWithAnimation();
    }
  }

  /**
  * 显示工具栏（带动画）
  */
  private showToolbarWithAnimation(): void {
    this.captureToolbarSafeArea('show_toolbar');
    this.clearToolbarAutoHideTimer();
    this.showTopToolbar = true;
    this.showBottomToolbar = true;
    
    this.getUIContext().animateTo({
      duration: 250,
      curve: curves.springMotion(0.5, 0.8)
    }, () => {
      this.toolbarOpacity = 1.0;
    });
    this.scheduleToolbarAutoHide('show_toolbar');
  }

  /**
  * 隐藏工具栏（带动画）
  */
  private hideToolbarWithAnimation(): void {
    this.clearToolbarAutoHideTimer();
    this.getUIContext().animateTo({
      duration: 200,
      curve: Curve.EaseOut
    }, () => {
      this.toolbarOpacity = 0.0;
    });
    
    setTimeout(() => {
      this.showTopToolbar = false;
      this.showBottomToolbar = false;
    }, 200);
    this.scheduleFullscreenRestore('hide_toolbar', 240);
  }

  /**
  * 显示更多菜单（带动画）
  */
  private showMoreMenuWithAnimation(): void {
    this.handleReaderOverlayOpening('more_menu_open');
    this.showMoreMenu = true;
    this.getUIContext().animateTo({
      duration: 200,
      curve: curves.springMotion(0.6, 0.9)
    }, () => {
      this.moreMenuOpacity = 1;
      this.moreMenuScale = 1;
      this.moreMenuTranslateY = 0;
    });
  }

  /**
  * 隐藏更多菜单（带动画）
  */
  private hideMoreMenuWithAnimation(): void {
    this.getUIContext().animateTo({
      duration: 150,
      curve: Curve.EaseOut
    }, () => {
      this.moreMenuOpacity = 0;
      this.moreMenuScale = 0.95;
      this.moreMenuTranslateY = -10;
    });
    setTimeout(() => {
      this.showMoreMenu = false;
      this.handleReaderOverlayClosed('more_menu_close');
    }, 150);
  }

  /**
  * 显示章节列表（带动画）
  */
  private showChapterListWithAnimation(): void {
    this.handleReaderOverlayOpening('chapter_list_open');
    logger.info(TAG, `显示章节列表，当前章节索引: ${this.currentChapterIndex}`);
    this.showChapterList = true;
    this.getUIContext().animateTo({
      duration: 250,
      curve: curves.springMotion(0.5, 0.8)
    }, () => {
      this.chapterListOpacity = 1;
    });
    
    // 延迟滚动到当前章节，确保列表已渲染
    setTimeout(() => {
        logger.info(TAG, `滚动命令已执行`);
      try {
        const maxIndex = Math.max(0, (this.ebook?.chapters.length || 1) - 1);
        const safeIndex = Math.max(0, Math.min(this.currentChapterIndex, maxIndex));
        this.chapterListScroller.scrollToIndex(safeIndex, true, ScrollAlign.CENTER);
        logger.info(TAG, `Chapter list positioned to index ${safeIndex}`);
      } catch (error) {
        logger.error(TAG, `滚动失败: ${String(error)}`);
      }
    }, 300);
  }

  /**
  * 隐藏章节列表（带动画）
  */
  private hideChapterListWithAnimation(): void {
    this.getUIContext().animateTo({
      duration: 200,
      curve: Curve.EaseOut
    }, () => {
      this.chapterListOpacity = 0;
    });
    setTimeout(() => {
      this.showChapterList = false;
      this.handleReaderOverlayClosed('chapter_list_close');
    }, 200);
  }

  /**
  * 显示设置面板（带动画）
  */
  private showSettingsPanelWithAnimation(): void {
    this.handleReaderOverlayOpening('settings_panel_open');
    this.showSettingsPanel = true;
    this.getUIContext().animateTo({
      duration: 250,
      curve: curves.springMotion(0.5, 0.8)
    }, () => {
      this.settingsPanelOpacity = 1;
      this.settingsPanelScale = 1;
      this.settingsPanelTranslateY = 0;
    });
  }

  /**
  * 隐藏设置面板（带动画）
  */
  private hideSettingsPanelWithAnimation(): void {
    this.getUIContext().animateTo({
      duration: 200,
      curve: Curve.EaseOut
    }, () => {
      this.settingsPanelOpacity = 0;
      this.settingsPanelScale = 0.95;
      this.settingsPanelTranslateY = 20;
    });
    setTimeout(() => {
      this.showSettingsPanel = false;
      this.handleReaderOverlayClosed('settings_panel_close');
    }, 200);
  }

  /**
  * 显示书籍信息弹窗（带动画）
  */
  private showBookInfoDialogWithAnimation(): void {
    this.handleReaderOverlayOpening('book_info_open');
    this.showBookInfoDialog = true;
    this.getUIContext().animateTo({
      duration: 250,
      curve: curves.springMotion(0.5, 0.8)
    }, () => {
      this.bookInfoDialogOpacity = 1;
    });
  }

  /**
  * 隐藏书籍信息弹窗（带动画）
  */
  private hideBookInfoDialogWithAnimation(): void {
    this.getUIContext().animateTo({
      duration: 200,
      curve: Curve.EaseOut
    }, () => {
      this.bookInfoDialogOpacity = 0;
    });
    setTimeout(() => {
      this.showBookInfoDialog = false;
      this.handleReaderOverlayClosed('book_info_close');
    }, 200);
  }

  /**
  * 显示字体设置面板（带动画）
  */
  private showFontSettingsPanelWithAnimation(): void {
    this.handleReaderOverlayOpening('font_settings_open');
    this.showFontSettingsPanel = true;
    this.getUIContext().animateTo({
      duration: 250,
      curve: curves.springMotion(0.5, 0.8)
    }, () => {
      this.fontSettingsPanelOpacity = 1;
      this.fontSettingsPanelScale = 1;
    });
  }

  /**
  * 隐藏字体设置面板（带动画）
  */
  private hideFontSettingsPanelWithAnimation(): void {
    this.getUIContext().animateTo({
      duration: 200,
      curve: Curve.EaseOut
    }, () => {
      this.fontSettingsPanelOpacity = 0;
      this.fontSettingsPanelScale = 0.95;
    });
    setTimeout(() => {
      this.showFontSettingsPanel = false;
      this.handleReaderOverlayClosed('font_settings_close');
    }, 200);
  }

  /**
  * 显示阅读设置面板（带动画）
  */
  private showReadingOptionsPanelWithAnimation(): void {
    this.handleReaderOverlayOpening('reading_options_open');
    this.showReadingOptionsPanel = true;
    this.getUIContext().animateTo({
      duration: 250,
      curve: curves.springMotion(0.5, 0.8)
    }, () => {
      this.readingOptionsPanelOpacity = 1;
      this.readingOptionsPanelScale = 1;
    });
  }

  /**
  * 隐藏阅读设置面板（带动画）
  */
  private hideReadingOptionsPanelWithAnimation(): void {
    this.getUIContext().animateTo({
      duration: 200,
      curve: Curve.EaseOut
    }, () => {
      this.readingOptionsPanelOpacity = 0;
      this.readingOptionsPanelScale = 0.95;
    });
    setTimeout(() => {
      this.showReadingOptionsPanel = false;
      this.handleReaderOverlayClosed('reading_options_close');
    }, 200);
  }

  /**
  * 返回上一页
  */
  private isHostedByIsolatedReaderAbility(): boolean {
    return this.readerHostMode === READER_ABILITY_HOST_MULTITON;
  }

  private async terminateIsolatedReaderAbility(reason: string): Promise<void> {
    try {
      const hostContext = this.getUIContext()?.getHostContext() as common.UIAbilityContext;
      if (!hostContext) {
        logger.warn(TAG, `独立电子书阅读器退出失败，回退页面栈: reason=${reason}`);
        this.pathStack.pop();
        return;
      }
      logger.info(TAG, `独立电子书阅读器实例退出: reason=${reason}, instanceId=${this.readerInstanceId}`);
      await hostContext.terminateSelf();
    } catch (error) {
      logger.error(TAG, `独立电子书阅读器实例退出异常: ${String(error)}`);
      this.pathStack.pop();
    }
  }

  private async goBack(): Promise<void> {
    try {
      // Build cover component id used by close animation.
      const ebookId: string = this.ebook?.id || '';
      const coverComponentId: string = this.sourceCoverComponentId || (ebookId ? `cover_ebook_lib_${ebookId}` : '');

      if (this.isUsingTextReader()) {
        await this.executeSaveTextReaderSettings();
      }

      // Save progress first, then trigger close transition.
      this.saveReadingProgress();

      if (this.isHostedByIsolatedReaderAbility()) {
        logger.info(TAG, `独立电子书阅读器退出不挂载关闭动画层，封面组件ID: ${coverComponentId}`);
        this.isCloseTransitionNavigating = true;
        cancelTransition();
        await this.terminateIsolatedReaderAbility('go_back_isolated_reader');
        return;
      }

      logger.info(TAG, `触发关闭过渡动画（带截图），封面组件ID: ${coverComponentId}`);
      await startBookCloseTransitionWithComponentId(
        'ebook_reader_root',
        coverComponentId
      );

      // Pop immediately after transition starts so detail page is visible during shrink.
      this.isCloseTransitionNavigating = true;
      this.closeReaderRoute();
    } catch (error) {
      logger.error(TAG, `goBack error: ${error instanceof Error ? error.message : String(error)}`);
      this.isCloseTransitionNavigating = false;
      cancelTransition();
      this.saveReadingProgress();
      if (this.isHostedByIsolatedReaderAbility()) {
        await this.terminateIsolatedReaderAbility('go_back_error');
      } else {
        this.closeReaderRoute();
      }
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


  build() {
    NavDestination() {
      Stack() {
        // 加载完成后，背景由 TextReaderComponent 或 ReaderKitViewerComponent 提供
        // 加载完成后，背景由 TextReaderComponent 或 ReaderKitViewerComponent 提供
        // 内容层 - 占满全屏
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(Color.Transparent)
          .id('guide_ebook_reader_root')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        // 内容层 - 占满全屏
        Column() {
          if (this.isLoading) {
            this.buildLoadingView()
          } else if (this.errorMessage) {
            this.buildErrorView()
          } else if (this.ebook) {
            this.buildReaderView()
          }
        }
        .width('100%')
        .height('100%')
        .onClick(() => {
          if (!this.isUsingTextReader() && !this.isUsingMarkdownReader()) {
            this.toggleToolbar();
          }
        })
        if (this.isRemoteControlled) {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.computer_share_fill'))
              .fontSize(16)
              .fontColor([Color.White])
            Text('被遥控中')
              .fontSize(14)
              .fontColor(Color.White)
          }
          .backgroundColor('rgba(0,0,0,0.6)')
          .borderRadius(16)
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .position({ x: 16, y: 16 })
          .zIndex(100)
        }

        if (this.showTextInteractionOverlay && this.isUsingTextReader()) {
          TextReaderInteractionOverlay({
            params: {
              readerLabel: '鐢靛瓙涔﹂槄璇诲櫒',
              readingMode: this.textReaderSettings.readingMode,
              readingDirection: this.textReaderSettings.readingDirection ?? TextReadingDirection.HORIZONTAL,
              tapToTurn: this.textReaderSettings.tapToTurn,
              componentWidth: this.readerViewportWidth > 0 ? this.readerViewportWidth : 360,
              componentHeight: this.readerViewportHeight > 0 ? this.readerViewportHeight : 780,
              onDismiss: () => {
                this.hideInteractionOverlay();
              }
            }
          })
            .width('100%')
            .height('100%')
            .zIndex(150)
        }

        // 顶部工具栏（悬浮覆盖）
        if (this.showTopToolbar) {
          Column() {
            this.buildTopToolbar()
          }
          .width('100%')
          .align(Alignment.TopStart)
          .position({ x: 0, y: 0 })
          .zIndex(100)
        }

        // 底部工具栏（悬浮覆盖）
        if (this.showBottomToolbar) {
          Column() {
            this.buildBottomToolbar()
          }
          .width('100%')
          .position({ x: 0, y: '100%' })
          .translate({ x: 0, y: '-100%' })
          .zIndex(100)
        }

        // 更多菜单
        if (this.showChapterList && this.ebook) {
          this.buildChapterListPanel()
        }

        // 阅读设置面板（旧的，保留兼容）
        if (this.showMoreMenu) {
          this.buildMoreMenu()
        }

        // 字体设置面板
        if (this.showSettingsPanel && this.ebook) {
          this.buildSettingsPanel()
        }

        // 阅读设置面板（主题等）
        if (this.showFontSettingsPanel && this.ebook) {
          this.buildFontSettingsPanel()
        }

        // 书籍信息弹窗
        if (this.showReadingOptionsPanel && this.ebook) {
          this.buildReadingOptionsPanel()
        }

        // 文本阅读器设置面板（独立渲染，确保在最上层）
        if (this.showBookInfoDialog && this.ebook) {
          this.buildBookInfoDialog()
        }

        // 文本阅读器设置面板（独立渲染，确保在最上层）
        if (this.showTextReaderSettings) {
          this.buildTextReaderSettingsPanel()
        }

        if (this.showReadAloudPanel && this.isUsingTextReader()) {
          ReadAloudSettingsInfoPanel({
            isLandscape: this.isLandscape,
            settings: this.readAloudPanelSettings,
            availability: this.readAloudAvailability,
            voiceOptions: this.readAloudVoiceOptions,
            statusMessage: this.readAloudStatusMessage,
            appFontFamily: this.appFontFamily,
            callbacks: {
              onClose: () => {
                const closeTime = Date.now();
                this.lastReadAloudPanelCloseTime = closeTime;
                this.showReadAloudPanel = false;
                this.handleReaderOverlayClosed('read_aloud_panel_close');
                logger.info(TAG, `关闭听书设置与信息面板: closeAt=${closeTime}`);
              },
              onRefresh: () => {
                this.refreshReadAloudAvailability();
              },
              onChange: (partial: Partial<ReadAloudSettings>) => {
                this.updateReadAloudSettings(partial);
              }
            }
          })
            .zIndex(20000)
        }

        if (this.appGuideStep) {
          AppGuideOverlay({
            visible: this.appGuideStep !== null,
            title: this.appGuideStep.title,
            message: this.appGuideStep.message,
            progressText: this.appGuideManager.getCurrentProgressText(),
            nextButtonText: this.appGuideStep.nextButtonText ?? '下一步',
            cardPosition: this.appGuideStep.cardPosition,
            highlightRect: this.appGuideHighlightRect,
            immersiveMode: true,
            showSkip: this.appGuideStep.showSkip !== false,
            themeState: this.themeState,
            onNext: () => {
              this.handlePageGuideNext();
            },
            onSkip: () => {
              this.handlePageGuideSkip();
            }
          })
        }
      }
      .width('100%')
      .height('100%')
      .id('ebook_reader_root')
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
      .focusable(true)
      .defaultFocus(true)
      .onAreaChange((oldValue: Area, newValue: Area) => {
        // 检测屏幕方向变化
        const newWidth = Number(newValue.width);
        const newHeight = Number(newValue.height);
        if (newWidth <= 0 || newHeight <= 0) {
          return;
        }
        const widthChanged = Math.abs(newWidth - this.readerViewportWidth) > 1;
        const heightChanged = Math.abs(newHeight - this.readerViewportHeight) > 1;
        this.readerViewportWidth = newWidth;
        this.readerViewportHeight = newHeight;
        const newIsLandscape = newWidth > newHeight;
        if (newIsLandscape !== this.isLandscape) {
          this.isLandscape = newIsLandscape;
        }
        this.screenWidth = newWidth;
        if ((widthChanged || heightChanged) && this.isPageVisible) {
          this.scheduleFullscreenRestore('area_change', 120);
          if (this.isUsingTextReader()) {
            this.tryShowQueuedInteractionHint('area_change', 180);
          }
        }
      })
      .onKeyEvent((event: KeyEvent) => {
        if (this.isUsingTextReader()) {
          return;
        }

        if (event.type === KeyType.Up) {
          const consumed = this.handleVolumeKeyPageTurn(event.keyCode);
          if (consumed) {
            event.stopPropagation();
          }
        }
      })
    }
    .onReady((context: NavDestinationContext) => {
      logger.info(TAG, 'EBookReaderPage onReady');
      this.pathStack = context.pathStack;
      this.uiContext = this.getUIContext();
      
      const params = context.pathInfo.param as EBookReaderParams | null;
      if (params && params.bookId) {
        this.sourceCoverComponentId = params.coverComponentId || '';
        this.routerBackOnClose = params.routerBackOnClose === true;
        this.forceReaderKit = params.forceReaderKit === true;
        this.readerHostMode = params.readerHostMode || '';
        this.readerInstanceId = params.readerInstanceId || '';
        this.originImportId = params.originImportId || '';
        this.originImportKind = params.originImportKind || '';
        if (this.isHostedByIsolatedReaderAbility()) {
          PageWindowCoordinator.reapplyPagePolicy('EBookReaderPage', this.uiContext);
          WindowManager.setDisplayMode(DisplayMode.FULL_IMMERSIVE, this.uiContext);
          setTimeout((): void => {
            PageWindowCoordinator.reapplyPagePolicy('EBookReaderPage', this.uiContext ?? undefined);
            WindowManager.setDisplayMode(DisplayMode.FULL_IMMERSIVE, this.uiContext ?? undefined);
          }, 96);
        }
        this.loadEBook(params.bookId);
        // [修复] 跨端接续恢复：读取 wantParam 快照存入待应用状态，由 loadEBook
        // 在本地进度恢复后覆盖为源端位置；命中后才提示用户，避免"显示接续状态却恢复失败"。
        const continuationSessionId = AppStorage.get<string>('continuationSessionId');
        if (continuationSessionId) {
          const snapshot = distributedReadingService.readContinuationSnapshot();
          if (snapshot) {
            this.pendingContinuationChapterIndex = snapshot.chapterIndex;
            this.pendingContinuationPageIndex = snapshot.pageIndex;
            logger.info(TAG, `[Distributed] 接续快照待应用: chapterIndex=${snapshot.chapterIndex}, pageIndex=${snapshot.pageIndex}`);
          } else {
            // 快照缺失：等待分布式数据对象同步（兜底）
            void this.tryRestoreEBookFromDistributedObject();
          }
          // 遥控监听与会话是否命中无关，直接注册
          this.registerRemoteControlListener();
        }
      } else {
        this.errorMessage = '电子书 ID 参数无效';
        logger.error(TAG, '缺少电子书ID参数');
      }
      setTimeout(() => {
        void this.refreshPageGuide('onReady');
      }, 80);
    })
    .hideTitleBar(true)
    .backgroundColor(Color.Transparent)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .onBackPressed(() => {
      // 返回键处理 - 调用 goBack() 触发关闭过渡动画
      this.goBack();
      return true;// 返回 true 表示已处理返回事件
    })
  }

  /**
  * 构建加载视图
  */
  @Builder
  buildLoadingView() {
    Column() {
      LoadingProgress()
        .width(50)
        .height(50)
        .color(Color.White)// 白色加载图标配合黑色背景

      Text('加载中...')
        .fontSize(16)
        .fontColor('rgba(255, 255, 255, 0.8)')  // 白色半透明文字
        .margin({ top: 16 })
        .fontFamily(this.appFontFamily)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(Color.Transparent)// 透明背景，配合翻开动画的黑色底页
    .padding({ top: this.statusBarHeight, bottom: this.navigationBarHeight })
  }

  /**
  * 构建加载视图
  */
  @Builder
  buildErrorView() {
    Column({ space: 16 }) {
      Text('!')
        .fontSize(48)
        .fontFamily(this.appFontFamily)

      Text(this.errorMessage)
        .fontSize(16)
        .fontFamily(this.appFontFamily)
        .fontColor(this.textColor)
        .textAlign(TextAlign.Center)

      Button('返回')
        .fontSize(16)
        .fontFamily(this.appFontFamily)
        .onClick(() => {
          this.closeReaderRoute();
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.bgColor)
    .padding({ top: this.statusBarHeight, bottom: this.navigationBarHeight })
  }

  /**
  * 构建加载视图
  */
  @Builder
  buildReaderView() {
    if (this.ebook) {
      if (this.ebook.format === EBookFormat.PDF) {
        this.buildPdfReaderView();
      } else if (this.isUsingImagePageReader()) {
        this.buildImagePageReaderView();
      } else if (this.isUsingMarkdownReader()) {
        this.buildMarkdownReaderView();
      } else if (this.isReaderKitSupported(this.ebook.format)) {
        this.buildReaderKitView();
      } else {
        this.buildTextReaderView();
      }
    }
  }

  /**
  * 检查格式是否支持 Reader Kit
  */
  private isReaderKitSupported(format: EBookFormat): boolean {
    if (!isReaderKitEnabled()) {
      return false;
    }
    if (this.isKindleFormat(format)) {
      return this.forceReaderKit;
    }
    return format === EBookFormat.EPUB;
  }

  private isTextReaderFormat(format: EBookFormat): boolean {
    return format === EBookFormat.TXT;
  }

  private isMarkdownReaderFormat(format: EBookFormat): boolean {
    return format === EBookFormat.MD;
  }

  /**
  * 检查当前是否使用文本阅读器（TXT纯文本格式）
  */
  private isUsingTextReader(): boolean {
    if (!this.ebook) {
      return false;
    }
    return this.isTextReaderFormat(this.ebook.format);
  }

  private isUsingMarkdownReader(): boolean {
    if (!this.ebook) {
      return false;
    }
    return this.isMarkdownReaderFormat(this.ebook.format);
  }

  private isUsingImagePageReader(): boolean {
    if (!this.ebook) {
      return false;
    }
    if (this.ebook.format !== EBookFormat.EPUB || this.ebook.contentMode !== EBookContentMode.IMAGE_PAGE) {
      return false;
    }
    return this.ebook.chapters.some((chapter: EBookChapter) => {
      return ((chapter.resourceImagePath || '').length > 0) || ((chapter.resourceImageRelativePath || '').length > 0);
    });
  }

  /**
  * 构建加载视图
  */
  @Builder
  buildReaderKitView() {
    if (this.ebook && isReaderKitEnabled()) {
      ReaderKitViewerComponent({
        ebook: this.ebook,
        currentChapterIndex: this.currentChapterIndex,
        initialDomPos: this.currentDomPos,
        readingSettings: this.ebook.readingSettings,
        onProgressChange: (progress: number, domPos: string): void => {
          this.handleProgressChange(progress, domPos);
        },
        onChapterChange: (chapterIndex: number): void => {
          if (!this.ebook || this.ebook.chapters.length <= 0) {
            return;
          }
          const safeChapterIndex = Math.max(0, Math.min(chapterIndex, this.ebook.chapters.length - 1));
          if (safeChapterIndex === this.currentChapterIndex) {
            return;
          }
          this.currentChapterIndex = safeChapterIndex;
          this.currentChapter = this.ebook.chapters[safeChapterIndex];
          this.refreshCurrentEBookBookmarkState('readerkit_chapter_change');
        },
        onControllerReady: (controller: ReaderKitViewerController): void => {
          this.readerKitController = controller;
          if (this.ebook && this.ebook.readingSettings && controller.isControllerReady()) {
            controller.applyReadingSettings(this.ebook.readingSettings, true);
          }
          logger.info(TAG, 'ReaderKit controller is ready');
          this.reportTransitionLoadingProgress(0.96, 'readerkit_controller_ready');
          this.notifyTransitionReaderReadyOnce('readerkit_controller_ready');
        }
      })
      .width('100%')
      .height('100%')
      .onAppear(() => {
        logger.info(TAG, 'ReaderKit 视图已显示');
      })
    }
  }

  /**
  * 构建加载视图
  */
  @Builder
  buildImagePageReaderView() {
    if (this.ebook) {
      if (this.hasRenderableImagePageChapter()) {
        MangaViewer({
          chapter: this.getRenderableImagePageChapter(),
          currentPageIndex: 0,
          readingSettings: this.imagePageReaderSettings,
          zoomScale: 1.0,
          toolbarsVisible: (this.showTopToolbar || this.showBottomToolbar),
          chapterTick: this.imagePageChapterTick,
          preloadCurrentPages: 1,
          preloadNextPages: 1,
          preloadDebugInfo: $imagePagePreloadDebugInfo,
          isFirstChapter: this.currentChapterIndex <= 0,
          isLastChapter: this.currentChapterIndex >= (this.ebook.chapters.length - 1),
          callbacks: {
            onPageChange: (_pageIndex: number) => {
              this.updateImagePagePreloadDebugInfo();
              this.refreshCurrentEBookBookmarkState('image_page_change');
            },
            onChapterChange: (direction: 'prev' | 'next') => {
              if (direction === 'prev') {
                this.previousChapter();
              } else {
                this.nextChapter();
              }
            },
            onZoomChange: (_scale: number) => {},
            onSingleTap: (_event: ClickEvent) => {
              this.toggleToolbar();
            },
            onDoubleTap: (_event: ClickEvent) => {},
            onComponentReady: () => {
              logger.info(TAG, 'Image-page EPUB viewer is ready');
              this.reportTransitionLoadingProgress(0.96, 'image_page_viewer_ready');
              this.notifyTransitionReaderReadyOnce('image_page_viewer_ready');
            }
          }
        })
        .width('100%')
        .height('100%')
        .onAppear(() => {
          this.updateImagePagePreloadDebugInfo();
          logger.info(TAG, 'Image-page EPUB view appeared');
        })
      } else {
        this.buildImagePageFallbackView();
      }
    }
  }

  @Builder
  private buildImagePageFallbackView() {
    Column({ space: 12 }) {
      Text('EPUB 图片页资源未就绪')
        .fontSize(18)
        .fontFamily(this.appFontFamily)
        .fontColor(this.textColor)

      Text('当前章节没有可用的页面图片，暂时无法切换到图片阅读模式。')
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor(this.textColor)
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding(24)
  }

  private buildImagePageMangaChapter(chapterIndex: number): MangaChapter | null {
    if (!this.ebook || chapterIndex < 0 || chapterIndex >= this.ebook.chapters.length) {
      return null;
    }
    const ebookChapter = this.ebook.chapters[chapterIndex];
    const imagePath = this.resolveImagePageChapterPath(ebookChapter);
    if (imagePath.length <= 0) {
      return null;
    }
    const page: MangaPage = {
      id: `${this.ebook.id}_img_${chapterIndex}`,
      index: 0,
      sourceType: ImageSourceType.LOCAL,
      imagePath: imagePath,
      imageUrl: '',
      localPath: imagePath,
      isLoaded: false,
      priority: 10
    };
    return {
      id: ebookChapter.id,
      title: ebookChapter.title,
      chapterNumber: chapterIndex + 1,
      pages: [page],
      totalPages: 1,
      publishDate: this.ebook.addTime || Date.now(),
      language: this.ebook.metadata.language || 'zh-CN',
      scanlationGroup: '',
      isDownloaded: true,
      downloadStatus: DownloadStatus.COMPLETED,
      downloadProgress: 100,
      localPath: imagePath
    };
  }

  private hasRenderableImagePageChapter(): boolean {
    return this.buildImagePageMangaChapter(this.currentChapterIndex) !== null;
  }

  private getRenderableImagePageChapter(): MangaChapter {
    const chapter = this.buildImagePageMangaChapter(this.currentChapterIndex);
    if (!chapter) {
      throw new Error('图片页 EPUB 章节不可渲染');
    }
    return chapter;
  }

  private resolveImagePageChapterPath(chapter: EBookChapter): string {
    if ((chapter.resourceImagePath || '').length > 0) {
      return chapter.resourceImagePath || '';
    }
    const relativePath = chapter.resourceImageRelativePath || '';
    if (!this.ebook || relativePath.length <= 0 || (this.ebook.extractedRootPath || '').length <= 0) {
      return '';
    }
    if (relativePath.startsWith('/')) {
      return relativePath;
    }
    return `${this.ebook.extractedRootPath}/${relativePath}`.replace(/\/+/g, '/');
  }

  private updateImagePagePreloadDebugInfo(): void {
    const total = this.ebook?.chapters.length || 0;
    this.imagePagePreloadDebugInfo = {
      currentPage: this.currentChapterIndex,
      totalPages: total,
      preloadRange: 1,
      queueItems: [],
      completedCount: 0,
      failedCount: 0,
      memCacheHits: 0,
      diskCacheHits: 0,
      networkLoads: 0
    };
  }

  private syncImagePageReaderSettings(): void {
    const keepScreenOn = this.ebook?.readingSettings?.keepScreenOn ?? DEFAULT_READING_SETTINGS.keepScreenOn;
    const volumeKeyNavigation = this.ebook?.readingSettings?.volumeKeyNavigation ?? DEFAULT_READING_SETTINGS.volumeKeyNavigation;
    const brightness = this.ebook?.readingSettings
      ? Math.max(0.1, Math.min(2.0, this.ebook.readingSettings.brightness / 100))
      : DEFAULT_READING_SETTINGS.brightness;
    const showPageInfo = this.ebook?.readingSettings?.showPageNumber ?? DEFAULT_READING_SETTINGS.showPageInfo;
    const showPageIndicator = this.ebook?.readingSettings?.showProgress ?? DEFAULT_READING_SETTINGS.showPageIndicator;
    this.imagePageReaderSettings = {
      readingMode: DEFAULT_READING_SETTINGS.readingMode,
      readingDirection: DEFAULT_READING_SETTINGS.readingDirection,
      brightness: brightness,
      keepScreenOn: keepScreenOn,
      lockDeviceOrientation: this.ebook?.readingSettings?.lockDeviceOrientation ??
        DEFAULT_READING_SETTINGS.lockDeviceOrientation ??
        false,
      lockMode: DEFAULT_READING_SETTINGS.lockMode ?? DEFAULT_READING_SETTINGS.lockOrientation ?? false,
      lockOrientation: DEFAULT_READING_SETTINGS.lockMode ?? DEFAULT_READING_SETTINGS.lockOrientation ?? false,
      pageSpacing: DEFAULT_READING_SETTINGS.pageSpacing,
      showPageInfo: showPageInfo,
      showPageIndicator: showPageIndicator,
      fitMode: 'fit_width',
      autoPageTurnInterval: DEFAULT_READING_SETTINGS.autoPageTurnInterval,
      skipIntroPages: DEFAULT_READING_SETTINGS.skipIntroPages,
      pageTurnAnimation: DEFAULT_READING_SETTINGS.pageTurnAnimation,
      doublePagePortraitLayout: DEFAULT_READING_SETTINGS.doublePagePortraitLayout,
      doublePageVerticalDirection: DEFAULT_READING_SETTINGS.doublePageVerticalDirection,
      filterSettings: DEFAULT_READING_SETTINGS.filterSettings,
      volumeKeyNavigation: volumeKeyNavigation,
      curlBackOpacity: DEFAULT_READING_SETTINGS.curlBackOpacity,
      webtoonLeftMargin: DEFAULT_READING_SETTINGS.webtoonLeftMargin,
      webtoonRightMargin: DEFAULT_READING_SETTINGS.webtoonRightMargin,
      webtoonMarginSync: DEFAULT_READING_SETTINGS.webtoonMarginSync
    };
  }

  private getMarkdownTheme(): MarkdownTheme {
    const settings = this.ebook?.readingSettings;
    if (settings && settings.nightMode) {
      return MarkdownTheme.DARK;
    }
    const bg = (this.bgColor || '').toUpperCase();
    if (bg === '#1E1E1E' || bg === '#1B3B2F' || bg === '#1A237E' || bg === '#000000') {
      return MarkdownTheme.DARK;
    }
    return MarkdownTheme.LIGHT;
  }

  private buildMarkdownReaderStyle(): MarkdownReaderStyle {
    const settings = this.ebook?.readingSettings;
    const style: MarkdownReaderStyle = {
      fontSize: clampTextReaderFontSize(this.fontSize),
      lineHeight: this.lineHeight,
      fontFamily: settings?.fontFamily || this.appFontFamily || 'HarmonyOS Sans',
      fontWeight: settings?.fontWeight || 400,
      textColor: this.textColor,
      backgroundColor: this.bgColor,
      pageMargin: this.pageMargin,
      pageTopMargin: settings?.pageTopMargin ?? (this.pageMargin + 12),
      pageBottomMargin: settings?.pageBottomMargin ?? (this.pageMargin + 28),
      letterSpacing: settings?.letterSpacing ?? 0,
      paragraphSpacing: settings?.paragraphSpacing ?? 8,
      firstLineIndent: settings?.firstLineIndent ?? 0,
      textAlignment: settings?.textAlignment || 'LEFT',
      pageMode: settings?.pageMode || '0',
      pageTurnAnimation: settings?.pageTurnAnimation || 'SLIDE',
      tapToTurn: settings?.tapToTurn ?? true
    };
    return style;
  }

  private applyMarkdownReaderStyle(): void {
    if (this.markdownController && this.markdownController.isControllerReady()) {
      this.markdownController.applyReaderStyle(this.buildMarkdownReaderStyle());
    }
  }

  private handleMarkdownControllerReady(controller: MarkdownViewerController): void {
    this.markdownController = controller;
    this.applyMarkdownReaderStyle();
    logger.info(TAG, 'Markdown viewer controller is ready');
  }

  private resetMarkdownChapterContent(progress: number, headingId: string = '', saveAfterRender: boolean = false): void {
    const safeProgress = Math.max(0, Math.min(100, progress));
    const safeHeadingId = headingId.trim();
    this.markdownChapterProgress = safeProgress;
    this.markdownOverallProgress = this.calculateMarkdownOverallProgress(safeProgress);
    this.markdownCurrentPage = 1;
    this.markdownPageCount = 1;
    this.pendingMarkdownRestoreProgress = safeProgress;
    this.pendingMarkdownHeadingId = safeHeadingId;
    this.pendingMarkdownSaveAfterRender = saveAfterRender;
    this.currentDomPos = this.buildMarkdownDomPos(safeProgress);
    this.markdownContent = this.getTextContent();
  }

  private handleMarkdownRenderComplete(): void {
    const controller = this.markdownController;
    if (controller && controller.isControllerReady()) {
      const restoreProgress = this.pendingMarkdownRestoreProgress >= 0
        ? this.pendingMarkdownRestoreProgress
        : this.markdownChapterProgress;
      const headingId = this.pendingMarkdownHeadingId.trim();
      const shouldSaveAfterRender = this.pendingMarkdownSaveAfterRender;
      this.pendingMarkdownRestoreProgress = -1;
      this.pendingMarkdownHeadingId = '';
      this.pendingMarkdownSaveAfterRender = false;
      setTimeout(() => {
        if (headingId.length > 0) {
          controller.scrollToHeading(headingId);
        } else {
          controller.scrollToProgress(restoreProgress);
        }
        setTimeout(() => {
          const reason = headingId.length > 0 ? 'render_complete_heading' : 'render_complete';
          void this.refreshMarkdownProgressSnapshot(reason).then(() => {
            if (shouldSaveAfterRender) {
              void this.saveReadingProgress();
            }
          });
        }, 220);
      }, 0);
    }
    this.reportTransitionLoadingProgress(0.96, 'markdown_render_complete');
    this.notifyTransitionReaderReadyOnce('markdown_render_complete');
  }

  private async refreshMarkdownProgressSnapshot(reason: string): Promise<void> {
    let snapshot: MarkdownProgressSnapshot = this.createMarkdownProgressSnapshotFromState();
    const controller = this.markdownController;
    if (controller && controller.isControllerReady()) {
      snapshot = await controller.getScrollSnapshot();
    }
    this.applyMarkdownProgressSnapshot(snapshot, reason);
  }

  private async getMarkdownProgressSnapshotForSave(): Promise<MarkdownProgressSnapshot> {
    const controller = this.markdownController;
    if (controller && controller.isControllerReady()) {
      return await controller.getScrollSnapshot();
    }
    return this.createMarkdownProgressSnapshotFromState();
  }

  private applyMarkdownProgressSnapshot(snapshot: MarkdownProgressSnapshot, reason: string): void {
    const chapterProgress = Math.max(0, Math.min(100, snapshot.progress));
    this.markdownChapterProgress = chapterProgress;
    this.markdownOverallProgress = this.calculateMarkdownOverallProgress(chapterProgress);
    this.markdownCurrentPage = Math.max(1, snapshot.currentPage);
    this.markdownPageCount = Math.max(1, snapshot.pageCount);
    this.currentDomPos = this.buildMarkdownDomPos(chapterProgress);
    logger.debug(TAG, `Markdown 进度更新: reason=${reason}, chapterProgress=${chapterProgress.toFixed(1)}%, page=${this.markdownCurrentPage}/${this.markdownPageCount}`);
  }

  private handleMarkdownProgressChange(progress: number): void {
    const chapterProgress = Math.max(0, Math.min(100, progress));
    this.markdownChapterProgress = chapterProgress;
    this.markdownOverallProgress = this.calculateMarkdownOverallProgress(chapterProgress);
    this.currentDomPos = this.buildMarkdownDomPos(chapterProgress);
    this.refreshCurrentEBookBookmarkState('markdown_progress_change');
  }

  private handleMarkdownReaderTap(zone: string): void {
    if (zone === 'center') {
      this.toggleToolbar();
      return;
    }
    const tapToTurn = this.ebook?.readingSettings?.tapToTurn ?? true;
    if (!tapToTurn || this.areReaderMenusVisible()) {
      return;
    }
    this.turnMarkdownPage(zone === 'right');
  }

  private decodeMarkdownAnchor(anchor: string): string {
    const rawAnchor = anchor.startsWith('#') ? anchor.substring(1) : anchor;
    try {
      return decodeURIComponent(rawAnchor);
    } catch {
      return rawAnchor;
    }
  }

  private scrollMarkdownToHeading(headingId: string, reason: string): void {
    const safeHeadingId = headingId.trim();
    if (safeHeadingId.length <= 0) {
      return;
    }
    const controller = this.markdownController;
    if (!controller || !controller.isControllerReady()) {
      this.pendingMarkdownHeadingId = safeHeadingId;
      logger.info(TAG, `Markdown 标题跳转延后执行: reason=${reason}, headingId=${safeHeadingId}`);
      return;
    }
    controller.scrollToHeading(safeHeadingId);
    setTimeout(() => {
      void this.refreshMarkdownProgressSnapshot(reason).then(() => {
        void this.saveReadingProgress();
      });
    }, 260);
  }

  private jumpToMarkdownChapter(chapterIndex: number, headingId: string): void {
    if (!this.ebook || chapterIndex < 0 || chapterIndex >= this.ebook.chapters.length) {
      logger.warn(TAG, `无效的 Markdown 章节跳转: chapterIndex=${chapterIndex}`);
      return;
    }
    const safeHeadingId = headingId.trim();
    if (chapterIndex === this.currentChapterIndex && safeHeadingId.length > 0) {
      this.scrollMarkdownToHeading(safeHeadingId, 'markdown_same_chapter_heading_link');
      return;
    }
    this.currentChapterIndex = chapterIndex;
    this.currentChapter = this.ebook.chapters[chapterIndex];
    this.currentDomPos = '';
    this.resetMarkdownChapterContent(0, safeHeadingId, true);
    this.refreshCurrentEBookBookmarkState(
      safeHeadingId.length > 0 ? 'jump_to_markdown_heading' : 'jump_to_chapter_markdown'
    );
    logger.info(
      TAG,
      `Markdown 阅读器跳转: chapterIndex=${chapterIndex}, headingId=${safeHeadingId || '(top)'}, contentLength=${this.markdownContent.length}`
    );
  }

  private handleMarkdownLinkClick(url: string): void {
    const trimmedUrl = url.trim();
    if (trimmedUrl.startsWith('#')) {
      this.scrollMarkdownToHeading(this.decodeMarkdownAnchor(trimmedUrl), 'markdown_anchor_link');
      return;
    }
    const manualChapterPrefix = 'https://manxia.local/manual/chapter/';
    if (trimmedUrl.startsWith(manualChapterPrefix)) {
      const chapterTextWithAnchor = trimmedUrl.substring(manualChapterPrefix.length);
      const hashIndex = chapterTextWithAnchor.indexOf('#');
      let chapterText = chapterTextWithAnchor;
      let headingId = '';
      if (hashIndex >= 0) {
        chapterText = chapterTextWithAnchor.substring(0, hashIndex);
        headingId = this.decodeMarkdownAnchor(chapterTextWithAnchor.substring(hashIndex + 1));
      }
      const queryIndex = chapterText.indexOf('?');
      if (queryIndex >= 0) {
        chapterText = chapterText.substring(0, queryIndex);
      }
      const chapterIndex = Number(chapterText);
      if (Number.isFinite(chapterIndex)) {
        this.jumpToMarkdownChapter(Math.floor(chapterIndex), headingId);
      }
      return;
    }
    logger.info(TAG, `Markdown 外部链接已拦截: ${trimmedUrl}`);
  }

  private turnMarkdownPage(forward: boolean): boolean {
    const controller = this.markdownController;
    if (!controller || !controller.isControllerReady()) {
      logger.warn(TAG, 'Markdown viewer controller not ready for page turn');
      return false;
    }
    controller.turnPage(forward)
      .then((result: MarkdownPageTurnResult) => {
        this.handleMarkdownPageTurnResult(forward, result);
      })
      .catch((error: Error) => {
        logger.error(TAG, `Markdown 翻页失败: ${error.message}`);
      });
    return true;
  }

  private handleMarkdownPageTurnResult(forward: boolean, result: MarkdownPageTurnResult): void {
    if (result.moved) {
      const snapshot: MarkdownProgressSnapshot = {
        progress: result.progress,
        scrollTop: result.scrollTop,
        maxScrollTop: result.maxScrollTop,
        currentPage: this.markdownCurrentPage,
        pageCount: this.markdownPageCount
      };
      this.applyMarkdownProgressSnapshot(snapshot, 'page_turn');
      void this.refreshMarkdownProgressSnapshot('page_turn_snapshot');
      void this.saveReadingProgress();
      return;
    }
    if (forward && result.boundary === 'end') {
      this.nextChapter();
      return;
    }
    if (!forward && result.boundary === 'start') {
      this.previousChapter();
    }
  }

  @Builder
  buildMarkdownReaderView() {
    if (this.ebook) {
      MarkdownViewerComponent({
        content: this.markdownContent,
        theme: this.getMarkdownTheme(),
        fontSize: clampTextReaderFontSize(this.fontSize),
        readerStyle: this.buildMarkdownReaderStyle(),
        callbacks: {
          onReady: (controller: MarkdownViewerController): void => {
            this.handleMarkdownControllerReady(controller);
          },
          onRenderComplete: (): void => {
            this.handleMarkdownRenderComplete();
          },
          onLinkClick: (url: string): void => {
            this.handleMarkdownLinkClick(url);
          },
          onReaderTap: (zone: string): void => {
            this.handleMarkdownReaderTap(zone);
          },
          onProgressChange: (progress: number): void => {
            this.handleMarkdownProgressChange(progress);
          }
        }
      })
        .width('100%')
        .height('100%')
        .backgroundColor(this.bgColor)
    }
  }

  @Builder
  buildPdfReaderView() {
    if (this.ebook) {
      // 使用 PDF Kit 阅读器组件
      PdfKitViewerComponent({
        ebook: this.ebook,
        readingSettings: this.ebook.readingSettings,
        themeBgColor: this.bgColor,// 传递背景色，响应主题
        onControllerReady: (controller: PdfViewerController): void => {
          this.pdfViewerController = controller;
          logger.info(TAG, 'PDF viewer controller is ready');
        },
        callbacks: {
          onPageChange: (currentPage: number, totalPages: number) => {
            logger.info(TAG, `PDF 页面变化: ${currentPage}/${totalPages}`);
            this.recordPdfReadFlowEvent(
              MangaReadFlowEventType.PAGE_CHANGED,
              'pdf_page_change',
              currentPage - 1,
              totalPages,
              `currentPage=${currentPage}`
            );
            // 保存阅读进度
            this.currentChapterIndex = currentPage - 1;
            if (this.ebook && this.ebook.chapters.length > this.currentChapterIndex) {
              this.currentChapter = this.ebook.chapters[this.currentChapterIndex];
            }
            this.refreshCurrentEBookBookmarkState('pdf_page_change');
            // 保存阅读进度
            this.handlePdfProgressChange(currentPage, totalPages);
          },
          onLoadComplete: (pageCount: number) => {
            logger.info(TAG, `PDF load complete, total pages: ${pageCount}`);
            this.recordPdfReadFlowEvent(
              MangaReadFlowEventType.PAGES_RESOLVED,
              'pdf_load_complete',
              this.currentChapterIndex,
              pageCount,
              `pageCount=${pageCount}`
            );
            this.reportTransitionLoadingProgress(0.96, 'pdf_load_complete');
            this.notifyTransitionReaderReadyOnce('pdf_load_complete');
          },
          onLoadError: (error: string) => {
            logger.error(TAG, `PDF 加载失败: ${error}`);
            this.errorMessage = error;
            this.recordPdfReadFlowError('pdf_load_error', error);
            this.reportTransitionLoadingProgress(0.96, 'pdf_load_error');
            this.notifyTransitionReaderReadyOnce('pdf_load_error');
          }
        } as PdfViewerCallbacks
      })
      .width('100%')
      .height('100%')
    }
  }

  /**
  * 处理 PDF 阅读进度变化
  */
  private handlePdfProgressChange(currentPage: number, totalPages: number): void {
    if (!this.ebook) {
      return;
    }
    if (currentPage <= 0 || totalPages <= 0) {
      this.recordPdfReadFlowGuardRejected(
        'pdf_progress_save_skipped_invalid_page',
        Math.max(0, currentPage - 1),
        Math.max(0, totalPages),
        `currentPage=${currentPage}, totalPages=${totalPages}`
      );
      return;
    }

    // 更新阅读进度
    const progress = totalPages > 0 ? (currentPage / totalPages) * 100 : 0;
    
    // 保存进度
    this.ebook.readingProgress.currentChapterIndex = currentPage - 1;
    this.ebook.readingProgress.progress = progress;
    this.ebook.readingProgress.lastReadTime = Date.now();
    this.refreshCurrentEBookBookmarkState('pdf_progress_change');
    
    // 保存进度
    this.saveReadingProgress();
    this.recordPdfReadFlowEvent(
      MangaReadFlowEventType.PROGRESS_SAVED,
      'pdf_progress_change',
      currentPage - 1,
      totalPages,
      `progress=${progress.toFixed(1)}`
    );
    logger.debug(TAG, `PDF 进度已保存: 第 ${currentPage} 页, ${progress.toFixed(1)}%`);
  }

  /**
  * 构建加载视图
  */
  @Builder
  buildTextReaderView() {
    Stack() {
      // 使用 @State textContent 而不是 getTextContent()，以便章节切换时触发更新
      // 使用 @State textContent 而不是 getTextContent()，以便章节切换时触发更新
      TextReaderComponent({
        content: this.textContent,
        chapters: this.getTextChapters(),
        paginationMode: PaginationMode.ONLINE,
        settings: this.textReaderSettings,
        currentChapterIndex: this.currentChapterIndex,
        currentPageIndex: this.textCurrentPageIndex,
        readAloudCurrentCharIndex: this.textReadAloudCurrentCharIndex,
        readAloudFollowEnabled: this.textReadAloudPlaying,
        readAloudHighlightEnabled: this.textReadAloudPlaying,
        bottomStatusBarHeight: 28,// 底部状态栏高度，避让时间、电量、页码显示区域
        onPageChange: (pageIndex: number, totalPages: number) => {
          this.textCurrentPageIndex = pageIndex;
          this.refreshCurrentEBookBookmarkState('text_reader_page_change');
          this.readAloudController.updatePageIndex(pageIndex);
          this.updateTextReadAloudContextByPosition();
          // 公式: (当前章节索引 + 当前页在章节内的比例) / 总章节数 * 100
          // 公式: (当前章节索引 + 当前页在章节内的比例) / 总章节数 * 100
          const totalChapters = this.ebook?.chapters?.length || 1;
          const chapterProgress = totalPages > 0 ? (pageIndex + 1) / totalPages : 0;
          const overallProgress = ((this.currentChapterIndex + chapterProgress) / totalChapters) * 100;
          logger.debug(TAG, `文本阅读进度: ${overallProgress.toFixed(1)}%`);
          this.saveTextReadingProgressWithPage(overallProgress, pageIndex);
        },
        onPageCharRangeChange: (startCharIndex: number, endCharIndex: number) => {
          this.onTextPageCharRangeChange(startCharIndex, endCharIndex);
        },
        onUserPageTurnStart: () => {
          this.onTextUserPageTurnStart();
        },
        onChapterChange: (chapterIndex: number) => {
          const readAloudSettings = this.getSafeReadAloudSettings(this.textReaderSettings.readAloud);
          const wasPlaying = this.readAloudController.getSnapshot().playbackState === ReadAloudPlaybackState.PLAYING;
          if (wasPlaying && !readAloudSettings.autoPlayNextChapter) {
            this.readAloudController.pause('chapter_switch');
          }
          this.currentChapterIndex = chapterIndex;
          this.currentChapter = this.ebook?.chapters[chapterIndex] || null;
          this.textCurrentPageIndex = 0;
          this.textCurrentPageStartCharIndex = 0;
          this.textCurrentPageEndCharIndex = 0;
          this.textReadAloudCurrentCharIndex = 0;
          this.refreshCurrentEBookBookmarkState('text_reader_chapter_change');
          // 章节切换时更新文本内容
          this.textContent = this.getTextContent();
          this.updateTextReadAloudContextByPosition();
          if (wasPlaying && readAloudSettings.enabled && readAloudSettings.autoPlayNextChapter) {
            this.readAloudController.start('chapter_switch');
          }
          this.textReadAloudPlaying = this.readAloudController.getSnapshot().playbackState === ReadAloudPlaybackState.PLAYING;
        },
        onProgressChange: (progress: number) => {
          logger.debug(TAG, `文本阅读进度: ${progress.toFixed(1)}%`);
          // 文本阅读器分页完成，通知过渡动画阅读器就绪
        },
        onTapCenter: () => {
          this.toggleToolbar();
        },
        onReady: () => {
          // 文本阅读器分页完成，通知过渡动画阅读器就绪
          logger.info(TAG, '📖 文本阅读器分页完成，通知过渡动画');
          this.reportTransitionLoadingProgress(0.96, 'text_reader_ready');
          this.notifyTransitionReaderReadyOnce('text_reader_ready');
          this.queueInteractionHintIfNeeded(this.textReaderSettings);
          this.tryShowQueuedInteractionHint('text_reader_ready', 120);
        }
      })
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }
  
  /**
  * 获取文本内容（合并所有章节或当前章节）
  */
  private getTextContent(): string {
    if (!this.ebook) {
      return '';
    }
    
    // 否则合并所有章节内容
    if (this.currentChapter && this.currentChapter.content) {
      return this.currentChapter.content;
    }
    
    // 否则合并所有章节内容
    return this.ebook.chapters.map(chapter => {
      return `${chapter.title}\n\n${chapter.content}`;
    }).join('\n\n');
  }

  /**
  * 检查电子书是否有有效封面
  */
  private hasValidEBookCover(): boolean {
    const raw = this.ebook?.metadata?.coverImagePath || '';
    return raw.length > 0;
  }

  /**
  * 获取电子书封面图片源
  * 支持本地文件路径、网络URL和应用资源路径
  */
  private getEBookCoverSource(): ResourceStr {
    const raw = this.ebook?.metadata?.coverImagePath || '';
    if (raw.length === 0) {
      return $r('app.media.ic_ebook');
    }
    
    // 检查是否为应用资源路径 (app.media.xxx)
    if (raw.startsWith('app.media.')) {
      const resourceName = raw.substring('app.media.'.length);
      if (resourceName === 'mangabook') {
        return $r('app.media.mangabook');
      } else if (resourceName === 'ic_ebook') {
        return $r('app.media.ic_ebook');
      } else if (resourceName === 'icon') {
        return $r('app.media.icon');
      }
      return $r('app.media.ic_ebook');
    }
    
    // 本地文件路径
    if (raw.startsWith('/')) {
      return `file://${raw}`;
    }
    
    return raw;
  }
  
  /**
  * 获取文本章节列表（用于 TextReaderComponent）
  */
  private getTextChapters(): TextChapter[] {
    if (!this.ebook) {
      return [];
    }
    
    const result: TextChapter[] = [];
    for (let i = 0; i < this.ebook.chapters.length; i++) {
      const ch = this.ebook.chapters[i];
      const chapter: TextChapter = {
        id: ch.id,
        title: ch.title,
        index: i,
        content: ch.content || '',
        wordCount: ch.wordCount || (ch.content || '').length,
        startPosition: 0,
        endPosition: (ch.content || '').length
      };
      result.push(chapter);
    }
    return result;
  }
  
  /**
  * 保存文本阅读进度（带页码参数）
  * 对于 TXT 阅读器，使用 currentPosition 保存页码，domPos 保存页码字符串
  */
  private async saveTextReadingProgressWithPage(progress: number, pageIndex: number): Promise<void> {
    if (!this.ebook) {
      return;
    }
    
    // 互斥锁：如果正在保存，跳过本次请求
    if (this.isSavingProgress) {
      logger.debug(TAG, 'Progress save in progress, skip duplicate request');
      return;
    }
    
    this.isSavingProgress = true;
    
    // 记录最新进度，避免退出时被旧值覆盖
    this.latestTextProgress = progress;
    const totalReadingTime = this.ebook.readingProgress?.totalReadingTime ?? 0;
    
    try {
      const readingProgress: EBookReadingProgress = {
        bookId: this.ebook.id,
        currentChapterId: this.currentChapter?.id || '',
        currentChapterIndex: this.currentChapterIndex,
        currentPosition: pageIndex,// 保存当前页码
        domPos: this.buildTextDomPos(pageIndex),// 同时记录页码与听书字符位置
        progress: progress,
        lastReadTime: Date.now(),
        totalReadingTime: totalReadingTime
      };
      
      await this.ebookDataManager.saveReadingProgress(readingProgress);
      if (this.ebook.readingProgress) {
        this.ebook.readingProgress.currentChapterId = readingProgress.currentChapterId;
        this.ebook.readingProgress.currentChapterIndex = readingProgress.currentChapterIndex;
        this.ebook.readingProgress.currentPosition = readingProgress.currentPosition;
        this.ebook.readingProgress.domPos = readingProgress.domPos;
        this.ebook.readingProgress.progress = readingProgress.progress;
        this.ebook.readingProgress.lastReadTime = readingProgress.lastReadTime;
        this.ebook.readingProgress.totalReadingTime = readingProgress.totalReadingTime;
      }
      distributedReadingService.syncProgress(
        this.ebook.id,
        this.currentChapterIndex,
        pageIndex,
        this.textCurrentPageStartCharIndex,
        'ebook'
      );
      logger.debug(TAG, `保存文本阅读进度: 章节=${this.currentChapterIndex}, 页码=${pageIndex}, 进度=${progress.toFixed(1)}%`);
    } catch (error) {
      logger.error(TAG, `保存文本阅读进度失败: ${String(error)}`);
    } finally {
      this.isSavingProgress = false;
    }
  }
  
  /**
  * 保存文本阅读进度（使用当前状态）
  * @deprecated 使用 saveTextReadingProgressWithPage 替代
  */
  private async saveTextReadingProgress(progress: number): Promise<void> {
    await this.saveTextReadingProgressWithPage(progress, this.textCurrentPageIndex);
  }
  
  /**
  * 构建加载视图
  */
  @Builder
  buildTextReaderSettingsPanel() {
    Stack() {
      // 遮罩
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.background_overlay'))
        .opacity(0.5 * this.textReaderSettingsOpacity)
        .onClick(() => {
          this.hideTextReaderSettingsWithAnimation();
        })
      
      // 设置面板
      Column() {
        TextReaderSettingsPanel({
          settings: this.textReaderSettings,
          isLandscape: this.isLandscape,
          onClose: () => {
            this.hideTextReaderSettingsWithAnimation();
          },
          onSettingsChange: (settings: TextReaderSettings) => {
            const previousHintKey = this.getInteractionHintKey(this.textReaderSettings);
            settings.readAloud = this.getSafeReadAloudSettings(settings.readAloud);
            const nextSettings: TextReaderSettings = JSON.parse(JSON.stringify(settings));
            this.textReaderSettings = nextSettings;
            if (previousHintKey !== this.getInteractionHintKey(settings)) {
              this.queueInteractionHintIfNeeded(settings);
            }
            this.syncDeviceOrientationLock('text_settings_change');
            this.queueTextReaderSettingsSave();
            this.syncTextReadAloudContext();
            this.persistGlobalReadAloudSettings(this.getSafeReadAloudSettings(settings.readAloud));
          }
        })
      }
      .width(this.isLandscape ? '50%' : '95%')
      .height(this.isLandscape ? '100%' : '80%')
      .constraintSize({ maxWidth: 450, minWidth: 320 })
      .backgroundColor(this.themeManager.getGlassBackgroundResource())
      .backgroundBlurStyle(this.themeManager.getGlassBlurStyle())
      .borderRadius(this.isLandscape ? 0 : 16)
      .opacity(this.textReaderSettingsOpacity)
      .scale({ x: this.textReaderSettingsScale, y: this.textReaderSettingsScale })
      .clip(true)
    }
    .width('100%')
    .height('100%')
    .alignContent(this.isLandscape ? Alignment.End : Alignment.Center)
    .zIndex(1300)
  }
  
  /**
  * 显示文本阅读器设置（带动画）
  */
  private showTextReaderSettingsWithAnimation(): void {
    this.handleReaderOverlayOpening('text_reader_settings_open');
    this.showTextReaderSettings = true;
    this.getUIContext().animateTo({
      duration: 250,
      curve: curves.springMotion(0.5, 0.8)
    }, () => {
      this.textReaderSettingsOpacity = 1;
      this.textReaderSettingsScale = 1;
    });
  }
  
  /**
  * 隐藏文本阅读器设置（带动画）
  */
  private hideTextReaderSettingsWithAnimation(): void {
    this.getUIContext().animateTo({
      duration: 200,
      curve: Curve.EaseOut
    }, () => {
      this.textReaderSettingsOpacity = 0;
      this.textReaderSettingsScale = 0.95;
    });
    setTimeout(() => {
      this.showTextReaderSettings = false;
      this.handleReaderOverlayClosed('text_reader_settings_close');
    }, 200);
  }
  
  /**
  * 保存文本阅读器设置
  * 将 TextReaderSettings 转换为 EBookReadingSettings 并保存到数据库
  */
  private textSettingsSaveTimeoutId: number = -1;

  private queueTextReaderSettingsSave(): void {
    if (this.textSettingsSaveTimeoutId !== -1) {
      clearTimeout(this.textSettingsSaveTimeoutId);
    }
    this.textSettingsSaveTimeoutId = setTimeout(() => {
      this.textSettingsSaveTimeoutId = -1;
      void this.executeSaveTextReaderSettings();
    }, 500);
  }

  private async executeSaveTextReaderSettings(): Promise<void> {
    if (!this.ebook) {
      return;
    }

    try {
      // 从 textReaderSettings 同步到 ebook.readingSettings
      if (!this.ebook.readingSettings) {
        this.ebook.readingSettings = DEFAULT_EBOOK_READING_SETTINGS;
      }

      // 字体设置
      const settings = this.ebook.readingSettings;
      
      // 字体设置
      settings.fontSize = this.textReaderSettings.textStyle.fontSize;
      settings.lineHeight = this.textReaderSettings.textStyle.lineHeight;
      settings.fontWeight = this.textReaderSettings.textStyle.fontWeight;
      settings.letterSpacing = this.textReaderSettings.textStyle.letterSpacing;
      settings.paragraphSpacing = this.textReaderSettings.textStyle.paragraphSpacing;
      settings.firstLineIndent = this.textReaderSettings.textStyle.firstLineIndent;
      settings.textAlignment = this.textReaderSettings.textStyle.textAlignment;
      settings.textColor = this.textReaderSettings.textStyle.textColor;
      
      // 用户设置了自定义背景，禁用跟随系统主题
      settings.backgroundType = this.textReaderSettings.background.type;
      settings.backgroundColor = this.textReaderSettings.background.color || '#F5F0E1';
      settings.backgroundImagePath = this.textReaderSettings.background.imagePath || '';
      settings.backgroundImageOpacity = this.textReaderSettings.background.imageOpacity || 1.0;
      
      // 翻页设置
      settings.followSystemTheme = false;
      
      // 显示设置
      settings.pageMargin = this.textReaderSettings.pageMargins.left;
      settings.pageTurnAnimation = this.textReaderSettings.pageTurnAnimation;
      settings.tapToTurn = this.textReaderSettings.tapToTurn;
      settings.volumeKeyNavigation = this.textReaderSettings.volumeKeyNavigation;
      settings.keepScreenOn = this.textReaderSettings.keepScreenOn;
      settings.lockDeviceOrientation = this.textReaderSettings.lockDeviceOrientation ?? false;
      this.updateVolumeKeyListener();
      
      // 保存到数据库
      settings.showPageNumber = this.textReaderSettings.showPageNumber;
      settings.showProgress = this.textReaderSettings.showProgress;
      settings.showTime = this.textReaderSettings.showTime;
      settings.showBattery = this.textReaderSettings.showBattery;

      // 保存到数据库
      await this.ebookDataManager.saveReadingSettings(this.ebook.id, settings);
      logger.info(TAG, `文本阅读器设置已保存: volumeKeyNavigation=${settings.volumeKeyNavigation}, bgType=${settings.backgroundType}, bgColor=${settings.backgroundColor}, textColor=${settings.textColor}, bgImagePath=${settings.backgroundImagePath}`);
    } catch (error) {
      logger.error(TAG, `保存文本阅读器设置失败: ${String(error)}`);
    }
  }

  /**
   * 添加当前电子书书签
   */
  private parseReaderKitPositionSnapshotFromDomPos(domPos: string): ReaderKitPositionSnapshot | null {
    if (domPos.length <= 0 || !domPos.startsWith('{')) {
      return null;
    }
    try {
      const rawData = SafeUtils.parseObj(domPos) as Record<string, number | string>;
      const resourceIndexValue = rawData['resourceIndex'];
      const resourceCountValue = rawData['resourceCount'];
      const totalResourceCountValue = rawData['totalResourceCount'];
      const pageOffsetValue = rawData['pageOffset'];
      const startDomPosValue = rawData['startDomPos'];
      const endDomPosValue = rawData['endDomPos'];
      const dataIdValue = rawData['dataId'];
      const rawResourceCount = (typeof resourceCountValue === 'number' && Number.isFinite(resourceCountValue) && resourceCountValue > 0)
        ? resourceCountValue
        : ((typeof totalResourceCountValue === 'number' && Number.isFinite(totalResourceCountValue) && totalResourceCountValue > 0)
            ? totalResourceCountValue
            : -1);
      return {
        resourceIndex: (typeof resourceIndexValue === 'number' && Number.isFinite(resourceIndexValue) && resourceIndexValue >= 0)
          ? Math.floor(resourceIndexValue)
          : -1,
        resourceCount: rawResourceCount > 0 ? Math.floor(rawResourceCount) : -1,
        pageOffset: (typeof pageOffsetValue === 'number' && Number.isFinite(pageOffsetValue) && pageOffsetValue >= 0)
          ? Math.floor(pageOffsetValue)
          : -1,
        startDomPos: typeof startDomPosValue === 'string' ? startDomPosValue : '',
        endDomPos: typeof endDomPosValue === 'string' ? endDomPosValue : '',
        dataId: typeof dataIdValue === 'string' ? dataIdValue : ''
      };
    } catch (_error) {
      return null;
    }
  }

  private parseReaderKitPositionSnapshot(): ReaderKitPositionSnapshot | null {
    if (this.isUsingTextReader() || this.isUsingMarkdownReader() || this.isUsingImagePageReader()) {
      return null;
    }
    return this.parseReaderKitPositionSnapshotFromDomPos(this.currentDomPos);
  }

  private clearReaderKitStartupGuard(reason: string): void {
    if (this.readerKitStartupGuardActive) {
      logger.info(TAG, `ReaderKit 启动进度保护结束: ${reason}`);
    }
    this.readerKitStartupGuardActive = false;
    this.readerKitStartupGuardStartTime = 0;
    this.readerKitStartupExpectedChapterIndex = -1;
    this.readerKitStartupExpectedPageOffset = -1;
  }

  private hasReaderKitDomAnchor(snapshot: ReaderKitPositionSnapshot | null): boolean {
    if (!snapshot) {
      return false;
    }
    return snapshot.startDomPos.length > 0 || snapshot.endDomPos.length > 0;
  }

  private initReaderKitStartupGuard(persistedPageOffset: number): void {
    this.clearReaderKitStartupGuard('reinit');
    if (!this.ebook || this.isUsingTextReader() || this.isUsingMarkdownReader() || this.isUsingImagePageReader() || !this.isReaderKitSupported(this.ebook.format)) {
      return;
    }
    if (!Number.isFinite(persistedPageOffset) || persistedPageOffset <= 0) {
      return;
    }
    this.readerKitStartupGuardActive = true;
    this.readerKitStartupGuardStartTime = Date.now();
    this.readerKitStartupExpectedChapterIndex = Math.max(0, this.currentChapterIndex);
    this.readerKitStartupExpectedPageOffset = Math.floor(persistedPageOffset);
    logger.warn(TAG, `启用 ReaderKit 启动进度保护: chapter=${this.readerKitStartupExpectedChapterIndex}, pageOffset=${this.readerKitStartupExpectedPageOffset}`);
  }

  private shouldSkipReaderKitStartupRegression(snapshot: ReaderKitPositionSnapshot | null): boolean {
    if (!this.readerKitStartupGuardActive) {
      return false;
    }

    const elapsed = Date.now() - this.readerKitStartupGuardStartTime;
    if (elapsed > EBookReaderPage.READERKIT_STARTUP_GUARD_WINDOW_MS) {
      this.clearReaderKitStartupGuard('timeout');
      return false;
    }

    if (!snapshot) {
      return false;
    }

    if (snapshot.resourceIndex >= 0 && snapshot.resourceIndex !== this.readerKitStartupExpectedChapterIndex) {
      this.clearReaderKitStartupGuard(`chapter_changed_${snapshot.resourceIndex}`);
      return false;
    }

    if (snapshot.pageOffset >= this.readerKitStartupExpectedPageOffset && this.readerKitStartupExpectedPageOffset > 0) {
      this.clearReaderKitStartupGuard(`restored_page_${snapshot.pageOffset}`);
      return false;
    }

    if (snapshot.pageOffset >= 0 && snapshot.pageOffset < this.readerKitStartupExpectedPageOffset) {
      logger.warn(TAG, `ReaderKit 启动进度保护: 忽略 pageOffset=${snapshot.pageOffset} 覆盖，期望页>=${this.readerKitStartupExpectedPageOffset}`);
      return true;
    }

    return false;
  }

  private getCurrentReaderKitChapterIndex(): number {
    const snapshot = this.parseReaderKitPositionSnapshot();
    if (snapshot && snapshot.resourceIndex >= 0) {
      return snapshot.resourceIndex;
    }
    return Math.max(0, this.currentChapterIndex);
  }

  private getCurrentReaderKitPageIndex(): number {
    if (this.isUsingImagePageReader()) {
      return 0;
    }
    const snapshot = this.parseReaderKitPositionSnapshot();
    if (snapshot && snapshot.pageOffset >= 0) {
      return snapshot.pageOffset;
    }
    const persistedPosition = this.ebook?.readingProgress?.currentPosition;
    if (typeof persistedPosition === 'number' && Number.isFinite(persistedPosition) && persistedPosition >= 0) {
      return Math.floor(persistedPosition);
    }
    return 0;
  }

  private getCurrentEBookProgressPercent(): number {
    if (this.isUsingTextReader() && (this.latestTextProgress > 0 || this.textReadAloudCurrentCharIndex >= 0)) {
      return Math.max(0, Math.min(100, this.latestTextProgress));
    }
    if (this.isUsingImagePageReader()) {
      const total = this.ebook?.chapters.length || 0;
      if (total <= 0) {
        return 0;
      }
      return Math.max(0, Math.min(100, ((this.currentChapterIndex + 1) / total) * 100));
    }
    if (this.isUsingMarkdownReader()) {
      return Math.max(0, Math.min(100, this.markdownOverallProgress));
    }
    const snapshot = this.parseReaderKitPositionSnapshot();
    if (snapshot && snapshot.resourceIndex >= 0 && snapshot.resourceCount > 0) {
      const percent = ((snapshot.resourceIndex + 1) / snapshot.resourceCount) * 100;
      return Math.max(0, Math.min(100, percent));
    }
    const rawProgress = this.ebook?.readingProgress?.progress;
    if (typeof rawProgress !== 'number' || !Number.isFinite(rawProgress) || rawProgress < 0) {
      return this.isUsingTextReader() ? 0 : -1;
    }
    return Math.max(0, Math.min(100, rawProgress));
  }

  private getReaderKitResourceCountForNavigation(): number {
    const snapshot = this.parseReaderKitPositionSnapshot();
    if (snapshot && snapshot.resourceCount > 0) {
      return snapshot.resourceCount;
    }
    return this.ebook?.chapters.length || 0;
  }

  private getReaderKitProgressSliderValue(): number {
    const progress = this.getCurrentEBookProgressPercent();
    if (progress >= 0) {
      return progress;
    }
    // 当总资源数未知时，使用当前 resourceIndex 作为滑条值，避免始终显示 0
    return Math.max(0, Math.min(100, this.getCurrentReaderKitChapterIndex()));
  }

  private async handleReaderKitProgressSliderEnd(rawValue: number): Promise<void> {
    if (!this.ebook || this.isUsingTextReader() || this.isUsingMarkdownReader() || !this.isReaderKitSupported(this.ebook.format)) {
      return;
    }
    const resourceCount = this.getReaderKitResourceCountForNavigation();
    const normalized = Math.max(0, Math.min(100, rawValue));
    const currentIndex = this.getCurrentReaderKitChapterIndex();
    let targetIndex = currentIndex;
    if (resourceCount > 1) {
      targetIndex = Math.max(0, Math.min(resourceCount - 1, Math.round((normalized / 100) * (resourceCount - 1))));
    } else {
      // 回退：Reader Kit 未返回总章节时，直接将滑条值视为 resourceIndex
      targetIndex = Math.round(normalized);
      logger.warn(TAG, `进度总量未知，使用 resourceIndex 回退跳转: value=${normalized}, targetIndex=${targetIndex}`);
    }
    if (targetIndex === currentIndex) {
      return;
    }
    await this.jumpToChapter(targetIndex);
  }

  private getBottomToolbarChapterTitle(): string {
    if (this.isUsingTextReader() || this.isUsingMarkdownReader()) {
      return this.currentChapter?.title || `第${this.currentChapterIndex + 1}章`;
    }
    const chapterIndex = this.getCurrentReaderKitChapterIndex();
    const chapterTitle = this.ebook?.chapters[chapterIndex]?.title || '';
    if (chapterTitle.trim().length > 0) {
      return chapterTitle;
    }
    return `第${chapterIndex + 1}章`;
  }

  private getBottomToolbarStatusText(): string {
    if (this.isUsingTextReader()) {
      return `${this.currentChapterIndex + 1} / ${this.ebook?.chapters.length || 0}`;
    }
    if (this.isUsingMarkdownReader()) {
      const total = this.ebook?.chapters.length || 0;
      const progressPercent = this.getCurrentEBookProgressPercent();
      return `${Math.round(progressPercent)}% · 章节 ${this.currentChapterIndex + 1} / ${total} · 页 ${this.markdownCurrentPage} / ${this.markdownPageCount}`;
    }
    if (this.isUsingImagePageReader()) {
      const total = this.ebook?.chapters.length || 0;
      const progressPercent = this.getCurrentEBookProgressPercent();
      return `${Math.round(progressPercent)}% 路 页面 ${this.currentChapterIndex + 1} / ${total}`;
    }
    const snapshot = this.parseReaderKitPositionSnapshot();
    const chapterIndex = this.getCurrentReaderKitChapterIndex();
    const pageIndex = this.getCurrentReaderKitPageIndex();
    const fallbackChapterCount = this.ebook?.chapters.length || 0;
    const chapterCount = (snapshot && snapshot.resourceCount > 0)
      ? snapshot.resourceCount
      : (fallbackChapterCount > 1 ? fallbackChapterCount : 0);
    const chapterText = chapterCount > 0
      ? `章节 ${chapterIndex + 1} / ${chapterCount}`
      : `章节 ${chapterIndex + 1}`;
    const progressPercent = this.getCurrentEBookProgressPercent();
    if (progressPercent < 0) {
      return `${chapterText} · 页 ${pageIndex + 1}`;
    }
    return `${Math.round(progressPercent)}% · ${chapterText} · 页 ${pageIndex + 1}`;
  }

  private getCurrentEBookBookmarkContext(): EBookBookmarkContext | null {
    if (!this.ebook) {
      return null;
    }
    const isTextMode = this.isUsingTextReader();
    const isMarkdownMode = this.isUsingMarkdownReader();
    const readerKitSnapshot = this.parseReaderKitPositionSnapshot();
    const chapterIndex = (isTextMode || isMarkdownMode)
      ? Math.max(0, this.currentChapterIndex)
      : (readerKitSnapshot && readerKitSnapshot.resourceIndex >= 0
          ? readerKitSnapshot.resourceIndex
          : Math.max(0, this.currentChapterIndex));
    const resolvedChapter = this.ebook.chapters[chapterIndex];
    const chapterTitle = (isTextMode || isMarkdownMode)
      ? (this.currentChapter?.title || `第${chapterIndex + 1}章`)
      : (resolvedChapter?.title || `第${chapterIndex + 1}章`);
    const chapterId = (isTextMode || isMarkdownMode)
      ? (this.currentChapter?.id || '')
      : (resolvedChapter?.id || `resource_${chapterIndex}`);
    const pageIndex = isTextMode
      ? Math.max(0, this.textCurrentPageIndex)
      : (isMarkdownMode ? Math.max(0, this.markdownCurrentPage - 1) : this.getCurrentReaderKitPageIndex());
    const rawProgress = this.isUsingImagePageReader()
      ? this.getCurrentEBookProgressPercent()
      : (isMarkdownMode ? this.markdownOverallProgress : this.ebook.readingProgress?.progress);
    const progress = (typeof rawProgress === 'number' && Number.isFinite(rawProgress) && rawProgress >= 0)
      ? Math.max(0, Math.min(1, rawProgress / 100))
      : -1;
    return {
      chapterId,
      chapterTitle,
      chapterIndex,
      pageIndex,
      progress,
      startOffset: isTextMode ? Math.max(0, this.textCurrentPageStartCharIndex) : -1,
      endOffset: isTextMode ? Math.max(0, this.textCurrentPageEndCharIndex) : -1,
      isTextMode
    };
  }

  private buildEBookBookmarkTitle(context: EBookBookmarkContext): string {
    return `${context.chapterTitle} · P${context.pageIndex + 1}`;
  }

  private buildCurrentEBookBookmarkAnchor(context: EBookBookmarkContext): AnnotationAnchor {
    return {
      chapterId: context.chapterId,
      chapterTitle: context.chapterTitle,
      chapterIndex: context.chapterIndex,
      pageIndex: context.pageIndex,
      progress: context.progress,
      startOffset: context.startOffset,
      endOffset: context.endOffset
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
      for (let i = 0; i < bookmarks.length; i++) {
        const item = bookmarks[i];
        if (item.pageIndex >= 0 && item.pageIndex === context.pageIndex) {
          matchedId = item.id;
          break;
        }
        if (
          context.isTextMode &&
          context.endOffset > context.startOffset &&
          item.startOffset >= 0 &&
          item.endOffset >= 0
        ) {
          const itemStart = Math.max(0, Math.floor(item.startOffset));
          const itemEnd = Math.max(itemStart + 1, Math.floor(item.endOffset));
          if (itemStart < context.endOffset && itemEnd > context.startOffset) {
            matchedId = item.id;
            break;
          }
        }
      }
      this.currentPageBookmarkId = matchedId;
      this.isCurrentPageBookmarked = matchedId.length > 0;
      logger.debug(
        TAG,
        `刷新电子书书签状态: 触发源=${trigger}, 章节索引=${context.chapterIndex}, 页索引=${context.pageIndex}, 已加书签=${this.isCurrentPageBookmarked}, 书签ID=${matchedId || '无'}`
      );
    } catch (error) {
      logger.error(TAG, `刷新电子书书签状态失败: 触发源=${trigger}, 错误=${String(error)}`);
      this.currentPageBookmarkId = '';
      this.isCurrentPageBookmarked = false;
    }
  }

  private async createCurrentEBookBookmark(): Promise<void> {
    if (!this.ebook) {
      this.getUIContext().getPromptAction().showToast({ message: '电子书信息未就绪' });
      return;
    }
    const context = this.getCurrentEBookBookmarkContext();
    if (!context) {
      this.getUIContext().getPromptAction().showToast({ message: '电子书信息未就绪' });
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
      logger.info(
        TAG,
        `电子书书签添加成功: chapterIndex=${context.chapterIndex}, pageIndex=${context.pageIndex}, bookmarkId=${bookmark.id}`
      );
    } catch (error) {
      logger.error(TAG, `添加电子书书签失败: ${String(error)}`);
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
      this.getUIContext().getPromptAction().showToast({ message: '当前页暂无书签' });
      return;
    }
    try {
      await this.annotationManager.deleteAnnotation(bookmarkId);
      this.currentPageBookmarkId = '';
      this.isCurrentPageBookmarked = false;
      this.getUIContext().getPromptAction().showToast({ message: '书签已移除' });
      logger.info(TAG, `电子书书签移除成功: bookmarkId=${bookmarkId}`);
    } catch (error) {
      logger.error(TAG, `移除电子书书签失败: ${String(error)}`);
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

  private addCurrentEBookBookmark(): void {
    this.toggleCurrentEBookBookmark();
  }

  private openCurrentEBookAnnotationCenter(): void {
    if (!this.ebook) {
      this.getUIContext().getPromptAction().showToast({ message: '电子书信息未就绪' });
      return;
    }
    const bookmarkContext = this.getCurrentEBookBookmarkContext();
    const chapterIndex = bookmarkContext ? bookmarkContext.chapterIndex : this.currentChapterIndex;
    const pageIndex = bookmarkContext
      ? bookmarkContext.pageIndex
      : (this.isUsingTextReader()
        ? this.textCurrentPageIndex
        : (this.isUsingMarkdownReader() ? Math.max(0, this.markdownCurrentPage - 1) : this.getCurrentReaderKitPageIndex()));
    const params: AnnotationCenterPageParams = {
      contentType: UnifiedContentType.EBOOK,
      contentId: this.ebook.id,
      contentTitle: this.ebook.metadata.title || '',
      readerContext: {
        ebook: {
          chapterIndex: chapterIndex,
          pageIndex: pageIndex,
          startOffset: bookmarkContext && bookmarkContext.startOffset >= 0 ? bookmarkContext.startOffset : undefined
        }
      }
    };
    try {
      PageWindowCoordinator.navigateWithManagedTransition(
        'EBookReaderPage',
        'AnnotationCenterPage',
        () => {
          try {
            this.pathStack.pushPathByName('AnnotationCenterPage', params);
          } catch (error) {
            logger.error(TAG, `打开灵感页面失败: ${String(error)}`);
            this.getUIContext().getPromptAction().showToast({ message: '打开灵感页面失败' });
          }
        },
        this.getUIContext()
      );
    } catch (error) {
      logger.error(TAG, `启动灵感页面过渡失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: '打开灵感页面失败' });
    }
  }

  @Builder
  buildTopToolbar() {
    Row() {
            // 只在用户释放滑块时触发章节切换，避免拖动过程中频繁触发分页导致卡死
      Button() {
        SymbolGlyph($r('sys.symbol.arrow_left'))
          .fontColor([$r('app.color.text_primary')])
      }
      .width(48)
      .height(48)
      .backgroundColor(Color.Transparent)
      .onClick(() => this.goBack())

      // 控制按钮区域 - 根据阅读器类型显示不同按钮
      Text(this.ebook?.metadata.title || '电子书阅读器')
        .fontSize(this.isLandscape ? 16 : 18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .margin({ left: 12 })
        .fontFamily(this.appFontFamily)

      Button() {
        SymbolGlyph(this.isCurrentPageBookmarked ? $r('sys.symbol.bookmark_fill') : $r('sys.symbol.bookmark'))
          .fontColor([this.isCurrentPageBookmarked ? $r('app.color.accent_primary') : $r('app.color.text_primary')])
      }
      .width(48)
      .height(48)
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        this.addCurrentEBookBookmark();
      })

      Button() {
        SymbolGlyph($r('sys.symbol.highlighter_line'))
          .fontColor([$r('app.color.text_primary')])
      }
      .width(48)
      .height(48)
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        this.openCurrentEBookAnnotationCenter();
      })

          // 纯文本阅读器：显示综合设置按钮
      Button() {
        SymbolGlyph($r('sys.symbol.more'))
          .fontColor([$r('app.color.text_primary')])

      }
      .width(48)
      .height(48)
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        this.showMoreMenuWithAnimation();
      })
    }
    .width('100%')
    .height(this.getStableTopToolbarHeight())
    .padding({ left: 8, right: 8, top: this.getStableTopToolbarInset() })
    .backgroundColor(this.themeManager.getGlassBackgroundResource())
    .backgroundBlurStyle(this.themeManager.getGlassBlurStyle())
    .shadow({ radius: this.themeManager.getGlassRadius(), color: this.themeManager.getGlassShadowColor(), offsetX: 0, offsetY: 4 })
    .opacity(this.toolbarOpacity)
    .id('guide_ebook_reader_top_toolbar')
  }

  /**
   * 构建更多菜单
    */
  @Builder
  buildBottomToolbar() {
    Column() {
          // 电子书阅读器：显示字体和阅读设置按钮
      Row() {
        Text(this.getBottomToolbarChapterTitle())
          .fontSize(13)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
          .fontFamily(this.appFontFamily)
        
        Text(this.getBottomToolbarStatusText())
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .fontFamily(this.appFontFamily)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 4 })

          // 阅读设置按钮（主题、翻页等）
      Row() {
        if (this.isUsingTextReader() || this.isUsingMarkdownReader()) {
          Slider({
            value: this.currentChapterIndex,
            min: 0,
            max: (this.ebook?.chapters.length || 1) - 1,
            step: 1
          })
            .layoutWeight(1)
            .trackColor($r('app.color.divider_primary'))
            .selectedColor($r('app.color.accent_primary'))
            .onChange((value: number, mode: SliderChangeMode) => {
              // 只在用户释放滑块时触发章节切换，避免拖动过程中频繁触发
              if (mode === SliderChangeMode.End) {
                const targetIndex = Math.round(value);
                if (targetIndex !== this.currentChapterIndex) {
                  this.jumpToChapter(targetIndex);
                }
              }
            })
        } else {
          Slider({
            value: this.getReaderKitProgressSliderValue(),
            min: 0,
            max: 100,
            step: 1
          })
            .layoutWeight(1)
            .trackColor($r('app.color.divider_primary'))
            .selectedColor($r('app.color.accent_primary'))
            .onChange((value: number, mode: SliderChangeMode) => {
              if (mode === SliderChangeMode.End) {
                void this.handleReaderKitProgressSliderEnd(value);
              }
            })
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16 })

      // 点击遮罩关闭
      Row() {
      // 点击遮罩关闭
        Button() {
          SymbolGlyph($r('sys.symbol.list_bullet'))
            .fontColor([$r('app.color.text_primary')])
        }
        .width(64)
        .height(48)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.showChapterListWithAnimation();
        })

        Blank()

      // 点击遮罩关闭
        if (this.isUsingTextReader()) {
      // 菜单面板
          Button() {
            SymbolGlyph($r('sys.symbol.eye'))
              .fontColor([$r('app.color.text_primary')])
          }
          .width(64)
          .height(48)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.showTextReaderSettingsWithAnimation();
          })

          Blank()

          Row() {
          Row() {
            SymbolGlyph(this.textReadAloudPlaying ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'))
              .fontSize(18)
              .fontColor([this.textReadAloudPlaying ? Color.White : $r('app.color.text_primary')])
          }
            .width(48)
            .height('100%')
            .justifyContent(FlexAlign.Center)
            .onClick(() => {
              this.toggleTextReadAloud();
            })

            Column()
              .width(1)
              .height(16)
              .backgroundColor(this.textReadAloudPlaying ? '#66FFFFFF' : $r('app.color.divider_primary'))

            Row() {
              SymbolGlyph($r('sys.symbol.gearshape'))
                .fontSize(16)
                .fontColor([this.textReadAloudPlaying ? Color.White : $r('app.color.text_primary')])
            }
            .width(44)
            .height('100%')
            .justifyContent(FlexAlign.Center)
            .onClick(() => {
              this.openReadAloudSettingsPanel();
            })
          }
          .height(36)
          .backgroundColor(this.textReadAloudPlaying ? '#1A1890FF' : $r('app.color.background_secondary'))
          .borderRadius(18)
          .clip(true)
        } else {
        // 字体调整按钮
        // 字体调整按钮
          Button() {
            SymbolGlyph($r('sys.symbol.textformat'))
              .fontSize(22)
              .fontColor([$r('app.color.text_primary')])
          }
          .width(48)
          .height(48)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.showFontSettingsPanelWithAnimation();
          })

          Blank()

        // 字体调整按钮
          Button() {
            SymbolGlyph($r('sys.symbol.eye'))
              .fontSize(22)
              .fontColor([$r('app.color.text_primary')])
          }
          .width(48)
          .height(48)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.showReadingOptionsPanelWithAnimation();
          })
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: this.navigationBarHeight })
    }
    .width('100%')
    .backgroundColor(this.themeManager.getGlassBackgroundResource())
    .backgroundBlurStyle(this.themeManager.getGlassBlurStyle())
    .shadow({ radius: this.themeManager.getGlassRadius(), color: this.themeManager.getGlassShadowColor(), offsetX: 0, offsetY: -2 })
    .opacity(this.toolbarOpacity)
    .id('guide_ebook_reader_bottom_toolbar')
  }

  /**
  * 构建加载视图
  */
  @Builder
  buildMoreMenu() {
    Stack() {
      // 遮罩
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.hideMoreMenuWithAnimation();
        })

        // 标题栏
      Column() {
        // 标题栏
        Row() {
          Text('目录')
            .fontColor($r('app.color.text_primary'))
            .fontSize(16)
            .fontFamily(this.appFontFamily)
          Blank().layoutWeight(1)
          SymbolGlyph($r('sys.symbol.arrow_right'))
            .fontSize(16)
            .fontColor([$r('app.color.text_secondary')])
        }
        .height(44)
        .padding({ left: 16, right: 16 })
        .onClick(() => {
          logger.info(TAG, '更多菜单：打开目录');
          this.hideMoreMenuWithAnimation();
          this.showChapterListWithAnimation();
        })

        Divider().color($r('app.color.divider'))

        // 章节列表
        Row() {
                Text('字体大小')
            .fontColor($r('app.color.text_primary'))
            .fontSize(16)
            .fontFamily(this.appFontFamily)
          Blank().layoutWeight(1)
          Text(`${this.fontSize}`)
            .fontColor($r('app.color.text_secondary'))
            .fontSize(14)
            .fontFamily(this.appFontFamily)
        }
        .height(44)
        .padding({ left: 16, right: 16 })

        // 章节列表
        Row({ space: 16 }) {
          Button('减小')
            .fontSize(14)
            .width(60)
            .height(36)
            .fontFamily(this.appFontFamily)
            .backgroundColor($r('app.color.background_secondary'))
            .fontColor($r('app.color.text_primary'))
            .onClick(() => {
              this.adjustFontSize(-2);
            })

          Button('增大')
            .fontSize(14)
            .width(60)
            .height(36)
            .fontFamily(this.appFontFamily)
            .backgroundColor($r('app.color.background_secondary'))
            .fontColor($r('app.color.text_primary'))
            .onClick(() => {
              this.adjustFontSize(2);
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 12 })
        .justifyContent(FlexAlign.Center)
      }
      .backgroundColor(this.themeManager.getGlassEffectOptions(GlassEffectContext.MENU).backgroundColorResource)
      .backgroundBlurStyle(this.themeManager.getGlassEffectOptions(GlassEffectContext.MENU).blurStyle)
      .borderRadius(this.themeManager.getGlassEffectOptions(GlassEffectContext.MENU).radius)
      .shadow({ radius: this.themeManager.getGlassEffectOptions(GlassEffectContext.MENU).radius, color: this.themeManager.getGlassEffectOptions(GlassEffectContext.MENU).shadowColor, offsetX: 0, offsetY: 4 })
      .opacity(this.moreMenuOpacity)
      .scale({ x: this.moreMenuScale, y: this.moreMenuScale })
      .translate({ y: this.moreMenuTranslateY })
      .align(Alignment.TopEnd)
      .margin({ top: this.getStableTopToolbarHeight() + 8, right: 12 })
      .constraintSize({ maxWidth: 260 })
      .zIndex(1100)
    }
    .width('100%')
    .height('100%')
    .zIndex(1100)
  }

  /**
  * 构建加载视图
  */
  @Builder
  buildChapterListPanel() {
    Stack() {
      // 使用完整的阅读设置面板组件
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.background_overlay'))
        .opacity(0.5 * this.chapterListOpacity)
        .onClick(() => {
          this.hideChapterListWithAnimation();
        })

      // 使用完整的阅读设置面板组件
      Column() {
      // 使用完整的阅读设置面板组件
        Row() {
          Text('目录')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
            .fontFamily(this.appFontFamily)

          Button() {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(18)
              .fontColor([$r('app.color.text_secondary')])
          }
          .width(36)
          .height(36)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.hideChapterListWithAnimation();
          })
        }
        .width('100%')
        .padding({ left: 20, right: 12, top: 16, bottom: 12 })

        Divider().color($r('app.color.divider'))

      // 遮罩
        List({ scroller: this.chapterListScroller }) {
          ForEach(this.ebook?.chapters || [], (chapter: EBookChapter, index: number) => {
            ListItem() {
              Row() {
                Text(chapter.title)
                  .fontSize(15)
                  .fontColor(index === this.currentChapterIndex ? $r('app.color.accent_primary') : $r('app.color.text_primary'))
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                  .fontFamily(this.appFontFamily)

                if (index === this.currentChapterIndex) {
                  Text('当前')
                    .fontSize(12)
                    .fontColor($r('app.color.accent_primary'))
                    .margin({ left: 8 })
                    .fontFamily(this.appFontFamily)
                }
              }
              .width('100%')
              .padding({ left: 20, right: 20, top: 14, bottom: 14 })
              .backgroundColor(index === this.currentChapterIndex ? $r('app.color.background_secondary') : Color.Transparent)
              .onClick(() => {
        // 标题栏
                this.jumpToChapter(index);
                this.hideChapterListWithAnimation();
              })
            }
          })
        }
        .width('100%')
        .layoutWeight(1)
        .divider({ strokeWidth: 0.5, color: $r('app.color.divider'), startMargin: 20, endMargin: 20 })
      }
      .width(this.isLandscape ? '40%' : '85%')
      .height(this.isLandscape ? '100%' : '80%')
      .constraintSize({ maxWidth: 400, minWidth: 280 })
      .backgroundColor(this.themeManager.getGlassBackgroundResource())
      .backgroundBlurStyle(this.themeManager.getGlassBlurStyle())
      .borderRadius(this.isLandscape ? 0 : 16)
      .opacity(this.chapterListOpacity)
      .id('guide_ebook_reader_chapter_list')
    }
    .width('100%')
    .height('100%')
    .alignContent(this.isLandscape ? Alignment.End : Alignment.Center)
    .zIndex(1000)
  }

  /**
  * 构建加载视图
  */
  @Builder
  buildSettingsPanel() {
    Stack() {
            // 字体大小
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.background_overlay'))
        .opacity(0.5 * this.settingsPanelOpacity)
        .onClick(() => {
          this.hideSettingsPanelWithAnimation();
        })

            // 字体大小
      Column() {
        if (this.ebook && this.ebook.readingSettings) {
          EBookReadingSettingsPanel({
            settings: this.ebook.readingSettings,
            onSettingsChange: (settings: EBookReadingSettings) => {
              this.updateReadingSettings(settings);
            },
            onClose: () => {
              this.hideSettingsPanelWithAnimation();
            }
          })
        }
      }
      .width(this.isLandscape ? '45%' : '90%')
      .height(this.isLandscape ? '100%' : '70%')
      .constraintSize({ maxWidth: 420, maxHeight: this.isLandscape ? undefined : 600, minWidth: 300 })
      .backgroundColor(this.themeManager.getGlassBackgroundResource())
      .backgroundBlurStyle(this.themeManager.getGlassBlurStyle())
      .borderRadius(this.isLandscape ? 0 : 16)
      .opacity(this.settingsPanelOpacity)
      .scale({ x: this.settingsPanelScale, y: this.settingsPanelScale })
      .translate({ y: this.settingsPanelTranslateY })
      .clip(true)
    }
    .width('100%')
    .height('100%')
    .alignContent(this.isLandscape ? Alignment.End : Alignment.Center)
    .zIndex(1200)
  }

  /**
   * 构建阅读设置面板（主题、翻页模式等）
    */
  @Builder
  buildFontSettingsPanel() {
    Stack() {
            // 行高
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.background_overlay'))
        .opacity(0.5 * this.fontSettingsPanelOpacity)
        .onClick(() => {
          this.hideFontSettingsPanelWithAnimation();
        })

            // 行高
      Column() {
            // 行高
        Row() {
              Text('字体与排版')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
            .fontFamily(this.appFontFamily)

          Button() {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(18)
              .fontColor([$r('app.color.text_secondary')])
          }
          .width(36)
          .height(36)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.hideFontSettingsPanelWithAnimation();
          })
        }
        .width('100%')
        .padding({ left: 20, right: 12, top: 16, bottom: 12 })

        Divider().color($r('app.color.divider'))

        Scroll() {
          Column({ space: 16 }) {
            // 页边距
            Column() {
              Text('预览效果')
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
                .margin({ bottom: 8 })
                .fontFamily(this.appFontFamily)
              
              Text('这是预览文本，用于观察字体大小、行高与页边距效果。')
                .fontSize(clampTextReaderFontSize(this.fontSize))
                .lineHeight(clampTextReaderFontSize(this.fontSize) * this.lineHeight)
                .fontColor(this.textColor)
                .width('100%')
                .padding(12)
                .backgroundColor($r('app.color.background_secondary'))
                .borderRadius(8)
                .fontFamily(this.appFontFamily)
            }
            .width('100%')

            // 页边距
            Row() {
              Text('字体大小')
                .fontSize(14)
                .fontColor($r('app.color.text_primary'))
                .fontFamily(this.appFontFamily)
              Blank()
              Text(`${clampTextReaderFontSize(this.fontSize)}`)
                .fontSize(14)
                .fontColor($r('app.color.accent_primary'))
                .fontFamily(this.appFontFamily)
            }
            .width('100%')

            Row({ space: 12 }) {
              Button('减小')
                .fontSize(14)
                .width(48)
                .height(36)
                .fontFamily(this.appFontFamily)
                .backgroundColor($r('app.color.background_secondary'))
                .fontColor($r('app.color.text_primary'))
                .onClick(() => {
                  this.adjustFontSize(-2);
                })

              Slider({
                value: clampTextReaderFontSize(this.fontSize),
                min: TEXT_READER_FONT_SIZE_MIN,
                max: TEXT_READER_FONT_SIZE_MAX,
                step: 1
              })
                .layoutWeight(1)
                .onChange((value: number) => {
                  this.fontSize = clampTextReaderFontSize(value);
                  this.saveSettings();
                })

              Button('增大')
                .fontSize(14)
                .width(48)
                .height(36)
                .fontFamily(this.appFontFamily)
                .backgroundColor($r('app.color.background_secondary'))
                .fontColor($r('app.color.text_primary'))
                .onClick(() => {
                  this.adjustFontSize(2);
                })
            }
            .width('100%')

        // 标题栏
            Row() {
          Text('行高')
                .fontSize(14)
                .fontColor($r('app.color.text_primary'))
                .fontFamily(this.appFontFamily)
              Blank()
              Text(`${this.lineHeight.toFixed(1)}`)
                .fontSize(14)
                .fontColor($r('app.color.accent_primary'))
                .fontFamily(this.appFontFamily)
            }
            .width('100%')

            Slider({
              value: this.lineHeight,
              min: 1.2,
              max: 2.5,
              step: 0.1
            })
              .width('100%')
              .onChange((value: number) => {
                this.lineHeight = Math.round(value * 10) / 10;
                this.saveSettings();
              })

                // 浅色主题
            Row() {
              Text('页边距')
                .fontSize(14)
                .fontColor($r('app.color.text_primary'))
                .fontFamily(this.appFontFamily)
              Blank()
              Text(`${this.pageMargin}`)
                .fontSize(14)
                .fontColor($r('app.color.accent_primary'))
                .fontFamily(this.appFontFamily)
            }
            .width('100%')

            Slider({
              value: this.pageMargin,
              min: 8,
              max: 48,
              step: 4
            })
              .width('100%')
              .onChange((value: number) => {
                this.pageMargin = Math.round(value);
                this.saveSettings();
              })
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 16, bottom: 20 })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
      }
      .width(this.isLandscape ? '45%' : '90%')
      .height(this.isLandscape ? '100%' : '70%')
      .constraintSize({ maxWidth: 400, maxHeight: this.isLandscape ? undefined : 550, minWidth: 300 })
      .backgroundColor(this.themeManager.getGlassBackgroundResource())
      .backgroundBlurStyle(this.themeManager.getGlassBlurStyle())
      .borderRadius(this.isLandscape ? 0 : 16)
      .opacity(this.fontSettingsPanelOpacity)
      .scale({ x: this.fontSettingsPanelScale, y: this.fontSettingsPanelScale })
      .clip(true)
    }
    .width('100%')
    .height('100%')
    .alignContent(this.isLandscape ? Alignment.End : Alignment.Center)
    .zIndex(1250)
  }

  /**
   * 构建书籍信息弹窗
    */
  @Builder
  buildReadingOptionsPanel() {
    Stack() {
                // 墨绿主题
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.background_overlay'))
        .opacity(0.5 * this.readingOptionsPanelOpacity)
        .onClick(() => {
          this.hideReadingOptionsPanelWithAnimation();
        })

                // 墨绿主题
      Column() {
                // 墨绿主题
        Row() {
                  Text('阅读选项')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
            .fontFamily(this.appFontFamily)

          Button() {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(18)
              .fontColor([$r('app.color.text_secondary')])
          }
          .width(36)
          .height(36)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.hideReadingOptionsPanelWithAnimation();
          })
        }
        .width('100%')
        .padding({ left: 20, right: 12, top: 16, bottom: 12 })

        Divider().color($r('app.color.divider'))

        Scroll() {
          Column({ space: 20 }) {
            // 其他设置提示
            Column({ space: 12 }) {
            Text('更多阅读设置可在书籍详情页的设置中调整')
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
                .fontFamily(this.appFontFamily)

              Row({ space: 12 }) {
            // 其他设置提示
                Column() {
                  Text('示例')
                    .fontSize(16)
                    .fontColor('#333333')
                    .fontFamily(this.appFontFamily)
                }
                .width(56)
                .height(40)
                .backgroundColor('#FFFFFF')
                .borderRadius(8)
                .border({ width: this.bgColor === '#FFFFFF' ? 2 : 1, color: this.bgColor === '#FFFFFF' ? $r('app.color.accent_primary') : $r('app.color.divider') })
                .justifyContent(FlexAlign.Center)
                .onClick(() => {
                  this.applyReadingThemePreset('#FFFFFF', '#333333');
                })

            // 其他设置提示
                Column() {
                  Text('示例')
                    .fontSize(16)
                    .fontColor('#5D4037')
                    .fontFamily(this.appFontFamily)
                }
                .width(56)
                .height(40)
                .backgroundColor('#F5F0E1')
                .borderRadius(8)
                .border({ width: this.bgColor === '#F5F0E1' ? 2 : 1, color: this.bgColor === '#F5F0E1' ? $r('app.color.accent_primary') : $r('app.color.divider') })
                .justifyContent(FlexAlign.Center)
                .onClick(() => {
                  this.applyReadingThemePreset('#F5F0E1', '#5D4037');
                })

      // 遮罩
                Column() {
                  Text('示例')
                    .fontSize(16)
                    .fontColor('#D4D4D4')
                    .fontFamily(this.appFontFamily)
                }
                .width(56)
                .height(40)
                .backgroundColor('#1E1E1E')
                .borderRadius(8)
                .border({ width: this.bgColor === '#1E1E1E' ? 2 : 1, color: this.bgColor === '#1E1E1E' ? $r('app.color.accent_primary') : $r('app.color.divider') })
                .justifyContent(FlexAlign.Center)
                .onClick(() => {
                  this.applyReadingThemePreset('#1E1E1E', '#D4D4D4');
                })

        // 标题栏
                Column() {
                  Text('示例')
                    .fontSize(16)
                    .fontColor('#C8E6C9')
                    .fontFamily(this.appFontFamily)
                }
                .width(56)
                .height(40)
                .backgroundColor('#1B3B2F')
                .borderRadius(8)
                .border({ width: this.bgColor === '#1B3B2F' ? 2 : 1, color: this.bgColor === '#1B3B2F' ? $r('app.color.accent_primary') : $r('app.color.divider') })
                .justifyContent(FlexAlign.Center)
                .onClick(() => {
                  this.applyReadingThemePreset('#1B3B2F', '#C8E6C9');
                })
              }
              .width('100%')
            }
            .width('100%')

            // 封面和基本信息
            Row() {
                Text('跟随系统主题')
                .fontSize(14)
                .fontColor($r('app.color.text_primary'))
                .fontFamily(this.appFontFamily)
              Blank()
              Toggle({ type: ToggleType.Switch, isOn: this.ebook?.readingSettings?.followSystemTheme !== false })
                .onChange((isOn: boolean) => {
                  if (this.ebook && this.ebook.readingSettings) {
                    this.ebook.readingSettings.followSystemTheme = isOn;
                    if (isOn) {
                      this.applySystemThemeToSettings(this.ebook);
                      this.bgColor = this.ebook.readingSettings.backgroundColor;
                      this.textColor = this.ebook.readingSettings.textColor;
                    } else {
                      this.ebook.readingSettings.nightMode = this.bgColor === '#1E1E1E' || this.bgColor === '#1B3B2F';
                    }
                    this.saveSettings();
                  }
                })
            }
            .width('100%')

            Divider().color($r('app.color.divider'))

              // 基本信息
            Text('当前设置会在阅读中即时生效。')
              .fontSize(12)
              .fontColor($r('app.color.text_muted'))
              .width('100%')
              .textAlign(TextAlign.Center)
              .fontFamily(this.appFontFamily)
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 16, bottom: 20 })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
      }
      .width(this.isLandscape ? '45%' : '90%')
      .height(this.isLandscape ? '100%' : '60%')
      .constraintSize({ maxWidth: 400, maxHeight: this.isLandscape ? undefined : 450, minWidth: 300 })
      .backgroundColor(this.themeManager.getGlassBackgroundResource())
      .backgroundBlurStyle(this.themeManager.getGlassBlurStyle())
      .borderRadius(this.isLandscape ? 0 : 16)
      .opacity(this.readingOptionsPanelOpacity)
      .scale({ x: this.readingOptionsPanelScale, y: this.readingOptionsPanelScale })
      .clip(true)
    }
    .width('100%')
    .height('100%')
    .alignContent(this.isLandscape ? Alignment.End : Alignment.Center)
    .zIndex(1250)
  }

  /**
   * 构建书籍信息项
    */
  @Builder
  buildBookInfoDialog() {
    Stack() {
            // 简介
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.background_overlay'))
        .opacity(0.5 * this.bookInfoDialogOpacity)
        .onClick(() => {
          this.hideBookInfoDialogWithAnimation();
        })

            // 简介
      Column() {
            // 简介
        Row() {
                Text('书籍信息')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
            .fontFamily(this.appFontFamily)

          Button() {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(18)
              .fontColor([$r('app.color.text_secondary')])
          }
          .width(36)
          .height(36)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.hideBookInfoDialogWithAnimation();
          })
        }
        .width('100%')
        .padding({ left: 20, right: 12, top: 16, bottom: 12 })

        Divider().color($r('app.color.divider'))

            // 简介
        Scroll() {
          Column({ space: 16 }) {
            // 简介
            Row({ space: 16 }) {
            // 简介
              if (this.hasValidEBookCover()) {
                Image(this.getEBookCoverSource())
                  .width(80)
                  .height(120)
                  .objectFit(ImageFit.Cover)
                  .borderRadius(8)
              } else {
                Column() {
                  Image($r('app.media.ic_ebook'))
                    .width(40)
                    .height(40)
                    .fillColor($r('app.color.accent_primary'))
                }
                .width(80)
                .height(120)
                .backgroundColor($r('app.color.background_secondary'))
                .borderRadius(8)
                .justifyContent(FlexAlign.Center)
              }

            // 简介
              Column({ space: 6 }) {
                Text(this.ebook?.metadata.title || '未知书名')
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.text_primary'))
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .fontFamily(this.appFontFamily)

                Text(this.ebook?.metadata.author || '未知作者')
                  .fontSize(14)
                  .fontColor($r('app.color.text_secondary'))
                  .fontFamily(this.appFontFamily)

                Text(this.ebook?.format || '')
                  .fontSize(12)
                  .fontColor($r('app.color.text_white'))
                  .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                  .backgroundColor($r('app.color.accent_primary'))
                  .borderRadius(4)
                  .fontFamily(this.appFontFamily)
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')

            Divider().color($r('app.color.divider'))

            // 简介
            this.buildBookInfoItem('出版社', this.ebook?.metadata.publisher || '未知')
            this.buildBookInfoItem('出版日期', this.ebook?.metadata.publishDate || '未知')
            this.buildBookInfoItem('ISBN', this.ebook?.metadata.isbn || '无')
            this.buildBookInfoItem('语言', this.ebook?.metadata.language || '未知')
            this.buildBookInfoItem('章节数', `${this.ebook?.chapters.length || 0}章`)

            // 简介
            if (this.ebook && this.ebook.metadata.description && this.ebook.metadata.description.length > 0) {
              Column({ space: 8 }) {
                Text('简介')
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                  .width('100%')
                  .fontFamily(this.appFontFamily)

                Text(this.ebook.metadata.description)
                  .fontSize(13)
                  .fontColor($r('app.color.text_secondary'))
                  .lineHeight(20)
                  .width('100%')
                  .fontFamily(this.appFontFamily)
              }
              .width('100%')
            }
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 16, bottom: 20 })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring)
      }
      .width(this.isLandscape ? '45%' : '90%')
      .height(this.isLandscape ? '100%' : '70%')
      .constraintSize({ maxWidth: 400, maxHeight: this.isLandscape ? undefined : 550, minWidth: 300 })
      .backgroundColor(this.themeManager.getGlassBackgroundResource())
      .backgroundBlurStyle(this.themeManager.getGlassBlurStyle())
      .borderRadius(this.isLandscape ? 0 : 16)
      .opacity(this.bookInfoDialogOpacity)
      .clip(true)
    }
    .width('100%')
    .height('100%')
    .alignContent(this.isLandscape ? Alignment.End : Alignment.Center)
    .zIndex(1300)
  }

  /**
  * 构建加载视图
  */
  @Builder
  buildBookInfoItem(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .width(80)
        .fontFamily(this.appFontFamily)

      Text(value)
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
        .textAlign(TextAlign.End)
        .fontFamily(this.appFontFamily)
    }
    .width('100%')
    .padding({ top: 4, bottom: 4 })
  }

  /**
  * 格式化文件大小
  */
  private formatFileSize(bytes: number): string {
    if (bytes < 1024) {
      return `${bytes} B`;
    } else if (bytes < 1024 * 1024) {
      return `${(bytes / 1024).toFixed(1)} KB`;
    } else {
      return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
    }
  }
}

export { EBookReaderPage };


