// 文件路径: entry/src/main/ets/Utils/WelcomeGuideTestHelper.ets
/**
 * 欢迎引导测试辅助工具
 * 提供便捷的测试方法，用于开发和调试引导功能
 */

import { WelcomeGuideManager, GuideStep } from '../Framework/Managers/WelcomeGuideManager';
import { logger } from './Logger';

const TAG = 'WelcomeGuideTestHelper';

/**
 * 欢迎引导测试辅助类
 */
export class WelcomeGuideTestHelper {
  private static guideManager: WelcomeGuideManager = WelcomeGuideManager.getInstance();

  /**
   * 重置引导状态（模拟首次启动）
   * 用于测试首次启动引导流程
   */
  public static async resetToFirstLaunch(): Promise<void> {
    try {
      await this.guideManager.initialize();
      await this.guideManager.resetGuide();
      logger.info(TAG, '✅ 引导状态已重置为首次启动');
      return Promise.resolve();
    } catch (error) {
      logger.error(TAG, '重置引导状态失败', String(error));
      return Promise.reject(error);
    }
  }

  /**
   * 完成引导
   * 用于跳过引导流程，直接进入应用
   */
  public static async completeGuide(): Promise<void> {
    try {
      await this.guideManager.initialize();
      await this.guideManager.markGuideCompleted();
      logger.info(TAG, '✅ 引导已标记为完成');
      return Promise.resolve();
    } catch (error) {
      logger.error(TAG, '完成引导失败', String(error));
      return Promise.reject(error);
    }
  }

  /**
   * 跳过引导
   * 用于测试跳过引导的场景
   */
  public static async skipGuide(): Promise<void> {
    try {
      await this.guideManager.initialize();
      await this.guideManager.skipGuide();
      logger.info(TAG, '✅ 引导已标记为跳过');
      return Promise.resolve();
    } catch (error) {
      logger.error(TAG, '跳过引导失败', String(error));
      return Promise.reject(error);
    }
  }

  /**
   * 设置引导步骤
   * 用于测试特定步骤的引导
   */
  public static async setGuideStep(step: GuideStep): Promise<void> {
    try {
      await this.guideManager.initialize();
      await this.guideManager.setCurrentStep(step);
      logger.info(TAG, `✅ 引导步骤已设置为: ${step}`);
      return Promise.resolve();
    } catch (error) {
      logger.error(TAG, '设置引导步骤失败', String(error));
      return Promise.reject(error);
    }
  }

  /**
   * 获取当前引导状态
   * 用于调试和状态检查
   */
  public static async getGuideStatus(): Promise<string> {
    try {
      await this.guideManager.initialize();
      const config = this.guideManager.getGuideConfig();
      
      const status = `
引导状态信息:
- 是否首次启动: ${this.guideManager.isFirstTimeLaunch()}
- 是否需要显示引导: ${this.guideManager.shouldShowGuide()}
- 引导是否完成: ${config.completed}
- 引导是否跳过: ${config.skipped}
- 当前步骤: ${this.getStepName(config.currentStep)}
- 最后显示时间: ${new Date(config.lastShowTime).toLocaleString()}
      `;
      
      logger.info(TAG, status);
      return Promise.resolve(status);
    } catch (error) {
      logger.error(TAG, '获取引导状态失败', String(error));
      return Promise.reject(error);
    }
  }

  /**
   * 获取步骤名称
   */
  private static getStepName(step: GuideStep): string {
    switch (step) {
      case GuideStep.WELCOME:
        return 'WELCOME (欢迎页)';
      case GuideStep.DATA_IMPORT:
        return 'DATA_IMPORT (数据导入)';
      case GuideStep.LOG_EXPORT:
        return 'LOG_EXPORT (日志导出)';
      case GuideStep.LIBRARY_INTRO:
        return 'LIBRARY_INTRO (书库介绍)';
      case GuideStep.COMPLETED:
        return 'COMPLETED (已完成)';
      default:
        return `UNKNOWN (${step})`;
    }
  }

  /**
   * 打印所有引导步骤
   */
  public static printAllSteps(): void {
    const steps = [
      GuideStep.WELCOME,
      GuideStep.DATA_IMPORT,
      GuideStep.LOG_EXPORT,
      GuideStep.LIBRARY_INTRO,
      GuideStep.COMPLETED
    ];

    logger.info(TAG, '=== 引导步骤列表 ===');
    steps.forEach((step, index) => {
      logger.info(TAG, `${index}. ${this.getStepName(step)}`);
    });
  }

  /**
   * 运行快速测试
   * 测试引导管理器的基本功能
   */
  public static async runQuickTest(): Promise<boolean> {
    try {
      logger.info(TAG, '🚀 开始快速测试...');

      // 测试1: 初始化
      logger.info(TAG, '测试1: 初始化引导管理器');
      await this.guideManager.initialize();
      logger.info(TAG, '✅ 初始化成功');

      // 测试2: 获取状态
      logger.info(TAG, '测试2: 获取当前状态');
      await this.getGuideStatus();
      logger.info(TAG, '✅ 获取状态成功');

      // 测试3: 重置引导
      logger.info(TAG, '测试3: 重置引导');
      await this.resetToFirstLaunch();
      logger.info(TAG, '✅ 重置成功');

      // 测试4: 验证首次启动
      logger.info(TAG, '测试4: 验证首次启动状态');
      const isFirstLaunch = this.guideManager.isFirstTimeLaunch();
      if (!isFirstLaunch) {
        throw new Error('首次启动状态不正确');
      }
      logger.info(TAG, '✅ 首次启动状态正确');

      // 测试5: 设置步骤
      logger.info(TAG, '测试5: 设置引导步骤');
      await this.setGuideStep(GuideStep.DATA_IMPORT);
      logger.info(TAG, '✅ 设置步骤成功');

      // 测试6: 完成引导
      logger.info(TAG, '测试6: 完成引导');
      await this.completeGuide();
      logger.info(TAG, '✅ 完成引导成功');

      // 测试7: 验证完成状态
      logger.info(TAG, '测试7: 验证完成状态');
      const isCompleted = this.guideManager.isGuideCompleted();
      if (!isCompleted) {
        throw new Error('完成状态不正确');
      }
      logger.info(TAG, '✅ 完成状态正确');

      logger.info(TAG, '🎉 所有测试通过！');
      return Promise.resolve(true);
    } catch (error) {
      logger.error(TAG, '❌ 测试失败', String(error));
      return Promise.resolve(false);
    }
  }

  /**
   * 打印使用帮助
   */
  public static printHelp(): void {
    const help = `
欢迎引导测试辅助工具 - 使用帮助
=====================================

1. 重置为首次启动:
   await WelcomeGuideTestHelper.resetToFirstLaunch();

2. 完成引导:
   await WelcomeGuideTestHelper.completeGuide();

3. 跳过引导:
   await WelcomeGuideTestHelper.skipGuide();

4. 设置引导步骤:
   await WelcomeGuideTestHelper.setGuideStep(GuideStep.DATA_IMPORT);

5. 获取引导状态:
   await WelcomeGuideTestHelper.getGuideStatus();

6. 打印所有步骤:
   WelcomeGuideTestHelper.printAllSteps();

7. 运行快速测试:
   await WelcomeGuideTestHelper.runQuickTest();

8. 打印帮助信息:
   WelcomeGuideTestHelper.printHelp();
    `;
    
    logger.info(TAG, help);
  }
}

