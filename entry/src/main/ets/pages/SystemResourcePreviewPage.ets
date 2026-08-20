/**
 * 系统资源预览页面
 * 展示HarmonyOS系统图标和颜色资源
 * 支持按需加载和分类浏览
 */

import { HdsNavDestination } from '@kit.UIDesignKit';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { ThemeAwareState, ThemeAwareHelper } from 'manxia_theme/src/main/ets/Framework/Components/ThemeAware';
import { FontAwareHelper, FontAwareState } from 'manxia_theme/src/main/ets/Framework/Components/FontAware';
import { ThemeManager, ThemeType } from 'manxia_theme/src/main/ets/Framework/Managers/ThemeManager';
import { SYSTEM_SYMBOL_GROUPS, SYSTEM_SYMBOL_TOTAL_COUNT, SystemSymbolResourceGroup } from '../Framework/Resources/SystemSymbolCatalog';
import { pasteboard } from '@kit.BasicServicesKit';
import { promptAction } from '@kit.ArkUI';
import { SettingsImmersiveTitleBar } from './settings/SettingsImmersiveTitleBar';
import { SettingsPageTitleBarManager } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPageTitleBarManager';
import { GlobalBackgroundLayerMode } from 'manxia_theme/src/main/ets/Framework/Components/GlobalBackgroundLayer';
import { SharedPageBackgroundLayer } from '../Framework/Components/SharedPageBackgroundLayer';

const TAG = 'SystemResourcePreviewPage';
const GROUP_BATCH_SIZE: number = 8;
const GRID_ITEM_BATCH_SIZE: number = 120;
const SEARCH_RESULT_BATCH_SIZE: number = 160;

/**
 * 资源分类
 */
enum ResourceCategory {
  SYMBOL = 'symbol',
  MEDIA = 'media',
  COLOR = 'color'
}

/**
 * 图标分组
 */

// 系统媒体图标完整列表（来源: SDK 23 sysResource.js，共 167 个公开图标，按功能分组）
const MEDIA_GROUPS: SystemSymbolResourceGroup[] = [
  {
    name: '基础图标',
    items: [
      'ohos_app_icon',
      'ohos_ic_public_ok',
      'ohos_ic_public_cast_stream',
      'ohos_ic_public_cast_mirror',
      'ohos_icon_mask_svg',
      'ohos_ic_public_ok_filled',
      'ic_due_control_picture',
      'ic_regional_generation',
    ]
  },
  {
    name: '导航方向',
    items: [
      'ohos_ic_back',
      'ohos_ic_public_arrow_left',
      'ohos_ic_public_arrow_right',
      'ohos_ic_public_arrow_up',
      'ohos_ic_public_arrow_down',
      'ohos_ic_compnent_titlebar_back',
      'ohos_ic_compnent_titlebar_back_filled',
      'chevron_right_titlebar',
    ]
  },
  {
    name: '编辑操作',
    items: [
      'ohos_ic_public_cut',
      'ohos_ic_public_copy',
      'ohos_ic_public_paste',
      'ohos_ic_public_select_all',
      'ohos_ic_public_share',
      'ohos_ic_public_add',
      'ohos_ic_public_minus',
      'ohos_ic_public_add_norm_filled',
      'ohos_ic_public_remove_filled',
      'ohos_ic_public_edit',
      'ohos_ic_public_remove',
    ]
  },
  {
    name: '搜索保存',
    items: [
      'ohos_ic_public_translate_c2e',
      'ohos_ic_public_search_filled',
      'ohos_save_button_filled',
      'ohos_save_button_line',
      'save_button_picture',
    ]
  },
  {
    name: '关闭取消',
    items: [
      'ohos_ic_bottomsheet_close',
      'ohos_ic_public_cancel',
      'ohos_ic_public_fail',
      'ohos_ic_public_close',
      'ohos_ic_public_cancel_filled',
      'ohos_ic_public_input_cancel',
    ]
  },
  {
    name: '通讯信息',
    items: [
      'ohos_ic_public_clock',
      'ohos_ic_public_email',
      'ohos_ic_public_express',
      'ohos_ic_public_flight',
      'ohos_ic_public_location',
      'ohos_ic_public_phone',
      'ohos_ic_public_text',
      'ohos_ic_public_web',
      'ic_public_worldclock_filled',
    ]
  },
  {
    name: '设备图标',
    items: [
      'ohos_ic_public_device_matebook',
      'ohos_ic_public_device_pad',
      'ohos_ic_public_device_smartscreen',
      'ohos_ic_public_device_watch',
      'ohos_ic_public_device_phone',
      'ohos_ic_public_device_bluetooth_filled',
      'ohos_ic_public_device_earphone_filled',
      'ohos_ic_public_device_earpiece_filled',
      'ohos_ic_public_device_speaker_filled',
      'ohos_ic_public_device_sound_filled',
      'ohos_ic_public_device_soundx_filled',
      'ohos_ic_public_device_smartscreen_filled',
    ]
  },
  {
    name: '相册扫描',
    items: [
      'ohos_ic_eco_hop',
      'ohos_ic_public_more',
      'ohos_ic_public_camera',
      'ohos_ic_public_albums',
      'ohos_ic_public_scan',
      'ic_public_camera_beauty',
    ]
  },
  {
    name: '媒体控制',
    items: [
      'ohos_ic_public_hang_up',
      'ohos_ic_public_pause',
      'ohos_ic_public_play_last',
      'ohos_ic_public_play_next',
      'ohos_ic_public_play',
      'ohos_ic_public_restore',
      'ohos_ic_public_sound_off',
      'ohos_ic_public_sound',
      'ohos_ic_public_video_off',
      'ohos_ic_public_video',
      'ohos_ic_public_voice_off',
      'ohos_ic_public_voice',
      'safe_volume_notification_icon',
      'loud_volume_notification_icon',
    ]
  },
  {
    name: '标题栏',
    items: [
      'ohos_ic_public_drawer_close',
      'ohos_ic_public_drawer_close_filled',
      'ohos_ic_public_drawer_open',
      'ohos_ic_public_drawer_open_filled',
      'checkmark_titlebar',
    ]
  },
  {
    name: '文件类型',
    items: [
      'ohos_ic_normal_white_grid_zip',
      'ohos_ic_normal_white_grid_xml',
      'ohos_ic_normal_white_grid_xls',
      'ohos_ic_normal_white_grid_wma',
      'ohos_ic_normal_white_grid_wav',
      'ohos_ic_normal_white_grid_video',
      'ohos_ic_normal_white_grid_txt',
      'ohos_ic_normal_white_grid_pdf',
      'ohos_ic_normal_white_grid_mp3',
      'ohos_ic_normal_white_grid_image',
      'ohos_ic_normal_white_grid_html',
      'ohos_ic_normal_white_grid_folder',
      'ohos_ic_normal_white_grid_flac',
      'ohos_ic_normal_white_grid_doc',
      'ohos_ic_normal_white_grid_compress',
      'ohos_ic_normal_white_grid_calendar',
      'ohos_ic_normal_white_grid_audio',
    ]
  },
  {
    name: '用户认证',
    items: [
      'ohos_user_auth_icon_face',
      'ohos_user_auth_icon_fingerprint',
      'app_lock_picture',
      'ic_time_limit_picture',
    ]
  },
  {
    name: '克隆应用',
    items: [
      'clone_app_badge_1',
      'clone_app_badge_2',
      'clone_app_badge_3',
      'clone_app_badge_4',
      'clone_app_badge_5',
    ]
  },
  {
    name: 'AI功能',
    items: [
      'ic_public_ai_write',
      'image_generation_create',
      'image_generation_style',
      'more_agent',
      'node_graph',
    ]
  },
  {
    name: '窗口管理',
    items: [
      'ohos_ic_window_menu_screen_t',
      'ohos_ic_window_menu_screen_b',
      'ohos_ic_window_menu_waterfall',
      'ohos_ic_window_menu_moveto_t',
      'ohos_ic_window_menu_moveto_b',
      'ohos_ic_window_menu_back',
      'compatible_mode_18_9_landscape',
      'compatible_mode_2_3_landscape',
      'compatible_mode_1_1_landscape',
      'compatible_mode_default_landscape',
      'compatible_mode_split_landscape',
    ]
  },
  {
    name: '画笔工具',
    items: [
      'ic_ballpointpen_tip_crop_circle',
      'ic_eraser_grid',
      'ic_stroke_heavy',
      'ic_stroke_medium',
      'ic_stroke_thin',
      'ballpointpen_result',
      'eraser_big',
      'eraser_medium',
      'eraser_small',
      'ic_eraser_big',
      'ic_eraser_medium',
      'ic_eraser_small',
    ]
  },
  {
    name: '图像编辑',
    items: [
      'blank_illustrate',
      'maintain_layout',
      'outline_glow',
      'pin_dot',
      'rotate',
      'clarity_1k',
      'clarity_2k',
      'clarity_4k',
      'proportion_1_1',
      'proportion_1_1_fill',
      'proportion_2_3',
      'proportion_2_3_fill',
      'proportion_3_2',
      'proportion_3_2_fill',
      'proportion_3_4',
      'proportion_3_4_fill',
      'proportion_4_3',
      'proportion_4_3_fill',
      'proportion_9_16',
      'proportion_9_16_fill',
      'proportion_16_9',
      'proportion_16_9_fill',
      'generate_landscape_white_border',
      'generate_portrait_white_border',
      'proportion_original_fill',
      'proportion_9_21',
      'proportion_9_21_fill',
      'proportion_21_9',
      'proportion_21_9_fill',
    ]
  },
];

