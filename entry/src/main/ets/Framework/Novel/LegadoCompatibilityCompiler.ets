import { sha256Hash } from '../../Utils/CryptoUtils';
import { logger } from '../../Utils/Logger';
import { LegadoBookSource } from './LegadoSourceTypes';
import { LegadoSourceParser } from './LegadoSourceParser';
import { getLegadoJsApiContractRegistry } from './LegadoJsApiContractRegistry';
import {
  CompiledBookSource,
  ImportReport,
  LegadoCompilationBatchResult,
  LegadoCompilationFailure,
  LegadoCapability,
  LegadoCapabilityReport,
  LegadoCompatibilityStatus,
  LegadoDiagnosticSeverity,
  LegadoImportDiagnostic,
  LegadoJsApiStatus,
  LegadoRuleIrNode,
  LegadoRuleNodeKind,
  LegadoRuleSourceLocation,
  LegadoWorkflowKind,
  LegadoCompiledRule,
  RawBookSourceDocument
} from './LegadoCompatibilityTypes';

const TAG = 'LegadoCompatibilityCompiler';

/**
 * Compiles the public Legado JSON DSL without discarding its source document.
 * Dynamic unknown fields are never converted into ArkTS objects: the original
 * UTF-8 JSON is persisted verbatim and only known fields are compiled.
 */
export class LegadoCompatibilityCompiler {
  private static readonly KNOWN_TOP_LEVEL_FIELDS: string[] = [
    'bookSourceUrl', 'bookSourceName', 'bookSourceGroup', 'bookSourceType',
    'bookUrlPattern', 'customOrder', 'enabled', 'enabledExplore', 'jsLib',
    'enabledCookieJar', 'concurrentRate', 'header', 'loginUrl', 'loginUi',
    'loginCheckJs', 'coverDecodeJs', 'bookSourceComment', 'variableComment',
    'lastUpdateTime', 'respondTime', 'weight', 'exploreUrl', 'exploreScreen',
    'ruleExplore', 'searchUrl', 'ruleSearch', 'ruleBookInfo', 'ruleToc',
    'ruleContent', 'ruleReview', 'isNSFW', 'ruleSearchUrl', 'ruleFindUrl',
    'ruleSearchList', 'ruleFindList', 'ruleBookName', 'ruleChapterList',
    'ruleBookContent', 'httpUserAgent', 'serialNumber', 'enable',
    'ruleBookUrlPattern'
  ];

  async compileMany(rawJson: string): Promise<CompiledBookSource[]> {
    const batch = await this.compileManyDetailed(rawJson);
    return batch.compiled;
  }

  /**
   * Compiles every syntactically isolated document and retains failures as
   * import evidence.  Callers must not mistake a shortened result list for a
   * fully compatible source package.
   */
  async compileManyDetailed(rawJson: string): Promise<LegadoCompilationBatchResult> {
    const documents = this.splitDocuments(rawJson);
    const compiled: CompiledBookSource[] = [];
    const failures: LegadoCompilationFailure[] = [];
    for (let i = 0; i < documents.length; i++) {
      try {
        const result = await this.compileOne(documents[i]);
        if (result !== null) {
          compiled.push(result);
        } else {
          failures.push(new LegadoCompilationFailure(i, '书源文档无法解析为 Legado BookSource。'));
        }
      } catch (error) {
        failures.push(new LegadoCompilationFailure(i, `书源编译失败: ${String(error)}`));
      }
    }
    return new LegadoCompilationBatchResult(compiled, failures, documents.length);
  }

