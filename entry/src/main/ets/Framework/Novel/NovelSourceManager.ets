import { SafeFileUtils } from 'manxia_core/src/main/ets/Utils/SafeFileUtils';
/**
 * 小说源管理器
 * 统一管理小说书源的导入、存储、执行
 * 
 * 文件路径: entry/src/main/ets/Framework/Novel/NovelSourceManager.ets
 */

import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { LegadoBookSource, LegadoSearchBook, LegadoBook, LegadoChapter, LegadoSourceImportResult, LegadoExploreKind, LegadoBookSourceType, LegadoRequestCarrier } from 'manxia_novel/src/main/ets/Framework/Novel/LegadoSourceTypes';
import { NovelSourceExecutor, SearchParseOptions } from './NovelSourceExecutor';
import { LegadoCompatibilityCompiler } from 'manxia_novel/src/main/ets/Framework/Novel/LegadoCompatibilityCompiler';
import { LegadoV2SourceExecutor } from './LegadoWorkflowOrchestrator';
import { getLegadoExecutionTraceStore, LegadoTraceSerializer } from 'manxia_novel/src/main/ets/Framework/Novel/LegadoTraceSerializer';
import {
  CompiledBookSource,
  LEGADO_COMPATIBILITY_SCHEMA_VERSION,
  LegadoCompatibilitySummary,
  LegadoCompatibilityEngineMode,
  LegadoCompatibilityStatus,
  LegadoCompatibilityStorageRecord,
  LegadoContentTraceDiagnostics,
  LegadoExecutionErrorCode,
  LegadoExecutionTrace,
  LegadoFileDownloadCandidate,
  LegadoExecutionTraceSummary,
  LegadoNetworkTraceEvidence,
  LegadoSearchExecutionOptions,
  LegadoSourceVerificationRecord,
  LegadoV2ExecutionPolicy,
  LegadoWorkflowBookInfoResult,
  LegadoWorkflowContentResult,
  LegadoWorkflowHandoffStatus,
  LegadoWorkflowKind,
  LegadoWorkflowOutputKind,
  LegadoWorkflowTocResult
} from 'manxia_novel/src/main/ets/Framework/Novel/LegadoCompatibilityTypes';
import { NovelSourceInfo, NovelSearchResult } from '../../Models/NovelModels';
import { getNovelDataManager } from './NovelDataManager';
import { getLegadoMangaSourceBridge } from './LegadoMangaSourceBridge';
import { LargeFileJSONParser, ParseProgressCallback, ParseConfig } from 'manxia_novel/src/main/ets/Framework/Novel/LargeFileJSONParser';
import { fileIo as fs } from '@kit.CoreFileKit';
import { SettingsManager } from '../Managers/SettingsManager';
import { LegadoExecutionCancellationToken, createLegadoCancellationToken } from 'manxia_novel/src/main/ets/Framework/Novel/LegadoExecutionCancellation';

const TAG = 'NovelSourceManager';
const V2_INTERACTIVE_WORKFLOW_TIMEOUT_MS: number = 60000;

type V2WorkflowTask<T> = (cancellationToken: LegadoExecutionCancellationToken) => Promise<T>;

/**
 * 大文件导入进度回调接口
 */
export interface LargeFileImportProgress {
  /**
   * 文件读取阶段
   * @param percent 读取百分比 0-100
   * @param bytesRead 已读取字节数
   * @param totalBytes 总字节数
   */
  onFileReadProgress?: (percent: number, bytesRead: number, totalBytes: number) => void;
  
  /**
   * 解析阶段
   * @param parsedCount 已解析书源数
   * @param currentSourceName 当前解析的书源名称
   */
  onParseProgress?: (parsedCount: number, currentSourceName: string) => void;
  
  /**
   * 导入阶段（保存到数据库）
   * @param importedCount 已导入数量
   * @param totalCount 总数量；流式扫描尚未结束时为 0，调用方不得伪造百分比
   * @param currentSourceName 当前导入的书源名称
   */
  onImportProgress?: (importedCount: number, totalCount: number, currentSourceName: string) => void;
  
  /**
   * 阶段变化
   * @param stage 当前阶段: 'reading' | 'parsing' | 'importing' | 'complete'
   */
  onStageChange?: (stage: string) => void;
  
  /**
   * 错误（可恢复）
   * @param error 错误信息
   * @param sourceName 相关书源名称（如果有）
   */
  onError?: (error: string, sourceName?: string) => void;
}

/**
 * 大文件导入结果
 */
export interface LargeFileImportResult {
  success: boolean;
  totalParsed: number;
  successCount: number;
  failedCount: number;
  skippedCount: number;
  errors: string[];
  elapsedMs: number;
}

export interface NovelSourceImportOptions {
  preserveLocalState?: boolean;
  defaultNSFW?: boolean;
}

/**
 * 小说源管理器类
 */
export class NovelSourceManager {
  private static instance: NovelSourceManager | null = null;
  private sources: Map<string, LegadoBookSource> = new Map();
  private executors: Map<string, NovelSourceExecutor> = new Map();
  private compiledSources: Map<string, CompiledBookSource> = new Map();
  private v2Executors: Map<string, LegadoV2SourceExecutor> = new Map();
  private v2BookVariableSnapshots: Map<string, string> = new Map();
  private v2BookRequestCarriers: Map<string, LegadoRequestCarrier> = new Map();
  private v2BookRequestCarrierIdentityIndex: Map<string, string> = new Map();
  private lastV2BookInfoResults: Map<string, LegadoWorkflowBookInfoResult> = new Map();
  private lastV2ContentResults: Map<string, LegadoWorkflowContentResult> = new Map();
  private v2RequestCarrierSequence: number = 0;
  private compatibilityModes: Map<string, LegadoCompatibilityEngineMode> = new Map();
  private compatibilityStatuses: Map<string, LegadoCompatibilityStatus> = new Map();
  private verificationRecords: Map<string, LegadoSourceVerificationRecord> = new Map();
  private lastExecutionTraces: Map<string, LegadoExecutionTrace> = new Map();
  private lastExecutionTraceSummaries: Map<string, LegadoExecutionTraceSummary> = new Map();
  private executionTraceWorkflowSummaries: Map<string, Map<LegadoWorkflowKind, LegadoExecutionTraceSummary>> = new Map();
  private executionTracePersistence: Map<string, boolean> = new Map<string, boolean>();
  // Multiple UI abilities may rehydrate evidence at once after a reader closes.
  // A persistence read started earlier must never restore an older snapshot
  // after a later refresh has already won the in-memory projection.
  private executionTraceRefreshGeneration: number = 0;

  private constructor() {}

  /**
   * V2 变量属于一次书籍执行上下文，而不是全局书源状态。它们只保存在
   * 内存中，并以 sourceId 与 bookUrl 共同隔离，避免并发阅读串扰。
   */
  private getV2BookExecutionCarrierKey(sourceId: string, bookUrl: string): string {
    return `${sourceId}|${bookUrl}`;
  }

  private rememberV2BookVariableSnapshot(sourceId: string, bookUrl: string, variable?: string): void {
    if (variable === undefined || variable.trim().length === 0 || bookUrl.length === 0) {
      return;
    }
    this.v2BookVariableSnapshots.set(this.getV2BookExecutionCarrierKey(sourceId, bookUrl), variable);
  }

  private registerV2RequestCarrier(
    sourceId: string,
    bookUrl: string,
    carrier?: LegadoRequestCarrier,
    requestUrlTemplate?: string,
    originWorkflow: string = 'manager'
  ): string | undefined {
    if (bookUrl.trim().length === 0) {
      return undefined;
    }
    const effectiveCarrier = carrier !== undefined
      ? carrier
      : (requestUrlTemplate !== undefined && requestUrlTemplate.trim().length > 0
        ? new LegadoRequestCarrier(sourceId, bookUrl, requestUrlTemplate, originWorkflow)
        : undefined);
    if (effectiveCarrier === undefined || effectiveCarrier.requestUrlTemplate.trim().length === 0) {
      return undefined;
    }
    if (effectiveCarrier.sourceUrl !== sourceId || effectiveCarrier.identityUrl !== bookUrl) {
      throw new Error('REQUEST_CARRIER_UNAVAILABLE:identity_mismatch');
    }
    this.v2RequestCarrierSequence++;
    const token = `v2rc:${this.v2RequestCarrierSequence}:${Date.now()}`;
    this.v2BookRequestCarriers.set(token, effectiveCarrier);
    const identityKey = this.getV2BookExecutionCarrierKey(sourceId, bookUrl);
    const currentToken = this.v2BookRequestCarrierIdentityIndex.get(identityKey);
    if (currentToken === undefined) {
      this.v2BookRequestCarrierIdentityIndex.set(identityKey, token);
    } else if (currentToken.length > 0) {
      const currentCarrier = this.v2BookRequestCarriers.get(currentToken);
      if (currentCarrier !== undefined && currentCarrier.requestUrlTemplate === effectiveCarrier.requestUrlTemplate) {
        this.v2BookRequestCarriers.delete(token);
        return currentToken;
      }
      // Multiple option expressions can share an identity URL. Do not guess
      // which one a reconstructed page intended to use.
      this.v2BookRequestCarrierIdentityIndex.set(identityKey, '');
    }
    return token;
  }

  private rememberV2BookRequestCarrier(
    sourceId: string,
    bookUrl: string,
    carrier?: LegadoRequestCarrier,
    requestUrlTemplate?: string,
    originWorkflow: string = 'manager'
  ): string | undefined {
    return this.registerV2RequestCarrier(sourceId, bookUrl, carrier, requestUrlTemplate, originWorkflow);
  }

  private resolveV2RequestCarrier(
    sourceId: string,
    bookUrl: string,
    requestCarrierKey?: string
  ): LegadoRequestCarrier | undefined {
    if (requestCarrierKey !== undefined && requestCarrierKey.length > 0) {
      const carrier = this.v2BookRequestCarriers.get(requestCarrierKey);
      if (carrier === undefined) {
        throw new Error('REQUEST_CARRIER_UNAVAILABLE:token_missing');
      }
      if (carrier.sourceUrl !== sourceId || carrier.identityUrl !== bookUrl) {
        throw new Error('REQUEST_CARRIER_UNAVAILABLE:identity_mismatch');
      }
      if (carrier.requestUrlTemplate.trim().length === 0) {
        throw new Error('REQUEST_CARRIER_UNAVAILABLE:template_missing');
      }
      return carrier;
    }
    const identityKey = this.getV2BookExecutionCarrierKey(sourceId, bookUrl);
    const indexedToken = this.v2BookRequestCarrierIdentityIndex.get(identityKey);
    if (indexedToken === undefined) {
      return undefined;
    }
    if (indexedToken.length === 0) {
      throw new Error('REQUEST_CARRIER_UNAVAILABLE:ambiguous_identity');
    }
    const carrier = this.v2BookRequestCarriers.get(indexedToken);
    if (carrier === undefined) {
      throw new Error('REQUEST_CARRIER_UNAVAILABLE:token_missing');
    }
    return carrier;
  }

  /**
   * Original Legado keeps the book rule-data scope and then applies a chapter
   * item scope on top of it. Preserve that ordering at the only cross-page
   * V2 boundary: chapter-local keys intentionally override book-local keys.
   */
  private mergeV2VariableSnapshots(bookVariable?: string, chapterVariable?: string): string | undefined {
    const mergedVariables: Map<string, string> = new Map<string, string>();
    this.appendV2VariableSnapshot(mergedVariables, bookVariable);
    this.appendV2VariableSnapshot(mergedVariables, chapterVariable);
    if (mergedVariables.size === 0) {
      return undefined;
    }
    const keys: string[] = [];
    mergedVariables.forEach((_value: string, key: string): void => {
      keys.push(key);
    });
    keys.sort((left: string, right: string): number => left.localeCompare(right));
    const entries: string[] = [];
    for (let index = 0; index < keys.length; index++) {
      const key = keys[index];
      const value = mergedVariables.get(key);
      if (value !== undefined) {
        entries.push(`${JSON.stringify(key)}:${JSON.stringify(value)}`);
      }
    }
    return `{${entries.join(',')}}`;
  }

  private appendV2VariableSnapshot(target: Map<string, string>, snapshot?: string): void {
    if (snapshot === undefined || snapshot.trim().length === 0) {
      return;
    }
    try {
      const parsed = JSON.parse(snapshot) as Record<string, string>;
      const keys = Object.keys(parsed);
      for (let index = 0; index < keys.length; index++) {
        const key = keys[index];
        const value = parsed[key];
        if (key.trim().length > 0 && value !== undefined && value !== null) {
          target.set(key, String(value));
        }
      }
    } catch (_error) {
      logger.warn(TAG, 'V2 书籍执行变量快照无效，已忽略该 carrier');
    }
  }

  private createV2ContentChapter(sourceId: string, chapter: LegadoChapter): LegadoChapter {
    const carrierKey = this.getV2BookExecutionCarrierKey(sourceId, chapter.bookUrl);
    const bookVariable = this.v2BookVariableSnapshots.get(carrierKey);
    const mergedVariable = this.mergeV2VariableSnapshots(bookVariable, chapter.variable);
    logger.warn(
      TAG,
      `V2_CONTENT_CARRIER source=${sourceId};bookVariable=${bookVariable !== undefined};` +
      `chapterVariable=${chapter.variable !== undefined};mergedVariable=${mergedVariable !== undefined}`
    );
    return {
      id: chapter.id,
      bookUrl: chapter.bookUrl,
      url: chapter.url,
      requestUrlTemplate: chapter.requestUrlTemplate,
      requestCarrier: chapter.requestCarrier,
      title: chapter.title,
      index: chapter.index,
      isVolume: chapter.isVolume,
      isVip: chapter.isVip,
      isPay: chapter.isPay,
      updateTime: chapter.updateTime,
      variable: mergedVariable,
      tag: chapter.tag
    };
  }

  /**
   * User-path V2 work must not leave a detail page loading forever. A private
   * child token isolates the deadline from an optional caller token while
   * still propagating caller cancellation to the transport and rule layers.
   */
  private async awaitV2InteractiveWorkflow<T>(
    workflow: LegadoWorkflowKind,
    callerToken: LegadoExecutionCancellationToken | undefined,
    taskFactory: V2WorkflowTask<T>
  ): Promise<T> {
    const workflowToken = createLegadoCancellationToken();
    let callerListenerId: number = 0;
    let timerId: number = -1;
    let settled: boolean = false;
    const timeoutReason = `V2_WORKFLOW_TIMEOUT:${workflow}`;

    const release = (): void => {
      if (timerId !== -1) {
        clearTimeout(timerId);
        timerId = -1;
      }
      if (callerToken !== undefined && callerListenerId > 0) {
        callerToken.unregister(callerListenerId);
        callerListenerId = 0;
      }
    };

    try {
      return await new Promise<T>((resolve: (result: T) => void, reject: (error: Error) => void): void => {
        const finishSuccess = (result: T): void => {
          if (settled) {
            return;
          }
          settled = true;
          release();
          resolve(result);
        };
        const finishError = (error: Error): void => {
          if (settled) {
            return;
          }
          settled = true;
          release();
          reject(error);
        };
        if (callerToken !== undefined) {
          callerListenerId = callerToken.register((reason: string): void => {
            workflowToken.cancel(reason);
            finishError(new Error(`LEGADO_EXECUTION_CANCELLED:${reason}`));
          });
          if (settled) {
            return;
          }
        }
        timerId = setTimeout((): void => {
          workflowToken.cancel(timeoutReason);
          finishError(new Error(timeoutReason));
        }, V2_INTERACTIVE_WORKFLOW_TIMEOUT_MS) as number;
        try {
          const task = taskFactory(workflowToken);
          task.then((result: T): void => {
            finishSuccess(result);
          }).catch((error: Error): void => {
            finishError(error);
          });
        } catch (error) {
          finishError(new Error(String(error)));
        }
      });
    } finally {
      release();
    }
  }

