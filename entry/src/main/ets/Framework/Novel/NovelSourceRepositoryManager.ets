import { Context } from '@kit.AbilityKit';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { SafeFileUtils } from 'manxia_core/src/main/ets/Utils/SafeFileUtils';
import { SafeUtils } from 'manxia_core/src/main/ets/Utils/SafeUtils';
import {
  DEFAULT_VERSION_COMMIT_REPOSITORIES,
  MANXIA_LEGADO_SOURCES_REPOSITORY_KEY,
  VersionCommitRepositoryTarget,
  VersionHistoryManager,
  VersionRepositoryUpdateCheckResult,
  VersionRepositoryVersionMarker
} from 'manxia_core/src/main/ets/Framework/Managers/VersionHistoryManager';
import { AppInfoManager } from 'manxia_core/src/main/ets/Framework/Managers/AppInfoManager';
import { LegadoSourceImportResult } from 'manxia_novel/src/main/ets/Framework/Novel/LegadoSourceTypes';
import { getNovelSourceManager, NovelSourceManager } from './NovelSourceManager';
import {
  LegadoCloudLogLevel,
  LegadoCloudUpdateUtils,
  LegadoRepositoryRouteResult,
  logLegadoCloudMessage
} from './LegadoCloudUpdateUtils';

const TAG = 'NovelSourceRepositoryManager';
const NOVEL_SOURCE_REPOSITORY_DIR_NAME = 'legado-source-repositories';
const NOVEL_SOURCE_REPOSITORY_INDEX_FILE = 'index.main.json';
const NOVEL_SOURCE_SAVED_REPOSITORIES_FILE = 'saved_repositories.json';
const NOVEL_SOURCE_UPDATE_STATE_FILE = 'update_state.json';
const NOVEL_SOURCE_SUPPORTED_RUNTIME_API = 1;
const DAILY_CHECK_INTERVAL_MS = 24 * 60 * 60 * 1000;

export const DEFAULT_NOVEL_SOURCE_REPOSITORY_URL =
  'https://raw.githubusercontent.com/DaLongZhuaZi/manxia-legado-sources/master/index.main.json';

export interface NovelSourceRepositoryEntry {
  pkg: string;
  name: string;
  bookSourceUrl: string;
  bookSourceType: number;
  lang: string;
  code: number;
  version: string;
  nsfw: number;
  hasIcon: boolean;
  sourcePath: string;
  sha256: string;
  minAppVersionCode: number;
  minRuntimeApi: number;
  changelog: string;
}

export interface NovelSourceRepositoryIndex {
  schemaVersion: string;
  repositoryName: string;
  lastUpdate: number;
  sources: NovelSourceRepositoryEntry[];
}

export interface NovelSourceSavedRepository {
  id: string;
  name: string;
  url: string;
  originalUrl: string;
  lastEffectiveUrl: string;
  lastSync: number;
  sourceCount: number;
}

export interface NovelSourceRepositorySyncResult {
  success: boolean;
  message: string;
  sourceCount: number;
  addedCount: number;
  updatedCount: number;
  skippedCount: number;
  failedCount: number;
}

export interface NovelSourceRepositoryUpdateStatus {
  lastCheckAt: number;
  hasUpdate: boolean;
  canCheck: boolean;
  latestCommitShortSha: string;
  latestCommitDate: string;
  errorMessage: string;
}

interface NovelSourceRepositoryState {
  lastOfficialCheckAt: number;
  hasOfficialUpdate: boolean;
  canCheckOfficialUpdate: boolean;
  latestCommitShortSha: string;
  latestCommitDate: string;
  errorMessage: string;
}

interface NovelSourceRepositoryEntryWorkResult {
  entry: NovelSourceRepositoryEntry;
  sourceJson: string;
  imported: boolean;
  skipped: boolean;
}

export interface NovelSourceRepositorySyncProgressCallback {
  onProgress: (current: number, total: number, message: string) => void;
  onLog: (level: LegadoCloudLogLevel, message: string) => void;
}

export class NovelSourceRepositoryManager {
  private static instance: NovelSourceRepositoryManager | null = null;
  private context: Context | null = null;
  private repositoryDir: string = '';
  private indexFilePath: string = '';
  private savedRepositoriesPath: string = '';
  private updateStatePath: string = '';
  private sourceManager: NovelSourceManager = getNovelSourceManager();

