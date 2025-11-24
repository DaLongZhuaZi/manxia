// 文件路径: src/main/ets/Framework/WebView/ConfigurationParser.ets
/**
 * WebView配置解析器
 * 负责解析JSON配置文件并转换为类型安全的配置对象
 * 符合HarmonyOS API 18和ArkTS类型安全要求
 */

import { logger } from '../../Utils/Logger';
import { TimeUtils } from '../Utils/TimeUtils';

const TAG = 'ConfigurationParser';

// 动态对象类型接口，替代ESObject
export interface DynamicObject {
  // 通用属性
  enabled?: boolean;
  name?: string;
  type?: string;
  path?: string;
  url?: string;
  timeout?: number;
  maxRequests?: number;
  timeWindow?: number;
  blockDuration?: number;
  
  // 数组属性
  userAgents?: string[];
  whitelist?: string[];
  blacklist?: string[];
  allowedOrigins?: string[];
  blockedResources?: string[];
  
  // 嵌套对象属性
  rateLimit?: DynamicObject;
  headers?: Record<string, string>;
  antiCrawler?: DynamicObject;
  domainControl?: DynamicObject;
  csp?: DynamicObject;
  
  // 配置相关属性
  config?: DynamicObject;
  metadata?: DynamicObject;
  webview?: DynamicObject;
  security?: DynamicObject;
  
  // 网络相关属性
  network?: DynamicObject;
  cache?: DynamicObject;
  basic?: DynamicObject;
  
  // 扩展相关属性
  extensions?: DynamicObject[];
  
  // CSP相关属性
  defaultSrc?: string[];
  scriptSrc?: string[];
  styleSrc?: string[];
  imgSrc?: string[];
  connectSrc?: string[];
  fontSrc?: string[];
  objectSrc?: string[];
  mediaSrc?: string[];
  frameSrc?: string[];
  
  // 其他常用属性
  version?: string;
  author?: string;
  description?: string;
  title?: string;
  content?: string;
  value?: string | number | boolean;
  data?: DynamicObject;
  options?: DynamicObject;
  settings?: DynamicObject;
  params?: DynamicObject;
  properties?: DynamicObject;

  //补充
  created?: string;
  updated?: string;
  javaScriptAccess?: boolean;
  domStorageAccess?: boolean;
  fileAccess?: boolean;
  imageAccess?: boolean;
  userAgent?: string;
  allowUniversalAccessFromFileURLs?: boolean;
  allowFileAccessFromFileURLs?: boolean;
  retryCount?: number;
  maxConcurrentRequests?: number;
  enableCompression?: boolean;
  followRedirects?: boolean;
  maxSize?: number;
  maxAge?: number;
  strategy?: 'memory-first' | 'disk-first' | 'network-first';
  policy?: string;
  reportOnly?: boolean;
  
  // 新增：动态域名切换
  baseUrl?: string;
  alternativeUrls?: Record<string, string>;
  
  // 新增：User-Agent轮换
  userAgentRotation?: DynamicObject;
  
  // 新增：简繁转换
  textProcessing?: DynamicObject;
  chineseConversion?: DynamicObject;
  
  // 新增：分页配置
  pagination?: DynamicObject;
  
  // 新增：会话管理
  sessionRefresh?: DynamicObject;
  authentication?: DynamicObject;
  
  // 新增：错误处理
  errorHandling?: DynamicObject;
  retry?: DynamicObject;
  fallback?: DynamicObject;
}

// 配置元数据接口
export interface ConfigurationMetadata {
  name: string;
  description: string;
  author: string;
  created: string;
  updated: string;
}

// 基础配置接口
export interface WebViewBasicConfig {
  javaScriptAccess: boolean;
  domStorageAccess: boolean;
  fileAccess: boolean;
  imageAccess: boolean;
  userAgent: string;
  allowUniversalAccessFromFileURLs: boolean;
  allowFileAccessFromFileURLs: boolean;
}

// 网络配置接口
export interface WebViewNetworkConfig {
  timeout: number;
  retryCount: number;
  maxConcurrentRequests: number;
  enableCompression: boolean;
  followRedirects: boolean;
}

