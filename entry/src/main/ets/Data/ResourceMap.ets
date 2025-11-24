/**
 * =======================================================================================
 * 文件路径: src/main/ets/Data/ResourceMap.ets
 *
 * 文件职责:
 * 资源映射表。本文件的核心作用是作为“桥梁”，连接在运行时动态获取的资源路径字符串
 * （例如从配置文件 resources_metadata.json 中读取的 "app.media.logo"）
 * 与在编译时由 $r() 语法生成的、包含唯一资源ID的真实 Resource 对象。
 *
 * 为什么需要这个文件？
 * HarmonyOS的 $r() 资源访问符是一个编译时特性。它会在应用打包时，将 'app.media.logo'
 * 这样的资源名称直接替换成一个包含内部ID的Resource对象。这意味着，我们无法在运行时
 * 将一个动态的字符串变量（如 let path = "app.media.logo"）传递给 $r()。
 * 因此，我们需要一个像下面这样的静态映射表，在编译时就完成“字符串”到“Resource对象”的转换。
 *
 * 如何使用:
 * 1. 在您的 `resources/base/media` 或 `resources/base/element` 等目录下添加新资源。
 * 2. 在下面的映射表（如 imageMap, stringMap）中，添加一个新的键值对。
 * - `键 (key)`: 您在配置文件（如 resources_metadata.json）中使用的资源路径字符串。
 * - `值 (value)`: 使用 $r('...') 语法获取的对应资源的 Resource 对象。
 * 3. 在您的 ResourceManager 中，使用从配置文件读取的字符串作为键，来这个映射表中查找对应的 Resource 对象。
 *
 * 重要提示：
 * 存放在 `resources/base/rawfile/` 目录下的文件是“原始文件”，它们没有资源ID，
 * 也不通过 $r() 访问。因此，`rawfile` 目录下的任何文件都【不需要】也【不能】在这个文件中进行映射。
 * 它们应该直接通过其相对于 `rawfile` 目录的路径字符串来加载。
 * =======================================================================================
 */

// Resource 类型通过 $r() 函数返回，无需从 @ohos.resourceManager 导入
// 在 HarmonyOS 中，Resource 是内置类型，通过 $r() 函数获取

/**
 * 图片资源映射表 (Image Resource Map)
 *
 * 键 (Key):   字符串，与您在配置文件中为图片资源定义的`path`字段完全一致。
 * 值 (Value): 通过 $r('app.media.图片文件名') 获取的Resource对象。
 * 注意：文件名不需要包含后缀。
 */

import { logger } from "../Utils/Logger";

