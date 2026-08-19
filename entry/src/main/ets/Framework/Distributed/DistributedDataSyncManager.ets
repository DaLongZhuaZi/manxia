import distributedDataObject from '@ohos.data.distributedDataObject';
import common from '@ohos.app.ability.common';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import {
  RemoteControlSocketChannel,
  RemoteControlSocketMessage
} from './RemoteControlSocketChannel';

const TAG = 'DistributedDataSyncManager';

export interface SyncReadingState {
  sessionId: string;
  bookId: string;
  sourceType: string;
  chapterIndex: number;
  pageIndex: number;
  offset: number;
  instructionType: string;
  instructionPayload: string;
  timestamp: number;
}

export class DistributedDataSyncManager {
  private static instance: DistributedDataSyncManager;
  private context: common.UIAbilityContext | null = null;
  private syncObj: distributedDataObject.DataObject | null = null;
  private sessionId: string = '';
  /** setSessionId 最近一次是否失败（权限未授权 201 / 未组网等）——失败后允许对同一会话重新尝试建立 */
  private lastJoinFailed: boolean = false;
  
  private dataChangedCallbacks: Set<(state: SyncReadingState) => void> = new Set();
  private statusChangedCallbacks: Set<(status: 'online' | 'offline' | 'restored' | 'error', message?: string) => void> = new Set();

  /** 最近一次会话状态（晚注册的回调立即回放该状态，如接续完成后才打开的遥控器页，
   *  否则页面会永远停留在“正在连接目标设备”且再没有任何状态事件可唤醒它） */
  private lastStatus: 'none' | 'online' | 'offline' | 'restored' | 'error' = 'none';
  private lastStatusMessage: string = '';

  /** 会话内设备上线/下线事件流水（诊断用：证明 DataObject 会话是否真正跨设备建立） */
  private statusEventLog: string[] = [];

  /** 独立连接通道（局域网 TCP）：分布式数据对象通道不可用时的遥控指令/进度直达链路 */
  private readonly socketChannel: RemoteControlSocketChannel = RemoteControlSocketChannel.getInstance();
  private socketChannelListenerAttached: boolean = false;

  // 远端状态等待：用于目标端恢复接续时，等待分布式数据对象把源端进度同步过来
  private remoteStateWaitResolve: ((state: SyncReadingState | null) => void) | null = null;
  private remoteStateWaitTimer: number = -1;

  private constructor() {}

  public static getInstance(): DistributedDataSyncManager {
    if (!DistributedDataSyncManager.instance) {
      DistributedDataSyncManager.instance = new DistributedDataSyncManager();
    }
    return DistributedDataSyncManager.instance;
  }

  public initialize(context: common.UIAbilityContext): void {
    this.context = context;
  }

