import { SafeFileUtils } from 'manxia_core/src/main/ets/Utils/SafeFileUtils';
import { SafeUtils } from 'manxia_core/src/main/ets/Utils/SafeUtils';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { common } from '@kit.AbilityKit';
import { display, promptAction, UIContext, window } from '@kit.ArkUI';
import { preferences } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { fileIo } from '@kit.CoreFileKit';
import batteryInfo from '@ohos.batteryInfo';
import { WindowManager, DisplayMode } from 'manxia_theme/src/main/ets/Utils/WindowManager';
import { PageWindowCoordinator } from 'manxia_theme/src/main/ets/Utils/PageWindowCoordinator';
import { ReaderOrientationLockHelper } from 'manxia_core/src/main/ets/Utils/ReaderOrientationLockHelper';
import { ReaderSafeAreaUtils } from '../Utils/ReaderSafeAreaUtils';
import { ThemeManager } from 'manxia_theme/src/main/ets/Framework/Managers/ThemeManager';
import { getFontManager, FontScene } from '../Framework/Managers/FontManager';
import { distributedReadingService } from '../Framework/Distributed/DistributedReadingService';
import { distributedDataSyncManager, SyncReadingState } from '../Framework/Distributed/DistributedDataSyncManager';
import { EBookDataManager } from '../Framework/Data/EBookDataManager';
import { EBookParserFactory, resolveEpubPackageDocumentPathFromRoot } from '../Framework/Parsers/EBookParser';
import { convertMobiToExtractedDir } from 'manxia_source_engine/src/main/ets/Framework/Parsers/MobiParser';
import { KeyCode, inputConsumer } from '@kit.InputKit';
import {
  EBook,
  EBookChapter,
  EBookContentMode,
  EBookFormat,
  EpubNavigationItem,
  EBookReaderEngine,
  EBookReadingProgress,
  EBookReadingSettings,
  DEFAULT_EBOOK_READING_SETTINGS
} from 'manxia_core/src/main/ets/Models/EBookModels';
import {
  ReadingSettings as MangaReadingSettings,
  DEFAULT_READING_SETTINGS,
  ReadingMode,
  ReadingDirection,
  DoublePagePortraitLayout,
  PageTurnAnimationType
} from 'manxia_core/src/main/ets/Models/MangaModels';
import {
  EpubWebViewReaderComponent,
  EpubWebViewReaderController,
  EpubSpineTransitionDirection,
  EpubWebViewReaderParams,
  EpubRuntimeBlankSpineInfo,
  EpubWebPageChangeSource,
  EpubWebHighlightRange,
  EpubWebSelectionSnapshot,
  EpubWebTextSnapshot,
  EpubWebPurifyRulePayload,
  EpubWebComponentFlowEvent,
  EpubWebComponentFlowEventName
} from '../Framework/Components/EpubWebViewReaderComponent';
import { UnifiedContentType } from 'manxia_core/src/main/ets/Models/UnifiedContentModels';
import {
  AnnotationAnchor,
  CreateThoughtInput,
  HighlightLineType,
  HighlightStyle,
  UnifiedAnnotationRecord,
  UnifiedAnnotationType
} from 'manxia_core/src/main/ets/Models/AnnotationModels';
import { getUnifiedAnnotationManager } from '../Framework/Annotations/UnifiedAnnotationManager';
import { SettingsManager } from '../Framework/Managers/SettingsManager';
import { AddRuleParams, NovelReplaceRuleManager, ReplaceRule, ReplaceScope } from '../Framework/Novel/NovelReplaceRuleManager';
import {
  DEFAULT_READ_ALOUD_SETTINGS,
  ReadAloudEngineType,
  ReadAloudSettings,
  mergeRemoteReadAloudSettings,
  normalizeReadAloudSettings
} from 'manxia_core/src/main/ets/Models/TextReaderModels';
import { ReadAloudController } from '../Framework/ReadAloud/ReadAloudController';
import { ReadAloudPlaybackState, ReadAloudVoiceOption } from '../Framework/ReadAloud/ReadAloudTypes';
import { ReadAloudAvailability, ReadAloudEngineAvailabilityMap } from '../Framework/ReadAloud/ReadAloudAvailability';
import {
  loadGlobalReadAloudSettings as loadStoredGlobalReadAloudSettings,
  persistGlobalReadAloudSettings as persistStoredGlobalReadAloudSettings
} from '../Framework/ReadAloud/ReadAloudSettingsStore';
import { ReadAloudSettingsInfoPanel } from '../components/ReadAloudSettingsInfoPanel';
import { eventBus, GameEvent, IEventPayload, ReadAloudStatePayload } from '../Framework/EventBus';
import { EpubReaderSettingsPanel } from '../components/EpubReaderSettingsPanel';
import { EpubReaderChapterList } from '../components/EpubReaderChapterList';
import { MangaQuickSettings } from '../components/MangaQuickSettings';
import { MangaInteractionOverlay } from '../components/MangaInteractionOverlay';
import {
  setReaderReady,
  startBookCloseTransitionWithComponentId,
  cancelTransition
} from '../components/BookTransitionOverlay';
import { EBookReaderParams } from './EBookReaderRouteTypes';
import { isReaderKitEnabled } from '../Framework/Initialization/ReaderKitFeatureGate';
import { openEBookReaderRouterPage } from '../Framework/Adapters/EBookReaderRouteNavigator';
import { READER_ABILITY_HOST_MULTITON } from 'manxia_reader_ui/src/main/ets/Framework/Reader/MangaReaderAbilityConstants';
import { openReadAloudPlayerInIsolatedAbility } from '../Framework/ReadAloud/ReadAloudPlayerAbilityLauncher';
import type { KeyEvent as InputKeyEvent } from '@kit.InputKit';
import { DetailOpenFlowMonitor } from 'manxia_reader_ui/src/main/ets/Framework/Reader/DetailOpenFlowMonitor';
import {
  DetailOpenFlowEventType,
  DetailOpenFlowTargetKind
} from 'manxia_reader_ui/src/main/ets/Framework/Reader/DetailOpenFlowTypes';
import { EpubReadFlowMonitor } from 'manxia_reader_ui/src/main/ets/Framework/Reader/EpubReadFlowMonitor';
import {
  EpubReadFlowEventType,
  EpubReadFlowSessionInfo,
  EpubReadFlowSeverity
} from 'manxia_reader_ui/src/main/ets/Framework/Reader/EpubReadFlowTypes';