// 缓存配置接口
export interface WebViewCacheConfig {
  enabled: boolean;
  maxSize: number;
  maxAge: number;
  strategy: 'memory-first' | 'disk-first' | 'network-first';
}

// 扩展配置接口
export interface WebViewExtensionConfig {
  name: string;
  type: 'native';
  path: string;
  enabled: boolean;
  config: Record<string, DynamicObject>;
}

// 主配置接口
export interface WebViewConfig {
  basic: WebViewBasicConfig;
  network: WebViewNetworkConfig;
  cache: WebViewCacheConfig;
}

export interface WebViewConfiguration {
  version: string;
  metadata: ConfigurationMetadata;
  webview: WebViewConfig;
  extensions: WebViewExtensionConfig[];
}

// 安全策略配置接口
export interface CSPConfig {
  enabled: boolean;
  policy: string;
  reportOnly: boolean;
}

export interface RateLimitConfig {
  maxRequests: number;
  timeWindow: number;
  blockDuration: number;
}

// 专门为ConfigurationParser定义的AntiCrawlerConfig接口
export interface SecurityAntiCrawlerConfig {
  enabled: boolean;
  userAgents: string[];
  rateLimit: RateLimitConfig;
  headers: Record<string, string>;
}

export interface DomainControlConfig {
  whitelist: string[];
  blacklist: string[];
}

export interface SecurityPolicyConfig {
  csp: CSPConfig;
  antiCrawler: SecurityAntiCrawlerConfig;
  domainControl: DomainControlConfig;
}

export interface SecurityPolicyConfiguration {
  version: string;
  metadata: ConfigurationMetadata;
  security: SecurityPolicyConfig;
}

// 缓存策略配置接口
export interface CacheLevel {
  name: string;
  enabled: boolean;
  maxSize: number;
  maxAge: number;
  priority: number;
  path?: string;
}

export interface CacheStrategy {
  level: string;
  maxAge: number;
  compression?: boolean;
  minify?: boolean;
}

export interface CacheStrategyConfig {
  images: CacheStrategy;
  scripts: CacheStrategy;
  styles: CacheStrategy;
}

export interface CachePolicyConfig {
  levels: CacheLevel[];
  strategies: CacheStrategyConfig;
}

export interface CachePolicyConfiguration {
  version: string;
  metadata: ConfigurationMetadata;
  cache: CachePolicyConfig;
}

// 验证结果接口
export interface ValidationError {
  field: string;
  message: string;
  code: string;
}

export interface ValidationWarning {
  field: string;
  message: string;
  suggestion: string;
}

export interface ValidationResult {
  isValid: boolean;
  errors: ValidationError[];
  warnings: ValidationWarning[];
}

// 配置解析器接口 - 移除Partial工具类型
export interface ConfigurationParser<T> {
  parse(jsonContent: string): T | null;
  validate(config: T): ValidationResult;
  merge(base: T, override: T): T;
  serialize(config: T): string;
}

// 错误代码枚举
export enum ConfigurationErrorCode {
  INVALID_JSON = 'INVALID_JSON',
  MISSING_REQUIRED_FIELD = 'MISSING_REQUIRED_FIELD',
  INVALID_FIELD_TYPE = 'INVALID_FIELD_TYPE',
  INVALID_FIELD_VALUE = 'INVALID_FIELD_VALUE',
  UNSUPPORTED_VERSION = 'UNSUPPORTED_VERSION'
}

// 配置错误类
export class ConfigurationError extends Error {
  code: ConfigurationErrorCode;
  field?: string;

  constructor(code: ConfigurationErrorCode, message: string, field?: string) {
    super(message);
    this.code = code;
    this.field = field;
    this.name = 'ConfigurationError';
  }
}

// 定义默认配置对象接口
interface DefaultWebViewConfiguration {
  version: string;
  metadata: ConfigurationMetadata;
  webview: WebViewConfig;
  extensions: WebViewExtensionConfig[];
}

