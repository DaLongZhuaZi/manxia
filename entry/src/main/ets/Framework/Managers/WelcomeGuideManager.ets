// 文件路径: entry/src/main/ets/Framework/Managers/WelcomeGuideManager.ets
/**
 * 欢迎引导管理器
 * 负责管理首次启动标记和引导流程
 */

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { logger } from '../../Utils/Logger';
import { getContext } from '../../GlobalContext';

const TAG = 'WelcomeGuideManager';

/**
 * 引导步骤枚举
 */
export enum GuideStep {
  WELCOME = 0,           // 欢迎页
  THEME_SELECTION = 1,   // 主题选择
  DATA_IMPORT = 2,       // 数据导入引导
  LOG_EXPORT = 3,        // 日志导出引导
  ANALYTICS_PERMISSION = 4, // 阅读报告权限询问
  LIBRARY_INTRO = 5,     // 书库介绍
  COMPLETED = 6          // 完成
}

/**
 * 引导配置接口
 */
export interface GuideConfig {
  currentStep: GuideStep;
  completed: boolean;
  skipped: boolean;
  lastShowTime: number;
}

/**
 * 欢迎引导管理器类
 */
export class WelcomeGuideManager {
  private static instance: WelcomeGuideManager | null = null;
  private preferencesStore: preferences.Preferences | null = null;
  private readonly PREFERENCES_NAME = 'welcome_guide_preferences';
  private readonly KEY_FIRST_LAUNCH = 'is_first_launch';
  private readonly KEY_GUIDE_COMPLETED = 'guide_completed';
  private readonly KEY_GUIDE_SKIPPED = 'guide_skipped';
  private readonly KEY_CURRENT_STEP = 'current_guide_step';
  private readonly KEY_LAST_SHOW_TIME = 'last_show_time';

  private isFirstLaunch: boolean = true;
  private guideCompleted: boolean = false;
  private guideSkipped: boolean = false;
  private currentStep: GuideStep = GuideStep.WELCOME;
  private isInitialized: boolean = false;

  private constructor() {
    // 私有构造函数，防止外部实例化
  }

  /**
   * 获取单例实例
   */
  public static getInstance(): WelcomeGuideManager {
    if (!WelcomeGuideManager.instance) {
      WelcomeGuideManager.instance = new WelcomeGuideManager();
    }
    return WelcomeGuideManager.instance;
  }

  /**
   * 初始化管理器
   */
  public async initialize(): Promise<void> {
    if (this.isInitialized) {
      logger.debug(TAG, '欢迎引导管理器已初始化，跳过');
      return;
    }

    try {
      logger.info(TAG, '开始初始化欢迎引导管理器');
      
      // 初始化Preferences
      await this.initializePreferences();
      
      // 加载引导状态
      await this.loadGuideState();
      
      this.isInitialized = true;
      logger.info(TAG, `欢迎引导管理器初始化完成，首次启动: ${this.isFirstLaunch}, 引导完成: ${this.guideCompleted}`);
    } catch (error) {
      logger.error(TAG, '初始化欢迎引导管理器失败', String(error));
      // 初始化失败，使用默认值
      this.isFirstLaunch = true;
      this.guideCompleted = false;
      this.isInitialized = true;
    }
  }

  /**
   * 初始化Preferences存储
   */
  private async initializePreferences(): Promise<void> {
    try {
      const context = getContext();
      this.preferencesStore = await preferences.getPreferences(context, this.PREFERENCES_NAME);
      logger.info(TAG, 'Preferences存储初始化成功');
    } catch (error) {
      logger.error(TAG, 'Preferences存储初始化失败', String(error));
      throw error as Error;
    }
  }

  /**
   * 加载引导状态
   */
  private async loadGuideState(): Promise<void> {
    try {
      if (!this.preferencesStore) {
        await this.initializePreferences();
      }

      if (this.preferencesStore) {
        // 读取首次启动标记
        this.isFirstLaunch = await this.preferencesStore.get(this.KEY_FIRST_LAUNCH, true) as boolean;
        
        // 读取引导完成标记
        this.guideCompleted = await this.preferencesStore.get(this.KEY_GUIDE_COMPLETED, false) as boolean;
        
        // 读取引导跳过标记
        this.guideSkipped = await this.preferencesStore.get(this.KEY_GUIDE_SKIPPED, false) as boolean;
        
        // 读取当前步骤
        const savedStep = await this.preferencesStore.get(this.KEY_CURRENT_STEP, GuideStep.WELCOME) as number;
        this.currentStep = savedStep as GuideStep;
        
        logger.info(TAG, `引导状态加载完成: 首次=${this.isFirstLaunch}, 完成=${this.guideCompleted}, 跳过=${this.guideSkipped}, 步骤=${this.currentStep}`);
      }
    } catch (error) {
      logger.error(TAG, '加载引导状态失败', String(error));
      throw error as Error;
    }
  }

