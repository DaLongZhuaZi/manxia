import { Context } from '@kit.AbilityKit';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { SafeFileUtils } from 'manxia_core/src/main/ets/Utils/SafeFileUtils';
import { SafeUtils } from 'manxia_core/src/main/ets/Utils/SafeUtils';
import {
  DEFAULT_VERSION_COMMIT_REPOSITORIES,
  MANXIA_LEGADO_RUNTIME_REPOSITORY_KEY,
  VersionCommitRepositoryTarget,
  VersionHistoryManager,
  VersionRepositoryVersionMarker
} from '../Managers/VersionHistoryManager';
import { AppInfoManager } from '../Managers/AppInfoManager';
import {
  LegadoCloudLogLevel,
  LegadoCloudUpdateUtils,
  LegadoRepositoryRouteResult,
  logLegadoCloudMessage
} from './LegadoCloudUpdateUtils';

const TAG = 'LegadoRuntimeAssetManager';
const LEGADO_RUNTIME_DIR_NAME = 'legado-runtime';
const LEGADO_RUNTIME_STAGING_DIR = 'staging';
const LEGADO_RUNTIME_ACTIVE_DIR = 'active';
const LEGADO_RUNTIME_ROLLBACK_DIR = 'rollback';
const LEGADO_RUNTIME_STATUS_FILE = 'active.json';
const LEGADO_RUNTIME_UPDATE_STATE_FILE = 'update_state.json';
// API 2 establishes the V2 bridge contract. Runtime API 1 predates the
// contract registry and can silently load a stale java.* surface after an app
// update, so it must fall back to the bundled runtime instead of being reused.
const LEGADO_RUNTIME_MINIMUM_API = 3;
const LEGADO_RUNTIME_SUPPORTED_API = 3;
const LEGADO_RUNTIME_DEFAULT_ENTRY = 'legado_runtime.html';
const LEGADO_RUNTIME_RHINO_ENTRY = 'rhino_sandbox/index.html';
const DAILY_CHECK_INTERVAL_MS = 24 * 60 * 60 * 1000;

export const DEFAULT_LEGADO_RUNTIME_REPOSITORY_URL =
  'https://raw.githubusercontent.com/DaLongZhuaZi/manxia-legado-runtime/master/index.main.json';

export type LegadoRuntimeEntryKind = 'legado' | 'rhino';

export interface LegadoRuntimeAssetFile {
  path: string;
  url: string;
  sha256: string;
  size: number;
  mimeType: string;
  required: boolean;
}

export interface LegadoRuntimeAssetIndex {
  schemaVersion: string;
  runtimeApi: number;
  code: number;
  version: string;
  minAppVersionCode: number;
  entry: string;
  files: LegadoRuntimeAssetFile[];
}

export interface LegadoRuntimeSyncResult {
  success: boolean;
  message: string;
  version: string;
  code: number;
  fileCount: number;
}

export interface LegadoRuntimeActiveStatus {
  installed: boolean;
  healthOk: boolean;
  runtimeApi: number;
  code: number;
  version: string;
  activePath: string;
  legadoEntryUrl: string;
  rhinoEntryUrl: string;
  updatedAt: number;
  message: string;
}

export interface LegadoRuntimeRepositoryUpdateStatus {
  lastCheckAt: number;
  hasUpdate: boolean;
  canCheck: boolean;
  latestCommitShortSha: string;
  latestCommitDate: string;
  errorMessage: string;
}

interface LegadoRuntimeUpdateState {
  lastOfficialCheckAt: number;
  hasOfficialUpdate: boolean;
  canCheckOfficialUpdate: boolean;
  latestCommitShortSha: string;
  latestCommitDate: string;
  errorMessage: string;
}

export interface LegadoRuntimeSyncProgressCallback {
  onProgress: (current: number, total: number, message: string) => void;
  onLog: (level: LegadoCloudLogLevel, message: string) => void;
}

export class LegadoRuntimeAssetManager {
  private static instance: LegadoRuntimeAssetManager | null = null;
  private context: Context | null = null;
  private runtimeDir: string = '';
  private stagingDir: string = '';
  private activeDir: string = '';
  private rollbackDir: string = '';
  private activeStatusPath: string = '';
  private updateStatePath: string = '';

