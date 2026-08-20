import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { taskpool, util } from '@kit.ArkTS';
import { http } from '@kit.NetworkKit';
import { SettingKeys, SettingsManager } from 'manxia_core/src/main/ets/Framework/Managers/SettingsManager';
import { getCookieStore } from 'manxia_novel/src/main/ets/Framework/Novel/LegadoCookieStore';
import { LegadoSourceParser } from 'manxia_novel/src/main/ets/Framework/Novel/LegadoSourceParser';
import { LegadoUrlAnalyzer, ParsedUrlRequest } from './LegadoUrlAnalyzer';
import { getWebViewExecutor } from 'manxia_novel/src/main/ets/Framework/Novel/LegadoWebViewExecutor';
import {
  LegadoExecutionCancellationToken,
  createLegadoExecutionCancelledError
} from 'manxia_novel/src/main/ets/Framework/Novel/LegadoExecutionCancellation';
import {
  CompiledBookSource,
  LegadoExecutionErrorCode,
  LegadoFinalUrlObservation,
  LegadoRequestDisposition,
  LegadoRequestHeader,
  LegadoRequestOptionTrace,
  LegadoResponseHeader,
  LegadoTransportKind,
  LegadoWorkflowKind,
  RequestSpec,
  ResponseEnvelope
} from 'manxia_novel/src/main/ets/Framework/Novel/LegadoCompatibilityTypes';

const TAG = 'LegadoRequestPipeline';
const DEFAULT_TIMEOUT_MS = 30000;

/**
 * NetStack callbacks can keep the UI event loop busy while a hostile or slow
 * source is negotiating TLS.  Keep the complete native request lifetime in a
 * TaskPool worker; the UI thread only receives the completed response.
 */
@Concurrent
async function executeLegadoHttpRequestTask(
  url: string,
  method: string,
  headers: Record<string, string>,
  body: string,
  timeoutMs: number
): Promise<http.HttpResponse> {
  const request = http.createHttp();
  try {
    const options: http.HttpRequestOptions = {
      method: method === 'POST' ? http.RequestMethod.POST :
        (method === 'HEAD' ? http.RequestMethod.HEAD : http.RequestMethod.GET),
      header: headers,
      connectTimeout: timeoutMs,
      readTimeout: timeoutMs,
      // The fixed Legado reference client installs an unsafe trust manager and
      // hostname verifier for book-source traffic. Keep that compatibility
      // boundary inside the V2 Legado transport only; other app networking
      // continues to use NetStack's system validation.
      remoteValidation: 'skip',
      expectDataType: http.HttpDataType.ARRAY_BUFFER
    };
    if (method === 'POST' && body.length > 0) {
      options.extraData = body;
    }
    return await request.request(url, options);
  } finally {
    request.destroy();
  }
}
/**
 * Legado adds its configured desktop browser UA to every source request unless
 * the source itself provides one.  Keep the compatibility fallback in the
 * request planner so HTTP and ArkWeb receive the same resolved header set.
 */
const LEGADO_REFERENCE_DEFAULT_USER_AGENT =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36';
// OkHttp's default request interceptor advertises these encodings. NetStack's
// platform default differs, so make the pinned Legado baseline explicit while
// still allowing a source or URL option to provide its own value.
const LEGADO_REFERENCE_DEFAULT_ACCEPT_ENCODING = 'gzip, deflate';

enum LegadoDefaultUserAgentOrigin {
  SOURCE = 'source',
  APP_CONFIG = 'app_config',
  UPSTREAM_DEFAULT = 'upstream_default'
}

/**
 * The upstream default is pinned to the verified Legado baseline, but its
 * AppConfig.userAgent behavior remains user-configurable.  A source or URL
 * option still takes precedence over this application-level setting.
 */
class LegadoRequestCompatibilityContract {
  resolveDefaultUserAgent(): string {
    const settings = SettingsManager.getInstance();
    const enabled = settings.getBoolean(SettingKeys.GLOBAL_USER_AGENT_ENABLED, false);
    const configured = settings.getString(SettingKeys.GLOBAL_USER_AGENT, '').trim();
    if (enabled && configured.length > 0) {
      return configured;
    }
    return LEGADO_REFERENCE_DEFAULT_USER_AGENT;
  }

  resolveDefaultUserAgentOrigin(): LegadoDefaultUserAgentOrigin {
    const settings = SettingsManager.getInstance();
    const enabled = settings.getBoolean(SettingKeys.GLOBAL_USER_AGENT_ENABLED, false);
    const configured = settings.getString(SettingKeys.GLOBAL_USER_AGENT, '').trim();
    return enabled && configured.length > 0
      ? LegadoDefaultUserAgentOrigin.APP_CONFIG
      : LegadoDefaultUserAgentOrigin.UPSTREAM_DEFAULT;
  }
}

