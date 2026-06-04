import distributedDataObject from '@ohos.data.distributedDataObject';
import common from '@ohos.app.ability.common';
import { logger } from '../../Utils/Logger';

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
  
  private onDataChangedCallback: ((state: SyncReadingState) => void) | null = null;

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
      return;
    }

    this.sessionId = sessionId;

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
        logger.info(TAG, `Data changed in session ${sessionId}, fields: ${fields.join(',')}`);
        if (this.onDataChangedCallback && this.syncObj) {
          const currentState = this.extractState();
          this.onDataChangedCallback(currentState);
        }
      });

      this.syncObj.on('status', (sessionId: string, networkId: string, status: 'online' | 'offline' | 'restored') => {
        logger.info(TAG, `Session ${sessionId} device ${networkId} is ${status}`);
      });

      this.syncObj.setSessionId(sessionId).then(() => {
        logger.info(TAG, `Successfully joined distributed data session: ${sessionId}`);
      }).catch((err: Error) => {
        logger.error(TAG, `Failed to set distributed data session: ${String(err)}`);
      });
    } catch (e) {
      logger.error(TAG, `Failed to join distributed data session: ${String(e)}`);
    }
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
    if (!this.syncObj) return;

    try {
      this.syncObj['sessionId'] = this.sessionId;
      this.syncObj['instructionType'] = type;
      this.syncObj['instructionPayload'] = payload;
      this.syncObj['timestamp'] = Date.now();
      
      this.syncObj.save('local');
      logger.info(TAG, `Sent instruction: ${type}`);
    } catch (e) {
      logger.error(TAG, `Error sending instruction: ${String(e)}`);
    }
  }

  /**
   * 设置数据变更监听
   */
  public setOnDataChangedCallback(callback: (state: SyncReadingState) => void): void {
    this.onDataChangedCallback = callback;
  }

  /**
   * 提取当前状态
   */
  public getCurrentState(): SyncReadingState | null {
    if (!this.syncObj) return null;
    return this.extractState();
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
   * 离开会话并清理资源
   */
  public leaveSession(): void {
    if (this.syncObj) {
      try {
        this.syncObj.setSessionId(() => {
          logger.info(TAG, 'Successfully left distributed data session');
        });
        this.syncObj = null;
        this.sessionId = '';
        this.onDataChangedCallback = null;
      } catch (e) {
        logger.error(TAG, `Error leaving session: ${String(e)}`);
      }
    }
  }
}

export const distributedDataSyncManager = DistributedDataSyncManager.getInstance();
