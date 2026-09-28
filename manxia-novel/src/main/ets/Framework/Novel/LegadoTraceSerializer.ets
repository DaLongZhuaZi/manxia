import { sha256Hash } from 'manxia_core/src/main/ets/Utils/CryptoUtils';
import {
  LegadoExecutionTrace,
  LegadoBridgeTrace,
  LegadoNetworkTraceEvidence,
  LegadoRequestHeader,
  LegadoResponseHeader
} from './LegadoCompatibilityTypes';

class RedactedTraceHeader {
  readonly name: string;
  readonly value: string;

  constructor(name: string, value: string) {
    this.name = name;
    this.value = value;
  }
}

class RedactedTraceRequest {
  readonly url: string;
  readonly method: string;
  readonly bodyLength: number;
  readonly charset: string;
  readonly retry: number;
  readonly transportHint: string;
  readonly responseType: string;
  readonly headers: RedactedTraceHeader[];
  readonly optionTrace: string[];

  constructor(
    url: string,
    method: string,
    bodyLength: number,
    charset: string,
    retry: number,
    transportHint: string,
    responseType: string,
    headers: RedactedTraceHeader[],
    optionTrace: string[]
  ) {
    this.url = url;
    this.method = method;
    this.bodyLength = bodyLength;
    this.charset = charset;
    this.retry = retry;
    this.transportHint = transportHint;
    this.responseType = responseType;
    this.headers = headers;
    this.optionTrace = optionTrace;
  }
}

class RedactedTraceResponse {
  readonly statusCode: number;
  readonly finalUrl: string;
  readonly finalUrlObservation: string;
  readonly bodyLength: number;
  readonly cookiesChanged: boolean;
  readonly redirectCount: number;
  readonly transport: string;
  readonly elapsedMs: number;
  readonly errorCode: string;
  readonly errorMessage: string;
  readonly headers: RedactedTraceHeader[];

  constructor(
    statusCode: number,
    finalUrl: string,
    finalUrlObservation: string,
    bodyLength: number,
    cookiesChanged: boolean,
    redirectCount: number,
    transport: string,
    elapsedMs: number,
    errorCode: string,
    errorMessage: string,
    headers: RedactedTraceHeader[]
  ) {
    this.statusCode = statusCode;
    this.finalUrl = finalUrl;
    this.finalUrlObservation = finalUrlObservation;
    this.bodyLength = bodyLength;
    this.cookiesChanged = cookiesChanged;
    this.redirectCount = redirectCount;
    this.transport = transport;
    this.elapsedMs = elapsedMs;
    this.errorCode = errorCode;
    this.errorMessage = errorMessage;
    this.headers = headers;
  }
}

class RedactedBridgeTrace {
  readonly id: string;
  readonly type: string;
  readonly url: string;
  readonly method: string;
  readonly success: boolean;
  readonly statusCode: number;
  readonly bodyLength: number;
  readonly headerNames: string[];
  readonly errorMessage: string;

  constructor(trace: LegadoBridgeTrace) {
    this.id = trace.id;
    this.type = trace.type;
    this.url = LegadoTraceSerializer.redactUrl(trace.url);
    this.method = trace.method;
    this.success = trace.success;
    this.statusCode = trace.code;
    this.bodyLength = trace.bodyLength;
    this.headerNames = trace.headerNames.slice();
    this.errorMessage = LegadoTraceSerializer.redactText(trace.errorMessage);
  }
}

class RedactedExecutionTrace {
  readonly traceId: string;
  readonly sourceUrl: string;
  readonly workflow: string;
  readonly request: RedactedTraceRequest;
  readonly response: RedactedTraceResponse;
  readonly variableKeys: string[];
  readonly outputSummary: string;
  readonly bridgeTraces: RedactedBridgeTrace[];

  constructor(
    traceId: string,
    sourceUrl: string,
    workflow: string,
    request: RedactedTraceRequest,
    response: RedactedTraceResponse,
    variableKeys: string[],
    outputSummary: string,
    bridgeTraces: RedactedBridgeTrace[]
  ) {
    this.traceId = traceId;
    this.sourceUrl = sourceUrl;
    this.workflow = workflow;
    this.request = request;
    this.response = response;
    this.variableKeys = variableKeys;
    this.outputSummary = outputSummary;
    this.bridgeTraces = bridgeTraces;
  }
}

