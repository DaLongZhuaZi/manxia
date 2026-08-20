import { SafeUtils } from 'manxia_core/src/main/ets/Utils/SafeUtils';
/**
 * 局域网传书上传收件箱服务
 *
 * 负责：
 * 1. 将浏览器上传文件保存到应用沙箱
 * 2. 维护最近上传记录
 * 3. 将记录转交给 DataManagementPage 继续导入
 */

import { fileIo, fileUri, statfs } from '@kit.CoreFileKit';
import type { WriteOptions } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { getContext } from 'manxia_theme/src/main/ets/GlobalContext';
import {
  TransferUploadRecord,
  cloneTransferUploadRecord,
  cloneTransferUploadRecords,
  isTransferAcceptedImportCategory
} from '../../Models/TransferModels';
import {
  getNetworkFolderFileExtension,
  inferNetworkFolderImportCategory,
  NetworkFolderImportCategory
} from '../../Models/NetworkFolderModels';
import {
  ExternalFileTaskFactory,
  ExternalFileTaskKind,
  ExternalFileTaskParams,
  ExternalFileTaskSource
} from 'manxia_network/src/main/ets/Framework/ExternalFile/ExternalFileTaskTypes';
import { ImportFlowMonitor, getImportFlowMonitor } from '../Import/ImportFlowMonitor';
import {
  ImportFlowContentType,
  ImportFlowEntrySource,
  ImportFlowEvent,
  ImportFlowEventType,
  ImportFlowSessionInfo
} from '../Import/ImportFlowTypes';

const TAG = 'TransferUploadStore';
const INDEX_VERSION = 1;
const MAX_RECORD_COUNT = 40;
const STALE_PART_FILE_MAX_AGE_MS = 12 * 60 * 60 * 1000;
const UPLOAD_WRITE_BUFFER_FLUSH_BYTES = 8 * 1024 * 1024;
const UPLOAD_FREE_SPACE_RESERVE_BYTES = 512 * 1024 * 1024;
const APP_STORAGE_TRANSFER_RECORD_ID = 'pendingTransferRecordId';
const APP_STORAGE_TRANSFER_RESULT = 'pendingTransferImportResult';
const APP_STORAGE_TRANSFER_TRACKING_ACTIVE = 'pendingTransferTrackingActive';
const APP_STORAGE_PENDING_IMPORT_FLOW_ID = 'pendingImportFlowId';

interface TransferUploadIndexData {
  version: number;
  records: TransferUploadRecord[];
}

export interface TransferStagedUploadSession {
  uploadId: string;
  normalizedFileName: string;
  contentType: string;
  clientName: string;
  clientIp: string;
  importCategory: NetworkFolderImportCategory;
  tempFilePath: string;
  expectedBytes: number;
  receivedBytes: number;
  flushedBytes: number;
  pendingWriteChunks: Uint8Array[];
  pendingWriteBytes: number;
  reservedBytes: number;
  fileDescriptor: number;
  createdAt: number;
}

export interface TransferUploadStorageBudget {
  inboxBytes: number;
  reservedBytes: number;
  freeBytes: number;
  reserveBytes: number;
}

export interface TransferExternalFileTaskPrepareResult {
  record: TransferUploadRecord;
  taskParams: ExternalFileTaskParams;
}

export class TransferUploadStoreService {
  private static instance: TransferUploadStoreService;

  private initialized: boolean = false;
  private initializePromise: Promise<void> | null = null;
  private baseDir: string = '';
  private filesDir: string = '';
  private indexFilePath: string = '';
  private records: TransferUploadRecord[] = [];
  private reservedUploadBytes: number = 0;
  private storageBudgetLock: Promise<void> = Promise.resolve<void>(undefined);
  private readonly importFlowMonitor: ImportFlowMonitor = getImportFlowMonitor();
  private readonly encoder: util.TextEncoder = new util.TextEncoder();
  private readonly decoder: util.TextDecoder = new util.TextDecoder('utf-8');

  private constructor() {}

  public static getInstance(): TransferUploadStoreService {
    if (!TransferUploadStoreService.instance) {
      TransferUploadStoreService.instance = new TransferUploadStoreService();
    }
    return TransferUploadStoreService.instance;
  }

  public async initialize(): Promise<void> {
    if (this.initialized) {
      return;
    }
    if (this.initializePromise !== null) {
      await this.initializePromise;
      return;
    }

    const initializeTask = this.initializeInternal();
    this.initializePromise = initializeTask;
    try {
      await initializeTask;
    } finally {
      if (this.initializePromise === initializeTask) {
        this.initializePromise = null;
      }
    }
  }

  private async initializeInternal(): Promise<void> {
    if (this.initialized) {
      return;
    }

    const context = getContext();
    this.baseDir = `${context.filesDir}/transfer_uploads`;
    this.filesDir = `${this.baseDir}/files`;
    this.indexFilePath = `${this.baseDir}/index.json`;

    await this.ensureDirectoryExists(this.baseDir);
    await this.ensureDirectoryExists(this.filesDir);
    await this.loadIndex();
    await this.cleanupFilesDirectory();

    this.initialized = true;
    logger.info(TAG, `局域网传书上传收件箱初始化完成: ${this.baseDir}`);
  }

