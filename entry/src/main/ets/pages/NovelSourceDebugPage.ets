/**
 * 小说书源调试页面
 * 提供完整的书源调试功能，类似Legado原版
 * 
 * 文件路径: entry/src/main/ets/pages/NovelSourceDebugPage.ets
 */

import { HdsNavDestination } from '@kit.UIDesignKit';
import { promptAction } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { GlobalBackgroundLayerMode } from '../Framework/Components/GlobalBackgroundLayer';
import { SharedPageBackgroundLayer } from '../Framework/Components/SharedPageBackgroundLayer';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';
import { PageLifecycleManager, CancellationError } from 'manxia_core/src/main/ets/Framework/Lifecycle/index';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { LegadoBookSource, LegadoSearchBook, LegadoBook, LegadoChapter, LegadoBookSourceType } from '../Framework/Novel/LegadoSourceTypes';
import { getNovelSourceManager, NovelSourceManager } from '../Framework/Novel/NovelSourceManager';
import { NovelSearchResult } from '../Models/NovelModels';
import { LegadoMangaImageExtractor } from '../Framework/Novel/LegadoMangaImageExtractor';
import { LegadoWebViewComponent } from '../Framework/Novel/LegadoWebViewComponent';
import { getLegadoJsEngine } from '../Framework/Novel/LegadoJsEngine';
import { SettingsImmersiveTitleBar } from './settings/SettingsImmersiveTitleBar';
import { SettingsPanelSurfaceHelper } from './settings/SettingsPanelSurfaceHelper';
import { SettingsPageTitleBarManager } from './settings/SettingsPageTitleBarManager';

const TAG = 'NovelSourceDebugPage';

/**
 * 调试步骤枚举
 */
enum DebugStep {
  IDLE = 'idle',
  SEARCH = 'search',
  BOOK_INFO = 'bookInfo',
  TOC = 'toc',
  CONTENT = 'content'
}

/**
 * 调试日志条目
 */
interface DebugLogEntry {
  time: string;
  level: 'info' | 'debug' | 'warn' | 'error' | 'success';
  message: string;
  detail?: string;
}

/**
 * 页面参数
 */
export interface NovelSourceDebugPageParams {
  sourceId: string;
}

@Component
export struct NovelSourceDebugPage {
  @Consume('NavPathStack') pathStack: NavPathStack;
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  private lifecycle = new PageLifecycleManager('NovelSourceDebugPage', { enableDebug: true });
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private componentId: string = `NovelSourceDebugPage_${Date.now()}`;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;
  
  // 书源信息
  @State source: LegadoBookSource | null = null;
  @State sourceId: string = '';
  
  // 调试状态
  @State currentStep: DebugStep = DebugStep.IDLE;
  @State isRunning: boolean = false;
  @State logs: DebugLogEntry[] = [];
  
  // 搜索相关
  @State searchKeyword: string = '斗罗';
  @State searchResults: LegadoSearchBook[] = [];
  @State selectedBookIndex: number = -1;
  
  // 书籍详情
  @State bookInfo: LegadoBook | null = null;
  
  // 目录
  @State chapters: LegadoChapter[] = [];
  @State selectedChapterIndex: number = -1;
  
  // 正文
  @State chapterContent: string = '';
  
  // 展开状态
  @State showSearchResults: boolean = true;
  @State showBookInfo: boolean = true;
  @State showChapters: boolean = true;
  @State showContent: boolean = true;
  
  // WebView控制器（用于网络请求）
  private webViewController: webview.WebviewController = new webview.WebviewController();
  
