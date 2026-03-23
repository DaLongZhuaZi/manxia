// 文件路径: entry/src/main/ets/Framework/Managers/AppGuideManager.ets
/**
 * 应用内引导管理器
 * 负责统一管理跨页面引导流程、首次自动播放状态和手动重播入口
 */

import { preferences } from '@kit.ArkData';
import { logger } from '../../Utils/Logger';
import { getContext } from '../../GlobalContext';
import { WelcomeGuideManager } from './WelcomeGuideManager';

const TAG = 'AppGuideManager';

export enum AppGuideFlowId {
  MAIN_MENU_CORE = 'main_menu_core',
  DOWNLOAD_SYNC = 'download_sync',
  BACKUP_RESTORE = 'backup_restore',
  INSPIRATION = 'inspiration',
  GLOBAL_SETTINGS = 'global_settings',
  THEME_SETTINGS = 'theme_settings',
  NOVEL_SOURCE_MANAGEMENT = 'novel_source_management',
  SUWAYOMI = 'suwayomi',
  UNIFIED_DETAIL = 'unified_detail',
  MANGA_READER = 'manga_reader',
  NOVEL_READER = 'novel_reader',
  EBOOK_READER = 'ebook_reader'
}

export enum AppGuidePageId {
  MAIN_HOME = 'main_home',
  MAIN_LIBRARY = 'main_library',
  MAIN_SOURCE = 'main_source',
  MAIN_BOOK_SOURCE = 'main_book_source',
  MAIN_SETTINGS = 'main_settings',
  DOWNLOAD_SYNC = 'download_sync_page',
  BACKUP_RESTORE = 'backup_restore_page',
  INSPIRATION = 'inspiration_page',
  GLOBAL_SETTINGS = 'global_settings_page',
  THEME_SETTINGS = 'theme_settings_page',
  NOVEL_SOURCE_MANAGEMENT = 'novel_source_management_page',
  SUWAYOMI = 'suwayomi_browse_page',
  UNIFIED_DETAIL = 'unified_detail_page',
  MANGA_READER = 'manga_reader_page',
  NOVEL_READER = 'novel_reader_page',
  EBOOK_READER = 'ebook_reader_page'
}

export type AppGuideCardPosition = 'top' | 'bottom' | 'center';

export interface AppGuideStep {
  id: string;
  pageId: AppGuidePageId;
  anchorId?: string;
  title: string;
  message: string;
  cardPosition: AppGuideCardPosition;
  nextButtonText?: string;
  showSkip?: boolean;
  borderRadius?: number;
}

export interface AppGuideFlowDefinition {
  id: AppGuideFlowId;
  title: string;
  description: string;
  autoStartPageId: AppGuidePageId;
  helpCenterReplayEnabled: boolean;
  helpCenterRouteName?: string;
  steps: AppGuideStep[];
}

export interface AppGuideFlowState {
  flowId: AppGuideFlowId;
  autoShown: boolean;
  completed: boolean;
  skipped: boolean;
  lastPlayedAt: number;
}

export interface AppGuideFlowSummary {
  id: AppGuideFlowId;
  title: string;
  description: string;
  helpCenterRouteName?: string;
}

interface PersistedAppGuideFlowState {
  flowId: AppGuideFlowId;
  autoShown?: boolean;
  completed?: boolean;
  skipped?: boolean;
  lastPlayedAt?: number;
}

const GUIDE_PREFERENCES_NAME = 'app_guide_preferences';
const GUIDE_FLOW_STATE_KEY = 'app_guide_flow_states_v1';
const GUIDE_ACTIVE_FLOW_ID_KEY = 'app_guide_active_flow_id';
const GUIDE_ACTIVE_STEP_INDEX_KEY = 'app_guide_active_step_index';