  private constructor() {}

  static getInstance(): LegadoRuntimeAssetManager {
    if (!LegadoRuntimeAssetManager.instance) {
      LegadoRuntimeAssetManager.instance = new LegadoRuntimeAssetManager();
    }
    return LegadoRuntimeAssetManager.instance;
  }

  initialize(context: Context): void {
    this.context = context;
    this.runtimeDir = `${LegadoCloudUpdateUtils.getFilesDir(context)}/${LEGADO_RUNTIME_DIR_NAME}`;
    this.stagingDir = `${this.runtimeDir}/${LEGADO_RUNTIME_STAGING_DIR}`;
    this.activeDir = `${this.runtimeDir}/${LEGADO_RUNTIME_ACTIVE_DIR}`;
    this.rollbackDir = `${this.runtimeDir}/${LEGADO_RUNTIME_ROLLBACK_DIR}`;
    this.activeStatusPath = `${this.runtimeDir}/${LEGADO_RUNTIME_STATUS_FILE}`;
    this.updateStatePath = `${this.runtimeDir}/${LEGADO_RUNTIME_UPDATE_STATE_FILE}`;
    LegadoCloudUpdateUtils.ensureDirectoryExists(this.runtimeDir);
    this.ensureUpdateStateFileExists();
    logger.info(TAG, `Legado运行时资产管理器初始化完成: ${this.runtimeDir}`);
  }

  async syncRuntimeFromUrl(
    url: string,
    progressCallback?: LegadoRuntimeSyncProgressCallback
  ): Promise<LegadoRuntimeSyncResult> {
    const log = (level: LegadoCloudLogLevel, message: string) => {
      logLegadoCloudMessage(level, TAG, message);
      progressCallback?.onLog(level, message);
    };

    try {
      this.ensureInitialized();
      const normalizedUrl = LegadoCloudUpdateUtils.normalizeRepositoryUrl(url);
      if (normalizedUrl.length === 0) {
        throw new Error('运行时仓库地址不能为空');
      }

      progressCallback?.onProgress(0, 100, '正在检测运行时仓库连通性...');
      const route = await LegadoCloudUpdateUtils.resolveBestRepositoryUrl(normalizedUrl, log);
      progressCallback?.onProgress(8, 100, '正在下载运行时索引...');
      const indexText = await LegadoCloudUpdateUtils.downloadText(route.effectiveUrl, 10000, 10000);
      const runtimeIndex = this.parseAndValidateIndex(indexText);
      await this.ensureRuntimeCompatible(runtimeIndex);

      progressCallback?.onProgress(12, 100, '正在准备 staging 目录...');
      LegadoCloudUpdateUtils.removePathRecursive(this.stagingDir);
      LegadoCloudUpdateUtils.ensureDirectoryExists(this.stagingDir);

      const total = runtimeIndex.files.length;
      for (let i = 0; i < runtimeIndex.files.length; i++) {
        const file = runtimeIndex.files[i];
        const current = i + 1;
        const progress = total > 0 ? 15 + Math.floor((current / total) * 60) : 75;
        progressCallback?.onProgress(progress, 100, `下载运行时文件 (${current}/${total}): ${file.path}`);
        await this.downloadRuntimeFile(route, file, log);
      }

      progressCallback?.onProgress(80, 100, '正在执行运行时健康检查...');
      this.validateRuntimeHealth(this.stagingDir, runtimeIndex);

      progressCallback?.onProgress(88, 100, '正在切换 active 运行时...');
      this.writeStatusFile(this.stagingDir, runtimeIndex, true, '运行时健康检查通过');
      this.switchStagingToActive();
      this.writeActiveRootStatus(runtimeIndex, true, '运行时已激活');
      await this.markOfficialRuntimeVersionIfPossible(route.originalUrl);

      progressCallback?.onProgress(100, 100, '运行时同步完成');
      const result: LegadoRuntimeSyncResult = {
        success: true,
        message: `运行时 ${runtimeIndex.version} 已激活`,
        version: runtimeIndex.version,
        code: runtimeIndex.code,
        fileCount: runtimeIndex.files.length
      };
      log('info', result.message);
      return result;
    } catch (error) {
      const errorMessage = LegadoCloudUpdateUtils.extractErrorMessage(error as Object);
      log('error', `运行时同步失败: ${errorMessage}`);
      LegadoCloudUpdateUtils.removePathRecursive(this.stagingDir);
      return {
        success: false,
        message: `运行时同步失败: ${errorMessage}`,
        version: '',
        code: 0,
        fileCount: 0
      };
    }
  }

