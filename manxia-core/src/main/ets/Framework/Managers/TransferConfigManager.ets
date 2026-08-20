/**
 * 局域网传书配置管理器
 */

import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { ISettingsManagerFacade, SettingsManagerHolder } from 'manxia_core/src/main/ets/Framework/Contracts/ISettingsManagerFacade';
import { SettingKeys } from 'manxia_core/src/main/ets/Framework/Contracts/SettingKeys';
import {
  TransferConfig,
  cloneTransferConfig,
  createDefaultTransferConfig,
  sanitizeTransferConfig
} from 'manxia_core/src/main/ets/Models/TransferModels';

const TAG = 'TransferConfigManager';

export class TransferConfigManager {
  private static instance: TransferConfigManager;
  private get settingsManager(): ISettingsManagerFacade { return SettingsManagerHolder.get(); }

  private constructor() {}

  public static getInstance(): TransferConfigManager {
    if (!TransferConfigManager.instance) {
      TransferConfigManager.instance = new TransferConfigManager();
    }
    return TransferConfigManager.instance;
  }

  public getConfig(): TransferConfig {
    const defaults = createDefaultTransferConfig();
    const persistedConfig: TransferConfig = {
      port: this.settingsManager.getNumber(SettingKeys.LAN_TRANSFER_PORT, defaults.port),
      autoStopMinutes: this.settingsManager.getNumber(
        SettingKeys.LAN_TRANSFER_AUTO_STOP_MINUTES,
        defaults.autoStopMinutes
      ),
      maxFileSizeMb: this.settingsManager.getNumber(
        SettingKeys.LAN_TRANSFER_MAX_FILE_SIZE_MB,
        defaults.maxFileSizeMb
      ),
      maxTotalSizeMb: this.settingsManager.getNumber(
        SettingKeys.LAN_TRANSFER_MAX_TOTAL_SIZE_MB,
        defaults.maxTotalSizeMb
      ),
      allowBackgroundTransfer: this.settingsManager.getBoolean(
        SettingKeys.LAN_TRANSFER_ALLOW_BACKGROUND_TRANSFER,
        defaults.allowBackgroundTransfer
      ),
      wsEnabled: this.settingsManager.getBoolean(
        SettingKeys.LAN_TRANSFER_WS_ENABLED,
        defaults.wsEnabled
      )
    };
    const upgradedConfig = this.upgradeLegacyCapacityDefaults(persistedConfig, defaults);
    return sanitizeTransferConfig(upgradedConfig);
  }

  public async saveConfig(config: TransferConfig): Promise<void> {
    const normalized = sanitizeTransferConfig(config);
    await this.settingsManager.setNumber(SettingKeys.LAN_TRANSFER_PORT, normalized.port);
    await this.settingsManager.setNumber(
      SettingKeys.LAN_TRANSFER_AUTO_STOP_MINUTES,
      normalized.autoStopMinutes
    );
    await this.settingsManager.setNumber(
      SettingKeys.LAN_TRANSFER_MAX_FILE_SIZE_MB,
      normalized.maxFileSizeMb
    );
    await this.settingsManager.setNumber(
      SettingKeys.LAN_TRANSFER_MAX_TOTAL_SIZE_MB,
      normalized.maxTotalSizeMb
    );
    await this.settingsManager.setBoolean(
      SettingKeys.LAN_TRANSFER_ALLOW_BACKGROUND_TRANSFER,
      normalized.allowBackgroundTransfer
    );
    await this.settingsManager.setBoolean(
      SettingKeys.LAN_TRANSFER_WS_ENABLED,
      normalized.wsEnabled
    );
    logger.info(
      TAG,
      `局域网传书配置已保存: 端口=${normalized.port}, 自动停止=${normalized.autoStopMinutes}分钟, 单文件上限=${normalized.maxFileSizeMb}MB, 总量上限=${normalized.maxTotalSizeMb}MB`
    );
  }

  public async resetToDefaults(): Promise<void> {
    await this.saveConfig(createDefaultTransferConfig());
  }

  public getConfigSummary(config?: TransferConfig): string {
    const targetConfig = config ? cloneTransferConfig(config) : this.getConfig();
    const wsStatus = targetConfig.wsEnabled ? '开启' : '关闭';
    const backgroundStatus = targetConfig.allowBackgroundTransfer ? '允许' : '关闭';
    return `HTTP ${targetConfig.port} / 自动停止 ${targetConfig.autoStopMinutes} 分钟 / 单文件 ${targetConfig.maxFileSizeMb} MB / 总量 ${targetConfig.maxTotalSizeMb} MB / 后台 ${backgroundStatus} / WS ${wsStatus}`;
  }

  private upgradeLegacyCapacityDefaults(config: TransferConfig, defaults: TransferConfig): TransferConfig {
    let maxFileSizeMb = config.maxFileSizeMb;
    let maxTotalSizeMb = config.maxTotalSizeMb;
    if (maxFileSizeMb === 2048 || maxFileSizeMb === 5120) {
      maxFileSizeMb = defaults.maxFileSizeMb;
    }
    if (maxTotalSizeMb === 20480) {
      maxTotalSizeMb = defaults.maxTotalSizeMb;
    }
    const upgradedConfig: TransferConfig = {
      port: config.port,
      autoStopMinutes: config.autoStopMinutes,
      maxFileSizeMb: maxFileSizeMb,
      maxTotalSizeMb: maxTotalSizeMb,
      allowBackgroundTransfer: config.allowBackgroundTransfer,
      wsEnabled: config.wsEnabled
    };
    return upgradedConfig;
  }
}

export function getTransferConfigManager(): TransferConfigManager {
  return TransferConfigManager.getInstance();
}