const GUIDE_FLOWS: AppGuideFlowDefinition[] = [
  {
    id: AppGuideFlowId.MAIN_MENU_CORE,
    title: '主页面与入口引导',
    description: '介绍首页、书库、图源、书源、设置，以及从帮助中心重播引导的方式。',
    autoStartPageId: AppGuidePageId.MAIN_LIBRARY,
    helpCenterReplayEnabled: true,
    steps: [
      {
        id: 'main_home_intro',
        pageId: AppGuidePageId.MAIN_LIBRARY,
        anchorId: 'guide_main_bottom_bar',
        title: '这是新的全屏交互引导',
        message: '后续进入各系统主页时，都会自动播放对应引导。即使跳过，也可以随时在帮助中心或页面的引导入口里重播。',
        cardPosition: 'top',
        nextButtonText: '继续查看'
      },
      {
        id: 'main_home_tab',
        pageId: AppGuidePageId.MAIN_HOME,
        anchorId: 'guide_main_tab_home',
        title: '首页负责承接最近阅读与推荐',
        message: '这里会优先展示最近阅读、继续阅读和一些快捷入口，适合作为每天回到应用后的起点。',
        cardPosition: 'top'
      },
      {
        id: 'main_library_tab',
        pageId: AppGuidePageId.MAIN_LIBRARY,
        anchorId: 'guide_main_tab_library',
        title: '书库是你的内容总入口',
        message: '这里统一管理本地导入的漫画、小说与电子书，也能继续阅读最近内容。后续进入统一详情页或阅读器时，会自动播放对应流程。',
        cardPosition: 'top',
        nextButtonText: '继续'
      },
      {
        id: 'main_source_tab',
        pageId: AppGuidePageId.MAIN_SOURCE,
        anchorId: 'guide_main_tab_source',
        title: '图源系统在这里',
        message: '图源页负责浏览在线漫画内容。首次深入进入图源相关页面时，会继续展示图源与详情页的专项引导。',
        cardPosition: 'top'
      },
      {
        id: 'main_book_source_tab',
        pageId: AppGuidePageId.MAIN_BOOK_SOURCE,
        anchorId: 'guide_main_tab_book_source',
        title: '书源系统在这里',
        message: '书源页用于发现和搜索小说源。首次进入书源管理页时，会自动补充如何导入、启用和排查书源。',
        cardPosition: 'top'
      },
      {
        id: 'main_settings_tab',
        pageId: AppGuidePageId.MAIN_SETTINGS,
        anchorId: 'guide_main_tab_settings',
        title: '个性化入口集中在设置页',
        message: '主题、全局设置、备份恢复、帮助中心都在这里。接下来我会把你常用的几个入口指给你。',
        cardPosition: 'top'
      },
      {
        id: 'main_settings_theme',
        pageId: AppGuidePageId.MAIN_SETTINGS,
        anchorId: 'guide_main_setting_theme',
        title: '主题设置',
        message: '这里可以调整背景、强调色、透明度和整套视觉风格。首次进入主题设置页时，也会自动播放更细的引导。',
        cardPosition: 'top'
      },
      {
        id: 'main_settings_global',
        pageId: AppGuidePageId.MAIN_SETTINGS,
        anchorId: 'guide_main_setting_global',
        title: '全局设置',
        message: '这里可以集中修改阅读默认值、主页面行为、下载网络、通知与高级项。首次进入后会自动介绍分类结构。',
        cardPosition: 'top'
      },
      {
        id: 'main_settings_help',
        pageId: AppGuidePageId.MAIN_SETTINGS,
        anchorId: 'guide_main_setting_help',
        title: '帮助中心支持重播引导',
        message: '如果你忘记某个系统怎么用，直接到帮助中心找到对应条目重播即可。主页面的第一轮引导先到这里，后面进入具体系统时会继续自动补充。',
        cardPosition: 'top',
        nextButtonText: '完成'
      }
    ]
  },
  {
    id: AppGuideFlowId.DOWNLOAD_SYNC,
    title: 'Download 同步引导',
    description: '说明如何扫描 Download 目录、按类型查看文件，并使用同步方式导入内容。',
    autoStartPageId: AppGuidePageId.DOWNLOAD_SYNC,
    helpCenterReplayEnabled: true,
    helpCenterRouteName: 'DownloadSyncPage',
    steps: [
      {
        id: 'download_sync_intro',
        pageId: AppGuidePageId.DOWNLOAD_SYNC,
        anchorId: 'guide_download_sync_root',
        title: '这里专门负责 Download 同步导入',
        message: '把文件放进 Download 目录下的应用专属文件夹后，就可以在这里统一扫描、识别和导入。',
        cardPosition: 'bottom'
      },
      {
        id: 'download_sync_tabs',
        pageId: AppGuidePageId.DOWNLOAD_SYNC,
        anchorId: 'guide_download_sync_tabs',
        title: '按流程切换不同分区',
        message: '建议先在“文件扫描与导入”确认扫描结果，再按类型核对小说、电子书、漫画与 PDF 的导入状态。',
        cardPosition: 'bottom'
      },
      {
        id: 'download_sync_finish',
        pageId: AppGuidePageId.DOWNLOAD_SYNC,
        anchorId: 'guide_download_sync_root',
        title: '只介绍同步方式，不打扰单文件导入',
        message: '这个引导只覆盖 Download 同步流程。后续你随时可以从本页的帮助/引导入口重新播放。',
        cardPosition: 'center',
        nextButtonText: '知道了'
      }
    ]
  },
  {
    id: AppGuideFlowId.BACKUP_RESTORE,
    title: '备份与恢复引导',
    description: '介绍本地备份、云端配置与恢复入口。',
    autoStartPageId: AppGuidePageId.BACKUP_RESTORE,
    helpCenterReplayEnabled: true,
    helpCenterRouteName: 'BackupPage',
    steps: [
      {
        id: 'backup_intro',
        pageId: AppGuidePageId.BACKUP_RESTORE,
        anchorId: 'guide_backup_root',
        title: '这里统一管理备份与恢复',
        message: '无论是本地备份、WebDAV 云端同步还是恢复任务，都集中在这个页面完成。',
        cardPosition: 'bottom'
      },
      {
        id: 'backup_tabs',
        pageId: AppGuidePageId.BACKUP_RESTORE,
        anchorId: 'guide_backup_tabs',
        title: '先选工作模式，再执行操作',
        message: '建议先在标签栏里确认当前是在本地备份、云端备份还是 FTP 管理，再开始创建或恢复任务。',
        cardPosition: 'bottom'
      },
      {
        id: 'backup_finish',
        pageId: AppGuidePageId.BACKUP_RESTORE,
        anchorId: 'guide_backup_root',
        title: '恢复前记得确认覆盖范围',
        message: '恢复会影响现有记录，建议先做一次备份再恢复。后续可在帮助中心或本页引导入口重播。',
        cardPosition: 'center',
        nextButtonText: '完成'
      }
    ]
  },
  {
    id: AppGuideFlowId.INSPIRATION,
    title: '灵感功能引导',
    description: '介绍灵感页的入口、筛选与内容摘录能力。',
    autoStartPageId: AppGuidePageId.INSPIRATION,
    helpCenterReplayEnabled: true,
    helpCenterRouteName: 'AnnotationCenterPage',
    steps: [
      {
        id: 'inspiration_intro',
        pageId: AppGuidePageId.INSPIRATION,
        anchorId: 'guide_inspiration_filters',
        title: '灵感页会统一收集你的标注与摘录',
        message: '这里适合回顾阅读中留下的高亮、笔记、片段和灵感卡片，也是后续整理内容的总入口。',
        cardPosition: 'bottom'
      },
      {
        id: 'inspiration_finish',
        pageId: AppGuidePageId.INSPIRATION,
        anchorId: 'guide_inspiration_root',
        title: '先从筛选与跳转开始用起',
        message: '你可以按内容类型、书籍和时间回看灵感，再跳回原文继续阅读。以后忘了怎么用，可以在本页重新播放。',
        cardPosition: 'center',
        nextButtonText: '完成'
      }
    ]
  },
  {
    id: AppGuideFlowId.GLOBAL_SETTINGS,
    title: '全局设置引导',
    description: '介绍搜索入口、设置分组和二级配置页结构。',
    autoStartPageId: AppGuidePageId.GLOBAL_SETTINGS,
    helpCenterReplayEnabled: true,
    helpCenterRouteName: 'GlobalSettingsPage',
    steps: [
      {
        id: 'global_settings_intro',
        pageId: AppGuidePageId.GLOBAL_SETTINGS,
        anchorId: 'guide_global_settings_root',
        title: '这里是全局设置总览',
        message: '应用级的默认行为、主页面布局、网络下载、高级选项等都在这里按分组管理。',
        cardPosition: 'bottom'
      },
      {
        id: 'global_settings_search',
        pageId: AppGuidePageId.GLOBAL_SETTINGS,
        anchorId: 'guide_global_settings_search',
        title: '先用搜索再进二级页面',
        message: '设置很多时，直接搜索“翻页动画”“主导航栏”“备份”等关键词会更快定位到目标配置。',
        cardPosition: 'bottom'
      },
      {
        id: 'global_settings_finish',
        pageId: AppGuidePageId.GLOBAL_SETTINGS,
        anchorId: 'guide_global_settings_group_list',
        title: '设置项按主题分组排列',
        message: '进入任一分组后，就能做更细的自定义。后续如果需要复习，可在帮助中心重播对应引导。',
        cardPosition: 'center',
        nextButtonText: '完成'
      }
    ]
  },
  {
    id: AppGuideFlowId.THEME_SETTINGS,
    title: '主题设置引导',
    description: '介绍主题风格、透明度与视觉效果的自定义能力。',
    autoStartPageId: AppGuidePageId.THEME_SETTINGS,
    helpCenterReplayEnabled: true,
    helpCenterRouteName: 'ThemeSettingsPage',
    steps: [
      {
        id: 'theme_settings_intro',
        pageId: AppGuidePageId.THEME_SETTINGS,
        anchorId: 'theme_custom',
        title: '主题设置负责界面观感',
        message: '你可以在这里统一调整背景、强调色、透明度和动效，让主页面和阅读页面更符合自己的习惯。',
        cardPosition: 'bottom'
      },
      {
        id: 'theme_settings_finish',
        pageId: AppGuidePageId.THEME_SETTINGS,
        anchorId: 'theme_effects',
        title: '建议边预览边调整',
        message: '修改主题后可以立刻观察整体变化，满意后再继续深入全局设置做功能级自定义。',
        cardPosition: 'center',
        nextButtonText: '完成'
      }
    ]
  },
  {
    id: AppGuideFlowId.NOVEL_SOURCE_MANAGEMENT,
    title: '书源管理引导',
    description: '介绍书源导入、启停和调试入口。',
    autoStartPageId: AppGuidePageId.NOVEL_SOURCE_MANAGEMENT,
    helpCenterReplayEnabled: true,
    helpCenterRouteName: 'NovelSourceManagementPage',
    steps: [
      {
        id: 'novel_source_intro',
        pageId: AppGuidePageId.NOVEL_SOURCE_MANAGEMENT,
        anchorId: 'guide_novel_source_stats',
        title: '这里集中管理小说书源',
        message: '你可以在这里导入、启用、排序、测试和排查书源，让书源搜索与详情页能正常工作。',
        cardPosition: 'bottom'
      },
      {
        id: 'novel_source_finish',
        pageId: AppGuidePageId.NOVEL_SOURCE_MANAGEMENT,
        anchorId: 'guide_novel_source_list',
        title: '先保证书源可用，再去发现与阅读',
        message: '推荐先完成导入和校验，再回到书源页搜索内容。忘记流程时，可在帮助中心重播这段引导。',
        cardPosition: 'center',
        nextButtonText: '完成'
      }
    ]
  },
  {
    id: AppGuideFlowId.SUWAYOMI,
    title: 'Suwayomi 引导',
    description: '介绍 Suwayomi 浏览页的发现、详情和阅读链路。',
    autoStartPageId: AppGuidePageId.SUWAYOMI,
    helpCenterReplayEnabled: true,
    helpCenterRouteName: 'SuwayomiBrowsePage',
    steps: [
      {
        id: 'suwayomi_intro',
        pageId: AppGuidePageId.SUWAYOMI,
        anchorId: 'guide_suwayomi_root',
        title: '这里是 Suwayomi 浏览入口',
        message: '你可以从这里浏览服务器内容、进入详情页，再继续跳到阅读器。第一次进入会先把使用节奏说明清楚。',
        cardPosition: 'bottom'
      },
      {
        id: 'suwayomi_finish',
        pageId: AppGuidePageId.SUWAYOMI,
        anchorId: 'guide_suwayomi_root',
        title: '浏览、详情、阅读是一条连续链路',
        message: '建议先熟悉浏览筛选，再进入具体内容详情。后续若需要回顾，也能在帮助中心里重播。',
        cardPosition: 'center',
        nextButtonText: '完成'
      }
    ]
  },
  {
    id: AppGuideFlowId.UNIFIED_DETAIL,
    title: '统一详情页引导',
    description: '介绍统一详情页中的封面、操作入口与缓存/听书能力。',
    autoStartPageId: AppGuidePageId.UNIFIED_DETAIL,
    helpCenterReplayEnabled: false,
    steps: [
      {
        id: 'unified_detail_intro',
        pageId: AppGuidePageId.UNIFIED_DETAIL,
        anchorId: 'guide_unified_detail_root',
        title: '这是统一详情页',
        message: '漫画、小说和电子书后续都会收敛到这里查看核心信息、封面、章节、下载与阅读入口。',
        cardPosition: 'bottom'
      },
      {
        id: 'unified_detail_finish',
        pageId: AppGuidePageId.UNIFIED_DETAIL,
        anchorId: 'guide_unified_detail_root',
        title: '进入阅读前先在这里确认信息',
        message: '你可以先检查章节、缓存状态和听书能力，再选择继续阅读或下载管理。',
        cardPosition: 'center',
        nextButtonText: '完成'
      }
    ]
  },
  {
    id: AppGuideFlowId.MANGA_READER,
    title: '漫画阅读器引导',
    description: '介绍漫画阅读器中的基础手势、菜单呼出和阅读设置入口。',
    autoStartPageId: AppGuidePageId.MANGA_READER,
    helpCenterReplayEnabled: false,
    steps: [
      {
        id: 'manga_reader_intro',
        pageId: AppGuidePageId.MANGA_READER,
        anchorId: 'guide_manga_reader_root',
        title: '这是漫画阅读器',
        message: '先记住一个核心动作：点击阅读区域中央呼出菜单，再去切章节、调方向和改翻页方式。',
        cardPosition: 'center',
        nextButtonText: '完成'
      }
    ]
  },
  {
    id: AppGuideFlowId.NOVEL_READER,
    title: '小说阅读器引导',
    description: '介绍小说阅读器中的菜单呼出、章节切换、听书和个性化设置。',
    autoStartPageId: AppGuidePageId.NOVEL_READER,
    helpCenterReplayEnabled: false,
    steps: [
      {
        id: 'novel_reader_intro',
        pageId: AppGuidePageId.NOVEL_READER,
        anchorId: 'guide_novel_reader_root',
        title: '这是小说阅读器',
        message: '点击正文中央可以呼出顶部和底部菜单，再进行目录跳转、字体背景调整和听书操作。',
        cardPosition: 'center',
        nextButtonText: '完成'
      }
    ]
  },
  {
    id: AppGuideFlowId.EBOOK_READER,
    title: '电子书阅读器引导',
    description: '介绍电子书阅读器中的分页、文本设置与听书入口。',
    autoStartPageId: AppGuidePageId.EBOOK_READER,
    helpCenterReplayEnabled: false,
    steps: [
      {
        id: 'ebook_reader_intro',
        pageId: AppGuidePageId.EBOOK_READER,
        anchorId: 'guide_ebook_reader_root',
        title: '这是电子书阅读器',
        message: '你可以在这里切分页模式、调整文本样式，并从阅读器内继续进入听书播放器。',
        cardPosition: 'center',
        nextButtonText: '完成'
      }
    ]
  }
];