  public getCachedRecords(limit: number = 8): TransferUploadRecord[] {
    const boundedLimit = limit > 0 ? limit : 8;
    const selected: TransferUploadRecord[] = [];
    for (let index = 0; index < this.records.length && index < boundedLimit; index++) {
      selected.push(this.records[index]);
    }
    return cloneTransferUploadRecords(selected);
  }

  public async getRecentUploads(limit: number = 20): Promise<TransferUploadRecord[]> {
    await this.initialize();
    return this.getCachedRecords(limit);
  }

  public async beginUpload(
    originalFileName: string,
    contentType: string,
    clientName: string,
    clientIp: string,
    expectedBytes: number,
    maxTotalBytes: number = 0
  ): Promise<TransferStagedUploadSession> {
    await this.initialize();

    const normalizedFileName = this.normalizeUploadFileName(originalFileName);
    const importCategory = inferNetworkFolderImportCategory(normalizedFileName);
    if (!isTransferAcceptedImportCategory(importCategory)) {
      throw new Error(`暂不支持当前文件类型: ${normalizedFileName}`);
    }
    await this.reserveUploadBudget(expectedBytes, maxTotalBytes);

    try {
      const uploadId = this.buildRecordId();
      const tempFilePath = `${this.filesDir}/${Date.now()}_${uploadId}.part`;
      const file = await fileIo.open(
        tempFilePath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC
      );

      const session: TransferStagedUploadSession = {
        uploadId: uploadId,
        normalizedFileName: normalizedFileName,
        contentType: contentType.trim(),
        clientName: clientName.trim(),
        clientIp: clientIp.trim(),
        importCategory: importCategory,
        tempFilePath: tempFilePath,
        expectedBytes: expectedBytes,
        receivedBytes: 0,
        flushedBytes: 0,
        pendingWriteChunks: [],
        pendingWriteBytes: 0,
        reservedBytes: expectedBytes,
        fileDescriptor: file.fd,
        createdAt: Date.now()
      };
      return session;
    } catch (error) {
      this.releaseUploadBytes(expectedBytes);
      throw new Error(this.stringifyError(error));
    }
  }

  public async getStorageBudget(): Promise<TransferUploadStorageBudget> {
    await this.initialize();
    const budget: TransferUploadStorageBudget = {
      inboxBytes: this.calculateInboxBytes(),
      reservedBytes: this.reservedUploadBytes,
      freeBytes: await this.getFreeStorageBytes(),
      reserveBytes: UPLOAD_FREE_SPACE_RESERVE_BYTES
    };
    return budget;
  }

  public getCachedInboxBytes(): number {
    return this.calculateInboxBytes();
  }

  public getCachedReservedBytes(): number {
    return this.reservedUploadBytes;
  }

  public async ensureUploadCapacity(expectedBytes: number, maxTotalBytes: number = 0): Promise<void> {
    await this.initialize();
    await this.ensureStorageBudget(expectedBytes, maxTotalBytes);
  }

  public async appendUploadChunk(session: TransferStagedUploadSession, chunk: Uint8Array): Promise<void> {
    if (chunk.byteLength <= 0) {
      return;
    }
    session.pendingWriteChunks.push(chunk);
    session.pendingWriteBytes += chunk.byteLength;
    session.receivedBytes += chunk.byteLength;
    if (session.pendingWriteBytes >= UPLOAD_WRITE_BUFFER_FLUSH_BYTES) {
      await this.flushPendingUploadChunks(session);
    }
  }

  public async finalizeUpload(session: TransferStagedUploadSession): Promise<TransferUploadRecord> {
    try {
      try {
        await this.flushPendingUploadChunks(session);
        this.assertUploadSizeMatches(session);
        await fileIo.close(session.fileDescriptor);
      } catch (error) {
        await this.tryCloseUploadFile(session);
        await this.tryDeleteFile(session.tempFilePath);
        throw new Error(this.stringifyError(error));
      }

      const storedFileName = `${Date.now()}_${session.uploadId}_${session.normalizedFileName}`;
      const localPath = `${this.filesDir}/${storedFileName}`;
      try {
        await fileIo.rename(session.tempFilePath, localPath);
      } catch (error) {
        await this.tryDeleteFile(session.tempFilePath);
        throw new Error(this.stringifyError(error));
      }

      const record: TransferUploadRecord = {
        id: session.uploadId,
        fileName: session.normalizedFileName,
        localPath: localPath,
        localUri: fileUri.getUriFromPath(localPath),
        fileSizeBytes: session.receivedBytes,
        contentType: session.contentType,
        importCategory: session.importCategory,
        clientName: session.clientName,
        clientIp: session.clientIp,
        source: 'lan_transfer',
        receivedAt: session.createdAt,
        status: 'received'
      };

      this.records.unshift(record);
      const removedRecords = this.trimRecords();
      await this.saveIndex();
      await this.deleteRecordFiles(removedRecords);

      logger.info(
        TAG,
        `已完成局域网传书文件落盘: ${record.fileName}, 分类=${record.importCategory}, 大小=${record.fileSizeBytes} 字节`
      );
      return cloneTransferUploadRecord(record);
    } finally {
      this.releaseUploadBytes(session.reservedBytes);
      session.reservedBytes = 0;
    }
  }

