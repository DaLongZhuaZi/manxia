export interface ISourceRegistry {
  registerSource(sourceId: string, pkg: string): boolean;
  unregisterSource(sourceId: string): boolean;
  hasSource(sourceId: string): boolean;
  listSourceIds(): string[];
}
