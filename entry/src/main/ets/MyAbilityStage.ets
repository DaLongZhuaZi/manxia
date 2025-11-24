// 文件路径: src/main/ets/MyAbilityStage.ets
/**
 * 应用阶段生命周期管理
 * AbilityStage是应用启动的第一个入口点，在EntryAbility之前被调用
 * 负责应用级别的初始化工作
 */
 
import { AbilityStage, Want, Configuration } from '@kit.AbilityKit'; 
import { logger } from './Utils/Logger';
import { startupController } from './Framework/Diagnostics/StartupController';
import { themeManager, ThemeType } from './Framework/Managers/ThemeManager';

const TAG = 'MyAbilityStage';

/**
 * 🚀 应用阶段生命周期管理
 * AbilityStage是应用启动的第一个入口点，在EntryAbility之前被调用
 * 负责应用级别的初始化工作
 */
export default class MyAbilityStage extends AbilityStage {
  /**
   * 🎯 应用阶段创建时调用
   * 这是整个应用最早被调用的生命周期方法
   */
  onCreate(): void {
    // 开始启动流程监控 - 使用StartupController统一管理
    startupController.startMonitoring();

    // 最早期的日志输出，确保能看到应用启动
    logger.startup(TAG, 'onCreate START', '应用阶段开始创建');

    // try {
    //   logger.info(TAG, '🚀 准备启动游戏引擎...');
    //   viewEngine.initializeAndStart();
    //   logger.info(TAG, '✅ 游戏引擎已成功启动并在后台运行。');
    // } catch (error) {
    //   // ...
    // }
  }

  /**
   * 🔄 应用配置更新时调用
   */
  onConfigurationUpdate(newConfig: Configuration): void {
    logger.lifecycle(TAG, '配置更新', `新配置: ${JSON.stringify(newConfig)}`);
    
    // 检查系统主题变化
    if (newConfig.colorMode !== undefined) {
      this.handleSystemThemeChange(newConfig.colorMode);
    }
  }

  /**
   * 处理系统主题变化
   */
  private handleSystemThemeChange(colorMode: number): void {
    logger.info(TAG, `系统颜色模式变化: ${colorMode}`);
    
    // 更新系统主题（ThemeManager会自动处理AUTO模式的切换）
    themeManager.updateSystemTheme(colorMode);
  }

  /**
   * 💾 内存不足时调用
   */
  onMemoryLevel(level: number): void {
    logger.warn('MyAbilityStage', `⚠️ 内存警告: 级别${level}`);
  }

  // [核心修正] 为 want 参数添加明确的 Want 类型
  onAcceptWant(want: Want): string {
    if (want.action === 'action.system.terminate') {
      logger.info(TAG, '🔴 应用即将终止（游戏引擎已移除）...');
      // viewEngine.stop(); // 游戏引擎已移除
      logger.info(TAG, '✅ 应用清理完成。');
    }
    return "MyAbilityStage";
  }
}