  private constructor() {}

  static getInstance(): NovelSourceRepositoryManager {
    if (!NovelSourceRepositoryManager.instance) {
      NovelSourceRepositoryManager.instance = new NovelSourceRepositoryManager();
    }
    return NovelSourceRepositoryManager.instance;
  }

  async initialize(context: Context): Promise<void> {
    this.context = context;
    this.repositoryDir = `${LegadoCloudUpdateUtils.getFilesDir(context)}/${NOVEL_SOURCE_REPOSITORY_DIR_NAME}`;
    this.indexFilePath = `${this.repositoryDir}/${NOVEL_SOURCE_REPOSITORY_INDEX_FILE}`;
    this.savedRepositoriesPath = `${this.repositoryDir}/${NOVEL_SOURCE_SAVED_REPOSITORIES_FILE}`;
    this.updateStatePath = `${this.repositoryDir}/${NOVEL_SOURCE_UPDATE_STATE_FILE}`;
    LegadoCloudUpdateUtils.ensureDirectoryExists(this.repositoryDir);
    this.ensureIndexFileExists();
    this.ensureSavedRepositoriesFileExists();
    this.ensureUpdateStateFileExists();
    logger.info(TAG, `Legado书源仓库管理器初始化完成: ${this.repositoryDir}`);
  }

  async syncRepositoryFromUrl(
    url: string,
    repositoryName?: string,
    progressCallback?: NovelSourceRepositorySyncProgressCallback
  ): Promise<NovelSourceRepositorySyncResult> {
    const log = (level: LegadoCloudLogLevel, message: string) => {
      logLegadoCloudMessage(level, TAG, message);
      progressCallback?.onLog(level, message);
    };

    try {
      this.ensureInitialized();
      const normalizedUrl = LegadoCloudUpdateUtils.normalizeRepositoryUrl(url);
      if (normalizedUrl.length === 0) {
        throw new Error('仓库地址不能为空');
      }

      progressCallback?.onProgress(0, 100, '正在检测仓库连通性...');
      const route = await LegadoCloudUpdateUtils.resolveBestRepositoryUrl(normalizedUrl, log);
      if (route.usedProxy) {
        log('warn', `原始仓库不可达，切换到代理地址: ${route.effectiveUrl}`);
      }
      progressCallback?.onProgress(8, 100, '正在下载书源仓库索引...');

      const indexText = await LegadoCloudUpdateUtils.downloadText(route.effectiveUrl, 10000, 10000);
      const remoteIndex = this.parseAndValidateIndex(indexText);
      const appVersionCode = await AppInfoManager.getInstance().getVersionCode();
      const currentIndex = this.readIndexFile();
      const mergedSources = currentIndex.sources.slice();

      log('info', `获取到 ${remoteIndex.sources.length} 个书源`);

      let addedCount = 0;
      let updatedCount = 0;
      let skippedCount = 0;
      let failedCount = 0;
      const total = remoteIndex.sources.length;

      for (let i = 0; i < remoteIndex.sources.length; i++) {
        const entry = remoteIndex.sources[i];
        const current = i + 1;
        const progress = total > 0 ? 10 + Math.floor((current / total) * 70) : 80;
        progressCallback?.onProgress(progress, 100, `处理书源 (${current}/${total}): ${entry.name}`);

        try {
          if (!this.isEntryCompatible(entry, appVersionCode, log)) {
            failedCount++;
            continue;
          }

          const existingIndex = this.findEntryIndex(mergedSources, entry.pkg);
          const shouldSkip = existingIndex >= 0 && !this.shouldRefreshEntry(mergedSources[existingIndex], entry);
          if (shouldSkip && this.hasLocalSourceFile(entry.pkg)) {
            skippedCount++;
            continue;
          }

          const workResult = await this.downloadAndImportEntry(route.effectiveUrl, entry, shouldSkip, log);
          this.upsertEntry(mergedSources, workResult.entry);
          if (existingIndex >= 0) {
            updatedCount++;
          } else {
            addedCount++;
          }
        } catch (entryError) {
          failedCount++;
          log('warn', `书源处理失败: ${entry.name} - ${LegadoCloudUpdateUtils.extractErrorMessage(entryError as Object)}`);
        }
      }

      progressCallback?.onProgress(86, 100, '正在保存本地书源仓库索引...');
      const mergedIndex: NovelSourceRepositoryIndex = {
        schemaVersion: remoteIndex.schemaVersion,
        repositoryName: remoteIndex.repositoryName,
        lastUpdate: remoteIndex.lastUpdate,
        sources: mergedSources
      };
      this.writeIndexFile(mergedIndex);
      this.saveRepositoryConfig(route, repositoryName || remoteIndex.repositoryName, remoteIndex.sources.length);

      progressCallback?.onProgress(95, 100, '正在记录仓库版本...');
      await this.markOfficialRepositoryVersionIfPossible(route.originalUrl);

      progressCallback?.onProgress(100, 100, '书源仓库同步完成');
      const result: NovelSourceRepositorySyncResult = {
        success: total === 0 || failedCount < total,
        message: `同步完成：新增 ${addedCount}，更新 ${updatedCount}，跳过 ${skippedCount}，失败 ${failedCount}`,
        sourceCount: remoteIndex.sources.length,
        addedCount: addedCount,
        updatedCount: updatedCount,
        skippedCount: skippedCount,
        failedCount: failedCount
      };
      log(result.success ? 'info' : 'warn', result.message);
      return result;
    } catch (error) {
      const errorMessage = LegadoCloudUpdateUtils.extractErrorMessage(error as Object);
      log('error', `书源仓库同步失败: ${errorMessage}`);
      return {
        success: false,
        message: `同步失败: ${errorMessage}`,
        sourceCount: 0,
        addedCount: 0,
        updatedCount: 0,
        skippedCount: 0,
        failedCount: 0
      };
    }
  }

