/**
 * 内容重复检测数据模型
 */

/**
 * 待检测内容的标准化输入
 */
export interface DuplicateCheckInput {
  title: string;
  author: string;
  contentType: DuplicateCheckContentType;
  sourceId?: string;
  externalId?: string;
  filePath?: string;
}

/**
 * 内容类型枚举（用于重复检测）
 */
export enum DuplicateCheckContentType {
  MANGA = 'manga',
  EBOOK = 'ebook',
  NOVEL = 'novel'
}

/**
 * 候选项（内部使用，从各 DataManager 查询出的标准化数据）
 */
export interface DuplicateCandidateItem {
  id: string;
  title: string;
  author: string;
  coverUrl: string;
  contentType: DuplicateCheckContentType;
  chapterCount: number;
  sourceName: string;
  isFavorite: boolean;
}

/**
 * 单个匹配结果
 */
export interface DuplicateMatchItem {
  id: string;
  title: string;
  author: string;
  coverUrl: string;
  contentType: DuplicateCheckContentType;
  titleSimilarity: number;
  authorSimilarity: number;
  overallSimilarity: number;
  chapterCount: number;
  sourceName: string;
  isFavorite: boolean;
}

/**
 * 检测结果
 */
export interface DuplicateCheckResult {
  hasDuplicates: boolean;
  matches: DuplicateMatchItem[];
  checkedCount: number;
}

/**
 * 检测配置
 */
export interface DuplicateDetectionConfig {
  enabled: boolean;
  threshold: number;
  checkScope: DuplicateCheckScope;
  titleWeight: number;
  authorWeight: number;
}

/**
 * 检测范围枚举
 */
export enum DuplicateCheckScope {
  SAME_TYPE = 'same_type',
  ALL_TYPES = 'all_types'
}

/**
 * 默认检测配置
 */
export const DEFAULT_DUPLICATE_DETECTION_CONFIG: DuplicateDetectionConfig = {
  enabled: false,
  threshold: 0.5,
  checkScope: DuplicateCheckScope.SAME_TYPE,
  titleWeight: 0.7,
  authorWeight: 0.3
};

/**
 * 内容类型显示名称映射
 */
export function getContentTypeDisplayName(contentType: DuplicateCheckContentType): string {
  if (contentType === DuplicateCheckContentType.MANGA) {
    return '漫画';
  } else if (contentType === DuplicateCheckContentType.EBOOK) {
    return '电子书';
  } else {
    return '小说';
  }
}

/**
 * 相似度百分比显示文本
 */
export function formatSimilarityPercent(similarity: number): string {
  return `${Math.round(similarity * 100)}%`;
}