  async compileOne(rawJson: string): Promise<CompiledBookSource | null> {
    const normalized = rawJson.trim();
    if (normalized.length === 0) {
      return null;
    }

    const parser = new LegadoSourceParser();
    const source = parser.parseFromJSON(normalized);
    if (source === null) {
      logger.warn(TAG, '跳过无法由旧解析器识别的书源文档');
      return null;
    }

    const fields = this.extractTopLevelFieldNames(normalized);
    const unknownFields = this.findUnknownFields(fields);
    const actualType = this.readTopLevelNumber(normalized, 'bookSourceType', Number(source.bookSourceType));
    const rawWeight = this.readTopLevelNumber(normalized, 'weight', source.weight || 0);
    // The legacy parser intentionally normalizes several fields for its old
    // executor. V2 must retain the source document's semantic values instead.
    source.bookSourceType = actualType;
    source.weight = rawWeight;

    const diagnostics: LegadoImportDiagnostic[] = [];
    if (actualType < 0 || actualType > 3) {
      diagnostics.push(new LegadoImportDiagnostic(
        LegadoDiagnosticSeverity.ERROR,
        actualType === 4 ? 'EXTERNAL_TYPE_PLUGIN_CANDIDATE' : 'UNSUPPORTED_EXTERNAL_TYPE',
        actualType === 4
          ? 'bookSourceType=4 已作为外部/插件候选完整保存，默认禁用且不会降级为 TEXT。'
          : `bookSourceType=${actualType} 不是 Legado 标准 0-3 类型，已保留原文并禁用 V2 执行。`,
        'bookSourceType'
      ));
      source.enabled = false;
    }
    if (unknownFields.length > 0) {
      diagnostics.push(new LegadoImportDiagnostic(
        LegadoDiagnosticSeverity.INFO,
        'UNKNOWN_FIELDS_PRESERVED',
        `已无损保留 ${unknownFields.length} 个未知或扩展字段。`,
        unknownFields.join(',')
      ));
    }
    if (source.loginUrl || source.loginUi || source.loginCheckJs) {
      diagnostics.push(new LegadoImportDiagnostic(
        LegadoDiagnosticSeverity.WARNING,
        'NEEDS_INTERACTION',
        '书源声明了登录或登录 UI；自动验证不会绕过登录、验证码或付费交互。',
        'loginUrl'
      ));
    }

    const raw = new RawBookSourceDocument(
      source.bookSourceUrl,
      rawJson,
      await sha256Hash(rawJson),
      Date.now(),
      fields,
      unknownFields
    );
    const rules = this.compileRules(source);
    const jsBlockingStatus = this.appendJsContractDiagnostics(source, rules, diagnostics);
    const capabilityReport = this.buildCapabilityReport(source, actualType, rules);
    const status = this.resolveStatus(actualType, capabilityReport, jsBlockingStatus);

    return new CompiledBookSource(raw, source, actualType, rules, capabilityReport, diagnostics, status);
  }

  createImportReport(compiled: CompiledBookSource): ImportReport {
    return new ImportReport(
      compiled.source.bookSourceUrl,
      compiled.source.bookSourceName,
      true,
      compiled.status !== LegadoCompatibilityStatus.BLOCKED,
      compiled.status,
      compiled.capabilityReport,
      compiled.diagnostics
    );
  }

  private resolveStatus(
    actualType: number,
    report: LegadoCapabilityReport,
    jsBlockingStatus: LegadoJsApiStatus | null
  ): LegadoCompatibilityStatus {
    if (actualType < 0 || actualType > 3) {
      return LegadoCompatibilityStatus.UNSUPPORTED;
    }
    if (report.needsInteraction || jsBlockingStatus === LegadoJsApiStatus.NEEDS_INTERACTION) {
      return LegadoCompatibilityStatus.NEEDS_INTERACTION;
    }
    if (report.unavailable.length > 0 || jsBlockingStatus !== null) {
      return LegadoCompatibilityStatus.BLOCKED;
    }
    return LegadoCompatibilityStatus.READY;
  }

  private appendJsContractDiagnostics(
    source: LegadoBookSource,
    rules: LegadoCompiledRule[],
    diagnostics: LegadoImportDiagnostic[]
  ): LegadoJsApiStatus | null {
    let script = source.jsLib || '';
    script += `\n${source.loginCheckJs || ''}`;
    for (let i = 0; i < rules.length; i++) {
      script += `\n${rules[i].rawText}`;
    }
    const assessment = getLegadoJsApiContractRegistry().assess(script);
    if (!assessment.hasBlockingContract || assessment.blockingStatus === null) {
      return null;
    }
    for (let i = 0; i < assessment.contracts.length; i++) {
      const contract = assessment.contracts[i];
      if (contract.status === LegadoJsApiStatus.SUPPORTED) {
        continue;
      }
      diagnostics.push(new LegadoImportDiagnostic(
        contract.status === LegadoJsApiStatus.NEEDS_INTERACTION
          ? LegadoDiagnosticSeverity.WARNING : LegadoDiagnosticSeverity.ERROR,
        `JS_${contract.status.toUpperCase()}`,
        `${contract.api}: ${contract.detail}`,
        'js'
      ));
    }
    return assessment.blockingStatus;
  }

