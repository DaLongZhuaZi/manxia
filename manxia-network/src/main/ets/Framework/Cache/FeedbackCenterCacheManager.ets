/**
 * 反馈中心缓存和本地草稿管理器。
 *
 * 远程 JSON 缓存只保存公开 Issue 列表/详情；草稿和待上传附件单独管理，
 * 清理远程缓存不会影响用户尚未提交的内容。
 */

import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { preferences } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';

const TAG: string = 'FeedbackCenterCacheManager';
const CACHE_NAME: string = 'feedback_center_cache';
const CACHE_DATA_KEY: string = 'remote_issue_json';
const MAX_CACHE_ENTRIES: number = 48;
const MAX_CACHE_BYTES: number = 8 * 1024 * 1024;
const DRAFT_READ_LIMIT_BYTES: number = 512 * 1024;

export const FEEDBACK_DRAFT_FILE_NAME: string = 'feedback/draft.json';
export const FEEDBACK_DRAFT_PART_FILE_NAME: string = 'feedback/draft.json.part';
export const FEEDBACK_PENDING_DIR_NAME: string = 'feedback/pending';
export const FEEDBACK_MAX_ATTACHMENT_BYTES: number = 160 * 1024 * 1024;

interface FeedbackCacheRecord {
  key: string;
  value: string;
  savedAt: number;
  lastAccessedAt?: number;
}

interface FeedbackCacheStore {
  records: FeedbackCacheRecord[];
}

interface FeedbackDraftAttachmentReference {
  localPath: string;
}

interface FeedbackDraftReferenceStore {
  attachments?: FeedbackDraftAttachmentReference[];
}

export interface FeedbackCenterCacheStats {
  entryCount: number;
  sizeBytes: number;
  lastUpdated: number;
  draftExists: boolean;
  draftSizeBytes: number;
  pendingAttachmentCount: number;
  pendingAttachmentBytes: number;
}

export class FeedbackCenterCacheManager {
  private static instance: FeedbackCenterCacheManager | null = null;
  private readonly records: Map<string, FeedbackCacheRecord> = new Map<string, FeedbackCacheRecord>();
  private preferencesStore: preferences.Preferences | null = null;
  private context: common.UIAbilityContext | null = null;
  private initialized: boolean = false;
  private lastUpdated: number = 0;
  private localStats: FeedbackCenterCacheStats = {
    entryCount: 0,
    sizeBytes: 0,
    lastUpdated: 0,
    draftExists: false,
    draftSizeBytes: 0,
    pendingAttachmentCount: 0,
    pendingAttachmentBytes: 0
  };

  private constructor() {}

  public static getInstance(): FeedbackCenterCacheManager {
    if (FeedbackCenterCacheManager.instance === null) {
      FeedbackCenterCacheManager.instance = new FeedbackCenterCacheManager();
    }
    return FeedbackCenterCacheManager.instance;
  }

  public async initialize(context: common.UIAbilityContext): Promise<void> {
    if (this.initialized) {
      if (this.context === null) {
        this.context = context;
      }
      return;
    }
    this.context = context;
    try {
      this.preferencesStore = await preferences.getPreferences(context, { name: CACHE_NAME });
      const rawValue = await this.preferencesStore.get(CACHE_DATA_KEY, '');
      if (typeof rawValue === 'string' && rawValue.length > 0) {
        this.restore(rawValue);
      }
      // Persist the trimmed representation so an oversized legacy cache is capped on disk too.
      await this.persist();
      this.initialized = true;
      await this.cleanupOrphanPendingAttachments();
      await this.refreshLocalStats();
      logger.info(TAG, `反馈中心缓存初始化完成: entries=${this.records.size}`);
    } catch (error) {
      this.initialized = true;
      await this.refreshLocalStats();
      logger.warn(TAG, `反馈中心缓存初始化失败，将使用内存缓存: ${String(error)}`);
    }
  }

  public async getJson(key: string, maxAgeMilliseconds: number): Promise<string | null> {
    const record = this.records.get(key);
    if (record === undefined) {
      return null;
    }
    if (Date.now() - record.savedAt > maxAgeMilliseconds) {
      this.records.delete(key);
      await this.persist();
      this.updateRemoteStats();
      return null;
    }
    record.lastAccessedAt = Date.now();
    await this.persist();
    this.updateRemoteStats();
    return record.value;
  }

  public async putJson(key: string, value: string): Promise<void> {
    const record: FeedbackCacheRecord = {
      key: key,
      value: value,
      savedAt: Date.now(),
      lastAccessedAt: Date.now()
    };
    this.records.set(key, record);
    this.trimToLimit();
    this.lastUpdated = record.savedAt;
    await this.persist();
    this.updateRemoteStats();
  }

