// 文件路径: entry/src/main/ets/Framework/Managers/WelcomeGuideManager.ets
/**
 * 欢迎引导管理器
 * 负责管理首次启动标记和引导流程
// 文件路径: entry/src/main/ets/Framework/Managers/WelcomeGuideManager.ets
/**
 * 欢迎引导管理器
 * 负责管理首次启动标记和引导流程
 */

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { getContext } from 'manxia_core/src/main/ets/GlobalContext';
import { createUserManualEBookFromRawFile, getLegacyUserManualIds, getUserManualId } from 'manxia_core/src/main/ets/Framework/Data/UserManualData';
import { EBookDataManager } from 'manxia_core/src/main/ets/Framework/Data/EBookDataManager';

const TAG = 'WelcomeGuideManager';

/**
 * 引导步骤枚举
 */
export enum GuideStep {
  WELCOME = 0,           // 欢迎页
  THEME_SELECTION = 1,   // 主题选择
  DATA_IMPORT = 2,       // Download同步引导（原数据导入引导）
  IMAGE_SOURCE_GUIDE = 3, // 图源引导
  BOOK_SOURCE_GUIDE = 4,  // 书源引导
  CUSTOM_EXPERIENCE = 5,  // 自定义体验引导
  ANALYTICS_PERMISSION = 6, // 通知权限与使用场景
  LIBRARY_INTRO = 7,     // 隐私书库与SFW模式说明
  REMOTE_LIBRARY_GUIDE = 8, // Suwayomi 与 Komga 远程书库引导
  COMPLETED = 9,         // 完成
  DISTRIBUTED_PERMISSION = 10 // 「设备发现和连接」权限引导（跨设备接续阅读）；追加在尾部编号，避免与已持久化的历史步骤值冲突
}

export enum GuideFlowMode {
  FULL = 'full',
  SOURCE_FEATURE_ONLY = 'source_feature_only'
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
  private readonly KEY_USER_MANUAL_ADDED = 'user_manual_added';
  private readonly KEY_USER_MANUAL_V5_ADDED = 'user_manual_v5_added';
  private readonly KEY_SOURCE_FEATURE_GUIDE_SHOWN = 'source_feature_guide_shown';
  private readonly KEY_ACTIVE_GUIDE_FLOW = 'active_guide_flow';

  private isFirstLaunch: boolean = true;
  private guideCompleted: boolean = false;
  private guideSkipped: boolean = false;
  private currentStep: GuideStep = GuideStep.WELCOME;
  private sourceFeatureGuideShown: boolean = false;
  private activeGuideFlow: GuideFlowMode = GuideFlowMode.FULL;
  private isInitialized: boolean = false;

  private constructor() {
    // 私有构造函数，防止外部实例化
  }

  private isSourceFeaturesEnabled(): boolean {
    const rawValue = AppStorage.get('source_features_enabled') as boolean | number | string | null | undefined;
    return rawValue === true || rawValue === 1 || rawValue === 'true' || rawValue === '1';
  }

  private isSourceFeatureStep(step: GuideStep): boolean {
    return step === GuideStep.IMAGE_SOURCE_GUIDE || step === GuideStep.BOOK_SOURCE_GUIDE;
  }

  private normalizeStep(step: GuideStep): GuideStep {
    if (!this.isSourceFeaturesEnabled() && this.isSourceFeatureStep(step)) {
      return GuideStep.CUSTOM_EXPERIENCE;
    }
    return step;
  }

