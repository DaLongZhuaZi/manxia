/**
 * Cancellation primitives shared by the V2 validator, workflow and
 * transports.  A token is deliberately source-scoped: cancelling one
 * validation must not cancel a different source's request.
 */

export type LegadoCancellationListener = (reason: string) => void;

export function createLegadoExecutionCancelledError(reason: string): Error {
  return new Error(`LEGADO_EXECUTION_CANCELLED:${reason}`);
}

export class LegadoExecutionCancellationToken {
  private cancelled: boolean = false;
  private reason: string = '';
  private nextListenerId: number = 1;
  private readonly listeners: Map<number, LegadoCancellationListener> = new Map();

  isCancelled(): boolean {
    return this.cancelled;
  }

  getReason(): string {
    return this.reason;
  }

  cancel(reason: string): void {
    if (this.cancelled) {
      return;
    }
    this.cancelled = true;
    this.reason = reason.trim().length > 0 ? reason : 'cancelled';
    const callbacks: LegadoCancellationListener[] = [];
    for (const callback of this.listeners.values()) {
      callbacks.push(callback);
    }
    this.listeners.clear();
    for (let index = 0; index < callbacks.length; index++) {
      try {
        callbacks[index](this.reason);
      } catch (_error) {
        // A transport cleanup callback must not prevent the other callbacks.
      }
    }
  }

  register(listener: LegadoCancellationListener): number {
    if (this.cancelled) {
      listener(this.reason);
      return 0;
    }
    const listenerId = this.nextListenerId;
    this.nextListenerId += 1;
    this.listeners.set(listenerId, listener);
    return listenerId;
  }

  unregister(listenerId: number): void {
    if (listenerId > 0) {
      this.listeners.delete(listenerId);
    }
  }

  throwIfCancelled(): void {
    if (this.cancelled) {
      throw createLegadoExecutionCancelledError(this.reason);
    }
  }
}

export function createLegadoCancellationToken(): LegadoExecutionCancellationToken {
  return new LegadoExecutionCancellationToken();
}
