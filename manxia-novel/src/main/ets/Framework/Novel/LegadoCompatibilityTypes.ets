/**
 * Legado V2 compatibility contracts.
 *
 * This module intentionally keeps the raw document separate from the compiled
 * source.  The legacy source model remains available for the existing engine,
 * while V2 can report every loss of fidelity before it is enabled.
 */

import {
  LegadoBook,
  LegadoBookSource,
  LegadoBookSourceType,
  LegadoChapter,
  LegadoSearchBook
} from './LegadoSourceTypes';

// Bump whenever compiler or JS bridge semantics change so persisted
// diagnostics are rebuilt from the lossless raw document on the next launch.
export const LEGADO_COMPATIBILITY_SCHEMA_VERSION: number = 3;

export enum LegadoCompatibilityEngineMode {
  LEGACY = 'legacy',
  V2_SHADOW = 'v2_shadow',
  V2_ENABLED = 'v2_enabled'
}

/**
 * Global routing policy for every user-facing Legado workflow.
 *
 * Per-source verification is kept separate from this policy.  In particular,
 * FORCE_TEST never disguises a V2 failure by issuing a second legacy request.
 */
export enum LegadoV2ExecutionPolicy {
  LEGACY_ONLY = 'legacy_only',
  V2_VERIFIED_ONLY = 'v2_verified_only',
  /**
   * Routes every losslessly compiled, standard Legado source through V2 for
   * every user-facing workflow. There is deliberately no legacy fallback:
   * a source that V2 cannot execute remains visibly blocked and traceable.
   */
  V2_FULL_CUTOVER = 'v2_full_cutover',
  /**
   * Compatibility value written by earlier development builds. It is
   * normalized to V2_FULL_CUTOVER when read and must not be exposed as a
   * separate user-facing mode.
   */
  V2_FORCE_TEST = 'v2_force_test'
}

export enum LegadoCompatibilityStatus {
  LEGACY_UNVERIFIABLE = 'legacy_unverifiable',
  PARSED = 'parsed',
  COMPILED = 'compiled',
  READY = 'ready',
  VERIFIED = 'verified',
  NEEDS_INTERACTION = 'needs_interaction',
  UNSUPPORTED = 'unsupported',
  BLOCKED = 'blocked'
}

export enum LegadoDiagnosticSeverity {
  INFO = 'info',
  WARNING = 'warning',
  ERROR = 'error'
}

export enum LegadoCapability {
  HTTP = 'http',
  POST_BODY = 'post_body',
  HEADER = 'header',
  CHARSET = 'charset',
  REDIRECT = 'redirect',
  RETRY = 'retry',
  COOKIE = 'cookie',
  RATE_LIMIT = 'rate_limit',
  WEB_VIEW = 'web_view',
  WEB_JS = 'web_js',
  SOURCE_REGEX = 'source_regex',
  CSS = 'css',
  XPATH = 'xpath',
  JSON_PATH = 'json_path',
  REGEX = 'regex',
  RULE_COMPOSITION = 'rule_composition',
  RULE_VARIABLE = 'rule_variable',
  JAVA_SCRIPT = 'java_script',
  LOGIN = 'login',
  FILE = 'file',
  IMAGE = 'image',
  AUDIO = 'audio',
  REVIEW = 'review',
  PAY_ACTION = 'pay_action',
  IMAGE_DECODE = 'image_decode',
  EXTERNAL_TYPE = 'external_type'
}

export enum LegadoRuleNodeKind {
  CSS = 'css',
  XPATH = 'xpath',
  JSON_PATH = 'json_path',
  REGEX = 'regex',
  REPLACE = 'replace',
  COMPOSE_AND = 'compose_and',
  COMPOSE_OR = 'compose_or',
  VARIABLE_GET = 'variable_get',
  VARIABLE_PUT = 'variable_put',
  TEMPLATE = 'template',
  JAVA_SCRIPT = 'java_script',
  URL_OPTION = 'url_option',
  LITERAL = 'literal'
}

export enum LegadoWorkflowKind {
  SEARCH = 'search',
  EXPLORE = 'explore',
  BOOK_INFO = 'book_info',
  TOC = 'toc',
  CONTENT = 'content',
  FILE = 'file',
  REVIEW = 'review'
}

