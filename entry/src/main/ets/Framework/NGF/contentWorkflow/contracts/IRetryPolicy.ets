export interface IRetryPolicy {
  shouldRetry(attempt: number, errorCode: string): boolean;
  nextDelayMs(attempt: number): number;
}
