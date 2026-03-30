// 文件路径: entry/src/main/ets/pages/WelcomeGuidePage.ets
/**
 * 欢迎引导页面
 * 首次启动时的引导页面，引导用户了解应用功能
 */

import { logger } from '../Utils/Logger';
import { PageLifecycleManager } from '../Framework/Lifecycle';
import { ThemeManager, ThemeType, CustomThemeData } from '../Framework/Managers/ThemeManager';
import { ThemeAwareHelper, ThemeAwareState } from '../Framework/Components/ThemeAware';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';
import { WelcomeGuideManager, GuideStep } from '../Framework/Managers/WelcomeGuideManager';
import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { promptAction } from '@kit.ArkUI';

const TAG = 'WelcomeGuidePage';
const SOURCE_REPO_URL = 'https://raw.githubusercontent.com/DaLongZhuaZi/manxia-extensions-source/master/index.main.json';

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
  @State private fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @StorageLink('source_features_enabled') sourceFeaturesEnabled: boolean = false;
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

  /**
   * 初始化引导步骤内容
   */
  private initGuideSteps(): Map<GuideStep, GuideStepContent> {
    const steps = new Map<GuideStep, GuideStepContent>();

    const welcomeContent: GuideStepContent = {
      title: '欢迎您使用漫匣',
      subtitle: '感谢您的支持',
      description: this.sourceFeaturesEnabled
        ? '漫匣是一款专注于漫画、电子书管理和阅读的开源免费应用，支持本地导入与图源、书源。接下来将引导您快速了解应用的核心功能。'
        : '漫匣是一款专注于漫画、电子书管理和阅读的开源免费应用，支持本地导入。接下来将引导您快速了解应用的核心功能。',
      icon: $r('sys.symbol.books_vertical_fill'),
      buttonText: '开始引导流程',
      showSkip: false
    };
    steps.set(GuideStep.WELCOME, welcomeContent);

    const themeSelectionContent: GuideStepContent = {
      title: '主题选择',
      subtitle: '选择一个您喜欢的风格',
      description: '您可以先在这里直接选择默认提供的两套主题预设之一，快速完成初始风格设置。后续如果需要更细致地调整透明度、背景或视觉效果，也可以再从设置页进入对应页面慢慢微调。',
      icon: $r('sys.symbol.paintpalette'),
      buttonText: '继续下一步',
      showSkip: false
    };
    steps.set(GuideStep.THEME_SELECTION, themeSelectionContent);

    const dataImportContent: GuideStepContent = {
      title: '从Download同步',
      subtitle: '导入您的漫画与电子书',
      description: '您可以将漫画文件（支持CBZ等格式压缩包）和电子书（TXT、EPUB、MOBI、AZW3、PDF等）放置到Download文件夹下的“漫匣”文件夹当中，然后通过Download同步功能导入到书库。点击下方按钮前往Download同步页面。',
      icon: $r('sys.symbol.square_and_arrow_down'),
      buttonText: '前往Download同步',
      showSkip: false
    };
    steps.set(GuideStep.DATA_IMPORT, dataImportContent);

    if (this.sourceFeaturesEnabled) {
      const imageSourceGuideContent: GuideStepContent = {
        title: '图源说明',
        subtitle: '了解图源支持情况',
        description: '漫匣仅支持使用自有图源。图源用于获取在线漫画内容，不同图源提供不同源站的漫画资源。点击主页面底栏中的「图源」，然后点击“图源导入”，输入下面的仓库地址即可同步仓库（需要科学网络）。',
        icon: $r('sys.symbol.rectangle_stack'),
        buttonText: '下一步',
        showSkip: false
      };
      steps.set(GuideStep.IMAGE_SOURCE_GUIDE, imageSourceGuideContent);

      const bookSourceGuideContent: GuideStepContent = {
        title: '书源说明',
        subtitle: '了解书源支持情况',
        description: '漫匣支持开源阅读（Legado）的大部分书源（聚合书源除外），您可以在后续需要在线小说时，再从对应功能页进入书源相关设置与使用流程。这里先帮助您建立整体认知，避免欢迎引导阶段跳转过多页面。',
        icon: $r('sys.symbol.text_book_closed'),
        buttonText: '继续下一步',
        showSkip: false
      };
      steps.set(GuideStep.BOOK_SOURCE_GUIDE, bookSourceGuideContent);
    }

    // 自定义体验引导步骤
    const customExperienceContent: GuideStepContent = {
      title: '自定义体验',
      subtitle: '打造专属于您的阅读体验',
      description: '漫匣支持丰富的自定义设置，包括自定义字体、自定义页面布局、自定义底栏标签、主题颜色等。您可以在设置页面中根据个人喜好进行调整。点击下方按钮前往全局设置页面。',
      icon: $r('sys.symbol.slider_horizontal_2_square'),
      buttonText: '前往全局设置',
      showSkip: false
    };
    steps.set(GuideStep.CUSTOM_EXPERIENCE, customExperienceContent);

    const analyticsPermissionContent: GuideStepContent = {
      title: '阅读报告',
      subtitle: '了解您的阅读习惯',
      description: '开启阅读报告功能后，应用将收集您的阅读时长、阅读偏好等数据，在本地分析处理后为您生成个性化的阅读分析报告。此功能默认关闭，您可以随时进入报告页面中更改。',
      icon: $r('sys.symbol.histogram_fill'),
      buttonText: '继续',
      showSkip: false
    };
    steps.set(GuideStep.ANALYTICS_PERMISSION, analyticsPermissionContent);

    const libraryIntroContent: GuideStepContent = {
      title: '开始阅读',
      subtitle: '探索您的书库',
      description: this.sourceFeaturesEnabled
        ? '现在，您可以在书库页面查看已导入的漫画与电子书，或者从图源/书源当中获取，点击封面即可前往详情页开始阅读。祝您阅读愉快！'
        : '现在，您可以在书库页面查看已导入的漫画与电子书，点击封面即可前往详情页开始阅读。祝您阅读愉快！',
      icon: $r('sys.symbol.books_vertical_fill'),
      buttonText: '进入书库',
      showSkip: false
    };
    steps.set(GuideStep.LIBRARY_INTRO, libraryIntroContent);

    return steps;
  }

  private getGuideSteps(): Map<GuideStep, GuideStepContent> {
    return this.initGuideSteps();
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

    // 初始化字体管理
    FontAwareHelper.initializeFontAware(this.componentId, this.fontState, (newState: FontAwareState) => {
      this.fontState = newState;
    });

    // 加载当前步骤（从WelcomeGuideManager获取最新状态）
    this.currentStep = this.welcomeGuideManager.getCurrentStep();
    logger.info(TAG, `欢迎引导页面加载，当前引导步骤: ${this.currentStep}`);
    void this.syncCurrentStepFromManager('aboutToAppear');

    // 启动入场动画
    this.startEntranceAnimation();
  }

  onPageShow(): void {
    logger.lifecycle(TAG, '欢迎引导页面显示');
    void this.syncCurrentStepFromManager('onPageShow', true);
  }

  private async syncCurrentStepFromManager(trigger: string, withAnimation: boolean = false): Promise<void> {
    try {
      await this.welcomeGuideManager.initialize();
      const latestStep = this.welcomeGuideManager.getCurrentStep();
      if (latestStep === this.currentStep) {
        return;
      }
      logger.info(TAG, `欢迎引导步骤同步: trigger=${trigger}, ${this.currentStep} -> ${latestStep}`);
      if (withAnimation && !this.isAnimating) {
        this.contentOpacity = 0;
        this.contentTranslateY = 30;
        this.currentStep = latestStep;
        setTimeout(() => {
          this.startEntranceAnimation();
        }, 100);
        return;
      }
      this.currentStep = latestStep;
    } catch (error) {
      logger.error(TAG, `同步欢迎引导步骤失败: trigger=${trigger}, error=${String(error)}`);
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

    const stepContent = this.getGuideSteps().get(this.currentStep);
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
        // 欢迎页，进入主题选择
        logger.debug(TAG, '执行 WELCOME 步骤处理');
        this.animateStepChange(() => {
          this.currentStep = GuideStep.THEME_SELECTION;
          this.welcomeGuideManager.setCurrentStep(GuideStep.THEME_SELECTION);
          logger.info(TAG, `步骤已更新到: ${this.currentStep}`);
        });
        break;

      case GuideStep.THEME_SELECTION:
        // 主题选择页，点击主按钮进入Download同步引导
        logger.debug(TAG, '执行 THEME_SELECTION 步骤处理');
        this.animateStepChange(() => {
          this.currentStep = GuideStep.DATA_IMPORT;
          this.welcomeGuideManager.setCurrentStep(GuideStep.DATA_IMPORT);
          logger.info(TAG, `步骤已更新到: ${this.currentStep}`);
        });
        break;

      case GuideStep.DATA_IMPORT:
        // 导航到Download同步页面
        logger.debug(TAG, '执行 DATA_IMPORT 步骤处理，准备导航到Download同步页面');
        void this.navigateToDownloadSync();
        break;

      case GuideStep.IMAGE_SOURCE_GUIDE:
        // 直接进入下一步（书源引导）
        logger.debug(TAG, '执行 IMAGE_SOURCE_GUIDE 步骤处理，进入书源引导');
        this.animateStepChange(() => {
          const nextStep = this.sourceFeaturesEnabled ? GuideStep.BOOK_SOURCE_GUIDE : GuideStep.CUSTOM_EXPERIENCE;
          this.currentStep = nextStep;
          this.welcomeGuideManager.setCurrentStep(nextStep);
          logger.info(TAG, `步骤已更新到: ${this.currentStep}`);
        });
        break;

      case GuideStep.BOOK_SOURCE_GUIDE:
        // 直接进入下一步，避免欢迎引导阶段额外跳转页面
        logger.debug(TAG, '执行 BOOK_SOURCE_GUIDE 步骤处理，直接进入自定义体验步骤');
        this.animateStepChange(() => {
          this.currentStep = GuideStep.CUSTOM_EXPERIENCE;
          this.welcomeGuideManager.setCurrentStep(GuideStep.CUSTOM_EXPERIENCE);
          logger.info(TAG, `步骤已更新到: ${this.currentStep}`);
        });
        break;

      case GuideStep.CUSTOM_EXPERIENCE:
        // 导航到全局设置页面
        logger.debug(TAG, '执行 CUSTOM_EXPERIENCE 步骤处理，准备导航到全局设置页面');
        void this.navigateToGlobalSettings();
        break;

      case GuideStep.ANALYTICS_PERMISSION:
        // 阅读报告步骤（保留但跳过），直接进入 LIBRARY_INTRO
        logger.debug(TAG, '跳过阅读报告步骤，直接进入 LIBRARY_INTRO');
        this.animateStepChange(() => {
          this.currentStep = GuideStep.LIBRARY_INTRO;
          this.welcomeGuideManager.setCurrentStep(GuideStep.LIBRARY_INTRO);
        });
        break;

      case GuideStep.LIBRARY_INTRO:
        // 完成引导，进入主页面的书库标签
        logger.debug(TAG, '执行 LIBRARY_INTRO 步骤处理，准备完成引导');
        void this.completeGuide();
        break;

      default:
        logger.warn(TAG, `未知的引导步骤: ${this.currentStep}`);
        break;
    }
  }

  /**
   * 不导航直接进入下一步（用于可导航步骤）
   */
  private handleNextStepSkipNavigation(): void {
    if (this.isAnimating) return;

    let nextStep: GuideStep = this.currentStep;
    switch (this.currentStep) {
      case GuideStep.DATA_IMPORT:
        nextStep = this.sourceFeaturesEnabled ? GuideStep.IMAGE_SOURCE_GUIDE : GuideStep.CUSTOM_EXPERIENCE;
        break;
      case GuideStep.BOOK_SOURCE_GUIDE:
        nextStep = GuideStep.CUSTOM_EXPERIENCE;
        break;
      case GuideStep.CUSTOM_EXPERIENCE:
        nextStep = GuideStep.ANALYTICS_PERMISSION;
        break;
      default:
        return;
    }

    logger.info(TAG, `跳过导航，直接进入下一步: ${nextStep}`);
    this.animateStepChange(() => {
      this.currentStep = nextStep;
      this.welcomeGuideManager.setCurrentStep(nextStep);
    });
  }

  /**
   * 完成引导
   */
  private async completeGuide(): Promise<void> {
    logger.info(TAG, '引导流程完成');
    await this.welcomeGuideManager.markGuideCompleted();
    this.navigateToMainMenu();
  }

  /**
   * 导航到Download同步页面
   */
  private async navigateToDownloadSync(): Promise<void> {
    try {
      const nextStep = this.sourceFeaturesEnabled ? GuideStep.IMAGE_SOURCE_GUIDE : GuideStep.CUSTOM_EXPERIENCE;
      await this.welcomeGuideManager.setCurrentStep(nextStep);

      const router = this.uiContext?.getRouter();
      if (router) {
        router.pushUrl({
          url: 'pages/MainMenuPage',
          params: {
            targetPage: 'DownloadSyncPage',
            fromGuide: true
          }
        }).then(() => {
          logger.info(TAG, '导航到Download同步页面成功');
        }).catch((error: Error) => {
          logger.error(TAG, '导航到Download同步页面失败', error.message);
        });
      }
    } catch (error) {
      logger.error(TAG, '导航到Download同步页面异常', String(error));
    }
  }

  /**
   * 导航到图源页面（MainMenuPage的图源Tab）
   */
  private navigateToSourceTab(): void {
    try {
      // 更新步骤到书源引导
      this.welcomeGuideManager.setCurrentStep(GuideStep.BOOK_SOURCE_GUIDE);

      const router = this.uiContext?.getRouter();
      if (router) {
        router.pushUrl({
          url: 'pages/MainMenuPage',
          params: {
            targetTab: 3,  // TabIndex.SOURCE = 3
            fromGuide: true
          }
        }).then(() => {
          logger.info(TAG, '导航到图源页面成功');
        }).catch((error: Error) => {
          logger.error(TAG, '导航到图源页面失败', error.message);
        });
      }
    } catch (error) {
      logger.error(TAG, '导航到图源页面异常', String(error));
    }
  }

  /**
   * 导航到全局设置页面
   */
  private async navigateToGlobalSettings(): Promise<void> {
    try {
      // 更新步骤到书库介绍
      await this.welcomeGuideManager.setCurrentStep(GuideStep.LIBRARY_INTRO);

      const router = this.uiContext?.getRouter();
      if (router) {
        router.pushUrl({
          url: 'pages/MainMenuPage',
          params: {
            targetPage: 'GlobalSettingsPage',
            fromGuide: true
          }
        }).then(() => {
          logger.info(TAG, '导航到全局设置页面成功');
        }).catch((error: Error) => {
          logger.error(TAG, '导航到全局设置页面失败', error.message);
        });
      }
    } catch (error) {
      logger.error(TAG, '导航到全局设置页面异常', String(error));
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
   * 复制图源仓库URL到剪贴板
   */
  private copySourceUrl(): void {
    try {
      const pasteboardData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, SOURCE_REPO_URL);
      const systemPasteboard = pasteboard.getSystemPasteboard();
      systemPasteboard.setData(pasteboardData).then(() => {
        logger.info(TAG, '图源仓库URL已复制到剪贴板');
        promptAction.showToast({
          message: '已复制到剪贴板',
          duration: 2000
        });
      }).catch((error: Error) => {
        logger.error(TAG, '复制到剪贴板失败', error.message);
        promptAction.showToast({
          message: '复制失败',
          duration: 2000
        });
      });
    } catch (error) {
      logger.error(TAG, '复制图源URL异常', String(error));
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
    return this.getGuideSteps().get(this.currentStep) ?? {
      title: '欢迎',
      subtitle: '',
      description: '',
      icon: $r('app.media.icon'),
      buttonText: '继续',
      showSkip: false
    };
  }

  private lifecycle = new PageLifecycleManager('WelcomeGuidePage', { enableDebug: true });

  aboutToDisappear(): void {
    logger.lifecycle(TAG, '欢迎引导页面即将销毁');
    this.lifecycle.destroy();
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

          } else {
            // 默认步骤布局
            Stack() {
              Column()
                .width(120)
                .height(120)
                .borderRadius(60)
                .backgroundColor(this.themeState.currentTheme === ThemeType.DARK
                  ? 'rgba(255, 255, 255, 0.08)'
                  : 'rgba(15, 23, 42, 0.06)')
                .border({
                  width: 1,
                  color: this.themeState.currentTheme === ThemeType.DARK
                    ? 'rgba(255, 255, 255, 0.10)'
                    : 'rgba(15, 23, 42, 0.08)'
                })
                .shadow({
                  radius: 20,
                  color: this.themeState.currentTheme === ThemeType.DARK
                    ? 'rgba(0, 0, 0, 0.28)'
                    : 'rgba(15, 23, 42, 0.10)',
                  offsetX: 0,
                  offsetY: 10
                })

              SymbolGlyph(this.getCurrentStepContent().icon as Resource)
                .fontSize(54)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)])
            }
            .width(120)
            .height(120)
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
              .margin({ bottom: this.currentStep === GuideStep.IMAGE_SOURCE_GUIDE && this.sourceFeaturesEnabled ? 16 : 48 })

            // 图源说明页面的可复制URL文本框
            if (this.currentStep === GuideStep.IMAGE_SOURCE_GUIDE && this.sourceFeaturesEnabled) {
              Column() {
                Text('图源仓库地址')
                  .fontSize(12)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                  .margin({ bottom: 8 })

                Row() {
                  Text(SOURCE_REPO_URL)
                    .fontSize(12)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .layoutWeight(1)
                    .padding({ left: 12, right: 8, top: 10, bottom: 10 })

                  Button('复制')
                    .fontSize(12)
                    .height(32)
                    .padding({ left: 12, right: 12 })
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
                    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
                    .borderRadius(16)
                    .margin({ right: 8 })
                    .onClick(() => {
                      this.copySourceUrl();
                    })
                }
                .width('100%')
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
                .borderRadius(8)
              }
              .width('100%')
              .padding({ left: 32, right: 32 })
              .margin({ bottom: 32 })
            }
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

          // 下一步按钮（用于可导航步骤，允许不导航直接进入下一步）
          if (this.currentStep === GuideStep.DATA_IMPORT ||
              this.currentStep === GuideStep.BOOK_SOURCE_GUIDE ||
              this.currentStep === GuideStep.CUSTOM_EXPERIENCE) {
            Text('下一步')
              .fontSize(14)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
              .margin({ top: 8 })
              .opacity(this.isAnimating ? 0.5 : 1.0)
              .enabled(!this.isAnimating)
              .onClick(() => {
                if (!this.isAnimating) {
                  this.handleNextStepSkipNavigation();
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
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
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

