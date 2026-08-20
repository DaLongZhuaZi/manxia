import { DisplayMode } from 'manxia_theme/src/main/ets/Utils/WindowManager';
import { PageWindowCoordinator } from 'manxia_theme/src/main/ets/Utils/PageWindowCoordinator';
import { uiContextManager } from '../../../Managers/UIContextManager';
import { IPagePolicyHost } from '../contracts/IPagePolicyHost';

export class PagePolicyHostFacade implements IPagePolicyHost {
  applyPolicy(pageName: string): void {
    const uiContext = uiContextManager.getUIContext();
    PageWindowCoordinator.applyPagePolicy(pageName, uiContext ?? undefined);
  }

  reapplyPolicy(pageName: string): void {
    const uiContext = uiContextManager.getUIContext();
    PageWindowCoordinator.reapplyPagePolicy(pageName, uiContext ?? undefined);
  }

  resolveDisplayMode(pageName: string): string {
    const mode = PageWindowCoordinator.resolveDisplayModeForPage(pageName);
    if (mode) {
      return mode;
    }
    return DisplayMode.DEFAULT;
  }
}

export const ngfPagePolicyHostFacade = new PagePolicyHostFacade();
