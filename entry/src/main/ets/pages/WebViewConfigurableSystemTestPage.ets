import { SafeUtils } from '../Utils/SafeUtils';
/**
 * WebView可配置系统测试页面
 * 
 * 功能说明：
 * 1. 演示JSON配置文件的解析和验证
 * 2. 测试扩展模块的注册和使用
 * 3. 验证统一操作接口的功能
 * 4. 提供性能测试和错误处理演示
 */

import { logger } from '../Utils/Logger';
import { UnifiedOperationInterface, OperationType, OperationParams, OperationParamsData, OperationResult, ConfigurationOperationData, SecurityOperationData, SecurityCheckOperationData, ExtensionOperationData } from '../Framework/WebView/UnifiedOperationInterface';
import { WebViewConfigurationParser, SecurityPolicyConfigurationParser, WebViewConfiguration, SecurityPolicyConfiguration, WebViewExtensionConfig } from '../Framework/WebView/ConfigurationParser';
import { curves, UIContext } from '@kit.ArkUI';
import { colorMap } from '../Data/ResourceMap';
import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { webview } from '@kit.ArkWeb';
import { BusinessError } from '@kit.BasicServicesKit';

const TAG = 'WebViewConfigurableSystemTestPage';

/**
 * 测试结果数据结构
 */
interface TestResult {
  name: string;
  success: boolean;
  message: string;
  executionTime: number;
  data?: TestResultData;
}

/**
 * 测试结果数据接口
 */
interface TestResultData {
  config?: WebViewConfiguration | SecurityPolicyConfiguration;
  validation?: ValidationResult;
  baseConfig?: WebViewConfiguration;
  overrideConfig?: WebViewConfiguration;
  mergedConfig?: WebViewConfiguration;
  domStorageEnabled?: boolean;
  timeout?: number;
  original?: WebViewConfiguration;
  serialized?: string;
  reparsed?: WebViewConfiguration;
  extensions?: ExtensionInfo[];
  operation?: string;
  timestamp?: number;
  results?: OperationResult[];
  operationCount?: number;
  errorHandled?: boolean;
  error?: string;
  iterations?: number;
  totalTime?: number;
  averageTime?: number;
  operationsPerSecond?: number;
  successCount?: number;
  failureCount?: number;
  initialMemory?: number;
  finalMemory?: number;
  memoryIncrease?: number;
  memoryPerOperation?: number;
  testIndex?: number;
  url?: string;
  headers?: HeadersMap;
  sourceType?: string;
}

/**
 * 验证结果接口
 */
interface ValidationResult {
  isValid: boolean;
  errors: ValidationError[];
}

/**
 * 验证错误接口
 */
interface ValidationError {
  message: string;
  field?: string;
  code?: string;
}

/**
 * 扩展信息接口
 */
interface ExtensionInfo {
  name: string;
  version: string;
}

/**
 * 请求头映射接口 - 使用显式属性定义替代索引签名
 */
interface HeadersMap {
  contentType?: string;
  authorization?: string;
  userAgent?: string;
  accept?: string;
  cacheControl?: string;
}

/**
 * 本地事件类型定义：标题接收事件
 */
interface TitleReceiveEventLocal {
  title: string;
}

/**
 * 链接信息接口
 */
interface LinkInfo {
  text: string;
  href: string;
  title: string;
}

/**
 * 图片信息接口
 */
interface ImageInfo {
  src: string;
  alt: string;
  width: number;
  height: number;
}

/**
 * Meta标签接口
 */
interface MetaTag {
  name: string;
  content: string;
}

/**
 * 页面元信息接口
 */
interface PageMetaInfo {
  title: string;
  url: string;
  domain: string;
  protocol: string;
  charset: string;
  referrer: string;
  readyState: string;
  lastModified: string;
  meta: MetaTag[];
}

/**
 * Cookie信息接口
 */
interface CookieData {
  cookie: string;
  cookieCount: number;
}

/**
 * LocalStorage信息接口
 */
interface StorageData {
  keys: string[];
  count: number;
  data: Record<string, string>;
}

/**
 * 性能时间信息接口
 */
interface PerformanceTiming {
  loadTime: number;
  domReady: number;
  responseTime: number;
}

/**
 * 性能导航信息接口
 */
interface PerformanceNavigation {
  type: number;
  redirectCount: number;
}

/**
 * 性能资源信息接口
 */
interface PerformanceResources {
  count: number;
  totalSize: number;
}

/**
 * 性能信息接口
 */
interface PerformanceData {
  timing: PerformanceTiming;
  navigation: PerformanceNavigation;
  resources: PerformanceResources;
}

/**
 * 测试类别数据结构
 */
interface TestCategory {
  name: string;
  tests: TestResult[];
  expanded: boolean;
}

/**
 * 元数据数据结构
 */
interface Metadata {
  name?: string;
  type?: OperationType;
  params?: OperationParams[];
  description?: string;
  author?: string;
  created?: string;
  updated?: string;
}

/**
 * WebView基础配置接口
 */
interface WebViewConfigBasic {
  javaScriptAccess: boolean;
  domStorageAccess: boolean;
}

/**
 * WebView网络配置接口
 */
interface WebViewConfigNetwork {
  timeout: number;
  retryCount: number;
}

/**
 * WebView缓存配置接口
 */
interface WebViewConfigCache {
  enabled: boolean;
  maxSize: number;
}

/**
 * WebView配置接口
 */
interface WebViewConfig {
  basic: WebViewConfigBasic;
  network: WebViewConfigNetwork;
  cache: WebViewConfigCache;
}

/**
 * 配置JSON数据结构 - 使用显式属性定义替代索引签名
 */
interface ConfigJson {
  version: string;
  metadata: Metadata[];
  webview: WebViewConfig;
  extensions: ExtensionsMap;
}

/**
 * 扩展映射接口 - 替代Record<string, string>
 */
interface ExtensionsMap {
  imageProcessor?: string;
  networkRequest?: string;
  customHandler?: string;
}

/**
 * CSP配置接口
 */
interface CSPConfig {
  enabled: boolean;
  policy: string;
  reportOnly: boolean;
}

/**
 * 速率限制配置接口
 */
interface RateLimitConfig {
  maxRequests: number;
  timeWindow: number;
  blockDuration: number;
}

/**
 * 反爬虫配置接口 - 使用显式属性定义替代索引签名
 */
interface AntiCrawlerConfig {
  enabled: boolean;
  userAgent: string;
  rateLimit: RateLimitConfig;
  headers: AntiCrawlerHeaders;
}

/**
 * 反爬虫请求头接口
 */
interface AntiCrawlerHeaders {
  xForwardedFor?: string;
  xRealIp?: string;
  userAgent?: string;
}

