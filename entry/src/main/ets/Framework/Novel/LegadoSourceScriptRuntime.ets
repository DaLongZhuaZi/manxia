import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { sha256Hash } from 'manxia_core/src/main/ets/Utils/CryptoUtils';
import {
  getLegadoJsEngine,
  JsContext,
  JsExecuteResult,
  LegadoJsSourceEffects
} from './LegadoJsEngine';
import { getNovelLoginManager } from './NovelLoginManager';
import { LegadoSourceParser } from './LegadoSourceParser';
import { LegadoBookSource } from './LegadoSourceTypes';
import { LegadoBridgeTrace, LegadoExecutionErrorCode } from './LegadoCompatibilityTypes';
import {
  LegadoExecutionCancellationToken,
  createLegadoExecutionCancelledError
} from './LegadoExecutionCancellation';

const TAG = 'LegadoSourceScriptRuntime';
const WEBVIEW_NOT_READY = 'WEBVIEW_NOT_READY';
const RETRY_DELAYS_MS: number[] = [120, 260, 500, 900];

export class LegadoSourceScriptVariableChange {
  readonly key: string;
  readonly value: string;

  constructor(key: string, value: string) {
    this.key = key;
    this.value = value;
  }
}

export class LegadoSourceScriptResult {
  readonly success: boolean;
  readonly result: string;
  readonly errorCode: LegadoExecutionErrorCode;
  readonly errorMessage: string;
  readonly variableChanges: LegadoSourceScriptVariableChange[];
  readonly sourceEffectNames: string[];
  readonly bridgeTraces: LegadoBridgeTrace[];

  constructor(
    success: boolean,
    result: string,
    errorCode: LegadoExecutionErrorCode,
    errorMessage: string,
    variableChanges: LegadoSourceScriptVariableChange[],
    sourceEffectNames: string[],
    bridgeTraces: LegadoBridgeTrace[] = []
  ) {
    this.success = success;
    this.result = result;
    this.errorCode = errorCode;
    this.errorMessage = errorMessage;
    this.variableChanges = variableChanges.slice();
    this.sourceEffectNames = sourceEffectNames.slice();
    this.bridgeTraces = bridgeTraces.slice();
  }
}

/**
 * Nominal runtime contract used by the V2 workflow and conformance fixtures.
 * Production execution never delegates to NovelSourceExecutor.
 */
export abstract class LegadoSourceScriptRuntimeBase {
  abstract execute(
    source: LegadoBookSource,
    code: string,
    workflowVariables: Map<string, string>,
    cancellationToken?: LegadoExecutionCancellationToken
  ): Promise<LegadoSourceScriptResult>;
}

/**
 * Source-scoped JavaScript runtime for rules that are evaluated before an HTTP
 * request exists, such as dynamic explore categories.
 */
export class LegadoSourceScriptRuntime extends LegadoSourceScriptRuntimeBase {
  async execute(
    source: LegadoBookSource,
    code: string,
    workflowVariables: Map<string, string>,
    cancellationToken?: LegadoExecutionCancellationToken
  ): Promise<LegadoSourceScriptResult> {
    cancellationToken?.throwIfCancelled();
    const trimmedCode = code.trim();
    if (trimmedCode.length <= 0) {
      return new LegadoSourceScriptResult(
        true,
        '',
        LegadoExecutionErrorCode.NONE,
        '',
        [],
        []
      );
    }

    const context = this.buildContext(source, workflowVariables);
    for (let attempt = 0; attempt <= RETRY_DELAYS_MS.length; attempt++) {
      cancellationToken?.throwIfCancelled();
      try {
        const execution = await getLegadoJsEngine().execute(trimmedCode, context);
        cancellationToken?.throwIfCancelled();
        const variableChanges = this.collectVariableChanges(execution);
        const sourceEffectNames = this.persistSourceEffects(source, execution.sourceEffects);
        if (execution.success) {
          return new LegadoSourceScriptResult(
            true,
            execution.result.trim(),
            LegadoExecutionErrorCode.NONE,
            '',
            variableChanges,
            sourceEffectNames,
            execution.bridgeTraces || []
          );
        }

        const runtimeError = (execution.error || '').trim();
        if (runtimeError === WEBVIEW_NOT_READY && attempt < RETRY_DELAYS_MS.length) {
          await this.sleep(RETRY_DELAYS_MS[attempt], cancellationToken);
          continue;
        }
        const diagnostic = await this.buildStableRuntimeDiagnostic(
          trimmedCode,
          runtimeError,
          execution.diagnostic || ''
        );
        logger.warn(TAG, `动态书源脚本执行失败: ${this.toStableFailure(runtimeError)}`);
        return new LegadoSourceScriptResult(
          false,
          '',
          this.classifyError(runtimeError, execution.bridgeTraces || []),
          diagnostic,
          variableChanges,
          sourceEffectNames,
          execution.bridgeTraces || []
        );
      } catch (error) {
        cancellationToken?.throwIfCancelled();
        if (attempt < RETRY_DELAYS_MS.length) {
          await this.sleep(RETRY_DELAYS_MS[attempt], cancellationToken);
          continue;
        }
        logger.warn(TAG, `动态书源脚本执行异常: ${String(error)}`);
        const diagnostic = await this.buildStableRuntimeDiagnostic(
          trimmedCode,
          String(error),
          ''
        );
        return new LegadoSourceScriptResult(
          false,
          '',
          LegadoExecutionErrorCode.UNKNOWN,
          diagnostic,
          [],
          []
        );
      }
    }

    return new LegadoSourceScriptResult(
      false,
      '',
      LegadoExecutionErrorCode.WEB_VIEW,
      WEBVIEW_NOT_READY,
      [],
      []
    );
  }

