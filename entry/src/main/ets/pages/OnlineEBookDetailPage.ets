// 文件路径: entry/src/main/ets/pages/OnlineEBookDetailPage.ets
/**
 * 在线电子书详情页
 * 用于从图源详情页进入，显示在线电子书的详细信息
 * UI结构与EBookDetailPage类似，但功能逻辑不同
 */

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { logger } from '../Utils/Logger';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { ThemeType } from '../Framework/Managers/ThemeManager';
import { DeviceAdaptationManager, DeviceChangeListener, DeviceInfo } from '../Framework/Managers/DeviceAdaptationManager';
import { SourceManager, SourceInfo } from '../Framework/Source/SourceManager';
import { MangaSourceEngine, EngineConfig } from '../Framework/WebView/MangaSourceEngine';
import { AntiCrawlerConfig } from '../Framework/WebView/MangaSourceTypes';
import { ImageCacheManager } from '../Framework/Cache/ImageCacheManager';
import { DataManager } from '../Framework/Data/DataManager';
import { webview } from '@kit.ArkWeb';
import { http } from '@kit.NetworkKit';
import { image } from '@kit.ImageKit';
import {
  DownloadSource,
  FileFormat,
  StepStatus,
  DownloadButtonState
} from '../Framework/Components/EBookDownloadComponents';
import {
  MangaDownloadManager,
  TaskStatus,
  DownloadTaskInfo,
  DownloadTaskType
} from '../Framework/Download/DownloadManager';
import { promptAction } from '@kit.ArkUI';

const TAG = 'OnlineEBookDetailPage';
const TITLE_BAR_HEIGHT = 56;

/**
 * 下载源解析结果
 */
interface DownloadSourcesParseResult {
  sources: DownloadSource[];
  formSubmitted: boolean;
  error: string | null;
}

/**
 * 页面信息（用于验证和调试）
 */
interface PageInfo {
  url: string;
  title: string;
  hasError: boolean;
}

/**
 * 在线电子书详情页参数
 */
export interface OnlineEBookDetailPageParams {
  sourceId: number;
  bookId: string;
  cachedCoverPath?: string;
  cachedTitle?: string;
  cachedCover?: string;
}

/**
 * 在线电子书信息
 */
interface OnlineEBookInfo {
  id: string;
  title: string;
  cover: string;
  author: string;
  publisher: string;
  publishDate: string;
  description: string;
  categories: string;
  isbn: string;
  fileSize: string;
  downloadLinks: DownloadLink[];
}

interface DownloadLink {
  url: string;
  format: string;
}

@Component
export struct OnlineEBookDetailPage {
  @Consume('NavPathStack') pathStack: NavPathStack;
  @State themeState: ThemeAwareState = new ThemeAwareState();
  private componentId: string = 'OnlineEBookDetailPage';
  private scroller: Scroller = new Scroller();

  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;

  private sourceId: number = 0;
  private bookId: string = '';
  private cachedCoverPath: string = '';
  private cachedTitle: string = '';
  private cachedCover: string = '';

  @State sourceInfo: SourceInfo | null = null;
  @State bookInfo: OnlineEBookInfo | null = null;
  @State isLoading: boolean = true;
  @State errorMessage: string = '';
  @State expandedDescription: boolean = false;
  @State coverPixelMap: image.PixelMap | null = null;
  @State private isLandscape: boolean = false;

  private deviceOrientationListener: DeviceChangeListener | null = null;
  private deviceAdaptationManager: DeviceAdaptationManager = DeviceAdaptationManager.getInstance();
  private sourceManager: SourceManager = SourceManager.getInstance();
  private dataManager: DataManager = DataManager.getInstance();
  private mangaSourceEngine: MangaSourceEngine | null = null;
  private webViewController: webview.WebviewController = new webview.WebviewController();
  @State private webViewReady: boolean = false;

  // 下载组件状态
  private globalDownloadManager: MangaDownloadManager = MangaDownloadManager.getInstance();
  @State currentDownloadTask: DownloadTaskInfo | null = null;
  @State showSourceSelector: boolean = false;
  @State showFormatSelector: boolean = false;
  @State downloadSources: DownloadSource[] = [];
  @State selectedSourceId: string = '';
  @State fileFormats: FileFormat[] = [];
  @State selectedFormat: string = '';
  @State downloadButtonState: DownloadButtonState = DownloadButtonState.IDLE;
  @State downloadProgress: number = 0;
  @State downloadPhase: string = 'idle';

