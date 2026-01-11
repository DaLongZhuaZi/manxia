// 文件路径: entry/src/main/ets/pages/UnifiedDetailPage.ets
/**
 * 统一详情页
 * 支持显示漫画、电子书、小说的详细信息
 * 通过适配器模式将不同类型数据转换为统一展示格式
 */

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics, promptAction, curves } from '@kit.ArkUI';
import { logger } from '../Utils/Logger';
import { PageLifecycleManager } from '../Framework/Lifecycle';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';
import { DeviceAdaptationManager, DeviceInfo, DeviceChangeListener, Breakpoint } from '../Framework/Managers/DeviceAdaptationManager';
import { ResponsiveLayoutHelper } from '../Framework/Utils/ResponsiveLayout';
import { ContentFilterManager } from '../Framework/Managers/ContentFilterManager';

import {
  UnifiedContent,
  UnifiedChapter,
  UnifiedContentType,
  UnifiedReadStatus,
  UnifiedDetailPageParams,
  UnifiedContentActions,
  ChapterFilterType,
  ChapterSortOrder,
  ChapterDisplayMode
} from '../Models/UnifiedContentModels';

import {
  UnifiedContentAdapterFactory,
  MangaAdapter,
  EBookAdapter,
  NovelAdapter,
  AdapterOptions
} from '../Framework/Adapters/UnifiedContentAdapter';

// 数据管理器导入
import { DataManager, ChapterInfo, OnlineChapterInfo } from '../Framework/Data/DataManager';
import { DataService } from '../Framework/Services/DataService';
import { MangaDetailLoader, MangaDetailLoadParams, MangaDetailLoadResult, MangaLoadProgressCallback, ChapterProgressInfo } from '../Framework/Loaders/MangaDetailLoader';
import webview from '@ohos.web.webview';
import { EBookDataManager } from '../Framework/Data/EBookDataManager';
import { getNovelSourceManager } from '../Framework/Novel/NovelSourceManager';
import { getNovelDataManager } from '../Framework/Novel/NovelDataManager';
import { getNovelChapterCacheManager } from '../Framework/Novel/NovelChapterCacheManager';
import { AvifImage } from '../components/AvifImage';

// 模型导入
import { Manga, MangaChapter, ReadingProgress, ReadingSettings, MangaBookmark, MangaMetadata, ImageSourceType, DEFAULT_READING_SETTINGS } from '../Models/MangaModels';
import { DownloadStatus, MangaStatus, ReadingStatus } from '../Framework/Types/StatusEnums';
import { EBook, EBookChapter } from '../Models/EBookModels';
import { LegadoBook, LegadoChapter } from '../Framework/Novel/LegadoSourceTypes';
import { NovelBook, NovelReadStatus } from '../Models/NovelModels';

// 阅读器参数导入
import { MangaReaderPageParams, MangaReaderContentType } from './MangaReaderPage';
import { MangaSettingsPageParams } from './MangaSettingsPage';
import { EBookSettingsPageParams } from './EBookDetailPage';
import { EBookReaderParams } from './EBookReaderPage';
import { NovelReaderPageParams } from './NovelBookshelfPage';

import { startBookOpenTransitionWithComponentId } from '../components/BookTransitionOverlay';

const TAG = 'UnifiedDetailPage';
const TITLE_BAR_HEIGHT = 56;
const COVER_HEIGHT = 200;
const COVER_WIDTH = 140;

@Component
export struct UnifiedDetailPage {
  @State pathStack: NavPathStack = new NavPathStack();
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  private componentId: string = `UnifiedDetailPage_${Date.now()}`;
  private scroller: Scroller = new Scroller();

  // 沉浸式显示状态
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;

  // 响应式布局
  private deviceManager: DeviceAdaptationManager = DeviceAdaptationManager.getInstance();
  private deviceChangeListener: DeviceChangeListener | null = null;
  @State responsive_contentPadding: number = 16;
  @State responsive_maxContentWidth: number = 1200;
  @State responsive_isLandscape: boolean = false;

  // 页面参数
  private pageParams: UnifiedDetailPageParams | null = null;

  // 统一内容数据
  @State content: UnifiedContent | null = null;
  @State isLoading: boolean = true;
  @State errorMessage: string = '';
  
  // 分阶段加载状态
  @State isBasicInfoLoaded: boolean = false;  // 基本信息是否加载完成
  @State isCoverLoading: boolean = true;      // 封面是否正在加载
  @State isChaptersLoading: boolean = true;   // 章节是否正在加载
  @State isPagesPreloading: boolean = false;  // 页面是否正在预加载
  @State chaptersLoadProgress: string = '';   // 章节加载进度文本
  
  // 下拉刷新状态
  @State isRefreshing: boolean = false;       // 是否正在刷新
  @State refreshProgress: string = '';        // 刷新进度文本
  
  // 漫画章节进度数据
  @State chapterProgressMap: Map<string, ChapterProgressInfo> = new Map();

  // UI状态
  @State isFavorite: boolean = false;
  @State showFullDescription: boolean = false;
  @State showChapterPanel: boolean = false;
  @State chapterFilter: ChapterFilterType = ChapterFilterType.ALL;
  @State chapterSortOrder: ChapterSortOrder = ChapterSortOrder.ASCENDING;
  @State chapterDisplayMode: ChapterDisplayMode = ChapterDisplayMode.LIST;

  // 数据管理器
  private dataManager: DataManager = DataManager.getInstance();
  private ebookDataManager: EBookDataManager = EBookDataManager.getInstance();
  private novelSourceManager = getNovelSourceManager();
  private novelDataManager = getNovelDataManager();
  private novelCacheManager = getNovelChapterCacheManager();
  
  // 漫画详情加载器
  private mangaDetailLoader: MangaDetailLoader = MangaDetailLoader.getInstance();
  private webViewController: webview.WebviewController = new webview.WebviewController();

  aboutToAppear(): void {
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (theme: ThemeType) => {
      logger.info(TAG, `主题切换: ${theme}`);
    });

    FontAwareHelper.initializeFontAware(
      this.componentId,
      this.fontState,
      (newState: FontAwareState) => {
        this.fontState = newState;
      }
    );