export enum LegadoTransportKind {
  HTTP = 'http',
  ARK_WEB = 'ark_web'
}

export enum LegadoRequestDisposition {
  EXECUTED = 'executed',
  IGNORED = 'ignored',
  UNSUPPORTED = 'unsupported'
}

export enum LegadoJsApiStatus {
  SUPPORTED = 'supported',
  UNSUPPORTED_API = 'unsupported_api',
  NEEDS_INTERACTION = 'needs_interaction',
  POLICY_BLOCKED = 'policy_blocked'
}

export enum LegadoExecutionErrorCode {
  NONE = 'none',
  INVALID_SOURCE = 'invalid_source',
  UNSUPPORTED_TYPE = 'unsupported_type',
  UNSUPPORTED_API = 'unsupported_api',
  NEEDS_INTERACTION = 'needs_interaction',
  POLICY_BLOCKED = 'policy_blocked',
  NETWORK = 'network',
  HTTP = 'http',
  RULE = 'rule',
  WEB_VIEW = 'web_view',
  CANCELLED = 'cancelled',
  UNKNOWN = 'unknown'
}

/**
 * Evidence for a nested JS bridge request.  It deliberately stores only
 * request metadata and header names; values and response bodies remain out of
 * the persisted trace.  A code of 0 with success=false is a transport-level
 * failure, while an HTTP status code is still a received response that the
 * rule may inspect, matching Legado's AnalyzeUrl contract.
 */
export class LegadoBridgeTrace {
  readonly id: string;
  readonly type: string;
  readonly url: string;
  readonly method: string;
  readonly success: boolean;
  readonly code: number;
  readonly bodyLength: number;
  readonly headerNames: string[];
  readonly errorMessage: string;

  constructor(
    id: string,
    type: string,
    url: string,
    method: string,
    success: boolean,
    code: number,
    bodyLength: number,
    headerNames: string[],
    errorMessage: string
  ) {
    this.id = id;
    this.type = type;
    this.url = url;
    this.method = method;
    this.success = success;
    this.code = code;
    this.bodyLength = bodyLength;
    this.headerNames = headerNames.slice();
    this.errorMessage = errorMessage;
  }

  isTransportFailure(): boolean {
    return this.type === 'http' && !this.success && this.code === 0;
  }
}

/** Whether a transport can prove the final URL after redirects. */
export enum LegadoFinalUrlObservation {
  OBSERVED = 'observed',
  UNOBSERVABLE = 'unobservable'
}

export class RawBookSourceDocument {
  readonly sourceUrl: string;
  readonly rawJson: string;
  readonly sha256: string;
  readonly importedAt: number;
  readonly topLevelFieldNames: string[];
  readonly unknownFieldNames: string[];
  readonly schemaVersion: number;

  constructor(
    sourceUrl: string,
    rawJson: string,
    sha256: string,
    importedAt: number,
    topLevelFieldNames: string[],
    unknownFieldNames: string[]
  ) {
    this.sourceUrl = sourceUrl;
    this.rawJson = rawJson;
    this.sha256 = sha256;
    this.importedAt = importedAt;
    this.topLevelFieldNames = topLevelFieldNames;
    this.unknownFieldNames = unknownFieldNames;
    this.schemaVersion = LEGADO_COMPATIBILITY_SCHEMA_VERSION;
  }
}

export class LegadoRuleSourceLocation {
  readonly workflow: LegadoWorkflowKind;
  readonly field: string;
  readonly ordinal: number;

  constructor(workflow: LegadoWorkflowKind, field: string, ordinal: number) {
    this.workflow = workflow;
    this.field = field;
    this.ordinal = ordinal;
  }
}

export class LegadoRuleIrNode {
  readonly kind: LegadoRuleNodeKind;
  readonly rawText: string;
  readonly location: LegadoRuleSourceLocation;
  readonly requiredCapabilities: LegadoCapability[];
  readonly children: LegadoRuleIrNode[];

  constructor(
    kind: LegadoRuleNodeKind,
    rawText: string,
    location: LegadoRuleSourceLocation,
    requiredCapabilities: LegadoCapability[],
    children: LegadoRuleIrNode[]
  ) {
    this.kind = kind;
    this.rawText = rawText;
    this.location = location;
    this.requiredCapabilities = requiredCapabilities;
    this.children = children;
  }
}

