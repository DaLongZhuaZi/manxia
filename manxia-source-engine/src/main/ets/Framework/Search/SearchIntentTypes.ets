/**
 * 搜索意图类型定义
 * 用于统一解析用户搜索输入，支持ID直达、URL直达等增强功能
 */

/**
 * 搜索意图类型枚举
 */
export enum SearchIntentType {
  /** 普通关键词搜索 */
  KEYWORD = 'keyword',
  /** URL直达 */
  URL = 'url',
  /** 作品ID直达 */
  MANGA_ID = 'manga_id',
  /** 作者ID搜索 */
  AUTHOR_ID = 'author_id',
  /** 系列ID搜索 */
  SERIES_ID = 'series_id',
  /** 章节ID直达 */
  CHAPTER_ID = 'chapter_id',
  /** 未知类型（需要用户选择） */
  AMBIGUOUS = 'ambiguous'
}

/**
 * URL解析信息
 */
export interface UrlParsedInfo {
  /** 域名 */
  domain: string;
  /** 路径类型：artwork/user/series/unknown */
  pathType: string;
  /** 提取的ID */
  extractedId?: string;
}

/**
 * 搜索意图解析结果
 */
export interface SearchIntent {
  /** 意图类型 */
  type: SearchIntentType;
  /** 解析出的ID（如果有） */
  id?: string;
  /** 解析出的URL（如果有） */
  url?: string;
  /** 原始输入 */
  rawQuery: string;
  /** 剩余关键词（用于组合搜索） */
  restKeyword?: string;
  /** URL解析出的额外信息 */
  urlParsedInfo?: UrlParsedInfo;
}

/**
 * 图源URL模式配置（可选，图源可在JSON中声明）
 */
export interface SourceUrlPattern {
  /** 作品详情URL正则 */
  artworkPattern?: string;
  /** 作者页面URL正则 */
  authorPattern?: string;
  /** 系列页面URL正则 */
  seriesPattern?: string;
}
