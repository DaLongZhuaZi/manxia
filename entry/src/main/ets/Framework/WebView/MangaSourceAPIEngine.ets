import { SafeUtils } from '../../Utils/SafeUtils';
/**
 * 漫画图源API请求引擎
 * 处理HTTP/GraphQL API请求，支持JSON数据提取
 */

import { http } from '@kit.NetworkKit';
import { logger } from '../../Utils/Logger';
import { lang } from '@kit.ArkTS';

const TAG = 'MangaSourceAPIEngine';

/**
 * 空对象类
 */
class EmptyObject {
}

/**
 * Headers类 - 使用类而不是接口以支持属性访问
 */
class APIHeaders {
  'Content-Type'?: string;
  'Accept'?: string;
  'User-Agent'?: string;
  'Referer'?: string;
  'Cookie'?: string;
  'Authorization'?: string;
  'Accept-Language'?: string;
  'Cache-Control'?: string;
  'Pragma'?: string;
  'Sec-Fetch-Dest'?: string;
  'Sec-Fetch-Mode'?: string;
  'Sec-Fetch-Site'?: string;
  'Origin'?: string;
  'X-Requested-With'?: string;
  'DNT'?: string;
  'Accept-Encoding'?: string;
  'Connection'?: string;
}

/**
 * 默认Headers类
 */
class DefaultHeaders extends APIHeaders {
  'Content-Type': string = 'application/json';
  'Accept': string = 'application/json';
  'User-Agent': string = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36';
}

/**
 * API请求配置
 */
export interface APIRequestConfig {
  method: 'GET' | 'POST' | 'PUT' | 'DELETE';
  url: string;
  headers?: Object;
  body?: Object | string;
  timeout?: number;
}

/**
 * API响应
 */
export interface APIResponse {
  status: number;
  headers: Object;
  data: Object | string;
}

/**
 * JSON路径提取配置
 */
export interface JSONExtractConfig {
  /** JSON路径（如 "data.comics" 或 "data.comicById.imageUrl"） */
  path?: string;
  /** 字段映射 */
  fields?: Object;
}

/**
 * 漫画图源API引擎
 */
export class MangaSourceAPIEngine {
  private timeout: number = 30000;

  constructor(timeout?: number) {
    if (timeout) {
      this.timeout = timeout;
    }
  }