  private isV2WorkflowTimeoutError(error: Error): boolean {
    return error.message.startsWith('V2_WORKFLOW_TIMEOUT:');
  }

  /**
   * 获取单例实例
   */
  static getInstance(): NovelSourceManager {
    if (!NovelSourceManager.instance) {
      NovelSourceManager.instance = new NovelSourceManager();
    }
    return NovelSourceManager.instance;
  }

  /**
   * 导入书源（从JSON字符串）
   * 支持单个书源或书源数组，同时持久化到数据库
   */
  async importFromJSON(
    jsonStr: string,
    persistToDb: boolean = true,
    options?: NovelSourceImportOptions
  ): Promise<LegadoSourceImportResult[]> {
    const results: LegadoSourceImportResult[] = [];
    const compiler = new LegadoCompatibilityCompiler();
    const batch = await compiler.compileManyDetailed(jsonStr);
    const totalCount = batch.totalDocuments;
    logger.info(TAG, `开始导入 ${totalCount} 个书源`);

    for (let index = 0; index < batch.compiled.length; index++) {
      const importResult = await this.importCompiledSource(batch.compiled[index], persistToDb, options);
      results.push(importResult);
      if (importResult.success) {
        logger.debug(TAG, `V2 无损导入完成: ${importResult.sourceName || ''} (${index + 1}/${totalCount})`);
      }
    }

    for (let i = 0; i < batch.failures.length; i++) {
      results.push({
        success: false,
        error: `书源文档 #${batch.failures[i].ordinal + 1}: ${batch.failures[i].message}`
      });
    }
    const successCount = results.filter(r => r.success).length;
    logger.info(TAG, `书源导入完成: 成功 ${successCount}/${totalCount}`);

    return results;
  }

  /**
   * The only write boundary for a losslessly compiled source. Every importer
   * (text, network, file, repository and streaming file) must reach here.
   */
  private async importCompiledSource(
    compiled: CompiledBookSource,
    persistToDb: boolean,
    options?: NovelSourceImportOptions
  ): Promise<LegadoSourceImportResult> {
    const source = compiled.source;
    if (source.bookSourceUrl.trim().length === 0 || source.bookSourceName.trim().length === 0) {
      return {
        success: false,
        sourceName: source.bookSourceName,
        error: '书源配置验证失败：缺少 bookSourceUrl 或 bookSourceName。'
      };
    }

    try {
      this.applyImportOptions(source, options);
      const sourceId = source.bookSourceUrl;
      const isUpdate = this.sources.has(sourceId);
      const persistedMode = this.getImportedCompatibilityEngineMode(compiled);
      const compatibilityRecord = this.createCompatibilityRecord(compiled, persistedMode);

      // Persist before mutating runtime maps. A storage failure must never
      // leave a source appearing V2-ready only until the next restart.
      if (persistToDb) {
        const dataManager = getNovelDataManager();
        await dataManager.saveSourceWithCompatibilityRecord(source, compatibilityRecord);
      }

      this.sources.set(sourceId, source);
      this.executors.delete(sourceId);
      this.compiledSources.set(sourceId, compiled);
      this.v2Executors.delete(sourceId);
      await this.discardStaleVerification(compiled, persistToDb);
      await this.discardStaleExecutionTraceSummary(compiled, persistToDb);
      this.compatibilityStatuses.set(sourceId, this.resolveEffectiveCompatibilityStatus(compiled));
      this.compatibilityModes.set(sourceId, persistedMode);
      await this.syncLegadoImageVirtualSource(source);

      logger.debug(TAG, `${isUpdate ? '更新' : '导入'} V2 无损书源: ${source.bookSourceName}`);
      return {
        success: true,
        sourceId: sourceId,
        sourceName: source.bookSourceName,
        preserved: true,
        compatibilityStatus: this.getCompatibilityStatus(sourceId),
        engineMode: this.getEffectiveCompatibilityEngineMode(sourceId),
        diagnostics: this.toDiagnosticMessages(compiled)
      };
    } catch (error) {
      const message = `保存 V2 无损书源失败: ${String(error)}`;
      logger.warn(TAG, `${source.bookSourceName}: ${message}`);
      return {
        success: false,
        sourceId: source.bookSourceUrl,
        sourceName: source.bookSourceName,
        error: message,
        preserved: false,
        compatibilityStatus: compiled.status,
        engineMode: LegadoCompatibilityEngineMode.LEGACY,
        diagnostics: this.toDiagnosticMessages(compiled)
      };
    }
  }

  /**
   * Per-source storage records retain a stable user-visible recovery mode.
   * Normal traffic still follows the global policy at dispatch time.
   */
  private getImportedCompatibilityEngineMode(compiled: CompiledBookSource): LegadoCompatibilityEngineMode {
    if (this.getV2ExecutionPolicy() === LegadoV2ExecutionPolicy.LEGACY_ONLY) {
      return LegadoCompatibilityEngineMode.LEGACY;
    }
    if (compiled.status === LegadoCompatibilityStatus.READY && compiled.isStandardType()) {
      return LegadoCompatibilityEngineMode.V2_ENABLED;
    }
    return LegadoCompatibilityEngineMode.LEGACY;
  }

  private applyImportOptions(source: LegadoBookSource, options?: NovelSourceImportOptions): void {
    if (!options) {
      return;
    }

    const existing = this.sources.get(source.bookSourceUrl);
    if (options.preserveLocalState === true && existing) {
      source.enabled = existing.enabled;
      source.weight = existing.weight;
      source.customOrder = existing.customOrder;
      source.bookSourceGroup = existing.bookSourceGroup;
      source.isNSFW = existing.isNSFW;
      return;
    }

    if (!existing && options.defaultNSFW !== undefined) {
      source.isNSFW = options.defaultNSFW;
    }
  }

  /**
   * Builds the V2 evidence payload before the single transactional write.
   * The raw JSON is never reconstructed from the normalized source object.
   */
  private createCompatibilityRecord(
    compiled: CompiledBookSource,
    engineMode: LegadoCompatibilityEngineMode
  ): LegadoCompatibilityStorageRecord {
    const now = Date.now();
    return new LegadoCompatibilityStorageRecord(
      compiled.source.bookSourceUrl,
      compiled.raw.rawJson,
      compiled.raw.sha256,
      LEGADO_COMPATIBILITY_SCHEMA_VERSION,
      compiled.status,
      engineMode,
      JSON.stringify(compiled.capabilityReport),
      JSON.stringify(compiled.diagnostics),
      now,
      now
    );
  }

  private toDiagnosticMessages(compiled: CompiledBookSource): string[] {
    const messages: string[] = [];
    for (let i = 0; i < compiled.diagnostics.length; i++) {
      const diagnostic = compiled.diagnostics[i];
      messages.push(`${diagnostic.severity}:${diagnostic.code}:${diagnostic.message}`);
    }
    return messages;
  }

  /**
   * Returns the V2 state that should be shown to users.  A parsed document is
   * never treated as executable merely because it was imported.
   */
  getCompatibilitySummary(sourceId: string): LegadoCompatibilitySummary | null {
    const source = this.sources.get(sourceId);
    if (!source) {
      return null;
    }
    const compiled = this.compiledSources.get(sourceId);
    const status = this.compatibilityStatuses.get(sourceId) || LegadoCompatibilityStatus.LEGACY_UNVERIFIABLE;
    // Management UI must show the backend that the next ordinary request will
    // use, not the persisted pre-cutover preference.
    const engineMode = this.getEffectiveCompatibilityEngineMode(sourceId);
    return new LegadoCompatibilitySummary(
      sourceId,
      status,
      engineMode,
      compiled !== undefined,
      compiled ? compiled.actualSourceType : source.bookSourceType,
      compiled ? this.getCompatibilityDiagnosticMessages(sourceId, compiled) : ['INFO:LEGACY_UNVERIFIABLE:历史记录没有原始 JSON，保持旧执行器。']
    );
  }

  private getCompatibilityDiagnosticMessages(sourceId: string, compiled: CompiledBookSource): string[] {
    const messages = this.toDiagnosticMessages(compiled);
    const record = this.verificationRecords.get(sourceId);
    if (record && record.rawSha256 === compiled.raw.sha256) {
      messages.push(`INFO:V2_WORKFLOWS_VERIFIED:${record.workflows.join(',')}`);
    } else if (compiled.status === LegadoCompatibilityStatus.READY) {
      messages.push('INFO:V2_WORKFLOWS_UNVERIFIED:可编译但尚无完整工作流验证；由当前全局执行策略决定执行内核。');
    }
    return messages;
  }

  getCompatibilityStatus(sourceId: string): LegadoCompatibilityStatus {
    return this.compatibilityStatuses.get(sourceId) || LegadoCompatibilityStatus.LEGACY_UNVERIFIABLE;
  }

  getCompatibilityEngineMode(sourceId: string): LegadoCompatibilityEngineMode {
    return this.compatibilityModes.get(sourceId) || LegadoCompatibilityEngineMode.LEGACY;
  }

  /**
   * Normalizes persisted policy values before any routing decision is made.
   * Earlier development builds wrote V2_FORCE_TEST; it now means the same
   * thing as the production-visible V2_FULL_CUTOVER policy.
   */
  private normalizeV2ExecutionPolicy(value: string): LegadoV2ExecutionPolicy {
    if (value === LegadoV2ExecutionPolicy.LEGACY_ONLY) {
      return LegadoV2ExecutionPolicy.LEGACY_ONLY;
    }
    if (value === LegadoV2ExecutionPolicy.V2_VERIFIED_ONLY) {
      return LegadoV2ExecutionPolicy.V2_VERIFIED_ONLY;
    }
    if (value === LegadoV2ExecutionPolicy.V2_FULL_CUTOVER ||
      value === LegadoV2ExecutionPolicy.V2_FORCE_TEST) {
      return LegadoV2ExecutionPolicy.V2_FULL_CUTOVER;
    }
    // Missing, malformed and pre-V2 values must not silently make a new
    // installation run the legacy executor. Legacy is now an explicit
    // recovery selection only.
    return LegadoV2ExecutionPolicy.V2_FULL_CUTOVER;
  }

  /**
   * The global policy is read at dispatch time, so one management-page switch
   * applies uniformly to search, explore, details, toc, content, validation
   * and IMAGE bridge traffic.
   */
  getV2ExecutionPolicy(): LegadoV2ExecutionPolicy {
    const value = SettingsManager.getInstance().getLegadoV2ExecutionPolicy();
    return this.normalizeV2ExecutionPolicy(value);
  }

  async setV2ExecutionPolicy(policy: LegadoV2ExecutionPolicy): Promise<void> {
    const normalized = this.normalizeV2ExecutionPolicy(policy);
    await SettingsManager.getInstance().setLegadoV2ExecutionPolicy(normalized);
    logger.info(TAG, `Legado V2 全局执行策略已切换: ${normalized}`);
  }

  /** Actual backend for user traffic after applying the global policy. */
  getEffectiveCompatibilityEngineMode(sourceId: string): LegadoCompatibilityEngineMode {
    const policy = this.getV2ExecutionPolicy();
    if (policy === LegadoV2ExecutionPolicy.V2_VERIFIED_ONLY && this.canEnableV2(sourceId)) {
      return LegadoCompatibilityEngineMode.V2_ENABLED;
    }
    if (policy === LegadoV2ExecutionPolicy.V2_FULL_CUTOVER && this.canRunV2FullCutover(sourceId)) {
      return LegadoCompatibilityEngineMode.V2_ENABLED;
    }
    return LegadoCompatibilityEngineMode.LEGACY;
  }

  /** In a full cutover, returning legacy would hide a V2 compatibility failure. */
  private isV2FullCutoverBlocked(sourceId: string): boolean {
    return this.getV2ExecutionPolicy() === LegadoV2ExecutionPolicy.V2_FULL_CUTOVER &&
      !this.canRunV2FullCutover(sourceId);
  }

  /**
   * One semantic boundary for every caller that may otherwise turn a failed
   * V2 detail request into a synthetic book and continue with a later
   * workflow. Full cutover never permits that downgrade. Verified-only
   * behaves identically for sources that are actually routed to V2; sources
   * still routed to the explicit legacy path retain their historical UI
   * convenience fallbacks.
   */
  shouldBlockLegacyFallback(sourceId: string): boolean {
    if (this.getV2ExecutionPolicy() === LegadoV2ExecutionPolicy.V2_FULL_CUTOVER) {
      return true;
    }
    return this.getEffectiveCompatibilityEngineMode(sourceId) ===
      LegadoCompatibilityEngineMode.V2_ENABLED;
  }

  private getActiveV2Executor(sourceId: string): LegadoV2SourceExecutor | null {
    const allowUnverified = this.getV2ExecutionPolicy() === LegadoV2ExecutionPolicy.V2_FULL_CUTOVER;
    if ((!allowUnverified && !this.canEnableV2(sourceId)) ||
      (allowUnverified && !this.canRunV2FullCutover(sourceId))) {
      return null;
    }
    const compiled = this.compiledSources.get(sourceId);
    if (compiled === undefined) {
      return null;
    }
    // User-path calls must never share an executor with shadow or another UI
    // action. The V2 orchestrator owns mutable variables and lastTrace.
    return new LegadoV2SourceExecutor(compiled);
  }

  private logV2FullCutoverBlock(sourceId: string, workflow: LegadoWorkflowKind): void {
    logger.warn(TAG, `V2_FULL_CUTOVER 阻断旧内核回退: source=${sourceId}, workflow=${workflow}`);
  }

  getLastExecutionTrace(sourceId: string): LegadoExecutionTrace | null {
    return this.lastExecutionTraces.get(sourceId) || null;
  }

  /**
   * Returns the persisted-safe evidence for the latest V2 user-path request.
   * A summary is hidden when it belongs to a different raw source document.
   */
  getLastExecutionTraceSummary(sourceId: string): LegadoExecutionTraceSummary | null {
    const summary = this.lastExecutionTraceSummaries.get(sourceId) || null;
    if (summary === null) {
      return null;
    }
    const compiled = this.compiledSources.get(sourceId);
    if (compiled === undefined || compiled.raw.sha256 !== summary.rawSha256) {
      return null;
    }
    return summary;
  }