// WebView基础配置解析器
export class WebViewConfigurationParser implements ConfigurationParser<WebViewConfiguration> {
  private static readonly SUPPORTED_VERSIONS = ['1.0.0'];
  private static readonly DEFAULT_CONFIG: DefaultWebViewConfiguration = {
    version: '1.0.0',
    metadata: {
      name: 'Default WebView Configuration',
      description: 'Default configuration for WebView component',
      author: 'System',
      created: TimeUtils.toISOString(Date.now()),
      updated: TimeUtils.toISOString(Date.now())
    },
    webview: {
      basic: {
        javaScriptAccess: true,
        domStorageAccess: true,
        fileAccess: false,
        imageAccess: true,
        userAgent: 'HarmonyOS WebView/1.0',
        allowUniversalAccessFromFileURLs: false,
        allowFileAccessFromFileURLs: false
      },
      network: {
        timeout: 30000,
        retryCount: 3,
        maxConcurrentRequests: 6,
        enableCompression: true,
        followRedirects: true
      },
      cache: {
        enabled: true,
        maxSize: 104857600, // 100MB
        maxAge: 86400000, // 24 hours
        strategy: 'memory-first'
      }
    },
    extensions: []
  };

  parse(jsonContent: string): WebViewConfiguration | null {
    try {
      logger.debug(TAG, '开始解析WebView配置文件');
      
      // 解析JSON字符串
      const rawConfig = JSON.parse(jsonContent) as DynamicObject;
      
      // 验证基本结构
      if (!this.isValidRawConfig(rawConfig)) {
        logger.error(TAG, '配置文件格式无效');
        return null;
      }

      // 转换为类型安全的配置对象
      const config = this.convertToTypedConfig(rawConfig);
      
      // 验证配置
      const validationResult = this.validate(config);
      if (!validationResult.isValid) {
        const errorMessage = validationResult.errors.map(e => e.message).join(', ');
        logger.error(TAG, '配置验证失败: ' + errorMessage);
        return null;
      }

      logger.info(TAG, 'WebView配置解析成功');
      return config;
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error(TAG, '解析WebView配置时发生错误: ' + errorMessage);
      return null;
    }
  }

  validate(config: WebViewConfiguration): ValidationResult {
    const errors: ValidationError[] = [];
    const warnings: ValidationWarning[] = [];

    // 验证版本
    if (!WebViewConfigurationParser.SUPPORTED_VERSIONS.includes(config.version)) {
      errors.push({
        field: 'version',
        message: `不支持的版本: ${config.version}`,
        code: ConfigurationErrorCode.UNSUPPORTED_VERSION
      });
    }

    // 验证基础配置
    this.validateBasicConfig(config.webview.basic, errors, warnings);
    
    // 验证网络配置
    this.validateNetworkConfig(config.webview.network, errors, warnings);
    
    // 验证缓存配置
    this.validateCacheConfig(config.webview.cache, errors, warnings);
    
    // 验证扩展配置
    this.validateExtensionsConfig(config.extensions, errors, warnings);

    return {
      isValid: errors.length === 0,
      errors,
      warnings
    };
  }

