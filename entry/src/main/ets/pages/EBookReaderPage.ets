// 文件路径: entry/src/main/ets/pages/EBookReaderPage.ets
/**
 * 电子书阅读器页面
 * 支持TXT、EPUB等格式的电子书阅读
 * 采用与漫画阅读器一致的沉浸式设计风格
 */

import { logger } from '../Utils/Logger';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { ThemeManager, ThemeType, GlassEffectContext } from '../Framework/Managers/ThemeManager';
import { WindowManager, DisplayMode } from '../Utils/WindowManager';
import { EBook, EBookChapter, EBookReadingProgress, EBookReadingSettings, EBookPageMode, EBookFormat, DEFAULT_EBOOK_READING_SETTINGS } from '../Models/EBookModels';
import { EBookDataManager } from '../Framework/Data/EBookDataManager';
import { PdfViewerComponent } from '../Framework/Components/PdfViewerComponent';
import { ReaderKitViewerComponent, ReaderKitViewerController } from '../Framework/Components/ReaderKitViewerComponent';
import { PdfKitViewerComponent, PdfViewerCallbacks } from '../Framework/Components/PdfKitViewerComponent';
import { EBookReadingSettingsPanel } from '../Framework/Components/EBookReadingSettingsPanel';
import { curves, UIContext } from '@kit.ArkUI';

