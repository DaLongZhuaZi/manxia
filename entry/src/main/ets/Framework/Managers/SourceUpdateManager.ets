/**
 * 图源更新管理器
 * 负责检查图源仓库更新、管理更新状态
 */

import { preferences } from '@kit.ArkData';
import { http } from '@kit.NetworkKit';
import { logger } from '../../Utils/Logger';

const TAG = 'SourceUpdateManager';
const PREFERENCES_NAME = 'source_update_preferences';
const REPO_INDEX_FILENAME = 'index.main.json';

/**
 * 图源仓库索引项
 */
export interface SourceIndexItem {
  name: string;
  version: string;
  file: string;
  description?: string;
  author?: string;
  updateTime?: string;
}

/**
 * 图源仓库索引
 */
export interface SourceRepoIndex {
  version: string;
  updateTime: string;
  sources: SourceIndexItem[];
}

/**
 * 更新检查结果
 */
export interface UpdateCheckResult {
  hasUpdate: boolean;
  remoteIndex: SourceRepoIndex | null;
  localIndex: SourceRepoIndex | null;
  updatedSources: SourceIndexItem[];
  newSources: SourceIndexItem[];
}

/**
 * 图源更新管理器单例
 */
export class SourceUpdateManager {
  private static instance: SourceUpdateManager;
  private preferences: preferences.Preferences | null = null;
  private initialized: boolean = false;
  
  // 更新状态
  private hasUpdate: boolean = false;
  private lastCheckTime: number = 0;
  private repoUrl: string = '';
  private localIndex: SourceRepoIndex | null = null;
  
  private constructor() {}

  public static getInstance(): SourceUpdateManager {
    if (!SourceUpdateManager.instance) {
      SourceUpdateManager.instance = new SourceUpdateManager();
    }
    return SourceUpdateManager.instance;
  }

  /**
   * 初始化管理器
   */
  public async initialize(context: Context): Promise<void> {
    if (this.initialized) {
      return;
    }

    try {
      this.preferences = await preferences.getPreferences(context, PREFERENCES_NAME);
      await this.loadSettings();
      this.initialized = true;
      logger.info(TAG, '图源更新管理器初始化完成');
    } catch (error) {
      logger.error(TAG, `初始化失败: ${String(error)}`);
    }
  }

  /**
   * 加载设置
   */
  private async loadSettings(): Promise<void> {
    if (!this.preferences) return;

    try {
      this.hasUpdate = (await this.preferences.get('hasUpdate', false)) as boolean;
      this.lastCheckTime = (await this.preferences.get('lastCheckTime', 0)) as number;
      this.repoUrl = (await this.preferences.get('repoUrl', '')) as string;
      
      const localIndexStr = (await this.preferences.get('localIndex', '')) as string;
      if (localIndexStr && localIndexStr.length > 0) {
        this.localIndex = JSON.parse(localIndexStr) as SourceRepoIndex;
      }
      
      logger.debug(TAG, `加载设置: hasUpdate=${this.hasUpdate}, repoUrl=${this.repoUrl}`);
    } catch (error) {
      logger.error(TAG, `加载设置失败: ${String(error)}`);
    }
  }

  /**
   * 保存设置
   */
  private async saveSettings(): Promise<void> {
    if (!this.preferences) return;

    try {
      await this.preferences.put('hasUpdate', this.hasUpdate);
      await this.preferences.put('lastCheckTime', this.lastCheckTime);
      await this.preferences.put('repoUrl', this.repoUrl);
      
      if (this.localIndex) {
        await this.preferences.put('localIndex', JSON.stringify(this.localIndex));
      }
      
      await this.preferences.flush();
      logger.debug(TAG, '设置已保存');
    } catch (error) {
      logger.error(TAG, `保存设置失败: ${String(error)}`);
    }
  }

  /**
   * 设置仓库URL
   */
  public async setRepoUrl(url: string): Promise<void> {
    this.repoUrl = url;
    await this.saveSettings();
  }

  /**
   * 获取仓库URL
   */
  public getRepoUrl(): string {
    return this.repoUrl;
  }

  /**
   * 是否有更新
   */
  public hasSourceUpdate(): boolean {
    return this.hasUpdate;
  }

  /**
   * 清除更新标记
   */
  public async clearUpdateFlag(): Promise<void> {
    this.hasUpdate = false;
    await this.saveSettings();
  }

