/**
 * 小说详情页面
 * 展示书籍详情和章节列表
 * 使用 HdsNavDestination 实现统一的导航体验
 * 
 * 文件路径: entry/src/main/ets/pages/NovelDetailPage.ets
 */

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics, promptAction } from '@kit.ArkUI';
import { logger } from '../Utils/Logger';
import { getNovelSourceManager } from '../Framework/Novel/NovelSourceManager';
import { getNovelDataManager } from '../Framework/Novel/NovelDataManager';
import { getNovelChapterCacheManager } from '../Framework/Novel/NovelChapterCacheManager';
import { getNovelSettingsManager, BrowseHistoryInput } from '../Framework/Novel/NovelSettingsManager';
import { getNovelCoverGenerator, NovelCoverGenerator } from '../Framework/Novel/NovelCoverGenerator';
import { LegadoBook, LegadoChapter } from '../Framework/Novel/LegadoSourceTypes';
import { NovelBook, NovelReadStatus, NovelSearchResult } from '../Models/NovelModels';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { NovelDetailPageParams, NovelReaderPageParams } from './NovelBookshelfPage';
import { startBookOpenTransitionWithComponentId } from '../components/BookTransitionOverlay';

const TAG = 'NovelDetailPage';

const TITLE_BAR_HEIGHT_MINI = 56;

@Component
export struct NovelDetailPage {
  @Consume('NavPathStack') pathStack: NavPathStack;
  @State themeState: ThemeAwareState = new ThemeAwareState();
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private componentId: string = `NovelDetailPage_${Date.now()}`;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;
  
  @State book: LegadoBook | null = null;
  @State chapters: LegadoChapter[] = [];
  @State isLoading: boolean = true;
  @State isFavorite: boolean = false;
  @State showAllChapters: boolean = false;
  @State showFullIntro: boolean = false; // 是否展开完整简介
  @State showChapterPanel: boolean = false;
  @State showChangeSourcePanel: boolean = false;
  @State showDownloadPanel: boolean = false; // 下载范围选择面板
  @State isDownloading: boolean = false;
  @State downloadProgress: number = 0;
  @State downloadStartIndex: number = 0; // 下载起始章节索引
  @State downloadEndIndex: number = 0; // 下载结束章节索引
  @State cachedChapterIndexes: Set<number> = new Set(); // 已缓存的章节索引
  @State alternativeSources: NovelSearchResult[] = [];
  @State isSearchingSource: boolean = false;
  @State lastReadChapterIndex: number = -1; // 上次阅读的章节索引，-1表示未阅读
  @State lastReadChapterTitle: string = ''; // 上次阅读的章节标题
  private sourceId: string = '';
  private bookUrl: string = '';
  private bookId: string = ''; // 用于获取阅读进度
  private sourceManager = getNovelSourceManager();
  private dataManager = getNovelDataManager();
  private cacheManager = getNovelChapterCacheManager();
  private coverGenerator = getNovelCoverGenerator();
  // 从搜索结果传递的fallback信息
  private fallbackBookInfo: NovelDetailPageParams | null = null;
  // 生成的本地封面路径
  @State generatedCoverPath: string = '';

