import { SafeUtils } from '../Utils/SafeUtils';
/**
 * 小说阅读器页面
 * 使用 TextReaderComponent 实现专业的文本阅读体验
 * 支持翻页动画、自定义背景、字体设置等
 * 采用与电子书阅读器一致的沉浸式设计风格
 * 
 * 文件路径: entry/src/main/ets/pages/NovelReaderPage.ets
  */

import { logger } from '../Utils/Logger';
import { ReaderSafeAreaUtils } from '../Utils/ReaderSafeAreaUtils';
import { getNovelSourceManager } from '../Framework/Novel/NovelSourceManager';
import { getNovelDataManager } from '../Framework/Novel/NovelDataManager';
import { getNovelChapterCacheManager } from '../Framework/Novel/NovelChapterCacheManager';
import { getNovelContentProcessor, ContentProcessConfig } from '../Framework/Novel/NovelContentProcessor';
import { ReplaceScope, NovelReplaceRuleManager, AddRuleParams } from '../Framework/Novel/NovelReplaceRuleManager';
import { LegadoChapter, LegadoBook, LegadoBookSourceType } from '../Framework/Novel/LegadoSourceTypes';
import { NovelReaderPageParams } from './NovelBookshelfPage';
import { NovelBook, NovelReadStatus } from '../Models/NovelModels';
import { TextReaderComponent, PaginationMode, TextReaderHighlightRange } from '../components/TextReaderComponent';
import { TextFontSettingsPanel } from '../components/TextFontSettingsPanel';
import { TextBackgroundSettingsPanel } from '../components/TextBackgroundSettingsPanel';
import { TextReadingSettingsPanel2 } from '../components/TextReadingSettingsPanel2';
import { TextReaderInteractionOverlay } from '../components/TextReaderInteractionOverlay';
import { 
  TextReaderSettings, 
  DEFAULT_TEXT_READER_SETTINGS,
  DEFAULT_TEXT_STYLE,
  TextChapter,
  TextChapterSwitchIntent,
  TextReadingMode,
  TextReadingDirection,
  BackgroundType,
  PageMargins,
  TextAlignment,
  SavedBackgroundImage,
  normalizeReadAloudSettings,
  clampTextReaderFontSize
} from '../Models/TextReaderModels';
import { NovelReadProgress } from '../Models/NovelModels';
import { UnifiedContentType } from '../Models/UnifiedContentModels';
import {
  AnnotationAnchor,
  HighlightLineType,
  HighlightStyle,
  UnifiedAnnotationType,
  UnifiedAnnotationRecord,
  CreateThoughtInput
} from '../Models/AnnotationModels';
import { SettingsManager, SettingKeys } from '../Framework/Managers/SettingsManager';
import { getNovelSettingsManager, BrowseHistoryInput } from '../Framework/Novel/NovelSettingsManager';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';
import { PageLifecycleManager } from '../Framework/Lifecycle';
import { WindowManager, DisplayMode } from '../Utils/WindowManager';
import { ReaderOrientationLockHelper } from '../Utils/ReaderOrientationLockHelper';
import { PageWindowCoordinator } from '../Utils/PageWindowCoordinator';
import { curves, promptAction } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { setReaderReady, setReaderLoadingProgress, startBookCloseTransitionWithComponentId, CoverPosition, cancelTransition } from '../components/BookTransitionOverlay';
import { NovelDictRuleManager, DictRule } from '../Framework/Novel/NovelDictRuleManager';
import { ReadAloudController } from '../Framework/ReadAloud/ReadAloudController';
import { ReadAloudPlaybackState } from '../Framework/ReadAloud/ReadAloudTypes';
import { eventBus, GameEvent, IEventPayload, ReadAloudStatePayload } from '../Framework/EventBus';
import { getUnifiedAnnotationManager } from '../Framework/Annotations/UnifiedAnnotationManager';
import { AnnotationCenterPageParams } from './AnnotationCenterPage';
import { EBook, EBookReadingProgress } from '../Models/EBookModels';
import { EBookDataManager } from '../Framework/Data/EBookDataManager';
import {
  buildLocalTextNovelBookId,
  buildTextReaderSettingsFromEBookSettings,
  hasCustomLocalTextNovelReadingSettings,
  isLocalTxtNovelReaderSource,
  syncTextReaderSettingsToEBookSettings
} from '../Framework/Adapters/LocalTextNovelAdapter';
import { AppGuideOverlay, GuideHighlightRect } from '../Framework/Components/AppGuideOverlay';
import { resolveGuideHighlightRectInRoot } from '../Framework/Components/AppGuideSupport';
import { AppGuideManager, AppGuidePageId, AppGuideStep } from '../Framework/Managers/AppGuideManager';
import { READER_ABILITY_HOST_MULTITON } from '../Framework/Reader/MangaReaderAbilityConstants';

const TAG = 'NovelReaderPage';
const NOVEL_SETTINGS_STORE = 'novel_settings';
const NOVEL_BOOK_RULE_SETTINGS_STORE = 'novel_book_rule_settings';
const NOVEL_BOOK_REPLACE_RULE_IDS_PREFIX = 'book_replace_rule_ids_';
const NOVEL_DEFAULT_PRELOAD_CHAPTERS = 50;
const MAX_PREPARSED_CHAPTER_CACHE = 12;
const NOVEL_SETTING_ENABLE_REPLACE_RULES = 'enableNovelReplaceRules';

interface HighlightOffsetRange {
  start: number;
  end: number;
}

interface LocalTextDomPosition {
  pageIndex: number;
  charIndex: number;
  chapterIndex: number;
}

interface PreparedTextChapter {
  content: string;
  wordCount: number;
}

@Component
export struct NovelReaderPage {
  private static readonly READ_ALOUD_RESUME_KEY_PREFIX: string = 'novel_read_aloud_resume_char_';
  private static readonly TOOLBAR_AUTO_HIDE_DELAY_MS: number = 2200;
  private static readonly GUIDE_LAYOUT_STABILIZE_DELAY_MS: number = 140;
  private static readonly INTERACTION_HINT_READER_SCOPE: string = 'novel';
  private static hasShownInteractionHint: boolean = false;
  private static lastShownInteractionHintKey: string = '';

  @State pathStack: NavPathStack = new NavPathStack();
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @State private appGuideStep: AppGuideStep | null = null;
  @State private appGuideHighlightRect: GuideHighlightRect | null = null;
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @StorageProp('isInBackground') @Watch('onAppBackgroundStateChanged') appInBackground: boolean = false;
  private lifecycle = new PageLifecycleManager('NovelReaderPage', { enableDebug: true });
  private componentId: string = 'NovelReaderPage';
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private appGuideManager: AppGuideManager = AppGuideManager.getInstance();

  // 内容状态
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;

  // 内容状态
  @State content: string = '';
  @State chapterTitle: string = '';
  @State isLoading: boolean = true;
  @State settings: TextReaderSettings = DEFAULT_TEXT_READER_SETTINGS;
  @State currentChapterIndex: number = 0;
  @State totalChapters: number = 0;
  @State currentPageIndex: number = 0;
  @State chapters: TextChapter[] = [];
  @State readAloudPlaying: boolean = false;
  @State readAloudCurrentCharIndex: number = -1;
  @State currentPageStartCharIndex: number = 0;
  @State currentPageEndCharIndex: number = 0;
  @State overallReadProgressPercent: number = 0;
  @State currentChapterHighlightRanges: TextReaderHighlightRange[] = [];
  @State isCurrentPageBookmarked: boolean = false;
  @State currentPageBookmarkId: string = '';
  private previousDisplayMode: DisplayMode = DisplayMode.DEFAULT;
  private isPageVisible: boolean = false;
  private sourceCoverComponentId: string = '';
  private readerHostMode: string = '';
  private readerInstanceId: string = '';
  private hasNotifiedTransitionReaderReady: boolean = false;
  private isCloseTransitionNavigating: boolean = false;

  // 3个独立设置面板
  @State showTopToolbar: boolean = false;
  @State showBottomToolbar: boolean = false;
  @State toolbarOpacity: number = 0.0;
  @State showInteractionOverlay: boolean = false;
  @State showChapterList: boolean = false;
  // 动画状态
  @State showFontSettings: boolean = false;
  @State showBackgroundSettings: boolean = false;
  @State showReadingSettings: boolean = false;
  @State openReadAloudInfoWhenOpenReadingSettings: boolean = false;

  // 组件重建控制（用于双页模式切换时强制重新加载组件）
  @State chapterListOpacity: number = 0;
  
  // 百科搜索对话框状态
  @State readerKey: number = 0;
  // 百科搜索对话框状态
  private lastReadingMode: TextReadingMode = TextReadingMode.PAGE;
  private pendingInteractionHintKey: string = '';
  
  // 章节列表滚动控制器
  @State showEncyclopediaDialog: boolean = false;
  @State encyclopediaKeyword: string = '';
  @State encyclopediaUrl: string = '';
  @State private readerViewportWidth: number = 0;
  @State private readerViewportHeight: number = 0;
  private toolbarAutoHideTimer: number = -1;
  private fullscreenRestoreTimer: number = -1;
  private interactionOverlayDismissTimer: number = -1;

  // 百科搜索WebView控制器
  private chapterListScroller: Scroller = new Scroller();
  // 百科搜索WebView控制器
  private encyclopediaWebController: webview.WebviewController = new webview.WebviewController();

  private sourceId: string = '';
  private bookUrl: string = '';
  private bookName: string = '';
  private author: string = '';
  private bookCoverUrl: string = '';
  private chapterUrl: string = '';
  private bookId: string = '';
  private chapterId: string = '';
  private localEbookId: string = '';
  private localEbook: EBook | null = null;
  private tocUrl: string = ''; // 目录URL
  private chapterList: LegadoChapter[] = [];// 完整章节列表
  private sourceManager = getNovelSourceManager();
  private dataManager = getNovelDataManager();
  private ebookDataManager: EBookDataManager = EBookDataManager.getInstance();
  private annotationManager = getUnifiedAnnotationManager();
  private cacheManager = getNovelChapterCacheManager();
  private settingsManager: SettingsManager = SettingsManager.getInstance();
  private readAloudController: ReadAloudController = ReadAloudController.getInstance();
  private readStartTime: number = 0;
  private lastSaveTime: number = 0;
  private lastProgressReadTime: number = 0;
  private pendingSettingsSnapshot: TextReaderSettings | null = null;
  private settingsSavePromise: Promise<void> | null = null;
  private uiContext: UIContext | null = null;
  private orientationLockToken: string = '';
  private saveProgressInterval: number = 30000;// 30秒自动保存
  private readAloudProgressSaveInterval: number = 4000;
  private readAloudUiSyncTimer: number = -1;
  private transitionLoadingProgress: number = 0;
  private currentChapterTotalPages: number = 0;
  private pendingSeekChapterIndex: number = -1;
  private pendingSeekChapterFraction: number = -1;
  private shouldAutoStartReadAloud: boolean = false;
  private shouldAutoOpenReadAloudPlayer: boolean = false;
  private lastReadAloudResumePersistTime: number = 0;
  private lastReadAloudProgressSaveTime: number = 0;
  private isReadProgressReady: boolean = false;
  private preloadSettingsLoaded: boolean = false;
  private preloadChapterCount: number = NOVEL_DEFAULT_PRELOAD_CHAPTERS;
  private preloadWhileReadingEnabled: boolean = true;
  private replaceRulesEnabled: boolean = true;
  private scopedReplaceRuleIds: string[] | null = null;
  private prefetchGeneration: number = 0;
  private preparsedChapterContent: Map<number, PreparedTextChapter> = new Map<number, PreparedTextChapter>();
  private prefetchingChapterIndexes: Set<number> = new Set<number>();

  private onReadAloudStateChanged: (payload: IEventPayload) => void = (payload: IEventPayload): void => {
    if (!this.bookId) {
      return;
    }
    const statePayload = payload as ReadAloudStatePayload;
    const payloadBookId = statePayload.bookId ?? '';
    if (!payloadBookId || payloadBookId !== this.bookId) {
      const controllerContext = this.readAloudController.getContextSnapshot();
      if (!controllerContext || controllerContext.bookId !== this.bookId) {
        return;
      }
    }
    if (!this.shouldHandleReadAloudUiEvents()) {
      return;
    }

    this.readAloudPlaying = statePayload.playbackState === ReadAloudPlaybackState.PLAYING;
    this.applyReadAloudProgress(statePayload);
    if (
      statePayload.playbackState === ReadAloudPlaybackState.PLAYING &&
      statePayload.reason === 'progress_updated'
    ) {
      const now = Date.now();
      if ((now - this.lastReadAloudProgressSaveTime) >= this.readAloudProgressSaveInterval) {
        this.lastReadAloudProgressSaveTime = now;
        this.lastSaveTime = now;
        this.saveReadProgress();
      }
    }
    if (
      statePayload.playbackState !== ReadAloudPlaybackState.PLAYING &&
      statePayload.reason !== 'progress_updated'
    ) {
      this.persistReadAloudResumeCharIndex(true);
      this.saveReadProgress();
    }
  };

