import { SafeUtils } from 'manxia_core/src/main/ets/Utils/SafeUtils';
// 文件路径: entry/src/main/ets/pages/settings/SettingsSearchSupport.ets
/**
 * 设置搜索支持
 * - 提供统一的设置项索引与检索
 * - 提供跨页面跳转目标暂存/消费能力
 */

import { ThemeType } from 'manxia_theme/src/main/ets/Framework/Managers/ThemeManager';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';

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

interface SettingsSearchHighlightHost {
  activeSearchAnchorId: string;
  searchHighlightPulse: boolean;
  searchHighlightPulseTimer: number;
  searchHighlightClearTimer: number;
}

interface SettingsSearchHighlightShadowStyle {
  radius: number;
  color: string;
  offsetX: number;
  offsetY: number;
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
    { id: 'page_reader_multiton', title: '阅读器页面多开', description: '控制漫画/电子书/小说阅读器是否使用独立任务实例', targetPage: 'PageSettingsSubPage', anchorId: 'page_reader_multiton', scrollOffset: 360, keywords: ['阅读器页面多开', '阅读器多开', '独立实例', '主实例'] },
    { id: 'page_recommendation', title: '相关推荐', description: '统一详情页相关推荐开关', targetPage: 'PageSettingsSubPage', anchorId: 'page_detail', scrollOffset: 0, keywords: ['相关推荐', '同书架内容'] },
    { id: 'page_background_blur', title: '后台模糊遮罩', description: '多任务界面隐私保护模糊遮罩与图标类型', targetPage: 'PageSettingsSubPage', anchorId: 'page_background_blur', scrollOffset: 1180, keywords: ['后台模糊遮罩', '隐私遮罩', '后台遮罩', '遮罩图标', '锁定图标', '应用Logo'] },
    { id: 'page_global_background', title: '全局自定义背景', description: '为非主页面启用全局背景', targetPage: 'PageSettingsSubPage', anchorId: 'page_global_background', scrollOffset: 980, keywords: ['全局自定义背景', '非主页面背景', '自定义背景层'] },
    { id: 'shortcut_tip', title: '快捷方式说明', description: '桌面长按菜单最多显示4项，可长按拖动快捷方式到桌面', targetPage: 'ShortcutSettingsSubPage', anchorId: 'shortcut_info', scrollOffset: 0, keywords: ['快捷方式', '长按', '拖动到桌面', '桌面快捷'] },
    { id: 'shortcut_select', title: '快捷方式选择', description: '从5个预设中选择最多4个展示项', targetPage: 'ShortcutSettingsSubPage', anchorId: 'shortcut_core', scrollOffset: 380, keywords: ['快捷方式选择', '最多4个', '阅读报告', '全局搜索', '继续阅读', '继续听书', '灵感'] },
    { id: 'main_menu_library_view', title: '主页面书库显示模式', description: '平铺/书架视图切换，重启后生效', targetPage: 'MainMenuSettingsSubPage', anchorId: 'main_menu_behavior', scrollOffset: 0, keywords: ['书库默认视图', '书架视图', '默认视图', '分类书架', '主页面书库显示模式', '平铺', '书架'] },
    { id: 'main_menu_cover_click', title: '书库封面点击行为', description: '书库封面点击直达阅读开关', targetPage: 'MainMenuSettingsSubPage', anchorId: 'main_menu_behavior', scrollOffset: 0, keywords: ['封面点击', '直达阅读', '书库封面'] },
    { id: 'main_menu_book_source_auto_scroll', title: '书源筛选自动定位', description: '打开书源筛选时自动滑动到当前书源', targetPage: 'MainMenuSettingsSubPage', anchorId: 'main_menu_behavior', scrollOffset: 0, keywords: ['书源筛选', '自动滑动', '自动定位', '当前书源', '筛选对话框'] },
    { id: 'main_menu_privacy_auth', title: '隐私书库验证方式', description: '可关闭指纹识别并改为直接密码验证', targetPage: 'MainMenuSettingsSubPage', anchorId: 'main_menu_behavior', scrollOffset: 0, keywords: ['不使用指纹识别', '隐私书库验证', '跳过指纹', '密码验证'] },
    { id: 'main_menu_suwayomi_entry', title: 'Suwayomi入口行为', description: '主页面 Suwayomi 入口直达浏览页', targetPage: 'MainMenuSettingsSubPage', anchorId: 'main_menu_behavior', scrollOffset: 0, keywords: ['Suwayomi入口', '浏览页面作为入口'] },
    { id: 'main_menu_nav_tabs', title: '主导航栏标签显示与顺序', description: '自定义主导航栏标签及顺序', targetPage: 'MainMenuSettingsSubPage', anchorId: 'main_menu_navigation', scrollOffset: 820, keywords: ['主导航栏自定义', '标签顺序', '已启用', '未启用', '保存配置'] },
    { id: 'main_menu_tablet_nav', title: '平板横屏主导航栏位置', description: '平板/折叠屏主导航布局位置', targetPage: 'MainMenuSettingsSubPage', anchorId: 'main_menu_adaptive_nav', scrollOffset: 1360, keywords: ['平板横屏主导航栏位置', '折叠屏主导航布局', '上方', '下方', '左侧', '右侧'] },
    { id: 'main_menu_reset', title: '主页面设置恢复默认', description: '恢复主页面相关设置和主导航栏配置', targetPage: 'MainMenuSettingsSubPage', anchorId: 'main_menu_reset', scrollOffset: 2000, keywords: ['恢复主页面设置', '确认重置'] },
    { id: 'page_reset', title: '页面设置恢复默认', description: '恢复详情页和推荐相关设置', targetPage: 'PageSettingsSubPage', anchorId: 'page_reset', scrollOffset: 1500, keywords: ['恢复页面设置', '确认重置'] },

