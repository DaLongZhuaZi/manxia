/**
 * 设置键名常量（契约基础层）—— 由 entry SettingsManager 再导出。Stage 6 U6-Pilot-1。
 */

export class SettingKeys {
  // 高级功能
  static readonly ADVANCED_MODE_ENABLED = 'advanced_mode_enabled';
  static readonly SOURCE_FEATURES_ENABLED = 'source_features_enabled';
  static readonly SOURCE_SETTINGS_VISIBLE = 'source_settings_visible';
  static readonly SOURCE_DETAIL_TRANSLATION_TAG_ENABLED = 'source_detail_translation_tag_enabled';
  static readonly SOURCE_DETAIL_MULTI_WINDOW_ENABLED = 'source_detail_multi_window_enabled';
  static readonly ENABLE_LOG_FLOATING_WINDOW = 'enable_log_floating_window';
  static readonly PRELOAD_DEBUG_MODE = 'preload_debug_mode'; // 预加载调试模式：off/on/always
  static readonly GLOBAL_SEARCH_V2_ENABLED = 'global_search_v2_enabled';
  static readonly GLOBAL_SEARCH_DEBUG_METRICS_ENABLED = 'global_search_debug_metrics_enabled';
  static readonly GLOBAL_SEARCH_ONLINE_CACHE_ENABLED = 'global_search_online_cache_enabled';
  /** Global routing policy for all Legado V2 book-source workflows. */
  static readonly LEGADO_V2_EXECUTION_POLICY = 'legado_v2_execution_policy';
  
  // 生命周期监控
  static readonly LIFECYCLE_MONITOR_ENABLED = 'lifecycle_monitor_enabled'; // 启用生命周期监控
  static readonly LIFECYCLE_FLOATING_BALL_ENABLED = 'lifecycle_floating_ball_enabled'; // 启用生命周期悬浮球
  
  // 漫画全局阅读设置
  static readonly GLOBAL_READING_MODE = 'global_reading_mode';
  static readonly GLOBAL_READING_DIRECTION = 'global_reading_direction';
  static readonly GLOBAL_BRIGHTNESS = 'global_brightness';
  static readonly GLOBAL_KEEP_SCREEN_ON = 'global_keep_screen_on';
  static readonly GLOBAL_VOLUME_KEY_NAVIGATION = 'global_volume_key_navigation';
  static readonly GLOBAL_PAGE_TURN_ANIMATION = 'global_page_turn_animation';
  static readonly GLOBAL_MANGA_DOUBLE_PAGE_PORTRAIT_LAYOUT = 'global_manga_double_page_portrait_layout';
  static readonly GLOBAL_MANGA_DOUBLE_PAGE_VERTICAL_DIRECTION = 'global_manga_double_page_vertical_direction';
  static readonly GLOBAL_MANGA_PAGE_SPACING = 'global_manga_page_spacing';
  static readonly GLOBAL_MANGA_SHOW_PAGE_INFO = 'global_manga_show_page_info';
  static readonly GLOBAL_MANGA_SHOW_PAGE_INDICATOR = 'global_manga_show_page_indicator';
  static readonly GLOBAL_MANGA_FIT_MODE = 'global_manga_fit_mode';
  static readonly GLOBAL_MANGA_AUTO_PAGE_TURN_INTERVAL = 'global_manga_auto_page_turn_interval';
  static readonly GLOBAL_MANGA_SKIP_INTRO_PAGES = 'global_manga_skip_intro_pages';
  static readonly GLOBAL_MANGA_CURL_BACK_OPACITY = 'global_manga_curl_back_opacity';
  static readonly GLOBAL_MANGA_WEBTOON_LEFT_MARGIN = 'global_manga_webtoon_left_margin';
  static readonly GLOBAL_MANGA_WEBTOON_RIGHT_MARGIN = 'global_manga_webtoon_right_margin';
  static readonly GLOBAL_MANGA_WEBTOON_MARGIN_SYNC = 'global_manga_webtoon_margin_sync';
  static readonly MANGA_READER_INTERACTION_HINT_LAST_MODE = 'manga_reader_interaction_hint_last_mode';
  