export class AppGuideManager {
  private static instance: AppGuideManager | null = null;
  private preferencesStore: preferences.Preferences | null = null;
  private isInitialized: boolean = false;
  private flowStateMap: Map<AppGuideFlowId, AppGuideFlowState> = new Map();
  private activeFlowId: AppGuideFlowId | null = null;
  private activeStepIndex: number = 0;
  private legacyWelcomeGuideManager: WelcomeGuideManager = WelcomeGuideManager.getInstance();

  private constructor() {}

  public static getInstance(): AppGuideManager {
    if (!AppGuideManager.instance) {
      AppGuideManager.instance = new AppGuideManager();
    }
    return AppGuideManager.instance;
  }

  public async initialize(): Promise<void> {
    if (this.isInitialized) {
      return;
    }

    try {
      const context = getContext();
      this.preferencesStore = await preferences.getPreferences(context, GUIDE_PREFERENCES_NAME);
      await this.loadFlowStates();
      await this.loadActiveSession();
      this.isInitialized = true;
      logger.info(TAG, '应用引导管理器初始化完成');
    } catch (error) {
      this.isInitialized = true;
      logger.error(TAG, '应用引导管理器初始化失败', String(error));
    }
  }

  public getCurrentStep(): AppGuideStep | null {
    const flow = this.getCurrentFlow();
    if (!flow) {
      return null;
    }
    if (this.activeStepIndex < 0 || this.activeStepIndex >= flow.steps.length) {
      return null;
    }
    return flow.steps[this.activeStepIndex];
  }

