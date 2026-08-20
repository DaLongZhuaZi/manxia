/** 网络代理契约（Stage 6 契约化推广）—— 公共类型与接口，entry ProxyManager 实现并自注册。*/

export enum ProxyProtocol {
  HTTP = 'HTTP',
  SOCKS5 = 'SOCKS5'
}

export interface ProxyConfig {
  enabled: boolean;
  protocol: ProxyProtocol;
  sharedAuthEnabled: boolean;
  sharedUsername: string;
  sharedPassword: string;
  httpEnabled: boolean;
  httpHost: string;
  httpPort: number;
  httpAuthEnabled: boolean;
  httpUsername: string;
  httpPassword: string;
  httpsEnabled: boolean;
  httpsHost: string;
  httpsPort: number;
  httpsAuthEnabled: boolean;
  httpsUsername: string;
  httpsPassword: string;
  socks5Host: string;
  socks5Port: number;
  socks5AuthEnabled: boolean;
  socks5Username: string;
  socks5Password: string;
}

export interface ProxyTestResult {
  success: boolean;
  url: string;
  responseCode?: number;
  responseTime?: number;
  error?: string;
}

export interface IProxyManagerFacade {
  getConfig(): ProxyConfig;
  isEnabled(): boolean;
  getHttpProxyUrl(): string | undefined;
  getHttpsProxyUrl(): string | undefined;
  saveConfig(config: ProxyConfig): Promise<void>;
  applySystemProxy(): Promise<void>;
  initialize(): Promise<void>;
  testSingleUrl(url: string): Promise<ProxyTestResult>;
}

export class ProxyManagerHolder {
  private static impl: IProxyManagerFacade | null = null;
  static register(facade: IProxyManagerFacade): void { ProxyManagerHolder.impl = facade; }
  static get(): IProxyManagerFacade {
    if (!ProxyManagerHolder.impl) { throw new Error('ProxyManager not registered'); }
    return ProxyManagerHolder.impl;
  }
}
