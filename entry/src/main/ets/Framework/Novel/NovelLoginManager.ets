/**
 * 小说书源登录管理器
 * 处理书源的登录逻辑、Cookie管理
 * 
 * 文件路径: entry/src/main/ets/Framework/Novel/NovelLoginManager.ets
 */

import { logger } from '../../Utils/Logger';
import { LegadoBookSource, LegadoLoginUiItem } from './LegadoSourceTypes';
import { getLegadoJsEngine } from './LegadoJsEngine';
import { preferences } from '@kit.ArkData';

const TAG = 'NovelLoginManager';

/**
 * 登录UI项
 */
export interface LoginUiItem {
  type: 'text' | 'password' | 'button';
  name: string;
  hint?: string;
  value?: string;
}

/**
 * 登录结果
 */
export interface LoginResult {
  success: boolean;
  message?: string;
  cookies?: Record<string, string>;
}

/**
 * 书源登录状态
 */
export interface SourceLoginStatus {
  sourceId: string;
  isLoggedIn: boolean;
  lastLoginTime?: number;
  cookies?: Record<string, string>;
}

// 持久化存储的key前缀
const COOKIE_STORAGE_PREFIX = 'novel_source_cookie_';
const LOGIN_STATUS_STORAGE_KEY = 'novel_login_status';

/**
 * 小说书源登录管理器
 */
export class NovelLoginManager {
  private static instance: NovelLoginManager | null = null;
  private loginStatus: Map<string, SourceLoginStatus> = new Map();
  private cookies: Map<string, Record<string, string>> = new Map();
  private dataPreferences: preferences.Preferences | null = null;
  private initialized: boolean = false;

  private constructor() {}

  static getInstance(): NovelLoginManager {
    if (!NovelLoginManager.instance) {
      NovelLoginManager.instance = new NovelLoginManager();
    }
    return NovelLoginManager.instance;
  }

  /**
   * 初始化登录管理器，加载持久化的Cookie
   */
  async initialize(context: Context): Promise<void> {
    if (this.initialized) {
      return;
    }

    try {
      this.dataPreferences = await preferences.getPreferences(context, 'novel_login_data');
      await this.loadPersistedData();
      this.initialized = true;
      logger.info(TAG, 'NovelLoginManager 初始化完成');
    } catch (error) {
      logger.error(TAG, `初始化失败: ${String(error)}`);
    }
  }

  /**
   * 加载持久化的数据
   */
  private async loadPersistedData(): Promise<void> {
    if (!this.dataPreferences) return;

    try {
      // 加载登录状态
      const statusJson = await this.dataPreferences.get(LOGIN_STATUS_STORAGE_KEY, '') as string;
      logger.debug(TAG, `加载持久化数据: statusJson长度=${statusJson ? statusJson.length : 0}`);
      if (statusJson) {
        const statusArray = JSON.parse(statusJson) as SourceLoginStatus[];
        statusArray.forEach((status: SourceLoginStatus) => {
          this.loginStatus.set(status.sourceId, status);
          if (status.cookies) {
            this.cookies.set(status.sourceId, status.cookies);
            logger.debug(TAG, `加载Cookie: sourceId=${status.sourceId}, cookieKeys=${Object.keys(status.cookies).join(',')}`);
          }
        });
        logger.info(TAG, `加载了 ${statusArray.length} 个书源的登录状态`);
      } else {
        logger.info(TAG, '没有持久化的登录状态数据');
      }
    } catch (error) {
      logger.error(TAG, `加载持久化数据失败: ${String(error)}`);
    }
  }

  /**
   * 保存持久化数据
   */
  private async savePersistedData(): Promise<void> {
    if (!this.dataPreferences) {
      logger.warn(TAG, 'dataPreferences 未初始化，无法保存数据');
      return;
    }

    try {
      // 保存登录状态和Cookie
      const statusArray: SourceLoginStatus[] = [];
      this.loginStatus.forEach((status, sourceId) => {
        const cookies = this.cookies.get(sourceId);
        const statusWithCookies: SourceLoginStatus = {
          sourceId: status.sourceId,
          isLoggedIn: status.isLoggedIn,
          lastLoginTime: status.lastLoginTime,
          cookies: cookies
        };
        statusArray.push(statusWithCookies);
      });

      await this.dataPreferences.put(LOGIN_STATUS_STORAGE_KEY, JSON.stringify(statusArray));
      await this.dataPreferences.flush();
      logger.debug(TAG, `保存了 ${statusArray.length} 个书源的登录状态`);
    } catch (error) {
      logger.error(TAG, `保存持久化数据失败: ${String(error)}`);
    }
  }

