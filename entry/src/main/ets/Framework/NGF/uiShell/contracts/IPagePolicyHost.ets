export interface IPagePolicyHost {
  applyPolicy(pageName: string): void;
  reapplyPolicy(pageName: string): void;
  resolveDisplayMode(pageName: string): string;
}
