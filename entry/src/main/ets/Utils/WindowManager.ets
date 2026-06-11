// 文件路径: src/main/ets/Utils/WindowManager.ets
// 职责: 提供统一的窗口管理功能，包括各种显示模式、沉浸式显示、系统栏设置等

import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { display } from '@kit.ArkUI';
import { logger } from './Logger';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { OrientationLockApplyResult, OrientationLockManager, OrientationLockStrategy } from './OrientationLockManager';

/**
 * 系统栏高度信息接口
 */
interface SystemBarHeights {
  statusBarHeight: number;
  navigationBarHeight: number;
}

/**
 * 显示模式枚举
 */
export enum DisplayMode {
  /** 默认模式 - 显示所有系统栏 */
  DEFAULT = 'default',
  /** 完全沉浸式 - 隐藏所有系统栏 */
  FULL_IMMERSIVE = 'full_immersive',
  /** 只隐藏状态栏 */
  HIDE_STATUS_BAR = 'hide_status_bar',
  /** 只隐藏导航栏 */
  HIDE_NAVIGATION_BAR = 'hide_navigation_bar',
  /** 沉浸式但保持系统栏可见 */
  IMMERSIVE_WITH_BARS = 'immersive_with_bars',
  /** 专用模式：页面自行避让状态栏，导航栏区域允许内容沉浸 */
  STATUS_SAFE_BOTTOM_IMMERSIVE = 'status_safe_bottom_immersive'
}

/**
 * 系统栏属性配置接口
 */
interface SystemBarConfig {
  statusBarColor?: string;
  navigationBarColor?: string;
  statusBarContentColor?: string;
  navigationBarContentColor?: string;
  isStatusBarLightIcon?: boolean;
  isNavigationBarLightIcon?: boolean;
}

interface ThemeSystemBarStyle {
  isDarkTheme: boolean;
  contentColor: string;
  backgroundColor: string;
}

enum DisplayModeTransitionStrategy {
  IMMEDIATE = 'immediate',
  SWITCH_BEFORE_NAVIGATION = 'switch_before_navigation',
  SWITCH_AFTER_PAGE_SHOW = 'switch_after_page_show'
}

interface DisplayModeTransitionProfile {
  key: string;
  strategy: DisplayModeTransitionStrategy;
  useOverlay: boolean;
  useBlurOverlay: boolean;
  overlayPeakOpacity: number;
  modeApplyDelayMs: number;
  navigationDelayMs: number;
  settleDurationMs: number;
  overlayFadeOutDurationMs: number;
}

export type AppFloatingWindowRouteName = 'TransferFloatingWindowPage';

export interface AppFloatingWindowConfig {
  routeName: AppFloatingWindowRouteName;
  title: string;
  widthVp: number;
  heightVp: number;
  xVp: number;
  yVp: number;
  zLevel: number;
}

interface AppFloatingWindowPixelRect {
  x: number;
  y: number;
  width: number;
  height: number;
}

/**
 * 窗口管理器 - 基于HarmonyOS NEXT API 12最新规范
 * 提供完整的显示模式管理、沉浸式显示、系统栏设置等功能
 */
export class WindowManager {
  private static readonly TAG = 'WindowManager';
  private static currentMode: DisplayMode = DisplayMode.DEFAULT;
  private static readonly BACKGROUND_STORAGE_KEY = 'isInBackground';
  private static readonly LAST_VISIBLE_STATUS_BAR_HEIGHT_KEY = 'window_manager_last_visible_status_bar_height';
  private static readonly LAST_VISIBLE_NAVIGATION_BAR_HEIGHT_KEY = 'window_manager_last_visible_navigation_bar_height';
  private static windowStageRef: window.WindowStage | null = null;
  private static windowStageEventCallback: ((event: window.WindowStageEventType) => void) | null = null;
  private static themeChangeCallback: ((theme: ThemeType) => void) | null = null;
  private static isMainWindowBackgroundPrivacyModeEnabled: boolean = false;
  private static isFloatingWindowBackgroundPrivacyModeEnabled: boolean = false;
  private static readonly TRANSITION_OVERLAY_VISIBLE_KEY = 'window_mode_transition_overlay_visible';
  private static readonly TRANSITION_OVERLAY_OPACITY_KEY = 'window_mode_transition_overlay_opacity';
  private static readonly TRANSITION_OVERLAY_USE_BLUR_KEY = 'window_mode_transition_overlay_use_blur';
  private static readonly TRANSITION_OVERLAY_PREFERS_DARK_KEY = 'window_mode_transition_overlay_prefers_dark';
  private static readonly TRANSITION_OVERLAY_CLEANUP_BUFFER_MS = 48;
  private static transitionModeApplyTimer: number = -1;
  private static transitionNavigationTimer: number = -1;
  private static transitionOverlayCleanupTimer: number = -1;
  private static transitionGeneration: number = 0;
  private static floatingWindowRef: window.Window | null = null;
  private static floatingWindowRouteName: string = '';
  private static isFloatingWindowOpening: boolean = false;
  private static readonly FLOATING_WINDOW_VISIBLE_KEY = 'app_floating_window_visible';
  private static readonly FLOATING_WINDOW_ROUTE_KEY = 'app_floating_window_route';

  private static getWindowLifecycleErrorMessage(error: BusinessError | Error): string {
    const message = (error as Error).message ?? '';
    if (message.length > 0) {
      return message;
    }
    return String(error);
  }

  private static getWindowLifecycleErrorCode(error: BusinessError | Error): number {
    return (error as BusinessError).code;
  }

  private static isWindowLifecycleAbnormalError(error: BusinessError | Error): boolean {
    if (WindowManager.getWindowLifecycleErrorCode(error) === 1300002) {
      return true;
    }
    const message = WindowManager.getWindowLifecycleErrorMessage(error);
    return message.includes('window state is abnormal') ||
      message.includes('not created or destroyed') ||
      message.includes('Get top window failed');
  }

  /**
   * 获取当前 Ability 的主窗口。
   * 优先复用 initialize()/registerWindowStageStateMonitor() 保存的 WindowStage，
   * 避免启动期没有 UIContext 时误判为无法获取主窗口。
   */
  private static getMainWindow(): window.Window | null {
    return WindowManager.getMainWindowFromWindowStageRef('WindowManager.getMainWindow');
  }

  /**
   * 通过UIContext获取主窗口（推荐方式）
   * 在@Component组件中使用：WindowManager.getMainWindowFromUIContext(this.getUIContext())
   */
  static getMainWindowFromUIContext(uiContext: UIContext | undefined): window.Window | null {
    try {
      if (!uiContext) {
        logger.error(WindowManager.TAG, '❌ UIContext为空');
        return null;
      }

      const hostContext = uiContext.getHostContext() as common.UIAbilityContext;
      if (!hostContext || !hostContext.windowStage) {
        logger.error(WindowManager.TAG, '❌ 无法从UIContext获取HostContext或WindowStage');
        return null;
      }

      return hostContext.windowStage.getMainWindowSync();
    } catch (error) {
      logger.error(WindowManager.TAG, `❌ 通过UIContext获取主窗口失败: ${(error as Error).message}`);
      return null;
    }
  }

  /**
   * 设置完全沉浸式模式 - 隐藏所有系统栏
   * @param uiContext 可选的UIContext，推荐在组件中传入
   */
  /**
   * 注册窗口状态变化监听（统一入口）
   *
   * 官方 WindowStageEventType 定义（OpenHarmony @ohos.window）:
   * SHOWN=1, ACTIVE=2, INACTIVE=3, HIDDEN=4, RESUMED=5, PAUSED=6
   *
   * 语义要点:
   * - HIDDEN: 窗口在后台运行
   * - INACTIVE/PAUSED: 前台但不可交互（并非后台）
   */
  static registerWindowStageStateMonitor(windowStage: window.WindowStage): void {
    try {
      if (WindowManager.windowStageRef === windowStage && WindowManager.windowStageEventCallback) {
        return;
      }

      WindowManager.unregisterWindowStageStateMonitor();

      const callback = (event: window.WindowStageEventType): void => {
        WindowManager.handleWindowStageEvent(event);
      };

      windowStage.on('windowStageEvent', callback);
      WindowManager.windowStageRef = windowStage;
      WindowManager.windowStageEventCallback = callback;
      logger.info(WindowManager.TAG, '窗口状态事件监听注册成功');
    } catch (error) {
      logger.error(WindowManager.TAG, `注册窗口状态事件监听失败: ${(error as Error).message}`);
    }
  }

  /**
   * 解除窗口状态变化监听
   */
  static unregisterWindowStageStateMonitor(): void {
    if (!WindowManager.windowStageRef || !WindowManager.windowStageEventCallback) {
      return;
    }

    try {
      WindowManager.applyBackgroundPrivacyMode(false, '解除窗口状态监听');
      WindowManager.windowStageRef.off('windowStageEvent', WindowManager.windowStageEventCallback);
      logger.info(WindowManager.TAG, '窗口状态事件监听已解除');
    } catch (error) {
      logger.warn(WindowManager.TAG, `解除窗口状态事件监听失败: ${(error as Error).message}`);
    } finally {
      WindowManager.windowStageRef = null;
      WindowManager.windowStageEventCallback = null;
    }
  }

