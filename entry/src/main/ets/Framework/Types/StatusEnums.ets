// 文件路径: src/main/ets/Framework/Types/StatusEnums.ets
/**
 * 统一状态枚举系统
 * 符合ArkTS规范的类型安全设计
 * 统一管理所有状态相关的枚举定义
 */

import { logger } from '../../Utils/Logger';

const TAG = 'StatusEnums';

/**
 * 漫画状态枚举
 */
export enum MangaStatus {
  /** 连载中 */
  ONGOING = 'ONGOING',
  /** 已完结 */
  COMPLETED = 'COMPLETED',
  /** 暂停/休刊 */
  HIATUS = 'HIATUS',
  /** 已取消 */
  CANCELLED = 'CANCELLED',
  /** 未知状态 */
  UNKNOWN = 'UNKNOWN'
}

/**
 * 下载任务状态枚举
 */
export enum DownloadStatus {
  /** 等待中 */
  PENDING = 'pending',
  /** 下载中 */
  DOWNLOADING = 'downloading',
  /** 已完成 */
  COMPLETED = 'completed',
  /** 失败 */
  FAILED = 'failed',
  /** 已暂停 */
  PAUSED = 'paused',
  /** 已取消 */
  CANCELLED = 'cancelled'
}

/**
 * 阅读状态枚举
 */
export enum ReadingStatus {
  /** 未读 */
  UNREAD = 'UNREAD',
  /** 阅读中 */
  READING = 'READING',
  /** 已读完 */
  COMPLETED = 'COMPLETED',
  /** 已收藏 */
  BOOKMARKED = 'BOOKMARKED'
}

/**
 * 缓存状态枚举
 */
export enum CacheStatus {
  /** 未缓存 */
  NOT_CACHED = 'NOT_CACHED',
  /** 缓存中 */
  CACHING = 'CACHING',
  /** 已缓存 */
  CACHED = 'CACHED',
  /** 缓存过期 */
  EXPIRED = 'EXPIRED',
  /** 缓存失败 */
  FAILED = 'FAILED'
}

/**
 * 网络状态枚举
 */
export enum NetworkStatus {
  /** 在线 */
  ONLINE = 'ONLINE',
  /** 离线 */
  OFFLINE = 'OFFLINE',
  /** 连接中 */
  CONNECTING = 'CONNECTING',
  /** 连接失败 */
  FAILED = 'FAILED'
}

/**
 * 枚举值常量
 */
const MANGA_STATUS_VALUES: MangaStatus[] = [
  MangaStatus.ONGOING,
  MangaStatus.COMPLETED,
  MangaStatus.HIATUS,
  MangaStatus.CANCELLED,
  MangaStatus.UNKNOWN
];

const DOWNLOAD_STATUS_VALUES: DownloadStatus[] = [
  DownloadStatus.PENDING,
  DownloadStatus.DOWNLOADING,
  DownloadStatus.COMPLETED,
  DownloadStatus.FAILED,
  DownloadStatus.PAUSED,
  DownloadStatus.CANCELLED
];

/**
 * 状态转换工具类
 */
export class StatusConverter {
  /**
   * 将字符串转换为MangaStatus枚举
   */
  static toMangaStatus(status: string | undefined | null): MangaStatus {
    if (!status || status.trim() === '') {
      return MangaStatus.UNKNOWN;
    }
    
    const normalizedStatus = status.toUpperCase().trim();
    
    switch (normalizedStatus) {
      case 'ONGOING':
      case '连载中':
      case '更新中':
      case 'SERIALIZING':
        return MangaStatus.ONGOING;
        
      case 'COMPLETED':
      case '已完结':
      case '完结':
      case 'FINISHED':
        return MangaStatus.COMPLETED;
        
      case 'HIATUS':
      case '暂停':
      case '休刊':
      case 'PAUSED':
        return MangaStatus.HIATUS;
        
      case 'CANCELLED':
      case '已取消':
      case '停刊':
      case 'DROPPED':
        return MangaStatus.CANCELLED;
        
      case 'UNKNOWN':
      case 'UNKNOWN_STATUS':
      case '未知':
        // 数据库默认值或未设置状态，不打印警告
        return MangaStatus.UNKNOWN;
        
      default:
        // 只有真正无法识别的状态才打印警告
        logger.warn(TAG, `⚠️ 警告 [StatusEnums] 未知的漫画状态: ${status}，使用默认值 UNKNOWN`);
        return MangaStatus.UNKNOWN;
    }
  }

  /**
   * 将字符串转换为DownloadStatus枚举
   */
  static toDownloadStatus(status: string): DownloadStatus {
    const normalizedStatus = status.toUpperCase().trim();
    
    switch (normalizedStatus) {
      case 'PENDING':
      case '等待中':
      case 'WAITING':
        return DownloadStatus.PENDING;
        
      case 'DOWNLOADING':
      case '下载中':
      case 'IN_PROGRESS':
        return DownloadStatus.DOWNLOADING;
        
      case 'COMPLETED':
      case '已完成':
      case 'FINISHED':
        return DownloadStatus.COMPLETED;
        
      case 'FAILED':
      case '失败':
      case 'ERROR':
        return DownloadStatus.FAILED;
        
      case 'PAUSED':
      case '已暂停':
      case '暂停':
        return DownloadStatus.PAUSED;
        
      case 'CANCELLED':
      case '已取消':
      case '取消':
        return DownloadStatus.CANCELLED;
        
      default:
        logger.warn(TAG, `未知的下载状态: ${status}，使用默认值 PENDING`);
        return DownloadStatus.PENDING;
    }
  }

