// 文件路径: entry/src/main/ets/pages/EBookReaderPage.ets
/**
 * 电子书阅读器页面
 * 支持TXT、EPUB等格式的电子书阅读
 * 采用与漫画阅读器一致的沉浸式设计风格
  */

import { logger } from '../Utils/Logger';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { ThemeManager, ThemeType, GlassEffectContext } from '../Framework/Managers/ThemeManager';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';
import { PageLifecycleManager } from '../Framework/Lifecycle';
import { WindowManager, DisplayMode } from '../Utils/WindowManager';
import { EBook, EBookChapter, EBookReadingProgress, EBookReadingSettings, EBookPageMode, EBookFormat, DEFAULT_EBOOK_READING_SETTINGS, EBOOK_THEME_PRESETS, EBookThemePreset } from '../Models/EBookModels';
import { SettingsManager, SettingKeys } from '../Framework/Managers/SettingsManager';
import { EBookDataManager } from '../Framework/Data/EBookDataManager';
import { PdfViewerComponent } from '../Framework/Components/PdfViewerComponent';
import { PdfKitViewerComponent, PdfViewerCallbacks } from '../Framework/Components/PdfKitViewerComponent';
import { isReaderKitEnabled } from '../Framework/Initialization/ReaderKitFeatureGate';
import { EBookReadingSettingsPanel } from '../Framework/Components/EBookReadingSettingsPanel';
import { curves, UIContext, promptAction } from '@kit.ArkUI';
import { display } from '@kit.ArkUI';
import { TextReaderComponent, PaginationMode } from '../components/TextReaderComponent';
import { TextReaderSettingsPanel } from '../components/TextReaderSettingsPanel';
import {
  TextReaderSettings,
  TextReadingMode,
  TextPageTurnAnimation,
  BackgroundType,
  DEFAULT_TEXT_READER_SETTINGS,
  DEFAULT_READ_ALOUD_SETTINGS,
  ReadAloudEngineType,
  ReadAloudSettings,
  isTextFile,
  TextAlignment,
  SavedBackgroundImage,
  TextChapter,
  PRESET_BACKGROUNDS,
  PresetBackground
} from '../Models/TextReaderModels';
import { eventBus, GameEvent, BasePayload, IEventPayload, ReadAloudStatePayload } from '../Framework/EventBus';
import { KeyCode, inputConsumer } from '@kit.InputKit';
import type { KeyEvent as InputKeyEvent } from '@kit.InputKit';
import { setReaderReady, setReaderLoadingProgress, startBookCloseTransitionWithComponentId, CoverPosition, cancelTransition } from '../components/BookTransitionOverlay';
import { ReadAloudController } from '../Framework/ReadAloud/ReadAloudController';
import { ReadAloudPlaybackState, ReadAloudVoiceOption } from '../Framework/ReadAloud/ReadAloudTypes';
import { ReadAloudAvailability, ReadAloudEngineAvailabilityMap } from '../Framework/ReadAloud/ReadAloudAvailability';
import { ReadAloudSettingsInfoPanel } from '../components/ReadAloudSettingsInfoPanel';
import { UnifiedContentType } from '../Models/UnifiedContentModels';
import { getUnifiedAnnotationManager } from '../Framework/Annotations/UnifiedAnnotationManager';
import { AnnotationCenterPageParams } from './AnnotationCenterPage';

const TAG = 'EBookReaderPage';

interface ReaderKitViewerControllerLike {
  isControllerReady(): boolean;
  applyReadingSettings(settings: EBookReadingSettings, force: boolean): void;
  goToChapter(chapterIndex: number, domPos: string): Promise<void>;
}

/**
* 阅读器页面参数
*/
export interface EBookReaderParams {
  bookId: string;
  coverComponentId?: string;
}

@Component
struct EBookReaderPage {
  @State pathStack: NavPathStack = new NavPathStack();
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  private componentId: string = 'EBookReaderPage';
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private lifecycle = new PageLifecycleManager('EBookReaderPage', { enableDebug: true });

  // 电子书数据
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;

  // 电子书数据
  @State ebook: EBook | null = null;
  @State currentChapter: EBookChapter | null = null;
  @State currentChapterIndex: number = 0;
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
  @State textContent: string = '';
  @State textCurrentPageStartCharIndex: number = 0;
  @State textCurrentPageEndCharIndex: number = 0;
  @State textReadAloudPlaying: boolean = false;
  @State textReadAloudCurrentCharIndex: number = -1;
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
  @State showTextReaderSettings: boolean = false;
  @State textReaderSettingsOpacity: number = 0;
  @State textReaderSettingsScale: number = 0.95;

  // UI上下文（用于设置沉浸式模式）
  private settingsManager: SettingsManager = SettingsManager.getInstance();
  private ebookDataManager: EBookDataManager = EBookDataManager.getInstance();
  private annotationManager = getUnifiedAnnotationManager();
  private readAloudController: ReadAloudController = ReadAloudController.getInstance();
  
  // Reader Kit 阅读器控制器（用于实时应用设置和跳转章节）
  private uiContext: UIContext | undefined = undefined;
  private sourceCoverComponentId: string = '';
  private hasNotifiedTransitionReaderReady: boolean = false;
  private transitionLoadingProgress: number = 0;
  private isCloseTransitionNavigating: boolean = false;
  
  // 阅读时间记录相关
  private readerKitController: ReaderKitViewerControllerLike | null = null;

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
    if (!this.ebook || this.ebook.format !== EBookFormat.TXT) {
      return;
    }
    const statePayload = payload as ReadAloudStatePayload;
    const payloadBookId = statePayload.bookId ?? '';
    if (!payloadBookId || payloadBookId !== this.ebook.id) {
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
    eventBus.subscribe(GameEvent.READ_ALOUD_STATE_CHANGED, this.onReadAloudStateChanged);
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (theme: ThemeType) => {
      logger.info(TAG, `主题切换到: ${theme}`);
      // 检查当前电子书是否设置了 followSystemTheme
      // 检查当前电子书是否设置了 followSystemTheme
      if (this.ebook?.readingSettings?.followSystemTheme === true) {
        if (theme === 'dark') {
          this.bgColor = '#1E1E1E';
          this.textColor = '#D4D4D4';
        } else {
          this.bgColor = '#FFFFFF';
          this.textColor = '#333333';
        }
        logger.info(TAG, `用户已自定义背景设置，不跟随系统主题`);
      } else {
        logger.info(TAG, `用户已自定义背景设置，不跟随系统主题`);
      }
    });
    // 初始化横屏检测
    // 初始化阅读时间记录
    
    // 初始化阅读时间记录
    this.updateScreenOrientation();
    
    // 注册音量键翻页监听
    this.startReadingTimeTracking();
    
