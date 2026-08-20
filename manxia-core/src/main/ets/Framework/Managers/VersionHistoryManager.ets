import { SafeFileUtils } from 'manxia_core/src/main/ets/Utils/SafeFileUtils';
import { SafeUtils } from 'manxia_core/src/main/ets/Utils/SafeUtils';
/**
 * 版本记录管理器
 * 负责获取 GitHub 提交记录、根据网络情况切换加速代理、并缓存历史提交
 */

import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { fileIo } from '@kit.CoreFileKit';
import { Context } from '@kit.AbilityKit';
import { http } from '@kit.NetworkKit';
import { IProxyManagerFacade, ProxyManagerHolder } from 'manxia_core/src/main/ets/Framework/Contracts/ProxyManagerFacade';

const TAG = 'VersionHistoryManager';
const VERSION_HISTORY_DIR = 'version-history';
const VERSION_HISTORY_CACHE_FILE = 'commit_cache.json';
const VERSION_HISTORY_CACHE_VERSION = '1.0.0';
const VERSION_HISTORY_DEFAULT_FETCH_LIMIT = 10;
const VERSION_HISTORY_MAX_CACHE_SIZE = 200;

const REPOSITORY_PROXY_GH: string = 'https://gh-proxy.org/';
const REPOSITORY_PROXY_HK_GH: string = 'https://hk.gh-proxy.org/';
const REPOSITORY_CONNECT_TIMEOUT_MS: number = 2500;
const REPOSITORY_READ_TIMEOUT_MS: number = 2500;

type RepositoryCandidateKind = 'origin' | 'ghProxy' | 'hkGhProxy';

interface RepositoryRouteCandidate {
  kind: RepositoryCandidateKind;
  url: string;
}

interface RepositoryConnectivityCheckResult {
  reachable: boolean;
  responseCode: number;
  errorMessage: string;
}

interface RepositoryProbeResult {
  candidate: RepositoryRouteCandidate;
  check: RepositoryConnectivityCheckResult;
}

interface RepositoryRouteResult {
  originalUrl: string;
  effectiveUrl: string;
  usedProxy: boolean;
  proxyPrefix: string;
}

interface RepositoryProxyUnwrapResult {
  proxyPrefix: string;
  rawUrl: string;
}

interface RepositoryUrlSplitResult {
  baseUrl: string;
  query: string;
}

interface GitHubCommitAuthor {
  name?: string;
  date?: string;
}

interface GitHubCommitNode {
  message?: string;
  author?: GitHubCommitAuthor;
}

interface GitHubAuthorNode {
  login?: string;
}

interface GitHubCommitResponseItem {
  sha?: string;
  html_url?: string;
  commit?: GitHubCommitNode;
  author?: GitHubAuthorNode | null;
}

interface GitHubCommitFileResponseItem {
  filename?: string;
  status?: string;
  additions?: number;
  deletions?: number;
  changes?: number;
}

interface GitHubCommitDetailResponseItem {
  sha?: string;
  html_url?: string;
  commit?: GitHubCommitNode;
  author?: GitHubAuthorNode | null;
  files?: GitHubCommitFileResponseItem[];
}

interface VersionHistoryCacheRepository {
  key: string;
  name: string;
  commitsPageUrl: string;
  lastFetchedAt: number;
  commits: VersionCommitRecord[];
}

interface VersionHistoryCacheData {
  version: string;
  updatedAt: number;
  repositories: VersionHistoryCacheRepository[];
  repositoryMarkers: VersionRepositoryVersionMarker[];
}

export interface VersionCommitRepositoryTarget {
  key: string;
  name: string;
  owner: string;
  repo: string;
  branch: string;
  commitsPageUrl: string;
}

export interface VersionCommitRecord {
  sha: string;
  shortSha: string;
  message: string;
  summary: string;
  title: string;
  body: string;
  authorName: string;
  authorLogin: string;
  date: string;
  timestamp: number;
  htmlUrl: string;
  files: VersionCommitFileChange[];
  detailLoaded: boolean;
  detailLoading: boolean;
  detailError: string;
}

export interface VersionCommitFileChange {
  filename: string;
  status: string;
  additions: number;
  deletions: number;
  changes: number;
}

export interface VersionCommitDetail {
  sha: string;
  message: string;
  title: string;
  body: string;
  htmlUrl: string;
  authorName: string;
  authorLogin: string;
  date: string;
  timestamp: number;
  files: VersionCommitFileChange[];
}

export interface VersionCommitRepositoryResult {
  key: string;
  name: string;
  apiUrl: string;
  effectiveApiUrl: string;
  commitsPageUrl: string;
  commits: VersionCommitRecord[];
  lastFetchedAt: number;
  networkUpdated: boolean;
  usingCache: boolean;
  usedProxy: boolean;
  errorMessage: string;
}

export interface VersionRepositoryVersionMarker {
  key: string;
  name: string;
  commitSha: string;
  commitShortSha: string;
  commitTimestamp: number;
  commitDate: string;
  repositoryUrl: string;
  markedAt: number;
}

