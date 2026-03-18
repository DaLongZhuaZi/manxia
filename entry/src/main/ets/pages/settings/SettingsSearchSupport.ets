// 文件路径: entry/src/main/ets/pages/settings/SettingsSearchSupport.ets
/**
 * 设置搜索支持
 * - 提供统一的设置项索引与检索
 * - 提供跨页面跳转目标暂存/消费能力
 */

import { logger } from '../../Utils/Logger';

const TAG = 'SettingsSearchSupport';

export interface SettingsSearchEntry {
  id: string;
  title: string;
  description: string;
  targetPage: string;
  anchorId: string;
  scrollOffset: number;
  keywords: string[];
}

export interface SettingsSearchResult extends SettingsSearchEntry {
  score: number;
  matchedKeyword: string;
}

export interface SettingsSearchTarget {
  id: string;
  query: string;
  title: string;
  targetPage: string;
  anchorId: string;
  scrollOffset: number;
  token: number;
}

const SETTINGS_SEARCH_STORAGE_KEY = 'settings_search_target_payload';

export class SettingsSearchSupport {
  private static readonly defaultResultLimit: number = 40;

  private static readonly entries: SettingsSearchEntry[] = [
    // 阅读设置
    { id: 'reading_manga_mode', title: '漫画默认阅读模式', description: '单页/双页/连续滚动/条漫模式', targetPage: 'ReadingSettingsSubPage', anchorId: 'reading_manga', scrollOffset: 0, keywords: ['漫画默认设置', '默认阅读模式', '单页', '双页', '连续滚动', '条漫模式'] },
    { id: 'reading_manga_direction', title: '漫画阅读方向', description: '从左到右、从右到左、从上到下', targetPage: 'ReadingSettingsSubPage', anchorId: 'reading_manga', scrollOffset: 0, keywords: ['默认阅读方向', '从左到右', '从右到左', '从上到下'] },
    { id: 'reading_manga_display', title: '漫画显示与翻页', description: '亮度、翻页动画、页码、页面指示器、图片适配', targetPage: 'ReadingSettingsSubPage', anchorId: 'reading_manga', scrollOffset: 0, keywords: ['默认亮度', '默认翻页动画', '显示页码信息', '显示页面指示器', '图片适配模式', '适宽', '适高', '原始'] },
    { id: 'reading_manga_behavior', title: '漫画交互行为', description: '常亮、音量键翻页、自动翻页、页面间距', targetPage: 'ReadingSettingsSubPage', anchorId: 'reading_manga', scrollOffset: 0, keywords: ['保持屏幕常亮', '音量键翻页', '自动翻页间隔', '页面间距'] },
    { id: 'reading_ebook_default', title: '电子书默认设置', description: '字体大小、行高、页边距、阅读主题和翻页模式', targetPage: 'ReadingSettingsSubPage', anchorId: 'reading_ebook', scrollOffset: 950, keywords: ['电子书默认设置', '默认字体大小', '默认行高', '默认页边距', '默认阅读主题', '默认翻页模式', '仿真翻页', '横向滑动'] },
    { id: 'reading_novel_default', title: '小说默认设置', description: '字体、背景、翻页、底部信息和自动翻页', targetPage: 'ReadingSettingsSubPage', anchorId: 'reading_novel', scrollOffset: 1800, keywords: ['小说阅读默认设置', '默认背景色', '背景图片', '背景图透明度', '文字颜色', '自动翻页', '底部显示模式', '显示时间', '显示电量'] },
    { id: 'reading_novel_layout', title: '小说排版设置', description: '字号、行高、段间距、首行缩进、字间距、文字对齐', targetPage: 'ReadingSettingsSubPage', anchorId: 'reading_novel', scrollOffset: 1800, keywords: ['段间距', '首行缩进', '字间距', '文字对齐', '左对齐', '居中', '两端'] },
    { id: 'reading_novel_font', title: '小说字体样式', description: '字体样式、字体粗细、自定义字体', targetPage: 'ReadingSettingsSubPage', anchorId: 'reading_novel', scrollOffset: 1800, keywords: ['字体样式', '字体粗细', '自定义字体'] },

    // 页面设置
    { id: 'page_detail_type', title: '详情页类型', description: '漫画/电子书/小说详情页类型与统一详情页', targetPage: 'PageSettingsSubPage', anchorId: 'page_detail', scrollOffset: 0, keywords: ['详情页设置', '漫画详情页', '电子书详情页', '小说详情页', '统一详情页'] },
    { id: 'page_recommendation', title: '相关推荐', description: '统一详情页相关推荐开关', targetPage: 'PageSettingsSubPage', anchorId: 'page_detail', scrollOffset: 0, keywords: ['相关推荐', '同书架内容'] },
    { id: 'page_library_view', title: '书库默认视图', description: '默认视图与书架视图切换', targetPage: 'PageSettingsSubPage', anchorId: 'page_library_view', scrollOffset: 520, keywords: ['书库默认视图', '书架视图', '默认视图', '分类书架'] },
    { id: 'page_nav_tabs', title: '主导航栏标签显示与顺序', description: '自定义主导航栏标签及顺序', targetPage: 'PageSettingsSubPage', anchorId: 'page_navigation', scrollOffset: 900, keywords: ['主导航栏自定义', '标签顺序', '已启用', '未启用', '保存配置'] },
    { id: 'page_tablet_nav', title: '平板横屏主导航栏位置', description: '平板/折叠屏主导航布局位置', targetPage: 'PageSettingsSubPage', anchorId: 'page_adaptive_nav', scrollOffset: 1450, keywords: ['平板横屏主导航栏位置', '折叠屏主导航布局', '上方', '下方', '左侧', '右侧'] },
    { id: 'page_reset', title: '页面设置恢复默认', description: '恢复页面设置和主导航栏配置', targetPage: 'PageSettingsSubPage', anchorId: 'page_reset', scrollOffset: 2100, keywords: ['恢复所有默认设置', '确认重置'] },

    // 字体设置
    { id: 'font_custom_manage', title: '自定义字体管理', description: '导入、预览与管理自定义字体', targetPage: 'FontSettingsSubPage', anchorId: 'font_custom', scrollOffset: 0, keywords: ['自定义字体管理', '导入字体', '系统字体', '自定义字体'] },
    { id: 'font_app', title: '界面字体设置', description: 'APP界面字体样式和大小倍率', targetPage: 'FontSettingsSubPage', anchorId: 'font_app', scrollOffset: 450, keywords: ['界面字体', '字体大小倍率'] },
    { id: 'font_novel', title: '小说字体设置', description: '小说字体、字号和行高倍率', targetPage: 'FontSettingsSubPage', anchorId: 'font_novel', scrollOffset: 920, keywords: ['小说字体', '字体大小', '行高倍率'] },
    { id: 'font_ebook', title: '电子书字体设置', description: '电子书字体、字号和行高倍率', targetPage: 'FontSettingsSubPage', anchorId: 'font_ebook', scrollOffset: 1400, keywords: ['电子书字体', '字体大小', '行高倍率'] },
    { id: 'font_reset', title: '字体设置恢复默认', description: '恢复字体相关设置', targetPage: 'FontSettingsSubPage', anchorId: 'font_reset', scrollOffset: 1880, keywords: ['恢复默认', '重置字体设置'] },

    // 交互设置
    { id: 'interaction_switch', title: '启用震动反馈', description: '全局震动反馈开关', targetPage: 'InteractionSettingsSubPage', anchorId: 'interaction_basic', scrollOffset: 0, keywords: ['启用震动反馈', '震动反馈', '触觉反馈'] },
    { id: 'interaction_intensity', title: '震动强度', description: '设置震动强度等级', targetPage: 'InteractionSettingsSubPage', anchorId: 'interaction_intensity', scrollOffset: 380, keywords: ['震动强度', '强度等级'] },
    { id: 'interaction_scene', title: '场景震动设置', description: '按阅读/操作场景配置震动行为', targetPage: 'InteractionSettingsSubPage', anchorId: 'interaction_scene', scrollOffset: 760, keywords: ['场景设置', '阅读器', '翻页', '手势', '震动场景'] },
    { id: 'interaction_reset', title: '交互设置恢复默认', description: '恢复震动与触觉默认配置', targetPage: 'InteractionSettingsSubPage', anchorId: 'interaction_reset', scrollOffset: 1480, keywords: ['恢复默认设置', '交互设置重置'] },

    // 动画设置
    { id: 'animation_book', title: '书籍开关动画', description: '书籍打开动画、关闭动画及速度', targetPage: 'AnimationSettingsSubPage', anchorId: 'animation_book', scrollOffset: 0, keywords: ['书籍打开动画', '书籍关闭动画', '打开动画速度', '关闭动画速度'] },
    { id: 'animation_main', title: '主页面动画', description: '主导航栏滚动隐藏/显示动画', targetPage: 'AnimationSettingsSubPage', anchorId: 'animation_main', scrollOffset: 620, keywords: ['主页面动画', '主导航栏动画效果', '滚动隐藏'] },
    { id: 'animation_reset', title: '动画设置恢复默认', description: '恢复全部动画设置默认值', targetPage: 'AnimationSettingsSubPage', anchorId: 'animation_reset', scrollOffset: 1220, keywords: ['恢复所有动画设置为默认值'] },

    // 进度记录
    { id: 'tracking_services', title: '进度记录服务', description: 'MAL/AniList/Bangumi 等同步服务配置', targetPage: 'TrackingSettingsSubPage', anchorId: 'tracking_services', scrollOffset: 0, keywords: ['进度记录', '未登录', 'AniList', 'MAL', 'Bangumi', 'Suwayomi'] },
    { id: 'tracking_info', title: '进度记录说明', description: '跟踪机制与同步规则说明', targetPage: 'TrackingSettingsSubPage', anchorId: 'tracking_info', scrollOffset: 680, keywords: ['关于进度记录', '注意：跟踪是单向的'] },

    // 网络设置
    { id: 'network_download', title: '下载设置', description: '仅 WiFi 下载与最大并发下载数', targetPage: 'NetworkSettingsSubPage', anchorId: 'network_download', scrollOffset: 0, keywords: ['下载设置', '仅WiFi下载', '最大并发下载数'] },
    { id: 'network_request', title: '网络请求设置', description: '自定义 User-Agent 全局请求配置', targetPage: 'NetworkSettingsSubPage', anchorId: 'network_request', scrollOffset: 620, keywords: ['网络请求设置', '启用自定义User-Agent', '自定义User-Agent'] },

    // 通知设置
    { id: 'notification_core', title: '通知设置', description: '下载完成通知与更新通知', targetPage: 'NotificationSettingsSubPage', anchorId: 'notification_core', scrollOffset: 0, keywords: ['通知设置', '下载完成通知', '更新通知'] },

    // 高级设置
    { id: 'advanced_debug', title: '调试设置', description: '高级模式、日志、布局、SFW、更新与隐私遮罩', targetPage: 'AdvancedSettingsSubPage', anchorId: 'advanced_debug', scrollOffset: 0, keywords: ['调试设置', '高级模式', '日志悬浮窗', '强制平板模式', '强制横屏模式', '预加载调试信息', 'SFW模式', '自动检查更新', '后台模糊遮罩', '日志等级'] },
    { id: 'advanced_tools', title: '开发者工具', description: '生命周期监控、日志管理、系统资源预览', targetPage: 'AdvancedSettingsSubPage', anchorId: 'advanced_tools', scrollOffset: 930, keywords: ['开发者工具', '生命周期监控', '日志管理', '系统资源预览'] },
    { id: 'advanced_actions', title: '高级其他操作', description: '重播引导页面等操作', targetPage: 'AdvancedSettingsSubPage', anchorId: 'advanced_actions', scrollOffset: 1560, keywords: ['其他操作', '重播引导页面', '需要重启应用'] },

    // 错误管理
    { id: 'error_summary', title: '错误统计', description: '总览统计、分类分布与高频模块', targetPage: 'ErrorManagementSubPage', anchorId: 'error_summary', scrollOffset: 0, keywords: ['错误统计', '分类分布', '高频模块'] },
    { id: 'error_filter', title: '错误筛选', description: '类型与分类筛选', targetPage: 'ErrorManagementSubPage', anchorId: 'error_filter', scrollOffset: 260, keywords: ['筛选', '运行时', '网络', '闪退', '分类筛选'] },
    { id: 'error_actions', title: '错误批量操作', description: '全选、删除、刷新、清空', targetPage: 'ErrorManagementSubPage', anchorId: 'error_actions', scrollOffset: 560, keywords: ['全选', '删除', '刷新', '清空'] },
    { id: 'error_list', title: '错误记录列表', description: '错误详情、导出与删除单条', targetPage: 'ErrorManagementSubPage', anchorId: 'error_list', scrollOffset: 920, keywords: ['堆栈信息', '导出此条', '删除', '暂无错误记录'] },
    { id: 'error_clear', title: '按时间清理错误日志', description: '按区间删除错误记录和日志文件', targetPage: 'ErrorManagementSubPage', anchorId: 'error_clear', scrollOffset: 1700, keywords: ['删除错误日志', '起始时间进度', '结束时间进度', '取消'] },

    // 数据管理（BackupPage）
    { id: 'backup_local', title: '本地备份', description: '创建本地备份、恢复、导入导出', targetPage: 'BackupPage', anchorId: 'backup_local', scrollOffset: 0, keywords: ['本地备份', '创建备份', '恢复备份', '导入备份'] },
    { id: 'backup_cloud', title: '云端备份', description: 'WebDAV 云端备份、同步、初始化', targetPage: 'BackupPage', anchorId: 'backup_cloud', scrollOffset: 0, keywords: ['云端备份', 'WebDAV', '初始化云端备份', '上传本地备份到云端'] },
    { id: 'backup_native', title: 'WebDAV Native 测试', description: '原生 WebDAV 能力测试配置', targetPage: 'BackupPage', anchorId: 'backup_native', scrollOffset: 0, keywords: ['Native测试', 'WebDAV Native 测试', '连接测试'] },
    { id: 'backup_ftp', title: 'FTP 管理', description: 'FTP 连接管理与文件浏览', targetPage: 'BackupPage', anchorId: 'backup_ftp', scrollOffset: 0, keywords: ['FTP管理', 'FTP连接', '文件浏览'] }
  ];

