import { SafeUtils } from 'manxia_core/src/main/ets/Utils/SafeUtils';
/**
 * Legado URL解析器
 * 处理URL模板变量替换、请求参数解析、JS规则执行
 * 
 * 文件路径: entry/src/main/ets/Framework/Novel/LegadoUrlAnalyzer.ets
 * 
 * 参考legado原版: AnalyzeUrl.kt
 * 实现了完整的JS规则支持：
 * 1. @js: 和 <js></js> 格式的JS代码执行
 * 2. {{...}} 内嵌JS表达式执行
 * 3. URL参数编码
 */

import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { LegadoHeaderOption, LegadoUrlOption, LegadoUrlOptionBody } from './LegadoSourceTypes';
import {
  getLegadoJsEngine,
  JsContext,
  LegadoJsSourceDataChange,
  LegadoJsSourceEffects
} from './LegadoJsEngine';
import { util } from '@kit.ArkTS';

const TAG = 'LegadoUrlAnalyzer';

/**
 * 请求方法枚举
 */
export enum RequestMethod {
  GET = 'GET',
  POST = 'POST'
}

/**
 * 解析后的URL请求信息
 */
export interface ParsedUrlRequest {
  url: string;
  requestUrl?: string;
  method: RequestMethod;
  headers: Record<string, string>;
  body?: string;
  encodedBody?: string;
  charset?: string;
  useWebView?: boolean;
  webJs?: string;
  retry?: number;
  responseType?: string;
  serverId?: number;
  webViewDelayTime?: number;
  optionJs?: string;
}

/**
 * JS规则模式 - 匹配 @js: 和 <js></js>
 * 参考: AppPattern.kt
 */
const JS_PATTERN = /<js>([\s\S]*?)<\/js>|(?:@|＠)js(?:\:|：)([\s\S]*)/i;

/**
 * URL选项分隔符查找结果
 */
interface OptionSeparatorResult {
  found: boolean;
  index: number;
}

interface JsExecutionOutcome {
  success: boolean;
  result: string;
  error?: string;
  useSimpleFallback: boolean;
}

interface EncodedRequestParts {
  requestUrl?: string;
  encodedBody?: string;
}

interface NormalizedUrlOption {
  method?: RequestMethod;
  headers?: Record<string, string>;
  body?: string;
  charset?: string;
  useWebView?: boolean;
  webJs?: string;
  retry?: number;
  responseType?: string;
  serverId?: number;
  webViewDelayTime?: number;
  js?: string;
}

/**
 * URL解析器类
 */
export class LegadoUrlAnalyzer {
  private baseUrl: string = '';
  private variables: Map<string, string> = new Map();
  private key: string = '';
  private page: number = 1;
  private sourceUrl: string = '';  // 书源URL，用于JS中的source.getKey()
  private jsLib: string = '';      // 书源JS库快照（避免并发串源）
  private sourceEffects: LegadoJsSourceEffects = {};

  constructor(baseUrl?: string, sourceUrl?: string, jsLib?: string) {
    if (baseUrl) {
      this.baseUrl = baseUrl;
    }
    if (sourceUrl) {
      this.sourceUrl = sourceUrl;
    }
    if (jsLib) {
      this.jsLib = jsLib;
    }
  }

  /**
   * 设置基础URL
   */
  setBaseUrl(baseUrl: string): LegadoUrlAnalyzer {
    this.baseUrl = baseUrl;
    return this;
  }

  getBaseUrl(): string {
    return this.baseUrl;
  }

  /**
   * 设置变量
   */
  setVariable(key: string, value: string): LegadoUrlAnalyzer {
    this.variables.set(key, value);
    return this;
  }

  setJsLib(jsLib?: string): LegadoUrlAnalyzer {
    this.jsLib = jsLib || '';
    return this;
  }

  /**
   * 设置多个变量
   */
  setVariables(vars: Record<string, string>): LegadoUrlAnalyzer {
    Object.keys(vars).forEach(key => {
      this.variables.set(key, vars[key]);
    });
    return this;
  }

  getVariablesSnapshot(): Record<string, string> {
    const snapshot: Record<string, string> = {};
    this.variables.forEach((value: string, key: string): void => {
      snapshot[key] = value;
    });
    return snapshot;
  }

  /**
   * 解析URL模板（同步版本，不执行JS）
   */
  analyzeUrl(urlTemplate: string, key?: string, page?: number): ParsedUrlRequest {
    // 保存参数
    if (key !== undefined) {
      this.key = key;
      this.variables.set('key', key);
      this.variables.set('encodedKey', encodeURIComponent(key));
    }
    if (page !== undefined) {
      this.page = page;
      this.variables.set('page', String(page));
    }

    let ruleUrl = urlTemplate;
    let method = RequestMethod.GET;
    let headers: Record<string, string> = {};
    let body: string | undefined;
    let charset: string | undefined;
    let useWebView = false;
    let webJs: string | undefined;
    let retry = 0;
    let responseType: string | undefined;
    let serverId = 0;
    let webViewDelayTime = 0;
    let optionJs: string | undefined;
    
    // 特殊处理: data:协议URL直接返回，不进行任何解析
    // data:URL用于在书源间传递数据，格式如: data:;base64,{json},{extra}
    if (urlTemplate.startsWith('data:')) {
      return {
        url: urlTemplate,
        method,
        headers,
        body,
        charset,
        useWebView,
        webJs,
        retry,
        responseType,
        serverId,
        webViewDelayTime,
        optionJs
      };
    }

    // 步骤1: 执行 @js: 和 <js></js> 格式的JS代码。
    // Legado原版 AnalyzeUrl 的顺序是先 analyzeJs()，再 replaceKeyPageJs()，最后 analyzeUrl() 拆 URL option。
    ruleUrl = this.analyzeJs(ruleUrl);

    // 步骤2: 替换 {{...}} 内嵌JS/变量
    ruleUrl = this.replaceKeyPageJs(ruleUrl);

    // 步骤3: 分离URL和选项JSON
    // 参考Legado原版: paramPattern = Pattern.compile("\\s*,\\s*(?=\\{)")
    let optionStr = '';
    const separatorResult = this.findOptionSeparator(ruleUrl);
    if (separatorResult.found) {
      optionStr = ruleUrl.substring(separatorResult.index + 1).trim();
      ruleUrl = ruleUrl.substring(0, separatorResult.index).trim();
    }

    // 步骤4: 解析选项JSON（支持单引号格式）
    if (optionStr) {
      const option = this.parseUrlOption(optionStr);
      if (option) {
        const normalizedOption = this.normalizeUrlOption(option);
        if (normalizedOption.method) method = normalizedOption.method;
        if (normalizedOption.headers) headers = normalizedOption.headers;
        if (normalizedOption.body !== undefined) body = normalizedOption.body;
        if (normalizedOption.charset) charset = normalizedOption.charset;
        if (normalizedOption.useWebView) useWebView = true;
        if (normalizedOption.webJs) webJs = normalizedOption.webJs;
        if (normalizedOption.retry !== undefined) retry = normalizedOption.retry;
        if (normalizedOption.responseType !== undefined) responseType = normalizedOption.responseType;
        if (normalizedOption.serverId !== undefined) serverId = normalizedOption.serverId;
        if (normalizedOption.webViewDelayTime !== undefined) webViewDelayTime = normalizedOption.webViewDelayTime;
        if (normalizedOption.js) optionJs = normalizedOption.js;
      }
    }

    // 步骤5: 处理body中的变量
    if (body) {
      body = this.replaceKeyPageJs(body);
    }

    // 步骤6: 处理<,page>页码模板
    ruleUrl = this.replacePageTemplate(ruleUrl, this.page);

    // 步骤6.5: 清理URL（去除换行符等无效字符）- 必须在resolveUrl之前
    // 否则以换行符开头的URL会被错误地识别为相对URL
    ruleUrl = this.cleanUrl(ruleUrl);

    // 步骤7: 解析相对URL
    let url = this.resolveUrl(ruleUrl);
    url = this.cleanUrl(url);
    if (optionJs && optionJs.trim().length > 0) {
      const optionJsResult = this.executeJsSimple(optionJs, url);
      if (optionJsResult !== null && optionJsResult.trim().length > 0) {
        url = this.cleanUrl(this.resolveUrl(optionJsResult));
      }
    }
    const encodedParts = LegadoUrlAnalyzer.buildEncodedRequestParts(url, method, body, charset, headers);

    return {
      url,
      requestUrl: encodedParts.requestUrl,
      method,
      headers,
      body,
      encodedBody: encodedParts.encodedBody,
      charset,
      useWebView,
      webJs,
      retry,
      responseType,
      serverId,
      webViewDelayTime,
      optionJs
    };
  }

