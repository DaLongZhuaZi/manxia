/**
 * Rhino沙箱WebView组件
 * 
 * 提供一个隐藏的WebView组件，用于运行CheerpJ + Rhino WASM沙箱
 * 该组件应该在应用启动时创建，并保持在后台运行
 * 
 * 文件路径: entry/src/main/ets/Framework/Novel/RhinoSandboxComponent.ets
 */

import { webview } from '@kit.ArkWeb';
import { logger } from '../../Utils/Logger';
import { getRhinoWasmExecutor, RhinoWasmExecutor } from './RhinoWasmExecutor';

const TAG = 'RhinoSandboxComponent';

/**
 * 沙箱事件回调接口
 */
export interface RhinoSandboxCallbacks {
  /** 沙箱就绪 */
  onReady?: () => void;
  /** 沙箱错误 */
  onError?: (error: string) => void;
  /** 控制台消息 */
  onConsoleMessage?: (message: string, level: string) => void;
}

/**
 * Rhino沙箱WebView组件
 * 
 * 特点：
 * 1. 完全隐藏（0尺寸，位于屏幕外）
 * 2. 加载本地HTML运行CheerpJ + Rhino
 * 3. 自动连接到RhinoWasmExecutor
 */
@Component
export struct RhinoSandboxWebView {
  /** 事件回调 */
  @Prop callbacks?: RhinoSandboxCallbacks;
  
  /** WebView控制器 */
  private controller: webview.WebviewController = new webview.WebviewController();
  
  /** 执行器实例 */
  private executor: RhinoWasmExecutor = getRhinoWasmExecutor();
  
  /** 是否已初始化 */
  @State private isInitialized: boolean = false;
  
  /** 加载状态 */
  @State private loadStatus: string = 'Loading...';
  
  /** 错误信息 */
  @State private errorMessage: string = '';

  aboutToAppear() {
    logger.info(TAG, 'Rhino沙箱组件初始化');
    
    // 启用网页调试功能（仅开发环境）
    try {
      webview.WebviewController.setWebDebuggingAccess(true);
      logger.debug(TAG, '网页调试功能已启用');
    } catch (error) {
      logger.warn(TAG, `启用网页调试功能失败: ${String(error)}`);
    }
    
    // 将控制器传递给执行器
    this.executor.setWebviewController(this.controller);
  }

  aboutToDisappear() {
    logger.info(TAG, 'Rhino沙箱组件销毁');
  }

  build() {
    Stack() {
      Web({
        src: 'resource://rawfile/rhino_sandbox/index.html',
        controller: this.controller
      })
        // ==================== 基础配置 ====================
        .width(1)
        .height(1)
        .opacity(0)
        
        // ==================== WebView功能配置 ====================
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .databaseAccess(true)
        .fileAccess(true)
        .imageAccess(false) // 不需要图片
        .mixedMode(MixedMode.All)
        .cacheMode(CacheMode.Default)
        
        // 注意：网页调试功能已在aboutToAppear中通过setWebDebuggingAccess启用
        
        // 设置User-Agent
        .userAgent('Mozilla/5.0 (Linux; Android 11; Pixel 5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/90.0.4430.91 Mobile Safari/537.36 RhinoSandbox/1.0')
        
        // ==================== 页面生命周期事件 ====================
        .onPageBegin((event) => {
          logger.debug(TAG, `页面开始加载: ${event.url}`);
          this.loadStatus = 'Loading page...';
        })
        
        .onPageEnd((event) => {
          logger.info(TAG, `页面加载完成: ${event.url}`);
          this.loadStatus = 'Page loaded, initializing...';
          this.isInitialized = true;
          
          // 开始初始化沙箱
          this.initializeSandbox();
        })
        
        .onProgressChange((event) => {
          this.loadStatus = `Loading: ${event.newProgress}%`;
        })
        
        // ==================== 错误处理 ====================
        .onErrorReceive((event) => {
          const errorInfo = event.error.getErrorInfo();
          logger.error(TAG, `页面加载错误: ${errorInfo}`);
          this.errorMessage = errorInfo;
          
          if (this.callbacks?.onError) {
            this.callbacks.onError(errorInfo);
          }
        })
        
        .onHttpErrorReceive((event) => {
          const code = event.response.getResponseCode();
          logger.error(TAG, `HTTP错误: ${code}`);
          this.errorMessage = `HTTP Error: ${code}`;
        })
        
        // ==================== 控制台消息 ====================
        .onConsole((event) => {
          const message = event.message.getMessage();
          const level = event.message.getMessageLevel();
          
          // 检查是否是沙箱事件消息
          if (message.startsWith('__RHINO_SANDBOX_EVENT__:')) {
            this.handleSandboxEvent(message.substring(24));
          } else {
            logger.debug(TAG, `控制台[${level}]: ${message}`);
            
            if (this.callbacks?.onConsoleMessage) {
              this.callbacks.onConsoleMessage(message, String(level));
            }
          }
          
          return false;
        })
        
        // ==================== SSL错误处理 ====================
        .onSslErrorEventReceive((event) => {
          logger.warn(TAG, `SSL错误: ${event.error}`);
          // 开发环境可以忽略SSL错误
          // 生产环境应该拒绝
          event.handler.handleCancel();
        })
        
        // ==================== 资源加载拦截 ====================
        .onLoadIntercept((event) => {
          const url = event.data.getRequestUrl();
          logger.debug(TAG, `资源请求: ${url}`);
          
          // 允许所有请求
          return false;
        })
    }
    .width(1)
    .height(1)
    .position({ x: -1000, y: -1000 })
    .visibility(Visibility.Hidden)
  }
  
