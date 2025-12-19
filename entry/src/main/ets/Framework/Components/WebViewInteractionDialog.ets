/**
 * WebView交互对话框组件
 * 用于显示WebView让用户完成验证码、登录等需要人工操作的场景
 * 设计原则：声明式配置、事件驱动、易于集成
 */

import { webview } from '@kit.ArkWeb';
import { ThemeAwareState, ThemeAwareHelper } from './ThemeAware';
import { logger } from '../../Utils/Logger';

const TAG = 'WebViewInteractionDialog';

// ==================== 数据模型 ====================

/**
 * 交互类型
 */
export enum InteractionType {
  /** 验证码 */
  CAPTCHA = 'captcha',
  /** 登录 */
  LOGIN = 'login',
  /** Cloudflare验证 */
  CLOUDFLARE = 'cloudflare',
  /** 自定义交互 */
  CUSTOM = 'custom'
}

/**
 * 交互状态
 */
export enum InteractionStatus {
  /** 等待用户操作 */
  WAITING = 'waiting',
  /** 验证中 */
  VERIFYING = 'verifying',
  /** 成功 */
  SUCCESS = 'success',
  /** 失败 */
  FAILED = 'failed',
  /** 超时 */
  TIMEOUT = 'timeout'
}

/**
 * 交互请求
 */
export interface InteractionRequest {
  /** 交互类型 */
  type: InteractionType;
  /** 目标URL */
  url: string;
  /** 标题 */
  title?: string;
  /** 提示信息 */
  hint?: string;
  /** 超时时间（毫秒） */
  timeout?: number;
  /** 成功检测条件（URL匹配或元素选择器） */
  successCondition?: SuccessCondition;
  /** 是否自动关闭（成功后） */
  autoClose?: boolean;
}

/**
 * 成功检测条件
 */
export interface SuccessCondition {
  /** 条件类型 */
  type: 'url' | 'element' | 'cookie' | 'script';
  /** URL匹配模式 */
  urlPattern?: string;
  /** 元素选择器 */
  selector?: string;
  /** Cookie名称 */
  cookieName?: string;
  /** 脚本代码（返回true表示成功） */
  script?: string;
}

/**
 * 交互结果
 */
export interface InteractionResult {
  /** 状态 */
  status: InteractionStatus;
  /** 最终URL */
  finalUrl?: string;
  /** 提取的数据 */
  data?: Record<string, string>;
  /** 错误信息 */
  error?: string;
}

/**
 * WebView交互对话框配置
 */
export interface WebViewInteractionDialogConfig {
  /** 对话框宽度 */
  width?: Length;
  /** 对话框高度 */
  height?: Length;
  /** 是否显示工具栏 */
  showToolbar?: boolean;
  /** 是否显示URL栏 */
  showUrlBar?: boolean;
  /** 是否显示刷新按钮 */
  showRefreshButton?: boolean;
  /** 是否显示倒计时 */
  showCountdown?: boolean;
  /** 默认超时时间（毫秒） */
  defaultTimeout?: number;
}

// ==================== WebView交互对话框组件 ====================

/**
 * WebView交互对话框组件
 * 用于显示WebView让用户完成验证码、登录等操作
 * 
 * 使用示例：
 * ```
 * WebViewInteractionDialog({
 *   isVisible: this.showInteractionDialog,
 *   request: {
 *     type: InteractionType.CAPTCHA,
 *     url: 'https://example.com/captcha',
 *     title: '请完成验证',
 *     hint: '请在下方完成人机验证',
 *     timeout: 60000,
 *     successCondition: { type: 'url', urlPattern: '/success' }
 *   },
 *   onComplete: (result) => { this.handleInteractionComplete(result); },
 *   onCancel: () => { this.showInteractionDialog = false; }
 * })
 * ```
 */
@Component
export struct WebViewInteractionDialog {
  /** 是否显示 */
  @Prop isVisible: boolean = false;
  /** 交互请求 */
  @Prop request: InteractionRequest | null = null;
  /** 完成回调 */
  onComplete: (result: InteractionResult) => void = () => {};
  /** 取消回调 */
  onCancel: () => void = () => {};
  /** 配置 */
  config: WebViewInteractionDialogConfig = {};
  /** 主题状态 */
  @Consume('themeState') themeState: ThemeAwareState;

  /** WebView控制器 */
  private webViewController: webview.WebviewController = new webview.WebviewController();
  /** 当前URL */
  @State currentUrl: string = '';
  /** 加载进度 */
  @State loadProgress: number = 0;
  /** 是否加载中 */
  @State isLoading: boolean = false;
  /** 剩余时间（秒） */
  @State remainingSeconds: number = 0;
  /** 状态 */
  @State status: InteractionStatus = InteractionStatus.WAITING;
  /** 定时器ID */
  private timeoutTimer: number = -1;
  private countdownTimer: number = -1;
  /** 成功检测定时器 */
  private checkTimer: number = -1;

  aboutToAppear(): void {
    if (this.request) {
      this.startInteraction();
    }
  }

  aboutToDisappear(): void {
    this.clearTimers();
  }

