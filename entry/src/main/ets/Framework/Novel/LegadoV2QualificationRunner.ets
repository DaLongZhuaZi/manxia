/**
 * Real-source V2 qualification runner.
 *
 * It executes the same V2 executor used by normal traffic, records only
 * redacted workflow facts, and writes a verification record only after every
 * required workflow succeeds.  It never switches a global policy itself.
 */

import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { LegadoBook, LegadoChapter, LegadoExploreKind, LegadoSearchBook } from './LegadoSourceTypes';
import { LegadoContentSemantics } from './LegadoContentSemantics';
import { LegadoV2SourceExecutor } from './LegadoWorkflowOrchestrator';
import { getNovelSourceManager, NovelSourceManager } from './NovelSourceManager';
import {
  LegadoExecutionErrorCode,
  LegadoExecutionTrace,
  LegadoWorkflowKind
} from './LegadoCompatibilityTypes';

const TAG = 'LegadoV2QualificationRunner';

export enum LegadoV2QualificationWorkflowStatus {
  PASSED = 'passed',
  FAILED = 'failed',
  UNSUPPORTED = 'unsupported'
}

export class LegadoV2QualificationWorkflowResult {
  readonly workflow: LegadoWorkflowKind;
  readonly status: LegadoV2QualificationWorkflowStatus;
  readonly errorCode: LegadoExecutionErrorCode;
  readonly outputCount: number;
  readonly traceDigest: string;

  constructor(
    workflow: LegadoWorkflowKind,
    status: LegadoV2QualificationWorkflowStatus,
    errorCode: LegadoExecutionErrorCode,
    outputCount: number,
    traceDigest: string
  ) {
    this.workflow = workflow;
    this.status = status;
    this.errorCode = errorCode;
    this.outputCount = outputCount;
    this.traceDigest = traceDigest;
  }
}

export class LegadoV2QualificationResult {
  readonly sourceId: string;
  readonly sourceName: string;
  readonly requiredWorkflows: LegadoWorkflowKind[];
  readonly workflowResults: LegadoV2QualificationWorkflowResult[];
  readonly verificationRecorded: boolean;
  readonly passed: boolean;
  readonly summary: string;

  constructor(
    sourceId: string,
    sourceName: string,
    requiredWorkflows: LegadoWorkflowKind[],
    workflowResults: LegadoV2QualificationWorkflowResult[],
    verificationRecorded: boolean,
    passed: boolean,
    summary: string
  ) {
    this.sourceId = sourceId;
    this.sourceName = sourceName;
    this.requiredWorkflows = requiredWorkflows;
    this.workflowResults = workflowResults;
    this.verificationRecorded = verificationRecorded;
    this.passed = passed;
    this.summary = summary;
  }
}

class LegadoV2QualificationBookInfoValue {
  readonly book: LegadoBook | null;
  readonly fileCandidateCount: number;

  constructor(book: LegadoBook | null, fileCandidateCount: number) {
    this.book = book;
    this.fileCandidateCount = fileCandidateCount;
  }
}

/** Executes and qualifies a source without retaining response content. */
export class LegadoV2QualificationRunner {
  private readonly sourceManager: NovelSourceManager;

  constructor(sourceManager: NovelSourceManager = getNovelSourceManager()) {
    this.sourceManager = sourceManager;
  }