  /**
   * 启动同步会话
   * 源端生成 sessionId，目标端加入同一 sessionId
   */
  public joinSession(sessionId: string): void {
    if (!this.context) {
      logger.error(TAG, 'Manager not initialized with context');
      this.notifyStatusChange('error', 'Manager not initialized with context');
      return;
    }

    // 防重入：已加入同一会话且上次建立成功时直接返回，避免重复创建对象
    if (this.syncObj && this.sessionId === sessionId) {
      if (this.lastJoinFailed) {
        // 上次 setSessionId 失败（如权限未授权 201 / 未组网）：
        // 对象已存在但未真正同步，复用对象重新建立会话，而不是创建新对象
        logger.info(TAG, `Session join previously failed, retrying setSessionId for same session: ${sessionId}`);
        this.retrySetSessionId(sessionId);
      } else {
        logger.info(TAG, `Already joined session: ${sessionId}, skip duplicate join`);
      }
      return;
    }

    // 切换会话前先释放旧会话对象，避免旧会话对象残留
    // （注意：不清理 dataChangedCallbacks/statusChangedCallbacks，这些功能回调
    //  与具体会话无关，阅读器/遥控器注册后应跨会话保持有效）
    if (this.syncObj) {
      logger.info(TAG, `Releasing previous session before joining new one: ${this.sessionId}`);
      this.releaseSyncObject();
    }

    this.sessionId = sessionId;
    this.lastJoinFailed = false;
    // 新会话开始：清空上一会话状态，等 setSessionId 结果再播报（避免把旧会话的 online 回放给新页面）
    this.lastStatus = 'none';
    this.lastStatusMessage = '';

    const defaultState: SyncReadingState = {
      sessionId: sessionId,
      bookId: '',
      sourceType: '',
      chapterIndex: 0,
      pageIndex: 0,
      offset: 0,
      instructionType: 'none',
      instructionPayload: '',
      timestamp: Date.now()
    };

    try {
      this.syncObj = distributedDataObject.create(this.context, defaultState);
      
      this.syncObj.on('change', (sessionId: string, fields: Array<string>) => {
        // 只处理当前会话的数据变化，防止旧会话/其他会话数据串扰
        if (sessionId !== this.sessionId) {
          logger.warn(TAG, `Ignore data change from other session: ${sessionId}, current=${this.sessionId}`);
          return;
        }
        logger.info(TAG, `Data changed in session ${sessionId}, fields: ${fields.join(',')}`);
        if (this.syncObj) {
          const currentState = this.extractState();
          this.dataChangedCallbacks.forEach(callback => callback(currentState));
          // 远端数据到达（bookId 非空表示收到了源端写入的进度）
          if (currentState.bookId.length > 0) {
            this.resolveRemoteStateWait(currentState);
          }
        }
      });

      this.syncObj.on('status', (sessionId: string, networkId: string, status: 'online' | 'offline' | 'restored') => {
        logger.info(TAG, `Session ${sessionId} device ${networkId} is ${status}`);
        const statusEvent = `${sessionId}|${networkId}|${status}|${Date.now()}`;
        this.statusEventLog.push(statusEvent);
        if (this.statusEventLog.length > 20) {
          this.statusEventLog.splice(0, this.statusEventLog.length - 20);
        }
        this.notifyStatusChange(status, `Device ${networkId} is ${status}`);
      });

      this.syncObj.setSessionId(sessionId).then(() => {
        this.lastJoinFailed = false;
        logger.info(TAG, `Successfully joined distributed data session: ${sessionId}`);
        this.notifyStatusChange('online', `Successfully joined session: ${sessionId}`);
      }).catch((err: Error) => {
        this.lastJoinFailed = true;
        const errorMsg = `Failed to set distributed data session: ${String(err)}`;
        logger.error(TAG, errorMsg);
        // [日志完善] 会话建立失败常见原因：ohos.permission.DISTRIBUTED_DATASYNC 未授权（错误码 201）、设备未组网
        logger.warn(TAG, `会话建立失败，常见原因: 1) 分布式数据同步权限未授权(201) 2) 设备未组网/未登录同一账号，err=${String(err)}`);
        this.notifyStatusChange('error', errorMsg);
        // 会话建立失败时，通知等待方立即返回，避免无限等待
        this.resolveRemoteStateWait(null);
      });
    } catch (e) {
      this.lastJoinFailed = true;
      const errorMsg = `Failed to join distributed data session: ${String(e)}`;
      logger.error(TAG, errorMsg);
      this.notifyStatusChange('error', errorMsg);
      this.syncObj = null;
      this.resolveRemoteStateWait(null);
    }
  }

  /**
   * 对已有会话对象重新执行 setSessionId（上次建立失败后的重试入口）。
   * 供权限刚授予、设备刚组网等场景调用；未失败或对象缺失时为空操作。
   */
  public retryJoinSession(): void {
    if (!this.syncObj || this.sessionId.length <= 0) {
      logger.debug(TAG, 'retryJoinSession: 无会话对象或会话ID为空，跳过');
      return;
    }
    if (!this.lastJoinFailed) {
      logger.debug(TAG, `retryJoinSession: 会话 ${this.sessionId} 已成功建立，跳过`);
      return;
    }
    this.retrySetSessionId(this.sessionId);
  }

