/**
 * 小说模块初始化器
 * 负责小说相关组件的初始化
 * 
 * 文件路径: entry/src/main/ets/Framework/Novel/NovelInitializer.ets
 */

import { common } from '@kit.AbilityKit';
import { logger } from '../../Utils/Logger';
import { NovelDataManager, getNovelDataManager } from './NovelDataManager';
import { NovelSourceManager, getNovelSourceManager } from './NovelSourceManager';

const TAG = 'NovelInitializer';

/**
 * 初始化结果
 */
export interface NovelInitResult {
  success: boolean;
  duration: number;
  databaseInitialized: boolean;
  sourceManagerInitialized: boolean;
  errors: string[];
}

/**
 * 小说模块初始化器
 */
export class NovelInitializer {
  private static instance: NovelInitializer | null = null;
  private isInitialized: boolean = false;
  private context: common.UIAbilityContext | null = null;
  private initializationPromise: Promise<NovelInitResult> | null = null;

  private constructor() {}

  static getInstance(): NovelInitializer {
    if (!NovelInitializer.instance) {
      NovelInitializer.instance = new NovelInitializer();
    }
    return NovelInitializer.instance;
  }

  /**
   * 初始化小说模块
   */
  async initialize(context: common.UIAbilityContext): Promise<NovelInitResult> {
    if (this.isInitialized) {
      return {
        success: true,
        duration: 0,
        databaseInitialized: true,
        sourceManagerInitialized: true,
        errors: []
      };
    }
    // The bookshelf, source management and search routes can become visible
    // during the same cold start. They must observe one complete restore, not
    // race independent database/source-map hydration passes.
    if (this.initializationPromise !== null) {
      return await this.initializationPromise;
    }
    const initialization = this.initializeInternal(context);
    this.initializationPromise = initialization;
    try {
      return await initialization;
    } finally {
      if (this.initializationPromise === initialization) {
        this.initializationPromise = null;
      }
    }
  }

  private async initializeInternal(context: common.UIAbilityContext): Promise<NovelInitResult> {
    const startTime = Date.now();
    const errors: string[] = [];
    let databaseInitialized = false;
    let sourceManagerInitialized = false;

    this.context = context;
    logger.info(TAG, '开始初始化小说模块');

    // 1. 初始化数据库
    try {
      const dataManager = getNovelDataManager();
      await dataManager.initialize(context);
      databaseInitialized = true;
      logger.info(TAG, '小说数据库初始化完成');
    } catch (error) {
      const msg = `小说数据库初始化失败: ${String(error)}`;
      errors.push(msg);
      logger.error(TAG, msg);
    }

    // 2. 初始化书源管理器（内存中，无需特殊初始化）
    try {
      const sourceManager = getNovelSourceManager();
      // 从数据库加载已保存的书源
      if (databaseInitialized) {
        await this.loadSavedSources();
      }
      sourceManagerInitialized = true;
      logger.info(TAG, '小说书源管理器初始化完成');
    } catch (error) {
      const msg = `小说书源管理器初始化失败: ${String(error)}`;
      errors.push(msg);
      logger.error(TAG, msg);
    }

    const duration = Date.now() - startTime;
    const success = errors.length === 0;

    if (success) {
      this.isInitialized = true;
      logger.info(TAG, `小说模块初始化完成，耗时: ${duration}ms`);
    } else {
      logger.warn(TAG, `小说模块初始化部分失败，错误数: ${errors.length}`);
    }

    return {
      success,
      duration,
      databaseInitialized,
      sourceManagerInitialized,
      errors
    };
  }

  /**
   * 从数据库加载已保存的书源
   */
  private async loadSavedSources(): Promise<void> {
    try {
      const dataManager = getNovelDataManager();
      const sourceManager = getNovelSourceManager();
      
      const savedSources = await dataManager.getAllSources();
      for (let index = 0; index < savedSources.length; index++) {
        const source = savedSources[index];
        // 直接加载到内存，不再持久化（已经在数据库中）
        sourceManager.loadSourceToMemory(source);
        // A full Legado import may contain hundreds of sources. Keep this
        // restore cooperative so navigation and an immediately submitted
        // single-source search cannot starve the ArkUI event loop.
        if ((index + 1) % 16 === 0) {
          await this.yieldToEventLoop();
        }
      }
      const compatibilityRecords = await dataManager.getAllCompatibilityRecords();
      await sourceManager.restoreCompatibilityRecords(compatibilityRecords);
      const verificationRecords = await dataManager.getAllCompatibilityVerifications();
      await sourceManager.restoreCompatibilityVerifications(verificationRecords);
      const traceSummaries = await dataManager.getAllCompatibilityTraceSummaries();
      sourceManager.restoreExecutionTraceSummaries(traceSummaries);
      const workflowTraceSummaries = await dataManager.getAllCompatibilityTraceWorkflowSummaries();
      sourceManager.restoreExecutionTraceWorkflowSummaries(workflowTraceSummaries);
      
      logger.info(
        TAG,
        `已加载 ${savedSources.length} 个书源，恢复 ${compatibilityRecords.length} 条 V2 兼容记录、` +
        `${verificationRecords.length} 条工作流验证记录、${traceSummaries.length} 条最新脱敏 V2 trace 摘要和 ` +
        `${workflowTraceSummaries.length} 条按工作流脱敏 V2 trace 摘要`
      );
    } catch (error) {
      logger.error(TAG, `加载已保存书源失败: ${String(error)}`);
      // A partial restore would leave search and management views out of sync
      // with persisted data. Keep the module unready and let initializeInternal
      // expose the failure to its caller instead of reporting a usable module.
      throw error as Error;
    }
  }

  private async yieldToEventLoop(): Promise<void> {
    await new Promise<void>((resolve: () => void): void => {
      setTimeout(resolve, 0);
    });
  }

  /**
   * 检查是否已初始化
   */
  isReady(): boolean {
    return this.isInitialized;
  }

  /**
   * 获取上下文
   */
  getContext(): common.UIAbilityContext | null {
    return this.context;
  }

  /**
   * 重置初始化状态
   */
  reset(): void {
    this.isInitialized = false;
    this.context = null;
    logger.info(TAG, '小说模块初始化状态已重置');
  }
}

/**
 * 获取小说初始化器实例
 */
export function getNovelInitializer(): NovelInitializer {
  return NovelInitializer.getInstance();
}

/**
 * 快速初始化小说模块
 */
export async function initializeNovelModule(context: common.UIAbilityContext): Promise<NovelInitResult> {
  return getNovelInitializer().initialize(context);
}
