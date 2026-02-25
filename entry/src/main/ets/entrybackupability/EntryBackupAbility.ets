import { BackupExtensionAbility, BundleVersion } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'EntryBackupAbility';
const DOMAIN = 0x0001;

/**
 * 系统备份扩展Ability
 * 
 * 【重要】此扩展运行在独立于主应用的进程中，主应用的全局上下文、数据库、
 * 沙箱管理器等均未初始化。绝对不能在此处调用任何依赖主应用初始化的管理器
 * （如EnhancedBackupManager、DatabaseManager等），否则会导致崩溃。
 * 
 * 系统备份/恢复的实际数据操作由用户在应用内通过BackupPage手动触发。
 * 此处仅作为系统备份框架的接入点，安全地返回即可。
 */
export default class EntryBackupAbility extends BackupExtensionAbility {
  /**
   * 当系统请求备份应用数据时调用
   * 由于此扩展运行在独立进程，主应用的数据管理器均未初始化，
   * 因此不执行实际备份操作，仅安全返回。
   */
  async onBackup() {
    hilog.info(DOMAIN, TAG, '系统触发应用数据备份（扩展进程）');
    hilog.info(DOMAIN, TAG, '实际备份由用户在应用内手动触发，此处安全返回');
    // 不调用任何依赖主应用初始化的管理器，直接返回
  }

  /**
   * 当系统请求恢复应用数据时调用
   * 由于此扩展运行在独立进程，主应用的数据管理器均未初始化，
   * 因此不执行实际恢复操作，仅安全返回。
   * @param bundleVersion 应用版本信息
   */
  async onRestore(bundleVersion: BundleVersion) {
    hilog.info(DOMAIN, TAG, `系统触发应用数据恢复（扩展进程），版本: code=${bundleVersion.code}, name=${bundleVersion.name}`);
    hilog.info(DOMAIN, TAG, '实际恢复由用户在应用内手动触发，此处安全返回');
    // 不调用任何依赖主应用初始化的管理器，直接返回
  }
}
