import { logger } from '../../Utils/Logger';
import { sha256Hash } from '../../Utils/CryptoUtils';
import { SafeUtils } from '../../Utils/SafeUtils';
import {
  LegadoRuleAnalyzer,
  LegadoRuleElementDiagnostic,
  LegadoRuleJsExecutionBinding
} from './LegadoRuleAnalyzer';
import { LegadoUrlAnalyzer } from './LegadoUrlAnalyzer';
import {
  LegadoBook,
  LegadoBookInfoRule,
  LegadoBookSourceType,
  LegadoChapter,
  LegadoContentRule,
  LegadoExploreKind,
  LegadoExploreRule,
  LegadoRequestCarrier,
  LegadoSearchRule,
  LegadoSearchBook
} from './LegadoSourceTypes';
import {
  CompiledBookSource,
  LegadoBridgeTrace,
  LegadoExecutionErrorCode,
  LegadoExecutionTrace,
  LegadoFinalUrlObservation,
  LegadoFileDownloadCandidate,
  LegadoAuxiliaryRuleOutcome,
  LegadoJsApiStatus,
  LegadoRequestDisposition,
  LegadoRequestHeader,
  LegadoRequestOptionTrace,
  LegadoResponseHeader,
  LegadoSearchExecutionOptions,
  LegadoWorkflowBookInfoResult,
  LegadoWorkflowContentResult,
  LegadoWorkflowHandoffStatus,
  LegadoWorkflowKind,
  LegadoWorkflowOutput,
  LegadoWorkflowOutputKind,
  LegadoWorkflowSearchResult,
  LegadoWorkflowTocResult,
  LegadoTransportKind,
  RequestSpec,
  ResponseEnvelope
} from './LegadoCompatibilityTypes';
import { LegadoRequestPlanner, LegadoTransportRouter } from './LegadoRequestPipeline';
import { getLegadoJsApiContractRegistry, LegadoJsApiAssessment } from './LegadoJsApiContractRegistry';
import {
  LegadoContentPresentationStatus,
  LegadoContentSemantics
} from './LegadoContentSemantics';
import { LegadoSourceParser } from './LegadoSourceParser';
import { getLegadoJsEngine, JsContext } from './LegadoJsEngine';
import {
  LegadoSourceScriptResult,
  LegadoSourceScriptRuntime,
  LegadoSourceScriptRuntimeBase
} from './LegadoSourceScriptRuntime';
import { LegadoExecutionCancellationToken } from './LegadoExecutionCancellation';

const TAG = 'LegadoWorkflowOrchestrator';
const MAX_PAGINATION_DEPTH = 8;

class LegadoBookInfoDiagnostic {
  readonly declaredRuleCount: number;
  readonly resolvedRuleCount: number;
  readonly summary: string;

  constructor(declaredRuleCount: number, resolvedRuleCount: number, summary: string) {
    this.declaredRuleCount = declaredRuleCount;
    this.resolvedRuleCount = resolvedRuleCount;
    this.summary = summary;
  }
}

/**
 * The original Legado discovery workflow treats an empty `ruleExplore.bookList`
 * as an instruction to reuse the complete search list rule.  Keep the chosen
 * rule and its provenance together so the execution trace can prove which
 * semantic branch was used.
 */
class LegadoExploreRuleResolution {
  readonly rule: LegadoExploreRule;
  readonly usesSearchRuleFallback: boolean;

  constructor(rule: LegadoExploreRule, usesSearchRuleFallback: boolean) {
    this.rule = rule;
    this.usesSearchRuleFallback = usesSearchRuleFallback;
  }
}

/**
 * Original Legado treats a single next-toc URL as a linear chain, but treats
 * multiple URLs found on the same page as a bounded fan-out.  Preserve that
 * distinction so a pagination selector cannot silently lose sibling pages.
 */
class LegadoTocPageRequest {
  readonly url: string;
  readonly mayDiscoverNextPages: boolean;

  constructor(url: string, mayDiscoverNextPages: boolean) {
    this.url = url;
    this.mayDiscoverNextPages = mayDiscoverNextPages;
  }
}

/**
 * V2 workflow owner. The legacy executor remains untouched and is selected
 * through the source feature flag until a source has passed conformance gates.
 */
export class LegadoWorkflowOrchestrator {
  private readonly compiled: CompiledBookSource;
  private readonly planner: LegadoRequestPlanner;
  private readonly router: LegadoTransportRouter;
  private readonly sourceScriptRuntime: LegadoSourceScriptRuntimeBase;
  private lastTrace: LegadoExecutionTrace | null = null;
  private activeWorkflowTraceId: string = '';
  private lastWorkflowVariableSnapshot: string = '';

  constructor(compiled: CompiledBookSource, sourceScriptRuntime?: LegadoSourceScriptRuntimeBase) {
    this.compiled = compiled;
    this.planner = new LegadoRequestPlanner(compiled);
    this.router = new LegadoTransportRouter();
    this.sourceScriptRuntime = sourceScriptRuntime || new LegadoSourceScriptRuntime();
  }

  getLastTrace(): LegadoExecutionTrace | null {
    return this.lastTrace;
  }

  /**
   * Emits a redacted projection of the exact compiled source used for Explore.
   * This is the minimum identity evidence needed to distinguish parser/storage
   * loss from a UI or transport failure without logging source URLs or rules.
   */
  private logExploreKindsProjection(mode: string, kindCount: number): void {
    const rawSha256Prefix: string = this.compiled.raw.sha256.substring(0, 16);
    const exploreUrlLength: number = (this.compiled.source.exploreUrl || '').length;
    const ruleExploreBookListPresent: boolean = (this.compiled.source.ruleExplore?.bookList || '').trim().length > 0;
    logger.warn(
      TAG,
      `V2_EXPLORE_KINDS_PROJECTION rawSha256Prefix=${rawSha256Prefix};` +
      `sourceType=${this.compiled.actualSourceType};exploreUrlLength=${exploreUrlLength};` +
      `ruleExploreBookListPresent=${ruleExploreBookListPresent};kindCount=${kindCount};mode=${mode}`
    );
  }

  /**
   * Creates a terminal, redaction-safe trace when a caller-owned workflow
   * deadline fires before the request or rule evaluation returns. The target
   * is intentionally omitted: persisted summaries must not retain URLs.
   */
  createWorkflowTimeoutTrace(workflow: LegadoWorkflowKind, timeoutMs: number): LegadoExecutionTrace {
    const traceId = `${this.compiled.source.bookSourceUrl}|${workflow}|timeout|${Date.now()}`;
    const previousTrace = this.lastTrace;
    const preservedBridgeTraces: LegadoBridgeTrace[] = previousTrace !== null &&
      previousTrace.workflow === workflow &&
      this.activeWorkflowTraceId.length > 0 &&
      previousTrace.traceId === this.activeWorkflowTraceId
      ? previousTrace.bridgeTraces.slice()
      : [];
    const request = new RequestSpec(
      traceId,
      this.compiled.source.bookSourceUrl,
      workflow,
      '',
      'GET',
      '',
      [],
      '',
      0,
      this.compiled.source.concurrentRate || '',
      this.compiled.source.enabledCookieJar === true,
      false,
      '',
      '',
      0,
      0,
      '',
      'not_sent',
      []
    );
    const response = new ResponseEnvelope(
      traceId,
      '',
      '',
      LegadoFinalUrlObservation.UNOBSERVABLE,
      0,
      [],
      [],
      false,
      [],
      LegadoTransportKind.HTTP,
      Math.max(0, timeoutMs),
      LegadoExecutionErrorCode.CANCELLED,
      `V2_WORKFLOW_TIMEOUT:${workflow}`
    );
    const trace = new LegadoExecutionTrace(
      traceId,
      this.compiled.source.bookSourceUrl,
      workflow,
      request,
      response,
      [],
      `workflow_timeout:${workflow};timeoutMs=${Math.max(0, timeoutMs)};bridgeTraces=${preservedBridgeTraces.length}`,
      preservedBridgeTraces
    );
    this.lastTrace = trace;
    return trace;
  }

  private blockForJsContracts(
    workflow: LegadoWorkflowKind,
    template: string,
    assessment: LegadoJsApiAssessment
  ): boolean {
    if (!assessment.hasBlockingContract || assessment.blockingStatus === null) {
      return false;
    }
    let code = LegadoExecutionErrorCode.UNSUPPORTED_API;
    if (assessment.blockingStatus === LegadoJsApiStatus.NEEDS_INTERACTION) {
      code = LegadoExecutionErrorCode.NEEDS_INTERACTION;
    } else if (assessment.blockingStatus === LegadoJsApiStatus.POLICY_BLOCKED) {
      code = LegadoExecutionErrorCode.POLICY_BLOCKED;
    }
    const apiNames: string[] = [];
    for (let i = 0; i < assessment.contracts.length; i++) {
      const contract = assessment.contracts[i];
      if (contract.status !== LegadoJsApiStatus.SUPPORTED) {
        apiNames.push(contract.api);
      }
    }
    const traceId = `${this.compiled.source.bookSourceUrl}|${workflow}|blocked|${Date.now()}`;
    const request = new RequestSpec(
      traceId,
      this.compiled.source.bookSourceUrl,
      workflow,
      template,
      'GET',
      '',
      [],
      '',
      0,
      this.compiled.source.concurrentRate || '',
      false,
      false,
      '',
      '',
      0,
      0,
      '',
      'not_sent',
      [new LegadoRequestOptionTrace('js_api', LegadoRequestDisposition.UNSUPPORTED, apiNames.join(','))]
    );
    const response = new ResponseEnvelope(
      traceId,
      '',
      template,
      LegadoFinalUrlObservation.UNOBSERVABLE,
      0,
      [],
      [],
      false,
      [template],
      LegadoTransportKind.HTTP,
      0,
      code,
      `JS_CONTRACT:${apiNames.join(',')}`
    );
    this.lastTrace = new LegadoExecutionTrace(
      traceId,
      this.compiled.source.bookSourceUrl,
      workflow,
      request,
      response,
      [],
      `blocked:${code}`
    );
    return true;
  }