  /**
   * 统一同步应用前后台状态（供窗口事件与Ability生命周期共用）
   */
  static syncBackgroundState(isInBackground: boolean, source: string): void {
    const current = AppStorage.get<boolean>(WindowManager.BACKGROUND_STORAGE_KEY);
    if (current === isInBackground) {
      WindowManager.applyBackgroundPrivacyMode(isInBackground, source);
      return;
    }

    AppStorage.setOrCreate(WindowManager.BACKGROUND_STORAGE_KEY, isInBackground);
    WindowManager.applyBackgroundPrivacyMode(isInBackground, source);
    logger.info(WindowManager.TAG, `前后台状态已更新: isInBackground=${isInBackground}, source=${source}`);
  }

  private static shouldEnableBackgroundPrivacyMode(isInBackground: boolean): boolean {
    if (!isInBackground) {
      return false;
    }
    return AppStorage.get<boolean>('backgroundBlurEnabled') === true;
  }

  private static applyBackgroundPrivacyMode(isInBackground: boolean, source: string): void {
    const shouldEnable = WindowManager.shouldEnableBackgroundPrivacyMode(isInBackground);

    const mainWindow = WindowManager.getMainWindowFromWindowStageRef(`background privacy mode: ${source}`);
    if (mainWindow) {
      WindowManager.applyPrivacyModeToWindow(
        mainWindow,
        shouldEnable,
        '主窗口',
        WindowManager.isMainWindowBackgroundPrivacyModeEnabled,
        (applied: boolean): void => {
          WindowManager.isMainWindowBackgroundPrivacyModeEnabled = applied;
        },
        source
      );
    } else if (!shouldEnable) {
      WindowManager.isMainWindowBackgroundPrivacyModeEnabled = false;
    }

    WindowManager.applyFloatingWindowBackgroundPrivacyMode(shouldEnable, source);
  }

  private static applyFloatingWindowBackgroundPrivacyMode(shouldEnable: boolean, source: string): void {
    const targetWindow = WindowManager.floatingWindowRef;
    if (!targetWindow) {
      if (!shouldEnable) {
        WindowManager.isFloatingWindowBackgroundPrivacyModeEnabled = false;
      }
      return;
    }

    WindowManager.applyPrivacyModeToWindow(
      targetWindow,
      shouldEnable,
      '应用内小窗',
      WindowManager.isFloatingWindowBackgroundPrivacyModeEnabled,
      (applied: boolean): void => {
        WindowManager.isFloatingWindowBackgroundPrivacyModeEnabled = applied;
      },
      source
    );
  }

  private static applyPrivacyModeToWindow(
    targetWindow: window.Window,
    shouldEnable: boolean,
    windowLabel: string,
    currentState: boolean,
    updateState: (applied: boolean) => void,
    source: string
  ): void {
    if (currentState === shouldEnable) {
      return;
    }

    updateState(shouldEnable);
    targetWindow.setWindowPrivacyMode(shouldEnable).then((): void => {
      logger.info(WindowManager.TAG, `${windowLabel}后台隐私窗口模式已更新: enabled=${shouldEnable}, source=${source}`);
    }).catch((error: BusinessError): void => {
      if (!shouldEnable && WindowManager.isWindowLifecycleAbnormalError(error)) {
        logger.debug(
          WindowManager.TAG,
          `${windowLabel}后台隐私窗口模式关闭跳过: enabled=${shouldEnable}, source=${source}, ` +
            `code=${WindowManager.getWindowLifecycleErrorCode(error)}, windowLifecycle=destroyed_or_detached, ` +
            `reason=${WindowManager.getWindowLifecycleErrorMessage(error)}`
        );
        updateState(false);
        return;
      }
      logger.warn(
        WindowManager.TAG,
        `${windowLabel}后台隐私窗口模式更新失败: enabled=${shouldEnable}, source=${source}, reason=${JSON.stringify(error)}`
      );
      updateState(!shouldEnable);
    });
  }

  private static handleWindowStageEvent(event: window.WindowStageEventType): void {
    const eventName = WindowManager.getWindowStageEventName(event);
    logger.info(WindowManager.TAG, `窗口状态事件: ${eventName}(${event})`);

    const nextBackgroundState = WindowManager.resolveBackgroundStateByWindowStageEvent(event);
    if (nextBackgroundState === null) {
      logger.debug(WindowManager.TAG, `窗口状态事件已忽略（不触发前后台切换）: ${eventName}(${event})`);
      return;
    }

    WindowManager.syncBackgroundState(nextBackgroundState, `窗口状态事件.${eventName}`);
  }

  private static resolveBackgroundStateByWindowStageEvent(event: window.WindowStageEventType): boolean | null {
    switch (event) {
      case window.WindowStageEventType.HIDDEN:
        return true;
      case window.WindowStageEventType.SHOWN:
      case window.WindowStageEventType.ACTIVE:
      case window.WindowStageEventType.RESUMED:
        return false;
      case window.WindowStageEventType.INACTIVE:
      case window.WindowStageEventType.PAUSED:
        return null;
      default:
        // 未知事件不强制切换前后台状态
        return null;
    }
  }

  private static getWindowStageEventName(event: window.WindowStageEventType): string {
    switch (event) {
      case window.WindowStageEventType.SHOWN:
        return '前台显示';
      case window.WindowStageEventType.ACTIVE:
        return '前台激活';
      case window.WindowStageEventType.INACTIVE:
        return '前台失焦';
      case window.WindowStageEventType.HIDDEN:
        return '后台隐藏';
      case window.WindowStageEventType.RESUMED:
        return '前台可交互';
      case window.WindowStageEventType.PAUSED:
        return '前台不可交互';
      default:
        return '未知事件';
    }
  }

  static setFullImmersive(uiContext?: UIContext): void {
    try {
      const mainWindow = uiContext ? 
        WindowManager.getMainWindowFromUIContext(uiContext) : 
        WindowManager.getMainWindow();
      
      if (!mainWindow) {
        logger.error(WindowManager.TAG, '❌ 无法获取主窗口，设置完全沉浸式失败');
        return;
      }

      // 设置全屏布局
      mainWindow.setWindowLayoutFullScreen(true).then(() => {
        logger.info(WindowManager.TAG, '✅ 全屏布局设置成功');
      }).catch((err: BusinessError) => {
        logger.error(WindowManager.TAG, `❌ 设置全屏布局失败: ${JSON.stringify(err)}`);
      });

      // 隐藏所有系统栏
      mainWindow.setWindowSystemBarEnable([]).then(() => {
        logger.info(WindowManager.TAG, '✅ 完全沉浸式模式设置成功');
        WindowManager.currentMode = DisplayMode.FULL_IMMERSIVE;
        WindowManager.refreshStoredSystemBarHeightsAfterModeChange(mainWindow);
      }).catch((err: BusinessError) => {
        logger.error(WindowManager.TAG, `❌ 隐藏系统栏失败: ${JSON.stringify(err)}`);
      });

    } catch (error) {
      logger.error(WindowManager.TAG, `❌ 设置完全沉浸式异常: ${(error as Error).message}`);
    }
  }

  /**
   * 只隐藏状态栏，保留导航栏
   * @param uiContext 可选的UIContext，推荐在组件中传入
   */
  static hideStatusBar(uiContext?: UIContext): void {
    try {
      const mainWindow = uiContext ? 
        WindowManager.getMainWindowFromUIContext(uiContext) : 
        WindowManager.getMainWindow();
      
      if (!mainWindow) {
        logger.error(WindowManager.TAG, '❌ 无法获取主窗口，隐藏状态栏失败');
        return;
      }

      // 取消全屏布局
      mainWindow.setWindowLayoutFullScreen(false).then(() => {
        logger.info(WindowManager.TAG, '✅ 取消全屏布局成功');
      }).catch((err: BusinessError) => {
        logger.error(WindowManager.TAG, `❌ 取消全屏布局失败: ${JSON.stringify(err)}`);
      });

      // 只显示导航栏
      mainWindow.setWindowSystemBarEnable(['navigation']).then(() => {
        logger.info(WindowManager.TAG, '✅ 状态栏已隐藏，导航栏保持显示');
        WindowManager.currentMode = DisplayMode.HIDE_STATUS_BAR;
        WindowManager.refreshStoredSystemBarHeightsAfterModeChange(mainWindow);
      }).catch((err: BusinessError) => {
        logger.error(WindowManager.TAG, `❌ 设置系统栏显示失败: ${JSON.stringify(err)}`);
      });

    } catch (error) {
      logger.error(WindowManager.TAG, `❌ 隐藏状态栏异常: ${(error as Error).message}`);
    }
  }

