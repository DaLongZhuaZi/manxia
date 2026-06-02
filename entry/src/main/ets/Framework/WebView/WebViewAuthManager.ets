import { SafeUtils } from '../../Utils/SafeUtils';
// 文件路径：entry/src/main/ets/Framework/WebView/WebViewAuthManager.ets
/**
 * WebView登录与Cookie管理器（全局单例）
 */
 
import { webview } from '@kit.ArkWeb';
import { logger } from '../../Utils/Logger';
import { DataManager } from '../Data/DataManager';

const TAG: string = 'WebViewAuthManager';

/**
 * Cookie条目接口
 */
interface CookieEntry {
  name: string;
  value: string;
  domain?: string;
  path?: string;
  expires?: number;
  httpOnly?: boolean;
  secure?: boolean;
}

/**
 * WebView登录与Cookie管理器（全局单例）
 */
export class WebViewAuthManager {
  private static instance: WebViewAuthManager | null = null;
  private readonly dataManager: DataManager;
  private readonly defaultTtlMs: number = 7 * 24 * 60 * 60 * 1000;

  private constructor() {
    this.dataManager = DataManager.getInstance();
  }

  static getInstance(): WebViewAuthManager {
    if (!WebViewAuthManager.instance) {
      WebViewAuthManager.instance = new WebViewAuthManager();
    }
    return WebViewAuthManager.instance;
  }

