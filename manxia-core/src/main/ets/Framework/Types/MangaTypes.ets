/**
 * 漫画类型系统重构
 * 明确区分本地漫画和在线漫画，避免类型混淆
 */

/**
 * 漫画来源类型（不可变）
 * 这是漫画的本质属性，一旦确定就不会改变
 */
export enum MangaSourceType {
  /** 本地漫画：从本地文件导入的漫画（ZIP、文件夹等） */
  LOCAL = 'LOCAL',
  
  /** 在线漫画：从图源网站获取的漫画 */
  ONLINE = 'ONLINE'
}

/**
 * 在线漫画的下载状态
 * 只有在线漫画才有这个属性
 */
export enum OnlineChapterDownloadStatus {
  /** 未下载 */
  NOT_DOWNLOADED = 'NOT_DOWNLOADED',
  
  /** 下载中 */
  DOWNLOADING = 'DOWNLOADING',
  
  /** 已下载 */
  DOWNLOADED = 'DOWNLOADED',
  
  /** 下载失败 */
  FAILED = 'FAILED'
}

/**
 * 漫画基础信息（所有漫画共有的属性）
 */
export interface MangaBase {
  /** 内部ID（数据库主键） */
  id: string;
  
  /** 标题 */
  title: string;
  
  /** 作者 */
  author?: string;
  
  /** 描述 */
  description?: string;
  
  /** 封面URL */
  coverUrl?: string;
  
  /** 封面本地路径 */
  coverLocalPath?: string;
  
  /** 标签 */
  tags?: string[];
  
  /** 创建时间 */
  createTime: number;
  
  /** 更新时间 */
  updateTime: number;
}

/**
 * 本地漫画信息
 */
export interface LocalManga extends MangaBase {
  /** 来源类型：固定为LOCAL */
  sourceType: MangaSourceType.LOCAL;
  
  /** 本地路径 */
  localPath: string;
  
  /** 文件大小 */
  fileSize?: number;
}

/**
 * 在线漫画信息
 */
export interface OnlineManga extends MangaBase {
  /** 来源类型：固定为ONLINE */
  sourceType: MangaSourceType.ONLINE;
  
  /** 图源名称（如：komiic、manhuagui等） */
  sourceName: string;
  
  /** 图源ID（数据库外键） */
  sourceId: number;
  
  /** 外部ID（图源网站的漫画ID） */
  externalId: string;
  
  /** 图源URL */
  sourceUrl?: string;
  
  /** 是否已加入书库 */
  isInLibrary: boolean;
  
  /** 最后同步时间（从图源获取数据的时间） */
  lastSyncTime?: number;
}

/**
 * 统一的漫画类型
 */
export type Manga = LocalManga | OnlineManga;

/**
 * 章节基础信息
 */
export interface ChapterBase {
  /** 内部ID */
  id: string;
  
  /** 所属漫画ID */
  mangaId: string;
  
  /** 标题 */
  title: string;
  
  /** 章节序号 */
  chapterNumber: number;
  
  /** 页数 */
  pageCount: number;
  
  /** 创建时间 */
  createTime: number;
}

/**
 * 本地章节信息
 */
export interface LocalChapter extends ChapterBase {
  /** 本地路径 */
  localPath: string;
}

/**
 * 在线章节信息
 */
export interface OnlineChapter extends ChapterBase {
  /** 外部ID（图源网站的章节ID） */
  externalId: string;
  
  /** 图源URL */
  sourceUrl?: string;
  
  /** 下载状态 */
  downloadStatus: OnlineChapterDownloadStatus;
  
  /** 下载路径（如果已下载） */
  downloadPath?: string;
  
  /** 发布时间 */
  publishTime?: number;
}

/**
 * 统一的章节类型
 */
export type Chapter = LocalChapter | OnlineChapter;

/**
 * 页面信息
 */
export interface PageInfo {
  /** 内部ID */
  id: string;
  
  /** 所属章节ID */
  chapterId: string;
  
  /** 页码（从0开始） */
  pageNumber: number;
  
  /** 图片URL（在线漫画） */
  imageUrl?: string;
  
  /** 本地路径（本地漫画或已下载的在线漫画） */
  localPath?: string;
  
  /** 图片宽度 */
  width?: number;
  
  /** 图片高度 */
  height?: number;
}

/**
 * 判断是否为在线漫画
 * ArkTS不支持类型守卫函数，使用简单的布尔返回
 */
export function isOnlineManga(manga: Manga): boolean {
  return (manga as OnlineManga).sourceType === MangaSourceType.ONLINE;
}

/**
 * 判断是否为本地漫画
 * ArkTS不支持类型守卫函数，使用简单的布尔返回
 */
export function isLocalManga(manga: Manga): boolean {
  return (manga as LocalManga).sourceType === MangaSourceType.LOCAL;
}

/**
 * 判断是否为在线章节
 * ArkTS不支持类型守卫函数，使用简单的布尔返回
 */
export function isOnlineChapter(chapter: Chapter): boolean {
  return (chapter as OnlineChapter).externalId !== undefined && (chapter as OnlineChapter).downloadStatus !== undefined;
}

/**
 * 判断是否为本地章节
 * ArkTS不支持类型守卫函数，使用简单的布尔返回
 */
export function isLocalChapter(chapter: Chapter): boolean {
  return (chapter as LocalChapter).localPath !== undefined && (chapter as OnlineChapter).externalId === undefined;
}

/**
 * 判断在线章节是否已下载
 */
export function isChapterDownloaded(chapter: OnlineChapter): boolean {
  return chapter.downloadStatus === OnlineChapterDownloadStatus.DOWNLOADED 
    && !!chapter.downloadPath;
}

/**
 * 判断页面是否有本地文件
 */
export function hasLocalImage(page: PageInfo): boolean {
  return !!page.localPath;
}

/**
 * 判断页面是否需要从网络加载
 */
export function needsNetworkLoad(page: PageInfo): boolean {
  return !page.localPath && !!page.imageUrl;
}