export class LegadoCompiledRule {
  readonly location: LegadoRuleSourceLocation;
  readonly rawText: string;
  readonly root: LegadoRuleIrNode;

  constructor(location: LegadoRuleSourceLocation, rawText: string, root: LegadoRuleIrNode) {
    this.location = location;
    this.rawText = rawText;
    this.root = root;
  }
}

export class LegadoImportDiagnostic {
  readonly severity: LegadoDiagnosticSeverity;
  readonly code: string;
  readonly message: string;
  readonly field: string;

  constructor(severity: LegadoDiagnosticSeverity, code: string, message: string, field: string = '') {
    this.severity = severity;
    this.code = code;
    this.message = message;
    this.field = field;
  }
}

export class LegadoCapabilityReport {
  readonly sourceUrl: string;
  readonly required: LegadoCapability[];
  readonly supported: LegadoCapability[];
  readonly unavailable: LegadoCapability[];
  readonly needsInteraction: boolean;
  readonly unsupportedExternalType: boolean;

  constructor(
    sourceUrl: string,
    required: LegadoCapability[],
    supported: LegadoCapability[],
    unavailable: LegadoCapability[],
    needsInteraction: boolean,
    unsupportedExternalType: boolean
  ) {
    this.sourceUrl = sourceUrl;
    this.required = required;
    this.supported = supported;
    this.unavailable = unavailable;
    this.needsInteraction = needsInteraction;
    this.unsupportedExternalType = unsupportedExternalType;
  }
}

export class CompiledBookSource {
  readonly raw: RawBookSourceDocument;
  readonly source: LegadoBookSource;
  readonly actualSourceType: number;
  readonly rules: LegadoCompiledRule[];
  readonly capabilityReport: LegadoCapabilityReport;
  readonly diagnostics: LegadoImportDiagnostic[];
  readonly status: LegadoCompatibilityStatus;

  constructor(
    raw: RawBookSourceDocument,
    source: LegadoBookSource,
    actualSourceType: number,
    rules: LegadoCompiledRule[],
    capabilityReport: LegadoCapabilityReport,
    diagnostics: LegadoImportDiagnostic[],
    status: LegadoCompatibilityStatus
  ) {
    this.raw = raw;
    this.source = source;
    this.actualSourceType = actualSourceType;
    this.rules = rules;
    this.capabilityReport = capabilityReport;
    this.diagnostics = diagnostics;
    this.status = status;
  }

  isStandardType(): boolean {
    return this.actualSourceType === LegadoBookSourceType.TEXT ||
      this.actualSourceType === LegadoBookSourceType.AUDIO ||
      this.actualSourceType === LegadoBookSourceType.IMAGE ||
      this.actualSourceType === LegadoBookSourceType.FILE;
  }
}

export class ImportReport {
  readonly sourceUrl: string;
  readonly sourceName: string;
  readonly rawDocumentPreserved: boolean;
  readonly compiled: boolean;
  readonly status: LegadoCompatibilityStatus;
  readonly capabilityReport: LegadoCapabilityReport;
  readonly diagnostics: LegadoImportDiagnostic[];

  constructor(
    sourceUrl: string,
    sourceName: string,
    rawDocumentPreserved: boolean,
    compiled: boolean,
    status: LegadoCompatibilityStatus,
    capabilityReport: LegadoCapabilityReport,
    diagnostics: LegadoImportDiagnostic[]
  ) {
    this.sourceUrl = sourceUrl;
    this.sourceName = sourceName;
    this.rawDocumentPreserved = rawDocumentPreserved;
    this.compiled = compiled;
    this.status = status;
    this.capabilityReport = capabilityReport;
    this.diagnostics = diagnostics;
  }
}

/**
 * Per-source state exposed to import and management UI.  It deliberately
 * separates successful parsing from permission to execute through V2.
 */
export class LegadoCompatibilitySummary {
  readonly sourceUrl: string;
  readonly status: LegadoCompatibilityStatus;
  readonly engineMode: LegadoCompatibilityEngineMode;
  readonly rawDocumentPreserved: boolean;
  readonly actualSourceType: number;
  readonly diagnostics: string[];

