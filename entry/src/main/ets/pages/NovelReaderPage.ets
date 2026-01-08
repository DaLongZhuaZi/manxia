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
import { ReplaceScope } from '../Framework/Novel/NovelReplaceRuleManager';
import { LegadoChapter, LegadoBook, LegadoBookSourceType } from '../Framework/Novel/LegadoSourceTypes';
import { NovelReaderPageParams } from './NovelBookshelfPage';
import { TextReaderComponent, PaginationMode } from '../components/TextReaderComponent';
import { TextReaderSettingsPanel } from '../components/TextReaderSettingsPanel';
import { 
  TextReaderSettings, 
  DEFAULT_TEXT_READER_SETTINGS,
  TextChapter,
  BackgroundType,
  PageMargins
} from '../Models/TextReaderModels';
import { NovelReadProgress } from '../Models/NovelModels';
import { SettingsManager, SettingKeys } from '../Framework/Managers/SettingsManager';
import { getNovelSettingsManager, BrowseHistoryInput } from '../Framework/Novel/NovelSettingsManager';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';
import { PageLifecycleManager } from '../Framework/Lifecycle';
import { WindowManager, DisplayMode } from '../Utils/WindowManager';
import { curves } from '@kit.ArkUI';
import { setReaderReady, startBookCloseTransitionWithComponentId, CoverPosition, cancelTransition } from '../components/BookTransitionOverlay';

const TAG = 'NovelReaderPage';

@Component
export struct NovelReaderPage {
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

  // UI控制状态 - 默认隐藏工具栏实现完全沉浸式体验
  @State showTopToolbar: boolean = false;
  @State showBottomToolbar: boolean = false;
  @State toolbarOpacity: number = 0.0;
  @State showSettingsPanel: boolean = false;
  @State showChapterList: boolean = false;

  // 动画状态
  @State settingsPanelOpacity: number = 0;
  @State settingsPanelScale: number = 0.95;
  @State chapterListOpacity: number = 0;

  // 章节列表滚动控制器
  private chapterListScroller: Scroller = new Scroller();

