/**
 * 小说阅读器页面
 * 使用 TextReaderComponent 实现专业的文本阅读体验
 * 支持翻页动画、自定义背景、字体设置等
 * 采用与电子书阅读器一致的沉浸式设计风格
 * 
 * 文件路径: entry/src/main/ets/pages/NovelReaderPage.ets
  */

import { logger } from '../Utils/Logger';
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
import { 
  TextReaderSettings, 
  DEFAULT_TEXT_READER_SETTINGS,
  DEFAULT_TEXT_STYLE,
  TextChapter,
  TextReadingMode,
  BackgroundType,
  PageMargins,
  TextAlignment,
  SavedBackgroundImage
} from '../Models/TextReaderModels';
import { NovelReadProgress } from '../Models/NovelModels';
import { UnifiedContentType } from '../Models/UnifiedContentModels';
import { AnnotationAnchor, HighlightLineType, HighlightStyle, UnifiedAnnotationType, UnifiedAnnotationRecord } from '../Models/AnnotationModels';
import { SettingsManager, SettingKeys } from '../Framework/Managers/SettingsManager';
import { getNovelSettingsManager, BrowseHistoryInput } from '../Framework/Novel/NovelSettingsManager';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';
import { PageLifecycleManager } from '../Framework/Lifecycle';
import { WindowManager, DisplayMode } from '../Utils/WindowManager';
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

@Component
export struct NovelReaderPage {
  private static readonly READ_ALOUD_RESUME_KEY_PREFIX: string = 'novel_read_aloud_resume_char_';

  @State pathStack: NavPathStack = new NavPathStack();
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  private lifecycle = new PageLifecycleManager('NovelReaderPage', { enableDebug: true });
  private componentId: string = 'NovelReaderPage';
  private themeManager: ThemeManager = ThemeManager.getInstance();

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
  @State currentChapterHighlightRanges: TextReaderHighlightRange[] = [];
  private previousDisplayMode: DisplayMode = DisplayMode.DEFAULT;
  private sourceCoverComponentId: string = '';
  private hasNotifiedTransitionReaderReady: boolean = false;
  private isCloseTransitionNavigating: boolean = false;

  // 3个独立设置面板
  @State showTopToolbar: boolean = false;
  @State showBottomToolbar: boolean = false;
  @State toolbarOpacity: number = 0.0;
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
  
  // 章节列表滚动控制器
  @State showEncyclopediaDialog: boolean = false;
  @State encyclopediaKeyword: string = '';
  @State encyclopediaUrl: string = '';

  // 百科搜索WebView控制器
  private chapterListScroller: Scroller = new Scroller();
  // 百科搜索WebView控制器
  private encyclopediaWebController: webview.WebviewController = new webview.WebviewController();

  private sourceId: string = '';
  private bookUrl: string = '';
  private bookName: string = '';
  private bookCoverUrl: string = '';
  private chapterUrl: string = '';
  private bookId: string = '';
  private chapterId: string = '';
  private tocUrl: string = ''; // 目录URL
  private chapterList: LegadoChapter[] = [];// 完整章节列表
  private sourceManager = getNovelSourceManager();
  private dataManager = getNovelDataManager();
  private annotationManager = getUnifiedAnnotationManager();
  private cacheManager = getNovelChapterCacheManager();
  private settingsManager: SettingsManager = SettingsManager.getInstance();
  private readAloudController: ReadAloudController = ReadAloudController.getInstance();
  private readStartTime: number = 0;
  private lastSaveTime: number = 0;
  private lastProgressReadTime: number = 0;
  private uiContext: UIContext | null = null;
  private saveProgressInterval: number = 30000;// 30秒自动保存
  private readAloudProgressSaveInterval: number = 4000;
  private transitionLoadingProgress: number = 0;
  private currentChapterTotalPages: number = 0;
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
  private preparsedChapterContent: Map<number, string> = new Map<number, string>();
  private prefetchingChapterIndexes: Set<number> = new Set<number>();

