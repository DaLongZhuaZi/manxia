export enum NetworkTransportFailureKind {
  NONE = 'none',
  DNS = 'dns',
  TLS = 'tls',
  TIMEOUT = 'timeout',
  HTTP = 'http',
  NETWORK = 'network'
}

export class NetworkTransportFailureDescriptor {
  public recognized: boolean = false;
  public kind: NetworkTransportFailureKind = NetworkTransportFailureKind.NONE;
  public host: string = '';
  public code: string = '';
  public fingerprint: string = '';
  public canonicalMessage: string = '';
  public circuitEligible: boolean = false;
}

export class NetworkTransportCircuitDecision {
  public suppressed: boolean = false;
  public remainingMs: number = 0;
  public descriptor: NetworkTransportFailureDescriptor = new NetworkTransportFailureDescriptor();
}

class NetworkTransportHostCircuitState {
  public descriptor: NetworkTransportFailureDescriptor = new NetworkTransportFailureDescriptor();
  public openedAt: number = 0;
  public expiresAt: number = 0;
  public failureCount: number = 0;
}

/**
 * Coordinates expected transport failures across page URLs and logging layers.
 * Fingerprints contain the failure class, host and error code, never a URL path,
 * query, cookie, request header or response body.
 */
export class NetworkTransportFailureCoordinator {
  private static instance: NetworkTransportFailureCoordinator | null = null;
  private static readonly FINGERPRINT_MARKER: string = '[transport-fingerprint=';
  private static readonly DNS_CIRCUIT_TTL_MS: number = 20 * 1000;
  private static readonly TLS_CIRCUIT_TTL_MS: number = 45 * 1000;
  private static readonly DIAGNOSTIC_ERROR_WINDOW_MS: number = 30 * 1000;
  private static readonly LEDGER_DEDUPE_WINDOW_MS: number = 60 * 1000;
  private static readonly MAX_TRACKED_KEYS: number = 256;

  private hostCircuits: Map<string, NetworkTransportHostCircuitState> =
    new Map<string, NetworkTransportHostCircuitState>();
  private diagnosticErrorTimes: Map<string, number> = new Map<string, number>();
  private ledgerRecordTimes: Map<string, number> = new Map<string, number>();

  private constructor() {}

  public static getInstance(): NetworkTransportFailureCoordinator {
    if (NetworkTransportFailureCoordinator.instance === null) {
      NetworkTransportFailureCoordinator.instance = new NetworkTransportFailureCoordinator();
    }
    return NetworkTransportFailureCoordinator.instance;
  }

  public static createIsolatedForTesting(): NetworkTransportFailureCoordinator {
    return new NetworkTransportFailureCoordinator();
  }

  public describe(url: string, message: string, codeText: string = ''): NetworkTransportFailureDescriptor {
    const embeddedFingerprint: string = this.extractFingerprint(message);
    if (embeddedFingerprint.length > 0) {
      return this.describeFingerprint(embeddedFingerprint);
    }

    const normalizedMessage: string = message.trim().toLowerCase();
    const code: string = this.normalizeCode(codeText, normalizedMessage);
    const kind: NetworkTransportFailureKind = this.classify(normalizedMessage, code);
    const descriptor: NetworkTransportFailureDescriptor = new NetworkTransportFailureDescriptor();
    if (kind === NetworkTransportFailureKind.NONE) {
      return descriptor;
    }

    descriptor.recognized = true;
    descriptor.kind = kind;
    descriptor.host = this.extractHost(url);
    descriptor.code = code;
    descriptor.fingerprint = this.buildFingerprint(kind, descriptor.host, code);
    descriptor.circuitEligible = kind === NetworkTransportFailureKind.DNS ||
      kind === NetworkTransportFailureKind.TLS;
    descriptor.canonicalMessage = this.buildCanonicalMessage(descriptor);
    return descriptor;
  }

  public recordFailure(
    url: string,
    message: string,
    codeText: string = '',
    now: number = Date.now()
  ): NetworkTransportFailureDescriptor {
    const descriptor: NetworkTransportFailureDescriptor = this.describe(url, message, codeText);
    if (!descriptor.recognized || !descriptor.circuitEligible || descriptor.host.length <= 0) {
      return descriptor;
    }

    const existing: NetworkTransportHostCircuitState | undefined = this.hostCircuits.get(descriptor.host);
    const state: NetworkTransportHostCircuitState = existing
      ? existing
      : new NetworkTransportHostCircuitState();
    state.descriptor = descriptor;
    state.openedAt = now;
    state.expiresAt = now + this.resolveCircuitTtl(descriptor.kind);
    state.failureCount = state.failureCount + 1;
    this.hostCircuits.set(descriptor.host, state);
    this.pruneIfNeeded(now);
    return descriptor;
  }

