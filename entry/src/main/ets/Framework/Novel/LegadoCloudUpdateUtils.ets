import { Context } from '@kit.AbilityKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { fileIo } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { SafeFileUtils } from 'manxia_core/src/main/ets/Utils/SafeFileUtils';
import { ProxyManager } from 'manxia_core/src/main/ets/Framework/Network/ProxyManager';

const TAG = 'LegadoCloudUpdateUtils';
const REPOSITORY_PROXY_GH: string = 'https://gh-proxy.org/';
const REPOSITORY_PROXY_HK_GH: string = 'https://hk.gh-proxy.org/';
const REPOSITORY_CONNECT_TIMEOUT_MS: number = 2500;
const REPOSITORY_READ_TIMEOUT_MS: number = 2500;

export type LegadoCloudLogLevel = 'info' | 'warn' | 'error';
export type LegadoRepositoryCandidateKind = 'origin' | 'ghProxy' | 'hkGhProxy';
export type LegadoRepositoryRouteLogCallback = (level: LegadoCloudLogLevel, message: string) => void;

export interface LegadoRepositoryRouteCandidate {
  kind: LegadoRepositoryCandidateKind;
  url: string;
}

export interface LegadoRepositoryConnectivityCheckResult {
  reachable: boolean;
  responseCode: number;
  errorMessage: string;
}

export interface LegadoRepositoryProbeResult {
  candidate: LegadoRepositoryRouteCandidate;
  check: LegadoRepositoryConnectivityCheckResult;
}

export interface LegadoRepositoryRouteResult {
  originalUrl: string;
  effectiveUrl: string;
  usedProxy: boolean;
  proxyPrefix: string;
}

export interface LegadoRepositoryProxyUnwrapResult {
  proxyPrefix: string;
  rawUrl: string;
}

export interface LegadoRepositoryUrlSplitResult {
  baseUrl: string;
  query: string;
}

export class LegadoCloudUpdateUtils {
  static getFilesDir(context: Context): string {
    return context.filesDir;
  }

  static normalizeRepositoryUrl(url: string): string {
    if (!url) {
      return '';
    }
    return url.trim();
  }

  static splitRepositoryUrlQuery(url: string): LegadoRepositoryUrlSplitResult {
    const queryIndex = url.indexOf('?');
    if (queryIndex < 0) {
      return {
        baseUrl: url,
        query: ''
      };
    }
    return {
      baseUrl: url.substring(0, queryIndex),
      query: url.substring(queryIndex)
    };
  }

  static unwrapRepositoryProxyUrl(url: string): LegadoRepositoryProxyUnwrapResult {
    const normalizedUrl = LegadoCloudUpdateUtils.normalizeRepositoryUrl(url);
    const proxyPrefixes = LegadoCloudUpdateUtils.getRepositoryProxyPrefixes();
    for (const prefix of proxyPrefixes) {
      if (normalizedUrl.startsWith(prefix)) {
        return {
          proxyPrefix: prefix,
          rawUrl: normalizedUrl.substring(prefix.length)
        };
      }
    }
    return {
      proxyPrefix: '',
      rawUrl: normalizedUrl
    };
  }

  static buildRepositoryProxyUrl(proxyPrefix: string, rawUrl: string): string {
    if (!proxyPrefix || !rawUrl) {
      return rawUrl;
    }
    if (rawUrl.startsWith(proxyPrefix)) {
      return rawUrl;
    }
    return `${proxyPrefix}${rawUrl}`;
  }

  static resolveRepositoryAssetUrl(indexUrl: string, relativePath: string): string {
    if (!indexUrl) {
      return relativePath;
    }

    const splitResult = LegadoCloudUpdateUtils.splitRepositoryUrlQuery(indexUrl);
    const unwrapped = LegadoCloudUpdateUtils.unwrapRepositoryProxyUrl(splitResult.baseUrl);
    const cleanInnerIndexUrl = unwrapped.rawUrl;
    const lastSlashIndex = cleanInnerIndexUrl.lastIndexOf('/');
    const rawBaseUrl = lastSlashIndex >= 0
      ? cleanInnerIndexUrl.substring(0, lastSlashIndex + 1)
      : `${cleanInnerIndexUrl}/`;
    const rawAssetUrl = `${rawBaseUrl}${relativePath}`;
    if (!unwrapped.proxyPrefix) {
      return rawAssetUrl;
    }
    return LegadoCloudUpdateUtils.buildRepositoryProxyUrl(unwrapped.proxyPrefix, rawAssetUrl);
  }

