// 文件路径: src/main/ets/Framework/Types/NamingConventions.ets


/**
 * 项目接口命名规范
 * 
 * 1. 接口命名规范：
 *    - 使用 PascalCase（首字母大写的驼峰命名）
 *    - 接口名应该清晰描述其用途
 *    - 避免使用缩写，除非是广泛认知的缩写（如 URL、ID）
 * 
 * 2. 字段命名规范：
 *    - 使用 camelCase（小写开头的驼峰命名）
 *    - 字段名应该具有描述性
 *    - 布尔字段使用 is/has/can/should 等前缀
 *    - 时间相关字段统一使用 timestamp 后缀（number 类型）
 * 
 * 3. 枚举命名规范：
 *    - 枚举名使用 PascalCase
 *    - 枚举值使用 UPPER_SNAKE_CASE
 * 
 * 4. 类型别名规范：
 *    - 使用 PascalCase
 *    - 类型别名应该清晰表达其用途
 */

import { MangaStatus, DownloadStatus } from './StatusEnums';

/**
 * 标准化的基础字段接口
 */
export interface BaseEntity {
  /** 唯一标识符 */
  id: string;
  /** 创建时间戳（毫秒） */
  createdTimestamp: number;
  /** 更新时间戳（毫秒） */
  updatedTimestamp: number;
}

/**
 * 标准化的元数据接口
 */
export interface Metadata {
  /** 名称 */
  name: string;
  /** 描述 */
  description: string;
  /** 作者 */
  author: string;
  /** 版本号 */
  version: string;
  /** 创建时间戳（毫秒） */
  createdTimestamp: number;
  /** 更新时间戳（毫秒） */
  updatedTimestamp: number;
}

/**
 * 标准化的漫画信息接口
 */
export interface MangaInfo extends BaseEntity {
  /** 漫画标题 */
  title: string;
  /** 漫画作者 */
  author: string;
  /** 漫画描述 */
  description: string;
  /** 封面图片URL */
  coverImageUrl: string;
  /** 漫画状态 */
  status: MangaStatus;
  /** 章节总数 */
  totalChapters: number;
  /** 当前阅读章节 */
  currentChapter: number;
  /** 是否收藏 */
  isFavorited: boolean;
  /** 是否已完结 */
  isCompleted: boolean;
  /** 最后阅读时间戳（毫秒） */
  lastReadTimestamp: number;
  /** 标签列表 */
  tags: string[];
  /** 分类列表 */
  categories: string[];
}

/**
 * 标准化的章节信息接口
 */
export interface ChapterInfo extends BaseEntity {
  /** 章节标题 */
  title: string;
  /** 章节编号 */
  chapterNumber: number;
  /** 所属漫画ID */
  mangaId: string;
  /** 章节URL */
  chapterUrl: string;
  /** 页面总数 */
  totalPages: number;
  /** 当前阅读页面 */
  currentPage: number;
  /** 是否已读 */
  isRead: boolean;
  /** 是否已下载 */
  isDownloaded: boolean;
  /** 下载状态 */
  downloadStatus: DownloadStatus;
  /** 文件大小（字节） */
  fileSizeBytes: number;
  /** 最后阅读时间戳（毫秒） */
  lastReadTimestamp: number;
}

/**
 * 标准化的下载任务接口
 */
export interface DownloadTask extends BaseEntity {
  /** 任务名称 */
  taskName: string;
  /** 下载URL */
  downloadUrl: string;
  /** 目标文件路径 */
  targetFilePath: string;
  /** 下载状态 */
  status: DownloadStatus;
  /** 下载进度（0-100） */
  progressPercentage: number;
  /** 已下载字节数 */
  downloadedBytes: number;
  /** 总字节数 */
  totalBytes: number;
  /** 下载速度（字节/秒） */
  downloadSpeedBytesPerSecond: number;
  /** 是否可暂停 */
  isPausable: boolean;
  /** 是否可取消 */
  isCancellable: boolean;
  /** 开始时间戳（毫秒） */
  startTimestamp: number;
  /** 完成时间戳（毫秒，未完成时为0） */
  completedTimestamp: number;
  /** 错误信息 */
  errorMessage: string;
}

