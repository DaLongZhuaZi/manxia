import { abilityAccessCtrl, bundleManager, common, Permissions } from '@kit.AbilityKit';
import motion from '@ohos.multimodalAwareness.motion';
import { logger } from '../../Utils/Logger';
import { getContext, isInitialized as isGlobalContextInitialized } from '../../GlobalContext';

const TAG = 'HoldingAwarenessManager';

interface BundleAppInfoWithTokenAccess {
  accessTokenId?: number;
}

interface BundleInfoWithTokenAccess {
  appInfo?: BundleAppInfoWithTokenAccess;
}

interface BusinessErrorLike {
  code?: number;
  message?: string;
}

type HoldingAwarenessError = Error | BusinessErrorLike | Object | string | number | boolean | null | undefined;

export enum HoldingUiAnchor {
  LEFT = 'left',
  RIGHT = 'right'
}

export enum HoldingAwarenessSide {
  UNKNOWN = 'unknown',
  NONE = 'none',
  LEFT = 'left',
  RIGHT = 'right',
  BOTH = 'both'
}

export enum HoldingAwarenessSource {
  DEFAULT = 'default',
  HOLDING_HAND = 'holding_hand',
  OPERATING_HAND = 'operating_hand',
  COMBINED = 'combined'
}

export enum HoldingAwarenessConfidence {
  FALLBACK = 'fallback',
  INFERRED = 'inferred',
  EXACT = 'exact'
}

export interface HoldingAwarenessSnapshot {
  preferredAnchor: HoldingUiAnchor;
  side: HoldingAwarenessSide;
  source: HoldingAwarenessSource;
  confidence: HoldingAwarenessConfidence;
  available: boolean;
  preciseSupported: boolean;
  detectGestureGranted: boolean;
  activityMotionGranted: boolean;
  lastUpdatedAt: number;
}

export type HoldingAwarenessListener = (snapshot: HoldingAwarenessSnapshot) => void;

export const HOLDING_AWARENESS_PREFERRED_ANCHOR_KEY = 'holding_awareness_preferred_anchor';
export const HOLDING_AWARENESS_SIDE_KEY = 'holding_awareness_side';
export const HOLDING_AWARENESS_SOURCE_KEY = 'holding_awareness_source';
export const HOLDING_AWARENESS_CONFIDENCE_KEY = 'holding_awareness_confidence';
export const HOLDING_AWARENESS_AVAILABLE_KEY = 'holding_awareness_available';
export const HOLDING_AWARENESS_PRECISE_SUPPORTED_KEY = 'holding_awareness_precise_supported';
export const HOLDING_AWARENESS_DETECT_GESTURE_GRANTED_KEY = 'holding_awareness_detect_gesture_granted';
export const HOLDING_AWARENESS_ACTIVITY_MOTION_GRANTED_KEY = 'holding_awareness_activity_motion_granted';
export const HOLDING_AWARENESS_LAST_UPDATED_KEY = 'holding_awareness_last_updated';

const DEFAULT_SNAPSHOT: HoldingAwarenessSnapshot = {
  preferredAnchor: HoldingUiAnchor.RIGHT,
  side: HoldingAwarenessSide.UNKNOWN,
  source: HoldingAwarenessSource.DEFAULT,
  confidence: HoldingAwarenessConfidence.FALLBACK,
  available: false,
  preciseSupported: false,
  detectGestureGranted: false,
  activityMotionGranted: false,
  lastUpdatedAt: 0
};

function cloneHoldingAwarenessSnapshot(snapshot: HoldingAwarenessSnapshot): HoldingAwarenessSnapshot {
  return {
    preferredAnchor: snapshot.preferredAnchor,
    side: snapshot.side,
    source: snapshot.source,
    confidence: snapshot.confidence,
    available: snapshot.available,
    preciseSupported: snapshot.preciseSupported,
    detectGestureGranted: snapshot.detectGestureGranted,
    activityMotionGranted: snapshot.activityMotionGranted,
    lastUpdatedAt: snapshot.lastUpdatedAt
  };
}

export class HoldingAwarenessManager {
  private static instance: HoldingAwarenessManager | null = null;