  async search(
    keyword: string,
    page: number = 1,
    cancellationToken?: LegadoExecutionCancellationToken,
    executionOptions?: LegadoSearchExecutionOptions
  ): Promise<LegadoWorkflowSearchResult> {
    cancellationToken?.throwIfCancelled();
    const template = this.compiled.source.searchUrl || '';
    try {
      if (template.length === 0) {
        return new LegadoWorkflowSearchResult([], null);
      }
      const rule = this.compiled.source.ruleSearch;
      if (!rule || !rule.bookList) {
        return new LegadoWorkflowSearchResult([], this.lastTrace);
      }
      const assessment = getLegadoJsApiContractRegistry().assess(
        `${template}\n${rule.bookList}\n${rule.bookUrl}\n${rule.name}\n${rule.author}\n${rule.kind}\n${rule.intro}\n${rule.coverUrl}\n${rule.lastChapter}\n${rule.wordCount}`
      );
      if (this.blockForJsContracts(LegadoWorkflowKind.SEARCH, template, assessment)) {
        return new LegadoWorkflowSearchResult([], this.lastTrace);
      }
      cancellationToken?.throwIfCancelled();
      const response = await this.execute(
        LegadoWorkflowKind.SEARCH,
        template,
        keyword,
        page,
        '',
        '',
        cancellationToken
      );
      if (await this.blockProtectedResponse(LegadoWorkflowKind.SEARCH, response)) {
        return new LegadoWorkflowSearchResult([], this.lastTrace);
      }
      if (!response.hasRuleReadableBody()) {
        // A failed transport is still a completed V2 search workflow. Keep a
        // workflow-level, value-free summary so management UI and device
        // evidence never present an empty diagnostic field.
        this.refreshTraceOutput(this.getSearchFailureSummary(response));
        return new LegadoWorkflowSearchResult([], this.lastTrace);
      }
      this.lastWorkflowVariableSnapshot = this.serializeVariableSnapshotFromPlanner();
      logger.warnForEvidence(TAG, 'V2_STAGE:search_analyzer_create_begin');
      const analyzer = this.createAnalyzer(response.body, response.finalUrl, undefined, undefined, keyword, page);
      logger.warnForEvidence(TAG, 'V2_STAGE:search_analyzer_create_returned');
      logger.warnForEvidence(TAG, 'V2_STAGE:search_book_list_begin');
      // BookList removes one leading ordering marker before rule evaluation:
      // '-' reverses the final de-duplicated list and '+' is an explicit
      // forward-order marker. Passing either marker into the selector changes
      // CSS parsing instead of reproducing original Legado semantics.
      let bookListRule: string = rule.bookList;
      let reverseBookList: boolean = false;
      if (bookListRule.startsWith('-')) {
        reverseBookList = true;
        bookListRule = bookListRule.substring(1);
      }
      if (bookListRule.startsWith('+')) {
        bookListRule = bookListRule.substring(1);
      }
      const elementDiagnostic: LegadoRuleElementDiagnostic =
        await analyzer.getElementsWithPureCssIndexDiagnosticsAsync(bookListRule);
      const elements: string[] = elementDiagnostic.elements;
      logger.warnForEvidence(TAG, 'V2_STAGE:search_book_list_returned');
      cancellationToken?.throwIfCancelled();
      const books: LegadoSearchBook[] = [];
      let emptyBookUrlCount: number = 0;
      let bookUrlJsResultCount: number = 0;
      let bookUrlJsEmptyCount: number = 0;
      let bookUrlJsErrorCount: number = 0;
      let bookUrlJsRuntimeUnavailableCount: number = 0;
      let bookUrlJsNotEvaluatedCount: number = 0;
      let bookUrlJsMainRuleEmptyCount: number = 0;
      let bookUrlJsInputJsonCount: number = 0;
      const bookUrlUsesJs: boolean = this.ruleUsesJavaScript(rule.bookUrl);
      const maxResults = executionOptions?.hasResultBudget() ? executionOptions.maxResults : Number.MAX_SAFE_INTEGER;
      for (let i = 0; i < elements.length && books.length < maxResults; i++) {
        cancellationToken?.throwIfCancelled();
        // A source may return thousands of candidates. A UI-owned budget
        // delivers only the requested prefix, while unbudgeted conformance
        // execution remains complete. Yield between records so either path
        // does not block ArkUI long enough for THREAD_BLOCK_6S.
        if (i > 0 && i % 4 === 0) {
          await this.yieldToEventLoop();
          cancellationToken?.throwIfCancelled();
        }
        const item = this.createAnalyzer(elements[i], response.finalUrl, undefined, undefined, keyword, page);
        const name = await item.getStringAsync(rule.name);
        if (name.trim().length === 0) {
          continue;
        }
        const bookUrl = await item.getUrlStringAsync(rule.bookUrl);
        if (bookUrlUsesJs) {
          if (item.isJsonContent()) {
            bookUrlJsInputJsonCount++;
          }
          const jsStatus = item.getLastJsExecutionStatus();
          if (jsStatus === 'result') {
            bookUrlJsResultCount++;
          } else if (jsStatus === 'empty') {
            bookUrlJsEmptyCount++;
          } else if (jsStatus === 'main_rule_empty') {
            bookUrlJsMainRuleEmptyCount++;
          } else if (jsStatus === 'error_webview_not_ready') {
            bookUrlJsRuntimeUnavailableCount++;
          } else if (jsStatus.startsWith('error_')) {
            bookUrlJsErrorCount++;
          } else {
            bookUrlJsNotEvaluatedCount++;
          }
        }
        let resolvedBookUrl = this.resolveUrl(bookUrl, response.finalUrl);
        let requestUrlTemplate = this.resolveRequestUrlTemplate(bookUrl, response.finalUrl);
        if (resolvedBookUrl.length <= 0) {
          emptyBookUrlCount++;
          // AnalyzeRule.getString(..., isUrl = true) returns its base URL for
          // a blank detail rule. Here baseUrl is the effective Search response
          // URL, not the source root URL.
          resolvedBookUrl = response.finalUrl;
          requestUrlTemplate = response.finalUrl;
        }
        books.push({
          origin: this.compiled.source.bookSourceUrl,
          originName: this.compiled.source.bookSourceName,
          bookUrl: resolvedBookUrl,
          requestUrlTemplate: requestUrlTemplate,
          requestCarrier: new LegadoRequestCarrier(
            this.compiled.source.bookSourceUrl,
            resolvedBookUrl,
            requestUrlTemplate,
            'search'
          ),
          name: name,
          author: await item.getStringAsync(rule.author),
          kind: await item.getStringAsync(rule.kind),
          intro: await item.getStringAsync(rule.intro),
          coverUrl: this.resolveUrl(await item.getStringAsync(rule.coverUrl), response.finalUrl),
          latestChapterTitle: await item.getStringAsync(rule.lastChapter),
          wordCount: await item.getStringAsync(rule.wordCount),
          type: this.compiled.source.bookSourceType,
          variable: this.serializeVariableSnapshot(item.getVariablesSnapshot())
        });
        cancellationToken?.throwIfCancelled();
        this.syncVariables(item);
      }
      cancellationToken?.throwIfCancelled();
      const finalizedBooks: LegadoSearchBook[] = this.finalizeSearchBooks(books, reverseBookList);
      const firstResolvedBookUrl: string = finalizedBooks.length > 0 ? finalizedBooks[0].bookUrl : '';
      // A count-only Search witness cannot distinguish a selector-order drift
      // from a relative-URL extraction drift. Mirror BookList's final
      // de-duplication/reversal before recording the bounded, one-way prefix.
      const bookTargetSequence: string[] = [];
      const bookTargetSequenceDistinct: Set<string> = new Set<string>();
      let bookTargetSequenceEmptyCount: number = 0;
      for (let targetIndex = 0; targetIndex < finalizedBooks.length && targetIndex < 8; targetIndex++) {
        const targetFingerprint: string = await this.getTraceTargetFingerprint(finalizedBooks[targetIndex].bookUrl);
        bookTargetSequence.push(targetFingerprint);
        if (targetFingerprint === 'empty') {
          bookTargetSequenceEmptyCount++;
        } else {
          bookTargetSequenceDistinct.add(targetFingerprint);
        }
      }
      const budgetSummary = maxResults === Number.MAX_SAFE_INTEGER ? 'full' : String(maxResults);
      const indexDiagnostic: string = elementDiagnostic.baseMatchedCount >= 0
        ? `;indexBase=${elementDiagnostic.baseMatchedCount};resolver=${elementDiagnostic.resolver}`
        : '';
      const domDiagnostic: string = this.getSearchDomDiagnostic(response.errorMessage);
      const firstBookTarget = await this.getTraceTargetFingerprint(firstResolvedBookUrl);
      const networkDiagnostic = await this.buildSearchNetworkDiagnostic(response);
      const bookUrlRuleDiagnostic = this.getSearchBookUrlRuleDiagnostic(rule.bookUrl);
      this.refreshTraceOutput(
        `search:${finalizedBooks.length};matched=${elements.length};budget=${budgetSummary};` +
        `deduplicated=${books.length - finalizedBooks.length};reversed=${reverseBookList}${indexDiagnostic}${domDiagnostic};` +
        `bookUrlEmpty=${emptyBookUrlCount};${bookUrlRuleDiagnostic};bookUrlJsResult=${bookUrlJsResultCount};` +
        `bookUrlJsEmpty=${bookUrlJsEmptyCount};bookUrlJsError=${bookUrlJsErrorCount};` +
        `bookUrlJsRuntimeUnavailable=${bookUrlJsRuntimeUnavailableCount};` +
        `bookUrlJsNotEvaluated=${bookUrlJsNotEvaluatedCount};` +
        `bookUrlJsMainRuleEmpty=${bookUrlJsMainRuleEmptyCount};` +
        `bookUrlJsInputJson=${bookUrlJsInputJsonCount};` +
        `bookTargetSequence=${bookTargetSequence.length > 0 ? bookTargetSequence.join(',') : 'empty'};` +
        `bookTargetSequenceDistinct=${bookTargetSequenceDistinct.size};` +
        `bookTargetSequenceEmpty=${bookTargetSequenceEmptyCount};` +
        `firstBookTarget=${firstBookTarget};${networkDiagnostic}`
      );
      return new LegadoWorkflowSearchResult(finalizedBooks, this.lastTrace);
    } catch (error) {
      cancellationToken?.throwIfCancelled();
      this.markWorkflowException(LegadoWorkflowKind.SEARCH, template, 'search_rule_exception');
      logger.warn(TAG, `V2 搜索规则执行失败: ${String(error)}`);
      return new LegadoWorkflowSearchResult([], this.lastTrace);
    }
  }

  async explore(
    exploreUrl: string,
    page: number = 1,
    cancellationToken?: LegadoExecutionCancellationToken
  ): Promise<LegadoWorkflowSearchResult> {
    cancellationToken?.throwIfCancelled();
    const template = exploreUrl || this.compiled.source.exploreUrl || '';
    if (template.length === 0) {
      return new LegadoWorkflowSearchResult([], null);
    }
    const ruleResolution = this.resolveExploreRule();
    if (ruleResolution === null) {
      return new LegadoWorkflowSearchResult([], this.lastTrace);
    }
    const rule = ruleResolution.rule;
    const bookListRule: string = rule.bookList || '';
    const assessment = getLegadoJsApiContractRegistry().assess(
      `${template}\n${rule.bookList}\n${rule.bookUrl}\n${rule.name}\n${rule.author}\n${rule.kind}\n${rule.intro}\n${rule.coverUrl}\n${rule.lastChapter}\n${rule.wordCount}`
    );
    if (this.blockForJsContracts(LegadoWorkflowKind.EXPLORE, template, assessment)) {
      return new LegadoWorkflowSearchResult([], this.lastTrace);
    }
    cancellationToken?.throwIfCancelled();
    const response = await this.execute(
      LegadoWorkflowKind.EXPLORE,
      template,
      '',
      page,
      '',
      '',
      cancellationToken
    );
    if (await this.blockProtectedResponse(LegadoWorkflowKind.EXPLORE, response)) {
      return new LegadoWorkflowSearchResult([], this.lastTrace);
    }
    if (!response.hasRuleReadableBody()) {
      return new LegadoWorkflowSearchResult([], this.lastTrace);
    }
    const analyzer = this.createAnalyzer(response.body, response.finalUrl, undefined, undefined, '', page);
    const elements = await analyzer.getElementsAsync(bookListRule);
    cancellationToken?.throwIfCancelled();
    const books: LegadoSearchBook[] = [];
    for (let i = 0; i < elements.length; i++) {
      cancellationToken?.throwIfCancelled();
      const item = this.createAnalyzer(elements[i], response.finalUrl, undefined, undefined, '', page);
      const name = await item.getStringAsync(rule.name);
      if (name.trim().length === 0) {
        continue;
      }
      const bookUrl = await item.getUrlStringAsync(rule.bookUrl);
      const resolvedExploreBookUrl = this.resolveUrl(bookUrl, response.finalUrl);
      const exploreRequestUrlTemplate = this.resolveRequestUrlTemplate(bookUrl, response.finalUrl);
      books.push({
        origin: this.compiled.source.bookSourceUrl,
        originName: this.compiled.source.bookSourceName,
        bookUrl: resolvedExploreBookUrl,
        requestUrlTemplate: exploreRequestUrlTemplate,
        requestCarrier: new LegadoRequestCarrier(
          this.compiled.source.bookSourceUrl,
          resolvedExploreBookUrl,
          exploreRequestUrlTemplate,
          'explore'
        ),
        name: name,
        author: await item.getStringAsync(rule.author),
        kind: await item.getStringAsync(rule.kind),
        intro: await item.getStringAsync(rule.intro),
        coverUrl: this.resolveUrl(await item.getStringAsync(rule.coverUrl), response.finalUrl),
        latestChapterTitle: await item.getStringAsync(rule.lastChapter),
        wordCount: await item.getStringAsync(rule.wordCount),
        type: this.compiled.source.bookSourceType,
        variable: this.serializeVariableSnapshot(item.getVariablesSnapshot())
      });
      cancellationToken?.throwIfCancelled();
      this.syncVariables(item);
    }
    cancellationToken?.throwIfCancelled();
    const ruleMode = ruleResolution.usesSearchRuleFallback ? 'search-fallback' : 'explore';
    this.refreshTraceOutput(`explore:${books.length};rule=${ruleMode}`);
    return new LegadoWorkflowSearchResult(books, this.lastTrace);
  }

  /**
   * Mirrors Legado's BookList.analyzeBookList selection exactly: discovery
   * keeps its own rule only when it has a list selector; otherwise it uses the
   * whole search rule (not merely the missing list selector).
   */
  private resolveExploreRule(): LegadoExploreRuleResolution | null {
    const exploreRule: LegadoExploreRule | undefined = this.compiled.source.ruleExplore;
    const exploreBookList: string = exploreRule?.bookList || '';
    if (exploreRule !== undefined && exploreBookList.trim().length > 0) {
      return new LegadoExploreRuleResolution(exploreRule, false);
    }

    const searchRule: LegadoSearchRule | undefined = this.compiled.source.ruleSearch;
    const searchBookList: string = searchRule?.bookList || '';
    if (searchRule === undefined || searchBookList.trim().length === 0) {
      return null;
    }

    const fallbackRule: LegadoExploreRule = {
      bookList: searchRule.bookList,
      name: searchRule.name,
      author: searchRule.author,
      intro: searchRule.intro,
      kind: searchRule.kind,
      lastChapter: searchRule.lastChapter,
      updateTime: searchRule.updateTime,
      bookUrl: searchRule.bookUrl,
      coverUrl: searchRule.coverUrl,
      wordCount: searchRule.wordCount
    };
    return new LegadoExploreRuleResolution(fallbackRule, true);
  }