  constructor(
    sourceUrl: string,
    status: LegadoCompatibilityStatus,
    engineMode: LegadoCompatibilityEngineMode,
    rawDocumentPreserved: boolean,
    actualSourceType: number,
    diagnostics: string[]
  ) {
    this.sourceUrl = sourceUrl;
    this.status = status;
    this.engineMode = engineMode;
    this.rawDocumentPreserved = rawDocumentPreserved;
    this.actualSourceType = actualSourceType;
    this.diagnostics = diagnostics;
  }
}

/** A failed element is retained as evidence instead of being silently skipped. */
export class LegadoCompilationFailure {
  readonly ordinal: number;
  readonly message: string;

  constructor(ordinal: number, message: string) {
    this.ordinal = ordinal;
    this.message = message;
  }
}

export class LegadoCompilationBatchResult {
  readonly compiled: CompiledBookSource[];
  readonly failures: LegadoCompilationFailure[];
  readonly totalDocuments: number;

  constructor(
    compiled: CompiledBookSource[],
    failures: LegadoCompilationFailure[],
    totalDocuments: number
  ) {
    this.compiled = compiled;
    this.failures = failures;
    this.totalDocuments = totalDocuments;
  }
}

/** Opaque database representation; raw source text is never reconstructed from dynamic JSON objects. */
export class LegadoCompatibilityStorageRecord {
  readonly sourceUrl: string;
  readonly rawJson: string;
  readonly rawSha256: string;
  readonly compilerVersion: number;
  readonly status: LegadoCompatibilityStatus;
  readonly engineMode: LegadoCompatibilityEngineMode;
  readonly capabilityJson: string;
  readonly diagnosticsJson: string;
  readonly compiledAt: number;
  readonly updatedAt: number;

  constructor(
    sourceUrl: string,
    rawJson: string,
    rawSha256: string,
    compilerVersion: number,
    status: LegadoCompatibilityStatus,
    engineMode: LegadoCompatibilityEngineMode,
    capabilityJson: string,
    diagnosticsJson: string,
    compiledAt: number,
    updatedAt: number
  ) {
    this.sourceUrl = sourceUrl;
    this.rawJson = rawJson;
    this.rawSha256 = rawSha256;
    this.compilerVersion = compilerVersion;
    this.status = status;
    this.engineMode = engineMode;
    this.capabilityJson = capabilityJson;
    this.diagnosticsJson = diagnosticsJson;
    this.compiledAt = compiledAt;
    this.updatedAt = updatedAt;
  }
}

/**
 * Evidence that a particular raw source document completed the declared V2
 * workflows. The digest points to a redacted trace/golden comparison only;
 * raw responses, headers and cookies are intentionally not persisted here.
 */
export class LegadoSourceVerificationRecord {
  readonly sourceUrl: string;
  readonly rawSha256: string;
  readonly workflows: LegadoWorkflowKind[];
  readonly evidenceDigest: string;
  readonly verifiedAt: number;
  readonly updatedAt: number;

  constructor(
    sourceUrl: string,
    rawSha256: string,
    workflows: LegadoWorkflowKind[],
    evidenceDigest: string,
    verifiedAt: number,
    updatedAt: number
  ) {
    this.sourceUrl = sourceUrl;
    this.rawSha256 = rawSha256;
    this.workflows = workflows;
    this.evidenceDigest = evidenceDigest;
    this.verifiedAt = verifiedAt;
    this.updatedAt = updatedAt;
  }

  includes(workflow: LegadoWorkflowKind): boolean {
    return this.workflows.includes(workflow);
  }
}

export class LegadoRequestHeader {
  readonly name: string;
  readonly value: string;

  constructor(name: string, value: string) {
    this.name = name;
    this.value = value;
  }
}

export class LegadoRequestOptionTrace {
  readonly option: string;
  readonly disposition: LegadoRequestDisposition;
  readonly detail: string;

  constructor(option: string, disposition: LegadoRequestDisposition, detail: string) {
    this.option = option;
    this.disposition = disposition;
    this.detail = detail;
  }
}