const TAG = 'EBookReaderPage';

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
  private componentId: string = 'EBookReaderPage';
  private themeManager: ThemeManager = ThemeManager.getInstance();

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
  @State showBookInfoDialog: boolean = false;
  @State bookInfoDialogOpacity: number = 0;

  // 数据管理器
  private ebookDataManager: EBookDataManager = EBookDataManager.getInstance();
  
  // UI上下文（用于设置沉浸式模式）
  private uiContext: UIContext | undefined = undefined;
  
  // Reader Kit 阅读器控制器（用于实时应用设置和跳转章节）
  private readerKitController: ReaderKitViewerController | null = null;

  aboutToAppear(): void {
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (theme: ThemeType) => {
      logger.info(TAG, `主题切换到: ${theme}`);
      // 根据主题更新背景色
      if (theme === 'dark') {
        this.bgColor = '#1E1E1E';
        this.textColor = '#D4D4D4';
      } else {
        this.bgColor = '#FFFFFF';
        this.textColor = '#333333';
      }
    });
    // 根据当前主题设置初始背景色
    if (this.themeState.currentTheme === 'dark') {
      this.bgColor = '#1E1E1E';
      this.textColor = '#D4D4D4';
    }
  }

  aboutToDisappear(): void {
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    // 保存阅读进度
    this.saveReadingProgress();
    // 恢复正常显示模式
    this.restoreNormalMode();
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
      if (ebook.readingSettings) {
        // 如果跟随系统主题，则根据当前系统主题调整颜色
        if (ebook.readingSettings.followSystemTheme !== false) {
          this.applySystemThemeToSettings(ebook);
        }
        
        this.fontSize = ebook.readingSettings.fontSize;
        this.lineHeight = ebook.readingSettings.lineHeight;
        this.bgColor = ebook.readingSettings.backgroundColor;
        this.textColor = ebook.readingSettings.textColor;
        this.pageMargin = ebook.readingSettings.pageMargin;
      } else {
        // 如果没有保存的设置，使用默认设置（ArkTS 不支持展开运算符）
        ebook.readingSettings = {
          fontSize: DEFAULT_EBOOK_READING_SETTINGS.fontSize,
          fontFamily: DEFAULT_EBOOK_READING_SETTINGS.fontFamily,
          fontPath: DEFAULT_EBOOK_READING_SETTINGS.fontPath,
          fontWeight: DEFAULT_EBOOK_READING_SETTINGS.fontWeight,
          lineHeight: DEFAULT_EBOOK_READING_SETTINGS.lineHeight,
          backgroundColor: DEFAULT_EBOOK_READING_SETTINGS.backgroundColor,
          textColor: DEFAULT_EBOOK_READING_SETTINGS.textColor,
          themeBgImage: DEFAULT_EBOOK_READING_SETTINGS.themeBgImage,
          nightMode: DEFAULT_EBOOK_READING_SETTINGS.nightMode,
          followSystemTheme: DEFAULT_EBOOK_READING_SETTINGS.followSystemTheme,
          pageMargin: DEFAULT_EBOOK_READING_SETTINGS.pageMargin,
          pageMode: DEFAULT_EBOOK_READING_SETTINGS.pageMode,
          brightness: DEFAULT_EBOOK_READING_SETTINGS.brightness,
          autoSave: DEFAULT_EBOOK_READING_SETTINGS.autoSave,
          saveInterval: DEFAULT_EBOOK_READING_SETTINGS.saveInterval
        };
        // 应用系统主题
        this.applySystemThemeToSettings(ebook);
        
        this.fontSize = ebook.readingSettings.fontSize;
        this.lineHeight = ebook.readingSettings.lineHeight;
        this.bgColor = ebook.readingSettings.backgroundColor;
        this.textColor = ebook.readingSettings.textColor;
        this.pageMargin = ebook.readingSettings.pageMargin;
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

      this.isLoading = false;
      logger.info(TAG, `电子书加载完成: ${ebook.metadata.title}`);
      
      // 设置沉浸式模式
      this.setupFullscreenMode();
      
    } catch (error) {
      this.errorMessage = `加载失败: ${String(error instanceof Error ? error.message : error)}`;
      this.isLoading = false;
      logger.error(TAG, '加载电子书失败', String(error instanceof Error ? error.message : error));
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
    this.saveReadingProgress();
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
    this.saveReadingProgress();
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

  // 当前 DOM 位置（用于 Reader Kit 精确恢复阅读位置）
  @State currentDomPos: string = '';

  /**
   * 保存阅读进度
   */
  private async saveReadingProgress(): Promise<void> {
    if (!this.ebook || !this.currentChapter) {
      return;
    }

    try {
      const progress: EBookReadingProgress = {
        bookId: this.ebook.id,
        currentChapterId: this.currentChapter.id,
        currentChapterIndex: this.currentChapterIndex,
        currentPosition: 0,
        domPos: this.currentDomPos,
        progress: (this.currentChapterIndex / this.ebook.chapters.length) * 100,
        lastReadTime: Date.now(),
        totalReadingTime: 0
      };

      await this.ebookDataManager.saveReadingProgress(progress);
      logger.debug(TAG, `阅读进度已保存: 章节=${this.currentChapterIndex}, domPos=${this.currentDomPos}`);
    } catch (error) {
      logger.error(TAG, '保存阅读进度失败', String(error instanceof Error ? error.message : error));
    }
  }

  // 上次保存进度的时间戳，用于防抖
  private lastProgressSaveTime: number = 0;
  // 进度保存的最小间隔（毫秒）
  private static readonly PROGRESS_SAVE_INTERVAL: number = 2000;

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
    
    // 通过控制器跳转（如果是 Reader Kit 格式）
    if (this.readerKitController && this.readerKitController.isControllerReady()) {
      await this.readerKitController.goToChapter(chapterIndex, '');
    }
    
    // 保存阅读进度
    this.saveReadingProgress();
  }

  /**
   * 调整字体大小
   */
  private adjustFontSize(delta: number): void {
    this.fontSize = Math.max(12, Math.min(32, this.fontSize + delta));
    logger.debug(TAG, `字体大小调整为: ${this.fontSize}`);
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
    this.showChapterList = true;
    animateTo({
      duration: 250,
      curve: curves.springMotion(0.5, 0.8)
    }, () => {
      this.chapterListOpacity = 1;
    });
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
   * 返回上一页
   */
  private goBack(): void {
    this.saveReadingProgress();
    this.pathStack.pop();
  }

  build() {
    NavDestination() {
      Stack() {
        // 背景层 - 扩展到系统栏区域实现完全沉浸式
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(this.bgColor)
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

        // 阅读设置面板
        if (this.showSettingsPanel && this.ebook) {
          this.buildSettingsPanel()
        }

        // 书籍信息弹窗
        if (this.showBookInfoDialog && this.ebook) {
          this.buildBookInfoDialog()
        }
      }
      .width('100%')
      .height('100%')
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
        .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))

      Text('加载中...')
        .fontSize(16)
        .fontColor(this.textColor)
        .margin({ top: 16 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.bgColor)
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

      Text(this.errorMessage)
        .fontSize(16)
        .fontColor(this.textColor)
        .textAlign(TextAlign.Center)

      Button('返回')
        .fontSize(16)
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
    return supportedFormats.includes(format);
  }

  /**
   * 构建 Reader Kit 阅读器视图
   */
  @Builder
  buildReaderKitView() {
    if (this.ebook) {
      // Reader Kit 阅读器组件 - 占满全屏
      ReaderKitViewerComponent({
        ebook: this.ebook,
        currentChapterIndex: this.currentChapterIndex,
        initialDomPos: this.currentDomPos,
        readingSettings: this.ebook.readingSettings,
        onChapterChange: (index: number) => {
          this.currentChapterIndex = index;
          this.currentChapter = this.ebook ? this.ebook.chapters[index] : null;
          // 章节切换时不清空 domPos，也不立即保存
          // 让 onProgressChange 回调来处理保存，这样可以保留完整的 domPos 信息
          logger.info(TAG, `章节切换: index=${index}, 等待 pageShow 事件更新 domPos`);
        },
        onProgressChange: (progress: number, domPos: string) => {
          logger.debug(TAG, `阅读进度更新: ${progress}%, domPos=${domPos}`);
          this.handleProgressChange(progress, domPos);
        },
        onSettingsChange: (settings: EBookReadingSettings) => {
          if (this.ebook) {
            this.ebook.readingSettings = settings;
            this.ebookDataManager.saveReadingSettings(this.ebook.id, settings);
          }
        },
        onControllerReady: (controller: ReaderKitViewerController) => {
          this.readerKitController = controller;
          logger.info(TAG, 'Reader Kit 控制器已就绪');
        }
      })
      .width('100%')
      .height('100%')
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
   */
  @Builder
  buildTextReaderView() {
    Scroll() {
      Column({ space: 24 }) {
        // 章节标题
        Text(this.currentChapter?.title || '')
          .fontSize(this.fontSize + 4)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.textColor)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 20, bottom: 10 })

        // 章节内容
        Text(this.currentChapter?.content || '')
          .fontSize(this.fontSize)
          .lineHeight(this.fontSize * this.lineHeight)
          .fontColor(this.textColor)
          .width('100%')
          .textAlign(TextAlign.Start)

        // 底部留白（给底部工具栏留出空间）
        Column()
          .height(80)
      }
      .width('100%')
      .padding({
        left: this.pageMargin,
        right: this.pageMargin,
        top: this.statusBarHeight + 20,
        bottom: this.navigationBarHeight + 20
      })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring)
  }

  /**
   * 构建顶部工具栏
   */
  @Builder
  buildTopToolbar() {
    Row() {
      // 返回按钮
      Button() {
        Image($r('app.media.ic_arrow_back'))
          .width(24)
          .height(24)
          .fillColor($r('app.color.text_primary'))
      }
      .width(48)
      .height(48)
      .backgroundColor(Color.Transparent)
      .onClick(() => this.goBack())

      // 标题
      Column({ space: 4 }) {
        Text(this.ebook?.metadata.title || '电子书阅读器')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (this.currentChapter) {
          Text(this.currentChapter.title)
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })

      // 菜单按钮
      Button() {
        Image($r('app.media.ic_more_vert'))
          .width(24)
          .height(24)
          .fillColor($r('app.color.text_primary'))
      }
      .width(48)
      .height(48)
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        this.showMoreMenuWithAnimation();
      })
    }
    .width('100%')
    .height(56)
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
      // 章节进度条
      Row() {
        Text(`${this.currentChapterIndex + 1}`)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width(40)
          .textAlign(TextAlign.Center)

        Slider({
          value: this.currentChapterIndex,
          min: 0,
          max: (this.ebook?.chapters.length || 1) - 1,
          step: 1
        })
          .layoutWeight(1)
          .trackColor($r('app.color.divider_primary'))
          .selectedColor($r('app.color.accent_primary'))
          .onChange((value: number) => {
            const targetIndex = Math.round(value);
            if (targetIndex !== this.currentChapterIndex) {
              // 跳转到目标章节
              this.jumpToChapter(targetIndex);
            }
          })

        Text(`${this.ebook?.chapters.length || 0}`)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width(40)
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .padding({ left: 16, right: 16 })

      // 控制按钮（移除翻页按钮，保留目录和设置）
      Row() {
        // 目录按钮
        Column({ space: 4 }) {
          Image($r('app.media.ic_reading_settings'))
            .width(24)
            .height(24)
            .fillColor($r('app.color.text_primary'))
          Text('目录')
            .fontSize(10)
            .fontColor($r('app.color.text_secondary'))
        }
        .layoutWeight(1)
        .height(56)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.showChapterListWithAnimation();
        })

        // 设置按钮
        Column({ space: 4 }) {
          Image($r('app.media.ic_brightness_high'))
            .width(24)
            .height(24)
            .fillColor($r('app.color.text_primary'))
          Text('设置')
            .fontSize(10)
            .fontColor($r('app.color.text_secondary'))
        }
        .layoutWeight(1)
        .height(56)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.showSettingsPanelWithAnimation();
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
          Blank().layoutWeight(1)
          Image($r('app.media.ic_arrow_right'))
            .width(16)
            .height(16)
            .fillColor($r('app.color.text_secondary'))
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
          Blank().layoutWeight(1)
          Text(`${this.fontSize}`)
            .fontColor($r('app.color.text_secondary'))
            .fontSize(14)
        }
        .height(44)
        .padding({ left: 16, right: 16 })

        // 字体调整按钮
        Row({ space: 16 }) {
          Button('A-')
            .fontSize(14)
            .width(60)
            .height(36)
            .backgroundColor($r('app.color.background_secondary'))
            .fontColor($r('app.color.text_primary'))
            .onClick(() => {
              this.adjustFontSize(-2);
            })

          Button('A+')
            .fontSize(14)
            .width(60)
            .height(36)
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
        List() {
          ForEach(this.ebook?.chapters || [], (chapter: EBookChapter, index: number) => {
            ListItem() {
              Row() {
                Text(chapter.title)
                  .fontSize(15)
                  .fontColor(index === this.currentChapterIndex ? $r('app.color.accent_primary') : $r('app.color.text_primary'))
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)

                if (index === this.currentChapterIndex) {
                  Text('当前')
                    .fontSize(12)
                    .fontColor($r('app.color.accent_primary'))
                    .margin({ left: 8 })
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
      .width('85%')
      .height('80%')
      .constraintSize({ maxWidth: 400 })
      .backgroundColor(this.themeManager.getGlassBackgroundResource())
      .backgroundBlurStyle(this.themeManager.getGlassBlurStyle())
      .borderRadius(16)
      .opacity(this.chapterListOpacity)
    }
    .width('100%')
    .height('100%')
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
      .width('90%')
      .height('70%')
      .constraintSize({ maxWidth: 420, maxHeight: 600 })
      .backgroundColor(this.themeManager.getGlassBackgroundResource())
      .backgroundBlurStyle(this.themeManager.getGlassBlurStyle())
      .borderRadius(16)
      .opacity(this.settingsPanelOpacity)
      .scale({ x: this.settingsPanelScale, y: this.settingsPanelScale })
      .translate({ y: this.settingsPanelTranslateY })
      .clip(true)
    }
    .width('100%')
    .height('100%')
    .zIndex(1200)
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
              if (this.ebook && this.ebook.metadata.coverImagePath && this.ebook.metadata.coverImagePath.length > 0) {
                Image(this.ebook.metadata.coverImagePath.startsWith('/') 
                  ? `file://${this.ebook.metadata.coverImagePath}` 
                  : this.ebook.metadata.coverImagePath)
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

                Text(this.ebook?.metadata.author || '未知作者')
                  .fontSize(14)
                  .fontColor($r('app.color.text_secondary'))

                Text(this.ebook?.format || '')
                  .fontSize(12)
                  .fontColor($r('app.color.text_white'))
                  .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                  .backgroundColor($r('app.color.accent_primary'))
                  .borderRadius(4)
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
            this.buildBookInfoItem('文件大小', this.formatFileSize(this.ebook?.fileSize || 0))

            // 简介
            if (this.ebook && this.ebook.metadata.description && this.ebook.metadata.description.length > 0) {
              Column({ space: 8 }) {
                Text('简介')
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                  .width('100%')

                Text(this.ebook.metadata.description)
                  .fontSize(13)
                  .fontColor($r('app.color.text_secondary'))
                  .lineHeight(20)
                  .width('100%')
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
      .width('90%')
      .height('70%')
      .constraintSize({ maxWidth: 400, maxHeight: 550 })
      .backgroundColor(this.themeManager.getGlassBackgroundResource())
      .backgroundBlurStyle(this.themeManager.getGlassBlurStyle())
      .borderRadius(16)
      .opacity(this.bookInfoDialogOpacity)
      .clip(true)
    }
    .width('100%')
    .height('100%')
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

      Text(value)
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
        .textAlign(TextAlign.End)
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