  merge(base: WebViewConfiguration, override: WebViewConfiguration): WebViewConfiguration {
    const merged: WebViewConfiguration = {
      version: override.version || base.version,
      metadata: {
        name: override.metadata.name || base.metadata.name,
        description: override.metadata.description || base.metadata.description,
        author: override.metadata.author || base.metadata.author,
        created: override.metadata.created || base.metadata.created,
        updated: override.metadata.updated || base.metadata.updated
      },
      webview: {
        basic: {
          javaScriptAccess: override.webview.basic.javaScriptAccess !== undefined ? override.webview.basic.javaScriptAccess : base.webview.basic.javaScriptAccess,
          domStorageAccess: override.webview.basic.domStorageAccess !== undefined ? override.webview.basic.domStorageAccess : base.webview.basic.domStorageAccess,
          fileAccess: override.webview.basic.fileAccess !== undefined ? override.webview.basic.fileAccess : base.webview.basic.fileAccess,
          imageAccess: override.webview.basic.imageAccess !== undefined ? override.webview.basic.imageAccess : base.webview.basic.imageAccess,
          userAgent: override.webview.basic.userAgent || base.webview.basic.userAgent,
          allowUniversalAccessFromFileURLs: override.webview.basic.allowUniversalAccessFromFileURLs !== undefined ? override.webview.basic.allowUniversalAccessFromFileURLs : base.webview.basic.allowUniversalAccessFromFileURLs,
          allowFileAccessFromFileURLs: override.webview.basic.allowFileAccessFromFileURLs !== undefined ? override.webview.basic.allowFileAccessFromFileURLs : base.webview.basic.allowFileAccessFromFileURLs
        },
        network: {
          timeout: override.webview.network.timeout || base.webview.network.timeout,
          retryCount: override.webview.network.retryCount !== undefined ? override.webview.network.retryCount : base.webview.network.retryCount,
          maxConcurrentRequests: override.webview.network.maxConcurrentRequests || base.webview.network.maxConcurrentRequests,
          enableCompression: override.webview.network.enableCompression !== undefined ? override.webview.network.enableCompression : base.webview.network.enableCompression,
          followRedirects: override.webview.network.followRedirects !== undefined ? override.webview.network.followRedirects : base.webview.network.followRedirects
        },
        cache: {
          enabled: override.webview.cache.enabled !== undefined ? override.webview.cache.enabled : base.webview.cache.enabled,
          maxSize: override.webview.cache.maxSize || base.webview.cache.maxSize,
          maxAge: override.webview.cache.maxAge || base.webview.cache.maxAge,
          strategy: override.webview.cache.strategy || base.webview.cache.strategy
        }
      },
      extensions: override.extensions.length > 0 ? override.extensions : base.extensions
    };

    return merged;
  }

  serialize(config: WebViewConfiguration): string {
    try {
      return JSON.stringify(config, null, 2);
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error(TAG, '序列化配置时发生错误: ' + errorMessage);
      throw new ConfigurationError(
        ConfigurationErrorCode.INVALID_JSON,
        '无法序列化配置对象'
      );
    }
  }

  static getDefaultConfig(): WebViewConfiguration {
    return JSON.parse(JSON.stringify(WebViewConfigurationParser.DEFAULT_CONFIG)) as WebViewConfiguration;
  }

  private isValidRawConfig(rawConfig: DynamicObject): boolean {
    return rawConfig !== null &&
           typeof rawConfig === 'object' &&
           Object.keys(rawConfig).includes('version') &&
           Object.keys(rawConfig).includes('webview');
  }

  private convertToTypedConfig(rawConfig: DynamicObject): WebViewConfiguration {
    const config: WebViewConfiguration = {
      version: rawConfig.version as string,
      metadata: this.convertMetadata(rawConfig.metadata as DynamicObject),
      webview: {
        basic: this.convertBasicConfig((rawConfig.webview as DynamicObject).basic as DynamicObject),
        network: this.convertNetworkConfig((rawConfig.webview as DynamicObject).network as DynamicObject),
        cache: this.convertCacheConfig((rawConfig.webview as DynamicObject).cache as DynamicObject)
      },
      extensions: this.convertExtensionsConfig(rawConfig.extensions as DynamicObject[])
    };

    return config;
  }

  private convertMetadata(raw: DynamicObject): ConfigurationMetadata {
    return {
      name: (raw?.name as string) ?? 'Unknown',
      description: (raw?.description as string) ?? '',
      author: (raw?.author as string) ?? 'Unknown',
      created: (raw?.created as string) ?? TimeUtils.toISOString(Date.now()),
      updated: (raw?.updated as string) ?? TimeUtils.toISOString(Date.now())
    };
  }

  private convertBasicConfig(raw: DynamicObject): WebViewBasicConfig {
    const defaultConfig = WebViewConfigurationParser.DEFAULT_CONFIG.webview.basic;
    return {
      javaScriptAccess: (raw?.javaScriptAccess as boolean) ?? defaultConfig.javaScriptAccess,
      domStorageAccess: (raw?.domStorageAccess as boolean) ?? defaultConfig.domStorageAccess,
      fileAccess: (raw?.fileAccess as boolean) ?? defaultConfig.fileAccess,
      imageAccess: (raw?.imageAccess as boolean) ?? defaultConfig.imageAccess,
      userAgent: (raw?.userAgent as string) ?? defaultConfig.userAgent,
      allowUniversalAccessFromFileURLs: (raw?.allowUniversalAccessFromFileURLs as boolean) ?? defaultConfig.allowUniversalAccessFromFileURLs,
      allowFileAccessFromFileURLs: (raw?.allowFileAccessFromFileURLs as boolean) ?? defaultConfig.allowFileAccessFromFileURLs
    };
  }

