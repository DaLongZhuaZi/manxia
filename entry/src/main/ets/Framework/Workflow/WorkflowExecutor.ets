// 文件路径: entry/src/main/ets/Framework/Workflow/WorkflowExecutor.ets
/**
 * 工作流执行器
 * 统一执行工作流并自动应用声明的能力
 */

import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import WorkflowCapabilities, { type WorkflowContext, type CapabilityType } from './WorkflowCapabilities';
import { MangaSourceAPIEngine, type JSONExtractConfig } from 'manxia_network/src/main/ets/Framework/WebView/MangaSourceAPIEngine';
import { type UserAgentRotationConfig } from 'manxia_core/src/main/ets/Framework/Managers/UserAgentManager';
import { ngfWorkflowEngineFacade } from '../NGF';

const TAG = 'WorkflowExecutor';
const NGF_WORKFLOW_SHADOW_FLAG_KEY = 'ngf_content_workflow_shadow_mode';

class EmptyExtractResult {
  items: Object[];

  constructor() {
    this.items = [];
  }
}

class NGFWorkflowShadowContext {
  sourceId: number;
  workflowName: string;
  variablesJson: string;
  stepCount: number;

  constructor(sourceId: number, workflowName: string, variablesJson: string, stepCount: number) {
    this.sourceId = sourceId;
    this.workflowName = workflowName;
    this.variablesJson = variablesJson;
    this.stepCount = stepCount;
  }
}

class NGFWorkflowShadowInput {
  actionType: string;
  actionJson: string;
  contextJson: string;

  constructor(actionType: string, actionJson: string, contextJson: string) {
    this.actionType = actionType;
    this.actionJson = actionJson;
    this.contextJson = contextJson;
  }
}

/**
 * 工作流步骤
 */
export interface WorkflowStep {
  type: 'api' | 'transform' | 'extract';
  name?: string;
  url?: string;
  method?: string;
  headers?: Record<string, string>;
  body?: Object;
  extract?: Object;
}

/**
 * 工作流定义
 */
export interface WorkflowDefinition {
  name: string;
  description?: string;
  steps: WorkflowStep[];
  capabilities?: CapabilityType[];
}

/**
 * 执行结果
 */
export interface ExecutionResult {
  success: boolean;
  data?: Object;
  error?: string;
  metadata?: Record<string, Object>;
}

/**
 * 工作流执行器
 */
export class WorkflowExecutor {
  private static instance: WorkflowExecutor | null = null;
  private capabilities: WorkflowCapabilities;
  private apiEngine: MangaSourceAPIEngine;

  private constructor() {
    this.capabilities = WorkflowCapabilities.getInstance();
    this.apiEngine = new MangaSourceAPIEngine();
  }

  static getInstance(): WorkflowExecutor {
    if (!WorkflowExecutor.instance) {
      WorkflowExecutor.instance = new WorkflowExecutor();
    }
    return WorkflowExecutor.instance;
  }

  /**
   * 执行工作流
   */
  async executeWorkflow(
    workflow: WorkflowDefinition,
    context: WorkflowContext
  ): Promise<ExecutionResult> {
    logger.info(TAG, `开始执行工作流: ${workflow.name}`);
    logger.debug(TAG, this.capabilities.getCapabilityStats(context));
    this.runNgfWorkflowShadow(workflow, context);

    try {
      let result: Object = {};

      for (let i = 0; i < workflow.steps.length; i++) {
        const step = workflow.steps[i];
        logger.debug(TAG, `执行步骤 ${i + 1}/${workflow.steps.length}: ${step.type}`);

        switch (step.type) {
          case 'api':
            result = await this.executeApiStep(step, context);
            break;
          case 'transform':
            result = this.executeTransformStep(step, context, result);
            break;
          case 'extract':
            result = this.executeExtractStep(step, context, result);
            break;
          default:
            logger.warn(TAG, `未知步骤类型: ${step.type}`);
        }
      }

      logger.info(TAG, `工作流执行成功: ${workflow.name}`);
      
      const executionResult: ExecutionResult = {
        success: true,
        data: result,
        metadata: {
          workflowName: workflow.name,
          stepsExecuted: workflow.steps.length
        }
      };
      
      return executionResult;
    } catch (error) {
      logger.error(TAG, `工作流执行失败: ${workflow.name}, error=${String(error)}`);
      
      const executionResult: ExecutionResult = {
        success: false,
        error: String(error)
      };
      
      return executionResult;
    }
  }

  private runNgfWorkflowShadow(workflow: WorkflowDefinition, context: WorkflowContext): void {
    if (!this.isNgfWorkflowShadowEnabled()) {
      return;
    }

    const stepCount = workflow.steps.length;
    const firstStep = stepCount > 0 ? workflow.steps[0] : undefined;
    const actionType = firstStep ? firstStep.type : 'extract';
    const actionJson = firstStep ? this.safeToJson(firstStep as Object) : '{}';
    const contextJson = this.safeToJson(
      new NGFWorkflowShadowContext(
        context.sourceId,
        workflow.name,
        this.safeToJson(context.variables as Object),
        stepCount
      )
    );
    const input = new NGFWorkflowShadowInput(actionType, actionJson, contextJson);
    void this.dispatchNgfWorkflowShadow(workflow.name, `${context.sourceId}`, input);
  }

  private async dispatchNgfWorkflowShadow(
    workflowName: string,
    sourceId: string,
    input: NGFWorkflowShadowInput
  ): Promise<void> {
    try {
      const result = await ngfWorkflowEngineFacade.executeWorkflow(
        workflowName,
        sourceId,
        this.safeToJson(input as Object)
      );
      logger.debug(TAG, `NGF workflow shadow result: success=${result.success}, source=${sourceId}`);
    } catch (error) {
      logger.warn(TAG, `NGF workflow shadow failed: ${String(error)}`);
    }
  }

