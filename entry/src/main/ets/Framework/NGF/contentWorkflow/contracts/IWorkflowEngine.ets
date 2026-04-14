export class NGFWorkflowResult {
  success: boolean;
  outputJson: string;

  constructor(success: boolean, outputJson: string) {
    this.success = success;
    this.outputJson = outputJson;
  }
}

export interface IWorkflowEngine {
  executeWorkflow(workflowName: string, sourceId: string, inputJson: string): Promise<NGFWorkflowResult>;
}