const SYMBOL_GROUPS: SystemSymbolResourceGroup[] = SYSTEM_SYMBOL_GROUPS;

// 系统颜色完整列表（来源: SDK 23 sysResource.js，共 1020 个公开颜色）
const SYSTEM_COLORS: string[] = [
  'ohos_id_color_foreground',
  'ohos_id_color_foreground_dark',
  'ohos_id_color_foreground_transparent',
  'ohos_id_color_foreground_contrary',
  'ohos_id_color_foreground_contrary_dark',
  'ohos_id_color_foreground_contrary_transparent',
  'ohos_id_color_foreground_contrary_disable',
  'ohos_id_color_foreground_contrary_disable_dark',
  'ohos_id_color_foreground_contrary_disable_transparent',
  'ohos_id_color_background',
  'ohos_id_color_background_dark',
  'ohos_id_color_background_transparent',
  'ohos_id_color_sub_background',
  'ohos_id_color_sub_background_dark',
  'ohos_id_color_sub_background_transparent',
  'ohos_id_color_emphasize',
  'ohos_id_color_emphasize_dark',
  'ohos_id_color_emphasize_transparent',
  'ohos_id_color_emphasize_contrary',
  'ohos_id_color_emphasize_contrary_dark',
  'ohos_id_color_emphasize_contrary_transparent',
  'ohos_id_color_warning',
  'ohos_id_color_warning_dark',
  'ohos_id_color_warning_transparent',
  'ohos_id_color_alert',
  'ohos_id_color_alert_dark',
  'ohos_id_color_alert_transparent',
  'ohos_id_color_handup',
  'ohos_id_color_handup_dark',
  'ohos_id_color_handup_transparent',
  'ohos_id_color_connected',
  'ohos_id_color_connected_dark',
  'ohos_id_color_connected_transparent',
  'ohos_id_color_component_activated',
  'ohos_id_color_component_activated_dark',
  'ohos_id_color_component_activated_transparent',
  'ohos_id_color_component_normal',
  'ohos_id_color_component_normal_dark',
  'ohos_id_color_component_normal_transparent',
  'ohos_id_color_list_separator',
  'ohos_id_color_list_separator_dark',
  'ohos_id_color_list_separator_transparent',
  'ohos_id_color_subheading_separator',
  'ohos_id_color_subheading_separator_dark',
  'ohos_id_color_subheading_separator_transparent',
  'ohos_id_color_click_effect',
  'ohos_id_color_click_effect_dark',
  'ohos_id_color_click_effect_transparent',
  'ohos_id_color_hover',
  'ohos_id_color_hover_dark',
  'ohos_id_color_hover_transparent',
  'ohos_id_color_focused_content_primary',
  'ohos_id_color_focused_content_primary_dark',
  'ohos_id_color_focused_content_primary_transparent',
  'ohos_id_color_focused_content_second',
  'ohos_id_color_focused_content_second_dark',
  'ohos_id_color_focused_content_second_transparent',
  'ohos_id_color_focused_content_tertiary',
  'ohos_id_color_focused_content_tertiary_dark',
  'ohos_id_color_focused_content_tertiary_transparent',
  'ohos_id_color_focused_outline',
  'ohos_id_color_focused_outline_dark',
  'ohos_id_color_focused_outline_transparent',
  'ohos_id_color_focused_bg',
  'ohos_id_color_focused_bg_dark',
  'ohos_id_color_focused_bg_transparent',
  'ohos_id_color_primary',
  'ohos_id_color_primary_dark',
  'ohos_id_color_primary_transparent',
  'ohos_id_color_primary_contrary',
  'ohos_id_color_primary_contrary_dark',
  'ohos_id_color_primary_contrary_transparent',
  'ohos_id_color_secondary',
  'ohos_id_color_secondary_dark',
  'ohos_id_color_secondary_transparent',
  'ohos_id_color_tertiary',
  'ohos_id_color_tertiary_dark',
  'ohos_id_color_tertiary_transparent',
  'ohos_id_color_fourth',
  'ohos_id_color_fourth_dark',
  'ohos_id_color_fourth_transparent',
  'ohos_id_color_activated',
  'ohos_id_color_activated_dark',
  'ohos_id_color_activated_transparent',
  'ohos_id_color_activated_start',
  'ohos_id_color_activated_start_dark',
  'ohos_id_color_activated_start_transparent',
  'ohos_id_color_activated_end',
  'ohos_id_color_activated_end_dark',
  'ohos_id_color_activated_end_transparent',
  'ohos_id_color_text_primary',
  'ohos_id_color_text_primary_dark',
  'ohos_id_color_text_primary_transparent',
  'ohos_id_color_text_primary_contrary',
  'ohos_id_color_text_primary_contrary_dark',
  'ohos_id_color_text_primary_contrary_transparent',
  'ohos_id_color_text_secondary',
  'ohos_id_color_text_secondary_dark',
  'ohos_id_color_text_secondary_transparent',
  'ohos_id_color_text_secondary_contrary',
  'ohos_id_color_text_secondary_contrary_dark',
  'ohos_id_color_text_secondary_contrary_transparent',
  'ohos_id_color_text_tertiary',
  'ohos_id_color_text_tertiary_dark',
  'ohos_id_color_text_tertiary_transparent',
  'ohos_id_color_text_tertiary_contrary',
  'ohos_id_color_text_tertiary_contrary_dark',
  'ohos_id_color_text_tertiary_contrary_transparent',
  'ohos_dialog_text_alert',
  'ohos_dialog_text_alert_dark',
  'ohos_dialog_text_alert_transparent',
  'ohos_id_color_text_primary_activated',
  'ohos_id_color_text_primary_activated_dark',
  'ohos_id_color_text_primary_activated_transparent',
  'ohos_id_color_text_secondary_activated',
  'ohos_id_color_text_secondary_activated_dark',
  'ohos_id_color_text_secondary_activated_transparent',
  'ohos_id_color_text_search_url',
  'ohos_id_color_text_search_url_dark',
  'ohos_id_color_text_search_url_transparent',
  'ohos_id_color_text_hint',
  'ohos_id_color_text_hint_dark',
  'ohos_id_color_text_hint_transparent',
  'ohos_id_color_text_hint_contrary',
  'ohos_id_color_text_hint_contrary_dark',
  'ohos_id_color_text_hint_contrary_transparent',
  'ohos_id_color_text_hyperlink',
  'ohos_id_color_text_hyperlink_dark',
  'ohos_id_color_text_hyperlink_transparent',
  'ohos_id_color_text_hyperlink_contrary',
  'ohos_id_color_text_hyperlink_contrary_dark',
  'ohos_id_color_text_hyperlink_contrary_transparent',
  'ohos_id_color_text_highlight_bg',
  'ohos_id_color_text_highlight_bg_dark',
  'ohos_id_color_text_highlight_bg_transparent',
  'ohos_id_color_text_highlight_bg_contrary',
  'ohos_id_color_text_highlight_bg_contrary_dark',
  'ohos_id_color_text_highlight_bg_contrary_transparent',
  'ohos_id_color_palette1',
  'ohos_id_color_palette1_dark',
  'ohos_id_color_palette1_transparent',
  'ohos_id_color_palette2',
  'ohos_id_color_palette2_dark',
  'ohos_id_color_palette2_transparent',
  'ohos_id_color_palette3',
  'ohos_id_color_palette3_dark',
  'ohos_id_color_palette3_transparent',
  'ohos_id_color_palette4',
  'ohos_id_color_palette4_dark',
  'ohos_id_color_palette4_transparent',
  'ohos_id_color_palette5',
  'ohos_id_color_palette5_dark',
  'ohos_id_color_palette5_transparent',
  'ohos_id_color_palette6',
  'ohos_id_color_palette6_dark',
  'ohos_id_color_palette6_transparent',
  'ohos_id_color_palette7',
  'ohos_id_color_palette7_dark',
  'ohos_id_color_palette7_transparent',
  'ohos_id_color_palette8',
  'ohos_id_color_palette8_dark',
  'ohos_id_color_palette8_transparent',
  'ohos_id_color_palette9',
  'ohos_id_color_palette9_dark',
  'ohos_id_color_palette9_transparent',
  'ohos_id_color_palette10',
  'ohos_id_color_palette10_dark',
  'ohos_id_color_palette10_transparent',
  'ohos_id_color_palette11',
  'ohos_id_color_palette11_dark',
  'ohos_id_color_palette11_transparent',
  'ohos_id_color_palette_aux1',
  'ohos_id_color_palette_aux1_dark',
  'ohos_id_color_palette_aux1_transparent',
  'ohos_id_color_palette_aux2',
  'ohos_id_color_palette_aux2_dark',
  'ohos_id_color_palette_aux2_transparent',
  'ohos_id_color_palette_aux3',
  'ohos_id_color_palette_aux3_dark',
  'ohos_id_color_palette_aux3_transparent',
  'ohos_id_color_palette_aux4',
  'ohos_id_color_palette_aux4_dark',
  'ohos_id_color_palette_aux4_transparent',
  'ohos_id_color_palette_aux5',
  'ohos_id_color_palette_aux5_dark',
  'ohos_id_color_palette_aux5_transparent',
  'ohos_id_color_palette_aux6',
  'ohos_id_color_palette_aux6_dark',
  'ohos_id_color_palette_aux6_transparent',
  'ohos_id_color_palette_aux7',
  'ohos_id_color_palette_aux7_dark',
  'ohos_id_color_palette_aux7_transparent',
  'ohos_id_color_palette_aux8',
  'ohos_id_color_palette_aux8_dark',
  'ohos_id_color_palette_aux8_transparent',
  'ohos_id_color_palette_aux9',
  'ohos_id_color_palette_aux9_dark',
  'ohos_id_color_palette_aux9_transparent',
  'ohos_id_color_palette_aux10',
  'ohos_id_color_palette_aux10_dark',
  'ohos_id_color_palette_aux10_transparent',
  'ohos_id_color_palette_aux11',
  'ohos_id_color_palette_aux11_dark',
  'ohos_id_color_palette_aux11_transparent',
  'ohos_id_color_special1',
  'ohos_id_color_special1_dark',
  'ohos_id_color_special1_transparent',
  'ohos_id_color_special2',
  'ohos_id_color_special2_dark',
  'ohos_id_color_special2_transparent',
  'ohos_id_color_special3',
  'ohos_id_color_special3_dark',
  'ohos_id_color_special3_transparent',
  'ohos_id_color_special4',
  'ohos_id_color_special4_dark',
  'ohos_id_color_special4_transparent',
  'ohos_id_color_special5',
  'ohos_id_color_special5_dark',
  'ohos_id_color_special5_transparent',
  'ohos_id_color_special6',
  'ohos_id_color_special6_dark',
  'ohos_id_color_special6_transparent',
  'ohos_id_color_special7',
  'ohos_id_color_special7_dark',
  'ohos_id_color_special7_transparent',
  'ohos_id_color_special8',
  'ohos_id_color_special8_dark',
  'ohos_id_color_special8_transparent',
  'ohos_id_color_special9',
  'ohos_id_color_special9_dark',
  'ohos_id_color_special9_transparent',
  'ohos_id_color_special10',
  'ohos_id_color_special10_dark',
  'ohos_id_color_special10_transparent',
  'ohos_id_color_special11',
  'ohos_id_color_special11_dark',
  'ohos_id_color_special11_transparent',
  'ohos_id_color_mask_thin',
  'ohos_id_color_mask_thin_dark',
  'ohos_id_color_mask_thin_transparent',
  'ohos_id_color_mask_light',
  'ohos_id_color_mask_light_dark',
  'ohos_id_color_mask_light_transparent',
  'ohos_id_color_mask_regular',
  'ohos_id_color_mask_regular_dark',
  'ohos_id_color_mask_regular_transparent',
  'ohos_id_color_mask_thick',
  'ohos_id_color_mask_thick_dark',
  'ohos_id_color_mask_thick_transparent',
  'ohos_id_color_statusbar_bg',
  'ohos_id_color_statusbar_bg_dark',
  'ohos_id_color_statusbar_bg_transparent',
  'ohos_id_color_navigationbar_bg',
  'ohos_id_color_navigationbar_bg_dark',
  'ohos_id_color_navigationbar_bg_transparent',
  'ohos_id_color_titlebar_icon',
  'ohos_id_color_titlebar_icon_dark',
  'ohos_id_color_titlebar_icon_transparent',
  'ohos_id_color_titlebar_icon_pressed',
  'ohos_id_color_titlebar_icon_pressed_dark',
  'ohos_id_color_titlebar_icon_pressed_transparent',
  'ohos_id_color_titlebar_text',
  'ohos_id_color_titlebar_text_dark',
  'ohos_id_color_titlebar_text_transparent',
  'ohos_id_color_titlebar_text_off',
  'ohos_id_color_titlebar_text_off_dark',
  'ohos_id_color_titlebar_text_off_transparent',
  'ohos_id_color_titlebar_subtitle_text',
  'ohos_id_color_titlebar_subtitle_text_dark',
  'ohos_id_color_titlebar_subtitle_text_transparent',
  'ohos_id_color_titlebar_bg',
  'ohos_id_color_titlebar_bg_dark',
  'ohos_id_color_titlebar_bg_transparent',
  'ohos_id_color_titlebar_sub_bg',
  'ohos_id_color_titlebar_sub_bg_dark',
  'ohos_id_color_titlebar_sub_bg_transparent',
  'ohos_id_color_bottom_tab_icon',
  'ohos_id_color_bottom_tab_icon_dark',
  'ohos_id_color_bottom_tab_icon_transparent',
  'ohos_id_color_bottom_tab_icon_off',
  'ohos_id_color_bottom_tab_icon_off_dark',
  'ohos_id_color_bottom_tab_icon_off_transparent',
  'ohos_id_color_bottom_tab_icon_auxcolor01',
  'ohos_id_color_bottom_tab_icon_auxcolor01_dark',
  'ohos_id_color_bottom_tab_icon_auxcolor01_transparent',
  'ohos_id_color_bottom_tab_icon_auxcolor_off01',
  'ohos_id_color_bottom_tab_icon_auxcolor_off01_dark',
  'ohos_id_color_bottom_tab_icon_auxcolor_off01_transparent',
  'ohos_id_color_bottom_tab_icon_auxcolor02',
  'ohos_id_color_bottom_tab_icon_auxcolor02_dark',
  'ohos_id_color_bottom_tab_icon_auxcolor02_transparent',
  'ohos_id_color_bottom_tab_icon_auxcolor_off02',
  'ohos_id_color_bottom_tab_icon_auxcolor_off02_dark',
  'ohos_id_color_bottom_tab_icon_auxcolor_off02_transparent',
  'ohos_id_color_bottom_tab_text_on',
  'ohos_id_color_bottom_tab_text_on_dark',
  'ohos_id_color_bottom_tab_text_on_transparent',
  'ohos_id_color_bottom_tab_text_off',
  'ohos_id_color_bottom_tab_text_off_dark',
  'ohos_id_color_bottom_tab_text_off_transparent',
  'ohos_id_color_bottom_tab_bg',
  'ohos_id_color_bottom_tab_bg_dark',
  'ohos_id_color_bottom_tab_bg_transparent',
  'ohos_id_color_bottom_tab_bg_blur',
  'ohos_id_color_bottom_tab_bg_blur_dark',
  'ohos_id_color_bottom_tab_bg_blur_transparent',
  'ohos_id_color_bottom_tab_sub_bg',
  'ohos_id_color_bottom_tab_sub_bg_dark',
  'ohos_id_color_bottom_tab_sub_bg_transparent',
  'ohos_id_color_bottom_tab_sub_bg_blur',
  'ohos_id_color_bottom_tab_sub_bg_blur_dark',
  'ohos_id_color_bottom_tab_sub_bg_blur_transparent',
  'ohos_id_color_subtab_text_on',
  'ohos_id_color_subtab_text_on_dark',
  'ohos_id_color_subtab_text_on_transparent',
  'ohos_id_color_subtab_text_off',
  'ohos_id_color_subtab_text_off_dark',
  'ohos_id_color_subtab_text_off_transparent',
  'ohos_id_color_subtab_line_on',
  'ohos_id_color_subtab_line_on_dark',
  'ohos_id_color_subtab_line_on_transparent',
  'ohos_id_color_subtab_bg',
  'ohos_id_color_subtab_bg_dark',
  'ohos_id_color_subtab_bg_transparent',
  'ohos_id_color_toolbar_icon',
  'ohos_id_color_toolbar_icon_dark',
  'ohos_id_color_toolbar_icon_transparent',
  'ohos_id_color_toolbar_icon_actived',
  'ohos_id_color_toolbar_icon_actived_dark',
  'ohos_id_color_toolbar_icon_actived_transparent',
  'ohos_id_color_toolbar_text',
  'ohos_id_color_toolbar_text_dark',
  'ohos_id_color_toolbar_text_transparent',
  'ohos_id_color_toolbar_text_actived',
  'ohos_id_color_toolbar_text_actived_dark',
  'ohos_id_color_toolbar_text_actived_transparent',
  'ohos_id_color_toolbar_bg',
  'ohos_id_color_toolbar_bg_dark',
  'ohos_id_color_toolbar_bg_transparent',
  'ohos_id_color_toolbar_sub_bg',
  'ohos_id_color_toolbar_sub_bg_dark',
  'ohos_id_color_toolbar_sub_bg_transparent',
  'ohos_id_color_text_field_bg',
  'ohos_id_color_text_field_bg_dark',
  'ohos_id_color_text_field_bg_transparent',
  'ohos_id_color_text_field_sub_bg',
  'ohos_id_color_text_field_sub_bg_dark',
  'ohos_id_color_text_field_sub_bg_transparent',
  'ohos_id_color_progress',
  'ohos_id_color_progress_dark',
  'ohos_id_color_progress_transparent',
  'ohos_id_color_spinner_icon',
  'ohos_id_color_spinner_icon_dark',
  'ohos_id_color_spinner_icon_transparent',
  'ohos_id_color_badge',
  'ohos_id_color_badge_dark',
  'ohos_id_color_badge_transparent',
  'ohos_id_color_badge_red',
  'ohos_id_color_badge_red_dark',
  'ohos_id_color_badge_red_transparent',
  'ohos_id_color_dialog_bg',
  'ohos_id_color_dialog_bg_dark',
  'ohos_id_color_dialog_bg_transparent',
  'ohos_id_color_button_normal',
  'ohos_id_color_button_normal_dark',
  'ohos_id_color_button_normal_transparent',
  'ohos_id_color_switch_outline_off',
  'ohos_id_color_switch_outline_off_dark',
  'ohos_id_color_switch_outline_off_transparent',
  'ohos_id_color_switch_bg_off',
  'ohos_id_color_switch_bg_off_dark',
  'ohos_id_color_switch_bg_off_transparent',
  'ohos_id_color_floating_button_icon',
  'ohos_id_color_floating_button_icon_dark',
  'ohos_id_color_floating_button_icon_transparent',
  'ohos_id_color_floating_button_icon_start',
  'ohos_id_color_floating_button_icon_start_dark',
  'ohos_id_color_floating_button_icon_start_transparent',
  'ohos_id_color_floating_button_icon_end',
  'ohos_id_color_floating_button_icon_end_dark',
  'ohos_id_color_floating_button_icon_end_transparent',
  'ohos_id_color_floating_button_bg_normal',
  'ohos_id_color_floating_button_bg_normal_dark',
  'ohos_id_color_floating_button_bg_normal_transparent',
  'ohos_id_color_floating_button_start',
  'ohos_id_color_floating_button_start_dark',
  'ohos_id_color_floating_button_start_transparent',
  'ohos_id_color_floating_button_center',
  'ohos_id_color_floating_button_center_dark',
  'ohos_id_color_floating_button_center_transparent',
  'ohos_id_color_floating_button_end',
  'ohos_id_color_floating_button_end_dark',
  'ohos_id_color_floating_button_end_transparent',
  'ohos_id_color_floating_button_shadow_start',
  'ohos_id_color_floating_button_shadow_start_dark',
  'ohos_id_color_floating_button_shadow_start_transparent',
  'ohos_id_color_floating_button_shadow_end',
  'ohos_id_color_floating_button_shadow_end_dark',
  'ohos_id_color_floating_button_shadow_end_transparent',
  'ohos_id_color_floating_button_bg_pressed',
  'ohos_id_color_floating_button_bg_pressed_dark',
  'ohos_id_color_floating_button_bg_pressed_transparent',
  'ohos_id_color_instant_tip_bg',
  'ohos_id_color_instant_tip_bg_dark',
  'ohos_id_color_instant_tip_bg_transparent',
  'ohos_id_color_panel_bg',
  'ohos_id_color_panel_bg_dark',
  'ohos_id_color_panel_bg_transparent',
  'ohos_id_color_card_bg',
  'ohos_id_color_card_bg_dark',
  'ohos_id_color_card_bg_transparent',
  'ohos_id_color_list_card_bg',
  'ohos_id_color_list_card_bg_dark',
  'ohos_id_color_list_card_bg_transparent',
  'ohos_id_color_tooltip_foreground',
  'ohos_id_color_tooltip_foreground_dark',
  'ohos_id_color_tooltip_foreground_transparent',
  'ohos_id_color_tooltip_background',
  'ohos_id_color_tooltip_background_dark',
  'ohos_id_color_tooltip_background_transparent',
  'ohos_toggle_bg',
  'ohos_toggle_bg_dark',
  'ohos_toggle_bg_transparent',
  'ohos_id_color_help_tip_bg',
  'ohos_id_color_help_tip_bg_dark',
  'ohos_id_color_help_tip_bg_transparent',
  'ohos_fa_foreground',
  'ohos_fa_foreground_dark',
  'ohos_fa_foreground_contrary',
  'ohos_fa_foreground_contrary_dark',
  'ohos_fa_emphasize',
  'ohos_fa_emphasize_dark',
  'ohos_fa_emphasize_outline',
  'ohos_fa_emphasize_outline_dark',
  'ohos_fa_alert',
  'ohos_fa_alert_dark',
  'ohos_fa_warning',
  'ohos_fa_warning_dark',
  'ohos_fa_handup',
  'ohos_fa_handup_dark',
  'ohos_fa_connected',
  'ohos_fa_connected_dark',
  'ohos_fa_component_normal',
  'ohos_fa_component_normal_dark',
  'ohos_fa_click_effect',
  'ohos_fa_click_effect_dark',
  'ohos_fa_list_separator',
  'ohos_fa_list_separator_dark',
  'ohos_fa_list_card_bg_blur',
  'ohos_fa_list_card_bg_blur_dark',
  'ohos_fa_list_card_bg',
  'ohos_fa_list_card_bg_dark',
  'ohos_fa_background_blur',
  'ohos_fa_background_blur_dark',
  'ohos_fa_background',
  'ohos_fa_background_dark',
  'ohos_fa_sub_background',
  'ohos_fa_sub_background_dark',
  'ohos_fa_text_primary',
  'ohos_fa_text_primary_dark',
  'ohos_fa_text_secondary',
  'ohos_fa_text_secondary_dark',
  'ohos_fa_text_tertiary',
  'ohos_fa_text_tertiary_dark',
  'ohos_fa_text_fourth',
  'ohos_fa_text_fourth_dark',
  'ohos_fa_text_contrary',
  'ohos_fa_text_contrary_dark',
  'ohos_fa_text_activated',
  'ohos_fa_text_activated_dark',
  'ohos_fa_icon_primary',
  'ohos_fa_icon_primary_dark',
  'ohos_fa_icon_secondary',
  'ohos_fa_icon_secondary_dark',
  'ohos_fa_icon_tertiary',
  'ohos_fa_icon_tertiary_dark',
  'ohos_fa_icon_fourth',
  'ohos_fa_icon_fourth_dark',
  'ohos_fa_icon_contrary',
  'ohos_fa_icon_contrary_dark',
  'ohos_fa_activated',
  'ohos_fa_activated_dark',
  'ohos_fa_palette1',
  'ohos_fa_palette1_dark',
  'ohos_fa_palette2',
  'ohos_fa_palette2_dark',
  'ohos_fa_palette3',
  'ohos_fa_palette3_dark',
  'ohos_fa_palette4',
  'ohos_fa_palette4_dark',
  'ohos_fa_palette5',
  'ohos_fa_palette5_dark',
  'ohos_fa_palette6',
  'ohos_fa_palette6_dark',
  'ohos_fa_palette7',
  'ohos_fa_palette7_dark',
  'ohos_fa_palette8',
  'ohos_fa_palette8_dark',
  'ohos_fa_palette9',
  'ohos_fa_palette9_dark',
  'ohos_fa_palette10',
  'ohos_fa_palette10_dark',
  'ohos_fa_palette11',
  'ohos_fa_palette11_dark',
  'ohos_fa_palette12',
  'ohos_fa_palette12_dark',
  'ohos_id_color_datapanel_color1_start',
  'ohos_id_color_datapanel_color2_start',
  'ohos_id_color_datapanel_color3_start',
  'ohos_id_color_datapanel_color4_start',
  'ohos_id_color_datapanel_color5_start',
  'ohos_id_color_datapanel_color6_start',
  'ohos_id_color_datapanel_color7_start',
  'ohos_id_color_datapanel_color8_start',
  'ohos_id_color_datapanel_color9_start',
  'ohos_id_color_datapanel_color1_end',
  'ohos_id_color_datapanel_color2_end',
  'ohos_id_color_datapanel_color3_end',
  'ohos_id_color_datapanel_color4_end',
  'ohos_id_color_datapanel_color5_end',
  'ohos_id_color_datapanel_color6_end',
  'ohos_id_color_datapanel_color7_end',
  'ohos_id_color_datapanel_color8_end',
  'ohos_id_color_datapanel_color9_end',
  'ohos_id_color_datapanel_bg',
  'ohos_id_color_ring_progress_end',
  'ohos_id_color_ring_progress_begin',
  'ohos_id_color_calendar_week',
  'ohos_id_color_calendar_day',
  'ohos_id_color_calendar_lunar',
  'ohos_id_color_calendar_weekend_day',
  'ohos_id_color_calendar_weekend_lunar',
  'ohos_id_color_calendar_today_day_focus',
  'ohos_id_color_calendar_today_lunar_focus',
  'ohos_id_color_calendar_today_day_unfocus',
  'ohos_id_color_calendar_today_lunar_unfocus',
  'ohos_id_color_calendar_work_mark',
  'ohos_id_color_calendar_off_mark',
  'ohos_id_color_calendar_non_current_month_work_mark',
  'ohos_id_color_calendar_non_current_month_off_mark',
  'ohos_id_color_calendar_non_current_month_day',
  'ohos_id_color_calendar_non_current_month_lunar',
  'ohos_id_color_calendar_focus_area_background',
  'ohos_id_color_calendar_blur_area_background',
  'ohos_id_video_control_bar_text_color',
  'ohos_id_video_control_bar_background_color',
  'ohos_id_color_button_divider',
  'ohos_id_color_dialog_default_bg',
  'ohos_id_navigation_group_color',
  'ohos_id_button_bg_focus_color',
  'ohos_id_button_text_focus_color',
  'ohos_id_button_progress_focus_color',
  'ohos_id_focus_color',
  'ohos_id_video_control_bar_error_text_color',
  'ohos_id_counter_title_font_color',
  'ohos_id_counter_title_background_color',
  'ohos_id_section_unfocus_color',
  'picker_focus_option_text_color',
  'ohos_id_picker_title_text_color',
  'ohos_id_picker_button_text_color',
  'ohos_id_picker_focus_color',
  'picker_select_option_back_color',
  'ohos_id_picker_focus_option_back_color',
  'ohos_id_picker_dialog_mask_color',
  'ohos_id_picker_select_divider_color',
  'ohos_id_picker_press_color',
  'ohos_id_checkbox_shadow_color',
  'ohos_id_switch_shadow_color',
  'ohos_id_radio_shadow_color',
  'ohos_id_color_help_tip_light_bg',
  'ohos_id_navigation_bar_button_normal_color',
  'ohos_id_marquee_text_color',
  'ohos_id_popup_mask_color',
  'ohos_id_popup_text_color',
  'ohos_id_scroll_bar_background_color',
  'ohos_id_text_overlay_menu_border_color',
  'ohos_id_dialog_mask_color_start',
  'ohos_id_dialog_mask_color_end',
  'ohos_id_select_color_text_primary',
  'ohos_id_select_selected_color',
  'ohos_id_select_font_color',
  'ohos_id_select_option_disable_color',
  'ohos_id_select_option_focused_disable_color',
  'ohos_id_select_option_focused_disable_text_color',
  'ohos_id_list_background_color',
  'ohos_id_divider_color',
  'ohos_id_calendar_touch_color',
  'ohos_id_card_bg_color',
  'ohos_id_icon_color_active',
  'ohos_id_icon_color_active_secondary',
  'ohos_id_text_color_active',
  'ohos_id_container_color_active',
  'ohos_id_container_color',
  'ohos_id_background_secondary',
  'ohos_id_popup_outer_border_color',
  'ohos_id_popup_inner_border_color',
  'ohos_id_toolbar_item_focus_color',
  'ohos_id_toolbar_item_hover_color',
  'ohos_id_toolbar_control_normal',
  'ohos_id_menu_blur_effect_color',
  'ohos_id_menu_outer_border_color',
  'ohos_id_menu_inner_border_color',
  'ohos_id_blur_style_thin_color',
  'ohos_id_blur_style_thin_color_dark',
  'ohos_id_blur_style_regular_color',
  'ohos_id_blur_style_regular_color_dark',
  'ohos_id_blur_style_thick_color',
  'ohos_id_blur_style_thick_color_dark',
  'ohos_id_blur_style_background_thin_color',
  'ohos_id_blur_style_background_thin_color_dark',
  'ohos_id_blur_style_background_regular_color',
  'ohos_id_blur_style_background_regular_color_dark',
  'ohos_id_blur_style_background_thick_color',
  'ohos_id_blur_style_background_thick_color_dark',
  'ohos_id_blur_style_background_ultra_thick_color',
  'ohos_id_blur_style_background_ultra_thick_color_dark',
  'ohos_id_blur_style_component_ultra_thin_color',
  'ohos_id_blur_style_component_ultra_thin_color_dark',
  'ohos_id_blur_style_component_thin_color',
  'ohos_id_blur_style_component_thin_color_dark',
  'ohos_id_blur_style_component_regular_color',
  'ohos_id_blur_style_component_regular_color_dark',
  'ohos_id_blur_style_component_thick_color',
  'ohos_id_blur_style_component_thick_color_dark',
  'ohos_id_blur_style_component_ultra_thick_color',
  'ohos_id_blur_style_component_ultra_thick_color_dark',
  'ohos_id_shadow_default_xs',
  'ohos_id_shadow_default_sm',
  'ohos_id_shadow_default_md',
  'ohos_id_shadow_default_lg',
  'ohos_id_shadow_floating_sm',
  'ohos_id_shadow_floating_md',
  'ohos_id_shadow_default_xs_dark',
  'ohos_id_shadow_default_sm_dark',
  'ohos_id_shadow_default_md_dark',
  'ohos_id_shadow_default_lg_dark',
  'ohos_id_shadow_floating_sm_dark',
  'ohos_id_shadow_floating_md_dark',
  'ohos_id_color_navigation_background_blur',
  'multi_color_aux_01',
  'multi_color_aux_02',
  'multi_color_aux_03',
  'multi_color_aux_04',
  'multi_color_aux_05',
  'brand',
  'brand_font',
  'brand_font_contrary',
  'warning',
  'alert',
  'confirm',
  'font_primary',
  'font_secondary',
  'font_tertiary',
  'font_fourth',
  'font_emphasize',
  'font_on_primary',
  'font_on_secondary',
  'font_on_tertiary',
  'font_on_fourth',
  'icon_primary',
  'icon_secondary',
  'icon_tertiary',
  'icon_fourth',
  'icon_emphasize',
  'icon_sub_emphasize',
  'mask_primary',
  'mask_secondary',
  'mask_tertiary',
  'mask_fourth',
  'mask_fifth',
  'mask_sixth',
  'comp_foreground_primary',
  'comp_background_primary',
  'comp_background_primary_contrary',
  'comp_background_gray',
  'comp_background_secondary',
  'comp_background_tertiary',
  'comp_background_emphasize',
  'multi_color_aux_06',
  'comp_emphasize_secondary',
  'comp_emphasize_tertiary',
  'comp_divider',
  'comp_common_contrary',
  'comp_background_focus',
  'comp_focused_primary',
  'comp_focused_secondary',
  'comp_focused_tertiary',
  'interactive_hover',
  'interactive_pressed',
  'interactive_focus',
  'interactive_active',
  'interactive_select',
  'interactive_click',
  'black',
  'white',
  'gray_01',
  'gray_02',
  'gray_03',
  'gray_04',
  'multi_color_01',
  'multi_color_02',
  'multi_color_03',
  'multi_color_04',
  'multi_color_05',
  'multi_color_06',
  'multi_color_07',
  'multi_color_08',
  'multi_color_09',
  'multi_color_10',
  'multi_color_11',
  'icon_on_primary',
  'icon_on_secondary',
  'icon_on_tertiary',
  'icon_on_fourth',
  'background_primary',
  'background_secondary',
  'background_tertiary',
  'background_fourth',
  'background_emphasize',
  'neutral',
  'multi_color_aux_07',
  'multi_color_aux_08',
  'multi_color_aux_09',
  'multi_color_aux_10',
  'multi_color_aux_11',
  'font',
  'font_on',
  'icon',
  'icon_on',
  'alert_divider_color',
  'titlebar_subheader_color',
  'titlebar_icon_color',
  'titlebar_icon_background_color',
  'titlebar_icon_background_hover_color',
  'titlebar_icon_background_pressed_color',
  'titlebar_icon_background_focus_outline_color',
  'titlebar_title_tertiary_color',
  'comp_background_list_card',
  'button_border_color',
  'ohos_id_shadow_focus_button',
  'button_small_border_color',
  'text_button_container_focus_color',
  'alertdialog_container_border_color',
  'text_input_border_color',
  'checkbox_container_focus_color',
  'checkbox_focus_border_color',
  'checkbox_container_focus_color_unselected',
  'radio_container_focus_color',
  'alertdialog_container_color_blur',
  'swiper_indicator_selected_focus_color',
  'switch_container_focus_color',
  'status_button_color_border_checked',
  'status_button_color_border_unchecked',
  'status_button_container_focus_unchecked',
  'status_button_container_focus_checked',
  'status_button_text_color_focus',
  'menu_border_color',
  'menu_item_focused_bg_color',
  'menu_item_focused_text_color',
  'container_modal_background',
  'container_modal_unfocus_background',
  'ohos_id_normalbtn_unfocus_bg',
  'ohos_id_closebtn_unfocus_bg',
  'ohos_id_normalbtn_bg',
  'ohos_id_normalbtn_hover_bg',
  'ohos_id_closebtn_color_warning',
  'ohos_id_closebtn_focus_bg',
  'ohos_id_closebtn_press_bg',
  'ohos_id_normalbtn_press_bg',
  'swiper_indicator_unselected_focus_color',
  'swiper_indicator_container_focus_color',
  'radio_ring_focus_color_unchecked',
  'radio_container_focus_color_unchecked',
  'normal_button_container_focus_color',
  'ohos_id_swiper_dot_active_color',
  'ohos_id_swiper_dot_color',
  'ohos_id_swiper_mask_color_start',
  'ohos_id_swiper_mask_color_end',
  'ohos_id_swiper_container_color',
  'dataPanel_color_subheading_separator',
  'color_sidebarcontainer_sub_bg',
  'comp_background_warning_secondary',
  'dialog_outer_border_color',
  'dialog_inner_border_color',
  'toast_outer_border_color',
  'toast_inner_border_color',
  'point_color_checked',
  'popup_background_color_api_twelve',
  'indexer_bar_color',
  'indexer_text_color_active',
  'indexer_text_color',
  'indexer_popup_bg_color',
  'indexer_pressed_bg_color',
  'indexer_selected_bg_color',
  'glass_material_outline_primary',
  'glass_material_outline_secondary',
  'glass_material_mask_primary',
  'glass_material_mask_secondary',
  'button_background_color_transparent',
  'window_outline_color',
  'window_border_color',
  'comp_outline_color',
  'comp_border_color',
  'ohos_id_dialog_mask_color_end_dark',
  'navigation_drag_bar_item_default',
  'navigation_drag_bar_active',
  'navigation_divider_light_blue_active',
  'navigation_divider_dark_blue_active',
  'ohos_id_blur_style_component_ultra_thick_window_color',
  'ohos_id_blur_style_component_ultra_thick_window_color_dark',
  'container_modal_button_normal_baseboard',
  'container_modal_button_hover_baseboard',
  'ring_progress_fg_color_begin',
  'scrollbar_color_foreground',
  'app_theme_focus_color',
  'alertdialog_divider_color',
  'progress_track_color',
  'progress_track_selected_color',
  'fg_progress_color',
  'loading_progress_focused_color',
  'progress_hover_blend_color',
  'capsule_progress_inprogress_border_color',
  'progress_border_color',
  'capsule_progress_bg_inprogress_color',
  'capsule_progress_bg_color',
  'capsule_progress_bg_focused_color',
  'capsule_progress_text_focused_color',
  'progress_text_color',
  'capsule_progress_select_focused_color',
  'capsule_progress_select_color',
  'progress_click_effect',
  'ring_progress_bg_color',
  'ring_progress_fg_color_end',
  'popup_container_default_color',
  'popup_border_color',
  'popup_text_primary_color',
  'rating_icon_active_color',
  'rating_icon_inactive_color',
  'rating_container_hover_color',
  'rating_container_press_color',
  'rating_container_focus_color',
  'rating_unlit_star_focus_color',
  'menu_back_blur_color',
  'search_icon_color',
  'search_symbol_icon_color',
  'search_text_focus_color',
  'search_container_focus_color',
  'search_icon_focus_color',
  'search_hover_color',
  'search_press_color',
  'textfield_bg_color',
  'search_text_color',
  'textfield_cursor_color',
  'search_placeholder_color',
  'search_border_color',
  'search_placeholder_focus_color',
  'textpicker_selected_text_color',
  'textpicker_text_color',
  'textpicker_disappear_text_color',
  'picker_selector_item_hover_color',
  'picker_selector_item_press_color',
  'picker_selector_item_text_focus_color',
  'picker_select_divider_color',
  'picker_selector_item_border_color',
  'picker_selector_item_border_focus_color',
  'picker_selector_item_container_focus_color',
  'picker_selector_item_container_normal_color',
  'switch_unchecked_point_color',
  'slider_color_foreground',
  'slider_outset_and_none_track_color',
  'slider_color_emphasize',
  'slider_color_foreground_contrary',
  'slider_hover_color',
  'slider_color_click_effect',
  'slider_block_shadow_color',
  'toast_border_color',
  'toast_color_text_primary_contrary',
  'toast_container_color',
  'toast_font_primary',
  'switch_container_unselected_focus_color',
  'switch_point_unselected_focus_color',
  'switch_container_unchecked_color',
  'sheet_title_text_font_color',
  'sheet_panel_background_color',
  'focus_animation_color',
  'tab_subtab_select_text_color',
  'tab_subtab_text_color',
  'tab_subtab_container_hover_color',
  'tab_subtab_container_press_color',
  'tab_subtab_active_indicator_color',
  'tab_subtab_text_focus_color',
  'tab_bar_focused_color',
  'checkbox_focus_color',
  'radio_focus_color',
  'switch_focus_color',
  'qrcode_focused_color',
  'swiper_indicator_color_focused',
  'picker_focus_color',
  'segment_button_checked_text_color',
  'segment_button_checked_foreground_color',
  'segment_button_unselected_text_color',
  'segment_button_backboard_color',
  'segment_button_hover_color',
  'segment_button_press_color',
  'segment_button_focus_backboard_primary',
  'segment_button_focus_text_primary',
  'toolBarDialog_container_focus_color',
  'chip_border_color',
  'chip_activated_border_color',
  'chip_container_activated_color',
  'chip_activated_fontcolor',
  'chip_hover_color',
  'chip_focus_color',
  'chip_container_activated_focus_color',
  'chip_focus_text',
  'chip_focus_icon',
  'chip_background_color',
  'chip_font_color',
  'chip_press_color',
  'chip_usually_icon_color',
  'chip_active_icon_color',
  'chip_icon_focus_fill',
  'chip_icon_activated_focus_color',
  'chip_activated_focus_font_color',
  'composeListItem_container_normal_color',
  'composeListItem_stroke_normal_color',
  'composeListItem_left_text_focus_color',
  'composeListItem_right_icon_normal_color',
  'composeListItem_container_focus_color',
  'composeListItem_right_text_focus_color',
  'composeListItem_right_icon_focus_color',
  'composeListItem_left_secondary_text_focus_color',
  'composeListItem_badge_color',
  'composeListItem_icon_normal_color',
  'password_border_normal_color',
  'password_container_focus_color',
  'password_icon_focus_color',
  'password_font_focus_color',
  'select_option_container_focus_color',
  'select_border_normal_color',
  'select_normal_icon_color',
  'select_normal_font_color',
  'select_option_hovered_bg_color',
  'select_option_clicked_bg_color',
  'select_menu_container_normal_color',
  'menu_text_normal_color',
  'select_normal_bg_color',
  'select_option_border_selected_color',
  'select_selected_color',
  'text_color_selected',
  'select_font_color',
  'select_bg_color_selected',
  'select_text_focus_color',
  'select_focus_text_color',
  'select_focus_icon_color',
  'select_container_focus_color',
  'select_option_focus_font_color',
  'menu_normal_border_color',
  'searchkeyboard_primary_control_color',
  'searchkeyboard_focus_bg',
  'toast_default_bg_color',
  'picker_background_color',
  'comp_background_primary_contrary_secondary',
  'segment_button_v2_tab_button_background',
  'segment_button_v2_tab_selected_item_background',
  'segment_button_v2_capsule_button_background',
  'segment_button_v2_capsule_selected_item_background',
  'segment_button_v2_multi_capsule_button_background',
  'segment_button_v2_multi_capsule_selected_item_background',
  'arc_scroll_bar_background_color',
  'ohos_id_color_text_highlight_bg_arc',
  'indicator_border_color',
  'tips_outer_border_color',
  'tips_outer_border_color_dark',
  'tips_inner_border_color',
  'font_normal',
  'popup_text_color_normal',
  'sheet_mask_color',
  'popup_secondary_button_font_color_sys',
  'popup_secondary_button_font_color',
  'popup_primary_button_background_color_sys',
  'popup_primary_button_background_color',
  'popup_secondary_button_background_color_sys',
  'popup_secondary_button_background_color',
  'popup_primary_button_font_color_sys',
  'popup_primary_button_font_color',
  'scroll_bar_foreground_hover_blend_color',
  'scroll_bar_foreground_pressed_blend_color',
  'font_emphasize_contrary',
  'container_modal_special_background',
  'picker_selected_background_color',
  'ai_intelligent_gradient_color1',
  'ai_intelligent_gradient_color2',
  'ai_intelligent_gradient_color3',
  'ai_intelligent_gradient_color4',
  'comp_background_float',
  'radio_color_hover',
  'radio_color_foreground_contrary',
  'radio_bg_color_checked',
  'radio_bg_color_unchecked',
  'radio_click_effect_color',
  'checkbox_fg_color_checked',
  'checkbox_bg_color_checked',
  'checkbox_bg_border_color_unchecked',
  'checkbox_hover_border_color',
  'checkbox_click_effect_color',
  'segment_button_border_color',
  'titlebar_icon_border_color',
  'title_primary_color',
  'navigation_focus_blend_bg_color',
  'node_graph_hover_border_color',
  'node_graph_toolbar_background_color',
  'node_graph_selected_icon_color',
  'node_graph_generator_selected_icon_color',
  'node_graph_generator_select_font_color',
  'node_graph_generator_button_border_color',
  'node_graph_body_background_color',
  'node_graph_node_background_color',
  'node_graph_generator_button_background_color',
  'node_graph_selected_font_color',
];