  private convertNetworkConfig(raw: DynamicObject): WebViewNetworkConfig {
    const defaultConfig = WebViewConfigurationParser.DEFAULT_CONFIG.webview.network;
    return {
      timeout: (raw?.timeout as number) ?? defaultConfig.timeout,
      retryCount: (raw?.retryCount as number) ?? defaultConfig.retryCount,
      maxConcurrentRequests: (raw?.maxConcurrentRequests as number) ?? defaultConfig.maxConcurrentRequests,
      enableCompression: (raw?.enableCompression as boolean) ?? defaultConfig.enableCompression,
      followRedirects: (raw?.followRedirects as boolean) ?? defaultConfig.followRedirects
    };
  }

  private convertCacheConfig(raw: DynamicObject): WebViewCacheConfig {
    const defaultConfig = WebViewConfigurationParser.DEFAULT_CONFIG.webview.cache;
    return {
      enabled: (raw?.enabled as boolean) ?? defaultConfig.enabled,
      maxSize: (raw?.maxSize as number) ?? defaultConfig.maxSize,
      maxAge: (raw?.maxAge as number) ?? defaultConfig.maxAge,
      strategy: (raw?.strategy as 'memory-first' | 'disk-first' | 'network-first') ?? defaultConfig.strategy
    };
  }

  private convertExtensionsConfig(raw: DynamicObject[]): WebViewExtensionConfig[] {
    if (!Array.isArray(raw)) {
      return [];
    }

    return raw.map(item => {
      const extensionConfig: WebViewExtensionConfig = {
        name: item.name as string,
        type: item.type as 'native',
        path: item.path as string,
        enabled: item.enabled as boolean,
        config: (item.config as Record<string, DynamicObject>) ?? {}
      };
      return extensionConfig;
    });
  }

  private validateBasicConfig(config: WebViewBasicConfig, errors: ValidationError[], warnings: ValidationWarning[]): void {
    if (typeof config.javaScriptAccess !== 'boolean') {
      errors.push({
        field: 'webview.basic.javaScriptAccess',
        message: 'javaScriptAccess必须是布尔值',
        code: ConfigurationErrorCode.INVALID_FIELD_TYPE
      });
    }

    if (typeof config.userAgent !== 'string' || config.userAgent.length === 0) {
      errors.push({
        field: 'webview.basic.userAgent',
        message: 'userAgent必须是非空字符串',
        code: ConfigurationErrorCode.INVALID_FIELD_VALUE
      });
    }

    if (config.fileAccess && config.allowUniversalAccessFromFileURLs) {
      warnings.push({
        field: 'webview.basic',
        message: '同时启用fileAccess和allowUniversalAccessFromFileURLs可能存在安全风险',
        suggestion: '建议仅在必要时启用文件访问权限'
      });
    }
  }

  private validateNetworkConfig(config: WebViewNetworkConfig, errors: ValidationError[], warnings: ValidationWarning[]): void {
    if (config.timeout <= 0) {
      errors.push({
        field: 'webview.network.timeout',
        message: 'timeout必须大于0',
        code: ConfigurationErrorCode.INVALID_FIELD_VALUE
      });
    }

    if (config.retryCount < 0) {
      errors.push({
        field: 'webview.network.retryCount',
        message: 'retryCount不能小于0',
        code: ConfigurationErrorCode.INVALID_FIELD_VALUE
      });
    }

    if (config.maxConcurrentRequests <= 0) {
      errors.push({
        field: 'webview.network.maxConcurrentRequests',
        message: 'maxConcurrentRequests必须大于0',
        code: ConfigurationErrorCode.INVALID_FIELD_VALUE
      });
    }

    if (config.maxConcurrentRequests > 20) {
      warnings.push({
        field: 'webview.network.maxConcurrentRequests',
        message: '并发请求数过高可能影响性能',
        suggestion: '建议将并发请求数控制在20以内'
      });
    }
  }

