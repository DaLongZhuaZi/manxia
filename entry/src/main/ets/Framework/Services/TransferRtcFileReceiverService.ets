/**
 * Native RTC DataChannel 文件接收服务。
 *
 * 当前 NAPI 只暴露文本 DataChannel，所以文件片段先按 JSON + Base64 文本承载。
 * 协议层保持 mx-transfer-file/0.1，后续 native 模块补二进制发送/接收后可复用同一状态机。
 */

import { util } from '@kit.ArkTS';
import { logger } from '../../Utils/Logger';
import { getTransferConfigManager, TransferConfigManager } from '../Managers/TransferConfigManager';
import {
  getTransferUploadStoreService,
  TransferStagedUploadSession,
  TransferUploadStoreService
} from './TransferUploadStoreService';
import {
  TransferDataChannelFileMessage,
  TransferRtcFileReceiverRuntime,
  TransferRtcFileReceiverStatus,
  TransferUploadRecord,
  buildTransferDataChannelAckMessage,
  buildTransferDataChannelErrorMessage,
  cloneTransferRtcFileReceiverRuntime,
  createEmptyTransferRtcFileReceiverRuntime,
  parseTransferDataChannelFileMessage
} from '../../Models/TransferModels';

const TAG = 'TransferRtcFileReceiver';

interface TransferRtcActiveReceiveSession {
  transferId: string;
  uploadSession: TransferStagedUploadSession;
  chunkSize: number;
  chunkCount: number;
  nextChunkIndex: number;
}

export interface TransferRtcFileReceiverResult {
  handled: boolean;
  ackText: string;
  shouldRefreshUploads: boolean;
  runtime: TransferRtcFileReceiverRuntime;
}

export class TransferRtcFileReceiverService {
  private static instance: TransferRtcFileReceiverService | null = null;

  private readonly uploadStoreService: TransferUploadStoreService = getTransferUploadStoreService();
  private readonly configManager: TransferConfigManager = getTransferConfigManager();
  private readonly base64Helper: util.Base64Helper = new util.Base64Helper();
  private runtime: TransferRtcFileReceiverRuntime = createEmptyTransferRtcFileReceiverRuntime();
  private activeSession: TransferRtcActiveReceiveSession | null = null;

  private constructor() {}

  public static getInstance(): TransferRtcFileReceiverService {
    const existingInstance = TransferRtcFileReceiverService.instance;
    if (existingInstance !== null) {
      return existingInstance;
    }
    const createdInstance = new TransferRtcFileReceiverService();
    TransferRtcFileReceiverService.instance = createdInstance;
    return createdInstance;
  }

  public getRuntimeState(): TransferRtcFileReceiverRuntime {
    return cloneTransferRtcFileReceiverRuntime(this.runtime);
  }

  public async handleDataChannelText(text: string): Promise<TransferRtcFileReceiverResult> {
    const parsed = parseTransferDataChannelFileMessage(text);
    if (parsed === null) {
      return this.buildResult(false, '', false);
    }

    try {
      if (parsed.type === 'file_start') {
        return await this.handleFileStart(parsed);
      }
      if (parsed.type === 'file_chunk') {
        return await this.handleFileChunk(parsed);
      }
      if (parsed.type === 'file_end') {
        return await this.handleFileEnd(parsed);
      }
      if (parsed.type === 'error') {
        await this.handleRemoteError(parsed);
        return this.buildResult(true, '', false);
      }
      return this.buildResult(true, '', false);
    } catch (error) {
      const message = this.stringifyError(error);
      logger.warn(TAG, `处理 DataChannel 文件消息失败: ${message}`);
      await this.failActiveReceive(parsed.transferId, message, parsed.chunkIndex);
      const ackText = buildTransferDataChannelErrorMessage(parsed.transferId, message, parsed.chunkIndex);
      return this.buildResult(true, ackText, false);
    }
  }

  public async abortActiveReceive(message: string): Promise<void> {
    const activeSession = this.activeSession;
    if (activeSession !== null) {
      await this.uploadStoreService.abortUpload(activeSession.uploadSession);
      this.activeSession = null;
    }
    this.runtime = this.buildRuntime(
      'failed',
      '',
      '',
      0,
      0,
      0,
      0,
      '',
      message,
      message
    );
  }