export const imageMap: Record<string, Resource> = {

  // 示例2：驴
  // 在 `resources_metadata.json` 中: "path": "app.media.SculptureLargeAnimalistA"
  'app.media.SculptureLargeAnimalistA': $r('app.media.SculptureLargeAnimalistA'),

  // 示例3：应用Logo
  // 在 `resources_metadata.json` 中: "path": "app.media.logo"
  'app.media.logo': $r('app.media.foreground'),

  // 返回按钮图标 - 暂时使用SculptureLargeAnimalistA代替，原图片应为返回箭头图标
  'app.media.ic_back': $r('app.media.SculptureLargeAnimalistA'),

  // 错误图标 - 使用新创建的ic_error SVG图标
  'app.media.ic_error': $r('app.media.ic_error'),

  // 图片图标 - 使用新创建的ic_image SVG图标
  'app.media.ic_image': $r('app.media.ic_image'),
  'app.media.ic_image_normal': $r('app.media.ic_image_normal'),
  'app.media.ic_image_selected': $r('app.media.ic_image_selected'),
  'app.media.ic_image_inactive': $r('app.media.ic_image_inactive'),

  // 搜索图标
  'app.media.ic_search_normal': $r('app.media.ic_search_normal'),
  'app.media.ic_search_selected': $r('app.media.ic_search_selected'),
  'app.media.ic_search_inactive': $r('app.media.ic_search_inactive'),

  // 列表视图图标
  'app.media.ic_view_list_normal': $r('app.media.ic_view_list_normal'),
  'app.media.ic_view_list_selected': $r('app.media.ic_view_list_selected'),
  'app.media.ic_view_list_inactive': $r('app.media.ic_view_list_inactive'),

  // 网格视图图标
  'app.media.ic_view_grid_normal': $r('app.media.ic_view_grid_normal'),
  'app.media.ic_view_grid_selected': $r('app.media.ic_view_grid_selected'),
  'app.media.ic_view_grid_inactive': $r('app.media.ic_view_grid_inactive'),

  // 性能图标
  'app.media.ic_performance_normal': $r('app.media.ic_performance_normal'),
  'app.media.ic_performance_selected': $r('app.media.ic_performance_selected'),
  'app.media.ic_performance_inactive': $r('app.media.ic_performance_inactive'),

  // 同步图标
  'app.media.ic_sync_normal': $r('app.media.ic_sync_normal'),
  'app.media.ic_sync_selected': $r('app.media.ic_sync_selected'),
  'app.media.ic_sync_inactive': $r('app.media.ic_sync_inactive'),

  // 系统图标
  'app.media.ic_system_normal': $r('app.media.ic_system_normal'),
  'app.media.ic_system_selected': $r('app.media.ic_system_selected'),
  'app.media.ic_system_inactive': $r('app.media.ic_system_inactive'),

  // 漫画阅读器页面图标映射
  'app.media.ic_arrow_back': $r('app.media.ic_arrow_right'), // 使用现有的右箭头图标代替
  'app.media.ic_more_vert': $r('app.media.ic_more'), // 使用现有的更多图标
  'app.media.ic_chevron_left': $r('app.media.ic_arrow_right'), // 使用右箭头图标代替左箭头
  'app.media.ic_settings': $r('app.media.ic_settings_normal'), // 使用现有的设置图标
  'app.media.ic_chevron_right': $r('app.media.ic_arrow_right'), // 使用现有的右箭头图标

  // 漫画详情页面图标映射
  'app.media.ic_image_placeholder': $r('app.media.ic_image_placeholder'), // 图片占位符图标
  'app.media.ic_favorite_filled': $r('app.media.ic_favorite_filled'), // 实心收藏图标
  'app.media.ic_favorite_outline': $r('app.media.ic_favorite_outline'), // 空心收藏图标
  'app.media.ic_sort': $r('app.media.ic_sort'), // 排序图标
  'app.media.ic_filter': $r('app.media.ic_filter'), // 筛选图标
  'app.media.ic_download_done': $r('app.media.ic_download_done'), // 下载完成图标

  // 电子书相关图标
  'app.media.ic_ebook': $r('app.media.ic_ebook'), // 电子书图标


  // 示例4：UI按钮纹理
  // 在 `resources_metadata.json` 中: "path": "app.media.ui_button"
  // 'app.media.ui_button': $r('app.media.ui_button'),

  // 如果您有更多图片资源，请继续在这里添加...
  // 'app.media.another_image': $r('app.media.another_image'),

  // 主页面标题图片
  'app.media.title_image': $r('app.media.SculptureLargeAnimalistA'),
};

/**
 * 音频资源映射表 (Audio Resource Map)
 *
 * 管理 `resources/base/media` 目录下的音频文件。
 */
export const audioMap: Record<string, Resource> = {
  // 示例：背景音乐
  // 在 `resources_metadata.json` 中: "path": "app.media.background_music"
  // 'app.media.background_music': $r('app.media.background_music'),

  // 如果您有更多音频资源，请继续在这里添加...
  // 'app.media.click_sound': $r('app.media.click_sound'),
};

/**
 * 字符串资源映射表 (String Resource Map)
 *
 * 管理 `resources/base/element/string.json` 中定义的字符串资源。
 */
