import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { webview } from '@kit.ArkWeb';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import fileIo from '@ohos.file.fs';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { SafeFileUtils } from 'manxia_core/src/main/ets/Utils/SafeFileUtils';
import { uiContextManager } from '../Managers/UIContextManager';
import { getCookieStore } from 'manxia_novel/src/main/ets/Framework/Novel/LegadoCookieStore';
import type {
  CookieChange,
  JsContext,
  JsExecuteResult,
  LegadoJsSourceEffects,
  ToastMessage
} from './LegadoJsEngine';
import { LegadoBridgeTrace } from 'manxia_novel/src/main/ets/Framework/Novel/LegadoCompatibilityTypes';
import type { LegadoBookSource } from 'manxia_novel/src/main/ets/Framework/Novel/LegadoSourceTypes';

const TAG = 'LegadoRuntimeV2';
const RUNTIME_MARKER = 'manxia-legado-runtime-v2';
// A runtime script is replayed once for each synchronous bridge request.  This
// is intentionally a request budget, not a small replay count: one legitimate
// rule can compose several crypto, HTTP, cookie and cache operations.
const MAX_BRIDGE_REQUEST_COUNT = 128;
const DEFAULT_USER_AGENT =
  'Mozilla/5.0 (Linux; Android 11; Pixel 5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/90.0.4430.91 Mobile Safari/537.36';

export enum LegadoRuntimeErrorCode {
  SCRIPT_SYNTAX = 'SCRIPT_SYNTAX',
  PENDING_BRIDGE_TIMEOUT = 'PENDING_BRIDGE_TIMEOUT',
  BRIDGE_REQUEST_LIMIT_EXCEEDED = 'BRIDGE_REQUEST_LIMIT_EXCEEDED',
  HTTP_FAILED = 'HTTP_FAILED',
  RULE_PARSE_FAILED = 'RULE_PARSE_FAILED',
  UNRESOLVED_RULE_TOKEN = 'UNRESOLVED_RULE_TOKEN',
  WEBVIEW_NOT_READY = 'WEBVIEW_NOT_READY',
  RUNTIME_ERROR = 'RUNTIME_ERROR'
}

export interface LegadoRuntimeContext {
  result?: string;
  src?: string;
  baseUrl?: string;
  key?: string;
  page?: number;
  book?: Record<string, string>;
  chapter?: Record<string, string>;
  variables?: Record<string, string>;
  jsLib?: string;
  sourceUrl?: string;
  source?: LegadoRuntimeSourceSnapshot;
}

export interface LegadoRuntimeSourceSnapshot {
  bookSourceUrl: string;
  bookSourceName: string;
  bookSourceType: string;
  bookSourceGroup?: string;
  bookSourceComment?: string;
  header?: string;
  loginUrl?: string;
  loginUi?: string;
  loginCheckJs?: string;
  variableComment?: string;
  enabledCookieJar?: boolean;
}

export interface LegadoRuntimeState {
  bridgeResponses: Record<string, LegadoBridgeResponse>;
  variables: Record<string, string>;
  cache: Record<string, string>;
  sourceData: Record<string, string>;
  sourceHeaders: Record<string, Record<string, string>>;
  sourceHeaderResolution: Record<string, string>;
  randomSeed: number;
  now: number;
}

export interface LegadoBridgeRequest {
  id: string;
  type: string;
  url?: string;
  method?: string;
  body?: string;
  headers?: Record<string, string>;
  key?: string;
  value?: string;
  path?: string;
  algorithm?: string;
  saveTime?: number;
}

interface LegadoSymmetricCipherSpec {
  cipherTransformation: string;
  keyAlgorithm: string;
  mode: string;
  requiresIv: boolean;
  ivLength: number;
}

export interface LegadoBridgeResponse {
  id: string;
  type: string;
  success: boolean;
  body: string;
  url: string;
  code: number;
  headers: string;
  method?: string;
  headerNames?: string[];
  path?: string;
  error?: string;
}

export interface LegadoRuntimeEnvelope {
  marker?: string;
  status?: string;
  result?: string;
  error?: string;
  diagnostic?: string;
  errorCode?: LegadoRuntimeErrorCode;
  variables?: Record<string, string>;
  sourceEffects?: LegadoJsSourceEffects;
  cookieChanges?: CookieChange[];
  toasts?: ToastMessage[];
  logs?: string[];
  bridgeRequests?: LegadoBridgeRequest[];
  cache?: Record<string, string>;
  sourceHeaders?: Record<string, Record<string, string>>;
  sourceHeaderResolution?: Record<string, string>;
}

interface PendingTask {
  code: string;
  context: LegadoRuntimeContext;
  resolve: (result: JsExecuteResult) => void;
}

interface RuntimePayload {
  code: string;
  context: LegadoRuntimeContext;
  state: LegadoRuntimeState;
}

class RuntimeJson {
  static parseEnvelope(raw: string): LegadoRuntimeEnvelope {
    const normalized = RuntimeJson.unwrapWebViewString(raw);
    try {
      return JSON.parse(normalized) as LegadoRuntimeEnvelope;
    } catch (error) {
      const envelope: LegadoRuntimeEnvelope = {
        marker: RUNTIME_MARKER,
        status: 'error',
        errorCode: LegadoRuntimeErrorCode.RUNTIME_ERROR,
        error: `运行层返回值不是有效JSON: ${String(error)}`
      };
      return envelope;
    }
  }

  private static unwrapWebViewString(raw: string): string {
    let text = raw === undefined || raw === null ? '' : String(raw);
    if (text.length >= 2 && text.startsWith('"') && text.endsWith('"')) {
      try {
        const parsed = JSON.parse(text) as string;
        text = parsed;
      } catch (_error) {
        // ArkWeb不同版本返回值可能已经是原始字符串，保留原值。
      }
    }
    return text;
  }
}

export class LegadoRuntimeV2 {
  private static instance: LegadoRuntimeV2 | null = null;
  private webviewController: webview.WebviewController | null = null;
  private ready: boolean = false;
  private queue: PendingTask[] = [];
  private running: boolean = false;
  private memoryCache: Map<string, string> = new Map();

