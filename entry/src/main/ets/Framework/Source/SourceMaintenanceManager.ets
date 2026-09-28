import fs from '@ohos.file.fs';
import { common } from '@kit.AbilityKit';
import { http } from '@kit.NetworkKit';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { SafeFileUtils } from 'manxia_core/src/main/ets/Utils/SafeFileUtils';
import { SafeUtils } from 'manxia_core/src/main/ets/Utils/SafeUtils';
import { ComicSourceDatabaseRecord } from 'manxia_core/src/main/ets/Framework/Database/DatabaseTypes';
import { DataManager } from '../Data/DataManager';
import { ProxyManager } from 'manxia_network/src/main/ets/Framework/Network/ProxyManager';
import { SourceManager, ImportResult } from './SourceManager';
import { SourceRepositoryEntry, SourceRepositoryManager } from './SourceRepositoryManager';

const TAG = 'SourceMaintenanceManager';
const STORE_KEY = 'source:maintenance:v1';
const AGENT_KIT_VERSION = '0.1.0';
const DEFAULT_BRANCH = 'main';

export type SourceMaintenanceMode = 'upstream' | 'localFork' | 'userRepository' | 'officialPullRequest';
export type SourceMaintenanceSyncState = 'clean' | 'dirty' | 'remoteChanged' | 'conflicted' | 'unlinked';
export type SourceMaintenanceRepositoryProvider = 'github' | 'raw' | 'generic';
export type SourceMaintenanceRepositoryKind = 'private' | 'official';
export type SourceMaintenanceFileChangeState =
  'clean' |
  'modified' |
  'added' |
  'untracked' |
  'remoteChanged' |
  'conflicted' |
  'missing' |
  'unknown';

export interface SourceMaintenanceRepositoryBinding {
  repositoryUrl: string;
  branch: string;
  sourcePath: string;
  indexPath: string;
  provider: SourceMaintenanceRepositoryProvider;
}

export interface SourceMaintenanceRecord {
  pkg: string;
  sourceId: number;
  sourceName: string;
  sourceVersion: string;
  mode: SourceMaintenanceMode;
  syncState: SourceMaintenanceSyncState;
  originRepositoryUrl: string;
  officialRepositoryUrl: string;
  baseHash: string;
  localHash: string;
  remoteHash: string;
  lastLocalEditTime: number;
  lastPullTime: number;
  lastExportTime: number;
  exportPath: string;
  pullRequestUrl: string;
  userRepository?: SourceMaintenanceRepositoryBinding;
  changeState?: SourceMaintenanceFileChangeState;
  officialLastSeenHash?: string;
  officialLastSeenVersion?: string;
  officialLastSeenCode?: number;
  privateLastSeenHash?: string;
  privateLastSeenVersion?: string;
  lastTrackingRefreshTime?: number;
  notes: string;
}

export interface SourceMaintenanceStore {
  version: number;
  records: SourceMaintenanceRecord[];
}

export interface SourceMaintenanceBadge {
  mode: SourceMaintenanceMode;
  syncState: SourceMaintenanceSyncState;
  modeLabel: string;
  syncLabel: string;
  description: string;
  needsAttention: boolean;
}

export interface SourceMaintenanceExportResult {
  success: boolean;
  message: string;
  exportDir: string;
  sourcePath: string;
  manifestPath: string;
  guidePath: string;
}

export interface SourceMaintenancePullResult {
  success: boolean;
  message: string;
  sourceId: number;
  sourceName: string;
  remoteHash: string;
}

export interface SourceMaintenancePageParams {
  sourceId: number;
  sourcePkg: string;
  sourceName: string;
}

export interface SourceMaintenanceRepositoryTracking {
  kind: SourceMaintenanceRepositoryKind;
  title: string;
  isBound: boolean;
  isTracked: boolean;
  repositoryUrl: string;
  branch: string;
  sourcePath: string;
  localHash: string;
  remoteHash: string;
  baseHash: string;
  localVersion: string;
  remoteVersion: string;
  remoteCode: number;
  state: SourceMaintenanceFileChangeState;
  stateLabel: string;
  description: string;
  lastSyncTime: number;
  lastError: string;
  canPull: boolean;
}

export interface SourceMaintenanceTrackingSnapshot {
  pkg: string;
  sourceId: number;
  sourceName: string;
  localHash: string;
  localVersion: string;
  fileState: SourceMaintenanceFileChangeState;
  fileStateLabel: string;
  changeSummary: string;
  badge: SourceMaintenanceBadge;
  privateRepository: SourceMaintenanceRepositoryTracking;
  officialRepository: SourceMaintenanceRepositoryTracking;
  exportPath: string;
  pullRequestUrl: string;
}

interface SourceMaintenanceConfigMetadata {
  id?: string;
  name?: string;
  version?: string;
  baseUrl?: string;
}

interface SourceMaintenanceConfigSummary {
  metadata?: SourceMaintenanceConfigMetadata;
}

interface SourceMaintenanceBundleSourceInfo {
  pkg: string;
  name: string;
  version: string;
  sourceId: number;
  hash: string;
}

interface SourceMaintenanceBundleFile {
  path: string;
  role: string;
}

interface SourceMaintenanceBundleManifest {
  schemaVersion: string;
  agentKitVersion: string;
  exportedAt: number;
  source: SourceMaintenanceBundleSourceInfo;
  maintenance: SourceMaintenanceRecord;
  tracking: SourceMaintenanceTrackingSnapshot;
  files: SourceMaintenanceBundleFile[];
}

export class SourceMaintenanceManager {
  private static instance: SourceMaintenanceManager | null = null;
  private readonly dataManager: DataManager = DataManager.getInstance();
  private readonly sourceManager: SourceManager = SourceManager.getInstance();
  private readonly sourceRepositoryManager: SourceRepositoryManager = SourceRepositoryManager.getInstance();
  private readonly proxyManager: ProxyManager = ProxyManager.getInstance();
  private abilityContext: common.UIAbilityContext | null = null;

  private constructor() {}

  public static getInstance(): SourceMaintenanceManager {
    if (!SourceMaintenanceManager.instance) {
      SourceMaintenanceManager.instance = new SourceMaintenanceManager();
    }
    return SourceMaintenanceManager.instance;
  }

  public setAbilityContext(context: common.UIAbilityContext | null): void {
    this.abilityContext = context;
  }