  /**
   * 解析URL模板（异步版本，支持完整JS执行）
   */
  async analyzeUrlAsync(urlTemplate: string, key?: string, page?: number): Promise<ParsedUrlRequest> {
    // 保存参数
    if (key !== undefined) {
      this.key = key;
      this.variables.set('key', key);
      this.variables.set('encodedKey', encodeURIComponent(key));
    }
    if (page !== undefined) {
      this.page = page;
      this.variables.set('page', String(page));
    }

    let ruleUrl = urlTemplate;
    let method = RequestMethod.GET;
    let headers: Record<string, string> = {};
    let body: string | undefined;
    let charset: string | undefined;
    let useWebView = false;
    let webJs: string | undefined;
    let retry = 0;
    let responseType: string | undefined;
    let serverId = 0;
    let webViewDelayTime = 0;
    let optionJs: string | undefined;
    
    // 特殊处理: data:协议URL直接返回，不进行任何解析
    // data:URL用于在书源间传递数据，格式如: data:;base64,{json},{extra}
    if (urlTemplate.startsWith('data:')) {
      return {
        url: urlTemplate,
        method,
        headers,
        body,
        charset,
        useWebView,
        webJs,
        retry,
        responseType,
        serverId,
        webViewDelayTime,
        optionJs
      };
    }

    // 步骤1: 执行 @js: 和 <js></js> 格式的JS代码（异步）
    // Legado原版 AnalyzeUrl 的顺序是先 analyzeJs()，再 replaceKeyPageJs()，最后 analyzeUrl() 拆 URL option。
    ruleUrl = await this.analyzeJsAsync(ruleUrl);

    // 步骤2: 替换 {{...}} 内嵌JS/变量（异步）
    ruleUrl = await this.replaceKeyPageJsAsync(ruleUrl);

    // 步骤3: 分离URL和选项JSON
    // 参考Legado原版: paramPattern = Pattern.compile("\\s*,\\s*(?=\\{)")
    let optionStr = '';
    const separatorResult = this.findOptionSeparator(ruleUrl);
    if (separatorResult.found) {
      optionStr = ruleUrl.substring(separatorResult.index + 1).trim();
      ruleUrl = ruleUrl.substring(0, separatorResult.index).trim();
    }

    // 步骤4: 解析选项JSON（支持单引号格式）
    if (optionStr) {
      const option = this.parseUrlOption(optionStr);
      if (option) {
        const normalizedOption = this.normalizeUrlOption(option);
        if (normalizedOption.method) method = normalizedOption.method;
        if (normalizedOption.headers) headers = normalizedOption.headers;
        if (normalizedOption.body !== undefined) body = normalizedOption.body;
        if (normalizedOption.charset) charset = normalizedOption.charset;
        if (normalizedOption.useWebView) useWebView = true;
        if (normalizedOption.webJs) webJs = normalizedOption.webJs;
        if (normalizedOption.retry !== undefined) retry = normalizedOption.retry;
        if (normalizedOption.responseType !== undefined) responseType = normalizedOption.responseType;
        if (normalizedOption.serverId !== undefined) serverId = normalizedOption.serverId;
        if (normalizedOption.webViewDelayTime !== undefined) webViewDelayTime = normalizedOption.webViewDelayTime;
        if (normalizedOption.js) optionJs = normalizedOption.js;
      }
    }

    // 步骤5: 处理body中的变量
    if (body) {
      body = await this.replaceKeyPageJsAsync(body);
    }

    // 步骤6: 处理<,page>页码模板
    ruleUrl = this.replacePageTemplate(ruleUrl, this.page);

    // 步骤6.5: 清理URL（去除换行符等无效字符）- 必须在resolveUrl之前
    // 否则以换行符开头的URL会被错误地识别为相对URL
    ruleUrl = this.cleanUrl(ruleUrl);

    // 步骤7: 解析相对URL
    let url = this.resolveUrl(ruleUrl);
    url = this.cleanUrl(url);
    if (optionJs && optionJs.trim().length > 0) {
      const optionJsResult = await this.executeJsAsync(optionJs, url);
      if (optionJsResult.success && optionJsResult.result.trim().length > 0) {
        url = this.cleanUrl(this.resolveUrl(optionJsResult.result));
      } else if (!optionJsResult.success) {
        logger.warn(TAG, `URL选项js执行失败: ${optionJsResult.error || ''}`);
      }
    }
    const encodedParts = LegadoUrlAnalyzer.buildEncodedRequestParts(url, method, body, charset, headers);

    return {
      url,
      requestUrl: encodedParts.requestUrl,
      method,
      headers,
      body,
      encodedBody: encodedParts.encodedBody,
      charset,
      useWebView,
      webJs,
      retry,
      responseType,
      serverId,
      webViewDelayTime,
      optionJs
    };
  }

  /**
   * 执行 @js: 和 <js></js> 格式的JS代码（同步版本）
   * 参考: AnalyzeUrl.kt 的 analyzeJs()
   */
  private analyzeJs(ruleUrl: string): string {
    let result = ruleUrl;
    let start = 0;
    while (start < ruleUrl.length) {
      const match = ruleUrl.substring(start).match(JS_PATTERN);
      if (match === null) {
        break;
      }
      const matchStart = start + (match.index || 0);
      const matchEnd = matchStart + match[0].length;
      const prefix = ruleUrl.substring(start, matchStart).trim();
      if (prefix.length > 0) {
        result = prefix.replace('@result', result);
      }
      const jsCode = match[1] || match[2] || '';
      const jsResult = this.executeJsSimple(jsCode, result);
      if (jsResult === null) {
        logger.warn(TAG, `JS规则需要异步执行: ${jsCode.substring(0, 50)}...`);
        return result;
      }
      result = jsResult;
      start = matchEnd;
    }
    const suffix = ruleUrl.substring(start).trim();
    return suffix.length > 0 ? suffix.replace('@result', result) : result;
  }

  /**
   * 执行 @js: 和 <js></js> 格式的JS代码（异步版本）
   */
  private async analyzeJsAsync(ruleUrl: string): Promise<string> {
    let result = ruleUrl;
    let start = 0;
    while (start < ruleUrl.length) {
      const jsMatch = ruleUrl.substring(start).match(JS_PATTERN);
      if (!jsMatch) {
        break;
      }
      const matchStart = start + (jsMatch.index || 0);
      const matchEnd = matchStart + jsMatch[0].length;
      const prefix = ruleUrl.substring(start, matchStart).trim();
      if (prefix.length > 0) {
        result = prefix.replace('@result', result);
      }
      const jsCode = jsMatch[1] || jsMatch[2] || '';
      const jsResult = await this.executeJsAsync(jsCode, result);
      if (!jsResult.success) {
        logger.warn(TAG, `JS执行失败，保留上一个原版语义结果: ${jsCode.substring(0, Math.min(80, jsCode.length))}`);
        return result;
      }
      result = jsResult.result;
      start = matchEnd;
    }
    const suffix = ruleUrl.substring(start).trim();
    return suffix.length > 0 ? suffix.replace('@result', result) : result;
  }

  /**
   * 合并JS规则执行结果
   */
  private mergeJsRuleResult(beforeJs: string, jsResult: string, afterJs: string): string {
    if (!beforeJs) {
      return jsResult + afterJs;
    }

    if (beforeJs.includes('@result')) {
      return beforeJs.replace('@result', jsResult) + afterJs;
    }

    // JS结果已是完整URL时，优先直接使用JS结果
    if (jsResult.startsWith('http://') || jsResult.startsWith('https://') || jsResult.startsWith('data:')) {
      return jsResult + afterJs;
    }

    return beforeJs + jsResult + afterJs;
  }

