import common from '@ohos.app.ability.common';
import { abilityAccessCtrl, bundleManager, Permissions, Want } from '@kit.AbilityKit';
import { logger } from '../../Utils/Logger';
import { distributedDataSyncManager } from './DistributedDataSyncManager';

const TAG = 'DistributedPermissionManager';

/**
 * 分布式数据同步权限管理器
 *
 * 背景：ohos.permission.DISTRIBUTED_DATASYNC 是 user_grant 权限，必须运行时弹窗授权；
 * 分布式数据对象 setSessionId 强依赖该权限（未授权报错 201）。
 *
 * 设计目标：
 * 1. 权限请求稳定提起 —— 在多个"窗口已就绪"的场景检查点（应用前台、主页显示、进入阅读器、onContinue）提起；
 * 2. 未授权时每次进入相关场景都能再次弹出 —— 不设任何冷却/节流：
 *    弹窗被打断（窗口未就绪、被系统取消）会自动重试；弹窗在途时其他检查点登记"补一次"重试需求；
 * 3. 权限处于"用户固定拒绝"（在系统设置中关闭/勾选"不再询问"，flag=USER_FIXED）时，
 *    平台不再弹应用内授权弹窗（access_token 服务直接返回拒绝），
 *    此时自动拉起系统权限设置页（requestPermissionOnSetting）引导用户开启 —— 保证"每次都能出现"。
 */
export class DistributedPermissionManager {
  private static instance: DistributedPermissionManager;
  private cachedTokenId: number = -1;
  /** 权限请求是否在途（防并发弹窗：系统不允许同一时刻存在多个权限请求） */
  private requestInFlight: boolean = false;
  /** 请求在途期间其他检查点登记的重试需求（本次结果落定后自动补一次） */
  private pendingRetry: boolean = false;
  /** 请求被打断后的自动重试计数 */
  private autoRetryCount: number = 0;
  /** 自动重试定时器句柄 */
  private autoRetryTimer: number = -1;
  /** 引导前往系统设置页的跳转是否在途 */
  private settingRedirectInFlight: boolean = false;
  /** 上次引导前往系统设置页的时间戳（避免同一轮检查点风暴反复拉起设置页） */
  private lastSettingRedirectTimestamp: number = 0;
  /** 新手引导期间抑制后台检查点的自动请求/设置跳转（由引导页的权限步骤统一负责首次请求） */
  private onboardingGuideActive: boolean = false;

  /** 请求被打断后自动重试的最大连续次数 */
  private static readonly MAX_AUTO_RETRY: number = 2;
  /** 打断后自动重试的延迟（等待系统权限 UI/窗口恢复稳定） */
  private static readonly RETRY_DELAY_MS: number = 1500;
  /** 两次引导前往系统设置页之间的最小间隔（只去重检查点风暴，不设冷却） */
  private static readonly SETTING_REDIRECT_MIN_INTERVAL_MS: number = 15 * 1000;
  /**
   * 判定"系统未弹窗直接拒绝"的耗时阈值：
   * 用户在系统设置中固定拒绝（flag=USER_FIXED）后，requestPermissionsFromUser 不弹窗、
   * 立即返回拒绝（实测 1~75ms）；真实用户操作拒绝至少数百毫秒。
   */
  private static readonly AUTO_DENY_THRESHOLD_MS: number = 500;

  private readonly permission: Permissions = 'ohos.permission.DISTRIBUTED_DATASYNC';

  private constructor() {}

  public static getInstance(): DistributedPermissionManager {
    if (!DistributedPermissionManager.instance) {
      DistributedPermissionManager.instance = new DistributedPermissionManager();
    }
    return DistributedPermissionManager.instance;
  }

  private async getTokenId(): Promise<number> {
    if (this.cachedTokenId >= 0) {
      return this.cachedTokenId;
    }
    try {
      const bundleInfo = await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
      this.cachedTokenId = bundleInfo.appInfo.accessTokenId;
      return this.cachedTokenId;
    } catch (error) {
      logger.warn(TAG, `获取应用 accessTokenId 失败: ${String(error)}`);
      return -1;
    }
  }