  public getCurrentFlow(): AppGuideFlowDefinition | null {
    if (!this.activeFlowId) {
      return null;
    }
    return this.getFlowDefinition(this.activeFlowId);
  }

  public getCurrentProgressText(): string {
    const flow = this.getCurrentFlow();
    if (!flow || flow.steps.length <= 0) {
      return '';
    }
    return `步骤 ${this.activeStepIndex + 1}/${flow.steps.length}`;
  }

  public getHelpCenterFlowSummaries(): AppGuideFlowSummary[] {
    const result: AppGuideFlowSummary[] = [];
    for (let index = 0; index < GUIDE_FLOWS.length; index++) {
      const flow = GUIDE_FLOWS[index];
      if (!flow.helpCenterReplayEnabled) {
        continue;
      }
      result.push({
        id: flow.id,
        title: flow.title,
        description: flow.description,
        helpCenterRouteName: flow.helpCenterRouteName
      });
    }
    return result;
  }

  public getFlowDefinition(flowId: AppGuideFlowId): AppGuideFlowDefinition | null {
    for (let index = 0; index < GUIDE_FLOWS.length; index++) {
      if (GUIDE_FLOWS[index].id === flowId) {
        return GUIDE_FLOWS[index];
      }
    }
    return null;
  }

  public async startFlow(flowId: AppGuideFlowId, source: 'auto' | 'manual' = 'manual'): Promise<AppGuideStep | null> {
    await this.initialize();
    const flow = this.getFlowDefinition(flowId);
    if (!flow) {
      logger.warn(TAG, `未找到引导流程定义: ${flowId}`);
      return null;
    }

    this.activeFlowId = flowId;
    this.activeStepIndex = 0;
    this.markFlowAsPlayed(flowId, source);
    await this.saveFlowStates();
    await this.saveActiveSession();
    logger.info(TAG, `已启动引导流程: 流程=${flowId}, 来源=${source}`);
    return this.getCurrentStep();
  }

