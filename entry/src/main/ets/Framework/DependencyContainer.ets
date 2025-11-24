import { logger } from '../Utils/Logger';
import { eventBus, GameEvent } from './EventBus';
import { ErrorHandler, GameError, ErrorSeverity, ErrorCategory } from './Core/ErrorHandler';


/**
 * 依赖注入容器的生命周期
 */
export enum ContainerLifecycle {
  SINGLETON = 'singleton',
  TRANSIENT = 'transient',
  SCOPED = 'scoped'
}

/**
 * 依赖描述符
 */
export interface DependencyDescriptor<T = object> {
  token: string;
  factory: () => T | Promise<T>;
  lifecycle: ContainerLifecycle;
  dependencies?: string[];
  initialized?: boolean;
}

/**
 * 依赖解析上下文
 */
export interface ResolutionContext {
  resolving: Set<string>;
  resolved: Map<string, object>;
  scope?: string;
}

/**
 * 依赖注入容器
 */
interface InjectableDependency {
  injectDependencies: (deps: Map<string, object>) => void;
}

interface Disposable {
  dispose?: () => void;
}

interface ValidationResult {
  valid: boolean;
  errors: string[];
}

interface RequiredDisposable {
  dispose: () => void;
}

export class DependencyContainer {
  private static instance: DependencyContainer;
  private dependencies = new Map<string, DependencyDescriptor>();
  private singletons = new Map<string, object>();
  private scoped = new Map<string, Map<string, object>>();
  private currentScope?: string;
  private errorHandler: ErrorHandler | undefined = undefined;

