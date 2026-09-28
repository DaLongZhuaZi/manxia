/**
 * Visual effects manager
 * - Detects material capability via `hdsMaterial`
 * - Stores adaptive/manual material strategy
 * - Syncs the current visual-effects state into AppStorage
 */

import { hdsMaterial } from '@kit.UIDesignKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { logger } from '../../Utils/Logger';
import { ISettingsManagerFacade, SettingsManagerHolder } from '../Contracts/ISettingsManagerFacade';
import { SettingKeys } from '../Contracts/SettingKeys';

const TAG = 'VisualEffectsManager';

export enum VisualEffectsMaterialMode {
  ADAPTIVE = 'adaptive',
  MANUAL = 'manual'
}

export interface VisualEffectsCapability {
  supportedMaterialTypes: Array<hdsMaterial.MaterialType>;
  supportsImmersiveMaterial: boolean;
  supportsAdaptiveMaterial: boolean;
  availableManualLevels: Array<hdsMaterial.MaterialLevel>;
  recommendedManualLevel: hdsMaterial.MaterialLevel;
  lastCheckedAt: number;
  detectError: string;
}

export interface VisualEffectsSettings {
  materialMode: VisualEffectsMaterialMode;
  manualMaterialLevel: hdsMaterial.MaterialLevel;
}

export interface VisualEffectsState {
  capability: VisualEffectsCapability;
  settings: VisualEffectsSettings;
  effectiveMaterialLevel: hdsMaterial.MaterialLevel;
}

export type VisualEffectsStateListener = (state: VisualEffectsState) => void;

const DEFAULT_VISUAL_EFFECTS_CAPABILITY: VisualEffectsCapability = {
  supportedMaterialTypes: [hdsMaterial.MaterialType.ADAPTIVE],
  supportsImmersiveMaterial: false,
  supportsAdaptiveMaterial: true,
  availableManualLevels: [hdsMaterial.MaterialLevel.SMOOTH],
  recommendedManualLevel: hdsMaterial.MaterialLevel.SMOOTH,
  lastCheckedAt: 0,
  detectError: ''
};

const DEFAULT_VISUAL_EFFECTS_SETTINGS: VisualEffectsSettings = {
  materialMode: VisualEffectsMaterialMode.ADAPTIVE,
  manualMaterialLevel: hdsMaterial.MaterialLevel.SMOOTH
};

export class VisualEffectsManager {
  private static instance: VisualEffectsManager | null = null;

  private get settingsManager(): ISettingsManagerFacade { return SettingsManagerHolder.get(); }
  private currentState: VisualEffectsState = this.createDefaultState();
  private listeners: Set<VisualEffectsStateListener> = new Set();
  private initialized: boolean = false;

  private constructor() {}

  public static getInstance(): VisualEffectsManager {
    if (!VisualEffectsManager.instance) {
      VisualEffectsManager.instance = new VisualEffectsManager();
    }
    return VisualEffectsManager.instance;
  }

  public async initialize(): Promise<void> {
    if (this.initialized) {
      return;
    }

    const hasPersistedCapability = this.loadCapabilityFromStorage();
    let capabilityPersistNeeded = false;

    if (!hasPersistedCapability) {
      await this.refreshCapabilityInternal();
      capabilityPersistNeeded = true;
    }

    const normalized = this.loadSettingsFromStorage();
    this.recalculateEffectiveMaterialLevel();

    if (capabilityPersistNeeded) {
      await this.persistCapability();
    }

    if (normalized) {
      await this.persistSettings();
    }

    this.syncStateToAppStorage();
    this.initialized = true;
    logger.info(
      TAG,
      `Initialized visual effects manager: mode=${this.currentState.settings.materialMode}, effective=${this.currentState.effectiveMaterialLevel}, capabilitySource=${hasPersistedCapability ? 'storage' : 'system'}`
    );
  }

  public async refreshCapability(): Promise<void> {
    await this.refreshCapabilityInternal();
    const normalized = this.sanitizeSettingsByCapability();
    this.recalculateEffectiveMaterialLevel();
    await this.persistCapability();

    if (normalized) {
      await this.persistSettings();
    }

    this.syncStateToAppStorage();
    this.notifyListeners();
  }

  public getState(): VisualEffectsState {
    return this.copyState(this.currentState);
  }

  public isInitialized(): boolean {
    return this.initialized;
  }