  /**
   * 执行API请求
   */
  async request(config: APIRequestConfig): Promise<APIResponse> {
    logger.info(TAG, `API请求: ${config.method} ${config.url}`);
    logger.debug(TAG, `请求body类型: ${typeof config.body}`);

    // 内置重试逻辑
    const maxRetries = 3;
    let lastError: Error | null = null;
    
    for (let attempt = 0; attempt < maxRetries; attempt++) {
      try {
        if (attempt > 0) {
          logger.info(TAG, `重试请求 (${attempt}/${maxRetries})`);
          await this.delay(1000 * attempt); // 指数退避
        }
        
        const httpRequest = http.createHttp();
        
        // 规范化并构建headers
        const defaultHeaders: DefaultHeaders = new DefaultHeaders();
        const baseHeaders: Object = this.normalizeHeaders(config.headers || (defaultHeaders as Object));
        
        // 使用规范化后的headers，但对于GET请求需要特殊处理
        let headers: Record<string, string> = baseHeaders as Record<string, string>;
        
        // GET请求不应该有Content-Type头，移除它，并修改Accept头
        if (config.method === 'GET') {
          const newHeaders: Record<string, string> = {};
          const keys = Object.keys(headers);
          for (let i = 0; i < keys.length; i++) {
            const key = keys[i];
            const lowerKey = key.toLowerCase();
            // 跳过Content-Type
            if (lowerKey === 'content-type') {
              continue;
            }
            // 将Accept从 application/json 改为 */*
            if (lowerKey === 'accept' && headers[key] === 'application/json') {
              newHeaders[key] = '*/*';
              continue;
            }
            newHeaders[key] = headers[key];
          }
          headers = newHeaders;
          logger.debug(TAG, 'GET请求：已移除Content-Type头，修改Accept为*/*');
        }
      
      const headerKeys: string[] = Object.keys(headers as Object);
      logger.debug(TAG, `最终Headers键数量: ${String(headerKeys.length)}`);
      logger.debug(TAG, `最终Headers: ${JSON.stringify(headers as Object)}`);

      const options: http.HttpRequestOptions = {
        method: this.convertMethod(config.method),
        header: headers as Object,
        readTimeout: config.timeout || this.timeout,
        connectTimeout: config.timeout || this.timeout,
        usingProxy: true
      };

      // 添加请求体
      if (config.body) {
        if (typeof config.body === 'string') {
          options.extraData = config.body;
          logger.debug(TAG, `请求body(字符串): ${config.body.substring(0, 200)}`);
        } else {
          const bodyStr = JSON.stringify(config.body);
          options.extraData = bodyStr;
          logger.debug(TAG, `请求body(对象): ${bodyStr.substring(0, 200)}`);
          // 如果没有提供headers，使用默认的JSON content-type
          // ArkTS不支持索引访问，所以直接使用headers对象
        }
      }

      const effectiveTimeout: number = options.readTimeout || this.timeout;
      logger.debug(TAG, `超时设置: read=${String(options.readTimeout)}ms, connect=${String(options.connectTimeout)}ms`);
      logger.info(TAG, '即将调用底层 http.request');
      let response: http.HttpResponse;
      try {
        response = await this.withTimeoutHttp(httpRequest.request(config.url, options), effectiveTimeout, config.url);
        logger.info(TAG, '底层 http.request 调用已返回');
      } catch (reqError) {
        const reqMsg: string = reqError instanceof Error ? reqError.message : String(reqError);
        logger.error(TAG, `http.request 调用失败或超时: ${reqMsg}`);
        throw new Error(reqMsg);
      }
      
      logger.debug(TAG, `API响应状态: ${response.responseCode}`);

      // 解析响应
      let responseData: Object | string;
      logger.debug(TAG, `响应result类型: ${typeof response.result}`);
      if (typeof response.result === 'string') {
        logger.debug(TAG, `响应字符串长度: ${response.result.length}, 前100字符: ${response.result.substring(0, 100)}`);
        try {
          responseData = SafeUtils.parseObj(response.result) as Object;
          logger.debug(TAG, `JSON解析成功`);
        } catch (e) {
          logger.warn(TAG, `JSON解析失败: ${e}`);
          responseData = response.result;
        }
      } else {
        responseData = response.result as Object;
        logger.debug(TAG, `响应直接为对象`);
      }

      try {
        httpRequest.destroy();
      } catch (_destroyErr) {
        logger.warn(TAG, 'HTTP对象销毁异常');
      }

      // 创建明确的响应对象
        const apiResponse: APIResponse = {
          status: response.responseCode,
          headers: response.header as Object,
          data: responseData
        };
        return apiResponse;
      } catch (error) {
        lastError = error instanceof Error ? error : new Error(String(error));
        logger.warn(TAG, `请求失败 (尝试 ${attempt + 1}/${maxRetries}): ${lastError.message}`);
        
        // 如果是最后一次尝试，抛出错误
        if (attempt === maxRetries - 1) {
          throw lastError;
        }
      }
    }
    
    // 理论上不会到这里，但为了类型安全
    throw lastError || new Error('请求失败');
  }

  /**
   * 延迟函数
   */
  private delay(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }

  private async withTimeoutHttp(
    promise: Promise<http.HttpResponse>,
    timeoutMs: number,
    url: string
  ): Promise<http.HttpResponse> {
    return new Promise<http.HttpResponse>((resolve, reject) => {
      let settled: boolean = false;
      const timerId: number = setTimeout((): void => {
        if (!settled) {
          settled = true;
          const msg: string = `请求超时(${String(timeoutMs)}ms): ${url}`;
          reject(new Error(msg));
        }
      }, timeoutMs);

      promise
        .then((resp: http.HttpResponse): void => {
          if (!settled) {
            settled = true;
            clearTimeout(timerId);
            resolve(resp);
          }
        })
        .catch((err: Object): void => {
          if (!settled) {
            settled = true;
            clearTimeout(timerId);
            const msg: string = err instanceof Error ? err.message : String(err);
            reject(new Error(msg));
          }
        });
    });
  }

