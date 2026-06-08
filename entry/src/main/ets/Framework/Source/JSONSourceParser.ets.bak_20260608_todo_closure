import { SafeUtils } from '../../Utils/SafeUtils';
/**
 * JSON图源解析器
 * 解析JSON格式的图源配置文件
 */

import { logger } from '../../Utils/Logger';
import { JSONPathParser } from '../Utils/JSONPathParser';
import { VariableReplacer, VariableContext } from '../Utils/VariableReplacer';

const TAG = 'JSONSourceParser';

/**
 * JSON图源配置
 */
export interface JSONSourceConfig {
  metadata: SourceMetadata;
  network: NetworkConfig;
  api: APIConfig;
  features: FeaturesConfig;
  settings?: SettingsConfig;
  urlPatterns?: Record<string, string>;
  notes?: string[];
  changelog?: ChangelogEntry[];
}

/**
 * 图源类型
 */
export type SourceType = 'manga' | 'ebook' | 'novel' | 'video' | 'audio' | 'image';

export interface SourceMetadata {
  id: string;
  name: string;
  type?: SourceType;  // 图源类型（默认为manga）
  version: string;
  language: string;
  baseUrl: string;
  description?: string;
  author?: string;
  icon?: string;
  nsfw?: boolean;
  tags?: string[];
  updateStrategy?: string;
}

export interface RateLimitConfig {
  requestsPerSecond: number;
  burstSize: number;
}

export interface NetworkConfig {
  userAgent?: string;
  headers?: Record<string, Object | undefined>;
  timeout?: number;
  retryCount?: number;
  retryDelay?: number;
  rateLimit?: RateLimitConfig;
}

export interface AuthenticationConfig {
  type: 'none' | 'basic' | 'bearer' | 'oauth2' | 'custom';
  credentials?: Record<string, Object | undefined>;
}

export interface APIConfig {
  type: 'rest' | 'graphql' | 'html' | 'custom';
  endpoint: string;
  authentication?: AuthenticationConfig;
}

export interface FeaturesConfig {
  popular?: FeatureDefinition;
  latest?: FeatureDefinition;
  search?: FeatureDefinition;
  detail?: FeatureDefinition;
  pages?: FeatureDefinition;
}

export interface FeatureDefinition {
  enabled: boolean;
  method?: 'GET' | 'POST' | 'PUT' | 'DELETE';
  url?: string;
  body?: Record<string, Object | undefined>;
  responseType?: 'json' | 'html' | 'xml' | 'text';
  parser?: ParserConfig;
  pagination?: PaginationConfig;
  filters?: FilterConfig[];
  imageHeaders?: Record<string, string>;
}

export interface ParserConfig {
  type: 'json' | 'html' | 'xml';
  listPath?: string;
  root?: string;
  item?: Record<string, Object | undefined>;
  fields?: Record<string, Object | undefined>;
}

export interface PaginationConfig {
  type: 'offset' | 'page' | 'cursor';
  limitParam?: string;
  offsetParam?: string;
  pageParam?: string;
  defaultLimit?: number;
  maxLimit?: number;
}

export interface FilterOption {
  value: string;
  label: string;
}

export interface FilterConfig {
  type: 'text' | 'number' | 'boolean' | 'select' | 'multiselect';
  id: string;
  name: string;
  default?: string | number | boolean;
  options?: FilterOption[];
  placeholder?: string;
  min?: number;
  max?: number;
}

export interface SettingOption {
  value: string;
  label: string;
}

export interface SettingDefinition {
  type: 'text' | 'number' | 'boolean' | 'select' | 'multiselect';
  name: string;
  default?: string | number | boolean;
  options?: SettingOption[];
}

export type SettingsConfig = Record<string, Object | undefined>;

export interface ChangelogEntry {
  version: string;
  date: string;
  changes: string[];
}

/**
 * JSON图源解析器类
 */
export class JSONSourceParser {
  private config: JSONSourceConfig;

  constructor(config: JSONSourceConfig) {
    this.config = config;
  }

  /**
   * 从JSON字符串创建解析器
   */
  static fromJSON(jsonString: string): JSONSourceParser {
    try {
      const config = SafeUtils.parseObj(jsonString) as JSONSourceConfig;
      return new JSONSourceParser(config);
    } catch (error) {
      logger.error(TAG, 'JSON解析失败', String(error));
      throw new Error(`JSON解析失败: ${error}`);
    }
  }

  /**
   * 验证配置
   */
  validate(): boolean {
    try {
      // 验证必需字段
      if (!this.config.metadata?.id || !this.config.metadata?.name) {
        logger.error(TAG, '缺少必需的metadata字段');
        return false;
      }

      if (!this.config.metadata?.baseUrl) {
        logger.error(TAG, '缺少baseUrl');
        return false;
      }

      if (!this.config.features) {
        logger.error(TAG, '缺少features配置');
        return false;
      }

      logger.info(TAG, `图源配置验证通过: ${this.config.metadata.name}`);
      return true;
    } catch (error) {
      logger.error(TAG, '配置验证失败', String(error));
      return false;
    }
  }

  /**
   * 获取元数据
   */
  getMetadata(): SourceMetadata {
    return this.config.metadata;
  }