  public async setMaterialMode(mode: VisualEffectsMaterialMode): Promise<void> {
    const normalizedMode = this.normalizeMaterialMode(mode);
    if (normalizedMode === this.currentState.settings.materialMode) {
      return;
    }

    this.currentState.settings.materialMode = normalizedMode;
    this.recalculateEffectiveMaterialLevel();
    await this.persistSettings();
    this.syncStateToAppStorage();
    this.notifyListeners();
    logger.info(TAG, `Updated material mode: ${normalizedMode}`);
  }

  public async setManualMaterialLevel(level: hdsMaterial.MaterialLevel): Promise<void> {
    const normalizedLevel = this.normalizeManualMaterialLevel(level);
    if (normalizedLevel === this.currentState.settings.manualMaterialLevel) {
      return;
    }

    this.currentState.settings.manualMaterialLevel = normalizedLevel;
    this.recalculateEffectiveMaterialLevel();
    await this.persistSettings();
    this.syncStateToAppStorage();
    this.notifyListeners();
    logger.info(TAG, `Updated manual material level: ${normalizedLevel}`);
  }

  public async resetToRecommended(): Promise<void> {
    this.currentState.settings.materialMode = DEFAULT_VISUAL_EFFECTS_SETTINGS.materialMode;
    this.currentState.settings.manualMaterialLevel = this.currentState.capability.recommendedManualLevel;
    this.recalculateEffectiveMaterialLevel();
    await this.persistSettings();
    this.syncStateToAppStorage();
    this.notifyListeners();
    logger.info(TAG, 'Reset visual effects settings to recommended defaults');
  }

  public addListener(listener: VisualEffectsStateListener): void {
    this.listeners.add(listener);
  }

  public removeListener(listener: VisualEffectsStateListener): void {
    this.listeners.delete(listener);
  }

  public getMaterialTypeLabel(type: hdsMaterial.MaterialType): string {
    switch (type) {
      case hdsMaterial.MaterialType.NONE:
        return 'NONE（无材质）';
      case hdsMaterial.MaterialType.ADAPTIVE:
        return 'ADAPTIVE（系统自适应）';
      case hdsMaterial.MaterialType.IMMERSIVE:
        return 'IMMERSIVE（沉浸式）';
      default:
        return `未知类型(${type})`;
    }
  }

  public getMaterialLevelLabel(level: hdsMaterial.MaterialLevel): string {
    switch (level) {
      case hdsMaterial.MaterialLevel.EXQUISITE:
        return 'EXQUISITE（精美）';
      case hdsMaterial.MaterialLevel.GENTLE:
        return 'GENTLE（轻柔）';
      case hdsMaterial.MaterialLevel.SMOOTH:
        return 'SMOOTH（流畅）';
      case hdsMaterial.MaterialLevel.ADAPTIVE:
        return 'ADAPTIVE（系统自适应）';
      default:
        return `未知等级(${level})`;
    }
  }

  public getMaterialModeLabel(mode: VisualEffectsMaterialMode): string {
    return mode === VisualEffectsMaterialMode.MANUAL ? '手动固定档位' : '系统自适应（推荐）';
  }

  private createDefaultState(): VisualEffectsState {
    return {
      capability: this.copyCapability(DEFAULT_VISUAL_EFFECTS_CAPABILITY),
      settings: this.copySettings(DEFAULT_VISUAL_EFFECTS_SETTINGS),
      effectiveMaterialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
    };
  }

  private copyState(source: VisualEffectsState): VisualEffectsState {
    return {
      capability: this.copyCapability(source.capability),
      settings: this.copySettings(source.settings),
      effectiveMaterialLevel: source.effectiveMaterialLevel
    };
  }

  private copyCapability(source: VisualEffectsCapability): VisualEffectsCapability {
    return {
      supportedMaterialTypes: source.supportedMaterialTypes.slice(),
      supportsImmersiveMaterial: source.supportsImmersiveMaterial,
      supportsAdaptiveMaterial: source.supportsAdaptiveMaterial,
      availableManualLevels: source.availableManualLevels.slice(),
      recommendedManualLevel: source.recommendedManualLevel,
      lastCheckedAt: source.lastCheckedAt,
      detectError: source.detectError
    };
  }

  private copySettings(source: VisualEffectsSettings): VisualEffectsSettings {
    return {
      materialMode: source.materialMode,
      manualMaterialLevel: source.manualMaterialLevel
    };
  }