  getActiveRuntimeStatus(): LegadoRuntimeActiveStatus {
    this.ensureInitialized();
    const fallbackStatus = this.createFallbackStatus('未安装云端运行时');
    if (!SafeFileUtils.accessSync(this.activeStatusPath)) {
      return fallbackStatus;
    }

    try {
      const text = LegadoCloudUpdateUtils.readTextFile(this.activeStatusPath, 256 * 1024);
      const parsed = SafeUtils.parseObj<LegadoRuntimeActiveStatus>(text);
      if (!parsed || parsed.installed !== true) {
        return fallbackStatus;
      }
      if (!SafeFileUtils.accessSync(this.activeDir)) {
        return this.createFallbackStatus('active 目录不存在');
      }
      const runtimeApi = typeof parsed.runtimeApi === 'number' ? parsed.runtimeApi : 0;
      if (runtimeApi < LEGADO_RUNTIME_MINIMUM_API) {
        return this.createFallbackStatus(
          `云端运行时 API 过低: remote=${runtimeApi}, required=${LEGADO_RUNTIME_MINIMUM_API}`
        );
      }
      return {
        installed: parsed.installed === true,
        healthOk: parsed.healthOk === true,
        runtimeApi: runtimeApi,
        code: typeof parsed.code === 'number' ? parsed.code : 0,
        version: typeof parsed.version === 'string' ? parsed.version : '',
        activePath: this.activeDir,
        legadoEntryUrl: this.resolveStoredOrDefaultEntryUrl(parsed.legadoEntryUrl, LEGADO_RUNTIME_DEFAULT_ENTRY),
        rhinoEntryUrl: this.resolveStoredOrDefaultEntryUrl(parsed.rhinoEntryUrl, LEGADO_RUNTIME_RHINO_ENTRY),
        updatedAt: typeof parsed.updatedAt === 'number' ? parsed.updatedAt : 0,
        message: typeof parsed.message === 'string' ? parsed.message : ''
      };
    } catch (error) {
      logger.warn(TAG, `读取运行时状态失败: ${String(error)}`);
      return this.createFallbackStatus('运行时状态读取失败');
    }
  }

  getRuntimeEntryUrl(kind: LegadoRuntimeEntryKind): string {
    this.ensureInitialized();
    const status = this.getActiveRuntimeStatus();
    if (status.installed && status.healthOk) {
      if (kind === 'legado') {
        if (status.legadoEntryUrl.length > 0) {
          return status.legadoEntryUrl;
        }
      } else {
        if (status.rhinoEntryUrl.length > 0) {
          return status.rhinoEntryUrl;
        }
      }
    }
    if (kind === 'legado') {
      return 'resource://rawfile/legado_runtime.html';
    }
    return 'resource://rawfile/rhino_sandbox/index.html';
  }

  rollbackRuntime(): boolean {
    this.ensureInitialized();
    if (!SafeFileUtils.accessSync(this.rollbackDir)) {
      return false;
    }

    const tempDir = `${this.runtimeDir}/rollback_tmp`;
    try {
      LegadoCloudUpdateUtils.removePathRecursive(tempDir);
      if (SafeFileUtils.accessSync(this.activeDir)) {
        SafeFileUtils.renameSyncStrict(this.activeDir, tempDir);
      }
      SafeFileUtils.renameSyncStrict(this.rollbackDir, this.activeDir);
      LegadoCloudUpdateUtils.removePathRecursive(tempDir);
      const statusPath = `${this.activeDir}/${LEGADO_RUNTIME_STATUS_FILE}`;
      if (SafeFileUtils.accessSync(statusPath)) {
        const statusText = LegadoCloudUpdateUtils.readTextFile(statusPath, 256 * 1024);
        LegadoCloudUpdateUtils.writeTextFile(this.activeStatusPath, statusText);
      }
      return true;
    } catch (error) {
      logger.error(TAG, `运行时回滚失败: ${String(error)}`);
      try {
        if (!SafeFileUtils.accessSync(this.activeDir) && SafeFileUtils.accessSync(tempDir)) {
          SafeFileUtils.renameSyncStrict(tempDir, this.activeDir);
        }
      } catch (_) {
        // ignore restore failure
      }
      return false;
    }
  }