  // 电子书全局阅读设置
  static readonly GLOBAL_EBOOK_FONT_SIZE = 'global_ebook_font_size';
  static readonly GLOBAL_EBOOK_FONT_FAMILY = 'global_ebook_font_family';
  static readonly GLOBAL_EBOOK_FONT_PATH = 'global_ebook_font_path';
  static readonly GLOBAL_EBOOK_FONT_WEIGHT = 'global_ebook_font_weight';
  static readonly GLOBAL_EBOOK_LINE_HEIGHT = 'global_ebook_line_height';
  static readonly GLOBAL_EBOOK_PAGE_MARGIN = 'global_ebook_page_margin';
  static readonly GLOBAL_EBOOK_PAGE_TOP_MARGIN = 'global_ebook_page_top_margin';
  static readonly GLOBAL_EBOOK_PAGE_BOTTOM_MARGIN = 'global_ebook_page_bottom_margin';
  static readonly GLOBAL_EBOOK_THEME = 'global_ebook_theme';
  static readonly GLOBAL_EBOOK_FOLLOW_SYSTEM_THEME = 'global_ebook_follow_system_theme';
  static readonly GLOBAL_EBOOK_PAGE_MODE = 'global_ebook_page_mode';
  static readonly GLOBAL_EBOOK_AUTO_SAVE = 'global_ebook_auto_save';
  static readonly GLOBAL_EBOOK_SAVE_INTERVAL = 'global_ebook_save_interval';
  static readonly GLOBAL_EBOOK_LETTER_SPACING = 'global_ebook_letter_spacing';
  static readonly GLOBAL_EBOOK_PARAGRAPH_SPACING = 'global_ebook_paragraph_spacing';
  static readonly GLOBAL_EBOOK_FIRST_LINE_INDENT = 'global_ebook_first_line_indent';
  static readonly GLOBAL_EBOOK_TEXT_ALIGNMENT = 'global_ebook_text_alignment';
  static readonly GLOBAL_EBOOK_PAGE_TURN_ANIMATION = 'global_ebook_page_turn_animation';
  static readonly GLOBAL_EBOOK_TAP_TO_TURN = 'global_ebook_tap_to_turn';
  static readonly GLOBAL_EBOOK_VOLUME_KEY_NAV = 'global_ebook_volume_key_nav';
  static readonly GLOBAL_EBOOK_KEEP_SCREEN_ON = 'global_ebook_keep_screen_on';
  static readonly GLOBAL_EBOOK_LOCK_DEVICE_ORIENTATION = 'global_ebook_lock_device_orientation';
  static readonly GLOBAL_EBOOK_SHOW_PAGE_NUMBER = 'global_ebook_show_page_number';
  static readonly GLOBAL_EBOOK_SHOW_PROGRESS = 'global_ebook_show_progress';
  static readonly GLOBAL_EBOOK_SHOW_TIME = 'global_ebook_show_time';
  static readonly GLOBAL_EBOOK_SHOW_BATTERY = 'global_ebook_show_battery';
  
