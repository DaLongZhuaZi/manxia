/**
 * 不可见的WebView组件包装器
 * 用于在后台运行WebView，支持自动化操作和数据抓取
 * 符合HarmonyOS API 18规范
 */

import { webview } from '@kit.ArkWeb';
import { logger } from '../../Utils/Logger';
import { WebViewSourceConfig } from './WebViewImageLoader';

const TAG = 'InvisibleWebViewComponent';

/**
 * WebView事件回调接口
 */
export interface WebViewEventCallbacks {
  /** 页面开始加载 */
  onPageBegin?: (url: string) => void;
  /** 页面加载完成 */
  onPageEnd?: (url: string) => void;
  /** 页面加载进度 */
  onProgressChange?: (progress: number) => void;
  /** 页面加载错误 */
  onError?: (error: string) => void;
  /** 控制台消息 */
  onConsoleMessage?: (message: string, level: string) => void;
}

/**
 * WebView实例数据接口
 */
export interface WebViewInstanceData {
  controller: webview.WebviewController;
  config: WebViewSourceConfig;
  callbacks?: WebViewEventCallbacks;
  createTime: number;
  lastUsedTime: number;
}

/**
 * 不可见WebView组件
 * 特点：
 * 1. 尺寸为1x1像素，完全透明
 * 2. 位于屏幕外（负坐标）
 * 3. 支持完整的WebView功能
 * 4. 提供事件回调机制
 */
@Component
export struct InvisibleWebView {
  /** WebView控制器 */
  @Prop controller: webview.WebviewController;
  /** WebView配置 */
  @Prop config: WebViewSourceConfig;
  /** 事件回调 */
  @Prop callbacks: WebViewEventCallbacks | null = null;
  /** 初始URL */
  @Prop @Watch('onInitialUrlChange') initialUrl: string = 'about:blank';
  
  /** 当前加载进度 */
  @State private loadProgress: number = 0;
  /** 是否正在加载 */
  @State private isLoading: boolean = false;

  /**
   * 监听初始URL变化
   */
  onInitialUrlChange() {
    if (this.initialUrl && this.initialUrl !== 'about:blank') {
      logger.debug(TAG, `初始URL变化: ${this.initialUrl}`);
    }
  }

  /**
   * 组件即将出现
   */
  aboutToAppear() {
    logger.info(TAG, `不可见WebView组件初始化, 源ID: ${this.config.sourceId}`);
    if (this.config.userAgent && this.config.userAgent.length > 0) {
      this.controller.setCustomUserAgent(this.config.userAgent);
    }
  }

  /**
   * 组件即将消失
   */
  aboutToDisappear() {
    logger.info(TAG, `不可见WebView组件销毁, 源ID: ${this.config.sourceId}`);
  }