  /** Reports whether the most recent redacted trace was durably written. */
  getLastExecutionTracePersistenceSucceeded(sourceId: string): boolean {
    return this.executionTracePersistence.get(sourceId) === true;
  }

  /**
   * Returns one restart-safe, redacted V2 result per workflow for the current
   * losslessly compiled source document.  This is intentionally separate from
   * the old single "latest activity" projection so user-path verification can
   * prove search, detail, toc and content without relying on Hilog settings.
   */
  getExecutionTraceWorkflowSummaries(sourceId: string): LegadoExecutionTraceSummary[] {
    const summariesByWorkflow = this.executionTraceWorkflowSummaries.get(sourceId);
    const compiled = this.compiledSources.get(sourceId);
    if (summariesByWorkflow === undefined || compiled === undefined) {
      return [];
    }
    const workflows: LegadoWorkflowKind[] = [
      LegadoWorkflowKind.SEARCH,
      LegadoWorkflowKind.BOOK_INFO,
      LegadoWorkflowKind.TOC,
      LegadoWorkflowKind.CONTENT,
      LegadoWorkflowKind.EXPLORE,
      LegadoWorkflowKind.FILE,
      LegadoWorkflowKind.REVIEW
    ];
    const summaries: LegadoExecutionTraceSummary[] = [];
    for (let i = 0; i < workflows.length; i++) {
      const summary = summariesByWorkflow.get(workflows[i]);
      if (summary !== undefined && summary.rawSha256 === compiled.raw.sha256) {
        summaries.push(summary);
      }
    }
    return summaries;
  }

  /** Fixed, redacted storage provenance used only by the cross-Ability harness. */
  async getExecutionTraceStorageDiagnostic(sourceId: string): Promise<string> {
    const compiled = this.compiledSources.get(sourceId);
    if (compiled === undefined) {
      return 'storage:compiled=missing;sourceRows=0;currentRawRows=0;contentRows=0;currentContentRows=0;latestContentAt=0;currentContentAt=0';
    }
    const summaries = await getNovelDataManager().getAllCompatibilityTraceWorkflowSummaries();
    let sourceRows = 0;
    let currentRawRows = 0;
    let contentRows = 0;
    let currentContentRows = 0;
    let latestContentAt = 0;
    let currentContentAt = 0;
    for (let index = 0; index < summaries.length; index++) {
      const summary = summaries[index];
      if (summary.sourceUrl !== sourceId) {
        continue;
      }
      sourceRows++;
      if (summary.rawSha256 === compiled.raw.sha256) {
        currentRawRows++;
      }
      if (summary.workflow !== LegadoWorkflowKind.CONTENT) {
        continue;
      }
      contentRows++;
      latestContentAt = Math.max(latestContentAt, summary.occurredAt);
      if (summary.rawSha256 === compiled.raw.sha256) {
        currentContentRows++;
        currentContentAt = Math.max(currentContentAt, summary.occurredAt);
      }
    }
    return `storage:compiled=present;sourceRows=${sourceRows};currentRawRows=${currentRawRows};` +
      `contentRows=${contentRows};currentContentRows=${currentContentRows};` +
      `latestContentAt=${latestContentAt};currentContentAt=${currentContentAt}`;
  }

  /**
   * Reloads only redacted, hash-bound trace summaries for a management UI
   * refresh. An isolated reader Ability writes through the same RDB store but
   * has a separate UI lifetime; its host detail page must explicitly replace
   * its pre-reader snapshot rather than merge it back over live stale maps.
   */
  async refreshExecutionTraceSummaries(replaceFromPersistence: boolean = false): Promise<void> {
    const refreshGeneration = ++this.executionTraceRefreshGeneration;
    try {
      const dataManager = getNovelDataManager();
      if (replaceFromPersistence) {
        const freshSummaries = await dataManager.getAllCompatibilityTraceSummaries();
        const freshWorkflowSummaries = await dataManager.getAllCompatibilityTraceWorkflowSummaries();
        if (refreshGeneration !== this.executionTraceRefreshGeneration) {
          logger.debug(TAG, '忽略过期的 V2 trace 持久化刷新');
          return;
        }
        this.restoreExecutionTraceSummaries(freshSummaries);
        this.restoreExecutionTraceWorkflowSummaries(freshWorkflowSummaries);
        return;
      }
      const summaries = await dataManager.getAllCompatibilityTraceSummaries();
      const workflowSummaries = await dataManager.getAllCompatibilityTraceWorkflowSummaries();
      if (refreshGeneration !== this.executionTraceRefreshGeneration) {
        logger.debug(TAG, '忽略过期的 V2 trace 合并刷新');
        return;
      }
      // This may complete after a user request has already recorded a newer
      // trace in memory. Merge by update time rather than restoring a stale
      // database snapshot over the active user-path evidence.
      this.mergeExecutionTraceSummaries(summaries);
      this.mergeExecutionTraceWorkflowSummaries(workflowSummaries);
    } catch (error) {
      logger.warn(TAG, `刷新 V2 trace 脱敏摘要失败: ${String(error)}`);
    }
  }

  /** A user-facing explanation when V2 full cutover correctly refuses legacy fallback. */
  getV2FullCutoverBlockReason(sourceId: string): string {
    if (!this.isV2FullCutoverBlocked(sourceId)) {
      return '';
    }
    const compiled = this.compiledSources.get(sourceId);
    if (compiled === undefined) {
      return '缺少无损原始书源记录';
    }
    if (!compiled.isStandardType()) {
      return '外部或插件书源类型尚无 V2 执行器';
    }
    if (compiled.status === LegadoCompatibilityStatus.NEEDS_INTERACTION) {
      return '需要登录、验证码或人工交互';
    }
    if (compiled.status === LegadoCompatibilityStatus.UNSUPPORTED) {
      return '存在当前不支持的 Legado 能力';
    }
    if (compiled.status === LegadoCompatibilityStatus.BLOCKED) {
      return '编译诊断阻断执行';
    }
    return '无可执行的 V2 编译结果';
  }

  /** Restores redacted V2 evidence after the source and raw-hash gates load. */
  restoreExecutionTraceSummaries(summaries: LegadoExecutionTraceSummary[]): void {
    this.lastExecutionTraceSummaries.clear();
    for (let i = 0; i < summaries.length; i++) {
      const summary = summaries[i];
      const compiled = this.compiledSources.get(summary.sourceUrl);
      if (compiled === undefined || compiled.raw.sha256 !== summary.rawSha256) {
        continue;
      }
      this.lastExecutionTraceSummaries.set(summary.sourceUrl, summary);
    }
  }

  /** Merges a database refresh without allowing an older read to win a race. */
  private mergeExecutionTraceSummaries(summaries: LegadoExecutionTraceSummary[]): void {
    for (let i = 0; i < summaries.length; i++) {
      const summary = summaries[i];
      const compiled = this.compiledSources.get(summary.sourceUrl);
      if (compiled === undefined || compiled.raw.sha256 !== summary.rawSha256) {
        continue;
      }
      const current = this.lastExecutionTraceSummaries.get(summary.sourceUrl);
      if (current === undefined || current.updatedAt <= summary.updatedAt) {
        this.lastExecutionTraceSummaries.set(summary.sourceUrl, summary);
      }
    }
  }

  /** Rehydrates per-workflow proof only when it belongs to the current raw JSON. */
  restoreExecutionTraceWorkflowSummaries(summaries: LegadoExecutionTraceSummary[]): void {
    this.executionTraceWorkflowSummaries.clear();
    for (let i = 0; i < summaries.length; i++) {
      const summary = summaries[i];
      const compiled = this.compiledSources.get(summary.sourceUrl);
      if (compiled === undefined || compiled.raw.sha256 !== summary.rawSha256) {
        continue;
      }
      this.rememberExecutionTraceWorkflowSummary(summary);
    }
  }

  /** Applies the same monotonic rule to the per-workflow evidence projection. */
  private mergeExecutionTraceWorkflowSummaries(summaries: LegadoExecutionTraceSummary[]): void {
    for (let i = 0; i < summaries.length; i++) {
      const summary = summaries[i];
      const compiled = this.compiledSources.get(summary.sourceUrl);
      if (compiled === undefined || compiled.raw.sha256 !== summary.rawSha256) {
        continue;
      }
      let summariesByWorkflow = this.executionTraceWorkflowSummaries.get(summary.sourceUrl);
      if (summariesByWorkflow === undefined) {
        summariesByWorkflow = new Map<LegadoWorkflowKind, LegadoExecutionTraceSummary>();
        this.executionTraceWorkflowSummaries.set(summary.sourceUrl, summariesByWorkflow);
      }
      const current = summariesByWorkflow.get(summary.workflow);
      if (this.isExecutionTraceWorkflowSummaryNewer(summary, current)) {
        summariesByWorkflow.set(summary.workflow, summary);
      }
    }
  }

  /**
   * Returns a point-in-time, raw-hash-bound workflow snapshot directly from
   * persistence.  Cross-Ability UI must compose its display from this result
   * instead of reading a singleton Map that another asynchronous refresh can
   * replace before the page writes its @State projection.
   */
  async getPersistedExecutionTraceWorkflowSummaries(sourceId: string): Promise<LegadoExecutionTraceSummary[]> {
    const compiled = this.compiledSources.get(sourceId);
    if (compiled === undefined) {
      return [];
    }
    const persisted = await getNovelDataManager().getAllCompatibilityTraceWorkflowSummaries();
    const latestByWorkflow = new Map<LegadoWorkflowKind, LegadoExecutionTraceSummary>();
    for (let index = 0; index < persisted.length; index++) {
      const summary = persisted[index];
      if (summary.sourceUrl !== sourceId || summary.rawSha256 !== compiled.raw.sha256) {
        continue;
      }
      const current = latestByWorkflow.get(summary.workflow);
      if (this.isExecutionTraceWorkflowSummaryNewer(summary, current)) {
        latestByWorkflow.set(summary.workflow, summary);
      }
    }
    const workflows: LegadoWorkflowKind[] = [
      LegadoWorkflowKind.SEARCH,
      LegadoWorkflowKind.BOOK_INFO,
      LegadoWorkflowKind.TOC,
      LegadoWorkflowKind.CONTENT,
      LegadoWorkflowKind.EXPLORE,
      LegadoWorkflowKind.FILE,
      LegadoWorkflowKind.REVIEW
    ];
    const summaries: LegadoExecutionTraceSummary[] = [];
    for (let index = 0; index < workflows.length; index++) {
      const summary = latestByWorkflow.get(workflows[index]);
      if (summary !== undefined) {
        summaries.push(summary);
      }
    }
    return summaries;
  }

  /**
   * Creates an isolated V2 executor for an explicit diagnostics run.
   *
   * This deliberately bypasses neither source compilation nor raw-document
   * preservation. It also does not update the persisted engine mode or write
   * a verification record: a successful diagnostic run still has to pass the
   * normal evidence gate before ordinary user traffic can use V2.
   */
  createV2DiagnosticExecutor(sourceId: string): LegadoV2SourceExecutor | null {
    const compiled = this.compiledSources.get(sourceId);
    if (compiled === undefined || !compiled.isStandardType()) {
      return null;
    }
    return new LegadoV2SourceExecutor(compiled);
  }

  getRequiredV2VerificationWorkflows(sourceId: string): LegadoWorkflowKind[] {
    const compiled = this.compiledSources.get(sourceId);
    if (compiled === undefined) {
      return [];
    }
    return this.getRequiredVerificationWorkflows(compiled);
  }

  /**
   * V2 is opt-in at source granularity.  The persisted source is only switched
   * after it has an intact raw document and is independently classified READY.
   */
  async setCompatibilityEngineMode(
    sourceId: string,
    mode: LegadoCompatibilityEngineMode
  ): Promise<boolean> {
    if (!this.sources.has(sourceId)) {
      return false;
    }
    if (mode === LegadoCompatibilityEngineMode.V2_ENABLED && !this.canEnableV2(sourceId)) {
      logger.warn(TAG, `拒绝启用 V2：${sourceId} 尚未达到 READY 门槛`);
      return false;
    }
    if (mode === LegadoCompatibilityEngineMode.V2_SHADOW && !this.canRunShadow(sourceId)) {
      logger.warn(TAG, `拒绝启用 V2 shadow：${sourceId} 不是无副作用 GET 工作流`);
      return false;
    }
    try {
      await getNovelDataManager().updateCompatibilityEngineMode(sourceId, mode);
      this.compatibilityModes.set(sourceId, mode);
      if (mode === LegadoCompatibilityEngineMode.LEGACY) {
        this.v2Executors.delete(sourceId);
      }
      return true;
    } catch (error) {
      logger.warn(TAG, `更新 V2 执行模式失败: ${sourceId}, ${String(error)}`);
      return false;
    }
  }

  /**
   * Records only a complete, redacted workflow verification bundle. The raw
   * source hash is part of the record so a later import automatically loses
   * eligibility instead of running V2 against altered rules.
   */
  async recordCompatibilityVerification(
    sourceId: string,
    workflows: LegadoWorkflowKind[],
    evidenceDigest: string
  ): Promise<boolean> {
    const compiled = this.compiledSources.get(sourceId);
    if (!compiled || compiled.status !== LegadoCompatibilityStatus.READY || !compiled.isStandardType()) {
      return false;
    }
    const required = this.getRequiredVerificationWorkflows(compiled);
    if (required.length === 0 || !this.includesAllWorkflows(workflows, required)) {
      logger.warn(TAG, `拒绝不完整的 V2 工作流验证: ${sourceId}`);
      return false;
    }
    const normalizedDigest = evidenceDigest.trim();
    if (normalizedDigest.length === 0) {
      logger.warn(TAG, `拒绝没有证据摘要的 V2 工作流验证: ${sourceId}`);
      return false;
    }
    const now = Date.now();
    const record = new LegadoSourceVerificationRecord(
      sourceId,
      compiled.raw.sha256,
      required,
      normalizedDigest,
      now,
      now
    );
    try {
      await getNovelDataManager().saveCompatibilityVerification(record);
      this.verificationRecords.set(sourceId, record);
      this.compatibilityStatuses.set(sourceId, LegadoCompatibilityStatus.VERIFIED);
      return true;
    } catch (error) {
      logger.warn(TAG, `保存 V2 工作流验证失败: ${sourceId}, ${String(error)}`);
      return false;
    }
  }

