import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { UIContext, window } from '@kit.ArkUI';
import { logger } from './Logger';

const TAG: string = 'OrientationLockManager';

export enum OrientationLockStrategy {
  FOLLOW_SYSTEM = 'FOLLOW_SYSTEM',
  AUTO_ROTATION = 'AUTO_ROTATION',
  AUTO_ROTATION_RESTRICTED = 'AUTO_ROTATION_RESTRICTED',
  AUTO_ROTATION_UNSPECIFIED = 'AUTO_ROTATION_UNSPECIFIED',
  PORTRAIT = 'PORTRAIT',
  LANDSCAPE = 'LANDSCAPE',
  PORTRAIT_INVERTED = 'PORTRAIT_INVERTED',
  LANDSCAPE_INVERTED = 'LANDSCAPE_INVERTED',
  SENSOR_PORTRAIT = 'SENSOR_PORTRAIT',
  SENSOR_LANDSCAPE = 'SENSOR_LANDSCAPE',
  SENSOR_PORTRAIT_RESTRICTED = 'SENSOR_PORTRAIT_RESTRICTED',
  SENSOR_LANDSCAPE_RESTRICTED = 'SENSOR_LANDSCAPE_RESTRICTED',
  USER_ROTATION_PORTRAIT = 'USER_ROTATION_PORTRAIT',
  USER_ROTATION_LANDSCAPE = 'USER_ROTATION_LANDSCAPE',
  LOCK_CURRENT = 'LOCK_CURRENT',
  FOLLOW_DESKTOP = 'FOLLOW_DESKTOP'
}

export enum OrientationLockPriority {
  APP_DEFAULT = 0,
  PAGE = 50,
  MODAL = 80,
  CRITICAL = 100
}

export interface OrientationLockRequest {
  token: string;
  owner: string;
  strategy: OrientationLockStrategy;
  priority: OrientationLockPriority;
  createdAt: number;
  /**
   * 请求所属的窗口 ID。同一进程可能存在多个阅读器窗口（multiton Ability），
   * 方向策略必须按窗口隔离，避免互相串台。无法解析时为 -1。
   */
  windowId: number;
}

export interface OrientationLockApplyResult {
  success: boolean;
  strategy: OrientationLockStrategy;
  appliedOrientation: window.Orientation;
  message: string;
}

export class OrientationLockManager {
  private static readonly DEFAULT_STRATEGY: OrientationLockStrategy =
    OrientationLockStrategy.AUTO_ROTATION_RESTRICTED;
  private static requests: OrientationLockRequest[] = [];
  private static tokenSequence: number = 0;
  private static fallbackStrategy: OrientationLockStrategy = OrientationLockManager.DEFAULT_STRATEGY;
  private static lastAppliedStrategy: OrientationLockStrategy = OrientationLockManager.DEFAULT_STRATEGY;

  static setFallbackStrategy(strategy: OrientationLockStrategy, uiContext?: UIContext): void {
    OrientationLockManager.fallbackStrategy = strategy;
    if (OrientationLockManager.requests.length === 0) {
      void OrientationLockManager.applyStrategy(strategy, uiContext, 'fallback_changed');
    }
  }

  static acquirePageLock(
    owner: string,
    strategy: OrientationLockStrategy,
    uiContext?: UIContext,
    priority: OrientationLockPriority = OrientationLockPriority.PAGE
  ): string {
    const token = OrientationLockManager.createToken(owner);
    const windowId = OrientationLockManager.resolveWindowId(uiContext);
    const request: OrientationLockRequest = {
      token,
      owner,
      strategy,
      priority,
      createdAt: Date.now(),
      windowId
    };
    OrientationLockManager.requests.push(request);
    logger.info(TAG, `方向策略入栈: owner=${owner}, strategy=${strategy}, priority=${priority}, token=${token}`);
    OrientationLockManager.applyActiveRequest(uiContext, `acquire:${owner}`);
    return token;
  }

