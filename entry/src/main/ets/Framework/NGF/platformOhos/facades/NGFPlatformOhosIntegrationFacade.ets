import { logger } from '../../../../Utils/Logger';
import { ContainerLifecycle, DependencyContainer } from '../../../DependencyContainer';
import { ngfServiceContainerFacade } from '../../core/facades/ServiceContainerFacade';
import { ngfOhosContextBridgeFacade } from './OhosContextBridgeFacade';
import { ngfPageWindowPolicyResolverFacade } from './PageWindowPolicyResolverFacade';
import { ngfPlatformWindowControllerFacade } from './PlatformWindowControllerFacade';

const TAG = 'NGFPlatformOhosIntegrationFacade';

class NGFPlatformServiceRegistration {
  token: string;
  implementationName: string;
  service: object;

  constructor(token: string, implementationName: string, service: object) {
    this.token = token;
    this.implementationName = implementationName;
    this.service = service;
  }
}

export class NGFPlatformOhosIntegrationFacade {
  private bootstrapped: boolean = false;
  private registrations: NGFPlatformServiceRegistration[] = [
    new NGFPlatformServiceRegistration(
      'ngf.platform.window_controller',
      'PlatformWindowControllerFacade',
      ngfPlatformWindowControllerFacade as object
    ),
    new NGFPlatformServiceRegistration(
      'ngf.platform.page_policy_resolver',
      'PageWindowPolicyResolverFacade',
      ngfPageWindowPolicyResolverFacade as object
    ),
    new NGFPlatformServiceRegistration(
      'ngf.platform.context_bridge',
      'OhosContextBridgeFacade',
      ngfOhosContextBridgeFacade as object
    )
  ];

  bootstrap(): boolean {
    if (this.bootstrapped) {
      return true;
    }

    try {
      const container = DependencyContainer.getInstance();
      this.registrations.forEach((registration: NGFPlatformServiceRegistration) => {
        this.register(container, registration);
      });
      ngfOhosContextBridgeFacade.bindUIContext('EntryAbility');
      this.bootstrapped = true;
      this.syncAppStorage(true);
      logger.info(TAG, '✅ NGF Platform OHOS 集成完成');
      return true;
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      this.syncAppStorage(false);
      logger.error(TAG, `❌ NGF Platform OHOS 集成失败: ${message}`);
      return false;
    }
  }

  isBootstrapped(): boolean {
    return this.bootstrapped;
  }

  private register(container: DependencyContainer, registration: NGFPlatformServiceRegistration): void {
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
    AppStorage.setOrCreate('ngf_platform_integrated', success);
    if (success) {
      AppStorage.setOrCreate('ngf_platform_integrated_at', Date.now());
    }
  }
}

export const ngfPlatformOhosIntegrationFacade = new NGFPlatformOhosIntegrationFacade();
