// 文件路径: entry/src/main/ets/Framework/Authentication/LoginManager.ets
/**
 * 登录管理器 - 支持WebView登录和表单登录
 */

import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { webview } from '@kit.ArkWeb';
import CookieManager from '../Managers/CookieManager';
import http from '@ohos.net.http';

const TAG = 'LoginManager';

/**
 * 登录类型
 */
export type LoginType = 'webview' | 'form' | 'oauth';

/**
 * WebView登录配置
 */
export interface WebViewLoginConfig {
  type: 'webview';
  loginUrl: string;
  successUrlPattern?: string;  // 登录成功后的URL模式
  cookieNames?: string[];      // 需要捕获的Cookie名称
  timeout?: number;            // 超时时间（毫秒）
}

/**
 * 表单登录配置
 */
export interface FormLoginConfig {
  type: 'form';
  loginUrl: string;
  method: 'GET' | 'POST';
  usernameField: string;
  passwordField: string;
  extraFields?: Record<string, string>;  // 额外字段（如CSRF token）
  headers?: Record<string, string>;
  successIndicator?: string;   // 成功标识（响应中包含的字符串）
  cookieNames?: string[];
}

/**
 * OAuth登录配置
 */
export interface OAuthLoginConfig {
  type: 'oauth';
  authUrl: string;
  tokenUrl: string;
  clientId: string;
  redirectUri: string;
  scope?: string;
}

/**
 * 登录配置联合类型
 */
export type LoginConfig = WebViewLoginConfig | FormLoginConfig | OAuthLoginConfig;

/**
 * 登录结果
 */
export interface LoginResult {
  success: boolean;
  message: string;
  cookies?: Record<string, string>;
  token?: string;
}

/**
 * 登录管理器
 */
export class LoginManager {
  private static instance: LoginManager | null = null;
  private cookieManager: CookieManager;

  private constructor() {
    this.cookieManager = CookieManager.getInstance();
  }

  static getInstance(): LoginManager {
    if (!LoginManager.instance) {
      LoginManager.instance = new LoginManager();
    }
    return LoginManager.instance;
  }

  /**
   * 执行登录
   */
  async login(
    sourceId: number,
    config: LoginConfig,
    credentials?: { username: string; password: string }
  ): Promise<LoginResult> {
    logger.info(TAG, `开始登录: sourceId=${sourceId}, type=${config.type}`);

    try {
      switch (config.type) {
        case 'webview':
          return await this.loginWithWebView(sourceId, config);
        case 'form':
          if (!credentials) {
            return { success: false, message: '表单登录需要提供用户名和密码' };
          }
          return await this.loginWithForm(sourceId, config, credentials);
        case 'oauth':
          return await this.loginWithOAuth(sourceId, config);
        default:
          return { success: false, message: '不支持的登录类型' };
      }
    } catch (error) {
      logger.error(TAG, `登录失败: ${String(error)}`);
      return { success: false, message: String(error) };
    }
  }

  /**
   * WebView登录
   */
  private async loginWithWebView(
    sourceId: number,
    config: WebViewLoginConfig
  ): Promise<LoginResult> {
    logger.info(TAG, `WebView登录: ${config.loginUrl}`);

    // 这个方法需要在UI组件中调用，因为需要显示WebView
    // 这里返回配置，让调用者打开WebView
    return {
      success: false,
      message: 'WebView登录需要在UI中完成，请使用openLoginWebView方法'
    };
  }

  /**
   * 表单登录
   */
  private async loginWithForm(
    sourceId: number,
    config: FormLoginConfig,
    credentials: { username: string; password: string }
  ): Promise<LoginResult> {
    logger.info(TAG, `表单登录: ${config.loginUrl}`);

    try {
      const httpRequest = http.createHttp();

      // 构建请求体
      const formData: Record<string, string> = {
        [config.usernameField]: credentials.username,
        [config.passwordField]: credentials.password
      };

      // 添加额外字段
      if (config.extraFields) {
        Object.assign(formData, config.extraFields);
      }

      // 构建请求
      // 转换method类型
      const httpMethod = config.method === 'GET' ? http.RequestMethod.GET : http.RequestMethod.POST;
      
      const options: http.HttpRequestOptions = {
        method: httpMethod,
        header: config.headers || {
          'Content-Type': 'application/x-www-form-urlencoded'
        },
        extraData: this.buildFormData(formData),
        expectDataType: http.HttpDataType.STRING
      };

      logger.debug(TAG, `发送登录请求: ${config.loginUrl}`);
      const response = await httpRequest.request(config.loginUrl, options);

      // 检查响应
      if (response.responseCode !== 200) {
        httpRequest.destroy();
        return {
          success: false,
          message: `登录失败: HTTP ${response.responseCode}`
        };
      }

      // 提取Cookie
      const cookies = this.extractCookiesFromResponse(response);
      logger.debug(TAG, `提取到${Object.keys(cookies).length}个Cookie`);

      // 保存Cookie
      if (Object.keys(cookies).length > 0) {
        await this.saveCookiesToDatabase(sourceId, cookies);
      }

      // 检查成功标识
      let success = true;
      if (config.successIndicator) {
        const body = String(response.result);
        success = body.includes(config.successIndicator);
      }

      httpRequest.destroy();

      return {
        success: success,
        message: success ? '登录成功' : '登录失败：未找到成功标识',
        cookies: cookies
      };
    } catch (error) {
      logger.error(TAG, `表单登录异常: ${String(error)}`);
      return {
        success: false,
        message: `登录异常: ${String(error)}`
      };
    }
  }

