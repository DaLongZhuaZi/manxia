import { AbilityConstant, Want } from '@kit.AbilityKit';
import common from '@ohos.app.ability.common';
import { logger } from '../../Utils/Logger';
import { distributedReadingService } from './DistributedReadingService';
import { distributedDataSyncManager } from './DistributedDataSyncManager';
import { distributedPermissionManager } from './DistributedPermissionManager';
import { eventBus, GameEvent, ContinuationTriggeredPayload } from '../EventBus';
import { openRemoteControlInIsolatedAbilityFromContext } from '../RemoteControl/RemoteControlAbilityLauncher';

const TAG = 'ContinuationStateHelper';
const APP_BUNDLE_NAME: string = 'com.dlzz.manxia';
const ENTRY_ABILITY_NAME: string = 'EntryAbility';

/** 目标端转交后等待 EntryAbility 前台确认的最大时长 */
const REDIRECT_FOREGROUND_CONFIRM_TIMEOUT_MS: number = 14 * 1000;
/** 前台确认轮询间隔 */
const REDIRECT_FOREGROUND_CONFIRM_POLL_MS: number = 500;
/** 目标端转交 EntryAbility 的启动尝试时间点（避开接续握手期间 startAbility 被系统吞掉的窗口） */
const REDIRECT_START_ATTEMPT_DELAYS_MS: number[] = [1200, 4000, 8000];
/** 目标端加入分布式会话的兜底重试延迟 */
const TARGET_JOIN_RETRY_DELAY_MS: number = 4000;
/** 源端自动拉起遥控器的尝试时间点。
 * [修复] 首个时间点为 0ms：必须在接续迁移完成前（阅读器仍在前台、应用未进入后台）发起，
 * 否则阅读器上下文随迁移释放（The caller has been released），而应用进入后台后受
 * 后台启动管控拦截（The application does not have permission to call the interface），
 * 后续任何重试都无法再拉起遥控器（连续流转时源端停留在桌面的根因）。 */
const SOURCE_REMOTE_CONTROL_ATTEMPT_DELAYS_MS: number[] = [0, 300, 900, 2500];
/** 源端遥控器全部失败后回退拉起入口 Ability 的尝试时间点 */
const SOURCE_ENTRY_FALLBACK_DELAYS_MS: number[] = [7000, 10000];
/** 遥控器 Ability 创建后等待页面就绪的宽限期：超过该时间页面仍未渲染则判定为僵尸实例 */
const REMOTE_CONTROL_PAGE_READY_GRACE_MS: number = 1500;

/**
 * 跨端接续状态的外部来源（如听书会话快照）
 */
export interface ContinuationPackSource {
  bookId: string;
  chapterIndex: number;
  pageIndex: number;
  offset: number;
  sourceType: string;
  isLocal: boolean;
}

/**
 * 跨端接续（App Continuation）状态统一处理：
 * - packContinuationWant：源端打包接续状态（EntryAbility 与阅读器/听书 Ability 共用）
 * - restoreContinuationState：目标端恢复接续状态
 * - setMissionContinueState：动态控制当前任务是否显示系统接续入口
 * - redirectContinuationToEntryAbility：目标端由阅读器/听书 Ability 接续启动时转交入口 Ability
 */
export class ContinuationStateHelper {
  private static instance: ContinuationStateHelper;

  /** 入口 Ability 上下文（由 EntryAbility.onCreate 注册，供源端接续后自动拉起遥控器等跨 Ability 操作使用） */
  private entryAbilityContext: common.UIAbilityContext | null = null;

  /** 当前阅读器场景的 Ability 上下文（源端接续后自动拉起遥控器优先使用：入口任务被迁移后入口上下文失效） */
  private activeReaderContext: common.UIAbilityContext | null = null;

  /** 听书等场景的外部接续状态来源提供器（入口 Ability 触发 onContinue 时由提供器取最新会话快照） */
  private continuationPackSourceProvider: (() => ContinuationPackSource | null) | null = null;

  /** 接续迁移开始时间戳（入口任务被系统迁移，源端 EntryAbility.onDestroy 据此跳过全局清理） */
  private continuationMigrationStartedAt: number = 0;
  /** 接续迁移标记自动清除定时器句柄 */
  private continuationMigrationClearTimer: number = -1;