  static updatePageLock(
    token: string,
    strategy: OrientationLockStrategy,
    uiContext?: UIContext,
    priority?: OrientationLockPriority
  ): boolean {
    for (let i = 0; i < OrientationLockManager.requests.length; i++) {
      const request = OrientationLockManager.requests[i];
      if (request.token === token) {
        request.strategy = strategy;
        if (priority !== undefined) {
          request.priority = priority;
        }
        const resolvedWindowId = OrientationLockManager.resolveWindowId(uiContext);
        if (resolvedWindowId >= 0) {
          request.windowId = resolvedWindowId;
        }
        request.createdAt = Date.now();
        logger.info(TAG, `方向策略更新: token=${token}, strategy=${strategy}, priority=${request.priority}`);
        OrientationLockManager.applyActiveRequest(uiContext, `update:${request.owner}`);
        return true;
      }
    }
    logger.warn(TAG, `方向策略更新失败，未找到token: ${token}`);
    return false;
  }

  static releaseLock(token: string, uiContext?: UIContext): boolean {
    const nextRequests: OrientationLockRequest[] = [];
    let releasedRequest: OrientationLockRequest | null = null;

    for (let i = 0; i < OrientationLockManager.requests.length; i++) {
      const request = OrientationLockManager.requests[i];
      if (request.token === token) {
        releasedRequest = request;
      } else {
        nextRequests.push(request);
      }
    }

    if (releasedRequest === null) {
      logger.warn(TAG, `释放方向策略失败，未找到token: ${token}`);
      return false;
    }

    OrientationLockManager.requests = nextRequests;
    logger.info(TAG, `方向策略出栈: owner=${releasedRequest.owner}, token=${token}`);
    OrientationLockManager.applyActiveRequest(uiContext, `release:${releasedRequest.owner}`);
    return true;
  }

  static releaseOwner(owner: string, uiContext?: UIContext): number {
    const nextRequests: OrientationLockRequest[] = [];
    let releaseCount: number = 0;
    const windowId = OrientationLockManager.resolveWindowId(uiContext);

    for (let i = 0; i < OrientationLockManager.requests.length; i++) {
      const request = OrientationLockManager.requests[i];
      const windowMatched = windowId < 0 || request.windowId < 0 || request.windowId === windowId;
      if (request.owner === owner && windowMatched) {
        releaseCount++;
      } else {
        nextRequests.push(request);
      }
    }

    if (releaseCount === 0) {
      logger.debug(TAG, `没有需要释放的方向策略: owner=${owner}`);
      return 0;
    }

    OrientationLockManager.requests = nextRequests;
    logger.info(TAG, `按页面释放方向策略: owner=${owner}, count=${releaseCount}`);
    OrientationLockManager.applyActiveRequest(uiContext, `release_owner:${owner}`);
    return releaseCount;
  }

  static clearAll(uiContext?: UIContext): void {
    OrientationLockManager.requests = [];
    logger.info(TAG, '已清空全部方向策略请求');
    OrientationLockManager.applyActiveRequest(uiContext, 'clear_all');
  }

  /**
   * 释放指定窗口的全部方向策略请求（窗口/Ability 销毁时调用）。
   * 仅清理传入 UIContext 对应窗口，不影响同进程其它阅读器实例。
   */
  static releaseWindow(uiContext?: UIContext): number {
    return OrientationLockManager.releaseWindowById(OrientationLockManager.resolveWindowId(uiContext));
  }

  /**
   * 按窗口 ID 释放方向策略请求。
   */
  static releaseWindowById(windowId: number): number {
    if (windowId < 0) {
      return 0;
    }
    const nextRequests: OrientationLockRequest[] = [];
    let releaseCount: number = 0;
    for (let i = 0; i < OrientationLockManager.requests.length; i++) {
      const request = OrientationLockManager.requests[i];
      if (request.windowId === windowId) {
        releaseCount++;
      } else {
        nextRequests.push(request);
      }
    }
    if (releaseCount === 0) {
      return 0;
    }
    OrientationLockManager.requests = nextRequests;
    logger.info(TAG, `按窗口释放方向策略: windowId=${windowId}, count=${releaseCount}`);
    return releaseCount;
  }

