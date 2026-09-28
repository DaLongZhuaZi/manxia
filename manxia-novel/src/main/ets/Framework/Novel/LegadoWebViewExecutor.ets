/**
 * Legado WebView执行器
 * 提供后台WebView执行JS、加载网页、获取源码等功能
 * 
 * 文件路径: entry/src/main/ets/Framework/Novel/LegadoWebViewExecutor.ets
 */

import { webview } from '@kit.ArkWeb';
import { http } from '@kit.NetworkKit';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { getCookieStore } from './LegadoCookieStore';
import {
  LegadoExecutionCancellationToken,
  createLegadoExecutionCancelledError
} from './LegadoExecutionCancellation';

const TAG = 'LegadoWebViewExecutor';

/**
 * WebView执行结果
 */
export interface WebViewResult {
  success: boolean;
  body: string;
  url: string;
  error?: string;
  cookies?: string;
  /** Redacted, fixed-grammar DOM state for ArkWeb conformance evidence. */
  diagnostic?: string;
  /** Main-document HTTP failure code, present only for an HTTP error. */
  statusCode?: number;
}

/**
 * WebView执行选项
 */
export interface WebViewOptions {
  /** 要加载的URL */
  url?: string;
  /** 直接加载的HTML内容 */
  html?: string;
  /** 执行的JavaScript代码 */
  javaScript?: string;
  /** 请求头 */
  headers?: Record<string, string>;
  /** 超时时间（毫秒） */
  timeout?: number;
  /** Legado waits after page completion before evaluating the DOM. */
  postLoadDelayTime?: number;
  /** 源正则（用于拦截资源URL） */
  sourceRegex?: string;
  /** 跳转URL正则（用于拦截跳转） */
  overrideUrlRegex?: string;
  /** 标签（用于Cookie管理） */
  tag?: string;
  /** V2 调用方的源级取消令牌 */
  cancellationToken?: LegadoExecutionCancellationToken;
}

/**
 * WebView任务
 */
interface WebViewTask {
  options: WebViewOptions;
  resolve: (result: WebViewResult) => void;
  reject: (error: Error) => void;
  timeoutId?: number;
  cancellationListenerId: number;
  settled: boolean;
  /**
   * A deliberately URL-free lifecycle snapshot. It is included in timeout
   * errors so a real-device ArkWeb timeout remains diagnosable without
   * putting an endpoint, cookies, or page content in the execution trace.
   */
  lifecycleStage: string;
  pageBeginCount: number;
  targetNavigationBeginCount: number;
  runtimePageBeginCount: number;
  nonRuntimePageBeginCount: number;
  pageEndCount: number;
  mainFrameErrorCount: number;
  lastMainFrameStatusCode: number;
}

/**
 * Legado WebView执行器
 * 管理后台WebView实例，执行网页加载和JS执行
 */
export class LegadoWebViewExecutor {
  private static instance: LegadoWebViewExecutor | null = null;
  private webviewController: webview.WebviewController | null = null;
  private isReady: boolean = false;
  private currentTask: WebViewTask | null = null;
  private taskQueue: WebViewTask[] = [];
  private isProcessing: boolean = false;
  private pageLoadCallback: ((url: string) => void) | null = null;
  private interceptedUrl: string = '';
  private expectedNavigationUrl: string = '';
  private currentTaskNavigationStarted: boolean = false;
  private currentTaskNavigationUrl: string = '';
  private platformUserAgent: string = '';

  private constructor() {}

  static getInstance(): LegadoWebViewExecutor {
    if (!LegadoWebViewExecutor.instance) {
      LegadoWebViewExecutor.instance = new LegadoWebViewExecutor();
    }
    return LegadoWebViewExecutor.instance;
  }

  /**
   * 设置WebView控制器
   */
  setWebviewController(controller: webview.WebviewController): void {
    this.webviewController = controller;
    try {
      this.platformUserAgent = controller.getCustomUserAgent();
    } catch (error) {
      this.platformUserAgent = '';
      logger.debug(TAG, `读取 ArkWeb 平台 User-Agent 失败: ${String(error)}`);
    }
    this.isReady = true;
    logger.info(TAG, 'WebView控制器已设置');
    this.processNextTask();
  }

