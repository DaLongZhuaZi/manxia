/**
 * 跟踪服务模型定义
 * 定义跟踪记录、跟踪服务类型等数据结构
 */

/**
 * 跟踪服务ID枚举
 */
export enum TrackerId {
  UNKNOWN = 0,
  MY_ANIME_LIST = 1,
  ANILIST = 2,
  KITSU = 3,
  MANGA_UPDATES = 4,
  BANGUMI = 5,
  SUWAYOMI = 6,
  KOMGA = 7
}

/**
 * 跟踪服务信息
 */
export interface TrackerInfo {
  id: TrackerId;
  name: string;
  icon: string;
  supportsScoring: boolean;
  scoreFormat: 'POINT_10' | 'POINT_100' | 'POINT_5' | 'POINT_10_DECIMAL';
  supportsPrivate: boolean;
  requiresAuth: boolean;
}

/**
 * 跟踪服务列表
 */
export const TRACKER_INFO_LIST: TrackerInfo[] = [
  {
    id: TrackerId.MY_ANIME_LIST,
    name: 'MyAnimeList',
    icon: 'mal_icon',
    supportsScoring: true,
    scoreFormat: 'POINT_10',
    supportsPrivate: false,
    requiresAuth: true
  },
  {
    id: TrackerId.ANILIST,
    name: 'AniList',
    icon: 'anilist_icon',
    supportsScoring: true,
    scoreFormat: 'POINT_10',
    supportsPrivate: true,
    requiresAuth: true
  },
  {
    id: TrackerId.KITSU,
    name: 'Kitsu',
    icon: 'kitsu_icon',
    supportsScoring: true,
    scoreFormat: 'POINT_10',
    supportsPrivate: true,
    requiresAuth: true
  },
  {
    id: TrackerId.MANGA_UPDATES,
    name: 'MangaUpdates',
    icon: 'mangaupdates_icon',
    supportsScoring: true,
    scoreFormat: 'POINT_10',
    supportsPrivate: false,
    requiresAuth: true
  },
  {
    id: TrackerId.BANGUMI,
    name: 'Bangumi',
    icon: 'bangumi_icon',
    supportsScoring: true,
    scoreFormat: 'POINT_10',
    supportsPrivate: false,
    requiresAuth: true
  },
  {
    id: TrackerId.SUWAYOMI,
    name: 'Suwayomi',
    icon: 'suwayomi_icon',
    supportsScoring: false,
    scoreFormat: 'POINT_10',
    supportsPrivate: false,
    requiresAuth: true
  },
  {
    id: TrackerId.KOMGA,
    name: 'Komga',
    icon: 'komga_icon',
    supportsScoring: false,
    scoreFormat: 'POINT_10',
    supportsPrivate: false,
    requiresAuth: true
  }
];

/**
 * 阅读状态枚举
 */
export enum TrackStatus {
  UNKNOWN = 0,
  READING = 1,
  COMPLETED = 2,
  ON_HOLD = 3,
  DROPPED = 4,
  PLAN_TO_READ = 5,
  REREADING = 6
}

/**
 * 获取阅读状态显示名称
 */
export function getTrackStatusName(status: TrackStatus): string {
  switch (status) {
    case TrackStatus.UNKNOWN:
      return '未知';
    case TrackStatus.READING:
      return '阅读中';
    case TrackStatus.COMPLETED:
      return '已完成';
    case TrackStatus.ON_HOLD:
      return '暂停';
    case TrackStatus.DROPPED:
      return '弃坑';
    case TrackStatus.PLAN_TO_READ:
      return '计划阅读';
    case TrackStatus.REREADING:
      return '重读中';
    default:
      return '未知';
  }
}

/**
 * 同步状态枚举
 */
export enum SyncStatus {
  SYNCED = 'synced',
  PENDING = 'pending',
  FAILED = 'failed'
}

/**
 * 内容类型枚举
 */
export enum TrackContentType {
  MANGA = 'manga',
  EBOOK = 'ebook',
  NOVEL = 'novel'
}

/**
 * 跟踪记录接口
 */
export interface TrackRecord {
  id: string;
  contentId: string;
  contentType: TrackContentType;
  trackerId: TrackerId;
  remoteId: string;
  remoteTitle: string;
  remoteUrl: string;
  lastChapterRead: number;
  totalChapters: number;
  score: number;
  status: TrackStatus;
  startedReadingDate: number;
  finishedReadingDate: number;
  lastSyncTime: number;
  syncStatus: SyncStatus;
  createTime: number;
  updateTime: number;
}

/**
 * 创建跟踪记录的参数
 */
export interface CreateTrackRecordParams {
  contentId: string;
  contentType: TrackContentType;
  trackerId: TrackerId;
  remoteId: string;
  remoteTitle?: string;
  remoteUrl?: string;
}

/**
 * 更新跟踪记录的参数
 */
export interface UpdateTrackRecordParams {
  lastChapterRead?: number;
  totalChapters?: number;
  score?: number;
  status?: TrackStatus;
  startedReadingDate?: number;
  finishedReadingDate?: number;
  syncStatus?: SyncStatus;
}

/**
 * 跟踪搜索结果
 */
export interface TrackSearchResult {
  remoteId: string;
  title: string;
  coverUrl: string;
  summary: string;
  status: string;
  totalChapters: number;
  trackingUrl: string;
  publishingType: string;
  startDate: string;
}

/**
 * 获取跟踪服务信息
 */
export function getTrackerInfo(trackerId: TrackerId): TrackerInfo | undefined {
  return TRACKER_INFO_LIST.find(info => info.id === trackerId);
}

/**
 * 获取跟踪服务名称
 */
export function getTrackerName(trackerId: TrackerId): string {
  const info = getTrackerInfo(trackerId);
  return info ? info.name : '未知服务';
}

/**
 * 获取状态显示名称
 */
export function getStatusName(status: TrackStatus): string {
  return getTrackStatusName(status);
}
