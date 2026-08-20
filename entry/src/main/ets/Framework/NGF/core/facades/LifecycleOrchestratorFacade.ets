import {
  AppInitializationManager,
  InitPhase,
  InitializationState
} from 'manxia_core/src/main/ets/Framework/Managers/AppInitializationManager';
import { ILifecycleOrchestrator, NGFPhaseState } from '../contracts/ILifecycleOrchestrator';

export class LifecycleOrchestratorFacade implements ILifecycleOrchestrator {
  private manager: AppInitializationManager = AppInitializationManager.getInstance();

  startInitialization(): void {
    this.manager.startInitialization();
  }

  beginPhase(phaseName: string): void {
    this.manager.beginPhase(this.toInitPhase(phaseName));
  }

  completePhase(phaseName: string): void {
    this.manager.completePhase(this.toInitPhase(phaseName));
  }

  failPhase(phaseName: string, reason: string): void {
    this.manager.failPhase(this.toInitPhase(phaseName), reason);
  }

  markCompleted(): void {
    this.manager.markCompleted();
  }

  getCurrentState(): NGFPhaseState {
    const state = this.manager.getState();
    return this.toNGFPhaseState(state);
  }

  isCompleted(): boolean {
    return this.manager.isCompleted();
  }

  getCompletionPromise(): Promise<boolean> {
    return this.manager.getCompletionPromise();
  }

  private toNGFPhaseState(state: InitializationState): NGFPhaseState {
    return new NGFPhaseState(state.currentPhase, state.progress, state.isCompleted);
  }

  private toInitPhase(phaseName: string): InitPhase {
    const normalized = phaseName.toLowerCase();
    switch (normalized) {
      case InitPhase.NOT_STARTED:
        return InitPhase.NOT_STARTED;
      case InitPhase.CONTEXT_SETUP:
        return InitPhase.CONTEXT_SETUP;
      case InitPhase.DEVICE_ADAPTATION:
        return InitPhase.DEVICE_ADAPTATION;
      case InitPhase.DATA_SYSTEM:
        return InitPhase.DATA_SYSTEM;
      case InitPhase.SETTINGS:
        return InitPhase.SETTINGS;
      case InitPhase.FONT_MANAGER:
        return InitPhase.FONT_MANAGER;
      case InitPhase.PROXY_MANAGER:
        return InitPhase.PROXY_MANAGER;
      case InitPhase.DOWNLOAD_SYNC:
        return InitPhase.DOWNLOAD_SYNC;
      case InitPhase.DOWNLOAD_MANAGER:
        return InitPhase.DOWNLOAD_MANAGER;
      case InitPhase.AUTO_BACKUP:
        return InitPhase.AUTO_BACKUP;
      case InitPhase.WIDGET_SYNC:
        return InitPhase.WIDGET_SYNC;
      case InitPhase.CHANGELOG:
        return InitPhase.CHANGELOG;
      case InitPhase.CRASH_RECORDER:
        return InitPhase.CRASH_RECORDER;
      case InitPhase.ERROR_MONITOR:
        return InitPhase.ERROR_MONITOR;
      case InitPhase.COMPLETED:
        return InitPhase.COMPLETED;
      case InitPhase.FAILED:
        return InitPhase.FAILED;
      default:
        return InitPhase.NOT_STARTED;
    }
  }
}

export const ngfLifecycleOrchestratorFacade = new LifecycleOrchestratorFacade();
