import { SafeUtils } from 'manxia_core/src/main/ets/Utils/SafeUtils';
/**
 * AniList 跟踪器
 * 实现与 AniList GraphQL API 的集成
 */

import { http } from '@kit.NetworkKit';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { SettingsManager } from 'manxia_core/src/main/ets/Framework/Managers/SettingsManager';
import { BaseTracker, TrackerAuthState } from './BaseTracker';
import {
  TrackRecord,
  TrackerId,
  TrackStatus,
  TrackSearchResult,
  UpdateTrackRecordParams
} from '../TrackingModels';

const TAG = 'AniListTracker';

// AniList API 配置
const ANILIST_CLIENT_ID = ''; // 需要用户在AniList开发者页面注册获取
const ANILIST_AUTH_URL = 'https://anilist.co/api/v2/oauth/authorize';
const ANILIST_TOKEN_URL = 'https://anilist.co/api/v2/oauth/token';
const ANILIST_GRAPHQL_URL = 'https://graphql.anilist.co';

// 设置键名
const ANILIST_AUTH_STATE_KEY = 'anilist_auth_state';

/**
 * AniList 用户信息接口
 */
interface AniListUserInfo {
  id: number;
  name: string;
}

/**
 * AniList GraphQL 变量接口
 */
interface GraphQLVariables {
  search?: string;
  mediaId?: number;
  userId?: number;
  status?: string;
  progress?: number;
  score?: number;
}

/**
 * GraphQL 响应接口
 */
interface GraphQLResponse {
  data: GraphQLData | null;
  errors?: GraphQLError[];
}

interface GraphQLError {
  message: string;
}

interface GraphQLData {
  Viewer?: AniListViewer;
  Page?: AniListPage;
  MediaList?: AniListMediaListEntry;
  SaveMediaListEntry?: AniListMediaListEntry;
}

interface AniListViewer {
  id: number;
  name: string;
}

interface AniListPage {
  media: AniListMedia[];
}

interface AniListMedia {
  id: number;
  title: AniListTitle;
  coverImage: AniListCoverImage | null;
  description: string | null;
  status: string | null;
  chapters: number | null;
  siteUrl: string | null;
  format: string | null;
  startDate: AniListDate | null;
}

interface AniListTitle {
  romaji: string | null;
  english: string | null;
  native: string | null;
}

interface AniListCoverImage {
  large: string | null;
}

interface AniListDate {
  year: number | null;
  month: number | null;
  day: number | null;
}

interface AniListMediaListEntry {
  id: number;
  progress: number;
  status: string;
  score: number;
  startedAt: AniListDate | null;
  completedAt: AniListDate | null;
}

/**
 * Token 响应接口
 */
interface TokenResponse {
  access_token: string;
  refresh_token: string;
  expires_in: number;
}

/**
 * 认证状态存储接口
 */
interface AuthStateStorage {
  isLoggedIn: boolean;
  username: string;
  userId: string;
  accessToken: string;
  refreshToken: string;
  expiresAt: number;
}

/**
 * 获取 AniList 状态字符串
 */
function getAniListStatusFromTrackStatus(status: TrackStatus): string {
  switch (status) {
    case TrackStatus.READING:
      return 'CURRENT';
    case TrackStatus.COMPLETED:
      return 'COMPLETED';
    case TrackStatus.ON_HOLD:
      return 'PAUSED';
    case TrackStatus.DROPPED:
      return 'DROPPED';
    case TrackStatus.PLAN_TO_READ:
      return 'PLANNING';
    case TrackStatus.REREADING:
      return 'REPEATING';
    default:
      return 'CURRENT';
  }
}

/**
 * 从 AniList 状态获取 TrackStatus
 */
function getTrackStatusFromAniList(anilistStatus: string): TrackStatus {
  switch (anilistStatus) {
    case 'CURRENT':
      return TrackStatus.READING;
    case 'COMPLETED':
      return TrackStatus.COMPLETED;
    case 'PAUSED':
      return TrackStatus.ON_HOLD;
    case 'DROPPED':
      return TrackStatus.DROPPED;
    case 'PLANNING':
      return TrackStatus.PLAN_TO_READ;
    case 'REPEATING':
      return TrackStatus.REREADING;
    default:
      return TrackStatus.UNKNOWN;
  }
}

/**
 * AniList 跟踪器实现
 */
export class AniListTracker extends BaseTracker {
  private settingsManager: SettingsManager;
  private httpSession: http.HttpRequest | null = null;