  private async handleFileStart(message: TransferDataChannelFileMessage): Promise<TransferRtcFileReceiverResult> {
    this.validateFileStartMessage(message);

    const activeSession = this.activeSession;
    if (activeSession !== null) {
      await this.uploadStoreService.abortUpload(activeSession.uploadSession);
      logger.warn(TAG, `收到新的文件传输，已清理未完成接收: ${activeSession.transferId}`);
      this.activeSession = null;
    }

    const clientName = message.clientName.length > 0 ? message.clientName : 'RTC 浏览器';
    const contentType = message.contentType.length > 0 ? message.contentType : 'application/octet-stream';
    const config = this.configManager.getConfig();
    const maxTotalSizeBytes = config.maxTotalSizeMb * 1024 * 1024;
    const uploadSession = await this.uploadStoreService.beginUpload(
      message.fileName,
      contentType,
      clientName,
      'rtc-datachannel',
      message.size,
      maxTotalSizeBytes
    );
    const receiveSession: TransferRtcActiveReceiveSession = {
      transferId: message.transferId,
      uploadSession: uploadSession,
      chunkSize: message.chunkSize,
      chunkCount: message.chunkCount,
      nextChunkIndex: 0
    };
    this.activeSession = receiveSession;
    this.runtime = this.buildRuntime(
      'receiving',
      message.transferId,
      uploadSession.normalizedFileName,
      0,
      message.size,
      0,
      message.chunkCount,
      '',
      `开始接收 ${uploadSession.normalizedFileName}`,
      ''
    );

    const ackText = buildTransferDataChannelAckMessage(message.transferId, 'ready', 0, 0, '', 'ready');
    return this.buildResult(true, ackText, false);
  }

  private async handleFileChunk(message: TransferDataChannelFileMessage): Promise<TransferRtcFileReceiverResult> {
    const activeSession = this.requireActiveSession(message.transferId);
    if (message.chunkIndex !== activeSession.nextChunkIndex) {
      throw new Error(`分片顺序错误: expected=${activeSession.nextChunkIndex}, actual=${message.chunkIndex}`);
    }
    if (message.byteLength <= 0 || message.data.length <= 0) {
      throw new Error('分片数据为空');
    }
    if (message.offset !== activeSession.uploadSession.receivedBytes) {
      throw new Error(`分片偏移错误: expected=${activeSession.uploadSession.receivedBytes}, actual=${message.offset}`);
    }

    const chunkBytes = this.decodeBase64Chunk(message.data);
    if (chunkBytes.byteLength !== message.byteLength) {
      throw new Error(`分片大小不匹配: expected=${message.byteLength}, actual=${chunkBytes.byteLength}`);
    }

    await this.uploadStoreService.appendUploadChunk(activeSession.uploadSession, chunkBytes);
    activeSession.nextChunkIndex += 1;
    const receivedBytes = activeSession.uploadSession.receivedBytes;
    this.runtime = this.buildRuntime(
      'receiving',
      activeSession.transferId,
      activeSession.uploadSession.normalizedFileName,
      receivedBytes,
      activeSession.uploadSession.expectedBytes,
      activeSession.nextChunkIndex,
      activeSession.chunkCount,
      '',
      `正在接收 ${activeSession.uploadSession.normalizedFileName}`,
      ''
    );

    const ackText = buildTransferDataChannelAckMessage(
      activeSession.transferId,
      'chunk',
      receivedBytes,
      activeSession.nextChunkIndex,
      '',
      'chunk_written'
    );
    return this.buildResult(true, ackText, false);
  }

  private async handleFileEnd(message: TransferDataChannelFileMessage): Promise<TransferRtcFileReceiverResult> {
    const activeSession = this.requireActiveSession(message.transferId);
    if (activeSession.nextChunkIndex !== activeSession.chunkCount) {
      throw new Error(`文件尚未接收完整: expectedChunks=${activeSession.chunkCount}, actual=${activeSession.nextChunkIndex}`);
    }
    if (activeSession.uploadSession.receivedBytes !== activeSession.uploadSession.expectedBytes) {
      throw new Error(
        `文件大小不匹配: expected=${activeSession.uploadSession.expectedBytes}, actual=${activeSession.uploadSession.receivedBytes}`
      );
    }

    const record: TransferUploadRecord = await this.uploadStoreService.finalizeUpload(activeSession.uploadSession);
    this.activeSession = null;
    this.runtime = this.buildRuntime(
      'completed',
      activeSession.transferId,
      record.fileName,
      record.fileSizeBytes,
      record.fileSizeBytes,
      activeSession.nextChunkIndex,
      activeSession.chunkCount,
      record.id,
      `DataChannel 文件已保存到收件箱: ${record.fileName}`,
      ''
    );

    const ackText = buildTransferDataChannelAckMessage(
      activeSession.transferId,
      'complete',
      record.fileSizeBytes,
      activeSession.nextChunkIndex,
      record.id,
      'complete'
    );
    return this.buildResult(true, ackText, true);
  }