export const stringMap: Record<string, Resource> = {
  // 模块描述
  'app.string.module_desc': $r('app.string.module_desc'),
  
  // 入口能力描述和标签
  'app.string.EntryAbility_desc': $r('app.string.EntryAbility_desc'),
  'app.string.EntryAbility_label': $r('app.string.EntryAbility_label'),
  
  // 权限申请原因
  'app.string.read_media_reason': $r('app.string.read_media_reason'),
  'app.string.write_media_reason': $r('app.string.write_media_reason'),
  'app.string.get_network_info_reason': $r('app.string.get_network_info_reason'),
  'app.string.internet_reason': $r('app.string.get_internet_reason'),

  // 如果您有更多字符串资源，请继续在这里添加...
  // 'app.string.welcome_message': $r('app.string.welcome_message'),
};

/**
 * 颜色资源映射表 (Color Resource Map)
 *
 * 管理 `resources/base/element/color.json` 中定义的颜色资源。
 * 键 (Key):   字符串，与您在 color.json 中为颜色定义的 "name" 字段所对应的映射路径一致。
 * 值 (Value): 通过 $r('app.color.颜色名称') 获取的Resource对象。
 */
export const colorMap: Record<string, Resource> = {
  // 基础颜色
  'app.color.accent': $r('app.color.accent'),
  'app.color.accent_background': $r('app.color.accent_background'),
  'app.color.start_window_background': $r('app.color.start_window_background'),
  'app.color.brand_primary': $r('app.color.brand_primary'),
  'app.color.brand_secondary': $r('app.color.brand_secondary'),
  'app.color.brand_light': $r('app.color.brand_light'),
  'app.color.brand': $r('app.color.brand'),
  'app.color.ohos_id_color_alert': $r('app.color.ohos_id_color_alert'),
  'app.color.background_primary': $r('app.color.background_primary'),
  'app.color.background_secondary': $r('app.color.background_secondary'),
  'app.color.text_primary': $r('app.color.text_primary'),
  'app.color.text_secondary': $r('app.color.text_secondary'),
  'app.color.divider_primary': $r('app.color.divider_primary'),
  'app.color.color_success': $r('app.color.color_success'),
  'app.color.color_warning': $r('app.color.color_warning'),
  'app.color.color_error': $r('app.color.color_error'),
  'app.color.color_info': $r('app.color.color_info'),
  
  // Console面板颜色
  'app.color.console_background_dark': $r('app.color.console_background_dark'),
  'app.color.console_panel_dark': $r('app.color.console_panel_dark'),
  'app.color.console_panel_secondary': $r('app.color.console_panel_secondary'),
  'app.color.console_border_dark': $r('app.color.console_border_dark'),
  'app.color.console_border_light': $r('app.color.console_border_light'),
  'app.color.console_border_active': $r('app.color.console_border_active'),
  'app.color.console_text_white': $r('app.color.console_text_white'),
  'app.color.console_text_light': $r('app.color.console_text_light'),
  'app.color.console_text_muted': $r('app.color.console_text_muted'),
  'app.color.console_text_dim': $r('app.color.console_text_dim'),
  'app.color.console_text_placeholder': $r('app.color.console_text_placeholder'),
  'app.color.console_button_primary': $r('app.color.console_button_primary'),
  'app.color.console_button_secondary': $r('app.color.console_button_secondary'),
  'app.color.console_button_danger': $r('app.color.console_button_danger'),
  'app.color.console_button_warning': $r('app.color.console_button_warning'),
  'app.color.console_button_success': $r('app.color.console_button_success'),
  'app.color.console_button_info': $r('app.color.console_button_info'),
  'app.color.console_button_purple': $r('app.color.console_button_purple'),
  'app.color.console_button_teal': $r('app.color.console_button_teal'),
  'app.color.console_button_orange': $r('app.color.console_button_orange'),
  'app.color.console_shadow_black': $r('app.color.console_shadow_black'),
  'app.color.console_brand_blue': $r('app.color.console_brand_blue'),
  'app.color.console_row_even': $r('app.color.console_row_even'),
  'app.color.console_row_odd': $r('app.color.console_row_odd'),
  'app.color.console_border_subtle': $r('app.color.console_border_subtle'),
  'app.color.console_background_darker': $r('app.color.console_background_darker'),
  'app.color.console_background_medium': $r('app.color.console_background_medium'),
  'app.color.console_toggle_off': $r('app.color.console_toggle_off'),
  'app.color.console_log_debug': $r('app.color.console_log_debug'),
  'app.color.background_disabled': $r('app.color.background_disabled'),
  'app.color.text_disabled': $r('app.color.text_disabled'),
  
  // 设置页面颜色
  'app.color.settings_background_dark': $r('app.color.settings_background_dark'),
  'app.color.settings_text_white': $r('app.color.settings_text_white'),
  'app.color.settings_text_muted': $r('app.color.settings_text_muted'),
  'app.color.settings_accent_green': $r('app.color.settings_accent_green'),
  'app.color.settings_text_black': $r('app.color.settings_text_black'),
  'app.color.settings_panel_background': $r('app.color.settings_panel_background'),
  'app.color.settings_panel_border': $r('app.color.settings_panel_border'),
  'app.color.settings_button_inactive': $r('app.color.settings_button_inactive'),
  'app.color.settings_slider_track': $r('app.color.settings_slider_track'),
  
  // 系统资源页面颜色
  'app.color.system_resource_tab_active_text': $r('app.color.system_resource_tab_active_text'),
  'app.color.system_resource_tab_inactive_text': $r('app.color.system_resource_tab_inactive_text'),
  'app.color.system_resource_tab_active_bg': $r('app.color.system_resource_tab_active_bg'),
  'app.color.system_resource_tab_inactive_bg': $r('app.color.system_resource_tab_inactive_bg'),
  'app.color.system_resource_border_light': $r('app.color.system_resource_border_light'),
  'app.color.system_resource_border_subtle': $r('app.color.system_resource_border_subtle'),
  'app.color.system_resource_background_overlay': $r('app.color.system_resource_background_overlay'),
  'app.color.system_resource_accent_green': $r('app.color.system_resource_accent_green'),
  'app.color.system_resource_text_muted': $r('app.color.system_resource_text_muted'),
  
  // 测试管理页面颜色
  'app.color.test_management_background_dark': $r('app.color.test_management_background_dark'),
  'app.color.test_management_text_white': $r('app.color.test_management_text_white'),
  'app.color.test_management_text_muted': $r('app.color.test_management_text_muted'),
  'app.color.test_management_text_dim': $r('app.color.test_management_text_dim'),
  'app.color.test_management_accent_green': $r('app.color.test_management_accent_green'),
  'app.color.test_management_text_black': $r('app.color.test_management_text_black'),
  'app.color.test_management_button_danger': $r('app.color.test_management_button_danger'),
  'app.color.test_management_panel_background': $r('app.color.test_management_panel_background'),
  'app.color.test_management_panel_border': $r('app.color.test_management_panel_border'),
  'app.color.test_management_button_inactive': $r('app.color.test_management_button_inactive'),
  'app.color.test_management_category_background': $r('app.color.test_management_category_background'),
  
  // 新增的缺失颜色资源
  // 测试管理页面新增颜色
  'app.color.test_management_background': $r('app.color.test_management_background'),
  'app.color.test_management_accent_blue': $r('app.color.test_management_accent_blue'),
  'app.color.test_management_accent_orange': $r('app.color.test_management_accent_orange'),
  'app.color.test_management_button_primary': $r('app.color.test_management_button_primary'),
  'app.color.test_management_button_secondary': $r('app.color.test_management_button_secondary'),
  
  // 主题相关颜色映射
  'app.color.test_management_background_light': $r('app.color.test_management_background_light'),
  'app.color.test_management_text_primary_light': $r('app.color.test_management_text_primary_light'),
  'app.color.test_management_text_secondary_light': $r('app.color.test_management_text_secondary_light'),
  'app.color.test_management_text_primary_dark': $r('app.color.test_management_text_primary_dark'),
  'app.color.test_management_text_secondary_dark': $r('app.color.test_management_text_secondary_dark'),
  'app.color.test_management_button_background_light': $r('app.color.test_management_button_background_light'),
  'app.color.test_management_button_background_dark': $r('app.color.test_management_button_background_dark'),
  'app.color.test_management_panel_background_light': $r('app.color.test_management_panel_background_light'),
  'app.color.test_management_panel_border_light': $r('app.color.test_management_panel_border_light'),
  'app.color.test_management_accent_primary_light': $r('app.color.test_management_accent_primary_light'),
  'app.color.test_management_accent_primary_dark': $r('app.color.test_management_accent_primary_dark'),
  'app.color.test_management_button_primary_light': $r('app.color.test_management_button_primary_light'),
  'app.color.test_management_button_secondary_light': $r('app.color.test_management_button_secondary_light'),
  'app.color.test_management_button_inactive_light': $r('app.color.test_management_button_inactive_light'),
  'app.color.test_management_divider_light': $r('app.color.test_management_divider_light'),
  'app.color.test_management_divider_dark': $r('app.color.test_management_divider_dark'),
  
  // 系统资源页面新增颜色
  'app.color.system_resource_text_white': $r('app.color.system_resource_text_white'),
  'app.color.system_resource_panel_background': $r('app.color.system_resource_panel_background'),
  'app.color.system_resource_panel_border': $r('app.color.system_resource_panel_border'),
  'app.color.system_resource_accent_blue': $r('app.color.system_resource_accent_blue'),
  'app.color.system_resource_accent_orange': $r('app.color.system_resource_accent_orange'),
  'app.color.system_resource_button_danger': $r('app.color.system_resource_button_danger'),
  'app.color.system_resource_button_primary': $r('app.color.system_resource_button_primary'),
  'app.color.system_resource_button_secondary': $r('app.color.system_resource_button_secondary'),
  'app.color.system_resource_background': $r('app.color.system_resource_background'),
  
  // 新增的通用颜色资源
  'app.color.background': $r('app.color.background'),
  'app.color.button_background': $r('app.color.button_background'),
  'app.color.panel_background': $r('app.color.panel_background'),
  'app.color.panel_border': $r('app.color.panel_border'),
  'app.color.background_card': $r('app.color.background_card'),
  'app.color.accent_primary': $r('app.color.accent_primary'),
  'app.color.button_primary': $r('app.color.button_primary'),
  'app.color.button_secondary': $r('app.color.button_secondary'),
  'app.color.button_inactive': $r('app.color.button_inactive'),
  'app.color.divider': $r('app.color.divider'),
  'app.color.text_white': $r('app.color.text_white'),
  'app.color.text_black': $r('app.color.text_black'),
  'app.color.text_muted': $r('app.color.text_muted'),
  'app.color.accent_green': $r('app.color.accent_green'),
  'app.color.button_danger': $r('app.color.button_danger'),
  'app.color.button_success': $r('app.color.button_success'),
  'app.color.button_warning': $r('app.color.button_warning'),
  'app.color.button_purple': $r('app.color.button_purple'),
  'app.color.button_info': $r('app.color.button_info'),
  'app.color.border_light': $r('app.color.border_light'),
  'app.color.border_active': $r('app.color.border_active'),
  'app.color.text_placeholder': $r('app.color.text_placeholder'),
  'app.color.background_darker': $r('app.color.background_darker'),
  'app.color.panel_dark': $r('app.color.panel_dark'),
  'app.color.border_subtle': $r('app.color.border_subtle'),
  'app.color.row_even': $r('app.color.row_even'),
  'app.color.row_odd': $r('app.color.row_odd'),
  'app.color.text_light': $r('app.color.text_light'),
  'app.color.background_dark': $r('app.color.background_dark'),
  'app.color.background_overlay': $r('app.color.background_overlay'),
  'app.color.glass_background_overlay': $r('app.color.glass_background_overlay'),
  'app.color.comp_background_tertiary': $r('app.color.comp_background_tertiary'),
  'app.color.icon_primary': $r('app.color.icon_primary'),
  'app.color.font_secondary': $r('app.color.font_secondary'),
  'app.color.text_dim': $r('app.color.text_dim'),
  'app.color.accent_blue': $r('app.color.accent_blue'),
  'app.color.accent_orange': $r('app.color.accent_orange'),
  'app.color.accent_secondary': $r('app.color.accent_secondary'),
  'app.color.color_neutral': $r('app.color.color_neutral'),
  'app.color.text_inverse': $r('app.color.text_inverse'),
  'app.color.background_inverse': $r('app.color.background_inverse'),
  'app.color.brand_tertiary': $r('app.color.brand_tertiary'),
  'app.color.shadow_black': $r('app.color.shadow_black'),
  'app.color.border_dark': $r('app.color.border_dark'),
  'app.color.brand_blue': $r('app.color.brand_blue'),
  
  // 新增的主题相关颜色映射（浅色模式）
  'app.color.test_management_background_primary_light': $r('app.color.test_management_background_primary_light'),
  'app.color.test_management_background_secondary_light': $r('app.color.test_management_background_secondary_light'),
  'app.color.test_management_background_dark_light': $r('app.color.test_management_background_dark_light'),
  'app.color.test_management_background_overlay_light': $r('app.color.test_management_background_overlay_light'),
  'app.color.test_management_comp_background_tertiary_light': $r('app.color.test_management_comp_background_tertiary_light'),
  'app.color.test_management_icon_primary_light': $r('app.color.test_management_icon_primary_light'),
  'app.color.test_management_font_secondary_light': $r('app.color.test_management_font_secondary_light'),
  'app.color.test_management_text_light_light': $r('app.color.test_management_text_light_light'),
  'app.color.test_management_accent_blue_light': $r('app.color.test_management_accent_blue_light'),
  'app.color.test_management_accent_orange_light': $r('app.color.test_management_accent_orange_light'),
  'app.color.test_management_accent_secondary_light': $r('app.color.test_management_accent_secondary_light'),
  'app.color.test_management_color_error_light': $r('app.color.test_management_color_error_light'),
  'app.color.test_management_color_success_light': $r('app.color.test_management_color_success_light'),
  'app.color.test_management_color_warning_light': $r('app.color.test_management_color_warning_light'),
  'app.color.test_management_color_info_light': $r('app.color.test_management_color_info_light'),
  'app.color.test_management_color_neutral_light': $r('app.color.test_management_color_neutral_light'),
  'app.color.test_management_text_inverse_light': $r('app.color.test_management_text_inverse_light'),
  'app.color.test_management_background_inverse_light': $r('app.color.test_management_background_inverse_light'),
  'app.color.test_management_brand_secondary_light': $r('app.color.test_management_brand_secondary_light'),
  'app.color.test_management_brand_tertiary_light': $r('app.color.test_management_brand_tertiary_light'),
  'app.color.test_management_shadow_black_light': $r('app.color.test_management_shadow_black_light'),
  'app.color.test_management_border_dark_light': $r('app.color.test_management_border_dark_light'),
  'app.color.test_management_brand_blue_light': $r('app.color.test_management_brand_blue_light'),
  'app.color.test_management_button_success_light': $r('app.color.test_management_button_success_light'),
  'app.color.test_management_button_warning_light': $r('app.color.test_management_button_warning_light'),
  'app.color.test_management_button_purple_light': $r('app.color.test_management_button_purple_light'),
  'app.color.test_management_button_info_light': $r('app.color.test_management_button_info_light'),
  'app.color.test_management_border_light_light': $r('app.color.test_management_border_light_light'),
  'app.color.test_management_border_active_light': $r('app.color.test_management_border_active_light'),
  'app.color.test_management_text_placeholder_light': $r('app.color.test_management_text_placeholder_light'),
  'app.color.test_management_background_darker_light': $r('app.color.test_management_background_darker_light'),
  'app.color.test_management_panel_dark_light': $r('app.color.test_management_panel_dark_light'),
  'app.color.test_management_border_subtle_light': $r('app.color.test_management_border_subtle_light'),
  'app.color.test_management_row_even_light': $r('app.color.test_management_row_even_light'),
  'app.color.test_management_row_odd_light': $r('app.color.test_management_row_odd_light'),
  'app.color.test_management_brand_light': $r('app.color.test_management_brand_light'),
  
  // 新增的主题相关颜色映射（深色模式）
  'app.color.test_management_background_primary_dark': $r('app.color.test_management_background_primary_dark'),
  'app.color.test_management_background_secondary_dark': $r('app.color.test_management_background_secondary_dark'),
  'app.color.test_management_background_dark_dark': $r('app.color.test_management_background_dark_dark'),
  'app.color.test_management_background_overlay_dark': $r('app.color.test_management_background_overlay_dark'),
  'app.color.test_management_comp_background_tertiary_dark': $r('app.color.test_management_comp_background_tertiary_dark'),
  'app.color.test_management_icon_primary_dark': $r('app.color.test_management_icon_primary_dark'),
  'app.color.test_management_font_secondary_dark': $r('app.color.test_management_font_secondary_dark'),
  'app.color.test_management_text_light_dark': $r('app.color.test_management_text_light_dark'),
  'app.color.test_management_accent_blue_dark': $r('app.color.test_management_accent_blue_dark'),
  'app.color.test_management_accent_orange_dark': $r('app.color.test_management_accent_orange_dark'),
  'app.color.test_management_accent_secondary_dark': $r('app.color.test_management_accent_secondary_dark'),
  'app.color.test_management_color_error_dark': $r('app.color.test_management_color_error_dark'),
  'app.color.test_management_color_success_dark': $r('app.color.test_management_color_success_dark'),
  'app.color.test_management_color_warning_dark': $r('app.color.test_management_color_warning_dark'),
  'app.color.test_management_color_info_dark': $r('app.color.test_management_color_info_dark'),
  'app.color.test_management_color_neutral_dark': $r('app.color.test_management_color_neutral_dark'),
  'app.color.test_management_text_inverse_dark': $r('app.color.test_management_text_inverse_dark'),
  'app.color.test_management_background_inverse_dark': $r('app.color.test_management_background_inverse_dark'),
  'app.color.test_management_brand_secondary_dark': $r('app.color.test_management_brand_secondary_dark'),
  'app.color.test_management_brand_tertiary_dark': $r('app.color.test_management_brand_tertiary_dark'),
  'app.color.test_management_shadow_black_dark': $r('app.color.test_management_shadow_black_dark'),
  'app.color.test_management_border_dark_dark': $r('app.color.test_management_border_dark_dark'),
  'app.color.test_management_brand_blue_dark': $r('app.color.test_management_brand_blue_dark'),
  'app.color.test_management_button_success_dark': $r('app.color.test_management_button_success_dark'),
  'app.color.test_management_button_warning_dark': $r('app.color.test_management_button_warning_dark'),
  'app.color.test_management_button_purple_dark': $r('app.color.test_management_button_purple_dark'),
  'app.color.test_management_button_info_dark': $r('app.color.test_management_button_info_dark'),
  'app.color.test_management_border_light_dark': $r('app.color.test_management_border_light_dark'),
  'app.color.test_management_border_active_dark': $r('app.color.test_management_border_active_dark'),
  'app.color.test_management_text_placeholder_dark': $r('app.color.test_management_text_placeholder_dark'),
  'app.color.test_management_background_darker_dark': $r('app.color.test_management_background_darker_dark'),
  'app.color.test_management_panel_dark_dark': $r('app.color.test_management_panel_dark_dark'),
  'app.color.test_management_border_subtle_dark': $r('app.color.test_management_border_subtle_dark'),
  'app.color.test_management_row_even_dark': $r('app.color.test_management_row_even_dark'),
  'app.color.test_management_row_odd_dark': $r('app.color.test_management_row_odd_dark'),
  'app.color.test_management_brand_dark': $r('app.color.test_management_brand_dark'),
  'app.color.test_management_button_inactive_dark': $r('app.color.test_management_button_inactive_dark'),
  
  // 通用颜色映射 - 浅色模式
  'app.color.test_management_text_white_light': $r('app.color.test_management_text_white_light'),
  'app.color.test_management_text_black_light': $r('app.color.test_management_text_black_light'),
  'app.color.test_management_text_muted_light': $r('app.color.test_management_text_muted_light'),
  'app.color.test_management_accent_green_light': $r('app.color.test_management_accent_green_light'),
  
  // 通用颜色映射 - 深色模式
  'app.color.test_management_text_white_dark': $r('app.color.test_management_text_white_dark'),
  'app.color.test_management_text_black_dark': $r('app.color.test_management_text_black_dark'),
  'app.color.test_management_text_muted_dark': $r('app.color.test_management_text_muted_dark'),
  'app.color.test_management_accent_green_dark': $r('app.color.test_management_accent_green_dark'),
  'app.color.test_management_button_text_primary_light': $r('app.color.test_management_button_text_primary_light'),
  'app.color.test_management_button_text_primary_dark': $r('app.color.test_management_button_text_primary_dark'),
  'app.color.test_management_button_text_secondary_light': $r('app.color.test_management_button_text_secondary_light'),
  'app.color.test_management_button_text_secondary_dark': $r('app.color.test_management_button_text_secondary_dark'),
  
  // 新增缺失的主题颜色资源
  'app.color.comp_background_secondary': $r('app.color.ohos_id_color_background_secondary'),
  'app.color.comp_background_primary': $r('sys.color.ohos_id_color_background'),
  'app.color.success_border': $r('app.color.ohos_id_color_success'),
  'app.color.comp_border_primary': $r('sys.color.ohos_id_color_component_normal'),
  'app.color.success_text': $r('app.color.ohos_id_color_success'),
  'app.color.error_text': $r('sys.color.ohos_id_color_warning'),
  'app.color.error_border': $r('sys.color.ohos_id_color_warning'),
  
  // 按钮颜色资源
  'app.color.test_management_button_primary_dark': $r('sys.color.ohos_id_color_emphasize'),
  'app.color.test_management_button_secondary_dark': $r('sys.color.ohos_id_color_secondary'),


  // 新增的测试管理页面主题颜色资源
  'app.color.test_management_comp_background_secondary_light': $r('app.color.test_management_comp_background_secondary_light'),
  'app.color.test_management_comp_background_secondary_dark': $r('app.color.test_management_comp_background_secondary_dark'),
  'app.color.test_management_comp_background_primary_light': $r('app.color.test_management_comp_background_primary_light'),
  'app.color.test_management_comp_background_primary_dark': $r('app.color.test_management_comp_background_primary_dark')
};