  /**
   * 获取网络配置
   */
  getNetworkConfig(): NetworkConfig {
    return this.config.network || {};
  }

  /**
   * 获取功能定义
   */
  getFeature(featureName: string): FeatureDefinition | undefined {
    return (this.config.features as Record<string, Object | undefined>)[featureName] as FeatureDefinition;
  }

  /**
   * 构建请求
   */
  buildRequest(featureName: string, params: Record<string, Object | undefined>): RequestInfo {
    const feature = this.getFeature(featureName);
    if (!feature || !feature.enabled) {
      throw new Error(`功能未启用: ${featureName}`);
    }

    // 创建变量上下文
    const context: VariableContext = this.createContext(params);

    // 替换URL中的变量
    const url: string = feature.url ? VariableReplacer.replace(feature.url, context) : '';

    // 替换请求体中的变量
    const body: Record<string, Object | undefined> | undefined = feature.body ? VariableReplacer.replaceObject(feature.body, context) : undefined;

    // 合并请求头 - 手动复制而不是使用展开运算符
    const headers: Record<string, Object | undefined> = {};
    if (this.config.network?.headers) {
      const headerKeys = Object.keys(this.config.network.headers);
      for (const key of headerKeys) {
        headers[key] = this.config.network.headers[key];
      }
    }

    const requestInfo: RequestInfo = {
      method: feature.method || 'GET',
      url: url,
      headers: headers,
      body: body,
      timeout: this.config.network?.timeout || 30000,
    };

    return requestInfo;
  }

  /**
   * 解析响应
   */
  parseResponse(featureName: string, response: Record<string, Object | undefined>): Record<string, Object | undefined>[] {
    const feature = this.getFeature(featureName);
    if (!feature || !feature.parser) {
      return [];
    }

    const parser = feature.parser;

    if (parser.type === 'json') {
      return this.parseJSONResponse(response, parser);
    }

    // HTML和XML解析待实现
    logger.warn(TAG, `暂不支持的解析器类型: ${parser.type}`);
    return [];
  }

  /**
   * 解析JSON响应
   */
  private parseJSONResponse(response: Record<string, Object | undefined>, parser: ParserConfig): Record<string, Object | undefined>[] {
    try {
      // 获取列表数据
      const listPath: string | undefined = parser.listPath || parser.root;
      const items: Object[] = listPath ? JSONPathParser.parseArray(response as Record<string, Object>, listPath) : [response];

      // 解析每个项目
      const results: Record<string, Object | undefined>[] = [];
      for (let i = 0; i < items.length; i++) {
        const item: Record<string, Object | undefined> = items[i] as Record<string, Object | undefined>;
        const itemMapping: Record<string, Object | undefined> = parser.item || parser.fields || {};
        const parsed: Record<string, Object | undefined> = this.parseItem(item, itemMapping);
        if (parsed) {
          results.push(parsed);
        }
      }

      return results;
    } catch (error) {
      logger.error(TAG, 'JSON响应解析失败', String(error));
      return [];
    }
  }

  /**
   * 解析单个项目
   */
  private parseItem(item: Record<string, Object | undefined>, mapping: Record<string, Object | undefined>): Record<string, Object | undefined> {
    const result: Record<string, Object | undefined> = {};
    const mappingKeys = Object.keys(mapping);

    for (const key of mappingKeys) {
      const value: Object | undefined = mapping[key];

      if (typeof value === 'string') {
        // 简单的JSONPath映射
        result[key] = JSONPathParser.parseString(item as Record<string, Object>, value);
      } else if (typeof value === 'object' && value !== null) {
        // 嵌套对象或数组
        const nestedMapping: Record<string, Object | undefined> = value as Record<string, Object | undefined>;
        if (nestedMapping.listPath) {
          // 数组映射
          const nestedItems: Object[] = JSONPathParser.parseArray(item as Record<string, Object>, nestedMapping.listPath as string);
          result[key] = nestedItems.map((nestedItem: Object): Record<string, Object | undefined> => 
            this.parseItem(nestedItem as Record<string, Object | undefined>, nestedMapping.item as Record<string, Object | undefined>)
          );
        } else {
          // 对象映射
          result[key] = this.parseItem(item, nestedMapping);
        }
      }
    }

    return result;
  }

  /**
   * 创建变量上下文
   */
  private createContext(params: Record<string, Object | undefined>): VariableContext {
    const context: VariableContext = {};
    context['baseUrl'] = this.config.metadata.baseUrl;

    // 手动复制params而不是使用展开运算符
    const paramKeys = Object.keys(params);
    for (const key of paramKeys) {
      context[key] = params[key];
    }

    // 添加设置变量
    if (this.config.settings) {
      const settingKeys = Object.keys(this.config.settings);
      for (const key of settingKeys) {
        const setting: Record<string, Object | undefined> = this.config.settings[key] as Record<string, Object | undefined>;
        if (setting.default !== undefined) {
          context[`settings.${key}`] = setting.default;
        }
      }
    }

    return context;
  }

  /**
   * 获取配置
   */
  getConfig(): JSONSourceConfig {
    return this.config;
  }
}

/**
 * 请求信息
 */
export interface RequestInfo {
  method: string;
  url: string;
  headers: Record<string, Object | undefined>;
  body?: Record<string, Object | undefined>;
  timeout: number;
}
