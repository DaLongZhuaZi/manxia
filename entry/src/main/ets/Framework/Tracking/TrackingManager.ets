/**
 * 跟踪服务管理器
 * 统一管理本地跟踪记录的CRUD操作
 * 为后续第三方服务同步提供基础
 */

import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { DatabaseManager } from 'manxia_core/src/main/ets/Framework/Database/DatabaseManager';
import { DatabaseRecord, DatabaseValue, TrackRecordDatabaseRecord } from 'manxia_core/src/main/ets/Framework/Database/DatabaseTypes';
import { generateUUID } from '../Utils/UUIDGenerator';
import {
  TrackRecord,
  TrackerId,
  TrackStatus,
  SyncStatus,
  TrackContentType,
  CreateTrackRecordParams,
  UpdateTrackRecordParams,
  getTrackerName
} from './TrackingModels';

const TAG = 'TrackingManager';

/**
 * 跟踪记录变化监听器
 */
export type TrackRecordListener = (record: TrackRecord) => void;

/**
 * 跟踪服务管理器（单例）
 */
export class TrackingManager {
  private static instance: TrackingManager | null = null;
  private dbManager: DatabaseManager;
  private listeners: Set<TrackRecordListener> = new Set();
  private initialized: boolean = false;

  private constructor() {
    this.dbManager = DatabaseManager.getInstance();
  }

  /**
   * 获取单例实例
   */
  public static getInstance(): TrackingManager {
    if (!TrackingManager.instance) {
      TrackingManager.instance = new TrackingManager();
    }
    return TrackingManager.instance;
  }

  /**
   * 初始化管理器
   */
  public async initialize(): Promise<void> {
    if (this.initialized) {
      return;
    }
    this.initialized = true;
    logger.info(TAG, '✅ 跟踪服务管理器初始化完成');
  }

  /**
   * 创建跟踪记录
   */
  public async createTrackRecord(params: CreateTrackRecordParams): Promise<TrackRecord> {
    const now = Date.now();
    const record: TrackRecord = {
      id: generateUUID(),
      contentId: params.contentId,
      contentType: params.contentType,
      trackerId: params.trackerId,
      remoteId: params.remoteId,
      remoteTitle: params.remoteTitle || '',
      remoteUrl: params.remoteUrl || '',
      lastChapterRead: 0,
      totalChapters: 0,
      score: 0,
      status: TrackStatus.UNKNOWN,
      startedReadingDate: 0,
      finishedReadingDate: 0,
      lastSyncTime: 0,
      syncStatus: SyncStatus.PENDING,
      createTime: now,
      updateTime: now
    };

    try {
      const sql = `INSERT INTO track_record (
        id, contentId, contentType, trackerId, remoteId, remoteTitle, remoteUrl,
        lastChapterRead, totalChapters, score, status, startedReadingDate,
        finishedReadingDate, lastSyncTime, syncStatus, createTime, updateTime
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`;

      await this.dbManager.executeSql(sql, [
        record.id,
        record.contentId,
        record.contentType,
        record.trackerId,
        record.remoteId,
        record.remoteTitle,
        record.remoteUrl,
        record.lastChapterRead,
        record.totalChapters,
        record.score,
        record.status,
        record.startedReadingDate,
        record.finishedReadingDate,
        record.lastSyncTime,
        record.syncStatus,
        record.createTime,
        record.updateTime
      ]);

      logger.info(TAG, `✅ 创建跟踪记录: contentId=${params.contentId}, tracker=${getTrackerName(params.trackerId)}`);
      this.notifyListeners(record);
      return record;
    } catch (error) {
      logger.error(TAG, `❌ 创建跟踪记录失败: ${String(error)}`);
      throw new Error(String(error));
    }
  }

  /**
   * 获取内容的所有跟踪记录
   */
  public async getTrackRecords(contentId: string): Promise<TrackRecord[]> {
    try {
      const sql = 'SELECT * FROM track_record WHERE contentId = ?';
      const results = await this.dbManager.querySql(sql, [contentId]);
      return this.parseTrackRecords(results);
    } catch (error) {
      logger.error(TAG, `❌ 获取跟踪记录失败: ${String(error)}`);
      return [];
    }
  }

