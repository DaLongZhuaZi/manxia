import { SafeUtils } from '../../Utils/SafeUtils';
/**
 * Legado Cookie存储管理
 * 提供Cookie的持久化存储和管理功能
 * 
 * 文件路径: entry/src/main/ets/Framework/Novel/LegadoCookieStore.ets
 */

import { preferences } from '@kit.ArkData';
import { logger } from '../../Utils/Logger';

const TAG = 'LegadoCookieStore';
const PREFERENCES_NAME = 'legado_cookies';

/**
 * Cookie项接口
 */
export interface CookieItem {
  name: string;
  value: string;
  domain: string;
  path: string;
  expires?: number;
  secure?: boolean;
  httpOnly?: boolean;
}

/**
 * Cookie存储管理类
 */
export class LegadoCookieStore {
  private static instance: LegadoCookieStore | null = null;
  private cookies: Map<string, Map<string, CookieItem>> = new Map();
  private dataPreferences: preferences.Preferences | null = null;
  private initialized: boolean = false;
  private context: Context | null = null;

  private constructor() {}

  static getInstance(): LegadoCookieStore {
    if (!LegadoCookieStore.instance) {
      LegadoCookieStore.instance = new LegadoCookieStore();
    }
    return LegadoCookieStore.instance;
  }

  /**
   * 初始化Cookie存储
   */
  async init(context: Context): Promise<void> {
    if (this.initialized) return;
    
    try {
      this.context = context;
      this.dataPreferences = await preferences.getPreferences(context, PREFERENCES_NAME);
      await this.loadCookies();
      this.initialized = true;
      logger.info(TAG, 'Cookie存储初始化成功');
    } catch (error) {
      logger.error(TAG, `Cookie存储初始化失败: ${String(error)}`);
    }
  }

  /**
   * 从持久化存储加载Cookie
   */
  private async loadCookies(): Promise<void> {
    if (!this.dataPreferences) return;
    
    try {
      const cookieData = await this.dataPreferences.get('cookies', '{}');
      const parsed = SafeUtils.parseObj(cookieData as string) as Record<string, Record<string, CookieItem>>;
      
      for (const domain of Object.keys(parsed)) {
        const domainCookies = new Map<string, CookieItem>();
        for (const name of Object.keys(parsed[domain])) {
          domainCookies.set(name, parsed[domain][name]);
        }
        this.cookies.set(domain, domainCookies);
      }
      
      logger.debug(TAG, `加载了 ${this.cookies.size} 个域名的Cookie`);
    } catch (error) {
      logger.warn(TAG, `加载Cookie失败: ${String(error)}`);
    }
  }

  /**
   * 保存Cookie到持久化存储
   */
  private async saveCookies(): Promise<void> {
    if (!this.dataPreferences) return;
    
    try {
      const data: Record<string, Record<string, CookieItem>> = {};
      
      this.cookies.forEach((domainCookies, domain) => {
        data[domain] = {};
        domainCookies.forEach((cookie, name) => {
          data[domain][name] = cookie;
        });
      });
      
      await this.dataPreferences.put('cookies', JSON.stringify(data));
      await this.dataPreferences.flush();
    } catch (error) {
      logger.warn(TAG, `保存Cookie失败: ${String(error)}`);
    }
  }

  /**
   * 设置Cookie
   */
  async setCookie(url: string, cookieStr: string): Promise<void> {
    const domain = this.extractDomain(url);
    if (!domain) return;
    
    const cookies = this.parseCookieString(cookieStr, domain);
    
    if (!this.cookies.has(domain)) {
      this.cookies.set(domain, new Map());
    }
    
    const domainCookies = this.cookies.get(domain)!;
    for (const cookie of cookies) {
      domainCookies.set(cookie.name, cookie);
    }
    
    await this.saveCookies();
  }

  /**
   * 获取Cookie
   */
  getCookie(url: string): string {
    const domain = this.extractDomain(url);
    if (!domain) return '';
    
    const domainCookies = this.cookies.get(domain);
    if (!domainCookies) return '';
    
    const now = Date.now();
    const validCookies: string[] = [];
    
    domainCookies.forEach((cookie, name) => {
      // 检查是否过期
      if (cookie.expires && cookie.expires < now) {
        domainCookies.delete(name);
        return;
      }
      validCookies.push(`${cookie.name}=${cookie.value}`);
    });
    
    return validCookies.join('; ');
  }

  /**
   * 获取指定名称的Cookie值
   */
  getCookieValue(url: string, name: string): string {
    const domain = this.extractDomain(url);
    if (!domain) return '';
    
    const domainCookies = this.cookies.get(domain);
    if (!domainCookies) return '';
    
    const cookie = domainCookies.get(name);
    if (!cookie) return '';
    
    // 检查是否过期
    if (cookie.expires && cookie.expires < Date.now()) {
      domainCookies.delete(name);
      return '';
    }
    
    return cookie.value;
  }