  private buildContext(source: LegadoBookSource, workflowVariables: Map<string, string>): JsContext {
    const loginManager = getNovelLoginManager();
    const sourceId = source.bookSourceUrl || '';
    const sourceData = loginManager.getSourceDataSnapshot(sourceId);
    const variables: Record<string, string> = {};
    variables.sourceUrl = sourceId;
    variables.__source_bookSourceName = source.bookSourceName || '';
    variables.__source_bookSourceGroup = source.bookSourceGroup || '';
    variables.__source_bookSourceComment = source.bookSourceComment || '';
    variables.__source_header = source.header || '';
    variables.__source_loginUrl = source.loginUrl || '';
    variables.__source_loginUi = source.loginUi || '';
    variables.__source_loginCheckJs = source.loginCheckJs || '';
    variables.__source_variableComment = source.variableComment || '';
    variables.__loginInfo = loginManager.getLoginInfo(sourceId);
    variables.__loginHeader = loginManager.getLoginHeader(sourceId);
    variables.__sourceVariable = loginManager.getSourceVariable(sourceId);
    variables.__sourceData = JSON.stringify(sourceData);
    variables.cookie = loginManager.getCookieString(sourceId);
    workflowVariables.forEach((value: string, key: string): void => {
      variables[key] = value;
    });

    const context: JsContext = {
      result: '',
      src: '',
      baseUrl: LegadoSourceParser.getBaseUrl(source),
      key: '',
      page: 1,
      variables,
      jsLib: source.jsLib || '',
      source
    };
    return context;
  }

  private collectVariableChanges(execution: JsExecuteResult): LegadoSourceScriptVariableChange[] {
    if (!execution.variables) {
      return [];
    }
    const keys = Object.keys(execution.variables);
    const changes: LegadoSourceScriptVariableChange[] = [];
    for (let i = 0; i < keys.length; i++) {
      changes.push(new LegadoSourceScriptVariableChange(keys[i], execution.variables[keys[i]]));
    }
    return changes;
  }

  private persistSourceEffects(source: LegadoBookSource, effects?: LegadoJsSourceEffects): string[] {
    if (!effects) {
      return [];
    }
    const sourceId = source.bookSourceUrl || '';
    if (sourceId.length <= 0) {
      return [];
    }

    const loginManager = getNovelLoginManager();
    const effectNames: string[] = [];
    if (effects.loginInfo !== undefined) {
      loginManager.putLoginInfo(sourceId, effects.loginInfo);
      effectNames.push('source.loginInfo');
    }
    if (effects.removeLoginHeader === true) {
      loginManager.removeLoginHeader(sourceId);
      effectNames.push('source.loginHeader.remove');
    }
    if (effects.loginHeader !== undefined) {
      loginManager.putLoginHeader(sourceId, effects.loginHeader);
      effectNames.push('source.loginHeader');
    }
    if (effects.sourceVariable !== undefined) {
      loginManager.setSourceVariable(sourceId, effects.sourceVariable);
      effectNames.push('source.variable');
    }
    if (effects.data) {
      for (let i = 0; i < effects.data.length; i++) {
        const item = effects.data[i];
        if (item.key.length <= 0) {
          continue;
        }
        loginManager.putSourceData(sourceId, item.key, item.value);
        effectNames.push(`source.data.${item.key}`);
      }
    }
    return effectNames;
  }

  private classifyError(error: string, bridgeTraces: LegadoBridgeTrace[] = []): LegadoExecutionErrorCode {
    if (this.hasTransportFailure(bridgeTraces)) {
      return LegadoExecutionErrorCode.NETWORK;
    }
    if (error === WEBVIEW_NOT_READY) {
      return LegadoExecutionErrorCode.WEB_VIEW;
    }
    const normalized = error.toLowerCase();
    if (normalized.includes('network') || normalized.includes('http')) {
      return LegadoExecutionErrorCode.NETWORK;
    }
    if (normalized.includes('syntax') || normalized.includes('runtime')) {
      return LegadoExecutionErrorCode.RULE;
    }
    return LegadoExecutionErrorCode.UNKNOWN;
  }