  private createCapability(
    materialTypes: Array<hdsMaterial.MaterialType>,
    checkedAt: number,
    detectError: string
  ): VisualEffectsCapability {
    const normalizedTypes = this.normalizeMaterialTypes(materialTypes);
    const supportsImmersive = this.hasMaterialType(normalizedTypes, hdsMaterial.MaterialType.IMMERSIVE);
    const supportsAdaptive = this.hasMaterialType(normalizedTypes, hdsMaterial.MaterialType.ADAPTIVE);
    const availableManualLevels = this.buildAvailableManualLevels(supportsImmersive);
    const recommendedManualLevel = supportsImmersive
      ? hdsMaterial.MaterialLevel.GENTLE
      : hdsMaterial.MaterialLevel.SMOOTH;

    return {
      supportedMaterialTypes: normalizedTypes,
      supportsImmersiveMaterial: supportsImmersive,
      supportsAdaptiveMaterial: supportsAdaptive,
      availableManualLevels,
      recommendedManualLevel,
      lastCheckedAt: checkedAt,
      detectError
    };
  }

  private async refreshCapabilityInternal(): Promise<void> {
    const checkedAt = Date.now();
    try {
      const queriedTypes = hdsMaterial.getSystemMaterialTypes();
      const normalizedTypes = this.normalizeMaterialTypes(queriedTypes);
      const capability = this.createCapability(normalizedTypes, checkedAt, '');
      this.currentState.capability = capability;
      logger.info(
        TAG,
        `Capability detected: supportsImmersive=${capability.supportsImmersiveMaterial}, supportsAdaptive=${capability.supportsAdaptiveMaterial}, types=${JSON.stringify(normalizedTypes)}`
      );
    } catch (error) {
      const businessError = error as BusinessError;
      const code = typeof businessError.code === 'number' ? businessError.code : -1;
      const message = typeof businessError.message === 'string' ? businessError.message : String(error);
      const detectError = `code=${code}, message=${message}`;
      const hasPreviousCapability = this.currentState.capability.lastCheckedAt > 0;
      const fallbackTypes = hasPreviousCapability
        ? this.currentState.capability.supportedMaterialTypes.slice()
        : DEFAULT_VISUAL_EFFECTS_CAPABILITY.supportedMaterialTypes.slice();

      this.currentState.capability = this.createCapability(fallbackTypes, checkedAt, detectError);
      logger.warn(
        TAG,
        `Capability detection failed, ${hasPreviousCapability ? 'preserved previous capability snapshot' : 'fallback to conservative defaults'}: ${detectError}`
      );
    }
  }

  private normalizeMaterialTypes(types: Array<hdsMaterial.MaterialType>): Array<hdsMaterial.MaterialType> {
    const uniqueTypes: Array<hdsMaterial.MaterialType> = [];
    types.forEach((type: hdsMaterial.MaterialType) => {
      if (!uniqueTypes.some((item: hdsMaterial.MaterialType) => item === type)) {
        uniqueTypes.push(type);
      }
    });

    if (uniqueTypes.length === 0) {
      uniqueTypes.push(hdsMaterial.MaterialType.ADAPTIVE);
    }

    return uniqueTypes;
  }

  private hasMaterialType(
    types: Array<hdsMaterial.MaterialType>,
    target: hdsMaterial.MaterialType
  ): boolean {
    return types.some((item: hdsMaterial.MaterialType) => item === target);
  }

  private buildAvailableManualLevels(supportsImmersive: boolean): Array<hdsMaterial.MaterialLevel> {
    if (supportsImmersive) {
      return [
        hdsMaterial.MaterialLevel.EXQUISITE,
        hdsMaterial.MaterialLevel.GENTLE,
        hdsMaterial.MaterialLevel.SMOOTH
      ];
    }

    return [hdsMaterial.MaterialLevel.SMOOTH];
  }