  private currentSnapshot: HoldingAwarenessSnapshot = cloneHoldingAwarenessSnapshot(DEFAULT_SNAPSHOT);
  private listeners: Set<HoldingAwarenessListener> = new Set();
  private isInitialized: boolean = false;
  private isInitializing: boolean = false;
  private selfTokenId: number = -1;
  private holdingSubscribed: boolean = false;
  private operatingSubscribed: boolean = false;
  private detectGestureGranted: boolean = false;
  private activityMotionGranted: boolean = false;
  private latestHoldingStatus: motion.HoldingHandStatus = motion.HoldingHandStatus.UNKNOWN_STATUS;
  private latestOperatingStatus: motion.OperatingHandStatus = motion.OperatingHandStatus.UNKNOWN_STATUS;

  private readonly holdingHandChangedCallback = (status: motion.HoldingHandStatus): void => {
    this.latestHoldingStatus = status;
    logger.info(TAG, `收到智感握姿变化：${this.describeHoldingHandStatus(status)}`);
    this.publishSnapshot(this.buildSnapshot(), 'holding_hand_changed');
  };

  private readonly operatingHandChangedCallback = (status: motion.OperatingHandStatus): void => {
    this.latestOperatingStatus = status;
    logger.info(TAG, `收到操作手变化：${this.describeOperatingHandStatus(status)}`);
    this.publishSnapshot(this.buildSnapshot(), 'operating_hand_changed');
  };

  private constructor() {}

  public static getInstance(): HoldingAwarenessManager {
    if (!HoldingAwarenessManager.instance) {
      HoldingAwarenessManager.instance = new HoldingAwarenessManager();
    }
    return HoldingAwarenessManager.instance;
  }

  public async initialize(): Promise<void> {
    this.ensureStorageDefaults();
    if (this.isInitialized || this.isInitializing) {
      logger.debug(TAG, `跳过初始化：isInitialized=${this.isInitialized}, isInitializing=${this.isInitializing}`);
      return;
    }

    logger.info(TAG, '开始初始化智感握持管理器');
    this.isInitializing = true;
    try {
      await this.refreshPermissionCache();
      await this.tryEnableSubscriptions('initialize');
      this.isInitialized = true;
      logger.info(TAG, '智感握持管理器初始化完成');
    } catch (error) {
      logger.warn(TAG, `初始化智感握持管理器失败：${this.extractErrorMessage(error)}`);
    } finally {
      this.isInitializing = false;
      this.publishSnapshot(this.buildSnapshot(), 'initialize_finalize');
    }
  }

  public async resume(): Promise<void> {
    logger.debug(TAG, '收到恢复请求，准备刷新握持感知状态');
    if (!this.isInitialized) {
      await this.initialize();
      return;
    }
    await this.refreshPermissionCache();
    await this.tryEnableSubscriptions('resume');
  }

  public async requestActivityMotionPermission(
    context?: common.UIAbilityContext
  ): Promise<boolean> {
    try {
      if (await this.checkPermission('ohos.permission.ACTIVITY_MOTION')) {
        this.activityMotionGranted = true;
        logger.info(TAG, 'ACTIVITY_MOTION 权限已存在，直接启用操作手感知能力');
        await this.tryEnableSubscriptions('activity_motion_already_granted');
        return true;
      }

      const hostContext = context ?? this.getAbilityContext();
      if (!hostContext) {
        logger.warn(TAG, '无法申请 ACTIVITY_MOTION 权限：UIAbilityContext 为空');
        return false;
      }

      logger.info(TAG, '开始向用户申请 ACTIVITY_MOTION 权限');
      const atManager = abilityAccessCtrl.createAtManager();
      const permissions: Permissions[] = ['ohos.permission.ACTIVITY_MOTION'];
      const result = await atManager.requestPermissionsFromUser(hostContext, permissions);
      const granted = result.authResults.length > 0 && result.authResults[0] === 0;
      this.activityMotionGranted = granted || await this.checkPermission('ohos.permission.ACTIVITY_MOTION');
      logger.info(
        TAG,
        `ACTIVITY_MOTION 权限申请完成：弹窗结果=${this.describeBoolean(granted)}，最终授权=${this.describeBoolean(this.activityMotionGranted)}`
      );
      await this.tryEnableSubscriptions('request_activity_motion');
      return this.activityMotionGranted;
    } catch (error) {
      logger.warn(TAG, `申请 ACTIVITY_MOTION 权限失败：${this.extractErrorMessage(error)}`);
      return false;
    }
  }