  /**
   * 替换 {{...}} 内嵌JS/变量（同步版本）
   * 参考: AnalyzeUrl.kt 的 replaceKeyPageJs()
   */
  private replaceKeyPageJs(ruleUrl: string): string {
    let normalizedRuleUrl = this.replaceGetTokens(ruleUrl);
    if (!normalizedRuleUrl.includes('{{') || !normalizedRuleUrl.includes('}}')) {
      return normalizedRuleUrl;
    }

    return this.innerRule(normalizedRuleUrl, '{{', '}}', (expr: string): string => {
      // 尝试作为简单变量处理
      const trimmedExpr = expr.trim();
      
      // 检查是否是简单变量
      if (trimmedExpr === 'key') {
        return encodeURIComponent(this.key);
      }
      if (trimmedExpr === 'page') {
        return String(this.page);
      }
      if (this.isSourceUrlExpression(trimmedExpr)) {
        return this.sourceUrl || this.baseUrl;
      }
      if (this.variables.has(trimmedExpr)) {
        return this.variables.get(trimmedExpr) || '';
      }
      if (this.isUrlSideEffectExpression(trimmedExpr)) {
        return '';
      }

      // 尝试作为JS表达式执行
      const jsResult = this.executeJsSimple(trimmedExpr);
      if (jsResult !== null) {
        return jsResult;
      }

      // 无法处理，返回原始内容
      return `{{${expr}}}`;
    });
  }

  /**
   * 替换 {{...}} 内嵌JS/变量（异步版本）
   */
  private async replaceKeyPageJsAsync(ruleUrl: string): Promise<string> {
    let normalizedRuleUrl = this.replaceGetTokens(ruleUrl);
    if (!normalizedRuleUrl.includes('{{') || !normalizedRuleUrl.includes('}}')) {
      return normalizedRuleUrl;
    }

    return await this.innerRuleAsync(normalizedRuleUrl, '{{', '}}', async (expr: string): Promise<string> => {
      const trimmedExpr = expr.trim();
      
      // 检查是否是简单变量
      if (trimmedExpr === 'key') {
        return encodeURIComponent(this.key);
      }
      if (trimmedExpr === 'page') {
        return String(this.page);
      }
      if (this.isSourceUrlExpression(trimmedExpr)) {
        return this.sourceUrl || this.baseUrl;
      }
      if (this.variables.has(trimmedExpr)) {
        return this.variables.get(trimmedExpr) || '';
      }
      if (this.isUrlSideEffectExpression(trimmedExpr)) {
        const sideEffectResult = await this.executeJsAsync(trimmedExpr);
        if (sideEffectResult.success && sideEffectResult.result.trim().length > 0) {
          return sideEffectResult.result;
        }
        return '';
      }

      if (!this.isLikelyComplexJs(trimmedExpr)) {
        const simpleResult = this.executeJsSimple(trimmedExpr);
        if (simpleResult !== null) {
          return simpleResult;
        }
      }

      // 作为JS表达式执行
      const jsResult = await this.executeJsAsync(trimmedExpr);
      if (jsResult.success) {
        return jsResult.result;
      }

      // 无法执行时保留原模板，交给上层识别为URL规则未完整解析
      return `{{${expr}}}`;
    });
  }

  /**
   * 内嵌规则替换（同步版本）
   * 参考: RuleAnalyzer.kt 的 innerRule()
   */
  private innerRule(str: string, startStr: string, endStr: string, fr: (expr: string) => string): string {
    const result: string[] = [];
    let pos = 0;
    let startX = 0;

    while (pos < str.length) {
      const startIndex = str.indexOf(startStr, pos);
      if (startIndex === -1) {
        break;
      }

      const endIndex = str.indexOf(endStr, startIndex + startStr.length);
      if (endIndex === -1) {
        break;
      }

      // 提取内嵌表达式
      const expr = str.substring(startIndex + startStr.length, endIndex);
      const replacement = fr(expr);

      // 如果替换成功，拼接结果
      if (replacement !== `{{${expr}}}`) {
        result.push(str.substring(startX, startIndex));
        result.push(replacement);
        startX = endIndex + endStr.length;
      }

      pos = endIndex + endStr.length;
    }

    if (startX === 0) {
      return str;
    }

    result.push(str.substring(startX));
    return result.join('');
  }

  /**
   * 内嵌规则替换（异步版本）
   */
  private async innerRuleAsync(str: string, startStr: string, endStr: string, fr: (expr: string) => Promise<string>): Promise<string> {
    const result: string[] = [];
    let pos = 0;
    let startX = 0;

    while (pos < str.length) {
      const startIndex = str.indexOf(startStr, pos);
      if (startIndex === -1) {
        break;
      }

      const endIndex = str.indexOf(endStr, startIndex + startStr.length);
      if (endIndex === -1) {
        break;
      }

      const expr = str.substring(startIndex + startStr.length, endIndex);
      const replacement = await fr(expr);

      result.push(str.substring(startX, startIndex));
      result.push(replacement);
      startX = endIndex + endStr.length;
      pos = endIndex + endStr.length;
    }

    if (startX === 0) {
      return str;
    }

    result.push(str.substring(startX));
    return result.join('');
  }

