import { IRateLimitPolicy } from '../contracts/IRateLimitPolicy';

class NGFRateLimitRecord {
  key: string;
  lastRequestAt: number;
  minIntervalMs: number;

  constructor(key: string, lastRequestAt: number, minIntervalMs: number) {
    this.key = key;
    this.lastRequestAt = lastRequestAt;
    this.minIntervalMs = minIntervalMs;
  }
}

export class RateLimitPolicyFacade implements IRateLimitPolicy {
  private readonly records: Map<string, NGFRateLimitRecord> = new Map<string, NGFRateLimitRecord>();
  private readonly defaultIntervalMs: number = 400;

  canProceed(key: string, nowMs: number): boolean {
    const normalizedKey = this.normalizeKey(key);
    const record = this.getOrCreateRecord(normalizedKey);
    if (record.lastRequestAt <= 0) {
      return true;
    }

    const elapsed = nowMs - record.lastRequestAt;
    return elapsed >= record.minIntervalMs;
  }

  markRequest(key: string, nowMs: number): void {
    const normalizedKey = this.normalizeKey(key);
    const record = this.getOrCreateRecord(normalizedKey);
    record.lastRequestAt = nowMs;
  }

  retryAfterMs(key: string, nowMs: number): number {
    const normalizedKey = this.normalizeKey(key);
    const record = this.getOrCreateRecord(normalizedKey);
    if (record.lastRequestAt <= 0) {
      return 0;
    }

    const elapsed = nowMs - record.lastRequestAt;
    const remaining = record.minIntervalMs - elapsed;
    if (remaining <= 0) {
      return 0;
    }
    return remaining;
  }

  private normalizeKey(key: string): string {
    const normalized = key.trim();
    if (normalized.length <= 0) {
      return 'global';
    }
    return normalized;
  }

  private getOrCreateRecord(key: string): NGFRateLimitRecord {
    const existing = this.records.get(key);
    if (existing) {
      return existing;
    }

    const created = new NGFRateLimitRecord(key, 0, this.defaultIntervalMs);
    this.records.set(key, created);
    return created;
  }
}

export const ngfRateLimitPolicyFacade = new RateLimitPolicyFacade();
