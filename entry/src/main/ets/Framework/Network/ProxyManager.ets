/**
 * 网络代理管理器
 * 管理APP内的HTTP/HTTPS代理配置
 */

import { logger } from '../../Utils/Logger';
import { SettingsManager } from '../Managers/SettingsManager';
import { http, connection } from '@kit.NetworkKit';

const TAG = 'ProxyManager';
const PROXY_SETTINGS_KEY = 'network_proxy_settings';

/**
 * 代理配置接口
 */
export interface ProxyConfig {
  enabled: boolean;
  httpEnabled: boolean;
  httpHost: string;
  httpPort: number;
  httpsEnabled: boolean;
  httpsHost: string;
  httpsPort: number;
}

/**
 * 默认代理配置
 */
export const DEFAULT_PROXY_CONFIG: ProxyConfig = {
  enabled: false,
  httpEnabled: true,
  httpHost: '',
  httpPort: 7890,
  httpsEnabled: false,
  httpsHost: '',
  httpsPort: 7890
};

/**
 * 代理管理器单例
 */
export class ProxyManager {
  private static instance: ProxyManager;
  private settingsManager: SettingsManager;
  private config: ProxyConfig = DEFAULT_PROXY_CONFIG;
  private initialized: boolean = false;

  private constructor() {
    this.settingsManager = SettingsManager.getInstance();
  }

  static getInstance(): ProxyManager {
    if (!ProxyManager.instance) {
      ProxyManager.instance = new ProxyManager();
    }
    return ProxyManager.instance;
  }

  /**
   * 初始化代理配置
   */
  async initialize(): Promise<void> {
    if (this.initialized) {
      return;
    }

    try {
      const savedConfig = this.settingsManager.getString(PROXY_SETTINGS_KEY, '');
      if (savedConfig) {
        const parsed = JSON.parse(savedConfig) as ProxyConfig;
        this.config = {
          enabled: parsed.enabled || false,
          httpEnabled: parsed.httpEnabled !== undefined ? parsed.httpEnabled : true,
          httpHost: parsed.httpHost || '',
          httpPort: parsed.httpPort || 7890,
          httpsEnabled: parsed.httpsEnabled || false,
          httpsHost: parsed.httpsHost || '',
          httpsPort: parsed.httpsPort || 7890
        };
        logger.info(TAG, `代理配置已加载: enabled=${this.config.enabled}`);
      }
      this.initialized = true;
      
      // 应用系统级代理配置
      this.applySystemProxy();
    } catch (error) {
      logger.error(TAG, `加载代理配置失败: ${error}`);
      this.config = DEFAULT_PROXY_CONFIG;
      this.initialized = true;
    }
  }

  /**
   * 获取当前代理配置
   */
  getConfig(): ProxyConfig {
    const result: ProxyConfig = {
      enabled: this.config.enabled,
      httpEnabled: this.config.httpEnabled,
      httpHost: this.config.httpHost,
      httpPort: this.config.httpPort,
      httpsEnabled: this.config.httpsEnabled,
      httpsHost: this.config.httpsHost,
      httpsPort: this.config.httpsPort
    };
    return result;
  }

  /**
   * 保存代理配置
   */
  async saveConfig(config: ProxyConfig): Promise<void> {
    try {
      this.config = {
        enabled: config.enabled,
        httpEnabled: config.httpEnabled,
        httpHost: config.httpHost,
        httpPort: config.httpPort,
        httpsEnabled: config.httpsEnabled,
        httpsHost: config.httpsHost,
        httpsPort: config.httpsPort
      };
      // 修复：使用await确保配置被持久化到数据库
      await this.settingsManager.setString(PROXY_SETTINGS_KEY, JSON.stringify(this.config));
      logger.info(TAG, `代理配置已保存: enabled=${config.enabled}, http=${config.httpHost}:${config.httpPort}`);
      
      // 应用系统级代理配置
      this.applySystemProxy();
    } catch (error) {
      logger.error(TAG, `保存代理配置失败: ${error}`);
      throw error as Error;
    }
  }
  
  /**
   * 应用系统级代理配置
   * 使用 connection.setAppHttpProxy 设置应用级代理
   */
  applySystemProxy(): void {
    try {
      if (this.config.enabled && this.config.httpEnabled && this.config.httpHost) {
        const httpProxy: connection.HttpProxy = {
          host: this.config.httpHost,
          port: this.config.httpPort,
          exclusionList: []
        };
        connection.setAppHttpProxy(httpProxy);
        logger.info(TAG, `系统代理已应用: ${this.config.httpHost}:${this.config.httpPort}`);
      } else {
        // 禁用代理时，设置空代理
        const emptyProxy: connection.HttpProxy = {
          host: '',
          port: 0,
          exclusionList: []
        };
        connection.setAppHttpProxy(emptyProxy);
        logger.info(TAG, '系统代理已禁用');
      }
    } catch (error) {
      logger.error(TAG, `应用系统代理失败: ${error}`);
    }
  }