  private isNgfWorkflowShadowEnabled(): boolean {
    const flag = AppStorage.get<boolean>(NGF_WORKFLOW_SHADOW_FLAG_KEY);
    return flag === true;
  }

  private safeToJson(value: Object): string {
    try {
      return JSON.stringify(value);
    } catch {
      return '{}';
    }
  }

  /**
   * 执行API步骤
   */
  private async executeApiStep(
    step: WorkflowStep,
    context: WorkflowContext
  ): Promise<Object> {
    if (!step.url) {
      throw new Error('API步骤缺少URL');
    }

    // 1. 应用URL解析能力
    let url = step.url;
    if (this.capabilities.hasCapabilityInContext(context, 'urlResolver')) {
      url = this.capabilities.applyUrlResolver(url, context);
      logger.debug(TAG, `URL解析: ${step.url} -> ${url}`);
    }

    // 2. 添加分页参数
    if (this.capabilities.hasCapabilityInContext(context, 'pagination')) {
      const paginationParams = this.capabilities.getPaginationParams(context);
      if (Object.keys(paginationParams).length > 0) {
        // 将分页参数添加到context.variables中
        Object.assign(context.variables, paginationParams);
        logger.debug(TAG, `添加分页参数: ${JSON.stringify(paginationParams)}`);
      }
    }

    // 3. 构建请求配置
    const method = (step.method || 'GET') as 'GET' | 'POST' | 'PUT' | 'DELETE';
    const requestConfig = {
      method: method,
      url: url,
      headers: step.headers,
      body: step.body
    };

    // 4. 获取User-Agent（如果启用）
    const uaConfigObj = context.capabilities.get('userAgentRotation');
    const uaConfig = uaConfigObj as UserAgentRotationConfig | undefined;

    // 5. 执行请求（自动应用错误重试）
    const response = await this.apiEngine.request(
      requestConfig,
      context.sourceId,
      uaConfig
    );

    logger.debug(TAG, `API请求成功: status=${response.status}`);
    return response.data as Object;
  }

  /**
   * 执行转换步骤
   */
  private executeTransformStep(
    step: WorkflowStep,
    context: WorkflowContext,
    inputData: Object
  ): Object {
    let result = inputData;

    // 应用简繁转换能力
    if (this.capabilities.hasCapabilityInContext(context, 'chineseConverter')) {
      result = this.capabilities.applyChineseConverter(result as Record<string, Object>, context);
      logger.debug(TAG, '应用简繁转换');
    }

    return result;
  }

  /**
   * 执行提取步骤
   */
  private executeExtractStep(
    step: WorkflowStep,
    context: WorkflowContext,
    inputData: Object
  ): Object {
    if (!step.extract) {
      logger.debug(TAG, 'extract步骤未配置提取规则，返回输入数据');
      return inputData;
    }

    const extractConfig = step.extract as JSONExtractConfig;
    const extracted = this.apiEngine.extractFromJSON(inputData, extractConfig);
    if (extracted === null) {
      logger.warn(TAG, `extract步骤未提取到数据: path=${extractConfig.path || 'root'}`);
      return new EmptyExtractResult() as Object;
    }

    logger.debug(TAG, `extract步骤完成: path=${extractConfig.path || 'root'}, array=${Array.isArray(extracted)}`);
    return extracted as Object;
  }

  /**
   * 执行带分页的工作流
   */
  async executeWithPagination(
    workflow: WorkflowDefinition,
    context: WorkflowContext,
    maxPages?: number
  ): Promise<ExecutionResult[]> {
    const results: ExecutionResult[] = [];
    let currentPage = 1;
    const max = maxPages || 10;

    while (currentPage <= max) {
      logger.info(TAG, `执行第 ${currentPage} 页`);

      const result = await this.executeWorkflow(workflow, context);
      results.push(result);

      if (!result.success) {
        logger.warn(TAG, '工作流执行失败，停止分页');
        break;
      }

      // 检查是否还有更多数据
      if (this.capabilities.hasCapabilityInContext(context, 'pagination')) {
        const paginationResult = this.capabilities.applyPagination(context, result.data);
        if (!paginationResult || !paginationResult.hasMore) {
          logger.info(TAG, '没有更多数据，停止分页');
          break;
        }
      } else {
        // 如果没有分页能力，只执行一次
        break;
      }

      currentPage++;
    }

    logger.info(TAG, `分页执行完成: 共 ${results.length} 页`);
    return results;
  }

  /**
   * 创建简单的API工作流
   */
  static createApiWorkflow(
    name: string,
    url: string,
    method: string = 'GET',
    headers?: Record<string, string>,
    body?: Object
  ): WorkflowDefinition {
    const step: WorkflowStep = {
      type: 'api',
      url: url,
      method: method,
      headers: headers,
      body: body
    };

    const workflow: WorkflowDefinition = {
      name: name,
      steps: [step]
    };

    return workflow;
  }

  /**
   * 从JSON配置创建工作流
   */
  static createFromConfig(config: Record<string, Object>): WorkflowDefinition {
    const workflow: WorkflowDefinition = {
      name: String(config['name'] || 'unnamed'),
      description: config['description'] ? String(config['description']) : undefined,
      steps: config['steps'] as WorkflowStep[] || []
    };

    return workflow;
  }

  /**
   * 清理工作流资源
   */
  cleanup(sourceId: number): void {
    this.capabilities.cleanup(sourceId);
    logger.info(TAG, `清理工作流资源: sourceId=${sourceId}`);
  }
}

export default WorkflowExecutor;