  /** 目标端转交的前台确认时间阈值（EntryAbility.onForeground 写 token，大于该值视为已前台接管） */
  private redirectForegroundConfirmThreshold: number = 0;
  /** 目标端转交前台确认轮询定时器句柄 */
  private redirectPollTimer: number = -1;

  /** 源端自动拉起遥控器的本次触发时间戳（用于判断遥控器是否已成功启动） */
  private remoteControlLaunchStartTimestamp: number = 0;

  private constructor() {}

  public static getInstance(): ContinuationStateHelper {
    if (!ContinuationStateHelper.instance) {
      ContinuationStateHelper.instance = new ContinuationStateHelper();
    }
    return ContinuationStateHelper.instance;
  }

  /**
   * 注册入口 Ability 上下文（EntryAbility.onCreate 调用）。
   * 用于接续成功后源端自动拉起遥控器（阅读器 Ability 会被系统迁移销毁，不能依赖其上下文）。
   */
  public registerEntryAbilityContext(context: common.UIAbilityContext): void {
    this.entryAbilityContext = context;
    logger.debug(TAG, 'registerEntryAbilityContext: 入口 Ability 上下文已注册');
  }

  /**
   * 设置 mission 的接续状态（ACTIVE=系统显示接续入口；INACTIVE=隐藏）。
   *
   * [架构修复] 接续入口统一挂在"入口 Ability"的 mission 上：
   * 实测平台对接续到非入口 Ability（独立阅读器）的落地支持不可靠——
   * 冷启动拿不到窗口舞台、热启动进程不恢复，目标端白屏且点击即退；
   * 而入口 Ability 的迁移走标准路径（目标端 EntryAbility 恢复 → 主页自动打开阅读器），
   * 源端入口任务被迁走后阅读器任务保留，不会回到桌面。
   * 因此非入口上下文统一重定向到入口上下文。
   */
  public setMissionContinueState(context: common.UIAbilityContext, active: boolean): void {
    const targetContext = (this.entryAbilityContext && context !== this.entryAbilityContext)
      ? this.entryAbilityContext
      : context;
    try {
      const state: AbilityConstant.ContinueState = active
        ? AbilityConstant.ContinueState.ACTIVE
        : AbilityConstant.ContinueState.INACTIVE;
      targetContext.setMissionContinueState(state).then(() => {
        logger.info(TAG, `Mission continue state set: ${active ? 'ACTIVE' : 'INACTIVE'} (${context === targetContext ? 'entry' : 'redirected-to-entry'})`);
      }).catch((error: Error) => {
        logger.warn(TAG, `setMissionContinueState failed: ${String(error)}`);
      });
    } catch (error) {
      logger.warn(TAG, `setMissionContinueState error: ${String(error)}`);
    }
  }

  /**
   * 注册听书等场景的接续状态来源提供器（入口 Ability 触发 onContinue 时取最新会话快照）。
   * 传入 null 清除。
   */
  public setContinuationPackSourceProvider(provider: (() => ContinuationPackSource | null) | null): void {
    this.continuationPackSourceProvider = provider;
    logger.debug(TAG, `setContinuationPackSourceProvider: ${provider ? 'registered' : 'cleared'}`);
  }

  /**
   * [修复] 激活接续入口（阅读器/听书前台场景调用）：
   * 入口统一挂在入口 Ability 的 mission 上（见 setMissionContinueState 说明）；
   * 同时记住当前阅读器上下文（源端接续后自动拉起遥控器使用）。
   * 权限在"触发接续"时（packContinuationWant）才做前置校验，此处异步确保权限就绪。
   */
  public activateMissionContinueEntry(context: common.UIAbilityContext): void {
    this.activeReaderContext = context;
    this.setMissionContinueState(context, true);
    void distributedPermissionManager.ensurePermission(context).then((granted: boolean) => {
      if (granted) {
        logger.info(TAG, '分布式数据同步权限就绪（接续入口场景）');
      } else {
        logger.warn(TAG, '分布式数据同步权限未授权：入口已显示，触发接续将被拒绝并再次请求权限');
      }
    });
  }