  /**
   * 同步检查权限是否已授予（基于缓存的 tokenId，用于 onContinue 等同步回调路径）
   * tokenId 尚未缓存时视为未授权（异步路径会先通过 ensurePermission 完成缓存与授权）
   */
  public isPermissionGrantedSync(): boolean {
    if (this.cachedTokenId < 0) {
      logger.debug(TAG, 'isPermissionGrantedSync=false: tokenId 尚未缓存（异步路径会先获取）');
      return false;
    }
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const state = atManager.checkAccessTokenSync(this.cachedTokenId, this.permission);
      return state === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
    } catch (error) {
      logger.warn(TAG, `同步检查分布式数据同步权限失败: ${String(error)}`);
      return false;
    }
  }

  /**
   * 异步检查权限是否已授予
   */
  public async isPermissionGranted(): Promise<boolean> {
    const tokenId = await this.getTokenId();
    if (tokenId < 0) {
      return false;
    }
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const state = atManager.checkAccessTokenSync(tokenId, this.permission);
      return state === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
    } catch (error) {
      logger.warn(TAG, `检查分布式数据同步权限失败: ${String(error)}`);
      return false;
    }
  }

  /**
   * 预载 accessTokenId 缓存（不弹窗）。
   * 供入口 Ability 早期调用，让 isPermissionGrantedSync() 在 onContinue 同步回调里拿到真实结果，
   * 避免"tokenId 未缓存即视为未授权"导致首次接续被误拒。
   */
  public preloadTokenId(): void {
    void this.getTokenId().then((tokenId: number): void => {
      if (tokenId >= 0) {
        logger.debug(TAG, `preloadTokenId: accessTokenId 已缓存: ${tokenId}`);
      }
    });
  }

  /**
   * 设置新手引导期间的抑制状态：
   * 引导页会先向用户解释「设备发现和连接」权限的用途，再由引导页的权限步骤统一触发首次请求，
   * 此期间后台检查点（前台/主页显示等）不再自动弹窗或跳转设置，避免"一进应用就直接跳设置"。
   */
  public setOnboardingGuideActive(active: boolean): void {
    if (this.onboardingGuideActive === active) {
      return;
    }
    this.onboardingGuideActive = active;
    logger.info(TAG, `新手引导期间权限请求抑制: ${active ? '开启' : '关闭'}`);
  }

  /**
   * 确保分布式数据同步权限：未授权时尝试弹出授权请求。
   * 无冷却、无时间节流：未授权时每次进入相关场景都会再次发起请求（用户在途时仅登记补一次）。
   * 请求被打断/失败会自动重试（最多连续 MAX_AUTO_RETRY 次），之后仍可在任何检查点再次提起。
   *
   * @param context 用于弹窗的 UIAbilityContext（必须是前台 Ability 的 context）
   * @returns true=已授权（或本次请求后已授权）；false=未授权
   */
  public async ensurePermission(context: common.UIAbilityContext): Promise<boolean> {
    if (await this.isPermissionGranted()) {
      logger.debug(TAG, 'ensurePermission: 权限已授权，跳过弹窗');
      this.resetAutoRetry();
      // 权限就绪：若此前分布式会话因权限未授权建立失败（201），立即重建
      distributedDataSyncManager.retryJoinSession();
      return true;
    }

    // 新手引导期间由引导页权限步骤统一负责首次请求：
    // 后台检查点不弹窗、不跳转设置，避免打断引导（"一进应用就直接跳设置"问题）
    if (this.onboardingGuideActive) {
      logger.info(TAG, 'ensurePermission: 新手引导进行中，本次检查点不请求权限（由引导页权限步骤统一处理）');
      return false;
    }

    if (this.requestInFlight) {
      // 已有请求在途：不叠加弹窗（系统会抑制），登记一次后续重试需求
      this.pendingRetry = true;
      logger.info(TAG, 'ensurePermission: 权限请求已在途，登记本次需求为后续补一次（不叠加弹窗）');
      return false;
    }

    this.requestInFlight = true;
    const requestStartedAt = Date.now();
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const result = await atManager.requestPermissionsFromUser(context, [this.permission]);
      const requestCostMs = Date.now() - requestStartedAt;
      const granted = result.authResults.length > 0 && result.authResults[0] === 0;
      if (granted) {
        logger.info(TAG, `✅ 分布式数据同步权限已授权, 请求耗时=${requestCostMs}ms`);
        logger.performance(TAG, 'distributed_permission_request', requestCostMs, 'ms');
        this.resetAutoRetry();
        // 权限刚获得：若此前分布式会话因权限未授权建立失败（201），立即重建
        distributedDataSyncManager.retryJoinSession();
        return true;
      }
      if (requestCostMs < DistributedPermissionManager.AUTO_DENY_THRESHOLD_MS) {
        // [实证修复] 系统未弹窗直接返回拒绝（实测 1~75ms）：
        // 设备日志显示权限处于 status=-1, flag=2（用户在设置中固定拒绝/勾选"不再询问"）后，
        // 平台侧 "[RequestPermissionsFromUserExecute]It does not need to request permission"，
        // 应用内弹窗永远不会再出现 —— 这是平台设计，不是节流/冷却问题。
        // 此时改为拉起系统权限设置页引导用户开启（requestPermissionOnSetting）。
        logger.warn(TAG, `权限被系统直接拒绝（未弹窗，耗时=${requestCostMs}ms）：权限处于"用户固定拒绝"状态，改为引导前往系统设置页开启`);
        this.redirectToPermissionSetting(context);
        return false;
      }
      // 用户真实点击拒绝：不记录冷却；后续任意检查点仍会重新请求
      logger.warn(TAG, `用户拒绝了分布式数据同步权限（无冷却，下次进入相关场景会再次请求）, 请求耗时=${requestCostMs}ms, results=${JSON.stringify(result.authResults)}`);
      return false;
    } catch (error) {
      // 弹窗被打断/失败（窗口未就绪、被系统取消等）：不记录拒绝，自动重试
      logger.warn(TAG, `权限请求被打断或失败，将自动重试, 耗时=${Date.now() - requestStartedAt}ms, err=${String(error)}`);
      this.scheduleAutoRetry(context);
      return false;
    } finally {
      this.requestInFlight = false;
      // 在途期间其他检查点登记过需求：本次结果落定后自动补一次
      if (this.pendingRetry) {
        this.pendingRetry = false;
        void this.isPermissionGranted().then((grantedNow: boolean): void => {
          if (!grantedNow) {
            this.scheduleAutoRetry(context);
          } else {
            logger.info(TAG, '补一次检查发现权限已授权，无需重试');
          }
        });
      }
    }
  }

  /**
   * 引导用户前往系统权限设置页开启权限（权限处于"用户固定拒绝"状态时应用内无法弹窗）。
   * 去重策略：仅避免同一轮检查点风暴反复拉起设置页（间隔阈值内跳过），不设拒绝冷却。
   *
   * 实现：优先深链跳转系统设置中的应用信息页（Huawei 设置深链），
   * 失败时回退 requestPermissionOnSetting（系统权限状态页，实测冷启动期间可能被系统关闭）。
   */
  private redirectToPermissionSetting(context: common.UIAbilityContext): void {
    if (this.settingRedirectInFlight) {
      logger.info(TAG, 'redirectToPermissionSetting: 权限设置页跳转已在途，跳过');
      return;
    }
    const now = Date.now();
    if (now - this.lastSettingRedirectTimestamp < DistributedPermissionManager.SETTING_REDIRECT_MIN_INTERVAL_MS) {
      logger.info(TAG, `redirectToPermissionSetting: 距上次引导 ${now - this.lastSettingRedirectTimestamp}ms < ${DistributedPermissionManager.SETTING_REDIRECT_MIN_INTERVAL_MS}ms，跳过本轮（检查点去重）`);
      return;
    }
    this.settingRedirectInFlight = true;
    this.lastSettingRedirectTimestamp = now;
    try {
      const mainWindow = context.windowStage.getMainWindowSync();
      // [用户可见文案] 权限的系统显示名为「设备发现和连接」；
      // 用一句话说明开启原因：接续阅读（把阅读进度流转到其他设备）依赖该权限
      mainWindow.getUIContext().getPromptAction().showToast({
        message: '接续阅读需要「设备发现和连接」权限，请在设置中开启'
      });
    } catch (toastError) {
      logger.debug(TAG, `设置引导提示失败（忽略）: ${String(toastError)}`);
    }
    this.openAppPermissionSettingsPage(context);
  }

  /**
   * 深链跳转系统设置中的应用信息页（用户可在其中开启权限）
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
        this.settingRedirectInFlight = false;
        logger.info(TAG, '✅ 已跳转系统设置中的应用信息页，用户可开启分布式数据同步权限');
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
      atManager.requestPermissionOnSetting(context, [this.permission]).then((statuses: Array<abilityAccessCtrl.GrantStatus>): void => {
        this.settingRedirectInFlight = false;
        const grantedNow = statuses.length > 0 && statuses[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
        logger.info(TAG, `权限设置页返回: granted=${grantedNow}, statuses=${JSON.stringify(statuses)}`);
        if (grantedNow) {
          logger.info(TAG, '✅ 用户已在系统设置中开启分布式数据同步权限');
        }
      }).catch((error: Error): void => {
        this.settingRedirectInFlight = false;
        logger.warn(TAG, `拉起权限设置页失败: ${String(error)}`);
      });
    } catch (error) {
      this.settingRedirectInFlight = false;
      logger.warn(TAG, `fallbackRequestPermissionOnSetting 异常: ${String(error)}`);
    }
  }

  /**
   * 新手引导页面的显式权限请求（不受引导抑制影响，也不自动跳转设置）。
   * 引导页需要区分"用户拒绝"与"系统未弹窗直接拒绝（用户固定拒绝）"以展示不同引导文案，
   * 因此返回细化结果；自动重试交由引导页的"再次请求"按钮处理。
   */
  public async requestPermissionForGuide(context: common.UIAbilityContext):
    Promise<'granted' | 'denied' | 'user_fixed_denied' | 'busy' | 'error'> {
    if (await this.isPermissionGranted()) {
      logger.info(TAG, 'requestPermissionForGuide: 权限已授权');
      this.resetAutoRetry();
      // 权限就绪：若此前分布式会话因权限未授权建立失败（201），立即重建
      distributedDataSyncManager.retryJoinSession();
      return 'granted';
    }
    if (this.requestInFlight) {
      logger.info(TAG, 'requestPermissionForGuide: 权限请求已在途');
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
        logger.info(TAG, `requestPermissionForGuide: 权限已授权, 请求耗时=${requestCostMs}ms`);
        this.resetAutoRetry();
        // 权限刚获得：若此前分布式会话因权限未授权建立失败（201），立即重建
        distributedDataSyncManager.retryJoinSession();
        return 'granted';
      }
      if (requestCostMs < DistributedPermissionManager.AUTO_DENY_THRESHOLD_MS) {
        logger.warn(TAG, `requestPermissionForGuide: 系统未弹窗直接拒绝（耗时=${requestCostMs}ms），权限处于"用户固定拒绝"状态`);
        return 'user_fixed_denied';
      }
      logger.warn(TAG, `requestPermissionForGuide: 用户在引导页拒绝了权限, 请求耗时=${requestCostMs}ms`);
      return 'denied';
    } catch (error) {
      logger.warn(TAG, `requestPermissionForGuide: 请求被打断或失败: ${String(error)}`);
      return 'error';
    } finally {
      this.requestInFlight = false;
      if (this.pendingRetry) {
        this.pendingRetry = false;
      }
    }
  }

  /**
   * 公开入口：深链跳转系统设置中的应用信息页（用户手动开启权限）。
   * 供新手引导页的"前往设置开启"按钮使用（用户主动点击，不做去重与提示）。
   */
  public openAppPermissionSettings(context: common.UIAbilityContext): void {
    this.openAppPermissionSettingsPage(context);
  }

  /**
   * 请求被打断后的自动重试：延迟 RETRY_DELAY_MS 后再次发起（最多连续 MAX_AUTO_RETRY 次）。
   * 授权成功或超过连续重试上限后复位计数；之后任意场景检查点仍可再次提起。
   */
  private scheduleAutoRetry(context: common.UIAbilityContext): void {
    if (this.autoRetryTimer >= 0) {
      logger.debug(TAG, 'scheduleAutoRetry: 已有自动重试定时器在途，跳过重复调度');
      return;
    }
    if (this.autoRetryCount >= DistributedPermissionManager.MAX_AUTO_RETRY) {
      logger.warn(TAG, `scheduleAutoRetry: 连续自动重试已达上限 ${DistributedPermissionManager.MAX_AUTO_RETRY} 次，等待下一个场景检查点`);
      this.autoRetryCount = 0;
      return;
    }
    this.autoRetryCount += 1;
    logger.info(TAG, `scheduleAutoRetry: ${DistributedPermissionManager.RETRY_DELAY_MS}ms 后自动重试权限请求（第 ${this.autoRetryCount}/${DistributedPermissionManager.MAX_AUTO_RETRY} 次）`);
    this.autoRetryTimer = setTimeout(() => {
      this.autoRetryTimer = -1;
      void this.ensurePermission(context).then((granted: boolean): void => {
        if (granted) {
          logger.info(TAG, '自动重试后分布式数据同步权限已授权');
          this.resetAutoRetry();
        }
      });
    }, DistributedPermissionManager.RETRY_DELAY_MS);
  }

  private resetAutoRetry(): void {
    this.autoRetryCount = 0;
    if (this.autoRetryTimer >= 0) {
      clearTimeout(this.autoRetryTimer);
      this.autoRetryTimer = -1;
    }
  }
}

export const distributedPermissionManager = DistributedPermissionManager.getInstance();