  getSavedRepositories(): NovelSourceSavedRepository[] {
    try {
      this.ensureInitialized();
      this.ensureSavedRepositoriesFileExists();
      const text = LegadoCloudUpdateUtils.readTextFile(this.savedRepositoriesPath, 1024 * 1024);
      const parsed = SafeUtils.parseArr<NovelSourceSavedRepository[]>(text);
      return Array.isArray(parsed) ? parsed : [];
    } catch (error) {
      logger.warn(TAG, `读取已保存书源仓库失败: ${String(error)}`);
      return [];
    }
  }

  deleteRepository(repoId: string): boolean {
    try {
      this.ensureInitialized();
      const repos = this.getSavedRepositories();
      const filtered = repos.filter((repo: NovelSourceSavedRepository) => repo.id !== repoId);
      this.writeSavedRepositories(filtered);
      return true;
    } catch (error) {
      logger.error(TAG, `删除书源仓库失败: ${String(error)}`);
      return false;
    }
  }

  getRepositorySources(): NovelSourceRepositoryEntry[] {
    return this.readIndexFile().sources;
  }

  async importSourceFromRepository(pkg: string): Promise<LegadoSourceImportResult[]> {
    this.ensureInitialized();
    const entry = this.readIndexFile().sources.find((item: NovelSourceRepositoryEntry) => item.pkg === pkg);
    if (!entry) {
      return [{
        success: false,
        sourceName: pkg,
        error: '仓库中不存在该书源'
      }];
    }
    const sourceFilePath = this.getLocalSourceFilePath(pkg);
    if (!SafeFileUtils.accessSync(sourceFilePath)) {
      return [{
        success: false,
        sourceName: entry.name,
        error: '本地书源文件不存在'
      }];
    }
    const jsonText = LegadoCloudUpdateUtils.readTextFile(sourceFilePath);
    return await this.sourceManager.importFromJSON(jsonText, true, {
      preserveLocalState: true,
      defaultNSFW: entry.nsfw === 1
    });
  }

