import { SettingsManager, SettingKeys } from '../Managers/SettingsManager';

export function isReaderPageMultitonEnabled(): boolean {
  return SettingsManager.getInstance().getBoolean(SettingKeys.READER_PAGE_MULTITON_ENABLED, true);
}
