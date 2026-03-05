/**
 * 文本阅读器数据模型定义
 * 支持多种阅读模式、翻页动画、自定义背景和文字样式
 */

/**
 * 文本阅读模式枚举
 */
export enum TextReadingMode {
  SCROLL = 'SCROLL',           // 连续滚动模式
  PAGE = 'PAGE',               // 翻页模式
  AUTO_SCROLL = 'AUTO_SCROLL', // 自动滚动模式
  DUAL_PAGE = 'DUAL_PAGE'      // 双页模式（横屏左右双页）
}

/**
 * 文本阅读方向枚举
 */
export enum TextReadingDirection {
  HORIZONTAL = 'HORIZONTAL',   // 水平翻页（左右）
  VERTICAL = 'VERTICAL'        // 垂直翻页（上下）
}

/**
 * 文本翻页动画类型枚举
 */
export enum TextPageTurnAnimation {
  NONE = 'NONE',               // 无动画
  SLIDE = 'SLIDE',             // 滑动
  CURL = 'CURL',               // 拟真卷曲
  FADE = 'FADE'                // 淡入淡出
}

/**
 * 文字对齐方式枚举
 */
export enum TextAlignment {
  LEFT = 'LEFT',               // 左对齐
  CENTER = 'CENTER',           // 居中对齐
  RIGHT = 'RIGHT',             // 右对齐
  JUSTIFY = 'JUSTIFY'          // 两端对齐
}

/**
 * 背景类型枚举
 */
export enum BackgroundType {
  COLOR = 'COLOR',             // 纯色背景
  IMAGE = 'IMAGE',             // 图片背景
  GRADIENT = 'GRADIENT'        // 渐变背景
}

/**
 * 预设背景颜色
 */
export interface PresetBackground {
  /** 背景名称 */
  name: string;
  /** 背景颜色 */
  backgroundColor: string;
  /** 文字颜色 */
  textColor: string;
  /** 预览颜色（用于选择器） */
  previewColor: string;
}

/**
 * 预设背景列表
 */
export const PRESET_BACKGROUNDS: PresetBackground[] = [
  { name: '经典白', backgroundColor: '#FFFFFF', textColor: '#333333', previewColor: '#FFFFFF' },
  { name: '护眼黄', backgroundColor: '#F5F0E1', textColor: '#5D4037', previewColor: '#F5F0E1' },
  { name: '淡绿', backgroundColor: '#E8F5E9', textColor: '#2E7D32', previewColor: '#E8F5E9' },
  { name: '浅蓝', backgroundColor: '#E3F2FD', textColor: '#1565C0', previewColor: '#E3F2FD' },
  { name: '暖粉', backgroundColor: '#FCE4EC', textColor: '#C2185B', previewColor: '#FCE4EC' },
  { name: '深色', backgroundColor: '#1E1E1E', textColor: '#D4D4D4', previewColor: '#1E1E1E' },
  { name: '墨绿', backgroundColor: '#1B3B2F', textColor: '#C8E6C9', previewColor: '#1B3B2F' },
  { name: '深蓝', backgroundColor: '#1A237E', textColor: '#B3E5FC', previewColor: '#1A237E' }
];

/**
 * 自定义背景设置
 */
export interface CustomBackground {
  /** 背景类型 */
  type: BackgroundType;
  /** 背景颜色（当type为COLOR时使用） */
  color?: string;
  /** 背景图片路径（当type为IMAGE时使用） */
  imagePath?: string;
  /** 背景图片不透明度（0-1） */
  imageOpacity?: number;
  /** 渐变起始颜色（当type为GRADIENT时使用） */
  gradientStart?: string;
  /** 渐变结束颜色（当type为GRADIENT时使用） */
  gradientEnd?: string;
  /** 渐变角度（度） */
  gradientAngle?: number;
}

/**
 * 文字样式设置
 */
export interface TextStyleSettings {
  /** 字体大小（vp） */
  fontSize: number;
  /** 行高倍数（相对于字体大小） */
  lineHeight: number;
  /** 段落间距（vp） */
  paragraphSpacing: number;
  /** 首行缩进（em数，0表示不缩进） */
  firstLineIndent: number;
  /** 字间距（vp） */
  letterSpacing: number;
  /** 文字颜色 */
  textColor: string;
  /** 字体粗细 */
  fontWeight: number;
  /** 字体族名称 */
  fontFamily: string;
  /** 自定义字体文件路径（可选） */
  fontPath?: string;
  /** 文字对齐方式 */
  textAlignment: TextAlignment;
}

/**
 * 页面边距设置
 */
export interface PageMargins {
  /** 上边距（vp） */
  top: number;
  /** 下边距（vp） */
  bottom: number;
  /** 左边距（vp） */
  left: number;
  /** 右边距（vp） */
  right: number;
}

/**
 * 保存的背景图片信息
 */