const TAG = 'EpubWebViewReaderPage';
const IMAGE_RESOURCE_PATH_PATTERN: RegExp = /\.(apng|avif|bmp|gif|heic|heif|jpe?g|png|svg|webp)$/i;
const EPUB_READER_CAMERA_SAFE_TOP_FALLBACK: number = 24;
const WINDOW_MANAGER_LAST_VISIBLE_STATUS_BAR_HEIGHT_KEY: string = 'window_manager_last_visible_status_bar_height';
const READABLE_SPINE_TEXT_THRESHOLD: number = 0;
const RUNTIME_BLANK_SPINE_SKIP_LIMIT: number = 8;
const NOVEL_SETTINGS_STORE: string = 'novel_settings';
const NOVEL_BOOK_RULE_SETTINGS_STORE: string = 'novel_book_rule_settings';
const NOVEL_BOOK_REPLACE_RULE_IDS_PREFIX: string = 'book_replace_rule_ids_';
const NOVEL_SETTING_ENABLE_REPLACE_RULES: string = 'enableNovelReplaceRules';
const EPUB_OPF_META_COVER_PATTERN: RegExp = /<meta\b[^>]*name\s*=\s*["']cover["'][^>]*content\s*=\s*["']([^"']+)["'][^>]*\/?>/i;

interface EpubSettingsPanelCallbacks {
  onSettingsChange: (settings: EBookReadingSettings) => void;
  onPageSettingsChange: (settings: MangaReadingSettings) => void;
  onClose: () => void;
}

interface EpubChapterListCallbacks {
  onChapterSelect: (spineIndex: number) => void;
  onClose: () => void;
}

interface EpubBookmarkContext {
  chapterId: string;
  chapterTitle: string;
  chapterIndex: number;
  pageIndex: number;
  progress: number;
  startOffset: number;
  endOffset: number;
  quoteText: string;
  contextBefore: string;
  contextAfter: string;
  isTextMode: boolean;
}

@Component
export struct EpubWebViewReaderPage {
  // ──── 导航 ────
  @State pathStack: NavPathStack = new NavPathStack();
  private uiContext: UIContext | null = null;
  private context: common.UIAbilityContext | null = null;
  private coverComponentId: string = '';
  private routerBackOnClose: boolean = false;
  private readerHostMode: string = '';
  private readerInstanceId: string = '';
  private readerOpenFlowId: string = '';
  private epubReadFlowId: string = '';
  private routeReaderTitle: string = '';

  // ──── 安全区 ────
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;
  @State private cameraCutoutTopInset: number = 0;

  // ──── 书籍数据 ────
  @State ebook: EBook | null = null;
  @State spineItems: EBookChapter[] = [];
  @State navigationChapters: EBookChapter[] = [];
  @State extractedRoot: string = '';
  @State currentSpineIndex: number = 0;
  @State currentPageWithinSpine: number = 0;
  @State totalPagesInSpine: number = 0;
  @State isFixedLayout: boolean = false;
  @State currentAnchorFragment: string = '';
  @State private canFallbackToReaderKit: boolean = false;
  private epubReaderController: EpubWebViewReaderController | null = null;
  private ebookDataManager: EBookDataManager = EBookDataManager.getInstance();
  private annotationManager = getUnifiedAnnotationManager();
  private navigationTargets: EpubNavigationItem[] = [];
  private spineReadableCache: Map<number, boolean> = new Map<number, boolean>();
  private runtimeBlankSpineIndices: number[] = [];
  private runtimeBlankSpineSkipCount: number = 0;

  // ──── 阅读设置 ────
  @State readingSettings: EBookReadingSettings = DEFAULT_EBOOK_READING_SETTINGS;
  @State pageReadingSettings: MangaReadingSettings = DEFAULT_READING_SETTINGS;

  // ──── UI 状态 ────
  @State isLoading: boolean = true;
  @State errorMessage: string = '';
  @State showTopToolbar: boolean = false;
  @State showBottomToolbar: boolean = false;
  @State toolbarOpacity: number = 0;
  @State showSettingsPanel: boolean = false;
  @State showQuickSettings: boolean = false;
  @State showChapterList: boolean = false;
  @State showPageTurnAnimationSettings: boolean = false;
  @State showAutoPageTurnSettings: boolean = false;
  @State showInteractionOverlay: boolean = false;
  @State private quickSettingsOpacity: number = 0;
  @State private quickSettingsScale: number = 0.96;
  @State private quickSettingsTranslateY: number = 24;
  @State private pageTurnSettingsBackdropOpacity: number = 0;
  @State private pageTurnSettingsPanelOpacity: number = 0;
  @State private pageTurnSettingsPanelScale: number = 0.96;
  @State private pageTurnSettingsPanelTranslateX: number = 48;
  @State private pageTurnSettingsPanelTranslateY: number = 24;
  @State private autoPageTurnSettingsBackdropOpacity: number = 0;
  @State private autoPageTurnSettingsPanelOpacity: number = 0;
  @State private autoPageTurnSettingsPanelScale: number = 0.96;
  @State private autoPageTurnSettingsPanelTranslateX: number = 48;
  @State private autoPageTurnSettingsPanelTranslateY: number = 24;
  @State componentWidth: number = 0;
  @State componentHeight: number = 0;
  @State isLandscapeMode: boolean = false;
  @State autoPageTurnEnabled: boolean = false;
  @State autoPageTurnIntervalSeconds: number = 5;
  @State currentTime: string = '';
  @State batteryLevel: number = 0;
  @State private currentSpineHighlightRanges: EpubWebHighlightRange[] = [];
  @State isCurrentPageBookmarked: boolean = false;
  @State currentPageBookmarkId: string = '';
  @State readAloudPlaying: boolean = false;
  @State readAloudCurrentCharIndex: number = -1;
  @State showReadAloudPanel: boolean = false;
  @State readAloudPanelSettings: ReadAloudSettings = DEFAULT_READ_ALOUD_SETTINGS;
  @State readAloudAvailability: ReadAloudEngineAvailabilityMap = ReadAloudAvailability.getCachedOrDefault();
  @State readAloudVoiceOptions: ReadAloudVoiceOption[] = [];
  @State readAloudStatusMessage: string = '';
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';

  // ──── 工具栏自动隐藏 ────
  private static readonly TOOLBAR_AUTO_HIDE_MS: number = 3000;
  private static readonly PROGRESS_SAVE_INTERVAL_MS: number = 1500;
  private toolbarHideTimer: number = -1;
  private fullscreenRestoreTimer: number = -1;
  private autoPageTurnTimer: number = -1;
  private timeUpdateTimer: number = -1;
  private lastProgressSaveTime: number = 0;
  private lastRemoteInstructionTimestamp: number = 0;
  private remoteCallbacksRegistered: boolean = false;
  private pendingContinuationSpineIndex: number = -1;
  private pendingContinuationPageIndex: number = -1;
  private sessionStartTimestamp: number = 0;
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private settingsManager: SettingsManager = SettingsManager.getInstance();
  private readAloudController: ReadAloudController = ReadAloudController.getInstance();
  private hasNotifiedTransitionReaderReady: boolean = false;
  private epubCurlGestureActive: boolean = false;
  private epubCurlGestureStarted: boolean = false;
  private epubCurlGestureStartX: number = 0;
  private epubCurlGestureStartY: number = 0;
  private epubCurlGestureProgress: number = 0;
  private pendingSpineIndex: number = -1;
  @State private readerMountEpoch: number = 0;
  private volumeUpCallback: ((event: InputKeyEvent) => void) | null = null;
  private volumeDownCallback: ((event: InputKeyEvent) => void) | null = null;
  private isVolumeKeyListenerRegistered: boolean = false;
  private isPageVisible: boolean = false;
  private orientationLockToken: string = '';
  private replaceSettingsLoaded: boolean = false;
  private replaceRulesEnabled: boolean = true;
  private scopedReplaceRuleIds: string[] | null = null;
  private currentVisibleTextSnapshot: EpubWebTextSnapshot | null = null;
  private currentSpineTextCache: string = '';
  private currentSpineTextCacheIndex: number = -1;
  private readAloudUiSyncTimer: number = -1;
  private readAloudProgressSaveInterval: number = 3000;
  private lastReadAloudProgressSaveTime: number = 0;
  private lastReadAloudPanelCloseTime: number = 0;
  private shouldAutoStartReadAloudFromRoute: boolean = false;
  private shouldAutoOpenReadAloudPlayerFromRoute: boolean = false;
  private routeReadAloudAutoStartAttempts: number = 0;
  private static readonly READ_ALOUD_PANEL_REOPEN_GUARD_MS: number = 320;

  private onReadAloudStateChanged: (payload: IEventPayload) => void = (payload: IEventPayload): void => {
    const ebook = this.ebook;
    if (!ebook) {
      return;
    }
    const statePayload = payload as ReadAloudStatePayload;
    const payloadBookId = statePayload.bookId ?? '';
    if (!payloadBookId || payloadBookId !== ebook.id) {
      const controllerContext = this.readAloudController.getContextSnapshot();
      if (!controllerContext || controllerContext.bookId !== ebook.id) {
        return;
      }
    }
    if (!this.shouldHandleReadAloudUiEvents()) {
      return;
    }

    this.readAloudPlaying = statePayload.playbackState === ReadAloudPlaybackState.PLAYING;
    this.applyReadAloudProgress(statePayload);
    if (
      statePayload.playbackState !== ReadAloudPlaybackState.PLAYING &&
      statePayload.reason !== 'progress_updated'
    ) {
      void this.saveReadingProgress('read_aloud_state_change');
    }
  };

  // ──── 生命周期 ────

  aboutToAppear(): void {
    this.isPageVisible = true;
    // [修复] WebView EPUB 阅读器接入跨端接续状态机：前台标志 + 接续快照 + 遥控监听
    AppStorage.setOrCreate('currentReaderHostPage', 'EpubWebViewReaderPage');
    const continuationSessionId = AppStorage.get<string>('continuationSessionId');
    if (continuationSessionId && continuationSessionId.length > 0) {
      const snapshot = distributedReadingService.readContinuationSnapshot();
      if (snapshot) {
        if (snapshot.chapterIndex >= 0) {
          this.pendingContinuationSpineIndex = snapshot.chapterIndex;
        }
        if (snapshot.pageIndex >= 0) {
          this.pendingContinuationPageIndex = snapshot.pageIndex;
        }
        logger.info(TAG, `[Distributed] WebView EPUB 接续快照待应用: chapterIndex=${snapshot.chapterIndex}, pageIndex=${snapshot.pageIndex}`);
      }
      this.registerRemoteControlListener();
      distributedReadingService.clearContinuationFlags();
    }
    this.themeManager = ThemeManager.getInstance();
    this.settingsManager = SettingsManager.getInstance();
    eventBus.subscribe(GameEvent.READ_ALOUD_STATE_CHANGED, this.onReadAloudStateChanged);
    AppStorage.setOrCreate('ReadAloudCurrentHostPage', 'EpubWebViewReaderPage');
    this.syncReadAloudStateFromController();
    this.startReadAloudUiSyncTimer();
    this.readAloudController.refreshMediaSession();
    const info = display.getDefaultDisplaySync();
    this.isLandscapeMode = info.width > info.height;
    void this.refreshCameraCutoutTopInset('appear');
    this.startTimeUpdate();
    this.updateBatteryLevel();
  }

  aboutToDisappear(): void {
    this.isPageVisible = false;
    AppStorage.setOrCreate('currentReaderHostPage', '');
    this.unregisterRemoteControlListener();
    this.stopReadAloudUiSyncTimer();
    eventBus.unsubscribe(GameEvent.READ_ALOUD_STATE_CHANGED, this.onReadAloudStateChanged);
    this.clearToolbarTimer();
    this.clearFullscreenRestoreTimer();
    this.epubReaderController?.cancelInteractiveCurl();
    this.epubReaderController?.clearReadAloudHighlight();
    this.unregisterVolumeKeyListener();
    this.stopAutoPageTurn();
    this.stopTimeUpdate();
    this.orientationLockToken = ReaderOrientationLockHelper.release(this.orientationLockToken, this.uiContext ?? undefined);
    void this.persistTextReadingSettings('about_to_disappear');
    void this.persistPageReadingSettings('about_to_disappear');
    void this.saveReadingProgress('about_to_disappear');
    if (this.epubReadFlowId.length > 0) {
      EpubReadFlowMonitor.getInstance().endSession(this.epubReadFlowId, 'about_to_disappear');
      this.epubReadFlowId = '';
    }
  }

  onPageShow(): void {
    this.isPageVisible = true;
    AppStorage.setOrCreate('ReadAloudCurrentHostPage', 'EpubWebViewReaderPage');
    WindowManager.setDisplayMode(DisplayMode.FULL_IMMERSIVE, this.uiContext ?? undefined);
    WindowManager.reapplyCurrentDisplayMode(24);
    void this.refreshCameraCutoutTopInset('show');
    this.updateVolumeKeyListener();
    this.syncDeviceOrientationLock('page_show');
    this.startTimeUpdate();
    this.syncAutoPageTurnState();
    this.updateBatteryLevel();
    this.syncReadAloudStateFromController();
    this.startReadAloudUiSyncTimer();
    void this.updateEpubReadAloudContextByPosition();
    this.refreshCurrentEpubBookmarkState('on_page_show');
    this.readAloudController.refreshMediaSession();
  }

  onPageHide(): void {
    this.isPageVisible = false;
    this.stopReadAloudUiSyncTimer();
    this.unregisterVolumeKeyListener();
    this.stopAutoPageTurn();
    this.stopTimeUpdate();
    this.readAloudController.handlePageHide();
    this.readAloudPlaying = this.readAloudController.getSnapshot().playbackState === ReadAloudPlaybackState.PLAYING;
    void this.persistTextReadingSettings('page_hide');
    void this.saveReadingProgress('page_hide');
  }

  // ──── 初始化 ────

  private async initializeWithParams(params: EBookReaderParams): Promise<void> {
    try {
      this.context = (this.getUIContext().getHostContext() as common.UIAbilityContext) as common.UIAbilityContext;
    } catch (_ignored) {}
    this.coverComponentId = params.coverComponentId ?? '';
    this.routerBackOnClose = params.routerBackOnClose === true;
    this.readerHostMode = params.readerHostMode || '';
    this.readerInstanceId = params.readerInstanceId || '';
    this.readerOpenFlowId = params.readerOpenFlowId || '';
    this.routeReaderTitle = params.readerTitle || '';
    this.shouldAutoStartReadAloudFromRoute = params.autoStartReadAloud === true;
    this.shouldAutoOpenReadAloudPlayerFromRoute = params.autoOpenReadAloudPlayer === true;
    this.routeReadAloudAutoStartAttempts = 0;
    this.startEpubReadFlowSession(params.bookId, this.routeReaderTitle, '', 'initialize_params');
    await this.loadEBook(params.bookId);
    this.sessionStartTimestamp = Date.now();
  }

  private async loadEBook(bookId: string): Promise<void> {
    const loadStartedAt = Date.now();
    this.isLoading = true;
    this.errorMessage = '';
    this.hasNotifiedTransitionReaderReady = false;
    this.epubReaderController = null;
    this.navigationTargets = [];
    this.navigationChapters = [];
    this.currentAnchorFragment = '';
    this.pendingSpineIndex = -1;
    this.readerMountEpoch = Date.now();
    this.spineReadableCache.clear();
    this.runtimeBlankSpineIndices = [];
    this.runtimeBlankSpineSkipCount = 0;
    this.currentSpineHighlightRanges = [];
    this.isCurrentPageBookmarked = false;
    this.currentPageBookmarkId = '';
    this.currentVisibleTextSnapshot = null;
    this.currentSpineTextCache = '';
    this.currentSpineTextCacheIndex = -1;
    this.readAloudCurrentCharIndex = -1;
    this.replaceSettingsLoaded = false;

    try {
      const ebook = await this.ebookDataManager.getEBookById(bookId);
      if (!ebook) {
        throw new Error('未找到电子书');
      }
      const isMobiFormat = ebook.format === EBookFormat.MOBI ||
        ebook.format === EBookFormat.AZW ||
        ebook.format === EBookFormat.AZW3;
      if (ebook.format !== EBookFormat.EPUB && !isMobiFormat) {
        throw new Error('当前文件格式不支持 WebView 渲染');
      }

      let extractedRoot = ebook.extractedRootPath ?? '';
      let mobiConversionError = '';

      if (extractedRoot.length === 0 && ebook.format === EBookFormat.EPUB) {
        logger.info(TAG, `extractedRootPath 为空，尝试懒解压: ${ebook.filePath}`);
        extractedRoot = await EBookParserFactory.ensureEpubExtracted(ebook.filePath ?? '');
        if (extractedRoot.length > 0) {
          ebook.extractedRootPath = extractedRoot;
          for (const ch of ebook.chapters) {
            if ((ch.resourceFile ?? '').trim().length === 0) {
              const rh = (ch.resourceHref ?? '').trim().replace(/^\//, '');
              if (rh.length > 0) {
                ch.resourceFile = rh;
              }
            }
          }
          void this.ebookDataManager.saveEBook(ebook, { skipReadingSettings: true });
          logger.info(TAG, `懒解压成功: extractedRootPath=${extractedRoot}`);
        }
      }

      if (isMobiFormat) {
        logger.info(
          TAG,
          `${extractedRoot.length === 0 ? 'MOBI extractedRootPath 为空，触发懒转换' : '检查 MOBI 本地转换缓存版本'}: ${ebook.filePath}`
        );
        const convResult = await convertMobiToExtractedDir(ebook.filePath ?? '');
        if (convResult.success) {
          extractedRoot = convResult.extractedRootPath;
          ebook.extractedRootPath = extractedRoot;
          ebook.preferredReaderEngine = EBookReaderEngine.WEBVIEW;
          const newSpine = EBookParserFactory.parseEpubSpineItems(extractedRoot);
          if (newSpine.length > 0) {
            for (const ch of newSpine) {
              ch.bookId = ebook.id;
            }
            ebook.chapters = newSpine;
          }
          void this.ebookDataManager.saveEBook(ebook, { skipReadingSettings: true });
          logger.info(TAG, `MOBI 本地转换缓存就绪: ${extractedRoot}`);
        } else {
          mobiConversionError = convResult.errorMessage;
          logger.warn(TAG, `MOBI 懒转换失败: ${mobiConversionError}`);
          if (extractedRoot.length > 0) {
            logger.warn(TAG, `MOBI 转换刷新失败，继续使用已有 extractedRootPath: ${extractedRoot}`);
          }
        }
      }

      if (extractedRoot.length === 0) {
        this.canFallbackToReaderKit = ebook.contentMode !== EBookContentMode.FIXED_LAYOUT_HTML;
        if (isMobiFormat) {
          const reason = mobiConversionError.length > 0 ? `：${mobiConversionError}` : '';
          throw new Error(`Kindle 格式本地转换失败${reason}，可尝试使用 ReaderKit 打开`);
        }
        throw new Error('EPUB 尚未解压，请重新导入文件，或使用 ReaderKit 打开');
      }

      let spineItems = ebook.chapters.filter((ch: EBookChapter) => {
        const rf = (ch.resourceFile ?? '').trim();
        const rh = (ch.resourceHref ?? '').trim();
        return rf.length > 0 || rh.length > 0;
      });

      if (ebook.format === EBookFormat.EPUB && extractedRoot.length > 0) {
        const opfSpineItems = EBookParserFactory.parseEpubSpineItems(extractedRoot);
        if (opfSpineItems.length > 0 && this.shouldRefreshEpubSpineItems(spineItems, opfSpineItems)) {
          for (const ch of opfSpineItems) {
            ch.bookId = ebook.id;
          }
          ebook.chapters = opfSpineItems;
          void this.ebookDataManager.saveEBook(ebook, { skipReadingSettings: true });
          spineItems = opfSpineItems;
          logger.info(TAG, `已根据 OPF 刷新 WebView spine 元数据: count=${spineItems.length}`);
        }
      }

      if (spineItems.length === 0) {
        logger.info(TAG, `章节缺少资源路径，尝试直接解析 OPF: extractedRoot=${extractedRoot}`);
        const opfSpineItems = EBookParserFactory.parseEpubSpineItems(extractedRoot);
        if (opfSpineItems.length > 0) {
          for (const ch of opfSpineItems) {
            ch.bookId = ebook.id;
          }
          ebook.chapters = opfSpineItems;
          void this.ebookDataManager.saveEBook(ebook, { skipReadingSettings: true });
          spineItems = opfSpineItems;
          logger.info(TAG, `OPF 直接解析成功，获得 ${spineItems.length} 个 spine 项`);
        }
      }

      if (spineItems.length === 0) {
        this.canFallbackToReaderKit = ebook.contentMode !== EBookContentMode.FIXED_LAYOUT_HTML;
        throw new Error('EPUB 内容无法被 WebView 渲染（缺少 spine 资源路径），请使用 ReaderKit 打开');
      }

      this.ebook = ebook;
      this.extractedRoot = extractedRoot;
      this.spineItems = spineItems;
      this.configureNavigationTargets(ebook.id, extractedRoot, spineItems);
      this.isFixedLayout = ebook.contentMode === EBookContentMode.FIXED_LAYOUT_HTML;

      const effectiveTextSettings = await this.ebookDataManager.resolveEffectiveEBookReadingSettings(
        ebook.id,
        ebook.readingSettings
      );
      this.readingSettings = this.resolveSystemThemeTextSettings(effectiveTextSettings);
      ebook.readingSettings = this.cloneTextReadingSettings(this.readingSettings);
      const loadedPageSettings = await this.ebookDataManager.loadImageReaderSettings(ebook.id);
      const normalizedLoadedPageSettings = this.normalizePageReadingSettings(loadedPageSettings);
      this.pageReadingSettings = this.clonePageReadingSettings(normalizedLoadedPageSettings);
      if (!this.arePageReadingSettingsEqual(normalizedLoadedPageSettings, loadedPageSettings)) {
        void this.ebookDataManager.saveImageReaderSettings(ebook.id, normalizedLoadedPageSettings);
      }
      this.autoPageTurnEnabled = this.pageReadingSettings.autoPageTurnInterval > 0;
      this.autoPageTurnIntervalSeconds = this.autoPageTurnEnabled ?
        this.pageReadingSettings.autoPageTurnInterval : 5;
      this.updateVolumeKeyListener();
      this.syncDeviceOrientationLock('settings_loaded');
      logger.info(
        TAG,
        `恢复阅读设置: text(fontSize=${this.readingSettings.fontSize}, fontFamily=${this.readingSettings.fontFamily}, fontPath=${this.readingSettings.fontPath || 'none'}, fontWeight=${this.readingSettings.fontWeight}, lineHeight=${this.readingSettings.lineHeight}, pageMargin=${this.readingSettings.pageMargin}, letterSpacing=${this.readingSettings.letterSpacing ?? 0}, paragraphSpacing=${this.readingSettings.paragraphSpacing ?? 8}, firstLineIndent=${this.readingSettings.firstLineIndent ?? 2}, textAlignment=${this.readingSettings.textAlignment ?? 'JUSTIFY'}, tapToTurn=${this.readingSettings.tapToTurn ?? true}), page(mode=${this.pageReadingSettings.readingMode}, direction=${this.pageReadingSettings.readingDirection}, animation=${this.pageReadingSettings.pageTurnAnimation}, volumeKey=${this.pageReadingSettings.volumeKeyNavigation}, autoPageTurn=${this.pageReadingSettings.autoPageTurnInterval})`
      );

      const progress = ebook.readingProgress;
      let restoredSpineIndex = 0;
      let restoredPageOffset = 0;
      if (progress && progress.currentChapterIndex >= 0 && progress.currentChapterIndex < spineItems.length) {
        restoredSpineIndex = progress.currentChapterIndex;
        restoredPageOffset = progress.currentPosition ?? 0;
      } else {
        restoredSpineIndex = 0;
        restoredPageOffset = 0;
      }
      let normalizedSpineIndex = restoredSpineIndex;
      if (!this.isReadableSpineIndex(restoredSpineIndex)) {
        const nextReadable = this.findReadableSpineIndex(restoredSpineIndex + 1, 1);
        const previousReadable = this.findReadableSpineIndex(restoredSpineIndex - 1, -1);
        normalizedSpineIndex = nextReadable >= 0 ? nextReadable : previousReadable;
        if (normalizedSpineIndex >= 0) {
          logger.info(
            TAG,
            `恢复进度命中空 spine，已跳转到可读 spine: restored=${restoredSpineIndex}, normalized=${normalizedSpineIndex}`
          );
          restoredPageOffset = 0;
        } else {
          normalizedSpineIndex = restoredSpineIndex;
        }
      }
      this.currentSpineIndex = normalizedSpineIndex;
      this.currentPageWithinSpine = restoredPageOffset;
      this.currentAnchorFragment = '';
      // [修复] 跨端接续：用源端 wantParam 快照覆盖本地进度（spine + 页内页码）
      if (this.pendingContinuationSpineIndex >= 0) {
        const continuationSpine = this.isReadableSpineIndex(this.pendingContinuationSpineIndex)
          ? this.pendingContinuationSpineIndex
          : normalizedSpineIndex;
        this.currentSpineIndex = continuationSpine;
        this.pendingContinuationSpineIndex = -1;
        logger.info(TAG, `[Distributed] 已应用 WebView EPUB 接续章节: spine=${continuationSpine}`);
      }
      if (this.pendingContinuationPageIndex >= 0) {
        this.currentPageWithinSpine = Math.max(0, this.pendingContinuationPageIndex);
        this.pendingContinuationPageIndex = -1;
        logger.info(TAG, `[Distributed] 已应用 WebView EPUB 接续页码: page=${this.currentPageWithinSpine}`);
      }
      // [修复] 加载完成立即同步一次阅读状态：打开书籍后未翻页就触发接续时，
      // onContinue 守卫依赖 currentRead*（此前该状态只随进度保存更新，会误判拒绝流转）
      distributedReadingService.syncProgress(ebook.id, this.currentSpineIndex, this.currentPageWithinSpine, 0, 'ebook');
      logger.info(TAG, `阅读状态已就绪: bookId=${ebook.id}, spine=${this.currentSpineIndex}, page=${this.currentPageWithinSpine}`);

      this.isLoading = false;
      void this.refreshCurrentSpineHighlightRanges('ebook_loaded');
      this.refreshCurrentEpubBookmarkState('ebook_loaded');
      void this.applyPurifyRulesToCurrentSpine('ebook_loaded');
      this.updateVolumeKeyListener();
      this.syncAutoPageTurnState();
      void this.updateEpubReadAloudContextByPosition();
      this.scheduleRouteReadAloudAutoStart('ebook_loaded', 360);
      this.recordEpubReadFlowEvent(
        EpubReadFlowEventType.BOOK_LOADED,
        'ebook_loaded',
        Math.max(0, Date.now() - loadStartedAt),
        true,
        `format=${ebook.format}, spineItems=${spineItems.length}`
      );
      logger.info(TAG, `EPUB 加载完成: bookId=${bookId}, spineItems=${spineItems.length}, spineIndex=${this.currentSpineIndex}`);
    } catch (error) {
      const msg = String(error);
      logger.error(TAG, `EPUB 加载失败: ${msg}`);
      this.errorMessage = msg;
      this.isLoading = false;
      this.updateVolumeKeyListener();
      this.recordEpubReadFlowEvent(
        EpubReadFlowEventType.ERROR,
        'ebook_load_failed',
        Math.max(0, Date.now() - loadStartedAt),
        false,
        msg
      );
      this.markDetailOpenReaderReady('ebook_load_failed', false, msg);
      cancelTransition();
    }
  }

  private notifyTransitionReaderReadyOnce(reason: string): void {
    if (this.hasNotifiedTransitionReaderReady) {
      logger.debug(TAG, `过渡动画就绪已通知，忽略重复触发: ${reason}`);
      return;
    }
    this.hasNotifiedTransitionReaderReady = true;
    setReaderReady();
    logger.info(TAG, `📖 已通知过渡动画阅读器就绪: ${reason}`);
    this.recordEpubReadFlowEvent(EpubReadFlowEventType.READER_READY, reason, 0, true, '');
    this.markDetailOpenReaderReady(reason, true, '');
  }

  private startEpubReadFlowSession(bookId: string, bookTitle: string, format: string, reason: string): void {
    if (this.epubReadFlowId.length > 0) {
      return;
    }
    const info = new EpubReadFlowSessionInfo();
    info.readerOpenFlowId = this.readerOpenFlowId;
    info.bookId = bookId;
    info.bookTitle = bookTitle;
    info.format = format;
    info.spineIndex = this.currentSpineIndex;
    info.spinePath = this.resolveSpinePath(this.currentSpineIndex);
    info.readerHostMode = this.readerHostMode;
    info.readerInstanceId = this.readerInstanceId;
    this.epubReadFlowId = EpubReadFlowMonitor.getInstance().startSession(info);
    this.recordEpubReadFlowEvent(EpubReadFlowEventType.PARAM_BOUND, reason, 0, true, `host=${this.readerHostMode}, instance=${this.readerInstanceId}`);
  }

  private recordEpubReadFlowEvent(
    eventType: EpubReadFlowEventType,
    reason: string,
    elapsedMs: number,
    success: boolean,
    detail: string
  ): void {
    const bookId = this.ebook ? this.ebook.id : '';
    if (this.epubReadFlowId.length <= 0) {
      this.startEpubReadFlowSession(bookId, this.getBookTitle(), this.ebook ? String(this.ebook.format) : '', 'auto_start_for_event');
    }
    if (this.epubReadFlowId.length <= 0) {
      return;
    }
    const event = EpubReadFlowMonitor.getInstance().createEvent(
      this.epubReadFlowId,
      eventType,
      bookId,
      this.currentSpineIndex,
      reason
    );
    event.readerOpenFlowId = this.readerOpenFlowId;
    event.spinePath = this.resolveSpinePath(this.currentSpineIndex);
    event.pageIndex = this.currentPageWithinSpine;
    event.pageCount = this.totalPagesInSpine;
    event.elapsedMs = Math.max(0, elapsedMs);
    event.success = success;
    event.detail = detail;
    if (!success) {
      event.severity = EpubReadFlowSeverity.ERROR;
      event.errorMessage = detail;
    }
    if (event.elapsedMs > 0) {
      event.metricName = `epub_read.${eventType}`;
      event.metricValue = event.elapsedMs;
      event.metricUnit = 'ms';
    }
    EpubReadFlowMonitor.getInstance().record(event);
  }

  private handleEpubComponentFlowEvent(event: EpubWebComponentFlowEvent): void {
    if (this.epubReadFlowId.length <= 0) {
      this.startEpubReadFlowSession(
        this.ebook ? this.ebook.id : '',
        this.getBookTitle(),
        this.ebook ? String(this.ebook.format) : '',
        'component_flow_event'
      );
    }
    if (this.epubReadFlowId.length <= 0) {
      return;
    }
    let eventType = EpubReadFlowEventType.WEBVIEW_LOAD_START;
    if (event.eventName === EpubWebComponentFlowEventName.WEBVIEW_LOAD_END) {
      eventType = EpubReadFlowEventType.WEBVIEW_LOAD_END;
    } else if (event.eventName === EpubWebComponentFlowEventName.WEBVIEW_ERROR) {
      eventType = EpubReadFlowEventType.WEBVIEW_ERROR;
    } else if (event.eventName === EpubWebComponentFlowEventName.JS_EXECUTED) {
      eventType = EpubReadFlowEventType.JS_EXECUTED;
    } else if (event.eventName === EpubWebComponentFlowEventName.JS_FAILED) {
      eventType = EpubReadFlowEventType.JS_FAILED;
    } else if (event.eventName === EpubWebComponentFlowEventName.PAGINATION_CHANGED) {
      eventType = EpubReadFlowEventType.PAGINATION_CHANGED;
    }
    const flowEvent = EpubReadFlowMonitor.getInstance().createEvent(
      this.epubReadFlowId,
      eventType,
      this.ebook ? this.ebook.id : '',
      this.currentSpineIndex,
      event.reason
    );
    flowEvent.readerOpenFlowId = this.readerOpenFlowId;
    flowEvent.spinePath = event.url.length > 0 ? event.url : this.resolveSpinePath(this.currentSpineIndex);
    flowEvent.pageIndex = event.pageIndex;
    flowEvent.pageCount = event.pageCount;
    flowEvent.elapsedMs = event.elapsedMs;
    flowEvent.success = event.success;
    flowEvent.errorMessage = event.errorMessage;
    flowEvent.detail = event.detail;
    if (!event.success) {
      flowEvent.severity = EpubReadFlowSeverity.ERROR;
    }
    if (event.elapsedMs > 0) {
      flowEvent.metricName = `epub_read.${eventType}`;
      flowEvent.metricValue = event.elapsedMs;
      flowEvent.metricUnit = 'ms';
    }
    EpubReadFlowMonitor.getInstance().record(flowEvent);
  }

  private markDetailOpenReaderReady(reason: string, success: boolean, detail: string): void {
    if (this.readerOpenFlowId.length <= 0) {
      return;
    }
    const event = DetailOpenFlowMonitor.getInstance().createEvent(
      this.readerOpenFlowId,
      success ? DetailOpenFlowEventType.READER_READY : DetailOpenFlowEventType.READER_FAILED,
      this.ebook ? this.ebook.id : '',
      this.spineItems.length > this.currentSpineIndex ? this.spineItems[this.currentSpineIndex].id : '',
      this.currentSpineIndex,
      reason
    );
    event.targetKind = DetailOpenFlowTargetKind.EPUB_WEBVIEW;
    event.routeName = 'EpubWebViewReaderPage';
    event.chapterTitle = this.getCurrentChapterTitle();
    event.elapsedMs = DetailOpenFlowMonitor.getInstance().getSessionElapsedMs(this.readerOpenFlowId);
    event.success = success;
    event.detail = detail;
    if (!success) {
      event.errorMessage = detail;
    }
    DetailOpenFlowMonitor.getInstance().record(event);
    DetailOpenFlowMonitor.getInstance().endSession(this.readerOpenFlowId, reason);
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

  // ──── Spine 路径解析 ────

  private resolveSpinePath(spineIndex: number): string {
    if (spineIndex < 0 || spineIndex >= this.spineItems.length) {
      return '';
    }
    const chapter = this.spineItems[spineIndex];
    const rf = (chapter.resourceFile ?? '').trim().replace(/^\//, '');
    const rh = (chapter.resourceHref ?? '').trim().replace(/^\//, '');
    const resourcePath = rf || rh;
    if (!resourcePath) {
      return '';
    }
    return `${this.extractedRoot}/${resourcePath}`;
  }

  private readUtf8TextFileSync(path: string): string {
    const file = SafeFileUtils.openSync(path, fileIo.OpenMode.READ_ONLY);
    try {
      const stat = SafeFileUtils.statSync(file.fd);
      if (stat.size <= 0) {
        return '';
      }
      const buffer = new ArrayBuffer(stat.size);
      const readLength = SafeFileUtils.readSync(file.fd, buffer);
      const bytes = readLength > 0 ? new Uint8Array(buffer, 0, readLength) : new Uint8Array(buffer);
      return new util.TextDecoder('utf-8', { ignoreBOM: true }).decodeToString(bytes);
    } finally {
      SafeFileUtils.closeSync(file);
    }
  }

  private localPathExists(path: string): boolean {
    const normalizedPath = path.trim();
    if (normalizedPath.length <= 0) {
      return false;
    }
    try {
      return SafeFileUtils.accessSync(normalizedPath);
    } catch (_error) {
      return false;
    }
  }

  private stripFileUriPrefix(path: string): string {
    const trimmed = path.trim();
    if (trimmed.startsWith('file://')) {
      return trimmed.substring('file://'.length);
    }
    return trimmed;
  }

  private isNetworkOrDataImagePath(path: string): boolean {
    const lower = path.trim().toLowerCase();
    return lower.startsWith('http://') || lower.startsWith('https://') || lower.startsWith('data:image/');
  }

  private isAbsoluteLocalPath(path: string): boolean {
    const normalized = this.stripFileUriPrefix(path).replace(/\\/g, '/');
    return normalized.startsWith('/') || /^[A-Za-z]:\//.test(normalized);
  }

  private normalizePathSegments(path: string): string {
    const normalized = path.trim().replace(/\\/g, '/');
    const isRooted = normalized.startsWith('/');
    const segments = normalized.split('/');
    const stack: string[] = [];
    for (const segment of segments) {
      if (segment.length <= 0 || segment === '.') {
        continue;
      }
      if (segment === '..') {
        if (stack.length > 0) {
          stack.pop();
        }
        continue;
      }
      stack.push(segment);
    }
    return `${isRooted ? '/' : ''}${stack.join('/')}`;
  }

  private getParentPath(path: string): string {
    const normalized = path.trim().replace(/\\/g, '/');
    const slashIndex = normalized.lastIndexOf('/');
    if (slashIndex <= 0) {
      return '';
    }
    return normalized.substring(0, slashIndex);
  }

  private normalizeEpubResourceRef(resourceRef: string): string {
    let normalized = resourceRef.trim().replace(/\\/g, '/');
    const hashIndex = normalized.indexOf('#');
    if (hashIndex >= 0) {
      normalized = normalized.substring(0, hashIndex);
    }
    const queryIndex = normalized.indexOf('?');
    if (queryIndex >= 0) {
      normalized = normalized.substring(0, queryIndex);
    }
    try {
      normalized = decodeURIComponent(normalized);
    } catch (_error) {
    }
    while (normalized.startsWith('./')) {
      normalized = normalized.substring(2);
    }
    while (normalized.startsWith('/')) {
      normalized = normalized.substring(1);
    }
    return normalized;
  }

  private joinLocalResourcePath(basePath: string, resourceRef: string): string {
    const normalizedBase = this.stripFileUriPrefix(basePath).trim().replace(/\\/g, '/').replace(/\/+$/g, '');
    const normalizedRef = this.normalizeEpubResourceRef(resourceRef);
    if (normalizedBase.length <= 0 || normalizedRef.length <= 0) {
      return '';
    }
    return this.normalizePathSegments(`${normalizedBase}/${normalizedRef}`);
  }

  private shouldRefreshEpubSpineItems(currentItems: EBookChapter[], opfItems: EBookChapter[]): boolean {
    if (opfItems.length <= 0) {
      return false;
    }
    if (currentItems.length !== opfItems.length) {
      return true;
    }
    for (let index = 0; index < opfItems.length; index++) {
      const current = currentItems[index];
      const opf = opfItems[index];
      const currentResourcePath = this.normalizeEpubResourceRef(current.resourceFile ?? current.resourceHref ?? '');
      const opfResourcePath = this.normalizeEpubResourceRef(opf.resourceFile ?? opf.resourceHref ?? '');
      const currentLayoutType = (current.resourceLayoutType ?? '').trim().toUpperCase();
      const opfLayoutType = (opf.resourceLayoutType ?? '').trim().toUpperCase();
      const currentMediaType = (current.resourceMediaType ?? '').trim().toLowerCase();
      const opfMediaType = (opf.resourceMediaType ?? '').trim().toLowerCase();
      if (currentResourcePath !== opfResourcePath) {
        return true;
      }
      if (opfLayoutType.length > 0 && currentLayoutType !== opfLayoutType) {
        return true;
      }
      if (opfMediaType.length > 0 && currentMediaType !== opfMediaType) {
        return true;
      }
    }
    return false;
  }

  private appendUniqueCoverCandidate(candidates: string[], candidate: string): void {
    const normalized = candidate.trim();
    if (normalized.length <= 0) {
      return;
    }
    if (!candidates.includes(normalized)) {
      candidates.push(normalized);
    }
  }

  private toMediaImageUri(localPath: string): string {
    const normalized = this.stripFileUriPrefix(localPath).trim().replace(/\\/g, '/');
    if (normalized.length <= 0) {
      return '';
    }
    if (/^[A-Za-z]:\//.test(normalized)) {
      return `file:///${normalized}`;
    }
    if (normalized.startsWith('/')) {
      return `file://${normalized}`;
    }
    return normalized;
  }

  private resolveEpubPackageDocumentPath(): string {
    const root = (this.extractedRoot || this.ebook?.extractedRootPath || '').trim();
    if (root.length <= 0) {
      return '';
    }
    try {
      return resolveEpubPackageDocumentPathFromRoot(root);
    } catch (error) {
      logger.warn(TAG, `解析 EPUB package document 失败: ${String(error)}`);
      return '';
    }
  }

  private extractXmlAttribute(attrs: string, name: string): string {
    const pattern = new RegExp(`${name}\\s*=\\s*["']([^"']+)["']`, 'i');
    const match = attrs.match(pattern);
    return match && match[1] ? String(match[1]).trim() : '';
  }

  private collectEpubOpfCoverCandidates(): string[] {
    const candidates: string[] = [];
    const opfPath = this.resolveEpubPackageDocumentPath();
    if (opfPath.length <= 0 || !this.localPathExists(opfPath)) {
      return candidates;
    }
    try {
      const opfText = this.readUtf8TextFileSync(opfPath);
      const packageRoot = this.getParentPath(opfPath);
      const metaMatch = opfText.match(EPUB_OPF_META_COVER_PATTERN);
      const coverId = metaMatch && metaMatch[1] ? String(metaMatch[1]).trim() : '';
      const itemPattern = /<item\b([^>]*?)\/?>/gi;
      let itemMatch = itemPattern.exec(opfText);
      while (itemMatch !== null) {
        const attrs = itemMatch[1] ? String(itemMatch[1]) : '';
        const id = this.extractXmlAttribute(attrs, 'id');
        const href = this.extractXmlAttribute(attrs, 'href');
        const mediaType = this.extractXmlAttribute(attrs, 'media-type').toLowerCase();
        const properties = this.extractXmlAttribute(attrs, 'properties').toLowerCase();
        if (href.length > 0 && mediaType.startsWith('image/')) {
          const resolved = this.joinLocalResourcePath(packageRoot, href);
          const lowerHref = href.toLowerCase();
          if (coverId.length > 0 && id === coverId) {
            this.appendUniqueCoverCandidate(candidates, resolved);
          } else if (properties.includes('cover-image')) {
            this.appendUniqueCoverCandidate(candidates, resolved);
          } else if (lowerHref.includes('cover') || lowerHref.includes('folder') || lowerHref.includes('front')) {
            this.appendUniqueCoverCandidate(candidates, resolved);
          } else if (candidates.length <= 0) {
            this.appendUniqueCoverCandidate(candidates, resolved);
          }
        }
        itemMatch = itemPattern.exec(opfText);
      }
    } catch (error) {
      logger.warn(TAG, `解析 EPUB OPF 封面失败: ${String(error)}`);
    }
    return candidates;
  }

  private resolveExistingLocalCoverPath(candidates: string[]): string {
    for (const candidate of candidates) {
      const localPath = this.stripFileUriPrefix(candidate).replace(/\\/g, '/');
      if (this.isAbsoluteLocalPath(localPath) && this.localPathExists(localPath)) {
        return localPath;
      }
    }
    return '';
  }

  private resolveEpubReadAloudCoverUrl(ebook: EBook): string {
    const rawCover = (ebook.metadata.coverImagePath || '').trim();
    if (rawCover.length > 0 && this.isNetworkOrDataImagePath(rawCover)) {
      return rawCover;
    }
    if (rawCover.startsWith('app.media.')) {
      return '';
    }

    const candidates: string[] = [];
    const root = (this.extractedRoot || ebook.extractedRootPath || '').trim();
    const opfPath = this.resolveEpubPackageDocumentPath();
    const packageRoot = opfPath.length > 0 ? this.getParentPath(opfPath) : root;

    if (rawCover.length > 0) {
      const rawLocal = this.stripFileUriPrefix(rawCover).replace(/\\/g, '/');
      if (this.isAbsoluteLocalPath(rawLocal)) {
        this.appendUniqueCoverCandidate(candidates, rawLocal);
      } else {
        this.appendUniqueCoverCandidate(candidates, this.joinLocalResourcePath(root, rawCover));
        this.appendUniqueCoverCandidate(candidates, this.joinLocalResourcePath(packageRoot, rawCover));
      }
    }

    const opfCandidates = this.collectEpubOpfCoverCandidates();
    for (const candidate of opfCandidates) {
      this.appendUniqueCoverCandidate(candidates, candidate);
    }

    const localCoverPath = this.resolveExistingLocalCoverPath(candidates);
    if (localCoverPath.length > 0) {
      return this.toMediaImageUri(localCoverPath);
    }
    return rawCover;
  }

  private extractBodyHtml(htmlText: string): string {
    const bodyMatch = htmlText.match(/<body\b[^>]*>([\s\S]*?)<\/body>/i);
    if (bodyMatch && bodyMatch[1]) {
      return bodyMatch[1];
    }
    return htmlText
      .replace(/<head[\s\S]*?<\/head>/ig, ' ')
      .replace(/<\?xml[\s\S]*?\?>/ig, ' ')
      .replace(/<!DOCTYPE[\s\S]*?>/ig, ' ');
  }

  private decodeCommonHtmlEntities(text: string): string {
    return text
      .replace(/&nbsp;|&#160;/ig, ' ')
      .replace(/&lt;/ig, '<')
      .replace(/&gt;/ig, '>')
      .replace(/&amp;/ig, '&')
      .replace(/&quot;/ig, '"')
      .replace(/&#39;|&apos;/ig, "'")
      .replace(/&#x([0-9a-f]+);/ig, (_match: string, value: string) => {
        const parsed = parseInt(value, 16);
        return Number.isFinite(parsed) && parsed > 0 ? String.fromCharCode(parsed) : ' ';
      })
      .replace(/&#([0-9]+);/g, (_match: string, value: string) => {
        const parsed = parseInt(value, 10);
        return Number.isFinite(parsed) && parsed > 0 ? String.fromCharCode(parsed) : ' ';
      });
  }

  private measureVisibleHtmlTextLength(htmlText: string): number {
    const bodyHtml = this.extractBodyHtml(htmlText);
    const visibleText = this.decodeCommonHtmlEntities(bodyHtml
      .replace(/<script[\s\S]*?<\/script>/ig, ' ')
      .replace(/<style[\s\S]*?<\/style>/ig, ' ')
      .replace(/<svg[\s\S]*?<\/svg>/ig, ' ')
      .replace(/<[^>]+>/g, ' '))
      .replace(/\s+/g, '')
      .trim();
    return visibleText.length;
  }

  private hasRenderableHtmlMedia(htmlText: string): boolean {
    const bodyHtml = this.extractBodyHtml(htmlText);
    return /<(img|image|svg|video|audio|canvas|picture|object|embed)\b/i.test(bodyHtml) ||
      /background-image\s*:/i.test(bodyHtml);
  }

  private isImageResourceSpine(chapter: EBookChapter, spinePath: string): boolean {
    const mediaType = (chapter.resourceMediaType ?? '').trim().toLowerCase();
    const layoutType = (chapter.resourceLayoutType ?? '').trim().toUpperCase();
    const imagePath = (chapter.resourceImagePath ?? chapter.resourceImageRelativePath ?? '').trim();
    return mediaType.startsWith('image/') ||
      layoutType === 'IMAGE_PAGE' ||
      IMAGE_RESOURCE_PATH_PATTERN.test(spinePath) ||
      IMAGE_RESOURCE_PATH_PATTERN.test(imagePath);
  }

  private isReadableSpineIndex(spineIndex: number): boolean {
    if (spineIndex < 0 || spineIndex >= this.spineItems.length) {
      return false;
    }
    const cached = this.spineReadableCache.get(spineIndex);
    if (cached !== undefined) {
      return cached;
    }
    if (this.isFixedLayout) {
      this.spineReadableCache.set(spineIndex, true);
      return true;
    }
    const chapter = this.spineItems[spineIndex];
    const spinePath = this.resolveSpinePath(spineIndex);
    if (spinePath.length <= 0) {
      this.spineReadableCache.set(spineIndex, false);
      return false;
    }
    if (this.isImageResourceSpine(chapter, spinePath)) {
      this.spineReadableCache.set(spineIndex, true);
      return true;
    }
    try {
      const htmlText = this.readUtf8TextFileSync(spinePath);
      const visibleTextLength = this.measureVisibleHtmlTextLength(htmlText);
      const hasMedia = this.hasRenderableHtmlMedia(htmlText);
      const readable = visibleTextLength > READABLE_SPINE_TEXT_THRESHOLD || hasMedia;
      this.spineReadableCache.set(spineIndex, readable);
      if (!readable) {
        logger.info(
          TAG,
          `跳过空 spine 候选: index=${spineIndex}, title=${chapter.title}, textLength=${visibleTextLength}, hasMedia=${hasMedia}, path=${spinePath}`
        );
      }
      return readable;
    } catch (error) {
      logger.warn(TAG, `检测 spine 可读性失败，保留原目标: index=${spineIndex}, path=${spinePath}, error=${String(error)}`);
      this.spineReadableCache.set(spineIndex, true);
      return true;
    }
  }

  private findReadableSpineIndex(startIndex: number, step: number): number {
    if (step === 0 || this.spineItems.length <= 0) {
      return -1;
    }
    let index = startIndex;
    while (index >= 0 && index < this.spineItems.length) {
      if (this.isReadableSpineIndex(index)) {
        return index;
      }
      index += step;
    }
    return -1;
  }

  private resolveReadableSpineIndex(
    requestedIndex: number,
    transitionDirection: EpubSpineTransitionDirection
  ): number {
    if (requestedIndex < 0 || requestedIndex >= this.spineItems.length) {
      return -1;
    }
    if (this.isReadableSpineIndex(requestedIndex)) {
      return requestedIndex;
    }
    const preferredStep: number = transitionDirection === 'prev' ? -1 : 1;
    const preferred = this.findReadableSpineIndex(requestedIndex + preferredStep, preferredStep);
    if (preferred >= 0) {
      return preferred;
    }
    const fallbackStep: number = transitionDirection === 'prev' ? 1 : -1;
    return this.findReadableSpineIndex(requestedIndex + fallbackStep, fallbackStep);
  }

  private normalizePathForCompare(path: string): string {
    return path.trim().replace(/\\/g, '/');
  }

  private resolveSpineIndexByPath(spineFilePath: string): number {
    const normalizedTarget = this.normalizePathForCompare(spineFilePath);
    if (normalizedTarget.length <= 0) {
      return this.pendingSpineIndex >= 0 ? this.pendingSpineIndex : this.currentSpineIndex;
    }
    for (let index = 0; index < this.spineItems.length; index++) {
      if (this.normalizePathForCompare(this.resolveSpinePath(index)) === normalizedTarget) {
        return index;
      }
    }
    return this.pendingSpineIndex >= 0 ? this.pendingSpineIndex : this.currentSpineIndex;
  }

  private hasSkippedRuntimeBlankSpine(spineIndex: number): boolean {
    return this.runtimeBlankSpineIndices.includes(spineIndex);
  }

  private findRuntimeBlankFallbackSpineIndex(blankSpineIndex: number): number {
    const nextSpineIndex = this.findReadableSpineIndex(blankSpineIndex + 1, 1);
    if (nextSpineIndex >= 0 && !this.hasSkippedRuntimeBlankSpine(nextSpineIndex)) {
      return nextSpineIndex;
    }
    const previousSpineIndex = this.findReadableSpineIndex(blankSpineIndex - 1, -1);
    if (previousSpineIndex >= 0 && !this.hasSkippedRuntimeBlankSpine(previousSpineIndex)) {
      return previousSpineIndex;
    }
    return -1;
  }

  private handleRuntimeBlankSpine(info: EpubRuntimeBlankSpineInfo): boolean {
    if (this.spineItems.length <= 0) {
      return false;
    }
    if (this.runtimeBlankSpineSkipCount >= RUNTIME_BLANK_SPINE_SKIP_LIMIT) {
      logger.warn(
        TAG,
        `运行时空 WebView spine 跳过次数达到上限，停止自动跳转: count=${this.runtimeBlankSpineSkipCount}, path=${info.spineFilePath}`
      );
      return false;
    }
    const blankSpineIndex = this.resolveSpineIndexByPath(info.spineFilePath);
    if (blankSpineIndex < 0 || blankSpineIndex >= this.spineItems.length) {
      logger.warn(
        TAG,
        `运行时空 WebView spine 无法定位索引: path=${info.spineFilePath}, doc=${info.documentUrl || 'none'}`
      );
      return false;
    }
    if (this.hasSkippedRuntimeBlankSpine(blankSpineIndex)) {
      logger.warn(
        TAG,
        `运行时空 WebView spine 已跳过，停止重复跳转: index=${blankSpineIndex}, path=${info.spineFilePath}`
      );
      return false;
    }

    this.runtimeBlankSpineIndices.push(blankSpineIndex);
    this.runtimeBlankSpineSkipCount++;
    this.spineReadableCache.set(blankSpineIndex, false);

    const fallbackSpineIndex = this.findRuntimeBlankFallbackSpineIndex(blankSpineIndex);
    if (fallbackSpineIndex < 0) {
      logger.warn(
        TAG,
        `运行时空 WebView spine 未找到可跳转目标: index=${blankSpineIndex}, text=${info.bodyTextLength}, media=${info.inlineMediaCount}/${info.blockMediaCount}, bodyChildren=${info.bodyChildCount}, bodyHtml=${info.bodyHtmlLength}`
      );
      return false;
    }

    const fallbackPath = this.resolveSpinePath(fallbackSpineIndex);
    if (fallbackPath.length <= 0) {
      logger.warn(TAG, `运行时空 WebView spine 跳转目标路径为空: target=${fallbackSpineIndex}`);
      return false;
    }

    this.pendingSpineIndex = -1;
    this.currentSpineIndex = fallbackSpineIndex;
    this.currentPageWithinSpine = 0;
    this.totalPagesInSpine = 0;
    this.currentAnchorFragment = '';
    this.syncAutoPageTurnState();

    logger.warn(
      TAG,
      `运行时检测到空 WebView spine，跳转到下一可读 spine: blank=${blankSpineIndex}, target=${fallbackSpineIndex}, source=${info.source}, text=${info.bodyTextLength}, media=${info.inlineMediaCount}/${info.blockMediaCount}, bodyChildren=${info.bodyChildCount}, bodyHtml=${info.bodyHtmlLength}, doc=${info.documentUrl || 'none'}, loaded=${info.loadedFileUrl || 'none'}`
    );

    setTimeout(() => {
      if (this.epubReaderController) {
        this.pendingSpineIndex = fallbackSpineIndex;
        this.epubReaderController.loadSpineItem(
          fallbackPath,
          0,
          'none',
          '',
          this.getSpineLayoutType(fallbackSpineIndex),
          this.getSpineMediaType(fallbackSpineIndex)
        );
        return;
      }
      this.readerMountEpoch = Date.now();
    }, 0);
    return true;
  }

  private buildFallbackNavigationTargets(spineItems: EBookChapter[]): EpubNavigationItem[] {
    const items: EpubNavigationItem[] = [];
    for (let index = 0; index < spineItems.length; index++) {
      const chapter = spineItems[index];
      const resourcePath = (chapter.resourceFile ?? chapter.resourceHref ?? '').trim();
      items.push({
        id: chapter.id,
        title: (chapter.title ?? '').trim().length > 0 ? chapter.title : `第 ${index + 1} 章`,
        href: chapter.resourceHref ?? resourcePath,
        resourcePath: resourcePath,
        fragment: '',
        spineIndex: index,
        level: 0,
        playOrder: index + 1
      });
    }
    return items;
  }

  private buildNavigationChapters(
    navigationItems: EpubNavigationItem[],
    spineItems: EBookChapter[],
    bookId: string
  ): EBookChapter[] {
    const chapters: EBookChapter[] = [];
    const now = Date.now();
    for (let index = 0; index < navigationItems.length; index++) {
      const item = navigationItems[index];
      const spine = item.spineIndex >= 0 && item.spineIndex < spineItems.length
        ? spineItems[item.spineIndex]
        : null;
      const title = item.title.trim().length > 0 ? item.title.trim() : `第 ${index + 1} 章`;
      const chapter: EBookChapter = {
        id: item.id.length > 0 ? item.id : `epub_nav_${index}`,
        bookId: bookId,
        chapterNumber: index + 1,
        title: title,
        content: '',
        startPosition: 0,
        endPosition: 0,
        wordCount: 0,
        resourceHref: item.href,
        resourceFile: spine ? (spine.resourceFile ?? '') : item.resourcePath,
        resourceMediaType: spine ? (spine.resourceMediaType ?? '') : '',
        resourceLayoutType: spine ? (spine.resourceLayoutType ?? '') : '',
        resourceImagePath: spine ? (spine.resourceImagePath ?? '') : '',
        resourceImageRelativePath: spine ? (spine.resourceImageRelativePath ?? '') : '',
        createTime: now
      };
      chapters.push(chapter);
    }
    return chapters;
  }

  private isGenericNavigationTitle(title: string): boolean {
    const normalized = title.trim();
    if (normalized.length <= 0) {
      return true;
    }
    return /^Chapter\s+\d+$/i.test(normalized) ||
      /^第\s*\d+\s*章$/.test(normalized) ||
      /^第\s*\d+$/.test(normalized) ||
      /^正文\s*\d*$/.test(normalized) ||
      normalized === '开始阅读';
  }

  private shouldPreferGeneratedNavigation(
    currentItems: EpubNavigationItem[],
    generatedItems: EpubNavigationItem[]
  ): boolean {
    if (generatedItems.length <= 0) {
      return false;
    }
    if (currentItems.length <= 0) {
      return true;
    }
    let genericCount = 0;
    for (let i = 0; i < currentItems.length; i++) {
      if (this.isGenericNavigationTitle(currentItems[i].title)) {
        genericCount++;
      }
    }
    const genericRatio = currentItems.length > 0 ? genericCount / currentItems.length : 0;
    return genericRatio >= 0.7 && generatedItems.length >= Math.max(2, Math.floor(currentItems.length * 0.35));
  }

  private configureNavigationTargets(
    bookId: string,
    extractedRoot: string,
    spineItems: EBookChapter[]
  ): void {
    let navigationItems = EBookParserFactory.parseEpubNavigationItems(extractedRoot, spineItems);
    const generatedNavigationItems = EBookParserFactory.parseEpubGeneratedNavigationItems(extractedRoot, spineItems);
    if (this.shouldPreferGeneratedNavigation(navigationItems, generatedNavigationItems)) {
      navigationItems = generatedNavigationItems;
      logger.info(TAG, `使用正文标题生成目录: count=${navigationItems.length}`);
    } else if (navigationItems.length <= 0) {
      navigationItems = this.buildFallbackNavigationTargets(spineItems);
      logger.info(TAG, `未解析到 EPUB 目录，回退为 spine 列表: count=${navigationItems.length}`);
    } else {
      logger.info(
        TAG,
        `EPUB 目录解析成功: navItems=${navigationItems.length}, generated=${generatedNavigationItems.length}, spineItems=${spineItems.length}`
      );
    }
    this.navigationTargets = navigationItems;
    this.navigationChapters = this.buildNavigationChapters(navigationItems, spineItems, bookId);
  }

  private getCurrentNavigationIndex(): number {
    if (this.navigationTargets.length <= 0) {
      return Math.max(0, Math.min(this.currentSpineIndex, Math.max(0, this.spineItems.length - 1)));
    }
    let targetIndex = 0;
    for (let index = 0; index < this.navigationTargets.length; index++) {
      const item = this.navigationTargets[index];
      if (item.spineIndex <= this.currentSpineIndex) {
        targetIndex = index;
        continue;
      }
      break;
    }
    return targetIndex;
  }

  private navigateToNavigationIndex(index: number): void {
    if (index < 0 || index >= this.navigationTargets.length) {
      return;
    }
    const item = this.navigationTargets[index];
    const fragment = item.fragment.trim();
    if (index === this.getCurrentNavigationIndex() &&
      item.spineIndex === this.currentSpineIndex &&
      fragment.length <= 0) {
      return;
    }
    if (this.currentSpineIndex === item.spineIndex && fragment.length > 0) {
      this.handleEpubManualReadAloudNavigation('toc_anchor_jump');
      const moved = this.epubReaderController?.goToAnchor(fragment) ?? false;
      if (moved) {
        this.currentAnchorFragment = fragment;
        logger.info(TAG, `目录跳转到当前 spine 锚点: index=${index}, spine=${item.spineIndex}, fragment=${fragment}`);
        void this.saveReadingProgress('toc_anchor_jump_same_spine');
        return;
      }
    }
    this.loadSpineItem(item.spineIndex, 0, 'none', fragment, 'manual');
    logger.info(TAG, `目录跳转: index=${index}, spine=${item.spineIndex}, fragment=${fragment || 'none'}`);
  }

  private getSpineLayoutType(spineIndex: number): string {
    if (spineIndex < 0 || spineIndex >= this.spineItems.length) {
      return '';
    }
    return this.spineItems[spineIndex].resourceLayoutType ?? '';
  }

  private getSpineMediaType(spineIndex: number): string {
    if (spineIndex < 0 || spineIndex >= this.spineItems.length) {
      return '';
    }
    return this.spineItems[spineIndex].resourceMediaType ?? '';
  }

  private getCurrentSpineChapter(): EBookChapter | null {
    if (this.currentSpineIndex < 0 || this.currentSpineIndex >= this.spineItems.length) {
      return null;
    }
    return this.spineItems[this.currentSpineIndex];
  }

  private buildCurrentEpubAnchor(snapshot: EpubWebSelectionSnapshot): AnnotationAnchor {
    const chapter = this.getCurrentSpineChapter();
    const anchor: AnnotationAnchor = {
      chapterId: chapter ? chapter.id : '',
      chapterTitle: chapter ? chapter.title : '',
      chapterIndex: this.currentSpineIndex,
      pageIndex: Math.max(0, Math.floor(snapshot.pageIndex)),
      progress: Math.max(0, Math.min(1, snapshot.pageProgress)),
      startOffset: Math.max(0, Math.floor(snapshot.startOffset)),
      endOffset: Math.max(Math.floor(snapshot.startOffset) + 1, Math.floor(snapshot.endOffset)),
      quoteText: snapshot.selectedText,
      contextBefore: snapshot.contextBefore,
      contextAfter: snapshot.contextAfter
    };
    return anchor;
  }

  private parseEpubHighlightColor(styleJson: string): string {
    const defaultColor = '#E8A317';
    if (!styleJson || styleJson.trim().length <= 0) {
      return defaultColor;
    }
    try {
      const style = SafeUtils.parseObj(styleJson) as HighlightStyle;
      if (style && style.color && style.color.trim().length > 0) {
        return style.color;
      }
      return defaultColor;
    } catch (_error) {
      return defaultColor;
    }
  }

  private parseEpubHighlightLineType(styleJson: string): HighlightLineType {
    if (!styleJson || styleJson.trim().length <= 0) {
      return HighlightLineType.UNDERLINE;
    }
    try {
      const style = SafeUtils.parseObj(styleJson) as HighlightStyle;
      if (style && style.lineType === HighlightLineType.WAVY) {
        return HighlightLineType.WAVY;
      }
      return HighlightLineType.UNDERLINE;
    } catch (_error) {
      return HighlightLineType.UNDERLINE;
    }
  }

  private async refreshCurrentSpineHighlightRanges(trigger: string): Promise<void> {
    const ebook = this.ebook;
    if (!ebook) {
      this.currentSpineHighlightRanges = [];
      return;
    }
    const chapter = this.getCurrentSpineChapter();
    const chapterId = chapter ? chapter.id : '';
    try {
      const records = await this.annotationManager.getContentAnnotations(
        UnifiedContentType.EBOOK,
        ebook.id,
        UnifiedAnnotationType.HIGHLIGHT,
        chapterId,
        this.currentSpineIndex
      );
      const thoughtRecords = await this.annotationManager.getContentAnnotations(
        UnifiedContentType.EBOOK,
        ebook.id,
        UnifiedAnnotationType.THOUGHT,
        chapterId,
        this.currentSpineIndex
      );
      const thoughtByHighlightId: Map<string, string> = new Map<string, string>();
      const thoughtByAnchorKey: Map<string, string> = new Map<string, string>();
      for (let i = 0; i < thoughtRecords.length; i++) {
        const thoughtRecord = thoughtRecords[i];
        const thoughtText = (thoughtRecord.textContent || '').trim();
        if (thoughtRecord.linkedAnnotationId && thoughtRecord.linkedAnnotationId.length > 0) {
          if (!thoughtByHighlightId.has(thoughtRecord.linkedAnnotationId)) {
            thoughtByHighlightId.set(thoughtRecord.linkedAnnotationId, thoughtText);
          }
        }
        const anchorKey = `${Math.floor(thoughtRecord.startOffset)}_${Math.floor(thoughtRecord.endOffset)}_${thoughtRecord.quoteText || ''}`;
        if (!thoughtByAnchorKey.has(anchorKey)) {
          thoughtByAnchorKey.set(anchorKey, thoughtText);
        }
      }

      const ranges: EpubWebHighlightRange[] = [];
      let linkedThoughtCount = 0;
      for (let i = 0; i < records.length; i++) {
        const record = records[i];
        const start = Math.max(0, Math.floor(record.startOffset));
        const end = Math.max(start + 1, Math.floor(record.endOffset));
        if (end <= start) {
          continue;
        }
        let thoughtText = thoughtByHighlightId.get(record.id) || '';
        if (thoughtText.length <= 0) {
          const anchorKey = `${start}_${end}_${record.quoteText || ''}`;
          thoughtText = thoughtByAnchorKey.get(anchorKey) || '';
        }
        if (thoughtText.trim().length > 0) {
          linkedThoughtCount += 1;
        }
        const range: EpubWebHighlightRange = {
          id: record.id,
          startOffset: start,
          endOffset: end,
          color: this.parseEpubHighlightColor(record.styleJson),
          lineType: this.parseEpubHighlightLineType(record.styleJson),
          quoteText: record.quoteText || '',
          pageIndex: record.pageIndex,
          thoughtText
        };
        ranges.push(range);
      }
      ranges.sort((a: EpubWebHighlightRange, b: EpubWebHighlightRange) => a.startOffset - b.startOffset);
      this.currentSpineHighlightRanges = ranges;
      logger.info(
        TAG,
        `刷新 EPUB Web 划线渲染数据成功: trigger=${trigger}, spine=${this.currentSpineIndex}, count=${ranges.length}, thoughtLinked=${linkedThoughtCount}`
      );
    } catch (error) {
      this.currentSpineHighlightRanges = [];
      logger.error(TAG, `刷新 EPUB Web 划线渲染数据失败: trigger=${trigger}, error=${String(error)}`);
    }
  }

  private onAddEpubHighlight(snapshot: EpubWebSelectionSnapshot): void {
    logger.info(
      TAG,
      `触发 EPUB Web 划线指令: spine=${this.currentSpineIndex}, start=${snapshot.startOffset}, end=${snapshot.endOffset}, textLength=${snapshot.selectedText.length}`
    );
    void this.createEpubHighlightByStyle(snapshot, false);
  }

  private onAddEpubHighlightWithThought(snapshot: EpubWebSelectionSnapshot): void {
    logger.info(
      TAG,
      `触发 EPUB Web 划线+想法指令: spine=${this.currentSpineIndex}, start=${snapshot.startOffset}, end=${snapshot.endOffset}, textLength=${snapshot.selectedText.length}`
    );
    void this.createEpubHighlightByStyle(snapshot, true);
  }

  private onUpdateEpubHighlightStyle(highlightId: string, lineType: HighlightLineType, color: string): void {
    this.applyLocalEpubHighlightStyle(highlightId, lineType, color);
    void this.updateEpubHighlightStyle(highlightId, lineType, color);
  }

  private onUpdateEpubHighlightThought(highlightId: string, thoughtText: string): void {
    this.applyLocalEpubHighlightThought(highlightId, thoughtText);
    void this.updateEpubHighlightThought(highlightId, thoughtText);
  }

  private applyLocalEpubHighlightStyle(highlightId: string, lineType: HighlightLineType, color: string): void {
    if (!highlightId || highlightId.length <= 0 || this.currentSpineHighlightRanges.length <= 0) {
      return;
    }
    const safeColor = color && color.trim().length > 0 ? color : '#E8A317';
    let changed = false;
    const updatedRanges: EpubWebHighlightRange[] = [];
    for (let i = 0; i < this.currentSpineHighlightRanges.length; i++) {
      const item = this.currentSpineHighlightRanges[i];
      if (item.id === highlightId) {
        const updated: EpubWebHighlightRange = {
          id: item.id,
          startOffset: item.startOffset,
          endOffset: item.endOffset,
          color: safeColor,
          lineType,
          quoteText: item.quoteText,
          pageIndex: item.pageIndex,
          thoughtText: item.thoughtText
        };
        updatedRanges.push(updated);
        changed = true;
      } else {
        updatedRanges.push(item);
      }
    }
    if (changed) {
      this.currentSpineHighlightRanges = updatedRanges;
      logger.info(TAG, `EPUB Web 划线样式本地刷新成功: highlightId=${highlightId}, lineType=${lineType}, color=${safeColor}`);
    }
  }

  private applyLocalEpubHighlightThought(highlightId: string, thoughtText: string): void {
    if (!highlightId || highlightId.length <= 0 || this.currentSpineHighlightRanges.length <= 0) {
      return;
    }
    const safeThoughtText = thoughtText.trim();
    let changed = false;
    const updatedRanges: EpubWebHighlightRange[] = [];
    for (let i = 0; i < this.currentSpineHighlightRanges.length; i++) {
      const item = this.currentSpineHighlightRanges[i];
      if (item.id === highlightId) {
        const updated: EpubWebHighlightRange = {
          id: item.id,
          startOffset: item.startOffset,
          endOffset: item.endOffset,
          color: item.color,
          lineType: item.lineType,
          quoteText: item.quoteText,
          pageIndex: item.pageIndex,
          thoughtText: safeThoughtText
        };
        updatedRanges.push(updated);
        changed = true;
      } else {
        updatedRanges.push(item);
      }
    }
    if (changed) {
      this.currentSpineHighlightRanges = updatedRanges;
      logger.info(TAG, `EPUB Web 划线想法本地刷新成功: highlightId=${highlightId}, textLength=${safeThoughtText.length}`);
    }
  }

  private async updateEpubHighlightStyle(highlightId: string, lineType: HighlightLineType, color: string): Promise<void> {
    const ebook = this.ebook;
    if (!ebook || !highlightId || highlightId.length <= 0) {
      return;
    }
    const safeColor = color && color.trim().length > 0 ? color : '#E8A317';
    try {
      await this.annotationManager.updateHighlightStyle(highlightId, {
        lineType,
        color: safeColor
      });
      await this.refreshCurrentSpineHighlightRanges('update_highlight_style');
      logger.info(TAG, `EPUB Web 划线样式更新成功: highlightId=${highlightId}, lineType=${lineType}, color=${safeColor}`);
    } catch (error) {
      logger.error(TAG, `更新 EPUB Web 划线样式失败: highlightId=${highlightId}, error=${String(error)}`);
    }
  }

  private async updateEpubHighlightThought(highlightId: string, thoughtText: string): Promise<void> {
    const ebook = this.ebook;
    if (!ebook || !highlightId || highlightId.length <= 0) {
      return;
    }
    const safeThoughtText = thoughtText.trim();
    try {
      const linkedThought = await this.annotationManager.getLinkedThoughtByHighlightId(
        UnifiedContentType.EBOOK,
        ebook.id,
        highlightId
      );

      if (linkedThought) {
        await this.annotationManager.updateAnnotationText(linkedThought.id, linkedThought.title || '', safeThoughtText);
      } else if (safeThoughtText.length > 0) {
        const targetHighlight = await this.annotationManager.getAnnotationById(highlightId);
        if (!targetHighlight) {
          logger.warn(TAG, `更新 EPUB Web 划线想法失败: 未找到对应划线, highlightId=${highlightId}`);
          return;
        }
        const anchor: AnnotationAnchor = {
          chapterId: targetHighlight.chapterId,
          chapterTitle: targetHighlight.chapterTitle,
          chapterIndex: targetHighlight.chapterIndex,
          pageIndex: targetHighlight.pageIndex,
          progress: targetHighlight.pageProgress,
          startOffset: targetHighlight.startOffset,
          endOffset: targetHighlight.endOffset,
          quoteText: targetHighlight.quoteText,
          contextBefore: targetHighlight.anchor.contextBefore ?? '',
          contextAfter: targetHighlight.anchor.contextAfter ?? ''
        };
        await this.annotationManager.createThought({
          contentType: UnifiedContentType.EBOOK,
          contentId: ebook.id,
          anchor,
          textContent: safeThoughtText,
          linkedAnnotationId: highlightId
        });
      }

      await this.refreshCurrentSpineHighlightRanges('update_highlight_thought');
      logger.info(TAG, `EPUB Web 划线想法更新成功: highlightId=${highlightId}, textLength=${safeThoughtText.length}`);
    } catch (error) {
      logger.error(TAG, `更新 EPUB Web 划线想法失败: highlightId=${highlightId}, error=${String(error)}`);
    }
  }

  private async createEpubHighlightByStyle(
    snapshot: EpubWebSelectionSnapshot,
    withThought: boolean
  ): Promise<void> {
    const ebook = this.ebook;
    if (!ebook) {
      this.getUIContext().getPromptAction().showToast({ message: '书籍信息未就绪', duration: 1500 });
      return;
    }

    const lineType = HighlightLineType.UNDERLINE;
    const color = '#E8A317';
    try {
      const anchor = this.buildCurrentEpubAnchor(snapshot);
      const thoughtPayload: CreateThoughtInput | undefined = withThought
        ? {
            contentType: UnifiedContentType.EBOOK,
            contentId: ebook.id,
            anchor: anchor,
            textContent: ''
          }
        : undefined;
      const highlight = await this.annotationManager.createHighlightWithThoughtTransaction({
        contentType: UnifiedContentType.EBOOK,
        contentId: ebook.id,
        anchor,
        style: {
          lineType,
          color
        }
      }, thoughtPayload);
      await this.refreshCurrentSpineHighlightRanges('create_highlight');
      logger.info(
        TAG,
        `EPUB Web 划线创建成功: annotationId=${highlight.id}, spine=${this.currentSpineIndex}, start=${snapshot.startOffset}, end=${snapshot.endOffset}, withThought=${withThought}`
      );
      this.getUIContext().getPromptAction().showToast({
        message: withThought ? '划线和想法已保存' : '划线已保存',
        duration: 1500
      });
    } catch (error) {
      logger.error(TAG, `创建 EPUB Web 划线失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: '划线保存失败', duration: 1500 });
    }
  }

  private resolveAbilityContext(): common.UIAbilityContext | null {
    if (this.context) {
      return this.context;
    }
    try {
      const hostContext = (this.getUIContext().getHostContext() as common.UIAbilityContext);
      if (!hostContext) {
        return null;
      }
      this.context = hostContext as common.UIAbilityContext;
      return this.context;
    } catch (error) {
      logger.warn(TAG, `获取 UIAbilityContext 失败: ${String(error)}`);
      return null;
    }
  }

  private queryCurrentEpubTextSnapshot(): Promise<EpubWebTextSnapshot | null> {
    return new Promise<EpubWebTextSnapshot | null>((resolve) => {
      if (!this.epubReaderController) {
        resolve(null);
        return;
      }
      this.epubReaderController.queryCurrentTextSnapshot((snapshot: EpubWebTextSnapshot | null) => {
        if (snapshot) {
          this.currentVisibleTextSnapshot = snapshot;
          this.currentSpineTextCache = snapshot.text;
          this.currentSpineTextCacheIndex = this.currentSpineIndex;
        }
        resolve(snapshot);
      });
    });
  }

  private buildFallbackEpubBookmarkContext(): EpubBookmarkContext | null {
    const ebook = this.ebook;
    if (!ebook) {
      return null;
    }
    const chapter = this.getCurrentSpineChapter();
    const hasPages = this.totalPagesInSpine > 0;
    const safePage = Math.max(0, this.currentPageWithinSpine);
    const context: EpubBookmarkContext = {
      chapterId: chapter ? chapter.id : '',
      chapterTitle: chapter ? (chapter.title || `第 ${this.currentSpineIndex + 1} 章`) : `第 ${this.currentSpineIndex + 1} 章`,
      chapterIndex: this.currentSpineIndex,
      pageIndex: safePage,
      progress: hasPages ? Math.max(0, Math.min(1, (safePage + 1) / this.totalPagesInSpine)) : this.getCurrentSpineReadRatio(),
      startOffset: -1,
      endOffset: -1,
      quoteText: '',
      contextBefore: '',
      contextAfter: '',
      isTextMode: false
    };
    return context;
  }

  private buildEpubBookmarkContextFromSnapshot(snapshot: EpubWebTextSnapshot): EpubBookmarkContext | null {
    const fallback = this.buildFallbackEpubBookmarkContext();
    if (!fallback) {
      return null;
    }
    const startOffset = Math.max(0, Math.floor(snapshot.startOffset));
    const endOffset = Math.max(startOffset + 1, Math.floor(snapshot.endOffset));
    const quoteText = snapshot.quoteText && snapshot.quoteText.trim().length > 0
      ? snapshot.quoteText.trim()
      : snapshot.text.substring(startOffset, Math.min(snapshot.text.length, endOffset)).replace(/\s+/g, ' ').trim();
    const context: EpubBookmarkContext = {
      chapterId: fallback.chapterId,
      chapterTitle: fallback.chapterTitle,
      chapterIndex: fallback.chapterIndex,
      pageIndex: Math.max(0, Math.floor(snapshot.pageIndex)),
      progress: Math.max(0, Math.min(1, snapshot.pageProgress)),
      startOffset,
      endOffset,
      quoteText: quoteText.length > 120 ? quoteText.substring(0, 120) : quoteText,
      contextBefore: snapshot.contextBefore,
      contextAfter: snapshot.contextAfter,
      isTextMode: true
    };
    return context;
  }

  private async getCurrentEpubBookmarkContext(): Promise<EpubBookmarkContext | null> {
    const snapshot = await this.queryCurrentEpubTextSnapshot();
    if (snapshot && snapshot.text.trim().length > 0) {
      const context = this.buildEpubBookmarkContextFromSnapshot(snapshot);
      if (context) {
        return context;
      }
    }
    return this.buildFallbackEpubBookmarkContext();
  }

  private buildEpubBookmarkTitle(context: EpubBookmarkContext): string {
    return `${context.chapterTitle} · P${context.pageIndex + 1}`;
  }

  private buildCurrentEpubBookmarkAnchor(context: EpubBookmarkContext): AnnotationAnchor {
    const anchor: AnnotationAnchor = {
      chapterId: context.chapterId,
      chapterTitle: context.chapterTitle,
      chapterIndex: context.chapterIndex,
      pageIndex: context.pageIndex,
      progress: context.progress,
      startOffset: context.startOffset,
      endOffset: context.endOffset,
      quoteText: context.quoteText,
      contextBefore: context.contextBefore,
      contextAfter: context.contextAfter
    };
    return anchor;
  }

  private isEpubBookmarkInCurrentContext(record: UnifiedAnnotationRecord, context: EpubBookmarkContext): boolean {
    if (record.pageIndex >= 0 && record.pageIndex === context.pageIndex) {
      return true;
    }
    if (!context.isTextMode || context.endOffset <= context.startOffset) {
      return false;
    }
    if (record.startOffset < 0 || record.endOffset < 0) {
      return false;
    }
    const itemStart = Math.max(0, Math.floor(record.startOffset));
    const itemEnd = Math.max(itemStart + 1, Math.floor(record.endOffset));
    return itemStart < context.endOffset && itemEnd > context.startOffset;
  }

  private refreshCurrentEpubBookmarkState(trigger: string): void {
    void this.refreshCurrentEpubBookmarkStateInternal(trigger);
  }

  private async refreshCurrentEpubBookmarkStateInternal(trigger: string): Promise<void> {
    const ebook = this.ebook;
    if (!ebook) {
      this.currentPageBookmarkId = '';
      this.isCurrentPageBookmarked = false;
      return;
    }
    const context = await this.getCurrentEpubBookmarkContext();
    if (!context) {
      this.currentPageBookmarkId = '';
      this.isCurrentPageBookmarked = false;
      return;
    }
    try {
      const bookmarks = await this.annotationManager.getContentAnnotations(
        UnifiedContentType.EBOOK,
        ebook.id,
        UnifiedAnnotationType.BOOKMARK,
        context.chapterId,
        context.chapterIndex
      );
      let matchedId = '';
      for (let i = 0; i < bookmarks.length; i++) {
        const item = bookmarks[i];
        if (this.isEpubBookmarkInCurrentContext(item, context)) {
          matchedId = item.id;
          break;
        }
      }
      this.currentPageBookmarkId = matchedId;
      this.isCurrentPageBookmarked = matchedId.length > 0;
      logger.debug(
        TAG,
        `刷新 EPUB Web 书签状态: trigger=${trigger}, spine=${context.chapterIndex}, page=${context.pageIndex}, bookmarked=${this.isCurrentPageBookmarked}, bookmarkId=${matchedId || 'none'}`
      );
    } catch (error) {
      logger.error(TAG, `刷新 EPUB Web 书签状态失败: trigger=${trigger}, error=${String(error)}`);
      this.currentPageBookmarkId = '';
      this.isCurrentPageBookmarked = false;
    }
  }

  private async createCurrentEpubBookmark(): Promise<void> {
    const ebook = this.ebook;
    if (!ebook) {
      this.getUIContext().getPromptAction().showToast({ message: '书籍信息未就绪', duration: 1500 });
      return;
    }
    const context = await this.getCurrentEpubBookmarkContext();
    if (!context) {
      this.getUIContext().getPromptAction().showToast({ message: '当前页无法添加书签', duration: 1500 });
      return;
    }
    try {
      const bookmark = await this.annotationManager.createBookmark({
        contentType: UnifiedContentType.EBOOK,
        contentId: ebook.id,
        title: this.buildEpubBookmarkTitle(context),
        textContent: context.quoteText,
        anchor: this.buildCurrentEpubBookmarkAnchor(context)
      });
      this.currentPageBookmarkId = bookmark.id;
      this.isCurrentPageBookmarked = true;
      this.getUIContext().getPromptAction().showToast({ message: '书签已添加', duration: 1200 });
      logger.info(
        TAG,
        `EPUB Web 书签添加成功: spine=${context.chapterIndex}, page=${context.pageIndex}, start=${context.startOffset}, bookmarkId=${bookmark.id}`
      );
    } catch (error) {
      logger.error(TAG, `添加 EPUB Web 书签失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: '添加书签失败', duration: 1500 });
    }
  }

  private async removeCurrentEpubBookmark(): Promise<void> {
    let bookmarkId = this.currentPageBookmarkId;
    if (!bookmarkId || bookmarkId.trim().length <= 0) {
      await this.refreshCurrentEpubBookmarkStateInternal('remove_before_refresh');
      bookmarkId = this.currentPageBookmarkId;
    }
    if (!bookmarkId || bookmarkId.trim().length <= 0) {
      this.getUIContext().getPromptAction().showToast({ message: '当前页暂无书签', duration: 1200 });
      return;
    }
    try {
      await this.annotationManager.deleteAnnotation(bookmarkId);
      this.currentPageBookmarkId = '';
      this.isCurrentPageBookmarked = false;
      this.getUIContext().getPromptAction().showToast({ message: '书签已移除', duration: 1200 });
      logger.info(TAG, `EPUB Web 书签移除成功: bookmarkId=${bookmarkId}`);
    } catch (error) {
      logger.error(TAG, `移除 EPUB Web 书签失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: '移除书签失败', duration: 1500 });
    }
  }

  private toggleCurrentEpubBookmark(): void {
    if (this.isCurrentPageBookmarked) {
      void this.removeCurrentEpubBookmark();
      return;
    }
    void this.createCurrentEpubBookmark();
  }

  private addCurrentEpubBookmark(): void {
    this.toggleCurrentEpubBookmark();
  }

  private buildScopedReplaceRuleKey(): string {
    const bookId = this.ebook?.id ?? '';
    return `${NOVEL_BOOK_REPLACE_RULE_IDS_PREFIX}${bookId}`;
  }

  private parseRuleIdArray(rawValue: string): string[] {
    if (!rawValue || rawValue.length <= 0) {
      return [];
    }
    try {
      const parsed = SafeUtils.parseArr(rawValue) as Array<string>;
      if (!Array.isArray(parsed)) {
        return [];
      }
      const result: string[] = [];
      for (let i = 0; i < parsed.length; i++) {
        const item = parsed[i];
        if (typeof item === 'string' && item.length > 0) {
          result.push(item);
        }
      }
      return result;
    } catch (error) {
      logger.warn(TAG, `解析 EPUB Web 书籍净化规则作用域失败: ${String(error)}`);
      return [];
    }
  }

  private async loadScopedReplaceRuleIds(): Promise<string[] | null> {
    const ebook = this.ebook;
    if (!ebook || ebook.id.length <= 0) {
      return null;
    }
    const abilityContext = this.resolveAbilityContext();
    if (!abilityContext) {
      return null;
    }
    try {
      const store = await preferences.getPreferences(abilityContext, NOVEL_BOOK_RULE_SETTINGS_STORE);
      const raw = await store.get(this.buildScopedReplaceRuleKey(), '') as string;
      if (!raw || raw.length <= 0) {
        return null;
      }
      return this.parseRuleIdArray(raw);
    } catch (error) {
      logger.warn(TAG, `加载 EPUB Web 书籍净化规则作用域失败: ${String(error)}`);
      return null;
    }
  }

  private async ensureReplaceSettingsLoaded(): Promise<void> {
    if (this.replaceSettingsLoaded) {
      return;
    }
    const abilityContext = this.resolveAbilityContext();
    if (!abilityContext) {
      this.replaceRulesEnabled = true;
      this.scopedReplaceRuleIds = null;
      this.replaceSettingsLoaded = true;
      return;
    }
    try {
      const store = await preferences.getPreferences(abilityContext, NOVEL_SETTINGS_STORE);
      this.replaceRulesEnabled = await store.get(NOVEL_SETTING_ENABLE_REPLACE_RULES, true) as boolean;
      this.scopedReplaceRuleIds = await this.loadScopedReplaceRuleIds();
      this.replaceSettingsLoaded = true;
      logger.info(
        TAG,
        `EPUB Web 净化设置加载完成: enabled=${this.replaceRulesEnabled}, scoped=${this.scopedReplaceRuleIds ? this.scopedReplaceRuleIds.length : -1}`
      );
    } catch (error) {
      this.replaceRulesEnabled = true;
      this.scopedReplaceRuleIds = null;
      this.replaceSettingsLoaded = true;
      logger.warn(TAG, `加载 EPUB Web 净化设置失败，使用默认值: ${String(error)}`);
    }
  }

  private async persistReplaceRulesEnabled(enabled: boolean, trigger: string): Promise<void> {
    this.replaceRulesEnabled = enabled;
    const abilityContext = this.resolveAbilityContext();
    if (!abilityContext) {
      return;
    }
    try {
      const store = await preferences.getPreferences(abilityContext, NOVEL_SETTINGS_STORE);
      await store.put(NOVEL_SETTING_ENABLE_REPLACE_RULES, enabled);
      await store.flush();
      logger.info(TAG, `EPUB Web 净化规则总开关已更新: enabled=${enabled}, trigger=${trigger}`);
    } catch (error) {
      logger.warn(TAG, `保存 EPUB Web 净化规则总开关失败: trigger=${trigger}, error=${String(error)}`);
    }
  }

  private async appendScopedReplaceRuleIdIfNeeded(ruleId: string): Promise<void> {
    if (!ruleId || ruleId.length <= 0) {
      return;
    }
    if (this.scopedReplaceRuleIds === null) {
      return;
    }
    if (this.scopedReplaceRuleIds.indexOf(ruleId) >= 0) {
      return;
    }
    const nextRuleIds = this.scopedReplaceRuleIds.slice();
    nextRuleIds.push(ruleId);
    this.scopedReplaceRuleIds = nextRuleIds;
    const abilityContext = this.resolveAbilityContext();
    const ebook = this.ebook;
    if (!abilityContext || !ebook) {
      return;
    }
    try {
      const store = await preferences.getPreferences(abilityContext, NOVEL_BOOK_RULE_SETTINGS_STORE);
      await store.put(this.buildScopedReplaceRuleKey(), JSON.stringify(nextRuleIds));
      await store.flush();
      logger.info(TAG, `EPUB Web 新增净化规则已纳入当前书籍作用域: ruleId=${ruleId}, total=${nextRuleIds.length}`);
    } catch (error) {
      logger.warn(TAG, `保存 EPUB Web 书籍净化规则作用域失败: ruleId=${ruleId}, error=${String(error)}`);
    }
  }

  private shouldUseReplaceRule(rule: ReplaceRule): boolean {
    if (this.scopedReplaceRuleIds === null) {
      return true;
    }
    return this.scopedReplaceRuleIds.indexOf(rule.id) >= 0;
  }

  private buildEpubPurifyRulePayload(rule: ReplaceRule): EpubWebPurifyRulePayload {
    const payload: EpubWebPurifyRulePayload = {
      id: rule.id,
      pattern: rule.pattern,
      replacement: rule.replacement,
      isRegex: rule.isRegex
    };
    return payload;
  }

  private async collectEpubPurifyRulePayloads(): Promise<EpubWebPurifyRulePayload[]> {
    await this.ensureReplaceSettingsLoaded();
    if (!this.replaceRulesEnabled) {
      return [];
    }
    const ebook = this.ebook;
    const bookId = ebook ? ebook.id : '';
    const ruleManager = NovelReplaceRuleManager.getInstance();
    await ruleManager.initialize();
    await ruleManager.refreshRules();
    const enabledRules = ruleManager.getEnabledRules(ReplaceScope.CONTENT, bookId);
    const payloads: EpubWebPurifyRulePayload[] = [];
    for (let i = 0; i < enabledRules.length; i++) {
      const rule = enabledRules[i];
      if (!this.shouldUseReplaceRule(rule)) {
        continue;
      }
      payloads.push(this.buildEpubPurifyRulePayload(rule));
    }
    return payloads;
  }

  private async applyPurifyRulesToCurrentSpine(trigger: string): Promise<void> {
    if (!this.epubReaderController) {
      return;
    }
    try {
      const payloads = await this.collectEpubPurifyRulePayloads();
      this.epubReaderController.applyPurifyRules(payloads);
      this.currentVisibleTextSnapshot = null;
      this.currentSpineTextCache = '';
      this.currentSpineTextCacheIndex = -1;
      setTimeout(() => {
        this.refreshCurrentEpubBookmarkState(`purify_${trigger}`);
        void this.updateEpubReadAloudContextByPosition();
        void this.refreshCurrentSpineHighlightRanges(`purify_${trigger}`);
      }, 120);
      logger.info(TAG, `EPUB Web 净化规则已应用: trigger=${trigger}, rules=${payloads.length}, spine=${this.currentSpineIndex}`);
    } catch (error) {
      logger.error(TAG, `应用 EPUB Web 净化规则失败: trigger=${trigger}, error=${String(error)}`);
    }
  }

  async addPurifyRule(pattern: string): Promise<void> {
    if (!pattern || pattern.trim().length <= 0) {
      return;
    }
    const normalizedPattern = pattern.trim();
    try {
      await this.ensureReplaceSettingsLoaded();
      const ruleManager = NovelReplaceRuleManager.getInstance();
      await ruleManager.initialize();
      if (!this.replaceRulesEnabled) {
        await this.persistReplaceRulesEnabled(true, 'epub_selection_add_rule');
      }
      const ruleParams: AddRuleParams = {
        name: `净化：${normalizedPattern.substring(0, 20)}${normalizedPattern.length > 20 ? '...' : ''}`,
        pattern: normalizedPattern,
        replacement: '',
        isRegex: false,
        scope: ReplaceScope.CONTENT,
        enabled: true,
        order: 100
      };
      const createdRule = await ruleManager.addRule(ruleParams);
      await this.appendScopedReplaceRuleIdIfNeeded(createdRule.id);
      await ruleManager.refreshRules();
      await this.applyPurifyRulesToCurrentSpine('add_from_selection');
      logger.info(TAG, `EPUB Web 已添加净化规则: ruleId=${createdRule.id}, pattern=${normalizedPattern.substring(0, 50)}`);
    } catch (error) {
      logger.error(TAG, `添加 EPUB Web 净化规则失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: '添加净化规则失败', duration: 1500 });
    }
  }

  private getSafeReadAloudSettings(settings?: ReadAloudSettings): ReadAloudSettings {
    const globalDefaults = this.loadGlobalReadAloudSettings();
    if (!settings) {
      return normalizeReadAloudSettings(globalDefaults);
    }
    return this.mergeReadAloudSettings(globalDefaults, settings);
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
      logger.warn(TAG, `保存 EPUB Web 全局听书设置失败: ${String(error)}`);
    }
  }

  private isReadAloudSentenceBoundary(char: string): boolean {
    return char === '\n' ||
      char === '\r' ||
      char === '\u3002' ||
      char === '\uff01' ||
      char === '\uff1f' ||
      char === '\u2026' ||
      char === '\u2014' ||
      char === '\u2025' ||
      char === '\u3001' ||
      char === '\u300d' ||
      char === '\u300f' ||
      char === '\u3011' ||
      char === '.' ||
      char === '!' ||
      char === '?' ||
      char === ';' ||
      char === '\uff1b';
  }

  private isReadAloudSentenceTailChar(char: string): boolean {
    return char === '"' ||
      char === '\'' ||
      char === ')' ||
      char === '\uff09' ||
      char === '\u300d' ||
      char === '\u300f' ||
      char === '\u3011' ||
      char === '\u300b' ||
      char === '\u201d' ||
      char === '\u2019';
  }

  private resolveReadAloudSentenceStartCharIndex(text: string, charIndex: number): number {
    if (!text || text.length <= 0) {
      return 0;
    }
    let sentenceStart = Math.max(0, Math.min(Math.floor(charIndex), text.length - 1));
    while (sentenceStart > 0) {
      const prevChar = text.charAt(sentenceStart - 1);
      if (this.isReadAloudSentenceBoundary(prevChar)) {
        break;
      }
      sentenceStart -= 1;
    }
    return sentenceStart;
  }

  private resolveReadAloudSentenceEndCharIndex(text: string, charIndex: number): number {
    if (!text || text.length <= 0) {
      return 0;
    }
    let sentenceEnd = Math.max(0, Math.min(Math.floor(charIndex), text.length - 1));
    while (sentenceEnd < text.length) {
      const currentChar = text.charAt(sentenceEnd);
      sentenceEnd += 1;
      if (this.isReadAloudSentenceBoundary(currentChar)) {
        while (sentenceEnd < text.length) {
          const tailChar = text.charAt(sentenceEnd);
          if (!this.isReadAloudSentenceTailChar(tailChar)) {
            break;
          }
          sentenceEnd += 1;
        }
        break;
      }
    }
    return Math.max(1, Math.min(text.length, sentenceEnd));
  }

  private getCurrentEpubReadAloudResumeCharIndex(snapshot: EpubWebTextSnapshot): number {
    if (
      this.readAloudCurrentCharIndex >= 0 &&
      this.currentSpineTextCacheIndex === this.currentSpineIndex &&
      this.readAloudCurrentCharIndex < snapshot.text.length
    ) {
      return this.readAloudCurrentCharIndex;
    }
    return Math.max(0, Math.min(snapshot.startOffset, Math.max(0, snapshot.text.length - 1)));
  }

  private async updateEpubReadAloudContextByPosition(resumeCharIndex?: number): Promise<boolean> {
    const ebook = this.ebook;
    if (!ebook) {
      return false;
    }
    const snapshot = await this.queryCurrentEpubTextSnapshot();
    if (!snapshot || snapshot.text.trim().length <= 0) {
      return false;
    }
    const readAloudSettings = this.getSafeReadAloudSettings(this.readAloudPanelSettings);
    this.readAloudPanelSettings = readAloudSettings;
    this.readAloudController.updateSettings(readAloudSettings);
    const maxCharIndex = Math.max(0, snapshot.text.length - 1);
    const fallbackResume = this.getCurrentEpubReadAloudResumeCharIndex(snapshot);
    const safeResumeCharIndex = Math.max(
      0,
      Math.min(Math.floor(resumeCharIndex ?? fallbackResume), maxCharIndex)
    );
    const chapter = this.getCurrentSpineChapter();
    const readAloudCoverUrl = this.resolveEpubReadAloudCoverUrl(ebook);
    this.readAloudController.updateContext({
      bookId: ebook.id,
      bookTitle: ebook.metadata.title || '电子书',
      chapterIndex: this.currentSpineIndex,
      chapterTitle: chapter ? (chapter.title || '') : '',
      coverUrl: readAloudCoverUrl,
      content: snapshot.text,
      pageIndex: this.currentPageWithinSpine,
      resumeCharIndex: safeResumeCharIndex,
      readerOpenFlowId: this.readerOpenFlowId,
      sourceId: 'ebook',
      totalChapters: this.spineItems.length
    });
    return true;
  }

  private syncReadAloudStateFromController(): void {
    const ebook = this.ebook;
    if (!ebook) {
      this.readAloudPlaying = false;
      return;
    }
    const context = this.readAloudController.getContextSnapshot();
    if (!context || context.bookId !== ebook.id) {
      this.readAloudPlaying = false;
      return;
    }
    const snapshot = this.readAloudController.getSnapshot();
    this.readAloudPlaying = snapshot.playbackState === ReadAloudPlaybackState.PLAYING;
    const textLength = Math.max(0, context.content.length);
    if (textLength <= 0) {
      return;
    }
    const rawCharIndex = snapshot.currentCharIndex >= 0 ? snapshot.currentCharIndex : (context.resumeCharIndex ?? -1);
    if (rawCharIndex < 0) {
      return;
    }
    this.readAloudCurrentCharIndex = Math.max(0, Math.min(Math.floor(rawCharIndex), Math.max(0, textLength - 1)));
  }

  private applyReadAloudProgress(payload: ReadAloudStatePayload): void {
    const ebook = this.ebook;
    if (!ebook) {
      return;
    }
    const context = this.readAloudController.getContextSnapshot();
    if (!context || context.bookId !== ebook.id) {
      return;
    }
    const content = context.content;
    if (!content || content.length <= 0) {
      return;
    }
    const payloadCharIndex = payload.currentCharIndex >= 0 ? payload.currentCharIndex : payload.chunkStartCharIndex;
    if (payloadCharIndex < 0) {
      return;
    }
    const maxCharIndex = Math.max(0, content.length - 1);
    const safeCharIndex = Math.max(0, Math.min(Math.floor(payloadCharIndex), maxCharIndex));
    this.readAloudCurrentCharIndex = safeCharIndex;
    this.currentSpineTextCache = content;
    this.currentSpineTextCacheIndex = context.chapterIndex;

    if (context.chapterIndex === this.currentSpineIndex) {
      const highlightStart = this.resolveReadAloudSentenceStartCharIndex(content, safeCharIndex);
      const highlightEnd = this.resolveReadAloudSentenceEndCharIndex(content, safeCharIndex);
      const progressOffset = Math.max(highlightStart, Math.min(safeCharIndex, highlightEnd));
      this.epubReaderController?.applyReadAloudHighlight(highlightStart, highlightEnd, true, progressOffset);
    }

    if (payload.reason === 'progress_updated') {
      const now = Date.now();
      if ((now - this.lastReadAloudProgressSaveTime) >= this.readAloudProgressSaveInterval) {
        this.lastReadAloudProgressSaveTime = now;
        void this.saveReadingProgress('read_aloud_progress');
      }
    }
  }

  private startReadAloudUiSyncTimer(): void {
    if (this.readAloudUiSyncTimer >= 0) {
      return;
    }
    this.readAloudUiSyncTimer = setInterval(() => {
      if (!this.isPageVisible || !this.ebook) {
        return;
      }
      this.syncReadAloudStateFromController();
    }, 240);
  }

  private stopReadAloudUiSyncTimer(): void {
    if (this.readAloudUiSyncTimer < 0) {
      return;
    }
    clearInterval(this.readAloudUiSyncTimer);
    this.readAloudUiSyncTimer = -1;
  }

  private shouldHandleReadAloudUiEvents(): boolean {
    if (!this.isPageVisible) {
      return false;
    }
    const currentHostPage = (AppStorage.get<string>('ReadAloudCurrentHostPage') ?? '').trim();
    return currentHostPage === 'EpubWebViewReaderPage';
  }

  private handleEpubManualReadAloudNavigation(reason: string): void {
    const readAloudSettings = this.getSafeReadAloudSettings(this.readAloudPanelSettings);
    if (!readAloudSettings.pauseOnManualPageTurn) {
      return;
    }
    const snapshot = this.readAloudController.getSnapshot();
    if (snapshot.playbackState !== ReadAloudPlaybackState.PLAYING) {
      return;
    }
    this.readAloudController.pause(reason);
    this.readAloudPlaying = false;
    this.epubReaderController?.clearReadAloudHighlight();
    void this.updateEpubReadAloudContextByPosition();
    void this.saveReadingProgress(reason);
    logger.info(TAG, `EPUB Web 手动导航触发听书暂停: reason=${reason}`);
  }

  private scheduleRouteReadAloudAutoStart(reason: string, delayMs: number): void {
    if (!this.shouldHandleRouteReadAloudAutoEntry()) {
      return;
    }
    setTimeout(() => {
      void this.tryRouteReadAloudAutoStart(reason);
    }, delayMs);
  }

  private shouldHandleRouteReadAloudAutoEntry(): boolean {
    return this.shouldAutoStartReadAloudFromRoute || this.shouldAutoOpenReadAloudPlayerFromRoute;
  }

  private clearRouteReadAloudAutoEntry(): void {
    this.shouldAutoStartReadAloudFromRoute = false;
    this.shouldAutoOpenReadAloudPlayerFromRoute = false;
  }

  private async tryRouteReadAloudAutoStart(reason: string): Promise<void> {
    if (!this.shouldHandleRouteReadAloudAutoEntry() || !this.ebook) {
      return;
    }
    this.routeReadAloudAutoStartAttempts += 1;
    let readAloudSettings = this.getSafeReadAloudSettings(this.readAloudPanelSettings);
    if (!readAloudSettings.enabled) {
      readAloudSettings.enabled = true;
      this.readAloudPanelSettings = readAloudSettings;
      await this.persistGlobalReadAloudSettings(readAloudSettings);
    }
    this.readAloudController.updateSettings(readAloudSettings);
    const hasContext = await this.updateEpubReadAloudContextByPosition();
    if (!hasContext) {
      if (this.routeReadAloudAutoStartAttempts < 4) {
        this.scheduleRouteReadAloudAutoStart(`${reason}_retry_${this.routeReadAloudAutoStartAttempts}`, 420);
      } else {
        this.clearRouteReadAloudAutoEntry();
        this.getUIContext().getPromptAction().showToast({ message: '当前页不是可朗读文本', duration: 1500 });
      }
      return;
    }
    const shouldOpenPlayer = this.shouldAutoOpenReadAloudPlayerFromRoute;
    const snapshot = this.readAloudController.getSnapshot();
    if (snapshot.playbackState !== ReadAloudPlaybackState.PLAYING) {
      this.readAloudController.start(`route_auto_start_${reason}`);
    }
    this.readAloudController.refreshMediaSession();
    this.syncReadAloudStateFromController();
    this.clearRouteReadAloudAutoEntry();
    if (shouldOpenPlayer) {
      setTimeout(() => {
        this.openReadAloudPlayerPageFromEpubReader();
      }, 60);
    }
    logger.info(TAG, `EPUB 路由参数已自动启动听书: reason=${reason}, attempts=${this.routeReadAloudAutoStartAttempts}`);
  }

  private openReadAloudPlayerPageFromEpubReader(): void {
    const ebook = this.ebook;
    if (!ebook) {
      return;
    }
    const context = this.readAloudController.getContextSnapshot();
    if (!context || context.bookId !== ebook.id) {
      logger.warn(TAG, 'EPUB 听书独立页打开失败：朗读上下文未就绪');
      return;
    }
    AppStorage.setOrCreate('ReadAloudPlayerOpeningAt', Date.now());
    openReadAloudPlayerInIsolatedAbility(
      this.getUIContext(),
      AppStorage.get<NavPathStack>('GlobalNavStack'),
      TAG,
      'EpubWebViewReaderPage',
      WindowManager.getCurrentMode(),
      null
    );
  }

  private toggleReadAloudFromToolbar(): void {
    void this.toggleReadAloudFromToolbarAsync();
  }

  private async toggleReadAloudFromToolbarAsync(): Promise<void> {
    const ebook = this.ebook;
    if (!ebook) {
      return;
    }
    let readAloudSettings = this.getSafeReadAloudSettings(this.readAloudPanelSettings);
    if (!readAloudSettings.enabled) {
      readAloudSettings.enabled = true;
      this.readAloudPanelSettings = readAloudSettings;
      await this.persistGlobalReadAloudSettings(readAloudSettings);
    }
    this.readAloudController.updateSettings(readAloudSettings);
    const hasContext = await this.updateEpubReadAloudContextByPosition();
    if (!hasContext) {
      this.getUIContext().getPromptAction().showToast({ message: '当前页不是可朗读文本', duration: 1500 });
      return;
    }
    if (this.readAloudController.getSnapshot().playbackState === ReadAloudPlaybackState.PLAYING) {
      this.readAloudController.pause('epub_toolbar_toggle');
    } else {
      this.readAloudController.start('epub_toolbar_toggle');
    }
    this.readAloudController.refreshMediaSession();
    this.syncReadAloudStateFromController();
  }

  private onStartReadAloudFromCharIndex(charIndex: number): void {
    void this.startReadAloudFromCharIndexAsync(charIndex);
  }

  private async startReadAloudFromCharIndexAsync(charIndex: number): Promise<void> {
    const snapshot = await this.queryCurrentEpubTextSnapshot();
    if (!snapshot || snapshot.text.trim().length <= 0) {
      this.getUIContext().getPromptAction().showToast({ message: '当前页不是可朗读文本', duration: 1500 });
      return;
    }
    const safeStart = this.resolveReadAloudSentenceStartCharIndex(snapshot.text, charIndex);
    this.readAloudCurrentCharIndex = safeStart;
    const hasContext = await this.updateEpubReadAloudContextByPosition(safeStart);
    if (!hasContext) {
      this.getUIContext().getPromptAction().showToast({ message: '听书内容未就绪', duration: 1500 });
      return;
    }
    const currentSettings = this.getSafeReadAloudSettings(this.readAloudPanelSettings);
    if (!currentSettings.enabled) {
      currentSettings.enabled = true;
      this.readAloudPanelSettings = currentSettings;
      await this.persistGlobalReadAloudSettings(currentSettings);
      this.readAloudController.updateSettings(currentSettings);
    }
    const controllerSnapshot = this.readAloudController.getSnapshot();
    if (controllerSnapshot.playbackState === ReadAloudPlaybackState.PLAYING) {
      const baseCharIndex = controllerSnapshot.currentCharIndex >= 0 ? controllerSnapshot.currentCharIndex : safeStart;
      this.readAloudController.seekByChars(safeStart - baseCharIndex, 'epub_selection_start');
    } else {
      this.readAloudController.start('epub_selection_start');
      this.syncReadAloudStateFromController();
    }
    this.readAloudController.refreshMediaSession();
  }

  private openReadAloudSettingsPanelFromToolbar(): void {
    const now = Date.now();
    if ((now - this.lastReadAloudPanelCloseTime) < EpubWebViewReaderPage.READ_ALOUD_PANEL_REOPEN_GUARD_MS) {
      return;
    }
    this.showReadAloudPanel = true;
    this.readAloudPanelSettings = this.getSafeReadAloudSettings(this.readAloudPanelSettings);
    this.hideToolbars();
    this.handleMenusVisibilityChange();
    this.refreshReadAloudAvailability();
  }

  private updateReadAloudSettings(partial: Partial<ReadAloudSettings>): void {
    logger.debug(TAG, `EPUB Web 应用听书设置变更: ${JSON.stringify(partial)}`);
    const current = this.getSafeReadAloudSettings(this.readAloudPanelSettings);
    const nextReadAloud = this.mergeReadAloudSettings(current, partial);
    this.readAloudPanelSettings = nextReadAloud;
    void this.persistGlobalReadAloudSettings(nextReadAloud);
    this.readAloudController.updateSettings(nextReadAloud);
    void this.updateEpubReadAloudContextByPosition();

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

  private refreshReadAloudAvailability(): void {
    ReadAloudAvailability.refresh(false, this.getSafeReadAloudSettings(this.readAloudPanelSettings)).then((map: ReadAloudEngineAvailabilityMap) => {
      this.readAloudAvailability = map;
      if (!map.SYSTEM) {
        const probeError = ReadAloudAvailability.getLastSystemProbeErrorMessage();
        if (probeError.length > 0) {
          this.readAloudStatusMessage = `System TTS probe failed: ${probeError}`;
        }
      }
      if (!map.REMOTE && this.getSafeReadAloudSettings(this.readAloudPanelSettings).engineType === ReadAloudEngineType.REMOTE) {
        const probeError = ReadAloudAvailability.getLastRemoteProbeErrorMessage();
        if (probeError.length > 0) {
          this.readAloudStatusMessage = `Remote TTS unavailable: ${probeError}`;
        }
      }
      this.refreshReadAloudVoices();
    }).catch((error: Object | string) => {
      const errorText = this.formatReadAloudError(error);
      logger.warn(TAG, `刷新 EPUB Web 听书引擎可用性失败: ${errorText}`);
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
    const engineType = this.getSafeReadAloudSettings(this.readAloudPanelSettings).engineType;
    if (!this.isReadAloudEngineAvailable(engineType)) {
      this.readAloudVoiceOptions = [];
      if (engineType === ReadAloudEngineType.SYSTEM) {
        const probeError = ReadAloudAvailability.getLastSystemProbeErrorMessage();
        this.readAloudStatusMessage = probeError.length > 0 ? `System TTS probe failed: ${probeError}` : 'System TTS is unavailable, please check device settings';
      } else if (engineType === ReadAloudEngineType.REMOTE) {
        const probeError = ReadAloudAvailability.getLastRemoteProbeErrorMessage();
        this.readAloudStatusMessage = probeError.length > 0 ? `Remote TTS unavailable: ${probeError}` : 'Remote TTS unavailable, please check endpoint/model/voice/apiKey settings';
      } else {
        this.readAloudStatusMessage = 'Current read-aloud engine is unavailable';
      }
      return;
    }
    this.readAloudController.listVoices(engineType).then((voices: ReadAloudVoiceOption[]) => {
      this.readAloudVoiceOptions = voices;
      this.readAloudStatusMessage = voices.length > 0 ? '' : 'System TTS engine initialization failed';
    }).catch((error: Object | string) => {
      const errorText = this.formatReadAloudError(error);
      logger.warn(TAG, `刷新 EPUB Web 听书音色列表失败: ${errorText}`);
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
    return String(error);
  }

  private isSpineImageLike(spineIndex: number): boolean {
    if (spineIndex < 0 || spineIndex >= this.spineItems.length) {
      return false;
    }
    const chapter = this.spineItems[spineIndex];
    const layoutType = (chapter.resourceLayoutType ?? '').trim().toUpperCase();
    if (layoutType === 'IMAGE_PAGE') {
      return true;
    }
    const mediaType = (chapter.resourceMediaType ?? '').trim().toLowerCase();
    if (mediaType.startsWith('image/')) {
      return true;
    }
    const resourceFile = (chapter.resourceFile ?? '').trim().replace(/[#?].*$/, '');
    const resourceHref = (chapter.resourceHref ?? '').trim().replace(/[#?].*$/, '');
    return IMAGE_RESOURCE_PATH_PATTERN.test(resourceFile) || IMAGE_RESOURCE_PATH_PATTERN.test(resourceHref);
  }

  private isCurrentSpineImageLike(): boolean {
    return this.isSpineImageLike(this.currentSpineIndex);
  }

  private getEffectiveTextHorizontalMargin(): number {
    return Math.max(0, Math.round(this.readingSettings.pageMargin ?? DEFAULT_EBOOK_READING_SETTINGS.pageMargin));
  }

  private getEffectiveTextTopMargin(): number {
    return Math.max(
      0,
      Math.round(
        this.readingSettings.pageTopMargin ??
          this.readingSettings.pageMargin ??
          DEFAULT_EBOOK_READING_SETTINGS.pageTopMargin ??
          DEFAULT_EBOOK_READING_SETTINGS.pageMargin
      )
    );
  }

  private getEffectiveTextBottomMargin(): number {
    return Math.max(
      0,
      Math.round(
        this.readingSettings.pageBottomMargin ??
          this.readingSettings.pageMargin ??
          DEFAULT_EBOOK_READING_SETTINGS.pageBottomMargin ??
          DEFAULT_EBOOK_READING_SETTINGS.pageMargin
      )
    );
  }

  private async refreshCameraCutoutTopInset(source: string): Promise<void> {
    try {
      const windowCutoutTopInset = this.getWindowCutoutTopInset();
      let displayCutoutTopInset = 0;
      try {
        const displayInfo = display.getDefaultDisplaySync();
        const cutoutInfo = await displayInfo.getCutoutInfo();
        let topInsetPx = 0;
        for (let i = 0; i < cutoutInfo.boundingRects.length; i++) {
          const rect = cutoutInfo.boundingRects[i];
          if (rect.top <= 1 && rect.height > 0) {
            topInsetPx = Math.max(topInsetPx, rect.top + rect.height);
          }
        }
        const uiContext = this.uiContext ?? this.getUIContext();
        displayCutoutTopInset = topInsetPx > 0 ? Math.ceil(uiContext.px2vp(topInsetPx)) : 0;
      } catch (displayError) {
        logger.debug(TAG, `读取 display cutout 信息失败: ${String(displayError)}`);
      }
      const topInsetVp = Math.max(windowCutoutTopInset, displayCutoutTopInset);
      if (Math.abs(this.cameraCutoutTopInset - topInsetVp) <= 1) {
        return;
      }
      this.cameraCutoutTopInset = topInsetVp;
      logger.info(
        TAG,
        `更新 EPUB 摄像头避让: source=${source}, cutoutTop=${topInsetVp}vp, window=${windowCutoutTopInset}vp, display=${displayCutoutTopInset}vp`
      );
      setTimeout(() => {
        this.epubReaderController?.applyReadingSettings(this.readingSettings);
      }, 0);
    } catch (error) {
      logger.debug(TAG, `读取摄像头避让区域失败: ${String(error)}`);
    }
  }

  private getWindowCutoutTopInset(): number {
    try {
      const hostContext = this.context ?? ((this.getUIContext().getHostContext() as common.UIAbilityContext) as common.UIAbilityContext);
      if (!hostContext || !hostContext.windowStage) {
        return 0;
      }
      const mainWindow = hostContext.windowStage.getMainWindowSync();
      const cutoutArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_CUTOUT);
      const displayInfo = display.getDefaultDisplaySync();
      const density = displayInfo.densityDPI / 160;
      if (density <= 0) {
        return 0;
      }
      return Math.max(0, Math.ceil(cutoutArea.topRect.height / density));
    } catch (error) {
      logger.debug(TAG, `读取窗口 cutout 避让失败: ${String(error)}`);
      return 0;
    }
  }

  private getReaderContentTopInset(): number {
    const measuredInset = Math.max(0, Math.ceil(this.statusBarHeight));
    const cutoutInset = Math.max(0, Math.ceil(this.cameraCutoutTopInset));
    const maxReasonableInset = Math.max(
      EPUB_READER_CAMERA_SAFE_TOP_FALLBACK,
      measuredInset > 0 ? measuredInset + 8 : 32
    );
    if (this.isLandscapeMode) {
      return Math.min(Math.max(measuredInset, cutoutInset), maxReasonableInset);
    }
    return Math.min(
      Math.max(measuredInset, cutoutInset, EPUB_READER_CAMERA_SAFE_TOP_FALLBACK),
      maxReasonableInset
    );
  }

  private getLastVisibleStatusBarInset(): number {
    const storedInset = AppStorage.get<number>(WINDOW_MANAGER_LAST_VISIBLE_STATUS_BAR_HEIGHT_KEY) ?? 0;
    return Math.max(0, Math.ceil(storedInset));
  }

  private getToolbarCutoutTopInset(): number {
    const cutoutInset = Math.max(0, Math.ceil(this.cameraCutoutTopInset));
    if (cutoutInset <= 0) {
      return 0;
    }
    const measuredInset = Math.max(0, Math.ceil(this.statusBarHeight));
    const lastVisibleInset = this.getLastVisibleStatusBarInset();
    const referenceInset = Math.max(measuredInset, lastVisibleInset);
    const maxReasonableInset = referenceInset > 0 ? referenceInset + 12 : 64;
    return Math.min(cutoutInset, maxReasonableInset);
  }

  private getReaderToolbarTopInset(): number {
    const effectiveStatusInset = Math.max(
      Math.max(0, Math.ceil(this.statusBarHeight)),
      this.getLastVisibleStatusBarInset(),
      this.getToolbarCutoutTopInset()
    );
    return ReaderSafeAreaUtils.getStatusBarInset(effectiveStatusInset);
  }

  private getReaderTopToolbarHeight(): number {
    return this.getReaderToolbarTopInset() + ReaderSafeAreaUtils.TOP_TOOLBAR_ROW_HEIGHT;
  }

  private shouldShowBottomInfoBar(): boolean {
    return !this.isCurrentSpineImageLike() && (
      this.readingSettings.showPageNumber !== false ||
      (this.readingSettings.showProgress ?? false) ||
      this.readingSettings.showTime !== false ||
      (this.readingSettings.showBattery ?? false)
    );
  }

  private shouldHideBottomInfoBar(): boolean {
    return this.showBottomToolbar ||
      this.showTopToolbar ||
      this.showSettingsPanel ||
      this.showQuickSettings ||
      this.showChapterList ||
      this.showPageTurnAnimationSettings ||
      this.showAutoPageTurnSettings ||
      this.showInteractionOverlay;
  }

  private getBottomInfoBarHeight(): number {
    return this.shouldShowBottomInfoBar() ? 28 : 0;
  }

  private getBottomInfoBarTextColor(): string {
    return this.readingSettings.textColor ?? '#333333';
  }

  private getBottomInfoBarSidePadding(): number {
    return this.getEffectiveTextHorizontalMargin();
  }

  private getBottomInfoBarBottomPadding(): number {
    return Math.max(
      8,
      Math.floor(this.getEffectiveTextBottomMargin() * 0.5) + this.navigationBarHeight
    );
  }

  private getCurrentSpineReadRatio(): number {
    if (this.totalPagesInSpine <= 0) {
      return 0;
    }
    const safePage = Math.max(0, Math.min(this.currentPageWithinSpine, this.totalPagesInSpine - 1));
    return Math.max(0, Math.min(1, (safePage + 1) / this.totalPagesInSpine));
  }

  private getReadingProgressValue(): number {
    const totalSpines = this.spineItems.length;
    if (totalSpines <= 0) {
      return 0;
    }
    const safeSpine = Math.max(0, Math.min(this.currentSpineIndex, totalSpines - 1));
    return Math.max(0, Math.min(100, ((safeSpine + this.getCurrentSpineReadRatio()) / totalSpines) * 100));
  }

  private getReadingProgressPercent(): number {
    return Math.round(this.getReadingProgressValue());
  }

  private updateCurrentTime(): void {
    const now = new Date();
    const hours = now.getHours().toString().padStart(2, '0');
    const minutes = now.getMinutes().toString().padStart(2, '0');
    this.currentTime = `${hours}:${minutes}`;
  }

  private startTimeUpdate(): void {
    this.updateCurrentTime();
    this.updateBatteryLevel();
    if (this.timeUpdateTimer !== -1) {
      clearInterval(this.timeUpdateTimer);
    }
    this.timeUpdateTimer = setInterval(() => {
      this.updateCurrentTime();
      this.updateBatteryLevel();
    }, 60000);
  }

  private stopTimeUpdate(): void {
    if (this.timeUpdateTimer !== -1) {
      clearInterval(this.timeUpdateTimer);
      this.timeUpdateTimer = -1;
    }
  }

  private updateBatteryLevel(): void {
    try {
      this.batteryLevel = batteryInfo.batterySOC;
    } catch (_error) {
      this.batteryLevel = 0;
    }
  }

  private getBatteryColor(level: number): string {
    if (level <= 20) {
      return '#FF6B6B';
    }
    if (level <= 50) {
      return '#F5A623';
    }
    return '#4CAF50';
  }

  private getBatteryColorEnd(level: number): string {
    if (level <= 20) {
      return '#FF8A80';
    }
    if (level <= 50) {
      return '#FFCA6A';
    }
    return '#81C784';
  }

  // ──── 翻页 ────

  private resolveSystemThemeTextSettings(settings: EBookReadingSettings): EBookReadingSettings {
    const resolved = this.cloneTextReadingSettings(settings);
    if (resolved.followSystemTheme === true) {
      if (this.themeManager.isDarkThemeSync()) {
        resolved.backgroundColor = '#1E1E1E';
        resolved.textColor = '#D4D4D4';
        resolved.nightMode = true;
      } else {
        resolved.backgroundColor = DEFAULT_EBOOK_READING_SETTINGS.backgroundColor;
        resolved.textColor = DEFAULT_EBOOK_READING_SETTINGS.textColor;
        resolved.nightMode = false;
      }
    }
    return resolved;
  }

  private cloneTextReadingSettings(settings: EBookReadingSettings): EBookReadingSettings {
    return {
      fontSize: settings.fontSize,
      fontFamily: settings.fontFamily,
      fontPath: settings.fontPath,
      fontWeight: settings.fontWeight,
      lineHeight: settings.lineHeight,
      backgroundColor: settings.backgroundColor,
      textColor: settings.textColor,
      themeBgImage: settings.themeBgImage,
      nightMode: settings.nightMode,
      followSystemTheme: settings.followSystemTheme,
      pageMargin: settings.pageMargin,
      pageTopMargin: settings.pageTopMargin ?? settings.pageMargin ?? DEFAULT_EBOOK_READING_SETTINGS.pageTopMargin,
      pageBottomMargin: settings.pageBottomMargin ?? settings.pageMargin ?? DEFAULT_EBOOK_READING_SETTINGS.pageBottomMargin,
      pageMode: settings.pageMode,
      brightness: settings.brightness,
      autoSave: settings.autoSave,
      saveInterval: settings.saveInterval,
      letterSpacing: settings.letterSpacing ?? 0,
      paragraphSpacing: settings.paragraphSpacing ?? 8,
      firstLineIndent: settings.firstLineIndent ?? 2,
      textAlignment: settings.textAlignment ?? 'JUSTIFY',
      pageTurnAnimation: settings.pageTurnAnimation ?? PageTurnAnimationType.SLIDE,
      tapToTurn: settings.tapToTurn ?? true,
      volumeKeyNavigation: settings.volumeKeyNavigation ?? true,
      keepScreenOn: settings.keepScreenOn ?? false,
      lockDeviceOrientation: settings.lockDeviceOrientation ?? false,
      showPageNumber: settings.showPageNumber ?? true,
      showProgress: settings.showProgress ?? false,
      showTime: settings.showTime ?? true,
      showBattery: settings.showBattery ?? false,
      backgroundType: settings.backgroundType ?? 'COLOR',
      backgroundImagePath: settings.backgroundImagePath ?? '',
      backgroundImageOpacity: settings.backgroundImageOpacity ?? 0.3
    };
  }

  private mergeTextReadingSettings(settings: EBookReadingSettings): EBookReadingSettings {
    return {
      fontSize: settings.fontSize,
      fontFamily: settings.fontFamily,
      fontPath: settings.fontPath,
      fontWeight: settings.fontWeight,
      lineHeight: settings.lineHeight,
      backgroundColor: settings.backgroundColor,
      textColor: settings.textColor,
      themeBgImage: settings.themeBgImage,
      nightMode: settings.nightMode,
      followSystemTheme: settings.followSystemTheme,
      pageMargin: settings.pageMargin,
      pageTopMargin: settings.pageTopMargin ?? this.readingSettings.pageTopMargin ?? settings.pageMargin ?? DEFAULT_EBOOK_READING_SETTINGS.pageTopMargin,
      pageBottomMargin: settings.pageBottomMargin ?? this.readingSettings.pageBottomMargin ?? settings.pageMargin ?? DEFAULT_EBOOK_READING_SETTINGS.pageBottomMargin,
      pageMode: settings.pageMode,
      brightness: settings.brightness,
      autoSave: settings.autoSave,
      saveInterval: settings.saveInterval,
      letterSpacing: settings.letterSpacing ?? this.readingSettings.letterSpacing ?? 0,
      paragraphSpacing: settings.paragraphSpacing ?? this.readingSettings.paragraphSpacing ?? 8,
      firstLineIndent: settings.firstLineIndent ?? this.readingSettings.firstLineIndent ?? 2,
      textAlignment: settings.textAlignment ?? this.readingSettings.textAlignment ?? 'JUSTIFY',
      pageTurnAnimation: settings.pageTurnAnimation ?? this.readingSettings.pageTurnAnimation ?? PageTurnAnimationType.SLIDE,
      tapToTurn: settings.tapToTurn ?? this.readingSettings.tapToTurn ?? true,
      volumeKeyNavigation: settings.volumeKeyNavigation ?? this.readingSettings.volumeKeyNavigation ?? true,
      keepScreenOn: settings.keepScreenOn ?? this.readingSettings.keepScreenOn ?? false,
      lockDeviceOrientation: settings.lockDeviceOrientation ?? this.readingSettings.lockDeviceOrientation ?? false,
      showPageNumber: settings.showPageNumber ?? this.readingSettings.showPageNumber ?? true,
      showProgress: settings.showProgress ?? this.readingSettings.showProgress ?? false,
      showTime: settings.showTime ?? this.readingSettings.showTime ?? true,
      showBattery: settings.showBattery ?? this.readingSettings.showBattery ?? false,
      backgroundType: settings.backgroundType ?? this.readingSettings.backgroundType ?? 'COLOR',
      backgroundImagePath: settings.backgroundImagePath ?? this.readingSettings.backgroundImagePath ?? '',
      backgroundImageOpacity: settings.backgroundImageOpacity ?? this.readingSettings.backgroundImageOpacity ?? 0.3
    };
  }

  private arePageReadingSettingsEqual(left: MangaReadingSettings, right: MangaReadingSettings): boolean {
    return JSON.stringify(left) === JSON.stringify(right);
  }

  private clonePageReadingSettings(settings: MangaReadingSettings): MangaReadingSettings {
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

  private normalizePageReadingSettings(
    settings: MangaReadingSettings,
    shouldNotify: boolean = false
  ): MangaReadingSettings {
    const normalized = this.clonePageReadingSettings(settings);
    let toastMessage: string = '';
    if (normalized.readingDirection === ReadingDirection.VERTICAL) {
      normalized.readingDirection = ReadingDirection.TOP_TO_BOTTOM;
    }
    if (normalized.readingMode === ReadingMode.SINGLE_PAGE_LTR) {
      normalized.readingMode = ReadingMode.SINGLE_PAGE;
      normalized.readingDirection = ReadingDirection.LEFT_TO_RIGHT;
    }
    if (normalized.readingMode === ReadingMode.SINGLE_PAGE_RTL) {
      normalized.readingMode = ReadingMode.SINGLE_PAGE;
      normalized.readingDirection = ReadingDirection.RIGHT_TO_LEFT;
    }
    if (normalized.readingMode === ReadingMode.CONTINUOUS_SCROLL) {
      normalized.readingMode = ReadingMode.SINGLE_PAGE;
      normalized.readingDirection = normalized.readingDirection === ReadingDirection.RIGHT_TO_LEFT
        ? ReadingDirection.RIGHT_TO_LEFT
        : ReadingDirection.LEFT_TO_RIGHT;
      toastMessage = 'EPUB WebView 已移除连续滚动，已切换为单页模式';
      logger.info(TAG, 'EPUB WebView 连续滚动设置已归一化为单页模式');
    }
    if (normalized.readingMode === ReadingMode.WEBTOON ||
      normalized.readingMode === ReadingMode.WEBTOON_WITH_GAP ||
      normalized.readingMode === ReadingMode.CONTINUOUS_VERTICAL) {
      normalized.readingDirection = ReadingDirection.TOP_TO_BOTTOM;
    }
    if (normalized.readingMode === ReadingMode.SINGLE_PAGE &&
      normalized.readingDirection === ReadingDirection.TOP_TO_BOTTOM) {
      normalized.readingMode = ReadingMode.SINGLE_PAGE_TTB;
    }
    if (normalized.readingMode === ReadingMode.SINGLE_PAGE_TTB) {
      normalized.readingDirection = ReadingDirection.TOP_TO_BOTTOM;
    }
    if (normalized.readingMode === ReadingMode.DOUBLE_PAGE &&
      normalized.readingDirection === ReadingDirection.TOP_TO_BOTTOM) {
      normalized.readingDirection = ReadingDirection.LEFT_TO_RIGHT;
    }
    if (normalized.readingMode === ReadingMode.DOUBLE_PAGE &&
      this.getDeviceOrientation() !== 'landscape' &&
      normalized.doublePagePortraitLayout === DoublePagePortraitLayout.VERTICAL) {
      normalized.doublePagePortraitLayout = DoublePagePortraitLayout.HORIZONTAL;
      toastMessage = 'WebView EPUB 暂不支持双页竖屏上下组合，已切换为左右组合';
    }
    if (shouldNotify && toastMessage.length > 0) {
      this.getUIContext().getPromptAction().showToast({ message: toastMessage, duration: 1400 });
    }
    return normalized;
  }

  private pageSettingsSaveTimeoutId: number = -1;
  private textSettingsSaveTimeoutId: number = -1;

  private queuePageReadingSettingsSave(trigger: string): void {
    if (this.pageSettingsSaveTimeoutId !== -1) {
      clearTimeout(this.pageSettingsSaveTimeoutId);
    }
    this.pageSettingsSaveTimeoutId = setTimeout(() => {
      this.pageSettingsSaveTimeoutId = -1;
      void this.executePersistPageReadingSettings(trigger);
    }, 500);
  }

  private queueTextReadingSettingsSave(trigger: string): void {
    if (this.textSettingsSaveTimeoutId !== -1) {
      clearTimeout(this.textSettingsSaveTimeoutId);
    }
    this.textSettingsSaveTimeoutId = setTimeout(() => {
      this.textSettingsSaveTimeoutId = -1;
      void this.executePersistTextReadingSettings(trigger);
    }, 500);
  }

  private async executePersistPageReadingSettings(trigger: string): Promise<void> {
    if (!this.ebook) {
      return;
    }
    try {
      await this.ebookDataManager.saveImageReaderSettings(
        this.ebook.id,
        this.clonePageReadingSettings(this.pageReadingSettings)
      );
    } catch (error) {
      logger.error(TAG, `保存 WebView EPUB 翻页设置失败: 触发源=${trigger}, 错误=${String(error)}`);
    }
  }

  private async persistPageReadingSettings(trigger: string): Promise<void> {
    this.queuePageReadingSettingsSave(trigger);
  }

  private async executePersistTextReadingSettings(trigger: string): Promise<void> {
    if (!this.ebook) {
      return;
    }
    const snapshot = this.cloneTextReadingSettings(this.readingSettings);
    this.ebook.readingSettings = snapshot;
    try {
      logger.info(
        TAG,
        `保存 WebView EPUB 文本阅读设置: 触发源=${trigger}, fontSize=${snapshot.fontSize}, fontFamily=${snapshot.fontFamily}, fontPath=${snapshot.fontPath || 'none'}, fontWeight=${snapshot.fontWeight}, lineHeight=${snapshot.lineHeight}, pageMargin=${snapshot.pageMargin}, letterSpacing=${snapshot.letterSpacing ?? 0}, paragraphSpacing=${snapshot.paragraphSpacing ?? 8}, firstLineIndent=${snapshot.firstLineIndent ?? 2}, textAlignment=${snapshot.textAlignment ?? 'JUSTIFY'}`
      );
      await this.ebookDataManager.saveReadingSettings(this.ebook.id, snapshot);
    } catch (error) {
      logger.error(TAG, `保存 WebView EPUB 文本阅读设置失败: 触发源=${trigger}, 错误=${String(error)}`);
    }
  }

  private async persistTextReadingSettings(trigger: string): Promise<void> {
    this.queueTextReadingSettingsSave(trigger);
  }

  private syncDeviceOrientationLock(reason: string): void {
    if (!this.uiContext) {
      this.uiContext = this.getUIContext();
    }
    const enabled: boolean = (this.readingSettings.lockDeviceOrientation ?? false) ||
      (this.pageReadingSettings.lockDeviceOrientation ?? false);
    this.orientationLockToken = ReaderOrientationLockHelper.syncCurrentOrientationLock(
      'EpubWebViewReaderPage',
      this.orientationLockToken,
      enabled,
      this.uiContext ?? undefined
    );
    logger.info(TAG, `设备方向锁同步完成: enabled=${enabled}, reason=${reason}`);
  }

  private applyPageReadingSettings(
    settings: MangaReadingSettings,
    trigger: string,
    shouldNotifyUnsupportedMode: boolean = false
  ): void {
    const normalized = this.normalizePageReadingSettings(settings, shouldNotifyUnsupportedMode);
    const readingModeChanged = this.pageReadingSettings.readingMode !== normalized.readingMode ||
      this.pageReadingSettings.readingDirection !== normalized.readingDirection;
    this.pageReadingSettings = this.clonePageReadingSettings(normalized);
    this.autoPageTurnEnabled = normalized.autoPageTurnInterval > 0;
    if (this.autoPageTurnEnabled) {
      this.autoPageTurnIntervalSeconds = normalized.autoPageTurnInterval;
    }
    this.updateVolumeKeyListener();
    this.syncDeviceOrientationLock('page_settings_change');
    this.epubReaderController?.applyPageSettings(normalized);
    void this.persistPageReadingSettings(trigger);
    if (readingModeChanged && !this.showQuickSettings) {
      this.showInteractionOverlay = true;
    }
    this.handleMenusVisibilityChange();
  }

  private getEffectiveComponentWidth(): number {
    if (this.componentWidth > 0) {
      return this.componentWidth;
    }
    const info = display.getDefaultDisplaySync();
    const uiContext = this.uiContext ?? this.getUIContext();
    return uiContext.px2vp(info.width);
  }

  private getEffectiveComponentHeight(): number {
    if (this.componentHeight > 0) {
      return this.componentHeight;
    }
    const info = display.getDefaultDisplaySync();
    const uiContext = this.uiContext ?? this.getUIContext();
    return uiContext.px2vp(info.height);
  }

  private getDeviceOrientation(): 'portrait' | 'landscape' | 'square' {
    const width = this.getEffectiveComponentWidth();
    const height = this.getEffectiveComponentHeight();
    if (Math.abs(width - height) < 1) {
      return 'square';
    }
    return width > height ? 'landscape' : 'portrait';
  }

  private isContinuousReadingMode(): boolean {
    return this.pageReadingSettings.readingMode === ReadingMode.WEBTOON ||
      this.pageReadingSettings.readingMode === ReadingMode.WEBTOON_WITH_GAP ||
      this.pageReadingSettings.readingMode === ReadingMode.CONTINUOUS_VERTICAL;
  }

  private isVerticalPagingMode(): boolean {
    return this.pageReadingSettings.readingMode === ReadingMode.SINGLE_PAGE_TTB ||
      (!this.isContinuousReadingMode() &&
        this.pageReadingSettings.readingDirection === ReadingDirection.TOP_TO_BOTTOM);
  }

  private isRtlPagingMode(): boolean {
    return this.pageReadingSettings.readingDirection === ReadingDirection.RIGHT_TO_LEFT;
  }

  private isDoublePageMode(): boolean {
    return this.pageReadingSettings.readingMode === ReadingMode.DOUBLE_PAGE &&
      this.getEffectiveComponentWidth() > this.getEffectiveComponentHeight();
  }

  private shouldUseGestureOverlay(): boolean {
    return this.isCurrentSpineImageLike();
  }

  private handlePageTap(event: ClickEvent): void {
    if (this.areMenusVisible()) {
      return;
    }
    if (!(this.readingSettings.tapToTurn ?? true)) {
      this.toggleToolbars();
      return;
    }
    this.processReaderTap(event.x, event.y);
  }

  private handleWebViewTap(xRatio: number, yRatio: number): void {
    if (this.areMenusVisible()) {
      return;
    }
    if (!(this.readingSettings.tapToTurn ?? true)) {
      this.toggleToolbars();
      return;
    }
    const displayWidth = this.getEffectiveComponentWidth();
    const displayHeight = this.getEffectiveComponentHeight();
    const safeX = Math.max(0, Math.min(displayWidth, displayWidth * xRatio));
    const safeY = Math.max(0, Math.min(displayHeight, displayHeight * yRatio));
    this.processReaderTap(safeX, safeY);
  }

  private processReaderTap(clickX: number, clickY: number): void {
    const displayWidth = this.getEffectiveComponentWidth();
    const displayHeight = this.getEffectiveComponentHeight();
    if (this.isDoublePageMode()) {
      this.handleDoublePageTap(clickX, clickY, displayWidth, displayHeight);
      return;
    }
    if (this.isVerticalPagingMode()) {
      this.handleVerticalPageTap(clickY, displayHeight);
      return;
    }
    this.handleHorizontalPageTap(clickX, displayWidth);
  }

  private handleDoublePageTap(
    clickX: number,
    clickY: number,
    displayWidth: number,
    displayHeight: number
  ): void {
    const centerAreaRatio = 0.4;
    const sideAreaRatio = (1 - centerAreaRatio) / 2;
    if (this.pageReadingSettings.readingDirection === ReadingDirection.TOP_TO_BOTTOM) {
      const topZoneEnd = displayHeight * sideAreaRatio;
      const bottomZoneStart = displayHeight * (1 - sideAreaRatio);
      if (clickY < topZoneEnd) {
        this.flipPage(false);
      } else if (clickY > bottomZoneStart) {
        this.flipPage(true);
      } else {
        this.toggleToolbars();
      }
      return;
    }
    const leftZoneEnd = displayWidth * sideAreaRatio;
    const rightZoneStart = displayWidth * (1 - sideAreaRatio);
    if (clickX < leftZoneEnd) {
      if (this.isRtlPagingMode()) {
        this.flipPage(true);
      } else {
        this.flipPage(false);
      }
    } else if (clickX > rightZoneStart) {
      if (this.isRtlPagingMode()) {
        this.flipPage(false);
      } else {
        this.flipPage(true);
      }
    } else {
      this.toggleToolbars();
    }
  }

  private handleVerticalPageTap(clickY: number, displayHeight: number): void {
    const centerAreaRatio = 0.4;
    const sideAreaRatio = (1 - centerAreaRatio) / 2;
    const topZoneEnd = displayHeight * sideAreaRatio;
    const bottomZoneStart = displayHeight * (1 - sideAreaRatio);
    if (clickY < topZoneEnd) {
      this.flipPage(false);
    } else if (clickY > bottomZoneStart) {
      this.flipPage(true);
    } else {
      this.toggleToolbars();
    }
  }

  private handleHorizontalPageTap(clickX: number, displayWidth: number): void {
    const centerAreaRatio = 0.4;
    const sideAreaRatio = (1 - centerAreaRatio) / 2;
    const leftZoneEnd = displayWidth * sideAreaRatio;
    const rightZoneStart = displayWidth * (1 - sideAreaRatio);
    if (clickX < leftZoneEnd) {
      if (this.isRtlPagingMode()) {
        this.flipPage(true);
      } else {
        this.flipPage(false);
      }
    } else if (clickX > rightZoneStart) {
      if (this.isRtlPagingMode()) {
        this.flipPage(false);
      } else {
        this.flipPage(true);
      }
    } else {
      this.toggleToolbars();
    }
  }

  private shouldUseInteractiveCurlGesture(): boolean {
    return this.pageReadingSettings.pageTurnAnimation === PageTurnAnimationType.CURL &&
      !this.isContinuousReadingMode() &&
      !this.isVerticalPagingMode();
  }

  private resetEpubCurlGestureState(): void {
    this.epubCurlGestureActive = false;
    this.epubCurlGestureStarted = false;
    this.epubCurlGestureStartX = 0;
    this.epubCurlGestureStartY = 0;
    this.epubCurlGestureProgress = 0;
  }

  private handleReaderPanStart(event: GestureEvent): void {
    this.resetEpubCurlGestureState();
    if (!event.fingerList || event.fingerList.length <= 0 || !event.fingerList[0]) {
      return;
    }
    this.epubCurlGestureStartX = event.fingerList[0].globalX;
    this.epubCurlGestureStartY = event.fingerList[0].globalY;
  }

  private handleReaderPanUpdate(event: GestureEvent): void {
    if (this.areMenusVisible() || !this.shouldUseInteractiveCurlGesture()) {
      return;
    }
    if (!event.fingerList || event.fingerList.length <= 0 || !event.fingerList[0]) {
      return;
    }
    const deltaX = event.offsetX;
    const deltaY = event.offsetY;
    if (Math.abs(deltaX) < Math.max(8, Math.abs(deltaY))) {
      return;
    }

    const swipingLeft = deltaX < 0;
    const forward = this.isRtlPagingMode() ? !swipingLeft : swipingLeft;
    const displayWidth = Math.max(1, this.getEffectiveComponentWidth());
    const progress = Math.max(0.01, Math.min(0.96, Math.abs(deltaX) / displayWidth));
    const touchX = this.epubCurlGestureStartX + deltaX;
    const touchY = this.epubCurlGestureStartY + deltaY;

    if (!this.epubCurlGestureStarted) {
      if (!this.epubReaderController?.beginInteractiveCurl(forward, this.epubCurlGestureStartX, this.epubCurlGestureStartY)) {
        return;
      }
      this.epubCurlGestureStarted = true;
      this.epubCurlGestureActive = true;
      this.currentAnchorFragment = '';
      this.stopAutoPageTurn();
    }

    this.epubCurlGestureProgress = progress;
    this.epubReaderController?.updateInteractiveCurl(progress, touchX, touchY);
  }

  private handleReaderPanEnd(event: GestureEvent): void {
    if (this.epubCurlGestureActive) {
      const displayWidth = Math.max(1, this.getEffectiveComponentWidth());
      const progress = Math.max(this.epubCurlGestureProgress, Math.abs(event.offsetX) / displayWidth);
      const complete = progress >= 0.34 || Math.abs(event.offsetX) >= displayWidth * 0.32;
      const handled = this.epubReaderController?.endInteractiveCurl(complete) ?? false;
      this.resetEpubCurlGestureState();
      if (handled) {
        if (complete) {
          this.syncAutoPageTurnState();
        }
        return;
      }
    }
    this.resetEpubCurlGestureState();
    this.handleSwipe(event);
  }

  private handleReaderSwipeDelta(deltaX: number, deltaY: number): void {
    if (this.areMenusVisible()) {
      return;
    }
    if (this.isContinuousReadingMode() && !this.isCurrentSpineImageLike()) {
      return;
    }
    if (this.isVerticalPagingMode()) {
      if (Math.abs(deltaY) < Math.max(40, Math.abs(deltaX))) {
        return;
      }
      this.flipPage(deltaY < 0);
      return;
    }
    if (Math.abs(deltaX) < Math.max(40, Math.abs(deltaY))) {
      return;
    }
    const swipingLeft = deltaX < 0;
    const forward = this.isRtlPagingMode() ? !swipingLeft : swipingLeft;
    this.flipPage(forward);
  }

  private handleSwipe(event: GestureEvent): void {
    this.handleReaderSwipeDelta(event.offsetX, event.offsetY);
  }

  private flipPage(forward: boolean, source: string = 'manual'): boolean {
    if (!this.epubReaderController) {
      logger.debug(TAG, `翻页请求被忽略: 控制器未就绪, forward=${forward}`);
      return false;
    }
    if (source === 'manual') {
      this.handleEpubManualReadAloudNavigation('manual_page_turn');
    }
    const handled = this.epubReaderController.flipPage(forward);
    if (handled) {
      this.currentAnchorFragment = '';
      this.syncAutoPageTurnState();
      return true;
    }
    logger.debug(
      TAG,
      `当前 spine 内翻页未处理，尝试跨 spine: forward=${forward}, spine=${this.currentSpineIndex}, page=${this.currentPageWithinSpine}/${this.totalPagesInSpine}, mode=${this.pageReadingSettings.readingMode}, direction=${this.pageReadingSettings.readingDirection}`
    );
    const chapterChanged = this.onSpineChangeRequested(forward ? 'next' : 'prev', source);
    if (!chapterChanged) {
      this.stopAutoPageTurn();
    }
    return chapterChanged;
  }

  private onSpineChangeRequested(direction: 'prev' | 'next', source: string = 'manual'): boolean {
    if (direction === 'next') {
      const nextSpineIndex = this.findReadableSpineIndex(this.currentSpineIndex + 1, 1);
      if (nextSpineIndex >= 0) {
        this.loadSpineItem(nextSpineIndex, 0, 'next', '', source);
        return true;
      }
      this.getUIContext().getPromptAction().showToast({ message: '已是最后一章', duration: 1200 });
      return false;
    }
    const previousSpineIndex = this.findReadableSpineIndex(this.currentSpineIndex - 1, -1);
    if (previousSpineIndex >= 0) {
      this.loadSpineItem(previousSpineIndex, 99999, 'prev', '', source);
      return true;
    }
    this.getUIContext().getPromptAction().showToast({ message: '已是第一章', duration: 1200 });
    return false;
  }

  /**
   * [修复] WebView EPUB 被控端遥控指令监听（与文本阅读器一致）：
   * 翻页/章节切换/朗读开关，执行后回 ack。
   */
  private onRemoteDataChanged = (state: SyncReadingState) => {
    if (!state.instructionType || state.instructionType === 'none' || state.instructionType === 'ack') {
      return;
    }
    if (state.timestamp <= this.lastRemoteInstructionTimestamp) {
      return;
    }
    this.lastRemoteInstructionTimestamp = state.timestamp;
    logger.info(TAG, `[RemoteControl] 收到 WebView EPUB 遥控指令: ${state.instructionType}`);
    switch (state.instructionType) {
      case 'cmd:next_page':
        this.flipPage(true, 'remote_next_page');
        break;
      case 'cmd:prev_page':
        this.flipPage(false, 'remote_prev_page');
        break;
      case 'cmd:next_chapter':
        this.onSpineChangeRequested('next', 'remote_next_chapter');
        break;
      case 'cmd:prev_chapter':
        this.onSpineChangeRequested('prev', 'remote_prev_chapter');
        break;
      case 'cmd:toggle_auto_read':
        this.toggleReadAloudFromToolbar();
        break;
      default:
        logger.warn(TAG, `[RemoteControl] 未知 WebView EPUB 指令: ${state.instructionType}`);
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
    logger.info(TAG, '[RemoteControl] WebView EPUB 被控端已注册遥控器指令监听');
    this.remoteCallbacksRegistered = true;
    this.getUIContext().getPromptAction().showToast({ message: '遥控已连接' });
    distributedDataSyncManager.addOnDataChangedCallback(this.onRemoteDataChanged);
    distributedDataSyncManager.addOnStatusChangedCallback(this.onRemoteStatusChanged);
    distributedDataSyncManager.diagnoseSession('WebView EPUB 被控端注册');
  }

  private unregisterRemoteControlListener(): void {
    if (!this.remoteCallbacksRegistered) {
      return;
    }
    this.remoteCallbacksRegistered = false;
    distributedDataSyncManager.removeOnDataChangedCallback(this.onRemoteDataChanged);
    distributedDataSyncManager.removeOnStatusChangedCallback(this.onRemoteStatusChanged);
  }

  private loadSpineItem(
    spineIndex: number,
    pageOffset: number,
    transitionDirection: EpubSpineTransitionDirection = 'none',
    anchorFragment: string = '',
    source: string = 'manual'
  ): void {
    const requestStartedAt = Date.now();
    const resolvedSpineIndex = this.resolveReadableSpineIndex(spineIndex, transitionDirection);
    if (resolvedSpineIndex < 0) {
      logger.warn(TAG, `请求切换 spine 失败: 未找到可读 spine, requested=${spineIndex}, direction=${transitionDirection}`);
      this.recordEpubReadFlowEvent(
        EpubReadFlowEventType.SPINE_REQUESTED,
        'spine_request_no_readable_target',
        Math.max(0, Date.now() - requestStartedAt),
        false,
        `requested=${spineIndex}, direction=${transitionDirection}`
      );
      return;
    }
    const path = this.resolveSpinePath(resolvedSpineIndex);
    if (path.length === 0) {
      this.recordEpubReadFlowEvent(
        EpubReadFlowEventType.SPINE_REQUESTED,
        'spine_request_empty_path',
        Math.max(0, Date.now() - requestStartedAt),
        false,
        `requested=${spineIndex}, resolved=${resolvedSpineIndex}`
      );
      return;
    }
    if (source === 'manual') {
      this.handleEpubManualReadAloudNavigation('manual_spine_navigation');
    }
    const movedToDifferentSpine = resolvedSpineIndex !== spineIndex;
    const normalizedAnchor = movedToDifferentSpine ? '' : anchorFragment.trim();
    const normalizedPageOffset = movedToDifferentSpine ? (transitionDirection === 'prev' ? 99999 : 0) : pageOffset;
    this.currentAnchorFragment = normalizedAnchor;
    if (resolvedSpineIndex !== this.currentSpineIndex) {
      this.currentSpineHighlightRanges = [];
      this.currentVisibleTextSnapshot = null;
      this.currentSpineTextCache = '';
      this.currentSpineTextCacheIndex = -1;
      this.currentPageBookmarkId = '';
      this.isCurrentPageBookmarked = false;
      this.epubReaderController?.clearReadAloudHighlight();
    }
    if (!this.epubReaderController) {
      this.pendingSpineIndex = -1;
      this.currentSpineIndex = resolvedSpineIndex;
      this.currentPageWithinSpine = 0;
      this.totalPagesInSpine = 0;
      void this.refreshCurrentSpineHighlightRanges('spine_change_without_controller');
      this.recordEpubReadFlowEvent(
        EpubReadFlowEventType.SPINE_REQUESTED,
        'spine_change_without_controller',
        Math.max(0, Date.now() - requestStartedAt),
        true,
        `resolved=${resolvedSpineIndex}, path=${path}`
      );
      return;
    }
    this.pendingSpineIndex = resolvedSpineIndex;
    this.epubReaderController.loadSpineItem(
      path,
      normalizedPageOffset,
      transitionDirection,
      normalizedAnchor,
      this.getSpineLayoutType(resolvedSpineIndex),
      this.getSpineMediaType(resolvedSpineIndex)
    );
    logger.info(
      TAG,
      `请求切换 spine: requested=${spineIndex}, resolved=${resolvedSpineIndex}, pageOffset=${normalizedPageOffset}, direction=${transitionDirection}, anchor=${normalizedAnchor || 'none'}, path=${path}`
    );
    this.recordEpubReadFlowEvent(
      EpubReadFlowEventType.SPINE_REQUESTED,
      source,
      Math.max(0, Date.now() - requestStartedAt),
      true,
      `requested=${spineIndex}, resolved=${resolvedSpineIndex}, pageOffset=${normalizedPageOffset}, direction=${transitionDirection}`
    );
  }

  private jumpToCurrentSpinePage(pageIndex: number): void {
    if (!this.epubReaderController || this.totalPagesInSpine <= 0) {
      return;
    }
    const safePageIndex = Math.max(0, Math.min(pageIndex, this.totalPagesInSpine - 1));
    this.handleEpubManualReadAloudNavigation('manual_page_jump');
    const moved = this.epubReaderController.goToPage(safePageIndex);
    if (moved) {
      this.syncAutoPageTurnState();
      logger.info(TAG, `跳转章节页: spine=${this.currentSpineIndex}, page=${safePageIndex}/${this.totalPagesInSpine}`);
    }
  }

  private registerVolumeKeyListener(): void {
    if (this.isVolumeKeyListenerRegistered) {
      return;
    }
    if (!this.pageReadingSettings.volumeKeyNavigation || this.isLoading || this.errorMessage.trim().length > 0) {
      return;
    }

    const volumeUpConfig: inputConsumer.KeyPressedConfig = {
      key: KeyCode.KEYCODE_VOLUME_UP,
      action: 1,
      isRepeat: false
    };
    const volumeDownConfig: inputConsumer.KeyPressedConfig = {
      key: KeyCode.KEYCODE_VOLUME_DOWN,
      action: 1,
      isRepeat: false
    };

    this.volumeUpCallback = (_event: InputKeyEvent) => {
      logger.info(TAG, '音量键翻页: 上一页 (inputConsumer)');
      if (!this.areMenusVisible()) {
        this.flipPage(false);
      }
    };
    this.volumeDownCallback = (_event: InputKeyEvent) => {
      logger.info(TAG, '音量键翻页: 下一页 (inputConsumer)');
      if (!this.areMenusVisible()) {
        this.flipPage(true);
      }
    };

    try {
      inputConsumer.on('keyPressed', volumeUpConfig, this.volumeUpCallback);
      inputConsumer.on('keyPressed', volumeDownConfig, this.volumeDownCallback);
      this.isVolumeKeyListenerRegistered = true;
      logger.info(TAG, 'EPUB 音量键翻页监听已注册');
    } catch (error) {
      try {
        if (this.volumeUpCallback !== null) {
          inputConsumer.off('keyPressed', this.volumeUpCallback);
        }
        if (this.volumeDownCallback !== null) {
          inputConsumer.off('keyPressed', this.volumeDownCallback);
        }
      } catch (_cleanupError) {}
      this.volumeUpCallback = null;
      this.volumeDownCallback = null;
      logger.warn(TAG, `注册 EPUB 音量键翻页监听失败: ${String(error)}`);
    }
  }

  private unregisterVolumeKeyListener(): void {
    if (!this.isVolumeKeyListenerRegistered) {
      this.volumeUpCallback = null;
      this.volumeDownCallback = null;
      return;
    }

    try {
      if (this.volumeUpCallback !== null) {
        inputConsumer.off('keyPressed', this.volumeUpCallback);
      }
      if (this.volumeDownCallback !== null) {
        inputConsumer.off('keyPressed', this.volumeDownCallback);
      }
      logger.info(TAG, 'EPUB 音量键翻页监听已注销');
    } catch (error) {
      logger.warn(TAG, `注销 EPUB 音量键翻页监听失败: ${String(error)}`);
    }
    this.volumeUpCallback = null;
    this.volumeDownCallback = null;
    this.isVolumeKeyListenerRegistered = false;
  }

  private updateVolumeKeyListener(): void {
    if (this.pageReadingSettings.volumeKeyNavigation && !this.isLoading && this.errorMessage.trim().length <= 0) {
      this.registerVolumeKeyListener();
      return;
    }
    this.unregisterVolumeKeyListener();
  }

  private handleVolumeKey(keyCode: number): boolean {
    if (!this.pageReadingSettings.volumeKeyNavigation) {
      return false;
    }
    if (keyCode === KeyCode.KEYCODE_VOLUME_UP || keyCode === 16) {
      if (!this.areMenusVisible()) {
        this.flipPage(false);
      }
      return true;
    }
    if (keyCode === KeyCode.KEYCODE_VOLUME_DOWN || keyCode === 17) {
      if (!this.areMenusVisible()) {
        this.flipPage(true);
      }
      return true;
    }
    return false;
  }

  // ──── 工具栏图标颜色 ────

  private getToolbarIconColor(isActive: boolean = false): ResourceColor {
    if (this.themeManager.isDarkThemeSync()) {
      return Color.White;
    }
    return isActive ? $r('app.color.accent_primary') : $r('app.color.text_primary');
  }

  private getAutoPageTurnIconResource(): Resource {
    return this.autoPageTurnEnabled ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill');
  }

  // ──── 工具栏显隐 ────

  private areMenusVisible(): boolean {
    return this.showSettingsPanel ||
      this.showQuickSettings ||
      this.showChapterList ||
      this.showPageTurnAnimationSettings ||
      this.showAutoPageTurnSettings ||
      this.showReadAloudPanel ||
      this.showInteractionOverlay;
  }

  private closeTransientPanels(): void {
    if (this.showReadAloudPanel) {
      this.lastReadAloudPanelCloseTime = Date.now();
      this.showReadAloudPanel = false;
      this.handleMenusVisibilityChange();
      return;
    }
    if (this.showQuickSettings) {
      this.hideQuickSettingsWithAnimation(null);
      return;
    }
    if (this.showPageTurnAnimationSettings) {
      this.hidePageTurnAnimationSettingsWithAnimation(null);
      return;
    }
    if (this.showAutoPageTurnSettings) {
      this.hideAutoPageTurnSettingsWithAnimation(null);
      return;
    }
    this.showSettingsPanel = false;
    this.showChapterList = false;
    this.showInteractionOverlay = false;
    this.handleMenusVisibilityChange();
  }

  private toggleToolbars(): void {
    if (this.areMenusVisible()) {
      this.closeTransientPanels();
      return;
    }
    if (this.showTopToolbar || this.showBottomToolbar) {
      this.hideToolbars();
    } else {
      this.showToolbars();
    }
  }

  private showToolbars(): void {
    this.stopAutoPageTurn();
    this.showTopToolbar = true;
    this.showBottomToolbar = true;
    const ctx = this.uiContext;
    if (ctx) {
      ctx.animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
        this.toolbarOpacity = 1;
      });
    } else {
      this.toolbarOpacity = 1;
    }
    this.scheduleToolbarAutoHide();
  }

  private hideToolbars(): void {
    this.clearToolbarTimer();
    const ctx = this.uiContext;
    if (ctx) {
      ctx.animateTo({
        duration: 180,
        curve: Curve.EaseIn,
        onFinish: () => {
          this.showTopToolbar = false;
          this.showBottomToolbar = false;
          this.syncAutoPageTurnState();
        }
      }, () => {
        this.toolbarOpacity = 0;
      });
    } else {
      this.toolbarOpacity = 0;
      this.showTopToolbar = false;
      this.showBottomToolbar = false;
      this.syncAutoPageTurnState();
    }
    this.scheduleFullscreenRestore('hide_toolbars', 200);
  }

  private scheduleToolbarAutoHide(): void {
    if (!this.showTopToolbar && !this.showBottomToolbar) {
      return;
    }
    if (this.areMenusVisible()) {
      return;
    }
    this.clearToolbarTimer();
    this.toolbarHideTimer = setTimeout(() => {
      this.toolbarHideTimer = -1;
      if (!this.areMenusVisible()) {
        this.hideToolbars();
      }
    }, EpubWebViewReaderPage.TOOLBAR_AUTO_HIDE_MS);
  }

  private clearToolbarTimer(): void {
    if (this.toolbarHideTimer !== -1) {
      clearTimeout(this.toolbarHideTimer);
      this.toolbarHideTimer = -1;
    }
  }

  private handleMenusVisibilityChange(): void {
    if (this.areMenusVisible()) {
      this.clearToolbarTimer();
      this.stopAutoPageTurn();
      return;
    }
    this.scheduleToolbarAutoHide();
    this.scheduleFullscreenRestore('menus_closed', 80);
    this.syncAutoPageTurnState();
  }

  private startAutoPageTurn(): void {
    if (!this.autoPageTurnEnabled || this.autoPageTurnIntervalSeconds <= 0) {
      return;
    }
    this.stopAutoPageTurn();
    this.autoPageTurnTimer = setInterval(() => {
      const moved = this.flipPage(true, 'auto_page_turn');
      if (!moved) {
        this.stopAutoPageTurn();
      }
    }, this.autoPageTurnIntervalSeconds * 1000);
  }

  private stopAutoPageTurn(): void {
    if (this.autoPageTurnTimer !== -1) {
      clearInterval(this.autoPageTurnTimer);
      this.autoPageTurnTimer = -1;
    }
  }

  private syncAutoPageTurnState(): void {
    if (!this.autoPageTurnEnabled ||
      this.isLoading ||
      this.errorMessage.trim().length > 0 ||
      this.areMenusVisible() ||
      this.showTopToolbar ||
      this.showBottomToolbar ||
      !this.epubReaderController ||
      !this.epubReaderController.isReady()) {
      this.stopAutoPageTurn();
      return;
    }
    this.startAutoPageTurn();
  }

  private setAutoPageTurnEnabled(enabled: boolean): void {
    const nextSettings = this.clonePageReadingSettings(this.pageReadingSettings);
    nextSettings.autoPageTurnInterval = enabled ? this.autoPageTurnIntervalSeconds : 0;
    this.applyPageReadingSettings(nextSettings, 'toggle_auto_page_turn');
  }

  private setAutoPageTurnIntervalSeconds(value: number): void {
    const clamped = Math.max(1, Math.min(30, Math.round(value)));
    this.autoPageTurnIntervalSeconds = clamped;
    if (!this.autoPageTurnEnabled) {
      return;
    }
    const nextSettings = this.clonePageReadingSettings(this.pageReadingSettings);
    nextSettings.autoPageTurnInterval = clamped;
    this.applyPageReadingSettings(nextSettings, 'update_auto_page_turn_interval');
  }

  private isForcedProgressSave(trigger: string): boolean {
    return trigger === 'about_to_disappear' ||
      trigger === 'page_hide' ||
      trigger === 'go_back' ||
      trigger === 'chapter_list_jump' ||
      trigger === 'slider';
  }

  private getProgressSaveIntervalMs(): number {
    const seconds = Math.max(1, Math.round(this.readingSettings.saveInterval ?? 0));
    return seconds * 1000;
  }

  private scheduleFullscreenRestore(reason: string, delayMs: number = 120): void {
    this.clearFullscreenRestoreTimer();
    this.fullscreenRestoreTimer = setTimeout(() => {
      this.fullscreenRestoreTimer = -1;
      const ctx = this.uiContext ?? undefined;
      logger.debug(TAG, `重新应用沉浸模式: 原因=${reason}`);
      WindowManager.setDisplayMode(DisplayMode.FULL_IMMERSIVE, ctx);
      WindowManager.reapplyCurrentDisplayMode(24);
    }, delayMs);
  }

  private clearFullscreenRestoreTimer(): void {
    if (this.fullscreenRestoreTimer !== -1) {
      clearTimeout(this.fullscreenRestoreTimer);
      this.fullscreenRestoreTimer = -1;
    }
  }

  // ──── 进度保存 ────

  private async saveReadingProgress(trigger: string): Promise<void> {
    const saveStartedAt = Date.now();
    const ebook = this.ebook;
    if (!ebook) {
      return;
    }
    const forceSave = this.isForcedProgressSave(trigger);
    const now = Date.now();
    if (!forceSave && !(this.readingSettings.autoSave ?? true)) {
      return;
    }
    const intervalMs = Math.max(
      EpubWebViewReaderPage.PROGRESS_SAVE_INTERVAL_MS,
      this.getProgressSaveIntervalMs()
    );
    if (!forceSave && (now - this.lastProgressSaveTime) < intervalMs) {
      return;
    }
    const baseTotalReadingTime = ebook.readingProgress?.totalReadingTime ?? 0;
    const sessionMinutes = this.sessionStartTimestamp > 0 ? Math.max(0, (now - this.sessionStartTimestamp) / 60000) : 0;
    const progressPercent = this.getReadingProgressValue();
    const progress: EBookReadingProgress = {
      bookId: ebook.id,
      currentChapterId: this.spineItems[this.currentSpineIndex]?.id ?? '',
      currentChapterIndex: this.currentSpineIndex,
      currentPosition: this.currentPageWithinSpine,
      domPos: `webview-epub:${this.currentSpineIndex}:${this.currentPageWithinSpine}`,
      progress: progressPercent,
      lastReadTime: now,
      totalReadingTime: baseTotalReadingTime + sessionMinutes
    };
    try {
      await this.ebookDataManager.saveReadingProgress(progress);
      ebook.readingProgress = progress;
      // [修复] 同步跨端接续阅读状态（currentRead* + 独立通道推送），
      // WebView EPUB 阅读器此前缺失该调用，导致 onContinue 打包旧书状态被拒绝
      distributedReadingService.syncProgress(ebook.id, progress.currentChapterIndex, progress.currentPosition, 0, 'ebook');
      this.lastProgressSaveTime = now;
      this.sessionStartTimestamp = now;
      logger.debug(
        TAG,
        `[${trigger}] 进度已保存: spine=${this.currentSpineIndex}, page=${this.currentPageWithinSpine}/${this.totalPagesInSpine}, progress=${progressPercent.toFixed(2)}%, totalReadingTime=${progress.totalReadingTime.toFixed(2)}min`
      );
      this.recordEpubReadFlowEvent(
        EpubReadFlowEventType.PROGRESS_SAVED,
        trigger,
        Math.max(0, Date.now() - saveStartedAt),
        true,
        `spine=${this.currentSpineIndex}, page=${this.currentPageWithinSpine}/${this.totalPagesInSpine}`
      );
    } catch (e) {
      logger.warn(TAG, `保存进度失败: ${String(e)}`);
      this.recordEpubReadFlowEvent(
        EpubReadFlowEventType.PROGRESS_SAVED,
        `${trigger}_failed`,
        Math.max(0, Date.now() - saveStartedAt),
        false,
        String(e)
      );
    }
  }

  // ──── 返回 ────

  private openWithReaderKit(): void {
    if (!isReaderKitEnabled()) {
      this.canFallbackToReaderKit = false;
      logger.warn(TAG, 'ReaderKit fallback blocked by global feature gate');
      this.getUIContext().getPromptAction().showToast({ message: 'ReaderKit 已在当前环境关闭', duration: 1400 });
      return;
    }
    const bookId = this.ebook?.id ?? '';
    if (!bookId) {
      this.closeReaderRoute();
      return;
    }
    const params: EBookReaderParams = {
      bookId: bookId,
      coverComponentId: this.coverComponentId,
      forceReaderKit: true,
      readerHostMode: this.readerHostMode,
      readerInstanceId: this.readerInstanceId,
      readerTitle: this.ebook?.metadata.title || ''
    };
    if (this.isHostedByIsolatedReaderAbility()) {
      this.pathStack.replacePathByName('EBookReaderPage', params, false);
      return;
    }
    this.closeReaderRoute();
    openEBookReaderRouterPage(this.getUIContext(), params, TAG);
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

  private isHostedByIsolatedReaderAbility(): boolean {
    return this.readerHostMode === READER_ABILITY_HOST_MULTITON;
  }

  private async terminateIsolatedReaderAbility(reason: string): Promise<void> {
    try {
      const hostContext = this.getUIContext()?.getHostContext() as common.UIAbilityContext;
      if (!hostContext) {
        logger.warn(TAG, `独立 EPUB 阅读器退出失败，回退页面栈: reason=${reason}`);
        this.pathStack.pop();
        return;
      }
      logger.info(TAG, `独立 EPUB 阅读器实例退出: reason=${reason}, instanceId=${this.readerInstanceId}`);
      await hostContext.terminateSelf();
    } catch (error) {
      logger.error(TAG, `独立 EPUB 阅读器实例退出异常: ${String(error)}`);
      this.pathStack.pop();
    }
  }

  private async goBack(): Promise<void> {
    if (this.areMenusVisible()) {
      this.closeTransientPanels();
      return;
    }
    this.stopAutoPageTurn();
    await this.persistTextReadingSettings('go_back');
    await this.persistPageReadingSettings('go_back');
    await this.saveReadingProgress('go_back');
    const coverCmpId = this.coverComponentId;
    if (this.isHostedByIsolatedReaderAbility()) {
      logger.info(TAG, `独立 EPUB 阅读器退出不挂载关闭动画层，封面组件ID: ${coverCmpId}`);
      cancelTransition();
      await this.terminateIsolatedReaderAbility('go_back_isolated_reader');
      return;
    }
    if (coverCmpId) {
      try {
        await startBookCloseTransitionWithComponentId('epub_webview_reader_root', coverCmpId);
      } catch (_ignored) {
        cancelTransition();
      }
    }
    this.closeReaderRoute();
  }

  private openChapterList(): void {
    if (this.showQuickSettings) {
      this.hideQuickSettingsWithAnimation(() => {
        this.openChapterList();
      });
      return;
    }
    if (this.showPageTurnAnimationSettings) {
      this.hidePageTurnAnimationSettingsWithAnimation(() => {
        this.openChapterList();
      });
      return;
    }
    if (this.showAutoPageTurnSettings) {
      this.hideAutoPageTurnSettingsWithAnimation(() => {
        this.openChapterList();
      });
      return;
    }
    this.showQuickSettings = false;
    this.showSettingsPanel = false;
    this.showPageTurnAnimationSettings = false;
    this.showAutoPageTurnSettings = false;
    this.showInteractionOverlay = false;
    this.showChapterList = true;
    this.handleMenusVisibilityChange();
  }

  private resetQuickSettingsAnimationState(): void {
    this.quickSettingsOpacity = 0;
    this.quickSettingsScale = 0.96;
    this.quickSettingsTranslateY = 24;
  }

  private openQuickSettingsWithAnimation(): void {
    this.showSettingsPanel = false;
    this.showChapterList = false;
    this.showPageTurnAnimationSettings = false;
    this.showAutoPageTurnSettings = false;
    this.showInteractionOverlay = false;
    this.resetQuickSettingsAnimationState();
    this.showQuickSettings = true;
    this.handleMenusVisibilityChange();

    const ctx = this.uiContext;
    if (!ctx) {
      this.quickSettingsOpacity = 1;
      this.quickSettingsScale = 1;
      this.quickSettingsTranslateY = 0;
      return;
    }
    setTimeout(() => {
      const nextCtx = this.uiContext;
      if (!this.showQuickSettings || !nextCtx) {
        return;
      }
      nextCtx.animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
        this.quickSettingsOpacity = 1;
        this.quickSettingsScale = 1;
        this.quickSettingsTranslateY = 0;
      });
    }, 0);
  }

  private hideQuickSettingsWithAnimation(afterClose: (() => void) | null): void {
    if (!this.showQuickSettings) {
      if (afterClose !== null) {
        afterClose();
      }
      return;
    }

    const finish = (): void => {
      this.showQuickSettings = false;
      this.handleMenusVisibilityChange();
      if (afterClose === null) {
        this.scheduleFullscreenRestore('quick_settings_closed', 80);
      } else {
        afterClose();
      }
    };

    const ctx = this.uiContext;
    if (!ctx) {
      this.resetQuickSettingsAnimationState();
      finish();
      return;
    }
    ctx.animateTo({
      duration: 160,
      curve: Curve.EaseIn,
      onFinish: () => {
        finish();
      }
    }, () => {
      this.resetQuickSettingsAnimationState();
    });
  }

  private resetPageTurnSettingsAnimationState(): void {
    this.pageTurnSettingsBackdropOpacity = 0;
    this.pageTurnSettingsPanelOpacity = 0;
    this.pageTurnSettingsPanelScale = 0.96;
    this.pageTurnSettingsPanelTranslateX = this.isLandscapeMode ? 48 : 0;
    this.pageTurnSettingsPanelTranslateY = this.isLandscapeMode ? 0 : 24;
  }

  private openPageTurnAnimationSettingsWithAnimation(): void {
    this.refreshAppFontFamilyForDialog('page_turn_settings_open');
    this.showQuickSettings = false;
    this.showChapterList = false;
    this.showSettingsPanel = false;
    this.showAutoPageTurnSettings = false;
    this.showInteractionOverlay = false;
    this.resetPageTurnSettingsAnimationState();
    this.showPageTurnAnimationSettings = true;
    this.handleMenusVisibilityChange();

    const ctx = this.uiContext;
    if (!ctx) {
      this.pageTurnSettingsBackdropOpacity = 0.5;
      this.pageTurnSettingsPanelOpacity = 1;
      this.pageTurnSettingsPanelScale = 1;
      this.pageTurnSettingsPanelTranslateX = 0;
      this.pageTurnSettingsPanelTranslateY = 0;
      return;
    }
    setTimeout(() => {
      const nextCtx = this.uiContext;
      if (!this.showPageTurnAnimationSettings || !nextCtx) {
        return;
      }
      nextCtx.animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
        this.pageTurnSettingsBackdropOpacity = 0.5;
        this.pageTurnSettingsPanelOpacity = 1;
        this.pageTurnSettingsPanelScale = 1;
        this.pageTurnSettingsPanelTranslateX = 0;
        this.pageTurnSettingsPanelTranslateY = 0;
      });
    }, 0);
  }

  private hidePageTurnAnimationSettingsWithAnimation(afterClose: (() => void) | null): void {
    if (!this.showPageTurnAnimationSettings) {
      if (afterClose !== null) {
        afterClose();
      }
      return;
    }

    const finish = (): void => {
      this.showPageTurnAnimationSettings = false;
      this.handleMenusVisibilityChange();
      if (afterClose === null) {
        this.scheduleFullscreenRestore('page_turn_settings_closed', 80);
      } else {
        afterClose();
      }
    };

    const ctx = this.uiContext;
    if (!ctx) {
      this.resetPageTurnSettingsAnimationState();
      finish();
      return;
    }
    ctx.animateTo({
      duration: 170,
      curve: Curve.EaseIn,
      onFinish: () => {
        finish();
      }
    }, () => {
      this.resetPageTurnSettingsAnimationState();
    });
  }

  private resetAutoPageTurnSettingsAnimationState(): void {
    this.autoPageTurnSettingsBackdropOpacity = 0;
    this.autoPageTurnSettingsPanelOpacity = 0;
    this.autoPageTurnSettingsPanelScale = 0.96;
    this.autoPageTurnSettingsPanelTranslateX = this.isLandscapeMode ? 48 : 0;
    this.autoPageTurnSettingsPanelTranslateY = this.isLandscapeMode ? 0 : 24;
  }

  private openAutoPageTurnSettingsWithAnimation(): void {
    this.refreshAppFontFamilyForDialog('auto_page_turn_settings_open');
    this.showQuickSettings = false;
    this.showChapterList = false;
    this.showSettingsPanel = false;
    this.showPageTurnAnimationSettings = false;
    this.showInteractionOverlay = false;
    this.resetAutoPageTurnSettingsAnimationState();
    this.showAutoPageTurnSettings = true;
    this.handleMenusVisibilityChange();

    const ctx = this.uiContext;
    if (!ctx) {
      this.autoPageTurnSettingsBackdropOpacity = 0.5;
      this.autoPageTurnSettingsPanelOpacity = 1;
      this.autoPageTurnSettingsPanelScale = 1;
      this.autoPageTurnSettingsPanelTranslateX = 0;
      this.autoPageTurnSettingsPanelTranslateY = 0;
      return;
    }
    setTimeout(() => {
      const nextCtx = this.uiContext;
      if (!this.showAutoPageTurnSettings || !nextCtx) {
        return;
      }
      nextCtx.animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
        this.autoPageTurnSettingsBackdropOpacity = 0.5;
        this.autoPageTurnSettingsPanelOpacity = 1;
        this.autoPageTurnSettingsPanelScale = 1;
        this.autoPageTurnSettingsPanelTranslateX = 0;
        this.autoPageTurnSettingsPanelTranslateY = 0;
      });
    }, 0);
  }

  private hideAutoPageTurnSettingsWithAnimation(afterClose: (() => void) | null): void {
    if (!this.showAutoPageTurnSettings) {
      if (afterClose !== null) {
        afterClose();
      }
      return;
    }

    const finish = (): void => {
      this.showAutoPageTurnSettings = false;
      this.handleMenusVisibilityChange();
      if (afterClose === null) {
        this.scheduleFullscreenRestore('auto_page_turn_settings_closed', 80);
      } else {
        afterClose();
      }
    };

    const ctx = this.uiContext;
    if (!ctx) {
      this.resetAutoPageTurnSettingsAnimationState();
      finish();
      return;
    }
    ctx.animateTo({
      duration: 170,
      curve: Curve.EaseIn,
      onFinish: () => {
        finish();
      }
    }, () => {
      this.resetAutoPageTurnSettingsAnimationState();
    });
  }

  private openQuickSettings(): void {
    if (this.showQuickSettings) {
      return;
    }
    if (this.showPageTurnAnimationSettings) {
      this.hidePageTurnAnimationSettingsWithAnimation(() => {
        this.openQuickSettings();
      });
      return;
    }
    if (this.showAutoPageTurnSettings) {
      this.hideAutoPageTurnSettingsWithAnimation(() => {
        this.openQuickSettings();
      });
      return;
    }
    this.openQuickSettingsWithAnimation();
  }

  private openTextSettings(): void {
    if (this.showQuickSettings) {
      this.hideQuickSettingsWithAnimation(() => {
        this.openTextSettings();
      });
      return;
    }
    if (this.showPageTurnAnimationSettings) {
      this.hidePageTurnAnimationSettingsWithAnimation(() => {
        this.openTextSettings();
      });
      return;
    }
    if (this.showAutoPageTurnSettings) {
      this.hideAutoPageTurnSettingsWithAnimation(() => {
        this.openTextSettings();
      });
      return;
    }
    this.showQuickSettings = false;
    this.showChapterList = false;
    this.showPageTurnAnimationSettings = false;
    this.showAutoPageTurnSettings = false;
    this.showInteractionOverlay = false;
    this.showSettingsPanel = true;
    this.handleMenusVisibilityChange();
  }

  private openPageTurnAnimationSettings(): void {
    if (this.showPageTurnAnimationSettings) {
      return;
    }
    if (this.showQuickSettings) {
      this.hideQuickSettingsWithAnimation(() => {
        this.openPageTurnAnimationSettings();
      });
      return;
    }
    if (this.showAutoPageTurnSettings) {
      this.hideAutoPageTurnSettingsWithAnimation(() => {
        this.openPageTurnAnimationSettings();
      });
      return;
    }
    this.openPageTurnAnimationSettingsWithAnimation();
  }

  private openAutoPageTurnSettings(): void {
    if (this.showAutoPageTurnSettings) {
      return;
    }
    if (this.showQuickSettings) {
      this.hideQuickSettingsWithAnimation(() => {
        this.openAutoPageTurnSettings();
      });
      return;
    }
    if (this.showPageTurnAnimationSettings) {
      this.hidePageTurnAnimationSettingsWithAnimation(() => {
        this.openAutoPageTurnSettings();
      });
      return;
    }
    this.openAutoPageTurnSettingsWithAnimation();
  }

  // ──── 标题辅助 ────

  private getBookTitle(): string {
    return this.ebook?.metadata.title ?? 'EPUB 阅读器';
  }

  private getCurrentChapterTitle(): string {
    if (this.spineItems.length === 0) {
      return '';
    }
    const ch = this.spineItems[this.currentSpineIndex];
    const t = (ch?.title ?? '').trim();
    return t.length > 0 ? t : `第 ${this.currentSpineIndex + 1} 章`;
  }

  // ──── Build ────

  @Builder
  private buildLoadingView() {
    Column() {
      LoadingProgress().width(48).height(48).color($r('app.color.accent_primary'))
      Text('正在加载 EPUB…')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 12 })
        .fontFamily(this.appFontFamily)
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(Color.Black)
  }

  @Builder
  private buildErrorView() {
    Column() {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
        .fontSize(48)
        .fontColor([$r('app.color.text_secondary')])
      Text(this.errorMessage)
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 12 })
        .fontFamily(this.appFontFamily)
        .padding({ left: 24, right: 24 })
        .textAlign(TextAlign.Center)
      if (this.canFallbackToReaderKit && isReaderKitEnabled()) {
        Button('使用 ReaderKit 打开')
          .fontFamily(this.appFontFamily)
          .margin({ top: 24 })
          .onClick(() => { this.openWithReaderKit(); })
      }
      Button('返回')
        .fontFamily(this.appFontFamily)
        .margin({ top: 12 })
        .buttonStyle(ButtonStyleMode.NORMAL)
        .onClick(() => { this.closeReaderRoute(); })
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(Color.Black)
  }

  @Builder
  private buildTopToolbar() {
    Row() {
      Button() {
        SymbolGlyph($r('sys.symbol.arrow_left'))
          .fontSize(22)
          .fontColor([this.getToolbarIconColor()])
      }
      .width(48).height(48)
      .backgroundColor(Color.Transparent)
      .onClick(() => { void this.goBack(); })

      Column() {
        Text(this.getBookTitle())
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontFamily(this.appFontFamily)
        if (this.getCurrentChapterTitle().length > 0) {
          Text(this.getCurrentChapterTitle())
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .fontFamily(this.appFontFamily)
            .margin({ top: 1 })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 8, right: 8 })

      Button() {
        SymbolGlyph(this.isCurrentPageBookmarked ? $r('sys.symbol.bookmark_fill') : $r('sys.symbol.bookmark'))
          .fontSize(20)
          .fontColor([this.isCurrentPageBookmarked ? $r('app.color.accent_primary') : this.getToolbarIconColor()])
      }
      .width(48)
      .height(48)
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        this.addCurrentEpubBookmark();
      })
    }
    .width('100%')
    .height(this.getReaderTopToolbarHeight())
    .padding({ left: 4, right: 8, top: this.getReaderToolbarTopInset() })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.themeManager.getGlassBackgroundResource())
    .backgroundBlurStyle(this.themeManager.getGlassBlurStyle())
    .shadow({ radius: 8, color: 'rgba(0,0,0,0.18)', offsetX: 0, offsetY: 4 })
    .opacity(this.toolbarOpacity)
  }

  @Builder
  private buildBottomToolbar() {
    Column() {
      // 进度条行
      Row() {
        Text(`${this.currentSpineIndex + 1}`)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width(36)
          .textAlign(TextAlign.Center)
          .fontFamily(this.appFontFamily)

        Slider({
          value: this.currentSpineIndex,
          min: 0,
          max: Math.max(0, this.spineItems.length - 1),
          step: 1
        })
          .layoutWeight(1)
          .trackColor($r('app.color.divider_primary'))
          .selectedColor($r('app.color.accent_primary'))
          .onChange((value: number) => {
            const idx = Math.round(value);
            if (idx !== this.currentSpineIndex) {
              this.loadSpineItem(idx, 0);
            }
          })

        Text(`${this.spineItems.length}`)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width(36)
          .textAlign(TextAlign.Center)
          .fontFamily(this.appFontFamily)
      }
      .width('100%')
      .padding({ left: 8, right: 8 })

      // 页内进度（仅在多页时显示）
      if (this.totalPagesInSpine > 1) {
        Column() {
          Text(`本章 ${this.currentPageWithinSpine + 1} / ${this.totalPagesInSpine} 页`)
            .fontSize(11)
            .fontColor($r('app.color.text_muted'))
            .margin({ bottom: 4 })
            .fontFamily(this.appFontFamily)

          Row() {
            Text('1')
              .fontSize(10)
              .fontColor($r('app.color.text_muted'))
              .width(24)
              .textAlign(TextAlign.Center)
              .fontFamily(this.appFontFamily)

            Slider({
              value: this.currentPageWithinSpine,
              min: 0,
              max: Math.max(0, this.totalPagesInSpine - 1),
              step: 1
            })
              .layoutWeight(1)
              .trackColor($r('app.color.divider_primary'))
              .selectedColor($r('app.color.accent_primary'))
              .onChange((value: number) => {
                const nextPage = Math.round(value);
                if (nextPage !== this.currentPageWithinSpine) {
                  this.jumpToCurrentSpinePage(nextPage);
                }
              })

            Text(`${this.totalPagesInSpine}`)
              .fontSize(10)
              .fontColor($r('app.color.text_muted'))
              .width(24)
              .textAlign(TextAlign.Center)
              .fontFamily(this.appFontFamily)
          }
          .width('100%')
          .padding({ left: 8, right: 8 })
        }
        .width('100%')
        .margin({ bottom: 4 })
      }

      // 功能按钮行
      Row() {
        Button() {
          SymbolGlyph($r('sys.symbol.list_bullet'))
            .fontSize(22)
            .fontColor([this.getToolbarIconColor()])
        }
        .width(48).height(48).backgroundColor(Color.Transparent)
        .onClick(() => {
          this.openChapterList();
        })

        Blank()

        Button() {
          SymbolGlyph($r('sys.symbol.gearshape'))
            .fontSize(22)
            .fontColor([this.getToolbarIconColor()])
        }
        .width(48).height(48).backgroundColor(Color.Transparent)
        .onClick(() => {
          this.openQuickSettings();
        })

        Blank()

        Button() {
          SymbolGlyph($r('sys.symbol.page_turning'))
            .fontSize(22)
            .fontColor([this.getToolbarIconColor()])
        }
        .width(48).height(48).backgroundColor(Color.Transparent)
        .onClick(() => {
          this.openPageTurnAnimationSettings();
        })

        Blank()

        Button() {
          SymbolGlyph($r('sys.symbol.eye'))
            .fontSize(22)
            .fontColor([this.getToolbarIconColor()])
        }
        .width(48).height(48).backgroundColor(Color.Transparent)
        .onClick(() => {
          this.openTextSettings();
        })

        Blank()

        Row() {
          Row() {
            SymbolGlyph(this.readAloudPlaying ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'))
              .fontSize(18)
              .fontColor([this.readAloudPlaying ? Color.White : this.getToolbarIconColor()])
          }
          .width(48)
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.toggleReadAloudFromToolbar();
          })

          Column()
            .width(1)
            .height(16)
            .backgroundColor(this.readAloudPlaying ? '#66FFFFFF' : $r('app.color.divider_primary'))

          Row() {
            SymbolGlyph($r('sys.symbol.gearshape'))
              .fontSize(16)
              .fontColor([this.readAloudPlaying ? Color.White : this.getToolbarIconColor()])
          }
          .width(44)
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.openReadAloudSettingsPanelFromToolbar();
          })
        }
        .height(36)
        .backgroundColor(this.readAloudPlaying ? '#1A1890FF' : $r('app.color.background_secondary'))
        .borderRadius(18)
        .clip(true)

        Blank()

        Button() {
          SymbolGlyph(this.getAutoPageTurnIconResource())
            .fontSize(22)
            .fontColor([this.getToolbarIconColor(this.autoPageTurnEnabled)])
        }
        .width(48).height(48).backgroundColor(Color.Transparent)
        .onClick(() => {
          this.openAutoPageTurnSettings();
        })
      }
      .width('100%')
      .padding({ left: 8, right: 8, bottom: this.navigationBarHeight })
    }
    .width('100%')
    .backgroundColor(this.themeManager.getGlassBackgroundResource())
    .backgroundBlurStyle(this.themeManager.getGlassBlurStyle())
    .shadow({ radius: 8, color: 'rgba(0,0,0,0.18)', offsetX: 0, offsetY: -2 })
    .opacity(this.toolbarOpacity)
  }

  @Builder
  private buildBottomInfoBar() {
    Row() {
      Row() {
        if (this.readingSettings.showBattery ?? false) {
          Row({ space: 6 }) {
            Stack({ alignContent: Alignment.Start }) {
              Row()
                .width(22)
                .height(11)
                .borderRadius(3)
                .border({ width: 1.5, color: this.getBottomInfoBarTextColor() })
                .opacity(0.52)
              Row()
                .width(Math.max(2, 17 * this.batteryLevel / 100))
                .height(7)
                .borderRadius(1.5)
                .position({ x: 2, y: 2 })
                .linearGradient({
                  angle: 90,
                  colors: this.batteryLevel > 20
                    ? [[this.getBatteryColor(this.batteryLevel), 0], [this.getBatteryColorEnd(this.batteryLevel), 1]]
                    : [['#FF4444', 0], ['#FF6666', 1]]
                })
              Row()
                .width(2.5)
                .height(5)
                .backgroundColor(this.getBottomInfoBarTextColor())
                .opacity(0.52)
                .borderRadius({ topRight: 1, bottomRight: 1 })
                .position({ x: 22, y: 3 })
            }
            .width(26)
            .height(11)

            Text(`${this.batteryLevel}%`)
              .fontSize(11)
              .fontColor(this.getBottomInfoBarTextColor())
              .opacity(0.6)
              .fontWeight(FontWeight.Medium)
              .fontFamily(this.appFontFamily)
          }
        }
      }
      .width(84)
      .justifyContent(FlexAlign.Start)

      Row() {
        if (this.readingSettings.showTime !== false) {
          Text(this.currentTime)
            .fontSize(12)
            .fontColor(this.getBottomInfoBarTextColor())
            .opacity(0.6)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
        }
      }
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)

      Row({ space: 8 }) {
        if (this.readingSettings.showPageNumber !== false) {
          Text(`${Math.max(1, this.currentPageWithinSpine + 1)} / ${Math.max(1, this.totalPagesInSpine)}`)
            .fontSize(12)
            .fontColor(this.getBottomInfoBarTextColor())
            .opacity(0.6)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
        }
        if (this.readingSettings.showProgress ?? false) {
          Text(`${this.getReadingProgressPercent()}%`)
            .fontSize(12)
            .fontColor(this.getBottomInfoBarTextColor())
            .opacity(0.6)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
        }
      }
      .width(148)
      .justifyContent(FlexAlign.End)
    }
    .width('100%')
    .padding({
      left: this.getBottomInfoBarSidePadding(),
      right: this.getBottomInfoBarSidePadding(),
      bottom: this.getBottomInfoBarBottomPadding()
    })
    .position({ x: 0, y: '100%' })
    .translate({ y: '-100%' })
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private buildAnimButton(label: string, type: PageTurnAnimationType) {
    Column() {
      Text(label)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(this.getDisplayedPageTurnAnimationType() === type ?
          $r('app.color.accent_primary') : $r('app.color.text_secondary'))
    }
    .width('31%')
    .padding(10)
    .backgroundColor(this.getDisplayedPageTurnAnimationType() === type ?
      $r('app.color.accent_background') : Color.Transparent)
    .borderRadius(8)
    .onClick(() => {
      const nextSettings = this.clonePageReadingSettings(this.pageReadingSettings);
      nextSettings.pageTurnAnimation = type;
      this.applyPageReadingSettings(nextSettings, 'page_turn_animation_select');
    })
  }

  private getDisplayedPageTurnAnimationType(): PageTurnAnimationType {
    return this.pageReadingSettings.pageTurnAnimation;
  }

  @Builder
  private buildPageTurnAnimationOptions() {
    Column() {
      Text('选择翻页动画')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .margin({ bottom: 8 })
        .fontFamily(this.appFontFamily)

      Text('卷页仅在横向分页/双页等可截图页面中启用，上下翻页会自动降级为覆盖动画')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .margin({ bottom: 12 })
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
      .margin({ bottom: 8 })

      Row() {
        this.buildAnimButton('卷页', PageTurnAnimationType.CURL)
        Column().width('31%')
        Column().width('31%')
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('100%')
  }

  @Builder
  private buildPageTurnAnimationSettings() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.background_overlay'))
        .opacity(this.pageTurnSettingsBackdropOpacity)
        .onClick(() => {
          this.hidePageTurnAnimationSettingsWithAnimation(null);
        })

      if (this.isLandscapeMode) {
        Row() {
          Column()
            .layoutWeight(1)
            .height('100%')
            .onClick(() => {
              this.hidePageTurnAnimationSettingsWithAnimation(null);
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
                SymbolGlyph($r('sys.symbol.xmark'))
                  .fontSize(18)
                  .fontColor([$r('app.color.text_secondary')])
              }
              .width(36)
              .height(36)
              .backgroundColor(Color.Transparent)
              .onClick(() => {
                this.hidePageTurnAnimationSettingsWithAnimation(null);
              })
            }
            .width('100%')
            .margin({ bottom: 16 })

            Scroll() {
              this.buildPageTurnAnimationOptions()
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
          .opacity(this.pageTurnSettingsPanelOpacity)
          .translate({ x: this.pageTurnSettingsPanelTranslateX })
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
              SymbolGlyph($r('sys.symbol.xmark'))
                .fontSize(18)
                .fontColor([$r('app.color.text_secondary')])
            }
            .width(36)
            .height(36)
            .backgroundColor(Color.Transparent)
            .onClick(() => {
              this.hidePageTurnAnimationSettingsWithAnimation(null);
            })
          }
          .width('100%')
          .margin({ bottom: 16 })

          this.buildPageTurnAnimationOptions()
        }
        .width('90%')
        .constraintSize({ maxWidth: 400 })
        .padding(20)
        .backgroundColor(this.themeManager.getGlassBackgroundResource())
        .backgroundBlurStyle(this.themeManager.getGlassBlurStyle())
        .borderRadius(16)
        .opacity(this.pageTurnSettingsPanelOpacity)
        .scale({ x: this.pageTurnSettingsPanelScale, y: this.pageTurnSettingsPanelScale })
        .translate({ y: this.pageTurnSettingsPanelTranslateY })
      }
    }
    .width('100%')
    .height('100%')
    .zIndex(240)
  }

  @Builder
  private buildAutoPageTurnSettings() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.background_overlay'))
        .opacity(this.autoPageTurnSettingsBackdropOpacity)
        .onClick(() => {
          this.hideAutoPageTurnSettingsWithAnimation(null);
        })

      if (this.isLandscapeMode) {
        Row() {
          Column()
            .layoutWeight(1)
            .height('100%')
            .onClick(() => {
              this.hideAutoPageTurnSettingsWithAnimation(null);
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
                SymbolGlyph($r('sys.symbol.xmark'))
                  .fontSize(18)
                  .fontColor([$r('app.color.text_secondary')])
              }
              .width(36)
              .height(36)
              .backgroundColor(Color.Transparent)
              .onClick(() => {
                this.hideAutoPageTurnSettingsWithAnimation(null);
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
                .fontColor($r('app.color.accent_primary'))
                .width(50)
                .fontFamily(this.appFontFamily)

              Slider({
                value: this.autoPageTurnIntervalSeconds,
                min: 1,
                max: 30,
                step: 1
              })
                .layoutWeight(1)
                .trackColor($r('app.color.divider_primary'))
                .selectedColor($r('app.color.accent_primary'))
                .onChange((value: number) => {
                  this.setAutoPageTurnIntervalSeconds(value);
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
                .selectedColor($r('app.color.accent_primary'))
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
          .opacity(this.autoPageTurnSettingsPanelOpacity)
          .translate({ x: this.autoPageTurnSettingsPanelTranslateX })
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
              SymbolGlyph($r('sys.symbol.xmark'))
                .fontSize(18)
                .fontColor([$r('app.color.text_secondary')])
            }
            .width(36)
            .height(36)
            .backgroundColor(Color.Transparent)
            .onClick(() => {
              this.hideAutoPageTurnSettingsWithAnimation(null);
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
              .fontColor($r('app.color.accent_primary'))
              .width(50)
              .fontFamily(this.appFontFamily)

            Slider({
              value: this.autoPageTurnIntervalSeconds,
              min: 1,
              max: 30,
              step: 1
            })
              .layoutWeight(1)
              .trackColor($r('app.color.divider_primary'))
              .selectedColor($r('app.color.accent_primary'))
              .onChange((value: number) => {
                this.setAutoPageTurnIntervalSeconds(value);
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
              .selectedColor($r('app.color.accent_primary'))
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
        .opacity(this.autoPageTurnSettingsPanelOpacity)
        .scale({ x: this.autoPageTurnSettingsPanelScale, y: this.autoPageTurnSettingsPanelScale })
        .translate({ y: this.autoPageTurnSettingsPanelTranslateY })
      }
    }
    .width('100%')
    .height('100%')
    .zIndex(240)
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        // ── 内容层 ──
        if (this.isLoading) {
          this.buildLoadingView()
        } else if (this.errorMessage.trim().length > 0) {
          this.buildErrorView()
        } else {
          Column() {
            EpubWebViewReaderComponent({
              params: {
                initialSpineFilePath: this.resolveSpinePath(this.currentSpineIndex),
                initialPageOffset: this.currentPageWithinSpine,
                initialAnchorFragment: this.currentAnchorFragment,
                contentSafeTopInset: this.getReaderContentTopInset(),
                textSettings: this.readingSettings,
                pageSettings: this.pageReadingSettings,
                isFixedLayout: this.isFixedLayout,
                spineLayoutType: this.getSpineLayoutType(this.currentSpineIndex),
                spineMediaType: this.getSpineMediaType(this.currentSpineIndex),
                callbacks: {
                  onPageChange: (page: number, totalPages: number, source?: EpubWebPageChangeSource) => {
                    let spineChanged = false;
                    if (this.pendingSpineIndex >= 0) {
                      spineChanged = this.currentSpineIndex !== this.pendingSpineIndex;
                      this.currentSpineIndex = this.pendingSpineIndex;
                      this.pendingSpineIndex = -1;
                    }
                    const isReadAloudFollow = source === EpubWebPageChangeSource.READ_ALOUD_FOLLOW && !spineChanged;
                    this.currentPageWithinSpine = page;
                    this.totalPagesInSpine = totalPages;
                    if (this.currentAnchorFragment.length > 0) {
                      this.currentAnchorFragment = '';
                    }
                    this.recordEpubReadFlowEvent(
                      EpubReadFlowEventType.PAGINATION_CHANGED,
                      isReadAloudFollow ? 'read_aloud_follow' : 'page_change',
                      0,
                      true,
                      `page=${page + 1}/${totalPages}, spineChanged=${spineChanged === true}`
                    );
                    this.syncAutoPageTurnState();
                    if (!isReadAloudFollow) {
                      this.readAloudController.updatePageIndex(page);
                    }
                    if (spineChanged) {
                      this.currentVisibleTextSnapshot = null;
                      this.currentSpineTextCache = '';
                      this.currentSpineTextCacheIndex = -1;
                      void this.refreshCurrentSpineHighlightRanges('spine_page_change');
                      void this.applyPurifyRulesToCurrentSpine('spine_page_change');
                    }
                    this.refreshCurrentEpubBookmarkState(isReadAloudFollow ? 'read_aloud_follow' : 'page_change');
                    if (isReadAloudFollow) {
                      logger.debug(TAG, `EPUB Web 听书跟随翻页: page=${page}/${totalPages}`);
                      return;
                    }
                    void this.updateEpubReadAloudContextByPosition();
                    void this.saveReadingProgress('page_change');
                  },
                  onSpineChangeRequested: (direction: 'prev' | 'next') => {
                    this.onSpineChangeRequested(direction);
                  },
                  onReady: (controller: EpubWebViewReaderController) => {
                    this.epubReaderController = controller;
                    this.syncAutoPageTurnState();
                    this.refreshCurrentEpubBookmarkState('webview_ready');
                    void this.applyPurifyRulesToCurrentSpine('webview_ready');
                    void this.updateEpubReadAloudContextByPosition();
                    this.syncReadAloudStateFromController();
                    this.notifyTransitionReaderReadyOnce('webview_layout_ready');
                    logger.info(TAG, 'EpubWebView 控制器就绪');
                  },
                  onError: (msg: string) => {
                    this.pendingSpineIndex = -1;
                    logger.warn(TAG, `WebView 错误: ${msg}`);
                    this.recordEpubReadFlowEvent(
                      EpubReadFlowEventType.WEBVIEW_ERROR,
                      'component_error',
                      0,
                      false,
                      msg
                    );
                    if (!this.hasNotifiedTransitionReaderReady) {
                      logger.warn(TAG, 'WebView 初始加载失败，取消翻开过渡遮罩');
                      this.markDetailOpenReaderReady('component_error_before_ready', false, msg);
                      cancelTransition();
                    }
                  },
                  onReaderTap: (xRatio: number, yRatio: number) => {
                    this.handleWebViewTap(xRatio, yRatio);
                  },
                  onReaderSwipe: (deltaX: number, deltaY: number) => {
                    this.handleReaderSwipeDelta(deltaX, deltaY);
                  },
                  onRuntimeBlankSpine: (info: EpubRuntimeBlankSpineInfo): boolean => {
                    return this.handleRuntimeBlankSpine(info);
                  },
                  onAddPurifyRule: (pattern: string) => {
                    void this.addPurifyRule(pattern);
                  },
                  onStartReadAloudFromCharIndex: (charIndex: number) => {
                    this.onStartReadAloudFromCharIndex(charIndex);
                  },
                  onAddHighlight: (snapshot: EpubWebSelectionSnapshot) => {
                    this.onAddEpubHighlight(snapshot);
                  },
                  onAddHighlightWithThought: (snapshot: EpubWebSelectionSnapshot) => {
                    this.onAddEpubHighlightWithThought(snapshot);
                  },
                  onUpdateHighlightStyle: (highlightId: string, lineType: HighlightLineType, color: string) => {
                    this.onUpdateEpubHighlightStyle(highlightId, lineType, color);
                  },
                  onUpdateHighlightThought: (highlightId: string, thoughtText: string) => {
                    this.onUpdateEpubHighlightThought(highlightId, thoughtText);
                  },
                  onFlowEvent: (event: EpubWebComponentFlowEvent) => {
                    this.handleEpubComponentFlowEvent(event);
                  }
                }
              } as EpubWebViewReaderParams,
              enableEpubAnnotations: true,
              epubHighlightRanges: this.currentSpineHighlightRanges
            })
              .id(`epub_webview_reader_component_${this.readerMountEpoch}`)
              .width('100%')
              .height('100%')
          }
          .width('100%')
          .height('100%')
          .onAreaChange((_oldArea: Area, newArea: Area) => {
            const widthVp = Number(newArea.width);
            const heightVp = Number(newArea.height);
            if (widthVp > 0 && heightVp > 0) {
              const widthChanged = Math.abs(widthVp - this.componentWidth) > 1;
              const heightChanged = Math.abs(heightVp - this.componentHeight) > 1;
              this.componentWidth = widthVp;
              this.componentHeight = heightVp;
              this.isLandscapeMode = widthVp > heightVp;
              if (widthChanged || heightChanged) {
                const normalizedSettings = this.normalizePageReadingSettings(this.pageReadingSettings);
                if (!this.arePageReadingSettingsEqual(normalizedSettings, this.pageReadingSettings)) {
                  this.pageReadingSettings = this.clonePageReadingSettings(normalizedSettings);
                  this.autoPageTurnEnabled = normalizedSettings.autoPageTurnInterval > 0;
                  if (this.autoPageTurnEnabled) {
                    this.autoPageTurnIntervalSeconds = normalizedSettings.autoPageTurnInterval;
                  }
                  void this.persistPageReadingSettings('component_area_change');
                }
                this.epubReaderController?.applyPageSettings(normalizedSettings);
              }
            }
          })
        }

        // ── 手势截取层 ──
        if (!this.isLoading && this.errorMessage.trim().length === 0 && this.shouldUseGestureOverlay()) {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor(Color.Transparent)
            .hitTestBehavior(HitTestMode.Block)
            .onClick((event: ClickEvent) => { this.handlePageTap(event); })
            .gesture(
              PanGesture({ direction: PanDirection.All, distance: 5 })
                .onActionStart((event: GestureEvent) => {
                  this.handleReaderPanStart(event);
                })
                .onActionUpdate((event: GestureEvent) => {
                  this.handleReaderPanUpdate(event);
                })
                .onActionEnd((event: GestureEvent) => {
                  this.handleReaderPanEnd(event);
                })
            )
        }

        if (!this.isLoading &&
          this.errorMessage.trim().length === 0 &&
          this.shouldShowBottomInfoBar() &&
          !this.shouldHideBottomInfoBar()) {
          Column() {
            this.buildBottomInfoBar()
          }
          .width('100%')
          .height('100%')
          .zIndex(36)
          .hitTestBehavior(HitTestMode.None)
        }

        // ── 顶部工具栏 ──
        if (this.showTopToolbar) {
          Column() {
            this.buildTopToolbar()
          }
          .width('100%')
          .align(Alignment.TopStart)
          .position({ x: 0, y: 0 })
          .zIndex(100)
        }

        // ── 底部工具栏 ──
        if (this.showBottomToolbar) {
          Column() {
            this.buildBottomToolbar()
          }
          .width('100%')
          .position({ x: 0, y: '100%' })
          .translate({ x: 0, y: '-100%' })
          .zIndex(100)
        }

        // ── 快捷设置面板 ──
        if (this.showQuickSettings) {
          MangaQuickSettings({
            readingSettings: this.pageReadingSettings,
            isVisible: this.showQuickSettings,
            hideContinuousScrollMode: true,
            callbacks: {
              onSettingsChange: (settings: MangaReadingSettings) => {
                this.applyPageReadingSettings(settings, 'quick_settings_change', true);
              },
              onClose: () => {
                this.hideQuickSettingsWithAnimation(null);
              },
              onOpenFullSettings: () => {
                this.hideQuickSettingsWithAnimation(() => {
                  this.openTextSettings();
                });
              }
            }
          })
          .opacity(this.quickSettingsOpacity)
          .scale({ x: this.quickSettingsScale, y: this.quickSettingsScale })
          .translate({ y: this.quickSettingsTranslateY })
          .zIndex(210)
        }

        // ── 文字/主题设置面板 ──
        if (this.showSettingsPanel) {
          EpubReaderSettingsPanel({
            settings: this.readingSettings,
            pageSettings: this.pageReadingSettings,
            isVisible: this.showSettingsPanel,
            callbacks: {
              onSettingsChange: (newSettings: EBookReadingSettings) => {
                const mergedSettings = this.mergeTextReadingSettings(newSettings);
                this.readingSettings = this.cloneTextReadingSettings(mergedSettings);
                if (this.ebook) {
                  this.ebook.readingSettings = this.cloneTextReadingSettings(mergedSettings);
                }
                this.epubReaderController?.applyReadingSettings(mergedSettings);
                this.syncDeviceOrientationLock('text_settings_change');
                const bookId = this.ebook?.id ?? '';
                if (bookId.length > 0) {
                  this.queueTextReadingSettingsSave('settings_change');
                }
              },
              onPageSettingsChange: (newSettings: MangaReadingSettings) => {
                this.applyPageReadingSettings(newSettings, 'full_settings_change', true);
              },
              onClose: () => {
                this.showSettingsPanel = false;
                this.handleMenusVisibilityChange();
                this.scheduleFullscreenRestore('settings_closed', 80);
              }
            } as EpubSettingsPanelCallbacks
          })
          .zIndex(220)
        }

        // ── 章节列表（自带遮罩与动画）──
        if (this.showChapterList) {
          EpubReaderChapterList({
            chapters: this.navigationChapters,
            currentIndex: this.getCurrentNavigationIndex(),
            isVisible: this.showChapterList,
            callbacks: {
              onChapterSelect: (navigationIndex: number) => {
                this.navigateToNavigationIndex(navigationIndex);
                this.showChapterList = false;
                this.handleMenusVisibilityChange();
              },
              onClose: () => {
                this.showChapterList = false;
                this.handleMenusVisibilityChange();
                this.scheduleFullscreenRestore('chapter_list_closed', 80);
              }
            } as EpubChapterListCallbacks
          })
          .zIndex(220)
        }

        if (this.showPageTurnAnimationSettings) {
          this.buildPageTurnAnimationSettings()
        }

        if (this.showAutoPageTurnSettings) {
          this.buildAutoPageTurnSettings()
        }

        if (this.showReadAloudPanel) {
          ReadAloudSettingsInfoPanel({
            isLandscape: this.isLandscapeMode,
            settings: this.readAloudPanelSettings,
            availability: this.readAloudAvailability,
            voiceOptions: this.readAloudVoiceOptions,
            statusMessage: this.readAloudStatusMessage,
            appFontFamily: this.appFontFamily,
            callbacks: {
              onClose: () => {
                this.lastReadAloudPanelCloseTime = Date.now();
                this.showReadAloudPanel = false;
                this.handleMenusVisibilityChange();
                this.scheduleFullscreenRestore('read_aloud_panel_closed', 80);
              },
              onRefresh: () => {
                this.refreshReadAloudAvailability();
              },
              onChange: (partial: Partial<ReadAloudSettings>) => {
                this.updateReadAloudSettings(partial);
              }
            }
          })
            .zIndex(220)
        }

        if (this.showInteractionOverlay) {
          MangaInteractionOverlay({
            params: {
              readingMode: this.pageReadingSettings.readingMode,
              readingDirection: this.pageReadingSettings.readingDirection,
              componentWidth: this.getEffectiveComponentWidth(),
              componentHeight: this.getEffectiveComponentHeight(),
              deviceOrientation: this.getDeviceOrientation(),
              statusBarHeight: this.statusBarHeight,
              navigationBarHeight: this.navigationBarHeight,
              onDismiss: () => {
                this.showInteractionOverlay = false;
                this.handleMenusVisibilityChange();
              }
            }
          })
          .zIndex(230)
        }
      }
      .width('100%')
      .height('100%')
      .id('epub_webview_reader_root')
      .backgroundColor(Color.Black)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
      .focusable(true)
      .defaultFocus(true)
      .onKeyEvent((event: KeyEvent) => {
        if (event.type === KeyType.Up) {
          if (this.handleVolumeKey(event.keyCode)) {
            event.stopPropagation();
          }
        }
      })
    }
    .hideTitleBar(true)
    .onBackPressed(() => {
      if (this.areMenusVisible()) {
        this.closeTransientPanels();
        return true;
      }
      void this.goBack();
      return true;
    })
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
      this.uiContext = this.getUIContext();
      PageWindowCoordinator.applyPagePolicy('EpubWebViewReaderPage', this.uiContext);
      WindowManager.setDisplayMode(DisplayMode.FULL_IMMERSIVE, this.uiContext);
      const params = ctx.pathInfo.param as EBookReaderParams;
      if (params?.bookId) {
        void this.initializeWithParams(params);
      } else {
        this.errorMessage = '缺少书籍参数';
        this.isLoading = false;
      }
    })
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
  }
}
