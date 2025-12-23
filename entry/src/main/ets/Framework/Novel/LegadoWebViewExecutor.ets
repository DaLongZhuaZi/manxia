/**
 * Legado WebView执行器
 * 提供后台WebView执行JS、加载网页、获取源码等功能
 * 
 * 文件路径: entry/src/main/ets/Framework/Novel/LegadoWebViewExecutor.ets
 */

import { webview } from '@kit.ArkWeb';
import { http } from '@kit.NetworkKit';
import { logger } from '../../Utils/Logger';
import { getCookieStore } from './LegadoCookieStore';

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
  /** 源正则（用于拦截资源URL） */
  sourceRegex?: string;
  /** 跳转URL正则（用于拦截跳转） */
  overrideUrlRegex?: string;
  /** 标签（用于Cookie管理） */
  tag?: string;
}

/**
 * WebView任务
 */
interface WebViewTask {
  options: WebViewOptions;
  resolve: (result: WebViewResult) => void;
  reject: (error: Error) => void;
  timeoutId?: number;
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
    return new Promise((resolve, reject) => {
      const task: WebViewTask = {
        options,
        resolve,
        reject
      };

      // 设置超时
      const timeout = options.timeout || 30000;
      task.timeoutId = setTimeout(() => {
        if (this.currentTask === task) {
          this.currentTask = null;
          this.isProcessing = false;
          reject(new Error('WebView执行超时'));
          this.processNextTask();
        } else {
          // 从队列中移除
          const index = this.taskQueue.indexOf(task);
          if (index > -1) {
            this.taskQueue.splice(index, 1);
            reject(new Error('WebView执行超时（等待中）'));
          }
        }
      }, timeout) as number;

      this.taskQueue.push(task);
      this.processNextTask();
    });
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
    this.executeTask(this.currentTask);
  }

  /**
   * 执行单个任务
   */
  private async executeTask(task: WebViewTask): Promise<void> {
    const options = task.options;
    const resolve = task.resolve;
    const reject = task.reject;
    const timeoutId = task.timeoutId;

    try {
      // 清除超时
      if (timeoutId) {
        clearTimeout(timeoutId);
      }

      let result: WebViewResult;

      if (options.html) {
        // 加载HTML内容
        result = await this.loadHtml(options);
      } else if (options.url) {
        // 加载URL
        result = await this.loadUrl(options);
      } else if (options.javaScript) {
        // 仅执行JS
        result = await this.executeJs(options.javaScript);
      } else {
        throw new Error('无效的WebView选项：需要url、html或javaScript');
      }

      resolve(result);
    } catch (error) {
      reject(error instanceof Error ? error : new Error(String(error)));
    } finally {
      this.currentTask = null;
      this.isProcessing = false;
      this.processNextTask();
    }
  }

  /**
   * 加载HTML内容
   */
  private async loadHtml(options: WebViewOptions): Promise<WebViewResult> {
    if (!this.webviewController) {
      throw new Error('WebView控制器未设置');
    }

    return new Promise((resolve, reject) => {
      try {
        const baseUrl = options.url || 'about:blank';
        
        // 设置页面加载完成回调
        this.pageLoadCallback = async (loadedUrl: string) => {
          try {
            let body = '';
            
            if (options.javaScript) {
              // 执行JS获取结果
              const jsResult = await this.runJavaScript(options.javaScript);
              body = jsResult;
            } else {
              // 获取页面源码
              body = await this.getPageSource();
            }

            // 获取Cookie
            const cookies = await this.getCookies(baseUrl);

            resolve({
              success: true,
              body: body,
              url: loadedUrl,
              cookies: cookies
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
  private async loadUrl(options: WebViewOptions): Promise<WebViewResult> {
    if (!this.webviewController) {
      throw new Error('WebView控制器未设置');
    }

    return new Promise((resolve, reject) => {
      try {
        const url = options.url!;
        this.interceptedUrl = '';

        // 设置页面加载完成回调
        this.pageLoadCallback = async (loadedUrl: string) => {
          try {
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

            // 获取Cookie
            const cookies = await this.getCookies(url);

            // 保存Cookie到持久化存储
            if (cookies && options.tag) {
              const cookieStore = getCookieStore();
              await cookieStore.setCookie(url, cookies);
            }

            resolve({
              success: true,
              body: body,
              url: loadedUrl,
              cookies: cookies
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
              // 去除引号
              if (result.startsWith('"') && result.endsWith('"')) {
                resolve(result.slice(1, -1));
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
   * 获取Cookie
   */
  private async getCookies(url: string): Promise<string> {
    try {
      return await this.runJavaScript('document.cookie');
    } catch (error) {
      logger.warn(TAG, `获取Cookie失败: ${String(error)}`);
      return '';
    }
  }

  /**
   * 页面加载完成回调（由WebView组件调用）
   */
  onPageFinish(url: string): void {
    logger.debug(TAG, `页面加载完成: ${url}`);
    if (this.pageLoadCallback) {
      this.pageLoadCallback(url);
    }
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
      this.currentTask.reject(new Error(`页面加载错误: ${description}`));
      this.currentTask = null;
      this.isProcessing = false;
      this.processNextTask();
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
      task.reject(new Error('WebView执行器已销毁'));
    }
    this.taskQueue = [];
    this.currentTask = null;
    this.isProcessing = false;
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