  /**
   * 将MangaStatus转换为显示文本
   */
  static mangaStatusToDisplayText(status: MangaStatus): string {
    switch (status) {
      case MangaStatus.ONGOING:
        return '连载中';
      case MangaStatus.COMPLETED:
        return '已完结';
      case MangaStatus.HIATUS:
        return '暂停';
      case MangaStatus.CANCELLED:
        return '已取消';
      case MangaStatus.UNKNOWN:
        return '未知';
      default:
        return '未知';
    }
  }

  /**
   * 将DownloadStatus转换为显示文本
   */
  static downloadStatusToDisplayText(status: DownloadStatus): string {
    switch (status) {
      case DownloadStatus.PENDING:
        return '等待中';
      case DownloadStatus.DOWNLOADING:
        return '下载中';
      case DownloadStatus.COMPLETED:
        return '已完成';
      case DownloadStatus.FAILED:
        return '失败';
      case DownloadStatus.PAUSED:
        return '已暂停';
      case DownloadStatus.CANCELLED:
        return '已取消';
      default:
        return '未知';
    }
  }

  /**
   * 检查状态是否为终态（不会再变化的状态）
   */
  static isFinalStatus(status: MangaStatus | DownloadStatus): boolean {
    if (MANGA_STATUS_VALUES.includes(status as MangaStatus)) {
      const mangaStatus = status as MangaStatus;
      return mangaStatus === MangaStatus.COMPLETED || 
             mangaStatus === MangaStatus.CANCELLED;
    }
    
    if (DOWNLOAD_STATUS_VALUES.includes(status as DownloadStatus)) {
      const downloadStatus = status as DownloadStatus;
      return downloadStatus === DownloadStatus.COMPLETED || 
             downloadStatus === DownloadStatus.FAILED || 
             downloadStatus === DownloadStatus.CANCELLED;
    }
    
    return false;
  }

  /**
   * 检查状态是否为进行中状态
   */
  static isActiveStatus(status: MangaStatus | DownloadStatus): boolean {
    if (MANGA_STATUS_VALUES.includes(status as MangaStatus)) {
      const mangaStatus = status as MangaStatus;
      return mangaStatus === MangaStatus.ONGOING;
    }
    
    if (DOWNLOAD_STATUS_VALUES.includes(status as DownloadStatus)) {
      const downloadStatus = status as DownloadStatus;
      return downloadStatus === DownloadStatus.DOWNLOADING || 
             downloadStatus === DownloadStatus.PENDING;
    }
    
    return false;
  }
}

/**
 * 状态验证工具类
 */
export class StatusValidator {
  /**
   * 验证MangaStatus是否有效
   */
  static isValidMangaStatus(status: string): boolean {
    return MANGA_STATUS_VALUES.includes(status as MangaStatus);
  }

  /**
   * 验证DownloadStatus是否有效
   */
  static isValidDownloadStatus(status: string): boolean {
    return DOWNLOAD_STATUS_VALUES.includes(status as DownloadStatus);
  }

  /**
   * 验证状态转换是否合法
   */
  static isValidStatusTransition(from: DownloadStatus, to: DownloadStatus): boolean {
    // 定义合法的状态转换规则
    const validTransitions: Record<DownloadStatus, DownloadStatus[]> = {
      [DownloadStatus.PENDING]: [DownloadStatus.DOWNLOADING, DownloadStatus.CANCELLED],
      [DownloadStatus.DOWNLOADING]: [DownloadStatus.COMPLETED, DownloadStatus.FAILED, DownloadStatus.PAUSED, DownloadStatus.CANCELLED],
      [DownloadStatus.PAUSED]: [DownloadStatus.DOWNLOADING, DownloadStatus.CANCELLED],
      [DownloadStatus.COMPLETED]: [], // 终态，不能转换
      [DownloadStatus.FAILED]: [DownloadStatus.PENDING], // 可以重试
      [DownloadStatus.CANCELLED]: [DownloadStatus.PENDING] // 可以重新开始
    };

    const allowedTransitions = validTransitions[from];
    return allowedTransitions ? allowedTransitions.includes(to) : false;
  }
}

// 导出便捷函数
export function toMangaStatus(status: string): MangaStatus {
  return StatusConverter.toMangaStatus(status);
}

export function toDownloadStatus(status: string): DownloadStatus {
  return StatusConverter.toDownloadStatus(status);
}

export function getMangaStatusDisplayText(status: MangaStatus): string {
  return StatusConverter.mangaStatusToDisplayText(status);
}

export function getDownloadStatusDisplayText(status: DownloadStatus): string {
  return StatusConverter.downloadStatusToDisplayText(status);
}

/**
 * 判断是否为部分下载状态（已下载部分页面但有失败）
 */
export function isPartiallyDownloaded(downloadedCount: number, totalCount: number, status: DownloadStatus): boolean {
  return status === DownloadStatus.FAILED && downloadedCount > 0 && downloadedCount < totalCount;
}

/**
 * 获取部分下载状态描述文本
 */
export function getPartialDownloadText(downloadedCount: number, totalCount: number): string {
  return `部分缓存 (${downloadedCount}/${totalCount}页)`;
}