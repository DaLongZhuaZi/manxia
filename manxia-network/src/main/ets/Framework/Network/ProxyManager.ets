import { ProxyProtocol, ProxyConfig, ProxyTestResult, IProxyManagerFacade, ProxyManagerHolder } from 'manxia_core/src/main/ets/Framework/Contracts/ProxyManagerFacade';
import { SafeUtils } from 'manxia_core/src/main/ets/Utils/SafeUtils';
/**
 * 网络代理管理器
 * 管理APP内的HTTP/HTTPS/SOCKS5代理配置
 */

import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { SettingsManager } from 'manxia_core/src/main/ets/Framework/Managers/SettingsManager';
import { http, connection } from '@kit.NetworkKit';
import { webview } from '@kit.ArkWeb';
import { LocalProxyBridge, LocalProxyBridgeConfig, LocalProxyBridgeUpstreamProtocol } from 'manxia_network/src/main/ets/Framework/Network/LocalProxyBridge';

const TAG = 'ProxyManager';
const PROXY_SETTINGS_KEY = 'network_proxy_settings';

export { ProxyProtocol, ProxyConfig, ProxyTestResult };


/**
 * 代理配置接口
 */


/**
 * 默认代理配置
 */
export const DEFAULT_PROXY_CONFIG: ProxyConfig = {
  enabled: false,
  protocol: ProxyProtocol.HTTP,
  sharedAuthEnabled: false,
  sharedUsername: '',
  sharedPassword: '',
  httpEnabled: true,
  httpHost: '',
  httpPort: 7890,
  httpAuthEnabled: false,
  httpUsername: '',
  httpPassword: '',
  httpsEnabled: false,
  httpsHost: '',
  httpsPort: 7890,
  httpsAuthEnabled: false,
  httpsUsername: '',
  httpsPassword: '',
  socks5Host: '',
  socks5Port: 1080,
  socks5AuthEnabled: false,
  socks5Username: '',
  socks5Password: ''
};

/**
 * 代理管理器单例
 */