  /**
   * 源端接续状态打包（EntryAbility 与阅读器/听书 Ability 共用）
   * @param wantParam 系统传入的接续参数容器（须写入业务状态）
   * @param context 当前 Ability 上下文（用于权限请求弹窗）
   * @param source 可选外部状态来源（如听书会话快照）；缺省使用 AppStorage currentRead*（阅读器）
   */
  public packContinuationWant(
    wantParam: Record<string, Object>,
    context: common.UIAbilityContext,
    source?: ContinuationPackSource
  ): AbilityConstant.OnContinueResult {
    // [修复] 权限前置：进入接续流转前必须确保分布式数据同步权限完整，
    // 未授权则拒绝流转并异步弹出权限请求（不进入接续状态）
    if (!distributedPermissionManager.isPermissionGrantedSync()) {
      logger.warn(TAG, 'packContinuationWant: 分布式数据同步权限未授权，拒绝进入接续流转（异步请求权限中）');
      void distributedPermissionManager.ensurePermission(context);
      return AbilityConstant.OnContinueResult.REJECT;
    }

    // 接续入口挂在入口 Ability mission 上：onContinue 由 EntryAbility 触发，
    // 听书等场景通过提供器补充最新会话快照（阅读器场景直接使用 AppStorage 阅读态）
    let resolvedSource: ContinuationPackSource | undefined = source;
    if (!resolvedSource && this.continuationPackSourceProvider) {
      try {
        resolvedSource = this.continuationPackSourceProvider() ?? undefined;
      } catch (error) {
        logger.warn(TAG, `packContinuationWant: 接续状态来源提供器执行异常: ${String(error)}`);
      }
    }

    let bookId: string = '';
    let chapterIndex: number = 0;
    let pageIndex: number = 0;
    let offset: number = 0;
    let sourceType: string = '';
    let isLocal: boolean = false;

    if (resolvedSource) {
      // 外部来源（听书等）：直接使用提供的状态
      bookId = resolvedSource.bookId || '';
      chapterIndex = resolvedSource.chapterIndex;
      pageIndex = resolvedSource.pageIndex;
      offset = resolvedSource.offset;
      sourceType = resolvedSource.sourceType;
      isLocal = resolvedSource.isLocal;
      logger.info(TAG, `packContinuationWant: 使用外部状态来源, bookId=${bookId}, chapterIndex=${chapterIndex}, pageIndex=${pageIndex}, offset=${offset}, sourceType=${sourceType}`);
    } else {
      // 阅读器来源：校验阅读态（未在阅读器内或最近进度同步已过期则拒绝流转）
      if (!distributedReadingService.isReadingActive()) {
        logger.warn(TAG, 'packContinuationWant: 当前未处于有效阅读状态，拒绝接续流转（详见 isReadingActive 日志）');
        return AbilityConstant.OnContinueResult.REJECT;
      }
      bookId = AppStorage.get<string>('currentReadBookId') || '';
      chapterIndex = AppStorage.get<number>('currentReadChapterIndex') || 0;
      pageIndex = AppStorage.get<number>('currentReadPageIndex') || 0;
      offset = AppStorage.get<number>('currentReadOffset') || 0;
      sourceType = AppStorage.get<string>('currentReadSourceType') || '';
      isLocal = AppStorage.get<boolean>('currentReadIsLocal') || false;
      logger.info(TAG, `packContinuationWant: 使用阅读器状态来源, bookId=${bookId}, chapterIndex=${chapterIndex}, pageIndex=${pageIndex}, offset=${offset}, sourceType=${sourceType}, isLocal=${isLocal}`);
    }

    if (bookId.length <= 0) {
      logger.warn(TAG, 'packContinuationWant: 接续书籍ID为空，拒绝接续流转');
      return AbilityConstant.OnContinueResult.REJECT;
    }

    logger.info(TAG, `packContinuationWant: bookId=${bookId}, chapter=${chapterIndex}, page=${pageIndex}, offset=${offset}, sourceType=${sourceType}, external=${resolvedSource ? 'yes' : 'no'}`);

    // 生成分布式状态机 sessionId 并写入 wantParam（系统保证送达目标端）
    const sessionId = `continuation_${Date.now()}`;
    wantParam['distributedSessionId'] = sessionId;
    wantParam['bookId'] = bookId;
    wantParam['isLocal'] = isLocal;
    wantParam['chapterIndex'] = chapterIndex;
    wantParam['pageIndex'] = pageIndex;
    wantParam['offset'] = offset;
    wantParam['sourceType'] = sourceType;

    // 启动分布式状态机会话并写入进度快照（实时同步通道，供遥控器等使用）
    distributedDataSyncManager.joinSession(sessionId);
    distributedDataSyncManager.updateProgress(bookId, chapterIndex, pageIndex, offset, sourceType);

    // [修复] 独立连接通道（局域网 TCP）：分布式数据对象通道在部分设备被平台级封禁
    // （GetAnonyLocalUdid 无权限），在此同步解析本机 IP 并把地址写入 wantParam，
    // 目标端恢复时按该地址回连，遥控指令/进度经 TCP 直达。
    const remoteControlLanIp = distributedDataSyncManager.resolveLocalLanIp();
    if (remoteControlLanIp.length > 0) {
      const remoteControlLanPort = distributedDataSyncManager.prepareSocketServer(sessionId);
      wantParam['remoteControlLanIp'] = remoteControlLanIp;
      wantParam['remoteControlLanPort'] = remoteControlLanPort;
      logger.info(TAG, `接续打包已附带独立连接通道地址: ${remoteControlLanIp}:${remoteControlLanPort}`);
    } else {
      logger.warn(TAG, '无法获取本机局域网IP，独立连接通道不可用（仅依赖分布式数据对象通道）');
    }

    // 未授权时异步提起权限请求（不阻塞本次流转；快照通道不依赖权限）
    try {
      void distributedPermissionManager.ensurePermission(context);
    } catch (error) {
      logger.warn(TAG, `接续时权限请求异常: ${String(error)}`);
    }

    // 触发全局接续事件（源端已不再弹窗询问，改为自动拉起遥控器；事件仅用于通知与日志）
    const continuationPayload: ContinuationTriggeredPayload = new ContinuationTriggeredPayload(
      sessionId, bookId, chapterIndex, pageIndex, offset, sourceType, isLocal
    );
    try {
      eventBus.publish(GameEvent.CONTINUATION_TRIGGERED, continuationPayload);
    } catch (error) {
      logger.warn(TAG, `接续事件发布异常: ${String(error)}`);
    }

    // [修复] 源端接续成功后自动拉起遥控器：入口任务被迁走后源端阅读器任务保留，
    // 用阅读器上下文（应用仍在前台）发起启动，避免入口上下文随迁移失效；
    // 若启动受限（后台启动管控），源端仍有阅读器窗口兜底，不会出现空白任务
    this.markContinuationMigrationActive();
    this.scheduleSourceRemoteControlLaunch(context, continuationPayload);

    logger.info(TAG, `packContinuationWant 完成: sessionId=${sessionId}, bookId=${bookId}`);
    return AbilityConstant.OnContinueResult.AGREE;
  }

