import { WindowManager, DisplayMode } from 'manxia_theme/src/main/ets/Utils/WindowManager';
import { uiContextManager } from '../../../Managers/UIContextManager';
import { IPlatformWindowController, NGFDisplayMode } from '../contracts/IPlatformWindowController';

export class PlatformWindowControllerFacade implements IPlatformWindowController {
  setDisplayMode(mode: NGFDisplayMode): void {
    const uiContext = uiContextManager.getUIContext();
    WindowManager.setDisplayMode(this.toLegacyMode(mode), uiContext ?? undefined);
  }

  getCurrentDisplayMode(): NGFDisplayMode {
    return this.toNGFMode(WindowManager.getCurrentMode());
  }

  reapplyCurrentDisplayMode(delayMs: number): void {
    WindowManager.reapplyCurrentDisplayMode(delayMs);
  }

  private toLegacyMode(mode: NGFDisplayMode): DisplayMode {
    switch (mode) {
      case NGFDisplayMode.FULL_IMMERSIVE:
        return DisplayMode.FULL_IMMERSIVE;
      case NGFDisplayMode.IMMERSIVE_WITH_BARS:
        return DisplayMode.IMMERSIVE_WITH_BARS;
      case NGFDisplayMode.STATUS_SAFE_BOTTOM_IMMERSIVE:
        return DisplayMode.STATUS_SAFE_BOTTOM_IMMERSIVE;
      case NGFDisplayMode.DEFAULT:
      default:
        return DisplayMode.DEFAULT;
    }
  }

  private toNGFMode(mode: DisplayMode): NGFDisplayMode {
    switch (mode) {
      case DisplayMode.FULL_IMMERSIVE:
        return NGFDisplayMode.FULL_IMMERSIVE;
      case DisplayMode.IMMERSIVE_WITH_BARS:
        return NGFDisplayMode.IMMERSIVE_WITH_BARS;
      case DisplayMode.STATUS_SAFE_BOTTOM_IMMERSIVE:
        return NGFDisplayMode.STATUS_SAFE_BOTTOM_IMMERSIVE;
      case DisplayMode.DEFAULT:
      case DisplayMode.HIDE_STATUS_BAR:
      case DisplayMode.HIDE_NAVIGATION_BAR:
      default:
        return NGFDisplayMode.DEFAULT;
    }
  }
}

export const ngfPlatformWindowControllerFacade = new PlatformWindowControllerFacade();
