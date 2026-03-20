/**
 * ReaderKit 能力开关。
 * 默认启用，可通过 SettingsManager 持久化控制。
 */
import { SettingKeys, SettingsManager } from '../Managers/SettingsManager';

export function isReaderKitEnabled(): boolean {
  try {
    const settingsManager = SettingsManager.getInstance();
    return settingsManager.getBoolean(SettingKeys.READER_KIT_ENABLED, true);
  } catch (_ignored) {
    return true;
  }
}

export async function setReaderKitEnabled(enabled: boolean): Promise<void> {
  try {
    const settingsManager = SettingsManager.getInstance();
    await settingsManager.setBoolean(SettingKeys.READER_KIT_ENABLED, enabled);
  } catch (_ignored) {
  }
}