  /**
   * 检查代理是否启用
   */
  isEnabled(): boolean {
    return this.config.enabled;
  }

  /**
   * 获取HTTP代理URL
   */
  getHttpProxyUrl(): string | undefined {
    if (!this.config.enabled || !this.config.httpEnabled || !this.config.httpHost) {
      return undefined;
    }
    return `http://${this.config.httpHost}:${this.config.httpPort}`;
  }

  /**
   * 获取HTTPS代理URL
   */
  getHttpsProxyUrl(): string | undefined {
    if (!this.config.enabled || !this.config.httpsEnabled || !this.config.httpsHost) {
      return undefined;
    }
    return `http://${this.config.httpsHost}:${this.config.httpsPort}`;
  }

  /**
   * 获取用于HTTP请求的代理配置
   * 返回格式适用于 @ohos.net.http 模块
   */
  getHttpRequestProxy(): string | undefined {
    if (!this.config.enabled) {
      return undefined;
    }
    
    // 优先使用HTTP代理
    if (this.config.httpEnabled && this.config.httpHost) {
      return `${this.config.httpHost}:${this.config.httpPort}`;
    }
    
    return undefined;
  }

  /**
   * 启用代理
   */
  async enable(): Promise<void> {
    this.config.enabled = true;
    await this.saveConfig(this.config);
  }

  /**
   * 禁用代理
   */
  async disable(): Promise<void> {
    this.config.enabled = false;
    await this.saveConfig(this.config);
  }

  /**
   * 切换代理状态
   */
  async toggle(): Promise<boolean> {
    this.config.enabled = !this.config.enabled;
    await this.saveConfig(this.config);
    return this.config.enabled;
  }
  
  /**
   * 测试代理连接
   * @param testUrl 测试URL
   * @param useHttps 是否使用HTTPS代理
   */
  async testProxy(testUrl: string, useHttps: boolean = false): Promise<ProxyTestResult> {
    const startTime = Date.now();
    
    try {
      logger.info(TAG, `开始测试代理: ${testUrl}, useHttps=${useHttps}`);
      
      const httpRequest = http.createHttp();
      const requestOptions: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        connectTimeout: 10000,
        readTimeout: 10000,
        header: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
        },
        usingProxy: true
      };
      
      const response = await httpRequest.request(testUrl, requestOptions);
      httpRequest.destroy();
      
      const responseTime = Date.now() - startTime;
      const success = response.responseCode >= 200 && response.responseCode < 400;
      
      logger.info(TAG, `代理测试完成: ${testUrl}, code=${response.responseCode}, time=${responseTime}ms`);
      
      return {
        success: success,
        url: testUrl,
        responseCode: response.responseCode,
        responseTime: responseTime
      };
    } catch (error) {
      const responseTime = Date.now() - startTime;
      let errorMsg = '未知错误';
      if (error instanceof Error) {
        errorMsg = error.message;
      } else if (typeof error === 'object' && error !== null) {
        const errObj = error as Record<string, Object>;
        errorMsg = errObj['message'] as string || errObj['code'] as string || JSON.stringify(error);
      } else {
        errorMsg = String(error);
      }
      logger.error(TAG, `代理测试失败: ${testUrl}, error=${errorMsg}`);
      
      return {
        success: false,
        url: testUrl,
        responseTime: responseTime,
        error: errorMsg
      };
    }
  }
  
  /**
   * 批量测试代理
   */
  async testProxyBatch(): Promise<ProxyTestResult[]> {
    const testUrls = [
      'https://www.google.com',
      'https://x.com',
      'https://www.youtube.com',
      'https://github.com'
    ];
    
    const results: ProxyTestResult[] = [];
    
    for (const url of testUrls) {
      const result = await this.testProxy(url, url.startsWith('https'));
      results.push(result);
    }
    
    return results;
  }
}

/**
 * 代理测试结果
 */
export interface ProxyTestResult {
  success: boolean;
  url: string;
  responseCode?: number;
  responseTime?: number;
  error?: string;
}

/**
 * 获取代理管理器实例
 */
export function getProxyManager(): ProxyManager {
  return ProxyManager.getInstance();
}
