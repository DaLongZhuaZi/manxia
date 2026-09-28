/**
 * 临时漫画数据模型
 * 用于缓存从图源获取的漫画基本信息和封面图片
 */

/**
 * 临时漫画信息接口
 */
export interface TempMangaInfo {
  /** 唯一标识：sourceId_externalId */
  id: string;
  /** 图源ID */
  sourceId: number;
  /** 外部漫画ID（图源中的ID） */
  externalId: string;
  /** 漫画名称 */
  title: string;
  /** 原始封面URL */
  coverUrl: string;
  /** 本地封面路径（如果已下载） */
  localCoverPath?: string;
  /** 创建时间 */
  createTime: number;
  /** 最后访问时间 */
  lastAccessTime: number;
}

/**
 * 临时漫画数据库记录
 */
export interface TempMangaDatabaseRecord {
  id: string;
  sourceId: number;
  externalId: string;
  title: string;
  coverUrl: string;
  localCoverPath: string | null;
  createTime: number;
  lastAccessTime: number;
}