  private constructor() {}

  static getInstance(): LegadoRuntimeV2 {
    if (!LegadoRuntimeV2.instance) {
      LegadoRuntimeV2.instance = new LegadoRuntimeV2();
    }
    return LegadoRuntimeV2.instance;
  }

  setWebviewController(controller: webview.WebviewController): void {
    this.webviewController = controller;
    this.ready = false;
    logger.info(TAG, 'LegadoRuntimeV2 WebView控制器已设置，等待运行时页面健康检查');
  }

  async setWebviewControllerWhenReady(controller: webview.WebviewController): Promise<boolean> {
    this.webviewController = controller;
    this.ready = false;
    return await this.checkRuntimePageReady();
  }

  async checkRuntimePageReady(): Promise<boolean> {
    if (!this.webviewController) {
      this.ready = false;
      return false;
    }
    try {
      const raw = await this.webviewController.runJavaScript(
        'typeof window.__manxiaLegadoRuntimeExecute === "function" ? "ok" : "missing"'
      );
      const status = this.unwrapWebViewString(String(raw));
      this.ready = status === 'ok';
      if (this.ready) {
        logger.info(TAG, 'LegadoRuntimeV2运行时页面健康检查通过');
        this.processQueue();
      } else {
        logger.warn(TAG, `LegadoRuntimeV2运行时页面健康检查失败: ${status}`);
      }
      return this.ready;
    } catch (error) {
      this.ready = false;
      logger.warn(TAG, `LegadoRuntimeV2运行时页面健康检查异常: ${String(error)}`);
      return false;
    }
  }

  reset(): void {
    this.ready = false;
    this.webviewController = null;
    this.running = false;
    this.queue = [];
  }

  isReady(): boolean {
    return this.ready && this.webviewController !== null;
  }

  async execute(code: string, context: JsContext = {}): Promise<JsExecuteResult> {
    if (!code || code.trim().length <= 0) {
      return { success: true, result: '' };
    }

    const runtimeContext = this.buildRuntimeContext(context);
    return new Promise<JsExecuteResult>((resolve) => {
      const task: PendingTask = {
        code,
        context: runtimeContext,
        resolve
      };
      this.queue.push(task);
      this.processQueue();
    });
  }

  private processQueue(): void {
    if (this.running || this.queue.length <= 0) {
      return;
    }
    if (!this.isReady()) {
      if (!this.webviewController) {
        const task = this.queue.shift();
        if (task) {
          const failed: JsExecuteResult = {
            success: false,
            result: '',
            error: LegadoRuntimeErrorCode.WEBVIEW_NOT_READY
          };
          task.resolve(failed);
        }
      }
      return;
    }

    const task = this.queue.shift();
    if (!task) {
      return;
    }
    this.running = true;
    this.executeTask(task)
      .then((result: JsExecuteResult) => task.resolve(result))
      .catch((error: Error) => {
        const failed: JsExecuteResult = {
          success: false,
          result: '',
          error: String(error)
        };
        task.resolve(failed);
      })
      .finally(() => {
        this.running = false;
        this.processQueue();
      });
  }

  private async executeTask(task: PendingTask): Promise<JsExecuteResult> {
    const state = this.buildInitialState(task.context);
    let envelope: LegadoRuntimeEnvelope | null = null;
    let resolvedBridgeRequestCount = 0;
    while (resolvedBridgeRequestCount < MAX_BRIDGE_REQUEST_COUNT) {
      envelope = await this.runRuntime(task.code, task.context, state);
      this.mergeEnvelopeSourceHeaders(state, envelope);
      if (envelope.status === 'pending' && envelope.bridgeRequests && envelope.bridgeRequests.length > 0) {
        const resolvedCount = await this.resolveBridgeRequests(envelope.bridgeRequests, state);
        if (resolvedCount <= 0) {
          return {
            success: false,
            result: '',
            error: LegadoRuntimeErrorCode.PENDING_BRIDGE_TIMEOUT,
            bridgeTraces: this.buildBridgeTraces(state)
          };
        }
        resolvedBridgeRequestCount += resolvedCount;
        continue;
      }
      return await this.finishEnvelope(envelope, state);
    }

    const failed: JsExecuteResult = {
      success: false,
      result: '',
      error: envelope?.error || LegadoRuntimeErrorCode.BRIDGE_REQUEST_LIMIT_EXCEEDED,
      bridgeTraces: this.buildBridgeTraces(state)
    };
    return failed;
  }

  private async runRuntime(
    code: string,
    context: LegadoRuntimeContext,
    state: LegadoRuntimeState
  ): Promise<LegadoRuntimeEnvelope> {
    if (!this.webviewController) {
      return {
        marker: RUNTIME_MARKER,
        status: 'error',
        errorCode: LegadoRuntimeErrorCode.WEBVIEW_NOT_READY,
        error: 'WebView控制器未就绪'
      };
    }

    const payload: RuntimePayload = {
      code,
      context,
      state
    };
    const script = `window.__manxiaLegadoRuntimeExecute(${JSON.stringify(payload)})`;
    const raw = await this.webviewController.runJavaScript(script);
    return RuntimeJson.parseEnvelope(String(raw));
  }

  private async resolveBridgeRequests(requests: LegadoBridgeRequest[], state: LegadoRuntimeState): Promise<number> {
    let resolvedCount = 0;
    for (let i = 0; i < requests.length; i++) {
      const request = requests[i];
      if (!request || request.id.length <= 0) {
        continue;
      }
      if (state.bridgeResponses[request.id] !== undefined) {
        continue;
      }
      const response = await this.executeBridgeRequest(request);
      state.bridgeResponses[request.id] = response;
      resolvedCount++;
    }
    return resolvedCount;
  }