  static async resolveBestRepositoryUrl(
    url: string,
    log?: LegadoRepositoryRouteLogCallback
  ): Promise<LegadoRepositoryRouteResult> {
    const candidates = LegadoCloudUpdateUtils.buildRepositoryRouteCandidates(url);
    if (candidates.length === 0) {
      throw new Error('仓库地址无效');
    }

    const probeTasks: Promise<LegadoRepositoryProbeResult>[] = [];
    for (const candidate of candidates) {
      probeTasks.push(LegadoCloudUpdateUtils.probeRepositoryCandidate(candidate));
    }
    const probeResults = await Promise.all(probeTasks);

    let selected: LegadoRepositoryRouteCandidate | null = null;
    for (const candidate of candidates) {
      const matched = probeResults.find((result: LegadoRepositoryProbeResult) => result.candidate.url === candidate.url);
      if (matched && matched.check.reachable) {
        selected = candidate;
        break;
      }
    }

    for (const probeResult of probeResults) {
      const label = LegadoCloudUpdateUtils.getRepositoryCandidateLabel(probeResult.candidate.kind);
      if (probeResult.check.reachable) {
        log?.('info', `仓库连通性通过(${label}): ${probeResult.candidate.url}`);
      } else {
        const detail = LegadoCloudUpdateUtils.buildRepositoryConnectivityDetail(probeResult.check);
        if (!selected || (probeResult.candidate.kind === 'origin' && selected.kind !== 'origin')) {
          log?.('warn', `仓库连通性失败(${label}): ${probeResult.candidate.url} (${detail})`);
        } else {
          log?.('info', `备用仓库连通性不可用(${label}): ${probeResult.candidate.url} (${detail})`);
        }
      }
    }

    if (!selected) {
      throw new Error('原始地址和加速代理均不可连通');
    }

    const splitResult = LegadoCloudUpdateUtils.splitRepositoryUrlQuery(
      LegadoCloudUpdateUtils.normalizeRepositoryUrl(url)
    );
    const unwrappedOriginal = LegadoCloudUpdateUtils.unwrapRepositoryProxyUrl(splitResult.baseUrl);
    const originalUrl = `${unwrappedOriginal.rawUrl}${splitResult.query}`;
    const selectedUnwrapped = LegadoCloudUpdateUtils.unwrapRepositoryProxyUrl(selected.url);
    return {
      originalUrl: originalUrl,
      effectiveUrl: selected.url,
      usedProxy: selected.kind !== 'origin',
      proxyPrefix: selectedUnwrapped.proxyPrefix
    };
  }