  /**
   * 解析 document.cookie 字符串为 CookieEntry 数组
   */
  private parseDocumentCookieString(cookieStr: string): CookieEntry[] {
    const result: CookieEntry[] = [];
    if (!cookieStr || cookieStr.length === 0) {
      return result;
    }
    let normalizedCookieString: string = cookieStr.replace(/\\"/g, '');
    normalizedCookieString = normalizedCookieString.replace(/^"|"$/g, '');
    normalizedCookieString = normalizedCookieString.replace(/;\s*;/g, ';').trim();
    if (normalizedCookieString.length === 0) {
      return result;
    }
    const parts: string[] = normalizedCookieString.split(';');
    let i: number = 0;
    while (i < parts.length) {
      const part: string = parts[i].trim();
      const eqIndex: number = part.indexOf('=');
      if (eqIndex > 0) {
        const name: string = part.substring(0, eqIndex);
        const value: string = part.substring(eqIndex + 1);
        const entry: CookieEntry = {
          name,
          value,
          expires: Date.now() + this.defaultTtlMs
        } as CookieEntry;
        result.push(entry);
      }
      i = i + 1;
    }
    return result;
  }

  private extractOriginUrl(url: string): string {
    const trimmedUrl: string = url.trim();
    if (trimmedUrl.length === 0) {
      return '';
    }
    const matched: RegExpMatchArray | null = trimmedUrl.match(/^(https?:\/\/[^\/]+)/);
    if (matched && matched.length > 1) {
      return String(matched[1]);
    }
    return '';
  }

  private getControllerUrl(controller: webview.WebviewController): string {
    try {
      const currentUrl: string = String(controller.getUrl()).trim();
      if (currentUrl.length > 0) {
        return currentUrl;
      }
    } catch (error) {
      logger.debug(TAG, `读取WebView当前URL失败: ${String(error)}`);
    }
    return '';
  }

  private async captureCookiesFromWebEngine(sourceId: number, url: string): Promise<boolean> {
    const normalizedUrl: string = url.trim();
    if (normalizedUrl.length === 0 || normalizedUrl === 'about:blank') {
      return false;
    }

    try {
      await webview.WebCookieManager.saveCookieAsync();
    } catch (saveError) {
      logger.debug(TAG, `WebCookieManager保存Cookie失败，继续尝试读取: ${String(saveError)}`);
    }

    try {
      const cookieStr: string = await webview.WebCookieManager.fetchCookie(normalizedUrl);
      const incoming: CookieEntry[] = this.parseDocumentCookieString(cookieStr);
      if (incoming.length === 0) {
        logger.debug(TAG, `WebCookieManager返回Cookie为空: sourceId=${sourceId}, url=${normalizedUrl}`);
        return false;
      }
      const normalizedIncoming: CookieEntry[] = this.mergeCookies([], incoming);
      const json: string = this.serializeCookies(normalizedIncoming);
      const merged: CookieEntry[] = normalizedIncoming;
      await this.dataManager.updateComicSourceCookies(sourceId, json);
      logger.info(TAG, `通过WebCookieManager捕获并保存Cookie(${incoming.length}条), 合并后${merged.length}条: sourceId=${sourceId}, url=${normalizedUrl}`);
      return true;
    } catch (error) {
      logger.debug(TAG, `通过WebCookieManager捕获Cookie失败: sourceId=${sourceId}, url=${normalizedUrl}, error=${String(error)}`);
      return false;
    }
  }

  /**
   * 合并并去重 CookieEntry（按 name）
   */
  private mergeCookies(existing: CookieEntry[], incoming: CookieEntry[]): CookieEntry[] {
    const merged: CookieEntry[] = [];
    let i: number = 0;
    const usedNames: string[] = [];
    while (i < existing.length) {
      const e: CookieEntry = existing[i] as CookieEntry;
      merged.push(e);
      usedNames.push(e.name);
      i = i + 1;
    }
    let j: number = 0;
    while (j < incoming.length) {
      const inc: CookieEntry = incoming[j] as CookieEntry;
      const exists: boolean = usedNames.indexOf(inc.name) >= 0;
      if (!exists) {
        merged.push(inc);
        usedNames.push(inc.name);
      } else {
        // 覆盖同名cookie的值
        let k: number = 0;
        while (k < merged.length) {
          if (merged[k].name === inc.name) {
            merged[k] = inc;
            break;
          }
          k = k + 1;
        }
      }
      j = j + 1;
    }
    return merged;
  }

  /**
   * 将 CookieEntry 数组序列化为 JSON（存入数据库）
   */
  private serializeCookies(cookies: CookieEntry[]): string {
    return JSON.stringify(cookies);
  }

  /**
   * 从 JSON 反序列化为 CookieEntry 数组
   */
  private deserializeCookies(json: string): CookieEntry[] {
    if (!json || json.length === 0) {
      return [];
    }
    try {
      const arr = SafeUtils.parseArr(json) as Object[];
      const result: CookieEntry[] = [];
      let i: number = 0;
      while (i < arr.length) {
        const item: Object = arr[i] as Object;
        const obj = item as Record<string, Object>;
        const name = obj['name'] as string;
        const value = obj['value'] as string;
        const domain = obj['domain'] ? (obj['domain'] as string) : undefined;
        const path = obj['path'] ? (obj['path'] as string) : undefined;
        const expires = obj['expires'] ? Number(obj['expires']) : undefined;
        const httpOnly = obj['httpOnly'] ? Boolean(obj['httpOnly']) : undefined;
        const secure = obj['secure'] ? Boolean(obj['secure']) : undefined;
        result.push({ name, value, domain, path, expires, httpOnly, secure } as CookieEntry);
        i = i + 1;
      }
      return result;
    } catch (error) {
      logger.error(TAG, '反序列化Cookie失败', String(error));
      return [];
    }
  }

  /**
   * 将已有Cookie应用到WebView控制器（在页面加载前调用）
   */
  async applyCookiesToController(sourceId: number, controller: webview.WebviewController): Promise<void> {
    try {
      const srcRecord = await this.dataManager.getComicSourceById(sourceId);
      if (!srcRecord) { 
        logger.warn(TAG, `图源不存在，无法注入Cookie: sourceId=${sourceId}`);
        return; 
      }
      const cookiesJson: string = srcRecord.cookies ? String(srcRecord.cookies) : '';
      if (!cookiesJson || cookiesJson.length === 0) {
        logger.debug(TAG, `图源无Cookie，跳过注入: sourceId=${sourceId}`);
        return;
      }
      
      const cookies: CookieEntry[] = this.deserializeCookies(cookiesJson);
      if (cookies.length === 0) {
        logger.debug(TAG, `Cookie解析为空，跳过注入: sourceId=${sourceId}`);
        return;
      }
      
      // 过滤过期的Cookie
      const now: number = Date.now();
      const validCookies: CookieEntry[] = [];
      let i: number = 0;
      while (i < cookies.length) {
        const c: CookieEntry = cookies[i] as CookieEntry;
        if (c.expires === undefined || now < c.expires) {
          validCookies.push(c);
        } else {
          logger.debug(TAG, `跳过过期Cookie: ${c.name}`);
        }
        i = i + 1;
      }
      
      if (validCookies.length === 0) {
        logger.warn(TAG, `所有Cookie已过期，跳过注入: sourceId=${sourceId}`);
        return;
      }
      
      // 注入Cookie
      let successCount: number = 0;
      let j: number = 0;
      while (j < validCookies.length) {
        const c: CookieEntry = validCookies[j] as CookieEntry;
        try {
          const path: string = c.path ? c.path : '/';
          const domain: string = c.domain ? `; domain=${c.domain}` : '';
          const secure: string = c.secure ? '; secure' : '';
          const js: string = `document.cookie = '${c.name}=${c.value}; path=${path}${domain}${secure}'; true;`;
          await controller.runJavaScript(js);
          successCount = successCount + 1;
          logger.debug(TAG, `注入Cookie成功: ${c.name}`);
        } catch (err) {
          logger.warn(TAG, `注入Cookie失败: ${c.name}, error=${String(err)}`);
        }
        j = j + 1;
      }
      
      logger.info(TAG, `WebView Cookie注入完成: sourceId=${sourceId}, 成功=${successCount}/${validCookies.length}`);
    } catch (error) {
      logger.error(TAG, '注入Cookie到WebView失败', String(error));
    }
  }

  /**
   * 从WebView控制器获取document.cookie并存储到数据库
   */
  async captureCookiesFromController(sourceId: number, controller: webview.WebviewController): Promise<void> {
    try {
      const currentUrl: string = this.getControllerUrl(controller);
      if (currentUrl.length > 0) {
        const exactCaptured: boolean = await this.captureCookiesFromWebEngine(sourceId, currentUrl);
        if (exactCaptured) {
          return;
        }
        const originUrl: string = this.extractOriginUrl(currentUrl);
        if (originUrl.length > 0 && originUrl !== currentUrl) {
          const originCaptured: boolean = await this.captureCookiesFromWebEngine(sourceId, originUrl);
          if (originCaptured) {
            return;
          }
        }
      }

      if (currentUrl === 'about:blank') {
        logger.debug(TAG, `当前页面为 about:blank，跳过 document.cookie 捕获: sourceId=${sourceId}`);
        return;
      }

      const cookieStr: string = await controller.runJavaScript('document.cookie');
      const incoming: CookieEntry[] = this.parseDocumentCookieString(cookieStr);
      if (incoming.length === 0) {
        logger.debug(TAG, `document.cookie 为空，跳过保存: sourceId=${sourceId}`);
        return;
      }
      const merged: CookieEntry[] = this.mergeCookies([], incoming);
      const json: string = this.serializeCookies(merged);
      await this.dataManager.updateComicSourceCookies(sourceId, json);
      logger.info(TAG, `已捕获并保存Cookie(${incoming.length}条), 合并后${merged.length}条: sourceId=${sourceId}`);
    } catch (error) {
      logger.error(TAG, '捕获Cookie失败', String(error));
    }
  }

  /**
   * 直接使用用户输入的原始Cookie字符串进行登录（注入并保存）
   */
  async loginWithCookieString(sourceId: number, controller: webview.WebviewController | null, rawCookie: string): Promise<void> {
    const entries: CookieEntry[] = this.parseDocumentCookieString(rawCookie);
    const json: string = this.serializeCookies(entries);
    await this.dataManager.updateComicSourceCookies(sourceId, json);
    if (controller) {
      await this.applyCookiesToController(sourceId, controller);
    }
    logger.info(TAG, `已保存并应用用户输入的Cookie: sourceId=${sourceId}`);
  }

  private async delay(ms: number): Promise<void> {
    await new Promise<void>((resolve) => {
      setTimeout(() => { resolve(); }, ms);
    });
  }

  async performFormLogin(
    sourceId: number,
    controller: webview.WebviewController,
    url: string,
    username: string,
    password: string,
    usernameSelector: string,
    passwordSelector: string,
    submitSelector: string
  ): Promise<void> {
    try {
      controller.loadUrl(url);
      await this.delay(1000);
      const js: string = `
        (function(){
          var u = document.querySelector('${usernameSelector}');
          var p = document.querySelector('${passwordSelector}');
          var b = document.querySelector('${submitSelector}');
          if (u) { u.value = '${username}'; }
          if (p) { p.value = '${password}'; }
          if (b) { b.click(); }
          return 'ok';
        })();
      `;
      await controller.runJavaScript(js);
      await this.delay(1500);
      await this.captureCookiesFromController(sourceId, controller);
      logger.info(TAG, `表单登录完成并捕获Cookie: sourceId=${sourceId}`);
    } catch (error) {
      logger.error(TAG, '表单登录失败', String(error));
    }
  }

  /**
   * 保存用户名与密码（不直接登录，供工作流或页面使用）
   */
  async saveCredentials(sourceId: number, username: string, password: string): Promise<void> {
    await this.dataManager.saveSourceCredentials(sourceId, username, password);
    logger.info(TAG, `已保存图源凭据: sourceId=${sourceId}`);
  }

  /**
   * 清空Cookie
   */
  async clearCookies(sourceId: number): Promise<void> {
    await this.dataManager.clearComicSourceCookies(sourceId);
    logger.info(TAG, `已清空Cookie: sourceId=${sourceId}`);
  }
}