    // 重复检测设置
    { id: 'dup_detect_enabled', title: '重复检测开关', description: '添加内容时自动检测书库中的重复', targetPage: 'DuplicateDetectionSettingsSubPage', anchorId: 'dup_detect_rules', scrollOffset: 0, keywords: ['重复检测', '去重', '重复内容', '相似内容', '内容重复'] },
    { id: 'dup_detect_threshold', title: '重复检测阈值', description: '设置相似度百分比阈值', targetPage: 'DuplicateDetectionSettingsSubPage', anchorId: 'dup_detect_rules', scrollOffset: 0, keywords: ['相似度阈值', '重复度', '检测灵敏度', '阈值'] },
    { id: 'dup_detect_scope', title: '检测范围', description: '同类型检测或跨类型检测', targetPage: 'DuplicateDetectionSettingsSubPage', anchorId: 'dup_detect_rules', scrollOffset: 0, keywords: ['检测范围', '跨类型', '同类型'] },
    { id: 'dup_detect_weight', title: '匹配权重', description: '标题与作者的匹配权重分配', targetPage: 'DuplicateDetectionSettingsSubPage', anchorId: 'dup_detect_weight', scrollOffset: 400, keywords: ['标题权重', '作者权重', '匹配权重'] },

    // 字体设置
    { id: 'font_custom_manage', title: '自定义字体管理', description: '导入、预览与管理自定义字体', targetPage: 'FontSettingsSubPage', anchorId: 'font_custom', scrollOffset: 0, keywords: ['自定义字体管理', '导入字体', '系统字体', '自定义字体'] },
    { id: 'font_app', title: '界面字体设置', description: '切换APP界面字体样式', targetPage: 'FontSettingsSubPage', anchorId: 'font_app', scrollOffset: 320, keywords: ['界面字体', '界面字体样式'] },
    { id: 'font_novel', title: '小说字体设置', description: '切换小说阅读器字体样式', targetPage: 'FontSettingsSubPage', anchorId: 'font_novel', scrollOffset: 760, keywords: ['小说字体', '小说字体样式'] },
    { id: 'font_ebook', title: '电子书字体设置', description: '切换电子书阅读器字体样式', targetPage: 'FontSettingsSubPage', anchorId: 'font_ebook', scrollOffset: 1120, keywords: ['电子书字体', '电子书字体样式'] },
    { id: 'font_reset', title: '字体设置恢复默认', description: '恢复字体相关设置', targetPage: 'FontSettingsSubPage', anchorId: 'font_reset', scrollOffset: 1520, keywords: ['恢复默认', '重置字体设置'] },

