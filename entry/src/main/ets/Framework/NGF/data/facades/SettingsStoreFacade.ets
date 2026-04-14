import { logger } from '../../../../Utils/Logger';
import { SettingsManager } from '../../../Managers/SettingsManager';
import { ISettingsStore } from '../contracts/ISettingsStore';

const TAG = 'NGFSettingsStoreFacade';

export class SettingsStoreFacade implements ISettingsStore {
  private readonly settingsManager: SettingsManager = SettingsManager.getInstance();

  getString(key: string, defaultValue: string): string {
    return this.settingsManager.getString(key, defaultValue);
  }

  getNumber(key: string, defaultValue: number): number {
    return this.settingsManager.getNumber(key, defaultValue);
  }

  getBoolean(key: string, defaultValue: boolean): boolean {
    return this.settingsManager.getBoolean(key, defaultValue);
  }

  setString(key: string, value: string): void {
    void this.persistString(key, value);
  }

  setNumber(key: string, value: number): void {
    void this.persistNumber(key, value);
  }

  setBoolean(key: string, value: boolean): void {
    void this.persistBoolean(key, value);
  }

  private async persistString(key: string, value: string): Promise<void> {
    try {
      await this.settingsManager.setString(key, value);
    } catch {
      logger.warn(TAG, `设置字符串失败: key=${key}`);
    }
  }

  private async persistNumber(key: string, value: number): Promise<void> {
    try {
      await this.settingsManager.setNumber(key, value);
    } catch {
      logger.warn(TAG, `设置数字失败: key=${key}`);
    }
  }

  private async persistBoolean(key: string, value: boolean): Promise<void> {
    try {
      await this.settingsManager.setBoolean(key, value);
    } catch {
      logger.warn(TAG, `设置布尔失败: key=${key}`);
    }
  }
}

export const ngfSettingsStoreFacade = new SettingsStoreFacade();
