import { DisplayMode } from './WindowManager';

export enum PageWindowPolicy {
  ROOT_MAIN_MENU = 'root_main_menu',
  NAV_STANDARD = 'nav_standard',
  NAV_CUSTOM_HEADER = 'nav_custom_header',
  FULLSCREEN_READER = 'fullscreen_reader',
  FULLSCREEN_READER_WITH_BARS = 'fullscreen_reader_with_bars',
  FOLLOW_HOST = 'follow_host',
  TRANSIENT_MODAL = 'transient_modal'
}

export enum PageTitleBarMode {
  SYSTEM = 'system',
  CUSTOM = 'custom',
  HIDDEN = 'hidden'
}

export enum PageSafeAreaContract {
  SYSTEM_TITLEBAR = 'system_titlebar',
  CUSTOM_HEADER = 'custom_header',
  FULLSCREEN = 'fullscreen',
  FOLLOW_HOST = 'follow_host'
}

export interface PageWindowSpec {
  pageName: string;
  policy: PageWindowPolicy;
  managedByMainMenu: boolean;
  titleBarMode: PageTitleBarMode;
  safeAreaContract: PageSafeAreaContract;
  requiresMainMenuReturnTransition: boolean;
  fallbackDisplayMode?: DisplayMode;
}