export interface VersionRepositoryUpdateCheckResult {
  canCheck: boolean;
  hasUpdate: boolean;
  key: string;
  name: string;
  localMarker: VersionRepositoryVersionMarker | null;
  latestCommit: VersionCommitRecord | null;
  errorMessage: string;
}

export const DEFAULT_VERSION_COMMIT_FETCH_LIMIT = VERSION_HISTORY_DEFAULT_FETCH_LIMIT;
export const MANXIA_EXTENSIONS_REPOSITORY_KEY = 'manxia_extensions';
export const MANXIA_LEGADO_SOURCES_REPOSITORY_KEY = 'manxia_legado_sources';
export const MANXIA_LEGADO_RUNTIME_REPOSITORY_KEY = 'manxia_legado_runtime';

export const DEFAULT_VERSION_COMMIT_REPOSITORIES: VersionCommitRepositoryTarget[] = [
  {
    key: 'manxia',
    name: '漫匣',
    owner: 'DaLongZhuaZi',
    repo: 'manxia',
    branch: 'main',
    commitsPageUrl: 'https://github.com/DaLongZhuaZi/manxia/commits/main/'
  },
  {
    key: 'manxia_extensions',
    name: '漫匣图源',
    owner: 'DaLongZhuaZi',
    repo: 'manxia-extensions-source',
    branch: 'master',
    commitsPageUrl: 'https://github.com/DaLongZhuaZi/manxia-extensions-source/commits/master/'
  },
  {
    key: MANXIA_LEGADO_SOURCES_REPOSITORY_KEY,
    name: '漫匣Legado书源',
    owner: 'DaLongZhuaZi',
    repo: 'manxia-legado-sources',
    branch: 'master',
    commitsPageUrl: 'https://github.com/DaLongZhuaZi/manxia-legado-sources/commits/master/'
  },
  {
    key: MANXIA_LEGADO_RUNTIME_REPOSITORY_KEY,
    name: '漫匣Legado运行时',
    owner: 'DaLongZhuaZi',
    repo: 'manxia-legado-runtime',
    branch: 'master',
    commitsPageUrl: 'https://github.com/DaLongZhuaZi/manxia-legado-runtime/commits/master/'
  }
];

export class VersionHistoryManager {
  private static instance: VersionHistoryManager | null = null;
  private context: Context | null = null;
  private historyDirPath: string = '';
  private cacheFilePath: string = '';

  private constructor() {}

  static getInstance(): VersionHistoryManager {
    if (!VersionHistoryManager.instance) {
      VersionHistoryManager.instance = new VersionHistoryManager();
    }
    return VersionHistoryManager.instance;
  }

  async initialize(context: Context): Promise<void> {
    this.context = context;
    this.historyDirPath = `${context.filesDir}/${VERSION_HISTORY_DIR}`;
    this.cacheFilePath = `${this.historyDirPath}/${VERSION_HISTORY_CACHE_FILE}`;
    await this.ensureDirectoryExists(this.historyDirPath);
    await this.ensureCacheFileExists();
  }

  async refreshRepositories(
    targets: VersionCommitRepositoryTarget[],
    fetchLimit: number = VERSION_HISTORY_DEFAULT_FETCH_LIMIT
  ): Promise<VersionCommitRepositoryResult[]> {
    this.ensureInitialized();

    const sanitizedLimit = fetchLimit > 0 ? fetchLimit : VERSION_HISTORY_DEFAULT_FETCH_LIMIT;
    const cacheData = this.readCacheFile();
    const results: VersionCommitRepositoryResult[] = [];
    const updatedCacheRepos: VersionHistoryCacheRepository[] = [];

    for (const target of targets) {
      const cachedRepo = cacheData.repositories.find((repo: VersionHistoryCacheRepository) => repo.key === target.key);
      const cachedCommits = cachedRepo ? this.normalizeCommitList(cachedRepo.commits) : [];
      const cachedLastFetchedAt = cachedRepo ? cachedRepo.lastFetchedAt : 0;
      const result = await this.fetchRepositoryCommits(target, sanitizedLimit, cachedCommits, cachedLastFetchedAt);

      results.push(result);
      updatedCacheRepos.push({
        key: target.key,
        name: target.name,
        commitsPageUrl: target.commitsPageUrl,
        lastFetchedAt: result.lastFetchedAt,
        commits: this.limitCommitList(result.commits)
      });
    }

    const retainedCacheRepos = cacheData.repositories.filter((repo: VersionHistoryCacheRepository) => {
      return !targets.some((target: VersionCommitRepositoryTarget) => target.key === repo.key);
    });

    const mergedRepositories: VersionHistoryCacheRepository[] = [];
    for (const repo of updatedCacheRepos) {
      mergedRepositories.push(repo);
    }
    for (const repo of retainedCacheRepos) {
      mergedRepositories.push(repo);
    }

    this.writeCacheFile({
      version: VERSION_HISTORY_CACHE_VERSION,
      updatedAt: Date.now(),
      repositories: mergedRepositories,
      repositoryMarkers: cacheData.repositoryMarkers
    });

    return results;
  }

