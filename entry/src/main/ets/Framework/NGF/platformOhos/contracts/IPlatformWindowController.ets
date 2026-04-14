export enum NGFDisplayMode {
  DEFAULT = 'default',
  FULL_IMMERSIVE = 'full_immersive',
  IMMERSIVE_WITH_BARS = 'immersive_with_bars',
  STATUS_SAFE_BOTTOM_IMMERSIVE = 'status_safe_bottom_immersive'
}

export interface IPlatformWindowController {
  setDisplayMode(mode: NGFDisplayMode): void;
  getCurrentDisplayMode(): NGFDisplayMode;
  reapplyCurrentDisplayMode(delayMs: number): void;
}
