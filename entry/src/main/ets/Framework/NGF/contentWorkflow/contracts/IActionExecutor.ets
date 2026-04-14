export class NGFActionResult {
  success: boolean;
  outputJson: string;

  constructor(success: boolean, outputJson: string) {
    this.success = success;
    this.outputJson = outputJson;
  }
}

export interface IActionExecutor {
  executeAction(actionType: string, actionJson: string, contextJson: string): Promise<NGFActionResult>;
}