  constructor() {
    super(TrackerId.ANILIST, 'AniList');
    this.settingsManager = SettingsManager.getInstance();
  }

  /**
   * 初始化跟踪器
   */
  public async initialize(): Promise<void> {
    await this.loadAuthState();
    this.log('AniList 跟踪器初始化完成');
  }

  /**
   * 获取登录URL
   */
  public getLoginUrl(): string {
    if (!ANILIST_CLIENT_ID) {
      this.logError('AniList Client ID 未配置');
      return '';
    }
    
    const params = new Map<string, string>();
    params.set('client_id', ANILIST_CLIENT_ID);
    params.set('response_type', 'code');
    
    const queryString = Array.from(params.entries())
      .map(entry => `${entry[0]}=${encodeURIComponent(entry[1])}`)
      .join('&');
    
    return `${ANILIST_AUTH_URL}?${queryString}`;
  }

  /**
   * 处理OAuth回调
   */
  public async handleAuthCallback(code: string): Promise<boolean> {
    try {
      this.log(`处理OAuth回调: code=${code.substring(0, 10)}...`);
      
      // 使用授权码换取访问令牌
      const tokenResponse = await this.exchangeCodeForToken(code);
      if (!tokenResponse) {
        this.logError('获取访问令牌失败');
        return false;
      }

      // 获取用户信息
      const userInfo = await this.fetchUserInfo();
      if (!userInfo) {
        this.logError('获取用户信息失败');
        return false;
      }

      this.authState.isLoggedIn = true;
      this.authState.username = userInfo.name;
      this.authState.userId = String(userInfo.id);
      
      await this.saveAuthState();
      this.log(`登录成功: ${this.authState.username}`);
      
      return true;
    } catch (error) {
      this.logError('OAuth回调处理失败', String(error));
      return false;
    }
  }

  /**
   * 使用授权码换取访问令牌
   */
  private async exchangeCodeForToken(code: string): Promise<boolean> {
    try {
      const httpRequest = http.createHttp();
      
      const requestBody = JSON.stringify({
        grant_type: 'authorization_code',
        client_id: ANILIST_CLIENT_ID,
        code: code
      });

      const response = await httpRequest.request(ANILIST_TOKEN_URL, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Accept': 'application/json'
        },
        extraData: requestBody
      });

      httpRequest.destroy();

      if (response.responseCode === 200) {
        const data: TokenResponse = SafeUtils.parseObj(response.result as string) as TokenResponse;
        this.authState.accessToken = data.access_token;
        this.authState.refreshToken = data.refresh_token || '';
        this.authState.expiresAt = Date.now() + data.expires_in * 1000;
        return true;
      }