  private retrySetSessionId(sessionId: string): void {
    if (!this.syncObj) {
      logger.warn(TAG, 'retrySetSessionId: 会话对象缺失，跳过重试');
      return;
    }
    this.syncObj.setSessionId(sessionId).then(() => {
      this.lastJoinFailed = false;
      logger.info(TAG, `重试建立分布式会话成功: ${sessionId}`);
      this.notifyStatusChange('online', `Successfully rejoined session: ${sessionId}`);
    }).catch((err: Error) => {
      this.lastJoinFailed = true;
      logger.warn(TAG, `重试建立分布式会话仍失败: ${sessionId}, err=${String(err)}`);
      this.notifyStatusChange('error', `Failed to rejoin session: ${String(err)}`);
    });
  }

  private notifyStatusChange(status: 'online' | 'offline' | 'restored' | 'error', message?: string): void {
    this.lastStatus = status;
    this.lastStatusMessage = message ?? '';
    this.statusChangedCallbacks.forEach(callback => callback(status, message));
  }

  /**
   * 更新阅读进度
   */
  public updateProgress(bookId: string, chapterIndex: number, pageIndex: number, offset: number, sourceType: string): void {
    if (!this.syncObj) return;

    try {
      this.syncObj['sessionId'] = this.sessionId;
      this.syncObj['bookId'] = bookId;
      this.syncObj['chapterIndex'] = chapterIndex;
      this.syncObj['pageIndex'] = pageIndex;
      this.syncObj['offset'] = offset;
      this.syncObj['sourceType'] = sourceType;
      this.syncObj['timestamp'] = Date.now();
      // 独立连接通道：进度经局域网 TCP 直达遥控端
      this.sendOverSocketChannel();
      
      // Save changes to distributed object
      this.syncObj.save('local').then((result) => {
        logger.debug(TAG, `Progress saved: ${result.sessionId}, ${result.version}`);
      }).catch((err: Error) => {
        logger.error(TAG, `Failed to save progress: ${String(err)}`);
      });
    } catch (e) {
      logger.error(TAG, `Error updating progress: ${String(e)}`);
    }
  }

  /**
   * 发送指令（例如目标端请求源端下载章节）
   */
  public sendInstruction(type: string, payload: string): void {
    if (!this.syncObj) {
      this.notifyStatusChange('error', 'Session not available');
      return;
    }

    try {
      // [诊断] 发送前输出会话状态，确认会话是否已跨设备建立（状态事件是否收到过）
      this.diagnoseSession(`发送指令:${type}`);
      this.syncObj['sessionId'] = this.sessionId;
      this.syncObj['instructionType'] = type;
      this.syncObj['instructionPayload'] = payload;
      this.syncObj['timestamp'] = Date.now();
      // 独立连接通道：指令经局域网 TCP 直达（DataObject 通道被平台封禁时的兜底）
      this.sendOverSocketChannel();
      
      this.syncObj.save('local').then(() => {
        logger.info(TAG, `Sent instruction: ${type}`);
      }).catch((err: Error) => {
        const errorMsg = `Failed to save instruction: ${String(err)}`;
        logger.error(TAG, errorMsg);
        this.notifyStatusChange('error', errorMsg);
      });
    } catch (e) {
      const errorMsg = `Error sending instruction: ${String(e)}`;
      logger.error(TAG, errorMsg);
      this.notifyStatusChange('error', errorMsg);
    }
  }

  /**
   * 添加数据变更监听
   */
  public addOnDataChangedCallback(callback: (state: SyncReadingState) => void): void {
    this.dataChangedCallbacks.add(callback);
  }

  /**
   * 移除数据变更监听
   */
  public removeOnDataChangedCallback(callback: (state: SyncReadingState) => void): void {
    this.dataChangedCallbacks.delete(callback);
  }