/**
 * Produces evidence-safe trace JSON.  It intentionally never serializes raw
 * source JSON, request/response bodies, cookie values, or variable values.
 */
export class LegadoTraceSerializer {
  static toRedactedJson(trace: LegadoExecutionTrace): string {
    const requestHeaders = LegadoTraceSerializer.redactRequestHeaders(trace.request.headers);
    const responseHeaders = LegadoTraceSerializer.redactResponseHeaders(trace.response.responseHeaders);
    const optionTrace: string[] = [];
    for (let i = 0; i < trace.request.optionTrace.length; i++) {
      const option = trace.request.optionTrace[i];
      optionTrace.push(`${option.option}:${option.disposition}:${LegadoTraceSerializer.redactText(option.detail)}`);
    }
    const request = new RedactedTraceRequest(
      LegadoTraceSerializer.redactUrl(trace.request.url),
      trace.request.method,
      trace.request.body.length,
      trace.request.charset,
      trace.request.retry,
      trace.request.useWebView ? 'ark_web' : 'http',
      trace.request.responseType,
      requestHeaders,
      optionTrace
    );
    const response = new RedactedTraceResponse(
      trace.response.statusCode,
      LegadoTraceSerializer.redactUrl(trace.response.finalUrl),
      trace.response.finalUrlObservation,
      trace.response.body.length,
      trace.response.cookiesChanged,
      trace.response.redirectChain.length,
      trace.response.transport,
      trace.response.elapsedMs,
      trace.response.errorCode,
      LegadoTraceSerializer.redactText(trace.response.errorMessage),
      responseHeaders
    );
    const output = new RedactedExecutionTrace(
      trace.traceId,
      LegadoTraceSerializer.redactUrl(trace.sourceUrl),
      trace.workflow,
      request,
      response,
      trace.variableChanges.slice(),
      LegadoTraceSerializer.redactText(trace.outputSummary),
      trace.bridgeTraces.map((item: LegadoBridgeTrace): RedactedBridgeTrace => new RedactedBridgeTrace(item))
    );
    return JSON.stringify(output);
  }

  /**
   * Generates restart-safe network evidence without retaining the address or
   * any header value. Hashing only origin host and path also excludes query
   * parameters, which may contain a transient credential.
   */
  static async toNetworkTraceEvidence(trace: LegadoExecutionTrace): Promise<LegadoNetworkTraceEvidence> {
    const target = LegadoTraceSerializer.normalizeRequestTarget(trace.request.url);
    const userAgent = LegadoTraceSerializer.findHeader(trace.request.headers, 'User-Agent');
    const requestTargetSha256 = await LegadoTraceSerializer.digestOrMarker(target);
    const requestUserAgentSha256 = await LegadoTraceSerializer.digestOrMarker(userAgent);
    const responseContentType = LegadoTraceSerializer.normalizeContentType(
      LegadoTraceSerializer.findResponseHeader(trace.response.responseHeaders, 'Content-Type')
    );
    return new LegadoNetworkTraceEvidence(
      requestTargetSha256,
      requestUserAgentSha256,
      responseContentType,
      Math.max(0, trace.response.redirectChain.length - 1)
    );
  }

  private static async digestOrMarker(value: string): Promise<string> {
    if (value.length <= 0) {
      return 'empty';
    }
    try {
      return await sha256Hash(value);
    } catch {
      return 'digest_error';
    }
  }

