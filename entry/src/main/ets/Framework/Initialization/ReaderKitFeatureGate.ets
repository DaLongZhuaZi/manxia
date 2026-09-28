/**
 * ReaderKit 能力开关。
 * 默认启用，可通过 SettingsManager 持久化控制。
 * 模拟器上强制关闭，但不写入持久化设置，避免影响真机。
 */
import { deviceInfo } from '@kit.BasicServicesKit';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { SettingKeys, SettingsManager } from 'manxia_core/src/main/ets/Framework/Managers/SettingsManager';

const TAG = 'ReaderKitFeatureGate';

interface ReaderKitRuntimeGateState {
  initialized: boolean;
  forceDisabled: boolean;
  disableReason: string;
  productModel: string;
}

const runtimeGateState: ReaderKitRuntimeGateState = {
  initialized: false,
  forceDisabled: false,
  disableReason: '',
  productModel: ''
};

export function initializeReaderKitRuntimeGate(trigger: string): void {
  if (runtimeGateState.initialized) {
    return;
  }

  runtimeGateState.initialized = true;
  try {
    runtimeGateState.productModel = normalizeDeviceInfoValue(deviceInfo.productModel);
  } catch (error) {
    runtimeGateState.productModel = '';
    logger.warn(TAG, `ReaderKit 运行环境检查失败，保持默认开关: trigger=${trigger}, error=${String(error)}`);
    return;
  }

  if (isEmulatorDeviceModel(runtimeGateState.productModel)) {
    runtimeGateState.forceDisabled = true;
    runtimeGateState.disableReason = 'emulator_device';
    logger.warn(TAG, `ReaderKit 已在模拟器环境强制关闭: trigger=${trigger}, productModel=${runtimeGateState.productModel}`);
    return;
  }

  logger.info(TAG, `ReaderKit 运行环境检查通过: trigger=${trigger}, productModel=${runtimeGateState.productModel}`);
}

export function isReaderKitEnabled(): boolean {
  initializeReaderKitRuntimeGate('feature_check');
  if (runtimeGateState.forceDisabled) {
    return false;
  }

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

export function isReaderKitRuntimeForceDisabled(): boolean {
  initializeReaderKitRuntimeGate('force_disabled_check');
  return runtimeGateState.forceDisabled;
}

export function getReaderKitRuntimeDisabledReason(): string {
  initializeReaderKitRuntimeGate('disabled_reason_check');
  return runtimeGateState.disableReason;
}

function normalizeDeviceInfoValue(value: string): string {
  if (!value) {
    return '';
  }
  return value.trim().toLowerCase();
}

function isEmulatorDeviceModel(productModel: string): boolean {
  return productModel === 'emulator';
}

export function isEpubWebViewEnabled(): boolean {
  try {
    const settingsManager = SettingsManager.getInstance();
    return settingsManager.getBoolean(SettingKeys.EPUB_WEBVIEW_RENDERER_ENABLED, false);
  } catch (_ignored) {
    return false;
  }
}

export async function setEpubWebViewEnabled(enabled: boolean): Promise<void> {
  try {
    const settingsManager = SettingsManager.getInstance();
    await settingsManager.setBoolean(SettingKeys.EPUB_WEBVIEW_RENDERER_ENABLED, enabled);
  } catch (_ignored) {
  }
}