export class ProxyManager implements IProxyManagerFacade {
  private static instance: ProxyManager;
  private settingsManager: SettingsManager;
  private config: ProxyConfig = this.copyProxyConfig(DEFAULT_PROXY_CONFIG);
  private initialized: boolean = false;
  private localBridge: LocalProxyBridge = new LocalProxyBridge();

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
        const parsed = SafeUtils.parseObj(savedConfig) as ProxyConfig;
        this.config = this.normalizeConfig(parsed);
        logger.info(TAG, `代理配置已加载: enabled=${this.config.enabled}, protocol=${this.config.protocol}`);
      }
      this.initialized = true;
      await this.applySystemProxy();
    } catch (error) {
      logger.error(TAG, `加载代理配置失败: ${String(error)}`);
      this.config = this.copyProxyConfig(DEFAULT_PROXY_CONFIG);
      this.initialized = true;
      await this.clearProxy();
    }
  
  ProxyManagerHolder.register(this);
}

  /**
   * 获取当前代理配置
   */
  getConfig(): ProxyConfig {
    return this.copyProxyConfig(this.config);
  }

  /**
   * 保存代理配置
   */
  async saveConfig(config: ProxyConfig): Promise<void> {
    try {
      this.config = this.normalizeConfig(config);
      await this.settingsManager.setString(PROXY_SETTINGS_KEY, JSON.stringify(this.config));
      logger.info(
        TAG,
        `代理配置已保存: enabled=${this.config.enabled}, protocol=${this.config.protocol}, ` +
          `http=${this.config.httpHost}:${this.config.httpPort}, https=${this.config.httpsHost}:${this.config.httpsPort}, ` +
          `socks5=${this.config.socks5Host}:${this.config.socks5Port}, auth=${this.hasActiveAuth()}`
      );
      await this.applySystemProxy();
    } catch (error) {
      logger.error(TAG, `保存代理配置失败: ${String(error)}`);
      throw error as Error;
    }
  }

  /**
   * 应用系统级代理配置
   */
  async applySystemProxy(): Promise<void> {
    try {
      if (!this.config.enabled) {
        await this.clearProxy();
        return;
      }

      if (this.config.protocol === ProxyProtocol.SOCKS5) {
        await this.applySocks5Proxy();
        return;
      }

      await this.localBridge.stop();
      const selected = this.getSelectedHttpProxy();
      if (selected === null) {
        await this.clearProxy();
        logger.warn(TAG, 'HTTP代理已启用但缺少有效地址，已清空系统代理');
        return;
      }
      if (this.hasHttpProxyAuth(selected)) {
        const bridgePort = await this.ensureHttpProxyBridge(selected);
        const localProxy: connection.HttpProxy = {
          host: '127.0.0.1',
          port: bridgePort,
          exclusionList: []
        };
        connection.setAppHttpProxy(localProxy);
        this.applyArkWebProxyRule(`http://127.0.0.1:${bridgePort}`);
        logger.info(TAG, `系统HTTP认证代理已通过本地桥应用: 127.0.0.1:${bridgePort}, upstream=${selected.host}:${selected.port}`);
        return;
      }
      connection.setAppHttpProxy(selected);
      this.applyArkWebHttpProxy(selected);
      logger.info(TAG, `系统HTTP代理已应用: ${selected.host}:${selected.port}, auth=${this.hasHttpProxyAuth(selected)}`);
    } catch (error) {
      logger.error(TAG, `应用系统代理失败: ${String(error)}`);
    }
  }

  /**
   * 将当前代理配置应用到单次HTTP请求选项。
   */
  async applyToHttpOptions(options: http.HttpRequestOptions, url: string): Promise<void> {
    if (!this.config.enabled) {
      return;
    }
    if (this.config.protocol === ProxyProtocol.SOCKS5) {
      await this.ensureSocks5Bridge();
      const bridgePort = this.localBridge.getPort();
      if (bridgePort > 0) {
        const localProxy: connection.HttpProxy = {
          host: '127.0.0.1',
          port: bridgePort,
          exclusionList: []
        };
        options.usingProxy = localProxy;
      }
      return;
    }

    const proxy = this.getHttpProxyForUrl(url);
    if (proxy !== null) {
      if (this.hasHttpProxyAuth(proxy)) {
        const bridgePort = await this.ensureHttpProxyBridge(proxy);
        const localProxy: connection.HttpProxy = {
          host: '127.0.0.1',
          port: bridgePort,
          exclusionList: []
        };
        options.usingProxy = localProxy;
        return;
      }
      options.usingProxy = proxy;
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
    if (!this.config.enabled) {
      return undefined;
    }
    if (this.config.protocol === ProxyProtocol.SOCKS5) {
      const bridgePort = this.localBridge.getPort();
      if (bridgePort > 0) {
        return `http://127.0.0.1:${bridgePort}`;
      }
      return undefined;
    }
    if (!this.config.httpEnabled || !this.config.httpHost) {
      return undefined;
    }
    return `http://${this.config.httpHost}:${this.config.httpPort}`;
  }

  /**
   * 获取HTTPS代理URL
   */
  getHttpsProxyUrl(): string | undefined {
    if (!this.config.enabled) {
      return undefined;
    }
    if (this.config.protocol === ProxyProtocol.SOCKS5) {
      const bridgePort = this.localBridge.getPort();
      if (bridgePort > 0) {
        return `http://127.0.0.1:${bridgePort}`;
      }
      return undefined;
    }
    if (!this.config.httpsEnabled || !this.config.httpsHost) {
      return undefined;
    }
    return `http://${this.config.httpsHost}:${this.config.httpsPort}`;
  }

  /**
   * 获取用于HTTP请求的代理配置
   */
  getHttpRequestProxy(): string | undefined {
    if (!this.config.enabled) {
      return undefined;
    }
    if (this.config.protocol === ProxyProtocol.SOCKS5) {
      const bridgePort = this.localBridge.getPort();
      if (bridgePort > 0) {
        return `127.0.0.1:${bridgePort}`;
      }
      return undefined;
    }
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
   */
  async testProxy(testUrl: string): Promise<ProxyTestResult> {
    const startTime = Date.now();

    try {
      logger.info(TAG, `开始测试代理: ${testUrl}, protocol=${this.config.protocol}`);

      await this.applySystemProxy();
      const httpRequest = http.createHttp();
      const requestOptions: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        connectTimeout: 10000,
        readTimeout: 10000,
        header: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
        }
      };
      await this.applyToHttpOptions(requestOptions, testUrl);

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
      const errorMsg = this.stringifyError(error);
      logger.error(TAG, `代理测试失败: ${testUrl}, error=${errorMsg}`);

      return {
        success: false,
        url: testUrl,
        responseTime: responseTime,
        error: this.classifyProxyError(errorMsg)
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
      const result = await this.testProxy(url);
      results.push(result);
    }

    return results;
  }

  /**
   * 测试单个URL
   * @param url 要测试的URL
   */
  async testSingleUrl(url: string): Promise<ProxyTestResult> {
    return await this.testProxy(url);
  }

  private async applySocks5Proxy(): Promise<void> {
    const bridgePort = await this.ensureSocks5Bridge();
    const localProxy: connection.HttpProxy = {
      host: '127.0.0.1',
      port: bridgePort,
      exclusionList: []
    };
    connection.setAppHttpProxy(localProxy);
    this.applyArkWebProxyRule(`http://127.0.0.1:${bridgePort}`);
    logger.info(TAG, `SOCKS5代理已通过本地桥应用: 127.0.0.1:${bridgePort}, upstream=${this.config.socks5Host}:${this.config.socks5Port}, auth=${this.config.sharedAuthEnabled}`);
  }

  private async ensureSocks5Bridge(): Promise<number> {
    const bridgeConfig: LocalProxyBridgeConfig = {
      upstreamProtocol: LocalProxyBridgeUpstreamProtocol.SOCKS5,
      upstreamHost: this.config.socks5Host,
      upstreamPort: this.config.socks5Port,
      upstreamAuthEnabled: this.config.sharedAuthEnabled,
      upstreamUsername: this.config.sharedUsername,
      upstreamPassword: this.config.sharedPassword
    };
    if (!this.isValidHostPort(bridgeConfig.upstreamHost, bridgeConfig.upstreamPort)) {
      throw new Error('SOCKS5代理地址或端口无效');
    }
    return await this.localBridge.start(bridgeConfig);
  }

  private async ensureHttpProxyBridge(proxy: connection.HttpProxy): Promise<number> {
    const bridgeConfig: LocalProxyBridgeConfig = {
      upstreamProtocol: LocalProxyBridgeUpstreamProtocol.HTTP,
      upstreamHost: proxy.host,
      upstreamPort: proxy.port,
      upstreamAuthEnabled: this.hasHttpProxyAuth(proxy),
      upstreamUsername: proxy.username !== undefined ? proxy.username : '',
      upstreamPassword: proxy.password !== undefined ? proxy.password : ''
    };
    if (!this.isValidHostPort(bridgeConfig.upstreamHost, bridgeConfig.upstreamPort)) {
      throw new Error('HTTP代理地址或端口无效');
    }
    return await this.localBridge.start(bridgeConfig);
  }

  private async clearProxy(): Promise<void> {
    await this.localBridge.stop();
    const emptyProxy: connection.HttpProxy = {
      host: '',
      port: 0,
      exclusionList: []
    };
    connection.setAppHttpProxy(emptyProxy);
    this.removeArkWebProxy();
    logger.info(TAG, '系统代理已禁用');
  }

  private getSelectedHttpProxy(): connection.HttpProxy | null {
    if (this.config.httpEnabled && this.config.httpHost.length > 0) {
      return this.buildHttpProxy(
        this.config.httpHost,
        this.config.httpPort,
        this.config.sharedAuthEnabled,
        this.config.sharedUsername,
        this.config.sharedPassword
      );
    }
    if (this.config.httpsEnabled && this.config.httpsHost.length > 0) {
      return this.buildHttpProxy(
        this.config.httpsHost,
        this.config.httpsPort,
        this.config.sharedAuthEnabled,
        this.config.sharedUsername,
        this.config.sharedPassword
      );
    }
    return null;
  }

  private getHttpProxyForUrl(url: string): connection.HttpProxy | null {
    const httpsTarget = url.startsWith('https://');
    if (httpsTarget && this.config.httpsEnabled && this.config.httpsHost.length > 0) {
      return this.buildHttpProxy(
        this.config.httpsHost,
        this.config.httpsPort,
        this.config.sharedAuthEnabled,
        this.config.sharedUsername,
        this.config.sharedPassword
      );
    }
    if (this.config.httpEnabled && this.config.httpHost.length > 0) {
      return this.buildHttpProxy(
        this.config.httpHost,
        this.config.httpPort,
        this.config.sharedAuthEnabled,
        this.config.sharedUsername,
        this.config.sharedPassword
      );
    }
    return this.getSelectedHttpProxy();
  }

  private buildHttpProxy(
    host: string,
    port: number,
    authEnabled: boolean,
    username: string,
    password: string
  ): connection.HttpProxy {
    const proxy: connection.HttpProxy = {
      host: host,
      port: port,
      exclusionList: []
    };
    if (authEnabled) {
      proxy.username = username;
      proxy.password = password;
    }
    return proxy;
  }

  private applyArkWebHttpProxy(proxy: connection.HttpProxy): void {
    this.applyArkWebProxyRule(`http://${proxy.host}:${proxy.port}`);
  }

  private applyArkWebProxyRule(proxyRule: string): void {
    try {
      const proxyConfig = new webview.ProxyConfig();
      proxyConfig.insertProxyRule(proxyRule, webview.ProxySchemeFilter.MATCH_ALL_SCHEMES);
      webview.ProxyController.applyProxyOverride(proxyConfig, () => {
        logger.info(TAG, `ArkWeb代理已应用: ${proxyRule}`);
      });
    } catch (error) {
      logger.warn(TAG, `应用ArkWeb代理失败: ${String(error)}`);
    }
  }

  private removeArkWebProxy(): void {
    try {
      webview.ProxyController.removeProxyOverride(() => {
        logger.info(TAG, 'ArkWeb代理已移除');
      });
    } catch (error) {
      logger.debug(TAG, `移除ArkWeb代理失败: ${String(error)}`);
    }
  }

  private normalizeConfig(config: ProxyConfig): ProxyConfig {
    const protocol = config.protocol === ProxyProtocol.SOCKS5 ? ProxyProtocol.SOCKS5 : ProxyProtocol.HTTP;
    const legacyAuthEnabled = config.httpAuthEnabled === true ||
      config.httpsAuthEnabled === true ||
      config.socks5AuthEnabled === true;
    const sharedAuthEnabled = config.sharedAuthEnabled === true ||
      (config.sharedAuthEnabled !== false && legacyAuthEnabled);
    let sharedUsername = this.normalizeText(config.sharedUsername);
    if (sharedUsername.length <= 0) {
      sharedUsername = this.normalizeText(config.httpUsername);
    }
    if (sharedUsername.length <= 0) {
      sharedUsername = this.normalizeText(config.httpsUsername);
    }
    if (sharedUsername.length <= 0) {
      sharedUsername = this.normalizeText(config.socks5Username);
    }
    let sharedPassword = this.normalizeText(config.sharedPassword);
    if (sharedPassword.length <= 0) {
      sharedPassword = this.normalizeText(config.httpPassword);
    }
    if (sharedPassword.length <= 0) {
      sharedPassword = this.normalizeText(config.httpsPassword);
    }
    if (sharedPassword.length <= 0) {
      sharedPassword = this.normalizeText(config.socks5Password);
    }
    const normalized: ProxyConfig = {
      enabled: config.enabled === true,
      protocol: protocol,
      sharedAuthEnabled: sharedAuthEnabled,
      sharedUsername: sharedUsername,
      sharedPassword: sharedPassword,
      httpEnabled: config.httpEnabled !== undefined ? config.httpEnabled : true,
      httpHost: this.normalizeText(config.httpHost),
      httpPort: this.normalizePort(config.httpPort, 7890),
      httpAuthEnabled: sharedAuthEnabled,
      httpUsername: sharedUsername,
      httpPassword: sharedPassword,
      httpsEnabled: config.httpsEnabled === true,
      httpsHost: this.normalizeText(config.httpsHost),
      httpsPort: this.normalizePort(config.httpsPort, 7890),
      httpsAuthEnabled: sharedAuthEnabled,
      httpsUsername: sharedUsername,
      httpsPassword: sharedPassword,
      socks5Host: this.normalizeText(config.socks5Host),
      socks5Port: this.normalizePort(config.socks5Port, 1080),
      socks5AuthEnabled: sharedAuthEnabled,
      socks5Username: sharedUsername,
      socks5Password: sharedPassword
    };
    return normalized;
  }

  private copyProxyConfig(source: ProxyConfig): ProxyConfig {
    const copied: ProxyConfig = {
      enabled: source.enabled,
      protocol: source.protocol,
      sharedAuthEnabled: source.sharedAuthEnabled,
      sharedUsername: source.sharedUsername,
      sharedPassword: source.sharedPassword,
      httpEnabled: source.httpEnabled,
      httpHost: source.httpHost,
      httpPort: source.httpPort,
      httpAuthEnabled: source.httpAuthEnabled,
      httpUsername: source.httpUsername,
      httpPassword: source.httpPassword,
      httpsEnabled: source.httpsEnabled,
      httpsHost: source.httpsHost,
      httpsPort: source.httpsPort,
      httpsAuthEnabled: source.httpsAuthEnabled,
      httpsUsername: source.httpsUsername,
      httpsPassword: source.httpsPassword,
      socks5Host: source.socks5Host,
      socks5Port: source.socks5Port,
      socks5AuthEnabled: source.socks5AuthEnabled,
      socks5Username: source.socks5Username,
      socks5Password: source.socks5Password
    };
    return copied;
  }

  private normalizeText(value: string | undefined | null): string {
    return value !== undefined && value !== null ? String(value).trim() : '';
  }

  private normalizePort(value: number | undefined | null, fallback: number): number {
    const port = Number(value);
    if (Number.isFinite(port) && port > 0 && port <= 65535) {
      return Math.floor(port);
    }
    return fallback;
  }

  private isValidHostPort(host: string, port: number): boolean {
    return host.trim().length > 0 && port > 0 && port <= 65535;
  }

  private hasActiveAuth(): boolean {
    return this.config.sharedAuthEnabled;
  }

  private hasHttpProxyAuth(proxy: connection.HttpProxy): boolean {
    return proxy.username !== undefined && proxy.username.length > 0;
  }

  private stringifyError(error: Error | Object | string | null | undefined): string {
    if (error instanceof Error) {
      return error.message;
    }
    return String(error);
  }

  private classifyProxyError(errorMsg: string): string {
    const lower = errorMsg.toLowerCase();
    if (lower.includes('407') || lower.includes('auth') || lower.includes('password') || lower.includes('2301207')) {
      return `代理认证失败: ${errorMsg}`;
    }
    if (lower.includes('proxy') || lower.includes('socks') || lower.includes('2301206') || lower.includes('2301209')) {
      return `代理连接失败: ${errorMsg}`;
    }
    return errorMsg;
  }
}

/**
 * 代理测试结果
 */


/**
 * 获取代理管理器实例
 */
export function getProxyManager(): ProxyManager {
  return ProxyManager.getInstance();
}