  public async listRecords(): Promise<SourceMaintenanceRecord[]> {
    const store: SourceMaintenanceStore = await this.readStore();
    return store.records;
  }

  public findRecord(records: SourceMaintenanceRecord[], pkg: string): SourceMaintenanceRecord | null {
    for (let index = 0; index < records.length; index++) {
      if (records[index].pkg === pkg) {
        return records[index];
      }
    }
    return null;
  }

  public buildBadge(record: SourceMaintenanceRecord | null): SourceMaintenanceBadge {
    if (!record) {
      const badge: SourceMaintenanceBadge = {
        mode: 'localFork',
        syncState: 'unlinked',
        modeLabel: '未追踪',
        syncLabel: '未建立基线',
        description: '尚未和漫匣仓库或私有仓库建立可验证的文件基线。',
        needsAttention: true
      };
      return badge;
    }

    const badge: SourceMaintenanceBadge = {
      mode: record.mode,
      syncState: record.syncState,
      modeLabel: this.getModeLabel(record.mode),
      syncLabel: this.getSyncStateLabel(record.syncState),
      description: this.getBadgeDescription(record),
      needsAttention: record.syncState === 'dirty' || record.syncState === 'conflicted' || record.syncState === 'unlinked'
    };
    return badge;
  }

  public async getRecord(pkg: string): Promise<SourceMaintenanceRecord | null> {
    const records: SourceMaintenanceRecord[] = await this.listRecords();
    return this.findRecord(records, pkg);
  }

  public createEmptyTrackingSnapshot(): SourceMaintenanceTrackingSnapshot {
    return this.buildEmptyTrackingSnapshot('', 0, '');
  }

  public async getBadgeForSource(pkg: string): Promise<SourceMaintenanceBadge> {
    if (pkg.trim().length <= 0) {
      return this.buildBadge(null);
    }
    const snapshot: SourceMaintenanceTrackingSnapshot = await this.getTrackingSnapshot(pkg, false);
    return snapshot.badge;
  }

  public async getTrackingSnapshot(pkg: string, refreshPrivateRepository: boolean = true): Promise<SourceMaintenanceTrackingSnapshot> {
    const sourceRecord: ComicSourceDatabaseRecord | null = await this.dataManager.getComicSourceByPkg(pkg);
    const storedRecord: SourceMaintenanceRecord | null = await this.getRecord(pkg);
    const sourceId: number = sourceRecord ? this.parseSourceId(sourceRecord.id) : (storedRecord ? storedRecord.sourceId : 0);
    const sourceName: string = sourceRecord ? (sourceRecord.name || pkg) : (storedRecord ? storedRecord.sourceName : pkg);
    const configJson: string = sourceRecord ? (sourceRecord.configJson || '') : '';
    const localHash: string = configJson.length > 0 ? this.computeHash(configJson) : '';
    const localVersion: string = this.resolveVersion(configJson, storedRecord ? storedRecord.sourceVersion : '');

    const officialTracking: SourceMaintenanceRepositoryTracking = await this.buildOfficialRepositoryTracking(
      pkg,
      localHash,
      localVersion,
      storedRecord
    );
    const privateTracking: SourceMaintenanceRepositoryTracking = await this.buildPrivateRepositoryTracking(
      pkg,
      localHash,
      localVersion,
      storedRecord,
      refreshPrivateRepository
    );

    const fileState: SourceMaintenanceFileChangeState = this.resolveOverallFileState(privateTracking, officialTracking);
    const badge: SourceMaintenanceBadge = this.buildBadgeFromTracking(storedRecord, privateTracking, officialTracking, fileState);
    const snapshot: SourceMaintenanceTrackingSnapshot = {
      pkg: pkg,
      sourceId: sourceId,
      sourceName: sourceName,
      localHash: localHash,
      localVersion: localVersion,
      fileState: fileState,
      fileStateLabel: this.getFileStateLabel(fileState),
      changeSummary: this.buildChangeSummary(privateTracking, officialTracking, fileState),
      badge: badge,
      privateRepository: privateTracking,
      officialRepository: officialTracking,
      exportPath: storedRecord ? storedRecord.exportPath : '',
      pullRequestUrl: storedRecord ? storedRecord.pullRequestUrl : ''
    };

    await this.persistSnapshotIfNeeded(snapshot, storedRecord, configJson);
    return snapshot;
  }

  public async markLocalFork(
    sourceId: number,
    pkg: string,
    sourceName: string,
    sourceVersion: string,
    configJson: string,
    notes: string
  ): Promise<void> {
    const localHash: string = this.computeHash(configJson);
    const record: SourceMaintenanceRecord = await this.getOrCreateRecord(sourceId, pkg, sourceName, sourceVersion, configJson);
    record.sourceId = sourceId;
    record.sourceName = sourceName;
    record.sourceVersion = sourceVersion;
    record.mode = 'localFork';
    record.syncState = 'dirty';
    record.localHash = localHash;
    const officialJson: string = await this.sourceRepositoryManager.readSourceJsonFromRepository(pkg);
    if (officialJson.trim().length > 0) {
      record.baseHash = this.computeHash(officialJson);
      record.officialLastSeenHash = record.baseHash;
      record.officialLastSeenVersion = this.resolveVersion(officialJson, '');
    } else if (record.baseHash.length <= 0) {
      record.baseHash = '';
    }
    record.changeState = 'modified';
    record.lastLocalEditTime = Date.now();
    record.notes = notes;
    await this.upsertRecord(record);
    logger.info(TAG, `已标记本地维护图源: pkg=${pkg}, sourceId=${sourceId}`);
  }

  public async bindUserRepository(
    pkg: string,
    sourceName: string,
    repositoryUrl: string,
    branch: string,
    sourcePath: string
  ): Promise<SourceMaintenanceRecord> {
    const record: SourceMaintenanceRecord = await this.getOrCreateRecordByPkg(pkg, sourceName);
    const normalizedBranch: string = branch.trim().length > 0 ? branch.trim() : DEFAULT_BRANCH;
    const normalizedSourcePath: string = sourcePath.trim().length > 0 ? sourcePath.trim() : `${pkg}/source.json`;
    const binding: SourceMaintenanceRepositoryBinding = {
      repositoryUrl: repositoryUrl.trim(),
      branch: normalizedBranch,
      sourcePath: normalizedSourcePath,
      indexPath: 'index.main.json',
      provider: this.detectProvider(repositoryUrl.trim())
    };
    record.userRepository = binding;
    record.mode = 'userRepository';
    record.syncState = record.localHash.length > 0 && record.baseHash.length > 0 && record.localHash !== record.baseHash ? 'dirty' : 'unlinked';
    record.changeState = record.syncState === 'dirty' ? 'modified' : 'untracked';
    record.sourceName = sourceName;
    await this.upsertRecord(record);
    logger.info(TAG, `已绑定图源用户仓库: pkg=${pkg}, repo=${binding.repositoryUrl}, path=${binding.sourcePath}`);
    return record;
  }