  private async executeBridgeRequest(request: LegadoBridgeRequest): Promise<LegadoBridgeResponse> {
    if (request.type === 'cache-get') {
      const cacheKey = request.key || '';
      const value = this.memoryCache.get(cacheKey) || '';
      return this.buildBridgeResponse(request, true, value, '', 200, '');
    }
    if (request.type === 'cache-put') {
      const cacheKey = request.key || '';
      this.memoryCache.set(cacheKey, request.value || '');
      return this.buildBridgeResponse(request, true, request.value || '', '', 200, '');
    }
    if (request.type === 'cache-delete') {
      const cacheKey = request.key || '';
      this.memoryCache.delete(cacheKey);
      return this.buildBridgeResponse(request, true, '', '', 200, '');
    }
    if (request.type === 'cookie-get') {
      const cookieUrl = request.url || '';
      const cookieText = cookieUrl.length > 0 ? getCookieStore().getCookie(cookieUrl) : '';
      return this.buildBridgeResponse(request, true, cookieText, cookieUrl, 200, '');
    }
    if (request.type === 'crypto-digest') {
      return await this.executeDigestBridgeRequest(request);
    }
    if (request.type === 'crypto-hmac') {
      return await this.executeHmacBridgeRequest(request);
    }
    if (request.type === 'crypto-symmetric') {
      return await this.executeSymmetricCryptoBridgeRequest(request);
    }
    if (request.type === 'file-read') {
      return this.executeFileReadBridgeRequest(request);
    }
    if (request.type === 'file-write') {
      return this.executeFileWriteBridgeRequest(request);
    }
    if (request.type === 'file-delete') {
      return this.executeFileDeleteBridgeRequest(request);
    }
    if (request.type === 'download-file') {
      return await this.executeDownloadFileBridgeRequest(request);
    }
    if (request.type === 'http') {
      return await this.executeHttpBridgeRequest(request);
    }
    return this.buildBridgeResponse(
      request,
      false,
      '',
      request.url || '',
      0,
      '',
      `不支持的桥接请求类型: ${request.type}`
    );
  }

  private async executeHttpBridgeRequest(request: LegadoBridgeRequest): Promise<LegadoBridgeResponse> {
    const url = request.url || '';
    if (url.length <= 0) {
      return this.buildBridgeResponse(request, false, '', '', 0, '', 'HTTP URL为空');
    }

    let httpRequest: http.HttpRequest | null = null;
    try {
      httpRequest = http.createHttp();
      const method = (request.method || 'GET').trim().toUpperCase();
      const headers = this.buildRequestHeaders(url, request.headers);
      const options: http.HttpRequestOptions = {
        method: method === 'POST' ? http.RequestMethod.POST :
          method === 'HEAD' ? http.RequestMethod.HEAD : http.RequestMethod.GET,
        header: headers,
        connectTimeout: 15000,
        readTimeout: 30000,
        expectDataType: http.HttpDataType.ARRAY_BUFFER
      };
      if (method === 'POST') {
        options.extraData = request.body || '';
      }

      const response = await httpRequest.request(url, options);
      await this.persistResponseCookies(url, response);
      const body = method === 'HEAD' ? '' : this.decodeHttpResponseBody(response);
      const headerText = this.serializeResponseHeaders(response.header);
      return this.buildBridgeResponse(request, true, body, url, response.responseCode, headerText);
    } catch (error) {
      logger.warn(TAG, `桥接HTTP失败: ${url}, ${String(error)}`);
      return this.buildBridgeResponse(
        request,
        false,
        '',
        url,
        0,
        '',
        `${LegadoRuntimeErrorCode.HTTP_FAILED}: ${String(error)}`
      );
    } finally {
      if (httpRequest !== null) {
        httpRequest.destroy();
      }
    }
  }

  private async executeDigestBridgeRequest(request: LegadoBridgeRequest): Promise<LegadoBridgeResponse> {
    try {
      const algorithm = this.normalizeDigestAlgorithm(request.algorithm || request.key || 'MD5');
      const body = await this.digestHex(algorithm, request.value || '');
      return this.buildBridgeResponse(request, true, body, '', 200, '');
    } catch (error) {
      return this.buildBridgeResponse(
        request,
        false,
        '',
        '',
        0,
        '',
        `CRYPTO_DIGEST_FAILED: ${String(error)}`
      );
    }
  }

  private async executeHmacBridgeRequest(request: LegadoBridgeRequest): Promise<LegadoBridgeResponse> {
    try {
      const algorithm = this.normalizeHmacAlgorithm(request.algorithm || 'HmacMD5');
      const mac = cryptoFramework.createMac(algorithm);
      const keyBlob: cryptoFramework.DataBlob = {
        data: this.encodeText(request.key || '')
      };
      const keyGenerator = cryptoFramework.createSymKeyGenerator('HMAC');
      const symKey = await keyGenerator.convertKey(keyBlob);
      await mac.init(symKey);
      await mac.update({ data: this.encodeText(request.value || '') });
      const result = await mac.doFinal();
      return this.buildBridgeResponse(request, true, this.bytesToHex(result.data), '', 200, '');
    } catch (error) {
      return this.buildBridgeResponse(
        request,
        false,
        '',
        '',
        0,
        '',
        `CRYPTO_HMAC_FAILED: ${String(error)}`
      );
    }
  }

  private async executeSymmetricCryptoBridgeRequest(request: LegadoBridgeRequest): Promise<LegadoBridgeResponse> {
    try {
      const operation = (request.method || '').trim();
      const keyBytes = this.decodeBase64(request.key || '');
      const spec = this.resolveSymmetricCipherSpec(request.algorithm || '', keyBytes.length);
      const keyGenerator = cryptoFramework.createSymKeyGenerator(spec.keyAlgorithm);
      const symKey = await keyGenerator.convertKey({ data: keyBytes });
      const ivText = this.getRequestHeader(request.headers, 'x-legado-iv-base64');
      const params = this.buildSymmetricParams(spec, ivText);
      const isEncrypt = operation.startsWith('encrypt');
      const input = this.decodeSymmetricInput(
        request.body || '',
        this.getRequestHeader(request.headers, 'x-legado-input-encoding')
      );
      const cipher = cryptoFramework.createCipher(spec.cipherTransformation);
      await cipher.init(
        isEncrypt ? cryptoFramework.CryptoMode.ENCRYPT_MODE : cryptoFramework.CryptoMode.DECRYPT_MODE,
        symKey,
        params
      );
      const result = await cipher.doFinal({ data: input });
      const body = this.formatSymmetricOutput(operation, result.data);
      return this.buildBridgeResponse(request, true, body, '', 200, '');
    } catch (error) {
      return this.buildBridgeResponse(
        request,
        false,
        '',
        '',
        0,
        '',
        `CRYPTO_SYMMETRIC_FAILED: ${String(error)}`
      );
    }
  }