  public async abortUpload(session: TransferStagedUploadSession): Promise<void> {
    session.pendingWriteChunks = [];
    session.pendingWriteBytes = 0;
    this.releaseUploadBytes(session.reservedBytes);
    session.reservedBytes = 0;
    try {
      await fileIo.close(session.fileDescriptor);
    } catch (_error) {
    }
    await this.tryDeleteFile(session.tempFilePath);
  }

  public async saveUpload(
    originalFileName: string,
    contentType: string,
    clientName: string,
    clientIp: string,
    body: ArrayBuffer,
    maxTotalBytes: number = 0
  ): Promise<TransferUploadRecord> {
    const session = await this.beginUpload(
      originalFileName,
      contentType,
      clientName,
      clientIp,
      body.byteLength,
      maxTotalBytes
    );
    try {
      await this.appendUploadChunk(session, new Uint8Array(body));
      return await this.finalizeUpload(session);
    } catch (error) {
      await this.abortUpload(session);
      throw new Error(this.stringifyError(error));
    }
  }

  public async prepareRecordForDataManagement(recordId: string): Promise<TransferUploadRecord | null> {
    await this.initialize();

    const record = this.findRecordById(recordId);
    if (record === null) {
      return null;
    }
    if (!isTransferAcceptedImportCategory(record.importCategory)) {
      return null;
    }

    this.clearPendingImportMarkers();
    this.preparePendingImportMarkers(record);
    if (this.shouldTrackImportResult(record.importCategory)) {
      AppStorage.setOrCreate(APP_STORAGE_TRANSFER_RECORD_ID, record.id);
      AppStorage.setOrCreate(APP_STORAGE_TRANSFER_RESULT, '');
      AppStorage.setOrCreate(APP_STORAGE_TRANSFER_TRACKING_ACTIVE, true);
    } else {
      this.clearTransferImportTrackingMarkers();
    }

    record.status = 'handoff_sent';
    await this.saveIndex();
    logger.info(TAG, `已将上传文件转交给应用导入流程: ${record.fileName}, 分类=${record.importCategory}`);
    return cloneTransferUploadRecord(record);
  }

  public async prepareRecordForExternalFileTask(recordId: string): Promise<TransferExternalFileTaskPrepareResult | null> {
    await this.initialize();

    const record = this.findRecordById(recordId);
    if (record === null) {
      return null;
    }
    if (!isTransferAcceptedImportCategory(record.importCategory)) {
      return null;
    }

    this.clearPendingImportMarkers();
    if (this.shouldTrackImportResult(record.importCategory)) {
      AppStorage.setOrCreate(APP_STORAGE_TRANSFER_RECORD_ID, record.id);
      AppStorage.setOrCreate(APP_STORAGE_TRANSFER_RESULT, '');
      AppStorage.setOrCreate(APP_STORAGE_TRANSFER_TRACKING_ACTIVE, true);
    } else {
      this.clearTransferImportTrackingMarkers();
    }

    record.status = 'handoff_sent';
    await this.saveIndex();
    const result: TransferExternalFileTaskPrepareResult = {
      record: cloneTransferUploadRecord(record),
      taskParams: this.createExternalFileTaskParams(record)
    };
    logger.info(TAG, `已准备局域网传书独立导入任务: ${record.fileName}, 分类=${record.importCategory}`);
    return result;
  }

  public async prepareRecordFallbackImport(recordId: string): Promise<TransferUploadRecord | null> {
    await this.initialize();

    const record = this.findRecordById(recordId);
    if (record === null) {
      return null;
    }
    if (!isTransferAcceptedImportCategory(record.importCategory)) {
      return null;
    }

    this.clearPendingImportMarkers();
    this.preparePendingImportMarkers(record);
    return cloneTransferUploadRecord(record);
  }

  public async consumePendingImportResult(): Promise<TransferUploadRecord | null> {
    await this.initialize();

    const recordId = AppStorage.get<string>(APP_STORAGE_TRANSFER_RECORD_ID);
    const result = AppStorage.get<string>(APP_STORAGE_TRANSFER_RESULT);
    const trackingActive = AppStorage.get<boolean>(APP_STORAGE_TRANSFER_TRACKING_ACTIVE);

    if (!recordId || recordId.trim().length <= 0) {
      this.clearTransferImportTrackingMarkers();
      return null;
    }
    if (trackingActive) {
      return null;
    }
    if (!result || result.trim().length <= 0) {
      return null;
    }

    let mappedStatus: 'imported' | 'import_failed' | 'import_cancelled';
    if (result === 'imported') {
      mappedStatus = 'imported';
    } else if (result === 'import_cancelled') {
      mappedStatus = 'import_cancelled';
    } else {
      mappedStatus = 'import_failed';
    }

    const updatedRecord = await this.updateRecordStatus(recordId, mappedStatus);
    this.clearTransferImportTrackingMarkers();
    return updatedRecord;
  }

