import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { sha256Hash } from 'manxia_core/src/main/ets/Utils/CryptoUtils';

const TAG: string = 'LegadoImageTransportTrace';
const TRACE_PREFIX: string = 'MANXIA_LEGADO_IMAGE_TRACE:';

export enum LegadoImageTraceEvent {
  PLANNED = 'planned',
  CACHE_HIT = 'cache_hit',
  REQUEST = 'request',
  HTTP_RESPONSE = 'http_response',
  DECODE = 'decode',
  TRANSPORT_FAILURE = 'transport_failure',
  PIPELINE_RESULT = 'pipeline_result'
}

export enum LegadoImageTraceOutcome {
  PLANNED = 'planned',
  CACHE_MEMORY = 'cache_memory',
  CACHE_DISK = 'cache_disk',
  REQUEST_STARTED = 'request_started',
  HTTP_COMPLETE = 'http_complete',
  DECODE_COMPLETE = 'decode_complete',
  DECODE_FAILED = 'decode_failed',
  NETWORK_DNS = 'network_dns',
  NETWORK_TIMEOUT = 'network_timeout',
  NETWORK_TLS = 'network_tls',
  NETWORK_ERROR = 'network_error',
  HTTP_ERROR = 'http_error',
  EMPTY_RESULT = 'empty_result',
  COMPLETE = 'complete'
}

export class LegadoImageTransportTraceContext {
  public traceId: string = '';
  public sourceRawSha256: string = 'unavailable';
  public sourceId: number = 0;
  public pageIndex: number = -1;
  public protocol: string = 'invalid';
  public requestTargetSha256: string = 'empty';
  public requestHeaderNames: string[] = [];
  public requestUserAgentSha256: string = 'empty';
  public statusCode: number = 0;
  public finalTargetSha256: string = 'unobservable';
  public responseContentType: string = '';
  public byteLength: number = 0;
  public decodeOutcome: string = 'not_attempted';
  public outcome: LegadoImageTraceOutcome = LegadoImageTraceOutcome.PLANNED;
  public attempt: number = 0;
  public startedAt: number = Date.now();
}

class LegadoImageTracePayload {
  public schemaVersion: number = 1;
  public event: string = '';
  public traceId: string = '';
  public sourceRawSha256: string = '';
  public sourceId: number = 0;
  public pageIndex: number = -1;
  public protocol: string = '';
  public requestTargetSha256: string = '';
  public requestHeaderNames: string[] = [];
  public requestUserAgentSha256: string = '';
  public outcome: string = '';
  public statusCode: number = 0;
  public finalTargetSha256: string = '';
  public responseContentType: string = '';
  public byteLength: number = 0;
  public decodeOutcome: string = '';
  public attempt: number = 0;
  public elapsedMs: number = 0;

  public constructor(event: LegadoImageTraceEvent, context: LegadoImageTransportTraceContext) {
    this.event = event;
    this.traceId = context.traceId;
    this.sourceRawSha256 = context.sourceRawSha256;
    this.sourceId = context.sourceId;
    this.pageIndex = context.pageIndex;
    this.protocol = context.protocol;
    this.requestTargetSha256 = context.requestTargetSha256;
    this.requestHeaderNames = context.requestHeaderNames.slice();
    this.requestUserAgentSha256 = context.requestUserAgentSha256;
    this.outcome = context.outcome;
    this.statusCode = context.statusCode;
    this.finalTargetSha256 = context.finalTargetSha256;
    this.responseContentType = context.responseContentType;
    this.byteLength = context.byteLength;
    this.decodeOutcome = context.decodeOutcome;
    this.attempt = context.attempt;
    this.elapsedMs = Math.max(0, Date.now() - context.startedAt);
  }
}

/**
 * Evidence-only IMAGE transport trace. It never serializes a URL, header
 * value, cookie, response body, chapter identifier, title or source JSON.
 */
