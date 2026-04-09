// 文件路径: src/main/ets/Framework/WebView/MangaSourceActionEngine.ets
/**
 * 漫画图源操作引擎
 * 执行JSON配置定义的WebView自动化操作
 */

import { webview } from '@kit.ArkWeb';
import { BusinessError } from '@kit.BasicServicesKit';
import { logger } from '../../Utils/Logger';
import { 
  Action, 
  ActionType, 
  ActionResult, 
  NavigateAction, 
  WaitAction, 
  ClickAction, 
  InputAction, 
  ExtractAction, 
  ConditionAction, 
  ScriptAction, 
  CloudflareBypassAction, 
  CaptchaAction, 
  IPBlockAction,
  APIRequestAction,
  HTTPRequestAction,
  LoopAction,
  WaitCondition,
  MangaSourceError,
  MangaSourceErrorCode,
  AntiCrawlerConfig
} from './MangaSourceTypes';
import { MangaSourceSelectorEngine } from './MangaSourceSelectorEngine';
import { MangaSourceAntiCrawler } from './MangaSourceAntiCrawler';
import { MangaSourceAPIEngine, JSONExtractConfig } from './MangaSourceAPIEngine';
import { DataManager } from '../Data/DataManager';
import CookieManager from '../Managers/CookieManager';
import { generatePicaSignature } from '../Source/SignatureHandler';
import { UserAgentManager } from '../Managers/UserAgentManager';

/**
 * 字段选择器解析结果
 */
interface FieldSelectorParseResult {
  selector: string;
  extractor: string;
}

const TAG = 'MangaSourceActionEngine';
const ACTION_QUEUE_OWNER_KEY = '__actionQueueOwner';
const SCRIPT_EXECUTION_TIMEOUT_MS = 8000;

/**
 * 操作执行上下文
 */
export interface ActionContext {
  /** WebView控制器 */
  webViewController: webview.WebviewController;
  /** 变量存储 */
  variables: Record<string, string>;
  /** 当前URL */
  currentUrl?: string;
  /** 页面标题 */
  pageTitle?: string;
}

/**
 * WebView页面事件接口
 */
interface WebViewPageEvent {
  url: string;
}

/**
 * WebView错误事件接口
 */
interface InternetError {
  getErrorInfo(): string;
}
interface WebViewErrorEvent {
  error: InternetError;
}

/**
 * WebView事件监听器接口
 */
interface WebViewEventListeners {
  onPageEnd?: (event: WebViewPageEvent) => void;
  onPageBegin?: (event: WebViewPageEvent) => void;
  onErrorReceive?: (event: WebViewErrorEvent) => void;
}

/**
 * 漫画图源操作引擎
 */
export class MangaSourceActionEngine {
  private webviewController: webview.WebviewController;
  private selectorEngine: MangaSourceSelectorEngine;
  private antiCrawler: MangaSourceAntiCrawler;
  private apiEngine: MangaSourceAPIEngine;
  private actionExecutionTail: Promise<void> = Promise.resolve();
  private actionExecutionSequence: number = 0;
  private activeActionOwnerToken: string = '';

  constructor(webviewController: webview.WebviewController, antiCrawlerConfig: AntiCrawlerConfig) {
    this.webviewController = webviewController;
    this.selectorEngine = new MangaSourceSelectorEngine();
    this.antiCrawler = new MangaSourceAntiCrawler(webviewController, antiCrawlerConfig);
    this.apiEngine = new MangaSourceAPIEngine();
  }

  /**
   * 更新WebView控制器（修复：页面返回后WebView失效）
   */
  updateWebViewController(controller: webview.WebviewController): void {
    this.webviewController = controller;
    this.antiCrawler.updateWebViewController(controller);
  }

  /**
   * 设置CF验证需要用户交互时的回调
   */
  setOnNeedCfVerify(callback: () => void): void {
    this.antiCrawler.setOnNeedUserInteraction(callback);
  }

  /**
   * 执行单个操作
   */
  async executeAction(action: Action, context: ActionContext): Promise<ActionResult> {
    const currentOwnerToken = context.variables[ACTION_QUEUE_OWNER_KEY] || '';
    if (currentOwnerToken !== '' && currentOwnerToken === this.activeActionOwnerToken) {
      return await this.executeActionInternal(action, context);
    }

    const previousTail = this.actionExecutionTail.catch((): void => {});
    const releaseResolvers: Array<() => void> = [];
    const gate = new Promise<void>((resolve: () => void) => {
      releaseResolvers.push(resolve);
    });
    this.actionExecutionTail = previousTail.then((): Promise<void> => gate);

    const sequence = this.actionExecutionSequence + 1;
    this.actionExecutionSequence = sequence;
    const queueWaitStart = Date.now();
    await previousTail;
    const queueWaitDuration = Date.now() - queueWaitStart;
    if (queueWaitDuration > 5) {
      logger.debug(TAG, `动作排队等待完成: #${sequence}, type=${action.type}, wait=${queueWaitDuration}ms`);
    }

    const ownerToken = `${sequence}_${Date.now()}`;
    const previousOwnerToken = context.variables[ACTION_QUEUE_OWNER_KEY] || '';
    context.variables[ACTION_QUEUE_OWNER_KEY] = ownerToken;
    this.activeActionOwnerToken = ownerToken;

    try {
      return await this.executeActionInternal(action, context);
    } finally {
      this.activeActionOwnerToken = '';
      if (previousOwnerToken !== '') {
        context.variables[ACTION_QUEUE_OWNER_KEY] = previousOwnerToken;
      } else {
        context.variables[ACTION_QUEUE_OWNER_KEY] = '';
      }

      const release = releaseResolvers[0];
      if (release) {
        release();
      }
    }
  }