  async qualify(sourceId: string, keyword: string): Promise<LegadoV2QualificationResult> {
    const source = this.sourceManager.getSource(sourceId);
    const required = this.sourceManager.getRequiredV2VerificationWorkflows(sourceId);
    if (source === null) {
      return new LegadoV2QualificationResult(
        sourceId,
        '',
        required,
        [],
        false,
        false,
        '未找到书源，无法执行 V2 资格验证。'
      );
    }

    const executor = this.sourceManager.createV2DiagnosticExecutor(sourceId);
    if (executor === null) {
      return new LegadoV2QualificationResult(
        sourceId,
        source.bookSourceName,
        required,
        [],
        false,
        false,
        '书源没有可直接运行的无损 V2 编译结果。'
      );
    }

    if (keyword.trim().length === 0) {
      return new LegadoV2QualificationResult(
        sourceId,
        source.bookSourceName,
        required,
        [],
        false,
        false,
        '资格验证需要非空搜索关键词。'
      );
    }

    const results: LegadoV2QualificationWorkflowResult[] = [];
    let selectedBook: LegadoSearchBook | null = null;
    let detailBook: LegadoBook | null = null;
    let selectedChapter: LegadoChapter | null = null;
    let fileCandidateCount: number = 0;

    if (required.includes(LegadoWorkflowKind.SEARCH)) {
      selectedBook = await this.runSearch(executor, keyword, results);
    }

    const requiresDetail: boolean = required.includes(LegadoWorkflowKind.BOOK_INFO) ||
      required.includes(LegadoWorkflowKind.TOC) ||
      required.includes(LegadoWorkflowKind.CONTENT) ||
      required.includes(LegadoWorkflowKind.FILE);
    if (requiresDetail) {
      if (selectedBook === null) {
        this.addDependencyFailure(results, LegadoWorkflowKind.BOOK_INFO, '搜索未返回可用书籍，无法进入详情工作流。');
      } else {
        const detailResult = await this.runBookInfo(executor, selectedBook, results);
        detailBook = detailResult.book;
        fileCandidateCount = detailResult.fileCandidateCount;
      }
    }

    if (required.includes(LegadoWorkflowKind.TOC)) {
      if (detailBook === null) {
        this.addDependencyFailure(results, LegadoWorkflowKind.TOC, '详情工作流未返回书籍，无法进入目录工作流。');
      } else {
        selectedChapter = await this.runToc(executor, detailBook, results);
      }
    }

    if (required.includes(LegadoWorkflowKind.CONTENT)) {
      if (selectedChapter === null) {
        this.addDependencyFailure(results, LegadoWorkflowKind.CONTENT, '目录工作流未返回章节，无法进入正文工作流。');
      } else {
        await this.runContent(executor, selectedChapter, source.bookSourceType, results);
      }
    }

    if (required.includes(LegadoWorkflowKind.EXPLORE)) {
      await this.runExplore(executor, results);
    }

    if (required.includes(LegadoWorkflowKind.FILE)) {
      this.addUnsupportedResult(
        results,
        LegadoWorkflowKind.FILE,
        `V2 已识别 ${fileCandidateCount} 个文件候选，但下载器交接尚未实现。`
      );
    }

    if (required.includes(LegadoWorkflowKind.REVIEW)) {
      this.addUnsupportedResult(
        results,
        LegadoWorkflowKind.REVIEW,
        'Review 工作流尚无完整的 V2 消费者。'
      );
    }

    const passedWorkflows = this.collectPassedRequiredWorkflows(required, results);
    const fullyPassed = passedWorkflows.length === required.length;
    let verificationRecorded = false;
    if (fullyPassed) {
      verificationRecorded = await this.sourceManager.recordCompatibilityVerification(
        sourceId,
        passedWorkflows,
        this.buildEvidenceDigest(results)
      );
    }

    const passed = fullyPassed && verificationRecorded;
    for (let i = 0; i < results.length; i++) {
      const workflowResult = results[i];
      logger.info(
        TAG,
        `V2_QUALIFICATION workflow=${workflowResult.workflow};status=${workflowResult.status};` +
        `error=${workflowResult.errorCode};outputs=${workflowResult.outputCount};` +
        `${workflowResult.traceDigest}`
      );
    }
    logger.info(TAG, `V2 资格验证结束: source=${source.bookSourceName}, passed=${passed}, required=${required.length}`);
    return new LegadoV2QualificationResult(
      sourceId,
      source.bookSourceName,
      required,
      results,
      verificationRecorded,
      passed,
      passed ? '全部必需 V2 工作流已完成并已写入哈希绑定验证记录。' : this.buildFailureSummary(required, results)
    );
  }

  private async runSearch(
    executor: LegadoV2SourceExecutor,
    keyword: string,
    results: LegadoV2QualificationWorkflowResult[]
  ): Promise<LegadoSearchBook | null> {
    try {
      const books = await executor.search(keyword, 1);
      const trace = executor.getLastTrace();
      const passed = books.length > 0 && this.isTraceSuccessful(trace);
      results.push(this.createTraceResult(LegadoWorkflowKind.SEARCH, passed, books.length, trace));
      return passed ? books[0] : null;
    } catch (error) {
      logger.warn(TAG, `V2 Search 资格验证异常: ${String(error)}`);
      results.push(this.createExceptionResult(LegadoWorkflowKind.SEARCH));
      return null;
    }
  }