  aboutToAppear(): void {
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (theme: ThemeType) => {
      logger.info(TAG, `主题切换: ${theme}`);
    });
  }

  aboutToDisappear(): void {
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
  }

  async loadBookInfo(): Promise<void> {
    if (!this.sourceId || !this.bookUrl) {
      logger.error(TAG, '缺少必要参数');
      this.isLoading = false;
      return;
    }

    try {
      // 尝试获取书籍详情
      this.book = await this.sourceManager.getBookInfo(this.sourceId, this.bookUrl);
      
      // 如果详情页返回了部分结果（如只有tocUrl没有name），用fallback补充缺失字段
      if (this.book && !this.book.name && this.fallbackBookInfo && this.fallbackBookInfo.bookName) {
        logger.info(TAG, `详情页部分解析成功，用fallback补充书名: ${this.fallbackBookInfo.bookName}`);
        this.book = this.mergeBookWithFallback(this.book);
      }
      
      // 如果详情页解析完全失败，使用搜索结果中的fallback信息
      if (!this.book && this.fallbackBookInfo && this.fallbackBookInfo.bookName) {
        logger.info(TAG, `详情页解析失败，使用fallback信息: ${this.fallbackBookInfo.bookName}`);
        this.book = this.createBookFromFallback();
      }
      
      if (this.book) {
        // 获取章节列表
        this.chapters = await this.sourceManager.getChapterList(this.sourceId, this.book);
        logger.info(TAG, `加载完成: ${this.book.name}, ${this.chapters.length}章`);
        
        // 检查收藏状态
        await this.checkFavoriteStatus();
        
        // 加载阅读进度
        await this.loadReadProgress();
        
        // 加载缓存状态
        this.cachedChapterIndexes = await this.cacheManager.getCachedChapterIndexes(this.bookId, this.chapters.length);
        logger.info(TAG, `已缓存 ${this.cachedChapterIndexes.size} 章`);
        
        // 记录历史浏览（进入详情页即记录）
        await this.recordBrowseHistory();
      } else {
        logger.error(TAG, '无法获取书籍信息');
      }
    } catch (error) {
      logger.error(TAG, `加载失败: ${String(error)}`);
      // 发生异常时也尝试使用fallback
      if (!this.book && this.fallbackBookInfo && this.fallbackBookInfo.bookName) {
        logger.info(TAG, `异常后使用fallback信息: ${this.fallbackBookInfo.bookName}`);
        this.book = this.createBookFromFallback();
        // 尝试获取章节列表
        if (this.book) {
          try {
            this.chapters = await this.sourceManager.getChapterList(this.sourceId, this.book);
          } catch (e) {
            logger.warn(TAG, `获取章节列表失败: ${String(e)}`);
          }
        }
      }
    }
    this.isLoading = false;
  }

  /**
   * 记录历史浏览
   */
  private async recordBrowseHistory(): Promise<void> {
    if (!this.book) return;
    
    try {
      const settingsManager = getNovelSettingsManager();
      const historyInput: BrowseHistoryInput = {
        sourceId: this.sourceId,
        bookUrl: this.bookUrl,
        bookName: this.book.name || '',
        author: this.book.author || '',
        coverUrl: this.book.coverUrl || '',
        sourceName: this.book.originName || ''
      };
      await settingsManager.addBrowseHistory(historyInput);
      logger.debug(TAG, `已记录历史浏览: ${this.book.name}`);
    } catch (error) {
      logger.warn(TAG, `记录历史浏览失败: ${String(error)}`);
    }
  }

  /**
   * 合并详情页解析结果和fallback信息
   * 详情页可能只解析出tocUrl，其他字段需要用fallback补充
   */
  private mergeBookWithFallback(parsedBook: LegadoBook): LegadoBook {
    const fallback = this.fallbackBookInfo!;
    const book: LegadoBook = {
      id: parsedBook.id,
      origin: parsedBook.origin,
      originName: parsedBook.originName || fallback.sourceName || '',
      bookUrl: parsedBook.bookUrl,
      name: parsedBook.name || fallback.bookName || '未知书名',
      author: parsedBook.author || fallback.author || '',
      kind: parsedBook.kind || fallback.kind,
      intro: parsedBook.intro || fallback.intro,
      coverUrl: parsedBook.coverUrl || fallback.coverUrl,
      tocUrl: parsedBook.tocUrl, // 使用详情页解析的tocUrl，这是关键
      latestChapterTitle: parsedBook.latestChapterTitle || fallback.latestChapterTitle,
      wordCount: parsedBook.wordCount || fallback.wordCount,
      type: parsedBook.type
    };
    return book;
  }

  /**
   * 从fallback信息创建书籍对象
   */
  private createBookFromFallback(): LegadoBook {
    const fallback = this.fallbackBookInfo!;
    const book: LegadoBook = {
      id: `fallback_${Date.now()}`,
      origin: this.sourceId,
      originName: fallback.sourceName || '',
      bookUrl: this.bookUrl,
      name: fallback.bookName || '未知书名',
      author: fallback.author || '',
      kind: fallback.kind,
      intro: fallback.intro,
      coverUrl: fallback.coverUrl,
      tocUrl: this.bookUrl, // 使用bookUrl作为目录URL
      latestChapterTitle: fallback.latestChapterTitle,
      wordCount: fallback.wordCount,
      type: 0
    };
    return book;
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.Bottom }) {
        // 背景层：扩展到系统栏区域，实现完全沉浸式背景
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme))
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .animation(ThemeAwareHelper.getThemeTransitionAnimation())
        
        // 内容层：预留标题栏高度
        Scroll() {
          Column() {
            
            if (this.isLoading) {
              this.buildLoading()
            } else if (this.book) {
              // 书籍信息
              this.buildBookInfo()
              
              // 操作按钮
              this.buildActions()
              
              // 章节列表
              this.buildChapterList()
            } else {
              this.buildError()
            }
            
            Blank().height(20)
          }
          .width('100%')
        }
        .width('100%')
        .height('100%')
        .align(Alignment.TopStart)
        .padding({ top: this.statusBarHeight, bottom: this.navigationBarHeight })
        
        // 章节列表面板
        Column() {
          // 遮罩层
          Column()
            .width('100%')
            .layoutWeight(1)
            .backgroundColor('rgba(0,0,0,0.5)')
            .onClick(() => {
              this.showChapterPanel = false;
            })
          
          this.buildChapterPanel()
        }
        .width('100%')
        .height('100%')
        .opacity(this.showChapterPanel ? 1 : 0)
        .translate({ y: this.showChapterPanel ? 0 : '100%' })
        .animation({ duration: 250, curve: Curve.EaseOut })
        .hitTestBehavior(this.showChapterPanel ? HitTestMode.Default : HitTestMode.None)
        
        // 换源面板
        Column() {
          // 遮罩层
          Column()
            .width('100%')
            .layoutWeight(1)
            .backgroundColor('rgba(0,0,0,0.5)')
            .onClick(() => {
              this.showChangeSourcePanel = false;
            })
          
          this.buildChangeSourcePanel()
        }
        .width('100%')
        .height('100%')
        .opacity(this.showChangeSourcePanel ? 1 : 0)
        .translate({ y: this.showChangeSourcePanel ? 0 : '100%' })
        .animation({ duration: 250, curve: Curve.EaseOut })
        .hitTestBehavior(this.showChangeSourcePanel ? HitTestMode.Default : HitTestMode.None)
        
        // 下载范围选择面板
        Column() {
          // 遮罩层
          Column()
            .width('100%')
            .layoutWeight(1)
            .backgroundColor('rgba(0,0,0,0.5)')
            .onClick(() => {
              this.showDownloadPanel = false;
            })
          
          this.buildDownloadPanel()
        }
        .width('100%')
        .height('100%')
        .opacity(this.showDownloadPanel ? 1 : 0)
        .translate({ y: this.showDownloadPanel ? 0 : '100%' })
        .animation({ duration: 250, curve: Curve.EaseOut })
        .hitTestBehavior(this.showDownloadPanel ? HitTestMode.Default : HitTestMode.None)
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
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: ScrollEffectType.COMMON_BLUR,
          blurEffectiveStartOffset: LengthMetrics.vp(0),
          blurEffectiveEndOffset: LengthMetrics.vp(20)
        },
        originalStyle: {
          backgroundStyle: {
            backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme),
          },
          contentStyle: {
            titleStyle: {
              mainTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme),
              subTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)
            },
            backIconStyle: {
              backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme),
              iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme)
            }
          }
        },
        scrollEffectStyle: {
          backgroundStyle: {
            backgroundColor: this.themeState.currentTheme === ThemeType.LIGHT ? '#E6FFFFFF' : '#E6000000',
          },
          contentStyle: {
            titleStyle: {
              mainTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme),
              subTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)
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
          mainTitle: this.book?.name || '书籍详情'
        }
      }
    })
    .backgroundColor(Color.Transparent)
    .onReady((context: NavDestinationContext) => {
      logger.info(TAG, 'HdsNavDestination.onReady 已触发');
      const param = context.pathInfo.param as NovelDetailPageParams | null;
      if (param) {
        this.sourceId = param.sourceId || '';
        this.bookUrl = param.bookUrl || '';
        // 生成bookId用于获取阅读进度
        this.bookId = `${this.sourceId}_${encodeURIComponent(this.bookUrl)}`;
        // 保存fallback信息
        this.fallbackBookInfo = param;
        this.loadBookInfo();
      } else {
        this.isLoading = false;
      }
    })
    .onShown(() => {
      // 页面显示时刷新阅读进度和缓存状态（无感刷新，不显示loading）
      logger.info(TAG, '页面显示，刷新阅读进度和缓存状态');
      this.refreshProgressAndCache();
    })
  }

  /**
   * 刷新阅读进度和缓存状态（无感刷新）
   */
  private async refreshProgressAndCache(): Promise<void> {
    if (!this.bookId || this.chapters.length === 0) return;
    
    try {
      // 刷新阅读进度
      await this.loadReadProgress();
      
      // 刷新收藏状态
      await this.checkFavoriteStatus();
      
      // 刷新缓存状态
      this.cachedChapterIndexes = await this.cacheManager.getCachedChapterIndexes(this.bookId, this.chapters.length);
      logger.debug(TAG, `刷新完成: 阅读进度=${this.lastReadChapterIndex}, 缓存=${this.cachedChapterIndexes.size}章`);
    } catch (error) {
      logger.warn(TAG, `刷新状态失败: ${String(error)}`);
    }
  }

  @Builder
  buildLoading() {
    Column() {
      LoadingProgress()
        .width(48)
        .height(48)
        .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
      Text('加载中...')
        .fontSize(14)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
        .margin({ top: 16 })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  buildError() {
    Column() {
      Text('加载失败')
        .fontSize(14)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
      Button('重试')
        .margin({ top: 16 })
        .onClick(() => {
          this.isLoading = true;
          this.loadBookInfo();
        })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  buildBookInfo() {
    Row() {
      // 封面 - 添加id用于翻开动画
      if (this.book?.coverUrl) {
        Image(this.book.coverUrl)
          .width(100)
          .height(140)
          .borderRadius(6)
          .objectFit(ImageFit.Cover)
          .id(`novel_cover_${this.sourceId}_${encodeURIComponent(this.bookUrl)}`)
      } else {
        Column() {
          Text((this.book?.name || '').substring(0, 1))
            .fontSize(32)
            .fontColor('#FFFFFF')
        }
        .width(100)
        .height(140)
        .borderRadius(6)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        .justifyContent(FlexAlign.Center)
        .id(`novel_cover_${this.sourceId}_${encodeURIComponent(this.bookUrl)}`)
      }
      
      // 信息
      Column() {
        Text(this.book?.name || '')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        
        Text(this.book?.author || '未知作者')
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .margin({ top: 8 })
        
        if (this.book?.kind) {
          Text(this.book.kind)
            .fontSize(12)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
            .margin({ top: 4 })
        }
        
        Row() {
          Text(this.book?.originName || '')
            .fontSize(11)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme))
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(2)
          
          Text(`${this.chapters.length}章`)
            .fontSize(11)
            .fontColor('#52C41A')
            .margin({ left: 8 })
        }
        .margin({ top: 12 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 16 })
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))

    // 简介
    if (this.book?.intro) {
      Column() {
        Row() {
          Text('简介')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          
          Blank()
          
          Text(this.showFullIntro ? '收起' : '展开')
            .fontSize(12)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .onClick(() => {
              this.showFullIntro = !this.showFullIntro;
            })
        }
        .width('100%')
        
        Text(this.book.intro)
          .fontSize(13)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .margin({ top: 8 })
          .maxLines(this.showFullIntro ? 100 : 3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .padding(16)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
      .margin({ top: 8 })
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  buildActions() {
    Column() {
      // 主要操作按钮
      Row() {
        Button(this.isFavorite ? '已收藏' : '加入书架')
          .fontSize(14)
          .fontColor(this.isFavorite ? 
            ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme) : '#FFFFFF')
          .backgroundColor(this.isFavorite ? 
            ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme) : 
            ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .borderRadius(20)
          .layoutWeight(1)
          .height(44)
          .margin({ right: 8 })
          .onClick(() => this.toggleFavorite())
        
        Button(this.lastReadChapterIndex >= 0 ? '继续阅读' : '开始阅读')
          .fontSize(14)
          .fontColor('#FFFFFF')
          .backgroundColor('#52C41A')
          .borderRadius(20)
          .layoutWeight(1)
          .height(44)
          .margin({ left: 8 })
          .onClick(() => this.startReading())
      }
      .width('100%')
      
      // 次要操作按钮（换源、下载）
      Row() {
        // 换源按钮
        Column() {
          Image($r('app.media.ic_refresh'))
            .width(20)
            .height(20)
            .fillColor(ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme))
          Text('换源')
            .fontSize(12)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .margin({ top: 4 })
        }
        .layoutWeight(1)
        .onClick(() => this.searchAlternativeSources())
        
        // 下载按钮
        Column() {
          if (this.isDownloading) {
            Stack() {
              Progress({ value: this.downloadProgress, total: 100, type: ProgressType.Ring })
                .width(20)
                .height(20)
                .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            }
          } else {
            Image($r('app.media.ic_download'))
              .width(20)
              .height(20)
              .fillColor(ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme))
          }
          Text(this.isDownloading ? `${Math.round(this.downloadProgress)}%` : '缓存')
            .fontSize(12)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .margin({ top: 4 })
        }
        .layoutWeight(1)
        .onClick(() => {
          if (!this.isDownloading) {
            this.showDownloadOptions();
          }
        })
      }
      .width('100%')
      .margin({ top: 16 })
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
    .margin({ top: 8 })
  }

  @Builder
  buildChapterList() {
    Column() {
      Row() {
        Text('章节列表')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        
        Blank()
        
        Text('查看全部')
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .onClick(() => {
            this.showChapterPanel = true;
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })

      // 章节列表
      ForEach(
        this.showAllChapters ? this.chapters : this.chapters.slice(0, 20),
        (chapter: LegadoChapter, index: number) => {
          Row() {
            // 阅读进度标记
            if (index === this.lastReadChapterIndex) {
              Text('▶')
                .fontSize(10)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                .margin({ right: 6 })
            }
            
            Text(chapter.title)
              .fontSize(14)
              .fontColor(index === this.lastReadChapterIndex ? 
                ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) :
                (chapter.isVip ? '#FF9800' : 
                  ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            
            // 缓存状态图标
            if (this.cachedChapterIndexes.has(index)) {
              Text('✓')
                .fontSize(10)
                .fontColor('#52C41A')
                .margin({ left: 4 })
            }
            
            if (index === this.lastReadChapterIndex) {
              Text('上次阅读')
                .fontSize(10)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme))
                .padding({ left: 4, right: 4, top: 2, bottom: 2 })
                .borderRadius(2)
                .margin({ left: 8 })
            } else if (chapter.isVip) {
              Text('VIP')
                .fontSize(10)
                .fontColor('#FF9800')
                .margin({ left: 8 })
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
          .backgroundColor(index === this.lastReadChapterIndex ? 
            ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme) : 
            Color.Transparent)
          .onClick(() => this.readChapter(chapter, index))
        }
      )
      
      if (!this.showAllChapters && this.chapters.length > 20) {
        Text(`还有${this.chapters.length - 20}章，点击展开`)
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
          .padding(16)
          .onClick(() => {
            this.showAllChapters = true;
          })
      }
    }
    .width('100%')
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
    .margin({ top: 8 })
    .alignItems(HorizontalAlign.Start)
  }

  async toggleFavorite(): Promise<void> {
    if (!this.book) return;
    
    this.isFavorite = !this.isFavorite;
    
    const bookId = `${this.sourceId}_${encodeURIComponent(this.bookUrl)}`;
    let coverLocalPath: string | undefined = undefined;
    
    // 如果是添加到书架且没有封面URL，生成本地封面
    if (this.isFavorite && !this.book.coverUrl) {
      try {
        logger.info(TAG, `书籍没有封面，尝试生成本地封面: ${this.book.name}`);
        const generatedPath = await this.coverGenerator.generateCover(
          bookId,
          this.book.name,
          () => { this.buildNovelCoverForSnapshot(this.book!.name); }
        );
        if (generatedPath) {
          coverLocalPath = generatedPath;
          this.generatedCoverPath = generatedPath;
          logger.info(TAG, `本地封面生成成功: ${generatedPath}`);
        }
      } catch (error) {
        logger.warn(TAG, `生成封面失败: ${String(error)}`);
      }
    }
    
    // 保存到数据库
    const novelBook: NovelBook = {
      id: bookId,
      sourceId: this.sourceId,
      sourceName: this.book.originName,
      bookUrl: this.bookUrl,
      name: this.book.name,
      author: this.book.author,
      kind: this.book.kind,
      intro: this.book.intro,
      coverUrl: this.book.coverUrl,
      coverLocalPath: coverLocalPath,
      tocUrl: this.book.tocUrl,
      latestChapterTitle: this.book.latestChapterTitle,
      wordCount: this.book.wordCount,
      chapterCount: this.chapters.length,
      readStatus: NovelReadStatus.UNREAD,
      totalReadingTime: 0,
      isFavorite: this.isFavorite,
      createTime: Date.now(),
      updateDbTime: Date.now()
    };
    
    await this.dataManager.saveBook(novelBook);
    
    if (this.isFavorite) {
      promptAction.showToast({ message: coverLocalPath ? '已加入书架（已生成封面）' : '已加入书架' });
    } else {
      promptAction.showToast({ message: '已从书架移除' });
    }
  }

  /**
   * 检查收藏状态
   */
  async checkFavoriteStatus(): Promise<void> {
    try {
      const existingBook = await this.dataManager.getBookByUrl(this.sourceId, this.bookUrl);
      if (existingBook && existingBook.isFavorite) {
        this.isFavorite = true;
        logger.info(TAG, `书籍已在书架: ${this.book?.name}`);
      } else {
        this.isFavorite = false;
      }
    } catch (error) {
      logger.warn(TAG, `检查收藏状态失败: ${String(error)}`);
    }
  }

  /**
   * 加载阅读进度
   */
  async loadReadProgress(): Promise<void> {
    try {
      const progress = await this.dataManager.getReadProgress(this.bookId);
      if (progress && progress.chapterIndex >= 0 && progress.chapterIndex < this.chapters.length) {
        this.lastReadChapterIndex = progress.chapterIndex;
        this.lastReadChapterTitle = this.chapters[progress.chapterIndex]?.title || '';
        logger.info(TAG, `加载阅读进度: 章节${progress.chapterIndex} - ${this.lastReadChapterTitle}`);
      }
    } catch (error) {
      logger.warn(TAG, `加载阅读进度失败: ${String(error)}`);
    }
  }

  startReading(): void {
    if (this.chapters.length > 0) {
      // 如果有阅读进度，从上次阅读的章节继续
      if (this.lastReadChapterIndex >= 0 && this.lastReadChapterIndex < this.chapters.length) {
        this.readChapter(this.chapters[this.lastReadChapterIndex], this.lastReadChapterIndex);
      } else {
        // 否则从第一章开始
        this.readChapter(this.chapters[0], 0);
      }
    }
  }

  readChapter(chapter: LegadoChapter, index: number): void {
    const tocUrl = this.book?.tocUrl || this.bookUrl;
    logger.info(TAG, `跳转阅读器: tocUrl=${tocUrl}, bookUrl=${this.bookUrl}`);
    const params: NovelReaderPageParams = {
      sourceId: this.sourceId,
      bookUrl: this.bookUrl,
      bookName: this.book?.name || '',
      chapterUrl: chapter.url,
      chapterTitle: chapter.title,
      chapterIndex: index,
      totalChapters: this.chapters.length,
      tocUrl: tocUrl // 传递目录URL
    };
    
    // 获取封面路径和组件ID
    const coverPath = this.book?.coverUrl || '';
    const bookId = `${this.sourceId}_${encodeURIComponent(this.bookUrl)}`;
    const coverComponentId = `novel_cover_${bookId}`;
    
    // 触发翻开动画
    logger.info(TAG, `触发翻开过渡动画: coverPath=${coverPath}, componentId=${coverComponentId}`);
    startBookOpenTransitionWithComponentId(
      coverPath,
      coverComponentId,
      bookId,
      'novel',
      () => {
        // 动画完成后导航到阅读器
        this.pathStack.pushPathByName('NovelReaderPage', params);
      }
    );
  }

  /**
   * 换源 - 搜索同名书籍
   */
  async searchAlternativeSources(): Promise<void> {
    if (!this.book) return;
    
    this.isSearchingSource = true;
    this.alternativeSources = [];
    this.showChangeSourcePanel = true;
    
    try {
      const results = await this.sourceManager.searchAll(this.book.name, 1, 10);
      // 过滤出同名或相似的书籍
      this.alternativeSources = results.filter(r => 
        r.name === this.book?.name || 
        r.name.includes(this.book?.name || '') ||
        (this.book?.name || '').includes(r.name)
      );
      logger.info(TAG, `找到 ${this.alternativeSources.length} 个可用书源`);
    } catch (error) {
      logger.error(TAG, `搜索书源失败: ${String(error)}`);
    }
    this.isSearchingSource = false;
  }

  /**
   * 切换书源
   */
  async changeSource(source: NovelSearchResult): Promise<void> {
    this.sourceId = source.sourceId;
    this.bookUrl = source.bookUrl;
    this.showChangeSourcePanel = false;
    this.isLoading = true;
    
    // 重新加载书籍信息
    await this.loadBookInfo();
    
    promptAction.showToast({ message: `已切换到: ${source.sourceName}` });
  }

  /**
   * 下载章节
   */
  async downloadChapters(startIndex: number = 0, endIndex?: number): Promise<void> {
    if (!this.book || this.chapters.length === 0) return;
    
    const end = endIndex ?? this.chapters.length - 1;
    this.isDownloading = true;
    this.downloadProgress = 0;
    
    // 保存书籍元数据
    await this.cacheManager.saveBookMetadata(
      this.bookId,
      this.book.name,
      this.book.author || '',
      this.book.coverUrl || ''
    );
    
    const taskId = this.cacheManager.createDownloadTask(
      this.bookId,
      this.book.name,
      startIndex,
      end
    );
    
    await this.cacheManager.startDownload(taskId, this.sourceId, this.chapters, {
      onProgress: (current: number, total: number, title: string) => {
        this.downloadProgress = (current / total) * 100;
        logger.debug(TAG, `下载进度: ${current}/${total} - ${title}`);
      },
      onComplete: async () => {
        this.isDownloading = false;
        this.downloadProgress = 100;
        // 刷新缓存状态
        this.cachedChapterIndexes = await this.cacheManager.getCachedChapterIndexes(this.bookId, this.chapters.length);
        promptAction.showToast({ message: '下载完成' });
      },
      onError: (error: string) => {
        this.isDownloading = false;
        promptAction.showToast({ message: `下载失败: ${error}` });
      }
    });
  }

  /**
   * 显示下载选项
   */
  async showDownloadOptions(): Promise<void> {
    if (this.chapters.length === 0) {
      promptAction.showToast({ message: '没有可下载的章节' });
      return;
    }
    
    // 加载已缓存的章节信息
    this.cachedChapterIndexes = await this.cacheManager.getCachedChapterIndexes(this.bookId, this.chapters.length);
    
    // 初始化下载范围（默认从第一个未缓存的章节开始）
    this.downloadStartIndex = 0;
    this.downloadEndIndex = this.chapters.length - 1;
    
    // 找到第一个未缓存的章节作为起始点
    for (let i = 0; i < this.chapters.length; i++) {
      if (!this.cachedChapterIndexes.has(i)) {
        this.downloadStartIndex = i;
        break;
      }
    }
    
    this.showDownloadPanel = true;
  }

  /**
   * 获取下载范围内未缓存的章节数
   */
  getUncachedCount(): number {
    let count = 0;
    for (let i = this.downloadStartIndex; i <= this.downloadEndIndex; i++) {
      if (!this.cachedChapterIndexes.has(i)) {
        count++;
      }
    }
    return count;
  }

  @Builder
  buildDownloadPanel() {
    Column() {
      // 顶部栏
      Row() {
        Text('选择下载范围')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        
        Blank()
        
        Image($r('app.media.ic_close'))
          .width(24)
          .height(24)
          .fillColor(ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme))
          .onClick(() => {
            this.showDownloadPanel = false;
          })
      }
      .width('100%')
      .padding(16)
      
      // 缓存状态信息
      Row() {
        Text(`共 ${this.chapters.length} 章`)
          .fontSize(13)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        
        Text(`已缓存 ${this.cachedChapterIndexes.size} 章`)
          .fontSize(13)
          .fontColor('#52C41A')
          .margin({ left: 16 })
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 8 })
      
      // 起始章节选择
      Column() {
        Row() {
          Text('起始章节')
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          
          Blank()
          
          Text(`第 ${this.downloadStartIndex + 1} 章`)
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        }
        .width('100%')
        
        Text(this.chapters[this.downloadStartIndex]?.title || '')
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 4 })
          .width('100%')
        
        Slider({
          value: this.downloadStartIndex,
          min: 0,
          max: this.chapters.length - 1,
          step: 1,
          style: SliderStyle.OutSet
        })
          .blockColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .trackColor(ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme))
          .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .margin({ top: 8 })
          .onChange((value: number) => {
            this.downloadStartIndex = Math.round(value);
            // 确保起始不超过结束
            if (this.downloadStartIndex > this.downloadEndIndex) {
              this.downloadEndIndex = this.downloadStartIndex;
            }
          })
      }
      .width('100%')
      .padding(16)
      .alignItems(HorizontalAlign.Start)
      
      // 结束章节选择
      Column() {
        Row() {
          Text('结束章节')
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          
          Blank()
          
          Text(`第 ${this.downloadEndIndex + 1} 章`)
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        }
        .width('100%')
        
        Text(this.chapters[this.downloadEndIndex]?.title || '')
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 4 })
          .width('100%')
        
        Slider({
          value: this.downloadEndIndex,
          min: 0,
          max: this.chapters.length - 1,
          step: 1,
          style: SliderStyle.OutSet
        })
          .blockColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .trackColor(ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme))
          .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .margin({ top: 8 })
          .onChange((value: number) => {
            this.downloadEndIndex = Math.round(value);
            // 确保结束不小于起始
            if (this.downloadEndIndex < this.downloadStartIndex) {
              this.downloadStartIndex = this.downloadEndIndex;
            }
          })
      }
      .width('100%')
      .padding(16)
      .alignItems(HorizontalAlign.Start)
      
      // 下载信息和按钮
      Column() {
        Text(`将下载 ${this.getUncachedCount()} 章（共选择 ${this.downloadEndIndex - this.downloadStartIndex + 1} 章）`)
          .fontSize(13)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        
        Button('开始下载')
          .fontSize(16)
          .fontColor('#FFFFFF')
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .borderRadius(24)
          .width('100%')
          .height(48)
          .margin({ top: 16 })
          .onClick(() => {
            this.showDownloadPanel = false;
            this.downloadChapters(this.downloadStartIndex, this.downloadEndIndex);
          })
      }
      .width('100%')
      .padding(16)
    }
    .width('100%')
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme))
    .borderRadius({ topLeft: 16, topRight: 16 })
  }

  @Builder
  buildChapterPanel() {
    Column() {
      // 顶部栏
      Row() {
        Text('章节列表')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        
        Blank()
        
        Image($r('app.media.ic_close'))
          .width(24)
          .height(24)
          .fillColor(ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme))
          .onClick(() => {
            this.showChapterPanel = false;
          })
      }
      .width('100%')
      .padding(16)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
      
      // 章节列表
      List() {
        ForEach(this.chapters, (chapter: LegadoChapter, index: number) => {
          ListItem() {
            Row() {
              Text(`${index + 1}.`)
                .fontSize(12)
                .fontColor(index === this.lastReadChapterIndex ? 
                  ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) :
                  ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
                .width(40)
              
              Text(chapter.title)
                .fontSize(14)
                .fontColor(index === this.lastReadChapterIndex ? 
                  ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) :
                  (chapter.isVip ? '#FF9800' : 
                    ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)))
                .fontWeight(index === this.lastReadChapterIndex ? FontWeight.Medium : FontWeight.Normal)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
              
              // 缓存状态图标
              if (this.cachedChapterIndexes.has(index)) {
                Text('✓')
                  .fontSize(10)
                  .fontColor('#52C41A')
                  .margin({ left: 4 })
              }
              
              if (index === this.lastReadChapterIndex) {
                Text('上次阅读')
                  .fontSize(10)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                  .margin({ left: 8 })
              } else if (chapter.isVip) {
                Text('VIP')
                  .fontSize(10)
                  .fontColor('#FF9800')
                  .margin({ left: 8 })
              }
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 12, bottom: 12 })
            .onClick(() => {
              this.showChapterPanel = false;
              this.readChapter(chapter, index);
            })
          }
        })
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('80%')
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_primary', this.themeState.currentTheme))
    .borderRadius({ topLeft: 16, topRight: 16 })
  }

  @Builder
  buildChangeSourcePanel() {
    Column() {
      // 顶部栏
      Row() {
        Text('换源')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        
        Blank()
        
        Image($r('app.media.ic_close'))
          .width(24)
          .height(24)
          .fillColor(ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme))
          .onClick(() => {
            this.showChangeSourcePanel = false;
          })
      }
      .width('100%')
      .padding(16)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
      
      if (this.isSearchingSource) {
        Column() {
          LoadingProgress()
            .width(32)
            .height(32)
          Text('正在搜索可用书源...')
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
            .margin({ top: 12 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.alternativeSources.length === 0) {
        Column() {
          Text('未找到其他书源')
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List() {
          ForEach(this.alternativeSources, (source: NovelSearchResult) => {
            ListItem() {
              Row() {
                Column() {
                  Text(source.sourceName)
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(source.sourceId === this.sourceId ? 
                      ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) :
                      ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                  
                  Text(source.latestChapterTitle || '暂无最新章节信息')
                    .fontSize(12)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
                    .margin({ top: 4 })
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                
                if (source.sourceId === this.sourceId) {
                  Text('当前')
                    .fontSize(12)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme))
                    .borderRadius(4)
                }
              }
              .width('100%')
              .padding(16)
              .onClick(() => {
                if (source.sourceId !== this.sourceId) {
                  this.changeSource(source);
                }
              })
            }
          })
        }
        .layoutWeight(1)
        .width('100%')
        .divider({ strokeWidth: 0.5, color: ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme) })
      }
    }
    .width('100%')
    .height('60%')
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_primary', this.themeState.currentTheme))
    .borderRadius({ topLeft: 16, topRight: 16 })
  }

  // 封面生成器常量
  private static readonly COVER_WIDTH = 400;
  private static readonly COVER_HEIGHT = 600;
  private static readonly TITLE_AREA_TOP_PERCENT = 0.130;
  private static readonly TITLE_AREA_BOTTOM_PERCENT = 0.345;
  private static readonly TITLE_AREA_LEFT_PERCENT = 0.110;
  private static readonly TITLE_AREA_RIGHT_PERCENT = 0.895;

  /**
   * 格式化封面标题
   */
  private formatCoverTitle(title: string): string {
    let cleanTitle = title.replace(/\.(txt|epub|pdf|mobi|azw3?)$/i, '');
    if (cleanTitle.length > 20) {
      cleanTitle = cleanTitle.substring(0, 17) + '...';
    }
    return cleanTitle;
  }

  /**
   * 计算封面字体大小
   */
  private calculateCoverFontSize(title: string): number {
    const length = title.length;
    if (length <= 2) return 70;
    if (length <= 4) return 56;
    if (length <= 6) return 48;
    if (length <= 8) return 36;
    if (length <= 12) return 32;
    if (length <= 16) return 28;
    return 24;
  }

  /**
   * 构建小说封面组件（用于 componentSnapshot）
   */
  @Builder
  buildNovelCoverForSnapshot(title: string) {
    Stack() {
      // 底层：默认封面图片
      Image($r('app.media.ebook'))
        .width(NovelDetailPage.COVER_WIDTH)
        .height(NovelDetailPage.COVER_HEIGHT)
        .objectFit(ImageFit.Cover)
      
      // 标题文字层
      Text(this.formatCoverTitle(title))
        .fontSize(this.calculateCoverFontSize(title))
        .fontWeight(FontWeight.Bold)
        .fontColor('#1a1a1a')
        .textAlign(TextAlign.Center)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .lineHeight(this.calculateCoverFontSize(title) * 1.3)
        .width(NovelDetailPage.COVER_WIDTH * (NovelDetailPage.TITLE_AREA_RIGHT_PERCENT - NovelDetailPage.TITLE_AREA_LEFT_PERCENT) - 24)
        .constraintSize({
          maxHeight: NovelDetailPage.COVER_HEIGHT * (NovelDetailPage.TITLE_AREA_BOTTOM_PERCENT - NovelDetailPage.TITLE_AREA_TOP_PERCENT) - 20
        })
        .position({
          x: NovelDetailPage.COVER_WIDTH * NovelDetailPage.TITLE_AREA_LEFT_PERCENT + 12,
          y: NovelDetailPage.COVER_HEIGHT * (NovelDetailPage.TITLE_AREA_TOP_PERCENT + NovelDetailPage.TITLE_AREA_BOTTOM_PERCENT) / 2 - this.calculateCoverFontSize(title) * 0.65
        })
    }
    .width(NovelDetailPage.COVER_WIDTH)
    .height(NovelDetailPage.COVER_HEIGHT)
  }
}
