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
  SUWAYOMI = 'suwayomi',
  UNIFIED_DETAIL = 'unified_detail',
  GLOBAL_SEARCH = 'global_search',
  MANGA_READER = 'manga_reader',
  NOVEL_READER = 'novel_reader',
  EBOOK_READER = 'ebook_reader'
}

export enum AppGuidePageId {
  MAIN_HOME = 'main_home',
  MAIN_LIBRARY = 'main_library',
  MAIN_DISCOVER = 'main_discover',
  MAIN_SOURCE = 'main_source',
  MAIN_BOOK_SOURCE = 'main_book_source',
  MAIN_SUWAYOMI = 'main_suwayomi',
  MAIN_SETTINGS = 'main_settings',
  DOWNLOAD_SYNC = 'download_sync_page',
  BACKUP_RESTORE = 'backup_restore_page',
  INSPIRATION = 'inspiration_page',
  GLOBAL_SETTINGS = 'global_settings_page',
  SUWAYOMI = 'suwayomi_browse_page',
  UNIFIED_DETAIL = 'unified_detail_page',
  GLOBAL_SEARCH = 'global_search_page',
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
        message: '书源页用于发现和搜索小说源。后续你可以继续从搜索页、详情页和阅读链路中完成实际使用。',
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
        message: '这里可以调整背景、强调色、透明度和整套视觉风格。建议先优先保证可读性，再逐步微调视觉氛围。',
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
        message: '把文件放进 Download 目录下的应用专属文件夹后，这里会负责连接目录、扫描文件、快速导入以及核对导入状态。第一次使用时，建议按“连接文件夹 -> 扫描 -> 导入 -> 复查”的顺序走完整套流程。',
        cardPosition: 'bottom'
      },
      {
        id: 'download_sync_tabs',
        pageId: AppGuidePageId.DOWNLOAD_SYNC,
        anchorId: 'guide_download_sync_tabs',
        title: '按流程切换不同分区',
        message: '上方标签把页面分成两块：左侧负责连接目录、扫描与导入，右侧负责查看哪些文件已经真正入库。引导会先把导入链路讲清楚，再带你切到状态核对区。',
        cardPosition: 'bottom'
      },
      {
        id: 'download_sync_folder_status',
        pageId: AppGuidePageId.DOWNLOAD_SYNC,
        anchorId: 'guide_download_sync_folder_status',
        title: '先在这里确认目录连接和扫描结果',
        message: '这里会显示当前是否已经连接到应用专属目录、目录路径是否正确，以及扫描后识别出的文件总数和类型数量。连接目录之后别忘了点“扫描文件”，否则下面不会出现待导入列表。',
        cardPosition: 'top'
      },
      {
        id: 'download_sync_quick_import',
        pageId: AppGuidePageId.DOWNLOAD_SYNC,
        anchorId: 'guide_download_sync_quick_import',
        title: '快速导入区按文件类型分组处理',
        message: '扫描完成后，这里会把漫画、电子书、PDF 和小说分别列出来。每组右侧的加号就是对应类型的一键导入入口，下方文件名则帮助你先确认识别结果有没有出错。',
        cardPosition: 'top'
      },
      {
        id: 'download_sync_imported_status',
        pageId: AppGuidePageId.DOWNLOAD_SYNC,
        anchorId: 'guide_download_sync_imported_status',
        title: '已导入管理负责防止重复导入',
        message: '切到“已导入管理”后，会用树状视图对照 Download 目录和应用内记录。圆点表示未导入，对勾表示已导入，批量同步后建议来这里再核对一次，避免重复处理同一批文件。',
        cardPosition: 'top'
      },
      {
        id: 'download_sync_finish',
        pageId: AppGuidePageId.DOWNLOAD_SYNC,
        anchorId: 'guide_download_sync_imported_status',
        title: '常用流程就是连接、扫描、导入、复查',
        message: '如果你只是想快速把文件入库，完成连接、扫描和导入通常就够了；如果你担心漏导或重复导入，再切回已导入管理确认一次。后续随时可以在本页或帮助中心重播这段引导。',
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
        message: '本地备份、WebDAV 云端同步、底层连通性测试和 FTP 文件管理都集中在这里。进入之前先想清楚自己是要“保护应用数据”“同步备份文件”还是“管理远程目录”，这样更不容易走错面板。',
        cardPosition: 'bottom'
      },
      {
        id: 'backup_tabs',
        pageId: AppGuidePageId.BACKUP_RESTORE,
        anchorId: 'guide_backup_tabs',
        title: '先选工作模式，再执行操作',
        message: '标签栏把流程拆成四种模式：本地备份、云端备份、Native 测试、FTP 管理。引导会依次切过去，让你分别知道每一块负责什么，不把“文件管理”和“应用数据备份”混成同一件事。',
        cardPosition: 'bottom'
      },
      {
        id: 'backup_local_panel',
        pageId: AppGuidePageId.BACKUP_RESTORE,
        anchorId: 'guide_backup_local_panel',
        title: '本地面板负责创建、导入、恢复和导出备份',
        message: '这里是最常用的应用数据保护区。准备恢复前，最好先额外创建一次当前设备的新备份；导入外部备份时，也建议先确认文件名和时间，避免把旧数据直接覆盖到现在的环境上。',
        cardPosition: 'top'
      },
      {
        id: 'backup_cloud_panel',
        pageId: AppGuidePageId.BACKUP_RESTORE,
        anchorId: 'guide_backup_cloud_panel',
        title: '云端面板的关键顺序是先配置再同步',
        message: 'WebDAV 云端备份适合跨设备保存备份文件。正确顺序通常是先填写服务器信息、测试连接、确认目录，再执行初始化、上传或下载，不要在连接异常时直接做同步操作。',
        cardPosition: 'top'
      },
      {
        id: 'backup_native_panel',
        pageId: AppGuidePageId.BACKUP_RESTORE,
        anchorId: 'guide_backup_native_panel',
        title: 'Native 测试面板更适合排障而不是日常备份',
        message: '当普通 WebDAV 测试无法说明问题时，可以来这里检查更底层的连接、目录创建、上传下载能力。它的目标是帮助你定位兼容性和证书问题，而不是替代日常的备份入口。',
        cardPosition: 'top'
      },
      {
        id: 'backup_ftp_panel',
        pageId: AppGuidePageId.BACKUP_RESTORE,
        anchorId: 'guide_backup_ftp_panel',
        title: 'FTP 面板用于管理远程文件，不等于应用备份',
        message: 'FTP 管理更像外部文件浏览器，可以保存连接、进入远程目录、管理文件，但它不会自动承担应用数据备份的语义。要保护阅读记录和设置，仍然应优先使用本地或 WebDAV 备份链路。',
        cardPosition: 'top'
      },
      {
        id: 'backup_finish',
        pageId: AppGuidePageId.BACKUP_RESTORE,
        anchorId: 'guide_backup_ftp_panel',
        title: '恢复前记得先做保护性备份',
        message: '无论你最终使用本地、云端还是 FTP 协作，真正执行恢复前都建议先把当前设备状态再备份一次。后续如果忘了各面板用途，也可以在帮助中心或本页重新播放这段引导。',
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
        anchorId: 'guide_inspiration_content_selector',
        title: '先决定要整理全部内容，还是只看某一本',
        message: '顶部内容选择区会把“全部内容”和每本书的灵感聚合出来。整理前先在这里缩小范围，会比直接在长列表里盲翻高效很多，尤其适合回顾某一本书的书签、划线和想法。',
        cardPosition: 'bottom'
      },
      {
        id: 'inspiration_filters',
        pageId: AppGuidePageId.INSPIRATION,
        anchorId: 'guide_inspiration_filters',
        title: '类型筛选会和上面的内容范围一起联动',
        message: '这一排负责在全部、书签、划线、想法之间切换。数字会随着内容范围变化而变化，所以如果你觉得结果太多，通常先缩小内容范围，再切类型筛选，会更容易找到目标。',
        cardPosition: 'bottom'
      },
      {
        id: 'inspiration_actions',
        pageId: AppGuidePageId.INSPIRATION,
        anchorId: 'guide_inspiration_actions',
        title: '批量整理主要在这一区完成',
        message: '当你需要集中处理灵感时，全选、分享已选、拼接复制都会从这里触发。它们只会作用于当前筛选后的可见内容，所以执行前最好先确认筛选范围没有选错。',
        cardPosition: 'top'
      },
      {
        id: 'inspiration_record_list',
        pageId: AppGuidePageId.INSPIRATION,
        anchorId: 'guide_inspiration_record_list',
        title: '下面的列表就是灵感正文和操作承载区',
        message: '每张卡片都会展示灵感内容本身，并继续承接编辑、定位原文、选择批量操作等后续动作。即使当前为空，这里也会明确告诉你是筛选结果为空，而不是页面加载异常。',
        cardPosition: 'top'
      },
      {
        id: 'inspiration_finish',
        pageId: AppGuidePageId.INSPIRATION,
        anchorId: 'guide_inspiration_record_list',
        title: '常用节奏是先缩小范围，再做整理和分享',
        message: '灵感页最常见的使用顺序是：先选内容，再切类型，最后批量整理或分享；如果你是从阅读器跳回来的，也可以在这里处理完，再继续返回原文阅读。',
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
        id: 'global_settings_reading_group',
        pageId: AppGuidePageId.GLOBAL_SETTINGS,
        anchorId: 'guide_global_settings_reading_group',
        title: '阅读相关的默认行为通常从这里开始改',
        message: '阅读模式、翻页动画、手势和交互习惯都拆到了对应分组里，建议先从阅读或页面设置开始调整。',
        cardPosition: 'bottom'
      },
      {
        id: 'global_settings_backup_group',
        pageId: AppGuidePageId.GLOBAL_SETTINGS,
        anchorId: 'guide_global_settings_backup_group',
        title: '备份、恢复和排障入口也集中在一级列表里',
        message: '准备换设备、清数据或排查异常时，优先来这里找到备份、错误管理和高级设置，先做保护性操作再继续修改。',
        cardPosition: 'top'
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
        message: '这里是 Suwayomi 服务器内容的浏览总入口，你可以在库模式查看已有漫画，也可以切到源模式管理和挑选图源，再继续进入详情页和阅读器。',
        cardPosition: 'bottom'
      },
      {
        id: 'suwayomi_bottom_tabs',
        pageId: AppGuidePageId.SUWAYOMI,
        anchorId: 'guide_suwayomi_bottom_tabs',
        title: '底部标签决定你现在是在看库，还是在看源',
        message: '“库”适合直接浏览已经同步到服务器里的漫画，“源”则适合查看当前安装的图源并进一步进入图源浏览。记住这两个模式的职责差别，后面操作会顺很多。',
        cardPosition: 'top'
      },
      {
        id: 'suwayomi_top_bar',
        pageId: AppGuidePageId.SUWAYOMI,
        anchorId: 'guide_suwayomi_top_bar',
        title: '顶部工具栏负责搜索、切换布局和进入设置',
        message: '这里的搜索会随着当前模式变化而变化：在库模式下是找漫画，在源模式下则是筛图源。右侧按钮还能切换网格或列表显示，并继续进入 Suwayomi 相关设置。',
        cardPosition: 'bottom'
      },
      {
        id: 'suwayomi_library_filters',
        pageId: AppGuidePageId.SUWAYOMI,
        anchorId: 'guide_suwayomi_library_filters',
        title: '库模式先用分类切范围，再继续浏览内容',
        message: '分类筛选适合先把漫画范围缩小到当前分类，再去看下方内容区；配合横向滑动切换分类，可以很快浏览不同分组，不需要每次都回到底部切模式。',
        cardPosition: 'bottom'
      },
      {
        id: 'suwayomi_library_content',
        pageId: AppGuidePageId.SUWAYOMI,
        anchorId: 'guide_suwayomi_library_content',
        title: '中间内容区会承接漫画浏览、下拉刷新和继续加载',
        message: '这里会根据当前分类与显示模式展示漫画卡片。下拉可以刷新，列表较长时还能继续加载更多；如果你主要是找书看，绝大多数时间都会停留在这一块。',
        cardPosition: 'top'
      },
      {
        id: 'suwayomi_source_content',
        pageId: AppGuidePageId.SUWAYOMI,
        anchorId: 'guide_suwayomi_source_content',
        title: '切到源模式后，这里会展示可用图源',
        message: '源模式更适合管理和挑选图源。上方搜索会变成过滤图源名称，如果当前源支持多语言，语言筛选也会在这个模式下出现在顶部，方便你快速缩小范围。',
        cardPosition: 'top'
      },
      {
        id: 'suwayomi_finish',
        pageId: AppGuidePageId.SUWAYOMI,
        anchorId: 'guide_suwayomi_source_content',
        title: '最常见的链路是先看库，再按需切到源',
        message: '推荐先在库模式里找现成漫画；如果没找到，再通过底部切到源模式挑图源或进入图源浏览。后续如果忘了这套节奏，也能在帮助中心里重新播放。',
        cardPosition: 'center',
        nextButtonText: '完成'
      }
    ]
  },
  {
    id: AppGuideFlowId.UNIFIED_DETAIL,
    title: '统一详情页引导',
    description: '介绍统一详情页中的信息区、阅读入口、工具操作与章节区域。',
    autoStartPageId: AppGuidePageId.UNIFIED_DETAIL,
    helpCenterReplayEnabled: false,
    steps: [
      {
        id: 'unified_detail_intro',
        pageId: AppGuidePageId.UNIFIED_DETAIL,
        anchorId: 'guide_unified_detail_header',
        title: '这是统一详情页',
        message: '漫画、小说和电子书都会在这里统一展示封面、标题、来源和当前阅读状态。进入后先在页头确认内容类型、来源和当前进度，可以避免把“在线内容”和“本地内容”的后续操作混在一起。',
        cardPosition: 'bottom'
      },
      {
        id: 'unified_detail_primary_action',
        pageId: AppGuidePageId.UNIFIED_DETAIL,
        anchorId: 'guide_unified_detail_primary_action',
        title: '最常用的入口在这里',
        message: '继续阅读、开始阅读通常都会从这个主按钮进入；如果当前内容支持听书或存在其他主要入口，也会在附近集中出现。想直接回到阅读流程时，优先看这里最省时间。',
        cardPosition: 'center'
      },
      {
        id: 'unified_detail_description',
        pageId: AppGuidePageId.UNIFIED_DETAIL,
        anchorId: 'guide_unified_detail_description',
        title: '标签和简介可以帮你快速判断内容',
        message: '这里可以查看标签、简介和补充说明，也是判断内容题材、状态和来源描述是否可靠的重要区域。简介支持展开，长按后还能直接复制或继续发起搜索。',
        cardPosition: 'top'
      },
      {
        id: 'unified_detail_action_bar',
        pageId: AppGuidePageId.UNIFIED_DETAIL,
        anchorId: 'guide_unified_detail_action_bar',
        title: '设置、换源、缓存等工具集中在这里',
        message: '不同内容类型会显示不同工具，例如设置、换源、浏览器、生成封面和缓存入口。准备做非阅读操作时，先扫这一排通常最快，不用在整个页面反复找按钮。',
        cardPosition: 'top'
      },
      {
        id: 'unified_detail_chapter_section',
        pageId: AppGuidePageId.UNIFIED_DETAIL,
        anchorId: 'guide_unified_detail_chapter_section',
        title: '章节区负责承接后续阅读和缓存操作',
        message: '这里会展示章节数量、阅读状态、排序和缓存情况，也是后续切章、缓存和继续阅读的主战场。即使电子书没有传统目录，这里也会承接文件信息和当前阅读进度。',
        cardPosition: 'top',
        nextButtonText: '完成'
      }
    ]
  },
  {
    id: AppGuideFlowId.GLOBAL_SEARCH,
    title: '全局搜索引导',
    description: '帮助你快速了解统一搜索入口、内容筛选，以及历史与结果区域的使用方式。',
    autoStartPageId: AppGuidePageId.GLOBAL_SEARCH,
    helpCenterReplayEnabled: true,
    helpCenterRouteName: 'GlobalSearchPage',
    steps: [
      {
        id: 'global_search_overview',
        pageId: AppGuidePageId.GLOBAL_SEARCH,
        anchorId: 'guide_global_search_root',
        title: '这里是统一搜索总入口',
        message: '本地内容、在线图源、小说书源和 Suwayomi 结果都会从这页统一汇总。使用时最重要的是先缩小范围，再决定是否扩展到在线来源。',
        cardPosition: 'bottom'
      },
      {
        id: 'global_search_input',
        pageId: AppGuidePageId.GLOBAL_SEARCH,
        anchorId: 'guide_global_search_input',
        title: '先从统一搜索入口开始',
        message: '关键词会从这里进入统一搜索链路。输入书名、作者、角色名或别名后，页面会按你当前启用的内容类型和来源范围去组织结果。',
        cardPosition: 'bottom'
      },
      {
        id: 'global_search_content_types',
        pageId: AppGuidePageId.GLOBAL_SEARCH,
        anchorId: 'guide_global_search_content_types',
        title: '先决定要找哪一类内容',
        message: '这里负责在全部、漫画、小说和电子书之间切换。结果太杂时，优先先缩小内容类型，通常比反复换关键词更有效。',
        cardPosition: 'bottom'
      },
      {
        id: 'global_search_source_types',
        pageId: AppGuidePageId.GLOBAL_SEARCH,
        anchorId: 'guide_global_search_source_types',
        title: '再决定查本地、在线还是全部来源',
        message: '本地适合查已导入内容，在线会联动图源、书源和 Suwayomi，全部则会一起搜索。想更快找到已有内容时先用本地，准备扩展搜索范围时再切在线或全部。',
        cardPosition: 'bottom',
        nextButtonText: '下一步'
      },
      {
        id: 'global_search_online_sources',
        pageId: AppGuidePageId.GLOBAL_SEARCH,
        anchorId: 'guide_global_search_online_sources',
        title: '在线源选择区决定具体要查哪些源',
        message: '当你切到在线或全部来源后，这里会出现图源和书源选择器。展开后可以按内容类型全选、清空或逐个勾选，减少无关源能明显提升结果可读性。',
        cardPosition: 'top'
      },
      {
        id: 'global_search_history_and_results',
        pageId: AppGuidePageId.GLOBAL_SEARCH,
        anchorId: 'guide_global_search_content_area',
        title: '下方区域会根据当前状态承接历史、进度和结果',
        message: '未搜索时这里会展示历史记录，搜索中会显示进度，搜索完成后则按来源分组呈现结果卡片。也就是说，真正的浏览、重复搜索和进入详情页，最后都会落到这一块。',
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
        message: '先记住漫画阅读器最核心的动作：点击阅读区域中央呼出菜单。章节切换、方向调整、阅读设置和自动翻页等操作，基本都要先通过这个动作进入控制层。',
        cardPosition: 'center'
      },
      {
        id: 'manga_reader_top_toolbar',
        pageId: AppGuidePageId.MANGA_READER,
        anchorId: 'guide_manga_reader_top_toolbar',
        title: '顶部工具栏负责返回、书签、灵感和更多入口',
        message: '这里可以快速返回、添加当前页书签、进入灵感页，也能打开更多菜单查看额外操作。遇到需要记录当前页、暂时离开阅读或把内容送去整理时，通常都会先用这里。',
        cardPosition: 'bottom'
      },
      {
        id: 'manga_reader_bottom_toolbar_progress',
        pageId: AppGuidePageId.MANGA_READER,
        anchorId: 'guide_manga_reader_bottom_toolbar',
        title: '底部工具栏先负责进度跳转和目录切换',
        message: '底部这一排里，最常用的是进度滑块和目录入口。想快速跳页、换章节或确认自己现在读到哪里时，优先从这里操作会比手动翻找快很多。',
        cardPosition: 'top'
      },
      {
        id: 'manga_reader_bottom_toolbar_settings',
        pageId: AppGuidePageId.MANGA_READER,
        anchorId: 'guide_manga_reader_bottom_toolbar',
        title: '同一排也承接快速设置、完整设置和自动翻页',
        message: '除了进度与目录，底部工具栏还会继续承接快速设置、完整阅读设置和自动翻页相关入口。方向、滚动模式、分页习惯不顺手时，重点就在这一排里调整。',
        cardPosition: 'top'
      },
      {
        id: 'manga_reader_chapter_list',
        pageId: AppGuidePageId.MANGA_READER,
        anchorId: 'guide_manga_reader_chapter_list',
        title: '目录面板用于章节切换和回到当前阅读位置',
        message: '章节很多时，先用目录找到目标章节，再回到底部工具栏继续细调阅读模式会更高效。长篇漫画最常见的“切章 -> 回读 -> 再跳转”流程，基本都从这里承接。',
        cardPosition: 'top'
      },
      {
        id: 'manga_reader_finish',
        pageId: AppGuidePageId.MANGA_READER,
        anchorId: 'guide_manga_reader_root',
        title: '记住中央点击和上下工具栏，漫画阅读就够用了',
        message: '把“中央点击呼出菜单”“顶部做记录和返回”“底部管进度与设置”这三个原则记住后，漫画阅读器的大多数高频操作就都能很快找到。',
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
        message: '点击正文中央可以呼出顶部和底部菜单。目录跳转、字体背景调整、分页方式和听书控制，都会从这一步之后继续展开。',
        cardPosition: 'center'
      },
      {
        id: 'novel_reader_top_toolbar',
        pageId: AppGuidePageId.NOVEL_READER,
        anchorId: 'guide_novel_reader_top_toolbar',
        title: '顶部工具栏负责返回、书签和灵感记录',
        message: '这里可以返回上一页、保存当前页书签，也可以把正在阅读的位置快速送到灵感页继续整理。想保留当前段落位置或中断阅读后稍后回来时，这一排最常用。',
        cardPosition: 'bottom'
      },
      {
        id: 'novel_reader_bottom_toolbar_progress',
        pageId: AppGuidePageId.NOVEL_READER,
        anchorId: 'guide_novel_reader_bottom_toolbar',
        title: '底部工具栏先负责进度跳转与目录定位',
        message: '进度条可以快速跳位置，目录入口则适合直接切章节。篇幅很长的小说，通常先用这里找到目标章节，再继续细调样式会更高效。',
        cardPosition: 'top'
      },
      {
        id: 'novel_reader_bottom_toolbar_style',
        pageId: AppGuidePageId.NOVEL_READER,
        anchorId: 'guide_novel_reader_bottom_toolbar',
        title: '同一排还承接字体、背景、阅读设置和听书',
        message: '字号、行距、背景、翻页方式以及听书控制，都集中在底部这一排。如果你觉得正文看着累、翻页不顺或想切到听书模式，重点就在这里调。',
        cardPosition: 'top'
      },
      {
        id: 'novel_reader_chapter_list',
        pageId: AppGuidePageId.NOVEL_READER,
        anchorId: 'guide_novel_reader_chapter_list',
        title: '目录面板适合快速切章和确认当前进度',
        message: '进入目录后可以直接跳到目标章节，也能更直观地确认当前阅读位置。长篇内容建议先用目录定位，再回到底部工具栏调整字号、背景和分页方式。',
        cardPosition: 'top'
      },
      {
        id: 'novel_reader_finish',
        pageId: AppGuidePageId.NOVEL_READER,
        anchorId: 'guide_novel_reader_root',
        title: '中央点击、顶部记录、底部调整，是小说阅读器的基本节奏',
        message: '把正文中央呼出菜单的动作记住后，再配合顶部做记录、底部调样式和听书，小说阅读器的大部分常用操作就都串起来了。',
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
        message: '电子书阅读器和小说阅读器很像，但更强调章节定位、文本排版和文件内目录。点击中央呼出菜单后，再去做后续跳转和样式调整会最顺手。',
        cardPosition: 'center'
      },
      {
        id: 'ebook_reader_top_toolbar',
        pageId: AppGuidePageId.EBOOK_READER,
        anchorId: 'guide_ebook_reader_top_toolbar',
        title: '顶部工具栏负责返回、书签、灵感和更多菜单',
        message: '这里可以返回书架、记录当前位置、跳到灵感页，也能打开更多菜单查看电子书专属的附加设置。需要临时离开阅读或标记当前位置时，通常先看这里。',
        cardPosition: 'bottom'
      },
      {
        id: 'ebook_reader_bottom_toolbar_progress',
        pageId: AppGuidePageId.EBOOK_READER,
        anchorId: 'guide_ebook_reader_bottom_toolbar',
        title: '底部工具栏先负责章节进度和目录定位',
        message: '滑块可以快速跳章节或位置，目录入口适合直接定位正文结构。电子书章节较多时，先用这里定位，再继续微调版式会更高效。',
        cardPosition: 'top'
      },
      {
        id: 'ebook_reader_bottom_toolbar_style',
        pageId: AppGuidePageId.EBOOK_READER,
        anchorId: 'guide_ebook_reader_bottom_toolbar',
        title: '同一排还承接文本样式、阅读选项和听书控制',
        message: '字体、背景、阅读选项和听书控制都集中在底部这一排。电子书正文如果排版太密、边距不舒服或者想切换听书，这里就是主操作区。',
        cardPosition: 'top'
      },
      {
        id: 'ebook_reader_chapter_list',
        pageId: AppGuidePageId.EBOOK_READER,
        anchorId: 'guide_ebook_reader_chapter_list',
        title: '目录面板适合快速定位章节',
        message: '长篇电子书建议先在目录里找到目标章节，再回到底部工具栏继续微调样式和阅读方式。需要在目录和正文之间来回切换时，这个面板会非常高频。',
        cardPosition: 'top'
      },
      {
        id: 'ebook_reader_finish',
        pageId: AppGuidePageId.EBOOK_READER,
        anchorId: 'guide_ebook_reader_root',
        title: '把中央点击和上下工具栏记住，电子书阅读就很完整了',
        message: '只要记住中央点击呼出控制层，再配合顶部做记录、底部调目录和样式，电子书阅读器的大多数核心操作都已经覆盖到了。',
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
  private flowOverrideMap: Map<AppGuideFlowId, AppGuideFlowDefinition> = new Map();
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
      const flow = this.getFlowDefinition(GUIDE_FLOWS[index].id);
      if (!flow) {
        continue;
      }
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

  public setFlowOverride(flow: AppGuideFlowDefinition): void {
    this.flowOverrideMap.set(flow.id, flow);
    if (this.activeFlowId === flow.id && this.activeStepIndex >= flow.steps.length) {
      this.activeStepIndex = Math.max(0, flow.steps.length - 1);
    }
  }

  public getFlowDefinition(flowId: AppGuideFlowId): AppGuideFlowDefinition | null {
    const override = this.flowOverrideMap.get(flowId);
    if (override) {
      return this.normalizeFlowDefinition(override);
    }
    for (let index = 0; index < GUIDE_FLOWS.length; index++) {
      if (GUIDE_FLOWS[index].id === flowId) {
        return this.normalizeFlowDefinition(GUIDE_FLOWS[index]);
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
      const currentFlow = this.getCurrentFlow();
      if (!currentFlow) {
        this.activeFlowId = null;
        this.activeStepIndex = 0;
        await this.saveActiveSession();
      } else {
        const currentStep = this.getCurrentStep();
        if (currentStep && currentStep.pageId === pageId) {
          return currentStep;
        }
        return null;
      }
    }

    for (let index = 0; index < GUIDE_FLOWS.length; index++) {
      const flow = this.getFlowDefinition(GUIDE_FLOWS[index].id);
      if (!flow) {
        continue;
      }
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

  private isSourceFeaturesEnabled(): boolean {
    const rawValue = AppStorage.get('source_features_enabled') as boolean | number | string | null | undefined;
    return rawValue === true || rawValue === 1 || rawValue === 'true' || rawValue === '1';
  }

  private cloneStep(step: AppGuideStep): AppGuideStep {
    return {
      id: step.id,
      pageId: step.pageId,
      anchorId: step.anchorId,
      title: step.title,
      message: step.message,
      cardPosition: step.cardPosition,
      nextButtonText: step.nextButtonText,
      showSkip: step.showSkip,
      borderRadius: step.borderRadius
    };
  }

  private cloneFlow(flow: AppGuideFlowDefinition): AppGuideFlowDefinition {
    const steps: AppGuideStep[] = [];
    for (let index = 0; index < flow.steps.length; index++) {
      steps.push(this.cloneStep(flow.steps[index]));
    }
    return {
      id: flow.id,
      title: flow.title,
      description: flow.description,
      autoStartPageId: flow.autoStartPageId,
      helpCenterReplayEnabled: flow.helpCenterReplayEnabled,
      helpCenterRouteName: flow.helpCenterRouteName,
      steps: steps
    };
  }

  private normalizeFlowDefinition(flow: AppGuideFlowDefinition): AppGuideFlowDefinition {
    const normalizedFlow = this.cloneFlow(flow);
    if (this.isSourceFeaturesEnabled()) {
      return normalizedFlow;
    }

    switch (normalizedFlow.id) {
      case AppGuideFlowId.MAIN_MENU_CORE:
        normalizedFlow.description = '介绍首页、书库、设置，以及从帮助中心重播引导的方式。';
        normalizedFlow.steps = normalizedFlow.steps.filter((step: AppGuideStep) => {
          return step.id !== 'main_source_tab' && step.id !== 'main_book_source_tab';
        });
        return normalizedFlow;
      case AppGuideFlowId.GLOBAL_SEARCH:
        normalizedFlow.description = '帮助你快速了解统一搜索入口、内容筛选，以及历史与结果区域的使用方式。';
        for (let index = 0; index < normalizedFlow.steps.length; index++) {
          const step = normalizedFlow.steps[index];
          if (step.id === 'global_search_overview') {
            step.message = '本地内容和其他可用结果都会从这页统一汇总。使用时最重要的是先缩小范围，再继续查看结果。';
          } else if (step.id === 'global_search_input') {
            step.message = '关键词会从这里进入统一搜索链路。输入书名、作者、角色名或别名后，页面会按你当前启用的内容类型组织结果。';
          } else if (step.id === 'global_search_history_and_results') {
            step.message = '未搜索时这里会展示历史记录，搜索中会显示进度，搜索完成后则按分组呈现结果卡片。也就是说，真正的浏览、重复搜索和进入详情页，最后都会落到这一块。';
          }
        }
        normalizedFlow.steps = normalizedFlow.steps.filter((step: AppGuideStep) => {
          return step.id !== 'global_search_source_types' && step.id !== 'global_search_online_sources';
        });
        return normalizedFlow;
      case AppGuideFlowId.SUWAYOMI:
        for (let index = 0; index < normalizedFlow.steps.length; index++) {
          const step = normalizedFlow.steps[index];
          if (step.id === 'suwayomi_intro') {
            step.message = '这里是 Suwayomi 服务器内容的浏览总入口，你可以在库模式查看已有漫画，也可以切到目录模式继续进入详情页和阅读器。';
          } else if (step.id === 'suwayomi_bottom_tabs') {
            step.title = '底部标签决定你现在是在看库，还是在看目录';
            step.message = '“库”适合直接浏览已经同步到服务器里的漫画，“目录”则适合查看当前可浏览的条目并继续进入内容浏览。记住这两个模式的职责差别，后面操作会顺很多。';
          } else if (step.id === 'suwayomi_top_bar') {
            step.message = '这里的搜索会随着当前模式变化而变化：在库模式下是找漫画，在目录模式下则是筛选可浏览条目。右侧按钮还能切换网格或列表显示，并继续进入 Suwayomi 相关设置。';
          } else if (step.id === 'suwayomi_source_content') {
            step.title = '切到目录模式后，这里会展示可用条目';
            step.message = '目录模式更适合管理和挑选可用条目。上方搜索会变成过滤条目名称，如果当前条目支持多语言，语言筛选也会在这个模式下出现在顶部，方便你快速缩小范围。';
          } else if (step.id === 'suwayomi_finish') {
            step.message = '推荐先在库模式里找现成漫画；如果没找到，再通过底部切到目录模式继续浏览。后续如果忘了这套节奏，也能在帮助中心里重新播放。';
          }
        }
        return normalizedFlow;
      default:
        return normalizedFlow;
    }
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