  // 纯文本阅读器全局设置
  static readonly GLOBAL_TEXT_FONT_SIZE = 'global_text_font_size';
  static readonly GLOBAL_TEXT_FONT_FAMILY = 'global_text_font_family';  // 字体
  static readonly GLOBAL_TEXT_FONT_WEIGHT = 'global_text_font_weight';  // 字体粗细
  static readonly GLOBAL_TEXT_LINE_HEIGHT = 'global_text_line_height';
  static readonly GLOBAL_TEXT_PARAGRAPH_SPACING = 'global_text_paragraph_spacing';
  static readonly GLOBAL_TEXT_FIRST_LINE_INDENT = 'global_text_first_line_indent';
  static readonly GLOBAL_TEXT_LETTER_SPACING = 'global_text_letter_spacing';
  static readonly GLOBAL_TEXT_ALIGNMENT = 'global_text_alignment';
  static readonly GLOBAL_TEXT_PAGE_MARGIN = 'global_text_page_margin';
  static readonly GLOBAL_TEXT_BG_COLOR = 'global_text_bg_color';
  static readonly GLOBAL_TEXT_TEXT_COLOR = 'global_text_text_color';
  static readonly GLOBAL_TEXT_PAGE_TURN_ANIMATION = 'global_text_page_turn_animation';
  static readonly GLOBAL_TEXT_KEEP_SCREEN_ON = 'global_text_keep_screen_on';
  static readonly GLOBAL_TEXT_LOCK_DEVICE_ORIENTATION = 'global_text_lock_device_orientation';
  static readonly GLOBAL_TEXT_VOLUME_KEY_NAV = 'global_text_volume_key_nav';
  static readonly GLOBAL_TEXT_TAP_TO_TURN = 'global_text_tap_to_turn';
  static readonly TEXT_READER_INTERACTION_HINT_SEEN_PREFIX = 'text_reader_interaction_hint_seen_';
  static readonly GLOBAL_TEXT_BG_IMAGE_PATH = 'global_text_bg_image_path';
  static readonly GLOBAL_TEXT_BG_IMAGE_OPACITY = 'global_text_bg_image_opacity';
  static readonly GLOBAL_TEXT_USE_BG_IMAGE = 'global_text_use_bg_image';
  // 底部信息栏设置
  static readonly GLOBAL_TEXT_SHOW_TIME = 'global_text_show_time';
  static readonly GLOBAL_TEXT_SHOW_BATTERY = 'global_text_show_battery';
  static readonly GLOBAL_TEXT_SHOW_PAGE_NUMBER = 'global_text_show_page_number';
  static readonly GLOBAL_TEXT_SHOW_PROGRESS = 'global_text_show_progress';
  // 听书全局默认设置
  static readonly GLOBAL_TEXT_READ_ALOUD_ENABLED = 'global_text_read_aloud_enabled';
  static readonly GLOBAL_TEXT_READ_ALOUD_ENGINE = 'global_text_read_aloud_engine';
  static readonly GLOBAL_TEXT_READ_ALOUD_SPEED = 'global_text_read_aloud_speed';
  static readonly GLOBAL_TEXT_READ_ALOUD_PITCH = 'global_text_read_aloud_pitch';
  static readonly GLOBAL_TEXT_READ_ALOUD_VOLUME = 'global_text_read_aloud_volume';
  static readonly GLOBAL_TEXT_READ_ALOUD_CONTINUE_BG = 'global_text_read_aloud_continue_bg';
  static readonly GLOBAL_TEXT_READ_ALOUD_AUTO_PLAY_NEXT_CHAPTER = 'global_text_read_aloud_auto_play_next_chapter';
  static readonly GLOBAL_TEXT_READ_ALOUD_PAUSE_ON_MANUAL_PAGE_TURN = 'global_text_read_aloud_pause_on_manual_page_turn';
  static readonly GLOBAL_TEXT_READ_ALOUD_VOICE_LANGUAGE = 'global_text_read_aloud_voice_language';
  static readonly GLOBAL_TEXT_READ_ALOUD_VOICE_PERSON = 'global_text_read_aloud_voice_person';
  static readonly GLOBAL_TEXT_READ_ALOUD_VOICE_ONLINE = 'global_text_read_aloud_voice_online';
  static readonly GLOBAL_TEXT_READ_ALOUD_REMOTE_ENDPOINT = 'global_text_read_aloud_remote_endpoint';
  static readonly GLOBAL_TEXT_READ_ALOUD_REMOTE_API_PATH = 'global_text_read_aloud_remote_api_path';
  static readonly GLOBAL_TEXT_READ_ALOUD_REMOTE_API_KEY = 'global_text_read_aloud_remote_api_key';
  static readonly GLOBAL_TEXT_READ_ALOUD_REMOTE_MODEL = 'global_text_read_aloud_remote_model';
  static readonly GLOBAL_TEXT_READ_ALOUD_REMOTE_VOICE = 'global_text_read_aloud_remote_voice';
  static readonly GLOBAL_TEXT_READ_ALOUD_REMOTE_STYLE_PROMPT = 'global_text_read_aloud_remote_style_prompt';
  static readonly GLOBAL_TEXT_READ_ALOUD_REMOTE_AUDIO_FORMAT = 'global_text_read_aloud_remote_audio_format';
  static readonly GLOBAL_TEXT_READ_ALOUD_REMOTE_STREAM_ENABLED = 'global_text_read_aloud_remote_stream_enabled';
  static readonly GLOBAL_TEXT_READ_ALOUD_REMOTE_PREFETCH_SEGMENTS = 'global_text_read_aloud_remote_prefetch_segments';
  static readonly GLOBAL_TEXT_READ_ALOUD_REMOTE_CONNECT_TIMEOUT_MS = 'global_text_read_aloud_remote_connect_timeout_ms';
  static readonly GLOBAL_TEXT_READ_ALOUD_REMOTE_READ_TIMEOUT_MS = 'global_text_read_aloud_remote_read_timeout_ms';
  static readonly GLOBAL_TEXT_READ_ALOUD_REMOTE_MAX_INPUT_CHARS = 'global_text_read_aloud_remote_max_input_chars';
  static readonly GLOBAL_TEXT_READ_ALOUD_REMOTE_RESERVED_INPUT_CHARS = 'global_text_read_aloud_remote_reserved_input_chars';
  static readonly GLOBAL_TEXT_READ_ALOUD_REMOTE_MIN_CHUNK_CHARS = 'global_text_read_aloud_remote_min_chunk_chars';
  static readonly GLOBAL_TEXT_READ_ALOUD_REMOTE_TARGET_CHUNK_CHARS = 'global_text_read_aloud_remote_target_chunk_chars';
  static readonly GLOBAL_TEXT_READ_ALOUD_REMOTE_MAX_CHUNK_CHARS = 'global_text_read_aloud_remote_max_chunk_chars';
  static readonly GLOBAL_TEXT_READ_ALOUD_REMOTE_CACHE_AUDIO_FILES = 'global_text_read_aloud_remote_cache_audio_files';
  static readonly GLOBAL_TEXT_READ_ALOUD_REMOTE_AUTO_CONCAT_AUDIO = 'global_text_read_aloud_remote_auto_concat_audio';
  static readonly GLOBAL_TEXT_READ_ALOUD_REMOTE_CUSTOM_HEADERS_JSON = 'global_text_read_aloud_remote_custom_headers_json';
  static readonly GLOBAL_TEXT_READ_ALOUD_REMOTE_EXTRA_BODY_JSON = 'global_text_read_aloud_remote_extra_body_json';
  static readonly GLOBAL_TEXT_READ_ALOUD_REMOTE_ACTIVE_PRESET_ID = 'global_text_read_aloud_remote_active_preset_id';
  static readonly GLOBAL_TEXT_READ_ALOUD_REMOTE_PRESETS_JSON = 'global_text_read_aloud_remote_presets_json';
  static readonly GLOBAL_TEXT_READ_ALOUD_FAVORITE_VOICE_IDS = 'global_text_read_aloud_favorite_voice_ids';
  