  private validateCacheConfig(config: WebViewCacheConfig, errors: ValidationError[], warnings: ValidationWarning[]): void {
    if (config.maxSize <= 0) {
      errors.push({
        field: 'webview.cache.maxSize',
        message: 'maxSize必须大于0',
        code: ConfigurationErrorCode.INVALID_FIELD_VALUE
      });
    }

    if (config.maxAge <= 0) {
      errors.push({
        field: 'webview.cache.maxAge',
        message: 'maxAge必须大于0',
        code: ConfigurationErrorCode.INVALID_FIELD_VALUE
      });
    }

    const validStrategies = ['memory-first', 'disk-first', 'network-first'];
    if (!validStrategies.includes(config.strategy)) {
      errors.push({
        field: 'webview.cache.strategy',
        message: `无效的缓存策略: ${config.strategy}`,
        code: ConfigurationErrorCode.INVALID_FIELD_VALUE
      });
    }

    if (config.maxSize > 1073741824) { // 1GB
      warnings.push({
        field: 'webview.cache.maxSize',
        message: '缓存大小过大可能占用过多存储空间',
        suggestion: '建议将缓存大小控制在1GB以内'
      });
    }
  }

  private validateExtensionsConfig(extensions: WebViewExtensionConfig[], errors: ValidationError[], warnings: ValidationWarning[]): void {
    const extensionNames = new Set<string>();

    extensions.forEach((extension, index) => {
      const fieldPrefix = `extensions[${index}]`;

      if (!extension.name || extension.name.length === 0) {
        errors.push({
          field: `${fieldPrefix}.name`,
          message: '扩展名称不能为空',
          code: ConfigurationErrorCode.MISSING_REQUIRED_FIELD
        });
      }

      if (extensionNames.has(extension.name)) {
        errors.push({
          field: `${fieldPrefix}.name`,
          message: `重复的扩展名称: ${extension.name}`,
          code: ConfigurationErrorCode.INVALID_FIELD_VALUE
        });
      }

      extensionNames.add(extension.name);

      const validTypes = ['native'];
      if (!validTypes.includes(extension.type)) {
        errors.push({
          field: `${fieldPrefix}.type`,
          message: `无效的扩展类型: ${extension.type}`,
          code: ConfigurationErrorCode.INVALID_FIELD_VALUE
        });
      }

      if (!extension.path || extension.path.length === 0) {
        errors.push({
          field: `${fieldPrefix}.path`,
          message: '扩展路径不能为空',
          code: ConfigurationErrorCode.MISSING_REQUIRED_FIELD
        });
      }
    });
  }
}

// 定义默认安全策略配置对象接口
interface DefaultSecurityPolicyConfiguration {
  version: string;
  metadata: ConfigurationMetadata;
  security: SecurityPolicyConfig;
}

// 安全策略配置解析器
export class SecurityPolicyConfigurationParser implements ConfigurationParser<SecurityPolicyConfiguration> {
  private static readonly SUPPORTED_VERSIONS = ['1.0.0'];
  private static readonly DEFAULT_CONFIG: DefaultSecurityPolicyConfiguration = {
    version: '1.0.0',
    metadata: {
      name: 'Default Security Policy',
      description: 'Default security policy configuration',
      author: 'System',
      created: TimeUtils.toISOString(Date.now()),
      updated: TimeUtils.toISOString(Date.now())
    },
    security: {
      csp: {
        enabled: false,
        policy: '',
        reportOnly: false
      },
      antiCrawler: {
        enabled: false,
        userAgents: [],
        rateLimit: {
          maxRequests: 100,
          timeWindow: 60000,
          blockDuration: 300000
        },
        headers: {}
      },
      domainControl: {
        whitelist: [],
        blacklist: []
      }
    }
  };