export interface SavedBackgroundImage {
  /** 图片路径 */
  path: string;
  /** 添加时间 */
  addTime: number;
}

/**
 * 听书引擎类型
 */
export enum ReadAloudEngineType {
  SYSTEM = 'SYSTEM',
  LEGADO_COMPAT = 'LEGADO_COMPAT',
  REMOTE = 'REMOTE'
}

/**
 * 听书设置
 */
export interface ReadAloudSettings {
  /** 听书总开关 */
  enabled: boolean;
  /** 引擎类型 */
  engineType: ReadAloudEngineType;
  /** 语速（0.5-2.0） */
  speed: number;
  /** 音调（0.5-2.0） */
  pitch: number;
  /** 音量（0-1） */
  volume: number;
  /** 后台是否继续播放 */
  continueInBackground: boolean;
  /** 章节切换后是否自动继续 */
  autoPlayNextChapter: boolean;
  /** 手动翻页时是否自动暂停听书 */
  pauseOnManualPageTurn: boolean;
  /** 系统TTS音色语种（空字符串表示跟随系统默认） */
  voiceLanguage?: string;
  /** 系统TTS音色人设（-1 表示跟随系统默认） */
  voicePerson?: number;
  /** 系统TTS音色在线类型（0在线/1离线，-1表示跟随系统默认） */
  voiceOnline?: number;
}

/**
 * 默认听书设置
 */
export const DEFAULT_READ_ALOUD_SETTINGS: ReadAloudSettings = {
  enabled: false,
  engineType: ReadAloudEngineType.SYSTEM,
  speed: 1.0,
  pitch: 1.0,
  volume: 1.0,
  continueInBackground: false,
  autoPlayNextChapter: true,
  pauseOnManualPageTurn: true,
  voiceLanguage: '',
  voicePerson: -1,
  voiceOnline: -1
};

/**
 * 文本阅读器设置
 */
export interface TextReaderSettings {
  /** 阅读模式 */
  readingMode: TextReadingMode;
  /** 阅读方向 */
  readingDirection: TextReadingDirection;
  /** 翻页动画类型 */
  pageTurnAnimation: TextPageTurnAnimation;
  /** 背景设置 */
  background: CustomBackground;
  /** 保存的背景图片列表（最多10个） */
  savedBackgroundImages: SavedBackgroundImage[];
  /** 文字样式 */
  textStyle: TextStyleSettings;
  /** 页面边距 */
  pageMargins: PageMargins;
  /** 是否保持屏幕常亮 */
  keepScreenOn: boolean;
  /** 是否显示页码 */
  showPageNumber: boolean;
  /** 是否显示进度百分比 */
  showProgress: boolean;
  /** 是否显示时间 */
  showTime: boolean;
  /** 是否显示电量 */
  showBattery: boolean;
  /** 点击区域翻页 */
  tapToTurn: boolean;
  /** 音量键翻页 */
  volumeKeyNavigation: boolean;
  /** 自动滚动速度（像素/秒） */
  autoScrollSpeed: number;
  /** Auto page turn switch */
  autoPageTurnEnabled?: boolean;
  /** Auto page turn interval in seconds */
  autoPageTurnInterval?: number;
  /** 卷页背面透明度（0-100） */
  curlBackOpacity: number;
  /** 听书设置（可选，兼容旧版本） */
  readAloud?: ReadAloudSettings;
}

/**
 * 默认文字样式
 */
export const DEFAULT_TEXT_STYLE: TextStyleSettings = {
  fontSize: 18,
  lineHeight: 1.8,
  paragraphSpacing: 16,
  firstLineIndent: 2,
  letterSpacing: 0.5,
  textColor: '#333333',
  fontWeight: 400,
  fontFamily: 'HarmonyOS Sans',
  textAlignment: TextAlignment.JUSTIFY
};

/**
 * 默认页面边距
 */
export const DEFAULT_PAGE_MARGINS: PageMargins = {
  top: 48,
  bottom: 48,
  left: 24,
  right: 24
};

/**
 * 默认背景设置
 */
export const DEFAULT_BACKGROUND: CustomBackground = {
  type: BackgroundType.COLOR,
  color: '#F5F0E1',
  imageOpacity: 1.0
};

/**
 * 默认文本阅读器设置
 */