  async checkOfficialRepositoryUpdateIfNeeded(force: boolean = false): Promise<NovelSourceRepositoryUpdateStatus> {
    this.ensureInitialized();
    const state = this.readUpdateState();
    const now = Date.now();
    if (!force && state.lastOfficialCheckAt > 0 && now - state.lastOfficialCheckAt < DAILY_CHECK_INTERVAL_MS) {
      return this.buildUpdateStatus(state);
    }

    const target = this.resolveOfficialVersionTarget();
    if (!target) {
      const missingState: NovelSourceRepositoryState = {
        lastOfficialCheckAt: now,
        hasOfficialUpdate: false,
        canCheckOfficialUpdate: false,
        latestCommitShortSha: '',
        latestCommitDate: '',
        errorMessage: '未找到默认书源索引仓库版本配置'
      };
      this.writeUpdateState(missingState);
      return this.buildUpdateStatus(missingState);
    }

    try {
      const context = this.context;
      if (!context) {
        throw new Error('书源仓库管理器未初始化');
      }
      const versionManager = VersionHistoryManager.getInstance();
      await versionManager.initialize(context);
      const result = await versionManager.checkRepositoryUpdateByTarget(target);
      const latestShortSha = result.latestCommit ? result.latestCommit.shortSha : '';
      const latestDate = result.latestCommit ? result.latestCommit.date : '';
      const newState: NovelSourceRepositoryState = {
        lastOfficialCheckAt: now,
        hasOfficialUpdate: result.hasUpdate,
        canCheckOfficialUpdate: result.canCheck,
        latestCommitShortSha: latestShortSha,
        latestCommitDate: latestDate,
        errorMessage: result.errorMessage
      };
      this.writeUpdateState(newState);
      return this.buildUpdateStatus(newState);
    } catch (error) {
      const failedState: NovelSourceRepositoryState = {
        lastOfficialCheckAt: now,
        hasOfficialUpdate: false,
        canCheckOfficialUpdate: false,
        latestCommitShortSha: '',
        latestCommitDate: '',
        errorMessage: LegadoCloudUpdateUtils.extractErrorMessage(error as Object)
      };
      this.writeUpdateState(failedState);
      return this.buildUpdateStatus(failedState);
    }
  }

  getRepositoryUpdateStatus(): NovelSourceRepositoryUpdateStatus {
    this.ensureInitialized();
    return this.buildUpdateStatus(this.readUpdateState());
  }

  private async downloadAndImportEntry(
    effectiveIndexUrl: string,
    entry: NovelSourceRepositoryEntry,
    skipped: boolean,
    log: (level: LegadoCloudLogLevel, message: string) => void
  ): Promise<NovelSourceRepositoryEntryWorkResult> {
    const sourceUrl = LegadoCloudUpdateUtils.resolveRepositoryAssetUrl(effectiveIndexUrl, this.getEntrySourcePath(entry));
    const sourceJson = await LegadoCloudUpdateUtils.downloadText(sourceUrl, 8000, 12000);
    await this.verifySourceSha256(entry, sourceJson);
    const localSourcePath = this.getLocalSourceFilePath(entry.pkg);
    LegadoCloudUpdateUtils.writeTextFile(localSourcePath, sourceJson);

    if (entry.hasIcon) {
      await this.downloadIconIfAvailable(effectiveIndexUrl, entry, log);
    }

    const importResults = await this.sourceManager.importFromJSON(sourceJson, true, {
      preserveLocalState: true,
      defaultNSFW: entry.nsfw === 1
    });
    const successCount = importResults.filter((result: LegadoSourceImportResult) => result.success).length;
    if (successCount <= 0) {
      throw new Error('书源导入失败');
    }

    return {
      entry: entry,
      sourceJson: sourceJson,
      imported: true,
      skipped: skipped
    };
  }

  private async downloadIconIfAvailable(
    effectiveIndexUrl: string,
    entry: NovelSourceRepositoryEntry,
    log: (level: LegadoCloudLogLevel, message: string) => void
  ): Promise<void> {
    const formats: string[] = ['webp', 'png', 'jpg'];
    for (const ext of formats) {
      const iconUrl = LegadoCloudUpdateUtils.resolveRepositoryAssetUrl(effectiveIndexUrl, `${entry.pkg}/icon.${ext}`);
      try {
        const bytes = await LegadoCloudUpdateUtils.downloadBytes(iconUrl, 5000, 5000);
        const iconPath = `${this.repositoryDir}/${entry.pkg}/icon.${ext}`;
        LegadoCloudUpdateUtils.writeBytesFile(iconPath, bytes);
        log('info', `书源图标已更新: ${entry.pkg}/icon.${ext}`);
        return;
      } catch (_) {
        // 尝试下一个图标格式
      }
    }
    log('warn', `未下载到书源图标: ${entry.pkg}`);
  }