  private constructor() {
    // 延迟初始化ErrorHandler，避免循环依赖
    try {
      this.errorHandler = ErrorHandler.getInstance();
      logger.debug('DI', 'DependencyContainer构造函数：ErrorHandler初始化成功');
    } catch (error) {
      // 如果ErrorHandler初始化失败，记录错误但不阻止DependencyContainer的创建
      logger.warn('DI', `DependencyContainer构造函数：ErrorHandler初始化失败，将使用基础错误处理 - ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  public static getInstance(): DependencyContainer {
    if (!DependencyContainer.instance) {
      try {
        DependencyContainer.instance = new DependencyContainer();
        logger.info('DI', 'DependencyContainer单例实例创建成功，开始初始化核心组件');
      } catch (error) {
        logger.error('DI', `DependencyContainer实例创建失败，尝试创建最小化实例 - ${error instanceof Error ? error.message : String(error)}`);
        // 即使ErrorHandler初始化失败，也要确保DependencyContainer能够创建
        // 创建一个最小化的实例，使用符合ArkTS规范的方式
        try {
          // 创建一个临时的DependencyContainer实例，手动初始化必要属性
          const tempInstance = new DependencyContainer();
          // 手动初始化核心属性，避免依赖ErrorHandler
          tempInstance.dependencies = new Map<string, DependencyDescriptor>();
          tempInstance.singletons = new Map<string, object>();
          tempInstance.scoped = new Map<string, Map<string, object>>();
          tempInstance.currentScope = undefined;
          tempInstance.errorHandler = undefined;
          
          DependencyContainer.instance = tempInstance;
          logger.info('DI', '创建了最小化的DependencyContainer实例，ErrorHandler不可用但核心功能正常');
        } catch (fallbackError) {
          logger.error('DI', `最小化实例创建也失败，使用最后备用方案 - ${fallbackError instanceof Error ? fallbackError.message : String(fallbackError)}`);
          // 最后的备用方案：直接调用构造函数，忽略所有错误
          DependencyContainer.instance = new DependencyContainer();
          // 重置errorHandler为undefined，避免后续错误
          if (DependencyContainer.instance.errorHandler !== undefined) {
            DependencyContainer.instance.errorHandler = undefined;
          }
        }
      }
    }
    
    // 记录最终返回的实例状态
    logger.info('DI', `getInstance方法完成，返回DependencyContainer实例 - ErrorHandler状态: ${DependencyContainer.instance.isErrorHandlerAvailable() ? '可用' : '不可用'}, Dependencies Map状态: ${DependencyContainer.instance.dependencies ? '已初始化' : '未初始化'}`);
    return DependencyContainer.instance;
  }

  /**
   * 注册依赖
   */
  public register<T>(
    token: string,
    factory: () => T | Promise<T>,
    lifecycle: ContainerLifecycle = ContainerLifecycle.SINGLETON,
    dependencies: string[] = []
  ): void {
    try {
      // 确保dependencies Map已初始化（处理最小化实例的情况）
      if (!this.dependencies) {
        this.dependencies = new Map<string, DependencyDescriptor>();
        logger.info('DI', 'register方法：检测到dependencies Map未初始化，已重新创建');
      }
      
      // 验证输入参数
      if (!token || typeof token !== 'string') {
        throw new Error(`无效的token: ${token}`);
      }
      
      if (!factory || typeof factory !== 'function') {
        throw new Error(`无效的factory函数: ${typeof factory}`);
      }
      
      logger.debug('DI', `开始注册依赖: ${token}, 生命周期: ${lifecycle}, 依赖项数量: ${dependencies.length}`);
      
      if (this.dependencies.has(token)) {
        logger.warn('DI', `依赖 ${token} 已存在，将被新注册覆盖 - 生命周期: ${lifecycle}`);
      }

      this.dependencies.set(token, {
        token,
        factory: factory as () => object | Promise<object>,
        lifecycle,
        dependencies,
        initialized: false
      });

      logger.info('DI', `依赖注册成功: ${token} (${lifecycle}) - 当前已注册依赖总数: ${this.dependencies.size}`);
      
      // 记录依赖项详情
      if (dependencies.length > 0) {
        logger.debug('DI', `依赖 ${token} 的依赖项: [${dependencies.join(', ')}]`);
      }
    } catch (error) {
      const errorMessage = `注册依赖失败: ${token} - ${error instanceof Error ? error.message : String(error)}`;
      logger.error('DI', `${errorMessage}, 生命周期: ${lifecycle}, 依赖项: [${dependencies.join(', ')}]`);
      
      // 尝试使用ErrorHandler，如果失败则直接抛出异常
      try {
        this.handleError(new GameError(
          errorMessage,
          ErrorSeverity.HIGH,
          ErrorCategory.SYSTEM,
          { 
            component: 'DependencyContainer',
            method: 'register',
            additionalData: {
              "token": token,
              "lifecycle": lifecycle,
              "dependenciesCount": dependencies.length.toString(),
              "errorType": error instanceof Error ? error.constructor.name : 'Unknown'
            }
          },
          'REGISTER_DEPENDENCY_FAILED'
        ));
      } catch (handlerError) {
        logger.error('[DI] ErrorHandler也失败了:', handlerError);
      }
      
      // 重新抛出原始错误，确保调用者知道注册失败
      throw new Error(errorMessage);
    }
  }

  /**
   * 解析依赖
   */
  public async resolve<T>(token: string, scope?: string): Promise<T> {
    // 确保dependencies Map已初始化
    if (!this.dependencies) {
      this.dependencies = new Map<string, DependencyDescriptor>();
      logger.warn('DI', `resolve方法：检测到dependencies Map未初始化，已重新创建 - 请求解析的token: ${token}`);
    }
    
    const context: ResolutionContext = {
      resolving: new Set(),
      resolved: new Map(),
      scope
    };

    try {
      const result = await this.resolveInternal<T>(token, context);
      eventBus.emit(GameEvent.DEPENDENCY_RESOLVED, { token, scope });
      return result;
    } catch (error) {
      this.handleError(new GameError(
        `解析依赖失败: ${token}`,
        ErrorSeverity.HIGH,
        ErrorCategory.SYSTEM,
        {
          component: 'DependencyContainer',
          method: 'resolve',
          additionalData: {
            "token": token,
            "scope": scope || 'default'
          }
        },
        'RESOLVE_DEPENDENCY_FAILED'
      ));
      throw new Error(error instanceof Error ? error.message : String(error));
    }
  }

  /**
   * 内部解析逻辑
   */
  private async resolveInternal<T>(token: string, context: ResolutionContext): Promise<T> {
    // 检查循环依赖
    if (context.resolving.has(token)) {
      const circularError = new Error(`检测到循环依赖: ${Array.from(context.resolving).join(' -> ')} -> ${token}`);
      logger.error('DI', circularError.message);
      throw circularError;
    }

    // 检查是否已在当前上下文中解析
    if (context.resolved.has(token)) {
      return context.resolved.get(token) as T;
    }

    const descriptor = this.dependencies.get(token);
    if (!descriptor) {
      const notFoundError = new Error(`未找到依赖: ${token}`);
      logger.error('DI', notFoundError.message);
      throw notFoundError;
    }

    // 检查现有实例
    const existingInstance = this.getExistingInstance(token, context.scope);
    if (existingInstance !== undefined) {
      context.resolved.set(token, existingInstance);
      return existingInstance as T;
    }

    // 开始解析
    context.resolving.add(token);

    try {
      // 先解析依赖项
      const resolvedDependencies = await this.resolveDependencies(descriptor.dependencies || [], context);
      
      // 创建实例
      const instance = await descriptor.factory();
      
      // 注入依赖项（如果实例有相应的方法）
      if (instance && typeof instance === 'object' && typeof (instance as InjectableDependency).injectDependencies === 'function') {
        const injectableInstance = instance as InjectableDependency;
        injectableInstance.injectDependencies(resolvedDependencies);
      }

      // 存储实例
      this.storeInstance(token, instance, descriptor.lifecycle, context.scope);
      context.resolved.set(token, instance);
      
      descriptor.initialized = true;
      logger.info('DI', `解析依赖成功: ${token} (${descriptor.lifecycle}) - 实例类型: ${typeof instance}, 作用域: ${context.scope || 'default'}`);
      
      return instance as T;
    } finally {
      context.resolving.delete(token);
    }
  }

  /**
   * 解析依赖项列表
   */
  private async resolveDependencies(dependencies: string[], context: ResolutionContext): Promise<Map<string, object>> {
    const resolved = new Map<string, object>();
    
    for (const dep of dependencies) {
      const instance: object = await this.resolveInternal<object>(dep, context);
      resolved.set(dep, instance as object);
    }
    
    return resolved;
  }

  /**
   * 获取现有实例
   */
  private getExistingInstance(token: string, scope?: string): object | undefined {
    // 确保Maps已初始化
    if (!this.dependencies) {
      this.dependencies = new Map<string, DependencyDescriptor>();
    }
    if (!this.singletons) {
      this.singletons = new Map<string, object>();
    }
    if (!this.scoped) {
      this.scoped = new Map<string, Map<string, object>>();
    }
    
    const descriptor = this.dependencies.get(token);
    if (!descriptor) return undefined;

    switch (descriptor.lifecycle) {
      case ContainerLifecycle.SINGLETON:
        return this.singletons.get(token);
      
      case ContainerLifecycle.SCOPED:
        if (scope) {
          const scopedInstances = this.scoped.get(scope);
          return scopedInstances?.get(token);
        }
        return undefined;
      
      case ContainerLifecycle.TRANSIENT:
      default:
        return undefined;
    }
  }

  /**
   * 存储实例
   */
  private storeInstance(token: string, instance: object, lifecycle: ContainerLifecycle, scope?: string): void {
    // 确保Maps已初始化
    if (!this.singletons) {
      this.singletons = new Map<string, object>();
    }
    if (!this.scoped) {
      this.scoped = new Map<string, Map<string, object>>();
    }
    
    switch (lifecycle) {
      case ContainerLifecycle.SINGLETON:
        this.singletons.set(token, instance);
        break;
      
      case ContainerLifecycle.SCOPED:
        if (scope) {
          if (!this.scoped.has(scope)) {
            this.scoped.set(scope, new Map());
          }
          this.scoped.get(scope)!.set(token, instance);
        }
        break;
      
      case ContainerLifecycle.TRANSIENT:
      default:
        // 瞬态实例不存储
        break;
    }
  }

  /**
   * 创建作用域
   */
  public createScope(scopeId: string): void {
    if (!this.scoped.has(scopeId)) {
      this.scoped.set(scopeId, new Map());
      logger.debug('DI', `创建作用域: ${scopeId}`);
    }
  }

  /**
   * 销毁作用域
   */
  public destroyScope(scopeId: string): void {
    const scopedInstances = this.scoped.get(scopeId);
    if (scopedInstances) {
      // 清理作用域内的实例
      scopedInstances.forEach((instance: object, token: string) => {
        if (instance && typeof (instance as Disposable).dispose === 'function') {
          try {
            (instance as RequiredDisposable).dispose();
          } catch (error) {
            logger.warn('DI', `销毁实例失败: ${token} - ${error instanceof Error ? error.message : String(error)}`);
          }
        }
      },
      
      this.scoped.delete(scopeId));
      logger.debug('DI', `销毁作用域: ${scopeId}`);
    }
  }

  /**
   * 设置当前作用域
   */
  public setCurrentScope(scopeId?: string): void {
    this.currentScope = scopeId;
  }

  /**
   * 获取当前作用域
   */
  public getCurrentScope(): string | undefined {
    return this.currentScope;
  }

  /**
   * 检查依赖是否已注册
   */
  public isRegistered(token: string): boolean {
    if (!this.dependencies) {
      this.dependencies = new Map<string, DependencyDescriptor>();
    }
    return this.dependencies.has(token);
  }

  /**
   * 获取所有已注册的依赖
   */
  public getRegisteredDependencies(): string[] {
    if (!this.dependencies) {
      this.dependencies = new Map<string, DependencyDescriptor>();
    }
    return Array.from(this.dependencies.keys());
  }

  /**
   * 检查ErrorHandler是否可用
   */
  public isErrorHandlerAvailable(): boolean {
    return this.errorHandler !== undefined;
  }

  /**
   * 验证依赖图
   */
  public validateDependencyGraph(): ValidationResult {
    // 确保dependencies Map已初始化
    if (!this.dependencies) {
      this.dependencies = new Map<string, DependencyDescriptor>();
      logger.warn('DI', 'validateDependencyGraph方法：检测到dependencies Map未初始化，已重新创建');
    }
    
    const errors: string[] = [];
    const visited = new Set<string>();
    const visiting = new Set<string>();

    const validateNode = (token: string): boolean => {
      if (visiting.has(token)) {
        errors.push(`检测到循环依赖: ${token}`);
        return false;
      }
      
      if (visited.has(token)) {
        return true;
      }

      const descriptor = this.dependencies.get(token);
      if (!descriptor) {
        errors.push(`未找到依赖: ${token}`);
        return false;
      }

      visiting.add(token);
      
      for (const dep of descriptor.dependencies || []) {
        if (!validateNode(dep)) {
          return false;
        }
      }
      
      visiting.delete(token);
      visited.add(token);
      return true;
    };

    for (const token of this.dependencies.keys()) {
      if (!visited.has(token)) {
        validateNode(token);
      }
    }

    return {
      valid: errors.length === 0,
      errors
    };
  }

  /**
   * 清理容器
   */
  public dispose(): void {
    try {
      // 清理所有单例
      this.singletons.forEach((instance: object, token: string) => {
        if (instance && typeof (instance as Disposable).dispose === 'function') {
          try {
            (instance as RequiredDisposable).dispose();
          } catch (error) {
            logger.warn('DI', `销毁单例失败: ${token} - ${error instanceof Error ? error.message : String(error)}`);
          }
        }
      },
      )

      // 清理所有作用域
      for (const scopeId of this.scoped.keys()) {
        this.destroyScope(scopeId);
      }

      this.dependencies.clear();
      this.singletons.clear();
      this.scoped.clear();
      this.currentScope = undefined;
      
      logger.info('DI', `依赖容器清理完成 - 清理前状态: 依赖项${this.dependencies.size}个, 单例${this.singletons.size}个, 作用域${this.scoped.size}个`);
    } catch (error) {
      this.handleError(new GameError(
        '清理依赖容器失败',
        ErrorSeverity.MEDIUM,
        ErrorCategory.SYSTEM,
        {
          component: 'DependencyContainer',
          method: 'dispose'
        },
        'DISPOSE_CONTAINER_FAILED'
      ));
    }
  }

  /**
   * 处理错误
   */
  private handleError(error: GameError): void {
    if (this.errorHandler) {
      try {
        this.errorHandler.handleError(error);
      } catch (handlerError) {
        logger.error('DI', `ErrorHandler处理错误失败: ${handlerError instanceof Error ? handlerError.message : String(handlerError)}`);
        logger.error('DI', `原始错误详情: ${error.message}, 错误类别: ${error.category}, 严重程度: ${error.severity}`);
      }
    } else {
      // 如果ErrorHandler不可用，使用基础错误处理
      logger.error('DI', `依赖容器错误: ${error.message}, 错误类别: ${error.category}, 严重程度: ${error.severity}`);
      if (error.context?.additionalData) {
        logger.error('DI', `错误上下文详情: 组件=${error.context.component}, 方法=${error.context.method}, 附加数据=${JSON.stringify(error.context.additionalData)}`);
      }
    }
  }
}

/**
 * 可注入类的抽象工厂接口
 * 使用抽象工厂模式替代构造函数类型签名
 */
export interface InjectableFactory {
  create(...args: object[]): object;
}

/**
 * 可注入类的基础抽象类
 * 提供统一的实例创建接口
 */
export abstract class InjectableBase {
  abstract create(...args: object[]): object;
}

/**
 * 依赖注入装饰器工厂
 * 使用抽象工厂模式，避免构造函数类型签名
 */
export function Injectable(token: string, lifecycle: ContainerLifecycle = ContainerLifecycle.SINGLETON) {
  return <T extends InjectableFactory>(factory: T): T => {
    const container = DependencyContainer.getInstance();
    container.register(token, (): object => {
      // 使用工厂函数创建实例，避免直接使用构造函数
      return factory.create();
    }, lifecycle);
    return factory;
  };
}

/**
 * 依赖注入装饰器
 */
export function Inject(token: string) {
  return (target: object, propertyKey: string) => {
    // 这里可以实现属性注入逻辑
    // 由于HarmonyOS的限制，我们主要通过手动注入的方式
  };
}