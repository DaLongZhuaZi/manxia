// 文件路径: entry/src/main/ets/Framework/Utils/DynamicUrlResolver.ets
/**
 * 动态URL解析器
 * 支持URL模板变量替换和动态域名切换
 */

import { logger } from 'manxia_core/src/main/ets/Utils/Logger';

const TAG = 'DynamicUrlResolver';

/**
 * URL解析配置
 */
export interface UrlResolverConfig {
  baseUrl: string;
  alternativeUrls?: Record<string, string>;
  variables?: Record<string, string>;
}

/**
 * 动态URL解析器（单例）
 */
export class DynamicUrlResolver {
  private static instance: DynamicUrlResolver | null = null;

  private constructor() {}

  static getInstance(): DynamicUrlResolver {
    if (!DynamicUrlResolver.instance) {
      DynamicUrlResolver.instance = new DynamicUrlResolver();
    }
    return DynamicUrlResolver.instance;
  }

  /**
   * 解析URL模板
   * 支持变量替换：{{baseUrl}}, {{apiDomain}}, {{mangaId}}等
   */
  resolveUrl(template: string, config: UrlResolverConfig): string {
    if (!template) {
      return '';
    }

    let url = template;

    // 1. 解析域名选择
    const actualBaseUrl = this.resolveBaseUrl(config);
    url = url.replace(/\{\{baseUrl\}\}/g, actualBaseUrl);

    // 2. 替换其他变量
    if (config.variables) {
      Object.keys(config.variables).forEach(key => {
        const pattern = new RegExp(`\\{\\{${key}\\}\\}`, 'g');
        const value = config.variables![key];
        url = url.replace(pattern, value);
      });
    }

    logger.debug(TAG, `URL解析: ${template} -> ${url}`);
    return url;
  }

  /**
   * 批量解析URL
   */
  resolveUrls(templates: string[], config: UrlResolverConfig): string[] {
    return templates.map(template => this.resolveUrl(template, config));
  }

  /**
   * 解析对象中的所有URL字段
   */
  resolveUrlsInObject(obj: Record<string, any>, config: UrlResolverConfig): Record<string, any> {
    const result: Record<string, any> = {};
    
    Object.keys(obj).forEach(key => {
      const value = obj[key];
      
      if (typeof value === 'string') {
        // 如果是字符串且包含{{}}，则解析
        if (value.includes('{{') && value.includes('}}')) {
          result[key] = this.resolveUrl(value, config);
        } else {
          result[key] = value;
        }
      } else if (typeof value === 'object' && value !== null) {
        // 递归处理嵌套对象
        result[key] = this.resolveUrlsInObject(value, config);
      } else {
        result[key] = value;
      }
    });
    
    return result;
  }

  /**
   * 解析baseUrl（支持动态域名切换）
   */
  private resolveBaseUrl(config: UrlResolverConfig): string {
    // 检查是否有域名选择设置
    const domainSetting = config.variables?.['apiDomain'];
    
    if (!domainSetting || domainSetting === 'main') {
      return config.baseUrl;
    }

    // 使用备用域名
    if (config.alternativeUrls && config.alternativeUrls[domainSetting]) {
      const alternativeUrl = config.alternativeUrls[domainSetting];
      logger.info(TAG, `使用备用域名: ${domainSetting} -> ${alternativeUrl}`);
      return alternativeUrl;
    }

    // 如果找不到备用域名，返回默认baseUrl
    logger.warn(TAG, `未找到备用域名: ${domainSetting}，使用默认baseUrl`);
    return config.baseUrl;
  }

  /**
   * 验证URL是否有效
   */
  isValidUrl(url: string): boolean {
    try {
      // 简单验证URL格式
      return url.startsWith('http://') || url.startsWith('https://');
    } catch (e) {
      return false;
    }
  }

  /**
   * 从URL中提取域名
   */
  extractDomain(url: string): string {
    try {
      const match = url.match(/^https?:\/\/([^\/]+)/);
      return match ? match[1] : '';
    } catch (e) {
      logger.error(TAG, `提取域名失败: ${e}`);
      return '';
    }
  }

  /**
   * 构建完整URL（处理相对路径）
   */
  buildFullUrl(baseUrl: string, path: string): string {
    // 如果path已经是完整URL，直接返回
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }

    // 确保baseUrl不以/结尾
    const cleanBaseUrl = baseUrl.endsWith('/') ? baseUrl.slice(0, -1) : baseUrl;
    
    // 确保path以/开头
    const cleanPath = path.startsWith('/') ? path : '/' + path;
    
    return cleanBaseUrl + cleanPath;
  }

  /**
   * 替换URL中的参数
   */
  replaceUrlParams(url: string, params: Record<string, string>): string {
    let result = url;
    
    Object.keys(params).forEach(key => {
      // 替换路径参数 :param
      result = result.replace(`:${key}`, params[key]);
      
      // 替换模板参数 {param}
      result = result.replace(`{${key}}`, params[key]);
      
      // 替换双花括号参数 {{param}}
      result = result.replace(`{{${key}}}`, params[key]);
    });
    
    return result;
  }

  /**
   * 添加查询参数到URL
   */
  addQueryParams(url: string, params: Record<string, string>): string {
    if (!params || Object.keys(params).length === 0) {
      return url;
    }

    const separator = url.includes('?') ? '&' : '?';
    const queryString = Object.keys(params)
      .map(key => `${encodeURIComponent(key)}=${encodeURIComponent(params[key])}`)
      .join('&');
    
    return url + separator + queryString;
  }

  /**
   * 解析URL查询参数
   */
  parseQueryParams(url: string): Record<string, string> {
    const params: Record<string, string> = {};
    
    try {
      const queryStart = url.indexOf('?');
      if (queryStart === -1) {
        return params;
      }

      const queryString = url.substring(queryStart + 1);
      const pairs = queryString.split('&');
      
      pairs.forEach(pair => {
        const [key, value] = pair.split('=');
        if (key) {
          params[decodeURIComponent(key)] = value ? decodeURIComponent(value) : '';
        }
      });
    } catch (e) {
      logger.error(TAG, `解析查询参数失败: ${e}`);
    }
    
    return params;
  }
}

export default DynamicUrlResolver;