  async getBookInfo(
    bookUrl: string,
    cancellationToken?: LegadoExecutionCancellationToken,
    bookVariable?: string,
    requestUrlTemplate?: string
  ): Promise<LegadoWorkflowBookInfoResult> {
    cancellationToken?.throwIfCancelled();
    this.restoreBookVariableSnapshot(bookVariable || this.lastWorkflowVariableSnapshot);
    const rule = this.compiled.source.ruleBookInfo;
    if (!rule) {
      return new LegadoWorkflowBookInfoResult(
        null,
        [],
        this.lastTrace,
        this.createBookInfoHandoff(null, [], 'book_info_rule_missing')
      );
    }
    const initAssessment = getLegadoJsApiContractRegistry().assess(
      `${rule.init || ''}\n${rule.tocUrl || ''}\n${rule.downloadUrls || ''}`
    );
    if (this.blockForJsContracts(LegadoWorkflowKind.BOOK_INFO, bookUrl, initAssessment)) {
      return new LegadoWorkflowBookInfoResult(
        null,
        [],
        this.lastTrace,
        this.createBookInfoHandoff(null, [], 'book_info_js_contract_blocked')
      );
    }
    cancellationToken?.throwIfCancelled();
    const requestTarget = requestUrlTemplate || bookUrl;
    const response = await this.execute(
      LegadoWorkflowKind.BOOK_INFO,
      requestTarget,
      '',
      1,
      '',
      '',
      cancellationToken
    );
    if (await this.blockProtectedResponse(LegadoWorkflowKind.BOOK_INFO, response)) {
      return new LegadoWorkflowBookInfoResult(
        null,
        [],
        this.lastTrace,
        this.createBookInfoHandoff(null, [], 'book_info_protected_response')
      );
    }
    if (!response.hasRuleReadableBody()) {
      this.refreshTraceOutput(await this.buildBookInfoTransportDiagnostic(rule, response));
      return new LegadoWorkflowBookInfoResult(
        null,
        [],
        this.lastTrace,
        this.createBookInfoHandoff(null, [], 'book_info_transport_unavailable')
      );
    }
    const book: LegadoBook = this.createBookInfoSeed(bookUrl, requestTarget);
    const analyzer = this.createAnalyzer(response.body, response.finalUrl, book);
    if (rule.init && rule.init.trim().length > 0) {
      // BookInfo.analyzeBookInfo calls setContent(getElement(init)). The init
      // rule therefore changes the input document for every following field;
      // merely evaluating it leaves templates such as {{$.id}} at the outer
      // response level and is observably incompatible with Legado sources.
      const initializedElements = await analyzer.getElementsAsync(rule.init);
      if (initializedElements.length > 0) {
        analyzer.setContent(initializedElements[0], response.finalUrl);
      }
      cancellationToken?.throwIfCancelled();
      this.syncVariables(analyzer);
    }
    const canRename = this.resolveBoolean(await analyzer.getStringAsync(rule.canReName));
    const parsedName = await analyzer.getStringAsync(rule.name);
    const parsedAuthor = await analyzer.getStringAsync(rule.author);
    const parsedKind = await analyzer.getStringAsync(rule.kind);
    const parsedIntro = await analyzer.getStringAsync(rule.intro);
    const parsedCoverUrl = await analyzer.getStringAsync(rule.coverUrl);
    book.name = parsedName.length > 0 || canRename ? parsedName : '';
    book.author = parsedAuthor.length > 0 || canRename ? parsedAuthor : '';
    book.kind = parsedKind;
    book.intro = parsedIntro;
    book.coverUrl = this.resolveUrl(parsedCoverUrl, response.finalUrl);
    analyzer.setJsExecutionBinding(this.createJsExecutionBinding(book, undefined, '', 1));
    const tocVariableFingerprintBefore = await this.getVariableScopeFingerprint(analyzer.getVariablesSnapshot());
    const parsedTocUrl = await analyzer.getUrlStringAsync(rule.tocUrl);
    const tocVariableFingerprintAfter = await this.getVariableScopeFingerprint(analyzer.getVariablesSnapshot());
    const parsedLastChapter = await analyzer.getStringAsync(rule.lastChapter);
    const parsedWordCount = await analyzer.getStringAsync(rule.wordCount);
    cancellationToken?.throwIfCancelled();
    const diagnostic = await this.buildBookInfoDiagnostic(
      analyzer,
      rule,
      response,
      parsedName,
      parsedAuthor,
      parsedKind,
      parsedIntro,
      parsedCoverUrl,
      parsedTocUrl,
      parsedLastChapter,
      parsedWordCount,
      tocVariableFingerprintBefore,
      tocVariableFingerprintAfter
    );
    // WebBook.getBookInfoAwait returns the incoming Book even when a received
    // document resolves none of the declared metadata fields. The next Toc
    // workflow still owns the decision about readability. Treating this as a
    // V2-only fatal rule error prevented that original-compatible path.
    const parsedTocRequestTemplate = this.resolveRequestUrlTemplate(parsedTocUrl, response.finalUrl);
    book.tocUrl = this.resolveUrl(parsedTocUrl, response.finalUrl) || bookUrl;
    book.tocRequestUrlTemplate = parsedTocRequestTemplate || requestTarget;
    book.tocRequestCarrier = new LegadoRequestCarrier(
      this.compiled.source.bookSourceUrl,
      book.tocUrl,
      book.tocRequestUrlTemplate,
      'book_info.toc'
    );
    book.latestChapterTitle = parsedLastChapter;
    book.wordCount = parsedWordCount;
    book.infoHtml = response.body;
    book.variable = this.serializeVariableSnapshot(analyzer.getVariablesSnapshot());
    const candidates = await this.readDownloadCandidates(analyzer, rule.downloadUrls || '', response.finalUrl);
    cancellationToken?.throwIfCancelled();
    const candidateUrls: string[] = [];
    for (let index = 0; index < candidates.length; index++) {
      candidateUrls.push(candidates[index].url);
    }
    book.downloadUrls = candidateUrls;
    const bookInfoHandoff = this.createBookInfoHandoff(book, candidates, 'book_info_ready');
    if (this.compiled.source.bookSourceType === LegadoBookSourceType.FILE && candidates.length <= 0) {
      this.markBookInfoRuleFailure(response, 'file_download_urls_empty');
      const failedHandoff = this.createBookInfoHandoff(null, [], 'file_download_urls_empty');
      this.refreshTraceOutput('file_download_urls_empty;handoff=blocked');
      return new LegadoWorkflowBookInfoResult(null, [], this.lastTrace, failedHandoff);
    }
    this.refreshTraceOutput(`${diagnostic.summary};downloads=${candidates.length}`);
    return new LegadoWorkflowBookInfoResult(book, candidates, this.lastTrace, bookInfoHandoff);
  }

  async getChapterList(
    book: LegadoBook,
    cancellationToken?: LegadoExecutionCancellationToken
  ): Promise<LegadoWorkflowTocResult> {
    this.restoreBookVariableSnapshot(book.variable);
    const initialUrl = book.tocRequestCarrier?.requestUrlTemplate ||
      book.tocRequestUrlTemplate ||
      book.requestCarrier?.requestUrlTemplate ||
      book.requestUrlTemplate ||
      book.tocUrl ||
      book.bookUrl;
    try {
      cancellationToken?.throwIfCancelled();
      const rule = this.compiled.source.ruleToc;
      if (!rule) {
        return new LegadoWorkflowTocResult([], null);
      }
      const preUpdateAssessment = getLegadoJsApiContractRegistry().assess(rule.preUpdateJs || '');
      if (this.blockForJsContracts(LegadoWorkflowKind.TOC, initialUrl, preUpdateAssessment)) {
        return new LegadoWorkflowTocResult([], this.lastTrace);
      }
      const chapters: LegadoChapter[] = [];
      const visited = new Set<string>();
      const queued = new Set<string>();
      const pendingPages: LegadoTocPageRequest[] = [];
      let matchedElementCount = 0;
      let missingChapterUrlCount = 0;
      let fallbackChapterUrlCount = 0;
      let droppedChapterUrlCount = 0;
      if (initialUrl.length > 0) {
        pendingPages.push(new LegadoTocPageRequest(initialUrl, true));
        queued.add(initialUrl);
      }
      let pageCount = 0;
      while (pendingPages.length > 0 && pageCount < MAX_PAGINATION_DEPTH) {
        cancellationToken?.throwIfCancelled();
        const currentPage = pendingPages.shift();
        if (currentPage === undefined || currentPage.url.length <= 0) {
          continue;
        }
        queued.delete(currentPage.url);
        if (visited.has(currentPage.url)) {
          continue;
        }
        visited.add(currentPage.url);
        pageCount++;
        const response = await this.execute(
          LegadoWorkflowKind.TOC,
          currentPage.url,
          '',
          pageCount,
          '',
          '',
          cancellationToken
        );
        if (await this.blockProtectedResponse(LegadoWorkflowKind.TOC, response)) {
          return new LegadoWorkflowTocResult([], this.lastTrace);
        }
        if (!response.hasRuleReadableBody()) {
          continue;
        }
        const analyzer = this.createAnalyzer(response.body, response.finalUrl, book, undefined, '', pageCount);
        if (rule.preUpdateJs && rule.preUpdateJs.trim().length > 0) {
          await analyzer.getStringAsync(rule.preUpdateJs);
          cancellationToken?.throwIfCancelled();
        }
        const elements = rule.chapterList ? await analyzer.getElementsAsync(rule.chapterList) : [];
        matchedElementCount += elements.length;
        cancellationToken?.throwIfCancelled();
        for (let i = 0; i < elements.length; i++) {
          cancellationToken?.throwIfCancelled();
          const item = this.createAnalyzer(elements[i], response.finalUrl, book, undefined, '', pageCount);
          let title = await item.getStringAsync(rule.chapterName);
          if (rule.formatJs && rule.formatJs.trim().length > 0) {
            const formatted = await this.formatChapterTitle(rule.formatJs, title, response.finalUrl, book, pageCount);
            if (formatted.length > 0) {
              title = formatted;
            }
          }
          const rawChapterUrl = await item.getUrlStringAsync(rule.chapterUrl);
          const isVolume = this.resolveBoolean(await item.getStringAsync(rule.isVolume));
          const isVip = this.resolveBoolean(await item.getStringAsync(rule.isVip));
          const isPay = this.resolveBoolean(await item.getStringAsync(rule.isPay));
          const updateTime = this.parseTime(await item.getStringAsync(rule.updateTime));
          let chapterUrl = this.resolveUrl(rawChapterUrl, response.finalUrl);
          if (chapterUrl.length === 0) {
            missingChapterUrlCount++;
            // Legado keeps a chapter even when its URL selector is empty:
            // volume entries use a stable synthetic key, other entries use
            // the current TOC page as the request target. Preserve that
            // fallback while recording it so an IMAGE source cannot be
            // mistaken for a fully resolved chapter list.
            chapterUrl = isVolume
              ? `${title}${i}`
              : (response.finalUrl.length > 0 ? response.finalUrl : currentPage.url);
            if (chapterUrl.length > 0) {
              fallbackChapterUrlCount++;
            } else {
              droppedChapterUrlCount++;
              continue;
            }
          }
          chapters.push({
            id: `${book.bookUrl}:${chapters.length}`,
            bookUrl: book.bookUrl,
            url: chapterUrl,
            requestUrlTemplate: this.resolveRequestUrlTemplate(rawChapterUrl, response.finalUrl) || chapterUrl,
            requestCarrier: new LegadoRequestCarrier(
              this.compiled.source.bookSourceUrl,
              chapterUrl,
              this.resolveRequestUrlTemplate(rawChapterUrl, response.finalUrl) || chapterUrl,
              'toc.chapter'
            ),
            title: title || `第${chapters.length + 1}章`,
            index: chapters.length,
            isVolume: isVolume,
            isVip: isVip,
            isPay: isPay,
            updateTime: updateTime,
            variable: this.serializeVariableSnapshot(item.getVariablesSnapshot())
          });
          cancellationToken?.throwIfCancelled();
          this.syncVariables(item);
        }
        if (!currentPage.mayDiscoverNextPages) {
          continue;
        }
        const nextUrls = await this.getTocNextUrls(analyzer, rule.nextTocUrl || '', response.finalUrl);
        cancellationToken?.throwIfCancelled();
        const nextMayDiscoverPages = nextUrls.length === 1;
        for (let index = 0; index < nextUrls.length; index++) {
          const nextUrl = nextUrls[index];
          if (visited.has(nextUrl) || queued.has(nextUrl)) {
            continue;
          }
          pendingPages.push(new LegadoTocPageRequest(nextUrl, nextMayDiscoverPages));
          queued.add(nextUrl);
        }
      }
      cancellationToken?.throwIfCancelled();
      const finalBody = this.lastTrace === null ? '' : this.lastTrace.response.body;
      const finalFingerprint = await this.getResponseFingerprint(finalBody);
      const responseClass = this.classifyResponseBody(finalBody);
      const requestUrl = this.lastTrace === null ? '' : this.lastTrace.request.url;
      const requestUrlFingerprint = await this.getResponseFingerprint(requestUrl);
      const chapterUrlRuleState = rule.chapterUrl && rule.chapterUrl.trim().length > 0 ? 'present' : 'absent';
      const bookVariableState = book.variable && book.variable.trim().length > 0 ? 'present' : 'absent';
      const imageWorkflowOutcome = this.resolveImageTocOutcome(
        matchedElementCount,
        chapters.length,
        missingChapterUrlCount,
        fallbackChapterUrlCount,
        droppedChapterUrlCount
      );
      const outputKind = chapters.length > 0
        ? (fallbackChapterUrlCount > 0 ? 'toc_nonempty_with_url_fallback' : 'toc_nonempty')
        : 'toc_empty';
      this.refreshTraceOutput(
        `toc:${chapters.length};matched=${matchedElementCount};missingUrl=${missingChapterUrlCount};` +
        `fallbackUrl=${fallbackChapterUrlCount};droppedUrl=${droppedChapterUrlCount};` +
        `pages=${pageCount};body=${finalBody.length}:${finalFingerprint};responseClass=${responseClass};` +
        `chapterUrlRule=${chapterUrlRuleState};bookVariable=${bookVariableState};` +
        `outputKind=${outputKind};imageWorkflowOutcome=${imageWorkflowOutcome};reqUrl=${requestUrlFingerprint}`
      );
      return new LegadoWorkflowTocResult(chapters, this.lastTrace);
    } catch (error) {
      cancellationToken?.throwIfCancelled();
      this.markWorkflowException(LegadoWorkflowKind.TOC, initialUrl, 'toc_rule_exception');
      logger.warn(TAG, `V2 目录规则执行失败: ${String(error)}`);
      return new LegadoWorkflowTocResult([], this.lastTrace);
    }
  }

