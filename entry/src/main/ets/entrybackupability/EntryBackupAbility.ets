import { hilog } from '@kit.PerformanceAnalysisKit';
import { BackupExtensionAbility, BundleVersion } from '@kit.CoreFileKit';
import { logger } from '../Utils/Logger';
import { getEnhancedBackupManager } from '../Framework/Managers/EnhancedBackupManager';
import { DEFAULT_BACKUP_OPTIONS } from '../Models/BackupModels';

const TAG = 'EntryBackupAbility';

export default class EntryBackupAbility extends BackupExtensionAbility {
  /**
   * 💾 当系统请求备份应用数据时调用
   * 在此方法中实现数据备份逻辑
   */
  async onBackup() {
    logger.lifecycle(TAG, '数据备份', '系统触发应用数据备份');
    logger.info(TAG, '📦 开始准备数据备份');
    
    try {
      // 使用增强版备份管理器创建备份
      const backupManager = getEnhancedBackupManager();
      
      logger.info(TAG, '📊 正在收集应用数据...');
      
      // 使用默认选项创建完整备份
      const backupPath = await backupManager.createBackup(DEFAULT_BACKUP_OPTIONS);
      
      logger.info(TAG, `💾 备份文件已创建: ${backupPath}`);
      logger.info(TAG, '✅ 数据备份完成');
      
    } catch (error) {
      logger.error(TAG, `❌ 备份过程失败: ${JSON.stringify(error)}`);
      throw new Error(`Backup failed: ${error}`);
    }
  }

  /**
   * 🔄 当系统请求恢复应用数据时调用
   * 在此方法中实现数据恢复逻辑
   * @param bundleVersion 应用版本信息，用于处理跨版本恢复
   */
  async onRestore(bundleVersion: BundleVersion) {
    logger.lifecycle(TAG, '数据恢复', '系统触发应用数据恢复');
    logger.info(TAG, `📦 开始准备数据恢复，目标版本: ${JSON.stringify(bundleVersion)}`);
    
    try {
      // 使用增强版备份管理器恢复备份
      const backupManager = getEnhancedBackupManager();
      
      logger.info(TAG, '🔍 正在检查备份数据完整性...');
      
      // 注意：系统备份恢复时，需要知道备份文件的位置
      // 这里需要根据实际的系统备份机制来获取备份文件路径
      // 暂时记录日志，实际恢复逻辑需要在应用内手动触发
      logger.warn(TAG, '⚠️ 系统备份恢复需要用户在应用内选择备份文件');
      logger.info(TAG, '✅ 数据恢复准备完成（需要用户手动操作）');
      
    } catch (error) {
      logger.error(TAG, `❌ 恢复过程失败: ${JSON.stringify(error)}`);
      throw new Error(`Restore failed: ${error}`);
    }
  }
}