export interface ISourceRepository {
  readIndexJson(): string;
  updateIndexJson(content: string): boolean;
  listPackages(): string[];
}