  /**
   * 检查书源是否需要登录
   */
  needsLogin(source: LegadoBookSource): boolean {
    return !!source.loginUrl;
  }

  /**
   * 检查书源是否已登录
   */
  isLoggedIn(sourceId: string): boolean {
    const status = this.loginStatus.get(sourceId);
    return status?.isLoggedIn ?? false;
  }

  /**
   * 获取登录UI配置
   */
  getLoginUi(source: LegadoBookSource): LoginUiItem[] {
    if (!source.loginUi) {
      // 默认登录UI
      return [
        { type: 'text', name: 'username', hint: '用户名' },
        { type: 'password', name: 'password', hint: '密码' },
        { type: 'button', name: 'login', hint: '登录' }
      ];
    }

    try {
      const parsed = JSON.parse(source.loginUi) as LegadoLoginUiItem[];
      return parsed.map((item): LoginUiItem => ({
        type: item.type as 'text' | 'password' | 'button',
        name: item.name,
        hint: item.hint
      }));
    } catch (e) {
      logger.warn(TAG, `解析loginUi失败: ${String(e)}`);
      return [];
    }
  }

  /**
   * 执行登录
   */
  async login(source: LegadoBookSource, formData: Record<string, string>): Promise<LoginResult> {
    if (!source.loginUrl) {
      return { success: false, message: '书源未配置登录URL' };
    }

    try {
      logger.info(TAG, `开始登录书源: ${source.bookSourceName}`);

      // 检查loginUrl是否是JS代码
      if (source.loginUrl.startsWith('@js:') || source.loginUrl.startsWith('<js>')) {
        return await this.executeJsLogin(source, formData);
      }

      // 普通URL登录
      return await this.executeUrlLogin(source, formData);
    } catch (error) {
      logger.error(TAG, `登录失败: ${String(error)}`);
      return { success: false, message: String(error) };
    }
  }

  /**
   * 执行JS登录
   */
  private async executeJsLogin(source: LegadoBookSource, formData: Record<string, string>): Promise<LoginResult> {
    const jsEngine = getLegadoJsEngine();
    
    // 提取JS代码
    let jsCode = source.loginUrl!;
    if (jsCode.startsWith('@js:')) {
      jsCode = jsCode.substring(4);
    } else if (jsCode.startsWith('<js>')) {
      const endIndex = jsCode.lastIndexOf('</js>');
      jsCode = jsCode.substring(4, endIndex > 0 ? endIndex : undefined);
    }

    // 执行JS
    const result = await jsEngine.execute(jsCode, {
      variables: formData
    });

    if (result.success) {
      // 解析结果
      try {
        const loginResult = JSON.parse(result.result) as Record<string, ESObject>;
        if (loginResult['success']) {
          this.setLoggedIn(source.bookSourceUrl, true, loginResult['cookies'] as Record<string, string>);
          return { 
            success: true, 
            message: '登录成功',
            cookies: loginResult['cookies'] as Record<string, string>
          };
        } else {
          return { 
            success: false, 
            message: loginResult['message'] as string || '登录失败' 
          };
        }
      } catch (e) {
        // 如果结果不是JSON，检查是否为空（表示成功）
        if (!result.result || result.result === 'true') {
          this.setLoggedIn(source.bookSourceUrl, true);
          return { success: true, message: '登录成功' };
        }
        return { success: false, message: result.result || '登录失败' };
      }
    } else {
      return { success: false, message: result.error || '登录失败' };
    }
  }

  /**
   * 执行URL登录
   */
  private async executeUrlLogin(source: LegadoBookSource, formData: Record<string, string>): Promise<LoginResult> {
    // TODO: 实现URL登录逻辑
    // 需要通过WebView加载登录页面并提交表单
    logger.warn(TAG, 'URL登录暂未完全实现，需要WebView支持');
    return { success: false, message: 'URL登录需要WebView支持' };
  }