export class LegadoImageTransportTrace {
  public static async createContext(
    sourceRawSha256: string,
    sourceId: number,
    pageIndex: number,
    requestUrl: string
  ): Promise<LegadoImageTransportTraceContext> {
    const context: LegadoImageTransportTraceContext = new LegadoImageTransportTraceContext();
    context.sourceRawSha256 = LegadoImageTransportTrace.normalizeSourceHash(sourceRawSha256);
    context.sourceId = sourceId > 0 ? sourceId : 0;
    context.pageIndex = pageIndex;
    context.protocol = LegadoImageTransportTrace.extractProtocol(requestUrl);
    const normalizedTarget: string = LegadoImageTransportTrace.normalizeRequestTarget(requestUrl);
    context.requestTargetSha256 = await LegadoImageTransportTrace.digestOrMarker(normalizedTarget);
    const traceSeed: string = `${context.sourceRawSha256}|${context.sourceId}|${context.pageIndex}|` +
      `${context.requestTargetSha256}|${context.startedAt}`;
    context.traceId = await LegadoImageTransportTrace.digestOrMarker(traceSeed);
    LegadoImageTransportTrace.emit(LegadoImageTraceEvent.PLANNED, context);
    return context;
  }

  public static recordCacheHit(context: LegadoImageTransportTraceContext, cacheLayer: string): void {
    context.outcome = cacheLayer === 'memory'
      ? LegadoImageTraceOutcome.CACHE_MEMORY
      : LegadoImageTraceOutcome.CACHE_DISK;
    context.decodeOutcome = 'cached_pixel_map';
    LegadoImageTransportTrace.emit(LegadoImageTraceEvent.CACHE_HIT, context);
  }

  public static async recordRequest(
    context: LegadoImageTransportTraceContext,
    headerNames: string[],
    userAgent: string
  ): Promise<void> {
    context.attempt = context.attempt + 1;
    context.requestHeaderNames = LegadoImageTransportTrace.normalizeHeaderNames(headerNames);
    context.requestUserAgentSha256 = await LegadoImageTransportTrace.digestOrMarker(userAgent);
    context.outcome = LegadoImageTraceOutcome.REQUEST_STARTED;
    LegadoImageTransportTrace.emit(LegadoImageTraceEvent.REQUEST, context);
  }

  public static recordHttpResponse(
    context: LegadoImageTransportTraceContext,
    statusCode: number,
    responseContentType: string,
    byteLength: number
  ): void {
    context.statusCode = statusCode;
    context.responseContentType = LegadoImageTransportTrace.normalizeContentType(responseContentType);
    context.byteLength = Math.max(0, byteLength);
    context.outcome = statusCode >= 200 && statusCode < 300
      ? LegadoImageTraceOutcome.HTTP_COMPLETE
      : LegadoImageTraceOutcome.HTTP_ERROR;
    LegadoImageTransportTrace.emit(LegadoImageTraceEvent.HTTP_RESPONSE, context);
  }

  public static recordDecode(
    context: LegadoImageTransportTraceContext,
    success: boolean,
    byteLength: number
  ): void {
    context.byteLength = Math.max(0, byteLength);
    context.decodeOutcome = success ? 'decoded' : 'decode_failed';
    context.outcome = success
      ? LegadoImageTraceOutcome.DECODE_COMPLETE
      : LegadoImageTraceOutcome.DECODE_FAILED;
    LegadoImageTransportTrace.emit(LegadoImageTraceEvent.DECODE, context);
  }

  public static recordTransportFailure(context: LegadoImageTransportTraceContext, errorMessage: string): void {
    if (context.outcome !== LegadoImageTraceOutcome.DECODE_FAILED) {
      context.outcome = LegadoImageTransportTrace.classifyFailure(errorMessage);
    }
    LegadoImageTransportTrace.emit(LegadoImageTraceEvent.TRANSPORT_FAILURE, context);
  }

