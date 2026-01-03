/**
 * 系统资源预览页面
 * 展示HarmonyOS系统图标和颜色资源
 * 支持按需加载和分类浏览
 */

import { logger } from '../Utils/Logger';
import { ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { pasteboard } from '@kit.BasicServicesKit';
import { promptAction } from '@kit.ArkUI';

const TAG = 'SystemResourcePreviewPage';

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
interface ResourceGroup {
  name: string;
  items: string[];
}

interface ThemeState {
  currentTheme: ThemeType;
}

// Media图标列表（按分组）- 完整列表
const MEDIA_GROUPS: ResourceGroup[] = [
  {
    name: '基础图标',
    items: [
      'ohos_app_icon', 'ohos_ic_back', 'ohos_ic_public_ok', 'ohos_ic_public_ok_filled',
      'ohos_ic_public_arrow_left', 'ohos_ic_public_arrow_right', 'ohos_ic_public_arrow_up',
      'ohos_ic_public_arrow_down', 'ohos_icon_mask_svg'
    ]
  },
  {
    name: '编辑操作',
    items: [
      'ohos_ic_public_cut', 'ohos_ic_public_copy', 'ohos_ic_public_paste',
      'ohos_ic_public_select_all', 'ohos_ic_public_share', 'ohos_ic_public_edit',
      'ohos_ic_public_remove', 'ohos_ic_public_remove_filled', 'ohos_ic_public_add',
      'ohos_ic_public_add_norm_filled', 'ohos_ic_public_minus'
    ]
  },
  {
    name: '搜索保存',
    items: [
      'ohos_ic_public_search_filled', 'ohos_save_button_filled', 'ohos_save_button_line',
      'ohos_ic_public_translate_c2e', 'save_button_picture'
    ]
  },
  {
    name: '关闭取消',
    items: [
      'ohos_ic_bottomsheet_close', 'ohos_ic_public_cancel', 'ohos_ic_public_cancel_filled',
      'ohos_ic_public_close', 'ohos_ic_public_fail', 'ohos_ic_public_input_cancel'
    ]
  },
  {
    name: '通讯信息',
    items: [
      'ohos_ic_public_clock', 'ohos_ic_public_email', 'ohos_ic_public_express',
      'ohos_ic_public_flight', 'ohos_ic_public_location', 'ohos_ic_public_phone',
      'ohos_ic_public_text', 'ohos_ic_public_web', 'ic_public_worldclock_filled'
    ]
  },
  {
    name: '设备图标',
    items: [
      'ohos_ic_public_device_matebook', 'ohos_ic_public_device_pad',
      'ohos_ic_public_device_smartscreen', 'ohos_ic_public_device_smartscreen_filled',
      'ohos_ic_public_device_watch', 'ohos_ic_public_device_phone',
      'ohos_ic_public_device_bluetooth_filled', 'ohos_ic_public_device_earphone_filled',
      'ohos_ic_public_device_earpiece_filled', 'ohos_ic_public_device_speaker_filled',
      'ohos_ic_public_device_sound_filled', 'ohos_ic_public_device_soundx_filled'
    ]
  },
  {
    name: '媒体控制',
    items: [
      'ohos_ic_public_pause', 'ohos_ic_public_play_last', 'ohos_ic_public_play_next',
      'ohos_ic_public_play', 'ohos_ic_public_restore', 'ohos_ic_public_sound_off',
      'ohos_ic_public_sound', 'ohos_ic_public_video_off', 'ohos_ic_public_video',
      'ohos_ic_public_voice_off', 'ohos_ic_public_voice', 'ohos_ic_public_hang_up',
      'safe_volume_notification_icon'
    ]
  },
  {
    name: '相册扫描',
    items: [
      'ohos_ic_public_albums', 'ohos_ic_public_scan', 'ohos_ic_public_camera',
      'ohos_ic_public_cast_stream', 'ohos_ic_public_cast_mirror', 'ohos_ic_eco_hop',
      'ohos_ic_public_more', 'ic_public_camera_beauty'
    ]
  },
  {
    name: '文件类型',
    items: [
      'ohos_ic_normal_white_grid_zip', 'ohos_ic_normal_white_grid_xml',
      'ohos_ic_normal_white_grid_xls', 'ohos_ic_normal_white_grid_wma',
      'ohos_ic_normal_white_grid_wav', 'ohos_ic_normal_white_grid_video',
      'ohos_ic_normal_white_grid_txt', 'ohos_ic_normal_white_grid_pdf',
      'ohos_ic_normal_white_grid_mp3', 'ohos_ic_normal_white_grid_image',
      'ohos_ic_normal_white_grid_html', 'ohos_ic_normal_white_grid_folder',
      'ohos_ic_normal_white_grid_flac', 'ohos_ic_normal_white_grid_doc',
      'ohos_ic_normal_white_grid_compress', 'ohos_ic_normal_white_grid_calendar',
      'ohos_ic_normal_white_grid_audio'
    ]
  },
  {
    name: '标题栏',
    items: [
      'ohos_ic_compnent_titlebar_back', 'ohos_ic_compnent_titlebar_back_filled',
      'ohos_ic_public_drawer_close', 'ohos_ic_public_drawer_close_filled',
      'ohos_ic_public_drawer_open', 'ohos_ic_public_drawer_open_filled'
    ]
  },
  {
    name: '用户认证',
    items: [
      'ohos_user_auth_icon_face', 'ohos_user_auth_icon_fingerprint',
      'app_lock_picture', 'ic_time_limit_picture'
    ]
  },
  {
    name: '窗口菜单',
    items: [
      'ohos_ic_window_menu_screen_t', 'ohos_ic_window_menu_screen_b',
      'ohos_ic_window_menu_waterfall', 'ohos_ic_window_menu_moveto_t',
      'ohos_ic_window_menu_moveto_b', 'ohos_ic_window_menu_back'
    ]
  },
  {
    name: '克隆应用',
    items: [
      'clone_app_badge_1', 'clone_app_badge_2', 'clone_app_badge_3',
      'clone_app_badge_4', 'clone_app_badge_5'
    ]
  },
  {
    name: '拖拽图标',
    items: [
      'Copy_Drag', 'Copy_One_Drag', 'Forbid_Drag', 'Forbid_One_Drag', 'Move_Drag'
    ]
  },
  {
    name: 'AI写作',
    items: [
      'ic_public_ai_write'
    ]
  }
];

// Symbol图标列表（按分组）- 完整3347个symbol
const SYMBOL_GROUPS: ResourceGroup[] = [
  {
    name: '基础OHOS',
    items: [
      'ohos_wifi', 'ohos_trash', 'ohos_trash_circle', 'ohos_photo', 'ohos_folder_badge_plus',
      'ohos_lungs', 'ohos_mic', 'ohos_circle', 'ohos_lock', 'ohos_star', 'ohos_arrow_up'
    ]
  },
  {
    name: '播放控制',
    items: [
      'heart_slash', 'speaker_slash', 'repeat_1', 'checkmark_circle', 'play_circle_fill',
      'speaker_plus', 'speaker_wave_3', 'rays', 'kidswatch_fill', 'play_circle', 'pause_circle',
      'play_fill', 'pause', 'play', 'play_rectangle', 'play_rectangle_fill', 'play_slash',
      'play_slash_fill', 'pause_fill', 'pause_circle_fill', 'pause_rectangle', 'pause_rectangle_fill',
      'stop', 'stop_fill', 'stop_circle', 'stop_circle_fill', 'record_circle', 'record_circle_fill',
      'playpause', 'playpause_fill', 'backward', 'backward_fill', 'forward', 'forward_fill',
      'backward_end', 'backward_end_fill', 'forward_end', 'forward_end_fill', 'shuffle', 'repeat',
      'infinity', 'goforward_5', 'goforward_10', 'goforward_15', 'goforward_30', 'gobackward_5',
      'gobackward_10', 'gobackward_15', 'gobackward_30','play', 'play_fill', 'play_circle',
      'play_rectangle', 'play_rectangle_fill', 'play_slash', 'play_slash_fill',
      'pause', 'pause_fill', 'pause_circle', 'pause_circle_fill', 'pause_rectangle',
      'pause_rectangle_fill', 'stop', 'stop_fill', 'stop_circle', 'stop_circle_fill',
      'record_circle', 'record_circle_fill', 'playpause', 'playpause_fill', 'playpause_circle',
      'playpause_circle_fill', 'backward', 'backward_fill', 'backward_circle',
      'backward_circle_fill', 'forward', 'forward_fill', 'forward_circle', 'forward_circle_fill',
      'backward_end', 'backward_end_fill', 'forward_end', 'forward_end_fill',
      'backward_end_alt', 'backward_end_alt_fill', 'forward_end_alt', 'forward_end_alt_fill',
      'backward_frame', 'backward_frame_fill', 'forward_frame', 'forward_frame_fill',
      'eject', 'eject_fill', 'eject_circle', 'eject_circle_fill', 'mount', 'mount_fill',
      'shuffle', 'shuffle_circle', 'shuffle_circle_fill', 'repeat', 'repeat_circle',
      'repeat_circle_fill', 'repeat_1', 'repeat_1_circle', 'repeat_1_circle_fill',
      'infinity', 'infinity_circle', 'infinity_circle_fill', 'goforward', 'gobackward',
      'goforward_5', 'gobackward_5', 'goforward_10', 'gobackward_10', 'goforward_15',
      'gobackward_15', 'goforward_30', 'gobackward_30', 'goforward_45', 'gobackward_45',
      'goforward_60', 'gobackward_60', 'goforward_75', 'gobackward_75', 'goforward_90',
      'gobackward_90', 'goforward_plus', 'gobackward_minus','play_circle_fill',
      'play_square', 'play_square_fill',
    ]
  },
  {
    name: '时间日历',
    items: [
      'doc_plaintext_fill_1', 'checkmark_circle_fill_1', 'alarm_fill_1', 'stopwatch_2',
      'worldclock_fill_2', 'timer_circle_fill', 'alarm_1', 'calendar_1', 'worldclock_fill_1',
      'stopwatch_fill_1', 'stopwatch_1', 'calendar', 'calendar_circle', 'calendar_circle_fill',
      'calendar_badge_plus', 'calendar_badge_minus', 'calendar_badge_clock',
      'calendar_badge_exclamationmark', 'clock', 'clock_fill', 'clock_badge_checkmark',
      'clock_badge_checkmark_fill', 'clock_badge_exclamationmark', 'clock_badge_exclamationmark_fill',
      'alarm', 'alarm_fill', 'stopwatch', 'stopwatch_fill', 'timer', 'timer_square'
    ]
  },
  {
    name: '日历数字',
    items: [
      'calendar_01_a', 'calendar_02_a', 'calendar_03_a', 'calendar_04_a', 'calendar_05_a',
      'calendar_06_a', 'calendar_07_a', 'calendar_08_a', 'calendar_09_a', 'calendar_10_a',
      'calendar_11_a', 'calendar_12_a', 'calendar_13_a', 'calendar_14_a', 'calendar_15_a',
      'calendar_16_a', 'calendar_17_a', 'calendar_18_a', 'calendar_19_a', 'calendar_20_a',
      'calendar_21_a', 'calendar_22_a', 'calendar_23_a', 'calendar_24_a', 'calendar_25_a',
      'calendar_26_a', 'calendar_27_a', 'calendar_28_a', 'calendar_29_a', 'calendar_30_a',
      'calendar_31_a'
    ]
  },
  {
    name: '导航首页',
    items: [
      'house_fill_1', 'person_crop_circle_fill_1', 'auditorium', 'ranking_fill',
      'slider_horizontal_2_1', 'indent_right', 'indentation_left', 'frame_overlay_rectify',
      'house', 'house_fill', 'house_circle', 'house_circle_fill', 'building', 'building_fill',
      'building_2', 'building_2_fill', 'building_columns', 'building_columns_fill'
    ]
  },
  {
    name: '存储卡片',
    items: [
      'sdcard_fill', 'sdcard_1', 'simcard_fill', 'simcard_3', 'checkmark_square_fill', 'card',
      'sd_card', 'TF_card', 'TF_card_1', 'simcard_fill_1_and_simcard_fill_2', 'creditcard',
      'creditcard_fill', 'creditcard_circle', 'creditcard_circle_fill'
    ]
  },
  {
    name: '编辑操作',
    items: [
      'undo', 'redo', 'download', 'upload', 'download_1',
      'square_and_arrow_down_1', 'arrow_down_circle_badge_vip_circle_filled'
    ]
  },
  {
    name: '图表排名',
    items: [
      'histogram', 'ranking', 'arrowshape_right_fill', 'histogram_fill', 'general_rectangle_fill',
      'sum_rectangle_fill', 'cltc_rectangle_fill', 'wltc_rectangle_fill', 'chart_bar_fill',
      'chart_pie', 'chart_pie_fill', 'chart_bar', 'chart_bar_square', 'chart_bar_square_fill'
    ]
  },
  {
    name: '智能AI',
    items: [
      'master_ai', 'intelligent', 'AI_person', 'AI_shield', 'network_acceleration', 'performance',
      'AI_best_expression', 'AI_expand', 'AI_flower', 'AI_retouch', 'AI_straighten', 'AI',
      'Celia', 'hi_vison', 'wand_and_stars_fill', 'wand_and_stars', 'sparkles'
    ]
  },
  {
    name: '相机拍摄',
    items: [
      'camera', 'camera_fill', 'camera_circle', 'camera_circle_fill', 'camera_badge_ellipsis',
      'camera_AF', 'camera_portrait_efferts', 'shutter_photo', 'shutter_photo_1', 'hdr',
      'motion_stabilization', 'motion_stabilization_slash', 'movie_fill', 'movie_slash', 'movie',
      'time_lapse', 'video_speed', 'camera_viewfinder', 'camera_metering_center_weighted',
      'camera_metering_matrix', 'camera_metering_spot', 'camera_aperture', 'camera_filters',
      'camera_macro', 'camera_macro_circle', 'qrcode', 'qrcode_viewfinder', 'barcode',
      'photo', 'photo_fill', 'photo_circle', 'photo_circle_fill', 'photo_stack', 'photo_stack_fill',
      'photo_artframe', 'photo_badge_plus', 'photo_self_portrait', 'capture_smiles'
    ]
  },
  {
    name: '安全隐私',
    items: [
      'lock', 'lock_fill', 'lock_circle', 'lock_circle_fill', 'lock_slash', 'lock_slash_fill',
      'lock_open', 'lock_open_fill', 'lock_text_rectangle_portrait', 'lock_badge_child',
      'lock_filled_arrow_counterclockwise', 'person_shield_1', 'plus_shield_badge_1',
      'plus_shield_badge_2', 'exclamationmark_shield_fill', 'hand_raised_hexagon_fill',
      'security_shield', 'anti_fraud_fill', 'shield', 'shield_fill', 'shield_slash',
      'shield_slash_fill', 'shield_lefthalf_fill', 'key', 'key_fill', 'key_horizontal',
      'key_horizontal_fill', 'faceid', 'touchid', 'person_shield_badge_clock'
    ]
  },
  {
    name: '汽车交通',
    items: [
      'car', 'car_fill', 'car_circle', 'car_circle_fill', 'car_suv_fill', 'car_suv',
      'steering_wheel', 'car_ac_1', 'car_base', 'car_badge_vs_fill', 'car_distance', 'sentry_mode',
      'car_top_door_front_left_open', 'car_top_door_front_right_open', 'car_window_close',
      'car_window_fill', 'car_camera_recorder', 'car_side_front_open_down', 'headlight_fog',
      'hazard_sign', 'horn_fill', 'brake', 'auto_car_brake', 'auto_car_obstacle_avoidance',
      'bus', 'bus_fill', 'tram', 'tram_fill', 'airplane', 'airplane_circle', 'airplane_departure',
      'airplane_arrival', 'bicycle', 'bicycle_circle', 'fuelpump', 'fuelpump_fill', 'ev_charger',
      'parkingsign', 'parkingsign_circle', 'car_parking_spot', 'elevator', 'stair'
    ]
  },
  {
    name: '箭头方向',
    items: [
      'arrow_up', 'arrow_up_circle', 'arrow_up_circle_fill', 'arrow_down', 'arrow_down_circle',
      'arrow_down_circle_fill', 'arrow_left', 'arrow_left_circle', 'arrow_left_circle_fill',
      'arrow_right', 'arrow_right_circle', 'arrow_right_circle_fill', 'arrow_up_left',
      'arrow_up_right', 'arrow_down_left', 'arrow_down_right', 'arrow_uturn_left',
      'arrow_uturn_right', 'arrow_uturn_up', 'arrow_uturn_down', 'arrow_left_arrow_right',
      'arrow_up_arrow_down', 'arrow_clockwise', 'arrow_counterclockwise', 'arrow_2_circlepath',
      'arrow_triangle_2_circlepath', 'arrow_3_trianglepath', 'arrowshape_turn_up_left',
      'arrowshape_turn_up_right', 'arrowshape_zigzag_right', 'arrowshape_bounce_right',
      'chevron_up', 'chevron_down', 'chevron_left', 'chevron_right', 'chevron_up_circle',
      'chevron_down_circle', 'chevron_left_2', 'chevron_right_2', 'chevron_up_L', 'chevron_down_L'
    ]
  },
  {
    name: '形状图形',
    items: [
      'square_fill', 'circle_fill', 'arrowtriangle_left_fill', 'arrowtriangle_left',
      'arrowtriangle_right_fill', 'arrowtriangle_right', 'arrowtriangle_up_fill',
      'arrowtriangle_down_fill', 'triangle', 'triangle_fill', 'diamond', 'diamond_fill',
      'octagon', 'octagon_fill', 'hexagon', 'hexagon_fill', 'pentagon', 'pentagon_fill',
      'seal', 'seal_fill', 'rhombus', 'rhombus_fill', 'capsule', 'capsule_fill',
      'oval', 'oval_fill', 'rectangle', 'rectangle_fill', 'rectangle_portrait',
      'rectangle_split_2x1', 'rectangle_split_3x1', 'rectangle_split_3x3',
      'rectangle_on_rectangle', 'rectangle_stack', 'rectangle_stack_fill',
      'square_on_square', 'square_stack', 'square_stack_fill', 'circle_grid_2x2',
      'circle_grid_3x3', 'square_grid_2x2', 'square_grid_3x3'
    ]
  },
  {
    name: '人物用户',
    items: [
      'person', 'person_fill', 'person_circle', 'person_circle_fill', 'person_crop_circle',
      'person_crop_circle_fill', 'person_crop_square', 'person_crop_square_fill',
      'person_badge_plus', 'person_badge_plus_fill', 'person_badge_minus', 'person_badge_minus_fill',
      'person_badge_checkmark', 'person_badge_xmark', 'person_2', 'person_2_fill',
      'person_3', 'person_3_fill', 'person_crop_circle_badge_plus', 'person_crop_circle_badge_minus',
      'person_crop_circle_badge_checkmark', 'person_crop_circle_badge_xmark',
      'person_crop_circle_dashed', 'person_filled_viewfinder', 'person_square_fill',
      'figure_walk', 'figure_walk_circle', 'figure_stand', 'figure_wave', 'guardian'
    ]
  },
  {
    name: '心形收藏',
    items: [
      'heart', 'heart_fill', 'heart_circle', 'heart_circle_fill', 'heart_slash',
      'heart_slash_circle', 'heart_text_square', 'heart_square_stack_fill', 'bolt_heart',
      'bolt_heart_fill', 'star', 'star_fill', 'star_circle', 'star_circle_fill',
      'star_slash', 'star_slash_fill', 'flag', 'flag_fill', 'flag_circle', 'flag_circle_fill',
      'flag_slash', 'flag_slash_fill', 'bookmark', 'bookmark_fill', 'bookmark_circle',
      'bookmark_slash', 'plus_bookmark', 'tag', 'tag_fill', 'tag_circle', 'tag_slash'
    ]
  },
  {
    name: '消息通讯',
    items: [
      'bubble_left', 'bubble_left_fill', 'bubble_right', 'bubble_right_fill',
      'bubble_left_and_bubble_right', 'bubble_middle_bottom', 'ellipsis_message_1',
      'message_badge_checkmark_fill', 'message_badge_gearshape', 'message_badge_plus_fill',
      'line_message_fill', 'phone', 'phone_fill', 'phone_circle', 'phone_circle_fill',
      'phone_badge_plus', 'phone_down', 'phone_down_fill', 'phone_arrow_up_right',
      'phone_arrow_down_left', 'phone_connection', 'phone_sos', 'phone_badge_video',
      'phone_badge_satellite_fill', 'video', 'video_fill', 'video_circle', 'video_circle_fill',
      'video_slash', 'video_slash_fill', 'video_badge_plus', 'video_badge_checkmark',
      'envelope', 'envelope_fill', 'envelope_circle', 'envelope_open', 'envelope_badge'
    ]
  },
  {
    name: '音频扬声器',
    items: [
      'speaker', 'speaker_fill', 'speaker_slash', 'speaker_slash_fill', 'speaker_zzz',
      'speaker_wave_1', 'speaker_wave_1_fill', 'speaker_wave_2', 'speaker_wave_2_fill',
      'speaker_wave_3_fill', 'speaker_wave_3_slash', 'speaker_badge_exclamationmark',
      'mic', 'mic_fill', 'mic_circle', 'mic_circle_fill', 'mic_circle_filled', 'mic_slash',
      'mic_slash_fill', 'music_note', 'music_note_list', 'music_quarternote_3', 'music_mic',
      'headphones', 'headphones_circle', 'headphones_circle_fill', 'hifispeaker',
      'hifispeaker_fill', 'hifispeaker_2', 'hifispeaker_2_fill', 'airpods', 'airpodspro',
      'beats_headphones', 'earpods', 'homepod', 'homepod_fill', 'homepodmini', 'homepodmini_fill'
    ]
  },
  {
    name: '设备硬件',
    items: [
      'desktopcomputer', 'pc', 'laptopcomputer', 'display', 'display_2', 'tv', 'tv_fill',
      'tv_circle', 'tv_slash', 'iphone', 'iphone_circle', 'iphone_slash', 'iphone_homebutton',
      'ipad', 'ipad_homebutton', 'ipad_landscape', 'applewatch', 'applewatch_watchface',
      'keyboard', 'keyboard_fill', 'printer', 'printer_fill', 'scanner', 'scanner_fill',
      'cpu', 'cpu_fill', 'memorychip', 'memorychip_fill', 'hard_disk', 'memory_module',
      'server_rack', 'externaldrive', 'externaldrive_fill', 'opticaldisc', 'opticaldisc_fill',
      'gamecontroller', 'gamecontroller_fill', 'remote_control_component', 'powercord'
    ]
  },
  {
    name: '网络WiFi',
    items: [
      'wifi', 'wifi_slash', 'wifi_exclamationmark', 'wifi_circle', 'wifi_circle_fill',
      'wifi_lock', 'antenna_radiowaves_left_and_right', 'dot_radiowaves_left_and_right',
      'dot_radiowaves_right', 'wave_3_left', 'wave_3_right', 'cellularbars', 'personalhotspot',
      'personalhotspot_circle', 'network', 'network_slash', 'network_badge_shield_half_filled',
      'globe', 'globe_americas', 'globe_europe_africa', 'globe_asia_australia',
      'bolt_horizontal', 'bolt_horizontal_fill', 'signal_check', 'mobiledata_and_cloud',
      'beidou_satellite_circle_fill', 'multiscreen_collaboration', 'multiscreen',
      'wireless_projection_1', 'screen_share_fill', 'screen_share', 'statusbar_cast'
    ]
  },
  {
    name: '云存储',
    items: [
      'icloud', 'icloud_fill', 'icloud_circle', 'icloud_circle_fill', 'icloud_slash',
      'icloud_slash_fill', 'exclamationmark_icloud', 'checkmark_icloud', 'xmark_icloud',
      'link_icloud', 'bolt_icloud', 'person_icloud', 'lock_icloud', 'key_icloud',
      'arrow_clockwise_icloud', 'arrow_counterclockwise_icloud', 'icloud_and_arrow_down',
      'icloud_and_arrow_up', 'cloud', 'cloud_fill', 'cloud_rain', 'cloud_rain_fill',
      'cloud_sun', 'cloud_sun_fill', 'cloud_moon', 'cloud_moon_fill', 'cloud_bolt',
      'cloud_bolt_fill', 'cloud_snow', 'hidisk', 'externaldrive_badge_icloud'
    ]
  },
  {
    name: '天气环境',
    items: [
      'sun_min', 'sun_max', 'sun_max_fill', 'moon', 'moon_fill', 'moon_circle_fill',
      'moon_slash_circle', 'sparkles', 'smoke', 'smoke_fill', 'wind', 'snowflake',
      'tornado', 'thermometer_sun', 'thermometer_snowflake', 'thermometer', 'humidity',
      'humidity_fill', 'drop', 'drop_fill', 'flame', 'flame_fill', 'flame_fill_1',
      'bolt', 'bolt_fill', 'bolt_circle', 'bolt_circle_fill', 'bolt_slash', 'bolt_slash_fill',
      'rays', 'sunprotection', 'sunsetglow_fill', 'UV_sun_max', 'rainfall_circle_fill',
      'typhoon_fill', 'frozen_rain', 'icing_and_snow_road', 'icing_road', 'water_waves'
    ]
  },
  {
    name: '文件文档',
    items: [
      'doc', 'doc_fill', 'doc_circle', 'doc_badge_plus', 'doc_badge_gearshape',
      'doc_text', 'doc_text_fill', 'doc_text_viewfinder', 'doc_richtext', 'doc_plaintext',
      'doc_plaintext_fill', 'doc_append', 'doc_on_doc', 'doc_on_clipboard', 'doc_rectify',
      'doc_text_badge_clock', 'doc_text_badge_person', 'doc_text_badge_park',
      'doc_text_badge_bolt', 'doc_text__badge_bolt_house', 'doc_text_badge_yuan',
      'clipboard', 'clipboard_fill', 'clipboard_sharing', 'list_clipboard', 'note', 'note_text'
    ]
  },
  {
    name: '文件夹',
    items: [
      'folder', 'folder_fill', 'folder_circle', 'folder_circle_fill', 'folder_badge_plus',
      'folder_fill_badge_plus', 'folder_badge_minus', 'folder_badge_questionmark',
      'folder_badge_gearshape', 'folder_badge_person_crop', 'paperplane', 'paperplane_fill',
      'paperplane_circle', 'paperplane_right_2', 'tray', 'tray_fill', 'tray_full',
      'tray_and_arrow_up', 'tray_and_arrow_down', 'tray_2', 'archivebox', 'archivebox_fill',
      'archivebox_circle', 'bin_xmark', 'bin_xmark_fill', 'xmark_bin', 'xmark_bin_fill'
    ]
  },
  {
    name: '编辑工具',
    items: [
      'pencil', 'pencil_circle', 'pencil_circle_fill', 'pencil_slash', 'pencil_line',
      'square_and_pencil', 'scribble', 'highlighter', 'highlighter_line', 'pencil_tip',
      'pencil_tip_crop_circle', 'lasso', 'lasso_and_sparkles', 'trash', 'trash_fill',
      'trash_circle', 'trash_circle_fill', 'trash_slash', 'trash_slash_fill',
      'scissors', 'scissors_circle', 'scissors_badge_ellipsis', 'wand_and_rays',
      'wand_and_rays_inverse', 'crop', 'crop_rotate', 'dial_min', 'dial_max',
      'slider_horizontal_3', 'slider_vertical_3', 'paintbrush', 'paintbrush_fill',
      'paintbrush_pointed', 'paintbrush_pointed_fill', 'paintpalette', 'paintpalette_fill',
      'eyedropper', 'eyedropper_halffull', 'eyedropper_full', 'rotate_left', 'rotate_right'
    ]
  },
  {
    name: '加减操作',
    items: [
      'plus', 'plus_circle', 'plus_circle_fill', 'plus_square', 'plus_square_fill',
      'plus_rectangle', 'plus_rectangle_fill', 'minus', 'minus_circle', 'minus_circle_fill',
      'minus_square', 'minus_square_fill', 'minus_rectangle', 'minus_rectangle_fill',
      'xmark', 'xmark_circle', 'xmark_circle_fill', 'xmark_square', 'xmark_square_fill',
      'checkmark', 'checkmark_circle', 'checkmark_circle_fill', 'checkmark_square',
      'checkmark_square_fill', 'checkmark_rectangle', 'checkmark_seal', 'checkmark_seal_fill',
      'exclamationmark', 'exclamationmark_circle', 'exclamationmark_circle_fill',
      'exclamationmark_triangle', 'exclamationmark_triangle_fill', 'questionmark',
      'questionmark_circle', 'questionmark_circle_fill', 'info_circle', 'info_circle_fill'
    ]
  },
  {
    name: '眼睛视觉',
    items: [
      'eye', 'eye_fill', 'eye_circle', 'eye_circle_fill', 'eye_slash', 'eye_slash_fill',
      'eye_trianglebadge_exclamationmark', 'visibility', 'visual_accessibility',
      'viewfinder', 'viewfinder_circle', 'viewfinder_circle_fill', 'scope', 'magnifyingglass',
      'magnifyingglass_circle', 'magnifyingglass_circle_fill', 'plus_magnifyingglass',
      'minus_magnifyingglass', 'a_magnify', 'checkered_magnifyingglass', 'search_things',
      'text_magnifyingglass', 'doc_text_magnifyingglass', 'location_magnifyingglass'
    ]
  },
  {
    name: '设置齿轮',
    items: [
      'gearshape', 'gearshape_fill', 'gearshape_circle', 'gearshape_circle_fill',
      'gearshape_2', 'gearshape_2_fill', 'wrench', 'wrench_fill', 'wrench_and_screwdriver',
      'wrench_and_screwdriver_fill', 'wrench_arrow_counterclockwise', 'wrench_rectangle_portrait',
      'hammer', 'hammer_fill', 'hammer_circle', 'hammer_circle_fill', 'screwdriver',
      'screwdriver_fill', 'eyedropper', 'eyedropper_halffull', 'eyedropper_full',
      'level', 'level_fill', 'ruler', 'ruler_fill', 'aspectratio', 'aspectratio_fill'
    ]
  },
  {
    name: '电源电池',
    items: [
      'power', 'power_circle', 'power_circle_fill', 'power_dotted', 'powersleep',
      'poweroff', 'poweron', 'wake', 'sleep', 'bolt_batteryblock', 'bolt_batteryblock_fill',
      'battery_100', 'battery_75', 'battery_50', 'battery_25', 'battery_0',
      'battery_100_bolt', 'minus_plus_batteryblock', 'minus_plus_batteryblock_fill',
      'power_circle_fill', 'lightbulb', 'lightbulb_fill', 'lightbulb_circle',
      'lightbulb_circle_fill', 'lightbulb_slash', 'lightbulb_slash_fill', 'lightbulb_1'
    ]
  },
  {
    name: '铃铛通知',
    items: [
      'bell', 'bell_fill', 'bell_circle', 'bell_circle_fill', 'bell_slash', 'bell_slash_fill',
      'bell_badge', 'bell_badge_fill', 'bell_and_waveform', 'bell_and_waveform_fill',
      'alarm', 'alarm_fill', 'alarm_waves_left_and_right', 'megaphone', 'megaphone_fill',
      'horn', 'horn_fill', 'horn_blast', 'horn_blast_fill', 'exclamationmark_bubble',
      'exclamationmark_bubble_fill', 'caution', 'caution_fill', 'warning'
    ]
  },
  {
    name: '手势操作',
    items: [
      'hand_raised', 'hand_raised_fill', 'hand_raised_slash', 'hand_raised_slash_fill',
      'hand_thumbsup', 'hand_thumbsup_fill', 'hand_thumbsdown', 'hand_thumbsdown_fill',
      'hand_point_up', 'hand_point_up_fill', 'hand_point_up_left', 'hand_point_up_left_fill',
      'hand_draw', 'hand_draw_fill', 'hand_tap', 'hand_tap_fill', 'hand_point_up_tap_fill_1',
      'rectangle_and_hand_point_up_left', 'rectangle_and_hand_point_up_left_fill',
      'onehand', 'fingerjoint_screenshot_slash', 'touchid'
    ]
  },
  {
    name: '服务维修',
    items: [
      'watch_rear_cover', 'pad_front_cover', 'pad_touchscreen_fault', 'rectangle_below_line_2',
      'smartscreen_front_cover', 'watch_frame', 'matebook_touchscreen_fault',
      'coins_badge_coin_fill', 'smartscreen_rear_cover', 'watch_case_base',
      'smartscreen_touchscreen_fault', 'matebook_front_cover', 'spanner_case_fill',
      'watch_front_cover', 'watch_touchscreen_fault', 'matebook_rear_cover', 'pad_rear_cover',
      'camera_cover', 'remote_services', 'engineer_fill', 'watchband_component',
      'diagnostic_analytics', 'engineer_badge_clock_fill', 'pad_headphone',
      'earphone_case_16640_lost', 'base_install', 'spanner_hand_fill',
      'spanner_hand_badge_checkmark_fill', 'computer_host_fill', 'earphone_case_16640_open',
      'printer_top', 'intelligent_lock_key_fill', 'door_service_fill', 'door_service'
    ]
  },
  {
    name: '遮阳帘',
    items: [
      'sunshade_rear_open', 'sunshade_rear_close', 'sunshade_right_open', 'sunshade_right_close',
      'sunshade_left_open', 'sunshade_left_close', 'sunblind_font_open', 'sunblind_font_close',
      'sunblind_font_pause_close', 'sunblind_font_pause_open', 'sunblind_rear_open',
      'sunblind_rear_close', 'sunblind_rear_pause_close', 'sunblind_rear_pause_open'
    ]
  },
  {
    name: '地图定位',
    items: [
      'location', 'location_fill', 'location_circle', 'location_circle_fill',
      'location_slash', 'location_slash_fill', 'location_north', 'location_north_fill',
      'location_north_circle', 'location_north_circle_fill', 'location_north_line',
      'location_north_line_fill', 'mappin', 'mappin_circle', 'mappin_circle_fill',
      'mappin_slash', 'mappin_and_ellipse', 'map', 'map_fill', 'map_circle', 'map_circle_fill',
      'globe', 'globe_americas', 'globe_europe_africa', 'globe_asia_australia', 'compass',
      'safari', 'safari_fill', 'pin', 'pin_fill', 'pin_circle', 'pin_slash', 'pin_vertical_fill'
    ]
  },
  {
    name: '购物支付',
    items: [
      'cart', 'cart_fill', 'cart_circle', 'cart_circle_fill', 'cart_badge_plus',
      'cart_fill_badge_plus', 'cart_badge_minus', 'cart_fill_badge_minus', 'bag', 'bag_fill',
      'bag_circle', 'bag_circle_fill', 'bag_badge_plus', 'bag_fill_badge_plus',
      'bag_badge_minus', 'bag_fill_badge_minus', 'basket', 'basket_fill', 'creditcard',
      'creditcard_fill', 'creditcard_circle', 'giftcard', 'giftcard_fill', 'gift',
      'gift_fill', 'gift_circle', 'gift_circle_fill', 'red_packets_fill', 'red_packets',
      'yuansign_moneybag', 'dollarsign_circle', 'dollarsign_circle_fill'
    ]
  },
  {
    name: '游戏娱乐',
    items: [
      'gamecontroller', 'gamecontroller_fill', 'puzzlepiece', 'puzzlepiece_fill',
      'puzzlepiece_extension', 'puzzlepiece_extension_fill', 'puzzle', 'puzzle_fill',
      'die_face_1', 'die_face_1_fill', 'die_face_2', 'die_face_2_fill', 'die_face_3',
      'die_face_3_fill', 'die_face_4', 'die_face_4_fill', 'die_face_5', 'die_face_5_fill',
      'die_face_6', 'die_face_6_fill', 'suit_heart', 'suit_heart_fill', 'suit_club',
      'suit_club_fill', 'suit_spade', 'suit_spade_fill', 'suit_diamond', 'suit_diamond_fill',
      'theatermasks', 'theatermasks_fill', 'film', 'film_fill', 'ticket', 'ticket_fill'
    ]
  },
  {
    name: '健康医疗',
    items: [
      'heart', 'heart_fill', 'heart_circle', 'heart_text_square', 'bolt_heart',
      'bolt_heart_fill', 'waveform_path_ecg', 'waveform_path_ecg_rectangle',
      'staroflife', 'staroflife_fill', 'staroflife_circle', 'staroflife_circle_fill',
      'cross', 'cross_fill', 'cross_circle', 'cross_circle_fill', 'pills', 'pills_fill',
      'pills_circle', 'pills_circle_fill', 'bandage', 'bandage_fill', 'syringe',
      'syringe_fill', 'facemask', 'facemask_fill', 'lungs', 'lungs_fill', 'brain',
      'brain_head_profile', 'ear', 'ear_fill', 'ear_badge_checkmark', 'figure_walk',
      'figure_walk_circle', 'figure_stand', 'sport', 'organ_donors'
    ]
  },
  {
    name: '动物植物',
    items: [
      'hare', 'hare_fill', 'tortoise', 'tortoise_fill', 'ant', 'ant_fill', 'ant_circle',
      'ant_circle_fill', 'ladybug', 'ladybug_fill', 'leaf', 'leaf_fill', 'leaf_circle',
      'leaf_circle_fill', 'leaf_arrow_triangle_circlepath', 'camera_macro', 'pawprint',
      'pawprint_fill', 'pawprint_circle', 'pawprint_circle_fill', 'fish', 'fish_fill',
      'fish_circle', 'fish_circle_fill', 'bird', 'bird_fill', 'bird_circle', 'bird_circle_fill'
    ]
  },
  {
    name: '文字排版',
    items: [
      'textformat', 'textformat_alt', 'textformat_size', 'bold', 'italic', 'underline',
      'strikethrough', 'text_justify', 'text_justify_left', 'text_justify_right',
      'text_alignleft', 'text_aligncenter', 'text_alignright', 'text_append', 'text_insert',
      'text_badge_plus', 'text_badge_minus', 'text_badge_checkmark', 'text_badge_xmark',
      'text_cursor', 'list_bullet', 'list_dash', 'list_number', 'list_star',
      'increase_indent', 'decrease_indent', 'text_quote', 'text_and_t', 'line_below_T',
      'character', 'character_book_closed', 'a_circle', 'a_circle_fill', 'a_square',
      'textformat_123', 'hash', 'number', 'number_circle', 'number_square'
    ]
  },
  {
    name: '窗口布局',
    items: [
      'rectangle_split_3x1', 'rectangle_split_2x1', 'rectangle_split_1x2', 'rectangle_3_group',
      'square_2_below_rectangle', 'layout_left_right', 'layout_up_down', 'sidebar_left',
      'sidebar_right', 'sidebar_leading', 'sidebar_trailing', 'macwindow', 'macwindow_badge_plus',
      'uiwindow_split_2x1', 'squares_below_rectangle', 'rectangle_on_rectangle',
      'rectangle_stack', 'square_stack', 'square_stack_3d', 'square_stack_3d_fill',
      'mosaic', 'mosaic_fill', 'thumbnails', 'templates', 'template_fill', 'template',
      'fullscreen', 'full_screen_fill', 'pip', 'pip_fill', 'pip_enter', 'pip_exit'
    ]
  },
  {
    name: '分享链接',
    items: [
      'square_and_arrow_up', 'square_and_arrow_up_fill', 'square_and_arrow_down',
      'square_and_arrow_down_fill', 'square_and_arrow_up_on_square',
      'square_and_arrow_down_on_square', 'link', 'link_circle', 'link_circle_fill',
      'link_badge_plus', 'personalhotspot', 'personalhotspot_circle', 'qrcode',
      'qrcode_viewfinder', 'barcode', 'barcode_viewfinder', 'airdrop', 'airplayaudio',
      'airplayvideo', 'airplayaudio_circle', 'airplayaudio_circle_fill', 'wechat',
      'square_link_square', 'picture_on_square', 'stickers'
    ]
  },
  {
    name: '更多符号1',
    items: [
      'sun_max_fill', 'sun_min_fill', 'sunrise', 'sunrise_fill', 'sunset', 'sunset_fill',
      'sun_dust', 'sun_dust_fill', 'sun_haze', 'sun_haze_fill', 'moon_stars', 'moon_stars_fill',
      'moon_zzz', 'moon_zzz_fill', 'sparkle', 'sparkle_magnifyingglass', 'star_leadinghalf_filled',
      'star_square', 'star_square_fill', 'rhombus_fill', 'circle_dashed', 'circle_dotted',
      'circle_inset_filled', 'circle_lefthalf_filled', 'circle_righthalf_filled',
      'circle_tophalf_filled', 'circle_bottomhalf_filled', 'smallcircle_filled_circle',
      'smallcircle_filled_circle_fill', 'smallcircle_circle', 'smallcircle_circle_fill',
      'target', 'scope', 'helm', 'clock_arrow_circlepath', 'clock_arrow_2_circlepath',
      'exclamationmark_arrow_circlepath', 'arrow_circlepath', 'arrow_2_squarepath',
      'arrow_triangle_branch', 'arrow_triangle_pull', 'arrow_triangle_turn_up_right_diamond',
      'arrow_triangle_turn_up_right_circle', 'arrow_triangle_capsulepath'
    ]
  },
  {
    name: '更多符号2',
    items: [
      'point_topleft_down_curvedto_point_bottomright_up', 'point_topleft_down_curvedto_point_filled_bottomright_up',
      'point_filled_topleft_down_curvedto_point_bottomright_up', 'cursorarrow', 'cursorarrow_rays',
      'cursorarrow_square', 'cursorarrow_and_square_on_square_dashed', 'cursorarrow_click',
      'cursorarrow_click_2', 'contextualmenu_and_cursorarrow', 'filemenu_and_cursorarrow',
      'filemenu_and_selection', 'dot_circle_and_hand_point_up_left_fill', 'dot_circle_and_cursorarrow',
      'move_3d', 'scale_3d', 'rotate_3d', 'rotate_left_fill', 'rotate_right_fill',
      'selection_pin_in_out', 'timeline_selection', 'cpu', 'cpu_fill', 'memorychip', 'memorychip_fill',
      'opticaldisc', 'opticaldisc_fill', 'tv', 'tv_fill', 'tv_circle', 'tv_circle_fill',
      'tv_slash', 'tv_slash_fill', 'tv_inset_filled', 'music_note_tv', 'music_note_tv_fill',
      'play_tv', 'play_tv_fill', 'photo_tv', 'tv_and_hifispeaker_fill', 'tv_and_mediabox'
    ]
  },
  {
    name: '更多符号3',
    items: [
      'guitars', 'guitars_fill', 'pianokeys', 'pianokeys_inverse', 'tuningfork', 'paintbrush',
      'paintbrush_fill', 'paintbrush_pointed', 'paintbrush_pointed_fill', 'bandage', 'bandage_fill',
      'ruler', 'ruler_fill', 'level', 'level_fill', 'wrench', 'wrench_fill', 'wrench_adjustable',
      'wrench_adjustable_fill', 'hammer', 'hammer_fill', 'hammer_circle', 'hammer_circle_fill',
      'screwdriver', 'screwdriver_fill', 'eyedropper', 'eyedropper_halffull', 'eyedropper_full',
      'wrench_and_screwdriver', 'wrench_and_screwdriver_fill', 'applescript', 'applescript_fill',
      'scroll', 'scroll_fill', 'stethoscope', 'stethoscope_circle', 'stethoscope_circle_fill',
      'printer', 'printer_fill', 'printer_filled_and_paper', 'printer_dotmatrix',
      'printer_dotmatrix_fill', 'printer_dotmatrix_filled_and_paper', 'scanner', 'scanner_fill'
    ]
  },
  {
    name: '更多符号4',
    items: [
      'faxmachine', 'faxmachine_fill', 'briefcase', 'briefcase_fill', 'briefcase_circle',
      'briefcase_circle_fill', 'case', 'case_fill', 'latch_2_case', 'latch_2_case_fill',
      'cross_case', 'cross_case_fill', 'cross_case_circle', 'cross_case_circle_fill',
      'suitcase', 'suitcase_fill', 'suitcase_cart', 'suitcase_cart_fill', 'suitcase_rolling',
      'suitcase_rolling_fill', 'theatermasks', 'theatermasks_fill', 'theatermasks_circle',
      'theatermasks_circle_fill', 'puzzlepiece', 'puzzlepiece_fill', 'puzzlepiece_extension',
      'puzzlepiece_extension_fill', 'house', 'house_fill', 'house_circle', 'house_circle_fill',
      'music_note_house', 'music_note_house_fill', 'building', 'building_fill', 'building_2',
      'building_2_fill', 'building_2_crop_circle', 'building_2_crop_circle_fill',
      'building_columns', 'building_columns_fill', 'building_columns_circle', 'building_columns_circle_fill'
    ]
  },
  {
    name: '更多符号5',
    items: [
      'lightswitch_on', 'lightswitch_on_fill', 'lightswitch_on_square', 'lightswitch_on_square_fill',
      'lightswitch_off', 'lightswitch_off_fill', 'lightswitch_off_square', 'lightswitch_off_square_fill',
      'fan', 'fan_fill', 'fan_badge_automatic', 'fan_badge_automatic_fill', 'fan_slash',
      'fan_slash_fill', 'fan_and_light_ceiling', 'fan_and_light_ceiling_fill', 'lamp_desk',
      'lamp_desk_fill', 'lamp_table', 'lamp_table_fill', 'lamp_floor', 'lamp_floor_fill',
      'lamp_ceiling', 'lamp_ceiling_fill', 'lamp_ceiling_inverse', 'light_recessed',
      'light_recessed_fill', 'light_recessed_inverse', 'light_recessed_3', 'light_recessed_3_fill',
      'light_recessed_3_inverse', 'chandelier', 'chandelier_fill', 'lightbulb_led',
      'lightbulb_led_fill', 'lightbulb_led_wide', 'lightbulb_led_wide_fill', 'light_panel',
      'light_panel_fill', 'light_strip_2', 'light_strip_2_fill', 'light_cylindrical_ceiling',
      'light_cylindrical_ceiling_fill', 'light_cylindrical_ceiling_inverse'
    ]
  },
  {
    name: '更多符号6',
    items: [
      'spigot', 'spigot_fill', 'shower', 'shower_fill', 'shower_sidejet', 'shower_sidejet_fill',
      'shower_handheld', 'shower_handheld_fill', 'bathtub', 'bathtub_fill', 'sink', 'sink_fill',
      'toilet', 'toilet_fill', 'toilet_circle', 'toilet_circle_fill', 'bed_double', 'bed_double_fill',
      'bed_double_circle', 'bed_double_circle_fill', 'sofa', 'sofa_fill', 'chair', 'chair_fill',
      'chair_lounge', 'chair_lounge_fill', 'cabinet', 'cabinet_fill', 'fireplace', 'fireplace_fill',
      'washer', 'washer_fill', 'dryer', 'dryer_fill', 'dishwasher', 'dishwasher_fill',
      'oven', 'oven_fill', 'stove', 'stove_fill', 'cooktop', 'cooktop_fill', 'microwave',
      'microwave_fill', 'refrigerator', 'refrigerator_fill', 'fridge', 'fridge_fill'
    ]
  },
  {
    name: '汽车详细',
    items: [
      'car_top_door_front_left_and_front_right_open', 'car_top_door_front_left_open_up',
      'car_top_door_front_left_open_down', 'car_top_door_front_right_open_up',
      'car_top_door_front_right_open_down', 'car_top_door_rear_left_open_up',
      'car_top_door_rear_left_open_down', 'car_top_door_rear_right_open_up',
      'car_top_door_rear_right_open_down', 'car_side_rear_radiowaves', 'car_window_ventilation',
      'smart_dock_display', 'smart_dock_hide', 'gauge_with_dots_needle_33percent',
      'headlight_low_beam_arrow_up_right', 'headlight_low_beam_arrow_down_right',
      'car_topwindow', 'car_topwindow_open', 'expand_rear_panel', 'flatten_rear_panel',
      'car_window_close_fill', 'figure_walk_wifi', 'screen_badge_power', 'rear_view_assist',
      'child_seat_carseat_right_installation_fixing', 'child_seat_carseat_right_circle',
      'arrowtriangle_up_and_down_window_right', 'steeringwheel_road_lane_dashed',
      'usb_badge_music', 'light_overhead', 'mirror_side_right', 'topwindow_system',
      'xmark_car_window_right', 'windshield_front_and_spray', 'windshield_rear_and_spray',
      'windshield_front_and_wiper_and_spray', 'windshield_rear_and_wiper_and_spray',
      'windshield_rear_and_wiper', 'optical_engine', 'ACC_cruise_control_reset',
      'windshield_wiper_rear', 'TJA_driver_assistance'
    ]
  },
  {
    name: '汽车高级',
    items: [
      'car_top_door_front_left_open_radiowaves_rear_left', 'car_top_rear_and_radiowaves_and_car_top_front',
      'phone_filled_badge_plus_waveform_2', 'mirror_side_right_and_heat_waves_auto_1',
      'car_side_rear_arrow_up_and_down', 'headlight_high_beam_auto', 'figure_seated_side_airbag_off_2',
      'carseat_right_backrest_down', 'car_top_radiowaves_left_and_right', 'arrow_double_clockwise',
      'escape_lightcar_ferry', 'ads_brakesignal_slash', 'mirror_side_left_and_heat_waves',
      'mirror_side_right_and_heat_waves', 'mirror_side_left_and_heat_waves_auto',
      'mirror_side_right_and_heat_waves_auto', 'height_adjustment', 'carseat_left_badge_checkmark',
      'dark_mode', 'sleeping_space', 'view_fill', 'curtain_switch', 'projection_switch',
      'back_desktop', 'angle_adjustment', 'rectangle_inset_filled_1', 'exclamationmark_warninglight',
      'light_overhead_front', 'light_overhead_rear', 'mini_fridge', 'light_overhead_left',
      'light_overhead_right', 'left_turn', 'right_turn', 'construction', 'main_lane_left',
      'T_junction', 'main_lane_right', 'crossroad', 'switch_lane_left', 'low_visibility',
      'road_narrow', 'obstacle', 'switch_lane_right', 'reduce_speed', 'auto_car_slow_speed'
    ]
  },
  {
    name: '导航停车',
    items: [
      'ddi_message', 'collection_panel', 'a_360_rotation', 'park_local_and_rectangle',
      'downstream_section', 'ra_reversing', 'car_straight_through', 'entrance_and_exit',
      'turn_around', 'outbound_straight', 'parking_side', 'outbound_side', 'upstream_section'
    ]
  },
  {
    name: '维修服务',
    items: [
      'international_insurance', 'data_line', 'hang_install', 'computer_host_fill',
      'power_component', 'doc_plaintext_2', 'base_component', 'move_install',
      'doc_text_badge_park', 'doc_text_badge_bolt', 'person_badge_bolt',
      'doc_text__badge_bolt_house', 'doc_text_badge_yuan', 'ranking_badge_bolt'
    ]
  },
  {
    name: '安全认证',
    items: [
      'rectangle_on_rectangle_fill_badge_arrow_right', 'text_character_square', 'ring', 'tone',
      'person_crop_circle_dashed', 'circle_circle_badge_checkmark_shield_filled',
      'dot_radiowaves_left_and_right_badge_person_filled', 'emergency_shelter'
    ]
  },
  {
    name: '特殊符号',
    items: [
      'artistic_virtualization', 'checkered_magnifyingglass', 'crop_video_fill', 'cut_in',
      'peripheral_device', 'dot', 'efficient_video_format', 'celiakeyboard_elevate',
      'fuzzy_input', 'input_mode', 'key_induction', 'resolution_video', 'main_auxiliary_screen_slash',
      'main_auxiliary_screen', 'arrowshape_3_triangle_path', 'watermark_font', 'harassment_interception',
      'vertically', 'triangleshape_left', 'circle_2', 'square_1', 'circle_on_circle_fill',
      'service_management', 'ad_rectangle_fill', 'adjustment', 'architecture', 'architecture_filled',
      'blur_bar', 'arrow_left_and_arrow_left', 'car_filled_below_drop_3', 'delete_left_fill',
      'dot_grid_1x2_circle', 'xmark_circle_video', 'fade', 'envelope_badge_adiowaves_fill',
      'ballpointpen_tip_crop_circle_fill', 'ballpointpen_tip_crop_circle', 'page_turning',
      'telephoto_macro', 'partial_screenshot', 'Interconnection_ic_multiscreen_collaboration',
      'merges', 'paperplan_right_2', 'pc_ic_tab_index', 'person_badge_envelope',
      'person_badge_nosign_fill', 'person_badge_nosign', 'scroll_horizontally', 'scroll_vertical',
      'space_enlarge', 'space_reduction', 'telescope_fill', 'video_badge_adiowaves_message_fill',
      'virtual_background', 'X_bottom', 'portrait_3_fill', 'portrait_fill', 'portrait'
    ]
  },
  {
    name: '数字字母',
    items: [
      '0_circle', '0_circle_fill', '0_square', '0_square_fill', '1_circle', '1_circle_fill',
      '1_square', '1_square_fill', '2_circle', '2_circle_fill', '2_square', '2_square_fill',
      '3_circle', '3_circle_fill', '3_square', '3_square_fill', '4_circle', '4_circle_fill',
      '4_square', '4_square_fill', '5_circle', '5_circle_fill', '5_square', '5_square_fill',
      '6_circle', '6_circle_fill', '6_square', '6_square_fill', '7_circle', '7_circle_fill',
      '7_square', '7_square_fill', '8_circle', '8_circle_fill', '8_square', '8_square_fill',
      '9_circle', '9_circle_fill', '9_square', '9_square_fill', '00_circle', '00_circle_fill',
      '00_square', '00_square_fill', '01_circle', '01_circle_fill', '01_square', '01_square_fill'
    ]
  },
  {
    name: '货币符号',
    items: [
      'dollarsign', 'dollarsign_circle', 'dollarsign_circle_fill', 'dollarsign_square',
      'dollarsign_square_fill', 'centsign', 'centsign_circle', 'centsign_circle_fill',
      'centsign_square', 'centsign_square_fill', 'yensign', 'yensign_circle', 'yensign_circle_fill',
      'yensign_square', 'yensign_square_fill', 'sterlingsign', 'sterlingsign_circle',
      'sterlingsign_circle_fill', 'sterlingsign_square', 'sterlingsign_square_fill',
      'francsign', 'francsign_circle', 'francsign_circle_fill', 'francsign_square',
      'francsign_square_fill', 'eurosign', 'eurosign_circle', 'eurosign_circle_fill',
      'eurosign_square', 'eurosign_square_fill', 'dongsign', 'dongsign_circle',
      'dongsign_circle_fill', 'dongsign_square', 'dongsign_square_fill', 'indianrupeesign',
      'indianrupeesign_circle', 'indianrupeesign_circle_fill', 'indianrupeesign_square',
      'indianrupeesign_square_fill', 'rupeesign', 'rupeesign_circle', 'rupeesign_circle_fill'
    ]
  },
  {
    name: '数学符号',
    items: [
      'plus_forwardslash_minus', 'minus_forwardslash_plus', 'plusminus', 'plusminus_circle',
      'plusminus_circle_fill', 'multiply', 'multiply_circle', 'multiply_circle_fill',
      'multiply_square', 'multiply_square_fill', 'divide', 'divide_circle', 'divide_circle_fill',
      'divide_square', 'divide_square_fill', 'equal', 'equal_circle', 'equal_circle_fill',
      'equal_square', 'equal_square_fill', 'lessthan', 'lessthan_circle', 'lessthan_circle_fill',
      'lessthan_square', 'lessthan_square_fill', 'greaterthan', 'greaterthan_circle',
      'greaterthan_circle_fill', 'greaterthan_square', 'greaterthan_square_fill',
      'number', 'number_circle', 'number_circle_fill', 'number_square', 'number_square_fill',
      'x_squareroot', 'percent', 'function', 'fx', 'sum', 'sigma'
    ]
  },
  {
    name: '箭头扩展',
    items: [
      'arrow_up_left_and_arrow_down_right', 'arrow_up_left_and_arrow_down_right_circle',
      'arrow_up_backward_and_arrow_down_forward', 'arrow_up_backward_and_arrow_down_forward_circle',
      'arrow_down_forward_and_arrow_up_backward', 'arrow_down_forward_and_arrow_up_backward_circle',
      'arrow_up_and_down_and_arrow_left_and_right', 'arrow_up_left_and_down_right_and_arrow_up_right_and_down_left',
      'arrow_left_and_right_righttriangle_left_righttriangle_right',
      'arrow_up_and_down_righttriangle_up_righttriangle_down', 'arrowtriangle_left_and_line_vertical_and_arrowtriangle_right',
      'arrowtriangle_right_and_line_vertical_and_arrowtriangle_left',
      'arrowtriangle_up_and_line_horizontal_and_arrowtriangle_down',
      'arrowtriangle_down_and_line_horizontal_and_arrowtriangle_up'
    ]
  },
  {
    name: '矩形扩展',
    items: [
      'rectangle_portrait_arrowtriangle_2_outward', 'rectangle_portrait_arrowtriangle_2_inward',
      'rectangle_arrowtriangle_2_outward', 'rectangle_arrowtriangle_2_inward',
      'rectangle_portrait_and_arrow_right', 'rectangle_portrait_and_arrow_right_fill',
      'rectangle_and_arrow_up_right_and_arrow_down_left', 'rectangle_and_arrow_up_right_and_arrow_down_left_slash',
      'rectangle_portrait_rotate', 'rectangle_landscape_rotate', 'rectangle_2_swap',
      'rectangle_portrait_on_rectangle_portrait', 'rectangle_portrait_on_rectangle_portrait_fill',
      'rectangle_portrait_on_rectangle_portrait_slash', 'rectangle_portrait_on_rectangle_portrait_slash_fill',
      'rectangle_portrait_on_rectangle_portrait_angled', 'rectangle_portrait_on_rectangle_portrait_angled_fill',
      'rectangle_portrait_split_2x1', 'rectangle_portrait_split_2x1_fill', 'rectangle_portrait_split_2x1_slash',
      'rectangle_portrait_split_2x1_slash_fill', 'tablecells', 'tablecells_fill', 'tablecells_badge_ellipsis',
      'tablecells_fill_badge_ellipsis'
    ]
  },
  {
    name: '方块扩展',
    items: [
      'square_2_stack_3d', 'square_2_stack_3d_top_filled', 'square_2_stack_3d_bottom_filled',
      'square_3_stack_3d', 'square_3_stack_3d_top_filled', 'square_3_stack_3d_middle_filled',
      'square_3_stack_3d_bottom_filled', 'square_3_layers_3d_down_right',
      'square_3_layers_3d_down_left', 'square_3_layers_3d_down_forward',
      'square_3_layers_3d_down_backward', 'cylinder', 'cylinder_fill', 'cylinder_split_1x2',
      'cylinder_split_1x2_fill', 'chart_bar_xaxis', 'chart_line_uptrend_xyaxis',
      'chart_line_uptrend_xyaxis_circle', 'chart_line_uptrend_xyaxis_circle_fill',
      'chart_xyaxis_line', 'point_3_connected_trianglepath_dotted', 'point_3_filled_connected_trianglepath_dotted'
    ]
  },
  {
    name: '书籍阅读',
    items: [
      'book', 'book_fill', 'book_circle', 'book_circle_fill', 'book_closed', 'book_closed_fill',
      'book_closed_circle', 'book_closed_circle_fill', 'books_vertical', 'books_vertical_fill',
      'books_vertical_circle', 'books_vertical_circle_fill', 'book_and_wrench',
      'menucard', 'menucard_fill', 'greetingcard', 'greetingcard_fill', 'magazine',
      'magazine_fill', 'newspaper', 'newspaper_fill', 'newspaper_circle', 'newspaper_circle_fill',
      'doc_text_image', 'doc_text_image_fill', 'bookmark', 'bookmark_fill', 'bookmark_circle',
      'bookmark_circle_fill', 'bookmark_slash', 'bookmark_slash_fill', 'rosette', 'graduationcap',
      'graduationcap_fill', 'graduationcap_circle', 'graduationcap_circle_fill'
    ]
  },
  {
    name: '运动健身',
    items: [
      'figure_walk', 'figure_walk_circle', 'figure_walk_circle_fill', 'figure_walk_diamond',
      'figure_walk_diamond_fill', 'figure_walk_arrival', 'figure_walk_departure', 'figure_walk_motion',
      'figure_stand', 'figure_stand_line_dotted_figure_stand', 'figure_wave', 'figure_wave_circle',
      'figure_wave_circle_fill', 'figure_run', 'figure_run_circle', 'figure_run_circle_fill',
      'figure_roll', 'figure_roll_runningpace', 'figure_american_football', 'figure_archery',
      'figure_australian_football', 'figure_badminton', 'figure_barre', 'figure_baseball',
      'figure_basketball', 'figure_bowling', 'figure_boxing', 'figure_climbing', 'figure_cooldown',
      'figure_core_training', 'figure_cricket', 'figure_cross_training', 'figure_curling',
      'figure_dance', 'figure_disc_sports', 'figure_elliptical', 'figure_equestrian_sports',
      'figure_fencing', 'figure_fishing', 'figure_flexibility', 'figure_golf', 'figure_gymnastics',
      'figure_hand_cycling', 'figure_handball', 'figure_highintensity_intervaltraining',
      'figure_hiking', 'figure_hockey', 'figure_hunting', 'figure_indoor_cycle'
    ]
  },
  {
    name: '运动扩展',
    items: [
      'figure_jumprope', 'figure_kickboxing', 'figure_lacrosse', 'figure_martial_arts',
      'figure_mind_and_body', 'figure_mixed_cardio', 'figure_open_water_swim', 'figure_outdoor_cycle',
      'figure_pickleball', 'figure_pilates', 'figure_play', 'figure_pool_swim', 'figure_racquetball',
      'figure_rolling', 'figure_rower', 'figure_rugby', 'figure_sailing', 'figure_skating',
      'figure_skiing_crosscountry', 'figure_skiing_downhill', 'figure_snowboarding',
      'figure_soccer', 'figure_socialdance', 'figure_softball', 'figure_squash', 'figure_stair_stepper',
      'figure_stairs', 'figure_step_training', 'figure_strengthtraining_functional',
      'figure_strengthtraining_traditional', 'figure_surfing', 'figure_table_tennis',
      'figure_taichi', 'figure_tennis', 'figure_track_and_field', 'figure_volleyball',
      'figure_water_fitness', 'figure_waterpolo', 'figure_wrestling', 'figure_yoga',
      'sportscourt', 'sportscourt_fill', 'sportscourt_circle', 'sportscourt_circle_fill'
    ]
  },
  {
    name: '交通工具',
    items: [
      'car_rear', 'car_rear_fill', 'car_rear_and_collision_and_car_front',
      'bolt_car', 'bolt_car_fill', 'bolt_car_circle', 'bolt_car_circle_fill',
      'car_2', 'car_2_fill', 'bus', 'bus_fill', 'bus_doubledecker', 'bus_doubledecker_fill',
      'tram', 'tram_fill', 'tram_circle', 'tram_circle_fill', 'tram_tunnel_fill',
      'cablecar', 'cablecar_fill', 'ferry', 'ferry_fill', 'car_ferry', 'car_ferry_fill',
      'train_side_front_car', 'train_side_middle_car', 'train_side_rear_car',
      'lightrail', 'lightrail_fill', 'scooter', 'figure_seated_seatbelt',
      'figure_seated_seatbelt_and_airbag_on', 'figure_seated_seatbelt_and_airbag_off',
      'figure_seated_side', 'figure_seated_side_air_upper', 'figure_seated_side_air_lower',
      'figure_seated_side_air_upper_and_lower', 'figure_seated_side_airbag_on',
      'figure_seated_side_airbag_on_and_heat', 'figure_seated_side_airbag_off',
      'figure_seated_side_automatic', 'figure_seated_side_windshield_front_and_heat_waves'
    ]
  },
  {
    name: '控制器',
    items: [
      'gamecontroller', 'gamecontroller_fill', 'l_joystick', 'l_joystick_fill',
      'r_joystick', 'r_joystick_fill', 'l_joystick_press_down', 'l_joystick_press_down_fill',
      'r_joystick_press_down', 'r_joystick_press_down_fill', 'l_joystick_tilt_left',
      'l_joystick_tilt_left_fill', 'l_joystick_tilt_right', 'l_joystick_tilt_right_fill',
      'l_joystick_tilt_up', 'l_joystick_tilt_up_fill', 'l_joystick_tilt_down',
      'l_joystick_tilt_down_fill', 'r_joystick_tilt_left', 'r_joystick_tilt_left_fill',
      'r_joystick_tilt_right', 'r_joystick_tilt_right_fill', 'r_joystick_tilt_up',
      'r_joystick_tilt_up_fill', 'r_joystick_tilt_down', 'r_joystick_tilt_down_fill',
      'dpad', 'dpad_fill', 'dpad_left_filled', 'dpad_up_filled', 'dpad_right_filled',
      'dpad_down_filled', 'circle_circle', 'circle_circle_fill', 'square_circle',
      'square_circle_fill', 'triangle_circle', 'triangle_circle_fill', 'xmark_circle_fill'
    ]
  },
  {
    name: '按钮标签',
    items: [
      'a_button_letterlike', 'b_button_letterlike', 'x_button_letterlike', 'y_button_letterlike',
      'lb_button_roundedbottom_horizontal', 'lb_button_roundedbottom_horizontal_fill',
      'rb_button_roundedbottom_horizontal', 'rb_button_roundedbottom_horizontal_fill',
      'lt_button_roundedtop_horizontal', 'lt_button_roundedtop_horizontal_fill',
      'rt_button_roundedtop_horizontal', 'rt_button_roundedtop_horizontal_fill',
      'zl_button_roundedtop_horizontal', 'zl_button_roundedtop_horizontal_fill',
      'zr_button_roundedtop_horizontal', 'zr_button_roundedtop_horizontal_fill',
      'l1_button_roundedbottom_horizontal', 'l1_button_roundedbottom_horizontal_fill',
      'r1_button_roundedbottom_horizontal', 'r1_button_roundedbottom_horizontal_fill',
      'l2_button_roundedtop_horizontal', 'l2_button_roundedtop_horizontal_fill',
      'r2_button_roundedtop_horizontal', 'r2_button_roundedtop_horizontal_fill'
    ]
  },
  {
    name: '键盘按键',
    items: [
      'keyboard', 'keyboard_fill', 'keyboard_badge_ellipsis', 'keyboard_badge_ellipsis_fill',
      'keyboard_badge_eye', 'keyboard_badge_eye_fill', 'keyboard_chevron_compact_down',
      'keyboard_chevron_compact_down_fill', 'keyboard_chevron_compact_left',
      'keyboard_chevron_compact_left_fill', 'keyboard_onehanded_left',
      'keyboard_onehanded_left_fill', 'keyboard_onehanded_right', 'keyboard_onehanded_right_fill',
      'globe', 'globe_badge_chevron_backward', 'character_cursor_ibeam', 'character_textbox',
      '123_rectangle', '123_rectangle_fill', 'character_bubble', 'character_bubble_fill',
      'text_bubble', 'text_bubble_fill', 'captions_bubble', 'captions_bubble_fill',
      'info_bubble', 'info_bubble_fill', 'questionmark_bubble', 'questionmark_bubble_fill',
      'exclamationmark_bubble', 'exclamationmark_bubble_fill', 'quote_bubble',
      'quote_bubble_fill', 'star_bubble', 'star_bubble_fill', 'character_book_closed',
      'character_book_closed_fill', 'text_book_closed', 'text_book_closed_fill'
    ]
  },
  {
    name: '苹果设备',
    items: [
      'applelogo', 'apple_logo', 'apple_terminal', 'apple_terminal_fill',
      'apple_terminal_on_rectangle', 'apple_terminal_on_rectangle_fill', 'applescript',
      'applescript_fill', 'swift', 'swiftdata', 'apple_meditate', 'apple_haptics_and_music_note',
      'appletv', 'appletv_fill', 'homepod_and_appletv', 'homepod_and_appletv_fill',
      'appletv_remote_gen1', 'appletv_remote_gen1_fill', 'appletv_remote_gen2',
      'appletv_remote_gen2_fill', 'appletv_remote_gen3', 'appletv_remote_gen3_fill',
      'appletv_remote_gen4', 'appletv_remote_gen4_fill', 'mediastick', 'cable_connector',
      'cable_connector_horizontal', 'magsafe_batterypack', 'magsafe_batterypack_fill',
      'magicmouse', 'magicmouse_fill', 'computermouse', 'computermouse_fill',
      'applewatch_and_arrow_forward', 'watchface_applewatch_case', 'applewatch_case_inset_filled'
    ]
  },
  {
    name: '智能家居',
    items: [
      'homekit', 'homepod', 'homepod_fill', 'homepod_2', 'homepod_2_fill', 'homepodmini',
      'homepodmini_fill', 'homepodmini_2', 'homepodmini_2_fill', 'homepod_and_homepodmini',
      'homepod_and_homepodmini_fill', 'hifispeaker_and_homepod', 'hifispeaker_and_homepod_fill',
      'hifispeaker_and_homepodmini', 'hifispeaker_and_homepodmini_fill', 'appletvremote_gen1',
      'appletvremote_gen1_fill', 'appletvremote_gen2', 'appletvremote_gen2_fill',
      'appletvremote_gen3', 'appletvremote_gen3_fill', 'appletvremote_gen4',
      'appletvremote_gen4_fill', 'remote_fill', 'av_remote', 'av_remote_fill',
      'dot_arrowtriangles_up_right_down_left_circle', 'sensor', 'sensor_fill',
      'sensor_tag_radiowaves_forward', 'sensor_tag_radiowaves_forward_fill',
      'light_beacon_max', 'light_beacon_max_fill', 'light_beacon_min', 'light_beacon_min_fill'
    ]
  },
  {
    name: '安全监控',
    items: [
      'video_doorbell', 'video_doorbell_fill', 'entry_lever_keypad', 'entry_lever_keypad_fill',
      'entry_lever_keypad_trianglebadge_exclamationmark', 'entry_lever_keypad_trianglebadge_exclamationmark_fill',
      'door_left_hand_open', 'door_left_hand_closed', 'door_right_hand_open', 'door_right_hand_closed',
      'door_sliding_left_hand_open', 'door_sliding_left_hand_closed', 'door_sliding_right_hand_open',
      'door_sliding_right_hand_closed', 'door_garage_open', 'door_garage_closed',
      'door_garage_open_trianglebadge_exclamationmark', 'door_garage_closed_trianglebadge_exclamationmark',
      'door_french_open', 'door_french_closed', 'window_vertical_open', 'window_vertical_closed',
      'window_horizontal', 'window_horizontal_closed', 'window_ceiling', 'window_ceiling_closed',
      'window_casement', 'window_casement_closed', 'window_awning', 'window_awning_closed',
      'blinds_vertical_open', 'blinds_vertical_closed', 'blinds_horizontal_open', 'blinds_horizontal_closed',
      'curtains_open', 'curtains_closed', 'roller_shade_open', 'roller_shade_closed'
    ]
  },
  {
    name: '空调温控',
    items: [
      'air_conditioner_horizontal', 'air_conditioner_horizontal_fill', 'air_conditioner_vertical',
      'air_conditioner_vertical_fill', 'air_purifier', 'air_purifier_fill', 'dehumidifier',
      'dehumidifier_fill', 'humidifier', 'humidifier_fill', 'humidifier_and_droplets',
      'humidifier_and_droplets_fill', 'heater_vertical', 'heater_vertical_fill',
      'cooktop', 'cooktop_fill', 'oven', 'oven_fill', 'stove', 'stove_fill',
      'microwave', 'microwave_fill', 'refrigerator', 'refrigerator_fill', 'fridge',
      'fridge_fill', 'washer', 'washer_fill', 'dryer', 'dryer_fill', 'dishwasher',
      'dishwasher_fill', 'sprinkler', 'sprinkler_fill', 'sprinkler_and_droplets',
      'sprinkler_and_droplets_fill', 'spigot', 'spigot_fill', 'pipe_and_drop', 'pipe_and_drop_fill'
    ]
  },
  {
    name: '电池充电',
    items: [
      'battery_100', 'battery_100_bolt', 'battery_75', 'battery_50', 'battery_25',
      'battery_0', 'battery_100_circle', 'battery_100_circle_fill', 'battery_75_circle',
      'battery_75_circle_fill', 'battery_50_circle', 'battery_50_circle_fill',
      'battery_25_circle', 'battery_25_circle_fill', 'battery_0_circle', 'battery_0_circle_fill',
      'minus_plus_batteryblock', 'minus_plus_batteryblock_fill', 'minus_plus_batteryblock_slash',
      'minus_plus_batteryblock_slash_fill', 'minus_plus_batteryblock_exclamationmark',
      'minus_plus_batteryblock_exclamationmark_fill', 'bolt_batteryblock', 'bolt_batteryblock_fill',
      'powerplug', 'powerplug_fill', 'powercord', 'powercord_fill', 'ev_plug_dc_combo_1',
      'ev_plug_dc_combo_1_fill', 'ev_plug_dc_combo_2', 'ev_plug_dc_combo_2_fill',
      'ev_plug_dc_chademo', 'ev_plug_dc_chademo_fill', 'ev_plug_dc_nacs', 'ev_plug_dc_nacs_fill',
      'ev_plug_ac_gb_t', 'ev_plug_ac_gb_t_fill', 'ev_plug_ac_type_1', 'ev_plug_ac_type_1_fill',
      'ev_plug_ac_type_2', 'ev_plug_ac_type_2_fill'
    ]
  },
  {
    name: '无障碍',
    items: [
      'accessibility', 'accessibility_fill', 'accessibility_badge_arrow_up_right',
      'figure_roll', 'figure_roll_runningpace', 'hearingdevice_ear', 'hearingdevice_ear_fill',
      'hearingdevice_and_signal_meter', 'hearingdevice_and_signal_meter_fill',
      'hand_raised', 'hand_raised_fill', 'hand_raised_circle', 'hand_raised_circle_fill',
      'hand_raised_slash', 'hand_raised_slash_fill', 'hand_raised_square', 'hand_raised_square_fill',
      'hand_thumbsup', 'hand_thumbsup_fill', 'hand_thumbsup_circle', 'hand_thumbsup_circle_fill',
      'hand_thumbsdown', 'hand_thumbsdown_fill', 'hand_thumbsdown_circle', 'hand_thumbsdown_circle_fill',
      'hand_point_up_left', 'hand_point_up_left_fill', 'hand_point_up', 'hand_point_up_fill',
      'hand_point_up_braille', 'hand_point_up_braille_fill', 'hand_point_down', 'hand_point_down_fill',
      'hand_point_left', 'hand_point_left_fill', 'hand_point_right', 'hand_point_right_fill',
      'hand_wave', 'hand_wave_fill', 'hands_clap', 'hands_clap_fill', 'hands_sparkles',
      'hands_sparkles_fill'
    ]
  },
  {
    name: '隐私安全',
    items: [
      'hand_raised_app', 'hand_raised_app_fill', 'eye_trianglebadge_exclamationmark',
      'eye_trianglebadge_exclamationmark_fill', 'eyes', 'eyes_inverse', 'eye_slash',
      'eye_slash_fill', 'eye_slash_circle', 'eye_slash_circle_fill', 'opticaldiscdrive',
      'opticaldiscdrive_fill', 'externaldrive', 'externaldrive_fill', 'externaldrive_badge_plus',
      'externaldrive_fill_badge_plus', 'externaldrive_badge_minus', 'externaldrive_fill_badge_minus',
      'externaldrive_badge_checkmark', 'externaldrive_fill_badge_checkmark', 'externaldrive_badge_xmark',
      'externaldrive_fill_badge_xmark', 'externaldrive_badge_person_crop', 'externaldrive_fill_badge_person_crop',
      'externaldrive_badge_icloud', 'externaldrive_fill_badge_icloud', 'externaldrive_badge_wifi',
      'externaldrive_fill_badge_wifi', 'externaldrive_badge_timemachine', 'externaldrive_fill_badge_timemachine',
      'externaldrive_connected_to_line_below', 'externaldrive_connected_to_line_below_fill',
      'archivebox', 'archivebox_fill', 'archivebox_circle', 'archivebox_circle_fill'
    ]
  },
  {
    name: '表情符号',
    items: [
      'face_smiling', 'face_smiling_fill', 'face_smiling_inverse', 'face_dashed',
      'face_dashed_fill', 'person_crop_circle_badge_questionmark', 'person_crop_circle_badge_questionmark_fill',
      'person_crop_circle_badge_exclamationmark', 'person_crop_circle_badge_exclamationmark_fill',
      'person_crop_circle_badge_moon', 'person_crop_circle_badge_moon_fill',
      'person_crop_circle_badge_clock', 'person_crop_circle_badge_clock_fill',
      'person_crop_artframe', 'person_crop_rectangle_stack', 'person_crop_rectangle_stack_fill',
      'person_crop_rectangle', 'person_crop_rectangle_fill', 'photo_artframe',
      'photo_artframe_circle', 'photo_artframe_circle_fill', 'rectangle_badge_person_crop',
      'rectangle_fill_badge_person_crop', 'person_text_rectangle', 'person_text_rectangle_fill'
    ]
  },
  {
    name: '徽章标记',
    items: [
      'app_badge', 'app_badge_fill', 'app_badge_checkmark', 'app_badge_checkmark_fill',
      'app_dashed', 'appclip', 'app_connected_to_app_below_fill', 'app_gift', 'app_gift_fill',
      'questionmark_app', 'questionmark_app_fill', 'questionmark_app_dashed', 'arrow_down_app',
      'arrow_down_app_fill', 'arrow_up_forward_app', 'arrow_up_forward_app_fill',
      'plus_app', 'plus_app_fill', 'minus_app', 'minus_app_fill', 'xmark_app', 'xmark_app_fill',
      'checkmark_seal', 'checkmark_seal_fill', 'xmark_seal', 'xmark_seal_fill',
      'exclamationmark_seal', 'exclamationmark_seal_fill', 'questionmark_seal',
      'questionmark_seal_fill', 'rosette', 'seal', 'seal_fill', 'crown', 'crown_fill'
    ]
  },
  {
    name: '波形图表',
    items: [
      'waveform', 'waveform_circle', 'waveform_circle_fill', 'waveform_path',
      'waveform_path_badge_plus', 'waveform_path_badge_minus', 'waveform_path_ecg',
      'waveform_path_ecg_rectangle', 'waveform_path_ecg_rectangle_fill',
      'waveform_badge_plus', 'waveform_badge_minus', 'waveform_badge_exclamationmark',
      'waveform_badge_magnifyingglass', 'waveform_and_magnifyingglass', 'waveform_and_mic',
      'point_topleft_down_curvedto_point_bottomright_up', 'point_topleft_down_curvedto_point_filled_bottomright_up',
      'point_filled_topleft_down_curvedto_point_bottomright_up', 'equal_circle', 'equal_circle_fill',
      'lessthan_circle', 'lessthan_circle_fill', 'greaterthan_circle', 'greaterthan_circle_fill',
      'plusminus_circle', 'plusminus_circle_fill', 'number_circle', 'number_circle_fill',
      'x_squareroot', 'percent', 'function', 'fx', 'sum', 'sigma'
    ]
  },
  {
    name: '其他符号',
    items: [
      'circle_and_arrow_down', 'circle_and_arrow_down_fill', 'line_below_arrowtriangle_up_circle_fill',
      'line_below_arrowtriangle_up_fill', 'a_4d_vibration', 'drop_bottomrighthalf_inset_filled_1',
      'square_and_square', 'skip_silence_fill', 'skip_silence', 'arrow_triangle_merge',
      'switch_majuscule_fill', 'switch_majuscule', 'control', 'more', 'sort',
      'screen_rotation', 'snapshot_fill', 'snapshot', 'mosaic', 'mosaic_fill',
      'pip', 'pip_fill', 'pip_enter', 'pip_exit', 'pip_swap', 'sidebar_left',
      'sidebar_right', 'sidebar_leading', 'sidebar_trailing', 'sidebar_squares_left',
      'sidebar_squares_right', 'sidebar_squares_leading', 'sidebar_squares_trailing',
      'macwindow', 'macwindow_badge_plus', 'dock_rectangle', 'dock_arrow_up_rectangle',
      'dock_arrow_down_rectangle', 'menubar_rectangle', 'menubar_dock_rectangle',
      'menubar_dock_rectangle_badge_record', 'menubar_arrow_up_rectangle',
      'menubar_arrow_down_rectangle'
    ]
  },
  {
    name: '时钟日历',
    items: [
      'doc_plaintext_fill_1', 'checkmark_circle_fill_1', 'alarm_fill_1', 'stopwatch_2',
      'worldclock_fill_2', 'timer_circle_fill', 'alarm_1', 'calendar_1', 'worldclock_fill_1',
      'stopwatch_fill_1', 'stopwatch_1'
    ]
  },
  {
    name: '界面布局',
    items: [
      'house_fill_1', 'person_crop_circle_fill_1', 'auditorium', 'ranking_fill',
      'slider_horizontal_2_1', 'indent_right', 'indentation_left', 'frame_overlay_rectify',
      'ranking', 'histogram', 'templates', 'thumbnails', 'layout_left_right', 'layout_up_down'
    ]
  },
  {
    name: '存储卡片',
    items: [
      'sdcard_fill', 'sdcard_1', 'simcard_fill', 'simcard_3', 'sd_card', 'TF_card', 'TF_card_1',
      'simcard_fill_1_and_simcard_fill_2', 'card', 'hidisk', 'hard_disk', 'memory_module'
    ]
  },
  {
    name: '操作符号',
    items: [
      'checkmark_square_fill', 'search_things', 'undo', 'redo', 'arrowshape_right_fill',
      'download', 'upload', 'download_1', 'square_and_arrow_down_1',
      'arrow_down_circle_badge_vip_circle_filled', 'arrow_left_arrow_right', 'arrow_uturn_down'
    ]
  },
  {
    name: '灯泡开关',
    items: [
      'lightbulb_1', 'onehand', 'organ_donors', 'lock_filled_arrow_counterclockwise',
      'warning', 'exclamationmark_shield_fill', 'lock_text_rectangle_portrait',
      'lock_badge_child', 'power_circle_fill'
    ]
  },
  {
    name: '相机拍摄',
    items: [
      'artistic_virtualization', 'camera_AF', 'camera_portrait_efferts', 'checkered_magnifyingglass',
      'crop_video_fill', 'cut_in', 'hdr', 'shutter_photo', 'shutter_photo_1', 'resolution_video',
      'time_lapse', 'video_speed', 'capture_smiles', 'photo_self_portrait', 'telephoto_macro',
      'partial_screenshot', 'movie_fill', 'movie_slash', 'movie'
    ]
  },
  {
    name: 'AI智能',
    items: [
      'intelligent', 'master_ai', 'AI_best_expression', 'AI_expand', 'AI_flower', 'AI_retouch',
      'AI_straighten', 'AI', 'AI_person', 'AI_shield', 'Celia', 'hi_vison', 'wand_and_stars_fill'
    ]
  },
  {
    name: '屏幕投射',
    items: [
      'main_auxiliary_screen_slash', 'main_auxiliary_screen', 'motion_stabilization_slash',
      'motion_stabilization', 'screen_share_fill', 'screen_share', 'multiscreen_collaboration',
      'multiscreen', 'wireless_projection_1', 'statusbar_cast', 'fullscreen', 'full_screen_fill'
    ]
  },
  {
    name: '网络通信',
    items: [
      'network_acceleration', 'mobiledata_and_cloud', 'signal_check', 'beidou_satellite_circle_fill',
      'phone_badge_satellite_fill', 'clipboard_sharing', 'envelope_badge_adiowaves_fill',
      'video_badge_adiowaves_message_fill', 'dot_radiowaves_left_and_right_badge_person_filled'
    ]
  },
  {
    name: '天气环境',
    items: [
      'frozen_rain', 'cloud_snow', 'icing_and_snow_road', 'icing_road', 'rainfall_circle_fill',
      'sunprotection', 'sunsetglow_fill', 'typhoon_fill', 'UV_sun_max', 'water_waves', 'wave_3_left'
    ]
  },
  {
    name: '人物安全',
    items: [
      'person_shield_1', 'plus_shield_badge_1', 'plus_shield_badge_2', 'guardian',
      'person_badge_checkmark', 'person_badge_envelope', 'person_badge_nosign_fill',
      'person_badge_nosign', 'person_filled_viewfinder', 'person_square_fill',
      'person_crop_circle_dashed', 'person_shield_badge_clock', 'anti_fraud_fill', 'security_shield'
    ]
  },
  {
    name: '消息通知',
    items: [
      'ellipsis_message_1', 'message_badge_checkmark_fill', 'message_badge_gearshape',
      'message_badge_plus_fill', 'line_message_fill', 'red_packets_fill', 'red_packets',
      'wechat', 'harassment_interception', 'ddi_message'
    ]
  },
  {
    name: '编辑工具2',
    items: [
      'highlighter_line', 'adjustment', 'blur_bar', 'fade', 'merges', 'stickers',
      'text_and_t', 'line_below_T', 'hash', 'X_bottom', 'doc_rectify', 'doc_text_badge_clock',
      'doc_text_badge_person', 'ballpointpen_tip_crop_circle_fill', 'ballpointpen_tip_crop_circle'
    ]
  },
  {
    name: '形状图形2',
    items: [
      'chevron_up_circle', 'circle_grid_2x2', 'dot', 'triangleshape_left', 'circle_2', 'square_1',
      'circle_on_circle_fill', 'rectangle_split_3x1', 'square_link_square', 'ad_rectangle_fill',
      'rectangle_3_group', 'square_2_below_rectangle', 'arrowshape_3_triangle_path',
      'square_stack_3d_fill', 'square_stack_3d', 'heart_square_stack_fill'
    ]
  },
  {
    name: '基础符号2',
    items: [
      'plus', 'plus_circle', 'plus_circle_fill', 'minus', 'minus_circle', 'minus_circle_fill',
      'xmark', 'xmark_circle', 'xmark_circle_fill', 'checkmark', 'checkmark_square',
      'checkmark_circle_fill', 'gearshape', 'gearshape_fill', 'sun_min'
    ]
  },
  {
    name: '键盘输入',
    items: [
      'celiakeyboard_elevate', 'fuzzy_input', 'input_mode', 'key_induction', 'puzzle',
      'puzzle_fill', 'peripheral_device', 'efficient_video_format', 'performance',
      'visibility', 'visual_accessibility', 'watermark_font', 'service_management',
      'template_fill', 'template', 'vertically', 'architecture', 'architecture_filled'
    ]
  },
  {
    name: '手势触控',
    items: [
      'hand_point_up_tap_fill_1', 'fingerjoint_screenshot_slash', 'hand_raised_hexagon_fill',
      'scroll_horizontally', 'scroll_vertical', 'space_enlarge', 'space_reduction',
      'page_turning', 'dot_grid_1x2_circle', 'xmark_circle_video'
    ]
  },
  {
    name: '麦克风音频',
    items: [
      'mic_circle_fill', 'mic_circle_filled', 'staroflife', 'moon_circle_fill',
      'moon_slash_circle', 'paperplan_right_2', 'pc_ic_tab_index', 'pin_vertical_fill',
      'phone_badge_video', 'picture_on_square', 'yuansign_moneybag'
    ]
  },
  {
    name: '肖像人物',
    items: [
      'portrait_3_fill', 'portrait_fill', 'portrait', 'basket', 'emergency_shelter',
      'circle_circle_badge_checkmark_shield_filled', 'compass', 'telescope_fill'
    ]
  },
  {
    name: '汽车车窗',
    items: [
      'car_window_fill', 'car_window_close', 'car_camera_recorder', 'car_side_front_open_down',
      'steering_wheel', 'display', 'powercord', 'phone_sos', 'headlight_fog', 'hazard_sign',
      'horn_fill', 'car_distance', 'sentry_mode', 'brake', 'auto_car_obstacle_avoidance',
      'auto_car_brake', 'car_parking_spot', 'elevator', 'stair'
    ]
  },
  {
    name: '设备维修',
    items: [
      'histogram_fill', 'general_rectangle_fill', 'sum_rectangle_fill', 'cltc_rectangle_fill',
      'wltc_rectangle_fill', 'watch_rear_cover', 'pad_front_cover', 'pad_touchscreen_fault',
      'rectangle_below_line_2', 'wrench_arrow_counterclockwise', 'smartscreen_front_cover',
      'watch_frame', 'matebook_touchscreen_fault', 'coins_badge_coin_fill', 'smartscreen_rear_cover',
      'watch_case_base', 'smartscreen_touchscreen_fault', 'matebook_front_cover',
      'spanner_case_fill', 'watch_front_cover', 'watch_touchscreen_fault', 'matebook_rear_cover',
      'pad_rear_cover', 'plus_bookmark'
    ]
  },
  {
    name: '维修服务',
    items: [
      'camera_cover', 'remote_services', 'engineer_fill', 'watchband_component',
      'diagnostic_analytics', 'engineer_badge_clock_fill', 'pad_headphone',
      'earphone_case_16640_lost', 'base_install', 'spanner_hand_fill',
      'wrench_and_screwdriver_fill', 'airplane_arrival', 'international_insurance',
      'data_line', 'hang_install', 'spanner_hand_badge_checkmark_fill', 'computer_host_fill',
      'earphone_case_16640_open', 'airplane_departure', 'printer_top',
      'wrench_rectangle_portrait', 'intelligent_lock_key_fill', 'door_service_fill',
      'power_component', 'doc_plaintext_2', 'base_component', 'door_service',
      'remote_control_component', 'move_install'
    ]
  },
  {
    name: '汽车服务',
    items: [
      'car_base', 'car_ac_1', 'car_badge_vs_fill', 'doc_text_badge_park',
      'doc_text_badge_bolt', 'person_badge_bolt', 'doc_text__badge_bolt_house',
      'doc_text_badge_yuan', 'ranking_badge_bolt'
    ]
  },
  {
    name: '遮阳帘',
    items: [
      'sunshade_rear_open', 'sunshade_rear_close', 'sunshade_right_open', 'sunshade_right_close',
      'sunshade_left_open', 'sunshade_left_close', 'sunblind_font_open', 'sunblind_font_close',
      'sunblind_font_pause_close', 'sunblind_font_pause_open', 'sunblind_rear_open',
      'sunblind_rear_close', 'sunblind_rear_pause_close', 'sunblind_rear_pause_open'
    ]
  },
  {
    name: '安全防护',
    items: [
      'rectangle_on_rectangle_fill_badge_arrow_right', 'text_character_square', 'ring', 'tone'
    ]
  },
  {
    name: '日历日期',
    items: [
      'calendar_01_a', 'calendar_02_a', 'calendar_03_a', 'calendar_04_a', 'calendar_05_a',
      'calendar_06_a', 'calendar_07_a', 'calendar_08_a', 'calendar_09_a', 'calendar_10_a',
      'calendar_11_a', 'calendar_12_a', 'calendar_13_a', 'calendar_14_a', 'calendar_15_a',
      'calendar_16_a', 'calendar_17_a', 'calendar_18_a', 'calendar_19_a', 'calendar_20_a',
      'calendar_21_a', 'calendar_22_a', 'calendar_23_a', 'calendar_24_a', 'calendar_25_a',
      'calendar_26_a', 'calendar_27_a', 'calendar_28_a', 'calendar_29_a', 'calendar_30_a',
      'calendar_31_a'
    ]
  },
  {
    name: '箭头方向2',
    items: [
      'chevron_up_L', 'chevron_down_L', 'square_fill', 'circle_fill', 'arrowtriangle_left_fill',
      'arrowtriangle_left', 'car_suv_fill', 'car_suv'
    ]
  },
  {
    name: '运动健身',
    items: [
      'sport', 'figure_walk', 'figure_walk_circle', 'figure_walk_circle_fill', 'figure_walk_motion',
      'figure_walk_arrival', 'figure_walk_departure', 'figure_stand', 'figure_stand_line_dotted_figure_stand',
      'figure_wave', 'figure_wave_circle', 'figure_wave_circle_fill', 'figure_run',
      'figure_run_circle', 'figure_run_circle_fill', 'figure_run_square_stack',
      'figure_run_square_stack_fill', 'figure_strengthtraining_traditional',
      'figure_strengthtraining_functional', 'figure_highintensity_intervaltraining',
      'figure_core_training', 'figure_cross_training', 'figure_cooldown', 'figure_flexibility',
      'figure_pilates', 'figure_yoga', 'figure_mind_and_body', 'figure_dance', 'figure_socialdance',
      'figure_step_training', 'figure_stairs', 'figure_stair_stepper', 'figure_elliptical',
      'figure_rower', 'figure_indoor_cycle', 'figure_outdoor_cycle', 'figure_roll'
    ]
  },
  {
    name: '球类运动',
    items: [
      'figure_american_football', 'figure_australian_football', 'figure_rugby',
      'figure_soccer', 'figure_basketball', 'figure_volleyball', 'figure_handball',
      'figure_baseball', 'figure_softball', 'figure_cricket', 'figure_lacrosse',
      'figure_field_hockey', 'figure_ice_hockey', 'figure_tennis', 'figure_badminton',
      'figure_racquetball', 'figure_squash', 'figure_table_tennis', 'figure_pickleball',
      'figure_golf', 'figure_disc_sports', 'figure_bowling', 'figure_pool_swim',
      'figure_open_water_swim', 'figure_surfing', 'figure_waterpolo', 'figure_skiing_downhill',
      'figure_skiing_crosscountry', 'figure_snowboarding', 'figure_skating', 'figure_curling'
    ]
  },
  {
    name: '格斗武术',
    items: [
      'figure_boxing', 'figure_kickboxing', 'figure_martial_arts', 'figure_taichi',
      'figure_wrestling', 'figure_fencing', 'figure_archery', 'figure_hunting',
      'figure_fishing', 'figure_climbing', 'figure_barre', 'figure_jumprope',
      'figure_play', 'figure_mixed_cardio', 'figure_hand_cycling', 'figure_wheelchair',
      'figure_equestrian_sports', 'figure_sailing', 'figure_water_fitness'
    ]
  },
  {
    name: '文档文件2',
    items: [
      'doc', 'doc_fill', 'doc_circle', 'doc_circle_fill', 'doc_badge_plus',
      'doc_fill_badge_plus', 'doc_badge_arrow_up', 'doc_badge_arrow_up_fill',
      'doc_badge_ellipsis', 'doc_badge_gearshape', 'doc_badge_gearshape_fill',
      'doc_badge_clock', 'doc_badge_clock_fill', 'arrow_up_doc', 'arrow_up_doc_fill',
      'arrow_down_doc', 'arrow_down_doc_fill', 'doc_on_doc', 'doc_on_doc_fill',
      'doc_on_clipboard', 'doc_on_clipboard_fill', 'clipboard', 'clipboard_fill',
      'list_clipboard', 'list_clipboard_fill', 'doc_richtext', 'doc_richtext_fill',
      'doc_append', 'doc_append_fill', 'doc_text_magnifyingglass', 'note', 'note_text',
      'note_text_badge_plus', 'calendar_badge_plus', 'calendar_badge_minus',
      'calendar_badge_clock', 'calendar_badge_exclamationmark', 'calendar_circle',
      'calendar_circle_fill'
    ]
  },
  {
    name: '书籍阅读',
    items: [
      'book', 'book_fill', 'book_circle', 'book_circle_fill', 'book_closed',
      'book_closed_fill', 'book_closed_circle', 'book_closed_circle_fill',
      'books_vertical', 'books_vertical_fill', 'books_vertical_circle',
      'books_vertical_circle_fill', 'book_and_wrench', 'book_and_wrench_fill',
      'bookmark', 'bookmark_fill', 'bookmark_circle', 'bookmark_circle_fill',
      'bookmark_slash', 'bookmark_slash_fill', 'rosette', 'graduationcap',
      'graduationcap_fill', 'graduationcap_circle', 'graduationcap_circle_fill',
      'pencil_and_ruler', 'pencil_and_ruler_fill', 'backpack', 'backpack_fill',
      'backpack_circle', 'backpack_circle_fill', 'paperclip', 'paperclip_circle',
      'paperclip_circle_fill', 'paperclip_badge_ellipsis', 'rectangle_and_paperclip',
      'rectangle_dashed_and_paperclip', 'link', 'link_circle', 'link_circle_fill',
      'link_badge_plus'
    ]
  },
  {
    name: '人物群组',
    items: [
      'person', 'person_fill', 'person_circle', 'person_circle_fill',
      'person_crop_circle', 'person_crop_circle_fill', 'person_crop_square',
      'person_crop_square_fill', 'person_badge_plus', 'person_fill_badge_plus',
      'person_badge_minus', 'person_fill_badge_minus', 'person_badge_clock',
      'person_badge_clock_fill', 'person_badge_key', 'person_badge_key_fill',
      'person_badge_shield_checkmark', 'person_badge_shield_checkmark_fill',
      'person_2', 'person_2_fill', 'person_2_circle', 'person_2_circle_fill',
      'person_2_crop_square_stack', 'person_2_crop_square_stack_fill',
      'person_3', 'person_3_fill', 'person_3_sequence', 'person_3_sequence_fill',
      'person_crop_circle_badge', 'person_crop_circle_fill_badge_plus',
      'person_crop_circle_badge_minus', 'person_crop_circle_fill_badge_minus',
      'person_crop_circle_badge_checkmark', 'person_crop_circle_fill_badge_checkmark',
      'person_crop_circle_badge_xmark', 'person_crop_circle_fill_badge_xmark'
    ]
  },
  {
    name: '地图导航',
    items: [
      'map', 'map_fill', 'map_circle', 'map_circle_fill', 'mappin', 'mappin_circle',
      'mappin_circle_fill', 'mappin_slash', 'mappin_slash_circle', 'mappin_slash_circle_fill',
      'mappin_and_ellipse', 'mappin_and_ellipse_circle', 'mappin_and_ellipse_circle_fill',
      'pin', 'pin_fill', 'pin_circle', 'pin_circle_fill', 'pin_slash', 'pin_slash_fill',
      'location', 'location_fill', 'location_circle', 'location_circle_fill',
      'location_slash', 'location_slash_fill', 'location_slash_circle',
      'location_slash_circle_fill', 'location_north', 'location_north_fill',
      'location_north_circle', 'location_north_circle_fill', 'location_north_line',
      'location_north_line_fill', 'location_square', 'location_square_fill',
      'location_magnifyingglass', 'location_viewfinder', 'sensor_tag_radiowaves_forward',
      'sensor_tag_radiowaves_forward_fill'
    ]
  },
  {
    name: '交通工具',
    items: [
      'car', 'car_fill', 'car_circle', 'car_circle_fill', 'bolt_car', 'bolt_car_fill',
      'bolt_car_circle', 'bolt_car_circle_fill', 'car_2', 'car_2_fill', 'bus', 'bus_fill',
      'bus_doubledecker', 'bus_doubledecker_fill', 'tram', 'tram_fill', 'tram_circle',
      'tram_circle_fill', 'tram_tunnel_fill', 'cablecar', 'cablecar_fill', 'ferry',
      'ferry_fill', 'airplane', 'airplane_circle', 'airplane_circle_fill',
      'airplane_departure', 'airplane_arrival', 'bicycle', 'bicycle_circle',
      'bicycle_circle_fill', 'scooter', 'fuelpump', 'fuelpump_fill', 'fuelpump_circle',
      'fuelpump_circle_fill', 'ev_charger', 'ev_charger_fill', 'ev_charger_slash',
      'ev_charger_slash_fill'
    ]
  },
  {
    name: '购物支付',
    items: [
      'cart', 'cart_fill', 'cart_circle', 'cart_circle_fill', 'cart_badge_plus',
      'cart_fill_badge_plus', 'cart_badge_minus', 'cart_fill_badge_minus',
      'cart_badge_questionmark', 'cart_fill_badge_questionmark', 'bag', 'bag_fill',
      'bag_circle', 'bag_circle_fill', 'bag_badge_plus', 'bag_fill_badge_plus',
      'bag_badge_minus', 'bag_fill_badge_minus', 'bag_badge_questionmark',
      'bag_fill_badge_questionmark', 'creditcard', 'creditcard_fill', 'creditcard_circle',
      'creditcard_circle_fill', 'creditcard_and_123', 'creditcard_trianglebadge_exclamationmark',
      'creditcard_trianglebadge_exclamationmark_fill', 'giftcard', 'giftcard_fill',
      'gift', 'gift_fill', 'gift_circle', 'gift_circle_fill', 'banknote',
      'banknote_fill', 'dollarsign', 'dollarsign_circle', 'dollarsign_circle_fill',
      'dollarsign_square', 'dollarsign_square_fill', 'yensign', 'yensign_circle',
      'yensign_circle_fill', 'yensign_square', 'yensign_square_fill'
    ]
  },
  {
    name: '医疗健康',
    items: [
      'heart', 'heart_fill', 'heart_circle', 'heart_circle_fill', 'heart_slash',
      'heart_slash_fill', 'heart_slash_circle', 'heart_slash_circle_fill',
      'heart_text_square', 'heart_text_square_fill', 'bolt_heart', 'bolt_heart_fill',
      'arrow_up_heart', 'arrow_up_heart_fill', 'arrow_down_heart', 'arrow_down_heart_fill',
      'cross', 'cross_fill', 'cross_circle', 'cross_circle_fill', 'cross_vial',
      'cross_vial_fill', 'pills', 'pills_fill', 'pills_circle', 'pills_circle_fill',
      'capsule', 'capsule_fill', 'bandage', 'bandage_fill', 'syringe', 'syringe_fill',
      'facemask', 'facemask_fill', 'lungs', 'lungs_fill', 'brain', 'brain_fill',
      'brain_head_profile', 'brain_head_profile_fill', 'ear', 'ear_fill',
      'ear_badge_checkmark', 'ear_badge_checkmark_fill', 'ear_trianglebadge_exclamationmark',
      'ear_trianglebadge_exclamationmark_fill', 'waveform_path_ecg', 'waveform_path_ecg_rectangle',
      'waveform_path_ecg_rectangle_fill', 'staroflife', 'staroflife_fill', 'staroflife_circle',
      'staroflife_circle_fill'
    ]
  },
  {
    name: '天气气象',
    items: [
      'sun_max', 'sun_max_fill', 'sun_min', 'sun_min_fill', 'sunrise', 'sunrise_fill',
      'sunset', 'sunset_fill', 'sun_dust', 'sun_dust_fill', 'sun_haze', 'sun_haze_fill',
      'moon', 'moon_fill', 'moon_circle', 'moon_circle_fill', 'moon_stars', 'moon_stars_fill',
      'moon_zzz', 'moon_zzz_fill', 'sparkle', 'sparkles', 'cloud', 'cloud_fill',
      'cloud_circle', 'cloud_circle_fill', 'cloud_drizzle', 'cloud_drizzle_fill',
      'cloud_rain', 'cloud_rain_fill', 'cloud_heavyrain', 'cloud_heavyrain_fill',
      'cloud_fog', 'cloud_fog_fill', 'cloud_hail', 'cloud_hail_fill', 'cloud_snow',
      'cloud_snow_fill', 'cloud_sleet', 'cloud_sleet_fill', 'cloud_bolt', 'cloud_bolt_fill',
      'cloud_bolt_rain', 'cloud_bolt_rain_fill', 'cloud_sun', 'cloud_sun_fill',
      'cloud_sun_rain', 'cloud_sun_rain_fill', 'cloud_sun_bolt', 'cloud_sun_bolt_fill',
      'cloud_moon', 'cloud_moon_fill', 'cloud_moon_rain', 'cloud_moon_rain_fill',
      'cloud_moon_bolt', 'cloud_moon_bolt_fill', 'smoke', 'smoke_fill', 'wind',
      'wind_circle', 'wind_circle_fill', 'wind_snow', 'wind_snow_circle', 'wind_snow_circle_fill',
      'snowflake', 'snowflake_circle', 'snowflake_circle_fill', 'tornado', 'tornado_circle',
      'tornado_circle_fill', 'tropicalstorm', 'tropicalstorm_circle', 'tropicalstorm_circle_fill',
      'hurricane', 'hurricane_circle', 'hurricane_circle_fill', 'thermometer_sun',
      'thermometer_sun_fill', 'thermometer_snowflake', 'thermometer_snowflake_fill',
      'thermometer_medium', 'thermometer_low', 'thermometer_high', 'thermometer_medium_slash',
      'humidity', 'humidity_fill', 'drop', 'drop_fill', 'drop_circle', 'drop_circle_fill',
      'drop_triangle', 'drop_triangle_fill', 'flame', 'flame_fill', 'flame_circle',
      'flame_circle_fill', 'bolt', 'bolt_fill', 'bolt_circle', 'bolt_circle_fill',
      'bolt_slash', 'bolt_slash_fill', 'bolt_slash_circle', 'bolt_slash_circle_fill',
      'bolt_horizontal', 'bolt_horizontal_fill', 'bolt_horizontal_circle',
      'bolt_horizontal_circle_fill'
    ]
  },
  {
    name: '时间日期',
    items: [
      'clock', 'clock_fill', 'clock_circle', 'clock_circle_fill', 'clock_badge_checkmark',
      'clock_badge_checkmark_fill', 'clock_badge_exclamationmark', 'clock_badge_exclamationmark_fill',
      'clock_badge_questionmark', 'clock_badge_questionmark_fill', 'clock_arrow_circlepath',
      'clock_arrow_2_circlepath', 'deskclock', 'deskclock_fill', 'alarm', 'alarm_fill',
      'alarm_waves_left_and_right', 'alarm_waves_left_and_right_fill', 'stopwatch',
      'stopwatch_fill', 'timer', 'timer_circle', 'timer_circle_fill', 'timer_square',
      'hourglass', 'hourglass_circle', 'hourglass_circle_fill', 'hourglass_badge_plus',
      'hourglass_bottomhalf_filled', 'hourglass_tophalf_filled', 'calendar', 'calendar_circle',
      'calendar_circle_fill', 'calendar_badge_plus', 'calendar_badge_minus',
      'calendar_badge_clock', 'calendar_badge_exclamationmark', 'calendar_day_timeline_left',
      'calendar_day_timeline_right', 'calendar_day_timeline_leading', 'calendar_day_timeline_trailing'
    ]
  },
  {
    name: '通信联系',
    items: [
      'phone', 'phone_fill', 'phone_circle', 'phone_circle_fill', 'phone_badge_plus',
      'phone_fill_badge_plus', 'phone_badge_checkmark', 'phone_fill_badge_checkmark',
      'phone_badge_waveform', 'phone_fill_badge_waveform', 'phone_connection',
      'phone_connection_fill', 'phone_down', 'phone_down_fill', 'phone_down_circle',
      'phone_down_circle_fill', 'phone_arrow_up_right', 'phone_arrow_up_right_fill',
      'phone_arrow_up_right_circle', 'phone_arrow_up_right_circle_fill',
      'phone_arrow_down_left', 'phone_arrow_down_left_fill', 'phone_arrow_right',
      'phone_arrow_right_fill', 'video', 'video_fill', 'video_circle', 'video_circle_fill',
      'video_slash', 'video_slash_fill', 'video_slash_circle', 'video_slash_circle_fill',
      'video_badge_plus', 'video_fill_badge_plus', 'video_badge_checkmark',
      'video_fill_badge_checkmark', 'video_badge_ellipsis', 'video_fill_badge_ellipsis',
      'video_bubble', 'video_bubble_fill', 'envelope', 'envelope_fill', 'envelope_circle',
      'envelope_circle_fill', 'envelope_open', 'envelope_open_fill', 'envelope_badge',
      'envelope_badge_fill', 'envelope_badge_shield_half_filled',
      'envelope_badge_shield_half_filled_fill', 'envelope_arrow_triangle_branch',
      'envelope_arrow_triangle_branch_fill', 'paperplane', 'paperplane_fill',
      'paperplane_circle', 'paperplane_circle_fill'
    ]
  },
  {
    name: '音乐音频',
    items: [
      'music_note', 'music_note_list', 'music_quarternote_3', 'music_mic',
      'music_mic_circle', 'music_mic_circle_fill', 'guitars', 'guitars_fill',
      'pianokeys', 'pianokeys_inverse', 'tuningfork', 'metronome', 'metronome_fill',
      'amplifier', 'die_face_1', 'die_face_1_fill', 'die_face_2', 'die_face_2_fill',
      'die_face_3', 'die_face_3_fill', 'die_face_4', 'die_face_4_fill', 'die_face_5',
      'die_face_5_fill', 'die_face_6', 'die_face_6_fill', 'speaker', 'speaker_fill',
      'speaker_circle', 'speaker_circle_fill', 'speaker_slash', 'speaker_slash_fill',
      'speaker_slash_circle', 'speaker_slash_circle_fill', 'speaker_wave_1',
      'speaker_wave_1_fill', 'speaker_wave_2', 'speaker_wave_2_fill', 'speaker_wave_3',
      'speaker_wave_3_fill', 'speaker_zzz', 'speaker_zzz_fill', 'speaker_badge_exclamationmark',
      'speaker_badge_exclamationmark_fill', 'speaker_plus', 'speaker_plus_fill',
      'speaker_minus', 'speaker_minus_fill', 'mic', 'mic_fill', 'mic_circle',
      'mic_circle_fill', 'mic_slash', 'mic_slash_fill', 'mic_slash_circle',
      'mic_slash_circle_fill', 'mic_badge_plus', 'mic_fill_badge_plus',
      'mic_badge_xmark', 'mic_fill_badge_xmark'
    ]
  },
  {
    name: '相机摄影',
    items: [
      'camera', 'camera_fill', 'camera_circle', 'camera_circle_fill', 'camera_shutter_button',
      'camera_shutter_button_fill', 'camera_badge_ellipsis', 'camera_fill_badge_ellipsis',
      'camera_on_rectangle', 'camera_on_rectangle_fill', 'camera_viewfinder',
      'camera_metering_center_weighted_average', 'camera_metering_center_weighted',
      'camera_metering_matrix', 'camera_metering_multispot', 'camera_metering_none',
      'camera_metering_partial', 'camera_metering_spot', 'camera_metering_unknown',
      'camera_aperture', 'camera_filters', 'camera_macro', 'camera_macro_circle',
      'camera_macro_circle_fill', 'photo', 'photo_fill', 'photo_circle', 'photo_circle_fill',
      'photo_on_rectangle', 'photo_on_rectangle_fill', 'photo_on_rectangle_angled',
      'photo_fill_on_rectangle_fill', 'photo_stack', 'photo_stack_fill', 'photo_badge_plus',
      'photo_fill_badge_plus', 'photo_badge_checkmark', 'photo_fill_badge_checkmark',
      'photo_badge_arrow_down', 'photo_fill_badge_arrow_down', 'rectangle_on_rectangle',
      'rectangle_fill_on_rectangle_fill', 'rectangle_on_rectangle_circle',
      'rectangle_on_rectangle_circle_fill', 'rectangle_on_rectangle_slash',
      'rectangle_on_rectangle_slash_fill', 'rectangle_on_rectangle_slash_circle',
      'rectangle_on_rectangle_slash_circle_fill'
    ]
  },
  {
    name: '文字编辑',
    items: [
      'textformat', 'textformat_size', 'textformat_size_smaller', 'textformat_size_larger',
      'textformat_alt', 'textformat_subscript', 'textformat_superscript', 'bold',
      'italic', 'underline', 'strikethrough', 'bold_italic_underline',
      'bold_italic_underline_strikethrough', 'textformat_abc', 'textformat_abc_dottedunderline',
      'textformat_123', 'textformat_12', 'list_bullet', 'list_bullet_circle',
      'list_bullet_circle_fill', 'list_bullet_indent', 'list_number', 'list_star',
      'list_triangle', 'list_dash', 'list_dash_header_rectangle', 'list_bullet_below_rectangle',
      'list_bullet_rectangle', 'list_bullet_rectangle_fill', 'list_bullet_rectangle_portrait',
      'list_bullet_rectangle_portrait_fill', 'list_clipboard', 'list_clipboard_fill',
      'checklist', 'checklist_unchecked', 'checklist_checked', 'increase_indent',
      'decrease_indent', 'increase_quotelevel', 'decrease_quotelevel', 'text_alignleft',
      'text_aligncenter', 'text_alignright', 'text_justify', 'text_justify_left',
      'text_justify_right', 'text_justify_leading', 'text_justify_trailing',
      'text_redaction', 'text_word_spacing', 'line_3_horizontal', 'line_3_horizontal_decrease',
      'line_3_horizontal_decrease_circle', 'line_3_horizontal_decrease_circle_fill',
      'line_3_horizontal_circle', 'line_3_horizontal_circle_fill'
    ]
  },
  {
    name: '网络连接',
    items: [
      'wifi', 'wifi_circle', 'wifi_circle_fill', 'wifi_slash', 'wifi_exclamationmark',
      'wifi_exclamationmark_circle', 'wifi_exclamationmark_circle_fill', 'wifi_router',
      'wifi_router_fill', 'antenna_radiowaves_left_and_right', 'antenna_radiowaves_left_and_right_circle',
      'antenna_radiowaves_left_and_right_circle_fill', 'antenna_radiowaves_left_and_right_slash',
      'dot_radiowaves_left_and_right', 'dot_radiowaves_right', 'dot_radiowaves_forward',
      'wave_3_left', 'wave_3_left_circle', 'wave_3_left_circle_fill', 'wave_3_right',
      'wave_3_right_circle', 'wave_3_right_circle_fill', 'wave_3_forward', 'wave_3_forward_circle',
      'wave_3_forward_circle_fill', 'wave_3_backward', 'wave_3_backward_circle',
      'wave_3_backward_circle_fill', 'cellularbars', 'chart_bar_fill', 'personalhotspot',
      'personalhotspot_circle', 'personalhotspot_circle_fill', 'network', 'network_slash',
      'globe', 'globe_americas', 'globe_americas_fill', 'globe_europe_africa',
      'globe_europe_africa_fill', 'globe_asia_australia', 'globe_asia_australia_fill',
      'globe_central_south_asia', 'globe_central_south_asia_fill'
    ]
  },
  {
    name: '安全锁定',
    items: [
      'lock', 'lock_fill', 'lock_circle', 'lock_circle_fill', 'lock_slash', 'lock_slash_fill',
      'lock_open', 'lock_open_fill', 'lock_rotation', 'lock_rotation_open', 'lock_shield',
      'lock_shield_fill', 'lock_square', 'lock_square_fill', 'lock_square_stack',
      'lock_square_stack_fill', 'lock_rectangle', 'lock_rectangle_fill', 'lock_rectangle_stack',
      'lock_rectangle_stack_fill', 'lock_rectangle_on_rectangle', 'lock_rectangle_on_rectangle_fill',
      'lock_badge_clock', 'lock_badge_clock_fill', 'lock_trianglebadge_exclamationmark',
      'lock_trianglebadge_exclamationmark_fill', 'lock_open_trianglebadge_exclamationmark',
      'lock_open_trianglebadge_exclamationmark_fill', 'key', 'key_fill', 'key_horizontal',
      'key_horizontal_fill', 'key_icloud', 'key_icloud_fill', 'key_viewfinder',
      'shield', 'shield_fill', 'shield_slash', 'shield_slash_fill', 'shield_lefthalf_filled',
      'shield_righthalf_filled', 'shield_lefthalf_filled_slash', 'shield_checkered',
      'checkmark_shield', 'checkmark_shield_fill', 'xmark_shield', 'xmark_shield_fill',
      'exclamationmark_shield', 'exclamationmark_shield_fill', 'questionmark_shield',
      'questionmark_shield_fill', 'plus_shield', 'plus_shield_fill', 'minus_shield', 'minus_shield_fill'
    ]
  },
  {
    name: '设置齿轮',
    items: [
      'gearshape', 'gearshape_fill', 'gearshape_circle', 'gearshape_circle_fill',
      'gearshape_2', 'gearshape_2_fill', 'gear', 'gear_badge_checkmark', 'gear_badge_xmark',
      'gear_badge_questionmark', 'gearshape_arrow_triangle_2_circlepath',
      'slider_horizontal_3', 'slider_horizontal_below_rectangle', 'slider_horizontal_below_square_filled_and_square',
      'slider_vertical_3', 'switch_2', 'togglepower', 'poweron', 'poweroff', 'power',
      'power_circle', 'power_circle_fill', 'power_dotted', 'wake', 'sleep', 'sleep_circle',
      'sleep_circle_fill', 'restart', 'restart_circle', 'restart_circle_fill'
    ]
  },
  {
    name: '文件夹',
    items: [
      'folder', 'folder_fill', 'folder_circle', 'folder_circle_fill', 'folder_badge_plus',
      'folder_fill_badge_plus', 'folder_badge_minus', 'folder_fill_badge_minus',
      'folder_badge_questionmark', 'folder_fill_badge_questionmark', 'folder_badge_gearshape',
      'folder_fill_badge_gearshape', 'folder_badge_person_crop', 'folder_fill_badge_person_crop',
      'plus_rectangle_on_folder', 'plus_rectangle_on_folder_fill', 'questionmark_folder',
      'questionmark_folder_fill', 'paperplane_fill', 'tray', 'tray_fill', 'tray_circle',
      'tray_circle_fill', 'tray_full', 'tray_full_fill', 'tray_and_arrow_up',
      'tray_and_arrow_up_fill', 'tray_and_arrow_down', 'tray_and_arrow_down_fill',
      'tray_2', 'tray_2_fill', 'externaldrive', 'externaldrive_fill', 'externaldrive_badge_plus',
      'externaldrive_fill_badge_plus', 'externaldrive_badge_minus', 'externaldrive_fill_badge_minus',
      'externaldrive_badge_checkmark', 'externaldrive_fill_badge_checkmark'
    ]
  },
  {
    name: '垃圾删除',
    items: [
      'trash', 'trash_fill', 'trash_circle', 'trash_circle_fill', 'trash_slash',
      'trash_slash_fill', 'trash_slash_circle', 'trash_slash_circle_fill',
      'trash_square', 'trash_square_fill', 'xmark_bin', 'xmark_bin_fill', 'xmark_bin_circle',
      'xmark_bin_circle_fill', 'arrow_up_bin', 'arrow_up_bin_fill', 'delete_left',
      'delete_left_fill', 'delete_right', 'delete_right_fill', 'delete_backward',
      'delete_backward_fill', 'delete_forward', 'delete_forward_fill', 'clear',
      'clear_fill', 'nosign', 'nosign_app', 'nosign_app_fill'
    ]
  },
  {
    name: '刷新同步',
    items: [
      'arrow_clockwise', 'arrow_clockwise_circle', 'arrow_clockwise_circle_fill',
      'arrow_counterclockwise', 'arrow_counterclockwise_circle', 'arrow_counterclockwise_circle_fill',
      'arrow_clockwise_icloud', 'arrow_clockwise_icloud_fill', 'arrow_counterclockwise_icloud',
      'arrow_counterclockwise_icloud_fill', 'arrow_triangle_2_circlepath',
      'arrow_triangle_2_circlepath_circle', 'arrow_triangle_2_circlepath_circle_fill',
      'arrow_triangle_2_circlepath_doc_on_clipboard', 'exclamationmark_arrow_circlepath',
      'arrow_2_squarepath', 'arrow_up_arrow_down', 'arrow_up_arrow_down_circle',
      'arrow_up_arrow_down_circle_fill', 'arrow_up_arrow_down_square', 'arrow_up_arrow_down_square_fill',
      'arrow_left_arrow_right', 'arrow_left_arrow_right_circle', 'arrow_left_arrow_right_circle_fill',
      'arrow_left_arrow_right_square', 'arrow_left_arrow_right_square_fill',
      'arrow_turn_down_left', 'arrow_turn_down_right', 'arrow_turn_up_left',
      'arrow_turn_up_right', 'arrow_turn_left_down', 'arrow_turn_left_up',
      'arrow_turn_right_down', 'arrow_turn_right_up', 'arrow_uturn_left',
      'arrow_uturn_left_circle', 'arrow_uturn_left_circle_fill', 'arrow_uturn_left_circle_badge_ellipsis',
      'arrow_uturn_left_square', 'arrow_uturn_left_square_fill', 'arrow_uturn_right',
      'arrow_uturn_right_circle', 'arrow_uturn_right_circle_fill', 'arrow_uturn_right_square',
      'arrow_uturn_right_square_fill', 'arrow_uturn_up', 'arrow_uturn_up_circle',
      'arrow_uturn_up_circle_fill', 'arrow_uturn_up_square', 'arrow_uturn_up_square_fill',
      'arrow_uturn_down', 'arrow_uturn_down_circle', 'arrow_uturn_down_circle_fill',
      'arrow_uturn_down_square', 'arrow_uturn_down_square_fill', 'arrow_uturn_forward',
      'arrow_uturn_forward_circle', 'arrow_uturn_forward_circle_fill', 'arrow_uturn_forward_square',
      'arrow_uturn_forward_square_fill', 'arrow_uturn_backward', 'arrow_uturn_backward_circle',
      'arrow_uturn_backward_circle_fill', 'arrow_uturn_backward_square', 'arrow_uturn_backward_square_fill'
    ]
  },
  {
    name: '放大缩小',
    items: [
      'magnifyingglass', 'magnifyingglass_circle', 'magnifyingglass_circle_fill',
      'plus_magnifyingglass', 'minus_magnifyingglass', 'arrow_up_left_and_arrow_down_right',
      'arrow_up_left_and_arrow_down_right_circle', 'arrow_up_left_and_arrow_down_right_circle_fill',
      'arrow_down_right_and_arrow_up_left', 'arrow_down_right_and_arrow_up_left_circle',
      'arrow_down_right_and_arrow_up_left_circle_fill', 'arrow_up_backward_and_arrow_down_forward',
      'arrow_up_backward_and_arrow_down_forward_circle', 'arrow_up_backward_and_arrow_down_forward_circle_fill',
      'arrow_down_forward_and_arrow_up_backward', 'arrow_down_forward_and_arrow_up_backward_circle',
      'arrow_down_forward_and_arrow_up_backward_circle_fill', 'loupe', 'text_magnifyingglass',
      'viewfinder', 'viewfinder_circle', 'viewfinder_circle_fill', 'viewfinder_rectangular',
      'crop', 'crop_rotate', 'aspectratio', 'aspectratio_fill'
    ]
  }
];

// 系统颜色列表
const SYSTEM_COLORS: string[] = [
  'ohos_id_color_foreground', 'ohos_id_color_foreground_dark',
  'ohos_id_color_background', 'ohos_id_color_background_dark',
  'ohos_id_color_emphasize', 'ohos_id_color_emphasize_dark',
  'ohos_id_color_warning', 'ohos_id_color_alert',
  'ohos_id_color_primary', 'ohos_id_color_secondary', 'ohos_id_color_tertiary',
  'ohos_id_color_text_primary', 'ohos_id_color_text_secondary',
  'ohos_id_color_component_normal', 'ohos_id_color_component_activated',
  'ohos_id_color_list_separator', 'ohos_id_color_click_effect', 'ohos_id_color_hover'
];

@ComponentV2
export struct SystemResourcePreviewPage {
  @Local themeState: ThemeState = { currentTheme: ThemeType.DARK };
  private themeManager: ThemeManager = ThemeManager.getInstance();
  pathStack: NavPathStack = new NavPathStack();
  
  @Local private selectedCategory: ResourceCategory = ResourceCategory.SYMBOL;
  @Local private selectedGroupIndex: number = 0;
  @Local private searchText: string = '';
  @Local private loadedGroups: number[] = [0]; // 按需加载的分组索引
  @Local private isSearching: boolean = false; // 是否正在搜索
  @Local private searchResults: string[] = []; // 搜索结果
  private themeChangeCallback: ((theme: ThemeType) => void) | null = null;
  
  aboutToAppear(): void {
    logger.info(TAG, '系统资源预览页面初始化');
    this.themeManager.getCurrentTheme().then((theme: ThemeType) => {
      this.themeState = { currentTheme: theme };
    });
    this.themeChangeCallback = (newTheme: ThemeType) => {
      logger.info(TAG, `主题切换到: ${newTheme}`);
      this.themeState = { currentTheme: newTheme };
    };
    this.themeManager.onThemeChange(this.themeChangeCallback);
  }
  
  aboutToDisappear(): void {
    // 移除主题监听器
    if (this.themeChangeCallback) {
      this.themeManager.offThemeChange(this.themeChangeCallback);
    }
  }
  
  /**
   * 加载更多分组
   */
  private loadMoreGroups(): void {
    const nextIndex = this.loadedGroups.length;
    if (nextIndex < SYMBOL_GROUPS.length) {
      this.loadedGroups = [...this.loadedGroups, nextIndex];
    }
  }
  
  /**
   * 获取当前分类的分组列表
   */
  private getCurrentGroups(): ResourceGroup[] {
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
  
  /**
   * 执行搜索
   */
  private performSearch(): void {
    if (!this.searchText || this.searchText.trim() === '') {
      this.isSearching = false;
      this.searchResults = [];
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
    logger.info(TAG, `搜索 "${keyword}" 找到 ${results.length} 个结果`);
  }
  
  /**
   * 清除搜索
   */
  private clearSearch(): void {
    this.searchText = '';
    this.isSearching = false;
    this.searchResults = [];
  }
  
  /**
   * 复制资源名称到剪贴板
   */
  private copyToClipboard(resourceType: string, resourceName: string): void {
    const fullName = `$r('sys.${resourceType}.${resourceName}')`;
    const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, fullName);
    const systemPasteboard = pasteboard.getSystemPasteboard();
    systemPasteboard.setData(pasteData).then(() => {
      promptAction.showToast({ message: `已复制: ${fullName}` });
      logger.info(TAG, `复制到剪贴板: ${fullName}`);
    }).catch((err: Error) => {
      logger.error(TAG, `复制失败: ${err.message}`);
      promptAction.showToast({ message: '复制失败' });
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
    Column() {
      // 搜索结果统计
      Row() {
        Text(`找到 ${this.searchResults.length} 个结果`)
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
            ForEach(this.searchResults, (itemName: string) => {
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
      Button(this.selectedCategory === ResourceCategory.SYMBOL ? '● Symbol' : '○ Symbol')
        .fontSize(14)
        .fontColor(this.selectedCategory === ResourceCategory.SYMBOL 
          ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
          : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.selectedCategory = ResourceCategory.SYMBOL;
          this.selectedGroupIndex = 0;
          this.loadedGroups = [0];
        })
      
      Button(this.selectedCategory === ResourceCategory.MEDIA ? '● Media' : '○ Media')
        .fontSize(14)
        .fontColor(this.selectedCategory === ResourceCategory.MEDIA 
          ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
          : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.selectedCategory = ResourceCategory.MEDIA;
          this.selectedGroupIndex = 0;
          this.loadedGroups = [0];
        })
      
      Button(this.selectedCategory === ResourceCategory.COLOR ? '● Color' : '○ Color')
        .fontSize(14)
        .fontColor(this.selectedCategory === ResourceCategory.COLOR 
          ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
          : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.selectedCategory = ResourceCategory.COLOR;
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
    Scroll() {
      Row({ space: 8 }) {
        ForEach(this.getCurrentGroups(), (group: ResourceGroup, index: number) => {
          Button(group.name)
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
              if (!this.loadedGroups.includes(index)) {
                this.loadedGroups = [...this.loadedGroups, index];
              }
            })
        })
      }
      .padding({ left: 16, right: 16 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .height(48)
  }
  
  /**
   * 构建Symbol图标网格
   */
  @Builder
  buildSymbolGrid() {
    Scroll() {
      Grid() {
        ForEach(this.getSymbolItems(), (itemName: string) => {
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
  }
  
  /**
   * 构建Media图标网格
   */
  @Builder
  buildMediaGrid() {
    Scroll() {
      Grid() {
        ForEach(this.getMediaItems(), (itemName: string) => {
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
    NavDestination() {
      Column() {
        // 搜索框
        this.buildSearchBar()
        
        // 分类选择器
        this.buildCategorySelector()
        
        // 根据是否在搜索状态显示不同内容
        if (this.isSearching) {
          // 搜索结果
          this.buildSearchResultGrid()
        } else {
          // 正常浏览模式
          if (this.selectedCategory === ResourceCategory.SYMBOL) {
            // 分组选择器
            this.buildGroupSelector()
            // Symbol图标网格
            this.buildSymbolGrid()
          } else if (this.selectedCategory === ResourceCategory.MEDIA) {
            // 分组选择器
            this.buildGroupSelector()
            // Media图标网格
            this.buildMediaGrid()
          } else {
            // 颜色列表
            this.buildColorList()
          }
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme))
    }
    .title('系统资源预览')
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