  parse(jsonContent: string): SecurityPolicyConfiguration | null {
    try {
      logger.debug(TAG, '开始解析安全策略配置文件');
      
      const rawConfig = JSON.parse(jsonContent) as DynamicObject;
      
      if (!this.isValidRawConfig(rawConfig)) {
        logger.error(TAG, '安全策略配置文件格式无效');
        return null;
      }

      const config = this.convertToTypedConfig(rawConfig);
      
      const validationResult = this.validate(config);
      if (!validationResult.isValid) {
        const errorMessage = validationResult.errors.map(e => e.message).join(', ');
        logger.error(TAG, '安全策略配置验证失败: ' + errorMessage);
        return null;
      }

      logger.info(TAG, '安全策略配置解析成功');
      return config;
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error(TAG, '解析安全策略配置时发生错误: ' + errorMessage);
      return null;
    }
  }

  validate(config: SecurityPolicyConfiguration): ValidationResult {
    const errors: ValidationError[] = [];
    const warnings: ValidationWarning[] = [];

    if (!SecurityPolicyConfigurationParser.SUPPORTED_VERSIONS.includes(config.version)) {
      errors.push({
        field: 'version',
        message: `不支持的版本: ${config.version}`,
        code: ConfigurationErrorCode.UNSUPPORTED_VERSION
      });
    }

    // 验证CSP配置
    if (config.security.csp.enabled && !config.security.csp.policy) {
      errors.push({
        field: 'security.csp.policy',
        message: '启用CSP时必须提供策略内容',
        code: ConfigurationErrorCode.MISSING_REQUIRED_FIELD
      });
    }

    // 验证反爬虫配置
    if (config.security.antiCrawler.enabled) {
      if (config.security.antiCrawler.userAgents.length === 0) {
        const warningItem: ValidationWarning = {
          field: 'security.antiCrawler.userAgents',
          message: '未配置User-Agent列表',
          suggestion: '建议配置多个User-Agent以提高反爬虫效果'
        };
        warnings.push(warningItem);
      }

      if (config.security.antiCrawler.rateLimit.maxRequests <= 0) {
        errors.push({
          field: 'security.antiCrawler.rateLimit.maxRequests',
          message: '最大请求数必须大于0',
          code: ConfigurationErrorCode.INVALID_FIELD_VALUE
        });
      }
    }

    return {
      isValid: errors.length === 0,
      errors,
      warnings
    };
  }

  merge(base: SecurityPolicyConfiguration, override: SecurityPolicyConfiguration): SecurityPolicyConfiguration {
    const mergedMetadata: ConfigurationMetadata = {
      name: override.metadata.name || base.metadata.name,
      description: override.metadata.description || base.metadata.description,
      author: override.metadata.author || base.metadata.author,
      created: override.metadata.created || base.metadata.created,
      updated: override.metadata.updated || base.metadata.updated
    };

    const mergedCSP: CSPConfig = {
      enabled: override.security.csp.enabled !== undefined ? override.security.csp.enabled : base.security.csp.enabled,
      policy: override.security.csp.policy || base.security.csp.policy,
      reportOnly: override.security.csp.reportOnly !== undefined ? override.security.csp.reportOnly : base.security.csp.reportOnly
    };

    const mergedRateLimit: RateLimitConfig = {
      maxRequests: override.security.antiCrawler.rateLimit.maxRequests || base.security.antiCrawler.rateLimit.maxRequests,
      timeWindow: override.security.antiCrawler.rateLimit.timeWindow || base.security.antiCrawler.rateLimit.timeWindow,
      blockDuration: override.security.antiCrawler.rateLimit.blockDuration || base.security.antiCrawler.rateLimit.blockDuration
    };

    const mergedAntiCrawler: SecurityAntiCrawlerConfig = {
      enabled: override.security.antiCrawler.enabled !== undefined ? override.security.antiCrawler.enabled : base.security.antiCrawler.enabled,
      userAgents: override.security.antiCrawler.userAgents.length > 0 ? override.security.antiCrawler.userAgents : base.security.antiCrawler.userAgents,
      rateLimit: mergedRateLimit,
      headers: this.mergeHeaders(base.security.antiCrawler.headers, override.security.antiCrawler.headers)
    };

    const mergedDomainControl: DomainControlConfig = {
      whitelist: override.security.domainControl.whitelist.length > 0 ? override.security.domainControl.whitelist : base.security.domainControl.whitelist,
      blacklist: override.security.domainControl.blacklist.length > 0 ? override.security.domainControl.blacklist : base.security.domainControl.blacklist
    };

    const mergedSecurity: SecurityPolicyConfig = {
      csp: mergedCSP,
      antiCrawler: mergedAntiCrawler,
      domainControl: mergedDomainControl
    };

    return {
      version: override.version || base.version,
      metadata: mergedMetadata,
      security: mergedSecurity
    };
  }