  public async tryAutoStartFlowByPage(pageId: AppGuidePageId): Promise<AppGuideStep | null> {
    await this.initialize();
    if (this.activeFlowId) {
      const currentStep = this.getCurrentStep();
      if (currentStep && currentStep.pageId === pageId) {
        return currentStep;
      }
      return null;
    }

    for (let index = 0; index < GUIDE_FLOWS.length; index++) {
      const flow = GUIDE_FLOWS[index];
      if (flow.autoStartPageId !== pageId) {
        continue;
      }
      const state = this.getFlowState(flow.id);
      if (state.autoShown) {
        continue;
      }
      return await this.startFlow(flow.id, 'auto');
    }
    return null;
  }

  public async nextStep(): Promise<AppGuideStep | null> {
    await this.initialize();
    const flow = this.getCurrentFlow();
    if (!flow) {
      return null;
    }

    const nextIndex = this.activeStepIndex + 1;
    if (nextIndex >= flow.steps.length) {
      await this.completeCurrentFlow();
      return null;
    }

    this.activeStepIndex = nextIndex;
    await this.saveActiveSession();
    logger.info(TAG, `引导进入下一步: 流程=${flow.id}, 步骤索引=${this.activeStepIndex}`);
    return this.getCurrentStep();
  }

  public async skipCurrentFlow(): Promise<void> {
    await this.initialize();
    if (!this.activeFlowId) {
      return;
    }

    const flowId = this.activeFlowId;
    const state = this.getFlowState(flowId);
    state.autoShown = true;
    state.skipped = true;
    state.lastPlayedAt = Date.now();
    this.flowStateMap.set(flowId, state);
    await this.handleLegacyWelcomeFlow(flowId, false);
    this.activeFlowId = null;
    this.activeStepIndex = 0;
    await this.saveFlowStates();
    await this.saveActiveSession();
    logger.info(TAG, `已跳过引导流程: 流程=${flowId}`);
  }