  async checkOfficialRepositoryUpdateIfNeeded(force: boolean = false): Promise<LegadoRuntimeRepositoryUpdateStatus> {
    this.ensureInitialized();
    const state = this.readUpdateState();
    const now = Date.now();
    if (!force && state.lastOfficialCheckAt > 0 && now - state.lastOfficialCheckAt < DAILY_CHECK_INTERVAL_MS) {
      return this.buildUpdateStatus(state);
    }

    const target = this.resolveOfficialVersionTarget();
    if (!target) {
      const missingState: LegadoRuntimeUpdateState = {
        lastOfficialCheckAt: now,
        hasOfficialUpdate: false,
        canCheckOfficialUpdate: false,
        latestCommitShortSha: '',
        latestCommitDate: '',
        errorMessage: '未找到官方运行时仓库版本配置'
      };
      this.writeUpdateState(missingState);
      return this.buildUpdateStatus(missingState);
    }

    try {
      const context = this.context;
      if (!context) {
        throw new Error('运行时资产管理器未初始化');
      }
      const versionManager = VersionHistoryManager.getInstance();
      await versionManager.initialize(context);
      const result = await versionManager.checkRepositoryUpdateByTarget(target);
      const newState: LegadoRuntimeUpdateState = {
        lastOfficialCheckAt: now,
        hasOfficialUpdate: result.hasUpdate,
        canCheckOfficialUpdate: result.canCheck,
        latestCommitShortSha: result.latestCommit ? result.latestCommit.shortSha : '',
        latestCommitDate: result.latestCommit ? result.latestCommit.date : '',
        errorMessage: result.errorMessage
      };
      this.writeUpdateState(newState);
      return this.buildUpdateStatus(newState);
    } catch (error) {
      const failedState: LegadoRuntimeUpdateState = {
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

  getRuntimeUpdateStatus(): LegadoRuntimeRepositoryUpdateStatus {
    this.ensureInitialized();
    return this.buildUpdateStatus(this.readUpdateState());
  }

  private async downloadRuntimeFile(
    route: LegadoRepositoryRouteResult,
    file: LegadoRuntimeAssetFile,
    log: (level: LegadoCloudLogLevel, message: string) => void
  ): Promise<void> {
    const downloadUrl = this.resolveRuntimeFileDownloadUrl(route, file);
    const downloadedBytes = await LegadoCloudUpdateUtils.downloadBytes(downloadUrl, 10000, 15000);
    const bytes = await this.prepareRuntimeFileBytes(file, downloadedBytes, log);
    await this.verifyFileSha256(file, bytes);
    const targetPath = LegadoCloudUpdateUtils.joinRelativePath(this.stagingDir, file.path);
    LegadoCloudUpdateUtils.writeBytesFile(targetPath, bytes);
  }

  private resolveRuntimeFileDownloadUrl(route: LegadoRepositoryRouteResult, file: LegadoRuntimeAssetFile): string {
    const url = file.url.trim();
    if (url.startsWith('http://') || url.startsWith('https://')) {
      if (route.proxyPrefix.length > 0) {
        return LegadoCloudUpdateUtils.buildRepositoryProxyUrl(route.proxyPrefix, url);
      }
      return url;
    }
    return LegadoCloudUpdateUtils.resolveRepositoryAssetUrl(route.effectiveUrl, LegadoCloudUpdateUtils.sanitizeRelativePath(url));
  }

  private async verifyFileSha256(file: LegadoRuntimeAssetFile, data: ArrayBuffer): Promise<void> {
    const expected = file.sha256.trim().toLowerCase();
    if (expected.length === 0) {
      return;
    }
    const actual = (await LegadoCloudUpdateUtils.sha256HexForArrayBuffer(data)).toLowerCase();
    if (actual !== expected) {
      throw new Error(`sha256不匹配: ${file.path}, expected=${expected}, actual=${actual}`);
    }
  }

  private async prepareRuntimeFileBytes(
    file: LegadoRuntimeAssetFile,
    data: ArrayBuffer,
    log: (level: LegadoCloudLogLevel, message: string) => void
  ): Promise<ArrayBuffer> {
    if (file.size <= 0 || data.byteLength === file.size) {
      return data;
    }

    const expectedHash = file.sha256.trim().toLowerCase();
    if (expectedHash.length > 0) {
      const actualHash = (await LegadoCloudUpdateUtils.sha256HexForArrayBuffer(data)).toLowerCase();
      if (actualHash === expectedHash) {
        log('warn', `运行时文件大小与索引不一致但sha256通过: ${file.path}, expected=${file.size}, actual=${data.byteLength}`);
        return data;
      }

      if (this.isTextRuntimeFile(file)) {
        const normalizedBytes = this.normalizeTextRuntimeFileBytes(data);
        if (normalizedBytes.byteLength === file.size) {
          const normalizedHash = (await LegadoCloudUpdateUtils.sha256HexForArrayBuffer(normalizedBytes)).toLowerCase();
          if (normalizedHash === expectedHash) {
            log('warn', `运行时文本文件已按索引换行格式归一化: ${file.path}, downloaded=${data.byteLength}, normalized=${normalizedBytes.byteLength}`);
            return normalizedBytes;
          }
        }
      }
    }

    throw new Error(`文件大小不匹配: ${file.path}, expected=${file.size}, actual=${data.byteLength}`);
  }

  private isTextRuntimeFile(file: LegadoRuntimeAssetFile): boolean {
    const mimeType = file.mimeType.trim().toLowerCase();
    const path = file.path.trim().toLowerCase();
    return mimeType.startsWith('text/')
      || mimeType.indexOf('javascript') >= 0
      || mimeType.indexOf('json') >= 0
      || path.endsWith('.html')
      || path.endsWith('.js')
      || path.endsWith('.json')
      || path.endsWith('.md')
      || path.endsWith('.css');
  }

  private normalizeTextRuntimeFileBytes(data: ArrayBuffer): ArrayBuffer {
    const text = LegadoCloudUpdateUtils.decodeUtf8FromArrayBuffer(data);
    const normalizedLf = text.replace(/\r\n/g, '\n').replace(/\r/g, '\n');
    const normalizedCrlf = normalizedLf.replace(/\n/g, '\r\n');
    return LegadoCloudUpdateUtils.encodeUtf8ToArrayBuffer(normalizedCrlf);
  }

  private validateRuntimeHealth(rootDir: string, index: LegadoRuntimeAssetIndex): void {
    for (const file of index.files) {
      const targetPath = LegadoCloudUpdateUtils.joinRelativePath(rootDir, file.path);
      if (file.required && !SafeFileUtils.accessSync(targetPath)) {
        throw new Error(`缺少必需运行时文件: ${file.path}`);
      }
    }

    const entryPath = LegadoCloudUpdateUtils.joinRelativePath(rootDir, this.resolveLegadoEntryPath(index));
    if (!SafeFileUtils.accessSync(entryPath)) {
      throw new Error(`缺少Legado运行时入口: ${this.resolveLegadoEntryPath(index)}`);
    }
    const entryText = LegadoCloudUpdateUtils.readTextFile(entryPath, 5 * 1024 * 1024);
    if (!entryText.includes('__manxiaLegadoRuntimeExecute')) {
      throw new Error('Legado运行时入口缺少执行函数');
    }
  }

  private switchStagingToActive(): void {
    LegadoCloudUpdateUtils.removePathRecursive(this.rollbackDir);
    if (SafeFileUtils.accessSync(this.activeDir)) {
      SafeFileUtils.renameSyncStrict(this.activeDir, this.rollbackDir);
    }

    try {
      SafeFileUtils.renameSyncStrict(this.stagingDir, this.activeDir);
    } catch (error) {
      if (SafeFileUtils.accessSync(this.rollbackDir) && !SafeFileUtils.accessSync(this.activeDir)) {
        SafeFileUtils.renameSyncStrict(this.rollbackDir, this.activeDir);
      }
      throw error as Error;
    }
  }

  private writeStatusFile(rootDir: string, index: LegadoRuntimeAssetIndex, healthOk: boolean, message: string): void {
    const status = this.buildActiveStatus(index, rootDir, healthOk, message);
    LegadoCloudUpdateUtils.writeTextFile(`${rootDir}/${LEGADO_RUNTIME_STATUS_FILE}`, JSON.stringify(status, null, 2));
  }

  private writeActiveRootStatus(index: LegadoRuntimeAssetIndex, healthOk: boolean, message: string): void {
    const status = this.buildActiveStatus(index, this.activeDir, healthOk, message);
    LegadoCloudUpdateUtils.writeTextFile(this.activeStatusPath, JSON.stringify(status, null, 2));
  }

  private buildActiveStatus(
    index: LegadoRuntimeAssetIndex,
    activePath: string,
    healthOk: boolean,
    message: string
  ): LegadoRuntimeActiveStatus {
    return {
      installed: true,
      healthOk: healthOk,
      runtimeApi: index.runtimeApi,
      code: index.code,
      version: index.version,
      activePath: activePath,
      legadoEntryUrl: LegadoCloudUpdateUtils.toFileUrl(`${activePath}/${this.resolveLegadoEntryPath(index)}`),
      rhinoEntryUrl: SafeFileUtils.accessSync(`${activePath}/${LEGADO_RUNTIME_RHINO_ENTRY}`)
        ? LegadoCloudUpdateUtils.toFileUrl(`${activePath}/${LEGADO_RUNTIME_RHINO_ENTRY}`)
        : '',
      updatedAt: Date.now(),
      message: message
    };
  }

  private createFallbackStatus(message: string): LegadoRuntimeActiveStatus {
    return {
      installed: false,
      healthOk: false,
      runtimeApi: 0,
      code: 0,
      version: '',
      activePath: '',
      legadoEntryUrl: 'resource://rawfile/legado_runtime.html',
      rhinoEntryUrl: 'resource://rawfile/rhino_sandbox/index.html',
      updatedAt: 0,
      message: message
    };
  }

  private resolveActiveEntryUrl(relativePath: string): string {
    const targetPath = LegadoCloudUpdateUtils.joinRelativePath(this.activeDir, relativePath);
    if (!SafeFileUtils.accessSync(targetPath)) {
      return '';
    }
    return LegadoCloudUpdateUtils.toFileUrl(targetPath);
  }

  private resolveStoredOrDefaultEntryUrl(storedUrl: string, fallbackRelativePath: string): string {
    if (typeof storedUrl === 'string' && storedUrl.startsWith('file://')) {
      const path = storedUrl.substring('file://'.length);
      if (SafeFileUtils.accessSync(path)) {
        return storedUrl;
      }
    }
    return this.resolveActiveEntryUrl(fallbackRelativePath);
  }

  private resolveLegadoEntryPath(index: LegadoRuntimeAssetIndex): string {
    const entry = index.entry.trim();
    if (entry.length === 0) {
      return LEGADO_RUNTIME_DEFAULT_ENTRY;
    }
    return LegadoCloudUpdateUtils.sanitizeRelativePath(entry);
  }

  private parseAndValidateIndex(indexText: string): LegadoRuntimeAssetIndex {
    const parsed = JSON.parse(indexText) as LegadoRuntimeAssetIndex;
    if (!parsed || typeof parsed !== 'object') {
      throw new Error('运行时索引不是有效对象');
    }
    this.requireString(parsed.schemaVersion, 'schemaVersion');
    this.requireNumber(parsed.runtimeApi, 'runtimeApi');
    this.requireNumber(parsed.code, 'code');
    this.requireString(parsed.version, 'version');
    this.requireNumber(parsed.minAppVersionCode, 'minAppVersionCode');
    this.requireString(parsed.entry, 'entry');
    if (!Array.isArray(parsed.files)) {
      throw new Error('files 类型错误');
    }

    const files: LegadoRuntimeAssetFile[] = [];
    for (let i = 0; i < parsed.files.length; i++) {
      files.push(this.validateFile(parsed.files[i], i));
    }
    return {
      schemaVersion: parsed.schemaVersion,
      runtimeApi: parsed.runtimeApi,
      code: parsed.code,
      version: parsed.version,
      minAppVersionCode: parsed.minAppVersionCode,
      entry: parsed.entry,
      files: files
    };
  }

  private validateFile(file: LegadoRuntimeAssetFile, index: number): LegadoRuntimeAssetFile {
    if (!file || typeof file !== 'object') {
      throw new Error(`files[${index}] 不是有效对象`);
    }
    this.requireString(file.path, `files[${index}].path`);
    this.requireString(file.url, `files[${index}].url`);
    this.requireString(file.sha256, `files[${index}].sha256`, true);
    this.requireNumber(file.size, `files[${index}].size`);
    this.requireString(file.mimeType, `files[${index}].mimeType`, true);
    this.requireBoolean(file.required, `files[${index}].required`);
    LegadoCloudUpdateUtils.sanitizeRelativePath(file.path);
    return file;
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

  private async ensureRuntimeCompatible(index: LegadoRuntimeAssetIndex): Promise<void> {
    if (index.runtimeApi < LEGADO_RUNTIME_MINIMUM_API) {
      throw new Error(`运行时 API 过低: remote=${index.runtimeApi}, required=${LEGADO_RUNTIME_MINIMUM_API}`);
    }
    if (index.runtimeApi > LEGADO_RUNTIME_SUPPORTED_API) {
      throw new Error(`运行时 API 不兼容: remote=${index.runtimeApi}, supported=${LEGADO_RUNTIME_SUPPORTED_API}`);
    }
    const appVersionCode = await AppInfoManager.getInstance().getVersionCode();
    if (appVersionCode > 0 && index.minAppVersionCode > appVersionCode) {
      throw new Error(`当前应用版本过低，需要 ${index.minAppVersionCode}`);
    }
  }

  private ensureInitialized(): void {
    if (!this.context || this.runtimeDir.length === 0) {
      throw new Error('Legado运行时资产管理器未初始化');
    }
  }

  private ensureUpdateStateFileExists(): void {
    if (SafeFileUtils.accessSync(this.updateStatePath)) {
      return;
    }
    this.writeUpdateState(this.createEmptyUpdateState());
  }

  private createEmptyUpdateState(): LegadoRuntimeUpdateState {
    return {
      lastOfficialCheckAt: 0,
      hasOfficialUpdate: false,
      canCheckOfficialUpdate: false,
      latestCommitShortSha: '',
      latestCommitDate: '',
      errorMessage: ''
    };
  }

  private readUpdateState(): LegadoRuntimeUpdateState {
    try {
      const text = LegadoCloudUpdateUtils.readTextFile(this.updateStatePath, 256 * 1024);
      const parsed = SafeUtils.parseObj<LegadoRuntimeUpdateState>(text);
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
      logger.warn(TAG, `读取运行时更新状态失败: ${String(error)}`);
    }
    return this.createEmptyUpdateState();
  }

  private writeUpdateState(state: LegadoRuntimeUpdateState): void {
    LegadoCloudUpdateUtils.writeTextFile(this.updateStatePath, JSON.stringify(state, null, 2));
  }

  private buildUpdateStatus(state: LegadoRuntimeUpdateState): LegadoRuntimeRepositoryUpdateStatus {
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
      (item: VersionCommitRepositoryTarget) => item.key === MANXIA_LEGADO_RUNTIME_REPOSITORY_KEY
    );
    return target || null;
  }

  private async markOfficialRuntimeVersionIfPossible(url: string): Promise<void> {
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
      logger.warn(TAG, `记录官方运行时仓库版本失败: ${String(error)}`);
    }
  }
}

export function getLegadoRuntimeAssetManager(): LegadoRuntimeAssetManager {
  return LegadoRuntimeAssetManager.getInstance();
}