const requestCompatibilityContract = new LegadoRequestCompatibilityContract();

interface LegadoMergedHeaders {
  headers: LegadoRequestHeader[];
  defaultUserAgentInjected: boolean;
  defaultUserAgentOrigin: LegadoDefaultUserAgentOrigin;
  defaultAcceptEncodingInjected: boolean;
}

export interface LegadoCompatibilityTransport {
  execute(spec: RequestSpec, cancellationToken?: LegadoExecutionCancellationToken): Promise<ResponseEnvelope>;
}

/** A source scoped limiter. It deliberately lives below UI/workflow code. */
class LegadoSourceRateLimiter {
  private readonly nextAllowedAt: Map<string, number> = new Map();

  async wait(
    sourceUrl: string,
    rate: string,
    cancellationToken?: LegadoExecutionCancellationToken
  ): Promise<void> {
    cancellationToken?.throwIfCancelled();
    const interval = this.resolveInterval(rate);
    if (interval <= 0) {
      return;
    }
    const now = Date.now();
    const allowedAt = this.nextAllowedAt.get(sourceUrl) || now;
    const delay = Math.max(0, allowedAt - now);
    if (delay > 0) {
      await waitForCancellationAwareDelay(delay, cancellationToken);
    }
    cancellationToken?.throwIfCancelled();
    this.nextAllowedAt.set(sourceUrl, Date.now() + interval);
  }

  private resolveInterval(rate: string): number {
    const normalized = rate.trim();
    if (normalized.length === 0) {
      return 0;
    }
    const match = normalized.match(/(\d+)\s*\/\s*(\d+)/);
    if (match && match[1] && match[2]) {
      const count = Number(match[1]);
      const windowMs = Number(match[2]);
      if (count > 0 && windowMs > 0) {
        return Math.ceil(windowMs / count);
      }
    }
    const explicitMs = Number(normalized);
    return Number.isFinite(explicitMs) && explicitMs > 0 ? explicitMs : 0;
  }
}

const sourceRateLimiter = new LegadoSourceRateLimiter();

async function waitForCancellationAwareDelay(
  delayMs: number,
  cancellationToken?: LegadoExecutionCancellationToken
): Promise<void> {
  cancellationToken?.throwIfCancelled();
  if (delayMs <= 0) {
    return;
  }
  await new Promise<void>((resolve: () => void, reject: (error: Error) => void): void => {
    let settled = false;
    let timerId = -1;
    let listenerId = 0;
    const clearResources = (): void => {
      if (timerId !== -1) {
        clearTimeout(timerId);
        timerId = -1;
      }
      if (cancellationToken !== undefined && listenerId > 0) {
        cancellationToken.unregister(listenerId);
        listenerId = 0;
      }
    };
    timerId = setTimeout((): void => {
      if (settled) {
        return;
      }
      settled = true;
      clearResources();
      resolve();
    }, delayMs) as number;
    if (cancellationToken !== undefined) {
      listenerId = cancellationToken.register((reason: string): void => {
        if (settled) {
          return;
        }
        settled = true;
        clearResources();
        reject(createLegadoExecutionCancelledError(reason));
      });
    }
  });
}

export class LegadoRequestPlanner {
  private static traceSequence: number = 0;
  private readonly compiled: CompiledBookSource;
  private readonly analyzer: LegadoUrlAnalyzer;

  constructor(compiled: CompiledBookSource) {
    this.compiled = compiled;
    this.analyzer = new LegadoUrlAnalyzer(
      LegadoSourceParser.getBaseUrl(compiled.source),
      compiled.source.bookSourceUrl,
      compiled.source.jsLib || ''
    );
  }

  async plan(
    workflow: LegadoWorkflowKind,
    template: string,
    key: string = '',
    page: number = 1,
    sourceRegex: string = '',
    workflowWebJs: string = ''
  ): Promise<RequestSpec> {
    const parsed = await this.analyzer.analyzeUrlAsync(template, key, page);
    const mergedHeaders = this.mergeHeaders(parsed);
    const headers = mergedHeaders.headers;
    const webJs = (parsed.webJs || workflowWebJs).trim();
    const useWebView = parsed.useWebView === true || webJs.length > 0 || sourceRegex.trim().length > 0;
    const optionTrace = this.buildOptionTrace(
      parsed,
      sourceRegex,
      useWebView,
      mergedHeaders.defaultUserAgentInjected,
      mergedHeaders.defaultUserAgentOrigin,
      mergedHeaders.defaultAcceptEncodingInjected
    );
    const body = parsed.encodedBody !== undefined ? parsed.encodedBody : (parsed.body || '');
    const traceId = this.nextTraceId(workflow);
    return new RequestSpec(
      traceId,
      this.compiled.source.bookSourceUrl,
      workflow,
      parsed.requestUrl || parsed.url,
      String(parsed.method),
      body,
      headers,
      parsed.charset || '',
      Math.max(0, parsed.retry || 0),
      this.compiled.source.concurrentRate || '',
      this.compiled.source.enabledCookieJar === true,
      useWebView,
      webJs,
      sourceRegex,
      parsed.webViewDelayTime || 0,
      parsed.serverId || 0,
      parsed.responseType || '',
      'follow',
      optionTrace
    );
  }