  public static recordPipelineResult(context: LegadoImageTransportTraceContext, success: boolean): void {
    if (success) {
      context.outcome = LegadoImageTraceOutcome.COMPLETE;
      if (context.decodeOutcome === 'not_attempted') {
        context.decodeOutcome = 'decoded';
      }
    } else if (context.outcome === LegadoImageTraceOutcome.PLANNED ||
      context.outcome === LegadoImageTraceOutcome.REQUEST_STARTED ||
      context.outcome === LegadoImageTraceOutcome.HTTP_COMPLETE) {
      context.outcome = LegadoImageTraceOutcome.EMPTY_RESULT;
    }
    LegadoImageTransportTrace.emit(LegadoImageTraceEvent.PIPELINE_RESULT, context);
  }

  public static normalizeContentType(value: string): string {
    const mediaType: string = value.split(';')[0].trim().toLowerCase();
    if (mediaType.length <= 0) {
      return '';
    }
    return /^[a-z0-9.+-]+\/[a-z0-9.+-]+$/.test(mediaType) ? mediaType : 'invalid';
  }

  private static normalizeSourceHash(value: string): string {
    const normalized: string = value.trim();
    return /^[0-9a-f]{64}$/i.test(normalized) ? normalized.toUpperCase() : 'unavailable';
  }

  private static extractProtocol(value: string): string {
    const match: RegExpMatchArray | null = value.trim().match(/^([a-z][a-z0-9+.-]*):\/\//i);
    return match && match.length > 1 ? match[1].toLowerCase() : 'invalid';
  }

  private static normalizeRequestTarget(value: string): string {
    const match: RegExpMatchArray | null = value.trim().match(/^[a-z][a-z0-9+.-]*:\/\/([^\/?#]+)(\/[^?#]*)?/i);
    if (!match || !match[1]) {
      return '';
    }
    const host: string = match[1].toLowerCase();
    const path: string = match[2] && match[2].length > 0 ? match[2] : '/';
    return `${host}${path}`;
  }

  private static normalizeHeaderNames(values: string[]): string[] {
    const result: string[] = [];
    for (let index: number = 0; index < values.length; index++) {
      const normalized: string = values[index].trim().toLowerCase();
      if (normalized.length > 0 && !result.includes(normalized)) {
        result.push(normalized);
      }
    }
    result.sort();
    return result;
  }

  private static classifyFailure(message: string): LegadoImageTraceOutcome {
    const normalized: string = message.toLowerCase();
    if (normalized.includes('2300006') || normalized.includes('resolve the host') ||
      normalized.includes('could not resolve host') || normalized.includes('curlcode result 6')) {
      return LegadoImageTraceOutcome.NETWORK_DNS;
    }
    if (normalized.includes('timeout') || normalized.includes('timed out') || normalized.includes('2300028')) {
      return LegadoImageTraceOutcome.NETWORK_TIMEOUT;
    }
    if (normalized.includes('certificate') || normalized.includes('ssl') || normalized.includes('tls')) {
      return LegadoImageTraceOutcome.NETWORK_TLS;
    }
    if (normalized.includes('http请求失败') || /http[^0-9]*[45][0-9]{2}/i.test(normalized)) {
      return LegadoImageTraceOutcome.HTTP_ERROR;
    }
    return LegadoImageTraceOutcome.NETWORK_ERROR;
  }

  private static async digestOrMarker(value: string): Promise<string> {
    if (value.length <= 0) {
      return 'empty';
    }
    try {
      return await sha256Hash(value);
    } catch (_error) {
      return 'digest_error';
    }
  }

  private static emit(event: LegadoImageTraceEvent, context: LegadoImageTransportTraceContext): void {
    try {
      const payload: LegadoImageTracePayload = new LegadoImageTracePayload(event, context);
      logger.warnForEvidence(TAG, `${TRACE_PREFIX}${JSON.stringify(payload)}`);
    } catch (_error) {
      logger.warnForEvidence(TAG, `${TRACE_PREFIX}{"schemaVersion":1,"event":"serialization_failed"}`);
    }
  }
}
