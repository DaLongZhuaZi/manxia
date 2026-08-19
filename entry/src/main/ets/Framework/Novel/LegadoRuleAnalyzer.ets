import { SafeUtils } from 'manxia_core/src/main/ets/Utils/SafeUtils';
/**
 * Legado规则解析引擎
 * 支持多种解析模式：Default(CSS)、XPath、JSONPath、Regex、JS
 * 
 * 文件路径: entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets
 * 职责: 解析Legado书源规则，从HTML/JSON内容中提取数据
 */

import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { LegadoBookSource, LegadoRuleMode, LegadoParsedRule } from './LegadoSourceTypes';
import {
  getLegadoJsEngine,
  JsContext,
  LegadoJsSourceDataChange,
  LegadoJsSourceEffects
} from './LegadoJsEngine';
import {
  LegadoHtmlBridge,
  createLegadoHtmlBridge,
  parse as parseHtml,
  HTMLElement as HtmlElement,
  HtmlEntities,
  LegadoTextAccumulator,
  LegadoTextNormalization
} from 'manxia_core/src/main/ets/libs/htmlparser/index';
import type { LegadoBridgeTrace } from './LegadoCompatibilityTypes';

const TAG = 'LegadoRuleAnalyzer';
const REGEX_GROUP_PAYLOAD_KEY = '__legadoRegexGroups';

/**
 * 性能保护配置
 * 用于防止大型HTML解析导致ANR闪退
 */
class PerformanceConfig {
  // 最大元素数量 - 支持超过5000章节的小说
  static readonly MAX_ELEMENTS = 5000;
  // 最大内容大小 - 2MB
  static readonly MAX_CONTENT_SIZE = 2 * 1024 * 1024;
  // 单次处理批次大小 - 每批处理500个元素后让出主线程
  static readonly BATCH_SIZE = 500;
  // ID查找最大元素数量（ID通常较少）
  static readonly MAX_ID_ELEMENTS = 1000;
  // HTML转文本时的最大输入大小（避免超大输入导致主线程长时间占用）
  static readonly MAX_TEXT_PARSE_INPUT_SIZE = 256 * 1024;
  // HTML转文本的最大输出大小（搜索场景下足够展示且能防止异常规则放大）
  static readonly MAX_TEXT_OUTPUT_SIZE = 64 * 1024;
  // HTML转文本缓存上限（每个Analyzer实例）
  static readonly HTML_TO_TEXT_CACHE_SIZE = 256;
  // 仅对较小片段启用HTML转文本缓存，避免大字符串高频Map写入带来的主线程抖动
  static readonly HTML_TO_TEXT_CACHE_MAX_INPUT_SIZE = 8 * 1024;
  // 标签闭合异常时的元素回退截断，防止单次规则解析把主线程长期占满
  static readonly MAX_UNCLOSED_ELEMENT_FALLBACK_SIZE = 128 * 1024;
  
  /**
   * 安全截取内容，避免处理过大的HTML
   */
  static safeSubstring(content: string, maxSize: number = PerformanceConfig.MAX_CONTENT_SIZE): string {
    if (content.length <= maxSize) {
      return content;
    }
    // 尝试在标签边界截断，避免截断标签中间
    const truncated = content.substring(0, maxSize);
    const lastTagEnd = truncated.lastIndexOf('>');
    if (lastTagEnd > maxSize * 0.9) {
      return truncated.substring(0, lastTagEnd + 1);
    }
    return truncated;
  }
  
  /**
   * 检查是否应该继续处理（防止无限循环）
   */
  static shouldContinue(count: number, maxCount: number = PerformanceConfig.MAX_ELEMENTS): boolean {
    return count < maxCount;
  }
}

/**
 * CSS选择器解析结果接口
 */
interface CssSelectorResult {
  sel: string;
  attr: string;
}

interface LegadoAttributeSelector {
  name: string;
  operator: string;
  value: string;
}

interface LegadoPseudoSelector {
  name: string;
  argument: string;
}

interface LegadoAttributeSelectorsResult {
  selector: string;
  attributes: LegadoAttributeSelector[];
}

interface LegadoPseudoSelectorsResult {
  selector: string;
  pseudoClasses: LegadoPseudoSelector[];
}

interface StringElementSiblingPosition {
  siblingIndex: number;
  typeIndex: number;
  typeCount: number;
  siblingCount: number;
}

interface StringCssCombinatorChain {
  parts: string[];
  combinators: string[];
}

interface LegadoRegexPrefix {
  pattern: string;
  flags: string;
}

interface LegadoAttributeSelectorParseResult {
  selector: LegadoAttributeSelector;
  endIndex: number;
}

interface HtmlTagScan {
  startIndex: number;
  endIndex: number;
  tagName: string;
  isClosing: boolean;
  isSelfClosing: boolean;
  isSpecial: boolean;
}

class StringElementOccurrence {
  element: string;
  startIndex: number;
  tagName: string;

  constructor(element: string, startIndex: number, tagName: string) {
    this.element = element;
    this.startIndex = startIndex;
    this.tagName = tagName;
  }
}

enum IndexSelectorItemType {
  Single = 0,
  Range = 1
}

/**
 * 索引范围接口
 */
interface IndexRange {
  start: number;
  end: number;
  step: number;
  startOmitted: boolean;
  endOmitted: boolean;
}

interface IndexSelectorItem {
  itemType: IndexSelectorItemType;
  index: number;
  start: number;
  end: number;
  step: number;
  startOmitted: boolean;
  endOmitted: boolean;
}

/**
 * 索引选择器解析结果接口
 */
interface IndexSelectorResult {
  selector: string;
  hasIndex: boolean;
  exclude: boolean;
  indexes: number[];
  ranges: IndexRange[];
  items: IndexSelectorItem[];
}

interface JsonFilterOperatorMatch {
  operator: string;
  index: number;
}

/**
 * 规则分割结果接口
 */
interface RuleSplitResult {
  rules: string[];
  splitType: string;
}

interface RuleReplaceParts {
  rule: string;
  replaceRegex?: string;
  replacement?: string;
  replaceFirst: boolean;
}

interface JsonPrefixJavaScriptRule {
  mainRule: string;
  jsCode: string;
}

interface RegexGroupPayload {
  __legadoRegexGroups: string[];
  __legadoRegexText: string;
}

/**
 * XPath步骤接口
 */
interface XPathStep {
  tag: string;
  predicates: XPathPredicate[];
  isDescendant: boolean;
}

/**
 * XPath谓词接口
 */
interface XPathPredicate {
  type: string;
  value?: string;
  attr?: string;
  position?: number;
  operator?: string;
}

/**
 * 规则链分析器
 * 用于分割@连接的规则链，正确处理引号和括号内的@符号
 * 参考Legado原版RuleAnalyzer.kt
 */
class LegadoRuleChainAnalyzer {
  private queue: string;
  private pos: number = 0;
  
  constructor(rule: string) {
    this.queue = rule.trim();
  }
  
  /**
   * 使用@分割规则链
   * 正确处理引号和括号内的@符号
   */
  splitByAt(): string[] {
    const rules: string[] = [];
    let start = 0;

    // 跳过开头的@符号
    while (this.pos < this.queue.length && (this.queue[this.pos] === '@' || this.queue[this.pos] <= ' ')) {
      this.pos++;
    }
    start = this.pos;

    // Legado's chain separator is meaningful only outside selector-local
    // contexts.  Keep parentheses and attribute/regex brackets independent:
    // a ')' inside [^)] must not close :matches(...) and expose a later '@'.
    let parenthesisDepth = 0;
    let bracketDepth = 0;
    let quote = '';
    let escaped = false;

    while (this.pos < this.queue.length) {
      const c = this.queue[this.pos];

      // 检查是否是<js>块开始
      if (c === '<' && this.queue.substring(this.pos, this.pos + 4).toLowerCase() === '<js>') {
        // 跳过整个<js>...</js>块
        this.skipJsBlock();
        continue;
      }

      if (escaped) {
        escaped = false;
        this.pos++;
        continue;
      }
      if (c === '\\') {
        escaped = true;
        this.pos++;
        continue;
      }
      if (quote.length > 0) {
        if (c === quote) {
          quote = '';
        }
        this.pos++;
        continue;
      }
      if (c === '"' || c === "'") {
        quote = c;
        this.pos++;
        continue;
      }
      if (c === '[') {
        bracketDepth++;
        this.pos++;
        continue;
      }
      if (c === ']' && bracketDepth > 0) {
        bracketDepth--;
        this.pos++;
        continue;
      }
      if (c === '(' && bracketDepth === 0) {
        parenthesisDepth++;
        this.pos++;
        continue;
      }
      if (c === ')' && parenthesisDepth > 0 && bracketDepth === 0) {
        parenthesisDepth--;
        this.pos++;
        continue;
      }

      if (c === '@' && parenthesisDepth === 0 && bracketDepth === 0) {
        // 找到分隔符
        if (this.pos > start) {
          rules.push(this.queue.substring(start, this.pos).trim());
        }
        this.pos++;
        // 跳过连续的@和空白
        while (this.pos < this.queue.length && (this.queue[this.pos] === '@' || this.queue[this.pos] <= ' ')) {
          this.pos++;
        }
        start = this.pos;
      } else {
        this.pos++;
      }
    }
    
    // 添加最后一个规则
    if (this.pos > start) {
      rules.push(this.queue.substring(start).trim());
    }
    
    return rules;
  }
  
  /**
   * 跳过平衡的括号
   */
  private skipBalanced(open: string, close: string): void {
    let depth = 1;
    this.pos++; // 跳过开始括号
    
    while (this.pos < this.queue.length && depth > 0) {
      const c = this.queue[this.pos];
      if (c === open) {
        depth++;
      } else if (c === close) {
        depth--;
      } else if (c === '"' || c === "'") {
        this.skipQuoted(c);
        continue;
      }
      this.pos++;
    }
  }
  
  /**
   * 跳过引号内容
   */
  private skipQuoted(quote: string): void {
    this.pos++; // 跳过开始引号
    while (this.pos < this.queue.length) {
      const c = this.queue[this.pos];
      if (c === '\\' && this.pos + 1 < this.queue.length) {
        this.pos += 2; // 跳过转义字符
        continue;
      }
      if (c === quote) {
        this.pos++;
        return;
      }
      this.pos++;
    }
  }
  
  /**
   * 跳过<js>...</js>块
   */
  private skipJsBlock(): void {
    // 跳过 <js>
    this.pos += 4;
    // 查找 </js>
    while (this.pos < this.queue.length) {
      if (this.queue[this.pos] === '<' && 
          this.queue.substring(this.pos, this.pos + 5).toLowerCase() === '</js>') {
        this.pos += 5; // 跳过 </js>
        return;
      }
      this.pos++;
    }
  }
}

/**
 * 规则解析器类
 * 负责解析Legado规则语法并从内容中提取数据
 */
export class LegadoRuleElementDiagnostic {
  readonly elements: string[];
  readonly baseMatchedCount: number;
  readonly resolver: string;

  constructor(elements: string[], baseMatchedCount: number, resolver: string) {
    this.elements = elements;
    this.baseMatchedCount = baseMatchedCount;
    this.resolver = resolver;
  }
}

/**
 * Sanitized candidate for a standard CSS chain. The candidate is kept in
 * memory so workflow tracing can record only its length and fingerprint.
 */
export class LegadoSimpleCssChainBridgeProbe {
  readonly status: string;
  readonly candidate: string;

  constructor(status: string, candidate: string) {
    this.status = status;
    this.candidate = candidate;
  }
}

/**
 * Upstream Legado creates fresh bindings for each evaluation. This immutable
 * value carries the workflow-owned values that every fresh binding inherits.
 */
export class LegadoRuleJsExecutionBinding {
  readonly source: LegadoBookSource;
  readonly book: Record<string, string> | undefined;
  readonly chapter: Record<string, string> | undefined;
  readonly key: string;
  readonly page: number;

  constructor(
    source: LegadoBookSource,
    book: Record<string, string> | undefined,
    chapter: Record<string, string> | undefined,
    key: string,
    page: number
  ) {
    this.source = source;
    this.book = book;
    this.chapter = chapter;
    this.key = key;
    this.page = page;
  }
}

export class LegadoRuleAnalyzer {
  // Hot-path selector tracing is disabled by default to prevent UI thread stalls.
  private static readonly ENABLE_SELECTOR_TRACE: boolean = false;
  private static readonly SELF_CLOSING_TAGS: Set<string> = new Set([
    'br', 'hr', 'img', 'input', 'meta', 'link', 'area', 'base', 'col', 'embed', 'param', 'source', 'track', 'wbr'
  ]);
  private static readonly PARSED_RULE_CACHE_MAX: number = 2048;
  private static readonly RULE_SPLIT_CACHE_MAX: number = 4096;
  private static readonly PARSED_RULE_CACHE: Map<string, LegadoParsedRule> = new Map();
  private static readonly RULE_SPLIT_CACHE: Map<string, RuleSplitResult> = new Map();
  private content: string = '';
  private baseUrl: string = '';
  private isJSON: boolean = false;
  private variables: Map<string, string> = new Map();
  private sourceEffects: LegadoJsSourceEffects = {};
  private htmlBridge: LegadoHtmlBridge | null = null;
  private htmlToTextCache: Map<string, string> = new Map();
  private maxElementsLimit: number = 0;
  private jsLib: string = '';
  private jsExecutionBinding: LegadoRuleJsExecutionBinding | null = null;
  private lastJsExecutionStatus: string = 'not_evaluated';
  private bridgeTraces: LegadoBridgeTrace[] = [];

  constructor() {}

  setJsLib(jsLib?: string): LegadoRuleAnalyzer {
    this.jsLib = jsLib || '';
    return this;
  }

  setJsExecutionBinding(binding: LegadoRuleJsExecutionBinding): LegadoRuleAnalyzer {
    this.jsExecutionBinding = binding;
    return this;
  }

  /**
   * Returns a fixed, content-free outcome for the most recent JS evaluation.
   * Workflow traces use this to distinguish an empty script result from an
   * unavailable ArkWeb runtime or a rejected bridge request.
   */
  getLastJsExecutionStatus(): string {
    return this.lastJsExecutionStatus;
  }

  /** Returns nested JS bridge evidence collected by this analyzer instance. */
  getBridgeTracesSnapshot(): LegadoBridgeTrace[] {
    return this.bridgeTraces.slice();
  }

  private recordBridgeTraces(traces: LegadoBridgeTrace[] | undefined): void {
    if (traces === undefined || traces.length <= 0) {
      return;
    }
    for (let index = 0; index < traces.length; index++) {
      const trace = traces[index];
      let duplicate = false;
      for (let existingIndex = 0; existingIndex < this.bridgeTraces.length; existingIndex++) {
        const existing = this.bridgeTraces[existingIndex];
        if (existing.id === trace.id && existing.type === trace.type &&
          existing.method === trace.method && existing.code === trace.code &&
          existing.success === trace.success && existing.bodyLength === trace.bodyLength) {
          duplicate = true;
          break;
        }
      }
      if (!duplicate) {
        this.bridgeTraces.push(trace);
      }
    }
  }

  /** Returns only the parser mode for redacted workflow diagnostics. */
  isJsonContent(): boolean {
    return this.isJSON;
  }

  private createJsContext(result: string, src: string, override?: JsContext): JsContext {
    const binding = this.jsExecutionBinding;
    const context: JsContext = {
      result: override?.result !== undefined ? override.result : result,
      baseUrl: override?.baseUrl !== undefined ? override.baseUrl : this.baseUrl,
      book: override?.book !== undefined ? override.book : binding?.book,
      chapter: override?.chapter !== undefined ? override.chapter : binding?.chapter,
      key: override?.key !== undefined ? override.key : (binding?.key || ''),
      page: override?.page !== undefined ? override.page : (binding?.page || 1),
      variables: this.getVariablesObject(),
      src: override?.src !== undefined ? override.src : src,
      jsLib: override?.jsLib !== undefined ? override.jsLib : this.jsLib,
      source: override?.source !== undefined ? override.source : binding?.source
    };
    if (override?.variables !== undefined && context.variables !== undefined) {
      const keys = Object.keys(override.variables);
      for (let index = 0; index < keys.length; index++) {
        const key = keys[index];
        context.variables[key] = override.variables[key];
      }
    }
    return context;
  }

  setMaxElementsLimit(limit?: number): LegadoRuleAnalyzer {
    if (limit === undefined || limit <= 0) {
      this.maxElementsLimit = 0;
      return this;
    }
    this.maxElementsLimit = Math.floor(limit);
    return this;
  }

  private getMaxElements(defaultLimit: number): number {
    if (this.maxElementsLimit <= 0) {
      return defaultLimit;
    }
    return Math.min(defaultLimit, this.maxElementsLimit);
  }

  private selectorTrace(messageBuilder: () => string): void {
    if (!LegadoRuleAnalyzer.ENABLE_SELECTOR_TRACE) {
      return;
    }
    logger.debug(TAG, messageBuilder());
  }

  private static putParsedRuleCache(key: string, value: LegadoParsedRule): void {
    if (LegadoRuleAnalyzer.PARSED_RULE_CACHE.size >= LegadoRuleAnalyzer.PARSED_RULE_CACHE_MAX) {
      const firstKey = LegadoRuleAnalyzer.PARSED_RULE_CACHE.keys().next().value as string | undefined;
      if (firstKey) {
        LegadoRuleAnalyzer.PARSED_RULE_CACHE.delete(firstKey);
      }
    }
    LegadoRuleAnalyzer.PARSED_RULE_CACHE.set(key, value);
  }

  private static putRuleSplitCache(key: string, value: RuleSplitResult): void {
    if (LegadoRuleAnalyzer.RULE_SPLIT_CACHE.size >= LegadoRuleAnalyzer.RULE_SPLIT_CACHE_MAX) {
      const firstKey = LegadoRuleAnalyzer.RULE_SPLIT_CACHE.keys().next().value as string | undefined;
      if (firstKey) {
        LegadoRuleAnalyzer.RULE_SPLIT_CACHE.delete(firstKey);
      }
    }
    LegadoRuleAnalyzer.RULE_SPLIT_CACHE.set(key, value);
  }

  private isJsOpenTagAt(str: string, index: number): boolean {
    if (index + 3 >= str.length) {
      return false;
    }
    const c1 = str[index + 1];
    const c2 = str[index + 2];
    return str[index] === '<' &&
      (c1 === 'j' || c1 === 'J') &&
      (c2 === 's' || c2 === 'S') &&
      str[index + 3] === '>';
  }

  private isJsCloseTagAt(str: string, index: number): boolean {
    if (index + 4 >= str.length) {
      return false;
    }
    const c2 = str[index + 2];
    const c3 = str[index + 3];
    return str[index] === '<' &&
      str[index + 1] === '/' &&
      (c2 === 'j' || c2 === 'J') &&
      (c3 === 's' || c3 === 'S') &&
      str[index + 4] === '>';
  }

  private matchesSplitterAt(str: string, index: number, splitter: string): boolean {
    if (index + splitter.length > str.length) {
      return false;
    }
    for (let i = 0; i < splitter.length; i++) {
      if (str[index + i] !== splitter[i]) {
        return false;
      }
    }
    return true;
  }

  private pushElementIfNew(
    results: string[],
    seenStartIndexes: Set<number>,
    html: string,
    startIndex: number,
    tagName: string,
    maxElements: number
  ): void {
    if (results.length >= maxElements || seenStartIndexes.has(startIndex)) {
      return;
    }
    const element = this.extractElement(html, startIndex, tagName);
    if (!element) {
      return;
    }
    seenStartIndexes.add(startIndex);
    results.push(element);
  }

  /**
   * 设置要解析的内容
   * 对于大型HTML（>100KB），跳过DOM解析以避免ANR
   */
  setContent(content: string, baseUrl?: string, disableHtmlBridge: boolean = false): LegadoRuleAnalyzer {
    this.content = content;
    if (baseUrl) {
      this.baseUrl = baseUrl;
    }
    this.isJSON = this.checkIsJSON(content);
    this.htmlToTextCache.clear();
    
    // HTML大小阈值：超过此大小不创建DOM桥接，使用字符串解析
    // 增加到100KB以支持更大的章节列表页面
    const HTML_SIZE_THRESHOLD = 100000; // 100KB
    
    // 如果不是JSON，且内容不太大，初始化HTML解析桥接
    if (!disableHtmlBridge && !this.isJSON && content.trim()) {
      if (content.length <= HTML_SIZE_THRESHOLD) {
        this.htmlBridge = createLegadoHtmlBridge(content);
        // 性能优化：减少日志输出
        // logger.debug(TAG, `HTML桥接初始化完成，内容长度: ${content.length}`);
      } else {
        // 大型HTML跳过DOM解析，使用字符串解析避免ANR
        this.htmlBridge = null;
        // 性能优化：减少日志输出
        // logger.debug(TAG, `HTML过大(${content.length}字节)，跳过DOM解析，使用字符串解析`);
      }
    } else {
      this.htmlBridge = null;
    }
    
    return this;
  }
  
  /**
   * 获取HTML解析桥接实例
   */
  getHtmlBridge(): LegadoHtmlBridge | null {
    return this.htmlBridge;
  }

  /**
   * 设置基础URL
   */
  setBaseUrl(baseUrl: string): LegadoRuleAnalyzer {
    this.baseUrl = baseUrl;
    return this;
  }

  /**
   * 检查内容是否为JSON
   */
  private checkIsJSON(content: string): boolean {
    const trimmed = content.trim();
    return (trimmed.startsWith('{') && trimmed.endsWith('}')) ||
           (trimmed.startsWith('[') && trimmed.endsWith(']'));
  }

  /**
   * 解析规则字符串，识别规则模式
   */
  parseRule(ruleStr: string): LegadoParsedRule {
    if (!ruleStr || ruleStr.trim() === '') {
      return {
        mode: LegadoRuleMode.Default,
        rule: ''
      };
    }

    const parseCacheKey = `${this.isJSON ? '1' : '0'}|${ruleStr}`;
    const cachedRule = LegadoRuleAnalyzer.PARSED_RULE_CACHE.get(parseCacheKey);
    if (cachedRule) {
      return cachedRule;
    }

    let rule = ruleStr.trim();
    let mode = LegadoRuleMode.Default;
    const putMap: Record<string, string> = {};

    rule = this.splitPutRule(rule, putMap);

    // 识别规则模式
    if (rule.startsWith('@XPath:') || rule.startsWith('@xpath:')) {
      mode = LegadoRuleMode.XPath;
      rule = rule.substring(7);
    } else if (rule.startsWith('//') || (rule.startsWith('/') && rule.includes('/'))) {
      // XPath: 以//开头，或以/开头且包含路径分隔符（如 /p[1]/a/text()）
      mode = LegadoRuleMode.XPath;
    } else if (rule.startsWith('@Json:') || rule.startsWith('@json:')) {
      mode = LegadoRuleMode.Json;
      rule = rule.substring(6);
    } else if (rule.startsWith('$.') || rule.startsWith('$[')) {
      mode = LegadoRuleMode.Json;
    } else if (this.isJSON && /^[a-zA-Z_][a-zA-Z0-9_]*(\.[a-zA-Z_][a-zA-Z0-9_]*|\[\d+\])*$/.test(rule.split('@')[0].split('##')[0].trim())) {
      // Legado evaluates every discovery item as its own JSON document. Both
      // `sourceId` and `data.books` therefore mean JSON paths at that item
      // scope, including before a following `@js:` rule consumes `result`.
      // 需要排除@后面的属性选择器和##后面的替换规则
      mode = LegadoRuleMode.Json;
      // 将简单路径转换为JSONPath格式
      const mainRule = rule.split('@')[0].split('##')[0].trim();
      rule = '$.' + mainRule + rule.substring(mainRule.length);
      // 性能优化：减少日志输出
      // logger.debug(TAG, `自动转换为JSONPath: ${rule}`);
    } else if (rule.startsWith('@js:') || rule.startsWith('@JS:')) {
      mode = LegadoRuleMode.Js;
      rule = rule.substring(4);
    } else if (rule.startsWith('<js>') && rule.includes('</js>')) {
      mode = LegadoRuleMode.Js;
      const jsEnd = rule.indexOf('</js>');
      const jsCode = rule.substring(4, jsEnd);
      const afterJs = rule.substring(jsEnd + 5).trim();
      // 如果</js>后面还有规则，将其作为后续规则保存
      if (afterJs) {
        // 返回包含后续规则的特殊格式
        rule = jsCode + '\n@AFTER_JS@' + afterJs;
      } else {
        rule = jsCode;
      }
    } else if (rule.startsWith('@css:') || rule.startsWith('@CSS:')) {
      mode = LegadoRuleMode.Default;
      rule = rule.substring(5);
    } else if (rule.startsWith('@@')) {
      mode = LegadoRuleMode.Default;
      rule = rule.substring(2);
    } else if (rule.startsWith(':')) {
      mode = LegadoRuleMode.Regex;
      rule = rule.substring(1);
    } else if (this.isJSON) {
      mode = LegadoRuleMode.Json;
    }

    // 解析替换规则 ##regex##replacement
    let replaceRegex: string | undefined;
    let replacement: string | undefined;
    let replaceFirst = false;

    const replaceParts = this.splitReplaceRule(rule);
    rule = replaceParts.rule;
    replaceRegex = replaceParts.replaceRegex;
    replacement = replaceParts.replacement;
    replaceFirst = replaceParts.replaceFirst;

    const parsedRule: LegadoParsedRule = {
      mode,
      rule: rule.trim(),
      replaceRegex,
      replacement,
      replaceFirst,
      putMap: Object.keys(putMap).length > 0 ? putMap : undefined
    };
    LegadoRuleAnalyzer.putParsedRuleCache(parseCacheKey, parsedRule);
    return parsedRule;
  }

  private splitPutRule(ruleText: string, putMap: Record<string, string>): string {
    let result = '';
    let cursor = 0;
    while (cursor < ruleText.length) {
      const markerIndex = this.indexOfIgnoreCase(ruleText, '@put:{', cursor);
      if (markerIndex < 0) {
        result += ruleText.substring(cursor);
        break;
      }
      result += ruleText.substring(cursor, markerIndex);
      const braceStart = markerIndex + 5;
      const braceEnd = this.findBalancedBraceEnd(ruleText, braceStart);
      if (braceEnd < 0) {
        result += ruleText.substring(markerIndex);
        break;
      }
      const putBody = ruleText.substring(braceStart + 1, braceEnd);
      this.parsePutRuleBody(putBody, putMap);
      cursor = braceEnd + 1;
    }
    return result.trim();
  }

  private indexOfIgnoreCase(text: string, search: string, fromIndex: number): number {
    const lowerText = text.toLowerCase();
    const lowerSearch = search.toLowerCase();
    return lowerText.indexOf(lowerSearch, fromIndex);
  }

  private parsePutRuleBody(body: string, putMap: Record<string, string>): void {
    try {
      const parsed = SafeUtils.parseObj(`{${body}}`) as Record<string, string>;
      const keys = Object.keys(parsed);
      if (keys.length > 0) {
        for (let i = 0; i < keys.length; i++) {
          const key = keys[i].trim();
          const value = parsed[key] === undefined || parsed[key] === null ? '' : String(parsed[key]).trim();
          if (key.length > 0 && value.length > 0) {
            putMap[key] = value;
          }
        }
        return;
      }
    } catch (_error) {
    }

    const pairs = this.splitTopLevelText(body, ',');
    for (let i = 0; i < pairs.length; i++) {
      const pair = pairs[i].trim();
      if (pair.length <= 0) {
        continue;
      }
      const colonIndex = this.findTopLevelChar(pair, ':');
      if (colonIndex <= 0) {
        continue;
      }
      const rawKey = pair.substring(0, colonIndex).trim();
      const rawValue = pair.substring(colonIndex + 1).trim();
      const key = this.unquoteRuleText(rawKey);
      const value = this.unquoteRuleText(rawValue);
      if (key.length > 0 && value.length > 0) {
        putMap[key] = value;
      }
    }
  }

  private splitTopLevelText(text: string, delimiter: string): string[] {
    const parts: string[] = [];
    let current = '';
    let quote = '';
    let escaped = false;
    let braceDepth = 0;
    let bracketDepth = 0;
    let parenDepth = 0;
    for (let i = 0; i < text.length; i++) {
      const ch = text[i];
      if (quote.length > 0) {
        current += ch;
        if (escaped) {
          escaped = false;
        } else if (ch === '\\') {
          escaped = true;
        } else if (ch === quote) {
          quote = '';
        }
        continue;
      }
      if (ch === '"' || ch === "'") {
        quote = ch;
        current += ch;
        continue;
      }
      if (ch === '{') {
        braceDepth++;
      } else if (ch === '}' && braceDepth > 0) {
        braceDepth--;
      } else if (ch === '[') {
        bracketDepth++;
      } else if (ch === ']' && bracketDepth > 0) {
        bracketDepth--;
      } else if (ch === '(') {
        parenDepth++;
      } else if (ch === ')' && parenDepth > 0) {
        parenDepth--;
      }
      if (ch === delimiter && braceDepth === 0 && bracketDepth === 0 && parenDepth === 0) {
        parts.push(current);
        current = '';
      } else {
        current += ch;
      }
    }
    parts.push(current);
    return parts;
  }

  private findTopLevelChar(text: string, target: string): number {
    let quote = '';
    let escaped = false;
    let braceDepth = 0;
    let bracketDepth = 0;
    let parenDepth = 0;
    for (let i = 0; i < text.length; i++) {
      const ch = text[i];
      if (quote.length > 0) {
        if (escaped) {
          escaped = false;
        } else if (ch === '\\') {
          escaped = true;
        } else if (ch === quote) {
          quote = '';
        }
        continue;
      }
      if (ch === '"' || ch === "'") {
        quote = ch;
        continue;
      }
      if (ch === '{') {
        braceDepth++;
      } else if (ch === '}' && braceDepth > 0) {
        braceDepth--;
      } else if (ch === '[') {
        bracketDepth++;
      } else if (ch === ']' && bracketDepth > 0) {
        bracketDepth--;
      } else if (ch === '(') {
        parenDepth++;
      } else if (ch === ')' && parenDepth > 0) {
        parenDepth--;
      }
      if (ch === target && braceDepth === 0 && bracketDepth === 0 && parenDepth === 0) {
        return i;
      }
    }
    return -1;
  }

  private unquoteRuleText(text: string): string {
    const trimmed = text.trim();
    if (trimmed.length >= 2) {
      const first = trimmed[0];
      const last = trimmed[trimmed.length - 1];
      if ((first === '"' && last === '"') || (first === "'" && last === "'")) {
        return trimmed.substring(1, trimmed.length - 1);
      }
    }
    return trimmed;
  }

  /**
   * 获取字符串结果
   * 支持规则分割符: && (与), || (或), %% (交叉合并)
   */
  getString(ruleStr: string | undefined): string {
    if (!ruleStr || ruleStr.trim() === '') {
      return '';
    }

    try {
      const processedRule = this.preprocessRuleText(ruleStr);
      const replacementParts = this.splitReplaceRule(processedRule);
      const compositionRule = replacementParts.rule;

      // 处理规则分割符
      const splitResult = this.splitRuleStr(compositionRule, ['&&', '||']);
      let result = '';
      if (splitResult.rules.length > 1) {
        result = this.getStringWithSplitRules(splitResult.rules, splitResult.splitType);
      } else {
        result = this.getStringSingle(compositionRule);
      }
      return this.applyReplaceToString(result, replacementParts);
    } catch (error) {
      logger.error(TAG, `解析规则失败: ${ruleStr}, 错误: ${String(error)}`);
      return '';
    }
  }

  /**
   * 获取字符串结果（异步版本）
   * 支持JS规则的异步执行
   */
  async getStringAsync(ruleStr: string | undefined, useFirstCssMatch: boolean = false): Promise<string> {
    if (!ruleStr || ruleStr.trim() === '') {
      return '';
    }

    try {
      this.lastJsExecutionStatus = 'not_evaluated';
      const processedRule = await this.preprocessRuleTextAsync(ruleStr);
      const replacementParts = this.splitReplaceRule(processedRule);
      const compositionRule = replacementParts.rule;

      // `||`, `&&` and `%%` are rule-combinator tokens only outside a
      // top-level JavaScript rule.  A Legado @js: body commonly contains JS
      // boolean operators (for example `encode == null || encode`); splitting
      // that body turns one executable program into invalid fragments.
      if (this.isStandaloneJavaScriptRule(compositionRule)) {
        const result = await this.getStringSingleAsync(compositionRule, useFirstCssMatch);
        return this.applyReplaceToString(result, replacementParts);
      }

      // 处理规则分割符
      const splitResult = this.splitRuleStr(compositionRule, ['&&', '||']);
      let result = '';
      if (splitResult.rules.length > 1) {
        result = await this.getStringWithSplitRulesAsync(
          splitResult.rules,
          splitResult.splitType,
          useFirstCssMatch
        );
      } else {
        result = await this.getStringSingleAsync(compositionRule, useFirstCssMatch);
      }
      return this.applyReplaceToString(result, replacementParts);
    } catch (error) {
      logger.error(TAG, `解析规则失败(异步): ${ruleStr}, 错误: ${String(error)}`);
      return '';
    }
  }

  /**
   * 使用分割规则获取字符串（异步版本）
   */
  private async getStringWithSplitRulesAsync(
    rules: string[],
    splitType: string,
    useFirstCssMatch: boolean
  ): Promise<string> {
    const results: string[] = [];
    
    for (const rule of rules) {
      const result = await this.getStringSingleAsync(rule, useFirstCssMatch);
      if (result) {
        results.push(result);
        // || 操作：第一个有结果就返回
        if (splitType === '||') {
          return result;
        }
      }
    }
    
    // && 操作：合并所有结果
    if (splitType === '&&') {
      return results.join('\n');
    }
    
    // %% 操作：交叉合并（对于单个字符串，直接返回第一个）
    return results.length > 0 ? results[0] : '';
  }

  /**
   * 获取单个规则的字符串结果（异步版本）
   */
  private async getStringSingleAsync(ruleStr: string, useFirstCssMatch: boolean = false): Promise<string> {
    const jsonPrefixJsRule = this.parseJsonPrefixJavaScriptRule(ruleStr);
    if (jsonPrefixJsRule !== null) {
      const mainResult = await this.getStringSingleInternalAsync(jsonPrefixJsRule.mainRule, useFirstCssMatch);
      if (mainResult.length <= 0) {
        this.lastJsExecutionStatus = 'main_rule_empty';
        return '';
      }
      const jsWithResult = `var result = ${JSON.stringify(mainResult)}; ${jsonPrefixJsRule.jsCode}`;
      return await this.evalJSAsync(jsWithResult);
    }

    const chainedParts = this.splitJsonFirstRuleChain(ruleStr);
    if (chainedParts.length > 1) {
      return await this.getStringFromJsonFirstRuleChainAsync(chainedParts, useFirstCssMatch);
    }

    // 检查是否是组合规则：主规则@js:JS代码
    const jsPostfixMatch = ruleStr.match(/^(.+?)@js:([\s\S]+)$/i);
    if (jsPostfixMatch) {
      const mainRule = jsPostfixMatch[1].trim();
      const jsCode = jsPostfixMatch[2].trim();
      
      // 先执行主规则获取结果
      const mainResult = await this.getStringSingleInternalAsync(mainRule, useFirstCssMatch);
      
      // 将主规则结果作为result传给JS执行
      if (mainResult) {
        const jsWithResult = `var result = ${JSON.stringify(mainResult)}; ${jsCode}`;
        return await this.evalJSAsync(jsWithResult);
      }
      this.lastJsExecutionStatus = 'main_rule_empty';
      return '';
    }
    
    return await this.getStringSingleInternalAsync(ruleStr, useFirstCssMatch);
  }

