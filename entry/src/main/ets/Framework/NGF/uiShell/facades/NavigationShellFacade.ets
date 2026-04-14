import { INavigationShell } from '../contracts/INavigationShell';

class NGFNavigationParamEnvelope {
  payloadJson: string;

  constructor(payloadJson: string) {
    this.payloadJson = payloadJson;
  }
}

export class NavigationShellFacade implements INavigationShell {
  push(pageName: string, paramsJson: string): boolean {
    const stack = this.resolveNavStack();
    if (!stack) {
      return false;
    }

    try {
      const navParam = this.buildNavigationParam(paramsJson);
      stack.pushPathByName(pageName, navParam ? navParam : null);
      return true;
    } catch {
      return false;
    }
  }

  pop(): boolean {
    const stack = this.resolveNavStack();
    if (!stack) {
      return false;
    }

    try {
      const allPathName = stack.getAllPathName();
      if (allPathName.length <= 0) {
        return false;
      }
      stack.pop();
      return true;
    } catch {
      return false;
    }
  }

  replace(pageName: string, paramsJson: string): boolean {
    const stack = this.resolveNavStack();
    if (!stack) {
      return false;
    }

    try {
      const allPathName = stack.getAllPathName();
      if (allPathName.length > 0) {
        stack.pop();
      }
      const navParam = this.buildNavigationParam(paramsJson);
      stack.pushPathByName(pageName, navParam ? navParam : null);
      return true;
    } catch {
      return false;
    }
  }

  currentPageName(): string {
    const stack = this.resolveNavStack();
    if (!stack) {
      return '';
    }

    try {
      const allPathName = stack.getAllPathName();
      if (allPathName.length <= 0) {
        return '';
      }
      return allPathName[allPathName.length - 1];
    } catch {
      return '';
    }
  }

  private resolveNavStack(): NavPathStack | null {
    try {
      const globalStack = AppStorage.get<NavPathStack>('GlobalNavStack');
      if (globalStack) {
        return globalStack;
      }
      return null;
    } catch {
      return null;
    }
  }

  private buildNavigationParam(paramsJson: string): Object | null {
    if (paramsJson.trim().length <= 0) {
      return null;
    }
    const envelope = new NGFNavigationParamEnvelope(paramsJson);
    return envelope as Object;
  }
}

export const ngfNavigationShellFacade = new NavigationShellFacade();