  /**
   * 检查WebView是否就绪
   */
  isWebViewReady(): boolean {
    return this.isReady && this.webviewController !== null;
  }

  /**
   * 使用WebView访问网络
   * @param html 直接用webView载入的html, 如果html为空直接访问url
   * @param url html内如果有相对路径的资源不传入url访问不了
   * @param js 用来取返回值的js语句, 没有就返回整个源代码
   * @returns 返回js获取的内容
   */
  async webView(html: string | null, url: string | null, js: string | null): Promise<string> {
    const result = await this.execute({
      url: url || undefined,
      html: html || undefined,
      javaScript: js || undefined,
      timeout: 30000
    });
    return result.body;
  }

  /**
   * 使用WebView获取资源URL
   */
  async webViewGetSource(
    html: string | null,
    url: string | null,
    js: string | null,
    sourceRegex: string
  ): Promise<string> {
    const result = await this.execute({
      url: url || undefined,
      html: html || undefined,
      javaScript: js || undefined,
      sourceRegex: sourceRegex,
      timeout: 30000
    });
    return result.body;
  }

  /**
   * 使用WebView获取跳转URL
   */
  async webViewGetOverrideUrl(
    html: string | null,
    url: string | null,
    js: string | null,
    overrideUrlRegex: string
  ): Promise<string> {
    const result = await this.execute({
      url: url || undefined,
      html: html || undefined,
      javaScript: js || undefined,
      overrideUrlRegex: overrideUrlRegex,
      timeout: 30000
    });
    return result.body;
  }

  /**
   * 执行WebView任务
   */
  async execute(options: WebViewOptions): Promise<WebViewResult> {
    options.cancellationToken?.throwIfCancelled();
    return new Promise((resolve, reject) => {
      const task: WebViewTask = {
        options,
        resolve,
        reject,
        cancellationListenerId: 0,
        settled: false,
        lifecycleStage: 'queued',
        pageBeginCount: 0,
        targetNavigationBeginCount: 0,
        runtimePageBeginCount: 0,
        nonRuntimePageBeginCount: 0,
        pageEndCount: 0,
        mainFrameErrorCount: 0,
        lastMainFrameStatusCode: 0
      };

      // 设置超时
      const timeout = options.timeout || 30000;
      task.timeoutId = setTimeout(() => {
        this.abortTask(task, new Error(this.buildTimeoutDiagnostic(task)));
      }, timeout) as number;

      if (options.cancellationToken !== undefined) {
        task.cancellationListenerId = options.cancellationToken.register((reason: string): void => {
          this.abortTask(task, createLegadoExecutionCancelledError(reason));
        });
      }
      if (!task.settled) {
        this.taskQueue.push(task);
        this.processNextTask();
      }
    });
  }

  private abortTask(task: WebViewTask, error: Error): void {
    if (task.settled) {
      return;
    }
    if (this.currentTask === task) {
      try {
        if (this.webviewController !== null) {
          this.webviewController.stop();
        }
      } catch (stopError) {
        logger.warn(TAG, `停止 WebView 任务失败: ${String(stopError)}`);
      }
    } else {
      const index = this.taskQueue.indexOf(task);
      if (index >= 0) {
        this.taskQueue.splice(index, 1);
      }
    }
    this.completeTask(task, null, error);
  }

  /**
   * 处理下一个任务
   */
  private processNextTask(): void {
    if (this.isProcessing || this.taskQueue.length === 0) {
      return;
    }

    if (!this.isWebViewReady()) {
      logger.warn(TAG, 'WebView未就绪，任务等待中');
      return;
    }

    this.isProcessing = true;
    this.currentTask = this.taskQueue.shift()!;
    this.currentTask.lifecycleStage = 'active';
    this.executeTask(this.currentTask);
  }

