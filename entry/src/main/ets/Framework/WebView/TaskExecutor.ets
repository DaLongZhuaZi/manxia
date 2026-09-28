import { SafeUtils } from 'manxia_core/src/main/ets/Utils/SafeUtils';
/**
 * 任务执行引擎
 * 负责执行任务定义中的步骤，支持顺序执行、并行执行和条件执行
 */

import { webview } from '@kit.ArkWeb';
import {
  TaskDefinition,
  TaskStep,
  TaskContext,
  TaskResult,
  TaskStatus,
  TaskExecutionMode,
  TaskError,
  Action
} from 'manxia_source_engine/src/main/ets/Framework/WebView/MangaSourceTypes';
import { MangaSourceActionEngine, ActionContext } from './MangaSourceActionEngine';
import { AntiCrawlerConfig } from 'manxia_source_engine/src/main/ets/Framework/WebView/MangaSourceTypes';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';

const TAG = 'TaskExecutor';

/**
 * 任务执行器配置
 */
export interface TaskExecutorConfig {
  webViewController: webview.WebviewController;
  antiCrawlerConfig?: AntiCrawlerConfig;
  debug?: boolean;
  defaultTimeout?: number;
}

/**
 * 步骤执行结果
 */
interface StepExecutionResult {
  success: boolean;
  data?: Object;
  error?: string;
}

/**
 * 任务执行器
 */
export class TaskExecutor {
  private config: TaskExecutorConfig;
  private actionEngine: MangaSourceActionEngine;
  private runningTasks: Map<string, TaskContext> = new Map();
  private taskDefinitions: Map<string, TaskDefinition> = new Map();
  private workflows: Map<string, Action[]> = new Map();

  constructor(config: TaskExecutorConfig) {
    this.config = config;
    this.actionEngine = new MangaSourceActionEngine(
      config.webViewController,
      config.antiCrawlerConfig || {} as AntiCrawlerConfig
    );
  }

  /**
   * 注册任务定义
   */
  registerTask(task: TaskDefinition): void {
    this.taskDefinitions.set(task.id, task);
    logger.debug(TAG, `注册任务: ${task.id} - ${task.name}`);
  }

  /**
   * 注册工作流
   */
  registerWorkflow(name: string, actions: Action[]): void {
    this.workflows.set(name, actions);
    logger.debug(TAG, `注册工作流: ${name}, 操作数: ${actions.length}`);
  }

  /**
   * 批量注册任务
   */
  registerTasks(tasks: Record<string, TaskDefinition>): void {
    const taskIds = Object.keys(tasks);
    for (let i = 0; i < taskIds.length; i++) {
      const taskId = taskIds[i];
      const task = tasks[taskId];
      if (task) {
        task.id = taskId;
        this.registerTask(task);
      }
    }
  }

  /**
   * 批量注册工作流
   */
  registerWorkflows(workflows: Record<string, Action[]>): void {
    const names = Object.keys(workflows);
    for (let i = 0; i < names.length; i++) {
      const name = names[i];
      const actions = workflows[name];
      if (actions) {
        this.registerWorkflow(name, actions);
      }
    }
  }