  getVariablesSnapshot(): Map<string, string> {
    const snapshot = new Map<string, string>();
    const values = this.analyzer.getVariablesSnapshot();
    const keys = Object.keys(values);
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i];
      snapshot.set(key, values[key]);
    }
    return snapshot;
  }

  setVariable(key: string, value: string): void {
    this.analyzer.setVariable(key, value);
  }

  private nextTraceId(workflow: LegadoWorkflowKind): string {
    LegadoRequestPlanner.traceSequence++;
    return `${this.compiled.source.bookSourceUrl}|${workflow}|${Date.now()}|${LegadoRequestPlanner.traceSequence}`;
  }

  private mergeHeaders(parsed: ParsedUrlRequest): LegadoMergedHeaders {
    const headers: LegadoRequestHeader[] = [];
    this.appendSourceHeader(headers, this.compiled.source.header || '');
    const parsedKeys = Object.keys(parsed.headers);
    for (let i = 0; i < parsedKeys.length; i++) {
      this.putHeader(headers, parsedKeys[i], parsed.headers[parsedKeys[i]]);
    }
    let defaultUserAgentInjected = false;
    let defaultUserAgentOrigin = LegadoDefaultUserAgentOrigin.SOURCE;
    if (!this.hasHeader(headers, 'User-Agent')) {
      this.putHeader(headers, 'User-Agent', requestCompatibilityContract.resolveDefaultUserAgent());
      defaultUserAgentInjected = true;
      defaultUserAgentOrigin = requestCompatibilityContract.resolveDefaultUserAgentOrigin();
    }
    let defaultAcceptEncodingInjected = false;
    if (!this.hasHeader(headers, 'Accept-Encoding')) {
      this.putHeader(headers, 'Accept-Encoding', LEGADO_REFERENCE_DEFAULT_ACCEPT_ENCODING);
      defaultAcceptEncodingInjected = true;
    }
    if (this.compiled.source.enabledCookieJar === true && !this.hasHeader(headers, 'Cookie')) {
      const cookie = getCookieStore().getCookie(parsed.requestUrl || parsed.url);
      if (cookie.trim().length > 0) {
        this.putHeader(headers, 'Cookie', cookie);
      }
    }
    if (this.compiled.source.enabledCookieJar === true) {
      // AnalyzeUrl.setCookie() in the pinned Legado reference always installs
      // this internal marker. It is part of the observable request plan and
      // tells the transport to merge/persist the source-scoped Cookie store;
      // it must not be treated as an ordinary source header on the wire.
      this.putHeader(headers, 'CookieJar', '1');
    }
    return {
      headers: headers,
      defaultUserAgentInjected: defaultUserAgentInjected,
      defaultUserAgentOrigin: defaultUserAgentOrigin,
      defaultAcceptEncodingInjected: defaultAcceptEncodingInjected
    };
  }

  private appendSourceHeader(target: LegadoRequestHeader[], headerText: string): void {
    const normalized = headerText.trim();
    if (normalized.length === 0) {
      return;
    }
    if (normalized.startsWith('{')) {
      const matches = normalized.matchAll(/['"]([^'"]+)['"]\s*:\s*['"]([^'"]*)['"]/g);
      for (const match of matches) {
        if (match[1] && match[2] !== undefined) {
          this.putHeader(target, match[1], match[2]);
        }
      }
      return;
    }
    // BaseSource.getHeaderMap() in the pinned Legado reference only accepts a
    // JSON object (or a JS result that becomes one). A legacy `Name: Value`
    // string is invalid source.header there and must fall back to the app UA.
    // Do not reinterpret it as an HTTP header just because it is line-shaped.
    return;
  }

  private putHeader(target: LegadoRequestHeader[], name: string, value: string): void {
    const normalizedName = name.trim();
    if (normalizedName.length === 0) {
      return;
    }
    for (let i = 0; i < target.length; i++) {
      if (target[i].name.toLowerCase() === normalizedName.toLowerCase()) {
        target[i] = new LegadoRequestHeader(normalizedName, value);
        return;
      }
    }
    target.push(new LegadoRequestHeader(normalizedName, value));
  }

  private hasHeader(headers: LegadoRequestHeader[], name: string): boolean {
    const normalized = name.toLowerCase();
    for (let i = 0; i < headers.length; i++) {
      if (headers[i].name.toLowerCase() === normalized) {
        return true;
      }
    }
    return false;
  }

  private buildOptionTrace(
    parsed: ParsedUrlRequest,
    sourceRegex: string,
    willUseWebView: boolean,
    defaultUserAgentInjected: boolean,
    defaultUserAgentOrigin: LegadoDefaultUserAgentOrigin,
    defaultAcceptEncodingInjected: boolean
  ): LegadoRequestOptionTrace[] {
    const trace: LegadoRequestOptionTrace[] = [];
    trace.push(new LegadoRequestOptionTrace('method', LegadoRequestDisposition.EXECUTED, String(parsed.method)));
    if ((parsed.body || '').length > 0) trace.push(new LegadoRequestOptionTrace('body', LegadoRequestDisposition.EXECUTED, '请求体已编码'));
    if (Object.keys(parsed.headers).length > 0) trace.push(new LegadoRequestOptionTrace('headers', LegadoRequestDisposition.EXECUTED, '请求头已合并'));
    trace.push(new LegadoRequestOptionTrace(
      'defaultUserAgent',
      defaultUserAgentInjected ? LegadoRequestDisposition.EXECUTED : LegadoRequestDisposition.IGNORED,
      defaultUserAgentInjected
        ? (defaultUserAgentOrigin === LegadoDefaultUserAgentOrigin.APP_CONFIG
          ? '已注入 Legado 应用 User-Agent 配置'
          : '已注入 Legado 固定基线默认 User-Agent')
        : '书源或 URL 选项已声明 User-Agent'
    ));
    trace.push(new LegadoRequestOptionTrace(
      'defaultAcceptEncoding',
      defaultAcceptEncodingInjected ? LegadoRequestDisposition.EXECUTED : LegadoRequestDisposition.IGNORED,
      defaultAcceptEncodingInjected
        ? '已注入 Legado HTTP 编码基线'
        : '书源或 URL 选项已声明 Accept-Encoding'
    ));
    if ((parsed.charset || '').length > 0) trace.push(new LegadoRequestOptionTrace('charset', LegadoRequestDisposition.EXECUTED, parsed.charset || ''));
    if ((parsed.retry || 0) > 0) trace.push(new LegadoRequestOptionTrace('retry', LegadoRequestDisposition.EXECUTED, String(parsed.retry)));
    trace.push(new LegadoRequestOptionTrace(
      'cookieJar',
      this.compiled.source.enabledCookieJar === true ? LegadoRequestDisposition.EXECUTED : LegadoRequestDisposition.IGNORED,
      this.compiled.source.enabledCookieJar === true ? '书源已启用 Cookie Jar' : '书源未启用 Cookie Jar'
    ));
    if (parsed.useWebView === true) trace.push(new LegadoRequestOptionTrace('webView', LegadoRequestDisposition.EXECUTED, 'ArkWeb transport'));
    if ((parsed.webJs || '').length > 0) trace.push(new LegadoRequestOptionTrace('webJs', LegadoRequestDisposition.EXECUTED, 'ArkWeb 执行'));
    if ((parsed.optionJs || '').length > 0) trace.push(new LegadoRequestOptionTrace('js', LegadoRequestDisposition.EXECUTED, 'URL 解析阶段执行'));
    if (sourceRegex.trim().length > 0) trace.push(new LegadoRequestOptionTrace('sourceRegex', LegadoRequestDisposition.EXECUTED, 'ArkWeb 资源拦截'));
    if ((parsed.webViewDelayTime || 0) > 0) {
      trace.push(new LegadoRequestOptionTrace(
        'webViewDelayTime',
        willUseWebView ? LegadoRequestDisposition.EXECUTED : LegadoRequestDisposition.IGNORED,
        willUseWebView ? String(parsed.webViewDelayTime) : '没有 WebView 请求'
      ));
    }
    if ((parsed.serverId || 0) !== 0) {
      trace.push(new LegadoRequestOptionTrace('serverID', LegadoRequestDisposition.IGNORED, '无服务器选择插件'));
    }
    if ((parsed.responseType || '').trim().length > 0) {
      const responseType = (parsed.responseType || '').trim().toLowerCase();
      const textResponse = responseType === 'text' || responseType === 'html' || responseType === 'json';
      trace.push(new LegadoRequestOptionTrace(
        'type',
        textResponse ? LegadoRequestDisposition.EXECUTED : LegadoRequestDisposition.UNSUPPORTED,
        textResponse ? responseType : `二进制类型 ${responseType} 需要 File/Binary 工作流`
      ));
    }
    trace.push(new LegadoRequestOptionTrace('redirect', LegadoRequestDisposition.EXECUTED, '系统 HTTP 默认跟随；HTTP 最终地址单独标记可观测性'));
    return trace;
  }
}

