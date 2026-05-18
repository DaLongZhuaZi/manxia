/**
 * 局域网传书配置管理器
 */

import { logger } from '../../Utils/Logger';
import { SettingKeys, SettingsManager } from './SettingsManager';
import {
  TransferConfig,
  cloneTransferConfig,
  createDefaultTransferConfig,
  sanitizeTransferConfig
} from '../../Models/TransferModels';

const TAG = 'TransferConfigManager';

export class TransferConfigManager {
  private static instance: TransferConfigManager;
  private settingsManager: SettingsManager = SettingsManager.getInstance();

  private constructor() {}

  public static getInstance(): TransferConfigManager {
    if (!TransferConfigManager.instance) {
      TransferConfigManager.instance = new TransferConfigManager();
    }
    return TransferConfigManager.instance;
  }

  public getConfig(): TransferConfig {
    const defaults = createDefaultTransferConfig();
    const config: TransferConfig = {
      port: this.settingsManager.getNumber(SettingKeys.LAN_TRANSFER_PORT, defaults.port),
      autoStopMinutes: this.settingsManager.getNumber(
        SettingKeys.LAN_TRANSFER_AUTO_STOP_MINUTES,
        defaults.autoStopMinutes
      ),
      maxFileSizeMb: this.settingsManager.getNumber(
        SettingKeys.LAN_TRANSFER_MAX_FILE_SIZE_MB,
        defaults.maxFileSizeMb
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
    return sanitizeTransferConfig(config);
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
      `局域网传书配置已保存: 端口=${normalized.port}, 自动停止=${normalized.autoStopMinutes}分钟, 文件上限=${normalized.maxFileSizeMb}MB`
    );
  }

  public async resetToDefaults(): Promise<void> {
    await this.saveConfig(createDefaultTransferConfig());
  }

  public getConfigSummary(config?: TransferConfig): string {
    const targetConfig = config ? cloneTransferConfig(config) : this.getConfig();
    const wsStatus = targetConfig.wsEnabled ? '开启' : '关闭';
    const backgroundStatus = targetConfig.allowBackgroundTransfer ? '允许' : '关闭';
    return `HTTP ${targetConfig.port} / 自动停止 ${targetConfig.autoStopMinutes} 分钟 / 文件上限 ${targetConfig.maxFileSizeMb} MB / 后台 ${backgroundStatus} / WS ${wsStatus}`;
  }
}

export function getTransferConfigManager(): TransferConfigManager {
  return TransferConfigManager.getInstance();
}