  private async verifySourceSha256(entry: NovelSourceRepositoryEntry, sourceJson: string): Promise<void> {
    const expected = entry.sha256.trim().toLowerCase();
    if (expected.length === 0) {
      return;
    }
    const actual = (await LegadoCloudUpdateUtils.sha256HexForString(sourceJson)).toLowerCase();
    if (actual !== expected) {
      throw new Error(`sha256不匹配: expected=${expected}, actual=${actual}`);
    }
  }

  private parseAndValidateIndex(indexText: string): NovelSourceRepositoryIndex {
    const parsed = JSON.parse(indexText) as NovelSourceRepositoryIndex;
    if (!parsed || typeof parsed !== 'object') {
      throw new Error('仓库索引不是有效对象');
    }
    if (typeof parsed.schemaVersion !== 'string' || parsed.schemaVersion.trim().length === 0) {
      throw new Error('仓库索引缺少 schemaVersion');
    }
    if (typeof parsed.repositoryName !== 'string' || parsed.repositoryName.trim().length === 0) {
      throw new Error('仓库索引缺少 repositoryName');
    }
    if (typeof parsed.lastUpdate !== 'number') {
      throw new Error('仓库索引 lastUpdate 类型错误');
    }
    if (!Array.isArray(parsed.sources)) {
      throw new Error('仓库索引 sources 类型错误');
    }

    const entries: NovelSourceRepositoryEntry[] = [];
    for (let i = 0; i < parsed.sources.length; i++) {
      entries.push(this.validateEntry(parsed.sources[i], i));
    }
    return {
      schemaVersion: parsed.schemaVersion,
      repositoryName: parsed.repositoryName,
      lastUpdate: parsed.lastUpdate,
      sources: entries
    };
  }

  private validateEntry(entry: NovelSourceRepositoryEntry, index: number): NovelSourceRepositoryEntry {
    if (!entry || typeof entry !== 'object') {
      throw new Error(`sources[${index}] 不是有效对象`);
    }
    this.requireString(entry.pkg, `sources[${index}].pkg`);
    this.requireString(entry.name, `sources[${index}].name`);
    this.requireString(entry.bookSourceUrl, `sources[${index}].bookSourceUrl`);
    this.requireString(entry.lang, `sources[${index}].lang`);
    this.requireString(entry.version, `sources[${index}].version`);
    this.requireString(entry.sourcePath, `sources[${index}].sourcePath`);
    this.requireString(entry.sha256, `sources[${index}].sha256`, true);
    this.requireString(entry.changelog, `sources[${index}].changelog`, true);
    this.requireNumber(entry.bookSourceType, `sources[${index}].bookSourceType`);
    this.requireNumber(entry.code, `sources[${index}].code`);
    this.requireNumber(entry.nsfw, `sources[${index}].nsfw`);
    this.requireBoolean(entry.hasIcon, `sources[${index}].hasIcon`);
    this.requireNumber(entry.minAppVersionCode, `sources[${index}].minAppVersionCode`);
    this.requireNumber(entry.minRuntimeApi, `sources[${index}].minRuntimeApi`);
    return entry;
  }

  private requireString(value: string, fieldName: string, allowEmpty: boolean = false): void {
    if (typeof value !== 'string') {
      throw new Error(`${fieldName} 类型错误`);
    }
    if (!allowEmpty && value.trim().length === 0) {
      throw new Error(`${fieldName} 不能为空`);
    }
  }

  private requireNumber(value: number, fieldName: string): void {
    if (typeof value !== 'number') {
      throw new Error(`${fieldName} 类型错误`);
    }
  }

  private requireBoolean(value: boolean, fieldName: string): void {
    if (typeof value !== 'boolean') {
      throw new Error(`${fieldName} 类型错误`);
    }
  }

  private isEntryCompatible(
    entry: NovelSourceRepositoryEntry,
    appVersionCode: number,
    log: (level: LegadoCloudLogLevel, message: string) => void
  ): boolean {
    if (appVersionCode > 0 && entry.minAppVersionCode > appVersionCode) {
      log('warn', `跳过书源 ${entry.name}: 需要应用版本 ${entry.minAppVersionCode}`);
      return false;
    }
    if (entry.minRuntimeApi > NOVEL_SOURCE_SUPPORTED_RUNTIME_API) {
      log('warn', `跳过书源 ${entry.name}: 需要运行时 API ${entry.minRuntimeApi}`);
      return false;
    }
    return true;
  }