  /**
   * 添加状态变更监听
   */
  public addOnStatusChangedCallback(callback: (status: 'online' | 'offline' | 'restored' | 'error', message?: string) => void): void {
    this.statusChangedCallbacks.add(callback);
    // [修复] 晚注册回调立即回放最近一次会话状态：接续完成后才打开的遥控器页
    // 错过了 joinSession 的 online 播报，不回放会永远停留在“正在连接目标设备”
    if (this.lastStatus !== 'none') {
      const replayedStatus: 'online' | 'offline' | 'restored' | 'error' = this.lastStatus;
      const replayedMessage: string = this.lastStatusMessage;
      logger.info(TAG, `晚注册状态回调回放当前会话状态: ${replayedStatus}, message=${replayedMessage}`);
      // [修复] 延迟到下一轮事件循环再回放：注册方可能在页面 onReady 等构建期内调用本方法，
      // 同步回放会在构建期修改 @State / 弹 Toast，导致页面渲染异常（遥控器页空白）
      setTimeout(() => {
        try {
          callback(replayedStatus, replayedMessage);
        } catch (error) {
          logger.warn(TAG, `回放状态回调执行异常: ${String(error)}`);
        }
      }, 0);
    }
  }

  /**
   * 移除状态变更监听
   */
  public removeOnStatusChangedCallback(callback: (status: 'online' | 'offline' | 'restored' | 'error', message?: string) => void): void {
    this.statusChangedCallbacks.delete(callback);
  }

  /**
   * 提取当前状态
   */
  public getCurrentState(): SyncReadingState | null {
    if (!this.syncObj) return null;
    try {
      return this.extractState();
    } catch (e) {
      logger.warn(TAG, `getCurrentState failed: ${String(e)}`);
      return null;
    }
  }

  /**
   * 输出会话诊断信息（判断 DataObject 会话是否真正跨设备建立的证据：
   * 对象字段 + 设备状态事件流水）。遥控端/被控端注册与发送指令时调用。
   */
  public diagnoseSession(tag: string): void {
    let stateSummary = '(对象缺失)';
    if (this.syncObj) {
      try {
        const state = this.extractState();
        stateSummary = `sessionId=${state.sessionId}, bookId=${state.bookId}, instructionType=${state.instructionType}, chapter=${state.chapterIndex}, page=${state.pageIndex}, timestamp=${state.timestamp}`;
      } catch (e) {
        stateSummary = `字段提取失败: ${String(e)}`;
      }
    }
    const statusEvents = this.statusEventLog.length > 0 ? this.statusEventLog.join(' | ') : '(从未收到设备状态事件)';
    logger.info(TAG, `[会话诊断|${tag}] 对象=${this.syncObj ? '存在' : '缺失'}, 本端sessionId=${this.sessionId}, lastJoinFailed=${this.lastJoinFailed}, lastStatus=${this.lastStatus}, 状态事件=[${statusEvents}], 对象字段={${stateSummary}}, 独立通道=${this.socketChannel.isConnected() ? '已连接' : '未连接'}`);
  }

  /**
   * 确保独立连接通道（局域网 TCP）的收/发回调已挂载；进程内仅挂载一次。
   */
  private ensureSocketChannelListener(): void {
    if (this.socketChannelListenerAttached) {
      return;
    }
    this.socketChannelListenerAttached = true;
    this.socketChannel.setOnMessage((message: RemoteControlSocketMessage) => {
      this.handleSocketMessage(message);
    });
    this.socketChannel.setOnStatus((connected: boolean, detail: string) => {
      if (connected) {
        this.notifyStatusChange('online', `独立连接通道已建立: ${detail}`);
        // 通道刚建立时立即推送当前状态，让对端尽快拿到最新进度/指令状态
        this.sendOverSocketChannel();
      } else {
        this.notifyStatusChange('offline', `独立连接通道已断开: ${detail}`);
      }
    });
  }

  /**
   * 独立连接通道消息到达：与 DataObject on('change') 同一分发路径，
   * 接收方（阅读器/遥控页）按 timestamp 去重，双通道并存也不会重复执行。
   */
  private handleSocketMessage(message: RemoteControlSocketMessage): void {
    if (message.sessionId !== this.sessionId) {
      logger.warn(TAG, `忽略非当前会话的独立通道消息: msg=${message.sessionId}, current=${this.sessionId}`);
      return;
    }
    const state: SyncReadingState = {
      sessionId: message.sessionId,
      bookId: message.bookId,
      sourceType: message.sourceType,
      chapterIndex: message.chapterIndex,
      pageIndex: message.pageIndex,
      offset: message.offset,
      instructionType: message.instructionType,
      instructionPayload: message.instructionPayload,
      timestamp: message.timestamp
    };
    logger.info(TAG, `独立通道消息到达: type=${state.instructionType}, chapter=${state.chapterIndex}, page=${state.pageIndex}, offset=${state.offset}`);
    this.dataChangedCallbacks.forEach(callback => callback(state));
    if (state.bookId.length > 0) {
      this.resolveRemoteStateWait(state);
    }
  }