  /**
   * 只隐藏导航栏，保留状态栏
   * @param uiContext 可选的UIContext，推荐在组件中传入
   */
  static hideNavigationBar(uiContext?: UIContext): void {
    try {
      const mainWindow = uiContext ? 
        WindowManager.getMainWindowFromUIContext(uiContext) : 
        WindowManager.getMainWindow();
      
      if (!mainWindow) {
        logger.error(WindowManager.TAG, '❌ 无法获取主窗口，隐藏导航栏失败');
        return;
      }

      // 取消全屏布局
      mainWindow.setWindowLayoutFullScreen(false).then(() => {
        logger.info(WindowManager.TAG, '✅ 取消全屏布局成功');
      }).catch((err: BusinessError) => {
        logger.error(WindowManager.TAG, `❌ 取消全屏布局失败: ${JSON.stringify(err)}`);
      });

      // 只显示状态栏
      mainWindow.setWindowSystemBarEnable(['status']).then(() => {
        logger.info(WindowManager.TAG, '✅ 导航栏已隐藏，状态栏保持显示');
        WindowManager.currentMode = DisplayMode.HIDE_NAVIGATION_BAR;
        WindowManager.refreshStoredSystemBarHeightsAfterModeChange(mainWindow);
      }).catch((err: BusinessError) => {
        logger.error(WindowManager.TAG, `❌ 设置系统栏显示失败: ${JSON.stringify(err)}`);
      });

    } catch (error) {
      logger.error(WindowManager.TAG, `❌ 隐藏导航栏异常: ${(error as Error).message}`);
    }
  }

  /**
   * 恢复默认显示模式 - 显示所有系统栏
   * @param uiContext 可选的UIContext，推荐在组件中传入
   */
  static restoreDefault(uiContext?: UIContext): void {
    try {
      const mainWindow = uiContext ? 
        WindowManager.getMainWindowFromUIContext(uiContext) : 
        WindowManager.getMainWindow();
      
      if (!mainWindow) {
        logger.error(WindowManager.TAG, '❌ 无法获取主窗口，恢复默认模式失败');
        return;
      }

      // 取消全屏布局，保证系统状态栏/导航栏由系统避让
      mainWindow.setWindowLayoutFullScreen(false).then(() => {
        logger.info(WindowManager.TAG, '✅ 取消全屏布局成功');
      }).catch((err: BusinessError) => {
        logger.error(WindowManager.TAG, `❌ 取消全屏布局失败: ${JSON.stringify(err)}`);
      });

      // 显示所有系统栏
      mainWindow.setWindowSystemBarEnable(['status', 'navigation']).then(() => {
        logger.info(WindowManager.TAG, '✅ 已恢复默认显示模式');
        WindowManager.currentMode = DisplayMode.DEFAULT;
        WindowManager.setDefaultSystemBar(mainWindow);
        WindowManager.refreshStoredSystemBarHeightsAfterModeChange(mainWindow);
      }).catch((err: BusinessError) => {
        logger.error(WindowManager.TAG, `❌ 恢复默认显示模式失败: ${JSON.stringify(err)}`);
      });

    } catch (error) {
      logger.error(WindowManager.TAG, `❌ 恢复默认模式异常: ${(error as Error).message}`);
    }
  }

  /**
   * 设置沉浸式但保持系统栏可见（透明背景）
   * @param uiContext 可选的UIContext，推荐在组件中传入
   */
  static setImmersiveWithBars(uiContext?: UIContext): void {
    try {
      const mainWindow = uiContext ? 
        WindowManager.getMainWindowFromUIContext(uiContext) : 
        WindowManager.getMainWindow();
      
      if (!mainWindow) {
        logger.error(WindowManager.TAG, '❌ 无法获取主窗口，设置沉浸式模式失败');
        return;
      }

      // 设置全屏布局
      mainWindow.setWindowLayoutFullScreen(true).then(() => {
        logger.info(WindowManager.TAG, '✅ 全屏布局设置成功');
      }).catch((err: BusinessError) => {
        logger.error(WindowManager.TAG, `❌ 设置全屏布局失败: ${JSON.stringify(err)}`);
      });

      // 保持系统栏显示
      mainWindow.setWindowSystemBarEnable(['status', 'navigation']).then(() => {
        logger.info(WindowManager.TAG, '✅ 系统栏保持显示');
        WindowManager.refreshStoredSystemBarHeightsAfterModeChange(mainWindow);
      }).catch((err: BusinessError) => {
        logger.error(WindowManager.TAG, `❌ 设置系统栏显示失败: ${JSON.stringify(err)}`);
      });

      // 设置透明系统栏
      WindowManager.setTransparentSystemBar(mainWindow);
      WindowManager.currentMode = DisplayMode.IMMERSIVE_WITH_BARS;

    } catch (error) {
      logger.error(WindowManager.TAG, `❌ 设置沉浸式模式异常: ${(error as Error).message}`);
    }
  }

  /**
   * 专用模式：页面自行处理状态栏避让，同时允许内容延伸到底部导航栏区域
   * @param uiContext 可选的UIContext，推荐在组件中传入
   */
  static setStatusSafeBottomImmersive(uiContext?: UIContext): void {
    try {
      const mainWindow = uiContext ?
        WindowManager.getMainWindowFromUIContext(uiContext) :
        WindowManager.getMainWindow();

      if (!mainWindow) {
        logger.error(WindowManager.TAG, '❌ 无法获取主窗口，设置专用沉浸模式失败');
        return;
      }

      // 启用全屏布局，允许内容延伸到导航栏区域
      mainWindow.setWindowLayoutFullScreen(true).then(() => {
        logger.info(WindowManager.TAG, '✅ 专用沉浸模式全屏布局设置成功');
      }).catch((err: BusinessError) => {
        logger.error(WindowManager.TAG, `❌ 专用沉浸模式全屏布局设置失败: ${JSON.stringify(err)}`);
      });

      // 保持状态栏和导航栏都可见，由页面自行处理顶部状态栏避让
      mainWindow.setWindowSystemBarEnable(['status', 'navigation']).then(() => {
        logger.info(WindowManager.TAG, '✅ 专用沉浸模式系统栏设置成功');
        WindowManager.currentMode = DisplayMode.STATUS_SAFE_BOTTOM_IMMERSIVE;
        WindowManager.setNormalSystemBar(mainWindow);
        WindowManager.refreshStoredSystemBarHeightsAfterModeChange(mainWindow);
      }).catch((err: BusinessError) => {
        logger.error(WindowManager.TAG, `❌ 专用沉浸模式系统栏设置失败: ${JSON.stringify(err)}`);
      });
    } catch (error) {
      logger.error(WindowManager.TAG, `❌ 设置专用沉浸模式异常: ${(error as Error).message}`);
    }
  }

  static setPreferredOrientationLandscape(uiContext?: UIContext): void {
    OrientationLockManager.applyStrategy(
      OrientationLockStrategy.LANDSCAPE,
      uiContext,
      'WindowManager.setPreferredOrientationLandscape'
    ).then((result: OrientationLockApplyResult) => {
      if (result.success) {
        logger.info(WindowManager.TAG, '已设置为横屏显示');
      } else {
        logger.error(WindowManager.TAG, `设置横屏失败: ${result.message}`);
      }
    });
  }

  static setPreferredOrientationAuto(uiContext?: UIContext): void {
    OrientationLockManager.applyStrategy(
      OrientationLockStrategy.AUTO_ROTATION_RESTRICTED,
      uiContext,
      'WindowManager.setPreferredOrientationAuto'
    ).then((result: OrientationLockApplyResult) => {
      if (result.success) {
        logger.info(WindowManager.TAG, '已恢复自动旋转');
      } else {
        logger.error(WindowManager.TAG, `恢复自动旋转失败: ${result.message}`);
      }
    });
  }

  /**
   * 设置系统栏颜色和样式
   * @param config 系统栏配置
   * @param uiContext 可选的UIContext，推荐在组件中传入
   */
  static setSystemBarStyle(config: SystemBarConfig, uiContext?: UIContext): void {
    try {
      const mainWindow = uiContext ? 
        WindowManager.getMainWindowFromUIContext(uiContext) : 
        WindowManager.getMainWindow();
      
      if (!mainWindow) {
        logger.error(WindowManager.TAG, '❌ 无法获取主窗口，设置系统栏样式失败');
        return;
      }

      const systemBarProperties: window.SystemBarProperties = {
        statusBarColor: config.statusBarColor ?? '#00000000',
        navigationBarColor: config.navigationBarColor ?? '#00000000',
        statusBarContentColor: config.statusBarContentColor ?? '#FF000000',
        navigationBarContentColor: config.navigationBarContentColor ?? '#FF000000',
        isStatusBarLightIcon: config.isStatusBarLightIcon ?? false,
        isNavigationBarLightIcon: config.isNavigationBarLightIcon ?? false
      };

      mainWindow.setWindowSystemBarProperties(systemBarProperties).then(() => {
        logger.info(WindowManager.TAG, '✅ 系统栏样式设置成功');
      }).catch((err: BusinessError) => {
        logger.error(WindowManager.TAG, `❌ 设置系统栏样式失败: ${JSON.stringify(err)}`);
      });

    } catch (error) {
      logger.error(WindowManager.TAG, `❌ 设置系统栏样式异常: ${(error as Error).message}`);
    }
  }

