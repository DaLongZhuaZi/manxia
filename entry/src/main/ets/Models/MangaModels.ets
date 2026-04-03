/**
 * 漫画阅读器数据模型定义
 * 支持本地和网络图片源，包含元数据、阅读进度、书签等信息
 * 遵循ArkTS类型安全规范，避免使用any和unknown类型
 */

import { MangaStatus, DownloadStatus, ReadingStatus } from '../Framework/Types/StatusEnums';
import { TimeUtils } from '../Framework/Utils/TimeUtils';

/**
 * 图片源类型枚举
 */
export enum ImageSourceType {
  LOCAL = 'LOCAL',
  NETWORK = 'NETWORK',
  RAWFILE = 'RAWFILE',
  RESOURCE = 'RESOURCE'
}

/**
 * 阅读模式枚举
 */
export enum ReadingMode {
  SINGLE_PAGE = 'SINGLE_PAGE',                    // 单页模式（默认从左到右）
  SINGLE_PAGE_LTR = 'SINGLE_PAGE_LTR',           // 单页式（从左到右）
  SINGLE_PAGE_RTL = 'SINGLE_PAGE_RTL',           // 单页式（从右到左）
  SINGLE_PAGE_TTB = 'SINGLE_PAGE_TTB',           // 单页式（从上到下）
  DOUBLE_PAGE = 'DOUBLE_PAGE',                    // 双页模式
  CONTINUOUS_SCROLL = 'CONTINUOUS_SCROLL',        // 连续滚动模式
  CONTINUOUS_VERTICAL = 'CONTINUOUS_VERTICAL',    // 连续垂直滚动模式（条漫）
  WEBTOON = 'WEBTOON',                           // 条漫模式
  WEBTOON_WITH_GAP = 'WEBTOON_WITH_GAP'          // 条漫（页间有间歇）
}

/**
 * 阅读方向枚举
 */
export enum ReadingDirection {
  LEFT_TO_RIGHT = 'LEFT_TO_RIGHT',    // 从左到右
  RIGHT_TO_LEFT = 'RIGHT_TO_LEFT',    // 从右到左
  TOP_TO_BOTTOM = 'TOP_TO_BOTTOM',    // 从上到下
  VERTICAL = 'VERTICAL'               // 垂直方向
}

/**
 * 页面信息接口
 */
export interface MangaPage {
  /** 页面ID */
  id: string;
  /** 页面索引（从0开始） */
  index: number;
  /** 图片源类型 */
  sourceType: ImageSourceType;
  /** 图片路径或URL */
  imagePath: string;
  /** 图片URL（兼容性属性） */
  imageUrl: string;
  /** 本地文件路径（已下载的页面） */
  localPath?: string;
  /** 图片宽度 */
  width?: number;
  /** 图片高度 */
  height?: number;
  /** 文件大小（字节） */
  fileSize?: number;
  /** 是否已加载 */
  isLoaded: boolean;
  /** 错误信息 */
  errorMessage?: string;
  /** 加载优先级（10=当前页，5=下一页，3=下下页，1=其他） */
  priority?: number;
}

/**
 * 章节信息接口
 */
export interface MangaChapter {
  /** 章节ID */
  id: string;
  /** 外部ID，用于源站的真实章节ID */
  externalId?: string;
  /** 章节标题 */
  title: string;
  /** 章节编号 */
  chapterNumber: number;
  /** 页面列表 */
  pages: MangaPage[];
  /** 实际总页数（用于动态加载场景，当pages数组不完整时使用） */
  totalPages?: number;
  /** 发布日期（时间戳） */
  publishDate: number | Date ;
  /** 章节语言 */
  language: string;
  /** 扫描组信息 */
  scanlationGroup: string;
  /** 是否已下载 */
  isDownloaded: boolean;
  /** 下载状态 */
  downloadStatus: DownloadStatus;
  /** 下载进度（0-100） */
  downloadProgress: number;
  /** 本地存储路径 */
  localPath?: string;
}

/**
 * 书签信息接口
 */
export interface MangaBookmark {
  /** 书签ID */
  id: string;
  /** 章节ID */
  chapterId: string;
  /** 页面索引 */
  pageIndex: number;
  /** 书签标题 */
  title: string;
  /** 创建时间 */
  createdAt: Date | number;
  /** 备注 */
  note?: string;
}

/**
 * 阅读进度接口
 */
export interface ReadingProgress {
  /** 当前章节ID */
  currentChapterId: string;
  /** 当前页面索引 */
  currentPageIndex: number;
  /** 阅读状态 */
  readingStatus: ReadingStatus;
  /** 总阅读时间（分钟） */
  totalReadingTime: number;
  /** 最后阅读时间（时间戳） */
  lastReadAt: number;
  /** 阅读百分比（0-100） */
  readingPercentage: number;
}