  /**
   * 执行单个任务
   */
  private async executeTask(task: WebViewTask): Promise<void> {
    const options = task.options;

    try {
      let result: WebViewResult;

      if (options.html) {
        task.lifecycleStage = 'html_loading';
        // 加载HTML内容
        result = await this.loadHtml(options, task);
      } else if (options.url) {
        task.lifecycleStage = 'url_loading';
        // 加载URL
        result = await this.loadUrl(options, task);
      } else if (options.javaScript) {
        task.lifecycleStage = 'javascript_running';
        // 仅执行JS
        result = await this.executeJs(options.javaScript);
      } else {
        throw new Error('无效的WebView选项：需要url、html或javaScript');
      }

      this.completeTask(task, result, null);
    } catch (error) {
      this.completeTask(task, null, error instanceof Error ? error : new Error(String(error)));
    }
  }

  /** Completes exactly once and keeps the timeout active until this point. */
  private completeTask(task: WebViewTask, result: WebViewResult | null, error: Error | null): void {
    if (task.settled) {
      return;
    }
    task.settled = true;
    if (task.timeoutId !== undefined) {
      clearTimeout(task.timeoutId);
      task.timeoutId = undefined;
    }
    if (task.options.cancellationToken !== undefined && task.cancellationListenerId > 0) {
      task.options.cancellationToken.unregister(task.cancellationListenerId);
      task.cancellationListenerId = 0;
    }
    if (this.currentTask === task) {
      this.currentTask = null;
      this.isProcessing = false;
      this.pageLoadCallback = null;
      this.expectedNavigationUrl = '';
      this.currentTaskNavigationStarted = false;
      this.currentTaskNavigationUrl = '';
    }
    if (error) {
      task.reject(error);
    } else if (result) {
      task.resolve(result);
    } else {
      task.reject(new Error('WebView任务没有结果'));
    }
    this.processNextTask();
  }

  private buildTimeoutDiagnostic(task: WebViewTask): string {
    const ownership: string = this.currentTask === task ? 'active' : 'queued';
    return `WEBVIEW_TIMEOUT;ownership=${ownership};stage=${task.lifecycleStage};pageBegin=${task.pageBeginCount};targetBegin=${task.targetNavigationBeginCount};runtimeBegin=${task.runtimePageBeginCount};nonRuntimeBegin=${task.nonRuntimePageBeginCount};pageEnd=${task.pageEndCount};mainFrameError=${task.mainFrameErrorCount};httpStatus=${task.lastMainFrameStatusCode}`;
  }

  private buildPageErrorDiagnostic(task: WebViewTask, errorCode: number): string {
    const ownership: string = this.currentTask === task ? 'active' : 'queued';
    return `WEBVIEW_ERROR;ownership=${ownership};stage=${task.lifecycleStage};pageBegin=${task.pageBeginCount};targetBegin=${task.targetNavigationBeginCount};runtimeBegin=${task.runtimePageBeginCount};nonRuntimeBegin=${task.nonRuntimePageBeginCount};pageEnd=${task.pageEndCount};mainFrameError=${task.mainFrameErrorCount};errorCode=${errorCode}`;
  }

