export class NGFEventPayload {
  payloadType: string;
  payloadJson: string;
  createdAt: number;

  constructor(payloadType: string, payloadJson: string, createdAt: number) {
    this.payloadType = payloadType;
    this.payloadJson = payloadJson;
    this.createdAt = createdAt;
  }
}

export type NGFEventListener = (payload: NGFEventPayload) => void;

export interface IEventBus {
  publish(eventName: string, payload: NGFEventPayload): void;
  subscribe(eventName: string, listenerId: string, listener: NGFEventListener): boolean;
  unsubscribe(eventName: string, listenerId: string): boolean;
  clear(eventName: string): void;
}