  /**
   * 规范化headers，确保类型安全
   */
  private normalizeHeaders(input?: Object): Object {
    // 初始化默认Headers
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36'
    };

    if (input) {
      const inputRecord: Record<string, Object> = input as Record<string, Object>;
      const keys: string[] = Object.keys(inputRecord);
      for (let i = 0; i < keys.length; i++) {
        const key = keys[i];
        const value = inputRecord[key];
        if (value !== undefined && value !== null) {
          headers[key] = String(value);
        }
      }
    }

    // [修复] 不再自动添加Origin头
    // CopyManga等API对Origin头敏感，添加会导致返回"error"
    // Origin头完全由配置控制，不自动添加

    return headers;
  }


  /**
   * 执行GraphQL查询
   */
  async graphql(endpoint: string, query: string, variables?: Object, headers?: Object): Promise<Object> {
    const emptyVars: EmptyObject = new EmptyObject();
    interface GraphQLRequestBody { query: string; variables: Object; }
    const body: GraphQLRequestBody = { query: query, variables: variables || (emptyVars as Object) };

    const defaultHeaders: DefaultHeaders = new DefaultHeaders();
    
    const config: APIRequestConfig = {
      method: 'POST',
      url: endpoint,
      headers: headers || (defaultHeaders as Object),
      body: body as Object
    };

    const response = await this.request(config);
    
    if (response.status !== 200) {
      throw new Error(`GraphQL请求失败: HTTP ${response.status}`);
    }

    return response.data as Object;
  }

  /**
   * 从JSON数据中提取字段
   */
  extractFromJSON(data: Object, config: JSONExtractConfig): Object | Object[] | null {
    logger.debug(TAG, `提取JSON数据，路径: ${config.path || 'root'}`);
    logger.debug(TAG, `响应数据类型: ${typeof data}, 是否为null: ${data === null}, 是否为undefined: ${data === undefined}`);
    if (data) {
      logger.debug(TAG, `响应数据keys: ${Object.keys(data).join(', ')}`);
    }

    // 获取目标数据
    let targetData: Object | Object[] | null = data;
    if (config.path) {
      targetData = this.getValueByPath(data, config.path);
      logger.debug(TAG, `路径提取后数据类型: ${typeof targetData}, 是否为null: ${targetData === null}`);
    }

    // [修复] 如果提取结果无效（null/undefined），直接返回空结果，避免后续错误映射
    if (targetData === null || targetData === undefined) {
      logger.warn(TAG, `路径 ${config.path} 提取结果为空`);
      // 如果配置暗示需要数组（path包含 [*]），返回空数组；否则返回 null
      return config.path && config.path.includes('[*]') ? [] : null;
    }

    // 如果没有字段映射，直接返回
    if (!config.fields) {
      return targetData;
    }

    // 应用字段映射
    if (Array.isArray(targetData)) {
      return (targetData as Object[]).map((item: Object): Object => this.mapFields(item, config.fields!));
    } else {
      return this.mapFields(targetData as Object, config.fields!);
    }
  }

  /**
   * 通过路径获取值（支持点号和数组索引）
   */
  private getValueByPath(obj: Object, path: string): Object | Object[] | null {
    const parts = path.split('.');
    let current: Object | Object[] | null = obj;
    let isArray = false;

    for (let i = 0; i < parts.length; i++) {
      const part = parts[i];

      // [修复] 如果当前对象为空，无法继续深入，返回 null
      if (!current) {
        return null;
      }

      if (!current) {
        return new EmptyObject() as Object;
      }

      // 处理数组索引 [0] 或 [*]
      const arrayMatch = part.match(/^(.+)\[(\d+|\*)\]$/);
      if (arrayMatch) {
        const key = arrayMatch[1];
        const index = arrayMatch[2];

        // 如果当前是数组，需要对每个元素应用路径
        if (isArray && Array.isArray(current)) {
          current = (current as Object[]).map((item: Object): Object | Object[] => {
            const itemRecord: Record<string, Object> = item as Record<string, Object>;
            const itemKeys: string[] = Object.keys(itemRecord);
            let valueObj: Object = new EmptyObject();
            if (itemKeys.includes(key)) {
              valueObj = itemRecord[key];
            }
            const isArr: boolean = Array.isArray(valueObj);
            const val: Object | Object[] = isArr ? (valueObj as Object[]) : (valueObj as Object);
            if (index === '*' && isArr) {
              return val;
            } else if (index !== '*') {
              return isArr ? (val as Object[])[Number(index)] : val;
            }
            return val;
          }).flat();
          isArray = true;
        } else {
          const currRecord: Record<string, Object> = current as Record<string, Object>;
          const currKeys: string[] = Object.keys(currRecord);
          if (!currKeys.includes(key)) return null;
          const nextObjRaw: Object = currRecord[key];
          current = Array.isArray(nextObjRaw) ? (nextObjRaw as Object[]) : (nextObjRaw as Object);

          if (index === '*') {
            // 标记为数组模式，继续处理后续路径
            isArray = true;
          } else {
            // 安全访问数组索引
            if (!Array.isArray(current) || Number(index) >= current.length) return null; // [修复] 索引越界或非数组
            current = (current as Object[])[Number(index)];
            isArray = false;
          }
        }
      } else {
        // 如果当前是数组模式，对每个元素获取属性
        if (isArray && Array.isArray(current)) {
          current = (current as Object[]).map((item: Object): Object | Object[] => {
            const itemRecord: Record<string, Object> = item as Record<string, Object>;
            const itemKeys: string[] = Object.keys(itemRecord);
            if (!itemKeys.includes(part)) {
              return new EmptyObject() as Object;
            }
            const raw: Object = itemRecord[part];
            return Array.isArray(raw) ? (raw as Object[]) : (raw as Object);
          }).flat();
        } else {
          const currRecord2: Record<string, Object> = current as Record<string, Object>;
          const currKeys2: string[] = Object.keys(currRecord2);
          if (!currKeys2.includes(part)) return null;
          const nextValRaw: Object = currRecord2[part];
          const nextVal: Object | Object[] = Array.isArray(nextValRaw) ? (nextValRaw as Object[]) : (nextValRaw as Object);
          current = nextVal;
          isArray = Array.isArray(current);
        }
      }
    }

    return current;
  }

  /**
   * 映射字段
   */
  private mapFields(source: Object, fieldMap: Object): Object {
    const result: Record<string, Object | null> = {};
    const keys = Object.keys(fieldMap);

    for (let i = 0; i < keys.length; i++) {
      const targetField = keys[i];
      const sourcePath = (fieldMap as Record<string, Object>)[targetField] as string;
      
      // 如果路径为空字符串，直接使用source本身（用于字符串数组）
      if (sourcePath === '') {
        result[targetField] = source;
      } else if (sourcePath.includes('[*]')) {
        // 处理数组聚合 [*].name
        const value: Object | Object[] | null = this.getValueByPath(source, sourcePath);
        result[targetField] = value;
      } else {
        const value: Object | Object[] | null = this.getValueByPath(source, sourcePath);
        result[targetField] = value;
      }
    }

    return result;
  }

  /**
   * 转换HTTP方法
   */
  private convertMethod(method: string): http.RequestMethod {
    if (method === 'GET') {
      return http.RequestMethod.GET;
    } else if (method === 'POST') {
      return http.RequestMethod.POST;
    } else if (method === 'PUT') {
      return http.RequestMethod.PUT;
    } else if (method === 'DELETE') {
      return http.RequestMethod.DELETE;
    } else {
      return http.RequestMethod.GET;
    }
  }

  /**
   * 替换URL中的变量
   */
  replaceVariables(template: string, variables: Object): string {
    let result = template;
    const keys = Object.keys(variables);
    
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i];
      const varsRecord: Record<string, Object> = variables as Record<string, Object>;
      const varKeys: string[] = Object.keys(varsRecord);
      const valueObj: Object = varKeys.includes(key) ? varsRecord[key] : '';
      const valueStr: string = String(valueObj);
      const pattern = new RegExp(`\\{\\{${key}\\}\\}`, 'g');
      result = result.replace(pattern, valueStr);
    }
    
    return result;
  }
}
