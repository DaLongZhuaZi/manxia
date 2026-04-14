export interface IRateLimitPolicy {
  canProceed(key: string, nowMs: number): boolean;
  markRequest(key: string, nowMs: number): void;
  retryAfterMs(key: string, nowMs: number): number;
}