    // 主题设置
    { id: 'theme_custom_manage', title: '自定义主题', description: '查看、应用、恢复和管理已保存的自定义主题', targetPage: 'ThemeSettingsPage', anchorId: 'theme_custom', scrollOffset: 0, keywords: ['主题设置', '自定义主题', '默认主题', '第一自定义主题', '第二自定义主题', '应用主题', '关闭自定义主题', '恢复默认主题'] },
    { id: 'theme_custom_create', title: '创建自定义主题', description: '创建新的主题并进入主题制作流程', targetPage: 'ThemeSettingsPage', anchorId: 'theme_custom', scrollOffset: 0, keywords: ['创建自定义主题', '新增主题', '主题商店', '主题列表'] },
    { id: 'theme_transparency_nav', title: '导航栏透明度', description: '调整导航栏、卡片、对话框和悬浮球透明度', targetPage: 'ThemeSettingsPage', anchorId: 'theme_transparency', scrollOffset: 280, keywords: ['透明度设置', '导航栏透明度', '卡片透明度', '对话框透明度', '悬浮球透明度', '预览效果'] },
    { id: 'theme_effects_blur', title: '主题特效', description: '模糊、阴影、动画、玻璃拟态和圆角效果', targetPage: 'ThemeSettingsPage', anchorId: 'theme_effects', scrollOffset: 880, keywords: ['特效设置', '模糊效果', '模糊强度', '阴影效果', '动画效果', '动画速度', '玻璃拟态效果', '重置为默认'] },
    { id: 'theme_effects_corner', title: '主题圆角', description: '分别调整组件圆角与封面图片圆角', targetPage: 'ThemeSettingsPage', anchorId: 'theme_effects', scrollOffset: 1040, keywords: ['组件圆角', '封面图片圆角', '封面圆角', '卡片圆角'] },
    { id: 'theme_hds_tab_effects', title: 'HdsTab特效', description: '调整 HDS 底栏透明度、高光、模糊策略、材质档位和留白', targetPage: 'ThemeSettingsPage', anchorId: 'theme_hds_tab_effects', scrollOffset: 1240, keywords: ['HdsTab特效', 'HDS底栏', 'HDS Tab', '底栏透明度', '高光强度', 'HDS模糊策略', '材质档位', '侧边留白', '底部偏移', '精致', '柔和', '平滑'] },
    { id: 'theme_create_background', title: '主题背景图片', description: '选择背景图片和开屏背景图片', targetPage: 'ThemeSettingsPage', anchorId: 'theme_create_background', scrollOffset: 1260, keywords: ['背景图片', '选择背景图片', '开屏背景图片', '开屏图片', '主题背景', '图片处理', '模糊程度', '亮度'] },
    { id: 'theme_create_colors', title: '主题色选择', description: '从图片提取主色调并选择主题色', targetPage: 'ThemeSettingsPage', anchorId: 'theme_create_colors', scrollOffset: 1900, keywords: ['选择主题色', '主题色', '主色调', '从图片提取', '可选主题色', '颜色提取'] },
    { id: 'theme_create_save', title: '保存主题', description: '填写主题名称并保存应用当前主题', targetPage: 'ThemeSettingsPage', anchorId: 'theme_create_save', scrollOffset: 2320, keywords: ['保存并应用主题', '主题名称', '保存主题', '应用主题', '创建主题'] },

    // 交互设置
    { id: 'interaction_switch', title: '启用震动反馈', description: '全局震动反馈开关', targetPage: 'InteractionSettingsSubPage', anchorId: 'interaction_basic', scrollOffset: 0, keywords: ['启用震动反馈', '震动反馈', '触觉反馈'] },
    { id: 'interaction_holding_awareness', title: '智感握姿', description: '全局握姿感知与主界面、阅读器、悬浮球适配开关', targetPage: 'InteractionSettingsSubPage', anchorId: 'interaction_holding_awareness', scrollOffset: 260, keywords: ['智感握姿', '握姿', '握持', '操作手', '主界面搜索按钮', '隐私退出按钮', '书架预览控件', '详情页横屏阅读按钮', '听书悬浮球', '后台任务悬浮球', '漫画条漫快速导航', '文本划线想法悬浮窗', '悬浮搜索按钮'] },
    { id: 'interaction_intensity', title: '震动强度', description: '设置震动强度等级', targetPage: 'InteractionSettingsSubPage', anchorId: 'interaction_intensity', scrollOffset: 380, keywords: ['震动强度', '强度等级'] },
    { id: 'interaction_scene', title: '场景震动设置', description: '按阅读/操作场景配置震动行为', targetPage: 'InteractionSettingsSubPage', anchorId: 'interaction_scene', scrollOffset: 760, keywords: ['场景设置', '阅读器', '翻页', '手势', '震动场景'] },
    { id: 'interaction_reset', title: '交互设置恢复默认', description: '恢复震动与触觉默认配置', targetPage: 'InteractionSettingsSubPage', anchorId: 'interaction_reset', scrollOffset: 1480, keywords: ['恢复默认设置', '交互设置重置'] },