    this.initializeResponsiveLayout();
  }

  private lifecycle = new PageLifecycleManager('UnifiedDetailPage', { enableDebug: true });

  aboutToDisappear(): void {
    this.lifecycle.destroy();
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    FontAwareHelper.cleanupFontAware(this.componentId);

    if (this.deviceChangeListener) {
      this.deviceManager.removeListener(this.deviceChangeListener);
      this.deviceChangeListener = null;
    }
  }

  private initializeResponsiveLayout(): void {
    try {
      this.updateResponsiveParams();
      this.deviceChangeListener = (deviceInfo: DeviceInfo) => {
        logger.info(TAG, `设备状态变化: 断点=${deviceInfo.breakpoint}, 方向=${deviceInfo.orientation}`);
        this.updateResponsiveParams();
      };
      this.deviceManager.addListener(this.deviceChangeListener);
    } catch (error) {
      logger.error(TAG, '响应式布局初始化失败', String(error));
    }
  }

  private updateResponsiveParams(): void {
    const layoutParams = ResponsiveLayoutHelper.getLayoutParams();
    const deviceInfo = this.deviceManager.getDeviceInfo();
    this.responsive_contentPadding = layoutParams.contentPadding;
    this.responsive_isLandscape = deviceInfo.isLandscape;
    switch (deviceInfo.breakpoint) {
      case Breakpoint.XS:
        this.responsive_maxContentWidth = 600;
        break;
      case Breakpoint.SM:
        this.responsive_maxContentWidth = 840;
        break;
      case Breakpoint.MD:
        this.responsive_maxContentWidth = 1024;
        break;
      case Breakpoint.LG:
        this.responsive_maxContentWidth = 1200;
        break;
    }
  }

  /**
   * 加载内容数据
   */
  private async loadContent(): Promise<void> {
    if (!this.pageParams) {
      this.errorMessage = '缺少页面参数';
      this.isLoading = false;
      return;
    }

    try {
      this.isLoading = true;
      this.errorMessage = '';

      switch (this.pageParams.contentType) {
        case UnifiedContentType.MANGA:
          await this.loadMangaContent();
          break;
        case UnifiedContentType.EBOOK:
          await this.loadEBookContent();
          break;
        case UnifiedContentType.NOVEL:
          await this.loadNovelContent();
          break;
        default:
          this.errorMessage = '未知的内容类型';
      }

      // 检查SFW模式
      if (this.content && this.content.isNSFW) {
        const sfwEnabled = ContentFilterManager.getInstance().isSFWModeEnabled();
        if (sfwEnabled) {
          logger.warn(TAG, 'SFW模式已启用，阻止访问NSFW内容');
          promptAction.showToast({
            message: 'SFW模式已启用，无法查看此内容',
            duration: 2000
          });
          this.pathStack.pop();
          return;
        }
      }

    } catch (error) {
      logger.error(TAG, '加载内容失败', String(error));
      this.errorMessage = '加载失败，请重试';
    } finally {
      this.isLoading = false;
    }
  }

  /**
   * 加载漫画内容（使用MangaDetailLoader分阶段加载）
   */
  private async loadMangaContent(): Promise<void> {
    if (!this.pageParams) return;

    const mangaId = this.pageParams.contentId;
    const sourceId = this.pageParams.sourceId;
    logger.info(TAG, `加载漫画内容: mangaId=${mangaId}, sourceId=${sourceId}`);

    // 重置加载状态
    this.isBasicInfoLoaded = false;
    this.isCoverLoading = true;
    this.isChaptersLoading = true;
    this.isPagesPreloading = false;
    this.chaptersLoadProgress = '';

    // 设置WebView控制器
    this.mangaDetailLoader.setWebViewController(this.webViewController);

    // 构建加载参数
    const loadParams: MangaDetailLoadParams = {
      mangaId: mangaId,
      sourceId: sourceId ? Number(sourceId) : undefined,
      cachedTitle: this.pageParams.cachedTitle,
      cachedCover: this.pageParams.cachedCover,
      forceRefresh: false
    };

    // 构建已读/已下载/书签章节ID集合
    const readChapterIds = new Set<string>();
    const downloadedChapterIds = new Set<string>();
    const bookmarkedChapterIds = new Set<string>();
    let lastReadChapterIndex = -1;

    // 分阶段加载回调
    const progressCallback: MangaLoadProgressCallback = {
      onBasicInfoLoaded: (manga: Manga, isFavorite: boolean) => {
        logger.info(TAG, `[分阶段] 基本信息已加载: ${manga.title}`);
        this.isFavorite = isFavorite;
        this.isBasicInfoLoaded = true;
        this.isLoading = false;  // 基本信息加载完成，停止主加载动画
        
        // 先显示基本信息（无章节）
        this.content = MangaAdapter.toUnifiedContent(
          manga,
          [],  // 章节稍后加载
          isFavorite,
          readChapterIds,
          downloadedChapterIds,
          bookmarkedChapterIds,
          lastReadChapterIndex,
          sourceId
        );
        
        // 封面加载完成
        this.isCoverLoading = false;
      },
      
      onChaptersLoaded: async (chapters: MangaChapter[]) => {
        logger.info(TAG, `[分阶段] 章节已加载: ${chapters.length}章`);
        this.isChaptersLoading = false;
        
        // 标记已下载章节
        chapters.forEach((ch: MangaChapter) => {
          if (ch.isDownloaded) {
            downloadedChapterIds.add(ch.id);
          }
        });
        
        // 加载章节进度数据
        const isOnline = sourceId !== undefined && Number(sourceId) > 0;
        const progressData = await this.mangaDetailLoader.loadChapterProgressData(
          mangaId, 
          chapters, 
          isOnline
        );
        
        // 更新已读章节ID集合和最后阅读章节索引
        progressData.readChapterIds.forEach(id => readChapterIds.add(id));
        lastReadChapterIndex = progressData.lastReadChapterIndex;
        
        // 保存章节进度到Map中（用于UI显示）
        const newProgressMap = new Map<string, ChapterProgressInfo>();
        progressData.progressList.forEach((progress: ChapterProgressInfo) => {
          newProgressMap.set(progress.chapterId, progress);
        });
        this.chapterProgressMap = newProgressMap;
        
        // 更新内容，添加章节
        if (this.content) {
          // 获取原始Manga对象以保留genres等元数据
          const originalManga = MangaAdapter.getOriginalManga(this.content);
          
          const updatedManga: Manga = {
            id: this.content.id,
            title: this.content.title,
            alternativeTitles: originalManga?.alternativeTitles || [],
            description: this.content.description,
            coverImagePath: this.content.coverUrl,
            coverSourceType: this.content.isLocal ? ImageSourceType.LOCAL : ImageSourceType.NETWORK,
            status: originalManga?.status || MangaStatus.UNKNOWN,
            metadata: {
              authors: this.content.author ? [this.content.author] : [],
              artists: originalManga?.metadata?.artists || [],
              genres: this.content.genres || originalManga?.metadata?.genres || [],
              themes: this.content.tags || originalManga?.metadata?.themes || [],
              demographics: originalManga?.metadata?.demographics || []
            },
            chapters: chapters,
            readingProgress: {
              currentChapterId: lastReadChapterIndex >= 0 && chapters[lastReadChapterIndex] ? chapters[lastReadChapterIndex].id : '',
              currentPageIndex: lastReadChapterIndex >= 0 && progressData.progressList[lastReadChapterIndex] ? progressData.progressList[lastReadChapterIndex].lastReadPageIndex : 0,
              lastReadAt: Date.now(),
              readingStatus: readChapterIds.size > 0 ? ReadingStatus.READING : ReadingStatus.UNREAD,
              totalReadingTime: 0,
              readingPercentage: chapters.length > 0 ? Math.round((readChapterIds.size / chapters.length) * 100) : 0
            },
            bookmarks: originalManga?.bookmarks || [],
            readingSettings: originalManga?.readingSettings || DEFAULT_READING_SETTINGS,
            isFavorite: this.isFavorite,
            lastUpdatedAt: Date.now(),
            isNSFW: this.content.isNSFW || false,
            sourceInfo: originalManga?.sourceInfo
          };
          
          this.content = MangaAdapter.toUnifiedContent(
            updatedManga,
            chapters,
            this.isFavorite,
            readChapterIds,
            downloadedChapterIds,
            bookmarkedChapterIds,
            lastReadChapterIndex,
            sourceId
          );
          
          logger.info(TAG, `章节进度已更新: 已读${readChapterIds.size}章, 最后阅读章节=${lastReadChapterIndex}`);
        }
      },
      
      onChapterPagesLoaded: (chapterId: string, pageCount: number) => {
        logger.debug(TAG, `[分阶段] 章节页面已加载: ${chapterId}, ${pageCount}页`);
        // 可以在这里更新章节的页数显示
      },
      
      onPagesPreloadProgress: (current: number, total: number) => {
        this.isPagesPreloading = true;
        this.chaptersLoadProgress = `预加载页面 ${current}/${total}`;
        logger.debug(TAG, `[分阶段] 页面预加载进度: ${current}/${total}`);
      },
      
      onPagesPreloadComplete: () => {
        this.isPagesPreloading = false;
        this.chaptersLoadProgress = '';
        logger.info(TAG, `[分阶段] 页面预加载完成`);
      },
      
      onError: (error: string) => {
        logger.error(TAG, `[分阶段] 加载错误: ${error}`);
        this.errorMessage = error;
        this.isLoading = false;
        this.isChaptersLoading = false;
        this.isCoverLoading = false;
      }
    };

    // 使用分阶段加载
    const result = await this.mangaDetailLoader.loadMangaDetailWithProgress(loadParams, progressCallback);

    if (!result.success) {
      logger.error(TAG, `漫画加载失败: ${result.errorMessage}`);
      if (!this.isBasicInfoLoaded) {
        this.errorMessage = result.errorMessage || '漫画加载失败';
      }
    } else {
      logger.info(TAG, `漫画内容加载完成: ${this.content?.title}`);
    }
  }

  /**
   * 下拉刷新处理
   */
  private async onRefresh(): Promise<void> {
    if (!this.content || !this.pageParams) {
      this.isRefreshing = false;
      return;
    }
    
    logger.info(TAG, `开始刷新: ${this.content.contentType}`);
    this.isRefreshing = true;
    this.refreshProgress = '正在刷新...';
    
    try {
      switch (this.content.contentType) {
        case UnifiedContentType.MANGA:
          await this.refreshMangaContent();
          break;
        case UnifiedContentType.NOVEL:
          await this.refreshNovelContent();
          break;
        case UnifiedContentType.EBOOK:
          // 电子书是本地文件，不需要刷新
          this.refreshProgress = '电子书无需刷新';
          break;
      }
      
      this.refreshProgress = '刷新完成';
      logger.info(TAG, '刷新完成');
    } catch (error) {
      logger.error(TAG, `刷新失败: ${String(error)}`);
      this.refreshProgress = '刷新失败';
    } finally {
      // 延迟关闭刷新状态，让用户看到结果
      setTimeout(() => {
        this.isRefreshing = false;
        this.refreshProgress = '';
      }, 500);
    }
  }
  
  /**
   * 刷新漫画内容（增量更新）
   */
  private async refreshMangaContent(): Promise<void> {
    if (!this.pageParams || !this.content) return;
    
    const mangaId = this.pageParams.contentId;
    const sourceId = this.pageParams.sourceId;
    
    // 只有在线漫画才需要刷新
    if (!sourceId || Number(sourceId) <= 0) {
      this.refreshProgress = '本地漫画无需刷新';
      return;
    }
    
    this.refreshProgress = '获取最新章节...';
    
    // 设置WebView控制器
    this.mangaDetailLoader.setWebViewController(this.webViewController);
    
    // 构建加载参数，强制刷新
    const loadParams: MangaDetailLoadParams = {
      mangaId: mangaId,
      sourceId: Number(sourceId),
      forceRefresh: true
    };
    
    // 保存当前内容用于增量更新
    const currentChapterCount = this.content.chapters.length;
    const currentChapterIds = new Set(this.content.chapters.map(ch => ch.id));
    
    // 使用分阶段加载刷新
    const progressCallback: MangaLoadProgressCallback = {
      onBasicInfoLoaded: (manga: Manga, isFavorite: boolean) => {
        this.refreshProgress = '更新基本信息...';
        // 增量更新：只更新有变化的字段
        if (this.content && manga.description && manga.description !== this.content.description) {
          // 更新描述等基本信息
          logger.info(TAG, '更新漫画描述');
        }
      },
      
      onChaptersLoaded: (chapters: MangaChapter[]) => {
        const newChapterCount = chapters.length;
        const addedCount = newChapterCount - currentChapterCount;
        
        if (addedCount > 0) {
          this.refreshProgress = `发现 ${addedCount} 个新章节`;
          logger.info(TAG, `刷新发现 ${addedCount} 个新章节`);
        } else {
          this.refreshProgress = '已是最新';
        }
        
        // 更新章节列表
        if (this.content) {
          const readChapterIds = new Set<string>();
          const downloadedChapterIds = new Set<string>();
          const bookmarkedChapterIds = new Set<string>();
          
          // 保留已有的阅读/下载/书签状态
          this.content.chapters.forEach(ch => {
            if (ch.isRead) readChapterIds.add(ch.id);
            if (ch.isDownloaded) downloadedChapterIds.add(ch.id);
            if (ch.isBookmarked) bookmarkedChapterIds.add(ch.id);
          });
          
          // 获取原始Manga对象并更新章节
          const originalManga = MangaAdapter.getOriginalManga(this.content);
          if (originalManga) {
            originalManga.chapters = chapters;
            
            this.content = MangaAdapter.toUnifiedContent(
              originalManga,
              chapters,
              this.isFavorite,
              readChapterIds,
              downloadedChapterIds,
              bookmarkedChapterIds,
              this.content.lastReadChapterIndex,
              this.pageParams?.sourceId
            );
          }
        }
      },
      
      onError: (error: string) => {
        this.refreshProgress = `刷新失败: ${error}`;
        logger.error(TAG, `刷新漫画失败: ${error}`);
      }
    };
    
    await this.mangaDetailLoader.loadMangaDetailWithProgress(loadParams, progressCallback);
  }
  
  /**
   * 刷新小说内容（增量更新）
   */
  private async refreshNovelContent(): Promise<void> {
    if (!this.pageParams || !this.content) return;
    
    const sourceId = this.pageParams.sourceId || '';
    const bookUrl = this.pageParams.contentId;
    
    if (!sourceId) {
      this.refreshProgress = '缺少图源信息';
      return;
    }
    
    this.refreshProgress = '获取最新章节...';
    
    try {
      // 获取原始小说数据
      const originalBook = NovelAdapter.getOriginalNovel(this.content);
      if (!originalBook) {
        this.refreshProgress = '无法获取小说数据';
        return;
      }
      
      // 从网络获取最新章节列表（需要传递LegadoBook对象）
      const chapters = await this.novelSourceManager.getChapterList(sourceId, originalBook);
      
      if (!chapters || chapters.length === 0) {
        this.refreshProgress = '获取章节失败';
        return;
      }
      
      const currentChapterCount = this.content.chapters.length;
      const newChapterCount = chapters.length;
      const addedCount = newChapterCount - currentChapterCount;
      
      if (addedCount > 0) {
        this.refreshProgress = `发现 ${addedCount} 个新章节`;
        logger.info(TAG, `刷新发现 ${addedCount} 个新章节`);
      } else {
        this.refreshProgress = '已是最新';
      }
      
      // 获取缓存状态
      const cachedIndexes = new Set<number>();
      for (let i = 0; i < chapters.length; i++) {
        const isCached = await this.novelCacheManager.isChapterCached(bookUrl, i);
        if (isCached) {
          cachedIndexes.add(i);
        }
      }
      
      // 更新内容
      this.content = NovelAdapter.toUnifiedContent(
        originalBook,
        chapters,
        this.isFavorite,
        cachedIndexes,
        this.content.lastReadChapterIndex,
        sourceId
      );
    } catch (error) {
      this.refreshProgress = `刷新失败: ${String(error)}`;
      logger.error(TAG, `刷新小说失败: ${String(error)}`);
    }
  }

  /**
   * 加载电子书内容
   */
  private async loadEBookContent(): Promise<void> {
    if (!this.pageParams) return;

    const bookId = this.pageParams.contentId;
    logger.info(TAG, `加载电子书内容: ${bookId}`);

    // 获取电子书数据
    const ebook = await this.ebookDataManager.getEBookById(bookId);
    if (!ebook) {
      this.errorMessage = '电子书不存在';
      logger.error(TAG, `电子书不存在: ${bookId}`);
      return;
    }

    logger.info(TAG, `电子书加载成功: ${ebook.metadata?.title}, 章节数: ${ebook.chapters?.length || 0}`);

    // 检查收藏状态
    this.isFavorite = ebook.isFavorite || false;

    // 转换为统一模型
    this.content = EBookAdapter.toUnifiedContent(ebook, this.isFavorite);
    logger.info(TAG, `统一模型转换完成: 章节数=${this.content.totalChapters}`);
  }

  /**
   * 加载小说内容
   */
  private async loadNovelContent(): Promise<void> {
    if (!this.pageParams) return;

    const sourceId = this.pageParams.sourceId || '';
    const bookUrl = this.pageParams.contentId;

    // 优先从数据库获取书籍信息
    let bookInDb = await this.novelDataManager.getBookByUrl(sourceId, bookUrl);
    let book: LegadoBook | null = null;
    let chapters: LegadoChapter[] = [];

    if (bookInDb) {
      // 数据库中有书籍信息，尝试从缓存获取章节
      logger.info(TAG, `从数据库加载小说: ${bookInDb.name}`);
      
      // 使用缓存的书籍信息构建LegadoBook
      book = {
        bookUrl: bookInDb.bookUrl,
        name: bookInDb.name,
        author: bookInDb.author,
        kind: bookInDb.kind,
        intro: bookInDb.intro,
        coverUrl: bookInDb.coverUrl,
        tocUrl: bookInDb.tocUrl,
        latestChapterTitle: bookInDb.latestChapterTitle,
        wordCount: bookInDb.wordCount
      } as LegadoBook;

      // 尝试从网络获取章节列表（如果失败则使用空列表）
      try {
        chapters = await this.novelSourceManager.getChapterList(sourceId, book);
      } catch (error) {
        logger.warn(TAG, `获取章节列表失败，使用缓存数据: ${String(error)}`);
        chapters = [];
      }
    } else {
      // 数据库中没有，从网络获取
      logger.info(TAG, `从网络加载小说: ${bookUrl}`);
      book = await this.novelSourceManager.getBookInfo(sourceId, bookUrl);
      if (!book) {
        this.errorMessage = '小说不存在';
        return;
      }

      // 获取章节列表
      try {
        chapters = await this.novelSourceManager.getChapterList(sourceId, book);
      } catch (error) {
        logger.warn(TAG, `获取章节列表失败: ${String(error)}`);
        chapters = [];
      }

      // 保存小说信息到数据库（持久化缓存）
      try {
        const novelBook: NovelBook = {
          id: `${sourceId}_${book.bookUrl}`,
          sourceId: sourceId,
          sourceName: '',
          bookUrl: book.bookUrl,
          name: book.name || '未知书名',
          author: book.author || '未知作者',
          kind: book.kind,
          intro: book.intro,
          coverUrl: book.coverUrl,
          tocUrl: book.tocUrl,
          latestChapterTitle: book.latestChapterTitle,
          wordCount: book.wordCount,
          chapterCount: chapters.length,
          readStatus: NovelReadStatus.UNREAD,
          totalReadingTime: 0,
          isFavorite: false,
          createTime: Date.now(),
          updateDbTime: Date.now()
        };
        await this.novelDataManager.saveBook(novelBook);
        logger.info(TAG, `小说信息已保存到数据库: ${book.name}`);
        // 更新bookInDb引用
        bookInDb = novelBook;
      } catch (error) {
        logger.warn(TAG, `保存小说信息失败: ${String(error)}`);
      }
    }

    // 获取缓存状态（使用bookUrl作为bookId）
    const cachedIndexes = new Set<number>();
    for (let i = 0; i < chapters.length; i++) {
      const isCached = await this.novelCacheManager.isChapterCached(bookUrl, i);
      if (isCached) {
        cachedIndexes.add(i);
      }
    }

    // 获取阅读进度（使用之前已查询的bookInDb）
    const lastReadIndex = bookInDb?.lastReadChapterIndex || -1;

    // 检查收藏状态
    this.isFavorite = bookInDb?.isFavorite || false;

    // 转换为统一模型
    this.content = NovelAdapter.toUnifiedContent(
      book,
      chapters,
      this.isFavorite,
      cachedIndexes,
      lastReadIndex,
      sourceId
    );
  }

  /**
   * 开始阅读
   */
  private startReading(chapterIndex: number): void {
    if (!this.content || !this.pageParams) return;

    const chapter = this.content.chapters[chapterIndex];
    if (!chapter) return;

    switch (this.content.contentType) {
      case UnifiedContentType.MANGA:
        this.openMangaReader(chapterIndex);
        break;
      case UnifiedContentType.EBOOK:
        this.openEBookReader(chapterIndex);
        break;
      case UnifiedContentType.NOVEL:
        this.openNovelReader(chapterIndex);
        break;
    }
  }

  /**
   * 继续阅读
   */
  private continueReading(): void {
    if (!this.content) return;

    // 电子书特殊处理：直接打开阅读器，不依赖章节列表
    if (this.content.contentType === UnifiedContentType.EBOOK) {
      this.openEBookReader(0);
      return;
    }

    const lastIndex = this.content.lastReadChapterIndex;
    if (lastIndex >= 0 && lastIndex < this.content.chapters.length) {
      this.startReading(lastIndex);
    } else {
      // 从第一章开始
      this.startReading(0);
    }
  }

  /**
   * 打开漫画阅读器
   */
  private openMangaReader(chapterIndex: number): void {
    if (!this.content) return;

    const chapter = this.content.chapters[chapterIndex];
    
    // 获取原始Manga对象
    const originalManga = MangaAdapter.getOriginalManga(this.content);
    
    // 构建阅读器参数（参考MangaDetailPage的实现）
    const readerParams: MangaReaderPageParams = {
      fromPage: 'UnifiedDetailPage'
    } as MangaReaderPageParams;
    
    // 判断是否为在线漫画
    const hasSourceId = this.content.sourceId && Number(this.content.sourceId) > 0;
    
    if (hasSourceId && originalManga) {
      // 在线漫画：传递完整的manga对象和sourceId
      readerParams.manga = originalManga;
      readerParams.sourceId = Number(this.content.sourceId);
      readerParams.mangaId = this.content.id;
      readerParams.sourceName = this.content.sourceName || '';
      
      // 判断章节是否已下载
      const isDownloaded = chapter.isDownloaded || false;
      readerParams.contentType = isDownloaded ? MangaReaderContentType.OnlineDownloaded : MangaReaderContentType.OnlineUndownloaded;
      
      // 对于WebView图源，需要传递外部章节ID
      const originalChapter = originalManga.chapters.find(ch => ch.id === chapter.id);
      if (originalChapter?.externalId) {
        readerParams.chapterId = originalChapter.externalId;
        logger.info(TAG, `转换章节ID: 内部ID=${chapter.id} -> 外部ID=${originalChapter.externalId}`);
      } else {
        readerParams.chapterId = chapter.id;
      }
      
      logger.info(TAG, `在线漫画阅读: sourceId=${readerParams.sourceId}, mangaId=${readerParams.mangaId}, chapterId=${readerParams.chapterId}`);
    } else {
      // 本地漫画：不传递manga对象，让MangaReaderPage从数据库加载完整的章节和页面信息
      readerParams.mangaId = this.content.id;
      readerParams.chapterId = chapter.id;
      readerParams.contentType = MangaReaderContentType.Local;
      readerParams.sourceName = 'LOCAL';
      // 注意：不传递manga对象，因为传递的manga对象中章节的pages数组可能为空
      // MangaReaderPage会通过mangaId从数据库加载完整的章节和页面信息
      logger.info(TAG, `本地漫画阅读: mangaId=${readerParams.mangaId}, chapterId=${readerParams.chapterId}`);
    }
    
    readerParams.pageIndex = 0;

    this.pathStack.pushPathByName('MangaReaderPage', readerParams);
  }

  /**
   * 打开电子书阅读器
   */
  private openEBookReader(chapterIndex: number): void {
    if (!this.content) return;

    // EBookReaderParams只需要bookId，章节索引通过阅读进度恢复
    const params: EBookReaderParams = {
      bookId: this.content.id
    };

    this.pathStack.pushPathByName('EBookReaderPage', params);
  }

  /**
   * 打开小说阅读器
   */
  private openNovelReader(chapterIndex: number): void {
    if (!this.content) return;

    const chapter = this.content.chapters[chapterIndex];
    if (!chapter) return;

    // 获取原始小说章节数据
    const originalChapter = NovelAdapter.getOriginalChapter(chapter);
    const originalBook = NovelAdapter.getOriginalNovel(this.content);

    const params: NovelReaderPageParams = {
      sourceId: this.content.sourceId || '',
      bookUrl: this.content.id,
      bookName: this.content.title,
      chapterUrl: originalChapter?.url || '',
      chapterTitle: chapter.title,
      chapterIndex: chapterIndex,
      totalChapters: this.content.totalChapters,
      tocUrl: originalBook?.tocUrl,
      author: this.content.author,
      coverUrl: this.content.coverUrl
    };

    this.pathStack.pushPathByName('NovelReaderPage', params);
  }

  /**
   * 切换收藏状态
   */
  private async toggleFavorite(): Promise<void> {
    if (!this.content) return;

    try {
      this.isFavorite = !this.isFavorite;

      switch (this.content.contentType) {
        case UnifiedContentType.MANGA:
          // 漫画收藏通过DataService处理
          const dataService = DataService.getInstance();
          if (this.isFavorite) {
            await dataService.addToFavorites(this.content.id);
          } else {
            await dataService.removeFromFavorites(this.content.id);
          }
          logger.info(TAG, `漫画收藏状态切换: ${this.isFavorite}`);
          break;
        case UnifiedContentType.EBOOK:
          // 电子书收藏需要重新保存整个对象
          const ebook = EBookAdapter.getOriginalEBook(this.content);
          if (ebook) {
            ebook.isFavorite = this.isFavorite;
            await this.ebookDataManager.saveEBook(ebook);
          }
          break;
        case UnifiedContentType.NOVEL:
          // 小说收藏通过saveBook更新isFavorite字段
          const novelBook = await this.novelDataManager.getBookByUrl(this.content.sourceId || '', this.content.id);
          if (novelBook) {
            novelBook.isFavorite = this.isFavorite;
            await this.novelDataManager.saveBook(novelBook);
          } else if (this.isFavorite) {
            // 如果书籍不存在且要收藏，需要先创建
            const now = Date.now();
            const newBook: NovelBook = {
              id: '',
              sourceId: this.content.sourceId || '',
              sourceName: this.content.sourceName || '',
              bookUrl: this.content.id,
              name: this.content.title,
              author: this.content.author,
              intro: this.content.description,
              coverUrl: this.content.coverUrl,
              chapterCount: this.content.totalChapters,
              readStatus: NovelReadStatus.UNREAD,
              totalReadingTime: 0,
              isFavorite: true,
              createTime: now,
              updateDbTime: now
            };
            await this.novelDataManager.saveBook(newBook);
          }
          break;
      }

      promptAction.showToast({
        message: this.isFavorite ? '已添加到收藏' : '已取消收藏',
        duration: 1500
      });
    } catch (error) {
      logger.error(TAG, '切换收藏状态失败', String(error));
      this.isFavorite = !this.isFavorite; // 回滚
      promptAction.showToast({
        message: '操作失败',
        duration: 1500
      });
    }
  }

  /**
   * 获取过滤后的章节列表
   */
  private getFilteredChapters(): UnifiedChapter[] {
    if (!this.content) return [];

    let chapters = [...this.content.chapters];

    // 应用过滤
    switch (this.chapterFilter) {
      case ChapterFilterType.UNREAD:
        chapters = chapters.filter(c => !c.isRead);
        break;
      case ChapterFilterType.DOWNLOADED:
        chapters = chapters.filter(c => c.isDownloaded);
        break;
      case ChapterFilterType.BOOKMARKED:
        chapters = chapters.filter(c => c.isBookmarked);
        break;
    }

    // 应用排序
    if (this.chapterSortOrder === ChapterSortOrder.DESCENDING) {
      chapters.reverse();
    }

    return chapters;
  }

  /**
   * 获取内容类型显示名称
   */
  private getContentTypeName(): string {
    if (!this.content) return '';
    switch (this.content.contentType) {
      case UnifiedContentType.MANGA:
        return '漫画';
      case UnifiedContentType.EBOOK:
        return '电子书';
      case UnifiedContentType.NOVEL:
        return '小说';
      default:
        return '';
    }
  }

  /**
   * 获取阅读状态显示文本
   */
  private getReadStatusText(): string {
    if (!this.content) return '';
    switch (this.content.readStatus) {
      case UnifiedReadStatus.UNREAD:
        return '未读';
      case UnifiedReadStatus.READING:
        return `阅读中 ${this.content.readProgress}%`;
      case UnifiedReadStatus.COMPLETED:
        return '已读完';
      default:
        return '';
    }
  }

  // ==================== UI构建 ====================

  /**
   * 获取封面图片路径（处理本地文件路径）
   */
  private getCoverImageSource(): string | Resource {
    const coverUrl = this.content?.coverUrl || '';
    if (!coverUrl) {
      return '';
    }
    
    // 如果是网络URL，直接返回
    if (coverUrl.startsWith('http://') || coverUrl.startsWith('https://')) {
      return coverUrl;
    }
    
    // 如果已经是file://开头，直接返回
    if (coverUrl.startsWith('file://')) {
      return coverUrl;
    }
    
    // 本地文件路径，添加file://前缀
    if (coverUrl.startsWith('/')) {
      return `file://${coverUrl}`;
    }
    
    return coverUrl;
  }

  @Builder
  buildHeader() {
    Row({ space: 16 }) {
      // 封面（支持AVIF格式）
      Stack() {
        if (this.content?.coverUrl) {
          AvifImage({
            src: this.getCoverImageSource() as string,
            imageWidth: COVER_WIDTH,
            imageHeight: COVER_HEIGHT,
            objectFit: ImageFit.Cover,
            imageBorderRadius: 8
          })
        } else {
          Column() {
            SymbolGlyph($r('sys.symbol.text_book_closed'))
              .fontSize(48)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
          }
          .width(COVER_WIDTH)
          .height(COVER_HEIGHT)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
          .borderRadius(8)
          .justifyContent(FlexAlign.Center)
        }

        // 内容类型标签
        Text(this.getContentTypeName())
          .fontSize(10)
          .fontColor(Color.White)
          .backgroundColor('rgba(0,0,0,0.6)')
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(4)
          .position({ x: 4, y: 4 })
      }
      .id(`cover_${this.componentId}`)

      // 信息区域
      Column({ space: 8 }) {
        Text(this.content?.title || '加载中...')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(this.content?.author || '')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

        Row({ space: 8 }) {
          Text(this.getReadStatusText())
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))

          Text(`${this.content?.totalChapters || 0}章`)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        }

        if (this.content?.sourceName) {
          Text(`来源: ${this.content.sourceName}`)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        }

        Blank()

        // 操作按钮
        Row({ space: 12 }) {
          Button((this.content?.lastReadChapterIndex ?? -1) >= 0 ? '继续阅读' : '开始阅读')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .fontColor(Color.White)
            .height(36)
            .layoutWeight(1)
            .onClick(() => this.continueReading())

          Button() {
            SymbolGlyph(this.isFavorite ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
              .fontSize(20)
              .fontColor([this.isFavorite 
                ? ThemeAwareHelper.getTestManagementThemedColor('color_error', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
          }
          .width(36)
          .height(36)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
          .borderRadius(18)
          .onClick(() => this.toggleFavorite())
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .height(COVER_HEIGHT)
    }
    .width('100%')
    .padding(16)
  }

  @Builder
  buildDescription() {
    Column({ space: 12 }) {
      // 标签区域
      if (this.content && ((this.content.genres && this.content.genres.length > 0) || (this.content.tags && this.content.tags.length > 0))) {
        Column({ space: 8 }) {
          Text('标签')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          
          Flex({ wrap: FlexWrap.Wrap }) {
            // 显示genres
            ForEach(this.content.genres || [], (genre: string) => {
              Text(genre)
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme))
                .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                .borderRadius(4)
                .margin({ right: 6, bottom: 6 })
            }, (genre: string, index: number) => `genre_${index}_${genre}`)
            
            // 显示tags
            ForEach(this.content.tags || [], (tag: string) => {
              Text(tag)
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme))
                .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                .borderRadius(4)
                .margin({ right: 6, bottom: 6 })
            }, (tag: string, index: number) => `tag_${index}_${tag}`)
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      
      // 简介区域
      Column({ space: 8 }) {
        Text('简介')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

        Text(this.content?.description || '暂无简介')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .maxLines(this.showFullDescription ? undefined : 3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .onClick(() => {
            this.showFullDescription = !this.showFullDescription;
          })

        if (this.content?.description && this.content.description.length > 100) {
          Text(this.showFullDescription ? '收起' : '展开')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .onClick(() => {
              this.showFullDescription = !this.showFullDescription;
            })
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
  }

  @Builder
  buildActionBar() {
    Row({ space: 12 }) {
      // 根据内容类型显示不同的设置入口
      if (this.content?.contentType === UnifiedContentType.MANGA) {
        Button() {
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.gearshape'))
              .fontSize(16)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
            Text('漫画设置')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          }
        }
        .height(36)
        .padding({ left: 16, right: 16 })
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
        .borderRadius(18)
        .onClick(() => this.openMangaSettings())
      } else if (this.content?.contentType === UnifiedContentType.EBOOK) {
        Button() {
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.gearshape'))
              .fontSize(16)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
            Text('电子书设置')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          }
        }
        .height(36)
        .padding({ left: 16, right: 16 })
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
        .borderRadius(18)
        .onClick(() => this.openEBookSettings())
      } else if (this.content?.contentType === UnifiedContentType.NOVEL) {
        Button() {
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.gearshape'))
              .fontSize(16)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
            Text('小说设置')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          }
        }
        .height(36)
        .padding({ left: 16, right: 16 })
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
        .borderRadius(18)
        .onClick(() => this.openNovelSettings())
      }

      Blank()

      // 下载按钮（仅漫画和小说显示）
      if (this.content?.contentType === UnifiedContentType.MANGA || this.content?.contentType === UnifiedContentType.NOVEL) {
        Button() {
          SymbolGlyph($r('sys.symbol.arrow_down_circle'))
            .fontSize(20)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
        }
        .width(36)
        .height(36)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
        .borderRadius(18)
        .onClick(() => this.showDownloadOptions())
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
  }

  /**
   * 打开漫画设置
   */
  private openMangaSettings(): void {
    if (!this.content || !this.pageParams) return;
    
    const params: MangaSettingsPageParams = {
      mangaId: this.content.id,
      fromPage: 'UnifiedDetailPage'
    };
    this.pathStack.pushPathByName('MangaSettingsPage', params);
  }

  /**
   * 打开电子书设置
   */
  private openEBookSettings(): void {
    if (!this.content || !this.pageParams) return;
    
    const params: EBookSettingsPageParams = {
      bookId: this.content.id
    };
    this.pathStack.pushPathByName('EBookSettingsPage', params);
  }

  /**
   * 打开小说设置（显示阅读设置弹窗）
   */
  private openNovelSettings(): void {
    if (!this.content || !this.pageParams) return;
    
    // 显示小说设置选项
    AlertDialog.show({
      title: '小说设置',
      message: '请选择要执行的操作',
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '进入阅读器设置',
        action: () => {
          // 跳转到阅读器，用户可以在阅读器中调整设置
          this.continueReading();
        }
      },
      secondaryButton: {
        value: '管理缓存',
        action: () => {
          this.showNovelCacheOptions();
        }
      }
    });
  }

  /**
   * 显示小说缓存选项
   */
  private showNovelCacheOptions(): void {
    AlertDialog.show({
      title: '缓存管理',
      message: '选择缓存操作',
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '缓存全部章节',
        action: () => {
          this.cacheAllNovelChapters();
        }
      },
      secondaryButton: {
        value: '清除缓存',
        action: () => {
          this.clearNovelCache();
        }
      }
    });
  }

  /**
   * 缓存全部小说章节
   */
  private async cacheAllNovelChapters(): Promise<void> {
    if (!this.content) return;
    promptAction.showToast({ message: '开始缓存章节...' });
    // TODO: 实现批量缓存逻辑
  }

  /**
   * 清除小说缓存
   */
  private async clearNovelCache(): Promise<void> {
    if (!this.content) return;
    promptAction.showToast({ message: '缓存已清除' });
    // TODO: 实现清除缓存逻辑
  }

  /**
   * 显示下载选项
   */
  private showDownloadOptions(): void {
    promptAction.showToast({ message: '下载功能开发中' });
  }

  @Builder
  buildChapterList() {
    // 电子书特殊处理：如果有章节则显示章节列表，否则显示阅读进度信息
    if (this.content?.contentType === UnifiedContentType.EBOOK && this.content.chapters.length === 0) {
      this.buildEBookProgressInfo()
    } else {
      Column({ space: 12 }) {
        // 章节列表头部
        Row() {
          Text(`章节列表 (${this.content?.totalChapters || 0})`)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

          Blank()

          // 排序按钮
          Button() {
            SymbolGlyph(this.chapterSortOrder === ChapterSortOrder.ASCENDING 
              ? $r('sys.symbol.arrow_up') 
              : $r('sys.symbol.arrow_down'))
              .fontSize(16)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
          }
          .width(32)
          .height(32)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.chapterSortOrder = this.chapterSortOrder === ChapterSortOrder.ASCENDING 
              ? ChapterSortOrder.DESCENDING 
              : ChapterSortOrder.ASCENDING;
          })
        }
        .width('100%')

        // 根据内容类型显示不同的章节列表
        if (this.content?.contentType === UnifiedContentType.MANGA) {
          this.buildMangaChapterList()
        } else if (this.content?.contentType === UnifiedContentType.NOVEL) {
          this.buildNovelChapterList()
        } else if (this.content?.contentType === UnifiedContentType.EBOOK) {
          this.buildEBookChapterList()
        }
      }
      .width('100%')
      .padding(16)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
      .borderRadius(12)
    }
  }
  
  /**
   * 电子书阅读进度信息（替代章节列表）
   */
  @Builder
  buildEBookProgressInfo() {
    Column({ space: 16 }) {
      Text('阅读信息')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
      
      // 阅读进度
      Column({ space: 8 }) {
        Row() {
          Text('阅读进度')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          Blank()
          Text(`${this.content?.readProgress || 0}%`)
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        }
        .width('100%')
        
        Progress({ value: this.content?.readProgress || 0, total: 100, type: ProgressType.Linear })
          .width('100%')
          .height(4)
          .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme))
      }
      
      // 当前章节
      if (this.content?.lastReadChapterTitle) {
        Row() {
          Text('当前章节')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          Blank()
          Text(this.content.lastReadChapterTitle)
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: '60%' })
        }
        .width('100%')
      }
      
      // 文件信息
      Row() {
        Text('文件格式')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        Blank()
        Text(this.getEBookFormat())
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
  }
  
  /**
   * 获取电子书格式
   */
  private getEBookFormat(): string {
    if (!this.content) return '未知';
    const originalEBook = EBookAdapter.getOriginalEBook(this.content);
    if (originalEBook) {
      return originalEBook.format.toUpperCase();
    }
    return '未知';
  }

  /**
   * 漫画章节列表（显示图片数量、阅读进度、更新时间等）
   */
  @Builder
  buildMangaChapterList() {
    List() {
      ForEach(this.getFilteredChapters(), (chapter: UnifiedChapter) => {
        ListItem() {
          Row({ space: 12 }) {
            // 左侧：已读指示器
            Column() {
              if (chapter.isRead) {
                Circle()
                  .width(8)
                  .height(8)
                  .fill(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
              } else {
                Circle()
                  .width(8)
                  .height(8)
                  .fill(Color.Transparent)
                  .stroke(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                  .strokeWidth(1)
              }
            }
            .width(20)
            .justifyContent(FlexAlign.Center)

            // 中间：章节信息
            Column({ space: 4 }) {
              Text(chapter.title)
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontWeight(chapter.isRead ? FontWeight.Normal : FontWeight.Medium)
                .fontColor(chapter.isRead 
                  ? ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)
                  : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })

              Row({ space: 12 }) {
                // 章节进度信息（从chapterProgressMap获取）
                Text(this.getChapterProgressText(chapter.id))
                  .fontSize(11)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                
                // 更新时间
                if (chapter.publishDate) {
                  Text(this.formatDate(chapter.publishDate))
                    .fontSize(11)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                }
              }
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            // 右侧：状态图标
            Row({ space: 6 }) {
              if (chapter.isDownloaded) {
                SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
                  .fontSize(16)
                  .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme)])
              }
              if (chapter.isBookmarked) {
                SymbolGlyph($r('sys.symbol.bookmark_fill'))
                  .fontSize(16)
                  .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme)])
              }
            }
          }
          .width('100%')
          .padding({ top: 12, bottom: 12 })
          .onClick(() => this.startReading(chapter.index))
        }
      }, (chapter: UnifiedChapter) => chapter.id)
    }
    .width('100%')
    .height(350)
    .scrollBar(BarState.Off)
    .divider({ strokeWidth: 0.5, color: ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme) })
  }

  /**
   * 小说章节列表（更直观的已读/未读状态）
   */
  @Builder
  buildNovelChapterList() {
    List() {
      ForEach(this.getFilteredChapters(), (chapter: UnifiedChapter) => {
        ListItem() {
          Row({ space: 12 }) {
            // 左侧：章节序号和已读状态
            Column() {
              Text(`${chapter.index + 1}`)
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(chapter.isRead 
                  ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
                  : ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                .fontWeight(chapter.isRead ? FontWeight.Bold : FontWeight.Normal)
            }
            .width(36)
            .height(36)
            .borderRadius(18)
            .backgroundColor(chapter.isRead 
              ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme) + '20'
              : ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
            .justifyContent(FlexAlign.Center)

            // 中间：章节标题
            Column({ space: 2 }) {
              Text(chapter.title)
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontWeight(chapter.isRead ? FontWeight.Normal : FontWeight.Medium)
                .fontColor(chapter.isRead 
                  ? ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)
                  : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })

              // 字数和缓存状态
              Row({ space: 8 }) {
                if (chapter.wordCount) {
                  Text(`${chapter.wordCount}字`)
                    .fontSize(11)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                }
                if (chapter.isDownloaded) {
                  Row({ space: 2 }) {
                    SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
                      .fontSize(10)
                      .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme)])
                    Text('已缓存')
                      .fontSize(10)
                      .fontFamily(this.appFontFamily)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
                  }
                }
              }
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            // 右侧：阅读状态标签
            if (chapter.isRead) {
              Text('已读')
                .fontSize(10)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
                .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme) + '15')
                .borderRadius(10)
            } else if (chapter.index === this.content?.lastReadChapterIndex) {
              Text('阅读中')
                .fontSize(10)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '15')
                .borderRadius(10)
            }
          }
          .width('100%')
          .padding({ top: 10, bottom: 10 })
          .onClick(() => this.startReading(chapter.index))
        }
      }, (chapter: UnifiedChapter) => chapter.id)
    }
    .width('100%')
    .height(350)
    .scrollBar(BarState.Off)
  }

  /**
   * 电子书章节列表
   */
  @Builder
  buildEBookChapterList() {
    List() {
      ForEach(this.getFilteredChapters(), (chapter: UnifiedChapter) => {
        ListItem() {
          Row({ space: 12 }) {
            // 左侧：章节信息
            Column({ space: 4 }) {
              // 章节标题
              Text(chapter.title)
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontWeight(chapter.isRead ? FontWeight.Normal : FontWeight.Medium)
                .fontColor(chapter.isRead 
                  ? ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)
                  : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })

              // 字数信息
              if (chapter.wordCount && chapter.wordCount > 0) {
                Text(`${chapter.wordCount}字`)
                  .fontSize(11)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              }
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            // 右侧：阅读状态标签
            if (chapter.isRead) {
              Text('已读')
                .fontSize(10)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
                .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme) + '15')
                .borderRadius(10)
            } else if (chapter.index === this.content?.lastReadChapterIndex) {
              Text('阅读中')
                .fontSize(10)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '15')
                .borderRadius(10)
            }
          }
          .width('100%')
          .padding({ top: 12, bottom: 12 })
          .onClick(() => this.startReading(chapter.index))
        }
      }, (chapter: UnifiedChapter) => chapter.id)
    }
    .width('100%')
    .height(350)
    .scrollBar(BarState.Off)
    .divider({ strokeWidth: 0.5, color: ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme) })
  }

  /**
   * 格式化日期（支持时间戳和ISO字符串）
   */
  private formatDate(dateValue: string | number | undefined): string {
    if (!dateValue) return '';
    
    let timestamp: number;
    if (typeof dateValue === 'string') {
      // ISO字符串格式
      const parsed = Date.parse(dateValue);
      if (isNaN(parsed)) return '';
      timestamp = parsed;
    } else {
      timestamp = dateValue;
    }
    
    if (isNaN(timestamp) || timestamp <= 0) return '';
    
    const date = new Date(timestamp);
    const now = new Date();
    const diff = now.getTime() - date.getTime();
    const days = Math.floor(diff / (1000 * 60 * 60 * 24));
    
    if (days === 0) return '今天';
    if (days === 1) return '昨天';
    if (days < 7) return `${days}天前`;
    if (days < 30) return `${Math.floor(days / 7)}周前`;
    if (days < 365) return `${Math.floor(days / 30)}月前`;
    return `${date.getFullYear()}/${date.getMonth() + 1}/${date.getDate()}`;
  }
  
  /**
   * 获取章节进度显示文本
   */
  private getChapterProgressText(chapterId: string): string {
    const progress = this.chapterProgressMap.get(chapterId);
    if (!progress) {
      return '页数未知';
    }
    
    const total = progress.totalPages;
    if (total <= 0) {
      return '页数未知';
    }
    
    const current = progress.lastReadPageIndex >= 0 ? (progress.lastReadPageIndex + 1) : 0;
    if (current > 0) {
      return `共 ${total} 页 • 已读 ${current}/${total}`;
    }
    return `共 ${total} 页 • 未开始`;
  }

  @Builder
  buildLoadingView() {
    Column() {
      LoadingProgress()
        .width(48)
        .height(48)
        .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
      Text('加载中...')
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .margin({ top: 16 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  buildErrorView() {
    Column({ space: 16 }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
        .fontSize(48)
        .fontColor([ThemeAwareHelper.getTestManagementThemedColor('color_error', this.themeState.currentTheme)])

      Text(this.errorMessage)
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

      Button('重试')
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .onClick(() => this.loadContent())
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  build() {
    NavDestination() {
      Stack() {
        // 背景层：封面图片毛玻璃效果
        Stack() {
          // 默认背景色（防止闪烁）
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor(this.themeState.currentTheme === ThemeType.DARK ? '#1A1A1A' : '#F5F5F5')
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          
          // 封面图片作为背景（支持AVIF格式）
          if (this.content?.coverUrl) {
            AvifImage({
              src: this.getCoverImageSource() as string,
              imageWidth: '100%',
              imageHeight: '100%',
              objectFit: ImageFit.Cover
            })
              .blur(30)
              .opacity(0.5)
              .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
              .transition({ type: TransitionType.Insert, opacity: 0 })
              .animation({ duration: 300, curve: Curve.EaseOut })
          }
          // 渐变遮罩
          Column()
            .width('100%')
            .height('100%')
            .linearGradient({
              direction: GradientDirection.Bottom,
              colors: [
                [this.themeState.currentTheme === ThemeType.DARK ? 'rgba(26,26,26,0.2)' : 'rgba(245,245,245,0.2)', 0],
                [this.themeState.currentTheme === ThemeType.DARK ? 'rgba(26,26,26,0.7)' : 'rgba(245,245,245,0.7)', 0.3],
                [this.themeState.currentTheme === ThemeType.DARK ? '#1A1A1A' : '#F5F5F5', 0.6]
              ]
            })
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        }
        .width('100%')
        .height('100%')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        if (this.isLoading) {
          this.buildLoadingView()
        } else if (this.errorMessage) {
          this.buildErrorView()
        } else {
          Refresh({ refreshing: $$this.isRefreshing }) {
            Scroll(this.scroller) {
              Column({ space: 16 }) {
                // 刷新进度提示
                if (this.refreshProgress) {
                  Text(this.refreshProgress)
                    .fontSize(12)
                    .fontColor(this.themeState.currentTheme === ThemeType.DARK ? '#AAAAAA' : '#666666')
                    .padding({ top: 8, bottom: 8 })
                }
                
                this.buildHeader()
                this.buildDescription()
                this.buildActionBar()
                this.buildChapterList()

                Blank().height(40)
              }
              .width('100%')
              .constraintSize({ maxWidth: this.responsive_maxContentWidth })
              .padding({ left: this.responsive_contentPadding, right: this.responsive_contentPadding, bottom: 40 })
            }
            .width('100%')
            .height('100%')
            .align(Alignment.TopStart)
            .scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.Spring)
          }
          .onRefreshing(() => {
            this.onRefresh();
          })
          .width('100%')
          .height('100%')
        }
      }
    }
    .hideTitleBar(true)
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      const params = context.pathInfo?.param as UnifiedDetailPageParams;
      if (params) {
        this.pageParams = params;
        this.loadContent();
      }
    })
    .onShown(() => {
      // 页面显示时刷新阅读记录（从阅读器返回时）
      this.refreshReadingProgress();
    })
    .backgroundColor(Color.Transparent)
  }
  
  /**
   * 刷新阅读进度（页面返回时调用）
   */
  private async refreshReadingProgress(): Promise<void> {
    if (!this.content || !this.pageParams) return;
    
    try {
      logger.info(TAG, `刷新阅读进度: ${this.content.contentType}`);
      
      switch (this.content.contentType) {
        case UnifiedContentType.MANGA:
          await this.refreshMangaReadingProgress();
          break;
        case UnifiedContentType.EBOOK:
          await this.refreshEBookReadingProgress();
          break;
        case UnifiedContentType.NOVEL:
          await this.refreshNovelReadingProgress();
          break;
      }
    } catch (error) {
      logger.error(TAG, `刷新阅读进度失败: ${String(error)}`);
    }
  }
  
  /**
   * 刷新漫画阅读进度
   */
  private async refreshMangaReadingProgress(): Promise<void> {
    if (!this.content) return;
    
    const mangaId = this.content.id;
    const isOnline = this.content.sourceId !== undefined && Number(this.content.sourceId) > 0;
    const chapters = this.content.chapters.map(ch => {
      const originalChapter = MangaAdapter.getOriginalChapter(ch);
      return originalChapter as MangaChapter;
    }).filter(ch => ch !== null);
    
    if (chapters.length === 0) return;
    
    // 重新加载章节进度
    const progressData = await this.mangaDetailLoader.loadChapterProgressData(mangaId, chapters, isOnline);
    
    // 更新章节进度Map
    const newProgressMap = new Map<string, ChapterProgressInfo>();
    progressData.progressList.forEach((progress: ChapterProgressInfo) => {
      newProgressMap.set(progress.chapterId, progress);
    });
    this.chapterProgressMap = newProgressMap;
    
    // 更新章节已读状态
    const updatedChapters: UnifiedChapter[] = [];
    for (let i = 0; i < this.content.chapters.length; i++) {
      const ch = this.content.chapters[i];
      const isRead = progressData.readChapterIds.has(ch.id);
      const updatedChapter: UnifiedChapter = {
        id: ch.id,
        title: ch.title,
        index: ch.index,
        isRead: isRead,
        isDownloaded: ch.isDownloaded,
        isBookmarked: ch.isBookmarked,
        pageCount: ch.pageCount,
        publishDate: ch.publishDate,
        originalData: ch.originalData,
        originalType: ch.originalType
      };
      updatedChapters.push(updatedChapter);
    }
    
    // 更新content（显式赋值而不是spread）
    this.content.chapters = updatedChapters;
    this.content.readChapters = progressData.readChapterIds.size;
    this.content.lastReadChapterIndex = progressData.lastReadChapterIndex;
    this.content.readProgress = this.content.totalChapters > 0 
      ? Math.round((progressData.readChapterIds.size / this.content.totalChapters) * 100) 
      : 0;
    
    logger.info(TAG, `漫画阅读进度已刷新: 已读${progressData.readChapterIds.size}章`);
  }
  
  /**
   * 刷新电子书阅读进度
   */
  private async refreshEBookReadingProgress(): Promise<void> {
    if (!this.content) return;
    
    try {
      const ebook: EBook | null = await this.ebookDataManager.getEBookById(this.content.id);
      if (ebook) {
        const currentChapterIndex: number = ebook.readingProgress?.currentChapterIndex || 0;
        const progress: number = ebook.readingProgress?.progress || 0;
        
        this.content.lastReadChapterIndex = currentChapterIndex;
        this.content.lastReadChapterTitle = currentChapterIndex < (ebook.chapters?.length || 0) 
          ? ebook.chapters![currentChapterIndex].title 
          : '';
        // progress已经是0-100的百分比值，不需要再乘以100
        this.content.readProgress = Math.round(progress);
        
        logger.info(TAG, `电子书阅读进度已刷新: 章节${currentChapterIndex}, 进度${progress}%`);
      }
    } catch (error) {
      logger.error(TAG, `刷新电子书阅读进度失败: ${String(error)}`);
    }
  }
  
  /**
   * 刷新小说阅读进度
   */
  private async refreshNovelReadingProgress(): Promise<void> {
    if (!this.content) return;
    
    try {
      const novelBook: NovelBook | null = await this.novelDataManager.getBookByUrl(
        this.content.sourceId || '', 
        this.content.id
      );
      
      if (novelBook) {
        const lastChapterIndex: number = novelBook.lastReadChapterIndex || 0;
        const readChapters: number = novelBook.chapterCount || 0;
        
        this.content.lastReadChapterIndex = lastChapterIndex;
        this.content.readChapters = readChapters;
        this.content.readProgress = this.content.totalChapters > 0 
          ? Math.round((readChapters / this.content.totalChapters) * 100) 
          : 0;
        
        logger.info(TAG, `小说阅读进度已刷新: 章节${lastChapterIndex}, 已读${readChapters}章`);
      }
    } catch (error) {
      logger.error(TAG, `刷新小说阅读进度失败: ${String(error)}`);
    }
  }
}
