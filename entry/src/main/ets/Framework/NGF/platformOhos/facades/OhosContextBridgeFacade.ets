import { uiContextManager } from 'manxia_theme/src/main/ets/Framework/Managers/UIContextManager';
import { IOhosContextBridge } from '../contracts/IOhosContextBridge';

export class OhosContextBridgeFacade implements IOhosContextBridge {
  private boundContextName: string = '';

  bindUIContext(contextName: string): void {
    this.boundContextName = contextName;
  }

  clearUIContext(): void {
    this.boundContextName = '';
  }

  isUIContextReady(): boolean {
    if (this.boundContextName.length <= 0) {
      return false;
    }
    return uiContextManager.getUIContext() !== null;
  }

  getHostContextName(): string {
    if (this.boundContextName.length > 0) {
      return this.boundContextName;
    }
    if (uiContextManager.getAbilityContext()) {
      return 'UIAbilityContext';
    }
    return '';
  }
}

export const ngfOhosContextBridgeFacade = new OhosContextBridgeFacade();