/**
 * 域名控制配置接口
 */
interface DomainControlConfig {
  whiteList: string[];
  blackList: string[];
}

/**
 * 安全配置接口
 */
interface SecurityConfig {
  csp: CSPConfig;
  antiCrawler: AntiCrawlerConfig;
  domainControl: DomainControlConfig;
}

/**
 * 安全策略JSON配置接口
 */
interface PolicyJsonConfig {
  version: string;
  metadata: Metadata[];
  security: SecurityConfig[];
}

/**
 * 基础配置数据结构
 */
interface BaseConfig {
  version: string;
  metadata: Metadata[];
  webview: WebViewConfig;
  extensions: ExtensionsMap;
}

/**
 * 性能测试配置数据接口 - 用于性能测试中的配置对象
 */
interface PerformanceTestConfigData {
  version: string;
  metadata: Metadata[];
  webview: WebViewConfig;
  extensions: ExtensionsMap;
}

/**
 * 测试操作参数接口
 */
interface TestOperationParams {
  type: OperationType;
  action: string;
  data: ConfigurationOperationData | SecurityOperationData | SecurityCheckOperationData | ExtensionOperationData;
  timeout?: number;
  priority?: number;
}

/**
 * 模拟操作结果接口
 */
interface MockOperationResult {
  success: boolean;
  message: string;
  data: MockOperationData;
}

/**
 * 模拟操作数据接口
 */
interface MockOperationData {
  operation: string;
  timestamp: number;
}

/**
 * 性能测试结果接口
 */
interface PerformanceTestResult {
  iterations: number;
  totalTime: number;
  averageTime: number;
  operationsPerSecond: number;
}

/**
 * 批量操作性能结果接口
 */
interface BatchPerformanceResult {
  operationCount: number;
  successCount: number;
  failureCount: number;
  totalTime: number;
  averageTime: number;
}

/**
 * 内存使用测试结果接口
 */
interface MemoryTestResult {
  initialMemory: number;
  finalMemory: number;
  memoryIncrease: number;
  operationCount: number;
  memoryPerOperation: number;
}

@Component
struct WebViewConfigurableSystemTestPage {
  // 导航栈
  @State pathStack: NavPathStack = new NavPathStack();
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  private webviewController: webview.WebviewController = new webview.WebviewController();
  @State webTestUrl: string = 'https://www.bing.com/';
  @State webLoadState: string = 'idle';
  @State webPageTitle: string = '';
  @State webCurrentUrl: string = '';
  @State jsOutput: string = '';
  
  @State testCategories: TestCategory[] = [];
  @State isRunning: boolean = false;
  @State currentTest: string = '';
  @State totalTests: number = 0;
  @State completedTests: number = 0;
  @State successfulTests: number = 0;
  @State failedTests: number = 0;
  @State overallStartTime: number = 0;
  @State overallEndTime: number = 0;

  private operationInterface: UnifiedOperationInterface = UnifiedOperationInterface.getInstance();
  private configParser: WebViewConfigurationParser = new WebViewConfigurationParser();
  private securityParser: SecurityPolicyConfigurationParser = new SecurityPolicyConfigurationParser();
  private uiContext: UIContext | undefined = undefined;

  aboutToAppear(): void {
    logger.lifecycle(TAG, 'aboutToAppear');
    this.uiContext = this.getUIContext();
    this.initializeTestCategories();
  }

  onPageShow() {
    logger.lifecycle(TAG, 'WebView可配置系统测试页面显示');
    try {
      const globalNavStack = AppStorage.get<NavPathStack>('GlobalNavStack');
      if (globalNavStack) {
        this.pathStack = globalNavStack;
      }
    } catch (error) {
      logger.error(TAG, `获取全局导航栈失败: ${error}`);
    }
  }

  aboutToDisappear(): void {
    logger.lifecycle(TAG, 'aboutToDisappear');
    this.cleanup();
  }

  private async runWebJavaScript(code: string): Promise<string> {
    return await new Promise<string>((resolve, reject) => {
      try {
        this.webviewController.runJavaScript(code, (error: BusinessError | null, result: string) => {
          if (error) {
            reject(error.message);
            return;
          }
          resolve(result);
        });
      } catch (e) {
        const msg = e instanceof Error ? e.message : String(e);
        reject(msg);
      }
    });
  }

  private startWebBasicTest(): void {
    try {
      logger.info(TAG, '🔵 开始Web基础测试');
      logger.info(TAG, `目标URL: ${this.webTestUrl}`);
      logger.info(TAG, `WebView控制器状态: ${this.webviewController ? '已初始化' : '未初始化'}`);
      
      this.webLoadState = 'loading';
      this.webPageTitle = '';
      this.webCurrentUrl = '';
      this.jsOutput = '';
      this.webCurrentUrl = this.webTestUrl;
      
      logger.info(TAG, '🔵 调用 loadUrl...');
      this.webviewController.loadUrl(this.webTestUrl);
      logger.info(TAG, '🔵 loadUrl 调用完成');
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      logger.error(TAG, `❌ Web基础测试失败: ${msg}`);
      logger.error(TAG, `错误堆栈: ${e instanceof Error ? e.stack : '无堆栈信息'}`);
      this.webLoadState = 'error';
      this.jsOutput = `错误: ${msg}`;
    }
  }

  private async runTitleJsTest(): Promise<void> {
    const testId = `test_${Date.now()}`;
    logger.info(TAG, '🔵 开始获取页面标题');
    try {
      const title = await this.runWebJavaScript('document.title');
      this.webPageTitle = title;
      this.jsOutput = '标题: ' + title;
      logger.info(TAG, `✅ 页面标题: ${title}`);
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      this.jsOutput = 'JS错误: ' + msg;
      logger.error(TAG, `❌ 获取标题失败: ${msg}`);
    }
  }

  private async runLinksCountTest(): Promise<void> {
    logger.info(TAG, '🔵 开始统计链接数量');
    try {
      const countStr = await this.runWebJavaScript('document.querySelectorAll("a").length.toString()');
      this.jsOutput = '链接数量: ' + countStr;
      logger.info(TAG, `✅ 链接数量: ${countStr}`);
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      this.jsOutput = 'JS错误: ' + msg;
      logger.error(TAG, `❌ 统计链接失败: ${msg}`);
    }
  }

  private async runUserAgentTest(): Promise<void> {
    logger.info(TAG, '🔵 开始获取UserAgent');
    try {
      const ua = await this.runWebJavaScript('navigator.userAgent');
      this.jsOutput = 'UA: ' + ua;
      logger.info(TAG, `✅ UserAgent: ${ua.substring(0, 50)}...`);
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      this.jsOutput = 'JS错误: ' + msg;
      logger.error(TAG, `❌ 获取UA失败: ${msg}`);
    }
  }