  public async markOfficialPullRequest(pkg: string, sourceName: string, pullRequestUrl: string): Promise<SourceMaintenanceRecord> {
    const record: SourceMaintenanceRecord = await this.getOrCreateRecordByPkg(pkg, sourceName);
    record.mode = 'officialPullRequest';
    record.pullRequestUrl = pullRequestUrl.trim();
    record.syncState = record.pullRequestUrl.length > 0 ? 'clean' : record.syncState;
    await this.upsertRecord(record);
    logger.info(TAG, `已标记官方 PR 候选: pkg=${pkg}, pr=${record.pullRequestUrl}`);
    return record;
  }

  public async exportMaintenanceBundle(pkg: string): Promise<SourceMaintenanceExportResult> {
    if (!this.abilityContext) {
      return this.buildExportFailure('无法获取应用目录，暂不能导出维护包');
    }

    const sourceRecord: ComicSourceDatabaseRecord | null = await this.dataManager.getComicSourceByPkg(pkg);
    if (!sourceRecord) {
      return this.buildExportFailure(`未找到图源: ${pkg}`);
    }

    const sourceId: number = this.parseSourceId(sourceRecord.id);
    const configJson: string = sourceRecord.configJson || '';
    const sourceName: string = sourceRecord.name || pkg;
    const sourceVersion: string = this.resolveVersion(configJson, '');
    const sourceHash: string = this.computeHash(configJson);
    const record: SourceMaintenanceRecord = await this.getOrCreateRecord(sourceId, pkg, sourceName, sourceVersion, configJson);
    const exportDir: string = `${this.abilityContext.filesDir}/source_maintenance/${this.sanitizeFileName(pkg)}_${Date.now()}`;
    const sourcePath: string = `${exportDir}/source.json`;
    const manifestPath: string = `${exportDir}/maintenance.manifest.json`;
    const guidePath: string = `${exportDir}/AGENT_GUIDE.md`;

    record.sourceId = sourceId;
    record.sourceName = sourceName;
    record.sourceVersion = sourceVersion;
    record.localHash = sourceHash;
    record.lastExportTime = Date.now();
    record.exportPath = exportDir;
    if (record.mode === 'upstream') {
      record.mode = 'localFork';
    }
    if (record.baseHash.length <= 0) {
      const officialJson: string = await this.sourceRepositoryManager.readSourceJsonFromRepository(pkg);
      record.baseHash = officialJson.trim().length > 0 ? this.computeHash(officialJson) : sourceHash;
    }
    await this.upsertRecord(record);

    const trackingSnapshot: SourceMaintenanceTrackingSnapshot = await this.getTrackingSnapshot(pkg, false);
    const manifest: SourceMaintenanceBundleManifest = this.buildBundleManifest(record, sourceHash, trackingSnapshot);
    const guideText: string = this.buildAgentGuide(record);
    let sourceFile: fs.File | null = null;
    let manifestFile: fs.File | null = null;
    let guideFile: fs.File | null = null;
    try {
      SafeFileUtils.mkdirSyncStrict(exportDir, true);
      sourceFile = SafeFileUtils.openSyncStrict(sourcePath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      SafeFileUtils.writeStringExactSync(sourceFile.fd, configJson);
      manifestFile = SafeFileUtils.openSyncStrict(manifestPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      SafeFileUtils.writeStringExactSync(manifestFile.fd, JSON.stringify(manifest, null, 2));
      guideFile = SafeFileUtils.openSyncStrict(guidePath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      SafeFileUtils.writeStringExactSync(guideFile.fd, guideText);
      logger.info(TAG, `维护包已导出: ${exportDir}`);
      const result: SourceMaintenanceExportResult = {
        success: true,
        message: '已导出维护包，可交给 AgentKit 同步到仓库或生成 PR',
        exportDir: exportDir,
        sourcePath: sourcePath,
        manifestPath: manifestPath,
        guidePath: guidePath
      };
      return result;
    } catch (error) {
      logger.error(TAG, `导出维护包失败: ${String(error)}`);
      return this.buildExportFailure(`导出失败: ${String(error)}`);
    } finally {
      if (sourceFile) {
        SafeFileUtils.closeSync(sourceFile);
      }
      if (manifestFile) {
        SafeFileUtils.closeSync(manifestFile);
      }
      if (guideFile) {
        SafeFileUtils.closeSync(guideFile);
      }
    }
  }

  public async pullFromUserRepository(pkg: string): Promise<SourceMaintenancePullResult> {
    const record: SourceMaintenanceRecord | null = await this.getRecord(pkg);
    if (!record || !record.userRepository) {
      return this.buildPullFailure('请先绑定用户仓库', 0, '', '');
    }

    const rawUrl: string = this.resolveRawSourceUrl(record.userRepository);
    if (rawUrl.length <= 0) {
      return this.buildPullFailure('无法解析远端 source.json 地址', record.sourceId, record.sourceName, '');
    }

    try {
      const remoteJson: string = await this.fetchText(rawUrl);
      if (remoteJson.trim().length <= 0) {
        return this.buildPullFailure('远端 source.json 内容为空', record.sourceId, record.sourceName, '');
      }
      const remotePkg: string = this.resolvePkg(remoteJson, '');
      if (remotePkg !== pkg) {
        return this.buildPullFailure(`远端图源 pkg 不匹配: ${remotePkg}`, record.sourceId, record.sourceName, '');
      }
      const remoteHash: string = this.computeHash(remoteJson);
      const currentRecord: ComicSourceDatabaseRecord | null = await this.dataManager.getComicSourceByPkg(pkg);
      let importResult: ImportResult;
      if (currentRecord) {
        importResult = await this.sourceManager.updateSourceFromJSON(remoteJson, this.parseSourceId(currentRecord.id));
      } else {
        importResult = await this.sourceManager.importFromJSON(remoteJson);
      }
      if (!importResult.success) {
        return this.buildPullFailure(importResult.error || '远端图源导入失败', record.sourceId, record.sourceName, remoteHash);
      }

      const resolvedName: string = importResult.sourceName || this.resolveName(remoteJson, record.sourceName);
      const resolvedId: number = importResult.sourceId || record.sourceId;
      record.sourceId = resolvedId;
      record.sourceName = resolvedName;
      record.sourceVersion = this.resolveVersion(remoteJson, record.sourceVersion);
      record.remoteHash = remoteHash;
      record.localHash = remoteHash;
      record.baseHash = remoteHash;
      record.privateLastSeenHash = remoteHash;
      record.privateLastSeenVersion = record.sourceVersion;
      record.changeState = 'clean';
      record.syncState = 'clean';
      record.mode = 'userRepository';
      record.lastPullTime = Date.now();
      await this.upsertRecord(record);
      logger.info(TAG, `已从用户仓库拉取图源: pkg=${pkg}, url=${rawUrl}`);

      const result: SourceMaintenancePullResult = {
        success: true,
        message: '已从用户仓库拉取并更新图源',
        sourceId: resolvedId,
        sourceName: resolvedName,
        remoteHash: remoteHash
      };
      return result;
    } catch (error) {
      logger.error(TAG, `从用户仓库拉取失败: pkg=${pkg}`, String(error));
      return this.buildPullFailure(`拉取失败: ${String(error)}`, record.sourceId, record.sourceName, '');
    }
  }

  public async pullFromOfficialRepository(pkg: string): Promise<SourceMaintenancePullResult> {
    const sourceRecord: ComicSourceDatabaseRecord | null = await this.dataManager.getComicSourceByPkg(pkg);
    const storedRecord: SourceMaintenanceRecord | null = await this.getRecord(pkg);
    const sourceId: number = sourceRecord ? this.parseSourceId(sourceRecord.id) : (storedRecord ? storedRecord.sourceId : 0);
    const sourceName: string = sourceRecord ? (sourceRecord.name || pkg) : (storedRecord ? storedRecord.sourceName : pkg);
    try {
      const remoteJson: string = await this.sourceRepositoryManager.readSourceJsonFromRepository(pkg);
      if (remoteJson.trim().length <= 0) {
        return this.buildPullFailure('漫匣仓库中未找到该图源，请先同步官方图源仓库', sourceId, sourceName, '');
      }
      const remotePkg: string = this.resolvePkg(remoteJson, '');
      if (remotePkg !== pkg) {
        return this.buildPullFailure(`漫匣仓库图源 pkg 不匹配: ${remotePkg}`, sourceId, sourceName, '');
      }

      const remoteHash: string = this.computeHash(remoteJson);
      let importResult: ImportResult;
      if (sourceRecord) {
        importResult = await this.sourceManager.updateSourceFromJSON(remoteJson, sourceId);
      } else {
        importResult = await this.sourceManager.importFromJSON(remoteJson);
      }
      if (!importResult.success) {
        return this.buildPullFailure(importResult.error || '漫匣仓库图源导入失败', sourceId, sourceName, remoteHash);
      }

      const resolvedName: string = importResult.sourceName || this.resolveName(remoteJson, sourceName);
      const resolvedId: number = importResult.sourceId || sourceId;
      const record: SourceMaintenanceRecord = storedRecord ?
        storedRecord :
        await this.getOrCreateRecord(resolvedId, pkg, resolvedName, this.resolveVersion(remoteJson, ''), remoteJson);
      record.sourceId = resolvedId;
      record.sourceName = resolvedName;
      record.sourceVersion = this.resolveVersion(remoteJson, record.sourceVersion);
      record.mode = 'upstream';
      record.syncState = 'clean';
      record.changeState = 'clean';
      record.baseHash = remoteHash;
      record.localHash = remoteHash;
      record.officialLastSeenHash = remoteHash;
      record.officialLastSeenVersion = record.sourceVersion;
      record.lastPullTime = Date.now();
      await this.upsertRecord(record);
      logger.info(TAG, `已从漫匣仓库拉取图源: pkg=${pkg}`);

      const result: SourceMaintenancePullResult = {
        success: true,
        message: '已从漫匣仓库拉取并更新图源',
        sourceId: resolvedId,
        sourceName: resolvedName,
        remoteHash: remoteHash
      };
      return result;
    } catch (error) {
      logger.error(TAG, `从漫匣仓库拉取失败: pkg=${pkg}`, String(error));
      return this.buildPullFailure(`拉取失败: ${String(error)}`, sourceId, sourceName, '');
    }
  }

  private async getOrCreateRecordByPkg(pkg: string, sourceName: string): Promise<SourceMaintenanceRecord> {
    const sourceRecord: ComicSourceDatabaseRecord | null = await this.dataManager.getComicSourceByPkg(pkg);
    if (sourceRecord) {
      return await this.getOrCreateRecord(
        this.parseSourceId(sourceRecord.id),
        pkg,
        sourceRecord.name || sourceName,
        this.resolveVersion(sourceRecord.configJson || '', ''),
        sourceRecord.configJson || ''
      );
    }
    return await this.getOrCreateRecord(0, pkg, sourceName, '', '');
  }

  private async getOrCreateRecord(
    sourceId: number,
    pkg: string,
    sourceName: string,
    sourceVersion: string,
    configJson: string
  ): Promise<SourceMaintenanceRecord> {
    const existing: SourceMaintenanceRecord | null = await this.getRecord(pkg);
    if (existing) {
      return existing;
    }
    const hash: string = configJson.length > 0 ? this.computeHash(configJson) : '';
    const record: SourceMaintenanceRecord = {
      pkg: pkg,
      sourceId: sourceId,
      sourceName: sourceName,
      sourceVersion: sourceVersion,
      mode: 'upstream',
      syncState: 'unlinked',
      originRepositoryUrl: '',
      officialRepositoryUrl: 'https://github.com/manxia-app/manxia-extensions-source',
      baseHash: '',
      localHash: hash,
      remoteHash: '',
      lastLocalEditTime: 0,
      lastPullTime: 0,
      lastExportTime: 0,
      exportPath: '',
      pullRequestUrl: '',
      notes: ''
    };
    return record;
  }

  private async readStore(): Promise<SourceMaintenanceStore> {
    const emptyStore: SourceMaintenanceStore = {
      version: 1,
      records: []
    };
    try {
      const setting = await this.dataManager.getSetting(STORE_KEY);
      if (!setting || !setting.settingValue || setting.settingValue.trim().length <= 0) {
        return emptyStore;
      }
      const parsed: SourceMaintenanceStore = SafeUtils.parseObj<SourceMaintenanceStore>(setting.settingValue);
      if (!parsed.records || !Array.isArray(parsed.records)) {
        return emptyStore;
      }
      return parsed;
    } catch (error) {
      logger.error(TAG, '读取维护记录失败', String(error));
      return emptyStore;
    }
  }

  private async writeStore(store: SourceMaintenanceStore): Promise<void> {
    await this.dataManager.saveSetting(STORE_KEY, JSON.stringify(store), 'json');
  }

  private async upsertRecord(record: SourceMaintenanceRecord): Promise<void> {
    const store: SourceMaintenanceStore = await this.readStore();
    let replaced: boolean = false;
    for (let index = 0; index < store.records.length; index++) {
      if (store.records[index].pkg === record.pkg) {
        store.records[index] = record;
        replaced = true;
        break;
      }
    }
    if (!replaced) {
      store.records.push(record);
    }
    await this.writeStore(store);
  }

  private async buildOfficialRepositoryTracking(
    pkg: string,
    localHash: string,
    localVersion: string,
    record: SourceMaintenanceRecord | null
  ): Promise<SourceMaintenanceRepositoryTracking> {
    const storedOfficialRepositoryUrl: string = record ? (record.officialRepositoryUrl || '') : '';
    const repositoryUrl: string = storedOfficialRepositoryUrl.length > 0 ?
      storedOfficialRepositoryUrl :
      'https://github.com/manxia-app/manxia-extensions-source';
    let remoteJson: string = '';
    let remoteHash: string = '';
    let remoteVersion: string = '';
    let remoteCode: number = 0;
    let isTracked: boolean = false;
    let lastError: string = '';
    try {
      const entry: SourceRepositoryEntry | null = await this.sourceRepositoryManager.findRepositoryEntry(pkg);
      if (entry) {
        remoteVersion = entry.version;
        remoteCode = entry.code;
        isTracked = true;
      }
      remoteJson = await this.sourceRepositoryManager.readSourceJsonFromRepository(pkg);
      if (remoteJson.trim().length > 0) {
        remoteHash = this.computeHash(remoteJson);
        const versionFromJson: string = this.resolveVersion(remoteJson, remoteVersion);
        remoteVersion = versionFromJson;
        isTracked = true;
      }
    } catch (error) {
      lastError = String(error);
    }

    const baseHash: string = record && record.baseHash.length > 0 ? record.baseHash : '';
    const state: SourceMaintenanceFileChangeState = this.compareFileState(localHash, remoteHash, baseHash, isTracked);
    const tracking: SourceMaintenanceRepositoryTracking = {
      kind: 'official',
      title: '漫匣图源仓库',
      isBound: true,
      isTracked: isTracked,
      repositoryUrl: repositoryUrl,
      branch: DEFAULT_BRANCH,
      sourcePath: `${pkg}/source.json`,
      localHash: localHash,
      remoteHash: remoteHash,
      baseHash: baseHash,
      localVersion: localVersion,
      remoteVersion: remoteVersion,
      remoteCode: remoteCode,
      state: state,
      stateLabel: this.getFileStateLabel(state),
      description: this.buildRepositoryDescription('official', state, isTracked, lastError),
      lastSyncTime: 0,
      lastError: lastError,
      canPull: isTracked && localHash !== remoteHash && remoteHash.length > 0
    };
    return tracking;
  }

  private async buildPrivateRepositoryTracking(
    pkg: string,
    localHash: string,
    localVersion: string,
    record: SourceMaintenanceRecord | null,
    refreshRemote: boolean
  ): Promise<SourceMaintenanceRepositoryTracking> {
    if (!record || !record.userRepository) {
      const unboundTracking: SourceMaintenanceRepositoryTracking = {
        kind: 'private',
        title: '私有图源仓库',
        isBound: false,
        isTracked: false,
        repositoryUrl: '',
        branch: DEFAULT_BRANCH,
        sourcePath: `${pkg}/source.json`,
        localHash: localHash,
        remoteHash: '',
        baseHash: '',
        localVersion: localVersion,
        remoteVersion: '',
        remoteCode: 0,
        state: 'untracked',
        stateLabel: this.getFileStateLabel('untracked'),
        description: '尚未绑定私有图源仓库。',
        lastSyncTime: 0,
        lastError: '',
        canPull: false
      };
      return unboundTracking;
    }

    let remoteHash: string = '';
    if (record.privateLastSeenHash && record.privateLastSeenHash.length > 0) {
      remoteHash = record.privateLastSeenHash;
    } else if (record.remoteHash && record.remoteHash.length > 0) {
      remoteHash = record.remoteHash;
    }
    let remoteVersion: string = '';
    if (record.privateLastSeenVersion && record.privateLastSeenVersion.length > 0) {
      remoteVersion = record.privateLastSeenVersion;
    }
    let lastError: string = '';
    let isTracked: boolean = remoteHash.length > 0;
    if (refreshRemote) {
      const rawUrl: string = this.resolveRawSourceUrl(record.userRepository);
      if (rawUrl.length <= 0) {
        lastError = '无法解析私有仓库 source.json 地址';
      } else {
        try {
          const remoteJson: string = await this.fetchText(rawUrl);
          const remotePkg: string = this.resolvePkg(remoteJson, '');
          if (remotePkg !== pkg) {
            lastError = `私有仓库图源 pkg 不匹配: ${remotePkg}`;
          } else {
            remoteHash = this.computeHash(remoteJson);
            remoteVersion = this.resolveVersion(remoteJson, remoteVersion);
            isTracked = true;
          }
        } catch (error) {
          lastError = String(error);
        }
      }
    }

    const baseHash: string = record.baseHash.length > 0 ? record.baseHash : '';
    const state: SourceMaintenanceFileChangeState = this.compareFileState(localHash, remoteHash, baseHash, isTracked);
    const tracking: SourceMaintenanceRepositoryTracking = {
      kind: 'private',
      title: '私有图源仓库',
      isBound: true,
      isTracked: isTracked,
      repositoryUrl: record.userRepository.repositoryUrl,
      branch: record.userRepository.branch,
      sourcePath: record.userRepository.sourcePath,
      localHash: localHash,
      remoteHash: remoteHash,
      baseHash: baseHash,
      localVersion: localVersion,
      remoteVersion: remoteVersion,
      remoteCode: 0,
      state: lastError.length > 0 && !isTracked ? 'unknown' : state,
      stateLabel: this.getFileStateLabel(lastError.length > 0 && !isTracked ? 'unknown' : state),
      description: this.buildRepositoryDescription('private', lastError.length > 0 && !isTracked ? 'unknown' : state, isTracked, lastError),
      lastSyncTime: record.lastPullTime,
      lastError: lastError,
      canPull: isTracked && remoteHash.length > 0 && localHash !== remoteHash
    };
    return tracking;
  }

  private compareFileState(
    localHash: string,
    remoteHash: string,
    baseHash: string,
    remoteTracked: boolean
  ): SourceMaintenanceFileChangeState {
    if (localHash.length <= 0) {
      return 'missing';
    }
    if (!remoteTracked || remoteHash.length <= 0) {
      return 'untracked';
    }
    if (localHash === remoteHash) {
      return 'clean';
    }
    if (baseHash.length > 0) {
      if (localHash === baseHash && remoteHash !== baseHash) {
        return 'remoteChanged';
      }
      if (remoteHash === baseHash && localHash !== baseHash) {
        return 'modified';
      }
      if (localHash !== baseHash && remoteHash !== baseHash) {
        return 'conflicted';
      }
    }
    return 'modified';
  }

  private resolveOverallFileState(
    privateTracking: SourceMaintenanceRepositoryTracking,
    officialTracking: SourceMaintenanceRepositoryTracking
  ): SourceMaintenanceFileChangeState {
    if (privateTracking.isBound) {
      return privateTracking.state;
    }
    return officialTracking.state;
  }

  private buildBadgeFromTracking(
    record: SourceMaintenanceRecord | null,
    privateTracking: SourceMaintenanceRepositoryTracking,
    officialTracking: SourceMaintenanceRepositoryTracking,
    fileState: SourceMaintenanceFileChangeState
  ): SourceMaintenanceBadge {
    let mode: SourceMaintenanceMode = 'localFork';
    if (privateTracking.isBound) {
      mode = 'userRepository';
    } else if (officialTracking.state === 'clean' || officialTracking.state === 'remoteChanged') {
      mode = 'upstream';
    }
    if (!privateTracking.isBound && record && record.mode === 'officialPullRequest') {
      mode = 'officialPullRequest';
    }

    const syncState: SourceMaintenanceSyncState = this.toSyncState(fileState);
    const badge: SourceMaintenanceBadge = {
      mode: mode,
      syncState: syncState,
      modeLabel: this.getModeLabelForState(mode, fileState),
      syncLabel: this.getSyncStateLabel(syncState),
      description: this.buildBadgeTrackingDescription(mode, privateTracking, officialTracking, fileState),
      needsAttention: syncState !== 'clean'
    };
    return badge;
  }

  private toSyncState(fileState: SourceMaintenanceFileChangeState): SourceMaintenanceSyncState {
    if (fileState === 'clean') {
      return 'clean';
    }
    if (fileState === 'remoteChanged') {
      return 'remoteChanged';
    }
    if (fileState === 'conflicted') {
      return 'conflicted';
    }
    if (fileState === 'untracked' || fileState === 'missing' || fileState === 'unknown') {
      return 'unlinked';
    }
    return 'dirty';
  }

  private getModeLabelForState(mode: SourceMaintenanceMode, fileState: SourceMaintenanceFileChangeState): string {
    if (fileState === 'untracked') {
      return '本地导入';
    }
    return this.getModeLabel(mode);
  }

  private buildBadgeTrackingDescription(
    mode: SourceMaintenanceMode,
    privateTracking: SourceMaintenanceRepositoryTracking,
    officialTracking: SourceMaintenanceRepositoryTracking,
    fileState: SourceMaintenanceFileChangeState
  ): string {
    if (privateTracking.isBound) {
      return privateTracking.description;
    }
    if (mode === 'officialPullRequest') {
      return '已记录向漫匣仓库提交的 PR，可继续追踪官方仓库状态。';
    }
    if (fileState === 'clean') {
      return '本地图源与已同步的漫匣仓库文件一致。';
    }
    return officialTracking.description;
  }

  private buildChangeSummary(
    privateTracking: SourceMaintenanceRepositoryTracking,
    officialTracking: SourceMaintenanceRepositoryTracking,
    fileState: SourceMaintenanceFileChangeState
  ): string {
    if (privateTracking.isBound) {
      return privateTracking.description;
    }
    if (fileState === 'clean') {
      return '当前文件没有相对漫匣仓库的变更。';
    }
    return officialTracking.description;
  }

  private buildRepositoryDescription(
    kind: SourceMaintenanceRepositoryKind,
    state: SourceMaintenanceFileChangeState,
    isTracked: boolean,
    lastError: string
  ): string {
    if (lastError.length > 0) {
      return lastError;
    }
    if (!isTracked) {
      return kind === 'private' ? '私有仓库尚未发现该 source.json。' : '当前同步的漫匣仓库中未发现该图源。';
    }
    if (state === 'clean') {
      return '本地文件与仓库文件一致。';
    }
    if (state === 'modified') {
      return '本地文件相对仓库基线已有修改。';
    }
    if (state === 'remoteChanged') {
      return '仓库文件已有更新，本地仍停留在旧基线。';
    }
    if (state === 'conflicted') {
      return '本地和仓库都偏离了共同基线，需要合并。';
    }
    if (state === 'missing') {
      return '本地图源记录缺失，无法比较。';
    }
    if (state === 'unknown') {
      return '仓库状态暂时无法确认。';
    }
    return '该图源尚未被此仓库追踪。';
  }

  private async persistSnapshotIfNeeded(
    snapshot: SourceMaintenanceTrackingSnapshot,
    record: SourceMaintenanceRecord | null,
    configJson: string
  ): Promise<void> {
    if (snapshot.pkg.length <= 0 || snapshot.localHash.length <= 0) {
      return;
    }
    if (!record && snapshot.fileState === 'clean') {
      return;
    }
    const nextRecord: SourceMaintenanceRecord = record ?
      record :
      await this.getOrCreateRecord(snapshot.sourceId, snapshot.pkg, snapshot.sourceName, snapshot.localVersion, configJson);
    nextRecord.sourceId = snapshot.sourceId;
    nextRecord.sourceName = snapshot.sourceName;
    nextRecord.sourceVersion = snapshot.localVersion;
    nextRecord.localHash = snapshot.localHash;
    nextRecord.changeState = snapshot.fileState;
    nextRecord.syncState = snapshot.badge.syncState;
    nextRecord.mode = snapshot.badge.mode;
    nextRecord.lastTrackingRefreshTime = Date.now();
    if (snapshot.officialRepository.remoteHash.length > 0) {
      nextRecord.officialLastSeenHash = snapshot.officialRepository.remoteHash;
      nextRecord.officialLastSeenVersion = snapshot.officialRepository.remoteVersion;
      nextRecord.officialLastSeenCode = snapshot.officialRepository.remoteCode;
      if (nextRecord.baseHash.length <= 0 && snapshot.officialRepository.state !== 'untracked') {
        nextRecord.baseHash = snapshot.officialRepository.remoteHash;
      }
    }
    if (snapshot.privateRepository.remoteHash.length > 0) {
      nextRecord.remoteHash = snapshot.privateRepository.remoteHash;
      nextRecord.privateLastSeenHash = snapshot.privateRepository.remoteHash;
      nextRecord.privateLastSeenVersion = snapshot.privateRepository.remoteVersion;
    }
    await this.upsertRecord(nextRecord);
  }

  private buildEmptyRepositoryTracking(kind: SourceMaintenanceRepositoryKind): SourceMaintenanceRepositoryTracking {
    const title: string = kind === 'private' ? '私有图源仓库' : '漫匣图源仓库';
    const tracking: SourceMaintenanceRepositoryTracking = {
      kind: kind,
      title: title,
      isBound: kind === 'official',
      isTracked: false,
      repositoryUrl: kind === 'official' ? 'https://github.com/manxia-app/manxia-extensions-source' : '',
      branch: DEFAULT_BRANCH,
      sourcePath: '',
      localHash: '',
      remoteHash: '',
      baseHash: '',
      localVersion: '',
      remoteVersion: '',
      remoteCode: 0,
      state: 'unknown',
      stateLabel: this.getFileStateLabel('unknown'),
      description: '尚未加载图源维护状态。',
      lastSyncTime: 0,
      lastError: '',
      canPull: false
    };
    return tracking;
  }

  private buildEmptyTrackingSnapshot(pkg: string, sourceId: number, sourceName: string): SourceMaintenanceTrackingSnapshot {
    const badge: SourceMaintenanceBadge = this.buildBadge(null);
    const snapshot: SourceMaintenanceTrackingSnapshot = {
      pkg: pkg,
      sourceId: sourceId,
      sourceName: sourceName,
      localHash: '',
      localVersion: '',
      fileState: 'unknown',
      fileStateLabel: this.getFileStateLabel('unknown'),
      changeSummary: '尚未加载图源维护状态。',
      badge: badge,
      privateRepository: this.buildEmptyRepositoryTracking('private'),
      officialRepository: this.buildEmptyRepositoryTracking('official'),
      exportPath: '',
      pullRequestUrl: ''
    };
    return snapshot;
  }

  private buildBundleManifest(
    record: SourceMaintenanceRecord,
    sourceHash: string,
    trackingSnapshot: SourceMaintenanceTrackingSnapshot
  ): SourceMaintenanceBundleManifest {
    const source: SourceMaintenanceBundleSourceInfo = {
      pkg: record.pkg,
      name: record.sourceName,
      version: record.sourceVersion,
      sourceId: record.sourceId,
      hash: sourceHash
    };
    const sourceFile: SourceMaintenanceBundleFile = {
      path: 'source.json',
      role: 'source-config'
    };
    const guideFile: SourceMaintenanceBundleFile = {
      path: 'AGENT_GUIDE.md',
      role: 'agent-instructions'
    };
    const manifest: SourceMaintenanceBundleManifest = {
      schemaVersion: 'manxia.sourceMaintenance.bundle.v1',
      agentKitVersion: AGENT_KIT_VERSION,
      exportedAt: Date.now(),
      source: source,
      maintenance: record,
      tracking: trackingSnapshot,
      files: [sourceFile, guideFile]
    };
    return manifest;
  }

  private buildAgentGuide(record: SourceMaintenanceRecord): string {
    const repoUrl: string = record.userRepository ? record.userRepository.repositoryUrl : '<你的图源仓库地址>';
    const branch: string = record.userRepository ? record.userRepository.branch : DEFAULT_BRANCH;
    const sourcePath: string = record.userRepository ? record.userRepository.sourcePath : `${record.pkg}/source.json`;
    return `# 漫匣图源独立维护包

这个文件夹由漫匣 App 导出，交给 Agent 后可以同步到你的个人图源仓库，或整理成提交给漫匣官方仓库的 Pull Request。

## 给 Agent 的提示词

请使用 manxia-source-agent-kit 帮我处理这个维护包：

1. 先运行 \`node src/cli.mjs verify-maintenance-bundle "<维护包目录>"\` 检查包结构。
2. 再运行 \`node src/cli.mjs status-maintenance-bundle "<维护包目录>"\`，先说明 App 识别到的文件变更和两个仓库追踪状态。
3. 如果我要同步到自己的仓库，请运行 \`node src/cli.mjs sync-user-repo "<维护包目录>" --repo "${repoUrl}" --branch "${branch}" --path "${sourcePath}"\`。
4. 如果我要投稿给漫匣官方仓库，请运行 \`node src/cli.mjs prepare-pr "<维护包目录>" --official-repo "${record.officialRepositoryUrl}"\`，然后按生成的说明创建 Pull Request。
5. 完成后，把仓库 raw source.json 地址或 PR 链接告诉我，方便我回填到漫匣 App 的独立维护页面。

## 图源信息

- pkg: ${record.pkg}
- 名称: ${record.sourceName}
- 版本: ${record.sourceVersion}
- 当前模式: ${this.getModeLabel(record.mode)}
- 当前状态: ${this.getSyncStateLabel(record.syncState)}
`;
  }

  private async fetchText(url: string): Promise<string> {
    const httpRequest = http.createHttp();
    const requestOptions: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      connectTimeout: 10000,
      readTimeout: 10000,
      header: {
        'Content-Type': 'application/json'
      }
    };
    if (this.proxyManager.isEnabled()) {
      await this.proxyManager.applyToHttpOptions(requestOptions, url);
    }
    const response = await httpRequest.request(url, requestOptions);
    if (response.responseCode !== 200 || !response.result) {
      throw new Error(`HTTP ${response.responseCode}`);
    }
    return response.result as string;
  }

  private resolveRawSourceUrl(binding: SourceMaintenanceRepositoryBinding): string {
    const url: string = binding.repositoryUrl.trim();
    if (url.length <= 0) {
      return '';
    }
    if (url.includes('/raw/') || url.includes('raw.githubusercontent.com')) {
      return url;
    }
    const pathPart: string = this.trimSlashes(binding.sourcePath);
    if (binding.provider === 'github') {
      const normalized: string = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
      const marker: string = 'github.com/';
      const markerIndex: number = normalized.indexOf(marker);
      if (markerIndex >= 0) {
        const repoPart: string = normalized.substring(markerIndex + marker.length);
        const cleanRepoPart: string = this.stripGithubTreeSuffix(repoPart);
        return `https://raw.githubusercontent.com/${cleanRepoPart}/${binding.branch}/${pathPart}`;
      }
    }
    if (url.endsWith('.json')) {
      return url;
    }
    const baseUrl: string = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    return `${baseUrl}/${pathPart}`;
  }

  private stripGithubTreeSuffix(repoPart: string): string {
    const treeIndex: number = repoPart.indexOf('/tree/');
    if (treeIndex >= 0) {
      return repoPart.substring(0, treeIndex);
    }
    const blobIndex: number = repoPart.indexOf('/blob/');
    if (blobIndex >= 0) {
      return repoPart.substring(0, blobIndex);
    }
    return repoPart;
  }

  private trimSlashes(path: string): string {
    let output: string = path.trim();
    while (output.startsWith('/')) {
      output = output.substring(1);
    }
    while (output.endsWith('/')) {
      output = output.substring(0, output.length - 1);
    }
    return output;
  }

  private detectProvider(repositoryUrl: string): SourceMaintenanceRepositoryProvider {
    if (repositoryUrl.includes('github.com') || repositoryUrl.includes('raw.githubusercontent.com')) {
      return 'github';
    }
    if (repositoryUrl.endsWith('.json') || repositoryUrl.includes('/raw/')) {
      return 'raw';
    }
    return 'generic';
  }

  private resolveName(configJson: string, fallback: string): string {
    const summary: SourceMaintenanceConfigSummary = SafeUtils.parseObj<SourceMaintenanceConfigSummary>(configJson);
    if (summary.metadata && summary.metadata.name && summary.metadata.name.length > 0) {
      return summary.metadata.name;
    }
    return fallback;
  }

  private resolvePkg(configJson: string, fallback: string): string {
    const summary: SourceMaintenanceConfigSummary = SafeUtils.parseObj<SourceMaintenanceConfigSummary>(configJson);
    if (summary.metadata && summary.metadata.id && summary.metadata.id.length > 0) {
      return summary.metadata.id;
    }
    return fallback;
  }

  private resolveVersion(configJson: string, fallback: string): string {
    const summary: SourceMaintenanceConfigSummary = SafeUtils.parseObj<SourceMaintenanceConfigSummary>(configJson);
    if (summary.metadata && summary.metadata.version && summary.metadata.version.length > 0) {
      return summary.metadata.version;
    }
    return fallback;
  }

  private parseSourceId(value: string | number): number {
    if (typeof value === 'number') {
      return value;
    }
    const parsed: number = Number(value);
    return Number.isNaN(parsed) ? 0 : parsed;
  }

  private sanitizeFileName(value: string): string {
    let output: string = value.trim();
    output = output.replace(/[\\/:*?"<>|]/g, '_');
    if (output.length <= 0) {
      output = 'source';
    }
    return output;
  }

  private computeHash(content: string): string {
    let hash: number = 2166136261;
    for (let index = 0; index < content.length; index++) {
      hash = hash ^ content.charCodeAt(index);
      hash = Math.imul(hash, 16777619);
    }
    const unsignedHash: number = hash >>> 0;
    return unsignedHash.toString(16).padStart(8, '0');
  }

  private getModeLabel(mode: SourceMaintenanceMode): string {
    if (mode === 'localFork') {
      return '本地维护';
    }
    if (mode === 'userRepository') {
      return '我的仓库';
    }
    if (mode === 'officialPullRequest') {
      return '官方 PR';
    }
    return '官方同步';
  }

  private getSyncStateLabel(state: SourceMaintenanceSyncState): string {
    if (state === 'dirty') {
      return '有本地修改';
    }
    if (state === 'remoteChanged') {
      return '远端有更新';
    }
    if (state === 'conflicted') {
      return '需要合并';
    }
    if (state === 'unlinked') {
      return '未绑定仓库';
    }
    return '干净';
  }

  private getFileStateLabel(state: SourceMaintenanceFileChangeState): string {
    if (state === 'clean') {
      return '干净';
    }
    if (state === 'modified') {
      return '本地修改';
    }
    if (state === 'added') {
      return '新增文件';
    }
    if (state === 'remoteChanged') {
      return '远端更新';
    }
    if (state === 'conflicted') {
      return '需要合并';
    }
    if (state === 'missing') {
      return '本地缺失';
    }
    if (state === 'unknown') {
      return '未知';
    }
    return '未追踪';
  }

  private getBadgeDescription(record: SourceMaintenanceRecord): string {
    if (record.mode === 'userRepository') {
      return record.userRepository ? `已绑定 ${record.userRepository.repositoryUrl}` : '准备绑定用户仓库';
    }
    if (record.mode === 'officialPullRequest') {
      return record.pullRequestUrl.length > 0 ? `已记录 PR: ${record.pullRequestUrl}` : '已准备投稿到漫匣官方仓库';
    }
    if (record.mode === 'localFork') {
      return '此图源包含本地修改，建议导出维护包并交给 AgentKit 同步。';
    }
    return '此图源跟随漫匣仓库更新。';
  }

  private buildExportFailure(message: string): SourceMaintenanceExportResult {
    const result: SourceMaintenanceExportResult = {
      success: false,
      message: message,
      exportDir: '',
      sourcePath: '',
      manifestPath: '',
      guidePath: ''
    };
    return result;
  }

  private buildPullFailure(message: string, sourceId: number, sourceName: string, remoteHash: string): SourceMaintenancePullResult {
    const result: SourceMaintenancePullResult = {
      success: false,
      message: message,
      sourceId: sourceId,
      sourceName: sourceName,
      remoteHash: remoteHash
    };
    return result;
  }
}

export const sourceMaintenanceManager = SourceMaintenanceManager.getInstance();