  async getContent(
    chapter: LegadoChapter,
    cancellationToken?: LegadoExecutionCancellationToken
  ): Promise<LegadoWorkflowContentResult> {
    cancellationToken?.throwIfCancelled();
    this.restoreBookVariableSnapshot(chapter.variable);
    const rule = this.compiled.source.ruleContent;
    if (!rule || !rule.content) {
      return new LegadoWorkflowContentResult(
        '',
        chapter.title,
        null,
        this.createContentHandoff('', 'content_rule_missing', null, null)
      );
    }
    const contentAssessment = getLegadoJsApiContractRegistry().assess(
      `${rule.content}\n${rule.replaceRegex || ''}\n${rule.webJs || ''}\n${rule.imageDecode || ''}\n${rule.payAction || ''}`
    );
    if (this.blockForJsContracts(LegadoWorkflowKind.CONTENT, chapter.url, contentAssessment)) {
      return new LegadoWorkflowContentResult(
        '',
        chapter.title,
        this.lastTrace,
        this.createContentHandoff('', 'content_js_contract_blocked', rule, contentAssessment)
      );
    }
    const visited = new Set<string>();
    const pendingUrls: string[] = [
      chapter.requestCarrier?.requestUrlTemplate || chapter.requestUrlTemplate || chapter.url
    ];
    const parts: string[] = [];
    let title = chapter.title;
    let lastBaseUrl = chapter.url;
    let pageCount = 0;
    let bridgeStatus = 'not_applicable';
    let bridgeCandidate = '';
    // Content diagnostics are deliberately aggregate-only: they make an
    // extraction-versus-presentation mismatch reproducible without retaining
    // a chapter body in an execution trace.
    let extractedCharacterCount = 0;
    let extractedLineFeedCount = 0;
    let normalizedCharacterCount = 0;
    let normalizedLineFeedCount = 0;
    let firstExtractLeadingWhitespaceCount = -1;
    let firstExtractStartsWithLineFeed = 0;
    let firstExtractStartsWithBlockTag = 0;
    let firstNormalizeStartsWithReaderIndent = 0;
    // Preserve only a fixed, redacted witness for the first production content
    // response.  This separates transport/request drift from selector drift
    // without retaining a URL, header value, or response body in the trace.
    let firstResponseEvidence =
      'reqTarget=empty;ua=empty;contentType=empty;redirects=0;body=0:empty;responseClass=empty;' +
      'reqMethod=unknown;reqHeaderCount=0;reqHeaderFingerprint=empty';
    while (pendingUrls.length > 0 && pageCount < MAX_PAGINATION_DEPTH) {
      cancellationToken?.throwIfCancelled();
      const currentUrl = pendingUrls.shift();
      if (currentUrl === undefined || currentUrl.length <= 0) {
        continue;
      }
      if (visited.has(currentUrl)) {
        continue;
      }
      visited.add(currentUrl);
      pageCount++;
      const response = await this.execute(
        LegadoWorkflowKind.CONTENT,
        currentUrl,
        '',
        pageCount,
        rule.sourceRegex || '',
        rule.webJs || '',
        cancellationToken
      );
      if (pageCount === 1) {
        firstResponseEvidence = await this.buildSearchNetworkDiagnostic(response);
      }
      if (await this.blockProtectedResponse(LegadoWorkflowKind.CONTENT, response)) {
        return new LegadoWorkflowContentResult(
          '',
          chapter.title,
          this.lastTrace,
          this.createContentHandoff('', 'content_protected_response', rule, contentAssessment)
        );
      }
      if (!response.hasRuleReadableBody()) {
        continue;
      }
      lastBaseUrl = response.finalUrl;
      const analyzer = this.createAnalyzer(response.body, response.finalUrl, undefined, chapter, '', pageCount);
      const extractedContent = await analyzer.getStringAsync(rule.content);
      extractedCharacterCount += extractedContent.length;
      extractedLineFeedCount += this.countLineFeeds(extractedContent);
      if (pageCount === 1) {
        firstExtractLeadingWhitespaceCount = this.countLeadingWhitespace(extractedContent);
        firstExtractStartsWithLineFeed = this.startsWithLineFeed(extractedContent) ? 1 : 0;
        firstExtractStartsWithBlockTag = this.startsWithHtmlBlockTag(extractedContent) ? 1 : 0;
      }
      const bridgeProbe = analyzer.getSimpleCssChainBridgeProbe(rule.content);
      if (pageCount === 1) {
        bridgeStatus = bridgeProbe.status;
        bridgeCandidate = bridgeProbe.candidate;
      }
      cancellationToken?.throwIfCancelled();
      const readerContent = LegadoContentSemantics.normalizePageContent(
        extractedContent,
        this.compiled.source.bookSourceType,
        response.finalUrl
      );
      normalizedCharacterCount += readerContent.length;
      normalizedLineFeedCount += this.countLineFeeds(readerContent);
      if (pageCount === 1) {
        firstNormalizeStartsWithReaderIndent = readerContent.startsWith('　　') ? 1 : 0;
      }
      if (readerContent.length > 0) {
        parts.push(readerContent);
      }
      if (rule.title && rule.title.trim().length > 0) {
        const parsedTitle = await analyzer.getStringAsync(rule.title);
        cancellationToken?.throwIfCancelled();
        if (parsedTitle.length > 0) {
          title = parsedTitle;
        }
      }
      cancellationToken?.throwIfCancelled();
      this.syncVariables(analyzer);
      const nextUrls = await this.getContentNextUrls(analyzer, rule.nextContentUrl || '', response.finalUrl);
      cancellationToken?.throwIfCancelled();
      for (let index = 0; index < nextUrls.length; index++) {
        const nextUrl = nextUrls[index];
        if (nextUrl.length > 0 && !visited.has(nextUrl) && !pendingUrls.includes(nextUrl)) {
          pendingUrls.push(nextUrl);
        }
      }
    }
    const joinedContent = LegadoContentSemantics.joinNormalizedPages(parts);
    const joinedLineFeedCount = this.countLineFeeds(joinedContent);
    const content = await this.applyFinalContentReplacement(
      joinedContent,
      rule.replaceRegex || '',
      title,
      lastBaseUrl
    );
    cancellationToken?.throwIfCancelled();
    const presentation = LegadoContentSemantics.assessReaderPayload(
      content,
      this.compiled.source.bookSourceType
    );
    const imageContentRejected = this.compiled.source.bookSourceType === LegadoBookSourceType.IMAGE &&
      presentation.status !== LegadoContentPresentationStatus.READABLE;
    const imageWorkflowOutcome = imageContentRejected
      ? (presentation.status === LegadoContentPresentationStatus.INVALID_IMAGE
        ? 'image_workflow_invalid_content'
        : 'image_workflow_empty_content')
      : 'none';
    const contentFingerprint = await this.getResponseFingerprint(content);
    const bridgeLength = bridgeCandidate.length;
    const bridgeFingerprint = bridgeLength <= 0
      ? 'empty'
      : await this.getResponseFingerprint(bridgeCandidate);
    // Diagnostic-only semantic witness for selector-only bridge candidates.
    // It never changes the active fallback result or persists source text;
    // the three aggregate values let a real-device mismatch prove whether
    // divergence is in DOM selection/serialization or reader formatting.
    const bridgeReaderContent = bridgeLength <= 0
      ? ''
      : LegadoContentSemantics.normalizePageContent(
        bridgeCandidate,
        this.compiled.source.bookSourceType,
        lastBaseUrl
      );
    const bridgeReaderLength = bridgeReaderContent.length;
    const bridgeReaderLineFeedCount = this.countLineFeeds(bridgeReaderContent);
    const bridgeReaderFingerprint = bridgeReaderLength <= 0
      ? 'empty'
      : await this.getResponseFingerprint(bridgeReaderContent);
    const finalLineFeedCount = this.countLineFeeds(content);
    const normalizationDelta = normalizedCharacterCount - extractedCharacterCount;
    const executionVariables = this.planner.getVariablesSnapshot();
    const contentScopeHeaders = executionVariables.has('headers') ? 'present' : 'absent';
    const contentScopeBid = executionVariables.has('bid') ? 'present' : 'absent';
    this.refreshTraceOutput(
      `content:pages=${pageCount};fragments=${parts.length};chars=${content.length};` +
      `replace=${rule.replaceRegex && rule.replaceRegex.trim().length > 0 ? 'applied' : 'none'};` +
      `presentation=${presentation.status};bridge=${bridgeStatus};bridgeChars=${bridgeLength};` +
      `imageOutcome=${imageWorkflowOutcome};` +
      `bridgeDigest=${bridgeFingerprint};bridgeReaderChars=${bridgeReaderLength};` +
      `bridgeReaderLf=${bridgeReaderLineFeedCount};bridgeReaderDigest=${bridgeReaderFingerprint};` +
      `digest=${contentFingerprint};` +
      `extractChars=${extractedCharacterCount};extractLf=${extractedLineFeedCount};` +
      `normalizeChars=${normalizedCharacterCount};normalizeLf=${normalizedLineFeedCount};` +
      `normalizeDelta=${normalizationDelta};joinedChars=${joinedContent.length};` +
      `joinedLf=${joinedLineFeedCount};finalLf=${finalLineFeedCount};` +
      `firstLead=${firstExtractLeadingWhitespaceCount};firstLf=${firstExtractStartsWithLineFeed};` +
      `firstBlock=${firstExtractStartsWithBlockTag};firstIndent=${firstNormalizeStartsWithReaderIndent};` +
      `scopeHeaders=${contentScopeHeaders};scopeBid=${contentScopeBid};` +
      firstResponseEvidence
    );
    const contentHandoff = this.createContentHandoff(
      content,
      imageContentRejected
        ? imageWorkflowOutcome
        : 'content_ready',
      rule,
      contentAssessment,
      presentation.status
    );
    if (imageContentRejected) {
      logger.warn(TAG, `IMAGE 正文被拒绝交接: outcome=${imageWorkflowOutcome};presentation=${presentation.status};chars=${content.length}`);
    }
    return new LegadoWorkflowContentResult(content, title, this.lastTrace, contentHandoff);
  }

  private resolveWorkflowOutputKind(sourceType: number): LegadoWorkflowOutputKind {
    if (sourceType === LegadoBookSourceType.AUDIO) {
      return LegadoWorkflowOutputKind.AUDIO;
    }
    if (sourceType === LegadoBookSourceType.IMAGE) {
      return LegadoWorkflowOutputKind.IMAGE;
    }
    if (sourceType === LegadoBookSourceType.FILE) {
      return LegadoWorkflowOutputKind.FILE;
    }
    if (sourceType === LegadoBookSourceType.TEXT) {
      return LegadoWorkflowOutputKind.TEXT;
    }
    return LegadoWorkflowOutputKind.NONE;
  }

  private mapJsApiStatusToHandoffStatus(status: LegadoJsApiStatus | null): LegadoWorkflowHandoffStatus {
    if (status === LegadoJsApiStatus.UNSUPPORTED_API) {
      return LegadoWorkflowHandoffStatus.UNSUPPORTED_API;
    }
    if (status === LegadoJsApiStatus.NEEDS_INTERACTION) {
      return LegadoWorkflowHandoffStatus.NEEDS_INTERACTION;
    }
    if (status === LegadoJsApiStatus.POLICY_BLOCKED) {
      return LegadoWorkflowHandoffStatus.POLICY_BLOCKED;
    }
    return LegadoWorkflowHandoffStatus.READY;
  }

  private createAuxiliaryRuleOutcome(
    feature: string,
    ruleText: string,
    assessment: LegadoJsApiAssessment | null
  ): LegadoAuxiliaryRuleOutcome {
    if (ruleText.trim().length <= 0) {
      return new LegadoAuxiliaryRuleOutcome(feature, LegadoJsApiStatus.SUPPORTED, 'not_declared');
    }
    if (assessment !== null && assessment.blockingStatus !== null) {
      return new LegadoAuxiliaryRuleOutcome(
        feature,
        assessment.blockingStatus,
        `js_contract:${assessment.blockingStatus}`
      );
    }
    if (feature === 'imageDecode') {
      return new LegadoAuxiliaryRuleOutcome(
        feature,
        LegadoJsApiStatus.POLICY_BLOCKED,
        'image_decode_requires_binary_consumer'
      );
    }
    return new LegadoAuxiliaryRuleOutcome(
      feature,
      LegadoJsApiStatus.NEEDS_INTERACTION,
      'pay_action_requires_user_interaction'
    );
  }

  private createBookInfoHandoff(
    book: LegadoBook | null,
    candidates: LegadoFileDownloadCandidate[],
    reasonCode: string
  ): LegadoWorkflowOutput {
    const sourceType = book === null ? this.compiled.source.bookSourceType : book.type;
    const kind = this.resolveWorkflowOutputKind(sourceType);
    const status = book === null
      ? LegadoWorkflowHandoffStatus.EMPTY
      : sourceType === LegadoBookSourceType.FILE
        ? (candidates.length <= 0
          ? LegadoWorkflowHandoffStatus.EMPTY
          : LegadoWorkflowHandoffStatus.MISSING_CONSUMER)
        : LegadoWorkflowHandoffStatus.READY;
    const effectiveReason = sourceType === LegadoBookSourceType.FILE && candidates.length > 0
      ? 'file_downloader_consumer_missing'
      : reasonCode;
    return new LegadoWorkflowOutput(
      kind,
      sourceType,
      status,
      '',
      '',
      '',
      candidates,
      effectiveReason
    );
  }

