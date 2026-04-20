import { hilog } from '@kit.PerformanceAnalysisKit';
import { ILogger, NGFLogLevel } from '../contracts/ILogger';
import { IEventBus, NGFEventListener, NGFEventPayload } from '../contracts/IEventBus';
import { IErrorHandler, NGFErrorContext, NGFErrorSeverity } from '../contracts/IErrorHandler';
import { ILifecycleOrchestrator, NGFPhaseState } from '../contracts/ILifecycleOrchestrator';
import { IServiceContainer } from '../contracts/IServiceContainer';

const LOG_DOMAIN: number = 0xD003A21;
const LOG_TAG: string = 'NGFStarterCore';
const MAX_RECENT_ERROR_RECORDS: number = 50;

export class NGFStarterServiceToken {
  static readonly LOGGER: string = 'ngf.core.logger';
  static readonly EVENT_BUS: string = 'ngf.core.event_bus';
  static readonly ERROR_HANDLER: string = 'ngf.core.error_handler';
  static readonly LIFECYCLE: string = 'ngf.core.lifecycle';
  static readonly SERVICE_CONTAINER: string = 'ngf.core.service_container';
}

export class NGFStarterEventName {
  static readonly CORE_READY: string = 'ngf.starter.core.ready';
  static readonly CORE_STATE_CHANGED: string = 'ngf.starter.core.state_changed';
  static readonly CORE_ERROR: string = 'ngf.starter.core.error';
  static readonly DEMO_EVENT: string = 'ngf.starter.demo.event';
}

class NGFStarterCoreStateEnvelope {
  phaseName: string;
  progress: number;
  isCompleted: boolean;
  timestamp: number;

  constructor(phaseName: string, progress: number, isCompleted: boolean, timestamp: number) {
    this.phaseName = phaseName;
    this.progress = progress;
    this.isCompleted = isCompleted;
    this.timestamp = timestamp;
  }
}

class NGFStarterErrorRecord {
  errorName: string;
  message: string;
  severity: NGFErrorSeverity;
  category: string;
  code: string;
  source: string;
  timestamp: number;

  constructor(
    errorName: string,
    message: string,
    severity: NGFErrorSeverity,
    category: string,
    code: string,
    source: string,
    timestamp: number
  ) {
    this.errorName = errorName;
    this.message = message;
    this.severity = severity;
    this.category = category;
    this.code = code;
    this.source = source;
    this.timestamp = timestamp;
  }
}

class NGFStarterLogger implements ILogger {
  private currentLevel: NGFLogLevel = NGFLogLevel.INFO;

  setLevel(level: NGFLogLevel): void {
    this.currentLevel = level;
  }

  getLevel(): NGFLogLevel {
    return this.currentLevel;
  }

  debug(tag: string, message: string): void {
    if (!this.shouldLog(NGFLogLevel.DEBUG)) {
      return;
    }
    hilog.debug(LOG_DOMAIN, LOG_TAG, '%{public}s', this.format(tag, message));
  }

  info(tag: string, message: string): void {
    if (!this.shouldLog(NGFLogLevel.INFO)) {
      return;
    }
    hilog.info(LOG_DOMAIN, LOG_TAG, '%{public}s', this.format(tag, message));
  }

  warn(tag: string, message: string): void {
    if (!this.shouldLog(NGFLogLevel.WARN)) {
      return;
    }
    hilog.warn(LOG_DOMAIN, LOG_TAG, '%{public}s', this.format(tag, message));
  }

  error(tag: string, message: string): void {
    if (!this.shouldLog(NGFLogLevel.ERROR)) {
      return;
    }
    hilog.error(LOG_DOMAIN, LOG_TAG, '%{public}s', this.format(tag, message));
  }

  lifecycle(tag: string, message: string): void {
    this.info(tag, `[lifecycle] ${message}`);
  }

  stateChange(tag: string, fromState: string, toState: string, reason: string): void {
    this.info(tag, `[state] ${fromState} -> ${toState}; reason=${reason}`);
  }