  /**
   * 标记接续迁移进行中：入口任务被系统迁移后，源端 EntryAbility.onDestroy
   * 会触发，需跳过全局清理（WindowManager/错误监控/分布式会话）以保留仍在运行的阅读器任务。
   * 标记 5 分钟后自动清除。
   */
  private markContinuationMigrationActive(): void {
    this.continuationMigrationStartedAt = Date.now();
    if (this.continuationMigrationClearTimer >= 0) {
      clearTimeout(this.continuationMigrationClearTimer);
      this.continuationMigrationClearTimer = -1;
    }
    this.continuationMigrationClearTimer = setTimeout(() => {
      this.continuationMigrationClearTimer = -1;
      this.continuationMigrationStartedAt = 0;
      logger.info(TAG, '接续迁移标记已自动清除');
    }, 5 * 60 * 1000);
    logger.info(TAG, '已标记接续迁移进行中（源端入口任务即将被系统迁移）');
  }

  /**
   * 是否处于接续迁移窗口内（供 EntryAbility.onDestroy 判断是否跳过全局清理）
   */
  public isContinuationMigrationActive(): boolean {
    return this.continuationMigrationStartedAt > 0;
  }

  /**
   * 源端自动拉起遥控器：接续握手结束后按时间点多次尝试启动独立遥控器实例。
   * 实证：接续迁移会销毁源端被迁移的 Ability（连续流转时其上下文报 "The caller has been released"），
   * 因此按 600/2500/5000ms 三个时间点重试，且每次按"入口 Ability → 阅读器 → 打包上下文"的
   * 候选链逐个尝试（入口 Ability 不参与迁移时始终存活，是连续流转最可靠的上下文）。
   * 全部未生效时兜底拉起入口 Ability，避免源端停留在桌面。
   */
  private scheduleSourceRemoteControlLaunch(
    sourceContext: common.UIAbilityContext,
    payload: ContinuationTriggeredPayload
  ): void {
    this.remoteControlLaunchStartTimestamp = Date.now();
    // [修复] 阅读器上下文在打包瞬间一定存活且应用处于前台，是 0ms 首发的唯一可靠上下文；
    // 入口 Ability 上下文不随阅读器迁移销毁，但应用进入后台后受后台启动管控拦截，
    // 仅作为迁移后重试的候选。
    const launchCandidates: common.UIAbilityContext[] = [];
    const candidateContexts: (common.UIAbilityContext | null)[] = [
      this.activeReaderContext,
      this.entryAbilityContext,
      sourceContext
    ];
    for (const candidate of candidateContexts) {
      if (candidate && !launchCandidates.includes(candidate)) {
        launchCandidates.push(candidate);
      }
    }

    for (let i = 0; i < SOURCE_REMOTE_CONTROL_ATTEMPT_DELAYS_MS.length; i++) {
      const delayMs = SOURCE_REMOTE_CONTROL_ATTEMPT_DELAYS_MS[i];
      const attemptIndex = i + 1;
      const attemptLabel = `源端遥控器自动拉起尝试 ${attemptIndex}/${SOURCE_REMOTE_CONTROL_ATTEMPT_DELAYS_MS.length}（触发后 ${delayMs}ms）`;
      setTimeout(() => {
        if (this.isRemoteControlAlive()) {
          logger.info(TAG, `源端遥控器已成功启动，跳过自动拉起尝试 ${attemptIndex}`);
          return;
        }
        logger.info(TAG, `${attemptLabel}, sessionId=${payload.sessionId}`);
        this.tryLaunchRemoteControlFromCandidates(payload, launchCandidates, attemptLabel);
      }, delayMs);
    }

    // 兜底：遥控器多次尝试后仍未生效时，拉起源端入口 Ability（至少回到应用主页而非桌面）
    for (let i = 0; i < SOURCE_ENTRY_FALLBACK_DELAYS_MS.length; i++) {
      const delayMs = SOURCE_ENTRY_FALLBACK_DELAYS_MS[i];
      setTimeout(() => {
        if (this.isRemoteControlAlive()) {
          logger.info(TAG, '源端遥控器已成功启动，跳过入口 Ability 兜底拉起');
          return;
        }
        logger.warn(TAG, `源端遥控器兜底检查（第 ${i + 1} 次）：拉起源端入口 Ability 保证窗口在前台`);
        this.bringEntryAbilityToFront(launchCandidates);
      }, delayMs);
    }
  }