/**
 * 翻页动画类型枚举
 * 
 * 可用动画：
 * - NONE: 无动画
 * - SLIDE: 滑动
 * - FADE: 淡入淡出
 * - CURL: 卷页效果（Canvas 3D卷曲）
 * - CUBE: 立方体旋转
 * - COVER: 覆盖滑入
 * - DEPTH: 景深推进
 * 
 * 已废弃（映射到其他效果）：
 * - ZOOM: 已废弃，映射到DEPTH
 * - FLIP: 已废弃，映射到CUBE
 */
export enum PageTurnAnimationType {
  NONE = 'NONE',                    // 无动画
  SLIDE = 'SLIDE',                  // 滑动
  FADE = 'FADE',                    // 淡入淡出
  CURL = 'CURL',                    // 卷页效果（Canvas 3D卷曲）
  ZOOM = 'ZOOM',                    // [已废弃] 缩放 -> 映射到DEPTH
  FLIP = 'FLIP',                    // [已废弃] 翻转 -> 映射到CUBE
  CUBE = 'CUBE',                    // 立方体旋转（3D）
  COVER = 'COVER',                  // 覆盖滑入
  DEPTH = 'DEPTH'                   // 景深推进（3D）
}

/**
 * 双页竖屏组合方式枚举
 */
export enum DoublePagePortraitLayout {
  VERTICAL = 'VERTICAL',            // 上下组合（页码小的在上）
  HORIZONTAL = 'HORIZONTAL'         // 左右组合（根据阅读方向决定位置）
}

/**
 * 阅读设置接口
 */
export interface ReadingSettings {
  /** 阅读模式 */
  readingMode: ReadingMode;
  /** 阅读方向 */
  readingDirection: ReadingDirection;
  /** 屏幕亮度（0-100） */
  brightness: number;
  /** 是否保持屏幕常亮 */
  keepScreenOn: boolean;
  /** 页面间距 */
  pageSpacing: number;
  /** 是否显示页面信息 */
  showPageInfo: boolean;
  /** 是否显示页面指示器 */
  showPageIndicator: boolean;
  /** 图片适配模式 */
  fitMode: string;
  /** 自动翻页间隔（秒，0表示禁用） */
  autoPageTurnInterval: number;
  /** 自动跳过前情提要页数（0表示不跳过） */
  skipIntroPages: number;
  /** 翻页动画类型 */
  pageTurnAnimation: PageTurnAnimationType;
  /** 双页竖屏组合方式 */
  doublePagePortraitLayout: DoublePagePortraitLayout;
  /** 滤镜设置 */
  filterSettings: FilterSettings;
  /** 音量键翻页 */
  volumeKeyNavigation: boolean;
  /** 卷页背面透明度（0-100，100为完全不透明） */
  curlBackOpacity: number;
  /** 条漫模式左边距（0-50%） */
  webtoonLeftMargin: number;
  /** 条漫模式右边距（0-50%） */
  webtoonRightMargin: number;
  /** 条漫模式边距同步调整 */
  webtoonMarginSync: boolean;
}

/**
 * 滤镜设置接口
 */
export interface FilterSettings {
  /** 是否启用滤镜 */
  enabled: boolean;
  /** 亮度（0-200，100为默认） */
  brightness: number;
  /** 对比度（0-200，100为默认） */
  contrast: number;
  /** 饱和度（0-200，100为默认） */
  saturation: number;
  /** 色调（-180到180，0为默认） */
  hue: number;
  /** 伽马值（0.1-3.0，1.0为默认） */
  gamma: number;
  /** 棕褐色滤镜（0-100，0为默认） */
  sepia: number;
  /** 是否反色 */
  invert: boolean;
  /** 灰度模式 */
  grayscale: boolean;
  /** 模糊程度（0-10，0为默认） */
  blur: number;
}

/**
 * 漫画元数据接口
 */
export interface MangaMetadata {
  /** 作者列表 */
  authors: string[];
  /** 艺术家列表 */
  artists: string[];
  /** 类型标签 */
  genres: string[];
  /** 主题标签 */
  themes: string[];
  /** 人口统计标签 */
  demographics: string[];
  /** 内容评级 */
  contentRating?: string;
  /** 发布年份 */
  publicationYear?: number;
  /** 出版社 */
  publisher?: string;
  /** 序列化信息 */
  serialization?: string;
}

/**
 * 漫画信息主接口
 */