  /**
   * OAuth登录
   */
  private async loginWithOAuth(
    sourceId: number,
    config: OAuthLoginConfig
  ): Promise<LoginResult> {
    logger.info(TAG, `OAuth登录: ${config.authUrl}`);

    // OAuth登录需要打开浏览器，这里返回配置
    return {
      success: false,
      message: 'OAuth登录需要在浏览器中完成'
    };
  }

  /**
   * 构建表单数据
   */
  private buildFormData(data: Record<string, string>): string {
    const parts: string[] = [];
    const keys = Object.keys(data);
    
    for (const key of keys) {
      const value = data[key];
      parts.push(`${encodeURIComponent(key)}=${encodeURIComponent(value)}`);
    }
    
    return parts.join('&');
  }

  /**
   * 从响应中提取Cookie
   */
  private extractCookiesFromResponse(response: http.HttpResponse): Record<string, string> {
    const cookies: Record<string, string> = {};
    
    try {
      const headers = response.header as Record<string, Object>;
      const setCookieHeader = headers['set-cookie'] || headers['Set-Cookie'];
      
      if (!setCookieHeader) {
        return cookies;
      }

      // 处理单个或多个Set-Cookie
      const cookieStrings: string[] = Array.isArray(setCookieHeader) 
        ? setCookieHeader.map(c => String(c))
        : [String(setCookieHeader)];

      for (const cookieStr of cookieStrings) {
        const parts = cookieStr.split(';');
        if (parts.length === 0) continue;

        const nameValue = parts[0].trim();
        const eqIndex = nameValue.indexOf('=');
        if (eqIndex === -1) continue;

        const name = nameValue.substring(0, eqIndex).trim();
        const value = nameValue.substring(eqIndex + 1).trim();
        
        if (name.length > 0) {
          cookies[name] = value;
        }
      }
    } catch (error) {
      logger.error(TAG, `提取Cookie失败: ${String(error)}`);
    }

    return cookies;
  }

  /**
   * 从WebView提取Cookie
   */
  async extractCookiesFromWebView(
    controller: webview.WebviewController,
    sourceId: number,
    domain: string,
    cookieNames?: string[]
  ): Promise<Record<string, string>> {
    const cookies: Record<string, string> = {};

    try {
      // 使用JavaScript获取Cookie
      const jsCode = 'document.cookie';
      const allCookies = await controller.runJavaScript(jsCode) as string;
      logger.debug(TAG, `从WebView获取Cookie: ${allCookies}`);

      // 解析Cookie字符串
      const cookiePairs = allCookies.split(';');
      for (const pair of cookiePairs) {
        const trimmed = pair.trim();
        const eqIndex = trimmed.indexOf('=');
        if (eqIndex === -1) continue;

        const name = trimmed.substring(0, eqIndex);
        const value = trimmed.substring(eqIndex + 1);

        // 如果指定了Cookie名称，只提取指定的
        if (!cookieNames || cookieNames.includes(name)) {
          cookies[name] = value;
        }
      }

      // 保存到数据库
      if (Object.keys(cookies).length > 0) {
        await this.saveCookiesToDatabase(sourceId, cookies);
        logger.info(TAG, `保存了${Object.keys(cookies).length}个Cookie`);
      }
    } catch (error) {
      logger.error(TAG, `从WebView提取Cookie失败: ${String(error)}`);
    }

    return cookies;
  }

  /**
   * 检查登录状态
   */
  async checkLoginStatus(sourceId: number, checkUrl: string): Promise<boolean> {
    try {
      const httpRequest = http.createHttp();

      // 获取已保存的Cookie
      const cookieStr = await this.cookieManager.getCookieString(sourceId);
      
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: {
          'Cookie': cookieStr
        },
        expectDataType: http.HttpDataType.STRING
      };

      const response = await httpRequest.request(checkUrl, options);
      httpRequest.destroy();

      // 检查是否返回401或需要登录
      return response.responseCode === 200;
    } catch (error) {
      logger.error(TAG, `检查登录状态失败: ${String(error)}`);
      return false;
    }
  }

  /**
   * 清除登录状态
   */
  async logout(sourceId: number): Promise<void> {
    await this.cookieManager.clearCookies(sourceId);
    logger.info(TAG, `已清除登录状态: sourceId=${sourceId}`);
  }

  /**
   * 保存Cookie到数据库
   */
  private async saveCookiesToDatabase(sourceId: number, cookies: Record<string, string>): Promise<void> {
    try {
      // 转换为CookieEntry数组
      const entries: Array<{ name: string; value: string; expires: number }> = [];
      const keys = Object.keys(cookies);
      const defaultExpires = Date.now() + (7 * 24 * 60 * 60 * 1000); // 7天后过期
      
      for (const key of keys) {
        entries.push({
          name: key,
          value: cookies[key],
          expires: defaultExpires
        });
      }

      // 序列化并保存
      const jsonStr = JSON.stringify(entries);
      await this.cookieManager['dataManager'].updateComicSourceCookies(sourceId, jsonStr);
      logger.debug(TAG, `保存Cookie到数据库: sourceId=${sourceId}, count=${entries.length}`);
    } catch (error) {
      logger.error(TAG, `保存Cookie到数据库失败: ${String(error)}`);
      throw error;
    }
  }
}

export default LoginManager;