  public async remove(key: string): Promise<void> {
    if (this.records.delete(key)) {
      this.lastUpdated = Date.now();
      await this.persist();
      this.updateRemoteStats();
    }
  }

  /** 只清理远程 Issue JSON，不触碰草稿和待上传附件。 */
  public async clear(): Promise<void> {
    this.records.clear();
    this.lastUpdated = Date.now();
    if (this.preferencesStore !== null) {
      await this.preferencesStore.delete(CACHE_DATA_KEY);
      await this.preferencesStore.flush();
    }
    this.updateRemoteStats();
    logger.info(TAG, '反馈中心远程缓存已清理');
  }

  public getStats(): FeedbackCenterCacheStats {
    return {
      entryCount: this.localStats.entryCount,
      sizeBytes: this.localStats.sizeBytes,
      lastUpdated: this.localStats.lastUpdated,
      draftExists: this.localStats.draftExists,
      draftSizeBytes: this.localStats.draftSizeBytes,
      pendingAttachmentCount: this.localStats.pendingAttachmentCount,
      pendingAttachmentBytes: this.localStats.pendingAttachmentBytes
    };
  }

  public async refreshLocalStats(): Promise<void> {
    const context = this.context;
    if (context === null) {
      this.updateRemoteStats();
      return;
    }
    const draftPath = `${context.filesDir}/${FEEDBACK_DRAFT_FILE_NAME}`;
    const draftPartPath = `${context.filesDir}/${FEEDBACK_DRAFT_PART_FILE_NAME}`;
    let draftSizeBytes: number = await this.fileSize(draftPath);
    if (draftSizeBytes === 0) {
      draftSizeBytes = await this.fileSize(draftPartPath);
    }

    const pendingDir = `${context.filesDir}/${FEEDBACK_PENDING_DIR_NAME}`;
    let pendingAttachmentCount: number = 0;
    let pendingAttachmentBytes: number = 0;
    try {
      const names: string[] = await fileIo.listFile(pendingDir);
      for (const name of names) {
        const path = `${pendingDir}/${name}`;
        const size = await this.fileSize(path);
        if (size > 0) {
          pendingAttachmentCount += 1;
          pendingAttachmentBytes += size;
        }
      }
    } catch (_) {
      // 目录不存在时按空目录处理。
    }

    this.localStats = {
      entryCount: this.records.size,
      sizeBytes: this.remoteCacheBytes(),
      lastUpdated: this.lastUpdated,
      draftExists: draftSizeBytes > 0,
      draftSizeBytes: draftSizeBytes,
      pendingAttachmentCount: pendingAttachmentCount,
      pendingAttachmentBytes: pendingAttachmentBytes
    };
  }

  /** 删除当前草稿及其引用的待上传附件，适用于用户明确确认后的清理操作。 */
  public async deleteFeedbackDraftAndAttachments(): Promise<void> {
    const context = this.context;
    if (context === null) {
      return;
    }
    const pendingRoot = `${context.filesDir}/${FEEDBACK_PENDING_DIR_NAME}/`;
    const references = await this.readDraftAttachmentReferences();
    for (const path of references) {
      if (path.indexOf(pendingRoot) === 0) {
        await this.unlinkIfPresent(path);
      }
    }
    await this.unlinkIfPresent(`${context.filesDir}/${FEEDBACK_DRAFT_FILE_NAME}`);
    await this.unlinkIfPresent(`${context.filesDir}/${FEEDBACK_DRAFT_PART_FILE_NAME}`);
    await this.refreshLocalStats();
    logger.info(TAG, '反馈中心草稿及其待上传附件已清理');
  }

  /** 只清理没有被当前草稿引用的待上传附件。 */
  public async cleanupOrphanPendingAttachments(): Promise<void> {
    const context = this.context;
    if (context === null) {
      return;
    }
    const pendingDir = `${context.filesDir}/${FEEDBACK_PENDING_DIR_NAME}`;
    const references = await this.readDraftAttachmentReferences();
    try {
      const names: string[] = await fileIo.listFile(pendingDir);
      for (const name of names) {
        const path = `${pendingDir}/${name}`;
        if (!references.has(path)) {
          await this.unlinkIfPresent(path);
        }
      }
    } catch (_) {
      // 目录不存在时无需清理。
    }
    await this.refreshLocalStats();
  }