  static async downloadText(url: string, connectTimeout: number = 10000, readTimeout: number = 10000): Promise<string> {
    const request = http.createHttp();
    try {
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: connectTimeout,
        readTimeout: readTimeout,
        header: {
          'Accept': 'application/json,text/plain,*/*'
        }
      };
      const proxyManager = ProxyManager.getInstance();
      if (proxyManager.isEnabled()) {
        await proxyManager.applyToHttpOptions(options, url);
      }
      const response = await request.request(url, options);
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error(`HTTP ${response.responseCode}`);
      }
      if (typeof response.result === 'string') {
        return response.result;
      }
      return JSON.stringify(response.result);
    } finally {
      try {
        request.destroy();
      } catch (_) {
        // ignore
      }
    }
  }

  static async downloadBytes(url: string, connectTimeout: number = 10000, readTimeout: number = 10000): Promise<ArrayBuffer> {
    const request = http.createHttp();
    try {
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: connectTimeout,
        readTimeout: readTimeout,
        header: {
          'Accept': '*/*'
        }
      };
      const proxyManager = ProxyManager.getInstance();
      if (proxyManager.isEnabled()) {
        await proxyManager.applyToHttpOptions(options, url);
      }
      const response = await request.request(url, options);
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error(`HTTP ${response.responseCode}`);
      }
      const result = response.result;
      if (result instanceof ArrayBuffer) {
        return result;
      }
      if (typeof result === 'string') {
        return LegadoCloudUpdateUtils.encodeUtf8ToArrayBuffer(result);
      }
      throw new Error(`响应数据类型不是二进制: ${response.resultType}`);
    } finally {
      try {
        request.destroy();
      } catch (_) {
        // ignore
      }
    }
  }

  static ensureDirectoryExists(dirPath: string): void {
    if (!dirPath) {
      throw new Error('目录路径不能为空');
    }
    if (SafeFileUtils.accessSync(dirPath)) {
      return;
    }
    SafeFileUtils.mkdirSyncStrict(dirPath, true);
  }

  static ensureParentDirectory(filePath: string): void {
    const slashIndex = filePath.lastIndexOf('/');
    if (slashIndex <= 0) {
      return;
    }
    LegadoCloudUpdateUtils.ensureDirectoryExists(filePath.substring(0, slashIndex));
  }

  static readTextFile(filePath: string, maxBytes: number = 20 * 1024 * 1024): string {
    const file = SafeFileUtils.openSyncStrict(filePath, fileIo.OpenMode.READ_ONLY);
    try {
      const stat = SafeFileUtils.statSyncStrict(file.fd);
      if (stat.size > maxBytes) {
        throw new Error(`文件过大: ${stat.size}`);
      }
      const buffer = new ArrayBuffer(stat.size);
      SafeFileUtils.readExactSync(file.fd, buffer, { length: stat.size });
      const decoder = new util.TextDecoder('utf-8', { ignoreBOM: true });
      return decoder.decodeToString(new Uint8Array(buffer));
    } finally {
      SafeFileUtils.closeSync(file);
    }
  }

  static writeTextFile(filePath: string, content: string): void {
    LegadoCloudUpdateUtils.ensureParentDirectory(filePath);
    const encoder = new util.TextEncoder();
    const bytes = encoder.encodeInto(content);
    const file = SafeFileUtils.openSyncStrict(
      filePath,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC
    );
    try {
      SafeFileUtils.writeExactSync(file.fd, bytes.buffer, { length: bytes.byteLength });
    } finally {
      SafeFileUtils.closeSync(file);
    }
  }

  static readBytesFile(filePath: string, maxBytes: number = 50 * 1024 * 1024): ArrayBuffer {
    const file = SafeFileUtils.openSyncStrict(filePath, fileIo.OpenMode.READ_ONLY);
    try {
      const stat = SafeFileUtils.statSyncStrict(file.fd);
      if (stat.size > maxBytes) {
        throw new Error(`文件过大: ${stat.size}`);
      }
      const buffer = new ArrayBuffer(stat.size);
      SafeFileUtils.readExactSync(file.fd, buffer, { length: stat.size });
      return buffer;
    } finally {
      SafeFileUtils.closeSync(file);
    }
  }

  static writeBytesFile(filePath: string, data: ArrayBuffer): void {
    LegadoCloudUpdateUtils.ensureParentDirectory(filePath);
    const file = SafeFileUtils.openSyncStrict(
      filePath,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC
    );
    try {
      SafeFileUtils.writeExactSync(file.fd, data, { length: data.byteLength });
    } finally {
      SafeFileUtils.closeSync(file);
    }
  }

  static removePathRecursive(path: string): void {
    if (!path || !SafeFileUtils.accessSync(path)) {
      return;
    }
    const stat = SafeFileUtils.statSyncStrict(path);
    if (stat.isDirectory()) {
      const children = SafeFileUtils.listFileSync(path);
      for (const child of children) {
        LegadoCloudUpdateUtils.removePathRecursive(`${path}/${child}`);
      }
      SafeFileUtils.rmdirSync(path);
      return;
    }
    SafeFileUtils.unlinkSync(path);
  }

  static copyPathRecursive(sourcePath: string, targetPath: string): void {
    const stat = SafeFileUtils.statSyncStrict(sourcePath);
    if (stat.isDirectory()) {
      LegadoCloudUpdateUtils.ensureDirectoryExists(targetPath);
      const children = SafeFileUtils.listFileSync(sourcePath);
      for (const child of children) {
        LegadoCloudUpdateUtils.copyPathRecursive(`${sourcePath}/${child}`, `${targetPath}/${child}`);
      }
      return;
    }
    LegadoCloudUpdateUtils.ensureParentDirectory(targetPath);
    SafeFileUtils.copyFileSyncStrict(sourcePath, targetPath);
  }

  static sanitizeRelativePath(path: string): string {
    const normalized = path.trim().replace(/\\/g, '/');
    if (normalized.length === 0) {
      throw new Error('相对路径不能为空');
    }
    if (normalized.startsWith('/') || normalized.includes(':')) {
      throw new Error(`非法相对路径: ${path}`);
    }
    const parts = normalized.split('/');
    const cleanParts: string[] = [];
    for (const part of parts) {
      if (!part || part === '.') {
        continue;
      }
      if (part === '..') {
        throw new Error(`非法相对路径: ${path}`);
      }
      cleanParts.push(part);
    }
    if (cleanParts.length === 0) {
      throw new Error(`非法相对路径: ${path}`);
    }
    return cleanParts.join('/');
  }

  static joinRelativePath(baseDir: string, relativePath: string): string {
    return `${baseDir}/${LegadoCloudUpdateUtils.sanitizeRelativePath(relativePath)}`;
  }

  static toFileUrl(path: string): string {
    if (!path) {
      return '';
    }
    if (path.startsWith('file://')) {
      return path;
    }
    return `file://${path}`;
  }

  static async sha256HexForString(value: string): Promise<string> {
    const bytes = new Uint8Array(LegadoCloudUpdateUtils.encodeUtf8ToArrayBuffer(value));
    return await LegadoCloudUpdateUtils.sha256HexForBytes(bytes);
  }

  static async sha256HexForArrayBuffer(data: ArrayBuffer): Promise<string> {
    return await LegadoCloudUpdateUtils.sha256HexForBytes(new Uint8Array(data));
  }

  static decodeUtf8FromArrayBuffer(data: ArrayBuffer): string {
    const decoder = new util.TextDecoder('utf-8', { ignoreBOM: true });
    return decoder.decodeToString(new Uint8Array(data));
  }

  static encodeUtf8ToArrayBuffer(value: string): ArrayBuffer {
    const encoder = new util.TextEncoder();
    const bytes = encoder.encodeInto(value);
    const buffer = new ArrayBuffer(bytes.length);
    new Uint8Array(buffer).set(bytes);
    return buffer;
  }

  static extractErrorMessage(error: Object | string | number | boolean | null | undefined): string {
    if (error === undefined || error === null) {
      return '未知错误';
    }
    if (typeof error === 'string' || typeof error === 'number' || typeof error === 'boolean') {
      return String(error);
    }
    if (error instanceof Error) {
      return error.message || error.name || 'Error';
    }
    try {
      const text = JSON.stringify(error);
      return text && text !== '{}' ? text : String(error);
    } catch (_) {
      return String(error);
    }
  }

  static generateRepositoryId(url: string): string {
    let hash = 0;
    for (let i = 0; i < url.length; i++) {
      const char = url.charCodeAt(i);
      hash = ((hash << 5) - hash) + char;
      hash = hash & hash;
    }
    return `repo_${Math.abs(hash)}`;
  }

  private static getRepositoryProxyPrefixes(): string[] {
    return [REPOSITORY_PROXY_GH, REPOSITORY_PROXY_HK_GH];
  }

  private static getRepositoryCandidateKindByPrefix(prefix: string): LegadoRepositoryCandidateKind {
    if (prefix === REPOSITORY_PROXY_HK_GH) {
      return 'hkGhProxy';
    }
    return 'ghProxy';
  }

  private static getRepositoryCandidateLabel(kind: LegadoRepositoryCandidateKind): string {
    if (kind === 'origin') {
      return 'origin';
    }
    if (kind === 'ghProxy') {
      return 'gh-proxy';
    }
    return 'hk-gh-proxy';
  }

  private static buildRepositoryConnectivityDetail(check: LegadoRepositoryConnectivityCheckResult): string {
    if (check.responseCode > 0) {
      return `HTTP ${check.responseCode}`;
    }
    if (check.errorMessage.length > 0) {
      return check.errorMessage;
    }
    return '连接失败';
  }

  private static addRepositoryRouteCandidate(
    candidates: LegadoRepositoryRouteCandidate[],
    seen: Set<string>,
    candidate: LegadoRepositoryRouteCandidate
  ): void {
    const normalizedCandidateUrl = LegadoCloudUpdateUtils.normalizeRepositoryUrl(candidate.url);
    if (!normalizedCandidateUrl || seen.has(normalizedCandidateUrl)) {
      return;
    }
    seen.add(normalizedCandidateUrl);
    candidates.push({
      kind: candidate.kind,
      url: normalizedCandidateUrl
    });
  }

  private static buildRepositoryRouteCandidates(url: string): LegadoRepositoryRouteCandidate[] {
    const normalizedInputUrl = LegadoCloudUpdateUtils.normalizeRepositoryUrl(url);
    if (!normalizedInputUrl) {
      return [];
    }

    const splitResult = LegadoCloudUpdateUtils.splitRepositoryUrlQuery(normalizedInputUrl);
    const unwrapped = LegadoCloudUpdateUtils.unwrapRepositoryProxyUrl(splitResult.baseUrl);
    const originalUrl = `${unwrapped.rawUrl}${splitResult.query}`;

    const candidates: LegadoRepositoryRouteCandidate[] = [];
    const seen = new Set<string>();
    LegadoCloudUpdateUtils.addRepositoryRouteCandidate(candidates, seen, {
      kind: 'origin',
      url: originalUrl
    });
    const proxyPrefixes = LegadoCloudUpdateUtils.getRepositoryProxyPrefixes();
    for (const proxyPrefix of proxyPrefixes) {
      LegadoCloudUpdateUtils.addRepositoryRouteCandidate(candidates, seen, {
        kind: LegadoCloudUpdateUtils.getRepositoryCandidateKindByPrefix(proxyPrefix),
        url: LegadoCloudUpdateUtils.buildRepositoryProxyUrl(proxyPrefix, originalUrl)
      });
    }
    return candidates;
  }

  private static async quickCheckRepositoryConnectivity(url: string): Promise<LegadoRepositoryConnectivityCheckResult> {
    const request = http.createHttp();
    try {
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        connectTimeout: REPOSITORY_CONNECT_TIMEOUT_MS,
        readTimeout: REPOSITORY_READ_TIMEOUT_MS,
        header: {
          'Accept': 'application/json,text/plain,*/*'
        }
      };
      const proxyManager = ProxyManager.getInstance();
      if (proxyManager.isEnabled()) {
        await proxyManager.applyToHttpOptions(options, url);
      }
      const response = await request.request(url, options);
      return {
        reachable: response.responseCode >= 200 && response.responseCode < 400,
        responseCode: response.responseCode,
        errorMessage: ''
      };
    } catch (error) {
      return {
        reachable: false,
        responseCode: 0,
        errorMessage: LegadoCloudUpdateUtils.extractErrorMessage(error as Object)
      };
    } finally {
      try {
        request.destroy();
      } catch (_) {
        // ignore
      }
    }
  }

  private static async probeRepositoryCandidate(
    candidate: LegadoRepositoryRouteCandidate
  ): Promise<LegadoRepositoryProbeResult> {
    const check = await LegadoCloudUpdateUtils.quickCheckRepositoryConnectivity(candidate.url);
    return {
      candidate: candidate,
      check: check
    };
  }

  private static async sha256HexForBytes(bytes: Uint8Array): Promise<string> {
    const md = cryptoFramework.createMd('SHA256');
    await md.update({ data: bytes });
    const result = await md.digest();
    return LegadoCloudUpdateUtils.bytesToHex(result.data);
  }

  private static bytesToHex(bytes: Uint8Array): string {
    const table = '0123456789abcdef';
    let result = '';
    for (let i = 0; i < bytes.length; i++) {
      const value = bytes[i];
      result += table.charAt(value >>> 4);
      result += table.charAt(value & 0x0f);
    }
    return result;
  }
}

export function logLegadoCloudMessage(level: LegadoCloudLogLevel, tag: string, message: string): void {
  if (level === 'info') {
    logger.info(tag, message);
    return;
  }
  if (level === 'warn') {
    logger.warn(tag, message);
    return;
  }
  logger.error(tag, message);
}