@Component
export struct SystemResourcePreviewPage {
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private componentId: string = 'SystemResourcePreviewPage';
  pathStack: NavPathStack = new NavPathStack();

  @State private selectedCategory: ResourceCategory = ResourceCategory.SYMBOL;
  @State private selectedGroupIndex: number = 0;
  @State private searchText: string = '';
  @State private visibleGroupCount: number = GROUP_BATCH_SIZE;
  @State private visibleGridItemCount: number = GRID_ITEM_BATCH_SIZE;
  @State private visibleSearchResultCount: number = SEARCH_RESULT_BATCH_SIZE;
  @State private isSearching: boolean = false;
  @State private searchResults: string[] = [];
  
  aboutToAppear(): void {
    logger.info(TAG, '系统资源预览页面初始化');
    this.resetSegmentedLoading();
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (newTheme: ThemeType) => {
      logger.info(TAG, `主题切换到: ${newTheme}`);
    });
    FontAwareHelper.initializeFontAware(this.componentId, this.fontState, (newState: FontAwareState) => {
      this.fontState = newState;
    });
  }

  aboutToDisappear(): void {
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    FontAwareHelper.cleanupFontAware(this.componentId);
  }
  
  private resetSegmentedLoading(): void {
    this.visibleGroupCount = GROUP_BATCH_SIZE;
    this.visibleGridItemCount = GRID_ITEM_BATCH_SIZE;
    this.visibleSearchResultCount = SEARCH_RESULT_BATCH_SIZE;
  }

  private resetGridItemLoading(): void {
    this.visibleGridItemCount = GRID_ITEM_BATCH_SIZE;
  }

  private getVisibleItems<T>(items: T[], limit: number): T[] {
    if (limit >= items.length) {
      return items;
    }

    const visibleItems: T[] = [];
    const maxCount = Math.min(items.length, limit);
    for (let index = 0; index < maxCount; index++) {
      visibleItems.push(items[index]);
    }
    return visibleItems;
  }

  private getVisibleGroupCount(): number {
    return Math.min(this.getCurrentGroups().length, this.visibleGroupCount);
  }

  private hasMoreGroups(): boolean {
    return this.getVisibleGroupCount() < this.getCurrentGroups().length;
  }

  /**
   * 加载更多分组（分段）
   */
  private loadMoreGroups(): void {
    const groups = this.getCurrentGroups();
    if (this.visibleGroupCount < groups.length) {
      this.visibleGroupCount = Math.min(groups.length, this.visibleGroupCount + GROUP_BATCH_SIZE);
    }
  }

  private getVisibleGroups(): SystemSymbolResourceGroup[] {
    return this.getVisibleItems<SystemSymbolResourceGroup>(this.getCurrentGroups(), this.visibleGroupCount);
  }
  
  /**
   * 获取当前分类的分组列表
   */
  private getCurrentGroups(): SystemSymbolResourceGroup[] {
    if (this.selectedCategory === ResourceCategory.SYMBOL) {
      return SYMBOL_GROUPS;
    } else if (this.selectedCategory === ResourceCategory.MEDIA) {
      return MEDIA_GROUPS;
    }
    return [];
  }
  
  /**
   * 获取当前Symbol分组的项目
   */
  private getSymbolItems(): string[] {
    if (this.selectedGroupIndex < SYMBOL_GROUPS.length) {
      return SYMBOL_GROUPS[this.selectedGroupIndex].items;
    }
    return [];
  }
  
  /**
   * 获取当前Media分组的项目
   */
  private getMediaItems(): string[] {
    if (this.selectedGroupIndex < MEDIA_GROUPS.length) {
      return MEDIA_GROUPS[this.selectedGroupIndex].items;
    }
    return [];
  }

  private getCurrentGridItems(): string[] {
    if (this.selectedCategory === ResourceCategory.SYMBOL) {
      return this.getSymbolItems();
    }
    if (this.selectedCategory === ResourceCategory.MEDIA) {
      return this.getMediaItems();
    }
    return [];
  }

  private getVisibleCurrentGridItems(): string[] {
    return this.getVisibleItems<string>(this.getCurrentGridItems(), this.visibleGridItemCount);
  }

  private getCurrentGridItemCount(): number {
    return this.getCurrentGridItems().length;
  }

  private getVisibleCurrentGridItemCount(): number {
    return Math.min(this.getCurrentGridItemCount(), this.visibleGridItemCount);
  }

  private hasMoreCurrentGridItems(): boolean {
    return this.getVisibleCurrentGridItemCount() < this.getCurrentGridItemCount();
  }

  private loadMoreCurrentGridItems(): void {
    const totalCount = this.getCurrentGridItemCount();
    if (this.visibleGridItemCount < totalCount) {
      this.visibleGridItemCount = Math.min(totalCount, this.visibleGridItemCount + GRID_ITEM_BATCH_SIZE);
    }
  }

  private getVisibleSearchResults(): string[] {
    return this.getVisibleItems<string>(this.searchResults, this.visibleSearchResultCount);
  }

  private getVisibleSearchResultCount(): number {
    return Math.min(this.searchResults.length, this.visibleSearchResultCount);
  }

  private hasMoreSearchResults(): boolean {
    return this.getVisibleSearchResultCount() < this.searchResults.length;
  }

  private loadMoreSearchResults(): void {
    if (this.visibleSearchResultCount < this.searchResults.length) {
      this.visibleSearchResultCount = Math.min(
        this.searchResults.length,
        this.visibleSearchResultCount + SEARCH_RESULT_BATCH_SIZE
      );
    }
  }

  private getMediaResourceCount(): number {
    let total = 0;
    for (const group of MEDIA_GROUPS) {
      total += group.items.length;
    }
    return total;
  }

  private getCategoryLabel(category: ResourceCategory): string {
    if (category === ResourceCategory.SYMBOL) {
      return `Symbol ${SYSTEM_SYMBOL_TOTAL_COUNT}`;
    }
    if (category === ResourceCategory.MEDIA) {
      return `Media ${this.getMediaResourceCount()}`;
    }
    return `Color ${SYSTEM_COLORS.length}`;
  }


  private getSelectedGroupSummaryText(): string {
    const groups = this.getCurrentGroups();
    if (this.selectedGroupIndex >= 0 && this.selectedGroupIndex < groups.length) {
      const currentGroup = groups[this.selectedGroupIndex];
      return currentGroup.name + ' | ' + currentGroup.items.length.toString() + ' items';
    }
    return '';
  }
  
  /**
   * 执行搜索
   */
  private performSearch(): void {
    if (!this.searchText || this.searchText.trim() === '') {
      this.isSearching = false;
      this.searchResults = [];
      this.visibleSearchResultCount = SEARCH_RESULT_BATCH_SIZE;
      return;
    }
    
    this.isSearching = true;
    const keyword = this.searchText.toLowerCase().trim();
    const results: string[] = [];
    
    if (this.selectedCategory === ResourceCategory.SYMBOL) {
      // 搜索所有Symbol分组
      for (const group of SYMBOL_GROUPS) {
        for (const item of group.items) {
          if (item.toLowerCase().includes(keyword)) {
            results.push(item);
          }
        }
      }
    } else if (this.selectedCategory === ResourceCategory.MEDIA) {
      // 搜索所有Media分组
      for (const group of MEDIA_GROUPS) {
        for (const item of group.items) {
          if (item.toLowerCase().includes(keyword)) {
            results.push(item);
          }
        }
      }
    } else {
      // 搜索颜色
      for (const color of SYSTEM_COLORS) {
        if (color.toLowerCase().includes(keyword)) {
          results.push(color);
        }
      }
    }
    
    this.searchResults = results;
    this.visibleSearchResultCount = SEARCH_RESULT_BATCH_SIZE;
    logger.info(TAG, `搜索 "${keyword}" 找到 ${results.length} 个结果`);
  }
  
  /**
   * 清除搜索
   */
  private clearSearch(): void {
    this.searchText = '';
    this.isSearching = false;
    this.searchResults = [];
    this.visibleSearchResultCount = SEARCH_RESULT_BATCH_SIZE;
  }
  
  /**
   * 复制资源名称到剪贴板
   */
  private copyToClipboard(resourceType: string, resourceName: string): void {
    const fullName = `$r('sys.${resourceType}.${resourceName}')`;
    const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, fullName);
    const systemPasteboard = pasteboard.getSystemPasteboard();
    systemPasteboard.setData(pasteData).then(() => {
      this.getUIContext().getPromptAction().showToast({ message: `已复制: ${fullName}` });
      logger.info(TAG, `复制到剪贴板: ${fullName}`);
    }).catch((err: Error) => {
      logger.error(TAG, `复制失败: ${err.message}`);
      this.getUIContext().getPromptAction().showToast({ message: '复制失败' });
    });
  }
  
  /**
   * 构建搜索框
   */
  @Builder
  buildSearchBar() {
    Row({ space: 8 }) {
      Search({ value: this.searchText, placeholder: '搜索资源名称...' })
        .searchButton('搜索')
        .width('100%')
        .height(40)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
        .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
        .placeholderFont({ size: 14 })
        .textFont({ size: 14 })
        .onChange((value: string) => {
          this.searchText = value;
          if (value === '') {
            this.clearSearch();
          }
        })
        .onSubmit((value: string) => {
          this.searchText = value;
          this.performSearch();
        })
        .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseInOut }))
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
  }
  
  /**
   * 构建搜索结果网格（Symbol/Media）
   */
  @Builder
  buildSearchResultGrid() {
    Column({ space: 8 }) {
      // 搜索结果统计
      Row() {
        Text(`找到 ${this.searchResults.length} 个结果，已加载 ${this.getVisibleSearchResultCount()}`)
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        
        Blank()
        
        Button('清除')
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.clearSearch();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      
      if (this.searchResults.length === 0) {
        // 无结果提示
        Column() {
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(48)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme)])
          Text('未找到匹配的资源')
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
            .margin({ top: 12 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        // 搜索结果网格
        Scroll() {
          Grid() {
            ForEach(this.getVisibleSearchResults(), (itemName: string) => {
              GridItem() {
                Column({ space: 6 }) {
                  if (this.selectedCategory === ResourceCategory.SYMBOL) {
                    SymbolGlyph($r(`sys.symbol.${itemName}`))
                      .fontSize(26)
                      .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
                  } else if (this.selectedCategory === ResourceCategory.MEDIA) {
                    Image($r(`sys.media.${itemName}`))
                      .width(26)
                      .height(26)
                      .objectFit(ImageFit.Contain)
                  } else {
                    // 颜色预览
                    Row()
                      .width(26)
                      .height(26)
                      .borderRadius(4)
                      .backgroundColor($r(`sys.color.${itemName}`))
                  }
                  
                  Text(itemName)
                    .fontSize(9)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .textAlign(TextAlign.Center)
                }
                .width('100%')
                .height('100%')
                .justifyContent(FlexAlign.Center)
                .padding(8)
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
                .borderRadius(8)
                .onClick(() => {
                  const resourceType = this.selectedCategory === ResourceCategory.SYMBOL ? 'symbol' : 
                    (this.selectedCategory === ResourceCategory.MEDIA ? 'media' : 'color');
                  this.copyToClipboard(resourceType, itemName);
                })
              }
              .aspectRatio(1)
            })
          }
          .columnsTemplate('1fr 1fr 1fr 1fr')
          .columnsGap(8)
          .rowsGap(8)
          .padding(16)
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .onScrollStop(() => {
          if (this.hasMoreSearchResults()) {
            this.loadMoreSearchResults();
          }
        })
      }
    }
    .width('100%')
    .layoutWeight(1)
    .transition(TransitionEffect.asymmetric(
      TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseOut }),
      TransitionEffect.OPACITY.animation({ duration: 150, curve: Curve.EaseIn })
    ))
  }
  
  /**
   * 构建分类选择器
   */
  @Builder
  buildCategorySelector() {
    Row({ space: 12 }) {
      Button(this.getCategoryLabel(ResourceCategory.SYMBOL))
        .fontSize(14)
        .fontColor(this.selectedCategory === ResourceCategory.SYMBOL 
          ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
          : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.selectedCategory = ResourceCategory.SYMBOL;
          this.selectedGroupIndex = 0;
          this.isSearching = false;
          this.searchResults = [];
          this.resetSegmentedLoading();
        })
      
      Button(this.getCategoryLabel(ResourceCategory.MEDIA))
        .fontSize(14)
        .fontColor(this.selectedCategory === ResourceCategory.MEDIA 
          ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
          : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.selectedCategory = ResourceCategory.MEDIA;
          this.selectedGroupIndex = 0;
          this.isSearching = false;
          this.searchResults = [];
          this.resetSegmentedLoading();
        })
      
      Button(this.getCategoryLabel(ResourceCategory.COLOR))
        .fontSize(14)
        .fontColor(this.selectedCategory === ResourceCategory.COLOR 
          ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
          : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.selectedCategory = ResourceCategory.COLOR;
          this.isSearching = false;
          this.searchResults = [];
          this.resetSegmentedLoading();
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .justifyContent(FlexAlign.Start)
  }
  
  /**
   * 构建分组选择器
   */
  @Builder
  buildGroupSelector() {
    Column({ space: 8 }) {

      Row() {
        Text(this.getSelectedGroupSummaryText())
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

        Blank()

        Text(this.getVisibleGroupCount().toString() + '/' + this.getCurrentGroups().length.toString() + ' groups')
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
      }
      .width('100%')
      .padding({ left: 16, right: 16 })

      Scroll() {
        Row({ space: 8 }) {
          ForEach(this.getVisibleGroups(), (group: SystemSymbolResourceGroup, index: number) => {
            Button(`${group.name} ${group.items.length}`)
              .fontSize(13)
              .fontColor(this.selectedGroupIndex === index 
                ? Color.White
                : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .backgroundColor(this.selectedGroupIndex === index 
                ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
              .borderRadius(16)
              .height(32)
              .onClick(() => {
                this.selectedGroupIndex = index;
                this.resetGridItemLoading();
              })
          })
        }
        .padding({ left: 16, right: 16 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .height(40)
      .onScrollStop(() => {
        if (this.hasMoreGroups()) {
          this.loadMoreGroups();
        }
      })
    }
    .width('100%')
    .padding({ top: 4, bottom: 4 })
  }
  
  /**
   * 构建Symbol图标网格
   */
  @Builder
  buildSymbolGrid() {
    Column({ space: 8 }) {
      Scroll() {
        Grid() {
          ForEach(this.getVisibleCurrentGridItems(), (itemName: string) => {
            GridItem() {
              Column({ space: 6 }) {
                SymbolGlyph($r(`sys.symbol.${itemName}`))
                  .fontSize(26)
                  .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
                
                Text(itemName)
                  .fontSize(9)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .textAlign(TextAlign.Center)
              }
              .width('100%')
              .height('100%')
              .justifyContent(FlexAlign.Center)
              .padding(6)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
              .borderRadius(8)
              .onClick(() => {
                this.copyToClipboard('symbol', itemName);
              })
            }
            .aspectRatio(1)
          })
        }
        .columnsTemplate('1fr 1fr 1fr 1fr')
        .rowsGap(10)
        .columnsGap(10)
        .padding(12)
        .width('100%')
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .onScrollStop(() => {
        if (this.hasMoreCurrentGridItems()) {
          this.loadMoreCurrentGridItems();
        }
      })
    }
    .width('100%')
    .layoutWeight(1)
  }

  /**
   * 构建Media图标网格
   */
  @Builder
  buildMediaGrid() {
    Column({ space: 8 }) {
      Scroll() {
        Grid() {
          ForEach(this.getVisibleCurrentGridItems(), (itemName: string) => {
            GridItem() {
              Column({ space: 6 }) {
                Image($r(`sys.media.${itemName}`))
                  .width(28)
                  .height(28)
                  .fillColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                
                Text(itemName)
                  .fontSize(9)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .textAlign(TextAlign.Center)
              }
              .width('100%')
              .height('100%')
              .justifyContent(FlexAlign.Center)
              .padding(6)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
              .borderRadius(8)
              .onClick(() => {
                this.copyToClipboard('media', itemName);
              })
            }
            .aspectRatio(1)
          })
        }
        .columnsTemplate('1fr 1fr 1fr 1fr')
        .rowsGap(10)
        .columnsGap(10)
        .padding(12)
        .width('100%')
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .onScrollStop(() => {
        if (this.hasMoreCurrentGridItems()) {
          this.loadMoreCurrentGridItems();
        }
      })
    }
    .width('100%')
    .layoutWeight(1)
  }

  /**
   * 构建颜色列表
   */
  @Builder
  buildColorList() {
    List() {
      ForEach(SYSTEM_COLORS, (colorName: string) => {
        ListItem() {
          Row({ space: 12 }) {
            // 颜色预览
            Column()
              .width(48)
              .height(48)
              .backgroundColor($r(`sys.color.${colorName}`))
              .borderRadius(8)
              .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme) })
            
            // 颜色名称
            Column({ space: 4 }) {
              Text(colorName)
                .fontSize(14)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              
              Text(`$r('sys.color.${colorName}')`)
                .fontSize(12)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
          }
          .width('100%')
          .padding(12)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
          .borderRadius(8)
          .onClick(() => {
            this.copyToClipboard('color', colorName);
          })
        }
        .margin({ bottom: 8 })
      })
    }
    .padding(16)
    .width('100%')
    .layoutWeight(1)
  }
  
  build() {
    HdsNavDestination() {
      Stack() {
        SharedPageBackgroundLayer({
          defaultBackgroundColor: ThemeAwareHelper.getTestManagementThemedColor('background_dark', this.themeState.currentTheme),
          mode: GlobalBackgroundLayerMode.IMMERSIVE
        })
          .width('100%')
          .height('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        Column() {
          Blank().height(SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight))

          this.buildSearchBar()
          this.buildCategorySelector()

          if (this.isSearching) {
            this.buildSearchResultGrid()
          } else {
            if (this.selectedCategory === ResourceCategory.SYMBOL) {
              this.buildGroupSelector()
              this.buildSymbolGrid()
            } else if (this.selectedCategory === ResourceCategory.MEDIA) {
              this.buildGroupSelector()
              this.buildMediaGrid()
            } else {
              this.buildColorList()
            }
          }

        }
        .width('100%')
        .height('100%')

        SettingsImmersiveTitleBar({
          themeState: this.themeState,
          title: '系统资源预览',
          appFontFamily: this.appFontFamily
        })
      }
    }
    .hideTitleBar(true)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .backgroundColor(Color.Transparent)
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
    })
    .onBackPressed(() => {
      if (this.isSearching) {
        this.clearSearch();
        return true;
      }
      this.pathStack.pop();
      return true;
    })
  }
}
