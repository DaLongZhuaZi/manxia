import { logger } from '../../../../Utils/Logger';
import { NGFEventPayload } from '../contracts/IEventBus';
import { NGFErrorContext, NGFErrorSeverity } from '../contracts/IErrorHandler';
import { ngfEventBusFacade } from './EventBusFacade';
import { ngfErrorHandlerFacade } from './ErrorHandlerFacade';

const TAG = 'NGFCoreEventBridge';

export enum NGFInitializationEventName {
  INIT_STATE_CHANGED = 'ngf.app.initialization.state_changed',
  INIT_FAILED = 'ngf.app.initialization.failed',
  INIT_COMPLETED = 'ngf.app.initialization.completed'
}

class NGFInitializationEventData {
  phaseName: string;
  status: string;
  message: string;
  timestamp: number;

  constructor(phaseName: string, status: string, message: string, timestamp: number) {
    this.phaseName = phaseName;
    this.status = status;
    this.message = message;
    this.timestamp = timestamp;
  }
}

export class NGFCoreEventBridge {
  publishInitializationState(phaseName: string, status: string, message: string): void {
    const payloadData = new NGFInitializationEventData(phaseName, status, message, Date.now());
    const payload = new NGFEventPayload('ngf_init_state', this.toJson(payloadData), Date.now());
    ngfEventBusFacade.publish(NGFInitializationEventName.INIT_STATE_CHANGED, payload);
  }

  publishInitializationFailed(phaseName: string, errorMessage: string): void {
    const payloadData = new NGFInitializationEventData(phaseName, 'failed', errorMessage, Date.now());
    const payload = new NGFEventPayload('ngf_init_failed', this.toJson(payloadData), Date.now());
    ngfEventBusFacade.publish(NGFInitializationEventName.INIT_FAILED, payload);
    this.reportInitializationFailureToErrorHandler(phaseName, errorMessage);
  }

  publishInitializationCompleted(message: string): void {
    const payloadData = new NGFInitializationEventData('completed', 'completed', message, Date.now());
    const payload = new NGFEventPayload('ngf_init_completed', this.toJson(payloadData), Date.now());
    ngfEventBusFacade.publish(NGFInitializationEventName.INIT_COMPLETED, payload);
  }

  private reportInitializationFailureToErrorHandler(phaseName: string, errorMessage: string): void {
    const context = new NGFErrorContext('system', 'NGF_INIT_PHASE_FAILED', TAG);
    const composedMessage = `[${phaseName}] ${errorMessage}`;
    void ngfErrorHandlerFacade.handle(
      'InitializationPhaseFailed',
      composedMessage,
      NGFErrorSeverity.HIGH,
      context
    ).catch((error: Error | string) => {
      const message = error instanceof Error ? error.message : String(error);
      logger.warn(TAG, `NGF错误上报失败: ${message}`);
    });
  }

  private toJson(data: NGFInitializationEventData): string {
    try {
      const serialized = JSON.stringify(data);
      if (serialized === undefined) {
        return '{}';
      }
      return serialized;
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      return `{"error":"${message}"}`;
    }
  }
}

export const ngfCoreEventBridge = new NGFCoreEventBridge();