  private buildCapabilityReport(
    source: LegadoBookSource,
    actualType: number,
    rules: LegadoCompiledRule[]
  ): LegadoCapabilityReport {
    const required: LegadoCapability[] = [];
    this.addCapability(required, LegadoCapability.HTTP);
    if (source.header && source.header.trim().length > 0) this.addCapability(required, LegadoCapability.HEADER);
    if (source.concurrentRate && source.concurrentRate.trim().length > 0) this.addCapability(required, LegadoCapability.RATE_LIMIT);
    if (source.loginUrl || source.loginUi || source.loginCheckJs) this.addCapability(required, LegadoCapability.LOGIN);
    if (actualType === 1) this.addCapability(required, LegadoCapability.AUDIO);
    if (actualType === 2) this.addCapability(required, LegadoCapability.IMAGE);
    if (actualType === 3) this.addCapability(required, LegadoCapability.FILE);
    if (actualType < 0 || actualType > 3) this.addCapability(required, LegadoCapability.EXTERNAL_TYPE);

    for (let i = 0; i < rules.length; i++) {
      this.appendNodeCapabilities(required, rules[i].root);
    }
    const content = source.ruleContent;
    if (content) {
      if (content.sourceRegex && content.sourceRegex.trim().length > 0) this.addCapability(required, LegadoCapability.SOURCE_REGEX);
      if (content.webJs && content.webJs.trim().length > 0) this.addCapability(required, LegadoCapability.WEB_JS);
      if (content.payAction && content.payAction.trim().length > 0) this.addCapability(required, LegadoCapability.PAY_ACTION);
      if (content.imageDecode && content.imageDecode.trim().length > 0) this.addCapability(required, LegadoCapability.IMAGE_DECODE);
    }
    if (source.ruleReview) this.addCapability(required, LegadoCapability.REVIEW);

    const supported: LegadoCapability[] = [];
    const unavailable: LegadoCapability[] = [];
    for (let i = 0; i < required.length; i++) {
      const capability = required[i];
      if (this.isCapabilitySupported(capability)) {
        supported.push(capability);
      } else {
        unavailable.push(capability);
      }
    }
    const needsInteraction = this.containsCapability(required, LegadoCapability.LOGIN) ||
      this.containsCapability(required, LegadoCapability.PAY_ACTION);
    return new LegadoCapabilityReport(
      source.bookSourceUrl,
      required,
      supported,
      unavailable,
      needsInteraction,
      this.containsCapability(required, LegadoCapability.EXTERNAL_TYPE)
    );
  }

  private isCapabilitySupported(capability: LegadoCapability): boolean {
    switch (capability) {
      case LegadoCapability.EXTERNAL_TYPE:
      // File candidates can be extracted, but there is not yet a V2 downloader
      // handoff in the ordinary reader path. Treating it as supported would
      // make a global cutover silently discard a real user-facing action.
      case LegadoCapability.FILE:
      case LegadoCapability.REVIEW:
      case LegadoCapability.PAY_ACTION:
      // V2 must not claim image output is usable if it cannot execute the
      // source-provided image transform.
      case LegadoCapability.IMAGE_DECODE:
        return false;
      default:
        return true;
    }
  }

  private appendNodeCapabilities(target: LegadoCapability[], node: LegadoRuleIrNode): void {
    for (let i = 0; i < node.requiredCapabilities.length; i++) {
      this.addCapability(target, node.requiredCapabilities[i]);
    }
    for (let i = 0; i < node.children.length; i++) {
      this.appendNodeCapabilities(target, node.children[i]);
    }
  }