  private async handleRemoteError(message: TransferDataChannelFileMessage): Promise<void> {
    const activeSession = this.activeSession;
    if (activeSession !== null && activeSession.transferId === message.transferId) {
      await this.uploadStoreService.abortUpload(activeSession.uploadSession);
      this.activeSession = null;
    }
    const errorMessage = message.message.length > 0 ? message.message : '浏览器端终止了 DataChannel 文件传输';
    this.runtime = this.buildRuntime(
      'failed',
      message.transferId,
      activeSession !== null ? activeSession.uploadSession.normalizedFileName : '',
      activeSession !== null ? activeSession.uploadSession.receivedBytes : 0,
      activeSession !== null ? activeSession.uploadSession.expectedBytes : 0,
      activeSession !== null ? activeSession.nextChunkIndex : 0,
      activeSession !== null ? activeSession.chunkCount : 0,
      '',
      errorMessage,
      errorMessage
    );
  }

  private validateFileStartMessage(message: TransferDataChannelFileMessage): void {
    if (message.transferId.length <= 0) {
      throw new Error('缺少 transferId');
    }
    if (message.fileName.length <= 0) {
      throw new Error('缺少文件名');
    }
    if (message.size <= 0) {
      throw new Error('文件大小无效');
    }
    if (message.chunkSize <= 0 || message.chunkCount <= 0) {
      throw new Error('分片参数无效');
    }
    const expectedChunkCount = Math.ceil(message.size / message.chunkSize);
    if (expectedChunkCount !== message.chunkCount) {
      throw new Error(`分片数量不匹配: expected=${expectedChunkCount}, actual=${message.chunkCount}`);
    }
    const config = this.configManager.getConfig();
    const maxFileSizeBytes = config.maxFileSizeMb * 1024 * 1024;
    if (message.size > maxFileSizeBytes) {
      throw new Error(`文件超出上限，当前最多支持 ${config.maxFileSizeMb} MB`);
    }
  }

  private requireActiveSession(transferId: string): TransferRtcActiveReceiveSession {
    const activeSession = this.activeSession;
    if (activeSession === null) {
      throw new Error('当前没有正在接收的 DataChannel 文件');
    }
    if (activeSession.transferId !== transferId) {
      throw new Error(`transferId 不匹配: expected=${activeSession.transferId}, actual=${transferId}`);
    }
    return activeSession;
  }

  private decodeBase64Chunk(data: string): Uint8Array {
    try {
      return this.base64Helper.decodeSync(data);
    } catch (error) {
      throw new Error(`Base64 分片解码失败: ${this.stringifyError(error)}`);
    }
  }

  private async failActiveReceive(transferId: string, message: string, chunkIndex: number): Promise<void> {
    const activeSession = this.activeSession;
    if (activeSession !== null && (transferId.length <= 0 || activeSession.transferId === transferId)) {
      await this.uploadStoreService.abortUpload(activeSession.uploadSession);
      this.runtime = this.buildRuntime(
        'failed',
        activeSession.transferId,
        activeSession.uploadSession.normalizedFileName,
        activeSession.uploadSession.receivedBytes,
        activeSession.uploadSession.expectedBytes,
        chunkIndex,
        activeSession.chunkCount,
        '',
        message,
        message
      );
      this.activeSession = null;
      return;
    }
    this.runtime = this.buildRuntime('failed', transferId, '', 0, 0, chunkIndex, 0, '', message, message);
  }

  private buildResult(
    handled: boolean,
    ackText: string,
    shouldRefreshUploads: boolean
  ): TransferRtcFileReceiverResult {
    const result: TransferRtcFileReceiverResult = {
      handled: handled,
      ackText: ackText,
      shouldRefreshUploads: shouldRefreshUploads,
      runtime: this.getRuntimeState()
    };
    return result;
  }

  private buildRuntime(
    status: TransferRtcFileReceiverStatus,
    transferId: string,
    fileName: string,
    receivedBytes: number,
    expectedBytes: number,
    nextChunkIndex: number,
    chunkCount: number,
    recordId: string,
    lastMessage: string,
    lastError: string
  ): TransferRtcFileReceiverRuntime {
    const runtime: TransferRtcFileReceiverRuntime = {
      status: status,
      transferId: transferId,
      fileName: fileName,
      receivedBytes: receivedBytes,
      expectedBytes: expectedBytes,
      nextChunkIndex: nextChunkIndex,
      chunkCount: chunkCount,
      recordId: recordId,
      lastMessage: lastMessage,
      lastError: lastError,
      updatedAt: Date.now()
    };
    return runtime;
  }

  private stringifyError(error: Object): string {
    if (error instanceof Error) {
      return error.message;
    }
    try {
      return JSON.stringify(error);
    } catch (_jsonError) {
      return String(error);
    }
  }
}

export function getTransferRtcFileReceiverService(): TransferRtcFileReceiverService {
  return TransferRtcFileReceiverService.getInstance();
}