  /**
   * 初始化沙箱
   */
  private async initializeSandbox(): Promise<void> {
    try {
      logger.info(TAG, '开始初始化Rhino沙箱...');
      
      const success = await this.executor.initialize();
      
      if (success) {
        logger.info(TAG, 'Rhino沙箱初始化成功');
        this.loadStatus = 'Ready';
        
        if (this.callbacks?.onReady) {
          this.callbacks.onReady();
        }
      } else {
        const error = this.executor.getInitError() || '未知错误';
        logger.error(TAG, `Rhino沙箱初始化失败: ${error}`);
        this.errorMessage = error;
        
        if (this.callbacks?.onError) {
          this.callbacks.onError(error);
        }
      }
    } catch (e) {
      const error = String(e);
      logger.error(TAG, `Rhino沙箱初始化异常: ${error}`);
      this.errorMessage = error;
      
      if (this.callbacks?.onError) {
        this.callbacks.onError(error);
      }
    }
  }
  
  /**
   * 处理沙箱事件
   */
  private handleSandboxEvent(eventJson: string): void {
    try {
      const event = JSON.parse(eventJson) as {
        event: string;
        data: Record<string, ESObject>;
        timestamp: number;
      };
      
      logger.debug(TAG, `收到沙箱事件: ${event.event}`);
      
      switch (event.event) {
        case 'sandboxReady':
          if (event.data.success) {
            logger.info(TAG, '沙箱报告就绪');
            if (this.callbacks?.onReady) {
              this.callbacks.onReady();
            }
          } else {
            const error = String(event.data.error || '未知错误');
            logger.error(TAG, `沙箱报告错误: ${error}`);
            if (this.callbacks?.onError) {
              this.callbacks.onError(error);
            }
          }
          break;
          
        case 'taskComplete':
          // 任务完成事件由RhinoWasmExecutor处理
          logger.debug(TAG, `任务完成: ${event.data.taskId}`);
          break;
          
        default:
          logger.debug(TAG, `未知沙箱事件: ${event.event}`);
      }
    } catch (e) {
      logger.error(TAG, `解析沙箱事件失败: ${String(e)}`);
    }
  }
}

/**
 * 全局Rhino沙箱管理器
 */
export class RhinoSandboxManager {
  private static instance: RhinoSandboxManager | null = null;
  private isComponentMounted: boolean = false;
  private readyCallbacks: Array<() => void> = [];
  
  private constructor() {}
  
  static getInstance(): RhinoSandboxManager {
    if (!RhinoSandboxManager.instance) {
      RhinoSandboxManager.instance = new RhinoSandboxManager();
    }
    return RhinoSandboxManager.instance;
  }
  
  /**
   * 标记组件已挂载
   */
  setComponentMounted(mounted: boolean): void {
    this.isComponentMounted = mounted;
    logger.info(TAG, `沙箱组件挂载状态: ${mounted}`);
  }
  
  /**
   * 检查组件是否已挂载
   */
  isComponentReady(): boolean {
    return this.isComponentMounted;
  }
  
  /**
   * 标记沙箱就绪
   */
  notifyReady(): void {
    logger.info(TAG, '沙箱就绪，执行回调');
    for (const callback of this.readyCallbacks) {
      try {
        callback();
      } catch (e) {
        logger.error(TAG, `就绪回调执行失败: ${String(e)}`);
      }
    }
    this.readyCallbacks = [];
  }
  
  /**
   * 等待沙箱就绪
   */
  onReady(callback: () => void): void {
    const executor = getRhinoWasmExecutor();
    if (executor.isSandboxReady()) {
      callback();
    } else {
      this.readyCallbacks.push(callback);
    }
  }
}

/**
 * 获取Rhino沙箱管理器实例
 */
export function getRhinoSandboxManager(): RhinoSandboxManager {
  return RhinoSandboxManager.getInstance();
}
