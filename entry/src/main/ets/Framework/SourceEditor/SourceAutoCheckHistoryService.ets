import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { logger } from '../../Utils/Logger';
import { SafeUtils } from '../../Utils/SafeUtils';

const TAG = 'SourceAutoCheckHistoryService';
const PREF_NAME = 'source_auto_check_history';
const INDEX_KEY = 'record_index';
const MAX_RECORD_COUNT: number = 80;

export type SourceAutoCheckRecordStatus = 'RUNNING' | 'COMPLETED' | 'FAILED' | 'CANCELLED';

export interface SourceAutoCheckRecordIndexEntry {
  taskId: string;
  sourceId: number;
  sourcePkg: string;
  sourceName: string;
  status: SourceAutoCheckRecordStatus;
  startTime: number;
  endTime: number;
  summary: string;
}

export interface SourceAutoCheckRecord {
  taskId: string;
  sourceId: number;
  sourcePkg: string;
  sourceName: string;
  initialUrl: string;
  status: SourceAutoCheckRecordStatus;
  startTime: number;
  endTime: number;
  durationMs: number;
  workflowKeysJson: string;
  workflowLabelsJson: string;
  siteCount: number;
  recommendedSiteBaseUrl: string;
  summary: string;
  errorMessage: string;
  reportJson: string;
  updateTime: number;
}

export class SourceAutoCheckHistoryService {
  private static instance: SourceAutoCheckHistoryService | null = null;
  private preferencesStore: preferences.Preferences | null = null;
  private initialized: boolean = false;

  private constructor() {}

  public static getInstance(): SourceAutoCheckHistoryService {
    if (SourceAutoCheckHistoryService.instance === null) {
      SourceAutoCheckHistoryService.instance = new SourceAutoCheckHistoryService();
    }
    return SourceAutoCheckHistoryService.instance;
  }

  public async initialize(context: common.UIAbilityContext): Promise<void> {
    if (this.initialized && this.preferencesStore !== null) {
      return;
    }
    try {
      const options: preferences.Options = { name: PREF_NAME };
      this.preferencesStore = await preferences.getPreferences(context, options);
      this.initialized = true;
    } catch (error) {
      logger.warn(TAG, `初始化巡检历史存储失败: ${String(error)}`);
    }
  }

  public async saveRecord(record: SourceAutoCheckRecord): Promise<void> {
    if (this.preferencesStore === null) {
      logger.warn(TAG, '保存巡检记录失败: 存储尚未初始化');
      return;
    }
    try {
      await this.preferencesStore.put(this.getRecordKey(record.taskId), JSON.stringify(record));
      await this.saveIndexEntry(record);
      await this.preferencesStore.flush();
      logger.debug(TAG, `巡检记录已保存: taskId=${record.taskId}, status=${record.status}`);
    } catch (error) {
      logger.warn(TAG, `保存巡检记录失败: ${String(error)}`);
    }
  }

  public async getRecord(taskId: string): Promise<SourceAutoCheckRecord | null> {
    if (this.preferencesStore === null || taskId.length <= 0) {
      return null;
    }
    try {
      const rawValue = await this.preferencesStore.get(this.getRecordKey(taskId), '');
      const recordJson: string = rawValue as string;
      if (recordJson.length <= 0) {
        return null;
      }
      return SafeUtils.parseObj<SourceAutoCheckRecord>(recordJson);
    } catch (error) {
      logger.warn(TAG, `读取巡检记录失败: taskId=${taskId}, error=${String(error)}`);
      return null;
    }
  }

  public async getLatestRecordForSource(sourceId: number, sourcePkg: string): Promise<SourceAutoCheckRecord | null> {
    const indexEntries: SourceAutoCheckRecordIndexEntry[] = await this.getIndexEntries();
    for (let index = 0; index < indexEntries.length; index += 1) {
      const entry: SourceAutoCheckRecordIndexEntry = indexEntries[index];
      if (entry.sourceId === sourceId || (sourcePkg.length > 0 && entry.sourcePkg === sourcePkg)) {
        return await this.getRecord(entry.taskId);
      }
    }
    return null;
  }

  public async getRecordsForSource(sourceId: number, sourcePkg: string, limit: number): Promise<SourceAutoCheckRecord[]> {
    const records: SourceAutoCheckRecord[] = [];
    if (limit <= 0) {
      return records;
    }
    const indexEntries: SourceAutoCheckRecordIndexEntry[] = await this.getIndexEntries();
    for (let index = 0; index < indexEntries.length; index += 1) {
      const entry: SourceAutoCheckRecordIndexEntry = indexEntries[index];
      if (entry.sourceId !== sourceId && (sourcePkg.length <= 0 || entry.sourcePkg !== sourcePkg)) {
        continue;
      }
      const record: SourceAutoCheckRecord | null = await this.getRecord(entry.taskId);
      if (record !== null) {
        records.push(record);
      }
      if (records.length >= limit) {
        break;
      }
    }
    return records;
  }

  private async saveIndexEntry(record: SourceAutoCheckRecord): Promise<void> {
    if (this.preferencesStore === null) {
      return;
    }
    const previousEntries: SourceAutoCheckRecordIndexEntry[] = await this.getIndexEntries();
    const nextEntries: SourceAutoCheckRecordIndexEntry[] = [];
    const nextEntry: SourceAutoCheckRecordIndexEntry = {
      taskId: record.taskId,
      sourceId: record.sourceId,
      sourcePkg: record.sourcePkg,
      sourceName: record.sourceName,
      status: record.status,
      startTime: record.startTime,
      endTime: record.endTime,
      summary: record.summary
    };
    nextEntries.push(nextEntry);
    for (let index = 0; index < previousEntries.length; index += 1) {
      const entry: SourceAutoCheckRecordIndexEntry = previousEntries[index];
      if (entry.taskId === record.taskId) {
        continue;
      }
      if (nextEntries.length >= MAX_RECORD_COUNT) {
        await this.preferencesStore.delete(this.getRecordKey(entry.taskId));
        continue;
      }
      nextEntries.push(entry);
    }
    await this.preferencesStore.put(INDEX_KEY, JSON.stringify(nextEntries));
  }

  private async getIndexEntries(): Promise<SourceAutoCheckRecordIndexEntry[]> {
    if (this.preferencesStore === null) {
      return [];
    }
    try {
      const rawValue = await this.preferencesStore.get(INDEX_KEY, '[]');
      const indexJson: string = rawValue as string;
      return SafeUtils.parseArr<SourceAutoCheckRecordIndexEntry[]>(indexJson);
    } catch (error) {
      logger.warn(TAG, `读取巡检记录索引失败: ${String(error)}`);
      return [];
    }
  }

  private getRecordKey(taskId: string): string {
    return `record_${taskId}`;
  }
}

export const sourceAutoCheckHistoryService: SourceAutoCheckHistoryService =
  SourceAutoCheckHistoryService.getInstance();