export class RequestSpec {
  readonly traceId: string;
  readonly sourceUrl: string;
  readonly workflow: LegadoWorkflowKind;
  readonly url: string;
  readonly method: string;
  readonly body: string;
  readonly headers: LegadoRequestHeader[];
  readonly charset: string;
  readonly retry: number;
  readonly rateLimit: string;
  /** Whether this source explicitly opted into Legado's CookieJar. */
  readonly cookieJarEnabled: boolean;
  readonly useWebView: boolean;
  readonly webJs: string;
  readonly sourceRegex: string;
  readonly webViewDelayTime: number;
  readonly serverId: number;
  /** Raw Legado URL-option `type`; non-text values are never silently coerced. */
  readonly responseType: string;
  readonly redirectPolicy: string;
  readonly optionTrace: LegadoRequestOptionTrace[];

  constructor(
    traceId: string,
    sourceUrl: string,
    workflow: LegadoWorkflowKind,
    url: string,
    method: string,
    body: string,
    headers: LegadoRequestHeader[],
    charset: string,
    retry: number,
    rateLimit: string,
    cookieJarEnabled: boolean,
    useWebView: boolean,
    webJs: string,
    sourceRegex: string,
    webViewDelayTime: number,
    serverId: number,
    responseType: string,
    redirectPolicy: string,
    optionTrace: LegadoRequestOptionTrace[]
  ) {
    this.traceId = traceId;
    this.sourceUrl = sourceUrl;
    this.workflow = workflow;
    this.url = url;
    this.method = method;
    this.body = body;
    this.headers = headers.slice();
    this.charset = charset;
    this.retry = retry;
    this.rateLimit = rateLimit;
    this.cookieJarEnabled = cookieJarEnabled;
    this.useWebView = useWebView;
    this.webJs = webJs;
    this.sourceRegex = sourceRegex;
    this.webViewDelayTime = webViewDelayTime;
    this.serverId = serverId;
    this.responseType = responseType;
    this.redirectPolicy = redirectPolicy;
    this.optionTrace = optionTrace.slice();
  }
}

export class LegadoResponseHeader {
  readonly name: string;
  readonly value: string;

  constructor(name: string, value: string) {
    this.name = name;
    this.value = value;
  }
}

export class ResponseEnvelope {
  readonly traceId: string;
  readonly body: string;
  readonly finalUrl: string;
  readonly finalUrlObservation: LegadoFinalUrlObservation;
  readonly statusCode: number;
  readonly requestHeaders: LegadoRequestHeader[];
  readonly responseHeaders: LegadoResponseHeader[];
  readonly cookiesChanged: boolean;
  readonly redirectChain: string[];
  readonly transport: LegadoTransportKind;
  readonly elapsedMs: number;
  readonly errorCode: LegadoExecutionErrorCode;
  readonly errorMessage: string;

  constructor(
    traceId: string,
    body: string,
    finalUrl: string,
    finalUrlObservation: LegadoFinalUrlObservation,
    statusCode: number,
    requestHeaders: LegadoRequestHeader[],
    responseHeaders: LegadoResponseHeader[],
    cookiesChanged: boolean,
    redirectChain: string[],
    transport: LegadoTransportKind,
    elapsedMs: number,
    errorCode: LegadoExecutionErrorCode,
    errorMessage: string
  ) {
    this.traceId = traceId;
    this.body = body;
    this.finalUrl = finalUrl;
    this.finalUrlObservation = finalUrlObservation;
    this.statusCode = statusCode;
    this.requestHeaders = requestHeaders.slice();
    this.responseHeaders = responseHeaders.slice();
    this.cookiesChanged = cookiesChanged;
    this.redirectChain = redirectChain.slice();
    this.transport = transport;
    this.elapsedMs = elapsedMs;
    this.errorCode = errorCode;
    this.errorMessage = errorMessage;
  }

  isSuccess(): boolean {
    return this.errorCode === LegadoExecutionErrorCode.NONE && this.statusCode >= 200 && this.statusCode < 400;
  }

  /**
   * Legado's AnalyzeUrl hands HTTP error documents to rule evaluation. A
   * status error remains visible in the trace, but a received HTML/JSON body
   * is not a transport absence and must not be discarded before a rule can
   * inspect it.
   */
  hasRuleReadableBody(): boolean {
    return this.isSuccess() ||
      (this.errorCode === LegadoExecutionErrorCode.HTTP && this.body.trim().length > 0);
  }
}