  /**
   * 加载HTML内容
   */
  private async loadHtml(options: WebViewOptions, task: WebViewTask): Promise<WebViewResult> {
    if (!this.webviewController) {
      throw new Error('WebView控制器未设置');
    }

    return new Promise((resolve, reject) => {
      try {
        const baseUrl = options.url || 'about:blank';
        
        // 设置页面加载完成回调
        this.pageLoadCallback = async (loadedUrl: string) => {
          if (task.settled || this.currentTask !== task) {
            return;
          }
          try {
            task.lifecycleStage = 'post_load_waiting';
            // Original Legado's BackstageWebView waits one second after every
            // onPageFinished callback, plus webViewDelayTime, before it
            // evaluates document.documentElement.outerHTML. Dynamic search
            // tables otherwise appear as a successful but empty response.
            await this.waitForPageContent(task, options.postLoadDelayTime || 0);
            if (task.settled || this.currentTask !== task) {
              return;
            }
            task.lifecycleStage = 'page_content_extracting';
            let body = '';
            
            if (options.javaScript) {
              // 执行JS获取结果
              const jsResult = await this.runJavaScript(options.javaScript);
              body = jsResult;
            } else {
              // 获取页面源码
              body = await this.getPageSource();
            }
            const diagnostic = await this.getPageStructureDiagnostic();

            // 获取Cookie
            const cookies = await this.getCookies(baseUrl);

            resolve({
              success: true,
              body: body,
              url: loadedUrl,
              cookies: cookies,
              diagnostic: diagnostic
            });
          } catch (error) {
            reject(error);
          }
          this.pageLoadCallback = null;
        };

        // 加载HTML
        if (this.webviewController) {
          this.webviewController.loadData(
            options.html!,
            'text/html',
            'UTF-8',
            baseUrl
          );
        }
      } catch (error) {
        reject(error);
      }
    });
  }

  /**
   * 加载URL
   */
  private async loadUrl(options: WebViewOptions, task: WebViewTask): Promise<WebViewResult> {
    if (!this.webviewController) {
      throw new Error('WebView控制器未设置');
    }

    const url = options.url!;
    this.applyRequestUserAgent(options.headers);
    await this.syncCompatibilityCookiesToWebEngine(url);
    task.lifecycleStage = 'cookies_synchronized';
    this.expectedNavigationUrl = url;
    this.currentTaskNavigationStarted = false;
    this.currentTaskNavigationUrl = '';

    return new Promise((resolve, reject) => {
      try {
        this.interceptedUrl = '';
        task.lifecycleStage = 'navigation_waiting';

        // 设置页面加载完成回调
        this.pageLoadCallback = async (loadedUrl: string) => {
          if (task.settled || this.currentTask !== task) {
            return;
          }
          try {
            task.lifecycleStage = 'post_load_waiting';
            await this.waitForPageContent(task, options.postLoadDelayTime || 0);
            if (task.settled || this.currentTask !== task) {
              return;
            }
            task.lifecycleStage = 'page_content_extracting';
            let body = '';

            // 检查是否有拦截的URL
            if (options.sourceRegex && this.interceptedUrl) {
              body = this.interceptedUrl;
            } else if (options.overrideUrlRegex && this.interceptedUrl) {
              body = this.interceptedUrl;
            } else if (options.javaScript) {
              // 执行JS获取结果
              body = await this.runJavaScript(options.javaScript);
            } else {
              // 获取页面源码
              body = await this.getPageSource();
            }
            const diagnostic = await this.getPageStructureDiagnostic();

            // 获取Cookie
            const cookies = await this.getCookies(url);

            // 浏览器 API 返回的是 Cookie 请求头而不是 Set-Cookie 响应头。
            // 因此需按多条 name=value 记录写回，而不能按 Set-Cookie 属性解析。
            if (cookies.length > 0) {
              const cookieStore = getCookieStore();
              await cookieStore.setCookieHeader(url, cookies);
            }

            resolve({
              success: true,
              body: body,
              url: loadedUrl,
              cookies: cookies,
              diagnostic: diagnostic
            });
          } catch (error) {
            reject(error);
          }
          this.pageLoadCallback = null;
        };

        // 设置请求头
        const headers: Array<webview.WebHeader> = [];
        if (options.headers) {
          for (const key of Object.keys(options.headers)) {
            headers.push({ headerKey: key, headerValue: options.headers[key] });
          }
        }

        // 加载URL
        if (this.webviewController) {
          task.lifecycleStage = 'navigation_dispatched';
          if (headers.length > 0) {
            this.webviewController.loadUrl(url, headers);
          } else {
            this.webviewController.loadUrl(url);
          }
        }
      } catch (error) {
        reject(error);
      }
    });
  }

  private async waitForPageContent(task: WebViewTask, configuredDelayTime: number): Promise<void> {
    const delayTime: number = 1000 + Math.max(0, configuredDelayTime);
    await new Promise<void>((resolve: () => void): void => {
      setTimeout((): void => {
        resolve();
      }, delayTime);
    });
  }