  private loadCapabilityFromStorage(): boolean {
    const rawMaterialTypes = this.settingsManager.getString(
      SettingKeys.VISUAL_EFFECTS_SUPPORTED_MATERIAL_TYPES,
      ''
    );
    const checkedAt = this.settingsManager.getNumber(
      SettingKeys.VISUAL_EFFECTS_CAPABILITY_LAST_CHECKED_AT,
      0
    );
    const detectError = this.settingsManager.getString(
      SettingKeys.VISUAL_EFFECTS_CAPABILITY_DETECT_ERROR,
      ''
    );
    const hasPersistedCapability = rawMaterialTypes.length > 0 || checkedAt > 0 || detectError.length > 0;

    if (!hasPersistedCapability) {
      return false;
    }

    const materialTypes = this.parsePersistedMaterialTypes(rawMaterialTypes);
    const normalizedTypes = materialTypes.length > 0
      ? materialTypes
      : DEFAULT_VISUAL_EFFECTS_CAPABILITY.supportedMaterialTypes.slice();

    this.currentState.capability = this.createCapability(normalizedTypes, checkedAt, detectError);
    logger.info(
      TAG,
      `Loaded persisted material capability snapshot: checkedAt=${checkedAt}, hasError=${detectError.length > 0}, types=${JSON.stringify(normalizedTypes)}`
    );
    return true;
  }

  private loadSettingsFromStorage(): boolean {
    let normalized = false;

    const modeFromStorage = this.settingsManager.getString(
      SettingKeys.VISUAL_EFFECTS_MATERIAL_MODE,
      DEFAULT_VISUAL_EFFECTS_SETTINGS.materialMode
    );
    const manualLevelFromStorage = this.settingsManager.getNumber(
      SettingKeys.VISUAL_EFFECTS_MANUAL_MATERIAL_LEVEL,
      DEFAULT_VISUAL_EFFECTS_SETTINGS.manualMaterialLevel
    );

    const mode = this.parseMaterialMode(modeFromStorage);
    const manualLevel = this.parseMaterialLevel(manualLevelFromStorage);

    if (modeFromStorage !== mode) {
      normalized = true;
    }
    if (manualLevelFromStorage !== manualLevel) {
      normalized = true;
    }

    this.currentState.settings = {
      materialMode: mode,
      manualMaterialLevel: manualLevel
    };

    if (this.sanitizeSettingsByCapability()) {
      normalized = true;
    }

    return normalized;
  }

  private sanitizeSettingsByCapability(): boolean {
    const normalizedManualLevel = this.normalizeManualMaterialLevel(this.currentState.settings.manualMaterialLevel);
    if (normalizedManualLevel !== this.currentState.settings.manualMaterialLevel) {
      this.currentState.settings.manualMaterialLevel = normalizedManualLevel;
      return true;
    }

    return false;
  }

  private normalizeManualMaterialLevel(level: hdsMaterial.MaterialLevel): hdsMaterial.MaterialLevel {
    if (this.currentState.capability.availableManualLevels.some((item: hdsMaterial.MaterialLevel) => item === level)) {
      return level;
    }

    return this.currentState.capability.recommendedManualLevel;
  }

  private parseMaterialMode(raw: string): VisualEffectsMaterialMode {
    return raw === VisualEffectsMaterialMode.MANUAL
      ? VisualEffectsMaterialMode.MANUAL
      : VisualEffectsMaterialMode.ADAPTIVE;
  }

  private normalizeMaterialMode(mode: VisualEffectsMaterialMode): VisualEffectsMaterialMode {
    return mode === VisualEffectsMaterialMode.MANUAL
      ? VisualEffectsMaterialMode.MANUAL
      : VisualEffectsMaterialMode.ADAPTIVE;
  }

  private parsePersistedMaterialTypes(raw: string): Array<hdsMaterial.MaterialType> {
    const parsedTypes: Array<hdsMaterial.MaterialType> = [];
    if (raw.length === 0) {
      return parsedTypes;
    }

    raw.split(',').forEach((segment: string) => {
      this.appendPersistedMaterialType(segment, parsedTypes);
    });
    return this.normalizeMaterialTypes(parsedTypes);
  }

  private appendPersistedMaterialType(
    rawValue: string,
    target: Array<hdsMaterial.MaterialType>
  ): void {
    const trimmed = rawValue.trim();
    if (trimmed.length === 0) {
      return;
    }

    const numericValue = Number(trimmed);
    if (Number.isNaN(numericValue)) {
      return;
    }

    switch (numericValue) {
      case hdsMaterial.MaterialType.NONE:
        target.push(hdsMaterial.MaterialType.NONE);
        return;
      case hdsMaterial.MaterialType.ADAPTIVE:
        target.push(hdsMaterial.MaterialType.ADAPTIVE);
        return;
      case hdsMaterial.MaterialType.IMMERSIVE:
        target.push(hdsMaterial.MaterialType.IMMERSIVE);
        return;
      default:
        return;
    }
  }