export interface Manga {
  /** 漫画ID */
  id: string;
  /** 漫画标题 */
  title: string;
  /** 替代标题 */
  alternativeTitles: string[];
  /** 描述 */
  description: string;
  /** 封面图片路径 */
  coverImagePath: string;
  /** 封面图片源类型 */
  coverSourceType: ImageSourceType;
  /** 漫画状态 */
  status: MangaStatus;
  /** 元数据 */
  metadata: MangaMetadata;
  /** 章节列表 */
  chapters: MangaChapter[];
  /** 阅读进度 */
  readingProgress: ReadingProgress;
  /** 书签列表 */
  bookmarks: MangaBookmark[];
  /** 阅读设置 */
  readingSettings: ReadingSettings;
  /** 是否收藏 */
  isFavorite: boolean;
  /** 添加到库的时间（时间戳） */
  addedToLibraryAt?: number;
  /** 最后更新时间（时间戳） */
  lastUpdatedAt: number;
  /** 源信息（用于网络漫画） */
  sourceInfo?: MangaSourceInfo;
  /** 内容类型：'manga' = 漫画, 'ebook' = 电子书类PDF（用于区分显示位置） */
  contentType?: string;
  /** 是否为NSFW内容 */
  isNSFW?: boolean;
  /** 是否为隐私内容 */
  isPrivate?: boolean;
}

/**
 * 漫画源信息接口
 */
export interface MangaSourceInfo {
  /** 源名称 */
  sourceName: string;
  /** 源URL */
  sourceUrl: string;
  /** 源ID */
  sourceId: string;
  /** 外部ID，用于源站的真实ID */
  externalId?: string;
  /** 源语言 */
  sourceLanguage: string;
  /** 是否需要登录 */
  requiresLogin: boolean;
  /** API版本 */
  apiVersion?: string;
  /** 是否为成人内容源（NSFW） */
  isNSFW?: boolean;
  providerType?: 'suwayomi' | 'komga';
  providerItemId?: string;
  providerInstanceId?: string;
  providerContentType?: 'SERIES' | 'READLISTS' | 'BOOKS';
}

/**
 * 漫画搜索结果接口
 */
export interface MangaSearchResult {
  /** 搜索到的漫画列表 */
  mangas: Manga[];
  /** 总数量 */
  totalCount: number;
  /** 当前页码 */
  currentPage: number;
  /** 每页数量 */
  pageSize: number;
  /** 是否有下一页 */
  hasNextPage: boolean;
  /** 搜索关键词 */
  searchQuery: string;
}

/**
 * 漫画阅读器状态接口
 */
export interface MangaReaderState {
  /** 当前漫画 */
  currentManga: Manga | null;
  /** 当前章节 */
  currentChapter: MangaChapter | null;
  /** 当前页面索引 */
  currentPageIndex: number;
  /** 是否全屏模式 */
  isFullscreen: boolean;
  /** 是否显示控制栏 */
  showControls: boolean;
  /** 是否正在加载 */
  isLoading: boolean;
  /** 加载状态消息 */
  loadingMessage?: string;
  /** 缩放比例 */
  zoomScale: number;
  /** 错误信息 */
  errorMessage: string;
}

/**
 * 默认阅读设置
 */
export const DEFAULT_READING_SETTINGS: ReadingSettings = {
  readingMode: ReadingMode.SINGLE_PAGE,
  readingDirection: ReadingDirection.LEFT_TO_RIGHT,
  brightness: 1.0,  // 范围 0.1-2.0，1.0 为默认亮度（对应系统亮度 0.5）
  keepScreenOn: true,
  pageSpacing: 0,
  showPageInfo: true,
  showPageIndicator: true,
  fitMode: 'fit_width',
  autoPageTurnInterval: 0,
  skipIntroPages: 0,
  pageTurnAnimation: PageTurnAnimationType.SLIDE,
  doublePagePortraitLayout: DoublePagePortraitLayout.VERTICAL,
  filterSettings: {
    enabled: false,
    contrast: 100,
    saturation: 100,
    hue: 0,
    gamma: 1.0,
    invert: false,
    grayscale: false,
    blur: 0,
    sepia: 0,
    brightness: 100
  },
  volumeKeyNavigation: false,
  curlBackOpacity: 90,  // 默认90%不透明
  webtoonLeftMargin: 0,  // 默认0，无边距
  webtoonRightMargin: 0,  // 默认0，无边距
  webtoonMarginSync: true  // 默认同步调整
};

/**
 * 默认滤镜设置
 */
export const DEFAULT_FILTER_SETTINGS: FilterSettings = {
  /** 是否启用滤镜 */
  enabled: true,
  /** 亮度（0-200，100为默认） */
  brightness: 100,
  /** 对比度（0-200，100为默认） */
  contrast: 100,
  /** 饱和度（0-200，100为默认） */
  saturation: 100,
  /** 色调（-180到180，0为默认） */
  hue: 0,
  /** 伽马值（0.1-3.0，1.0为默认） */
  gamma: 1.0,
  /** 棕褐色滤镜（0-100，0为默认） */
  sepia: 0,
  /** 是否反色 */
  invert: false,
  /** 灰度模式 */
  grayscale: false,
  /** 模糊程度（0-10，0为默认） */
  blur: 0
};

export { MangaStatus, ReadingStatus };