  /**
   * ArkWeb gives a controller-level custom User-Agent priority over the
   * User-Agent passed to loadUrl. Apply the planner's resolved source header
   * immediately before dispatch so WebView sources observe the same request
   * contract as HTTP sources.
   */
  private applyRequestUserAgent(headers?: Record<string, string>): void {
    if (this.webviewController === null) {
      return;
    }
    let userAgent = '';
    let hasSourceUserAgent = false;
    if (headers === undefined) {
      this.restorePlatformUserAgent();
      return;
    }
    const headerNames: string[] = Object.keys(headers);
    for (let index = 0; index < headerNames.length; index++) {
      const name: string = headerNames[index];
      if (name.toLowerCase() === 'user-agent') {
        hasSourceUserAgent = true;
        userAgent = headers[name];
        break;
      }
    }
    if (!hasSourceUserAgent) {
      this.restorePlatformUserAgent();
      return;
    }
    try {
      this.webviewController.setCustomUserAgent(userAgent);
      logger.debug(TAG, `已应用当前书源 User-Agent，状态=${userAgent.length === 0 ? 'explicit_empty' : 'explicit_value'}`);
    } catch (error) {
      // Preserve execution continuity: loadUrl still carries the merged
      // header even when this ArkWeb controller setting is unavailable.
      logger.warn(TAG, `应用当前书源 User-Agent 失败: ${String(error)}`);
    }
  }

  private restorePlatformUserAgent(): void {
    if (this.webviewController === null) {
      return;
    }
    try {
      this.webviewController.setCustomUserAgent(this.platformUserAgent);
    } catch (error) {
      logger.warn(TAG, `恢复 ArkWeb 平台 User-Agent 失败: ${String(error)}`);
    }
  }

  /**
   * 执行JavaScript
   */
  private async executeJs(js: string): Promise<WebViewResult> {
    try {
      const result = await this.runJavaScript(js);
      return {
        success: true,
        body: result,
        url: ''
      };
    } catch (error) {
      return {
        success: false,
        body: '',
        url: '',
        error: String(error)
      };
    }
  }

  /**
   * 运行JavaScript代码
   */
  private async runJavaScript(js: string): Promise<string> {
    if (!this.webviewController) {
      throw new Error('WebView控制器未设置');
    }

    return new Promise((resolve, reject) => {
      try {
        this.webviewController!.runJavaScript(js)
          .then((result) => {
            // 处理返回结果
            if (result === undefined || result === null) {
              resolve('');
            } else if (typeof result === 'string') {
              // ArkWeb may return a JSON-encoded JavaScript string. Merely
              // stripping the outer quotes leaves escaped HTML attributes in
              // the response, which makes the downstream DOM bridge observe
              // no elements even though the WebView document contains them.
              if (result.startsWith('"') && result.endsWith('"')) {
                try {
                  resolve(JSON.parse(result) as string);
                } catch (error) {
                  logger.debug(TAG, `ArkWeb JS 字符串 JSON 解码失败，保留兼容回退: ${String(error)}`);
                  resolve(result.slice(1, -1));
                }
              } else {
                resolve(result);
              }
            } else {
              resolve(String(result));
            }
          })
          .catch((error: Error) => {
            reject(error);
          });
      } catch (error) {
        reject(error);
      }
    });
  }

  /**
   * 获取页面源码
   */
  private async getPageSource(): Promise<string> {
    return this.runJavaScript('document.documentElement.outerHTML');
  }