  public async completeCurrentFlow(): Promise<void> {
    await this.initialize();
    if (!this.activeFlowId) {
      return;
    }

    const flowId = this.activeFlowId;
    const state = this.getFlowState(flowId);
    state.autoShown = true;
    state.completed = true;
    state.skipped = false;
    state.lastPlayedAt = Date.now();
    this.flowStateMap.set(flowId, state);
    await this.handleLegacyWelcomeFlow(flowId, true);
    this.activeFlowId = null;
    this.activeStepIndex = 0;
    await this.saveFlowStates();
    await this.saveActiveSession();
    logger.info(TAG, `已完成引导流程: 流程=${flowId}`);
  }

  public async resetAllGuideStates(): Promise<void> {
    await this.initialize();
    this.flowStateMap.clear();
    this.activeFlowId = null;
    this.activeStepIndex = 0;
    await this.saveFlowStates();
    await this.saveActiveSession();
    logger.info(TAG, '已重置全部应用引导状态');
  }

  public isFlowActive(flowId: AppGuideFlowId): boolean {
    return this.activeFlowId === flowId;
  }

  private markFlowAsPlayed(flowId: AppGuideFlowId, source: 'auto' | 'manual'): void {
    const state = this.getFlowState(flowId);
    state.autoShown = true;
    state.lastPlayedAt = Date.now();
    if (source === 'manual') {
      state.skipped = false;
    }
    this.flowStateMap.set(flowId, state);
  }

