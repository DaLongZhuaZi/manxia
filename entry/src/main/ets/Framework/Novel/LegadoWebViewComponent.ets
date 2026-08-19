/**
 * Legado隐藏WebView组件
 * 用于后台执行JS和加载网页，不显示在UI上
 * 
 * 文件路径: entry/src/main/ets/Framework/Novel/LegadoWebViewComponent.ets
 */

import { webview } from '@kit.ArkWeb';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { getWebViewExecutor } from './LegadoWebViewExecutor';
import { getLegadoJsEngine } from './LegadoJsEngine';
import { getLegadoRuntimeV2 } from './LegadoRuntimeV2';
import { getLegadoRuntimeAssetManager } from './LegadoRuntimeAssetManager';

const TAG = 'LegadoWebViewComponent';

/**
 * Legado隐藏WebView组件
 * 在页面中嵌入此组件以启用WebView功能
 */
@Component
export struct LegadoWebViewComponent {
  // ArkWeb navigation replaces a controller's document. Keep the JS runtime
  // document isolated so a source's webView request cannot evict RuntimeV2.
  private runtimeWebviewController: webview.WebviewController = new webview.WebviewController();
  private transportWebviewController: webview.WebviewController = new webview.WebviewController();
  @State private isInitialized: boolean = false;
  @State private runtimeSrc: ResourceStr = $rawfile('legado_runtime.html');
  @State private transportSrc: ResourceStr = 'about:blank';
  private usingBundledRuntime: boolean = true;
  private runtimeReady: boolean = false;

  aboutToAppear(): void {
    logger.info(TAG, 'LegadoWebView组件初始化');
    this.resolveRuntimeSource();
  }

  aboutToDisappear(): void {
    logger.info(TAG, 'LegadoWebView组件销毁');
    // 停止WebView加载，释放WebView资源
    try {
      this.runtimeWebviewController.stop();
    } catch (_e) {}
    try {
      this.transportWebviewController.stop();
    } catch (_e) {}
    try {
      getWebViewExecutor().destroy();
    } catch (_e) {}
    // 重置JS引擎的WebView引用，防止单例持有已销毁的WebView
    try {
      getLegadoJsEngine().reset();
    } catch (_e) {}
    try {
      getLegadoRuntimeV2().reset();
    } catch (_e) {}
  }

  build() {
    Stack() {
      // 使用本地HTML页面而不是about:blank，避免跨域限制
      Web({
        src: this.runtimeSrc,
        controller: this.runtimeWebviewController
      })
        .id('legado_runtime_webview_host')
        .width(1)
        .height(1)
        .opacity(0)
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .fileAccess(true)
        .imageAccess(true)
        .mixedMode(MixedMode.All)
        .cacheMode(CacheMode.Default)
        .onControllerAttached(() => {
          this.onRuntimeWebViewReady();
        })
        .onPageBegin((event) => {
          if (event) {
            this.onRuntimePageBegin(event.url);
          }
        })
        .onPageEnd((event) => {
          if (event) {
            this.onRuntimePageFinish(event.url);
          }
        })
        .onErrorReceive((event) => {
          if (event && event.error && event.request.isMainFrame()) {
            this.onRuntimePageError(
              event.error.getErrorCode(),
              event.error.getErrorInfo(),
              event.request.getRequestUrl()
            );
          }
        })
        .onHttpErrorReceive((event) => {
          if (event && event.response && event.request.isMainFrame()) {
            const code = event.response.getResponseCode();
            if (code >= 400) {
              this.onRuntimePageError(
                code,
                `HTTP Error: ${code}`,
                event.request.getRequestUrl()
              );
            }
          }
        })
      Web({
        src: this.transportSrc,
        controller: this.transportWebviewController
      })
        .id('legado_transport_webview_host')
        .width(1)
        .height(1)
        .opacity(0)
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .fileAccess(true)
        .imageAccess(true)
        .mixedMode(MixedMode.All)
        .cacheMode(CacheMode.Default)
        .onControllerAttached(() => {
          this.onTransportWebViewReady();
        })
        .onPageBegin((event) => {
          if (event) {
            this.onTransportPageBegin(event.url);
          }
        })
        .onPageEnd((event) => {
          if (event) {
            this.onTransportPageFinish(event.url);
          }
        })
        .onErrorReceive((event) => {
          if (event && event.error && event.request.isMainFrame()) {
            this.onTransportPageError(
              event.error.getErrorCode(),
              event.error.getErrorInfo(),
              event.request.getRequestUrl()
            );
          }
        })
        .onHttpErrorReceive((event) => {
          if (event && event.response && event.request.isMainFrame()) {
            const code = event.response.getResponseCode();
            if (code >= 400) {
              this.onTransportPageError(
                code,
                `HTTP Error: ${code}`,
                event.request.getRequestUrl()
              );
            }
          }
        })
        .onInterceptRequest((event) => {
          if (event && event.request) {
            this.onResourceRequest(event.request.getRequestUrl());
          }
          return null; // 不拦截，继续正常加载
        })
    }
    .width(1)
    .height(1)
  }