  private shouldRefreshEntry(existing: NovelSourceRepositoryEntry, incoming: NovelSourceRepositoryEntry): boolean {
    if (incoming.code > existing.code) {
      return true;
    }
    if (incoming.code < existing.code) {
      return false;
    }
    return incoming.version !== existing.version;
  }

  private findEntryIndex(entries: NovelSourceRepositoryEntry[], pkg: string): number {
    return entries.findIndex((item: NovelSourceRepositoryEntry) => item.pkg === pkg);
  }

  private upsertEntry(entries: NovelSourceRepositoryEntry[], entry: NovelSourceRepositoryEntry): void {
    const index = this.findEntryIndex(entries, entry.pkg);
    if (index >= 0) {
      entries[index] = entry;
      return;
    }
    entries.push(entry);
  }

  private getEntrySourcePath(entry: NovelSourceRepositoryEntry): string {
    const trimmed = entry.sourcePath.trim();
    if (trimmed.length > 0) {
      return LegadoCloudUpdateUtils.sanitizeRelativePath(trimmed);
    }
    return `${entry.pkg}/source.json`;
  }

  private getLocalSourceFilePath(pkg: string): string {
    return `${this.repositoryDir}/${LegadoCloudUpdateUtils.sanitizeRelativePath(pkg)}/source.json`;
  }

  private hasLocalSourceFile(pkg: string): boolean {
    return SafeFileUtils.accessSync(this.getLocalSourceFilePath(pkg));
  }

  private ensureInitialized(): void {
    if (!this.context || this.repositoryDir.length === 0) {
      throw new Error('Legado书源仓库管理器未初始化');
    }
  }

  private ensureIndexFileExists(): void {
    if (SafeFileUtils.accessSync(this.indexFilePath)) {
      return;
    }
    const emptyIndex: NovelSourceRepositoryIndex = {
      schemaVersion: '1.0.0',
      repositoryName: 'Legado书源索引',
      lastUpdate: 0,
      sources: []
    };
    this.writeIndexFile(emptyIndex);
  }

  private ensureSavedRepositoriesFileExists(): void {
    if (SafeFileUtils.accessSync(this.savedRepositoriesPath)) {
      return;
    }
    this.writeSavedRepositories([]);
  }

  private ensureUpdateStateFileExists(): void {
    if (SafeFileUtils.accessSync(this.updateStatePath)) {
      return;
    }
    this.writeUpdateState(this.createEmptyUpdateState());
  }

  private readIndexFile(): NovelSourceRepositoryIndex {
    try {
      const text = LegadoCloudUpdateUtils.readTextFile(this.indexFilePath);
      const parsed = SafeUtils.parseObj<NovelSourceRepositoryIndex>(text);
      if (parsed && Array.isArray(parsed.sources)) {
        return parsed;
      }
    } catch (error) {
      logger.warn(TAG, `读取本地书源仓库索引失败: ${String(error)}`);
    }
    return {
      schemaVersion: '1.0.0',
      repositoryName: 'Legado书源索引',
      lastUpdate: 0,
      sources: []
    };
  }

  private writeIndexFile(index: NovelSourceRepositoryIndex): void {
    LegadoCloudUpdateUtils.writeTextFile(this.indexFilePath, JSON.stringify(index, null, 2));
  }

  private writeSavedRepositories(repos: NovelSourceSavedRepository[]): void {
    LegadoCloudUpdateUtils.writeTextFile(this.savedRepositoriesPath, JSON.stringify(repos, null, 2));
  }

