import { logger } from './Logger';
import { DisplayMode, WindowManager } from './WindowManager';
import { PageWindowRegistry } from './PageWindowRegistry';
import { PageWindowPolicy, PageWindowSpec } from './PageWindowPolicy';

const TAG: string = 'PageWindowCoordinator';

export class PageWindowCoordinator {
  static getPageSpec(pageName: string): PageWindowSpec | null {
    return PageWindowRegistry.getSpec(pageName);
  }

  static captureCurrentDisplayMode(): DisplayMode {
    return WindowManager.getCurrentMode();
  }

  static isManagedByMainMenu(pageName: string): boolean {
    return PageWindowRegistry.isManagedByMainMenu(pageName);
  }

  static shouldUseMainMenuReturnTransition(pageName: string): boolean {
    return PageWindowRegistry.requiresMainMenuReturnTransition(pageName);
  }

  static applyRootMainMenu(uiContext?: UIContext): void {
    PageWindowCoordinator.applyPolicy(PageWindowPolicy.ROOT_MAIN_MENU, uiContext);
  }

  static navigateWithManagedTransition(
    fromPageName: string,
    toPageName: string,
    navigate: () => void,
    uiContext?: UIContext,
    hostDisplayMode?: DisplayMode
  ): void {
    const targetMode = PageWindowCoordinator.resolveDisplayModeForPage(toPageName, hostDisplayMode);
    if (!targetMode) {
      logger.debug(TAG, `跳过托管过渡：无法解析目标窗口模式，from=${fromPageName}, to=${toPageName}`);
      navigate();
      return;
    }
    WindowManager.navigateWithManagedDisplayMode(targetMode, navigate, uiContext);
  }

  static applyPagePolicy(pageName: string, uiContext?: UIContext, hostDisplayMode?: DisplayMode): void {
    const targetMode = PageWindowCoordinator.resolveDisplayModeForPage(pageName, hostDisplayMode);
    if (!targetMode) {
      logger.debug(TAG, `页面未配置窗口模式或需要宿主模式跟随: page=${pageName}`);
      return;
    }
    if (WindowManager.getCurrentMode() === targetMode) {
      return;
    }
    WindowManager.setDisplayMode(targetMode, uiContext);
  }

  static reapplyPagePolicy(pageName: string, uiContext?: UIContext, hostDisplayMode?: DisplayMode): void {
    const targetMode = PageWindowCoordinator.resolveDisplayModeForPage(pageName, hostDisplayMode);
    if (!targetMode) {
      return;
    }
    WindowManager.setDisplayMode(targetMode, uiContext);
  }

  static restoreDisplayMode(previousMode: DisplayMode, uiContext?: UIContext): void {
    if (WindowManager.getCurrentMode() === previousMode) {
      return;
    }
    WindowManager.setDisplayMode(previousMode, uiContext);
  }

  static resolveDisplayModeForPage(pageName: string, hostDisplayMode?: DisplayMode): DisplayMode | null {
    const spec = PageWindowRegistry.getSpec(pageName);
    if (!spec) {
      return DisplayMode.DEFAULT;
    }
    return PageWindowCoordinator.resolveDisplayModeForPolicy(spec.policy, spec.fallbackDisplayMode, hostDisplayMode);
  }

  static applyPolicy(
    policy: PageWindowPolicy,
    uiContext?: UIContext,
    fallbackDisplayMode?: DisplayMode,
    hostDisplayMode?: DisplayMode
  ): void {
    const targetMode = PageWindowCoordinator.resolveDisplayModeForPolicy(policy, fallbackDisplayMode, hostDisplayMode);
    if (!targetMode) {
      return;
    }
    if (WindowManager.getCurrentMode() === targetMode) {
      return;
    }
    WindowManager.setDisplayMode(targetMode, uiContext);
  }

  private static resolveDisplayModeForPolicy(
    policy: PageWindowPolicy,
    fallbackDisplayMode?: DisplayMode,
    hostDisplayMode?: DisplayMode
  ): DisplayMode | null {
    switch (policy) {
      case PageWindowPolicy.ROOT_MAIN_MENU:
        return DisplayMode.DEFAULT;
      case PageWindowPolicy.NAV_STANDARD:
      case PageWindowPolicy.NAV_CUSTOM_HEADER:
        return DisplayMode.STATUS_SAFE_BOTTOM_IMMERSIVE;
      case PageWindowPolicy.FULLSCREEN_READER:
        return DisplayMode.FULL_IMMERSIVE;
      case PageWindowPolicy.FULLSCREEN_READER_WITH_BARS:
        return DisplayMode.IMMERSIVE_WITH_BARS;
      case PageWindowPolicy.FOLLOW_HOST:
        if (hostDisplayMode) {
          return hostDisplayMode;
        }
        return fallbackDisplayMode ?? null;
      case PageWindowPolicy.TRANSIENT_MODAL:
        return fallbackDisplayMode ?? DisplayMode.DEFAULT;
      default:
        return fallbackDisplayMode ?? DisplayMode.DEFAULT;
    }
  }
}