  /**
   * Evaluates only a deterministic, selector-only CSS chain through the DOM
   * bridge. It is diagnostic-only and never changes the active rule result.
   */
  getSimpleCssChainBridgeProbe(ruleStr: string | undefined): LegadoSimpleCssChainBridgeProbe {
    if (this.htmlBridge === null) {
      return new LegadoSimpleCssChainBridgeProbe('bridge_unavailable', '');
    }
    if (ruleStr === undefined) {
      return new LegadoSimpleCssChainBridgeProbe('not_applicable', '');
    }
    const rule = ruleStr.trim();
    if (rule.length <= 0 || rule.includes('##') || rule.includes('<js>') || rule.includes('&&') ||
      rule.includes('||') || rule.includes('%%') || rule.includes('@put:') || rule.includes('@get:') ||
      this.hasLegacyIndexInCssChain(rule)) {
      return new LegadoSimpleCssChainBridgeProbe('not_applicable', '');
    }
    const parts = rule.split('@');
    if (parts.length < 2) {
      return new LegadoSimpleCssChainBridgeProbe('not_applicable', '');
    }
    const finalAttribute = parts[parts.length - 1].trim().toLowerCase();
    if (!['text', 'textnodes', 'owntext', 'html', 'all', 'href', 'src', 'title', 'alt', 'value', 'content'].includes(finalAttribute)) {
      return new LegadoSimpleCssChainBridgeProbe('not_applicable', '');
    }
    for (let index = 0; index < parts.length - 1; index++) {
      const selector = parts[index].trim();
      if (!(selector === 'children' || selector.startsWith('class.') || selector.startsWith('id.') || selector.startsWith('tag.'))) {
        return new LegadoSimpleCssChainBridgeProbe('not_applicable', '');
      }
    }
    try {
      return new LegadoSimpleCssChainBridgeProbe('available', this.htmlBridge.parseChainRule(rule));
    } catch (error) {
      logger.warn(TAG, `CSS chain DOM probe failed: ${String(error)}`);
      return new LegadoSimpleCssChainBridgeProbe('bridge_error', '');
    }
  }

  private async getStringFromJsonFirstRuleChainAsync(
    parts: string[],
    useFirstCssMatch: boolean = false
  ): Promise<string> {
    const firstResult = await this.getStringSingleInternalAsync(parts[0], useFirstCssMatch);
    if (firstResult.length <= 0) {
      return '';
    }
    let currentContent = firstResult;
    for (let i = 1; i < parts.length; i++) {
      const part = parts[i];
      const result = await this.getStringSingleInternalAsyncWithContent(part, currentContent, useFirstCssMatch);
      if (result.length <= 0) {
        return '';
      }
      currentContent = result;
    }
    return currentContent;
  }

  private async getStringSingleInternalAsyncWithContent(
    ruleStr: string,
    content: string,
    useFirstCssMatch: boolean = false
  ): Promise<string> {
    const originalContent = this.content;
    const originalBridge = this.htmlBridge;
    const originalIsJSON = this.isJSON;
    this.content = content;
    this.isJSON = this.checkIsJSON(content);
    this.htmlBridge = null;
    try {
      return await this.getStringSingleInternalAsync(ruleStr, useFirstCssMatch);
    } finally {
      this.content = originalContent;
      this.isJSON = originalIsJSON;
      this.htmlBridge = originalBridge;
    }
  }
  
  /**
   * 内部方法：获取单个规则的字符串结果（异步版本）
   */
  private async getStringSingleInternalAsync(
    ruleStr: string,
    useFirstCssMatch: boolean = false
  ): Promise<string> {
    const regexGroupValue = this.getStringFromRegexGroupPayload(ruleStr);
    if (regexGroupValue !== null) {
      return regexGroupValue;
    }

    const parsedRule = this.parseRule(ruleStr);
    if (LegadoRuleAnalyzer.ENABLE_SELECTOR_TRACE) {
      logger.debug(TAG, `getStringSingleInternalAsync: mode=${parsedRule.mode}, rule=${ruleStr.substring(0, 50)}...`);
    }
    
    // 处理put变量
    if (parsedRule.putMap) {
      for (const key of Object.keys(parsedRule.putMap)) {
        const value = await this.getPutRuleValueAsync(parsedRule.putMap[key]);
        this.variables.set(key, value);
      }
    }

    let result = '';
    
    switch (parsedRule.mode) {
      case LegadoRuleMode.Json:
        result = this.getStringByJsonPath(parsedRule.rule);
        break;
      case LegadoRuleMode.XPath:
        result = this.getStringByXPath(parsedRule.rule);
        break;
      case LegadoRuleMode.Regex:
        result = this.getStringByRegex(parsedRule.rule);
        break;
      case LegadoRuleMode.Js:
        if (LegadoRuleAnalyzer.ENABLE_SELECTOR_TRACE) {
          logger.debug(TAG, `执行JS规则(异步), content长度=${this.content.length}, content前100字符=${this.content.substring(0, 100)}`);
        }
        result = await this.evalJSAsync(parsedRule.rule);
        if (LegadoRuleAnalyzer.ENABLE_SELECTOR_TRACE) {
          logger.debug(TAG, `JS规则执行结果: ${result.substring(0, 100)}`);
        }
        break;
      case LegadoRuleMode.Default:
      default:
        result = this.getStringByCSS(parsedRule.rule, useFirstCssMatch);
        break;
    }

    // 应用替换规则
    if (parsedRule.replaceRegex && result) {
      result = this.applyReplace(result, parsedRule.replaceRegex, 
        parsedRule.replacement || '', parsedRule.replaceFirst || false);
    }

    return result;
  }

  /**
   * 分割规则字符串
   * 支持 &&, ||, %% 分割符
   */
  private splitRuleStr(ruleStr: string, allowedSplitters: string[] = ['&&', '||', '%%']): RuleSplitResult {
    const cacheKey = `${allowedSplitters.join('|')}::${ruleStr}`;
    const cached = LegadoRuleAnalyzer.RULE_SPLIT_CACHE.get(cacheKey);
    if (cached) {
      return cached;
    }

    // Legado chooses the first top-level operator by source position, then
    // recursively keeps that operator for the remaining segments. A fixed
    // operator priority changes mixed expressions such as A&&B||C.
    const firstOperator = this.findFirstTopLevelSplitter(ruleStr, allowedSplitters);
    const result: RuleSplitResult = firstOperator === null
      ? { rules: [ruleStr], splitType: '' }
      : { rules: this.safeSplit(ruleStr, firstOperator.operator), splitType: firstOperator.operator };
    LegadoRuleAnalyzer.putRuleSplitCache(cacheKey, result);
    return result;
  }

  private findFirstTopLevelSplitter(str: string, splitters: string[]): JsonFilterOperatorMatch | null {
    let inQuote = false;
    let quoteChar = '';
    let inJsTag = false;
    let bracketDepth = 0;
    let parenDepth = 0;
    let braceDepth = 0;
    for (let i = 0; i < str.length; i++) {
      if (this.isJsOpenTagAt(str, i)) {
        inJsTag = true;
        i += 3;
        continue;
      }
      if (this.isJsCloseTagAt(str, i)) {
        inJsTag = false;
        i += 4;
        continue;
      }
      if (inJsTag) {
        continue;
      }
      const char = str[i];
      if ((char === '"' || char === "'") && (i === 0 || str[i - 1] !== '\\')) {
        if (!inQuote) {
          inQuote = true;
          quoteChar = char;
        } else if (char === quoteChar) {
          inQuote = false;
        }
        continue;
      }
      if (inQuote) {
        continue;
      }
      if (char === '[') {
        bracketDepth++;
        continue;
      }
      if (char === ']' && bracketDepth > 0) {
        bracketDepth--;
        continue;
      }
      if (char === '(') {
        parenDepth++;
        continue;
      }
      if (char === ')' && parenDepth > 0) {
        parenDepth--;
        continue;
      }
      if (char === '{') {
        braceDepth++;
        continue;
      }
      if (char === '}' && braceDepth > 0) {
        braceDepth--;
        continue;
      }
      if (bracketDepth > 0 || parenDepth > 0 || braceDepth > 0) {
        continue;
      }
      for (let splitterIndex = 0; splitterIndex < splitters.length; splitterIndex++) {
        const splitter = splitters[splitterIndex];
        if (this.matchesSplitterAt(str, i, splitter)) {
          return { operator: splitter, index: i };
        }
      }
    }
    return null;
  }

  /**
   * 检查是否包含分割符（排除引号内和<js>标签内的）
   */
  private containsSplitter(str: string, splitter: string): boolean {
    let inQuote = false;
    let quoteChar = '';
    let inJsTag = false;

    for (let i = 0; i < str.length; i++) {
      // 检查是否进入或离开<js>标签
      if (this.isJsOpenTagAt(str, i)) {
        inJsTag = true;
        i += 3;
        continue;
      }
      if (this.isJsCloseTagAt(str, i)) {
        inJsTag = false;
        i += 4;
        continue;
      }
      
      // 在<js>标签内，跳过分割符检查
      if (inJsTag) {
        continue;
      }
      
      const char = str[i];
      if ((char === '"' || char === "'") && (i === 0 || str[i-1] !== '\\')) {
        if (!inQuote) {
          inQuote = true;
          quoteChar = char;
        } else if (char === quoteChar) {
          inQuote = false;
        }
      }
      if (!inQuote && this.matchesSplitterAt(str, i, splitter)) {
        return true;
      }
    }
    return false;
  }

  /**
   * 安全分割字符串（排除引号内和<js>标签内的分割符）
   */
  private safeSplit(str: string, splitter: string): string[] {
    const results: string[] = [];
    let current = '';
    let inQuote = false;
    let quoteChar = '';
    let inJsTag = false;
    let bracketDepth = 0;
    let parenDepth = 0;
    let braceDepth = 0;

    for (let i = 0; i < str.length; i++) {
      // 检查是否进入或离开<js>标签
      if (this.isJsOpenTagAt(str, i)) {
        inJsTag = true;
        current += str[i] + str[i + 1] + str[i + 2] + str[i + 3];
        i += 3;
        continue;
      }
      if (this.isJsCloseTagAt(str, i)) {
        inJsTag = false;
        current += str[i] + str[i + 1] + str[i + 2] + str[i + 3] + str[i + 4];
        i += 4;
        continue;
      }
      
      const char = str[i];
      
      // 在<js>标签内，直接添加字符，不检查分割符
      if (inJsTag) {
        current += char;
        continue;
      }
      
      if ((char === '"' || char === "'") && (i === 0 || str[i-1] !== '\\')) {
        if (!inQuote) {
          inQuote = true;
          quoteChar = char;
        } else if (char === quoteChar) {
          inQuote = false;
        }
      }

      if (!inQuote) {
        if (char === '[') bracketDepth++;
        else if (char === ']' && bracketDepth > 0) bracketDepth--;
        else if (char === '(') parenDepth++;
        else if (char === ')' && parenDepth > 0) parenDepth--;
        else if (char === '{') braceDepth++;
        else if (char === '}' && braceDepth > 0) braceDepth--;
      }

      if (!inQuote && bracketDepth === 0 && parenDepth === 0 && braceDepth === 0 &&
        this.matchesSplitterAt(str, i, splitter)) {
        if (current.trim()) {
          results.push(current.trim());
        }
        current = '';
        i += splitter.length - 1;
      } else {
        current += char;
      }
    }
    
    if (current.trim()) {
      results.push(current.trim());
    }
    return results;
  }

  /**
   * 使用分割规则获取字符串
   */
  private getStringWithSplitRules(rules: string[], splitType: string): string {
    const results: string[] = [];
    
    for (const rule of rules) {
      const result = this.getStringSingle(rule);
      if (result) {
        results.push(result);
        // || 操作：第一个有结果就返回
        if (splitType === '||') {
          return result;
        }
      }
    }
    
    // && 操作：合并所有结果
    if (splitType === '&&') {
      return results.join('\n');
    }
    
    // %% 操作：交叉合并（对于单个字符串，直接返回第一个）
    return results.length > 0 ? results[0] : '';
  }

  /**
   * 获取单个规则的字符串结果
   * 支持组合规则：如 $.name@js:java.put("name",result);result
   */
  private getStringSingle(ruleStr: string): string {
    const jsonPrefixJsRule = this.parseJsonPrefixJavaScriptRule(ruleStr);
    if (jsonPrefixJsRule !== null) {
      const mainResult = this.getStringSingleInternal(jsonPrefixJsRule.mainRule);
      if (mainResult.length <= 0) {
        return '';
      }
      return this.evalJS(`var result = ${JSON.stringify(mainResult)}; ${jsonPrefixJsRule.jsCode}`);
    }

    const chainedParts = this.splitJsonFirstRuleChain(ruleStr);
    if (chainedParts.length > 1) {
      return this.getStringFromJsonFirstRuleChain(chainedParts);
    }

    // 检查是否是组合规则：主规则@js:JS代码
    // 例如：$.name@js:java.put("name",result);result
    const jsPostfixMatch = ruleStr.match(/^(.+?)@js:([\s\S]+)$/i);
    if (jsPostfixMatch) {
      const mainRule = jsPostfixMatch[1].trim();
      const jsCode = jsPostfixMatch[2].trim();
      
      // 先执行主规则获取结果
      const mainResult = this.getStringSingleInternal(mainRule);
      
      // 将主规则结果作为result传给JS执行
      if (mainResult) {
        // 构建JS执行环境，将mainResult作为result变量
        const jsWithResult = `var result = ${JSON.stringify(mainResult)}; ${jsCode}`;
        return this.evalJS(jsWithResult);
      }
      return '';
    }

    return this.getStringSingleInternal(ruleStr);
  }

  /** A complete @js:/<js> rule owns its internal boolean operators. */
  private isStandaloneJavaScriptRule(ruleStr: string): boolean {
    const normalized = ruleStr.trim().toLowerCase();
    return normalized.startsWith('@js:') ||
      (normalized.startsWith('<js>') && normalized.includes('</js>'));
  }

  /**
   * Legado permits a JSON rule to feed its value into a trailing JS block,
   * for example `$.bid<js>java.put('id', result); result</js>`. This is
   * distinct from a top-level `<js>` rule and from the CSS `attr<js>` form:
   * the JSONPath must run first, then the resulting value becomes `result`.
   */
  private parseJsonPrefixJavaScriptRule(ruleStr: string): JsonPrefixJavaScriptRule | null {
    const trimmed = ruleStr.trim();
    const normalized = trimmed.toLowerCase();
    const openingIndex = normalized.indexOf('<js>');
    const closingIndex = normalized.lastIndexOf('</js>');
    if (openingIndex <= 0 || closingIndex <= openingIndex + 4 || closingIndex + 5 !== trimmed.length) {
      return null;
    }

    const mainRule = trimmed.substring(0, openingIndex).trim();
    if (!this.isJsonRuleAfterLeadingPutRules(mainRule)) {
      return null;
    }

    return {
      mainRule: mainRule,
      jsCode: trimmed.substring(openingIndex + 4, closingIndex)
    };
  }

  private isJsonRuleAfterLeadingPutRules(ruleStr: string): boolean {
    let remaining = ruleStr.trim();
    while (remaining.toLowerCase().startsWith('@put:{')) {
      const braceEnd = this.findBalancedBraceEnd(remaining, 5);
      if (braceEnd < 0) {
        return false;
      }
      remaining = remaining.substring(braceEnd + 1).trim();
    }
    return this.startsWithJsonRulePrefix(remaining) ||
      (this.isJSON && /^[a-zA-Z_][a-zA-Z0-9_]*(\.[a-zA-Z_][a-zA-Z0-9_]*|\[\d+\])*$/.test(remaining));
  }

  private splitJsonFirstRuleChain(ruleStr: string): string[] {
    const trimmed = ruleStr.trim();
    if (!this.startsWithJsonRulePrefix(trimmed)) {
      return [ruleStr];
    }
    const parts: string[] = [];
    let current = '';
    let quote = '';
    let escaped = false;
    let bracketDepth = 0;
    let parenDepth = 0;
    let braceDepth = 0;
    for (let i = 0; i < trimmed.length; i++) {
      const ch = trimmed[i];
      if (quote.length > 0) {
        current += ch;
        if (escaped) {
          escaped = false;
        } else if (ch === '\\') {
          escaped = true;
        } else if (ch === quote) {
          quote = '';
        }
        continue;
      }
      if (ch === '"' || ch === "'") {
        quote = ch;
        current += ch;
        continue;
      }
      if (ch === '[') {
        bracketDepth++;
      } else if (ch === ']' && bracketDepth > 0) {
        bracketDepth--;
      } else if (ch === '(') {
        parenDepth++;
      } else if (ch === ')' && parenDepth > 0) {
        parenDepth--;
      } else if (ch === '{') {
        braceDepth++;
      } else if (ch === '}' && braceDepth > 0) {
        braceDepth--;
      }
      if (ch === '@' && bracketDepth === 0 && parenDepth === 0 && braceDepth === 0) {
        // `$.url@js:...` is a single postfix-JS rule, not a JSON-first
        // chain. Splitting it here turns the second segment into `js:...`,
        // which is then incorrectly treated as a selector and silently loses
        // the URL. Leave the complete rule for getStringSingleAsync(), which
        // binds the first JSON result to `result` before executing the JS.
        if (trimmed.substring(i).toLowerCase().startsWith('@js:')) {
          return [ruleStr];
        }
        if (current.trim().length > 0) {
          parts.push(current.trim());
        }
        current = '';
      } else {
        current += ch;
      }
    }
    if (current.trim().length > 0) {
      parts.push(current.trim());
    }
    return parts.length > 1 ? parts : [ruleStr];
  }

  private startsWithJsonRulePrefix(rule: string): boolean {
    return rule.startsWith('$.') ||
      rule.startsWith('$[') ||
      rule.startsWith('@Json:') ||
      rule.startsWith('@json:');
  }

  private getStringFromJsonFirstRuleChain(parts: string[]): string {
    const firstResult = this.getStringSingleInternal(parts[0]);
    if (firstResult.length <= 0) {
      return '';
    }
    let currentContent = firstResult;
    for (let i = 1; i < parts.length; i++) {
      const part = parts[i];
      const result = this.getStringSingleInternalWithContent(part, currentContent);
      if (result.length <= 0) {
        return '';
      }
      currentContent = result;
    }
    return currentContent;
  }
  
  /**
   * 内部方法：获取单个规则的字符串结果
   */
  private getStringSingleInternal(ruleStr: string): string {
    const regexGroupValue = this.getStringFromRegexGroupPayload(ruleStr);
    if (regexGroupValue !== null) {
      return regexGroupValue;
    }

    const parsedRule = this.parseRule(ruleStr);
    
    // 处理put变量
    if (parsedRule.putMap) {
      Object.keys(parsedRule.putMap).forEach((key: string): void => {
        const value = this.getPutRuleValue(parsedRule.putMap![key]);
        this.variables.set(key, value);
      });
    }

    let result = '';
    
    switch (parsedRule.mode) {
      case LegadoRuleMode.Json:
        result = this.getStringByJsonPath(parsedRule.rule);
        break;
      case LegadoRuleMode.XPath:
        result = this.getStringByXPath(parsedRule.rule);
        break;
      case LegadoRuleMode.Regex:
        result = this.getStringByRegex(parsedRule.rule);
        break;
      case LegadoRuleMode.Js:
        result = this.evalJS(parsedRule.rule);
        break;
      case LegadoRuleMode.Default:
      default:
        result = this.getStringByCSS(parsedRule.rule);
        break;
    }

    // 应用替换规则
    if (parsedRule.replaceRegex && result) {
      result = this.applyReplace(result, parsedRule.replaceRegex, 
        parsedRule.replacement || '', parsedRule.replaceFirst || false);
    }

    return result;
  }

  private getStringSingleInternalWithContent(ruleStr: string, content: string): string {
    const originalContent = this.content;
    const originalBridge = this.htmlBridge;
    const originalIsJSON = this.isJSON;
    this.content = content;
    this.isJSON = this.checkIsJSON(content);
    this.htmlBridge = null;
    try {
      return this.getStringSingleInternal(ruleStr);
    } finally {
      this.content = originalContent;
      this.isJSON = originalIsJSON;
      this.htmlBridge = originalBridge;
    }
  }

  private preprocessRuleText(ruleStr: string): string {
    let processedRule = ruleStr;
    if (processedRule.includes('@get:')) {
      processedRule = processedRule.replace(/@get:\{([^}]+)\}/gi, (_match: string, key: string): string => {
        return this.variables.get(key.trim()) || '';
      });
    }