  public getSnapshot(): HoldingAwarenessSnapshot {
    return cloneHoldingAwarenessSnapshot(this.currentSnapshot);
  }

  public getPreferredAnchor(): HoldingUiAnchor {
    return this.currentSnapshot.preferredAnchor;
  }

  public addListener(listener: HoldingAwarenessListener): void {
    this.listeners.add(listener);
  }

  public removeListener(listener: HoldingAwarenessListener): void {
    this.listeners.delete(listener);
  }

  public destroy(): void {
    logger.info(TAG, '销毁智感握持管理器，准备取消所有监听');
    this.teardownSubscriptions();
    this.listeners.clear();
    this.isInitialized = false;
  }

  private ensureStorageDefaults(): void {
    AppStorage.setOrCreate(HOLDING_AWARENESS_PREFERRED_ANCHOR_KEY, DEFAULT_SNAPSHOT.preferredAnchor);
    AppStorage.setOrCreate(HOLDING_AWARENESS_SIDE_KEY, DEFAULT_SNAPSHOT.side);
    AppStorage.setOrCreate(HOLDING_AWARENESS_SOURCE_KEY, DEFAULT_SNAPSHOT.source);
    AppStorage.setOrCreate(HOLDING_AWARENESS_CONFIDENCE_KEY, DEFAULT_SNAPSHOT.confidence);
    AppStorage.setOrCreate(HOLDING_AWARENESS_AVAILABLE_KEY, DEFAULT_SNAPSHOT.available);
    AppStorage.setOrCreate(HOLDING_AWARENESS_PRECISE_SUPPORTED_KEY, DEFAULT_SNAPSHOT.preciseSupported);
    AppStorage.setOrCreate(HOLDING_AWARENESS_DETECT_GESTURE_GRANTED_KEY, DEFAULT_SNAPSHOT.detectGestureGranted);
    AppStorage.setOrCreate(HOLDING_AWARENESS_ACTIVITY_MOTION_GRANTED_KEY, DEFAULT_SNAPSHOT.activityMotionGranted);
    AppStorage.setOrCreate(HOLDING_AWARENESS_LAST_UPDATED_KEY, DEFAULT_SNAPSHOT.lastUpdatedAt);
  }

  private getAbilityContext(): common.UIAbilityContext | undefined {
    if (!isGlobalContextInitialized()) {
      return undefined;
    }
    try {
      return getContext();
    } catch (_error) {
      return undefined;
    }
  }

  private async ensureSelfTokenId(): Promise<number> {
    if (this.selfTokenId >= 0) {
      return this.selfTokenId;
    }

    const info = await bundleManager.getBundleInfoForSelf(
      bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION
    ) as BundleInfoWithTokenAccess;
    const tokenId = info.appInfo?.accessTokenId ?? -1;
    if (tokenId < 0) {
      throw new Error('无法获取 accessTokenId');
    }
    this.selfTokenId = tokenId;
    return tokenId;
  }

  private async checkPermission(permission: Permissions): Promise<boolean> {
    try {
      const tokenId = await this.ensureSelfTokenId();
      const atManager = abilityAccessCtrl.createAtManager();
      const status = atManager.checkAccessTokenSync(tokenId, permission);
      return status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
    } catch (error) {
      logger.debug(TAG, `检查权限失败：permission=${permission}, error=${this.extractErrorMessage(error)}`);
      return false;
    }
  }

  private async refreshPermissionCache(): Promise<void> {
    this.activityMotionGranted = await this.checkPermission('ohos.permission.ACTIVITY_MOTION');
    this.detectGestureGranted = await this.checkPermission('ohos.permission.DETECT_GESTURE');
    logger.info(
      TAG,
      `握持感知权限状态已刷新：DETECT_GESTURE=${this.describeBoolean(this.detectGestureGranted)}，ACTIVITY_MOTION=${this.describeBoolean(this.activityMotionGranted)}`
    );
  }

