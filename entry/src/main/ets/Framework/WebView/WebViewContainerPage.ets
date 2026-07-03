/**
 * WebView容器页面
 * 用于承载多个不可见的WebView组件
 * 这个页面应该在应用启动时创建，并保持在后台运行
 */

import { webview } from '@kit.ArkWeb';
import { logger } from '../../Utils/Logger';
import { InvisibleWebView, InvisibleWebViewManager, WebViewEventCallbacks, WebViewInstanceData } from './InvisibleWebViewComponent';
import { WebViewSourceConfig } from './WebViewImageLoader';

// 重新导出以便其他模块使用
export { WebViewEventCallbacks, WebViewInstanceData } from './InvisibleWebViewComponent';

const TAG = 'WebViewContainerPage';

/**
 * WebView容器项接口
 */
interface WebViewContainerItem {
  sourceId: string;
  controller: webview.WebviewController;
  config: WebViewSourceConfig;
  callbacks?: WebViewEventCallbacks;
  initialUrl: string;
}

/**
 * WebView容器页面组件
 * 特点：
 * 1. 完全不可见（0尺寸）
 * 2. 可以动态添加/移除WebView实例
 * 3. 统一管理所有后台WebView
 */
@Component
export struct WebViewContainer {
  /** WebView实例列表 */
  @State private webViewItems: WebViewContainerItem[] = [];
  /** 管理器实例 */
  private manager: InvisibleWebViewManager = InvisibleWebViewManager.getInstance();

  /**
   * 组件即将出现
   */
  aboutToAppear() {
    logger.info(TAG, 'WebView容器初始化');
  }

  /**
   * 组件即将消失
   */
  aboutToDisappear() {
    logger.info(TAG, 'WebView容器销毁');
    this.clearAllWebViews();
  }

  /**
   * 添加WebView实例
   */
  addWebView(
    sourceId: string,
    controller: webview.WebviewController,
    config: WebViewSourceConfig,
    callbacks?: WebViewEventCallbacks,
    initialUrl: string = 'about:blank'
  ): void {
    // 检查是否已存在
    const existingIndex = this.webViewItems.findIndex(item => item.sourceId === sourceId);
    if (existingIndex >= 0) {
      logger.warn(TAG, `WebView已存在: ${sourceId}, 将替换`);
      this.webViewItems.splice(existingIndex, 1);
    }

    // 添加新实例
    const item: WebViewContainerItem = {
      sourceId,
      controller,
      config,
      callbacks,
      initialUrl
    };
    
    this.webViewItems.push(item);
    this.manager.registerWebView(sourceId, controller, config, callbacks);
    
    logger.info(TAG, `添加WebView实例: ${sourceId}, 当前总数: ${this.webViewItems.length}`);
  }

  /**
   * 移除WebView实例
   */
  removeWebView(sourceId: string): void {
    const index = this.webViewItems.findIndex(item => item.sourceId === sourceId);
    if (index >= 0) {
      this.webViewItems.splice(index, 1);
      this.manager.unregisterWebView(sourceId);
      logger.info(TAG, `移除WebView实例: ${sourceId}, 剩余: ${this.webViewItems.length}`);
    }
  }

  /**
   * 清理所有WebView
   */
  clearAllWebViews(): void {
    this.webViewItems = [];
    this.manager.clearAll();
    logger.info(TAG, '清理所有WebView实例');
  }

  /**
   * 获取WebView数量
   */
  getWebViewCount(): number {
    return this.webViewItems.length;
  }

  build() {
    Stack() {
      // 渲染所有不可见的WebView
      ForEach(this.webViewItems, (item: WebViewContainerItem) => {
        InvisibleWebView({
          controller: item.controller,
          config: item.config,
          callbacks: item.callbacks ? item.callbacks : null,
          initialUrl: item.initialUrl
        })
      }, (item: WebViewContainerItem) => item.sourceId)
    }
    .width(0)
    .height(0)
    .visibility(Visibility.None)
  }
}

/**
 * 全局WebView容器管理器
 * 提供便捷的API来操作容器
 */
export class GlobalWebViewContainer {
  private static containerRef: WebViewContainer | null = null;  

  /**
   * 设置容器引用
   */
  static setContainer(container: WebViewContainer): void {
    GlobalWebViewContainer.containerRef = container;
    logger.info(TAG, '设置全局WebView容器引用');
  }

  /**
   * 添加WebView
   */
  static addWebView(
    sourceId: string,
    controller: webview.WebviewController,
    config: WebViewSourceConfig,
    callbacks?: WebViewEventCallbacks,
    initialUrl?: string
  ): void {
    if (GlobalWebViewContainer.containerRef) {
      GlobalWebViewContainer.containerRef.addWebView(sourceId, controller, config, callbacks, initialUrl);
    } else {
      logger.error(TAG, '容器引用未设置，无法添加WebView');
    }
  }

  /**
   * 移除WebView
   */
  static removeWebView(sourceId: string): void {
    if (GlobalWebViewContainer.containerRef) {
      GlobalWebViewContainer.containerRef.removeWebView(sourceId);
    } else {
      logger.error(TAG, '容器引用未设置，无法移除WebView');
    }
  }

  /**
   * 清理所有WebView
   */ 
  static clearAll(): void {
    if (GlobalWebViewContainer.containerRef) {
      GlobalWebViewContainer.containerRef.clearAllWebViews();
    }
  }

  /**
   * 获取WebView数量
   */
  static getCount(): number {
    return GlobalWebViewContainer.containerRef ? GlobalWebViewContainer.containerRef.getWebViewCount() : 0;
  }
}