    // 动画设置
    { id: 'animation_book', title: '书籍开关动画', description: '书籍打开动画、关闭动画及速度', targetPage: 'AnimationSettingsSubPage', anchorId: 'animation_book', scrollOffset: 0, keywords: ['书籍打开动画', '书籍关闭动画', '打开动画速度', '关闭动画速度'] },
    { id: 'main_menu_animation', title: '主页面动画', description: '主导航栏滚动隐藏/显示动画', targetPage: 'MainMenuSettingsSubPage', anchorId: 'main_menu_behavior', scrollOffset: 0, keywords: ['主页面动画', '主导航栏动画效果', '滚动隐藏', '底栏动画'] },
    { id: 'animation_reset', title: '动画设置恢复默认', description: '恢复全部动画设置默认值', targetPage: 'AnimationSettingsSubPage', anchorId: 'animation_reset', scrollOffset: 1220, keywords: ['恢复所有动画设置为默认值'] },

    // 视觉效果
    { id: 'visual_effects_capability', title: '视觉效果设备能力', description: '查看设备支持的材质类型、沉浸式材质能力与推荐档位', targetPage: 'VisualEffectsSettingsSubPage', anchorId: 'visual_effects_capability', scrollOffset: 0, keywords: ['视觉效果', '材质能力', 'hdsMaterial', '沉浸式材质', '设备支持', '推荐档位'] },
    { id: 'visual_effects_strategy', title: '视觉效果材质策略', description: '切换系统自适应或手动固定档位', targetPage: 'VisualEffectsSettingsSubPage', anchorId: 'visual_effects_strategy', scrollOffset: 520, keywords: ['系统自适应', '手动固定档位', '材质策略', '自定义档位', '手动档位'] },
    { id: 'visual_effects_effective', title: '视觉效果当前生效等级', description: '查看当前最终生效的材质等级与推荐说明', targetPage: 'VisualEffectsSettingsSubPage', anchorId: 'visual_effects_effective', scrollOffset: 980, keywords: ['当前生效等级', '材质等级', '推荐说明', 'effective'] },
    { id: 'visual_effects_actions', title: '视觉效果检测与重置', description: '重新检测设备能力或恢复推荐设置', targetPage: 'VisualEffectsSettingsSubPage', anchorId: 'visual_effects_actions', scrollOffset: 1420, keywords: ['重新检测', '恢复推荐设置', '检测设备能力', '重置视觉效果'] },

    // 进度记录与服务器
    { id: 'tracking_services', title: '进度记录与服务器', description: 'MAL/AniList/Bangumi 进度同步，以及 Suwayomi/Komga 服务器配置', targetPage: 'TrackingSettingsSubPage', anchorId: 'tracking_services', scrollOffset: 0, keywords: ['进度记录与服务器', '进度记录', '服务器', '同步服务', 'AniList', 'MAL', 'Bangumi', 'Suwayomi服务器', 'Komga服务器', 'Suwayomi', 'Komga'] },
    { id: 'tracking_info', title: '进度记录与服务器说明', description: '跟踪机制、服务器角色与同步规则说明', targetPage: 'TrackingSettingsSubPage', anchorId: 'tracking_info', scrollOffset: 680, keywords: ['关于进度记录与服务器', '跟踪是单向的', 'Suwayomi是服务器', 'Komga是服务器'] },
    { id: 'subscription_tracking', title: '内容更新跟踪', description: '管理应用内书架、远程库与作品级的提醒规则，当前版本会在回到前台时补查', targetPage: 'TrackingSettingsSubPage', anchorId: 'subscription_tracking', scrollOffset: 1180, keywords: ['内容更新跟踪', '内容跟踪', '统一跟踪管理', '更新跟踪规则', '自动检查更新', '自动下载', '书架跟踪', '远程库跟踪', '前台补查', '后台不检查'] },

    // 网络设置
    { id: 'network_download', title: '下载设置', description: '仅 WiFi 下载与最大并发下载数', targetPage: 'NetworkSettingsSubPage', anchorId: 'network_download', scrollOffset: 0, keywords: ['下载设置', '仅WiFi下载', '最大并发下载数'] },
    { id: 'network_request', title: '网络请求设置', description: '自定义 User-Agent 全局请求配置', targetPage: 'NetworkSettingsSubPage', anchorId: 'network_request', scrollOffset: 620, keywords: ['网络请求设置', '启用自定义User-Agent', '自定义User-Agent'] },

    // 通知设置
    { id: 'notification_core', title: '通知设置', description: '下载完成通知与更新通知', targetPage: 'NotificationSettingsSubPage', anchorId: 'notification_core', scrollOffset: 0, keywords: ['通知设置', '下载完成通知', '更新通知'] },