  private createContentHandoff(
    content: string,
    reasonCode: string,
    rule: LegadoContentRule | null,
    assessment: LegadoJsApiAssessment | null,
    presentationStatus: LegadoContentPresentationStatus | null = null
  ): LegadoWorkflowOutput {
    const sourceType = this.compiled.source.bookSourceType;
    const kind = this.resolveWorkflowOutputKind(sourceType);
    const payAction = this.createAuxiliaryRuleOutcome(
      'payAction',
      rule === null ? '' : rule.payAction || '',
      assessment
    );
    const imageDecode = this.createAuxiliaryRuleOutcome(
      'imageDecode',
      rule === null ? '' : rule.imageDecode || '',
      assessment
    );
    let status = assessment === null
      ? LegadoWorkflowHandoffStatus.READY
      : this.mapJsApiStatusToHandoffStatus(assessment.blockingStatus);
    if (status === LegadoWorkflowHandoffStatus.READY && rule === null) {
      status = LegadoWorkflowHandoffStatus.EMPTY;
    }
    if (status === LegadoWorkflowHandoffStatus.READY && content.trim().length <= 0) {
      status = LegadoWorkflowHandoffStatus.EMPTY;
    }
    if (status === LegadoWorkflowHandoffStatus.READY && sourceType === LegadoBookSourceType.FILE) {
      status = LegadoWorkflowHandoffStatus.MISSING_CONSUMER;
    }
    if (status === LegadoWorkflowHandoffStatus.READY && sourceType === LegadoBookSourceType.IMAGE &&
      presentationStatus !== null && presentationStatus !== LegadoContentPresentationStatus.READABLE) {
      status = LegadoWorkflowHandoffStatus.INVALID_OUTPUT;
    }
    if (status === LegadoWorkflowHandoffStatus.READY && payAction.status !== LegadoJsApiStatus.SUPPORTED) {
      status = this.mapJsApiStatusToHandoffStatus(payAction.status);
    }
    if (status === LegadoWorkflowHandoffStatus.READY && imageDecode.status !== LegadoJsApiStatus.SUPPORTED) {
      status = this.mapJsApiStatusToHandoffStatus(imageDecode.status);
    }
    const textContent = kind === LegadoWorkflowOutputKind.TEXT ? content : '';
    const mediaUrl = kind === LegadoWorkflowOutputKind.AUDIO ? content : '';
    const imageContent = kind === LegadoWorkflowOutputKind.IMAGE ? content : '';
    return new LegadoWorkflowOutput(
      kind,
      sourceType,
      status,
      textContent,
      mediaUrl,
      imageContent,
      [],
      reasonCode,
      payAction,
      imageDecode
    );
  }

  private countLineFeeds(value: string): number {
    let count = 0;
    for (let index = 0; index < value.length; index++) {
      if (value[index] === '\n') {
        count++;
      }
    }
    return count;
  }

  private countLeadingWhitespace(value: string): number {
    let count = 0;
    while (count < value.length && /\s/.test(value[count])) {
      count++;
    }
    return count;
  }

  private startsWithLineFeed(value: string): boolean {
    return value.startsWith('\n') || value.startsWith('\r\n');
  }

  private startsWithHtmlBlockTag(value: string): boolean {
    const trimmed = value.trimStart().toLowerCase();
    return trimmed.startsWith('<div') || trimmed.startsWith('<p') || trimmed.startsWith('<article') ||
      trimmed.startsWith('<dd') || trimmed.startsWith('<dl') || trimmed.startsWith('<br') ||
      trimmed.startsWith('<hr') || /^<h[1-6](?:\s|>)/.test(trimmed);
  }

  private resolveImageTocOutcome(
    matchedElementCount: number,
    chapterCount: number,
    missingChapterUrlCount: number,
    fallbackChapterUrlCount: number,
    droppedChapterUrlCount: number
  ): string {
    if (this.compiled.source.bookSourceType !== LegadoBookSourceType.IMAGE) {
      return 'none';
    }
    if (matchedElementCount <= 0) {
      return 'image_workflow_empty_toc';
    }
    if (droppedChapterUrlCount > 0 || (chapterCount <= 0 && missingChapterUrlCount > 0)) {
      return 'image_workflow_missing_chapter_url';
    }
    if (fallbackChapterUrlCount > 0) {
      return 'image_workflow_chapter_url_fallback';
    }
    return 'none';
  }

  getExploreKinds(): LegadoExploreKind[] {
    const text = (this.compiled.source.exploreUrl || '').trim();
    if (text.length === 0) {
      this.logExploreKindsProjection('empty', 0);
      return [];
    }
    if (this.isExploreKindsScript(text)) {
      this.logExploreKindsProjection('dynamic_script_sync', 0);
      return [];
    }
    const kinds = new LegadoSourceParser().parseExploreKinds(text);
    this.logExploreKindsProjection('static_sync', kinds.length);
    return kinds;
  }

  async getExploreKindsAsync(
    cancellationToken?: LegadoExecutionCancellationToken
  ): Promise<LegadoExploreKind[]> {
    cancellationToken?.throwIfCancelled();
    const exploreUrl = (this.compiled.source.exploreUrl || '').trim();
    if (exploreUrl.length === 0) {
      this.logExploreKindsProjection('empty_async', 0);
      return [];
    }
    if (!this.isExploreKindsScript(exploreUrl)) {
      const kinds = this.getExploreKinds();
      this.logExploreKindsProjection('static_async', kinds.length);
      return kinds;
    }

    const script = this.extractExploreKindsScript(exploreUrl);
    const assessment = getLegadoJsApiContractRegistry().assess(script);
    if (this.blockForJsContracts(
      LegadoWorkflowKind.EXPLORE,
      'legado://explore-kinds',
      assessment
    )) {
      throw new Error('LEGADO_EXPLORE_KINDS_JS_CONTRACT_BLOCKED');
    }

    const execution = await this.sourceScriptRuntime.execute(
      this.compiled.source,
      script,
      this.planner.getVariablesSnapshot(),
      cancellationToken
    );
    cancellationToken?.throwIfCancelled();
    this.applySourceScriptVariables(execution);
    if (!execution.success) {
      this.recordExploreKindsScriptTrace(execution, 0);
      throw new Error(`LEGADO_EXPLORE_KINDS_${execution.errorMessage}`);
    }

    const kinds = new LegadoSourceParser().parseExploreKinds(execution.result);
    this.recordExploreKindsScriptTrace(execution, kinds.length);
    this.logExploreKindsProjection('dynamic_async', kinds.length);
    return kinds;
  }

  private isExploreKindsScript(value: string): boolean {
    const normalized = value.trim().toLowerCase();
    return normalized.startsWith('@js:') ||
      normalized.startsWith('@js：') ||
      normalized.startsWith('＠js:') ||
      normalized.startsWith('＠js：') ||
      normalized.startsWith('<js>');
  }

  private extractExploreKindsScript(value: string): string {
    const trimmed = value.trim();
    const normalized = trimmed.toLowerCase();
    if (normalized.startsWith('@js:') || normalized.startsWith('@js：') ||
      normalized.startsWith('＠js:') || normalized.startsWith('＠js：')) {
      return trimmed.substring(4);
    }
    if (normalized.startsWith('<js>')) {
      const closingIndex = normalized.lastIndexOf('</js>');
      return closingIndex > 4
        ? trimmed.substring(4, closingIndex)
        : trimmed.substring(4);
    }
    return trimmed;
  }

  private applySourceScriptVariables(execution: LegadoSourceScriptResult): void {
    for (let i = 0; i < execution.variableChanges.length; i++) {
      const change = execution.variableChanges[i];
      this.planner.setVariable(change.key, change.value);
    }
  }

  private recordExploreKindsScriptTrace(execution: LegadoSourceScriptResult, kindCount: number): void {
    const traceId = `${this.compiled.source.bookSourceUrl}|explore|${Date.now()}|dynamic_kinds`;
    const optionTrace: LegadoRequestOptionTrace[] = [
      new LegadoRequestOptionTrace(
        'exploreUrlJs',
        execution.success ? LegadoRequestDisposition.EXECUTED : LegadoRequestDisposition.UNSUPPORTED,
        execution.success ? '动态发现分类脚本已执行' : execution.errorMessage
      )
    ];
    const request = new RequestSpec(
      traceId,
      this.compiled.source.bookSourceUrl,
      LegadoWorkflowKind.EXPLORE,
      'legado://explore-kinds',
      'SCRIPT',
      '',
      [],
      'UTF-8',
      0,
      '',
      false,
      true,
      '',
      '',
      0,
      0,
      'text',
      'not_applicable',
      optionTrace
    );
    const response = new ResponseEnvelope(
      traceId,
      '',
      'legado://explore-kinds',
      LegadoFinalUrlObservation.OBSERVED,
      execution.success ? 200 : 0,
      [],
      [],
      false,
      ['legado://explore-kinds'],
      LegadoTransportKind.ARK_WEB,
      0,
      execution.errorCode,
      execution.errorMessage
    );
    const variableChanges: string[] = [];
    for (let i = 0; i < execution.variableChanges.length; i++) {
      variableChanges.push(execution.variableChanges[i].key);
    }
    for (let i = 0; i < execution.sourceEffectNames.length; i++) {
      variableChanges.push(execution.sourceEffectNames[i]);
    }
    this.lastTrace = new LegadoExecutionTrace(
      traceId,
      this.compiled.source.bookSourceUrl,
      LegadoWorkflowKind.EXPLORE,
      request,
      response,
      variableChanges,
      execution.success
        ? `explore-kinds:${kindCount}`
        : `explore-kinds:failed:${execution.errorCode}:diagnostic=${this.toTraceDiagnosticToken(execution.errorMessage)}`,
      execution.bridgeTraces
    );
  }

  /**
   * The management UI exposes outputSummary through a compact grammar used by
   * the device harness. Keep the full structural diagnostic in
   * response.errorMessage, while using a punctuation-safe token in the
   * human-facing summary so the trace can still be parsed deterministically.
   */
  private toTraceDiagnosticToken(value: string): string {
    const normalized = value.replace(/[^A-Za-z0-9_.=-]/g, '_');
    return normalized.length > 0 ? normalized.substring(0, 240) : 'empty';
  }

  private async execute(
    workflow: LegadoWorkflowKind,
    template: string,
    key: string,
    page: number,
    sourceRegex: string,
    workflowWebJs: string = '',
    cancellationToken?: LegadoExecutionCancellationToken
  ): Promise<ResponseEnvelope> {
    this.activeWorkflowTraceId = '';
    cancellationToken?.throwIfCancelled();
    let request: RequestSpec;
    try {
      logger.warnForEvidence(TAG, `V2_STAGE:workflow_plan_begin:${workflow}`);
      request = await this.planner.plan(workflow, template, key, page, sourceRegex, workflowWebJs);
      logger.warnForEvidence(
        TAG,
        `V2_STAGE:workflow_plan_ready:${workflow}:${request.useWebView ? 'arkweb' : 'http'}`
      );
      this.activeWorkflowTraceId = request.traceId;
    } catch (error) {
      cancellationToken?.throwIfCancelled();
      return this.createPlanningFailureResponse(workflow, template, String(error));
    }
    try {
      cancellationToken?.throwIfCancelled();
      logger.warnForEvidence(TAG, `V2_STAGE:workflow_transport_dispatch:${workflow}`);
      const response = await this.router.execute(request, cancellationToken);
      logger.warnForEvidence(TAG, `V2_STAGE:workflow_transport_returned:${workflow}`);
      cancellationToken?.throwIfCancelled();
      this.lastTrace = new LegadoExecutionTrace(
        request.traceId,
        this.compiled.source.bookSourceUrl,
        workflow,
        request,
        response,
        [],
        response.hasRuleReadableBody() ? '' : `transport_failed:${response.errorCode}`
      );
      return response;
    } catch (error) {
      cancellationToken?.throwIfCancelled();
      return this.createExecutionFailureResponse(request, String(error));
    }
  }

  private async yieldToEventLoop(): Promise<void> {
    await new Promise<void>((resolve: () => void): void => {
      // A zero-delay timer can be coalesced into the active UV callback on
      // this API level. One frame gives ArkUI a real dispatch boundary.
      setTimeout(resolve, 16);
    });
  }

  /**
   * Planner exceptions previously escaped before a RequestSpec existed, which
   * made a real V2 failure indistinguishable from a legacy fallback. Create a
   * minimal, redaction-safe trace instead. The original template is retained
   * only in memory and is never persisted by the trace-summary store.
   */
  private createPlanningFailureResponse(
    workflow: LegadoWorkflowKind,
    template: string,
    message: string
  ): ResponseEnvelope {
    const traceId = `${this.compiled.source.bookSourceUrl}|${workflow}|${Date.now()}|planning_failure`;
    const requestHeaders: LegadoRequestHeader[] = [];
    const responseHeaders: LegadoResponseHeader[] = [];
    const redirectChain: string[] = [template];
    const request = new RequestSpec(
      traceId,
      this.compiled.source.bookSourceUrl,
      workflow,
      template,
      'GET',
      '',
      requestHeaders,
      '',
      0,
      this.compiled.source.concurrentRate || '',
      this.compiled.source.enabledCookieJar === true,
      false,
      '',
      '',
      0,
      0,
      '',
      'follow',
      [new LegadoRequestOptionTrace('planner', LegadoRequestDisposition.UNSUPPORTED, '请求计划失败')]
    );
    const response = new ResponseEnvelope(
      traceId,
      '',
      template,
      LegadoFinalUrlObservation.UNOBSERVABLE,
      0,
      requestHeaders,
      responseHeaders,
      false,
      redirectChain,
      LegadoTransportKind.HTTP,
      0,
      LegadoExecutionErrorCode.RULE,
      message
    );
    this.lastTrace = new LegadoExecutionTrace(
      traceId,
      this.compiled.source.bookSourceUrl,
      workflow,
      request,
      response,
      [],
      `planning_failed:${this.toTraceDiagnosticToken(message)}`
    );
    return response;
  }

  /** Gives unexpected transport/router exceptions the same trace contract. */
  private createExecutionFailureResponse(request: RequestSpec, message: string): ResponseEnvelope {
    const responseHeaders: LegadoResponseHeader[] = [];
    const redirectChain: string[] = [request.url];
    const response = new ResponseEnvelope(
      request.traceId,
      '',
      request.url,
      LegadoFinalUrlObservation.UNOBSERVABLE,
      0,
      request.headers,
      responseHeaders,
      false,
      redirectChain,
      request.useWebView ? LegadoTransportKind.ARK_WEB : LegadoTransportKind.HTTP,
      0,
      LegadoExecutionErrorCode.UNKNOWN,
      message
    );
    this.lastTrace = new LegadoExecutionTrace(
      request.traceId,
      this.compiled.source.bookSourceUrl,
      request.workflow,
      request,
      response,
      [],
      'transport_failed'
    );
    return response;
  }