  private static normalize(text: string): string {
    return text
      .toLowerCase()
      .replace(/\s+/g, '')
      .replace(/[，。！？、；：“”"'‘’（）()\[\]【】\-_/:：]/g, '');
  }

  static search(query: string, limit: number = SettingsSearchSupport.defaultResultLimit): SettingsSearchResult[] {
    const normalizedQuery = SettingsSearchSupport.normalize(query);
    if (!normalizedQuery || normalizedQuery.length === 0) {
      return [];
    }

    const results: SettingsSearchResult[] = [];
    for (const entry of SettingsSearchSupport.entries) {
      const titleNorm = SettingsSearchSupport.normalize(entry.title);
      const descNorm = SettingsSearchSupport.normalize(entry.description);
      let score = 0;
      let matchedKeyword = '';

      if (titleNorm.includes(normalizedQuery)) {
        score += 120;
      }
      if (descNorm.includes(normalizedQuery)) {
        score += 70;
      }

      for (const keyword of entry.keywords) {
        const keywordNorm = SettingsSearchSupport.normalize(keyword);
        if (keywordNorm.includes(normalizedQuery)) {
          score += keywordNorm.startsWith(normalizedQuery) ? 56 : 42;
          if (matchedKeyword.length === 0) {
            matchedKeyword = keyword;
          }
        }
      }

      if (score > 0) {
        results.push({
          id: entry.id,
          title: entry.title,
          description: entry.description,
          targetPage: entry.targetPage,
          anchorId: entry.anchorId,
          scrollOffset: entry.scrollOffset,
          keywords: entry.keywords,
          score,
          matchedKeyword: matchedKeyword.length > 0 ? matchedKeyword : entry.title
        });
      }
    }

    results.sort((a: SettingsSearchResult, b: SettingsSearchResult) => {
      if (b.score !== a.score) {
        return b.score - a.score;
      }
      return a.title.localeCompare(b.title);
    });
    return results.slice(0, limit);
  }

  static setPendingTarget(target: SettingsSearchTarget): void {
    AppStorage.setOrCreate(SETTINGS_SEARCH_STORAGE_KEY, JSON.stringify(target));
  }

  static consumePendingTarget(pageName: string): SettingsSearchTarget | null {
    try {
      const payload = AppStorage.get<string>(SETTINGS_SEARCH_STORAGE_KEY);
      if (!payload || payload.length === 0) {
        return null;
      }
      const parsed = JSON.parse(payload) as SettingsSearchTarget;
      if (!parsed || parsed.targetPage !== pageName) {
        return null;
      }
      AppStorage.setOrCreate(SETTINGS_SEARCH_STORAGE_KEY, '');
      return parsed;
    } catch (error) {
      logger.error(TAG, '解析设置搜索目标失败', String(error));
      AppStorage.setOrCreate(SETTINGS_SEARCH_STORAGE_KEY, '');
      return null;
    }
  }

  static createTargetFromResult(result: SettingsSearchResult, query: string): SettingsSearchTarget {
    return {
      id: result.id,
      query,
      title: result.title,
      targetPage: result.targetPage,
      anchorId: result.anchorId,
      scrollOffset: result.scrollOffset,
      token: Date.now()
    };
  }
}