export class LegadoExecutionTrace {
  readonly traceId: string;
  readonly sourceUrl: string;
  readonly workflow: LegadoWorkflowKind;
  readonly request: RequestSpec;
  readonly response: ResponseEnvelope;
  readonly variableChanges: string[];
  readonly outputSummary: string;
  readonly bridgeTraces: LegadoBridgeTrace[];

  constructor(
    traceId: string,
    sourceUrl: string,
    workflow: LegadoWorkflowKind,
    request: RequestSpec,
    response: ResponseEnvelope,
    variableChanges: string[],
    outputSummary: string,
    bridgeTraces: LegadoBridgeTrace[] = []
  ) {
    this.traceId = traceId;
    this.sourceUrl = sourceUrl;
    this.workflow = workflow;
    this.request = request;
    this.response = response;
    this.variableChanges = variableChanges.slice();
    this.outputSummary = outputSummary;
    this.bridgeTraces = bridgeTraces.slice();
  }
}

/**
 * Persisted network evidence deliberately contains only one-way identifiers
 * and a normalized media type. It never stores a URL, request header value,
 * cookie, or response body.
 */
export class LegadoNetworkTraceEvidence {
  readonly requestTargetSha256: string;
  readonly requestUserAgentSha256: string;
  readonly responseContentType: string;
  readonly redirectCount: number;

  constructor(
    requestTargetSha256: string,
    requestUserAgentSha256: string,
    responseContentType: string,
    redirectCount: number
  ) {
    this.requestTargetSha256 = requestTargetSha256;
    this.requestUserAgentSha256 = requestUserAgentSha256;
    this.responseContentType = responseContentType;
    this.redirectCount = redirectCount;
  }
}

/**
 * Fixed-size, persistence-safe diagnostics for a content workflow. These
 * fields deliberately contain only counts, state tokens, and one-way hashes.
 * Keeping them outside outputSummary means device evidence never has to
 * recover correctness data from a presentation string.
 */
export class LegadoContentTraceDiagnostics {
  readonly status: string;
  readonly characterCount: number;
  readonly bridgeStatus: string;
  readonly bridgeCharacterCount: number;
  readonly bridgeFingerprint: string;
  readonly contentFingerprint: string;

  constructor(
    status: string = '',
    characterCount: number = 0,
    bridgeStatus: string = '',
    bridgeCharacterCount: number = 0,
    bridgeFingerprint: string = '',
    contentFingerprint: string = ''
  ) {
    this.status = status;
    this.characterCount = characterCount;
    this.bridgeStatus = bridgeStatus;
    this.bridgeCharacterCount = bridgeCharacterCount;
    this.bridgeFingerprint = bridgeFingerprint;
    this.contentFingerprint = contentFingerprint;
  }
}

/**
 * Persistence-safe V2 execution evidence. This deliberately omits traceId,
 * request URL, headers, cookies, request/response bodies and variable values.
 * rawSha256 binds the observation to the exact losslessly imported source
 * document, so a changed source can never display stale V2 evidence.
 */
export class LegadoExecutionTraceSummary {
  readonly sourceUrl: string;
  readonly rawSha256: string;
  readonly workflow: LegadoWorkflowKind;
  readonly transport: LegadoTransportKind;
  readonly statusCode: number;
  readonly finalUrlObservation: LegadoFinalUrlObservation;
  readonly errorCode: LegadoExecutionErrorCode;
  readonly outputSummary: string;
  readonly optionCount: number;
  readonly variableCount: number;
  readonly occurredAt: number;
  readonly updatedAt: number;
  readonly networkEvidence: LegadoNetworkTraceEvidence;
  readonly contentDiagnostics: LegadoContentTraceDiagnostics;