    if (processedRule.includes('{{') && processedRule.includes('}}')) {
      processedRule = this.replaceTemplateVariables(processedRule);
    }
    return processedRule;
  }

  private async preprocessRuleTextAsync(ruleStr: string): Promise<string> {
    let processedRule = ruleStr;
    if (processedRule.includes('@get:')) {
      processedRule = processedRule.replace(/@get:\{([^}]+)\}/gi, (_match: string, key: string): string => {
        return this.variables.get(key.trim()) || '';
      });
    }

    if (processedRule.includes('{{') && processedRule.includes('}}')) {
      processedRule = await this.replaceTemplateVariablesAsync(processedRule);
    }
    return processedRule;
  }

  getVariableValue(key: string): string {
    return this.variables.get(key) || '';
  }

  /**
   * Mirrors AnalyzeRule.getString(..., isUrl = true): a default/CSS rule
   * contributes only its first matched value before URL resolution. Text
   * extraction remains multi-value and keeps Legado's newline joining.
   */
  async getUrlStringAsync(ruleStr: string | undefined): Promise<string> {
    if (!ruleStr || ruleStr.trim().length === 0) {
      return '';
    }
    const processedRule = await this.preprocessRuleTextAsync(ruleStr);
    // AnalyzeRule.makeUpRule expands {{$.field}} before the rule mode is
    // evaluated.  A resulting absolute URL is the value itself, not a CSS
    // selector.  Sending it through the default selector branch loses URLs
    // such as https://host/path?bookId={{$.bookId}} on JSON search results.
    if (this.isExpandedAbsoluteUrl(processedRule)) {
      return processedRule.trim();
    }
    return await this.getStringAsync(processedRule, true);
  }

  /**
   * URL-list rules use the same literal-after-template rule as single URLs.
   * Keep the existing selector list behaviour for CSS/JSONPath rules so toc
   * and content pagination can still return sibling links.
   */
  async getUrlStringListAsync(ruleStr: string | undefined): Promise<string[]> {
    if (!ruleStr || ruleStr.trim().length === 0) {
      return [];
    }
    const processedRule = await this.preprocessRuleTextAsync(ruleStr);
    if (this.isExpandedAbsoluteUrl(processedRule)) {
      return [processedRule.trim()];
    }
    const values = this.getStringList(processedRule);
    if (values.length > 0) {
      return values;
    }
    const value = await this.getUrlStringAsync(processedRule);
    return value.length > 0 ? [value] : [];
  }

  private isExpandedAbsoluteUrl(value: string): boolean {
    const trimmed = value.trim();
    return /^https?:\/\/[^\s]+$/i.test(trimmed) ||
      /^data:[^\s]+$/i.test(trimmed);
  }

  /**
   * 替换模板变量 {{$.xxx}} 或 {{xxx}} 或 @get:{xxx}
   */
  private replaceTemplateVariables(template: string): string {
    let result = template;
    
    // 处理 @get:{xxx} 变量获取
    result = result.replace(/@get:\{([^}]+)\}/gi, (match: string, key: string): string => {
      const trimmedKey = key.trim();
      return this.variables.get(trimmedKey) || '';
    });
    
    // 匹配 {{...}} 模板变量
    const pattern = /\{\{([^}]+)\}\}/g;
    
    result = result.replace(pattern, (match: string, expr: string): string => {
      const trimmedExpr = expr.trim();
      
      // 处理 $.xxx 形式的JSONPath表达式
      if (trimmedExpr.startsWith('$.') || trimmedExpr.startsWith('$[')) {
        return this.getStringByJsonPath(trimmedExpr);
      }
      
      // 处理 xxx || 'default' 形式的默认值表达式
      if (trimmedExpr.includes('||')) {
        const parts = trimmedExpr.split('||').map((p: string): string => p.trim());
        for (const part of parts) {
          if (part.startsWith("'") && part.endsWith("'")) {
            return part.slice(1, -1);
          }
          if (part.startsWith('"') && part.endsWith('"')) {
            return part.slice(1, -1);
          }
          if (part.startsWith('$.') || part.startsWith('$[')) {
            const value = this.getStringByJsonPath(part);
            if (value) {
              return value;
            }
          }
          // 尝试作为变量名
          if (this.variables.has(part)) {
            const value = this.variables.get(part);
            if (value) {
              return value;
            }
          }
        }
        return '';
      }
      
      // 尝试作为变量名从variables中获取
      if (this.variables.has(trimmedExpr)) {
        return this.variables.get(trimmedExpr) || '';
      }
      
      // 处理 @@xxx 形式的规则（从当前内容解析）
      // 例如: {{@@tag.a.0@href}} 表示从当前内容中提取 tag.a.0@href
      if (trimmedExpr.startsWith('@@')) {
        const innerRule = trimmedExpr.substring(2); // 去掉 @@
        const value = this.getStringSingle(innerRule);
        return value || '';
      }
      
      // 处理 @xxx 形式的规则（Legado选择器）
      if (trimmedExpr.startsWith('@') && !trimmedExpr.startsWith('@get:')) {
        const value = this.getStringSingle(trimmedExpr.substring(1));
        return value || '';
      }

      if (this.looksLikeRuleExpression(trimmedExpr)) {
        const value = this.getStringSingle(trimmedExpr);
        return value || '';
      }
      
      // 尝试作为JSONPath解析
      const value = this.getStringByJsonPath('$.' + trimmedExpr);
      return value || match;
    });
    
    return result;
  }

  private async replaceTemplateVariablesAsync(template: string): Promise<string> {
    let result = '';
    const pattern = /\{\{([^}]+)\}\}/g;
    let lastIndex = 0;
    let match: RegExpExecArray | null = pattern.exec(template);
    while (match !== null) {
      result += template.substring(lastIndex, match.index);
      result += await this.resolveTemplateExpressionAsync(match[1]);
      lastIndex = pattern.lastIndex;
      match = pattern.exec(template);
    }
    result += template.substring(lastIndex);

    result = result.replace(/@get:\{([^}]+)\}/gi, (rawMatch: string, key: string): string => {
      const trimmedKey = key.trim();
      return this.variables.get(trimmedKey) || '';
    });
    return result;
  }

  private async resolveTemplateExpressionAsync(expr: string): Promise<string> {
    const trimmedExpr = expr.trim();
    if (trimmedExpr.length <= 0) {
      return '';
    }
    if (trimmedExpr.startsWith('$.') || trimmedExpr.startsWith('$[')) {
      return this.getStringByJsonPath(trimmedExpr);
    }
    if (trimmedExpr.includes('||')) {
      const parts = trimmedExpr.split('||').map((p: string): string => p.trim());
      for (let i = 0; i < parts.length; i++) {
        const value = await this.resolveTemplateExpressionAsync(parts[i]);
        if (value.length > 0) {
          return value;
        }
      }
      return '';
    }
    if (trimmedExpr.startsWith("'") && trimmedExpr.endsWith("'")) {
      return trimmedExpr.slice(1, -1);
    }
    if (trimmedExpr.startsWith('"') && trimmedExpr.endsWith('"')) {
      return trimmedExpr.slice(1, -1);
    }
    if (this.variables.has(trimmedExpr)) {
      return this.variables.get(trimmedExpr) || '';
    }
    if (trimmedExpr.startsWith('@@')) {
      return await this.getStringSingleAsync(trimmedExpr.substring(2));
    }
    if (trimmedExpr.startsWith('@') && !trimmedExpr.startsWith('@get:')) {
      return await this.getStringSingleAsync(trimmedExpr.substring(1));
    }
    if (this.looksLikeRuleExpression(trimmedExpr)) {
      return await this.getStringSingleAsync(trimmedExpr);
    }
    return await this.evalJSAsync(trimmedExpr);
  }

  private looksLikeRuleExpression(expr: string): boolean {
    return expr.startsWith('$.') ||
      expr.startsWith('$[') ||
      expr.startsWith('//') ||
      expr.startsWith('@XPath:') ||
      expr.startsWith('@xpath:') ||
      expr.startsWith('@Json:') ||
      expr.startsWith('@json:') ||
      expr.startsWith('@CSS:') ||
      expr.startsWith('@css:');
  }

  /**
   * 获取字符串列表
   * 支持规则分割符: && (与), || (或), %% (交叉合并)
   */
  getStringList(ruleStr: string | undefined): string[] {
    if (!ruleStr || ruleStr.trim() === '') {
      return [];
    }

    try {
      const processedRule = this.preprocessRuleText(ruleStr);
      const replacementParts = this.splitReplaceRule(processedRule);
      const compositionRule = replacementParts.rule;
      // 处理规则分割符
      const splitResult = this.splitRuleStr(compositionRule);
      let results: string[];
      if (splitResult.rules.length > 1) {
        results = this.getStringListWithSplitRules(splitResult.rules, splitResult.splitType);
      } else {
        results = this.getStringListSingle(compositionRule);
      }
      return this.applyReplaceToList(results, replacementParts);
    } catch (error) {
      logger.error(TAG, `解析列表规则失败: ${ruleStr}, 错误: ${String(error)}`);
      return [];
    }
  }

  /**
   * 使用分割规则获取字符串列表
   */
  private getStringListWithSplitRules(rules: string[], splitType: string): string[] {
    const allResults: string[][] = [];
    
    for (const rule of rules) {
      const results = this.getStringListSingle(rule);
      if (results.length > 0) {
        allResults.push(results);
        // || 操作：第一个有结果就返回
        if (splitType === '||') {
          return results;
        }
      }
    }
    
    if (allResults.length === 0) {
      return [];
    }
    
    // && 操作：合并所有结果
    if (splitType === '&&') {
      const merged: string[] = [];
      for (const results of allResults) {
        for (const r of results) {
          merged.push(r);
        }
      }
      return merged;
    }
    
    // %% 操作：交叉合并
    if (splitType === '%%') {
      const merged: string[] = [];
      const maxLen = Math.max(...allResults.map(r => r.length));
      for (let i = 0; i < maxLen; i++) {
        for (const results of allResults) {
          if (i < results.length) {
            merged.push(results[i]);
          }
        }
      }
      return merged;
    }
    
    return allResults.length > 0 ? allResults[0] : [];
  }

  /**
   * 获取单个规则的字符串列表
   */
  private getStringListSingle(ruleStr: string): string[] {
    const chainedParts = this.splitJsonFirstRuleChain(ruleStr);
    if (chainedParts.length > 1) {
      return this.getStringListFromJsonFirstRuleChain(chainedParts);
    }

    const parsedRule = this.parseRule(ruleStr);
    let results: string[] = [];

    switch (parsedRule.mode) {
      case LegadoRuleMode.Json:
        results = this.getStringListByJsonPath(parsedRule.rule);
        break;
      case LegadoRuleMode.XPath:
        results = this.getStringListByXPath(parsedRule.rule);
        break;
      case LegadoRuleMode.Regex:
        results = this.getStringListByRegex(parsedRule.rule);
        break;
      case LegadoRuleMode.Default:
      default:
        results = this.getStringListByCSS(parsedRule.rule);
        break;
    }

    // 应用替换规则
    if (parsedRule.replaceRegex) {
      results = results.map((item: string): string => 
        this.applyReplace(item, parsedRule.replaceRegex!, 
          parsedRule.replacement || '', parsedRule.replaceFirst || false)
      );
    }

    return results;
  }

  private getStringListFromJsonFirstRuleChain(parts: string[]): string[] {
    const firstItems = this.getElementsSingle(parts[0]);
    if (firstItems.length <= 0) {
      return [];
    }
    const tailRule = parts.slice(1).join('@');
    const results: string[] = [];
    for (let i = 0; i < firstItems.length; i++) {
      const item = firstItems[i];
      const value = this.getStringSingleInternalWithContent(tailRule, item);
      if (value.length > 0) {
        const lines = value.split('\n');
        for (let j = 0; j < lines.length; j++) {
          const line = lines[j].trim();
          if (line.length > 0) {
            results.push(line);
          }
        }
      }
    }
    return results;
  }

  /**
   * 获取元素列表（用于遍历）
   */
  getElements(ruleStr: string): string[] {
    if (!ruleStr || ruleStr.trim() === '') {
      return [];
    }

    try {
      const processedRule = this.preprocessRuleText(ruleStr);
      // 先处理 || 操作符（或操作，第一个有结果就返回）
      if (processedRule.includes('||')) {
        const orParts = this.safeSplit(processedRule, '||');
        for (const part of orParts) {
          const trimmedPart = part.trim();
          if (trimmedPart) {
            const results = this.getElementsSingle(trimmedPart);
            if (results.length > 0) {
              // 性能优化：减少日志输出
              // logger.debug(TAG, `getElements: ||操作符，使用规则=${trimmedPart}, 结果数量=${results.length}`);
              return results;
            }
          }
        }
        return [];
      }
      
      return this.getElementsSingle(processedRule);
    } catch (error) {
      logger.error(TAG, `获取元素列表失败: ${ruleStr}, 错误: ${String(error)}`);
      return [];
    }
  }
  
  /**
   * 异步获取元素列表（支持JS规则执行）
   */
  async getElementsAsync(ruleStr: string, jsContext?: JsContext): Promise<string[]> {
    if (!ruleStr || ruleStr.trim() === '') {
      this.lastJsExecutionStatus = 'not_evaluated';
      return [];
    }

    try {
      this.lastJsExecutionStatus = 'not_evaluated';
      const processedRule = await this.preprocessRuleTextAsync(ruleStr);
      // A standalone JS rule owns its internal operators and must reach the
      // JS branch intact.  Sending it through the generic element-rule
      // splitter can classify the rule as CSS and silently return one raw
      // element without updating lastJsExecutionStatus.
      if (this.isStandaloneJavaScriptRule(processedRule)) {
        return await this.getElementsSingleAsync(processedRule, jsContext);
      }
      // 先处理 || 操作符（或操作，第一个有结果就返回）
      if (processedRule.includes('||')) {
        const orParts = this.safeSplit(processedRule, '||');
        for (const part of orParts) {
          const trimmedPart = part.trim();
          if (trimmedPart) {
            const results = await this.getElementsSingleAsync(trimmedPart, jsContext);
            if (results.length > 0) {
              // 性能优化：减少日志输出
              // logger.debug(TAG, `getElementsAsync: ||操作符，使用规则=${trimmedPart.substring(0, 50)}, 结果数量=${results.length}`);
              return results;
            }
          }
        }
        return [];
      }
      
      return await this.getElementsSingleAsync(processedRule, jsContext);
    } catch (error) {
      logger.error(TAG, `异步获取元素列表失败: ${ruleStr.substring(0, 100)}, 错误: ${String(error)}`);
      return [];
    }
  }
  
  /**
   * 异步获取单个规则的元素列表
   * 支持换行符分隔的链式规则：class.xxx\n<js>...</js>\na
   */
  private async getElementsSingleAsync(ruleStr: string, jsContext?: JsContext): Promise<string[]> {
    const normalizedRule = ruleStr.trim().toLowerCase();
    if ((normalizedRule.startsWith('@js:') || normalizedRule.startsWith('<js>')) &&
      normalizedRule.includes('</js>')) {
      const standaloneRule = this.parseRule(ruleStr);
      if (standaloneRule.mode === LegadoRuleMode.Js) {
        return await this.executeJavaScriptElementsAsync(standaloneRule.rule, jsContext);
      }
    }
    const chainedParts = this.splitJsonFirstRuleChain(ruleStr);
    if (chainedParts.length > 1) {
      return await this.getElementsFromJsonFirstRuleChainAsync(chainedParts, jsContext);
    }

    // 检查是否包含换行符分隔的链式规则（包含<js>标签的情况）
    // 格式：selector\n<js>...</js>\nselector
    if (ruleStr.includes('\n') && ruleStr.includes('<js>')) {
      return await this.processChainedRuleWithJs(ruleStr, jsContext);
    }
    
    const parsedRule = this.parseRule(ruleStr);
    // 性能优化：减少日志输出
    // logger.debug(TAG, `getElementsSingleAsync: 规则=${ruleStr.substring(0, 100)}, 模式=${parsedRule.mode}`);
    
    let results: string[] = [];
    switch (parsedRule.mode) {
      case LegadoRuleMode.Json:
        results = this.getElementsByJsonPath(parsedRule.rule);
        break;
      case LegadoRuleMode.XPath:
        results = this.getElementsByXPath(parsedRule.rule);
        break;
      case LegadoRuleMode.Regex:
        results = this.getElementsByRegex(parsedRule.rule);
        break;
      case LegadoRuleMode.Js:
        results = await this.executeJavaScriptElementsAsync(parsedRule.rule, jsContext);
        break;
      case LegadoRuleMode.Default:
      default:
        results = this.getElementsByCSS(parsedRule.rule);
        break;
    }
    // 性能优化：减少日志输出
    // logger.debug(TAG, `getElementsSingleAsync: 结果数量=${results.length}`);
    return results;
  }

  private async executeJavaScriptElementsAsync(jsRule: string, jsContext?: JsContext): Promise<string[]> {
    this.lastJsExecutionStatus = 'not_evaluated';
    try {
      let jsCode = jsRule;
      let afterJsRule = '';
      const afterJsIndex = jsCode.indexOf('\n@AFTER_JS@');
      if (afterJsIndex !== -1) {
        afterJsRule = jsCode.substring(afterJsIndex + 11);
        jsCode = jsCode.substring(0, afterJsIndex);
      }

      const jsEngine = getLegadoJsEngine();
      const context: JsContext = this.createJsContext(this.content, this.content, jsContext);
      const executeResult = await jsEngine.execute(jsCode, context);
      this.recordBridgeTraces(executeResult.bridgeTraces);
      this.syncVariablesFromRecord(executeResult.variables);
      this.syncSourceEffects(executeResult.sourceEffects);
      if (!executeResult.success) {
        this.lastJsExecutionStatus = this.toSafeJsExecutionStatus(executeResult.error);
        logger.warn(TAG, `JS规则执行失败: ${executeResult.error || 'unknown error'}`);
        return [];
      }

      const rawJsResult: string = executeResult.result.trim();
      if (rawJsResult.length === 0) {
        this.lastJsExecutionStatus = 'empty';
        return [];
      }

      if (afterJsRule) {
        this.lastJsExecutionStatus = 'result';
        this.content = rawJsResult;
        this.isJSON = this.checkIsJSON(rawJsResult);
        const afterResults: string[] = await this.getElementsAsync(afterJsRule, jsContext);
        if (afterResults.length > 0) {
          this.lastJsExecutionStatus = 'result';
        } else if (this.lastJsExecutionStatus === 'not_evaluated' || this.lastJsExecutionStatus === 'result') {
          this.lastJsExecutionStatus = 'empty';
        }
        return afterResults;
      }

      let parsed: Object;
      try {
        parsed = SafeUtils.parseObj<Object>(rawJsResult);
      } catch (parseError) {
        this.lastJsExecutionStatus = 'error_result_parse';
        logger.warn(TAG, `JS列表结果解析失败: ${String(parseError)}`);
        return [];
      }
      if (Array.isArray(parsed)) {
        const parsedArray: Object[] = parsed as Object[];
        this.lastJsExecutionStatus = parsedArray.length > 0 ? 'result' : 'empty';
        return parsedArray.map((item: Object): string =>
          typeof item === 'string' ? item : JSON.stringify(item)
        );
      }
      this.lastJsExecutionStatus = 'error_js_result_not_list';
      logger.warn(TAG, 'JS列表规则返回了非数组结果');
      return [];
    } catch (error) {
      this.lastJsExecutionStatus = this.toSafeJsExecutionStatus(String(error));
      logger.error(TAG, `JS规则执行失败: ${String(error)}`);
      return [];
    }
  }

  private async getElementsFromJsonFirstRuleChainAsync(parts: string[], jsContext?: JsContext): Promise<string[]> {
    const firstItems = this.getElementsSingle(parts[0]);
    if (firstItems.length <= 0) {
      return [];
    }
    const tailRule = parts.slice(1).join('@');
    const results: string[] = [];
    for (let i = 0; i < firstItems.length; i++) {
      const item = firstItems[i];
      const originalContent = this.content;
      const originalBridge = this.htmlBridge;
      const originalIsJSON = this.isJSON;
      this.content = item;
      this.isJSON = this.checkIsJSON(item);
      this.htmlBridge = null;
      try {
        const itemResults = await this.getElementsSingleAsync(tailRule, jsContext);
        for (let j = 0; j < itemResults.length; j++) {
          results.push(itemResults[j]);
        }
      } finally {
        this.content = originalContent;
        this.isJSON = originalIsJSON;
        this.htmlBridge = originalBridge;
      }
    }
    return results;
  }

  /**
   * Produces evidence-safe diagnostics for a pure CSS rule with Legado's
   * trailing index syntax. No rule text or HTML is returned in the diagnostic.
   */
  async getElementsWithPureCssIndexDiagnosticsAsync(ruleStr: string): Promise<LegadoRuleElementDiagnostic> {
    const elements: string[] = await this.getElementsAsync(ruleStr);
    const baseRule: string = this.getPureCssIndexBaseRule(ruleStr);
    if (baseRule.length === 0) {
      return new LegadoRuleElementDiagnostic(elements, -1, 'not_applicable');
    }
    const baseElements: string[] = await this.getElementsAsync(baseRule);
    const resolver: string = this.htmlBridge !== null ? 'html_bridge_available' : 'string_fallback';
    return new LegadoRuleElementDiagnostic(elements, baseElements.length, resolver);
  }

  private getPureCssIndexBaseRule(ruleStr: string): string {
    const rule: string = ruleStr.trim();
    if (rule.length === 0 || rule.includes('@') || rule.includes('$') || rule.includes('<js>') ||
      rule.includes('&&') || rule.includes('||') || rule.includes('##') || rule.includes('\n')) {
      return '';
    }
    const indexResult: IndexSelectorResult = this.parseIndexSelector(rule);
    return indexResult.hasIndex && indexResult.selector.trim().length > 0 ? indexResult.selector.trim() : '';
  }
  
  /**
   * 处理包含换行符和JS的链式规则
   * 格式：selector\n<js>...</js>\nselector
   * 例如：class.zw_txt\n<js>key=java.get("key");...</js>\na
   */
  private async processChainedRuleWithJs(ruleStr: string, jsContext?: JsContext): Promise<string[]> {
    // 性能优化：减少日志输出
    // logger.debug(TAG, `processChainedRuleWithJs: 处理链式规则`);
    
    // 提取<js>...</js>部分
    const jsMatch = ruleStr.match(/<js>([\s\S]*?)<\/js>/i);
    if (!jsMatch) {
      // 没有JS部分，按普通规则处理
      return this.getElementsByCSS(ruleStr.replace(/\n/g, ' '));
    }
    
    const jsCode = jsMatch[1];
    const jsFullMatch = jsMatch[0];
    const jsStartIndex = ruleStr.indexOf(jsFullMatch);
    const jsEndIndex = jsStartIndex + jsFullMatch.length;
    
    // 提取JS前后的规则
    const beforeJs = ruleStr.substring(0, jsStartIndex).trim();
    const afterJs = ruleStr.substring(jsEndIndex).trim();
    
    // 性能优化：减少日志输出
    // logger.debug(TAG, `链式规则解析: beforeJs="${beforeJs}", afterJs="${afterJs}"`);
    
    // 步骤1: 执行JS前的选择器
    let currentResults: string[] = [];
    if (beforeJs) {
      // 按换行符分割前置规则
      const beforeParts = beforeJs.split('\n').filter((p: string): boolean => p.trim().length > 0);
      if (beforeParts.length > 0) {
        currentResults = this.getElementsByCSS(beforeParts[beforeParts.length - 1].trim());
      }
    }
    
    // 如果没有前置结果，使用整个content
    if (currentResults.length === 0) {
      currentResults = [this.content];
    }
    
    // 步骤2: 对每个结果执行JS
    const jsEngine = getLegadoJsEngine();
    const processedResults: string[] = [];
    
    for (const element of currentResults) {
      try {
        const context: JsContext = this.createJsContext(element, element, jsContext);
        
        const executeResult = await jsEngine.execute(jsCode, context);
        this.recordBridgeTraces(executeResult.bridgeTraces);
        this.syncVariablesFromRecord(executeResult.variables);
        this.syncSourceEffects(executeResult.sourceEffects);
        if (!executeResult.success) {
          logger.warn(TAG, `链式规则JS执行失败: ${executeResult.error || 'unknown error'}`);
          continue;
        }
        const resultStr = executeResult.result;
        if (resultStr && resultStr.trim().length > 0 &&
          resultStr.trim() !== '[object Object]' &&
          resultStr.trim() !== '[object Array]') {
          processedResults.push(resultStr);
        } else {
          // JS仅做副作用时，继续沿用当前元素参与后续规则解析
          processedResults.push(element);
        }
      } catch (e) {
        logger.warn(TAG, `链式规则JS执行失败: ${String(e)}`);
      }
    }
    
    // 步骤3: 对JS结果执行后续选择器
    if (afterJs && processedResults.length > 0) {
      const afterParts = afterJs.split('\n').filter((p: string): boolean => p.trim().length > 0);
      if (afterParts.length > 0) {
        const finalResults: string[] = [];
        for (const result of processedResults) {
          // 临时设置content为JS结果，同时禁用HTML桥接避免不一致
          const originalContent = this.content;
          const originalBridge = this.htmlBridge;
          const originalIsJSON = this.isJSON;
          this.content = result;
          this.isJSON = this.checkIsJSON(result);
          this.htmlBridge = null; // 禁用桥接，强制使用字符串解析
          try {
            // 执行后续规则（需要完整规则解析能力，而不只是CSS）
            const afterSelector = afterParts[0].trim();
            const found = await this.getElementsAsync(afterSelector, jsContext);
            for (const f of found) {
              finalResults.push(f);
            }
          } finally {
            // 恢复content和桥接
            this.content = originalContent;
            this.isJSON = originalIsJSON;
            this.htmlBridge = originalBridge;
          }
        }
        return finalResults;
      }
    }
    
    return processedResults;
  }
  
  /**
   * 获取单个规则的元素列表
   */
  private getElementsSingle(ruleStr: string): string[] {
    const chainedParts = this.splitJsonFirstRuleChain(ruleStr);
    if (chainedParts.length > 1) {
      return this.getElementsFromJsonFirstRuleChain(chainedParts);
    }

    const parsedRule = this.parseRule(ruleStr);
    // 性能优化：减少日志输出
    // logger.debug(TAG, `getElementsSingle: 规则=${ruleStr.substring(0, 100)}, 模式=${parsedRule.mode}`);
    
    let results: string[] = [];
    switch (parsedRule.mode) {
      case LegadoRuleMode.Json:
        results = this.getElementsByJsonPath(parsedRule.rule);
        break;
      case LegadoRuleMode.XPath:
        results = this.getElementsByXPath(parsedRule.rule);
        break;
      case LegadoRuleMode.Regex:
        results = this.getElementsByRegex(parsedRule.rule);
        break;
      case LegadoRuleMode.Js:
        // JS规则需要执行JS代码，然后解析结果
        // 注意：getElementsSingle是同步方法，无法执行异步JS
        // 这里返回空数组，JS规则应该在调用方使用异步方法处理
        logger.warn(TAG, `getElementsSingle不支持JS规则，请使用异步方法`);
        results = [];
        break;
      case LegadoRuleMode.Default:
      default:
        results = this.getElementsByCSS(parsedRule.rule);
        break;
    }
    // 性能优化：减少日志输出
    // logger.debug(TAG, `getElementsSingle: 结果数量=${results.length}`);
    return results;
  }

  private getElementsFromJsonFirstRuleChain(parts: string[]): string[] {
    const firstItems = this.getElementsSingle(parts[0]);
    if (firstItems.length <= 0) {
      return [];
    }
    const tailRule = parts.slice(1).join('@');
    const results: string[] = [];
    for (let i = 0; i < firstItems.length; i++) {
      const item = firstItems[i];
      const originalContent = this.content;
      const originalBridge = this.htmlBridge;
      const originalIsJSON = this.isJSON;
      this.content = item;
      this.isJSON = this.checkIsJSON(item);
      this.htmlBridge = null;
      try {
        const itemResults = this.getElementsSingle(tailRule);
        for (let j = 0; j < itemResults.length; j++) {
          results.push(itemResults[j]);
        }
      } finally {
        this.content = originalContent;
        this.isJSON = originalIsJSON;
        this.htmlBridge = originalBridge;
      }
    }
    return results;
  }

  // ==================== JSONPath解析 ====================

  /**
   * 通过JSONPath获取字符串
   */
  private getStringByJsonPath(path: string): string {
    try {
      const data: Object = SafeUtils.parseObj(this.content);
      const embeddedResult: string | null = this.replaceJsonPathEmbeddedRules(path, data as ESObject);
      if (embeddedResult !== null) {
        return embeddedResult;
      }
      const result: Object | null = this.evaluateJsonPath(data as ESObject, path);
      if (result === null || result === undefined) {
        return '';
      }
      if (Array.isArray(result)) {
        return result.map((item: ESObject): string => this.valueToString(item)).join('\n');
      }
      return this.valueToString(result);
    } catch (error) {
      logger.warn(TAG, `JSONPath解析失败: ${path}`);
      return '';
    }
  }

  /**
   * 将值转换为字符串，对象转为JSON字符串
   */
  private valueToString(value: ESObject): string {
    if (value === null || value === undefined) {
      return '';
    }
    if (typeof value === 'object') {
      return JSON.stringify(value);
    }
    return String(value);
  }

  /**
   * 通过JSONPath获取字符串列表
   */
  private getStringListByJsonPath(path: string): string[] {
    try {
      const data: Object = SafeUtils.parseObj(this.content);
      const embeddedResult: string | null = this.replaceJsonPathEmbeddedRules(path, data as ESObject);
      if (embeddedResult !== null) {
        return embeddedResult.length > 0 ? [embeddedResult] : [];
      }
      const result: Object | null = this.evaluateJsonPath(data as ESObject, path);
      if (Array.isArray(result)) {
        return result.map((item: ESObject): string => this.valueToString(item));
      }
      return result !== null && result !== undefined ? [this.valueToString(result)] : [];
    } catch (error) {
      logger.warn(TAG, `JSONPath列表解析失败: ${path}`);
      return [];
    }
  }

  /**
   * 通过JSONPath获取元素列表
   */
  private getElementsByJsonPath(path: string): string[] {
    try {
      // 检查内容是否为空
      if (!this.content || this.content.trim() === '') {
        this.selectorTrace((): string => `JSONPath解析: 内容为空`);
        return [];
      }
      
      // 尝试解析JSON
      let data: Object;
      try {
        data = SafeUtils.parseObj(this.content);
      } catch (parseError) {
        // 内容不是有效的JSON，可能是HTML
        this.selectorTrace((): string => `JSONPath解析: 内容不是有效JSON，跳过`);
        return [];
      }
      
      const embeddedResult: string | null = this.replaceJsonPathEmbeddedRules(path, data as ESObject);
      if (embeddedResult !== null) {
        return embeddedResult.length > 0 ? [embeddedResult] : [];
      }
      const result: Object | null = this.evaluateJsonPath(data as ESObject, path);
      if (Array.isArray(result)) {
        return result.map((item: ESObject): string => this.valueToElementString(item));
      }
      return result !== null && result !== undefined ? [this.valueToElementString(result as ESObject)] : [];
    } catch (error) {
      logger.warn(TAG, `JSONPath元素解析失败: ${path}, 错误: ${String(error)}`);
      return [];
    }
  }

  private replaceJsonPathEmbeddedRules(path: string, data: ESObject): string | null {
    const hasEmbeddedRule = path.includes('{$.') || path.includes('{$[');
    if (!hasEmbeddedRule) {
      return null;
    }

    let result = '';
    let lastIndex = 0;
    let replaced = false;
    for (let i = 0; i < path.length; i++) {
      if (path[i] !== '{' || i + 2 >= path.length || path[i + 1] !== '$') {
        continue;
      }
      const pathStart = path[i + 2];
      if (pathStart !== '.' && pathStart !== '[') {
        continue;
      }

      const endIndex = this.findBalancedBraceEnd(path, i);
      if (endIndex < 0) {
        continue;
      }

      const innerPath = path.substring(i + 1, endIndex);
      const value: ESObject = this.evaluateJsonPath(data, innerPath);
      const valueString = this.jsonPathResultToString(value);
      if (valueString.length > 0) {
        result += path.substring(lastIndex, i);
        result += valueString;
        lastIndex = endIndex + 1;
        replaced = true;
      }
      i = endIndex;
    }

    if (!replaced) {
      return null;
    }
    result += path.substring(lastIndex);
    return result;
  }

  private jsonPathResultToString(value: ESObject): string {
    if (value === null || value === undefined) {
      return '';
    }
    if (Array.isArray(value)) {
      return value.map((item: ESObject): string => this.valueToString(item)).join('\n');
    }
    return this.valueToString(value);
  }

  private findBalancedBraceEnd(text: string, startIndex: number): number {
    let depth = 0;
    let quote = '';
    let escaped = false;
    for (let i = startIndex; i < text.length; i++) {
      const ch = text[i];
      if (quote.length > 0) {
        if (escaped) {
          escaped = false;
        } else if (ch === '\\') {
          escaped = true;
        } else if (ch === quote) {
          quote = '';
        }
        continue;
      }
      if (ch === '"' || ch === "'") {
        quote = ch;
        continue;
      }
      if (ch === '{') {
        depth++;
      } else if (ch === '}') {
        depth--;
        if (depth === 0) {
          return i;
        }
      }
    }
    return -1;
  }

  /**
   * 执行JSONPath查询
   * 增强实现，支持更多JSONPath语法
   */
  private evaluateJsonPath(data: ESObject, path: string): ESObject {
    if (!path || path === '$') {
      return data;
    }

    // 移除开头的$
    let normalizedPath = path;
    if (normalizedPath.startsWith('$.')) {
      normalizedPath = normalizedPath.substring(2);
    } else if (normalizedPath.startsWith('$')) {
      normalizedPath = normalizedPath.substring(1);
    }

    // 处理递归下降 $..xxx 语法
    if (normalizedPath.startsWith('.')) {
      // $..xxx 形式，递归搜索所有层级，并继续应用后续路径
      return this.evaluateRecursiveJsonPath(data, normalizedPath.substring(1));
    }

    // 处理 $[*] 或 $.* 形式 - 返回所有元素
    if (normalizedPath === '*' || normalizedPath === '[*]') {
      if (Array.isArray(data)) {
        return data;
      }
      if (typeof data === 'object' && data !== null) {
        return this.getJsonObjectValues(data);
      }
      return data;
    }

    const parts = this.splitJsonPath(normalizedPath);
    let current: ESObject = data;

    for (let i = 0; i < parts.length; i++) {
      const part = parts[i];
      if (current === null || current === undefined) {
        return null;
      }

      // 处理通配符 * - 遍历所有元素并收集结果
      if (part === '*') {
        if (Array.isArray(current)) {
          // 如果还有后续路径，对每个元素应用后续路径
          if (i < parts.length - 1) {
            return this.evaluateJsonPathForItems(current as ESObject[], parts, i + 1);
          }
          return current;
        }
        if (typeof current === 'object' && current !== null) {
          const values: ESObject[] = this.getJsonObjectValues(current);
          if (i < parts.length - 1) {
            return this.evaluateJsonPathForItems(values, parts, i + 1);
          }
          return values;
        }
        return current;
      }

      // 处理数组索引 [0] 或 [*]
      if (part.startsWith('[') && part.endsWith(']')) {
        const indexStr = part.substring(1, part.length - 1);
        if (indexStr === '*') {
          // 返回所有元素，并继续处理后续路径
          if (Array.isArray(current)) {
            if (i < parts.length - 1) {
              return this.evaluateJsonPathForItems(current as ESObject[], parts, i + 1);
            }
            return current;
          }
          if (typeof current === 'object' && current !== null) {
            const values: ESObject[] = this.getJsonObjectValues(current);
            if (i < parts.length - 1) {
              return this.evaluateJsonPathForItems(values, parts, i + 1);
            }
            return values;
          }
        } else {
          const bracketFieldName = this.parseJsonBracketFieldName(indexStr);
          if (bracketFieldName !== null) {
            current = this.getJsonBracketFieldValue(current, bracketFieldName);
          } else if (Array.isArray(current)) {
            const selected: ESObject[] = this.selectJsonArrayItems(current as ESObject[], indexStr);
            if (selected.length === 1 && !indexStr.includes(',') && !indexStr.includes(':')) {
              current = selected[0];
            } else {
              current = selected as ESObject;
            }
          }
        }
      } else {
        // 处理属性访问
        if (typeof current === 'object' && current !== null) {
          const fieldName = this.parseJsonPathFieldName(part);
          // 如果当前是数组，对每个元素获取属性
          if (Array.isArray(current)) {
            const results: ESObject[] = [];
            const currentArray: ESObject[] = current as ESObject[];
            for (let j = 0; j < currentArray.length; j++) {
              const arrayItem: ESObject = currentArray[j];
              if (typeof arrayItem === 'object' && arrayItem !== null) {
                const itemValue: ESObject = (arrayItem as Record<string, ESObject>)[fieldName];
                if (itemValue !== null && itemValue !== undefined) {
                  results.push(itemValue);
                }
              }
            }
            current = results as ESObject;
          } else {
            current = (current as Record<string, ESObject>)[fieldName];
          }
        } else {
          return null;
        }
      }
    }

    return current;
  }

  private evaluateRecursiveJsonPath(data: ESObject, recursivePath: string): ESObject {
    const parts = this.splitJsonPath(recursivePath);
    if (parts.length === 0) {
      return [];
    }
    const matches: ESObject[] = this.recursiveSearch(data, this.parseJsonPathFieldName(parts[0]));
    if (parts.length === 1) {
      return matches as ESObject;
    }
    return this.evaluateJsonPathForItems(matches, parts, 1);
  }

  private getJsonObjectValues(value: ESObject): ESObject[] {
    if (value === null || value === undefined || typeof value !== 'object' || Array.isArray(value)) {
      return [];
    }
    const record = value as Record<string, ESObject>;
    const keys: string[] = Object.keys(record);
    const results: ESObject[] = [];
    for (let i = 0; i < keys.length; i++) {
      results.push(record[keys[i]]);
    }
    return results;
  }

  private evaluateJsonPathForItems(items: ESObject[], parts: string[], startIndex: number): ESObject[] {
    const results: ESObject[] = [];
    const remainingPath = parts.slice(startIndex).join('.');
    for (let i = 0; i < items.length; i++) {
      const itemResult: ESObject = this.evaluateJsonPath(items[i], '$.' + remainingPath);
      this.appendJsonPathResult(results, itemResult);
    }
    return results;
  }

  private appendJsonPathResult(results: ESObject[], value: ESObject): void {
    if (value === null || value === undefined) {
      return;
    }
    if (Array.isArray(value)) {
      const valueArray: ESObject[] = value as ESObject[];
      for (let i = 0; i < valueArray.length; i++) {
        results.push(valueArray[i]);
      }
      return;
    }
    results.push(value);
  }

  private parseJsonPathFieldName(part: string): string {
    const trimmed = part.trim();
    const quoted = this.parseJsonBracketFieldName(trimmed);
    return quoted !== null ? quoted : trimmed;
  }

  private parseJsonBracketFieldName(indexStr: string): string | null {
    const trimmed = indexStr.trim();
    if (trimmed.length < 2) {
      return null;
    }
    const first = trimmed[0];
    const last = trimmed[trimmed.length - 1];
    if ((first === "'" && last === "'") || (first === '"' && last === '"')) {
      return this.unescapeJsonPathQuotedText(trimmed.substring(1, trimmed.length - 1));
    }
    return null;
  }

  private unescapeJsonPathQuotedText(text: string): string {
    if (text.indexOf('\\') < 0) {
      return text;
    }
    let result = '';
    for (let i = 0; i < text.length; i++) {
      const ch = text[i];
      if (ch !== '\\' || i + 1 >= text.length) {
        result += ch;
        continue;
      }
      const next = text[i + 1];
      if (next === 'n') {
        result += '\n';
      } else if (next === 'r') {
        result += '\r';
      } else if (next === 't') {
        result += '\t';
      } else if (next === 'b') {
        result += '\b';
      } else if (next === 'f') {
        result += '\f';
      } else if (next === 'u' && i + 5 < text.length) {
        const hex = text.substring(i + 2, i + 6);
        const code = parseInt(hex, 16);
        if (!Number.isNaN(code)) {
          result += String.fromCharCode(code);
          i += 5;
          continue;
        }
        result += next;
      } else {
        result += next;
      }
      i++;
    }
    return result;
  }

  private getJsonBracketFieldValue(current: ESObject, fieldName: string): ESObject {
    if (current === null || current === undefined) {
      return null;
    }
    if (Array.isArray(current)) {
      const results: ESObject[] = [];
      const currentArray: ESObject[] = current as ESObject[];
      for (let i = 0; i < currentArray.length; i++) {
        const item: ESObject = currentArray[i];
        const value: ESObject = this.getJsonObjectFieldValue(item, fieldName);
        if (value !== null && value !== undefined) {
          results.push(value);
        }
      }
      return results as ESObject;
    }
    return this.getJsonObjectFieldValue(current, fieldName);
  }

  private getJsonObjectFieldValue(item: ESObject, fieldName: string): ESObject {
    if (item === null || item === undefined || typeof item !== 'object' || Array.isArray(item)) {
      return null;
    }
    const record = item as Record<string, ESObject>;
    const keys: string[] = Object.keys(record);
    if (keys.includes(fieldName)) {
      return record[fieldName];
    }
    const trimmedFieldName = fieldName.trim();
    if (trimmedFieldName !== fieldName && keys.includes(trimmedFieldName)) {
      return record[trimmedFieldName];
    }
    return null;
  }

  private selectJsonArrayItems(items: ESObject[], indexExpr: string): ESObject[] {
    const filterExpr = this.extractJsonFilterExpression(indexExpr);
    if (filterExpr !== null) {
      return this.filterJsonArrayItems(items, filterExpr);
    }

    const results: ESObject[] = [];
    const parts = indexExpr.split(',');
    for (const part of parts) {
      const trimmed = part.trim();
      if (!trimmed) {
        continue;
      }
      if (trimmed.includes(':')) {
        this.appendJsonArraySlice(results, items, trimmed);
      } else {
        const index = parseInt(trimmed);
        if (!Number.isNaN(index)) {
          const actualIndex = index < 0 ? items.length + index : index;
          if (actualIndex >= 0 && actualIndex < items.length) {
            results.push(items[actualIndex]);
          }
        }
      }
    }
    return results;
  }

  private extractJsonFilterExpression(indexExpr: string): string | null {
    const trimmed = indexExpr.trim();
    if (!trimmed.startsWith('?(') || !trimmed.endsWith(')')) {
      return null;
    }
    return trimmed.substring(2, trimmed.length - 1).trim();
  }

  private filterJsonArrayItems(items: ESObject[], filterExpr: string): ESObject[] {
    const results: ESObject[] = [];
    for (let i = 0; i < items.length; i++) {
      const item: ESObject = items[i];
      if (this.evaluateJsonFilter(item, filterExpr)) {
        results.push(item);
      }
    }
    return results;
  }

  private evaluateJsonFilter(item: ESObject, filterExpr: string): boolean {
    const orParts = this.splitJsonFilterByOperator(filterExpr, '||');
    for (let i = 0; i < orParts.length; i++) {
      const andParts = this.splitJsonFilterByOperator(orParts[i], '&&');
      let andMatched = true;
      for (let j = 0; j < andParts.length; j++) {
        if (!this.evaluateJsonFilterSingle(item, andParts[j].trim())) {
          andMatched = false;
          break;
        }
      }
      if (andMatched) {
        return true;
      }
    }
    return false;
  }

  private splitJsonFilterByOperator(expr: string, operator: string): string[] {
    const parts: string[] = [];
    let current = '';
    let quote = '';
    let escaped = false;
    let parenDepth = 0;
    let regexMode = false;
    for (let i = 0; i < expr.length; i++) {
      const ch = expr[i];
      if (quote.length > 0) {
        current += ch;
        if (escaped) {
          escaped = false;
        } else if (ch === '\\') {
          escaped = true;
        } else if (ch === quote) {
          quote = '';
        }
        continue;
      }
      if (regexMode) {
        current += ch;
        if (escaped) {
          escaped = false;
        } else if (ch === '\\') {
          escaped = true;
        } else if (ch === '/') {
          regexMode = false;
        }
        continue;
      }
      if (ch === '"' || ch === "'") {
        quote = ch;
        current += ch;
        continue;
      }
      if (ch === '/' && i > 0 && expr[i - 1] === '~') {
        regexMode = true;
        current += ch;
        continue;
      }
      if (ch === '(') {
        parenDepth++;
      } else if (ch === ')' && parenDepth > 0) {
        parenDepth--;
      }
      if (parenDepth === 0 && expr.substring(i, i + operator.length) === operator) {
        parts.push(current.trim());
        current = '';
        i += operator.length - 1;
      } else {
        current += ch;
      }
    }
    if (current.trim().length > 0) {
      parts.push(current.trim());
    }
    return parts.length > 0 ? parts : [expr];
  }

  private evaluateJsonFilterSingle(item: ESObject, expression: string): boolean {
    let expr = expression.trim();
    if (expr.length <= 0) {
      return false;
    }
    if (expr.startsWith('!')) {
      return !this.evaluateJsonFilterSingle(item, expr.substring(1));
    }
    if (expr.startsWith('(') && expr.endsWith(')')) {
      return this.evaluateJsonFilter(item, expr.substring(1, expr.length - 1));
    }

    const containsMatch = expr.match(/^@\.([A-Za-z0-9_\-.$\[\]]+)\s+contains\s+(.+)$/);
    if (containsMatch) {
      const actual = this.valueToString(this.getJsonFilterFieldValue(item, containsMatch[1]));
      const expected = this.valueToString(this.parseJsonFilterLiteral(containsMatch[2]) as ESObject);
      return actual.indexOf(expected) >= 0;
    }

    const operatorMatch = this.findJsonFilterOperator(expr);
    if (operatorMatch !== null) {
      const left = expr.substring(0, operatorMatch.index).trim();
      const right = expr.substring(operatorMatch.index + operatorMatch.operator.length).trim();
      return this.evaluateJsonFilterComparison(item, left, operatorMatch.operator, right);
    }

    if (expr.startsWith('@.')) {
      return this.isTruthyJsonValue(this.getJsonFilterFieldValue(item, expr.substring(2)));
    }
    if (expr === '@') {
      return this.isTruthyJsonValue(item);
    }
    return false;
  }

  private findJsonFilterOperator(expr: string): JsonFilterOperatorMatch | null {
    const operators: string[] = ['==', '!=', '>=', '<=', '=~', '>', '<', '='];
    let quote = '';
    let escaped = false;
    for (let i = 0; i < expr.length; i++) {
      const ch = expr[i];
      if (quote.length > 0) {
        if (escaped) {
          escaped = false;
        } else if (ch === '\\') {
          escaped = true;
        } else if (ch === quote) {
          quote = '';
        }
        continue;
      }
      if (ch === '"' || ch === "'") {
        quote = ch;
        continue;
      }
      for (let j = 0; j < operators.length; j++) {
        const operator = operators[j];
        if (expr.substring(i, i + operator.length) === operator) {
          const result: JsonFilterOperatorMatch = {
            operator: operator,
            index: i
          };
          return result;
        }
      }
    }
    return null;
  }

  private evaluateJsonFilterComparison(item: ESObject, leftExpr: string, operator: string, rightExpr: string): boolean {
    const leftValue: ESObject = this.resolveJsonFilterValue(item, leftExpr);
    if (operator === '=~') {
      return this.matchJsonFilterRegex(this.valueToString(leftValue), rightExpr);
    }

    const rightValue: ESObject = this.resolveJsonFilterValue(item, rightExpr);
    if (operator === '==' || operator === '=') {
      return this.compareJsonFilterEquality(leftValue, rightValue);
    }
    if (operator === '!=') {
      return !this.compareJsonFilterEquality(leftValue, rightValue);
    }

    const leftNumber = Number(this.valueToString(leftValue));
    const rightNumber = Number(this.valueToString(rightValue));
    if (!Number.isNaN(leftNumber) && !Number.isNaN(rightNumber)) {
      if (operator === '>') {
        return leftNumber > rightNumber;
      }
      if (operator === '<') {
        return leftNumber < rightNumber;
      }
      if (operator === '>=') {
        return leftNumber >= rightNumber;
      }
      if (operator === '<=') {
        return leftNumber <= rightNumber;
      }
    }

    const leftText = this.valueToString(leftValue);
    const rightText = this.valueToString(rightValue);
    if (operator === '>') {
      return leftText > rightText;
    }
    if (operator === '<') {
      return leftText < rightText;
    }
    if (operator === '>=') {
      return leftText >= rightText;
    }
    if (operator === '<=') {
      return leftText <= rightText;
    }
    return false;
  }

  private resolveJsonFilterValue(item: ESObject, expr: string): ESObject {
    const trimmed = expr.trim();
    if (trimmed.startsWith('@.')) {
      return this.getJsonFilterFieldValue(item, trimmed.substring(2));
    }
    if (trimmed === '@') {
      return item;
    }
    return this.parseJsonFilterLiteral(trimmed) as ESObject;
  }

  private getJsonFilterFieldValue(item: ESObject, fieldPath: string): ESObject {
    if (item === null || item === undefined || typeof item !== 'object') {
      return null;
    }
    const normalizedPath = fieldPath.startsWith('$.') || fieldPath.startsWith('$[') ? fieldPath : '$.' + fieldPath;
    return this.evaluateJsonPath(item, normalizedPath);
  }

  private parseJsonFilterLiteral(raw: string): string | number | boolean | null {
    const trimmed = raw.trim();
    if ((trimmed.startsWith("'") && trimmed.endsWith("'")) || (trimmed.startsWith('"') && trimmed.endsWith('"'))) {
      return trimmed.substring(1, trimmed.length - 1);
    }
    if (trimmed === 'true') {
      return true;
    }
    if (trimmed === 'false') {
      return false;
    }
    if (trimmed === 'null') {
      return null;
    }
    const numeric = Number(trimmed);
    if (!Number.isNaN(numeric) && trimmed.length > 0) {
      return numeric;
    }
    return trimmed;
  }

  private compareJsonFilterEquality(leftValue: ESObject, rightValue: ESObject): boolean {
    if (leftValue === null || leftValue === undefined || rightValue === null || rightValue === undefined) {
      return leftValue === rightValue;
    }
    if (typeof leftValue === 'number' || typeof rightValue === 'number') {
      const leftNumber = Number(this.valueToString(leftValue));
      const rightNumber = Number(this.valueToString(rightValue));
      if (!Number.isNaN(leftNumber) && !Number.isNaN(rightNumber)) {
        return leftNumber === rightNumber;
      }
    }
    if (typeof leftValue === 'boolean' || typeof rightValue === 'boolean') {
      return this.valueToString(leftValue) === this.valueToString(rightValue);
    }
    return this.valueToString(leftValue) === this.valueToString(rightValue);
  }

  private isTruthyJsonValue(value: ESObject): boolean {
    if (value === null || value === undefined) {
      return false;
    }
    if (typeof value === 'boolean') {
      return value;
    }
    if (typeof value === 'number') {
      return value !== 0;
    }
    if (typeof value === 'string') {
      return value.length > 0;
    }
    if (Array.isArray(value)) {
      return value.length > 0;
    }
    return true;
  }

  private matchJsonFilterRegex(actual: string, regexExpr: string): boolean {
    const trimmed = regexExpr.trim();
    if (!trimmed.startsWith('/')) {
      return actual.indexOf(this.parseJsonFilterLiteral(trimmed) as string) >= 0;
    }
    let end = -1;
    let escaped = false;
    for (let i = 1; i < trimmed.length; i++) {
      const ch = trimmed[i];
      if (escaped) {
        escaped = false;
      } else if (ch === '\\') {
        escaped = true;
      } else if (ch === '/') {
        end = i;
        break;
      }
    }
    if (end <= 0) {
      return false;
    }
    const pattern = trimmed.substring(1, end);
    const flags = trimmed.substring(end + 1);
    try {
      const regex = new RegExp(pattern, flags);
      return regex.test(actual);
    } catch (_error) {
      return false;
    }
  }

  private appendJsonArraySlice(results: ESObject[], items: ESObject[], sliceExpr: string): void {
    const len = items.length;
    if (len === 0) {
      return;
    }
    const parts = sliceExpr.split(':');
    const rawStep = parts.length > 2 && parts[2].trim().length > 0 ? parseInt(parts[2].trim()) : 1;
    const step = Number.isNaN(rawStep) || rawStep === 0 ? 1 : rawStep;
    const isReverse = step < 0;
    const startOmitted = parts.length > 0 && parts[0].trim().length === 0;
    const endOmitted = parts.length > 1 && parts[1].trim().length === 0;

    let start = startOmitted ? (isReverse ? len - 1 : 0) : parseInt(parts[0].trim());
    let end = endOmitted ? (isReverse ? 0 : len - 1) : parseInt(parts[1].trim());
    if (Number.isNaN(start) || Number.isNaN(end)) {
      return;
    }

    if (start < 0) {
      start += len;
    }
    if (end < 0) {
      end += len;
    }

    if ((start < 0 && end < 0) || (start >= len && end >= len)) {
      return;
    }

    if (start < 0) {
      start = 0;
    } else if (start >= len) {
      start = len - 1;
    }

    if (end < 0) {
      end = 0;
    } else if (end >= len) {
      end = len - 1;
    }

    if (isReverse) {
      const positiveStep = -step;
      for (let i = start; i >= end; i -= positiveStep) {
        results.push(items[i]);
      }
      return;
    }

    for (let i = start; i <= end; i += step) {
      results.push(items[i]);
    }
  }

  /**
   * 递归搜索JSON对象中的指定键
   * 支持 $..xxx 和 $..xxx[*] 语法
   */
  private recursiveSearch(data: ESObject, searchKey: string): ESObject[] {
    const results: ESObject[] = [];
    
    // 解析搜索键，可能包含数组索引如 filterBookList[*]
    let key = searchKey;
    let arrayIndex = '';
    const bracketMatch = searchKey.match(/^([^\[]+)(\[.+\])$/);
    if (bracketMatch) {
      key = bracketMatch[1];
      arrayIndex = bracketMatch[2];
    }
    
    const search = (obj: ESObject): void => {
      if (obj === null || obj === undefined) return;
      
      if (Array.isArray(obj)) {
        // 遍历数组中的每个元素
        const objArray: ESObject[] = obj as ESObject[];
        for (let i = 0; i < objArray.length; i++) {
          search(objArray[i]);
        }
      } else if (typeof obj === 'object') {
        // 检查当前对象是否有目标键
        const record: Record<string, ESObject> = obj as Record<string, ESObject>;
        const recordKeys: string[] = Object.keys(record);
        const hasKey: boolean = recordKeys.includes(key);
        if (hasKey) {
          const value: ESObject = record[key];
          // 如果有数组索引，应用它
          if (arrayIndex && Array.isArray(value)) {
            if (arrayIndex === '[*]') {
              // 返回所有元素
              const valueArray: ESObject[] = value as ESObject[];
              for (let j = 0; j < valueArray.length; j++) {
                results.push(valueArray[j]);
              }
            } else {
              // 解析具体索引
              const indexMatch = arrayIndex.match(/\[(\d+)\]/);
              if (indexMatch) {
                const idx = parseInt(indexMatch[1]);
                const valueArray: ESObject[] = value as ESObject[];
                if (idx < valueArray.length) {
                  results.push(valueArray[idx]);
                }
              }
            }
          } else {
            results.push(value);
          }
        }
        // 递归搜索所有子对象
        const childKeys = Object.keys(record);
        for (let k = 0; k < childKeys.length; k++) {
          search(record[childKeys[k]]);
        }
      }
    };
    
    search(data);
    return results;
  }

  /**
   * 分割JSONPath路径
   */
  private splitJsonPath(path: string): string[] {
    const parts: string[] = [];
    let current = '';
    let inBracket = false;
    let quote = '';
    let escaped = false;

    for (let i = 0; i < path.length; i++) {
      const char = path[i];
      if (quote.length > 0) {
        current += char;
        if (escaped) {
          escaped = false;
        } else if (char === '\\') {
          escaped = true;
        } else if (char === quote) {
          quote = '';
        }
        continue;
      }

      if (char === '"' || char === "'") {
        quote = char;
        current += char;
        continue;
      }

      if (char === '[') {
        if (current) {
          parts.push(current);
          current = '';
        }
        inBracket = true;
        current += char;
      } else if (char === ']') {
        current += char;
        parts.push(current);
        current = '';
        inBracket = false;
      } else if (char === '.' && !inBracket) {
        if (current) {
          parts.push(current);
          current = '';
        }
      } else {
        current += char;
      }
    }

    if (current) {
      parts.push(current);
    }

    return parts;
  }

  // ==================== CSS选择器解析 ====================

  /**
   * 通过CSS选择器获取字符串
   * 增强实现，支持Legado特有语法
   */
  private getStringByCSS(selector: string, useFirstCssMatch: boolean = false): string {
    // 检查是否是Legado链式规则 (class.xxx@tag.a.0@text)
    if (selector.includes('@') && (selector.startsWith('class.') || selector.startsWith('id.') || 
        selector.startsWith('tag.') || selector.match(/^[a-z]+\./))) {
      return this.getStringByLegadoRule(selector, useFirstCssMatch);
    }
    
    // 检查是否是纯属性名（如 text, href, src 等）
    // 这种情况下直接从当前内容中提取属性，不需要查找元素
    const pureAttrNames = ['text', 'href', 'src', 'html', 'textcontent', 'textnodes', 'owntext', 
                           'innerhtml', 'title', 'alt', 'value', 'content', 'class', 'id', 'name',
                           'data-src', 'data-original', 'type', 'placeholder', 'action'];
    const lowerSelector = selector.trim().toLowerCase();
    if (pureAttrNames.includes(lowerSelector) || lowerSelector.startsWith('data-')) {
      // 纯属性名，直接从当前内容提取
      return this.extractAttribute(this.content, lowerSelector);
    }
    
    // 解析选择器和属性
    const result = this.parseCSSSelectorAndAttr(selector);
    
    // 使用CSS选择器获取元素
    // @html/@all are element serialization operations in AnalyzeByJSoup.
    // Evaluate the selector chain to elements first, then serialize each
    // selected element; evaluating the terminal attribute as another CSS rule
    // loses the selected outer block and changes HtmlFormatter indentation.
    const requiresOuterHtml = result.attr === 'html' || result.attr === 'all' || result.attr === 'outerhtml';
    const elements = requiresOuterHtml
      ? this.getElementsByCSSForOuterHtml(result.sel)
      : this.getElementsByCSS(result.sel);
    if (elements.length === 0) {
      return '';
    }

    // AnalyzeByJSoup aggregates Elements.outerHtml() for @html and @all.
    // Jsoup's Elements.outerHtml() concatenates sibling nodes without an
    // artificial delimiter. A newline here is observable: HtmlFormatter
    // turns it into a paragraph boundary and reader indentation. Keep the
    // outer blocks, but preserve the upstream serialization boundary.
    if (requiresOuterHtml) {
      const values: string[] = [];
      for (let index = 0; index < elements.length; index++) {
        const value = this.extractAttribute(elements[index], result.attr);
        if (value.length > 0) {
          values.push(value);
        }
      }
      if (useFirstCssMatch) {
        return values.length > 0 ? values[0] : '';
      }
      return values.join('');
    }

    return this.extractAttribute(elements[0], result.attr);
  }

  /**
   * Keep selector resolution and outer-HTML serialization separate. The DOM
   * bridge handles standard CSS (for example #vcon@p) without turning a
   * selected node into its text, while the string implementation remains the
   * deterministic fallback for oversized documents and legacy indexes.
   */
  private getElementsByCSSForOuterHtml(selector: string): string[] {
    if (this.htmlBridge !== null && !this.hasLegacyIndexInCssChain(selector)) {
      try {
        const bridgeElements = this.htmlBridge.parseChainRuleToHtmlList(selector);
        if (bridgeElements.length > 0) {
          return bridgeElements;
        }
      } catch (error) {
        logger.warn(TAG, `HTML outer selector bridge failed, falling back: ${String(error)}`);
      }
    }
    return this.getElementsByCSSChain(selector);
  }
  
  /**
   * 解析Legado链式规则
   * 支持格式: class.xxx@tag.a.0@text, id.xxx@tag.div@href
   * 支持正则替换: rule##regex##replacement##
   * 
   * 参考Legado原版AnalyzeByJSoup.kt的实现
   */
  private getStringByLegadoRule(rule: string, useFirstCssMatch: boolean = false): string {
    // 步骤1: 分离正则替换规则 (##regex##replacement##)
    let replaceRegex = '';
    let replacement = '';
    let replaceFirst = false;
    
    const regexParts = rule.split('##');
    rule = regexParts[0]; // 主规则
    if (regexParts.length > 1) {
      replaceRegex = regexParts[1];
    }
    if (regexParts.length > 2) {
      replacement = regexParts[2];
    }
    if (regexParts.length > 3) {
      replaceFirst = true;
    }
    
    // 步骤2: 使用@分割规则链
    const ruleAnalyzer = new LegadoRuleChainAnalyzer(rule);
    const rules = ruleAnalyzer.splitByAt();
    if (LegadoRuleAnalyzer.ENABLE_SELECTOR_TRACE) {
      logger.debug(TAG, `getStringByLegadoRule: rule=${rule}, rules=${JSON.stringify(rules)}`);
    }
    
    if (rules.length === 0) {
      return '';
    }

    // 步骤3: 逐级解析规则
    let elements: string[] = [this.content];
    const lastIndex = rules.length - 1;
    
    for (let i = 0; i < lastIndex; i++) {
      const newElements: string[] = [];
      for (const el of elements) {
        const found = this.findElementsBySingleRule(el, rules[i]);
        newElements.push(...found);
      }
      if (LegadoRuleAnalyzer.ENABLE_SELECTOR_TRACE) {
        logger.debug(TAG, `getStringByLegadoRule: step[${i}]=${rules[i]}, found=${newElements.length}`);
      }
      elements = newElements;
      if (elements.length === 0) {
        return '';
      }
    }
    
    // 步骤4: 获取最后一个规则指定的属性
    const lastRule = rules[lastIndex];
    const result = this.getResultByLastRule(elements, lastRule, useFirstCssMatch);
    
    // 步骤5: 应用正则替换
    if (replaceRegex && result) {
      return this.applyReplace(result, replaceRegex, replacement, replaceFirst);
    }
    
    return result;
  }
  
  /**
   * 根据最后一个规则获取结果
   * 最后一个规则可能是属性名(text, href, src等)或选择器
   * 支持属性+JS组合：href<js>...</js>
   */
  private getResultByLastRule(
    elements: string[],
    lastRule: string,
    useFirstCssMatch: boolean = false
  ): string {
    // 扩展属性名列表，包含常见HTML属性
    const attrNames = ['text', 'href', 'src', 'html', 'textnodes', 'owntext', 'all',
                       'title', 'alt', 'value', 'content', 'data-src', 'data-original',
                       'class', 'id', 'name', 'type', 'placeholder', 'action'];
    
    // 检查是否是属性+JS组合：attr<js>...</js>
    const attrJsMatch = lastRule.match(/^([a-zA-Z_-]+)<js>([\s\S]*)<\/js>$/i);
    if (attrJsMatch) {
      const attrName = attrJsMatch[1].toLowerCase();
      const jsCode = attrJsMatch[2];
      // 性能优化：减少日志输出
      // logger.debug(TAG, `getResultByLastRule: 属性+JS组合, attr=${attrName}, jsCode=${jsCode.substring(0, 50)}`);
      
      const results: string[] = [];
      for (const el of elements) {
        // 先提取属性值
        const attrValue = this.extractAttribute(el, attrName);
        if (attrValue) {
          // 将属性值作为result传给JS执行
          const jsResult = this.evalJS(`var result = ${JSON.stringify(attrValue)}; ${jsCode}`);
          if (jsResult) {
            results.push(jsResult);
          }
        }
      }
      return useFirstCssMatch ? (results[0] || '') : results.join('\n');
    }
    
    const lowerRule = lastRule.toLowerCase();
    
    // 检查是否是属性名
    if (attrNames.includes(lowerRule) || this.isGenericCssAttributeName(lowerRule)) {
      const results: string[] = [];
      for (const el of elements) {
        const text = this.extractAttribute(el, lowerRule);
        if (text) {
          results.push(text);
        }
      }
      const projectedResults: string[] = this.shouldDeduplicateLegadoAttributeValues(lowerRule)
        ? this.deduplicateLegadoAttributeValues(results)
        : results;
      // AnalyzeByJSoup has a distinct @html/@all path: it serializes the
      // entire Elements collection with Elements.outerHtml(), which appends
      // sibling nodes directly. Joining with a newline injects a reader
      // paragraph boundary after HtmlFormatter runs, so it cannot share the
      // ordinary multi-value attribute delimiter.
      if (lowerRule === 'html' || lowerRule === 'all' || lowerRule === 'outerhtml') {
        return useFirstCssMatch ? (projectedResults[0] || '') : projectedResults.join('');
      }
      return useFirstCssMatch ? (projectedResults[0] || '') : projectedResults.join('\n');
    }
    
    // 不是属性名，继续作为选择器处理，然后获取text
    const newElements: string[] = [];
    for (const el of elements) {
      const found = this.findElementsBySingleRule(el, lastRule);
      newElements.push(...found);
    }
    
    if (newElements.length === 0) {
      return '';
    }
    
    const results: string[] = [];
    for (const el of newElements) {
      const text = this.extractAttribute(el, 'text');
      if (text) {
        results.push(text);
      }
    }
    return useFirstCssMatch ? (results[0] || '') : results.join('\n');
  }

  /**
   * AnalyzeByJSoup delegates every non-special terminal token to
   * Element.attr(token), so data-* and site-specific attributes must not be
   * reduced to a short allow-list. Selector-chain tokens retain dots or
   * brackets and therefore do not match this attribute-name grammar.
   */
  private isGenericCssAttributeName(value: string): boolean {
    if (value === 'children') {
      return false;
    }
    return /^[a-z_:][a-z0-9_:.-]*$/.test(value);
  }

  /**
   * Legado deduplicates nonblank terminal attribute values in
   * AnalyzeByJSoup.getResultLast. This boundary is intentionally separate
   * from Elements.eachAttr(), whose Jsoup 1.16.2 contract preserves order and
   * duplicate values for direct JavaScript callers.
   */
  private shouldDeduplicateLegadoAttributeValues(attributeName: string): boolean {
    const normalized = attributeName.toLowerCase();
    return normalized !== 'text' && normalized !== 'textcontent' &&
      normalized !== 'textnodes' && normalized !== 'owntext' &&
      normalized !== 'html' && normalized !== 'innerhtml' &&
      normalized !== 'all' && normalized !== 'outerhtml';
  }

  private deduplicateLegadoAttributeValues(values: string[]): string[] {
    const result: string[] = [];
    const seen = new Set<string>();
    for (const value of values) {
      if (value.trim().length === 0 || seen.has(value)) {
        continue;
      }
      seen.add(value);
      result.push(value);
    }
    return result;
  }
  
  /**
   * 根据单个规则查找元素
   * 支持: class.xxx, id.xxx, tag.div, tag.a.0, text.xxx, children
   * 支持索引: tag.a.0, tag.a.-1, tag.a[0], tag.a[0:3]
   */
  private findElementsBySingleRule(content: string, rule: string): string[] {
    // 解析索引选择器
    const indexResult = this.parseIndexSelector(rule);
    const selector = indexResult.selector;
    const requiredCount = this.estimateRequiredElementCount(indexResult);
    
    // 获取所有匹配的元素
    let results: string[] = [];
    
    if (selector === 'children' || selector === '') {
      results = this.getChildElements(content);
    } else if (selector.startsWith('class.')) {
      const className = selector.substring(6);
      results = this.findElementsByClass(content, className, requiredCount);
    } else if (selector.startsWith('id.')) {
      const idName = selector.substring(3);
      results = this.findElementsById(content, idName, requiredCount);
    } else if (selector.startsWith('tag.')) {
      const tagName = selector.substring(4);
      results = this.findElementsByTag(content, tagName, requiredCount);
    } else if (selector.startsWith('text.')) {
      const searchText = selector.substring(5);
      results = this.findElementsByText(content, searchText, requiredCount);
    } else if (selector.includes('.') && !selector.startsWith('.')) {
      // 处理CSS选择器格式: tag.class (如 span.zuo, div.content)
      // 这是标准CSS选择器，表示 <tag class="class">
      const dotIndex = selector.indexOf('.');
      const tagName = selector.substring(0, dotIndex);
      const className = selector.substring(dotIndex + 1);
      // 先按标签查找，再按class过滤
      // tag.class 需要先取全量tag再按class过滤，不能提前按索引限制tag数量，否则会改变语义
      const tagElements = this.findElementsByTag(content, tagName);
      for (const el of tagElements) {
        // 检查元素是否包含指定的class
        const classMatch = el.match(/class\s*=\s*["']([^"']*)["']/i);
        if (classMatch) {
          const classes = classMatch[1].split(/\s+/);
          if (classes.includes(className)) {
            results.push(el);
          }
        }
      }
    } else {
      // 默认作为标签名处理
      results = this.findElementsByTag(content, selector, requiredCount);
    }
    
    // 应用索引筛选
    if (indexResult.hasIndex) {
      results = this.applyIndexFilter(results, indexResult);
    }
    
    return results;
  }
  
  /**
   * 解析索引选择器
   * 支持: tag.a.0, tag.a.-1, tag.a[0], tag.a[0:3], tag.a[!0]
   */
  private parseIndexSelector(rule: string): IndexSelectorResult {
    const result: IndexSelectorResult = {
      selector: rule,
      hasIndex: false,
      exclude: false,
      indexes: [],
      ranges: [],
      items: []
    };
    
    // 检查[]式索引
    if (rule.endsWith(']')) {
      const bracketStart = rule.lastIndexOf('[');
      if (bracketStart !== -1) {
        result.selector = rule.substring(0, bracketStart);
        const indexStr = rule.substring(bracketStart + 1, rule.length - 1);
        result.hasIndex = true;
        
        // 检查是否是排除模式
        if (indexStr.startsWith('!')) {
          result.exclude = true;
          this.parseIndexString(indexStr.substring(1), result);
        } else {
          this.parseIndexString(indexStr, result);
        }
        return result;
      }
    }
    
    // 检查.式范围索引 (tag.td.5:4 或 tag.a.0:3)
    const dotRangeMatch = rule.match(/\.(-?\d+):(-?\d+)(?::(-?\d+))?$/);
    if (dotRangeMatch) {
      result.selector = rule.substring(0, rule.length - dotRangeMatch[0].length);
      result.hasIndex = true;
      const start = parseInt(dotRangeMatch[1]);
      const end = parseInt(dotRangeMatch[2]);
      const step = dotRangeMatch[3] ? parseInt(dotRangeMatch[3]) : 1;
      this.addIndexRange(result, start, end, step, false, false);
      return result;
    }
    
    // 检查.式索引 (tag.a.0 或 tag.a.-1)
    const dotIndexMatch = rule.match(/\.(-?\d+)$/);
    if (dotIndexMatch) {
      result.selector = rule.substring(0, rule.length - dotIndexMatch[0].length);
      result.hasIndex = true;
      this.addIndexSingle(result, parseInt(dotIndexMatch[1]));
      return result;
    }
    
    // 检查!式排除索引 (tag.a!0)
    const excludeMatch = rule.match(/!(-?\d+)$/);
    if (excludeMatch) {
      result.selector = rule.substring(0, rule.length - excludeMatch[0].length);
      result.hasIndex = true;
      result.exclude = true;
      this.addIndexSingle(result, parseInt(excludeMatch[1]));
      return result;
    }
    
    return result;
  }
  
  /**
   * 解析索引字符串
   * 支持: 0, 0:3, 0:10:2, -1
   */
  private parseIndexString(indexStr: string, result: IndexSelectorResult): void {
    const parts = indexStr.split(',');
    for (const part of parts) {
      const trimmed = part.trim();
      if (!trimmed) {
        continue;
      }
      if (trimmed.includes(':')) {
        // 范围索引 start:end:step
        const rangeParts = trimmed.split(':');
        const startOmitted = rangeParts.length > 0 && rangeParts[0].trim().length === 0;
        const endOmitted = rangeParts.length > 1 && rangeParts[1].trim().length === 0;
        const start = startOmitted ? 0 : parseInt(rangeParts[0].trim());
        const end = endOmitted ? -1 : parseInt(rangeParts[1].trim());
        const step = rangeParts.length > 2 && rangeParts[2].trim().length > 0 ? parseInt(rangeParts[2].trim()) : 1;
        if (!Number.isNaN(start) && !Number.isNaN(end) && !Number.isNaN(step)) {
          this.addIndexRange(result, start, end, step, startOmitted, endOmitted);
        }
      } else {
        // 单个索引
        const index = parseInt(trimmed);
        if (!Number.isNaN(index)) {
          this.addIndexSingle(result, index);
        }
      }
    }
  }

  private valueToElementString(value: ESObject): string {
    if (value === null || value === undefined) {
      return '';
    }
    if (typeof value === 'object') {
      return JSON.stringify(value);
    }
    return String(value);
  }

  private addIndexSingle(result: IndexSelectorResult, index: number): void {
    result.indexes.push(index);
    const item: IndexSelectorItem = {
      itemType: IndexSelectorItemType.Single,
      index: index,
      start: 0,
      end: 0,
      step: 1,
      startOmitted: false,
      endOmitted: false
    };
    result.items.push(item);
  }

  private addIndexRange(result: IndexSelectorResult, start: number, end: number, step: number,
    startOmitted: boolean, endOmitted: boolean): void {
    const normalizedStep = step === 0 ? 1 : step;
    const range: IndexRange = {
      start: start,
      end: end,
      step: normalizedStep,
      startOmitted: startOmitted,
      endOmitted: endOmitted
    };
    result.ranges.push(range);
    const item: IndexSelectorItem = {
      itemType: IndexSelectorItemType.Range,
      index: 0,
      start: start,
      end: end,
      step: normalizedStep,
      startOmitted: startOmitted,
      endOmitted: endOmitted
    };
    result.items.push(item);
  }

  /**
   * 基于索引规则估算所需最小元素数。
   * 仅在“选择模式 + 全部非负索引”时返回正数；否则返回0表示无法提前裁剪。
   */
  private estimateRequiredElementCount(indexResult: IndexSelectorResult): number {
    if (!indexResult.hasIndex || indexResult.exclude) {
      return 0;
    }

    let maxIndex = -1;

    for (const idx of indexResult.indexes) {
      if (idx < 0) {
        return 0;
      }
      if (idx > maxIndex) {
        maxIndex = idx;
      }
    }

    for (const range of indexResult.ranges) {
      if (range.start < 0 || range.end < 0) {
        return 0;
      }
      if (range.start > maxIndex) {
        maxIndex = range.start;
      }
      if (range.end > maxIndex) {
        maxIndex = range.end;
      }
    }

    if (maxIndex < 0) {
      return 0;
    }
    return maxIndex + 1;
  }
  
  /**
   * 应用索引筛选
   */
  private applyIndexFilter(elements: string[], indexResult: IndexSelectorResult): string[] {
    const len = elements.length;
    if (len === 0) {
      return [];
    }

    // 如果没有指定索引，返回所有元素
    if (indexResult.items.length === 0 && indexResult.indexes.length === 0 && indexResult.ranges.length === 0) {
      return elements;
    }

    const indexes = this.collectIndexFilterIndexes(len, indexResult);
    if (indexResult.exclude) {
      const excludeSet = new Set<number>();
      for (const idx of indexes) {
        excludeSet.add(idx);
      }
      return elements.filter((_: string, i: number): boolean => !excludeSet.has(i));
    }

    const results: string[] = [];
    const addedSet = new Set<number>();
    for (const idx of indexes) {
      if (!addedSet.has(idx)) {
        results.push(elements[idx]);
        addedSet.add(idx);
      }
    }
    return results;
  }

  private collectIndexFilterIndexes(len: number, indexResult: IndexSelectorResult): number[] {
    const indexes: number[] = [];
    if (indexResult.items.length > 0) {
      for (const item of indexResult.items) {
        if (item.itemType === IndexSelectorItemType.Single) {
          this.appendSingleIndex(indexes, len, item.index);
        } else {
          this.appendRangeIndexes(indexes, len, item.start, item.end, item.step, item.startOmitted, item.endOmitted);
        }
      }
      return indexes;
    }

    for (const idx of indexResult.indexes) {
      this.appendSingleIndex(indexes, len, idx);
    }

    for (const range of indexResult.ranges) {
      this.appendRangeIndexes(indexes, len, range.start, range.end, range.step, range.startOmitted, range.endOmitted);
    }

    return indexes;
  }

  private appendSingleIndex(indexes: number[], len: number, index: number): void {
    const actualIdx = index < 0 ? len + index : index;
    if (actualIdx >= 0 && actualIdx < len) {
      indexes.push(actualIdx);
    }
  }

  private appendRangeIndexes(indexes: number[], len: number, startValue: number, endValue: number,
    stepValue: number, startOmitted: boolean, endOmitted: boolean): void {
    let start = startOmitted ? 0 : startValue;
    if (start < 0) {
      start += len;
    }

    let end = endOmitted ? len - 1 : endValue;
    if (end < 0) {
      end += len;
    }

    if ((start < 0 && end < 0) || (start >= len && end >= len)) {
      return;
    }

    if (start >= len) {
      start = len - 1;
    } else if (start < 0) {
      start = 0;
    }

    if (end >= len) {
      end = len - 1;
    } else if (end < 0) {
      end = 0;
    }

    const rawStep = stepValue === 0 ? 1 : stepValue;
    let step = rawStep > 0 ? rawStep : -rawStep;
    if (step >= len) {
      indexes.push(start);
      return;
    }

    if (start <= end) {
      for (let i = start; i <= end; i += step) {
        indexes.push(i);
      }
    } else {
      for (let i = start; i >= end; i -= step) {
        indexes.push(i);
      }
    }
  }
  
  /**
   * 获取直接子元素
   * 添加性能保护：限制元素数量和内容大小以避免ANR
   */
  private getChildElements(content: string): string[] {
    // 性能保护：使用统一配置
    const MAX_ELEMENTS = this.getMaxElements(PerformanceConfig.MAX_ELEMENTS);
    const searchContent = PerformanceConfig.safeSubstring(content);
    return this.findDirectChildren(searchContent, MAX_ELEMENTS);
  }

  private isWhitespaceChar(ch: string): boolean {
    return ch === ' ' || ch === '\t' || ch === '\n' || ch === '\r' || ch === '\f';
  }

  private extractTagNameAt(content: string, tagStart: number): string {
    if (tagStart < 0 || tagStart + 1 >= content.length) {
      return '';
    }
    let i = tagStart + 1;
    if (content[i] === '/' || content[i] === '!') {
      return '';
    }
    const start = i;
    while (i < content.length) {
      const ch = content[i];
      const isLower = ch >= 'a' && ch <= 'z';
      const isUpper = ch >= 'A' && ch <= 'Z';
      const isDigit = ch >= '0' && ch <= '9';
      if (!isLower && !isUpper && !isDigit) {
        break;
      }
      i++;
    }
    if (i === start) {
      return '';
    }
    return content.substring(start, i);
  }

  private containsClassToken(classValue: string, classToken: string): boolean {
    if (!classToken || !classValue) {
      return false;
    }
    let index = classValue.indexOf(classToken);
    while (index !== -1) {
      const beforeIndex = index - 1;
      const afterIndex = index + classToken.length;
      const beforeOk = beforeIndex < 0 || this.isWhitespaceChar(classValue[beforeIndex]);
      const afterOk = afterIndex >= classValue.length || this.isWhitespaceChar(classValue[afterIndex]);
      if (beforeOk && afterOk) {
        return true;
      }
      index = classValue.indexOf(classToken, index + 1);
    }
    return false;
  }

  private containsAllClassTokens(classValue: string, classNames: string[]): boolean {
    for (const classToken of classNames) {
      if (!this.containsClassToken(classValue, classToken)) {
        return false;
      }
    }
    return true;
  }

  private extractAttributeValueFromTagContent(tagContent: string, attrName: string): string | null {
    const lowerAttrName = attrName.trim().toLowerCase();
    if (!lowerAttrName) {
      return null;
    }
    const tagEnd = this.findHtmlTagEnd(tagContent, 0);
    const source = tagEnd >= 0 ? tagContent.substring(0, tagEnd + 1) : tagContent;
    const sourceLength = source.length;
    let cursor = 0;
    if (cursor < sourceLength && source[cursor] === '<') {
      cursor++;
    }
    if (cursor < sourceLength && source[cursor] === '/') {
      cursor++;
    }
    while (cursor < sourceLength && !this.isWhitespaceChar(source[cursor]) && source[cursor] !== '>') {
      cursor++;
    }

    while (cursor < sourceLength) {
      while (cursor < sourceLength && this.isWhitespaceChar(source[cursor])) {
        cursor++;
      }
      if (cursor >= sourceLength || source[cursor] === '>') {
        break;
      }
      if (source[cursor] === '/') {
        cursor++;
        continue;
      }

      const nameStart = cursor;
      while (cursor < sourceLength && !this.isWhitespaceChar(source[cursor]) &&
        source[cursor] !== '=' && source[cursor] !== '>') {
        cursor++;
      }
      if (cursor <= nameStart) {
        cursor++;
        continue;
      }
      const name = source.substring(nameStart, cursor).toLowerCase();
      while (cursor < sourceLength && this.isWhitespaceChar(source[cursor])) {
        cursor++;
      }

      let value = '';
      if (cursor < sourceLength && source[cursor] === '=') {
        cursor++;
        while (cursor < sourceLength && this.isWhitespaceChar(source[cursor])) {
          cursor++;
        }
        if (cursor < sourceLength && (source[cursor] === '"' || source[cursor] === "'")) {
          const quote = source[cursor];
          cursor++;
          const valueStart = cursor;
          while (cursor < sourceLength && source[cursor] !== quote) {
            cursor++;
          }
          value = source.substring(valueStart, cursor);
          if (cursor < sourceLength && source[cursor] === quote) {
            cursor++;
          }
        } else {
          const valueStart = cursor;
          while (cursor < sourceLength && !this.isWhitespaceChar(source[cursor]) && source[cursor] !== '>') {
            cursor++;
          }
          value = source.substring(valueStart, cursor);
        }
      }
      if (name === lowerAttrName) {
        return value;
      }
    }
    return null;
  }

  private findTagStartByName(content: string, fromIndex: number, lowerTagName: string): number {
    let cursor = fromIndex;
    while (cursor < content.length) {
      const scan = this.scanNextHtmlTag(content, cursor);
      if (scan === null) {
        return -1;
      }
      if (!scan.isSpecial && !scan.isClosing && scan.tagName.length > 0 &&
        (lowerTagName.length === 0 || scan.tagName === lowerTagName)) {
        return scan.startIndex;
      }
      cursor = scan.endIndex + 1;
    }
    return -1;
  }

  /**
   * 按class查找元素
   * 增强版：支持多个class名称，添加诊断日志
   * 添加性能保护：限制元素数量和内容大小以避免ANR
   */
  private findElementsByClass(content: string, className: string, maxElementsHint: number = 0): string[] {
    const results: string[] = [];
    const seenStartIndexes: Set<number> = new Set();
    
    // 性能保护：使用统一配置
    let maxElements = this.getMaxElements(PerformanceConfig.MAX_ELEMENTS);
    if (maxElementsHint > 0) {
      maxElements = Math.min(maxElements, maxElementsHint);
    }
    const searchContent = PerformanceConfig.safeSubstring(content);
    
    // 分割多个class名称
    const classNames = className.split(/\s+/).filter(c => c.length > 0);
    if (classNames.length === 0) {
      return results;
    }
    
    // 性能优化：减少大型内容时的日志输出
    if (searchContent.length < 10000) {
      this.selectorTrace((): string => `findElementsByClass: 查找class="${className}", contentLen=${searchContent.length}`);
    }
    
    // 统一使用 quote-aware 标签扫描，属性值中的 class= 文本不能成为属性节点
    let searchStart = 0;
    while (searchStart < searchContent.length && results.length < maxElements) {
      const scan = this.scanNextHtmlTag(searchContent, searchStart);
      if (scan === null) {
        break;
      }
      searchStart = scan.endIndex + 1;
      if (scan.isSpecial || scan.isClosing || scan.tagName.length === 0) {
        continue;
      }
      const tagContent = searchContent.substring(scan.startIndex, scan.endIndex + 1);
      const classValue = this.extractAttributeValueFromTagContent(tagContent, 'class');
      if (classValue !== null && this.containsAllClassTokens(classValue, classNames)) {
        this.pushElementIfNew(results, seenStartIndexes, searchContent, scan.startIndex, scan.tagName, maxElements);
      }
    }

    // 如果还是没找到，输出HTML中存在的class供诊断（仅在开启trace时）
    if (results.length === 0 && LegadoRuleAnalyzer.ENABLE_SELECTOR_TRACE) {
      const allClasses: string[] = [];
      const classRegex = /\bclass\s*=\s*["']([^"']+)["']/gi;
      let classMatch = classRegex.exec(searchContent);
      while (classMatch !== null && allClasses.length < 20) {
        const classes = classMatch[1].split(/\s+/);
        for (const c of classes) {
          if (c && !allClasses.includes(c) && allClasses.length < 20) {
            allClasses.push(c);
          }
        }
        classMatch = classRegex.exec(searchContent);
      }
      if (allClasses.length > 0) {
        this.selectorTrace((): string => `findElementsByClass: 未找到class="${className}", HTML中存在的class: ${allClasses.slice(0, 10).join(', ')}...`);
      } else {
        this.selectorTrace((): string => `findElementsByClass: 未找到class="${className}", HTML中没有任何class属性`);
      }
    }
    
    // 性能优化：减少日志输出
    if (content.length < 10000) {
      this.selectorTrace((): string => `findElementsByClass: 找到${results.length}个元素`);
    }
    return results;
  }

  /**
   * 按id查找元素
   * 增强版：支持更多id属性格式，添加诊断日志
   * 添加性能保护：限制元素数量和内容大小以避免ANR
   */
  private findElementsById(content: string, idName: string, maxElementsHint: number = 0): string[] {
    const results: string[] = [];
    const seenStartIndexes: Set<number> = new Set();
    
    // 性能保护：使用统一配置（ID查找使用较小限制）
    let maxElements = this.getMaxElements(PerformanceConfig.MAX_ID_ELEMENTS);
    if (maxElementsHint > 0) {
      maxElements = Math.min(maxElements, maxElementsHint);
    }
    const searchContent = PerformanceConfig.safeSubstring(content);
    
    // 性能优化：减少大型内容时的日志输出
    if (searchContent.length < 10000) {
      this.selectorTrace((): string => `findElementsById: 查找id="${idName}", contentLen=${searchContent.length}`);
    }

    // 统一使用 quote-aware 标签扫描，属性值中的 id= 文本不能成为属性节点
    let searchStart = 0;
    const lowerIdName = idName.toLowerCase();
    while (searchStart < searchContent.length && results.length < maxElements) {
      const scan = this.scanNextHtmlTag(searchContent, searchStart);
      if (scan === null) {
        break;
      }
      searchStart = scan.endIndex + 1;
      if (scan.isSpecial || scan.isClosing || scan.tagName.length === 0) {
        continue;
      }
      const tagContent = searchContent.substring(scan.startIndex, scan.endIndex + 1);
      const idValue = this.extractAttributeValueFromTagContent(tagContent, 'id');
      if (idValue !== null && idValue.toLowerCase() === lowerIdName) {
        this.pushElementIfNew(results, seenStartIndexes, searchContent, scan.startIndex, scan.tagName, maxElements);
      }
    }
    
    // 如果还是没找到，输出HTML中所有id属性供诊断（仅在开启trace时）
    if (results.length === 0 && LegadoRuleAnalyzer.ENABLE_SELECTOR_TRACE) {
      const allIds: string[] = [];
      const idRegex = /\bid\s*=\s*["']?([^"'\s>]+)["']?/gi;
      let idMatch = idRegex.exec(searchContent);
      while (idMatch !== null && allIds.length < 10) {
        if (!allIds.includes(idMatch[1])) {
          allIds.push(idMatch[1]);
        }
        idMatch = idRegex.exec(searchContent);
      }
      if (allIds.length > 0) {
        this.selectorTrace((): string => `findElementsById: 未找到id="${idName}", HTML中存在的id: ${allIds.join(', ')}`);
      } else {
        this.selectorTrace((): string => `findElementsById: 未找到id="${idName}", HTML中没有任何id属性`);
      }
    }
    
    // 性能优化：减少日志输出
    if (content.length < 10000) {
      this.selectorTrace((): string => `findElementsById: 找到${results.length}个元素`);
    }
    return results;
  }

  /**
   * 按标签名查找元素
   * 添加性能保护：限制元素数量和内容大小以避免ANR
   */
  private findElementsByTag(content: string, tagName: string, maxElementsHint: number = 0): string[] {
    const results: string[] = [];
    
    // 性能保护：使用统一配置
    let maxElements = this.getMaxElements(PerformanceConfig.MAX_ELEMENTS);
    if (maxElementsHint > 0) {
      maxElements = Math.min(maxElements, maxElementsHint);
    }
    const searchContent = PerformanceConfig.safeSubstring(content);

    const normalizedTagName = tagName.trim().toLowerCase();
    let searchStart = 0;
    while (searchStart < searchContent.length && results.length < maxElements) {
      const tagStart = this.findTagStartByName(searchContent, searchStart, normalizedTagName);
      if (tagStart === -1) {
        break;
      }

      const startTagEnd = this.findHtmlTagEnd(searchContent, tagStart);
      if (startTagEnd === -1) {
        break;
      }
      const matchedTagName = normalizedTagName || this.extractTagNameAt(searchContent, tagStart).toLowerCase();
      if (matchedTagName) {
        const element = this.extractElement(searchContent, tagStart, matchedTagName);
        if (element) {
          results.push(element);
        }
      }
      searchStart = startTagEnd + 1;
    }

    return results;
  }

  /**
   * 按文本内容查找元素
   * 添加性能保护：限制元素数量和内容大小以避免ANR
   */
  private findElementsByText(content: string, searchText: string, maxElementsHint: number = 0): string[] {
    const results: string[] = [];
    
    // 性能保护：使用统一配置
    let maxElements = this.getMaxElements(PerformanceConfig.MAX_ELEMENTS);
    if (maxElementsHint > 0) {
      maxElements = Math.min(maxElements, maxElementsHint);
    }
    const searchContent = PerformanceConfig.safeSubstring(content);

    if (!searchText) {
      return results;
    }

    const targetLower = searchText.toLowerCase();
    let searchStart = 0;
    while (searchStart < searchContent.length && results.length < maxElements) {
      const tagStart = this.findTagStartByName(searchContent, searchStart, '');
      if (tagStart === -1) {
        break;
      }

      const tagName = this.extractTagNameAt(searchContent, tagStart).toLowerCase();
      if (!tagName) {
        const invalidTagEnd = this.findHtmlTagEnd(searchContent, tagStart);
        if (invalidTagEnd === -1) {
          break;
        }
        searchStart = invalidTagEnd + 1;
        continue;
      }

      const startTagEnd = this.findHtmlTagEnd(searchContent, tagStart);
      if (startTagEnd === -1) {
        break;
      }

      const textStart = startTagEnd + 1;
      const nextLt = searchContent.indexOf('<', textStart);
      if (nextLt === -1) {
        break;
      }
      if (nextLt <= textStart || nextLt + 1 >= searchContent.length || searchContent[nextLt + 1] !== '/') {
        searchStart = startTagEnd + 1;
        continue;
      }

      let closeNameEnd = nextLt + 2;
      while (closeNameEnd < searchContent.length) {
        const code = searchContent.charCodeAt(closeNameEnd);
        if (!this.isAlphaNumericCode(code)) {
          break;
        }
        closeNameEnd++;
      }
      const closeTagName = searchContent.substring(nextLt + 2, closeNameEnd).toLowerCase();
      if (closeTagName !== tagName) {
        searchStart = startTagEnd + 1;
        continue;
      }

      const closeTagEnd = this.findHtmlTagEnd(searchContent, nextLt);
      if (closeTagEnd === -1) {
        break;
      }

      const textContent = searchContent.substring(textStart, nextLt);
      if (textContent.toLowerCase().indexOf(targetLower) !== -1) {
        results.push(searchContent.substring(tagStart, closeTagEnd + 1));
      }

      searchStart = closeTagEnd + 1;
    }

    return results;
  }
  
  /**
   * 转义正则特殊字符
   */
  private escapeRegex(str: string): string {
    return str.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  }

  /**
   * 通过CSS选择器获取字符串列表
   */
  private getStringListByCSS(selector: string): string[] {
    const result = this.parseCSSSelectorAndAttr(selector);
    const elements = this.getElementsByCSS(result.sel);
    const values: string[] = elements.map((el: string): string => this.extractAttribute(el, result.attr));
    return this.shouldDeduplicateLegadoAttributeValues(result.attr)
      ? this.deduplicateLegadoAttributeValues(values)
      : values;
  }

  /**
   * 通过CSS选择器获取元素列表
   * 支持Legado的@分隔符语法，例如 .container ul@li
   * 支持&&操作符（与操作，合并多个选择器结果）
   * 
   * 优先使用HTML解析器进行DOM解析，回退到字符串解析
   */
  private getElementsByCSS(selector: string): string[] {
    // 先处理 && 操作符（与操作，合并多个选择器的结果）
    if (selector.includes('&&')) {
      const andParts = selector.split('&&');
      const allResults: string[] = [];
      for (const part of andParts) {
        const trimmedPart = part.trim();
        if (trimmedPart) {
          const results = this.getElementsByCSSWithBridge(trimmedPart);
          for (const r of results) {
            allResults.push(r);
          }
        }
      }
      this.selectorTrace((): string => `getElementsByCSS: &&操作符，合并结果数量=${allResults.length}`);
      return allResults;
    }
    
    return this.getElementsByCSSWithBridge(selector);
  }
  
  /**
   * 使用HTML桥接获取元素（优先使用DOM解析）
   * 注意：对于大型HTML（>50KB），DOM解析可能导致主线程阻塞，应使用字符串解析
   */
  private getElementsByCSSWithBridge(selector: string): string[] {
    // 性能保护：对于大型HTML，直接使用字符串解析避免ANR
    // DOM解析的querySelectorAll对于大型HTML有O(n²)复杂度问题
    const HTML_SIZE_THRESHOLD = 50000; // 50KB
    const contentLength = this.content.length;
    
    if (contentLength > HTML_SIZE_THRESHOLD) {
      if (LegadoRuleAnalyzer.ENABLE_SELECTOR_TRACE) {
        logger.debug(TAG, `getElementsByCSSWithBridge: HTML过大(${contentLength}字节)，使用字符串解析避免ANR`);
      }
      return this.getElementsByCSSChain(selector);
    }
    
    // 如果有HTML桥接，优先使用DOM解析
    if (this.htmlBridge) {
      try {
        // Chained rules that contain a legacy index must use the canonical
        // selector path. The bridge has a fast chain implementation, but its
        // index grammar is intentionally smaller than the full Legado grammar
        // (notably `!0`, ranges, and negative indexes).
        if (selector.includes('@')) {
          if (this.hasLegacyIndexInCssChain(selector)) {
            return this.getElementsByCSSChain(selector);
          }
          const elements = this.htmlBridge.parseChainRuleToHtmlList(selector);
          if (elements.length > 0) {
            if (LegadoRuleAnalyzer.ENABLE_SELECTOR_TRACE) {
              logger.debug(TAG, `getElementsByCSSWithBridge: 使用HTML桥接解析链式规则，结果数量=${elements.length}`);
            }
            return elements;
          }
        } else {
          // The DOM matcher accepts standard CSS only. Normalize Legado's
          // trailing index expression before matching so bridge and string
          // fallback paths keep the same selection semantics.
          const indexResult = this.parseIndexSelector(selector);
          const elements = this.htmlBridge.querySelectorAll(indexResult.selector);
          if (elements.length > 0) {
            let results = elements.map((elem: HtmlElement): string => elem.outerHTML);
            if (indexResult.hasIndex) {
              results = this.applyIndexFilter(results, indexResult);
            }
            if (LegadoRuleAnalyzer.ENABLE_SELECTOR_TRACE) {
              logger.debug(TAG, `getElementsByCSSWithBridge: 使用HTML桥接解析CSS选择器，结果数量=${results.length}`);
            }
            return results;
          }
        }
      } catch (e) {
        logger.warn(TAG, `HTML桥接解析失败，回退到字符串解析: ${String(e)}`);
      }
    }
    
    // 回退到字符串解析
    return this.getElementsByCSSChain(selector);
  }

  /** Keeps indexed bridge chains on the single, full Legado index implementation. */
  private hasLegacyIndexInCssChain(selector: string): boolean {
    const parts: string[] = this.splitSelectorWithJs(selector);
    for (let index = 0; index < parts.length; index++) {
      const part: string = parts[index].trim();
      if (part.length <= 0) {
        continue;
      }
      if (this.parseIndexSelector(part).hasIndex) {
        return true;
      }
    }
    return false;
  }

  /**
   * 处理CSS选择器链（@分隔）
   * 支持属性+JS组合：a@href<js>...</js>
   */
  private getElementsByCSSChain(selector: string): string[] {
    // Split only top-level Legado chain delimiters. An @ inside a pseudo
    // argument, attribute value, quoted string, escape or <js> block belongs
    // to that selector part and must reach the Jsoup-compatible evaluator.
    const parts: string[] = this.splitSelectorWithJs(selector);
    this.selectorTrace((): string => `getElementsByCSSChain: selector=${selector}, parts=${parts.length}`);
    
    const needsOccurrenceMarkers = selector.includes(':') || selector.includes(',') ||
      selector.includes('>') || selector.includes('+') || selector.includes('~');
    const selectionContextHtml = needsOccurrenceMarkers
      ? this.annotateStringSelectorHtml(this.content, 0)
      : this.content;
    let currentElements: string[] = [selectionContextHtml];
    
    for (let i = 0; i < parts.length; i++) {
      const part = parts[i].trim();
      if (!part) continue;
      
      // 检查是否是属性+JS组合：attr<js>...</js>
      const attrJsMatch = part.match(/^([a-zA-Z_-]+)<js>([\s\S]*)<\/js>$/i);
      if (attrJsMatch) {
        // 这是属性+JS组合，提取属性值并执行JS
        const attrName = attrJsMatch[1].toLowerCase();
        const jsCode = attrJsMatch[2];
        this.selectorTrace((): string => `getElementsByCSSChain: 属性+JS组合, attr=${attrName}`);
        
        const newElements: string[] = [];
        for (const element of currentElements) {
          const attrValue = this.extractAttribute(element, attrName);
          if (attrValue) {
            const jsResult = this.evalJS(`var result = ${JSON.stringify(attrValue)}; ${jsCode}`);
            if (jsResult) {
              newElements.push(jsResult);
            }
          }
        }
        currentElements = newElements;
      } else {
        // 普通选择器
        const newElements: string[] = [];
        for (const element of currentElements) {
          const found = this.findElementsBySingleSelector(element, part, selectionContextHtml);
          for (const f of found) {
            newElements.push(f);
          }
        }
        currentElements = newElements;
      }
      this.selectorTrace((): string => `getElementsByCSSChain: part[${i}]=${part.substring(0, 50)}, found=${currentElements.length}`);
      
      if (currentElements.length === 0) {
        break;
      }
    }
    
    if (!needsOccurrenceMarkers) {
      return currentElements;
    }
    return currentElements.map((element: string): string => {
      return this.stripStringSelectorOccurrenceMarker(element);
    });
  }
  
  /**
   * Split Legado's @ chain only at top level. Parentheses, brackets, quotes,
   * escapes and <js> blocks are selector-local contexts, not chain boundaries.
   */
  private splitSelectorWithJs(selector: string): string[] {
    const parts: string[] = [];
    let current = '';
    let inJs = false;

    let parenthesisDepth = 0;
    let bracketDepth = 0;
    let quote = '';
    let escaped = false;
    let index = 0;
    while (index < selector.length) {
      if (!inJs && selector.substring(index, index + 4).toLowerCase() === '<js>') {
        inJs = true;
        current += selector.substring(index, index + 4);
        index += 4;
        continue;
      }
      if (inJs && selector.substring(index, index + 5).toLowerCase() === '</js>') {
        inJs = false;
        current += selector.substring(index, index + 5);
        index += 5;
        continue;
      }

      const character = selector[index];
      if (inJs) {
        current += character;
        index++;
        continue;
      }
      if (escaped) {
        current += character;
        escaped = false;
        index++;
        continue;
      }
      if (character === '\\') {
        current += character;
        escaped = true;
        index++;
        continue;
      }
      if (quote.length > 0) {
        current += character;
        if (character === quote) {
          quote = '';
        }
        index++;
        continue;
      }
      if (character === '"' || character === "'") {
        quote = character;
        current += character;
        index++;
        continue;
      }
      if (character === '(' && bracketDepth === 0) {
        parenthesisDepth++;
        current += character;
        index++;
        continue;
      }
      if (character === ')' && parenthesisDepth > 0 && bracketDepth === 0) {
        parenthesisDepth--;
        current += character;
        index++;
        continue;
      }
      if (character === '[') {
        bracketDepth++;
        current += character;
        index++;
        continue;
      }
      if (character === ']' && bracketDepth > 0) {
        bracketDepth--;
        current += character;
        index++;
        continue;
      }
      if (character === '@' && parenthesisDepth === 0 && bracketDepth === 0) {
        const part = current.trim();
        if (part.length > 0) {
          parts.push(part);
        }
        current = '';
        index++;
        continue;
      }
      current += character;
      index++;
    }

    const finalPart = current.trim();
    if (finalPart.length > 0) {
      parts.push(finalPart);
    }
    return parts;
  }

  /**
   * 解析CSS选择器和属性
   * 支持Legado的@分隔符语法
   */
  private parseCSSSelectorAndAttr(selector: string): CssSelectorResult {
    // Legado使用@分隔选择器链，最后一个@后面可能是属性名
    // 例如 .s2 a@href 意味着：选择.s2 a，然后提取href属性
    // 例如 .s2 a@text 意味着：选择.s2 a，然后提取文本
    
    const parts = selector.split('@');
    let attr = 'text';
    let sel = selector;
    
    if (parts.length > 1) {
      const lastPart = parts[parts.length - 1].trim().toLowerCase();
      // 检查最后一部分是否是属性名（而不是选择器）
      const attrNames = ['text', 'href', 'src', 'html', 'textcontent', 'textnodes', 'owntext', 
                         'innerhtml', 'data-src', 'content', 'title', 'alt', 'value', 'class', 'id'];
      if (attrNames.includes(lastPart) || lastPart.startsWith('data-')) {
        attr = lastPart;
        sel = parts.slice(0, -1).join('@');
      }
    }

    const result: CssSelectorResult = { sel: sel, attr: attr };
    return result;
  }

  /**
   * 使用单个选择器查找元素
   * 支持: tag, .class, #id, tag.class, 空格分隔的后代选择器
   * 支持索引选择器: .0, .-1, [0,2,4], [!0,1], [0:10], [0:10:2]
   * 支持Legado特殊选择器: class.xxx, tag.xxx, id.xxx, text.xxx, children
   */
  private findElementsBySingleSelector(
    html: string,
    selector: string,
    selectorContextHtml: string = ''
  ): string[] {
    const effectiveContextHtml = selectorContextHtml.length > 0 ? selectorContextHtml : html;
    const selectorGroups = this.splitTopLevelCssSelectorGroups(selector);
    if (selectorGroups.length > 1) {
      return this.mergeSelectorGroupResultsByOccurrence(html, selectorGroups, effectiveContextHtml);
    }

    // Evaluate top-level CSS sibling/child chains before the simple class/id
    // fast path.  Selectors such as `.item+.next` contain no whitespace and
    // would otherwise be returned by the single-class shortcut unchanged.
    const siblingChain = this.splitTopLevelCssSiblingCombinatorSelector(selector);
    if (siblingChain !== null) {
      return this.findElementsByCssCombinatorChain(html, siblingChain, effectiveContextHtml);
    }

    // 先检查是否是CSS标准选择器格式（.class 或 #id）
    // 这些选择器不应该被parseIndexSelector处理，因为.后面不是数字
    const isCssClassSelector = selector.startsWith('.') && !/^\.\d/.test(selector);
    const isCssIdSelector = selector.startsWith('#');
    
    // 检查是否包含空格（后代选择器），如 "#chapterlist li a"
    const hasDescendant = selector.includes(' ');
    // A class/id selector can still contain a top-level child combinator
    // without whitespace (for example `#chapterlist>p` or `.manga-list>a`).
    // Keep those selectors on the direct-child path; the simple-selector
    // fast path would otherwise consume the whole chain as an id/class token.
    const hasTopLevelDirectChildCombinator = this.splitTopLevelDirectChildSelectors(selector).length > 1;

    if ((isCssClassSelector || isCssIdSelector) && !hasDescendant && !hasTopLevelDirectChildCombinator) {
      // 简单的CSS选择器（不含后代选择器），直接使用findElementsBySimpleSelector处理
      this.selectorTrace((): string => `findElementsBySingleSelector: 简单CSS选择器=${selector}, htmlLen=${html.length}`);
      return this.findElementsBySimpleSelector(html, selector, effectiveContextHtml);
    }
    
    // 解析索引选择器 [0,2,4] 或 [!0,1] 或 [0:10] 或 [0:10:2]
    const indexResult = this.parseIndexSelector(selector);
    selector = indexResult.selector;

    const directChildParts = this.splitTopLevelDirectChildSelectors(selector);
    if (directChildParts.length > 1) {
      const directChildResults = this.findElementsByDirectChildSelector(html, selector, effectiveContextHtml);
      return indexResult.hasIndex ? this.applyIndexFilter(directChildResults, indexResult) : directChildResults;
    }
    
    this.selectorTrace((): string => `findElementsBySingleSelector: selector=${selector}, htmlLen=${html.length}, startsWithId=${selector.startsWith('id.')}, startsWithClass=${selector.startsWith('class.')}`);
    
    // 处理Legado特殊选择器格式
    // class.xxx - 按类名查找
    if (selector.startsWith('class.')) {
      const className = selector.substring(6);
      const results = this.findElementsByClass(html, className);
      return indexResult.hasIndex ? this.applyIndexFilter(results, indexResult) : results;
    }
    
    // tag.xxx - 按标签名查找
    if (selector.startsWith('tag.')) {
      const tagName = selector.substring(4);
      const results = this.findElementsByTag(html, tagName);
      return indexResult.hasIndex ? this.applyIndexFilter(results, indexResult) : results;
    }
    
    // tbody - 特殊处理：HTML中可能没有显式tbody标签，直接返回table内容或整个内容
    if (selector === 'tbody') {
      // 尝试查找显式的tbody
      let results = this.findElementsByTag(html, 'tbody');
      if (results.length === 0) {
        // 没有显式tbody，尝试查找table并返回其内容
        const tables = this.findElementsByTag(html, 'table');
        if (tables.length > 0) {
          results = tables; // 返回table内容，让后续选择器在table中查找tr
        } else {
          // 没有table，返回整个内容
          results = [html];
        }
      }
      return indexResult.hasIndex ? this.applyIndexFilter(results, indexResult) : results;
    }
    
    // id.xxx - 按ID查找
    if (selector.startsWith('id.')) {
      const idName = selector.substring(3);
      this.selectorTrace((): string => `id.xxx选择器: idName=${idName}`);
      const results = this.findElementsById(html, idName);
      this.selectorTrace((): string => `id.xxx选择器结果: ${results.length}个`);
      return indexResult.hasIndex ? this.applyIndexFilter(results, indexResult) : results;
    }
    
    // text.xxx - 按文本内容查找
    if (selector.startsWith('text.')) {
      const searchText = selector.substring(5);
      const results = this.findElementsByText(html, searchText);
      return indexResult.hasIndex ? this.applyIndexFilter(results, indexResult) : results;
    }
    
    // children - 获取子元素
    if (selector === 'children') {
      const results = this.findDirectChildren(html);
      return indexResult.hasIndex ? this.applyIndexFilter(results, indexResult) : results;
    }
    
    // 处理空格分隔的后代选择器，例如 ".container ul" 或 "tbody tr"
    const selectorParts = this.splitTopLevelCssDescendantSelector(selector);
    
    let results: string[] = [];
    if (selectorParts.length > 1) {
      // 多级选择器，递归处理
      this.selectorTrace((): string => `findElementsBySingleSelector: 多级选择器, parts=${JSON.stringify(selectorParts)}`);
      let currentElements: string[] = [html];
      for (const part of selectorParts) {
        const newElements: string[] = [];
        for (const element of currentElements) {
          // 对tbody进行特殊处理
          let found: string[] = [];
          if (part === 'tbody') {
            found = this.findElementsByTag(element, 'tbody');
            this.selectorTrace((): string => `findElementsBySingleSelector: tbody查找, found=${found.length}`);
            if (found.length === 0) {
              // 没有显式tbody，尝试在table中查找
              const tables = this.findElementsByTag(element, 'table');
              this.selectorTrace((): string => `findElementsBySingleSelector: table查找, found=${tables.length}`);
              if (tables.length > 0) {
                found = tables;
              } else {
                // 没有table也没有tbody，直接使用当前元素继续
                found = [element];
              }
            }
          } else {
            found = this.findElementsBySimpleSelector(element, part, effectiveContextHtml);
            this.selectorTrace((): string => `findElementsBySingleSelector: part=${part}, found=${found.length}`);
          }
          for (const f of found) {
            newElements.push(f);
          }
        }
        currentElements = newElements;
        if (currentElements.length === 0) {
          this.selectorTrace((): string => `findElementsBySingleSelector: part=${part}后结果为空，停止`);
          break;
        }
      }
      results = currentElements;
    } else {
      results = this.findElementsBySimpleSelector(html, selector, effectiveContextHtml);
    }
    
    // 应用索引选择
    if (indexResult.hasIndex) {
      results = this.applyIndexFilter(results, indexResult);
    }
    
    return results;
  }

  /**
   * 使用简单选择器查找元素
   * 支持: tag, .class, #id, tag.class, [attr], [attr=value]
   */
  private findElementsBySimpleSelector(
    html: string,
    selector: string,
    selectorContextHtml: string = ''
  ): string[] {
    const effectiveContextHtml = selectorContextHtml.length > 0 ? selectorContextHtml : html;
    // 解析选择器组件
    let tagName = '';
    let className = '';
    let idName = '';
    const attributeParse = this.parseLegadoAttributeSelectors(selector);
    const attributeSelectors = attributeParse.attributes;
    const pseudoParse = this.parseLegadoPseudoSelectors(attributeParse.selector);
    const pseudoSelectors = pseudoParse.pseudoClasses;
    selector = pseudoParse.selector;
    
    // 解析class
    const classMatch = selector.match(/\.([a-zA-Z0-9_-]+)/);
    if (classMatch) {
      className = classMatch[1];
      selector = selector.replace(/\.[a-zA-Z0-9_-]+/, '');
    }
    
    // 解析id
    const idMatch = selector.match(/#([a-zA-Z0-9_-]+)/);
    if (idMatch) {
      idName = idMatch[1];
      selector = selector.replace(/#[a-zA-Z0-9_-]+/, '');
    }
    
    // 解析tag
    const tagMatch = selector.match(/^([a-zA-Z0-9]+)/);
    if (tagMatch) {
      tagName = tagMatch[1].toLowerCase();
    }
    
    // 如果只有class，使用findElementsByClass
    if (className && !tagName && !idName && attributeSelectors.length === 0) {
      return this.filterElementsByPseudoClasses(this.findElementsByClass(html, className), pseudoSelectors, effectiveContextHtml);
    }
    
    // 如果只有id，使用findElementsById
    if (idName && !tagName && !className && attributeSelectors.length === 0) {
      return this.filterElementsByPseudoClasses(this.findElementsById(html, idName), pseudoSelectors, effectiveContextHtml);
    }
    
    // 如果只有tag，使用findElementsByTag
    if (tagName && !className && !idName && attributeSelectors.length === 0) {
      return this.filterElementsByPseudoClasses(this.findElementsByTag(html, tagName), pseudoSelectors, effectiveContextHtml);
    }
    
    // 复合选择器：使用字符串搜索方法
    const results: string[] = [];
    const seenStartIndexes: Set<number> = new Set();
    let searchStart = 0;
    
    while (searchStart < html.length) {
      // 通过统一扫描器推进，注释和属性值中的伪标签不会重新进入候选路径
      const scan = this.scanNextHtmlTag(html, searchStart);
      if (scan === null) {
        break;
      }
      searchStart = scan.endIndex + 1;
      if (scan.isSpecial || scan.isClosing || scan.tagName.length === 0) {
        continue;
      }
      const tagStartIndex = scan.startIndex;
      const tagEndIndex = scan.endIndex;
      
      // 提取标签内容
      const tagContent = html.substring(tagStartIndex, tagEndIndex + 1);
      const currentTagName = scan.tagName;
      
      // 检查标签名
      if (tagName && currentTagName !== tagName) {
        searchStart = tagEndIndex + 1;
        continue;
      }
      
      // 检查class
      if (className) {
        const classAttrValue = this.extractAttributeValueFromTagContent(tagContent, 'class');
        if (classAttrValue === null || !this.hasClass(classAttrValue, className)) {
          searchStart = tagEndIndex + 1;
          continue;
        }
      }
      
      // 检查id
      if (idName) {
        const idAttrValue = this.extractAttributeValueFromTagContent(tagContent, 'id');
        if (idAttrValue === null || idAttrValue !== idName) {
          searchStart = tagEndIndex + 1;
          continue;
        }
      }
      
      // 检查属性选择器。Legado 的 ~= 与浏览器 CSS 不同，按 Jsoup
      // 正则语义匹配，而不是按空白分隔 token 匹配。
      let attributesMatch = true;
      for (const attributeSelector of attributeSelectors) {
        const attrActualValue = this.extractAttributeValueFromTagContent(tagContent, attributeSelector.name);
        if (attrActualValue === null || !this.matchesLegadoAttributeSelector(attrActualValue, attributeSelector)) {
          attributesMatch = false;
          break;
        }
      }
      if (!attributesMatch) {
          searchStart = tagEndIndex + 1;
          continue;
      }
      
      // 匹配成功，提取完整元素
      this.pushElementIfNew(results, seenStartIndexes, html, tagStartIndex, currentTagName, Number.MAX_SAFE_INTEGER);
      
      searchStart = tagEndIndex + 1;
    }
    
    return this.filterElementsByPseudoClasses(results, pseudoSelectors, effectiveContextHtml);
  }

  private splitTopLevelCssSelectorGroups(selector: string): string[] {
    const groups: string[] = [];
    let current = '';
    let parenthesisDepth = 0;
    let bracketDepth = 0;
    let quote = '';
    let escaped = false;
    for (let index = 0; index < selector.length; index++) {
      const character = selector[index];
      if (escaped) {
        current += character;
        escaped = false;
        continue;
      }
      if (character === '\\') {
        current += character;
        escaped = true;
        continue;
      }
      if (quote) {
        current += character;
        if (character === quote) {
          quote = '';
        }
        continue;
      }
      if (character === '"' || character === "'") {
        quote = character;
        current += character;
        continue;
      }
      if (character === '(' && bracketDepth === 0) {
        parenthesisDepth++;
      } else if (character === ')' && parenthesisDepth > 0 && bracketDepth === 0) {
        parenthesisDepth--;
      } else if (character === '[') {
        bracketDepth++;
      } else if (character === ']' && bracketDepth > 0) {
        bracketDepth--;
      }
      if (character === ',' && parenthesisDepth === 0 && bracketDepth === 0) {
        if (current.trim()) {
          groups.push(current.trim());
        }
        current = '';
      } else {
        current += character;
      }
    }
    if (current.trim()) {
      groups.push(current.trim());
    }
    return groups;
  }

  /**
   * Splits descendant combinators only at the selector's top level. Spaces
   * inside pseudo arguments, attribute values, quoted strings, or escaped
   * identifiers belong to the current selector part and must be preserved.
   */
  private splitTopLevelCssDescendantSelector(selector: string): string[] {
    const parts: string[] = [];
    let current = '';
    let parenthesisDepth = 0;
    let bracketDepth = 0;
    let quote = '';
    let escaped = false;
    for (let index = 0; index < selector.length; index++) {
      const character = selector[index];
      if (escaped) {
        current += character;
        escaped = false;
        continue;
      }
      if (character === '\\') {
        current += character;
        escaped = true;
        continue;
      }
      if (quote.length > 0) {
        current += character;
        if (character === quote) {
          quote = '';
        }
        continue;
      }
      if (character === '"' || character === "'") {
        current += character;
        quote = character;
        continue;
      }
      if (character === '(' && bracketDepth === 0) {
        parenthesisDepth++;
        current += character;
        continue;
      }
      if (character === ')' && parenthesisDepth > 0 && bracketDepth === 0) {
        parenthesisDepth--;
        current += character;
        continue;
      }
      if (character === '[') {
        bracketDepth++;
        current += character;
        continue;
      }
      if (character === ']' && bracketDepth > 0) {
        bracketDepth--;
        current += character;
        continue;
      }
      if (parenthesisDepth === 0 && bracketDepth === 0 && /\s/.test(character)) {
        if (current.trim().length > 0) {
          parts.push(current.trim());
          current = '';
        }
        continue;
      }
      current += character;
    }
    if (current.trim().length > 0) {
      parts.push(current.trim());
    }
    return parts;
  }

  /**
   * Add an internal source-offset attribute while evaluating a selector group.
   * String extraction otherwise loses identity when two nodes have identical
   * outerHTML. The marker never leaves this method's selector evaluation path.
   */
  private annotateStringSelectorHtml(html: string, baseOffset: number): string {
    if (html.includes('data-legado-occurrence-index="')) {
      return html;
    }
    const chunks: string[] = [];
    let cursor = 0;
    while (cursor < html.length) {
      const tagStart = html.indexOf('<', cursor);
      if (tagStart < 0) {
        chunks.push(html.substring(cursor));
        break;
      }
      chunks.push(html.substring(cursor, tagStart));
      if (tagStart + 1 >= html.length || html[tagStart + 1] === '/' || html[tagStart + 1] === '!') {
        const tagEnd = this.findHtmlTagEnd(html, tagStart);
        if (tagEnd < 0) {
          chunks.push(html.substring(tagStart));
          break;
        }
        chunks.push(html.substring(tagStart, tagEnd + 1));
        cursor = tagEnd + 1;
        continue;
      }
      const tagEnd = this.findHtmlTagEnd(html, tagStart);
      if (tagEnd < 0) {
        chunks.push(html.substring(tagStart));
        break;
      }
      const tag = html.substring(tagStart, tagEnd + 1);
      if (!/^<[a-zA-Z][a-zA-Z0-9]*/.test(tag)) {
        chunks.push(tag);
        cursor = tagEnd + 1;
        continue;
      }
      const insertionIndex = tag.endsWith('/>') ? tag.length - 2 : tag.length - 1;
      const marker = ` data-legado-occurrence-index="${baseOffset + tagStart}"`;
      chunks.push(tag.substring(0, insertionIndex));
      chunks.push(marker);
      chunks.push(tag.substring(insertionIndex));
      cursor = tagEnd + 1;
    }
    return chunks.join('');
  }

  private stripStringSelectorOccurrenceMarker(value: string): string {
    return value.replace(/\sdata-legado-occurrence-index="\d+"/g, '');
  }

  private findAnnotatedSelectorOccurrences(
    annotatedHtml: string,
    selector: string,
    originalHtml: string,
    baseOffset: number,
    annotatedContextHtml: string
  ): StringElementOccurrence[] {
    const markedResults = this.findElementsBySingleSelector(annotatedHtml, selector, annotatedContextHtml);
    const occurrences: StringElementOccurrence[] = [];
    const seenOffsets = new Set<number>();
    for (const markedResult of markedResults) {
      const markerMatch = markedResult.match(/data-legado-occurrence-index="(\d+)"/);
      if (markerMatch === null) {
        continue;
      }
      const absoluteOffset = parseInt(markerMatch[1], 10);
      const localOffset = absoluteOffset - baseOffset;
      if (Number.isNaN(absoluteOffset) || localOffset < 0 || seenOffsets.has(absoluteOffset)) {
        continue;
      }
      const tagName = this.getTagName(markedResult);
      const originalElement = originalHtml.includes('data-legado-occurrence-index="')
        ? this.stripStringSelectorOccurrenceMarker(markedResult)
        : this.extractElement(originalHtml, localOffset, tagName);
      if (originalElement === null || originalElement.length === 0) {
        continue;
      }
      seenOffsets.add(absoluteOffset);
      occurrences.push(new StringElementOccurrence(originalElement, absoluteOffset, tagName));
    }
    if (occurrences.length > 0 || markedResults.length === 0) {
      return occurrences;
    }
    const unmarkedResults = markedResults.map((result: string): string => {
      return this.stripStringSelectorOccurrenceMarker(result);
    });
    const fallback = this.mapStringElementOccurrences(originalHtml, unmarkedResults);
    return fallback.map((occurrence: StringElementOccurrence): StringElementOccurrence => {
      return new StringElementOccurrence(occurrence.element, occurrence.startIndex + baseOffset, occurrence.tagName);
    });
  }

  private mergeSelectorGroupResultsByOccurrence(
    html: string,
    selectorGroups: string[],
    selectorContextHtml: string
  ): string[] {
    const effectiveContextHtml = selectorContextHtml.length > 0 ? selectorContextHtml : html;
    const htmlBaseOffset = effectiveContextHtml === html ? 0 : effectiveContextHtml.indexOf(html);
    if (htmlBaseOffset >= 0) {
      const annotatedHtml = this.annotateStringSelectorHtml(html, htmlBaseOffset);
      const annotatedContextHtml = this.annotateStringSelectorHtml(effectiveContextHtml, 0);
      const occurrenceResults: StringElementOccurrence[] = [];
      const seenOffsets = new Set<number>();
      for (const group of selectorGroups) {
        const groupOccurrences = this.findAnnotatedSelectorOccurrences(
          annotatedHtml,
          group,
          html,
          htmlBaseOffset,
          annotatedContextHtml
        );
        for (const occurrence of groupOccurrences) {
          if (!seenOffsets.has(occurrence.startIndex)) {
            seenOffsets.add(occurrence.startIndex);
            occurrenceResults.push(occurrence);
          }
        }
      }
      occurrenceResults.sort((left: StringElementOccurrence, right: StringElementOccurrence): number => {
        return left.startIndex - right.startIndex;
      });
      return occurrenceResults.map((occurrence: StringElementOccurrence): string => occurrence.element);
    }

    const occurrences: StringElementOccurrence[] = [];
    const seenOffsets = new Set<number>();
    for (const group of selectorGroups) {
      const groupResults = this.findElementsBySingleSelector(html, group, selectorContextHtml);
      const groupOccurrences = this.mapStringElementOccurrences(html, groupResults);
      if (groupOccurrences.length !== groupResults.length) {
        return [];
      }
      for (const occurrence of groupOccurrences) {
        if (!seenOffsets.has(occurrence.startIndex)) {
          seenOffsets.add(occurrence.startIndex);
          occurrences.push(occurrence);
        }
      }
    }
    occurrences.sort((left: StringElementOccurrence, right: StringElementOccurrence): number => {
      return left.startIndex - right.startIndex;
    });
    return occurrences.map((occurrence: StringElementOccurrence): string => occurrence.element);
  }

  /**
   * 检查class属性是否包含指定的class
   */
  private hasClass(classAttr: string, className: string): boolean {
    const classes = classAttr.split(/\s+/);
    return classes.includes(className);
  }

  /**
   * 从指定位置提取完整的HTML元素
   */
  private getUnclosedElementFallback(html: string, startIndex: number): string {
    const fallbackEnd = Math.min(
      html.length,
      startIndex + PerformanceConfig.MAX_UNCLOSED_ELEMENT_FALLBACK_SIZE
    );
    return html.substring(startIndex, fallbackEnd);
  }

  private extractElement(html: string, startIndex: number, tagName: string): string | null {
    // 检查是否是自关闭标签
    const normalizedTagName = tagName.toLowerCase();
    if (LegadoRuleAnalyzer.SELF_CLOSING_TAGS.has(normalizedTagName)) {
      const endOfTag = this.findHtmlTagEnd(html, startIndex);
      if (endOfTag !== -1) {
        return html.substring(startIndex, endOfTag + 1);
      }
      return null;
    }
    
    // 查找匹配的结束标签。只按共享扫描器识别真实的同名节点，避免
    // 引号属性里的 </tag> 或 <tag> 文本改变元素深度。
    let depth = 1;
    const startTagEnd = this.findHtmlTagEnd(html, startIndex);
    if (startTagEnd === -1) {
      return null;
    }
    let pos = startTagEnd + 1;
    while (depth > 0 && pos < html.length) {
      const scan = this.scanNextHtmlTag(html, pos);
      if (scan === null) {
        return this.getUnclosedElementFallback(html, startIndex);
      }
      if (!scan.isSpecial && scan.tagName === normalizedTagName) {
        if (scan.isClosing) {
          depth--;
        } else if (!scan.isSelfClosing) {
          depth++;
        }
      }
      pos = scan.endIndex + 1;
    }
    
    if (depth === 0) {
      return html.substring(startIndex, pos);
    }
    
    return this.getUnclosedElementFallback(html, startIndex);
  }

  /**
   * 从元素中提取属性
   * 支持Legado原版的所有属性提取方式
   */
  private extractAttribute(element: string, attr: string): string {
    switch (attr.toLowerCase()) {
      case 'text':
      case 'textcontent':
        // Legado AnalyzeByJSoup delegates to Jsoup Element.text(). The
        // parsed projection is shared with the DOM bridge so block/br
        // boundaries and whitespace state cannot drift in the large-input
        // fallback path.
        return this.extractJsoupText(element);
      case 'textnodes':
        // Each direct TextNode is normalized independently, Java-trimmed and
        // joined with LF by AnalyzeByJSoup.getResultLast().
        return this.extractDirectTextNodes(element);
      case 'owntext':
        // ownText shares one accumulator across direct TextNodes and inserts
        // an ASCII space for a direct <br>.
        return this.extractOwnText(element);
      case 'html':
        // Legado JSoup @html returns outerHtml after removing script/style.
        return this.removeScriptAndStyleElements(element);
      case 'innerhtml':
        // 获取内部HTML（移除script和style）
        const innerHtml = this.removeScriptAndStyleElements(element);
        const innerMatch = innerHtml.match(/^<[^>]+>([\s\S]*)<\/[^>]+>$/);
        return innerMatch ? innerMatch[1] : '';
      case 'all':
      case 'outerhtml':
        // 获取完整外部HTML
        return element;
      case 'srcset':
      case 'data-srcset':
        return this.extractSrcSetUrl(element, attr);
      case 'href':
      case 'src':
      case 'data-src':
      case 'data-original':
      case 'data-lazy-src':
      case 'data-original-src':
      case 'data-url':
      case 'data-img':
      case 'data-cover':
        // AnalyzeByJSoup uses Element.attr here and keeps the source value
        // unchanged. URL consumers decide when and against which redirect
        // target to resolve it; resolving at selector time changes JS and
        // replacement-rule semantics.
        const urlAttrValue = this.extractAttributeValueFromTagContent(element, attr);
        return urlAttrValue === null ? '' : urlAttrValue;
      case 'content':
        // 获取meta标签的content属性
        const contentValue = this.extractAttributeValueFromTagContent(element, 'content');
        return contentValue === null ? '' : contentValue;
      default:
        // 其他属性
        const defaultValue = this.extractAttributeValueFromTagContent(element, attr);
        return defaultValue === null ? '' : defaultValue;
    }
  }

  private removeScriptAndStyleElements(html: string): string {
    const retained: string[] = [];
    let cursor = 0;
    let retainedStart = 0;
    while (cursor < html.length) {
      const scan = this.scanNextHtmlTag(html, cursor);
      if (scan === null) {
        break;
      }
      const isRemovable = !scan.isSpecial && !scan.isClosing &&
        (scan.tagName === 'script' || scan.tagName === 'style');
      if (isRemovable) {
        const element = this.extractElement(html, scan.startIndex, scan.tagName);
        if (element !== null) {
          if (scan.startIndex > retainedStart) {
            retained.push(html.substring(retainedStart, scan.startIndex));
          }
          cursor = scan.startIndex + Math.max(1, element.length);
          retainedStart = cursor;
          continue;
        }
      }
      cursor = scan.endIndex + 1;
    }
    if (retainedStart < html.length) {
      retained.push(html.substring(retainedStart));
    }
    return retained.join('');
  }

  private extractDirectTextNodes(element: string): string {
    const parsed = parseHtml(element);
    const candidate = this.firstParsedElement(parsed);
    return candidate.textNodes;
  }

  private extractOwnText(element: string): string {
    const parsed = parseHtml(element);
    const candidate = this.firstParsedElement(parsed);
    return candidate.ownText;
  }

  private extractJsoupText(element: string): string {
    return parseHtml(element).text;
  }

  private firstParsedElement(parsed: HtmlElement): HtmlElement {
    const children = parsed.children;
    return children.length > 0 ? children[0] : parsed;
  }

  private appendLegacyTextNode(
    accumulator: LegadoTextAccumulator,
    value: string,
    preserveWhitespace: boolean
  ): void {
    accumulator.appendText(this.decodeHtmlEntitiesFast(value), preserveWhitespace);
  }

  private extractTagNameFromRawTag(tag: string): string {
    let index = 1;
    if (tag.charAt(index) === '/') {
      index++;
    }
    while (index < tag.length && this.isWhitespaceChar(tag.charAt(index))) {
      index++;
    }
    const start = index;
    while (index < tag.length && /[A-Za-z0-9]/.test(tag.charAt(index))) {
      index++;
    }
    return tag.substring(start, index).toLowerCase();
  }

  private findHtmlTagEnd(html: string, start: number): number {
    let quote = '';
    for (let index = start; index < html.length; index++) {
      const character = html.charAt(index);
      if (quote.length > 0) {
        if (character === quote) {
          quote = '';
        }
      } else if (character === '"' || character === "'") {
        quote = character;
      } else if (character === '>') {
        return index;
      }
    }
    return -1;
  }

  private isSelfClosingHtmlTag(tag: string): boolean {
    const trimmed = tag.trim();
    if (trimmed.endsWith('/>')) {
      return true;
    }
    let index = 1;
    while (index < trimmed.length && /[A-Za-z0-9]/.test(trimmed.charAt(index))) {
      index++;
    }
    const tagName = trimmed.substring(1, index).toLowerCase();
    return LegadoRuleAnalyzer.SELF_CLOSING_TAGS.has(tagName);
  }

  private extractSrcSetUrl(element: string, attr: string): string {
    const srcsetValue = this.extractAttributeValueFromTagContent(element, attr);
    if (srcsetValue === null || srcsetValue.trim().length === 0) {
      return '';
    }
    const candidates = srcsetValue.split(',');
    for (const candidate of candidates) {
      const trimmed = candidate.trim();
      if (!trimmed) {
        continue;
      }
      const firstPart = trimmed.split(/\s+/)[0].trim();
      if (firstPart.length > 0) {
        return firstPart;
      }
    }
    return '';
  }

  /**
   * 将HTML转换为纯文本
   * 移除所有HTML标签、script、style、注释，并处理HTML实体
   */
  private htmlToTextCached(html: string): string {
    if (!html) {
      return '';
    }
    if (html.length > PerformanceConfig.HTML_TO_TEXT_CACHE_MAX_INPUT_SIZE) {
      return this.htmlToText(html);
    }
    const cacheKey = this.buildHtmlToTextCacheKey(html);
    const cached = this.htmlToTextCache.get(cacheKey);
    if (cached !== undefined) {
      return cached;
    }

    const parsed = this.htmlToText(html);
    if (this.htmlToTextCache.size >= PerformanceConfig.HTML_TO_TEXT_CACHE_SIZE) {
      const firstKey = this.htmlToTextCache.keys().next().value as string | undefined;
      if (firstKey) {
        this.htmlToTextCache.delete(firstKey);
      }
    }
    this.htmlToTextCache.set(cacheKey, parsed);
    return parsed;
  }

  private buildHtmlToTextCacheKey(html: string): string {
    const len = html.length;
    let hash = 2166136261;
    if (len > 0) {
      const step = Math.max(1, Math.floor(len / 32));
      for (let i = 0; i < len; i += step) {
        hash ^= html.charCodeAt(i);
        hash = (hash * 16777619) >>> 0;
      }
      hash ^= html.charCodeAt(len - 1);
      hash = (hash * 16777619) >>> 0;
    }
    const headLen = Math.min(48, len);
    const tailLen = Math.min(48, len);
    const head = html.substring(0, headLen);
    const tail = html.substring(len - tailLen);
    return `${len}|${hash.toString(16)}|${head}|${tail}`;
  }

  private htmlToText(html: string): string {
    if (!html) {
      return '';
    }

    // 保护性截断：避免异常规则把整页甚至大文件都送进文本转换。
    let text = PerformanceConfig.safeSubstring(html, PerformanceConfig.MAX_TEXT_PARSE_INPUT_SIZE);
    const hasTags = text.indexOf('<') !== -1;
    if (hasTags) {
      text = this.stripHtmlTagsFast(text);
    } else {
      const accumulator = new LegadoTextAccumulator();
      accumulator.appendText(this.decodeHtmlEntitiesFast(text), false);
      text = accumulator.toTrimmedString();
    }
    if (text.length > PerformanceConfig.MAX_TEXT_OUTPUT_SIZE) {
      return this.trimLegadoTextWhitespace(text.substring(0, PerformanceConfig.MAX_TEXT_OUTPUT_SIZE));
    }
    return text;
  }

  private isAlphaNumericCode(code: number): boolean {
    return (code >= 48 && code <= 57) || (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
  }

  private isAlphaNumericChar(ch: string): boolean {
    if (!ch || ch.length === 0) {
      return false;
    }
    return this.isAlphaNumericCode(ch.charCodeAt(0));
  }

  private isBreakTagName(tagName: string): boolean {
    return tagName === 'br' || LegadoTextNormalization.isBlockTag(tagName);
  }

  private stripHtmlTagsFast(html: string): string {
    const accumulator = new LegadoTextAccumulator();
    const outputLimit = PerformanceConfig.MAX_TEXT_OUTPUT_SIZE * 2;
    let i = 0;
    let textStart = 0;
    let skipTag = '';
    let preserveTag = '';
    const len = html.length;

    while (i < len && accumulator.length < outputLimit) {
      // 在script/style中时，直接跳到下一个标签起点
      if (skipTag) {
        const nextTag = html.indexOf('<', i);
        if (nextTag === -1) {
          break;
        }
        i = nextTag;
      }

      if (html[i] !== '<') {
        i++;
        continue;
      }

      if (!skipTag && i > textStart) {
        const part = html.substring(textStart, i);
        if (part) {
          accumulator.appendText(this.decodeHtmlEntitiesFast(part), preserveTag.length > 0);
          if (accumulator.length >= outputLimit) {
            break;
          }
        }
      }

      // HTML注释
      if (i + 3 < len && html[i + 1] === '!' && html[i + 2] === '-' && html[i + 3] === '-') {
        const commentEnd = html.indexOf('-->', i + 4);
        i = commentEnd === -1 ? len : commentEnd + 3;
        textStart = i;
        continue;
      }

      // 解析标签名
      let j = i + 1;
      let isClosingTag = false;
      if (j < len && html[j] === '/') {
        isClosingTag = true;
        j++;
      }
      while (j < len && this.isWhitespaceChar(html[j])) {
        j++;
      }

      const nameStart = j;
      while (j < len) {
        const code = html.charCodeAt(j);
        if (!this.isAlphaNumericCode(code)) {
          break;
        }
        j++;
      }
      const tagName = nameStart < j ? html.substring(nameStart, j).toLowerCase() : '';

      // 查找标签结束，处理引号内的 >
      let k = j;
      let quoteChar = '';
      while (k < len) {
        const tk = html[k];
        if (quoteChar) {
          if (tk === quoteChar) {
            quoteChar = '';
          }
        } else if (tk === '"' || tk === "'") {
          quoteChar = tk;
        } else if (tk === '>') {
          break;
        }
        k++;
      }
      const tagEnd = k < len ? k + 1 : len;

      if (skipTag) {
        if (isClosingTag && tagName === skipTag) {
          skipTag = '';
        }
        i = tagEnd;
        textStart = i;
        continue;
      }

      if (!isClosingTag && (tagName === 'script' || tagName === 'style')) {
        skipTag = tagName;
        i = tagEnd;
        textStart = i;
        continue;
      }

      if (!isClosingTag && LegadoTextNormalization.isPreserveWhitespaceTag(tagName)) {
        preserveTag = tagName;
      } else if (isClosingTag && preserveTag === tagName) {
        preserveTag = '';
      }

      if (tagName === 'br') {
        accumulator.appendLineBreak();
      } else if (this.isBreakTagName(tagName)) {
        accumulator.appendBlockBoundary();
      }

      i = tagEnd;
      textStart = i;
    }

    if (!skipTag && textStart < len && accumulator.length < outputLimit) {
      const tailLen = Math.min(len - textStart, outputLimit - accumulator.length);
      if (tailLen > 0) {
        const tail = html.substring(textStart, textStart + tailLen);
        accumulator.appendText(this.decodeHtmlEntitiesFast(tail), preserveTag.length > 0);
      }
    }

    return accumulator.toTrimmedString();
  }

  private decodeHtmlEntitiesFast(text: string): string {
    return HtmlEntities.decode(text);
  }

  private normalizePlainText(text: string): string {
    let result = text;

    if (result.indexOf('\r') !== -1) {
      result = result.replace(/\r\n?/g, '\n');
    }
    if (result.indexOf('\t') !== -1 || result.indexOf('  ') !== -1) {
      result = result.replace(/[ \t]+/g, ' ');
    }
    if (result.indexOf('\n') !== -1) {
      // 去除每行首尾空白并收敛空行
      result = result.replace(/^[ \t]+|[ \t]+$/gm, '');
      result = result.replace(/\n{3,}/g, '\n\n');
    }

    return this.trimLegadoTextWhitespace(result);
  }

  /**
   * JSoup's text normalization trims only characters up to U+0020 here.
   * JavaScript String.trim() also removes U+3000, which is meaningful reader
   * indentation in real Legado source paragraphs and must survive until
   * HtmlFormatter applies the upstream presentation rules.
   */
  private trimLegadoTextWhitespace(value: string): string {
    let start = 0;
    let end = value.length;
    while (start < end && value.charCodeAt(start) <= 0x20) {
      start++;
    }
    while (end > start && value.charCodeAt(end - 1) <= 0x20) {
      end--;
    }
    return value.substring(start, end);
  }

  // ==================== XPath解析 ====================

  /**
   * 预处理HTML内容，处理特殊情况
   * 参考Kotlin原版strToJXDocument
   */
  private preprocessHtmlForXPath(html: string): string {
    let processed = html;
    
    // 处理表格片段，自动包装
    if (processed.trimEnd().endsWith('</td>')) {
      processed = `<tr>${processed}</tr>`;
    }
    if (processed.trimEnd().endsWith('</tr>') || processed.trimEnd().endsWith('</tbody>')) {
      processed = `<table>${processed}</table>`;
    }
    
    return processed;
  }

  /**
   * 通过XPath获取字符串
   * 完整实现，支持多种XPath语法
   */
  private getStringByXPath(xpath: string): string {
    const results = this.getStringListByXPath(xpath);
    return results.length > 0 ? results.join('\n') : '';
  }

  /**
   * 通过XPath获取字符串列表
   * 支持: //tag, //tag[@attr='value'], //tag/text(), //tag/@attr
   * 支持: //tag[position()], //tag[contains(@attr,'value')]
   * 支持: 规则分割符 &&, ||, %%
   */
  private getStringListByXPath(xpath: string): string[] {
    // 处理规则分割符
    const splitResult = this.splitRuleStr(xpath);
    if (splitResult.rules.length > 1) {
      return this.getXPathListWithSplitRules(splitResult.rules, splitResult.splitType);
    }
    
    return this.getStringListByXPathSingle(xpath);
  }

  /**
   * 使用分割规则获取XPath字符串列表
   */
  private getXPathListWithSplitRules(rules: string[], splitType: string): string[] {
    const allResults: string[][] = [];
    
    for (const rule of rules) {
      const results = this.getStringListByXPathSingle(rule);
      if (results.length > 0) {
        allResults.push(results);
        if (splitType === '||') {
          return results;
        }
      }
    }
    
    if (allResults.length === 0) {
      return [];
    }
    
    if (splitType === '&&') {
      const merged: string[] = [];
      for (const results of allResults) {
        for (const r of results) {
          merged.push(r);
        }
      }
      return merged;
    }
    
    // %% 交叉合并
    const maxLen = Math.max(...allResults.map(r => r.length));
    const merged: string[] = [];
    for (let i = 0; i < maxLen; i++) {
      for (const results of allResults) {
        if (i < results.length) {
          merged.push(results[i]);
        }
      }
    }
    return merged;
  }

  /**
   * 单个XPath规则获取字符串列表
   */
  private getStringListByXPathSingle(xpath: string): string[] {
    const results: string[] = [];
    
    // 预处理HTML
    const processedContent = this.preprocessHtmlForXPath(this.content);
    
    // 解析XPath末尾的提取类型
    let path = xpath;
    let extractType = 'text';
    let extractAttr = '';

    // 检查 /text()
    if (path.endsWith('/text()')) {
      path = path.substring(0, path.length - 7);
      extractType = 'text';
    }
    // 检查 /@attr
    else if (path.match(/@([a-zA-Z0-9_-]+)$/)) {
      const attrMatch = path.match(/@([a-zA-Z0-9_-]+)$/);
      if (attrMatch) {
        extractAttr = attrMatch[1];
        path = path.substring(0, path.length - attrMatch[0].length);
        if (path.endsWith('/')) {
          path = path.substring(0, path.length - 1);
        }
        extractType = 'attr';
      }
    }
    // 检查 /string()
    else if (path.endsWith('/string()')) {
      path = path.substring(0, path.length - 9);
      extractType = 'text';
    }
    // 检查 /allText()
    else if (path.endsWith('/allText()')) {
      path = path.substring(0, path.length - 10);
      extractType = 'allText';
    }
    // 检查 /html()
    else if (path.endsWith('/html()')) {
      path = path.substring(0, path.length - 7);
      extractType = 'html';
    }
    // 检查 /outerHtml()
    else if (path.endsWith('/outerHtml()')) {
      path = path.substring(0, path.length - 12);
      extractType = 'outerHtml';
    }
    // 检查 /node()
    else if (path.endsWith('/node()')) {
      path = path.substring(0, path.length - 7);
      extractType = 'node';
    }
    // 检查 /normalize-space()
    else if (path.endsWith('/normalize-space()')) {
      path = path.substring(0, path.length - 18);
      extractType = 'normalizeSpace';
    }

    // 解析XPath路径
    const elements = this.getElementsByXPathPathWithContent(path, processedContent);
    
    for (const element of elements) {
      let value = '';
      switch (extractType) {
        case 'text':
          value = this.extractAllText(element);
          break;
        case 'allText':
          value = this.extractAllText(element);
          break;
        case 'attr':
          if (extractAttr) {
            value = this.extractAttribute(element, extractAttr);
          }
          break;
        case 'html':
          value = this.extractInnerHtml(element);
          break;
        case 'outerHtml':
          value = element;
          break;
        case 'node':
          value = element;
          break;
        case 'normalizeSpace':
          value = this.normalizeSpace(this.extractAllText(element));
          break;
        default:
          value = this.extractAllText(element);
      }
      
      if (value) {
        results.push(value);
      }
    }

    return results;
  }

  /**
   * 提取元素的内部HTML
   */
  private extractInnerHtml(element: string): string {
    // 移除外层标签
    const match = element.match(/^<[^>]+>([\s\S]*)<\/[^>]+>$/);
    return match ? match[1] : element;
  }

  /**
   * 根据XPath路径获取元素（使用指定内容）
   */
  private getElementsByXPathPathWithContent(xpath: string, content: string): string[] {
    let elements: string[] = [content];
    
    // 分解XPath路径
    const steps = this.parseXPathSteps(xpath);
    
    for (const step of steps) {
      const newElements: string[] = [];
      for (const element of elements) {
        const matched = this.matchXPathStepWithAxis(element, step, content);
        for (const m of matched) {
          newElements.push(m);
        }
      }
      elements = newElements;
      if (elements.length === 0) break;
    }
    
    return elements;
  }

  /**
   * 匹配XPath步骤（支持轴选择器）
   */
  private matchXPathStepWithAxis(html: string, step: XPathStep, fullContent: string): string[] {
    // 检查是否有轴选择器
    const axisMatch = step.tag.match(/^([a-z-]+)::(.+)$/);
    if (axisMatch) {
      const axis = axisMatch[1];
      const tag = axisMatch[2];
      return this.matchXPathAxis(html, axis, tag, step.predicates, fullContent);
    }
    
    // 普通标签匹配
    return this.matchXPathStep(html, step);
  }

  /**
   * 匹配XPath轴选择器
   */
  private matchXPathAxis(
    currentElement: string,
    axis: string,
    tag: string,
    predicates: XPathPredicate[],
    fullContent: string
  ): string[] {
    let elements: string[] = [];
    
    switch (axis) {
      case 'following-sibling':
        elements = this.getFollowingSiblings(currentElement, tag, fullContent);
        break;
      case 'preceding-sibling':
        elements = this.getPrecedingSiblings(currentElement, tag, fullContent);
        break;
      case 'parent':
        elements = this.getParentElement(currentElement, tag, fullContent);
        break;
      case 'ancestor':
        elements = this.getAncestorElements(currentElement, tag, fullContent);
        break;
      case 'child':
        elements = this.getChildElementsWithTag(currentElement, tag);
        break;
      case 'descendant':
        elements = this.getDescendantElements(currentElement, tag);
        break;
      case 'self':
        elements = this.getSelfElement(currentElement, tag);
        break;
      case 'descendant-or-self':
        elements = [currentElement, ...this.getDescendantElements(currentElement, tag)];
        break;
      default:
        // 默认当作普通标签处理
        elements = this.findElementsByTag(currentElement, tag === '*' ? '' : tag);
    }
    
    // 应用谓词过滤
    for (const pred of predicates) {
      elements = this.applyXPathPredicate(elements, pred);
    }
    
    return elements;
  }

  /**
   * 获取后续兄弟元素
   */
  private getFollowingSiblings(element: string, tag: string, fullContent: string): string[] {
    const results: string[] = [];
    const elementIndex = fullContent.indexOf(element);
    if (elementIndex === -1) return results;
    
    const afterContent = fullContent.substring(elementIndex + element.length);
    const parentEnd = this.findParentEndTag(fullContent, elementIndex);
    const searchContent = parentEnd > 0 ? afterContent.substring(0, parentEnd - elementIndex - element.length) : afterContent;
    
    if (tag === '*') {
      return this.findAllElements(searchContent);
    }
    return this.findElementsByTag(searchContent, tag);
  }

  /**
   * 获取前面的兄弟元素
   */
  private getPrecedingSiblings(element: string, tag: string, fullContent: string): string[] {
    const results: string[] = [];
    const elementIndex = fullContent.indexOf(element);
    if (elementIndex === -1) return results;
    
    const parentStart = this.findParentStartTag(fullContent, elementIndex);
    const searchContent = fullContent.substring(parentStart, elementIndex);
    
    if (tag === '*') {
      return this.findAllElements(searchContent);
    }
    return this.findElementsByTag(searchContent, tag);
  }

  /**
   * 获取父元素
   */
  private getParentElement(element: string, tag: string, fullContent: string): string[] {
    const elementIndex = fullContent.indexOf(element);
    if (elementIndex === -1) return [];

    const openTags: HtmlTagScan[] = [];
    let cursor = 0;
    while (cursor < elementIndex) {
      const scan = this.scanNextHtmlTag(fullContent, cursor);
      if (scan === null || scan.startIndex >= elementIndex) {
        break;
      }
      if (!scan.isSpecial) {
        if (scan.isClosing) {
          for (let index = openTags.length - 1; index >= 0; index--) {
            if (openTags[index].tagName === scan.tagName) {
              openTags.splice(index, 1);
              break;
            }
          }
        } else if (scan.tagName.length > 0 && !scan.isSelfClosing) {
          openTags.push(scan);
        }
      }
      cursor = scan.endIndex + 1;
    }

    if (openTags.length === 0) {
      return [];
    }
    const parentScan = openTags[openTags.length - 1];
    if (tag !== '*' && parentScan.tagName !== tag.toLowerCase()) {
      return [];
    }
    const parentElement = this.extractElement(fullContent, parentScan.startIndex, parentScan.tagName);
    return parentElement === null ? [] : [parentElement];
  }

  /**
   * 获取祖先元素
   */
  private getAncestorElements(element: string, tag: string, fullContent: string): string[] {
    const results: string[] = [];
    let currentElement = element;
    
    while (true) {
      const parents = this.getParentElement(currentElement, '*', fullContent);
      if (parents.length === 0) break;
      
      const parent = parents[0];
      if (tag === '*' || this.getTagName(parent) === tag) {
        results.push(parent);
      }
      currentElement = parent;
    }
    
    return results;
  }

  /**
   * 获取子元素（带标签过滤）
   */
  private getChildElementsWithTag(element: string, tag: string): string[] {
    const innerHtml = this.extractInnerHtml(element);
    if (tag === '*') {
      return this.findDirectChildren(innerHtml);
    }
    return this.findDirectChildrenByTag(innerHtml, tag);
  }

  /**
   * 获取后代元素
   */
  private getDescendantElements(element: string, tag: string): string[] {
    const innerHtml = this.extractInnerHtml(element);
    if (tag === '*') {
      return this.findAllElements(innerHtml);
    }
    return this.findElementsByTag(innerHtml, tag);
  }

  /**
   * 获取自身元素
   */
  private getSelfElement(element: string, tag: string): string[] {
    if (tag === '*') return [element];
    const elementTag = this.getTagName(element);
    return elementTag === tag ? [element] : [];
  }

  /**
   * 获取元素的标签名
   */
  private getTagName(element: string): string {
    const match = element.match(/^<([a-zA-Z][a-zA-Z0-9]*)/);
    return match ? match[1].toLowerCase() : '';
  }

  /**
   * 查找直接子元素
   */
  private findDirectChildren(html: string, maxElementsHint: number = 0): string[] {
    const results: string[] = [];
    const maxElements = maxElementsHint > 0 ? maxElementsHint : 0;
    let cursor = 0;
    while (cursor < html.length && (maxElements === 0 || results.length < maxElements)) {
      const scan = this.scanNextHtmlTag(html, cursor);
      if (scan === null) {
        break;
      }
      if (!scan.isSpecial && !scan.isClosing && scan.tagName.length > 0) {
        const element = this.extractElement(html, scan.startIndex, scan.tagName);
        if (element !== null) {
          results.push(element);
          cursor = scan.startIndex + Math.max(1, element.length);
          continue;
        }
      }
      cursor = scan.endIndex + 1;
    }
    return results;
  }

  /**
   * 按标签名查找直接子元素
   */
  private findDirectChildrenByTag(html: string, tag: string): string[] {
    return this.findDirectChildren(html).filter(el => this.getTagName(el) === tag.toLowerCase());
  }

  /**
   * 查找父元素结束标签位置
   */
  private findParentEndTag(content: string, startIndex: number): number {
    let depth = 0;
    let cursor = startIndex;
    while (cursor < content.length) {
      const scan = this.scanNextHtmlTag(content, cursor);
      if (scan === null) {
        break;
      }
      if (!scan.isSpecial) {
        if (scan.isClosing) {
          if (depth === 0) {
            return scan.startIndex;
          }
          depth--;
        } else if (scan.tagName.length > 0 && !scan.isSelfClosing) {
          depth++;
        }
      }
      cursor = scan.endIndex + 1;
    }
    return content.length;
  }

  /**
   * 查找父元素开始标签位置
   */
  private findParentStartTag(content: string, endIndex: number): number {
    const openTags: HtmlTagScan[] = [];
    let cursor = 0;
    while (cursor < endIndex) {
      const scan = this.scanNextHtmlTag(content, cursor);
      if (scan === null || scan.startIndex >= endIndex) {
        break;
      }
      if (!scan.isSpecial) {
        if (scan.isClosing) {
          for (let index = openTags.length - 1; index >= 0; index--) {
            if (openTags[index].tagName === scan.tagName) {
              openTags.splice(index, 1);
              break;
            }
          }
        } else if (scan.tagName.length > 0 && !scan.isSelfClosing) {
          openTags.push(scan);
        }
      }
      cursor = scan.endIndex + 1;
    }
    return openTags.length > 0 ? openTags[openTags.length - 1].startIndex : 0;
  }

  /**
   * 根据XPath路径获取元素
   */
  private getElementsByXPathPath(xpath: string): string[] {
    let elements: string[] = [this.content];
    
    // 分解XPath路径
    const steps = this.parseXPathSteps(xpath);
    
    for (const step of steps) {
      const newElements: string[] = [];
      for (const element of elements) {
        const matched = this.matchXPathStep(element, step);
        for (const m of matched) {
          newElements.push(m);
        }
      }
      elements = newElements;
      if (elements.length === 0) break;
    }
    
    return elements;
  }

  /**
   * 解析XPath步骤
   */
  private parseXPathSteps(xpath: string): XPathStep[] {
    const steps: XPathStep[] = [];
    
    // 移除开头的 // 或 /
    let path = xpath;
    let isDescendant = false;
    
    if (path.startsWith('//')) {
      path = path.substring(2);
      isDescendant = true;
    } else if (path.startsWith('/')) {
      path = path.substring(1);
    }
    
    // 分割路径，注意处理谓词中的 /
    const parts: string[] = [];
    let current = '';
    let bracketDepth = 0;
    
    for (let i = 0; i < path.length; i++) {
      const char = path[i];
      if (char === '[') bracketDepth++;
      else if (char === ']') bracketDepth--;
      
      if (char === '/' && bracketDepth === 0) {
        if (current) {
          parts.push(current);
        }
        current = '';
        // 检查是否是 //
        if (i + 1 < path.length && path[i + 1] === '/') {
          i++;
          if (current) parts.push(current);
          current = '';
          // 标记下一个为后代选择
          if (parts.length > 0) {
            steps.push(this.parseXPathPart(parts[parts.length - 1], false));
          }
          isDescendant = true;
          continue;
        }
      } else {
        current += char;
      }
    }
    if (current) {
      parts.push(current);
    }
    
    // 解析每个部分
    for (let i = 0; i < parts.length; i++) {
      const step = this.parseXPathPart(parts[i], i === 0 ? isDescendant : false);
      steps.push(step);
    }
    
    return steps;
  }

  /**
   * 解析单个XPath部分
   */
  private parseXPathPart(part: string, isDescendant: boolean): XPathStep {
    const step: XPathStep = {
      tag: '*',
      predicates: [],
      isDescendant: isDescendant
    };
    
    // 解析标签名和谓词
    const bracketIndex = part.indexOf('[');
    if (bracketIndex === -1) {
      step.tag = part || '*';
    } else {
      step.tag = part.substring(0, bracketIndex) || '*';
      
      // 解析谓词
      let predicateStr = part.substring(bracketIndex);
      const predicateRegex = /\[([^\]]+)\]/g;
      let match = predicateRegex.exec(predicateStr);
      while (match !== null) {
        step.predicates.push(this.parseXPathPredicate(match[1]));
        match = predicateRegex.exec(predicateStr);
      }
    }
    
    return step;
  }

  /**
   * 解析XPath谓词
   */
  private parseXPathPredicate(predicate: string): XPathPredicate {
    const pred: XPathPredicate = { type: 'unknown', value: predicate };
    
    // 数字索引 [1], [2]
    if (/^\d+$/.test(predicate)) {
      pred.type = 'position';
      pred.position = parseInt(predicate);
      return pred;
    }
    
    // last()
    if (predicate === 'last()') {
      pred.type = 'last';
      return pred;
    }
    
    // last()-n
    const lastMinusMatch = predicate.match(/^last\(\)\s*-\s*(\d+)$/);
    if (lastMinusMatch) {
      pred.type = 'lastMinus';
      pred.position = parseInt(lastMinusMatch[1]);
      return pred;
    }
    
    // position()=n 或 position()<n 等
    const posMatch = predicate.match(/^position\(\)\s*([<>=!]+)\s*(\d+)$/);
    if (posMatch) {
      pred.type = 'positionCompare';
      pred.operator = posMatch[1];
      pred.position = parseInt(posMatch[2]);
      return pred;
    }
    
    // position() mod n = m
    const posModMatch = predicate.match(/^position\(\)\s*mod\s*(\d+)\s*=\s*(\d+)$/);
    if (posModMatch) {
      pred.type = 'positionMod';
      pred.position = parseInt(posModMatch[1]); // 除数
      pred.value = posModMatch[2]; // 余数
      return pred;
    }
    
    // @attr='value'
    const attrEqMatch = predicate.match(/^@([a-zA-Z0-9_-]+)\s*=\s*['"]([^'"]*)['"]/);
    if (attrEqMatch) {
      pred.type = 'attrEquals';
      pred.attr = attrEqMatch[1];
      pred.value = attrEqMatch[2];
      return pred;
    }
    
    // @attr!='value'
    const attrNeqMatch = predicate.match(/^@([a-zA-Z0-9_-]+)\s*!=\s*['"]([^'"]*)['"]/);
    if (attrNeqMatch) {
      pred.type = 'attrNotEquals';
      pred.attr = attrNeqMatch[1];
      pred.value = attrNeqMatch[2];
      return pred;
    }
    
    // not(@attr='value')
    const notAttrEqMatch = predicate.match(/^not\s*\(\s*@([a-zA-Z0-9_-]+)\s*=\s*['"]([^'"]*)['"]\s*\)/);
    if (notAttrEqMatch) {
      pred.type = 'notAttrEquals';
      pred.attr = notAttrEqMatch[1];
      pred.value = notAttrEqMatch[2];
      return pred;
    }
    
    // not(contains(@attr, 'value'))
    const notContainsMatch = predicate.match(/^not\s*\(\s*contains\s*\(\s*@([a-zA-Z0-9_-]+)\s*,\s*['"]([^'"]*)['"]\s*\)\s*\)/);
    if (notContainsMatch) {
      pred.type = 'notAttrContains';
      pred.attr = notContainsMatch[1];
      pred.value = notContainsMatch[2];
      return pred;
    }
    
    // contains(@attr, 'value')
    const containsMatch = predicate.match(/^contains\s*\(\s*@([a-zA-Z0-9_-]+)\s*,\s*['"]([^'"]*)['"]\s*\)/);
    if (containsMatch) {
      pred.type = 'attrContains';
      pred.attr = containsMatch[1];
      pred.value = containsMatch[2];
      return pred;
    }
    
    // starts-with(@attr, 'value')
    const startsWithMatch = predicate.match(/^starts-with\s*\(\s*@([a-zA-Z0-9_-]+)\s*,\s*['"]([^'"]*)['"]\s*\)/);
    if (startsWithMatch) {
      pred.type = 'attrStartsWith';
      pred.attr = startsWithMatch[1];
      pred.value = startsWithMatch[2];
      return pred;
    }
    
    // ends-with(@attr, 'value')
    const endsWithMatch = predicate.match(/^ends-with\s*\(\s*@([a-zA-Z0-9_-]+)\s*,\s*['"]([^'"]*)['"]\s*\)/);
    if (endsWithMatch) {
      pred.type = 'attrEndsWith';
      pred.attr = endsWithMatch[1];
      pred.value = endsWithMatch[2];
      return pred;
    }
    
    // @attr (属性存在)
    if (/^@[a-zA-Z0-9_-]+$/.test(predicate)) {
      pred.type = 'attrExists';
      pred.attr = predicate.substring(1);
      return pred;
    }
    
    // not(@attr) 属性不存在
    const notAttrExistsMatch = predicate.match(/^not\s*\(\s*@([a-zA-Z0-9_-]+)\s*\)/);
    if (notAttrExistsMatch) {
      pred.type = 'attrNotExists';
      pred.attr = notAttrExistsMatch[1];
      return pred;
    }
    
    // text()='value'
    const textEqMatch = predicate.match(/^text\(\)\s*=\s*['"]([^'"]*)['"]/);
    if (textEqMatch) {
      pred.type = 'textEquals';
      pred.value = textEqMatch[1];
      return pred;
    }
    
    // text()!='value'
    const textNeqMatch = predicate.match(/^text\(\)\s*!=\s*['"]([^'"]*)['"]/);
    if (textNeqMatch) {
      pred.type = 'textNotEquals';
      pred.value = textNeqMatch[1];
      return pred;
    }
    
    // contains(text(), 'value')
    const textContainsMatch = predicate.match(/^contains\s*\(\s*text\(\)\s*,\s*['"]([^'"]*)['"]\s*\)/);
    if (textContainsMatch) {
      pred.type = 'textContains';
      pred.value = textContainsMatch[1];
      return pred;
    }
    
    // not(contains(text(), 'value'))
    const notTextContainsMatch = predicate.match(/^not\s*\(\s*contains\s*\(\s*text\(\)\s*,\s*['"]([^'"]*)['"]\s*\)\s*\)/);
    if (notTextContainsMatch) {
      pred.type = 'notTextContains';
      pred.value = notTextContainsMatch[1];
      return pred;
    }
    
    // starts-with(text(), 'value')
    const textStartsWithMatch = predicate.match(/^starts-with\s*\(\s*text\(\)\s*,\s*['"]([^'"]*)['"]\s*\)/);
    if (textStartsWithMatch) {
      pred.type = 'textStartsWith';
      pred.value = textStartsWithMatch[1];
      return pred;
    }
    
    // normalize-space()='value'
    const normalizeSpaceMatch = predicate.match(/^normalize-space\s*\(\s*\)\s*=\s*['"]([^'"]*)['"]/);
    if (normalizeSpaceMatch) {
      pred.type = 'normalizeSpaceEquals';
      pred.value = normalizeSpaceMatch[1];
      return pred;
    }
    
    // contains(normalize-space(), 'value')
    const containsNormalizeMatch = predicate.match(/^contains\s*\(\s*normalize-space\s*\(\s*\)\s*,\s*['"]([^'"]*)['"]\s*\)/);
    if (containsNormalizeMatch) {
      pred.type = 'normalizeSpaceContains';
      pred.value = containsNormalizeMatch[1];
      return pred;
    }
    
    // string-length(@attr) > n
    const strLenMatch = predicate.match(/^string-length\s*\(\s*@([a-zA-Z0-9_-]+)\s*\)\s*([<>=!]+)\s*(\d+)/);
    if (strLenMatch) {
      pred.type = 'stringLength';
      pred.attr = strLenMatch[1];
      pred.operator = strLenMatch[2];
      pred.position = parseInt(strLenMatch[3]);
      return pred;
    }
    
    // and/or 逻辑运算 - 简化处理
    if (predicate.includes(' and ')) {
      pred.type = 'and';
      pred.value = predicate;
      return pred;
    }
    if (predicate.includes(' or ')) {
      pred.type = 'or';
      pred.value = predicate;
      return pred;
    }
    
    return pred;
  }

  /**
   * 匹配XPath步骤
   */
  private matchXPathStep(html: string, step: XPathStep): string[] {
    const results: string[] = [];
    
    // 查找所有匹配标签的元素
    let elements: string[];
    if (step.tag === '*') {
      elements = this.findAllElements(html);
    } else {
      elements = this.findElementsByTag(html, step.tag);
    }
    
    // 应用谓词过滤
    let filtered = elements;
    for (const pred of step.predicates) {
      filtered = this.applyXPathPredicate(filtered, pred);
    }
    
    return filtered;
  }

  /**
   * 查找所有元素
   */
  private findAllElements(html: string): string[] {
    const results: string[] = [];
    let cursor = 0;
    while (cursor < html.length) {
      const scan = this.scanNextHtmlTag(html, cursor);
      if (scan === null) {
        break;
      }
      if (!scan.isSpecial && !scan.isClosing && scan.tagName.length > 0) {
        const element = this.extractElement(html, scan.startIndex, scan.tagName);
        if (element !== null) {
          results.push(element);
        }
      }
      cursor = scan.endIndex + 1;
    }
    return results;
  }

  /**
   * 应用XPath谓词
   */
  private applyXPathPredicate(elements: string[], pred: XPathPredicate): string[] {
    switch (pred.type) {
      case 'position':
        const idx = (pred.position || 1) - 1;
        return idx >= 0 && idx < elements.length ? [elements[idx]] : [];
        
      case 'last':
        return elements.length > 0 ? [elements[elements.length - 1]] : [];
        
      case 'lastMinus':
        const lastIdx = elements.length - 1 - (pred.position || 0);
        return lastIdx >= 0 && lastIdx < elements.length ? [elements[lastIdx]] : [];
        
      case 'positionCompare':
        return elements.filter((_, i) => {
          const pos = i + 1;
          switch (pred.operator) {
            case '<': return pos < (pred.position || 0);
            case '<=': return pos <= (pred.position || 0);
            case '>': return pos > (pred.position || 0);
            case '>=': return pos >= (pred.position || 0);
            case '=': return pos === (pred.position || 0);
            case '!=': return pos !== (pred.position || 0);
            default: return true;
          }
        });
        
      case 'positionMod':
        return elements.filter((_, i) => {
          const pos = i + 1;
          const divisor = pred.position || 1;
          const remainder = parseInt(pred.value || '0');
          return pos % divisor === remainder;
        });
        
      case 'attrEquals':
        return elements.filter(el => {
          const attrValue = this.extractAttribute(el, pred.attr || '');
          return attrValue === pred.value;
        });
        
      case 'attrNotEquals':
        return elements.filter(el => {
          const attrValue = this.extractAttribute(el, pred.attr || '');
          return attrValue !== pred.value;
        });
        
      case 'notAttrEquals':
        return elements.filter(el => {
          const attrValue = this.extractAttribute(el, pred.attr || '');
          return attrValue !== pred.value;
        });
        
      case 'attrContains':
        return elements.filter(el => {
          const attrValue = this.extractAttribute(el, pred.attr || '');
          return attrValue.includes(pred.value || '');
        });
        
      case 'notAttrContains':
        return elements.filter(el => {
          const attrValue = this.extractAttribute(el, pred.attr || '');
          return !attrValue.includes(pred.value || '');
        });
        
      case 'attrStartsWith':
        return elements.filter(el => {
          const attrValue = this.extractAttribute(el, pred.attr || '');
          return attrValue.startsWith(pred.value || '');
        });
        
      case 'attrEndsWith':
        return elements.filter(el => {
          const attrValue = this.extractAttribute(el, pred.attr || '');
          return attrValue.endsWith(pred.value || '');
        });
        
      case 'attrExists':
        return elements.filter(el => {
          const attrValue = this.extractAttribute(el, pred.attr || '');
          return attrValue !== '';
        });
        
      case 'attrNotExists':
        return elements.filter(el => {
          const attrValue = this.extractAttribute(el, pred.attr || '');
          return attrValue === '';
        });
        
      case 'textEquals':
        return elements.filter(el => {
          const text = this.extractAllText(el);
          return text === pred.value;
        });
        
      case 'textNotEquals':
        return elements.filter(el => {
          const text = this.extractAllText(el);
          return text !== pred.value;
        });
        
      case 'textContains':
        return elements.filter(el => {
          const text = this.extractAllText(el);
          return text.includes(pred.value || '');
        });
        
      case 'notTextContains':
        return elements.filter(el => {
          const text = this.extractAllText(el);
          return !text.includes(pred.value || '');
        });
        
      case 'textStartsWith':
        return elements.filter(el => {
          const text = this.extractAllText(el);
          return text.startsWith(pred.value || '');
        });
        
      case 'normalizeSpaceEquals':
        return elements.filter(el => {
          const text = this.normalizeSpace(this.extractAllText(el));
          return text === pred.value;
        });
        
      case 'normalizeSpaceContains':
        return elements.filter(el => {
          const text = this.normalizeSpace(this.extractAllText(el));
          return text.includes(pred.value || '');
        });
        
      case 'stringLength':
        return elements.filter(el => {
          const attrValue = this.extractAttribute(el, pred.attr || '');
          const len = attrValue.length;
          const target = pred.position || 0;
          switch (pred.operator) {
            case '<': return len < target;
            case '<=': return len <= target;
            case '>': return len > target;
            case '>=': return len >= target;
            case '=': return len === target;
            case '!=': return len !== target;
            default: return true;
          }
        });
        
      case 'and':
        // 处理 and 逻辑运算
        return this.applyAndPredicate(elements, pred.value || '');
        
      case 'or':
        // 处理 or 逻辑运算
        return this.applyOrPredicate(elements, pred.value || '');
        
      default:
        return elements;
    }
  }

  /**
   * 规范化空白字符
   */
  private normalizeSpace(text: string): string {
    return text.replace(/\s+/g, ' ').trim();
  }

  /**
   * 处理 and 逻辑运算
   */
  private applyAndPredicate(elements: string[], predicateStr: string): string[] {
    const parts = predicateStr.split(/\s+and\s+/);
    let result = elements;
    for (const part of parts) {
      const pred = this.parseXPathPredicate(part.trim());
      result = this.applyXPathPredicate(result, pred);
    }
    return result;
  }

  /**
   * 处理 or 逻辑运算
   */
  private applyOrPredicate(elements: string[], predicateStr: string): string[] {
    const parts = predicateStr.split(/\s+or\s+/);
    const resultSet = new Set<string>();
    for (const part of parts) {
      const pred = this.parseXPathPredicate(part.trim());
      const matched = this.applyXPathPredicate(elements, pred);
      for (const el of matched) {
        resultSet.add(el);
      }
    }
    // 保持原始顺序
    return elements.filter(el => resultSet.has(el));
  }

  /**
   * 提取所有文本（包括子元素）
   */
  private extractAllText(html: string): string {
    return html.replace(/<[^>]+>/g, '').replace(/\s+/g, ' ').trim();
  }

  /**
   * 通过XPath获取元素列表
   */
  private getElementsByXPath(xpath: string): string[] {
    return this.getElementsByXPathPath(xpath);
  }

  // ==================== 正则解析 ====================

  /**
   * 通过正则获取字符串
   * 支持: 单个正则, &&组合正则, ||组合正则
   */
  private getStringByRegex(pattern: string): string {
    // 处理规则分割符
    const splitResult = this.splitRuleStr(pattern);
    if (splitResult.rules.length > 1) {
      return this.getRegexStringWithSplitRules(splitResult.rules, splitResult.splitType);
    }
    
    return this.getStringByRegexSingle(pattern);
  }

  /**
   * 使用分割规则获取正则字符串
   */
  private getRegexStringWithSplitRules(rules: string[], splitType: string): string {
    const results: string[] = [];
    
    for (const rule of rules) {
      const result = this.getStringByRegexSingle(rule);
      if (result) {
        results.push(result);
        if (splitType === '||') {
          return result;
        }
      }
    }
    
    if (splitType === '&&') {
      return results.join('\n');
    }
    
    return results.length > 0 ? results[0] : '';
  }

  /**
   * 单个正则获取字符串
   */
  private getStringByRegexSingle(pattern: string): string {
    try {
      // 处理多个正则组合 (用&&分隔)
      const patterns = pattern.split('&&').map(p => p.trim());
      let content = this.content;
      
      for (const p of patterns) {
        if (!p) continue;
        
        const regex = new RegExp(p, 's'); // s标志使.匹配换行符
        const match = regex.exec(content);
        if (match) {
          // 优先返回第一个捕获组，否则返回整个匹配
          content = match.length > 1 ? match[1] : match[0];
        } else {
          return '';
        }
      }
      
      return content;
    } catch (e) {
      logger.warn(TAG, `正则匹配失败: ${pattern}`);
    }
    return '';
  }

  /**
   * 通过正则获取字符串列表
   * 支持: 单个正则, &&组合正则, ||组合正则, %%交叉合并
   */
  private getStringListByRegex(pattern: string): string[] {
    // 处理规则分割符
    const splitResult = this.splitRuleStr(pattern);
    if (splitResult.rules.length > 1) {
      return this.getRegexListWithSplitRules(splitResult.rules, splitResult.splitType);
    }
    
    return this.getStringListByRegexSingle(pattern);
  }

  /**
   * 使用分割规则获取正则字符串列表
   */
  private getRegexListWithSplitRules(rules: string[], splitType: string): string[] {
    const allResults: string[][] = [];
    
    for (const rule of rules) {
      const results = this.getStringListByRegexSingle(rule);
      if (results.length > 0) {
        allResults.push(results);
        if (splitType === '||') {
          return results;
        }
      }
    }
    
    if (allResults.length === 0) {
      return [];
    }
    
    if (splitType === '&&') {
      const merged: string[] = [];
      for (const results of allResults) {
        for (const r of results) {
          merged.push(r);
        }
      }
      return merged;
    }
    
    // %% 交叉合并
    const maxLen = Math.max(...allResults.map(r => r.length));
    const merged: string[] = [];
    for (let i = 0; i < maxLen; i++) {
      for (const results of allResults) {
        if (i < results.length) {
          merged.push(results[i]);
        }
      }
    }
    return merged;
  }

  /**
   * 单个正则获取字符串列表
   */
  private getStringListByRegexSingle(pattern: string): string[] {
    const results: string[] = [];
    try {
      // 处理多个正则组合 (用&&分隔)
      const patterns = pattern.split('&&').map(p => p.trim());
      
      if (patterns.length === 1) {
        // 单个正则，全局匹配
        const regex = new RegExp(pattern, 'gs');
        let match = regex.exec(this.content);
        while (match !== null) {
          results.push(match.length > 1 ? match[1] : match[0]);
          match = regex.exec(this.content);
        }
      } else {
        // 多个正则组合，先用第一个匹配所有，然后对每个结果应用后续正则
        const firstRegex = new RegExp(patterns[0], 'gs');
        let match = firstRegex.exec(this.content);
        
        while (match !== null) {
          let content = match.length > 1 ? match[1] : match[0];
          let valid = true;
          
          // 应用后续正则
          for (let i = 1; i < patterns.length; i++) {
            const subRegex = new RegExp(patterns[i], 's');
            const subMatch = subRegex.exec(content);
            if (subMatch) {
              content = subMatch.length > 1 ? subMatch[1] : subMatch[0];
            } else {
              valid = false;
              break;
            }
          }
          
          if (valid && content) {
            results.push(content);
          }
          
          match = firstRegex.exec(this.content);
        }
      }
    } catch (e) {
      logger.warn(TAG, `正则列表匹配失败: ${pattern}`);
    }
    return results;
  }

  private scanNextHtmlTag(html: string, fromIndex: number): HtmlTagScan | null {
    let cursor = Math.max(0, fromIndex);
    while (cursor < html.length) {
      const tagStart = html.indexOf('<', cursor);
      if (tagStart < 0) {
        return null;
      }
      const tagEnd = this.findHtmlTagEnd(html, tagStart);
      if (tagEnd < 0) {
        return null;
      }
      const rawTag = html.substring(tagStart, tagEnd + 1);
      const trimmedTag = rawTag.trim();
      const isSpecial = trimmedTag.startsWith('<!--') || trimmedTag.startsWith('<!') ||
        trimmedTag.startsWith('<?');
      const isClosing = !isSpecial && trimmedTag.startsWith('</');
      const tagName = isSpecial ? '' : this.extractTagNameFromRawTag(rawTag);
      return {
        startIndex: tagStart,
        endIndex: tagEnd,
        tagName: tagName,
        isClosing: isClosing,
        isSelfClosing: !isClosing && !isSpecial && this.isSelfClosingHtmlTag(rawTag),
        isSpecial: isSpecial
      };
    }
    return null;
  }

  /**
   * Parses one or more attribute selectors without treating regex character
   * classes inside `[attr~=...]` as the end of the selector.
   */
  private parseLegadoAttributeSelectors(selector: string): LegadoAttributeSelectorsResult {
    const attributes: LegadoAttributeSelector[] = [];
    let normalized = '';
    let cursor = 0;
    let parenthesisDepth = 0;
    let bracketDepth = 0;
    let quote = '';
    let escaped = false;
    while (cursor < selector.length) {
      const current = selector[cursor];
      if (escaped) {
        normalized += current;
        escaped = false;
        cursor++;
        continue;
      }
      if (current === '\\') {
        normalized += current;
        escaped = true;
        cursor++;
        continue;
      }
      if (quote.length > 0) {
        normalized += current;
        if (current === quote) {
          quote = '';
        }
        cursor++;
        continue;
      }
      if (current === '"' || current === "'") {
        normalized += current;
        quote = current;
        cursor++;
        continue;
      }
      if (current === '[') {
        if (parenthesisDepth === 0 && bracketDepth === 0) {
          const parsed = this.parseLegadoAttributeSelectorAt(selector, cursor);
          if (parsed !== null) {
            attributes.push(parsed.selector);
            cursor = parsed.endIndex;
            continue;
          }
        }
        bracketDepth++;
        normalized += current;
        cursor++;
        continue;
      }
      if (current === ']' && bracketDepth > 0) {
        bracketDepth--;
        normalized += current;
        cursor++;
        continue;
      }
      normalized += current;
      if (bracketDepth === 0) {
        if (current === '(') {
          parenthesisDepth++;
        } else if (current === ')' && parenthesisDepth > 0) {
          parenthesisDepth--;
        }
      }
      cursor++;
    }
    return { selector: normalized, attributes };
  }

  /**
   * Removes Jsoup text pseudo classes before the string selector matcher runs.
   * The matcher then applies the pseudo predicates to complete element HTML,
   * which preserves descendant text and direct-text semantics.
   */
  private parseLegadoPseudoSelectors(selector: string): LegadoPseudoSelectorsResult {
    const pseudoClasses: LegadoPseudoSelector[] = [];
    let normalized = '';
    let cursor = 0;
    let bracketDepth = 0;
    let quote = '';
    while (cursor < selector.length) {
      const current = selector[cursor];
      if (quote) {
        normalized += current;
        if (current === '\\' && cursor + 1 < selector.length) {
          normalized += selector[cursor + 1];
          cursor += 2;
          continue;
        }
        if (current === quote) {
          quote = '';
        }
        cursor++;
        continue;
      }
      if (current === '"' || current === "'") {
        quote = current;
        normalized += current;
        cursor++;
        continue;
      }
      if (current === '[') {
        bracketDepth++;
        normalized += current;
        cursor++;
        continue;
      }
      if (current === ']' && bracketDepth > 0) {
        bracketDepth--;
        normalized += current;
        cursor++;
        continue;
      }
      if (current !== ':' || bracketDepth > 0) {
        normalized += current;
        cursor++;
        continue;
      }

      let nameCursor = cursor + 1;
      if (nameCursor < selector.length && selector[nameCursor] === ':') {
        nameCursor++;
      }
      const nameStart = nameCursor;
      while (nameCursor < selector.length && /[A-Za-z0-9-]/.test(selector[nameCursor])) {
        nameCursor++;
      }
      if (nameCursor === nameStart) {
        normalized += current;
        cursor++;
        continue;
      }

      let argument = '';
      let endCursor = nameCursor;
      if (nameCursor < selector.length && selector[nameCursor] === '(') {
        endCursor++;
        let depth = 1;
        let argumentQuote = '';
        let escaped = false;
        let regexClassDepth = 0;
        while (endCursor < selector.length && depth > 0) {
          const argumentChar = selector[endCursor];
          if (escaped) {
            argument += argumentChar;
            escaped = false;
            endCursor++;
            continue;
          }
          if (argumentChar === '\\') {
            argument += argumentChar;
            escaped = true;
            endCursor++;
            continue;
          }
          if (argumentQuote) {
            argument += argumentChar;
            if (argumentChar === argumentQuote) {
              argumentQuote = '';
            }
            endCursor++;
            continue;
          }
          if (argumentChar === '"' || argumentChar === "'") {
            argumentQuote = argumentChar;
            argument += argumentChar;
            endCursor++;
            continue;
          }
          if (argumentChar === '[') {
            regexClassDepth++;
            argument += argumentChar;
            endCursor++;
            continue;
          }
          if (argumentChar === ']' && regexClassDepth > 0) {
            regexClassDepth--;
            argument += argumentChar;
            endCursor++;
            continue;
          }
          if (regexClassDepth === 0 && argumentChar === '(') {
            depth++;
          } else if (regexClassDepth === 0 && argumentChar === ')') {
            depth--;
          }
          if (depth > 0) {
            argument += argumentChar;
          }
          endCursor++;
        }
      }
      pseudoClasses.push({
        name: selector.substring(nameStart, nameCursor).toLowerCase(),
        argument: argument.trim()
      });
      cursor = endCursor;
    }
    return { selector: normalized, pseudoClasses };
  }

  private filterElementsByPseudoClasses(
    elements: string[],
    pseudoClasses: LegadoPseudoSelector[],
    contextHtml: string = ''
  ): string[] {
    let filtered = elements;
    for (const pseudo of pseudoClasses) {
      const argument = this.normalizeLegadoPseudoArgument(pseudo.argument);
      if (pseudo.name === 'contains' || pseudo.name === 'containsown') {
        const own = pseudo.name === 'containsown';
        filtered = filtered.filter((element: string): boolean => {
          const text = own ? this.extractOwnText(element) : this.extractAttribute(element, 'text');
          return text.includes(argument);
        });
        continue;
      }
      if (pseudo.name === 'matches' || pseudo.name === 'matchesown') {
        const own = pseudo.name === 'matchesown';
        const regexParts = this.parseLegadoRegexPrefix(argument);
        const matched: string[] = [];
        for (const element of filtered) {
          const text = own ? this.extractOwnText(element) : this.extractAttribute(element, 'text');
          try {
            if (new RegExp(regexParts.pattern, regexParts.flags).test(text)) {
              matched.push(element);
            }
          } catch (error) {
            logger.warn(TAG, `Jsoup 文本正则无效: ${argument}`);
          }
        }
        filtered = matched;
        continue;
      }
      if (pseudo.name === 'not') {
        if (argument.length === 0) {
          return [];
        }
        if (contextHtml.length === 0) {
          filtered = filtered.filter((element: string): boolean => {
            return !this.matchesStringNestedSelector(element, argument, contextHtml);
          });
        } else {
          const contextOccurrences = this.mapStringElementOccurrences(contextHtml, filtered);
          const contextFiltered: string[] = [];
          if (contextOccurrences.length === filtered.length) {
            const matchedOffsets = this.collectNestedSelectorMatchOffsets(contextHtml, argument);
            for (let elementIndex = 0; elementIndex < filtered.length; elementIndex++) {
              const element = filtered[elementIndex];
              const occurrence = contextOccurrences[elementIndex];
              if (!matchedOffsets.has(occurrence.startIndex)) {
                contextFiltered.push(element);
              }
            }
          } else {
            for (const element of filtered) {
              if (!this.matchesStringNestedSelector(element, argument, contextHtml)) {
                contextFiltered.push(element);
              }
            }
          }
          filtered = contextFiltered;
        }
        continue;
      }
      if (pseudo.name === 'has') {
        filtered = filtered.filter((element: string): boolean => this.matchesStringHasPseudo(element, argument));
        continue;
      }
      if (pseudo.name === 'empty') {
        filtered = filtered.filter((element: string): boolean => this.matchesStringEmptyPseudo(element));
        continue;
      }
      if (pseudo.name === 'first-child' || pseudo.name === 'last-child' ||
        pseudo.name === 'nth-child' || pseudo.name === 'nth-last-child' ||
        pseudo.name === 'only-child') {
        filtered = this.filterElementsByStandardChildPseudo(filtered, pseudo.name, contextHtml, argument);
        continue;
      }
      if (pseudo.name === 'first-of-type' || pseudo.name === 'last-of-type' ||
        pseudo.name === 'only-of-type' || pseudo.name === 'nth-of-type' ||
        pseudo.name === 'nth-last-of-type' || pseudo.name === 'eq' || pseudo.name === 'lt') {
        filtered = this.filterElementsByIndexPseudo(filtered, pseudo.name, argument, contextHtml);
        continue;
      }
      // Do not silently widen selectors when a Jsoup pseudo class is unknown.
      return [];
    }
    return filtered;
  }

  private filterElementsByStandardChildPseudo(
    elements: string[],
    pseudoName: string,
    contextHtml: string,
    argument: string
  ): string[] {
    if (contextHtml.length === 0) {
      return [];
    }
    if (pseudoName === 'nth-child' && argument.length === 0) {
      return [];
    }
    const occurrences = this.mapStringElementOccurrences(contextHtml, elements);
    const filtered: string[] = [];
    for (const occurrence of occurrences) {
      const siblingPosition = this.getStringElementSiblingPosition(contextHtml, occurrence);
      if (siblingPosition === null) {
        continue;
      }
      let matches = false;
      if (pseudoName === 'first-child') {
        matches = siblingPosition.siblingIndex === 0;
      } else if (pseudoName === 'last-child') {
        matches = siblingPosition.siblingIndex === siblingPosition.siblingCount - 1;
      } else if (pseudoName === 'only-child') {
        matches = siblingPosition.siblingCount === 1;
      } else if (pseudoName === 'nth-last-child') {
        matches = this.matchIndexPseudoExpression(
          siblingPosition.siblingCount - siblingPosition.siblingIndex,
          argument
        );
      } else {
        matches = this.matchIndexPseudoExpression(siblingPosition.siblingIndex + 1, argument);
      }
      if (matches) {
        filtered.push(occurrence.element);
      }
    }
    return filtered;
  }

  private filterElementsByIndexPseudo(
    elements: string[],
    pseudoName: string,
    argument: string,
    contextHtml: string
  ): string[] {
    if (contextHtml.length === 0) {
      return [];
    }
    const occurrences = this.mapStringElementOccurrences(contextHtml, elements);
    const isTypeExpression = pseudoName === 'nth-of-type' || pseudoName === 'nth-last-of-type';
    const numericArgument = isTypeExpression
      ? null
      : this.parseIndexPseudoArgument(argument);
    if (!isTypeExpression && numericArgument === null && pseudoName !== 'first-of-type' &&
      pseudoName !== 'last-of-type' && pseudoName !== 'only-of-type') {
      return [];
    }

    const filtered: string[] = [];
    for (const occurrence of occurrences) {
      const siblingPosition = this.getStringElementSiblingPosition(contextHtml, occurrence);
      if (siblingPosition === null) {
        continue;
      }
      let matches = false;
      if (pseudoName === 'eq') {
        matches = numericArgument !== null && siblingPosition.siblingIndex === numericArgument;
      } else if (pseudoName === 'lt') {
        matches = numericArgument !== null && siblingPosition.siblingIndex >= 0 &&
          siblingPosition.siblingIndex < numericArgument;
      } else if (pseudoName === 'first-of-type') {
        matches = siblingPosition.typeIndex === 1;
      } else if (pseudoName === 'last-of-type') {
        matches = siblingPosition.typeIndex > 0 && siblingPosition.typeIndex === siblingPosition.typeCount;
      } else if (pseudoName === 'only-of-type') {
        matches = siblingPosition.typeCount === 1;
      } else if (pseudoName === 'nth-last-of-type') {
        const typeIndexFromEnd = siblingPosition.typeCount - siblingPosition.typeIndex + 1;
        matches = siblingPosition.typeIndex > 0 && this.matchIndexPseudoExpression(typeIndexFromEnd, argument);
      } else {
        matches = siblingPosition.typeIndex > 0 &&
          this.matchIndexPseudoExpression(siblingPosition.typeIndex, argument);
      }
      if (matches) {
        filtered.push(occurrence.element);
      }
    }
    return filtered;
  }

  private parseIndexPseudoArgument(argument: string): number | null {
    const normalized = argument.trim();
    if (!/^\d+$/.test(normalized)) {
      return null;
    }
    const value = parseInt(normalized, 10);
    return Number.isNaN(value) ? null : value;
  }

  private matchIndexPseudoExpression(index: number, expression: string): boolean {
    const normalized = expression.replace(/\s+/g, '').toLowerCase();
    if (normalized === 'odd') {
      return index % 2 === 1;
    }
    if (normalized === 'even') {
      return index % 2 === 0;
    }
    const numberMatch = normalized.match(/^(\d+)$/);
    if (numberMatch) {
      return index === parseInt(numberMatch[1], 10);
    }
    const formulaMatch = normalized.match(/^([+-]?\d*)n([+-]?\d+)?$/);
    if (!formulaMatch) {
      return false;
    }
    const coefficientText = formulaMatch[1];
    const coefficient = coefficientText === '' || coefficientText === '+'
      ? 1
      : coefficientText === '-'
        ? -1
        : parseInt(coefficientText, 10);
    const offset = formulaMatch[2] ? parseInt(formulaMatch[2], 10) : 0;
    if (Number.isNaN(coefficient) || Number.isNaN(offset) || coefficient === 0) {
      return coefficient === 0 && index === offset;
    }
    const distance = index - offset;
    return distance * coefficient >= 0 && distance % coefficient === 0;
  }

  private mapStringElementOccurrences(contextHtml: string, elements: string[]): StringElementOccurrence[] {
    const occurrences: StringElementOccurrence[] = [];
    let searchStart = 0;
    for (const element of elements) {
      let startIndex = contextHtml.indexOf(element, searchStart);
      if (startIndex < 0) {
        startIndex = contextHtml.indexOf(element);
      }
      if (startIndex < 0) {
        continue;
      }
      occurrences.push(new StringElementOccurrence(element, startIndex, this.getTagName(element)));
      searchStart = startIndex + Math.max(1, element.length);
    }
    return occurrences;
  }

  private getStringElementSiblingPosition(
    contextHtml: string,
    occurrence: StringElementOccurrence
  ): StringElementSiblingPosition | null {
    const parentStart = this.findParentStartTag(contextHtml, occurrence.startIndex);
    if (parentStart < 0 || parentStart === occurrence.startIndex) {
      return null;
    }
    const parentTag = this.extractTagNameAt(contextHtml, parentStart);
    if (parentTag.length === 0) {
      return null;
    }
    const parentElement = this.extractElement(contextHtml, parentStart, parentTag);
    const parentOpeningEnd = this.findHtmlTagEnd(contextHtml, parentStart);
    if (parentElement === null || parentOpeningEnd < 0) {
      return null;
    }
    const relativeStart = occurrence.startIndex - parentOpeningEnd - 1;
    const children = this.findDirectChildOccurrences(this.extractInnerHtml(parentElement));
    let siblingIndex = -1;
    let typeIndex = 0;
    let sameTagCount = 0;
    let typeCount = 0;
    for (const child of children) {
      if (child.tagName === occurrence.tagName) {
        typeCount++;
      }
    }
    for (const child of children) {
      if (child.startIndex === relativeStart) {
        siblingIndex = children.indexOf(child);
        typeIndex = sameTagCount + 1;
        break;
      }
      if (child.tagName === occurrence.tagName) {
        sameTagCount++;
      }
    }
    if (siblingIndex < 0) {
      return null;
    }
    return { siblingIndex: siblingIndex, typeIndex: typeIndex, typeCount: typeCount, siblingCount: children.length };
  }

  private findDirectChildOccurrences(html: string): StringElementOccurrence[] {
    const results: StringElementOccurrence[] = [];
    let cursor = 0;
    while (cursor < html.length) {
      const scan = this.scanNextHtmlTag(html, cursor);
      if (scan === null) {
        break;
      }
      if (!scan.isSpecial && !scan.isClosing && scan.tagName.length > 0) {
        const element = this.extractElement(html, scan.startIndex, scan.tagName);
        if (element !== null) {
          results.push(new StringElementOccurrence(element, scan.startIndex, scan.tagName));
          cursor = scan.startIndex + Math.max(1, element.length);
          continue;
        }
      }
      cursor = scan.endIndex + 1;
    }
    return results;
  }

  private matchesStringHasPseudo(element: string, argument: string): boolean {
    if (argument.length === 0) {
      return false;
    }
    const innerHtml = this.extractInnerHtml(element);
    if (argument.startsWith('>')) {
      const childSelector = argument.substring(1).trim();
      if (childSelector.length === 0) {
        return false;
      }
      const directChildren = this.findDirectChildren(innerHtml);
      for (const child of directChildren) {
        const wrapper = `<legado-has-root>${child}</legado-has-root>`;
        const wrapperOpeningEnd = this.findHtmlTagEnd(wrapper, 0);
        if (wrapperOpeningEnd < 0) {
          continue;
        }
        const subjectSelector = this.extractTopLevelSelectorSubject(childSelector);
        if (!this.matchesStringSelectorAtElementStart(wrapper, subjectSelector, wrapperOpeningEnd + 1)) {
          continue;
        }
        const matches = this.findElementsBySingleSelector(wrapper, childSelector);
        // A relative :has selector may continue past the direct child, e.g.
        // `:has(>div span)`. Jsoup evaluates the whole relative selector from
        // the parent; requiring the result to equal the direct child rejects
        // valid descendant matches below that child.
        if (matches.some((match: string): boolean => match !== wrapper)) {
          return true;
        }
      }
      return false;
    }
    if (argument === '*') {
      return this.findAllElements(innerHtml).length > 0;
    }
    return this.findElementsBySingleSelector(innerHtml, argument).length > 0;
  }

  /**
   * Match Jsoup's :empty evaluator for the large-document string fallback.
   * Blank text and comments do not make an element non-empty; child elements do.
   */
  private matchesStringEmptyPseudo(element: string): boolean {
    const tagName = this.getTagName(element);
    if (tagName.length > 0 && LegadoRuleAnalyzer.SELF_CLOSING_TAGS.has(tagName)) {
      return true;
    }
    const openingEnd = this.findHtmlTagEnd(element, 0);
    if (openingEnd < 0) {
      return false;
    }
    const openingTag = element.substring(0, openingEnd + 1).trim();
    if (openingTag.endsWith('/>')) {
      return true;
    }
    const innerHtml = this.extractInnerHtml(element);
    if (innerHtml === element) {
      return false;
    }
    let cursor = 0;
    while (cursor < innerHtml.length) {
      const tagStart = innerHtml.indexOf('<', cursor);
      if (tagStart < 0) {
        return innerHtml.substring(cursor).trim().length === 0;
      }
      if (innerHtml.substring(cursor, tagStart).trim().length > 0) {
        return false;
      }
      const scan = this.scanNextHtmlTag(innerHtml, tagStart);
      if (scan === null) {
        return false;
      }
      const rawTag = innerHtml.substring(scan.startIndex, scan.endIndex + 1).trim();
      if (rawTag.startsWith('<!--') || rawTag.startsWith('<?') || /^<!doctype\b/i.test(rawTag)) {
        cursor = scan.endIndex + 1;
        continue;
      }
      return false;
    }
    return true;
  }

  private extractTopLevelSelectorSubject(selector: string): string {
    const directChildParts = this.splitTopLevelDirectChildSelectors(selector);
    let firstPart = directChildParts.length > 0 ? directChildParts[0].trim() : selector.trim();
    const siblingChain = this.splitTopLevelCssSiblingCombinatorSelector(firstPart);
    if (siblingChain !== null && siblingChain.parts.length > 0) {
      firstPart = siblingChain.parts[0].trim();
    }
    const descendantParts = this.splitTopLevelCssDescendantSelector(firstPart);
    if (descendantParts.length > 0) {
      return descendantParts[0].trim();
    }
    return firstPart;
  }

  private matchesStringSelectorAtElementStart(
    html: string,
    selector: string,
    expectedStart: number
  ): boolean {
    if (selector.length === 0 || expectedStart < 0) {
      return false;
    }
    const matches = this.findElementsBySingleSelector(html, selector, html);
    const occurrences = this.mapStringElementOccurrences(html, matches);
    return occurrences.some((occurrence: StringElementOccurrence): boolean => occurrence.startIndex === expectedStart);
  }

  private collectNestedSelectorMatchOffsets(contextHtml: string, selector: string): Set<number> {
    const matchedOffsets = new Set<number>();
    const selectorGroups = this.splitTopLevelCssSelectorGroups(selector);
    for (const selectorGroup of selectorGroups) {
      const matches = this.findElementsBySingleSelector(contextHtml, selectorGroup, contextHtml);
      const occurrences = this.mapStringElementOccurrences(contextHtml, matches);
      for (const occurrence of occurrences) {
        matchedOffsets.add(occurrence.startIndex);
      }
    }
    return matchedOffsets;
  }

  private matchesStringNestedSelector(
    element: string,
    selector: string,
    contextHtml: string
  ): boolean {
    const normalizedSelector = selector.trim();
    if (normalizedSelector.length === 0) {
      return false;
    }
    const occurrences = this.mapStringElementOccurrences(contextHtml, [element]);
    if (occurrences.length === 0) {
      return this.matchesStringNestedSelectorWithoutContext(element, normalizedSelector);
    }
    const target = occurrences[0];
    const parentStart = this.findParentStartTag(contextHtml, target.startIndex);
    if (parentStart < 0 || parentStart === target.startIndex) {
      return this.matchesStringNestedSelectorWithoutContext(element, normalizedSelector);
    }
    return this.matchesStringNestedSelectorAtOccurrence(element, normalizedSelector, contextHtml, target.startIndex);
  }

  private matchesStringNestedSelectorAtOccurrence(
    element: string,
    selector: string,
    contextHtml: string,
    candidateStartIndex: number
  ): boolean {
    const normalizedSelector = selector.trim();
    if (normalizedSelector.length === 0) {
      return false;
    }
    if (contextHtml.length === 0 || candidateStartIndex < 0) {
      return this.matchesStringNestedSelectorWithoutContext(element, normalizedSelector);
    }
    const parentStart = this.findParentStartTag(contextHtml, candidateStartIndex);
    if (parentStart < 0 || parentStart === candidateStartIndex) {
      return this.matchesStringNestedSelectorWithoutContext(element, normalizedSelector);
    }
    const wrapper = `<legado-not-root>${contextHtml}</legado-not-root>`;
    const matches = this.findElementsBySingleSelector(wrapper, normalizedSelector, wrapper);
    const matchedOccurrences = this.mapStringElementOccurrences(wrapper, matches);
    const wrapperOpeningEnd = this.findHtmlTagEnd(wrapper, 0);
    if (wrapperOpeningEnd < 0) {
      return false;
    }
    const targetRelativeStart = wrapperOpeningEnd + 1 + candidateStartIndex;
    for (const match of matchedOccurrences) {
      if (match.startIndex === targetRelativeStart) {
        return true;
      }
    }
    return false;
  }

  private matchesStringNestedSelectorWithoutContext(element: string, selector: string): boolean {
    const wrapper = `<legado-not-root>${element}</legado-not-root>`;
    const matches = this.findElementsBySingleSelector(wrapper, selector);
    return matches.some((match: string): boolean => match === element);
  }

  private normalizeLegadoPseudoArgument(argument: string): string {
    const trimmed = argument.trim();
    if (trimmed.length >= 2) {
      const first = trimmed[0];
      const last = trimmed[trimmed.length - 1];
      if ((first === '"' || first === "'") && first === last) {
        return trimmed.substring(1, trimmed.length - 1);
      }
    }
    return trimmed;
  }

  private parseLegadoRegexPrefix(pattern: string): LegadoRegexPrefix {
    const prefix = pattern.match(/^\(\?([imsu-]+)\)/);
    if (!prefix) {
      return { pattern: pattern, flags: '' };
    }
    let flags = '';
    for (const flag of prefix[1]) {
      if ((flag === 'i' || flag === 'm' || flag === 's' || flag === 'u') && !flags.includes(flag)) {
        flags += flag;
      }
    }
    return { pattern: pattern.substring(prefix[0].length), flags: flags };
  }

  private parseLegadoAttributeSelectorAt(selector: string, openIndex: number): LegadoAttributeSelectorParseResult | null {
    let cursor = openIndex + 1;
    const nameStart = cursor;
    while (cursor < selector.length && /[A-Za-z0-9_:-]/.test(selector[cursor])) {
      cursor++;
    }
    const name = selector.substring(nameStart, cursor).trim();
    if (name.length === 0) {
      return null;
    }
    while (cursor < selector.length && /\s/.test(selector[cursor])) {
      cursor++;
    }

    let operator = '';
    if (cursor < selector.length && '=~$*^|'.includes(selector[cursor])) {
      const operatorStart = selector[cursor];
      cursor++;
      if (operatorStart === '=') {
        operator = '=';
      } else if (cursor < selector.length && selector[cursor] === '=') {
        operator = `${operatorStart}=`;
        cursor++;
      } else {
        return null;
      }
    }
    while (cursor < selector.length && /\s/.test(selector[cursor])) {
      cursor++;
    }

    let value = '';
    if (cursor < selector.length && selector[cursor] !== ']') {
      const quote = selector[cursor];
      if (quote === '"' || quote === "'") {
        cursor++;
        while (cursor < selector.length && selector[cursor] !== quote) {
          if (selector[cursor] === '\\' && cursor + 1 < selector.length) {
            value += selector[cursor];
            cursor++;
          }
          value += selector[cursor];
          cursor++;
        }
        if (cursor < selector.length && selector[cursor] === quote) {
          cursor++;
        }
      } else if (operator === '~=') {
        let regexClassDepth = 0;
        while (cursor < selector.length) {
          const current = selector[cursor];
          if (current === '\\' && cursor + 1 < selector.length) {
            value += current;
            cursor++;
            value += selector[cursor];
            cursor++;
            continue;
          }
          if (current === '[') {
            regexClassDepth++;
            value += current;
            cursor++;
            continue;
          }
          if (current === ']' && regexClassDepth > 0) {
            regexClassDepth--;
            value += current;
            cursor++;
            continue;
          }
          if (current === ']' && regexClassDepth === 0) {
            break;
          }
          value += current;
          cursor++;
        }
      } else {
        const valueStart = cursor;
        while (cursor < selector.length && selector[cursor] !== ']') {
          cursor++;
        }
        value = selector.substring(valueStart, cursor).trim();
      }
    }
    while (cursor < selector.length && /\s/.test(selector[cursor])) {
      cursor++;
    }
    if (cursor >= selector.length || selector[cursor] !== ']') {
      return null;
    }
    const attributeSelector: LegadoAttributeSelector = {
      name: name.toLowerCase(),
      operator: operator,
      value: value.trim()
    };
    return {
      selector: attributeSelector,
      endIndex: cursor + 1
    };
  }

  private matchesLegadoAttributeSelector(actualValue: string, selector: LegadoAttributeSelector): boolean {
    if (selector.operator.length === 0) {
      return true;
    }
    switch (selector.operator) {
      case '=':
        return actualValue === selector.value;
      case '^=':
        return actualValue.startsWith(selector.value);
      case '$=':
        return actualValue.endsWith(selector.value);
      case '*=':
        return actualValue.includes(selector.value);
      case '|=':
        return actualValue === selector.value || actualValue.startsWith(`${selector.value}-`);
      case '~=':
        try {
          const regexParts = this.parseLegadoRegexPrefix(selector.value);
          return new RegExp(regexParts.pattern, regexParts.flags).test(actualValue);
        } catch (error) {
          logger.warn(TAG, `Legado ~= 正则无效: ${selector.value}`);
          return false;
        }
      default:
        return false;
    }
  }

  /**
   * CSS child combinators must not be treated as descendant-selector tokens.
   * The string fallback is used for large documents, where that distinction is
   * essential to avoid expanding a narrow table row selector to the page.
   */
  private splitTopLevelCssSiblingCombinatorSelector(selector: string): StringCssCombinatorChain | null {
    const parts: string[] = [];
    const combinators: string[] = [];
    let current = '';
    let parenthesisDepth = 0;
    let bracketDepth = 0;
    let quote = '';
    let escaped = false;
    let hasSiblingCombinator = false;
    for (let index = 0; index < selector.length; index++) {
      const character = selector[index];
      if (escaped) {
        current += character;
        escaped = false;
        continue;
      }
      if (character === '\\') {
        current += character;
        escaped = true;
        continue;
      }
      if (quote.length > 0) {
        current += character;
        if (character === quote) {
          quote = '';
        }
        continue;
      }
      if (character === '"' || character === "'") {
        quote = character;
        current += character;
        continue;
      }
      if (character === '(' && bracketDepth === 0) {
        parenthesisDepth++;
        current += character;
        continue;
      }
      if (character === ')' && parenthesisDepth > 0 && bracketDepth === 0) {
        parenthesisDepth--;
        current += character;
        continue;
      }
      if (character === '[') {
        bracketDepth++;
        current += character;
        continue;
      }
      if (character === ']' && bracketDepth > 0) {
        bracketDepth--;
        current += character;
        continue;
      }
      if (parenthesisDepth === 0 && bracketDepth === 0 &&
        (character === '>' || character === '+' || character === '~')) {
        const part = current.trim();
        if (part.length === 0) {
          return null;
        }
        parts.push(part);
        combinators.push(character);
        hasSiblingCombinator = hasSiblingCombinator || character === '+' || character === '~';
        current = '';
        continue;
      }
      current += character;
    }
    const lastPart = current.trim();
    if (!hasSiblingCombinator || lastPart.length === 0) {
      return null;
    }
    parts.push(lastPart);
    if (parts.length !== combinators.length + 1) {
      return null;
    }
    return { parts: parts, combinators: combinators };
  }

  private findElementsByCssCombinatorChain(
    html: string,
    chain: StringCssCombinatorChain,
    selectorContextHtml: string
  ): string[] {
    const effectiveContextHtml = selectorContextHtml.length > 0 ? selectorContextHtml : html;
    if (chain.parts.length < 2 || chain.combinators.length !== chain.parts.length - 1) {
      return [];
    }
    const firstMatches = this.findElementsBySingleSelector(html, chain.parts[0], effectiveContextHtml);
    let currentOccurrences = this.mapStringElementOccurrences(effectiveContextHtml, firstMatches);
    if (currentOccurrences.length !== firstMatches.length) {
      return [];
    }
    for (let partIndex = 1; partIndex < chain.parts.length; partIndex++) {
      const candidateMatches = this.findElementsBySingleSelector(
        effectiveContextHtml,
        chain.parts[partIndex],
        effectiveContextHtml
      );
      const candidateOccurrences = this.mapStringElementOccurrences(effectiveContextHtml, candidateMatches);
      if (candidateOccurrences.length !== candidateMatches.length) {
        return [];
      }
      const nextOccurrences: StringElementOccurrence[] = [];
      const seenOffsets = new Set<number>();
      const combinator = chain.combinators[partIndex - 1];
      for (const candidate of candidateOccurrences) {
        for (const previous of currentOccurrences) {
          if (this.matchesStringCombinatorRelation(effectiveContextHtml, previous, candidate, combinator)) {
            if (!seenOffsets.has(candidate.startIndex)) {
              seenOffsets.add(candidate.startIndex);
              nextOccurrences.push(candidate);
            }
            break;
          }
        }
      }
      currentOccurrences = nextOccurrences;
      if (currentOccurrences.length === 0) {
        return [];
      }
    }
    return currentOccurrences.map((occurrence: StringElementOccurrence): string => occurrence.element);
  }

  private matchesStringCombinatorRelation(
    contextHtml: string,
    previous: StringElementOccurrence,
    candidate: StringElementOccurrence,
    combinator: string
  ): boolean {
    const candidateParentStart = this.findParentStartTag(contextHtml, candidate.startIndex);
    if (candidateParentStart < 0) {
      return false;
    }
    if (combinator === '>') {
      return candidateParentStart === previous.startIndex;
    }
    const previousParentStart = this.findParentStartTag(contextHtml, previous.startIndex);
    if (previousParentStart < 0 || previousParentStart !== candidateParentStart) {
      return false;
    }
    const previousPosition = this.getStringElementSiblingPosition(contextHtml, previous);
    const candidatePosition = this.getStringElementSiblingPosition(contextHtml, candidate);
    if (previousPosition === null || candidatePosition === null) {
      return false;
    }
    if (combinator === '+') {
      return candidatePosition.siblingIndex === previousPosition.siblingIndex + 1;
    }
    if (combinator === '~') {
      return candidatePosition.siblingIndex > previousPosition.siblingIndex;
    }
    return false;
  }

  private splitTopLevelDirectChildSelectors(selector: string): string[] {
    const parts: string[] = [];
    let current = '';
    let parenthesisDepth = 0;
    let bracketDepth = 0;
    let quote = '';
    let escaped = false;
    for (let index = 0; index < selector.length; index++) {
      const character = selector[index];
      if (escaped) {
        current += character;
        escaped = false;
        continue;
      }
      if (character === '\\') {
        current += character;
        escaped = true;
        continue;
      }
      if (quote.length > 0) {
        current += character;
        if (character === quote) {
          quote = '';
        }
        continue;
      }
      if (character === '"' || character === "'") {
        quote = character;
        current += character;
        continue;
      }
      if (character === '(' && bracketDepth === 0) {
        parenthesisDepth++;
      } else if (character === ')' && parenthesisDepth > 0 && bracketDepth === 0) {
        parenthesisDepth--;
      } else if (character === '[') {
        bracketDepth++;
      } else if (character === ']' && bracketDepth > 0) {
        bracketDepth--;
      }
      if (character === '>' && parenthesisDepth === 0 && bracketDepth === 0) {
        parts.push(current.trim());
        current = '';
      } else {
        current += character;
      }
    }
    parts.push(current.trim());
    return parts;
  }
  private findElementsByDirectChildSelector(
    html: string,
    selector: string,
    selectorContextHtml: string = ''
  ): string[] {
    const effectiveContextHtml = selectorContextHtml.length > 0 ? selectorContextHtml : html;
    const parts = this.splitTopLevelDirectChildSelectors(selector);
    if (parts.length < 2) {
      return this.findElementsBySimpleSelector(html, selector, effectiveContextHtml);
    }
    const firstSelector = parts[0].trim();
    if (firstSelector.length === 0) {
      return [];
    }
    // The segment before a top-level `>` may itself contain descendant or
    // sibling combinators and pseudo classes.  Jsoup evaluates that complete
    // left-hand selector before applying the direct-child relation; routing it
    // through the simple-selector parser silently drops all but its first
    // token (for example `.book_list2 .col-md-3:nth-child(n+1) > a`).
    let currentElements = this.findElementsBySingleSelector(html, firstSelector, effectiveContextHtml);
    for (let i = 1; i < parts.length; i++) {
      const childSelector = parts[i].trim();
      if (childSelector.length === 0) {
        return [];
      }
      const nextElements: string[] = [];
      for (let parentIndex = 0; parentIndex < currentElements.length; parentIndex++) {
        const parentElement = currentElements[parentIndex];
        const innerHtml = this.extractInnerHtml(parentElement);
        const directChildOccurrences = this.findDirectChildOccurrences(innerHtml);
        const directChildren = directChildOccurrences.map((occurrence: StringElementOccurrence): string => occurrence.element);
        // Browsers insert a tbody node for rows written directly under a table.
        // The string fallback represents that implicit node with its table parent.
        const hasExplicitTbody = directChildren.some((child: string): boolean => this.getTagName(child) === 'tbody');
        if (childSelector.toLowerCase() === 'tbody' && this.getTagName(parentElement) === 'table' && !hasExplicitTbody) {
          nextElements.push(parentElement);
          continue;
        }
        if (directChildOccurrences.length === 0) {
          continue;
        }
        // Standard child pseudos need the complete sibling context.  Evaluate
        // the selector against a synthetic parent and retain matches by their
        // occurrence offset, so identical sibling HTML remains distinguishable.
        const scopedParent = `<legado-direct-parent>${innerHtml}</legado-direct-parent>`;
        // The right operand may contain its own descendant chain, such as
        // `div:nth-child(4) span:first-child`.  Route it through the full
        // selector dispatcher so each segment keeps its own pseudo context;
        // the simple-selector path would apply every pseudo to the final
        // element and lose the ancestor constraint.
        const matches = this.findElementsBySingleSelector(scopedParent, childSelector, effectiveContextHtml);
        const matchedOccurrences = this.mapStringElementOccurrences(scopedParent, matches);
        const scopedParentOpeningEnd = this.findHtmlTagEnd(scopedParent, 0);
        if (scopedParentOpeningEnd < 0) {
          continue;
        }
        const childSelectorParts = this.splitTopLevelCssDescendantSelector(childSelector);
        if (childSelectorParts.length <= 1) {
          const matchedRelativeStarts = new Set<number>();
          for (const occurrence of matchedOccurrences) {
            const relativeStart = occurrence.startIndex - scopedParentOpeningEnd - 1;
            matchedRelativeStarts.add(relativeStart);
          }
          for (const childOccurrence of directChildOccurrences) {
            if (matchedRelativeStarts.has(childOccurrence.startIndex)) {
              nextElements.push(childOccurrence.element);
            }
          }
        } else {
          // For `parent > direct-child descendant`, the result belongs below
          // a qualifying direct child.  Verify the first selector segment at
          // each direct-child offset, then keep descendant matches whose
          // nearest direct-child ancestor is one of those offsets.
          const firstSelector = childSelectorParts[0];
          const firstMatches = this.findElementsBySingleSelector(
            scopedParent,
            firstSelector,
            effectiveContextHtml
          );
          const firstOccurrences = this.mapStringElementOccurrences(scopedParent, firstMatches);
          const qualifyingDirectStarts = new Set<number>();
          for (const firstOccurrence of firstOccurrences) {
            for (const childOccurrence of directChildOccurrences) {
              if (firstOccurrence.startIndex === childOccurrence.startIndex) {
                qualifyingDirectStarts.add(childOccurrence.startIndex);
                break;
              }
            }
          }
          for (const occurrence of matchedOccurrences) {
            let ownerStart = -1;
            for (const childOccurrence of directChildOccurrences) {
              const childEnd = childOccurrence.startIndex + childOccurrence.element.length;
              if (occurrence.startIndex >= childOccurrence.startIndex && occurrence.startIndex < childEnd) {
                ownerStart = childOccurrence.startIndex;
                break;
              }
            }
            if (ownerStart >= 0 && qualifyingDirectStarts.has(ownerStart)) {
              nextElements.push(occurrence.element);
            }
          }
        }
      }
      currentElements = nextElements;
      if (currentElements.length === 0) {
        break;
      }
    }
    // Keep occurrence markers until the outer CSS chain has completed. The
    // chain owns the marker state; this helper must not read an outer local.
    return currentElements;
  }

  private getElementsByRegex(pattern: string): string[] {
    const results: string[] = [];
    if (!pattern || pattern.trim().length <= 0) {
      return results;
    }
    try {
      const patterns = pattern.split('&&').map((p: string): string => p.trim()).filter((p: string): boolean => p.length > 0);
      if (patterns.length <= 0) {
        return results;
      }

      let sourceText = this.content;
      for (let i = 0; i < patterns.length - 1; i++) {
        const regex = new RegExp(patterns[i], 'gs');
        let match = regex.exec(sourceText);
        let merged = '';
        while (match !== null) {
          merged += match[0];
          match = regex.exec(sourceText);
        }
        if (merged.length <= 0) {
          return results;
        }
        sourceText = merged;
      }

      const finalRegex = new RegExp(patterns[patterns.length - 1], 'gs');
      let finalMatch = finalRegex.exec(sourceText);
      while (finalMatch !== null) {
        const groups: string[] = [];
        for (let i = 0; i < finalMatch.length && i <= 99; i++) {
          groups.push(finalMatch[i] !== undefined ? finalMatch[i] : '');
        }
        const payload: RegexGroupPayload = {
          __legadoRegexGroups: groups,
          __legadoRegexText: finalMatch[0] || ''
        };
        results.push(JSON.stringify(payload));
        finalMatch = finalRegex.exec(sourceText);
      }
    } catch (e) {
      logger.warn(TAG, `正则元素匹配失败: ${pattern}, 错误=${String(e)}`);
    }
    return results;
  }

  private getStringFromRegexGroupPayload(ruleStr: string): string | null {
    const payload = this.parseRegexGroupPayload(this.content);
    if (payload === null) {
      return null;
    }

    const trimmedRule = ruleStr.trim();
    if (trimmedRule.length <= 0 || trimmedRule === 'text' || trimmedRule === 'all') {
      return payload.__legadoRegexText;
    }

    if (/\$\d{1,2}/.test(trimmedRule)) {
      return trimmedRule.replace(/\$(\d{1,2})/g, (token: string, groupIndexText: string): string => {
        const groupIndex = Number(groupIndexText);
        if (Number.isNaN(groupIndex) || groupIndex < 0 || groupIndex >= payload.__legadoRegexGroups.length) {
          return '';
        }
        return payload.__legadoRegexGroups[groupIndex] || '';
      });
    }

    if (/^\d{1,2}$/.test(trimmedRule)) {
      const groupIndex = Number(trimmedRule);
      if (!Number.isNaN(groupIndex) && groupIndex >= 0 && groupIndex < payload.__legadoRegexGroups.length) {
        return payload.__legadoRegexGroups[groupIndex] || '';
      }
    }

    if (this.shouldParseRegexPayloadTextWithRule(trimmedRule)) {
      return this.getStringSingleInternalWithContent(trimmedRule, payload.__legadoRegexText);
    }

    return null;
  }

  private shouldParseRegexPayloadTextWithRule(rule: string): boolean {
    if (rule.length <= 0) {
      return false;
    }
    if (rule.includes('<js>') || rule.toLowerCase().includes('@js:')) {
      return false;
    }
    return this.looksLikeRuleExpression(rule) ||
      rule.includes('@') ||
      rule.startsWith('class.') ||
      rule.startsWith('id.') ||
      rule.startsWith('tag.') ||
      rule.startsWith('text.') ||
      /^[a-zA-Z][a-zA-Z0-9_-]*(?:[.#].*)?$/.test(rule);
  }

  private parseRegexGroupPayload(content: string): RegexGroupPayload | null {
    if (!content || content.indexOf(REGEX_GROUP_PAYLOAD_KEY) < 0) {
      return null;
    }
    try {
      const parsed = SafeUtils.parseObj(content) as RegexGroupPayload;
      if (!parsed || !Array.isArray(parsed.__legadoRegexGroups)) {
        return null;
      }
      const groups: string[] = [];
      for (let i = 0; i < parsed.__legadoRegexGroups.length; i++) {
        groups.push(String(parsed.__legadoRegexGroups[i] || ''));
      }
      const payload: RegexGroupPayload = {
        __legadoRegexGroups: groups,
        __legadoRegexText: String(parsed.__legadoRegexText || groups[0] || '')
      };
      return payload;
    } catch (_error) {
      return null;
    }
  }

  // ==================== JS执行 ====================

  /**
   * 执行JavaScript代码（同步版本）
   * 注意：此方法在同步上下文中调用异步的JSVM执行
   * 由于ArkTS不支持同步等待，这里使用Promise.then处理
   * 实际使用时应优先调用evalJSAsync
   */
  private evalJS(code: string): string {
    // 在同步上下文中，我们无法等待异步结果
    // 记录日志并返回空字符串，调用方应使用异步版本
    if (LegadoRuleAnalyzer.ENABLE_SELECTOR_TRACE) {
      logger.debug(TAG, `JS执行(同步): ${code.substring(0, 50)}... - 建议使用异步版本`);
    }
    
    // 启动异步执行但不等待结果（用于预热）
    const jsEngine = getLegadoJsEngine();
    const context: JsContext = this.createJsContext(this.content, this.content);
    
    // 异步执行，结果会被丢弃（同步上下文无法等待）
    jsEngine.execute(code, context).then((result) => {
      this.recordBridgeTraces(result.bridgeTraces);
      this.syncVariablesFromRecord(result.variables);
      this.syncSourceEffects(result.sourceEffects);
      if (result.success && result.result) {
        if (LegadoRuleAnalyzer.ENABLE_SELECTOR_TRACE) {
          logger.debug(TAG, `JS异步执行完成: ${result.result.substring(0, 50)}...`);
        }
      }
    }).catch((e: Error) => {
      logger.warn(TAG, `JS异步执行失败: ${String(e)}`);
    });
    
    return '';
  }
  
  /**
   * 执行JavaScript代码（异步版本）
   */
  async evalJSAsync(code: string): Promise<string> {
    const jsEngine = getLegadoJsEngine();
    const context: JsContext = this.createJsContext(this.content, this.content);
    
    const result = await jsEngine.execute(code, context);
    this.recordBridgeTraces(result.bridgeTraces);
    this.syncVariablesFromRecord(result.variables);
    this.syncSourceEffects(result.sourceEffects);
    if (result.success) {
      this.lastJsExecutionStatus = result.result.length > 0 ? 'result' : 'empty';
      return result.result;
    } else {
      this.lastJsExecutionStatus = this.toSafeJsExecutionStatus(result.error);
      logger.warn(TAG, `JS执行失败: ${result.error}`);
      return '';
    }
  }

  private toSafeJsExecutionStatus(error: string | undefined): string {
    const value = error || '';
    const supportedCodes: string[] = [
      'SCRIPT_SYNTAX',
      'PENDING_BRIDGE_TIMEOUT',
      'HTTP_FAILED',
      'RULE_PARSE_FAILED',
      'UNRESOLVED_RULE_TOKEN',
      'WEBVIEW_NOT_READY',
      'RUNTIME_ERROR'
    ];
    for (let index = 0; index < supportedCodes.length; index++) {
      if (value.includes(supportedCodes[index])) {
        return `error_${supportedCodes[index].toLowerCase()}`;
      }
    }
    return 'error_other';
  }
  
  /**
   * 获取变量对象
   */
  private getVariablesObject(): Record<string, string> {
    const obj: Record<string, string> = {};
    this.variables.forEach((value: string, key: string): void => {
      obj[key] = value;
    });
    return obj;
  }

  private syncVariablesFromRecord(variables?: Record<string, string>): void {
    if (!variables) {
      return;
    }
    const keys = Object.keys(variables);
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i];
      const value = variables[key];
      if (key && key.length > 0 && value !== undefined && value !== null) {
        this.variables.set(key, String(value));
      }
    }
  }

  private syncSourceEffects(effects?: LegadoJsSourceEffects): void {
    if (!effects) {
      return;
    }
    if (effects.loginInfo !== undefined && effects.loginInfo !== null) {
      this.sourceEffects.loginInfo = String(effects.loginInfo);
    }
    if (effects.loginHeader !== undefined && effects.loginHeader !== null) {
      this.sourceEffects.loginHeader = String(effects.loginHeader);
    }
    if (effects.sourceVariable !== undefined && effects.sourceVariable !== null) {
      this.sourceEffects.sourceVariable = String(effects.sourceVariable);
      this.variables.set('__sourceVariable', this.sourceEffects.sourceVariable);
    }
    if (effects.removeLoginHeader === true) {
      this.sourceEffects.removeLoginHeader = true;
      this.variables.set('__loginHeader', '');
    }
    if (effects.data && effects.data.length > 0) {
      const existing: LegadoJsSourceDataChange[] = this.sourceEffects.data ? this.sourceEffects.data : [];
      for (let i = 0; i < effects.data.length; i++) {
        const item = effects.data[i];
        if (!item) {
          continue;
        }
        const key = String(item.key || '').trim();
        if (key.length <= 0) {
          continue;
        }
        existing.push({
          key: key,
          value: String(item.value || '')
        });
        this.variables.set(key, String(item.value || ''));
      }
      if (existing.length > 0) {
        this.sourceEffects.data = existing;
        this.variables.set('__sourceData', this.mergeSourceDataVariable(existing));
      }
    }
  }

  private mergeSourceDataVariable(changes: LegadoJsSourceDataChange[]): string {
    const merged: Record<string, string> = {};
    const raw = this.variables.get('__sourceData') || '';
    if (raw.length > 0) {
      try {
        const parsed = SafeUtils.parseObj(raw) as Record<string, string>;
        const keys = Object.keys(parsed);
        for (let i = 0; i < keys.length; i++) {
          merged[keys[i]] = String(parsed[keys[i]]);
        }
      } catch (_error) {
      }
    }
    for (let i = 0; i < changes.length; i++) {
      const item = changes[i];
      merged[item.key] = item.value;
    }
    return JSON.stringify(merged);
  }

  // ==================== 工具方法 ====================

  private splitReplaceRule(ruleText: string): RuleReplaceParts {
    const result: RuleReplaceParts = {
      rule: ruleText,
      replaceFirst: false
    };
    const firstSep = ruleText.indexOf('##');
    if (firstSep < 0) {
      return result;
    }

    result.rule = ruleText.substring(0, firstSep).trim();
    const rest = ruleText.substring(firstSep + 2);
    const secondSep = rest.indexOf('##');
    if (secondSep < 0) {
      result.replaceRegex = rest;
      return result;
    }

    result.replaceRegex = rest.substring(0, secondSep);
    let replacement = rest.substring(secondSep + 2);
    if (replacement.endsWith('##')) {
      result.replaceFirst = true;
      replacement = replacement.substring(0, replacement.length - 2);
    }
    result.replacement = replacement;
    return result;
  }

  /**
   * In an object-valued JSON rule context, original Legado accepts a bare
   * `@put:{key:field}` value as a property lookup on the current JSON item.
   * It is not a CSS attribute selector. Explicit rule syntaxes retain their
   * own evaluator, which keeps HTML and mixed-mode rules unchanged.
   */
  private async getPutRuleValueAsync(rule: string): Promise<string> {
    const normalizedRule = rule.trim();
    if (this.isImplicitJsonPutPath(normalizedRule)) {
      return this.getStringByJsonPath(`$.${normalizedRule}`);
    }
    return await this.getStringAsync(rule);
  }

  private getPutRuleValue(rule: string): string {
    const normalizedRule = rule.trim();
    if (this.isImplicitJsonPutPath(normalizedRule)) {
      return this.getStringByJsonPath(`$.${normalizedRule}`);
    }
    return this.getString(rule);
  }

  private isImplicitJsonPutPath(rule: string): boolean {
    if (!this.isJSON || rule.length <= 0) {
      return false;
    }
    return /^[A-Za-z_$][A-Za-z0-9_$-]*(?:\.[A-Za-z_$][A-Za-z0-9_$-]*)*$/.test(rule);
  }

  /**
   * 应用替换规则
   * 支持$1, $2等正则捕获组引用
   */
  private applyReplace(input: string, pattern: string, replacement: string, first: boolean): string {
    try {
      const regex = new RegExp(pattern, first ? '' : 'g');
      if (first) {
        const firstMatch = input.match(regex);
        if (!firstMatch || firstMatch.length <= 0) {
          return '';
        }
        return firstMatch[0].replace(regex, (...args: string[]): string => {
          return this.applyRegexReplacementArgs(replacement, args);
        });
      }
      
      // 使用函数替换以支持$1, $2等捕获组
      return input.replace(regex, (...args: string[]): string => {
        return this.applyRegexReplacementArgs(replacement, args);
      });
    } catch (e) {
      logger.warn(TAG, `替换规则执行失败: ${pattern}`);
      return input.replace(pattern, replacement);
    }
  }

  private applyReplaceToString(input: string, parts: RuleReplaceParts): string {
    if (!parts.replaceRegex) {
      return input;
    }
    return this.applyReplace(input, parts.replaceRegex, parts.replacement || '', parts.replaceFirst);
  }

  private applyReplaceToList(values: string[], parts: RuleReplaceParts): string[] {
    if (!parts.replaceRegex) {
      return values;
    }
    return values.map((value: string): string => {
      return this.applyReplace(value, parts.replaceRegex as string, parts.replacement || '', parts.replaceFirst);
    });
  }

  private applyRegexReplacementArgs(replacement: string, args: string[]): string {
    // args: [match, group1, group2, ..., offset, string]
    return replacement.replace(/\$(\d{1,2})/g, (token: string, groupIndexText: string): string => {
      const groupIndex = Number(groupIndexText);
      if (Number.isNaN(groupIndex) || groupIndex < 0 || groupIndex > 99) {
        return token;
      }
      if (groupIndex < args.length - 2) {
        const groupValue = args[groupIndex];
        return groupValue !== undefined ? groupValue : '';
      }
      return '';
    });
  }

  /**
   * 获取变量值
   */
  get(key: string): string {
    return this.variables.get(key) || '';
  }

  /**
   * 设置变量值
   */
  put(key: string, value: string): void {
    this.variables.set(key, value);
  }

  /**
   * 获取变量快照
   */
  getVariablesSnapshot(): Record<string, string> {
    const snapshot: Record<string, string> = {};
    this.variables.forEach((value: string, key: string): void => {
      snapshot[key] = value;
    });
    return snapshot;
  }

  getSourceEffectsSnapshot(): LegadoJsSourceEffects {
    const snapshot: LegadoJsSourceEffects = {};
    if (this.sourceEffects.loginInfo !== undefined) {
      snapshot.loginInfo = this.sourceEffects.loginInfo;
    }
    if (this.sourceEffects.loginHeader !== undefined) {
      snapshot.loginHeader = this.sourceEffects.loginHeader;
    }
    if (this.sourceEffects.sourceVariable !== undefined) {
      snapshot.sourceVariable = this.sourceEffects.sourceVariable;
    }
    if (this.sourceEffects.removeLoginHeader === true) {
      snapshot.removeLoginHeader = true;
    }
    if (this.sourceEffects.data && this.sourceEffects.data.length > 0) {
      const changes: LegadoJsSourceDataChange[] = [];
      for (let i = 0; i < this.sourceEffects.data.length; i++) {
        const item = this.sourceEffects.data[i];
        changes.push({
          key: item.key,
          value: item.value
        });
      }
      snapshot.data = changes;
    }
    return snapshot;
  }

  clearSourceEffects(): void {
    this.sourceEffects = {};
  }

  /**
   * 清除变量
   */
  clearVariables(): void {
    this.variables.clear();
    this.sourceEffects = {};
  }
}
