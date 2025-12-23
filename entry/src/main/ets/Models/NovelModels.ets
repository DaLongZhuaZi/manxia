/**
 * 小说数据模型
 * 定义小说相关的数据结构
 * 
 * 文件路径: entry/src/main/ets/Models/NovelModels.ets
 */

/**
 * 小说阅读状态
 */
export enum NovelReadStatus {
  UNREAD = 'unread',
  READING = 'reading',
  FINISHED = 'finished'
}

/**
 * 小说书籍信息
 */
export interface NovelBook {
  id: string;
  sourceId: string;
  sourceName: string;
  bookUrl: string;
  name: string;
  author: string;
  kind?: string;
  intro?: string;
  coverUrl?: string;
  coverLocalPath?: string;
  tocUrl?: string;
  latestChapterTitle?: string;
  wordCount?: string;
  updateTime?: number;
  chapterCount: number;
  readStatus: NovelReadStatus;
  lastReadChapterId?: string;
  lastReadChapterIndex?: number;
  lastReadPosition?: number;
  lastReadTime?: number;
  totalReadingTime: number;  // 总阅读时长（秒）
  isFavorite: boolean;
  createTime: number;
  updateDbTime: number;
  groupName?: string;
}

/**
 * 小说章节信息
 */
export interface NovelChapter {
  id: string;
  bookId: string;
  url: string;
  title: string;
  index: number;
  isVolume: boolean;
  isVip: boolean;
  isPay: boolean;
  isDownloaded: boolean;
  contentPath?: string;
  wordCount?: number;
  updateTime?: number;
  createTime: number;
}

/**
 * 小说正文内容
 */
export interface NovelContent {
  chapterId: string;
  title: string;
  content: string;
  wordCount: number;
  hasNextPage: boolean;
  nextPageUrl?: string;
}

/**
 * 小说阅读进度
 */
export interface NovelReadProgress {
  bookId: string;
  chapterId: string;
  chapterIndex: number;
  position: number;
  progress: number;
  readTime: number;
}

/**
 * 小说搜索结果
 */
export interface NovelSearchResult {
  sourceId: string;
  sourceName: string;
  bookUrl: string;
  name: string;
  author: string;
  kind?: string;
  intro?: string;
  coverUrl?: string;
  latestChapterTitle?: string;
  wordCount?: string;
}

/**
 * 小说书源信息
 */
export interface NovelSourceInfo {
  id: string;
  name: string;
  url: string;
  group?: string;
  enabled: boolean;
  weight: number;
  lastUpdateTime: number;
  respondTime: number;
  searchable: boolean;
  hasExplore: boolean;
  isTop?: boolean;
}

/**
 * 小说阅读设置
 */
export interface NovelReaderSettings {
  fontSize: number;
  lineHeight: number;
  letterSpacing: number;
  paragraphSpacing: number;
  fontFamily: string;
  textColor: string;
  backgroundColor: string;
  brightness: number;
  keepScreenOn: boolean;
  volumeKeyTurn: boolean;
  clickTurn: boolean;
  autoScroll: boolean;
  autoScrollSpeed: number;
}

/**
 * 默认阅读设置
 */
export const DEFAULT_NOVEL_READER_SETTINGS: NovelReaderSettings = {
  fontSize: 18,
  lineHeight: 1.8,
  letterSpacing: 0,
  paragraphSpacing: 16,
  fontFamily: 'HarmonyOS Sans',
  textColor: '#333333',
  backgroundColor: '#F5F5DC',
  brightness: 1.0,
  keepScreenOn: true,
  volumeKeyTurn: true,
  clickTurn: true,
  autoScroll: false,
  autoScrollSpeed: 50
};

/**
 * 预设主题
 */
export interface NovelReaderTheme {
  name: string;
  textColor: string;
  backgroundColor: string;
}

/**
 * 预设主题列表
 */
export const NOVEL_READER_THEMES: NovelReaderTheme[] = [
  { name: '默认', textColor: '#333333', backgroundColor: '#F5F5DC' },
  { name: '护眼', textColor: '#2E4A2E', backgroundColor: '#C7EDCC' },
  { name: '夜间', textColor: '#808080', backgroundColor: '#1A1A1A' },
  { name: '纯白', textColor: '#000000', backgroundColor: '#FFFFFF' },
  { name: '羊皮纸', textColor: '#5C4033', backgroundColor: '#F4ECD8' },
  { name: '淡蓝', textColor: '#2F4F4F', backgroundColor: '#E0FFFF' }
];

/**
 * 小说缓存信息
 */
export interface NovelCacheInfo {
  bookId: string;
  cachedChapterCount: number;
  totalChapterCount: number;
  cacheSize: number;
  lastCacheTime: number;
}

/**
 * 小说下载任务
 */
export interface NovelDownloadTask {
  id: string;
  bookId: string;
  bookName: string;
  startChapterIndex: number;
  endChapterIndex: number;
  currentChapterIndex: number;
  status: 'pending' | 'downloading' | 'paused' | 'completed' | 'failed';
  progress: number;
  errorMessage?: string;
  createTime: number;
  updateTime: number;
}

/**
 * 书籍元数据（用于缓存）
 */
export interface BookMetadata {
  bookId: string;
  bookName: string;
  author: string;
  coverUrl: string;
  createTime: number;
  updateTime: number;
}
