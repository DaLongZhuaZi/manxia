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

import { logger } from '../../Utils/Logger';
import { LegadoUrlOption } from './LegadoSourceTypes';
import { getLegadoJsEngine, JsContext } from './LegadoJsEngine';

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
  method: RequestMethod;
  headers: Record<string, string>;
  body?: string;
  charset?: string;
  useWebView?: boolean;
  webJs?: string;
  retry?: number;
}

/**
 * JS规则模式 - 匹配 @js: 和 <js></js>
 * 参考: AppPattern.kt
 */
const JS_PATTERN = /<js>([\s\S]*?)<\/js>|@js:([\s\S]*)/i;

/**
 * URL选项分隔符查找结果
 */
interface OptionSeparatorResult {
  found: boolean;
  index: number;
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

  constructor(baseUrl?: string, sourceUrl?: string) {
    if (baseUrl) {
      this.baseUrl = baseUrl;
    }
    if (sourceUrl) {
      this.sourceUrl = sourceUrl;
    }
  }

  /**
   * 设置基础URL
   */
  setBaseUrl(baseUrl: string): LegadoUrlAnalyzer {
    this.baseUrl = baseUrl;
    return this;
  }

  /**
   * 设置变量
   */
  setVariable(key: string, value: string): LegadoUrlAnalyzer {
    this.variables.set(key, value);
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
        retry
      };
    }

    // 步骤1: 分离URL和选项JSON（在JS执行之前）
    // 参考Legado原版: paramPattern = Pattern.compile("\\s*,\\s*(?=\\{)")
    // 使用正向前瞻匹配逗号后紧跟{的位置
    let optionStr = '';
    const separatorResult = this.findOptionSeparator(ruleUrl);
    if (separatorResult.found) {
      optionStr = ruleUrl.substring(separatorResult.index + 1).trim();
      ruleUrl = ruleUrl.substring(0, separatorResult.index).trim();
    }

    // 步骤2: 执行 @js: 和 <js></js> 格式的JS代码
    ruleUrl = this.analyzeJs(ruleUrl);

    // 步骤3: 替换 {{...}} 内嵌JS/变量
    ruleUrl = this.replaceKeyPageJs(ruleUrl);
    
    // 步骤3.5: 再次检查JS执行结果是否包含选项JSON
    const postJsSeparatorResult = this.findOptionSeparator(ruleUrl);
    if (postJsSeparatorResult.found) {
      const postJsOptionStr = ruleUrl.substring(postJsSeparatorResult.index + 1).trim();
      ruleUrl = ruleUrl.substring(0, postJsSeparatorResult.index).trim();
      // JS返回的选项优先
      optionStr = postJsOptionStr;
    }

    // 步骤4: 解析选项JSON（支持单引号格式）
    if (optionStr) {
      const option = this.parseUrlOption(optionStr);
      if (option) {
        if (option.method?.toUpperCase() === 'POST') {
          method = RequestMethod.POST;
        }
        if (option.headers) {
          headers = option.headers;
        }
        if (option.body) {
          body = option.body;
        }
        if (option.charset) {
          charset = option.charset;
        }
        if (option.webView) {
          useWebView = true;
        }
        if (option.webJs) {
          webJs = option.webJs;
        }
        if (option.retry) {
          retry = option.retry;
        }
      }
    }

    // 步骤5: 处理body中的变量
    if (body) {
      body = this.replaceKeyPageJs(body);
    }

    // 步骤6: 处理<,page>页码模板
    ruleUrl = this.replacePageTemplate(ruleUrl, this.page);

    // 步骤7: 解析相对URL
    let url = this.resolveUrl(ruleUrl);
    
    // 步骤8: 清理URL（去除换行符等无效字符）
    url = this.cleanUrl(url);

    return {
      url,
      method,
      headers,
      body,
      charset,
      useWebView,
      webJs,
      retry
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

    // 步骤1: 分离URL和选项JSON（第一次，处理原始模板中的选项）
    // 参考Legado原版: paramPattern = Pattern.compile("\\s*,\\s*(?=\\{)")
    let optionStr = '';
    const separatorResult = this.findOptionSeparator(ruleUrl);
    if (separatorResult.found) {
      optionStr = ruleUrl.substring(separatorResult.index + 1).trim();
      ruleUrl = ruleUrl.substring(0, separatorResult.index).trim();
    }

    // 步骤2: 执行 @js: 和 <js></js> 格式的JS代码（异步）
    ruleUrl = await this.analyzeJsAsync(ruleUrl);

    // 步骤3: 替换 {{...}} 内嵌JS/变量（异步）
    ruleUrl = await this.replaceKeyPageJsAsync(ruleUrl);
    
    // 步骤3.5: 再次检查JS执行结果是否包含选项JSON
    // 有些书源的JS会返回完整的URL+选项格式
    const postJsSeparatorResult = this.findOptionSeparator(ruleUrl);
    if (postJsSeparatorResult.found) {
      const postJsOptionStr = ruleUrl.substring(postJsSeparatorResult.index + 1).trim();
      ruleUrl = ruleUrl.substring(0, postJsSeparatorResult.index).trim();
      // JS返回的选项优先
      optionStr = postJsOptionStr;
    }

    // 步骤4: 解析选项JSON（支持单引号格式）
    if (optionStr) {
      const option = this.parseUrlOption(optionStr);
      if (option) {
        if (option.method?.toUpperCase() === 'POST') {
          method = RequestMethod.POST;
        }
        if (option.headers) {
          headers = option.headers;
        }
        if (option.body) {
          body = option.body;
        }
        if (option.charset) {
          charset = option.charset;
        }
        if (option.webView) {
          useWebView = true;
        }
        if (option.webJs) {
          webJs = option.webJs;
        }
        if (option.retry) {
          retry = option.retry;
        }
      }
    }

    // 步骤5: 处理body中的变量
    if (body) {
      body = await this.replaceKeyPageJsAsync(body);
    }

    // 步骤6: 处理<,page>页码模板
    ruleUrl = this.replacePageTemplate(ruleUrl, this.page);

    // 步骤7: 解析相对URL
    let url = this.resolveUrl(ruleUrl);
    
    // 步骤8: 清理URL（去除换行符等无效字符）
    url = this.cleanUrl(url);

    return {
      url,
      method,
      headers,
      body,
      charset,
      useWebView,
      webJs,
      retry
    };
  }

  /**
   * 执行 @js: 和 <js></js> 格式的JS代码（同步版本）
   * 参考: AnalyzeUrl.kt 的 analyzeJs()
   */
  private analyzeJs(ruleUrl: string): string {
    const jsMatch = ruleUrl.match(JS_PATTERN);
    if (!jsMatch) {
      return ruleUrl;
    }

    // 提取JS代码
    const jsCode = jsMatch[1] || jsMatch[2];
    if (!jsCode) {
      return ruleUrl;
    }

    // 同步版本：尝试简单执行
    const jsResult = this.executeJsSimple(jsCode);
    if (jsResult !== null) {
      // JS执行成功，替换结果
      const beforeJs = ruleUrl.substring(0, jsMatch.index || 0).trim();
      const afterJs = ruleUrl.substring((jsMatch.index || 0) + jsMatch[0].length).trim();
      
      if (beforeJs) {
        return beforeJs.replace('@result', jsResult) + afterJs;
      }
      return jsResult + afterJs;
    }

    // JS执行失败，返回原始内容（去除JS部分）
    logger.warn(TAG, `JS规则需要异步执行: ${jsCode.substring(0, 50)}...`);
    const beforeJs = ruleUrl.substring(0, jsMatch.index || 0).trim();
    return beforeJs || ruleUrl.replace(JS_PATTERN, '');
  }

  /**
   * 执行 @js: 和 <js></js> 格式的JS代码（异步版本）
   */
  private async analyzeJsAsync(ruleUrl: string): Promise<string> {
    let result = ruleUrl;
    let start = 0;
    
    // 循环处理所有JS代码块
    while (true) {
      const remaining = result.substring(start);
      const jsMatch = remaining.match(JS_PATTERN);
      if (!jsMatch) {
        break;
      }

      const jsCode = jsMatch[1] || jsMatch[2];
      if (!jsCode) {
        start += (jsMatch.index || 0) + jsMatch[0].length;
        continue;
      }

      // 执行JS
      const jsResult = await this.executeJsAsync(jsCode, result);
      
      // 替换结果
      const matchStart = start + (jsMatch.index || 0);
      const matchEnd = matchStart + jsMatch[0].length;
      const beforeJs = result.substring(0, matchStart).trim();
      const afterJs = result.substring(matchEnd).trim();
      
      if (beforeJs) {
        result = beforeJs.replace('@result', jsResult) + afterJs;
      } else {
        result = jsResult + afterJs;
      }
      
      start = beforeJs.length;
    }

    return result;
  }

  /**
   * 替换 {{...}} 内嵌JS/变量（同步版本）
   * 参考: AnalyzeUrl.kt 的 replaceKeyPageJs()
   */
  private replaceKeyPageJs(ruleUrl: string): string {
    if (!ruleUrl.includes('{{') || !ruleUrl.includes('}}')) {
      return ruleUrl;
    }

    return this.innerRule(ruleUrl, '{{', '}}', (expr: string): string => {
      // 尝试作为简单变量处理
      const trimmedExpr = expr.trim();
      
      // 检查是否是简单变量
      if (trimmedExpr === 'key') {
        return encodeURIComponent(this.key);
      }
      if (trimmedExpr === 'page') {
        return String(this.page);
      }
      if (this.variables.has(trimmedExpr)) {
        return this.variables.get(trimmedExpr) || '';
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
    if (!ruleUrl.includes('{{') || !ruleUrl.includes('}}')) {
      return ruleUrl;
    }

    return await this.innerRuleAsync(ruleUrl, '{{', '}}', async (expr: string): Promise<string> => {
      const trimmedExpr = expr.trim();
      
      // 检查是否是简单变量
      if (trimmedExpr === 'key') {
        return encodeURIComponent(this.key);
      }
      if (trimmedExpr === 'page') {
        return String(this.page);
      }
      if (this.variables.has(trimmedExpr)) {
        return this.variables.get(trimmedExpr) || '';
      }

      // 作为JS表达式执行
      const jsResult = await this.executeJsAsync(trimmedExpr);
      return jsResult;
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
  private executeJsSimple(jsCode: string): string | null {
    try {
      let code = jsCode.trim();
      
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

      // 处理 source.getKey() - 返回书源URL
      if (code.includes('source.getKey()')) {
        code = code.replace(/source\.getKey\(\)/g, `"${this.sourceUrl}"`);
      }

      // 处理简单的纯字符串
      if (/^["'][^"']*["']$/.test(code)) {
        return code.slice(1, -1);
      }

      // 处理 key 变量
      if (code === 'key') {
        return this.key;
      }

      // 处理 page 变量
      if (code === 'page') {
        return String(this.page);
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

      // 处理 encodeURI(key) 或 java.encodeURI(key)
      const encodeMatch = code.match(/(?:java\.)?encodeURI\s*\(\s*key\s*\)/i);
      if (encodeMatch) {
        return encodeURIComponent(this.key);
      }

      // 处理 encodeURIComponent(key)
      const encodeCompMatch = code.match(/encodeURIComponent\s*\(\s*key\s*\)/i);
      if (encodeCompMatch) {
        return encodeURIComponent(this.key);
      }

      // 处理简单的字符串拼接: "xxx" + key + "yyy"
      if (code.includes('+') && !code.includes('function') && !code.includes('=>')) {
        let result = code;
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

  /**
   * 异步JS执行（强制使用LegadoJsEngine的Native JSVM）
   */
  private async executeJsAsync(jsCode: string, result?: string): Promise<string> {
    // 直接使用JS引擎执行，不再使用简单执行绕过JSVM
    try {
      const jsEngine = getLegadoJsEngine();
      // 将Map转换为Record对象（ArkTS不支持Object.fromEntries）
      const varsRecord: Record<string, string> = {};
      this.variables.forEach((value: string, key: string) => {
        varsRecord[key] = value;
      });
      // 添加sourceUrl到变量中，供buildNativeScript使用
      varsRecord['sourceUrl'] = this.sourceUrl;
      
      const context: JsContext = {
        result: result,
        baseUrl: this.baseUrl,
        key: this.key,
        page: this.page,
        variables: varsRecord
      };

      // 直接传递jsCode，buildNativeScript会自动添加source对象
      const executeResult = await jsEngine.execute(jsCode, context);
      if (executeResult.success) {
        return executeResult.result;
      } else {
        logger.warn(TAG, `JS执行失败: ${executeResult.error}`);
        return '';
      }
    } catch (e) {
      logger.error(TAG, `JS执行异常: ${String(e)}`);
      return '';
    }
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
    
    // 步骤1: 首先尝试标准JSON解析
    try {
      return JSON.parse(jsonStr) as LegadoUrlOption;
    } catch (e) {
      // 标准解析失败，尝试宽松解析
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
      
      return JSON.parse(fixedJson) as LegadoUrlOption;
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
    
    // 提取headers字段（复杂对象，尝试提取）
    const headersMatch = optionStr.match(/headers\s*[:=]\s*(\{[^}]*\})/i);
    if (headersMatch) {
      try {
        // 递归修复headers的JSON
        let headersJson = headersMatch[1];
        headersJson = headersJson.replace(/([{,]\s*)([a-zA-Z_$][a-zA-Z0-9_$-]*)\s*:/g, '$1"$2":');
        headersJson = headersJson.replace(/'([^'\\]*)'/g, '"$1"');
        option.headers = JSON.parse(headersJson) as Record<string, string>;
      } catch (e) {
        // 忽略headers解析失败
      }
    }
    
    // 如果至少提取到了method或body，认为解析成功
    if (option.method || option.body) {
      logger.debug(TAG, `手动解析URL选项成功: method=${option.method}, body=${option.body?.substring(0, 50)}`);
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
  private findOptionSeparator(url: string): OptionSeparatorResult {
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
    
    return cleaned;
  }
}