  /**
   * Captures only a fixed structural grammar. This distinguishes a completed
   * but unexpected ArkWeb document from a selector regression without
   * retaining response HTML, title text, address, credentials, or cookies.
   */
  private async getPageStructureDiagnostic(): Promise<string> {
    const script = "(function(){var root=document.documentElement;var body=document.body;return 'DOM_STATE;ready=' + document.readyState + ';table=' + document.getElementsByTagName('table').length + ';tr=' + document.getElementsByTagName('tr').length + ';bodyChildren=' + (body ? body.children.length : 0) + ';htmlLength=' + (root ? root.outerHTML.length : 0);})()";
    try {
      const diagnostic = await this.runJavaScript(script);
      const safePattern: RegExp = /^DOM_STATE;ready=(loading|interactive|complete);table=\d+;tr=\d+;bodyChildren=\d+;htmlLength=\d+$/;
      return safePattern.test(diagnostic) ? diagnostic : '';
    } catch (error) {
      logger.debug(TAG, `读取 ArkWeb DOM 结构摘要失败: ${String(error)}`);
      return '';
    }
  }

  /**
   * 获取Cookie
   */
  private async getCookies(url: string): Promise<string> {
    try {
      await webview.WebCookieManager.saveCookieAsync();
    } catch (error) {
      logger.debug(TAG, `保存 ArkWeb Cookie 失败，继续读取当前 Cookie: ${String(error)}`);
    }

    try {
      const nativeCookies: string = await webview.WebCookieManager.fetchCookie(url);
      if (nativeCookies.trim().length > 0) {
        logger.debug(TAG, `从 ArkWeb Cookie 管理器读取 Cookie，长度=${nativeCookies.length}`);
        return nativeCookies;
      }
    } catch (error) {
      logger.debug(TAG, `从 ArkWeb Cookie 管理器读取 Cookie 失败，回退 document.cookie: ${String(error)}`);
    }

    try {
      const documentCookies: string = await this.runJavaScript('document.cookie');
      if (documentCookies.trim().length > 0) {
        logger.debug(TAG, `从 document.cookie 读取 Cookie，长度=${documentCookies.length}`);
      }
      return documentCookies;
    } catch (error) {
      logger.warn(TAG, `获取Cookie失败: ${String(error)}`);
      return '';
    }
  }

  /**
   * 将 V2 兼容 Cookie Jar 同步到 ArkWeb。这样 Web 页面脚本、跳转请求和资源
   * 请求都与 HTTP transport 共享同一份已验证的书源 Cookie 状态。
   */
  private async syncCompatibilityCookiesToWebEngine(url: string): Promise<void> {
    const cookieHeader: string = getCookieStore().getCookie(url);
    if (cookieHeader.trim().length === 0) {
      return;
    }

    const parts: string[] = cookieHeader.split(';');
    let importedCount: number = 0;
    for (let i = 0; i < parts.length; i++) {
      const cookie: string = parts[i].trim();
      const separator: number = cookie.indexOf('=');
      if (separator <= 0) {
        continue;
      }
      try {
        await webview.WebCookieManager.configCookie(url, `${cookie}; Path=/`);
        importedCount++;
      } catch (error) {
        logger.warn(TAG, `同步兼容 Cookie 到 ArkWeb 失败: ${String(error)}`);
      }
    }

    if (importedCount > 0) {
      try {
        await webview.WebCookieManager.saveCookieAsync();
      } catch (error) {
        logger.debug(TAG, `保存同步后的 ArkWeb Cookie 失败: ${String(error)}`);
      }
      logger.debug(TAG, `已同步 ${importedCount} 条兼容 Cookie 到 ArkWeb。`);
    }
  }

