// 文件路径: entry/src/main/ets/pages/WelcomeGuidePage.ets
/**
 * 欢迎引导页面
 * 首次启动时的引导页面，引导用户了解应用功能
 */

import { logger } from '../Utils/Logger';
import { ThemeManager, ThemeType, CustomThemeData } from '../Framework/Managers/ThemeManager';
import { ThemeAwareHelper, ThemeAwareState } from '../Framework/Components/ThemeAware';
import { WelcomeGuideManager, GuideStep } from '../Framework/Managers/WelcomeGuideManager';
import { common } from '@kit.AbilityKit';

const TAG = 'WelcomeGuidePage';

/**
 * 引导步骤内容接口
 */
interface GuideStepContent {
  title: string;
  subtitle: string;
  description: string;
  icon: ResourceStr;
  buttonText: string;
  showSkip: boolean;
}

@Entry
@Component
struct WelcomeGuidePage {
  // 沉浸式显示状态属性
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;

  // 主题相关状态
  @State private themeState: ThemeAwareState = new ThemeAwareState();
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private componentId: string = 'WelcomeGuidePage';

  // 引导管理器
  private welcomeGuideManager: WelcomeGuideManager = WelcomeGuideManager.getInstance();

  // 页面状态
  @State private currentStep: GuideStep = GuideStep.WELCOME;
  @State private isAnimating: boolean = false;
  @State private contentOpacity: number = 0;
  @State private contentTranslateY: number = 50;
  @State private buttonClickTrigger: number = 0;  // 按钮点击触发器，用于强制更新

  private uiContext: UIContext | undefined = undefined;

  // 引导步骤内容 - 使用set方法逐个添加以符合ArkTS规范
  private readonly guideSteps: Map<GuideStep, GuideStepContent> = this.initGuideSteps();

  /**
   * 初始化引导步骤内容
   */
  private initGuideSteps(): Map<GuideStep, GuideStepContent> {
    const steps = new Map<GuideStep, GuideStepContent>();
    
    const welcomeContent: GuideStepContent = {
      title: '欢迎参与漫匣首次测试',
      subtitle: '感谢您的支持',
      description: '漫匣是一款专注于本地漫画管理和阅读的应用。接下来将引导您快速了解应用的核心功能。',
      icon: $r('app.media.icon'),
      buttonText: '开始引导',
      showSkip: true
    };
    steps.set(GuideStep.WELCOME, welcomeContent);

    const themeSelectionContent: GuideStepContent = {
      title: '主题选择',
      subtitle: '选择一个您喜欢的风格',
      description: '您可以在下方选择默认的两套自定义主题之一进行应用，或点击按钮前往自定义主题页面进行更细致的个性化设置。',
      icon: $r('app.media.icon'),
      buttonText: '继续下一步',
      showSkip: true
    };
    steps.set(GuideStep.THEME_SELECTION, themeSelectionContent);
    
    const dataImportContent: GuideStepContent = {
      title: '导入本地漫画',
      subtitle: '管理您的漫画收藏',
      description: '您可以导入本地的漫画文件（支持CBZ格式），应用会自动解析漫画信息并组织管理。点击下方按钮前往数据管理页面。',
      icon: $r('app.media.ic_guide_import'),
      buttonText: '前往导入',
      showSkip: true
    };
    steps.set(GuideStep.DATA_IMPORT, dataImportContent);
    
    const logExportContent: GuideStepContent = {
      title: '日志管理',
      subtitle: '帮助我们改进',
      description: '在使用过程中如遇到问题，您可以在日志管理页面导出日志文件，并附上截图和详细的问题描述，以便我们更好地为您解决问题。',
      icon: $r('app.media.ic_guide_log'),
      buttonText: '查看日志',
      showSkip: true
    };
    steps.set(GuideStep.LOG_EXPORT, logExportContent);
    
    const libraryIntroContent: GuideStepContent = {
      title: '开始阅读',
      subtitle: '探索您的书库',
      description: '现在，您可以在书库页面查看已导入的漫画，点击封面即可开始阅读。祝您阅读愉快！',
      icon: $r('app.media.ic_guide_library'),
      buttonText: '进入书库',
      showSkip: false
    };
    steps.set(GuideStep.LIBRARY_INTRO, libraryIntroContent);
    
    return steps;
  }

