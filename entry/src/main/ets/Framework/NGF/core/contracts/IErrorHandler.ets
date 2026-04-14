export enum NGFErrorSeverity {
  LOW = 'low',
  MEDIUM = 'medium',
  HIGH = 'high',
  CRITICAL = 'critical'
}

export class NGFErrorContext {
  category: string;
  code: string;
  source: string;

  constructor(category: string, code: string, source: string) {
    this.category = category;
    this.code = code;
    this.source = source;
  }
}

export interface IErrorHandler {
  handle(errorName: string, message: string, severity: NGFErrorSeverity, context: NGFErrorContext): Promise<boolean>;
  registerRecoverStrategy(strategyName: string): boolean;
  getRecentErrorCount(): number;
}
