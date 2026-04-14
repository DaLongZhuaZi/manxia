export interface INavigationShell {
  push(pageName: string, paramsJson: string): boolean;
  pop(): boolean;
  replace(pageName: string, paramsJson: string): boolean;
  currentPageName(): string;
}