  aboutToAppear(): void {
    logger.lifecycle(TAG, '欢迎引导页面开始加载');
    
    // 获取UIContext
    this.uiContext = this.getUIContext();
    if (!this.uiContext) {
      logger.error(TAG, '获取UIContext失败');
      return;
    }

    // 初始化主题
    this.initializeTheme();

    // 加载当前步骤（从WelcomeGuideManager获取最新状态）
    this.currentStep = this.welcomeGuideManager.getCurrentStep();
    logger.info(TAG, `欢迎引导页面加载，当前引导步骤: ${this.currentStep}`);

    // 启动入场动画
    this.startEntranceAnimation();
  }
  
  onPageShow(): void {
    logger.lifecycle(TAG, '欢迎引导页面显示');
    
    // 每次页面显示时重新加载当前步骤（用于从其他页面返回后恢复状态）
    const latestStep = this.welcomeGuideManager.getCurrentStep();
    if (latestStep !== this.currentStep) {
      logger.info(TAG, `引导步骤已更新: ${this.currentStep} -> ${latestStep}`);
      this.currentStep = latestStep;
      
      // 重新启动入场动画
      this.contentOpacity = 0;
      this.contentTranslateY = 30;
      setTimeout(() => {
        this.startEntranceAnimation();
      }, 100);
    }
  }

  /**
   * 初始化主题
   */
  private async initializeTheme(): Promise<void> {
    try {
      await ThemeAwareHelper.initializeThemeAware(
        this.componentId,
        this.themeState,
        (newTheme: ThemeType) => {
          logger.info(TAG, `主题切换到: ${newTheme}`);
        },
        (newState: ThemeAwareState) => {
          this.themeState = newState;
        }
      );
    } catch (error) {
      logger.error(TAG, '初始化主题失败', String(error));
    }
  }

  /**
   * 启动入场动画
   */
  private startEntranceAnimation(): void {
    if (!this.uiContext) return;

    setTimeout(() => {
      if (!this.uiContext) return;

      const animateOptions: AnimateParam = {
        duration: 800,
        curve: Curve.EaseOut,
        iterations: 1,
        playMode: PlayMode.Normal
      };

      this.uiContext.animateTo(animateOptions, () => {
        this.contentOpacity = 1.0;
        this.contentTranslateY = 0;
      });
    }, 100);
  }

  /**
   * 步骤切换动画
   */
  private animateStepChange(callback: () => void): void {
    if (!this.uiContext || this.isAnimating) return;

    this.isAnimating = true;

    // 淡出动画
    const fadeOutOptions: AnimateParam = {
      duration: 300,
      curve: Curve.EaseIn,
      iterations: 1,
      playMode: PlayMode.Normal
    };

    this.uiContext.animateTo(fadeOutOptions, () => {
      this.contentOpacity = 0;
      this.contentTranslateY = -30;
    });

    // 等待淡出完成后执行回调并淡入
    setTimeout(() => {
      callback();

      if (!this.uiContext) {
        this.isAnimating = false;
        return;
      }

      // 重置位置
      this.contentTranslateY = 30;

      setTimeout(() => {
        if (!this.uiContext) {
          this.isAnimating = false;
          return;
        }

        const fadeInOptions: AnimateParam = {
          duration: 400,
          curve: Curve.EaseOut,
          iterations: 1,
          playMode: PlayMode.Normal
        };

        this.uiContext.animateTo(fadeInOptions, () => {
          this.contentOpacity = 1.0;
          this.contentTranslateY = 0;
          this.isAnimating = false;
        });
      }, 50);
    }, 300);
  }