  private getNextStepForCurrentStep(step: GuideStep): GuideStep {
    switch (step) {
      case GuideStep.WELCOME:
        return GuideStep.THEME_SELECTION;
      case GuideStep.THEME_SELECTION:
        return GuideStep.DATA_IMPORT;
      case GuideStep.DATA_IMPORT:
        return this.isSourceFeaturesEnabled() ? GuideStep.IMAGE_SOURCE_GUIDE : GuideStep.REMOTE_LIBRARY_GUIDE;
      case GuideStep.IMAGE_SOURCE_GUIDE:
        return GuideStep.BOOK_SOURCE_GUIDE;
      case GuideStep.BOOK_SOURCE_GUIDE:
        return GuideStep.REMOTE_LIBRARY_GUIDE;
      case GuideStep.REMOTE_LIBRARY_GUIDE:
        return GuideStep.CUSTOM_EXPERIENCE;
      case GuideStep.CUSTOM_EXPERIENCE:
        return GuideStep.ANALYTICS_PERMISSION;
      case GuideStep.ANALYTICS_PERMISSION:
        return GuideStep.DISTRIBUTED_PERMISSION;
      case GuideStep.DISTRIBUTED_PERMISSION:
        return GuideStep.LIBRARY_INTRO;
      case GuideStep.LIBRARY_INTRO:
        return GuideStep.COMPLETED;
      case GuideStep.COMPLETED:
      default:
        return GuideStep.COMPLETED;
    }
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
        this.currentStep = this.normalizeStep(savedStep as GuideStep);
        this.sourceFeatureGuideShown = await this.preferencesStore.get(this.KEY_SOURCE_FEATURE_GUIDE_SHOWN, false) as boolean;

        const savedGuideFlow = await this.preferencesStore.get(this.KEY_ACTIVE_GUIDE_FLOW, GuideFlowMode.FULL) as string;
        if (savedGuideFlow === GuideFlowMode.SOURCE_FEATURE_ONLY) {
          this.activeGuideFlow = GuideFlowMode.SOURCE_FEATURE_ONLY;
        } else {
          this.activeGuideFlow = GuideFlowMode.FULL;
        }
        if (this.guideCompleted && this.activeGuideFlow !== GuideFlowMode.SOURCE_FEATURE_ONLY) {
          this.currentStep = GuideStep.COMPLETED;
        }
        
        logger.info(TAG, `引导状态加载完成: 首次=${this.isFirstLaunch}, 完成=${this.guideCompleted}, 跳过=${this.guideSkipped}, 步骤=${this.currentStep}, 源功能引导已显示=${this.sourceFeatureGuideShown}, flow=${this.activeGuideFlow}`);
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
      await this.preferencesStore.put(this.KEY_SOURCE_FEATURE_GUIDE_SHOWN, this.sourceFeatureGuideShown);
      await this.preferencesStore.put(this.KEY_ACTIVE_GUIDE_FLOW, this.activeGuideFlow);
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
      if (!this.isInitialized) {
        await this.initialize();
      }
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
      if (!this.isInitialized) {
        await this.initialize();
      }
      this.guideCompleted = true;
      this.isFirstLaunch = false;
      this.currentStep = GuideStep.COMPLETED;
      this.activeGuideFlow = GuideFlowMode.FULL;
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
      if (!this.isInitialized) {
        await this.initialize();
      }
      this.guideSkipped = true;
      this.isFirstLaunch = false;
      this.activeGuideFlow = GuideFlowMode.FULL;
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
      if (!this.isInitialized) {
        await this.initialize();
      }
      this.isFirstLaunch = true;
      this.guideCompleted = false;
      this.guideSkipped = false;
      this.currentStep = GuideStep.WELCOME;
      this.sourceFeatureGuideShown = false;
      this.activeGuideFlow = GuideFlowMode.FULL;
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
    return this.normalizeStep(this.currentStep);
  }

  public getActiveGuideFlow(): GuideFlowMode {
    return this.activeGuideFlow;
  }

  public isSourceFeatureGuideShown(): boolean {
    return this.sourceFeatureGuideShown;
  }

  /**
   * 设置当前步骤
   */
  public async setCurrentStep(step: GuideStep): Promise<void> {
    try {
      if (!this.isInitialized) {
        await this.initialize();
      }
      this.currentStep = this.normalizeStep(step);
      await this.saveGuideState();
      logger.info(TAG, `引导步骤更新为: ${this.currentStep}`);
    } catch (error) {
      logger.error(TAG, '设置引导步骤失败', String(error));
    }
  }