  private compileRules(source: LegadoBookSource): LegadoCompiledRule[] {
    const rules: LegadoCompiledRule[] = [];
    this.appendRule(rules, LegadoWorkflowKind.SEARCH, 'searchUrl', source.searchUrl || '');
    this.appendRule(rules, LegadoWorkflowKind.EXPLORE, 'exploreUrl', source.exploreUrl || '');
    if (source.ruleSearch) {
      this.appendRule(rules, LegadoWorkflowKind.SEARCH, 'ruleSearch.bookList', source.ruleSearch.bookList || '');
      this.appendRule(rules, LegadoWorkflowKind.SEARCH, 'ruleSearch.bookUrl', source.ruleSearch.bookUrl || '');
      this.appendRule(rules, LegadoWorkflowKind.SEARCH, 'ruleSearch.name', source.ruleSearch.name || '');
    }
    if (source.ruleExplore) {
      this.appendRule(rules, LegadoWorkflowKind.EXPLORE, 'ruleExplore.bookList', source.ruleExplore.bookList || '');
      this.appendRule(rules, LegadoWorkflowKind.EXPLORE, 'ruleExplore.bookUrl', source.ruleExplore.bookUrl || '');
      this.appendRule(rules, LegadoWorkflowKind.EXPLORE, 'ruleExplore.name', source.ruleExplore.name || '');
    }
    if (source.ruleBookInfo) {
      this.appendRule(rules, LegadoWorkflowKind.BOOK_INFO, 'ruleBookInfo.init', source.ruleBookInfo.init || '');
      this.appendRule(rules, LegadoWorkflowKind.BOOK_INFO, 'ruleBookInfo.tocUrl', source.ruleBookInfo.tocUrl || '');
      this.appendRule(rules, LegadoWorkflowKind.BOOK_INFO, 'ruleBookInfo.downloadUrls', source.ruleBookInfo.downloadUrls || '');
    }
    if (source.ruleToc) {
      this.appendRule(rules, LegadoWorkflowKind.TOC, 'ruleToc.preUpdateJs', source.ruleToc.preUpdateJs || '');
      this.appendRule(rules, LegadoWorkflowKind.TOC, 'ruleToc.chapterList', source.ruleToc.chapterList || '');
      this.appendRule(rules, LegadoWorkflowKind.TOC, 'ruleToc.chapterUrl', source.ruleToc.chapterUrl || '');
      this.appendRule(rules, LegadoWorkflowKind.TOC, 'ruleToc.formatJs', source.ruleToc.formatJs || '');
      this.appendRule(rules, LegadoWorkflowKind.TOC, 'ruleToc.nextTocUrl', source.ruleToc.nextTocUrl || '');
    }
    if (source.ruleContent) {
      this.appendRule(rules, LegadoWorkflowKind.CONTENT, 'ruleContent.content', source.ruleContent.content || '');
      this.appendRule(rules, LegadoWorkflowKind.CONTENT, 'ruleContent.title', source.ruleContent.title || '');
      this.appendRule(rules, LegadoWorkflowKind.CONTENT, 'ruleContent.nextContentUrl', source.ruleContent.nextContentUrl || '');
      this.appendRule(rules, LegadoWorkflowKind.CONTENT, 'ruleContent.replaceRegex', source.ruleContent.replaceRegex || '');
      this.appendRule(rules, LegadoWorkflowKind.CONTENT, 'ruleContent.webJs', source.ruleContent.webJs || '');
      this.appendRule(rules, LegadoWorkflowKind.CONTENT, 'ruleContent.sourceRegex', source.ruleContent.sourceRegex || '');
      this.appendRule(rules, LegadoWorkflowKind.CONTENT, 'ruleContent.imageDecode', source.ruleContent.imageDecode || '');
      this.appendRule(rules, LegadoWorkflowKind.CONTENT, 'ruleContent.payAction', source.ruleContent.payAction || '');
    }
    if (source.ruleReview) {
      this.appendRule(rules, LegadoWorkflowKind.REVIEW, 'ruleReview.reviewList', source.ruleReview.reviewList || '');
    }
    return rules;
  }

  private appendRule(rules: LegadoCompiledRule[], workflow: LegadoWorkflowKind, field: string, rawText: string): void {
    const text = rawText.trim();
    if (text.length === 0) {
      return;
    }
    const location = new LegadoRuleSourceLocation(workflow, field, rules.length);
    const root = this.compileRuleNode(text, location);
    rules.push(new LegadoCompiledRule(location, text, root));
  }