  private static normalizeRequestTarget(value: string): string {
    const trimmed = value.trim();
    const match = trimmed.match(/^[a-z][a-z0-9+.-]*:\/\/([^\/?#]+)(\/[^?#]*)?/i);
    if (!match || !match[1]) {
      return '';
    }
    const host = match[1].toLowerCase();
    const path = match[2] && match[2].length > 0 ? match[2] : '/';
    return `${host}${path}`;
  }

  private static normalizeContentType(value: string): string {
    const mediaType = value.split(';')[0].trim().toLowerCase();
    if (mediaType.length <= 0) {
      return '';
    }
    return /^[a-z0-9.+-]+\/[a-z0-9.+-]+$/.test(mediaType) ? mediaType : 'invalid';
  }

  private static findHeader(headers: LegadoRequestHeader[], name: string): string {
    const normalized = name.toLowerCase();
    for (let index = 0; index < headers.length; index++) {
      if (headers[index].name.toLowerCase() === normalized) {
        return headers[index].value;
      }
    }
    return '';
  }

  private static findResponseHeader(headers: LegadoResponseHeader[], name: string): string {
    const normalized = name.toLowerCase();
    for (let index = 0; index < headers.length; index++) {
      if (headers[index].name.toLowerCase() === normalized) {
        return headers[index].value;
      }
    }
    return '';
  }

  private static redactRequestHeaders(headers: LegadoRequestHeader[]): RedactedTraceHeader[] {
    const result: RedactedTraceHeader[] = [];
    for (let i = 0; i < headers.length; i++) {
      result.push(new RedactedTraceHeader(
        headers[i].name,
        LegadoTraceSerializer.redactHeaderValue(headers[i].name, headers[i].value)
      ));
    }
    return result;
  }

  private static redactResponseHeaders(headers: LegadoResponseHeader[]): RedactedTraceHeader[] {
    const result: RedactedTraceHeader[] = [];
    for (let i = 0; i < headers.length; i++) {
      result.push(new RedactedTraceHeader(
        headers[i].name,
        LegadoTraceSerializer.redactHeaderValue(headers[i].name, headers[i].value)
      ));
    }
    return result;
  }

  private static redactHeaderValue(name: string, value: string): string {
    if (LegadoTraceSerializer.isSensitiveName(name)) {
      return '[REDACTED]';
    }
    return LegadoTraceSerializer.redactText(value);
  }

  static redactUrl(url: string): string {
    let output = url.replace(/:\/\/([^/@:]+):([^/@]+)@/g, '://$1:[REDACTED]@');
    output = output.replace(/([?&](?:token|access_token|auth|authorization|cookie|session|sid|key|secret|password)=)[^&#\s]*/gi, '$1[REDACTED]');
    return output;
  }

  static redactText(value: string): string {
    let output = value;
    output = output.replace(/((?:cookie|authorization|token|access_token|secret|password|session|sid|key)\s*[:=]\s*)[^,;\s"'}]+/gi, '$1[REDACTED]');
    // Bridge failures may include a credential-shaped bare token rather than
    // a key/value pair (for example: `HTTP_FAILED: secret-token`).  These
    // values are still sensitive and must not survive in persisted evidence.
    output = output.replace(/(?<![A-Za-z0-9])(?:access[_-]?token|authorization|cookie|password|session|secret|token|sid|key)[_-][A-Za-z0-9._~+\/=:-]+/gi, '[REDACTED]');
    output = output.replace(/(Bearer\s+)[A-Za-z0-9._~+\/=:-]+/gi, '$1[REDACTED]');
    return output;
  }

  private static isSensitiveName(name: string): boolean {
    const normalized = name.toLowerCase();
    return normalized.includes('cookie') || normalized.includes('authorization') ||
      normalized.includes('token') || normalized.includes('secret') ||
      normalized.includes('password') || normalized.includes('key');
  }
}

/** In-memory handoff for UI diagnostics and instrumented conformance tests. */
export class LegadoExecutionTraceStore {
  private static instance: LegadoExecutionTraceStore | null = null;
  private readonly traces: Map<string, string> = new Map();

  static getInstance(): LegadoExecutionTraceStore {
    if (LegadoExecutionTraceStore.instance === null) {
      LegadoExecutionTraceStore.instance = new LegadoExecutionTraceStore();
    }
    return LegadoExecutionTraceStore.instance;
  }

  record(trace: LegadoExecutionTrace): string {
    const serialized = LegadoTraceSerializer.toRedactedJson(trace);
    this.traces.set(trace.traceId, serialized);
    return serialized;
  }

  get(traceId: string): string | null {
    return this.traces.get(traceId) || null;
  }

  clear(): void {
    this.traces.clear();
  }
}

export function getLegadoExecutionTraceStore(): LegadoExecutionTraceStore {
  return LegadoExecutionTraceStore.getInstance();
}