  /**
   * 执行任务
   */
  async executeTask(
    taskId: string,
    initialParams?: Record<string, Object | undefined>
  ): Promise<TaskResult> {
    const task = this.taskDefinitions.get(taskId);
    if (!task) {
      return {
        taskId,
        success: false,
        error: `任务未找到: ${taskId}`,
        duration: 0,
        stepResults: {}
      };
    }

    logger.info(TAG, `开始执行任务: ${task.name} (${taskId})`);
    const startTime = Date.now();

    // 创建任务上下文
    const variables: Record<string, Object | undefined> = {};
    if (initialParams) {
      const paramKeys = Object.keys(initialParams);
      for (let i = 0; i < paramKeys.length; i++) {
        const key = paramKeys[i];
        variables[key] = initialParams[key];
      }
    }
    
    const context: TaskContext = {
      taskId: taskId,
      currentStepIndex: 0,
      status: TaskStatus.RUNNING,
      variables: variables,
      stepResults: {},
      errors: [],
      startTime: startTime
    };

    // 合并初始参数
    if (task.initialParams) {
      const keys = Object.keys(task.initialParams);
      for (let i = 0; i < keys.length; i++) {
        const key = keys[i];
        if (context.variables[key] === undefined) {
          context.variables[key] = task.initialParams[key];
        }
      }
    }

    this.runningTasks.set(taskId, context);

    try {
      // 根据执行模式执行任务
      switch (task.mode) {
        case TaskExecutionMode.SEQUENTIAL:
          await this.executeSequential(task, context);
          break;
        case TaskExecutionMode.PARALLEL:
          await this.executeParallel(task, context);
          break;
        case TaskExecutionMode.CONDITIONAL:
          await this.executeConditional(task, context);
          break;
        default:
          await this.executeSequential(task, context);
      }

      context.status = TaskStatus.COMPLETED;
      context.endTime = Date.now();

      const result: TaskResult = {
        taskId,
        success: context.errors.length === 0,
        data: context.variables['result'] as Object | undefined,
        duration: context.endTime - context.startTime,
        stepResults: context.stepResults
      };

      if (context.errors.length > 0) {
        result.error = context.errors.map(e => e.message).join('; ');
      }

      logger.info(TAG, `任务完成: ${task.name}, 耗时: ${result.duration}ms, 成功: ${result.success}`);

      // 执行成功回调
      if (result.success && task.onSuccess) {
        await this.executeTask(task.onSuccess, context.variables);
      }

      return result;

    } catch (error) {
      context.status = TaskStatus.FAILED;
      context.endTime = Date.now();

      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `任务执行失败: ${task.name}, 错误: ${errorMessage}`);

      // 执行失败回调或回退任务
      if (task.onFailure) {
        await this.executeTask(task.onFailure, context.variables);
      } else if (task.fallbackTask) {
        return await this.executeTask(task.fallbackTask, initialParams);
      }

      return {
        taskId,
        success: false,
        error: errorMessage,
        duration: context.endTime - context.startTime,
        stepResults: context.stepResults
      };

    } finally {
      this.runningTasks.delete(taskId);
    }
  }

  /**
   * 顺序执行步骤
   */
  private async executeSequential(task: TaskDefinition, context: TaskContext): Promise<void> {
    for (let i = 0; i < task.steps.length; i++) {
      context.currentStepIndex = i;
      const step = task.steps[i];

      // 检查条件
      if (step.condition && !this.evaluateCondition(step.condition, context)) {
        logger.debug(TAG, `跳过步骤 ${step.id}: 条件不满足`);
        continue;
      }

      // 检查是否需要等待用户交互
      if (step.waitForUserInteraction) {
        context.status = TaskStatus.WAITING;
        logger.info(TAG, `等待用户交互: ${step.userInteractionPrompt || '请完成操作'}`);
        // 这里需要实现用户交互等待机制
        // 暂时跳过，后续可以通过事件机制实现
      }

      const result = await this.executeStep(step, context);

      if (!result.success && !step.continueOnError) {
        throw new Error(`步骤 ${step.id} 执行失败: ${result.error}`);
      }
    }
  }

  /**
   * 并行执行步骤
   */
  private async executeParallel(task: TaskDefinition, context: TaskContext): Promise<void> {
    const promises = task.steps.map(async (step, index) => {
      // 检查条件
      if (step.condition && !this.evaluateCondition(step.condition, context)) {
        logger.debug(TAG, `跳过步骤 ${step.id}: 条件不满足`);
        return;
      }

      try {
        await this.executeStep(step, context);
      } catch (error) {
        if (!step.continueOnError) {
          if (error instanceof Error) {
            throw error;
          }
          throw new Error(String(error));
        }
      }
    });

    await Promise.all(promises);
  }

  /**
   * 条件执行步骤
   */
  private async executeConditional(task: TaskDefinition, context: TaskContext): Promise<void> {
    for (const step of task.steps) {
      // 条件执行模式下，每个步骤都必须有条件
      if (step.condition && this.evaluateCondition(step.condition, context)) {
        await this.executeStep(step, context);
        // 条件执行模式下，只执行第一个满足条件的步骤
        break;
      }
    }
  }

  /**
   * 执行单个步骤
   */
  private async executeStep(step: TaskStep, context: TaskContext): Promise<StepExecutionResult> {
    logger.info(TAG, `开始执行步骤: ${step.id} - ${step.name || step.description || ''}`);

    const timeout = step.timeout || this.config.defaultTimeout || 30000;
    logger.debug(TAG, `步骤超时设置: ${timeout}ms`);
    let retryCount = 0;
    const maxRetries = step.retry?.maxRetries || 0;

    while (retryCount <= maxRetries) {
      try {
        // 应用输入参数映射
        const stepVariables = this.applyInputMapping(step.inputMapping, context);

        // 获取要执行的操作
        let actions: Action[] = [];
        if (step.workflow) {
          const workflowActions = this.workflows.get(step.workflow);
          if (!workflowActions) {
            logger.error(TAG, `工作流未找到: ${step.workflow}`);
            throw new Error(`工作流未找到: ${step.workflow}`);
          }
          actions = workflowActions;
          logger.info(TAG, `使用工作流: ${step.workflow}, 操作数: ${actions.length}`);
        } else if (step.actions) {
          actions = step.actions;
          logger.info(TAG, `使用内联操作, 操作数: ${actions.length}`);
        }

        // 执行操作
        let result: Object | null = null;
        for (let j = 0; j < actions.length; j++) {
          const action = actions[j];
          logger.info(TAG, `执行操作 ${j + 1}/${actions.length}: ${action.type}`);
          // 替换操作中的变量
          const mergedVariables = this.mergeVariables(context.variables, stepVariables);
          const processedAction = this.replaceVariables(action, mergedVariables);
          
          // 构建ActionContext
          const stringVariables: Record<string, string> = {};
          const varKeys = Object.keys(context.variables);
          for (let k = 0; k < varKeys.length; k++) {
            const key: string = varKeys[k];
            const value: Object | undefined = context.variables[key];
            stringVariables[key] = typeof value === 'string' ? value : String(value);
          }
          const actionContext: ActionContext = {
            webViewController: this.config.webViewController,
            variables: stringVariables
          };
          const actionResult = await this.actionEngine.executeAction(processedAction, actionContext);
          logger.info(TAG, `操作 ${j + 1} 完成: success=${actionResult.success}`);

          if (!actionResult.success) {
            logger.error(TAG, `操作失败: ${actionResult.error}`);
            throw new Error(actionResult.error || '操作执行失败');
          }

          // 保存脚本结果
          if (actionResult.data !== undefined) {
            result = actionResult.data;
            context.variables['scriptResult'] = result;
            logger.debug(TAG, `保存脚本结果到context`);
          }
        }
        logger.info(TAG, `步骤 ${step.id} 所有操作执行完成`);

        // 应用输出参数映射
        if (step.outputMapping && result !== null) {
          this.applyOutputMapping(step.outputMapping, result as Object, context);
        }

        // 保存步骤结果
        context.stepResults[step.id] = result ?? undefined;

        return { success: true, data: result ?? undefined };

      } catch (error) {
        retryCount++;
        const errorMessage = error instanceof Error ? error.message : String(error);

        if (retryCount <= maxRetries) {
          logger.warn(TAG, `步骤 ${step.id} 失败，重试 ${retryCount}/${maxRetries}: ${errorMessage}`);
          const delay = step.retry?.delay || 1000;
          await this.sleep(delay * (step.retry?.backoff === 'exponential' ? Math.pow(2, retryCount - 1) : 1));
        } else {
          const taskError: TaskError = {
            stepId: step.id,
            message: errorMessage,
            timestamp: Date.now(),
            recoverable: step.continueOnError || false
          };
          context.errors.push(taskError);

          return { success: false, error: errorMessage };
        }
      }
    }

    return { success: false, error: '未知错误' };
  }

  /**
   * 应用输入参数映射
   */
  private applyInputMapping(
    mapping: Record<string, string> | undefined,
    context: TaskContext
  ): Record<string, Object | undefined> {
    const result: Record<string, Object | undefined> = {};

    if (!mapping) {
      return result;
    }

    const targetParams = Object.keys(mapping);
    for (let i = 0; i < targetParams.length; i++) {
      const targetParam = targetParams[i];
      const sourceExpr = mapping[targetParam];
      result[targetParam] = this.evaluateExpression(sourceExpr, context);
    }

    return result;
  }

  /**
   * 应用输出参数映射
   */
  private applyOutputMapping(
    mapping: Record<string, string>,
    data: Object,
    context: TaskContext
  ): void {
    const outputVars = Object.keys(mapping);
    for (let i = 0; i < outputVars.length; i++) {
      const outputVar: string = outputVars[i];
      const extractExpr: string = mapping[outputVar];
      const value: Object | undefined = this.extractValue(extractExpr, data);
      context.variables[outputVar] = value;
    }
  }

  /**
   * 评估条件表达式
   */
  private evaluateCondition(condition: string, context: TaskContext): boolean {
    try {
      // 简单的条件评估，支持变量引用
      const processedCondition = this.replaceVariableReferences(condition, context.variables);

      // 简化的条件评估，支持基本的真假判断
      if (processedCondition === 'true') return true;
      if (processedCondition === 'false') return false;
      // 检查变量是否存在且不为空
      const varValue: Object | undefined = context.variables[processedCondition];
      return varValue !== undefined && varValue !== null && varValue !== '';
    } catch (error) {
      logger.warn(TAG, `条件评估失败: ${condition}, 错误: ${error}`);
      return false;
    }
  }

  /**
   * 评估表达式
   */
  private evaluateExpression(expr: string, context: TaskContext): Object | undefined {
    // 支持简单的变量引用: ${variableName} 或 ${stepResults.stepId.field}
    if (expr.startsWith('${') && expr.endsWith('}')) {
      const path = expr.slice(2, -1);
      return this.getValueByPath(context, path);
    }
    return expr;
  }

  /**
   * 从数据中提取值
   */
  private extractValue(expr: string, data: Object): Object | undefined {
    if (!data) return undefined;

    // 支持JSON路径: $.field.subfield
    if (expr.startsWith('$.')) {
      const path = expr.slice(2);
      return this.getValueByPath(data as Record<string, Object | undefined>, path);
    }

    return data;
  }

  /**
   * 根据路径获取值
   */
  private getValueByPath(obj: Object | undefined, path: string): Object | undefined {
    if (!obj) return undefined;
    const parts = path.split('.');
    let current: Object | undefined = obj;

    for (const part of parts) {
      if (current === null || current === undefined) {
        return undefined;
      }
      current = (current as Record<string, Object | undefined>)[part];
    }

    return current;
  }

  /**
   * 替换变量引用
   */
  private replaceVariableReferences(str: string, variables: Record<string, Object | undefined>): string {
    return str.replace(/\{\{([a-zA-Z0-9_.]+)\}\}/g, (match: string, varName: string): string => {
      const value: Object | undefined = variables[varName];
      if (value === undefined) return match;
      return typeof value === 'string' ? value : JSON.stringify(value);
    });
  }

  /**
   * 替换操作中的变量
   */
  private replaceVariables(action: Action, variables: Record<string, Object | undefined>): Action {
    const actionStr = JSON.stringify(action).replace(/\{\{([a-zA-Z0-9_.]+)\}\}/g, (match: string, varName: string): string => {
      const value: Object | undefined = variables[varName];
      if (value === undefined) return match;
      return typeof value === 'string' ? value : String(value);
    });
    return SafeUtils.parseObj(actionStr) as Action;
  }

  /**
   * 合并变量
   */
  private mergeVariables(base: Record<string, Object | undefined>, additional: Record<string, Object | undefined>): Record<string, Object | undefined> {
    const result: Record<string, Object | undefined> = {};
    const baseKeys = Object.keys(base);
    for (let i = 0; i < baseKeys.length; i++) {
      const key = baseKeys[i];
      result[key] = base[key];
    }
    const additionalKeys = Object.keys(additional);
    for (let i = 0; i < additionalKeys.length; i++) {
      const key = additionalKeys[i];
      result[key] = additional[key];
    }
    return result;
  }

  /**
   * 睡眠
   */
  private sleep(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  /**
   * 取消任务
   */
  cancelTask(taskId: string): boolean {
    const context = this.runningTasks.get(taskId);
    if (context) {
      context.status = TaskStatus.CANCELLED;
      this.runningTasks.delete(taskId);
      logger.info(TAG, `任务已取消: ${taskId}`);
      return true;
    }
    return false;
  }

  /**
   * 获取任务状态
   */
  getTaskStatus(taskId: string): TaskStatus | null {
    const context = this.runningTasks.get(taskId);
    return context?.status || null;
  }

  /**
   * 获取任务上下文
   */
  getTaskContext(taskId: string): TaskContext | null {
    return this.runningTasks.get(taskId) || null;
  }

  /**
   * 恢复等待中的任务
   */
  async resumeTask(taskId: string, userInput?: Record<string, Object | undefined>): Promise<void> {
    const context = this.runningTasks.get(taskId);
    if (context && context.status === TaskStatus.WAITING) {
      // 合并用户输入
      if (userInput) {
        const inputKeys = Object.keys(userInput);
        for (let i = 0; i < inputKeys.length; i++) {
          const key = inputKeys[i];
          context.variables[key] = userInput[key];
        }
      }
      context.status = TaskStatus.RUNNING;
      logger.info(TAG, `任务已恢复: ${taskId}`);
    }
  }
}
