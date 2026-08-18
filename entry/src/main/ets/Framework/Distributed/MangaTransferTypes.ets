// 文件路径: src/main/ets/Framework/Distributed/MangaTransferTypes.ets
/**
 * 漫画跨端接续传输的共享元数据类型。
 * 由 RemoteControlSocketChannel（源端打包/目标端接收）与 DataManager（目标端入库）共同引用，
 * 独立成文件避免循环依赖。
 */

/** 漫画行元数据（本地/在线统一形态，字段已展平为可 JSON 传输的原始值） */
export interface RemoteComicMetadata {
  id: string;
  title: string;
  author: string;
  description: string;
  coverUrl: string;
  coverLocalPath: string;
  sourceId: string;
  externalId: string;
  status: string;
  tags: string[];
  rating: number;
  chapterCount: number;
  lastUpdateTime: number;
  addTime: number;
  contentType: string;
  isNSFW: number;
  isPrivate: number;
}

/** 章节行元数据 */
export interface RemoteChapterMetadata {
  id: string;
  title: string;
  index: number;
  pageCount: number;
  isDownloaded: boolean;
  downloadPath: string;
  publishTime: number;
  addTime: number;
  externalId: string;
}

/** 页面行元数据 */
export interface RemotePageMetadata {
  id: string;
  index: number;
  imageUrl: string;
  localPath: string;
  width: number;
  height: number;
  fileSize: number;
}

/** 章节 -> 页面分组 */
export interface MangaChapterPagesEntry {
  chapterId: string;
  pages: RemotePageMetadata[];
}

/** 待传输文件条目（originalPath 为源端绝对路径，relPath 为目标端相对路径） */
export interface MangaTransferFileEntry {
  originalPath: string;
  relPath: string;
  size: number;
  hash: string;
}

/** 漫画接续传输元数据包 */
export interface MangaTransferBundle {
  comic: RemoteComicMetadata;
  chapters: RemoteChapterMetadata[];
  chapterPages: MangaChapterPagesEntry[];
  files: MangaTransferFileEntry[];
}

/** 目标端漫画接收结果 */
export interface MangaBundleReceiveResult {
  bundle: MangaTransferBundle;
  targetRoot: string;
}