  /**
   * 源端：启动独立连接通道服务并返回监听端口（onContinue 打包时同步调用）。
   */
  public prepareSocketServer(sessionId: string): number {
    this.ensureSocketChannelListener();
    return this.socketChannel.prepareServer(sessionId);
  }

  /**
   * 目标端：按源端随 Want 携带的局域网地址回连独立连接通道。
   */
  public connectSocketClient(sessionId: string, ip: string, port: number): void {
    this.ensureSocketChannelListener();
    this.socketChannel.connectToRemote(sessionId, ip, port);
  }

  /**
   * 同步解析本机局域网 IPv4 地址（源端打包 Want 时使用）。
   */
  public resolveLocalLanIp(): string {
    return this.socketChannel.resolveLocalLanIp();
  }

  /**
   * 独立连接通道是否已建立（诊断用）。
   */
  public isSocketChannelConnected(): boolean {
    return this.socketChannel.isConnected();
  }

  /**
   * 将当前对象字段经独立连接通道发出（未连接时静默忽略）。
   */
  private sendOverSocketChannel(): void {
    if (!this.syncObj) {
      return;
    }
    let state: SyncReadingState | null = null;
    try {
      state = this.extractState();
    } catch (e) {
      logger.warn(TAG, `构建独立通道消息失败: ${String(e)}`);
      return;
    }
    const message: RemoteControlSocketMessage = {
      sessionId: state.sessionId,
      bookId: state.bookId,
      sourceType: state.sourceType,
      chapterIndex: state.chapterIndex,
      pageIndex: state.pageIndex,
      offset: state.offset,
      instructionType: state.instructionType,
      instructionPayload: state.instructionPayload,
      timestamp: state.timestamp
    };
    this.socketChannel.send(message);
  }

  /**
   * 等待远端数据同步到达
   * 分两阶段：
   * 1) 等待会话对象建立（目标端 joinSession 延迟执行，阅读器可能更早发起兜底等待 —— 此前直接返回 null 是"接续只成功一半"的根因之一）；
   * 2) 等待远端数据（bookId 非空且属于当前会话），on('change') 提前唤醒，超时返回 null。
   * 用于目标端恢复接续时，避免在分布式数据对象尚未同步完成时读到默认值。
   */
  public waitForRemoteState(timeoutMs: number): Promise<SyncReadingState | null> {
    return new Promise<SyncReadingState | null>((resolve: (state: SyncReadingState | null) => void) => {
      if (!this.syncObj) {
        logger.info(TAG, `waitForRemoteState: 会话对象尚未建立（joinSession 延迟执行），进入等待阶段, timeout=${timeoutMs}ms`);
        this.waitForSessionObject(timeoutMs, resolve);
        return;
      }
      this.startRemoteDataWait(timeoutMs, resolve);
    });
  }

  /**
   * 轮询等待分布式会话对象建立（目标端 joinSession 延迟执行，最长等待 timeoutMs）
   */
  private waitForSessionObject(timeoutMs: number, resolve: (state: SyncReadingState | null) => void): void {
    const waitStartedAt = Date.now();
    const poll = (): void => {
      const elapsedMs = Date.now() - waitStartedAt;
      if (this.syncObj) {
        logger.info(TAG, `waitForRemoteState: 会话对象已建立（等待 ${elapsedMs}ms），开始等待远端数据`);
        this.startRemoteDataWait(Math.max(500, timeoutMs - elapsedMs), resolve);
        return;
      }
      if (elapsedMs >= timeoutMs) {
        logger.warn(TAG, `waitForRemoteState: 等待会话对象超时（${elapsedMs}ms），joinSession 未执行或失败，返回 null`);
        resolve(null);
        return;
      }
      setTimeout(() => {
        poll();
      }, 200);
    };
    poll();
  }