  /**
   * 处理下一步按钮点击
   */
  private handleNextStep(): void {
    logger.info(TAG, `🔘 handleNextStep 被调用，当前步骤: ${this.currentStep}`);
    
    const stepContent = this.guideSteps.get(this.currentStep);
    if (!stepContent) {
      logger.error(TAG, `❌ 无法获取步骤内容，当前步骤: ${this.currentStep}`);
      return;
    }

    logger.info(TAG, `点击按钮: ${stepContent.buttonText}, 当前步骤: ${this.currentStep}, 动画状态: ${this.isAnimating}`);

    // 如果动画正在进行，防止重复点击
    if (this.isAnimating) {
      logger.warn(TAG, '⚠️ 动画进行中，忽略点击事件');
      return;
    }

    switch (this.currentStep) {
      case GuideStep.WELCOME:
        // 欢迎页，进入数据导入引导
        logger.debug(TAG, '执行 WELCOME 步骤处理');
        this.animateStepChange(() => {
          this.currentStep = GuideStep.THEME_SELECTION;
          this.welcomeGuideManager.setCurrentStep(GuideStep.THEME_SELECTION);
          logger.info(TAG, `步骤已更新到: ${this.currentStep}`);
        });
        break;

      case GuideStep.THEME_SELECTION:
        // 主题选择页，点击主按钮进入数据导入
        logger.debug(TAG, '执行 THEME_SELECTION 步骤处理');
        this.animateStepChange(() => {
          this.currentStep = GuideStep.DATA_IMPORT;
          this.welcomeGuideManager.setCurrentStep(GuideStep.DATA_IMPORT);
          logger.info(TAG, `步骤已更新到: ${this.currentStep}`);
        });
        break;

      case GuideStep.DATA_IMPORT:
        // 导航到数据管理页面
        logger.debug(TAG, '执行 DATA_IMPORT 步骤处理，准备导航到数据管理页面');
        this.navigateToDataManagement();
        break;

      case GuideStep.LOG_EXPORT:
        // 导航到日志管理页面
        logger.debug(TAG, '执行 LOG_EXPORT 步骤处理，准备导航到日志管理页面');
        this.navigateToLogManager();
        break;

      case GuideStep.LIBRARY_INTRO:
        // 完成引导，进入主页面的书库标签
        logger.debug(TAG, '执行 LIBRARY_INTRO 步骤处理，准备完成引导');
        this.completeGuide();
        break;

      default:
        logger.warn(TAG, `未知的引导步骤: ${this.currentStep}`);
        break;
    }
  }

  /**
   * 跳过引导
   */
  private skipGuide(): void {
    logger.info(TAG, '用户选择跳过引导');
    this.welcomeGuideManager.skipGuide();
    this.navigateToMainMenu();
  }

  /**
   * 完成引导
   */
  private completeGuide(): void {
    logger.info(TAG, '引导流程完成');
    this.welcomeGuideManager.markGuideCompleted();
    this.navigateToMainMenu();
  }

  /**
   * 导航到数据管理页面
   */
  private navigateToDataManagement(): void {
    try {
      // 更新步骤到日志导出
      this.welcomeGuideManager.setCurrentStep(GuideStep.LOG_EXPORT);

      const router = this.uiContext?.getRouter();
      if (router) {
        router.pushUrl({
          url: 'pages/MainMenuPage',
          params: {
            targetPage: 'DataManagementPage',
            fromGuide: true
          }
        }).then(() => {
          logger.info(TAG, '导航到数据管理页面成功');
        }).catch((error: Error) => {
          logger.error(TAG, '导航到数据管理页面失败', error.message);
        });
      }
    } catch (error) {
      logger.error(TAG, '导航到数据管理页面异常', String(error));
    }
  }

  /**
   * 导航到自定义主题设置页面
   */
  private navigateToThemeSettings(): void {
    try {
      const router = this.uiContext?.getRouter();
      if (router) {
        router.pushUrl({
          url: 'pages/MainMenuPage',
          params: {
            targetPage: 'ThemeSettingsPage',
            fromGuide: true
          }
        }).then(() => {
          logger.info(TAG, '导航到自定义主题设置页面成功');
        }).catch((error: Error) => {
          logger.error(TAG, '导航到自定义主题设置页面失败', error.message);
        });
      }
    } catch (error) {
      logger.error(TAG, '导航到自定义主题设置页面异常', String(error));
    }
  }