  private async tryEnableSubscriptions(reason: string): Promise<void> {
    await this.trySubscribeHolding(reason);
    await this.trySubscribeOperating(reason);
    this.refreshRecentOperatingStatus(reason);
    this.publishSnapshot(this.buildSnapshot(), `subscriptions_${reason}`);
  }

  private async trySubscribeHolding(reason: string): Promise<void> {
    if (this.holdingSubscribed) {
      logger.debug(TAG, `智感握姿监听已存在，跳过重复订阅：原因=${reason}`);
      return;
    }
    try {
      motion.on('holdingHandChanged', this.holdingHandChangedCallback);
      this.holdingSubscribed = true;
      logger.info(TAG, `已启用智感握姿监听：原因=${reason}`);
    } catch (error) {
      logger.warn(
        TAG,
        `启用智感握姿监听失败：原因=${reason}，错误码=${this.extractErrorCode(error)}，错误=${this.extractErrorMessage(error)}`
      );
    }
  }

  private async trySubscribeOperating(reason: string): Promise<void> {
    if (this.operatingSubscribed) {
      logger.debug(TAG, `操作手监听已存在，跳过重复订阅：原因=${reason}`);
      return;
    }
    try {
      motion.on('operatingHandChanged', this.operatingHandChangedCallback);
      this.operatingSubscribed = true;
      logger.info(TAG, `已启用操作手监听：原因=${reason}`);
    } catch (error) {
      logger.warn(
        TAG,
        `启用操作手监听失败：原因=${reason}，错误码=${this.extractErrorCode(error)}，错误=${this.extractErrorMessage(error)}`
      );
    }
  }

  private refreshRecentOperatingStatus(reason: string): void {
    if (!this.detectGestureGranted && !this.activityMotionGranted) {
      logger.debug(TAG, `缺少可用权限，跳过最近一次操作手状态刷新：原因=${reason}`);
      return;
    }
    try {
      this.latestOperatingStatus = motion.getRecentOperatingHandStatus();
      logger.info(
        TAG,
        `已刷新最近一次操作手状态：状态=${this.describeOperatingHandStatus(this.latestOperatingStatus)}，原因=${reason}`
      );
    } catch (error) {
      logger.debug(
        TAG,
        `刷新最近一次操作手状态失败：原因=${reason}，错误码=${this.extractErrorCode(error)}，错误=${this.extractErrorMessage(error)}`
      );
    }
  }

  private teardownSubscriptions(): void {
    if (this.holdingSubscribed) {
      try {
        motion.off('holdingHandChanged', this.holdingHandChangedCallback);
      } catch (_error) {}
      this.holdingSubscribed = false;
    }

    if (this.operatingSubscribed) {
      try {
        motion.off('operatingHandChanged', this.operatingHandChangedCallback);
      } catch (_error) {}
      this.operatingSubscribed = false;
    }
  }