  /**
   * 按候选上下文链逐个尝试启动遥控器：当前上下文失败（如被迁移释放）时自动切换下一个。
   */
  private tryLaunchRemoteControlFromCandidates(
    payload: ContinuationTriggeredPayload,
    candidates: common.UIAbilityContext[],
    attemptLabel: string
  ): void {
    if (candidates.length <= 0) {
      logger.warn(TAG, `${attemptLabel} 失败（无可用 Ability 上下文）`);
      return;
    }
    const currentContext = candidates[0];
    const remainingCandidates = candidates.slice(1);
    openRemoteControlInIsolatedAbilityFromContext(currentContext, payload, 'continuation_auto', () => {
      logger.warn(TAG, `${attemptLabel} 使用当前上下文失败（Promise 拒绝），切换下一个候选上下文`);
      this.tryLaunchRemoteControlFromCandidates(payload, remainingCandidates, attemptLabel);
    });
  }

  /**
   * 判断源端遥控器是否已成功拉起。
   * [修复] 仅靠 RemoteControlAbility.onCreate 的 token 会误判：接续握手期间发起的
   * 0ms 启动可能只创建 Ability 而窗口被吞掉（僵尸实例），此时页面永远不会出现。
   * 规则：
   * 1) RemoteControlPage 页面就绪 token 晚于本次拉起时间点 → 真正存活；
   * 2) Ability 刚创建（宽限期内）→ 暂时视为存活，给页面渲染留时间，避免 300ms 重试重复建实例；
   * 3) Ability 已创建但超过宽限期页面仍未就绪 → 视为未存活，允许后续重试重建实例。
   */
  private isRemoteControlAlive(): boolean {
    const launchStartedAt = this.remoteControlLaunchStartTimestamp;
    const pageReadyToken = AppStorage.get<number>('remoteControlPageReadyToken') || 0;
    if (pageReadyToken >= launchStartedAt) {
      return true;
    }
    const abilityToken = AppStorage.get<number>('remoteControlAbilityActiveToken') || 0;
    if (abilityToken >= launchStartedAt) {
      const abilityAge = Date.now() - abilityToken;
      if (abilityAge < REMOTE_CONTROL_PAGE_READY_GRACE_MS) {
        return true;
      }
      logger.warn(TAG, `遥控器 Ability 已创建但页面未就绪（可能被接续握手吞掉窗口），视为未存活: age=${abilityAge}ms`);
      return false;
    }
    return false;
  }