  /**
   * 简单JS执行（同步，不依赖WebView）
   * 处理简单的字符串拼接、变量替换、数学表达式等
   */
  private executeJsSimple(jsCode: string, currentResult?: string): string | null {
    try {
      let code = jsCode.trim();
      const resultValue = currentResult !== undefined ? currentResult : (this.variables.get('result') || '');
      
      // 处理 cookie.removeCookie() - 这是一个副作用函数，直接返回空字符串
      // 书源中常用于清除cookie，但不影响URL生成
      if (code.includes('cookie.removeCookie') || code.includes('cookie.getCookie')) {
        // 提取cookie操作后面的实际URL生成代码
        // 通常格式: cookie.removeCookie(...)\nactualUrl 或 cookie.removeCookie(...);actualUrl
        const lines = code.split(/[;\n]/).filter(line => line.trim() !== '');
        for (let i = lines.length - 1; i >= 0; i--) {
          const line = lines[i].trim();
          // 跳过cookie操作行
          if (line.includes('cookie.') || line.startsWith('//')) {
            continue;
          }
          // 找到可能是URL的行
          if (line.startsWith('"') || line.startsWith("'") || line.startsWith('http') || line.includes('baseUrl')) {
            code = line;
            break;
          }
        }
        // 如果整个代码都是cookie操作，返回空字符串（不影响URL）
        if (code.includes('cookie.removeCookie') || code.includes('cookie.getCookie')) {
          return '';
        }
      }

      // 处理 source.key/source.bookSourceUrl/source.getKey() - 返回书源URL
      if (code.includes('source.getKey') || code.includes('source.key') || code.includes('source.bookSourceUrl')) {
        const sourceUrlValue = this.sourceUrl || this.baseUrl;
        code = code.replace(/source\.getKey\(\)/g, `"${sourceUrlValue}"`);
        code = code.replace(/source\.getKey\b/g, `"${sourceUrlValue}"`);
        code = code.replace(/source\.key\b/g, `"${sourceUrlValue}"`);
        code = code.replace(/source\.bookSourceUrl\b/g, `"${sourceUrlValue}"`);
      }

      // 处理简单的纯字符串
      if (/^["'][^"']*["']$/.test(code)) {
        return code.slice(1, -1);
      }

      // 处理 key 变量
      if (code === 'key') {
        return this.key;
      }

      // 处理 result 变量
      if (code === 'result') {
        return resultValue;
      }

      // 处理 page 变量
      if (code === 'page') {
        return String(this.page);
      }

      // 处理 parseInt(result) 以及四则运算组合（常见于bookId拼接）
      const parseIntOnlyMatch = code.match(/^parseInt\s*\(\s*result\s*(?:,\s*(\d+)\s*)?\)$/i);
      if (parseIntOnlyMatch) {
        const radix = parseIntOnlyMatch[1] ? parseInt(parseIntOnlyMatch[1]) : undefined;
        const parsedResult = radix ? parseInt(resultValue, radix) : parseInt(resultValue);
        if (!Number.isNaN(parsedResult)) {
          return String(parsedResult);
        }
      }

      const leftMathWithResult = code.match(/^(\d+)\s*([+\-*/])\s*parseInt\s*\(\s*result\s*(?:,\s*(\d+)\s*)?\)\s*$/i);
      if (leftMathWithResult) {
        const leftValue = parseInt(leftMathWithResult[1]);
        const operator = leftMathWithResult[2];
        const radix = leftMathWithResult[3] ? parseInt(leftMathWithResult[3]) : undefined;
        const parsedResult = radix ? parseInt(resultValue, radix) : parseInt(resultValue);
        if (!Number.isNaN(parsedResult)) {
          const mathResult = this.applySimpleArithmetic(leftValue, parsedResult, operator);
          if (mathResult !== null) {
            return String(mathResult);
          }
        }
      }

      const rightMathWithResult = code.match(/^parseInt\s*\(\s*result\s*(?:,\s*(\d+)\s*)?\)\s*([+\-*/])\s*(\d+)\s*$/i);
      if (rightMathWithResult) {
        const radix = rightMathWithResult[1] ? parseInt(rightMathWithResult[1]) : undefined;
        const operator = rightMathWithResult[2];
        const rightValue = parseInt(rightMathWithResult[3]);
        const parsedResult = radix ? parseInt(resultValue, radix) : parseInt(resultValue);
        if (!Number.isNaN(parsedResult)) {
          const mathResult = this.applySimpleArithmetic(parsedResult, rightValue, operator);
          if (mathResult !== null) {
            return String(mathResult);
          }
        }
      }

      // 处理简单数学表达式: page-1, page+1, page*10 等
      const mathMatch = code.match(/^page\s*([+\-*/])\s*(\d+)$/);
      if (mathMatch) {
        const operator = mathMatch[1];
        const operand = parseInt(mathMatch[2]);
        let result = this.page;
        switch (operator) {
          case '+': result = this.page + operand; break;
          case '-': result = this.page - operand; break;
          case '*': result = this.page * operand; break;
          case '/': result = Math.floor(this.page / operand); break;
        }
        return String(result);
      }

      // 处理 (page-1)*10 等复杂数学表达式
      const complexMathMatch = code.match(/^\(page\s*([+\-])\s*(\d+)\)\s*([*/])\s*(\d+)$/);
      if (complexMathMatch) {
        const op1 = complexMathMatch[1];
        const num1 = parseInt(complexMathMatch[2]);
        const op2 = complexMathMatch[3];
        const num2 = parseInt(complexMathMatch[4]);
        let intermediate = this.page;
        if (op1 === '+') intermediate = this.page + num1;
        else if (op1 === '-') intermediate = this.page - num1;
        let result = intermediate;
        if (op2 === '*') result = intermediate * num2;
        else if (op2 === '/') result = Math.floor(intermediate / num2);
        return String(result);
      }

      // 处理 encodeURI(key) 或 java.encodeURI(key, "gbk")
      const encodeMatch = code.match(/(?:java\.)?encodeURI\s*\(\s*key\s*(?:,\s*["']([^"']+)["']\s*)?\)/i);
      if (encodeMatch) {
        return LegadoUrlAnalyzer.encode(this.key, encodeMatch[1]);
      }

      // 处理 encodeURIComponent(key)
      const encodeCompMatch = code.match(/encodeURIComponent\s*\(\s*key\s*\)/i);
      if (encodeCompMatch) {
        return encodeURIComponent(this.key);
      }

      // 处理简单的字符串拼接: "xxx" + key + "yyy"
      if (code.includes('+') && !code.includes('function') && !code.includes('=>')) {
        let result = code;
        result = result.replace(/\bresult\b/g, JSON.stringify(resultValue));
        result = result.replace(/\bkey\b/g, `"${this.key}"`);
        result = result.replace(/\bpage\b/g, String(this.page));
        result = result.replace(/\bbaseUrl\b/g, `"${this.baseUrl}"`);
        
        // 尝试计算字符串拼接
        const parts = result.split('+').map(p => p.trim());
        let concatResult = '';
        let allStrings = true;
        
        for (const part of parts) {
          if (part.startsWith('"') && part.endsWith('"')) {
            concatResult += part.slice(1, -1);
          } else if (part.startsWith("'") && part.endsWith("'")) {
            concatResult += part.slice(1, -1);
          } else if (/^\d+$/.test(part)) {
            concatResult += part;
          } else {
            allStrings = false;
            break;
          }
        }
        
        if (allStrings) {
          return concatResult;
        }
      }

      // 无法简单处理
      return null;
    } catch (e) {
      logger.debug(TAG, `简单JS执行失败: ${String(e)}`);
      return null;
    }
  }

  private applySimpleArithmetic(left: number, right: number, operator: string): number | null {
    switch (operator) {
      case '+':
        return left + right;
      case '-':
        return left - right;
      case '*':
        return left * right;
      case '/':
        if (right === 0) {
          return null;
        }
        return left / right;
      default:
        return null;
    }
  }

  /**
   * 异步JS执行（强制使用LegadoJsEngine的Native JSVM）
   */
  private async executeJsAsync(jsCode: string, result?: string): Promise<JsExecutionOutcome> {
    // 直接使用JS引擎执行，不再使用简单执行绕过JSVM
    try {
      const jsEngine = getLegadoJsEngine();
      const activeJsLib = this.shouldLoadJsLibForUrlRule(jsCode) ? this.jsLib : '';
      const context: JsContext = this.buildJsContext(result, activeJsLib);

      // 直接传递jsCode，buildNativeScript会自动添加source对象
      let executeResult = await jsEngine.execute(jsCode, context);
      if (!activeJsLib && this.jsLib.trim().length > 0 &&
        executeResult.error && this.isMissingFunctionError(executeResult.error)) {
        logger.info(TAG, `JS执行缺少函数，加载jsLib重试: ${executeResult.error}`);
        const retryContext = this.buildJsContext(result, this.jsLib);
        executeResult = await jsEngine.execute(jsCode, retryContext);
      }
      this.syncVariablesFromRecord(executeResult.variables);
      this.syncSourceEffects(executeResult.sourceEffects);
      if (executeResult.success && !executeResult.error) {
        if (!(executeResult.result.trim().length === 0 && this.isLikelyComplexJs(jsCode))) {
          const successResult: JsExecutionOutcome = {
            success: true,
            result: executeResult.result,
            useSimpleFallback: false
          };
          return successResult;
        }
        logger.warn(TAG, `JS执行结果为空，转为降级求值: ${jsCode.substring(0, Math.min(80, jsCode.length))}`);
      }

      const nativeError = executeResult.error || 'native_execute_failed';
      logger.warn(TAG, `JS执行失败: ${nativeError}`);
      const fallbackResult = this.executeJsSimple(jsCode, result);
      if (fallbackResult !== null) {
        logger.debug(TAG, `JS执行降级为简单求值: ${jsCode.substring(0, Math.min(80, jsCode.length))}`);
        const fallbackSuccess: JsExecutionOutcome = {
          success: true,
          result: fallbackResult,
          useSimpleFallback: true
        };
        return fallbackSuccess;
      }

      const failedResult: JsExecutionOutcome = {
        success: false,
        result: '',
        error: nativeError,
        useSimpleFallback: false
      };
      return failedResult;
    } catch (e) {
      const exceptionError = String(e);
      logger.error(TAG, `JS执行异常: ${exceptionError}`);
      const fallbackResult = this.executeJsSimple(jsCode, result);
      if (fallbackResult !== null) {
        logger.debug(TAG, `JS执行异常后降级为简单求值: ${jsCode.substring(0, Math.min(80, jsCode.length))}`);
        const fallbackSuccess: JsExecutionOutcome = {
          success: true,
          result: fallbackResult,
          useSimpleFallback: true
        };
        return fallbackSuccess;
      }

      const failedResult: JsExecutionOutcome = {
        success: false,
        result: '',
        error: exceptionError,
        useSimpleFallback: false
      };
      return failedResult;
    }
  }

  private buildJsContext(result: string | undefined, jsLib: string): JsContext {
    const varsRecord: Record<string, string> = {};
    this.variables.forEach((value: string, key: string) => {
      varsRecord[key] = value;
    });
    varsRecord['sourceUrl'] = this.sourceUrl;

    const context: JsContext = {
      result: result,
      src: result,
      baseUrl: this.baseUrl,
      key: this.key,
      page: this.page,
      variables: varsRecord,
      jsLib: jsLib
    };
    return context;
  }

  private isMissingFunctionError(error: string): boolean {
    const lowerError = error.toLowerCase();
    return lowerError.includes('is not defined') ||
      lowerError.includes('not defined') ||
      lowerError.includes('is not a function') ||
      lowerError.includes('undefined is not a function');
  }