  /**
   * Rebuild V2 only from a stored raw document.  Old rows that only have
   * legacy configJson remain operational but cannot be declared lossless.
   */
  async restoreCompatibilityRecords(records: LegadoCompatibilityStorageRecord[]): Promise<void> {
    const compiler = new LegadoCompatibilityCompiler();
    const restoredOrExamined: Set<string> = new Set<string>();
    for (let i = 0; i < records.length; i++) {
      const record = records[i];
      const savedSource = this.sources.get(record.sourceUrl);
      if (!savedSource) {
        logger.warn(TAG, `兼容记录缺少对应书源，忽略恢复: ${record.sourceUrl}`);
        continue;
      }
      restoredOrExamined.add(record.sourceUrl);
      try {
        const compiled = await compiler.compileOne(record.rawJson);
        if (compiled === null || compiled.source.bookSourceUrl !== record.sourceUrl ||
          compiled.raw.sha256 !== record.rawSha256) {
          this.compatibilityStatuses.set(record.sourceUrl, LegadoCompatibilityStatus.BLOCKED);
          this.compatibilityModes.set(record.sourceUrl, LegadoCompatibilityEngineMode.LEGACY);
          logger.warn(TAG, `兼容记录校验失败，回退旧执行器: ${record.sourceUrl}`);
          continue;
        }
        this.applySavedLocalState(savedSource, compiled.source);
        this.sources.set(record.sourceUrl, compiled.source);
        this.executors.delete(record.sourceUrl);
        this.v2Executors.delete(record.sourceUrl);
        this.compiledSources.set(record.sourceUrl, compiled);
        this.compatibilityStatuses.set(record.sourceUrl, this.resolveEffectiveCompatibilityStatus(compiled));
        const restoredMode = this.resolveRestoredMode(record.sourceUrl, record.engineMode);
        this.compatibilityModes.set(record.sourceUrl, restoredMode);
        // A compiler contract may gain support for an existing Legado API
        // without changing the storage schema. Keep the persisted readiness
        // snapshot in step with the freshly compiled source so full cutover
        // never routes using stale BLOCKED diagnostics after an app upgrade.
        if (this.isCompatibilitySnapshotStale(record, compiled)) {
          await getNovelDataManager().saveCompatibilityRecord(
            this.createCompatibilityRecord(compiled, record.engineMode)
          );
          logger.info(TAG, `已刷新 V2 编译快照: ${record.sourceUrl}`);
        }
        await this.syncLegadoImageVirtualSource(compiled.source);
      } catch (error) {
        this.compatibilityStatuses.set(record.sourceUrl, LegadoCompatibilityStatus.BLOCKED);
        this.compatibilityModes.set(record.sourceUrl, LegadoCompatibilityEngineMode.LEGACY);
        logger.warn(TAG, `恢复兼容记录失败，回退旧执行器: ${record.sourceUrl}, ${String(error)}`);
      }
    }
    this.sources.forEach((_source: LegadoBookSource, sourceUrl: string): void => {
      if (!restoredOrExamined.has(sourceUrl) && !this.compiledSources.has(sourceUrl)) {
        this.compatibilityStatuses.set(sourceUrl, LegadoCompatibilityStatus.LEGACY_UNVERIFIABLE);
        this.compatibilityModes.set(sourceUrl, LegadoCompatibilityEngineMode.LEGACY);
      }
    });
  }

  /** Restore only records whose raw hash still matches the compiled source. */
  async restoreCompatibilityVerifications(records: LegadoSourceVerificationRecord[]): Promise<void> {
    for (let i = 0; i < records.length; i++) {
      const record = records[i];
      const compiled = this.compiledSources.get(record.sourceUrl);
      if (!compiled || compiled.raw.sha256 !== record.rawSha256 ||
        !this.includesAllWorkflows(record.workflows, this.getRequiredVerificationWorkflows(compiled))) {
        logger.warn(TAG, `忽略已过期或不完整的 V2 工作流验证: ${record.sourceUrl}`);
        continue;
      }
      this.verificationRecords.set(record.sourceUrl, record);
      this.compatibilityStatuses.set(record.sourceUrl, LegadoCompatibilityStatus.VERIFIED);
    }
  }

  private applySavedLocalState(saved: LegadoBookSource, target: LegadoBookSource): void {
    target.enabled = saved.enabled;
    target.bookSourceGroup = saved.bookSourceGroup;
    target.weight = saved.weight;
    target.customOrder = saved.customOrder;
    target.isNSFW = saved.isNSFW;
    target.respondTime = saved.respondTime;
  }

  private resolveRestoredMode(
    sourceId: string,
    requestedMode: LegadoCompatibilityEngineMode
  ): LegadoCompatibilityEngineMode {
    if (requestedMode === LegadoCompatibilityEngineMode.V2_ENABLED && this.canEnableV2(sourceId)) {
      return LegadoCompatibilityEngineMode.V2_ENABLED;
    }
    if (requestedMode === LegadoCompatibilityEngineMode.V2_SHADOW && this.canRunShadow(sourceId)) {
      return LegadoCompatibilityEngineMode.V2_SHADOW;
    }
    return LegadoCompatibilityEngineMode.LEGACY;
  }

  private isCompatibilitySnapshotStale(
    record: LegadoCompatibilityStorageRecord,
    compiled: CompiledBookSource
  ): boolean {
    if (record.compilerVersion !== LEGADO_COMPATIBILITY_SCHEMA_VERSION ||
      record.status !== compiled.status) {
      return true;
    }
    const capabilityJson = JSON.stringify(compiled.capabilityReport);
    if (record.capabilityJson !== capabilityJson) {
      return true;
    }
    return record.diagnosticsJson !== JSON.stringify(compiled.diagnostics);
  }

  private canEnableV2(sourceId: string): boolean {
    const compiled = this.compiledSources.get(sourceId);
    if (compiled === undefined || compiled.status !== LegadoCompatibilityStatus.READY || !compiled.isStandardType()) {
      return false;
    }
    const verification = this.verificationRecords.get(sourceId);
    return verification !== undefined && verification.rawSha256 === compiled.raw.sha256 &&
      this.includesAllWorkflows(verification.workflows, this.getRequiredVerificationWorkflows(compiled));
  }

  /**
   * Full cutover may execute an unverified but losslessly compiled standard
   * source only when every declared requirement is ready. Interaction,
   * paywall, review and file diagnostics must stop at this central boundary:
   * allowing partial execution would silently discard a user-facing action.
   */
  private canRunV2FullCutover(sourceId: string): boolean {
    const compiled = this.compiledSources.get(sourceId);
    if (compiled === undefined || !compiled.isStandardType()) {
      return false;
    }
    return compiled.status === LegadoCompatibilityStatus.READY;
  }

  private canRunShadow(sourceId: string): boolean {
    const compiled = this.compiledSources.get(sourceId);
    if (!compiled || compiled.status !== LegadoCompatibilityStatus.READY ||
      !compiled.isStandardType() || compiled.actualSourceType !== LegadoBookSourceType.TEXT) {
      return false;
    }
    const source = compiled.source;
    const templates: string[] = [source.searchUrl || '', source.exploreUrl || ''];
    for (let i = 0; i < templates.length; i++) {
      if (!this.isSafeShadowTemplate(templates[i])) {
        return false;
      }
    }
    return !source.loginUrl && !source.loginUi && !source.loginCheckJs;
  }

  private resolveEffectiveCompatibilityStatus(compiled: CompiledBookSource): LegadoCompatibilityStatus {
    const verification = this.verificationRecords.get(compiled.source.bookSourceUrl);
    if (compiled.status === LegadoCompatibilityStatus.READY && verification !== undefined &&
      verification.rawSha256 === compiled.raw.sha256 &&
      this.includesAllWorkflows(verification.workflows, this.getRequiredVerificationWorkflows(compiled))) {
      return LegadoCompatibilityStatus.VERIFIED;
    }
    return compiled.status;
  }

  private getRequiredVerificationWorkflows(compiled: CompiledBookSource): LegadoWorkflowKind[] {
    const workflows: LegadoWorkflowKind[] = [];
    const source = compiled.source;
    if (source.searchUrl && source.ruleSearch && source.ruleSearch.bookList) {
      workflows.push(LegadoWorkflowKind.SEARCH);
    }
    if (source.exploreUrl && source.ruleExplore && source.ruleExplore.bookList) {
      workflows.push(LegadoWorkflowKind.EXPLORE);
    }
    if (source.ruleBookInfo) {
      workflows.push(LegadoWorkflowKind.BOOK_INFO);
    }
    if (source.ruleToc && source.ruleToc.chapterList) {
      workflows.push(LegadoWorkflowKind.TOC);
    }
    if (source.ruleContent && source.ruleContent.content) {
      workflows.push(LegadoWorkflowKind.CONTENT);
    }
    if (source.ruleBookInfo && source.ruleBookInfo.downloadUrls) {
      workflows.push(LegadoWorkflowKind.FILE);
    }
    if (source.ruleReview && source.ruleReview.reviewList) {
      workflows.push(LegadoWorkflowKind.REVIEW);
    }
    return workflows;
  }

  private includesAllWorkflows(
    actual: LegadoWorkflowKind[],
    expected: LegadoWorkflowKind[]
  ): boolean {
    for (let i = 0; i < expected.length; i++) {
      if (!actual.includes(expected[i])) {
        return false;
      }
    }
    return true;
  }

  private async discardStaleVerification(compiled: CompiledBookSource, persistToDb: boolean): Promise<void> {
    const existing = this.verificationRecords.get(compiled.source.bookSourceUrl);
    if (!existing || existing.rawSha256 === compiled.raw.sha256) {
      return;
    }
    this.verificationRecords.delete(compiled.source.bookSourceUrl);
    if (persistToDb) {
      try {
        await getNovelDataManager().deleteCompatibilityVerification(compiled.source.bookSourceUrl);
      } catch (error) {
        logger.warn(TAG, `清除过期 V2 工作流验证失败: ${compiled.source.bookSourceUrl}, ${String(error)}`);
      }
    }
  }

  private async discardStaleExecutionTraceSummary(
    compiled: CompiledBookSource,
    persistToDb: boolean
  ): Promise<void> {
    const sourceId = compiled.source.bookSourceUrl;
    const summary = this.lastExecutionTraceSummaries.get(sourceId);
    const workflowSummaries = this.executionTraceWorkflowSummaries.get(sourceId);
    let isStale = summary !== undefined && summary.rawSha256 !== compiled.raw.sha256;
    if (workflowSummaries !== undefined) {
      for (const workflowSummary of workflowSummaries.values()) {
        if (workflowSummary.rawSha256 !== compiled.raw.sha256) {
          isStale = true;
          break;
        }
      }
    }
    if (!isStale) {
      return;
    }
    this.lastExecutionTraceSummaries.delete(sourceId);
    this.lastExecutionTraces.delete(sourceId);
    this.executionTraceWorkflowSummaries.delete(sourceId);
    if (!persistToDb) {
      return;
    }
    try {
      await getNovelDataManager().deleteCompatibilityTraceSummary(sourceId);
      await getNovelDataManager().deleteCompatibilityTraceWorkflowSummaries(sourceId);
    } catch (error) {
      logger.warn(TAG, `清除过期 V2 trace 摘要失败: ${sourceId}, ${String(error)}`);
    }
  }

  private isSafeShadowTemplate(template: string): boolean {
    const normalized = template.toLowerCase();
    return !normalized.includes('@js') && !normalized.includes('<js>') &&
      !normalized.includes('webview') && !normalized.includes('webjs') &&
      !normalized.includes('"body"') && !normalized.includes("'body'") &&
      !normalized.includes('"data"') && !normalized.includes("'data'") &&
      !normalized.includes('"method"') && !normalized.includes("'method'");
  }
  
  /**
   * 批量导入书源（带进度回调）
   * 适用于大量书源导入场景
   */
  async importFromJSONWithProgress(
    jsonStr: string,
    onProgress?: (current: number, total: number, sourceName: string) => void
  ): Promise<LegadoSourceImportResult[]> {
    const results: LegadoSourceImportResult[] = [];
    const compiler = new LegadoCompatibilityCompiler();
    const batch = await compiler.compileManyDetailed(jsonStr);
    const totalCount = batch.totalDocuments;
    logger.info(TAG, `开始批量导入 ${totalCount} 个书源`);

    for (let i = 0; i < batch.compiled.length; i++) {
      const compiled = batch.compiled[i];
      const current = i + 1;
      onProgress?.(current, totalCount, compiled.source.bookSourceName);
      results.push(await this.importCompiledSource(compiled, true));
    }

    for (let i = 0; i < batch.failures.length; i++) {
      results.push({
        success: false,
        error: `书源文档 #${batch.failures[i].ordinal + 1}: ${batch.failures[i].message}`
      });
    }
    
    const successCount = results.filter(r => r.success).length;
    logger.info(TAG, `批量导入完成: 成功 ${successCount}/${totalCount}`);

    return results;
  }

  /**
   * 获取所有书源
   * 排序规则：启用的书源按 customOrder 排序，未启用的书源放在末尾
   */
  getAllSources(): NovelSourceInfo[] {
    const infos: NovelSourceInfo[] = [];
    
    this.sources.forEach((source, url) => {
      infos.push({
        id: url,
        name: source.bookSourceName,
        url: url,
        group: source.bookSourceGroup,
        bookSourceType: source.bookSourceType,
        enabled: source.enabled !== false,
        weight: source.weight || 0,
        customOrder: source.customOrder ?? 0,
        lastUpdateTime: source.lastUpdateTime || 0,
        respondTime: source.respondTime || 180000,
        searchable: !!source.searchUrl,
        hasExplore: !!source.exploreUrl,
        isNSFW: source.isNSFW === true,
        compatibilityStatus: this.getCompatibilityStatus(url),
        engineMode: this.getEffectiveCompatibilityEngineMode(url),
        v2FullCutoverBlockReason: this.getV2FullCutoverBlockReason(url)
      });
    });

    // 排序规则：启用的书源按 customOrder 升序（越小越靠前），未启用的放在末尾
    infos.sort((a, b) => {
      // 启用状态不同：启用的在前，未启用的在后
      if (a.enabled !== b.enabled) {
        return a.enabled ? -1 : 1;
      }
      // 同为启用或同为未启用：按 customOrder 升序
      return a.customOrder - b.customOrder;
    });
    return infos;
  }

  /**
   * 获取启用的书源
   */
  getEnabledSources(): NovelSourceInfo[] {
    return this.getAllSources().filter(s => s.enabled);
  }

  /**
   * 删除书源（同时从数据库删除）
   */
  async deleteSource(sourceId: string): Promise<boolean> {
    const deletedSource = this.sources.get(sourceId) || null;
    this.executors.delete(sourceId);
    this.compiledSources.delete(sourceId);
    this.v2Executors.delete(sourceId);
    this.compatibilityModes.delete(sourceId);
    this.compatibilityStatuses.delete(sourceId);
    this.verificationRecords.delete(sourceId);
    this.lastExecutionTraces.delete(sourceId);
    this.lastExecutionTraceSummaries.delete(sourceId);
    const deleted = this.sources.delete(sourceId);
    
    // 从数据库删除
    if (deleted) {
      try {
        const dataManager = getNovelDataManager();
        await dataManager.deleteSource(sourceId);
        if (deletedSource) {
          await this.disableLegadoImageVirtualSource(deletedSource);
        }
        logger.info(TAG, `已删除书源: ${sourceId}`);
      } catch (error) {
        logger.warn(TAG, `从数据库删除书源失败: ${String(error)}`);
      }
    }
    
    return deleted;
  }