  /**
   * 检查登录状态
   */
  async checkLoginStatus(source: LegadoBookSource): Promise<boolean> {
    if (!source.loginCheckJs) {
      return this.isLoggedIn(source.bookSourceUrl);
    }

    try {
      const jsEngine = getLegadoJsEngine();
      const result = await jsEngine.execute(source.loginCheckJs, {
        variables: this.getVariables(source.bookSourceUrl)
      });

      const isLoggedIn = result.success && (result.result === 'true' || result.result === '1');
      this.setLoggedIn(source.bookSourceUrl, isLoggedIn);
      return isLoggedIn;
    } catch (error) {
      logger.warn(TAG, `检查登录状态失败: ${String(error)}`);
      return false;
    }
  }

  /**
   * 设置登录状态
   */
  setLoggedIn(sourceId: string, isLoggedIn: boolean, cookies?: Record<string, string>): void {
    this.loginStatus.set(sourceId, {
      sourceId,
      isLoggedIn,
      lastLoginTime: isLoggedIn ? Date.now() : undefined,
      cookies
    });

    if (cookies) {
      this.cookies.set(sourceId, cookies);
    }

    logger.info(TAG, `书源 ${sourceId} 登录状态: ${isLoggedIn}`);
    
    // 持久化保存
    this.savePersistedData();
  }

  /**
   * 获取书源的Cookie
   */
  getCookies(sourceId: string): Record<string, string> {
    return this.cookies.get(sourceId) || {};
  }

  /**
   * 设置Cookie
   */
  setCookies(sourceId: string, cookies: Record<string, string>): void {
    logger.info(TAG, `setCookies: sourceId=${sourceId}, cookieKeys=${Object.keys(cookies).join(',')}`);
    const existing = this.cookies.get(sourceId) || {};
    const merged: Record<string, string> = {};
    // 复制现有的cookies
    const existingKeys = Object.keys(existing);
    for (let i = 0; i < existingKeys.length; i++) {
      merged[existingKeys[i]] = existing[existingKeys[i]];
    }
    // 复制新的cookies
    const newKeys = Object.keys(cookies);
    for (let i = 0; i < newKeys.length; i++) {
      merged[newKeys[i]] = cookies[newKeys[i]];
    }
    this.cookies.set(sourceId, merged);
    logger.info(TAG, `Cookie已保存: sourceId=${sourceId}, 总共${Object.keys(merged).length}个cookie`);
    
    // 持久化保存
    this.savePersistedData();
  }

  /**
   * 获取Cookie字符串
   */
  getCookieString(sourceId: string): string {
    // 调试：输出所有已保存的Cookie keys
    const allKeys: string[] = [];
    this.cookies.forEach((_, key) => allKeys.push(key));
    logger.debug(TAG, `getCookieString: 查找=${sourceId}, 已保存的keys=[${allKeys.join(', ')}], initialized=${this.initialized}`);
    
    const cookies = this.getCookies(sourceId);
    const keys = Object.keys(cookies);
    const parts: string[] = [];
    for (let i = 0; i < keys.length; i++) {
      parts.push(`${keys[i]}=${cookies[keys[i]]}`);
    }
    return parts.join('; ');
  }

  /**
   * 获取变量（用于JS执行）
   */
  private getVariables(sourceId: string): Record<string, string> {
    const cookies = this.getCookies(sourceId);
    const result: Record<string, string> = {};
    result['cookie'] = this.getCookieString(sourceId);
    // 复制cookies到result
    const keys = Object.keys(cookies);
    for (let i = 0; i < keys.length; i++) {
      result[keys[i]] = cookies[keys[i]];
    }
    return result;
  }

  /**
   * 登出
   */
  logout(sourceId: string): void {
    this.loginStatus.delete(sourceId);
    this.cookies.delete(sourceId);
    logger.info(TAG, `书源 ${sourceId} 已登出`);
  }

  /**
   * 清除所有登录状态
   */
  clearAll(): void {
    this.loginStatus.clear();
    this.cookies.clear();
    logger.info(TAG, '已清除所有登录状态');
  }
}

/**
 * 获取登录管理器实例
 */
export function getNovelLoginManager(): NovelLoginManager {
  return NovelLoginManager.getInstance();
}