  private async runBookInfo(
    executor: LegadoV2SourceExecutor,
    book: LegadoSearchBook,
    results: LegadoV2QualificationWorkflowResult[]
  ): Promise<LegadoV2QualificationBookInfoValue> {
    try {
      const result = await executor.getBookInfoWithCandidates(
        book.bookUrl,
        book.variable,
        book.requestCarrier?.requestUrlTemplate || book.requestUrlTemplate
      );
      const trace = executor.getLastTrace();
      const passed = result.book !== null && this.isTraceSuccessful(trace);
      results.push(this.createTraceResult(
        LegadoWorkflowKind.BOOK_INFO,
        passed,
        result.book === null ? 0 : 1,
        trace
      ));
      return new LegadoV2QualificationBookInfoValue(
        passed ? result.book : null,
        result.downloadCandidates.length
      );
    } catch (error) {
      logger.warn(TAG, `V2 BookInfo 资格验证异常: ${String(error)}`);
      results.push(this.createExceptionResult(LegadoWorkflowKind.BOOK_INFO));
      return new LegadoV2QualificationBookInfoValue(null, 0);
    }
  }

  private async runToc(
    executor: LegadoV2SourceExecutor,
    book: LegadoBook,
    results: LegadoV2QualificationWorkflowResult[]
  ): Promise<LegadoChapter | null> {
    try {
      const chapters = await executor.getChapterList(book);
      const trace = executor.getLastTrace();
      const passed = chapters.length > 0 && this.isTraceSuccessful(trace);
      results.push(this.createTraceResult(LegadoWorkflowKind.TOC, passed, chapters.length, trace));
      return passed ? chapters[0] : null;
    } catch (error) {
      logger.warn(TAG, `V2 Toc 资格验证异常: ${String(error)}`);
      results.push(this.createExceptionResult(LegadoWorkflowKind.TOC));
      return null;
    }
  }

  private async runContent(
    executor: LegadoV2SourceExecutor,
    chapter: LegadoChapter,
    sourceType: number,
    results: LegadoV2QualificationWorkflowResult[]
  ): Promise<void> {
    try {
      const content = await executor.getContent(chapter);
      const trace = executor.getLastTrace();
      const presentation = LegadoContentSemantics.assessReaderPayload(content, sourceType);
      const passed = presentation.isReadable() && this.isTraceSuccessful(trace);
      if (!presentation.isReadable()) {
        results.push(new LegadoV2QualificationWorkflowResult(
          LegadoWorkflowKind.CONTENT,
          LegadoV2QualificationWorkflowStatus.FAILED,
          LegadoExecutionErrorCode.RULE,
          content.length,
          `${this.buildTraceDigest(trace)};presentation=${presentation.status};visible=${presentation.visibleLength}`
        ));
        return;
      }
      results.push(this.createTraceResult(LegadoWorkflowKind.CONTENT, passed, content.length, trace));
    } catch (error) {
      logger.warn(TAG, `V2 Content 资格验证异常: ${String(error)}`);
      results.push(this.createExceptionResult(LegadoWorkflowKind.CONTENT));
    }
  }

  private async runExplore(
    executor: LegadoV2SourceExecutor,
    results: LegadoV2QualificationWorkflowResult[]
  ): Promise<void> {
    try {
      const kinds: LegadoExploreKind[] = await executor.getExploreKindsAsync();
      if (kinds.length === 0 || kinds[0].url.trim().length === 0) {
        results.push(new LegadoV2QualificationWorkflowResult(
          LegadoWorkflowKind.EXPLORE,
          LegadoV2QualificationWorkflowStatus.FAILED,
          LegadoExecutionErrorCode.RULE,
          0,
          'exploreKinds=0; no request was issued'
        ));
        return;
      }
      const books = await executor.explore(kinds[0].url, 1);
      const trace = executor.getLastTrace();
      const passed = this.isTraceSuccessful(trace);
      results.push(this.createTraceResult(LegadoWorkflowKind.EXPLORE, passed, books.length, trace));
    } catch (error) {
      logger.warn(TAG, `V2 Explore 资格验证异常: ${String(error)}`);
      results.push(this.createExceptionResult(LegadoWorkflowKind.EXPLORE));
    }
  }

