/**
 * 共享 UI 资源目录。
 *
 * 资源文件只在资源所属模块保存一份，运行时仅通过 key 查找 Resource。
 * Map 中的 key 是逻辑资源路径，legacy alias 不对应额外的物理文件。
 */

export interface ResourceCatalogEntry {
  key: string;
  resource: Resource;
}

const mediaResources: Map<string, Resource> = new Map<string, Resource>();
const colorResources: Map<string, Resource> = new Map<string, Resource>();
const stringResources: Map<string, Resource> = new Map<string, Resource>();
const systemResources: Map<string, Resource> = new Map<string, Resource>();
const legacyAliases: Map<string, string> = new Map<string, string>();
const warnedKeys: Set<string> = new Set<string>();
const fallbackColorResource: Resource = $r('app.color.transparent');
const fallbackMediaResource: Resource = $r('app.media.ic_image');

function registerMedia(key: string, resource: Resource): void {
  mediaResources.set(key, resource);
}

function registerColor(key: string, resource: Resource): void {
  colorResources.set(key, resource);
}

function registerSystem(key: string, resource: Resource): void {
  systemResources.set(key, resource);
}

function registerString(key: string, resource: Resource): void {
  stringResources.set(key, resource);
}

function registerAlias(legacyKey: string, canonicalKey: string): void {
  legacyAliases.set(legacyKey, canonicalKey);
}

// Shared media resources. Entry-only launch resources remain in entry/module.json5.
registerMedia('app.media.a_1', $r('app.media.a_1'));
registerMedia('app.media.a_2', $r('app.media.a_2'));
registerMedia('app.media.a_3', $r('app.media.a_3'));
registerMedia('app.media.anilist_icon', $r('app.media.anilist_icon'));
registerMedia('app.media.avatar_256', $r('app.media.avatar_256'));
registerMedia('app.media.b_1', $r('app.media.b_1'));
registerMedia('app.media.b_2', $r('app.media.b_2'));
registerMedia('app.media.b_3', $r('app.media.b_3'));
registerMedia('app.media.background', $r('app.media.background'));
registerMedia('app.media.ic_bg_startwindow', $r('app.media.ic_bg_startwindow'));
registerMedia('app.media.ic_fg', $r('app.media.ic_fg'));
registerMedia('app.media.ic_fg_startwindow', $r('app.media.ic_fg_startwindow'));
registerMedia('app.media.bg1', $r('app.media.bg1'));
registerMedia('app.media.bg2', $r('app.media.bg2'));
registerMedia('app.media.bookshelf', $r('app.media.bookshelf'));
registerMedia('app.media.cat_dark_1', $r('app.media.cat_dark_1'));
registerMedia('app.media.cat_dark_2', $r('app.media.cat_dark_2'));
registerMedia('app.media.cat_dark_3', $r('app.media.cat_dark_3'));
registerMedia('app.media.ebook', $r('app.media.ebook'));
registerMedia('app.media.fg1', $r('app.media.fg1'));
registerMedia('app.media.fg2', $r('app.media.fg2'));
registerMedia('app.media.foreground', $r('app.media.foreground'));
registerMedia('app.media.icon', $r('app.media.icon'));
registerMedia('app.media.komga_icon', $r('app.media.komga_icon'));
registerMedia('app.media.legado', $r('app.media.legado'));
registerMedia('app.media.logo', $r('app.media.logo'));
registerMedia('app.media.lumabloom_icon', $r('app.media.lumabloom_icon'));
registerMedia('app.media.mangabook', $r('app.media.mangabook'));
registerMedia('app.media.mm_reward_qrcode', $r('app.media.mm_reward_qrcode'));
registerMedia('app.media.ngfcoder_icon', $r('app.media.ngfcoder_icon'));
registerMedia('app.media.SculptureLargeAnimalistA', $r('app.media.SculptureLargeAnimalistA'));
registerMedia('app.media.shumai_icon', $r('app.media.shumai_icon'));
registerMedia('app.media.suwayomi_icon', $r('app.media.suwayomi_icon'));

