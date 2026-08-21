// 文件路径: src/main/ets/GlobalContext.ts
/**
 * 全局上下文模块
 * 负责管理应用的全局上下文（UIAbilityContext），
 * 提供上下文设置、获取和自检功能。
 */
 
import { common } from '@kit.AbilityKit';
import { logger } from './Utils/Logger';

// 定义状态接口
interface GlobalContextStatus {
  initialized: boolean;
  selfCheckPassed: boolean;
  initializationTime: number;
  contextExists: boolean;
}

// 全局上下文状态管理
let _context: common.UIAbilityContext | null = null;
let _isInitialized: boolean = false;
let _initializationTime: number = 0;
let _selfCheckPassed: boolean = false;

/**
 * 执行GlobalContext自检
 * @returns 自检是否通过
 */
function performSelfCheck(): boolean {
  try {
    logger.startup('GlobalContext', '自检开始', '执行GlobalContext模块自检');
    
    // 检查1: 验证context是否存在且有效
    if (!_context) {
      logger.error('GlobalContext', '❌ 自检失败: context为null');
      return false;
    }
    
    // 检查2: 验证context类型
    if (typeof _context !== 'object') {
      logger.error('GlobalContext', `❌ 自检失败: context类型错误 - ${typeof _context}`);
      return false;
    }
    
    // 检查3: 验证关键属性是否存在
    if (!_context.resourceManager) {
      logger.error('GlobalContext', '❌ 自检失败: 缺少必要属性 - resourceManager');
      return false;
    }
    
    if (!_context.applicationInfo) {
      logger.error('GlobalContext', '❌ 自检失败: 缺少必要属性 - applicationInfo');
      return false;
    }
    
    logger.startup('GlobalContext', '自检通过', '所有检查项目均通过');
    return true;
  } catch (error) {
    logger.error('GlobalContext', `❌ 自检异常: ${error}`);
    return false;
  }
}

/**
 * 设置全局的应用上下文（UIAbilityContext）。
 * 此方法应在应用的MainAbility的onCreate生命周期中被调用一次。
 * @param context 从UIAbility实例中获取的上下文对象。
 */
export function setContext(context: common.UIAbilityContext): void {
  const startTime = Date.now();
  logger.startup('GlobalContext', '设置开始', `开始设置全局上下文`);
  
  try {
    // 防止重复设置
    if (_isInitialized) {
      logger.warn('GlobalContext', '⚠️ 重复设置警告', 'GlobalContext已经初始化，忽略重复设置');
      return;
    }
    
    // 参数验证
    if (!context) {
      const error = new Error('传入的context参数为null或undefined');
      logger.error('GlobalContext', `❌ 设置失败: ${error.message}`);
      throw error;
    }
    
    // 设置上下文
    _context = context;
    _initializationTime = Date.now();
    
    // 执行自检
    _selfCheckPassed = performSelfCheck();
    
    if (_selfCheckPassed) {
      _isInitialized = true;
      const duration = Date.now() - startTime;
      logger.startup('GlobalContext', '设置成功', `GlobalContext初始化完成，耗时${duration}ms`);
      logger.performance('GlobalContext', 'initialization_time', duration, 'ms');
    } else {
      _context = null;
      const error = new Error('GlobalContext自检失败，设置被回滚');
      logger.error('GlobalContext', `❌ 设置失败: ${error.message}`);
      throw error;
    }
  } catch (error) {
      _context = null;
      _isInitialized = false;
      _selfCheckPassed = false;
      // 按照项目规则处理error类型
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error('GlobalContext', `❌ 设置异常: ${errorMessage}`);
      throw new Error(errorMessage);
    }
}

/**
 * 获取已设置的全局应用上下文。
 * 在应用的任何地方都可以调用此方法来获取上下文，以便访问资源管理器等系统能力。
 * @returns 返回已设置的UIAbilityContext实例。
 * @throws 如果setContext尚未被调用，则会抛出错误。
 */
export function getContext(): common.UIAbilityContext {
  logger.debug('GlobalContext', '获取请求', '组件请求获取GlobalContext');
  
  if (!_isInitialized || !_context || !_selfCheckPassed) {
    const errorDetails: GlobalContextStatus = {
      initialized: _isInitialized,
      contextExists: !!_context,
      selfCheckPassed: _selfCheckPassed,
      initializationTime: _initializationTime
    };
    
    const error = new Error(`GlobalContext未正确初始化。详情: ${JSON.stringify(errorDetails)}`);
    logger.error('GlobalContext', `❌ 获取失败: ${error.message}`);
    throw error;
  }
  
  logger.debug('GlobalContext', '获取成功', '成功返回GlobalContext实例');
  return _context;
}

/**
 * 检查GlobalContext是否已初始化
 * @returns 是否已初始化
 */
export function isInitialized(): boolean {
  return _isInitialized && _selfCheckPassed && !!_context;
}

/**
 * 获取GlobalContext状态信息
 * @returns 状态信息对象
 */
export function getStatus(): GlobalContextStatus {
  return {
    initialized: _isInitialized,
    selfCheckPassed: _selfCheckPassed,
    initializationTime: _initializationTime,
    contextExists: !!_context
  };
}

/**
 * 等待GlobalContext初始化完成
 * @param maxWaitTime 最大等待时间（毫秒）
 * @param checkInterval 检查间隔（毫秒）
 * @returns Promise，初始化完成时resolve
 */
export function waitForInitialization(maxWaitTime: number = 10000, checkInterval: number = 50): Promise<void> {
  return new Promise((resolve, reject) => {
    const startTime = Date.now();
    logger.startup('GlobalContext', '等待初始化', `开始等待GlobalContext初始化，最大等待${maxWaitTime}ms`);
    
    const checkInitialization = (): void => {
      const waitedTime = Date.now() - startTime;
      
      if (isInitialized()) {
        logger.startup('GlobalContext', '等待完成', `GlobalContext初始化完成，等待时间${waitedTime}ms`);
        resolve();
        return;
      }
      
      if (waitedTime >= maxWaitTime) {
        const status = getStatus();
        const error = new Error(`等待GlobalContext初始化超时: ${maxWaitTime}ms，状态: ${JSON.stringify(status)}`);
        logger.error('GlobalContext', `❌ 等待超时: ${error.message}`);
        reject(error);
        return;
      }
      
      logger.debug('GlobalContext', '等待中', `等待GlobalContext初始化... (${waitedTime}ms)`);
      setTimeout(checkInitialization, checkInterval);
    };
    
    checkInitialization();
  });
}