  /**
   * 检查更新
   * @returns 更新检查结果
   */
  public async checkForUpdates(): Promise<UpdateCheckResult> {
    const result: UpdateCheckResult = {
      hasUpdate: false,
      remoteIndex: null,
      localIndex: this.localIndex,
      updatedSources: [],
      newSources: []
    };

    if (!this.repoUrl || this.repoUrl.length === 0) {
      logger.warn(TAG, '未设置仓库URL，跳过更新检查');
      return result;
    }

    try {
      logger.info(TAG, `开始检查更新: ${this.repoUrl}`);
      
      // 获取远程索引文件
      const indexUrl = this.repoUrl.endsWith('/') 
        ? `${this.repoUrl}${REPO_INDEX_FILENAME}` 
        : `${this.repoUrl}/${REPO_INDEX_FILENAME}`;
      
      const remoteIndex = await this.fetchRemoteIndex(indexUrl);
      if (!remoteIndex) {
        logger.warn(TAG, '无法获取远程索引');
        return result;
      }

      result.remoteIndex = remoteIndex;
      this.lastCheckTime = Date.now();

      // 比较本地和远程索引
      if (!this.localIndex) {
        // 没有本地索引，所有远程图源都是新的
        result.newSources = remoteIndex.sources;
        result.hasUpdate = remoteIndex.sources.length > 0;
      } else {
        // 比较版本
        for (const remoteSource of remoteIndex.sources) {
          const localSource = this.localIndex.sources.find(s => s.name === remoteSource.name);
          if (!localSource) {
            // 新图源
            result.newSources.push(remoteSource);
          } else if (localSource.version !== remoteSource.version) {
            // 版本不同，有更新
            result.updatedSources.push(remoteSource);
          }
        }
        result.hasUpdate = result.newSources.length > 0 || result.updatedSources.length > 0;
      }

      // 更新状态
      this.hasUpdate = result.hasUpdate;
      await this.saveSettings();

      logger.info(TAG, `更新检查完成: hasUpdate=${result.hasUpdate}, new=${result.newSources.length}, updated=${result.updatedSources.length}`);
      return result;
    } catch (error) {
      logger.error(TAG, `检查更新失败: ${String(error)}`);
      return result;
    }
  }

  /**
   * 获取远程索引文件
   */
  private async fetchRemoteIndex(url: string): Promise<SourceRepoIndex | null> {
    try {
      const httpRequest = http.createHttp();
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: {
          'Content-Type': 'application/json'
        },
        connectTimeout: 10000,
        readTimeout: 10000
      });

      httpRequest.destroy();

      if (response.responseCode === 200) {
        const data = response.result as string;
        return JSON.parse(data) as SourceRepoIndex;
      } else {
        logger.warn(TAG, `获取远程索引失败: HTTP ${response.responseCode}`);
        return null;
      }
    } catch (error) {
      logger.error(TAG, `获取远程索引异常: ${String(error)}`);
      return null;
    }
  }

  /**
   * 同步仓库（只更新JSON文件，不删除数据库条目）
   */
  public async syncRepository(): Promise<boolean> {
    if (!this.repoUrl || this.repoUrl.length === 0) {
      logger.warn(TAG, '未设置仓库URL，无法同步');
      return false;
    }

    try {
      logger.info(TAG, '开始同步仓库...');
      
      // 获取远程索引
      const indexUrl = this.repoUrl.endsWith('/') 
        ? `${this.repoUrl}index.json` 
        : `${this.repoUrl}/index.json`;
      
      const remoteIndex = await this.fetchRemoteIndex(indexUrl);
      if (!remoteIndex) {
        logger.error(TAG, '无法获取远程索引，同步失败');
        return false;
      }

      // 更新本地索引
      this.localIndex = remoteIndex;
      this.hasUpdate = false;
      this.lastCheckTime = Date.now();
      await this.saveSettings();

      logger.info(TAG, '仓库同步完成');
      return true;
    } catch (error) {
      logger.error(TAG, `同步仓库失败: ${String(error)}`);
      return false;
    }
  }

  /**
   * 获取本地索引
   */
  public getLocalIndex(): SourceRepoIndex | null {
    return this.localIndex;
  }

  /**
   * 更新本地索引
   */
  public async updateLocalIndex(index: SourceRepoIndex): Promise<void> {
    this.localIndex = index;
    await this.saveSettings();
  }
}