  /**
   * 页面开始加载回调（由WebView组件调用）。
   *
   * 隐藏 Web 组件会先加载 Legado 运行时页面；该页面的 onPageEnd 可能在任务
   * 已入队后才送达。只有确认目标 URL 已经开始导航，后续 onPageFinish 才能
   * 完成当前任务，避免把运行时页面误记为书源请求的最终 URL。
   */
  onPageBegin(url: string): void {
    if (!this.currentTask || !this.currentTask.options.url || this.currentTask.options.html) {
      return;
    }
    this.currentTask.pageBeginCount++;
    if (this.isExpectedNavigationStart(this.expectedNavigationUrl, url)) {
      this.currentTaskNavigationStarted = true;
      this.currentTaskNavigationUrl = url;
      this.currentTask.targetNavigationBeginCount++;
      this.currentTask.lifecycleStage = 'target_navigation_started';
      logger.debug(TAG, `当前任务页面开始加载: ${url}`);
      return;
    }
    if (this.isRuntimeOrBlankNavigation(url)) {
      this.currentTask.runtimePageBeginCount++;
      return;
    }
    this.currentTask.nonRuntimePageBeginCount++;
    // ArkWeb can report the first hop of a server redirect rather than the
    // planned URL. Once loadUrl has been dispatched, that first non-runtime
    // navigation is the task's real document start. Runtime/blank events are
    // still rejected above so a delayed hidden-runtime callback cannot finish
    // a source request.
    if (!this.currentTaskNavigationStarted) {
      this.currentTaskNavigationStarted = true;
      this.currentTaskNavigationUrl = url;
      this.currentTask.targetNavigationBeginCount++;
      this.currentTask.lifecycleStage = 'redirect_navigation_started';
      logger.debug(TAG, `当前任务页面通过跳转开始加载: ${url}`);
      return;
    }
    if (this.currentTaskNavigationStarted) {
      this.currentTaskNavigationUrl = url;
      this.currentTask.lifecycleStage = 'follow_up_navigation_started';
      logger.debug(TAG, `当前任务页面发生后续导航: ${url}`);
      return;
    }
    logger.debug(TAG, `忽略非当前任务的页面开始事件: ${url}`);
  }

  /**
   * 页面加载完成回调（由WebView组件调用）
   */
  onPageFinish(url: string): void {
    logger.debug(TAG, `页面加载完成: ${url}`);
    if (this.currentTask !== null) {
      this.currentTask.pageEndCount++;
    }
    if (this.currentTask && this.currentTask.options.url && !this.currentTask.options.html &&
      !this.currentTaskNavigationStarted) {
      logger.debug(TAG, `忽略目标导航开始前的页面完成事件: ${url}`);
      return;
    }
    if (this.currentTask && this.currentTask.options.url && !this.currentTask.options.html &&
      !this.isCurrentTaskNavigationFinish(url)) {
      logger.debug(TAG, `忽略过期导航的页面完成事件: ${url}`);
      return;
    }
    if (this.pageLoadCallback) {
      if (this.currentTask !== null) {
        this.currentTask.lifecycleStage = 'target_navigation_finished';
      }
      this.pageLoadCallback(url);
    }
  }

  private isExpectedNavigationStart(expectedUrl: string, actualUrl: string): boolean {
    const expected: string = expectedUrl.trim();
    const actual: string = actualUrl.trim();
    if (expected.length === 0 || actual.length === 0) {
      return false;
    }
    if (this.isEquivalentWebUrl(expected, actual)) {
      return true;
    }
    const expectedWithoutFragment: string = this.removeUrlFragment(expected);
    const actualWithoutFragment: string = this.removeUrlFragment(actual);
    return this.isEquivalentWebUrl(expectedWithoutFragment, actualWithoutFragment);
  }

  private isRuntimeOrBlankNavigation(url: string): boolean {
    const normalized: string = url.trim().toLowerCase();
    return normalized.startsWith('file://') || normalized.startsWith('about:blank') || normalized.startsWith('data:');
  }

  private isCurrentTaskNavigationFinish(actualUrl: string): boolean {
    const actual: string = actualUrl.trim();
    const active: string = this.currentTaskNavigationUrl.trim();
    if (actual.length === 0 || active.length === 0) {
      return false;
    }
    if (this.isEquivalentWebUrl(actual, active)) {
      return true;
    }
    if (!this.webviewController) {
      return false;
    }
    try {
      const controllerUrl: string = String(this.webviewController.getUrl()).trim();
      return controllerUrl.length > 0 && this.isEquivalentWebUrl(controllerUrl, actual);
    } catch (error) {
      logger.debug(TAG, `读取当前 ArkWeb 地址失败: ${String(error)}`);
      return false;
    }
  }