  /**
   * 启用/禁用书源（同时更新数据库）
   */
  async setSourceEnabled(sourceId: string, enabled: boolean): Promise<boolean> {
    const source = this.sources.get(sourceId);
    if (source) {
      source.enabled = enabled;
      
      // 更新数据库
      try {
        const dataManager = getNovelDataManager();
        await dataManager.saveSource(source);
      } catch (error) {
        logger.warn(TAG, `更新书源状态失败: ${String(error)}`);
      }
      await this.syncLegadoImageVirtualSource(source);
      
      return true;
    }
    return false;
  }

  private async syncLegadoImageVirtualSource(source: LegadoBookSource): Promise<void> {
    if (source.bookSourceType !== LegadoBookSourceType.IMAGE) {
      return;
    }
    try {
      await getLegadoMangaSourceBridge().ensureVirtualComicSource(source);
    } catch (error) {
      logger.warn(TAG, `同步Legado漫画虚拟图源失败: ${source.bookSourceName}, ${String(error)}`);
    }
  }

  private async disableLegadoImageVirtualSource(source: LegadoBookSource): Promise<void> {
    if (source.bookSourceType !== LegadoBookSourceType.IMAGE) {
      return;
    }
    try {
      await getLegadoMangaSourceBridge().disableVirtualComicSource(source);
    } catch (error) {
      logger.warn(TAG, `停用Legado漫画虚拟图源失败: ${source.bookSourceName}, ${String(error)}`);
    }
  }

  /**
   * 设置书源的NSFW状态
   */
  async setSourceNSFW(sourceId: string, isNSFW: boolean): Promise<boolean> {
    const source = this.sources.get(sourceId);
    if (source) {
      source.isNSFW = isNSFW;

      // 更新数据库
      try {
        const dataManager = getNovelDataManager();
        await dataManager.saveSource(source);
        logger.info(TAG, `书源NSFW状态已更新: ${source.bookSourceName}, isNSFW=${isNSFW}`);
      } catch (error) {
        logger.warn(TAG, `更新书源NSFW状态失败: ${String(error)}`);
      }

      return true;
    }
    return false;
  }

  /**
   * 获取原始书源对象
   */
  getSource(sourceId: string): LegadoBookSource | null {
    return this.sources.get(sourceId) || null;
  }

  /**
   * 获取执行器
   */
  private getExecutor(sourceId: string): NovelSourceExecutor | null {
    if (this.executors.has(sourceId)) {
      return this.executors.get(sourceId)!;
    }

    const source = this.sources.get(sourceId);
    if (!source) {
      return null;
    }

    const executor = new NovelSourceExecutor(source);
    this.executors.set(sourceId, executor);
    return executor;
  }

  private getV2Executor(sourceId: string, allowUnverified: boolean = false): LegadoV2SourceExecutor | null {
    if ((!allowUnverified && !this.canEnableV2(sourceId)) ||
      (allowUnverified && !this.canRunV2FullCutover(sourceId))) {
      return null;
    }
    const existing = this.v2Executors.get(sourceId);
    if (existing) {
      return existing;
    }
    const compiled = this.compiledSources.get(sourceId);
    if (!compiled) {
      return null;
    }
    const executor = new LegadoV2SourceExecutor(compiled);
    this.v2Executors.set(sourceId, executor);
    return executor;
  }

  /**
   * Records V2 evidence before the caller returns control to a page. Awaiting
   * the database write makes a search → detail → reader → management-page
   * path observable even when the page stack is recreated immediately.
   */
  private async recordV2Trace(
    sourceId: string,
    trace: LegadoExecutionTrace | null,
    cancellationToken?: LegadoExecutionCancellationToken
  ): Promise<boolean> {
    cancellationToken?.throwIfCancelled();
    if (!trace) {
      logger.error(TAG, `V2_TRACE_MISSING source=${sourceId}; V2 结果不具备可复核执行证据`);
      // A V2 result without a trace is not a valid empty result.  Full-cutover
      // callers must surface this explicitly instead of silently presenting it
      // as a successful search with zero books.
      throw new Error('V2_EXECUTION_TRACE_MISSING');
    }
    cancellationToken?.throwIfCancelled();
    this.lastExecutionTraces.set(sourceId, trace);
    try {
      const compiled = this.compiledSources.get(sourceId);
      let summary: LegadoExecutionTraceSummary | null = null;
      if (compiled !== undefined) {
        const now = Date.now();
        // Persist a structurally complete, redacted summary before optional
        // digest enrichment. A malformed transport value must never erase
        // proof that this exact V2 workflow reached a terminal outcome.
        const fallbackNetworkEvidence = new LegadoNetworkTraceEvidence(
          'digest_pending',
          'digest_pending',
          '',
          Math.max(0, trace.response.redirectChain.length - 1)
        );
        const contentDiagnostics = this.createContentTraceDiagnostics(trace);
        summary = new LegadoExecutionTraceSummary(
          sourceId,
          compiled.raw.sha256,
          trace.workflow,
          trace.response.transport,
          trace.response.statusCode,
          trace.response.finalUrlObservation,
          trace.response.errorCode,
          trace.outputSummary,
          trace.request.optionTrace.length,
          trace.variableChanges.length,
          now,
          now,
          fallbackNetworkEvidence,
          contentDiagnostics
        );
        this.lastExecutionTraceSummaries.set(sourceId, summary);
        this.rememberExecutionTraceWorkflowSummary(summary);
        cancellationToken?.throwIfCancelled();
        await this.persistExecutionTraceSummary(summary);

        try {
          const networkEvidence = await LegadoTraceSerializer.toNetworkTraceEvidence(trace);
          cancellationToken?.throwIfCancelled();
          summary = new LegadoExecutionTraceSummary(
            sourceId,
            compiled.raw.sha256,
            trace.workflow,
            trace.response.transport,
            trace.response.statusCode,
            trace.response.finalUrlObservation,
            trace.response.errorCode,
            trace.outputSummary,
            trace.request.optionTrace.length,
            trace.variableChanges.length,
            now,
            Date.now(),
            networkEvidence,
            contentDiagnostics
          );
        } catch (error) {
          logger.warn(TAG, `生成 V2 网络摘要失败，保留基础证据: ${sourceId}, ${String(error)}`);
        }
      }
      if (summary !== null) {
        this.lastExecutionTraceSummaries.set(sourceId, summary);
        this.rememberExecutionTraceWorkflowSummary(summary);
        cancellationToken?.throwIfCancelled();
        await this.persistExecutionTraceSummary(summary);
      }
    } catch (error) {
      // A valid trace remains available in memory. Observability persistence
      // is best effort and must not change the completed workflow result.
      logger.warn(TAG, `写入 V2 trace 诊断证据失败: ${sourceId}, ${String(error)}`);
    }
    try {
      // The redacted in-memory inspector is diagnostic-only. Its failure must
      // never prevent the hash-bound workflow summary above from surviving a
      // return to source management or a process recreation.
      getLegadoExecutionTraceStore().record(trace);
    } catch (error) {
      logger.warn(TAG, `写入 V2 内存 trace 诊断失败: ${sourceId}, ${String(error)}`);
    }
    // This deliberately contains no URL, request/response body, header, cookie
    // or variable value. It is the production-visible proof that ordinary
    // traffic used V2 rather than falling through to the legacy executor.
    logger.warn(
      TAG,
      `V2_TRACE workflow=${trace.workflow};transport=${trace.response.transport};` +
      `http=${trace.response.statusCode};finalUrl=${trace.response.finalUrlObservation};` +
      `error=${trace.response.errorCode};options=${trace.request.optionTrace.length};` +
      `variables=${trace.variableChanges.length};output=${trace.outputSummary}`
    );
    return true;
  }

  /**
   * V2 workflows may represent transport, policy, and rule failures as an
   * empty typed result. Persist the trace first, then reject only responses
   * without a rule-readable payload. Legado evaluates received HTTP error
   * documents, so a 4xx/5xx status with a body remains observable in the
   * trace while the workflow is allowed to apply its declared rules.
   */
  private async recordV2TraceAndRequireSuccess(
    sourceId: string,
    trace: LegadoExecutionTrace | null,
    cancellationToken?: LegadoExecutionCancellationToken
  ): Promise<void> {
    await this.recordV2Trace(sourceId, trace, cancellationToken);
    if (trace === null) {
      throw new Error('V2_EXECUTION_TRACE_MISSING');
    }
    if (!trace.response.hasRuleReadableBody()) {
      throw new Error(
        `V2_EXECUTION_FAILED;workflow=${trace.workflow};` +
        `error=${trace.response.errorCode};status=${trace.response.statusCode}`
      );
    }
  }

  private async persistExecutionTraceSummary(summary: LegadoExecutionTraceSummary): Promise<boolean> {
    this.executionTracePersistence.set(summary.sourceUrl, false);
    const retryDelays: number[] = [0, 120, 360];
    let lastError: string = '';
    for (let attempt = 0; attempt < retryDelays.length; attempt++) {
      const delay = retryDelays[attempt];
      if (delay > 0) {
        await new Promise<void>((resolve: () => void): void => {
          setTimeout(resolve, delay);
        });
      }
      try {
        const dataManager = getNovelDataManager();
        await dataManager.saveCompatibilityTraceSummary(summary);
        await dataManager.saveCompatibilityTraceWorkflowSummary(summary);
        const workflowVisible = await dataManager.isCompatibilityTraceWorkflowSummaryPersisted(summary);
        if (!workflowVisible) {
          lastError = 'workflow_trace_read_back_not_visible';
          continue;
        }
        this.executionTracePersistence.set(summary.sourceUrl, true);
        return true;
      } catch (error) {
        lastError = String(error);
      }
    }
    logger.warn(TAG, `保存 V2 trace 脱敏摘要失败: ${summary.sourceUrl};attempts=${retryDelays.length};error=${lastError}`);
    return false;
  }

  /**
   * Extracts the fixed content grammar once at the trace boundary. The parsed
   * values are persisted separately from the human-readable summary so device
   * automation never depends on a page Text node or a regex over UI copy.
   */
  private createContentTraceDiagnostics(trace: LegadoExecutionTrace): LegadoContentTraceDiagnostics {
    if (trace.workflow !== LegadoWorkflowKind.CONTENT) {
      return new LegadoContentTraceDiagnostics();
    }
    const match = trace.outputSummary.match(/^content:pages=\d+;fragments=\d+;chars=(\d+);replace=(?:applied|none);presentation=([a-z_]+);bridge=([a-z_]+);bridgeChars=(\d+);bridgeDigest=([a-z0-9_]+);(?:bridgeReaderChars=\d+;bridgeReaderLf=\d+;bridgeReaderDigest=[a-z0-9_]+;)?digest=([a-z0-9_]+)(?:;[A-Za-z0-9_:=./,\-]+)*$/i);
    if (match === null) {
      return new LegadoContentTraceDiagnostics('unrecognized');
    }
    return new LegadoContentTraceDiagnostics(
      match[2].toLowerCase(),
      Number(match[1]),
      match[3].toLowerCase(),
      Number(match[4]),
      match[5].toLowerCase(),
      match[6].toLowerCase()
    );
  }

  private rememberExecutionTraceWorkflowSummary(summary: LegadoExecutionTraceSummary): void {
    let summariesByWorkflow = this.executionTraceWorkflowSummaries.get(summary.sourceUrl);
    if (summariesByWorkflow === undefined) {
      summariesByWorkflow = new Map<LegadoWorkflowKind, LegadoExecutionTraceSummary>();
      this.executionTraceWorkflowSummaries.set(summary.sourceUrl, summariesByWorkflow);
    }
    const current = summariesByWorkflow.get(summary.workflow);
    if (this.isExecutionTraceWorkflowSummaryNewer(summary, current)) {
      summariesByWorkflow.set(summary.workflow, summary);
    }
  }

  /** Maintains a deterministic newest-wins order even when update times tie. */
  private isExecutionTraceWorkflowSummaryNewer(
    candidate: LegadoExecutionTraceSummary,
    current: LegadoExecutionTraceSummary | undefined
  ): boolean {
    if (current === undefined) {
      return true;
    }
    if (candidate.updatedAt !== current.updatedAt) {
      return candidate.updatedAt > current.updatedAt;
    }
    return candidate.occurredAt >= current.occurredAt;
  }

  private async mapSearchBooks(
    sourceId: string,
    source: LegadoBookSource,
    books: LegadoSearchBook[],
    parseOptions?: SearchParseOptions,
    cancellationToken?: LegadoExecutionCancellationToken
  ): Promise<NovelSearchResult[]> {
    cancellationToken?.throwIfCancelled();
    const mapped: NovelSearchResult[] = [];
    const maxResults = parseOptions?.forceFullExecution === true || !parseOptions?.maxResults || parseOptions.maxResults <= 0
      ? Number.MAX_SAFE_INTEGER
      : Math.floor(parseOptions.maxResults);
    const mapYieldStep = parseOptions?.forceFullExecution === true ? 80 : 200;
    for (let i = 0; i < books.length && mapped.length < maxResults; i++) {
      cancellationToken?.throwIfCancelled();
      const book = books[i];
      const requestCarrierKey = this.rememberV2BookRequestCarrier(
        sourceId,
        book.bookUrl,
        book.requestCarrier,
        book.requestUrlTemplate,
        book.requestCarrier?.originWorkflow || 'search'
      );
      mapped.push({
        sourceId: sourceId,
        sourceName: source.bookSourceName,
        bookUrl: book.bookUrl,
        name: book.name,
        author: book.author,
        kind: book.kind,
        intro: book.intro,
        coverUrl: book.coverUrl,
        latestChapterTitle: book.latestChapterTitle,
        wordCount: book.wordCount,
        isNSFW: source.isNSFW === true,
        variable: book.variable,
        requestCarrierKey: requestCarrierKey
      });
      this.rememberV2BookVariableSnapshot(sourceId, book.bookUrl, book.variable);
      if ((i + 1) % mapYieldStep === 0) {
        await this.yieldToEventLoop();
        cancellationToken?.throwIfCancelled();
      }
    }
    return mapped;
  }

  private createV2SearchExecutionOptions(parseOptions?: SearchParseOptions): LegadoSearchExecutionOptions {
    const maxResults = parseOptions?.maxResults && parseOptions.maxResults > 0
      ? Math.floor(parseOptions.maxResults)
      : 0;
    return new LegadoSearchExecutionOptions(maxResults, parseOptions?.forceFullExecution === true);
  }

  private scheduleShadowSearch(sourceId: string, keyword: string, page: number): void {
    if (this.getV2ExecutionPolicy() === LegadoV2ExecutionPolicy.LEGACY_ONLY ||
      this.getCompatibilityEngineMode(sourceId) !== LegadoCompatibilityEngineMode.V2_SHADOW ||
      !this.canRunShadow(sourceId)) {
      return;
    }
    const work: Promise<void> = this.runShadowSearch(sourceId, keyword, page);
    work.catch((error: Error): void => {
      logger.warn(TAG, `V2 shadow 搜索失败: ${sourceId}, ${String(error)}`);
    });
  }

  private async runShadowSearch(sourceId: string, keyword: string, page: number): Promise<void> {
    const executor = this.getV2Executor(sourceId, true);
    if (!executor) {
      return;
    }
    await executor.search(keyword, page);
    // Shadow traffic is not user-path evidence. Persisting it here could make
    // a source card describe a different request than the visible page.
    logger.debug(TAG, `V2 shadow 搜索完成（不写入用户 trace）: ${sourceId}`);
  }