  build() {
    // 使用Stack确保组件不可见但功能正常
    Stack() {
      Web({ 
        src: this.initialUrl, 
        controller: this.controller 
      })
        // ==================== 基础配置 ====================
        .width(1)  // 最小宽度
        .height(1) // 最小高度
        .opacity(0) // 完全透明
        
        // ==================== WebView功能配置 ====================
        .javaScriptAccess(this.config.enableJavaScript)
        .domStorageAccess(true)
        .imageAccess(this.config.enableImages)
        .mixedMode(MixedMode.All)
        .cacheMode(CacheMode.Default)
        .databaseAccess(true)
        .fileAccess(true)
        
        // ==================== 页面生命周期事件 ====================
        .onPageBegin((event) => {
          this.isLoading = true;
          this.loadProgress = 0;
          logger.debug(TAG, `页面开始加载: ${event.url}`);
          
          if (this.callbacks?.onPageBegin) {
            this.callbacks.onPageBegin(event.url);
          }
        })
        
        .onPageEnd((event) => {
          this.isLoading = false;
          this.loadProgress = 100;
          logger.debug(TAG, `页面加载完成: ${event.url}`);
          
          if (this.callbacks?.onPageEnd) {
            this.callbacks.onPageEnd(event.url);
          }
        })
        
        .onProgressChange((event) => {
          this.loadProgress = event.newProgress;
          
          if (this.callbacks?.onProgressChange) {
            this.callbacks.onProgressChange(event.newProgress);
          }
        })
        
        // ==================== 错误处理 ====================
        .onErrorReceive((event) => {
          const errorInfo = event.error.getErrorInfo();
          logger.error(TAG, `页面加载错误: ${errorInfo}`);
          
          if (this.callbacks?.onError) {
            this.callbacks.onError(errorInfo);
          }
        })
        
        .onHttpErrorReceive((event) => {
          logger.error(TAG, `HTTP错误: ${event.response.getResponseCode()}`);
        })
        
        // ==================== 控制台消息 ====================
        .onConsole((event) => {
          const message = event.message.getMessage();
          const level = event.message.getMessageLevel();
          logger.debug(TAG, `控制台[${level}]: ${message}`);
          
          if (this.callbacks?.onConsoleMessage) {
            this.callbacks.onConsoleMessage(message, String(level));
          }
          
          return false; // 返回false表示继续传递到系统控制台
        })
        
        // ==================== SSL错误处理 ====================
        .onSslErrorEventReceive((event) => {
          logger.warn(TAG, `SSL错误: ${event.error}`);
          // 生产环境应该拒绝不安全的连接
          event.handler.handleCancel();
        })
        
        // ==================== 资源加载 ====================
        .onLoadIntercept((event) => {
          // 可以在这里拦截和修改请求
          logger.debug(TAG, `拦截请求: ${event.data.getRequestUrl()}`);
          return false; // 返回false表示不拦截
        })
    }
    .width(1)
    .height(1)
    .position({ x: -1000, y: -1000 }) // 移到屏幕外
    .visibility(Visibility.Hidden) // 隐藏但保持功能
  }
}

/**
 * WebView容器管理器
 * 用于管理多个不可见WebView实例
 */
export class InvisibleWebViewManager {
  private static instance: InvisibleWebViewManager | null = null;
  private webViewMap: Map<string, WebViewInstanceData> = new Map();

  private constructor() {
    logger.info(TAG, '不可见WebView管理器初始化');
  }

  /**
   * 获取单例实例
   */
  static getInstance(): InvisibleWebViewManager {
    if (!InvisibleWebViewManager.instance) {
      InvisibleWebViewManager.instance = new InvisibleWebViewManager();
    }
    return InvisibleWebViewManager.instance;
  }

  /**
   * 注册WebView实例
   */
  registerWebView(
    sourceId: string, 
    controller: webview.WebviewController,
    config: WebViewSourceConfig,
    callbacks?: WebViewEventCallbacks
  ): void {
    const data: WebViewInstanceData = {
      controller,
      config,
      callbacks,
      createTime: Date.now(),
      lastUsedTime: Date.now()
    };
    
    this.webViewMap.set(sourceId, data);
    logger.info(TAG, `注册WebView实例: ${sourceId}`);
  }

  /**
   * 获取WebView实例数据
   */
  getWebViewData(sourceId: string): WebViewInstanceData | undefined {
    const data = this.webViewMap.get(sourceId);
    if (data) {
      data.lastUsedTime = Date.now();
    }
    return data;
  }

  /**
   * 注销WebView实例
   */
  unregisterWebView(sourceId: string): void {
    this.webViewMap.delete(sourceId);
    logger.info(TAG, `注销WebView实例: ${sourceId}`);
  }

  /**
   * 获取所有注册的源ID
   */
  getAllSourceIds(): string[] {
    return Array.from(this.webViewMap.keys());
  }

  /**
   * 清理所有实例
   */
  clearAll(): void {
    this.webViewMap.clear();
    logger.info(TAG, '清理所有WebView实例');
  }
}