  private buildSnapshot(): HoldingAwarenessSnapshot {
    const previousAnchor = this.currentSnapshot.preferredAnchor ?? HoldingUiAnchor.RIGHT;
    let preferredAnchor: HoldingUiAnchor = previousAnchor;
    let side: HoldingAwarenessSide = HoldingAwarenessSide.UNKNOWN;
    let source: HoldingAwarenessSource = HoldingAwarenessSource.DEFAULT;
    let confidence: HoldingAwarenessConfidence = HoldingAwarenessConfidence.FALLBACK;

    switch (this.latestHoldingStatus) {
      case motion.HoldingHandStatus.LEFT_HAND_HELD:
        preferredAnchor = HoldingUiAnchor.LEFT;
        side = HoldingAwarenessSide.LEFT;
        source = HoldingAwarenessSource.HOLDING_HAND;
        confidence = HoldingAwarenessConfidence.EXACT;
        break;
      case motion.HoldingHandStatus.RIGHT_HAND_HELD:
        preferredAnchor = HoldingUiAnchor.RIGHT;
        side = HoldingAwarenessSide.RIGHT;
        source = HoldingAwarenessSource.HOLDING_HAND;
        confidence = HoldingAwarenessConfidence.EXACT;
        break;
      case motion.HoldingHandStatus.BOTH_HANDS_HELD:
        side = HoldingAwarenessSide.BOTH;
        source = HoldingAwarenessSource.HOLDING_HAND;
        confidence = HoldingAwarenessConfidence.INFERRED;
        break;
      case motion.HoldingHandStatus.NOT_HELD:
        side = HoldingAwarenessSide.NONE;
        break;
      default:
        break;
    }

    if (this.latestOperatingStatus === motion.OperatingHandStatus.LEFT_HAND_OPERATED) {
      if (confidence !== HoldingAwarenessConfidence.EXACT) {
        preferredAnchor = HoldingUiAnchor.LEFT;
        source = side === HoldingAwarenessSide.BOTH
          ? HoldingAwarenessSource.COMBINED
          : HoldingAwarenessSource.OPERATING_HAND;
        confidence = HoldingAwarenessConfidence.INFERRED;
        if (side === HoldingAwarenessSide.UNKNOWN || side === HoldingAwarenessSide.NONE) {
          side = HoldingAwarenessSide.LEFT;
        }
      }
    } else if (this.latestOperatingStatus === motion.OperatingHandStatus.RIGHT_HAND_OPERATED) {
      if (confidence !== HoldingAwarenessConfidence.EXACT) {
        preferredAnchor = HoldingUiAnchor.RIGHT;
        source = side === HoldingAwarenessSide.BOTH
          ? HoldingAwarenessSource.COMBINED
          : HoldingAwarenessSource.OPERATING_HAND;
        confidence = HoldingAwarenessConfidence.INFERRED;
        if (side === HoldingAwarenessSide.UNKNOWN || side === HoldingAwarenessSide.NONE) {
          side = HoldingAwarenessSide.RIGHT;
        }
      }
    }

    return {
      preferredAnchor,
      side,
      source,
      confidence,
      available: this.holdingSubscribed || this.operatingSubscribed,
      preciseSupported: this.holdingSubscribed,
      detectGestureGranted: this.detectGestureGranted,
      activityMotionGranted: this.activityMotionGranted,
      lastUpdatedAt: Date.now()
    };
  }

  private publishSnapshot(nextSnapshot: HoldingAwarenessSnapshot, reason: string): void {
    if (this.isSameSnapshot(this.currentSnapshot, nextSnapshot)) {
      logger.debug(TAG, `握持感知快照未变化，跳过发布：原因=${reason}`);
      return;
    }

    this.currentSnapshot = nextSnapshot;
    AppStorage.setOrCreate(HOLDING_AWARENESS_PREFERRED_ANCHOR_KEY, nextSnapshot.preferredAnchor);
    AppStorage.setOrCreate(HOLDING_AWARENESS_SIDE_KEY, nextSnapshot.side);
    AppStorage.setOrCreate(HOLDING_AWARENESS_SOURCE_KEY, nextSnapshot.source);
    AppStorage.setOrCreate(HOLDING_AWARENESS_CONFIDENCE_KEY, nextSnapshot.confidence);
    AppStorage.setOrCreate(HOLDING_AWARENESS_AVAILABLE_KEY, nextSnapshot.available);
    AppStorage.setOrCreate(HOLDING_AWARENESS_PRECISE_SUPPORTED_KEY, nextSnapshot.preciseSupported);
    AppStorage.setOrCreate(HOLDING_AWARENESS_DETECT_GESTURE_GRANTED_KEY, nextSnapshot.detectGestureGranted);
    AppStorage.setOrCreate(HOLDING_AWARENESS_ACTIVITY_MOTION_GRANTED_KEY, nextSnapshot.activityMotionGranted);
    AppStorage.setOrCreate(HOLDING_AWARENESS_LAST_UPDATED_KEY, nextSnapshot.lastUpdatedAt);

    logger.info(
      TAG,
      `握持感知快照已更新：推荐停靠=${this.describeUiAnchor(nextSnapshot.preferredAnchor)}，` +
        `握持侧=${this.describeAwarenessSide(nextSnapshot.side)}，来源=${this.describeSource(nextSnapshot.source)}，` +
        `置信度=${this.describeConfidence(nextSnapshot.confidence)}，可用=${this.describeBoolean(nextSnapshot.available)}，` +
        `精确支持=${this.describeBoolean(nextSnapshot.preciseSupported)}，DETECT_GESTURE=${this.describeBoolean(nextSnapshot.detectGestureGranted)}，` +
        `ACTIVITY_MOTION=${this.describeBoolean(nextSnapshot.activityMotionGranted)}，原因=${reason}`
    );

    this.listeners.forEach((listener: HoldingAwarenessListener) => {
      try {
        listener(cloneHoldingAwarenessSnapshot(nextSnapshot));
      } catch (error) {
        logger.warn(TAG, `握持感知监听器回调失败：${this.extractErrorMessage(error)}`);
      }
    });
  }