  /**
   * 按标签获取Cookie（兼容Legado格式）
   */
  getCookieByTag(tag: string, key?: string): string {
    // tag通常是域名或书源标识
    const domain = tag.includes('.') ? tag : '';
    
    if (key) {
      // 获取指定key的cookie值
      if (domain) {
        return this.getCookieValue(`https://${domain}`, key);
      }
      // 遍历所有域名查找
      const domains = Array.from(this.cookies.keys());
      for (let i = 0; i < domains.length; i++) {
        const domainCookies = this.cookies.get(domains[i]);
        if (domainCookies) {
          const cookie = domainCookies.get(key);
          if (cookie) {
            return cookie.value;
          }
        }
      }
      return '';
    }
    
    // 获取整个cookie字符串
    if (domain) {
      return this.getCookie(`https://${domain}`);
    }
    return '';
  }

  /**
   * 删除Cookie
   */
  async removeCookie(url: string, name?: string): Promise<void> {
    const domain = this.extractDomain(url);
    if (!domain) return;
    
    if (name) {
      const domainCookies = this.cookies.get(domain);
      if (domainCookies) {
        domainCookies.delete(name);
      }
    } else {
      this.cookies.delete(domain);
    }
    
    await this.saveCookies();
  }

  /**
   * 清除所有Cookie
   */
  async clearAllCookies(): Promise<void> {
    this.cookies.clear();
    await this.saveCookies();
  }

  /**
   * 清除指定域名的Cookie
   */
  async clearCookies(domain: string): Promise<void> {
    this.cookies.delete(domain);
    await this.saveCookies();
  }

  /**
   * 解析Cookie字符串
   */
  private parseCookieString(cookieStr: string, domain: string): CookieItem[] {
    const cookies: CookieItem[] = [];
    
    // 分割多个cookie
    const parts = cookieStr.split(';').map(s => s.trim());
    
    if (parts.length === 0) return cookies;
    
    // 第一部分是name=value
    const firstPart = parts[0];
    const eqIndex = firstPart.indexOf('=');
    if (eqIndex === -1) return cookies;
    
    const cookie: CookieItem = {
      name: firstPart.substring(0, eqIndex).trim(),
      value: firstPart.substring(eqIndex + 1).trim(),
      domain: domain,
      path: '/'
    };
    
    // 解析其他属性
    for (let i = 1; i < parts.length; i++) {
      const part = parts[i];
      const attrEqIndex = part.indexOf('=');
      
      if (attrEqIndex === -1) {
        const attrName = part.toLowerCase();
        if (attrName === 'secure') {
          cookie.secure = true;
        } else if (attrName === 'httponly') {
          cookie.httpOnly = true;
        }
      } else {
        const attrName = part.substring(0, attrEqIndex).trim().toLowerCase();
        const attrValue = part.substring(attrEqIndex + 1).trim();
        
        switch (attrName) {
          case 'domain':
            cookie.domain = attrValue;
            break;
          case 'path':
            cookie.path = attrValue;
            break;
          case 'expires':
            try {
              cookie.expires = new Date(attrValue).getTime();
            } catch (e) {
              // 忽略解析错误
            }
            break;
          case 'max-age':
            try {
              const maxAge = parseInt(attrValue);
              cookie.expires = Date.now() + maxAge * 1000;
            } catch (e) {
              // 忽略解析错误
            }
            break;
        }
      }
    }
    
    cookies.push(cookie);
    return cookies;
  }

  /**
   * 从URL提取域名
   */
  private extractDomain(url: string): string {
    try {
      // 处理简单的域名格式
      if (!url.includes('://')) {
        return url.split('/')[0];
      }
      
      const match = url.match(/^https?:\/\/([^\/]+)/);
      if (match) {
        return match[1];
      }
      return '';
    } catch (e) {
      return '';
    }
  }

  /**
   * 合并Cookie字符串
   */
  mergeCookies(existing: string, newCookies: string): string {
    const cookieMap = new Map<string, string>();
    
    // 解析现有cookie
    if (existing) {
      existing.split(';').forEach(part => {
        const trimmed = part.trim();
        const eqIndex = trimmed.indexOf('=');
        if (eqIndex > 0) {
          cookieMap.set(trimmed.substring(0, eqIndex), trimmed.substring(eqIndex + 1));
        }
      });
    }
    
    // 合并新cookie
    if (newCookies) {
      newCookies.split(';').forEach(part => {
        const trimmed = part.trim();
        const eqIndex = trimmed.indexOf('=');
        if (eqIndex > 0) {
          cookieMap.set(trimmed.substring(0, eqIndex), trimmed.substring(eqIndex + 1));
        }
      });
    }
    
    // 生成合并后的字符串
    const result: string[] = [];
    cookieMap.forEach((value, name) => {
      result.push(`${name}=${value}`);
    });
    
    return result.join('; ');
  }
}

/**
 * 获取Cookie存储实例
 */
export function getCookieStore(): LegadoCookieStore {
  return LegadoCookieStore.getInstance();
}
