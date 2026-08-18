import { MangaAssetRetryMode } from './MangaAssetTypes';

export enum MangaImageRetryPhase {
  IDLE = 'idle',
  AUTO_RETRY = 'auto_retry',
  MANUAL_CACHE_FIRST = 'manual_cache_first',
  MANUAL_FORCE_REFRESH = 'manual_force_refresh',
  TERMINAL = 'terminal'
}

export class MangaImageRetryDecision {
  public shouldRetry: boolean = false;
  public showTerminalError: boolean = false;
  public retryMode: MangaAssetRetryMode = MangaAssetRetryMode.NONE;
  public automatic: boolean = false;
  public attempt: number = 0;
}

class MangaImageRetryState {
  public automaticAttempts: number = 0;
  public manualAttempts: number = 0;
  public phase: MangaImageRetryPhase = MangaImageRetryPhase.IDLE;
  public terminalError: string = '';
  public loading: boolean = false;
}

export function buildMangaImageRetryKey(chapterId: string, pageId: string): string {
  return `${chapterId}|${pageId}`;
}

export class MangaImageRetryCoordinator {
  private states: Map<string, MangaImageRetryState> = new Map();

  public recordFailure(
    key: string,
    message: string,
    allowAutomaticRetry: boolean = true
  ): MangaImageRetryDecision {
    const state: MangaImageRetryState = this.getOrCreateState(key);
    state.loading = false;
    state.terminalError = message;

    if (allowAutomaticRetry && state.automaticAttempts < 1 && state.manualAttempts <= 0) {
      state.automaticAttempts = state.automaticAttempts + 1;
      state.phase = MangaImageRetryPhase.AUTO_RETRY;
      state.loading = true;

      const retryDecision: MangaImageRetryDecision = new MangaImageRetryDecision();
      retryDecision.shouldRetry = true;
      retryDecision.retryMode = MangaAssetRetryMode.CACHE_FIRST;
      retryDecision.automatic = true;
      retryDecision.attempt = state.automaticAttempts;
      return retryDecision;
    }

    state.phase = MangaImageRetryPhase.TERMINAL;
    const terminalDecision: MangaImageRetryDecision = new MangaImageRetryDecision();
    terminalDecision.showTerminalError = true;
    terminalDecision.attempt = state.manualAttempts;
    return terminalDecision;
  }

  public beginManualRetry(key: string): MangaImageRetryDecision {
    const state: MangaImageRetryState = this.getOrCreateState(key);
    if (state.loading) {
      return new MangaImageRetryDecision();
    }

    state.manualAttempts = state.manualAttempts + 1;
    state.loading = true;
    state.terminalError = '';

    const decision: MangaImageRetryDecision = new MangaImageRetryDecision();
    decision.shouldRetry = true;
    decision.attempt = state.manualAttempts;
    if (state.manualAttempts === 1) {
      state.phase = MangaImageRetryPhase.MANUAL_CACHE_FIRST;
      decision.retryMode = MangaAssetRetryMode.CACHE_FIRST;
    } else {
      state.phase = MangaImageRetryPhase.MANUAL_FORCE_REFRESH;
      decision.retryMode = MangaAssetRetryMode.FORCE_REFRESH;
    }
    return decision;
  }

  public markSuccess(key: string): void {
    this.states.delete(key);
  }

  public resetPage(key: string): void {
    this.states.delete(key);
  }

  public resetAll(): void {
    this.states.clear();
  }

  public isLoading(key: string): boolean {
    const state: MangaImageRetryState | undefined = this.states.get(key);
    return state ? state.loading : false;
  }

  public getErrorMessage(key: string): string {
    const state: MangaImageRetryState | undefined = this.states.get(key);
    return state ? state.terminalError : '';
  }

  public getPhase(key: string): MangaImageRetryPhase {
    const state: MangaImageRetryState | undefined = this.states.get(key);
    return state ? state.phase : MangaImageRetryPhase.IDLE;
  }

  private getOrCreateState(key: string): MangaImageRetryState {
    const existing: MangaImageRetryState | undefined = this.states.get(key);
    if (existing) {
      return existing;
    }
    const created: MangaImageRetryState = new MangaImageRetryState();
    this.states.set(key, created);
    return created;
  }
}