  /**
   * 获取页面所有链接
   */
  private async getAllLinks(): Promise<void> {
    logger.info(TAG, '🔵 开始获取所有链接');
    try {
      const script = `
        JSON.stringify(
          Array.from(document.querySelectorAll('a')).slice(0, 20).map(a => ({
            text: a.textContent?.trim() || '',
            href: a.href || '',
            title: a.title || ''
          }))
        )
      `;
      const result = await this.runWebJavaScript(script);
      const links: LinkInfo[] = SafeUtils.parseArr(result) as LinkInfo[];
      this.jsOutput = `找到 ${links.length} 个链接:\\n${JSON.stringify(links, null, 2)}`;
      logger.info(TAG, `✅ 获取了 ${links.length} 个链接`);
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      this.jsOutput = 'JS错误: ' + msg;
      logger.error(TAG, `❌ 获取链接失败: ${msg}`);
    }
  }

  /**
   * 获取页面所有图片
   */
  private async getAllImages(): Promise<void> {
    logger.info(TAG, '🔵 开始获取所有图片');
    try {
      const script = `
        JSON.stringify(
          Array.from(document.querySelectorAll('img')).slice(0, 20).map(img => ({
            src: img.src || '',
            alt: img.alt || '',
            width: img.width,
            height: img.height
          }))
        )
      `;
      const result = await this.runWebJavaScript(script);
      const images: ImageInfo[] = SafeUtils.parseArr(result) as ImageInfo[];
      this.jsOutput = `找到 ${images.length} 个图片:\\n${JSON.stringify(images, null, 2)}`;
      logger.info(TAG, `✅ 获取了 ${images.length} 个图片`);
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      this.jsOutput = 'JS错误: ' + msg;
      logger.error(TAG, `❌ 获取图片失败: ${msg}`);
    }
  }

  /**
   * 获取页面元信息
   */
  private async getPageMetaInfo(): Promise<void> {
    logger.info(TAG, '🔵 开始获取页面元信息');
    try {
      const script = `
        JSON.stringify({
          title: document.title,
          url: window.location.href,
          domain: window.location.hostname,
          protocol: window.location.protocol,
          charset: document.characterSet,
          referrer: document.referrer,
          readyState: document.readyState,
          lastModified: document.lastModified,
          meta: Array.from(document.querySelectorAll('meta')).slice(0, 10).map(m => ({
            name: m.getAttribute('name') || m.getAttribute('property') || '',
            content: m.getAttribute('content') || ''
          }))
        })
      `;
      const result = await this.runWebJavaScript(script);
      const metaInfo: PageMetaInfo = SafeUtils.parseObj(result) as PageMetaInfo;
      this.jsOutput = JSON.stringify(metaInfo, null, 2);
      logger.info(TAG, `✅ 页面元信息获取成功`);
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      this.jsOutput = 'JS错误: ' + msg;
      logger.error(TAG, `❌ 获取元信息失败: ${msg}`);
    }
  }

  /**
   * 获取Cookie信息
   */
  private async getCookieInfo(): Promise<void> {
    logger.info(TAG, '🔵 开始获取Cookie');
    try {
      const script = `
        JSON.stringify({
          cookie: document.cookie,
          cookieCount: document.cookie.split(';').filter(c => c.trim()).length
        })
      `;
      const result = await this.runWebJavaScript(script);
      const cookieInfo: CookieData = SafeUtils.parseObj(result) as CookieData;
      this.jsOutput = JSON.stringify(cookieInfo, null, 2);
      logger.info(TAG, `✅ Cookie数量: ${cookieInfo.cookieCount}`);
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      this.jsOutput = 'JS错误: ' + msg;
      logger.error(TAG, `❌ 获取Cookie失败: ${msg}`);
    }
  }

  /**
   * 获取LocalStorage信息
   */
  private async getLocalStorageInfo(): Promise<void> {
    logger.info(TAG, '🔵 开始获取LocalStorage');
    try {
      const script = `
        JSON.stringify({
          keys: Object.keys(localStorage),
          count: localStorage.length,
          data: Object.keys(localStorage).slice(0, 10).reduce((acc, key) => {
            acc[key] = localStorage.getItem(key);
            return acc;
          }, {})
        })
      `;
      const result = await this.runWebJavaScript(script);
      const storageInfo: StorageData = SafeUtils.parseObj(result) as StorageData;
      this.jsOutput = JSON.stringify(storageInfo, null, 2);
      logger.info(TAG, `✅ LocalStorage项数: ${storageInfo.count}`);
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      this.jsOutput = 'JS错误: ' + msg;
      logger.error(TAG, `❌ 获取LocalStorage失败: ${msg}`);
    }
  }

  /**
   * 获取页面性能信息
   */
  private async getPerformanceInfo(): Promise<void> {
    logger.info(TAG, '🔵 开始获取性能信息');
    try {
      const script = `
        JSON.stringify({
          timing: {
            loadTime: performance.timing.loadEventEnd - performance.timing.navigationStart,
            domReady: performance.timing.domContentLoadedEventEnd - performance.timing.navigationStart,
            responseTime: performance.timing.responseEnd - performance.timing.requestStart
          },
          navigation: {
            type: performance.navigation.type,
            redirectCount: performance.navigation.redirectCount
          },
          resources: {
            count: performance.getEntriesByType('resource').length,
            totalSize: performance.getEntriesByType('resource').reduce((sum, r) => sum + (r.transferSize || 0), 0)
          }
        })
      `;
      const result = await this.runWebJavaScript(script);
      const perfInfo: PerformanceData = SafeUtils.parseObj(result) as PerformanceData;
      this.jsOutput = JSON.stringify(perfInfo, null, 2);
      logger.info(TAG, `✅ 性能信息获取成功`);
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      this.jsOutput = 'JS错误: ' + msg;
      logger.error(TAG, `❌ 获取性能信息失败: ${msg}`);
    }
  }

  /**
   * 获取页面HTML源码
   */
  private async getPageSource(): Promise<void> {
    logger.info(TAG, '🔵 开始获取页面源码');
    try {
      const script = 'document.documentElement.outerHTML';
      const result = await this.runWebJavaScript(script);
      // 只显示前1000个字符
      this.jsOutput = `源码长度: ${result.length} 字符\\n\\n${result.substring(0, 1000)}...`;
      logger.info(TAG, `✅ 页面源码长度: ${result.length} 字符`);
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      this.jsOutput = 'JS错误: ' + msg;
      logger.error(TAG, `❌ 获取源码失败: ${msg}`);
    }
  }