  private resolveSymmetricCipherSpec(transformation: string, keyLength: number): LegadoSymmetricCipherSpec {
    const parts = transformation.trim().toUpperCase().split('/');
    if (parts.length > 3) {
      throw new Error(`UNSUPPORTED_SYMMETRIC_TRANSFORMATION:${transformation}`);
    }
    const algorithm = parts.length > 0 ? parts[0] : '';
    if (algorithm.length <= 0) {
      throw new Error(`UNSUPPORTED_SYMMETRIC_ALGORITHM:${transformation}`);
    }
    if (parts.length > 1 && parts[1].length <= 0) {
      throw new Error(`UNSUPPORTED_SYMMETRIC_MODE:${transformation}`);
    }
    if (parts.length > 2 && parts[2].length <= 0) {
      throw new Error(`UNSUPPORTED_SYMMETRIC_PADDING:${transformation}`);
    }
    const mode = parts.length > 1 && parts[1].length > 0 ? parts[1] : 'ECB';
    const paddingSource = parts.length > 2 && parts[2].length > 0 ? parts[2] : 'PKCS5PADDING';
    if (mode !== 'ECB' && mode !== 'CBC') {
      throw new Error(`UNSUPPORTED_SYMMETRIC_MODE:${transformation}`);
    }
    let padding = '';
    if (paddingSource === 'PKCS5PADDING' || paddingSource === 'PKCS7PADDING') {
      padding = 'PKCS7';
    } else if (paddingSource === 'NOPADDING') {
      padding = 'NoPadding';
    } else {
      throw new Error(`UNSUPPORTED_SYMMETRIC_PADDING:${transformation}`);
    }
    let keyAlgorithm = '';
    let ivLength = 0;
    if (algorithm === 'AES') {
      if (keyLength === 16) {
        keyAlgorithm = 'AES128';
      } else if (keyLength === 24) {
        keyAlgorithm = 'AES192';
      } else if (keyLength === 32) {
        keyAlgorithm = 'AES256';
      } else {
        throw new Error(`INVALID_AES_KEY_LENGTH:${keyLength}`);
      }
      ivLength = 16;
    } else if (algorithm === 'DES') {
      if (keyLength !== 8) {
        throw new Error(`INVALID_DES_KEY_LENGTH:${keyLength}`);
      }
      keyAlgorithm = 'DES64';
      ivLength = 8;
    } else if (algorithm === 'DESEDE' || algorithm === '3DES') {
      if (keyLength !== 24) {
        throw new Error(`INVALID_3DES_KEY_LENGTH:${keyLength}`);
      }
      keyAlgorithm = '3DES192';
      ivLength = 8;
    } else {
      throw new Error(`UNSUPPORTED_SYMMETRIC_ALGORITHM:${transformation}`);
    }
    return {
      cipherTransformation: `${keyAlgorithm}|${mode}|${padding}`,
      keyAlgorithm,
      mode,
      requiresIv: mode === 'CBC',
      ivLength
    };
  }

  private buildSymmetricParams(
    spec: LegadoSymmetricCipherSpec,
    ivBase64: string
  ): cryptoFramework.ParamsSpec | null {
    if (!spec.requiresIv) {
      return null;
    }
    const iv = this.decodeBase64(ivBase64);
    if (iv.length !== spec.ivLength) {
      throw new Error(`INVALID_${spec.keyAlgorithm}_CBC_IV_LENGTH:${iv.length}`);
    }
    const params: cryptoFramework.IvParamsSpec = {
      // CryptoFramework identifies the parameter object itself as IvParamsSpec;
      // using the AES key algorithm here makes native Cipher.init reject the params.
      algName: 'IvParamsSpec',
      iv: { data: iv }
    };
    return params;
  }

  private decodeSymmetricInput(value: string, encoding: string): Uint8Array {
    if (encoding === 'hex') {
      return this.decodeHex(value);
    }
    if (encoding === 'base64') {
      return this.decodeBase64(value);
    }
    throw new Error(`UNSUPPORTED_SYMMETRIC_INPUT_ENCODING:${encoding}`);
  }

  private formatSymmetricOutput(operation: string, bytes: Uint8Array): string {
    if (operation === 'encryptHex' || operation === 'decryptHex') {
      return this.bytesToHex(bytes);
    }
    if (operation === 'decryptStr' || operation === 'encryptStr') {
      const decoder = new util.TextDecoder();
      return decoder.decodeToString(bytes);
    }
    const base64 = new util.Base64Helper();
    return base64.encodeToStringSync(bytes);
  }

  private decodeBase64(value: string): Uint8Array {
    const base64 = new util.Base64Helper();
    return base64.decodeSync(value);
  }

  private decodeHex(value: string): Uint8Array {
    const text = value.replace(/[^0-9a-fA-F]/g, '');
    if (text.length % 2 !== 0) {
      throw new Error('INVALID_HEX_LENGTH');
    }
    const result = new Uint8Array(text.length / 2);
    for (let i = 0; i < result.length; i++) {
      const segment = text.substring(i * 2, i * 2 + 2);
      result[i] = parseInt(segment, 16);
    }
    return result;
  }

  private getRequestHeader(headers: Record<string, string> | undefined, target: string): string {
    if (!headers) {
      return '';
    }
    const normalizedTarget = target.toLowerCase();
    const keys = Object.keys(headers);
    for (let i = 0; i < keys.length; i++) {
      if (keys[i].toLowerCase() === normalizedTarget) {
        return headers[keys[i]];
      }
    }
    return '';
  }

