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
const KEY_LAST_SHOWN_VERSION_CODE = 'last_shown_version_code';

/**
 * 更新日志管理器 - 单例模式
 */
export class ChangelogManager {
  private static instance: ChangelogManager;
  private context: common.UIAbilityContext | null = null;
  private currentVersion: string = '';
  private currentVersionCode: number = 0;
  private lastShownVersion: string = '';
  private lastShownVersionCode: number = 0;
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
      this.currentVersionCode = bundleInfo.versionCode;
      logger.info(TAG, `当前应用版本: ${this.currentVersion} (${this.currentVersionCode})`);
      
      // 读取上次显示的版本
      this.prefs = await preferences.getPreferences(context, PREFS_NAME);
      this.lastShownVersion = await this.prefs.get(KEY_LAST_SHOWN_VERSION, '') as string;
      this.lastShownVersionCode = await this.prefs.get(KEY_LAST_SHOWN_VERSION_CODE, 0) as number;
      logger.info(TAG, `上次显示版本: ${this.lastShownVersion || '无'} (${this.lastShownVersionCode})`);
    } catch (error) {
      logger.error(TAG, `初始化失败: ${error}`);
    }
  }

  /**
   * 检查是否是首次安装（从未记录过版本号）
   */
  isFirstInstall(): boolean {
    return this.lastShownVersionCode === 0;
  }

  /**
   * 检查是否需要显示更新日志（新版本首次启动）
   * 使用 versionCode 进行比较，确保数字版本号变更也能触发
   * 注意：首次安装时不显示更新日志，只在版本升级时显示
   */
  shouldShowChangelog(): boolean {
    if (!this.currentVersionCode) {
      return false;
    }
    // 首次安装时不显示更新日志
    if (this.isFirstInstall()) {
      return false;
    }
    // 使用 versionCode 比较，只要版本号增加就显示更新日志
    return this.currentVersionCode > this.lastShownVersionCode;
  }

  /**
   * 获取当前版本号（字符串）
   */
  getCurrentVersion(): string {
    return this.currentVersion;
  }

  /**
   * 获取当前版本码（数字）
   */
  getCurrentVersionCode(): number {
    return this.currentVersionCode;
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
        await this.prefs.put(KEY_LAST_SHOWN_VERSION_CODE, this.currentVersionCode);
        await this.prefs.flush();
        this.lastShownVersion = this.currentVersion;
        this.lastShownVersionCode = this.currentVersionCode;
        logger.info(TAG, `已标记版本 ${this.currentVersion} (${this.currentVersionCode}) 的更新日志为已显示`);
      }
    } catch (error) {
      logger.error(TAG, `显示更新日志失败: ${error}`);
    }
  }

  /**
   * 检查并显示更新日志（如果是新版本）
   * 首次安装时静默记录当前版本号，不显示更新日志
   */
  async checkAndShowChangelog(): Promise<boolean> {
    // 首次安装时，静默记录当前版本号，不显示更新日志
    if (this.isFirstInstall()) {
      logger.info(TAG, `首次安装，静默记录版本 ${this.currentVersion} (${this.currentVersionCode})`);
      await this.markCurrentVersionAsShown();
      return false;
    }
    
    if (this.shouldShowChangelog()) {
      logger.info(TAG, `检测到新版本 ${this.currentVersion}，显示更新日志`);
      await this.showChangelog(true);
      return true;
    }
    return false;
  }

  /**
   * 标记当前版本为已显示（不实际显示更新日志）
   */
  private async markCurrentVersionAsShown(): Promise<void> {
    if (this.prefs) {
      await this.prefs.put(KEY_LAST_SHOWN_VERSION, this.currentVersion);
      await this.prefs.put(KEY_LAST_SHOWN_VERSION_CODE, this.currentVersionCode);
      await this.prefs.flush();
      this.lastShownVersion = this.currentVersion;
      this.lastShownVersionCode = this.currentVersionCode;
      logger.info(TAG, `已静默标记版本 ${this.currentVersion} (${this.currentVersionCode})`);
    }
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
      await this.prefs.delete(KEY_LAST_SHOWN_VERSION_CODE);
      await this.prefs.flush();
      this.lastShownVersion = '';
      this.lastShownVersionCode = 0;
      logger.info(TAG, '已重置更新日志显示状态');
    }
  }
}

export function getChangelogManager(): ChangelogManager {
  return ChangelogManager.getInstance();
}
