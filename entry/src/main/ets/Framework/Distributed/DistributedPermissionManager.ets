import common from '@ohos.app.ability.common';
import { abilityAccessCtrl, bundleManager, Permissions, Want } from '@kit.AbilityKit';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { distributedDataSyncManager } from './DistributedDataSyncManager';

const TAG = 'DistributedPermissionManager';

/**
 * 「设备发现和连接」（ohos.permission.DISTRIBUTED_DATASYNC）权限的请求结果。
 * - granted：已授权（或本次请求后已授权）
 * - denied：用户在系统弹窗中明确拒绝
 * - user_fixed_denied：权限曾在系统设置中被固定关闭，应用内无法再弹窗
 * - busy：已有授权请求在途，本次不重复弹窗
 * - error：请求被系统打断或发生异常
 */
export type DistributedPermissionRequestResult =
  'granted' | 'denied' | 'user_fixed_denied' | 'busy' | 'error';

/**
 * 接续阅读不可用的原因，用于选择统一提示文案。
 * - disabled：用户在「设置 → 接续阅读」中关闭了总开关
 * - permission_missing：缺少「设备发现和连接」权限
 */
export type ContinuationUnavailableReason = 'disabled' | 'permission_missing';

/**
 * 分布式数据同步权限管理器（即应用市场权限说明中的「设备发现和连接」）。
 *
 * 该权限只是"跨设备接续阅读"这一可选能力的依赖，**不是使用应用的前提**。合规约定：
 *
 * 1. 所有自动检查点（应用启动、回到前台、主页显示、进入阅读器）只做**静默检查**，
 *    绝不弹授权弹窗、绝不跳转系统设置。拒绝该权限的用户可以完整使用应用其他功能
 *    （阅读、书库、下载、登录等），不会被退出、不会被关闭，也不会被反复弹窗打扰。
 * 2. 只有**用户主动点击**（新手引导权限步骤、接续阅读设置页按钮、接续失败提示卡片）
 *    才会发起系统授权弹窗；同一时刻只允许一个请求在途。
 * 3. 请求被拒绝或失败后**不自动重试**、不做无冷却重复请求，避免"频繁弹窗"。
 * 4. 权限缺失或接续总开关关闭时，在接续相关场景给出明确的一次性提示，
 *    说明"功能无法正常使用"以及开启路径。
 */
export class DistributedPermissionManager {
  private static instance: DistributedPermissionManager;
  /** 应用 accessTokenId 缓存（-1 表示尚未解析） */
  private cachedTokenId: number = -1;
  /** 权限请求是否在途（系统不允许同一时刻存在多个权限请求） */
  private requestInFlight: boolean = false;
  /** 上次跳转系统设置页的时间戳（仅用于去重用户连点，不做冷却限制） */
  private lastSettingRedirectTimestamp: number = 0;
  /** 上次"接续不可用"提示的时间戳（避免同一场景反复打扰用户） */
  private lastUnavailableHintTimestamp: number = 0;

  /**
   * 判定"系统未弹窗直接拒绝"的耗时阈值：
   * 用户在系统设置中固定拒绝后，requestPermissionsFromUser 不弹窗、立即返回拒绝
   * （实测 1~75ms）；真实用户操作拒绝至少数百毫秒。
   */
  private static readonly AUTO_DENY_THRESHOLD_MS: number = 500;
  /** 用户连点"前往设置"的去重间隔 */
  private static readonly SETTING_REDIRECT_DEBOUNCE_MS: number = 1500;
  /** 同一句"接续不可用"提示的最小间隔，避免进入阅读器等场景连续打扰 */
  private static readonly UNAVAILABLE_HINT_MIN_INTERVAL_MS: number = 120 * 1000;

  /** 缺少「设备发现和连接」权限时的统一提示文案 */
  public static readonly PERMISSION_MISSING_HINT: string =
    '未开启「设备发现和连接」权限，跨设备接续阅读暂时无法使用。可在「设置 → 接续阅读」中开启。';
  /** 接续阅读总开关已关闭时的统一提示文案 */
  public static readonly CONTINUATION_DISABLED_HINT: string =
    '接续阅读已关闭，跨设备接续暂时无法使用。可在「设置 → 接续阅读」中重新开启。';

  private readonly permission: Permissions = 'ohos.permission.DISTRIBUTED_DATASYNC';

  private constructor() {}

  public static getInstance(): DistributedPermissionManager {
    if (!DistributedPermissionManager.instance) {
      DistributedPermissionManager.instance = new DistributedPermissionManager();
    }
    return DistributedPermissionManager.instance;
  }