    // 注册音量键翻页监听
    this.registerVolumeKeyListener();
  }
  
  /**
  * 更新屏幕方向状态
  */
  private updateScreenOrientation(): void {
    try {
      const displayInfo = display.getDefaultDisplaySync();
      this.screenWidth = px2vp(displayInfo.width);
      const screenHeight = px2vp(displayInfo.height);
      this.isLandscape = this.screenWidth > screenHeight;
      logger.info(TAG, `屏幕方向: ${this.isLandscape ? '横屏' : '竖屏'}, 宽度=${this.screenWidth}vp`);
    } catch (error) {
      logger.error(TAG, `获取屏幕方向失败: ${String(error)}`);
    }
  }

  aboutToDisappear(): void {
    eventBus.unsubscribe(GameEvent.READ_ALOUD_STATE_CHANGED, this.onReadAloudStateChanged);
    const readAloudSettings = this.getSafeReadAloudSettings(this.textReaderSettings.readAloud);
    const readAloudSnapshot = this.readAloudController.getSnapshot();
    const keepReadAloudAliveOnExit = readAloudSettings.continueInBackground &&
      (
        readAloudSnapshot.playbackState === ReadAloudPlaybackState.PLAYING ||
        readAloudSnapshot.playbackState === ReadAloudPlaybackState.PAUSED
      );
    if (keepReadAloudAliveOnExit) {
      this.textReadAloudPlaying = readAloudSnapshot.playbackState === ReadAloudPlaybackState.PLAYING;
      logger.info(TAG, '离开电子书阅读器：已保持听书后台继续播放');
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
    // [修复] 安全清理过渡动画状态，防止页面销毁后覆盖层仍然阻止交互
    this.restoreNormalMode();
    // [修复] 安全清理过渡动画状态，防止页面销毁后覆盖层仍然阻止交互
    eventBus.publish(GameEvent.EBOOK_UPDATED, new BasePayload());
    // [修复] 安全清理过渡动画状态，防止页面销毁后覆盖层仍然阻止交互
    if (!this.isCloseTransitionNavigating) {
      cancelTransition();
    } else {
      logger.info(TAG, 'aboutToDisappear: close transition in progress, skip cancelTransition');
    }
  }

  onPageShow(): void {
    this.setupFullscreenMode();
  }

  onPageHide(): void {
    this.restoreNormalMode();
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
    
    logger.info(TAG, 'EBookReaderPage initialized');
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
      logger.debug(TAG, 'Volume key listener already registered');
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
      this.volumeUpCallback = (event: InputKeyEvent) => {
        logger.info(TAG, '音量键翻页: 上一页 (inputConsumer)');
        // 只在 TXT 格式时处理
        if (this.ebook?.format === EBookFormat.TXT) {
          if (this.textCurrentPageIndex > 0) {
            this.textCurrentPageIndex--;
          }
        }
      };

        // 只在 TXT 格式时处理
      this.volumeDownCallback = (event: InputKeyEvent) => {
        logger.info(TAG, '音量键翻页: 下一页 (inputConsumer)');
      // 注册监听
        if (this.ebook?.format === EBookFormat.TXT) {
          this.textCurrentPageIndex++;
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
    logger.info(TAG, `📤 已通知过渡动画阅读器就绪: ${reason}`);
  }

  /**
  * 加载电子书
  */
  private async loadEBook(bookId: string): Promise<void> {
    try {
      this.hasNotifiedTransitionReaderReady = false;
      this.transitionLoadingProgress = 0;
      this.isLoading = true;
      this.errorMessage = '';
      this.reportTransitionLoadingProgress(0.06, 'load_start');

      logger.info(TAG, `开始加载电子书: ${bookId}`);
      
      // 从数据库加载电子书
      const ebook = await this.ebookDataManager.getEBookById(bookId);
      
      if (!ebook) {
      throw new Error('电子书不存在');
      }

      this.ebook = ebook;
      this.reportTransitionLoadingProgress(0.24, 'ebook_loaded');
      
      // [修复] 优先使用全局设置，除非用户明确修改过该电子书的设置
      // [修复] 优先使用全局设置，除非用户明确修改过该电子书的设置
      const settingsManager = SettingsManager.getInstance();
      const globalThemeIndex = settingsManager.getNumber(SettingKeys.GLOBAL_EBOOK_THEME, 0);
      const globalFontSize = settingsManager.getNumber(SettingKeys.GLOBAL_EBOOK_FONT_SIZE, DEFAULT_EBOOK_READING_SETTINGS.fontSize);
      const globalLineHeight = settingsManager.getNumber(SettingKeys.GLOBAL_EBOOK_LINE_HEIGHT, DEFAULT_EBOOK_READING_SETTINGS.lineHeight);
      const globalPageMargin = settingsManager.getNumber(SettingKeys.GLOBAL_EBOOK_PAGE_MARGIN, DEFAULT_EBOOK_READING_SETTINGS.pageMargin);
      const globalPageMode = settingsManager.getString(SettingKeys.GLOBAL_EBOOK_PAGE_MODE, DEFAULT_EBOOK_READING_SETTINGS.pageMode) as EBookPageMode;
      const themePreset: EBookThemePreset = EBOOK_THEME_PRESETS[globalThemeIndex] || EBOOK_THEME_PRESETS[0];
      
      if (ebook.readingSettings) {
        // followSystemTheme=false 表示用户已自定义设置，应使用保存的设置
          // 使用全局设置覆盖默认设置
          // 使用全局设置覆盖默认设置
        const isDefaultSettings = ebook.readingSettings.followSystemTheme === true;
        
        if (isDefaultSettings) {
          // 使用全局设置覆盖默认设置
          logger.info(TAG, `检测到默认设置，应用全局设置: 主题索引=${globalThemeIndex}, 背景色=${themePreset.backgroundColor}, 字体大小=${globalFontSize}`);
          
          this.fontSize = globalFontSize;
          this.lineHeight = globalLineHeight;
          this.bgColor = themePreset.backgroundColor;
          this.textColor = themePreset.textColor;
          this.pageMargin = globalPageMargin;
          
          // 更新 ebook.readingSettings 以便后续保存
          ebook.readingSettings.fontSize = globalFontSize;
          ebook.readingSettings.lineHeight = globalLineHeight;
          ebook.readingSettings.backgroundColor = themePreset.backgroundColor;
          ebook.readingSettings.textColor = themePreset.textColor;
          ebook.readingSettings.pageMargin = globalPageMargin;
          ebook.readingSettings.pageMode = globalPageMode;
          ebook.readingSettings.nightMode = themePreset.nightMode;
          ebook.readingSettings.followSystemTheme = false;// 应用全局设置后关闭跟随系统主题
        } else {
          // 用户已修改过设置，直接使用保存的设置
          logger.info(TAG, `使用用户自定义设置: 背景色=${ebook.readingSettings.backgroundColor}, 字体大小=${ebook.readingSettings.fontSize}`);
          
          this.fontSize = ebook.readingSettings.fontSize;
          this.lineHeight = ebook.readingSettings.lineHeight;
          this.bgColor = ebook.readingSettings.backgroundColor;
          this.textColor = ebook.readingSettings.textColor;
          this.pageMargin = ebook.readingSettings.pageMargin;
        }
      } else {
        // 没有保存的设置，使用全局设置创建新的设置对象
        logger.info(TAG, `无保存设置，应用全局设置: 主题索引=${globalThemeIndex}, 背景色=${themePreset.backgroundColor}, 字体大小=${globalFontSize}`);
        
        ebook.readingSettings = {
          fontSize: globalFontSize,
          fontFamily: DEFAULT_EBOOK_READING_SETTINGS.fontFamily,
          fontPath: DEFAULT_EBOOK_READING_SETTINGS.fontPath,
          fontWeight: DEFAULT_EBOOK_READING_SETTINGS.fontWeight,
          lineHeight: globalLineHeight,
          backgroundColor: themePreset.backgroundColor,
          textColor: themePreset.textColor,
          themeBgImage: themePreset.themeBgImage || '',
          nightMode: themePreset.nightMode,
          followSystemTheme: true,// [修复] 新电子书设为true，让loadTextReaderSettingsWithGlobalDefaults应用全局设置
          pageMargin: globalPageMargin,
          pageMode: globalPageMode,
          brightness: DEFAULT_EBOOK_READING_SETTINGS.brightness,
          autoSave: DEFAULT_EBOOK_READING_SETTINGS.autoSave,
          saveInterval: DEFAULT_EBOOK_READING_SETTINGS.saveInterval
        };
        
        this.fontSize = globalFontSize;
        this.lineHeight = globalLineHeight;
        this.bgColor = themePreset.backgroundColor;
        this.textColor = themePreset.textColor;
        this.pageMargin = globalPageMargin;
      }

        // 优先使用保存的章节索引
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
          this.restoreTextReadAloudFromDomPos(ebook.readingProgress.domPos);
        }
        
      // 加载当前章节
        if (this.textCurrentPageIndex === 0 && ebook.readingProgress.currentPosition > 0) {
          this.textCurrentPageIndex = ebook.readingProgress.currentPosition;
          logger.info(TAG, `从 currentPosition 恢复页码: ${this.textCurrentPageIndex}`);
        }
      }

      // 调试日志：检查章节内容
      this.reportTransitionLoadingProgress(0.48, 'settings_restored');
      this.currentChapter = ebook.chapters[this.currentChapterIndex];
      
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
      if (ebook.format === EBookFormat.TXT) {
        this.loadTextReaderSettingsWithGlobalDefaults(ebook);
      }
      
      // 初始化文本内容（用于纯文本阅读器）
      if (ebook.format === EBookFormat.TXT) {
        this.textContent = this.getTextContent();
      logger.info(TAG, `电子书加载完成: ${ebook.metadata.title}`);
        this.syncTextReadAloudContext();
      }

      this.reportTransitionLoadingProgress(0.72, 'reader_data_prepared');
      this.isLoading = false;
      this.reportTransitionLoadingProgress(0.84, 'reader_view_shown');
      logger.info(TAG, '📤 已进入阅读器就绪等待阶段，等待具体组件回调');
      
      // ReaderKit占位: buildReaderKitView.onAppear
      // TXT: TextReaderComponent.onReady
      // PDF: PdfKitViewerComponent.onLoadComplete/onLoadError
      // 设置沉浸式模式
      logger.info(TAG, 'ReaderKit view appeared, start loading chapter content');
      
      // 设置沉浸式模式
      this.setupFullscreenMode();
      
    } catch (error) {
      this.errorMessage = `Load chapter failed: ${String(error instanceof Error ? error.message : error)}`;
      this.isLoading = false;
      logger.error(TAG, 'Failed to load chapter content', String(error instanceof Error ? error.message : error));
      this.notifyTransitionReaderReadyOnce('ebook_load_failed');
    }
  }

  /**
  * 加载纯文本阅读器设置（带全局默认设置支持）
  * 用于 TXT 格式电子书，优先使用全局设置，除非用户已修改
  */
  private loadTextReaderSettingsWithGlobalDefaults(ebook: EBook): void {
    const settingsManager = SettingsManager.getInstance();
    
    // 获取全局纯文本阅读器设置
    const globalFontSize = settingsManager.getNumber(SettingKeys.GLOBAL_TEXT_FONT_SIZE, DEFAULT_TEXT_READER_SETTINGS.textStyle.fontSize);
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
          globalBgImageOpacity, globalPageTurnAnimation, globalKeepScreenOn, globalVolumeKeyNav, globalTapToTurn);
        // 用户已修改过设置，使用保存的设置
        ebook.readingSettings.followSystemTheme = false;
        // 用户已修改过设置，使用保存的设置
        this.saveTextReaderSettings();
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
        globalBgImageOpacity, globalPageTurnAnimation, globalKeepScreenOn, globalVolumeKeyNav, globalTapToTurn);
    }
  }

  /**
  * 从全局设置加载纯文本阅读器设置
  */
  private loadTextReaderSettingsFromGlobal(
    fontSize: number, fontFamily: string, fontWeight: number, lineHeight: number, paragraphSpacing: number, firstLineIndent: number,
    pageMargin: number, bgPreset: PresetBackground, useBgImage: boolean, bgImagePath: string,
    bgImageOpacity: number, pageTurnAnimation: TextPageTurnAnimation, keepScreenOn: boolean,
    volumeKeyNav: boolean, tapToTurn: boolean
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
        fontSize: fontSize,
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
    this.fontSize = fontSize;
    this.lineHeight = lineHeight;
    this.bgColor = bgPreset.backgroundColor;
    this.textColor = bgPreset.textColor;
    this.pageMargin = pageMargin;
    // 同步背景图片设置
    this.bgImagePath = useBgImage ? bgImagePath : '';
    this.bgImageOpacity = bgImageOpacity;
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
        fontSize: settings.fontSize,
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
    const rawEngine = settings?.engineType ?? globalDefaults.engineType;
    const safeEngine = (
      rawEngine === ReadAloudEngineType.SYSTEM ||
      rawEngine === ReadAloudEngineType.LEGADO_COMPAT ||
      rawEngine === ReadAloudEngineType.REMOTE
    ) ? rawEngine : ReadAloudEngineType.SYSTEM;

    const speed = Math.max(0.5, Math.min(2.0, settings?.speed ?? globalDefaults.speed));
    const pitch = Math.max(0.5, Math.min(2.0, settings?.pitch ?? globalDefaults.pitch));
    const volume = Math.max(0, Math.min(1, settings?.volume ?? globalDefaults.volume));
    const voiceLanguage = settings?.voiceLanguage ?? globalDefaults.voiceLanguage ?? '';
    const voicePersonRaw = settings?.voicePerson ?? globalDefaults.voicePerson ?? -1;
    const voiceOnlineRaw = settings?.voiceOnline ?? globalDefaults.voiceOnline ?? -1;
    const voicePerson = voicePersonRaw >= 0 ? Math.floor(voicePersonRaw) : -1;
    const voiceOnline = (voiceOnlineRaw === 0 || voiceOnlineRaw === 1) ? voiceOnlineRaw : -1;

    return {
      enabled: settings?.enabled ?? globalDefaults.enabled,
      engineType: safeEngine,
      speed,
      pitch,
      volume,
      continueInBackground: settings?.continueInBackground ?? globalDefaults.continueInBackground,
      autoPlayNextChapter: settings?.autoPlayNextChapter ?? globalDefaults.autoPlayNextChapter,
      pauseOnManualPageTurn: settings?.pauseOnManualPageTurn ?? globalDefaults.pauseOnManualPageTurn,
      voiceLanguage,
      voicePerson,
      voiceOnline
    };
  }

  private loadGlobalReadAloudSettings(): ReadAloudSettings {
    const engineRaw = this.settingsManager.getString(
      SettingKeys.GLOBAL_TEXT_READ_ALOUD_ENGINE,
      DEFAULT_READ_ALOUD_SETTINGS.engineType
    ) as ReadAloudEngineType;

    return {
      enabled: this.settingsManager.getBoolean(
        SettingKeys.GLOBAL_TEXT_READ_ALOUD_ENABLED,
        DEFAULT_READ_ALOUD_SETTINGS.enabled
      ),
      engineType: engineRaw,
      speed: this.settingsManager.getNumber(
        SettingKeys.GLOBAL_TEXT_READ_ALOUD_SPEED,
        DEFAULT_READ_ALOUD_SETTINGS.speed
      ),
      pitch: this.settingsManager.getNumber(
        SettingKeys.GLOBAL_TEXT_READ_ALOUD_PITCH,
        DEFAULT_READ_ALOUD_SETTINGS.pitch
      ),
      volume: this.settingsManager.getNumber(
        SettingKeys.GLOBAL_TEXT_READ_ALOUD_VOLUME,
        DEFAULT_READ_ALOUD_SETTINGS.volume
      ),
      continueInBackground: this.settingsManager.getBoolean(
        SettingKeys.GLOBAL_TEXT_READ_ALOUD_CONTINUE_BG,
        DEFAULT_READ_ALOUD_SETTINGS.continueInBackground
      ),
      autoPlayNextChapter: this.settingsManager.getBoolean(
        SettingKeys.GLOBAL_TEXT_READ_ALOUD_AUTO_PLAY_NEXT_CHAPTER,
        DEFAULT_READ_ALOUD_SETTINGS.autoPlayNextChapter
      ),
      pauseOnManualPageTurn: this.settingsManager.getBoolean(
        SettingKeys.GLOBAL_TEXT_READ_ALOUD_PAUSE_ON_MANUAL_PAGE_TURN,
        DEFAULT_READ_ALOUD_SETTINGS.pauseOnManualPageTurn
      ),
      voiceLanguage: this.settingsManager.getString(
        SettingKeys.GLOBAL_TEXT_READ_ALOUD_VOICE_LANGUAGE,
        DEFAULT_READ_ALOUD_SETTINGS.voiceLanguage ?? ''
      ),
      voicePerson: this.settingsManager.getNumber(
        SettingKeys.GLOBAL_TEXT_READ_ALOUD_VOICE_PERSON,
        DEFAULT_READ_ALOUD_SETTINGS.voicePerson ?? -1
      ),
      voiceOnline: this.settingsManager.getNumber(
        SettingKeys.GLOBAL_TEXT_READ_ALOUD_VOICE_ONLINE,
        DEFAULT_READ_ALOUD_SETTINGS.voiceOnline ?? -1
      )
    };
  }

  private async persistGlobalReadAloudSettings(settings: ReadAloudSettings): Promise<void> {
    try {
      await this.settingsManager.setBoolean(SettingKeys.GLOBAL_TEXT_READ_ALOUD_ENABLED, settings.enabled);
      await this.settingsManager.setString(SettingKeys.GLOBAL_TEXT_READ_ALOUD_ENGINE, settings.engineType);
      await this.settingsManager.setNumber(SettingKeys.GLOBAL_TEXT_READ_ALOUD_SPEED, settings.speed);
      await this.settingsManager.setNumber(SettingKeys.GLOBAL_TEXT_READ_ALOUD_PITCH, settings.pitch);
      await this.settingsManager.setNumber(SettingKeys.GLOBAL_TEXT_READ_ALOUD_VOLUME, settings.volume);
      await this.settingsManager.setBoolean(SettingKeys.GLOBAL_TEXT_READ_ALOUD_CONTINUE_BG, settings.continueInBackground);
      await this.settingsManager.setBoolean(
        SettingKeys.GLOBAL_TEXT_READ_ALOUD_AUTO_PLAY_NEXT_CHAPTER,
        settings.autoPlayNextChapter
      );
      await this.settingsManager.setBoolean(
        SettingKeys.GLOBAL_TEXT_READ_ALOUD_PAUSE_ON_MANUAL_PAGE_TURN,
        settings.pauseOnManualPageTurn
      );
      await this.settingsManager.setString(
        SettingKeys.GLOBAL_TEXT_READ_ALOUD_VOICE_LANGUAGE,
        settings.voiceLanguage ?? ''
      );
      await this.settingsManager.setNumber(
        SettingKeys.GLOBAL_TEXT_READ_ALOUD_VOICE_PERSON,
        settings.voicePerson ?? -1
      );
      await this.settingsManager.setNumber(
        SettingKeys.GLOBAL_TEXT_READ_ALOUD_VOICE_ONLINE,
        settings.voiceOnline ?? -1
      );
    } catch (error) {
      logger.warn(TAG, `保存全局听书设置失败: ${String(error)}`);
    }
  }

  private syncTextReadAloudContext(): void {
    if (!this.ebook || this.ebook.format !== EBookFormat.TXT) {
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

  private calculateTextOverallProgressByChar(charIndex: number): number {
    if (!this.ebook || this.ebook.chapters.length === 0) {
      return 0;
    }

    const totalChapters = this.ebook.chapters.length;
    const chapterLength = this.textContent.length;
    if (chapterLength <= 0) {
      const baseProgress = (this.currentChapterIndex / totalChapters) * 100;
      return Math.max(0, Math.min(100, baseProgress));
    }

    const safeCharIndex = Math.max(0, Math.min(charIndex, chapterLength));
    const chapterProgress = safeCharIndex / chapterLength;
    const overallProgress = ((this.currentChapterIndex + chapterProgress) / totalChapters) * 100;
    return Math.max(0, Math.min(100, overallProgress));
  }

  private tryPersistTextReadAloudProgress(): void {
    if (!this.ebook || this.ebook.format !== EBookFormat.TXT) {
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

    const overallProgress = this.calculateTextOverallProgressByChar(this.textReadAloudCurrentCharIndex);
    this.latestTextProgress = overallProgress;
    this.saveTextReadingProgressWithPage(overallProgress, this.textCurrentPageIndex);
  }

  private updateTextReadAloudContextByPosition(): void {
    if (!this.ebook || this.ebook.format !== EBookFormat.TXT) {
      return;
    }
    this.readAloudController.updateContext({
      bookId: this.ebook.id,
      chapterIndex: this.currentChapterIndex,
      chapterTitle: this.currentChapter?.title || '',
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
    this.latestTextProgress = this.calculateTextOverallProgressByChar(this.textReadAloudCurrentCharIndex);
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
  }

  private onTextUserPageTurnStart(): void {
    if (!this.ebook || this.ebook.format !== EBookFormat.TXT) {
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
    if (!this.ebook || this.ebook.format !== EBookFormat.TXT) {
      return;
    }

    const currentReadAloud = this.getSafeReadAloudSettings(this.textReaderSettings.readAloud);
    let nextReadAloud: ReadAloudSettings = {
      enabled: currentReadAloud.enabled,
      engineType: currentReadAloud.engineType,
      speed: currentReadAloud.speed,
      pitch: currentReadAloud.pitch,
      volume: currentReadAloud.volume,
      continueInBackground: currentReadAloud.continueInBackground,
      autoPlayNextChapter: currentReadAloud.autoPlayNextChapter,
      pauseOnManualPageTurn: currentReadAloud.pauseOnManualPageTurn,
      voiceLanguage: currentReadAloud.voiceLanguage,
      voicePerson: currentReadAloud.voicePerson,
      voiceOnline: currentReadAloud.voiceOnline
    };

    if (!nextReadAloud.enabled) {
      nextReadAloud.enabled = true;
      this.textReaderSettings.readAloud = nextReadAloud;
      this.saveTextReaderSettings();
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
    if (!this.ebook || this.ebook.format !== EBookFormat.TXT) {
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
    this.showReadAloudPanel = true;
    this.readAloudPanelSettings = this.getSafeReadAloudSettings(this.textReaderSettings.readAloud);
    logger.info(TAG, 'Read-aloud settings refreshed');
    this.refreshReadAloudAvailability();
  }

  private updateReadAloudSettings(partial: Partial<ReadAloudSettings>): void {
    if (!this.ebook || this.ebook.format !== EBookFormat.TXT) {
      return;
    }
    logger.debug(TAG, `应用听书设置变更: ${JSON.stringify(partial)}`);
    const current = this.getSafeReadAloudSettings(this.textReaderSettings.readAloud);
    const rawEngine = partial.engineType ?? current.engineType;
    const safeEngine = (
      rawEngine === ReadAloudEngineType.SYSTEM ||
      rawEngine === ReadAloudEngineType.LEGADO_COMPAT ||
      rawEngine === ReadAloudEngineType.REMOTE
    ) ? rawEngine : ReadAloudEngineType.SYSTEM;

    const speed = Math.max(0.5, Math.min(2.0, partial.speed ?? current.speed));
    const pitch = Math.max(0.5, Math.min(2.0, partial.pitch ?? current.pitch));
    const volume = Math.max(0, Math.min(1, partial.volume ?? current.volume));
    const voiceLanguage = partial.voiceLanguage ?? current.voiceLanguage ?? '';
    const voicePersonRaw = partial.voicePerson ?? current.voicePerson ?? -1;
    const voiceOnlineRaw = partial.voiceOnline ?? current.voiceOnline ?? -1;
    const voicePerson = voicePersonRaw >= 0 ? Math.floor(voicePersonRaw) : -1;
    const voiceOnline = (voiceOnlineRaw === 0 || voiceOnlineRaw === 1) ? voiceOnlineRaw : -1;

    const nextReadAloud: ReadAloudSettings = {
      enabled: partial.enabled ?? current.enabled,
      engineType: safeEngine,
      speed,
      pitch,
      volume,
      continueInBackground: partial.continueInBackground ?? current.continueInBackground,
      autoPlayNextChapter: partial.autoPlayNextChapter ?? current.autoPlayNextChapter,
      pauseOnManualPageTurn: partial.pauseOnManualPageTurn ?? current.pauseOnManualPageTurn,
      voiceLanguage,
      voicePerson,
      voiceOnline
    };
    this.readAloudPanelSettings = nextReadAloud;
    this.textReaderSettings.readAloud = nextReadAloud;
    this.saveTextReaderSettings();
    this.persistGlobalReadAloudSettings(nextReadAloud);
    this.syncTextReadAloudContext();

    if (
      partial.engineType !== undefined ||
      partial.voiceLanguage !== undefined ||
      partial.voicePerson !== undefined ||
      partial.voiceOnline !== undefined
    ) {
      this.refreshReadAloudVoices();
    }
  }

  private refreshReadAloudAvailability(): void {
    ReadAloudAvailability.refresh().then((map: ReadAloudEngineAvailabilityMap) => {
      this.readAloudAvailability = map;
      if (!map.SYSTEM) {
        const probeError = ReadAloudAvailability.getLastSystemProbeErrorMessage();
        if (probeError.length > 0) {
          this.readAloudStatusMessage = `System TTS probe failed: ${probeError}`;
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
      } else {
        this.readAloudStatusMessage = 'System TTS is not available on this device';
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
    if (this.ebook.format === EBookFormat.TXT) {
      readAloudSettings = this.getSafeReadAloudSettings(this.textReaderSettings.readAloud);
      wasPlaying = this.readAloudController.getSnapshot().playbackState === ReadAloudPlaybackState.PLAYING;
      if (wasPlaying && !readAloudSettings.autoPlayNextChapter) {
        this.readAloudController.pause('chapter_switch');
      }
    }

    this.currentChapterIndex--;
    this.currentChapter = this.ebook.chapters[this.currentChapterIndex];
    // TXT格式使用页码进度保存，其他格式使用通用方法
    if (this.ebook.format === EBookFormat.TXT) {
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
    if (this.ebook.format === EBookFormat.TXT) {
      readAloudSettings = this.getSafeReadAloudSettings(this.textReaderSettings.readAloud);
      wasPlaying = this.readAloudController.getSnapshot().playbackState === ReadAloudPlaybackState.PLAYING;
      if (wasPlaying && !readAloudSettings.autoPlayNextChapter) {
        this.readAloudController.pause('chapter_switch');
      }
    }

    this.currentChapterIndex++;
    this.currentChapter = this.ebook.chapters[this.currentChapterIndex];
    // TXT格式使用页码进度保存，其他格式使用通用方法
    if (this.ebook.format === EBookFormat.TXT) {
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

      // 立即应用到 Reader Kit（如果控制器已就绪）
      this.ebook.readingSettings = settings;

      // 保存到数据库
      if (this.readerKitController && this.readerKitController.isControllerReady()) {
        this.readerKitController.applyReadingSettings(settings, true);
      logger.info(TAG, '阅读设置已保存');
      }

      // 保存到数据库
      await this.ebookDataManager.saveReadingSettings(this.ebook.id, settings);
      logger.info(TAG, 'Reading settings saved');
    } catch (error) {
      logger.error(TAG, `保存阅读设置失败: ${String(error)}`);
    }
  }

  /**
  * 保存当前设置（简化版本，用于面板中的即时保存）
  */
  private saveSettings(): void {
    if (!this.ebook || !this.ebook.readingSettings) {
      return;
    }

    // 立即应用到 Reader Kit
    this.ebook.readingSettings.fontSize = this.fontSize;
    this.ebook.readingSettings.lineHeight = this.lineHeight;
    this.ebook.readingSettings.backgroundColor = this.bgColor;
    this.ebook.readingSettings.textColor = this.textColor;
    this.ebook.readingSettings.pageMargin = this.pageMargin;

    // 异步保存到数据库
    if (this.readerKitController && this.readerKitController.isControllerReady()) {
      this.readerKitController.applyReadingSettings(this.ebook.readingSettings, true);
    }

  // 当前 DOM 位置（用于 Reader Kit 精确恢复阅读位置）
    this.ebookDataManager.saveReadingSettings(this.ebook.id, this.ebook.readingSettings)
      .then(() => logger.debug(TAG, '设置已保存'))
      .catch((error: Error) => {
        logger.error(TAG, `保存阅读设置失败: ${String(error)}`);
      });
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
      
      if (this.ebook.format === EBookFormat.TXT) {
        domPos = this.buildTextDomPos(this.textCurrentPageIndex);
        currentPosition = this.textCurrentPageIndex;
        chapterId = this.currentChapter?.id || '';
        // EPUB/MOBI 格式：使用 Reader Kit 的 domPos
        progressPercent = this.latestTextProgress > 0 ? this.latestTextProgress : (this.ebook.readingProgress?.progress || 0);
      } else {
        // 从 domPos 中提取 resourceIndex 计算进度
        chapterId = this.currentChapter?.id || `chapter_${this.currentChapterIndex}`;
              // 使用 resourceIndex 作为进度参考
        if (domPos && domPos.length > 0) {
          try {
            const domPosObj: Record<string, number> = JSON.parse(domPos) as Record<string, number>;
            if (domPosObj['resourceIndex'] !== undefined) {
            // 解析失败，使用章节索引
              progressPercent = domPosObj['resourceIndex'];
            }
          } catch (parseError) {
      // 获取已有的阅读时间并累加本次阅读时间
            progressPercent = this.currentChapterIndex;
          }
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
        currentChapterIndex: this.currentChapterIndex,
        currentPosition: currentPosition,
        domPos: domPos,
        progress: progressPercent,
        lastReadTime: Date.now(),
        totalReadingTime: totalReadingTime
      };

      await this.ebookDataManager.saveReadingProgress(progress);
      
      // 更新内存中的阅读进度
      if (this.ebook.readingProgress) {
        this.ebook.readingProgress.totalReadingTime = totalReadingTime;
      }
      
      logger.info(TAG, `阅读进度已保存: 章节=${this.currentChapterIndex}, domPos长度=${domPos.length}, 累计阅读时间=${totalReadingTime.toFixed(2)}分钟`);
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
    this.currentDomPos = domPos;
    
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
    if (!this.ebook || chapterIndex < 0 || chapterIndex >= this.ebook.chapters.length) {
      logger.warn(TAG, `无效的章节索引: ${chapterIndex}`);
      return;
    }
    
    let wasPlaying = false;
    let readAloudSettings: ReadAloudSettings = this.getSafeReadAloudSettings(this.textReaderSettings.readAloud);
    if (this.ebook.format === EBookFormat.TXT) {
      readAloudSettings = this.getSafeReadAloudSettings(this.textReaderSettings.readAloud);
      wasPlaying = this.readAloudController.getSnapshot().playbackState === ReadAloudPlaybackState.PLAYING;
      if (wasPlaying && !readAloudSettings.autoPlayNextChapter) {
        this.readAloudController.pause('chapter_switch');
      }
    }

    logger.info(TAG, `跳转到章节: ${chapterIndex}`);
    
    // 根据电子书格式处理跳转
    this.currentChapterIndex = chapterIndex;
    this.currentChapter = this.ebook.chapters[chapterIndex];
    this.currentDomPos = ''; // 清空 DOM 位置，从章节开头开始
    
      // 纯文本阅读器：重置页码到第一页，并更新文本内容
    if (this.ebook.format === EBookFormat.TXT) {
      // 更新文本内容（触发 TextReaderComponent 重新分页）
      this.textCurrentPageIndex = 0;
      this.textCurrentPageStartCharIndex = 0;
      this.textCurrentPageEndCharIndex = 0;
      this.textReadAloudCurrentCharIndex = 0;
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
      // 其他格式：保存阅读进度
      this.saveReadingProgress();
    } else {
      // 其他格式：保存阅读进度
      this.saveReadingProgress();
    }
  }

  /**
  * 调整字体大小
  * 实时更新UI、应用到阅读器并保存到数据库
  */
  private adjustFontSize(delta: number): void {
    const newSize = Math.max(12, Math.min(32, this.fontSize + delta));
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
        showPageNumber: this.textReaderSettings.showPageNumber,
        showProgress: this.textReaderSettings.showProgress,
        showTime: this.textReaderSettings.showTime,
        showBattery: this.textReaderSettings.showBattery,
        tapToTurn: this.textReaderSettings.tapToTurn,
        volumeKeyNavigation: this.textReaderSettings.volumeKeyNavigation,
        autoScrollSpeed: this.textReaderSettings.autoScrollSpeed,
        curlBackOpacity: this.textReaderSettings.curlBackOpacity
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
  * 显示更多菜单（带动画）
  */
  private showMoreMenuWithAnimation(): void {
    this.showMoreMenu = true;
    animateTo({
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
    animateTo({
      duration: 150,
      curve: Curve.EaseOut
    }, () => {
      this.moreMenuOpacity = 0;
      this.moreMenuScale = 0.95;
      this.moreMenuTranslateY = -10;
    });
    setTimeout(() => {
      this.showMoreMenu = false;
    }, 150);
  }

  /**
  * 显示章节列表（带动画）
  */
  private showChapterListWithAnimation(): void {
    logger.info(TAG, `显示章节列表，当前章节索引: ${this.currentChapterIndex}`);
    this.showChapterList = true;
    animateTo({
      duration: 250,
      curve: curves.springMotion(0.5, 0.8)
    }, () => {
      this.chapterListOpacity = 1;
    });
    
    // 延迟滚动到当前章节，确保列表已渲染
    setTimeout(() => {
        logger.info(TAG, `滚动命令已执行`);
      try {
        this.chapterListScroller.scrollToIndex(this.currentChapterIndex, true, ScrollAlign.CENTER);
        logger.info(TAG, `Chapter list positioned to index ${this.currentChapterIndex}`);
      } catch (error) {
        logger.error(TAG, `滚动失败: ${String(error)}`);
      }
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
  * 显示设置面板（带动画）
  */
  private showSettingsPanelWithAnimation(): void {
    this.showSettingsPanel = true;
    animateTo({
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
    animateTo({
      duration: 200,
      curve: Curve.EaseOut
    }, () => {
      this.settingsPanelOpacity = 0;
      this.settingsPanelScale = 0.95;
      this.settingsPanelTranslateY = 20;
    });
    setTimeout(() => {
      this.showSettingsPanel = false;
    }, 200);
  }

  /**
  * 显示书籍信息弹窗（带动画）
  */
  private showBookInfoDialogWithAnimation(): void {
    this.showBookInfoDialog = true;
    animateTo({
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
    animateTo({
      duration: 200,
      curve: Curve.EaseOut
    }, () => {
      this.bookInfoDialogOpacity = 0;
    });
    setTimeout(() => {
      this.showBookInfoDialog = false;
    }, 200);
  }

  /**
  * 显示字体设置面板（带动画）
  */
  private showFontSettingsPanelWithAnimation(): void {
    this.showFontSettingsPanel = true;
    animateTo({
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
    animateTo({
      duration: 200,
      curve: Curve.EaseOut
    }, () => {
      this.fontSettingsPanelOpacity = 0;
      this.fontSettingsPanelScale = 0.95;
    });
    setTimeout(() => {
      this.showFontSettingsPanel = false;
    }, 200);
  }

  /**
  * 显示阅读设置面板（带动画）
  */
  private showReadingOptionsPanelWithAnimation(): void {
    this.showReadingOptionsPanel = true;
    animateTo({
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
    animateTo({
      duration: 200,
      curve: Curve.EaseOut
    }, () => {
      this.readingOptionsPanelOpacity = 0;
      this.readingOptionsPanelScale = 0.95;
    });
    setTimeout(() => {
      this.showReadingOptionsPanel = false;
    }, 200);
  }

  /**
  * 返回上一页
  */
  private async goBack(): Promise<void> {
    try {
      // Build cover component id used by close animation.
      const ebookId: string = this.ebook?.id || '';
      const coverComponentId: string = this.sourceCoverComponentId || (ebookId ? `cover_ebook_lib_${ebookId}` : '');

      // Save progress first, then trigger close transition.
      this.saveReadingProgress();

      logger.info(TAG, `触发关闭过渡动画（带截图），封面组件ID: ${coverComponentId}`);
      await startBookCloseTransitionWithComponentId(
        'ebook_reader_root',
        coverComponentId
      );

      // Pop immediately after transition starts so detail page is visible during shrink.
      this.isCloseTransitionNavigating = true;
      this.pathStack.pop();
    } catch (error) {
      logger.error(TAG, `goBack error: ${error instanceof Error ? error.message : String(error)}`);
      this.isCloseTransitionNavigating = false;
      cancelTransition();
      this.saveReadingProgress();
      this.pathStack.pop();
    }
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
          this.toggleToolbar();
        })

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
      }
      .width('100%')
      .height('100%')
      .id('ebook_reader_root')
      .onAreaChange((oldValue: Area, newValue: Area) => {
        // 检测屏幕方向变化
        const newWidth = newValue.width as number;
        const newHeight = newValue.height as number;
        const newIsLandscape = newWidth > newHeight;
        if (newIsLandscape !== this.isLandscape) {
          this.isLandscape = newIsLandscape;
          this.screenWidth = newWidth;
      logger.info(TAG, 'EBookReaderPage onReady');
        }
      })
    }
    .onReady((context: NavDestinationContext) => {
      logger.info(TAG, 'EBookReaderPage onReady');
      this.pathStack = context.pathStack;
      
      const params = context.pathInfo.param as EBookReaderParams | null;
      if (params && params.bookId) {
        this.sourceCoverComponentId = params.coverComponentId || '';
        this.loadEBook(params.bookId);
      } else {
        this.errorMessage = 'Invalid ebook ID parameter';
        logger.error(TAG, '缺少电子书ID参数');
      }
    })
    .hideTitleBar(true)
    .backgroundColor(Color.Transparent)
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
          this.pathStack.pop();
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
        // EPUB/MOBI/AZW 格式：使用 Reader Kit 阅读器
      if (this.ebook.format === EBookFormat.PDF) {
        // EPUB/MOBI/AZW 格式：使用 Reader Kit 阅读器
        this.buildPdfReaderView();
      } else if (this.isReaderKitSupported(this.ebook.format)) {
        // TXT 等其他格式：使用文本阅读器
        this.buildReaderKitView();
      } else {
        // TXT 等其他格式：使用文本阅读器
        this.buildTextReaderView();
      }
    }
  }

  /**
  * 检查格式是否支持 Reader Kit
  */
  private isReaderKitSupported(format: EBookFormat): boolean {
    const supportedFormats = [
      EBookFormat.EPUB,
      EBookFormat.MOBI,
      EBookFormat.AZW,
      EBookFormat.AZW3
    ];
    return isReaderKitEnabled() && supportedFormats.includes(format);
  }

  /**
  * 检查当前是否使用文本阅读器（TXT等纯文本格式）
  */
  private isUsingTextReader(): boolean {
    if (!this.ebook) {
      return false;
    }
    // PDF 使用 PDF Kit，EPUB/MOBI/AZW 使用 Reader Kit
    // PDF 使用 PDF Kit，EPUB/MOBI/AZW 使用 Reader Kit
    return this.ebook.format === EBookFormat.TXT;
  }

  /**
  * 构建加载视图
  */
  @Builder
  buildReaderKitView() {
    if (this.ebook) {
      Column() {
        Text('ReaderKit content is loading, please wait...')
          .fontSize(16)
          .fontColor('#666666')
          .textAlign(TextAlign.Center)
          .width('90%')
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .onAppear(() => {
        this.reportTransitionLoadingProgress(0.96, 'readerkit_placeholder_appear');
        this.notifyTransitionReaderReadyOnce('readerkit_placeholder_appear');
      })
    }
  }

  /**
  * 构建加载视图
  */
  @Builder
  buildPdfReaderView() {
    if (this.ebook) {
      // 使用 PDF Kit 阅读器组件
      PdfKitViewerComponent({
        ebook: this.ebook,
        readingSettings: this.ebook.readingSettings,
        themeBgColor: this.bgColor,// 传递背景色，响应主题
        callbacks: {
          onPageChange: (currentPage: number, totalPages: number) => {
            logger.info(TAG, `PDF 页面变化: ${currentPage}/${totalPages}`);
            // 保存阅读进度
            this.currentChapterIndex = currentPage - 1;
            if (this.ebook && this.ebook.chapters.length > this.currentChapterIndex) {
              this.currentChapter = this.ebook.chapters[this.currentChapterIndex];
            }
            // 保存阅读进度
            this.handlePdfProgressChange(currentPage, totalPages);
          },
          onLoadComplete: (pageCount: number) => {
            logger.info(TAG, `PDF load complete, total pages: ${pageCount}`);
            this.reportTransitionLoadingProgress(0.96, 'pdf_load_complete');
            this.notifyTransitionReaderReadyOnce('pdf_load_complete');
          },
          onLoadError: (error: string) => {
            logger.error(TAG, `PDF 加载失败: ${error}`);
            this.errorMessage = error;
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

    // 更新阅读进度
    const progress = totalPages > 0 ? (currentPage / totalPages) * 100 : 0;
    
    // 保存进度
    this.ebook.readingProgress.currentChapterIndex = currentPage - 1;
    this.ebook.readingProgress.progress = progress;
    this.ebook.readingProgress.lastReadTime = Date.now();
    
    // 保存进度
    this.saveReadingProgress();
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
            settings.readAloud = this.getSafeReadAloudSettings(settings.readAloud);
            this.textReaderSettings = settings;
            this.saveTextReaderSettings();
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
    this.showTextReaderSettings = true;
    animateTo({
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
    animateTo({
      duration: 200,
      curve: Curve.EaseOut
    }, () => {
      this.textReaderSettingsOpacity = 0;
      this.textReaderSettingsScale = 0.95;
    });
    setTimeout(() => {
      this.showTextReaderSettings = false;
    }, 200);
  }
  
  /**
  * 保存文本阅读器设置
  * 将 TextReaderSettings 转换为 EBookReadingSettings 并保存到数据库
  */
  private async saveTextReaderSettings(): Promise<void> {
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
  private addCurrentEBookBookmark(): void {
    if (!this.ebook) {
      promptAction.showToast({ message: '电子书信息未就绪' });
      return;
    }
    const currentEbook = this.ebook;

    const chapterTitle = this.currentChapter?.title || `第${this.currentChapterIndex + 1}章`;
    const chapterId = this.currentChapter?.id || '';
    const isTextMode = this.isUsingTextReader();
    const currentPage = isTextMode ? Math.max(0, this.textCurrentPageIndex) : Math.max(0, this.currentChapterIndex);
    const totalChapterCount = this.ebook.chapters.length || 0;
    const pageLabel = isTextMode
      ? `P${currentPage + 1}`
      : `${currentPage + 1}/${Math.max(1, totalChapterCount)}`;

    promptAction.showActionMenu({
      title: '添加电子书书签',
      buttons: [
        { text: chapterTitle, color: '#007AFF' },
        { text: `${chapterTitle} - ${pageLabel}`, color: '#007AFF' },
        { text: '仅记录位置', color: '#007AFF' },
        { text: '取消', color: '#999999' }
      ]
    }).then(async (result: promptAction.ActionMenuSuccessResponse) => {
      if (result.index === 3) {
        return;
      }
      let marker = '';
      if (result.index === 0) {
        marker = chapterTitle;
      } else if (result.index === 1) {
        marker = `${chapterTitle} - ${pageLabel}`;
      }
      const progress = currentEbook.readingProgress
        ? Math.max(0, Math.min(1, (currentEbook.readingProgress.progress || 0) / 100))
        : -1;
      try {
        await this.annotationManager.createBookmark({
          contentType: UnifiedContentType.EBOOK,
          contentId: currentEbook.id,
          title: marker,
          anchor: {
            chapterId,
            chapterTitle,
            chapterIndex: this.currentChapterIndex,
            pageIndex: currentPage,
            progress,
            startOffset: isTextMode ? this.textCurrentPageStartCharIndex : -1,
            endOffset: isTextMode ? this.textCurrentPageEndCharIndex : -1
          }
        });
        promptAction.showToast({ message: '书签已添加' });
      } catch (error) {
        logger.error(TAG, `添加电子书书签失败: ${String(error)}`);
        promptAction.showToast({ message: '添加书签失败' });
      }
    }).catch(() => {});
  }

  private openCurrentEBookAnnotationCenter(): void {
    if (!this.ebook) {
      promptAction.showToast({ message: '电子书信息未就绪' });
      return;
    }
    const params: AnnotationCenterPageParams = {
      contentType: UnifiedContentType.EBOOK,
      contentId: this.ebook.id,
      contentTitle: this.ebook.metadata.title || ''
    };
    try {
      this.pathStack.pushPathByName('AnnotationCenterPage', params);
    } catch (error) {
      logger.error(TAG, `打开摘录中心失败: ${String(error)}`);
      promptAction.showToast({ message: '打开摘录中心失败' });
    }
  }

  @Builder
  buildTopToolbar() {
    Row() {
            // 只在用户释放滑块时触发章节切换，避免拖动过程中频繁触发分页导致卡死
      Button() {
        SymbolGlyph($r('sys.symbol.arrow_left'))
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
        SymbolGlyph($r('sys.symbol.bookmark'))
      }
      .width(48)
      .height(48)
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        this.addCurrentEBookBookmark();
      })

      Button() {
        SymbolGlyph($r('sys.symbol.list_bullet'))
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

      }
      .width(48)
      .height(48)
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        this.showMoreMenuWithAnimation();
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
   * 构建更多菜单
    */
  @Builder
  buildBottomToolbar() {
    Column() {
          // 电子书阅读器：显示字体和阅读设置按钮
      Row() {
        Text(this.currentChapter?.title || `第${this.currentChapterIndex + 1}章`)
          .fontSize(13)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
          .fontFamily(this.appFontFamily)
        
        Text(`${this.currentChapterIndex + 1} / ${this.ebook?.chapters.length || 0}`)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .fontFamily(this.appFontFamily)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 4 })

          // 阅读设置按钮（主题、翻页等）
      Row() {
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
          // 阅读设置按钮（主题、翻页等）
            if (mode === SliderChangeMode.End) {
              const targetIndex = Math.round(value);
              if (targetIndex !== this.currentChapterIndex) {
                this.jumpToChapter(targetIndex);
              }
            }
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16 })

      // 点击遮罩关闭
      Row() {
      // 点击遮罩关闭
        Button() {
          SymbolGlyph($r('sys.symbol.list_bullet'))
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
            Image($r('app.media.ic_book'))
              .width(24)
              .height(24)
              .fillColor($r('app.color.text_primary'))
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
            Image($r('app.media.ic_brightness_high'))
              .width(24)
              .height(24)
              .fillColor($r('app.color.text_primary'))
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
          logger.info(TAG, 'MoreMenu: 书籍信息');
          this.hideMoreMenuWithAnimation();
          this.showBookInfoDialogWithAnimation();
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
          Button('A-')
            .fontSize(14)
            .width(60)
            .height(36)
            .fontFamily(this.appFontFamily)
            .backgroundColor($r('app.color.background_secondary'))
            .fontColor($r('app.color.text_primary'))
            .onClick(() => {
              this.adjustFontSize(-2);
            })

          Button('A+')
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
      .margin({ top: this.statusBarHeight + 56 + 8, right: 12 })
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
          Text('字体设置')
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
          Text('字体设置')
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
              Text('行高')
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
              Text(`${this.pageMargin}`)
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
                .margin({ bottom: 8 })
                .fontFamily(this.appFontFamily)
              
              Text('If metadata is missing, verify source file and parsing rules, then refresh.')
                .fontSize(this.fontSize)
                .lineHeight(this.fontSize * this.lineHeight)
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
              Text(`${this.pageMargin}`)
                .fontSize(14)
                .fontColor($r('app.color.text_primary'))
                .fontFamily(this.appFontFamily)
              Blank()
              Text(`${this.fontSize}`)
                .fontSize(14)
                .fontColor($r('app.color.accent_primary'))
                .fontFamily(this.appFontFamily)
            }
            .width('100%')

            Row({ space: 12 }) {
              Button('A-')
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
                value: this.fontSize,
                min: 12,
                max: 32,
                step: 1
              })
                .layoutWeight(1)
                .onChange((value: number) => {
                  this.fontSize = Math.round(value);
                  this.saveSettings();
                })

              Button('A+')
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
          Text('阅读设置')
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
              Text('Current page')
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
                  Text('Aa')
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
                  Text('Aa')
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
                  this.bgColor = '#FFFFFF';
                  this.textColor = '#333333';
                  this.saveSettings();
                })

            // 其他设置提示
                Column() {
                  Text('Aa')
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
                  this.bgColor = '#F5F0E1';
                  this.textColor = '#5D4037';
                  this.saveSettings();
                })

      // 遮罩
                Column() {
                  Text('Aa')
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
                  this.bgColor = '#1E1E1E';
                  this.textColor = '#D4D4D4';
                  this.saveSettings();
                })

        // 标题栏
                Column() {
                  Text('Aa')
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
                  this.bgColor = '#1B3B2F';
                  this.textColor = '#C8E6C9';
                  this.saveSettings();
                })
              }
              .width('100%')
            }
            .width('100%')

            // 封面和基本信息
            Row() {
                Text(this.ebook?.metadata.title || '未知书名')
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
                    }
                    this.saveSettings();
                  }
                })
            }
            .width('100%')

            Divider().color($r('app.color.divider'))

              // 基本信息
            Text('Current settings apply immediately while reading.')
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
                Text(this.ebook?.metadata.description || '')
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
                Text(this.ebook?.metadata.title || 'Unknown Title')
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
                Text('Description')
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