  constructor(
    sourceUrl: string,
    rawSha256: string,
    workflow: LegadoWorkflowKind,
    transport: LegadoTransportKind,
    statusCode: number,
    finalUrlObservation: LegadoFinalUrlObservation,
    errorCode: LegadoExecutionErrorCode,
    outputSummary: string,
    optionCount: number,
    variableCount: number,
    occurredAt: number,
    updatedAt: number,
    networkEvidence: LegadoNetworkTraceEvidence,
    contentDiagnostics: LegadoContentTraceDiagnostics = new LegadoContentTraceDiagnostics()
  ) {
    this.sourceUrl = sourceUrl;
    this.rawSha256 = rawSha256;
    this.workflow = workflow;
    this.transport = transport;
    this.statusCode = statusCode;
    this.finalUrlObservation = finalUrlObservation;
    this.errorCode = errorCode;
    this.outputSummary = outputSummary;
    this.optionCount = optionCount;
    this.variableCount = variableCount;
    this.occurredAt = occurredAt;
    this.updatedAt = updatedAt;
    this.networkEvidence = networkEvidence;
    this.contentDiagnostics = contentDiagnostics;
  }
}

export class LegadoFileDownloadCandidate {
  readonly url: string;
  readonly name: string;

  constructor(url: string, name: string) {
    this.url = url;
    this.name = name;
  }
}

export enum LegadoWorkflowOutputKind {
  TEXT = 'text',
  AUDIO = 'audio',
  IMAGE = 'image',
  FILE = 'file',
  NONE = 'none'
}

export enum LegadoWorkflowHandoffStatus {
  READY = 'ready',
  EMPTY = 'empty',
  INVALID_OUTPUT = 'invalid_output',
  UNSUPPORTED_API = 'unsupported_api',
  NEEDS_INTERACTION = 'needs_interaction',
  POLICY_BLOCKED = 'policy_blocked',
  MISSING_CONSUMER = 'missing_consumer'
}

export class LegadoAuxiliaryRuleOutcome {
  readonly feature: string;
  readonly status: LegadoJsApiStatus;
  readonly reason: string;

  constructor(feature: string, status: LegadoJsApiStatus, reason: string) {
    this.feature = feature;
    this.status = status;
    this.reason = reason;
  }
}

/**
 * Typed boundary between a V2 workflow and its actual reader/player/downloader
 * consumer. Empty values are never a success: callers must inspect status and
 * reason before selecting a payload field.
 */
export class LegadoWorkflowOutput {
  readonly kind: LegadoWorkflowOutputKind;
  readonly sourceType: number;
  readonly status: LegadoWorkflowHandoffStatus;
  readonly textContent: string;
  readonly mediaUrl: string;
  readonly imageContent: string;
  readonly downloadCandidates: LegadoFileDownloadCandidate[];
  readonly payAction: LegadoAuxiliaryRuleOutcome;
  readonly imageDecode: LegadoAuxiliaryRuleOutcome;
  readonly reasonCode: string;

  constructor(
    kind: LegadoWorkflowOutputKind,
    sourceType: number,
    status: LegadoWorkflowHandoffStatus,
    textContent: string,
    mediaUrl: string,
    imageContent: string,
    downloadCandidates: LegadoFileDownloadCandidate[],
    reasonCode: string,
    payAction?: LegadoAuxiliaryRuleOutcome,
    imageDecode?: LegadoAuxiliaryRuleOutcome
  ) {
    this.kind = kind;
    this.sourceType = sourceType;
    this.status = status;
    this.textContent = textContent;
    this.mediaUrl = mediaUrl;
    this.imageContent = imageContent;
    this.downloadCandidates = downloadCandidates;
    this.reasonCode = reasonCode;
    this.payAction = payAction === undefined
      ? new LegadoAuxiliaryRuleOutcome('payAction', LegadoJsApiStatus.SUPPORTED, 'not_declared')
      : payAction;
    this.imageDecode = imageDecode === undefined
      ? new LegadoAuxiliaryRuleOutcome('imageDecode', LegadoJsApiStatus.SUPPORTED, 'not_declared')
      : imageDecode;
  }

  isReady(): boolean {
    return this.status === LegadoWorkflowHandoffStatus.READY;
  }
}

export class LegadoWorkflowBookInfoResult {
  readonly book: LegadoBook | null;
  readonly downloadCandidates: LegadoFileDownloadCandidate[];
  readonly handoff: LegadoWorkflowOutput;
  readonly trace: LegadoExecutionTrace | null;

