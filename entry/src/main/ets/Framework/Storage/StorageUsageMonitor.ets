import { ManagedStorageClearResult, ManagedStorageSnapshot } from './UnifiedStorageCoordinator';

export class StorageUsageTrendPoint {
  public timestamp: number = 0;
  public scannedTotalSizeBytes: number = 0;
  public reclaimableSizeBytes: number = 0;
  public dangerSizeBytes: number = 0;
  public protectedSizeBytes: number = 0;
  public memorySizeBytes: number = 0;
  public failedProviderCount: number = 0;
}

export class StorageOperationRecord {
  public timestamp: number = 0;
  public title: string = '';
  public success: boolean = true;
  public sizeBytes: number = 0;
  public detail: string = '';
}

export class StorageUsageMonitor {
  private static instance: StorageUsageMonitor | null = null;
  private lastSnapshot: ManagedStorageSnapshot | null = null;
  private history: StorageUsageTrendPoint[] = [];
  private operationRecords: StorageOperationRecord[] = [];
  private readonly maxHistoryCount: number = 12;
  private readonly maxRecordCount: number = 20;

  private constructor() {
  }

  static getInstance(): StorageUsageMonitor {
    if (!StorageUsageMonitor.instance) {
      StorageUsageMonitor.instance = new StorageUsageMonitor();
    }
    return StorageUsageMonitor.instance;
  }

  recordSnapshot(snapshot: ManagedStorageSnapshot): void {
    this.lastSnapshot = snapshot;
    const point = new StorageUsageTrendPoint();
    point.timestamp = snapshot.overview.updatedAt;
    point.scannedTotalSizeBytes = snapshot.overview.scannedTotalSizeBytes;
    point.reclaimableSizeBytes = snapshot.overview.reclaimableSizeBytes;
    point.dangerSizeBytes = snapshot.overview.dangerSizeBytes;
    point.protectedSizeBytes = snapshot.overview.protectedSizeBytes;
    point.memorySizeBytes = snapshot.overview.memorySizeBytes;
    point.failedProviderCount = snapshot.overview.failedProviderCount;
    this.history.push(point);
    this.trimHistory();
  }

  recordClearResult(result: ManagedStorageClearResult): void {
    const record = new StorageOperationRecord();
    record.timestamp = Date.now();
    record.title = '手动清理';
    record.success = result.success;
    record.sizeBytes = result.clearedSizeBytes;
    record.detail = result.success ? '清理完成' : `部分失败 ${result.errors.length} 项`;
    this.operationRecords.push(record);
    this.trimRecords();
  }

  getLastSnapshot(): ManagedStorageSnapshot | null {
    return this.lastSnapshot;
  }

  getHistory(): StorageUsageTrendPoint[] {
    const result: StorageUsageTrendPoint[] = [];
    for (let index = 0; index < this.history.length; index++) {
      const point = this.history[index];
      const clone = new StorageUsageTrendPoint();
      clone.timestamp = point.timestamp;
      clone.scannedTotalSizeBytes = point.scannedTotalSizeBytes;
      clone.reclaimableSizeBytes = point.reclaimableSizeBytes;
      clone.dangerSizeBytes = point.dangerSizeBytes;
      clone.protectedSizeBytes = point.protectedSizeBytes;
      clone.memorySizeBytes = point.memorySizeBytes;
      clone.failedProviderCount = point.failedProviderCount;
      result.push(clone);
    }
    return result;
  }

  getOperationRecords(): StorageOperationRecord[] {
    const result: StorageOperationRecord[] = [];
    for (let index = 0; index < this.operationRecords.length; index++) {
      const record = this.operationRecords[index];
      const clone = new StorageOperationRecord();
      clone.timestamp = record.timestamp;
      clone.title = record.title;
      clone.success = record.success;
      clone.sizeBytes = record.sizeBytes;
      clone.detail = record.detail;
      result.push(clone);
    }
    return result;
  }

  private trimHistory(): void {
    while (this.history.length > this.maxHistoryCount) {
      this.history.shift();
    }
  }

  private trimRecords(): void {
    while (this.operationRecords.length > this.maxRecordCount) {
      this.operationRecords.shift();
    }
  }
}