  private compileRuleNode(rawText: string, location: LegadoRuleSourceLocation): LegadoRuleIrNode {
    const children: LegadoRuleIrNode[] = [];
    let kind = LegadoRuleNodeKind.LITERAL;
    const required: LegadoCapability[] = [];
    const lower = rawText.toLowerCase();
    if (lower.includes('@js:') || lower.includes('<js>') || lower.includes('{{js')) {
      kind = LegadoRuleNodeKind.JAVA_SCRIPT;
      required.push(LegadoCapability.JAVA_SCRIPT);
    } else if (rawText.includes('@put') || rawText.includes('@get')) {
      kind = rawText.includes('@put') ? LegadoRuleNodeKind.VARIABLE_PUT : LegadoRuleNodeKind.VARIABLE_GET;
      required.push(LegadoCapability.RULE_VARIABLE);
    } else if (rawText.includes('&&')) {
      kind = LegadoRuleNodeKind.COMPOSE_AND;
      required.push(LegadoCapability.RULE_COMPOSITION);
      this.appendCompositionChildren(children, rawText, '&&', location);
    } else if (rawText.includes('||')) {
      kind = LegadoRuleNodeKind.COMPOSE_OR;
      required.push(LegadoCapability.RULE_COMPOSITION);
      this.appendCompositionChildren(children, rawText, '||', location);
    } else if (rawText.includes('##')) {
      kind = LegadoRuleNodeKind.REPLACE;
      required.push(LegadoCapability.REGEX);
    } else if (this.isXPath(rawText)) {
      kind = LegadoRuleNodeKind.XPATH;
      required.push(LegadoCapability.XPATH);
    } else if (this.isJsonPath(rawText)) {
      kind = LegadoRuleNodeKind.JSON_PATH;
      required.push(LegadoCapability.JSON_PATH);
    } else if (this.isRegex(rawText)) {
      kind = LegadoRuleNodeKind.REGEX;
      required.push(LegadoCapability.REGEX);
    } else if (this.isUrlOption(rawText)) {
      kind = LegadoRuleNodeKind.URL_OPTION;
      this.addUrlOptionCapabilities(required, rawText);
    } else if (this.isCss(rawText)) {
      kind = LegadoRuleNodeKind.CSS;
      required.push(LegadoCapability.CSS);
    }
    if (rawText.includes('{{') || rawText.includes('}}')) {
      this.addCapability(required, LegadoCapability.JAVA_SCRIPT);
    }
    return new LegadoRuleIrNode(kind, rawText, location, required, children);
  }

  private appendCompositionChildren(
    target: LegadoRuleIrNode[],
    rawText: string,
    separator: string,
    location: LegadoRuleSourceLocation
  ): void {
    const values = rawText.split(separator);
    for (let i = 0; i < values.length; i++) {
      const childText = values[i].trim();
      if (childText.length > 0) {
        target.push(this.compileRuleNode(childText, location));
      }
    }
  }

  private addUrlOptionCapabilities(required: LegadoCapability[], rawText: string): void {
    this.addCapability(required, LegadoCapability.HTTP);
    const lower = rawText.toLowerCase();
    if (lower.includes('"method"') || lower.includes("'method'")) this.addCapability(required, LegadoCapability.POST_BODY);
    if (lower.includes('"header"') || lower.includes('"headers"') || lower.includes("'header'")) this.addCapability(required, LegadoCapability.HEADER);
    if (lower.includes('"charset"') || lower.includes("'charset'")) this.addCapability(required, LegadoCapability.CHARSET);
    if (lower.includes('"retry"') || lower.includes("'retry'")) this.addCapability(required, LegadoCapability.RETRY);
    if (lower.includes('"webview"') || lower.includes("'webview'")) this.addCapability(required, LegadoCapability.WEB_VIEW);
    if (lower.includes('"webjs"') || lower.includes("'webjs'")) this.addCapability(required, LegadoCapability.WEB_JS);
  }

  private isXPath(text: string): boolean {
    const lower = text.toLowerCase();
    return lower.startsWith('@xpath:') || lower.startsWith('xpath:') || text.startsWith('//') || text.startsWith('./');
  }

  private isJsonPath(text: string): boolean {
    const lower = text.toLowerCase();
    return lower.startsWith('@json:') || lower.startsWith('json:') || text.startsWith('$.') || text.startsWith('$[');
  }

  private isRegex(text: string): boolean {
    const lower = text.toLowerCase();
    return lower.startsWith('@regex:') || lower.startsWith('regex:') || text.includes('##');
  }

  private isUrlOption(text: string): boolean {
    return text.includes(',{') || text.includes(', {') || text.includes(",'{") || text.includes(", '{");
  }

  private isCss(text: string): boolean {
    return text.length > 0 && !text.startsWith('http://') && !text.startsWith('https://') && !text.startsWith('data:');
  }