  private isSameSnapshot(
    previous: HoldingAwarenessSnapshot,
    next: HoldingAwarenessSnapshot
  ): boolean {
    return previous.preferredAnchor === next.preferredAnchor &&
      previous.side === next.side &&
      previous.source === next.source &&
      previous.confidence === next.confidence &&
      previous.available === next.available &&
      previous.preciseSupported === next.preciseSupported &&
      previous.detectGestureGranted === next.detectGestureGranted &&
      previous.activityMotionGranted === next.activityMotionGranted;
  }

  private describeBoolean(value: boolean): string {
    return value ? '是' : '否';
  }

  private describeUiAnchor(anchor: HoldingUiAnchor): string {
    return anchor === HoldingUiAnchor.LEFT ? '左侧' : '右侧';
  }

  private describeAwarenessSide(side: HoldingAwarenessSide): string {
    switch (side) {
      case HoldingAwarenessSide.NONE:
        return '未握持';
      case HoldingAwarenessSide.LEFT:
        return '左手握持';
      case HoldingAwarenessSide.RIGHT:
        return '右手握持';
      case HoldingAwarenessSide.BOTH:
        return '双手握持';
      default:
        return '未知';
    }
  }

  private describeSource(source: HoldingAwarenessSource): string {
    switch (source) {
      case HoldingAwarenessSource.HOLDING_HAND:
        return '智感握姿';
      case HoldingAwarenessSource.OPERATING_HAND:
        return '操作手';
      case HoldingAwarenessSource.COMBINED:
        return '握姿+操作手联合判断';
      default:
        return '默认回退';
    }
  }

  private describeConfidence(confidence: HoldingAwarenessConfidence): string {
    switch (confidence) {
      case HoldingAwarenessConfidence.EXACT:
        return '精确';
      case HoldingAwarenessConfidence.INFERRED:
        return '推断';
      default:
        return '回退';
    }
  }

  private describeHoldingHandStatus(status: motion.HoldingHandStatus): string {
    switch (status) {
      case motion.HoldingHandStatus.NOT_HELD:
        return '未检测到握持';
      case motion.HoldingHandStatus.LEFT_HAND_HELD:
        return '左手握持';
      case motion.HoldingHandStatus.RIGHT_HAND_HELD:
        return '右手握持';
      case motion.HoldingHandStatus.BOTH_HANDS_HELD:
        return '双手握持';
      default:
        return '未知握姿';
    }
  }

  private describeOperatingHandStatus(status: motion.OperatingHandStatus): string {
    switch (status) {
      case motion.OperatingHandStatus.LEFT_HAND_OPERATED:
        return '左手操作';
      case motion.OperatingHandStatus.RIGHT_HAND_OPERATED:
        return '右手操作';
      default:
        return '未知操作手';
    }
  }

  private extractErrorCode(error: HoldingAwarenessError): string {
    const businessError = error as BusinessErrorLike;
    if (businessError && businessError.code !== undefined) {
      return String(businessError.code);
    }
    return '未知';
  }

  private extractErrorMessage(error: HoldingAwarenessError): string {
    if (error instanceof Error) {
      return error.message;
    }
    const businessError = error as BusinessErrorLike;
    if (businessError && businessError.message !== undefined) {
      return String(businessError.message);
    }
    return String(error);
  }
}

export function getHoldingAwarenessManager(): HoldingAwarenessManager {
  return HoldingAwarenessManager.getInstance();
}

export const holdingAwarenessManager = HoldingAwarenessManager.getInstance();