  private saveRepositoryConfig(route: LegadoRepositoryRouteResult, name: string, sourceCount: number): void {
    const savedRepos = this.getSavedRepositories();
    const originalUrl = LegadoCloudUpdateUtils.normalizeRepositoryUrl(route.originalUrl || route.effectiveUrl);
    const effectiveUrl = LegadoCloudUpdateUtils.normalizeRepositoryUrl(route.effectiveUrl || route.originalUrl);
    const repoId = LegadoCloudUpdateUtils.generateRepositoryId(originalUrl);
    const newRepo: NovelSourceSavedRepository = {
      id: repoId,
      name: name,
      url: originalUrl,
      originalUrl: originalUrl,
      lastEffectiveUrl: effectiveUrl,
      lastSync: Date.now(),
      sourceCount: sourceCount
    };
    let replaced = false;
    const merged: NovelSourceSavedRepository[] = [];
    for (const repo of savedRepos) {
      if (repo.id === repoId || repo.url === originalUrl || repo.originalUrl === originalUrl) {
        if (!replaced) {
          merged.push(newRepo);
          replaced = true;
        }
      } else {
        merged.push(repo);
      }
    }
    if (!replaced) {
      merged.push(newRepo);
    }
    this.writeSavedRepositories(merged);
  }

  private createEmptyUpdateState(): NovelSourceRepositoryState {
    return {
      lastOfficialCheckAt: 0,
      hasOfficialUpdate: false,
      canCheckOfficialUpdate: false,
      latestCommitShortSha: '',
      latestCommitDate: '',
      errorMessage: ''
    };
  }

  private readUpdateState(): NovelSourceRepositoryState {
    try {
      const text = LegadoCloudUpdateUtils.readTextFile(this.updateStatePath, 256 * 1024);
      const parsed = SafeUtils.parseObj<NovelSourceRepositoryState>(text);
      if (parsed) {
        return {
          lastOfficialCheckAt: typeof parsed.lastOfficialCheckAt === 'number' ? parsed.lastOfficialCheckAt : 0,
          hasOfficialUpdate: parsed.hasOfficialUpdate === true,
          canCheckOfficialUpdate: parsed.canCheckOfficialUpdate === true,
          latestCommitShortSha: typeof parsed.latestCommitShortSha === 'string' ? parsed.latestCommitShortSha : '',
          latestCommitDate: typeof parsed.latestCommitDate === 'string' ? parsed.latestCommitDate : '',
          errorMessage: typeof parsed.errorMessage === 'string' ? parsed.errorMessage : ''
        };
      }
    } catch (error) {
      logger.warn(TAG, `读取书源仓库更新状态失败: ${String(error)}`);
    }
    return this.createEmptyUpdateState();
  }

  private writeUpdateState(state: NovelSourceRepositoryState): void {
    LegadoCloudUpdateUtils.writeTextFile(this.updateStatePath, JSON.stringify(state, null, 2));
  }

  private buildUpdateStatus(state: NovelSourceRepositoryState): NovelSourceRepositoryUpdateStatus {
    return {
      lastCheckAt: state.lastOfficialCheckAt,
      hasUpdate: state.hasOfficialUpdate,
      canCheck: state.canCheckOfficialUpdate,
      latestCommitShortSha: state.latestCommitShortSha,
      latestCommitDate: state.latestCommitDate,
      errorMessage: state.errorMessage
    };
  }

  private resolveOfficialVersionTarget(): VersionCommitRepositoryTarget | null {
    const target = DEFAULT_VERSION_COMMIT_REPOSITORIES.find(
      (item: VersionCommitRepositoryTarget) => item.key === MANXIA_LEGADO_SOURCES_REPOSITORY_KEY
    );
    return target || null;
  }

  private async markOfficialRepositoryVersionIfPossible(url: string): Promise<void> {
    const context = this.context;
    if (!context) {
      return;
    }
    try {
      const versionManager = VersionHistoryManager.getInstance();
      await versionManager.initialize(context);
      const marker: VersionRepositoryVersionMarker | null = await versionManager.markRepositoryVersionByUrl(url);
      if (marker) {
        const state = this.readUpdateState();
        state.hasOfficialUpdate = false;
        state.canCheckOfficialUpdate = true;
        state.latestCommitShortSha = marker.commitShortSha;
        state.latestCommitDate = marker.commitDate;
        state.errorMessage = '';
        this.writeUpdateState(state);
      }
    } catch (error) {
      logger.warn(TAG, `记录默认书源索引仓库版本失败: ${String(error)}`);
    }
  }
}

export function getNovelSourceRepositoryManager(): NovelSourceRepositoryManager {
  return NovelSourceRepositoryManager.getInstance();
}