  /**
   * 回退拉起入口 Ability（源端窗口兜底：至少回到应用主页而不是桌面）。
   * [修复] 按候选上下文链逐个尝试，规避被迁移 Ability 的上下文已释放（The caller has been released）问题。
   */
  private bringEntryAbilityToFront(candidates: common.UIAbilityContext[]): void {
    if (candidates.length <= 0) {
      logger.error(TAG, 'bringEntryAbilityToFront: 无可用 Ability 上下文');
      return;
    }
    const context = candidates[0];
    const remaining = candidates.slice(1);
    try {
      const want: Want = {
        bundleName: APP_BUNDLE_NAME,
        abilityName: ENTRY_ABILITY_NAME
      };
      context.startAbility(want).then(() => {
        logger.info(TAG, '已回退拉起入口 Ability（源端窗口兜底）');
      }).catch((error: Error) => {
        logger.error(TAG, `回退拉起入口 Ability 失败: ${String(error)}`);
        this.bringEntryAbilityToFront(remaining);
      });
    } catch (error) {
      logger.error(TAG, `bringEntryAbilityToFront 异常: ${String(error)}`);
      this.bringEntryAbilityToFront(remaining);
    }
  }

  /**
   * 目标端恢复接续状态（设置 AppStorage 接续标志并立即加入分布式会话）
   * 供 EntryAbility 与阅读器/听书 Ability 的 CONTINUATION 启动路径共用。
   *
   * @param want 系统转交的接续 Want（含 distributedSessionId 与阅读进度快照）
   * @param context 可选 Ability 上下文；提供时立即初始化分布式管理器并确保权限后入会
   *                （阅读器 Ability 接续启动时 EntryAbility 可能尚未创建，必须用本上下文入会，
   *                 否则"遥控器连不上"——目标端从未加入会话）
   */
  public restoreContinuationState(want: Want, context?: common.UIAbilityContext): void {
    if (!want.parameters || !want.parameters['distributedSessionId']) {
      // [日志完善] 区分"非接续启动"与"接续 want 但字段缺失"，便于排查转交/恢复链路
      logger.debug(TAG, 'restoreContinuationState: want 中无 distributedSessionId，非跨端接续启动，跳过');
      return;
    }
    const sessionId = want.parameters['distributedSessionId'] as string;
    const bookId = want.parameters['bookId'] as string;
    const isLocal = want.parameters['isLocal'] as boolean;
    const chapterIndex = want.parameters['chapterIndex'] as number;
    const pageIndex = want.parameters['pageIndex'] as number;
    const offset = want.parameters['offset'] as number;
    const rawSourceType = want.parameters['sourceType'] as string;
    const sourceType = this.normalizeContinuationSourceType(rawSourceType);

    // [诊断] 接续链路排查需要完整日志：目标端用户若把日志等级设为“关闭”，
    // 接续期间临时强制为 DEBUG（仅本次进程运行时生效，不改写用户设置）。
    if (logger.getHilogLevelIndex() === 0) {
      logger.initializeHilogLevelFromIndex(1);
      logger.info(TAG, '接续恢复期间已临时开启 DEBUG 日志（运行时生效，不修改用户设置）');
    }

    logger.info(TAG, `restoreContinuationState: sessionId=${sessionId}, bookId=${bookId}, chapterIndex=${chapterIndex}, pageIndex=${pageIndex}, offset=${offset}, sourceType=${rawSourceType}->${sourceType}, isLocal=${isLocal}, hasContext=${context ? 'yes' : 'no'}`);

    // 先清理旧的接续标志，避免与历史残留状态混合导致误触发
    distributedReadingService.clearContinuationFlags();

    // [修复] 立即加入分布式状态机会话（不再延迟 1500ms）：
    // 1) 阅读器 Ability 接续启动后会转交并可能被终止，延迟入会可能随 Ability 生命周期丢失；
    // 2) 分布式管理器为进程级单例，与会话对象生命周期无关，可安全提前入会；
    // 3) 等待会话对象建立的竞态已由 waitForSessionObject 轮询兜底。
    if (context) {
      distributedDataSyncManager.initialize(context);
    }
    distributedDataSyncManager.joinSession(sessionId);
    logger.info(TAG, `restoreContinuationState: 已立即加入分布式状态机会话, sessionId=${sessionId}`);
    // [诊断] 目标端入会后输出会话状态，确认本端会话对象已建立并等待对端设备上线
    distributedDataSyncManager.diagnoseSession('目标端恢复入会');

    // [修复] 独立连接通道（局域网 TCP）：按源端随 Want 携带的地址回连，
    // 不依赖分布式数据服务（该服务在部分设备被平台级封禁）。
    const remoteControlLanIp = want.parameters['remoteControlLanIp'] as string;
    const remoteControlLanPortRaw = want.parameters['remoteControlLanPort'] as number;
    if (remoteControlLanIp && remoteControlLanIp.length > 0 && remoteControlLanPortRaw > 0) {
      const remoteControlLanPort = Math.floor(remoteControlLanPortRaw);
      distributedDataSyncManager.connectSocketClient(sessionId, remoteControlLanIp, remoteControlLanPort);
      logger.info(TAG, `目标端已发起独立连接通道回连: ${remoteControlLanIp}:${remoteControlLanPort}, sessionId=${sessionId}`);
    } else {
      logger.info(TAG, '接续 Want 未携带独立连接通道地址，仅使用分布式数据对象通道');
    }

    // 目标端权限确保 + 会话重试：权限未授权时 setSessionId 会以 201 失败，
    // 授权/组网就绪后通过 retryJoinSession 重建同步通道（遥控器连接的前提）。
    if (context) {
      void distributedPermissionManager.ensurePermission(context).then((granted: boolean): void => {
        if (granted) {
          logger.info(TAG, 'restoreContinuationState: 目标端分布式数据同步权限就绪，检查会话是否需要重建');
          distributedDataSyncManager.retryJoinSession();
        } else {
          logger.warn(TAG, 'restoreContinuationState: 目标端权限未就绪，会话同步可能未建立（后续检查点会继续请求权限）');
        }
      });
    }
    // 兜底重试：权限弹窗授权耗时、组网延迟等场景下，稍后再次尝试建立会话（已成功建立时为空操作）
    setTimeout(() => {
      distributedDataSyncManager.retryJoinSession();
    }, TARGET_JOIN_RETRY_DELAY_MS);

    // bookId 为空说明源端未在阅读（或旧版本流转），不设置接续导航标志，
    // 避免目标端误显示"接续状态"却无法恢复
    if (!bookId || bookId.length <= 0) {
      logger.warn(TAG, 'restoreContinuationState: bookId 为空，跳过接续导航（仅加入会话）');
      return;
    }

    // 设置标志位，让 MainMenuPage 直接拉起内容
    AppStorage.setOrCreate('widgetTargetPage', 'continueRead');
    AppStorage.setOrCreate('widgetContentType', sourceType);
    AppStorage.setOrCreate('widgetContentId', bookId);
    AppStorage.setOrCreate('continuationSessionId', sessionId);
    AppStorage.setOrCreate('continuationPageIndex', pageIndex);
    AppStorage.setOrCreate('continuationOffset', offset);
    AppStorage.setOrCreate('continuationChapterIndex', chapterIndex);
    AppStorage.setOrCreate('continuationIsLocal', isLocal);
    logger.info(TAG, `restoreContinuationState: 接续导航标志已设置, contentType=${sourceType}, contentId=${bookId}`);
  }

