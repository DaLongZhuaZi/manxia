// 文件路径：entry/src/main/ets/Framework/Managers/CookieManager.ets
/**
 * 全局 Cookie 管理器（与 WebView 配合）
 * 需求：
 *  - 当数据库无 Cookie 时，所有请求不携带 Cookie
 *  - 当数据库存在 Cookie 时，为请求构建带 Cookie 的请求头
 *  - 支持通过不带 Cookie 的默认请求获取服务器下发的 Set-Cookie 并保存
 *  - 与图源设置页面联动：信息展示、手动获取、手动设置
 */

import { http } from '@kit.NetworkKit';
import { webview } from '@kit.ArkWeb';
import { logger } from '../../Utils/Logger';
import { DataManager } from '../Data/DataManager';
import { RequestHeaders } from '../Cache/ImageCacheManager';

const TAG: string = 'CookieManager';

interface CookieEntry {
  name: string;
  value: string;
  domain?: string;
  path?: string;
  expires?: number;
  httpOnly?: boolean;
  secure?: boolean;
}

export interface CookieInfo {
  hasCookie: boolean;
  cookieCount: number;
  updateTime?: number;
}

interface HttpHeadersObject {
  'User-Agent'?: string;
  'Accept-Language'?: string;
  'Cache-Control'?: string;
}

export class CookieManager {
  private static instance: CookieManager | null = null;
  private readonly dataManager: DataManager;
  private readonly defaultTtlMs: number = 7 * 24 * 60 * 60 * 1000;

  private constructor() {
    this.dataManager = DataManager.getInstance();
  }

  static getInstance(): CookieManager {
    if (CookieManager.instance === null) {
      CookieManager.instance = new CookieManager();
    }
    return CookieManager.instance as CookieManager;
  }

  private parseCookiesJson(jsonStr: string): CookieEntry[] {
    if (!jsonStr || jsonStr.length === 0) {
      return [];
    }
    try {
      const arr: Object[] = JSON.parse(jsonStr) as Object[];
      const result: CookieEntry[] = [];
      let i: number = 0;
      while (i < arr.length) {
        const itemObj: Record<string, Object> = arr[i] as Record<string, Object>;
        const keys: string[] = Object.keys(itemObj);
        let name: string = '';
        let value: string = '';
        let domain: string | undefined = undefined;
        let path: string | undefined = undefined;
        let expires: number | undefined = undefined;
        let httpOnly: boolean | undefined = undefined;
        let secure: boolean | undefined = undefined;
        if (keys.includes('name')) { name = String(itemObj['name']); }
        if (keys.includes('value')) { value = String(itemObj['value']); }
        if (keys.includes('domain')) { domain = String(itemObj['domain']); }
        if (keys.includes('path')) { path = String(itemObj['path']); }
        if (keys.includes('expires')) { expires = Number(itemObj['expires']); }
        if (keys.includes('httpOnly')) { httpOnly = Boolean(itemObj['httpOnly']); }
        if (keys.includes('secure')) { secure = Boolean(itemObj['secure']); }
        if (name.length > 0) {
          result.push({ name: name, value: value, domain: domain, path: path, expires: expires, httpOnly: httpOnly, secure: secure } as CookieEntry);
        }
        i = i + 1;
      }
      return result;
    } catch (error) {
      logger.warn(TAG, `Cookie JSON 解析失败: ${String(error)}`);
      return [];
    }
  }

  private serializeCookies(entries: CookieEntry[]): string {
    return JSON.stringify(entries);
  }

  async getCookieInfo(sourceId: number): Promise<CookieInfo> {
    try {
      const srcRecord = await this.dataManager.getComicSourceById(sourceId);
      if (!srcRecord) { return { hasCookie: false, cookieCount: 0 } as CookieInfo; }
      let cookiesJson: string = srcRecord.cookies ? String(srcRecord.cookies) : '';
      if (!cookiesJson || cookiesJson.length === 0) {
        return { hasCookie: false, cookieCount: 0 } as CookieInfo;
      }
      
      const entries: CookieEntry[] = this.parseCookiesJson(cookiesJson);
      
      // 统计有效Cookie数量
      const now: number = Date.now();
      let validCount: number = 0;
      let i: number = 0;
      while (i < entries.length) {
        const e: CookieEntry = entries[i] as CookieEntry;
        const exp: number | undefined = e.expires;
        if (exp === undefined || now < exp) {
          validCount = validCount + 1;
        }
        i = i + 1;
      }
      
      const updateTime: number | undefined = undefined;
      const has: boolean = validCount > 0;
      return { hasCookie: has, cookieCount: validCount, updateTime: updateTime } as CookieInfo;
    } catch (error) {
      logger.error(TAG, '获取 Cookie 信息失败', String(error));
      return { hasCookie: false, cookieCount: 0 } as CookieInfo;
    }
  }

