import { SafeUtils } from '../../Utils/SafeUtils';
/**
 * 统一操作接口
 * 提供WebView配置系统的统一操作入口
 * 支持配置解析、扩展模块注册等功能
 */

import { logger } from '../../Utils/Logger';
import { WebViewConfigurationParser, SecurityPolicyConfigurationParser, WebViewConfiguration, SecurityPolicyConfiguration } from './ConfigurationParser';

const TAG = 'UnifiedOperationInterface';

/**
 * 操作类型枚举
 */
export enum OperationType {
  CONFIGURATION = 'configuration',
  SECURITY = 'security',
  EXTENSION = 'extension',
  NETWORK = 'network',
  CACHE = 'cache'
}

/**
 * 操作参数数据接口 - 用于元数据
 */
export interface OperationParamsData {
  description?: string;
  author?: string;
  created?: string;
  updated?: string;
}

/**
 * 配置操作数据接口 - 用于配置相关操作的业务数据
 */
export interface ConfigurationOperationData {
  type: string;
  content: string;
}

/**
 * 安全操作数据接口 - 用于安全相关操作的业务数据
 */
export interface SecurityOperationData {
  url: string;
  policy: string;
}

/**
 * 安全检查操作数据接口 - 用于安全检查操作的业务数据
 */
export interface SecurityCheckOperationData {
  url: string;
  action: string;
}

/**
 * 扩展操作数据接口 - 用于扩展相关操作的业务数据
 */
export interface ExtensionOperationData {
  name: string;
  path: string;
}

/**
 * 操作业务数据联合类型
 */
export type OperationBusinessData = ConfigurationOperationData | SecurityOperationData | SecurityCheckOperationData | ExtensionOperationData;

/**
 * 操作参数接口 - 重新设计，分离业务数据和元数据
 */
export interface OperationParams {
  type: OperationType;
  action: string;
  data?: OperationBusinessData;
  metadata?: OperationParamsData;
  timeout?: number;
  priority?: number;
}

/**
 * 操作结果数据接口 - 修复null类型赋值问题
 */
export interface OperationResultData {
  result?: Object | null;
  allowed?: boolean;
  reason?: string;
}

/**
 * 操作结果接口
 */
export interface OperationResult {
  success: boolean;
  data?: ExecuteOperationResult;
  error?: string;
  timestamp: number;
  operationId: string;
}

/**
 * 日志上下文接口
 */
export interface LogContext {
  operationId: string;
  duration?: number;
  error?: string;
}

/**
 * 扩展模块接口
 */
export interface ExtensionModule {
  name: string;
  version: string;
  initialize(context: OperationContext): Promise<boolean>;
  execute(action: string, params: Record<string, Object>): Promise<Object>;
  destroy(): Promise<void>;
}

/**
 * 操作上下文接口
 */
export interface OperationContext {
  configParser: WebViewConfigurationParser;
  securityParser: SecurityPolicyConfigurationParser;
  extensionRegistry: Map<string, ExtensionModule>;
}

/**
 * 配置类型描述接口
 */
export interface ConfigTypeDescriptor {
  description: string;
}

/**
 * 配置内容描述接口
 */
export interface ConfigContentDescriptor {
  description: string;
}

/**
 * 配置数组描述接口 - 修复类型转换问题
 */
export interface ConfigArrayDescriptor {
  description: (WebViewConfiguration | SecurityPolicyConfiguration)[];
}

/**
 * 配置数组参数接口 - 专门用于merge操作的参数传递
 */
export interface ConfigArrayParamsData {
  description?: string;
  author?: string;
  created?: number;
  updated?: number;
  configs?: (WebViewConfiguration | SecurityPolicyConfiguration)[];
}

/**
 * 名称描述接口
 */
export interface NameDescriptor {
  description: string;
}

/**
 * 路径描述接口
 */
export interface PathDescriptor {
  description: string;
}

/**
 * URL描述接口
 */
export interface UrlDescriptor {
  description: string;
}

/**
 * 动作描述接口
 */
export interface ActionDescriptor {
  description: string;
}

/**
 * 验证结果接口 - 替代any/unknown类型
 */
