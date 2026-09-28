// 文件路径: entry/src/main/ets/pages/OnlineEBookDetailPage.ets
/**
 * 在线电子书详情页
 * 用于从图源详情页进入，显示在线电子书的详细信息
 * UI结构与EBookDetailPage类似，但功能逻辑不同
 */

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { ThemeAwareState, ThemeAwareHelper } from 'manxia_theme/src/main/ets/Framework/Components/ThemeAware';
import { ThemeType } from 'manxia_theme/src/main/ets/Framework/Managers/ThemeManager';
import { PageLifecycleManager } from 'manxia_core/src/main/ets/Framework/Lifecycle/index';
import { DeviceAdaptationManager, DeviceChangeListener, DeviceInfo } from 'manxia_theme/src/main/ets/Framework/Managers/DeviceAdaptationManager';
import { SourceManager, SourceInfo } from '../Framework/Source/SourceManager';
import { MangaSourceEngine, EngineConfig } from '../Framework/WebView/MangaSourceEngine';
import { WebViewAuthManager } from '../Framework/WebView/WebViewAuthManager';
import { AntiCrawlerConfig, TaskResult } from 'manxia_source_engine/src/main/ets/Framework/WebView/MangaSourceTypes';
import { ImageCacheManager } from '../Framework/Cache/ImageCacheManager';
import { DataManager } from '../Framework/Data/DataManager';
import { EBookDataManager } from 'manxia_core/src/main/ets/Framework/Data/EBookDataManager';
import { openEBookReaderRouterPage } from '../Framework/Adapters/EBookReaderRouteNavigator';
import { OnlineEBookImportService } from '../Framework/Services/OnlineEBookImportService';
import { webview } from '@kit.ArkWeb';
import { http } from '@kit.NetworkKit';
import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import request from '@ohos.request';
import fs from '@ohos.file.fs';
import {
  DownloadSource,
  FileFormat,
  StepStatus,
  DownloadButtonState,
  DownloadSourceSelector,
  FileFormatSelector
} from 'manxia_theme/src/main/ets/Framework/Components/EBookDownloadComponents';
import {
  MangaDownloadManager,
  TaskStatus,
  DownloadTaskInfo,
  DownloadTaskType
} from '../Framework/Download/DownloadManager';
import { EBookReaderParams } from './EBookReaderRouteTypes';
import { ChapterInfo as SourceChapterInfo, PageInfo as SourcePageInfo } from 'manxia_source_engine/src/main/ets/Framework/WebView/MangaSourceTypes';
import { promptAction } from '@kit.ArkUI';
import { AppColors } from 'manxia_theme/src/main/ets/Framework/Theme/AppColors';
import { SettingsImmersiveTitleBar } from './settings/SettingsImmersiveTitleBar';
import { SettingsPageTitleBarManager } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPageTitleBarManager';
import { SharedPageBackgroundLayer } from 'manxia_theme/src/main/ets/Framework/Components/SharedPageBackgroundLayer';
import { GlobalBackgroundLayerMode } from 'manxia_theme/src/main/ets/Framework/Components/GlobalBackgroundLayer';

const TAG = 'OnlineEBookDetailPage';

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
  autoStartDownload?: boolean;
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

interface OnlineEBookVerifyState {
  url: string;
  title: string;
  isVerifyEntry: boolean;
  cooldownText: string;
  canRetryVerification: boolean;
}

@Component
export struct OnlineEBookDetailPage {
  @Consume('NavPathStack') pathStack: NavPathStack;
  @Provide('themeState') themeState: ThemeAwareState = new ThemeAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  private componentId: string = 'OnlineEBookDetailPage';
  private scroller: Scroller = new Scroller();

  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;

  private sourceId: number = 0;
  private bookId: string = '';
  private cachedCoverPath: string = '';
  private cachedTitle: string = '';
  private cachedCover: string = '';
  private autoStartDownload: boolean = false;
  private autoStartTriggered: boolean = false;

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
  private authManager: WebViewAuthManager = WebViewAuthManager.getInstance();
  private dataManager: DataManager = DataManager.getInstance();
  private ebookDataManager: EBookDataManager = EBookDataManager.getInstance();
  private onlineEBookImportService: OnlineEBookImportService = OnlineEBookImportService.getInstance();
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
  @State importedBookId: string = '';
  @State importStatusText: string = '';
  @State importErrorMessage: string = '';
  @State detailRecoveryInProgress: boolean = false;
  @State detailRecoveryStatusText: string = '';
  private readonly detailRecoveryMaxAttempts: number = 2;
  private detailRecoveryTimer: number = -1;
  private importInProgress: boolean = false;
  @State isWaitingForDlRedirect: boolean = false;
  @State dlOriginalUrl: string = '';
  @State dlBookTitle: string = '';
  @State dlFileFormat: string = '';

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

  private lifecycle = new PageLifecycleManager('OnlineEBookDetailPage', { enableDebug: true });