  private getFlowState(flowId: AppGuideFlowId): AppGuideFlowState {
    const existing = this.flowStateMap.get(flowId);
    if (existing) {
      return existing;
    }
    const created: AppGuideFlowState = {
      flowId: flowId,
      autoShown: false,
      completed: false,
      skipped: false,
      lastPlayedAt: 0
    };
    this.flowStateMap.set(flowId, created);
    return created;
  }

  private async loadFlowStates(): Promise<void> {
    if (!this.preferencesStore) {
      return;
    }

    try {
      const raw = await this.preferencesStore.get(GUIDE_FLOW_STATE_KEY, '[]') as string;
      const parsed = JSON.parse(raw) as PersistedAppGuideFlowState[];
      if (!Array.isArray(parsed)) {
        return;
      }
      for (let index = 0; index < parsed.length; index++) {
        const item = parsed[index];
        const created: AppGuideFlowState = {
          flowId: item.flowId,
          autoShown: item.autoShown === true,
          completed: item.completed === true,
          skipped: item.skipped === true,
          lastPlayedAt: item.lastPlayedAt ?? 0
        };
        this.flowStateMap.set(item.flowId, created);
      }
    } catch (error) {
      logger.warn(TAG, `加载引导状态失败，将使用默认值: ${String(error)}`);
    }
  }