/**
 * HTTP transport owns the non-WebView request path. URL options must retain
 * the same observable request semantics even when no JavaScript rule runs.
 */
export class LegadoHttpTransport implements LegadoCompatibilityTransport {
  async execute(
    spec: RequestSpec,
    cancellationToken?: LegadoExecutionCancellationToken
  ): Promise<ResponseEnvelope> {
    const startedAt = Date.now();
    cancellationToken?.throwIfCancelled();
    await sourceRateLimiter.wait(spec.sourceUrl, spec.rateLimit, cancellationToken);
    let attempt = 0;
    let lastEnvelope: ResponseEnvelope | null = null;
    while (attempt <= spec.retry) {
      cancellationToken?.throwIfCancelled();
      attempt++;
      const envelope = await this.executeAttempt(spec, startedAt, cancellationToken);
      cancellationToken?.throwIfCancelled();
      lastEnvelope = envelope;
      if (envelope.isSuccess() || attempt > spec.retry) {
        return envelope;
      }
    }
    return lastEnvelope || this.failedEnvelope(spec, startedAt, LegadoExecutionErrorCode.UNKNOWN, 'HTTP transport 未返回响应');
  }

  private async executeAttempt(
    spec: RequestSpec,
    startedAt: number,
    cancellationToken?: LegadoExecutionCancellationToken
  ): Promise<ResponseEnvelope> {
    let task: taskpool.Task | null = null;
    let cancellationListenerId = 0;
    cancellationToken?.throwIfCancelled();
    const beforeCookie = spec.cookieJarEnabled ? getCookieStore().getCookie(spec.url) : '';
    try {
      if (cancellationToken !== undefined) {
        cancellationListenerId = cancellationToken.register((_reason: string): void => {
          if (task !== null) {
            // TaskPool can prevent queued work from starting. A task already
            // executing owns its worker-local HttpRequest and is bounded by
            // the connection/read timeout in executeLegadoHttpRequestTask.
            taskpool.cancel(task);
          }
        });
      }
      cancellationToken?.throwIfCancelled();
      // Keep two header views. The original response trace exposes the
      // AnalyzeUrl/OkHttp application request: it contains the CookieJar
      // marker but does not synthesize the body media type. NetStack requires
      // the latter to be passed to the wire request, while CookieJar must be
      // consumed locally before the request leaves the application.
      const observableHeaders = this.toHeaderRecord(spec.headers);
      if (spec.cookieJarEnabled && !this.hasHeader(observableHeaders, 'Cookie') && beforeCookie.length > 0) {
        observableHeaders['Cookie'] = beforeCookie;
      }
      this.applyUpstreamHttpInterceptorDefaults(observableHeaders);
      const wireHeaders = this.removeHeader(this.copyHeaderRecord(observableHeaders), 'CookieJar');
      const method = spec.method.trim().toUpperCase();
      if (method === 'POST' && spec.body.length > 0) {
        if (!this.hasHeader(wireHeaders, 'Content-Type')) {
          wireHeaders['Content-Type'] = spec.body.trim().startsWith('{') || spec.body.trim().startsWith('[')
            ? 'application/json; charset=utf-8'
            // AnalyzeUrl sends a URL-option form through OkHttp postForm(),
            // whose media type has no charset parameter. Some legacy search
            // endpoints distinguish that exact form contract.
          : 'application/x-www-form-urlencoded';
        }
      }
      const effectiveHeaders = this.toHeaderEntries(observableHeaders);
      logger.warnForEvidence(TAG, `V2_STAGE:http_task_create:${spec.workflow}`);
      task = new taskpool.Task(
        executeLegadoHttpRequestTask,
        spec.url,
        method,
        wireHeaders,
        spec.body,
        DEFAULT_TIMEOUT_MS
      );
      logger.warnForEvidence(TAG, `V2_STAGE:http_task_execute:${spec.workflow}`);
      const response = await taskpool.execute(task) as http.HttpResponse;
      logger.warnForEvidence(TAG, `V2_STAGE:http_task_returned:${spec.workflow}`);
      cancellationToken?.throwIfCancelled();
      if (spec.cookieJarEnabled) {
        logger.warnForEvidence(TAG, `V2_STAGE:http_cookie_persist_begin:${spec.workflow}`);
        await this.persistResponseCookies(spec.url, response, cancellationToken);
        logger.warnForEvidence(TAG, `V2_STAGE:http_cookie_persist_returned:${spec.workflow}`);
      }
      cancellationToken?.throwIfCancelled();
      logger.warnForEvidence(TAG, `V2_STAGE:http_cookie_read_begin:${spec.workflow}`);
      const afterCookie = spec.cookieJarEnabled ? getCookieStore().getCookie(spec.url) : '';
      logger.warnForEvidence(TAG, `V2_STAGE:http_cookie_read_returned:${spec.workflow}`);
      const statusCode = response.responseCode;
      logger.warnForEvidence(TAG, `V2_STAGE:http_body_decode_begin:${spec.workflow}`);
      const responseBody = method === 'HEAD' ? '' : this.decodeResponseBody(response, spec.charset);
      logger.warnForEvidence(TAG, `V2_STAGE:http_body_decode_returned:${spec.workflow}`);
      logger.warnForEvidence(TAG, `V2_STAGE:http_headers_convert_begin:${spec.workflow}`);
      const responseHeaders = this.toResponseHeaders(response.header);
      logger.warnForEvidence(TAG, `V2_STAGE:http_headers_convert_returned:${spec.workflow}`);
      return new ResponseEnvelope(
        spec.traceId,
        responseBody,
        spec.url,
        LegadoFinalUrlObservation.UNOBSERVABLE,
        statusCode,
        effectiveHeaders,
        responseHeaders,
        spec.cookieJarEnabled && beforeCookie !== afterCookie,
        [spec.url],
        LegadoTransportKind.HTTP,
        Date.now() - startedAt,
        statusCode >= 200 && statusCode < 400 ? LegadoExecutionErrorCode.NONE : LegadoExecutionErrorCode.HTTP,
        ''
      );
    } catch (error) {
      logger.warnForEvidence(TAG, `V2_STAGE:http_task_failed:${spec.workflow}`);
      if (cancellationToken?.isCancelled() === true) {
        return this.failedEnvelope(
          spec,
          startedAt,
          LegadoExecutionErrorCode.CANCELLED,
          `LEGADO_EXECUTION_CANCELLED:${cancellationToken.getReason()}`
        );
      }
      return this.failedEnvelope(spec, startedAt, LegadoExecutionErrorCode.NETWORK, String(error));
    } finally {
      if (cancellationToken !== undefined && cancellationListenerId > 0) {
        cancellationToken.unregister(cancellationListenerId);
      }
    }
  }

