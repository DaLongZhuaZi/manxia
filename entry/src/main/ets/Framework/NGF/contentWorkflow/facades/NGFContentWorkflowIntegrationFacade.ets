import { logger } from '../../../../Utils/Logger';
import { ContainerLifecycle, DependencyContainer } from '../../../DependencyContainer';
import { ngfServiceContainerFacade } from '../../core/facades/ServiceContainerFacade';
import { ngfActionExecutorFacade } from './ActionExecutorFacade';
import { ngfRateLimitPolicyFacade } from './RateLimitPolicyFacade';
import { ngfRetryPolicyFacade } from './RetryPolicyFacade';
import { ngfWorkflowEngineFacade } from './WorkflowEngineFacade';

const TAG = 'NGFContentWorkflowIntegrationFacade';

class NGFContentWorkflowServiceRegistration {
  token: string;
  implementationName: string;
  service: object;

  constructor(token: string, implementationName: string, service: object) {
    this.token = token;
    this.implementationName = implementationName;
    this.service = service;
  }
}

export class NGFContentWorkflowIntegrationFacade {
  private bootstrapped: boolean = false;
  private registrations: NGFContentWorkflowServiceRegistration[] = [
    new NGFContentWorkflowServiceRegistration(
      'ngf.workflow.engine',
      'WorkflowEngineFacade',
      ngfWorkflowEngineFacade as object
    ),
    new NGFContentWorkflowServiceRegistration(
      'ngf.workflow.action_executor',
      'ActionExecutorFacade',
      ngfActionExecutorFacade as object
    ),
    new NGFContentWorkflowServiceRegistration(
      'ngf.workflow.retry_policy',
      'RetryPolicyFacade',
      ngfRetryPolicyFacade as object
    ),
    new NGFContentWorkflowServiceRegistration(
      'ngf.workflow.rate_limit_policy',
      'RateLimitPolicyFacade',
      ngfRateLimitPolicyFacade as object
    )
  ];

  bootstrap(): boolean {
    if (this.bootstrapped) {
      return true;
    }

    try {
      const container = DependencyContainer.getInstance();
      this.registrations.forEach((registration: NGFContentWorkflowServiceRegistration) => {
        this.register(container, registration);
      });
      this.bootstrapped = true;
      this.syncAppStorage(true);
      logger.info(TAG, '✅ NGF Content Workflow 集成完成');
      return true;
    } catch {
      this.syncAppStorage(false);
      logger.error(TAG, '❌ NGF Content Workflow 集成失败');
      return false;
    }
  }

  isBootstrapped(): boolean {
    return this.bootstrapped;
  }

  private register(container: DependencyContainer, registration: NGFContentWorkflowServiceRegistration): void {
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
    AppStorage.setOrCreate('ngf_content_workflow_integrated', success);
    if (success) {
      AppStorage.setOrCreate('ngf_content_workflow_integrated_at', Date.now());
    }
  }
}

export const ngfContentWorkflowIntegrationFacade = new NGFContentWorkflowIntegrationFacade();
