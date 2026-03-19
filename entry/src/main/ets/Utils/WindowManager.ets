// 文件路径: src/main/ets/Utils/WindowManager.ets
// 职责: 提供统一的窗口管理功能，包括各种显示模式、沉浸式显示、系统栏设置等

import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { display } from '@kit.ArkUI';
import { logger } from './Logger';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';

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

/**
 * 窗口管理器 - 基于HarmonyOS NEXT API 12最新规范
 * 提供完整的显示模式管理、沉浸式显示、系统栏设置等功能
 */
export class WindowManager {
  private static readonly TAG = 'WindowManager';
  private static currentMode: DisplayMode = DisplayMode.DEFAULT;
  private static readonly BACKGROUND_STORAGE_KEY = 'isInBackground';
  private static windowStageRef: window.WindowStage | null = null;
  private static windowStageEventCallback: ((event: window.WindowStageEventType) => void) | null = null;
  private static themeChangeCallback: ((theme: ThemeType) => void) | null = null;

  /**
   * 获取当前 Ability 的主窗口（已废弃，仅用于内部兼容）
   * ⚠️ 警告：此方法依赖globalThis，在某些情况下可能不可用
   * 推荐使用：getMainWindowFromUIContext() 或 通过 initialize() 传入的 WindowStage
   */
  private static getMainWindow(): window.Window | null {
    logger.warn(WindowManager.TAG, '⚠️ 使用了已废弃的getMainWindow()方法，推荐使用getMainWindowFromUIContext()');
    return null;
    // 注释掉不安全的globalThis访问
    // try {
    //   const context = globalThis.abilityContext as common.UIAbilityContext;
    //   if (!context || !context.windowStage) {
    //     logger.error(WindowManager.TAG, '❌ 无法获取AbilityContext或WindowStage');
    //     return null;
    //   }
    //   return context.windowStage.getMainWindowSync();
    // } catch (error) {
    //   logger.error(WindowManager.TAG, `❌ 获取主窗口失败: ${(error as Error).message}`);
    //   return null;
    // }
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
      return;
    }

    AppStorage.setOrCreate(WindowManager.BACKGROUND_STORAGE_KEY, isInBackground);
    logger.info(WindowManager.TAG, `前后台状态已更新: isInBackground=${isInBackground}, source=${source}`);
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
      case window.WindowStageEventType.INACTIVE:
      case window.WindowStageEventType.HIDDEN:
      case window.WindowStageEventType.PAUSED:
        return true;
      case window.WindowStageEventType.SHOWN:
      case window.WindowStageEventType.ACTIVE:
      case window.WindowStageEventType.RESUMED:
        return false;
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
      }).catch((err: BusinessError) => {
        logger.error(WindowManager.TAG, `❌ 专用沉浸模式系统栏设置失败: ${JSON.stringify(err)}`);
      });
    } catch (error) {
      logger.error(WindowManager.TAG, `❌ 设置专用沉浸模式异常: ${(error as Error).message}`);
    }
  }

  static setPreferredOrientationLandscape(uiContext?: UIContext): void {
    try {
      const mainWindow = uiContext ? WindowManager.getMainWindowFromUIContext(uiContext) : WindowManager.getMainWindow();
      if (!mainWindow) {
        logger.error(WindowManager.TAG, '无法获取主窗口，设置横屏失败');
        return;
      }
      const promise = mainWindow.setPreferredOrientation(window.Orientation.LANDSCAPE);
      promise.then(() => {
        logger.info(WindowManager.TAG, '已设置为横屏显示');
      }).catch((err: BusinessError) => {
        logger.error(WindowManager.TAG, `设置横屏失败: ${JSON.stringify(err)}`);
      });
    } catch (error) {
      logger.error(WindowManager.TAG, `设置横屏异常: ${(error as Error).message}`);
    }
  }

  static setPreferredOrientationAuto(uiContext?: UIContext): void {
    try {
      const mainWindow = uiContext ? WindowManager.getMainWindowFromUIContext(uiContext) : WindowManager.getMainWindow();
      if (!mainWindow) {
        logger.error(WindowManager.TAG, '无法获取主窗口，恢复自动旋转失败');
        return;
      }
      const promise = mainWindow.setPreferredOrientation(window.Orientation.AUTO_ROTATION_RESTRICTED);
      promise.then(() => {
        logger.info(WindowManager.TAG, '已恢复自动旋转');
      }).catch((err: BusinessError) => {
        logger.error(WindowManager.TAG, `恢复自动旋转失败: ${JSON.stringify(err)}`);
      });
    } catch (error) {
      logger.error(WindowManager.TAG, `恢复自动旋转异常: ${(error as Error).message}`);
    }
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
    try {
      const themeStyle = WindowManager.resolveThemeSystemBarStyle();
      const systemBarProperties: window.SystemBarProperties = {
        statusBarColor: themeStyle.backgroundColor,
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

  private static applyThemeAwareSystemBar(mainWindow: window.Window, transparentBackground: boolean): void {
    try {
      const themeStyle = WindowManager.resolveThemeSystemBarStyle();
      const barColor = transparentBackground ? '#00000000' : themeStyle.backgroundColor;
      const systemBarProperties: window.SystemBarProperties = {
        statusBarColor: barColor,
        navigationBarColor: barColor,
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
  static getCurrentMode(): DisplayMode {
    return WindowManager.currentMode;
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

      const statusBarHeight = statusBarHeightPx / density;
      const navigationBarHeight = navigationBarHeightPx / density;

      // 存储到AppStorage中供组件使用
      AppStorage.setOrCreate('statusBarHeight', statusBarHeight);
      AppStorage.setOrCreate('navigationBarHeight', navigationBarHeight);

      // 持久化存储
      PersistentStorage.persistProp('statusBarHeight', statusBarHeight);
      PersistentStorage.persistProp('navigationBarHeight', navigationBarHeight);

      logger.info(WindowManager.TAG, `📏 系统栏高度信息已存储 - 状态栏: ${statusBarHeight.toFixed(2)}vp, 导航栏: ${navigationBarHeight.toFixed(2)}vp`);

    } catch (error) {
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

  static dispose(): void {
    WindowManager.unregisterThemeChangeMonitor();
    WindowManager.unregisterWindowStageStateMonitor();
  }
}
