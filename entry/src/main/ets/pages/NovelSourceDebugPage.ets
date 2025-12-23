/**
 * 小说书源调试页面
 * 提供完整的书源调试功能，类似Legado原版
 * 
 * 文件路径: entry/src/main/ets/pages/NovelSourceDebugPage.ets
 */

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics, promptAction } from '@kit.ArkUI';
import { logger } from '../Utils/Logger';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { LegadoBookSource, LegadoSearchBook, LegadoBook, LegadoChapter } from '../Framework/Novel/LegadoSourceTypes';
import { getNovelSourceManager } from '../Framework/Novel/NovelSourceManager';
import { NovelSourceExecutor } from '../Framework/Novel/NovelSourceExecutor';
import { LegadoWebViewComponent } from '../Framework/Novel/LegadoWebViewComponent';

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
  
  private executor: NovelSourceExecutor | null = null;
  private logScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (theme: ThemeType) => {
      logger.info(TAG, `主题切换: ${theme}`);
    });
    
    // 从AppStorage获取参数
    const params = AppStorage.get<NovelSourceDebugPageParams>('NovelSourceDebugPageParams');
    if (params && params.sourceId) {
      this.sourceId = params.sourceId;
      this.loadSource();
    }
  }

  aboutToDisappear(): void {
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
  }

  /**
   * 加载书源
   */
  loadSource(): void {
    const sourceManager = getNovelSourceManager();
    const source = sourceManager.getSource(this.sourceId);
    if (source) {
      this.source = source;
      this.executor = new NovelSourceExecutor(source);
      this.addLog('info', `已加载书源: ${source.bookSourceName}`);
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
    if (!this.executor || !this.source) {
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
      const results = await this.executor.search(this.searchKeyword, 1);
      const elapsed = Date.now() - startTime;
      
      this.searchResults = results;
      
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
    if (!this.executor) {
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
      const info = await this.executor.getBookInfo(book.bookUrl);
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
    if (!this.executor || !this.bookInfo) {
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
      const chapters = await this.executor.getChapterList(this.bookInfo);
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
    if (!this.executor) {
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
      const content = await this.executor.getContent(chapter);
      const elapsed = Date.now() - startTime;
      
      if (content && content.length > 0) {
        this.chapterContent = content;
        this.addLog('success', `获取正文成功，${content.length} 字符 (${elapsed}ms)`);
        this.addLog('debug', `正文预览: ${content.substring(0, 200)}...`);
      } else {
        this.addLog('warn', `获取正文失败，返回空数据 (${elapsed}ms)`);
      }
    } catch (error) {
      this.addLog('error', `获取正文失败: ${String(error)}`);
    }
    
    this.isRunning = false;
  }

  /**
   * 一键测试所有功能
   */
  async testAll(): Promise<void> {
    if (!this.executor || !this.source) {
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
        // 隐藏的WebView组件，用于执行JS网络请求
        LegadoWebViewComponent()
        
        Column() {
          // 搜索输入区
          this.buildSearchInput()
          
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
            .padding({ left: 16, right: 16, bottom: 32 })
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
        }
        .width('100%')
        .height('100%')
        .padding({ top: this.statusBarHeight, bottom: this.navigationBarHeight })
        
        // 加载遮罩
        if (this.isRunning) {
          this.buildLoadingOverlay()
        }
      }
      .width('100%')
      .height('100%')
    }
    .titleBar({
      padding: {
        start: LengthMetrics.vp(2),
        end: LengthMetrics.vp(2)
      },
      style: {
        originalStyle: {
          backgroundStyle: {
            backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme),
          },
          contentStyle: {
            titleStyle: {
              mainTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme),
            },
            menuStyle: {
              backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme),
              iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme)
            },
            backIconStyle: {
              backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme),
              iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme)
            }
          }
        }
      },
      content: {
        title: {
          mainTitle: this.source ? `调试: ${this.source.bookSourceName}` : '书源调试'
        }
      }
    })
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme))
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
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
          .onChange((value: string) => {
            this.searchKeyword = value;
          })
        
        Button('搜索')
          .fontSize(14)
          .height(40)
          .margin({ left: 8 })
          .enabled(!this.isRunning)
          .onClick(() => this.testSearch())
        
        Button('一键测试')
          .fontSize(14)
          .height(40)
          .margin({ left: 8 })
          .backgroundColor('#FF9800')
          .enabled(!this.isRunning)
          .onClick(() => this.testAll())
      }
      .width('100%')
      .padding(16)
    }
    .width('100%')
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
  }

  @Builder
  buildSearchResults() {
    Column() {
      Row() {
        Text(`搜索结果 (${this.searchResults.length})`)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        
        Blank()
        
        Text(this.showSearchResults ? '收起' : '展开')
          .fontSize(12)
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
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              
              Text(`${book.author || '未知作者'} · ${book.kind || '未分类'}`)
                .fontSize(12)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
                .margin({ top: 4 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            
            Button('详情')
              .fontSize(12)
              .height(28)
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
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        
        Blank()
        
        Button('获取目录')
          .fontSize(12)
          .height(28)
          .enabled(!this.isRunning)
          .onClick(() => this.testToc())
        
        Text(this.showBookInfo ? '收起' : '展开')
          .fontSize(12)
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
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
        .borderRadius(8)
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
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
        .width(60)
      
      Text(value)
        .fontSize(12)
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
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        
        Blank()
        
        Text(this.showChapters ? '收起' : '展开')
          .fontSize(12)
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
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            
            Button('正文')
              .fontSize(12)
              .height(26)
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
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        
        Blank()
        
        Text(`${this.chapterContent.length} 字`)
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
        
        Text(this.showContent ? '收起' : '展开')
          .fontSize(12)
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
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .lineHeight(22)
          .width('100%')
          .padding(12)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
          .borderRadius(8)
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
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        
        Blank()
        
        Text('清空')
          .fontSize(12)
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
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                .width(80)
              
              Text(this.getLogLevelIcon(log.level))
                .fontSize(12)
                .width(20)
              
              Text(log.message)
                .fontSize(12)
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
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
      .borderRadius(8)
      .padding(8)
    }
    .width('100%')
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
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .margin({ top: 12 })
    }
    .width('100%')
    .height('100%')
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
