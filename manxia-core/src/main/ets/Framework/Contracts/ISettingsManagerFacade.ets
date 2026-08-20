/**
 * 设置管理器契约（Stage 6 U6-Pilot-2）
 * 实现方：entry SettingsManager（启动时经 initialize() 自注册到 SettingsManagerHolder）。
 */

export interface ISettingsManagerFacade {
  getBoolean(key: string, defaultValue?: boolean): boolean;
  getString(key: string, defaultValue?: string): string;
  getNumber(key: string, defaultValue?: number): number;
  setBoolean(key: string, value: boolean): Promise<void>;
  setString(key: string, value: string): Promise<void>;
  setNumber(key: string, value: number): Promise<void>;
  syncToAppStorage(): void;
  isInitialized(): boolean;
  initialize(): Promise<void>;
  setVisibleTabs(tabs: number[]): Promise<void>;
  setBottomBarStyle(style: string): Promise<void>;
  getVisibleTabs(): Promise<number[]>;
  getBottomBarStyle(): string;
  getJSON<T>(key: string, defaultValue: T): T;
  setJSON<T>(key: string, value: T): Promise<void>;
}

/**
 * 设置管理器持有者：core 侧单例，供上层按契约获取实现。
 */
export class SettingsManagerHolder {
  private static impl: ISettingsManagerFacade | null = null;

  static register(facade: ISettingsManagerFacade): void {
    SettingsManagerHolder.impl = facade;
  }

  static get(): ISettingsManagerFacade {
    if (!SettingsManagerHolder.impl) {
      throw new Error('SettingsManager not registered');
    }
    return SettingsManagerHolder.impl;
  }
}