  private startRemoteDataWait(timeoutMs: number, resolve: (state: SyncReadingState | null) => void): void {
    let currentState: SyncReadingState | null = null;
    try {
      currentState = this.extractState();
    } catch (e) {
      logger.warn(TAG, `waitForRemoteState extract failed: ${String(e)}`);
      resolve(null);
      return;
    }
    if (currentState && currentState.bookId.length > 0 && currentState.sessionId === this.sessionId) {
      logger.info(TAG, `waitForRemoteState: 会话已有远端状态，直接返回: bookId=${currentState.bookId}, chapter=${currentState.chapterIndex}, page=${currentState.pageIndex}`);
      resolve(currentState);
      return;
    }
    // 尚未收到远端数据，注册等待回调（on('change') 数据到达时提前唤醒）
    logger.info(TAG, `waitForRemoteState: 开始等待远端数据同步, timeout=${timeoutMs}ms, currentBookId=${currentState ? currentState.bookId : '(empty)'}`);
    this.remoteStateWaitResolve = resolve;
    this.remoteStateWaitTimer = setTimeout(() => {
      logger.info(TAG, 'waitForRemoteState timed out, remote state not received');
      this.resolveRemoteStateWait(null);
    }, timeoutMs);
  }

  private resolveRemoteStateWait(state: SyncReadingState | null): void {
    if (this.remoteStateWaitTimer >= 0) {
      clearTimeout(this.remoteStateWaitTimer);
      this.remoteStateWaitTimer = -1;
    }
    if (this.remoteStateWaitResolve) {
      const resolve = this.remoteStateWaitResolve;
      this.remoteStateWaitResolve = null;
      // [日志完善] 等待结果（数据到达/超时/会话失败）是排查接续恢复失败的关键证据
      if (state) {
        logger.info(TAG, `waitForRemoteState 收到远端数据: bookId=${state.bookId}, chapter=${state.chapterIndex}, page=${state.pageIndex}, offset=${state.offset}, sourceType=${state.sourceType}`);
      } else {
        logger.warn(TAG, 'waitForRemoteState 结束（超时/会话失败/被取消），未收到远端数据');
      }
      resolve(state);
    }
  }

  private extractState(): SyncReadingState {
    if (!this.syncObj) {
      throw new Error("syncObj is null");
    }
    return {
      sessionId: this.syncObj['sessionId'] as string,
      bookId: this.syncObj['bookId'] as string,
      sourceType: this.syncObj['sourceType'] as string,
      chapterIndex: this.syncObj['chapterIndex'] as number,
      pageIndex: this.syncObj['pageIndex'] as number,
      offset: this.syncObj['offset'] as number,
      instructionType: this.syncObj['instructionType'] as string,
      instructionPayload: this.syncObj['instructionPayload'] as string,
      timestamp: this.syncObj['timestamp'] as number
    };
  }

  /**
   * 释放当前分布式数据对象并离开会话（保留功能回调集合）
   */
  private releaseSyncObject(): void {
    // 通知等待方立即结束，避免悬挂
    this.resolveRemoteStateWait(null);
    // 会话已释放：清空最近状态，避免把已离开会话的 online 回放给后续新页面
    this.lastStatus = 'none';
    this.lastStatusMessage = '';
    if (this.syncObj) {
      try {
        const objToLeave = this.syncObj;
        this.syncObj = null;
        this.sessionId = '';
        objToLeave.setSessionId(() => {
          logger.info(TAG, 'Successfully left distributed data session');
        });
      } catch (e) {
        logger.error(TAG, `Error leaving session: ${String(e)}`);
      }
    }
  }

  /**
   * 离开会话并清理资源（应用销毁等终态场景）
   */
  public leaveSession(): void {
    this.releaseSyncObject();
    this.dataChangedCallbacks.clear();
    this.statusChangedCallbacks.clear();
    // 独立连接通道一并释放
    this.socketChannel.teardown();
  }
}

export const distributedDataSyncManager = DistributedDataSyncManager.getInstance();
