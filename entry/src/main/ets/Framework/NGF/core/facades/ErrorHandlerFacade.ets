import {
  ErrorCategory,
  ErrorContext,
  ErrorSeverity,
  GameError,
  errorHandler
} from '../../../Core/ErrorHandler';
import { IErrorHandler, NGFErrorContext, NGFErrorSeverity } from '../contracts/IErrorHandler';

class NGFErrorContextPatch implements Partial<ErrorContext> {
  component?: string;
  method?: string;
  additionalData?: Record<string, string | number | boolean>;

  constructor(component: string, method: string, additionalData: Record<string, string | number | boolean>) {
    this.component = component;
    this.method = method;
    this.additionalData = additionalData;
  }
}

export class ErrorHandlerFacade implements IErrorHandler {
  private strategyNames: Set<string> = new Set<string>();

  private createGameErrorAdditionalData(category: string, source: string): Record<string, string | number | boolean> {
    const additionalData: Record<string, string | number | boolean> = {} as Record<string, string | number | boolean>;
    additionalData.ngfCategory = category;
    additionalData.ngfSource = source;
    return additionalData;
  }

  private createHandleErrorAdditionalData(code: string): Record<string, string | number | boolean> {
    const additionalData: Record<string, string | number | boolean> = {} as Record<string, string | number | boolean>;
    additionalData.ngfFacade = true;
    additionalData.ngfCode = code;
    return additionalData;
  }

  async handle(
    errorName: string,
    message: string,
    severity: NGFErrorSeverity,
    context: NGFErrorContext
  ): Promise<boolean> {
    const mappedSeverity = this.toLegacySeverity(severity);
    const mappedCategory = this.toLegacyCategory(context.category);
    const code = context.code.length > 0 ? context.code : 'NGF_ERROR';
    const source = context.source.length > 0 ? context.source : 'NGF';
    const fullMessage = errorName.length > 0 ? `[${errorName}] ${message}` : message;

    const gameErrorAdditionalData = this.createGameErrorAdditionalData(context.category, source);
    const gameErrorContext = new NGFErrorContextPatch(source, errorName, gameErrorAdditionalData);
    const handleErrorAdditionalData = this.createHandleErrorAdditionalData(code);
    const handleErrorContext = new NGFErrorContextPatch(source, errorName, handleErrorAdditionalData);

    const gameError = new GameError(
      fullMessage,
      mappedSeverity,
      mappedCategory,
      gameErrorContext,
      code,
      true
    );

    return errorHandler.handleError(gameError, handleErrorContext);
  }

  registerRecoverStrategy(strategyName: string): boolean {
    if (strategyName.length <= 0) {
      return false;
    }
    if (this.strategyNames.has(strategyName)) {
      return false;
    }

    this.strategyNames.add(strategyName);
    return true;
  }

  getRecentErrorCount(): number {
    const statistics = errorHandler.getStatistics();
    return statistics.recentErrors.length;
  }

  private toLegacySeverity(severity: NGFErrorSeverity): ErrorSeverity {
    switch (severity) {
      case NGFErrorSeverity.LOW:
        return ErrorSeverity.LOW;
      case NGFErrorSeverity.MEDIUM:
        return ErrorSeverity.MEDIUM;
      case NGFErrorSeverity.HIGH:
        return ErrorSeverity.HIGH;
      case NGFErrorSeverity.CRITICAL:
        return ErrorSeverity.CRITICAL;
      default:
        return ErrorSeverity.MEDIUM;
    }
  }

  private toLegacyCategory(category: string): ErrorCategory {
    const normalized = category.toLowerCase();
    switch (normalized) {
      case ErrorCategory.NETWORK:
        return ErrorCategory.NETWORK;
      case ErrorCategory.RESOURCE:
        return ErrorCategory.RESOURCE;
      case ErrorCategory.VALIDATION:
        return ErrorCategory.VALIDATION;
      case ErrorCategory.BUSINESS_LOGIC:
        return ErrorCategory.BUSINESS_LOGIC;
      case ErrorCategory.UI:
        return ErrorCategory.UI;
      case ErrorCategory.PERFORMANCE:
        return ErrorCategory.PERFORMANCE;
      case ErrorCategory.SECURITY:
        return ErrorCategory.SECURITY;
      case ErrorCategory.COMPONENT:
        return ErrorCategory.COMPONENT;
      case ErrorCategory.SYSTEM:
      default:
        return ErrorCategory.SYSTEM;
    }
  }
}

export const ngfErrorHandlerFacade = new ErrorHandlerFacade();