  /**
   * ArkWeb reports navigation URLs after its own percent-decoding and fragment
   * normalization. Compare their URL semantics so an encoded Legado keyword
   * cannot leave the active request waiting for an event it has already seen.
   */
  private isEquivalentWebUrl(left: string, right: string): boolean {
    const normalizedLeft: string = this.normalizeWebEventUrl(left);
    const normalizedRight: string = this.normalizeWebEventUrl(right);
    return normalizedLeft.length > 0 && normalizedLeft === normalizedRight;
  }

  private normalizeWebEventUrl(url: string): string {
    const withoutFragment: string = this.removeUrlFragment(url.trim());
    if (withoutFragment.length === 0) {
      return '';
    }
    try {
      return decodeURI(withoutFragment);
    } catch (error) {
      logger.debug(TAG, `规范化 ArkWeb 导航地址失败: ${String(error)}`);
      return withoutFragment;
    }
  }

  private removeUrlFragment(url: string): string {
    const fragmentIndex: number = url.indexOf('#');
    return fragmentIndex >= 0 ? url.substring(0, fragmentIndex) : url;
  }

  /**
   * 资源请求拦截回调（由WebView组件调用）
   */
  onResourceRequest(url: string): void {
    if (!this.currentTask) return;

    const options = this.currentTask.options;

    // 检查sourceRegex
    if (options.sourceRegex) {
      try {
        const regex = new RegExp(options.sourceRegex);
        if (regex.test(url)) {
          this.interceptedUrl = url;
          logger.debug(TAG, `拦截到资源URL: ${url}`);
        }
      } catch (e) {
        // 忽略正则错误
      }
    }

    // 检查overrideUrlRegex
    if (options.overrideUrlRegex) {
      try {
        const regex = new RegExp(options.overrideUrlRegex);
        if (regex.test(url)) {
          this.interceptedUrl = url;
          logger.debug(TAG, `拦截到跳转URL: ${url}`);
        }
      } catch (e) {
        // 忽略正则错误
      }
    }
  }

  /**
   * 页面加载错误回调（由WebView组件调用）
   */
  onPageError(errorCode: number, description: string, url: string): void {
    logger.error(TAG, `页面加载错误: ${url}, code: ${errorCode}, desc: ${description}`);
    if (this.currentTask) {
      this.currentTask.mainFrameErrorCount++;
      this.currentTask.lastMainFrameStatusCode = errorCode >= 400 ? errorCode : 0;
      this.currentTask.lifecycleStage = 'main_frame_error';
      this.completeTask(
        this.currentTask,
        {
          success: false,
          body: '',
          url: url,
          error: this.buildPageErrorDiagnostic(this.currentTask, errorCode),
          statusCode: errorCode >= 400 ? errorCode : undefined
        },
        null
      );
    }
  }

  /**
   * 清理资源
   */
  destroy(): void {
    // 清理所有等待中的任务
    for (const task of this.taskQueue) {
      if (task.timeoutId) {
        clearTimeout(task.timeoutId);
      }
      if (task.options.cancellationToken !== undefined && task.cancellationListenerId > 0) {
        task.options.cancellationToken.unregister(task.cancellationListenerId);
        task.cancellationListenerId = 0;
      }
      task.settled = true;
      task.reject(new Error('WebView执行器已销毁'));
    }
    this.taskQueue = [];
    if (this.currentTask) {
      this.completeTask(this.currentTask, null, new Error('WebView执行器已销毁'));
    }
    this.currentTask = null;
    this.isProcessing = false;
    this.expectedNavigationUrl = '';
    this.currentTaskNavigationStarted = false;
    this.currentTaskNavigationUrl = '';
    if (this.webviewController) {
      try {
        this.webviewController.stop();
      } catch (_e) {}
    }
    this.webviewController = null;
    this.isReady = false;
    LegadoWebViewExecutor.instance = null;
  }
}

/**
 * 获取WebView执行器实例
 */
export function getWebViewExecutor(): LegadoWebViewExecutor {
  return LegadoWebViewExecutor.getInstance();
}
