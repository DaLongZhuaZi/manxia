// 文件路径: src/main/ets/Framework/Initialization/ContinuationBootstrap.ets
/**
 * 接续落地引导初始化器
 * 跨端接续冷启动时，进程内可能只有阅读器 Ability（没有 EntryAbility），
 * GlobalContext、数据管理器和设置门面都不会自动初始化，导致落地页面
 * 解析 bookId 或构建阅读器时访问未注册的服务。
 * 本模块提供幂等的就绪保障：
 * - 阅读器 Ability 在 onCreate 提前触发（与窗口恢复并行）；
 * - 落地页面在解析阅读路由前等待就绪（已就绪时立即返回）。
 */

import { common } from '@kit.AbilityKit';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { setContext, isInitialized as isGlobalContextInitialized } from 'manxia_core/src/main/ets/GlobalContext';
import { SettingsManager } from 'manxia_core/src/main/ets/Framework/Managers/SettingsManager';
import { DataInitializer } from './DataInitializer';
import { ContinuationReadingSettingsManager } from '../Distributed/ContinuationReadingSettingsManager';
import { ContinuationCacheManager } from '../Distributed/ContinuationCacheManager';

const TAG = 'ContinuationBootstrap';

export class ContinuationBootstrap {
  private static instance: ContinuationBootstrap | null = null;
  private readyPromise: Promise<void> | null = null;
  private completed: boolean = false;

  private constructor() {}

  /**
   * 获取单例实例
   */
  public static getInstance(): ContinuationBootstrap {
    if (!ContinuationBootstrap.instance) {
      ContinuationBootstrap.instance = new ContinuationBootstrap();
    }
    return ContinuationBootstrap.instance;
  }

  /**
   * 确保接续落地所需全局依赖就绪（GlobalContext + 数据系统 + 设置门面）。
   * 幂等：已完成立即返回；进行中共享同一 Promise；失败后允许下次重试。
   */
  public ensureReady(context: common.UIAbilityContext): Promise<void> {
    if (this.completed) {
      return Promise.resolve();
    }
    if (!this.readyPromise) {
      this.readyPromise = this.performBootstrap(context);
    }
    return this.readyPromise;
  }

  /**
   * 是否已就绪
   */
  public isReady(): boolean {
    return this.completed;
  }

  private async performBootstrap(context: common.UIAbilityContext): Promise<void> {
    const startTime = Date.now();
    try {
      if (!isGlobalContextInitialized()) {
        setContext(context);
        logger.startup(TAG, 'GlobalContext 初始化完成', '接续引导已设置全局上下文');
      } else {
        logger.debug(TAG, 'GlobalContext 已就绪', '跳过重复设置全局上下文');
      }
      const dataResult = await DataInitializer.getInstance().initialize(context);
      if (!dataResult.success) {
        throw new Error(`数据系统初始化失败: ${dataResult.errors.join(', ')}`);
      }
      const settingsManager = SettingsManager.getInstance();
      if (!settingsManager.isInitialized()) {
        await settingsManager.initialize();
      }
      settingsManager.syncToAppStorage();
      await ContinuationReadingSettingsManager.getInstance().initialize(context);
      await ContinuationCacheManager.getInstance().initialize(context);
      this.completed = true;
      const duration = Date.now() - startTime;
      logger.startup(TAG, '接续引导初始化完成', `GlobalContext + 数据系统 + 设置门面就绪，耗时${duration}ms`);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `❌ 接续引导初始化失败: ${message}`);
      // 清除进行中的 Promise，允许下一次调用重试
      this.readyPromise = null;
      throw error as Error;
    }
  }
}
