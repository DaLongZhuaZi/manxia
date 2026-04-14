import { logger } from '../../../../Utils/Logger';
import { ContainerLifecycle, DependencyContainer } from '../../../DependencyContainer';
import { ngfServiceContainerFacade } from '../../core/facades/ServiceContainerFacade';
import { ngfCacheStoreFacade } from './CacheStoreFacade';
import { ngfDataFacade } from './DataFacade';
import { ngfDbMigratorFacade } from './DbMigratorFacade';
import { ngfSettingsStoreFacade } from './SettingsStoreFacade';
import { ngfStorageProviderFacade } from './StorageProviderFacade';

const TAG = 'NGFDataIntegrationFacade';

class NGFDataServiceRegistration {
  token: string;
  implementationName: string;
  service: object;

  constructor(token: string, implementationName: string, service: object) {
    this.token = token;
    this.implementationName = implementationName;
    this.service = service;
  }
}

export class NGFDataIntegrationFacade {
  private bootstrapped: boolean = false;
  private registrations: NGFDataServiceRegistration[] = [
    new NGFDataServiceRegistration(
      'ngf.data.data_facade',
      'DataFacade',
      ngfDataFacade as object
    ),
    new NGFDataServiceRegistration(
      'ngf.data.settings_store',
      'SettingsStoreFacade',
      ngfSettingsStoreFacade as object
    ),
    new NGFDataServiceRegistration(
      'ngf.data.cache_store',
      'CacheStoreFacade',
      ngfCacheStoreFacade as object
    ),
    new NGFDataServiceRegistration(
      'ngf.data.storage_provider',
      'StorageProviderFacade',
      ngfStorageProviderFacade as object
    ),
    new NGFDataServiceRegistration(
      'ngf.data.db_migrator',
      'DbMigratorFacade',
      ngfDbMigratorFacade as object
    )
  ];

  bootstrap(): boolean {
    if (this.bootstrapped) {
      return true;
    }

    try {
      const container = DependencyContainer.getInstance();
      this.registrations.forEach((registration: NGFDataServiceRegistration) => {
        this.register(container, registration);
      });
      this.bootstrapped = true;
      this.syncAppStorage(true);
      logger.info(TAG, '✅ NGF Data 集成完成');
      return true;
    } catch {
      this.syncAppStorage(false);
      logger.error(TAG, '❌ NGF Data 集成失败');
      return false;
    }
  }

  isBootstrapped(): boolean {
    return this.bootstrapped;
  }

  private register(container: DependencyContainer, registration: NGFDataServiceRegistration): void {
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
    AppStorage.setOrCreate('ngf_data_integrated', success);
    if (success) {
      AppStorage.setOrCreate('ngf_data_integrated_at', Date.now());
    }
  }
}

export const ngfDataIntegrationFacade = new NGFDataIntegrationFacade();