  /** Ensures an analyzer/runtime failure never escapes the V2 trace contract. */
  private markWorkflowException(
    workflow: LegadoWorkflowKind,
    template: string,
    summary: string
  ): void {
    if (this.lastTrace === null) {
      this.createPlanningFailureResponse(workflow, template, 'WORKFLOW_EXCEPTION');
    }
    if (this.lastTrace === null) {
      return;
    }
    const trace = this.lastTrace;
    const failedResponse = new ResponseEnvelope(
      trace.response.traceId,
      trace.response.body,
      trace.response.finalUrl,
      trace.response.finalUrlObservation,
      trace.response.statusCode,
      trace.response.requestHeaders,
      trace.response.responseHeaders,
      trace.response.cookiesChanged,
      trace.response.redirectChain,
      trace.response.transport,
      trace.response.elapsedMs,
      LegadoExecutionErrorCode.RULE,
      'WORKFLOW_EXCEPTION'
    );
    this.replaceTrace(trace, workflow, failedResponse, trace.variableChanges, summary);
  }

  /**
   * Rebuilds an immutable trace while carrying forward nested JS bridge
   * evidence. Keeping this invariant in one place prevents later workflow
   * diagnostics from silently resetting bridgeTraces to its empty default.
   */
  private replaceTrace(
    trace: LegadoExecutionTrace,
    workflow: LegadoWorkflowKind,
    response: ResponseEnvelope,
    variableChanges: string[],
    outputSummary: string,
    bridgeTraces?: LegadoBridgeTrace[]
  ): void {
    const effectiveBridgeTraces: LegadoBridgeTrace[] = bridgeTraces === undefined
      ? trace.bridgeTraces
      : bridgeTraces;
    this.lastTrace = new LegadoExecutionTrace(
      trace.traceId,
      trace.sourceUrl,
      workflow,
      trace.request,
      response,
      variableChanges.slice(),
      outputSummary,
      effectiveBridgeTraces.slice()
    );
  }

  private mergeBridgeTraces(
    existing: LegadoBridgeTrace[],
    observed: LegadoBridgeTrace[]
  ): LegadoBridgeTrace[] {
    const merged: LegadoBridgeTrace[] = existing.slice();
    for (let index = 0; index < observed.length; index++) {
      const trace = observed[index];
      let duplicate = false;
      for (let existingIndex = 0; existingIndex < merged.length; existingIndex++) {
        const current = merged[existingIndex];
        if (current.id === trace.id && current.type === trace.type &&
          current.method === trace.method && current.code === trace.code &&
          current.success === trace.success && current.bodyLength === trace.bodyLength) {
          duplicate = true;
          break;
        }
      }
      if (!duplicate) {
        merged.push(trace);
      }
    }
    return merged;
  }

  private createBookInfoSeed(bookUrl: string, requestUrlTemplate: string): LegadoBook {
    return {
      id: `${this.compiled.source.bookSourceUrl}:${bookUrl}`,
      origin: this.compiled.source.bookSourceUrl,
      originName: this.compiled.source.bookSourceName,
      bookUrl: bookUrl,
      requestUrlTemplate: requestUrlTemplate,
      requestCarrier: new LegadoRequestCarrier(
        this.compiled.source.bookSourceUrl,
        bookUrl,
        requestUrlTemplate,
        'book_info'
      ),
      name: '',
      author: '',
      type: this.compiled.source.bookSourceType
    };
  }

  private createBookJsBinding(book: LegadoBook): Record<string, string> {
    const binding = this.createEmptyJsBindingRecord();
    binding.id = book.id;
    binding.origin = book.origin;
    binding.originName = book.originName;
    binding.bookUrl = book.bookUrl;
    binding.name = book.name;
    binding.author = book.author;
    binding.type = String(book.type);
    if (book.kind !== undefined) binding.kind = book.kind;
    if (book.intro !== undefined) binding.intro = book.intro;
    if (book.coverUrl !== undefined) binding.coverUrl = book.coverUrl;
    if (book.tocUrl !== undefined) binding.tocUrl = book.tocUrl;
    if (book.latestChapterTitle !== undefined) binding.latestChapterTitle = book.latestChapterTitle;
    if (book.wordCount !== undefined) binding.wordCount = book.wordCount;
    if (book.updateTime !== undefined) binding.updateTime = String(book.updateTime);
    if (book.variable !== undefined) binding.variable = book.variable;
    if (book.isPrivate !== undefined) binding.isPrivate = String(book.isPrivate);
    if (book.isNSFW !== undefined) binding.isNSFW = String(book.isNSFW);
    return binding;
  }

  private createChapterJsBinding(chapter: LegadoChapter): Record<string, string> {
    const binding = this.createEmptyJsBindingRecord();
    binding.id = chapter.id;
    binding.bookUrl = chapter.bookUrl;
    binding.url = chapter.url;
    binding.title = chapter.title;
    binding.index = String(chapter.index);
    if (chapter.isVolume !== undefined) binding.isVolume = String(chapter.isVolume);
    if (chapter.isVip !== undefined) binding.isVip = String(chapter.isVip);
    if (chapter.isPay !== undefined) binding.isPay = String(chapter.isPay);
    if (chapter.updateTime !== undefined) binding.updateTime = String(chapter.updateTime);
    if (chapter.variable !== undefined) binding.variable = chapter.variable;
    if (chapter.tag !== undefined) binding.tag = chapter.tag;
    return binding;
  }

  private createEmptyJsBindingRecord(): Record<string, string> {
    return SafeUtils.parseObj('{}') as Record<string, string>;
  }

  private createJsExecutionBinding(
    book: LegadoBook | undefined,
    chapter: LegadoChapter | undefined,
    key: string,
    page: number
  ): LegadoRuleJsExecutionBinding {
    return new LegadoRuleJsExecutionBinding(
      this.compiled.source,
      book === undefined ? undefined : this.createBookJsBinding(book),
      chapter === undefined ? undefined : this.createChapterJsBinding(chapter),
      key,
      page
    );
  }

  private createAnalyzer(
    content: string,
    baseUrl: string,
    book?: LegadoBook,
    chapter?: LegadoChapter,
    key: string = '',
    page: number = 1
  ): LegadoRuleAnalyzer {
    const analyzer = new LegadoRuleAnalyzer();
    analyzer.setJsLib(this.compiled.source.jsLib || '');
    analyzer.setContent(content, baseUrl);
    analyzer.setJsExecutionBinding(this.createJsExecutionBinding(book, chapter, key, page));
    const variables = this.planner.getVariablesSnapshot();
    variables.forEach((value: string, key: string): void => {
      analyzer.put(key, value);
    });
    return analyzer;
  }

  private ruleUsesJavaScript(rule: string | undefined): boolean {
    if (rule === undefined) {
      return false;
    }
    const normalized = rule.toLowerCase();
    return normalized.includes('@js:') || normalized.includes('<js>');
  }

  /**
   * Keeps source-rule provenance observable without retaining rule text in a
   * UI trace. This distinguishes a lost field from a JavaScript runtime error.
   */
  private getSearchBookUrlRuleDiagnostic(rule: string | undefined): string {
    if (rule === undefined || rule.trim().length === 0) {
      return 'bookUrlRule=missing;bookUrlRuleLength=0;bookUrlRuleJavaScript=false;bookUrlRulePostfixJs=false';
    }
    const normalized = rule.trim().toLowerCase();
    const postfixJs = normalized.indexOf('@js:') > 0;
    return `bookUrlRule=present;bookUrlRuleLength=${rule.length};` +
      `bookUrlRuleJavaScript=${this.ruleUsesJavaScript(rule)};bookUrlRulePostfixJs=${postfixJs}`;
  }

  private syncVariables(analyzer: LegadoRuleAnalyzer): void {
    const variables = analyzer.getVariablesSnapshot();
    const keys = Object.keys(variables);
    const changes: string[] = [];
    for (let i = 0; i < keys.length; i++) {
      this.planner.setVariable(keys[i], variables[keys[i]]);
      changes.push(keys[i]);
    }
    if (this.lastTrace !== null) {
      const mergedBridgeTraces = this.mergeBridgeTraces(
        this.lastTrace.bridgeTraces,
        analyzer.getBridgeTracesSnapshot()
      );
      const bridgeTraceChanged = mergedBridgeTraces.length > this.lastTrace.bridgeTraces.length;
      if (!bridgeTraceChanged && changes.length <= 0) {
        return;
      }
      this.replaceTrace(
        this.lastTrace,
        this.lastTrace.workflow,
        this.lastTrace.response,
        changes.length > 0 ? changes : this.lastTrace.variableChanges,
        this.lastTrace.outputSummary,
        mergedBridgeTraces
      );
    }
  }

  /**
   * Original Legado stores rule data on each SearchBook/Book/BookChapter.
   * Serializing a stable snapshot here keeps java.put/java.get scoped to the
   * selected result instead of leaking the latest concurrent search into a
   * later detail request.
   */
  private serializeVariableSnapshot(variables: Record<string, string>): string {
    const keys = Object.keys(variables).sort();
    const snapshot: Record<string, string> = {};
    for (let index = 0; index < keys.length; index++) {
      snapshot[keys[index]] = String(variables[keys[index]]);
    }
    return JSON.stringify(snapshot);
  }

  getVariableSnapshot(): string {
    return this.serializeVariableSnapshotFromPlanner();
  }

  private serializeVariableSnapshotFromPlanner(): string {
    const variables: Record<string, string> = {};
    this.planner.getVariablesSnapshot().forEach((value: string, key: string): void => {
      variables[key] = value;
    });
    return this.serializeVariableSnapshot(variables);
  }

  private restoreBookVariableSnapshot(variable?: string): void {
    if (variable === undefined || variable.trim().length === 0) {
      return;
    }
    try {
      const parsed = JSON.parse(variable) as Record<string, string>;
      const keys = Object.keys(parsed);
      for (let index = 0; index < keys.length; index++) {
        const key = keys[index];
        const value = parsed[key];
        if (key.trim().length > 0 && value !== undefined && value !== null) {
          this.planner.setVariable(key, String(value));
        }
      }
    } catch (_error) {
      logger.warn(TAG, 'V2 书籍变量快照解析失败，保持当前作用域');
    }
  }

  private refreshTraceOutput(summary: string): void {
    if (this.lastTrace !== null) {
      this.replaceTrace(
        this.lastTrace,
        this.lastTrace.workflow,
        this.lastTrace.response,
        this.lastTrace.variableChanges,
        summary
      );
    }
  }

  /**
   * ArkWeb can time out before it reports a main-document status. Preserve
   * only the executor's fixed, URL-free lifecycle grammar; every other error
   * stays classified by errorCode alone so responses and credentials cannot
   * leak into a persisted source verification summary.
   */
  private getSearchFailureSummary(response: ResponseEnvelope): string {
    const prefix: string = `search_failed:${response.errorCode}`;
    if (response.errorCode !== LegadoExecutionErrorCode.WEB_VIEW) {
      return prefix;
    }
    const timeoutMarker: string = 'WEBVIEW_TIMEOUT;';
    const errorMarker: string = 'WEBVIEW_ERROR;';
    const timeoutIndex: number = response.errorMessage.indexOf(timeoutMarker);
    const errorIndex: number = response.errorMessage.indexOf(errorMarker);
    const markerIndex: number = timeoutIndex >= 0 ? timeoutIndex : errorIndex;
    if (markerIndex < 0) {
      return prefix;
    }
    const diagnostic: string = response.errorMessage.substring(markerIndex).trim();
    const safePattern: RegExp = /^WEBVIEW_(TIMEOUT|ERROR);ownership=(active|queued);stage=[a-z_]+;pageBegin=\d+;targetBegin=\d+;runtimeBegin=\d+;nonRuntimeBegin=\d+;pageEnd=\d+;mainFrameError=\d+;(httpStatus=\d+|errorCode=-?\d+)$/;
    return safePattern.test(diagnostic) ? `${prefix};${diagnostic}` : prefix;
  }

  /** Converts the ArkWeb fixed DOM grammar into trace-safe search fields. */
  private getSearchDomDiagnostic(message: string): string {
    const safePattern: RegExp = /^DOM_STATE;ready=(loading|interactive|complete);table=(\d+);tr=(\d+);bodyChildren=(\d+);htmlLength=(\d+)$/;
    const match = safePattern.exec(message);
    if (match === null) {
      return '';
    }
    return `;domReady=${match[1]};domTable=${match[2]};domTr=${match[3]};domBodyChildren=${match[4]};domHtmlLength=${match[5]}`;
  }