  /**
   * 设置透明系统栏
   * @param mainWindow 主窗口实例
   */
  private static setTransparentSystemBar(mainWindow: window.Window): void {
    if (AppStorage.get<boolean>('window_manager_theme_bar_enabled') !== false) {
      WindowManager.applyThemeAwareSystemBar(mainWindow, true);
      return;
    }
    try {
      const themeStyle = WindowManager.resolveThemeSystemBarStyle();
      const systemBarProperties: window.SystemBarProperties = {
        statusBarColor: '#00000000', // 透明状态栏背景
        navigationBarColor: '#00000000', // 透明导航栏背景
        statusBarContentColor: themeStyle.contentColor, // 状态栏内容颜色（跟随主题）
        navigationBarContentColor: themeStyle.contentColor, // 导航栏内容颜色（跟随主题）
        isStatusBarLightIcon: themeStyle.isDarkTheme, // 深色主题下使用浅色图标
        isNavigationBarLightIcon: themeStyle.isDarkTheme, // 深色主题下使用浅色图标
        enableStatusBarAnimation: true, // 启用状态栏动画
        enableNavigationBarAnimation: true // 启用导航栏动画
      };

      mainWindow.setWindowSystemBarProperties(systemBarProperties).then(() => {
        logger.info(WindowManager.TAG, '✅ 透明系统栏设置成功');
      }).catch((err: BusinessError) => {
        logger.error(WindowManager.TAG, `❌ 设置透明系统栏失败: ${JSON.stringify(err)}`);
      });

    } catch (error) {
      logger.error(WindowManager.TAG, `❌ 设置透明系统栏异常: ${(error as Error).message}`);
    }
  }

  private static resolveThemeSystemBarStyle(): ThemeSystemBarStyle {
    try {
      const themeManager = ThemeManager.getInstance();
      const isDarkTheme = themeManager.isDarkThemeSync();
      const themeConfig = themeManager.getCurrentThemeConfigSync();
      const backgroundColor = themeConfig.backgroundColor || (isDarkTheme ? '#121214' : '#FAFAFA');
      const themeStyle: ThemeSystemBarStyle = {
        isDarkTheme,
        contentColor: isDarkTheme ? '#FFFFFFFF' : '#E5000000',
        backgroundColor
      };
      return themeStyle;
    } catch (error) {
      logger.warn(WindowManager.TAG, `系统栏主题样式解析失败，使用兜底值: ${(error as Error).message}`);
      const fallbackStyle: ThemeSystemBarStyle = {
        isDarkTheme: true,
        contentColor: '#FFFFFFFF',
        backgroundColor: '#121214'
      };
      return fallbackStyle;
    }
  }

  private static setDefaultSystemBar(mainWindow: window.Window): void {
    if (AppStorage.get<boolean>('window_manager_theme_bar_enabled') !== false) {
      WindowManager.applyThemeAwareSystemBar(mainWindow, true, false);
      return;
    }
    try {
      const themeStyle = WindowManager.resolveThemeSystemBarStyle();
      const systemBarProperties: window.SystemBarProperties = {
        // 默认模式继续使用系统避让，但让顶部状态栏透出页面自己的背景层。
        statusBarColor: '#00000000',
        navigationBarColor: themeStyle.backgroundColor,
        statusBarContentColor: themeStyle.contentColor,
        navigationBarContentColor: themeStyle.contentColor,
        isStatusBarLightIcon: themeStyle.isDarkTheme,
        isNavigationBarLightIcon: themeStyle.isDarkTheme,
        enableStatusBarAnimation: true,
        enableNavigationBarAnimation: true
      };

      mainWindow.setWindowSystemBarProperties(systemBarProperties).then(() => {
        logger.info(WindowManager.TAG, '✅ 非沉浸场景系统栏样式设置成功');
      }).catch((err: BusinessError) => {
        logger.error(WindowManager.TAG, `❌ 非沉浸场景系统栏样式设置失败: ${JSON.stringify(err)}`);
      });
    } catch (error) {
      logger.error(WindowManager.TAG, `❌ 非沉浸场景系统栏样式设置异常: ${(error as Error).message}`);
    }
  }

  private static applyThemeAwareSystemBar(mainWindow: window.Window, statusBarTransparent: boolean,
    navigationBarTransparent: boolean = statusBarTransparent): void {
    try {
      const themeStyle = WindowManager.resolveThemeSystemBarStyle();
      const systemBarProperties: window.SystemBarProperties = {
        statusBarColor: statusBarTransparent ? '#00000000' : themeStyle.backgroundColor,
        navigationBarColor: navigationBarTransparent ? '#00000000' : themeStyle.backgroundColor,
        statusBarContentColor: themeStyle.contentColor,
        navigationBarContentColor: themeStyle.contentColor,
        isStatusBarLightIcon: themeStyle.isDarkTheme,
        isNavigationBarLightIcon: themeStyle.isDarkTheme,
        enableStatusBarAnimation: true,
        enableNavigationBarAnimation: true
      };

      mainWindow.setWindowSystemBarProperties(systemBarProperties).then(() => {
        logger.info(WindowManager.TAG, '✅ 系统栏样式按主题更新成功');
      }).catch((err: BusinessError) => {
        logger.error(WindowManager.TAG, `❌ 系统栏样式按主题更新失败: ${JSON.stringify(err)}`);
      });
    } catch (error) {
      logger.error(WindowManager.TAG, `❌ 系统栏样式按主题更新异常: ${(error as Error).message}`);
    }
  }

  private static registerThemeChangeMonitor(mainWindow: window.Window): void {
    try {
      WindowManager.unregisterThemeChangeMonitor();
      WindowManager.themeChangeCallback = (_theme: ThemeType): void => {
        switch (WindowManager.currentMode) {
          case DisplayMode.DEFAULT:
            WindowManager.setDefaultSystemBar(mainWindow);
            break;
          case DisplayMode.STATUS_SAFE_BOTTOM_IMMERSIVE:
            WindowManager.setNormalSystemBar(mainWindow);
            break;
          case DisplayMode.IMMERSIVE_WITH_BARS:
            WindowManager.setTransparentSystemBar(mainWindow);
            break;
          default:
            break;
        }
      };
      ThemeManager.getInstance().onThemeChange(WindowManager.themeChangeCallback);
    } catch (error) {
      logger.warn(WindowManager.TAG, `注册主题变化监听失败: ${(error as Error).message}`);
    }
  }

  private static unregisterThemeChangeMonitor(): void {
    if (!WindowManager.themeChangeCallback) {
      return;
    }
    try {
      ThemeManager.getInstance().offThemeChange(WindowManager.themeChangeCallback);
    } catch (error) {
      logger.warn(WindowManager.TAG, `移除主题变化监听失败: ${(error as Error).message}`);
    } finally {
      WindowManager.themeChangeCallback = null;
    }
  }

  /**
   * 设置正常系统栏
   * @param mainWindow 主窗口实例
   */

  static setNormalSystemBar(mainWindow: window.Window): void {
    if (AppStorage.get<boolean>('window_manager_theme_bar_enabled') !== false) {
      WindowManager.applyThemeAwareSystemBar(mainWindow, true);
      return;
    }
    try {
      const themeStyle = WindowManager.resolveThemeSystemBarStyle();
      const systemBarProperties: window.SystemBarProperties = {
        statusBarColor: '#00000000', // 状态栏默认颜色
        navigationBarColor: '#00000000', // 导航栏默认颜色
        statusBarContentColor: themeStyle.contentColor, // 状态栏内容颜色（跟随主题）
        navigationBarContentColor: themeStyle.contentColor, // 导航栏内容颜色（跟随主题）
        isStatusBarLightIcon: themeStyle.isDarkTheme, // 深色主题下使用浅色图标
        isNavigationBarLightIcon: themeStyle.isDarkTheme, // 深色主题下使用浅色图标
        enableStatusBarAnimation: true, // 启用状态栏动画
        enableNavigationBarAnimation: true // 启用导航栏动画
      };

      mainWindow.setWindowSystemBarProperties(systemBarProperties).then(() => {
        logger.info(WindowManager.TAG, '✅ 正常系统栏设置成功');
      }).catch((err: BusinessError) => {
        logger.error(WindowManager.TAG, `❌ 设置正常系统栏失败: ${JSON.stringify(err)}`);
      });

    } catch (error) {
      logger.error(WindowManager.TAG, `❌ 设置正常系统栏异常: ${(error as Error).message}`);
    }
  }

  /**
   * 根据显示模式枚举设置显示模式
   * @param mode 显示模式
   * @param uiContext 可选的UIContext，推荐在组件中传入
   */
  static setDisplayMode(mode: DisplayMode, uiContext?: UIContext): void {
    switch (mode) {
      case DisplayMode.FULL_IMMERSIVE:
        WindowManager.setFullImmersive(uiContext);
        break;
      case DisplayMode.HIDE_STATUS_BAR:
        WindowManager.hideStatusBar(uiContext);
        break;
      case DisplayMode.HIDE_NAVIGATION_BAR:
        WindowManager.hideNavigationBar(uiContext);
        break;
      case DisplayMode.IMMERSIVE_WITH_BARS:
        WindowManager.setImmersiveWithBars(uiContext);
        break;
      case DisplayMode.STATUS_SAFE_BOTTOM_IMMERSIVE:
        WindowManager.setStatusSafeBottomImmersive(uiContext);
        break;
      case DisplayMode.DEFAULT:
      default:
        WindowManager.restoreDefault(uiContext);
        break;
    }
  }