  private async saveFlowStates(): Promise<void> {
    if (!this.preferencesStore) {
      return;
    }

    const states: PersistedAppGuideFlowState[] = [];
    this.flowStateMap.forEach((state: AppGuideFlowState) => {
      states.push({
        flowId: state.flowId,
        autoShown: state.autoShown,
        completed: state.completed,
        skipped: state.skipped,
        lastPlayedAt: state.lastPlayedAt
      });
    });

    try {
      await this.preferencesStore.put(GUIDE_FLOW_STATE_KEY, JSON.stringify(states));
      await this.preferencesStore.flush();
    } catch (error) {
      logger.error(TAG, '保存引导状态失败', String(error));
    }
  }

  private async loadActiveSession(): Promise<void> {
    if (!this.preferencesStore) {
      return;
    }

    try {
      const flowIdRaw = await this.preferencesStore.get(GUIDE_ACTIVE_FLOW_ID_KEY, '') as string;
      const stepIndex = await this.preferencesStore.get(GUIDE_ACTIVE_STEP_INDEX_KEY, 0) as number;
      if (!flowIdRaw || flowIdRaw.length <= 0) {
        this.activeFlowId = null;
        this.activeStepIndex = 0;
        return;
      }

      const flowId = flowIdRaw as AppGuideFlowId;
      const flow = this.getFlowDefinition(flowId);
      if (!flow || stepIndex < 0 || stepIndex >= flow.steps.length) {
        this.activeFlowId = null;
        this.activeStepIndex = 0;
        return;
      }

      this.activeFlowId = flowId;
      this.activeStepIndex = stepIndex;
      logger.info(TAG, `已恢复引导会话: 流程=${flowId}, 步骤索引=${stepIndex}`);
    } catch (error) {
      logger.warn(TAG, `恢复引导会话失败: ${String(error)}`);
      this.activeFlowId = null;
      this.activeStepIndex = 0;
    }
  }

  private async saveActiveSession(): Promise<void> {
    if (!this.preferencesStore) {
      return;
    }

    try {
      await this.preferencesStore.put(GUIDE_ACTIVE_FLOW_ID_KEY, this.activeFlowId ?? '');
      await this.preferencesStore.put(GUIDE_ACTIVE_STEP_INDEX_KEY, this.activeStepIndex);
      await this.preferencesStore.flush();
    } catch (error) {
      logger.error(TAG, '保存引导会话失败', String(error));
    }
  }

  private async handleLegacyWelcomeFlow(flowId: AppGuideFlowId, completed: boolean): Promise<void> {
    if (flowId !== AppGuideFlowId.MAIN_MENU_CORE) {
      return;
    }
    try {
      if (completed) {
        await this.legacyWelcomeGuideManager.markGuideCompleted();
      } else {
        await this.legacyWelcomeGuideManager.skipGuide();
      }
    } catch (error) {
      logger.warn(TAG, `同步旧版欢迎引导状态失败: ${String(error)}`);
    }
  }
}

export const appGuideManager = AppGuideManager.getInstance();
