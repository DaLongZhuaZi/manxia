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
import { curves, UIContext } from '@kit.ArkUI';
import { display } from '@kit.ArkUI';
import { TextReaderComponent } from '../components/TextReaderComponent';
import { TextReaderSettingsPanel } from '../components/TextReaderSettingsPanel';
import {
  TextReaderSettings,
  TextReadingMode,
  TextPageTurnAnimation,
  BackgroundType,
  DEFAULT_TEXT_READER_SETTINGS,
  isTextFile,
  TextAlignment,
  SavedBackgroundImage,
  TextChapter,
  PRESET_BACKGROUNDS,
  PresetBackground
} from '../Models/TextReaderModels';
import { eventBus, GameEvent, BasePayload } from '../Framework/EventBus';
import { KeyCode, inputConsumer } from '@kit.InputKit';
import type { KeyEvent as InputKeyEvent } from '@kit.InputKit';
import { setReaderReady, startBookCloseTransitionWithComponentId, CoverPosition, cancelTransition } from '../components/BookTransitionOverlay';

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

  // 沉浸式显示状态
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
  @State bgImageOpacity: number = 0.3;  // 背景图片透明度

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
  
  // 章节列表滚动控制器
  private chapterListScroller: Scroller = new Scroller();
  
  // 书籍信息弹窗状态
  @State showBookInfoDialog: boolean = false;
  @State bookInfoDialogOpacity: number = 0;

  // 字体设置面板状态
  @State showFontSettingsPanel: boolean = false;
  @State fontSettingsPanelOpacity: number = 0;
  @State fontSettingsPanelScale: number = 0.95;
  
  // 阅读设置面板状态（主题、翻页等）
  @State showReadingOptionsPanel: boolean = false;
  @State readingOptionsPanelOpacity: number = 0;
  @State readingOptionsPanelScale: number = 0.95;

  // 横屏检测状态
  @State isLandscape: boolean = false;
  @State screenWidth: number = 0;

  // 文本阅读器状态（用于 TXT 等纯文本格式）
  @State textReaderSettings: TextReaderSettings = DEFAULT_TEXT_READER_SETTINGS;
  @State textCurrentPageIndex: number = 0;
  @State textContent: string = '';
  // 跟踪最新的文本阅读进度百分比（避免退出时被旧值覆盖）
  private latestTextProgress: number = 0;
  @State showTextReaderSettings: boolean = false;
  @State textReaderSettingsOpacity: number = 0;
  @State textReaderSettingsScale: number = 0.95;

  // 数据管理器
  private ebookDataManager: EBookDataManager = EBookDataManager.getInstance();
  
  // UI上下文（用于设置沉浸式模式）
  private uiContext: UIContext | undefined = undefined;
  
  // Reader Kit 阅读器控制器（用于实时应用设置和跳转章节）
  private readerKitController: ReaderKitViewerControllerLike | null = null;

  // 阅读时间记录相关
  private readingSessionStartTime: number = 0;  // 阅读会话开始时间
  private accumulatedReadingTime: number = 0;   // 累计阅读时间（分钟）
  private readingTimeTimer: number = -1;        // 阅读时间定时器
  private static readonly READING_TIME_INTERVAL: number = 1000;  // 阅读时间记录间隔（1秒）

  // 音量键翻页相关
  private isVolumeKeyListenerRegistered: boolean = false;
  private volumeUpCallback: ((event: InputKeyEvent) => void) | null = null;
  private volumeDownCallback: ((event: InputKeyEvent) => void) | null = null;

  aboutToAppear(): void {
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (theme: ThemeType) => {
      logger.info(TAG, `主题切换到: ${theme}`);
      // [修复] 只有当用户选择跟随系统主题时才更新背景色
      // 检查当前电子书是否设置了 followSystemTheme
      if (this.ebook?.readingSettings?.followSystemTheme === true) {
        if (theme === 'dark') {
          this.bgColor = '#1E1E1E';
          this.textColor = '#D4D4D4';
        } else {
          this.bgColor = '#FFFFFF';
          this.textColor = '#333333';
        }
        logger.info(TAG, `跟随系统主题，更新背景色: ${this.bgColor}`);
      } else {
        logger.info(TAG, `用户已自定义背景设置，不跟随系统主题`);
      }
    });
    // [修复] 不再在 aboutToAppear 中设置初始背景色
    // 背景色将在 loadEBook 中根据保存的设置或全局设置正确初始化
    
    // 初始化横屏检测
    this.updateScreenOrientation();
    
    // 初始化阅读时间记录
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
    this.lifecycle.destroy();
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    // 注销音量键翻页监听
    this.unregisterVolumeKeyListener();
    // 停止阅读时间记录并累加最后一段时间
    this.stopReadingTimeTracking();
    // 保存阅读进度（包含累计阅读时间）
    this.saveReadingProgress();
    // 恢复正常显示模式
    this.restoreNormalMode();
    // [修复] 发布阅读进度更新事件，通知书库页面刷新
    eventBus.publish(GameEvent.EBOOK_UPDATED, new BasePayload());
    // [修复] 安全清理过渡动画状态，防止页面销毁后覆盖层仍然阻止交互
    cancelTransition();
  }

  onPageHide(): void {
    logger.lifecycle(TAG, '电子书阅读器页面隐藏（进入后台）');
    // 累加当前阅读时间段，确保不丢失
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
    
    // 清除可能存在的旧定时器
    if (this.readingTimeTimer !== -1) {
      clearInterval(this.readingTimeTimer);
    }
    
    // 每1秒累加一次阅读时间
    this.readingTimeTimer = setInterval(() => {
      this.accumulateReadingTime();
    }, EBookReaderPage.READING_TIME_INTERVAL);
    
    logger.info(TAG, '阅读时间追踪已启动');
  }

  /**
   * 停止阅读时间追踪
   */
  private stopReadingTimeTracking(): void {
    // 累加最后一段时间
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
    // 转换为分钟
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
      logger.debug(TAG, '音量键监听已注册，跳过');
      return;
    }

    // 检查是否启用了音量键翻页（默认启用）
    const volumeKeyEnabled = this.textReaderSettings.volumeKeyNavigation ?? true;
    if (!volumeKeyEnabled) {
      logger.info(TAG, '音量键翻页未启用，不注册监听');
      return;
    }

    try {
      // 音量上键配置
      const volumeUpConfig: inputConsumer.KeyPressedConfig = {
        key: KeyCode.KEYCODE_VOLUME_UP,
        action: 1, // 按下按键的行为
        isRepeat: false // 不重复触发
      };

      // 音量下键配置
      const volumeDownConfig: inputConsumer.KeyPressedConfig = {
        key: KeyCode.KEYCODE_VOLUME_DOWN,
        action: 1,
        isRepeat: false
      };

      // 音量上键回调 - 上一页
      this.volumeUpCallback = (event: InputKeyEvent) => {
        logger.info(TAG, '音量键翻页: 上一页 (inputConsumer)');
        // 只在 TXT 格式时处理
        if (this.ebook?.format === EBookFormat.TXT) {
          if (this.textCurrentPageIndex > 0) {
            this.textCurrentPageIndex--;
          }
        }
      };

      // 音量下键回调 - 下一页
      this.volumeDownCallback = (event: InputKeyEvent) => {
        logger.info(TAG, '音量键翻页: 下一页 (inputConsumer)');
        // 只在 TXT 格式时处理
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
   * 加载电子书
   */
  private async loadEBook(bookId: string): Promise<void> {
    try {
      this.isLoading = true;
      this.errorMessage = '';

      logger.info(TAG, `开始加载电子书: ${bookId}`);
      
      // 从数据库加载电子书
      const ebook = await this.ebookDataManager.getEBookById(bookId);
      
      if (!ebook) {
        throw new Error('电子书不存在');
      }

      this.ebook = ebook;
      
      // 加载阅读设置
      // [修复] 优先使用全局设置，除非用户明确修改过该电子书的设置
      const settingsManager = SettingsManager.getInstance();
      const globalThemeIndex = settingsManager.getNumber(SettingKeys.GLOBAL_EBOOK_THEME, 0);
      const globalFontSize = settingsManager.getNumber(SettingKeys.GLOBAL_EBOOK_FONT_SIZE, DEFAULT_EBOOK_READING_SETTINGS.fontSize);
      const globalLineHeight = settingsManager.getNumber(SettingKeys.GLOBAL_EBOOK_LINE_HEIGHT, DEFAULT_EBOOK_READING_SETTINGS.lineHeight);
      const globalPageMargin = settingsManager.getNumber(SettingKeys.GLOBAL_EBOOK_PAGE_MARGIN, DEFAULT_EBOOK_READING_SETTINGS.pageMargin);
      const globalPageMode = settingsManager.getString(SettingKeys.GLOBAL_EBOOK_PAGE_MODE, DEFAULT_EBOOK_READING_SETTINGS.pageMode) as EBookPageMode;
      const themePreset: EBookThemePreset = EBOOK_THEME_PRESETS[globalThemeIndex] || EBOOK_THEME_PRESETS[0];
      
      if (ebook.readingSettings) {
        // [修复] 简化判断逻辑：只依赖 followSystemTheme 标志
        // followSystemTheme=true 表示用户从未自定义过设置，应使用全局设置
        // followSystemTheme=false 表示用户已自定义设置，应使用保存的设置
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
          ebook.readingSettings.followSystemTheme = false; // 应用全局设置后关闭跟随系统主题
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
          followSystemTheme: true, // [修复] 新电子书设为true，让loadTextReaderSettingsWithGlobalDefaults应用全局设置
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

      // 定位到上次阅读位置
      if (ebook.readingProgress) {
        // 优先使用保存的章节索引
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
            logger.info(TAG, `恢复阅读位置（通过章节ID）: 章节索引=${this.currentChapterIndex}`);
          }
        }
        
        // 恢复 DOM 位置
        if (ebook.readingProgress.domPos) {
          this.currentDomPos = ebook.readingProgress.domPos;
          logger.info(TAG, `恢复 DOM 位置: ${this.currentDomPos}`);
          
          // 对于 TXT 阅读器，从 domPos 恢复页码
          // 格式: "page:N" 其中 N 是页码
          if (ebook.readingProgress.domPos.startsWith('page:')) {
            const pageIndex = parseInt(ebook.readingProgress.domPos.substring(5), 10);
            if (!isNaN(pageIndex) && pageIndex >= 0) {
              this.textCurrentPageIndex = pageIndex;
              logger.info(TAG, `恢复文本阅读器页码: ${pageIndex}`);
            }
          }
        }
        
        // 备用：从 currentPosition 恢复页码
        if (this.textCurrentPageIndex === 0 && ebook.readingProgress.currentPosition > 0) {
          this.textCurrentPageIndex = ebook.readingProgress.currentPosition;
          logger.info(TAG, `从 currentPosition 恢复页码: ${this.textCurrentPageIndex}`);
        }
      }

      // 加载当前章节
      this.currentChapter = ebook.chapters[this.currentChapterIndex];
      
      // 调试日志：检查章节内容
      logger.info(TAG, `章节数量: ${ebook.chapters.length}`);
      if (this.currentChapter) {
        logger.info(TAG, `当前章节标题: ${this.currentChapter.title}`);
        logger.info(TAG, `当前章节内容长度: ${this.currentChapter.content?.length || 0} 字符`);
        logger.info(TAG, `当前章节内容前100字: ${this.currentChapter.content?.substring(0, 100) || '(空)'}`);
      } else {
        logger.warn(TAG, '当前章节为空');
      }

      // 如果是TXT格式，加载 TextReaderSettings
      if (ebook.format === EBookFormat.TXT) {
        this.loadTextReaderSettingsWithGlobalDefaults(ebook);
      }
      
      // 初始化文本内容（用于纯文本阅读器）
      if (ebook.format === EBookFormat.TXT) {
        this.textContent = this.getTextContent();
        logger.info(TAG, `初始化文本内容，长度: ${this.textContent.length}`);
      }

      this.isLoading = false;
      logger.info(TAG, `电子书加载完成: ${ebook.metadata.title}`);
      
      // 通知过渡动画阅读器就绪
      // 注意：TXT 格式由 TextReaderComponent 的 onReady 回调通知，确保分页完成后才显示
      if (ebook.format !== EBookFormat.TXT) {
        setReaderReady();
        logger.info(TAG, '📤 已通知过渡动画阅读器就绪');
      } else {
        logger.info(TAG, '📤 TXT格式等待TextReaderComponent分页完成后通知');
      }
      
      // 设置沉浸式模式
      this.setupFullscreenMode();
      
    } catch (error) {
      this.errorMessage = `加载失败: ${String(error instanceof Error ? error.message : error)}`;
      this.isLoading = false;
      logger.error(TAG, '加载电子书失败', String(error instanceof Error ? error.message : error));
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
    
    // 获取全局背景色和文字颜色
    const globalBgPreset = PRESET_BACKGROUNDS[globalBgColorIndex] || PRESET_BACKGROUNDS[0];
    
    if (ebook.readingSettings) {
      // [修复] 简化判断逻辑：只依赖 followSystemTheme 标志
      // followSystemTheme=true 表示用户从未自定义过设置，应使用全局设置
      // followSystemTheme=false 表示用户已自定义设置，应使用保存的设置
      const isDefaultSettings = ebook.readingSettings.followSystemTheme === true;
      
      if (isDefaultSettings) {
        // 使用全局设置
        logger.info(TAG, `纯文本阅读器检测到默认设置，应用全局设置: 字体大小=${globalFontSize}, 字体=${globalFontFamily}, 背景色=${globalBgPreset.backgroundColor}`);
        this.loadTextReaderSettingsFromGlobal(globalFontSize, globalFontFamily, globalFontWeight, globalLineHeight, globalParagraphSpacing, 
          globalFirstLineIndent, globalPageMargin, globalBgPreset, globalUseBgImage, globalBgImagePath, 
          globalBgImageOpacity, globalPageTurnAnimation, globalKeepScreenOn, globalVolumeKeyNav, globalTapToTurn);
        // [修复] 应用全局设置后，设置 followSystemTheme=false，表示已初始化，下次使用保存的设置
        ebook.readingSettings.followSystemTheme = false;
        // [修复] 立即保存设置到数据库，确保全局背景图片与电子书的关联被持久化
        this.saveTextReaderSettings();
      } else {
        // 用户已修改过设置，使用保存的设置
        logger.info(TAG, `纯文本阅读器使用用户自定义设置: 字体大小=${ebook.readingSettings.fontSize}, 背景色=${ebook.readingSettings.backgroundColor}`);
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
      curlBackOpacity: 90
    };
    
    // 同步更新 fontSize 等状态变量
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
      curlBackOpacity: 90
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
    
    // 获取当前系统主题
    const currentTheme = this.themeState.currentTheme;
    const isDarkMode = currentTheme === ThemeType.DARK;
    
    logger.info(TAG, `应用系统主题: currentTheme=${currentTheme}, isDarkMode=${isDarkMode}`);
    
    if (isDarkMode) {
      // 夜间模式
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
      logger.warn(TAG, '已经是第一章');
      return;
    }

    this.currentChapterIndex--;
    this.currentChapter = this.ebook.chapters[this.currentChapterIndex];
    // TXT格式使用页码进度保存，其他格式使用通用方法
    if (this.ebook.format === EBookFormat.TXT) {
      this.textCurrentPageIndex = 0;
      this.textContent = this.getTextContent();
      // 计算全书进度：当前章节索引 / 总章节数 * 100
      const totalChapters = this.ebook.chapters?.length || 1;
      const overallProgress = (this.currentChapterIndex / totalChapters) * 100;
      this.saveTextReadingProgressWithPage(overallProgress, 0);
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
      logger.warn(TAG, '已经是最后一章');
      return;
    }

    this.currentChapterIndex++;
    this.currentChapter = this.ebook.chapters[this.currentChapterIndex];
    // TXT格式使用页码进度保存，其他格式使用通用方法
    if (this.ebook.format === EBookFormat.TXT) {
      this.textCurrentPageIndex = 0;
      this.textContent = this.getTextContent();
      // 计算全书进度：当前章节索引 / 总章节数 * 100
      const totalChapters = this.ebook.chapters?.length || 1;
      const overallProgress = (this.currentChapterIndex / totalChapters) * 100;
      this.saveTextReadingProgressWithPage(overallProgress, 0);
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
      // 更新本地状态
      this.fontSize = settings.fontSize;
      this.lineHeight = settings.lineHeight;
      this.bgColor = settings.backgroundColor;
      this.textColor = settings.textColor;
      this.pageMargin = settings.pageMargin;

      // 更新电子书设置
      this.ebook.readingSettings = settings;

      // 立即应用到 Reader Kit（如果控制器已就绪）
      if (this.readerKitController && this.readerKitController.isControllerReady()) {
        this.readerKitController.applyReadingSettings(settings, true);
        logger.info(TAG, '阅读设置已立即应用到 Reader Kit');
      }

      // 保存到数据库
      await this.ebookDataManager.saveReadingSettings(this.ebook.id, settings);
      logger.info(TAG, '阅读设置已保存');
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

    // 更新电子书设置对象
    this.ebook.readingSettings.fontSize = this.fontSize;
    this.ebook.readingSettings.lineHeight = this.lineHeight;
    this.ebook.readingSettings.backgroundColor = this.bgColor;
    this.ebook.readingSettings.textColor = this.textColor;
    this.ebook.readingSettings.pageMargin = this.pageMargin;

    // 立即应用到 Reader Kit
    if (this.readerKitController && this.readerKitController.isControllerReady()) {
      this.readerKitController.applyReadingSettings(this.ebook.readingSettings, true);
    }

    // 异步保存到数据库
    this.ebookDataManager.saveReadingSettings(this.ebook.id, this.ebook.readingSettings)
      .then(() => logger.debug(TAG, '设置已保存'))
      .catch((error: Error) => logger.error(TAG, `保存设置失败: ${error.message}`));
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
      logger.debug(TAG, '正在保存进度，跳过重复请求');
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
        domPos = `page:${this.textCurrentPageIndex}`;
        currentPosition = this.textCurrentPageIndex;
        chapterId = this.currentChapter?.id || '';
        // TXT格式：使用翻页时记录的最新进度值，避免被旧值覆盖
        progressPercent = this.latestTextProgress > 0 ? this.latestTextProgress : (this.ebook.readingProgress?.progress || 0);
      } else {
        // EPUB/MOBI 格式：使用 Reader Kit 的 domPos
        chapterId = this.currentChapter?.id || `chapter_${this.currentChapterIndex}`;
        // 从 domPos 中提取 resourceIndex 计算进度
        if (domPos && domPos.length > 0) {
          try {
            const domPosObj: Record<string, number> = JSON.parse(domPos) as Record<string, number>;
            if (domPosObj['resourceIndex'] !== undefined) {
              // 使用 resourceIndex 作为进度参考
              progressPercent = domPosObj['resourceIndex'];
            }
          } catch (parseError) {
            // 解析失败，使用章节索引
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

  // 上次保存进度的时间戳，用于防抖
  private lastProgressSaveTime: number = 0;
  // 进度保存的最小间隔（毫秒）
  private static readonly PROGRESS_SAVE_INTERVAL: number = 2000;
  // 互斥锁：防止并发保存导致 SQLite 约束违反
  private isSavingProgress: boolean = false;

  /**
   * 处理 Reader Kit 进度变化回调（带防抖）
   */
  private handleProgressChange(progress: number, domPos: string): void {
    this.currentDomPos = domPos;
    
    // 防抖：检查距离上次保存的时间间隔
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
    
    logger.info(TAG, `跳转到章节: ${chapterIndex}`);
    
    // 更新本地状态
    this.currentChapterIndex = chapterIndex;
    this.currentChapter = this.ebook.chapters[chapterIndex];
    this.currentDomPos = ''; // 清空 DOM 位置，从章节开头开始
    
    // 根据电子书格式处理跳转
    if (this.ebook.format === EBookFormat.TXT) {
      // 纯文本阅读器：重置页码到第一页，并更新文本内容
      this.textCurrentPageIndex = 0;
      // 更新文本内容（触发 TextReaderComponent 重新分页）
      this.textContent = this.getTextContent();
      logger.info(TAG, `纯文本阅读器跳转到章节 ${chapterIndex}，内容长度: ${this.textContent.length}`);
      // 计算全书进度：当前章节索引 / 总章节数 * 100
      const totalChapters = this.ebook.chapters?.length || 1;
      const overallProgress = (chapterIndex / totalChapters) * 100;
      this.saveTextReadingProgressWithPage(overallProgress, 0);
    } else if (this.readerKitController && this.readerKitController.isControllerReady()) {
      // Reader Kit 格式：通过控制器跳转
      await this.readerKitController.goToChapter(chapterIndex, '');
      // 保存阅读进度
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
      return; // 没有变化，不需要更新
    }
    
    this.fontSize = newSize;
    logger.debug(TAG, `字体大小调整为: ${this.fontSize}`);
    
    // 同步更新 textReaderSettings（用于 TXT 阅读器）
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
      logger.info(TAG, `尝试滚动到章节: ${this.currentChapterIndex}`);
      try {
        this.chapterListScroller.scrollToIndex(this.currentChapterIndex, true, ScrollAlign.CENTER);
        logger.info(TAG, `滚动命令已执行`);
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
      // 使用当前电子书ID构建封面组件ID，获取正确的封面位置
      const ebookId: string = this.ebook?.id || '';
      const coverComponentId: string = ebookId ? `cover_ebook_lib_${ebookId}` : '';
      
      // 触发关闭过渡动画（带截图和动态封面位置）
      logger.info(TAG, `触发关闭过渡动画（带截图），封面组件ID: ${coverComponentId}`);
      await startBookCloseTransitionWithComponentId(
        'ebook_reader_root',
        coverComponentId,
        () => {
          logger.info(TAG, '关闭过渡动画完成');
        }
      );
      
      this.saveReadingProgress();
      setTimeout(() => {
        this.pathStack.pop();
        logger.info(TAG, '返回上一页');
      }, 50);
    } catch (error) {
      logger.error(TAG, `goBack error: ${error instanceof Error ? error.message : String(error)}`);
      // [修复] 确保在异常情况下也能返回，重置过渡动画状态
      cancelTransition();
      this.saveReadingProgress();
      this.pathStack.pop();
    }
  }

  build() {
    NavDestination() {
      Stack() {
        // 背景层 - 扩展到系统栏区域实现完全沉浸式
        // 加载时使用透明背景，让翻开动画的背景层可见
        // 加载完成后，背景由 TextReaderComponent 或 ReaderKitViewerComponent 提供
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

        // 章节列表面板
        if (this.showChapterList && this.ebook) {
          this.buildChapterListPanel()
        }

        // 更多菜单
        if (this.showMoreMenu) {
          this.buildMoreMenu()
        }

        // 阅读设置面板（旧的，保留兼容）
        if (this.showSettingsPanel && this.ebook) {
          this.buildSettingsPanel()
        }

        // 字体设置面板
        if (this.showFontSettingsPanel && this.ebook) {
          this.buildFontSettingsPanel()
        }

        // 阅读设置面板（主题等）
        if (this.showReadingOptionsPanel && this.ebook) {
          this.buildReadingOptionsPanel()
        }

        // 书籍信息弹窗
        if (this.showBookInfoDialog && this.ebook) {
          this.buildBookInfoDialog()
        }

        // 文本阅读器设置面板（独立渲染，确保在最上层）
        if (this.showTextReaderSettings) {
          this.buildTextReaderSettingsPanel()
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
          logger.info(TAG, `屏幕方向变化: ${this.isLandscape ? '横屏' : '竖屏'}`);
        }
      })
    }
    .onReady((context: NavDestinationContext) => {
      logger.info(TAG, 'EBookReaderPage onReady');
      this.pathStack = context.pathStack;
      
      const params = context.pathInfo.param as EBookReaderParams | null;
      if (params && params.bookId) {
        this.loadEBook(params.bookId);
      } else {
        this.errorMessage = '缺少电子书ID参数';
        logger.error(TAG, '缺少电子书ID参数');
      }
    })
    .hideTitleBar(true)
    .backgroundColor(Color.Transparent)
    .onBackPressed(() => {
      // 返回键处理 - 调用 goBack() 触发关闭过渡动画
      this.goBack();
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
        .width(50)
        .height(50)
        .color(Color.White)  // 白色加载图标配合黑色背景

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
    .backgroundColor(Color.Transparent)  // 透明背景，配合翻开动画的黑色底页
    .padding({ top: this.statusBarHeight, bottom: this.navigationBarHeight })
  }

  /**
   * 构建错误视图
   */
  @Builder
  buildErrorView() {
    Column({ space: 16 }) {
      Text('❌')
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
   * 构建阅读器视图
   */
  @Builder
  buildReaderView() {
    if (this.ebook) {
      // 根据格式选择合适的阅读器
      if (this.ebook.format === EBookFormat.PDF) {
        // PDF格式：使用 Web 组件预览
        this.buildPdfReaderView();
      } else if (this.isReaderKitSupported(this.ebook.format)) {
        // EPUB/MOBI/AZW 格式：使用 Reader Kit 阅读器
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
    // TXT 格式使用自定义文本阅读器
    // PDF 使用 PDF Kit，EPUB/MOBI/AZW 使用 Reader Kit
    return this.ebook.format === EBookFormat.TXT;
  }

  /**
   * 构建 Reader Kit 阅读器视图
   */
  @Builder
  buildReaderKitView() {
    if (this.ebook) {
      Column() {
        Text('ReaderKit 已临时屏蔽，模拟器不加载该能力')
          .fontSize(16)
          .fontColor('#666666')
          .textAlign(TextAlign.Center)
          .width('90%')
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
  }

  /**
   * 构建PDF阅读器视图
   * 使用 PDF Kit 的 PdfView 组件（单页非连续模式）
   * 通过 goToPage 实现精确的页面控制和进度保存
   */
  @Builder
  buildPdfReaderView() {
    if (this.ebook) {
      // 使用 PDF Kit 阅读器组件
      PdfKitViewerComponent({
        ebook: this.ebook,
        readingSettings: this.ebook.readingSettings,
        themeBgColor: this.bgColor, // 传递背景色，响应主题
        callbacks: {
          onPageChange: (currentPage: number, totalPages: number) => {
            logger.info(TAG, `PDF 页面变化: ${currentPage}/${totalPages}`);
            // 更新当前章节索引（PDF 中每页对应一个章节）
            this.currentChapterIndex = currentPage - 1;
            if (this.ebook && this.ebook.chapters.length > this.currentChapterIndex) {
              this.currentChapter = this.ebook.chapters[this.currentChapterIndex];
            }
            // 保存阅读进度
            this.handlePdfProgressChange(currentPage, totalPages);
          },
          onLoadComplete: (pageCount: number) => {
            logger.info(TAG, `PDF 加载完成，共 ${pageCount} 页`);
          },
          onLoadError: (error: string) => {
            logger.error(TAG, `PDF 加载失败: ${error}`);
            this.errorMessage = error;
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

    // 计算进度百分比
    const progress = totalPages > 0 ? (currentPage / totalPages) * 100 : 0;
    
    // 更新阅读进度
    this.ebook.readingProgress.currentChapterIndex = currentPage - 1;
    this.ebook.readingProgress.progress = progress;
    this.ebook.readingProgress.lastReadTime = Date.now();
    
    // 保存进度
    this.saveReadingProgress();
    logger.debug(TAG, `PDF 进度已保存: 第 ${currentPage} 页, ${progress.toFixed(1)}%`);
  }

  /**
   * 构建文本阅读器视图
   * 使用自定义的 TextReaderComponent 组件，支持翻页动画、自定义背景等
   */
  @Builder
  buildTextReaderView() {
    Stack() {
      // 文本阅读器组件
      // 使用 @State textContent 而不是 getTextContent()，以便章节切换时触发更新
      TextReaderComponent({
        content: this.textContent,
        chapters: this.getTextChapters(),
        settings: this.textReaderSettings,
        currentChapterIndex: this.currentChapterIndex,
        currentPageIndex: this.textCurrentPageIndex,
        bottomStatusBarHeight: 28,  // 底部状态栏高度，避让时间、电量、页码显示区域
        onPageChange: (pageIndex: number, totalPages: number) => {
          this.textCurrentPageIndex = pageIndex;
          logger.debug(TAG, `文本阅读器页面切换: ${pageIndex + 1}/${totalPages}`);
          // 计算全书进度（而非章节内进度）
          // 公式: (当前章节索引 + 当前页在章节内的比例) / 总章节数 * 100
          const totalChapters = this.ebook?.chapters?.length || 1;
          const chapterProgress = totalPages > 0 ? (pageIndex + 1) / totalPages : 0;
          const overallProgress = ((this.currentChapterIndex + chapterProgress) / totalChapters) * 100;
          logger.debug(TAG, `文本阅读进度: ${overallProgress.toFixed(1)}%`);
          this.saveTextReadingProgressWithPage(overallProgress, pageIndex);
        },
        onChapterChange: (chapterIndex: number) => {
          this.currentChapterIndex = chapterIndex;
          this.currentChapter = this.ebook?.chapters[chapterIndex] || null;
          // 章节切换时更新文本内容
          this.textContent = this.getTextContent();
        },
        onProgressChange: (progress: number) => {
          logger.debug(TAG, `文本阅读进度: ${progress.toFixed(1)}%`);
          // 不在这里保存，改为在 onPageChange 中保存
        },
        onTapCenter: () => {
          this.toggleToolbar();
        },
        onReady: () => {
          // 文本阅读器分页完成，通知过渡动画阅读器就绪
          logger.info(TAG, '📖 文本阅读器分页完成，通知过渡动画');
          setReaderReady();
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
    
    // 如果有章节，返回当前章节内容
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
      logger.debug(TAG, '正在保存进度，跳过重复请求');
      return;
    }
    
    this.isSavingProgress = true;
    
    // 记录最新进度，避免退出时被旧值覆盖
    this.latestTextProgress = progress;
    
    try {
      const readingProgress: EBookReadingProgress = {
        bookId: this.ebook.id,
        currentChapterId: this.currentChapter?.id || '',
        currentChapterIndex: this.currentChapterIndex,
        currentPosition: pageIndex,  // 保存当前页码
        domPos: `page:${pageIndex}`,  // 使用特殊格式标记页码
        progress: progress,
        lastReadTime: Date.now(),
        totalReadingTime: 0
      };
      
      await this.ebookDataManager.saveReadingProgress(readingProgress);
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
   * 构建文本阅读器设置面板
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
            this.textReaderSettings = settings;
            this.saveTextReaderSettings();
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
      // 确保 readingSettings 存在
      if (!this.ebook.readingSettings) {
        this.ebook.readingSettings = DEFAULT_EBOOK_READING_SETTINGS;
      }

      // 从 textReaderSettings 同步到 ebook.readingSettings
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
      
      // 背景设置
      settings.backgroundType = this.textReaderSettings.background.type;
      settings.backgroundColor = this.textReaderSettings.background.color || '#F5F0E1';
      settings.backgroundImagePath = this.textReaderSettings.background.imagePath || '';
      settings.backgroundImageOpacity = this.textReaderSettings.background.imageOpacity || 1.0;
      
      // 用户设置了自定义背景，禁用跟随系统主题
      settings.followSystemTheme = false;
      
      // 翻页设置
      settings.pageMargin = this.textReaderSettings.pageMargins.left;
      settings.pageTurnAnimation = this.textReaderSettings.pageTurnAnimation;
      settings.tapToTurn = this.textReaderSettings.tapToTurn;
      settings.volumeKeyNavigation = this.textReaderSettings.volumeKeyNavigation;
      settings.keepScreenOn = this.textReaderSettings.keepScreenOn;
      
      // 显示设置
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
   * 构建顶部工具栏
   */
  @Builder
  buildTopToolbar() {
    Row() {
      // 返回按钮
      Button() {
        SymbolGlyph($r('sys.symbol.arrow_left'))
      }
      .width(48)
      .height(48)
      .backgroundColor(Color.Transparent)
      .onClick(() => this.goBack())

      // 标题区域 - 只显示书名，章节信息移到底部
      Text(this.ebook?.metadata.title || '电子书阅读器')
        .fontSize(this.isLandscape ? 16 : 18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .margin({ left: 12 })
        .fontFamily(this.appFontFamily)

      // 菜单按钮
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
   * 构建底部工具栏
   */
  @Builder
  buildBottomToolbar() {
    Column() {
      // 章节信息（从顶部移到这里）
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

      // 章节进度条
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
            // 只在用户释放滑块时触发章节切换，避免拖动过程中频繁触发分页导致卡死
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

      // 控制按钮区域 - 根据阅读器类型显示不同按钮
      Row() {
        // 目录按钮
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

        // 根据文件格式显示不同的设置按钮
        if (this.isUsingTextReader()) {
          // 纯文本阅读器：显示综合设置按钮
          Button() {
            SymbolGlyph($r('sys.symbol.eye'))
          }
          .width(64)
          .height(48)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.showTextReaderSettingsWithAnimation();
          })
        } else {
          // 电子书阅读器：显示字体和阅读设置按钮
          // 字体设置按钮
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

          // 阅读设置按钮（主题、翻页等）
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
   * 构建更多菜单
   */
  @Builder
  buildMoreMenu() {
    Stack() {
      // 点击遮罩关闭
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.hideMoreMenuWithAnimation();
        })

      // 菜单面板
      Column() {
        // 书籍信息
        Row() {
          Text('书籍信息')
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

        // 字体设置
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

        // 字体调整按钮
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
   * 构建章节列表面板
   */
  @Builder
  buildChapterListPanel() {
    Stack() {
      // 遮罩
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.background_overlay'))
        .opacity(0.5 * this.chapterListOpacity)
        .onClick(() => {
          this.hideChapterListWithAnimation();
        })

      // 面板
      Column() {
        // 标题栏
        Row() {
          Text('目录')
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

        // 章节列表
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
                // 跳转到选中的章节
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
   * 构建设置面板 - 使用完整的 EBookReadingSettingsPanel 组件
   */
  @Builder
  buildSettingsPanel() {
    Stack() {
      // 遮罩
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.background_overlay'))
        .opacity(0.5 * this.settingsPanelOpacity)
        .onClick(() => {
          this.hideSettingsPanelWithAnimation();
        })

      // 使用完整的阅读设置面板组件
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
   * 构建字体设置面板（大小、行高、页边距、预览）
   */
  @Builder
  buildFontSettingsPanel() {
    Stack() {
      // 遮罩
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.background_overlay'))
        .opacity(0.5 * this.fontSettingsPanelOpacity)
        .onClick(() => {
          this.hideFontSettingsPanelWithAnimation();
        })

      // 字体设置面板
      Column() {
        // 标题栏
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
            this.hideFontSettingsPanelWithAnimation();
          })
        }
        .width('100%')
        .padding({ left: 20, right: 12, top: 16, bottom: 12 })

        Divider().color($r('app.color.divider'))

        Scroll() {
          Column({ space: 16 }) {
            // 预览区域
            Column() {
              Text('预览效果')
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
                .margin({ bottom: 8 })
                .fontFamily(this.appFontFamily)
              
              Text('这是一段预览文字，用于展示当前的字体设置效果。调整下方的设置项可以实时看到效果变化。')
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

            // 字体大小
            Row() {
              Text('字体大小')
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

            // 行高
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

            // 页边距
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
   * 构建阅读设置面板（主题、翻页模式等）
   */
  @Builder
  buildReadingOptionsPanel() {
    Stack() {
      // 遮罩
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.background_overlay'))
        .opacity(0.5 * this.readingOptionsPanelOpacity)
        .onClick(() => {
          this.hideReadingOptionsPanelWithAnimation();
        })

      // 阅读设置面板
      Column() {
        // 标题栏
        Row() {
          Text('阅读设置')
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
            // 主题设置
            Column({ space: 12 }) {
              Text('阅读主题')
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
                .fontFamily(this.appFontFamily)

              Row({ space: 12 }) {
                // 浅色主题
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

                // 护眼主题
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

                // 深色主题
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

                // 墨绿主题
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

            // 跟随系统主题
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
                    }
                    this.saveSettings();
                  }
                })
            }
            .width('100%')

            Divider().color($r('app.color.divider'))

            // 其他设置提示
            Text('更多阅读设置可在书籍详情页的设置中调整')
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
   * 构建书籍信息弹窗
   */
  @Builder
  buildBookInfoDialog() {
    Stack() {
      // 遮罩
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.background_overlay'))
        .opacity(0.5 * this.bookInfoDialogOpacity)
        .onClick(() => {
          this.hideBookInfoDialogWithAnimation();
        })

      // 书籍信息面板
      Column() {
        // 标题栏
        Row() {
          Text('书籍信息')
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

        // 书籍信息内容
        Scroll() {
          Column({ space: 16 }) {
            // 封面和基本信息
            Row({ space: 16 }) {
              // 封面
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

              // 基本信息
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

            // 详细信息列表
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
   * 构建书籍信息项
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