  /**
   * 获取当前显示模式
   */
  static setDisplayModeWithTransition(mode: DisplayMode, uiContext?: UIContext): void {
    const currentMode = WindowManager.getCurrentMode();
    if (currentMode === mode) {
      return;
    }

    const profile = WindowManager.resolvePageShowTransitionProfile(currentMode, mode);
    if (profile.strategy !== DisplayModeTransitionStrategy.SWITCH_AFTER_PAGE_SHOW || !profile.useOverlay) {
      WindowManager.setDisplayMode(mode, uiContext);
      return;
    }

    const generation = WindowManager.beginManagedDisplayTransition(profile);
    WindowManager.transitionModeApplyTimer = setTimeout(() => {
      WindowManager.transitionModeApplyTimer = -1;
      if (generation !== WindowManager.transitionGeneration) {
        return;
      }

      WindowManager.setDisplayMode(mode, uiContext);
      WindowManager.transitionOverlayCleanupTimer = setTimeout(() => {
        WindowManager.transitionOverlayCleanupTimer = -1;
        if (generation !== WindowManager.transitionGeneration) {
          return;
        }
        WindowManager.hideTransitionOverlay(profile.overlayFadeOutDurationMs);
      }, profile.settleDurationMs);
    }, profile.modeApplyDelayMs);
  }

  static navigateWithManagedDisplayMode(
    targetMode: DisplayMode,
    navigate: () => void,
    uiContext?: UIContext
  ): void {
    const currentMode = WindowManager.getCurrentMode();
    const profile = WindowManager.resolveForwardNavigationTransitionProfile(currentMode, targetMode);
    if (profile.strategy !== DisplayModeTransitionStrategy.SWITCH_BEFORE_NAVIGATION || !profile.useOverlay) {
      const shouldApplyImmediately = currentMode !== targetMode
        && WindowManager.isFullscreenDisplayMode(currentMode)
        && !WindowManager.isFullscreenDisplayMode(targetMode);
      if (shouldApplyImmediately && profile.strategy === DisplayModeTransitionStrategy.IMMEDIATE) {
        WindowManager.setDisplayMode(targetMode, uiContext);
      }
      navigate();
      return;
    }

    const generation = WindowManager.beginManagedDisplayTransition(profile);
    WindowManager.transitionModeApplyTimer = setTimeout(() => {
      WindowManager.transitionModeApplyTimer = -1;
      if (generation !== WindowManager.transitionGeneration) {
        return;
      }
      WindowManager.setDisplayMode(targetMode, uiContext);
    }, profile.modeApplyDelayMs);

    WindowManager.transitionNavigationTimer = setTimeout(() => {
      WindowManager.transitionNavigationTimer = -1;
      if (generation !== WindowManager.transitionGeneration) {
        return;
      }
      navigate();
      WindowManager.hideTransitionOverlay(profile.overlayFadeOutDurationMs);
    }, profile.navigationDelayMs);
  }

  static getCurrentMode(): DisplayMode {
    return WindowManager.currentMode;
  }

  private static isFullscreenDisplayMode(mode: DisplayMode): boolean {
    return mode === DisplayMode.FULL_IMMERSIVE || mode === DisplayMode.IMMERSIVE_WITH_BARS;
  }

  private static isSystemFittedDisplayMode(mode: DisplayMode): boolean {
    return mode === DisplayMode.DEFAULT
      || mode === DisplayMode.HIDE_STATUS_BAR
      || mode === DisplayMode.HIDE_NAVIGATION_BAR;
  }

  private static initializeTransitionOverlayState(): void {
    AppStorage.setOrCreate(WindowManager.TRANSITION_OVERLAY_VISIBLE_KEY, false);
    AppStorage.setOrCreate(WindowManager.TRANSITION_OVERLAY_OPACITY_KEY, 0);
    AppStorage.setOrCreate(WindowManager.TRANSITION_OVERLAY_USE_BLUR_KEY, true);
    AppStorage.setOrCreate(WindowManager.TRANSITION_OVERLAY_PREFERS_DARK_KEY, true);
  }

  private static clearManagedDisplayTransitionTimers(): void {
    if (WindowManager.transitionModeApplyTimer >= 0) {
      clearTimeout(WindowManager.transitionModeApplyTimer);
      WindowManager.transitionModeApplyTimer = -1;
    }
    if (WindowManager.transitionNavigationTimer >= 0) {
      clearTimeout(WindowManager.transitionNavigationTimer);
      WindowManager.transitionNavigationTimer = -1;
    }
    if (WindowManager.transitionOverlayCleanupTimer >= 0) {
      clearTimeout(WindowManager.transitionOverlayCleanupTimer);
      WindowManager.transitionOverlayCleanupTimer = -1;
    }
  }

  private static beginManagedDisplayTransition(profile: DisplayModeTransitionProfile): number {
    WindowManager.initializeTransitionOverlayState();
    WindowManager.clearManagedDisplayTransitionTimers();
    WindowManager.transitionGeneration += 1;
    WindowManager.showTransitionOverlay(profile.overlayPeakOpacity, profile.useBlurOverlay);
    logger.info(WindowManager.TAG, `开始托管窗口过渡: ${profile.key}`);
    return WindowManager.transitionGeneration;
  }

  private static showTransitionOverlay(opacity: number, useBlur: boolean): void {
    WindowManager.initializeTransitionOverlayState();
    const prefersDark = WindowManager.resolveThemeSystemBarStyle().isDarkTheme;
    AppStorage.setOrCreate(WindowManager.TRANSITION_OVERLAY_PREFERS_DARK_KEY, prefersDark);
    AppStorage.setOrCreate(WindowManager.TRANSITION_OVERLAY_USE_BLUR_KEY, useBlur);
    AppStorage.setOrCreate(WindowManager.TRANSITION_OVERLAY_VISIBLE_KEY, true);
    AppStorage.setOrCreate(WindowManager.TRANSITION_OVERLAY_OPACITY_KEY, opacity);
  }

  private static hideTransitionOverlay(fadeOutDurationMs: number): void {
    WindowManager.initializeTransitionOverlayState();
    AppStorage.setOrCreate(WindowManager.TRANSITION_OVERLAY_OPACITY_KEY, 0);
    if (WindowManager.transitionOverlayCleanupTimer >= 0) {
      clearTimeout(WindowManager.transitionOverlayCleanupTimer);
      WindowManager.transitionOverlayCleanupTimer = -1;
    }
    WindowManager.transitionOverlayCleanupTimer = setTimeout(() => {
      WindowManager.transitionOverlayCleanupTimer = -1;
      AppStorage.setOrCreate(WindowManager.TRANSITION_OVERLAY_VISIBLE_KEY, false);
    }, fadeOutDurationMs + WindowManager.TRANSITION_OVERLAY_CLEANUP_BUFFER_MS);
  }

  private static resolveForwardNavigationTransitionProfile(
    sourceMode: DisplayMode,
    targetMode: DisplayMode
  ): DisplayModeTransitionProfile {
    if (sourceMode === targetMode) {
      return WindowManager.buildImmediateTransitionProfile('same_mode');
    }

    const sourceIsFullscreen = WindowManager.isFullscreenDisplayMode(sourceMode);
    const targetIsFullscreen = WindowManager.isFullscreenDisplayMode(targetMode);
    if (!sourceIsFullscreen || targetIsFullscreen) {
      return WindowManager.buildImmediateTransitionProfile(`forward_direct_${sourceMode}_to_${targetMode}`);
    }

    if (targetMode === DisplayMode.STATUS_SAFE_BOTTOM_IMMERSIVE) {
      return {
        key: 'fullscreen_to_safe_immersive',
        strategy: DisplayModeTransitionStrategy.SWITCH_BEFORE_NAVIGATION,
        useOverlay: true,
        useBlurOverlay: true,
        overlayPeakOpacity: 0.14,
        modeApplyDelayMs: 18,
        navigationDelayMs: 68,
        settleDurationMs: 0,
        overlayFadeOutDurationMs: 170
      };
    }

    return {
      key: 'fullscreen_to_system_fitted',
      strategy: DisplayModeTransitionStrategy.SWITCH_BEFORE_NAVIGATION,
      useOverlay: true,
      useBlurOverlay: true,
      overlayPeakOpacity: 0.2,
      modeApplyDelayMs: 18,
      navigationDelayMs: 84,
      settleDurationMs: 0,
      overlayFadeOutDurationMs: 190
    };
  }