  aboutToAppear(): void {
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (theme: ThemeType) => {
      logger.info(TAG, `主题切换: ${theme}`);
    });
    this.updateDeviceOrientation();
    this.deviceOrientationListener = (deviceInfo: DeviceInfo) => {
      this.isLandscape = deviceInfo.isLandscape;
    };
    this.deviceAdaptationManager.addListener(this.deviceOrientationListener);
  }

  aboutToDisappear(): void {
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    if (this.deviceOrientationListener) {
      this.deviceAdaptationManager.removeListener(this.deviceOrientationListener);
      this.deviceOrientationListener = null;
    }
    if (this.coverPixelMap) {
      this.coverPixelMap.release();
      this.coverPixelMap = null;
    }
  }

  private updateDeviceOrientation(): void {
    const deviceInfo = this.deviceAdaptationManager.getDeviceInfo();
    this.isLandscape = deviceInfo.isLandscape;
  }

  private async initializePage(params: OnlineEBookDetailPageParams): Promise<void> {
    this.sourceId = params.sourceId;
    this.bookId = params.bookId;
    this.cachedCoverPath = params.cachedCoverPath || '';
    this.cachedTitle = params.cachedTitle || '';
    this.cachedCover = params.cachedCover || '';
    logger.info(TAG, `初始化在线电子书详情页: sourceId=${this.sourceId}, bookId=${this.bookId}`);
    await this.loadSourceInfo();
    if (this.cachedCoverPath || this.cachedCover) {
      this.loadCoverImage();
    }
    await this.loadBookDetail();
  }

  private async loadSourceInfo(): Promise<void> {
    try {
      const sources = await this.sourceManager.getAllSources();
      this.sourceInfo = sources.find((s: SourceInfo) => s.id === this.sourceId) || null;
      if (!this.sourceInfo) {
        throw new Error('图源不存在');
      }
      logger.info(TAG, `图源信息加载完成: ${this.sourceInfo.name}`);
    } catch (error) {
      logger.error(TAG, `加载图源信息失败: ${String(error)}`);
      this.errorMessage = '加载图源信息失败';
    }
  }

  private async loadCoverImage(): Promise<void> {
    try {
      const coverUrl = this.cachedCoverPath || this.cachedCover;
      if (!coverUrl) {
        return;
      }
      const imageCacheManager = ImageCacheManager.getInstance();
      const pixelMap = await imageCacheManager.loadImage(coverUrl, {});
      if (pixelMap) {
        this.coverPixelMap = pixelMap;
      }
    } catch (error) {
      logger.error(TAG, `加载封面失败: ${String(error)}`);
    }
  }

  private async loadBookDetail(): Promise<void> {
    logger.info(TAG, `加载电子书详情: ${this.bookId}`);
    
    // 先设置缓存的基本信息
    this.bookInfo = {
      id: this.bookId,
      title: this.cachedTitle || '未知书名',
      cover: this.cachedCover || '',
      author: '',
      publisher: '',
      publishDate: '',
      description: '',
      categories: '',
      isbn: '',
      fileSize: '',
      downloadLinks: []
    };
    
    try {
      // 初始化WebView引擎
      await this.initializeWebViewEngine();
      
      if (this.mangaSourceEngine && this.webViewReady) {
        // 使用WebView获取详情
        const result = await this.mangaSourceEngine.getBookDetail(this.bookId);
        
        if (result.success && result.data) {
          const detail = result.data;
          this.bookInfo = {
            id: this.bookId,
            title: String(detail['title'] || this.cachedTitle || '未知书名'),
            cover: String(detail['cover'] || this.cachedCover || ''),
            author: String(detail['author'] || ''),
            publisher: String(detail['publisher'] || ''),
            publishDate: String(detail['publishDate'] || ''),
            description: String(detail['description'] || ''),
            categories: String(detail['category'] || detail['categories'] || ''),
            isbn: String(detail['isbn'] || ''),
            fileSize: String(detail['fileSize'] || ''),
            downloadLinks: []
          };
          
          // 解析格式列表
          const formats = detail['formats'] as string[] | undefined;
          if (formats && Array.isArray(formats)) {
            this.bookInfo.downloadLinks = formats.map((format: string) => {
              const link: DownloadLink = {
                url: '',
                format: format
              };
              return link;
            });
          }
          
          logger.info(TAG, `电子书详情加载成功: ${this.bookInfo.title}`);
        } else {
          logger.warn(TAG, `获取电子书详情失败: ${result.error}`);
          this.bookInfo.description = '无法获取详细信息';
        }
      } else {
        logger.warn(TAG, 'WebView引擎未就绪，使用缓存数据');
        this.bookInfo.description = '详情加载中...';
      }
    } catch (error) {
      logger.error(TAG, `加载电子书详情失败: ${String(error)}`);
      this.bookInfo.description = '加载失败';
    }
    
    this.isLoading = false;
    logger.info(TAG, `电子书详情已设置: ${this.bookInfo.title}`);
  }

  private async initializeWebViewEngine(): Promise<void> {
    try {
      if (!this.sourceInfo) {
        logger.warn(TAG, '图源信息未加载');
        return;
      }
      
      // 获取图源配置（返回解析后的对象，需要重新序列化）
      const sourceConfig: Record<string, Object> | null = await this.dataManager.getSourceConfig(this.sourceId) as Record<string, Object> | null;
      if (!sourceConfig) {
        logger.warn(TAG, '无法获取图源配置');
        return;
      }
      
      // 将配置对象序列化为JSON字符串
      const configJson = JSON.stringify(sourceConfig);
      
      // 初始化WebView引擎
      const engineConfig: EngineConfig = {
        webViewController: this.webViewController,
        antiCrawlerConfig: {} as AntiCrawlerConfig,
        debug: false,
        timeout: 30000,
        caseSensitive: false,
        sourceId: this.sourceId
      };
      this.mangaSourceEngine = new MangaSourceEngine(engineConfig);
      
      const loadResult = await this.mangaSourceEngine.loadConfig(configJson);
      if (!loadResult.success) {
        logger.error(TAG, `加载图源配置失败: ${loadResult.error}`);
        return;
      }
      
      this.webViewReady = true;
      logger.info(TAG, 'WebView引擎初始化成功');
    } catch (error) {
      logger.error(TAG, `初始化WebView引擎失败: ${String(error)}`);
    }
  }

  private getCoverSource(): ResourceStr {
    if (this.cachedCoverPath && this.cachedCoverPath.length > 0) {
      return `file://${this.cachedCoverPath}`;
    }
    if (this.cachedCover && this.cachedCover.length > 0) {
      return this.cachedCover;
    }
    return $r('app.media.ebook');
  }

  private getBookTitle(): string {
    return this.bookInfo?.title || this.cachedTitle || '加载中...';
  }

  private downloadBook(link: DownloadLink): void {
    logger.info(TAG, `下载电子书: ${link.url} 格式: ${link.format}`);
  }

  private async startDownloadFlow(): Promise<void> {
    // TODO: 暂时封存下载功能，等待后续实现
    promptAction.showToast({ message: '电子书下载功能暂未实现', duration: 2000 });
    logger.info(TAG, `[封存] 下载功能暂未实现: bookId=${this.bookId}`);
    return;
    
    /* === 封存的下载逻辑开始 ===
    logger.info(TAG, `开始下载流程: bookId=${this.bookId}`);
    
    if (!this.mangaSourceEngine) {
      logger.error(TAG, '引擎未初始化');
      return;
    }

    // 检查是否已有下载任务
    const existingTask = this.globalDownloadManager.getEBookTask(this.bookId);
    if (existingTask) {
      this.currentDownloadTask = existingTask;
      this.updateUIFromTaskStatus(existingTask.status);
      if (existingTask.status === TaskStatus.COMPLETED) {
        logger.info(TAG, `电子书已下载: ${existingTask.savePath}`);
        return;
      }
    }

    // 开始获取下载源
    this.downloadButtonState = DownloadButtonState.LOADING;
    this.downloadPhase = 'fetching_sources';
    logger.info(TAG, `设置下载状态: LOADING, phase=fetching_sources`);

    try {
      // 使用WebView引擎获取下载源
      const params: Record<string, ESObject> = {};
      params['bookId'] = this.bookId;
      logger.info(TAG, `调用executeTask: getDownloadSources, bookId=${this.bookId}`);
      const result = await this.mangaSourceEngine.executeTask('getDownloadSources', params);
      logger.info(TAG, `executeTask返回: success=${result.success}, error=${result.error || 'none'}`);
      logger.debug(TAG, `executeTask结果详情: ${JSON.stringify(result).substring(0, 500)}`);

      if (result.success) {
        const parseResult = this.parseDownloadSourcesResult(result);
        const sources = parseResult.sources;
        const formSubmitted = parseResult.formSubmitted;
        const parseError = parseResult.error;
        
        logger.info(TAG, `解析到下载源数量: ${sources.length}, 表单已提交: ${formSubmitted}, 错误: ${parseError || 'none'}`);
        
        // 检查是否有解析错误
        if (parseError) {
          logger.error(TAG, `[验证失败] 解析阶段错误: ${parseError}`);
          throw new Error(`下载源解析失败: ${parseError}`);
        }
        
        if (formSubmitted) {
          // ManyBooks 表单已提交，等待页面跳转并提取文件列表
          logger.info(TAG, `[验证通过] ManyBooks 表单已提交，开始等待页面跳转...`);
          this.downloadPhase = 'fetching_files';
          // 等待页面跳转并提取文件列表
          await this.waitForNavigationAndExtractFileList();
          return;
        } else {
          // 表单未提交，检查原因
          logger.warn(TAG, `[验证失败] 表单未提交，可能原因: ManyBooks表单不存在或提交失败`);
        }
        
        if (sources.length > 0) {
          this.downloadSources = sources;
          
          // 显示选择器让用户选择
          this.showSourceSelector = true;
          this.downloadButtonState = DownloadButtonState.IDLE;
          this.downloadPhase = 'selecting_source';
          logger.info(TAG, `显示下载源选择器，共 ${sources.length} 个源`);
        } else {
          throw new Error('未找到可用的下载源');
        }
      } else {
        throw new Error(result.error || '获取下载源失败');
      }
    } catch (error) {
      logger.error(TAG, `获取下载源失败: ${String(error)}`);
      this.downloadButtonState = DownloadButtonState.FAILED;
      this.downloadPhase = 'failed';
    }
    === 封存的下载逻辑结束 === */
  }

  private parseDownloadSourcesResult(result: ESObject): DownloadSourcesParseResult {
    const sources: DownloadSource[] = [];
    let formSubmitted: boolean = false;
    let parseError: string | null = null;
    const emptyResult: DownloadSourcesParseResult = { sources: sources, formSubmitted: false, error: null as string | null };
    try {
      const resultRecord = result as Record<string, ESObject>;
      const stepResults = resultRecord['stepResults'] as Record<string, ESObject> | undefined;
      let data: ESObject = stepResults?.['step2_waitSources'] || resultRecord['data'];
      
      logger.debug(TAG, `解析下载源原始数据类型: ${typeof data}`);
      if (!data) {
        logger.warn(TAG, `下载源数据为空`);
        return { sources: sources, formSubmitted: false, error: '下载源数据为空' };
      }

      // 处理可能的双重JSON编码
      let parsed: ESObject;
      if (typeof data === 'string') {
        parsed = JSON.parse(data) as ESObject;
        if (typeof parsed === 'string') {
          logger.debug(TAG, `检测到双重JSON编码，再次解析`);
          parsed = JSON.parse(parsed) as ESObject;
        }
      } else {
        parsed = data;
      }

      // 检查是否是新格式（包含 sources 字段）
      let sourceList: ESObject[];
      if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
        const parsedRecord = parsed as Record<string, ESObject>;
        if (parsedRecord['sources'] !== undefined) {
          // 提取 formSubmitted 和 error
          formSubmitted = Boolean(parsedRecord['formSubmitted']);
          if (parsedRecord['error']) {
            parseError = String(parsedRecord['error']);
          }
          logger.info(TAG, `[解析] 表单提交状态: ${formSubmitted}, 错误: ${parseError || 'none'}`);
          
          sourceList = (parsedRecord['sources'] as ESObject[]) || [];
          // 记录调试信息
          if (parsedRecord['debug']) {
            const debug = parsedRecord['debug'] as Record<string, ESObject>;
            logger.info(TAG, `[下载源调试] phase: ${debug['phase']}, URL: ${debug['url']}, hasFindResults: ${debug['hasFindResults']}, formCount: ${debug['formCount']}`);
            logger.info(TAG, `[下载源调试] manyBooksFormFound: ${debug['manyBooksFormFound']}, formSubmitted: ${debug['formSubmitted']}, submitMethod: ${debug['submitMethod']}`);
            if (debug['manyBooksFormAction']) {
              logger.info(TAG, `[下载源调试] ManyBooks表单Action: ${String(debug['manyBooksFormAction']).substring(0, 100)}`);
            }
            if (debug['error']) {
              logger.error(TAG, `[下载源调试] 脚本错误: ${debug['error']}`);
              if (!parseError) {
                parseError = String(debug['error']);
              }
            }
            if (debug['bodyText']) {
              logger.info(TAG, `[下载源调试] 页面内容: ${String(debug['bodyText']).substring(0, 200)}`);
            }
          }
          logger.info(TAG, `新格式: formSubmitted=${formSubmitted}, sources=${sourceList.length}`);
        } else {
          logger.warn(TAG, `解析后的数据不是数组也不是新格式`);
          return { sources: sources, formSubmitted: false, error: '数据格式不支持' };
        }
      } else if (Array.isArray(parsed)) {
        sourceList = parsed;
      } else {
        logger.warn(TAG, `下载源数据格式不支持: ${typeof parsed}`);
        return { sources: sources, formSubmitted: false, error: '数据格式不支持' };
      }

      logger.info(TAG, `解析到 ${sourceList.length} 个下载源`);
      
      for (let i = 0; i < sourceList.length; i++) {
        const item = sourceList[i] as Record<string, ESObject>;
        const sourceName = String(item['name'] || `下载源 ${i + 1}`);
        const sourceUrl = String(item['url'] || '');
        logger.debug(TAG, `下载源 ${i}: name=${sourceName}, url=${sourceUrl.substring(0, 50)}...`);
        
        sources.push({
          id: String(item['id'] || i),
          name: sourceName,
          icon: item['icon'] ? String(item['icon']) : undefined,
          recommended: Boolean(item['recommended']),
          url: sourceUrl,
          params: item['params'] as Record<string, string> | undefined,
          available: true
        });
      }
    } catch (error) {
      logger.error(TAG, `解析下载源失败: ${String(error)}`);
      parseError = String(error);
    }
    const finalResult: DownloadSourcesParseResult = { sources: sources, formSubmitted: formSubmitted, error: parseError };
    return finalResult;
  }

  /**
   * 等待表单提交后的页面跳转，然后提取文件列表
   * 表单已在 waitForDownloadSources 脚本中提交，这里只需等待跳转完成
   * 
   * 验证流程：
   * 1. 验证页面已跳转离开 tstrs.me
   * 2. 验证跳转到的页面不是错误页面
   * 3. 验证页面包含可下载的文件
   */
  private async waitForNavigationAndExtractFileList(): Promise<void> {
    try {
      logger.info(TAG, `[表单跳转] === 阶段1: 等待页面跳转 ===`);
      
      // 阶段1: 等待页面跳转（表单提交后需要时间加载新页面）
      const maxWaitTime = 25000; // 最多等待25秒
      const checkInterval = 1000; // 每秒检查一次
      const maxChecks = maxWaitTime / checkInterval;
      let currentUrl = '';
      let hasNavigated = false;
      let lastUrl = '';
      
      // 先获取初始URL
      try {
        lastUrl = await this.mangaSourceEngine?.getCurrentUrl() || '';
        logger.info(TAG, `[表单跳转] 初始URL: ${lastUrl}`);
      } catch (e) {
        logger.warn(TAG, `[表单跳转] 获取初始URL失败: ${String(e)}`);
      }
      
      for (let i = 0; i < maxChecks; i++) {
        await new Promise<void>((resolve) => setTimeout(resolve, checkInterval));
        
        try {
          currentUrl = await this.mangaSourceEngine?.getCurrentUrl() || '';
          
          // 检查URL是否变化
          if (currentUrl !== lastUrl) {
            logger.info(TAG, `[表单跳转] 第${i + 1}次检查, URL变化: ${lastUrl} -> ${currentUrl}`);
            lastUrl = currentUrl;
          } else {
            logger.debug(TAG, `[表单跳转] 第${i + 1}次检查, URL未变化: ${currentUrl}`);
          }
          
          // 检查是否已经跳转到 ManyBooks 页面（不再是 tstrs.me）
          if (currentUrl && !currentUrl.includes('tstrs.me')) {
            hasNavigated = true;
            logger.info(TAG, `[表单跳转] ✅ 阶段1通过: 页面已跳转到外部站点: ${currentUrl}`);
            break;
          }
        } catch (e) {
          logger.warn(TAG, `[表单跳转] 第${i + 1}次检查失败: ${String(e)}`);
        }
      }
      
      // 验证阶段1
      if (!hasNavigated) {
        logger.error(TAG, `[表单跳转] ❌ 阶段1失败: 页面未跳转，仍在 tstrs.me (${currentUrl})`);
        throw new Error('表单提交后页面未跳转，可能原因: 1)表单提交失败 2)网络问题 3)需要验证码');
      }
      
      logger.info(TAG, `[表单跳转] === 阶段2: 验证目标页面 ===`);
      
      // 阶段2: 等待页面完全加载并验证
      await new Promise<void>((resolve) => setTimeout(resolve, 3000));
      
      currentUrl = await this.mangaSourceEngine?.getCurrentUrl() || '';
      logger.info(TAG, `[表单跳转] 最终URL: ${currentUrl}`);
      
      // 检查是否跳转到了错误页面
      if (currentUrl.includes('temporary_link')) {
        // 获取页面标题来确认是否是错误页面
        const pageInfo = await this.getPageInfo();
        logger.info(TAG, `[表单跳转] 页面信息: title=${pageInfo.title}, hasError=${pageInfo.hasError}`);
        
        if (pageInfo.hasError) {
          logger.error(TAG, `[表单跳转] ❌ 阶段2失败: 跳转到错误页面 (${pageInfo.title})`);
          throw new Error(`ManyBooks返回错误页面: ${pageInfo.title}`);
        }
      }
      
      logger.info(TAG, `[表单跳转] ✅ 阶段2通过: 目标页面有效`);
      
      logger.info(TAG, `[表单跳转] === 阶段3: 提取文件列表 ===`);
      
      // 阶段3: 执行 extractFileListOnly 任务提取文件列表
      const result = await this.mangaSourceEngine?.executeTask('extractFileListOnly', {});
      logger.debug(TAG, `[表单跳转] 任务结果: ${JSON.stringify(result).substring(0, 500)}`);

      if (!result?.success) {
        logger.error(TAG, `[表单跳转] ❌ 阶段3失败: extractFileListOnly任务失败 (${result?.error})`);
        throw new Error(result?.error || '获取文件列表失败');
      }
      
      const formats = this.parseFileFormats(result);
      logger.info(TAG, `[表单跳转] 解析到 ${formats.length} 个文件格式`);
      
      if (formats.length === 0) {
        // 获取更多页面信息用于调试
        const pageInfo = await this.getPageInfo();
        logger.error(TAG, `[表单跳转] ❌ 阶段3失败: 未找到可下载的文件`);
        logger.error(TAG, `[表单跳转] 页面调试: URL=${pageInfo.url}, title=${pageInfo.title}`);
        throw new Error('未找到可下载的文件，页面可能未正确加载');
      }
      
      logger.info(TAG, `[表单跳转] ✅ 阶段3通过: 找到 ${formats.length} 个可下载文件`);
      
      this.fileFormats = formats;
      this.showFormatSelector = true;
      this.downloadButtonState = DownloadButtonState.IDLE;
      this.downloadPhase = 'selecting_format';
      
      logger.info(TAG, `[表单跳转] === 全部验证通过，显示格式选择器 ===`);
      
    } catch (error) {
      logger.error(TAG, `[表单跳转] 获取文件列表失败: ${String(error)}`);
      this.downloadButtonState = DownloadButtonState.FAILED;
      this.downloadPhase = 'failed';
    }
  }

  /**
   * 获取当前页面信息（用于验证和调试）
   */
  private async getPageInfo(): Promise<PageInfo> {
    const defaultInfo: PageInfo = { url: '', title: '', hasError: false };
    try {
      const script = `JSON.stringify({ url: location.href, title: document.title, hasError: document.title.toLowerCase().includes('error') || document.body.innerText.toLowerCase().includes('something error') })`;
      const resultStr = await new Promise<string>((resolve, reject) => {
        this.webViewController?.runJavaScript(script, (error: Error | null, result: string) => {
          if (error) {
            reject(error);
          } else {
            resolve(String(result));
          }
        });
      });
      // 去掉可能的引号
      let cleanResult = resultStr;
      if (cleanResult.startsWith('"') && cleanResult.endsWith('"')) {
        cleanResult = cleanResult.slice(1, -1).replace(/\\"/g, '"');
      }
      const info = JSON.parse(cleanResult) as PageInfo;
      return info;
    } catch (e) {
      logger.warn(TAG, `获取页面信息失败: ${String(e)}`);
      return defaultInfo;
    }
  }

  /**
   * 使用 HTTP POST 请求模拟表单提交访问 ManyBooks 代理（备用方案）
   * 然后解析返回的 HTML 提取文件列表
   */
  private async navigateAndExtractFileList(sourceUrl: string): Promise<void> {
    try {
      logger.info(TAG, `[HTTP请求] 开始POST请求: ${sourceUrl}`);
      
      // 使用 HTTP POST 请求模拟表单提交
      const httpRequest = http.createHttp();
      
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'User-Agent': 'Mozilla/5.0 (Phone; OpenHarmony 6.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36 ArkWeb/6.0.0.120 Mobile',
          'Referer': 'https://tstrs.me/',
          'Origin': 'https://tstrs.me'
        },
        readTimeout: 30000,
        connectTimeout: 15000
      };
      
      logger.info(TAG, `[HTTP请求] 发送POST请求...`);
      const response = await httpRequest.request(sourceUrl, options);
      logger.info(TAG, `[HTTP请求] 响应状态: ${response.responseCode}`);
      
      if (response.responseCode === 200 || response.responseCode === 302 || response.responseCode === 301) {
        const html = typeof response.result === 'string' ? response.result : String(response.result);
        logger.info(TAG, `[HTTP请求] 响应HTML长度: ${html.length}`);
        logger.debug(TAG, `[HTTP请求] HTML前500字符: ${html.substring(0, 500)}`);
        
        // 解析 HTML 提取文件列表
        const formats = this.parseFileFormatsFromHtml(html);
        logger.info(TAG, `[HTTP请求] 解析到 ${formats.length} 个文件格式`);
        
        if (formats.length > 0) {
          this.fileFormats = formats;
          this.showFormatSelector = true;
          this.downloadButtonState = DownloadButtonState.IDLE;
          this.downloadPhase = 'selecting_format';
        } else {
          // 如果POST不行，尝试GET请求
          logger.warn(TAG, `[HTTP请求] POST请求未找到文件，尝试GET请求...`);
          await this.tryGetRequest(sourceUrl);
        }
      } else {
        throw new Error(`HTTP请求失败: ${response.responseCode}`);
      }
      
      httpRequest.destroy();
    } catch (error) {
      logger.error(TAG, `[HTTP请求] 获取文件列表失败: ${String(error)}`);
      // 回退到 WebView 导航方式
      logger.info(TAG, `[HTTP请求] 回退到WebView导航方式...`);
      await this.navigateAndExtractFileListViaWebView(sourceUrl);
    }
  }

  /**
   * 尝试使用 GET 请求获取文件列表
   */
  private async tryGetRequest(sourceUrl: string): Promise<void> {
    const httpRequest = http.createHttp();
    
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      header: {
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'User-Agent': 'Mozilla/5.0 (Phone; OpenHarmony 6.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36 ArkWeb/6.0.0.120 Mobile',
        'Referer': 'https://tstrs.me/'
      },
      readTimeout: 30000,
      connectTimeout: 15000
    };
    
    logger.info(TAG, `[HTTP GET] 发送GET请求: ${sourceUrl}`);
    const response = await httpRequest.request(sourceUrl, options);
    logger.info(TAG, `[HTTP GET] 响应状态: ${response.responseCode}`);
    
    if (response.responseCode === 200) {
      const html = typeof response.result === 'string' ? response.result : String(response.result);
      logger.info(TAG, `[HTTP GET] 响应HTML长度: ${html.length}`);
      logger.debug(TAG, `[HTTP GET] HTML前500字符: ${html.substring(0, 500)}`);
      
      const formats = this.parseFileFormatsFromHtml(html);
      logger.info(TAG, `[HTTP GET] 解析到 ${formats.length} 个文件格式`);
      
      if (formats.length > 0) {
        this.fileFormats = formats;
        this.showFormatSelector = true;
        this.downloadButtonState = DownloadButtonState.IDLE;
        this.downloadPhase = 'selecting_format';
      } else {
        throw new Error('未找到可下载的文件');
      }
    } else {
      throw new Error(`GET请求失败: ${response.responseCode}`);
    }
    
    httpRequest.destroy();
  }

  /**
   * 从 HTML 解析文件格式列表
   */
  private parseFileFormatsFromHtml(html: string): FileFormat[] {
    const formats: FileFormat[] = [];
    
    // 查找下载链接 - 匹配常见的电子书格式
    const linkPattern = /href=["']([^"']*\.(epub|mobi|pdf|azw3|txt)[^"']*)["']/gi;
    let match: RegExpExecArray | null;
    const seen = new Set<string>();
    
    while ((match = linkPattern.exec(html)) !== null) {
      const url = match[1];
      const format = match[2].toLowerCase();
      
      if (!seen.has(format)) {
        seen.add(format);
        const fileFormat: FileFormat = {
          format: format,
          displayName: `${format.toUpperCase()} 格式`,
          size: '',
          url: url.startsWith('http') ? url : `https://manybooks.net${url}`,
          available: true
        };
        formats.push(fileFormat);
        logger.debug(TAG, `[HTML解析] 找到文件: format=${format}, url=${url.substring(0, 80)}`);
      }
    }
    
    // 如果没找到直接链接，尝试查找按钮或其他下载元素
    if (formats.length === 0) {
      // 查找 onclick 中的链接
      const onclickPattern = /onclick=["'][^"']*href=["']([^"']*\.(epub|mobi|pdf|azw3|txt)[^"']*)["']/gi;
      while ((match = onclickPattern.exec(html)) !== null) {
        const url = match[1];
        const format = match[2].toLowerCase();
        
        if (!seen.has(format)) {
          seen.add(format);
          const fileFormat: FileFormat = {
            format: format,
            displayName: `${format.toUpperCase()} 格式`,
            size: '',
            url: url.startsWith('http') ? url : `https://manybooks.net${url}`,
            available: true
          };
          formats.push(fileFormat);
          logger.debug(TAG, `[HTML解析] 从onclick找到文件: format=${format}`);
        }
      }
    }
    
    return formats;
  }

  /**
   * 使用 WebView 导航方式获取文件列表（回退方案）
   */
  private async navigateAndExtractFileListViaWebView(sourceUrl: string): Promise<void> {
    try {
      logger.info(TAG, `[WebView导航] 开始导航到: ${sourceUrl}`);
      
      const params: Record<string, ESObject> = {};
      params['sourceUrl'] = sourceUrl;
      
      const result = await this.mangaSourceEngine?.executeTask('getFileListFromSource', params);
      
      try {
        const currentUrl = await this.mangaSourceEngine?.getCurrentUrl() || '';
        logger.info(TAG, `[WebView导航] 导航后URL: ${currentUrl}`);
      } catch (e) {
        logger.warn(TAG, `[WebView导航] 获取当前URL失败: ${String(e)}`);
      }
      
      logger.debug(TAG, `[WebView导航] 任务结果: ${JSON.stringify(result).substring(0, 500)}`);

      if (result?.success) {
        const formats = this.parseFileFormats(result);
        logger.info(TAG, `[WebView导航] 解析到 ${formats.length} 个文件格式`);
        if (formats.length > 0) {
          this.fileFormats = formats;
          this.showFormatSelector = true;
          this.downloadButtonState = DownloadButtonState.IDLE;
          this.downloadPhase = 'selecting_format';
        } else {
          throw new Error('未找到可下载的文件');
        }
      } else {
        throw new Error(result?.error || '获取文件列表失败');
      }
    } catch (error) {
      logger.error(TAG, `[WebView导航] 获取文件列表失败: ${String(error)}`);
      this.downloadButtonState = DownloadButtonState.FAILED;
      this.downloadPhase = 'failed';
    }
  }

  private async waitAndExtractFileList(): Promise<void> {
    try {
      // 获取初始URL用于对比
      let initialUrl = '';
      try {
        initialUrl = await this.mangaSourceEngine?.getCurrentUrl() || '';
        logger.info(TAG, `[跳转检测] 初始URL: ${initialUrl}`);
      } catch (e) {
        logger.warn(TAG, `[跳转检测] 获取初始URL失败: ${String(e)}`);
      }

      // 多次检查页面是否真的跳转（最多检查10次，每次间隔2秒）
      const maxChecks = 10;
      const checkInterval = 2000;
      let hasNavigated = false;
      let currentUrl = initialUrl;
      
      for (let i = 0; i < maxChecks; i++) {
        await new Promise<void>((resolve) => setTimeout(resolve, checkInterval));
        
        try {
          currentUrl = await this.mangaSourceEngine?.getCurrentUrl() || '';
          logger.info(TAG, `[跳转检测] 第${i + 1}次检查, URL: ${currentUrl}`);
          
          // 检查是否已经跳转到非tstrs.me的页面（ManyBooks等外部页面）
          if (currentUrl && !currentUrl.includes('tstrs.me')) {
            hasNavigated = true;
            logger.info(TAG, `[跳转检测] ✅ 页面已跳转到外部页面: ${currentUrl}`);
            break;
          }
          
          // 检查是否跳转到了temporary_link页面（ManyBooks的中转页面）
          if (currentUrl && currentUrl.includes('temporary_link')) {
            hasNavigated = true;
            logger.info(TAG, `[跳转检测] ✅ 页面已跳转到临时链接页面: ${currentUrl}`);
            break;
          }
          
          // 检查URL是否发生了变化（可能跳转到了其他tstrs.me页面）
          if (currentUrl && currentUrl !== initialUrl) {
            logger.info(TAG, `[跳转检测] URL已变化: ${initialUrl} -> ${currentUrl}`);
          }
        } catch (e) {
          logger.warn(TAG, `[跳转检测] 第${i + 1}次检查失败: ${String(e)}`);
        }
      }
      
      if (!hasNavigated) {
        logger.warn(TAG, `[跳转检测] ⚠️ 页面未跳转，仍在: ${currentUrl}`);
        logger.warn(TAG, `[跳转检测] 可能原因: 1)按钮点击失败 2)网络问题 3)需要验证码`);
      }
      
      // 再等待2秒让页面完全加载
      await new Promise<void>((resolve) => setTimeout(resolve, 2000));
      
      // 执行前再次验证当前URL
      try {
        currentUrl = await this.mangaSourceEngine?.getCurrentUrl() || '';
        logger.info(TAG, `[extractFileListOnly] 执行前URL验证: ${currentUrl}`);
        
        // 如果仍在tstrs.me页面，记录警告
        if (currentUrl.includes('tstrs.me')) {
          logger.warn(TAG, `[extractFileListOnly] ⚠️ 仍在tstrs.me页面，提取可能失败`);
        }
      } catch (e) {
        logger.warn(TAG, `[extractFileListOnly] URL验证失败: ${String(e)}`);
      }
      
      // 执行 extractFileListOnly 任务提取文件列表
      logger.info(TAG, `[extractFileListOnly] 开始执行任务...`);
      const result = await this.mangaSourceEngine?.executeTask('extractFileListOnly', {});
      logger.debug(TAG, `[extractFileListOnly] 任务结果: ${JSON.stringify(result).substring(0, 500)}`);

      if (result?.success) {
        const formats = this.parseFileFormats(result);
        logger.info(TAG, `[extractFileListOnly] 解析到 ${formats.length} 个文件格式`);
        if (formats.length > 0) {
          this.fileFormats = formats;
          this.showFormatSelector = true;
          this.downloadButtonState = DownloadButtonState.IDLE;
          this.downloadPhase = 'selecting_format';
        } else {
          throw new Error('未找到可下载的文件');
        }
      } else {
        throw new Error(result?.error || '获取文件列表失败');
      }
    } catch (error) {
      logger.error(TAG, `获取文件列表失败: ${String(error)}`);
      this.downloadButtonState = DownloadButtonState.FAILED;
      this.downloadPhase = 'failed';
    }
  }

  private updateUIFromTaskStatus(status: TaskStatus): void {
    switch (status) {
      case TaskStatus.PENDING:
        this.downloadButtonState = DownloadButtonState.LOADING;
        break;
      case TaskStatus.DOWNLOADING:
        this.downloadButtonState = DownloadButtonState.DOWNLOADING;
        break;
      case TaskStatus.COMPLETED:
        this.downloadButtonState = DownloadButtonState.COMPLETED;
        break;
      case TaskStatus.FAILED:
        this.downloadButtonState = DownloadButtonState.FAILED;
        break;
      default:
        this.downloadButtonState = DownloadButtonState.IDLE;
        break;
    }
  }

  private async handleSourceSelect(source: DownloadSource): Promise<void> {
    this.selectedSourceId = source.id;
    this.showSourceSelector = false;
    this.downloadButtonState = DownloadButtonState.LOADING;
    this.downloadPhase = 'fetching_files';

    try {
      // 获取文件列表
      const params: Record<string, ESObject> = {};
      params['sourceUrl'] = source.url;
      const result = await this.mangaSourceEngine?.executeTask('getFileListFromSource', params);

      if (result?.success) {
        const formats = this.parseFileFormats(result);
        if (formats.length > 0) {
          this.fileFormats = formats;
          this.showFormatSelector = true;
          this.downloadButtonState = DownloadButtonState.IDLE;
          this.downloadPhase = 'selecting_format';
        } else {
          throw new Error('未找到可下载的文件');
        }
      } else {
        throw new Error(result?.error || '获取文件列表失败');
      }
    } catch (error) {
      logger.error(TAG, `获取文件列表失败: ${String(error)}`);
      this.downloadButtonState = DownloadButtonState.FAILED;
      this.downloadPhase = 'failed';
    }
  }

  private parseFileFormats(result: ESObject): FileFormat[] {
    const formats: FileFormat[] = [];
    try {
      const resultRecord = result as Record<string, ESObject>;
      const stepResults = resultRecord['stepResults'] as Record<string, ESObject> | undefined;
      let data: ESObject = stepResults?.['step2_extractFiles'] || resultRecord['data'];
      if (!data) return formats;

      // 处理可能的双重JSON编码
      if (typeof data === 'string') {
        let parsed: ESObject = JSON.parse(data) as ESObject;
        if (typeof parsed === 'string') {
          parsed = JSON.parse(parsed) as ESObject;
        }
        data = parsed;
      }

      // 检查是否是新格式（包含 debug 和 files 字段）
      let fileList: ESObject[];
      if (data && typeof data === 'object' && !Array.isArray(data)) {
        const dataRecord = data as Record<string, ESObject>;
        // 记录调试信息
        if (dataRecord['debug']) {
          const debug = dataRecord['debug'] as Record<string, ESObject>;
          logger.info(TAG, `[文件列表调试] URL: ${debug['url']}, 是否临时链接: ${debug['isTemporaryLink']}, 有file-list: ${debug['hasFileList']}, file-item数量: ${debug['fileItemCount']}`);
          if (debug['bodyText']) {
            logger.info(TAG, `[文件列表调试] 页面内容: ${String(debug['bodyText']).substring(0, 200)}`);
          }
        }
        fileList = (dataRecord['files'] as ESObject[]) || [];
      } else if (Array.isArray(data)) {
        fileList = data;
      } else {
        return formats;
      }

      for (let i = 0; i < fileList.length; i++) {
        const item = fileList[i] as Record<string, ESObject>;
        const format = String(item['format'] || '').toLowerCase();
        if (format) {
          formats.push({
            format: format,
            displayName: format.toUpperCase(),
            size: item['size'] ? String(item['size']) : undefined,
            url: item['url'] ? String(item['url']) : undefined,
            available: true
          });
        }
      }
    } catch (error) {
      logger.error(TAG, `解析文件格式失败: ${String(error)}`);
    }
    return formats;
  }

  private async handleFormatSelect(format: FileFormat): Promise<void> {
    this.selectedFormat = format.format;
    this.showFormatSelector = false;
    this.downloadButtonState = DownloadButtonState.DOWNLOADING;
    this.downloadPhase = 'downloading';

    if (!format.url) {
      logger.error(TAG, '下载链接不可用');
      this.downloadButtonState = DownloadButtonState.FAILED;
      return;
    }

    try {
      // 使用全局下载管理器创建下载任务
      const taskId = await this.globalDownloadManager.createEBookDownloadTask(
        this.bookId,
        this.bookInfo?.title || this.cachedTitle || 'ebook',
        format.url,
        format.format,
        this.sourceId
      );

      logger.info(TAG, `电子书下载任务已创建: ${taskId}`);
      
      // 开始轮询下载进度
      this.pollDownloadProgress(taskId);
    } catch (error) {
      logger.error(TAG, `创建下载任务失败: ${String(error)}`);
      this.downloadButtonState = DownloadButtonState.FAILED;
      this.downloadPhase = 'failed';
    }
  }

  private pollDownloadProgress(taskId: string): void {
    const checkProgress = (): void => {
      const task = this.globalDownloadManager.getTask(taskId);
      if (!task) {
        return;
      }

      this.currentDownloadTask = task;
      this.downloadProgress = task.progress;
      this.updateUIFromTaskStatus(task.status);

      if (task.status === TaskStatus.DOWNLOADING || task.status === TaskStatus.PENDING) {
        setTimeout(() => checkProgress(), 500);
      } else if (task.status === TaskStatus.COMPLETED) {
        this.downloadPhase = 'completed';
        logger.info(TAG, `电子书下载完成: ${task.savePath}`);
      } else if (task.status === TaskStatus.FAILED) {
        this.downloadPhase = 'failed';
        logger.error(TAG, `电子书下载失败: ${task.error}`);
      }
    };

    checkProgress();
  }

  build() {
    HdsNavDestination() {
      Stack() {
        // 隐藏的WebView用于执行脚本
        Web({ src: 'about:blank', controller: this.webViewController })
          .width(1)
          .height(1)
          .opacity(0)
          .position({ x: -100, y: -100 })
          .onControllerAttached(() => {
            logger.info(TAG, 'WebView控制器已附加');
          })

        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_dark', this.themeState.currentTheme))
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        Column() {
          Blank().height(TITLE_BAR_HEIGHT)

          if (this.isLoading) {
            Column({ space: 16 }) {
              LoadingProgress()
                .width(48)
                .height(48)
                .color(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
              Text('加载中...')
                .fontSize(14)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else if (this.errorMessage && !this.bookInfo) {
            Column({ space: 16 }) {
              Text(this.errorMessage)
                .fontSize(14)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              Button('重试')
                .onClick(() => {
                  this.loadBookDetail();
                })
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else {
            Scroll(this.scroller) {
              Column({ space: 16 }) {
                this.buildBookInfoCard()
                if (this.bookInfo?.description) {
                  this.buildDescriptionCard()
                }
                if (this.bookInfo?.downloadLinks && this.bookInfo.downloadLinks.length > 0) {
                  this.buildDownloadCard()
                }
                Blank().height(this.navigationBarHeight + 20)
              }
              .width('100%')
              .padding({ left: 16, right: 16 })
            }
            .scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.Spring)
            .layoutWeight(1)
          }
        }
        .width('100%')
        .height('100%')
      }
    }
    .hideTitleBar(true)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_dark', this.themeState.currentTheme))
    .onReady((context: NavDestinationContext) => {
      const params = context.pathInfo.param as OnlineEBookDetailPageParams;
      if (params) {
        this.initializePage(params);
      }
    })
  }

  @Builder
  buildBookInfoCard() {
    Row({ space: 16 }) {
      if (this.coverPixelMap) {
        Image(this.coverPixelMap)
          .width(120)
          .height(180)
          .borderRadius(8)
          .objectFit(ImageFit.Cover)
      } else {
        Image(this.getCoverSource())
          .width(120)
          .height(180)
          .borderRadius(8)
          .objectFit(ImageFit.Cover)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
      }

      Column({ space: 8 }) {
        Text(this.bookInfo?.title || this.cachedTitle || '未知书名')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (this.bookInfo?.author) {
          Text(this.bookInfo.author)
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }

        if (this.bookInfo?.publisher) {
          Text(this.bookInfo.publisher)
            .fontSize(12)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        }

        if (this.bookInfo?.categories) {
          Text(this.bookInfo.categories)
            .fontSize(12)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
        }

        Blank()

        Row({ space: 4 }) {
          Text('来源:')
            .fontSize(11)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          Text(this.sourceInfo?.name || '')
            .fontSize(11)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme))
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .height(180)
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
  }

  @Builder
  buildDescriptionCard() {
    Column({ space: 8 }) {
      Text('简介')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

      Text(this.bookInfo?.description || '')
        .fontSize(14)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .maxLines(this.expandedDescription ? 100 : 4)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .onClick(() => {
          this.expandedDescription = !this.expandedDescription;
        })

      if (!this.expandedDescription && (this.bookInfo?.description?.length || 0) > 100) {
        Text('展开')
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .onClick(() => {
            this.expandedDescription = true;
          })
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  buildDownloadCard() {
    Column({ space: 12 }) {
      Text('下载')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

      // 下载源选择器
      if (this.showSourceSelector && this.downloadSources.length > 0) {
        this.buildSourceSelector()
      }
      // 格式选择器
      else if (this.showFormatSelector && this.fileFormats.length > 0) {
        this.buildFormatSelector()
      }
      // 下载按钮
      else {
        this.buildDownloadButton()
      }

      // 任务进度
      if (this.currentDownloadTask && this.downloadPhase !== 'idle') {
        this.buildTaskProgress()
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  buildDownloadButton() {
    Stack() {
      // 进度背景
      if (this.downloadButtonState === DownloadButtonState.DOWNLOADING) {
        Row()
          .width(`${this.downloadProgress}%`)
          .height('100%')
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme) + '40')
          .borderRadius(8)
      }

      Row({ space: 8 }) {
        if (this.downloadButtonState === DownloadButtonState.LOADING || 
            this.downloadButtonState === DownloadButtonState.DOWNLOADING) {
          LoadingProgress()
            .width(20)
            .height(20)
            .color(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
        }

        Text(this.getDownloadButtonText())
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
      }
      .justifyContent(FlexAlign.Center)
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height(48)
    .backgroundColor(this.getDownloadButtonColor())
    .borderRadius(8)
    .onClick(() => {
      if (this.downloadButtonState === DownloadButtonState.IDLE || 
          this.downloadButtonState === DownloadButtonState.FAILED) {
        this.startDownloadFlow();
      }
    })
  }

  private getDownloadButtonText(): string {
    switch (this.downloadButtonState) {
      case DownloadButtonState.LOADING:
        // 根据下载阶段显示不同的提示
        switch (this.downloadPhase) {
          case 'fetching_sources':
            return '正在搜索下载源...';
          case 'fetching_files':
            return '正在获取文件列表...';
          case 'selecting_source':
            return '请选择下载源';
          case 'selecting_format':
            return '请选择文件格式';
          default:
            return '准备中...';
        }
      case DownloadButtonState.DOWNLOADING:
        return `下载中 ${this.downloadProgress}%`;
      case DownloadButtonState.COMPLETED:
        return '下载完成';
      case DownloadButtonState.FAILED:
        return '下载失败，点击重试';
      default:
        return '下载电子书';
    }
  }

  private getDownloadButtonColor(): ResourceColor {
    switch (this.downloadButtonState) {
      case DownloadButtonState.COMPLETED:
        return '#4CAF50';
      case DownloadButtonState.FAILED:
        return '#F44336';
      default:
        return ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme);
    }
  }

  @Builder
  buildSourceSelector() {
    Column({ space: 8 }) {
      Text('选择下载源')
        .fontSize(14)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

      ForEach(this.downloadSources, (source: DownloadSource) => {
        Row({ space: 12 }) {
          // 图标
          Text(source.name.charAt(0).toUpperCase())
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
            .width(32)
            .height(32)
            .textAlign(TextAlign.Center)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
            .borderRadius(6)

          // 名称
          Text(source.name)
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .layoutWeight(1)

          // 推荐标签
          if (source.recommended) {
            Text('推荐')
              .fontSize(10)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
              .backgroundColor('#FF9800')
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .borderRadius(4)
          }
        }
        .width('100%')
        .padding(12)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_dark', this.themeState.currentTheme))
        .borderRadius(8)
        .onClick(() => {
          this.handleSourceSelect(source);
        })
      }, (source: DownloadSource) => source.id)

      // 取消按钮
      Button('取消')
        .width('100%')
        .height(40)
        .fontSize(14)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_dark', this.themeState.currentTheme))
        .borderRadius(8)
        .onClick(() => {
          this.showSourceSelector = false;
          this.downloadPhase = 'idle';
        })
    }
    .width('100%')
  }

  @Builder
  buildFormatSelector() {
    Column({ space: 8 }) {
      Text('选择格式')
        .fontSize(14)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        ForEach(this.fileFormats, (format: FileFormat) => {
          Column({ space: 4 }) {
            Text(format.displayName || format.format.toUpperCase())
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.selectedFormat === format.format 
                ? ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme)
                : this.getFormatColor(format.format))

            if (format.size) {
              Text(format.size)
                .fontSize(10)
                .fontColor(this.selectedFormat === format.format 
                  ? ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme) + 'CC'
                  : ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            }
          }
          .padding({ left: 16, right: 16, top: 10, bottom: 10 })
          .margin({ right: 8, bottom: 8 })
          .backgroundColor(this.selectedFormat === format.format 
            ? this.getFormatColor(format.format)
            : ThemeAwareHelper.getTestManagementThemedColor('background_dark', this.themeState.currentTheme))
          .borderRadius(8)
          .border({
            width: 1,
            color: this.getFormatColor(format.format)
          })
          .onClick(() => {
            this.handleFormatSelect(format);
          })
        }, (format: FileFormat) => format.format)
      }
      .width('100%')

      // 取消按钮
      Button('取消')
        .width('100%')
        .height(40)
        .fontSize(14)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_dark', this.themeState.currentTheme))
        .borderRadius(8)
        .onClick(() => {
          this.showFormatSelector = false;
          this.downloadPhase = 'idle';
        })
    }
    .width('100%')
  }

  private getFormatColor(format: string): ResourceColor {
    const colorMap: Record<string, string> = {
      'epub': '#4CAF50',
      'mobi': '#FF9800',
      'pdf': '#F44336',
      'azw3': '#9C27B0',
      'txt': '#607D8B'
    };
    return colorMap[format.toLowerCase()] || '#2196F3';
  }

  @Builder
  buildTaskProgress() {
    Column({ space: 8 }) {
      // 进度条
      Progress({ value: this.downloadProgress, total: 100, type: ProgressType.Linear })
        .width('100%')
        .height(4)
        .color(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_dark', this.themeState.currentTheme))
        .borderRadius(2)

      // 当前状态
      Row({ space: 8 }) {
        Text(this.getPhaseIcon())
          .fontSize(12)
          .fontColor(this.getPhaseColor())
          .width(16)

        Text(this.getPhaseText())
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .layoutWeight(1)

        if (this.downloadPhase === 'downloading' || this.downloadPhase === 'fetching_sources' || this.downloadPhase === 'fetching_files') {
          LoadingProgress()
            .width(14)
            .height(14)
            .color(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
        }
      }
      .width('100%')

      // 错误信息
      if (this.currentDownloadTask?.error) {
        Text(this.currentDownloadTask.error)
          .fontSize(12)
          .fontColor('#F44336')
          .width('100%')
          .padding(8)
          .backgroundColor('#F4433620')
          .borderRadius(6)
      }
    }
    .width('100%')
    .padding({ top: 8 })
  }

  private getPhaseIcon(): string {
    switch (this.downloadPhase) {
      case 'completed':
        return '✓';
      case 'downloading':
      case 'fetching_sources':
      case 'fetching_files':
        return '●';
      case 'failed':
        return '✗';
      default:
        return '○';
    }
  }

  private getPhaseColor(): ResourceColor {
    switch (this.downloadPhase) {
      case 'completed':
        return '#4CAF50';
      case 'downloading':
      case 'fetching_sources':
      case 'fetching_files':
        return ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme);
      case 'failed':
        return '#F44336';
      default:
        return ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme);
    }
  }

  private getPhaseText(): string {
    switch (this.downloadPhase) {
      case 'fetching_sources':
        return '正在获取下载源...';
      case 'selecting_source':
        return '请选择下载源';
      case 'fetching_files':
        return '正在获取文件列表...';
      case 'selecting_format':
        return '请选择文件格式';
      case 'downloading':
        return `下载中 ${this.downloadProgress}%`;
      case 'completed':
        return '下载完成';
      case 'failed':
        return '下载失败';
      default:
        return '';
    }
  }

  private getStepIcon(status: StepStatus): string {
    switch (status) {
      case StepStatus.COMPLETED:
        return '✓';
      case StepStatus.RUNNING:
        return '●';
      case StepStatus.FAILED:
        return '✗';
      case StepStatus.WAITING:
        return '⏸';
      default:
        return '○';
    }
  }

  private getStepColor(status: StepStatus): ResourceColor {
    switch (status) {
      case StepStatus.COMPLETED:
        return '#4CAF50';
      case StepStatus.RUNNING:
        return ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme);
      case StepStatus.FAILED:
        return '#F44336';
      case StepStatus.WAITING:
        return '#FF9800';
      default:
        return ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme);
    }
  }
}
