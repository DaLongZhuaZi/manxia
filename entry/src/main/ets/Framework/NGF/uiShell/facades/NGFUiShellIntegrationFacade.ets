import { logger } from '../../../../Utils/Logger';
import { ContainerLifecycle, DependencyContainer } from '../../../DependencyContainer';
import { ngfServiceContainerFacade } from '../../core/facades/ServiceContainerFacade';
import { ngfNavigationShellFacade } from './NavigationShellFacade';
import { ngfPagePolicyHostFacade } from './PagePolicyHostFacade';

const TAG = 'NGFUiShellIntegrationFacade';

class NGFUiShellServiceRegistration {
  token: string;
  implementationName: string;
  service: object;

  constructor(token: string, implementationName: string, service: object) {
    this.token = token;
    this.implementationName = implementationName;
    this.service = service;
  }
}

export class NGFUiShellIntegrationFacade {
  private bootstrapped: boolean = false;
  private registrations: NGFUiShellServiceRegistration[] = [
    new NGFUiShellServiceRegistration(
      'ngf.ui.navigation_shell',
      'NavigationShellFacade',
      ngfNavigationShellFacade as object
    ),
    new NGFUiShellServiceRegistration(
      'ngf.ui.page_policy_host',
      'PagePolicyHostFacade',
      ngfPagePolicyHostFacade as object
    )
  ];

  bootstrap(): boolean {
    if (this.bootstrapped) {
      return true;
    }

    try {
      const container = DependencyContainer.getInstance();
      this.registrations.forEach((registration: NGFUiShellServiceRegistration) => {
        this.register(container, registration);
      });
      this.bootstrapped = true;
      this.syncAppStorage(true);
      logger.info(TAG, '✅ NGF UI Shell 集成完成');
      return true;
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      this.syncAppStorage(false);
      logger.error(TAG, `❌ NGF UI Shell 集成失败: ${message}`);
      return false;
    }
  }

  isBootstrapped(): boolean {
    return this.bootstrapped;
  }

  private register(container: DependencyContainer, registration: NGFUiShellServiceRegistration): void {
    if (!container.isRegistered(registration.token)) {
      container.register(registration.token, (): object => {
        return registration.service;
      }, ContainerLifecycle.SINGLETON);
    }

    if (!ngfServiceContainerFacade.contains(registration.token)) {
      ngfServiceContainerFacade.registerSingleton(registration.token, registration.implementationName);
    }
  }

  private syncAppStorage(success: boolean): void {
    AppStorage.setOrCreate('ngf_ui_shell_integrated', success);
    if (success) {
      AppStorage.setOrCreate('ngf_ui_shell_integrated_at', Date.now());
    }
  }
}

export const ngfUiShellIntegrationFacade = new NGFUiShellIntegrationFacade();
