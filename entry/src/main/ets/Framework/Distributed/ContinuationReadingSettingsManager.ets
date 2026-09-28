import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import {
  ContinuationReadingSettings,
  ContinuationTransferMode,
  normalizeContinuationReadingSettings,
  resolveContinuationTransferMode
} from './ContinuationReadingTypes';

const TAG = 'ContinuationReadingSettingsManager';
const PREFERENCES_NAME = 'continuation_reading_settings';
const ENABLED_KEY = 'continuationEnabled';
const READ_ONLY_ENABLED_KEY = 'readOnlyEnabled';
const IMPORT_ENABLED_KEY = 'importToLibraryEnabled';
const DEFAULT_MODE_KEY = 'defaultMode';

/**
 * 接续阅读默认开启（功能开关，不是权限开关）。
 *
 * [合规说明] 应用启动、回到前台、进入阅读器等自动检查点都不会申请「设备发现和连接」权限；
 * 该权限只在用户主动点击时申请（新手引导权限步骤、接续阅读设置页、接续失败提示卡片）。
 * 因此这里为 true 只代表"接续能力默认可用"，不构成任何强制授权要求。
 */
function createDefaultSettings(): ContinuationReadingSettings {
  return {
    enabled: true,
    readOnlyEnabled: true,
    importToLibraryEnabled: true,
    defaultMode: ContinuationTransferMode.READ_ONLY
  };
}

function normalizeMode(value: string): ContinuationTransferMode {
  if (value === ContinuationTransferMode.IMPORT_TO_LIBRARY) {
    return ContinuationTransferMode.IMPORT_TO_LIBRARY;
  }
  return ContinuationTransferMode.READ_ONLY;
}

export class ContinuationReadingSettingsManager {
  private static instance: ContinuationReadingSettingsManager | null = null;
  private settings: ContinuationReadingSettings = createDefaultSettings();
  private store: preferences.Preferences | null = null;
  private initializationPromise: Promise<void> | null = null;
  private initialized: boolean = false;

  private constructor() {}

  public static getInstance(): ContinuationReadingSettingsManager {
    if (!ContinuationReadingSettingsManager.instance) {
      ContinuationReadingSettingsManager.instance = new ContinuationReadingSettingsManager();
    }
    return ContinuationReadingSettingsManager.instance;
  }

  public async initialize(context: common.UIAbilityContext): Promise<void> {
    if (this.initialized) {
      return;
    }
    if (this.initializationPromise) {
      await this.initializationPromise;
      return;
    }
    this.initializationPromise = this.loadSettings(context);
    try {
      await this.initializationPromise;
      this.initialized = true;
    } finally {
      this.initializationPromise = null;
    }
  }

  private async loadSettings(context: common.UIAbilityContext): Promise<void> {
    const store = await preferences.getPreferences(context, PREFERENCES_NAME);
    this.store = store;
    const enabled = await store.get(ENABLED_KEY, true) as boolean;
    const readOnlyEnabled = await store.get(READ_ONLY_ENABLED_KEY, true) as boolean;
    const importToLibraryEnabled = await store.get(IMPORT_ENABLED_KEY, true) as boolean;
    const rawMode = await store.get(DEFAULT_MODE_KEY, ContinuationTransferMode.READ_ONLY) as string;
    const loaded: ContinuationReadingSettings = {
      enabled: enabled,
      readOnlyEnabled: readOnlyEnabled,
      importToLibraryEnabled: importToLibraryEnabled,
      defaultMode: normalizeMode(rawMode)
    };
    this.settings = this.normalizeSettings(loaded);
    logger.info(
      TAG,
      `接续设置已加载: enabled=${this.settings.enabled}, readOnly=${this.settings.readOnlyEnabled}, import=${this.settings.importToLibraryEnabled}, default=${this.settings.defaultMode}`
    );
  }

  public getSnapshot(): ContinuationReadingSettings {
    return {
      enabled: this.settings.enabled,
      readOnlyEnabled: this.settings.readOnlyEnabled,
      importToLibraryEnabled: this.settings.importToLibraryEnabled,
      defaultMode: this.settings.defaultMode
    };
  }

  /**
   * 接续阅读总开关是否开启。
   * 关闭后：不显示系统接续入口、不进入接续流转、不再申请「设备发现和连接」权限，
   * 但不影响应用其他任何功能，也不清理既有接续缓存。
   */
  public isContinuationEnabled(): boolean {
    return this.settings.enabled;
  }

  /**
   * 设置接续阅读总开关（由「设置 → 接续阅读」页面的开关调用）。
   */
  public async setContinuationEnabled(enabled: boolean): Promise<void> {
    if (this.settings.enabled === enabled) {
      return;
    }
    const next = this.getSnapshot();
    next.enabled = enabled;
    this.settings = this.normalizeSettings(next);
    await this.persistSettings();
  }

  public getEffectiveMode(): ContinuationTransferMode {
    return resolveContinuationTransferMode(this.settings);
  }

  public async setModeEnabled(mode: ContinuationTransferMode, enabled: boolean): Promise<void> {
    const next = this.getSnapshot();
    if (mode === ContinuationTransferMode.READ_ONLY) {
      next.readOnlyEnabled = enabled;
    } else if (mode === ContinuationTransferMode.IMPORT_TO_LIBRARY) {
      next.importToLibraryEnabled = enabled;
    }
    this.settings = this.normalizeSettings(next);
    await this.persistSettings();
  }

  public async setDefaultMode(mode: ContinuationTransferMode): Promise<void> {
    if (mode === ContinuationTransferMode.DISABLED) {
      return;
    }
    const next = this.getSnapshot();
    next.defaultMode = mode;
    if (mode === ContinuationTransferMode.READ_ONLY) {
      next.readOnlyEnabled = true;
    } else {
      next.importToLibraryEnabled = true;
    }
    this.settings = this.normalizeSettings(next);
    await this.persistSettings();
  }

  public isModeEnabled(mode: ContinuationTransferMode): boolean {
    if (!this.settings.enabled) {
      return false;
    }
    if (mode === ContinuationTransferMode.READ_ONLY) {
      return this.settings.readOnlyEnabled;
    }
    if (mode === ContinuationTransferMode.IMPORT_TO_LIBRARY) {
      return this.settings.importToLibraryEnabled;
    }
    return false;
  }

  private normalizeSettings(settings: ContinuationReadingSettings): ContinuationReadingSettings {
    return normalizeContinuationReadingSettings(settings);
  }

  private async persistSettings(): Promise<void> {
    const store = this.store;
    if (!store) {
      return;
    }
    await store.put(ENABLED_KEY, this.settings.enabled);
    await store.put(READ_ONLY_ENABLED_KEY, this.settings.readOnlyEnabled);
    await store.put(IMPORT_ENABLED_KEY, this.settings.importToLibraryEnabled);
    await store.put(DEFAULT_MODE_KEY, this.settings.defaultMode);
    await store.flush();
    logger.info(
      TAG,
      `接续设置已更新: enabled=${this.settings.enabled}, readOnly=${this.settings.readOnlyEnabled}, import=${this.settings.importToLibraryEnabled}, default=${this.settings.defaultMode}`
    );
  }
}