registerMedia('app.media.ic_add', $r('app.media.ic_add'));
registerMedia('app.media.ic_analytics', $r('app.media.ic_analytics'));
registerMedia('app.media.ic_analytics_inactive', $r('app.media.ic_analytics_inactive'));
registerMedia('app.media.ic_analytics_normal', $r('app.media.ic_analytics_normal'));
registerMedia('app.media.ic_analytics_selected', $r('app.media.ic_analytics_selected'));
registerMedia('app.media.ic_arrow_back', $r('app.media.ic_arrow_back'));
registerMedia('app.media.ic_arrow_down', $r('app.media.ic_arrow_down'));
registerMedia('app.media.ic_arrow_left', $r('app.media.ic_arrow_left'));
registerMedia('app.media.ic_arrow_right', $r('app.media.ic_arrow_right'));
registerMedia('app.media.ic_auto', $r('app.media.ic_auto'));
registerMedia('app.media.ic_auto_color', $r('app.media.ic_auto_color'));
registerMedia('app.media.ic_auto_selected', $r('app.media.ic_auto_selected'));
registerMedia('app.media.ic_bg', $r('app.media.ic_bg'));
registerMedia('app.media.ic_book', $r('app.media.ic_book'));
registerMedia('app.media.ic_book_color', $r('app.media.ic_book_color'));
registerMedia('app.media.ic_book_selected', $r('app.media.ic_book_selected'));
registerMedia('app.media.ic_bookmark', $r('app.media.ic_bookmark'));
registerMedia('app.media.ic_brightness_high', $r('app.media.ic_brightness_high'));
registerMedia('app.media.ic_brightness_low', $r('app.media.ic_brightness_low'));
registerMedia('app.media.ic_cache', $r('app.media.ic_cache'));
registerMedia('app.media.ic_calendar_day', $r('app.media.ic_calendar_day'));
registerMedia('app.media.ic_calendar_range', $r('app.media.ic_calendar_range'));
registerMedia('app.media.ic_cancel', $r('app.media.ic_cancel'));
registerMedia('app.media.ic_check', $r('app.media.ic_check'));
registerMedia('app.media.ic_checkbox', $r('app.media.ic_checkbox'));
registerMedia('app.media.ic_chevron_left', $r('app.media.ic_chevron_left'));
registerMedia('app.media.ic_chevron_right', $r('app.media.ic_chevron_right'));
registerMedia('app.media.ic_close', $r('app.media.ic_close'));
registerMedia('app.media.ic_continuous', $r('app.media.ic_continuous'));
registerMedia('app.media.ic_data_management', $r('app.media.ic_data_management'));
registerMedia('app.media.ic_database', $r('app.media.ic_database'));
registerMedia('app.media.ic_delete', $r('app.media.ic_delete'));
registerMedia('app.media.ic_discover_normal', $r('app.media.ic_discover_normal'));
registerMedia('app.media.ic_discover_selected', $r('app.media.ic_discover_selected'));
registerMedia('app.media.ic_double_page', $r('app.media.ic_double_page'));
registerMedia('app.media.ic_download', $r('app.media.ic_download'));
registerMedia('app.media.ic_download_done', $r('app.media.ic_download_done'));
registerMedia('app.media.ic_download_inactive', $r('app.media.ic_download_inactive'));
registerMedia('app.media.ic_download_normal', $r('app.media.ic_download_normal'));
registerMedia('app.media.ic_download_selected', $r('app.media.ic_download_selected'));
registerMedia('app.media.ic_ebook', $r('app.media.ic_ebook'));
registerMedia('app.media.ic_edit', $r('app.media.ic_edit'));
registerMedia('app.media.ic_empty', $r('app.media.ic_empty'));
registerMedia('app.media.ic_error', $r('app.media.ic_error'));
registerMedia('app.media.ic_favorite_filled', $r('app.media.ic_favorite_filled'));
registerMedia('app.media.ic_favorite_outline', $r('app.media.ic_favorite_outline'));
registerMedia('app.media.ic_feedback', $r('app.media.ic_feedback'));
registerMedia('app.media.ic_filter', $r('app.media.ic_filter'));
registerMedia('app.media.ic_guide_import', $r('app.media.ic_guide_import'));
registerMedia('app.media.ic_guide_library', $r('app.media.ic_guide_library'));
registerMedia('app.media.ic_guide_log', $r('app.media.ic_guide_log'));
registerMedia('app.media.ic_home_normal', $r('app.media.ic_home_normal'));
registerMedia('app.media.ic_home_selected', $r('app.media.ic_home_selected'));
registerMedia('app.media.ic_image', $r('app.media.ic_image'));
registerMedia('app.media.ic_image_inactive', $r('app.media.ic_image_inactive'));
registerMedia('app.media.ic_image_normal', $r('app.media.ic_image_normal'));
registerMedia('app.media.ic_image_placeholder', $r('app.media.ic_image_placeholder'));
registerMedia('app.media.ic_image_selected', $r('app.media.ic_image_selected'));
registerMedia('app.media.ic_info', $r('app.media.ic_info'));
registerMedia('app.media.ic_library_empty', $r('app.media.ic_library_empty'));
registerMedia('app.media.ic_library_normal', $r('app.media.ic_library_normal'));
registerMedia('app.media.ic_library_selected', $r('app.media.ic_library_selected'));
registerMedia('app.media.ic_list', $r('app.media.ic_list'));
registerMedia('app.media.ic_log', $r('app.media.ic_log'));
registerMedia('app.media.ic_log_inactive', $r('app.media.ic_log_inactive'));
registerMedia('app.media.ic_log_normal', $r('app.media.ic_log_normal'));
registerMedia('app.media.ic_log_selected', $r('app.media.ic_log_selected'));
registerMedia('app.media.ic_login', $r('app.media.ic_login'));
registerMedia('app.media.ic_ltr', $r('app.media.ic_ltr'));
registerMedia('app.media.ic_moon', $r('app.media.ic_moon'));
registerMedia('app.media.ic_more', $r('app.media.ic_more'));
registerMedia('app.media.ic_more_vert', $r('app.media.ic_more_vert'));
registerMedia('app.media.ic_page_turn_animation', $r('app.media.ic_page_turn_animation'));
registerMedia('app.media.ic_pdf', $r('app.media.ic_pdf'));
registerMedia('app.media.ic_performance', $r('app.media.ic_performance'));
registerMedia('app.media.ic_performance_inactive', $r('app.media.ic_performance_inactive'));
registerMedia('app.media.ic_performance_normal', $r('app.media.ic_performance_normal'));
registerMedia('app.media.ic_performance_selected', $r('app.media.ic_performance_selected'));
registerMedia('app.media.ic_placeholder', $r('app.media.ic_placeholder'));
registerMedia('app.media.ic_public_cancel', $r('app.media.ic_public_cancel'));
registerMedia('app.media.ic_public_correct', $r('app.media.ic_public_correct'));
registerMedia('app.media.ic_public_help', $r('app.media.ic_public_help'));
registerMedia('app.media.ic_public_refresh', $r('app.media.ic_public_refresh'));
registerMedia('app.media.ic_reading_settings', $r('app.media.ic_reading_settings'));
registerMedia('app.media.ic_refresh', $r('app.media.ic_refresh'));
registerMedia('app.media.ic_report', $r('app.media.ic_report'));
registerMedia('app.media.ic_restore', $r('app.media.ic_restore'));
registerMedia('app.media.ic_robot', $r('app.media.ic_robot'));
registerMedia('app.media.ic_rtl', $r('app.media.ic_rtl'));
registerMedia('app.media.ic_scraper', $r('app.media.ic_scraper'));
registerMedia('app.media.ic_search', $r('app.media.ic_search'));
registerMedia('app.media.ic_search_inactive', $r('app.media.ic_search_inactive'));
registerMedia('app.media.ic_search_normal', $r('app.media.ic_search_normal'));
registerMedia('app.media.ic_search_selected', $r('app.media.ic_search_selected'));
registerMedia('app.media.ic_settings', $r('app.media.ic_settings'));
registerMedia('app.media.ic_settings_normal', $r('app.media.ic_settings_normal'));
registerMedia('app.media.ic_settings_selected', $r('app.media.ic_settings_selected'));
registerMedia('app.media.ic_single_page', $r('app.media.ic_single_page'));
registerMedia('app.media.ic_sort', $r('app.media.ic_sort'));
registerMedia('app.media.ic_source_all', $r('app.media.ic_source_all'));
registerMedia('app.media.ic_source_ebook', $r('app.media.ic_source_ebook'));
registerMedia('app.media.ic_source_manga', $r('app.media.ic_source_manga'));
registerMedia('app.media.ic_source_normal', $r('app.media.ic_source_normal'));
registerMedia('app.media.ic_source_novel', $r('app.media.ic_source_novel'));
registerMedia('app.media.ic_source_selected', $r('app.media.ic_source_selected'));
registerMedia('app.media.ic_star', $r('app.media.ic_star'));
registerMedia('app.media.ic_storage', $r('app.media.ic_storage'));
registerMedia('app.media.ic_storage_manage', $r('app.media.ic_storage_manage'));
registerMedia('app.media.ic_sync', $r('app.media.ic_sync'));
registerMedia('app.media.ic_sync_inactive', $r('app.media.ic_sync_inactive'));
registerMedia('app.media.ic_sync_normal', $r('app.media.ic_sync_normal'));
registerMedia('app.media.ic_sync_selected', $r('app.media.ic_sync_selected'));
registerMedia('app.media.ic_system', $r('app.media.ic_system'));
registerMedia('app.media.ic_system_inactive', $r('app.media.ic_system_inactive'));
registerMedia('app.media.ic_system_normal', $r('app.media.ic_system_normal'));
registerMedia('app.media.ic_system_selected', $r('app.media.ic_system_selected'));
registerMedia('app.media.ic_terminal', $r('app.media.ic_terminal'));
registerMedia('app.media.ic_theme', $r('app.media.ic_theme'));
registerMedia('app.media.ic_theme_inactive', $r('app.media.ic_theme_inactive'));
registerMedia('app.media.ic_theme_normal', $r('app.media.ic_theme_normal'));
registerMedia('app.media.ic_theme_selected', $r('app.media.ic_theme_selected'));
registerMedia('app.media.ic_upgrade', $r('app.media.ic_upgrade'));
registerMedia('app.media.ic_user_avatar', $r('app.media.ic_user_avatar'));
registerMedia('app.media.ic_vertical', $r('app.media.ic_vertical'));
registerMedia('app.media.ic_view_grid', $r('app.media.ic_view_grid'));
registerMedia('app.media.ic_view_grid_inactive', $r('app.media.ic_view_grid_inactive'));
registerMedia('app.media.ic_view_grid_normal', $r('app.media.ic_view_grid_normal'));
registerMedia('app.media.ic_view_grid_selected', $r('app.media.ic_view_grid_selected'));
registerMedia('app.media.ic_view_list', $r('app.media.ic_view_list'));
registerMedia('app.media.ic_view_list_inactive', $r('app.media.ic_view_list_inactive'));
registerMedia('app.media.ic_view_list_normal', $r('app.media.ic_view_list_normal'));
registerMedia('app.media.ic_view_list_selected', $r('app.media.ic_view_list_selected'));
registerMedia('app.media.shortcut_icon_continue_read', $r('app.media.shortcut_icon_continue_read'));
registerMedia('app.media.shortcut_icon_continue_read_aloud', $r('app.media.shortcut_icon_continue_read_aloud'));
registerMedia('app.media.shortcut_icon_inspiration', $r('app.media.shortcut_icon_inspiration'));
registerMedia('app.media.shortcut_icon_reading_analytics', $r('app.media.shortcut_icon_reading_analytics'));
registerMedia('app.media.shortcut_icon_search', $r('app.media.shortcut_icon_search'));