  private shouldLoadJsLibForUrlRule(jsCode: string): boolean {
    if (!this.jsLib || this.jsLib.trim().length <= 0) {
      return false;
    }

    let strippedCode = jsCode
      .replace(/"(?:\\.|[^"\\])*"/g, '')
      .replace(/'(?:\\.|[^'\\])*'/g, '')
      .replace(/`(?:\\.|[^`\\])*`/g, '')
      .replace(/\/\/[^\n\r]*/g, '')
      .replace(/\/\*[\s\S]*?\*\//g, '');

    const builtinObjects: string[] = [
      'source',
      'java',
      'cookie',
      'cache',
      'JSON',
      'String',
      'Number',
      'Date',
      'Math',
      'Array',
      'Object',
      'RegExp',
      'parseInt',
      'parseFloat',
      'isNaN',
      'encodeURI',
      'encodeURIComponent',
      'decodeURI',
      'decodeURIComponent',
      'console'
    ];

    for (let i = 0; i < builtinObjects.length; i++) {
      const name = builtinObjects[i];
      const pattern = new RegExp(`\\b${name}\\s*\\.\\s*[A-Za-z_$][0-9A-Za-z_$]*\\s*\\(`, 'g');
      strippedCode = strippedCode.replace(pattern, '');
    }

    const localDeclarationPattern = /\b(?:var|let|const|function)\s+([A-Za-z_$][0-9A-Za-z_$]*)/g;
    const localNames: string[] = [];
    let localMatch: RegExpExecArray | null = localDeclarationPattern.exec(strippedCode);
    while (localMatch) {
      localNames.push(localMatch[1]);
      localMatch = localDeclarationPattern.exec(strippedCode);
    }

    const functionCallPattern = /\b([A-Za-z_$][0-9A-Za-z_$]*)\s*\(/g;
    let callMatch: RegExpExecArray | null = functionCallPattern.exec(strippedCode);
    while (callMatch) {
      const name = callMatch[1];
      if (this.isObjectMethodCall(strippedCode, callMatch.index)) {
        callMatch = functionCallPattern.exec(strippedCode);
        continue;
      }
      if (builtinObjects.indexOf(name) < 0 &&
        localNames.indexOf(name) < 0 &&
        name !== 'if' &&
        name !== 'for' &&
        name !== 'while' &&
        name !== 'switch' &&
        name !== 'function' &&
        name !== 'catch') {
        return true;
      }
      callMatch = functionCallPattern.exec(strippedCode);
    }

    return false;
  }

  private isObjectMethodCall(code: string, callIndex: number): boolean {
    let index = callIndex - 1;
    while (index >= 0) {
      const char = code.charAt(index);
      if (char !== ' ' && char !== '\t' && char !== '\n' && char !== '\r') {
        return char === '.';
      }
      index--;
    }
    return false;
  }

  private isUrlSideEffectExpression(expr: string): boolean {
    const trimmed = expr.trim();
    return trimmed.includes('cookie.removeCookie') ||
      trimmed.includes('cookie.setCookie') ||
      trimmed.includes('java.put(') ||
      trimmed.includes('java.putCache(') ||
      trimmed.includes('java.deleteCache(');
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
    }
    if (effects.removeLoginHeader === true) {
      this.sourceEffects.removeLoginHeader = true;
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
      }
      if (existing.length > 0) {
        this.sourceEffects.data = existing;
      }
    }
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

  private isLikelyComplexJs(jsCode: string): boolean {
    const code = jsCode.trim();
    if (code.length > 120) {
      return true;
    }
    return code.includes('\n') ||
      code.includes(';') ||
      code.includes('var ') ||
      code.includes('let ') ||
      code.includes('const ') ||
      code.includes('function') ||
      code.includes('=>') ||
      code.includes('Date.') ||
      code.includes('java.');
  }


  /**
   * 替换页码模板
   * 支持格式:
   * - <,{{page}}> - 第一页为空，其他页为页码
   * - <page,1,2,3> - 根据页码选择对应值
   * - {{page}} - 直接替换为页码
   */
  private replacePageTemplate(url: string, page: number): string {
    // 处理 <page,1,2,3> 格式 - 根据页码选择值
    url = url.replace(/<page,([^>]+)>/gi, (match: string, content: string): string => {
      const parts = content.split(',').map(p => p.trim());
      if (page <= parts.length) {
        return parts[page - 1];
      }
      return parts[parts.length - 1]; // 超出范围使用最后一个值
    });
    
    // 处理 <,{{page}}> 格式 - 第一页为空
    url = url.replace(/<([^>]*)>/g, (match: string, content: string): string => {
      // 跳过已处理的page格式
      if (content.toLowerCase().startsWith('page,')) {
        return match;
      }
      
      const parts = content.split(',');
      if (parts.length >= 2) {
        // 第一页使用第一个值，其他页使用第二个值
        if (page === 1) {
          return parts[0];
        } else {
          let pageStr = parts[1];
          pageStr = pageStr.replace(/\{\{page\}\}/g, String(page));
          pageStr = pageStr.replace(/\bpage\b/g, String(page));
          return pageStr;
        }
      }
      return match;
    });
    
    // 处理直接的 {{page}} 替换
    url = url.replace(/\{\{page\}\}/g, String(page));
    
    return url;
  }
  
  /**
   * 解析相对URL为绝对URL
   */
  private resolveUrl(url: string): string {
    if (!url) {
      return '';
    }

    // 已经是绝对URL
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    
    // data:协议URL，直接返回（用于传递数据）
    if (url.startsWith('data:')) {
      return url;
    }

    // 协议相对URL
    if (url.startsWith('//')) {
      return 'https:' + url;
    }

    if (!this.baseUrl) {
      return url;
    }

    // 从根路径开始
    if (url.startsWith('/')) {
      const match = this.baseUrl.match(/^(https?:\/\/[^\/]+)/);
      if (match) {
        return match[1] + url;
      }
    }

    // 相对当前路径
    let base = this.baseUrl;
    if (!base.endsWith('/')) {
      const lastSlash = base.lastIndexOf('/');
      if (lastSlash > 8) { // 跳过 https://
        base = base.substring(0, lastSlash + 1);
      } else {
        base = base + '/';
      }
    }
    return base + url;
  }

  /**
   * URL编码
   */
  static encode(str: string, charset?: string): string {
    try {
      return encodeURIComponent(str);
    } catch (e) {
      return str;
    }
  }

  /**
   * URL解码
   */
  static decode(str: string): string {
    try {
      return decodeURIComponent(str);
    } catch (e) {
      return str;
    }
  }

  private static buildEncodedRequestParts(
    url: string,
    method: RequestMethod,
    body: string | undefined,
    charset: string | undefined,
    headers: Record<string, string>
  ): EncodedRequestParts {
    const result: EncodedRequestParts = {};
    if (method === RequestMethod.GET) {
      result.requestUrl = LegadoUrlAnalyzer.buildEncodedGetUrl(url, charset);
      return result;
    }

    result.requestUrl = url;
    if (body !== undefined) {
      result.encodedBody = LegadoUrlAnalyzer.shouldEncodePostForm(body, headers)
        ? LegadoUrlAnalyzer.encodeParams(body, charset, false)
        : body;
    }
    return result;
  }

  private static buildEncodedGetUrl(url: string, charset?: string): string {
    const queryStart = url.indexOf('?');
    if (queryStart < 0) {
      return url;
    }
    const hashStart = url.indexOf('#', queryStart + 1);
    const path = url.substring(0, queryStart);
    const query = hashStart >= 0 ? url.substring(queryStart + 1, hashStart) : url.substring(queryStart + 1);
    const fragment = hashStart >= 0 ? url.substring(hashStart) : '';
    if (query.length <= 0) {
      return url;
    }
    const encodedQuery = LegadoUrlAnalyzer.encodeParams(query, charset, true);
    return `${path}?${encodedQuery}${fragment}`;
  }

  private static shouldEncodePostForm(body: string, headers: Record<string, string>): boolean {
    const trimmedBody = body.trim();
    if (trimmedBody.length <= 0) {
      return true;
    }
    if (LegadoUrlAnalyzer.isJsonBody(trimmedBody) || LegadoUrlAnalyzer.isXmlBody(trimmedBody)) {
      return false;
    }
    return !LegadoUrlAnalyzer.hasHeader(headers, 'Content-Type');
  }

  private static isJsonBody(value: string): boolean {
    return (value.startsWith('{') && value.endsWith('}')) ||
      (value.startsWith('[') && value.endsWith(']'));
  }

  private static isXmlBody(value: string): boolean {
    return value.startsWith('<') && value.endsWith('>');
  }

  private static hasHeader(headers: Record<string, string>, headerName: string): boolean {
    const target = headerName.toLowerCase();
    const keys = Object.keys(headers);
    for (let i = 0; i < keys.length; i++) {
      if (keys[i].toLowerCase() === target) {
        return true;
      }
    }
    return false;
  }

  private static encodeParams(params: string, charset: string | undefined, isQuery: boolean): string {
    const normalizedCharset = charset ? charset.trim().toLowerCase() : '';
    const checkEncoded = normalizedCharset.length <= 0;
    if (isQuery && normalizedCharset !== 'escape' && LegadoUrlAnalyzer.isEncodedQuery(params)) {
      return params;
    }
    if (isQuery) {
      return LegadoUrlAnalyzer.percentEncodeByAllowedSet(params, normalizedCharset, true, checkEncoded);
    }

    const parts: string[] = [];
    let pos = 0;
    while (pos <= params.length) {
      let ampOffset = params.indexOf('&', pos);
      if (ampOffset < 0) {
        ampOffset = params.length;
      }
      const eqOffset = params.indexOf('=', pos);
      if (eqOffset < 0 || eqOffset > ampOffset) {
        const keyOnly = params.substring(pos, ampOffset);
        parts.push(LegadoUrlAnalyzer.encodeFormComponent(keyOnly, normalizedCharset, checkEncoded));
      } else {
        const key = params.substring(pos, eqOffset);
        const value = params.substring(eqOffset + 1, ampOffset);
        parts.push(`${LegadoUrlAnalyzer.encodeFormComponent(key, normalizedCharset, checkEncoded)}=${LegadoUrlAnalyzer.encodeFormComponent(value, normalizedCharset, checkEncoded)}`);
      }
      if (ampOffset >= params.length) {
        break;
      }
      pos = ampOffset + 1;
    }
    return parts.join('&');
  }

  private static encodeFormComponent(value: string, charset: string, checkEncoded: boolean): string {
    if (checkEncoded && LegadoUrlAnalyzer.isEncodedForm(value)) {
      return value;
    }
    if (charset === 'escape') {
      return LegadoUrlAnalyzer.escapeEncode(value);
    }
    return LegadoUrlAnalyzer.percentEncodeByAllowedSet(value, charset, false, false);
  }

  private static percentEncodeByAllowedSet(
    value: string,
    charset: string,
    isQuery: boolean,
    checkEncoded: boolean
  ): string {
    const result: string[] = [];
    let i = 0;
    while (i < value.length) {
      const char = value.charAt(i);
      if (checkEncoded && char === '%' && i + 2 < value.length &&
        LegadoUrlAnalyzer.isHexChar(value.charAt(i + 1)) && LegadoUrlAnalyzer.isHexChar(value.charAt(i + 2))) {
        result.push(value.substring(i, i + 3));
        i += 3;
        continue;
      }
      if (LegadoUrlAnalyzer.isAllowedUrlChar(char, isQuery)) {
        result.push(char);
      } else if (!isQuery && char === ' ') {
        result.push('+');
      } else {
        result.push(LegadoUrlAnalyzer.percentEncodeChar(char, charset));
      }
      i++;
    }
    return result.join('');
  }

  private static percentEncodeChar(char: string, charset: string): string {
    if (charset === 'escape') {
      return LegadoUrlAnalyzer.escapeEncode(char);
    }
    try {
      const encoder = charset.length > 0 ? new util.TextEncoder(charset) : new util.TextEncoder('utf-8');
      const encoded = encoder.encodeInto(char);
      const bytes = new Uint8Array(encoded.buffer);
      const parts: string[] = [];
      for (let i = 0; i < bytes.length; i++) {
        parts.push(`%${bytes[i].toString(16).toUpperCase().padStart(2, '0')}`);
      }
      return parts.join('');
    } catch (error) {
      logger.warn(TAG, `按${charset || 'utf-8'}编码URL参数失败，回退encodeURIComponent: ${String(error)}`);
      return encodeURIComponent(char);
    }
  }

  private static isAllowedUrlChar(char: string, isQuery: boolean): boolean {
    const code = char.charCodeAt(0);
    if ((code >= 0x30 && code <= 0x39) ||
      (code >= 0x41 && code <= 0x5A) ||
      (code >= 0x61 && code <= 0x7A)) {
      return true;
    }
    const allowed = isQuery ? "!$&()*+,-./:;=?@[\\]^_`{|}~" : "*-._";
    return allowed.indexOf(char) >= 0;
  }

  private static isEncodedQuery(value: string): boolean {
    for (let i = 0; i < value.length; i++) {
      const char = value.charAt(i);
      if (LegadoUrlAnalyzer.isAllowedUrlChar(char, true)) {
        continue;
      }
      if (char === '%' && i + 2 < value.length &&
        LegadoUrlAnalyzer.isHexChar(value.charAt(i + 1)) && LegadoUrlAnalyzer.isHexChar(value.charAt(i + 2))) {
        i += 2;
        continue;
      }
      return false;
    }
    return true;
  }

  private static isEncodedForm(value: string): boolean {
    for (let i = 0; i < value.length; i++) {
      const char = value.charAt(i);
      if (LegadoUrlAnalyzer.isAllowedUrlChar(char, false)) {
        continue;
      }
      if (char === '%' && i + 2 < value.length &&
        LegadoUrlAnalyzer.isHexChar(value.charAt(i + 1)) && LegadoUrlAnalyzer.isHexChar(value.charAt(i + 2))) {
        i += 2;
        continue;
      }
      return false;
    }
    return true;
  }

  private static isHexChar(char: string): boolean {
    return /^[0-9a-fA-F]$/.test(char);
  }

  private static escapeEncode(value: string): string {
    const result: string[] = [];
    for (let i = 0; i < value.length; i++) {
      const code = value.charCodeAt(i);
      if ((code >= 48 && code <= 57) || (code >= 65 && code <= 90) || (code >= 97 && code <= 122)) {
        result.push(value.charAt(i));
        continue;
      }
      if (code < 16) {
        result.push(`%0${code.toString(16)}`);
      } else if (code < 256) {
        result.push(`%${code.toString(16)}`);
      } else {
        result.push(`%u${code.toString(16)}`);
      }
    }
    return result.join('');
  }

  private replaceGetTokens(input: string): string {
    if (!input.includes('@get:')) {
      return input;
    }
    return input.replace(/@get:\{([^}]+)\}/gi, (_match: string, key: string): string => {
      const trimmedKey = key.trim();
      if (trimmedKey.length <= 0) {
        return '';
      }
      if (trimmedKey === 'key') {
        return this.key;
      }
      if (trimmedKey === 'page') {
        return String(this.page);
      }
      if (trimmedKey === 'baseUrl') {
        return this.baseUrl;
      }
      if (trimmedKey === 'sourceUrl') {
        return this.sourceUrl || this.baseUrl;
      }
      return this.variables.get(trimmedKey) || '';
    });
  }

  private isSourceUrlExpression(expr: string): boolean {
    return expr === 'source.key' ||
      expr === 'source.bookSourceUrl' ||
      expr === 'source.getKey()' ||
      expr === 'source.getKey';
  }

  private normalizeUrlOption(option: LegadoUrlOption): NormalizedUrlOption {
    const normalized: NormalizedUrlOption = {};
    const methodText = option.method ? option.method.trim().toUpperCase() : '';
    let bodyValue: LegadoUrlOptionBody | undefined = option.body;

    if ((bodyValue === undefined || bodyValue === null) && option.data !== undefined && option.data !== null) {
      bodyValue = this.stringifyOptionData(option.data);
    }
    const bodyText = this.normalizeUrlOptionBody(bodyValue);

    if (methodText === 'POST' || (methodText.length <= 0 && bodyText !== undefined)) {
      normalized.method = RequestMethod.POST;
    }

    const mergedHeaders: Record<string, string> = {};
    this.mergeHeaders(mergedHeaders, option.headers);
    this.mergeHeaders(mergedHeaders, option.header);
    if (Object.keys(mergedHeaders).length > 0) {
      normalized.headers = mergedHeaders;
    }

    if (bodyText !== undefined && bodyText !== null) {
      normalized.body = bodyText;
    }
    if (option.charset) normalized.charset = option.charset;
    if (option.webView) normalized.useWebView = true;
    if (option.webJs) normalized.webJs = option.webJs;
    if (option.retry !== undefined) normalized.retry = option.retry;
    if (option.type !== undefined) normalized.responseType = option.type;
    if (option.serverID !== undefined && Number.isFinite(option.serverID)) normalized.serverId = option.serverID;
    if (option.webViewDelayTime !== undefined && Number.isFinite(option.webViewDelayTime)) {
      normalized.webViewDelayTime = Math.max(0, option.webViewDelayTime);
    }
    if (option.js) normalized.js = option.js;
    return normalized;
  }

  /**
   * AnalyzeUrl.UrlOption.getBody() in the pinned Legado implementation returns
   * the original text for string values and GSON JSON for object/array values.
   * Preserve that distinction before template substitution reaches the request
   * planner; treating an object as a string otherwise fails at `.replace()`.
   */
  private normalizeUrlOptionBody(value: LegadoUrlOptionBody | undefined | null): string | undefined {
    if (value === undefined || value === null) {
      return undefined;
    }
    if (typeof value === 'string') {
      return value;
    }
    const serialized = SafeUtils.stringifyJson(value, '');
    if (serialized.length <= 0) {
      logger.warn(TAG, 'LEGADO_URL_OPTION_BODY_SERIALIZATION_FAILED');
      return undefined;
    }
    return serialized;
  }

  private mergeHeaders(target: Record<string, string>, source?: LegadoHeaderOption): void {
    if (!source) {
      return;
    }
    const normalized = this.normalizeHeaderOption(source);
    if (!normalized) {
      return;
    }
    const keys = Object.keys(normalized);
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i];
      const value = normalized[key];
      if (value !== undefined && value !== null) {
        target[key] = String(value);
      }
    }
  }

  private normalizeHeaderOption(source: LegadoHeaderOption): Record<string, string> | undefined {
    if (typeof source !== 'string') {
      return source;
    }
    const trimmed = source.trim();
    if (trimmed.length <= 0) {
      return undefined;
    }

    const parsed = this.tryParseHeaderRecord(trimmed);
    if (parsed !== undefined) {
      return parsed;
    }

    const fixedHeader = trimmed
      .replace(/([{,]\s*)([a-zA-Z_$][a-zA-Z0-9_$-]*)\s*:/g, '$1"$2":')
      .replace(/([{,]\s*)'([^']+)'\s*:/g, '$1"$2":')
      .replace(/:\s*'([^'\\]*(?:\\.[^'\\]*)*)'/g, (match: string, value: string): string => {
        const escapedValue = value.replace(/"/g, '\\"');
        return `:"${escapedValue}"`;
      });
    const fixedParsed = this.tryParseHeaderRecord(fixedHeader);
    if (fixedParsed !== undefined) {
      return fixedParsed;
    }

    return this.parseHeaderPairs(trimmed);
  }

  private tryParseHeaderRecord(headerJson: string): Record<string, string> | undefined {
    const parsed = SafeUtils.parseObj<Record<string, Object>>(headerJson);
    if (parsed === null || parsed === undefined || typeof parsed !== 'object' || Array.isArray(parsed)) {
      return undefined;
    }
    const keys = Object.keys(parsed);
    if (keys.length <= 0) {
      return undefined;
    }
    const headers: Record<string, string> = {};
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i].trim();
      const value = parsed[key];
      if (key.length > 0 && value !== undefined && value !== null) {
        headers[key] = String(value);
      }
    }
    return Object.keys(headers).length > 0 ? headers : undefined;
  }

  private parseHeaderPairs(headerText: string): Record<string, string> | undefined {
    let body = headerText.trim();
    if (body.startsWith('{') && body.endsWith('}')) {
      body = body.substring(1, body.length - 1);
    }
    const headers: Record<string, string> = {};
    const pairs = body.split(',');
    for (let i = 0; i < pairs.length; i++) {
      const pair = pairs[i].trim();
      const splitIndex = pair.indexOf(':');
      if (splitIndex <= 0) {
        continue;
      }
      const key = this.trimHeaderToken(pair.substring(0, splitIndex));
      const value = this.trimHeaderToken(pair.substring(splitIndex + 1));
      if (key.length > 0 && value.length > 0) {
        headers[key] = value;
      }
    }
    return Object.keys(headers).length > 0 ? headers : undefined;
  }

  private trimHeaderToken(value: string): string {
    let result = value.trim();
    if (result.length >= 2) {
      const first = result.charAt(0);
      const last = result.charAt(result.length - 1);
      if ((first === '"' && last === '"') || (first === '\'' && last === '\'')) {
        result = result.substring(1, result.length - 1).trim();
      }
    }
    return result;
  }

  private stringifyOptionData(data: string | Record<string, string>): string {
    if (typeof data === 'string') {
      return data;
    }
    const pairs: string[] = [];
    const keys = Object.keys(data);
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i];
      const value = data[key];
      pairs.push(`${key}=${value}`);
    }
    return pairs.join('&');
  }

  /**
   * 解析URL选项JSON（宽松模式）
   * 参考Legado原版GSON宽松解析，支持以下非标准格式：
   * 1. 无引号键名: {method: "post"} 
   * 2. 单引号: {'method': 'post'}
   * 3. 尾部逗号: {method: "post",}
   * 4. 注释: {method: "post" ...comment... }
   */
  private parseUrlOption(optionStr: string): LegadoUrlOption | null {
    if (!optionStr || !optionStr.trim()) {
      return null;
    }
    
    let jsonStr = optionStr.trim();
    
    const strictOption = this.tryParseUrlOptionJson(jsonStr);
    if (strictOption !== null) {
      return strictOption;
    }
    
    // 步骤2: 宽松JSON修复
    try {
      let fixedJson = jsonStr;
      
      // 2.1 移除JavaScript注释
      // 移除单行注释 // ...
      fixedJson = fixedJson.replace(/\/\/[^\n]*/g, '');
      // 移除多行注释 /* ... */
      fixedJson = fixedJson.replace(/\/\*[\s\S]*?\*\//g, '');
      
      // 2.2 处理无引号的键名: {method: "post"} -> {"method": "post"}
      // 匹配 { 或 , 后面跟着的无引号键名
      fixedJson = fixedJson.replace(/([{,]\s*)([a-zA-Z_$][a-zA-Z0-9_$]*)\s*:/g, '$1"$2":');
      
      // 2.3 处理单引号的键名: {'method': 'post'} -> {"method": "post"}
      fixedJson = fixedJson.replace(/'([^'\\]*(?:\\.[^'\\]*)*)'\s*:/g, '"$1":');
      
      // 2.4 处理单引号的字符串值: "key": 'value' -> "key": "value"
      // 需要小心处理值中包含双引号的情况
      fixedJson = fixedJson.replace(/:\s*'([^'\\]*(?:\\.[^'\\]*)*)'/g, (match: string, value: string): string => {
        // 转义值中的双引号
        const escapedValue = value.replace(/"/g, '\\"');
        return `: "${escapedValue}"`;
      });
      
      // 2.5 移除尾部逗号: {a: 1,} -> {a: 1}
      fixedJson = fixedJson.replace(/,(\s*[}\]])/g, '$1');
      
      // 2.6 处理布尔值和null（确保小写）
      fixedJson = fixedJson.replace(/:\s*True\b/gi, ': true');
      fixedJson = fixedJson.replace(/:\s*False\b/gi, ': false');
      fixedJson = fixedJson.replace(/:\s*None\b/gi, ': null');
      fixedJson = fixedJson.replace(/:\s*Null\b/gi, ': null');
      
      logger.debug(TAG, `宽松JSON修复: 原始=${optionStr.substring(0, 100)}, 修复后=${fixedJson.substring(0, 100)}`);
      
      const fixedOption = this.tryParseUrlOptionJson(fixedJson);
      if (fixedOption !== null) {
        return fixedOption;
      }
      return this.manualParseUrlOption(jsonStr);
    } catch (e2) {
      // 步骤3: 如果还是失败，尝试手动解析关键字段
      try {
        return this.manualParseUrlOption(jsonStr);
      } catch (e3) {
        logger.warn(TAG, `解析URL选项失败: ${optionStr}`);
        return null;
      }
    }
  }

  private tryParseUrlOptionJson(jsonStr: string): LegadoUrlOption | null {
    const parsed: LegadoUrlOption = SafeUtils.parseObj<LegadoUrlOption>(jsonStr);
    if (parsed === null || parsed === undefined || typeof parsed !== 'object' || Array.isArray(parsed)) {
      return null;
    }
    if (!this.hasUrlOptionField(parsed) && jsonStr.trim() !== '{}') {
      return null;
    }
    return parsed;
  }

  private hasUrlOptionField(option: LegadoUrlOption): boolean {
    return option.method !== undefined ||
      option.charset !== undefined ||
      option.headers !== undefined ||
      option.header !== undefined ||
      option.body !== undefined ||
      option.data !== undefined ||
      option.retry !== undefined ||
      option.type !== undefined ||
      option.webView !== undefined ||
      option.webJs !== undefined ||
      option.js !== undefined ||
      option.serverID !== undefined ||
      option.webViewDelayTime !== undefined;
  }
  
  /**
   * 手动解析URL选项（最后的回退方案）
   * 当JSON解析完全失败时，尝试用正则提取关键字段
   */
  private manualParseUrlOption(optionStr: string): LegadoUrlOption | null {
    const option: LegadoUrlOption = {
      method: undefined,
      charset: undefined,
      headers: undefined,
      body: undefined,
      retry: undefined,
      type: undefined,
      webView: undefined,
      webJs: undefined,
      js: undefined,
      serverID: undefined,
      webViewDelayTime: undefined
    };
    
    // 提取method字段
    const methodMatch = optionStr.match(/method\s*[:=]\s*["']?(\w+)["']?/i);
    if (methodMatch) {
      option.method = methodMatch[1];
    }
    
    // 提取body字段 - 支持多种格式
    // body: "xxx" 或 body: 'xxx' 或 body: xxx
    let bodyMatch = optionStr.match(/body\s*[:=]\s*"([^"]*)"/i);
    if (!bodyMatch) {
      bodyMatch = optionStr.match(/body\s*[:=]\s*'([^']*)'/i);
    }
    if (!bodyMatch) {
      // 无引号的body，匹配到下一个逗号或}
      bodyMatch = optionStr.match(/body\s*[:=]\s*([^,}"']+)/i);
    }
    if (bodyMatch) {
      option.body = bodyMatch[1].trim();
    }
    if (!option.body) {
      let dataMatch = optionStr.match(/data\s*[:=]\s*"([^"]*)"/i);
      if (!dataMatch) {
        dataMatch = optionStr.match(/data\s*[:=]\s*'([^']*)'/i);
      }
      if (!dataMatch) {
        dataMatch = optionStr.match(/data\s*[:=]\s*([^,}"']+)/i);
      }
      if (dataMatch) {
        option.data = dataMatch[1].trim();
      }
    }
    
    // 提取charset字段
    const charsetMatch = optionStr.match(/charset\s*[:=]\s*["']?([^"',}\s]+)["']?/i);
    if (charsetMatch) {
      option.charset = charsetMatch[1];
    }
    
    // 提取webView字段
    const webViewMatch = optionStr.match(/webView\s*[:=]\s*["']?(true|false|\d+)["']?/i);
    if (webViewMatch) {
      option.webView = webViewMatch[1].toLowerCase() === 'true' || webViewMatch[1] === '1';
    }
    
    // 提取webJs字段
    const webJsMatch = optionStr.match(/webJs\s*[:=]\s*["']([^"']*)["']/i);
    if (webJsMatch) {
      option.webJs = webJsMatch[1];
    }
    
    // 提取retry字段
    const retryMatch = optionStr.match(/retry\s*[:=]\s*["']?(\d+)["']?/i);
    if (retryMatch) {
      option.retry = parseInt(retryMatch[1]);
    }
    
    // 提取headers/header字段（复杂对象，尝试提取）
    const headersMatch = optionStr.match(/(?:headers|header)\s*[:=]\s*(\{[^}]*\})/i);
    if (headersMatch) {
      try {
        // 递归修复headers的JSON
        let headersJson = headersMatch[1];
        headersJson = headersJson.replace(/([{,]\s*)([a-zA-Z_$][a-zA-Z0-9_$-]*)\s*:/g, '$1"$2":');
        headersJson = headersJson.replace(/'([^'\\]*)'/g, '"$1"');
        option.headers = SafeUtils.parseObj(headersJson) as Record<string, string>;
      } catch (e) {
        // 忽略headers解析失败
      }
    }
    
    // 如果至少提取到了method或body，认为解析成功
    if (option.method || option.body || option.data) {
      const bodyForLog = this.normalizeUrlOptionBody(option.body);
      logger.debug(TAG, `手动解析URL选项成功: method=${option.method}, body=${bodyForLog?.substring(0, 50)}`);
      return option;
    }
    
    return null;
  }

  /**
   * 查找URL和选项JSON之间的分隔符位置
   * 参考Legado原版: paramPattern = Pattern.compile("\\s*,\\s*(?=\\{)")
   * 
   * 需要正确处理以下情况：
   * 1. URL中可能包含逗号（如查询参数）
   * 2. JSON选项以{开头
   * 3. 需要找到最后一个有效的分隔符（逗号后紧跟{）
   */
  /**
   * Splits a completed Legado URL expression into its URL and trailing option
   * JSON boundary. Rule extraction uses this before request dispatch because
   * original Legado keeps URL options on a SearchBook until the next workflow.
   */
  findOptionSeparator(url: string): OptionSeparatorResult {
    if (!url || !url.includes(',')) {
      const result: OptionSeparatorResult = { found: false, index: -1 };
      return result;
    }
    
    // 从后向前查找 ,{ 模式
    // 这样可以正确处理URL中包含逗号的情况
    let pos = url.length - 1;
    let braceDepth = 0;
    let inString = false;
    let stringChar = '';
    
    // 首先检查是否以}结尾（表示有JSON选项）
    const trimmed = url.trimEnd();
    if (!trimmed.endsWith('}')) {
      const result: OptionSeparatorResult = { found: false, index: -1 };
      return result;
    }
    
    // 从后向前扫描，找到匹配的{
    for (let i = trimmed.length - 1; i >= 0; i--) {
      const char = trimmed[i];
      const prevChar = i > 0 ? trimmed[i - 1] : '';
      
      // 处理字符串（跳过字符串内的字符）
      if ((char === '"' || char === "'") && prevChar !== '\\') {
        if (inString && char === stringChar) {
          inString = false;
        } else if (!inString) {
          inString = true;
          stringChar = char;
        }
        continue;
      }
      
      if (inString) continue;
      
      // 计算大括号深度
      if (char === '}') {
        braceDepth++;
      } else if (char === '{') {
        braceDepth--;
        
        // 当braceDepth变为0时，找到了JSON的开始位置
        if (braceDepth === 0) {
          // 向前查找逗号
          let commaIndex = i - 1;
          while (commaIndex >= 0 && /\s/.test(trimmed[commaIndex])) {
            commaIndex--;
          }
          
          if (commaIndex >= 0 && trimmed[commaIndex] === ',') {
            // 找到分隔符，返回逗号的位置
            const result: OptionSeparatorResult = { found: true, index: commaIndex };
            return result;
          }
          
          // 没有找到逗号，可能整个字符串就是JSON
          const notFoundResult: OptionSeparatorResult = { found: false, index: -1 };
          return notFoundResult;
        }
      }
    }
    
    const finalResult: OptionSeparatorResult = { found: false, index: -1 };
    return finalResult;
  }

  /**
   * 清理URL（去除换行符、多余空格等无效字符）
   */
  private cleanUrl(url: string): string {
    if (!url) return '';
    
    // 去除换行符和回车符
    let cleaned = url.replace(/[\r\n]/g, '');
    // 去除首尾空格
    cleaned = cleaned.trim();
    // 去除URL中的多余空格
    cleaned = cleaned.replace(/\s+/g, '');
    // 修复规则拼接导致的尾部脏字符，如 https://lnovel.tw/]
    if (cleaned.endsWith('/]') || cleaned.endsWith('/］')) {
      cleaned = cleaned.substring(0, cleaned.length - 1);
    }
    
    return cleaned;
  }
}
