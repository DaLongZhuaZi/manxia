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
import { TextReaderComponent, PaginationMode } from '../components/TextReaderComponent';
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
  TextAlignment
} from '../Models/TextReaderModels';
import { NovelReadProgress } from '../Models/NovelModels';
import { SettingsManager, SettingKeys } from '../Framework/Managers/SettingsManager';
import { getNovelSettingsManager, BrowseHistoryInput } from '../Framework/Novel/NovelSettingsManager';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';
import { PageLifecycleManager } from '../Framework/Lifecycle';
import { WindowManager, DisplayMode } from '../Utils/WindowManager';
import { curves, promptAction } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { setReaderReady, startBookCloseTransitionWithComponentId, CoverPosition, cancelTransition } from '../components/BookTransitionOverlay';
import { NovelDictRuleManager, DictRule } from '../Framework/Novel/NovelDictRuleManager';
import { ReadAloudController } from '../Framework/ReadAloud/ReadAloudController';
import { ReadAloudPlaybackState } from '../Framework/ReadAloud/ReadAloudTypes';
import { eventBus, GameEvent, IEventPayload, ReadAloudStatePayload } from '../Framework/EventBus';

const TAG = 'NovelReaderPage';

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

  // 沉浸式显示状态
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

  // UI控制状态 - 默认隐藏工具栏实现完全沉浸式体验
  @State showTopToolbar: boolean = false;
  @State showBottomToolbar: boolean = false;
  @State toolbarOpacity: number = 0.0;
  @State showChapterList: boolean = false;
  // 3个独立设置面板
  @State showFontSettings: boolean = false;
  @State showBackgroundSettings: boolean = false;
  @State showReadingSettings: boolean = false;
  @State openReadAloudInfoWhenOpenReadingSettings: boolean = false;

  // 动画状态
  @State chapterListOpacity: number = 0;
  
  // 组件重建控制（用于双页模式切换时强制重新加载组件）
  @State readerKey: number = 0;
  // 上一次的阅读模式（用于检测变化）
  private lastReadingMode: TextReadingMode = TextReadingMode.PAGE;
  
  // 百科搜索对话框状态
  @State showEncyclopediaDialog: boolean = false;
  @State encyclopediaKeyword: string = '';
  @State encyclopediaUrl: string = '';

  // 章节列表滚动控制器
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
  private chapterList: LegadoChapter[] = []; // 完整章节列表
  private sourceManager = getNovelSourceManager();
  private dataManager = getNovelDataManager();
  private cacheManager = getNovelChapterCacheManager();
  private settingsManager: SettingsManager = SettingsManager.getInstance();
  private readAloudController: ReadAloudController = ReadAloudController.getInstance();
  private readStartTime: number = 0;
  private lastSaveTime: number = 0;
  private uiContext: UIContext | null = null;
  private saveProgressInterval: number = 30000; // 30秒自动保存
  private shouldAutoStartReadAloud: boolean = false;
  private shouldAutoOpenReadAloudPlayer: boolean = false;
  private lastReadAloudResumePersistTime: number = 0;

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
    logger.lifecycle(TAG, 'aboutToDisappear - 开始清理资源');
    this.lifecycle.destroy();
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    FontAwareHelper.cleanupFontAware(this.componentId);
    // 页面退出时保存阅读进度
    this.saveReadProgress();
    // 恢复正常显示模式
    this.restoreNormalMode();
    // 离开页面时恢复自动旋转（防止双页模式强制横屏残留）
    WindowManager.setPreferredOrientationAuto(this.uiContext ?? undefined);
    // [修复] 安全清理过渡动画状态，防止页面销毁后覆盖层仍然阻止交互
    cancelTransition();
  }

  onPageShow(): void {
    AppStorage.setOrCreate('ReadAloudCurrentHostPage', 'NovelReaderPage');
    this.syncReadAloudStateFromController();
    this.updateReadAloudContextByPosition();
    this.readAloudController.refreshMediaSession();
  }

  onPageHide(): void {
    this.readAloudController.handlePageHide();
    this.readAloudPlaying = this.readAloudController.getSnapshot().playbackState === ReadAloudPlaybackState.PLAYING;
    this.persistReadAloudResumeCharIndex(true);
    this.readAloudController.refreshMediaSession();
    logger.lifecycle(TAG, '小说阅读器页面隐藏（进入后台）');
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
        logger.error(TAG, '无法获取UIContext，设置全屏模式失败');
        return;
      }

      WindowManager.setDisplayMode(DisplayMode.FULL_IMMERSIVE, this.uiContext);
      logger.info(TAG, '设置完全沉浸式阅读模式');
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
        logger.error(TAG, '无法获取UIContext，恢复正常模式失败');
        return;
      }

      WindowManager.setDisplayMode(DisplayMode.DEFAULT, this.uiContext);
      logger.info(TAG, '恢复默认显示模式');
    } catch (error) {
      logger.error(TAG, `恢复正常模式失败: ${String(error)}`);
    }
  }

  /**
   * 关闭阅读器（带动画）
   */
  private async closeReader(): Promise<void> {
    // 先保存阅读进度
    this.saveReadProgress();

    // 获取封面组件ID（用于关闭动画）
    const coverComponentId = `novel_cover_${this.bookId}`;

    try {
      // 触发关闭过渡动画
      logger.info(TAG, `触发关闭过渡动画，封面组件ID: ${coverComponentId}`);
      await startBookCloseTransitionWithComponentId(
        'novel_reader_root',
        coverComponentId,
        () => {
          // 动画完成后返回
          this.pathStack.pop();
        }
      );
    } catch (error) {
      logger.error(TAG, `关闭动画失败: ${String(error)}`);
      // [修复] 动画失败时重置过渡状态并返回
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
      // 优先加载书籍专属设置，如果不存在则使用全局设置
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
        // 使用书籍专属设置（用户已经设置过，尊重用户选择）
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
        logger.info(TAG, `使用全局小说阅读器设置`);
      }
    } catch (e) {
      logger.warn(TAG, `加载设置失败: ${String(e)}`);
    }
  }
  
  /**
   * 确保设置对象的所有子属性完整（兼容旧版本设置）
   */
  private ensureSettingsComplete(settings: TextReaderSettings): void {
    // 确保background对象完整
    if (!settings.background) {
      settings.background = { type: BackgroundType.COLOR, color: '#F5F0E1' };
    } else if (!settings.background.type) {
      settings.background.type = BackgroundType.COLOR;
    }
    
    // 确保textStyle对象完整
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
    
    // 确保pageMargins对象完整，包括各个属性
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

  async loadContent(): Promise<void> {
    this.isLoading = true;
    try {
      // 设置沉浸式模式
      this.setupFullscreenMode();
      
      // [优化] 确保净化规则管理器已初始化并加载最新规则
      const ruleManager = NovelReplaceRuleManager.getInstance();
      await ruleManager.initialize();
      await ruleManager.refreshRules();
      
      // 加载章节列表（如果还没有加载）
      if (this.chapterList.length === 0) {
        await this.loadChapterList();
      }
      
      const chapter: LegadoChapter = {
        id: '',
        bookUrl: this.bookUrl,
        url: this.chapterUrl,
        title: this.chapterTitle,
        index: this.currentChapterIndex
      };
      
      // 先尝试从txt文件缓存加载
      logger.info(TAG, `尝试从缓存加载章节: bookId=${this.bookId}, index=${this.currentChapterIndex}`);
      let rawContent = await this.cacheManager.getChapterCache(this.bookId, this.currentChapterIndex);
      
      if (rawContent) {
        logger.info(TAG, `✅ 从txt缓存加载成功: ${this.chapterTitle}`);
      } else {
        // 缓存中没有，从网络加载
        logger.info(TAG, `缓存未命中，从网络加载: ${this.chapterTitle}`);
        rawContent = await this.sourceManager.getContent(this.sourceId, chapter);
      }
      
      if (!rawContent) {
        this.content = '加载失败，请重试';
      } else {
        // 使用内容处理器应用替换规则
        // 注意：不在这里添加段落缩进，缩进由TextReaderComponent统一处理
        // 这样可以避免与TextReaderComponent的缩进逻辑冲突
        const contentProcessor = getNovelContentProcessor();
        const processConfig: ContentProcessConfig = {
          useReplace: true,
          chineseConvert: 0,
          reSegment: false,
          includeTitle: true,
          paragraphIndent: '',  // 不添加缩进，由TextReaderComponent处理
          sourceId: this.sourceId
        };
        const processResult = contentProcessor.processContent(
          rawContent,
          this.chapterTitle,
          this.bookName,
          processConfig
        );
        // 直接使用处理后的内容，不使用paragraphs（避免额外的换行处理）
        this.content = processResult.content;
        
        if (processResult.appliedRules.length > 0) {
          logger.info(TAG, `应用了 ${processResult.appliedRules.length} 条替换规则`);
        }
      }
      
      // 加载阅读进度
      await this.loadReadProgress();
      this.currentPageStartCharIndex = 0;
      this.currentPageEndCharIndex = 0;
      this.restoreReadAloudResumeCharIndex();
      this.syncReadAloudStateFromController();
      this.updateReadAloudContextByPosition();
      this.tryHandleAutoReadAloudEntry();
    } catch (error) {
      logger.error(TAG, `加载正文失败: ${String(error)}`);
      this.content = '加载失败: ' + String(error);
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
        tocUrl: tocUrl, // 使用tocUrl加载章节列表
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
            startPosition: 0, // 小说章节独立加载，不需要全文位置
            endPosition: 0
          };
        });
        
        logger.info(TAG, `加载章节列表成功: ${chapters.length}章`);
      }
    } catch (error) {
      logger.error(TAG, `加载章节列表失败: ${String(error)}`);
    }
  }

  async saveSettings(): Promise<void> {
    try {
      // 保存为全局设置
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
    const oldMode = this.lastReadingMode;
    const newMode = newSettings.readingMode;
    
    // 直接更新settings状态，触发UI响应式更新
    this.settings = newSettings;
    // 异步保存设置（不阻塞UI）
    this.saveSettings();
    if (newSettings.readAloud) {
      this.readAloudController.updateSettings(newSettings.readAloud);
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
        // 进入双页模式：强制横屏 + 重载组件
        logger.info(TAG, '切换到双页模式，强制横屏并重载组件');
        WindowManager.setPreferredOrientationLandscape(this.uiContext ?? undefined);
        // 延迟重载组件，等待横屏旋转完成
        setTimeout(() => {
          this.readerKey++;
        }, 300);
      } else if (oldMode === TextReadingMode.DUAL_PAGE) {
        // 离开双页模式：恢复自动旋转 + 重载组件
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
        name: `用户添加: ${pattern.substring(0, 20)}${pattern.length > 20 ? '...' : ''}`,
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
      this.loadContent();
    } catch (error) {
      logger.error(TAG, `添加净化规则失败: ${String(error)}`);
    }
  }

  onPageChange(pageIndex: number, totalPages: number): void {
    this.currentPageIndex = pageIndex;
    this.readAloudController.updatePageIndex(pageIndex);
    this.updateReadAloudContextByPosition();
    logger.debug(TAG, `页面切换: ${pageIndex + 1}/${totalPages}`);
    
    // 定期保存阅读进度
    const now = Date.now();
    if (now - this.lastSaveTime > this.saveProgressInterval) {
      this.saveReadProgress();
      this.lastSaveTime = now;
    }
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
      logger.warn(TAG, `无效的章节索引: ${chapterIndex}`);
      return;
    }
    
    if (this.chapterList.length === 0) {
      logger.warn(TAG, '章节列表为空，无法切换');
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
  async saveReadProgress(): Promise<void> {
    if (!this.bookId) return;
    
    try {
      const now = Date.now();
      const progress: NovelReadProgress = {
        bookId: this.bookId,
        chapterId: this.chapterId,
        chapterIndex: this.currentChapterIndex,
        position: this.currentPageIndex,
        progress: this.totalChapters > 0 ? (this.currentChapterIndex / this.totalChapters) * 100 : 0,
        readTime: now
      };
      
      await this.dataManager.saveReadProgress(progress);
      
      // 更新阅读时长（秒）
      if (this.readStartTime > 0) {
        const readingDuration = Math.floor((now - this.readStartTime) / 1000);
        if (readingDuration > 0) {
          await this.dataManager.updateReadingTime(this.bookId, readingDuration);
          this.readStartTime = now; // 重置开始时间，避免重复计算
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
      // 检查书籍是否已存在
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
  
  /**
   * 显示百科搜索对话框（使用字典规则）
   */
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
    // 根据规则数量构建按钮
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
      readAloudHighlightEnabled: true,
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
        setReaderReady();
      },
      onAddPurifyRule: (pattern: string) => this.addPurifyRule(pattern),
      onSearchEncyclopedia: (keyword: string) => this.showEncyclopediaSearch(keyword),
      onStartReadAloudFromCharIndex: (charIndex: number) => this.onStartReadAloudFromCharIndex(charIndex)
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
