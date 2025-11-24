// 文件路径: src/main/ets/Framework/Diagnostics/StartupTest.ets

import { logger } from '../../Utils/Logger';
import { startupController } from './StartupController';
import { StartupPhase } from './StartupDiagnostics';

/**
 * 启动流程测试工具
 * 用于验证启动诊断、健康检查和恢复系统的功能
 */
export class StartupTest {
  private static instance: StartupTest;

  private constructor() {}

  static getInstance(): StartupTest {
    if (!StartupTest.instance) {
      StartupTest.instance = new StartupTest();
    }
    return StartupTest.instance;
  }

  /**
   * 测试正常启动流程
   */
  async testNormalStartup(): Promise<boolean> {
    logger.info('StartupTest', '🧪 开始测试正常启动流程');
    
    try {
      // 开始监控
      startupController.startMonitoring();
      
      // 模拟各个启动阶段
      await this.simulatePhase(StartupPhase.ABILITY_STAGE_CREATE, 100);
      await this.simulatePhase(StartupPhase.ENTRY_ABILITY_CREATE, 150);
      await this.simulatePhase(StartupPhase.GLOBAL_CONTEXT_INIT, 200);
      await this.simulatePhase(StartupPhase.WINDOW_STAGE_CREATE, 120);
      await this.simulatePhase(StartupPhase.PERMISSION_REQUEST, 300);
      await this.simulatePhase(StartupPhase.LOADING_PAGE_START, 80);
      await this.simulatePhase(StartupPhase.STARTUP_HEALTH_CHECK, 250);
      await this.simulatePhase(StartupPhase.RESOURCE_LOADING, 500);
      await this.simulatePhase(StartupPhase.SYSTEM_REGISTRATION, 300);
      await this.simulatePhase(StartupPhase.POST_STARTUP_HEALTH_CHECK, 200);
      await this.simulatePhase(StartupPhase.MAIN_MENU_READY, 100);
      
      // 完成监控
      startupController.completeStartup();
      
      logger.info('StartupTest', '✅ 正常启动流程测试完成');
      return true;
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error('StartupTest', `❌ 正常启动流程测试失败: ${errorMessage}`);
      return false;
    }
  }

  /**
   * 测试启动失败和恢复流程
   */
  async testFailureRecovery(): Promise<boolean> {
    logger.info('StartupTest', '🧪 开始测试启动失败和恢复流程');
    
    try {
      // 开始监控
      startupController.startMonitoring();
      
      // 模拟正常阶段
      await this.simulatePhase(StartupPhase.ABILITY_STAGE_CREATE, 100);
      await this.simulatePhase(StartupPhase.ENTRY_ABILITY_CREATE, 150);
      
      // 模拟失败阶段
      try {
        await this.simulateFailedPhase(StartupPhase.GLOBAL_CONTEXT_INIT, 'GlobalContext初始化失败');
      } catch (error) {
        logger.info('StartupTest', '预期的失败已捕获，测试恢复机制');
      }
      
      // 继续其他阶段
      await this.simulatePhase(StartupPhase.WINDOW_STAGE_CREATE, 120);
      
      logger.info('StartupTest', '✅ 启动失败和恢复流程测试完成');
      return true;
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error('StartupTest', `❌ 启动失败和恢复流程测试失败: ${errorMessage}`);
      return false;
    }
  }

  /**
   * 测试性能监控
   */
  async testPerformanceMonitoring(): Promise<boolean> {
    logger.info('StartupTest', '🧪 开始测试性能监控');
    
    try {
      // 开始监控
      startupController.startMonitoring();
      
      // 模拟慢速阶段
      await this.simulatePhase(StartupPhase.ABILITY_STAGE_CREATE, 100);
      await this.simulatePhase(StartupPhase.ENTRY_ABILITY_CREATE, 150);
      await this.simulatePhase(StartupPhase.GLOBAL_CONTEXT_INIT, 1000); // 慢速阶段
      await this.simulatePhase(StartupPhase.WINDOW_STAGE_CREATE, 120);
      
      // 完成监控
      startupController.completeStartup();
      
      logger.info('StartupTest', '✅ 性能监控测试完成');
      return true;
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error('StartupTest', `❌ 性能监控测试失败: ${errorMessage}`);
      return false;
    }
  }

  /**
   * 运行所有测试
   */
  async runAllTests(): Promise<void> {
    logger.info('StartupTest', '🚀 开始运行启动流程测试套件');
    
    const results = {
      normalStartup: false,
      failureRecovery: false,
      performanceMonitoring: false
    };
    
    // 测试正常启动流程
    results.normalStartup = await this.testNormalStartup();
    await this.delay(1000); // 测试间隔
    
    // 测试失败恢复流程
    results.failureRecovery = await this.testFailureRecovery();
    await this.delay(1000); // 测试间隔
    
    // 测试性能监控
    results.performanceMonitoring = await this.testPerformanceMonitoring();
    
    // 输出测试结果
    this.logTestResults(results);
  }

  /**
   * 模拟启动阶段
   */
  private async simulatePhase(phase: StartupPhase, duration: number): Promise<void> {
    await startupController.executePhase(phase, async () => {
      logger.debug('StartupTest', `模拟阶段: ${phase}`);
      await this.delay(duration);
    });
  }

  /**
   * 模拟失败的启动阶段
   */
  private async simulateFailedPhase(phase: StartupPhase, errorMessage: string): Promise<void> {
    await startupController.executePhase(phase, async () => {
      logger.debug('StartupTest', `模拟失败阶段: ${phase}`);
      await this.delay(100);
      throw new Error(errorMessage);
    });
  }

  /**
   * 延迟函数
   */
  private delay(ms: number): Promise<void> {
    return new Promise<void>((resolve) => setTimeout(resolve, ms));
  }

  /**
   * 输出测试结果
   */
  private logTestResults(results: Record<string, boolean>): void {
    // 构建完整的测试报告
    const reportLines: string[] = [];
    reportLines.push('🧪 ========== 启动流程测试报告 ==========');
    
    Object.entries(results).forEach(([testName, success]) => {
      const status = success ? '✅ 通过' : '❌ 失败';
      reportLines.push(`  ${testName}: ${status}`);
    });
    
    const totalTests = Object.keys(results).length;
    const passedTests = Object.values(results).filter(result => result).length;
    const successRate = totalTests > 0 && typeof passedTests === 'number' ? (passedTests / totalTests * 100).toFixed(1) : '未知';
    
    reportLines.push(`📈 测试通过率: ${passedTests}/${totalTests} (${successRate}%)`);
    
    if (passedTests === totalTests) {
      reportLines.push('🎉 所有测试通过！启动流程系统运行正常');
    } else {
      reportLines.push('⚠️ 部分测试失败，请检查启动流程系统');
    }
    
    reportLines.push('🧪 ========== 测试报告结束 ==========');
    
    // 使用warn级别输出完整报告
    logger.warn('StartupTest', reportLines.join('\n'));
  }
}

// 导出单例实例
export const startupTest = StartupTest.getInstance();