  private shouldLog(level: NGFLogLevel): boolean {
    return this.toWeight(level) >= this.toWeight(this.currentLevel);
  }

  private toWeight(level: NGFLogLevel): number {
    switch (level) {
      case NGFLogLevel.DEBUG:
        return 10;
      case NGFLogLevel.INFO:
      case NGFLogLevel.LIFECYCLE:
        return 20;
      case NGFLogLevel.WARN:
        return 30;
      case NGFLogLevel.ERROR:
        return 40;
      default:
        return 20;
    }
  }

  private format(tag: string, message: string): string {
    return `[${tag}] ${message}`;
  }
}

class NGFStarterEventBus implements IEventBus {
  private readonly logger: ILogger;
  private readonly listenersByEvent: Map<string, Map<string, NGFEventListener>> = new Map<string, Map<string, NGFEventListener>>();

  constructor(logger: ILogger) {
    this.logger = logger;
  }

  publish(eventName: string, payload: NGFEventPayload): void {
    const listeners = this.listenersByEvent.get(eventName);
    if (!listeners) {
      return;
    }

    listeners.forEach((listener: NGFEventListener) => {
      try {
        listener(payload);
      } catch (error) {
        this.logger.warn(LOG_TAG, `event listener failed: ${this.errorToString(error as Object | string | number | boolean)}`);
      }
    });
  }

  subscribe(eventName: string, listenerId: string, listener: NGFEventListener): boolean {
    if (eventName.trim().length <= 0 || listenerId.trim().length <= 0) {
      return false;
    }

    const listeners = this.ensureListeners(eventName);
    if (listeners.has(listenerId)) {
      return false;
    }

    listeners.set(listenerId, listener);
    return true;
  }

  unsubscribe(eventName: string, listenerId: string): boolean {
    const listeners = this.listenersByEvent.get(eventName);
    if (!listeners || !listeners.has(listenerId)) {
      return false;
    }

    listeners.delete(listenerId);
    if (listeners.size === 0) {
      this.listenersByEvent.delete(eventName);
    }
    return true;
  }

  clear(eventName: string): void {
    this.listenersByEvent.delete(eventName);
  }

  private ensureListeners(eventName: string): Map<string, NGFEventListener> {
    const existing = this.listenersByEvent.get(eventName);
    if (existing) {
      return existing;
    }
    const created = new Map<string, NGFEventListener>();
    this.listenersByEvent.set(eventName, created);
    return created;
  }

  private errorToString(error: Object | string | number | boolean): string {
    if (typeof error === 'string') {
      return error;
    }
    if (typeof error === 'number' || typeof error === 'boolean') {
      return String(error);
    }
    if (error instanceof Error) {
      return error.message;
    }
    return String(error);
  }
}

class NGFStarterLifecycleOrchestrator implements ILifecycleOrchestrator {
  private currentPhase: string = 'not_started';
  private progress: number = 0;
  private completed: boolean = false;
  private readonly phaseOrder: string[] = ['context_setup', 'core_services', 'ready'];

  startInitialization(): void {
    this.currentPhase = 'not_started';
    this.progress = 0;
    this.completed = false;
  }

  beginPhase(phaseName: string): void {
    const normalized = this.normalizePhaseName(phaseName);
    this.currentPhase = normalized;
    this.progress = this.resolveProgress(normalized, false);
    this.completed = false;
  }

  completePhase(phaseName: string): void {
    const normalized = this.normalizePhaseName(phaseName);
    this.currentPhase = normalized;
    this.progress = this.resolveProgress(normalized, true);
  }

  failPhase(phaseName: string, reason: string): void {
    const normalized = this.normalizePhaseName(phaseName);
    this.currentPhase = normalized;
    this.completed = false;
    this.progress = Math.max(0, this.resolveProgress(normalized, false));
    if (reason.trim().length > 0) {
      this.currentPhase = `${normalized}:failed`;
    }
  }

  markCompleted(): void {
    this.currentPhase = 'completed';
    this.progress = 100;
    this.completed = true;
  }