  private scheduleShadowExplore(sourceId: string, exploreUrl: string, page: number): void {
    if (this.getV2ExecutionPolicy() === LegadoV2ExecutionPolicy.LEGACY_ONLY ||
      this.getCompatibilityEngineMode(sourceId) !== LegadoCompatibilityEngineMode.V2_SHADOW ||
      !this.canRunShadow(sourceId)) {
      return;
    }
    const work: Promise<void> = this.runShadowExplore(sourceId, exploreUrl, page);
    work.catch((error: Error): void => {
      logger.warn(TAG, `V2 shadow 发现页失败: ${sourceId}, ${String(error)}`);
    });
  }

  private async runShadowExplore(sourceId: string, exploreUrl: string, page: number): Promise<void> {
    const executor = this.getV2Executor(sourceId, true);
    if (!executor) {
      return;
    }
    await executor.explore(exploreUrl, page);
    logger.debug(TAG, `V2 shadow 发现页完成（不写入用户 trace）: ${sourceId}`);
  }

  /**
   * 搜索书籍（单个书源）
   */
  async search(
    sourceId: string,
    keyword: string,
    page: number = 1,
    parseOptions?: SearchParseOptions,
    cancellationToken?: LegadoExecutionCancellationToken
  ): Promise<NovelSearchResult[]> {
    cancellationToken?.throwIfCancelled();
    const source = this.sources.get(sourceId);
    if (!source) {
      logger.warn(TAG, `书源不存在: ${sourceId}`);
      return [];
    }
    if (this.getEffectiveCompatibilityEngineMode(sourceId) === LegadoCompatibilityEngineMode.V2_ENABLED) {
      const v2Executor = this.getActiveV2Executor(sourceId);
      if (!v2Executor) {
        logger.warn(TAG, `V2 未就绪，拒绝执行: ${sourceId}`);
        // Full cutover must never turn an unavailable V2 executor into a
        // plausible empty search result. Callers need an explicit failure so
        // they neither render a false empty state nor silently use legacy.
        throw new Error('V2_EXECUTION_UNAVAILABLE;workflow=search');
      }
      let v2SearchStage: string = 'request';
      let v2Trace: LegadoExecutionTrace | null = null;
      try {
        const v2Options = this.createV2SearchExecutionOptions(parseOptions);
        const v2Result = await v2Executor.searchWithTrace(keyword, page, cancellationToken, v2Options);
        v2Trace = v2Result.trace;
        cancellationToken?.throwIfCancelled();
        v2SearchStage = 'trace';
        await this.recordV2TraceAndRequireSuccess(sourceId, v2Trace, cancellationToken);
        cancellationToken?.throwIfCancelled();
        v2SearchStage = 'result_mapping';
        return await this.mapSearchBooks(sourceId, source, v2Result.books, parseOptions, cancellationToken);
      } catch (error) {
        cancellationToken?.throwIfCancelled();
        if (v2Trace === null) {
          v2Trace = v2Executor.getLastTrace();
        }
        await this.recordV2Trace(sourceId, v2Trace);
        logger.warn(TAG, `V2 搜索失败: ${sourceId};stage=${v2SearchStage};error=${String(error)}`);
        const traceErrorCode: string = v2Trace === null ? 'trace_missing' : v2Trace.response.errorCode;
        const traceStatusCode: number = v2Trace === null ? 0 : v2Trace.response.statusCode;
        throw new Error(
          `V2_EXECUTION_FAILED;workflow=search;stage=${v2SearchStage};` +
          `error=${traceErrorCode};status=${traceStatusCode}`
        );
      }
    }
    if (this.isV2FullCutoverBlocked(sourceId)) {
      this.logV2FullCutoverBlock(sourceId, LegadoWorkflowKind.SEARCH);
      throw new Error(
        `V2_FULL_CUTOVER_BLOCKED;workflow=search;reason=${this.getV2FullCutoverBlockReason(sourceId)}`
      );
    }
    const executor = this.getExecutor(sourceId);
    if (!executor) {
      logger.warn(TAG, `书源不存在: ${sourceId}`);
      return [];
    }

    const results = await executor.search(keyword, page, parseOptions);
    this.scheduleShadowSearch(sourceId, keyword, page);
    return await this.mapSearchBooks(sourceId, source, results, parseOptions);
  }