// Current app color resources are shared by entry and theme. The complete catalog is
// generated from the resource files; these initial entries cover the public runtime API.
registerColor('app.color.background_primary', $r('app.color.background_primary'));
registerColor('app.color.background_secondary', $r('app.color.background_secondary'));
registerColor('app.color.glass_background_overlay', $r('app.color.glass_background_overlay'));
registerColor('app.color.background_overlay', $r('app.color.background_overlay'));
registerColor('app.color.settings_panel_border', $r('app.color.settings_panel_border'));
registerColor('app.color.text_primary', $r('app.color.text_primary'));
registerColor('app.color.text_secondary', $r('app.color.text_secondary'));
registerColor('app.color.divider', $r('app.color.divider'));
registerColor('app.color.accent_primary', $r('app.color.accent_primary'));
registerColor('app.color.accent_blue', $r('app.color.accent_blue'));
registerColor('app.color.accent_orange', $r('app.color.accent_orange'));
registerColor('app.color.accent_green', $r('app.color.accent_green'));
registerColor('app.color.text_inverse', $r('app.color.text_inverse'));
registerColor('app.color.transparent', $r('app.color.transparent'));
registerString('app.string.activity_motion_reason', $r('app.string.activity_motion_reason'));
registerString('app.string.app_module_desc', $r('app.string.app_module_desc'));
registerString('app.string.background_running_reason', $r('app.string.background_running_reason'));
registerString('app.string.biometric_permission_reason', $r('app.string.biometric_permission_reason'));
registerString('app.string.distributed_data_sync_reason', $r('app.string.distributed_data_sync_reason'));
registerString('app.string.EntryAbility_desc', $r('app.string.EntryAbility_desc'));
registerString('app.string.EntryAbility_label', $r('app.string.EntryAbility_label'));
registerString('app.string.get_documents_reason', $r('app.string.get_documents_reason'));
registerString('app.string.get_download_reason', $r('app.string.get_download_reason'));
registerString('app.string.get_internet_reason', $r('app.string.get_internet_reason'));
registerString('app.string.get_network_info_reason', $r('app.string.get_network_info_reason'));
registerString('app.string.get_notification_reason', $r('app.string.get_notification_reason'));
registerString('app.string.get_vibrate_reason', $r('app.string.get_vibrate_reason'));
registerString('app.string.read_media_reason', $r('app.string.read_media_reason'));
registerString('app.string.shortcut_continue_read', $r('app.string.shortcut_continue_read'));
registerString('app.string.shortcut_continue_read_aloud', $r('app.string.shortcut_continue_read_aloud'));
registerString('app.string.shortcut_inspiration', $r('app.string.shortcut_inspiration'));
registerString('app.string.shortcut_reading_analytics', $r('app.string.shortcut_reading_analytics'));
registerString('app.string.shortcut_search', $r('app.string.shortcut_search'));
registerString('app.string.widget_desc', $r('app.string.widget_desc'));
registerString('app.string.widget_display_name', $r('app.string.widget_display_name'));
registerString('app.string.write_media_reason', $r('app.string.write_media_reason'));

