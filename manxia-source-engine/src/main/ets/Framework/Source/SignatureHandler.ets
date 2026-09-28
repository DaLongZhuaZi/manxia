/**
 * 签名处理器
 * 为API请求生成签名（支持HMAC-SHA256等）
 */

import { hmacSHA256, generateRandomString } from 'manxia_core/src/main/ets/Utils/CryptoUtils';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';

const TAG = 'SignatureHandler';

/**
 * 签名配置
 */
export interface SignatureConfig {
  enabled: boolean;
  algorithm: 'hmac-sha256' | 'md5' | 'sha256';
  key: string;
  headers: Record<string, string>;
  signatureFormat: string;
  toLowerCase?: boolean;
}

/**
 * 签名上下文
 */
export interface SignatureContext {
  url: string;
  method: string;
  timestamp?: number;
  nonce?: string;
  apiKey?: string;
  path?: string;
  time?: string;
}

/**
 * 签名处理器类
 */
export class SignatureHandler {
  private config: SignatureConfig;

  constructor(config: SignatureConfig) {
    this.config = config;
  }

  /**
   * 为请求生成签名头
   * @param context 签名上下文
   * @returns 包含签名的请求头
   */
  async generateSignatureHeaders(context: SignatureContext): Promise<Record<string, string>> {
    if (!this.config.enabled) {
      return {};
    }

    try {
      // 生成时间戳和nonce
      const timestamp: number = context.timestamp !== undefined ? context.timestamp : Math.floor(Date.now() / 1000);
      const nonce: string = context.nonce !== undefined ? context.nonce : generateRandomString(32);

      // 提取URL路径
      const url: string = context.url;
      const path: string = this.extractPath(url);

      // 构建签名上下文
      const signContext: SignatureContext = {
        url: context.url,
        method: context.method,
        timestamp: timestamp,
        nonce: nonce,
        apiKey: context.apiKey,
        path: path,
        time: timestamp.toString()
      };

      // 构建签名字符串
      const signatureData: string = this.buildSignatureData(signContext);

      // 计算签名
      const signature: string = await this.computeSignature(signatureData);

      // 构建签名头
      const headers: Record<string, string> = {};
      const headerKeys: string[] = Object.keys(this.config.headers);
      for (let i: number = 0; i < headerKeys.length; i++) {
        const key: string = headerKeys[i];
        const template: string = this.config.headers[key];
        const vars: Record<string, string> = {
          'timestamp': timestamp.toString(),
          'time': timestamp.toString(),
          'nonce': nonce,
          'signature': signature
        };
        headers[key] = this.replaceVariables(template, vars);
      }

      logger.debug(TAG, `生成签名头: ${JSON.stringify(headers)}`);
      return headers;
    } catch (error) {
      logger.error(TAG, `生成签名失败: ${error}`);
      throw new Error(String(error));
    }
  }

  /**
   * 从URL中提取路径
   */
  private extractPath(url: string): string {
    try {
      // 移除协议和域名
      const match = url.match(/^https?:\/\/[^\/]+(.*)$/);
      if (match && match[1]) {
        return match[1];
      }
      return url;
    } catch (error) {
      logger.error(TAG, `提取路径失败: ${error}`);
      return url;
    }
  }

  /**
   * 构建签名数据字符串
   */
  private buildSignatureData(context: SignatureContext): string {
    let data: string = this.config.signatureFormat;

    // 构建变量映射
    const vars: Record<string, string> = {
      'url': context.url,
      'method': context.method,
      'timestamp': context.timestamp !== undefined ? context.timestamp.toString() : '',
      'nonce': context.nonce !== undefined ? context.nonce : '',
      'apiKey': context.apiKey !== undefined ? context.apiKey : '',
      'path': context.path !== undefined ? context.path : '',
      'time': context.time !== undefined ? context.time : ''
    };

    // 替换变量
    data = this.replaceVariables(data, vars);

    // 转换为小写（如果需要）
    if (this.config.toLowerCase) {
      data = data.toLowerCase();
    }

    logger.debug(TAG, `签名数据: ${data}`);
    return data;
  }

  /**
   * 计算签名
   */
  private async computeSignature(data: string): Promise<string> {
    switch (this.config.algorithm) {
      case 'hmac-sha256':
        return await hmacSHA256(this.config.key, data);
      default:
        throw new Error(`不支持的签名算法: ${this.config.algorithm}`);
    }
  }

  /**
   * 替换模板中的变量
   */
  private replaceVariables(template: string, variables: Record<string, string>): string {
    let result: string = template;

    // 替换 {{variable}} 格式的变量
    const keys: string[] = Object.keys(variables);
    for (let i: number = 0; i < keys.length; i++) {
      const key: string = keys[i];
      const value: string = variables[key];
      const pattern: string = `{{${key}}}`;
      // 使用 split + join 替代 replace 以避免正则表达式问题
      result = result.split(pattern).join(value);
    }

    return result;
  }

  /**
   * 验证签名配置
   */
  static validateConfig(config: SignatureConfig): boolean {
    if (!config.enabled) {
      return true;
    }

    if (!config.algorithm || !config.key || !config.signatureFormat) {
      logger.error(TAG, '签名配置不完整');
      return false;
    }

    return true;
  }
}

/**
 * 为PicaComic生成签名（专用方法）
 * @param url 请求URL
 * @param method 请求方法
 * @param apiKey API密钥
 * @param hmacKey HMAC密钥
 * @returns 签名头对象
 */
export async function generatePicaSignature(
  url: string,
  method: string,
  apiKey: string,
  hmacKey: string
): Promise<Record<string, string>> {
  try {
    // 生成时间戳和nonce
    const time: number = Math.floor(Date.now() / 1000);
    const nonce: string = generateRandomString(32);

    // 提取路径（包含查询参数，不包含前导斜杠）
    // 关键修复：Kotlin 版本使用 url.substringAfter("$baseUrl/")，这会保留查询参数！
    // 例如: https://picaapi.picacomic.com/comics?page=1&s=dd -> comics?page=1&s=dd
    // 例如: https://picaapi.picacomic.com/auth/sign-in -> auth/sign-in
    let path: string = '';
    const pathMatch: RegExpMatchArray | null = url.match(/^https?:\/\/[^\/]+\/(.*)$/);
    if (pathMatch !== null && pathMatch[1] !== undefined) {
      path = pathMatch[1];
    } else {
      // 如果匹配失败，尝试直接使用 URL
      path = url;
    }
    
    logger.debug(TAG, `PicaComic签名路径: "${path}", 方法: ${method}`);

    // 构建签名字符串: path + time + nonce + method + apiKey
    const raw: string = `${path}${time}${nonce}${method}${apiKey}`.toLowerCase();
    logger.debug(TAG, `PicaComic签名原始字符串: ${raw.substring(0, 50)}...`);

    // 计算HMAC-SHA256
    const signature = await hmacSHA256(hmacKey, raw);

    return {
      'time': time.toString(),
      'nonce': nonce,
      'signature': signature
    };
  } catch (error) {
    logger.error(TAG, `生成PicaComic签名失败: ${error}`);
    throw new Error(String(error));
  }
}