  // 下载设置
  static readonly DOWNLOAD_WIFI_ONLY = 'download_wifi_only';
  static readonly MAX_CONCURRENT_DOWNLOADS = 'max_concurrent_downloads';

  // 统一详情页全局设置
  static readonly GLOBAL_UNIFIED_DETAIL_CHAPTER_SORT_ORDER = 'global_unified_detail_chapter_sort_order';
  
  // 通知设置
  static readonly ENABLE_DOWNLOAD_NOTIFICATIONS = 'enable_download_notifications';
  static readonly ENABLE_UPDATE_NOTIFICATIONS = 'enable_update_notifications';
  static readonly SHORTCUT_VISIBLE_IDS = 'shortcut_visible_ids'; // 快捷方式可见ID列表（JSON数组）
  
  // 其他设置
  static readonly AUTO_CHECK_UPDATES = 'auto_check_updates';
  static readonly CLEAR_CACHE_ON_EXIT = 'clear_cache_on_exit';
  static readonly FORCE_TABLET_MODE = 'force_tablet_mode';
  static readonly FORCE_LANDSCAPE_MODE = 'force_landscape_mode';
  
  // Download同步设置
  static readonly DOWNLOAD_SYNC_DIR_PATH = 'download_sync_dir_path';
  static readonly DOWNLOAD_SYNC_DIR_URI = 'download_sync_dir_uri';
  
  // 局域网传书设置
  static readonly LAN_TRANSFER_PORT = 'lan_transfer_port';
  static readonly LAN_TRANSFER_AUTO_STOP_MINUTES = 'lan_transfer_auto_stop_minutes';
  static readonly LAN_TRANSFER_MAX_FILE_SIZE_MB = 'lan_transfer_max_file_size_mb';
  static readonly LAN_TRANSFER_MAX_TOTAL_SIZE_MB = 'lan_transfer_max_total_size_mb';
  static readonly LAN_TRANSFER_ALLOW_BACKGROUND_TRANSFER = 'lan_transfer_allow_background_transfer';
  static readonly LAN_TRANSFER_WS_ENABLED = 'lan_transfer_ws_enabled';
   
  // 小说阅读器设置（使用TextReaderSettings）
  static readonly NOVEL_READER_SETTINGS = 'novel_reader_settings';
  // 小说搜索设置
  static readonly NOVEL_SEARCH_MAX_SOURCES = 'novel_search_max_sources';
  // 书源校验并发线程数（默认 10，范围 1-50）
  static readonly NOVEL_SOURCE_VALIDATION_CONCURRENCY = 'novel_source_validation_concurrency';
  
