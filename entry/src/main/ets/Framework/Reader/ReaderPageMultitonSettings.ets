import { SettingsManager, SettingKeys } from 'manxia_core/src/main/ets/Framework/Managers/SettingsManager';

export function isReaderPageMultitonEnabled(): boolean {
  return SettingsManager.getInstance().getBoolean(SettingKeys.READER_PAGE_MULTITON_ENABLED, true);
}