registerSystem('sys.color.ohos_id_color_background', $r('sys.color.ohos_id_color_background'));
registerSystem('sys.color.ohos_id_color_component_normal', $r('sys.color.ohos_id_color_component_normal'));
registerSystem('sys.color.ohos_id_color_warning', $r('sys.color.ohos_id_color_warning'));
registerSystem('sys.color.ohos_id_color_emphasize', $r('sys.color.ohos_id_color_emphasize'));
registerSystem('sys.color.ohos_id_color_secondary', $r('sys.color.ohos_id_color_secondary'));
registerColor('app.color.accent', $r('app.color.accent'));
registerColor('app.color.accent_background', $r('app.color.accent_background'));
registerColor('app.color.accent_secondary', $r('app.color.accent_secondary'));
registerColor('app.color.app_start_window_background', $r('app.color.app_start_window_background'));
registerColor('app.color.background', $r('app.color.background'));
registerColor('app.color.background_card', $r('app.color.background_card'));
registerColor('app.color.background_dark', $r('app.color.background_dark'));
registerColor('app.color.background_darker', $r('app.color.background_darker'));
registerColor('app.color.background_disabled', $r('app.color.background_disabled'));
registerColor('app.color.background_inverse', $r('app.color.background_inverse'));
registerColor('app.color.border_active', $r('app.color.border_active'));
registerColor('app.color.border_dark', $r('app.color.border_dark'));
registerColor('app.color.border_light', $r('app.color.border_light'));
registerColor('app.color.border_subtle', $r('app.color.border_subtle'));
registerColor('app.color.brand', $r('app.color.brand'));
registerColor('app.color.brand_blue', $r('app.color.brand_blue'));
registerColor('app.color.brand_light', $r('app.color.brand_light'));
registerColor('app.color.brand_primary', $r('app.color.brand_primary'));
registerColor('app.color.brand_secondary', $r('app.color.brand_secondary'));
registerColor('app.color.brand_tertiary', $r('app.color.brand_tertiary'));
registerColor('app.color.button_background', $r('app.color.button_background'));
registerColor('app.color.button_danger', $r('app.color.button_danger'));
registerColor('app.color.button_inactive', $r('app.color.button_inactive'));
registerColor('app.color.button_info', $r('app.color.button_info'));
registerColor('app.color.button_primary', $r('app.color.button_primary'));
registerColor('app.color.button_purple', $r('app.color.button_purple'));
registerColor('app.color.button_secondary', $r('app.color.button_secondary'));
registerColor('app.color.button_success', $r('app.color.button_success'));
registerColor('app.color.button_warning', $r('app.color.button_warning'));
registerColor('app.color.color_error', $r('app.color.color_error'));
registerColor('app.color.color_info', $r('app.color.color_info'));
registerColor('app.color.color_neutral', $r('app.color.color_neutral'));
registerColor('app.color.color_success', $r('app.color.color_success'));
registerColor('app.color.color_warning', $r('app.color.color_warning'));
registerColor('app.color.comp_background_tertiary', $r('app.color.comp_background_tertiary'));
registerColor('app.color.console_background_dark', $r('app.color.console_background_dark'));
registerColor('app.color.console_background_darker', $r('app.color.console_background_darker'));
registerColor('app.color.console_background_medium', $r('app.color.console_background_medium'));
registerColor('app.color.console_border_active', $r('app.color.console_border_active'));
registerColor('app.color.console_border_dark', $r('app.color.console_border_dark'));
registerColor('app.color.console_border_light', $r('app.color.console_border_light'));
registerColor('app.color.console_border_subtle', $r('app.color.console_border_subtle'));
registerColor('app.color.console_brand_blue', $r('app.color.console_brand_blue'));
registerColor('app.color.console_button_danger', $r('app.color.console_button_danger'));
registerColor('app.color.console_button_info', $r('app.color.console_button_info'));
registerColor('app.color.console_button_orange', $r('app.color.console_button_orange'));
registerColor('app.color.console_button_primary', $r('app.color.console_button_primary'));
registerColor('app.color.console_button_purple', $r('app.color.console_button_purple'));
registerColor('app.color.console_button_secondary', $r('app.color.console_button_secondary'));
registerColor('app.color.console_button_success', $r('app.color.console_button_success'));
registerColor('app.color.console_button_teal', $r('app.color.console_button_teal'));
registerColor('app.color.console_button_warning', $r('app.color.console_button_warning'));
registerColor('app.color.console_log_debug', $r('app.color.console_log_debug'));
registerColor('app.color.console_panel_dark', $r('app.color.console_panel_dark'));
registerColor('app.color.console_panel_secondary', $r('app.color.console_panel_secondary'));
registerColor('app.color.console_row_even', $r('app.color.console_row_even'));
registerColor('app.color.console_row_odd', $r('app.color.console_row_odd'));
registerColor('app.color.console_shadow_black', $r('app.color.console_shadow_black'));
registerColor('app.color.console_text_dim', $r('app.color.console_text_dim'));
registerColor('app.color.console_text_light', $r('app.color.console_text_light'));
registerColor('app.color.console_text_muted', $r('app.color.console_text_muted'));
registerColor('app.color.console_text_placeholder', $r('app.color.console_text_placeholder'));
registerColor('app.color.console_text_white', $r('app.color.console_text_white'));
registerColor('app.color.console_toggle_off', $r('app.color.console_toggle_off'));
registerColor('app.color.divider_primary', $r('app.color.divider_primary'));
registerColor('app.color.font_secondary', $r('app.color.font_secondary'));
registerColor('app.color.game_apparel_armor', $r('app.color.game_apparel_armor'));
registerColor('app.color.game_apparel_clothing', $r('app.color.game_apparel_clothing'));
registerColor('app.color.game_apparel_headgear', $r('app.color.game_apparel_headgear'));
registerColor('app.color.game_building_bed', $r('app.color.game_building_bed'));
registerColor('app.color.game_building_defense', $r('app.color.game_building_defense'));
registerColor('app.color.game_building_door', $r('app.color.game_building_door'));
registerColor('app.color.game_building_power', $r('app.color.game_building_power'));
registerColor('app.color.game_building_wall', $r('app.color.game_building_wall'));
registerColor('app.color.game_building_workbench', $r('app.color.game_building_workbench'));
registerColor('app.color.game_faction_friendly', $r('app.color.game_faction_friendly'));
registerColor('app.color.game_faction_hostile', $r('app.color.game_faction_hostile'));
registerColor('app.color.game_faction_neutral', $r('app.color.game_faction_neutral'));
registerColor('app.color.game_health_critical', $r('app.color.game_health_critical'));
registerColor('app.color.game_health_good', $r('app.color.game_health_good'));
registerColor('app.color.game_health_injured', $r('app.color.game_health_injured'));
registerColor('app.color.game_mood_happy', $r('app.color.game_mood_happy'));
registerColor('app.color.game_mood_neutral', $r('app.color.game_mood_neutral'));
registerColor('app.color.game_mood_sad', $r('app.color.game_mood_sad'));
registerColor('app.color.game_priority_critical', $r('app.color.game_priority_critical'));
registerColor('app.color.game_priority_high', $r('app.color.game_priority_high'));
registerColor('app.color.game_priority_low', $r('app.color.game_priority_low'));
registerColor('app.color.game_priority_normal', $r('app.color.game_priority_normal'));
registerColor('app.color.game_resource_food', $r('app.color.game_resource_food'));
registerColor('app.color.game_resource_metal', $r('app.color.game_resource_metal'));
registerColor('app.color.game_resource_stone', $r('app.color.game_resource_stone'));
registerColor('app.color.game_resource_wood', $r('app.color.game_resource_wood'));
registerColor('app.color.game_season_autumn', $r('app.color.game_season_autumn'));
registerColor('app.color.game_season_spring', $r('app.color.game_season_spring'));
registerColor('app.color.game_season_summer', $r('app.color.game_season_summer'));
registerColor('app.color.game_season_winter', $r('app.color.game_season_winter'));
registerColor('app.color.game_skill_animals', $r('app.color.game_skill_animals'));
registerColor('app.color.game_skill_artistic', $r('app.color.game_skill_artistic'));
registerColor('app.color.game_skill_construction', $r('app.color.game_skill_construction'));
registerColor('app.color.game_skill_cooking', $r('app.color.game_skill_cooking'));
registerColor('app.color.game_skill_crafting', $r('app.color.game_skill_crafting'));
registerColor('app.color.game_skill_intellectual', $r('app.color.game_skill_intellectual'));
registerColor('app.color.game_skill_medical', $r('app.color.game_skill_medical'));
registerColor('app.color.game_skill_melee', $r('app.color.game_skill_melee'));
registerColor('app.color.game_skill_mining', $r('app.color.game_skill_mining'));
registerColor('app.color.game_skill_plants', $r('app.color.game_skill_plants'));
registerColor('app.color.game_skill_shooting', $r('app.color.game_skill_shooting'));
registerColor('app.color.game_skill_social', $r('app.color.game_skill_social'));
registerColor('app.color.game_temperature_cold', $r('app.color.game_temperature_cold'));
registerColor('app.color.game_temperature_hot', $r('app.color.game_temperature_hot'));
registerColor('app.color.game_ui_accent_blue', $r('app.color.game_ui_accent_blue'));
registerColor('app.color.game_ui_accent_green', $r('app.color.game_ui_accent_green'));
registerColor('app.color.game_ui_accent_orange', $r('app.color.game_ui_accent_orange'));
registerColor('app.color.game_ui_background', $r('app.color.game_ui_background'));
registerColor('app.color.game_ui_border', $r('app.color.game_ui_border'));
registerColor('app.color.game_ui_button_primary', $r('app.color.game_ui_button_primary'));
registerColor('app.color.game_ui_button_secondary', $r('app.color.game_ui_button_secondary'));
registerColor('app.color.game_ui_button_warning', $r('app.color.game_ui_button_warning'));
registerColor('app.color.game_ui_panel', $r('app.color.game_ui_panel'));
registerColor('app.color.game_ui_panel_background', $r('app.color.game_ui_panel_background'));
registerColor('app.color.game_ui_panel_border', $r('app.color.game_ui_panel_border'));
registerColor('app.color.game_ui_text_muted', $r('app.color.game_ui_text_muted'));
registerColor('app.color.game_ui_text_white', $r('app.color.game_ui_text_white'));
registerColor('app.color.game_weapon_explosive', $r('app.color.game_weapon_explosive'));
registerColor('app.color.game_weapon_melee', $r('app.color.game_weapon_melee'));
registerColor('app.color.game_weapon_ranged', $r('app.color.game_weapon_ranged'));
registerColor('app.color.game_weather_clear', $r('app.color.game_weather_clear'));
registerColor('app.color.game_weather_fog', $r('app.color.game_weather_fog'));
registerColor('app.color.game_weather_rain', $r('app.color.game_weather_rain'));
registerColor('app.color.game_weather_snow', $r('app.color.game_weather_snow'));
registerColor('app.color.icon_primary', $r('app.color.icon_primary'));
registerColor('app.color.manga_detail_gradient_end_dark', $r('app.color.manga_detail_gradient_end_dark'));
registerColor('app.color.manga_detail_gradient_end_light', $r('app.color.manga_detail_gradient_end_light'));
registerColor('app.color.manga_detail_gradient_mid_dark', $r('app.color.manga_detail_gradient_mid_dark'));
registerColor('app.color.manga_detail_gradient_mid_light', $r('app.color.manga_detail_gradient_mid_light'));
registerColor('app.color.manga_detail_gradient_start_dark', $r('app.color.manga_detail_gradient_start_dark'));
registerColor('app.color.manga_detail_gradient_start_light', $r('app.color.manga_detail_gradient_start_light'));
registerColor('app.color.ohos_id_color_alert', $r('app.color.ohos_id_color_alert'));
registerColor('app.color.ohos_id_color_background_secondary', $r('app.color.ohos_id_color_background_secondary'));
registerColor('app.color.ohos_id_color_success', $r('app.color.ohos_id_color_success'));
registerColor('app.color.panel_background', $r('app.color.panel_background'));
registerColor('app.color.panel_border', $r('app.color.panel_border'));
registerColor('app.color.panel_dark', $r('app.color.panel_dark'));
registerColor('app.color.reader_divider', $r('app.color.reader_divider'));
registerColor('app.color.reader_overlay_background', $r('app.color.reader_overlay_background'));
registerColor('app.color.reader_progress_track', $r('app.color.reader_progress_track'));
registerColor('app.color.reader_text_primary', $r('app.color.reader_text_primary'));
registerColor('app.color.reader_text_secondary', $r('app.color.reader_text_secondary'));
registerColor('app.color.row_even', $r('app.color.row_even'));
registerColor('app.color.row_odd', $r('app.color.row_odd'));
registerColor('app.color.settings_accent_green', $r('app.color.settings_accent_green'));
registerColor('app.color.settings_background_dark', $r('app.color.settings_background_dark'));
registerColor('app.color.settings_button_inactive', $r('app.color.settings_button_inactive'));
registerColor('app.color.settings_panel_background', $r('app.color.settings_panel_background'));
registerColor('app.color.settings_slider_track', $r('app.color.settings_slider_track'));
registerColor('app.color.settings_text_black', $r('app.color.settings_text_black'));
registerColor('app.color.settings_text_muted', $r('app.color.settings_text_muted'));
registerColor('app.color.settings_text_white', $r('app.color.settings_text_white'));
registerColor('app.color.shadow_black', $r('app.color.shadow_black'));
registerColor('app.color.system_resource_accent_blue', $r('app.color.system_resource_accent_blue'));
registerColor('app.color.system_resource_accent_green', $r('app.color.system_resource_accent_green'));
registerColor('app.color.system_resource_accent_orange', $r('app.color.system_resource_accent_orange'));
registerColor('app.color.system_resource_background', $r('app.color.system_resource_background'));
registerColor('app.color.system_resource_background_overlay', $r('app.color.system_resource_background_overlay'));
registerColor('app.color.system_resource_border_light', $r('app.color.system_resource_border_light'));
registerColor('app.color.system_resource_border_subtle', $r('app.color.system_resource_border_subtle'));
registerColor('app.color.system_resource_button_danger', $r('app.color.system_resource_button_danger'));
registerColor('app.color.system_resource_button_primary', $r('app.color.system_resource_button_primary'));
registerColor('app.color.system_resource_button_secondary', $r('app.color.system_resource_button_secondary'));
registerColor('app.color.system_resource_panel_background', $r('app.color.system_resource_panel_background'));
registerColor('app.color.system_resource_panel_border', $r('app.color.system_resource_panel_border'));
registerColor('app.color.system_resource_tab_active_bg', $r('app.color.system_resource_tab_active_bg'));
registerColor('app.color.system_resource_tab_active_text', $r('app.color.system_resource_tab_active_text'));
registerColor('app.color.system_resource_tab_inactive_bg', $r('app.color.system_resource_tab_inactive_bg'));
registerColor('app.color.system_resource_tab_inactive_text', $r('app.color.system_resource_tab_inactive_text'));
registerColor('app.color.system_resource_text_muted', $r('app.color.system_resource_text_muted'));
registerColor('app.color.system_resource_text_white', $r('app.color.system_resource_text_white'));
registerColor('app.color.test_management_accent_blue', $r('app.color.test_management_accent_blue'));
registerColor('app.color.test_management_accent_blue_dark', $r('app.color.test_management_accent_blue_dark'));
registerColor('app.color.test_management_accent_blue_light', $r('app.color.test_management_accent_blue_light'));
registerColor('app.color.test_management_accent_green', $r('app.color.test_management_accent_green'));
registerColor('app.color.test_management_accent_green_dark', $r('app.color.test_management_accent_green_dark'));
registerColor('app.color.test_management_accent_green_light', $r('app.color.test_management_accent_green_light'));
registerColor('app.color.test_management_accent_orange', $r('app.color.test_management_accent_orange'));
registerColor('app.color.test_management_accent_orange_dark', $r('app.color.test_management_accent_orange_dark'));
registerColor('app.color.test_management_accent_orange_light', $r('app.color.test_management_accent_orange_light'));
registerColor('app.color.test_management_accent_primary_dark', $r('app.color.test_management_accent_primary_dark'));
registerColor('app.color.test_management_accent_primary_dimmed_dark', $r('app.color.test_management_accent_primary_dimmed_dark'));
registerColor('app.color.test_management_accent_primary_dimmed_light', $r('app.color.test_management_accent_primary_dimmed_light'));
registerColor('app.color.test_management_accent_primary_light', $r('app.color.test_management_accent_primary_light'));
registerColor('app.color.test_management_accent_secondary_dark', $r('app.color.test_management_accent_secondary_dark'));
registerColor('app.color.test_management_accent_secondary_light', $r('app.color.test_management_accent_secondary_light'));
registerColor('app.color.test_management_background', $r('app.color.test_management_background'));
registerColor('app.color.test_management_background_dark', $r('app.color.test_management_background_dark'));
registerColor('app.color.test_management_background_dark_dark', $r('app.color.test_management_background_dark_dark'));
registerColor('app.color.test_management_background_dark_light', $r('app.color.test_management_background_dark_light'));
registerColor('app.color.test_management_background_darker_dark', $r('app.color.test_management_background_darker_dark'));
registerColor('app.color.test_management_background_darker_light', $r('app.color.test_management_background_darker_light'));
registerColor('app.color.test_management_background_inverse_dark', $r('app.color.test_management_background_inverse_dark'));
registerColor('app.color.test_management_background_inverse_light', $r('app.color.test_management_background_inverse_light'));
registerColor('app.color.test_management_background_light', $r('app.color.test_management_background_light'));
registerColor('app.color.test_management_background_overlay_dark', $r('app.color.test_management_background_overlay_dark'));
registerColor('app.color.test_management_background_overlay_light', $r('app.color.test_management_background_overlay_light'));
registerColor('app.color.test_management_background_primary_dark', $r('app.color.test_management_background_primary_dark'));
registerColor('app.color.test_management_background_primary_light', $r('app.color.test_management_background_primary_light'));
registerColor('app.color.test_management_background_secondary_dark', $r('app.color.test_management_background_secondary_dark'));
registerColor('app.color.test_management_background_secondary_light', $r('app.color.test_management_background_secondary_light'));
registerColor('app.color.test_management_border_active_dark', $r('app.color.test_management_border_active_dark'));
registerColor('app.color.test_management_border_active_light', $r('app.color.test_management_border_active_light'));
registerColor('app.color.test_management_border_dark_dark', $r('app.color.test_management_border_dark_dark'));
registerColor('app.color.test_management_border_dark_light', $r('app.color.test_management_border_dark_light'));
registerColor('app.color.test_management_border_light_dark', $r('app.color.test_management_border_light_dark'));
registerColor('app.color.test_management_border_light_light', $r('app.color.test_management_border_light_light'));
registerColor('app.color.test_management_border_subtle_dark', $r('app.color.test_management_border_subtle_dark'));
registerColor('app.color.test_management_border_subtle_light', $r('app.color.test_management_border_subtle_light'));
registerColor('app.color.test_management_brand_blue_dark', $r('app.color.test_management_brand_blue_dark'));
registerColor('app.color.test_management_brand_blue_light', $r('app.color.test_management_brand_blue_light'));
registerColor('app.color.test_management_brand_dark', $r('app.color.test_management_brand_dark'));
registerColor('app.color.test_management_brand_light', $r('app.color.test_management_brand_light'));
registerColor('app.color.test_management_brand_secondary_dark', $r('app.color.test_management_brand_secondary_dark'));
registerColor('app.color.test_management_brand_secondary_light', $r('app.color.test_management_brand_secondary_light'));
registerColor('app.color.test_management_brand_tertiary_dark', $r('app.color.test_management_brand_tertiary_dark'));
registerColor('app.color.test_management_brand_tertiary_light', $r('app.color.test_management_brand_tertiary_light'));
registerColor('app.color.test_management_button_background_dark', $r('app.color.test_management_button_background_dark'));
registerColor('app.color.test_management_button_background_light', $r('app.color.test_management_button_background_light'));
registerColor('app.color.test_management_button_danger', $r('app.color.test_management_button_danger'));
registerColor('app.color.test_management_button_inactive', $r('app.color.test_management_button_inactive'));
registerColor('app.color.test_management_button_inactive_dark', $r('app.color.test_management_button_inactive_dark'));
registerColor('app.color.test_management_button_inactive_light', $r('app.color.test_management_button_inactive_light'));
registerColor('app.color.test_management_button_info_dark', $r('app.color.test_management_button_info_dark'));
registerColor('app.color.test_management_button_info_light', $r('app.color.test_management_button_info_light'));
registerColor('app.color.test_management_button_primary', $r('app.color.test_management_button_primary'));
registerColor('app.color.test_management_button_primary_light', $r('app.color.test_management_button_primary_light'));
registerColor('app.color.test_management_button_purple_dark', $r('app.color.test_management_button_purple_dark'));
registerColor('app.color.test_management_button_purple_light', $r('app.color.test_management_button_purple_light'));
registerColor('app.color.test_management_button_secondary', $r('app.color.test_management_button_secondary'));
registerColor('app.color.test_management_button_secondary_light', $r('app.color.test_management_button_secondary_light'));
registerColor('app.color.test_management_button_success_dark', $r('app.color.test_management_button_success_dark'));
registerColor('app.color.test_management_button_success_light', $r('app.color.test_management_button_success_light'));
registerColor('app.color.test_management_button_text_primary_dark', $r('app.color.test_management_button_text_primary_dark'));
registerColor('app.color.test_management_button_text_primary_light', $r('app.color.test_management_button_text_primary_light'));
registerColor('app.color.test_management_button_text_secondary_dark', $r('app.color.test_management_button_text_secondary_dark'));
registerColor('app.color.test_management_button_text_secondary_light', $r('app.color.test_management_button_text_secondary_light'));
registerColor('app.color.test_management_button_warning_dark', $r('app.color.test_management_button_warning_dark'));
registerColor('app.color.test_management_button_warning_light', $r('app.color.test_management_button_warning_light'));
registerColor('app.color.test_management_category_background', $r('app.color.test_management_category_background'));
registerColor('app.color.test_management_color_error_dark', $r('app.color.test_management_color_error_dark'));
registerColor('app.color.test_management_color_error_light', $r('app.color.test_management_color_error_light'));
registerColor('app.color.test_management_color_info_dark', $r('app.color.test_management_color_info_dark'));
registerColor('app.color.test_management_color_info_light', $r('app.color.test_management_color_info_light'));
registerColor('app.color.test_management_color_neutral_dark', $r('app.color.test_management_color_neutral_dark'));
registerColor('app.color.test_management_color_neutral_light', $r('app.color.test_management_color_neutral_light'));
registerColor('app.color.test_management_color_success_dark', $r('app.color.test_management_color_success_dark'));
registerColor('app.color.test_management_color_success_light', $r('app.color.test_management_color_success_light'));
registerColor('app.color.test_management_color_warning_dark', $r('app.color.test_management_color_warning_dark'));
registerColor('app.color.test_management_color_warning_light', $r('app.color.test_management_color_warning_light'));
registerColor('app.color.test_management_comp_background_primary_dark', $r('app.color.test_management_comp_background_primary_dark'));
registerColor('app.color.test_management_comp_background_primary_light', $r('app.color.test_management_comp_background_primary_light'));
registerColor('app.color.test_management_comp_background_secondary_dark', $r('app.color.test_management_comp_background_secondary_dark'));
registerColor('app.color.test_management_comp_background_secondary_light', $r('app.color.test_management_comp_background_secondary_light'));
registerColor('app.color.test_management_comp_background_tertiary_dark', $r('app.color.test_management_comp_background_tertiary_dark'));
registerColor('app.color.test_management_comp_background_tertiary_light', $r('app.color.test_management_comp_background_tertiary_light'));
registerColor('app.color.test_management_divider_dark', $r('app.color.test_management_divider_dark'));
registerColor('app.color.test_management_divider_light', $r('app.color.test_management_divider_light'));
registerColor('app.color.test_management_font_secondary_dark', $r('app.color.test_management_font_secondary_dark'));
registerColor('app.color.test_management_font_secondary_light', $r('app.color.test_management_font_secondary_light'));
registerColor('app.color.test_management_icon_primary_dark', $r('app.color.test_management_icon_primary_dark'));
registerColor('app.color.test_management_icon_primary_light', $r('app.color.test_management_icon_primary_light'));
registerColor('app.color.test_management_panel_background', $r('app.color.test_management_panel_background'));
registerColor('app.color.test_management_panel_background_dark', $r('app.color.test_management_panel_background_dark'));
registerColor('app.color.test_management_panel_background_light', $r('app.color.test_management_panel_background_light'));
registerColor('app.color.test_management_panel_border', $r('app.color.test_management_panel_border'));
registerColor('app.color.test_management_panel_border_dark', $r('app.color.test_management_panel_border_dark'));
registerColor('app.color.test_management_panel_border_light', $r('app.color.test_management_panel_border_light'));
registerColor('app.color.test_management_panel_dark_dark', $r('app.color.test_management_panel_dark_dark'));
registerColor('app.color.test_management_panel_dark_light', $r('app.color.test_management_panel_dark_light'));
registerColor('app.color.test_management_row_even_dark', $r('app.color.test_management_row_even_dark'));
registerColor('app.color.test_management_row_even_light', $r('app.color.test_management_row_even_light'));
registerColor('app.color.test_management_row_odd_dark', $r('app.color.test_management_row_odd_dark'));
registerColor('app.color.test_management_row_odd_light', $r('app.color.test_management_row_odd_light'));
registerColor('app.color.test_management_shadow_black_dark', $r('app.color.test_management_shadow_black_dark'));
registerColor('app.color.test_management_shadow_black_light', $r('app.color.test_management_shadow_black_light'));
registerColor('app.color.test_management_text_black', $r('app.color.test_management_text_black'));
registerColor('app.color.test_management_text_black_dark', $r('app.color.test_management_text_black_dark'));
registerColor('app.color.test_management_text_black_light', $r('app.color.test_management_text_black_light'));
registerColor('app.color.test_management_text_dim', $r('app.color.test_management_text_dim'));
registerColor('app.color.test_management_text_inverse_dark', $r('app.color.test_management_text_inverse_dark'));
registerColor('app.color.test_management_text_inverse_light', $r('app.color.test_management_text_inverse_light'));
registerColor('app.color.test_management_text_light_dark', $r('app.color.test_management_text_light_dark'));
registerColor('app.color.test_management_text_light_light', $r('app.color.test_management_text_light_light'));
registerColor('app.color.test_management_text_muted', $r('app.color.test_management_text_muted'));
registerColor('app.color.test_management_text_muted_dark', $r('app.color.test_management_text_muted_dark'));
registerColor('app.color.test_management_text_muted_light', $r('app.color.test_management_text_muted_light'));
registerColor('app.color.test_management_text_placeholder_dark', $r('app.color.test_management_text_placeholder_dark'));
registerColor('app.color.test_management_text_placeholder_light', $r('app.color.test_management_text_placeholder_light'));
registerColor('app.color.test_management_text_primary_dark', $r('app.color.test_management_text_primary_dark'));
registerColor('app.color.test_management_text_primary_light', $r('app.color.test_management_text_primary_light'));
registerColor('app.color.test_management_text_secondary_dark', $r('app.color.test_management_text_secondary_dark'));
registerColor('app.color.test_management_text_secondary_light', $r('app.color.test_management_text_secondary_light'));
registerColor('app.color.test_management_text_white', $r('app.color.test_management_text_white'));
registerColor('app.color.test_management_text_white_dark', $r('app.color.test_management_text_white_dark'));
registerColor('app.color.test_management_text_white_light', $r('app.color.test_management_text_white_light'));
registerColor('app.color.text_black', $r('app.color.text_black'));
registerColor('app.color.text_dim', $r('app.color.text_dim'));
registerColor('app.color.text_disabled', $r('app.color.text_disabled'));
registerColor('app.color.text_light', $r('app.color.text_light'));
registerColor('app.color.text_muted', $r('app.color.text_muted'));
registerColor('app.color.text_on_accent', $r('app.color.text_on_accent'));
registerColor('app.color.text_placeholder', $r('app.color.text_placeholder'));
registerColor('app.color.text_white', $r('app.color.text_white'));
registerColor('app.color.transport', $r('app.color.transport'));