  private toHeaderRecord(headers: LegadoRequestHeader[]): Record<string, string> {
    const record: Record<string, string> = {};
    for (let i = 0; i < headers.length; i++) {
      record[headers[i].name] = headers[i].value;
    }
    return record;
  }

  private copyHeaderRecord(headers: Record<string, string>): Record<string, string> {
    const copy: Record<string, string> = {};
    const keys = Object.keys(headers);
    for (let index = 0; index < keys.length; index++) {
      const key = keys[index];
      copy[key] = headers[key];
    }
    return copy;
  }

  private removeHeader(headers: Record<string, string>, name: string): Record<string, string> {
    const target = name.toLowerCase();
    const filtered: Record<string, string> = {};
    const keys = Object.keys(headers);
    for (let index = 0; index < keys.length; index++) {
      const key = keys[index];
      if (key.toLowerCase() !== target) {
        filtered[key] = headers[key];
      }
    }
    return filtered;
  }

  /**
   * Mirrors the fixed headers applied by Legado's OkHttp interceptor. They are
   * transport semantics, not source-rule defaults, so explicit source headers
   * remain authoritative on platforms whose header API cannot represent a
   * duplicate field name.
   */
  private applyUpstreamHttpInterceptorDefaults(headers: Record<string, string>): void {
    if (!this.hasHeader(headers, 'Keep-Alive')) {
      headers['Keep-Alive'] = '300';
    }
    if (!this.hasHeader(headers, 'Connection')) {
      headers['Connection'] = 'Keep-Alive';
    }
    if (!this.hasHeader(headers, 'Cache-Control')) {
      headers['Cache-Control'] = 'no-cache';
    }
  }