  /**
   * 保存引导状态
   */
  private async saveGuideState(): Promise<void> {
    try {
      if (!this.preferencesStore) {
        logger.warn(TAG, 'Preferences存储未初始化，无法保存引导状态');
        return;
      }

      await this.preferencesStore.put(this.KEY_FIRST_LAUNCH, this.isFirstLaunch);
      await this.preferencesStore.put(this.KEY_GUIDE_COMPLETED, this.guideCompleted);
      await this.preferencesStore.put(this.KEY_GUIDE_SKIPPED, this.guideSkipped);
      await this.preferencesStore.put(this.KEY_CURRENT_STEP, this.currentStep);
      await this.preferencesStore.put(this.KEY_LAST_SHOW_TIME, Date.now());
      await this.preferencesStore.flush();
      
      logger.info(TAG, '引导状态保存成功');
    } catch (error) {
      logger.error(TAG, '保存引导状态失败', String(error));
    }
  }

  /**
   * 检查是否首次启动
   */
  public isFirstTimeLaunch(): boolean {
    return this.isFirstLaunch && !this.guideCompleted && !this.guideSkipped;
  }

  /**
   * 检查是否需要显示引导
   */
  public shouldShowGuide(): boolean {
    return this.isFirstTimeLaunch();
  }

  /**
   * 标记为非首次启动
   */
  public async markNotFirstLaunch(): Promise<void> {
    try {
      this.isFirstLaunch = false;
      await this.saveGuideState();
      logger.info(TAG, '已标记为非首次启动');
    } catch (error) {
      logger.error(TAG, '标记非首次启动失败', String(error));
    }
  }

  /**
   * 标记引导完成
   */
  public async markGuideCompleted(): Promise<void> {
    try {
      this.guideCompleted = true;
      this.isFirstLaunch = false;
      this.currentStep = GuideStep.COMPLETED;
      await this.saveGuideState();
      logger.info(TAG, '引导流程已完成');
    } catch (error) {
      logger.error(TAG, '标记引导完成失败', String(error));
    }
  }

  /**
   * 跳过引导
   */
  public async skipGuide(): Promise<void> {
    try {
      this.guideSkipped = true;
      this.isFirstLaunch = false;
      await this.saveGuideState();
      logger.info(TAG, '用户跳过了引导流程');
    } catch (error) {
      logger.error(TAG, '跳过引导失败', String(error));
    }
  }

  /**
   * 重置引导状态（用于测试）
   */
  public async resetGuide(): Promise<void> {
    try {
      this.isFirstLaunch = true;
      this.guideCompleted = false;
      this.guideSkipped = false;
      this.currentStep = GuideStep.WELCOME;
      await this.saveGuideState();
      logger.info(TAG, '引导状态已重置');
    } catch (error) {
      logger.error(TAG, '重置引导状态失败', String(error));
    }
  }

  /**
   * 获取当前步骤
   */
  public getCurrentStep(): GuideStep {
    return this.currentStep;
  }

  /**
   * 设置当前步骤
   */
  public async setCurrentStep(step: GuideStep): Promise<void> {
    try {
      this.currentStep = step;
      await this.saveGuideState();
      logger.info(TAG, `引导步骤更新为: ${step}`);
    } catch (error) {
      logger.error(TAG, '设置引导步骤失败', String(error));
    }
  }

  /**
   * 进入下一步
   */
  public async nextStep(): Promise<GuideStep> {
    try {
      if (this.currentStep < GuideStep.COMPLETED) {
        this.currentStep = this.currentStep + 1;
        await this.saveGuideState();
        logger.info(TAG, `进入下一步: ${this.currentStep}`);
      }
      return this.currentStep;
    } catch (error) {
      logger.error(TAG, '进入下一步失败', String(error));
      return this.currentStep;
    }
  }

  /**
   * 获取引导配置
   */
  public getGuideConfig(): GuideConfig {
    return {
      currentStep: this.currentStep,
      completed: this.guideCompleted,
      skipped: this.guideSkipped,
      lastShowTime: Date.now()
    };
  }

  /**
   * 检查引导是否完成
   */
  public isGuideCompleted(): boolean {
    return this.guideCompleted;
  }

  /**
   * 检查引导是否被跳过
   */
  public isGuideSkipped(): boolean {
    return this.guideSkipped;
  }

  /**
   * 销毁实例
   */
  public static destroyInstance(): void {
    if (WelcomeGuideManager.instance) {
      WelcomeGuideManager.instance.preferencesStore = null;
      WelcomeGuideManager.instance = null;
      logger.info(TAG, '欢迎引导管理器实例已销毁');
    }
  }
}

// 导出单例实例
export const welcomeGuideManager = WelcomeGuideManager.getInstance();