  /**
   * 应用预设自定义主题：默认主题（A 系列）
   * 使用媒体资源回退展示（a_*），不设置文件路径
   */
  private async applyCustomThemePresetA(): Promise<void> {
    try {
      const data: CustomThemeData = {
        id: 'default_custom_theme',
        name: '默认自定义主题',
        backgroundImagePath: '',
        backgroundImagePathDark: '',
        splashBackgroundImagePath: '',
        blurLevel: 12,
        primaryColor: '#007AFF',
        isDark: false,
        createTime: Date.now(),
        lastModified: Date.now()
      };
      await this.themeManager.applyCustomTheme(data);
      logger.info(TAG, '已应用默认自定义主题（A 系列，媒体资源回退）');

      // 主题应用成功后，若当前为主题选择步骤，则自动切换到下一步（数据导入）
      if (this.currentStep === GuideStep.THEME_SELECTION) {
        if (this.isAnimating) {
          logger.warn(TAG, '动画进行中，暂不切换到下一步');
          return;
        }
        this.animateStepChange(() => {
          this.currentStep = GuideStep.DATA_IMPORT;
          this.welcomeGuideManager.setCurrentStep(GuideStep.DATA_IMPORT);
          logger.info(TAG, `主题应用后已切换到下一步: ${this.currentStep}`);
        });
      }
    } catch (error) {
      const msg: string = error instanceof Error ? error.message : String(error);
      logger.error(TAG, '应用默认自定义主题失败', msg);
    }
  }

  /**
   * 应用预设自定义主题：次级主题（B 系列）
   * 使用媒体资源回退展示（b_*），不设置文件路径
   */
  private async applyCustomThemePresetB(): Promise<void> {
    try {
      const data: CustomThemeData = {
        id: 'secondary_custom_theme',
        name: '次级自定义主题',
        backgroundImagePath: '',
        backgroundImagePathDark: '',
        splashBackgroundImagePath: '',
        blurLevel: 12,
        primaryColor: '#0A84FF',
        isDark: true,
        createTime: Date.now(),
        lastModified: Date.now()
      };
      await this.themeManager.applyCustomTheme(data);
      logger.info(TAG, '已应用次级自定义主题（B 系列，媒体资源回退）');

      // 主题应用成功后，若当前为主题选择步骤，则自动切换到下一步（数据导入）
      if (this.currentStep === GuideStep.THEME_SELECTION) {
        if (this.isAnimating) {
          logger.warn(TAG, '动画进行中，暂不切换到下一步');
          return;
        }
        this.animateStepChange(() => {
          this.currentStep = GuideStep.DATA_IMPORT;
          this.welcomeGuideManager.setCurrentStep(GuideStep.DATA_IMPORT);
          logger.info(TAG, `主题应用后已切换到下一步: ${this.currentStep}`);
        });
      }
    } catch (error) {
      const msg: string = error instanceof Error ? error.message : String(error);
      logger.error(TAG, '应用次级自定义主题失败', msg);
    }
  }

  /**
   * 导航到日志管理页面
   */
  private navigateToLogManager(): void {
    try {
      // 更新步骤到书库介绍
      this.welcomeGuideManager.setCurrentStep(GuideStep.LIBRARY_INTRO);

      const router = this.uiContext?.getRouter();
      if (router) {
        router.pushUrl({
          url: 'pages/MainMenuPage',
          params: {
            targetPage: 'LogManagerPage',
            fromGuide: true
          }
        }).then(() => {
          logger.info(TAG, '导航到日志管理页面成功');
        }).catch((error: Error) => {
          logger.error(TAG, '导航到日志管理页面失败', error.message);
        });
      }
    } catch (error) {
      logger.error(TAG, '导航到日志管理页面异常', String(error));
    }
  }

  /**
   * 导航到主页面
   */
  private navigateToMainMenu(): void {
    try {
      const router = this.uiContext?.getRouter();
      if (router) {
        router.replaceUrl({
          url: 'pages/MainMenuPage',
          params: {
            fromGuide: true,
            targetTab: 1 // 书库标签的索引
          }
        }).then(() => {
          logger.info(TAG, '导航到主页面成功');
        }).catch((error: Error) => {
          logger.error(TAG, '导航到主页面失败', error.message);
        });
      }
    } catch (error) {
      logger.error(TAG, '导航到主页面异常', String(error));
    }
  }

  /**
   * 获取当前步骤内容
   */
  private getCurrentStepContent(): GuideStepContent {
    return this.guideSteps.get(this.currentStep) ?? {
      title: '欢迎',
      subtitle: '',
      description: '',
      icon: $r('app.media.icon'),
      buttonText: '继续',
      showSkip: true
    };
  }

  aboutToDisappear(): void {
    logger.lifecycle(TAG, '欢迎引导页面即将销毁');
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
  }

