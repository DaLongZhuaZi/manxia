export interface ISourceLoader {
  exists(pkg: string): boolean;
  loadSourceJson(pkg: string): string;
  loadIconPath(pkg: string): string;
}