  private toStableFailure(error: string, bridgeTraces: LegadoBridgeTrace[] = []): string {
    if (this.hasTransportFailure(bridgeTraces)) {
      return 'SCRIPT_NETWORK';
    }
    if (error === WEBVIEW_NOT_READY) {
      return WEBVIEW_NOT_READY;
    }
    const normalized = error.toLowerCase();
    if (normalized.includes('syntax')) {
      return 'SCRIPT_SYNTAX';
    }
    if (normalized.includes('network') || normalized.includes('http')) {
      return 'SCRIPT_NETWORK';
    }
    if (normalized.includes('runtime')) {
      return 'SCRIPT_RUNTIME';
    }
    return 'JS_EXECUTION_FAILED';
  }

  /**
   * Converts a raw runtime failure into a deterministic, evidence-safe
   * diagnostic.  The raw exception is used only as hash input and is never
   * returned or persisted; this prevents URLs, cookies, response bodies and
   * source code from leaking into device traces.
   */
  private async buildStableRuntimeDiagnostic(
    code: string,
    error: string,
    runtimeDiagnostic: string
  ): Promise<string> {
    const digestInput = `${runtimeDiagnostic}|${error}|${code.length}`;
    let digest = 'hash_unavailable';
    try {
      digest = (await sha256Hash(digestInput)).substring(0, 16);
    } catch (_hashError) {
      digest = 'hash_unavailable';
    }
    const errorClass = this.readDiagnosticField(runtimeDiagnostic, 'errorClass', 'RUNTIME_ERROR');
    const errorType = this.sanitizeDiagnosticToken(
      this.readDiagnosticField(runtimeDiagnostic, 'errorType', 'RuntimeError')
    );
    const operation = this.sanitizeDiagnosticToken(
      this.readDiagnosticField(runtimeDiagnostic, 'operation', 'execute')
    );
    const sourceComment = this.normalizeCapabilityState(
      this.readDiagnosticField(runtimeDiagnostic, 'sourceComment', 'unknown')
    );
    const domParser = this.normalizeCapabilityState(
      this.readDiagnosticField(runtimeDiagnostic, 'domParser', 'unknown')
    );
    const line = this.normalizeDiagnosticNumber(
      this.readDiagnosticField(runtimeDiagnostic, 'line', 'unknown')
    );
    const column = this.normalizeDiagnosticNumber(
      this.readDiagnosticField(runtimeDiagnostic, 'column', 'unknown')
    );
    return `runtime_diagnostic;operation=${operation};errorType=${errorType};` +
      `errorClass=${this.sanitizeDiagnosticToken(errorClass)};errorDigest=${digest};` +
      `codeLength=${code.length};sourceComment=${sourceComment};domParser=${domParser};` +
      `line=${line};column=${column}`;
  }

  private readDiagnosticField(value: string, key: string, fallback: string): string {
    const marker = `${key}=`;
    const start = value.indexOf(marker);
    if (start < 0) {
      return fallback;
    }
    const valueStart = start + marker.length;
    const end = value.indexOf(';', valueStart);
    const candidate = (end < 0 ? value.substring(valueStart) : value.substring(valueStart, end)).trim();
    return candidate.length > 0 ? candidate : fallback;
  }

  private normalizeCapabilityState(value: string): string {
    if (value === 'present' || value === 'fallback' || value === 'absent' || value === 'unknown') {
      return value;
    }
    return 'unknown';
  }

  private sanitizeDiagnosticToken(value: string): string {
    const normalized = value.replace(/[^A-Za-z0-9_.-]/g, '_');
    return normalized.length > 0 ? normalized.substring(0, 48) : 'unknown';
  }

  private normalizeDiagnosticNumber(value: string): string {
    if (/^\d+$/.test(value)) {
      return value.substring(0, 8);
    }
    return 'unknown';
  }

  private hasTransportFailure(bridgeTraces: LegadoBridgeTrace[]): boolean {
    for (let i = 0; i < bridgeTraces.length; i++) {
      if (bridgeTraces[i].isTransportFailure()) {
        return true;
      }
    }
    return false;
  }

  private async sleep(
    milliseconds: number,
    cancellationToken?: LegadoExecutionCancellationToken
  ): Promise<void> {
    cancellationToken?.throwIfCancelled();
    await new Promise<void>((resolve: () => void, reject: (error: Error) => void): void => {
      let settled = false;
      let listenerId = 0;
      let timerId = -1;
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
      }, milliseconds) as number;
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
}