  private async executeActionInternal(action: Action, context: ActionContext): Promise<ActionResult> {
    const startTime = Date.now();
    
    try {
      logger.info(TAG, `执行操作: ${action.type}`, JSON.stringify(action));
      
      let result: string | boolean | Record<string, string | string[]> | Array<Record<string, string>> | ActionResult[];
      
      switch (action.type) {
        case ActionType.NAVIGATE:
          result = await this.executeNavigate(action as NavigateAction, context);
          break;
        case ActionType.WAIT:
          result = await this.executeWait(action as WaitAction, context);
          break;
        case ActionType.CLICK:
          result = await this.executeClick(action as ClickAction, context);
          break;
        case ActionType.INPUT:
          result = await this.executeInput(action as InputAction, context);
          break;
        case ActionType.EXTRACT:
          result = await this.executeExtract(action as ExtractAction, context);
          break;
        case ActionType.CONDITION:
          result = await this.executeCondition(action as ConditionAction, context);
          break;
        case ActionType.SCRIPT:
          result = await this.executeScript(action as ScriptAction, context);
          break;
        case ActionType.CLOUDFLARE_BYPASS:
          result = await this.executeCloudflareBypass(action as CloudflareBypassAction, context);
          break;
        case ActionType.CAPTCHA:
          result = await this.executeCaptcha(action as CaptchaAction, context);
          break;
        case ActionType.IP_BLOCK:
          result = await this.executeIPBlock(action as IPBlockAction, context);
          break;
        case ActionType.API_REQUEST:
          result = await this.executeAPIRequest(action as APIRequestAction, context);
          break;
        case ActionType.HTTP_REQUEST:
          result = await this.executeHTTPRequest(action as HTTPRequestAction, context);
          break;
        case ActionType.LOOP:
          result = await this.executeLoop(action as LoopAction, context);
          break;
        default:
          throw new MangaSourceError(
            MangaSourceErrorCode.INVALID_CONFIG,
            `不支持的操作类型: ${(action as Action).type}`
          );
      }

      const duration = Date.now() - startTime;
      logger.debug(TAG, `操作完成: ${action.type}, 耗时: ${duration}ms`);
      
      // 如果是script操作，将结果保存到变量
      if (action.type === ActionType.SCRIPT && typeof result === 'string') {
        // 移除JSON.stringify添加的引号（如果有）
        let cleanResult = result;
        if (cleanResult.startsWith('"') && cleanResult.endsWith('"')) {
          cleanResult = cleanResult.substring(1, cleanResult.length - 1);
        }
        
        // 检查是否有saveAs字段指定变量名
        const actionObj: ESObject = action as ESObject;
        const saveAsField: string | undefined = actionObj['saveAs'] as string | undefined;
        if (saveAsField) {
          // 尝试解析JSON并保存各个字段
          try {
            const parsed: ESObject = JSON.parse(cleanResult) as ESObject;
            if (typeof parsed === 'object' && parsed !== null) {
              // 保存整个对象到指定变量
              context.variables[saveAsField] = cleanResult;
              // 同时保存各个字段到 saveAs.fieldName 格式
              const keys: string[] = Object.keys(parsed);
              for (const key of keys) {
                const value: ESObject = parsed[key] as ESObject;
                context.variables[`${saveAsField}.${key}`] = typeof value === 'string' ? value : JSON.stringify(value);
              }
              logger.debug(TAG, `脚本结果已保存到${saveAsField}及其子字段`);
            } else {
              context.variables[saveAsField] = cleanResult;
            }
          } catch {
            context.variables[saveAsField] = cleanResult;
          }
        }
        
        // 始终保存到scriptResult作为默认变量
        context.variables['scriptResult'] = cleanResult;
        logger.debug(TAG, `脚本结果已保存: ${cleanResult.substring(0, 100)}${cleanResult.length > 100 ? '...' : ''}`);
      }

      return {
        success: true,
        data: result,
        duration
      };

    } catch (error) {
      const duration = Date.now() - startTime;
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `操作失败: ${action.type}, 错误: ${errorMessage}`);

      return {
        success: false,
        error: errorMessage,
        duration
      };
    }
  }

  /**
   * 执行导航操作
   */
  private async executeNavigate(action: NavigateAction, context: ActionContext): Promise<string> {
    const url = this.replaceVariables(action.url, context.variables);
    // 注意：timeout是最大超时时间，不是固定等待时间
    // 使用waitAfterLoad作为导航后的固定等待时间，默认1秒
    const waitAfterLoad = action.waitAfterLoad !== undefined ? action.waitAfterLoad : 1000;
    
    logger.info(TAG, `导航到: ${url}, waitAfterLoad=${waitAfterLoad}ms`);

    try {
      // 开始导航
      this.webviewController.loadUrl(url);
      
      // 等待页面加载（简单的固定时间等待）
      // 注意：WebView的onPageEnd等事件只能在UI组件层面监听，无法在控制器层面注册
      logger.debug(TAG, `等待页面加载，时间: ${waitAfterLoad}ms`);
      await this.sleep(waitAfterLoad);
      
      // 更新上下文URL
      context.currentUrl = url;
      
      logger.debug(TAG, `导航完成: ${url}`);
      
      // 首次导航后输出UserAgent
      if (!context.variables['_uaLogged']) {
        try {
          const ua = await this.executeJavaScript<string>('navigator.userAgent');
          logger.info(TAG, `📱 WebView UserAgent: ${ua}`);
          context.variables['_uaLogged'] = 'true';
        } catch (error) {
          logger.warn(TAG, `获取UserAgent失败`);
        }
      }
      
      return url;
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `导航失败: ${errorMsg}`);
      throw new MangaSourceError(
        MangaSourceErrorCode.NETWORK_ERROR,
        `导航失败: ${errorMsg}`
      );
    }
  }

  /**
   * 执行等待操作
   */
  private async executeWait(action: WaitAction, context: ActionContext): Promise<boolean> {
    logger.info(TAG, `等待条件: ${action.condition}`);

    switch (action.condition) {
      case WaitCondition.TIME:
        await this.sleep(action.duration || 1000);
        return true;

      case WaitCondition.ELEMENT:
        if (!action.selector) {
          throw new MangaSourceError(
            MangaSourceErrorCode.INVALID_CONFIG,
            '等待元素操作需要指定选择器'
          );
        }
        return await this.waitForElement(action.selector, action.timeout || 10000);

      case WaitCondition.LOAD:
        await this.waitForPageLoad(action.timeout || 30000);
        return true;

      case WaitCondition.NETWORK_IDLE:
        await this.sleep(action.duration || 2000);
        return true;

      default:
        throw new MangaSourceError(
          MangaSourceErrorCode.INVALID_CONFIG,
          `不支持的等待条件: ${action.condition}`
        );
    }
  }

  /**
   * 执行点击操作
   */
  private async executeClick(action: ClickAction, context: ActionContext): Promise<boolean> {
    const selector = this.replaceVariables(action.selector, context.variables);
    logger.info(TAG, `点击元素: ${selector}`);

    const exists = await this.checkElement(selector);
    if (!exists) {
      throw new MangaSourceError(
        MangaSourceErrorCode.ELEMENT_NOT_FOUND,
        `元素不存在: ${selector}`
      );
    }

    const script = `
      const element = document.querySelector('${selector}');
      if (element) {
        element.click();
        true;
      } else {
        false;
      }
    `;

    const result = await this.executeJavaScript<boolean>(script);
    if (!result) {
      throw new MangaSourceError(
        MangaSourceErrorCode.SCRIPT_ERROR,
        `点击失败: ${selector}`
      );
    }

    return result;
  }

  /**
   * 执行输入操作
   */
  private async executeInput(action: InputAction, context: ActionContext): Promise<boolean> {
    const selector = this.replaceVariables(action.selector, context.variables);
    const value = this.replaceVariables(action.value, context.variables);
    logger.info(TAG, `输入文本: ${selector} = ${value}`);

    const exists = await this.checkElement(selector);
    if (!exists) {
      throw new MangaSourceError(
        MangaSourceErrorCode.ELEMENT_NOT_FOUND,
        `元素不存在: ${selector}`
      );
    }

    const clearScript = action.clear ? 'element.value = "";' : '';
    const script = `
      const element = document.querySelector('${selector}');
      if (element) {
        ${clearScript}
        element.value = '${value}';
        element.dispatchEvent(new Event('input', { bubbles: true }));
        element.dispatchEvent(new Event('change', { bubbles: true }));
        true;
      } else {
        false;
      }
    `;

    const result = await this.executeJavaScript<boolean>(script);
    if (!result) {
      throw new MangaSourceError(
        MangaSourceErrorCode.SCRIPT_ERROR,
        `输入失败: ${selector}`
      );
    }

    return result;
  }

  /**
   * 执行提取操作
   */
  private async executeExtract(action: ExtractAction, context: ActionContext): Promise<Record<string, string | string[]> | Array<Record<string, string>>> {
    // 根据数据源类型处理
    if (action.source === 'variable') {
      // 从变量中提取数据
      const variableName = action.variable || '';
      logger.info(TAG, `从变量提取数据: ${variableName}`);
      const variableData = context.variables[variableName];
      if (!variableData) {
        throw new MangaSourceError(
          MangaSourceErrorCode.VARIABLE_NOT_FOUND,
          `变量不存在: ${variableName}`
        );
      }
      // 解析变量数据
      if (typeof variableData === 'string') {
        try {
          // 使用 JSON5 兼容的解析方式处理可能的嵌套对象
          const parsed = JSON.parse(variableData) as Record<string, Object> | Array<Record<string, Object>>;
          logger.debug(TAG, `变量数据解析成功，类型: ${Array.isArray(parsed) ? 'array' : typeof parsed}`);
          return parsed as Record<string, string | string[]> | Array<Record<string, string>>;
        } catch (e) {
          logger.error(TAG, `变量数据解析失败: ${e}`);
          throw new MangaSourceError(
            MangaSourceErrorCode.EXTRACTION_FAILED,
            `变量数据解析失败: ${e}`
          );
        }
      }
      return variableData as Record<string, string | string[]> | Array<Record<string, string>>;
    }
    
    // 从DOM或脚本结果提取
    const selector = action.selector ? this.replaceVariables(action.selector, context.variables) : '';
    if (!selector) {
      throw new MangaSourceError(
        MangaSourceErrorCode.INVALID_SELECTOR,
        '提取操作缺少selector字段'
      );
    }
    
    logger.info(TAG, `提取数据: ${selector}`);

    const exists = await this.checkElement(selector);
    if (!exists) {
      logger.warn(TAG, `元素不存在: ${selector}，返回空结果`);
      return {};
    }

    // 如果是multiple模式，需要特殊处理
    if (action.multiple) {
      logger.debug(TAG, `多项提取模式，基础选择器: ${selector}`);
      // 只有Record类型才支持多项提取
      if (!Array.isArray(action.fields)) {
        return await this.extractMultipleItems(selector, action.fields, context);
      }
    }

    const result: Record<string, string | string[]> = {};

    if (Array.isArray(action.fields)) {
      // 使用ExtractField数组
      for (const field of action.fields) {
        const fieldSelector = this.replaceVariables(field.selector, context.variables);
        const script = action.multiple 
          ? `Array.from(document.querySelectorAll('${fieldSelector}')).map(el => el.${field.attribute})`
          : `document.querySelector('${fieldSelector}')?.${field.attribute} || ''`;
        
        const value = await this.executeJavaScript<string | string[]>(script);
        result[field.field] = value || (action.multiple ? [] : '');
      }
    } else {
      // 使用Record<string, string>
      const entries = Object.entries(action.fields);
      for (let i = 0; i < entries.length; i++) {
        const fieldName = entries[i][0];
        const fieldSelector = entries[i][1];
        const resolvedSelector = this.replaceVariables(fieldSelector, context.variables);
        
        // 解析字段选择器语法
        const parsed = this.parseFieldSelector(resolvedSelector);
        const cleanSelector = parsed.selector;
        const extractor = parsed.extractor;
        
        logger.debug(TAG, `提取字段 ${fieldName}: selector="${cleanSelector}", extractor="${extractor}"`);
        
        const script = this.buildExtractScript(cleanSelector, extractor, action.multiple || false);
        
        let value = await this.executeJavaScript<string | string[]>(script);
        
        // 移除JSON.stringify添加的引号
        if (typeof value === 'string' && value.startsWith('"') && value.endsWith('"')) {
          value = value.slice(1, -1);
        }
        
        result[fieldName] = value || (action.multiple ? [] : '');
        
        logger.debug(TAG, `字段 ${fieldName} 提取结果: ${JSON.stringify(value)}`);
      }
    }

    logger.debug(TAG, `提取完成，结果: ${JSON.stringify(result)}`);
    return result;
  }
  
  /**
   * 提取多个项目
   */
  private async extractMultipleItems(
    baseSelector: string, 
    fields: Record<string, string>, 
    context: ActionContext
  ): Promise<Record<string, string[]>> {
    const fieldEntries: Array<[string, string]> = Object.entries(fields) as Array<[string, string]>;
    
    // 构建提取脚本
    const extractScript = this.buildMultipleItemsScript(baseSelector, fieldEntries);
    logger.debug(TAG, `多项提取模式，基础选择器: ${baseSelector}`);
    logger.debug(TAG, `提取脚本: ${extractScript.substring(0, 200)}...`);
    
    const result = await this.executeJavaScript<Record<string, string[]>>(extractScript);
    logger.debug(TAG, `JavaScript返回结果类型: ${typeof result}, 是否数组: ${Array.isArray(result)}`);
    logger.debug(TAG, `JavaScript返回结果: ${JSON.stringify(result).substring(0, 500)}`);
    
    const resultCount = result && Array.isArray(result) ? result.length : 0;
    logger.debug(TAG, `多项提取完成，获取 ${resultCount} 条数据`);
    
    return result || {};
  }
  
  /**
   * 构建多项提取脚本
   */
  private buildMultipleItemsScript(baseSelector: string, fields: Array<[string, string]>): string {
    let fieldExtractions = fields.map((field: [string, string]) => {
      const fieldName = field[0];
      const fieldSelector = field[1];
      
      // 特殊处理 ::index
      if (fieldSelector === '::index') {
        return `${fieldName}: index`;
      }
      
      const parsed = this.parseFieldSelector(fieldSelector);
      const cleanSelector = parsed.selector;
      const extractor = parsed.extractor;
      
      let extractCode = '';
      if (extractor === 'text') {
        extractCode = cleanSelector 
          ? `item.querySelector('${cleanSelector}')?.textContent?.trim() || ''`
          : `item.textContent?.trim() || ''`;
      } else if (extractor.startsWith('attr:')) {
        const attrName = extractor.substring(5);
        extractCode = cleanSelector
          ? `item.querySelector('${cleanSelector}')?.getAttribute('${attrName}') || ''`
          : `item.getAttribute('${attrName}') || ''`;
      }
      
      return `${fieldName}: ${extractCode}`;
    }).join(',\n        ');
    
    // 为cover字段生成特殊的提取代码
    const coverFieldIndex = fields.findIndex((field: [string, string]) => field[0] === 'cover');
    let coverExtractionCode = '';
    let debugCode = '';
    if (coverFieldIndex >= 0) {
      coverExtractionCode = `
        // 特殊处理：搜索包含cover的图片URL
        const allImgs = item.querySelectorAll('img');
        let coverUrl = '';
        let debugInfo = '';
        
        // 调试：记录第一个item的所有img信息
        if (index === 0) {
          const imgInfos = [];
          for (let i = 0; i < allImgs.length; i++) {
            const img = allImgs[i];
            imgInfos.push({
              index: i,
              src: img.getAttribute('src') || '',
              dataSrc: img.getAttribute('data-src') || '',
              className: img.className,
              parent: img.parentElement ? img.parentElement.className : ''
            });
          }
          debugInfo = JSON.stringify({ imgCount: allImgs.length, imgs: imgInfos });
        }
        
        // 查找包含cover的图片
        for (let i = 0; i < allImgs.length; i++) {
          const src = allImgs[i].getAttribute('src') || '';
          const dataSrc = allImgs[i].getAttribute('data-src') || '';
          if (src.includes('cover') || src.includes('public.komiic.com') || 
              dataSrc.includes('cover') || dataSrc.includes('public.komiic.com')) {
            coverUrl = src || dataSrc;
            break;
          }
        }
        
        // 后备：使用第一个img
        if (!coverUrl && allImgs.length > 0) {
          coverUrl = allImgs[0].getAttribute('src') || allImgs[0].getAttribute('data-src') || '';
        }
      `;
      
      // 替换cover字段的提取代码
      const fieldExtractionsArray = fieldExtractions.split(',\n        ');
      fieldExtractionsArray[coverFieldIndex] = 'cover: coverUrl';
      fieldExtractions = fieldExtractionsArray.join(',\n        ');
      
      // 添加debug字段
      debugCode = ',\n            _imgDebug: debugInfo || ""';
    }
    
    return `
      (function() {
        const items = Array.from(document.querySelectorAll('${baseSelector}'));
        
        return items.map((item, index) => {
          ${coverExtractionCode}
          
          return {
            ${fieldExtractions}${debugCode}
          };
        });
      })()
    `;
  }
  
  /**
   * 解析字段选择器语法
   * 支持：
   * - .selector::text - 提取文本内容
   * - .selector::attr(name) - 提取属性
   * - @href - 提取href属性（简写）
   * - @data-id - 提取data-id属性（简写）
   */
  private parseFieldSelector(fieldSelector: string): FieldSelectorParseResult {
    // 处理 @属性名 简写
    if (fieldSelector.startsWith('@')) {
      const attrName = fieldSelector.substring(1);
      const result: FieldSelectorParseResult = { 
        selector: '', 
        extractor: `attr:${attrName}` 
      };
      return result;
    }
    
    // 处理 ::text
    if (fieldSelector.includes('::text')) {
      const selector = fieldSelector.replace('::text', '').trim();
      const result: FieldSelectorParseResult = { 
        selector: selector, 
        extractor: 'text' 
      };
      return result;
    }
    
    // 处理 ::attr(name)
    const attrMatch = fieldSelector.match(/(.+)::attr\(([^)]+)\)/);
    if (attrMatch) {
      const result: FieldSelectorParseResult = { 
        selector: attrMatch[1].trim(), 
        extractor: `attr:${attrMatch[2]}` 
      };
      return result;
    }
    
    // 默认提取文本
    const result: FieldSelectorParseResult = { 
      selector: fieldSelector, 
      extractor: 'text' 
    };
    return result;
  }
  
  /**
   * 构建提取脚本
   */
  private buildExtractScript(selector: string, extractor: string, multiple: boolean): string {
    let extractCode = '';
    
    if (extractor === 'text') {
      extractCode = 'el.textContent || \'\'';
    } else if (extractor.startsWith('attr:')) {
      const attrName = extractor.substring(5);
      extractCode = `el.getAttribute('${attrName}') || ''`;
    } else {
      extractCode = 'el.textContent || \'\'';
    }
    
    if (multiple) {
      if (selector) {
        return `Array.from(document.querySelectorAll('${selector}')).map(el => ${extractCode})`;
      } else {
        // 没有selector，说明是@href这种简写，需要从父元素提取
        return `Array.from(document.querySelectorAll('a')).map(el => ${extractCode})`;
      }
    } else {
      if (selector) {
        return `(function() { const el = document.querySelector('${selector}'); return el ? (${extractCode}) : ''; })()`;
      } else {
        return `(function() { const el = document.querySelector('a'); return el ? (${extractCode}) : ''; })()`;
      }
    }
  }

  /**
   * 执行条件判断操作
   */
  private async executeCondition(action: ConditionAction, context: ActionContext): Promise<ActionResult[]> {
    const selector = this.replaceVariables(action.selector, context.variables);
    logger.info(TAG, `条件判断: ${selector}`);

    let conditionMet = false;

    if (action.exists !== undefined) {
      const exists = await this.checkElement(selector);
      conditionMet = exists === action.exists;
    }

    if (action.text && !conditionMet) {
      const script = `document.querySelector('${selector}')?.textContent || ''`;
      const elementText = await this.executeJavaScript<string>(script);
      conditionMet = elementText.includes(action.text);
    }

    const actionsToExecute = conditionMet ? action.then : (action.else || []);
    const results: ActionResult[] = [];

    for (const subAction of actionsToExecute) {
      const result = await this.executeAction(subAction, context);
      results.push(result);
    }

    return results;
  }

  /**
   * 执行脚本操作
   */
  private async executeScript(action: ScriptAction, context: ActionContext): Promise<string> {
    const code = this.replaceVariables(action.code, context.variables);
    // 输出更详细的日志，帮助调试变量替换问题
    logger.info(TAG, `执行脚本: ${code.substring(0, 200)}...`);
    // 输出关键筛选变量
    logger.debug(TAG, `脚本变量: category=${context.variables['category']}, sort=${context.variables['sort']}, time=${context.variables['time']}, timeType=${context.variables['timeType']}, page=${context.variables['page']}`);

    return await this.executeJavaScriptWithTimeout<string>(code, SCRIPT_EXECUTION_TIMEOUT_MS);
  }

  /**
   * 执行Cloudflare绕过操作
   */
  private async executeCloudflareBypass(action: CloudflareBypassAction, context: ActionContext): Promise<boolean> {
    logger.info(TAG, `绕过Cloudflare: ${action.method}, maxWaitTime: ${action.maxWaitTime}`);

    const result = await this.antiCrawler.bypassCloudflare(action.method, action.maxWaitTime);
    return result.success;
  }

  /**
   * 执行验证码处理操作
   */
  private async executeCaptcha(action: CaptchaAction, context: ActionContext): Promise<boolean> {
    const selector = this.replaceVariables(action.selector, context.variables);
    logger.info(TAG, `处理验证码: ${selector}`);

    const exists = await this.checkElement(selector);
    if (!exists) {
      throw new MangaSourceError(
        MangaSourceErrorCode.ELEMENT_NOT_FOUND,
        `验证码元素不存在: ${selector}`
      );
    }

    if (action.method === 'auto') {
      const result = await this.antiCrawler.autoSolveCaptcha('recaptcha');
      return result.solved;
    } else {
      throw new MangaSourceError(
        MangaSourceErrorCode.CAPTCHA_FAILED,
        '手动验证码处理暂未实现'
      );
    }
  }

  /**
   * 执行IP封禁处理操作
   */
  private async executeIPBlock(action: IPBlockAction, context: ActionContext): Promise<boolean> {
    logger.info(TAG, `处理IP封禁: ${action.action}`);

    if (action.action === 'retry') {
      const result = await this.antiCrawler.handleIpBlock();
      return result;
    } else {
      throw new MangaSourceError(
        MangaSourceErrorCode.IP_BLOCKED,
        'IP被封禁，操作中止'
      );
    }
  }

  /**
   * 执行循环操作（用于分页递归获取等场景）
   */
  private async executeLoop(action: LoopAction, context: ActionContext): Promise<ActionResult[]> {
    const maxIterations = action.maxIterations || 100;
    const results: ActionResult[] = [];
    
    logger.info(TAG, `开始循环操作, 最大迭代次数: ${maxIterations}`);
    
    for (let i = 0; i < maxIterations; i++) {
      // 检查跳出条件
      if (action.breakCondition) {
        const conditionVar: string = action.breakCondition.variable || '';
        const conditionValue: string = action.breakCondition.value || '';
        const currentValue: string = conditionVar ? (context.variables[conditionVar] || '') : '';
        const operator: string = action.breakCondition.operator || 'equals';
        
        if (operator === 'equals' && currentValue === conditionValue) {
          logger.info(TAG, `循环跳出条件满足: ${conditionVar} === ${conditionValue}`);
          break;
        }
        if (operator === 'notEquals' && currentValue !== conditionValue) {
          logger.info(TAG, `循环跳出条件满足: ${conditionVar} !== ${conditionValue}`);
          break;
        }
        if (operator === 'empty' && (!currentValue || currentValue === 'null' || currentValue === 'undefined')) {
          logger.info(TAG, `循环跳出条件满足: ${conditionVar} 为空`);
          break;
        }
        if (operator === 'notEmpty' && currentValue && currentValue !== 'null' && currentValue !== 'undefined') {
          // 继续循环
        }
      }
      
      // 检查基于condition字段的简化跳出条件（用于JSON配置中的{{variable}}格式）
      const actionObj: ESObject = action as ESObject;
      const conditionField: string | undefined = actionObj['condition'] as string | undefined;
      if (conditionField) {
        const resolvedCondition = this.replaceVariables(conditionField, context.variables);
        // 如果条件为空、null、undefined或false，则跳出循环
        if (!resolvedCondition || resolvedCondition === 'null' || resolvedCondition === 'undefined' || 
            resolvedCondition === 'false' || resolvedCondition === '') {
          logger.info(TAG, `循环条件不满足，跳出循环: ${conditionField} = ${resolvedCondition}`);
          break;
        }
      }
      
      logger.debug(TAG, `循环迭代 ${i + 1}/${maxIterations}`);
      
      // 执行循环内的所有操作
      for (const subAction of action.actions) {
        const result = await this.executeAction(subAction, context);
        results.push(result);
        
        // 如果操作失败且不是可选操作，则中断循环
        if (!result.success && !subAction.optional) {
          logger.warn(TAG, `循环中操作失败，中断循环: ${subAction.type}`);
          return results;
        }
      }
    }
    
    logger.info(TAG, `循环操作完成，共执行 ${results.length} 个操作`);
    return results;
  }

  /**
   * 执行JavaScript代码
   */
  private async executeJavaScript<T>(code: string): Promise<T> {
    return new Promise<T>((resolve, reject) => {
      try {
        this.webviewController.runJavaScript(code, (error: BusinessError | null, result: string) => {
          if (error) {
            // 特殊处理UNDEFINED转换错误
            if (error.message && error.message.includes('Cannot convert a UNDEFINED value')) {
              logger.warn(TAG, `JavaScript返回undefined，可能是元素不存在: ${code.substring(0, 100)}`);
              resolve('' as T);
              return;
            }
            
            logger.error(TAG, `JavaScript执行失败: ${error.message}` + error);
            reject(new MangaSourceError(
              MangaSourceErrorCode.SCRIPT_ERROR,
              `JavaScript执行失败: ${error.message}`
            ));
            return;
          }

          try {
            // 处理空结果
            if (!result || result === 'undefined' || result === 'null') {
              logger.debug(TAG, `JavaScript返回空值: ${result}`);
              resolve('' as T);
              return;
            }
            
            // 尝试解析JSON结果
            if (result.trim().startsWith('{') || result.trim().startsWith('[')) {
              const parsedResult = JSON.parse(result) as T;
              resolve(parsedResult);
            } else {
              // 对于非JSON结果，进行类型转换
              resolve(result as T);
            }
          } catch (parseError) {
            logger.warn(TAG, `JSON解析失败，返回原始字符串: ${parseError}`);
            // 如果JSON解析失败，返回原始字符串结果
            resolve(result as T);
          }
        });
      } catch (error) {
        logger.error(TAG, `runJavaScript调用失败: ${error}`);
        reject(new MangaSourceError(
          MangaSourceErrorCode.SCRIPT_ERROR,
          `runJavaScript调用失败: ${error instanceof Error ? error.message : String(error)}`
        ));
      }
    });
  }

  private async executeJavaScriptWithTimeout<T>(code: string, timeoutMs: number): Promise<T> {
    return new Promise<T>((resolve, reject) => {
      let finished: boolean = false;
      const timerId: number = setTimeout(() => {
        if (!finished) {
          finished = true;
          logger.warn(TAG, `JavaScript执行超时(${timeoutMs}ms)，可能是WebView未附加或页面上下文已切换: ${code.substring(0, 120)}`);
          reject(new MangaSourceError(
            MangaSourceErrorCode.TIMEOUT_ERROR,
            `JavaScript执行超时(${timeoutMs}ms)`
          ));
        }
      }, timeoutMs);

      try {
        this.webviewController.runJavaScript(code, (error: BusinessError | null, result: string) => {
          if (finished) {
            return;
          }
          finished = true;
          clearTimeout(timerId);
          if (error) {
            reject(new MangaSourceError(
              MangaSourceErrorCode.SCRIPT_ERROR,
              `JavaScript执行失败: ${error.message}`
            ));
            return;
          }
          try {
            if (!result || result === 'undefined' || result === 'null') {
              logger.debug(TAG, `JavaScript返回空值: ${result}`);
              resolve('' as T);
              return;
            }
            if (result.trim().startsWith('{') || result.trim().startsWith('[')) {
              const parsed = JSON.parse(result) as T;
              resolve(parsed);
            } else {
              resolve(result as T);
            }
          } catch (parseError) {
            logger.warn(TAG, `JSON解析失败，返回原始字符串: ${parseError instanceof Error ? parseError.message : String(parseError)}`);
            resolve(result as T);
          }
        });
      } catch (error) {
        if (!finished) {
          finished = true;
          clearTimeout(timerId);
          reject(new MangaSourceError(
            MangaSourceErrorCode.SCRIPT_ERROR,
            `runJavaScript调用失败: ${error instanceof Error ? error.message : String(error)}`
          ));
        }
      }
    });
  }

  /**
   * 检查元素是否存在
   */
  private async checkElement(selector: string): Promise<boolean> {
    const script = `document.querySelector('${selector}') !== null`;
    return await this.executeJavaScript<boolean>(script);
  }

  /**
   * 等待元素出现
   */
  private async waitForElement(selector: string, timeout: number): Promise<boolean> {
    const startTime = Date.now();
    
    while (Date.now() - startTime < timeout) {
      const exists = await this.checkElement(selector);
      if (exists) {
        return true;
      }
      await this.sleep(500);
    }

    throw new MangaSourceError(
      MangaSourceErrorCode.TIMEOUT_ERROR,
      `等待元素超时: ${selector}`
    );
  }

  /**
   * 等待页面加载完成
   */
  private async waitForPageLoad(timeout: number = 30000): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      let isResolved = false;

      const timeoutId = setTimeout(() => {
        if (!isResolved) {
          isResolved = true;
          reject(new MangaSourceError(
            MangaSourceErrorCode.TIMEOUT_ERROR,
            '等待页面加载超时'
          ));
        }
      }, timeout);

      // 创建页面加载完成监听器
      const onPageEndListener = (event: WebViewPageEvent) => {
        if (!isResolved) {
          isResolved = true;
          clearTimeout(timeoutId);
          resolve();
        }
      };

      // 注意：实际使用时需要在Web组件上设置事件监听器
      // 这里只是示例，实际实现需要配合Web组件
      logger.debug(TAG, '等待页面加载完成...');
      
      // 使用递归调度替代setInterval，符合ArkTS规范
      const checkPageState = (): void => {
        this.executeJavaScript<string>('document.readyState')
          .then((readyState: string) => {
            if (readyState === 'complete' && !isResolved) {
              isResolved = true;
              clearTimeout(timeoutId);
              resolve();
            } else if (!isResolved) {
              // 继续检查，使用setTimeout递归调度
              setTimeout(checkPageState, 500);
            }
          })
          .catch(() => {
            // 忽略检查错误，继续等待
            if (!isResolved) {
              setTimeout(checkPageState, 500);
            }
          });
      };
      
      // 开始检查
      checkPageState();
    });
  }

  /**
   * 获取页面内容
   */
  private async getPageContent(): Promise<string> {
    return await this.executeJavaScript<string>('document.documentElement.outerHTML');
  }

  /**
   * 执行API请求操作
   */
  private async executeAPIRequest(action: APIRequestAction, context: ActionContext): Promise<Record<string, string | string[]>> {
    logger.debug(TAG, `executeAPIRequest收到的action: type=${action.type}, method=${action.method}, url=${action.url}`);
    logger.info(TAG, `执行API请求: ${action.method} ${action.url}`);
    
    try {
      // 替换URL中的变量
      let url = this.replaceVariables(action.url, context.variables);
      logger.info(TAG, `最终API URL: ${url}`);
      
      // 处理查询参数
      if (action.params) {
        const paramKeys = Object.keys(action.params);
        if (paramKeys.length > 0) {
          const queryParams: string[] = [];
          for (let i = 0; i < paramKeys.length; i++) {
            const key = paramKeys[i];
            const value = this.replaceVariables(action.params[key], context.variables);
            // [修复] 跳过空值参数，避免发送无效的查询参数
            if (value !== '' && value !== undefined && value !== null) {
              queryParams.push(`${encodeURIComponent(key)}=${encodeURIComponent(value)}`);
            } else {
              logger.debug(TAG, `跳过空值参数: ${key}`);
            }
          }
          if (queryParams.length > 0) {
            const separator = url.includes('?') ? '&' : '?';
            url = url + separator + queryParams.join('&');
            logger.debug(TAG, `添加查询参数后的URL: ${url}`);
          }
        }
      }
      const normalizedUrl: string = this.ensureCopyMangaPlatformParam(url);
      if (normalizedUrl !== url) {
        url = normalizedUrl;
        logger.debug(TAG, `CopyManga接口自动补充platform参数后的URL: ${url}`);
      }
      logger.info(TAG, '开始构建请求Headers');
      
      // [修复] 检测是否需要签名，并预先计算签名变量
      // 检查 action.headers 中是否有签名相关的变量占位符
      let needsSignature: boolean = false;
      if (action.headers) {
        const headerValues: string = JSON.stringify(action.headers);
        if (headerValues.includes('{{timestamp}}') || 
            headerValues.includes('{{nonce}}') || 
            headerValues.includes('{{signature}}') ||
            headerValues.includes('{{computeSignature}}')) {
          needsSignature = true;
        }
      }
      
      if (needsSignature) {
        logger.info(TAG, '检测到签名变量，开始计算HMAC-SHA256签名');
        try {
          // 哔咔漫画的 API Key
          const apiKey: string = 'C69BAF41DA5ABD1FFEDC6D2FEA56B';
          // 哔咔漫画的 HMAC 密钥
          const hmacKey: string = '~d}$Q7$eIni=V)9\\RK/P.RM4;9[7|@/CA}b~OW!3?EV`:<>M7pddUBL5n|0/*Cn';
          
          // 调用签名生成函数
          const signatureHeaders: Record<string, string> = await generatePicaSignature(
            url,
            action.method,
            apiKey,
            hmacKey
          );
          
          // 将签名相关的值注入到 context.variables 中
          context.variables['timestamp'] = signatureHeaders['time'];
          context.variables['time'] = signatureHeaders['time'];
          context.variables['nonce'] = signatureHeaders['nonce'];
          context.variables['signature'] = signatureHeaders['signature'];
          context.variables['computeSignature'] = signatureHeaders['signature'];
          context.variables['apiKey'] = apiKey;
          
          logger.info(TAG, `签名计算完成: time=${signatureHeaders['time']}, nonce=${signatureHeaders['nonce'].substring(0, 8)}..., signature=${signatureHeaders['signature'].substring(0, 16)}...`);
        } catch (signError) {
          logger.error(TAG, `签名计算失败: ${signError}`);
          // 签名失败不阻止请求，但可能导致401错误
        }
      }
      
      let headers: Record<string, string> = {};
      
      // [修复] 0. 先应用 network.headers 配置（全局默认headers）
      const networkHeadersStr: string | undefined = context.variables['__networkHeaders__'];
      if (networkHeadersStr && networkHeadersStr.length > 0) {
        try {
          const networkHeaders: Record<string, string> = JSON.parse(networkHeadersStr) as Record<string, string>;
          const netHeaderKeys: string[] = Object.keys(networkHeaders);
          for (let ni = 0; ni < netHeaderKeys.length; ni++) {
            const nKey: string = netHeaderKeys[ni];
            headers[nKey] = networkHeaders[nKey];
          }
          logger.debug(TAG, `应用 network.headers: ${netHeaderKeys.join(', ')}`);
        } catch (parseErr) {
          logger.warn(TAG, `解析 network.headers 失败: ${parseErr}`);
        }
      }
      
      // 1. 如果配置中有 headers，先进行处理和合并（会覆盖network.headers）
      if (action.headers) {
        const configHeaders = action.headers;
        const headerKeys = Object.keys(configHeaders);
        
        // 检查是否有__template__标记
        if (headerKeys.length === 1 && headerKeys[0] === '__template__') {
          const template = configHeaders['__template__'];
          const replaced = this.replaceVariables(template, context.variables);
          try {
            const parsed = JSON.parse(replaced) as Record<string, string>;
            const parsedKeys: string[] = Object.keys(parsed);
            for (let i = 0; i < parsedKeys.length; i++) {
              const k: string = parsedKeys[i];
              const v: string = parsed[k];
              headers[k] = v;
            }
          } catch (e) {
            logger.warn(TAG, `解析headers模板失败: ${e}`);
          }
        } else {
          // 普通headers对象，逐个替换变量
          for (let i = 0; i < headerKeys.length; i++) {
            const key = headerKeys[i];
            const value = configHeaders[key];
            if (value && value.includes('{{') && value.includes('}}')) {
              headers[key] = this.replaceVariables(value, context.variables);
            } else {
              headers[key] = value;
            }
          }
        }
      }

      // [修复] 只有当配置中没有指定 User-Agent 时，才使用 WebView 的 User-Agent
      // 某些 API（如哔咔漫画）对 User-Agent 有严格要求，必须使用特定值
      let configHasUserAgent: boolean = false;
      const existingHeaderKeys: string[] = Object.keys(headers);
      for (let idx = 0; idx < existingHeaderKeys.length; idx++) {
        const hKey: string = existingHeaderKeys[idx];
        if (hKey.toLowerCase() === 'user-agent') {
          configHasUserAgent = true;
          break;
        }
      }
      
      if (!configHasUserAgent) {
        // [修复] 优先使用 network.userAgent 配置
        const networkUA: string | undefined = context.variables['__networkUserAgent__'];
        if (networkUA && networkUA.length > 0) {
          headers['User-Agent'] = networkUA;
          logger.info(TAG, `使用 network.userAgent: ${networkUA.substring(0, 50)}...`);
        } else {
          // 回退到 UserAgentManager
          const sidStr: string | undefined = context.variables['sourceId'];
          if (sidStr && sidStr.length > 0) {
            try {
              const customUA = await UserAgentManager.getInstance().getUserAgent(Number(sidStr));
              headers['User-Agent'] = customUA;
              logger.info(TAG, `使用UserAgentManager获取的UA: sourceId=${sidStr}`);
            } catch (_e) {
              headers['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36';
            }
          } else {
            headers['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36';
          }
        }
      } else {
        logger.info(TAG, `使用配置中指定的 User-Agent: ${headers['User-Agent']}`);
      }

      // [修复] 不再强制覆盖Referer和Origin
      // CopyManga等API对这些头敏感，需要使用配置中的值
      // 只在后面的检查中自动注入缺失的Referer（如果配置中没有指定）
      // Origin头完全由配置控制，不自动添加

      // 始终尝试获取Cookie，不再依赖useCookies变量
      const sidStr: string | undefined = context.variables['sourceId'];
      let cookieStrForAuth: string = '';
      if (sidStr && sidStr.length > 0) {
        try {
          const allowStoredFallback: boolean = !this.needsCookieAuthHeaders(url);
          const cookieStr: string = await CookieManager.getInstance().getCookieStringForUrl(Number(sidStr), url, allowStoredFallback);
          if (cookieStr.length > 0) {
            headers = this.setHeaderCanonical(headers, 'Cookie', cookieStr);
            cookieStrForAuth = cookieStr;
            logger.info(TAG, `API请求添加Cookie: sourceId=${sidStr}, length=${cookieStr.length}`);
          } else {
            logger.debug(TAG, `图源无可用Cookie: sourceId=${sidStr}`);
          }
        } catch (e) {
          logger.warn(TAG, `获取Cookie失败: sourceId=${sidStr}, error=${String(e)}`);
        }
      } else {
        logger.debug(TAG, 'API请求未sourceId，无法获取Cookie');
      }

      // 2. 自动注入缺少的关键 Headers (修复问题的关键)
      // 检查 User-Agent
      if (cookieStrForAuth.length > 0) {
        headers = this.injectAuthHeadersFromCookie(url, headers, cookieStrForAuth);
      }

      const uaKeys: string[] = Object.keys(headers);
      let hasUA: boolean = false;
      let iUA: number = 0;
      while (iUA < uaKeys.length) {
        const k: string = uaKeys[iUA];
        if (k.toLowerCase() === 'user-agent') {
          hasUA = true;
          break;
        }
        iUA = iUA + 1;
      }
      if (!hasUA) {
        // 使用默认 WebView UA 或从上下文获取
        headers['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36';
        logger.debug(TAG, '自动注入默认 User-Agent');
      }

      // 检查 Referer (很多图源图片接口强依赖此字段)
      const headerKeys: string[] = Object.keys(headers);
      let hasReferer: boolean = false;
      let iRef: number = 0;
      while (iRef < headerKeys.length) {
        const k: string = headerKeys[iRef];
        if (k.toLowerCase() === 'referer') {
          hasReferer = true;
          break;
        }
        iRef = iRef + 1;
      }
      if (!hasReferer && context.variables['baseUrl']) {
        headers['Referer'] = context.variables['baseUrl'];
        logger.debug(TAG, `自动注入 Referer: ${headers['Referer']}`);
      }
      const hdrKeysBefore: string[] = Object.keys(headers);
      logger.debug(TAG, `Headers准备完成，键数量: ${String(hdrKeysBefore.length)}`);
      logger.debug(TAG, `Headers详情: ${JSON.stringify(headers)}`);
      logger.info(TAG, 'Headers构建完成');
      
      
      // 替换body中的变量
      let body: ESObject | string | undefined = action.body;
      if (body && typeof body === 'object') {
        body = this.replaceObjectVariables(body as ESObject, context.variables);
      }
      
      // 执行请求
      logger.info(TAG, '准备发起HTTP请求');
      logger.info(TAG, `准备发出API请求: method=${action.method}, url=${url}`);
      let response = await this.apiEngine.request({
        method: action.method,
        url: url,
        headers: headers, // 使用处理后的 headers
        body: body
      });

      // 对需要登录鉴权的接口，401 时先刷新 URL 对应 Cookie 并自动重试一次
      if (response.status === 401 && sidStr && sidStr.length > 0 && this.needsCookieAuthHeaders(url)) {
        logger.warn(TAG, `检测到401响应，尝试刷新Cookie后重试: ${url}`);
        try {
          const refreshedCookie: string = await CookieManager.getInstance().getCookieStringForUrl(Number(sidStr), url, false);
          if (refreshedCookie.length > 0) {
            headers = this.setHeaderCanonical(headers, 'Cookie', refreshedCookie);
            cookieStrForAuth = refreshedCookie;
            headers = this.injectAuthHeadersFromCookie(url, headers, refreshedCookie);

            response = await this.apiEngine.request({
              method: action.method,
              url: url,
              headers: headers,
              body: body
            });
            logger.debug(TAG, `401重试后API响应状态: ${response.status}`);
          } else {
            logger.warn(TAG, '401重试前刷新Cookie为空，跳过重试');
          }
        } catch (retryErr) {
          logger.warn(TAG, `401重试前刷新Cookie失败: ${String(retryErr)}`);
        }
      }
      
      logger.debug(TAG, `API响应状态: ${response.status}`);
      
      // 持久化响应Cookie（Set-Cookie）到数据库
      try {
        const sidVar: string | undefined = context.variables['sourceId'];
        if (sidVar && sidVar.length > 0) {
          const sidNum: number = Number(sidVar);
          const headerObj: Object = response.headers as Object;
          const headerEntries: [string, Object][] = Object.entries(headerObj) as [string, Object][];
          const setCookieValues: string[] = [];
          let hi: number = 0;
          while (hi < headerEntries.length) {
            const keyLower: string = headerEntries[hi][0].toLowerCase();
            if (keyLower === 'set-cookie') {
              const valObj: Object = headerEntries[hi][1];
              if (Array.isArray(valObj)) {
                const arr: Object[] = valObj as Object[];
                let ai: number = 0;
                while (ai < arr.length) {
                  setCookieValues.push(String(arr[ai]));
                  ai = ai + 1;
                }
              } else {
                setCookieValues.push(String(valObj));
              }
            }
            hi = hi + 1;
          }
          if (setCookieValues.length > 0) {
            const entries: Object[] = [];
            let ci: number = 0;
            while (ci < setCookieValues.length) {
              const raw: string = setCookieValues[ci] as string;
              const segments: string[] = raw.split('\n');
              let si: number = 0;
              while (si < segments.length) {
                const seg: string = segments[si].trim();
                if (seg.length > 0) {
                  const semiIndex: number = seg.indexOf(';');
                  const firstPart: string = semiIndex > 0 ? seg.substring(0, semiIndex) : seg;
                  const eqIndex: number = firstPart.indexOf('=');
                  if (eqIndex > 0) {
                    const name: string = firstPart.substring(0, eqIndex);
                    const value: string = firstPart.substring(eqIndex + 1);
                    const obj: Record<string, Object> = {};
                    obj['name'] = name;
                    obj['value'] = value;
                    entries.push(obj);
                  }
                }
                si = si + 1;
              }
              ci = ci + 1;
            }
            if (entries.length > 0) {
              const jsonStr: string = JSON.stringify(entries);
              await DataManager.getInstance().updateComicSourceCookies(sidNum, jsonStr);
              logger.info(TAG, `API响应中捕获并保存Cookie: count=${entries.length}`);
            }
          }
        }
      } catch (_cookieErr) {}

      if (!this.isSuccessStatusCode(response.status)) {
        const errorDetail: string = this.extractApiErrorDetail(response.data);
        const statusMessage: string = errorDetail.length > 0
          ? `API请求失败: HTTP ${response.status}, ${errorDetail}`
          : `API请求失败: HTTP ${response.status}`;
        logger.warn(TAG, statusMessage);
        throw new MangaSourceError(MangaSourceErrorCode.NETWORK_ERROR, statusMessage);
      }

      // 提取数据
      if (action.extract && response.data) {
        const extracted: ESObject | ESObject[] = this.apiEngine.extractFromJSON(
          response.data as ESObject,
          action.extract as JSONExtractConfig
        );
        
        logger.info(TAG, `API数据提取完成`);
        return extracted as Record<string, string | string[]>;
      }
      
      return response.data as Record<string, string | string[]>;
      
    } catch (error) {
      if (error instanceof MangaSourceError) {
        throw error;
      }
      logger.error(TAG, `API请求失败: ${error}`);
      throw new MangaSourceError(
        MangaSourceErrorCode.NETWORK_ERROR,
        `API请求失败: ${error}`
      );
    }
  }

  /**
   * 执行HTTP请求操作
   */
  private async executeHTTPRequest(action: HTTPRequestAction, context: ActionContext): Promise<string> {
    logger.info(TAG, `执行HTTP请求: ${action.method} ${action.url}`);
    
    try {
      const url = this.replaceVariables(action.url, context.variables);
      
      // 从数据库读取Cookie并合并到headers中
      let finalHeaders: Object | undefined = action.headers;
      const sidVar: string | undefined = context.variables['sourceId'];
      if (sidVar && sidVar.length > 0) {
        const sidNum: number = Number(sidVar);
        try {
          const cookieManager = CookieManager.getInstance();
          const allowStoredFallback: boolean = !this.needsCookieAuthHeaders(url);
          const cookieStr: string = await cookieManager.getCookieStringForUrl(sidNum, url, allowStoredFallback);
          if (cookieStr && cookieStr.length > 0) {
              // 手动合并Cookie到headers
              if (finalHeaders && typeof finalHeaders === 'object') {
                const mergedHeaders: Record<string, Object> = {};
                const entries: [string, Object][] = Object.entries(finalHeaders) as [string, Object][];
                for (let i = 0; i < entries.length; i++) {
                  const key: string = entries[i][0];
                  const value: Object = entries[i][1];
                  mergedHeaders[key] = value;
                }
                mergedHeaders['Cookie'] = cookieStr;
                finalHeaders = mergedHeaders as Object;
              } else {
                const newHeaders: Record<string, string> = {};
                newHeaders['Cookie'] = cookieStr;
                finalHeaders = newHeaders as Object;
              }
              logger.debug(TAG, `已从数据库读取并添加Cookie到请求: len=${cookieStr.length}`);
            }
        } catch (cookieErr) {
          logger.warn(TAG, `读取Cookie失败: ${cookieErr}`);
        }
      }
      
      const response = await this.apiEngine.request({
        method: action.method,
        url: url,
        headers: finalHeaders,
        body: action.body,
        timeout: action.timeout
      });
      try {
        const sidVar: string | undefined = context.variables['sourceId'];
        if (sidVar && sidVar.length > 0) {
          const sidNum: number = Number(sidVar);
          const headerObj: Object = response.headers as Object;
          const headerEntries: [string, Object][] = Object.entries(headerObj) as [string, Object][];
          const setCookieValues: string[] = [];
          let hi: number = 0;
          while (hi < headerEntries.length) {
            const keyLower: string = headerEntries[hi][0].toLowerCase();
            if (keyLower === 'set-cookie') {
              const valObj: Object = headerEntries[hi][1];
              if (Array.isArray(valObj)) {
                const arr: Object[] = valObj as Object[];
                let ai: number = 0;
                while (ai < arr.length) {
                  setCookieValues.push(String(arr[ai]));
                  ai = ai + 1;
                }
              } else {
                setCookieValues.push(String(valObj));
              }
            }
            hi = hi + 1;
          }
          if (setCookieValues.length > 0) {
            const entries: Object[] = [];
            let ci: number = 0;
            while (ci < setCookieValues.length) {
              const raw: string = setCookieValues[ci] as string;
              const segments: string[] = raw.split('\n');
              let si: number = 0;
              while (si < segments.length) {
                const seg: string = segments[si].trim();
                if (seg.length > 0) {
                  const semiIndex: number = seg.indexOf(';');
                  const firstPart: string = semiIndex > 0 ? seg.substring(0, semiIndex) : seg;
                  const eqIndex: number = firstPart.indexOf('=');
                  if (eqIndex > 0) {
                    const name: string = firstPart.substring(0, eqIndex);
                    const value: string = firstPart.substring(eqIndex + 1);
                    const obj: Record<string, Object> = {};
                    obj['name'] = name;
                    obj['value'] = value;
                    entries.push(obj);
                  }
                }
                si = si + 1;
              }
              ci = ci + 1;
            }
            if (entries.length > 0) {
              const jsonStr: string = JSON.stringify(entries);
              await DataManager.getInstance().updateComicSourceCookies(sidNum, jsonStr);
              logger.info(TAG, `HTTP响应中捕获并保存Cookie: count=${entries.length}`);
            }
          }
        }
      } catch (_cookieErr) {}
      
      return JSON.stringify(response.data);
      
    } catch (error) {
      logger.error(TAG, `HTTP请求失败: ${error}`);
      throw new MangaSourceError(
        MangaSourceErrorCode.NETWORK_ERROR,
        `HTTP请求失败: ${error}`
      );
    }
  }

  /**
   * 替换对象中的变量
   */
  private replaceObjectVariables(obj: ESObject, variables: Record<string, string>): ESObject {
    const result: ESObject = {};
    const keys = Object.keys(obj);
    
    // 只对这些字段进行数字转换，其他字段保持字符串（特别是ID字段）
    const numericFields = ['offset', 'limit', 'page', 'pageSize', 'count'];
    
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i];
      const value: ESObject | ESObject[] | string | number = obj[key];
      
      if (typeof value === 'string') {
        const replaced = this.replaceVariables(value, variables);
        // 只对特定的分页字段进行数字转换
        const isNumeric = /^\d+$/.test(replaced);
        const shouldConvertToNumber = replaced !== value && isNumeric && numericFields.indexOf(key) !== -1;
        logger.debug(TAG, `变量替换: key="${key}", 原值="${value}", 替换后="${replaced}", 是否数字=${isNumeric}, 是否转换=${shouldConvertToNumber}`);
        if (shouldConvertToNumber) {
          const numValue = parseInt(replaced);
          logger.debug(TAG, `转换为数字: ${numValue}`);
          result[key] = numValue;
        } else {
          result[key] = replaced;
        }
      } else if (typeof value === 'object' && value !== null) {
        result[key] = this.replaceObjectVariables(value as ESObject, variables);
      } else {
        result[key] = value;
      }
    }
    
    return result;
  }

  /**
   * 替换变量
   */
  private needsCookieAuthHeaders(url: string): boolean {
    const lowerUrl: string = url.toLowerCase();
    if (lowerUrl.includes('/api/v3/member/')) {
      return true;
    }
    if (lowerUrl.includes('/api/kb/web/browses')) {
      return true;
    }
    return false;
  }

  private ensureCopyMangaPlatformParam(url: string): string {
    const lowerUrl: string = url.toLowerCase();
    const isCollectApi: boolean = lowerUrl.includes('https://www.mangacopy.com/api/v3/member/collect/comics');
    const isBrowseApi: boolean = lowerUrl.includes('https://www.mangacopy.com/api/kb/web/browses');
    if (!isCollectApi && !isBrowseApi) {
      return url;
    }

    const hasPlatformParam: boolean = /(?:\?|&)platform=/i.test(url);
    if (hasPlatformParam) {
      return url;
    }

    const separator: string = url.includes('?') ? '&' : '?';
    return `${url}${separator}platform=3`;
  }

  private removeHeaderCanonical(headers: Record<string, string>, headerName: string): Record<string, string> {
    const targetHeaderName: string = headerName.toLowerCase();
    const normalizedHeaders: Record<string, string> = {};
    const keys: string[] = Object.keys(headers);
    for (let i: number = 0; i < keys.length; i++) {
      const key: string = keys[i];
      if (key.toLowerCase() !== targetHeaderName) {
        normalizedHeaders[key] = headers[key];
      }
    }
    return normalizedHeaders;
  }

  private setHeaderCanonical(headers: Record<string, string>, headerName: string, value: string): Record<string, string> {
    const normalizedHeaders: Record<string, string> = this.removeHeaderCanonical(headers, headerName);
    normalizedHeaders[headerName] = value;
    return normalizedHeaders;
  }

  private extractCookieValue(cookieString: string, cookieName: string): string {
    const segments: string[] = cookieString.split(';');
    for (let i: number = segments.length - 1; i >= 0; i--) {
      const segment: string = segments[i].trim();
      if (segment.length === 0) {
        continue;
      }

      const equalIndex: number = segment.indexOf('=');
      if (equalIndex <= 0) {
        continue;
      }

      const key: string = segment.substring(0, equalIndex).trim();
      if (key === cookieName) {
        const rawValue: string = segment.substring(equalIndex + 1).trim();
        try {
          return decodeURIComponent(rawValue);
        } catch (_decodeError) {
          return rawValue;
        }
      }
    }
    return '';
  }

  private injectAuthHeadersFromCookie(
    url: string,
    headers: Record<string, string>,
    cookieString: string
  ): Record<string, string> {
    if (!this.needsCookieAuthHeaders(url)) {
      return headers;
    }

    let normalizedHeaders: Record<string, string> = headers;
    normalizedHeaders = this.removeHeaderCanonical(normalizedHeaders, 'authorization');
    normalizedHeaders = this.removeHeaderCanonical(normalizedHeaders, 'token');
    normalizedHeaders = this.removeHeaderCanonical(normalizedHeaders, 'x-csrftoken');
    const token: string = this.extractCookieValue(cookieString, 'token');
    const csrfToken: string = this.extractCookieValue(cookieString, 'csrftoken');

    if (token.length > 0) {
      // DRF TokenAuthentication 需要 "Token <value>" 格式
      normalizedHeaders = this.setHeaderCanonical(normalizedHeaders, 'Authorization', `Token ${token}`);
    }

    if (csrfToken.length > 0) {
      normalizedHeaders = this.setHeaderCanonical(normalizedHeaders, 'X-CSRFToken', csrfToken);
    }

    if (token.length > 0 || csrfToken.length > 0) {
      logger.info(
        TAG,
        `自动注入Cookie认证头: token=${token.length > 0 ? 'yes' : 'no'}, csrf=${csrfToken.length > 0 ? 'yes' : 'no'}`
      );
    }
    return normalizedHeaders;
  }

  private isSuccessStatusCode(statusCode: number): boolean {
    return statusCode >= 200 && statusCode < 300;
  }

  private extractApiErrorDetail(responseData: Object | string): string {
    if (typeof responseData === 'string') {
      const trimmedText: string = responseData.trim();
      if (trimmedText.length === 0) {
        return '';
      }
      if (trimmedText.length > 200) {
        return `${trimmedText.substring(0, 200)}...`;
      }
      return trimmedText;
    }

    const responseObject: Record<string, Object> = responseData as Record<string, Object>;
    const detailValue: Object | undefined = responseObject['detail'];
    if (detailValue !== undefined && detailValue !== null) {
      return String(detailValue);
    }

    const messageValue: Object | undefined = responseObject['message'];
    if (messageValue !== undefined && messageValue !== null) {
      return String(messageValue);
    }

    const errorValue: Object | undefined = responseObject['error'];
    if (errorValue !== undefined && errorValue !== null) {
      return String(errorValue);
    }

    const codeValue: Object | undefined = responseObject['code'];
    if (codeValue !== undefined && codeValue !== null) {
      return String(codeValue);
    }

    try {
      const jsonText: string = JSON.stringify(responseData);
      if (jsonText.length > 200) {
        return `${jsonText.substring(0, 200)}...`;
      }
      return jsonText;
    } catch (_stringifyError) {
      return '';
    }
  }

  private replaceVariables(text: string, variables: Record<string, string>): string {
    let result = text;
    for (const key of Object.keys(variables)) {
      const value = variables[key];
      if (value !== undefined) {
        result = result.replace(new RegExp(`\\{\\{${key}\\}\\}`, 'g'), value);
      }
    }
    return result;
  }

  /**
   * 休眠
   */
  private async sleep(ms: number): Promise<void> {
    return new Promise<void>(resolve => setTimeout(resolve, ms));
  }
}