/**
 * 标准化的用户配置接口
 */
export interface UserConfiguration extends BaseEntity {
  /** 配置名称 */
  configName: string;
  /** 配置值 */
  configValue: string;
  /** 配置类型 */
  configType: ConfigurationType;
  /** 是否启用 */
  isEnabled: boolean;
  /** 是否只读 */
  isReadOnly: boolean;
  /** 默认值 */
  defaultValue: string;
  /** 配置描述 */
  description: string;
  /** 配置分组 */
  groupName: string;
}

/**
 * 配置类型枚举
 */
export enum ConfigurationType {
  STRING = 'string',
  NUMBER = 'number',
  BOOLEAN = 'boolean',
  JSON = 'json',
  URL = 'url',
  FILE_PATH = 'file_path'
}

/**
 * 标准化的API响应接口
 */
export interface ApiResponse<T = Object> {
  /** 是否成功 */
  isSuccess: boolean;
  /** 响应数据 */
  data: T;
  /** 错误信息 */
  errorMessage: string;
  /** 错误代码 */
  errorCode: string;
  /** 响应时间戳（毫秒） */
  responseTimestamp: number;
  /** 请求ID */
  requestId: string;
}

/**
 * 标准化的分页信息接口
 */
export interface PaginationInfo {
  /** 当前页码（从1开始） */
  currentPage: number;
  /** 每页大小 */
  pageSize: number;
  /** 总记录数 */
  totalRecords: number;
  /** 总页数 */
  totalPages: number;
  /** 是否有上一页 */
  hasPreviousPage: boolean;
  /** 是否有下一页 */
  hasNextPage: boolean;
}

/**
 * 标准化的分页响应接口
 */
export interface PaginatedResponse<T> extends ApiResponse<T[]> {
  /** 分页信息 */
  pagination: PaginationInfo;
}

/**
 * 标准化的搜索条件接口
 */
export interface SearchCriteria {
  /** 搜索关键词 */
  keyword: string;
  /** 搜索字段 */
  searchFields: string[];
  /** 排序字段 */
  sortField: string;
  /** 排序方向 */
  sortDirection: SortDirection;
  /** 过滤条件 */
  filters: SearchFilter[];
  /** 分页信息 */
  pagination: PaginationRequest;
}

/**
 * 排序方向枚举
 */
export enum SortDirection {
  ASC = 'asc',
  DESC = 'desc'
}

/**
 * 搜索过滤条件接口
 */
export interface SearchFilter {
  /** 字段名 */
  fieldName: string;
  /** 操作符 */
  operator: FilterOperator;
  /** 过滤值 */
  value: Object;
}

/**
 * 过滤操作符枚举
 */
export enum FilterOperator {
  EQUALS = 'equals',
  NOT_EQUALS = 'not_equals',
  CONTAINS = 'contains',
  NOT_CONTAINS = 'not_contains',
  STARTS_WITH = 'starts_with',
  ENDS_WITH = 'ends_with',
  GREATER_THAN = 'greater_than',
  GREATER_THAN_OR_EQUAL = 'greater_than_or_equal',
  LESS_THAN = 'less_than',
  LESS_THAN_OR_EQUAL = 'less_than_or_equal',
  IN = 'in',
  NOT_IN = 'not_in'
}

/**
 * 分页请求接口
 */
export interface PaginationRequest {
  /** 页码（从1开始） */
  page: number;
  /** 每页大小 */
  size: number;
}

/**
 * 标准化的文件信息接口
 */
export interface FileInfo extends BaseEntity {
  /** 文件名 */
  fileName: string;
  /** 文件路径 */
  filePath: string;
  /** 文件大小（字节） */
  fileSizeBytes: number;
  /** 文件类型 */
  fileType: string;
  /** MIME类型 */
  mimeType: string;
  /** 文件扩展名 */
  fileExtension: string;
  /** 是否存在 */
  isExists: boolean;
  /** 是否可读 */
  isReadable: boolean;
  /** 是否可写 */
  isWritable: boolean;
  /** 最后修改时间戳（毫秒） */
  lastModifiedTimestamp: number;
}