// Preserve the historical substitutions made by the old resource map.
registerAlias('app.media.logo', 'app.media.foreground');
registerAlias('app.media.ic_back', 'app.media.ic_arrow_back');
registerAlias('app.media.ic_arrow_back', 'app.media.ic_arrow_right');
registerAlias('app.media.ic_novel', 'app.media.ic_source_novel');
registerAlias('app.media.ic_more_vert', 'app.media.ic_more');
registerAlias('app.media.ic_chevron_left', 'app.media.ic_arrow_right');
registerAlias('app.media.ic_settings', 'app.media.ic_settings_normal');
registerAlias('app.media.ic_chevron_right', 'app.media.ic_arrow_right');
registerAlias('app.color.comp_background_primary', 'sys.color.ohos_id_color_background');
registerAlias('app.color.comp_border_primary', 'sys.color.ohos_id_color_component_normal');
registerAlias('app.color.success_text', 'app.color.ohos_id_color_success');
registerAlias('app.color.error_text', 'sys.color.ohos_id_color_warning');
registerAlias('app.color.error_border', 'sys.color.ohos_id_color_warning');
registerAlias('app.color.test_management_button_primary_dark', 'sys.color.ohos_id_color_emphasize');
registerAlias('app.color.test_management_button_secondary_dark', 'sys.color.ohos_id_color_secondary');

