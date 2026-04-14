import { IRetryPolicy } from '../contracts/IRetryPolicy';

class NGFRetryProfile {
  maxAttempts: number;
  baseDelayMs: number;
  maxDelayMs: number;

  constructor(maxAttempts: number, baseDelayMs: number, maxDelayMs: number) {
    this.maxAttempts = maxAttempts;
    this.baseDelayMs = baseDelayMs;
    this.maxDelayMs = maxDelayMs;
  }
}

export class RetryPolicyFacade implements IRetryPolicy {
  private readonly profile: NGFRetryProfile = new NGFRetryProfile(3, 600, 5000);

  shouldRetry(attempt: number, errorCode: string): boolean {
    if (attempt <= 0) {
      return false;
    }

    const normalizedCode = errorCode.trim().toUpperCase();
    if (normalizedCode === 'NON_RETRYABLE') {
      return false;
    }

    return attempt < this.profile.maxAttempts;
  }

  nextDelayMs(attempt: number): number {
    if (attempt <= 0) {
      return this.profile.baseDelayMs;
    }

    const rawDelay = this.profile.baseDelayMs * Math.pow(2, attempt - 1);
    if (rawDelay > this.profile.maxDelayMs) {
      return this.profile.maxDelayMs;
    }
    return rawDelay;
  }
}

export const ngfRetryPolicyFacade = new RetryPolicyFacade();