  getCurrentState(): NGFPhaseState {
    return new NGFPhaseState(this.currentPhase, this.progress, this.completed);
  }

  isCompleted(): boolean {
    return this.completed;
  }

  private normalizePhaseName(phaseName: string): string {
    const normalized = phaseName.trim().toLowerCase();
    if (normalized.length <= 0) {
      return 'not_started';
    }
    return normalized;
  }

  private resolveProgress(phaseName: string, isPhaseCompleted: boolean): number {
    if (phaseName === 'not_started') {
      return 0;
    }
    if (phaseName === 'completed') {
      return 100;
    }

    const index = this.phaseOrder.indexOf(phaseName);
    if (index < 0) {
      return this.progress;
    }

    const totalPhases = this.phaseOrder.length;
    if (isPhaseCompleted) {
      return Math.floor(((index + 1) * 100) / totalPhases);
    }
    return Math.floor((index * 100) / totalPhases);
  }
}

class NGFStarterServiceContainer implements IServiceContainer {
  private readonly registrations: Map<string, string> = new Map<string, string>();

  registerSingleton(token: string, implementationName: string): void {
    this.registrations.set(token, implementationName);
  }

  resolve(token: string): string {
    const implementationName = this.registrations.get(token);
    if (implementationName) {
      return implementationName;
    }
    return '';
  }

  contains(token: string): boolean {
    return this.registrations.has(token);
  }
}

class NGFStarterErrorHandler implements IErrorHandler {
  private readonly logger: ILogger;
  private readonly eventBus: IEventBus;
  private readonly strategyNames: Set<string> = new Set<string>();
  private readonly recentErrors: Array<NGFStarterErrorRecord> = [];

  constructor(logger: ILogger, eventBus: IEventBus) {
    this.logger = logger;
    this.eventBus = eventBus;
  }

  async handle(
    errorName: string,
    message: string,
    severity: NGFErrorSeverity,
    context: NGFErrorContext
  ): Promise<boolean> {
    try {
      const now = Date.now();
      const record = new NGFStarterErrorRecord(
        errorName,
        message,
        severity,
        context.category,
        context.code,
        context.source,
        now
      );
      this.pushRecord(record);
      this.logger.error(context.source, `${errorName}: ${message}`);

      const payload = new NGFEventPayload('ngf_core_error', this.toJson(record), now);
      this.eventBus.publish(NGFStarterEventName.CORE_ERROR, payload);
      return true;
    } catch (error) {
      this.logger.error(LOG_TAG, `error handling failed: ${this.errorToString(error as Object | string | number | boolean)}`);
      return false;
    }
  }

  registerRecoverStrategy(strategyName: string): boolean {
    const normalized = strategyName.trim();
    if (normalized.length <= 0 || this.strategyNames.has(normalized)) {
      return false;
    }
    this.strategyNames.add(normalized);
    return true;
  }

  getRecentErrorCount(): number {
    return this.recentErrors.length;
  }

  private pushRecord(record: NGFStarterErrorRecord): void {
    this.recentErrors.push(record);
    if (this.recentErrors.length > MAX_RECENT_ERROR_RECORDS) {
      this.recentErrors.shift();
    }
  }

  private toJson(record: NGFStarterErrorRecord): string {
    try {
      const serialized = JSON.stringify(record);
      if (serialized === undefined) {
        return '{}';
      }
      return serialized;
    } catch {
      return '{}';
    }
  }

  private errorToString(error: Object | string | number | boolean): string {
    if (typeof error === 'string') {
      return error;
    }
    if (typeof error === 'number' || typeof error === 'boolean') {
      return String(error);
    }
    if (error instanceof Error) {
      return error.message;
    }
    return String(error);
  }
}

export class NGFStarterKernel {
  private static instance: NGFStarterKernel | null = null;

  readonly logger: ILogger;
  readonly eventBus: IEventBus;
  readonly errorHandler: IErrorHandler;
  readonly lifecycle: ILifecycleOrchestrator;
  readonly serviceContainer: IServiceContainer;
  private bootstrapped: boolean = false;