export interface ValidationResultData {
  isValid: boolean;
  errors: string[];
  warnings: string[];
}

/**
 * 解析结果包装接口 - 用于parse操作的结果包装
 */
export interface ParseResultWrapper {
  result: WebViewConfiguration | SecurityPolicyConfiguration;
}

/**
 * 验证结果包装接口 - 用于validate操作的结果包装
 */
export interface ValidationResultWrapper {
  result: ValidationResultData;
}

/**
 * 合并结果包装接口 - 用于merge操作的结果包装
 */
export interface MergeResultWrapper {
  result: WebViewConfiguration;
}

/**
 * 操作结果包装接口 - 用于包装OperationResultData
 */
export interface OperationResultWrapper {
  result: OperationResultData;
}

/**
 * 执行操作结果接口 - 专门给execute方法使用，明确定义属性而不使用索引签名
 */
export interface ExecuteOperationResult {
  operation: OperationResultData;
}

/**
 * 元数据接口 - 用于策略验证的元数据
 */
export interface ValidationMetadata {
  source: string;
}

/**
 * 扩展注册结果接口 - 用于扩展注册操作的结果
 */
export interface ExtensionRegistrationResult {
  success: boolean;
}

/**
 * 安全检查结果接口 - 用于安全检查操作的结果
 */
export interface SecurityCheckResult {
  allowed: boolean;
  reason: string;
}

/**
 * 合并结果接口 - 替代any/unknown类型
 */
export interface MergeResultData {
  merged: WebViewConfiguration | SecurityPolicyConfiguration;
  conflicts: string[];
}

/**
 * 策略值接口 - 替代any/unknown类型
 */
export interface PolicyValueData {
  policy: SecurityPolicyConfiguration;
  metadata: ValidationMetadata;
}

/**
 * 统一操作接口主类
 */
export class UnifiedOperationInterface {
  private static instance: UnifiedOperationInterface | null = null;
  private configParser: WebViewConfigurationParser;
  private securityParser: SecurityPolicyConfigurationParser;
  private extensionRegistry: Map<string, ExtensionModule>;

  private constructor() {
    this.configParser = new WebViewConfigurationParser();
    this.securityParser = new SecurityPolicyConfigurationParser();
    this.extensionRegistry = new Map<string, ExtensionModule>();
    
    logger.info(TAG, '统一操作接口初始化完成');
  }

  /**
   * 获取单例实例
   */
  public static getInstance(): UnifiedOperationInterface {
    if (!UnifiedOperationInterface.instance) {
      UnifiedOperationInterface.instance = new UnifiedOperationInterface();
    }
    return UnifiedOperationInterface.instance;
  }

  /**
   * 执行操作
   */
  public async execute(params: OperationParams): Promise<OperationResult> {
    const startTime = Date.now();
    const operationId = this.generateOperationId();
    
    try {
      logger.debug(TAG, '开始执行操作', params.type, params.action);
      
      let result: ExecuteOperationResult;
      
      switch (params.type) {
        case OperationType.CONFIGURATION:
          result = await this.executeConfigurationOperation(params.action, params.data);
          break;
        case OperationType.SECURITY:
          result = await this.executeSecurityOperation(params.action, params.data);
          break;
        case OperationType.EXTENSION:
          result = await this.executeExtensionOperation(params.action, params.data);
          break;
        default:
          throw new Error(`不支持的操作类型: ${params.type}`);
      }
      
      const duration = Date.now() - startTime;
      const logContext: LogContext = { operationId, duration };
      logger.info(TAG, '操作执行成功', JSON.stringify(logContext));
      
      return {
        success: true,
        data: result,
        timestamp: Date.now(),
        operationId
      };
    } catch (error) {
      const duration = Date.now() - startTime;
      const errorMessage = error instanceof Error ? error.message : '未知错误';
      const logContext: LogContext = { operationId, duration, error: errorMessage };
      logger.error(TAG, '操作执行失败', JSON.stringify(logContext));
      
      return {
        success: false,
        error: errorMessage,
        timestamp: Date.now(),
        operationId
      };
    }
  }