  private addDependencyFailure(
    results: LegadoV2QualificationWorkflowResult[],
    workflow: LegadoWorkflowKind,
    reason: string
  ): void {
    results.push(new LegadoV2QualificationWorkflowResult(
      workflow,
      LegadoV2QualificationWorkflowStatus.FAILED,
      LegadoExecutionErrorCode.RULE,
      0,
      reason
    ));
  }

  private addUnsupportedResult(
    results: LegadoV2QualificationWorkflowResult[],
    workflow: LegadoWorkflowKind,
    reason: string
  ): void {
    results.push(new LegadoV2QualificationWorkflowResult(
      workflow,
      LegadoV2QualificationWorkflowStatus.UNSUPPORTED,
      LegadoExecutionErrorCode.UNSUPPORTED_API,
      0,
      reason
    ));
  }

  private createExceptionResult(workflow: LegadoWorkflowKind): LegadoV2QualificationWorkflowResult {
    return new LegadoV2QualificationWorkflowResult(
      workflow,
      LegadoV2QualificationWorkflowStatus.FAILED,
      LegadoExecutionErrorCode.UNKNOWN,
      0,
      'exception; trace unavailable'
    );
  }

  private createTraceResult(
    workflow: LegadoWorkflowKind,
    passed: boolean,
    outputCount: number,
    trace: LegadoExecutionTrace | null
  ): LegadoV2QualificationWorkflowResult {
    const errorCode = trace === null ? LegadoExecutionErrorCode.UNKNOWN : trace.response.errorCode;
    return new LegadoV2QualificationWorkflowResult(
      workflow,
      passed ? LegadoV2QualificationWorkflowStatus.PASSED : LegadoV2QualificationWorkflowStatus.FAILED,
      errorCode,
      outputCount,
      this.buildTraceDigest(trace)
    );
  }

  private isTraceSuccessful(trace: LegadoExecutionTrace | null): boolean {
    return trace !== null && trace.response.isSuccess();
  }

  /** Never includes URL, request body, headers, cookies or response text. */
  private buildTraceDigest(trace: LegadoExecutionTrace | null): string {
    if (trace === null) {
      return 'trace=missing';
    }
    return `workflow=${trace.workflow};transport=${trace.response.transport};http=${trace.response.statusCode};` +
      `elapsedMs=${trace.response.elapsedMs};error=${trace.response.errorCode};` +
      `finalUrl=${trace.response.finalUrlObservation};options=${trace.request.optionTrace.length};` +
      `variables=${trace.variableChanges.length};output=${trace.outputSummary}`;
  }

  private collectPassedRequiredWorkflows(
    required: LegadoWorkflowKind[],
    results: LegadoV2QualificationWorkflowResult[]
  ): LegadoWorkflowKind[] {
    const passed: LegadoWorkflowKind[] = [];
    for (let i = 0; i < required.length; i++) {
      const workflow = required[i];
      const result = this.findWorkflowResult(results, workflow);
      if (result !== null && result.status === LegadoV2QualificationWorkflowStatus.PASSED) {
        passed.push(workflow);
      }
    }
    return passed;
  }

  private findWorkflowResult(
    results: LegadoV2QualificationWorkflowResult[],
    workflow: LegadoWorkflowKind
  ): LegadoV2QualificationWorkflowResult | null {
    for (let i = 0; i < results.length; i++) {
      if (results[i].workflow === workflow) {
        return results[i];
      }
    }
    return null;
  }

  private buildEvidenceDigest(results: LegadoV2QualificationWorkflowResult[]): string {
    const items: string[] = [];
    for (let i = 0; i < results.length; i++) {
      const result = results[i];
      items.push(`${result.workflow}:${result.status}:${result.errorCode}:${result.outputCount}`);
    }
    return items.join('|');
  }

  private buildFailureSummary(
    required: LegadoWorkflowKind[],
    results: LegadoV2QualificationWorkflowResult[]
  ): string {
    const failures: string[] = [];
    for (let i = 0; i < required.length; i++) {
      const workflow = required[i];
      const result = this.findWorkflowResult(results, workflow);
      if (result === null) {
        failures.push(`${workflow}:missing`);
      } else if (result.status !== LegadoV2QualificationWorkflowStatus.PASSED) {
        failures.push(`${workflow}:${result.status}:${result.errorCode}`);
      }
    }
    return failures.length > 0 ? `V2 资格验证未通过：${failures.join(', ')}` : '验证记录写入失败。';
  }
}