  public isRecordTrackingActive(recordId: string): boolean {
    const pendingRecordId = AppStorage.get<string>(APP_STORAGE_TRANSFER_RECORD_ID);
    const trackingActive = AppStorage.get<boolean>(APP_STORAGE_TRANSFER_TRACKING_ACTIVE);
    if (!trackingActive) {
      return false;
    }
    if (!pendingRecordId || pendingRecordId.trim().length <= 0) {
      return false;
    }
    return pendingRecordId === recordId;
  }

  public async deleteRecord(recordId: string): Promise<boolean> {
    const deletedCount = await this.deleteRecords([recordId]);
    return deletedCount > 0;
  }

  public async deleteRecords(recordIds: string[]): Promise<number> {
    await this.initialize();

    const normalizedRecordIds: string[] = [];
    for (const recordId of recordIds) {
      const normalizedRecordId = recordId.trim();
      if (normalizedRecordId.length <= 0) {
        continue;
      }
      if (!this.containsRecordId(normalizedRecordIds, normalizedRecordId)) {
        normalizedRecordIds.push(normalizedRecordId);
      }
    }

    if (normalizedRecordIds.length <= 0) {
      return 0;
    }

    for (const recordId of normalizedRecordIds) {
      if (this.isRecordTrackingActive(recordId)) {
        throw new Error('当前记录正在导入流程中，暂时不能删除');
      }
    }

    const deletedRecords: TransferUploadRecord[] = [];
    const remainingRecords: TransferUploadRecord[] = [];
    for (const record of this.records) {
      if (this.containsRecordId(normalizedRecordIds, record.id)) {
        deletedRecords.push(record);
      } else {
        remainingRecords.push(record);
      }
    }

    if (deletedRecords.length <= 0) {
      return 0;
    }

    this.records = remainingRecords;
    await this.saveIndex();
    await this.deleteRecordFiles(deletedRecords);

    const pendingRecordId = AppStorage.get<string>(APP_STORAGE_TRANSFER_RECORD_ID);
    if (pendingRecordId && this.containsRecordId(normalizedRecordIds, pendingRecordId)) {
      this.clearPendingImportMarkers();
      this.clearTransferImportTrackingMarkers();
    }

    logger.info(TAG, `已删除传书收件箱记录及文件: ${deletedRecords.length} 条`);
    return deletedRecords.length;
  }

  public getImportCategoryLabel(category: NetworkFolderImportCategory): string {
    if (category === 'comic') {
      return '漫画';
    }
    if (category === 'ebook') {
      return '电子书';
    }
    if (category === 'pdf') {
      return 'PDF';
    }
    if (category === 'backup') {
      return '备份';
    }
    if (category === 'json') {
      return 'JSON';
    }
    if (category === 'font') {
      return '字体';
    }
    if (category === 'code') {
      return '代码';
    }
    if (category === 'avif') {
      return 'AVIF';
    }
    return '其他';
  }

  private async loadIndex(): Promise<void> {
    try {
      const exists = await this.fileExists(this.indexFilePath);
      if (!exists) {
        this.records = [];
        await this.saveIndex();
        return;
      }

      let shouldPruneLoadedRecords = false;
      const file = await fileIo.open(this.indexFilePath, fileIo.OpenMode.READ_ONLY);
      try {
        const stat = await fileIo.stat(this.indexFilePath);
        const buffer = new ArrayBuffer(stat.size);
        await fileIo.read(file.fd, buffer);
        const text = this.decoder.decodeToString(new Uint8Array(buffer));
        const parsed = SafeUtils.parseObj(text) as TransferUploadIndexData;
        if (parsed.version === INDEX_VERSION && Array.isArray(parsed.records)) {
          this.records = cloneTransferUploadRecords(parsed.records);
          shouldPruneLoadedRecords = true;
        } else {
          this.records = [];
        }
      } finally {
        await fileIo.close(file);
      }
      if (shouldPruneLoadedRecords) {
        await this.pruneLoadedRecords();
      }
    } catch (error) {
      this.records = [];
      logger.warn(TAG, `读取上传收件箱索引失败，将回退为空索引: ${this.stringifyError(error)}`);
      await this.saveIndex();
    }
  }

  private async saveIndex(): Promise<void> {
    const payload: TransferUploadIndexData = {
      version: INDEX_VERSION,
      records: cloneTransferUploadRecords(this.records)
    };
    const text = JSON.stringify(payload);
    const buffer = this.copyUint8ArrayToBuffer(this.encoder.encodeInto(text));
    await this.writeArrayBuffer(this.indexFilePath, buffer);
  }