  private executeFileReadBridgeRequest(request: LegadoBridgeRequest): LegadoBridgeResponse {
    try {
      const resolvedPath = this.resolveRuntimeFilePath(request.path || request.url || '');
      if (resolvedPath.length <= 0) {
        return this.buildBridgeResponse(request, false, '', '', 0, '', 'FILE_READ_PATH_EMPTY');
      }
      const text = SafeFileUtils.readTextSync(resolvedPath, { encoding: 'utf-8' });
      return this.buildBridgeResponse(request, true, text, resolvedPath, 200, '');
    } catch (error) {
      return this.buildBridgeResponse(
        request,
        false,
        '',
        request.path || '',
        0,
        '',
        `FILE_READ_FAILED: ${String(error)}`
      );
    }
  }

  private executeFileWriteBridgeRequest(request: LegadoBridgeRequest): LegadoBridgeResponse {
    let file: fileIo.File | null = null;
    try {
      const resolvedPath = this.resolveRuntimeFilePath(request.path || '');
      if (resolvedPath.length <= 0) {
        return this.buildBridgeResponse(request, false, '', '', 0, '', 'FILE_WRITE_PATH_EMPTY');
      }
      this.ensureParentDirectory(resolvedPath);
      file = SafeFileUtils.openSyncStrict(
        resolvedPath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC | fileIo.OpenMode.WRITE_ONLY
      );
      SafeFileUtils.writeStringExactSync(file.fd, request.value || '');
      const response = this.buildBridgeResponse(request, true, request.value || '', resolvedPath, 200, '');
      response.path = this.toRuntimeRelativePath(resolvedPath);
      return response;
    } catch (error) {
      return this.buildBridgeResponse(
        request,
        false,
        '',
        request.path || '',
        0,
        '',
        `FILE_WRITE_FAILED: ${String(error)}`
      );
    } finally {
      if (file !== null) {
        SafeFileUtils.closeSync(file);
      }
    }
  }

  private executeFileDeleteBridgeRequest(request: LegadoBridgeRequest): LegadoBridgeResponse {
    try {
      const resolvedPath = this.resolveRuntimeFilePath(request.path || request.url || '');
      if (resolvedPath.length <= 0) {
        return this.buildBridgeResponse(request, false, '', '', 0, '', 'FILE_DELETE_PATH_EMPTY');
      }
      if (!SafeFileUtils.accessSync(resolvedPath)) {
        return this.buildBridgeResponse(request, true, '', resolvedPath, 200, '');
      }
      const stat = SafeFileUtils.statSyncStrict(resolvedPath);
      if (stat.isDirectory()) {
        SafeFileUtils.rmdirSync(resolvedPath);
      } else {
        SafeFileUtils.unlinkSyncStrict(resolvedPath);
      }
      return this.buildBridgeResponse(request, true, '', resolvedPath, 200, '');
    } catch (error) {
      return this.buildBridgeResponse(
        request,
        false,
        '',
        request.path || '',
        0,
        '',
        `FILE_DELETE_FAILED: ${String(error)}`
      );
    }
  }

  private async executeDownloadFileBridgeRequest(request: LegadoBridgeRequest): Promise<LegadoBridgeResponse> {
    const url = request.url || '';
    if (url.length <= 0) {
      return this.buildBridgeResponse(request, false, '', '', 0, '', 'DOWNLOAD_URL_EMPTY');
    }

    let httpRequest: http.HttpRequest | null = null;
    let file: fileIo.File | null = null;
    try {
      httpRequest = http.createHttp();
      const headers = this.buildRequestHeaders(url, request.headers);
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: headers,
        connectTimeout: 15000,
        readTimeout: 30000,
        expectDataType: http.HttpDataType.ARRAY_BUFFER
      });
      await this.persistResponseCookies(url, response);
      const buffer: ArrayBuffer = this.httpResultToArrayBuffer(response.result);
      const absolutePath = await this.buildDownloadFilePath(url);
      this.ensureParentDirectory(absolutePath);
      file = SafeFileUtils.openSyncStrict(
        absolutePath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC | fileIo.OpenMode.WRITE_ONLY
      );
      SafeFileUtils.writeExactSync(file.fd, buffer);