  aboutToAppear(): void {
    // 初始化主题感知
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (theme: ThemeType) => {
      logger.info(TAG, `主题切换到: ${theme}`);
    });
    FontAwareHelper.initializeFontAware(
      this.componentId,
      this.fontState,
      (newState: FontAwareState) => {
        this.fontState = newState;
      }
    );
    this.readStartTime = Date.now();
    this.isPageVisible = true;
    eventBus.subscribe(GameEvent.READ_ALOUD_STATE_CHANGED, this.onReadAloudStateChanged);
    AppStorage.setOrCreate('ReadAloudCurrentHostPage', 'NovelReaderPage');
    this.syncReadAloudStateFromController();
    this.startReadAloudUiSyncTimer();
    this.readAloudController.refreshMediaSession();
    void this.refreshPageGuide('aboutToAppear');
  }

  aboutToDisappear(): void {
    this.isPageVisible = false;
    this.stopReadAloudUiSyncTimer();
    const isOpeningReadAloudPlayer = this.isReadAloudPlayerOpeningSoon();
    eventBus.unsubscribe(GameEvent.READ_ALOUD_STATE_CHANGED, this.onReadAloudStateChanged);
    this.clearToolbarAutoHideTimer();
    this.clearFullscreenRestoreTimer();
    this.hideInteractionOverlay();
    this.persistReadAloudResumeCharIndex(true);
    this.stopCrossChapterPrefetch(true);
    logger.lifecycle(TAG, 'aboutToDisappear - release resources');
    this.lifecycle.destroy();
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    FontAwareHelper.cleanupFontAware(this.componentId);
    // 离开页面时恢复自动旋转（防止双页模式强制横屏残留）
    this.saveReadProgress();
    // 关闭动画主动返回时，不要在这里中断过渡层
    if (isOpeningReadAloudPlayer) {
      logger.info(TAG, '小说阅读器即将进入听书独立页，aboutToDisappear 保留沉浸式与方向设置');
    } else {
      this.restoreNormalMode();
      this.orientationLockToken = ReaderOrientationLockHelper.release(
        this.orientationLockToken,
        this.uiContext ?? undefined
      );
      // 关闭动画主动返回时，不要在这里中断过渡层
      WindowManager.setPreferredOrientationAuto(this.uiContext ?? undefined);
    }
    // 关闭动画主动返回时，不要在这里中断过渡层
    // 关闭动画主动返回时，不要在这里中断过渡层
    if (!this.isCloseTransitionNavigating) {
      cancelTransition();
    } else {
      logger.info(TAG, '页面销毁：关闭动画进行中，跳过cancelTransition');
    }
  }

  onPageShow(): void {
    this.isPageVisible = true;
    this.setupFullscreenMode();
    this.scheduleFullscreenRestore('page_show');
    this.tryShowQueuedInteractionHint('page_show', 260);
    AppStorage.setOrCreate('ReadAloudCurrentHostPage', 'NovelReaderPage');
    this.syncReadAloudStateFromController();
    this.startReadAloudUiSyncTimer();
    this.updateReadAloudContextByPosition();
    this.refreshCurrentNovelBookmarkState('on_page_show');
    this.readAloudController.refreshMediaSession();
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

  private getInteractionHintKey(settings: TextReaderSettings = this.settings): string {
    const tapToTurnFlag = settings.tapToTurn ? '1' : '0';
    return `mode=${settings.readingMode}|direction=${settings.readingDirection}|tap=${tapToTurnFlag}`;
  }

  private getInteractionHintSeenSettingKey(hintKey: string): string {
    const encodedKey = encodeURIComponent(hintKey);
    return `${SettingKeys.TEXT_READER_INTERACTION_HINT_SEEN_PREFIX}${NovelReaderPage.INTERACTION_HINT_READER_SCOPE}_${encodedKey}`;
  }

  private hasSeenInteractionHint(hintKey: string): boolean {
    if (NovelReaderPage.hasShownInteractionHint && NovelReaderPage.lastShownInteractionHintKey === hintKey) {
      return true;
    }
    return this.settingsManager.getBoolean(this.getInteractionHintSeenSettingKey(hintKey), false);
  }

  private markInteractionHintSeen(hintKey: string): void {
    NovelReaderPage.lastShownInteractionHintKey = hintKey;
    NovelReaderPage.hasShownInteractionHint = true;
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

  private queueInteractionHintIfNeeded(settings: TextReaderSettings = this.settings): void {
    const nextKey = this.getInteractionHintKey(settings);
    if (!this.hasSeenInteractionHint(nextKey)) {
      this.pendingInteractionHintKey = nextKey;
      return;
    }
    this.pendingInteractionHintKey = '';
  }

  private canShowInteractionOverlay(): boolean {
    return this.isPageVisible &&
      !this.isLoading &&
      this.content.length > 0 &&
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
    this.showInteractionOverlay = false;
  }

  private tryShowQueuedInteractionHint(reason: string, delayMs: number = 0): void {
    const showOverlay = (): void => {
      if (!this.pendingInteractionHintKey || !this.canShowInteractionOverlay()) {
        return;
      }
      const shownHintKey = this.pendingInteractionHintKey;
      this.showInteractionOverlay = true;
      this.markInteractionHintSeen(shownHintKey);
      this.pendingInteractionHintKey = '';
      this.clearInteractionOverlayTimer();
      this.interactionOverlayDismissTimer = setTimeout(() => {
        this.hideInteractionOverlay();
      }, 6000);
      logger.info(TAG, `show interaction overlay: reason=${reason}, key=${shownHintKey}`);
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
      return resolveGuideHighlightRectInRoot(this.getUIContext(), anchorId, borderRadius, 'guide_novel_reader_root');
    } catch (error) {
      logger.warn(TAG, `获取小说阅读器引导锚点失败: ${String(error)}`);
      return null;
    }
  }

  private async waitForGuideLayout(delayMs: number = NovelReaderPage.GUIDE_LAYOUT_STABILIZE_DELAY_MS): Promise<void> {
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
      case 'guide_novel_reader_top_toolbar':
      case 'guide_novel_reader_bottom_toolbar':
        changed = !this.showTopToolbar || !this.showBottomToolbar || this.showChapterList ||
          this.showFontSettings || this.showBackgroundSettings || this.showReadingSettings ||
          this.showEncyclopediaDialog || this.toolbarOpacity < 0.99;
        this.showChapterList = false;
        this.chapterListOpacity = 0;
        this.showFontSettings = false;
        this.showBackgroundSettings = false;
        this.showReadingSettings = false;
        this.showEncyclopediaDialog = false;
        this.showTopToolbar = true;
        this.showBottomToolbar = true;
        this.toolbarOpacity = 1;
        break;
      case 'guide_novel_reader_chapter_list':
        changed = this.showTopToolbar || this.showBottomToolbar || !this.showChapterList ||
          this.showFontSettings || this.showBackgroundSettings || this.showReadingSettings ||
          this.showEncyclopediaDialog || this.toolbarOpacity > 0.01 || this.chapterListOpacity < 0.99;
        this.showTopToolbar = false;
        this.showBottomToolbar = false;
        this.toolbarOpacity = 0;
        this.showFontSettings = false;
        this.showBackgroundSettings = false;
        this.showReadingSettings = false;
        this.showEncyclopediaDialog = false;
        this.showChapterList = true;
        this.chapterListOpacity = 1;
        setTimeout(() => {
          try {
            const safeIndex = Math.max(0, Math.min(this.currentChapterIndex, Math.max(0, this.chapterList.length - 1)));
            this.chapterListScroller.scrollToIndex(safeIndex, true, ScrollAlign.CENTER);
          } catch (error) {
            logger.warn(TAG, `引导滚动小说目录失败: ${String(error)}`);
          }
        }, 60);
        break;
      default:
        changed = this.showTopToolbar || this.showBottomToolbar || this.showChapterList ||
          this.showFontSettings || this.showBackgroundSettings || this.showReadingSettings ||
          this.showEncyclopediaDialog || this.toolbarOpacity > 0.01 || this.chapterListOpacity > 0.01;
        this.showTopToolbar = false;
        this.showBottomToolbar = false;
        this.toolbarOpacity = 0;
        this.showChapterList = false;
        this.chapterListOpacity = 0;
        this.showFontSettings = false;
        this.showBackgroundSettings = false;
        this.showReadingSettings = false;
        this.showEncyclopediaDialog = false;
        break;
    }
    if (changed) {
      await this.waitForGuideLayout();
    }
  }

  private async refreshPageGuide(trigger: string): Promise<void> {
    await this.appGuideManager.initialize();
    if (!this.appGuideManager.getCurrentStep()) {
      await this.appGuideManager.tryAutoStartFlowByPage(AppGuidePageId.NOVEL_READER);
    }
    const step = this.appGuideManager.getCurrentStep();
    if (!step || step.pageId !== AppGuidePageId.NOVEL_READER) {
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
    logger.debug(TAG, `小说阅读器引导已刷新: trigger=${trigger}, step=${step.id}`);
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
    this.stopReadAloudUiSyncTimer();
    this.clearToolbarAutoHideTimer();
    this.clearFullscreenRestoreTimer();
    this.hideInteractionOverlay();
    const isOpeningReadAloudPlayer = this.isReadAloudPlayerOpeningSoon();
    if (isOpeningReadAloudPlayer) {
      logger.info(TAG, '小说阅读器进入听书独立页，保留当前沉浸模式');
    }
    this.readAloudController.handlePageHide();
    this.readAloudPlaying = this.readAloudController.getSnapshot().playbackState === ReadAloudPlaybackState.PLAYING;
    this.persistReadAloudResumeCharIndex(true);
    this.stopCrossChapterPrefetch(false);
    this.readAloudController.refreshMediaSession();
    logger.lifecycle(TAG, 'onWindowUnfocused - paused');
    // 立即保存阅读进度，确保 Home → 杀进程场景下进度不丢失
    this.saveReadProgress();
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
        logger.error(TAG, 'Failed to enter immersive mode: UIContext is null');
        return;
      }

      const currentMode = WindowManager.getCurrentMode();
      if (currentMode !== DisplayMode.FULL_IMMERSIVE) {
        this.previousDisplayMode = currentMode;
      }
      WindowManager.setDisplayModeWithTransition(DisplayMode.FULL_IMMERSIVE, this.uiContext);
      logger.info(TAG, 'Entered full immersive mode');
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
        logger.error(TAG, 'Failed to exit immersive mode: UIContext is null');
        return;
      }

      const targetMode = this.previousDisplayMode === DisplayMode.FULL_IMMERSIVE
        ? DisplayMode.DEFAULT
        : this.previousDisplayMode;
      if (WindowManager.getCurrentMode() === targetMode) {
        return;
      }
      WindowManager.setDisplayMode(targetMode, this.uiContext);
      logger.info(TAG, `恢复显示模式: ${targetMode}`);
    } catch (error) {
      logger.error(TAG, `恢复正常模式失败: ${String(error)}`);
    }
  }

  private reportTransitionLoadingProgress(progress: number, reason: string): void {
    const normalized = Math.max(0, Math.min(1, progress > 1 ? progress / 100 : progress));
    if (normalized <= this.transitionLoadingProgress + 0.001) {
      return;
    }
    this.transitionLoadingProgress = normalized;
    setReaderLoadingProgress(normalized);
    logger.debug(TAG, `transition loading progress: ${(normalized * 100).toFixed(1)}%, reason=${reason}`);
  }

  private notifyTransitionReaderReadyOnce(reason: string): void {
    if (this.hasNotifiedTransitionReaderReady) {
      logger.debug(TAG, `过渡动画就绪已通知，忽略重复触发: ${reason}`);
      return;
    }
    this.hasNotifiedTransitionReaderReady = true;
    this.reportTransitionLoadingProgress(1, `ready_${reason}`);
    setReaderReady();
    logger.info(TAG, `📖 已通知过渡动画阅读器就绪: ${reason}`);
  }

  /**
  * 关闭阅读器（带动画）
  */
  private isHostedByIsolatedReaderAbility(): boolean {
    return this.readerHostMode === READER_ABILITY_HOST_MULTITON;
  }

  private async terminateIsolatedReaderAbility(reason: string): Promise<void> {
    try {
      const hostContext = this.getUIContext()?.getHostContext() as common.UIAbilityContext;
      if (!hostContext) {
        logger.warn(TAG, `独立小说阅读器退出失败，回退页面栈: reason=${reason}`);
        this.pathStack.pop();
        return;
      }
      logger.info(TAG, `独立小说阅读器实例退出: reason=${reason}, instanceId=${this.readerInstanceId}`);
      await hostContext.terminateSelf();
    } catch (error) {
      logger.error(TAG, `独立小说阅读器实例退出异常: ${String(error)}`);
      this.pathStack.pop();
    }
  }

  private async closeReader(): Promise<void> {
    if (this.pendingSettingsSnapshot !== null || this.settingsSavePromise !== null) {
      try {
        await this.saveSettings();
      } catch (error) {
        logger.warn(TAG, `鍏抽棴鍓嶅埛鏂伴槄璇昏缃け璐? ${String(error)}`);
      }
    }

    // Save progress before triggering close transition.
    this.saveReadProgress();

    // Resolve source cover id for close animation target.
    const coverComponentId = this.sourceCoverComponentId || `novel_cover_${this.bookId}`;

    try {
      if (this.isHostedByIsolatedReaderAbility()) {
        logger.info(TAG, `独立小说阅读器退出不挂载关闭动画层，封面组件ID: ${coverComponentId}`);
        this.isCloseTransitionNavigating = true;
        cancelTransition();
        await this.terminateIsolatedReaderAbility('close_reader_isolated_reader');
        return;
      }

      logger.info(TAG, `触发关闭过渡动画，封面组件ID: ${coverComponentId}`);
      await startBookCloseTransitionWithComponentId(
        'novel_reader_root',
        coverComponentId
      );

      // Pop immediately after transition starts so detail page is visible during shrink.
      this.isCloseTransitionNavigating = true;
      this.pathStack.pop();
    } catch (error) {
      logger.error(TAG, `关闭动画失败: ${String(error)}`);
      this.isCloseTransitionNavigating = false;
      cancelTransition();
      if (this.isHostedByIsolatedReaderAbility()) {
        await this.terminateIsolatedReaderAbility('close_reader_error');
      } else {
        this.pathStack.pop();
      }
    }
  }


  /**
  * 切换工具栏显示/隐藏
  */
  private toggleToolbar(): void {
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
  * 显示章节列表（带动画）
  */
  private showChapterListWithAnimation(): void {
    this.showChapterList = true;
    this.getUIContext().animateTo({
      duration: 250,
      curve: curves.springMotion(0.5, 0.8)
    }, () => {
      this.chapterListOpacity = 1;
    });
    // 延迟滚动到当前章节
    setTimeout(() => {
      this.chapterListScroller.scrollToIndex(this.currentChapterIndex, true, ScrollAlign.CENTER);
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
  * 显示字体设置面板
  */
  private showFontSettingsPanel(): void {
    this.hideToolbarWithAnimation();
    this.showBackgroundSettings = false;
    this.showReadingSettings = false;
    this.showFontSettings = true;
  }

  /**
  * 显示背景设置面板
  */
  private showBackgroundSettingsPanel(): void {
    this.hideToolbarWithAnimation();
    this.showFontSettings = false;
    this.showReadingSettings = false;
    this.showBackgroundSettings = true;
  }

  /**
  * 显示阅读设置面板
  */
  private showReadingSettingsPanel(): void {
    this.hideToolbarWithAnimation();
    this.showFontSettings = false;
    this.showBackgroundSettings = false;
    this.openReadAloudInfoWhenOpenReadingSettings = false;
    this.showReadingSettings = true;
  }

  private toggleReadAloudFromToolbar(): void {
    const defaultReadAloud = DEFAULT_TEXT_READER_SETTINGS.readAloud;
    if (!defaultReadAloud) {
      return;
    }
    if (!this.settings.readAloud) {
      this.settings.readAloud = normalizeReadAloudSettings(defaultReadAloud);
    }
    const readAloudSettings = this.settings.readAloud
      ? normalizeReadAloudSettings(this.settings.readAloud)
      : normalizeReadAloudSettings(defaultReadAloud);
    this.settings.readAloud = readAloudSettings;
    if (!readAloudSettings) {
      return;
    }
    if (!readAloudSettings.enabled) {
      readAloudSettings.enabled = true;
      this.saveSettings();
    }
    this.readAloudController.updateSettings(readAloudSettings);
    this.updateReadAloudContextByPosition();
    if (this.readAloudController.getSnapshot().playbackState === ReadAloudPlaybackState.PLAYING) {
      this.readAloudController.pause('toolbar_toggle');
    } else {
      this.readAloudController.start('toolbar_toggle');
    }
    this.readAloudController.refreshMediaSession();
    this.syncReadAloudStateFromController();
  }

  private openReadAloudSettingsPanelFromToolbar(): void {
    const defaultReadAloud = DEFAULT_TEXT_READER_SETTINGS.readAloud;
    if (defaultReadAloud && !this.settings.readAloud) {
      this.settings.readAloud = normalizeReadAloudSettings(defaultReadAloud);
    }
    this.hideToolbarWithAnimation();
    this.showFontSettings = false;
    this.showBackgroundSettings = false;
    this.openReadAloudInfoWhenOpenReadingSettings = true;
    this.showReadingSettings = true;
  }

  private async initializeReaderAfterReady(): Promise<void> {
    await this.loadSettings();
    await this.loadContent();
  }

  async loadSettings(): Promise<void> {
    try {
          // 检查是否有书籍专属设置
      let bookSettings: TextReaderSettings | undefined = undefined;
      let hasBookSpecificSettings = false;
      
      if (this.bookId) {
        const settingsKey = `${SettingKeys.NOVEL_READER_SETTINGS}_${this.bookId}`;
        try {
          // 检查是否有书籍专属设置
          const hasBookSettings = this.settingsManager.getString(settingsKey, '');
          if (hasBookSettings) {
            bookSettings = this.settingsManager.getJSON<TextReaderSettings>(settingsKey, DEFAULT_TEXT_READER_SETTINGS);
            hasBookSpecificSettings = true;
          }
        } catch (e) {
          bookSettings = undefined;
        }
      }
      
      if (bookSettings && hasBookSpecificSettings) {
        // 使用全局设置
        logger.info(TAG, `加载书籍专属设置: ${this.bookId}`);
        this.ensureSettingsComplete(bookSettings);
        this.settings = bookSettings;
        if (this.settings.readAloud) {
          this.readAloudController.updateSettings(this.settings.readAloud);
        }
      } else {
        // 使用全局设置
        const globalSettings = this.settingsManager.getJSON<TextReaderSettings>(SettingKeys.NOVEL_READER_SETTINGS, DEFAULT_TEXT_READER_SETTINGS);
        this.ensureSettingsComplete(globalSettings);
        if (this.isLocalTxtNovelMode()) {
          const ebook = await this.ensureLocalEbookLoaded();
          const ebookSettings = hasCustomLocalTextNovelReadingSettings(ebook?.readingSettings)
            ? ebook?.readingSettings
            : undefined;
          this.settings = buildTextReaderSettingsFromEBookSettings(ebookSettings, globalSettings);
          this.ensureSettingsComplete(this.settings);
          logger.info(TAG, `加载本地 TXT 小说阅读设置: ebookId=${this.localEbookId}`);
        } else {
          this.settings = globalSettings;
        }
        if (this.settings.readAloud) {
          this.readAloudController.updateSettings(this.settings.readAloud);
        }
        logger.info(TAG, 'Loaded global reader settings');
      }
    } catch (e) {
      logger.warn(TAG, `加载设置失败: ${String(e)}`);
    }
    this.syncDeviceOrientationLock('settings_loaded');
  }
  
  /**
  * 确保设置对象的所有子属性完整（兼容旧版本设置）
  */
  private ensureSettingsComplete(settings: TextReaderSettings): void {
    // 确保textStyle对象完整
    if (!settings.background) {
      settings.background = { type: BackgroundType.COLOR, color: '#F5F0E1' };
    } else if (!settings.background.type) {
      settings.background.type = BackgroundType.COLOR;
    }
    
      // 确保textStyle的所有属性都有默认值
    if (!settings.textStyle) {
      settings.textStyle = {
        fontSize: clampTextReaderFontSize(DEFAULT_TEXT_STYLE.fontSize),
        lineHeight: DEFAULT_TEXT_STYLE.lineHeight,
        paragraphSpacing: DEFAULT_TEXT_STYLE.paragraphSpacing,
        firstLineIndent: DEFAULT_TEXT_STYLE.firstLineIndent,
        letterSpacing: DEFAULT_TEXT_STYLE.letterSpacing,
        textColor: DEFAULT_TEXT_STYLE.textColor,
        fontWeight: DEFAULT_TEXT_STYLE.fontWeight,
        fontFamily: DEFAULT_TEXT_STYLE.fontFamily,
        textAlignment: DEFAULT_TEXT_STYLE.textAlignment
      };
    } else {
      // 确保textStyle的所有属性都有默认值
      if (settings.textStyle.fontSize === undefined) {
        settings.textStyle.fontSize = DEFAULT_TEXT_STYLE.fontSize;
      } else {
        settings.textStyle.fontSize = clampTextReaderFontSize(settings.textStyle.fontSize);
      }
      if (settings.textStyle.lineHeight === undefined) settings.textStyle.lineHeight = 1.8;
      if (settings.textStyle.paragraphSpacing === undefined) settings.textStyle.paragraphSpacing = 16;
      if (settings.textStyle.firstLineIndent === undefined) settings.textStyle.firstLineIndent = 2;
      if (settings.textStyle.letterSpacing === undefined) settings.textStyle.letterSpacing = 0.5;
      if (settings.textStyle.textColor === undefined) settings.textStyle.textColor = '#333333';
      if (settings.textStyle.fontWeight === undefined) settings.textStyle.fontWeight = 400;
      if (settings.textStyle.fontFamily === undefined) settings.textStyle.fontFamily = 'HarmonyOS Sans';
      if (settings.textStyle.textAlignment === undefined) settings.textStyle.textAlignment = TextAlignment.JUSTIFY;
    }
    
      // 确保pageMargins的所有属性都有合理的默认值
    if (!settings.pageMargins) {
      settings.pageMargins = { top: 48, bottom: 48, left: 24, right: 24 };
    } else {
      // 确保pageMargins的所有属性都有合理的默认值
      if (settings.pageMargins.top === undefined || settings.pageMargins.top < 0) settings.pageMargins.top = 48;
      if (settings.pageMargins.bottom === undefined || settings.pageMargins.bottom < 0) settings.pageMargins.bottom = 48;
      if (settings.pageMargins.left === undefined || settings.pageMargins.left < 0) settings.pageMargins.left = 24;
      if (settings.pageMargins.right === undefined || settings.pageMargins.right < 0) settings.pageMargins.right = 24;
    }

    if (settings.tapToTurn === undefined) settings.tapToTurn = DEFAULT_TEXT_READER_SETTINGS.tapToTurn;
    if (settings.volumeKeyNavigation === undefined) settings.volumeKeyNavigation = DEFAULT_TEXT_READER_SETTINGS.volumeKeyNavigation;
    if (settings.lockDeviceOrientation === undefined) {
      settings.lockDeviceOrientation = DEFAULT_TEXT_READER_SETTINGS.lockDeviceOrientation ?? false;
    }

    settings.readAloud = normalizeReadAloudSettings(
      settings.readAloud ?? DEFAULT_TEXT_READER_SETTINGS.readAloud
    );
  }

  private syncDeviceOrientationLock(reason: string): void {
    if (!this.uiContext) {
      this.uiContext = this.getUIContext();
    }
    const enabled: boolean = this.settings.lockDeviceOrientation ??
      DEFAULT_TEXT_READER_SETTINGS.lockDeviceOrientation ??
      false;
    this.orientationLockToken = ReaderOrientationLockHelper.syncCurrentOrientationLock(
      'NovelReaderPage',
      this.orientationLockToken,
      enabled,
      this.uiContext ?? undefined
    );
    logger.info(TAG, `设备方向锁同步完成: enabled=${enabled}, reason=${reason}`);
  }

  private isLocalTxtNovelMode(): boolean {
    return isLocalTxtNovelReaderSource(this.sourceId) || this.localEbookId.length > 0;
  }

  private isReadAloudPlayerOpeningSoon(): boolean {
    const openingAt = AppStorage.get<number>('ReadAloudPlayerOpeningAt') ?? 0;
    if (openingAt <= 0) {
      return false;
    }
    return Math.abs(Date.now() - openingAt) <= 2000;
  }

  private startReadAloudUiSyncTimer(): void {
    if (this.readAloudUiSyncTimer >= 0) {
      return;
    }
    this.readAloudUiSyncTimer = setInterval(() => {
      if (!this.isPageVisible || !this.bookId) {
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
    return currentHostPage !== 'ReadAloudPlayerPage';
  }

  private async ensureLocalEbookLoaded(): Promise<EBook | null> {
    if (!this.isLocalTxtNovelMode() || this.localEbookId.length <= 0) {
      return null;
    }
    if (this.localEbook) {
      return this.localEbook;
    }

    try {
      const ebook = await this.ebookDataManager.getEBookById(this.localEbookId);
      if (!ebook) {
        logger.warn(TAG, `Local TXT ebook data not found: ebookId=${this.localEbookId}`);
        return null;
      }
      this.localEbook = ebook;
      return ebook;
    } catch (error) {
      logger.error(TAG, `加载本地 TXT 小说失败: ebookId=${this.localEbookId}, error=${String(error)}`);
      return null;
    }
  }

  private getReaderPaginationMode(): PaginationMode {
    return this.isLocalTxtNovelMode() ? PaginationMode.LOCAL : PaginationMode.ONLINE;
  }

  private buildLocalTextDomPos(pageIndex: number): string {
    const safePageIndex = Math.max(0, Math.floor(pageIndex));
    const safeCharIndex = Math.max(0, this.getCurrentReadAloudResumeCharIndex());
    return `page:${safePageIndex};char:${safeCharIndex};chapter:${Math.max(0, this.currentChapterIndex)}`;
  }

  private parseLocalTextDomPos(domPos: string): LocalTextDomPosition | null {
    if (!domPos || domPos.length <= 0) {
      return null;
    }

    let pageIndex = -1;
    let charIndex = -1;
    let chapterIndex = -1;
    const parts = domPos.split(';');
    for (let i = 0; i < parts.length; i++) {
      const part = parts[i];
      if (part.startsWith('page:')) {
        const value = parseInt(part.substring(5), 10);
        if (!isNaN(value) && value >= 0) {
          pageIndex = value;
        }
      } else if (part.startsWith('char:')) {
        const value = parseInt(part.substring(5), 10);
        if (!isNaN(value) && value >= 0) {
          charIndex = value;
        }
      } else if (part.startsWith('chapter:')) {
        const value = parseInt(part.substring(8), 10);
        if (!isNaN(value) && value >= 0) {
          chapterIndex = value;
        }
      }
    }

    if (pageIndex < 0 && charIndex < 0 && chapterIndex < 0) {
      return null;
    }

    const position: LocalTextDomPosition = {
      pageIndex: Math.max(0, pageIndex),
      charIndex: Math.max(0, charIndex),
      chapterIndex: Math.max(0, chapterIndex)
    };
    return position;
  }

  private async ensurePreloadSettingsLoaded(): Promise<void> {
    if (this.preloadSettingsLoaded) {
      return;
    }
    try {
      const context = (this.getUIContext().getHostContext() as common.UIAbilityContext) as common.UIAbilityContext;
      const store = await preferences.getPreferences(context, NOVEL_SETTINGS_STORE);
      const rawDefaultLoadChapters = Number(await store.get('defaultLoadChapters', NOVEL_DEFAULT_PRELOAD_CHAPTERS));
      this.preloadChapterCount = this.normalizePreloadChapterCount(rawDefaultLoadChapters);
      this.preloadWhileReadingEnabled = await store.get('enableReadWhileDownload', true) as boolean;
      this.replaceRulesEnabled = await store.get(NOVEL_SETTING_ENABLE_REPLACE_RULES, true) as boolean;
      this.scopedReplaceRuleIds = await this.loadScopedReplaceRuleIds();
      this.preloadSettingsLoaded = true;
      logger.info(
        TAG,
        `preload settings loaded: chapters=${this.preloadChapterCount}, whileReading=${this.preloadWhileReadingEnabled}, replaceRules=${this.replaceRulesEnabled}, scopedReplaceRules=${this.scopedReplaceRuleIds ? this.scopedReplaceRuleIds.length : -1}`
      );
    } catch (error) {
      this.preloadChapterCount = NOVEL_DEFAULT_PRELOAD_CHAPTERS;
      this.preloadWhileReadingEnabled = true;
      this.replaceRulesEnabled = true;
      this.scopedReplaceRuleIds = null;
      this.preloadSettingsLoaded = true;
      logger.warn(TAG, `load preload settings failed, use default: ${String(error)}`);
    }
  }

  private buildScopedReplaceRuleKey(): string {
    return `${NOVEL_BOOK_REPLACE_RULE_IDS_PREFIX}${this.bookId}`;
  }

  private parseRuleIdArray(rawValue: string): string[] {
    if (!rawValue || rawValue.length === 0) {
      return [];
    }
    try {
      const parsed = SafeUtils.parseArr(rawValue) as Array<string>;
      if (!Array.isArray(parsed)) {
        return [];
      }
      const result: string[] = [];
      for (const item of parsed) {
        if (typeof item === 'string' && item.length > 0) {
          result.push(item);
        }
      }
      return result;
    } catch (error) {
      logger.warn(TAG, `parse scoped replace rule ids failed: ${String(error)}`);
      return [];
    }
  }

  private async loadScopedReplaceRuleIds(): Promise<string[] | null> {
    if (!this.bookId || this.bookId.length === 0) {
      return null;
    }
    try {
      const context = (this.getUIContext().getHostContext() as common.UIAbilityContext) as common.UIAbilityContext;
      const store = await preferences.getPreferences(context, NOVEL_BOOK_RULE_SETTINGS_STORE);
      const raw = await store.get(this.buildScopedReplaceRuleKey(), '') as string;
      if (!raw || raw.length === 0) {
        return null;
      }
      return this.parseRuleIdArray(raw);
    } catch (error) {
      logger.warn(TAG, `load scoped replace rule ids failed: ${String(error)}`);
      return null;
    }
  }

  private async persistReplaceRulesEnabled(enabled: boolean, trigger: string): Promise<void> {
    this.replaceRulesEnabled = enabled;
    try {
      const context = (this.getUIContext().getHostContext() as common.UIAbilityContext) as common.UIAbilityContext;
      const store = await preferences.getPreferences(context, NOVEL_SETTINGS_STORE);
      await store.put(NOVEL_SETTING_ENABLE_REPLACE_RULES, enabled);
      await store.flush();
      logger.info(TAG, `净化规则总开关已更新: enabled=${enabled}, trigger=${trigger}`);
    } catch (error) {
      logger.warn(TAG, `保存净化规则总开关失败: trigger=${trigger}, error=${String(error)}`);
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

    if (!this.bookId || this.bookId.length <= 0) {
      return;
    }
    try {
      const context = (this.getUIContext().getHostContext() as common.UIAbilityContext) as common.UIAbilityContext;
      const store = await preferences.getPreferences(context, NOVEL_BOOK_RULE_SETTINGS_STORE);
      await store.put(this.buildScopedReplaceRuleKey(), JSON.stringify(nextRuleIds));
      await store.flush();
      logger.info(TAG, `已将新增净化规则纳入当前书籍作用域: ruleId=${ruleId}, total=${nextRuleIds.length}`);
    } catch (error) {
      logger.warn(TAG, `保存书籍净化规则作用域失败: ruleId=${ruleId}, error=${String(error)}`);
    }
  }

  private async refreshCurrentChapterAfterPurifyRuleAdded(trigger: string): Promise<void> {
    try {
      if (this.content && this.content.length > 0) {
        const ruleManager = NovelReplaceRuleManager.getInstance();
        const replacedContent = ruleManager.applyRules(this.content, ReplaceScope.CONTENT, this.sourceId);
        if (replacedContent !== this.content) {
          this.content = replacedContent;
          this.readerKey += 1;
          await this.refreshCurrentChapterHighlightRanges('purify_rule_local_apply');
          this.syncOverallReadProgress('purify_rule_local_apply');
          this.refreshCurrentNovelBookmarkState('purify_rule_local_apply');
          logger.info(TAG, `净化规则已完成本地即时刷新: trigger=${trigger}, chapterIndex=${this.currentChapterIndex}`);
          return;
        }
      }
    } catch (error) {
      logger.warn(TAG, `净化规则本地即时刷新失败，将尝试章节重处理: trigger=${trigger}, error=${String(error)}`);
    }

    try {
      let rawContent = await this.cacheManager.getChapterCache(this.bookId, this.currentChapterIndex);
      if (!rawContent || rawContent.length <= 0) {
        const currentChapter = this.chapterList[this.currentChapterIndex];
        if (currentChapter) {
          rawContent = await this.sourceManager.getContent(this.sourceId, currentChapter);
        }
      }

      if (rawContent && rawContent.length > 0) {
        this.content = this.processChapterContent(
          rawContent,
          this.chapterTitle,
          this.currentChapterIndex,
          `purify_rule_${trigger}`
        );
        this.readerKey += 1;
        await this.refreshCurrentChapterHighlightRanges('purify_rule_realtime_refresh');
        this.syncOverallReadProgress('purify_rule_realtime_refresh');
        this.refreshCurrentNovelBookmarkState('purify_rule_realtime_refresh');
        logger.info(TAG, `净化规则已实时刷新当前章节: trigger=${trigger}, chapterIndex=${this.currentChapterIndex}`);
        return;
      }

      logger.warn(TAG, `净化规则实时刷新未命中原始内容，回退完整重载: trigger=${trigger}`);
    } catch (error) {
      logger.warn(TAG, `净化规则实时刷新失败，回退完整重载: trigger=${trigger}, error=${String(error)}`);
    }

    this.stopCrossChapterPrefetch(true);
    await this.loadContent();
  }

  private normalizePreloadChapterCount(rawValue: number): number {
    if (!Number.isFinite(rawValue)) {
      return NOVEL_DEFAULT_PRELOAD_CHAPTERS;
    }
    const safeValue = Math.floor(rawValue);
    return Math.max(0, safeValue);
  }

  private buildContentProcessConfig(): ContentProcessConfig {
    return {
      useReplace: this.replaceRulesEnabled,
      chineseConvert: 0,
      reSegment: false,
      includeTitle: true,
      paragraphIndent: '',
      sourceId: this.sourceId,
      enabledRuleIds: this.scopedReplaceRuleIds === null ? undefined : this.scopedReplaceRuleIds
    };
  }

  private processChapterContent(
    rawContent: string,
    chapterTitle: string,
    chapterIndex: number,
    reason: string
  ): string {
    const contentProcessor = getNovelContentProcessor();
    const processResult = contentProcessor.processContent(
      rawContent,
      chapterTitle,
      this.bookName,
      this.buildContentProcessConfig()
    );
    if (processResult.appliedRules.length > 0) {
      logger.info(TAG, `chapter ${chapterIndex} applied ${processResult.appliedRules.length} replace rules, reason=${reason}`);
    }
    logger.debug(
      TAG,
      `chapter ${chapterIndex} parsed: chars=${processResult.content.length}, paragraphs=${processResult.paragraphs.length}, reason=${reason}`
    );
    return processResult.content;
  }

  private countPreparedTextChapterWords(content: string): number {
    if (!content) {
      return 0;
    }
    const compactContent = content.replace(/\s+/g, '');
    if (compactContent.length > 0) {
      return compactContent.length;
    }
    return content.length;
  }

  private buildPreparedTextChapter(content: string): PreparedTextChapter {
    const safeContent = content || '';
    return {
      content: safeContent,
      wordCount: this.countPreparedTextChapterWords(safeContent)
    };
  }

  private updatePreparedTextChapterState(chapterIndex: number, preparedChapter: PreparedTextChapter): void {
    if (chapterIndex < 0 || chapterIndex >= this.chapters.length) {
      return;
    }
    const currentChapter = this.chapters[chapterIndex];
    if (!currentChapter) {
      return;
    }
    const currentWordCount = currentChapter.wordCount || 0;
    const nextEndPosition = preparedChapter.content.length > 0
      ? preparedChapter.content.length
      : currentChapter.endPosition;
    if (
      currentChapter.content === preparedChapter.content &&
      currentWordCount === preparedChapter.wordCount &&
      currentChapter.endPosition === nextEndPosition
    ) {
      return;
    }

    const nextChapter: TextChapter = {
      id: currentChapter.id,
      title: currentChapter.title,
      index: currentChapter.index,
      content: preparedChapter.content,
      wordCount: preparedChapter.wordCount,
      startPosition: currentChapter.startPosition,
      endPosition: nextEndPosition
    };
    const nextChapters = this.chapters.slice();
    nextChapters[chapterIndex] = nextChapter;
    this.chapters = nextChapters;
  }

  private clearPreparedTextChapterContentState(chapterIndex: number): void {
    if (chapterIndex < 0 || chapterIndex >= this.chapters.length) {
      return;
    }
    const currentChapter = this.chapters[chapterIndex];
    if (!currentChapter || currentChapter.content.length <= 0) {
      return;
    }
    const clearedChapter: TextChapter = {
      id: currentChapter.id,
      title: currentChapter.title,
      index: currentChapter.index,
      content: '',
      wordCount: currentChapter.wordCount || 0,
      startPosition: currentChapter.startPosition,
      endPosition: currentChapter.endPosition
    };
    const nextChapters = this.chapters.slice();
    nextChapters[chapterIndex] = clearedChapter;
    this.chapters = nextChapters;
  }

  private clearPreparedTextChapterStates(): void {
    if (this.chapters.length <= 0) {
      return;
    }
    for (let chapterIndex = 0; chapterIndex < this.chapters.length; chapterIndex++) {
      if (chapterIndex === this.currentChapterIndex) {
        continue;
      }
      this.clearPreparedTextChapterContentState(chapterIndex);
    }
  }

  private getEffectivePrefetchCount(): number {
    if (!this.preloadWhileReadingEnabled) {
      return 0;
    }
    const maxDistance = Math.max(this.currentChapterIndex, this.totalChapters - this.currentChapterIndex - 1);
    if (maxDistance <= 0) {
      return 0;
    }
    if (this.preloadChapterCount >= 9999) {
      return maxDistance;
    }
    return Math.max(0, Math.min(this.preloadChapterCount, maxDistance));
  }

  private buildPrefetchChapterIndexes(preloadCount: number): number[] {
    const indexes: number[] = [];
    if (preloadCount <= 0 || this.totalChapters <= 0) {
      return indexes;
    }
    const radius = Math.max(0, Math.min(preloadCount, MAX_PREPARSED_CHAPTER_CACHE - 1));
    for (let offset = 1; offset <= radius; offset++) {
      const nextIndex = this.currentChapterIndex + offset;
      if (nextIndex < this.totalChapters) {
        indexes.push(nextIndex);
      }
      const prevIndex = this.currentChapterIndex - offset;
      if (prevIndex >= 0) {
        indexes.push(prevIndex);
      }
    }
    return indexes;
  }

  private stopCrossChapterPrefetch(clearPreparedCache: boolean): void {
    this.prefetchGeneration++;
    if (clearPreparedCache) {
      this.prefetchingChapterIndexes.clear();
      this.preparsedChapterContent.clear();
      this.clearPreparedTextChapterStates();
    }
  }

  private trimPreparsedChapterCache(): void {
    if (this.preparsedChapterContent.size <= MAX_PREPARSED_CHAPTER_CACHE) {
      return;
    }
    const indexes = Array.from(this.preparsedChapterContent.keys()).sort((a: number, b: number) => {
      const distanceA = Math.abs(a - this.currentChapterIndex);
      const distanceB = Math.abs(b - this.currentChapterIndex);
      if (distanceA !== distanceB) {
        return distanceB - distanceA;
      }
      return a - b;
    });
    while (this.preparsedChapterContent.size > MAX_PREPARSED_CHAPTER_CACHE && indexes.length > 0) {
      const removableIndex = indexes.shift();
      if (removableIndex === undefined) {
        break;
      }
      if (removableIndex === this.currentChapterIndex) {
        continue;
      }
      this.preparsedChapterContent.delete(removableIndex);
      this.clearPreparedTextChapterContentState(removableIndex);
    }
  }

  private scheduleCrossChapterPrefetch(): void {
    const preloadCount = this.getEffectivePrefetchCount();
    const chapterIndexes = this.buildPrefetchChapterIndexes(preloadCount);
    if (chapterIndexes.length <= 0 || this.chapterList.length === 0) {
      return;
    }
    const generation = ++this.prefetchGeneration;
    const previewIndexes = chapterIndexes.slice(0, 6).join(',');
    logger.info(
      TAG,
      `schedule chapter prefetch: targets=${previewIndexes}${chapterIndexes.length > 6 ? ',...' : ''}, generation=${generation}`
    );
    void this.prefetchChapterIndexes(generation, chapterIndexes);
  }

  private async prefetchChapterIndexes(generation: number, chapterIndexes: number[]): Promise<void> {
    for (const chapterIndex of chapterIndexes) {
      if (generation !== this.prefetchGeneration) {
        logger.debug(TAG, `prefetch canceled: generation=${generation}, current=${this.prefetchGeneration}`);
        return;
      }
      if (this.preparsedChapterContent.has(chapterIndex) || this.prefetchingChapterIndexes.has(chapterIndex)) {
        continue;
      }
      const chapter = this.chapterList[chapterIndex];
      if (!chapter) {
        continue;
      }

      this.prefetchingChapterIndexes.add(chapterIndex);
      try {
        let rawContent: string | null = null;
        if (this.isLocalTxtNovelMode()) {
          const ebook = await this.ensureLocalEbookLoaded();
          rawContent = ebook?.chapters[chapterIndex]?.content || null;
        } else {
          rawContent = await this.cacheManager.getChapterCache(this.bookId, chapterIndex);
          if (!rawContent) {
            const chapterForCache: LegadoChapter = {
              id: chapter.id || '',
              bookUrl: this.bookUrl,
              url: chapter.url,
              title: chapter.title,
              index: chapterIndex
            };
            const cached = await this.cacheManager.cacheChapter(this.sourceId, this.bookId, chapterForCache);
            if (!cached) {
              continue;
            }
            rawContent = await this.cacheManager.getChapterCache(this.bookId, chapterIndex);
          }
        }
        if (!rawContent) {
          continue;
        }
        const parsedContent = this.processChapterContent(rawContent, chapter.title, chapterIndex, 'prefetch');
        const preparedChapter = this.buildPreparedTextChapter(parsedContent);
        this.preparsedChapterContent.set(chapterIndex, preparedChapter);
        this.updatePreparedTextChapterState(chapterIndex, preparedChapter);
        this.trimPreparsedChapterCache();
      } catch (error) {
        logger.warn(TAG, `prefetch chapter failed: index=${chapterIndex}, error=${String(error)}`);
      } finally {
        this.prefetchingChapterIndexes.delete(chapterIndex);
      }
    }
  }

  private async getRawChapterContent(chapterIndex: number): Promise<string | null> {
    if (this.isLocalTxtNovelMode()) {
      const ebook = await this.ensureLocalEbookLoaded();
      const chapter = ebook?.chapters[chapterIndex];
      return chapter?.content || null;
    }

    let rawContent = await this.cacheManager.getChapterCache(this.bookId, chapterIndex);
    if (rawContent) {
      return rawContent;
    }

    const chapter = this.chapterList[chapterIndex];
    if (!chapter) {
      return null;
    }

    const chapterForRequest: LegadoChapter = {
      id: chapter.id || '',
      bookUrl: this.bookUrl,
      url: chapter.url,
      title: chapter.title,
      index: chapterIndex
    };
    rawContent = await this.sourceManager.getContent(this.sourceId, chapterForRequest);
    return rawContent || null;
  }

  async loadContent(): Promise<void> {
    this.hasNotifiedTransitionReaderReady = false;
    this.transitionLoadingProgress = 0;
    this.isLoading = true;
    this.isReadProgressReady = false;
    this.currentChapterHighlightRanges = [];
    this.isCurrentPageBookmarked = false;
    this.currentPageBookmarkId = '';
    this.reportTransitionLoadingProgress(0.06, 'load_start');
    try {
      // [优化] 确保净化规则管理器已初始化并加载最新规则
      this.setupFullscreenMode();
      await this.ensurePreloadSettingsLoaded();
      
      // 加载章节列表（如果还没有加载）
      const ruleManager = NovelReplaceRuleManager.getInstance();
      await ruleManager.initialize();
      await ruleManager.refreshRules();
      this.reportTransitionLoadingProgress(0.2, 'rules_ready');
      
      // 加载章节列表（如果还没有加载）
      if (this.chapterList.length === 0) {
        await this.loadChapterList();
      }
      this.reportTransitionLoadingProgress(0.38, 'chapter_list_ready');
      
      const currentChapter = this.chapterList[this.currentChapterIndex];
      if (currentChapter) {
        this.chapterUrl = currentChapter.url;
        this.chapterTitle = currentChapter.title;
        this.chapterId = `${this.bookId}_${this.currentChapterIndex}`;
      }
      
      // Prefer preparsed chapter content when available to avoid duplicate parsing.
      const preparsedContent = this.preparsedChapterContent.get(this.currentChapterIndex);
      if (preparsedContent !== undefined) {
        this.preparsedChapterContent.delete(this.currentChapterIndex);
        this.content = preparsedContent.content;
        this.updatePreparedTextChapterState(this.currentChapterIndex, preparsedContent);
        logger.info(TAG, `hit preparsed chapter cache: index=${this.currentChapterIndex}`);
        this.reportTransitionLoadingProgress(0.62, 'chapter_content_ready');
      } else {
        const rawContent = await this.getRawChapterContent(this.currentChapterIndex);
        if (rawContent) {
          logger.info(TAG, `loaded raw chapter content: ${this.chapterTitle}`);
        } else {
          logger.info(TAG, `chapter content is empty: ${this.chapterTitle}`);
        }
        this.reportTransitionLoadingProgress(0.62, 'chapter_content_ready');

        if (!rawContent) {
          this.content = 'Load failed, please retry';
        } else {
          const preparedChapter = this.buildPreparedTextChapter(this.processChapterContent(
            rawContent,
            this.chapterTitle,
            this.currentChapterIndex,
            'current_chapter_load'
          ));
          this.content = preparedChapter.content;
          this.updatePreparedTextChapterState(this.currentChapterIndex, preparedChapter);
        }
      }
      this.reportTransitionLoadingProgress(0.76, 'content_processed');
      await this.refreshCurrentChapterHighlightRanges('load_content');
      
      // 加载阅读进度
      await this.loadReadProgress();
      this.isReadProgressReady = true;
      this.currentPageStartCharIndex = 0;
      this.currentPageEndCharIndex = 0;
      this.restoreReadAloudResumeCharIndex();
      this.syncReadAloudStateFromController();
      this.updateReadAloudContextByPosition();
      this.tryHandleAutoReadAloudEntry();
      this.reportTransitionLoadingProgress(0.9, 'progress_restored');
      this.scheduleCrossChapterPrefetch();
      this.syncOverallReadProgress('load_content_success');
      this.refreshCurrentNovelBookmarkState('load_content_success');
    } catch (error) {
      logger.error(TAG, `加载正文失败: ${String(error)}`);
      this.content = '加载失败: ' + String(error);
      this.currentChapterHighlightRanges = [];
      this.pendingSeekChapterIndex = -1;
      this.pendingSeekChapterFraction = -1;
      this.isCurrentPageBookmarked = false;
      this.currentPageBookmarkId = '';
      this.reportTransitionLoadingProgress(0.9, 'load_failed_fallback');
      this.syncOverallReadProgress('load_content_failed');
    }
    this.isLoading = false;
  }
  
  /**
  * 加载章节列表
  */
  private getCurrentSourceType(): LegadoBookSourceType {
    const source = this.sourceManager.getSource(this.sourceId);
    if (source) {
      return source.bookSourceType;
    }
    return LegadoBookSourceType.TEXT;
  }

  async loadChapterList(): Promise<void> {
    try {
      if (this.isLocalTxtNovelMode()) {
        const ebook = await this.ensureLocalEbookLoaded();
        if (!ebook) {
          this.chapterList = [];
          this.chapters = [];
          this.totalChapters = 0;
          return;
        }

        const localChapters = ebook.chapters ?? [];
        this.totalChapters = localChapters.length;
        this.chapterList = localChapters.map((chapter, index: number): LegadoChapter => {
          const chapterUrl = chapter.id || `ebook://${ebook.id}/chapter/${index}`;
          return {
            id: chapter.id || `chapter_${index}`,
            bookUrl: this.bookUrl,
            url: chapterUrl,
            title: chapter.title || `Chapter ${index + 1}`,
            index: index
          };
        });
        this.chapters = localChapters.map((chapter, index: number): TextChapter => {
          return {
            id: chapter.id || `chapter_${index}`,
            title: chapter.title || `Chapter ${index + 1}`,
            content: '',
            wordCount: chapter.wordCount || 0,
            index: index,
            startPosition: chapter.startPosition,
            endPosition: chapter.endPosition
          };
        });

        if (this.totalChapters > 0) {
          const safeChapterIndex = Math.max(0, Math.min(this.currentChapterIndex, this.totalChapters - 1));
          this.currentChapterIndex = safeChapterIndex;
          const currentChapter = this.chapterList[safeChapterIndex];
          this.chapterUrl = currentChapter.url;
          this.chapterTitle = currentChapter.title;
          this.chapterId = `${this.bookId}_${safeChapterIndex}`;
        }

        this.bookName = ebook.metadata?.title || this.bookName;
        this.bookCoverUrl = ebook.metadata?.coverImagePath || this.bookCoverUrl;
        logger.info(TAG, `加载本地 TXT 小说章节列表成功: ebookId=${ebook.id}, count=${localChapters.length}`);
        this.syncOverallReadProgress('load_local_chapter_list');
        return;
      }

      const tocUrl = this.tocUrl || this.bookUrl;
      logger.info(TAG, `加载章节列表: tocUrl=${tocUrl}`);
      const sourceType = this.getCurrentSourceType();
      const book: LegadoBook = {
        id: '',
        type: sourceType,
        bookUrl: this.bookUrl,
        tocUrl: tocUrl,// 使用tocUrl加载章节列表
        name: this.bookName,
        author: '',
        origin: this.sourceId,
        originName: ''
      };
      const chapters = await this.sourceManager.getChapterList(this.sourceId, book);
      if (chapters && chapters.length > 0) {
        this.chapterList = chapters;
        this.totalChapters = chapters.length;
        let matchedChapterIndex = -1;
        for (let i = 0; i < chapters.length; i++) {
          const chapterItem = chapters[i];
          if (
            (this.chapterUrl.length > 0 && chapterItem.url === this.chapterUrl) ||
            (this.chapterId.length > 0 && chapterItem.id && chapterItem.id === this.chapterId)
          ) {
            matchedChapterIndex = i;
            break;
          }
        }
        if (matchedChapterIndex >= 0 && matchedChapterIndex !== this.currentChapterIndex) {
          logger.info(
            TAG,
            `对齐在线小说章节索引: oldIndex=${this.currentChapterIndex}, newIndex=${matchedChapterIndex}, chapterUrl=${this.chapterUrl}`
          );
          this.currentChapterIndex = matchedChapterIndex;
          this.chapterTitle = chapters[matchedChapterIndex].title;
          this.chapterId = `${this.bookId}_${matchedChapterIndex}`;
        }
        
        // 转换为TextChapter格式供TextReaderComponent使用
        this.chapters = chapters.map((chapter: LegadoChapter, index: number): TextChapter => {
          return {
            id: chapter.id || `chapter_${index}`,
            title: chapter.title,
            content: '', // 内容将在切换章节时加载
            wordCount: 0,
            index: index,
            startPosition: 0,// 小说章节独立加载，不需要全文位置
            endPosition: 0
          };
        });
        
        logger.info(TAG, `Loaded chapter list: ${chapters.length}`);
        this.syncOverallReadProgress('load_chapter_list');
      }
    } catch (error) {
      logger.error(TAG, `加载章节列表失败: ${String(error)}`);
    }
  }

  private cloneTextReaderSettings(settings: TextReaderSettings): TextReaderSettings {
    const snapshot = SafeUtils.parseObj(JSON.stringify(settings)) as TextReaderSettings;
    this.ensureSettingsComplete(snapshot);
    return snapshot;
  }

  private async persistSettingsSnapshot(snapshot: TextReaderSettings): Promise<void> {
    if (this.isLocalTxtNovelMode() && this.localEbookId.length > 0) {
      const ebook = await this.ensureLocalEbookLoaded();
      const ebookSettings = syncTextReaderSettingsToEBookSettings(snapshot, ebook?.readingSettings);
      await this.ebookDataManager.saveReadingSettings(this.localEbookId, ebookSettings);
      if (ebook) {
        ebook.readingSettings = ebookSettings;
      }
    }
    
    if (this.bookId) {
      const settingsKey = `${SettingKeys.NOVEL_READER_SETTINGS}_${this.bookId}`;
      await this.settingsManager.setJSON<TextReaderSettings>(settingsKey, snapshot);
      logger.debug(TAG, `保存书籍专属设置: ${this.bookId}`);
    } else {
      await this.settingsManager.setJSON<TextReaderSettings>(SettingKeys.NOVEL_READER_SETTINGS, snapshot);
      logger.debug(TAG, 'Saved global novel reader settings');
    }

    const readAloudSettings = normalizeReadAloudSettings(snapshot.readAloud ?? DEFAULT_TEXT_READER_SETTINGS.readAloud);
    const remoteSettings = readAloudSettings.remote;
    const hasRemoteApiKey = remoteSettings ? remoteSettings.apiKey.trim().length > 0 : false;
    logger.debug(
      TAG,
      `设置保存完成: target=${this.bookId.length > 0 ? this.bookId : 'global'}, engine=${readAloudSettings.engineType}, hasRemoteApiKey=${hasRemoteApiKey}`
    );
  }

  private async flushPendingSettingsSaves(): Promise<void> {
    try {
      while (this.pendingSettingsSnapshot !== null) {
        const snapshot = this.pendingSettingsSnapshot;
        this.pendingSettingsSnapshot = null;
        try {
          await this.persistSettingsSnapshot(snapshot);
        } catch (e) {
          logger.warn(TAG, `保存设置失败: ${String(e)}`);
        }
      }
    } finally {
      this.settingsSavePromise = null;
    }
  }

  private clearToolbarAutoHideTimer(): void {
    if (this.toolbarAutoHideTimer >= 0) {
      clearTimeout(this.toolbarAutoHideTimer);
      this.toolbarAutoHideTimer = -1;
    }
  }

  private hasReaderOverlayVisible(): boolean {
    return this.showChapterList ||
      this.showFontSettings ||
      this.showBackgroundSettings ||
      this.showReadingSettings ||
      this.showEncyclopediaDialog;
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
        logger.debug(TAG, `工具栏自动隐藏: reason=${reason}`);
        this.hideToolbarWithAnimation();
      }
    }, NovelReaderPage.TOOLBAR_AUTO_HIDE_DELAY_MS);
  }

  private clearFullscreenRestoreTimer(): void {
    if (this.fullscreenRestoreTimer >= 0) {
      clearTimeout(this.fullscreenRestoreTimer);
      this.fullscreenRestoreTimer = -1;
    }
  }

  private scheduleFullscreenRestore(reason: string, delayMs: number = 120): void {
    this.clearFullscreenRestoreTimer();
    this.fullscreenRestoreTimer = setTimeout(() => {
      this.fullscreenRestoreTimer = -1;
      logger.debug(TAG, `重新应用沉浸模式: reason=${reason}`);
      WindowManager.setDisplayMode(DisplayMode.FULL_IMMERSIVE, this.uiContext ?? undefined);
      WindowManager.reapplyCurrentDisplayMode(24);
      if (this.showTopToolbar || this.showBottomToolbar) {
        this.scheduleToolbarAutoHide(`fullscreen_restore_${reason}`);
      }
    }, delayMs);
  }

  private handleReaderOverlayClosed(reason: string): void {
    this.scheduleFullscreenRestore(reason);
    this.scheduleToolbarAutoHide(reason);
    this.tryShowQueuedInteractionHint(reason, 220);
  }

  async saveSettings(): Promise<void> {
    this.pendingSettingsSnapshot = this.cloneTextReaderSettings(this.settings);
    if (this.settingsSavePromise === null) {
      this.settingsSavePromise = this.flushPendingSettingsSaves();
    }
    return await this.settingsSavePromise;
  }

  onSettingsChange(newSettings: TextReaderSettings): void {
    const previousHintKey = this.getInteractionHintKey(this.settings);
    const sourceBackground = newSettings.background ?? this.settings.background;
    const sourceTextStyle = newSettings.textStyle ?? this.settings.textStyle;
    const sourcePageMargins = newSettings.pageMargins ?? this.settings.pageMargins;
    const sourceSavedBackgroundImages: SavedBackgroundImage[] =
      newSettings.savedBackgroundImages ?? [];

    const savedBackgroundImages: SavedBackgroundImage[] = [];
    for (let i = 0; i < sourceSavedBackgroundImages.length; i++) {
      const item = sourceSavedBackgroundImages[i];
      savedBackgroundImages.push({
        path: item.path,
        addTime: item.addTime
      });
    }

    const nextSettings: TextReaderSettings = {
      readingMode: newSettings.readingMode,
      readingDirection: newSettings.readingDirection,
      pageTurnAnimation: newSettings.pageTurnAnimation,
      background: {
        type: sourceBackground.type,
        color: sourceBackground.color,
        imagePath: sourceBackground.imagePath,
        imageOpacity: sourceBackground.imageOpacity,
        gradientStart: sourceBackground.gradientStart,
        gradientEnd: sourceBackground.gradientEnd,
        gradientAngle: sourceBackground.gradientAngle
      },
      savedBackgroundImages: savedBackgroundImages,
      textStyle: {
        fontSize: clampTextReaderFontSize(sourceTextStyle.fontSize),
        lineHeight: sourceTextStyle.lineHeight,
        paragraphSpacing: sourceTextStyle.paragraphSpacing,
        firstLineIndent: sourceTextStyle.firstLineIndent,
        letterSpacing: sourceTextStyle.letterSpacing,
        textColor: sourceTextStyle.textColor,
        fontWeight: sourceTextStyle.fontWeight,
        fontFamily: sourceTextStyle.fontFamily,
        fontPath: sourceTextStyle.fontPath,
        textAlignment: sourceTextStyle.textAlignment
      },
      pageMargins: {
        top: sourcePageMargins.top,
        bottom: sourcePageMargins.bottom,
        left: sourcePageMargins.left,
        right: sourcePageMargins.right
      },
      keepScreenOn: newSettings.keepScreenOn,
      lockDeviceOrientation: newSettings.lockDeviceOrientation ?? false,
      showPageNumber: newSettings.showPageNumber,
      showProgress: newSettings.showProgress,
      showTime: newSettings.showTime,
      showBattery: newSettings.showBattery,
      tapToTurn: newSettings.tapToTurn,
      volumeKeyNavigation: newSettings.volumeKeyNavigation,
      autoScrollSpeed: newSettings.autoScrollSpeed,
      autoPageTurnEnabled: newSettings.autoPageTurnEnabled,
      autoPageTurnInterval: newSettings.autoPageTurnInterval,
      curlBackOpacity: newSettings.curlBackOpacity,
      readAloud: normalizeReadAloudSettings(newSettings.readAloud ?? DEFAULT_TEXT_READER_SETTINGS.readAloud)
    };
    this.ensureSettingsComplete(nextSettings);

    const oldMode = this.lastReadingMode;
    const newMode = nextSettings.readingMode;
    
    // 异步保存设置（不阻塞UI）
    this.settings = nextSettings;
    // 检测阅读模式变化，处理双页模式的横屏切换和组件重载
    this.saveSettings();
    this.syncDeviceOrientationLock('settings_change');
    if (nextSettings.readAloud) {
      this.readAloudController.updateSettings(nextSettings.readAloud);
    }
    logger.debug(TAG, `设置已更新并保存`);
    
    // 检测阅读模式变化，处理双页模式的横屏切换和组件重载
    if (oldMode !== newMode) {
      this.lastReadingMode = newMode;
      this.handleReadingModeChange(oldMode, newMode);
    }

    if (previousHintKey !== this.getInteractionHintKey(nextSettings)) {
      this.queueInteractionHintIfNeeded(nextSettings);
      this.tryShowQueuedInteractionHint('settings_change', 260);
    }
  }
  
  /**
  * 处理阅读模式变化：双页模式需要强制横屏并重载组件
  */
  private handleReadingModeChange(oldMode: TextReadingMode, newMode: TextReadingMode): void {
    try {
      if (!this.uiContext) {
        this.uiContext = this.getUIContext();
      }
      const deviceOrientationLocked: boolean = this.settings.lockDeviceOrientation ??
        DEFAULT_TEXT_READER_SETTINGS.lockDeviceOrientation ??
        false;
      
      if (newMode === TextReadingMode.DUAL_PAGE) {
        // 延迟重载组件，等待横屏旋转完成
        logger.info(TAG, 'Screen orientation changed to landscape');
        if (!deviceOrientationLocked) {
          WindowManager.setPreferredOrientationLandscape(this.uiContext ?? undefined);
        }
        // 离开双页模式：恢复自动旋转 + 重载组件
        setTimeout(() => {
          this.readerKey++;
        }, 300);
      } else if (oldMode === TextReadingMode.DUAL_PAGE) {
        // 延迟重载组件，等待旋转完成
        logger.info(TAG, '离开双页模式，恢复自动旋转并重载组件');
        if (!deviceOrientationLocked) {
          WindowManager.setPreferredOrientationAuto(this.uiContext ?? undefined);
        }
        // 延迟重载组件，等待旋转完成
        setTimeout(() => {
          this.readerKey++;
        }, 300);
      }
    } catch (error) {
      logger.error(TAG, `处理阅读模式变化失败: ${String(error)}`);
    }
  }
  
  /**
  * 添加净化规则（从选中文本）
  */
  async addPurifyRule(pattern: string): Promise<void> {
    if (!pattern || pattern.trim().length === 0) {
      return;
    }

    const normalizedPattern = pattern.trim();
    try {
      await this.ensurePreloadSettingsLoaded();
      const ruleManager = NovelReplaceRuleManager.getInstance();
      await ruleManager.initialize();

      if (!this.replaceRulesEnabled) {
        await this.persistReplaceRulesEnabled(true, 'add_purify_rule_from_selection');
      }

      // 创建新规则
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
      logger.info(TAG, `已添加净化规则: ${normalizedPattern.substring(0, 50)}`);
      
      // 重新加载当前章节内容以应用新规则
      logger.info(
        TAG,
        `已添加净化规则并启用: ruleId=${createdRule.id}, chapterIndex=${this.currentChapterIndex}, pattern=${normalizedPattern.substring(0, 50)}`
      );
      await this.refreshCurrentChapterAfterPurifyRuleAdded('add_from_selection');
    } catch (error) {
      logger.error(TAG, `添加净化规则失败: ${String(error)}`);
    }
  }

  onPageChange(pageIndex: number, totalPages: number): void {
    logger.info(TAG, `onPageChange called: pageIndex=${pageIndex}, totalPages=${totalPages}, pendingSeekChapterIndex=${this.pendingSeekChapterIndex}, pendingSeekChapterFraction=${this.pendingSeekChapterFraction}, currentChapterIndex=${this.currentChapterIndex}`);
    this.currentPageIndex = pageIndex;
    this.currentChapterTotalPages = Math.max(0, totalPages);
    if (this.tryApplyPendingSeekPage(pageIndex, this.currentChapterTotalPages)) {
      this.syncOverallReadProgress('page_change_apply_pending_seek');
      this.refreshCurrentNovelBookmarkState('page_change_apply_pending_seek');
      return;
    }
    this.readAloudController.updatePageIndex(pageIndex);
    this.updateReadAloudContextByPosition();
    this.syncOverallReadProgress('page_change');
    this.refreshCurrentNovelBookmarkState('page_change');
    logger.info(TAG, `页面切换: ${pageIndex + 1}/${totalPages}`);

    // 页码变化立即落库，避免短时阅读/异常退出时进度丢失
    const now = Date.now();
    this.lastSaveTime = now;
    this.saveReadProgress();
  }

  onChapterChange(chapterIndex: number, switchIntent: TextChapterSwitchIntent = TextChapterSwitchIntent.DEFAULT): void {
    logger.info(TAG, `章节切换请求: ${chapterIndex}, intent=${switchIntent}`);
    void this.handleReaderChapterChange(chapterIndex, switchIntent);
  }

  private async handleReaderChapterChange(chapterIndex: number, switchIntent: TextChapterSwitchIntent): Promise<void> {
    const previousChapterIndex = this.currentChapterIndex;
    await this.saveReadProgress();

    let pendingChapterFraction = -1;
    if (switchIntent === TextChapterSwitchIntent.LAST_PAGE) {
      pendingChapterFraction = 0.9999;
    } else if (switchIntent === TextChapterSwitchIntent.FIRST_PAGE) {
      pendingChapterFraction = 0;
    } else if (chapterIndex < previousChapterIndex) {
      pendingChapterFraction = 0.9999;
    } else if (chapterIndex > previousChapterIndex) {
      pendingChapterFraction = 0;
    }

    await this.switchToChapter(chapterIndex, pendingChapterFraction);
  }

  /**
  * 切换到指定章节
  */
  async switchToChapter(chapterIndex: number, pendingChapterFraction: number = -1): Promise<void> {
    if (chapterIndex < 0 || chapterIndex >= this.totalChapters) {
      logger.warn(TAG, '章节列表为空，无法切换');
      return;
    }
    
    if (this.chapterList.length === 0) {
      logger.warn(TAG, 'Chapter list is empty, skip build');
      return;
    }
    
    const targetChapter = this.chapterList[chapterIndex];
    if (!targetChapter) {
      logger.warn(TAG, `找不到章节: ${chapterIndex}`);
      return;
    }
    
    // 更新当前章节信息
    this.currentChapterIndex = chapterIndex;
    this.chapterUrl = targetChapter.url;
    this.chapterTitle = targetChapter.title;
    this.chapterId = `${this.bookId}_${chapterIndex}`;
    this.pendingSeekChapterIndex = pendingChapterFraction >= 0 ? chapterIndex : -1;
    this.pendingSeekChapterFraction = pendingChapterFraction >= 0
      ? Math.max(0, Math.min(0.9999, pendingChapterFraction))
      : -1;
    logger.info(TAG, `switchToChapter: chapterIndex=${chapterIndex}, pendingChapterFraction=${pendingChapterFraction}, pendingSeekChapterIndex=${this.pendingSeekChapterIndex}, pendingSeekChapterFraction=${this.pendingSeekChapterFraction}`);
    // 不要在这里设置 currentPageIndex = 0，因为这会触发组件重建，
    // 导致 TextReaderComponent 的动画回调在组件销毁后仍然触发。
    // 页码重置由 TextReaderComponent 内部的 applyPostPaginationState 处理。
    this.isCurrentPageBookmarked = false;
    this.currentPageBookmarkId = '';
    this.stopCrossChapterPrefetch(false);
    this.syncOverallReadProgress('switch_chapter');

    // 重新加载内容
    await this.loadContent();
  }

  /**
  * 上一章
  */
  goToPreviousChapter(): void {
    if (this.currentChapterIndex > 0) {
      this.switchToChapter(this.currentChapterIndex - 1);
    }
  }

  /**
  * 下一章
  */
  goToNextChapter(): void {
    if (this.currentChapterIndex < this.totalChapters - 1) {
      this.switchToChapter(this.currentChapterIndex + 1);
    }
  }

  /**
  * 保存阅读进度
  */
  private calculateReadProgressPercent(): number {
    if (this.totalChapters <= 0) {
      return 0;
    }

    let chapterFraction = 0;
    const contentLength = this.content ? this.content.length : 0;
    if (contentLength > 0) {
      let anchorCharIndex = -1;
      if (this.readAloudCurrentCharIndex >= 0) {
        anchorCharIndex = this.readAloudCurrentCharIndex;
      } else if (this.currentPageEndCharIndex > this.currentPageStartCharIndex) {
        anchorCharIndex = this.currentPageEndCharIndex;
      } else {
        anchorCharIndex = this.currentPageStartCharIndex;
      }
      const safeAnchorCharIndex = Math.max(0, Math.min(Math.floor(anchorCharIndex), contentLength - 1));
      chapterFraction = Math.max(0, Math.min(1, (safeAnchorCharIndex + 1) / contentLength));
    } else if (this.currentChapterTotalPages > 0) {
      const safePageIndex = Math.max(0, Math.min(this.currentPageIndex, this.currentChapterTotalPages - 1));
      chapterFraction = Math.max(0, Math.min(1, (safePageIndex + 1) / this.currentChapterTotalPages));
    }

    const safeChapterIndex = Math.max(0, Math.min(this.currentChapterIndex, Math.max(0, this.totalChapters - 1)));
    const progressPercent = ((safeChapterIndex + chapterFraction) / this.totalChapters) * 100;
    return Math.max(0, Math.min(100, progressPercent));
  }

  private clampProgressPercent(value: number): number {
    if (!Number.isFinite(value)) {
      return 0;
    }
    return Math.max(0, Math.min(100, value));
  }

  private syncOverallReadProgress(trigger: string): void {
    const nextPercent = this.clampProgressPercent(this.calculateReadProgressPercent());
    if (Math.abs(nextPercent - this.overallReadProgressPercent) < 0.01) {
      return;
    }
    this.overallReadProgressPercent = nextPercent;
    logger.debug(TAG, `同步小说总进度: trigger=${trigger}, progress=${nextPercent.toFixed(2)}%`);
  }

  private getCurrentPageIndicatorText(): string {
    const safePageNumber = Math.max(1, this.currentPageIndex + 1);
    if (this.currentChapterTotalPages > 0) {
      const boundedPageNumber = Math.max(1, Math.min(safePageNumber, this.currentChapterTotalPages));
      return `P${boundedPageNumber}/${this.currentChapterTotalPages}`;
    }
    return `P${safePageNumber}`;
  }

  private getCurrentPagePercentText(): string {
    if (this.currentChapterTotalPages <= 0) {
      return '0%';
    }
    const safePageNumber = Math.max(1, Math.min(this.currentPageIndex + 1, this.currentChapterTotalPages));
    const percent = Math.round((safePageNumber / this.currentChapterTotalPages) * 100);
    return `${percent}%`;
  }

  private buildBottomProgressIndicatorText(): string {
    return `${this.getCurrentPageIndicatorText()} · ${this.getCurrentPagePercentText()} · 全书${this.overallReadProgressPercent.toFixed(1)}%`;
  }

  private tryApplyPendingSeekPage(currentPageIndex: number, totalPages: number): boolean {
    if (this.pendingSeekChapterIndex !== this.currentChapterIndex || this.pendingSeekChapterFraction < 0) {
      return false;
    }
    if (totalPages <= 0) {
      return false;
    }
    const safeFraction = Math.max(0, Math.min(0.9999, this.pendingSeekChapterFraction));
    const targetPageIndex = Math.max(0, Math.min(totalPages - 1, Math.floor(totalPages * safeFraction)));
    this.pendingSeekChapterIndex = -1;
    this.pendingSeekChapterFraction = -1;
    if (targetPageIndex === currentPageIndex) {
      return false;
    }
    this.currentPageIndex = targetPageIndex;
    logger.info(
      TAG,
      `应用跨章节进度定位: chapterIndex=${this.currentChapterIndex}, pageIndex=${targetPageIndex}, totalPages=${totalPages}`
    );
    return true;
  }

  private seekToOverallProgress(targetPercent: number): void {
    if (this.totalChapters <= 0) {
      return;
    }
    const safePercent = this.clampProgressPercent(targetPercent);
    const normalized = safePercent / 100;
    const chapterFloat = normalized * this.totalChapters;
    let targetChapterIndex = Math.floor(chapterFloat);
    if (targetChapterIndex >= this.totalChapters) {
      targetChapterIndex = this.totalChapters - 1;
    }
    targetChapterIndex = Math.max(0, targetChapterIndex);
    const chapterFraction = Math.max(0, Math.min(0.9999, chapterFloat - targetChapterIndex));

    if (targetChapterIndex === this.currentChapterIndex) {
      if (this.currentChapterTotalPages > 0) {
        const targetPageIndex = Math.max(
          0,
          Math.min(this.currentChapterTotalPages - 1, Math.floor(this.currentChapterTotalPages * chapterFraction))
        );
        if (targetPageIndex !== this.currentPageIndex) {
          this.currentPageIndex = targetPageIndex;
          logger.info(
            TAG,
            `小说进度条定位当前章节页: progress=${safePercent.toFixed(2)}%, chapterIndex=${targetChapterIndex}, pageIndex=${targetPageIndex}`
          );
        }
      }
      this.syncOverallReadProgress('seek_same_chapter');
      return;
    }

    logger.info(
      TAG,
      `小说进度条定位章节: progress=${safePercent.toFixed(2)}%, fromChapter=${this.currentChapterIndex}, toChapter=${targetChapterIndex}, fraction=${chapterFraction.toFixed(3)}`
    );
    void this.switchToChapter(targetChapterIndex, chapterFraction);
  }

  async saveReadProgress(): Promise<void> {
    if (!this.bookId) return;
    if (!this.isReadProgressReady) {
      logger.debug(TAG, `跳过保存阅读进度（尚未完成进度恢复）: 章节${this.currentChapterIndex}, 页面${this.currentPageIndex}`);
      return;
    }

    try {
      const candidateNow = Date.now();
      const now = candidateNow > this.lastProgressReadTime ? candidateNow : (this.lastProgressReadTime + 1);
      this.lastProgressReadTime = now;
      if (this.isLocalTxtNovelMode()) {
        const ebook = await this.ensureLocalEbookLoaded();
        if (!ebook || this.localEbookId.length <= 0) {
          return;
        }

        let totalReadingTime = ebook.readingProgress?.totalReadingTime ?? 0;
        if (this.readStartTime > 0) {
          const readingDuration = Math.floor((now - this.readStartTime) / 1000);
          if (readingDuration > 0) {
            totalReadingTime += readingDuration;
            this.readStartTime = now;
          }
        }

        const chapter = ebook.chapters[this.currentChapterIndex];
        const progress: EBookReadingProgress = {
          bookId: this.localEbookId,
          currentChapterId: chapter?.id || this.chapterUrl || '',
          currentChapterIndex: this.currentChapterIndex,
          currentPosition: this.currentPageIndex,
          domPos: this.buildLocalTextDomPos(this.currentPageIndex),
          progress: this.calculateReadProgressPercent(),
          lastReadTime: now,
          totalReadingTime: totalReadingTime
        };

        await this.ebookDataManager.saveReadingProgress(progress);
        ebook.readingProgress.currentChapterId = progress.currentChapterId;
        ebook.readingProgress.currentChapterIndex = progress.currentChapterIndex;
        ebook.readingProgress.currentPosition = progress.currentPosition;
        ebook.readingProgress.domPos = progress.domPos;
        ebook.readingProgress.progress = progress.progress;
        ebook.readingProgress.lastReadTime = progress.lastReadTime;
        ebook.readingProgress.totalReadingTime = progress.totalReadingTime;
        logger.debug(TAG, `保存本地 TXT 小说阅读进度: chapter=${this.currentChapterIndex}, page=${this.currentPageIndex}`);
        return;
      }
      const progress: NovelReadProgress = {
        bookId: this.bookId,
        chapterId: this.chapterId,
        chapterIndex: this.currentChapterIndex,
        position: this.currentPageIndex,
        progress: this.calculateReadProgressPercent(),
        readTime: now
      };
      
      await this.dataManager.saveReadProgress(progress);
      
      // 更新阅读时长（秒）
      if (this.readStartTime > 0) {
        const readingDuration = Math.floor((now - this.readStartTime) / 1000);
        if (readingDuration > 0) {
          await this.dataManager.updateReadingTime(this.bookId, readingDuration);
          this.readStartTime = now;// 重置开始时间，避免重复计算
        }
      }
      
      logger.debug(TAG, `保存阅读进度: 章节${this.currentChapterIndex}, 页面${this.currentPageIndex}`);
    } catch (error) {
      logger.error(TAG, `保存阅读进度失败: ${String(error)}`);
    }
  }

  /**
  * 加载阅读进度
  */
  async loadReadProgress(): Promise<void> {
    if (!this.bookId) return;
    
    try {
      if (this.isLocalTxtNovelMode()) {
        const ebook = await this.ensureLocalEbookLoaded();
        const progress = ebook?.readingProgress;
        if (progress && progress.currentChapterIndex === this.currentChapterIndex) {
          const parsedDomPos = this.parseLocalTextDomPos(progress.domPos);
          this.currentPageIndex = parsedDomPos?.pageIndex ?? Math.max(0, progress.currentPosition);
          if (parsedDomPos && parsedDomPos.charIndex >= 0) {
            this.readAloudCurrentCharIndex = parsedDomPos.charIndex;
          }
          logger.info(TAG, `恢复本地 TXT 小说阅读进度: chapter=${this.currentChapterIndex}, page=${this.currentPageIndex}`);
        }
        return;
      }

      const progress = await this.dataManager.getReadProgress(this.bookId);
      if (progress && progress.chapterIndex === this.currentChapterIndex) {
        // 同一章节，恢复页面位置
        this.currentPageIndex = progress.position;
        logger.info(TAG, `恢复阅读进度: 页面${progress.position}`);
      }
    } catch (error) {
      logger.error(TAG, `加载阅读进度失败: ${String(error)}`);
    }
  }

  /**
  * [修复] 记录浏览历史
  * 确保阅读过的小说出现在历史浏览中，即使没有加入书架
  */
  private getCurrentReadAloudResumeCharIndex(): number {
    if (this.readAloudCurrentCharIndex >= 0) {
      return this.readAloudCurrentCharIndex;
    }
    if (this.currentPageEndCharIndex > this.currentPageStartCharIndex) {
      return this.currentPageStartCharIndex;
    }
    return 0;
  }

  private getReadAloudResumeKey(): string {
    return `${NovelReaderPage.READ_ALOUD_RESUME_KEY_PREFIX}${this.bookId}_${this.currentChapterIndex}`;
  }

  private restoreReadAloudResumeCharIndex(): void {
    if (!this.bookId || !this.content || this.content.length <= 0) {
      return;
    }
    const persistedResumeCharIndex = Math.floor(this.settingsManager.getNumber(this.getReadAloudResumeKey(), -1));
    const resumeCharIndex = persistedResumeCharIndex >= 0
      ? persistedResumeCharIndex
      : Math.max(0, this.readAloudCurrentCharIndex);
    const maxCharIndex = Math.max(0, this.content.length - 1);
    this.readAloudCurrentCharIndex = Math.max(0, Math.min(resumeCharIndex, maxCharIndex));
  }

  private persistReadAloudResumeCharIndex(force: boolean): void {
    if (!this.bookId || !this.content || this.content.length <= 0) {
      return;
    }
    const now = Date.now();
    if (!force && (now - this.lastReadAloudResumePersistTime) < 1200) {
      return;
    }
    this.lastReadAloudResumePersistTime = now;
    const maxCharIndex = Math.max(0, this.content.length - 1);
    const resumeCharIndex = Math.max(
      0,
      Math.min(Math.floor(this.getCurrentReadAloudResumeCharIndex()), maxCharIndex)
    );
    this.settingsManager.setNumber(this.getReadAloudResumeKey(), resumeCharIndex).catch((error: Object | string) => {
      logger.warn(TAG, `保存听书恢复点失败: ${String(error)}`);
    });
  }

  private updateReadAloudContextByPosition(resumeCharIndex?: number): void {
    if (!this.bookId || !this.content || this.content.length <= 0) {
      return;
    }
    const maxCharIndex = Math.max(0, this.content.length - 1);
    const fallbackCharIndex = this.getCurrentReadAloudResumeCharIndex();
    const safeResumeCharIndex = Math.max(
      0,
      Math.min(Math.floor(resumeCharIndex ?? fallbackCharIndex), maxCharIndex)
    );
    this.readAloudController.updateContext({
      bookId: this.bookId,
      bookTitle: this.bookName,
      chapterIndex: this.currentChapterIndex,
      chapterTitle: this.chapterTitle,
      coverUrl: this.bookCoverUrl,
      content: this.content,
      pageIndex: this.currentPageIndex,
      resumeCharIndex: safeResumeCharIndex
    });
  }

  private syncReadAloudStateFromController(): void {
    if (!this.bookId) {
      return;
    }
    const context = this.readAloudController.getContextSnapshot();
    if (!context || context.bookId !== this.bookId) {
      this.readAloudPlaying = false;
      return;
    }
    const snapshot = this.readAloudController.getSnapshot();
    this.readAloudPlaying = snapshot.playbackState === ReadAloudPlaybackState.PLAYING;
    if (!this.content || this.content.length <= 0) {
      return;
    }
    const rawCharIndex = snapshot.currentCharIndex >= 0 ? snapshot.currentCharIndex : (context.resumeCharIndex ?? -1);
    if (rawCharIndex < 0) {
      return;
    }
    const maxCharIndex = Math.max(0, this.content.length - 1);
    this.readAloudCurrentCharIndex = Math.max(0, Math.min(Math.floor(rawCharIndex), maxCharIndex));
  }

  private applyReadAloudProgress(payload: ReadAloudStatePayload): void {
    if (!this.content || this.content.length <= 0) {
      return;
    }
    const payloadCharIndex = payload.currentCharIndex >= 0 ? payload.currentCharIndex : payload.chunkStartCharIndex;
    if (payloadCharIndex < 0) {
      return;
    }
    const maxCharIndex = Math.max(0, this.content.length - 1);
    this.readAloudCurrentCharIndex = Math.max(0, Math.min(Math.floor(payloadCharIndex), maxCharIndex));
    this.updateReadAloudContextByPosition();
    this.persistReadAloudResumeCharIndex(false);
  }

  private onTextPageCharRangeChange(startCharIndex: number, endCharIndex: number): void {
    this.currentPageStartCharIndex = Math.max(0, startCharIndex);
    this.currentPageEndCharIndex = Math.max(this.currentPageStartCharIndex, endCharIndex);
    if (this.readAloudCurrentCharIndex < 0) {
      this.readAloudCurrentCharIndex = this.currentPageStartCharIndex;
    }
    this.updateReadAloudContextByPosition();
    this.syncOverallReadProgress('page_char_range_change');
    this.refreshCurrentNovelBookmarkState('page_char_range_change');
  }

  private onTextUserPageTurnStart(): void {
    const snapshot = this.readAloudController.getSnapshot();
    if (!snapshot.settings.pauseOnManualPageTurn) {
      return;
    }
    if (snapshot.playbackState !== ReadAloudPlaybackState.PLAYING) {
      return;
    }
    this.readAloudController.pause('manual_page_turn');
    this.updateReadAloudContextByPosition();
    this.readAloudPlaying = false;
    this.persistReadAloudResumeCharIndex(true);
    this.saveReadProgress();
  }

  private onStartReadAloudFromCharIndex(charIndex: number): void {
    if (!this.content || this.content.length <= 0) {
      return;
    }
    const maxCharIndex = Math.max(0, this.content.length - 1);
    const safeCharIndex = Math.max(0, Math.min(Math.floor(charIndex), maxCharIndex));
    this.readAloudCurrentCharIndex = safeCharIndex;
    this.readAloudPlaying = true;
    this.updateReadAloudContextByPosition(safeCharIndex);
    this.persistReadAloudResumeCharIndex(false);

    const snapshot = this.readAloudController.getSnapshot();
    if (snapshot.playbackState === ReadAloudPlaybackState.PLAYING) {
      const baseCharIndex = snapshot.currentCharIndex >= 0 ? snapshot.currentCharIndex : safeCharIndex;
      this.readAloudController.seekByChars(safeCharIndex - baseCharIndex, 'selection_start');
    } else {
      this.readAloudController.start('selection_start');
      this.syncReadAloudStateFromController();
    }
    this.readAloudController.refreshMediaSession();
  }

  private tryHandleAutoReadAloudEntry(): void {
    if (!this.content || this.content.length <= 0) {
      return;
    }
    if (!this.shouldAutoStartReadAloud && !this.shouldAutoOpenReadAloudPlayer) {
      return;
    }

    if (this.getCurrentSourceType() === LegadoBookSourceType.AUDIO) {
      const shouldAutoStart = this.shouldAutoStartReadAloud || this.shouldAutoOpenReadAloudPlayer;
      this.shouldAutoStartReadAloud = false;
      this.shouldAutoOpenReadAloudPlayer = false;
      this.openNovelReadAloudPageFromReader(shouldAutoStart);
      return;
    }

    this.updateReadAloudContextByPosition();

    if (this.shouldAutoStartReadAloud) {
      this.readAloudController.start('read_aloud_page_auto_start');
      this.shouldAutoStartReadAloud = false;
    }

    if (this.shouldAutoOpenReadAloudPlayer) {
      this.shouldAutoOpenReadAloudPlayer = false;
      setTimeout(() => {
        this.openReadAloudPlayerPageFromReader();
      }, 60);
    }
  }

  private openNovelReadAloudPageFromReader(autoStart: boolean): void {
    const params: NovelReaderPageParams = {
      sourceId: this.sourceId,
      bookUrl: this.bookUrl,
      bookName: this.bookName,
      chapterUrl: this.chapterUrl,
      chapterTitle: this.chapterTitle,
      chapterIndex: this.currentChapterIndex,
      totalChapters: this.totalChapters,
      tocUrl: this.tocUrl || this.bookUrl,
      author: this.author,
      coverUrl: this.bookCoverUrl,
      coverComponentId: this.sourceCoverComponentId || undefined,
      autoStartReadAloud: autoStart
    };
    this.pathStack.pushPathByName('NovelReadAloudPage', params);
  }

  private openReadAloudPlayerPageFromReader(): void {
    const context = this.readAloudController.getContextSnapshot();
    if (!context || context.bookId !== this.bookId) {
      return;
    }
    const globalStack = AppStorage.get<NavPathStack>('GlobalNavStack');
    if (!globalStack) {
      logger.warn(TAG, 'GlobalNavStack not found, cannot open ReadAloudPlayerPage');
      return;
    }
    AppStorage.setOrCreate('ReadAloudPlayerReturnHostPage', 'NovelReaderPage');
    AppStorage.setOrCreate('ReadAloudPlayerReturnDisplayMode', WindowManager.getCurrentMode());
    AppStorage.setOrCreate('ReadAloudPlayerOpeningAt', Date.now());
    globalStack.pushPathByName('ReadAloudPlayerPage', undefined);
  }

  private async recordBrowseHistory(param: NovelReaderPageParams): Promise<void> {
    if (this.isLocalTxtNovelMode()) {
      return;
    }
    try {
      const settingsManager = getNovelSettingsManager();
      const historyInput: BrowseHistoryInput = {
        sourceId: param.sourceId,
        bookUrl: param.bookUrl,
        bookName: param.bookName,
        author: param.author || '',
        coverUrl: param.coverUrl || '',
        sourceName: param.sourceName || ''
      };
      await settingsManager.addBrowseHistory(historyInput);
      logger.debug(TAG, `已记录浏览历史: ${param.bookName}`);
    } catch (error) {
      logger.warn(TAG, `记录浏览历史失败: ${String(error)}`);
    }
  }
  
  /**
  * [修复] 确保书籍存在于数据库中（用于首页最近阅读显示）
  */
  private async ensureBookInDatabase(param: NovelReaderPageParams): Promise<void> {
    if (this.isLocalTxtNovelMode()) {
      return;
    }
    try {
      // 书籍不存在，创建新记录
      const existingBook = await this.dataManager.getBook(this.bookId);
      if (existingBook) {
        logger.debug(TAG, `书籍已存在于数据库: ${param.bookName}`);
        return;
      }
      
      // 书籍不存在，创建新记录
      const newBook: NovelBook = {
        id: this.bookId,
        sourceId: param.sourceId,
        sourceName: param.sourceName || '',
        bookUrl: param.bookUrl,
        name: param.bookName,
        author: param.author || '',
        kind: '',
        intro: '',
        coverUrl: param.coverUrl || '',
        coverLocalPath: '',
        tocUrl: param.tocUrl || param.bookUrl,
        latestChapterTitle: '',
        wordCount: '',
        chapterCount: param.totalChapters || 0,
        readStatus: NovelReadStatus.READING,
        lastReadChapterId: this.chapterId,
        lastReadChapterIndex: param.chapterIndex,
        lastReadPosition: 0,
        lastReadTime: Date.now(),
        totalReadingTime: 0,
        isFavorite: false,
        isPrivate: false,
        isNSFW: false,
        createTime: Date.now(),
        updateTime: Date.now(),
        updateDbTime: Date.now()
      };
      
      await this.dataManager.saveBook(newBook);
      logger.info(TAG, `已将书籍保存到数据库: ${param.bookName}`);
    } catch (error) {
      logger.warn(TAG, `保存书籍到数据库失败: ${String(error)}`);
    }
  }

  /**
  * 点击中间区域回调 - 显示/隐藏工具栏
  * TextReaderComponent 内部已经处理了点击区域判断，这里只需要切换工具栏状态
  */
  onTapCenter(): void {
    this.toggleToolbar();
  }

  private getNovelBookmarkPageLabel(): string {
    if (this.currentChapterTotalPages > 0) {
      const safePage = Math.max(1, Math.min(this.currentPageIndex + 1, this.currentChapterTotalPages));
      return `${safePage}/${this.currentChapterTotalPages}`;
    }
    return `${Math.max(1, this.currentPageIndex + 1)}`;
  }

  private buildNovelBookmarkTitle(): string {
    const chapterName = this.chapterTitle || `第${this.currentChapterIndex + 1}章`;
    return `${chapterName} · P${this.getNovelBookmarkPageLabel()}`;
  }

  private computeParagraphIndexByOffset(offset: number): number {
    if (!this.content || this.content.length <= 0) {
      return -1;
    }
    const safeOffset = Math.max(0, Math.min(Math.floor(offset), this.content.length - 1));
    let paragraphIndex = 0;
    for (let i = 0; i < safeOffset; i++) {
      const ch = this.content.charAt(i);
      if (ch === '\n') {
        paragraphIndex += 1;
      }
    }
    return paragraphIndex;
  }

  private resolveNovelBookmarkParagraphRange(): HighlightOffsetRange {
    const contentLength = this.content ? this.content.length : 0;
    const fallbackStart = Math.max(0, Math.floor(this.currentPageStartCharIndex));
    const fallbackEnd = Math.max(fallbackStart + 1, Math.floor(this.currentPageEndCharIndex));
    if (contentLength <= 0) {
      return {
        start: fallbackStart,
        end: fallbackEnd
      };
    }

    const safePageStart = Math.max(0, Math.min(fallbackStart, contentLength - 1));
    const safePageEnd = Math.max(
      safePageStart + 1,
      Math.min(Math.max(fallbackEnd, safePageStart + 1), contentLength)
    );
    let paragraphStart = safePageStart;
    for (let index = safePageStart - 1; index >= 0; index--) {
      const ch = this.content.charAt(index);
      if (ch === '\n' || ch === '\r') {
        paragraphStart = index + 1;
        break;
      }
      if (index === 0) {
        paragraphStart = 0;
      }
    }
    paragraphStart = Math.max(safePageStart, Math.min(paragraphStart, safePageEnd - 1));

    let paragraphEnd = safePageEnd;
    for (let index = paragraphStart; index < contentLength; index++) {
      const ch = this.content.charAt(index);
      if (ch === '\n' || ch === '\r') {
        paragraphEnd = index;
        break;
      }
      if (index >= safePageEnd - 1) {
        paragraphEnd = safePageEnd;
        break;
      }
    }
    paragraphEnd = Math.max(paragraphStart + 1, Math.min(paragraphEnd, safePageEnd));
    return {
      start: paragraphStart,
      end: paragraphEnd
    };
  }

  private buildCurrentNovelBookmarkAnchor(): AnnotationAnchor {
    const paragraphRange = this.resolveNovelBookmarkParagraphRange();
    const contentLength = this.content ? this.content.length : 0;
    let quoteText = '';
    if (contentLength > 0 && paragraphRange.end > paragraphRange.start) {
      quoteText = this.content.substring(paragraphRange.start, paragraphRange.end).trim();
    }
    const normalizedQuote = quoteText.length > 120 ? quoteText.substring(0, 120) : quoteText;
    const anchor = this.buildCurrentAnchor(normalizedQuote, paragraphRange.start, paragraphRange.end);
    anchor.paragraphIndex = this.computeParagraphIndexByOffset(paragraphRange.start);
    anchor.paragraphStartOffset = paragraphRange.start;
    anchor.paragraphEndOffset = paragraphRange.end;
    return anchor;
  }

  private isNovelBookmarkInCurrentPage(record: UnifiedAnnotationRecord): boolean {
    if (record.pageIndex >= 0 && record.pageIndex === this.currentPageIndex) {
      return true;
    }
    const pageStart = this.currentPageStartCharIndex;
    const pageEnd = this.currentPageEndCharIndex;
    if (pageEnd <= pageStart) {
      return false;
    }
    const recordStart = Math.max(0, Math.floor(record.startOffset));
    const recordEnd = Math.max(recordStart + 1, Math.floor(record.endOffset));
    if (record.startOffset >= 0 && record.endOffset >= 0 && recordStart < pageEnd && recordEnd > pageStart) {
      return true;
    }
    const anchorStart = typeof record.anchor.paragraphStartOffset === 'number'
      ? Math.max(0, Math.floor(record.anchor.paragraphStartOffset))
      : -1;
    const anchorEnd = typeof record.anchor.paragraphEndOffset === 'number'
      ? Math.max(anchorStart + 1, Math.floor(record.anchor.paragraphEndOffset))
      : -1;
    if (anchorStart >= 0 && anchorEnd > anchorStart && anchorStart < pageEnd && anchorEnd > pageStart) {
      return true;
    }
    return false;
  }

  private refreshCurrentNovelBookmarkState(trigger: string): void {
    void this.refreshCurrentNovelBookmarkStateInternal(trigger);
  }

  private async refreshCurrentNovelBookmarkStateInternal(trigger: string): Promise<void> {
    if (!this.bookId) {
      this.isCurrentPageBookmarked = false;
      this.currentPageBookmarkId = '';
      return;
    }
    try {
      const bookmarks = await this.annotationManager.getContentAnnotations(
        UnifiedContentType.NOVEL,
        this.bookId,
        UnifiedAnnotationType.BOOKMARK,
        this.chapterId,
        this.currentChapterIndex
      );
      let matchedId = '';
      for (let i = 0; i < bookmarks.length; i++) {
        const item = bookmarks[i];
        if (this.isNovelBookmarkInCurrentPage(item)) {
          matchedId = item.id;
          break;
        }
      }
      this.currentPageBookmarkId = matchedId;
      this.isCurrentPageBookmarked = matchedId.length > 0;
      logger.debug(
        TAG,
        `刷新小说书签状态: trigger=${trigger}, chapterIndex=${this.currentChapterIndex}, pageIndex=${this.currentPageIndex}, bookmarked=${this.isCurrentPageBookmarked}, bookmarkId=${matchedId || 'none'}`
      );
    } catch (error) {
      logger.error(TAG, `刷新小说书签状态失败: trigger=${trigger}, error=${String(error)}`);
      this.isCurrentPageBookmarked = false;
      this.currentPageBookmarkId = '';
    }
  }

  private async createCurrentNovelBookmark(): Promise<void> {
    if (!this.bookId) {
      this.getUIContext().getPromptAction().showToast({ message: '书籍信息未就绪', duration: 1500 });
      return;
    }
    try {
      const anchor = this.buildCurrentNovelBookmarkAnchor();
      const bookmark = await this.annotationManager.createBookmark({
        contentType: UnifiedContentType.NOVEL,
        contentId: this.bookId,
        title: this.buildNovelBookmarkTitle(),
        anchor
      });
      this.currentPageBookmarkId = bookmark.id;
      this.isCurrentPageBookmarked = true;
      this.getUIContext().getPromptAction().showToast({ message: '书签已添加', duration: 1200 });
      logger.info(
        TAG,
        `小说书签添加成功: chapterIndex=${this.currentChapterIndex}, pageIndex=${this.currentPageIndex}, paragraphIndex=${anchor.paragraphIndex ?? -1}, bookmarkId=${bookmark.id}`
      );
    } catch (error) {
      logger.error(TAG, `添加小说书签失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: '添加书签失败', duration: 1500 });
    }
  }

  private async removeCurrentNovelBookmark(): Promise<void> {
    let bookmarkId = this.currentPageBookmarkId;
    if (!bookmarkId || bookmarkId.trim().length <= 0) {
      await this.refreshCurrentNovelBookmarkStateInternal('remove_before_refresh');
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
      logger.info(
        TAG,
        `小说书签移除成功: chapterIndex=${this.currentChapterIndex}, pageIndex=${this.currentPageIndex}, bookmarkId=${bookmarkId}`
      );
    } catch (error) {
      logger.error(TAG, `移除小说书签失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: '移除书签失败', duration: 1500 });
    }
  }

  private toggleCurrentNovelBookmark(): void {
    if (this.isCurrentPageBookmarked) {
      void this.removeCurrentNovelBookmark();
      return;
    }
    void this.createCurrentNovelBookmark();
  }

  private buildCurrentAnchor(selectedText?: string, startOffset?: number, endOffset?: number): AnnotationAnchor {
    const hasTotalPages = this.currentChapterTotalPages > 0;
    const safePageIndex = Math.max(0, this.currentPageIndex);
    const pageProgress = hasTotalPages
      ? Math.max(0, Math.min(1, (safePageIndex + 1) / this.currentChapterTotalPages))
      : -1;
    const safeStart = typeof startOffset === 'number' ? Math.max(0, Math.floor(startOffset)) : -1;
    const safeEnd = typeof endOffset === 'number' ? Math.max(safeStart, Math.floor(endOffset)) : -1;
    const contentLength = this.content ? this.content.length : 0;
    let contextBefore = '';
    let contextAfter = '';
    if (contentLength > 0 && safeStart >= 0 && safeEnd > safeStart) {
      const clippedStart = Math.max(0, Math.min(safeStart, contentLength - 1));
      const clippedEnd = Math.max(clippedStart + 1, Math.min(safeEnd, contentLength));
      contextBefore = this.content.substring(Math.max(0, clippedStart - 18), clippedStart);
      contextAfter = this.content.substring(clippedEnd, Math.min(contentLength, clippedEnd + 18));
    }
    return {
      chapterId: this.chapterId,
      chapterTitle: this.chapterTitle,
      chapterIndex: this.currentChapterIndex,
      pageIndex: safePageIndex,
      progress: pageProgress,
      startOffset: safeStart,
      endOffset: safeEnd,
      quoteText: selectedText || '',
      contextBefore,
      contextAfter
    };
  }

  private parseHighlightColor(styleJson: string): string {
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

  private parseHighlightLineType(styleJson: string): HighlightLineType {
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

  private calculateContextMatchScore(position: number, quoteText: string, contextBefore: string, contextAfter: string): number {
    if (!this.content || this.content.length <= 0) {
      return 0;
    }
    let score = 0;
    const safeQuoteLength = quoteText.length;

    if (contextBefore.length > 0) {
      const beforeStart = Math.max(0, position - contextBefore.length);
      const actualBefore = this.content.substring(beforeStart, position);
      if (actualBefore === contextBefore) {
        score += contextBefore.length * 2;
      } else {
        let suffixMatch = 0;
        const minLen = Math.min(actualBefore.length, contextBefore.length);
        for (let i = 1; i <= minLen; i++) {
          const actualChar = actualBefore.charAt(actualBefore.length - i);
          const expectedChar = contextBefore.charAt(contextBefore.length - i);
          if (actualChar !== expectedChar) {
            break;
          }
          suffixMatch += 1;
        }
        score += suffixMatch;
      }
    }

    if (contextAfter.length > 0) {
      const afterStart = Math.min(this.content.length, position + safeQuoteLength);
      const afterEnd = Math.min(this.content.length, afterStart + contextAfter.length);
      const actualAfter = this.content.substring(afterStart, afterEnd);
      if (actualAfter === contextAfter) {
        score += contextAfter.length * 2;
      } else {
        let prefixMatch = 0;
        const minLen = Math.min(actualAfter.length, contextAfter.length);
        for (let i = 0; i < minLen; i++) {
          if (actualAfter.charAt(i) !== contextAfter.charAt(i)) {
            break;
          }
          prefixMatch += 1;
        }
        score += prefixMatch;
      }
    }

    return score;
  }

  private resolveHighlightOffsetRange(record: UnifiedAnnotationRecord): HighlightOffsetRange | null {
    const contentLength = this.content ? this.content.length : 0;
    if (contentLength <= 0) {
      return null;
    }

    let start = Math.max(0, Math.floor(record.startOffset));
    let end = Math.max(start + 1, Math.floor(record.endOffset));
    const hasValidStoredRange = end > start && start < contentLength;
    if (hasValidStoredRange) {
      start = Math.max(0, Math.min(start, contentLength - 1));
      end = Math.max(start + 1, Math.min(end, contentLength));
      const directRange: HighlightOffsetRange = {
        start,
        end
      };
      return directRange;
    }

    const quote = (record.quoteText || '').trim();
    if (quote.length <= 0) {
      return null;
    }

    const rawStart = Math.max(0, Math.floor(record.startOffset));
    const searchPivot = Math.max(0, Math.min(rawStart, contentLength - 1));
    const searchFrom = Math.max(0, searchPivot - 1200);
    const searchTo = Math.min(contentLength, searchPivot + 1200);
    const candidates: number[] = [];
    let cursor = this.content.indexOf(quote, searchFrom);
    while (cursor >= 0 && cursor < searchTo) {
      candidates.push(cursor);
      cursor = this.content.indexOf(quote, cursor + 1);
    }
    if (candidates.length <= 0) {
      let globalCursor = this.content.indexOf(quote);
      while (globalCursor >= 0 && candidates.length < 24) {
        candidates.push(globalCursor);
        globalCursor = this.content.indexOf(quote, globalCursor + 1);
      }
    }
    if (candidates.length <= 0) {
      return null;
    }

    const contextBefore = record.anchor && record.anchor.contextBefore ? record.anchor.contextBefore : '';
    const contextAfter = record.anchor && record.anchor.contextAfter ? record.anchor.contextAfter : '';
    let resolvedStart = candidates[0];
    let bestScore = -1;
    let nearestDistance = Number.MAX_SAFE_INTEGER;
    for (let i = 0; i < candidates.length; i++) {
      const candidate = candidates[i];
      const score = this.calculateContextMatchScore(candidate, quote, contextBefore, contextAfter);
      const distance = Math.abs(candidate - searchPivot);
      if (score > bestScore || (score === bestScore && distance < nearestDistance)) {
        bestScore = score;
        nearestDistance = distance;
        resolvedStart = candidate;
      }
    }

    start = resolvedStart;
    end = Math.min(contentLength, resolvedStart + quote.length);
    if (end <= start) {
      return null;
    }
    const resolvedRange: HighlightOffsetRange = {
      start: start,
      end: end
    };
    return resolvedRange;
  }

  private async refreshCurrentChapterHighlightRanges(trigger: string): Promise<void> {
    if (!this.bookId) {
      this.currentChapterHighlightRanges = [];
      logger.debug(TAG, `跳过刷新小说划线渲染数据: 书籍ID为空, trigger=${trigger}`);
      return;
    }
    try {
      const records = await this.annotationManager.getContentAnnotations(
        UnifiedContentType.NOVEL,
        this.bookId,
        UnifiedAnnotationType.HIGHLIGHT,
        this.chapterId,
        this.currentChapterIndex
      );
      const thoughtRecords = await this.annotationManager.getContentAnnotations(
        UnifiedContentType.NOVEL,
        this.bookId,
        UnifiedAnnotationType.THOUGHT,
        this.chapterId,
        this.currentChapterIndex
      );
      const thoughtByHighlightId: Map<string, string> = new Map<string, string>();
      const thoughtByAnchorKey: Map<string, string> = new Map<string, string>();
      for (let i = 0; i < thoughtRecords.length; i++) {
        const thoughtRecord = thoughtRecords[i];
        let thoughtSameChapter = false;
        if (thoughtRecord.chapterId && this.chapterId) {
          thoughtSameChapter = thoughtRecord.chapterId === this.chapterId;
        } else if (thoughtRecord.chapterIndex >= 0) {
          thoughtSameChapter = thoughtRecord.chapterIndex === this.currentChapterIndex;
        }
        if (!thoughtSameChapter) {
          continue;
        }
        const thoughtText = (thoughtRecord.textContent || '').trim();
        if (thoughtRecord.linkedAnnotationId && thoughtRecord.linkedAnnotationId.length > 0) {
          if (!thoughtByHighlightId.has(thoughtRecord.linkedAnnotationId)) {
            thoughtByHighlightId.set(thoughtRecord.linkedAnnotationId, thoughtText);
          }
        }
        const thoughtAnchorKey = `${Math.floor(thoughtRecord.startOffset)}_${Math.floor(thoughtRecord.endOffset)}_${thoughtRecord.quoteText || ''}`;
        if (!thoughtByAnchorKey.has(thoughtAnchorKey)) {
          thoughtByAnchorKey.set(thoughtAnchorKey, thoughtText);
        }
      }
      const ranges: TextReaderHighlightRange[] = [];
      let fallbackByQuoteCount = 0;
      let linkedThoughtCount = 0;
      for (let i = 0; i < records.length; i++) {
        const record = records[i];

        let sameChapter = false;
        if (record.chapterId && this.chapterId) {
          sameChapter = record.chapterId === this.chapterId;
        } else if (record.chapterIndex >= 0) {
          sameChapter = record.chapterIndex === this.currentChapterIndex;
        }
        if (!sameChapter) {
          continue;
        }

        const resolvedRange = this.resolveHighlightOffsetRange(record);
        const rawStart = Math.max(0, Math.floor(record.startOffset));
        const rawEnd = Math.max(rawStart + 1, Math.floor(record.endOffset));
        const quoteText = record.quoteText || '';
        const hasQuoteText = quoteText.trim().length > 0;
        if (!resolvedRange && !hasQuoteText) {
          continue;
        }
        if (!resolvedRange && hasQuoteText) {
          logger.debug(TAG, `小说划线偏移对齐失败，改用引用文本回退匹配: annotationId=${record.id}`);
          fallbackByQuoteCount += 1;
        }
        const finalStart = resolvedRange ? resolvedRange.start : rawStart;
        const finalEnd = resolvedRange ? resolvedRange.end : rawEnd;
        let thoughtText = thoughtByHighlightId.get(record.id) || '';
        if (thoughtText.length <= 0) {
          const finalAnchorKey = `${finalStart}_${finalEnd}_${quoteText}`;
          const rawAnchorKey = `${rawStart}_${rawEnd}_${quoteText}`;
          thoughtText = thoughtByAnchorKey.get(finalAnchorKey) || thoughtByAnchorKey.get(rawAnchorKey) || '';
        }
        if (thoughtText.trim().length > 0) {
          linkedThoughtCount += 1;
        }
        const range: TextReaderHighlightRange = {
          id: record.id,
          startOffset: finalStart,
          endOffset: finalEnd,
          color: this.parseHighlightColor(record.styleJson),
          lineType: this.parseHighlightLineType(record.styleJson),
          quoteText,
          pageIndex: record.pageIndex,
          thoughtText
        };
        ranges.push(range);
      }
      ranges.sort((a: TextReaderHighlightRange, b: TextReaderHighlightRange) => a.startOffset - b.startOffset);
      this.currentChapterHighlightRanges = ranges;
      const hasPageRange = this.currentPageEndCharIndex > this.currentPageStartCharIndex;
      const currentPageHitCount = hasPageRange
        ? ranges.filter((item: TextReaderHighlightRange) =>
            item.endOffset > this.currentPageStartCharIndex && item.startOffset < this.currentPageEndCharIndex
          ).length
        : -1;
      let preview = '';
      const previewCount = Math.min(3, ranges.length);
      for (let i = 0; i < previewCount; i++) {
        const item = ranges[i];
        preview += `${item.startOffset}-${item.endOffset}`;
        if (i < previewCount - 1) {
          preview += ', ';
        }
      }
      logger.info(TAG, `小说划线刷新摘要: trigger=${trigger}, quoteFallback=${fallbackByQuoteCount}, preview=[${preview}]`);
      logger.info(
        TAG,
        `刷新小说划线渲染数据成功: trigger=${trigger}, chapterIndex=${this.currentChapterIndex}, count=${ranges.length}, thoughtLinked=${linkedThoughtCount}, pageRange=${this.currentPageStartCharIndex}-${this.currentPageEndCharIndex}, hitInPage=${currentPageHitCount}`
      );
    } catch (error) {
      this.currentChapterHighlightRanges = [];
      logger.error(TAG, `刷新小说划线渲染数据失败: trigger=${trigger}, error=${String(error)}`);
    }
  }

  private addCurrentNovelBookmark(): void {
    this.toggleCurrentNovelBookmark();
  }

  private openCurrentNovelAnnotationCenter(): void {
    if (!this.bookId) {
      this.getUIContext().getPromptAction().showToast({ message: '书籍信息未就绪', duration: 1500 });
      return;
    }
    const params: AnnotationCenterPageParams = {
      contentType: UnifiedContentType.NOVEL,
      contentId: this.bookId,
      contentTitle: this.bookName,
      readerContext: {
        novel: {
          sourceId: this.sourceId,
          bookUrl: this.bookUrl,
          tocUrl: this.tocUrl
        }
      }
    };
    try {
      PageWindowCoordinator.navigateWithManagedTransition(
        'NovelReaderPage',
        'AnnotationCenterPage',
        () => {
          try {
            this.pathStack.pushPathByName('AnnotationCenterPage', params);
          } catch (error) {
            logger.error(TAG, `打开灵感页面失败: ${String(error)}`);
            this.getUIContext().getPromptAction().showToast({ message: '打开灵感页面失败', duration: 1500 });
          }
        },
        this.getUIContext()
      );
    } catch (error) {
      logger.error(TAG, `打开灵感页面失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: '打开灵感页面失败', duration: 1500 });
    }
  }

  private onAddNovelHighlight(selectedText: string, globalStart: number, globalEnd: number): void {
    logger.info(
      TAG,
      `触发小说划线指令: chapterIndex=${this.currentChapterIndex}, start=${globalStart}, end=${globalEnd}, textLength=${selectedText.length}`
    );
    void this.createNovelHighlightByStyle(selectedText, globalStart, globalEnd, false);
  }

  private onAddNovelHighlightWithThought(selectedText: string, globalStart: number, globalEnd: number): void {
    logger.info(
      TAG,
      `触发小说划线+想法指令: chapterIndex=${this.currentChapterIndex}, start=${globalStart}, end=${globalEnd}, textLength=${selectedText.length}`
    );
    void this.createNovelHighlightByStyle(selectedText, globalStart, globalEnd, true);
  }

  private onUpdateNovelHighlightStyle(highlightId: string, lineType: HighlightLineType, color: string): void {
    this.applyLocalNovelHighlightStyle(highlightId, lineType, color);
    void this.updateNovelHighlightStyle(highlightId, lineType, color);
  }

  private onUpdateNovelHighlightThought(highlightId: string, thoughtText: string): void {
    this.applyLocalNovelHighlightThought(highlightId, thoughtText);
    void this.updateNovelHighlightThought(highlightId, thoughtText);
  }

  private applyLocalNovelHighlightStyle(highlightId: string, lineType: HighlightLineType, color: string): void {
    if (!highlightId || highlightId.length <= 0 || this.currentChapterHighlightRanges.length <= 0) {
      return;
    }
    const safeColor = color && color.trim().length > 0 ? color : '#E8A317';
    let changed = false;
    const updatedRanges: TextReaderHighlightRange[] = [];
    for (let i = 0; i < this.currentChapterHighlightRanges.length; i++) {
      const item = this.currentChapterHighlightRanges[i];
      if (item.id === highlightId) {
        updatedRanges.push({
          id: item.id,
          startOffset: item.startOffset,
          endOffset: item.endOffset,
          color: safeColor,
          lineType,
          quoteText: item.quoteText,
          pageIndex: item.pageIndex,
          thoughtText: item.thoughtText
        });
        changed = true;
      } else {
        updatedRanges.push(item);
      }
    }
    if (changed) {
      this.currentChapterHighlightRanges = updatedRanges;
      logger.info(TAG, `小说划线样式本地刷新成功: highlightId=${highlightId}, lineType=${lineType}, color=${safeColor}`);
    }
  }

  private applyLocalNovelHighlightThought(highlightId: string, thoughtText: string): void {
    if (!highlightId || highlightId.length <= 0 || this.currentChapterHighlightRanges.length <= 0) {
      return;
    }
    const safeThoughtText = thoughtText.trim();
    let changed = false;
    const updatedRanges: TextReaderHighlightRange[] = [];
    for (let i = 0; i < this.currentChapterHighlightRanges.length; i++) {
      const item = this.currentChapterHighlightRanges[i];
      if (item.id === highlightId) {
        updatedRanges.push({
          id: item.id,
          startOffset: item.startOffset,
          endOffset: item.endOffset,
          color: item.color,
          lineType: item.lineType,
          quoteText: item.quoteText,
          pageIndex: item.pageIndex,
          thoughtText: safeThoughtText
        });
        changed = true;
      } else {
        updatedRanges.push(item);
      }
    }
    if (changed) {
      this.currentChapterHighlightRanges = updatedRanges;
      logger.info(TAG, `小说划线想法本地刷新成功: highlightId=${highlightId}, textLength=${safeThoughtText.length}`);
    }
  }

  private async updateNovelHighlightStyle(highlightId: string, lineType: HighlightLineType, color: string): Promise<void> {
    if (!this.bookId || !highlightId || highlightId.length <= 0) {
      return;
    }
    const safeColor = color && color.trim().length > 0 ? color : '#E8A317';
    logger.info(
      TAG,
      `开始更新小说划线样式: highlightId=${highlightId}, lineType=${lineType}, color=${safeColor}`
    );
    try {
      await this.annotationManager.updateHighlightStyle(highlightId, {
        lineType,
        color: safeColor
      });
      await this.refreshCurrentChapterHighlightRanges('update_highlight_style');
      logger.info(
        TAG,
        `小说划线样式更新成功: highlightId=${highlightId}, lineType=${lineType}, color=${safeColor}`
      );
    } catch (error) {
      logger.error(TAG, `更新小说划线样式失败: highlightId=${highlightId}, error=${String(error)}`);
    }
  }

  private async updateNovelHighlightThought(highlightId: string, thoughtText: string): Promise<void> {
    if (!this.bookId || !highlightId || highlightId.length <= 0) {
      return;
    }
    const safeThoughtText = thoughtText.trim();
    logger.info(
      TAG,
      `开始更新小说划线想法: highlightId=${highlightId}, textLength=${safeThoughtText.length}`
    );
    try {
      const linkedThought = await this.annotationManager.getLinkedThoughtByHighlightId(
        UnifiedContentType.NOVEL,
        this.bookId,
        highlightId
      );

      if (linkedThought) {
        await this.annotationManager.updateAnnotationText(linkedThought.id, linkedThought.title || '', safeThoughtText);
      } else if (safeThoughtText.length > 0) {
        const targetHighlight = await this.annotationManager.getAnnotationById(highlightId);
        if (!targetHighlight) {
          logger.warn(TAG, `更新小说划线想法失败: 未找到对应划线, highlightId=${highlightId}`);
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
          quoteText: targetHighlight.quoteText
        };
        await this.annotationManager.createThought({
          contentId: this.bookId,
          anchor,
          textContent: safeThoughtText,
          linkedAnnotationId: highlightId
        });
      }

      await this.refreshCurrentChapterHighlightRanges('update_highlight_thought');
      logger.info(
        TAG,
        `小说划线想法更新成功: highlightId=${highlightId}, textLength=${safeThoughtText.length}`
      );
    } catch (error) {
      logger.error(TAG, `更新小说划线想法失败: highlightId=${highlightId}, error=${String(error)}`);
    }
  }

  private async onAddNovelThought(selectedText: string, globalStart: number, globalEnd: number): Promise<void> {
    if (!this.bookId) {
      this.getUIContext().getPromptAction().showToast({ message: '书籍信息未就绪', duration: 1500 });
      return;
    }
    try {
      await this.annotationManager.createThought({
        contentId: this.bookId,
        anchor: this.buildCurrentAnchor(selectedText, globalStart, globalEnd),
        textContent: ''
      });
      await this.refreshCurrentChapterHighlightRanges('create_thought');
      this.getUIContext().getPromptAction().showToast({ message: '想法已保存', duration: 1500 });
    } catch (error) {
      logger.error(TAG, `创建小说想法失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: '想法保存失败', duration: 1500 });
    }
  }

  private async createNovelHighlightByStyle(
    selectedText: string,
    globalStart: number,
    globalEnd: number,
    withThought: boolean
  ): Promise<void> {
    if (!this.bookId) {
      this.getUIContext().getPromptAction().showToast({ message: '书籍信息未就绪', duration: 1500 });
      return;
    }

    const lineType = HighlightLineType.UNDERLINE;
    const color = '#E8A317';
    logger.info(
      TAG,
      `开始创建小说划线: chapterIndex=${this.currentChapterIndex}, start=${globalStart}, end=${globalEnd}, withThought=${withThought}`
    );

    try {
      const anchor = this.buildCurrentAnchor(selectedText, globalStart, globalEnd);
      const thoughtPayload: CreateThoughtInput | undefined = withThought
        ? {
            contentId: this.bookId,
            anchor: anchor,
            textContent: ''
          }
        : undefined;
      const highlight = await this.annotationManager.createHighlightWithThoughtTransaction({
        contentId: this.bookId,
        anchor,
        style: {
          lineType,
          color
        }
      }, thoughtPayload);
      logger.info(
        TAG,
        `小说划线创建成功: annotationId=${highlight.id}, chapterIndex=${this.currentChapterIndex}, start=${globalStart}, end=${globalEnd}`
      );

      if (withThought) {
        logger.info(TAG, `划线关联想法创建成功: linkedAnnotationId=${highlight.id}`);
      }

      await this.refreshCurrentChapterHighlightRanges('create_highlight');
      if (withThought) {
        this.getUIContext().getPromptAction().showToast({ message: '划线和想法已保存', duration: 1500 });
      } else {
        this.getUIContext().getPromptAction().showToast({ message: '划线已保存', duration: 1500 });
      }
    } catch (error) {
      logger.error(TAG, `创建小说划线失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: '划线保存失败', duration: 1500 });
    }
  }

  private createNovelHighlightByStyleLegacy(
    selectedText: string,
    globalStart: number,
    globalEnd: number,
    withThought: boolean
  ): void {
    if (!this.bookId) {
      this.getUIContext().getPromptAction().showToast({ message: '书籍信息未就绪', duration: 1500 });
      return;
    }

    this.getUIContext().getPromptAction().showActionMenu({
      title: '选择划线样式',
      buttons: [
        { text: '下划线-琥珀', color: '#007AFF' },
        { text: '下划线-蓝色', color: '#007AFF' },
        { text: '波浪线-琥珀', color: '#007AFF' },
        { text: '波浪线-蓝色', color: '#007AFF' },
        { text: '取消', color: '#999999' }
      ]
    }).then(async (result: promptAction.ActionMenuSuccessResponse) => {
      if (result.index < 0 || result.index > 3) {
        return;
      }
      const lineType = (result.index === 0 || result.index === 1) ? HighlightLineType.UNDERLINE : HighlightLineType.WAVY;
      const color = (result.index === 0 || result.index === 2) ? '#E8A317' : '#3B82F6';
      try {
        const highlight = await this.annotationManager.createHighlight({
          contentId: this.bookId,
          anchor: this.buildCurrentAnchor(selectedText, globalStart, globalEnd),
          style: {
            lineType,
            color
          }
        });
        if (withThought) {
          await this.annotationManager.createThought({
            contentId: this.bookId,
            anchor: this.buildCurrentAnchor(selectedText, globalStart, globalEnd),
            textContent: '',
            linkedAnnotationId: highlight.id
          });
          this.getUIContext().getPromptAction().showToast({ message: '划线和想法已保存', duration: 1500 });
        } else {
          this.getUIContext().getPromptAction().showToast({ message: '划线已保存', duration: 1500 });
        }
      } catch (error) {
        logger.error(TAG, `创建小说划线失败: ${String(error)}`);
        this.getUIContext().getPromptAction().showToast({ message: '划线保存失败', duration: 1500 });
      }
    }).catch(() => {});
  }

  async showEncyclopediaSearch(keyword: string): Promise<void> {
    this.encyclopediaKeyword = keyword;
    
    // 获取启用的字典规则
    const dictManager = NovelDictRuleManager.getInstance();
    await dictManager.initialize();
    const enabledRules = dictManager.getEnabledRules();
    
    if (enabledRules.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '没有启用的字典规则，请在设置中添加', duration: 2000 });
      return;
    }
    
    if (enabledRules.length === 1) {
      // 只有一个规则，直接使用
      this.openDictSearch(enabledRules[0], keyword);
    } else {
      // 多个规则，让用户选择（最多显示5个规则+取消按钮）
      const ruleCount = Math.min(enabledRules.length, 5);
      this.showDictSelectionMenu(enabledRules, ruleCount, keyword);
    }
  }
  
  /**
   * 显示字典选择菜单
   */
  private showDictSelectionMenu(rules: DictRule[], count: number, keyword: string): void {
    if (count === 2) {
      this.getUIContext().getPromptAction().showActionMenu({
        title: `搜索: ${keyword}`,
        buttons: [
          { text: rules[0].name, color: '#007AFF' },
          { text: rules[1].name, color: '#007AFF' },
          { text: '取消', color: '#999999' }
        ]
      }).then((result: promptAction.ActionMenuSuccessResponse) => {
        if (result.index < 2) {
          this.openDictSearch(rules[result.index], keyword);
        }
      }).catch(() => {});
    } else if (count === 3) {
      this.getUIContext().getPromptAction().showActionMenu({
        title: `搜索: ${keyword}`,
        buttons: [
          { text: rules[0].name, color: '#007AFF' },
          { text: rules[1].name, color: '#007AFF' },
          { text: rules[2].name, color: '#007AFF' },
          { text: '取消', color: '#999999' }
        ]
      }).then((result: promptAction.ActionMenuSuccessResponse) => {
        if (result.index < 3) {
          this.openDictSearch(rules[result.index], keyword);
        }
      }).catch(() => {});
    } else if (count === 4) {
      this.getUIContext().getPromptAction().showActionMenu({
        title: `搜索: ${keyword}`,
        buttons: [
          { text: rules[0].name, color: '#007AFF' },
          { text: rules[1].name, color: '#007AFF' },
          { text: rules[2].name, color: '#007AFF' },
          { text: rules[3].name, color: '#007AFF' },
          { text: '取消', color: '#999999' }
        ]
      }).then((result: promptAction.ActionMenuSuccessResponse) => {
        if (result.index < 4) {
          this.openDictSearch(rules[result.index], keyword);
        }
      }).catch(() => {});
    } else {
      // 5个或更多
      this.getUIContext().getPromptAction().showActionMenu({
        title: `搜索: ${keyword}`,
        buttons: [
          { text: rules[0].name, color: '#007AFF' },
          { text: rules[1].name, color: '#007AFF' },
          { text: rules[2].name, color: '#007AFF' },
          { text: rules[3].name, color: '#007AFF' },
          { text: rules[4].name, color: '#007AFF' },
          { text: '取消', color: '#999999' }
        ]
      }).then((result: promptAction.ActionMenuSuccessResponse) => {
        if (result.index < 5) {
          this.openDictSearch(rules[result.index], keyword);
        }
      }).catch(() => {});
    }
  }
  
  /**
   * 使用指定字典规则打开搜索
   */
  private openDictSearch(rule: DictRule, keyword: string): void {
    const dictManager = NovelDictRuleManager.getInstance();
    this.encyclopediaUrl = dictManager.buildSearchUrl(rule, keyword);
    this.showEncyclopediaDialog = true;
    logger.info(TAG, `字典搜索: ${rule.name} - ${keyword} -> ${this.encyclopediaUrl}`);
  }
  
  /**
   * 关闭百科搜索对话框
   */
  closeEncyclopediaDialog(): void {
    this.showEncyclopediaDialog = false;
    this.encyclopediaKeyword = '';
    this.encyclopediaUrl = '';
    this.handleReaderOverlayClosed('encyclopedia_close');
  }

  getBackgroundColor(): string {
    // 防御性检查：确保background对象存在且有type属性
    if (this.settings?.background?.type === BackgroundType.COLOR) {
      return this.settings.background.color || '#F5F0E1';
    }
    // 如果background存在但type不是COLOR，或者background不存在，返回默认颜色
    return this.settings?.background?.color || '#F5F0E1';
  }

  build() {
    NavDestination() {
      Stack() {
        // 背景层 - 扩展到系统栏区域实现完全沉浸式
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(this.getBackgroundColor())
          .id('guide_novel_reader_root')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        // 内容层 - 占满全屏
        Column() {
          if (this.isLoading) {
            this.buildLoadingView()
          } else {
            this.buildReaderView()
          }
        }
        .width('100%')
        .height('100%')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        if (this.showInteractionOverlay) {
          TextReaderInteractionOverlay({
            params: {
              readerLabel: '小说阅读器',
              readingMode: this.settings.readingMode,
              readingDirection: this.settings.readingDirection ?? TextReadingDirection.HORIZONTAL,
              tapToTurn: this.settings.tapToTurn,
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

        // 章节列表面板
        if (this.showChapterList) {
          this.buildChapterListPanel()
        }

        // 字体设置面板
        if (this.showFontSettings) {
          TextFontSettingsPanel({
            settings: this.settings,
            isVisible: this.showFontSettings,
            callbacks: {
              onSettingsChange: (newSettings: TextReaderSettings) => {
                this.onSettingsChange(newSettings);
              },
              onClose: () => {
                this.showFontSettings = false;
                this.handleReaderOverlayClosed('font_settings_close');
              }
            }
          })
            .zIndex(1000)
        }

        // 背景设置面板
        if (this.showBackgroundSettings) {
          TextBackgroundSettingsPanel({
            settings: this.settings,
            isVisible: this.showBackgroundSettings,
            callbacks: {
              onSettingsChange: (newSettings: TextReaderSettings) => {
                this.onSettingsChange(newSettings);
              },
              onClose: () => {
                this.showBackgroundSettings = false;
                this.handleReaderOverlayClosed('background_settings_close');
              }
            }
          })
            .zIndex(1000)
        }

        // 阅读设置面板
        if (this.showReadingSettings) {
          TextReadingSettingsPanel2({
            settings: this.settings,
            isVisible: this.showReadingSettings,
            initialShowReadAloudPanel: this.openReadAloudInfoWhenOpenReadingSettings,
            callbacks: {
              onSettingsChange: (newSettings: TextReaderSettings) => {
                this.onSettingsChange(newSettings);
              },
              onClose: () => {
                this.showReadingSettings = false;
                this.openReadAloudInfoWhenOpenReadingSettings = false;
                this.handleReaderOverlayClosed('reading_settings_close');
              }
            }
          })
            .zIndex(1000)
        }
        
        // 百科搜索对话框
        if (this.showEncyclopediaDialog) {
          this.buildEncyclopediaDialog()
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
      .id('novel_reader_root')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .onAreaChange((oldArea: Area, newArea: Area) => {
        const width = Number(newArea.width);
        const height = Number(newArea.height);
        if (width <= 0 || height <= 0) {
          return;
        }
        const widthChanged = Math.abs(width - this.readerViewportWidth) > 1;
        const heightChanged = Math.abs(height - this.readerViewportHeight) > 1;
        this.readerViewportWidth = width;
        this.readerViewportHeight = height;
        if ((widthChanged || heightChanged) && this.isPageVisible) {
          this.scheduleFullscreenRestore('area_change', 120);
          this.tryShowQueuedInteractionHint('area_change', 180);
        }
      })
    }
    .onReady((context: NavDestinationContext) => {
      logger.info(TAG, 'NavDestination.onReady 已触发');
      this.pathStack = context.pathStack;
      const param = context.pathInfo.param as NovelReaderPageParams | null;
      if (param) {
        this.sourceCoverComponentId = param.coverComponentId || '';
        this.readerHostMode = param.readerHostMode || '';
        this.readerInstanceId = param.readerInstanceId || '';
        this.sourceId = param.sourceId;
        this.localEbook = null;
        this.localEbookId = param.localEbookId
          || (isLocalTxtNovelReaderSource(param.sourceId) && param.bookUrl.startsWith('ebook://')
            ? param.bookUrl.substring('ebook://'.length)
            : '');
        this.bookUrl = param.bookUrl;
        this.bookName = param.bookName;
        this.author = param.author || '';
        this.chapterUrl = param.chapterUrl;
        this.chapterTitle = param.chapterTitle;
        this.currentChapterIndex = param.chapterIndex;
        this.totalChapters = param.totalChapters;
        if (typeof param.chapterPageIndex === 'number' && Number.isFinite(param.chapterPageIndex) && param.chapterPageIndex >= 0) {
          this.currentPageIndex = Math.floor(param.chapterPageIndex);
          logger.info(TAG, `应用小说定位页码参数: pageIndex=${this.currentPageIndex}`);
        }
        if (typeof param.chapterStartOffset === 'number' && Number.isFinite(param.chapterStartOffset) && param.chapterStartOffset >= 0) {
          this.currentPageStartCharIndex = Math.floor(param.chapterStartOffset);
          logger.info(TAG, `应用小说定位字符偏移参数: startOffset=${this.currentPageStartCharIndex}`);
        }
        this.tocUrl = param.tocUrl || param.bookUrl; // 使用传递的tocUrl或bookUrl
        // 生成bookId和chapterId
        const localBookIdentity = this.localEbookId.length > 0 ? this.localEbookId : encodeURIComponent(param.bookUrl);
        this.bookId = this.isLocalTxtNovelMode()
          ? buildLocalTextNovelBookId(localBookIdentity)
          : `${param.sourceId}_${encodeURIComponent(param.bookUrl)}`;
        this.chapterId = `${this.bookId}_${param.chapterIndex}`;
        this.bookCoverUrl = param.coverUrl || '';
        this.shouldAutoStartReadAloud = param.autoStartReadAloud === true;
        this.shouldAutoOpenReadAloudPlayer = param.autoOpenReadAloudPlayer === true;
        this.syncOverallReadProgress('on_ready_params');
        AppStorage.setOrCreate('ReadAloudCurrentHostPage', 'NovelReaderPage');
        void this.initializeReaderAfterReady();
        
        // [修复] 记录浏览历史，确保阅读过的小说出现在历史浏览中
        this.recordBrowseHistory(param);
        
        // [修复] 确保书籍存在于数据库中，用于首页最近阅读显示
        this.ensureBookInDatabase(param);
      }
      setTimeout(() => {
        void this.refreshPageGuide('onReady');
      }, 80);
    })
    .hideTitleBar(true)
    .onBackPressed(() => {
      // 返回键处理 - 调用 closeReader() 触发关闭过渡动画
      this.closeReader();
      return true;  // 返回 true 表示已处理返回事件
    })
  }

  /**
   * 构建加载视图
   */
  @Builder
  buildLoadingView() {
    Column() {
      LoadingProgress()
        .width(40)
        .height(40)
        .color($r('app.color.accent_primary'))
      Text('加载中...')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 12 })
        .fontFamily(this.appFontFamily)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.getBackgroundColor())
  }

  /**
   * 构建阅读器视图
   * 使用 readerKey 控制组件重建，切换双页模式时强制重新创建组件触发重新排版
   */
  @Builder
  buildReaderView() {
    TextReaderComponent({
      content: this.content,
      chapters: this.chapters,
      settings: this.settings,
      currentChapterIndex: this.currentChapterIndex,
      currentPageIndex: this.currentPageIndex,
      readAloudCurrentCharIndex: this.readAloudCurrentCharIndex,
      readAloudFollowEnabled: this.readAloudPlaying,
      readAloudHighlightEnabled: this.readAloudPlaying,
      bottomStatusBarHeight: 0,
      enableNovelAnnotations: true,
      novelHighlightRanges: this.currentChapterHighlightRanges,
      paginationMode: this.getReaderPaginationMode(),
      pendingSeekChapterIndex: this.pendingSeekChapterIndex,
      pendingSeekChapterFraction: this.pendingSeekChapterFraction,
      onPageChange: (pageIndex: number, totalPages: number) => this.onPageChange(pageIndex, totalPages),
      onPageCharRangeChange: (startCharIndex: number, endCharIndex: number) => {
        this.onTextPageCharRangeChange(startCharIndex, endCharIndex);
      },
      onUserPageTurnStart: () => {
        this.onTextUserPageTurnStart();
      },
      onChapterChange: (chapterIndex: number, switchIntent?: TextChapterSwitchIntent) =>
        this.onChapterChange(chapterIndex, switchIntent),
      onTapCenter: () => this.onTapCenter(),
      onReady: () => {
        // 文本阅读器分页完成，通知过渡动画阅读器就绪
        logger.info(TAG, '📖 文本阅读器分页完成，通知过渡动画');
        this.reportTransitionLoadingProgress(0.96, 'text_reader_ready');
        this.notifyTransitionReaderReadyOnce('TextReaderComponent.onReady');
        this.queueInteractionHintIfNeeded(this.settings);
        this.tryShowQueuedInteractionHint('text_reader_ready', 120);
      },
      onAddPurifyRule: (pattern: string) => this.addPurifyRule(pattern),
      onSearchEncyclopedia: (keyword: string) => this.showEncyclopediaSearch(keyword),
      onStartReadAloudFromCharIndex: (charIndex: number) => this.onStartReadAloudFromCharIndex(charIndex),
      onAddHighlight: (selectedText: string, globalStart: number, globalEnd: number) =>
        this.onAddNovelHighlight(selectedText, globalStart, globalEnd),
      onAddHighlightWithThought: (selectedText: string, globalStart: number, globalEnd: number) =>
        this.onAddNovelHighlightWithThought(selectedText, globalStart, globalEnd),
      onAddThought: (selectedText: string, globalStart: number, globalEnd: number) =>
        this.onAddNovelThought(selectedText, globalStart, globalEnd),
      onUpdateHighlightStyle: (highlightId: string, lineType: HighlightLineType, color: string) =>
        this.onUpdateNovelHighlightStyle(highlightId, lineType, color),
      onUpdateHighlightThought: (highlightId: string, thoughtText: string) =>
        this.onUpdateNovelHighlightThought(highlightId, thoughtText)
    })
      .width('100%')
      .height('100%')
      .id(`novel_reader_component_${this.readerKey}`)
  }

  /**
   * 构建顶部工具栏
   */
  @Builder
  buildTopToolbar() {
    Row() {
      // 返回按钮
      Button() {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(24)
          .fontColor([$r('app.color.text_primary')])
      }
      .width(48)
      .height(48)
      .backgroundColor(Color.Transparent)
      .onClick(() => this.closeReader())

      // 书名
      Text(this.bookName)
        .fontSize(18)
        .fontFamily(this.appFontFamily)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .margin({ left: 12 })

      Button() {
        SymbolGlyph(this.isCurrentPageBookmarked ? $r('sys.symbol.bookmark_fill') : $r('sys.symbol.bookmark'))
          .fontSize(20)
          .fontColor([this.isCurrentPageBookmarked ? $r('app.color.accent_primary') : $r('app.color.text_primary')])
      }
      .width(48)
      .height(48)
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        this.addCurrentNovelBookmark();
      })

      Button() {
        SymbolGlyph($r('sys.symbol.stickers'))
          .fontSize(20)
          .fontColor([$r('app.color.text_primary')])
      }
      .width(48)
      .height(48)
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        this.openCurrentNovelAnnotationCenter();
      })
    }
    .width('100%')
    .height(ReaderSafeAreaUtils.getTopToolbarHeight(this.statusBarHeight))
    .padding({ left: 8, right: 8, top: ReaderSafeAreaUtils.getStatusBarInset(this.statusBarHeight) })
    .backgroundColor(this.themeManager.getGlassBackgroundResource())
    .backgroundBlurStyle(this.themeManager.getGlassBlurStyle())
    .shadow({ radius: this.themeManager.getGlassRadius(), color: this.themeManager.getGlassShadowColor(), offsetX: 0, offsetY: 4 })
    .opacity(this.toolbarOpacity)
    .id('guide_novel_reader_top_toolbar')
  }

  /**
   * 构建底部工具栏
   */
  @Builder
  buildBottomToolbar() {
    Column() {
      // 章节信息
      Row() {
        Text(this.chapterTitle)
          .fontSize(13)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
          .fontFamily(this.appFontFamily)
        
        Text(this.buildBottomProgressIndicatorText())
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .fontFamily(this.appFontFamily)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 4 })

      // 章节进度条
      Row() {
        Slider({
          value: this.overallReadProgressPercent,
          min: 0,
          max: 100,
          step: 0.1
        })
          .layoutWeight(1)
          .trackColor($r('app.color.divider_primary'))
          .selectedColor($r('app.color.accent_primary'))
          .onChange((value: number, mode: SliderChangeMode) => {
            if (mode === SliderChangeMode.End) {
              this.seekToOverallProgress(value);
            }
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16 })

      // 控制按钮
      Row() {
        // 目录按钮
        Button() {
          SymbolGlyph($r('sys.symbol.list_bullet'))
            .fontColor([$r('app.color.text_primary')])

        }
        .width(48)
        .height(48)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.hideToolbarWithAnimation();
          this.showChapterListWithAnimation();
        })

        Blank()

        // 字体设置按钮
        Button() {
          SymbolGlyph($r('sys.symbol.textformat'))
            .fontColor([$r('app.color.text_primary')])

        }
        .width(48)
        .height(48)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.showFontSettingsPanel();
        })

        Blank()

        // 背景设置按钮
        Button() {
          SymbolGlyph($r('sys.symbol.paintbrush'))
            .fontColor([$r('app.color.text_primary')])

        }
        .width(48)
        .height(48)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.showBackgroundSettingsPanel();
        })

        Blank()

        // 阅读设置按钮
        Button() {
          SymbolGlyph($r('sys.symbol.gearshape'))
            .fontColor([$r('app.color.text_primary')])
        }
        .width(48)
        .height(48)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.showReadingSettingsPanel();
        })

        Blank()

        // 听书胶囊区域
        Row() {
          Row() {
            SymbolGlyph(this.readAloudPlaying ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'))
              .fontSize(18)
              .fontColor([this.readAloudPlaying ? Color.White : $r('app.color.text_primary')])
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
            SymbolGlyph($r('sys.symbol.Celia'))
              .fontSize(16)
              .fontColor([this.readAloudPlaying ? Color.White : $r('app.color.text_primary')])
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


      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: this.navigationBarHeight })
    }
    .width('100%')
    .backgroundColor(this.themeManager.getGlassBackgroundResource())
    .backgroundBlurStyle(this.themeManager.getGlassBlurStyle())
    .shadow({ radius: this.themeManager.getGlassRadius(), color: this.themeManager.getGlassShadowColor(), offsetX: 0, offsetY: -2 })
    .opacity(this.toolbarOpacity)
    .id('guide_novel_reader_bottom_toolbar')
  }

  /**
   * 构建章节列表面板
   */
  @Builder
  buildChapterListPanel() {
    Stack() {
      // 点击遮罩关闭
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.5)')
        .opacity(this.chapterListOpacity)
        .onClick(() => {
          this.hideChapterListWithAnimation();
        })

      // 章节列表
      Column() {
        // 标题
        Row() {
          Text('目录')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor($r('app.color.text_primary'))
          Blank()
          Text(`共${this.totalChapters}章`)
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .fontFamily(this.appFontFamily)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 12 })

        // 章节列表
        List({ scroller: this.chapterListScroller }) {
          ForEach(this.chapterList, (chapter: LegadoChapter, index: number) => {
            ListItem() {
              Row() {
                Text(chapter.title)
                  .fontSize(15)
                  .fontFamily(this.appFontFamily)
                  .fontColor(index === this.currentChapterIndex ? $r('app.color.accent_primary') : $r('app.color.text_primary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
              }
              .width('100%')
              .height(48)
              .padding({ left: 16, right: 16 })
              .backgroundColor(index === this.currentChapterIndex ? '#1A1890FF' : Color.Transparent)
              .onClick(() => {
                this.hideChapterListWithAnimation();
                this.switchToChapter(index);
              })
            }
          })
        }
        .width('100%')
        .layoutWeight(1)
        .divider({ strokeWidth: 0.5, color: $r('app.color.divider_primary') })
      }
      .width('85%')
      .height('100%')
      .backgroundColor(this.themeState.currentTheme === ThemeType.DARK ? '#1E1E1E' : '#FFFFFF')
      .opacity(this.chapterListOpacity)
      .position({ x: 0, y: 0 })
      .id('guide_novel_reader_chapter_list')
    }
    .width('100%')
    .height('100%')
  }


  toggleNightMode(): void {
    // 防御性检查：确保background对象存在
    if (!this.settings.background) {
      this.settings.background = { type: BackgroundType.COLOR, color: '#F5F0E1' };
    }
    const isDark = this.settings.background.color === '#1E1E1E';
    if (isDark) {
      // 切换到护眼黄
      this.settings.background.color = '#F5F0E1';
      this.settings.textStyle.textColor = '#5D4037';
    } else {
      // 切换到深色
      this.settings.background.color = '#1E1E1E';
      this.settings.textStyle.textColor = '#D4D4D4';
    }
    this.saveSettings();
  }
  
  /**
   * 构建百科搜索对话框
   */
  @Builder
  buildEncyclopediaDialog() {
    Stack() {
      // 遮罩层
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.5)')
        .onClick(() => {
          this.closeEncyclopediaDialog();
        })
        .transition(TransitionEffect.opacity(0).animation({ duration: 250, curve: Curve.EaseOut }))
      
      // 对话框内容
      Column() {
        // 标题栏
        Row() {
          Text(`百科搜索: ${this.encyclopediaKeyword}`)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          
          Button() {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(20)
              .fontColor([$r('app.color.text_secondary')])
          }
          .width(36)
          .height(36)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.closeEncyclopediaDialog();
          })
        }
        .width('100%')
        .padding({ left: 16, right: 8, top: 12, bottom: 8 })
        
        Divider()
          .color($r('app.color.divider_primary'))
        
        // WebView内容区
        Web({ src: this.encyclopediaUrl, controller: this.encyclopediaWebController })
          .width('100%')
          .layoutWeight(1)
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .mixedMode(MixedMode.All)
          .onPageBegin(() => {
            logger.debug(TAG, `百科页面开始加载: ${this.encyclopediaUrl}`);
          })
          .onPageEnd(() => {
            logger.debug(TAG, '百科页面加载完成');
          })
          .onErrorReceive((event) => {
            if (event && event.error) {
              logger.warn(TAG, `百科页面加载错误: ${event.error.getErrorInfo()}`);
            }
          })
      }
      .width('90%')
      .height('80%')
      .backgroundColor($r('app.color.background'))
      .borderRadius(16)
      .clip(true)
      .shadow({
        radius: 20,
        color: 'rgba(0,0,0,0.2)',
        offsetX: 0,
        offsetY: 4
      })
      .transition(TransitionEffect.scale({ x: 0.9, y: 0.9 }).combine(TransitionEffect.opacity(0)).animation({ duration: 250, curve: Curve.EaseOut }))
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Center)
    .zIndex(200)
  }
}