  /**
   * 解析应用 accessTokenId（优先缓存，其次同步读取）。
   * 同步读取是为了让 onContinue 等同步回调路径也能拿到真实授权结果，
   * 避免"tokenId 未缓存即视为未授权"导致的误判。
   */
  private resolveTokenId(): number {
    if (this.cachedTokenId >= 0) {
      return this.cachedTokenId;
    }
    try {
      const bundleInfo = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION
      );
      this.cachedTokenId = bundleInfo.appInfo.accessTokenId;
      return this.cachedTokenId;
    } catch (error) {
      logger.warn(TAG, `获取应用 accessTokenId 失败: ${String(error)}`);
      return -1;
    }
  }

  /**
   * 预载 accessTokenId 缓存（不弹窗，仅同步解析一次）。
   */
  public preloadTokenId(): void {
    const tokenId = this.resolveTokenId();
    if (tokenId >= 0) {
      logger.debug(TAG, `preloadTokenId: accessTokenId 已缓存: ${tokenId}`);
    }
  }

  /**
   * 同步检查权限是否已授予（用于 onContinue 等同步回调路径）。
   */
  public isPermissionGrantedSync(): boolean {
    const tokenId = this.resolveTokenId();
    if (tokenId < 0) {
      logger.debug(TAG, 'isPermissionGrantedSync=false: 无法解析 accessTokenId');
      return false;
    }
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const state = atManager.checkAccessTokenSync(tokenId, this.permission);
      return state === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
    } catch (error) {
      logger.warn(TAG, `同步检查「设备发现和连接」权限失败: ${String(error)}`);
      return false;
    }
  }

  /**
   * 异步检查权限是否已授予（不弹窗）。
   */
  public async isPermissionGranted(): Promise<boolean> {
    return this.isPermissionGrantedSync();
  }

  /**
   * 静默刷新权限状态：**绝不弹窗、绝不跳转系统设置**。
   *
   * 供应用前台、主页显示、进入阅读器等自动检查点使用：这些检查点只负责"发现"权限状态，
   * 并在权限就绪时重建此前的分布式会话；向用户索要权限一律交给用户主动操作。
   *
   * @returns true=已授权；false=未授权（调用方自行决定是否提示，不得直接弹窗索要）
   */
  public async refreshPermissionState(): Promise<boolean> {
    const granted = this.isPermissionGrantedSync();
    if (granted) {
      // 权限就绪：若此前分布式会话因权限未授权建立失败（201），立即重建
      distributedDataSyncManager.retryJoinSession();
    }
    return granted;
  }

  /**
   * 显式请求权限（**仅允许由用户主动点击触发**，例如引导页按钮、设置页开关）。
   * 同一时刻只允许一个请求在途；被拒绝后不自动重试。
   *
   * @param context 用于弹窗的 UIAbilityContext（必须是前台 Ability 的 context）
   * @param trigger 触发来源（仅用于日志定位）
   */
  public async requestPermission(
    context: common.UIAbilityContext,
    trigger: string
  ): Promise<DistributedPermissionRequestResult> {
    if (this.isPermissionGrantedSync()) {
      logger.info(TAG, `requestPermission(${trigger}): 权限已授权，跳过弹窗`);
      this.resetUnavailableHintThrottle();
      distributedDataSyncManager.retryJoinSession();
      return 'granted';
    }
    if (this.requestInFlight) {
      logger.info(TAG, `requestPermission(${trigger}): 已有权限请求在途，本次不重复弹窗`);
      return 'busy';
    }

    this.requestInFlight = true;
    const requestStartedAt = Date.now();
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const result = await atManager.requestPermissionsFromUser(context, [this.permission]);
      const requestCostMs = Date.now() - requestStartedAt;
      const granted = result.authResults.length > 0 && result.authResults[0] === 0;
      if (granted) {
        logger.info(TAG, `✅ requestPermission(${trigger}): 权限已授权, 耗时=${requestCostMs}ms`);
        logger.performance(TAG, 'distributed_permission_request', requestCostMs, 'ms');
        this.resetUnavailableHintThrottle();
        distributedDataSyncManager.retryJoinSession();
        return 'granted';
      }
      if (requestCostMs < DistributedPermissionManager.AUTO_DENY_THRESHOLD_MS) {
        // 系统未弹窗直接返回拒绝：权限处于"用户固定拒绝"状态（平台设计，非应用节流）。
        // [合规] 此处不自动跳转系统设置，由调用方在界面上展示"前往设置开启"入口。
        logger.warn(TAG, `requestPermission(${trigger}): 系统未弹窗直接拒绝（耗时=${requestCostMs}ms），权限处于"用户固定拒绝"状态`);
        return 'user_fixed_denied';
      }
      logger.warn(TAG, `requestPermission(${trigger}): 用户拒绝了「设备发现和连接」权限, 耗时=${requestCostMs}ms`);
      return 'denied';
    } catch (error) {
      logger.warn(TAG, `requestPermission(${trigger}): 请求被打断或失败: ${String(error)}`);
      return 'error';
    } finally {
      this.requestInFlight = false;
    }
  }

  /**
   * 显式跳转系统设置中的应用信息页，供用户手动开启权限。
   * **仅允许由用户主动点击调用**，内部不做任何自动触发。
   */
  public openAppPermissionSettings(context: common.UIAbilityContext): void {
    const now = Date.now();
    if (now - this.lastSettingRedirectTimestamp < DistributedPermissionManager.SETTING_REDIRECT_DEBOUNCE_MS) {
      logger.info(TAG, 'openAppPermissionSettings: 用户连点，忽略本次重复跳转');
      return;
    }
    this.lastSettingRedirectTimestamp = now;
    logger.info(TAG, 'openAppPermissionSettings: 用户主动前往系统设置开启「设备发现和连接」权限');
    this.openAppPermissionSettingsPage(context);
  }

  /**
   * 在接续相关场景提示用户"接续阅读暂时无法使用"，并说明原因与开启路径。
   *
   * 提示做最短间隔去重（同一场景连续进入不会反复打扰）；
   * 用户主动触发接续失败等明确场景可传 force=true 强制提示。
   */
  public notifyContinuationUnavailable(
    context: common.UIAbilityContext,
    reason: ContinuationUnavailableReason,
    scene: string,
    force: boolean = false
  ): void {
    const now = Date.now();
    if (!force && now - this.lastUnavailableHintTimestamp <
      DistributedPermissionManager.UNAVAILABLE_HINT_MIN_INTERVAL_MS) {
      logger.debug(TAG, `notifyContinuationUnavailable(${scene}): 距上次提示 ${now - this.lastUnavailableHintTimestamp}ms，跳过重复提示`);
      return;
    }
    this.lastUnavailableHintTimestamp = now;
    const message = reason === 'disabled'
      ? DistributedPermissionManager.CONTINUATION_DISABLED_HINT
      : DistributedPermissionManager.PERMISSION_MISSING_HINT;
    try {
      const mainWindow = context.windowStage.getMainWindowSync();
      mainWindow.getUIContext().getPromptAction().showToast({ message: message });
      logger.info(TAG, `notifyContinuationUnavailable(${scene}): 已提示用户接续阅读不可用（原因=${reason}）`);
    } catch (error) {
      logger.debug(TAG, `notifyContinuationUnavailable(${scene}) 提示失败（忽略）: ${String(error)}`);
    }
  }

  /**
   * 复位"接续不可用"提示节流（权限就绪或用户重新开启接续后调用）。
   */
  public resetUnavailableHintThrottle(): void {
    this.lastUnavailableHintTimestamp = 0;
  }

  /**
   * 深链跳转系统设置中的应用信息页（用户可在其中开启权限）。
   */
  private openAppPermissionSettingsPage(context: common.UIAbilityContext): void {
    try {
      const want: Want = {
        bundleName: 'com.huawei.hmos.settings',
        abilityName: 'com.huawei.hmos.settings.MainAbility',
        uri: 'application_info_entry',
        parameters: {
          'pushParams': 'com.dlzz.manxia'
        }
      };
      context.startAbility(want).then(() => {
        logger.info(TAG, '✅ 已跳转系统设置中的应用信息页，用户可开启「设备发现和连接」权限');
      }).catch((error: Error): void => {
        logger.warn(TAG, `跳转应用信息页失败: ${String(error)}，回退 requestPermissionOnSetting`);
        this.fallbackRequestPermissionOnSetting(context);
      });
    } catch (error) {
      logger.warn(TAG, `openAppPermissionSettingsPage 异常: ${String(error)}，回退 requestPermissionOnSetting`);
      this.fallbackRequestPermissionOnSetting(context);
    }
  }

  /**
   * 回退方案：requestPermissionOnSetting（系统权限状态页）。
   * 实测该接口在应用冷启动期间可能被系统提前关闭（"Common inner error"），仅作兜底。
   */
  private fallbackRequestPermissionOnSetting(context: common.UIAbilityContext): void {
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      atManager.requestPermissionOnSetting(context, [this.permission])
        .then((statuses: Array<abilityAccessCtrl.GrantStatus>): void => {
          const grantedNow = statuses.length > 0 &&
            statuses[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
          logger.info(TAG, `权限设置页返回: granted=${grantedNow}`);
          if (grantedNow) {
            this.resetUnavailableHintThrottle();
            distributedDataSyncManager.retryJoinSession();
          }
        })
        .catch((error: Error): void => {
          logger.warn(TAG, `拉起权限设置页失败: ${String(error)}`);
        });
    } catch (error) {
      logger.warn(TAG, `fallbackRequestPermissionOnSetting 异常: ${String(error)}`);
    }
  }
}

export const distributedPermissionManager = DistributedPermissionManager.getInstance();