      this.logError(`获取令牌失败: ${response.responseCode}`);
      return false;
    } catch (error) {
      this.logError('获取令牌异常', String(error));
      return false;
    }
  }

  /**
   * 获取用户信息
   */
  private async fetchUserInfo(): Promise<AniListUserInfo | null> {
    const query = `
      query {
        Viewer {
          id
          name
        }
      }
    `;

    const result = await this.executeGraphQL(query, null);
    if (result && result.data && result.data.Viewer) {
      const viewer = result.data.Viewer;
      const userInfo: AniListUserInfo = {
        id: viewer.id,
        name: viewer.name
      };
      return userInfo;
    }
    return null;
  }

  /**
   * 处理 Implicit Grant 回调（用于移动端 OAuth）
   */
  public async handleImplicitAuthCallback(accessToken: string, expiresIn: number): Promise<boolean> {
    try {
      this.log(`处理 Implicit Grant 回调`);
      
      this.authState.accessToken = accessToken;
      this.authState.refreshToken = '';
      this.authState.expiresAt = expiresIn > 0 ? Date.now() + expiresIn * 1000 : 0;

      // 获取用户信息
      const userInfo = await this.fetchUserInfo();
      if (!userInfo) {
        this.logError('获取用户信息失败');
        return false;
      }

      this.authState.isLoggedIn = true;
      this.authState.username = userInfo.name;
      this.authState.userId = String(userInfo.id);
      
      await this.saveAuthState();
      this.log(`登录成功: ${this.authState.username}`);
      
      return true;
    } catch (error) {
      this.logError('Implicit Grant 回调处理失败', String(error));
      return false;
    }
  }

  /**
   * 登出
   */
  public async logout(): Promise<void> {
    this.authState = {
      isLoggedIn: false,
      username: '',
      userId: '',
      accessToken: '',
      refreshToken: '',
      expiresAt: 0
    };
    await this.saveAuthState();
    this.log('已登出');
  }

  /**
   * 搜索漫画
   */
  public async search(query: string): Promise<TrackSearchResult[]> {
    if (!this.isLoggedIn()) {
      this.logError('未登录，无法搜索');
      return [];
    }

    const graphqlQuery = `
      query ($search: String) {
        Page(perPage: 20) {
          media(search: $search, type: MANGA) {
            id
            title {
              romaji
              english
              native
            }
            coverImage {
              large
            }
            description
            status
            chapters
            siteUrl
            format
            startDate {
              year
              month
              day
            }
          }
        }
      }
    `;

    const variables: GraphQLVariables = { search: query };
    const result = await this.executeGraphQL(graphqlQuery, variables);

    if (!result || !result.data || !result.data.Page) {
      return [];
    }
    const page: AniListPage = result.data.Page;
    if (!page.media) {
      return [];
    }

    const mediaList: AniListMedia[] = page.media;
    const results: TrackSearchResult[] = [];

    for (let i = 0; i < mediaList.length; i++) {
      const media: AniListMedia = mediaList[i];
      const title: AniListTitle = media.title;
      const coverImage: AniListCoverImage | null = media.coverImage;
      const startDate: AniListDate | null = media.startDate;

      const displayTitle: string = title.english || title.romaji || title.native || '';
      const coverUrl: string = coverImage ? (coverImage.large || '') : '';
      const startDateStr: string = startDate && startDate.year ? `${startDate.year}-${startDate.month || 1}-${startDate.day || 1}` : '';

      const searchResult: TrackSearchResult = {
        remoteId: String(media.id),
        title: displayTitle,
        coverUrl: coverUrl,
        summary: media.description || '',
        status: media.status || '',
        totalChapters: media.chapters || 0,
        trackingUrl: media.siteUrl || '',
        publishingType: media.format || '',
        startDate: startDateStr
      };
      results.push(searchResult);
    }

    this.log(`搜索完成: 找到 ${results.length} 个结果`);
    return results;
  }

  /**
   * 绑定跟踪
   */
  public async bind(trackRecord: TrackRecord): Promise<boolean> {
    if (!this.isLoggedIn()) {
      this.logError('未登录，无法绑定');
      return false;
    }

    // 在AniList上添加到列表
    const mutation = `
      mutation ($mediaId: Int, $status: MediaListStatus) {
        SaveMediaListEntry(mediaId: $mediaId, status: $status) {
          id
          status
          progress
        }
      }
    `;

    const variables: GraphQLVariables = {
      mediaId: parseInt(trackRecord.remoteId),
      status: getAniListStatusFromTrackStatus(trackRecord.status || TrackStatus.PLAN_TO_READ)
    };

    const result = await this.executeGraphQL(mutation, variables);
    if (result && result.data && result.data.SaveMediaListEntry) {
      this.log(`绑定成功: remoteId=${trackRecord.remoteId}`);
      return true;
    }

    this.logError('绑定失败');
    return false;
  }

  /**
   * 更新远程进度
   */
  public async updateRemoteProgress(trackRecord: TrackRecord): Promise<boolean> {
    if (!this.isLoggedIn()) {
      this.logError('未登录，无法更新进度');
      return false;
    }

    const mutation = `
      mutation ($mediaId: Int, $progress: Int, $status: MediaListStatus, $score: Float) {
        SaveMediaListEntry(mediaId: $mediaId, progress: $progress, status: $status, score: $score) {
          id
          progress
          status
          score
        }
      }
    `;

    const variables: GraphQLVariables = {
      mediaId: parseInt(trackRecord.remoteId),
      progress: Math.floor(trackRecord.lastChapterRead),
      status: getAniListStatusFromTrackStatus(trackRecord.status)
    };

    if (trackRecord.score > 0) {
      variables.score = trackRecord.score;
    }

    const result = await this.executeGraphQL(mutation, variables);
    if (result && result.data && result.data.SaveMediaListEntry) {
      this.log(`进度更新成功: remoteId=${trackRecord.remoteId}, progress=${trackRecord.lastChapterRead}`);
      return true;
    }

    this.logError('进度更新失败');
    return false;
  }

  /**
   * 获取远程进度
   */
  public async getRemoteProgress(remoteId: string): Promise<UpdateTrackRecordParams | null> {
    if (!this.isLoggedIn()) {
      this.logError('未登录，无法获取进度');
      return null;
    }

    const query = `
      query ($mediaId: Int, $userId: Int) {
        MediaList(mediaId: $mediaId, userId: $userId) {
          progress
          status
          score
          startedAt {
            year
            month
            day
          }
          completedAt {
            year
            month
            day
          }
        }
      }
    `;

    const variables: GraphQLVariables = {
      mediaId: parseInt(remoteId),
      userId: parseInt(this.authState.userId)
    };

    const result = await this.executeGraphQL(query, variables);
    if (!result || !result.data || !result.data.MediaList) {
      return null;
    }

    const mediaList: AniListMediaListEntry = result.data.MediaList;
    const anilistStatus: string = mediaList.status;
    const trackStatus: TrackStatus = getTrackStatusFromAniList(anilistStatus);

    const params: UpdateTrackRecordParams = {
      lastChapterRead: mediaList.progress || 0,
      score: mediaList.score || 0,
      status: trackStatus
    };

    // 解析日期
    const startedAt: AniListDate | null = mediaList.startedAt;
    if (startedAt && startedAt.year) {
      params.startedReadingDate = new Date(
        startedAt.year,
        (startedAt.month || 1) - 1,
        startedAt.day || 1
      ).getTime();
    }

    const completedAt: AniListDate | null = mediaList.completedAt;
    if (completedAt && completedAt.year) {
      params.finishedReadingDate = new Date(
        completedAt.year,
        (completedAt.month || 1) - 1,
        completedAt.day || 1
      ).getTime();
    }

    return params;
  }

  /**
   * 刷新访问令牌
   */
  public async refreshAccessToken(): Promise<boolean> {
    // AniList 的访问令牌是长期有效的，通常不需要刷新
    // 如果令牌过期，用户需要重新登录
    if (this.authState.expiresAt > 0 && Date.now() > this.authState.expiresAt) {
      this.log('访问令牌已过期，需要重新登录');
      await this.logout();
      return false;
    }
    return true;
  }

  /**
   * 执行 GraphQL 查询
   */
  private async executeGraphQL(query: string, variables: GraphQLVariables | null): Promise<GraphQLResponse | null> {
    try {
      const httpRequest = http.createHttp();

      const requestBody = JSON.stringify({
        query: query,
        variables: variables || {}
      });

      const response = await httpRequest.request(ANILIST_GRAPHQL_URL, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': `Bearer ${this.authState.accessToken}`
        },
        extraData: requestBody
      });

      httpRequest.destroy();

      if (response.responseCode === 200) {
        return SafeUtils.parseObj(response.result as string) as GraphQLResponse;
      }

      this.logError(`GraphQL请求失败: ${response.responseCode}`);
      return null;
    } catch (error) {
      this.logError('GraphQL请求异常', String(error));
      return null;
    }
  }

  /**
   * 保存认证状态
   */
  protected async saveAuthState(): Promise<void> {
    try {
      const stateJson = JSON.stringify({
        isLoggedIn: this.authState.isLoggedIn,
        username: this.authState.username,
        userId: this.authState.userId,
        accessToken: this.authState.accessToken,
        refreshToken: this.authState.refreshToken,
        expiresAt: this.authState.expiresAt
      });
      await this.settingsManager.setString(ANILIST_AUTH_STATE_KEY, stateJson);
      this.log('认证状态已保存');
    } catch (error) {
      this.logError('保存认证状态失败', String(error));
    }
  }

  /**
   * 加载认证状态
   */
  protected async loadAuthState(): Promise<void> {
    try {
      const stateJson = this.settingsManager.getString(ANILIST_AUTH_STATE_KEY, '');
      if (stateJson) {
        const state: AuthStateStorage = SafeUtils.parseObj(stateJson) as AuthStateStorage;
        this.authState = {
          isLoggedIn: state.isLoggedIn || false,
          username: state.username || '',
          userId: state.userId || '',
          accessToken: state.accessToken || '',
          refreshToken: state.refreshToken || '',
          expiresAt: state.expiresAt || 0
        };
        this.log(`认证状态已加载: isLoggedIn=${this.authState.isLoggedIn}`);
      }
    } catch (error) {
      this.logError('加载认证状态失败', String(error));
    }
  }
}

// 导出单例
let aniListTrackerInstance: AniListTracker | null = null;

export function getAniListTracker(): AniListTracker {
  if (!aniListTrackerInstance) {
    aniListTrackerInstance = new AniListTracker();
  }
  return aniListTrackerInstance;
}