  private toHeaderEntries(headers: Record<string, string>): LegadoRequestHeader[] {
    const entries: LegadoRequestHeader[] = [];
    const keys = Object.keys(headers);
    for (let index = 0; index < keys.length; index++) {
      entries.push(new LegadoRequestHeader(keys[index], headers[keys[index]]));
    }
    return entries;
  }

  private toResponseHeaders(headerObject: Object): LegadoResponseHeader[] {
    const headers: LegadoResponseHeader[] = [];
    const values = headerObject as Record<string, Object>;
    const keys = Object.keys(values);
    for (let i = 0; i < keys.length; i++) {
      const value = values[keys[i]];
      if (Array.isArray(value)) {
        const parts = value as Object[];
        for (let index = 0; index < parts.length; index++) {
          headers.push(new LegadoResponseHeader(keys[i], String(parts[index])));
        }
      } else {
        headers.push(new LegadoResponseHeader(keys[i], String(value)));
      }
    }
    return headers;
  }

  private hasHeader(headers: Record<string, string>, name: string): boolean {
    const lowerName = name.toLowerCase();
    const keys = Object.keys(headers);
    for (let i = 0; i < keys.length; i++) {
      if (keys[i].toLowerCase() === lowerName) {
        return true;
      }
    }
    return false;
  }