  private extractTopLevelFieldNames(rawJson: string): string[] {
    const fields: string[] = [];
    let depth = 0;
    let inString = false;
    let escaped = false;
    let expectingKey = false;
    let keyStart = -1;
    for (let i = 0; i < rawJson.length; i++) {
      const char = rawJson.charAt(i);
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (char === '\\') {
          escaped = true;
        } else if (char === '"') {
          inString = false;
          if (depth === 1 && expectingKey && keyStart >= 0) {
            const key = rawJson.substring(keyStart, i);
            const next = this.nextNonWhitespace(rawJson, i + 1);
            if (next < rawJson.length && rawJson.charAt(next) === ':') {
              if (!fields.includes(key)) {
                fields.push(key);
              }
              expectingKey = false;
            }
          }
          keyStart = -1;
        }
        continue;
      }
      if (char === '"') {
        inString = true;
        if (depth === 1) {
          expectingKey = true;
          keyStart = i + 1;
        }
      } else if (char === '{' || char === '[') {
        depth++;
      } else if (char === '}' || char === ']') {
        depth--;
      } else if (char === ',' && depth === 1) {
        expectingKey = true;
      }
    }
    return fields;
  }

  private findUnknownFields(fields: string[]): string[] {
    const unknown: string[] = [];
    for (let i = 0; i < fields.length; i++) {
      if (!LegadoCompatibilityCompiler.KNOWN_TOP_LEVEL_FIELDS.includes(fields[i])) {
        unknown.push(fields[i]);
      }
    }
    return unknown;
  }

  private readTopLevelNumber(rawJson: string, field: string, fallback: number): number {
    const token = this.readTopLevelValue(rawJson, field);
    if (token.length === 0) {
      return fallback;
    }
    const parsed = Number(token);
    return Number.isFinite(parsed) ? parsed : fallback;
  }

  private readTopLevelValue(rawJson: string, field: string): string {
    let depth = 0;
    let inString = false;
    let escaped = false;
    let keyStart = -1;
    for (let i = 0; i < rawJson.length; i++) {
      const char = rawJson.charAt(i);
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (char === '\\') {
          escaped = true;
        } else if (char === '"') {
          inString = false;
          if (depth === 1 && keyStart >= 0 && rawJson.substring(keyStart, i) === field) {
            const colon = this.nextNonWhitespace(rawJson, i + 1);
            if (colon < rawJson.length && rawJson.charAt(colon) === ':') {
              const valueStart = this.nextNonWhitespace(rawJson, colon + 1);
              return this.readJsonScalar(rawJson, valueStart);
            }
          }
          keyStart = -1;
        }
        continue;
      }
      if (char === '"') {
        inString = true;
        keyStart = depth === 1 ? i + 1 : -1;
      } else if (char === '{' || char === '[') {
        depth++;
      } else if (char === '}' || char === ']') {
        depth--;
      }
    }
    return '';
  }

  private readJsonScalar(rawJson: string, start: number): string {
    let end = start;
    while (end < rawJson.length) {
      const char = rawJson.charAt(end);
      if (char === ',' || char === '}' || char === ']') {
        break;
      }
      end++;
    }
    return rawJson.substring(start, end).trim().replace(/^"|"$/g, '');
  }

  private nextNonWhitespace(value: string, start: number): number {
    let index = start;
    while (index < value.length && value.charAt(index) <= ' ') {
      index++;
    }
    return index;
  }

  private splitDocuments(rawJson: string): string[] {
    const text = rawJson.trim();
    if (!text.startsWith('[')) {
      return [rawJson];
    }
    const documents: string[] = [];
    let inString = false;
    let escaped = false;
    let depth = 0;
    let start = -1;
    for (let i = 0; i < text.length; i++) {
      const char = text.charAt(i);
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (char === '\\') {
          escaped = true;
        } else if (char === '"') {
          inString = false;
        }
        continue;
      }
      if (char === '"') {
        inString = true;
      } else if (char === '{') {
        if (depth === 0) {
          start = i;
        }
        depth++;
      } else if (char === '}') {
        depth--;
        if (depth === 0 && start >= 0) {
          documents.push(text.substring(start, i + 1));
          start = -1;
        }
      }
    }
    return documents;
  }

  private containsCapability(values: LegadoCapability[], capability: LegadoCapability): boolean {
    return values.includes(capability);
  }

  private addCapability(values: LegadoCapability[], capability: LegadoCapability): void {
    if (!values.includes(capability)) {
      values.push(capability);
    }
  }
}

export function getLegadoCompatibilityCompiler(): LegadoCompatibilityCompiler {
  return new LegadoCompatibilityCompiler();
}