  // 底部导航栏自定义设置
  static readonly VISIBLE_TABS = 'visible_tabs'; // JSON数组，存储可见的标签索引
  static readonly BOTTOM_BAR_STYLE = 'bottom_bar_style'; // 底栏样式: 'custom' | 'hds'
  static readonly MAIN_MENU_TABLET_TOP_BAR_POSITION = 'main_menu_tablet_top_bar_position';
  static readonly MAIN_MENU_BOOK_SOURCE_PICKER_AUTO_SCROLL_ENABLED = 'main_menu_book_source_picker_auto_scroll_enabled';
  static readonly HOLDING_AWARENESS_ENABLED = 'holding_awareness_enabled';
  static readonly HOLDING_AWARENESS_MAIN_MENU_FLOATING_CONTROLS_ENABLED = 'holding_awareness_main_menu_floating_controls_enabled';
  static readonly HOLDING_AWARENESS_MAIN_MENU_SEARCH_BUTTON_ENABLED = 'holding_awareness_main_menu_search_button_enabled';
  static readonly HOLDING_AWARENESS_MAIN_MENU_PRIVACY_EXIT_BUTTON_ENABLED = 'holding_awareness_main_menu_privacy_exit_button_enabled';
  static readonly HOLDING_AWARENESS_MAIN_MENU_SHELF_PREVIEW_ENABLED = 'holding_awareness_main_menu_shelf_preview_enabled';
  static readonly HOLDING_AWARENESS_DETAIL_LANDSCAPE_READ_ACTIONS_ENABLED = 'holding_awareness_detail_landscape_read_actions_enabled';
  static readonly HOLDING_AWARENESS_READ_ALOUD_FLOATING_BALL_ENABLED = 'holding_awareness_read_aloud_floating_ball_enabled';
  static readonly HOLDING_AWARENESS_TASK_FLOATING_BALL_ENABLED = 'holding_awareness_task_floating_ball_enabled';
  static readonly HOLDING_AWARENESS_MANGA_WEBTOON_QUICK_NAVIGATION_ENABLED = 'holding_awareness_manga_webtoon_quick_navigation_enabled';
  static readonly HOLDING_AWARENESS_TEXT_HIGHLIGHT_THOUGHT_POPUP_ENABLED = 'holding_awareness_text_highlight_thought_popup_enabled';
  static readonly LIBRARY_DEFAULT_GRID_COLUMNS = 'library_default_grid_columns';
  static readonly LIBRARY_SHELF_GRID_COLUMNS = 'library_shelf_grid_columns';
  static readonly LIBRARY_HIDE_WOOD_SHELF_TEXTURE = 'library_hide_wood_shelf_texture';
  static readonly LIBRARY_SHELF_TOOLBAR_PLACEMENT = 'library_shelf_toolbar_placement';
  static readonly LIBRARY_GRID_AUTHOR_DISPLAY_MODE = 'library_grid_author_display_mode';
  static readonly LIBRARY_GRID_PROGRESS_DISPLAY_MODE = 'library_grid_progress_display_mode';
  static readonly LIBRARY_GRID_DIRECT_COVER_ENABLED = 'library_grid_direct_cover_enabled';
  static readonly LIBRARY_GRID_COVER_TYPE_MARKER_ENABLED = 'library_grid_cover_type_marker_enabled';
  static readonly LIBRARY_SHELF_DETAIL_DIRECT_COVER_ENABLED = 'library_shelf_detail_direct_cover_enabled';
  static readonly LIBRARY_GRID_START_FROM_TOP = 'library_grid_start_from_top'; // 默认视图从顶部开始显示（默认关闭）
  
  // 内容过滤设置
  static readonly SFW_MODE_ENABLED = 'sfw_mode_enabled'; // 启用SFW模式（隐藏NSFW内容）
  static readonly NSFW_SCOPE_IMAGE_SOURCE_ENABLED = 'nsfw_scope_image_source_enabled'; // 图源NSFW作用域（默认true）
  static readonly NSFW_SCOPE_BOOK_SOURCE_ENABLED = 'nsfw_scope_book_source_enabled'; // 书源NSFW作用域（默认true）
  
  // 全局UserAgent设置
  static readonly GLOBAL_USER_AGENT = 'global_user_agent'; // 全局自定义User-Agent
  static readonly GLOBAL_USER_AGENT_ENABLED = 'global_user_agent_enabled'; // 是否启用全局自定义UA
  
