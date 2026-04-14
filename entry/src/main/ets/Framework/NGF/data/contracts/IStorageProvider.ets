export interface IStorageProvider {
  getCacheDir(): string;
  getFilesDir(): string;
  readText(path: string): string;
  writeText(path: string, content: string): boolean;
  exists(path: string): boolean;
}