// New names are logical aliases during the migration. New physical files must use
// the prefixed name directly; these aliases avoid duplicating existing binaries.
registerAlias('app.media.ui_logo', 'app.media.foreground');
registerAlias('app.media.ui_default_manga_cover', 'app.media.mangabook');
registerAlias('app.media.ui_default_ebook_cover', 'app.media.ebook');
registerAlias('app.media.ui_placeholder', 'app.media.ic_image');
registerAlias('app.color.ui_background_primary', 'app.color.background_primary');
registerAlias('app.color.ui_background_secondary', 'app.color.background_secondary');
registerAlias('app.color.ui_text_primary', 'app.color.text_primary');
registerAlias('app.color.ui_text_secondary', 'app.color.text_secondary');

function warnUnknownResource(key: string): void {
  if (!warnedKeys.has(key)) {
    warnedKeys.add(key);
    console.warn(`[ResourceCatalog] 未找到资源: ${key}`);
  }
}

export function normalizeResourcePath(path: string): string {
  if (!path || path.startsWith('http://') || path.startsWith('https://') ||
    path.startsWith('file://') || path.startsWith('/')) {
    return path;
  }
  const alias = legacyAliases.get(path);
  return alias === undefined ? path : alias;
}

export function resolveMedia(path: string): Resource {
  const key = normalizeResourcePath(path);
  const resource = mediaResources.get(key);
  if (resource === undefined && key.startsWith('app.media.')) {
    warnUnknownResource(path);
  }
  return resource === undefined ? fallbackMediaResource : resource;
}