  constructor(
    book: LegadoBook | null,
    downloadCandidates: LegadoFileDownloadCandidate[],
    trace: LegadoExecutionTrace | null,
    handoff?: LegadoWorkflowOutput
  ) {
    this.book = book;
    this.downloadCandidates = downloadCandidates;
    this.handoff = handoff === undefined
      ? LegadoWorkflowBookInfoResult.createDefaultHandoff(book, downloadCandidates)
      : handoff;
    this.trace = trace;
  }

  private static createDefaultHandoff(
    book: LegadoBook | null,
    downloadCandidates: LegadoFileDownloadCandidate[]
  ): LegadoWorkflowOutput {
    const sourceType = book === null ? LegadoBookSourceType.TEXT : book.type;
    const kind = sourceType === LegadoBookSourceType.AUDIO
      ? LegadoWorkflowOutputKind.AUDIO
      : sourceType === LegadoBookSourceType.IMAGE
        ? LegadoWorkflowOutputKind.IMAGE
        : sourceType === LegadoBookSourceType.FILE
          ? LegadoWorkflowOutputKind.FILE
          : LegadoWorkflowOutputKind.TEXT;
    const status = book === null
      ? LegadoWorkflowHandoffStatus.EMPTY
      : sourceType === LegadoBookSourceType.FILE && downloadCandidates.length <= 0
        ? LegadoWorkflowHandoffStatus.EMPTY
        : sourceType === LegadoBookSourceType.FILE
          ? LegadoWorkflowHandoffStatus.MISSING_CONSUMER
          : LegadoWorkflowHandoffStatus.READY;
    const reasonCode = book === null
      ? 'book_info_empty'
      : sourceType === LegadoBookSourceType.FILE && downloadCandidates.length <= 0
        ? 'file_download_urls_empty'
        : sourceType === LegadoBookSourceType.FILE
          ? 'file_downloader_consumer_missing'
          : 'book_info_ready';
    return new LegadoWorkflowOutput(
      kind,
      sourceType,
      status,
      '',
      '',
      '',
      downloadCandidates,
      reasonCode
    );
  }
}

export class LegadoWorkflowSearchResult {
  readonly books: LegadoSearchBook[];
  readonly trace: LegadoExecutionTrace | null;

  constructor(books: LegadoSearchBook[], trace: LegadoExecutionTrace | null) {
    this.books = books;
    this.trace = trace;
  }
}

/**
 * A caller-owned result budget for an interactive search. Omitting this
 * object preserves complete Legado workflow execution for conformance work.
 */
export class LegadoSearchExecutionOptions {
  readonly maxResults: number;
  readonly forceFullExecution: boolean;

  constructor(maxResults: number = 0, forceFullExecution: boolean = false) {
    this.maxResults = maxResults > 0 ? Math.floor(maxResults) : 0;
    this.forceFullExecution = forceFullExecution;
  }

  hasResultBudget(): boolean {
    return !this.forceFullExecution && this.maxResults > 0;
  }
}

export class LegadoWorkflowTocResult {
  readonly chapters: LegadoChapter[];
  readonly trace: LegadoExecutionTrace | null;

  constructor(chapters: LegadoChapter[], trace: LegadoExecutionTrace | null) {
    this.chapters = chapters;
    this.trace = trace;
  }
}

export class LegadoWorkflowContentResult {
  readonly content: string;
  readonly title: string;
  readonly handoff: LegadoWorkflowOutput;
  readonly trace: LegadoExecutionTrace | null;

  constructor(
    content: string,
    title: string,
    trace: LegadoExecutionTrace | null,
    handoff?: LegadoWorkflowOutput
  ) {
    this.content = content;
    this.title = title;
    this.handoff = handoff === undefined
      ? new LegadoWorkflowOutput(
        LegadoWorkflowOutputKind.TEXT,
        LegadoBookSourceType.TEXT,
        content.trim().length > 0 ? LegadoWorkflowHandoffStatus.READY : LegadoWorkflowHandoffStatus.EMPTY,
        content,
        '',
        '',
        [],
        content.trim().length > 0 ? 'content_ready' : 'content_empty'
      )
      : handoff;
    this.trace = trace;
  }
}