  private constructor() {
    this.logger = new NGFStarterLogger();
    this.eventBus = new NGFStarterEventBus(this.logger);
    this.errorHandler = new NGFStarterErrorHandler(this.logger, this.eventBus);
    this.lifecycle = new NGFStarterLifecycleOrchestrator();
    this.serviceContainer = new NGFStarterServiceContainer();
  }

  static getInstance(): NGFStarterKernel {
    if (!NGFStarterKernel.instance) {
      NGFStarterKernel.instance = new NGFStarterKernel();
    }
    return NGFStarterKernel.instance;
  }

  bootstrap(): boolean {
    if (this.bootstrapped) {
      return true;
    }

    try {
      this.lifecycle.startInitialization();
      this.publishCurrentState();

      this.lifecycle.beginPhase('context_setup');
      this.publishCurrentState();
      this.registerCoreServices();
      this.lifecycle.completePhase('context_setup');
      this.publishCurrentState();

      this.lifecycle.beginPhase('core_services');
      this.publishCurrentState();
      this.lifecycle.completePhase('core_services');
      this.publishCurrentState();

      this.lifecycle.beginPhase('ready');
      this.publishCurrentState();
      this.lifecycle.completePhase('ready');
      this.lifecycle.markCompleted();
      this.publishCurrentState();

      this.bootstrapped = true;
      this.logger.lifecycle(LOG_TAG, 'NGF starter core bootstrapped');

      const readyPayload = new NGFEventPayload(
        'ngf_core_ready',
        this.toStateEnvelopeJson(this.lifecycle.getCurrentState()),
        Date.now()
      );
      this.eventBus.publish(NGFStarterEventName.CORE_READY, readyPayload);
      return true;
    } catch (error) {
      const message = this.errorToString(error as Object | string | number | boolean);
      const context = new NGFErrorContext('system', 'NGF_STARTER_BOOTSTRAP_FAILED', LOG_TAG);
      void this.errorHandler.handle('StarterBootstrapFailed', message, NGFErrorSeverity.CRITICAL, context);
      this.bootstrapped = false;
      return false;
    }
  }

  isBootstrapped(): boolean {
    return this.bootstrapped;
  }

  private registerCoreServices(): void {
    this.serviceContainer.registerSingleton(NGFStarterServiceToken.LOGGER, 'NGFStarterLogger');
    this.serviceContainer.registerSingleton(NGFStarterServiceToken.EVENT_BUS, 'NGFStarterEventBus');
    this.serviceContainer.registerSingleton(NGFStarterServiceToken.ERROR_HANDLER, 'NGFStarterErrorHandler');
    this.serviceContainer.registerSingleton(NGFStarterServiceToken.LIFECYCLE, 'NGFStarterLifecycleOrchestrator');
    this.serviceContainer.registerSingleton(NGFStarterServiceToken.SERVICE_CONTAINER, 'NGFStarterServiceContainer');
  }

  private publishCurrentState(): void {
    const payload = new NGFEventPayload(
      'ngf_core_state',
      this.toStateEnvelopeJson(this.lifecycle.getCurrentState()),
      Date.now()
    );
    this.eventBus.publish(NGFStarterEventName.CORE_STATE_CHANGED, payload);
  }

  private toStateEnvelopeJson(state: NGFPhaseState): string {
    const envelope = new NGFStarterCoreStateEnvelope(state.phaseName, state.progress, state.isCompleted, Date.now());
    try {
      const serialized = JSON.stringify(envelope);
      if (serialized === undefined) {
        return '{}';
      }
      return serialized;
    } catch {
      return '{}';
    }
  }

  private errorToString(error: Object | string | number | boolean): string {
    if (typeof error === 'string') {
      return error;
    }
    if (typeof error === 'number' || typeof error === 'boolean') {
      return String(error);
    }
    if (error instanceof Error) {
      return error.message;
    }
    return String(error);
  }
}

export const ngfStarterKernel: NGFStarterKernel = NGFStarterKernel.getInstance();