export const DEFAULT_TEXT_READER_SETTINGS: TextReaderSettings = {
  readingMode: TextReadingMode.PAGE,
  readingDirection: TextReadingDirection.HORIZONTAL,
  pageTurnAnimation: TextPageTurnAnimation.CURL,
  background: DEFAULT_BACKGROUND,
  savedBackgroundImages: [],
  textStyle: DEFAULT_TEXT_STYLE,
  pageMargins: DEFAULT_PAGE_MARGINS,
  keepScreenOn: true,
  showPageNumber: true,
  showProgress: true,
  showTime: true,
  showBattery: true,
  tapToTurn: true,
  volumeKeyNavigation: true,
  autoScrollSpeed: 50,
  autoPageTurnEnabled: false,
  autoPageTurnInterval: 8,
  curlBackOpacity: 90,
  readAloud: {
    enabled: DEFAULT_READ_ALOUD_SETTINGS.enabled,
    engineType: DEFAULT_READ_ALOUD_SETTINGS.engineType,
    speed: DEFAULT_READ_ALOUD_SETTINGS.speed,
    pitch: DEFAULT_READ_ALOUD_SETTINGS.pitch,
    volume: DEFAULT_READ_ALOUD_SETTINGS.volume,
    continueInBackground: DEFAULT_READ_ALOUD_SETTINGS.continueInBackground,
    autoPlayNextChapter: DEFAULT_READ_ALOUD_SETTINGS.autoPlayNextChapter,
    pauseOnManualPageTurn: DEFAULT_READ_ALOUD_SETTINGS.pauseOnManualPageTurn,
    voiceLanguage: DEFAULT_READ_ALOUD_SETTINGS.voiceLanguage,
    voicePerson: DEFAULT_READ_ALOUD_SETTINGS.voicePerson,
    voiceOnline: DEFAULT_READ_ALOUD_SETTINGS.voiceOnline
  }
};

/**
 * 文本页面数据
 */
export interface TextPage {
  /** 页面索引 */
  index: number;
  /** 页面文本内容 */
  content: string;
  /** 起始字符位置 */
  startCharIndex: number;
  /** 结束字符位置 */
  endCharIndex: number;
}

/**
 * 文本章节数据
 */
export interface TextChapter {
  /** 章节ID */
  id: string;
  /** 章节标题 */
  title: string;
  /** 章节索引 */
  index: number;
  /** 章节内容 */
  content: string;
  /** 章节起始字符位置（在全文中） */
  startPosition: number;
  /** 章节结束字符位置（在全文中） */
  endPosition: number;
}

/**
 * 文本阅读进度
 */
export interface TextReadingProgress {
  /** 当前章节索引 */
  currentChapterIndex: number;
  /** 当前页面索引 */
  currentPageIndex: number;
  /** 当前字符位置 */
  currentCharPosition: number;
  /** 阅读进度百分比（0-100） */
  progressPercent: number;
  /** 最后阅读时间 */
  lastReadTime: number;
}

/**
 * 文本阅读器回调接口
 */
export interface TextReaderCallbacks {
  /** 页面切换回调 */
  onPageChange?: (pageIndex: number, totalPages: number) => void;
  /** 当前页字符区间变化回调（用于听书进度映射） */
  onPageCharRangeChange?: (startCharIndex: number, endCharIndex: number) => void;
  /** 章节切换回调 */
  onChapterChange?: (chapterIndex: number) => void;
  /** 进度变化回调 */
  onProgressChange?: (progress: number) => void;
  /** 点击中间区域回调（用于显示/隐藏工具栏） */
  onTapCenter?: () => void;
  /** 长按回调（选择文字） */
  onLongPress?: (event: GestureEvent) => void;
  /** 设置变化回调 */
  onSettingsChange?: (settings: TextReaderSettings) => void;
}

/**
 * 文本阅读器参数接口
 */
export interface TextReaderParams {
  /** 文本内容（完整文本或章节列表） */
  content: string;
  /** 章节列表（可选，如果提供则支持章节导航） */
  chapters?: TextChapter[];
  /** 初始章节索引 */
  initialChapterIndex?: number;
  /** 初始页面索引 */
  initialPageIndex?: number;
  /** 初始字符位置 */
  initialCharPosition?: number;
  /** 阅读设置 */
  settings: TextReaderSettings;
  /** 回调函数 */
  callbacks?: TextReaderCallbacks;
}

/**
 * 支持的纯文本文件扩展名
 */
export const SUPPORTED_TEXT_EXTENSIONS: string[] = [
  'txt', 'text',
  'md', 'markdown',
  'json',
  'xml',
  'html', 'htm',
  'css',
  'js', 'ts',
  'log',
  'ini', 'conf', 'cfg',
  'yaml', 'yml',
  'csv',
  'sql'
];

/**
 * 判断文件是否为纯文本文件
 */
export function isTextFile(filePath: string): boolean {
  const extension = filePath.split('.').pop()?.toLowerCase() || '';
  return SUPPORTED_TEXT_EXTENSIONS.includes(extension);
}

/**
 * 判断文件是否为电子书文件（需要使用官方阅读器）
 */
export function isEBookFile(filePath: string): boolean {
  const extension = filePath.split('.').pop()?.toLowerCase() || '';
  return ['epub', 'mobi', 'azw', 'azw3', 'pdf'].includes(extension);
}