export function resolveColor(path: string): Resource {
  const key = normalizeResourcePath(path);
  const resource = colorResources.get(key);
  if (resource !== undefined) {
    return resource;
  }
  const systemResource = systemResources.get(key);
  if (systemResource === undefined && (key.startsWith('app.color.') || key.startsWith('sys.color.'))) {
    warnUnknownResource(path);
  }
  return systemResource === undefined ? fallbackColorResource : systemResource;
}

export function resolveString(path: string): Resource | undefined {
  const key = normalizeResourcePath(path);
  const resource = stringResources.get(key);
  if (resource === undefined && key.startsWith('app.string.')) {
    warnUnknownResource(path);
  }
  return resource;
}

export function resolveResource(path: string): Resource | undefined {
  if (path.startsWith('app.media.')) {
    return resolveMedia(path);
  }
  if (path.startsWith('app.color.') || path.startsWith('sys.color.')) {
    return resolveColor(path);
  }
  if (path.startsWith('app.string.')) {
    return resolveString(path);
  }
  return undefined;
}

/** Compatibility name for callers migrated from the old ResourceMap. */
export function findResourceInMap(path: string): Resource | undefined {
  return resolveResource(path);
}

export function getColorResourceKeys(): string[] {
  const keys: string[] = [];
  colorResources.forEach((_resource: Resource, key: string): void => {
    keys.push(key);
  });
  keys.sort();
  return keys;
}