  private static resolvePageShowTransitionProfile(
    sourceMode: DisplayMode,
    targetMode: DisplayMode
  ): DisplayModeTransitionProfile {
    if (sourceMode === targetMode) {
      return WindowManager.buildImmediateTransitionProfile('same_mode');
    }

    const sourceIsFullscreen = WindowManager.isFullscreenDisplayMode(sourceMode);
    const targetIsFullscreen = WindowManager.isFullscreenDisplayMode(targetMode);
    if (sourceIsFullscreen || !targetIsFullscreen) {
      return WindowManager.buildImmediateTransitionProfile(`page_show_direct_${sourceMode}_to_${targetMode}`);
    }

    if (targetMode === DisplayMode.IMMERSIVE_WITH_BARS) {
      return {
        key: 'system_to_fullscreen_with_bars',
        strategy: DisplayModeTransitionStrategy.SWITCH_AFTER_PAGE_SHOW,
        useOverlay: true,
        useBlurOverlay: true,
        overlayPeakOpacity: 0.12,
        modeApplyDelayMs: 28,
        navigationDelayMs: 0,
        settleDurationMs: 130,
        overlayFadeOutDurationMs: 170
      };
    }

    if (WindowManager.isSystemFittedDisplayMode(sourceMode)) {
      return {
        key: 'system_to_fullscreen_hidden_bars',
        strategy: DisplayModeTransitionStrategy.SWITCH_AFTER_PAGE_SHOW,
        useOverlay: true,
        useBlurOverlay: true,
        overlayPeakOpacity: 0.18,
        modeApplyDelayMs: 42,
        navigationDelayMs: 0,
        settleDurationMs: 150,
        overlayFadeOutDurationMs: 190
      };
    }

    return {
      key: 'safe_immersive_to_fullscreen_hidden_bars',
      strategy: DisplayModeTransitionStrategy.SWITCH_AFTER_PAGE_SHOW,
      useOverlay: true,
      useBlurOverlay: true,
      overlayPeakOpacity: 0.15,
      modeApplyDelayMs: 36,
      navigationDelayMs: 0,
      settleDurationMs: 140,
      overlayFadeOutDurationMs: 180
    };
  }

  private static buildImmediateTransitionProfile(key: string): DisplayModeTransitionProfile {
    return {
      key,
      strategy: DisplayModeTransitionStrategy.IMMEDIATE,
      useOverlay: false,
      useBlurOverlay: false,
      overlayPeakOpacity: 0,
      modeApplyDelayMs: 0,
      navigationDelayMs: 0,
      settleDurationMs: 0,
      overlayFadeOutDurationMs: 0
    };
  }

  private static refreshStoredSystemBarHeightsAfterModeChange(
    mainWindow: window.Window,
    delayMs: number = 96
  ): void {
    const initialWindow = WindowManager.resolveSystemBarHeightWindow(mainWindow, 'mode_change_initial');
    if (initialWindow) {
      WindowManager.storeSystemBarHeights(initialWindow);
    }
    const retryDelays: number[] = [
      Math.max(0, delayMs),
      Math.max(delayMs + 144, 240),
      Math.max(delayMs + 384, 480)
    ];
    retryDelays.forEach((retryDelay: number) => {
      setTimeout(() => {
        const retryWindow = WindowManager.resolveSystemBarHeightWindow(mainWindow, `mode_change_retry_${retryDelay}`);
        if (!retryWindow) {
          return;
        }
        WindowManager.storeSystemBarHeights(retryWindow);
      }, retryDelay);
    });
  }

  private static isWindowUsableForSystemBarHeights(targetWindow: window.Window, reason: string): boolean {
    try {
      targetWindow.getWindowProperties();
      return true;
    } catch (error) {
      const lifecycleError = error as BusinessError;
      if (WindowManager.isWindowLifecycleAbnormalError(lifecycleError)) {
        logger.debug(
          WindowManager.TAG,
          `系统栏高度刷新跳过失效窗口: source=${reason}, ` +
            `code=${WindowManager.getWindowLifecycleErrorCode(lifecycleError)}, ` +
            `windowLifecycle=destroyed_or_detached, reason=${WindowManager.getWindowLifecycleErrorMessage(lifecycleError)}`
        );
        return false;
      }
      return true;
    }
  }

  private static resolveSystemBarHeightWindow(
    preferredWindow: window.Window,
    reason: string
  ): window.Window | null {
    if (WindowManager.isWindowUsableForSystemBarHeights(preferredWindow, reason)) {
      return preferredWindow;
    }

    const currentMainWindow = WindowManager.getMainWindowFromWindowStageRef(
      `system bar height fallback: ${reason}`,
      true
    );
    if (!currentMainWindow) {
      logger.debug(
        WindowManager.TAG,
        `系统栏高度刷新跳过: source=${reason}, windowLifecycle=destroyed_or_detached, reason=no_active_main_window`
      );
      return null;
    }

    if (!WindowManager.isWindowUsableForSystemBarHeights(currentMainWindow, `${reason}_fallback`)) {
      return null;
    }
    return currentMainWindow;
  }

  private static isStatusBarExpectedVisible(mode: DisplayMode): boolean {
    return mode !== DisplayMode.FULL_IMMERSIVE && mode !== DisplayMode.HIDE_STATUS_BAR;
  }

  private static isNavigationBarExpectedVisible(mode: DisplayMode): boolean {
    return mode !== DisplayMode.FULL_IMMERSIVE && mode !== DisplayMode.HIDE_NAVIGATION_BAR;
  }

  /**
   * 获取并存储系统栏高度信息
   * @param windowOrContext 可以传入Window实例或UIContext
   */
  static storeSystemBarHeights(windowOrContext?: window.Window | UIContext): void {
    try {
      let mainWindow: window.Window | null = null;

      if (windowOrContext) {
        // 使用typeof检查是否是Window实例（Window有getWindowAvoidArea方法）
        const temp = windowOrContext as window.Window;
        if (typeof temp.getWindowAvoidArea === 'function') {
          mainWindow = temp;
        } else {
          // 尝试从UIContext获取
          mainWindow = WindowManager.getMainWindowFromUIContext(windowOrContext as UIContext);
        }
      } else {
        // 兼容旧的调用方式（不推荐）
        mainWindow = WindowManager.getMainWindow();
      }
      
      if (!mainWindow) {
        logger.error(WindowManager.TAG, '❌ 无法获取主窗口，存储系统栏高度失败');
        return;
      }

      // 获取状态栏区域
      const statusBarArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const statusBarHeightPx = statusBarArea.topRect.height;

      // 获取导航栏区域
      const navigationArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      const navigationBarHeightPx = navigationArea.bottomRect.height;

      // 使用display模块获取屏幕密度进行单位转换
      const displayInfo = display.getDefaultDisplaySync();
      const density = displayInfo.densityDPI / 160; // 计算密度比例

      const measuredStatusBarHeight = statusBarHeightPx / density;
      const measuredNavigationBarHeight = navigationBarHeightPx / density;
      let statusBarHeight = measuredStatusBarHeight;
      let navigationBarHeight = measuredNavigationBarHeight;

      if (measuredStatusBarHeight > 0) {
        AppStorage.setOrCreate(WindowManager.LAST_VISIBLE_STATUS_BAR_HEIGHT_KEY, measuredStatusBarHeight);
      }
      if (measuredNavigationBarHeight > 0) {
        AppStorage.setOrCreate(WindowManager.LAST_VISIBLE_NAVIGATION_BAR_HEIGHT_KEY, measuredNavigationBarHeight);
      }

      if (WindowManager.isStatusBarExpectedVisible(WindowManager.currentMode) && measuredStatusBarHeight <= 0) {
        const fallbackStatusBarHeight = AppStorage.get<number>(WindowManager.LAST_VISIBLE_STATUS_BAR_HEIGHT_KEY)
          ?? AppStorage.get<number>('statusBarHeight')
          ?? 0;
        if (fallbackStatusBarHeight > 0) {
          statusBarHeight = fallbackStatusBarHeight;
          logger.warn(
            WindowManager.TAG,
            `Status bar height measured as 0 while visible in mode=${WindowManager.currentMode}, using fallback=${fallbackStatusBarHeight.toFixed(2)}vp`
          );
        }
      }

      if (WindowManager.isNavigationBarExpectedVisible(WindowManager.currentMode) && measuredNavigationBarHeight <= 0) {
        const fallbackNavigationBarHeight = AppStorage.get<number>(WindowManager.LAST_VISIBLE_NAVIGATION_BAR_HEIGHT_KEY)
          ?? AppStorage.get<number>('navigationBarHeight')
          ?? 0;
        if (fallbackNavigationBarHeight > 0) {
          navigationBarHeight = fallbackNavigationBarHeight;
          logger.warn(
            WindowManager.TAG,
            `Navigation bar height measured as 0 while visible in mode=${WindowManager.currentMode}, using fallback=${fallbackNavigationBarHeight.toFixed(2)}vp`
          );
        }
      }

      // 存储到AppStorage中供组件使用
      AppStorage.setOrCreate('statusBarHeight', statusBarHeight);
      AppStorage.setOrCreate('navigationBarHeight', navigationBarHeight);

      // 持久化存储
      PersistentStorage.persistProp('statusBarHeight', statusBarHeight);
      PersistentStorage.persistProp('navigationBarHeight', navigationBarHeight);

      logger.info(
        WindowManager.TAG,
        `📏 系统栏高度信息已存储 - 状态栏: ${statusBarHeight.toFixed(2)}vp(测量=${measuredStatusBarHeight.toFixed(2)}vp), ` +
          `导航栏: ${navigationBarHeight.toFixed(2)}vp(测量=${measuredNavigationBarHeight.toFixed(2)}vp)`
      );

    } catch (error) {
      const lifecycleError = error as BusinessError;
      if (WindowManager.isWindowLifecycleAbnormalError(lifecycleError)) {
        logger.debug(
          WindowManager.TAG,
          `系统栏高度存储跳过: source=storeSystemBarHeights, ` +
            `code=${WindowManager.getWindowLifecycleErrorCode(lifecycleError)}, ` +
            `windowLifecycle=destroyed_or_detached, reason=${WindowManager.getWindowLifecycleErrorMessage(lifecycleError)}`
        );
        return;
      }
      logger.error(WindowManager.TAG, `❌ 存储系统栏高度失败: ${(error as Error).message}`);
    }
  }