  // 隐私保护设置
  static readonly BACKGROUND_BLUR_ENABLED = 'background_blur_enabled'; // 后台任务界面模糊遮罩
  static readonly BACKGROUND_BLUR_BG_TYPE = 'background_blur_bg_type'; // 后台遮罩背景类型: 'solid' | 'custom'
  static readonly BACKGROUND_BLUR_BG_IMAGE = 'background_blur_bg_image'; // 自定义背景图片路径
  static readonly BACKGROUND_BLUR_ICON_TYPE = 'background_blur_icon_type'; // 图标类型: 'shield' | 'logo'
  static readonly PRIVACY_LIBRARY_SKIP_BIOMETRIC_AUTH = 'privacy_library_skip_biometric_auth'; // 进入隐私书库时跳过指纹识别，直接走密码验证
  
  // 动画设置
  static readonly ANIMATION_BOOK_OPEN_ENABLED = 'animation_book_open_enabled'; // 书籍打开动画开关
  static readonly ANIMATION_BOOK_CLOSE_ENABLED = 'animation_book_close_enabled'; // 书籍关闭动画开关
  static readonly ANIMATION_BOOK_OPEN_DURATION = 'animation_book_open_duration'; // 书籍打开动画时长(ms)
  static readonly ANIMATION_BOOK_CLOSE_DURATION = 'animation_book_close_duration'; // 书籍关闭动画时长(ms)
  static readonly ANIMATION_MAIN_PAGE_BOTTOM_BAR_ENABLED = 'animation_main_page_bottom_bar_enabled'; // 主页面底栏动画开关

  // 视觉效果与材质设置
  static readonly VISUAL_EFFECTS_MATERIAL_MODE = 'visual_effects_material_mode'; // 材质等级策略: adaptive | manual
  static readonly VISUAL_EFFECTS_MANUAL_MATERIAL_LEVEL = 'visual_effects_manual_material_level'; // 手动材质等级（MaterialLevel枚举值）
  static readonly VISUAL_EFFECTS_SUPPORTED_MATERIAL_TYPES = 'visual_effects_supported_material_types'; // 最近一次检测到的材质类型列表（CSV）
  static readonly VISUAL_EFFECTS_CAPABILITY_LAST_CHECKED_AT = 'visual_effects_capability_last_checked_at'; // 最近一次检测时间戳
  static readonly VISUAL_EFFECTS_CAPABILITY_DETECT_ERROR = 'visual_effects_capability_detect_error'; // 最近一次检测错误信息
  
  // 日志设置
  static readonly LOG_OUTPUT_LEVEL = 'log_output_level'; // hilog日志输出等级: 0=关闭, 1=DEBUG, 2=INFO, 3=WARN, 4=ERROR, 5=FATAL
  
  // 详情页推荐功能
  static readonly RECOMMENDATION_ENABLED = 'recommendation_enabled'; // 统一详情页相关推荐功能开关（默认开启）
  static readonly SHELF_CONTENT_ENABLED = 'shelf_content_enabled'; // 统一详情页同书架内容功能开关（默认开启）
  static readonly MAIN_MENU_LIBRARY_COVER_OPEN_READER_ENABLED = 'main_menu_library_cover_open_reader_enabled'; // 主页面书库封面点击直接阅读开关（默认开启）
  static readonly READER_PAGE_MULTITON_ENABLED = 'reader_page_multiton_enabled'; // 阅读器页面多开开关（默认开启）
  static readonly READER_KIT_ENABLED = 'reader_kit_enabled'; // ReaderKit 能力开关（默认开启）
  static readonly EPUB_WEBVIEW_RENDERER_ENABLED = 'epub_webview_renderer_enabled'; // 文字型 EPUB 使用 WebView 渲染引擎（默认关闭）
  static readonly NON_MAIN_PAGE_GLOBAL_BACKGROUND_ENABLED = 'non_main_page_global_background_enabled'; // 全局自定义背景开关（默认开启）

  // 内容重复检测设置
  static readonly DUPLICATE_DETECTION_ENABLED = 'duplicate_detection_enabled'; // 启用重复检测（默认关闭）
  static readonly DUPLICATE_DETECTION_THRESHOLD = 'duplicate_detection_threshold'; // 相似度阈值 0.0~1.0（默认0.5）
  static readonly DUPLICATE_DETECTION_SCOPE = 'duplicate_detection_scope'; // 检测范围: same_type | all_types
  static readonly DUPLICATE_DETECTION_TITLE_WEIGHT = 'duplicate_detection_title_weight'; // 标题权重 0.1~0.9（默认0.7）
}