// 漫画详情页渐变颜色资源
// 统一在颜色资源映射中暴露，便于通过 ThemeAwareHelper 按主题检索
colorMap['app.color.manga_detail_gradient_start_light'] = $r('app.color.manga_detail_gradient_start_light');
colorMap['app.color.manga_detail_gradient_mid_light'] = $r('app.color.manga_detail_gradient_mid_light');
colorMap['app.color.manga_detail_gradient_end_light'] = $r('app.color.manga_detail_gradient_end_light');
colorMap['app.color.manga_detail_gradient_start_dark'] = $r('app.color.manga_detail_gradient_start_dark');
colorMap['app.color.manga_detail_gradient_mid_dark'] = $r('app.color.manga_detail_gradient_mid_dark');
colorMap['app.color.manga_detail_gradient_end_dark'] = $r('app.color.manga_detail_gradient_end_dark');

/**
 * 统一的资源映射查找器 (Optional Helper)
 * 这是一个可选的辅助工具，可以根据资源类型在不同的映射表中查找。
 *
 * @param path - 从配置文件中读取的资源路径字符串。
 * @returns 对应的 Resource 对象，如果未找到则返回 undefined。
 */
export function findResourceInMap(path: string): Resource | undefined {
  if (path.startsWith('app.media.')) {
    // 尝试在 imageMap 和 audioMap 中查找
    return imageMap[path] ?? audioMap[path];
  }
  if (path.startsWith('app.string.')) {
    return stringMap[path];
  }
  if (path.startsWith('app.color.')) {
    return colorMap[path];
  }
  // ...

  logger.warn('ResourceMap', `在任何资源映射表中都未找到路径: ${path}`);
  return undefined;
}