  /**
   * 进入下一步
   */
  public async nextStep(): Promise<GuideStep> {
    try {
      if (!this.isInitialized) {
        await this.initialize();
      }
      if (this.currentStep !== GuideStep.COMPLETED) {
        this.currentStep = this.normalizeStep(this.getNextStepForCurrentStep(this.currentStep));
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

  public async startSourceFeatureGuide(): Promise<void> {
    try {
      if (!this.isInitialized) {
        await this.initialize();
      }
      this.sourceFeatureGuideShown = true;
      this.activeGuideFlow = GuideFlowMode.SOURCE_FEATURE_ONLY;
      this.currentStep = GuideStep.IMAGE_SOURCE_GUIDE;
      await this.saveGuideState();
      logger.info(TAG, '已启动仅源功能引导流程');
    } catch (error) {
      logger.error(TAG, `启动源功能引导失败: ${String(error)}`);
    }
  }

  public async finishSourceFeatureGuide(): Promise<void> {
    try {
      if (!this.isInitialized) {
        await this.initialize();
      }
      this.activeGuideFlow = GuideFlowMode.FULL;
      this.currentStep = this.guideCompleted ? GuideStep.COMPLETED : GuideStep.WELCOME;
      await this.saveGuideState();
      logger.info(TAG, '仅源功能引导流程已结束');
    } catch (error) {
      logger.error(TAG, `结束源功能引导失败: ${String(error)}`);
    }
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
   * 初始化使用手册（首次运行时添加到书库）
   */
  public async initializeUserManual(): Promise<void> {
    try {
      // 确保已初始化
      if (!this.isInitialized) {
        await this.initialize();
      }

      const ebookDataManager = EBookDataManager.getInstance();

      // Delete old user manual versions if they exist
      const oldManualIds = getLegacyUserManualIds();
      for (const id of oldManualIds) {
        const manual = await ebookDataManager.getEBookById(id);
        if (manual) {
          await ebookDataManager.deleteEBook(id);
          logger.info(TAG, `已清理旧版使用手册: ${id}`);
        }
      }

      const userManualId = getUserManualId();
      const existingManual = await ebookDataManager.getEBookById(userManualId);
      let userManualV5Added = false;

      // 检查是否已添加过使用手册 v5
      if (this.preferencesStore) {
        userManualV5Added = await this.preferencesStore.get(this.KEY_USER_MANUAL_V5_ADDED, false) as boolean;
      }

      if (existingManual) {
        logger.info(TAG, '使用手册已存在于书库中，标记为已添加');
        if (this.preferencesStore) {
          if (!userManualV5Added) {
            await this.preferencesStore.put(this.KEY_USER_MANUAL_V5_ADDED, true);
          }
          await this.preferencesStore.put(this.KEY_USER_MANUAL_ADDED, true);
          await this.preferencesStore.flush();
        }
        return;
      }

      if (userManualV5Added) {
        logger.warn(TAG, '新版 MD 使用手册偏好标记已存在，但数据库未找到记录，重新写入内置手册');
      }

      // 创建并添加使用手册
      const userManual = await createUserManualEBookFromRawFile();
      await ebookDataManager.saveEBook(userManual);
      
      // 标记为已添加
      if (this.preferencesStore) {
        await this.preferencesStore.put(this.KEY_USER_MANUAL_V5_ADDED, true);
        await this.preferencesStore.put(this.KEY_USER_MANUAL_ADDED, true);
        await this.preferencesStore.flush();
      }

      logger.info(TAG, '✅ 使用手册已成功添加到书库');
    } catch (error) {
      logger.error(TAG, '初始化使用手册失败', String(error));
      // 不抛出错误，避免影响应用启动
    }
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