  private getConfig(): WebViewInteractionDialogConfig {
    return {
      width: this.config.width || '90%',
      height: this.config.height || '70%',
      showToolbar: this.config.showToolbar !== false,
      showUrlBar: this.config.showUrlBar || false,
      showRefreshButton: this.config.showRefreshButton !== false,
      showCountdown: this.config.showCountdown !== false,
      defaultTimeout: this.config.defaultTimeout || 120000
    };
  }

  private startInteraction(): void {
    if (!this.request) return;

    this.status = InteractionStatus.WAITING;
    this.currentUrl = this.request.url;

    // 设置超时
    const timeout = this.request.timeout || this.getConfig().defaultTimeout || 120000;
    this.remainingSeconds = Math.ceil(timeout / 1000);

    // 启动倒计时
    this.countdownTimer = setInterval(() => {
      this.remainingSeconds--;
      if (this.remainingSeconds <= 0) {
        this.handleTimeout();
      }
    }, 1000);

    // 启动成功检测
    if (this.request.successCondition) {
      this.checkTimer = setInterval(() => {
        this.checkSuccessCondition();
      }, 1000);
    }

    logger.info(TAG, `开始交互: ${this.request.type}, URL: ${this.request.url}`);
  }

  private clearTimers(): void {
    if (this.timeoutTimer !== -1) {
      clearTimeout(this.timeoutTimer);
      this.timeoutTimer = -1;
    }
    if (this.countdownTimer !== -1) {
      clearInterval(this.countdownTimer);
      this.countdownTimer = -1;
    }
    if (this.checkTimer !== -1) {
      clearInterval(this.checkTimer);
      this.checkTimer = -1;
    }
  }

  private handleTimeout(): void {
    this.clearTimers();
    this.status = InteractionStatus.TIMEOUT;
    this.onComplete({
      status: InteractionStatus.TIMEOUT,
      error: '操作超时'
    });
  }

  private async checkSuccessCondition(): Promise<void> {
    if (!this.request?.successCondition || this.status !== InteractionStatus.WAITING) {
      return;
    }

    const condition = this.request.successCondition;
    let success = false;

    try {
      switch (condition.type) {
        case 'url':
          if (condition.urlPattern && this.currentUrl.includes(condition.urlPattern)) {
            success = true;
          }
          break;

        case 'element':
          if (condition.selector) {
            const script = `!!document.querySelector('${condition.selector}')`;
            const result = await this.webViewController.runJavaScript(script);
            success = result === 'true';
          }
          break;

        case 'cookie':
          if (condition.cookieName) {
            const script = `document.cookie.includes('${condition.cookieName}')`;
            const result = await this.webViewController.runJavaScript(script);
            success = result === 'true';
          }
          break;

        case 'script':
          if (condition.script) {
            const result = await this.webViewController.runJavaScript(condition.script);
            success = result === 'true';
          }
          break;
      }

      if (success) {
        this.handleSuccess();
      }
    } catch (error) {
      logger.warn(TAG, `检测成功条件失败: ${String(error)}`);
    }
  }

  private handleSuccess(): void {
    this.clearTimers();
    this.status = InteractionStatus.SUCCESS;
    
    const result: InteractionResult = {
      status: InteractionStatus.SUCCESS,
      finalUrl: this.currentUrl
    };

    logger.info(TAG, `交互成功: ${this.currentUrl}`);
    this.onComplete(result);

    if (this.request?.autoClose !== false) {
      // 自动关闭
    }
  }

  private handleCancel(): void {
    this.clearTimers();
    this.status = InteractionStatus.FAILED;
    this.onCancel();
  }

  private handleManualComplete(): void {
    this.handleSuccess();
  }

  private getTitle(): string {
    if (this.request?.title) {
      return this.request.title;
    }
    switch (this.request?.type) {
      case InteractionType.CAPTCHA:
        return '请完成验证';
      case InteractionType.LOGIN:
        return '请登录';
      case InteractionType.CLOUDFLARE:
        return '安全验证';
      default:
        return '请完成操作';
    }
  }

  private getHint(): string {
    if (this.request?.hint) {
      return this.request.hint;
    }
    switch (this.request?.type) {
      case InteractionType.CAPTCHA:
        return '请在下方完成人机验证';
      case InteractionType.LOGIN:
        return '请在下方登录您的账号';
      case InteractionType.CLOUDFLARE:
        return '请等待或完成Cloudflare验证';
      default:
        return '请在下方完成所需操作';
    }
  }