    // 高级设置
    { id: 'advanced_debug', title: '调试设置', description: '高级模式、日志、布局、SFW、更新与日志等级', targetPage: 'AdvancedSettingsSubPage', anchorId: 'advanced_debug', scrollOffset: 0, keywords: ['调试设置', '高级模式', '日志悬浮窗', '强制平板模式', '强制横屏模式', '预加载调试信息', 'SFW模式', '自动检查更新', '日志等级'] },
    { id: 'advanced_epub_webview', title: 'EPUB WebView 渲染引擎', description: '文字型 EPUB 的 WebView 排版渲染开关', targetPage: 'AdvancedSettingsSubPage', anchorId: 'advanced_debug', scrollOffset: 420, keywords: ['EPUB WebView 渲染引擎', 'EPUB渲染', 'WebView渲染', 'MD渲染', 'HTML渲染'] },
    { id: 'advanced_tools', title: '开发者工具', description: '日志管理、系统资源预览', targetPage: 'AdvancedSettingsSubPage', anchorId: 'advanced_tools', scrollOffset: 930, keywords: ['开发者工具', '日志管理', '系统资源预览'] },
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
      const parsed = SafeUtils.parseObj(payload) as SettingsSearchTarget;
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

  static activateHighlight(host: Object | undefined, anchorId: string, keepMs: number = 2800): void {
    if (!host) {
      return;
    }
    const highlightHost = host as SettingsSearchHighlightHost;
    SettingsSearchSupport.clearHighlight(host);
    highlightHost.activeSearchAnchorId = anchorId;
    highlightHost.searchHighlightPulse = true;
    highlightHost.searchHighlightPulseTimer = setTimeout(() => {
      highlightHost.searchHighlightPulse = false;
      highlightHost.searchHighlightPulseTimer = -1;
    }, 520);
    highlightHost.searchHighlightClearTimer = setTimeout(() => {
      highlightHost.activeSearchAnchorId = '';
      highlightHost.searchHighlightPulse = false;
      highlightHost.searchHighlightClearTimer = -1;
    }, keepMs);
  }

  static clearHighlight(host: Object | undefined): void {
    if (!host) {
      return;
    }
    const highlightHost = host as SettingsSearchHighlightHost;
    if (typeof highlightHost.searchHighlightPulseTimer === 'number' && highlightHost.searchHighlightPulseTimer >= 0) {
      clearTimeout(highlightHost.searchHighlightPulseTimer);
      highlightHost.searchHighlightPulseTimer = -1;
    }
    if (typeof highlightHost.searchHighlightClearTimer === 'number' && highlightHost.searchHighlightClearTimer >= 0) {
      clearTimeout(highlightHost.searchHighlightClearTimer);
      highlightHost.searchHighlightClearTimer = -1;
    }
    highlightHost.searchHighlightPulse = false;
    highlightHost.activeSearchAnchorId = '';
  }

  static isHighlightActive(activeAnchorId: string, anchorId: string): boolean {
    return activeAnchorId === anchorId;
  }

  static getHighlightScale(activeAnchorId: string, anchorId: string, pulsing: boolean): number {
    if (!SettingsSearchSupport.isHighlightActive(activeAnchorId, anchorId)) {
      return 1;
    }
    return pulsing ? 1.015 : 1;
  }

  static getHighlightOverlayBackground(theme: ThemeType, activeAnchorId: string, anchorId: string): string {
    if (!SettingsSearchSupport.isHighlightActive(activeAnchorId, anchorId)) {
      return 'rgba(0, 0, 0, 0)';
    }
    return theme === ThemeType.DARK ? 'rgba(66, 153, 225, 0.16)' : 'rgba(33, 150, 243, 0.10)';
  }

  static getHighlightOverlayBorder(theme: ThemeType, activeAnchorId: string, anchorId: string): string {
    if (!SettingsSearchSupport.isHighlightActive(activeAnchorId, anchorId)) {
      return 'rgba(0, 0, 0, 0)';
    }
    return theme === ThemeType.DARK ? 'rgba(120, 201, 255, 0.88)' : 'rgba(33, 150, 243, 0.82)';
  }

  static getHighlightOverlayShadow(
    theme: ThemeType,
    activeAnchorId: string,
    anchorId: string,
    pulsing: boolean
  ): SettingsSearchHighlightShadowStyle | undefined {
    if (!SettingsSearchSupport.isHighlightActive(activeAnchorId, anchorId)) {
      return undefined;
    }
    return {
      radius: pulsing ? 20 : 14,
      color: theme === ThemeType.DARK ? 'rgba(33, 150, 243, 0.28)' : 'rgba(33, 150, 243, 0.18)',
      offsetX: 0,
      offsetY: pulsing ? 8 : 4
    };
  }
}