  /**
   * Stores only counts and a truncated digest. The raw response and rule values
   * remain in memory and are never written into persistent compatibility evidence.
   */
  private async buildBookInfoDiagnostic(
    analyzer: LegadoRuleAnalyzer,
    rule: LegadoBookInfoRule,
    response: ResponseEnvelope,
    name: string,
    author: string,
    kind: string,
    intro: string,
    coverUrl: string,
    tocUrl: string,
    lastChapter: string,
    wordCount: string,
    tocVariableFingerprintBefore: string,
    tocVariableFingerprintAfter: string
  ): Promise<LegadoBookInfoDiagnostic> {
    const fields: string[] = ['name', 'author', 'kind', 'intro', 'cover', 'toc', 'last', 'wordCount'];
    const rules: string[] = [
      rule.name || '', rule.author || '', rule.kind || '', rule.intro || '',
      rule.coverUrl || '', rule.tocUrl || '', rule.lastChapter || '', rule.wordCount || ''
    ];
    const values: string[] = [name, author, kind, intro, coverUrl, tocUrl, lastChapter, wordCount];
    let declaredRuleCount = 0;
    let resolvedRuleCount = 0;
    const probeParts: string[] = [];
    for (let index = 0; index < fields.length; index++) {
      const ruleText = rules[index].trim();
      if (ruleText.length <= 0) {
        continue;
      }
      declaredRuleCount++;
      if (values[index].trim().length > 0) {
        resolvedRuleCount++;
      }
      const selectorCount = await this.getRuleSelectorProbeCount(analyzer, ruleText);
      probeParts.push(`${fields[index]}:${selectorCount}/${values[index].trim().length > 0 ? 1 : 0}`);
    }
    const fingerprint = await this.getResponseFingerprint(response.body);
    const responseClass = this.classifyResponseBody(response.body);
    const tocUrlFingerprint = await this.getResponseFingerprint(tocUrl);
    const tocRuleFingerprint = await this.getResponseFingerprint(rule.tocUrl || '');
    const headersVariableFingerprint = await this.getResponseFingerprint(analyzer.getVariableValue('headers'));
    const variableKeys = Object.keys(analyzer.getVariablesSnapshot());
    const bidVariableState = variableKeys.includes('bid') ? 'present' : 'absent';
    const nativeJsShimStatus = await this.getNativeJsShimStatus();
    const requestEvidence = await this.buildRequestHeaderEvidence(response);
    const outputKind = resolvedRuleCount <= 0
      ? 'book_info_metadata_empty'
      : (resolvedRuleCount < declaredRuleCount ? 'book_info_metadata_partial' : 'book_info_metadata_resolved');
    const imageWorkflowOutcome = this.compiled.source.bookSourceType === LegadoBookSourceType.IMAGE &&
      resolvedRuleCount <= 0
      ? 'image_workflow_book_info_empty'
      : 'none';
    const summary = `book_info:rules=${declaredRuleCount};resolved=${resolvedRuleCount};` +
      `selectors=${probeParts.join(',')};body=${response.body.length}:${fingerprint};responseClass=${responseClass};` +
      `tocUrl=${tocUrlFingerprint};tocRule=${tocRuleFingerprint};tocVarsBefore=${tocVariableFingerprintBefore};` +
      `tocVarsAfter=${tocVariableFingerprintAfter};headersVar=${headersVariableFingerprint};bidVar=${bidVariableState};` +
      `nativeJsShim=${nativeJsShimStatus};outputKind=${outputKind};` +
      `imageWorkflowOutcome=${imageWorkflowOutcome};${requestEvidence}`;
    return new LegadoBookInfoDiagnostic(declaredRuleCount, resolvedRuleCount, summary);
  }

  private async getNativeJsShimStatus(): Promise<string> {
    const variables: Record<string, string> = {};
    variables['headers'] = 'fixture-header';
    const context: JsContext = { variables: variables };
    const expressions: string[] = [
      "java.get('headers')",
      "java.encodeURI('a b~')",
      "java.md5Encode('abc')",
      "java.md5Encode('你好')"
    ];
    const expected: string[] = [
      'fixture-header',
      'a+b%7E',
      '900150983cd24fb0d6963f7d28e17f72',
      '7eca689f0d3389d9dea66ae112e5cfd7'
    ];
    let detail = '';
    for (let index = 0; index < expressions.length; index++) {
      const result = await getLegadoJsEngine().execute(expressions[index], context);
      detail += result.success && result.result === expected[index] ? '1' : '0';
    }
    const emptyVariables: Record<string, string> = {};
    const emptyContext: JsContext = { variables: emptyVariables };
    const missingVariable = await getLegadoJsEngine().execute(
      "var headers = 'runtime-only'; java.get('headers')",
      emptyContext
    );
    detail += missingVariable.success && missingVariable.result === '' ? '1' : '0';
    return detail === '11111' ? 'passed' : `failed-${detail}`;
  }

  /**
   * A redacted, deterministic witness for a rule's variable scope. It is
   * intentionally limited to a SHA-256-derived token so compatibility traces
   * can compare evaluation state without persisting source values or cookies.
   */
  private async getVariableScopeFingerprint(variables: Record<string, string>): Promise<string> {
    const keys: string[] = Object.keys(variables);
    keys.sort();
    const entries: string[] = [];
    for (let index = 0; index < keys.length; index++) {
      const key = keys[index];
      entries.push(`${key.length}:${key}:${variables[key].length}:${variables[key]}`);
    }
    return await this.getResponseFingerprint(entries.join('|'));
  }

  private async buildBookInfoTransportDiagnostic(
    rule: LegadoBookInfoRule,
    response: ResponseEnvelope
  ): Promise<string> {
    const rules: string[] = [
      rule.name || '', rule.author || '', rule.kind || '', rule.intro || '',
      rule.coverUrl || '', rule.tocUrl || '', rule.lastChapter || '', rule.wordCount || ''
    ];
    let declaredRuleCount = 0;
    for (let index = 0; index < rules.length; index++) {
      if (rules[index].trim().length > 0) {
        declaredRuleCount++;
      }
    }
    const fingerprint = await this.getResponseFingerprint(response.body);
    const responseClass = this.classifyResponseBody(response.body);
    const requestEvidence = await this.buildRequestHeaderEvidence(response);
    return `book_info:rules=${declaredRuleCount};resolved=0;selectors=transport_unavailable;` +
      `body=${response.body.length}:${fingerprint};responseClass=${responseClass};${requestEvidence}`;
  }

  /** Keep only a comparable effective-request footprint for cross-engine evidence. */
  private async buildRequestHeaderEvidence(response: ResponseEnvelope): Promise<string> {
    const method = this.lastTrace === null ? 'unknown' : this.lastTrace.request.method.toUpperCase();
    const parts: string[] = [];
    const headerNames: string[] = [];
    for (let index = 0; index < response.requestHeaders.length; index++) {
      const header = response.requestHeaders[index];
      const name = header.name.trim().toLowerCase();
      if (!/^[a-z0-9-]{1,64}$/.test(name)) {
        continue;
      }
      const valueFingerprint = await this.getResponseFingerprint(header.value);
      parts.push(`${name}=${valueFingerprint}`);
      if (headerNames.indexOf(name) < 0) {
        headerNames.push(name);
      }
    }
    parts.sort();
    headerNames.sort();
    const fingerprint = await this.getResponseFingerprint(parts.join('\n'));
    const safeMethod = /^[A-Z]{1,12}$/.test(method) ? method : 'unknown';
    const serializedNames = headerNames.length > 0 ? headerNames.join(',') : 'empty';
    return `reqMethod=${safeMethod};reqHeaderCount=${parts.length};reqHeaderNames=${serializedNames};reqHeaderFingerprint=${fingerprint}`;
  }

  private async getRuleSelectorProbeCount(analyzer: LegadoRuleAnalyzer, rule: string): Promise<number> {
    const primaryRule = rule.indexOf('##') >= 0 ? rule.substring(0, rule.indexOf('##')) : rule;
    const alternatives = primaryRule.split('||');
    for (let index = 0; index < alternatives.length; index++) {
      const alternative = alternatives[index].trim();
      const terminalAt = alternative.lastIndexOf('@');
      const selector = terminalAt > 0 ? alternative.substring(0, terminalAt) : alternative;
      if (selector.trim().length <= 0) {
        continue;
      }
      try {
        const elements = await analyzer.getElementsAsync(selector);
        if (elements.length > 0) {
          return elements.length;
        }
      } catch (error) {
        logger.warn(TAG, `详情规则探针失败: ${String(error)}`);
      }
    }
    return 0;
  }

  private async getResponseFingerprint(body: string): Promise<string> {
    if (body.length <= 0) {
      return 'empty';
    }
    try {
      return (await sha256Hash(body)).substring(0, 16);
    } catch (error) {
      logger.warn(TAG, `详情响应摘要计算失败: ${String(error)}`);
      return 'digest_error';
    }
  }