  private serializeMaterialTypes(types: Array<hdsMaterial.MaterialType>): string {
    return types.map((type: hdsMaterial.MaterialType) => String(type)).join(',');
  }

  private parseMaterialLevel(raw: number): hdsMaterial.MaterialLevel {
    switch (raw) {
      case hdsMaterial.MaterialLevel.EXQUISITE:
        return hdsMaterial.MaterialLevel.EXQUISITE;
      case hdsMaterial.MaterialLevel.GENTLE:
        return hdsMaterial.MaterialLevel.GENTLE;
      case hdsMaterial.MaterialLevel.SMOOTH:
        return hdsMaterial.MaterialLevel.SMOOTH;
      case hdsMaterial.MaterialLevel.ADAPTIVE:
        return hdsMaterial.MaterialLevel.ADAPTIVE;
      default:
        return DEFAULT_VISUAL_EFFECTS_SETTINGS.manualMaterialLevel;
    }
  }

  private recalculateEffectiveMaterialLevel(): void {
    if (this.currentState.settings.materialMode === VisualEffectsMaterialMode.ADAPTIVE) {
      this.currentState.effectiveMaterialLevel = hdsMaterial.MaterialLevel.ADAPTIVE;
      return;
    }

    this.currentState.effectiveMaterialLevel = this.normalizeManualMaterialLevel(
      this.currentState.settings.manualMaterialLevel
    );
  }

  private async persistSettings(): Promise<void> {
    await this.settingsManager.setString(
      SettingKeys.VISUAL_EFFECTS_MATERIAL_MODE,
      this.currentState.settings.materialMode
    );
    await this.settingsManager.setNumber(
      SettingKeys.VISUAL_EFFECTS_MANUAL_MATERIAL_LEVEL,
      this.currentState.settings.manualMaterialLevel
    );
  }

  private async persistCapability(): Promise<void> {
    await this.settingsManager.setString(
      SettingKeys.VISUAL_EFFECTS_SUPPORTED_MATERIAL_TYPES,
      this.serializeMaterialTypes(this.currentState.capability.supportedMaterialTypes)
    );
    await this.settingsManager.setNumber(
      SettingKeys.VISUAL_EFFECTS_CAPABILITY_LAST_CHECKED_AT,
      this.currentState.capability.lastCheckedAt
    );
    await this.settingsManager.setString(
      SettingKeys.VISUAL_EFFECTS_CAPABILITY_DETECT_ERROR,
      this.currentState.capability.detectError
    );
  }

  private syncStateToAppStorage(): void {
    AppStorage.setOrCreate('visual_effects_material_mode', this.currentState.settings.materialMode);
    AppStorage.setOrCreate('visual_effects_manual_material_level', this.currentState.settings.manualMaterialLevel);
    AppStorage.setOrCreate('visual_effects_effective_material_level', this.currentState.effectiveMaterialLevel);
    AppStorage.setOrCreate(
      'visual_effects_supported_material_types',
      JSON.stringify(this.currentState.capability.supportedMaterialTypes)
    );
    AppStorage.setOrCreate(
      'visual_effects_available_manual_levels',
      JSON.stringify(this.currentState.capability.availableManualLevels)
    );
    AppStorage.setOrCreate('visual_effects_supports_immersive', this.currentState.capability.supportsImmersiveMaterial);
    AppStorage.setOrCreate('visual_effects_supports_adaptive', this.currentState.capability.supportsAdaptiveMaterial);
    AppStorage.setOrCreate('visual_effects_recommended_manual_level', this.currentState.capability.recommendedManualLevel);
    AppStorage.setOrCreate('visual_effects_capability_last_checked_at', this.currentState.capability.lastCheckedAt);
    AppStorage.setOrCreate('visual_effects_capability_error', this.currentState.capability.detectError);
  }

  private notifyListeners(): void {
    const snapshot = this.getState();
    this.listeners.forEach((listener: VisualEffectsStateListener) => {
      try {
        listener(snapshot);
      } catch (error) {
        logger.error(TAG, 'Failed to execute visual effects listener callback', String(error));
      }
    });
  }
}

export function getVisualEffectsManager(): VisualEffectsManager {
  return VisualEffectsManager.getInstance();
}