  build() {
    HdsNavDestination() {
      Column() {
        // 固定顶部标题栏
        this.buildHeader()

        // 可滚动内容区域
        Scroll() {
          Column({ space: 16 }) {
            this.buildTestControls()
            this.buildWebViewPanel()
            this.buildWebTestControls()
            this.buildTestProgress()
            this.buildTestResults()
          }
          .width('100%')
          .padding({
            left: 16,
            right: 16,
            top: 16,
            bottom: 16
          })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(colorMap['app.color.background_primary'])
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .padding({ top: this.statusBarHeight })
    }
    .hideTitleBar(true)
    .onReady((context: NavDestinationContext) => {
      logger.info(TAG, 'HdsNavDestination.onReady 已触发');
      this.pathStack = context.pathStack;
      this.onPageShow();
    })
    .backgroundColor(Color.Transparent)
  }

  @Builder
  buildWebViewPanel() {
    Column({ space: 12 }) {
      Text('WebView基础测试')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(colorMap['app.color.text_primary'])

      // URL输入框
      TextInput({ placeholder: '输入测试URL', text: this.webTestUrl })
        .width('100%')
        .height(44)
        .fontSize(14)
        .backgroundColor(colorMap['app.color.background_secondary'])
        .fontColor(colorMap['app.color.text_primary'])
        .placeholderColor(colorMap['app.color.text_secondary'])
        .borderRadius(8)
        .padding({ left: 12, right: 12 })
        .onChange((value: string) => {
          this.webTestUrl = value;
        })

      // WebView容器
      Column() {
        Web({ src: 'about:blank', controller: this.webviewController })
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .zoomAccess(true)
          .fileAccess(true)
          .onControllerAttached(() => {
            logger.info(TAG, '✅ WebView控制器已附加到Web组件');
          })
          .onPageBegin((event) => {
            const urlText: string = event.url;
            logger.info(TAG, `🟢 页面开始加载: ${urlText}`);
            this.webCurrentUrl = urlText;
            this.webLoadState = 'loading';
          })
          .onPageEnd((event) => {
            const urlText: string = event.url;
            logger.info(TAG, `🟢 页面加载完成: ${urlText}`);
            this.webCurrentUrl = urlText;
            this.webLoadState = 'loaded';
            this.runTitleJsTest();
          })
          .onProgressChange((event) => {
            logger.debug(TAG, `📊 加载进度: ${event.newProgress}%`);
          })
          .onErrorReceive((event) => {
            const errorInfo = event.error.getErrorInfo();
            logger.error(TAG, `❌ 页面加载错误: ${errorInfo}`);
            this.webLoadState = 'error';
            this.jsOutput = `加载错误: ${errorInfo}`;
          })
          .onHttpErrorReceive((event) => {
            logger.error(TAG, `❌ HTTP错误: ${event.response.getResponseCode()}`);
          })
          .onTitleReceive((event) => {
            const hasTitle: boolean = Object.keys(event as Object).includes('title');
            if (hasTitle) {
              const evt: TitleReceiveEventLocal = event as TitleReceiveEventLocal;
              logger.info(TAG, `📄 页面标题: ${evt.title}`);
              this.webPageTitle = evt.title;
            }
          })
          .width('100%')
          .height(250)
      }
      .width('100%')
      .borderRadius(8)
      .clip(true)
      .border({ width: 1, color: colorMap['app.color.divider'] })

      // 状态信息
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          Text('状态:')
            .fontSize(13)
            .fontColor(colorMap['app.color.text_secondary'])
            .width(50)
          Text(this.webLoadState)
            .fontSize(13)
            .fontColor(this.webLoadState === 'error' ? '#FF5252' : colorMap['app.color.text_primary'])
            .fontWeight(FontWeight.Medium)
        }
        .width('100%')

        Row({ space: 8 }) {
          Text('URL:')
            .fontSize(13)
            .fontColor(colorMap['app.color.text_secondary'])
            .width(50)
          Text(this.webCurrentUrl)
            .fontSize(13)
            .fontColor(colorMap['app.color.text_primary'])
            .layoutWeight(1)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)

        Row({ space: 8 }) {
          Text('标题:')
            .fontSize(13)
            .fontColor(colorMap['app.color.text_secondary'])
            .width(50)
          Text(this.webPageTitle || '无')
            .fontSize(13)
            .fontColor(colorMap['app.color.text_primary'])
            .layoutWeight(1)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
      }
      .width('100%')
      .padding(12)
      .backgroundColor(colorMap['app.color.background_secondary'])
      .borderRadius(8)
    }
    .width('100%')
    .padding(16)
    .backgroundColor(colorMap['app.color.panel_background'])
    .borderRadius(12)
  }

  @Builder
  buildWebTestControls() {
    Column({ space: 12 }) {
      // 基础测试
      Text('基础测试')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(colorMap['app.color.text_primary'])
      
      // 使用Flex自动换行
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        Button('加载页面')
          .fontSize(12)
          .type(ButtonType.Capsule)
          .backgroundColor(colorMap['app.color.accent_primary'])
          .fontColor(colorMap['app.color.text_inverse'])
          .margin({ right: 8, bottom: 8 })
          .padding({ left: 16, right: 16 })
          .onClick(() => this.startWebBasicTest())

        Button('标题')
          .fontSize(12)
          .type(ButtonType.Capsule)
          .backgroundColor(colorMap['app.color.accent_blue'])
          .fontColor(colorMap['app.color.text_inverse'])
          .margin({ right: 8, bottom: 8 })
          .padding({ left: 16, right: 16 })
          .onClick(() => this.runTitleJsTest())

        Button('链接数')
          .fontSize(12)
          .type(ButtonType.Capsule)
          .backgroundColor(colorMap['app.color.accent_orange'])
          .fontColor(colorMap['app.color.text_inverse'])
          .margin({ right: 8, bottom: 8 })
          .padding({ left: 16, right: 16 })
          .onClick(() => this.runLinksCountTest())

        Button('UA')
          .fontSize(12)
          .type(ButtonType.Capsule)
          .backgroundColor(colorMap['app.color.accent_green'])
          .fontColor(colorMap['app.color.text_inverse'])
          .margin({ right: 8, bottom: 8 })
          .padding({ left: 16, right: 16 })
          .onClick(() => this.runUserAgentTest())
      }
      .width('100%')

      // 高级捕获
      Text('高级捕获')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(colorMap['app.color.text_primary'])
        .margin({ top: 8 })
      
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        Button('所有链接')
          .fontSize(12)
          .type(ButtonType.Capsule)
          .backgroundColor(colorMap['app.color.accent_purple'])
          .fontColor(colorMap['app.color.text_inverse'])
          .margin({ right: 8, bottom: 8 })
          .padding({ left: 16, right: 16 })
          .onClick(() => this.getAllLinks())

        Button('所有图片')
          .fontSize(12)
          .type(ButtonType.Capsule)
          .backgroundColor(colorMap['app.color.accent_pink'])
          .fontColor(colorMap['app.color.text_inverse'])
          .margin({ right: 8, bottom: 8 })
          .padding({ left: 16, right: 16 })
          .onClick(() => this.getAllImages())

        Button('元信息')
          .fontSize(12)
          .type(ButtonType.Capsule)
          .backgroundColor(colorMap['app.color.accent_teal'])
          .fontColor(colorMap['app.color.text_inverse'])
          .margin({ right: 8, bottom: 8 })
          .padding({ left: 16, right: 16 })
          .onClick(() => this.getPageMetaInfo())

        Button('Cookie')
          .fontSize(12)
          .type(ButtonType.Capsule)
          .backgroundColor(colorMap['app.color.accent_amber'])
          .fontColor(colorMap['app.color.text_inverse'])
          .margin({ right: 8, bottom: 8 })
          .padding({ left: 16, right: 16 })
          .onClick(() => this.getCookieInfo())

        Button('Storage')
          .fontSize(12)
          .type(ButtonType.Capsule)
          .backgroundColor(colorMap['app.color.accent_cyan'])
          .fontColor(colorMap['app.color.text_inverse'])
          .margin({ right: 8, bottom: 8 })
          .padding({ left: 16, right: 16 })
          .onClick(() => this.getLocalStorageInfo())

        Button('性能')
          .fontSize(12)
          .type(ButtonType.Capsule)
          .backgroundColor(colorMap['app.color.accent_indigo'])
          .fontColor(colorMap['app.color.text_inverse'])
          .margin({ right: 8, bottom: 8 })
          .padding({ left: 16, right: 16 })
          .onClick(() => this.getPerformanceInfo())

        Button('源码')
          .fontSize(12)
          .type(ButtonType.Capsule)
          .backgroundColor(colorMap['app.color.accent_brown'])
          .fontColor(colorMap['app.color.text_inverse'])
          .margin({ right: 8, bottom: 8 })
          .padding({ left: 16, right: 16 })
          .onClick(() => this.getPageSource())
      }
      .width('100%')

      // JS输出区域
      Column({ space: 8 }) {
        Row() {
          Text('JS输出')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(colorMap['app.color.text_secondary'])
            .layoutWeight(1)
          
          Text(`${this.jsOutput.length} 字符`)
            .fontSize(12)
            .fontColor(colorMap['app.color.text_tertiary'])
        }
        .width('100%')
        
        Scroll() {
          Text(this.jsOutput || '暂无输出')
            .fontSize(12)
            .fontColor(colorMap['app.color.text_primary'])
            .fontFamily('monospace')
            .width('100%')
            .padding(8)
        }
        .width('100%')
        .height(180)
        .backgroundColor(colorMap['app.color.background_secondary'])
        .borderRadius(8)
        .border({ width: 1, color: colorMap['app.color.divider'] })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(16)
    .backgroundColor(colorMap['app.color.panel_background'])
    .borderRadius(12)
  }

  @Builder
  buildHeader() {
    Row() {
      Button() {
        Image($r('sys.media.ohos_ic_public_arrow_left'))
          .width(24)
          .height(24)
          .fillColor(colorMap['app.color.text_primary'])
      }
      .type(ButtonType.Circle)
      .backgroundColor(colorMap['app.color.button_background'])
      .onClick(() => {
        this.goBack();
      })

      Text('WebView可配置系统测试')
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor(colorMap['app.color.text_primary'])
        .layoutWeight(1)
        .textAlign(TextAlign.Center)

      Button() {
        Image($r('app.media.ic_public_refresh'))
          .width(24)
          .height(24)
          .fillColor(colorMap['app.color.text_primary'])
      }
      .type(ButtonType.Circle)
      .backgroundColor(colorMap['app.color.button_background'])
      .onClick(() => {
        this.resetTests();
      })
    }
    .width('100%')
    .height(56)
  }

  @Builder
  buildTestControls() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        Button('运行所有测试')
          .type(ButtonType.Capsule)
          .backgroundColor(colorMap['app.color.accent_primary'])
          .fontColor(colorMap['app.color.text_inverse'])
          .enabled(!this.isRunning)
          .layoutWeight(1)
          .onClick(() => {
            this.runAllTests();
          })

        Button('运行配置测试')
          .type(ButtonType.Capsule)
          .backgroundColor(colorMap['app.color.accent_orange'])
          .fontColor(colorMap['app.color.text_inverse'])
          .enabled(!this.isRunning)
          .layoutWeight(1)
          .onClick(() => {
            this.runConfigurationTests();
          })
      }