  /**
   * 读取当前窗口生效的方向策略请求；传入 UIContext 时只返回该窗口的请求。
   */
  static getActiveRequest(uiContext?: UIContext): OrientationLockRequest | null {
    const windowId = OrientationLockManager.resolveWindowId(uiContext);
    const activeRequest = OrientationLockManager.resolveActiveRequest(windowId);
    if (activeRequest === null) {
      return null;
    }
    return OrientationLockManager.cloneRequest(activeRequest);
  }

  static getLastAppliedStrategy(): OrientationLockStrategy {
    return OrientationLockManager.lastAppliedStrategy;
  }

  static resolveOrientation(strategy: OrientationLockStrategy): window.Orientation {
    switch (strategy) {
      case OrientationLockStrategy.FOLLOW_SYSTEM:
      case OrientationLockStrategy.AUTO_ROTATION_UNSPECIFIED:
        return window.Orientation.AUTO_ROTATION_UNSPECIFIED;
      case OrientationLockStrategy.AUTO_ROTATION:
        return window.Orientation.AUTO_ROTATION;
      case OrientationLockStrategy.AUTO_ROTATION_RESTRICTED:
        return window.Orientation.AUTO_ROTATION_RESTRICTED;
      case OrientationLockStrategy.PORTRAIT:
        return window.Orientation.PORTRAIT;
      case OrientationLockStrategy.LANDSCAPE:
        return window.Orientation.LANDSCAPE;
      case OrientationLockStrategy.PORTRAIT_INVERTED:
        return window.Orientation.PORTRAIT_INVERTED;
      case OrientationLockStrategy.LANDSCAPE_INVERTED:
        return window.Orientation.LANDSCAPE_INVERTED;
      case OrientationLockStrategy.SENSOR_PORTRAIT:
        return window.Orientation.AUTO_ROTATION_PORTRAIT;
      case OrientationLockStrategy.SENSOR_LANDSCAPE:
        return window.Orientation.AUTO_ROTATION_LANDSCAPE;
      case OrientationLockStrategy.SENSOR_PORTRAIT_RESTRICTED:
        return window.Orientation.AUTO_ROTATION_PORTRAIT_RESTRICTED;
      case OrientationLockStrategy.SENSOR_LANDSCAPE_RESTRICTED:
        return window.Orientation.AUTO_ROTATION_LANDSCAPE_RESTRICTED;
      case OrientationLockStrategy.USER_ROTATION_PORTRAIT:
        return window.Orientation.USER_ROTATION_PORTRAIT;
      case OrientationLockStrategy.USER_ROTATION_LANDSCAPE:
        return window.Orientation.USER_ROTATION_LANDSCAPE;
      case OrientationLockStrategy.LOCK_CURRENT:
        return window.Orientation.LOCKED;
      case OrientationLockStrategy.FOLLOW_DESKTOP:
        return window.Orientation.FOLLOW_DESKTOP;
      default:
        return window.Orientation.AUTO_ROTATION_RESTRICTED;
    }
  }

  static async applyStrategy(
    strategy: OrientationLockStrategy,
    uiContext?: UIContext,
    reason: string = 'manual'
  ): Promise<OrientationLockApplyResult> {
    const targetWindow = OrientationLockManager.getMainWindowFromUIContext(uiContext);
    return OrientationLockManager.applyStrategyToWindow(targetWindow, strategy, reason);
  }

