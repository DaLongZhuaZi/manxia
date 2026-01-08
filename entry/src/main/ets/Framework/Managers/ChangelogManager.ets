/**
 * 更新日志管理器
 * 负责检测版本更新并显示更新日志
 * 
 * 文件路径: entry/src/main/ets/Framework/Managers/ChangelogManager.ets
 */

import { logger } from '../../Utils/Logger';
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { bundleManager } from '@kit.AbilityKit';
import { getContentPanelManager, ContentSource, ContentPanelType } from '../Components/ContentPanel';

const TAG = 'ChangelogManager';
const PREFS_NAME = 'changelog_prefs';
const KEY_LAST_SHOWN_VERSION = 'last_shown_version';

/**
 * 更新日志管理器 - 单例模式
 */
export class ChangelogManager {
  private static instance: ChangelogManager;
  private context: common.UIAbilityContext | null = null;
  private currentVersion: string = '';
  private lastShownVersion: string = '';
  private prefs: preferences.Preferences | null = null;

  private constructor() {}

  static getInstance(): ChangelogManager {
    if (!ChangelogManager.instance) {
      ChangelogManager.instance = new ChangelogManager();
    }
    return ChangelogManager.instance;
  }

  /**
   * 初始化管理器
   */
  async initialize(context: common.UIAbilityContext): Promise<void> {
    this.context = context;
    
    try {
      // 获取当前应用版本
      const bundleInfo = await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
      this.currentVersion = bundleInfo.versionName;
      logger.info(TAG, `当前应用版本: ${this.currentVersion}`);
      
      // 读取上次显示的版本
      this.prefs = await preferences.getPreferences(context, PREFS_NAME);
      this.lastShownVersion = await this.prefs.get(KEY_LAST_SHOWN_VERSION, '') as string;
      logger.info(TAG, `上次显示版本: ${this.lastShownVersion || '无'}`);
    } catch (error) {
      logger.error(TAG, `初始化失败: ${error}`);
    }
  }

  /**
   * 检查是否需要显示更新日志（新版本首次启动）
   */
  shouldShowChangelog(): boolean {
    if (!this.currentVersion) {
      return false;
    }
    return this.currentVersion !== this.lastShownVersion;
  }

  /**
   * 获取当前版本号
   */
  getCurrentVersion(): string {
    return this.currentVersion;
  }

  /**
   * 显示更新日志
   * @param markAsShown 是否标记为已显示（默认true）
   */
  async showChangelog(markAsShown: boolean = true): Promise<void> {
    if (!this.context) {
      logger.warn(TAG, '管理器未初始化');
      return;
    }

    try {
      const panelManager = getContentPanelManager();
      panelManager.addTab({
        title: `更新日志 v${this.currentVersion}`,
        type: ContentPanelType.CHANGELOG,
        source: ContentSource.RAWFILE,
        content: 'changelog.md',
        icon: $r('sys.symbol.doc_text_fill')
      });

      // 标记为已显示
      if (markAsShown && this.prefs) {
        await this.prefs.put(KEY_LAST_SHOWN_VERSION, this.currentVersion);
        await this.prefs.flush();
        this.lastShownVersion = this.currentVersion;
        logger.info(TAG, `已标记版本 ${this.currentVersion} 的更新日志为已显示`);
      }
    } catch (error) {
      logger.error(TAG, `显示更新日志失败: ${error}`);
    }
  }

  /**
   * 检查并显示更新日志（如果是新版本）
   */
  async checkAndShowChangelog(): Promise<boolean> {
    if (this.shouldShowChangelog()) {
      logger.info(TAG, `检测到新版本 ${this.currentVersion}，显示更新日志`);
      await this.showChangelog(true);
      return true;
    }
    return false;
  }

  /**
   * 强制显示更新日志（不标记为已显示）
   */
  async forceShowChangelog(): Promise<void> {
    await this.showChangelog(false);
  }

  /**
   * 重置已显示状态（用于测试）
   */
  async resetShownStatus(): Promise<void> {
    if (this.prefs) {
      await this.prefs.delete(KEY_LAST_SHOWN_VERSION);
      await this.prefs.flush();
      this.lastShownVersion = '';
      logger.info(TAG, '已重置更新日志显示状态');
    }
  }
}

export function getChangelogManager(): ChangelogManager {
  return ChangelogManager.getInstance();
}