  private sourceId: string = '';
  private bookUrl: string = '';
  private bookName: string = '';
  private chapterUrl: string = '';
  private bookId: string = '';
  private chapterId: string = '';
  private tocUrl: string = ''; // 目录URL
  private chapterList: LegadoChapter[] = []; // 完整章节列表
  private sourceManager = getNovelSourceManager();
  private dataManager = getNovelDataManager();
  private cacheManager = getNovelChapterCacheManager();
  private settingsManager: SettingsManager = SettingsManager.getInstance();
  private readStartTime: number = 0;
  private lastSaveTime: number = 0;
  private uiContext: UIContext | null = null;
  private saveProgressInterval: number = 30000; // 30秒自动保存

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
  }

  aboutToDisappear(): void {
    logger.lifecycle(TAG, 'aboutToDisappear - 开始清理资源');
    this.lifecycle.destroy();
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    FontAwareHelper.cleanupFontAware(this.componentId);
    // 页面退出时保存阅读进度
    this.saveReadProgress();
    // 恢复正常显示模式
    this.restoreNormalMode();
    // [修复] 安全清理过渡动画状态，防止页面销毁后覆盖层仍然阻止交互
    cancelTransition();
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
    });
    setTimeout(() => {
      this.showSettingsPanel = false;
    }, 200);
  }

  async loadSettings(): Promise<void> {
    try {
      // 优先加载书籍专属设置，如果不存在则使用全局设置
      let bookSettings: TextReaderSettings | undefined = undefined;

      // 为在线小说使用更小的页边距，提高屏幕利用率
      const onlineNovelMargins: PageMargins = {
        top: 32,
        bottom: 0,
        left: 8,
        right: 8
      };
      
      if (this.bookId) {
        const settingsKey = `${SettingKeys.NOVEL_READER_SETTINGS}_${this.bookId}`;
        try {
          bookSettings = this.settingsManager.getJSON<TextReaderSettings>(settingsKey, DEFAULT_TEXT_READER_SETTINGS);
          // 检查是否真的有书籍专属设置（通过检查key是否存在）
          const hasBookSettings = this.settingsManager.getString(settingsKey, '');
          if (!hasBookSettings) {
            bookSettings = undefined;
          }
        } catch (e) {
          bookSettings = undefined;
        }
      }
      
      if (bookSettings) {
        logger.info(TAG, `加载书籍专属设置: ${this.bookId}`);
        // 为在线小说调整页边距
        bookSettings.pageMargins = onlineNovelMargins;
        this.settings = bookSettings;
      } else {
        // 使用全局设置
        const globalSettings = this.settingsManager.getJSON<TextReaderSettings>(SettingKeys.NOVEL_READER_SETTINGS, DEFAULT_TEXT_READER_SETTINGS);
        // 为在线小说调整页边距
        globalSettings.pageMargins = onlineNovelMargins;
        this.settings = globalSettings;
        logger.info(TAG, `使用全局小说阅读器设置，已调整为在线小说页边距`);
      }
    } catch (e) {
      logger.warn(TAG, `加载设置失败: ${String(e)}`);
    }
  }

  async loadContent(): Promise<void> {
    this.isLoading = true;
    try {
      // 设置沉浸式模式
      this.setupFullscreenMode();
      
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
    // 直接更新settings状态，触发UI响应式更新
    this.settings = newSettings;
    // 异步保存设置（不阻塞UI）
    this.saveSettings();
    logger.debug(TAG, `设置已更新并保存`);
  }

  onPageChange(pageIndex: number, totalPages: number): void {
    this.currentPageIndex = pageIndex;
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
   * 点击中间区域回调 - 显示/隐藏工具栏
   * TextReaderComponent 内部已经处理了点击区域判断，这里只需要切换工具栏状态
   */
  onTapCenter(): void {
    this.toggleToolbar();
  }

  getBackgroundColor(): string {
    if (this.settings.background.type === BackgroundType.COLOR) {
      return this.settings.background.color || '#F5F0E1';
    }
    return '#F5F0E1';
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

        // 设置面板
        if (this.showSettingsPanel) {
          this.buildSettingsPanel()
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
        this.loadSettings();
        this.loadContent();
        
        // [修复] 记录浏览历史，确保阅读过的小说出现在历史浏览中
        this.recordBrowseHistory(param);
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
   */
  @Builder
  buildReaderView() {
    TextReaderComponent({
      content: this.content,
      chapters: this.chapters,
      settings: this.settings,
      currentChapterIndex: this.currentChapterIndex,
      currentPageIndex: this.currentPageIndex,
      paginationMode: PaginationMode.ONLINE,  // 在线小说使用ONLINE分页模式
      onPageChange: (pageIndex: number, totalPages: number) => this.onPageChange(pageIndex, totalPages),
      onChapterChange: (chapterIndex: number) => this.onChapterChange(chapterIndex),
      onTapCenter: () => this.onTapCenter(),
      onReady: () => {
        // 文本阅读器分页完成，通知过渡动画阅读器就绪
        logger.info(TAG, '📖 文本阅读器分页完成，通知过渡动画');
        setReaderReady();
      }
    })
      .width('100%')
      .height('100%')
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
            .fontSize(24)
            .fontColor([$r('app.color.text_primary')])
        }
        .width(64)
        .height(48)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.hideToolbarWithAnimation();
          this.showChapterListWithAnimation();
        })

        Blank()

        // 设置按钮
        Button() {
          SymbolGlyph($r('sys.symbol.sun_max'))
            .fontSize(24)
            .fontColor([$r('app.color.text_primary')])
        }
        .width(64)
        .height(48)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.hideToolbarWithAnimation();
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

  /**
   * 构建设置面板
   */
  @Builder
  buildSettingsPanel() {
    Stack() {
      // 遮罩
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.5)')
        .opacity(this.settingsPanelOpacity)
        .onClick(() => {
          this.hideSettingsPanelWithAnimation();
        })
      
      // 设置面板
      Column() {
        TextReaderSettingsPanel({
          settings: this.settings,
          onClose: () => {
            this.hideSettingsPanelWithAnimation();
          },
          onSettingsChange: (newSettings: TextReaderSettings) => {
            this.onSettingsChange(newSettings);
          }
        })
      }
      .width('95%')
      .height('80%')
      .constraintSize({ maxWidth: 450, minWidth: 320 })
      .backgroundColor($r('app.color.panel_background'))
      .borderRadius(16)
      .opacity(this.settingsPanelOpacity)
      .scale({ x: this.settingsPanelScale, y: this.settingsPanelScale })
      .clip(true)
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Center)
  }

  toggleNightMode(): void {
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
}