  /**
   * 获取特定跟踪服务的记录
   */
  public async getTrackRecord(contentId: string, trackerId: TrackerId): Promise<TrackRecord | null> {
    try {
      const sql = 'SELECT * FROM track_record WHERE contentId = ? AND trackerId = ?';
      const results = await this.dbManager.querySql(sql, [contentId, trackerId]);
      const records = this.parseTrackRecords(results);
      return records.length > 0 ? records[0] : null;
    } catch (error) {
      logger.error(TAG, `❌ 获取跟踪记录失败: ${String(error)}`);
      return null;
    }
  }

  /**
   * 更新跟踪记录
   */
  public async updateTrackRecord(
    contentId: string,
    trackerId: TrackerId,
    params: UpdateTrackRecordParams
  ): Promise<boolean> {
    try {
      const updates: string[] = [];
      const values: (string | number)[] = [];

      if (params.lastChapterRead !== undefined) {
        updates.push('lastChapterRead = ?');
        values.push(params.lastChapterRead);
      }
      if (params.totalChapters !== undefined) {
        updates.push('totalChapters = ?');
        values.push(params.totalChapters);
      }
      if (params.score !== undefined) {
        updates.push('score = ?');
        values.push(params.score);
      }
      if (params.status !== undefined) {
        updates.push('status = ?');
        values.push(params.status);
      }
      if (params.startedReadingDate !== undefined) {
        updates.push('startedReadingDate = ?');
        values.push(params.startedReadingDate);
      }
      if (params.finishedReadingDate !== undefined) {
        updates.push('finishedReadingDate = ?');
        values.push(params.finishedReadingDate);
      }
      if (params.syncStatus !== undefined) {
        updates.push('syncStatus = ?');
        values.push(params.syncStatus);
      }

      if (updates.length === 0) {
        return true;
      }

      updates.push('updateTime = ?');
      values.push(Date.now());

      values.push(contentId);
      values.push(trackerId);

      const sql = `UPDATE track_record SET ${updates.join(', ')} WHERE contentId = ? AND trackerId = ?`;
      await this.dbManager.executeSql(sql, values);

      logger.info(TAG, `✅ 更新跟踪记录: contentId=${contentId}, tracker=${getTrackerName(trackerId)}`);

      // 获取更新后的记录并通知监听器
      const updatedRecord = await this.getTrackRecord(contentId, trackerId);
      if (updatedRecord) {
        this.notifyListeners(updatedRecord);
      }

      return true;
    } catch (error) {
      logger.error(TAG, `❌ 更新跟踪记录失败: ${String(error)}`);
      return false;
    }
  }

  /**
   * 更新阅读进度
   * 这是最常用的方法，在阅读器中调用
   */
  public async updateReadingProgress(
    contentId: string,
    trackerId: TrackerId,
    chapterNumber: number,
    totalChapters?: number
  ): Promise<boolean> {
    const record = await this.getTrackRecord(contentId, trackerId);
    if (!record) {
      logger.warn(TAG, `跟踪记录不存在: contentId=${contentId}, trackerId=${trackerId}`);
      return false;
    }

    // 只有当新章节号大于已记录的章节号时才更新
    if (chapterNumber <= record.lastChapterRead) {
      return true;
    }

    const updateParams: UpdateTrackRecordParams = {
      lastChapterRead: chapterNumber,
      syncStatus: SyncStatus.PENDING
    };

    // 如果是第一次阅读，设置开始日期和状态
    if (record.lastChapterRead === 0 && record.status === TrackStatus.UNKNOWN) {
      updateParams.startedReadingDate = Date.now();
      updateParams.status = TrackStatus.READING;
    }

    // 更新总章节数
    if (totalChapters !== undefined && totalChapters > record.totalChapters) {
      updateParams.totalChapters = totalChapters;
    }

    // 如果读完了最后一章，自动标记为完成
    if (totalChapters !== undefined && chapterNumber >= totalChapters) {
      updateParams.status = TrackStatus.COMPLETED;
      updateParams.finishedReadingDate = Date.now();
    }

    return this.updateTrackRecord(contentId, trackerId, updateParams);
  }