  serialize(config: SecurityPolicyConfiguration): string {
    return JSON.stringify(config, null, 2);
  }

  private mergeHeaders(base: Record<string, string>, override: Record<string, string>): Record<string, string> {
    const merged: Record<string, string> = {};
    
    // 复制基础配置
    const baseKeys = Object.keys(base);
    for (let i = 0; i < baseKeys.length; i++) {
      const key = baseKeys[i];
      merged[key] = base[key];
    }
    
    // 覆盖配置
    const overrideKeys = Object.keys(override);
    for (let i = 0; i < overrideKeys.length; i++) {
      const key = overrideKeys[i];
      merged[key] = override[key];
    }
    
    return merged;
  }

  private isValidRawConfig(rawConfig: DynamicObject): boolean {
    return rawConfig !== null &&
           typeof rawConfig === 'object' &&
           Object.keys(rawConfig).includes('version') &&
           Object.keys(rawConfig).includes('security');
  }

  private convertToTypedConfig(rawConfig: DynamicObject): SecurityPolicyConfiguration {
    const securityRaw = rawConfig.security as DynamicObject;
    
    const metadata: ConfigurationMetadata = {
      name: (rawConfig.metadata as DynamicObject)?.name as string ?? 'Security Policy',
      description: (rawConfig.metadata as DynamicObject)?.description as string ?? '',
      author: (rawConfig.metadata as DynamicObject)?.author as string ?? 'System',
      created: (rawConfig.metadata as DynamicObject)?.created as string ?? TimeUtils.toISOString(Date.now()),
      updated: (rawConfig.metadata as DynamicObject)?.updated as string ?? TimeUtils.toISOString(Date.now())
    };

    const csp: CSPConfig = {
      enabled: (securityRaw.csp as DynamicObject)?.enabled as boolean ?? false,
      policy: (securityRaw.csp as DynamicObject)?.policy as string ?? '',
      reportOnly: (securityRaw.csp as DynamicObject)?.reportOnly as boolean ?? false
    };

    const rateLimit: RateLimitConfig = {
      maxRequests: ((securityRaw.antiCrawler as DynamicObject)?.rateLimit as DynamicObject)?.maxRequests as number ?? 100,
      timeWindow: ((securityRaw.antiCrawler as DynamicObject)?.rateLimit as DynamicObject)?.timeWindow as number ?? 60000,
      blockDuration: ((securityRaw.antiCrawler as DynamicObject)?.rateLimit as DynamicObject)?.blockDuration as number ?? 300000
    };

    const antiCrawler: SecurityAntiCrawlerConfig = {
      enabled: (securityRaw.antiCrawler as DynamicObject)?.enabled as boolean ?? false,
      userAgents: (securityRaw.antiCrawler as DynamicObject)?.userAgents as string[] ?? [],
      rateLimit: rateLimit,
      headers: (securityRaw.antiCrawler as DynamicObject)?.headers as Record<string, string> ?? {}
    };

    const domainControl: DomainControlConfig = {
      whitelist: (securityRaw.domainControl as DynamicObject)?.whitelist as string[] ?? [],
      blacklist: (securityRaw.domainControl as DynamicObject)?.blacklist as string[] ?? []
    };

    const security: SecurityPolicyConfig = {
      csp: csp,
      antiCrawler: antiCrawler,
      domainControl: domainControl
    };

    return {
      version: rawConfig.version as string,
      metadata: metadata,
      security: security
    };
  }
}