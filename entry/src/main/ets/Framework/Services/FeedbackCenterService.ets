import { common } from '@kit.AbilityKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { fileIo } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { FeedbackCenterCacheManager, FeedbackCenterCacheStats } from '../Cache/FeedbackCenterCacheManager';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';

const TAG = 'FeedbackCenterService';
const FEEDBACK_ORIGIN = 'https://feedback.manxia.top';
const UPLOAD_CHUNK_SIZE = 4 * 1024 * 1024;
const UPLOAD_CHUNK_RETRY_COUNT = 2;

export type FeedbackIssueType = 'source' | 'book_source' | 'software' | 'ui' | 'suggestion' | 'other';
export type FeedbackIssueStatus = 'open' | 'in_progress' | 'resolved' | 'closed' | 'merged';

export type FeedbackUploadCategory = 'text' | 'image' | 'video' | 'archive';

export interface FeedbackDiagnosticInfo {
  model: string;
  system_version: string;
  app_version: string;
  build_number: number;
  device_type: string;
}

export interface FeedbackContextInfo {
  manga_title: string;
  chapter_title: string;
  source: string;
}

export interface FeedbackAttachment {
  id: string;
  original_name: string;
  category: FeedbackUploadCategory;
  media_type: string;
  size: number;
  sha256: string;
  visibility: string;
  review_status: string;
  created_at: string;
  download_url: string;
}

export interface FeedbackIssueSummary {
  id: string;
  issue_number: number;
  title: string;
  issue_type: FeedbackIssueType;
  status: FeedbackIssueStatus;
  priority: string;
  visibility: string;
  labels: string[];
  support_count: number;
  post_count: number;
  attachment_count: number;
  created_at: string;
  updated_at: string;
}

export interface FeedbackIssuePost {
  id: string;
  author_kind: string;
  body: string;
  is_public: boolean;
  created_at: string;
  attachments: FeedbackAttachment[];
}

export interface FeedbackIssueDetail extends FeedbackIssueSummary {
  description: string;
  diagnostic: FeedbackDiagnosticInfo;
  context: FeedbackContextInfo;
  posts: FeedbackIssuePost[];
  attachments: FeedbackAttachment[];
  supported_by_device: boolean;
}

export interface FeedbackIssuePage {
  items: FeedbackIssueSummary[];
  page: number;
  page_size: number;
  total: number;
}

interface FeedbackSupportResponse {
  issue_number: number;
  support_count: number;
  already_supported: boolean;
}

interface FeedbackSupportPayload {
  turnstile_token?: string;
  device_id?: string;
}

export interface FeedbackFileHash {
  size: number;
  sha256: string;
}

interface FeedbackErrorResponse {
  detail?: string;
}

export interface FeedbackCreateIssuePayload {
  title: string;
  description: string;
  issue_type: FeedbackIssueType;
  diagnostic: FeedbackDiagnosticInfo;
  context: FeedbackContextInfo;
  turnstile_token?: string;
}

export interface FeedbackCreatePostPayload {
  body: string;
  turnstile_token?: string;
}

export interface FeedbackUploadSessionPayload {
  original_name: string;
  size: number;
  sha256: string;
  media_type: string;
  category: FeedbackUploadCategory;
  post_id?: string;
  turnstile_token?: string;
}

export interface FeedbackUploadSession {
  upload_id: string;
  issue_number: number;
  chunk_size: number;
  requested_size: number;
  received_size: number;
  expires_at: string;
}

export interface FeedbackUploadChunkResult {
  upload_id: string;
  received_size: number;
  requested_size: number;
  complete: boolean;
}

export interface FeedbackUploadProgress {
  completed: number;
  total: number;
  fileName: string;
}

export class FeedbackUploadCancelledError extends Error {
  public constructor() {
    super('上传已取消');
  }
}

interface FeedbackRequestHeaders {
  'Content-Type'?: string;
  'Accept'?: string;
  'X-Chunk-Offset'?: string;
  'X-Device-Id'?: string;
}

export class FeedbackCenterService {
  private static instance: FeedbackCenterService | null = null;
  private readonly cacheManager: FeedbackCenterCacheManager = FeedbackCenterCacheManager.getInstance();
  private readonly listCacheTtlMilliseconds: number = 5 * 60 * 1000;
  private readonly detailCacheTtlMilliseconds: number = 2 * 60 * 1000;
  private deviceId: string = '';

  private constructor() {}

  public static getInstance(): FeedbackCenterService {
    if (FeedbackCenterService.instance === null) {
      FeedbackCenterService.instance = new FeedbackCenterService();
    }
    return FeedbackCenterService.instance;
  }