      const body = this.decodeArrayBufferBody(buffer, this.getHeaderValue(response.header, 'content-type'));
      const headerText = this.serializeResponseHeaders(response.header);
      const result = this.buildBridgeResponse(request, true, body, url, response.responseCode, headerText);
      result.path = this.toRuntimeRelativePath(absolutePath);
      return result;
    } catch (error) {
      return this.buildBridgeResponse(
        request,
        false,
        '',
        url,
        0,
        '',
        `DOWNLOAD_FAILED: ${String(error)}`
      );
    } finally {
      if (file !== null) {
        SafeFileUtils.closeSync(file);
      }
      if (httpRequest !== null) {
        httpRequest.destroy();
      }
    }
  }

  private normalizeDigestAlgorithm(algorithm: string): string {
    const upper = algorithm.trim().toUpperCase().replace(/-/g, '');
    if (upper === 'SHA1') {
      return 'SHA1';
    }
    if (upper === 'SHA256') {
      return 'SHA256';
    }
    if (upper === 'SHA384') {
      return 'SHA384';
    }
    if (upper === 'SHA512') {
      return 'SHA512';
    }
    return 'MD5';
  }

  private normalizeHmacAlgorithm(algorithm: string): string {
    const upper = algorithm.trim().toUpperCase().replace(/-/g, '');
    if (upper === 'HMACSHA512') {
      return 'SHA512';
    }
    if (upper === 'HMACSHA384') {
      return 'SHA384';
    }
    if (upper === 'HMACSHA256') {
      return 'SHA256';
    }
    if (upper === 'HMACSHA1') {
      return 'SHA1';
    }
    if (upper === 'HMACMD5') {
      return 'MD5';
    }
    throw new Error(`UNSUPPORTED_HMAC_ALGORITHM:${algorithm}`);
  }

  private async digestHex(algorithm: string, value: string): Promise<string> {
    const md = cryptoFramework.createMd(algorithm);
    await md.update({ data: this.encodeText(value) });
    const result = await md.digest();
    return this.bytesToHex(result.data);
  }

  private encodeText(value: string): Uint8Array {
    const encoder = new util.TextEncoder();
    return encoder.encodeInto(value);
  }

  private bytesToHex(bytes: Uint8Array): string {
    const table = '0123456789abcdef';
    let result = '';
    for (let i = 0; i < bytes.length; i++) {
      const value = bytes[i];
      result += table.charAt(value >>> 4);
      result += table.charAt(value & 0x0f);
    }
    return result;
  }

  private unwrapWebViewString(raw: string): string {
    let text = raw === undefined || raw === null ? '' : String(raw);
    if (text.length >= 2 && text.startsWith('"') && text.endsWith('"')) {
      try {
        const parsed = JSON.parse(text) as string;
        text = parsed;
      } catch (_error) {
        // ArkWeb不同版本返回值可能已经是原始字符串。
      }
    }
    return text;
  }

  private async buildDownloadFilePath(url: string): Promise<string> {
    const fileName = `${(await this.digestHex('MD5', url)).substring(8, 24)}.${this.inferUrlSuffix(url)}`;
    return `${this.getRuntimeFileRoot()}/downloads/${fileName}`;
  }

  private inferUrlSuffix(url: string): string {
    const cleanUrl = url.split('?')[0].split('#')[0];
    const slashIndex = cleanUrl.lastIndexOf('/');
    const name = slashIndex >= 0 ? cleanUrl.substring(slashIndex + 1) : cleanUrl;
    const dotIndex = name.lastIndexOf('.');
    if (dotIndex >= 0 && dotIndex < name.length - 1) {
      const suffix = name.substring(dotIndex + 1).replace(/[^0-9A-Za-z]/g, '').toLowerCase();
      if (suffix.length > 0 && suffix.length <= 8) {
        return suffix;
      }
    }
    return 'bin';
  }

  private httpResultToArrayBuffer(result: string | Object | ArrayBuffer): ArrayBuffer {
    if (result instanceof ArrayBuffer) {
      return result;
    }
    const bytes = this.encodeText(String(result || ''));
    const buffer = new ArrayBuffer(bytes.length);
    new Uint8Array(buffer).set(bytes);
    return buffer;
  }

  private getRuntimeFileRoot(): string {
    const context = uiContextManager.getAbilityContext();
    const baseDir = context ? context.cacheDir : '';
    if (baseDir.length <= 0) {
      return 'legado_runtime';
    }
    return `${baseDir}/legado_runtime`;
  }

  private resolveRuntimeFilePath(path: string): string {
    const cleanPath = this.normalizeRuntimePath(path);
    if (cleanPath.length <= 0) {
      return '';
    }
    const context = uiContextManager.getAbilityContext();
    if (context && this.isAllowedAbsolutePath(cleanPath, context.cacheDir, context.filesDir)) {
      return cleanPath;
    }
    return `${this.getRuntimeFileRoot()}/${cleanPath}`;
  }

  private normalizeRuntimePath(path: string): string {
    let cleanPath = path.trim().replace(/\\/g, '/');
    if (cleanPath.startsWith('file://')) {
      cleanPath = cleanPath.substring(7);
    }
    while (cleanPath.startsWith('/')) {
      cleanPath = cleanPath.substring(1);
    }
    const parts = cleanPath.split('/');
    const safeParts: string[] = [];
    for (let i = 0; i < parts.length; i++) {
      const part = parts[i].trim();
      if (part.length <= 0 || part === '.') {
        continue;
      }
      if (part === '..') {
        continue;
      }
      safeParts.push(part.replace(/[^0-9A-Za-z._-]/g, '_'));
    }
    return safeParts.join('/');
  }

  private isAllowedAbsolutePath(path: string, cacheDir: string, filesDir: string): boolean {
    const normalized = path.replace(/\\/g, '/');
    const normalizedCacheDir = cacheDir.replace(/\\/g, '/');
    const normalizedFilesDir = filesDir.replace(/\\/g, '/');
    return normalized.startsWith(`${normalizedCacheDir}/`) ||
      normalized === normalizedCacheDir ||
      normalized.startsWith(`${normalizedFilesDir}/`) ||
      normalized === normalizedFilesDir;
  }

  private ensureParentDirectory(path: string): void {
    const normalized = path.replace(/\\/g, '/');
    const slashIndex = normalized.lastIndexOf('/');
    if (slashIndex <= 0) {
      return;
    }
    const directory = normalized.substring(0, slashIndex);
    if (!SafeFileUtils.accessSync(directory)) {
      SafeFileUtils.mkdirSyncStrict(directory, true);
    }
  }

  private toRuntimeRelativePath(path: string): string {
    const root = this.getRuntimeFileRoot().replace(/\\/g, '/');
    const normalized = path.replace(/\\/g, '/');
    if (normalized.startsWith(`${root}/`)) {
      return normalized.substring(root.length + 1);
    }
    return normalized;
  }

  private buildBridgeResponse(
    request: LegadoBridgeRequest,
    success: boolean,
    body: string,
    url: string,
    code: number,
    headers: string,
    error?: string
  ): LegadoBridgeResponse {
    const method = (request.method || 'GET').trim().toUpperCase();
    const headerNames = request.headers ? Object.keys(request.headers) : [];
    return {
      id: request.id,
      type: request.type,
      success,
      body,
      url,
      code,
      headers,
      method,
      headerNames,
      error
    };
  }

  private buildBridgeTraces(state: LegadoRuntimeState): LegadoBridgeTrace[] {
    const traces: LegadoBridgeTrace[] = [];
    const ids = Object.keys(state.bridgeResponses);
    for (let i = 0; i < ids.length; i++) {
      const response = state.bridgeResponses[ids[i]];
      traces.push(new LegadoBridgeTrace(
        response.id,
        response.type,
        response.url,
        response.method || 'GET',
        response.success,
        response.code,
        response.body.length,
        response.headerNames || [],
        response.error || ''
      ));
    }
    return traces;
  }

  private async finishEnvelope(envelope: LegadoRuntimeEnvelope, state: LegadoRuntimeState): Promise<JsExecuteResult> {
    if (envelope.status !== 'ok') {
      const failed: JsExecuteResult = {
        success: false,
        result: envelope.result || '',
        error: envelope.error || envelope.errorCode || LegadoRuntimeErrorCode.RUNTIME_ERROR,
        diagnostic: envelope.diagnostic,
        logs: envelope.logs,
        bridgeTraces: this.buildBridgeTraces(state)
      };
      return failed;
    }

    this.mergeEnvelopeCache(state, envelope.cache);
    await this.applyCookieChanges(envelope.cookieChanges);

    const success: JsExecuteResult = {
      success: true,
      result: envelope.result || '',
      variables: envelope.variables,
      sourceEffects: envelope.sourceEffects,
      toasts: envelope.toasts,
      logs: envelope.logs,
      cookieChanges: envelope.cookieChanges,
      bridgeTraces: this.buildBridgeTraces(state)
    };
    return success;
  }

  private mergeEnvelopeSourceHeaders(state: LegadoRuntimeState, envelope: LegadoRuntimeEnvelope): void {
    if (envelope.sourceHeaders !== undefined) {
      state.sourceHeaders = envelope.sourceHeaders;
    }
    if (envelope.sourceHeaderResolution !== undefined) {
      state.sourceHeaderResolution = envelope.sourceHeaderResolution;
    }
  }

  private mergeEnvelopeCache(state: LegadoRuntimeState, cache?: Record<string, string>): void {
    const effectiveCache = cache ? cache : state.cache;
    const keys = Object.keys(effectiveCache);
    for (let i = 0; i < keys.length; i++) {
      this.memoryCache.set(keys[i], effectiveCache[keys[i]]);
    }
  }

  private async applyCookieChanges(changes?: CookieChange[]): Promise<void> {
    if (!changes || changes.length <= 0) {
      return;
    }
    const cookieStore = getCookieStore();
    for (let i = 0; i < changes.length; i++) {
      const change = changes[i];
      if (change.action === 'remove') {
        await cookieStore.removeCookie(change.url);
      } else if (change.value !== undefined) {
        await cookieStore.setCookie(change.url, change.value);
      }
    }
  }

  private buildRuntimeContext(context: JsContext): LegadoRuntimeContext {
    const variables = this.copyRecord(context.variables);
    const sourceSnapshot = this.buildSourceSnapshot(context.source);
    const sourceUrl = variables['sourceUrl'] ||
      (sourceSnapshot ? sourceSnapshot.bookSourceUrl : '') ||
      context.baseUrl ||
      '';
    this.mergeSourceVariables(variables, sourceSnapshot);
    const runtimeContext: LegadoRuntimeContext = {
      result: context.result,
      src: context.src !== undefined ? context.src : context.result,
      baseUrl: context.baseUrl,
      key: context.key,
      page: context.page,
      book: this.copyRecord(context.book),
      chapter: this.copyRecord(context.chapter),
      variables,
      jsLib: context.jsLib,
      sourceUrl,
      source: sourceSnapshot
    };
    return runtimeContext;
  }

  private buildSourceSnapshot(source?: LegadoBookSource): LegadoRuntimeSourceSnapshot | undefined {
    if (!source) {
      return undefined;
    }
    const snapshot: LegadoRuntimeSourceSnapshot = {
      bookSourceUrl: source.bookSourceUrl,
      bookSourceName: source.bookSourceName,
      bookSourceType: String(source.bookSourceType)
    };
    if (source.bookSourceGroup !== undefined) {
      snapshot.bookSourceGroup = source.bookSourceGroup;
    }
    if (source.bookSourceComment !== undefined) {
      snapshot.bookSourceComment = source.bookSourceComment;
    }
    if (source.header !== undefined) {
      snapshot.header = source.header;
    }
    if (source.loginUrl !== undefined) {
      snapshot.loginUrl = source.loginUrl;
    }
    if (source.loginUi !== undefined) {
      snapshot.loginUi = source.loginUi;
    }
    if (source.loginCheckJs !== undefined) {
      snapshot.loginCheckJs = source.loginCheckJs;
    }
    if (source.variableComment !== undefined) {
      snapshot.variableComment = source.variableComment;
    }
    if (source.enabledCookieJar !== undefined) {
      snapshot.enabledCookieJar = source.enabledCookieJar;
    }
    return snapshot;
  }

  private mergeSourceVariables(
    variables: Record<string, string>,
    source?: LegadoRuntimeSourceSnapshot
  ): void {
    if (!source) {
      return;
    }
    this.putVariableIfAbsent(variables, 'sourceUrl', source.bookSourceUrl);
    this.putVariableIfAbsent(variables, '__source_bookSourceName', source.bookSourceName);
    this.putVariableIfAbsent(variables, '__source_bookSourceType', source.bookSourceType);
    this.putVariableIfAbsent(variables, '__source_bookSourceGroup', source.bookSourceGroup || '');
    this.putVariableIfAbsent(variables, '__source_bookSourceComment', source.bookSourceComment || '');
    this.putVariableIfAbsent(variables, '__source_header', source.header || '');
    this.putVariableIfAbsent(variables, '__source_loginUrl', source.loginUrl || '');
    this.putVariableIfAbsent(variables, '__source_loginUi', source.loginUi || '');
    this.putVariableIfAbsent(variables, '__source_loginCheckJs', source.loginCheckJs || '');
    this.putVariableIfAbsent(variables, '__source_variableComment', source.variableComment || '');
  }

  private putVariableIfAbsent(variables: Record<string, string>, key: string, value: string): void {
    if (variables[key] === undefined) {
      variables[key] = value;
    }
  }

  private buildInitialState(context: LegadoRuntimeContext): LegadoRuntimeState {
    const cache: Record<string, string> = {};
    this.memoryCache.forEach((value: string, key: string) => {
      cache[key] = value;
    });
    return {
      bridgeResponses: {},
      variables: this.copyRecord(context.variables),
      cache,
      sourceData: this.readSourceData(context.variables),
      sourceHeaders: {},
      sourceHeaderResolution: {},
      randomSeed: this.buildSeed(context),
      now: Date.now()
    };
  }

  private buildSeed(context: LegadoRuntimeContext): number {
    const text = `${context.sourceUrl || ''}|${context.key || ''}|${context.page || 1}|${context.baseUrl || ''}`;
    let hash = 2166136261;
    for (let i = 0; i < text.length; i++) {
      hash ^= text.charCodeAt(i);
      hash = Math.imul(hash, 16777619);
    }
    return hash >>> 0;
  }

  private readSourceData(variables?: Record<string, string>): Record<string, string> {
    const result: Record<string, string> = {};
    const raw = variables ? variables['__sourceData'] : '';
    if (!raw || raw.trim().length <= 0) {
      return result;
    }
    try {
      const parsed = JSON.parse(raw) as Record<string, string>;
      const keys = Object.keys(parsed);
      for (let i = 0; i < keys.length; i++) {
        result[keys[i]] = String(parsed[keys[i]]);
      }
    } catch (_error) {
      // 忽略损坏的sourceData，保持与Legado空缓存降级一致。
    }
    return result;
  }

  private copyRecord(source?: Record<string, string>): Record<string, string> {
    const target: Record<string, string> = {};
    if (!source) {
      return target;
    }
    const keys = Object.keys(source);
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i];
      target[key] = source[key];
    }
    return target;
  }

  private buildRequestHeaders(url: string, headers?: Record<string, string>): Record<string, string> {
    const result: Record<string, string> = {};
    if (headers) {
      const keys = Object.keys(headers);
      for (let i = 0; i < keys.length; i++) {
        result[keys[i]] = headers[keys[i]];
      }
    }
    if (!this.hasHeader(result, 'User-Agent')) {
      result['User-Agent'] = DEFAULT_USER_AGENT;
    }
    if (!this.hasHeader(result, 'Cookie')) {
      const cookie = getCookieStore().getCookie(url);
      if (cookie.length > 0) {
        result['Cookie'] = cookie;
      }
    }
    return result;
  }

  private hasHeader(headers: Record<string, string>, name: string): boolean {
    const target = name.toLowerCase();
    const keys = Object.keys(headers);
    for (let i = 0; i < keys.length; i++) {
      if (keys[i].toLowerCase() === target) {
        return true;
      }
    }
    return false;
  }

  private async persistResponseCookies(url: string, response: http.HttpResponse): Promise<void> {
    const cookieStore = getCookieStore();
    const cookieValues: string[] = [];
    if (response.cookies && response.cookies.length > 0) {
      cookieValues.push(response.cookies);
    }
    const setCookie = this.getHeaderValue(response.header, 'set-cookie');
    if (setCookie.length > 0) {
      cookieValues.push(setCookie);
    }
    for (let i = 0; i < cookieValues.length; i++) {
      const parts = this.splitSetCookieHeader(cookieValues[i]);
      for (let j = 0; j < parts.length; j++) {
        await cookieStore.setCookie(url, parts[j]);
      }
    }
  }

  private splitSetCookieHeader(value: string): string[] {
    const result: string[] = [];
    const lines = value.split('\n');
    for (let i = 0; i < lines.length; i++) {
      const parts = lines[i].split(/,\s*(?=[A-Za-z0-9_.-]+=)/);
      for (let j = 0; j < parts.length; j++) {
        const part = parts[j].trim();
        if (part.length > 0) {
          result.push(part);
        }
      }
    }
    return result;
  }

  private serializeResponseHeaders(headers: Object): string {
    const object = headers as Record<string, string | string[]>;
    const keys = Object.keys(object);
    const lines: string[] = [];
    for (let i = 0; i < keys.length; i++) {
      const value = object[keys[i]];
      if (Array.isArray(value)) {
        lines.push(`${keys[i]}: ${value.join(', ')}`);
      } else {
        lines.push(`${keys[i]}: ${String(value)}`);
      }
    }
    return lines.join('\n');
  }

  private getHeaderValue(headers: Object, name: string): string {
    const target = name.toLowerCase();
    const object = headers as Record<string, string | string[]>;
    const keys = Object.keys(object);
    for (let i = 0; i < keys.length; i++) {
      if (keys[i].toLowerCase() === target) {
        const value = object[keys[i]];
        return Array.isArray(value) ? value.join('\n') : String(value);
      }
    }
    return '';
  }

  private decodeHttpResponseBody(response: http.HttpResponse): string {
    if (typeof response.result === 'string') {
      return this.stripBom(response.result);
    }
    if (response.result instanceof ArrayBuffer) {
      return this.decodeArrayBufferBody(response.result, this.getHeaderValue(response.header, 'content-type'));
    }
    return this.stripBom(String(response.result || ''));
  }

  private decodeArrayBufferBody(buffer: ArrayBuffer, contentType: string): string {
    const charset = this.extractCharset(contentType);
    const decoder = util.TextDecoder.create(charset.length > 0 ? charset : 'utf-8', {
      ignoreBOM: true
    });
    return this.stripBom(decoder.decodeToString(new Uint8Array(buffer)));
  }

  private extractCharset(contentType: string): string {
    const match = /charset\s*=\s*["']?([^;"'\s]+)/i.exec(contentType);
    return match ? match[1].trim() : '';
  }

  private stripBom(value: string): string {
    if (value.length > 0 && value.charCodeAt(0) === 0xFEFF) {
      return value.substring(1);
    }
    return value;
  }
}

export function getLegadoRuntimeV2(): LegadoRuntimeV2 {
  return LegadoRuntimeV2.getInstance();
}
