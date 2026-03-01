/**
 * Legado规则解析引擎
 * 支持多种解析模式：Default(CSS)、XPath、JSONPath、Regex、JS
 * 
 * 文件路径: entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets
 * 职责: 解析Legado书源规则，从HTML/JSON内容中提取数据
 */

import { logger } from '../../Utils/Logger';
import { LegadoRuleMode, LegadoParsedRule } from './LegadoSourceTypes';
import { getLegadoJsEngine, JsContext } from './LegadoJsEngine';
import { LegadoHtmlBridge, createLegadoHtmlBridge, HTMLElement as HtmlElement } from '../../libs/htmlparser';

const TAG = 'LegadoRuleAnalyzer';

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

/**
 * 索引范围接口
 */
interface IndexRange {
  start: number;
  end: number;
  step: number;
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
}

/**
 * 规则分割结果接口
 */
interface RuleSplitResult {
  rules: string[];
  splitType: string;
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
    
    while (this.pos < this.queue.length) {
      const c = this.queue[this.pos];
      
      // 检查是否是<js>块开始
      if (c === '<' && this.queue.substring(this.pos, this.pos + 4).toLowerCase() === '<js>') {
        // 跳过整个<js>...</js>块
        this.skipJsBlock();
        continue;
      }
      
      if (c === '@') {
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
      } else if (c === '[') {
        // 跳过方括号内容
        this.skipBalanced('[', ']');
      } else if (c === '(') {
        // 跳过圆括号内容
        this.skipBalanced('(', ')');
      } else if (c === '"' || c === "'") {
        // 跳过引号内容
        this.skipQuoted(c);
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
export class LegadoRuleAnalyzer {
  // Hot-path selector tracing is disabled by default to prevent UI thread stalls.
  private static readonly ENABLE_SELECTOR_TRACE: boolean = false;
  private content: string = '';
  private baseUrl: string = '';
  private isJSON: boolean = false;
  private variables: Map<string, string> = new Map();
  private htmlBridge: LegadoHtmlBridge | null = null;

  constructor() {}

  private selectorTrace(messageBuilder: () => string): void {
    if (!LegadoRuleAnalyzer.ENABLE_SELECTOR_TRACE) {
      return;
    }
    logger.debug(TAG, messageBuilder());
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

    let rule = ruleStr.trim();
    let mode = LegadoRuleMode.Default;
    const putMap: Record<string, string> = {};

    // 处理@put规则
    // Legado的@put格式是 @put:{key:value,key2:value2}，不是标准JSON
    const putPattern = /@put:\{([^}]+)\}/gi;
    let putMatch = putPattern.exec(rule);
    while (putMatch !== null) {
      rule = rule.replace(putMatch[0], '');
      try {
        // 尝试标准JSON解析
        const putJson = JSON.parse(`{${putMatch[1]}}`) as Record<string, string>;
        Object.keys(putJson).forEach(key => {
          putMap[key] = putJson[key];
        });
      } catch (e) {
        // [修复] 如果JSON解析失败，尝试解析Legado的key:value格式
        // 格式: id:id,name:name,author:author
        try {
          const pairs = putMatch[1].split(',');
          for (const pair of pairs) {
            const colonIndex = pair.indexOf(':');
            if (colonIndex > 0) {
              const key = pair.substring(0, colonIndex).trim();
              const value = pair.substring(colonIndex + 1).trim();
              if (key && value) {
                putMap[key] = value;
              }
            }
          }
        } catch (e2) {
          logger.warn(TAG, `解析@put规则失败: ${putMatch[1]}`);
        }
      }
      putMatch = putPattern.exec(rule);
    }

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
    } else if (this.isJSON && /^[a-zA-Z_][a-zA-Z0-9_]*(\.[a-zA-Z_][a-zA-Z0-9_]*|\[\d+\])+$/.test(rule.split('@')[0].split('##')[0].trim())) {
      // 对于JSON内容，识别类似 data.books 或 result.list[0] 这样的简单路径为JSON模式
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

    const regexParts = rule.split('##');
    if (regexParts.length > 1) {
      rule = regexParts[0];
      replaceRegex = regexParts[1];
      if (regexParts.length > 2) {
        replacement = regexParts[2];
      }
      if (regexParts.length > 3) {
        replaceFirst = true;
      }
    }

    return {
      mode,
      rule: rule.trim(),
      replaceRegex,
      replacement,
      replaceFirst,
      putMap: Object.keys(putMap).length > 0 ? putMap : undefined
    };
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
      // 先处理 @get:{xxx} 变量获取
      let processedRule = ruleStr;
      if (processedRule.includes('@get:')) {
        processedRule = processedRule.replace(/@get:\{([^}]+)\}/gi, (match: string, key: string): string => {
          return this.variables.get(key.trim()) || '';
        });
      }
      
      // 检查是否包含{{}}模板变量，如果有则先替换
      if (processedRule.includes('{{') && processedRule.includes('}}')) {
        return this.replaceTemplateVariables(processedRule);
      }

      // 处理规则分割符
      const splitResult = this.splitRuleStr(processedRule);
      if (splitResult.rules.length > 1) {
        return this.getStringWithSplitRules(splitResult.rules, splitResult.splitType);
      }

      return this.getStringSingle(processedRule);
    } catch (error) {
      logger.error(TAG, `解析规则失败: ${ruleStr}, 错误: ${String(error)}`);
      return '';
    }
  }