  build() {
    // 沉浸式显示设计：Stack双层布局
    Stack() {
      // 背景层 - 扩展到系统栏区域
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_primary', this.themeState.currentTheme))
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      // 内容层 - 预留安全区域
      Column() {
        // 主要内容区域（主题选择步骤采用专用布局）
        Column() {
          if (this.currentStep === GuideStep.THEME_SELECTION) {
            // 标题
            Text(this.getCurrentStepContent().title)
              .fontSize(28)
              .fontWeight(FontWeight.Bold)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .margin({ bottom: 8 })

            // 副标题
            Text(this.getCurrentStepContent().subtitle)
              .fontSize(16)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .margin({ bottom: 16 })

            // 描述
            Text(this.getCurrentStepContent().description)
              .fontSize(14)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .textAlign(TextAlign.Center)
              .lineHeight(24)
              .padding({ left: 32, right: 32 })
              .margin({ bottom: 24 })

            // 两个主题演示卡片
            Row({ space: 16 }) {
              // 主题一（A 系列）
              Column() {
                Image($r('app.media.a_2'))
                  .width(160)
                  .height(100)
                  .objectFit(ImageFit.Cover)
                  .borderRadius(12)
                  .margin({ bottom: 8 })

                Button('应用主题一')
                  .fontSize(14)
                  .height(40)
                  .width(160)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
                  .borderRadius(20)
                  .onClick(() => {
                    this.applyCustomThemePresetA();
                  })
              }

              // 主题二（B 系列）
              Column() {
                Image($r('app.media.b_2'))
                  .width(160)
                  .height(100)
                  .objectFit(ImageFit.Cover)
                  .borderRadius(12)
                  .margin({ bottom: 8 })

                Button('应用主题二')
                  .fontSize(14)
                  .height(40)
                  .width(160)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
                  .borderRadius(20)
                  .onClick(() => {
                    this.applyCustomThemePresetB();
                  })
              }
            }
            .margin({ bottom: 16 })

            // 前往自定义主题设置
            Text('前往自定义主题页面')
              .fontSize(14)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
              .textAlign(TextAlign.Center)
              .margin({ top: 8, bottom: 24 })
              .onClick(() => {
                this.navigateToThemeSettings();
              })
          } else {
            // 默认步骤布局
            Image(this.getCurrentStepContent().icon)
              .width(120)
              .height(120)
              .objectFit(ImageFit.Contain)
              .margin({ bottom: 32 })

            Text(this.getCurrentStepContent().title)
              .fontSize(28)
              .fontWeight(FontWeight.Bold)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .margin({ bottom: 12 })

            Text(this.getCurrentStepContent().subtitle)
              .fontSize(16)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .margin({ bottom: 24 })

            Text(this.getCurrentStepContent().description)
              .fontSize(14)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .textAlign(TextAlign.Center)
              .lineHeight(24)
              .padding({ left: 32, right: 32 })
              .margin({ bottom: 48 })
          }
        }
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .layoutWeight(1)
        .opacity(this.contentOpacity)
        .translate({ y: this.contentTranslateY })

        // 底部按钮区域
        Column({ space: 12 }) {
          // 主要操作按钮 - 暂时使用普通Button来排查AnimatedButton的问题
          Button(this.getCurrentStepContent().buttonText)
            .fontSize(16)
            .height(48)
            .width('80%')
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
            .borderRadius(24)
            .enabled(!this.isAnimating)  // 动画期间禁用按钮
            .opacity(this.isAnimating ? 0.6 : 1.0)
            .onClick(() => {
              logger.info(TAG, `🔘 Button点击回调触发，当前步骤: ${this.currentStep}, 按钮文本: ${this.getCurrentStepContent().buttonText}`);
              this.handleNextStep();
            })

          // 跳过按钮
          if (this.getCurrentStepContent().showSkip) {
            Text('跳过引导')
              .fontSize(14)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              .margin({ top: 8 })
              .opacity(this.isAnimating ? 0.5 : 1.0)  // 动画期间降低透明度
              .enabled(!this.isAnimating)  // 动画期间禁用
              .onClick(() => {
                if (!this.isAnimating) {
                  logger.info(TAG, '🔘 跳过按钮点击');
                  this.skipGuide();
                }
              })
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .padding({ bottom: 32 })
      }
      .width('100%')
      .height('100%')
      .padding({
        top: this.statusBarHeight,
        bottom: this.navigationBarHeight
      })
    }
    .width('100%')
    .height('100%')
  }
}

export { WelcomeGuidePage };

