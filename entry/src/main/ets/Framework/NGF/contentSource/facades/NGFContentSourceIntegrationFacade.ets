import { logger } from '../../../../Utils/Logger';
import { ContainerLifecycle, DependencyContainer } from '../../../DependencyContainer';
import { ngfServiceContainerFacade } from '../../core/facades/ServiceContainerFacade';
import { ngfSourceLoaderFacade } from './SourceLoaderFacade';
import { ngfSourceRegistryFacade } from './SourceRegistryFacade';
import { ngfSourceRepositoryFacade } from './SourceRepositoryFacade';

const TAG = 'NGFContentSourceIntegrationFacade';

class NGFContentSourceServiceRegistration {
  token: string;
  implementationName: string;
  service: object;

  constructor(token: string, implementationName: string, service: object) {
    this.token = token;
    this.implementationName = implementationName;
    this.service = service;
  }
}

export class NGFContentSourceIntegrationFacade {
  private bootstrapped: boolean = false;
  private registrations: NGFContentSourceServiceRegistration[] = [
    new NGFContentSourceServiceRegistration(
      'ngf.source.repository',
      'SourceRepositoryFacade',
      ngfSourceRepositoryFacade as object
    ),
    new NGFContentSourceServiceRegistration(
      'ngf.source.loader',
      'SourceLoaderFacade',
      ngfSourceLoaderFacade as object
    ),
    new NGFContentSourceServiceRegistration(
      'ngf.source.registry',
      'SourceRegistryFacade',
      ngfSourceRegistryFacade as object
    )
  ];

  bootstrap(): boolean {
    if (this.bootstrapped) {
      return true;
    }

    try {
      const container = DependencyContainer.getInstance();
      this.registrations.forEach((registration: NGFContentSourceServiceRegistration) => {
        this.register(container, registration);
      });
      this.bootstrapped = true;
      this.syncAppStorage(true);
      logger.info(TAG, '✅ NGF Content Source 集成完成');
      return true;
    } catch {
      this.syncAppStorage(false);
      logger.error(TAG, '❌ NGF Content Source 集成失败');
      return false;
    }
  }

  isBootstrapped(): boolean {
    return this.bootstrapped;
  }

  private register(container: DependencyContainer, registration: NGFContentSourceServiceRegistration): void {
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
    AppStorage.setOrCreate('ngf_content_source_integrated', success);
    if (success) {
      AppStorage.setOrCreate('ngf_content_source_integrated_at', Date.now());
    }
  }
}

export const ngfContentSourceIntegrationFacade = new NGFContentSourceIntegrationFacade();