  public getOrigin(): string {
    return FEEDBACK_ORIGIN;
  }

  public getUploadChunkSize(): number {
    return UPLOAD_CHUNK_SIZE;
  }

  public async initializeCache(context: common.UIAbilityContext): Promise<void> {
    await this.cacheManager.initialize(context);
    await this.ensureDeviceId(context);
  }

  /**
   * 匿名设备标识：持久化在应用沙箱内，用于服务端对同一设备对同一 Issue 的去重支持。
   */
  private async ensureDeviceId(context: common.UIAbilityContext): Promise<void> {
    if (this.deviceId.length > 0) {
      return;
    }
    const path: string = `${context.filesDir}/feedback_device_id`;
    try {
      // 先确保文件存在（创建空文件），再用路径读写文本内容。
      const file = await fileIo.open(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
      await fileIo.close(file);
      const existing = (await fileIo.readText(path)).trim();
      if (existing.length > 0 && existing.length <= 128) {
        this.deviceId = existing;
        return;
      }
      const newId: string = util.generateRandomUUID();
      const encoder = new util.TextEncoder();
      const bytes = encoder.encodeInto(newId);
      const writeFile = await fileIo.open(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      try {
        await fileIo.write(writeFile.fd, bytes.buffer);
      } finally {
        await fileIo.close(writeFile);
      }
      this.deviceId = newId;
      logger.info(TAG, '已生成匿名设备标识');
    } catch (error) {
      logger.warn(TAG, '初始化匿名设备标识失败: ' + String(error));
    }
  }

  public getDeviceId(): string {
    return this.deviceId;
  }

  public async clearCache(): Promise<void> {
    await this.cacheManager.clear();
  }

  public getCacheStats(): FeedbackCenterCacheStats {
    return this.cacheManager.getStats();
  }

  public async listIssues(
    page: number = 1,
    pageSize: number = 20,
    search: string = '',
    issueType: FeedbackIssueType | '' = '',
    issueStatus: FeedbackIssueStatus | '' = ''
  ): Promise<FeedbackIssuePage> {
    const queryParts: string[] = [
      'page=' + String(page),
      'page_size=' + String(pageSize)
    ];
    if (search.trim().length > 0) {
      queryParts.push('search=' + encodeURIComponent(search.trim()));
    }
    if (issueType.length > 0) {
      queryParts.push('issue_type=' + encodeURIComponent(issueType));
    }
    if (issueStatus.length > 0) {
      queryParts.push('status=' + encodeURIComponent(issueStatus));
    }
    const path: string = '/api/v1/issues?' + queryParts.join('&');
    const cacheKey: string = 'list:' + path;
    const cached = await this.readCachedJson<FeedbackIssuePage>(cacheKey, this.listCacheTtlMilliseconds);
    if (cached !== null) {
      return cached;
    }
    const result = await this.requestJson<FeedbackIssuePage>(path, http.RequestMethod.GET, '', this.jsonHeaders());
    await this.writeCachedJson(cacheKey, JSON.stringify(result));
    return result;
  }

  public async getIssue(issueNumber: number, forceRefresh: boolean = false): Promise<FeedbackIssueDetail> {
    const path: string = '/api/v1/issues/' + String(issueNumber);
    const cacheKey: string = 'detail:' + String(issueNumber);
    if (!forceRefresh) {
      const cached = await this.readCachedJson<FeedbackIssueDetail>(cacheKey, this.detailCacheTtlMilliseconds);
      if (cached !== null) {
        return cached;
      }
    }
    const result = await this.requestJson<FeedbackIssueDetail>(path, http.RequestMethod.GET, '', this.jsonHeaders());
    await this.writeCachedJson(cacheKey, JSON.stringify(result));
    return result;
  }
  public async createIssue(payload: FeedbackCreateIssuePayload): Promise<FeedbackIssueDetail> {
    const result = await this.requestJson<FeedbackIssueDetail>(
      '/api/v1/issues',
      http.RequestMethod.POST,
      JSON.stringify(payload),
      this.jsonHeaders()
    );
    await this.invalidateCache();
    return result;
  }

  public async supportIssue(issueNumber: number, turnstileToken: string = ''): Promise<FeedbackSupportResponse> {
    const payload: FeedbackSupportPayload = {
      turnstile_token: turnstileToken.length > 0 ? turnstileToken : undefined,
      device_id: this.deviceId.length > 0 ? this.deviceId : undefined
    };
    const body: string = JSON.stringify(payload);
    const result = await this.requestJson<FeedbackSupportResponse>(
      `/api/v1/issues/${issueNumber}/supports`,
      http.RequestMethod.POST,
      body,
      this.jsonHeaders()
    );
    await this.invalidateCache();
    return result;
  }

  public async createPost(issueNumber: number, payload: FeedbackCreatePostPayload): Promise<FeedbackIssuePost> {
    const result = await this.requestJson<FeedbackIssuePost>(
      '/api/v1/issues/' + String(issueNumber) + '/posts',
      http.RequestMethod.POST,
      JSON.stringify(payload),
      this.jsonHeaders()
    );
    await this.invalidateCache();
    return result;
  }
  public async createUploadSession(issueNumber: number, payload: FeedbackUploadSessionPayload): Promise<FeedbackUploadSession> {
    return await this.requestJson<FeedbackUploadSession>(
      `/api/v1/issues/${issueNumber}/upload-sessions`,
      http.RequestMethod.POST,
      JSON.stringify(payload),
      this.jsonHeaders()
    );
  }

  public async uploadFile(
    localPath: string,
    session: FeedbackUploadSession,
    onProgress?: (progress: FeedbackUploadProgress) => void,
    shouldCancel?: () => boolean
  ): Promise<FeedbackAttachment> {
    const source = await fileIo.open(localPath, fileIo.OpenMode.READ_ONLY);
    try {
      const stat = await fileIo.stat(source.fd);
      if (stat.size !== session.requested_size) {
        throw new Error('本地文件大小在上传前发生变化');
      }
      let offset: number = session.received_size;
      if (offset < 0 || offset > session.requested_size) {
        throw new Error('上传会话偏移无效');
      }
      if (shouldCancel && shouldCancel()) {
        throw new FeedbackUploadCancelledError();
      }
      fileIo.lseek(source.fd, offset, fileIo.WhenceType.SEEK_SET);
      while (offset < session.requested_size) {
        if (shouldCancel && shouldCancel()) {
          throw new FeedbackUploadCancelledError();
        }
        const remaining: number = session.requested_size - offset;
        const readSize: number = remaining > UPLOAD_CHUNK_SIZE ? UPLOAD_CHUNK_SIZE : remaining;
        const buffer = new ArrayBuffer(readSize);
        const readBytes = await fileIo.read(source.fd, buffer, { length: readSize });
        if (readBytes !== readSize) {
          throw new Error(`读取附件失败: expected=${readSize}, actual=${readBytes}`);
        }
        const result = await this.uploadChunkWithRetry(session.upload_id, offset, buffer, shouldCancel);
        if (result.received_size <= offset && !result.complete) {
          throw new Error('服务器未推进上传偏移');
        }
        offset = result.received_size;
        if (onProgress) {
          onProgress({ completed: offset, total: session.requested_size, fileName: '' });
        }
      }
      if (shouldCancel && shouldCancel()) {
        throw new FeedbackUploadCancelledError();
      }
      const result = await this.completeUpload(session.upload_id);
      await this.invalidateCache();
      return result;
    } finally {
      await fileIo.close(source);
    }
  }

  public async calculateFileSha256(localPath: string): Promise<FeedbackFileHash> {
    const source = await fileIo.open(localPath, fileIo.OpenMode.READ_ONLY);
    try {
      const stat = await fileIo.stat(source.fd);
      const md = cryptoFramework.createMd('SHA256');
      let offset: number = 0;
      while (offset < stat.size) {
        const remaining: number = stat.size - offset;
        const readSize: number = remaining > UPLOAD_CHUNK_SIZE ? UPLOAD_CHUNK_SIZE : remaining;
        const buffer = new ArrayBuffer(readSize);
        const readBytes = await fileIo.read(source.fd, buffer, { length: readSize });
        if (readBytes !== readSize) {
          throw new Error(`读取附件失败: expected=${readSize}, actual=${readBytes}`);
        }
        await md.update({ data: new Uint8Array(buffer) });
        offset += readBytes;
      }
      const digest = await md.digest();
      return { size: stat.size, sha256: this.bytesToHex(digest.data) };
    } finally {
      await fileIo.close(source);
    }
  }

  private async uploadChunk(uploadId: string, offset: number, buffer: ArrayBuffer): Promise<FeedbackUploadChunkResult> {
    return await this.requestJson<FeedbackUploadChunkResult>(
      `/api/v1/uploads/${uploadId}/chunks`,
      http.RequestMethod.POST,
      buffer,
      {
        'Content-Type': 'application/octet-stream',
        'X-Chunk-Offset': String(offset)
      }
    );
  }

  private async uploadChunkWithRetry(
    uploadId: string,
    offset: number,
    buffer: ArrayBuffer,
    shouldCancel?: () => boolean
  ): Promise<FeedbackUploadChunkResult> {
    let attempt: number = 0;
    while (true) {
      if (shouldCancel && shouldCancel()) {
        throw new FeedbackUploadCancelledError();
      }
      try {
        return await this.uploadChunk(uploadId, offset, buffer);
      } catch (error) {
        if (attempt >= UPLOAD_CHUNK_RETRY_COUNT) {
          if (error instanceof Error) {
            throw error;
          }
          throw new Error(String(error));
        }
        attempt += 1;
        await this.delay(350 * attempt);
      }
    }
  }

  private async delay(milliseconds: number): Promise<void> {
    await new Promise<void>((resolve) => {
      setTimeout(resolve, milliseconds);
    });
  }

  private async readCachedJson<T>(key: string, maxAgeMilliseconds: number): Promise<T | null> {
    try {
      const rawValue = await this.cacheManager.getJson(key, maxAgeMilliseconds);
      if (rawValue === null) {
        return null;
      }
      return JSON.parse(rawValue) as T;
    } catch (error) {
      logger.warn(TAG, '读取反馈缓存失败，将请求网络: ' + String(error));
      await this.removeCachedValue(key);
      return null;
    }
  }

  private async writeCachedJson(key: string, value: string): Promise<void> {
    try {
      await this.cacheManager.putJson(key, value);
    } catch (error) {
      logger.warn(TAG, '写入反馈缓存失败，不影响网络结果: ' + String(error));
    }
  }

  private async removeCachedValue(key: string): Promise<void> {
    try {
      await this.cacheManager.remove(key);
    } catch (error) {
      logger.warn(TAG, '删除无效反馈缓存失败: ' + String(error));
    }
  }

  private async invalidateCache(): Promise<void> {
    try {
      await this.cacheManager.clear();
    } catch (error) {
      logger.warn(TAG, '反馈缓存失效失败，不影响已提交数据: ' + String(error));
    }
  }
  private async completeUpload(uploadId: string): Promise<FeedbackAttachment> {
    return await this.requestJson<FeedbackAttachment>(
      `/api/v1/uploads/${uploadId}/complete`,
      http.RequestMethod.POST,
      '',
      this.jsonHeaders()
    );
  }

  private jsonHeaders(): FeedbackRequestHeaders {
    if (this.deviceId.length > 0) {
      return {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'X-Device-Id': this.deviceId
      };
    }
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json'
    };
  }

  private async requestJson<T>(
    path: string,
    method: http.RequestMethod,
    body: string | ArrayBuffer,
    headers: FeedbackRequestHeaders
  ): Promise<T> {
    const request = http.createHttp();
    try {
      const options: http.HttpRequestOptions = {
        method,
        header: headers as Object,
        connectTimeout: 15000,
        readTimeout: 30000,
        expectDataType: http.HttpDataType.STRING
      };
      if (typeof body === 'string') {
        if (body.length > 0) {
          options.extraData = body;
        }
      } else {
        options.extraData = body;
      }
      const response = await request.request(`${FEEDBACK_ORIGIN}${path}`, options);
      const responseText = typeof response.result === 'string' ? response.result : String(response.result);
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error(this.buildHttpError(response.responseCode, responseText));
      }
      if (responseText.length === 0) {
        throw new Error('反馈中心返回空响应');
      }
      return JSON.parse(responseText) as T;
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `反馈中心请求失败: ${method} ${path}: ${message}`);
      throw new Error(message);
    } finally {
      request.destroy();
    }
  }

  private buildHttpError(code: number, responseText: string): string {
    try {
      const parsed = JSON.parse(responseText) as FeedbackErrorResponse;
      if (parsed.detail && parsed.detail.length > 0) {
        return `HTTP ${code}: ${parsed.detail}`;
      }
    } catch (_) {
      // 保留状态码和截断后的原文。
    }
    return `HTTP ${code}: ${responseText.substring(0, 160)}`;
  }

  private bytesToHex(bytes: Uint8Array): string {
    const table = '0123456789abcdef';
    let result: string = '';
    for (let index = 0; index < bytes.length; index++) {
      const value: number = bytes[index];
      result += table.charAt(value >>> 4);
      result += table.charAt(value & 0x0f);
    }
    return result;
  }
}

export const feedbackCenterService = FeedbackCenterService.getInstance();
