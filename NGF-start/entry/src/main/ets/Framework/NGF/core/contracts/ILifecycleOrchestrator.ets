export class NGFPhaseState {
  phaseName: string;
  progress: number;
  isCompleted: boolean;

  constructor(phaseName: string, progress: number, isCompleted: boolean) {
    this.phaseName = phaseName;
    this.progress = progress;
    this.isCompleted = isCompleted;
  }
}

export interface ILifecycleOrchestrator {
  startInitialization(): void;
  beginPhase(phaseName: string): void;
  completePhase(phaseName: string): void;
  failPhase(phaseName: string, reason: string): void;
  markCompleted(): void;
  getCurrentState(): NGFPhaseState;
  isCompleted(): boolean;
}