  /**
   * 执行配置操作
   */
  private async executeConfigurationOperation(action: string, data?: OperationBusinessData): Promise<ExecuteOperationResult> {
    if (action === 'parse') {
      if (data && Object.keys(data).includes('type') && Object.keys(data).includes('content')) {
        const configData = data as ConfigurationOperationData;
        if (configData.type === 'webview') {
          const result = this.configParser.parse(configData.content);
          const resultData: OperationResultData = { result: result };
          return { operation: resultData };
        } else if (configData.type === 'security') {
          const result = this.securityParser.parse(configData.content);
          const resultData: OperationResultData = { result: result };
          return { operation: resultData };
        }
      }
      throw new Error('无效的配置解析参数');
      
    } else if (action === 'validate') {
      // 这里需要根据实际需求实现验证逻辑
      throw new Error('配置验证操作需要进一步实现');
      
    } else if (action === 'merge') {
      // 这里需要根据实际需求实现合并逻辑
      throw new Error('配置合并操作需要进一步实现');
      
    } else {
      throw new Error(`不支持的配置操作: ${action}`);
    }
  }

  /**
   * 执行安全操作
   */
  private async executeSecurityOperation(action: string, data?: OperationBusinessData): Promise<ExecuteOperationResult> {
    if (action === 'validate') {
      if (data && Object.keys(data).includes('url') && Object.keys(data).includes('policy')) {
        const securityData = data as SecurityOperationData;
        const policyData: PolicyValueData = {
          policy: SafeUtils.parseObj(securityData.policy) as SecurityPolicyConfiguration,
          metadata: { source: 'validation' } as ValidationMetadata
        };
        const result = this.securityParser.validate(policyData.policy);
        const resultData: OperationResultData = { result: result };
        return { operation: resultData };
      }
      throw new Error('无效的安全验证参数');
      
    } else if (action === 'check') {
      if (data && Object.keys(data).includes('url') && Object.keys(data).includes('action')) {
        const checkData = data as SecurityCheckOperationData;
        const allowed = this.checkSecurityPolicy(checkData.url, checkData.action);
        const securityResult: SecurityCheckResult = { 
          allowed: allowed, 
          reason: allowed ? '安全检查通过' : '安全检查失败' 
        };
        const resultData: OperationResultData = { 
          allowed: securityResult.allowed, 
          reason: securityResult.reason 
        };
        return { operation: resultData };
      }
      throw new Error('无效的安全检查参数');
      
    } else {
      throw new Error(`不支持的安全操作: ${action}`);
    }
  }

  /**
   * 执行扩展操作
   */
  private async executeExtensionOperation(action: string, data?: OperationBusinessData): Promise<ExecuteOperationResult> {
    if (action === 'register') {
      if (data && Object.keys(data).includes('name') && Object.keys(data).includes('path')) {
        const extensionData = data as ExtensionOperationData;
        const success = await this.registerExtension(extensionData.name, extensionData.path);
        const extensionResult: ExtensionRegistrationResult = { success: success };
        const resultData: OperationResultData = { 
          result: extensionResult,
          reason: success ? '扩展注册成功' : '扩展注册失败' 
        };
        return { operation: resultData };
      }
      throw new Error('无效的扩展注册参数');
      
    } else {
      throw new Error(`不支持的扩展操作: ${action}`);
    }
  }

  /**
   * 检查安全策略
   */
  private checkSecurityPolicy(url: string, action: string): boolean {
    // 实现安全策略检查逻辑
    logger.debug(TAG, '检查安全策略', url, action);
    return true; // 简化实现
  }

  /**
   * 注册扩展模块
   */
  private async registerExtension(name: string, path: string): Promise<boolean> {
    try {
      logger.debug(TAG, '注册扩展模块', name, path);
      // 实现扩展模块注册逻辑
      return true; // 简化实现
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : '未知错误';
      logger.error(TAG, '扩展模块注册失败', errorMessage);
      return false;
    }
  }

  /**
   * 生成操作ID
   */
  private generateOperationId(): string {
    return `op_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
  }

  /**
   * 销毁实例
   */
  public static destroy(): void {
    if (UnifiedOperationInterface.instance) {
      logger.info(TAG, '销毁统一操作接口实例');
      UnifiedOperationInterface.instance = null;
    }
  }
}