  /**
   * 目标端由阅读器/听书 Ability 接续启动时：转交 EntryAbility 统一处理接续导航
   * （MainMenuPage 消费 AppStorage continuation* 后按内容类型打开对应阅读器）。
   *
   * 握手式终止时序（修复"目标端回桌面/白屏"）：
   * 1. 不在 onCreate 内同步 startAbility —— 实证该时机的启动请求会被系统吞掉
   *    （Promise resolve 但 EntryAbility 不创建），且疑似导致接续 Ability 拿不到窗口舞台；
   * 2. 接续 Ability 先展示"正在恢复"中转页；1200/4000/8000ms 三个时间点分时尝试启动 EntryAbility；
   * 3. 轮询等待 EntryAbility 前台确认（onCreate/onNewWant/onForeground 写 token），确认后终止自身；
   *    14s 超时强制终止，避免目标端停留空白窗口。
   */
  public redirectContinuationToEntryAbility(context: common.UIAbilityContext): void {
    this.redirectForegroundConfirmThreshold = Date.now();
    if (this.redirectPollTimer >= 0) {
      clearTimeout(this.redirectPollTimer);
      this.redirectPollTimer = -1;
    }
    logger.info(TAG, '目标端接续转交：分时启动 EntryAbility，以前台确认驱动终止本 Ability');
    this.startRedirectForegroundConfirmPoll(context);
  }