  public resolveRepositoryTargetByUrl(url: string): VersionCommitRepositoryTarget | null {
    const normalizedUrl = this.normalizeRepositoryUrl(url).toLowerCase();
    if (!normalizedUrl) {
      return null;
    }

    const splitResult = this.splitRepositoryUrlQuery(normalizedUrl);
    const unwrapped = this.unwrapRepositoryProxyUrl(splitResult.baseUrl);
    const rawUrl = unwrapped.rawUrl.toLowerCase();

    for (const target of DEFAULT_VERSION_COMMIT_REPOSITORIES) {
      const ownerRepoPath = `${target.owner.toLowerCase()}/${target.repo.toLowerCase()}`;
      if (rawUrl.includes(ownerRepoPath)) {
        return target;
      }
    }

    return null;
  }

  public isManxiaExtensionsRepositoryUrl(url: string): boolean {
    const target = this.resolveRepositoryTargetByUrl(url);
    return target !== null && target.key === MANXIA_EXTENSIONS_REPOSITORY_KEY;
  }

  public getRepositoryVersionMarker(key: string): VersionRepositoryVersionMarker | null {
    const cacheData = this.readCacheFile();
    const marker = cacheData.repositoryMarkers.find((item: VersionRepositoryVersionMarker) => item.key === key);
    return marker || null;
  }

  public async markRepositoryVersionByUrl(url: string): Promise<VersionRepositoryVersionMarker | null> {
    this.ensureInitialized();
    const target = this.resolveRepositoryTargetByUrl(url);
    if (!target) {
      logger.warn(TAG, `无法识别仓库URL，跳过版本标记: ${url}`);
      return null;
    }

    return await this.markRepositoryVersionByTarget(target, url);
  }

  public async markRepositoryVersionByTarget(
    target: VersionCommitRepositoryTarget,
    repositoryUrl: string = ''
  ): Promise<VersionRepositoryVersionMarker | null> {
    this.ensureInitialized();
    const results = await this.refreshRepositories([target], 1);
    if (!results || results.length === 0) {
      return null;
    }

    const latestResult = results[0];
    if (!latestResult.networkUpdated && latestResult.usingCache) {
      logger.warn(TAG, `版本标记跳过：未获取到最新网络提交，避免使用缓存提交误标记，target=${target.key}`);
      return null;
    }

    if (latestResult.commits.length === 0) {
      return null;
    }

    const latestCommit = latestResult.commits[0];
    const marker = this.createRepositoryMarker(target, latestCommit, repositoryUrl);
    this.saveRepositoryVersionMarker(marker);
    return marker;
  }

  public async checkRepositoryUpdateByTarget(
    target: VersionCommitRepositoryTarget
  ): Promise<VersionRepositoryUpdateCheckResult> {
    this.ensureInitialized();

    const localMarker = this.getRepositoryVersionMarker(target.key);
    const results = await this.refreshRepositories([target], 1);
    if (!results || results.length === 0 || results[0].commits.length === 0) {
      return {
        canCheck: false,
        hasUpdate: false,
        key: target.key,
        name: target.name,
        localMarker: localMarker,
        latestCommit: null,
        errorMessage: '无法获取远程提交记录'
      };
    }

    const latestCommit = results[0].commits[0];
    if (!localMarker) {
      return {
        canCheck: true,
        hasUpdate: false,
        key: target.key,
        name: target.name,
        localMarker: null,
        latestCommit: latestCommit,
        errorMessage: ''
      };
    }

    const hasUpdate = this.isRemoteCommitNewer(localMarker, latestCommit);
    return {
      canCheck: true,
      hasUpdate: hasUpdate,
      key: target.key,
      name: target.name,
      localMarker: localMarker,
      latestCommit: latestCommit,
      errorMessage: ''
    };
  }

  public async checkManxiaExtensionsRepositoryUpdate(): Promise<VersionRepositoryUpdateCheckResult> {
    const target = DEFAULT_VERSION_COMMIT_REPOSITORIES.find(
      (item: VersionCommitRepositoryTarget) => item.key === MANXIA_EXTENSIONS_REPOSITORY_KEY
    );
    if (!target) {
      return {
        canCheck: false,
        hasUpdate: false,
        key: MANXIA_EXTENSIONS_REPOSITORY_KEY,
        name: '漫匣图源',
        localMarker: null,
        latestCommit: null,
        errorMessage: '未找到漫匣图源仓库配置'
      };
    }

    return await this.checkRepositoryUpdateByTarget(target);
  }