  public shouldSuppress(
    url: string,
    backgroundRequest: boolean,
    userInitiated: boolean = false,
    now: number = Date.now()
  ): NetworkTransportCircuitDecision {
    const decision: NetworkTransportCircuitDecision = new NetworkTransportCircuitDecision();
    if (!backgroundRequest || userInitiated) {
      return decision;
    }

    const host: string = this.extractHost(url);
    if (host.length <= 0) {
      return decision;
    }
    const state: NetworkTransportHostCircuitState | undefined = this.hostCircuits.get(host);
    if (!state) {
      return decision;
    }
    if (state.expiresAt <= now) {
      this.hostCircuits.delete(host);
      return decision;
    }

    decision.suppressed = true;
    decision.remainingMs = Math.max(0, state.expiresAt - now);
    decision.descriptor = state.descriptor;
    return decision;
  }

  public recordSuccess(url: string): void {
    const host: string = this.extractHost(url);
    if (host.length > 0) {
      this.hostCircuits.delete(host);
    }
  }

  public isRecognizedFailureMessage(message: string): boolean {
    return this.extractFingerprint(message).length > 0;
  }

  public extractFingerprint(message: string): string {
    const markerStart: number = message.indexOf(NetworkTransportFailureCoordinator.FINGERPRINT_MARKER);
    if (markerStart >= 0) {
      const valueStart: number = markerStart + NetworkTransportFailureCoordinator.FINGERPRINT_MARKER.length;
      const valueEnd: number = message.indexOf(']', valueStart);
      if (valueEnd > valueStart) {
        const markedCandidate: string = message.substring(valueStart, valueEnd).trim().toLowerCase();
        if (this.isValidFingerprintCandidate(markedCandidate)) {
          return markedCandidate;
        }
      }
    }

    // Some transport/queue diagnostics historically emitted
    // `fingerprint=network_transport|...` without the canonical marker.
    // Normalize that projection too so the error monitor and persistent
    // ledger cannot split one host failure by page or logging layer.
    const bareStart: number = message.indexOf('network_transport|');
    if (bareStart < 0) {
      return '';
    }
    let bareEnd: number = bareStart;
    while (bareEnd < message.length) {
      const character: string = message.charAt(bareEnd);
      if (/\s|[\],;)]/.test(character)) {
        break;
      }
      bareEnd++;
    }
    const bareCandidate: string = message.substring(bareStart, bareEnd).trim().toLowerCase();
    return this.isValidFingerprintCandidate(bareCandidate) ? bareCandidate : '';
  }

  private isValidFingerprintCandidate(candidate: string): boolean {
    if (!candidate.startsWith('network_transport|') || candidate.includes('/') || candidate.includes('?') ||
      candidate.includes('#')) {
      return false;
    }
    const parts: string[] = candidate.split('|');
    if (parts.length !== 4 || parts[0] !== 'network_transport' || parts[2].length <= 0 || parts[3].length <= 0) {
      return false;
    }
    return this.parseKind(parts[1]) !== NetworkTransportFailureKind.NONE;
  }

  public claimDiagnosticError(messageOrFingerprint: string, now: number = Date.now()): boolean {
    const fingerprint: string = this.resolveFingerprintInput(messageOrFingerprint);
    if (fingerprint.length <= 0) {
      return true;
    }
    return this.claimWindow(
      this.diagnosticErrorTimes,
      fingerprint,
      now,
      NetworkTransportFailureCoordinator.DIAGNOSTIC_ERROR_WINDOW_MS
    );
  }

  public claimLedgerRecord(messageOrFingerprint: string, now: number = Date.now()): boolean {
    const fingerprint: string = this.resolveFingerprintInput(messageOrFingerprint);
    if (fingerprint.length <= 0) {
      return true;
    }
    return this.claimWindow(
      this.ledgerRecordTimes,
      fingerprint,
      now,
      NetworkTransportFailureCoordinator.LEDGER_DEDUPE_WINDOW_MS
    );
  }

  public resetForTesting(): void {
    this.hostCircuits.clear();
    this.diagnosticErrorTimes.clear();
    this.ledgerRecordTimes.clear();
  }

  private describeFingerprint(fingerprint: string): NetworkTransportFailureDescriptor {
    const descriptor: NetworkTransportFailureDescriptor = new NetworkTransportFailureDescriptor();
    const parts: string[] = fingerprint.split('|');
    if (parts.length !== 4 || parts[0] !== 'network_transport') {
      return descriptor;
    }
    const kind: NetworkTransportFailureKind = this.parseKind(parts[1]);
    if (kind === NetworkTransportFailureKind.NONE) {
      return descriptor;
    }
    descriptor.recognized = true;
    descriptor.kind = kind;
    descriptor.host = parts[2] === 'unknown_host' ? '' : parts[2];
    descriptor.code = parts[3] === 'no_code' ? '' : parts[3];
    descriptor.fingerprint = fingerprint;
    descriptor.circuitEligible = kind === NetworkTransportFailureKind.DNS ||
      kind === NetworkTransportFailureKind.TLS;
    descriptor.canonicalMessage = this.buildCanonicalMessage(descriptor);
    return descriptor;
  }

  private classify(message: string, code: string): NetworkTransportFailureKind {
    if (code === '2300006' || message.includes('resolve the host') ||
      message.includes('could not resolve host') || message.includes('unable to resolve') ||
      message.includes('name resolution') || message.includes('name or service not known') ||
      message.includes('enotfound') || message.includes('curlcode result 6') ||
      message.includes('dns') || message.includes('域名解析') || message.includes('无法解析主机')) {
      return NetworkTransportFailureKind.DNS;
    }
    if (code === '2300060' || message.includes('certificate') || message.includes('ssl') ||
      message.includes('tls') || message.includes('handshake') || message.includes('证书') ||
      message.includes('安全连接') || message.includes('握手失败')) {
      return NetworkTransportFailureKind.TLS;
    }
    if (code === '2300028' || message.includes('timeout') || message.includes('timed out') ||
      message.includes('etimedout') || message.includes('超时')) {
      return NetworkTransportFailureKind.TIMEOUT;
    }
    if (/http[^0-9]*[45][0-9]{2}/i.test(message) ||
      /status[^0-9]*[45][0-9]{2}/i.test(message)) {
      return NetworkTransportFailureKind.HTTP;
    }
    if (code.startsWith('2300') || message.includes('network error') ||
      message.includes('connection refused') || message.includes('connection reset') ||
      message.includes('econnrefused') || message.includes('econnreset') ||
      message.includes('host unreachable') || message.includes('网络错误') ||
      message.includes('网络连接失败') || message.includes('连接被拒绝') ||
      message.includes('连接已重置') || message.includes('主机不可达')) {
      return NetworkTransportFailureKind.NETWORK;
    }
    return NetworkTransportFailureKind.NONE;
  }

  private normalizeCode(codeText: string, message: string): string {
    const explicitMatch: RegExpMatchArray | null = codeText.match(/\b(230[0-9]{4}|[45][0-9]{2})\b/);
    if (explicitMatch && explicitMatch.length > 1) {
      return explicitMatch[1];
    }
    const messageMatch: RegExpMatchArray | null = message.match(/\b(230[0-9]{4})\b/);
    if (messageMatch && messageMatch.length > 1) {
      return messageMatch[1];
    }
    const httpMatch: RegExpMatchArray | null = message.match(/(?:http|status)[^0-9]*([45][0-9]{2})/i);
    return httpMatch && httpMatch.length > 1 ? httpMatch[1] : '';
  }

  private extractHost(url: string): string {
    const match: RegExpMatchArray | null = url.trim().match(/^[a-z][a-z0-9+.-]*:\/\/([^\/?#]+)/i);
    if (!match || match.length <= 1) {
      return '';
    }
    let authority: string = match[1].trim().toLowerCase();
    const userInfoEnd: number = authority.lastIndexOf('@');
    if (userInfoEnd >= 0) {
      authority = authority.substring(userInfoEnd + 1);
    }
    if (authority.startsWith('[')) {
      const bracketEnd: number = authority.indexOf(']');
      return bracketEnd > 1 ? this.normalizeHost(authority.substring(1, bracketEnd)) : '';
    }
    const portSeparator: number = authority.indexOf(':');
    const host: string = portSeparator >= 0 ? authority.substring(0, portSeparator) : authority;
    const withoutTrailingDot: string = host.endsWith('.') ? host.substring(0, host.length - 1) : host;
    return this.normalizeHost(withoutTrailingDot);
  }

  private normalizeHost(host: string): string {
    return host.replace(/[^a-z0-9.:-]/g, '_');
  }

  private buildFingerprint(kind: NetworkTransportFailureKind, host: string, code: string): string {
    const hostPart: string = host.length > 0 ? host : 'unknown_host';
    const codePart: string = code.length > 0 ? code : 'no_code';
    return `network_transport|${kind}|${hostPart}|${codePart}`;
  }

  private buildCanonicalMessage(descriptor: NetworkTransportFailureDescriptor): string {
    let summary: string = 'Network transport failed';
    if (descriptor.kind === NetworkTransportFailureKind.DNS) {
      summary = 'DNS resolution failed';
    } else if (descriptor.kind === NetworkTransportFailureKind.TLS) {
      summary = 'TLS connection failed';
    } else if (descriptor.kind === NetworkTransportFailureKind.TIMEOUT) {
      summary = 'Network request timed out';
    } else if (descriptor.kind === NetworkTransportFailureKind.HTTP) {
      summary = 'HTTP request failed';
    }
    const hostText: string = descriptor.host.length > 0 ? descriptor.host : 'unknown_host';
    const codeText: string = descriptor.code.length > 0 ? `, code=${descriptor.code}` : '';
    return `${summary} (host=${hostText}${codeText}) ` +
      `${NetworkTransportFailureCoordinator.FINGERPRINT_MARKER}${descriptor.fingerprint}]`;
  }

  private parseKind(value: string): NetworkTransportFailureKind {
    if (value === NetworkTransportFailureKind.DNS) {
      return NetworkTransportFailureKind.DNS;
    }
    if (value === NetworkTransportFailureKind.TLS) {
      return NetworkTransportFailureKind.TLS;
    }
    if (value === NetworkTransportFailureKind.TIMEOUT) {
      return NetworkTransportFailureKind.TIMEOUT;
    }
    if (value === NetworkTransportFailureKind.HTTP) {
      return NetworkTransportFailureKind.HTTP;
    }
    if (value === NetworkTransportFailureKind.NETWORK) {
      return NetworkTransportFailureKind.NETWORK;
    }
    return NetworkTransportFailureKind.NONE;
  }

  private resolveCircuitTtl(kind: NetworkTransportFailureKind): number {
    return kind === NetworkTransportFailureKind.TLS
      ? NetworkTransportFailureCoordinator.TLS_CIRCUIT_TTL_MS
      : NetworkTransportFailureCoordinator.DNS_CIRCUIT_TTL_MS;
  }

  private resolveFingerprintInput(value: string): string {
    if (value.startsWith('network_transport|')) {
      return value;
    }
    return this.extractFingerprint(value);
  }

  private claimWindow(
    entries: Map<string, number>,
    fingerprint: string,
    now: number,
    windowMs: number
  ): boolean {
    const previous: number | undefined = entries.get(fingerprint);
    if (previous !== undefined && now - previous < windowMs) {
      return false;
    }
    entries.set(fingerprint, now);
    this.pruneMap(entries, now, windowMs);
    return true;
  }

  private pruneIfNeeded(now: number): void {
    if (this.hostCircuits.size <= NetworkTransportFailureCoordinator.MAX_TRACKED_KEYS) {
      return;
    }
    const expiredHosts: string[] = [];
    this.hostCircuits.forEach((state: NetworkTransportHostCircuitState, host: string): void => {
      if (state.expiresAt <= now) {
        expiredHosts.push(host);
      }
    });
    for (let index: number = 0; index < expiredHosts.length; index++) {
      this.hostCircuits.delete(expiredHosts[index]);
    }
    if (this.hostCircuits.size > NetworkTransportFailureCoordinator.MAX_TRACKED_KEYS) {
      this.hostCircuits.clear();
    }
  }

  private pruneMap(entries: Map<string, number>, now: number, windowMs: number): void {
    if (entries.size <= NetworkTransportFailureCoordinator.MAX_TRACKED_KEYS) {
      return;
    }
    const expiredKeys: string[] = [];
    entries.forEach((timestamp: number, key: string): void => {
      if (now - timestamp >= windowMs) {
        expiredKeys.push(key);
      }
    });
    for (let index: number = 0; index < expiredKeys.length; index++) {
      entries.delete(expiredKeys[index]);
    }
    if (entries.size > NetworkTransportFailureCoordinator.MAX_TRACKED_KEYS) {
      entries.clear();
    }
  }
}

export function getNetworkTransportFailureCoordinator(): NetworkTransportFailureCoordinator {
  return NetworkTransportFailureCoordinator.getInstance();
}