  private async yieldToEventLoop(): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, 0));
  }

  /**
   * 搜索书籍（多个书源并行，限制并发数）
   * @param keyword 搜索关键词
   * @param page 页码
   * @param maxConcurrent 最大并发书源数，默认10
   */
  async searchAll(keyword: string, page: number = 1, maxConcurrent: number = 10): Promise<NovelSearchResult[]> {
    const enabledSources = this.getEnabledSources().filter(s => s.searchable);
    const allResults: NovelSearchResult[] = [];
    
    // 限制搜索的书源数量，避免同时搜索太多导致主线程阻塞
    const sourcesToSearch = enabledSources.slice(0, maxConcurrent);
    
    logger.info(TAG, `搜索 "${keyword}"，使用 ${sourcesToSearch.length}/${enabledSources.length} 个书源`);

    // 并行搜索选中的书源
    const promises = sourcesToSearch.map(async (sourceInfo) => {
      try {
        const results = await this.search(sourceInfo.id, keyword, page);
        return results;
      } catch (error) {
        logger.warn(TAG, `书源 ${sourceInfo.name} 搜索失败: ${String(error)}`);
        return [];
      }
    });

    const resultsArray = await Promise.all(promises);
    for (const results of resultsArray) {
      allResults.push(...results);
    }

    return allResults;
  }
  
  /**
   * 搜索书籍（分批并行，适用于大量书源）
   * @param keyword 搜索关键词
   * @param page 页码
   * @param batchSize 每批并发数
   * @param onProgress 进度回调
   */
  async searchAllBatched(
    keyword: string, 
    page: number = 1, 
    batchSize: number = 5,
    onProgress?: (completed: number, total: number, results: NovelSearchResult[]) => void
  ): Promise<NovelSearchResult[]> {
    const enabledSources = this.getEnabledSources().filter(s => s.searchable);
    const allResults: NovelSearchResult[] = [];
    const totalSources = enabledSources.length;
    
    logger.info(TAG, `分批搜索 "${keyword}"，共 ${totalSources} 个书源，每批 ${batchSize} 个`);

    // 分批处理
    for (let i = 0; i < totalSources; i += batchSize) {
      const batch = enabledSources.slice(i, Math.min(i + batchSize, totalSources));
      
      const promises = batch.map(async (sourceInfo) => {
        try {
          const results = await this.search(sourceInfo.id, keyword, page);
          return results;
        } catch (error) {
          logger.warn(TAG, `书源 ${sourceInfo.name} 搜索失败: ${String(error)}`);
          return [];
        }
      });

      const batchResults = await Promise.all(promises);
      for (const results of batchResults) {
        allResults.push(...results);
      }
      
      // 回调进度
      if (onProgress) {
        const completed = Math.min(i + batchSize, totalSources);
        onProgress(completed, totalSources, allResults);
      }
    }

    return allResults;
  }

  /**
   * 获取带完整 V2 handoff 的书籍详情。调用者必须消费或显式处理
   * FILE/unsupported/interaction 状态，不能只读取 book 字段。
   */
  async getBookInfoWithResult(
    sourceId: string,
    bookUrl: string,
    cancellationToken?: LegadoExecutionCancellationToken,
    bookVariable?: string,
    requestCarrierKey?: string
  ): Promise<LegadoWorkflowBookInfoResult> {
    cancellationToken?.throwIfCancelled();
    if (this.getEffectiveCompatibilityEngineMode(sourceId) === LegadoCompatibilityEngineMode.V2_ENABLED) {
      const v2Executor = this.getActiveV2Executor(sourceId);
      if (!v2Executor) {
        logger.warn(TAG, `V2 未就绪，拒绝获取书籍详情: ${sourceId}`);
        return new LegadoWorkflowBookInfoResult(null, [], null);
      }
      let v2Trace: LegadoExecutionTrace | null = null;
      try {
        logger.warn(TAG, `V2_BOOK_INFO_DISPATCH source=${sourceId};bookUrlLength=${bookUrl.length}`);
        const result = await this.awaitV2InteractiveWorkflow<LegadoWorkflowBookInfoResult>(
          LegadoWorkflowKind.BOOK_INFO,
          cancellationToken,
          async (workflowToken: LegadoExecutionCancellationToken): Promise<LegadoWorkflowBookInfoResult> => {
            const variable = bookVariable ||
              this.v2BookVariableSnapshots.get(this.getV2BookExecutionCarrierKey(sourceId, bookUrl)) ||
              v2Executor.getVariableSnapshot();
            const requestCarrier = this.resolveV2RequestCarrier(sourceId, bookUrl, requestCarrierKey);
            return await v2Executor.getBookInfoWithTrace(
              bookUrl,
              workflowToken,
              variable,
              requestCarrier?.requestUrlTemplate
            );
          }
        );
        v2Trace = result.trace;
        this.lastV2BookInfoResults.set(
          this.getV2BookExecutionCarrierKey(sourceId, bookUrl),
          result
        );
        cancellationToken?.throwIfCancelled();
        if (!this.isStructuredBookInfoHandoff(result)) {
          await this.recordV2TraceAndRequireSuccess(sourceId, v2Trace, cancellationToken);
        } else {
          await this.recordV2Trace(sourceId, v2Trace, cancellationToken);
        }
        cancellationToken?.throwIfCancelled();
        if (result.book !== null) {
          this.rememberV2BookVariableSnapshot(sourceId, bookUrl, result.book.variable);
          this.rememberV2BookRequestCarrier(
            sourceId,
            bookUrl,
            result.book.requestCarrier,
            result.book.requestUrlTemplate,
            result.book.requestCarrier?.originWorkflow || 'book_info'
          );
          if (result.book.bookUrl !== bookUrl) {
            this.rememberV2BookVariableSnapshot(sourceId, result.book.bookUrl, result.book.variable);
            this.rememberV2BookRequestCarrier(
              sourceId,
              result.book.bookUrl,
              result.book.requestCarrier,
              result.book.requestUrlTemplate,
              result.book.requestCarrier?.originWorkflow || 'book_info'
            );
          }
        }
        logger.warn(
          TAG,
          `V2_BOOK_INFO_RESULT source=${sourceId};present=${result.book !== null};` +
          `kind=${result.handoff.kind};status=${result.handoff.status};downloads=${result.downloadCandidates.length}`
        );
        return result;
      } catch (error) {
        cancellationToken?.throwIfCancelled();
        const executionError = new Error(String(error));
        if (this.isV2WorkflowTimeoutError(executionError)) {
          v2Trace = v2Executor.createWorkflowTimeoutTrace(
            LegadoWorkflowKind.BOOK_INFO,
            V2_INTERACTIVE_WORKFLOW_TIMEOUT_MS
          );
        } else if (v2Trace === null) {
          v2Trace = v2Executor.getLastTrace();
        }
        await this.recordV2Trace(sourceId, v2Trace);
        logger.warn(TAG, `V2 获取书籍详情失败: ${sourceId}, ${executionError.message}`);
        throw executionError;
      }
    }
    if (this.isV2FullCutoverBlocked(sourceId)) {
      this.logV2FullCutoverBlock(sourceId, LegadoWorkflowKind.BOOK_INFO);
      return new LegadoWorkflowBookInfoResult(null, [], null);
    }
    const executor = this.getExecutor(sourceId);
    if (!executor) {
      return new LegadoWorkflowBookInfoResult(null, [], null);
    }

    const book = await executor.getBookInfo(bookUrl);
    return new LegadoWorkflowBookInfoResult(book, book?.downloadUrls === undefined ? [] : this.toDownloadCandidates(book.downloadUrls), null);
  }

  /**
   * Legacy-shaped facade for existing reader pages. It is intentionally an
   * adapter over the typed result and rejects an unconsumed V2 handoff.
   */
  async getBookInfo(
    sourceId: string,
    bookUrl: string,
    cancellationToken?: LegadoExecutionCancellationToken,
    bookVariable?: string,
    requestCarrierKey?: string
  ): Promise<LegadoBook | null> {
    const result = await this.getBookInfoWithResult(
      sourceId,
      bookUrl,
      cancellationToken,
      bookVariable,
      requestCarrierKey
    );
    if (!result.handoff.isReady()) {
      throw new Error(
        `V2_OUTPUT_HANDOFF_BLOCKED;workflow=book_info;kind=${result.handoff.kind};` +
        `status=${result.handoff.status};reason=${result.handoff.reasonCode}`
      );
    }
    return result.book;
  }

  getLastBookInfoResult(sourceId: string, bookUrl: string): LegadoWorkflowBookInfoResult | null {
    return this.lastV2BookInfoResults.get(this.getV2BookExecutionCarrierKey(sourceId, bookUrl)) || null;
  }

  async getFileDownloadCandidates(
    sourceId: string,
    bookUrl: string,
    cancellationToken?: LegadoExecutionCancellationToken
  ): Promise<LegadoFileDownloadCandidate[]> {
    const result = await this.getBookInfoWithResult(sourceId, bookUrl, cancellationToken);
    if (result.handoff.kind !== LegadoWorkflowOutputKind.FILE || !result.handoff.isReady()) {
      throw new Error(
        `V2_OUTPUT_HANDOFF_BLOCKED;workflow=file;kind=${result.handoff.kind};` +
        `status=${result.handoff.status};reason=${result.handoff.reasonCode}`
      );
    }
    return result.handoff.downloadCandidates;
  }

  private isStructuredBookInfoHandoff(result: LegadoWorkflowBookInfoResult): boolean {
    if (result.handoff.status !== LegadoWorkflowHandoffStatus.READY) {
      return result.handoff.reasonCode === 'file_download_urls_empty' ||
        result.handoff.reasonCode === 'file_downloader_consumer_missing' ||
        result.handoff.reasonCode === 'book_info_js_contract_blocked';
    }
    return false;
  }

  private isStructuredHandoffStatus(status: LegadoWorkflowHandoffStatus): boolean {
    return status === LegadoWorkflowHandoffStatus.UNSUPPORTED_API ||
      status === LegadoWorkflowHandoffStatus.NEEDS_INTERACTION ||
      status === LegadoWorkflowHandoffStatus.POLICY_BLOCKED ||
      status === LegadoWorkflowHandoffStatus.MISSING_CONSUMER ||
      status === LegadoWorkflowHandoffStatus.INVALID_OUTPUT;
  }

  private toDownloadCandidates(urls: string[]): LegadoFileDownloadCandidate[] {
    const candidates: LegadoFileDownloadCandidate[] = [];
    for (let index = 0; index < urls.length; index++) {
      const url = urls[index].trim();
      if (url.length > 0) {
        candidates.push(new LegadoFileDownloadCandidate(url, `download-${index + 1}`));
      }
    }
    return candidates;
  }

  /**
   * 获取章节列表
   */
  async getChapterList(
    sourceId: string,
    book: LegadoBook,
    cancellationToken?: LegadoExecutionCancellationToken
  ): Promise<LegadoChapter[]> {
    cancellationToken?.throwIfCancelled();
    if (this.getEffectiveCompatibilityEngineMode(sourceId) === LegadoCompatibilityEngineMode.V2_ENABLED) {
      const v2Executor = this.getActiveV2Executor(sourceId);
      if (!v2Executor) {
        logger.warn(TAG, `V2 未就绪，拒绝获取目录: ${sourceId}`);
        return [];
      }
      let v2Trace: LegadoExecutionTrace | null = null;
      try {
        this.rememberV2BookVariableSnapshot(sourceId, book.bookUrl, book.variable);
        this.rememberV2BookRequestCarrier(
          sourceId,
          book.bookUrl,
          book.requestCarrier,
          book.requestUrlTemplate,
          book.requestCarrier?.originWorkflow || 'toc'
        );
        const result = await this.awaitV2InteractiveWorkflow<LegadoWorkflowTocResult>(
          LegadoWorkflowKind.TOC,
          cancellationToken,
          async (workflowToken: LegadoExecutionCancellationToken): Promise<LegadoWorkflowTocResult> => {
            return await v2Executor.getChapterListWithTrace(book, workflowToken);
          }
        );
        v2Trace = result.trace;
        cancellationToken?.throwIfCancelled();
        await this.recordV2TraceAndRequireSuccess(sourceId, v2Trace, cancellationToken);
        cancellationToken?.throwIfCancelled();
        return result.chapters;
      } catch (error) {
        cancellationToken?.throwIfCancelled();
        const executionError = new Error(String(error));
        if (this.isV2WorkflowTimeoutError(executionError)) {
          v2Trace = v2Executor.createWorkflowTimeoutTrace(
            LegadoWorkflowKind.TOC,
            V2_INTERACTIVE_WORKFLOW_TIMEOUT_MS
          );
        } else if (v2Trace === null) {
          v2Trace = v2Executor.getLastTrace();
        }
        await this.recordV2Trace(sourceId, v2Trace);
        logger.warn(TAG, `V2 获取目录失败: ${sourceId}, ${executionError.message}`);
        throw executionError;
      }
    }
    if (this.isV2FullCutoverBlocked(sourceId)) {
      this.logV2FullCutoverBlock(sourceId, LegadoWorkflowKind.TOC);
      return [];
    }
    const executor = this.getExecutor(sourceId);
    if (!executor) {
      return [];
    }

    return await executor.getChapterList(book);
  }

  /**
   * 获取带类型化 handoff 的章节输出。
   */
  async getContentWithResult(
    sourceId: string,
    chapter: LegadoChapter,
    cancellationToken?: LegadoExecutionCancellationToken
  ): Promise<LegadoWorkflowContentResult> {
    cancellationToken?.throwIfCancelled();
    if (this.getEffectiveCompatibilityEngineMode(sourceId) === LegadoCompatibilityEngineMode.V2_ENABLED) {
      const v2Executor = this.getActiveV2Executor(sourceId);
      if (!v2Executor) {
        logger.warn(TAG, `V2 未就绪，拒绝获取正文: ${sourceId}`);
        return new LegadoWorkflowContentResult('', chapter.title, null);
      }
      let v2Trace: LegadoExecutionTrace | null = null;
      try {
        const chapterForV2 = this.createV2ContentChapter(sourceId, chapter);
        const result = await this.awaitV2InteractiveWorkflow<LegadoWorkflowContentResult>(
          LegadoWorkflowKind.CONTENT,
          cancellationToken,
          async (workflowToken: LegadoExecutionCancellationToken): Promise<LegadoWorkflowContentResult> => {
            return await v2Executor.getContentWithTrace(chapterForV2, workflowToken);
          }
        );
        v2Trace = result.trace;
        this.lastV2ContentResults.set(
          `${sourceId}|${chapter.bookUrl}|${chapter.id}|${chapter.index}`,
          result
        );
        cancellationToken?.throwIfCancelled();
        if (this.isStructuredHandoffStatus(result.handoff.status)) {
          await this.recordV2Trace(sourceId, v2Trace, cancellationToken);
        } else {
          await this.recordV2TraceAndRequireSuccess(sourceId, v2Trace, cancellationToken);
        }
        cancellationToken?.throwIfCancelled();
        return result;
      } catch (error) {
        cancellationToken?.throwIfCancelled();
        const executionError = new Error(String(error));
        if (this.isV2WorkflowTimeoutError(executionError)) {
          v2Trace = v2Executor.createWorkflowTimeoutTrace(
            LegadoWorkflowKind.CONTENT,
            V2_INTERACTIVE_WORKFLOW_TIMEOUT_MS
          );
        } else if (v2Trace === null) {
          v2Trace = v2Executor.getLastTrace();
        }
        await this.recordV2Trace(sourceId, v2Trace);
        logger.warn(TAG, `V2 获取正文失败: ${sourceId}, ${executionError.message}`);
        throw executionError;
      }
    }
    if (this.isV2FullCutoverBlocked(sourceId)) {
      this.logV2FullCutoverBlock(sourceId, LegadoWorkflowKind.CONTENT);
      return new LegadoWorkflowContentResult('', chapter.title, null);
    }
    const executor = this.getExecutor(sourceId);
    if (!executor) {
      return new LegadoWorkflowContentResult('', chapter.title, null);
    }

    const content = await executor.getContent(chapter);
    return new LegadoWorkflowContentResult(content, chapter.title, null);
  }

  /** Legacy-shaped adapter. Typed consumers should call getContentWithResult. */
  async getContent(
    sourceId: string,
    chapter: LegadoChapter,
    cancellationToken?: LegadoExecutionCancellationToken
  ): Promise<string> {
    const result = await this.getContentWithResult(sourceId, chapter, cancellationToken);
    if (!result.handoff.isReady()) {
      throw new Error(
        `V2_OUTPUT_HANDOFF_BLOCKED;workflow=content;kind=${result.handoff.kind};` +
        `status=${result.handoff.status};reason=${result.handoff.reasonCode}`
      );
    }
    if (result.handoff.kind === LegadoWorkflowOutputKind.TEXT) {
      return result.handoff.textContent;
    }
    if (result.handoff.kind === LegadoWorkflowOutputKind.AUDIO) {
      return result.handoff.mediaUrl;
    }
    if (result.handoff.kind === LegadoWorkflowOutputKind.IMAGE) {
      return result.handoff.imageContent;
    }
    throw new Error(
      `V2_OUTPUT_HANDOFF_BLOCKED;workflow=content;kind=${result.handoff.kind};reason=file_content_consumer_missing`
    );
  }

  getLastContentResult(
    sourceId: string,
    chapter: LegadoChapter
  ): LegadoWorkflowContentResult | null {
    return this.lastV2ContentResults.get(`${sourceId}|${chapter.bookUrl}|${chapter.id}|${chapter.index}`) || null;
  }

  // ==================== 发现页功能 ====================

  /**
   * 获取支持发现功能的书源
   */
  getExploreSources(): NovelSourceInfo[] {
    return this.getAllSources().filter(s => s.hasExplore && s.enabled);
  }

  /**
   * 获取书源的发现分类
   */
  getExploreKinds(sourceId: string): LegadoExploreKind[] {
    if (this.getEffectiveCompatibilityEngineMode(sourceId) === LegadoCompatibilityEngineMode.V2_ENABLED) {
      const v2Executor = this.getActiveV2Executor(sourceId);
      if (!v2Executor) {
        logger.error(TAG, `V2_EXPLORE_EXECUTOR_MISSING sourceLength=${sourceId.length}`);
        throw new Error('V2_EXPLORE_EXECUTOR_MISSING');
      }
      return v2Executor.getExploreKinds();
    }
    if (this.isV2FullCutoverBlocked(sourceId)) {
      this.logV2FullCutoverBlock(sourceId, LegadoWorkflowKind.EXPLORE);
      return [];
    }
    const executor = this.getExecutor(sourceId);
    if (!executor) {
      return [];
    }
    return executor.getExploreKinds();
  }

  async getExploreKindsAsync(
    sourceId: string,
    cancellationToken?: LegadoExecutionCancellationToken
  ): Promise<LegadoExploreKind[]> {
    cancellationToken?.throwIfCancelled();
    if (this.getEffectiveCompatibilityEngineMode(sourceId) === LegadoCompatibilityEngineMode.V2_ENABLED) {
      const v2Executor = this.getActiveV2Executor(sourceId);
      if (!v2Executor) {
        logger.error(TAG, `V2_EXPLORE_EXECUTOR_MISSING sourceLength=${sourceId.length}`);
        throw new Error('V2_EXPLORE_EXECUTOR_MISSING');
      }
      try {
        const kinds = await v2Executor.getExploreKindsAsync(cancellationToken);
        cancellationToken?.throwIfCancelled();
        // Static explore kinds are compiled from the source document and do
        // not issue a request or script execution, so they intentionally have
        // no runtime trace. Dynamic kinds do create a trace and must persist it.
        if (v2Executor.getLastTrace() !== null) {
          await this.recordV2Trace(sourceId, v2Executor.getLastTrace(), cancellationToken);
        }
        cancellationToken?.throwIfCancelled();
        return kinds;
      } catch (error) {
        cancellationToken?.throwIfCancelled();
        if (v2Executor.getLastTrace() !== null) {
          await this.recordV2Trace(sourceId, v2Executor.getLastTrace());
        }
        logger.warn(TAG, `V2 获取发现分类失败: ${String(error)}`);
        throw new Error(String(error));
      }
    }
    if (this.isV2FullCutoverBlocked(sourceId)) {
      this.logV2FullCutoverBlock(sourceId, LegadoWorkflowKind.EXPLORE);
      return [];
    }
    const executor = this.getExecutor(sourceId);
    if (!executor) {
      return [];
    }
    return await executor.getExploreKindsAsync();
  }

  /**
   * 获取发现页书籍列表
   */
  async explore(
    sourceId: string,
    exploreUrl: string,
    page: number = 1,
    cancellationToken?: LegadoExecutionCancellationToken
  ): Promise<NovelSearchResult[]> {
    cancellationToken?.throwIfCancelled();
    const source = this.sources.get(sourceId);
    if (!source) {
      return [];
    }
    if (this.getEffectiveCompatibilityEngineMode(sourceId) === LegadoCompatibilityEngineMode.V2_ENABLED) {
      const v2Executor = this.getActiveV2Executor(sourceId);
      if (!v2Executor) {
        logger.warn(TAG, `V2 未就绪，拒绝获取发现页: ${sourceId}`);
        return [];
      }
      let v2Trace: LegadoExecutionTrace | null = null;
      try {
        const result = await v2Executor.exploreWithTrace(exploreUrl, page, cancellationToken);
        v2Trace = result.trace;
        cancellationToken?.throwIfCancelled();
        await this.recordV2TraceAndRequireSuccess(sourceId, v2Trace, cancellationToken);
        cancellationToken?.throwIfCancelled();
        return await this.mapSearchBooks(sourceId, source, result.books, undefined, cancellationToken);
      } catch (error) {
        cancellationToken?.throwIfCancelled();
        if (v2Trace === null) {
          v2Trace = v2Executor.getLastTrace();
        }
        await this.recordV2Trace(sourceId, v2Trace);
        logger.warn(TAG, `V2 获取发现页失败: ${sourceId}, ${String(error)}`);
        throw new Error(String(error));
      }
    }
    if (this.isV2FullCutoverBlocked(sourceId)) {
      this.logV2FullCutoverBlock(sourceId, LegadoWorkflowKind.EXPLORE);
      return [];
    }
    const executor = this.getExecutor(sourceId);
    if (!executor) {
      return [];
    }

    const results = await executor.explore(exploreUrl, page);
    this.scheduleShadowExplore(sourceId, exploreUrl, page);
    return await this.mapSearchBooks(sourceId, source, results);
  }

  /**
   * 获取书源数量
   */
  getSourceCount(): number {
    return this.sources.size;
  }

  /**
   * 清除所有书源（同时清除数据库）
   */
  async clearAll(): Promise<void> {
    // 从数据库删除所有书源
    try {
      const dataManager = getNovelDataManager();
      const allSources = this.getAllSources();
      for (const source of allSources) {
        const fullSource = this.sources.get(source.id) || null;
        await dataManager.deleteSource(source.id);
        if (fullSource) {
          await this.disableLegadoImageVirtualSource(fullSource);
        }
      }
    } catch (error) {
      logger.warn(TAG, `清除数据库书源失败: ${String(error)}`);
    }
    
    this.sources.clear();
    this.executors.clear();
    this.compiledSources.clear();
    this.v2Executors.clear();
    this.compatibilityModes.clear();
    this.compatibilityStatuses.clear();
    this.verificationRecords.clear();
    this.lastExecutionTraces.clear();
    this.lastExecutionTraceSummaries.clear();
    this.executionTraceWorkflowSummaries.clear();
    logger.info(TAG, '已清除所有书源');
  }
  
  /**
   * 从数据库加载书源到内存（仅内部使用）
   * 注意：这个方法不会持久化，用于初始化时加载
   */
  loadSourceToMemory(source: LegadoBookSource): void {
    this.sources.set(source.bookSourceUrl, source);
    this.executors.delete(source.bookSourceUrl);
    this.compiledSources.delete(source.bookSourceUrl);
    this.v2Executors.delete(source.bookSourceUrl);
    this.verificationRecords.delete(source.bookSourceUrl);
    this.lastExecutionTraces.delete(source.bookSourceUrl);
    this.lastExecutionTraceSummaries.delete(source.bookSourceUrl);
    this.executionTraceWorkflowSummaries.delete(source.bookSourceUrl);
    this.compatibilityStatuses.set(source.bookSourceUrl, LegadoCompatibilityStatus.LEGACY_UNVERIFIABLE);
    this.compatibilityModes.set(source.bookSourceUrl, LegadoCompatibilityEngineMode.LEGACY);
  }

  // ==================== 大文件流式导入 ====================

  /**
   * 从大文件流式导入书源
   * 适用于50M~100M+的大型书源JSON文件
   * 
   * @param filePath 文件路径
   * @param progress 进度回调
   * @returns 导入结果
   */
  async importFromLargeFile(
    filePath: string,
    progress?: LargeFileImportProgress
  ): Promise<LargeFileImportResult> {
    const startTime = Date.now();
    const result: LargeFileImportResult = {
      success: false,
      totalParsed: 0,
      successCount: 0,
      failedCount: 0,
      skippedCount: 0,
      errors: [],
      elapsedMs: 0
    };

    try {
      logger.info(TAG, `开始大文件流式导入: ${filePath}`);
      progress?.onStageChange?.('reading');

      // 配置解析器
      const parseConfig: ParseConfig = {
        chunkSize: 512 * 1024,    // 512KB 每次读取
        batchSize: 100,            // 每批100个对象
        batchDelayMs: 5,           // 5ms 让出主线程
        maxObjectSize: 8 * 1024 * 1024  // 单个书源最大8MB，保留实际原始文档
      };

      const compiler = new LegadoCompatibilityCompiler();
      let totalImportedCandidates = 0;
      let importStageReported = false;

      // 解析回调
      const parseCallback: ParseProgressCallback = {
        onFileProgress: (bytesRead, totalBytes) => {
          const percent = Math.round((bytesRead / totalBytes) * 100);
          progress?.onFileReadProgress?.(percent, bytesRead, totalBytes);
        },
        onDocumentParsed: async (parsedCount: number, rawDocument: string): Promise<void> => {
          const compiled = await compiler.compileOne(rawDocument);
          if (compiled === null) {
            result.skippedCount++;
            progress?.onParseProgress?.(parsedCount, '无法识别的书源文档');
            return;
          }

          progress?.onParseProgress?.(parsedCount, compiled.source.bookSourceName);
          if (!importStageReported) {
            importStageReported = true;
            progress?.onStageChange?.('importing');
          }
          totalImportedCandidates++;
          const importResult = await this.importCompiledSource(compiled, true);
          if (importResult.success) {
            result.successCount++;
          } else {
            result.failedCount++;
            const errorMessage = importResult.error || '未知的 V2 无损导入失败';
            result.errors.push(`${compiled.source.bookSourceName}: ${errorMessage}`);
            progress?.onError?.(errorMessage, compiled.source.bookSourceName);
          }
          progress?.onImportProgress?.(
            result.successCount + result.failedCount,
            0,
            compiled.source.bookSourceName
          );
        },
        onBatchComplete: (batchIndex, batchSize, totalParsed) => {
          logger.debug(TAG, `解析批次 ${batchIndex} 完成, 批次大小: ${batchSize}, 总计: ${totalParsed}`);
        },
        onError: (error, recoverable) => {
          result.errors.push(error);
          progress?.onError?.(error);
        }
      };

      // 流式解析文件
      progress?.onStageChange?.('parsing');
      const parseResult = await LargeFileJSONParser.parseFile(
        filePath,
        parseConfig,
        parseCallback
      );

      result.totalParsed = parseResult.totalParsed;
      if (!parseResult.success) {
        const parseError = parseResult.errors.length > 0 ? parseResult.errors[0] : '书源文件解析失败';
        throw new Error(parseError);
      }
      logger.info(
        TAG,
        `流式 V2 导入完成: parsed=${result.totalParsed}, candidates=${totalImportedCandidates}, skipped=${result.skippedCount}`
      );

      // A final update may use the actual parsed count. During scanning it is
      // deliberately unknown so pages cannot display a fabricated 100% value.
      progress?.onImportProgress?.(
        result.successCount + result.failedCount,
        result.totalParsed,
        ''
      );

      // `success` means the file pipeline completed and persisted at least one
      // document. Per-document failures remain visible in failedCount/errors;
      // callers must not collapse this into an "all sources are usable" claim.
      result.success = result.successCount > 0;
      progress?.onStageChange?.('complete');
      
      logger.info(TAG, `大文件导入完成: 成功 ${result.successCount}, 失败 ${result.failedCount}, 跳过 ${result.skippedCount}`);

    } catch (error) {
      const errorMsg = `大文件导入失败: ${String(error)}`;
      logger.error(TAG, errorMsg);
      result.errors.push(errorMsg);
      progress?.onError?.(errorMsg);
    }

    result.elapsedMs = Date.now() - startTime;
    return result;
  }

  /**
   * 休眠指定毫秒
   */
  private sleep(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  /**
   * 检查文件是否为大文件（超过阈值则建议使用流式导入）
   * @param filePath 文件路径
   * @param thresholdMB 阈值（MB），默认5MB
   * @returns 是否为大文件
   */
  static isLargeFile(filePath: string, thresholdMB: number = 5): boolean {
    try {
      const stat = SafeFileUtils.statSync(filePath);
      return stat.size > thresholdMB * 1024 * 1024;
    } catch (error) {
      logger.warn(TAG, `检查文件大小失败: ${String(error)}`);
      return false;
    }
  }

  /**
   * 获取文件大小（字节）
   */
  static getFileSize(filePath: string): number {
    try {
      const stat = SafeFileUtils.statSync(filePath);
      return stat.size;
    } catch (error) {
      logger.warn(TAG, `获取文件大小失败: ${String(error)}`);
      return 0;
    }
  }

  /**
   * 格式化文件大小
   */
  static formatFileSize(bytes: number): string {
    if (bytes < 1024) {
      return `${bytes}B`;
    } else if (bytes < 1024 * 1024) {
      return `${(bytes / 1024).toFixed(1)}KB`;
    } else if (bytes < 1024 * 1024 * 1024) {
      return `${(bytes / 1024 / 1024).toFixed(1)}MB`;
    } else {
      return `${(bytes / 1024 / 1024 / 1024).toFixed(2)}GB`;
    }
  }

  /**
   * 导出所有书源为JSON
   */
  exportToJSON(): string {
    const sources: LegadoBookSource[] = [];
    this.sources.forEach(source => {
      sources.push(source);
    });
    return JSON.stringify(sources, null, 2);
  }

  // ==================== 分组管理功能 ====================

  /**
   * 更新书源分组
   */
  async updateSourceGroup(sourceId: string, group: string): Promise<boolean> {
    const source = this.sources.get(sourceId);
    if (!source) {
      return false;
    }
    
    source.bookSourceGroup = group;
    
    // 更新数据库
    try {
      const dataManager = getNovelDataManager();
      await dataManager.saveSource(source);
      logger.debug(TAG, `更新书源分组: ${source.bookSourceName} -> ${group}`);
      return true;
    } catch (error) {
      logger.warn(TAG, `更新书源分组失败: ${String(error)}`);
      return false;
    }
  }

  /**
   * 更新书源响应时间
   */
  async updateSourceRespondTime(sourceId: string, respondTime: number): Promise<boolean> {
    const source = this.sources.get(sourceId);
    if (!source) {
      return false;
    }
    
    source.respondTime = respondTime;
    
    // 更新数据库
    try {
      const dataManager = getNovelDataManager();
      await dataManager.saveSource(source);
      return true;
    } catch (error) {
      logger.warn(TAG, `更新书源响应时间失败: ${String(error)}`);
      return false;
    }
  }

  /**
   * 批量添加书源到分组
   */
  async addSourcesToGroup(sourceIds: string[], groupName: string): Promise<number> {
    let successCount = 0;
    
    for (const sourceId of sourceIds) {
      const source = this.sources.get(sourceId);
      if (!source) continue;
      
      // 获取当前分组
      const currentGroups = source.bookSourceGroup 
        ? source.bookSourceGroup.split(',').map(g => g.trim()).filter(g => g.length > 0)
        : [];
      
      // 如果已经在该分组中，跳过
      if (currentGroups.includes(groupName)) {
        successCount++;
        continue;
      }
      
      // 添加新分组
      currentGroups.push(groupName);
      const newGroupStr = currentGroups.join(',');
      
      if (await this.updateSourceGroup(sourceId, newGroupStr)) {
        successCount++;
      }
    }
    
    logger.info(TAG, `批量添加到分组 "${groupName}": ${successCount}/${sourceIds.length}`);
    return successCount;
  }

  /**
   * 批量从分组移除书源
   */
  async removeSourcesFromGroup(sourceIds: string[], groupName: string): Promise<number> {
    let successCount = 0;
    
    for (const sourceId of sourceIds) {
      const source = this.sources.get(sourceId);
      if (!source) continue;
      
      // 获取当前分组
      const currentGroups = source.bookSourceGroup 
        ? source.bookSourceGroup.split(',').map(g => g.trim()).filter(g => g.length > 0)
        : [];
      
      // 移除指定分组
      const newGroups = currentGroups.filter(g => g !== groupName);
      
      // 如果分组没有变化，跳过
      if (newGroups.length === currentGroups.length) {
        continue;
      }
      
      const newGroupStr = newGroups.join(',');
      
      if (await this.updateSourceGroup(sourceId, newGroupStr)) {
        successCount++;
      }
    }
    
    logger.info(TAG, `批量从分组 "${groupName}" 移除: ${successCount}/${sourceIds.length}`);
    return successCount;
  }

  /**
   * 获取所有分组名称
   */
  getAllGroups(): string[] {
    const groupSet = new Set<string>();
    
    this.sources.forEach(source => {
      if (source.bookSourceGroup) {
        const groups = source.bookSourceGroup.split(',').map(g => g.trim()).filter(g => g.length > 0);
        groups.forEach(g => groupSet.add(g));
      }
    });
    
    return Array.from(groupSet).sort();
  }

  /**
   * 获取分组内的书源
   */
  getSourcesByGroup(groupName: string): NovelSourceInfo[] {
    return this.getAllSources().filter(s => {
      if (!s.group) return false;
      const groups = s.group.split(',').map(g => g.trim());
      return groups.includes(groupName);
    });
  }

  /**
   * 获取无分组的书源
   */
  getSourcesWithoutGroup(): NovelSourceInfo[] {
    return this.getAllSources().filter(s => !s.group || s.group.trim().length === 0);
  }

  /**
   * 重命名分组
   */
  async renameGroup(oldName: string, newName: string): Promise<number> {
    let successCount = 0;
    const sourcesInGroup = this.getSourcesByGroup(oldName);
    
    for (const sourceInfo of sourcesInGroup) {
      const source = this.sources.get(sourceInfo.id);
      if (!source || !source.bookSourceGroup) continue;
      
      const groups = source.bookSourceGroup.split(',').map(g => g.trim());
      const newGroups = groups.map(g => g === oldName ? newName : g);
      const newGroupStr = newGroups.join(',');
      
      if (await this.updateSourceGroup(sourceInfo.id, newGroupStr)) {
        successCount++;
      }
    }
    
    logger.info(TAG, `重命名分组 "${oldName}" -> "${newName}": ${successCount} 个书源`);
    return successCount;
  }

  /**
   * 删除分组（仅移除分组标签，不删除书源）
   */
  async deleteGroup(groupName: string): Promise<number> {
    return this.removeSourcesFromGroup(
      this.getSourcesByGroup(groupName).map(s => s.id),
      groupName
    );
  }

  /**
   * 设置书源权重（用于置顶）
   */
  async setSourceWeight(sourceId: string, weight: number): Promise<boolean> {
    const source = this.sources.get(sourceId);
    if (!source) {
      return false;
    }
    
    source.weight = weight;
    
    try {
      const dataManager = getNovelDataManager();
      await dataManager.saveSource(source);
      logger.debug(TAG, `设置书源权重: ${source.bookSourceName} -> ${weight}`);
      return true;
    } catch (error) {
      logger.warn(TAG, `设置书源权重失败: ${String(error)}`);
      return false;
    }
  }

  /**
   * 设置书源自定义排序
   * @param sourceId 书源ID
   * @param order 排序顺序（越小越靠前）
   */
  async setSourceCustomOrder(sourceId: string, order: number): Promise<boolean> {
    const source = this.sources.get(sourceId);
    if (!source) {
      return false;
    }
    
    source.customOrder = order;
    
    try {
      const dataManager = getNovelDataManager();
      await dataManager.saveSource(source);
      logger.debug(TAG, `设置书源排序: ${source.bookSourceName} -> ${order}`);
      return true;
    } catch (error) {
      logger.warn(TAG, `设置书源排序失败: ${String(error)}`);
      return false;
    }
  }

  /**
   * 批量更新书源排序
   * 将传入的书源ID列表按顺序设置 customOrder
   * @param sourceIds 按顺序排列的书源ID列表
   */
  async batchUpdateSourceOrder(sourceIds: string[]): Promise<number> {
    let successCount = 0;
    
    for (let i = 0; i < sourceIds.length; i++) {
      const sourceId = sourceIds[i];
      const source = this.sources.get(sourceId);
      if (!source) continue;
      
      // 只为启用的书源设置排序
      if (source.enabled !== false) {
        source.customOrder = i;
        try {
          const dataManager = getNovelDataManager();
          await dataManager.saveSource(source);
          successCount++;
        } catch (error) {
          logger.warn(TAG, `更新书源排序失败: ${source.bookSourceName}, ${String(error)}`);
        }
      }
    }
    
    logger.info(TAG, `批量更新书源排序完成: ${successCount}/${sourceIds.length}`);
    return successCount;
  }

  /**
   * 批量置顶书源
   */
  async topSources(sourceIds: string[]): Promise<number> {
    // 获取当前最小的 customOrder
    let minOrder = 0;
    this.sources.forEach(source => {
      if (source.enabled !== false && source.customOrder !== undefined && source.customOrder < minOrder) {
        minOrder = source.customOrder;
      }
    });
    
    let successCount = 0;
    // 从最小值开始向前分配
    for (let i = 0; i < sourceIds.length; i++) {
      const newOrder = minOrder - sourceIds.length + i;
      if (await this.setSourceCustomOrder(sourceIds[i], newOrder)) {
        successCount++;
      }
    }
    
    logger.info(TAG, `批量置顶: ${successCount}/${sourceIds.length}`);
    return successCount;
  }

  /**
   * 批量置底书源
   */
  async bottomSources(sourceIds: string[]): Promise<number> {
    // 获取当前最大的 customOrder
    let maxOrder = 0;
    this.sources.forEach(source => {
      if (source.enabled !== false && source.customOrder !== undefined && source.customOrder > maxOrder) {
        maxOrder = source.customOrder;
      }
    });
    
    let successCount = 0;
    // 从最大值开始向后分配
    for (let i = 0; i < sourceIds.length; i++) {
      const newOrder = maxOrder + i + 1;
      if (await this.setSourceCustomOrder(sourceIds[i], newOrder)) {
        successCount++;
      }
    }
    
    logger.info(TAG, `批量置底: ${successCount}/${sourceIds.length}`);
    return successCount;
  }

  /**
   * 移动书源到指定位置
   * @param sourceId 要移动的书源ID
   * @param targetIndex 目标位置索引
   */
  async moveSource(sourceId: string, targetIndex: number): Promise<boolean> {
    const source = this.sources.get(sourceId);
    if (!source || source.enabled === false) {
      return false;
    }
    
    // 获取当前启用的书源列表（按 customOrder 排序）
    const enabledSources = this.getAllSources().filter(s => s.enabled);
    const currentIndex = enabledSources.findIndex(s => s.id === sourceId);
    
    if (currentIndex === -1 || targetIndex < 0 || targetIndex >= enabledSources.length) {
      return false;
    }
    
    // 从当前位置移除
    enabledSources.splice(currentIndex, 1);
    // 插入到目标位置
    const movedSource = this.getAllSources().find(s => s.id === sourceId)!;
    enabledSources.splice(targetIndex, 0, movedSource);
    
    // 更新所有书源的 customOrder
    const sourceIdsInOrder = enabledSources.map(s => s.id);
    await this.batchUpdateSourceOrder(sourceIdsInOrder);
    
    return true;
  }
}

/**
 * 获取小说源管理器实例
 */
export function getNovelSourceManager(): NovelSourceManager {
  return NovelSourceManager.getInstance();
}