  public async checkManxiaLegadoSourcesRepositoryUpdate(): Promise<VersionRepositoryUpdateCheckResult> {
    const target = DEFAULT_VERSION_COMMIT_REPOSITORIES.find(
      (item: VersionCommitRepositoryTarget) => item.key === MANXIA_LEGADO_SOURCES_REPOSITORY_KEY
    );
    if (!target) {
      return {
        canCheck: false,
        hasUpdate: false,
        key: MANXIA_LEGADO_SOURCES_REPOSITORY_KEY,
        name: '漫匣Legado书源',
        localMarker: null,
        latestCommit: null,
        errorMessage: '未找到漫匣Legado书源仓库配置'
      };
    }

    return await this.checkRepositoryUpdateByTarget(target);
  }

  public async checkManxiaLegadoRuntimeRepositoryUpdate(): Promise<VersionRepositoryUpdateCheckResult> {
    const target = DEFAULT_VERSION_COMMIT_REPOSITORIES.find(
      (item: VersionCommitRepositoryTarget) => item.key === MANXIA_LEGADO_RUNTIME_REPOSITORY_KEY
    );
    if (!target) {
      return {
        canCheck: false,
        hasUpdate: false,
        key: MANXIA_LEGADO_RUNTIME_REPOSITORY_KEY,
        name: '漫匣Legado运行时',
        localMarker: null,
        latestCommit: null,
        errorMessage: '未找到漫匣Legado运行时仓库配置'
      };
    }

    return await this.checkRepositoryUpdateByTarget(target);
  }

  async fetchCommitDetail(target: VersionCommitRepositoryTarget, sha: string): Promise<VersionCommitDetail> {
    this.ensureInitialized();
    const normalizedSha = sha.trim();
    if (!normalizedSha) {
      throw new Error('提交 SHA 不能为空');
    }

    const apiUrl = this.buildGitHubCommitDetailApiUrl(target, normalizedSha);
    const route = await this.resolveBestRepositoryUrl(apiUrl);
    const detail = await this.requestCommitDetail(route.effectiveUrl);
    return detail;
  }

  private async fetchRepositoryCommits(
    target: VersionCommitRepositoryTarget,
    fetchLimit: number,
    cachedCommits: VersionCommitRecord[],
    cachedLastFetchedAt: number
  ): Promise<VersionCommitRepositoryResult> {
    const apiUrl = this.buildGitHubCommitsApiUrl(target, fetchLimit);
    try {
      const route = await this.resolveBestRepositoryUrl(apiUrl);
      const latestCommits = await this.requestCommitList(route.effectiveUrl);
      const mergedCommits = this.mergeCommitHistory(latestCommits, cachedCommits);
      const fetchedAt = Date.now();

      logger.info(
        TAG,
        `提交记录更新成功: ${target.name}, latest=${latestCommits.length}, merged=${mergedCommits.length}, proxy=${route.usedProxy}`
      );

      return {
        key: target.key,
        name: target.name,
        apiUrl: apiUrl,
        effectiveApiUrl: route.effectiveUrl,
        commitsPageUrl: target.commitsPageUrl,
        commits: mergedCommits,
        lastFetchedAt: fetchedAt,
        networkUpdated: true,
        usingCache: false,
        usedProxy: route.usedProxy,
        errorMessage: ''
      };
    } catch (error) {
      const errorMsg = this.extractErrorMessage(error);
      logger.warn(TAG, `提交记录更新失败，回退缓存: ${target.name}, error=${errorMsg}`);

      const fallbackCommits = this.normalizeCommitList(cachedCommits);
      return {
        key: target.key,
        name: target.name,
        apiUrl: apiUrl,
        effectiveApiUrl: apiUrl,
        commitsPageUrl: target.commitsPageUrl,
        commits: fallbackCommits,
        lastFetchedAt: cachedLastFetchedAt > 0 ? cachedLastFetchedAt : Date.now(),
        networkUpdated: false,
        usingCache: fallbackCommits.length > 0,
        usedProxy: false,
        errorMessage: errorMsg
      };
    }
  }