  /**
   * 轮询驱动转交流程：到时间点发起 EntryAbility 启动尝试；前台确认（token）后终止本 Ability；
   * 超时强制终止。
   */
  private startRedirectForegroundConfirmPoll(context: common.UIAbilityContext): void {
    const startedAt = Date.now();
    let startAttemptCount = 0;
    const want: Want = {
      bundleName: APP_BUNDLE_NAME,
      abilityName: ENTRY_ABILITY_NAME,
      parameters: {
        'continuationRedirect': true
      }
    };

    const tryStartEntryAbility = (): void => {
      if (startAttemptCount >= REDIRECT_START_ATTEMPT_DELAYS_MS.length) {
        return;
      }
      const dueDelayMs = REDIRECT_START_ATTEMPT_DELAYS_MS[startAttemptCount];
      if (Date.now() - startedAt < dueDelayMs) {
        return;
      }
      startAttemptCount += 1;
      logger.info(TAG, `转交 EntryAbility 尝试 ${startAttemptCount}/${REDIRECT_START_ATTEMPT_DELAYS_MS.length}（onCreate 后 ${dueDelayMs}ms）`);
      context.startAbility(want).then(() => {
        logger.info(TAG, `转交 EntryAbility 尝试 ${startAttemptCount} 请求已受理`);
      }).catch((error: Error) => {
        logger.error(TAG, `转交 EntryAbility 尝试 ${startAttemptCount} 失败: ${String(error)}`);
      });
    };

    const poll = (): void => {
      const confirmToken = AppStorage.get<number>('continuationRedirectForegroundToken') || 0;
      if (confirmToken >= this.redirectForegroundConfirmThreshold) {
        logger.info(TAG, 'EntryAbility 已前台接管接续导航，终止接续启动的 Ability');
        this.terminateContinuationHost(context);
        return;
      }
      const elapsedMs = Date.now() - startedAt;
      if (elapsedMs >= REDIRECT_FOREGROUND_CONFIRM_TIMEOUT_MS) {
        logger.warn(TAG, '等待 EntryAbility 前台确认超时，强制终止接续启动的 Ability');
        this.terminateContinuationHost(context);
        return;
      }
      tryStartEntryAbility();
      this.redirectPollTimer = setTimeout(() => {
        this.redirectPollTimer = -1;
        poll();
      }, REDIRECT_FOREGROUND_CONFIRM_POLL_MS);
    };
    poll();
  }

  private terminateContinuationHost(context: common.UIAbilityContext): void {
    if (this.redirectPollTimer >= 0) {
      clearTimeout(this.redirectPollTimer);
      this.redirectPollTimer = -1;
    }
    context.terminateSelf().then(() => {
      logger.info(TAG, '接续启动的 Ability 已终止');
    }).catch((error: Error) => {
      logger.warn(TAG, `终止接续启动的 Ability 失败（可能已终止）: ${String(error)}`);
    });
  }

  private normalizeContinuationSourceType(sourceType: string): string {
    const safeSourceType = sourceType ? sourceType : '';
    const normalized = safeSourceType.trim().toLowerCase();
    if (normalized === 'novel') {
      return 'novel';
    }
    if (normalized === 'ebook' || normalized === 'epub' || normalized === 'pdf' || normalized === 'txt') {
      return 'ebook';
    }
    return 'manga';
  }
}

export const continuationStateHelper = ContinuationStateHelper.getInstance();
