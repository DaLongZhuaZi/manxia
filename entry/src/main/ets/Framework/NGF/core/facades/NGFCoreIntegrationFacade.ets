import { logger } from '../../../../Utils/Logger';
import { ContainerLifecycle, DependencyContainer } from '../../../DependencyContainer';
import { ngfEventBusFacade } from './EventBusFacade';
import { ngfErrorHandlerFacade } from './ErrorHandlerFacade';
import { ngfLifecycleOrchestratorFacade } from './LifecycleOrchestratorFacade';
import { ngfLoggerFacade } from './LoggerFacade';
import { ngfServiceContainerFacade } from './ServiceContainerFacade';

const TAG = 'NGFCoreIntegrationFacade';

class NGFCoreServiceRegistration {
  token: string;
  service: object;

  constructor(token: string, service: object) {
    this.token = token;
    this.service = service;
  }
}

export class NGFCoreIntegrationFacade {
  private bootstrapped: boolean = false;
  private registrations: NGFCoreServiceRegistration[] = [
    new NGFCoreServiceRegistration('ngf.core.logger', ngfLoggerFacade as object),
    new NGFCoreServiceRegistration('ngf.core.event_bus', ngfEventBusFacade as object),
    new NGFCoreServiceRegistration('ngf.core.error_handler', ngfErrorHandlerFacade as object),
    new NGFCoreServiceRegistration('ngf.core.lifecycle', ngfLifecycleOrchestratorFacade as object),
    new NGFCoreServiceRegistration('ngf.core.service_container', ngfServiceContainerFacade as object)
  ];

  bootstrap(): boolean {
    if (this.bootstrapped) {
      return true;
    }

    try {
      const container = DependencyContainer.getInstance();
      this.registrations.forEach((registration: NGFCoreServiceRegistration) => {
        this.registerService(container, registration);
      });
      this.bootstrapped = true;
      this.syncAppStorage(true);
      logger.info(TAG, '✅ NGF Core 集成完成，服务已注册到 DependencyContainer');
      return true;
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      this.syncAppStorage(false);
      logger.error(TAG, `❌ NGF Core 集成失败: ${message}`);
      return false;
    }
  }

  isBootstrapped(): boolean {
    return this.bootstrapped;
  }

  private registerService(container: DependencyContainer, registration: NGFCoreServiceRegistration): void {
    if (container.isRegistered(registration.token)) {
      logger.debug(TAG, `检测到已注册服务，跳过: ${registration.token}`);
      return;
    }

    container.register(registration.token, (): object => {
      return registration.service;
    }, ContainerLifecycle.SINGLETON);
    logger.debug(TAG, `已注册 NGF 服务: ${registration.token}`);
  }

  private syncAppStorage(success: boolean): void {
    AppStorage.setOrCreate('ngf_core_integrated', success);
    if (success) {
      AppStorage.setOrCreate('ngf_core_integrated_at', Date.now());
    }
  }
}

export const ngfCoreIntegrationFacade = new NGFCoreIntegrationFacade();
