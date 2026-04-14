import { eventBus } from '../../../EventBus';
import type { IEventPayload } from '../../../EventBus';
import { IEventBus, NGFEventListener, NGFEventPayload } from '../contracts/IEventBus';

class NGFJsonEventPayload implements IEventPayload {
  payloadType: string;
  payloadJson: string;
  createdAt: number;

  constructor(payloadType: string, payloadJson: string, createdAt: number) {
    this.payloadType = payloadType;
    this.payloadJson = payloadJson;
    this.createdAt = createdAt;
  }
}

type LegacyEventCallback = (payload: IEventPayload) => void;

export class EventBusFacade implements IEventBus {
  private listenersByEvent: Map<string, Map<string, NGFEventListener>> = new Map<string, Map<string, NGFEventListener>>();
  private wrappersByEvent: Map<string, Map<string, LegacyEventCallback>> = new Map<string, Map<string, LegacyEventCallback>>();

  publish(eventName: string, payload: NGFEventPayload): void {
    const eventPayload = new NGFJsonEventPayload(payload.payloadType, payload.payloadJson, payload.createdAt);
    eventBus.publish(eventName, eventPayload);
  }

  subscribe(eventName: string, listenerId: string, listener: NGFEventListener): boolean {
    if (listenerId.length <= 0) {
      return false;
    }

    const listenersForEvent = this.getOrCreateListeners(eventName);
    if (listenersForEvent.has(listenerId)) {
      return false;
    }

    const wrapper: LegacyEventCallback = (payload: IEventPayload) => {
      listener(this.toNGFEventPayload(payload));
    };

    listenersForEvent.set(listenerId, listener);
    const wrappersForEvent = this.getOrCreateWrappers(eventName);
    wrappersForEvent.set(listenerId, wrapper);
    eventBus.subscribe(eventName, wrapper);
    return true;
  }

  unsubscribe(eventName: string, listenerId: string): boolean {
    const wrappersForEvent = this.wrappersByEvent.get(eventName);
    if (!wrappersForEvent) {
      return false;
    }

    const wrapper = wrappersForEvent.get(listenerId);
    if (!wrapper) {
      return false;
    }

    eventBus.unsubscribe(eventName, wrapper);
    wrappersForEvent.delete(listenerId);

    const listenersForEvent = this.listenersByEvent.get(eventName);
    if (listenersForEvent) {
      listenersForEvent.delete(listenerId);
      if (listenersForEvent.size === 0) {
        this.listenersByEvent.delete(eventName);
      }
    }

    if (wrappersForEvent.size === 0) {
      this.wrappersByEvent.delete(eventName);
    }

    return true;
  }

  clear(eventName: string): void {
    const wrappersForEvent = this.wrappersByEvent.get(eventName);
    if (!wrappersForEvent) {
      return;
    }

    wrappersForEvent.forEach((wrapper: LegacyEventCallback) => {
      eventBus.unsubscribe(eventName, wrapper);
    });

    this.wrappersByEvent.delete(eventName);
    this.listenersByEvent.delete(eventName);
  }

  private getOrCreateListeners(eventName: string): Map<string, NGFEventListener> {
    const existing = this.listenersByEvent.get(eventName);
    if (existing) {
      return existing;
    }

    const created = new Map<string, NGFEventListener>();
    this.listenersByEvent.set(eventName, created);
    return created;
  }

  private getOrCreateWrappers(eventName: string): Map<string, LegacyEventCallback> {
    const existing = this.wrappersByEvent.get(eventName);
    if (existing) {
      return existing;
    }

    const created = new Map<string, LegacyEventCallback>();
    this.wrappersByEvent.set(eventName, created);
    return created;
  }

  private toNGFEventPayload(payload: IEventPayload): NGFEventPayload {
    if (payload instanceof NGFJsonEventPayload) {
      return new NGFEventPayload(payload.payloadType, payload.payloadJson, payload.createdAt);
    }

    const serializedPayload = this.safeSerialize(payload);
    return new NGFEventPayload('legacy_payload', serializedPayload, Date.now());
  }

  private safeSerialize(payload: IEventPayload): string {
    try {
      const serialized = JSON.stringify(payload);
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

export const ngfEventBusFacade = new EventBusFacade();