  async hasCookie(sourceId: number): Promise<boolean> {
    try {
      const srcRecord = await this.dataManager.getComicSourceById(sourceId);
      if (!srcRecord) { return false; }
      let cookiesJson: string = srcRecord.cookies ? String(srcRecord.cookies) : '';
      if (!cookiesJson || cookiesJson.length === 0) {
        return false;
      }
      
      const entries: CookieEntry[] = this.parseCookiesJson(cookiesJson);
      if (entries.length === 0) {
        return false;
      }
      
      const now: number = Date.now();
      let anyValid: boolean = false;
      let i: number = 0;
      while (i < entries.length) {
        const e: CookieEntry = entries[i] as CookieEntry;
        const exp: number | undefined = e.expires;
        // 没有过期时间或未过期的Cookie都认为有效
        if (exp === undefined || now < exp) {
          anyValid = true;
          break;
        }
        i = i + 1;
      }
      return anyValid;
    } catch (_err) {
      return false;
    }
  }

  async getCookieString(sourceId: number): Promise<string> {
    try {
      const srcRecord = await this.dataManager.getComicSourceById(sourceId);
      if (!srcRecord) { 
        logger.debug(TAG, `图源不存在: sourceId=${sourceId}`);
        return ''; 
      }
      let cookiesJson: string = srcRecord.cookies ? String(srcRecord.cookies) : '';
      if (!cookiesJson || cookiesJson.length === 0) {
        logger.debug(TAG, `图源无Cookie: sourceId=${sourceId}`);
        return '';
      }
      
      const entries: CookieEntry[] = this.parseCookiesJson(cookiesJson);
      if (entries.length === 0) {
        logger.debug(TAG, `Cookie解析为空: sourceId=${sourceId}`);
        return '';
      }
      
      // 过滤过期的Cookie
      const now: number = Date.now();
      const validEntries: CookieEntry[] = [];
      let i: number = 0;
      while (i < entries.length) {
        const e: CookieEntry = entries[i] as CookieEntry;
        const exp: number | undefined = e.expires;
        if (exp === undefined || now < exp) {
          validEntries.push(e);
        } else {
          logger.debug(TAG, `跳过过期Cookie: ${e.name}, expires=${exp}`);
        }
        i = i + 1;
      }
      
      if (validEntries.length === 0) {
        logger.warn(TAG, `所有Cookie已过期: sourceId=${sourceId}`);
        return '';
      }
      
      const parts: string[] = [];
      let j: number = 0;
      while (j < validEntries.length) {
        const e: CookieEntry = validEntries[j] as CookieEntry;
        // 过滤掉值为空的Cookie
        if (e.value && e.value.length > 0) {
          parts.push(`${e.name}=${e.value}`);
        } else {
          logger.debug(TAG, `跳过空值Cookie: ${e.name}`);
        }
        j = j + 1;
      }
      
      if (parts.length === 0) {
        logger.warn(TAG, `所有Cookie值为空: sourceId=${sourceId}`);
        return '';
      }
      
      let cookieStr: string = parts.join('; ');
      
      // [修复] 清理Cookie字符串中的转义字符和多余引号
      // 移除转义的引号: \" -> "
      cookieStr = cookieStr.replace(/\\"/g, '');
      // 移除单独的引号: " -> (空)
      cookieStr = cookieStr.replace(/"/g, '');
      // 移除多余的分号和空格
      cookieStr = cookieStr.replace(/;\s*;/g, ';').trim();
      
      logger.debug(TAG, `获取Cookie成功: sourceId=${sourceId}, count=${parts.length}, length=${cookieStr.length}`);
      return cookieStr;
    } catch (error) {
      logger.error(TAG, '读取 Cookie 字符串失败', String(error));
      return '';
    }
  }

  async buildHeadersWithCookie(base: RequestHeaders | undefined, sourceId: number): Promise<RequestHeaders> {
    const result: RequestHeaders = {} as RequestHeaders;
    if (base) {
      if (base.userAgent) { result.userAgent = String(base.userAgent); }
      if (base.accept) { result.accept = String(base.accept); }
      if (base.referer) { result.referer = String(base.referer); }
      if (base.authorization) { result.authorization = String(base.authorization); }
      if (base.acceptLanguage) { result.acceptLanguage = String(base.acceptLanguage); }
      if (base.cacheControl) { result.cacheControl = String(base.cacheControl); }
      if (base.pragma) { result.pragma = String(base.pragma); }
      if (base.secFetchDest) { result.secFetchDest = String(base.secFetchDest); }
      if (base.secFetchMode) { result.secFetchMode = String(base.secFetchMode); }
      if (base.secFetchSite) { result.secFetchSite = String(base.secFetchSite); }
    }
    const cookieStr: string = await this.getCookieString(sourceId);
    if (cookieStr.length > 0) {
      result.cookie = cookieStr;
    }
    return result;
  }

  async refreshCookiesIfNeeded(sourceId: number, controller: webview.WebviewController | null, baseUrl: string): Promise<boolean> {
    const valid: boolean = await this.hasCookie(sourceId);
    if (valid) { return true; }
    return await this.forceCaptureWebViewCookies(sourceId, controller, baseUrl);
  }

  /**
   * 强制从WebView捕获Cookie（用于CF验证后强制刷新）
   * 不检查现有Cookie，直接从WebView提取并保存
   */
  async forceCaptureWebViewCookies(sourceId: number, controller: webview.WebviewController | null, baseUrl: string): Promise<boolean> {
    let captured: boolean = false;
    try {
      if (controller) {
        const js: string = 'document.cookie';
        const resultStr: string = await controller.runJavaScript(js) as string;
        logger.info(TAG, `从WebView捕获Cookie: sourceId=${sourceId}, rawLength=${resultStr?.length || 0}`);
        
        const entries: CookieEntry[] = [];
        const cookieStr: string = resultStr || '';
        
        // 清理可能的引号包裹
        const cleanedStr: string = cookieStr.replace(/^"|"$/g, '');
        const parts: string[] = cleanedStr.split(';');
        let p: number = 0;
        while (p < parts.length) {
          const item: string = parts[p].trim();
          const eqIndex: number = item.indexOf('=');
          if (eqIndex > 0) {
            const name: string = item.substring(0, eqIndex);
            const value: string = item.substring(eqIndex + 1);
            // 特别记录CF相关Cookie
            if (name.includes('cf_') || name.includes('__cf')) {
              logger.info(TAG, `捕获到CF Cookie: ${name}`);
            }
            entries.push({ name: name, value: value, expires: Date.now() + this.defaultTtlMs } as CookieEntry);
          }
          p = p + 1;
        }
        if (entries.length > 0) {
          await this.dataManager.updateComicSourceCookies(sourceId, this.serializeCookies(entries));
          logger.info(TAG, `成功保存${entries.length}个Cookie到数据库: sourceId=${sourceId}`);
          captured = true;
        } else {
          logger.warn(TAG, `WebView中未找到Cookie: sourceId=${sourceId}`);
        }
      }
    } catch (e) {
      logger.error(TAG, `从WebView捕获Cookie失败: ${String(e)}`);
    }
    if (captured) { return true; }
    if (baseUrl && baseUrl.length > 0) {
      const ok: boolean = await this.fetchCookiesByDefaultRequest(sourceId, baseUrl);
      return ok;
    }
    return false;
  }

  async clearCookies(sourceId: number): Promise<void> {
    await this.dataManager.clearComicSourceCookies(sourceId);
  }

  async fetchCookiesByDefaultRequest(sourceId: number, url: string): Promise<boolean> {
    try {
      const headers: HttpHeadersObject = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
        'Accept-Language': 'zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7',
        'Cache-Control': 'no-cache'
      };
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        connectTimeout: 10000,
        readTimeout: 10000,
        header: headers as Object
      };
      const httpRequest: http.HttpRequest = http.createHttp();
      const response: http.HttpResponse = await httpRequest.request(url, options);
      httpRequest.destroy();
      const code: number = response.responseCode;
      const headerEntries: [string, Object][] = Object.entries(response.header as Object) as [string, Object][];
      const headerCount: number = headerEntries.length;
      logger.info(TAG, `默认请求返回: code=${code}, headerKeys=${headerCount}`);

      const setCookieValues: string[] = [];
      let i: number = 0;
      while (i < headerEntries.length) {
        const keyLower: string = headerEntries[i][0].toLowerCase();
        if (keyLower === 'set-cookie') {
          const valObj: Object = headerEntries[i][1];
          const valStr: string = String(valObj);
          setCookieValues.push(valStr);
        }
        i = i + 1;
      }

      if (setCookieValues.length === 0) {
        logger.warn(TAG, '服务器未返回 Set-Cookie');
        return false;
      }

      const entries: CookieEntry[] = [];
      let j: number = 0;
      while (j < setCookieValues.length) {
        const raw: string = setCookieValues[j] as string;
        // 多条 cookie 可能合并在一个字符串，尝试按换行或逗号拆分
        const segments: string[] = raw.split('\n');
        let sIndex: number = 0;
        while (sIndex < segments.length) {
          const seg: string = segments[sIndex].trim();
          if (seg.length > 0) {
            const semiIndex: number = seg.indexOf(';');
            const firstPart: string = semiIndex > 0 ? seg.substring(0, semiIndex) : seg;
            const eqIndex: number = firstPart.indexOf('=');
            if (eqIndex > 0) {
              const name: string = firstPart.substring(0, eqIndex);
              const value: string = firstPart.substring(eqIndex + 1);
              entries.push({ name: name, value: value } as CookieEntry);
            }
          }
          sIndex = sIndex + 1;
        }
        j = j + 1;
      }

      if (entries.length === 0) {
        logger.warn(TAG, '未能解析到有效的 Cookie 条目');
        return false;
      }

      const json: string = this.serializeCookies(entries);
      await this.dataManager.updateComicSourceCookies(sourceId, json);
      logger.info(TAG, `已保存服务器返回的 Cookie，共 ${entries.length} 条: sourceId=${sourceId}`);
      return true;
    } catch (error) {
      logger.error(TAG, '默认请求获取 Cookie 失败', String(error));
      return false;
    }
  }
}

export default CookieManager;
