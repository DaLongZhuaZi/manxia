export interface ICacheStore {
  put(key: string, value: string, ttlMs: number): void;
  get(key: string): string;
  has(key: string): boolean;
  remove(key: string): void;
  clear(): void;
}