  build() {
    if (this.isVisible && this.request) {
      Column() {
        // 遮罩层
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#00000080')
          .onClick(() => {
            // 点击遮罩不关闭
          })

        // 对话框
        Column({ space: 0 }) {
          // 标题栏
          this.buildToolbar()

          // 提示信息
          if (this.getHint()) {
            Text(this.getHint())
              .fontSize(14)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .width('100%')
              .padding({ left: 16, right: 16, top: 8, bottom: 8 })
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_dark', this.themeState.currentTheme))
          }

          // 加载进度条
          if (this.isLoading) {
            Progress({ value: this.loadProgress, total: 100, type: ProgressType.Linear })
              .width('100%')
              .height(2)
              .color(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          }

          // WebView
          Web({ src: this.request.url, controller: this.webViewController })
            .width('100%')
            .layoutWeight(1)
            .javaScriptAccess(true)
            .domStorageAccess(true)
            .mixedMode(MixedMode.All)
            .onProgressChange((event) => {
              if (event) {
                this.loadProgress = event.newProgress;
                this.isLoading = event.newProgress < 100;
              }
            })
            .onPageEnd(() => {
              this.isLoading = false;
              // 页面加载完成后立即检测
              this.checkSuccessCondition();
            })
            .onPageBegin((event) => {
              if (event) {
                this.currentUrl = event.url;
                logger.debug(TAG, `URL变化: ${event.url}`);
                // URL变化时检测
                this.checkSuccessCondition();
              }
            })

          // 底部操作栏
          this.buildBottomBar()
        }
        .width('90%')
        .height('70%')
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
        .borderRadius(16)
        .clip(true)
        .position({ x: '50%', y: '50%' })
        .translate({ x: '-50%', y: '-50%' })
      }
      .width('100%')
      .height('100%')
      .position({ x: 0, y: 0 })
    }
  }

  @Builder
  buildToolbar() {
    Row({ space: 12 }) {
      // 关闭按钮
      Text('✕')
        .fontSize(18)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .width(32)
        .height(32)
        .textAlign(TextAlign.Center)
        .onClick(() => this.handleCancel())

      // 标题
      Text(this.getTitle())
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .layoutWeight(1)

      // 倒计时
      if (this.getConfig().showCountdown && this.remainingSeconds > 0) {
        Text(`${this.remainingSeconds}s`)
          .fontSize(14)
          .fontColor(this.remainingSeconds <= 10 
            ? '#F44336' 
            : ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      }

      // 刷新按钮
      if (this.getConfig().showRefreshButton) {
        Text('↻')
          .fontSize(18)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width(32)
          .height(32)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.webViewController.refresh();
          })
      }
    }
    .width('100%')
    .height(48)
    .padding({ left: 8, right: 8 })
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
  }

  @Builder
  buildBottomBar() {
    Row({ space: 12 }) {
      // 取消按钮
      Button('取消')
        .fontSize(14)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_dark', this.themeState.currentTheme))
        .height(40)
        .layoutWeight(1)
        .onClick(() => this.handleCancel())

      // 完成按钮
      Button('我已完成')
        .fontSize(14)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
        .height(40)
        .layoutWeight(1)
        .onClick(() => this.handleManualComplete())
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
  }
}

// ==================== 交互管理器 ====================

/**
 * 交互管理器
 * 用于管理WebView交互请求队列
 */
export class InteractionManager {
  private static instance: InteractionManager | null = null;
  private pendingRequests: InteractionRequest[] = [];
  private currentRequest: InteractionRequest | null = null;
  private onRequestCallback: ((request: InteractionRequest | null) => void) | null = null;

  private constructor() {}

  static getInstance(): InteractionManager {
    if (!InteractionManager.instance) {
      InteractionManager.instance = new InteractionManager();
    }
    return InteractionManager.instance;
  }

  /**
   * 设置请求回调
   */
  setOnRequestCallback(callback: (request: InteractionRequest | null) => void): void {
    this.onRequestCallback = callback;
  }

  /**
   * 请求交互
   */
  requestInteraction(request: InteractionRequest): Promise<InteractionResult> {
    return new Promise((resolve) => {
      // 暂存resolve回调
      const wrappedRequest = {
        ...request,
        _resolve: resolve
      };
      
      if (this.currentRequest) {
        this.pendingRequests.push(wrappedRequest as InteractionRequest);
      } else {
        this.currentRequest = wrappedRequest as InteractionRequest;
        this.onRequestCallback?.(this.currentRequest);
      }
    });
  }

  /**
   * 完成当前交互
   */
  completeInteraction(result: InteractionResult): void {
    if (this.currentRequest) {
      const request = this.currentRequest as InteractionRequest & { _resolve?: (result: InteractionResult) => void };
      request._resolve?.(result);
      this.currentRequest = null;
    }

    // 处理下一个请求
    if (this.pendingRequests.length > 0) {
      this.currentRequest = this.pendingRequests.shift() || null;
      this.onRequestCallback?.(this.currentRequest);
    } else {
      this.onRequestCallback?.(null);
    }
  }

  /**
   * 取消所有交互
   */
  cancelAll(): void {
    const failedResult: InteractionResult = {
      status: InteractionStatus.FAILED,
      error: '用户取消'
    };

    if (this.currentRequest) {
      const request = this.currentRequest as InteractionRequest & { _resolve?: (result: InteractionResult) => void };
      request._resolve?.(failedResult);
      this.currentRequest = null;
    }

    for (const request of this.pendingRequests) {
      const req = request as InteractionRequest & { _resolve?: (result: InteractionResult) => void };
      req._resolve?.(failedResult);
    }
    this.pendingRequests = [];
    this.onRequestCallback?.(null);
  }
}