  private sourceManager: NovelSourceManager = getNovelSourceManager();
  private logScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (theme: ThemeType) => {
      logger.info(TAG, `主题切换: ${theme}`);
    });
    FontAwareHelper.initializeFontAware(this.componentId, this.fontState, (newState: FontAwareState) => {
      this.fontState = newState;
    });
    
    // 从AppStorage获取参数
    const params = AppStorage.get<NovelSourceDebugPageParams>('NovelSourceDebugPageParams');
    if (params && params.sourceId) {
      this.sourceId = params.sourceId;
      this.loadSource();
    }
  }

  aboutToDisappear(): void {
    logger.lifecycle(TAG, 'aboutToDisappear - 开始清理资源');
    this.lifecycle.destroy();
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    FontAwareHelper.cleanupFontAware(this.componentId);
  }

  /**
   * 加载书源
   */
  loadSource(): void {
    const source = this.sourceManager.getSource(this.sourceId);
    if (source) {
      this.source = source;
      this.addLog('info', `已加载书源: ${source.bookSourceName}`);
      this.addLog('debug', `当前统一策略: ${this.sourceManager.getV2ExecutionPolicy()}`);
      this.addLog('debug', `书源URL: ${source.bookSourceUrl}`);
      if (source.searchUrl) {
        this.addLog('debug', `搜索URL: ${source.searchUrl.substring(0, 100)}...`);
      }
    } else {
      this.addLog('error', `未找到书源: ${this.sourceId}`);
    }
  }

  /**
   * 添加日志
   */
  addLog(level: 'info' | 'debug' | 'warn' | 'error' | 'success', message: string, detail?: string): void {
    const now = new Date();
    const time = `${now.getHours().toString().padStart(2, '0')}:${now.getMinutes().toString().padStart(2, '0')}:${now.getSeconds().toString().padStart(2, '0')}.${now.getMilliseconds().toString().padStart(3, '0')}`;
    
    const entry: DebugLogEntry = { time, level, message, detail };
    this.logs = [...this.logs, entry];
    
    // 自动滚动到底部
    setTimeout(() => {
      this.logScroller.scrollEdge(Edge.Bottom);
    }, 100);
  }

  /**
   * 清空日志
   */
  clearLogs(): void {
    this.logs = [];
  }

  /**
   * 执行搜索测试
   */
  async testSearch(): Promise<void> {
    if (!this.source) {
      this.addLog('error', '书源未加载');
      return;
    }
    
    if (!this.searchKeyword.trim()) {
      this.addLog('warn', '请输入搜索关键词');
      return;
    }
    
    this.isRunning = true;
    this.currentStep = DebugStep.SEARCH;
    this.searchResults = [];
    this.selectedBookIndex = -1;
    
    this.addLog('info', `开始搜索: "${this.searchKeyword}"`);
    
    try {
      const startTime = Date.now();
      const results = await this.sourceManager.search(this.sourceId, this.searchKeyword, 1);
      const elapsed = Date.now() - startTime;
      
      this.searchResults = this.toLegadoSearchBooks(results);
      
      if (results.length > 0) {
        this.addLog('success', `搜索完成，找到 ${results.length} 本书 (${elapsed}ms)`);
        for (let i = 0; i < Math.min(results.length, 5); i++) {
          const book = results[i];
          this.addLog('debug', `[${i + 1}] ${book.name} - ${book.author || '未知作者'}`);
        }
        if (results.length > 5) {
          this.addLog('debug', `... 还有 ${results.length - 5} 本书`);
        }
      } else {
        this.addLog('warn', `搜索完成，未找到结果 (${elapsed}ms)`);
        this.addLog('debug', '可能原因: 1.搜索规则不匹配 2.网站返回空数据 3.关键词无结果');
      }
    } catch (error) {
      this.addLog('error', `搜索失败: ${String(error)}`);
    }
    
    this.isRunning = false;
  }

  /**
   * 测试书籍详情
   */
  async testBookInfo(book: LegadoSearchBook): Promise<void> {
    if (!this.source) {
      this.addLog('error', '书源未加载');
      return;
    }
    
    this.isRunning = true;
    this.currentStep = DebugStep.BOOK_INFO;
    this.bookInfo = null;
    this.chapters = [];
    this.selectedChapterIndex = -1;
    
    this.addLog('info', `获取书籍详情: ${book.name}`);
    this.addLog('debug', `书籍URL: ${book.bookUrl}`);
    
    try {
      const startTime = Date.now();
      const info = await this.sourceManager.getBookInfo(this.sourceId, book.bookUrl);
      const elapsed = Date.now() - startTime;
      
      if (info) {
        this.bookInfo = info;
        this.addLog('success', `获取详情成功 (${elapsed}ms)`);
        this.addLog('debug', `书名: ${info.name}`);
        this.addLog('debug', `作者: ${info.author || '未知'}`);
        this.addLog('debug', `简介: ${(info.intro || '无').substring(0, 100)}...`);
        this.addLog('debug', `目录URL: ${info.tocUrl || info.bookUrl}`);
      } else {
        this.addLog('warn', `获取详情失败，返回空数据 (${elapsed}ms)`);
      }
    } catch (error) {
      this.addLog('error', `获取详情失败: ${String(error)}`);
    }
    
    this.isRunning = false;
  }

  /**
   * 测试目录
   */
  async testToc(): Promise<void> {
    if (!this.source || !this.bookInfo) {
      this.addLog('error', '请先获取书籍详情');
      return;
    }
    
    this.isRunning = true;
    this.currentStep = DebugStep.TOC;
    this.chapters = [];
    this.selectedChapterIndex = -1;
    
    this.addLog('info', `获取目录: ${this.bookInfo.name}`);
    
    try {
      const startTime = Date.now();
      const chapters = await this.sourceManager.getChapterList(this.sourceId, this.bookInfo);
      const elapsed = Date.now() - startTime;
      
      this.chapters = chapters;
      
      if (chapters.length > 0) {
        this.addLog('success', `获取目录成功，共 ${chapters.length} 章 (${elapsed}ms)`);
        this.addLog('debug', `第一章: ${chapters[0].title}`);
        if (chapters.length > 1) {
          this.addLog('debug', `最后一章: ${chapters[chapters.length - 1].title}`);
        }
      } else {
        this.addLog('warn', `获取目录失败，返回空数据 (${elapsed}ms)`);
      }
    } catch (error) {
      this.addLog('error', `获取目录失败: ${String(error)}`);
    }
    
    this.isRunning = false;
  }

  /**
   * 测试正文
   */
  async testContent(chapter: LegadoChapter): Promise<void> {
    if (!this.source) {
      this.addLog('error', '书源未加载');
      return;
    }
    
    this.isRunning = true;
    this.currentStep = DebugStep.CONTENT;
    this.chapterContent = '';
    
    this.addLog('info', `获取正文: ${chapter.title}`);
    this.addLog('debug', `章节URL: ${chapter.url}`);
    
    try {
      const startTime = Date.now();
      const content = await this.sourceManager.getContent(this.sourceId, chapter);
      const elapsed = Date.now() - startTime;
      
      if (content && content.length > 0) {
        this.chapterContent = content;
        this.addLog('success', `获取正文成功，${content.length} 字符 (${elapsed}ms)`);
        if (this.source && this.source.bookSourceType === LegadoBookSourceType.IMAGE) {
          const imageUrls = LegadoMangaImageExtractor.extractImageUrls(content, chapter.url);
          const pageSegments = content.split('\n\n').filter((segment: string): boolean => segment.trim().length > 0).length;
          this.addLog('success', `漫画图片解析成功，${imageUrls.length} 张图片`);
          this.addLog('debug', `分页正文统计: ${pageSegments} 段，章节URL=${chapter.url}`);
          const headerSummary = this.buildImageHeaderDebugSummary(this.source, chapter.url);
          this.addLog('debug', `图片请求头摘要: ${headerSummary}`);
          const sampleCount = Math.min(5, imageUrls.length);
          for (let i = 0; i < sampleCount; i++) {
            this.addLog('debug', `图片${i + 1}: ${imageUrls[i]}`);
          }
          if (imageUrls.length === 0) {
            this.addLog('warn', 'IMAGE书源正文未解析到图片，请检查ruleContent.content或图片属性');
          }
        } else {
          this.addLog('debug', `正文预览: ${content.substring(0, 200)}...`);
        }
      } else {
        this.addLog('warn', `获取正文失败，返回空数据 (${elapsed}ms)`);
      }
    } catch (error) {
      this.addLog('error', `获取正文失败: ${String(error)}`);
    }
    
    this.isRunning = false;
  }

  private buildImageHeaderDebugSummary(source: LegadoBookSource, chapterUrl: string): string {
    const parts: string[] = [];
    if (source.header && source.header.trim().length > 0) {
      parts.push(`source.header=${source.header.length}字符`);
    } else {
      parts.push('source.header=空');
    }
    if (source.loginUrl && source.loginUrl.trim().length > 0) {
      parts.push('login=已配置');
    } else {
      parts.push('login=未配置');
    }
    if (chapterUrl && chapterUrl.trim().length > 0) {
      parts.push('Referer=章节URL');
    }
    parts.push('User-Agent=默认/书源');
    return parts.join(', ');
  }

  /** Maps the central manager result back to the debug page's display model. */
  private toLegadoSearchBooks(results: NovelSearchResult[]): LegadoSearchBook[] {
    const books: LegadoSearchBook[] = [];
    const source = this.source;
    if (source === null) {
      return books;
    }
    for (let i = 0; i < results.length; i++) {
      const result = results[i];
      books.push({
        origin: source.bookSourceUrl,
        originName: source.bookSourceName,
        bookUrl: result.bookUrl,
        name: result.name,
        author: result.author,
        kind: result.kind || '',
        intro: result.intro || '',
        coverUrl: result.coverUrl || '',
        latestChapterTitle: result.latestChapterTitle || '',
        wordCount: result.wordCount || '',
        type: source.bookSourceType
      });
    }
    return books;
  }

  /**
   * 一键测试所有功能
   */
  async testAll(): Promise<void> {
    if (!this.source) {
      this.addLog('error', '书源未加载');
      return;
    }
    
    this.clearLogs();
    this.addLog('info', '=== 开始一键测试 ===');
    
    // 1. 搜索
    await this.testSearch();
    if (this.searchResults.length === 0) {
      this.addLog('error', '搜索无结果，测试终止');
      return;
    }
    
    // 2. 书籍详情
    await this.testBookInfo(this.searchResults[0]);
    if (!this.bookInfo) {
      this.addLog('error', '获取详情失败，测试终止');
      return;
    }
    
    // 3. 目录
    await this.testToc();
    if (this.chapters.length === 0) {
      this.addLog('error', '获取目录失败，测试终止');
      return;
    }
    
    // 4. 正文
    await this.testContent(this.chapters[0]);
    
    this.addLog('info', '=== 一键测试完成 ===');
  }

  build() {
    HdsNavDestination() {
      Stack() {
        // 背景层
        SharedPageBackgroundLayer({
          defaultBackgroundColor: ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme),
          mode: GlobalBackgroundLayerMode.IMMERSIVE
        })
          .width('100%')
          .height('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .animation(ThemeAwareHelper.getThemeTransitionAnimation())
        
        Column() {
          // 标题栏占位
          Blank().height(SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight))
          
          // 搜索输入区
          this.buildSearchInput()
          
          // 步骤指示器
          this.buildStepIndicator()
          
          // 主内容区
          Scroll() {
            Column() {
              // 搜索结果
              if (this.searchResults.length > 0) {
                this.buildSearchResults()
              }
              
              // 书籍详情
              if (this.bookInfo) {
                this.buildBookInfo()
              }
              
              // 目录
              if (this.chapters.length > 0) {
                this.buildChapters()
              }
              
              // 正文
              if (this.chapterContent) {
                this.buildContent()
              }
              
              // 日志区域
              this.buildLogs()
            }
            .width('100%')
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
            .padding({ left: 16, right: 16, top: 8, bottom: 32 + this.navigationBarHeight })
          }
          .width('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .layoutWeight(1)
          .scrollBar(BarState.Auto)
          .edgeEffect(EdgeEffect.Spring)
        }
        .width('100%')
        .height('100%')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        
        // 加载遮罩
        if (this.isRunning) {
          this.buildLoadingOverlay()
        }

        SettingsImmersiveTitleBar({
          themeState: this.themeState,
          title: this.source ? `调试: ${this.source.bookSourceName}` : '书源调试',
          appFontFamily: this.appFontFamily
        })
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .backgroundColor(Color.Transparent)
    .onReady(() => {
      logger.info(TAG, 'HdsNavDestination.onReady 已触发');
    })
  }

  @Builder
  buildSearchInput() {
    Column() {
      Row() {
        TextInput({ placeholder: '输入搜索关键词', text: this.searchKeyword })
          .layoutWeight(1)
          .height(40)
          .borderRadius(20)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
          .border({
            width: 1,
            color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme)
          })
          .onChange((value: string) => {
            this.searchKeyword = value;
          })
          .onSubmit(() => this.testSearch())
        
        Button('搜索')
          .fontSize(14)
          .height(40)
          .margin({ left: 8 })
          .fontFamily(this.appFontFamily)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .enabled(!this.isRunning)
          .onClick(() => this.testSearch())
        
        Button('一键测试')
          .fontSize(14)
          .height(40)
          .margin({ left: 8 })
          .fontFamily(this.appFontFamily)
          .backgroundColor('#FF9800')
          .enabled(!this.isRunning)
          .onClick(() => this.testAll())
      }
      .width('100%')
      .padding(16)
    }
    .width('100%')
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(
      SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
      SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
    )
    .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
    .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
    .clip(true)
    .border({
      width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
      color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
    })
    .shadow({
      radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4,
      color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
      offsetX: 0,
      offsetY: 8
    })
    .margin({ left: 16, right: 16, top: 8 })
  }

  @Builder
  buildStepIndicator() {
    Row({ space: 8 }) {
      // 搜索步骤
      this.buildStepItem('搜索', DebugStep.SEARCH, this.searchResults.length > 0)
      
      // 详情步骤
      this.buildStepItem('详情', DebugStep.BOOK_INFO, this.bookInfo !== null)
      
      // 目录步骤
      this.buildStepItem('目录', DebugStep.TOC, this.chapters.length > 0)
      
      // 正文步骤
      this.buildStepItem('正文', DebugStep.CONTENT, this.chapterContent !== '')
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(
      SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
      SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
    )
    .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
    .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
    .clip(true)
    .border({
      width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
      color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
    })
    .shadow({
      radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4,
      color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
      offsetX: 0,
      offsetY: 8
    })
    .margin({ left: 16, right: 16, top: 12 })
  }

  @Builder
  buildStepItem(label: string, step: DebugStep, completed: boolean) {
    Column({ space: 4 }) {
      Row() {
        if (completed) {
          SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
            .fontSize(20)
            .fontColor(['#52C41A'])
        } else if (this.currentStep === step) {
          LoadingProgress()
            .width(20)
            .height(20)
            .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        } else {
          SymbolGlyph($r('sys.symbol.circle'))
            .fontSize(20)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
        }
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      
      Text(label)
        .fontSize(11)
        .fontFamily(this.appFontFamily)
        .fontColor(completed ? '#52C41A' : 
                   this.currentStep === step ? 
                   ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) :
                   ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
    }
    .layoutWeight(1)
  }

  @Builder
  buildSearchResults() {
    Column() {
      Row() {
        Text(`搜索结果 (${this.searchResults.length})`)
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        
        Blank()
        
        Text(this.showSearchResults ? '收起' : '展开')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .onClick(() => {
            this.showSearchResults = !this.showSearchResults;
          })
      }
      .width('100%')
      .padding({ top: 12, bottom: 8 })
      
      if (this.showSearchResults) {
        ForEach(this.searchResults.slice(0, 10), (book: LegadoSearchBook, index: number) => {
          Row() {
            Column() {
              Text(book.name)
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              
              Text(`${book.author || '未知作者'} · ${book.kind || '未分类'}`)
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
                .margin({ top: 4 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            
            Button('详情')
              .fontSize(12)
              .height(28)
              .fontFamily(this.appFontFamily)
              .enabled(!this.isRunning)
              .onClick(() => {
                this.selectedBookIndex = index;
                this.testBookInfo(book);
              })
          }
          .width('100%')
          .padding(12)
          .backgroundColor(this.selectedBookIndex === index ? 
            ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme) :
            ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
          .borderRadius(8)
          .margin({ bottom: 8 })
        })
      }
    }
    .width('100%')
    .margin({ top: 16 })
  }

  @Builder
  buildBookInfo() {
    Column() {
      Row() {
        Text('书籍详情')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        
        Blank()
        
        Button('获取目录')
          .fontSize(12)
          .height(28)
          .fontFamily(this.appFontFamily)
          .enabled(!this.isRunning)
          .onClick(() => this.testToc())
        
        Text(this.showBookInfo ? '收起' : '展开')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .margin({ left: 12 })
          .onClick(() => {
            this.showBookInfo = !this.showBookInfo;
          })
      }
      .width('100%')
      .padding({ top: 12, bottom: 8 })
      
      if (this.showBookInfo && this.bookInfo) {
        Column() {
          this.buildInfoRow('书名', this.bookInfo.name)
          this.buildInfoRow('作者', this.bookInfo.author || '未知')
          this.buildInfoRow('分类', this.bookInfo.kind || '未分类')
          this.buildInfoRow('最新章节', this.bookInfo.latestChapterTitle || '未知')
          this.buildInfoRow('简介', (this.bookInfo.intro || '无').substring(0, 200))
        }
        .width('100%')
        .padding(12)
        .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
        .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
        .backgroundBlurStyle(
          SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
          SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
        )
        .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
        .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
        .clip(true)
        .border({
          width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
          color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
        })
      }
    }
    .width('100%')
    .margin({ top: 16 })
  }

  @Builder
  buildInfoRow(label: string, value: string) {
    Row() {
      Text(label + ':')
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
        .width(60)
      
      Text(value)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .layoutWeight(1)
    }
    .width('100%')
    .margin({ bottom: 8 })
  }

  @Builder
  buildChapters() {
    Column() {
      Row() {
        Text(`目录 (${this.chapters.length}章)`)
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        
        Blank()
        
        Text(this.showChapters ? '收起' : '展开')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .onClick(() => {
            this.showChapters = !this.showChapters;
          })
      }
      .width('100%')
      .padding({ top: 12, bottom: 8 })
      
      if (this.showChapters) {
        ForEach(this.chapters.slice(0, 20), (chapter: LegadoChapter, index: number) => {
          Row() {
            Text(`${index + 1}. ${chapter.title}`)
              .fontSize(13)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            
            Button('正文')
              .fontSize(12)
              .height(26)
              .fontFamily(this.appFontFamily)
              .enabled(!this.isRunning)
              .onClick(() => {
                this.selectedChapterIndex = index;
                this.testContent(chapter);
              })
          }
          .width('100%')
          .padding({ top: 8, bottom: 8, left: 12, right: 12 })
          .backgroundColor(this.selectedChapterIndex === index ? 
            ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme) :
            ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
          .borderRadius(6)
          .margin({ bottom: 4 })
        })
        
        if (this.chapters.length > 20) {
          Text(`... 还有 ${this.chapters.length - 20} 章`)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
            .margin({ top: 8 })
        }
      }
    }
    .width('100%')
    .margin({ top: 16 })
  }

  @Builder
  buildContent() {
    Column() {
      Row() {
        Text('正文预览')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        
        Blank()
        
        Text(`${this.chapterContent.length} 字`)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
        
        Text(this.showContent ? '收起' : '展开')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .margin({ left: 12 })
          .onClick(() => {
            this.showContent = !this.showContent;
          })
      }
      .width('100%')
      .padding({ top: 12, bottom: 8 })
      
      if (this.showContent) {
        Text(this.chapterContent.substring(0, 2000) + (this.chapterContent.length > 2000 ? '...' : ''))
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .lineHeight(22)
          .width('100%')
          .padding(12)
          .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
          .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
          .backgroundBlurStyle(
            SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
            SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
          )
          .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
          .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
          .clip(true)
          .border({
            width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
            color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
          })
      }
    }
    .width('100%')
    .margin({ top: 16 })
  }

  @Builder
  buildLogs() {
    Column() {
      Row() {
        Text(`调试日志 (${this.logs.length})`)
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        
        Blank()
        
        Text('清空')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('color_error', this.themeState.currentTheme))
          .onClick(() => this.clearLogs())
      }
      .width('100%')
      .padding({ top: 12, bottom: 8 })
      
      Scroll(this.logScroller) {
        Column() {
          ForEach(this.logs, (log: DebugLogEntry, index: number) => {
            Row() {
              Text(log.time)
                .fontSize(10)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                .width(80)
              
              Text(this.getLogLevelIcon(log.level))
                .fontSize(12)
                .width(20)
                .fontFamily(this.appFontFamily)
              
              Text(log.message)
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(this.getLogColor(log.level))
                .layoutWeight(1)
            }
            .width('100%')
            .padding({ top: 4, bottom: 4 })
          })
        }
        .width('100%')
      }
      .width('100%')
      .height(200)
      .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
      .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
      .backgroundBlurStyle(
        SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
        SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
      )
      .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
      .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
      .clip(true)
      .border({
        width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
        color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
      })
      .padding(8)
    }
    .width('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .margin({ top: 16 })
  }

  @Builder
  buildLoadingOverlay() {
    Column() {
      LoadingProgress()
        .width(48)
        .height(48)
        .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
      
      Text('正在执行...')
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .margin({ top: 12 })
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .backgroundColor('#80000000')
    .justifyContent(FlexAlign.Center)
  }

  getLogLevelIcon(level: string): string {
    switch (level) {
      case 'info': return 'ℹ️';
      case 'debug': return '🔍';
      case 'warn': return '⚠️';
      case 'error': return '❌';
      case 'success': return '✅';
      default: return '•';
    }
  }

  getLogColor(level: string): ResourceColor {
    switch (level) {
      case 'info': return ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme);
      case 'debug': return ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme);
      case 'warn': return '#FF9800';
      case 'error': return '#F44336';
      case 'success': return '#4CAF50';
      default: return ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme);
    }
  }
}