  private async persistResponseCookies(
    url: string,
    response: http.HttpResponse,
    cancellationToken?: LegadoExecutionCancellationToken
  ): Promise<void> {
    const values: string[] = [];
    if (response.cookies && response.cookies.length > 0) {
      values.push(response.cookies);
    }
    const headers = this.toResponseHeaders(response.header);
    for (let i = 0; i < headers.length; i++) {
      if (headers[i].name.toLowerCase() === 'set-cookie') {
        values.push(headers[i].value);
      }
    }
    for (let i = 0; i < values.length; i++) {
      cancellationToken?.throwIfCancelled();
      const parts = values[i].split(/\r?\n/);
      for (let index = 0; index < parts.length; index++) {
        cancellationToken?.throwIfCancelled();
        const cookie = parts[index].trim();
        if (cookie.length > 0) {
          await getCookieStore().setCookie(url, cookie);
        }
      }
    }
  }

  private decodeResponseBody(response: http.HttpResponse, explicitCharset: string): string {
    const result = response.result;
    if (!(result instanceof ArrayBuffer)) {
      return String(result);
    }
    const bytes = new Uint8Array(result);
    const charset = this.resolveCharset(explicitCharset, response.header);
    try {
      return util.TextDecoder.create(charset, { ignoreBOM: true }).decodeToString(bytes);
    } catch (error) {
      logger.warn(TAG, `按 ${charset} 解码响应失败，回退 UTF-8: ${String(error)}`);
      return util.TextDecoder.create('utf-8', { ignoreBOM: true }).decodeToString(bytes);
    }
  }