  /**
   * WebView就绪回调
   */
  private onRuntimeWebViewReady(): void {
    if (this.isInitialized) {
      return;
    }
    
    this.isInitialized = true;
    logger.info(TAG, 'WebView控制器已就绪');
    
    // RuntimeV2 must keep its rawfile document for runJavaScript calls.
    const jsEngine = getLegadoJsEngine();
    jsEngine.setWebviewController(this.runtimeWebviewController);
    
    this.configureWebView();
  }

  private onTransportWebViewReady(): void {
    getWebViewExecutor().setWebviewController(this.transportWebviewController);
    this.configureWebView();
  }

  private resolveRuntimeSource(): void {
    try {
      const runtimeUrl = getLegadoRuntimeAssetManager().getRuntimeEntryUrl('legado');
      if (runtimeUrl.startsWith('file://')) {
        this.runtimeSrc = runtimeUrl;
        this.usingBundledRuntime = false;
        logger.info(TAG, `使用云端Legado运行时: ${runtimeUrl}`);
        return;
      }
    } catch (error) {
      logger.warn(TAG, `读取云端Legado运行时失败，回退内置资源: ${String(error)}`);
    }
    this.runtimeSrc = $rawfile('legado_runtime.html');
    this.usingBundledRuntime = true;
  }

  /**
   * 配置WebView
   */
  private configureWebView(): void {
    try {
      // 启用调试（开发模式）
      webview.WebviewController.setWebDebuggingAccess(true);

      // A source header owns request-level User-Agent semantics. Leaving the
      // controller untouched here preserves ArkWeb's platform default when a
      // Legado source deliberately provides an empty User-Agent value.
      logger.debug(TAG, 'WebView配置完成');
    } catch (error) {
      logger.warn(TAG, `WebView配置失败: ${String(error)}`);
    }
  }

  /**
   * 页面开始加载回调
   */
  private onRuntimePageBegin(url: string): void {
    logger.debug(TAG, `Runtime页面开始加载: ${url}`);
  }

  private onTransportPageBegin(url: string): void {
    const executor = getWebViewExecutor();
    executor.onPageBegin(url);
  }

  /**
   * 页面加载完成回调
   */
  private onRuntimePageFinish(url: string): void {
    logger.debug(TAG, `Runtime页面加载完成: ${url}`);
    void this.checkRuntimeHealthAfterPageFinish();
  }

  private onTransportPageFinish(url: string): void {
    logger.debug(TAG, `传输页面加载完成: ${url}`);
    const executor = getWebViewExecutor();
    executor.onPageFinish(url);
  }

  private async checkRuntimeHealthAfterPageFinish(): Promise<void> {
    if (this.runtimeReady) {
      return;
    }
    const ok = await getLegadoRuntimeV2().setWebviewControllerWhenReady(this.runtimeWebviewController);
    if (ok) {
      this.runtimeReady = true;
      return;
    }
    if (!this.usingBundledRuntime) {
      logger.warn(TAG, '云端Legado运行时健康检查失败，回退内置运行时');
      this.loadBundledRuntime();
    }
  }

  /**
   * 资源请求回调
   */
  private onResourceRequest(url: string): void {
    const executor = getWebViewExecutor();
    executor.onResourceRequest(url);
  }

  /**
   * 页面加载错误回调
   */
  private onRuntimePageError(errorCode: number, description: string, url: string): void {
    logger.error(TAG, `Runtime页面加载错误: ${url}, code: ${errorCode}, desc: ${description}`);
    if (!this.usingBundledRuntime) {
      logger.warn(TAG, '云端Legado运行时加载失败，回退内置运行时');
      this.loadBundledRuntime();
    }
  }

  private onTransportPageError(errorCode: number, description: string, url: string): void {
    logger.error(TAG, `传输页面加载错误: ${url}, code: ${errorCode}, desc: ${description}`);
    const executor = getWebViewExecutor();
    executor.onPageError(errorCode, description, url);
  }

  private loadBundledRuntime(): void {
    this.usingBundledRuntime = true;
    this.runtimeReady = false;
    this.runtimeSrc = $rawfile('legado_runtime.html');
    try {
      this.runtimeWebviewController.loadUrl($rawfile('legado_runtime.html'));
    } catch (error) {
      logger.warn(TAG, `加载内置Legado运行时失败: ${String(error)}`);
    }
  }
}

/**
 * 全局WebView管理器
 * 用于在应用级别管理WebView组件
 */
export class LegadoWebViewManager {
  private static instance: LegadoWebViewManager | null = null;
  private isComponentMounted: boolean = false;

  private constructor() {}

  static getInstance(): LegadoWebViewManager {
    if (!LegadoWebViewManager.instance) {
      LegadoWebViewManager.instance = new LegadoWebViewManager();
    }
    return LegadoWebViewManager.instance;
  }

  /**
   * 标记组件已挂载
   */
  setComponentMounted(mounted: boolean): void {
    this.isComponentMounted = mounted;
    logger.info(TAG, `WebView组件挂载状态: ${mounted}`);
  }

  /**
   * 检查组件是否已挂载
   */
  isComponentReady(): boolean {
    return this.isComponentMounted;
  }

  /**
   * 检查WebView是否可用
   */
  isWebViewAvailable(): boolean {
    const executor = getWebViewExecutor();
    return executor.isWebViewReady();
  }
}

/**
 * 获取WebView管理器实例
 */
export function getWebViewManager(): LegadoWebViewManager {
  return LegadoWebViewManager.getInstance();
}