  /**
   * 获取字符串结果（异步版本）
   * 支持JS规则的异步执行
   */
  async getStringAsync(ruleStr: string | undefined): Promise<string> {
    if (!ruleStr || ruleStr.trim() === '') {
      return '';
    }

    try {
      // 先处理 @get:{xxx} 变量获取
      let processedRule = ruleStr;
      if (processedRule.includes('@get:')) {
        processedRule = processedRule.replace(/@get:\{([^}]+)\}/gi, (match: string, key: string): string => {
          return this.variables.get(key.trim()) || '';
        });
      }
      
      // 检查是否包含{{}}模板变量，如果有则先替换
      if (processedRule.includes('{{') && processedRule.includes('}}')) {
        return this.replaceTemplateVariables(processedRule);
      }

      // 处理规则分割符
      const splitResult = this.splitRuleStr(processedRule);
      if (splitResult.rules.length > 1) {
        return await this.getStringWithSplitRulesAsync(splitResult.rules, splitResult.splitType);
      }

      return await this.getStringSingleAsync(processedRule);
    } catch (error) {
      logger.error(TAG, `解析规则失败(异步): ${ruleStr}, 错误: ${String(error)}`);
      return '';
    }
  }

  /**
   * 使用分割规则获取字符串（异步版本）
   */
  private async getStringWithSplitRulesAsync(rules: string[], splitType: string): Promise<string> {
    const results: string[] = [];
    
    for (const rule of rules) {
      const result = await this.getStringSingleAsync(rule);
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
  private async getStringSingleAsync(ruleStr: string): Promise<string> {
    // 检查是否是组合规则：主规则@js:JS代码
    const jsPostfixMatch = ruleStr.match(/^(.+?)@js:(.+)$/i);
    if (jsPostfixMatch) {
      const mainRule = jsPostfixMatch[1].trim();
      const jsCode = jsPostfixMatch[2].trim();
      
      // 先执行主规则获取结果
      const mainResult = await this.getStringSingleInternalAsync(mainRule);
      
      // 将主规则结果作为result传给JS执行
      if (mainResult) {
        const jsWithResult = `var result = ${JSON.stringify(mainResult)}; ${jsCode}`;
        return await this.evalJSAsync(jsWithResult);
      }
      return '';
    }
    
    return await this.getStringSingleInternalAsync(ruleStr);
  }
  
  /**
   * 内部方法：获取单个规则的字符串结果（异步版本）
   */
  private async getStringSingleInternalAsync(ruleStr: string): Promise<string> {
    const parsedRule = this.parseRule(ruleStr);
    
    // 调试日志
    logger.debug(TAG, `getStringSingleInternalAsync: mode=${parsedRule.mode}, rule=${ruleStr.substring(0, 50)}...`);
    
    // 处理put变量
    if (parsedRule.putMap) {
      for (const key of Object.keys(parsedRule.putMap)) {
        const value = await this.getStringAsync(parsedRule.putMap[key]);
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
        logger.debug(TAG, `执行JS规则(异步), content长度=${this.content.length}, content前100字符=${this.content.substring(0, 100)}`);
        result = await this.evalJSAsync(parsedRule.rule);
        logger.debug(TAG, `JS规则执行结果: ${result.substring(0, 100)}`);
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

  /**
   * 分割规则字符串
   * 支持 &&, ||, %% 分割符
   */
  private splitRuleStr(ruleStr: string): RuleSplitResult {
    // 按优先级检查分割符: %%, ||, &&
    // 注意：需要避免在引号内或JS代码内分割
    const result: RuleSplitResult = { rules: [ruleStr], splitType: '' };
    if (this.containsSplitter(ruleStr, '%%')) {
      result.rules = this.safeSplit(ruleStr, '%%');
      result.splitType = '%%';
      return result;
    }
    if (this.containsSplitter(ruleStr, '||')) {
      result.rules = this.safeSplit(ruleStr, '||');
      result.splitType = '||';
      return result;
    }
    if (this.containsSplitter(ruleStr, '&&')) {
      result.rules = this.safeSplit(ruleStr, '&&');
      result.splitType = '&&';
      return result;
    }
    return result;
  }

  /**
   * 检查是否包含分割符（排除引号内和<js>标签内的）
   */
  private containsSplitter(str: string, splitter: string): boolean {
    let inQuote = false;
    let quoteChar = '';
    let inJsTag = false;
    
    for (let i = 0; i < str.length - splitter.length + 1; i++) {
      // 检查是否进入或离开<js>标签
      if (str.substring(i, i + 4).toLowerCase() === '<js>') {
        inJsTag = true;
        i += 3;
        continue;
      }
      if (str.substring(i, i + 5).toLowerCase() === '</js>') {
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
      if (!inQuote && str.substring(i, i + splitter.length) === splitter) {
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
    
    for (let i = 0; i < str.length; i++) {
      // 检查是否进入或离开<js>标签
      if (str.substring(i, i + 4).toLowerCase() === '<js>') {
        inJsTag = true;
        current += str.substring(i, i + 4);
        i += 3;
        continue;
      }
      if (str.substring(i, i + 5).toLowerCase() === '</js>') {
        inJsTag = false;
        current += str.substring(i, i + 5);
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
      
      if (!inQuote && str.substring(i, i + splitter.length) === splitter) {
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
    // 检查是否是组合规则：主规则@js:JS代码
    // 例如：$.name@js:java.put("name",result);result
    const jsPostfixMatch = ruleStr.match(/^(.+?)@js:(.+)$/i);
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
  
  /**
   * 内部方法：获取单个规则的字符串结果
   */
  private getStringSingleInternal(ruleStr: string): string {
    const parsedRule = this.parseRule(ruleStr);
    
    // 处理put变量
    if (parsedRule.putMap) {
      Object.keys(parsedRule.putMap).forEach((key: string): void => {
        const value = this.getString(parsedRule.putMap![key]);
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
      
      // 尝试作为JSONPath解析
      const value = this.getStringByJsonPath('$.' + trimmedExpr);
      return value || match;
    });
    
    return result;
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
      // 处理规则分割符
      const splitResult = this.splitRuleStr(ruleStr);
      if (splitResult.rules.length > 1) {
        return this.getStringListWithSplitRules(splitResult.rules, splitResult.splitType);
      }

      return this.getStringListSingle(ruleStr);
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

  /**
   * 获取元素列表（用于遍历）
   */
  getElements(ruleStr: string): string[] {
    if (!ruleStr || ruleStr.trim() === '') {
      return [];
    }

    try {
      // 先处理 || 操作符（或操作，第一个有结果就返回）
      if (ruleStr.includes('||')) {
        const orParts = ruleStr.split('||');
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
      
      return this.getElementsSingle(ruleStr);
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
      return [];
    }

    try {
      // 先处理 || 操作符（或操作，第一个有结果就返回）
      if (ruleStr.includes('||')) {
        const orParts = ruleStr.split('||');
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
      
      return await this.getElementsSingleAsync(ruleStr, jsContext);
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
      case LegadoRuleMode.Js:
        // 执行JS代码，然后解析结果
        try {
          // 检查是否有后续规则（@AFTER_JS@标记）
          let jsCode = parsedRule.rule;
          let afterJsRule = '';
          const afterJsIndex = jsCode.indexOf('\n@AFTER_JS@');
          if (afterJsIndex !== -1) {
            afterJsRule = jsCode.substring(afterJsIndex + 11);
            jsCode = jsCode.substring(0, afterJsIndex);
          }
          
          const jsEngine = getLegadoJsEngine();
          const context: JsContext = jsContext || {
            result: this.content,
            baseUrl: this.baseUrl,
            src: this.content
          };
          const jsResult = await jsEngine.execute(jsCode, context);
          // 性能优化：减少日志输出
          // logger.debug(TAG, `JS执行结果: ${String(jsResult).substring(0, 200)}`);
          
          // 更新content为JS执行结果
          let jsResultStr = '';
          if (typeof jsResult === 'string') {
            jsResultStr = jsResult;
          } else if (Array.isArray(jsResult)) {
            jsResultStr = JSON.stringify(jsResult);
          } else if (jsResult !== null && jsResult !== undefined) {
            jsResultStr = String(jsResult);
          }
          
          // 如果有后续规则，使用JS结果继续解析
          if (afterJsRule) {
            this.content = jsResultStr;
            this.isJSON = this.checkIsJSON(jsResultStr);
            // 性能优化：减少日志输出
            // logger.debug(TAG, `JS后续规则: ${afterJsRule}, isJSON=${this.isJSON}`);
            results = await this.getElementsSingleAsync(afterJsRule, jsContext);
          } else {
            // 没有后续规则，尝试解析JS结果
            try {
              const parsed: ESObject = JSON.parse(jsResultStr) as ESObject;
              if (Array.isArray(parsed)) {
                const parsedArray: ESObject[] = parsed as ESObject[];
                results = parsedArray.map((item: ESObject): string => 
                  typeof item === 'object' ? JSON.stringify(item) : String(item)
                );
              } else {
                this.content = jsResultStr;
              }
            } catch (parseError) {
              this.content = jsResultStr;
            }
          }
        } catch (e) {
          logger.error(TAG, `JS规则执行失败: ${String(e)}`);
        }
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
        const context: JsContext = {
          result: element,
          baseUrl: this.baseUrl,
          src: element,
          key: jsContext?.key,
          page: jsContext?.page,
          variables: jsContext?.variables
        };
        
        const jsResult = await jsEngine.execute(jsCode, context);
        let resultStr = '';
        if (typeof jsResult === 'string') {
          resultStr = jsResult;
        } else if (jsResult !== null && jsResult !== undefined) {
          resultStr = String(jsResult);
        }
        
        if (resultStr) {
          processedResults.push(resultStr);
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
          this.content = result;
          this.htmlBridge = null; // 禁用桥接，强制使用字符串解析
          
          // 执行后续选择器
          const afterSelector = afterParts[0].trim();
          const found = this.getElementsByCSS(afterSelector);
          for (const f of found) {
            finalResults.push(f);
          }
          
          // 恢复content和桥接
          this.content = originalContent;
          this.htmlBridge = originalBridge;
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

  // ==================== JSONPath解析 ====================

  /**
   * 通过JSONPath获取字符串
   */
  private getStringByJsonPath(path: string): string {
    try {
      const data: Object = JSON.parse(this.content);
      const result: Object | null = this.evaluateJsonPath(data as ESObject, path);
      if (result === null || result === undefined) {
        return '';
      }
      if (Array.isArray(result)) {
        return result.length > 0 ? this.valueToString(result[0]) : '';
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
      const data: Object = JSON.parse(this.content);
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
        logger.debug(TAG, `JSONPath解析: 内容为空`);
        return [];
      }
      
      // 尝试解析JSON
      let data: Object;
      try {
        data = JSON.parse(this.content);
      } catch (parseError) {
        // 内容不是有效的JSON，可能是HTML
        logger.debug(TAG, `JSONPath解析: 内容不是有效JSON，跳过`);
        return [];
      }
      
      const result: Object | null = this.evaluateJsonPath(data as ESObject, path);
      if (Array.isArray(result)) {
        return result.map((item: ESObject): string => JSON.stringify(item));
      }
      return result !== null && result !== undefined ? [JSON.stringify(result)] : [];
    } catch (error) {
      logger.warn(TAG, `JSONPath元素解析失败: ${path}, 错误: ${String(error)}`);
      return [];
    }
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
      // $..xxx 形式，递归搜索所有层级
      const searchKey = normalizedPath.substring(1); // 去掉开头的.
      return this.recursiveSearch(data, searchKey);
    }

    // 处理 $[*] 或 $.* 形式 - 返回所有元素
    if (normalizedPath === '*' || normalizedPath === '[*]') {
      if (Array.isArray(data)) {
        return data;
      }
      if (typeof data === 'object' && data !== null) {
        return Object.values(data as Record<string, ESObject>);
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
            const remainingPath = parts.slice(i + 1).join('.');
            const results: ESObject[] = [];
            const currentArray: ESObject[] = current as ESObject[];
            for (let j = 0; j < currentArray.length; j++) {
              const currentItem: ESObject = currentArray[j];
              const itemResult: ESObject = this.evaluateJsonPath(currentItem, '$.' + remainingPath);
              if (itemResult !== null && itemResult !== undefined) {
                if (Array.isArray(itemResult)) {
                  results.push(...(itemResult as ESObject[]));
                } else {
                  results.push(itemResult);
                }
              }
            }
            return results;
          }
          return current;
        }
        if (typeof current === 'object' && current !== null) {
          return Object.values(current as Record<string, ESObject>);
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
              const remainingPath = parts.slice(i + 1).join('.');
              const results: ESObject[] = [];
              const currentArray: ESObject[] = current as ESObject[];
              for (let j = 0; j < currentArray.length; j++) {
                const currentItem: ESObject = currentArray[j];
                const itemResult: ESObject = this.evaluateJsonPath(currentItem, '$.' + remainingPath);
                if (itemResult !== null && itemResult !== undefined) {
                  if (Array.isArray(itemResult)) {
                    results.push(...(itemResult as ESObject[]));
                  } else {
                    results.push(itemResult);
                  }
                }
              }
              return results;
            }
            return current;
          }
        } else {
          const index = parseInt(indexStr);
          if (!isNaN(index) && Array.isArray(current)) {
            current = current[index] as ESObject;
          }
        }
      } else {
        // 处理属性访问
        if (typeof current === 'object' && current !== null) {
          // 如果当前是数组，对每个元素获取属性
          if (Array.isArray(current)) {
            const results: ESObject[] = [];
            const currentArray: ESObject[] = current as ESObject[];
            for (let j = 0; j < currentArray.length; j++) {
              const arrayItem: ESObject = currentArray[j];
              if (typeof arrayItem === 'object' && arrayItem !== null) {
                const itemValue: ESObject = (arrayItem as Record<string, ESObject>)[part];
                if (itemValue !== null && itemValue !== undefined) {
                  results.push(itemValue);
                }
              }
            }
            current = results as ESObject;
          } else {
            current = (current as Record<string, ESObject>)[part];
          }
        } else {
          return null;
        }
      }
    }

    return current;
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

    for (let i = 0; i < path.length; i++) {
      const char = path[i];
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
  private getStringByCSS(selector: string): string {
    // 检查是否是Legado链式规则 (class.xxx@tag.a.0@text)
    if (selector.includes('@') && (selector.startsWith('class.') || selector.startsWith('id.') || 
        selector.startsWith('tag.') || selector.match(/^[a-z]+\./))) {
      return this.getStringByLegadoRule(selector);
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
    const elements = this.getElementsByCSS(result.sel);
    if (elements.length === 0) {
      return '';
    }

    return this.extractAttribute(elements[0], result.attr);
  }
  
  /**
   * 解析Legado链式规则
   * 支持格式: class.xxx@tag.a.0@text, id.xxx@tag.div@href
   * 支持正则替换: rule##regex##replacement##
   * 
   * 参考Legado原版AnalyzeByJSoup.kt的实现
   */
  private getStringByLegadoRule(rule: string): string {
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
    // 性能优化：减少日志输出，仅在内容较小时输出调试日志
    if (this.content.length < 10000) {
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
      // 性能优化：减少日志输出
      if (this.content.length < 10000) {
        logger.debug(TAG, `getStringByLegadoRule: step[${i}]=${rules[i]}, found=${newElements.length}`);
      }
      elements = newElements;
      if (elements.length === 0) {
        return '';
      }
    }
    
    // 步骤4: 获取最后一个规则指定的属性
    const lastRule = rules[lastIndex];
    const result = this.getResultByLastRule(elements, lastRule);
    
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
  private getResultByLastRule(elements: string[], lastRule: string): string {
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
      return results.join('\n');
    }
    
    const lowerRule = lastRule.toLowerCase();
    
    // 检查是否是属性名
    if (attrNames.includes(lowerRule)) {
      const results: string[] = [];
      for (const el of elements) {
        const text = this.extractAttribute(el, lowerRule);
        if (text) {
          results.push(text);
        }
      }
      return results.join('\n');
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
    return results.join('\n');
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
    
    // 获取所有匹配的元素
    let results: string[] = [];
    
    if (selector === 'children' || selector === '') {
      results = this.getChildElements(content);
    } else if (selector.startsWith('class.')) {
      const className = selector.substring(6);
      results = this.findElementsByClass(content, className);
    } else if (selector.startsWith('id.')) {
      const idName = selector.substring(3);
      results = this.findElementsById(content, idName);
    } else if (selector.startsWith('tag.')) {
      const tagName = selector.substring(4);
      results = this.findElementsByTag(content, tagName);
    } else if (selector.startsWith('text.')) {
      const searchText = selector.substring(5);
      results = this.findElementsByText(content, searchText);
    } else if (selector.includes('.') && !selector.startsWith('.')) {
      // 处理CSS选择器格式: tag.class (如 span.zuo, div.content)
      // 这是标准CSS选择器，表示 <tag class="class">
      const dotIndex = selector.indexOf('.');
      const tagName = selector.substring(0, dotIndex);
      const className = selector.substring(dotIndex + 1);
      // 先按标签查找，再按class过滤
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
      results = this.findElementsByTag(content, selector);
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
      ranges: []
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
    const dotRangeMatch = rule.match(/\.(-?\d+):(-?\d+)$/);
    if (dotRangeMatch) {
      result.selector = rule.substring(0, rule.length - dotRangeMatch[0].length);
      result.hasIndex = true;
      const start = parseInt(dotRangeMatch[1]);
      const end = parseInt(dotRangeMatch[2]);
      result.ranges.push({ start, end, step: 1 });
      return result;
    }
    
    // 检查.式索引 (tag.a.0 或 tag.a.-1)
    const dotIndexMatch = rule.match(/\.(-?\d+)$/);
    if (dotIndexMatch) {
      result.selector = rule.substring(0, rule.length - dotIndexMatch[0].length);
      result.hasIndex = true;
      result.indexes.push(parseInt(dotIndexMatch[1]));
      return result;
    }
    
    // 检查!式排除索引 (tag.a!0)
    const excludeMatch = rule.match(/!(-?\d+)$/);
    if (excludeMatch) {
      result.selector = rule.substring(0, rule.length - excludeMatch[0].length);
      result.hasIndex = true;
      result.exclude = true;
      result.indexes.push(parseInt(excludeMatch[1]));
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
      if (trimmed.includes(':')) {
        // 范围索引 start:end:step
        const rangeParts = trimmed.split(':');
        const start = rangeParts[0] ? parseInt(rangeParts[0]) : 0;
        const end = rangeParts.length > 1 && rangeParts[1] ? parseInt(rangeParts[1]) : -1;
        const step = rangeParts.length > 2 && rangeParts[2] ? parseInt(rangeParts[2]) : 1;
        result.ranges.push({ start, end, step });
      } else if (trimmed) {
        // 单个索引
        result.indexes.push(parseInt(trimmed));
      }
    }
  }
  
  /**
   * 应用索引筛选
   */
  private applyIndexFilter(elements: string[], indexResult: IndexSelectorResult): string[] {
    const len = elements.length;
    if (len === 0) {
      return [];
    }
    
    const indexSet = new Set<number>();
    
    // 处理单个索引
    for (const idx of indexResult.indexes) {
      const actualIdx = idx < 0 ? len + idx : idx;
      if (actualIdx >= 0 && actualIdx < len) {
        indexSet.add(actualIdx);
      }
    }
    
    // 处理范围索引
    for (const range of indexResult.ranges) {
      let start = range.start < 0 ? len + range.start : range.start;
      let end = range.end < 0 ? len + range.end : range.end;
      const step = range.step > 0 ? range.step : 1;
      
      // 边界检查
      start = Math.max(0, Math.min(start, len - 1));
      end = Math.max(0, Math.min(end, len - 1));
      
      if (start <= end) {
        for (let i = start; i <= end; i += step) {
          indexSet.add(i);
        }
      } else {
        for (let i = start; i >= end; i -= step) {
          indexSet.add(i);
        }
      }
    }
    
    // 如果没有指定索引，返回所有元素
    if (indexSet.size === 0 && indexResult.indexes.length === 0 && indexResult.ranges.length === 0) {
      return elements;
    }
    
    // 应用筛选
    if (indexResult.exclude) {
      // 排除模式
      return elements.filter((_, i) => !indexSet.has(i));
    } else {
      // 选择模式
      const sorted = Array.from(indexSet).sort((a, b) => a - b);
      return sorted.map(i => elements[i]);
    }
  }
  
  /**
   * 获取直接子元素
   * 添加性能保护：限制元素数量和内容大小以避免ANR
   */
  private getChildElements(content: string): string[] {
    const results: string[] = [];
    
    // 性能保护：使用统一配置
    const MAX_ELEMENTS = PerformanceConfig.MAX_ELEMENTS;
    const searchContent = PerformanceConfig.safeSubstring(content);
    
    // 匹配第一层子元素
    const tagRegex = /<([a-zA-Z][a-zA-Z0-9]*)[^>]*>/g;
    let match = tagRegex.exec(searchContent);
    let pos = 0;
    
    while (match !== null && results.length < MAX_ELEMENTS) {
      const tagName = match[1];
      const startIndex = match.index;
      
      // 跳过已处理的部分
      if (startIndex < pos) {
        match = tagRegex.exec(searchContent);
        continue;
      }
      
      const element = this.extractElement(searchContent, startIndex, tagName);
      if (element) {
        results.push(element);
        pos = startIndex + element.length;
      }
      
      match = tagRegex.exec(searchContent);
    }
    
    return results;
  }

  /**
   * 按class查找元素
   * 增强版：支持多个class名称，添加诊断日志
   * 添加性能保护：限制元素数量和内容大小以避免ANR
   */
  private findElementsByClass(content: string, className: string): string[] {
    const results: string[] = [];
    
    // 性能保护：使用统一配置
    const MAX_ELEMENTS = PerformanceConfig.MAX_ELEMENTS;
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
    
    // 方法1: 使用正则表达式直接匹配（更可靠）
    // 对于单个class，使用更精确的正则
    if (classNames.length === 1) {
      const singleClass = classNames[0];
      // 匹配 class="...className..." 或 class='...className...'
      // 确保className是完整的class名（前后是空格或引号边界）
      const classPatterns = [
        new RegExp(`<([a-zA-Z][a-zA-Z0-9]*)\\s+[^>]*\\bclass\\s*=\\s*"([^"]*\\b${this.escapeRegex(singleClass)}\\b[^"]*)"[^>]*>`, 'gi'),
        new RegExp(`<([a-zA-Z][a-zA-Z0-9]*)\\s+[^>]*\\bclass\\s*=\\s*'([^']*\\b${this.escapeRegex(singleClass)}\\b[^']*)'[^>]*>`, 'gi')
      ];
      
      for (const pattern of classPatterns) {
        let match = pattern.exec(searchContent);
        while (match !== null && results.length < MAX_ELEMENTS) {
          const tagName = match[1];
          const classAttr = match[2];
          // 验证class是完整匹配（不是子字符串）
          const classes = classAttr.split(/\s+/);
          if (classes.includes(singleClass)) {
            const element = this.extractElement(searchContent, match.index, tagName);
            if (element && !results.includes(element)) {
              results.push(element);
            }
          }
          match = pattern.exec(searchContent);
        }
        if (results.length > 0) break;
      }
    }
    
    // 如果正则方法没找到或需要匹配多个class，使用字符串搜索方法
    if (results.length === 0) {
      let searchStart = 0;
      const lowerContent = searchContent.toLowerCase();
      
      while (searchStart < searchContent.length && results.length < MAX_ELEMENTS) {
        // 查找 class= 的位置
        const classAttrIndex = lowerContent.indexOf('class=', searchStart);
        if (classAttrIndex === -1) break;
        
        // 向前找到开始标签的 <
        let tagStart = classAttrIndex;
        while (tagStart > 0 && searchContent[tagStart] !== '<') {
          tagStart--;
        }
        
        // 确保这是一个开始标签
        if (searchContent[tagStart] !== '<' || searchContent[tagStart + 1] === '/' || searchContent[tagStart + 1] === '!') {
          searchStart = classAttrIndex + 6;
          continue;
        }
        
        // 找到标签名
        const tagNameMatch = searchContent.substring(tagStart).match(/^<([a-zA-Z][a-zA-Z0-9]*)/);
        if (!tagNameMatch) {
          searchStart = classAttrIndex + 6;
          continue;
        }
        const tagName = tagNameMatch[1];
        
        // 找到标签结束位置
        let tagEnd = searchContent.indexOf('>', classAttrIndex);
        if (tagEnd === -1) {
          searchStart = classAttrIndex + 6;
          continue;
        }
        
        // 提取class属性值
        const attrPart = searchContent.substring(classAttrIndex, tagEnd);
        let classValue = '';
        
        // 匹配 class="value" 或 class='value' 或 class=value
        const doubleQuoteMatch = attrPart.match(/^class\s*=\s*"([^"]*)"/i);
        const singleQuoteMatch = attrPart.match(/^class\s*=\s*'([^']*)'/i);
        const noQuoteMatch = attrPart.match(/^class\s*=\s*([^\s>"']+)/i);
        
        if (doubleQuoteMatch) {
          classValue = doubleQuoteMatch[1];
        } else if (singleQuoteMatch) {
          classValue = singleQuoteMatch[1];
        } else if (noQuoteMatch) {
          classValue = noQuoteMatch[1];
        }
        
        // 检查是否包含所有目标class
        if (classValue) {
          const elementClasses = classValue.split(/\s+/);
          let hasAllClasses = true;
          for (const targetClass of classNames) {
            if (!elementClasses.includes(targetClass)) {
              hasAllClasses = false;
              break;
            }
          }
          
          if (hasAllClasses) {
            const element = this.extractElement(searchContent, tagStart, tagName);
            if (element && !results.includes(element)) {
              results.push(element);
            }
          }
        }
        
        searchStart = tagEnd + 1;
      }
    }
    
    // 如果还是没找到，输出HTML中存在的class供诊断
    if (results.length === 0) {
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
  private findElementsById(content: string, idName: string): string[] {
    const results: string[] = [];
    
    // 性能保护：使用统一配置（ID查找使用较小限制）
    const MAX_ELEMENTS = PerformanceConfig.MAX_ID_ELEMENTS;
    const searchContent = PerformanceConfig.safeSubstring(content);
    
    // 性能优化：减少大型内容时的日志输出
    if (searchContent.length < 10000) {
      this.selectorTrace((): string => `findElementsById: 查找id="${idName}", contentLen=${searchContent.length}`);
    }
    
    // 方法1: 使用正则表达式直接匹配（更可靠）
    // 匹配 id="xxx" 或 id='xxx' 或 id=xxx
    const idPatterns = [
      new RegExp(`<([a-zA-Z][a-zA-Z0-9]*)\\s+[^>]*\\bid\\s*=\\s*"${this.escapeRegex(idName)}"[^>]*>`, 'gi'),
      new RegExp(`<([a-zA-Z][a-zA-Z0-9]*)\\s+[^>]*\\bid\\s*=\\s*'${this.escapeRegex(idName)}'[^>]*>`, 'gi'),
      new RegExp(`<([a-zA-Z][a-zA-Z0-9]*)\\s+[^>]*\\bid\\s*=\\s*${this.escapeRegex(idName)}(?=[\\s>])[^>]*>`, 'gi')
    ];
    
    for (const pattern of idPatterns) {
      let match = pattern.exec(searchContent);
      while (match !== null && results.length < MAX_ELEMENTS) {
        const tagName = match[1];
        const element = this.extractElement(searchContent, match.index, tagName);
        if (element && !results.includes(element)) {
          results.push(element);
          this.selectorTrace((): string => `findElementsById: 找到元素 <${tagName} id="${idName}">`);
        }
        match = pattern.exec(searchContent);
      }
      if (results.length > 0) break; // 找到了就不再尝试其他模式
    }
    
    // 如果正则方法没找到，尝试字符串搜索方法（作为备用）
    if (results.length === 0) {
      let searchStart = 0;
      const lowerContent = searchContent.toLowerCase();
      const lowerIdName = idName.toLowerCase();
      
      while (searchStart < searchContent.length && results.length < MAX_ELEMENTS) {
        // 查找 id= 的位置
        const idAttrIndex = lowerContent.indexOf('id=', searchStart);
        if (idAttrIndex === -1) break;
        
        // 向前找到开始标签的 <
        let tagStart = idAttrIndex;
        while (tagStart > 0 && searchContent[tagStart] !== '<') {
          tagStart--;
        }
        
        // 确保这是一个开始标签
        if (searchContent[tagStart] !== '<' || searchContent[tagStart + 1] === '/' || searchContent[tagStart + 1] === '!') {
          searchStart = idAttrIndex + 3;
          continue;
        }
        
        // 找到标签名
        const tagNameMatch = searchContent.substring(tagStart).match(/^<([a-zA-Z][a-zA-Z0-9]*)/);
        if (!tagNameMatch) {
          searchStart = idAttrIndex + 3;
          continue;
        }
        const tagName = tagNameMatch[1];
        
        // 找到标签结束位置
        let tagEnd = searchContent.indexOf('>', idAttrIndex);
        if (tagEnd === -1) {
          searchStart = idAttrIndex + 3;
          continue;
        }
        
        // 提取id属性值
        const attrPart = searchContent.substring(idAttrIndex, tagEnd);
        let idValue = '';
        
        // 匹配 id="value" 或 id='value' 或 id=value
        const doubleQuoteMatch = attrPart.match(/^id\s*=\s*"([^"]*)"/i);
        const singleQuoteMatch = attrPart.match(/^id\s*=\s*'([^']*)'/i);
        const noQuoteMatch = attrPart.match(/^id\s*=\s*([^\s>"']+)/i);
        
        if (doubleQuoteMatch) {
          idValue = doubleQuoteMatch[1];
        } else if (singleQuoteMatch) {
          idValue = singleQuoteMatch[1];
        } else if (noQuoteMatch) {
          idValue = noQuoteMatch[1];
        }
        
        // 检查是否匹配目标id（不区分大小写）
        if (idValue.toLowerCase() === lowerIdName) {
          const element = this.extractElement(searchContent, tagStart, tagName);
          if (element && !results.includes(element)) {
            results.push(element);
          }
        }
        
        searchStart = tagEnd + 1;
      }
    }
    
    // 如果还是没找到，输出HTML中所有id属性供诊断
    if (results.length === 0) {
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
  private findElementsByTag(content: string, tagName: string): string[] {
    const results: string[] = [];
    
    // 性能保护：使用统一配置
    const MAX_ELEMENTS = PerformanceConfig.MAX_ELEMENTS;
    const searchContent = PerformanceConfig.safeSubstring(content);
    
    const pattern = `<${this.escapeRegex(tagName)}[^>]*>`;
    try {
      const regex = new RegExp(pattern, 'gi');
      let match = regex.exec(searchContent);
      while (match !== null && results.length < MAX_ELEMENTS) {
        const element = this.extractElement(searchContent, match.index, tagName);
        if (element) {
          results.push(element);
        }
        match = regex.exec(searchContent);
      }
    } catch (e) {
      // 忽略正则错误
    }
    return results;
  }

  /**
   * 按文本内容查找元素
   * 添加性能保护：限制元素数量和内容大小以避免ANR
   */
  private findElementsByText(content: string, searchText: string): string[] {
    const results: string[] = [];
    
    // 性能保护：使用统一配置
    const MAX_ELEMENTS = PerformanceConfig.MAX_ELEMENTS;
    const searchContent = PerformanceConfig.safeSubstring(content);
    
    const pattern = `<([a-zA-Z][a-zA-Z0-9]*)[^>]*>[^<]*${this.escapeRegex(searchText)}[^<]*</\\1>`;
    try {
      const regex = new RegExp(pattern, 'gi');
      let match = regex.exec(searchContent);
      while (match !== null && results.length < MAX_ELEMENTS) {
        results.push(match[0]);
        match = regex.exec(searchContent);
      }
    } catch (e) {
      // 忽略正则错误
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
    return elements.map((el: string): string => this.extractAttribute(el, result.attr));
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
      logger.debug(TAG, `getElementsByCSSWithBridge: HTML过大(${contentLength}字节)，使用字符串解析避免ANR`);
      return this.getElementsByCSSChain(selector);
    }
    
    // 如果有HTML桥接，优先使用DOM解析
    if (this.htmlBridge) {
      try {
        // 检查是否是Legado链式规则（包含@）
        if (selector.includes('@')) {
          const elements = this.htmlBridge.parseChainRuleToHtmlList(selector);
          if (elements.length > 0) {
            logger.debug(TAG, `getElementsByCSSWithBridge: 使用HTML桥接解析链式规则，结果数量=${elements.length}`);
            return elements;
          }
        } else {
          // 标准CSS选择器
          const elements = this.htmlBridge.querySelectorAll(selector);
          if (elements.length > 0) {
            const results = elements.map((elem: HtmlElement): string => elem.outerHTML);
            logger.debug(TAG, `getElementsByCSSWithBridge: 使用HTML桥接解析CSS选择器，结果数量=${results.length}`);
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
  
  /**
   * 处理CSS选择器链（@分隔）
   * 支持属性+JS组合：a@href<js>...</js>
   */
  private getElementsByCSSChain(selector: string): string[] {
    // 检查是否包含<js>标签，需要特殊处理@分隔
    // 例如 a@href<js>...</js> 应该分为 [a, href<js>...</js>]
    let parts: string[] = [];
    if (selector.includes('<js>')) {
      // 使用智能分割，避免分割<js>标签内的@
      parts = this.splitSelectorWithJs(selector);
    } else {
      parts = selector.split('@');
    }
    this.selectorTrace((): string => `getElementsByCSSChain: selector=${selector}, parts=${parts.length}`);
    
    let currentElements: string[] = [this.content];
    
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
          const found = this.findElementsBySingleSelector(element, part);
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
    
    return currentElements;
  }
  
  /**
   * 智能分割包含<js>标签的选择器
   * 避免分割<js>...</js>内部的@符号
   */
  private splitSelectorWithJs(selector: string): string[] {
    const parts: string[] = [];
    let current = '';
    let inJs = false;
    
    for (let i = 0; i < selector.length; i++) {
      const char = selector[i];
      
      // 检查是否进入<js>标签
      if (selector.substring(i, i + 4).toLowerCase() === '<js>') {
        inJs = true;
        current += selector.substring(i, i + 4);
        i += 3;
        continue;
      }
      
      // 检查是否离开</js>标签
      if (selector.substring(i, i + 5).toLowerCase() === '</js>') {
        inJs = false;
        current += selector.substring(i, i + 5);
        i += 4;
        continue;
      }
      
      // 在JS标签外遇到@，分割
      if (char === '@' && !inJs) {
        if (current) {
          parts.push(current);
        }
        current = '';
      } else {
        current += char;
      }
    }
    
    if (current) {
      parts.push(current);
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
  private findElementsBySingleSelector(html: string, selector: string): string[] {
    // 先检查是否是CSS标准选择器格式（.class 或 #id）
    // 这些选择器不应该被parseIndexSelector处理，因为.后面不是数字
    const isCssClassSelector = selector.startsWith('.') && !/^\.\d/.test(selector);
    const isCssIdSelector = selector.startsWith('#');
    
    // 检查是否包含空格（后代选择器），如 "#chapterlist li a"
    const hasDescendant = selector.includes(' ');
    
    if ((isCssClassSelector || isCssIdSelector) && !hasDescendant) {
      // 简单的CSS选择器（不含后代选择器），直接使用findElementsBySimpleSelector处理
      this.selectorTrace((): string => `findElementsBySingleSelector: 简单CSS选择器=${selector}, htmlLen=${html.length}`);
      return this.findElementsBySimpleSelector(html, selector);
    }
    
    // 解析索引选择器 [0,2,4] 或 [!0,1] 或 [0:10] 或 [0:10:2]
    const indexResult = this.parseIndexSelector(selector);
    selector = indexResult.selector;
    
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
    const selectorParts = selector.trim().split(/\s+/);
    
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
            found = this.findElementsBySimpleSelector(element, part);
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
      results = this.findElementsBySimpleSelector(html, selector);
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
  private findElementsBySimpleSelector(html: string, selector: string): string[] {
    // 解析选择器组件
    let tagName = '';
    let className = '';
    let idName = '';
    let attrSelector = '';
    let attrValue = '';
    let attrOperator = '=';
    
    // 解析属性选择器
    const attrMatch = selector.match(/\[([^\]=~$*^]+)([~$*^]?=)?["']?([^"'\]]*)["']?\]/);
    if (attrMatch) {
      attrSelector = attrMatch[1];
      attrOperator = attrMatch[2] || '=';
      attrValue = attrMatch[3] || '';
      selector = selector.replace(/\[[^\]]+\]/g, '');
    }
    
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
    if (className && !tagName && !idName && !attrSelector) {
      return this.findElementsByClass(html, className);
    }
    
    // 如果只有id，使用findElementsById
    if (idName && !tagName && !className && !attrSelector) {
      return this.findElementsById(html, idName);
    }
    
    // 如果只有tag，使用findElementsByTag
    if (tagName && !className && !idName && !attrSelector) {
      return this.findElementsByTag(html, tagName);
    }
    
    // 复合选择器：使用字符串搜索方法
    const results: string[] = [];
    let searchStart = 0;
    
    while (searchStart < html.length) {
      // 查找下一个开始标签
      const tagStartIndex = html.indexOf('<', searchStart);
      if (tagStartIndex === -1) break;
      
      // 跳过结束标签和注释
      if (html[tagStartIndex + 1] === '/' || html[tagStartIndex + 1] === '!') {
        searchStart = tagStartIndex + 1;
        continue;
      }
      
      // 找到标签结束位置
      const tagEndIndex = html.indexOf('>', tagStartIndex);
      if (tagEndIndex === -1) break;
      
      // 提取标签内容
      const tagContent = html.substring(tagStartIndex, tagEndIndex + 1);
      const tagNameMatch2 = tagContent.match(/^<([a-zA-Z][a-zA-Z0-9]*)/);
      if (!tagNameMatch2) {
        searchStart = tagEndIndex + 1;
        continue;
      }
      
      const currentTagName = tagNameMatch2[1].toLowerCase();
      
      // 检查标签名
      if (tagName && currentTagName !== tagName) {
        searchStart = tagEndIndex + 1;
        continue;
      }
      
      // 检查class
      if (className) {
        const classAttrMatch = tagContent.match(/\bclass\s*=\s*"([^"]*)"/i) ||
                               tagContent.match(/\bclass\s*=\s*'([^']*)'/i) ||
                               tagContent.match(/\bclass\s*=\s*([^\s>"']+)/i);
        if (!classAttrMatch || !this.hasClass(classAttrMatch[1], className)) {
          searchStart = tagEndIndex + 1;
          continue;
        }
      }
      
      // 检查id
      if (idName) {
        const idAttrMatch = tagContent.match(/\bid\s*=\s*"([^"]*)"/i) ||
                            tagContent.match(/\bid\s*=\s*'([^']*)'/i) ||
                            tagContent.match(/\bid\s*=\s*([^\s>"']+)/i);
        if (!idAttrMatch || idAttrMatch[1] !== idName) {
          searchStart = tagEndIndex + 1;
          continue;
        }
      }
      
      // 检查属性选择器
      if (attrSelector) {
        const attrRegex = new RegExp(`\\b${this.escapeRegex(attrSelector)}\\s*=\\s*["']([^"']*)["']`, 'i');
        const attrMatchResult = tagContent.match(attrRegex);
        if (!attrMatchResult) {
          searchStart = tagEndIndex + 1;
          continue;
        }
        if (attrValue) {
          const attrActualValue = attrMatchResult[1];
          let attrMatches = false;
          switch (attrOperator) {
            case '$=': attrMatches = attrActualValue.endsWith(attrValue); break;
            case '^=': attrMatches = attrActualValue.startsWith(attrValue); break;
            case '*=': attrMatches = attrActualValue.includes(attrValue); break;
            case '~=': attrMatches = attrActualValue.split(/\s+/).includes(attrValue); break;
            default: attrMatches = attrActualValue === attrValue;
          }
          if (!attrMatches) {
            searchStart = tagEndIndex + 1;
            continue;
          }
        }
      }
      
      // 匹配成功，提取完整元素
      const element = this.extractElement(html, tagStartIndex, currentTagName);
      if (element && !results.includes(element)) {
        results.push(element);
      }
      
      searchStart = tagEndIndex + 1;
    }
    
    return results;
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
  private extractElement(html: string, startIndex: number, tagName: string): string | null {
    // 检查是否是自关闭标签
    const selfClosingTags = ['br', 'hr', 'img', 'input', 'meta', 'link', 'area', 'base', 'col', 'embed', 'param', 'source', 'track', 'wbr'];
    if (selfClosingTags.includes(tagName.toLowerCase())) {
      const endOfTag = html.indexOf('>', startIndex);
      if (endOfTag !== -1) {
        return html.substring(startIndex, endOfTag + 1);
      }
      return null;
    }
    
    // 查找匹配的结束标签
    let depth = 1;
    let pos = html.indexOf('>', startIndex) + 1;
    const openTag = new RegExp(`<${tagName}(?:\\s|>)`, 'gi');
    const closeTag = new RegExp(`</${tagName}>`, 'gi');
    
    while (depth > 0 && pos < html.length) {
      openTag.lastIndex = pos;
      closeTag.lastIndex = pos;
      
      const nextOpen = openTag.exec(html);
      const nextClose = closeTag.exec(html);
      
      if (!nextClose) {
        // 没有找到结束标签，返回到文档末尾
        return html.substring(startIndex);
      }
      
      if (!nextOpen || nextClose.index < nextOpen.index) {
        // 先找到结束标签
        depth--;
        pos = nextClose.index + nextClose[0].length;
      } else {
        // 先找到开始标签
        depth++;
        pos = nextOpen.index + nextOpen[0].length;
      }
    }
    
    if (depth === 0) {
      return html.substring(startIndex, pos);
    }
    
    return null;
  }

  /**
   * 从元素中提取属性
   * 支持Legado原版的所有属性提取方式
   */
  private extractAttribute(element: string, attr: string): string {
    switch (attr.toLowerCase()) {
      case 'text':
      case 'textcontent':
        // 移除HTML标签，获取纯文本
        return this.htmlToText(element);
      case 'textnodes':
        // 获取所有文本节点，换行分隔
        // 移除script和style标签内容
        let textContent = element
          .replace(/<script[^>]*>[\s\S]*?<\/script>/gi, '')
          .replace(/<style[^>]*>[\s\S]*?<\/style>/gi, '');
        // 获取文本节点
        const textNodes: string[] = [];
        const textNodeRegex = />([^<]+)</g;
        let textMatch = textNodeRegex.exec(textContent);
        while (textMatch !== null) {
          const text = textMatch[1].trim();
          if (text) {
            textNodes.push(text);
          }
          textMatch = textNodeRegex.exec(textContent);
        }
        return textNodes.join('\n');
      case 'owntext':
        // 获取元素自身文本（不含子元素）
        // 先获取第一层内容
        const ownTextMatch = element.match(/^<[^>]+>([^<]*)/);
        return ownTextMatch ? ownTextMatch[1].trim() : '';
      case 'html':
      case 'innerhtml':
        // 获取内部HTML（移除script和style）
        let innerHtml = element
          .replace(/<script[^>]*>[\s\S]*?<\/script>/gi, '')
          .replace(/<style[^>]*>[\s\S]*?<\/style>/gi, '');
        const innerMatch = innerHtml.match(/^<[^>]+>([\s\S]*)<\/[^>]+>$/);
        return innerMatch ? innerMatch[1] : '';
      case 'all':
      case 'outerhtml':
        // 获取完整外部HTML
        return element;
      case 'href':
      case 'src':
      case 'data-src':
        // 获取属性值并解析为绝对URL
        const urlAttrRegex = new RegExp(`${attr}=["']([^"']+)["']`, 'i');
        const urlAttrMatch = element.match(urlAttrRegex);
        if (urlAttrMatch) {
          return this.resolveUrl(urlAttrMatch[1]);
        }
        return '';
      case 'content':
        // 获取meta标签的content属性
        const contentMatch = element.match(/content=["']([^"']+)["']/i);
        return contentMatch ? contentMatch[1] : '';
      default:
        // 其他属性
        const defaultRegex = new RegExp(`${this.escapeRegex(attr)}=["']([^"']+)["']`, 'i');
        const defaultMatch = element.match(defaultRegex);
        return defaultMatch ? defaultMatch[1] : '';
    }
  }

  /**
   * 将HTML转换为纯文本
   * 移除所有HTML标签、script、style、注释，并处理HTML实体
   */
  private htmlToText(html: string): string {
    let text = html;
    
    // 1. 移除script标签及其内容
    text = text.replace(/<script[^>]*>[\s\S]*?<\/script>/gi, '');
    
    // 2. 移除style标签及其内容
    text = text.replace(/<style[^>]*>[\s\S]*?<\/style>/gi, '');
    
    // 3. 移除HTML注释
    text = text.replace(/<!--[\s\S]*?-->/g, '');
    
    // 4. 将<br>、<br/>、<p>、</p>、<div>、</div>等转换为换行
    text = text.replace(/<br\s*\/?>/gi, '\n');
    text = text.replace(/<\/?(p|div|li|tr|h[1-6])[^>]*>/gi, '\n');
    
    // 5. 移除所有其他HTML标签
    text = text.replace(/<[^>]+>/g, '');
    
    // 6. 处理常见HTML实体
    text = text.replace(/&nbsp;/gi, ' ');
    text = text.replace(/&lt;/gi, '<');
    text = text.replace(/&gt;/gi, '>');
    text = text.replace(/&amp;/gi, '&');
    text = text.replace(/&quot;/gi, '"');
    text = text.replace(/&apos;/gi, "'");
    text = text.replace(/&#(\d+);/g, (_match: string, dec: string): string => {
      return String.fromCharCode(parseInt(dec, 10));
    });
    text = text.replace(/&#x([0-9a-fA-F]+);/g, (_match: string, hex: string): string => {
      return String.fromCharCode(parseInt(hex, 16));
    });
    
    // 7. 合并多个连续空白字符为单个空格（但保留换行）
    text = text.replace(/[ \t]+/g, ' ');
    
    // 8. 合并多个连续换行为最多两个换行
    text = text.replace(/\n{3,}/g, '\n\n');
    
    // 9. 去除每行首尾空白
    text = text.split('\n').map((line: string): string => line.trim()).join('\n');
    
    // 10. 去除首尾空白
    return text.trim();
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
    
    // 向前查找最近的未闭合标签
    let depth = 0;
    let i = elementIndex - 1;
    while (i >= 0) {
      const beforeContent = fullContent.substring(0, i + 1);
      const lastTagMatch = beforeContent.match(/<\/?([a-zA-Z][a-zA-Z0-9]*)[^>]*>$/);
      if (lastTagMatch) {
        const isClosing = lastTagMatch[0].startsWith('</');
        const tagName = lastTagMatch[1];
        if (isClosing) {
          depth++;
        } else {
          if (depth === 0) {
            // 找到父元素
            if (tag === '*' || tag === tagName) {
              const parentElement = this.extractElement(fullContent, i - lastTagMatch[0].length + 1, tagName);
              if (parentElement) {
                return [parentElement];
              }
            }
            return [];
          }
          depth--;
        }
        i -= lastTagMatch[0].length;
      } else {
        i--;
      }
    }
    return [];
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
  private findDirectChildren(html: string): string[] {
    const results: string[] = [];
    let depth = 0;
    let i = 0;
    
    while (i < html.length) {
      const tagMatch = html.substring(i).match(/^<([a-zA-Z][a-zA-Z0-9]*)[^>]*>/);
      if (tagMatch && depth === 0) {
        const tagName = tagMatch[1];
        const element = this.extractElement(html, i, tagName);
        if (element) {
          results.push(element);
          i += element.length;
          continue;
        }
      }
      
      // 跟踪深度
      const anyTagMatch = html.substring(i).match(/^<\/?([a-zA-Z][a-zA-Z0-9]*)[^>]*>/);
      if (anyTagMatch) {
        if (anyTagMatch[0].startsWith('</')) {
          depth--;
        } else if (!anyTagMatch[0].endsWith('/>')) {
          depth++;
        }
        i += anyTagMatch[0].length;
      } else {
        i++;
      }
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
    // 简化实现：向后查找第一个闭合标签
    let depth = 0;
    let i = startIndex;
    while (i < content.length) {
      const tagMatch = content.substring(i).match(/^<\/?([a-zA-Z][a-zA-Z0-9]*)[^>]*>/);
      if (tagMatch) {
        if (tagMatch[0].startsWith('</')) {
          if (depth === 0) {
            return i;
          }
          depth--;
        } else if (!tagMatch[0].endsWith('/>')) {
          depth++;
        }
        i += tagMatch[0].length;
      } else {
        i++;
      }
    }
    return content.length;
  }

  /**
   * 查找父元素开始标签位置
   */
  private findParentStartTag(content: string, endIndex: number): number {
    let depth = 0;
    let i = endIndex - 1;
    while (i >= 0) {
      // 向前查找标签
      let tagEnd = i;
      while (tagEnd >= 0 && content[tagEnd] !== '>') tagEnd--;
      if (tagEnd < 0) break;
      
      let tagStart = tagEnd;
      while (tagStart >= 0 && content[tagStart] !== '<') tagStart--;
      if (tagStart < 0) break;
      
      const tag = content.substring(tagStart, tagEnd + 1);
      const isClosing = tag.startsWith('</');
      
      if (isClosing) {
        depth++;
      } else if (!tag.endsWith('/>')) {
        if (depth === 0) {
          return tagStart;
        }
        depth--;
      }
      
      i = tagStart - 1;
    }
    return 0;
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
    const tagRegex = /<([a-zA-Z][a-zA-Z0-9]*)[^>]*>/g;
    let match = tagRegex.exec(html);
    let pos = 0;
    
    while (match !== null) {
      if (match.index < pos) {
        match = tagRegex.exec(html);
        continue;
      }
      
      const tagName = match[1];
      const element = this.extractElement(html, match.index, tagName);
      if (element) {
        results.push(element);
        pos = match.index + element.length;
      }
      match = tagRegex.exec(html);
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
    logger.debug(TAG, `JS执行(同步): ${code.substring(0, 50)}... - 建议使用异步版本`);
    
    // 启动异步执行但不等待结果（用于预热）
    const jsEngine = getLegadoJsEngine();
    const context: JsContext = {
      result: this.content,
      baseUrl: this.baseUrl,
      variables: this.getVariablesObject()
    };
    
    // 异步执行，结果会被丢弃（同步上下文无法等待）
    jsEngine.execute(code, context).then((result) => {
      if (result.success && result.result) {
        logger.debug(TAG, `JS异步执行完成: ${result.result.substring(0, 50)}...`);
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
    const context: JsContext = {
      result: this.content,
      baseUrl: this.baseUrl,
      variables: this.getVariablesObject()
    };
    
    const result = await jsEngine.execute(code, context);
    if (result.success) {
      return result.result;
    } else {
      logger.warn(TAG, `JS执行失败: ${result.error}`);
      return '';
    }
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

  // ==================== 工具方法 ====================

  /**
   * 应用替换规则
   * 支持$1, $2等正则捕获组引用
   */
  private applyReplace(input: string, pattern: string, replacement: string, first: boolean): string {
    try {
      const regex = new RegExp(pattern, first ? '' : 'g');
      
      // 使用函数替换以支持$1, $2等捕获组
      return input.replace(regex, (...args: string[]): string => {
        let result = replacement;
        // args: [match, group1, group2, ..., offset, string]
        // 替换$0为完整匹配
        result = result.replace(/\$0/g, args[0]);
        // 替换$1, $2, ... $9为对应捕获组
        for (let i = 1; i < args.length - 2 && i <= 9; i++) {
          const groupValue = args[i] !== undefined ? args[i] : '';
          result = result.replace(new RegExp('\\$' + i, 'g'), groupValue);
        }
        return result;
      });
    } catch (e) {
      logger.warn(TAG, `替换规则执行失败: ${pattern}`);
      return input.replace(pattern, replacement);
    }
  }

  /**
   * 解析相对URL为绝对URL
   */
  private resolveUrl(url: string): string {
    if (!url) {
      return '';
    }
    
    // 已经是绝对URL
    if (url.startsWith('http://') || url.startsWith('https://') || url.startsWith('//')) {
      if (url.startsWith('//')) {
        return 'https:' + url;
      }
      return url;
    }

    // 相对URL
    if (!this.baseUrl) {
      return url;
    }

    try {
      // 简单的URL拼接
      let base = this.baseUrl;
      if (url.startsWith('/')) {
        // 从根路径开始
        const match = base.match(/^(https?:\/\/[^\/]+)/);
        if (match) {
          return match[1] + url;
        }
      } else {
        // 相对当前路径
        if (!base.endsWith('/')) {
          const lastSlash = base.lastIndexOf('/');
          base = base.substring(0, lastSlash + 1);
        }
        return base + url;
      }
    } catch (e) {
      logger.warn(TAG, `URL解析失败: ${url}`);
    }

    return url;
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
   * 清除变量
   */
  clearVariables(): void {
    this.variables.clear();
  }
}