  private async writeArrayBuffer(path: string, buffer: ArrayBuffer): Promise<void> {
    const file = await fileIo.open(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    try {
      await fileIo.write(file.fd, buffer);
    } finally {
      await fileIo.close(file);
    }
  }

  private async ensureStorageBudget(incomingBytes: number, maxTotalBytes: number = 0): Promise<void> {
    const budget = await this.getStorageBudget();
    const currentTotalBytes = budget.inboxBytes + budget.reservedBytes;
    if (maxTotalBytes > 0 && currentTotalBytes + incomingBytes > maxTotalBytes) {
      throw new Error(
        `传书收件箱总量已达上限: 当前 ${this.formatBytes(currentTotalBytes)}，本次需要 ${this.formatBytes(incomingBytes)}，总上限 ${this.formatBytes(maxTotalBytes)}`
      );
    }
    const requiredBytes = incomingBytes + budget.reserveBytes;
    if (budget.freeBytes > 0 && budget.freeBytes < requiredBytes) {
      throw new Error(
        `设备剩余空间不足: 文件需要 ${this.formatBytes(incomingBytes)}，建议至少保留 ${this.formatBytes(budget.reserveBytes)}，当前可用 ${this.formatBytes(budget.freeBytes)}`
      );
    }
  }

  private async reserveUploadBudget(incomingBytes: number, maxTotalBytes: number): Promise<void> {
    const previousLock = this.storageBudgetLock;
    let releaseLock: () => void = (): void => {};
    this.storageBudgetLock = new Promise<void>((resolve: () => void) => {
      releaseLock = resolve;
    });

    await previousLock;
    try {
      await this.ensureStorageBudget(incomingBytes, maxTotalBytes);
      this.reserveUploadBytes(incomingBytes);
    } finally {
      releaseLock();
    }
  }

  private calculateInboxBytes(): number {
    let totalBytes = 0;
    for (const record of this.records) {
      totalBytes += record.fileSizeBytes;
    }
    return totalBytes;
  }

  private reserveUploadBytes(bytes: number): void {
    if (bytes <= 0) {
      return;
    }
    this.reservedUploadBytes += bytes;
  }

  private releaseUploadBytes(bytes: number): void {
    if (bytes <= 0) {
      return;
    }
    this.reservedUploadBytes = Math.max(0, this.reservedUploadBytes - bytes);
  }

  private async getFreeStorageBytes(): Promise<number> {
    try {
      return await statfs.getFreeSize(this.filesDir);
    } catch (error) {
      logger.warn(TAG, `获取传书收件箱剩余空间失败: ${this.stringifyError(error)}`);
      return 0;
    }
  }

  private formatBytes(bytes: number): string {
    if (bytes <= 0) {
      return '0 B';
    }
    const units: string[] = ['B', 'KB', 'MB', 'GB', 'TB'];
    let value = bytes;
    let index = 0;
    while (value >= 1024 && index < units.length - 1) {
      value = value / 1024;
      index += 1;
    }
    const fractionDigits = index === 0 ? 0 : 1;
    return `${value.toFixed(fractionDigits)} ${units[index]}`;
  }

  private async fileExists(path: string): Promise<boolean> {
    try {
      await fileIo.stat(path);
      return true;
    } catch (_error) {
      return false;
    }
  }

  private async ensureDirectoryExists(path: string): Promise<void> {
    const exists = await fileIo.access(path);
    if (exists) {
      const stat = await fileIo.stat(path);
      if (!stat.isDirectory()) {
        throw new Error(`路径已存在但不是目录: ${path}`);
      }
      return;
    }
    try {
      await fileIo.mkdir(path, true);
    } catch (error) {
      const errorMessage = this.stringifyError(error);
      if (errorMessage.indexOf('File exists') >= 0) {
        const stat = await fileIo.stat(path);
        if (stat.isDirectory()) {
          return;
        }
      }
      throw error as Error;
    }
  }

  private async tryDeleteFile(path: string): Promise<void> {
    try {
      const exists = await this.fileExists(path);
      if (exists) {
        await fileIo.unlink(path);
      }
    } catch (_error) {
    }
  }

  private findRecordById(recordId: string): TransferUploadRecord | null {
    for (const record of this.records) {
      if (record.id === recordId) {
        return record;
      }
    }
    return null;
  }

  private async updateRecordStatus(
    recordId: string,
    status: 'imported' | 'import_failed' | 'import_cancelled'
  ): Promise<TransferUploadRecord | null> {
    const record = this.findRecordById(recordId);
    if (record === null) {
      return null;
    }
    record.status = status;
    await this.saveIndex();
    logger.info(TAG, `已更新传书记录状态: ${record.fileName}, status=${status}`);
    return cloneTransferUploadRecord(record);
  }

  private trimRecords(): TransferUploadRecord[] {
    if (this.records.length <= MAX_RECORD_COUNT) {
      return [];
    }
    const removedRecords = this.records.slice(MAX_RECORD_COUNT);
    this.records = this.records.slice(0, MAX_RECORD_COUNT);
    return removedRecords;
  }

  private normalizeUploadFileName(originalFileName: string): string {
    let normalized = originalFileName.trim();
    if (normalized.length <= 0) {
      normalized = 'upload.bin';
    }
    try {
      normalized = decodeURIComponent(normalized);
    } catch (_error) {
    }

    normalized = normalized.replace(/[\\/:*?"<>|]/g, '_');
    normalized = normalized.replace(/\s+/g, ' ').trim();
    if (normalized.length <= 0) {
      normalized = 'upload.bin';
    }
    if (normalized.length > 120) {
      normalized = normalized.substring(normalized.length - 120);
    }
    return normalized;
  }

  private buildRecordId(): string {
    const randomPart = Math.floor(Math.random() * 1000000).toString().padStart(6, '0');
    return `tx_${Date.now()}_${randomPart}`;
  }

  private copyUint8ArrayToBuffer(source: Uint8Array): ArrayBuffer {
    const copy = new Uint8Array(source.byteLength);
    copy.set(source);
    return copy.buffer;
  }

  private async flushPendingUploadChunks(session: TransferStagedUploadSession): Promise<void> {
    if (session.pendingWriteBytes <= 0) {
      return;
    }

    const writeBytes = session.pendingWriteBytes;
    await this.writeUploadChunksFully(session.fileDescriptor, session.pendingWriteChunks);
    session.flushedBytes += writeBytes;
    session.pendingWriteChunks = [];
    session.pendingWriteBytes = 0;
  }

  private async writeUploadChunksFully(fileDescriptor: number, chunks: Uint8Array[]): Promise<void> {
    for (const chunk of chunks) {
      if (chunk.byteLength <= 0) {
        continue;
      }
      await this.writeUint8ArrayFully(fileDescriptor, chunk);
    }
  }

  private async writeUint8ArrayFully(fileDescriptor: number, source: Uint8Array): Promise<void> {
    let writtenTotal = 0;
    while (writtenTotal < source.byteLength) {
      const remainingBytes = source.byteLength - writtenTotal;
      const writeBuffer = this.resolveWritableBuffer(source, writtenTotal);
      const options: WriteOptions = {
        length: remainingBytes
      };
      const writtenBytes = await fileIo.write(fileDescriptor, writeBuffer, options);
      if (writtenBytes <= 0 || writtenBytes > remainingBytes) {
        throw new Error(`上传文件写入不完整: expected=${source.byteLength}, actual=${writtenTotal + writtenBytes}`);
      }
      writtenTotal += writtenBytes;
    }
  }

  private resolveWritableBuffer(source: Uint8Array, offset: number): ArrayBuffer {
    if (offset <= 0) {
      const sourceBuffer = source.buffer;
      if (source.byteOffset === 0 && source.byteLength === sourceBuffer.byteLength) {
        return sourceBuffer;
      }
      return this.copyUint8ArrayToBuffer(source);
    }
    return this.copyUint8ArrayToBuffer(source.subarray(offset));
  }

  private assertUploadSizeMatches(session: TransferStagedUploadSession): void {
    if (session.receivedBytes !== session.expectedBytes) {
      throw new Error(`上传大小不匹配: expected=${session.expectedBytes}, actual=${session.receivedBytes}`);
    }
    if (session.flushedBytes !== session.expectedBytes) {
      throw new Error(`上传落盘大小不匹配: expected=${session.expectedBytes}, actual=${session.flushedBytes}`);
    }
  }

  private async tryCloseUploadFile(session: TransferStagedUploadSession): Promise<void> {
    try {
      await fileIo.close(session.fileDescriptor);
    } catch (_error) {
    }
  }

  private clearPendingImportMarkers(): void {
    AppStorage.delete('pendingFileUri');
    AppStorage.delete('pendingFileType');
    AppStorage.delete('pendingFileCategory');
    AppStorage.delete('pendingFileSource');
    AppStorage.delete('pendingFileTarget');
    AppStorage.delete('pendingFileDisplayName');
    AppStorage.delete(APP_STORAGE_PENDING_IMPORT_FLOW_ID);
    AppStorage.delete('fileImportPending');

    AppStorage.delete('pendingBackupUri');
    AppStorage.delete('backupImportPending');
    AppStorage.delete('pendingJsonUri');
    AppStorage.delete('pendingFontUri');
    AppStorage.delete('pendingCodeUri');
    AppStorage.delete('pendingCodeLanguage');
    AppStorage.delete('pendingAvifUri');
  }

  private preparePendingImportMarkers(record: TransferUploadRecord): void {
    if (this.shouldRouteToDataManagementImport(record.importCategory)) {
      const importFlowId: string = this.createPendingImportFlow(record, 'data_management');
      AppStorage.setOrCreate(APP_STORAGE_PENDING_IMPORT_FLOW_ID, importFlowId);
      AppStorage.setOrCreate('pendingFileUri', record.localUri);
      AppStorage.setOrCreate('pendingFileType', record.fileName);
      AppStorage.setOrCreate('pendingFileCategory', record.importCategory);
      AppStorage.setOrCreate('pendingFileSource', 'lan_transfer');
      AppStorage.setOrCreate('pendingFileTarget', 'inbox');
      AppStorage.setOrCreate('pendingFileDisplayName', record.fileName);
      AppStorage.setOrCreate('fileImportPending', true);
      return;
    }

    this.prepareMainMenuImportMarkers(record);
  }

  private shouldRouteToDataManagementImport(category: NetworkFolderImportCategory): boolean {
    return category === 'comic' || category === 'ebook' || category === 'pdf';
  }

  private shouldTrackImportResult(category: NetworkFolderImportCategory): boolean {
    return this.shouldRouteToDataManagementImport(category) ||
      category === 'backup' ||
      category === 'json' ||
      category === 'font' ||
      category === 'code' ||
      category === 'avif' ||
      category === 'image';
  }

  private createPendingImportFlow(record: TransferUploadRecord, target: string): string {
    const info: ImportFlowSessionInfo = new ImportFlowSessionInfo();
    info.sessionId = this.importFlowMonitor.createSessionId('import');
    info.entrySource = ImportFlowEntrySource.LAN_TRANSFER;
    info.contentType = this.mapTransferCategoryToImportFlowContentType(record.importCategory);
    info.sourceUri = record.localUri;
    info.targetPath = target;
    info.displayName = record.fileName;
    info.fileCount = 1;
    info.batchMode = false;
    info.transferRecordId = record.id;
    info.pageName = 'TransferUploadStoreService';
    info.startedAt = Date.now();
    const sessionId: string = this.importFlowMonitor.ensureSession(info);

    const event: ImportFlowEvent = new ImportFlowEvent();
    event.sessionId = sessionId;
    event.eventType = ImportFlowEventType.PENDING_MARKERS_WRITTEN;
    event.reason = 'lan_transfer_pending_markers_written';
    event.entrySource = ImportFlowEntrySource.LAN_TRANSFER;
    event.contentType = info.contentType;
    event.sourceUri = record.localUri;
    event.targetPath = target;
    event.displayName = record.fileName;
    event.fileCount = 1;
    event.transferRecordId = record.id;
    event.byteCount = record.fileSizeBytes;
    event.detail = `category=${record.importCategory}, target=${target}`;
    this.importFlowMonitor.record(event);
    return sessionId;
  }

  private mapTransferCategoryToImportFlowContentType(category: NetworkFolderImportCategory): ImportFlowContentType {
    switch (category) {
      case 'comic':
        return ImportFlowContentType.MANGA;
      case 'ebook':
        return ImportFlowContentType.EBOOK;
      case 'pdf':
        return ImportFlowContentType.PDF;
      case 'backup':
        return ImportFlowContentType.BACKUP;
      case 'json':
        return ImportFlowContentType.JSON;
      case 'font':
        return ImportFlowContentType.FONT;
      case 'code':
        return ImportFlowContentType.CODE;
      case 'avif':
        return ImportFlowContentType.AVIF;
      case 'image':
        return ImportFlowContentType.IMAGE;
      default:
        return ImportFlowContentType.UNKNOWN;
    }
  }

  private createExternalFileTaskParams(record: TransferUploadRecord): ExternalFileTaskParams {
    const kind = this.mapImportCategoryToExternalTaskKind(record.importCategory);
    return ExternalFileTaskFactory.createSingleFileTask(
      kind,
      record.localUri,
      record.contentType,
      ExternalFileTaskSource.TRANSFER,
      record.fileName,
      kind === ExternalFileTaskKind.CODE ? this.inferCodeLanguageFromFileName(record.fileName) : '',
      'inbox',
      record.id
    );
  }

  private mapImportCategoryToExternalTaskKind(category: NetworkFolderImportCategory): ExternalFileTaskKind {
    switch (category) {
      case 'comic':
        return ExternalFileTaskKind.COMIC;
      case 'ebook':
        return ExternalFileTaskKind.EBOOK;
      case 'pdf':
        return ExternalFileTaskKind.PDF;
      case 'backup':
        return ExternalFileTaskKind.BACKUP;
      case 'json':
        return ExternalFileTaskKind.JSON;
      case 'font':
        return ExternalFileTaskKind.FONT;
      case 'code':
        return ExternalFileTaskKind.CODE;
      case 'avif':
        return ExternalFileTaskKind.AVIF;
      case 'image':
        return ExternalFileTaskKind.IMAGE;
      default:
        return ExternalFileTaskKind.UNKNOWN;
    }
  }

  private prepareMainMenuImportMarkers(record: TransferUploadRecord): void {
    const importFlowId: string = this.createPendingImportFlow(record, 'main_menu');
    AppStorage.setOrCreate(APP_STORAGE_PENDING_IMPORT_FLOW_ID, importFlowId);
    AppStorage.setOrCreate('pendingFileSource', 'lan_transfer');
    AppStorage.setOrCreate('pendingFileTarget', 'inbox');
    AppStorage.setOrCreate('pendingFileDisplayName', record.fileName);

    if (record.importCategory === 'backup') {
      AppStorage.setOrCreate('pendingBackupUri', record.localUri);
      AppStorage.setOrCreate('pendingFileCategory', 'backup');
      AppStorage.setOrCreate('backupImportPending', true);
      return;
    }

    if (record.importCategory === 'json') {
      AppStorage.setOrCreate('pendingJsonUri', record.localUri);
      AppStorage.setOrCreate('pendingFileCategory', 'json');
      return;
    }

    if (record.importCategory === 'font') {
      AppStorage.setOrCreate('pendingFontUri', record.localUri);
      AppStorage.setOrCreate('pendingFileCategory', 'font');
      return;
    }

    if (record.importCategory === 'code') {
      AppStorage.setOrCreate('pendingCodeUri', record.localUri);
      AppStorage.setOrCreate('pendingCodeLanguage', this.inferCodeLanguageFromFileName(record.fileName));
      AppStorage.setOrCreate('pendingFileCategory', 'code');
      return;
    }

    if (record.importCategory === 'avif' || record.importCategory === 'image') {
      AppStorage.setOrCreate('pendingAvifUri', record.localUri);
      AppStorage.setOrCreate('pendingFileCategory', record.importCategory);
      return;
    }

    AppStorage.setOrCreate('pendingFileUri', record.localUri);
    AppStorage.setOrCreate('pendingFileType', record.fileName);
    AppStorage.setOrCreate('pendingFileCategory', record.importCategory);
    AppStorage.setOrCreate('fileImportPending', true);
  }

  private inferCodeLanguageFromFileName(fileName: string): string {
    const extension = getNetworkFolderFileExtension(fileName);
    switch (extension) {
      case 'ts':
      case 'ets':
      case 'tsx':
        return 'typescript';
      case 'js':
      case 'jsx':
        return 'javascript';
      case 'py':
        return 'python';
      case 'java':
        return 'java';
      case 'cpp':
      case 'c':
      case 'h':
      case 'hpp':
        return 'cpp';
      case 'cs':
        return 'csharp';
      case 'go':
        return 'go';
      case 'rs':
        return 'rust';
      case 'swift':
        return 'swift';
      case 'kt':
        return 'kotlin';
      case 'rb':
        return 'ruby';
      case 'php':
        return 'php';
      case 'html':
      case 'htm':
        return 'html';
      case 'css':
        return 'css';
      case 'scss':
        return 'scss';
      case 'less':
        return 'less';
      case 'jsonc':
        return 'json';
      case 'xml':
        return 'xml';
      case 'yaml':
      case 'yml':
        return 'yaml';
      case 'md':
      case 'markdown':
        return 'markdown';
      case 'sql':
        return 'sql';
      case 'sh':
      case 'bash':
      case 'zsh':
        return 'shell';
      case 'ps1':
        return 'powershell';
      case 'bat':
      case 'cmd':
        return 'bat';
      case 'ini':
      case 'conf':
      case 'cfg':
        return 'ini';
      case 'toml':
        return 'toml';
      case 'lua':
        return 'lua';
      case 'r':
        return 'r';
      case 'dart':
        return 'dart';
      case 'vue':
        return 'vue';
      case 'svelte':
        return 'svelte';
      default:
        return 'plaintext';
    }
  }

  private clearTransferImportTrackingMarkers(): void {
    AppStorage.delete(APP_STORAGE_TRANSFER_RECORD_ID);
    AppStorage.delete(APP_STORAGE_TRANSFER_RESULT);
    AppStorage.delete(APP_STORAGE_TRANSFER_TRACKING_ACTIVE);
  }

  private async pruneLoadedRecords(): Promise<void> {
    const validRecords: TransferUploadRecord[] = [];
    const removedRecords: TransferUploadRecord[] = [];
    for (const record of this.records) {
      const exists = await this.fileExists(record.localPath);
      if (exists && validRecords.length < MAX_RECORD_COUNT) {
        validRecords.push(record);
      } else {
        removedRecords.push(record);
      }
    }
    if (removedRecords.length <= 0) {
      return;
    }
    this.records = validRecords;
    logger.info(TAG, `上传收件箱索引已清理 ${removedRecords.length} 条无效或超限记录`);
    await this.saveIndex();
    await this.deleteRecordFiles(removedRecords);
  }

  private async cleanupFilesDirectory(): Promise<void> {
    const keepFileNames: string[] = [];
    for (const record of this.records) {
      keepFileNames.push(this.getFileNameFromPath(record.localPath));
    }
    try {
      const fileNames = await fileIo.listFile(this.filesDir);
      const now = Date.now();
      for (const fileName of fileNames) {
        const fullPath = `${this.filesDir}/${fileName}`;
        if (fileName.endsWith('.part')) {
          const stat = await fileIo.stat(fullPath);
          if (now - stat.mtime >= STALE_PART_FILE_MAX_AGE_MS) {
            await this.tryDeleteFile(fullPath);
          }
          continue;
        }
        if (!keepFileNames.includes(fileName)) {
          await this.tryDeleteFile(fullPath);
        }
      }
    } catch (error) {
      logger.warn(TAG, `清理上传收件箱目录失败: ${this.stringifyError(error)}`);
    }
  }

  private async deleteRecordFiles(records: TransferUploadRecord[]): Promise<void> {
    for (const record of records) {
      const exists = await this.fileExists(record.localPath);
      if (exists) {
        await this.tryDeleteFile(record.localPath);
      }
    }
  }

  private containsRecordId(recordIds: string[], recordId: string): boolean {
    for (const item of recordIds) {
      if (item === recordId) {
        return true;
      }
    }
    return false;
  }

  private getFileNameFromPath(path: string): string {
    const normalizedPath = path.trim();
    const lastSlashIndex = normalizedPath.lastIndexOf('/');
    if (lastSlashIndex < 0 || lastSlashIndex >= normalizedPath.length - 1) {
      return normalizedPath;
    }
    return normalizedPath.substring(lastSlashIndex + 1);
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

export function getTransferUploadStoreService(): TransferUploadStoreService {
  return TransferUploadStoreService.getInstance();
}