  /**
   * Produces the same host-and-path-only target identity used by persisted
   * network evidence. Query parameters are deliberately excluded because a
   * source may carry transient credentials there.
   */
  private async getTraceTargetFingerprint(value: string): Promise<string> {
    const trimmed = value.trim();
    if (trimmed.length <= 0) {
      return 'empty';
    }
    const match = trimmed.match(/^[a-z][a-z0-9+.-]*:\/\/([^\/?#]+)(\/[^?#]*)?/i);
    if (match === null || match[1].length <= 0) {
      return 'empty';
    }
    const path = match[2] === undefined || match[2].length <= 0 ? '/' : match[2];
    try {
      return await sha256Hash(`${match[1].toLowerCase()}${path}`);
    } catch (error) {
      logger.warn(TAG, `搜索详情目标摘要计算失败: ${String(error)}`);
      return 'digest_error';
    }
  }

  /** Builds a fixed, redacted request witness for search trace comparison. */
  private async buildSearchNetworkDiagnostic(response: ResponseEnvelope): Promise<string> {
    const request = this.lastTrace === null ? null : this.lastTrace.request;
    const target = request === null ? 'empty' : await this.getTraceTargetFingerprint(request.url);
    let userAgent = '';
    for (let index = 0; index < response.requestHeaders.length; index++) {
      const header = response.requestHeaders[index];
      if (header.name.trim().toLowerCase() === 'user-agent') {
        userAgent = header.value;
        break;
      }
    }
    let contentType = '';
    for (let index = 0; index < response.responseHeaders.length; index++) {
      const header = response.responseHeaders[index];
      if (header.name.trim().toLowerCase() === 'content-type') {
        contentType = header.value.split(';')[0].trim().toLowerCase();
        break;
      }
    }
    const safeContentType = /^[a-z0-9.+-]+\/[a-z0-9.+-]+$/.test(contentType) ? contentType : 'empty';
    const bodyFingerprint = await this.getResponseFingerprint(response.body);
    const responseClass = this.classifyResponseBody(response.body);
    const requestEvidence = await this.buildRequestHeaderEvidence(response);
    return `reqTarget=${target};ua=${await this.getTraceValueFingerprint(userAgent)};` +
      `contentType=${safeContentType};redirects=${Math.max(0, response.redirectChain.length - 1)};` +
      `body=${response.body.length}:${bodyFingerprint};responseClass=${responseClass};${requestEvidence}`;
  }

  private async getTraceValueFingerprint(value: string): Promise<string> {
    if (value.length <= 0) {
      return 'empty';
    }
    try {
      return await sha256Hash(value);
    } catch (error) {
      logger.warn(TAG, `请求值摘要计算失败: ${String(error)}`);
      return 'digest_error';
    }
  }

  /**
   * Persistent trace evidence must never retain server text. Classify only the
   * response shape needed to distinguish a generic HTML page from common
   * access-control paths while keeping the raw body in memory.
   */
  private classifyResponseBody(body: string): string {
    const normalized = body.trim().toLowerCase();
    if (normalized.length === 0) {
      return 'empty';
    }
    const looksHtml = normalized.indexOf('<html') >= 0 || normalized.indexOf('<!doctype html') >= 0;
    if (!looksHtml) {
      return 'non_html';
    }
    if (normalized.indexOf('captcha') >= 0 || normalized.indexOf('verify you are human') >= 0 ||
      normalized.indexOf('security challenge') >= 0) {
      return 'html_challenge';
    }
    if (normalized.indexOf('too many requests') >= 0 || normalized.indexOf('rate limit') >= 0) {
      return 'html_rate_limited';
    }
    if (normalized.indexOf('access denied') >= 0 || normalized.indexOf('forbidden') >= 0 ||
      normalized.indexOf('拒绝访问') >= 0) {
      return 'html_access_denied';
    }
    if (normalized.indexOf('login') >= 0 || normalized.indexOf('sign in') >= 0 || normalized.indexOf('登录') >= 0) {
      return 'html_login';
    }
    return 'html_generic';
  }

  /**
   * A successful HTTP status does not make a login/challenge page readable
   * source content. Gate protected HTML before any workflow rule runs so it
   * cannot become a false-positive book, chapter list, or reader body.
   */
  private async blockProtectedResponse(workflow: LegadoWorkflowKind, response: ResponseEnvelope): Promise<boolean> {
    const responseClass = this.classifyResponseBody(response.body);
    let errorCode: LegadoExecutionErrorCode | null = null;
    if (responseClass === 'html_login' || responseClass === 'html_challenge') {
      errorCode = LegadoExecutionErrorCode.NEEDS_INTERACTION;
    } else if (responseClass === 'html_access_denied' || responseClass === 'html_rate_limited') {
      errorCode = LegadoExecutionErrorCode.HTTP;
    }
    if (errorCode === null) {
      return false;
    }
    if (this.lastTrace === null) {
      return true;
    }
    const trace = this.lastTrace;
    const bodyFingerprint = await this.getResponseFingerprint(response.body);
    const requestEvidence = await this.buildRequestHeaderEvidence(response);
    const bodyEvidence = `body=${response.body.length}:${bodyFingerprint};responseClass=${responseClass};${requestEvidence}`;
    let blockedSummary = `protected_response:${responseClass};semantic=blocked;${bodyEvidence}`;
    if (workflow === LegadoWorkflowKind.BOOK_INFO) {
      blockedSummary = `book_info:rules=0;resolved=0;selectors=protected_response;${bodyEvidence};protected_response:${responseClass};semantic=blocked`;
    } else if (workflow === LegadoWorkflowKind.TOC) {
      blockedSummary = `toc:0;matched=0;missingUrl=0;pages=0;${bodyEvidence};protected_response:${responseClass};semantic=blocked`;
    }
    const protectedResponse = new ResponseEnvelope(
      response.traceId,
      response.body,
      response.finalUrl,
      response.finalUrlObservation,
      response.statusCode,
      response.requestHeaders,
      response.responseHeaders,
      response.cookiesChanged,
      response.redirectChain,
      response.transport,
      response.elapsedMs,
      errorCode,
      `PROTECTED_RESPONSE:${responseClass}`
    );
    this.replaceTrace(trace, workflow, protectedResponse, trace.variableChanges, blockedSummary);
    return true;
  }

  private markBookInfoRuleFailure(response: ResponseEnvelope, summary: string): void {
    if (this.lastTrace === null) {
      return;
    }
    const failedResponse = new ResponseEnvelope(
      response.traceId,
      response.body,
      response.finalUrl,
      response.finalUrlObservation,
      response.statusCode,
      response.requestHeaders,
      response.responseHeaders,
      response.cookiesChanged,
      response.redirectChain,
      response.transport,
      response.elapsedMs,
      LegadoExecutionErrorCode.RULE,
      'BOOK_INFO_RULES_EMPTY'
    );
    this.replaceTrace(
      this.lastTrace,
      this.lastTrace.workflow,
      failedResponse,
      this.lastTrace.variableChanges,
      `${summary};semantic=empty`
    );
  }

  private async readDownloadCandidates(
    analyzer: LegadoRuleAnalyzer,
    rule: string,
    baseUrl: string
  ): Promise<LegadoFileDownloadCandidate[]> {
    if (rule.trim().length === 0) {
      return [];
    }
    const values = await analyzer.getElementsAsync(rule);
    const candidates: LegadoFileDownloadCandidate[] = [];
    if (values.length > 0) {
      for (let i = 0; i < values.length; i++) {
        const url = this.resolveUrl(values[i], baseUrl);
        if (url.length > 0) {
          candidates.push(new LegadoFileDownloadCandidate(url, `download-${i + 1}`));
        }
      }
      return candidates;
    }
    const valuesByUrlRule = await analyzer.getUrlStringListAsync(rule);
    for (let i = 0; i < valuesByUrlRule.length; i++) {
      const url = this.resolveUrl(valuesByUrlRule[i], baseUrl);
      if (url.length > 0) {
        candidates.push(new LegadoFileDownloadCandidate(url, `download-${i + 1}`));
      }
    }
    return candidates;
  }

  private async formatChapterTitle(
    script: string,
    title: string,
    baseUrl: string,
    book: LegadoBook,
    page: number
  ): Promise<string> {
    const analyzer = this.createAnalyzer(title, baseUrl, book, undefined, '', page);
    const result = await analyzer.getStringAsync(`<js>var result = ${JSON.stringify(title)}; ${script}</js>`);
    return result.trim();
  }

  /**
   * Original Legado obtains every next-content URL before it aggregates the
   * chapter.  Keep the source order and deduplicate in the caller; this is
   * deliberately a workflow concern rather than a transport retry.
   */
  private async getContentNextUrls(
    analyzer: LegadoRuleAnalyzer,
    rule: string,
    baseUrl: string
  ): Promise<string[]> {
    if (rule.trim().length <= 0) {
      return [];
    }
    const values = await analyzer.getUrlStringListAsync(rule);
    const urls: string[] = [];
    for (let index = 0; index < values.length; index++) {
      const lines = values[index].split(/\r?\n/);
      for (let lineIndex = 0; lineIndex < lines.length; lineIndex++) {
        const url = this.resolveRequestUrlTemplate(lines[lineIndex], baseUrl);
        if (url.length > 0 && !urls.includes(url)) {
          urls.push(url);
        }
      }
    }
    return urls;
  }

  /**
   * Mirrors AnalyzeRule.getStringList(..., isUrl = true) for toc pagination.
   * A single value remains a linear pagination chain; several values are
   * preserved for the caller to process as sibling pages.
   */
  private async getTocNextUrls(
    analyzer: LegadoRuleAnalyzer,
    rule: string,
    baseUrl: string
  ): Promise<string[]> {
    if (rule.trim().length <= 0) {
      return [];
    }
    const values = await analyzer.getUrlStringListAsync(rule);
    const urls: string[] = [];
    for (let index = 0; index < values.length; index++) {
      const lines = values[index].split(/\r?\n/);
      for (let lineIndex = 0; lineIndex < lines.length; lineIndex++) {
        const url = this.resolveRequestUrlTemplate(lines[lineIndex], baseUrl);
        if (url.length > 0 && !urls.includes(url)) {
          urls.push(url);
        }
      }
    }
    return urls;
  }

  /**
   * BookContent applies ruleContent.replaceRegex once after all content pages
   * have been normalized and joined. Running it per page is observably wrong
   * for cross-page patterns and differs from upstream Legado semantics.
   */
  private async applyFinalContentReplacement(
    content: string,
    replaceRule: string,
    chapterTitle: string,
    baseUrl: string
  ): Promise<string> {
    if (content.length <= 0 || replaceRule.trim().length <= 0) {
      return content;
    }
    const lines = content.split(/\r?\n/);
    const normalizedLines: string[] = [];
    for (let index = 0; index < lines.length; index++) {
      normalizedLines.push(lines[index].trim());
    }
    const preparedContent = normalizedLines.join('\n');
    const normalizedRule = replaceRule.trim();
    if (normalizedRule.startsWith('##')) {
      return this.applySimpleContentReplacement(preparedContent, normalizedRule);
    }
    const analyzer = this.createAnalyzer(preparedContent, baseUrl);
    analyzer.put('chapter.title', chapterTitle);
    analyzer.put('chapterTitle', chapterTitle);
    const ruleForAnalyzer = normalizedRule.toLowerCase().startsWith('@js:')
      ? `<js>var result = ${JSON.stringify(preparedContent)}; ${normalizedRule.substring(4)}</js>`
      : normalizedRule;
    const result = await analyzer.getStringAsync(ruleForAnalyzer);
    this.syncVariables(analyzer);
    return result;
  }

  private applySimpleContentReplacement(content: string, rule: string): string {
    const rest = rule.substring(2);
    const separator = rest.indexOf('##');
    const pattern = separator >= 0 ? rest.substring(0, separator) : rest;
    let replacement = separator >= 0 ? rest.substring(separator + 2) : '';
    let replaceFirst = false;
    if (replacement.endsWith('#')) {
      replaceFirst = true;
      replacement = replacement.substring(0, replacement.length - 1);
    }
    if (pattern.length <= 0) {
      return content;
    }
    try {
      return content.replace(new RegExp(pattern, replaceFirst ? '' : 'g'), replacement);
    } catch (_error) {
      if (replaceFirst) {
        const index = content.indexOf(pattern);
        return index < 0
          ? content
          : content.substring(0, index) + replacement + content.substring(index + pattern.length);
      }
      return content.split(pattern).join(replacement);
    }
  }

  private resolveUrl(value: string, baseUrl: string): string {
    const trimmed = value.trim();
    if (trimmed.length === 0) {
      return '';
    }
    return this.resolveUrlWithoutOptions(trimmed, baseUrl);
  }

  /**
   * Resolve only the identity segment. AnalyzeUrl must not see the trailing
   * option JSON here because its `js` member and other side effects belong to
   * the request-owning workflow, not Search/Explore extraction.
   */
  private resolveUrlWithoutOptions(value: string, baseUrl: string): string {
    if (value.startsWith('data:')) {
      return value;
    }
    const analyzer = new LegadoUrlAnalyzer(baseUrl, this.compiled.source.bookSourceUrl, this.compiled.source.jsLib || '');
    const separator = analyzer.findOptionSeparator(value);
    const identityValue = separator.found ? value.substring(0, separator.index).trim() : value;
    const parsed = analyzer.analyzeUrl(identityValue);
    return parsed.url || identityValue;
  }

  /**
   * Resolves only the URL segment and retains the completed trailing option.
   * Original AnalyzeRule.getString(isUrl=true) has this separation; AnalyzeUrl
   * must not consume options until the request-owning workflow dispatches.
   */
  private resolveRequestUrlTemplate(value: string, baseUrl: string): string {
    const trimmed = value.trim();
    if (trimmed.length === 0) {
      return '';
    }
    if (trimmed.startsWith('data:')) {
      return trimmed;
    }
    const analyzer = new LegadoUrlAnalyzer(baseUrl, this.compiled.source.bookSourceUrl, this.compiled.source.jsLib || '');
    const separator = analyzer.findOptionSeparator(trimmed);
    if (!separator.found) {
      return this.resolveUrl(trimmed, baseUrl);
    }
    const resolvedUrl = this.resolveUrlWithoutOptions(trimmed.substring(0, separator.index), baseUrl);
    if (resolvedUrl.length === 0) {
      return '';
    }
    return resolvedUrl + trimmed.substring(separator.index);
  }

  /** Mirrors BookList's LinkedHashSet<SearchBook> plus optional '-' reversal. */
  private finalizeSearchBooks(candidates: LegadoSearchBook[], reverse: boolean): LegadoSearchBook[] {
    const uniqueBooks: LegadoSearchBook[] = [];
    const seenBookUrls: Set<string> = new Set<string>();
    for (let index = 0; index < candidates.length; index++) {
      const candidate: LegadoSearchBook = candidates[index];
      if (seenBookUrls.has(candidate.bookUrl)) {
        continue;
      }
      seenBookUrls.add(candidate.bookUrl);
      uniqueBooks.push(candidate);
    }
    if (reverse) {
      uniqueBooks.reverse();
    }
    return uniqueBooks;
  }

  private resolveBoolean(value: string): boolean {
    const normalized = value.trim().toLowerCase();
    return normalized === 'true' || normalized === '1' || normalized === 'yes' || normalized === '是';
  }

  private parseTime(value: string): number | undefined {
    const parsed = Number(value);
    return Number.isFinite(parsed) && parsed > 0 ? parsed : undefined;
  }
}

/** Adapter with the method names used by the current source manager. */
export class LegadoV2SourceExecutor {
  private readonly workflow: LegadoWorkflowOrchestrator;

  constructor(compiled: CompiledBookSource) {
    this.workflow = new LegadoWorkflowOrchestrator(compiled);
  }

  async search(
    keyword: string,
    page: number = 1,
    cancellationToken?: LegadoExecutionCancellationToken,
    executionOptions?: LegadoSearchExecutionOptions
  ): Promise<LegadoSearchBook[]> {
    return (await this.searchWithTrace(keyword, page, cancellationToken, executionOptions)).books;
  }

  /**
   * A workflow result owns the trace produced by that exact invocation.  Call
   * sites which persist user-path evidence must use this instead of reading a
   * mutable executor-wide "last" trace after an await boundary.
   */
  async searchWithTrace(
    keyword: string,
    page: number = 1,
    cancellationToken?: LegadoExecutionCancellationToken,
    executionOptions?: LegadoSearchExecutionOptions
  ): Promise<LegadoWorkflowSearchResult> {
    return await this.workflow.search(keyword, page, cancellationToken, executionOptions);
  }

  async explore(
    exploreUrl: string,
    page: number = 1,
    cancellationToken?: LegadoExecutionCancellationToken
  ): Promise<LegadoSearchBook[]> {
    return (await this.exploreWithTrace(exploreUrl, page, cancellationToken)).books;
  }

  async exploreWithTrace(
    exploreUrl: string,
    page: number = 1,
    cancellationToken?: LegadoExecutionCancellationToken
  ): Promise<LegadoWorkflowSearchResult> {
    return await this.workflow.explore(exploreUrl, page, cancellationToken);
  }

  async getBookInfo(
    bookUrl: string,
    cancellationToken?: LegadoExecutionCancellationToken,
    bookVariable?: string,
    requestUrlTemplate?: string
  ): Promise<LegadoBook | null> {
    return (await this.getBookInfoWithTrace(bookUrl, cancellationToken, bookVariable, requestUrlTemplate)).book;
  }

  async getBookInfoWithTrace(
    bookUrl: string,
    cancellationToken?: LegadoExecutionCancellationToken,
    bookVariable?: string,
    requestUrlTemplate?: string
  ): Promise<LegadoWorkflowBookInfoResult> {
    return await this.workflow.getBookInfo(bookUrl, cancellationToken, bookVariable, requestUrlTemplate);
  }

  getVariableSnapshot(): string {
    return this.workflow.getVariableSnapshot();
  }

  /**
   * Qualification uses the same V2 workflow but retains File candidates so it
   * can report that a downloader handoff is still unsupported when applicable.
   */
  async getBookInfoWithCandidates(
    bookUrl: string,
    bookVariable?: string,
    requestUrlTemplate?: string
  ): Promise<LegadoWorkflowBookInfoResult> {
    return await this.workflow.getBookInfo(bookUrl, undefined, bookVariable, requestUrlTemplate);
  }

  async getChapterList(
    book: LegadoBook,
    cancellationToken?: LegadoExecutionCancellationToken
  ): Promise<LegadoChapter[]> {
    return (await this.getChapterListWithTrace(book, cancellationToken)).chapters;
  }

  async getChapterListWithTrace(
    book: LegadoBook,
    cancellationToken?: LegadoExecutionCancellationToken
  ): Promise<LegadoWorkflowTocResult> {
    return await this.workflow.getChapterList(book, cancellationToken);
  }

  async getContent(
    chapter: LegadoChapter,
    cancellationToken?: LegadoExecutionCancellationToken
  ): Promise<string> {
    return (await this.getContentWithTrace(chapter, cancellationToken)).content;
  }

  async getContentWithTrace(
    chapter: LegadoChapter,
    cancellationToken?: LegadoExecutionCancellationToken
  ): Promise<LegadoWorkflowContentResult> {
    return await this.workflow.getContent(chapter, cancellationToken);
  }

  getExploreKinds(): LegadoExploreKind[] {
    return this.workflow.getExploreKinds();
  }

  async getExploreKindsAsync(
    cancellationToken?: LegadoExecutionCancellationToken
  ): Promise<LegadoExploreKind[]> {
    return await this.workflow.getExploreKindsAsync(cancellationToken);
  }

  getLastTrace(): LegadoExecutionTrace | null {
    return this.workflow.getLastTrace();
  }

  createWorkflowTimeoutTrace(workflow: LegadoWorkflowKind, timeoutMs: number): LegadoExecutionTrace {
    return this.workflow.createWorkflowTimeoutTrace(workflow, timeoutMs);
  }
}