  private resolveCharset(explicitCharset: string, headers: Object): string {
    const explicit = explicitCharset.trim();
    if (explicit.length > 0) {
      return explicit.toLowerCase() === 'utf8' ? 'utf-8' : explicit;
    }
    const responseHeaders = this.toResponseHeaders(headers);
    for (let i = 0; i < responseHeaders.length; i++) {
      if (responseHeaders[i].name.toLowerCase() !== 'content-type') {
        continue;
      }
      const match = responseHeaders[i].value.match(/charset\s*=\s*["']?([^"';,\s>]+)/i);
      if (match && match[1]) {
        return match[1].trim();
      }
    }
    return 'utf-8';
  }

  private failedEnvelope(
    spec: RequestSpec,
    startedAt: number,
    code: LegadoExecutionErrorCode,
    message: string
  ): ResponseEnvelope {
    return new ResponseEnvelope(
      spec.traceId, '', spec.url, LegadoFinalUrlObservation.UNOBSERVABLE, 0, spec.headers, [], false, [spec.url],
      LegadoTransportKind.HTTP, Date.now() - startedAt, code, message
    );
  }
}

export class LegadoArkWebTransport implements LegadoCompatibilityTransport {
  async execute(
    spec: RequestSpec,
    cancellationToken?: LegadoExecutionCancellationToken
  ): Promise<ResponseEnvelope> {
    const startedAt = Date.now();
    cancellationToken?.throwIfCancelled();
    await sourceRateLimiter.wait(spec.sourceUrl, spec.rateLimit, cancellationToken);
    if (!getWebViewExecutor().isWebViewReady()) {
      return new ResponseEnvelope(
        spec.traceId, '', spec.url, LegadoFinalUrlObservation.UNOBSERVABLE, 0, spec.headers, [], false, [spec.url],
        LegadoTransportKind.ARK_WEB, Date.now() - startedAt,
        LegadoExecutionErrorCode.WEB_VIEW, 'WEBVIEW_NOT_READY'
      );
    }
    try {
      cancellationToken?.throwIfCancelled();
      const beforeCookie = getCookieStore().getCookie(spec.url);
      const result = await getWebViewExecutor().execute({
        url: spec.url,
        javaScript: spec.webJs || undefined,
        headers: this.toHeaderRecord(spec.headers),
        sourceRegex: spec.sourceRegex || undefined,
        tag: spec.sourceUrl,
        postLoadDelayTime: spec.webViewDelayTime,
        timeout: DEFAULT_TIMEOUT_MS,
        cancellationToken: cancellationToken
      });
      cancellationToken?.throwIfCancelled();
      // Cookie 回写发生在原始请求 URL 的域名范围内。若页面最终跳转到其他
      // 域名，按最终 URL 查询会漏掉原始域名刚写入的 Cookie。
      const afterCookie = getCookieStore().getCookie(spec.url);
      const hasHttpFailure: boolean = !result.success && result.statusCode !== undefined && result.statusCode >= 400;
      let statusCode: number = 0;
      if (result.success) {
        statusCode = 200;
      } else if (hasHttpFailure && result.statusCode !== undefined) {
        statusCode = result.statusCode;
      }
      const errorCode: LegadoExecutionErrorCode = result.success
        ? LegadoExecutionErrorCode.NONE
        : (hasHttpFailure ? LegadoExecutionErrorCode.HTTP : LegadoExecutionErrorCode.WEB_VIEW);
      const diagnostic: string = result.diagnostic || '';
      return new ResponseEnvelope(
        spec.traceId,
        result.body,
        result.url || spec.url,
        result.success ? LegadoFinalUrlObservation.OBSERVED : LegadoFinalUrlObservation.UNOBSERVABLE,
        statusCode,
        spec.headers,
        [],
        beforeCookie !== afterCookie,
        [spec.url, result.url || spec.url],
        LegadoTransportKind.ARK_WEB,
        Date.now() - startedAt,
        errorCode,
        result.error || diagnostic
      );
    } catch (error) {
      if (cancellationToken?.isCancelled() === true) {
        return new ResponseEnvelope(
          spec.traceId, '', spec.url, LegadoFinalUrlObservation.UNOBSERVABLE, 0, spec.headers, [], false, [spec.url],
          LegadoTransportKind.ARK_WEB, Date.now() - startedAt,
          LegadoExecutionErrorCode.CANCELLED,
          `LEGADO_EXECUTION_CANCELLED:${cancellationToken.getReason()}`
        );
      }
      return new ResponseEnvelope(
        spec.traceId, '', spec.url, LegadoFinalUrlObservation.UNOBSERVABLE, 0, spec.headers, [], false, [spec.url],
        LegadoTransportKind.ARK_WEB, Date.now() - startedAt,
        LegadoExecutionErrorCode.WEB_VIEW, String(error)
      );
    }
  }

  private toHeaderRecord(headers: LegadoRequestHeader[]): Record<string, string> {
    const record: Record<string, string> = {};
    for (let i = 0; i < headers.length; i++) {
      // Legado's OkHttp interceptor removes this explicit sentinel before
      // sending. ArkTS forbids delete, so omit it at record construction.
      if (headers[i].name.toLowerCase() === 'user-agent' && headers[i].value === 'null') {
        continue;
      }
      record[headers[i].name] = headers[i].value;
    }
    return record;
  }
}

export class LegadoTransportRouter {
  private readonly httpTransport: LegadoHttpTransport = new LegadoHttpTransport();
  private readonly arkWebTransport: LegadoArkWebTransport = new LegadoArkWebTransport();

  async execute(
    spec: RequestSpec,
    cancellationToken?: LegadoExecutionCancellationToken
  ): Promise<ResponseEnvelope> {
    cancellationToken?.throwIfCancelled();
    if (!this.supportsTextResponse(spec.responseType)) {
      return new ResponseEnvelope(
        spec.traceId,
        '',
        spec.url,
        LegadoFinalUrlObservation.UNOBSERVABLE,
        0,
        spec.headers,
        [],
        false,
        [spec.url],
        LegadoTransportKind.HTTP,
        0,
        LegadoExecutionErrorCode.UNSUPPORTED_TYPE,
        `UNSUPPORTED_URL_OPTION_TYPE:${spec.responseType}`
      );
    }
    if (spec.useWebView || spec.webJs.length > 0 || spec.sourceRegex.length > 0) {
      logger.debug(TAG, `ArkWeb transport: ${spec.workflow} ${spec.url}`);
      const response = await this.arkWebTransport.execute(spec, cancellationToken);
      cancellationToken?.throwIfCancelled();
      return response;
    }
    logger.debug(TAG, `HTTP transport: ${spec.workflow} ${spec.url}`);
    const response = await this.httpTransport.execute(spec, cancellationToken);
    cancellationToken?.throwIfCancelled();
    return response;
  }

  private supportsTextResponse(responseType: string): boolean {
    const normalized = responseType.trim().toLowerCase();
    return normalized.length === 0 || normalized === 'text' || normalized === 'html' || normalized === 'json';
  }
}
