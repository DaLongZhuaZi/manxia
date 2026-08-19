import { http } from '@kit.NetworkKit';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { base64Encode } from 'manxia_core/src/main/ets/Utils/CryptoUtils';
import { BaseTracker } from './BaseTracker';
import { TrackRecord, TrackSearchResult, TrackerId, UpdateTrackRecordParams } from '../TrackingModels';
import { KomgaConfig, KomgaInstanceConfig } from '../../Source/KomgaModels';
import {
  createEmptyKomgaConfig,
  getKomgaInstanceDisplayName,
  loadKomgaConfig,
  saveKomgaConfig
} from '../../Source/KomgaConfigStore';

const TAG = 'KomgaTracker';

let komgaTrackerInstance: KomgaTracker | null = null;

export function getKomgaTracker(): KomgaTracker {
  if (!komgaTrackerInstance) {
    komgaTrackerInstance = new KomgaTracker();
  }
  return komgaTrackerInstance;
}

export class KomgaTracker extends BaseTracker {
  private config: KomgaConfig = createEmptyKomgaConfig();
  private isInitialized: boolean = false;

  constructor() {
    super(TrackerId.KOMGA, 'Komga');
  }

  public async initialize(forceReload: boolean = false): Promise<void> {
    if (this.isInitialized && !forceReload) {
      return;
    }

    this.config = await loadKomgaConfig();
    this.syncAuthState();
    this.isInitialized = true;
    logger.info(TAG, 'Komga 追踪器已初始化');
  }

  public getConfig(): KomgaConfig {
    return this.config;
  }

  public getInstances(): KomgaInstanceConfig[] {
    return this.config.instances;
  }

  public getCurrentInstance(): KomgaInstanceConfig | null {
    const instance = this.config.instances.find(item => item.id === this.config.currentInstanceId && item.enabled !== false);
    return instance || this.config.instances.find(item => item.enabled !== false) || null;
  }

  public async saveConfig(config: KomgaConfig): Promise<boolean> {
    const success = await saveKomgaConfig(config);
    if (success) {
      this.config = await loadKomgaConfig();
      this.syncAuthState();
      this.isInitialized = true;
    }
    return success;
  }

  public async setCurrentInstance(instanceId: string): Promise<boolean> {
    const nextConfig: KomgaConfig = {
      instances: this.config.instances,
      currentInstanceId: instanceId,
      useBrowsePageAsEntry: this.config.useBrowsePageAsEntry
    };
    return this.saveConfig(nextConfig);
  }

  public async testConnection(instanceId?: string): Promise<boolean> {
    await this.initialize();

    const instance = instanceId
      ? this.config.instances.find(item => item.id === instanceId)
      : this.getCurrentInstance();

    if (!instance || instance.serverUrl.trim().length <= 0) {
      return false;
    }

    const request = http.createHttp();
    try {
      const response = await request.request(`${this.normalizeServerUrl(instance.serverUrl)}/api/v1/libraries`, {
        method: http.RequestMethod.GET,
        header: this.buildHeaders(instance),
        connectTimeout: 20000,
        readTimeout: 20000
      });
      return response.responseCode >= 200 && response.responseCode < 300;
    } catch (error) {
      logger.error(TAG, `测试 Komga 连接失败: ${String(error)}`);
      return false;
    } finally {
      request.destroy();
    }
  }

  public getLoginUrl(): string {
    return '';
  }

  public async handleAuthCallback(_code: string): Promise<boolean> {
    return false;
  }

  public async logout(): Promise<void> {
    this.config = createEmptyKomgaConfig();
    await saveKomgaConfig(this.config);
    this.syncAuthState();
    this.isInitialized = true;
  }

  public async search(_query: string): Promise<TrackSearchResult[]> {
    return [];
  }

  public async bind(_trackRecord: TrackRecord): Promise<boolean> {
    return false;
  }

  public async updateRemoteProgress(_trackRecord: TrackRecord): Promise<boolean> {
    return false;
  }

  public async getRemoteProgress(_remoteId: string): Promise<UpdateTrackRecordParams | null> {
    return null;
  }

  public async refreshAccessToken(): Promise<boolean> {
    return false;
  }

  protected async saveAuthState(): Promise<void> {
  }

  protected async loadAuthState(): Promise<void> {
  }

  private syncAuthState(): void {
    const instance = this.getCurrentInstance();
    if (instance && instance.serverUrl.trim().length > 0) {
      this.authState.isLoggedIn = true;
      this.authState.username = getKomgaInstanceDisplayName(instance);
      this.authState.userId = instance.id;
    } else {
      this.authState.isLoggedIn = false;
      this.authState.username = '';
      this.authState.userId = '';
    }
  }

  private normalizeServerUrl(serverUrl: string): string {
    const raw = serverUrl.trim();
    if (raw.length <= 0) {
      return '';
    }
    const hasScheme = /^[a-zA-Z][a-zA-Z0-9+\-.]*:\/\//.test(raw);
    const withScheme = hasScheme ? raw : `http://${raw}`;
    return withScheme.endsWith('/') ? withScheme.substring(0, withScheme.length - 1) : withScheme;
  }

  private buildHeaders(instance: KomgaInstanceConfig): Record<string, string> {
    const headers: Record<string, string> = {
      'Accept': 'application/json',
      'User-Agent': 'ManXiaKomga/1.0'
    };

    if (instance.authMode === 'API_KEY' && instance.apiKey.trim().length > 0) {
      headers['X-API-Key'] = instance.apiKey.trim();
    } else if (instance.authMode === 'BASIC' && instance.username.trim().length > 0) {
      headers['Authorization'] = `Basic ${base64Encode(`${instance.username}:${instance.password}`)}`;
    }

    return headers;
  }

}