/**
 * 标准化的缓存项接口
 */
export interface CacheItem<T = Object> {
  /** 缓存键 */
  cacheKey: string;
  /** 缓存值 */
  cacheValue: T;
  /** 创建时间戳（毫秒） */
  createdTimestamp: number;
  /** 过期时间戳（毫秒） */
  expirationTimestamp: number;
  /** 是否已过期 */
  isExpired: boolean;
  /** 访问次数 */
  accessCount: number;
  /** 最后访问时间戳（毫秒） */
  lastAccessTimestamp: number;
}

/**
 * 标准化的日志条目接口
 */
export interface LogEntry {
  /** 日志ID */
  logId: string;
  /** 日志级别 */
  logLevel: LogLevel;
  /** 日志消息 */
  message: string;
  /** 日志标签 */
  tag: string;
  /** 时间戳（毫秒） */
  timestamp: number;
  /** 线程ID */
  threadId: string;
  /** 文件名 */
  fileName: string;
  /** 行号 */
  lineNumber: number;
  /** 额外数据 */
  extraData: Record<string, Object>;
}

/**
 * 日志级别枚举
 */
export enum LogLevel {
  DEBUG = 'debug',
  INFO = 'info',
  WARN = 'warn',
  ERROR = 'error',
  FATAL = 'fatal'
}

/**
 * 命名规范验证工具
 */
export class NamingValidator {
  
  /**
   * 验证接口名称是否符合规范
   * @param name - 接口名称
   * @returns 是否符合规范
   */
  static validateInterfaceName(name: string): boolean {
    // PascalCase 规则：首字母大写，后续单词首字母大写
    const pascalCaseRegex = /^[A-Z][a-zA-Z0-9]*$/;
    return pascalCaseRegex.test(name);
  }

  /**
   * 验证字段名称是否符合规范
   * @param name - 字段名称
   * @returns 是否符合规范
   */
  static validateFieldName(name: string): boolean {
    // camelCase 规则：首字母小写，后续单词首字母大写
    const camelCaseRegex = /^[a-z][a-zA-Z0-9]*$/;
    return camelCaseRegex.test(name);
  }

  /**
   * 验证枚举名称是否符合规范
   * @param name - 枚举名称
   * @returns 是否符合规范
   */
  static validateEnumName(name: string): boolean {
    // 直接复用 PascalCase 规则，避免使用 this
    const pascalCaseRegex = /^[A-Z][a-zA-Z0-9]*$/;
    return pascalCaseRegex.test(name);
  }

  /**
   * 验证枚举值是否符合规范
   * @param value - 枚举值
   * @returns 是否符合规范
   */
  static validateEnumValue(value: string): boolean {
    // UPPER_SNAKE_CASE 规则：全大写，单词间用下划线分隔
    const upperSnakeCaseRegex = /^[A-Z][A-Z0-9_]*$/;
    return upperSnakeCaseRegex.test(value);
  }

  /**
   * 生成标准化的字段名
   * @param words - 单词数组
   * @returns 标准化的字段名
   */
  static generateFieldName(words: string[]): string {
    if (words.length === 0) return '';
    
    const camelCaseWords = words.map((word, index) => {
      const cleanWord = word.toLowerCase().replace(/[^a-z0-9]/g, '');
      return index === 0 ? cleanWord : cleanWord.charAt(0).toUpperCase() + cleanWord.slice(1);
    });
    
    return camelCaseWords.join('');
  }

  /**
   * 生成标准化的接口名
   * @param words - 单词数组
   * @returns 标准化的接口名
   */
  static generateInterfaceName(words: string[]): string {
    if (words.length === 0) return '';
    
    const pascalCaseWords = words.map(word => {
      const cleanWord = word.toLowerCase().replace(/[^a-z0-9]/g, '');
      return cleanWord.charAt(0).toUpperCase() + cleanWord.slice(1);
    });
    
    return pascalCaseWords.join('');
  }
}