  static async applyStrategyToWindow(
    targetWindow: window.Window | null,
    strategy: OrientationLockStrategy,
    reason: string = 'manual_window'
  ): Promise<OrientationLockApplyResult> {
    const orientation = OrientationLockManager.resolveOrientation(strategy);
    if (targetWindow === null) {
      return {
        success: false,
        strategy,
        appliedOrientation: orientation,
        message: '主窗口为空，方向策略未应用'
      };
    }

    try {
      await targetWindow.setPreferredOrientation(orientation);
      OrientationLockManager.lastAppliedStrategy = strategy;
      logger.info(TAG, `方向策略已应用: strategy=${strategy}, orientation=${orientation}, reason=${reason}`);
      return {
        success: true,
        strategy,
        appliedOrientation: orientation,
        message: '方向策略已应用'
      };
    } catch (error) {
      const businessError = error as BusinessError;
      const message = businessError.message ?? String(error);
      logger.error(TAG, `方向策略应用失败: strategy=${strategy}, orientation=${orientation}, reason=${reason}, error=${message}`);
      return {
        success: false,
        strategy,
        appliedOrientation: orientation,
        message
      };
    }
  }

  private static applyActiveRequest(uiContext?: UIContext, reason: string = 'stack_changed'): void {
    const windowId = OrientationLockManager.resolveWindowId(uiContext);
    const activeRequest = OrientationLockManager.resolveActiveRequest(windowId);
    const strategy = activeRequest ? activeRequest.strategy : OrientationLockManager.fallbackStrategy;
    void OrientationLockManager.applyStrategy(strategy, uiContext, reason);
  }

  /**
   * 解析指定窗口的当前活跃方向策略。
   * windowId < 0 时退化为全局解析（兼容无法解析窗口的旧调用）。
   */
  private static resolveActiveRequest(windowId: number): OrientationLockRequest | null {
    let activeRequest: OrientationLockRequest | null = null;
    for (let i = 0; i < OrientationLockManager.requests.length; i++) {
      const request = OrientationLockManager.requests[i];
      if (windowId >= 0 && request.windowId >= 0 && request.windowId !== windowId) {
        continue;
      }
      if (activeRequest === null ||
        request.priority > activeRequest.priority ||
        (request.priority === activeRequest.priority && request.createdAt >= activeRequest.createdAt)) {
        activeRequest = request;
      }
    }
    return activeRequest;
  }

  private static createToken(owner: string): string {
    OrientationLockManager.tokenSequence++;
    return `${owner}_${Date.now()}_${OrientationLockManager.tokenSequence}`;
  }

  private static cloneRequest(request: OrientationLockRequest): OrientationLockRequest {
    return {
      token: request.token,
      owner: request.owner,
      strategy: request.strategy,
      priority: request.priority,
      createdAt: request.createdAt,
      windowId: request.windowId
    };
  }

  /**
   * 解析 UIContext 所属主窗口的窗口 ID；无法解析返回 -1。
   */
  private static resolveWindowId(uiContext?: UIContext): number {
    if (!uiContext) {
      return -1;
    }
    const targetWindow = OrientationLockManager.getMainWindowFromUIContext(uiContext);
    if (targetWindow === null) {
      return -1;
    }
    try {
      const windowProperties: window.WindowProperties = targetWindow.getWindowProperties();
      return windowProperties.id;
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      logger.debug(TAG, `解析窗口ID失败: ${message}`);
      return -1;
    }
  }

  private static getMainWindowFromUIContext(uiContext?: UIContext): window.Window | null {
    if (!uiContext) {
      logger.warn(TAG, 'UIContext为空，无法获取主窗口');
      return null;
    }

    try {
      const hostContext = uiContext.getHostContext() as common.UIAbilityContext;
      if (!hostContext || !hostContext.windowStage) {
        logger.warn(TAG, 'HostContext或WindowStage为空，无法获取主窗口');
        return null;
      }
      return hostContext.windowStage.getMainWindowSync();
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `通过UIContext获取主窗口失败: ${message}`);
      return null;
    }
  }
}