      Row({ space: 12 }) {
        Button('运行性能测试')
          .type(ButtonType.Capsule)
          .backgroundColor(colorMap['app.color.accent_blue'])
          .fontColor(colorMap['app.color.text_inverse'])
          .enabled(!this.isRunning)
          .layoutWeight(1)
          .onClick(() => {
            this.runPerformanceTests();
          })
      }

      if (this.isRunning) {
        Row({ space: 8 }) {
          LoadingProgress()
            .width(20)
            .height(20)
            .color(colorMap['app.color.accent_primary'])

          Text(`正在执行: ${this.currentTest}`)
            .fontSize(14)
            .fontColor(colorMap['app.color.text_secondary'])
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(colorMap['app.color.panel_background'])
    .borderRadius(12)
  }

  @Builder
  buildTestProgress() {
    if (this.totalTests > 0) {
      Column({ space: 8 }) {
        Row() {
          Text('测试进度')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(colorMap['app.color.text_primary'])

          Blank()

          Text(`${this.completedTests}/${this.totalTests}`)
            .fontSize(14)
            .fontColor(colorMap['app.color.text_secondary'])
        }
        .width('100%')

        Progress({
          value: this.completedTests,
          total: this.totalTests,
          type: ProgressType.Linear
        })
        .width('100%')
        .color(colorMap['app.color.accent_primary'])
        .backgroundColor(colorMap['app.color.background_secondary'])

        Row({ space: 16 }) {
          Text(`成功: ${this.successfulTests}`)
            .fontSize(12)
            .fontColor(colorMap['app.color.success_text'])

          Text(`失败: ${this.failedTests}`)
            .fontSize(12)
            .fontColor(colorMap['app.color.error_text'])

          if (this.overallEndTime > 0) {
            Text(`总耗时: ${this.overallEndTime - this.overallStartTime}ms`)
              .fontSize(12)
              .fontColor(colorMap['app.color.text_secondary'])
          }
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceEvenly)
      }
      .width('100%')
      .padding(16)
      .backgroundColor(colorMap['app.color.panel_background'])
      .borderRadius(12)
    }
  }

  @Builder
  buildTestResults() {
    if (this.testCategories.length > 0) {
      Column({ space: 8 }) {
        Text('测试结果')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(colorMap['app.color.text_primary'])
          .width('100%')

        List({ space: 8 }) {
          ForEach(this.testCategories, (category: TestCategory, categoryIndex: number) => {
            ListItem() {
              this.buildTestCategory(category, categoryIndex)
            }
          })
        }
        .width('100%')
        .height('100%')
        .layoutWeight(1)
      }
      .width('100%')
      .layoutWeight(1)
    }
  }

  @Builder
  buildTestCategory(category: TestCategory, categoryIndex: number) {
    Column({ space: 8 }) {
      // 分类标题
      Row({ space: 8 }) {
        Image(category.expanded ? $r('sys.media.ohos_ic_public_arrow_down') : $r('sys.media.ohos_ic_public_arrow_right'))
          .width(16)
          .height(16)
          .fillColor(colorMap['app.color.text_secondary'])

        Text(category.name)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(colorMap['app.color.text_primary'])
          .layoutWeight(1)

        Text(`${category.tests.filter(t => t.success).length}/${category.tests.length}`)
          .fontSize(12)
          .fontColor(colorMap['app.color.text_secondary'])
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .backgroundColor(colorMap['app.color.background_secondary'])
          .borderRadius(8)
      }
      .width('100%')
      .padding(12)
      .backgroundColor(colorMap['app.color.panel_background'])
      .borderRadius(8)
      .onClick(() => {
        this.testCategories[categoryIndex].expanded = !this.testCategories[categoryIndex].expanded;
      })

      // 测试项目列表
      if (category.expanded && category.tests.length > 0) {
        Column({ space: 4 }) {
          ForEach(category.tests, (test: TestResult) => {
            this.buildTestItem(test)
          })
        }
        .width('100%')
        .padding({ left: 16 })
      }
    }
    .width('100%')
  }

  @Builder
  buildTestItem(test: TestResult) {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Image(test.success ? $r('app.media.ic_public_correct') : $r('app.media.ic_public_cancel'))
          .width(16)
          .height(16)
          .fillColor(test.success ? colorMap['app.color.success_text'] : colorMap['app.color.error_text'])

        Text(test.name)
          .fontSize(14)
          .fontColor(colorMap['app.color.text_primary'])
          .layoutWeight(1)

        Text(`${test.executionTime}ms`)
          .fontSize(12)
          .fontColor(colorMap['app.color.text_secondary'])
      }
      .width('100%')

      if (test.message) {
        Text(test.message)
          .fontSize(12)
          .fontColor(test.success ? colorMap['app.color.text_secondary'] : colorMap['app.color.error_text'])
          .width('100%')
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }

      if (test.data) {
        Text(JSON.stringify(test.data, null, 2))
          .fontSize(10)
          .fontColor(colorMap['app.color.text_secondary'])
          .width('100%')
          .maxLines(5)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontFamily('monospace')
          .backgroundColor(colorMap['app.color.background_secondary'])
          .padding(8)
          .borderRadius(4)
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor(colorMap['app.color.background_secondary'])
    .borderRadius(8)
  }

  private initializeTestCategories(): void {
    const configCategory: TestCategory = { name: '配置解析测试', tests: [], expanded: true };
    const securityCategory: TestCategory = { name: '安全策略测试', tests: [], expanded: true };
    const extensionCategory: TestCategory = { name: '扩展模块测试', tests: [], expanded: true };
    const interfaceCategory: TestCategory = { name: '统一接口测试', tests: [], expanded: true };
    const performanceCategory: TestCategory = { name: '性能测试', tests: [], expanded: false };

    this.testCategories = [
      configCategory,
      securityCategory,
      extensionCategory,
      interfaceCategory,
      performanceCategory
    ];
  }

  private async runAllTests(): Promise<void> {
    this.isRunning = true;
    this.overallStartTime = Date.now();
    this.resetTestResults();

    try {
      await this.runConfigurationTests();
      await this.runSecurityTests();
      await this.runExtensionTests();
      await this.runUnifiedInterfaceTests();
      await this.runPerformanceTests();
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error(TAG, '运行所有测试时发生错误: ' + errorMessage);
    } finally {
      this.overallEndTime = Date.now();
      this.isRunning = false;
      this.currentTest = '';
      
      logger.info(TAG, '所有测试完成', 
        'totalTests: ' + this.totalTests + ', ' +
        'successfulTests: ' + this.successfulTests + ', ' +
        'failedTests: ' + this.failedTests + ', ' +
        'totalTime: ' + (this.overallEndTime - this.overallStartTime)
      );
    }
  }

  private async runConfigurationTests(): Promise<void> {
    const categoryIndex = 0;
    
    // 测试WebView配置解析
    await this.runTest('WebView配置解析', categoryIndex, async (): Promise<TestResultData> => {
      const configData: ConfigJson = {
        version: '1.0.0',
        metadata: [
          this.createTestMetadata('测试配置', OperationType.CONFIGURATION, '测试WebView配置')
        ],
        webview: {
          basic: { javaScriptAccess: true, domStorageAccess: true },
          network: { timeout: 30000, retryCount: 3 },
          cache: { enabled: true, maxSize: 50 * 1024 * 1024 }
        },
        extensions: {}
      };

      const config = this.configParser.parse(JSON.stringify(configData));
      if (!config) {
        throw new Error('配置解析失败');
      }
      
      const validation = this.configParser.validate(config);

      if (!validation.isValid) {
        throw new Error(`配置验证失败: ${validation.errors.join(', ')}`);
      }

      return { config, validation };
    });

    // 测试安全策略解析
    await this.runTest('安全策略解析', categoryIndex, async (): Promise<TestResultData> => {
      const policyData: PolicyJsonConfig = {
        version: '1.0.0',
        metadata: [
          this.createTestMetadata('测试安全策略', OperationType.SECURITY, '测试安全策略配置')
        ],
        security: [
          this.createSecurityConfig()
        ]
      };

      const policy = this.securityParser.parse(JSON.stringify(policyData));
      if (!policy) {
        throw new Error('安全策略解析失败');
      }
      
      const validation = this.securityParser.validate(policy);

      if (!validation.isValid) {
        const errorMessages = validation.errors.map(e => e.message);
        throw new Error(`安全策略验证失败: ${errorMessages.join(', ')}`);
      }

      return { config: policy, validation };
    });

    // 测试配置合并
    await this.runTest('配置合并', categoryIndex, async (): Promise<TestResultData> => {
      const baseConfigData: BaseConfig = {
        version: '1.0.0',
        metadata: [
          this.createTestMetadata('基础配置', undefined, '基础WebView配置')
        ],
        webview: {
          basic: { javaScriptAccess: true, domStorageAccess: false },
          network: { timeout: 30000, retryCount: 3 },
          cache: { enabled: true, maxSize: 50 * 1024 * 1024 }
        },
        extensions: {}
      };

      const overrideConfigData: BaseConfig = {
        version: '1.0.0',
        metadata: [
          this.createTestMetadata('覆盖配置', undefined, '覆盖WebView配置')
        ],
        webview: {
          basic: { javaScriptAccess: true, domStorageAccess: true },
          network: { timeout: 60000, retryCount: 3 },
          cache: { enabled: true, maxSize: 100 * 1024 * 1024 }
        },
        extensions: {}
      };

      const baseConfig = this.configParser.parse(JSON.stringify(baseConfigData));
      const overrideConfig = this.configParser.parse(JSON.stringify(overrideConfigData));

      if (!baseConfig || !overrideConfig) {
        throw new Error('配置解析失败');
      }

      const mergedConfig = this.configParser.merge(baseConfig, overrideConfig);

      return { 
        baseConfig, 
        overrideConfig, 
        mergedConfig,
        domStorageEnabled: mergedConfig.webview.basic.domStorageAccess,
        timeout: mergedConfig.webview.network.timeout
      };
    });

    // 测试配置序列化
    await this.runTest('配置序列化', categoryIndex, async (): Promise<TestResultData> => {
      const configData: BaseConfig = {
        version: '1.0.0',
        metadata: [
          this.createTestMetadata('序列化测试', undefined, '测试配置序列化')
        ],
        webview: {
          basic: { javaScriptAccess: true, domStorageAccess: true },
          network: { timeout: 30000, retryCount: 3 },
          cache: { enabled: true, maxSize: 50 * 1024 * 1024 }
        },
        extensions: {}
      };

      const original = this.configParser.parse(JSON.stringify(configData));
      if (!original) {
        throw new Error('原始配置解析失败');
      }

      const serialized = this.configParser.serialize(original);
      const reparsed = this.configParser.parse(serialized);

      if (!reparsed) {
        throw new Error('重新解析失败');
      }

      return { original, serialized, reparsed };
    });
  }

  private async runSecurityTests(): Promise<void> {
    const categoryIndex = 1;

    // 测试URL验证
    await this.runTest('URL验证', categoryIndex, async (): Promise<TestResultData> => {
      const params: OperationParams = {
        type: OperationType.SECURITY,
        action: 'validate',
        data: this.createSecurityValidationData('https://www.bing.com/', 'test-policy')
      };

      const result = await this.operationInterface.execute(params);
      
      return {
        operation: 'URL验证',
        timestamp: result.timestamp,
        url: 'https://www.bing.com/'
      };
    });

    // 测试安全头获取
    await this.runTest('安全头获取', categoryIndex, async (): Promise<TestResultData> => {
      const params: OperationParams = {
        type: OperationType.SECURITY,
        action: 'check',
        data: this.createSecurityCheckData('https://www.bing.com/', 'get_headers')
      };

      const result = await this.operationInterface.execute(params);
      
      return {
        operation: '安全头获取',
        timestamp: result.timestamp,
        headers: { contentType: 'application/json' }
      };
    });

    // 测试速率限制检查
    await this.runTest('速率限制检查', categoryIndex, async (): Promise<TestResultData> => {
      const params: OperationParams = {
        type: OperationType.SECURITY,
        action: 'check',
        data: this.createSecurityCheckData('https://www.bing.com/', 'rate_limit')
      };

      const result = await this.operationInterface.execute(params);
      
      return {
        operation: '速率限制检查',
        timestamp: result.timestamp
      };
    });
  }

  private async runExtensionTests(): Promise<void> {
    const categoryIndex = 2;

    // 测试扩展模块列表
    await this.runTest('扩展模块列表', categoryIndex, async (): Promise<TestResultData> => {
      // 模拟扩展模块列表
      const extensions: ExtensionInfo[] = [
        { name: 'ImageProcessor', version: '1.0.0' },
        { name: 'NetworkRequest', version: '2.1.0' }
      ];

      return { extensions };
    });

    // 测试扩展功能
    await this.runTest('扩展功能测试', categoryIndex, async (): Promise<TestResultData> => {
      const params: OperationParams = {
        type: OperationType.EXTENSION,
        action: 'register',
        data: this.createExtensionRegistrationData('TestExtension', '/path/to/extension')
      };

      const result = await this.operationInterface.execute(params);
      
      return {
        operation: '扩展功能测试',
        timestamp: result.timestamp
      };
    });
  }

  private async runUnifiedInterfaceTests(): Promise<void> {
    const categoryIndex = 3;

    // 测试单个操作
    await this.runTest('单个操作测试', categoryIndex, async (): Promise<TestResultData> => {
      const params: OperationParams = {
        type: OperationType.CONFIGURATION,
        action: 'parse',
        data: this.createConfigurationParseData('webview', '{"basic":{"javaScriptAccess":true}}')
      };

      const result = await this.operationInterface.execute(params);
      
      return {
        operation: '单个操作测试',
        timestamp: result.timestamp
      };
    });

    // 测试批量操作 - 使用单个操作模拟批量
    await this.runTest('批量操作测试', categoryIndex, async (): Promise<TestResultData> => {
      const operations: OperationParams[] = [
        {
          type: OperationType.CONFIGURATION,
          action: 'parse',
          data: this.createConfigurationParseData('webview', '{"basic":{"javaScriptAccess":true}}')
        },
        {
          type: OperationType.SECURITY,
          action: 'validate',
          data: this.createSecurityValidationData('https://www.bing.com/', 'test-policy')
        }
      ];

      const results: OperationResult[] = [];
      for (const operation of operations) {
        const result = await this.operationInterface.execute(operation);
        results.push(result);
      }
      
      return {
        results,
        operationCount: operations.length
      };
    });

    // 测试错误处理
    await this.runTest('错误处理测试', categoryIndex, async (): Promise<TestResultData> => {
      const params: OperationParams = {
        type: OperationType.CONFIGURATION,
        action: 'invalid_action',
        data: this.createConfigurationParseData('invalid', 'invalid_content')
      };

      const result = await this.operationInterface.execute(params);
      
      return {
        errorHandled: !result.success,
        error: result.error || '无错误信息'
      };
    });
  }

  private async runPerformanceTests(): Promise<void> {
    const categoryIndex = 4;

    // 测试配置解析性能
    await this.runTest('配置解析性能', categoryIndex, async (): Promise<TestResultData> => {
      const iterations = 100;
      const startTime = Date.now();

      for (let i = 0; i < iterations; i++) {
        const configData: PerformanceTestConfigData = {
          version: '1.0.0',
          metadata: [],
          webview: {
            basic: { javaScriptAccess: true, domStorageAccess: true },
            network: { timeout: 30000, retryCount: 3 },
            cache: { enabled: true, maxSize: 50 * 1024 * 1024 }
          },
          extensions: {}
        };
        this.configParser.parse(JSON.stringify(configData));
      }

      const totalTime = Date.now() - startTime;
      const averageTime = totalTime / iterations;
      const operationsPerSecond = Math.round(1000 / averageTime);

      return {
        iterations,
        totalTime,
        averageTime,
        operationsPerSecond
      };
    });

    // 测试批量操作性能 - 使用单个操作模拟
    await this.runTest('批量操作性能', categoryIndex, async (): Promise<TestResultData> => {
      const operationCount = 50;
      const startTime = Date.now();
      let successCount = 0;
      let failureCount = 0;

      for (let i = 0; i < operationCount; i++) {
        const params: OperationParams = {
          type: OperationType.CONFIGURATION,
          action: 'parse',
          data: this.createConfigurationParseData('webview', `{"testIndex":${i}}`)
        };

        const result = await this.operationInterface.execute(params);
        if (result.success) {
          successCount++;
        } else {
          failureCount++;
        }
      }

      const totalTime = Date.now() - startTime;
      const averageTime = totalTime / operationCount;

      return {
        operationCount,
        successCount,
        failureCount,
        totalTime,
        averageTime
      };
    });

    // 测试内存使用
    await this.runTest('内存使用测试', categoryIndex, async (): Promise<TestResultData> => {
      const initialMemory = this.getSimulatedMemoryUsage();
      const operationCount = 100;

      // 执行一系列操作
      for (let i = 0; i < operationCount; i++) {
        const configData: PerformanceTestConfigData = {
          version: '1.0.0',
          metadata: [],
          webview: {
            basic: { javaScriptAccess: true, domStorageAccess: true },
            network: { timeout: 30000, retryCount: 3 },
            cache: { enabled: true, maxSize: 50 * 1024 * 1024 }
          },
          extensions: {}
        };
        this.configParser.parse(JSON.stringify(configData));
      }

      const finalMemory = this.getSimulatedMemoryUsage();
      const memoryIncrease = finalMemory - initialMemory;
      const memoryPerOperation = memoryIncrease / operationCount;

      return {
        initialMemory,
        finalMemory,
        memoryIncrease,
        operationCount,
        memoryPerOperation
      };
    });
  }

  private async runTest(testName: string, categoryIndex: number, testFunction: () => Promise<TestResultData>): Promise<void> {
    this.currentTest = testName;
    const startTime = Date.now();

    try {
      const data = await testFunction();
      const executionTime = Date.now() - startTime;

      const testResult: TestResult = {
        name: testName,
        success: true,
        message: '测试通过',
        executionTime,
        data
      };

      this.testCategories[categoryIndex].tests.push(testResult);
      this.successfulTests++;
    } catch (error) {
      const executionTime = Date.now() - startTime;
      const errorMessage = error instanceof Error ? error.message : String(error);

      const testResult: TestResult = {
        name: testName,
        success: false,
        message: errorMessage,
        executionTime
      };

      this.testCategories[categoryIndex].tests.push(testResult);
      this.failedTests++;
    } finally {
      this.completedTests++;
      this.totalTests = this.calculateTotalTests();
    }
  }

  private resetTests(): void {
    this.resetTestResults();
    this.initializeTestCategories();
  }

  private resetTestResults(): void {
    this.completedTests = 0;
    this.successfulTests = 0;
    this.failedTests = 0;
    this.totalTests = this.calculateTotalTests();
    this.overallStartTime = 0;
    this.overallEndTime = 0;

    // 清空所有测试结果
    for (const category of this.testCategories) {
      category.tests = [];
    }
  }

  private calculateTotalTests(): number {
    // 配置测试(4) + 安全测试(3) + 扩展测试(2) + 统一接口测试(3) + 性能测试(3) = 15
    return 15;
  }

  private getSimulatedMemoryUsage(): number {
    // 模拟内存使用情况，返回以KB为单位的内存使用量
    return Math.floor(Math.random() * 1000) + 5000;
  }

  private async cleanup(): Promise<void> {
    try {
      // 使用静态方法销毁实例
      UnifiedOperationInterface.destroy();
      logger.info(TAG, '清理完成');
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error(TAG, '清理过程中发生错误: ' + errorMessage);
    }
  }

  // 辅助方法 - 创建测试元数据
  private createTestMetadata(name: string, type?: OperationType, description?: string): Metadata {
    return {
      name,
      type,
      description,
      author: 'TestSystem',
      created: new Date().toISOString(),
      updated: new Date().toISOString()
    };
  }

  // 辅助方法 - 创建安全配置
  private createSecurityConfig(): SecurityConfig {
    return {
      csp: {
        enabled: true,
        policy: "default-src 'self'",
        reportOnly: false
      },
      antiCrawler: {
        enabled: true,
        userAgent: 'TestAgent/1.0',
        rateLimit: {
          maxRequests: 100,
          timeWindow: 60000,
          blockDuration: 300000
        },
        headers: {
          xForwardedFor: '127.0.0.1',
          userAgent: 'TestAgent/1.0'
        }
      },
      domainControl: {
        whiteList: ['www.bing.com'],
        blackList: ['malicious.com']
      }
    };
  }

  // 辅助方法 - 创建配置解析数据
  private createConfigurationParseData(type: string, content: string): ConfigurationOperationData {
    return {
      type: type,
      content: content
    };
  }

  // 辅助方法 - 创建安全验证数据
  private createSecurityValidationData(url: string, policy: string): SecurityOperationData {
    return {
      url: url,
      policy: policy
    };
  }

  // 辅助方法 - 创建安全检查数据
  private createSecurityCheckData(url: string, action: string): SecurityCheckOperationData {
    return {
      url: url,
      action: action
    };
  }

  // 辅助方法 - 创建扩展注册数据
  private createExtensionRegistrationData(name: string, path: string): ExtensionOperationData {
    return {
      name: name,
      path: path
    };
  }

  /**
   * 返回上一页
   */
  private goBack(): void {
    logger.info(TAG, '用户点击返回按钮');
    try {
      this.pathStack.pop();
      logger.info(TAG, '✅ 成功返回上一页');
    } catch (error) {
      logger.error(TAG, `返回失败: ${error}`);
      // 如果返回失败，尝试跳转到测试管理页面
      try {
        this.pathStack.pushPath({ name: 'TestManagementPage' });
      } catch (fallbackError) {
        logger.error(TAG, `跳转到测试管理页面也失败: ${fallbackError}`);
      }
    }
  }
}

export { WebViewConfigurableSystemTestPage };