  /**
   * 获取当前存储的系统栏高度
   */
  static getStoredSystemBarHeights(): SystemBarHeights {
    const statusBarHeight = AppStorage.get<number>('statusBarHeight') ?? 0;
    const navigationBarHeight = AppStorage.get<number>('navigationBarHeight') ?? 0;

    return {
      statusBarHeight,
      navigationBarHeight
    };
  }

  /**
   * 初始化窗口管理器 - 推荐在应用启动时调用
   * @param windowStage 窗口舞台实例
   */
  static initialize(windowStage: window.WindowStage): void {
    try {
      const mainWindow = windowStage.getMainWindowSync();
      WindowManager.initializeTransitionOverlayState();
      WindowManager.registerWindowStageStateMonitor(windowStage);
      
      // 存储系统栏高度信息（直接传递mainWindow实例）
      WindowManager.storeSystemBarHeights(mainWindow);

      // 初始化默认模式：显示系统栏并保持非全屏布局（系统自动避让）
      mainWindow.setWindowLayoutFullScreen(false).then(() => {
        logger.info(WindowManager.TAG, '✅ 初始化默认模式非全屏布局设置成功');
      }).catch((err: BusinessError) => {
        logger.error(WindowManager.TAG, `❌ 初始化默认模式非全屏布局设置失败: ${JSON.stringify(err)}`);
      });

      mainWindow.setWindowSystemBarEnable(['status', 'navigation']).then(() => {
        logger.info(WindowManager.TAG, '✅ 初始化默认模式系统栏设置成功');
      }).catch((err: BusinessError) => {
        logger.error(WindowManager.TAG, `❌ 初始化默认模式系统栏设置失败: ${JSON.stringify(err)}`);
      });

      WindowManager.currentMode = DisplayMode.DEFAULT;
      // 设置默认的非沉浸系统栏样式
      WindowManager.setDefaultSystemBar(mainWindow);
      WindowManager.registerThemeChangeMonitor(mainWindow);
      WindowManager.syncBackgroundState(false, '窗口管理器初始化');
      
      logger.info(WindowManager.TAG, '✅ WindowManager初始化完成');
      
    } catch (error) {
      logger.error(WindowManager.TAG, `❌ WindowManager初始化失败: ${(error as Error).message}`);
    }
  }

  private static getMainWindowFromWindowStageRef(
    reason: string = 'reapply display mode',
    quietWhenUnavailable: boolean = false
  ): window.Window | null {
    try {
      if (!WindowManager.windowStageRef) {
        if (quietWhenUnavailable) {
          logger.debug(
            WindowManager.TAG,
            `windowStageRef unavailable: ${reason}, windowLifecycle=destroyed_or_detached`
          );
          return null;
        }
        logger.warn(WindowManager.TAG, `windowStageRef unavailable: ${reason}`);
        return null;
      }
      return WindowManager.windowStageRef.getMainWindowSync();
    } catch (error) {
      const lifecycleError = error as BusinessError;
      if (WindowManager.isWindowLifecycleAbnormalError(lifecycleError)) {
        logger.debug(
          WindowManager.TAG,
          `获取主窗口跳过: source=${reason}, code=${WindowManager.getWindowLifecycleErrorCode(lifecycleError)}, ` +
            `windowLifecycle=destroyed_or_detached, reason=${WindowManager.getWindowLifecycleErrorMessage(lifecycleError)}`
        );
        return null;
      }
      logger.error(WindowManager.TAG, `Failed to get main window from WindowStage: ${(error as Error).message}, reason=${reason}`);
      return null;
    }
  }

  static isFloatingWindowVisible(routeName?: AppFloatingWindowRouteName): boolean {
    if (!WindowManager.floatingWindowRef) {
      return false;
    }
    if (!routeName) {
      return true;
    }
    return WindowManager.floatingWindowRouteName === routeName;
  }

  private static syncFloatingWindowBackgroundPrivacyMode(source: string): void {
    const isInBackground = AppStorage.get<boolean>(WindowManager.BACKGROUND_STORAGE_KEY) === true;
    const shouldEnable = WindowManager.shouldEnableBackgroundPrivacyMode(isInBackground);
    WindowManager.applyFloatingWindowBackgroundPrivacyMode(shouldEnable, source);
  }

  static async openAppFloatingWindow(config: AppFloatingWindowConfig): Promise<boolean> {
    if (WindowManager.isFloatingWindowOpening) {
      logger.warn(WindowManager.TAG, `应用内小窗正在打开中: route=${config.routeName}`);
      return false;
    }

    const windowStage = WindowManager.windowStageRef;
    if (!windowStage) {
      logger.warn(WindowManager.TAG, `无法打开应用内小窗，WindowStage未初始化: route=${config.routeName}`);
      return false;
    }

    if (WindowManager.floatingWindowRef && WindowManager.floatingWindowRouteName === config.routeName) {
      return await WindowManager.showExistingFloatingWindow(config);
    }

    if (WindowManager.floatingWindowRef) {
      await WindowManager.closeAppFloatingWindow('切换应用内小窗内容');
    }

    WindowManager.isFloatingWindowOpening = true;
    const windowName = `manxia_app_float_${config.routeName}`;
    const pixelRect = WindowManager.resolveFloatingWindowPixelRect(config);
    const rect: window.Rect = {
      left: pixelRect.x,
      top: pixelRect.y,
      width: pixelRect.width,
      height: pixelRect.height
    };
    const options: window.SubWindowOptions = {
      title: config.title,
      decorEnabled: false,
      isModal: false,
      windowRect: rect,
      maximizeSupported: false,
      zLevel: config.zLevel,
      outlineEnabled: false
    };

    try {
      const subWindow = await windowStage.createSubWindowWithOptions(windowName, options);
      WindowManager.floatingWindowRef = subWindow;
      WindowManager.floatingWindowRouteName = config.routeName;
      AppStorage.setOrCreate(WindowManager.FLOATING_WINDOW_VISIBLE_KEY, true);
      AppStorage.setOrCreate(WindowManager.FLOATING_WINDOW_ROUTE_KEY, config.routeName);

      await WindowManager.configureFloatingWindow(subWindow, config);
      await subWindow.setUIContent(`pages/${config.routeName}`);
      await subWindow.showWindow();
      WindowManager.syncFloatingWindowBackgroundPrivacyMode('应用内小窗打开');
      logger.info(
        WindowManager.TAG,
        `应用内小窗已打开: route=${config.routeName}, rect=${pixelRect.x},${pixelRect.y},${pixelRect.width},${pixelRect.height}`
      );
      return true;
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error(WindowManager.TAG, `打开应用内小窗失败: route=${config.routeName}, error=${errorMessage}`);
      try {
        await WindowManager.destroyFloatingWindowRef('打开失败清理');
      } catch (cleanupError) {
        logger.warn(WindowManager.TAG, `打开失败后清理应用内小窗引用异常: ${String(cleanupError)}`);
      }
      return false;
    } finally {
      WindowManager.isFloatingWindowOpening = false;
    }
  }

  private static async showExistingFloatingWindow(config: AppFloatingWindowConfig): Promise<boolean> {
    const existingWindow = WindowManager.floatingWindowRef;
    if (!existingWindow) {
      return false;
    }

    try {
      await WindowManager.configureFloatingWindow(existingWindow, config);
      await existingWindow.showWindow();
      AppStorage.setOrCreate(WindowManager.FLOATING_WINDOW_VISIBLE_KEY, true);
      AppStorage.setOrCreate(WindowManager.FLOATING_WINDOW_ROUTE_KEY, config.routeName);
      WindowManager.syncFloatingWindowBackgroundPrivacyMode('应用内小窗唤起');
      logger.info(WindowManager.TAG, `已唤起现有应用内小窗: route=${config.routeName}`);
      return true;
    } catch (error) {
      logger.warn(WindowManager.TAG, `唤起现有应用内小窗失败，将重新创建: ${String(error)}`);
      await WindowManager.closeAppFloatingWindow('现有小窗不可用');
      return await WindowManager.openAppFloatingWindow(config);
    }
  }