  aboutToDisappear(): void {
    if (this.detailRecoveryTimer >= 0) {
      clearTimeout(this.detailRecoveryTimer);
      this.detailRecoveryTimer = -1;
    }
    this.lifecycle.destroy();
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
    this.autoStartDownload = params.autoStartDownload === true;
    this.autoStartTriggered = false;
    this.importedBookId = '';
    this.importStatusText = '';
    this.importErrorMessage = '';
    this.importInProgress = false;
    this.detailRecoveryInProgress = false;
    this.detailRecoveryStatusText = '';
    if (this.autoStartDownload) {
      this.downloadButtonState = DownloadButtonState.LOADING;
      this.downloadPhase = 'recovering_detail';
    } else {
      this.downloadButtonState = DownloadButtonState.IDLE;
      this.downloadPhase = 'idle';
    }
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
      let coverUrl = this.cachedCoverPath || this.cachedCover;
      if (!coverUrl) {
        return;
      }
      // 解析相对URL为绝对URL
      if (coverUrl.startsWith('/') && this.sourceInfo?.baseUrl) {
        const base = String(this.sourceInfo.baseUrl);
        coverUrl = base.endsWith('/') ? base + coverUrl.substring(1) : base + coverUrl;
        logger.info(TAG, `封面相对URL已解析: ${coverUrl.substring(0, 80)}`);
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

  private isInvalidBookDetailResult(detail: Record<string, Object>): boolean {
    const title: string = String(detail['title'] || '').trim();
    const detailId: string = String(detail['id'] || '').trim();
    const baseUrl: string = this.sourceInfo?.baseUrl ? String(this.sourceInfo.baseUrl).toLowerCase() : '';
    if (title.includes('安全检查') || detailId.includes('verify_entry')) {
      return true;
    }
    if (baseUrl.includes('tstrs.me') && detailId.startsWith('/')) {
      return true;
    }
    return false;
  }

  private parseCooldownTextToSeconds(text: string): number {
    const normalizedText: string = String(text || '').replace(/\s+/g, ' ').trim();
    if (normalizedText.length <= 0) {
      return 0;
    }
    const minuteMatch: RegExpMatchArray | null = normalizedText.match(/(\d+)\s*分钟/);
    if (minuteMatch && minuteMatch.length > 1) {
      return Number(minuteMatch[1]) * 60;
    }
    const secondMatch: RegExpMatchArray | null = normalizedText.match(/(\d+)\s*秒/);
    if (secondMatch && secondMatch.length > 1) {
      return Number(secondMatch[1]);
    }
    return 0;
  }

  private async getVerifyState(): Promise<OnlineEBookVerifyState> {
    const fallback: OnlineEBookVerifyState = {
      url: '',
      title: '',
      isVerifyEntry: false,
      cooldownText: '',
      canRetryVerification: false
    };
    try {
      const script = `JSON.stringify({
        url: location.href || '',
        title: document.title || '',
        isVerifyEntry: (location.pathname || '').includes('verify_entry') || (document.title || '').includes('安全检查'),
        cooldownText: (document.querySelector('.cooldown-time') && document.querySelector('.cooldown-time').textContent) ? document.querySelector('.cooldown-time').textContent.trim() : '',
        canRetryVerification: typeof window.retryVerification === 'function'
      })`;
      const resultStr = await new Promise<string>((resolve, reject) => {
        this.webViewController.runJavaScript(script, (error: Error | null, result: string) => {
          if (error) {
            reject(error);
          } else {
            resolve(String(result));
          }
        });
      });
      let cleanResult = resultStr;
      if (cleanResult.startsWith('"') && cleanResult.endsWith('"')) {
        cleanResult = cleanResult.slice(1, -1).replace(/\\"/g, '"');
      }
      const parsed = JSON.parse(cleanResult) as Record<string, Object>;
      return {
        url: String(parsed['url'] || ''),
        title: String(parsed['title'] || ''),
        isVerifyEntry: Boolean(parsed['isVerifyEntry']),
        cooldownText: String(parsed['cooldownText'] || ''),
        canRetryVerification: Boolean(parsed['canRetryVerification'])
      };
    } catch (error) {
      logger.warn(TAG, `读取在线电子书验证状态失败: ${String(error)}`);
      return fallback;
    }
  }

  private async triggerVerificationRetry(): Promise<boolean> {
    try {
      const resultStr = await new Promise<string>((resolve, reject) => {
        this.webViewController.runJavaScript(
          `(() => { if (typeof window.retryVerification === 'function') { window.retryVerification(); return 'true'; } return 'false'; })()`,
          (error: Error | null, result: string) => {
            if (error) {
              reject(error);
            } else {
              resolve(String(result));
            }
          }
        );
      });
      const normalized = resultStr.replace(/^"+|"+$/g, '').trim().toLowerCase();
      return normalized === 'true';
    } catch (error) {
      logger.warn(TAG, `触发在线电子书站点验证失败: ${String(error)}`);
      return false;
    }
  }

  private scheduleDetailRecovery(retryAttempt: number, delayMs: number, statusText: string): void {
    if (this.detailRecoveryTimer >= 0) {
      clearTimeout(this.detailRecoveryTimer);
      this.detailRecoveryTimer = -1;
    }
    this.beginDetailRecovery(statusText);
    this.detailRecoveryTimer = setTimeout(() => {
      this.detailRecoveryTimer = -1;
      void this.loadBookDetail(retryAttempt);
    }, delayMs);
  }

  private beginDetailRecovery(statusText: string): void {
    this.detailRecoveryInProgress = true;
    this.detailRecoveryStatusText = statusText;
    if (this.bookInfo) {
      this.bookInfo.description = statusText;
    }
    this.isLoading = false;
    if (this.autoStartDownload) {
      this.downloadButtonState = DownloadButtonState.LOADING;
      this.downloadPhase = 'recovering_detail';
    }
  }

  private endDetailRecovery(): void {
    this.detailRecoveryInProgress = false;
    this.detailRecoveryStatusText = '';
  }

  private async retryLoadBookDetailAfterVerification(retryAttempt: number): Promise<void> {
    const verifyState: OnlineEBookVerifyState = await this.getVerifyState();
    const cooldownSeconds: number = this.parseCooldownTextToSeconds(verifyState.cooldownText);
    if (cooldownSeconds > 0) {
      const delayMs: number = Math.max(5000, (cooldownSeconds * 1000) + 1500);
      this.scheduleDetailRecovery(retryAttempt, delayMs, `站点安全验证冷却中，约 ${verifyState.cooldownText} 后自动重试...`);
      return;
    }
    if (verifyState.canRetryVerification) {
      const triggered: boolean = await this.triggerVerificationRetry();
      if (triggered) {
        this.scheduleDetailRecovery(retryAttempt, 6500, `正在通过站点安全验证（第 ${retryAttempt}/${this.detailRecoveryMaxAttempts} 次）...`);
        return;
      }
    }
    this.scheduleDetailRecovery(retryAttempt, 2000 * retryAttempt, `站点安全验证中，正在第 ${retryAttempt}/${this.detailRecoveryMaxAttempts} 次重试...`);
  }

  private startAutoDownloadIfNeeded(): void {
    if (!this.autoStartDownload || this.autoStartTriggered) {
      return;
    }
    this.autoStartTriggered = true;
    this.downloadButtonState = DownloadButtonState.LOADING;
    this.downloadPhase = 'fetching_sources';
    void this.startDownloadFlow();
  }

  private async loadBookDetail(retryAttempt: number = 0): Promise<void> {
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
          const detail = result.data as Record<string, Object>;
          if (this.isInvalidBookDetailResult(detail)) {
            logger.warn(TAG, `在线电子书详情命中非目标页面，保留缓存信息: id=${String(detail['id'] || '')}, title=${String(detail['title'] || '')}`);
            if (retryAttempt < this.detailRecoveryMaxAttempts) {
              void this.retryLoadBookDetailAfterVerification(retryAttempt + 1);
              return;
            }
            this.beginDetailRecovery('站点仍在安全验证中，稍后会继续补全详情。');
            logger.info(TAG, `电子书详情已设置: ${this.bookInfo.title}`);
            return;
          }
          this.endDetailRecovery();
          this.bookInfo = {
            id: this.bookId,
            title: String(detail['title'] || this.cachedTitle || '未知书名'),
            cover: String(detail['cover'] || (this.cachedCover && !this.cachedCover.includes('/img/logo') && !this.cachedCover.endsWith('.svg') ? this.cachedCover : '') || ''),
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

          // 直接从详情页提取的下载链接（getBookDetail workflow会提取）
          const detailDownloadLinks = detail['downloadLinks'] as DownloadLink[] | undefined;
          if (detailDownloadLinks && Array.isArray(detailDownloadLinks) && detailDownloadLinks.length > 0) {
            this.bookInfo.downloadLinks = detailDownloadLinks;
            logger.info(TAG, `从详情页提取到 ${detailDownloadLinks.length} 个下载链接`);
          }

          logger.info(TAG, `电子书详情加载成功: ${this.bookInfo.title}`);
          // 更新封面：如果 WebView 获取到了新的封面 URL 且当前没有已加载的封面
          if (this.bookInfo.cover && !this.coverPixelMap) {
            this.cachedCover = this.bookInfo.cover;
            void this.loadCoverImage();
          }
          this.startAutoDownloadIfNeeded();
        } else {
          logger.warn(TAG, `获取电子书详情失败: ${result.error}`);
          this.bookInfo.description = '无法获取详细信息';
          this.startAutoDownloadIfNeeded();
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
      await this.authManager.applyCookiesToController(this.sourceId, this.webViewController);
      
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
    logger.info(TAG, `开始下载流程: bookId=${this.bookId}`);

    if (!this.mangaSourceEngine) {
      logger.error(TAG, '引擎未初始化');
      return;
    }

    // 检查是否已有下载任务
    const existingTask = this.globalDownloadManager.getEBookTask(this.bookId);
    if (existingTask) {
      this.currentDownloadTask = existingTask;
      this.downloadProgress = existingTask.progress;
      this.updateUIFromTaskStatus(existingTask.status);
      if (existingTask.status === TaskStatus.COMPLETED) {
        logger.info(TAG, `电子书已下载: ${existingTask.savePath}`);
        await this.handleCompletedDownloadTask(existingTask, this.autoStartDownload);
        return;
      }
    }

    // 检查是否已有从详情页提取的下载链接
    if (this.bookInfo && this.bookInfo.downloadLinks.length > 0) {
      logger.info(TAG, `使用详情页提取的下载链接: ${this.bookInfo.downloadLinks.length} 个`);
      const sources: DownloadSource[] = [];
      for (let i = 0; i < this.bookInfo.downloadLinks.length; i++) {
        const link: DownloadLink = this.bookInfo.downloadLinks[i];
        const source: DownloadSource = {
          id: `detail_${i}`,
          name: link.format.toUpperCase(),
          url: link.url,
          recommended: i === 0,
          available: true
        };
        sources.push(source);
      }
      await this.presentDownloadSources(sources);
      return;
    }

    // 开始获取下载源
    this.downloadButtonState = DownloadButtonState.LOADING;
    this.downloadPhase = 'fetching_sources';
    logger.info(TAG, `设置下载状态: LOADING, phase=fetching_sources`);

    try {
      // 使用WebView引擎获取下载源
      const params: Record<string, Object> = {};
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
        }
        
        if (sources.length > 0) {
          await this.presentDownloadSources(sources);
        } else {
          throw new Error('未找到可用的下载源');
        }
      } else if (this.shouldFallbackToLegacyDownloadWorkflow('getDownloadSources', result.error || '')) {
        logger.info(TAG, '任务式下载源获取不可用，回退到旧电子书工作流');
        await this.startLegacyDownloadFlow();
      } else {
        throw new Error(result.error || '获取下载源失败');
      }
    } catch (error) {
      logger.error(TAG, `获取下载源失败: ${String(error)}`);
      this.downloadButtonState = DownloadButtonState.FAILED;
      this.downloadPhase = 'failed';
    }
  }

  private shouldFallbackToLegacyDownloadWorkflow(taskId: string, errorText: string): boolean {
    const normalizedError = String(errorText || '');
    return normalizedError.includes(`任务未找到: ${taskId}`);
  }

  private async startLegacyDownloadFlow(): Promise<void> {
    if (!this.mangaSourceEngine) {
      throw new Error('图源引擎未初始化');
    }

    const chapterResult = await this.mangaSourceEngine.getChapterList(this.bookId);
    if (!chapterResult.success || !chapterResult.data || chapterResult.data.length <= 0) {
      throw new Error(chapterResult.error || '旧工作流未返回可用下载源');
    }

    const sources = this.buildLegacyDownloadSources(chapterResult.data);
    if (sources.length <= 0) {
      throw new Error('旧工作流未解析出可用下载源');
    }

    logger.info(TAG, `旧工作流解析到 ${sources.length} 个下载源`);
    await this.presentDownloadSources(sources);
  }

  private buildLegacyDownloadSources(chapters: SourceChapterInfo[]): DownloadSource[] {
    const sources: DownloadSource[] = [];
    const seen: Record<string, boolean> = {};

    for (let i = 0; i < chapters.length; i++) {
      const chapter = chapters[i];
      const url = String(chapter.url || '');
      const name = String(chapter.title || `下载源 ${i + 1}`).trim();
      const key = `${name}|${url}`.toLowerCase();
      if (key.length <= 1 || seen[key]) {
        continue;
      }
      seen[key] = true;
      sources.push({
        id: `legacy_${i}_${chapter.id || chapter.externalId || name}`,
        name: name,
        url: url,
        recommended: i === 0,
        available: true
      });
    }

    return sources;
  }

  private async presentDownloadSources(sources: DownloadSource[]): Promise<void> {
    this.downloadSources = sources;
    const autoSelectedSource = this.pickAutoSelectedSource(sources);
    if (autoSelectedSource !== null) {
      logger.info(TAG, `自动选择下载源: ${autoSelectedSource.name}`);
      await this.handleSourceSelect(autoSelectedSource);
      return;
    }

    this.showSourceSelector = true;
    this.downloadButtonState = DownloadButtonState.IDLE;
    this.downloadPhase = 'selecting_source';
    logger.info(TAG, `显示下载源选择器，共 ${sources.length} 个源`);
  }

  private pickAutoSelectedSource(sources: DownloadSource[]): DownloadSource | null {
    for (let i = 0; i < sources.length; i++) {
      const candidate = sources[i];
      if (candidate.recommended && candidate.available !== false) {
        return candidate;
      }
    }
    if (sources.length === 1) {
      return sources[0];
    }
    return null;
  }

  private parseDownloadSourcesResult(result: TaskResult): DownloadSourcesParseResult {
    const sources: DownloadSource[] = [];
    let formSubmitted: boolean = false;
    let parseError: string | null = null;
    try {
      const stepData: Object | undefined = result.stepResults['step2_waitSources'];
      let data: Object | undefined = stepData ? stepData : result.data;
      
      logger.debug(TAG, `解析下载源原始数据类型: ${typeof data}`);
      if (!data) {
        logger.warn(TAG, `下载源数据为空`);
        return { sources: sources, formSubmitted: false, error: '下载源数据为空' };
      }

      // 处理可能的双重JSON编码
      let parsed: Object;
      if (typeof data === 'string') {
        parsed = JSON.parse(data) as Object;
        if (typeof parsed === 'string') {
          logger.debug(TAG, `检测到双重JSON编码，再次解析`);
          parsed = JSON.parse(parsed) as Object;
        }
      } else {
        parsed = data;
      }

      // 检查是否是新格式（包含 sources 字段）
      let sourceList: Object[];
      if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
        const parsedRecord = parsed as Record<string, Object>;
        if (parsedRecord['sources'] !== undefined) {
          // 提取 formSubmitted 和 error
          formSubmitted = Boolean(parsedRecord['formSubmitted']);
          if (parsedRecord['error']) {
            parseError = String(parsedRecord['error']);
          }
          logger.info(TAG, `[解析] 表单提交状态: ${formSubmitted}, 错误: ${parseError || 'none'}`);
          
          const parsedSources = parsedRecord['sources'];
          sourceList = Array.isArray(parsedSources) ? parsedSources as Object[] : [];
          // 记录调试信息
          if (parsedRecord['debug']) {
            const debug = parsedRecord['debug'] as Record<string, Object>;
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
        sourceList = parsed as Object[];
      } else {
        logger.warn(TAG, `下载源数据格式不支持: ${typeof parsed}`);
        return { sources: sources, formSubmitted: false, error: '数据格式不支持' };
      }

      logger.info(TAG, `解析到 ${sourceList.length} 个下载源`);
      
      for (let i = 0; i < sourceList.length; i++) {
        const item = sourceList[i] as Record<string, Object>;
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
    
    // 如果没找到直接链接，尝试查找旧式 onclick 中的 href 链接
    if (formats.length === 0) {
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

    // 兼容 temporary_link 页面中的 window.location.href='...' 写法
    if (formats.length === 0) {
      const locationPattern = /window\.location\.href=['"]([^'"]*\.(epub|mobi|pdf|azw3|txt)[^'"]*)['"]/gi;
      while ((match = locationPattern.exec(html)) !== null) {
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
          logger.debug(TAG, `[HTML解析] 从window.location.href找到文件: format=${format}`);
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
      
      const params: Record<string, Object> = {};
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
      const params: Record<string, Object> = {};
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
      } else if (this.shouldFallbackToLegacyDownloadWorkflow('getFileListFromSource', result?.error || '')) {
        logger.info(TAG, `任务式文件列表获取不可用，回退到旧电子书工作流: ${source.name}`);
        await this.handleLegacySourceSelect(source);
      } else {
        throw new Error(result?.error || '获取文件列表失败');
      }
    } catch (error) {
      logger.error(TAG, `获取文件列表失败: ${String(error)}`);
      this.downloadButtonState = DownloadButtonState.FAILED;
      this.downloadPhase = 'failed';
    }
  }

  private async handleLegacySourceSelect(source: DownloadSource): Promise<void> {
    if (!this.mangaSourceEngine) {
      throw new Error('图源引擎未初始化');
    }

    // 如果源URL是直接下载链接（包含文件扩展名或 /dl/ 端点），直接使用
    // /dl/ 链接由 handleFormatSelect 通过 WebView fetch 下载（绕过 Cloudflare）
    const sourceUrl = String(source.url || '');
    const isDirectDownload = sourceUrl.includes('/dl/') || sourceUrl.includes('/download/') ||
      /\.(epub|pdf|mobi|azw3|txt|djvu)(?:\b|\?)/i.test(sourceUrl);

    let formats: FileFormat[] = [];

    if (isDirectDownload) {
      logger.info(TAG, `源URL是直接下载链接，跳过getPageList: ${sourceUrl.substring(0, 80)}`);
      const directFormat = this.buildDirectFormatFromSource(source);
      if (directFormat !== null) {
        formats.push(directFormat);
      }
    } else {
      const pageResult = await this.mangaSourceEngine.getPageList(source.url, this.bookId);
      if (pageResult.success && pageResult.data && pageResult.data.length > 0) {
        formats = this.buildLegacyFileFormats(pageResult.data, source);
      }

      if (formats.length <= 0) {
        const fallbackFormat = this.buildDirectFormatFromSource(source);
        if (fallbackFormat !== null) {
          formats.push(fallbackFormat);
        }
      }
    }

    if (formats.length <= 0) {
      throw new Error('旧工作流未找到可下载的文件');
    }

    this.fileFormats = formats;
    this.showFormatSelector = true;
    this.downloadButtonState = DownloadButtonState.IDLE;
    this.downloadPhase = 'selecting_format';
    logger.info(TAG, `旧工作流解析到 ${formats.length} 个文件格式`);
  }

  private buildLegacyFileFormats(pages: SourcePageInfo[], source: DownloadSource): FileFormat[] {
    const formats: FileFormat[] = [];
    const seen: Record<string, boolean> = {};

    for (let i = 0; i < pages.length; i++) {
      const page = pages[i];
      const url = String(page.imageUrl || '');
      const format = this.inferFormat(source.name, url);
      if (format.length <= 0 || seen[format]) {
        continue;
      }
      seen[format] = true;
      formats.push({
        format: format,
        displayName: this.getFormatDisplayName(format, source.name),
        url: url,
        available: true
      });
    }

    return formats;
  }

  private buildDirectFormatFromSource(source: DownloadSource): FileFormat | null {
    const format = this.inferFormat(source.name, source.url);
    if (format.length <= 0 || source.url.length <= 0) {
      return null;
    }
    return {
      format: format,
      displayName: this.getFormatDisplayName(format, source.name),
      url: source.url,
      available: true
    };
  }

  private inferFormat(sourceName: string, url: string): string {
    const normalizedName = String(sourceName || '').toLowerCase();
    const normalizedUrl = String(url || '').toLowerCase();

    if (normalizedUrl.includes('.epub') || normalizedUrl.includes('.epub3') || normalizedName.includes('epub')) {
      return 'epub';
    }
    if (normalizedUrl.includes('.txt') || normalizedName.includes('plain text') || normalizedName.includes('txt')) {
      return 'txt';
    }
    if (normalizedUrl.includes('.pdf') || normalizedName.includes('pdf')) {
      return 'pdf';
    }
    if (normalizedUrl.includes('.azw3') || normalizedName.includes('azw3')) {
      return 'azw3';
    }
    if (normalizedUrl.includes('.mobi') || normalizedUrl.includes('.kf8') || normalizedUrl.includes('.kindle') ||
      normalizedName.includes('kindle') || normalizedName.includes('mobi')) {
      return 'mobi';
    }
    return '';
  }

  private getFormatDisplayName(format: string, sourceName: string): string {
    if (sourceName.trim().length > 0) {
      return sourceName;
    }
    return format.toUpperCase();
  }

  private parseFileFormats(result: TaskResult): FileFormat[] {
    const formats: FileFormat[] = [];
    try {
      const stepData: Object | undefined = result.stepResults['step2_extractFiles'];
      let data: Object | undefined = stepData ? stepData : result.data;
      if (!data) return formats;

      // 处理可能的双重JSON编码
      if (typeof data === 'string') {
        let parsed: Object = JSON.parse(data) as Object;
        if (typeof parsed === 'string') {
          parsed = JSON.parse(parsed) as Object;
        }
        data = parsed;
      }

      // 检查是否是新格式（包含 debug 和 files 字段）
      let fileList: Object[];
      if (data && typeof data === 'object' && !Array.isArray(data)) {
        const dataRecord = data as Record<string, Object>;
        // 记录调试信息
        if (dataRecord['debug']) {
          const debug = dataRecord['debug'] as Record<string, Object>;
          logger.info(TAG, `[文件列表调试] URL: ${debug['url']}, 是否临时链接: ${debug['isTemporaryLink']}, 有file-list: ${debug['hasFileList']}, file-item数量: ${debug['fileItemCount']}`);
          if (debug['bodyText']) {
            logger.info(TAG, `[文件列表调试] 页面内容: ${String(debug['bodyText']).substring(0, 200)}`);
          }
        }
        const filesValue = dataRecord['files'];
        fileList = Array.isArray(filesValue) ? filesValue as Object[] : [];
      } else if (Array.isArray(data)) {
        fileList = data as Object[];
      } else {
        return formats;
      }

      for (let i = 0; i < fileList.length; i++) {
        const item = fileList[i] as Record<string, Object>;
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
    this.importErrorMessage = '';
    this.importStatusText = '';

    if (!format.url) {
      logger.error(TAG, '下载链接不可用');
      this.downloadButtonState = DownloadButtonState.FAILED;
      return;
    }

    try {
      const downloadUrl = format.url;
      const bookTitle = this.bookInfo?.title || this.cachedTitle || 'ebook';

      if (downloadUrl.includes('/dl/')) {
        // /dl/ 链接被 Cloudflare 保护，HTTP 请求会返回 503
        // 策略：通过 WebView 导航处理 Cloudflare，onLoadIntercept 捕获重定向 URL
        logger.info(TAG, `检测到 /dl/ 链接，使用 WebView 导航: ${downloadUrl.substring(0, 80)}`);
        this.importStatusText = '正在通过浏览器下载...';
        this.isWaitingForDlRedirect = true;
        this.dlOriginalUrl = downloadUrl;
        this.dlBookTitle = bookTitle;
        this.dlFileFormat = format.format;

        // 通过 JS 导航 WebView 到下载链接
        const navScript: string = `window.location.href = '${downloadUrl}'; 'navigating';`;
        this.webViewController.runJavaScript(navScript, (error: Error | null, result: string) => {
          if (error) {
            logger.error(TAG, `导航失败: ${error.message}`);
            this.isWaitingForDlRedirect = false;
            this.downloadButtonState = DownloadButtonState.FAILED;
            this.downloadPhase = 'failed';
            this.importErrorMessage = '下载失败，请重试';
          } else {
            logger.info(TAG, `WebView 导航已触发`);
          }
        });

        // 超时机制：30秒内未捕获重定向则失败
        setTimeout(() => {
          if (this.isWaitingForDlRedirect) {
            logger.error(TAG, `等待重定向超时`);
            this.isWaitingForDlRedirect = false;
            this.downloadButtonState = DownloadButtonState.FAILED;
            this.downloadPhase = 'failed';
            this.importErrorMessage = '下载超时，请重试';
          }
        }, 30000);
      } else {
        // 普通 URL 使用 HTTP 下载
        const taskId = await this.globalDownloadManager.createEBookDownloadTask(
          this.bookId,
          bookTitle,
          downloadUrl,
          format.format,
          this.sourceId
        );

        logger.info(TAG, `电子书下载任务已创建: ${taskId}`);
        this.pollDownloadProgress(taskId);
      }
    } catch (error) {
      logger.error(TAG, `创建下载任务失败: ${String(error)}`);
      this.downloadButtonState = DownloadButtonState.FAILED;
      this.downloadPhase = 'failed';
    }
  }

  /**
   * 使用捕获的 CDN URL 下载文件
   * onLoadIntercept 拦截到重定向 URL 后调用
   */
  private async downloadFromCapturedUrl(cdnUrl: string): Promise<void> {
    try {
      const bookTitle: string = this.dlBookTitle;
      const fileFormat: string = this.dlFileFormat;
      const safeTitle: string = bookTitle.replace(/[/\\:*?"<>|]/g, '_');
      const hostCtx = (this.getUIContext().getHostContext() as common.UIAbilityContext) as common.UIAbilityContext;
      const saveDir: string = `${hostCtx.filesDir}/ebooks/${this.bookId}`;
      fs.mkdirSync(saveDir, true);
      const filePath: string = `${saveDir}/${safeTitle}.${fileFormat}`;

      logger.info(TAG, `使用 request.agent 下载: ${cdnUrl.substring(0, 80)}`);
      this.importStatusText = '正在下载文件...';

      const headers: Record<string, string> = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
      };

      await this.globalDownloadManager.downloadFileWithAgent(
        cdnUrl, filePath, headers,
        (received: number, total: number) => {
          if (total > 0) {
            const pct: number = Math.floor((received / total) * 100);
            this.downloadProgress = pct;
          }
        }
      );

      logger.info(TAG, `下载完成: ${filePath}`);

      // 注册下载任务
      const taskId: string = await this.globalDownloadManager.registerEBookDownloadTask(
        this.bookId, bookTitle, filePath, fileFormat, this.sourceId
      );
      this.pollDownloadProgress(taskId);
    } catch (error) {
      logger.error(TAG, `下载失败: ${String(error)}`);
      this.downloadButtonState = DownloadButtonState.FAILED;
      this.downloadPhase = 'failed';
      this.importErrorMessage = '下载失败，请重试';
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
        logger.info(TAG, `电子书下载完成: ${task.savePath}`);
        void this.handleCompletedDownloadTask(task, this.autoStartDownload);
      } else if (task.status === TaskStatus.FAILED) {
        this.downloadPhase = 'failed';
        logger.error(TAG, `电子书下载失败: ${task.error}`);
      }
    };

    checkProgress();
  }

  private async handleCompletedDownloadTask(task: DownloadTaskInfo, openAfterImport: boolean): Promise<void> {
    this.currentDownloadTask = task;
    this.downloadProgress = 100;
    this.downloadPhase = 'importing';
    this.downloadButtonState = DownloadButtonState.LOADING;
    this.importStatusText = '正在导入书库...';

    if (this.importInProgress) {
      logger.info(TAG, '电子书导入已在进行中，跳过重复触发');
      return;
    }

    this.importInProgress = true;
    try {
      const existingBook = await this.ebookDataManager.getEBookByFilePath(task.savePath);
      if (existingBook) {
        this.importedBookId = existingBook.id;
        this.importStatusText = '已导入书库';
        this.importErrorMessage = '';
        this.downloadPhase = 'completed';
        this.downloadButtonState = DownloadButtonState.COMPLETED;
        logger.info(TAG, `下载文件已存在于书库: ${existingBook.id}`);
      } else {
        const importedBook = await this.onlineEBookImportService.importDownloadedBook(task.savePath);
        this.importedBookId = importedBook.id;
        this.importStatusText = '已导入书库';
        this.importErrorMessage = '';
        this.downloadPhase = 'completed';
        this.downloadButtonState = DownloadButtonState.COMPLETED;
        this.getUIContext().getPromptAction().showToast({ message: `已导入书库: ${importedBook.metadata.title}`, duration: 1600 });
      }

      if (openAfterImport && this.importedBookId.length > 0) {
        this.openImportedBookReader();
      }
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      this.importErrorMessage = `导入失败: ${errorMessage}`;
      this.importStatusText = '';
      this.downloadButtonState = DownloadButtonState.FAILED;
      this.downloadPhase = 'failed';
      logger.error(TAG, `下载完成后导入电子书失败: ${errorMessage}`);
    } finally {
      this.importInProgress = false;
    }
  }

  private openImportedBookReader(): void {
    if (this.importedBookId.length <= 0) {
      return;
    }

    const params: EBookReaderParams = {
      bookId: this.importedBookId,
      readerTitle: this.getBookTitle()
    };
    const opened = openEBookReaderRouterPage(this.getUIContext(), params, TAG);
    if (!opened) {
      this.getUIContext().getPromptAction().showToast({ message: '无法打开本地阅读器', duration: 1500 });
    }
  }

  build() {
    HdsNavDestination() {
      Stack() {
        // Layer 1: Background
        SharedPageBackgroundLayer({
          defaultBackgroundColor: AppColors.background,
          mode: GlobalBackgroundLayerMode.IMMERSIVE
        })
          .width('100%')
          .height('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        // Layer 4: Hidden WebView (needs minimum size for Cloudflare JS execution)
        Web({ src: 'about:blank', controller: this.webViewController })
          .width(100)
          .height(100)
          .opacity(0)
          .position({ x: -100, y: -100 })
          .onControllerAttached(() => {
            logger.info(TAG, 'WebView控制器已附加');
          })
          .onPageBegin((event) => {
            logger.debug(TAG, `在线电子书隐藏WebView页面开始加载: ${event.url}`);
            if (this.sourceId > 0) {
              void this.authManager.applyCookiesToController(this.sourceId, this.webViewController);
            }
          })
          .onPageEnd((event) => {
            logger.debug(TAG, `在线电子书隐藏WebView页面加载完成: ${event.url}`);
            if (this.sourceId > 0) {
              void this.authManager.captureCookiesFromController(this.sourceId, this.webViewController);
            }
            // 备选方案：如果 onLoadIntercept 未捕获重定向，检查 onPageEnd 中的 URL
            if (this.isWaitingForDlRedirect && !event.url.includes('/dl/') && event.url !== 'about:blank') {
              logger.info(TAG, `onPageEnd 检测到重定向: ${event.url.substring(0, 80)}`);
              this.isWaitingForDlRedirect = false;
              void this.downloadFromCapturedUrl(event.url);
            }
          })
          .onLoadIntercept((event) => {
            const req = event.data;
            const url: string = typeof req === 'string' ? req : req.getRequestUrl();
            logger.debug(TAG, `onLoadIntercept: ${url}, isWaiting=${this.isWaitingForDlRedirect}`);

            if (this.isWaitingForDlRedirect) {
              if (url.includes('/dl/') && url !== this.dlOriginalUrl) {
                // 重定向到新的 /dl/ URL（Cloudflare 解决后的重试）
                return false; // 放行
              }
              if (!url.includes('/dl/')) {
                // 重定向到 CDN URL（实际文件地址）
                logger.info(TAG, `捕获重定向 URL: ${url.substring(0, 80)}`);
                this.isWaitingForDlRedirect = false;
                void this.downloadFromCapturedUrl(url);
                return true; // 阻止 WebView 加载
              }
            }
            return false; // 默认放行
          })

        // Layer 2: Content
        if (this.isLoading) {
          this.buildLoadingSkeleton()
        } else if (this.errorMessage.length > 0 && !this.bookInfo) {
          this.buildErrorState()
        } else {
          Scroll(this.scroller) {
            Column({ space: 16 }) {
              Blank().height(SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight))
              this.buildBookInfoCard()
              if (this.bookInfo?.description) {
                this.buildDescriptionCard()
              }
              if (this.sourceId > 0) {
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
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        }

        // Layer 3: Immersive Title Bar
        SettingsImmersiveTitleBar({
          themeState: this.themeState,
          title: this.getBookTitle(),
          appFontFamily: this.appFontFamily,
          backAction: (): boolean => {
            try {
              this.pathStack.pop();
              return true;
            } catch (_error) {
              return false;
            }
          }
        })
      }
    }
    .hideTitleBar(true)
    .backgroundColor(AppColors.background)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP])
    .onReady((context: NavDestinationContext) => {
      const params = context.pathInfo.param as OnlineEBookDetailPageParams;
      if (params) {
        this.initializePage(params);
      }
    })
  }

  @Builder
  buildLoadingSkeleton() {
    Column({ space: 16 }) {
      Blank().height(SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight))
      this.buildBookInfoCardSkeleton()
      this.buildDescriptionCardSkeleton()
      this.buildDownloadCardSkeleton()
      Blank().height(this.navigationBarHeight + 20)
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
  }

  @Builder
  buildBookInfoCardSkeleton() {
    Row({ space: 16 }) {
      Blank()
        .width(120)
        .height(180)
        .borderRadius(8)
        .backgroundColor(AppColors.surfaceContainerHighest)

      Column({ space: 8 }) {
        Blank()
          .width('80%')
          .height(20)
          .borderRadius(10)
          .backgroundColor(AppColors.surfaceContainerHighest)
        Blank()
          .width('50%')
          .height(14)
          .borderRadius(7)
          .backgroundColor(AppColors.surfaceContainerHigh)
        Blank()
          .width('60%')
          .height(12)
          .borderRadius(6)
          .backgroundColor(AppColors.surfaceContainerHigh)
        Blank()
          .width('40%')
          .height(12)
          .borderRadius(6)
          .backgroundColor(AppColors.surfaceContainer)
        Blank()
        Blank()
          .width('30%')
          .height(11)
          .borderRadius(5)
          .backgroundColor(AppColors.surfaceContainer)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .height(180)
    }
    .width('100%')
    .padding(16)
    .backgroundColor(AppColors.surfaceContainer)
    .borderRadius(12)
  }

  @Builder
  buildDescriptionCardSkeleton() {
    Column({ space: 8 }) {
      Blank()
        .width('20%')
        .height(16)
        .borderRadius(8)
        .backgroundColor(AppColors.surfaceContainerHighest)
      Blank()
        .width('100%')
        .height(14)
        .borderRadius(7)
        .backgroundColor(AppColors.surfaceContainerHigh)
      Blank()
        .width('90%')
        .height(14)
        .borderRadius(7)
        .backgroundColor(AppColors.surfaceContainerHigh)
      Blank()
        .width('70%')
        .height(14)
        .borderRadius(7)
        .backgroundColor(AppColors.surfaceContainer)
    }
    .width('100%')
    .padding(16)
    .backgroundColor(AppColors.surfaceContainer)
    .borderRadius(12)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  buildDownloadCardSkeleton() {
    Column({ space: 12 }) {
      Blank()
        .width('15%')
        .height(16)
        .borderRadius(8)
        .backgroundColor(AppColors.surfaceContainerHighest)
      Blank()
        .width('100%')
        .height(48)
        .borderRadius(8)
        .backgroundColor(AppColors.surfaceContainerHigh)
    }
    .width('100%')
    .padding(16)
    .backgroundColor(AppColors.surfaceContainer)
    .borderRadius(12)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  buildErrorState() {
    Column({ space: 16 }) {
      Blank().height(SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight))

      Column({ space: 12 }) {
        Text('!')
          .fontSize(32)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.onError)
          .width(64)
          .height(64)
          .textAlign(TextAlign.Center)
          .backgroundColor(AppColors.errorContainer)
          .borderRadius(32)

        Text(this.errorMessage)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColors.textPrimary)
          .textAlign(TextAlign.Center)

        Text('请检查网络连接后重试')
          .fontSize(13)
          .fontColor(AppColors.textSecondary)
          .textAlign(TextAlign.Center)

        Button('重试')
          .width(160)
          .height(44)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColors.onPrimary)
          .backgroundColor(AppColors.primary)
          .borderRadius(22)
          .onClick(() => {
            this.isLoading = true;
            this.errorMessage = '';
            void this.loadBookDetail();
          })
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .padding({ left: 32, right: 32 })
    }
    .width('100%')
    .height('100%')
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
          .backgroundColor(AppColors.surfaceContainer)
      }

      Column({ space: 8 }) {
        Text(this.bookInfo?.title || this.cachedTitle || '未知书名')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.textPrimary)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (this.bookInfo?.author) {
          Text(this.bookInfo.author)
            .fontSize(14)
            .fontColor(AppColors.textSecondary)
        } else if (this.detailRecoveryInProgress) {
          Row({ space: 6 }) {
            LoadingProgress()
              .width(14)
              .height(14)
              .color(AppColors.primary)
            Text(this.detailRecoveryStatusText || '站点安全验证中...')
              .fontSize(12)
              .fontColor(AppColors.textSecondary)
          }
        }

        if (this.bookInfo?.publisher) {
          Text(this.bookInfo.publisher)
            .fontSize(12)
            .fontColor(AppColors.textTertiary)
        }

        if (this.bookInfo?.categories) {
          Text(this.bookInfo.categories)
            .fontSize(12)
            .fontColor(AppColors.primary)
        }

        Blank()

        Row({ space: 4 }) {
          Text('来源:')
            .fontSize(11)
            .fontColor(AppColors.textTertiary)
          Text(this.sourceInfo?.name || '')
            .fontSize(11)
            .fontColor(AppColors.warning)
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .height(180)
    }
    .width('100%')
    .padding(16)
    .backgroundColor(AppColors.surfaceContainer)
    .borderRadius(12)
  }

  @Builder
  buildDescriptionCard() {
    Column({ space: 8 }) {
      Text('简介')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppColors.textPrimary)

      Text(this.bookInfo?.description || '')
        .fontSize(14)
        .fontColor(AppColors.textSecondary)
        .maxLines(this.expandedDescription ? 100 : 4)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .onClick(() => {
          this.expandedDescription = !this.expandedDescription;
        })

      if (!this.expandedDescription && (this.bookInfo?.description?.length || 0) > 100) {
        Text('展开')
          .fontSize(12)
          .fontColor(AppColors.primary)
          .onClick(() => {
            this.expandedDescription = true;
          })
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(AppColors.surfaceContainer)
    .borderRadius(12)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  buildDownloadCard() {
    Column({ space: 12 }) {
      Text('下载')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppColors.textPrimary)

      // 下载源选择器
      if (this.showSourceSelector && this.downloadSources.length > 0) {
        DownloadSourceSelector({
          sources: this.downloadSources,
          isLoading: false,
          selectedId: this.selectedSourceId,
          onSelect: (source: DownloadSource) => {
            this.handleSourceSelect(source);
          },
          config: {
            title: '选择下载源',
            showRecommendedBadge: true
          }
        })
      }
      // 格式选择器
      else if (this.showFormatSelector && this.fileFormats.length > 0) {
        FileFormatSelector({
          formats: this.fileFormats,
          selectedFormat: this.selectedFormat,
          onSelect: (format: FileFormat) => {
            this.handleFormatSelect(format);
          },
          config: {
            title: '选择格式',
            layout: 'grid',
            showSize: true
          }
        })
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
    .backgroundColor(AppColors.surfaceContainer)
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
          .backgroundColor(AppColors.primaryContainer)
          .borderRadius(8)
      }

      Row({ space: 8 }) {
        if (this.downloadButtonState === DownloadButtonState.LOADING ||
            this.downloadButtonState === DownloadButtonState.DOWNLOADING) {
          LoadingProgress()
            .width(20)
            .height(20)
            .color(AppColors.onPrimary)
        }

        Text(this.getDownloadButtonText())
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColors.onPrimary)
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
      if (this.importedBookId.length > 0) {
        this.openImportedBookReader();
        return;
      }
      if (this.downloadButtonState === DownloadButtonState.IDLE ||
          this.downloadButtonState === DownloadButtonState.FAILED) {
        void this.startDownloadFlow();
      }
    })
  }

  private getDownloadButtonText(): string {
    if (this.importedBookId.length > 0 && !this.importInProgress) {
      return '打开本地阅读';
    }

    switch (this.downloadButtonState) {
      case DownloadButtonState.LOADING:
        // 根据下载阶段显示不同的提示
        switch (this.downloadPhase) {
          case 'recovering_detail':
            return '正在验证站点...';
          case 'fetching_sources':
            return '正在搜索下载源...';
          case 'fetching_files':
            return '正在获取文件列表...';
          case 'importing':
            return '正在导入书库...';
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
        return this.importedBookId.length > 0 ? '打开本地阅读' : '下载完成';
      case DownloadButtonState.FAILED:
        return '下载失败，点击重试';
      default:
        return '下载电子书';
    }
  }

  private getDownloadButtonColor(): ResourceColor {
    switch (this.downloadButtonState) {
      case DownloadButtonState.COMPLETED:
        return AppColors.success;
      case DownloadButtonState.FAILED:
        return AppColors.error;
      default:
        return AppColors.primary;
    }
  }

  private getFormatColor(format: string): ResourceColor {
    const colorMap: Record<string, string> = {
      'epub': AppColors.success,
      'mobi': AppColors.warning,
      'pdf': AppColors.error,
      'azw3': AppColors.tertiary,
      'txt': AppColors.secondary
    };
    const lowerFormat = format.toLowerCase();
    if (colorMap[lowerFormat]) {
      return colorMap[lowerFormat];
    }
    return AppColors.info;
  }

  @Builder
  buildTaskProgress() {
    Column({ space: 8 }) {
      // 进度条
      Progress({ value: this.downloadProgress, total: 100, type: ProgressType.Linear })
        .width('100%')
        .height(4)
        .color(AppColors.primary)
        .backgroundColor(AppColors.surfaceContainerHigh)
        .borderRadius(2)

      // 当前状态
      Row({ space: 8 }) {
        Text(this.getPhaseIcon())
          .fontSize(12)
          .fontColor(this.getPhaseColor())
          .width(16)

        Text(this.getPhaseText())
          .fontSize(12)
          .fontColor(AppColors.textSecondary)
          .layoutWeight(1)

        if (this.downloadPhase === 'downloading' || this.downloadPhase === 'fetching_sources' ||
          this.downloadPhase === 'fetching_files' || this.downloadPhase === 'importing') {
          LoadingProgress()
            .width(14)
            .height(14)
            .color(AppColors.primary)
        }
      }
      .width('100%')

      // 错误信息
      if (this.currentDownloadTask?.error) {
        Text(this.currentDownloadTask.error)
          .fontSize(12)
          .fontColor(AppColors.error)
          .width('100%')
          .padding(8)
          .backgroundColor(AppColors.errorContainer)
          .borderRadius(6)
      }

      if (this.importErrorMessage.length > 0) {
        Text(this.importErrorMessage)
          .fontSize(12)
          .fontColor(AppColors.error)
          .width('100%')
          .padding(8)
          .backgroundColor(AppColors.errorContainer)
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
      case 'importing':
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
        return AppColors.success;
      case 'downloading':
      case 'fetching_sources':
      case 'fetching_files':
      case 'importing':
        return AppColors.primary;
      case 'failed':
        return AppColors.error;
      default:
        return AppColors.textTertiary;
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
      case 'importing':
        return this.importStatusText.length > 0 ? this.importStatusText : '正在导入书库...';
      case 'completed':
        return this.importedBookId.length > 0 ? '已导入书库，可打开阅读' : '下载完成';
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
        return AppColors.success;
      case StepStatus.RUNNING:
        return AppColors.primary;
      case StepStatus.FAILED:
        return AppColors.error;
      case StepStatus.WAITING:
        return AppColors.warning;
      default:
        return AppColors.textTertiary;
    }
  }
}