  /**
   * 删除跟踪记录
   */
  public async deleteTrackRecord(contentId: string, trackerId: TrackerId): Promise<boolean> {
    try {
      const sql = 'DELETE FROM track_record WHERE contentId = ? AND trackerId = ?';
      await this.dbManager.executeSql(sql, [contentId, trackerId]);
      logger.info(TAG, `✅ 删除跟踪记录: contentId=${contentId}, tracker=${getTrackerName(trackerId)}`);
      return true;
    } catch (error) {
      logger.error(TAG, `❌ 删除跟踪记录失败: ${String(error)}`);
      return false;
    }
  }

  /**
   * 删除内容的所有跟踪记录
   */
  public async deleteAllTrackRecords(contentId: string): Promise<boolean> {
    try {
      const sql = 'DELETE FROM track_record WHERE contentId = ?';
      await this.dbManager.executeSql(sql, [contentId]);
      logger.info(TAG, `✅ 删除所有跟踪记录: contentId=${contentId}`);
      return true;
    } catch (error) {
      logger.error(TAG, `❌ 删除跟踪记录失败: ${String(error)}`);
      return false;
    }
  }

  /**
   * 获取待同步的记录
   */
  public async getPendingSyncRecords(): Promise<TrackRecord[]> {
    try {
      const sql = 'SELECT * FROM track_record WHERE syncStatus = ?';
      const results = await this.dbManager.querySql(sql, [SyncStatus.PENDING]);
      return this.parseTrackRecords(results);
    } catch (error) {
      logger.error(TAG, `❌ 获取待同步记录失败: ${String(error)}`);
      return [];
    }
  }

  /**
   * 标记记录为已同步
   */
  public async markAsSynced(contentId: string, trackerId: TrackerId): Promise<boolean> {
    return this.updateTrackRecord(contentId, trackerId, {
      syncStatus: SyncStatus.SYNCED
    });
  }

  /**
   * 标记记录同步失败
   */
  public async markAsFailed(contentId: string, trackerId: TrackerId): Promise<boolean> {
    return this.updateTrackRecord(contentId, trackerId, {
      syncStatus: SyncStatus.FAILED
    });
  }

  /**
   * 添加监听器
   */
  public addListener(listener: TrackRecordListener): void {
    this.listeners.add(listener);
  }

  /**
   * 移除监听器
   */
  public removeListener(listener: TrackRecordListener): void {
    this.listeners.delete(listener);
  }

  /**
   * 通知监听器
   */
  private notifyListeners(record: TrackRecord): void {
    this.listeners.forEach(listener => {
      try {
        listener(record);
      } catch (error) {
        logger.error(TAG, `监听器回调失败: ${String(error)}`);
      }
    });
  }

  /**
   * 解析数据库查询结果为TrackRecord数组
   */
  private parseTrackRecords(results: DatabaseRecord[]): TrackRecord[] {
    if (!results || results.length === 0) {
      return [];
    }

    const records: TrackRecord[] = [];
    for (let i = 0; i < results.length; i++) {
      const row: TrackRecordDatabaseRecord = results[i] as TrackRecordDatabaseRecord;
      const record: TrackRecord = {
        id: String(row.id || ''),
        contentId: String(row.contentId || ''),
        contentType: (row.contentType as TrackContentType) || TrackContentType.MANGA,
        trackerId: Number(row.trackerId) || TrackerId.UNKNOWN,
        remoteId: String(row.remoteId || ''),
        remoteTitle: String(row.remoteTitle || ''),
        remoteUrl: String(row.remoteUrl || ''),
        lastChapterRead: Number(row.lastChapterRead) || 0,
        totalChapters: Number(row.totalChapters) || 0,
        score: Number(row.score) || 0,
        status: Number(row.status) || TrackStatus.UNKNOWN,
        startedReadingDate: Number(row.startedReadingDate) || 0,
        finishedReadingDate: Number(row.finishedReadingDate) || 0,
        lastSyncTime: Number(row.lastSyncTime) || 0,
        syncStatus: (row.syncStatus as SyncStatus) || SyncStatus.PENDING,
        createTime: Number(row.createTime) || 0,
        updateTime: Number(row.updateTime) || 0
      };
      records.push(record);
    }
    return records;
  }

  /**
   * 检查是否已初始化
   */
  public isInitialized(): boolean {
    return this.initialized;
  }
}

// 导出便捷函数
export function getTrackingManager(): TrackingManager {
  return TrackingManager.getInstance();
}
