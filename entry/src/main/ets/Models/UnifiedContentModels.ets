// 文件路径: entry/src/main/ets/Models/UnifiedContentModels.ets
/**
 * 统一内容模型
 * 用于将漫画、电子书、小说的数据统一为通用展示格式
 * 注意：这只是展示层的适配，不会修改原有数据结构
 */

/**
 * 内容类型枚举
 */
export enum UnifiedContentType {
  MANGA = 'manga',
  EBOOK = 'ebook',
  NOVEL = 'novel'
}

/**
 * 阅读状态枚举
 */
export enum UnifiedReadStatus {
  UNREAD = 'unread',
  READING = 'reading',
  COMPLETED = 'completed'
}

/**
 * 统一章节模型
 */
export interface UnifiedChapter {
  id: string;
  title: string;
  index: number;
  isRead: boolean;
  isDownloaded: boolean;
  isBookmarked: boolean;
  pageCount?: number;
  wordCount?: number;
  publishDate?: string;
  // 原始数据引用，用于实际操作时获取原始类型
  originalData: Object;
  originalType: UnifiedContentType;
}

/**
 * 统一内容模型（用于详情页展示）
 */
export interface UnifiedContent {
  // 基础信息
  id: string;
  title: string;
  coverUrl: string;
  author: string;
  description: string;
  
  // 分类信息
  contentType: UnifiedContentType;
  genres: string[];
  tags: string[];
  
  // 状态信息
  readStatus: UnifiedReadStatus;
  isFavorite: boolean;
  isNSFW: boolean;
  
  // 进度信息
  totalChapters: number;
  readChapters: number;
  lastReadChapterIndex: number;
  lastReadChapterTitle: string;
  lastReadTime?: number;
  readProgress: number; // 0-100
  
  // 来源信息
  sourceId?: string;
  sourceName?: string;
  sourceUrl?: string;
  isLocal: boolean;
  
  // 额外元数据
  publisher?: string;
  publishDate?: string;
  isbn?: string;
  fileSize?: number;
  filePath?: string;
  format?: string;
  
  // 章节列表
  chapters: UnifiedChapter[];
  
  // 原始数据引用
  originalData: Object;
  originalType: UnifiedContentType;
}

/**
 * 详情页导航参数
 */
export interface UnifiedDetailPageParams {
  contentType: UnifiedContentType;
  contentId: string;
  sourceId?: string;
  // 缓存的基础信息（从列表页传递，用于快速显示）
  cachedTitle?: string;
  cachedCover?: string;
  cachedAuthor?: string;
}

/**
 * 阅读器导航参数
 */
export interface UnifiedReaderParams {
  contentType: UnifiedContentType;
  contentId: string;
  chapterId: string;
  chapterIndex: number;
  sourceId?: string;
  sourceName?: string;
}

/**
 * 内容操作回调接口
 */
export interface UnifiedContentActions {
  // 阅读操作
  onStartReading: (chapterIndex: number) => void;
  onContinueReading: () => void;
  
  // 收藏操作
  onToggleFavorite: () => Promise<void>;
  
  // 下载操作
  onDownloadChapters?: (startIndex: number, endIndex: number) => Promise<void>;
  onDeleteDownloads?: (chapterIds: string[]) => Promise<void>;
  
  // 换源操作（仅小说/在线漫画）
  onChangeSource?: () => void;
  
  // 编辑操作（仅本地内容）
  onEditMetadata?: () => void;
  
  // 刷新操作
  onRefresh: () => Promise<void>;
  
  // 删除操作
  onDelete?: () => Promise<void>;
}

/**
 * 章节过滤类型
 */
export enum ChapterFilterType {
  ALL = 'all',
  UNREAD = 'unread',
  DOWNLOADED = 'downloaded',
  BOOKMARKED = 'bookmarked'
}

/**
 * 章节排序方式
 */
export enum ChapterSortOrder {
  ASCENDING = 'asc',
  DESCENDING = 'desc'
}

/**
 * 章节显示模式
 */
export enum ChapterDisplayMode {
  LIST = 'list',
  GRID = 'grid'
}