  private async readDraftAttachmentReferences(): Promise<Set<string>> {
    const references: Set<string> = new Set<string>();
    const context = this.context;
    if (context === null) {
      return references;
    }
    const draftPaths: string[] = [
      `${context.filesDir}/${FEEDBACK_DRAFT_FILE_NAME}`,
      `${context.filesDir}/${FEEDBACK_DRAFT_PART_FILE_NAME}`
    ];
    for (const path of draftPaths) {
      const raw = await this.readText(path);
      if (raw.length === 0) {
        continue;
      }
      try {
        const draft = JSON.parse(raw) as FeedbackDraftReferenceStore;
        if (draft.attachments === undefined) {
          continue;
        }
        for (const attachment of draft.attachments) {
          if (attachment.localPath.length > 0) {
            references.add(attachment.localPath);
          }
        }
      } catch (error) {
        logger.warn(TAG, `读取草稿附件引用失败: ${String(error)}`);
      }
    }
    return references;
  }

  private async readText(path: string): Promise<string> {
    let file: fileIo.File | null = null;
    try {
      file = await fileIo.open(path, fileIo.OpenMode.READ_ONLY);
      const stat = await fileIo.stat(file.fd);
      if (stat.size <= 0 || stat.size > DRAFT_READ_LIMIT_BYTES) {
        return '';
      }
      const buffer = new ArrayBuffer(stat.size);
      const readBytes = await fileIo.read(file.fd, buffer, { length: stat.size });
      return util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(buffer, 0, readBytes));
    } catch (_) {
      return '';
    } finally {
      if (file !== null) {
        await fileIo.close(file);
      }
    }
  }

  private async fileSize(path: string): Promise<number> {
    try {
      const stat = await fileIo.stat(path);
      return stat.isDirectory() ? 0 : stat.size;
    } catch (_) {
      return 0;
    }
  }

  private async unlinkIfPresent(path: string): Promise<void> {
    try {
      await fileIo.unlink(path);
    } catch (_) {
      // 文件不存在或已经被页面清理时无需重复报错。
    }
  }

  private restore(rawValue: string): void {
    try {
      const store = JSON.parse(rawValue) as FeedbackCacheStore;
      if (store === null || !Array.isArray(store.records)) {
        return;
      }
      for (const record of store.records) {
        if (record.key.length === 0 || record.value.length === 0 || record.savedAt <= 0) {
          continue;
        }
        if (record.lastAccessedAt === undefined || record.lastAccessedAt <= 0) {
          record.lastAccessedAt = record.savedAt;
        }
        this.records.set(record.key, record);
        if (record.savedAt > this.lastUpdated) {
          this.lastUpdated = record.savedAt;
        }
      }
      this.trimToLimit();
    } catch (error) {
      logger.warn(TAG, `读取反馈中心缓存失败，将忽略旧缓存: ${String(error)}`);
    }
  }

  private trimToLimit(): void {
    while (this.records.size > MAX_CACHE_ENTRIES || this.remoteCacheBytes() > MAX_CACHE_BYTES) {
      let oldestKey: string = '';
      let oldestTime: number = Number.MAX_SAFE_INTEGER;
      for (const record of this.records.values()) {
        if (this.recordAccessTime(record) < oldestTime) {
          oldestKey = record.key;
          oldestTime = this.recordAccessTime(record);
        }
      }
      if (oldestKey.length === 0) {
        break;
      }
      this.records.delete(oldestKey);
    }
  }

  private remoteCacheBytes(): number {
    let sizeBytes: number = 0;
    for (const record of this.records.values()) {
      sizeBytes += this.utf8Bytes(record.key);
      sizeBytes += this.utf8Bytes(record.value);
    }
    return sizeBytes;
  }

  private recordAccessTime(record: FeedbackCacheRecord): number {
    return record.lastAccessedAt === undefined ? record.savedAt : record.lastAccessedAt;
  }

  private utf8Bytes(value: string): number {
    return new util.TextEncoder().encodeInto(value).length;
  }

  private updateRemoteStats(): void {
    this.localStats = {
      entryCount: this.records.size,
      sizeBytes: this.remoteCacheBytes(),
      lastUpdated: this.lastUpdated,
      draftExists: this.localStats.draftExists,
      draftSizeBytes: this.localStats.draftSizeBytes,
      pendingAttachmentCount: this.localStats.pendingAttachmentCount,
      pendingAttachmentBytes: this.localStats.pendingAttachmentBytes
    };
  }

  private async persist(): Promise<void> {
    if (this.preferencesStore === null) {
      return;
    }
    const records: FeedbackCacheRecord[] = [];
    for (const record of this.records.values()) {
      records.push({
        key: record.key,
        value: record.value,
        savedAt: record.savedAt,
        lastAccessedAt: record.lastAccessedAt
      });
    }
    const store: FeedbackCacheStore = { records: records };
    await this.preferencesStore.put(CACHE_DATA_KEY, JSON.stringify(store));
    await this.preferencesStore.flush();
  }
}