  private async requestCommitList(url: string): Promise<VersionCommitRecord[]> {
    const request = http.createHttp();
    try {
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        connectTimeout: 10000,
        readTimeout: 10000,
        header: {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'ManXia-VersionHistory',
          'X-GitHub-Api-Version': '2022-11-28'
        }
      };

      const proxyManager: IProxyManagerFacade = ProxyManagerHolder.get();
      if (proxyManager.isEnabled()) {
        await proxyManager.applyToHttpOptions(options, url);
      }

      const response = await request.request(url, options);
      if (response.responseCode !== 200) {
        throw new Error(`HTTP ${response.responseCode}`);
      }

      const payload = response.result;
      const responseText = typeof payload === 'string' ? payload : JSON.stringify(payload);
      const parsed = SafeUtils.parseArr(responseText) as GitHubCommitResponseItem[];
      if (!Array.isArray(parsed)) {
        throw new Error('提交数据格式异常');
      }

      const commits: VersionCommitRecord[] = [];
      for (const item of parsed) {
        const sha = item.sha ? item.sha.trim() : '';
        if (!sha) {
          continue;
        }

        const message = item.commit?.message ? item.commit.message.trim() : '';
        const title = this.extractCommitSummary(message);
        const body = this.extractCommitBody(message);
        const authorName = item.commit?.author?.name ? item.commit.author.name.trim() : '';
        const authorLogin = item.author?.login ? item.author.login.trim() : '';
        const date = item.commit?.author?.date ? item.commit.author.date : '';
        const timestamp = this.safeParseTimestamp(date);
        const htmlUrl = item.html_url ? item.html_url : '';

        commits.push({
          sha: sha,
          shortSha: sha.substring(0, 7),
          message: message,
          summary: title,
          title: title,
          body: body,
          authorName: authorName || authorLogin || 'Unknown',
          authorLogin: authorLogin,
          date: date,
          timestamp: timestamp,
          htmlUrl: htmlUrl,
          files: [],
          detailLoaded: false,
          detailLoading: false,
          detailError: ''
        });
      }

      commits.sort((a: VersionCommitRecord, b: VersionCommitRecord) => b.timestamp - a.timestamp);
      return commits;
    } finally {
      try {
        request.destroy();
      } catch (_) {
        // ignore
      }
    }
  }

  private async requestCommitDetail(url: string): Promise<VersionCommitDetail> {
    const request = http.createHttp();
    try {
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        connectTimeout: 10000,
        readTimeout: 10000,
        header: {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'ManXia-VersionHistory',
          'X-GitHub-Api-Version': '2022-11-28'
        }
      };

      const proxyManager: IProxyManagerFacade = ProxyManagerHolder.get();
      if (proxyManager.isEnabled()) {
        await proxyManager.applyToHttpOptions(options, url);
      }

      const response = await request.request(url, options);
      if (response.responseCode !== 200) {
        throw new Error(`HTTP ${response.responseCode}`);
      }

      const payload = response.result;
      const responseText = typeof payload === 'string' ? payload : JSON.stringify(payload);
      const parsed = SafeUtils.parseObj(responseText) as GitHubCommitDetailResponseItem;
      if (!parsed || typeof parsed !== 'object') {
        throw new Error('提交详情数据格式异常');
      }

      const sha = parsed.sha ? parsed.sha.trim() : '';
      const message = parsed.commit?.message ? parsed.commit.message.trim() : '';
      const title = this.extractCommitSummary(message);
      const body = this.extractCommitBody(message);
      const authorName = parsed.commit?.author?.name ? parsed.commit.author.name.trim() : '';
      const authorLogin = parsed.author?.login ? parsed.author.login.trim() : '';
      const date = parsed.commit?.author?.date ? parsed.commit.author.date : '';
      const timestamp = this.safeParseTimestamp(date);
      const htmlUrl = parsed.html_url ? parsed.html_url : '';
      const files = this.parseCommitFiles(parsed.files || []);

      return {
        sha: sha,
        message: message,
        title: title,
        body: body,
        htmlUrl: htmlUrl,
        authorName: authorName || authorLogin || 'Unknown',
        authorLogin: authorLogin,
        date: date,
        timestamp: timestamp,
        files: files
      };
    } finally {
      try {
        request.destroy();
      } catch (_) {
        // ignore
      }
    }
  }

  private parseCommitFiles(files: GitHubCommitFileResponseItem[]): VersionCommitFileChange[] {
    const parsedFiles: VersionCommitFileChange[] = [];
    for (const file of files) {
      const filename = file.filename ? file.filename.trim() : '';
      if (!filename) {
        continue;
      }
      parsedFiles.push({
        filename: filename,
        status: file.status ? file.status : 'modified',
        additions: typeof file.additions === 'number' ? file.additions : 0,
        deletions: typeof file.deletions === 'number' ? file.deletions : 0,
        changes: typeof file.changes === 'number' ? file.changes : 0
      });
    }
    return parsedFiles;
  }

  private extractCommitSummary(message: string): string {
    if (!message) {
      return '无提交说明';
    }
    const firstLineBreak = message.indexOf('\n');
    if (firstLineBreak < 0) {
      return message;
    }
    return message.substring(0, firstLineBreak).trim();
  }

  private extractCommitBody(message: string): string {
    if (!message) {
      return '';
    }
    const firstLineBreak = message.indexOf('\n');
    if (firstLineBreak < 0) {
      return '';
    }
    return message.substring(firstLineBreak + 1).trim();
  }

  private mergeCommitHistory(latest: VersionCommitRecord[], cached: VersionCommitRecord[]): VersionCommitRecord[] {
    const merged: VersionCommitRecord[] = [];
    const seenSha = new Set<string>();

    for (const commit of latest) {
      if (!commit.sha || seenSha.has(commit.sha)) {
        continue;
      }
      seenSha.add(commit.sha);
      merged.push(commit);
    }

    for (const commit of cached) {
      if (!commit.sha || seenSha.has(commit.sha)) {
        continue;
      }
      seenSha.add(commit.sha);
      merged.push(commit);
    }

    merged.sort((a: VersionCommitRecord, b: VersionCommitRecord) => b.timestamp - a.timestamp);
    return this.limitCommitList(merged);
  }

  private normalizeCommitList(commits: VersionCommitRecord[]): VersionCommitRecord[] {
    if (!commits || commits.length === 0) {
      return [];
    }

    const normalized: VersionCommitRecord[] = [];
    const seenSha = new Set<string>();

    for (const commit of commits) {
      if (!commit.sha || seenSha.has(commit.sha)) {
        continue;
      }
      seenSha.add(commit.sha);

      const message = commit.message ? commit.message : commit.summary;
      const summary = commit.summary ? commit.summary : this.extractCommitSummary(message);
      const title = commit.title ? commit.title : summary;
      const body = commit.body ? commit.body : this.extractCommitBody(message);
      const timestamp = commit.timestamp > 0
        ? commit.timestamp
        : this.safeParseTimestamp(commit.date);

      normalized.push({
        sha: commit.sha,
        shortSha: commit.shortSha ? commit.shortSha : commit.sha.substring(0, 7),
        message: message || '无提交说明',
        summary: summary,
        title: title,
        body: body,
        authorName: commit.authorName || 'Unknown',
        authorLogin: commit.authorLogin || '',
        date: commit.date || '',
        timestamp: timestamp,
        htmlUrl: commit.htmlUrl || '',
        files: Array.isArray(commit.files) ? commit.files : [],
        detailLoaded: commit.detailLoaded || false,
        detailLoading: false,
        detailError: ''
      });
    }

    normalized.sort((a: VersionCommitRecord, b: VersionCommitRecord) => b.timestamp - a.timestamp);
    return this.limitCommitList(normalized);
  }

  private limitCommitList(commits: VersionCommitRecord[]): VersionCommitRecord[] {
    if (commits.length <= VERSION_HISTORY_MAX_CACHE_SIZE) {
      return commits;
    }
    return commits.slice(0, VERSION_HISTORY_MAX_CACHE_SIZE);
  }

  private buildGitHubCommitsApiUrl(target: VersionCommitRepositoryTarget, fetchLimit: number): string {
    const owner = target.owner.trim();
    const repo = target.repo.trim();
    const branch = target.branch.trim();
    const perPage = fetchLimit > 0 ? fetchLimit : VERSION_HISTORY_DEFAULT_FETCH_LIMIT;
    return `https://api.github.com/repos/${owner}/${repo}/commits?sha=${branch}&per_page=${perPage}`;
  }

  private buildGitHubCommitDetailApiUrl(target: VersionCommitRepositoryTarget, sha: string): string {
    const owner = target.owner.trim();
    const repo = target.repo.trim();
    return `https://api.github.com/repos/${owner}/${repo}/commits/${sha}`;
  }

  private createRepositoryMarker(
    target: VersionCommitRepositoryTarget,
    commit: VersionCommitRecord,
    repositoryUrl: string
  ): VersionRepositoryVersionMarker {
    return {
      key: target.key,
      name: target.name,
      commitSha: commit.sha,
      commitShortSha: commit.shortSha,
      commitTimestamp: commit.timestamp,
      commitDate: commit.date,
      repositoryUrl: repositoryUrl,
      markedAt: Date.now()
    };
  }

  private saveRepositoryVersionMarker(marker: VersionRepositoryVersionMarker): void {
    const cacheData = this.readCacheFile();
    const markers: VersionRepositoryVersionMarker[] = [];
    let replaced = false;

    for (const existing of cacheData.repositoryMarkers) {
      if (existing.key === marker.key) {
        markers.push(marker);
        replaced = true;
      } else {
        markers.push(existing);
      }
    }
    if (!replaced) {
      markers.push(marker);
    }

    this.writeCacheFile({
      version: cacheData.version,
      updatedAt: Date.now(),
      repositories: cacheData.repositories,
      repositoryMarkers: markers
    });
  }

  private isRemoteCommitNewer(localMarker: VersionRepositoryVersionMarker, remoteCommit: VersionCommitRecord): boolean {
    if (remoteCommit.sha === localMarker.commitSha) {
      return false;
    }
    if (remoteCommit.timestamp > localMarker.commitTimestamp) {
      return true;
    }
    // 时间戳相同但SHA不同，视为更新
    return true;
  }

  private normalizeRepositoryUrl(url: string): string {
    if (!url) {
      return '';
    }
    return url.trim();
  }

  private splitRepositoryUrlQuery(url: string): RepositoryUrlSplitResult {
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

  private getRepositoryProxyPrefixes(): string[] {
    return [REPOSITORY_PROXY_GH, REPOSITORY_PROXY_HK_GH];
  }

  private unwrapRepositoryProxyUrl(url: string): RepositoryProxyUnwrapResult {
    const normalizedUrl = this.normalizeRepositoryUrl(url);
    const proxyPrefixes = this.getRepositoryProxyPrefixes();
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

  private buildRepositoryProxyUrl(proxyPrefix: string, rawUrl: string): string {
    if (!proxyPrefix || !rawUrl) {
      return rawUrl;
    }
    if (rawUrl.startsWith(proxyPrefix)) {
      return rawUrl;
    }
    return `${proxyPrefix}${rawUrl}`;
  }

  private getRepositoryCandidateKindByPrefix(prefix: string): RepositoryCandidateKind {
    if (prefix === REPOSITORY_PROXY_HK_GH) {
      return 'hkGhProxy';
    }
    return 'ghProxy';
  }

  private addRepositoryRouteCandidate(
    candidates: RepositoryRouteCandidate[],
    seen: Set<string>,
    candidate: RepositoryRouteCandidate
  ): void {
    const normalizedCandidateUrl = this.normalizeRepositoryUrl(candidate.url);
    if (!normalizedCandidateUrl || seen.has(normalizedCandidateUrl)) {
      return;
    }

    seen.add(normalizedCandidateUrl);
    candidates.push({
      kind: candidate.kind,
      url: normalizedCandidateUrl
    });
  }

  private buildRepositoryRouteCandidates(url: string): RepositoryRouteCandidate[] {
    const normalizedInputUrl = this.normalizeRepositoryUrl(url);
    if (!normalizedInputUrl) {
      return [];
    }

    const splitResult = this.splitRepositoryUrlQuery(normalizedInputUrl);
    const unwrapped = this.unwrapRepositoryProxyUrl(splitResult.baseUrl);
    const originalUrl = `${unwrapped.rawUrl}${splitResult.query}`;
    const candidates: RepositoryRouteCandidate[] = [];
    const seen = new Set<string>();

    this.addRepositoryRouteCandidate(candidates, seen, {
      kind: 'origin',
      url: originalUrl
    });

    const proxyPrefixes = this.getRepositoryProxyPrefixes();
    for (const proxyPrefix of proxyPrefixes) {
      this.addRepositoryRouteCandidate(candidates, seen, {
        kind: this.getRepositoryCandidateKindByPrefix(proxyPrefix),
        url: this.buildRepositoryProxyUrl(proxyPrefix, originalUrl)
      });
    }

    return candidates;
  }

  private async quickCheckRepositoryConnectivity(url: string): Promise<RepositoryConnectivityCheckResult> {
    const request = http.createHttp();
    try {
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        connectTimeout: REPOSITORY_CONNECT_TIMEOUT_MS,
        readTimeout: REPOSITORY_READ_TIMEOUT_MS,
        header: {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'ManXia-VersionHistory-Probe'
        }
      };

      const proxyManager: IProxyManagerFacade = ProxyManagerHolder.get();
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
        errorMessage: this.extractErrorMessage(error)
      };
    } finally {
      try {
        request.destroy();
      } catch (_) {
        // ignore
      }
    }
  }

  private async probeRepositoryCandidate(candidate: RepositoryRouteCandidate): Promise<RepositoryProbeResult> {
    const check = await this.quickCheckRepositoryConnectivity(candidate.url);
    return {
      candidate: candidate,
      check: check
    };
  }

  private async resolveBestRepositoryUrl(url: string): Promise<RepositoryRouteResult> {
    const candidates = this.buildRepositoryRouteCandidates(url);
    if (candidates.length === 0) {
      throw new Error('提交地址无效');
    }

    const probeTasks: Promise<RepositoryProbeResult>[] = [];
    for (const candidate of candidates) {
      probeTasks.push(this.probeRepositoryCandidate(candidate));
    }
    const probeResults = await Promise.all(probeTasks);

    let selected: RepositoryRouteCandidate | null = null;
    for (const candidate of candidates) {
      const matched = probeResults.find((result: RepositoryProbeResult) => result.candidate.url === candidate.url);
      if (matched && matched.check.reachable) {
        selected = candidate;
        break;
      }
    }

    for (const probeResult of probeResults) {
      if (probeResult.check.reachable) {
        logger.info(TAG, `连通性通过: ${probeResult.candidate.url}`);
      } else {
        const detail = probeResult.check.errorMessage || String(probeResult.check.responseCode);
        if (!selected || (probeResult.candidate.kind === 'origin' && selected.kind !== 'origin')) {
          logger.warn(TAG, `连通性失败: ${probeResult.candidate.url}, detail=${detail}`);
        } else {
          logger.info(TAG, `备用连通性不可用: ${probeResult.candidate.url}, detail=${detail}`);
        }
      }
    }

    if (!selected) {
      throw new Error('原始地址和加速代理均不可连通');
    }

    const splitResult = this.splitRepositoryUrlQuery(this.normalizeRepositoryUrl(url));
    const unwrappedOriginal = this.unwrapRepositoryProxyUrl(splitResult.baseUrl);
    const originalUrl = `${unwrappedOriginal.rawUrl}${splitResult.query}`;
    const selectedUnwrapped = this.unwrapRepositoryProxyUrl(selected.url);

    return {
      originalUrl: originalUrl,
      effectiveUrl: selected.url,
      usedProxy: selected.kind !== 'origin',
      proxyPrefix: selectedUnwrapped.proxyPrefix
    };
  }

  private ensureInitialized(): void {
    if (!this.context || !this.historyDirPath || !this.cacheFilePath) {
      throw new Error('VersionHistoryManager 尚未初始化');
    }
  }

  private async ensureDirectoryExists(dirPath: string): Promise<void> {
    try {
      const exists = SafeFileUtils.accessSync(dirPath);
      if (!exists) {
        SafeFileUtils.mkdirSync(dirPath);
      }
    } catch (_) {
      SafeFileUtils.mkdirSync(dirPath);
    }
  }

  private async ensureCacheFileExists(): Promise<void> {
    try {
      const exists = SafeFileUtils.accessSync(this.cacheFilePath);
      if (!exists) {
        this.writeCacheFile(this.createEmptyCacheData());
      }
    } catch (_) {
      this.writeCacheFile(this.createEmptyCacheData());
    }
  }

  private createEmptyCacheData(): VersionHistoryCacheData {
    return {
      version: VERSION_HISTORY_CACHE_VERSION,
      updatedAt: Date.now(),
      repositories: [],
      repositoryMarkers: []
    };
  }

  private readCacheFile(): VersionHistoryCacheData {
    try {
      const file = SafeFileUtils.openSync(this.cacheFilePath, fileIo.OpenMode.READ_ONLY);
      const buffer = new ArrayBuffer(2 * 1024 * 1024);
      const readLen = SafeFileUtils.readSync(file.fd, buffer);
      SafeFileUtils.closeSync(file);
      const jsonContent = this.decodeToString(buffer, readLen);
      const parsed = SafeUtils.parseObj(jsonContent) as VersionHistoryCacheData;

      if (!parsed || !Array.isArray(parsed.repositories)) {
        return this.createEmptyCacheData();
      }

      const markers = Array.isArray(parsed.repositoryMarkers)
        ? parsed.repositoryMarkers as VersionRepositoryVersionMarker[]
        : [];

      return {
        version: parsed.version || VERSION_HISTORY_CACHE_VERSION,
        updatedAt: parsed.updatedAt || Date.now(),
        repositories: parsed.repositories,
        repositoryMarkers: markers
      };
    } catch (error) {
      logger.warn(TAG, `读取版本记录缓存失败: ${String(error)}`);
      return this.createEmptyCacheData();
    }
  }

  private writeCacheFile(cacheData: VersionHistoryCacheData): void {
    const jsonContent = JSON.stringify(cacheData, null, 2);
    const file = SafeFileUtils.openSync(
      this.cacheFilePath,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC
    );
    SafeFileUtils.writeSync(file.fd, jsonContent);
    SafeFileUtils.closeSync(file);
  }

  private decodeToString(buffer: ArrayBuffer, length: number): string {
    const bytes: Uint8Array = new Uint8Array(buffer, 0, length);
    let out: string = '';
    let i: number = 0;
    const len: number = bytes.length;
    while (i < len) {
      const b0: number = bytes[i++];
      if ((b0 & 0x80) === 0) {
        out += String.fromCharCode(b0);
      } else if ((b0 & 0xe0) === 0xc0 && i < len) {
        const b1: number = bytes[i++];
        const code: number = ((b0 & 0x1f) << 6) | (b1 & 0x3f);
        out += String.fromCharCode(code);
      } else if ((b0 & 0xf0) === 0xe0 && i + 1 < len) {
        const b1: number = bytes[i++];
        const b2: number = bytes[i++];
        const code: number = ((b0 & 0x0f) << 12) | ((b1 & 0x3f) << 6) | (b2 & 0x3f);
        out += String.fromCharCode(code);
      } else if ((b0 & 0xf8) === 0xf0 && i + 2 < len) {
        const b1: number = bytes[i++];
        const b2: number = bytes[i++];
        const b3: number = bytes[i++];
        let codePoint: number = ((b0 & 0x07) << 18) | ((b1 & 0x3f) << 12) | ((b2 & 0x3f) << 6) | (b3 & 0x3f);
        codePoint -= 0x10000;
        out += String.fromCharCode(0xd800 + ((codePoint >> 10) & 0x3ff));
        out += String.fromCharCode(0xdc00 + (codePoint & 0x3ff));
      } else {
        out += '\uFFFD';
      }
    }
    return out;
  }

  private safeParseTimestamp(date: string): number {
    if (!date) {
      return Date.now();
    }
    const parsed = Date.parse(date);
    if (isNaN(parsed)) {
      return Date.now();
    }
    return parsed;
  }

  private extractErrorMessage(error: Object): string {
    if (error instanceof Error) {
      return error.message;
    }
    if (typeof error === 'object' && error !== null) {
      const errObj = error as Record<string, string | number | boolean>;
      if (typeof errObj.message === 'string' && errObj.message.length > 0) {
        return errObj.message;
      }
      if (errObj.code !== undefined) {
        return `code: ${String(errObj.code)}`;
      }
      try {
        return JSON.stringify(error);
      } catch (_) {
        return String(error);
      }
    }
    return String(error);
  }
}

export function getVersionHistoryManager(): VersionHistoryManager {
  return VersionHistoryManager.getInstance();
}