  private onReadAloudStateChanged: (payload: IEventPayload) => void = (payload: IEventPayload): void => {
    if (!this.bookId) {
      return;
    }
    const statePayload = payload as ReadAloudStatePayload;
    const payloadBookId = statePayload.bookId ?? '';
    if (!payloadBookId || payloadBookId !== this.bookId) {
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
    eventBus.subscribe(GameEvent.READ_ALOUD_STATE_CHANGED, this.onReadAloudStateChanged);
    AppStorage.setOrCreate('ReadAloudCurrentHostPage', 'NovelReaderPage');
    this.syncReadAloudStateFromController();
    this.readAloudController.refreshMediaSession();
  }

  aboutToDisappear(): void {
    eventBus.unsubscribe(GameEvent.READ_ALOUD_STATE_CHANGED, this.onReadAloudStateChanged);
    this.persistReadAloudResumeCharIndex(true);
    this.stopCrossChapterPrefetch(true);
    logger.lifecycle(TAG, 'aboutToDisappear - release resources');
    this.lifecycle.destroy();
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    FontAwareHelper.cleanupFontAware(this.componentId);
    // 离开页面时恢复自动旋转（防止双页模式强制横屏残留）
    this.saveReadProgress();
    // 关闭动画主动返回时，不要在这里中断过渡层
    this.restoreNormalMode();
    // 关闭动画主动返回时，不要在这里中断过渡层
    WindowManager.setPreferredOrientationAuto(this.uiContext ?? undefined);
    // 关闭动画主动返回时，不要在这里中断过渡层
    // 关闭动画主动返回时，不要在这里中断过渡层
    if (!this.isCloseTransitionNavigating) {
      cancelTransition();
    } else {
      logger.info(TAG, '页面销毁：关闭动画进行中，跳过cancelTransition');
    }
  }

  onPageShow(): void {
    this.setupFullscreenMode();
    AppStorage.setOrCreate('ReadAloudCurrentHostPage', 'NovelReaderPage');
    this.syncReadAloudStateFromController();
    this.updateReadAloudContextByPosition();
    this.readAloudController.refreshMediaSession();
  }

  onPageHide(): void {
    this.restoreNormalMode();
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
      WindowManager.setDisplayMode(DisplayMode.FULL_IMMERSIVE, this.uiContext);
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
  private async closeReader(): Promise<void> {
    // Save progress before triggering close transition.
    this.saveReadProgress();

    // Resolve source cover id for close animation target.
    const coverComponentId = this.sourceCoverComponentId || `novel_cover_${this.bookId}`;

    try {
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
      this.pathStack.pop();
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
    this.showTopToolbar = true;
    this.showBottomToolbar = true;
    animateTo({
      duration: 250,
      curve: curves.springMotion(0.5, 0.8)
    }, () => {
      this.toolbarOpacity = 1.0;
    });
  }

  /**
  * 隐藏工具栏（带动画）
  */
  private hideToolbarWithAnimation(): void {
    animateTo({
      duration: 200,
      curve: Curve.EaseOut
    }, () => {
      this.toolbarOpacity = 0.0;
    });
    setTimeout(() => {
      this.showTopToolbar = false;
      this.showBottomToolbar = false;
    }, 200);
  }

  /**
  * 显示章节列表（带动画）
  */
  private showChapterListWithAnimation(): void {
    this.showChapterList = true;
    animateTo({
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
    animateTo({
      duration: 200,
      curve: Curve.EaseOut
    }, () => {
      this.chapterListOpacity = 0;
    });
    setTimeout(() => {
      this.showChapterList = false;
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
      this.settings.readAloud = {
        enabled: defaultReadAloud.enabled,
        engineType: defaultReadAloud.engineType,
        speed: defaultReadAloud.speed,
        pitch: defaultReadAloud.pitch,
        volume: defaultReadAloud.volume,
        continueInBackground: defaultReadAloud.continueInBackground,
        autoPlayNextChapter: defaultReadAloud.autoPlayNextChapter,
        pauseOnManualPageTurn: defaultReadAloud.pauseOnManualPageTurn,
        voiceLanguage: defaultReadAloud.voiceLanguage,
        voicePerson: defaultReadAloud.voicePerson,
        voiceOnline: defaultReadAloud.voiceOnline
      };
    }
    const readAloudSettings = this.settings.readAloud;
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
      this.settings.readAloud = {
        enabled: defaultReadAloud.enabled,
        engineType: defaultReadAloud.engineType,
        speed: defaultReadAloud.speed,
        pitch: defaultReadAloud.pitch,
        volume: defaultReadAloud.volume,
        continueInBackground: defaultReadAloud.continueInBackground,
        autoPlayNextChapter: defaultReadAloud.autoPlayNextChapter,
        pauseOnManualPageTurn: defaultReadAloud.pauseOnManualPageTurn,
        voiceLanguage: defaultReadAloud.voiceLanguage,
        voicePerson: defaultReadAloud.voicePerson,
        voiceOnline: defaultReadAloud.voiceOnline
      };
    }
    this.hideToolbarWithAnimation();
    this.showFontSettings = false;
    this.showBackgroundSettings = false;
    this.openReadAloudInfoWhenOpenReadingSettings = true;
    this.showReadingSettings = true;
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
        this.settings = globalSettings;
        if (this.settings.readAloud) {
          this.readAloudController.updateSettings(this.settings.readAloud);
        }
        logger.info(TAG, 'Loaded global reader settings');
      }
    } catch (e) {
      logger.warn(TAG, `加载设置失败: ${String(e)}`);
    }
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
      settings.textStyle = DEFAULT_TEXT_STYLE;
    } else {
      // 确保textStyle的所有属性都有默认值
      if (settings.textStyle.fontSize === undefined) settings.textStyle.fontSize = 18;
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
  }

  private async ensurePreloadSettingsLoaded(): Promise<void> {
    if (this.preloadSettingsLoaded) {
      return;
    }
    try {
      const context = getContext(this) as common.UIAbilityContext;
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
      const parsed = JSON.parse(rawValue) as Array<string>;
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
      const context = getContext(this) as common.UIAbilityContext;
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

  private getEffectivePrefetchCount(): number {
    if (!this.preloadWhileReadingEnabled) {
      return 0;
    }
    const remaining = this.totalChapters - this.currentChapterIndex - 1;
    if (remaining <= 0) {
      return 0;
    }
    if (this.preloadChapterCount >= 9999) {
      return remaining;
    }
    return Math.max(0, Math.min(this.preloadChapterCount, remaining));
  }

  private stopCrossChapterPrefetch(clearPreparedCache: boolean): void {
    this.prefetchGeneration++;
    if (clearPreparedCache) {
      this.prefetchingChapterIndexes.clear();
      this.preparsedChapterContent.clear();
    }
  }

  private trimPreparsedChapterCache(): void {
    if (this.preparsedChapterContent.size <= MAX_PREPARSED_CHAPTER_CACHE) {
      return;
    }
    const indexes = Array.from(this.preparsedChapterContent.keys()).sort((a: number, b: number) => a - b);
    while (this.preparsedChapterContent.size > MAX_PREPARSED_CHAPTER_CACHE && indexes.length > 0) {
      const oldest = indexes.shift();
      if (oldest === undefined) {
        break;
      }
      if (oldest === this.currentChapterIndex) {
        continue;
      }
      this.preparsedChapterContent.delete(oldest);
    }
  }

  private scheduleCrossChapterPrefetch(): void {
    const preloadCount = this.getEffectivePrefetchCount();
    if (preloadCount <= 0 || this.chapterList.length === 0) {
      return;
    }
    const startIndex = this.currentChapterIndex + 1;
    const endIndex = Math.min(this.totalChapters - 1, this.currentChapterIndex + preloadCount);
    if (startIndex > endIndex) {
      return;
    }
    const generation = ++this.prefetchGeneration;
    logger.info(TAG, `schedule chapter prefetch: range=${startIndex}-${endIndex}, generation=${generation}`);
    void this.prefetchChapterRange(generation, startIndex, endIndex);
  }

  private async prefetchChapterRange(generation: number, startIndex: number, endIndex: number): Promise<void> {
    for (let chapterIndex = startIndex; chapterIndex <= endIndex; chapterIndex++) {
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
        let rawContent = await this.cacheManager.getChapterCache(this.bookId, chapterIndex);
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
        if (!rawContent) {
          continue;
        }
        const parsedContent = this.processChapterContent(rawContent, chapter.title, chapterIndex, 'prefetch');
        this.preparsedChapterContent.set(chapterIndex, parsedContent);
        this.trimPreparsedChapterCache();
      } catch (error) {
        logger.warn(TAG, `prefetch chapter failed: index=${chapterIndex}, error=${String(error)}`);
      } finally {
        this.prefetchingChapterIndexes.delete(chapterIndex);
      }
    }
  }

  async loadContent(): Promise<void> {
    this.hasNotifiedTransitionReaderReady = false;
    this.transitionLoadingProgress = 0;
    this.isLoading = true;
    this.isReadProgressReady = false;
    this.currentChapterHighlightRanges = [];
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
      
      const chapter: LegadoChapter = {
        id: '',
        bookUrl: this.bookUrl,
        url: this.chapterUrl,
        title: this.chapterTitle,
        index: this.currentChapterIndex
      };
      
      // 先尝试从txt文件缓存加载
        logger.info(TAG, `hit preparsed chapter cache: index=${this.currentChapterIndex}`);
      const preparsedContent = this.preparsedChapterContent.get(this.currentChapterIndex);
      if (preparsedContent !== undefined) {
        this.preparsedChapterContent.delete(this.currentChapterIndex);
        this.content = preparsedContent;
        logger.info(TAG, `hit preparsed chapter cache: index=${this.currentChapterIndex}`);
        this.reportTransitionLoadingProgress(0.62, 'chapter_content_ready');
      } else {
        let rawContent = await this.cacheManager.getChapterCache(this.bookId, this.currentChapterIndex);
      
      if (rawContent) {
        logger.info(TAG, `✅ 从txt缓存加载成功: ${this.chapterTitle}`);
      } else {
        logger.info(TAG, `缓存未命中，从网络加载: ${this.chapterTitle}`);
        rawContent = await this.sourceManager.getContent(this.sourceId, chapter);
      }
      this.reportTransitionLoadingProgress(0.62, 'chapter_content_ready');
      
      if (!rawContent) {
        this.content = '加载失败，请重试';
      } else {
        this.content = this.processChapterContent(
          rawContent,
          this.chapterTitle,
          this.currentChapterIndex,
          'current_chapter_load'
        );
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
    } catch (error) {
      logger.error(TAG, `加载正文失败: ${String(error)}`);
      this.content = '加载失败: ' + String(error);
      this.currentChapterHighlightRanges = [];
      this.reportTransitionLoadingProgress(0.9, 'load_failed_fallback');
    }
    this.isLoading = false;
  }
  
  /**
  * 加载章节列表
  */
  async loadChapterList(): Promise<void> {
    try {
      const tocUrl = this.tocUrl || this.bookUrl;
      logger.info(TAG, `加载章节列表: tocUrl=${tocUrl}`);
      const book: LegadoBook = {
        id: '',
        type: LegadoBookSourceType.TEXT,
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
        
        // 转换为TextChapter格式供TextReaderComponent使用
        this.chapters = chapters.map((chapter: LegadoChapter, index: number): TextChapter => {
          return {
            id: chapter.id || `chapter_${index}`,
            title: chapter.title,
            content: '', // 内容将在切换章节时加载
            index: index,
            startPosition: 0,// 小说章节独立加载，不需要全文位置
            endPosition: 0
          };
        });
        
        logger.info(TAG, `Loaded chapter list: ${chapters.length}`);
      }
    } catch (error) {
      logger.error(TAG, `加载章节列表失败: ${String(error)}`);
    }
  }

  async saveSettings(): Promise<void> {
    try {
      // 同时保存为书籍专属设置（如果有bookId）
      await this.settingsManager.setJSON<TextReaderSettings>(SettingKeys.NOVEL_READER_SETTINGS, this.settings);
      
      // 同时保存为书籍专属设置（如果有bookId）
      if (this.bookId) {
        const settingsKey = `${SettingKeys.NOVEL_READER_SETTINGS}_${this.bookId}`;
        await this.settingsManager.setJSON<TextReaderSettings>(settingsKey, this.settings);
        logger.debug(TAG, `保存书籍专属设置: ${this.bookId}`);
      }
    } catch (e) {
      logger.warn(TAG, `保存设置失败: ${String(e)}`);
    }
  }

  onSettingsChange(newSettings: TextReaderSettings): void {
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
        fontSize: sourceTextStyle.fontSize,
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
      readAloud: newSettings.readAloud
        ? {
            enabled: newSettings.readAloud.enabled,
            engineType: newSettings.readAloud.engineType,
            speed: newSettings.readAloud.speed,
            pitch: newSettings.readAloud.pitch,
            volume: newSettings.readAloud.volume,
            continueInBackground: newSettings.readAloud.continueInBackground,
            autoPlayNextChapter: newSettings.readAloud.autoPlayNextChapter,
            pauseOnManualPageTurn: newSettings.readAloud.pauseOnManualPageTurn,
            voiceLanguage: newSettings.readAloud.voiceLanguage,
            voicePerson: newSettings.readAloud.voicePerson,
            voiceOnline: newSettings.readAloud.voiceOnline
          }
        : undefined
    };
    this.ensureSettingsComplete(nextSettings);

    const oldMode = this.lastReadingMode;
    const newMode = nextSettings.readingMode;
    
    // 异步保存设置（不阻塞UI）
    this.settings = nextSettings;
    // 检测阅读模式变化，处理双页模式的横屏切换和组件重载
    this.saveSettings();
    if (nextSettings.readAloud) {
      this.readAloudController.updateSettings(nextSettings.readAloud);
    }
    logger.debug(TAG, `设置已更新并保存`);
    
    // 检测阅读模式变化，处理双页模式的横屏切换和组件重载
    if (oldMode !== newMode) {
      this.lastReadingMode = newMode;
      this.handleReadingModeChange(oldMode, newMode);
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
      
      if (newMode === TextReadingMode.DUAL_PAGE) {
        // 延迟重载组件，等待横屏旋转完成
        logger.info(TAG, 'Screen orientation changed to landscape');
        WindowManager.setPreferredOrientationLandscape(this.uiContext ?? undefined);
        // 离开双页模式：恢复自动旋转 + 重载组件
        setTimeout(() => {
          this.readerKey++;
        }, 300);
      } else if (oldMode === TextReadingMode.DUAL_PAGE) {
        // 延迟重载组件，等待旋转完成
        logger.info(TAG, '离开双页模式，恢复自动旋转并重载组件');
        WindowManager.setPreferredOrientationAuto(this.uiContext ?? undefined);
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
    
    try {
      const ruleManager = NovelReplaceRuleManager.getInstance();
      await ruleManager.initialize();
      
      // 创建新规则
      const ruleParams: AddRuleParams = {
        name: `Encyclopedia: ${pattern.substring(0, 20)}${pattern.length > 20 ? '...' : ''}` ,
        pattern: pattern,
        replacement: '',
        isRegex: false,
        scope: ReplaceScope.CONTENT,
        enabled: true,
        order: 100
      };
      
      await ruleManager.addRule(ruleParams);
      logger.info(TAG, `已添加净化规则: ${pattern.substring(0, 50)}`);
      
      // 重新加载当前章节内容以应用新规则
      this.stopCrossChapterPrefetch(true);
      this.loadContent();
    } catch (error) {
      logger.error(TAG, `添加净化规则失败: ${String(error)}`);
    }
  }

  onPageChange(pageIndex: number, totalPages: number): void {
    this.currentPageIndex = pageIndex;
    this.currentChapterTotalPages = Math.max(0, totalPages);
    this.readAloudController.updatePageIndex(pageIndex);
    this.updateReadAloudContextByPosition();
    logger.debug(TAG, `页面切换: ${pageIndex + 1}/${totalPages}`);

    // 页码变化立即落库，避免短时阅读/异常退出时进度丢失
    const now = Date.now();
    this.lastSaveTime = now;
    this.saveReadProgress();
  }

  onChapterChange(chapterIndex: number): void {
    logger.info(TAG, `章节切换请求: ${chapterIndex}`);
    // 保存当前进度后切换章节
    this.saveReadProgress();
    this.switchToChapter(chapterIndex);
  }

  /**
  * 切换到指定章节
  */
  async switchToChapter(chapterIndex: number): Promise<void> {
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
    this.currentPageIndex = 0;
    this.stopCrossChapterPrefetch(false);
    
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
    const resumeCharIndex = Math.floor(this.settingsManager.getNumber(this.getReadAloudResumeKey(), 0));
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
    this.updateReadAloudContextByPosition(safeCharIndex);
    this.persistReadAloudResumeCharIndex(false);

    const snapshot = this.readAloudController.getSnapshot();
    if (snapshot.playbackState === ReadAloudPlaybackState.PLAYING) {
      const baseCharIndex = snapshot.currentCharIndex >= 0 ? snapshot.currentCharIndex : safeCharIndex;
      this.readAloudController.seekByChars(safeCharIndex - baseCharIndex, 'selection_start');
    } else {
      this.readAloudController.start('selection_start');
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
    AppStorage.setOrCreate('ReadAloudPlayerOpeningAt', Date.now());
    globalStack.pushPathByName('ReadAloudPlayerPage', undefined);
  }

  private async recordBrowseHistory(param: NovelReaderPageParams): Promise<void> {
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
      const style = JSON.parse(styleJson) as HighlightStyle;
      if (style && style.color && style.color.trim().length > 0) {
        return style.color;
      }
      return defaultColor;
    } catch (_error) {
      return defaultColor;
    }
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
    let resolvedStart = -1;
    let cursor = this.content.indexOf(quote, searchFrom);
    let nearestDistance = Number.MAX_SAFE_INTEGER;
    while (cursor >= 0 && cursor < searchTo) {
      const distance = Math.abs(cursor - searchPivot);
      if (distance < nearestDistance) {
        nearestDistance = distance;
        resolvedStart = cursor;
      }
      cursor = this.content.indexOf(quote, cursor + 1);
    }
    if (resolvedStart < 0) {
      resolvedStart = this.content.indexOf(quote);
    }
    if (resolvedStart < 0) {
      return null;
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
        UnifiedAnnotationType.HIGHLIGHT
      );
      const ranges: TextReaderHighlightRange[] = [];
      let fallbackByQuoteCount = 0;
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
        const range: TextReaderHighlightRange = {
          id: record.id,
          startOffset: finalStart,
          endOffset: finalEnd,
          color: this.parseHighlightColor(record.styleJson),
          quoteText,
          pageIndex: record.pageIndex
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
        `刷新小说划线渲染数据成功: trigger=${trigger}, chapterIndex=${this.currentChapterIndex}, count=${ranges.length}, pageRange=${this.currentPageStartCharIndex}-${this.currentPageEndCharIndex}, hitInPage=${currentPageHitCount}`
      );
    } catch (error) {
      this.currentChapterHighlightRanges = [];
      logger.error(TAG, `刷新小说划线渲染数据失败: trigger=${trigger}, error=${String(error)}`);
    }
  }

  private addCurrentNovelBookmark(): void {
    if (!this.bookId) {
      promptAction.showToast({ message: '书籍信息未就绪', duration: 1500 });
      return;
    }
    const chapterName = this.chapterTitle || `第${this.currentChapterIndex + 1}章`;
    const pageLabel = this.currentChapterTotalPages > 0
      ? `${this.currentPageIndex + 1}/${this.currentChapterTotalPages}`
      : `${this.currentPageIndex + 1}`;

    promptAction.showActionMenu({
      title: '书签标题',
      buttons: [
        { text: chapterName, color: '#007AFF' },
        { text: `${chapterName} | P${pageLabel}`, color: '#007AFF' },
        { text: '仅记录位置', color: '#007AFF' },
        { text: '取消', color: '#999999' }
      ]
    }).then(async (result: promptAction.ActionMenuSuccessResponse) => {
      if (result.index === 3) {
        return;
      }
      let marker = '';
      if (result.index === 0) {
        marker = chapterName;
      } else if (result.index === 1) {
        marker = `${chapterName} | P${pageLabel}`;
      }
      try {
        await this.annotationManager.createBookmark({
          contentType: UnifiedContentType.NOVEL,
          contentId: this.bookId,
          title: marker,
          anchor: this.buildCurrentAnchor(undefined, this.currentPageStartCharIndex, this.currentPageEndCharIndex)
        });
        promptAction.showToast({ message: '书签已添加', duration: 1500 });
      } catch (error) {
        logger.error(TAG, `添加小说书签失败: ${String(error)}`);
        promptAction.showToast({ message: '添加书签失败', duration: 1500 });
      }
    }).catch(() => {});
  }

  private openCurrentNovelAnnotationCenter(): void {
    if (!this.bookId) {
      promptAction.showToast({ message: '书籍信息未就绪', duration: 1500 });
      return;
    }
    const params: AnnotationCenterPageParams = {
      contentType: UnifiedContentType.NOVEL,
      contentId: this.bookId,
      contentTitle: this.bookName
    };
    try {
      this.pathStack.pushPathByName('AnnotationCenterPage', params);
    } catch (error) {
      logger.error(TAG, `打开摘录中心失败: ${String(error)}`);
      promptAction.showToast({ message: '打开摘录中心失败', duration: 1500 });
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

  private async onAddNovelThought(selectedText: string, globalStart: number, globalEnd: number): Promise<void> {
    if (!this.bookId) {
      promptAction.showToast({ message: '书籍信息未就绪', duration: 1500 });
      return;
    }
    try {
      await this.annotationManager.createThought({
        contentId: this.bookId,
        anchor: this.buildCurrentAnchor(selectedText, globalStart, globalEnd),
        textContent: ''
      });
      promptAction.showToast({ message: '想法已保存', duration: 1500 });
    } catch (error) {
      logger.error(TAG, `创建小说想法失败: ${String(error)}`);
      promptAction.showToast({ message: '想法保存失败', duration: 1500 });
    }
  }

  private async createNovelHighlightByStyle(
    selectedText: string,
    globalStart: number,
    globalEnd: number,
    withThought: boolean
  ): Promise<void> {
    if (!this.bookId) {
      promptAction.showToast({ message: '书籍信息未就绪', duration: 1500 });
      return;
    }

    const lineType = HighlightLineType.UNDERLINE;
    const color = '#E8A317';
    logger.info(
      TAG,
      `开始创建小说划线: chapterIndex=${this.currentChapterIndex}, start=${globalStart}, end=${globalEnd}, withThought=${withThought}`
    );

    try {
      const highlight = await this.annotationManager.createHighlight({
        contentId: this.bookId,
        anchor: this.buildCurrentAnchor(selectedText, globalStart, globalEnd),
        style: {
          lineType,
          color
        }
      });
      logger.info(
        TAG,
        `小说划线创建成功: annotationId=${highlight.id}, chapterIndex=${this.currentChapterIndex}, start=${globalStart}, end=${globalEnd}`
      );

      if (withThought) {
        await this.annotationManager.createThought({
          contentId: this.bookId,
          anchor: this.buildCurrentAnchor(selectedText, globalStart, globalEnd),
          textContent: '',
          linkedAnnotationId: highlight.id
        });
        logger.info(TAG, `划线关联想法创建成功: linkedAnnotationId=${highlight.id}`);
      }

      await this.refreshCurrentChapterHighlightRanges('create_highlight');
      if (withThought) {
        promptAction.showToast({ message: '划线和想法已保存', duration: 1500 });
      } else {
        promptAction.showToast({ message: '划线已保存', duration: 1500 });
      }
    } catch (error) {
      logger.error(TAG, `创建小说划线失败: ${String(error)}`);
      promptAction.showToast({ message: '划线保存失败', duration: 1500 });
    }
  }

  private createNovelHighlightByStyleLegacy(
    selectedText: string,
    globalStart: number,
    globalEnd: number,
    withThought: boolean
  ): void {
    if (!this.bookId) {
      promptAction.showToast({ message: '书籍信息未就绪', duration: 1500 });
      return;
    }

    promptAction.showActionMenu({
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
          promptAction.showToast({ message: '划线和想法已保存', duration: 1500 });
        } else {
          promptAction.showToast({ message: '划线已保存', duration: 1500 });
        }
      } catch (error) {
        logger.error(TAG, `创建小说划线失败: ${String(error)}`);
        promptAction.showToast({ message: '划线保存失败', duration: 1500 });
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
      promptAction.showToast({ message: '没有启用的字典规则，请在设置中添加', duration: 2000 });
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
      promptAction.showActionMenu({
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
      promptAction.showActionMenu({
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
      promptAction.showActionMenu({
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
      promptAction.showActionMenu({
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
              }
            }
          })
            .zIndex(1000)
        }
        
        // 百科搜索对话框
        if (this.showEncyclopediaDialog) {
          this.buildEncyclopediaDialog()
        }
      }
      .width('100%')
      .height('100%')
      .id('novel_reader_root')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
    .onReady((context: NavDestinationContext) => {
      logger.info(TAG, 'NavDestination.onReady 已触发');
      this.pathStack = context.pathStack;
      const param = context.pathInfo.param as NovelReaderPageParams | null;
      if (param) {
        this.sourceCoverComponentId = param.coverComponentId || '';
        this.sourceId = param.sourceId;
        this.bookUrl = param.bookUrl;
        this.bookName = param.bookName;
        this.chapterUrl = param.chapterUrl;
        this.chapterTitle = param.chapterTitle;
        this.currentChapterIndex = param.chapterIndex;
        this.totalChapters = param.totalChapters;
        this.tocUrl = param.tocUrl || param.bookUrl; // 使用传递的tocUrl或bookUrl
        // 生成bookId和chapterId
        this.bookId = `${param.sourceId}_${encodeURIComponent(param.bookUrl)}`;
        this.chapterId = `${this.bookId}_${param.chapterIndex}`;
        this.bookCoverUrl = param.coverUrl || '';
        this.shouldAutoStartReadAloud = param.autoStartReadAloud === true;
        this.shouldAutoOpenReadAloudPlayer = param.autoOpenReadAloudPlayer === true;
        AppStorage.setOrCreate('ReadAloudCurrentHostPage', 'NovelReaderPage');
        this.loadSettings();
        this.loadContent();
        
        // [修复] 记录浏览历史，确保阅读过的小说出现在历史浏览中
        this.recordBrowseHistory(param);
        
        // [修复] 确保书籍存在于数据库中，用于首页最近阅读显示
        this.ensureBookInDatabase(param);
      }
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
      paginationMode: PaginationMode.ONLINE,  // 在线小说使用ONLINE分页模式
      onPageChange: (pageIndex: number, totalPages: number) => this.onPageChange(pageIndex, totalPages),
      onPageCharRangeChange: (startCharIndex: number, endCharIndex: number) => {
        this.onTextPageCharRangeChange(startCharIndex, endCharIndex);
      },
      onUserPageTurnStart: () => {
        this.onTextUserPageTurnStart();
      },
      onChapterChange: (chapterIndex: number) => this.onChapterChange(chapterIndex),
      onTapCenter: () => this.onTapCenter(),
      onReady: () => {
        // 文本阅读器分页完成，通知过渡动画阅读器就绪
        logger.info(TAG, '📖 文本阅读器分页完成，通知过渡动画');
        this.reportTransitionLoadingProgress(0.96, 'text_reader_ready');
        this.notifyTransitionReaderReadyOnce('TextReaderComponent.onReady');
      },
      onAddPurifyRule: (pattern: string) => this.addPurifyRule(pattern),
      onSearchEncyclopedia: (keyword: string) => this.showEncyclopediaSearch(keyword),
      onStartReadAloudFromCharIndex: (charIndex: number) => this.onStartReadAloudFromCharIndex(charIndex),
      onAddHighlight: (selectedText: string, globalStart: number, globalEnd: number) =>
        this.onAddNovelHighlight(selectedText, globalStart, globalEnd),
      onAddHighlightWithThought: (selectedText: string, globalStart: number, globalEnd: number) =>
        this.onAddNovelHighlightWithThought(selectedText, globalStart, globalEnd),
      onAddThought: (selectedText: string, globalStart: number, globalEnd: number) =>
        this.onAddNovelThought(selectedText, globalStart, globalEnd)
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
        SymbolGlyph($r('sys.symbol.bookmark'))
          .fontSize(20)
          .fontColor([$r('app.color.text_primary')])
      }
      .width(48)
      .height(48)
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        this.addCurrentNovelBookmark();
      })

      Button() {
        SymbolGlyph($r('sys.symbol.list_bullet'))
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
    .height(56 + this.statusBarHeight)
    .padding({ left: 8, right: 8, top: this.statusBarHeight })
    .backgroundColor(this.themeManager.getGlassBackgroundResource())
    .backgroundBlurStyle(this.themeManager.getGlassBlurStyle())
    .shadow({ radius: this.themeManager.getGlassRadius(), color: this.themeManager.getGlassShadowColor(), offsetX: 0, offsetY: 4 })
    .opacity(this.toolbarOpacity)
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
        
        Text(`${this.currentChapterIndex + 1} / ${this.totalChapters}`)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .fontFamily(this.appFontFamily)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 4 })

      // 章节进度条
      Row() {
        Slider({
          value: this.currentChapterIndex,
          min: 0,
          max: Math.max(0, this.totalChapters - 1),
          step: 1
        })
          .layoutWeight(1)
          .trackColor($r('app.color.divider_primary'))
          .selectedColor($r('app.color.accent_primary'))
          .onChange((value: number, mode: SliderChangeMode) => {
            if (mode === SliderChangeMode.End) {
              const targetIndex = Math.round(value);
              if (targetIndex !== this.currentChapterIndex) {
                this.switchToChapter(targetIndex);
              }
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