  private static async configureFloatingWindow(
    targetWindow: window.Window,
    config: AppFloatingWindowConfig
  ): Promise<void> {
    try {
      targetWindow.setWindowBackgroundColor('#00000000');
      targetWindow.setWindowDecorVisible(false);
    } catch (error) {
      logger.warn(WindowManager.TAG, `设置应用内小窗基础外观失败: ${String(error)}`);
    }

    try {
      await targetWindow.setWindowShadowEnabled(false);
    } catch (error) {
      logger.warn(WindowManager.TAG, `关闭应用内小窗系统阴影开关失败: ${String(error)}`);
    }

    try {
      targetWindow.setWindowShadowRadius(0);
    } catch (error) {
      logger.warn(WindowManager.TAG, `清除应用内小窗系统阴影半径失败: ${String(error)}`);
    }

    try {
      await targetWindow.setWindowCornerRadius(18);
    } catch (error) {
      logger.warn(WindowManager.TAG, `设置应用内小窗圆角失败: ${String(error)}`);
    }

    const pixelRect = WindowManager.resolveFloatingWindowPixelRect(config);
    await targetWindow.resize(pixelRect.width, pixelRect.height);
    await targetWindow.moveWindowTo(pixelRect.x, pixelRect.y);
    try {
      await targetWindow.setSubWindowModal(false);
      await targetWindow.setSubWindowZLevel(config.zLevel);
    } catch (error) {
      logger.warn(WindowManager.TAG, `设置应用内小窗层级失败: ${String(error)}`);
    }
  }

  private static resolveFloatingWindowPixelRect(config: AppFloatingWindowConfig): AppFloatingWindowPixelRect {
    try {
      const displayInfo = display.getDefaultDisplaySync();
      const density = Math.max(displayInfo.densityDPI / 160, 1);
      const width = Math.round(config.widthVp * density);
      const height = Math.round(config.heightVp * density);
      const maxX = Math.max(0, displayInfo.width - width);
      const maxY = Math.max(0, displayInfo.height - height);
      const rect: AppFloatingWindowPixelRect = {
        x: Math.round(Math.max(0, Math.min(config.xVp * density, maxX))),
        y: Math.round(Math.max(0, Math.min(config.yVp * density, maxY))),
        width: Math.max(1, Math.min(width, displayInfo.width)),
        height: Math.max(1, Math.min(height, displayInfo.height))
      };
      return rect;
    } catch (error) {
      logger.warn(WindowManager.TAG, `解析应用内小窗像素尺寸失败，使用原始配置: ${String(error)}`);
      const fallbackRect: AppFloatingWindowPixelRect = {
        x: Math.round(config.xVp),
        y: Math.round(config.yVp),
        width: Math.max(1, Math.round(config.widthVp)),
        height: Math.max(1, Math.round(config.heightVp))
      };
      return fallbackRect;
    }
  }

  static async closeAppFloatingWindow(reason: string = '用户关闭'): Promise<boolean> {
    if (!WindowManager.floatingWindowRef) {
      AppStorage.setOrCreate(WindowManager.FLOATING_WINDOW_VISIBLE_KEY, false);
      AppStorage.setOrCreate(WindowManager.FLOATING_WINDOW_ROUTE_KEY, '');
      return true;
    }

    try {
      await WindowManager.destroyFloatingWindowRef(reason);
      logger.info(WindowManager.TAG, `应用内小窗已关闭: reason=${reason}`);
      return true;
    } catch (error) {
      logger.error(WindowManager.TAG, `关闭应用内小窗失败: reason=${reason}, error=${String(error)}`);
      return false;
    }
  }

  static getAppFloatingWindowRect(): window.Rect | null {
    const targetWindow = WindowManager.floatingWindowRef;
    if (!targetWindow) {
      return null;
    }

    try {
      const properties = targetWindow.getWindowProperties();
      const sourceRect = properties.windowRect;
      const rect: window.Rect = {
        left: sourceRect.left,
        top: sourceRect.top,
        width: sourceRect.width,
        height: sourceRect.height
      };
      return rect;
    } catch (error) {
      logger.warn(WindowManager.TAG, `获取应用内小窗位置失败: ${String(error)}`);
      return null;
    }
  }

  static async moveAppFloatingWindowTo(x: number, y: number): Promise<boolean> {
    const targetWindow = WindowManager.floatingWindowRef;
    if (!targetWindow) {
      return false;
    }

    try {
      await targetWindow.moveWindowTo(Math.round(x), Math.round(y));
      return true;
    } catch (error) {
      logger.warn(WindowManager.TAG, `移动应用内小窗失败: x=${x}, y=${y}, error=${String(error)}`);
      return false;
    }
  }

  static async moveAppFloatingWindowByVpOffset(
    startX: number,
    startY: number,
    offsetXVp: number,
    offsetYVp: number
  ): Promise<boolean> {
    try {
      const displayInfo = display.getDefaultDisplaySync();
      const density = Math.max(displayInfo.densityDPI / 160, 1);
      return await WindowManager.moveAppFloatingWindowTo(
        startX + offsetXVp * density,
        startY + offsetYVp * density
      );
    } catch (error) {
      logger.warn(WindowManager.TAG, `按vp偏移移动应用内小窗失败: ${String(error)}`);
      return await WindowManager.moveAppFloatingWindowTo(startX + offsetXVp, startY + offsetYVp);
    }
  }

  static async toggleAppFloatingWindow(config: AppFloatingWindowConfig): Promise<boolean> {
    if (WindowManager.isFloatingWindowVisible(config.routeName)) {
      return await WindowManager.closeAppFloatingWindow('用户切换关闭');
    }
    return await WindowManager.openAppFloatingWindow(config);
  }

  private static async destroyFloatingWindowRef(reason: string): Promise<void> {
    const targetWindow = WindowManager.floatingWindowRef;
    WindowManager.floatingWindowRef = null;
    WindowManager.floatingWindowRouteName = '';
    WindowManager.isFloatingWindowBackgroundPrivacyModeEnabled = false;
    AppStorage.setOrCreate(WindowManager.FLOATING_WINDOW_VISIBLE_KEY, false);
    AppStorage.setOrCreate(WindowManager.FLOATING_WINDOW_ROUTE_KEY, '');
    if (!targetWindow) {
      return;
    }

    try {
      await targetWindow.destroyWindow();
    } catch (error) {
      logger.warn(WindowManager.TAG, `销毁应用内小窗失败: reason=${reason}, error=${String(error)}`);
      throw new Error(`销毁应用内小窗失败: ${String(error)}`);
    }
  }

  private static applyDisplayModeWithMainWindow(mainWindow: window.Window, mode: DisplayMode): void {
    switch (mode) {
      case DisplayMode.FULL_IMMERSIVE:
        void mainWindow.setWindowLayoutFullScreen(true);
        void mainWindow.setWindowSystemBarEnable([]);
        break;
      case DisplayMode.HIDE_STATUS_BAR:
        void mainWindow.setWindowLayoutFullScreen(false);
        void mainWindow.setWindowSystemBarEnable(['navigation']);
        break;
      case DisplayMode.HIDE_NAVIGATION_BAR:
        void mainWindow.setWindowLayoutFullScreen(false);
        void mainWindow.setWindowSystemBarEnable(['status']);
        break;
      case DisplayMode.IMMERSIVE_WITH_BARS:
        void mainWindow.setWindowLayoutFullScreen(true);
        void mainWindow.setWindowSystemBarEnable(['status', 'navigation']);
        WindowManager.setTransparentSystemBar(mainWindow);
        break;
      case DisplayMode.STATUS_SAFE_BOTTOM_IMMERSIVE:
        void mainWindow.setWindowLayoutFullScreen(true);
        void mainWindow.setWindowSystemBarEnable(['status', 'navigation']);
        WindowManager.setNormalSystemBar(mainWindow);
        break;
      case DisplayMode.DEFAULT:
      default:
        void mainWindow.setWindowLayoutFullScreen(false);
        void mainWindow.setWindowSystemBarEnable(['status', 'navigation']);
        WindowManager.setDefaultSystemBar(mainWindow);
        break;
    }
    WindowManager.refreshStoredSystemBarHeightsAfterModeChange(mainWindow);
  }

  static reapplyCurrentDisplayMode(delayMs: number = 0): void {
    const apply = (): void => {
      const mainWindow = WindowManager.getMainWindowFromWindowStageRef();
      if (!mainWindow) {
        return;
      }

      WindowManager.registerThemeChangeMonitor(mainWindow);
      WindowManager.storeSystemBarHeights(mainWindow);
      logger.info(WindowManager.TAG, `Reapplying display mode after foreground: ${WindowManager.currentMode}`);
      WindowManager.applyDisplayModeWithMainWindow(mainWindow, WindowManager.currentMode);
    };

    if (delayMs > 0) {
      setTimeout(() => {
        apply();
      }, delayMs);
      return;
    }

    apply();
  }

  static dispose(): void {
    void WindowManager.closeAppFloatingWindow('WindowManager销毁');
    WindowManager.clearManagedDisplayTransitionTimers();
    WindowManager.initializeTransitionOverlayState();
    AppStorage.setOrCreate(WindowManager.TRANSITION_OVERLAY_OPACITY_KEY, 0);
    AppStorage.setOrCreate(WindowManager.TRANSITION_OVERLAY_VISIBLE_KEY, false);
    WindowManager.unregisterThemeChangeMonitor();
    WindowManager.unregisterWindowStageStateMonitor();
  }
}
