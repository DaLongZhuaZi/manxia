/**
 * 跟踪器基类
 * 定义所有跟踪服务的通用接口
 */

import { logger } from '../../../Utils/Logger';
import {
  TrackRecord,
  TrackerId,
  TrackStatus,
  TrackSearchResult,
  UpdateTrackRecordParams
} from '../TrackingModels';

const TAG = 'BaseTracker';

/**
 * 跟踪器认证状态
 */
export interface TrackerAuthState {
  isLoggedIn: boolean;
  username: string;
  userId: string;
  accessToken: string;
  refreshToken: string;
  expiresAt: number;
}

/**
 * 跟踪器基类
 */
export abstract class BaseTracker {
  protected trackerId: TrackerId;
  protected name: string;
  protected authState: TrackerAuthState;

  constructor(trackerId: TrackerId, name: string) {
    this.trackerId = trackerId;
    this.name = name;
    this.authState = {
      isLoggedIn: false,
      username: '',
      userId: '',
      accessToken: '',
      refreshToken: '',
      expiresAt: 0
    };
  }

  /**
   * 获取跟踪器ID
   */
  public getTrackerId(): TrackerId {
    return this.trackerId;
  }

  /**
   * 获取跟踪器名称
   */
  public getName(): string {
    return this.name;
  }

  /**
   * 检查是否已登录
   */
  public isLoggedIn(): boolean {
    return this.authState.isLoggedIn;
  }

  /**
   * 获取认证状态
   */
  public getAuthState(): TrackerAuthState {
    return this.authState;
  }

  /**
   * 获取登录URL（用于OAuth）
   */
  public abstract getLoginUrl(): string;

  /**
   * 处理OAuth回调
   */
  public abstract handleAuthCallback(code: string): Promise<boolean>;

  /**
   * 登出
   */
  public abstract logout(): Promise<void>;

  /**
   * 搜索漫画/内容
   */
  public abstract search(query: string): Promise<TrackSearchResult[]>;

  /**
   * 绑定跟踪（将本地内容与远程服务关联）
   */
  public abstract bind(trackRecord: TrackRecord): Promise<boolean>;

  /**
   * 更新远程进度
   */
  public abstract updateRemoteProgress(trackRecord: TrackRecord): Promise<boolean>;

  /**
   * 获取远程进度
   */
  public abstract getRemoteProgress(remoteId: string): Promise<UpdateTrackRecordParams | null>;

  /**
   * 刷新访问令牌
   */
  public abstract refreshAccessToken(): Promise<boolean>;

  /**
   * 保存认证状态到本地存储
   */
  protected abstract saveAuthState(): Promise<void>;

  /**
   * 从本地存储加载认证状态
   */
  protected abstract loadAuthState(): Promise<void>;

  /**
   * 记录日志
   */
  protected log(message: string): void {
    logger.info(TAG, `[${this.name}] ${message}`);
  }

  /**
   * 记录错误日志
   */
  protected logError(message: string, error?: string): void {
    if (error) {
      logger.error(TAG, `[${this.name}] ${message}`, error);
    } else {
      logger.error(TAG, `[${this.name}] ${message}`);
    }
  }
}
