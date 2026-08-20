import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import {
  DEFAULT_READ_ALOUD_SETTINGS,
  ReadAloudEngineType,
  ReadAloudSettings,
  isRemoteReadAloudPresetConfigEqual,
  normalizeReadAloudSettings
} from '../../Models/TextReaderModels';
import { eventBus, GameEvent, ReadAloudStatePayload } from '../EventBus';
import {
  ReadAloudPlaybackState,
  ReadAloudProgressSnapshot,
  ReadAloudSessionContext,
  ReadAloudStateSnapshot,
  ReadAloudVoiceOption
} from './ReadAloudTypes';
import { IReadAloudBackend, ReadAloudBackendFactory, ReadAloudPlaybackEvent, ReadAloudVoiceCatalog } from './ReadAloudBackends';
import { ReadAloudAvailability } from './ReadAloudAvailability';
import { ReadAloudMediaCommandListener, ReadAloudMediaSession } from './ReadAloudMediaSession';
import { ReadAloudFlowMonitor } from 'manxia_novel/src/main/ets/Framework/ReadAloud/ReadAloudFlowMonitor';
import {
  ReadAloudFlowEventType,
  ReadAloudFlowMode,
  ReadAloudFlowSessionInfo,
  ReadAloudFlowSeverity
} from 'manxia_novel/src/main/ets/Framework/ReadAloud/ReadAloudFlowTypes';

const TAG = 'ReadAloudController';
const MEDIA_SKIP_CHARS: number = 420;
const BASE_CHARS_PER_SECOND: number = 11;
const BACKGROUND_KEEP_ALIVE_INTERVAL_MS: number = 15000;
const PAUSE_RESUME_REWIND_CHARS: number = 2;
const READ_ALOUD_UI_STATUS_TEXT_KEY = 'ReadAloudUiStatusText';
const READ_ALOUD_UI_STATUS_DETAIL_KEY = 'ReadAloudUiStatusDetail';
const READ_ALOUD_UI_STATUS_PHASE_KEY = 'ReadAloudUiStatusPhase';
const READ_ALOUD_UI_STATUS_UPDATED_AT_KEY = 'ReadAloudUiStatusUpdatedAt';

export interface ReadAloudSleepTimerSnapshot {
  active: boolean;
  endAt: number;
  remainingMs: number;
}

interface ReadAloudControllerErrorLike {
  code?: number | string;
  message?: string;
}

class ReadAloudMediaCommandBridge implements ReadAloudMediaCommandListener {
  private readonly onPlayCallback: () => void;
  private readonly onPauseCallback: () => void;
  private readonly onStopCallback: () => void;
  private readonly onPlayNextCallback: () => void;
  private readonly onPlayPreviousCallback: () => void;
  private readonly onSeekCallback: (positionMs: number) => void;

  constructor(
    onPlayCallback: () => void,
    onPauseCallback: () => void,
    onStopCallback: () => void,
    onPlayNextCallback: () => void,
    onPlayPreviousCallback: () => void,
    onSeekCallback: (positionMs: number) => void
  ) {
    this.onPlayCallback = onPlayCallback;
    this.onPauseCallback = onPauseCallback;
    this.onStopCallback = onStopCallback;
    this.onPlayNextCallback = onPlayNextCallback;
    this.onPlayPreviousCallback = onPlayPreviousCallback;
    this.onSeekCallback = onSeekCallback;
  }

  onPlay(): void {
    this.onPlayCallback();
  }

  onPause(): void {
    this.onPauseCallback();
  }

  onStop(): void {
    this.onStopCallback();
  }

  onPlayNext(): void {
    this.onPlayNextCallback();
  }

  onPlayPrevious(): void {
    this.onPlayPreviousCallback();
  }

  onSeek(positionMs: number): void {
    this.onSeekCallback(positionMs);
  }
}

export class ReadAloudController {
  private static instance: ReadAloudController;

  private settings: ReadAloudSettings = ReadAloudController.copySettings(DEFAULT_READ_ALOUD_SETTINGS);
  private playbackState: ReadAloudPlaybackState = ReadAloudPlaybackState.IDLE;
  private context: ReadAloudSessionContext | null = null;
  private lastBookId: string = '';
  private backend: IReadAloudBackend = ReadAloudBackendFactory.create(DEFAULT_READ_ALOUD_SETTINGS.engineType);
  private currentCharIndex: number = -1;
  private chunkStartCharIndex: number = -1;
  private chunkEndCharIndex: number = -1;
  private currentPositionMs: number = -1;
  private totalDurationMs: number = -1;
  private mediaSession: ReadAloudMediaSession = new ReadAloudMediaSession();
  private backgroundKeepAliveTimer: number = -1;
  private sleepTimerHandle: number = -1;
  private sleepTimerEndAt: number = 0;
  private readAloudFlowId: string = '';
  private readAloudFlowBookId: string = '';

  private constructor() {
    this.bindBackendProgressListener();
    this.syncProgressSnapshotFromBackend();
    const mediaCommandListener: ReadAloudMediaCommandListener = new ReadAloudMediaCommandBridge(
      (): void => {
        this.start('media_control_play');
      },
      (): void => {
        this.pause('media_control_pause');
      },
      (): void => {
        this.stop('media_control_stop');
      },
      (): void => {
        this.skipByChars(MEDIA_SKIP_CHARS, 'media_control_next');
      },
      (): void => {
        this.skipByChars(-MEDIA_SKIP_CHARS, 'media_control_previous');
      },
      (positionMs: number): void => {
        this.seekToPositionMs(positionMs, 'media_control_seek');
      }
    );
    this.mediaSession.setCommandListener(mediaCommandListener);
    this.syncMediaSession();
  }

  static getInstance(): ReadAloudController {
    if (!ReadAloudController.instance) {
      ReadAloudController.instance = new ReadAloudController();
    }
    return ReadAloudController.instance;
  }

  updateSettings(settings?: ReadAloudSettings): void {
    const previousSettings = ReadAloudController.copySettings(this.settings);
    const previousEngine = this.settings.engineType;
    this.settings = ReadAloudController.mergeSettingsWithDefaults(settings);
    const nextEngine = this.normalizeEngineType(this.settings.engineType);
    this.settings.engineType = nextEngine;
    const engineChanged = previousEngine !== nextEngine;
    const voiceChanged = this.isVoiceSelectionChanged(previousSettings, this.settings);
    const remoteSettingsChanged = this.isRemoteSettingsChanged(previousSettings, this.settings);

    if (engineChanged) {
      this.switchBackend(nextEngine);
    }
    this.backend.applySettings(this.settings);

    if (!this.settings.enabled && this.playbackState === ReadAloudPlaybackState.PLAYING) {
      this.stop('settings_disabled');
    }
    if (
      (engineChanged || voiceChanged || remoteSettingsChanged) &&
      this.settings.enabled &&
      this.playbackState === ReadAloudPlaybackState.PLAYING
    ) {
      this.restartPlaybackForConfigurationChange('settings_changed');
    }
    this.updateBackgroundKeepAliveTimer();
    this.syncMediaSession();
  }

  updateContext(context: ReadAloudSessionContext): void {
    this.context = context;
    if (context.bookId && context.bookId.trim().length > 0) {
      this.lastBookId = context.bookId;
    }
    this.backend.updateContext(context);
    this.syncProgressSnapshotFromBackend();
    this.updateBackgroundKeepAliveTimer();
    this.syncMediaSession();
    this.recordReadAloudFlowEvent(
      ReadAloudFlowEventType.CONTEXT_UPDATED,
      'update_context',
      0,
      true,
      `contentLength=${context.content.length}, page=${context.pageIndex}`
    );
  }

  updatePageIndex(pageIndex: number): void {
    if (!this.context) {
      return;
    }
    this.context.pageIndex = pageIndex;
    this.backend.updateContext(this.context);
    this.syncProgressSnapshotFromBackend();
    this.updateBackgroundKeepAliveTimer();
    this.syncMediaSession();
  }

  getContextSnapshot(): ReadAloudSessionContext | null {
    if (!this.context) {
      return null;
    }
    return {
      bookId: this.context.bookId,
      bookTitle: this.context.bookTitle,
      chapterIndex: this.context.chapterIndex,
      chapterTitle: this.context.chapterTitle,
      coverUrl: this.context.coverUrl,
      content: this.context.content,
      pageIndex: this.context.pageIndex,
      resumeCharIndex: this.context.resumeCharIndex,
      readerOpenFlowId: this.context.readerOpenFlowId,
      sourceId: this.context.sourceId,
      totalChapters: this.context.totalChapters
    };
  }

  private ensureReadAloudFlowSession(reason: string): void {
    if (!this.context) {
      return;
    }
    if (this.readAloudFlowId.length > 0 && this.readAloudFlowBookId !== this.context.bookId) {
      ReadAloudFlowMonitor.getInstance().endSession(this.readAloudFlowId, `context_changed_${reason}`);
      this.readAloudFlowId = '';
      this.readAloudFlowBookId = '';
    }
    if (this.readAloudFlowId.length > 0) {
      return;
    }
    const info = new ReadAloudFlowSessionInfo();
    info.readerOpenFlowId = this.context.readerOpenFlowId || '';
    info.mode = ReadAloudFlowMode.NORMAL_TTS;
    info.sourceId = this.context.sourceId || '';
    info.bookId = this.context.bookId;
    info.bookTitle = this.context.bookTitle || '';
    info.chapterTitle = this.context.chapterTitle;
    info.chapterIndex = this.context.chapterIndex;
    info.totalChapters = this.context.totalChapters ?? 0;
    info.pageIndex = this.context.pageIndex;
    info.engineType = String(this.settings.engineType);
    this.readAloudFlowId = ReadAloudFlowMonitor.getInstance().startSession(info);
    this.readAloudFlowBookId = this.context.bookId;
  }

  private recordReadAloudFlowEvent(
    eventType: ReadAloudFlowEventType,
    reason: string,
    elapsedMs: number,
    success: boolean,
    detail: string,
    backendTaskName: string = '',
    playerOperation: string = ''
  ): void {
    this.ensureReadAloudFlowSession(reason);
    if (this.readAloudFlowId.length <= 0 || !this.context) {
      return;
    }
    const event = ReadAloudFlowMonitor.getInstance().createEvent(
      this.readAloudFlowId,
      eventType,
      ReadAloudFlowMode.NORMAL_TTS,
      this.context.bookId,
      this.context.chapterIndex,
      reason
    );
    event.readerOpenFlowId = this.context.readerOpenFlowId || '';
    event.sourceId = this.context.sourceId || '';
    event.chapterTitle = this.context.chapterTitle;
    event.totalChapters = this.context.totalChapters ?? 0;
    event.pageIndex = this.context.pageIndex;
    event.positionMs = this.currentPositionMs;
    event.durationMs = this.totalDurationMs;
    event.engineType = String(this.settings.engineType);
    event.backendTaskName = backendTaskName;
    event.playerOperation = playerOperation;
    event.elapsedMs = Math.max(0, elapsedMs);
    event.success = success;
    event.detail = detail;
    if (!success) {
      event.severity = ReadAloudFlowSeverity.ERROR;
      event.errorMessage = detail;
    }
    if (event.elapsedMs > 0) {
      event.metricName = `read_aloud.${eventType}`;
      event.metricValue = event.elapsedMs;
      event.metricUnit = 'ms';
    }
    ReadAloudFlowMonitor.getInstance().record(event);
  }

  seekByChars(delta: number, reason: string = 'player_seek_by_chars'): void {
    this.skipByChars(delta, reason);
  }

  togglePlayback(): void {
    if (this.playbackState === ReadAloudPlaybackState.PLAYING) {
      this.pause('user_toggle');
      return;
    }
    this.start('user_toggle');
  }

  start(reason: string = 'manual'): void {
    logger.info(TAG, `收到听书启动请求: reason=${reason}, engine=${this.settings.engineType}`);
    if (!this.settings.enabled) {
      logger.debug(TAG, '听书未启用，忽略启动请求');
      this.recordReadAloudFlowEvent(ReadAloudFlowEventType.START_REQUESTED, reason, 0, false, 'settings_disabled');
      return;
    }
    if (!this.ensureEngineAvailableForStart()) {
      this.recordReadAloudFlowEvent(ReadAloudFlowEventType.START_REQUESTED, reason, 0, false, 'engine_unavailable');
      return;
    }
    if (!this.context || !this.context.content || this.context.content.trim().length === 0) {
      logger.warn(TAG, '听书启动失败：当前没有可朗读内容');
      this.recordReadAloudFlowEvent(ReadAloudFlowEventType.START_REQUESTED, reason, 0, false, 'content_empty');
      return;
    }
    if (this.playbackState === ReadAloudPlaybackState.PLAYING) {
      this.recordReadAloudFlowEvent(ReadAloudFlowEventType.START_REQUESTED, reason, 0, true, 'already_playing');
      return;
    }
    this.recordReadAloudFlowEvent(ReadAloudFlowEventType.START_REQUESTED, reason, 0, true, '');
    this.syncContextResumeCharFromSnapshot(`start_before_${reason}`);

    this.runBackendTask(
      this.backend.start(),
      `start:${this.settings.engineType}`,
      () => {
        this.syncProgressSnapshotFromBackend();
        this.syncContextResumeCharFromSnapshot(`start_after_${reason}`);
        this.changeState(ReadAloudPlaybackState.PLAYING, reason);
        eventBus.publish(GameEvent.READ_ALOUD_STARTED, this.createStatePayload(reason));
        this.syncMediaSession();
      }
    );
  }

  pause(reason: string = 'manual'): void {
    logger.info(TAG, `收到听书暂停请求: reason=${reason}`);
    if (this.playbackState !== ReadAloudPlaybackState.PLAYING) {
      this.recordReadAloudFlowEvent(ReadAloudFlowEventType.PAUSE_REQUESTED, reason, 0, true, 'not_playing');
      return;
    }
    this.recordReadAloudFlowEvent(ReadAloudFlowEventType.PAUSE_REQUESTED, reason, 0, true, '');
    this.runBackendTask(
      this.backend.pause(),
      `pause:${this.settings.engineType}`,
      () => {
        this.syncProgressSnapshotFromBackend();
        if (this.playbackState !== ReadAloudPlaybackState.PAUSED) {
          return;
        }
        this.applyPauseResumeCompensation(reason);
        this.syncContextResumeCharFromSnapshot(`pause_after_${reason}`);
      }
    );
    this.syncProgressSnapshotFromBackend();
    this.applyPauseResumeCompensation(reason);
    this.syncContextResumeCharFromSnapshot(`pause_before_${reason}`);
    this.changeState(ReadAloudPlaybackState.PAUSED, reason);
    eventBus.publish(GameEvent.READ_ALOUD_PAUSED, this.createStatePayload(reason));
    this.syncMediaSession();
  }

  stop(reason: string = 'manual'): void {
    logger.info(TAG, `收到听书停止请求: reason=${reason}`);
    if (
      this.playbackState === ReadAloudPlaybackState.IDLE ||
      this.playbackState === ReadAloudPlaybackState.STOPPED
    ) {
      this.recordReadAloudFlowEvent(ReadAloudFlowEventType.STOP_REQUESTED, reason, 0, true, 'already_stopped');
      return;
    }
    this.recordReadAloudFlowEvent(ReadAloudFlowEventType.STOP_REQUESTED, reason, 0, true, '');
    this.runBackendTask(
      this.backend.stop(),
      `stop:${this.settings.engineType}`,
      () => {
        this.syncProgressSnapshotFromBackend();
        this.syncContextResumeCharFromSnapshot(`stop_after_${reason}`);
      }
    );
    this.syncProgressSnapshotFromBackend();
    this.syncContextResumeCharFromSnapshot(`stop_before_${reason}`);
    this.changeState(ReadAloudPlaybackState.STOPPED, reason);
    eventBus.publish(GameEvent.READ_ALOUD_STOPPED, this.createStatePayload(reason));
    this.syncMediaSession();
  }

  handlePageHide(): void {
    const isInBackground = AppStorage.get<boolean>('isInBackground') === true;
    if (!isInBackground) {
      return;
    }
    if (!this.settings.continueInBackground && this.playbackState === ReadAloudPlaybackState.PLAYING) {
      this.pause('page_hide');
    }
  }

  seekToPositionMs(positionMs: number, reason: string = 'manual_seek'): void {
    if (!this.context || !this.context.content || this.context.content.length <= 0) {
      return;
    }
    this.recordReadAloudFlowEvent(
      ReadAloudFlowEventType.SEEK_REQUESTED,
      reason,
      0,
      true,
      `positionMs=${Math.max(0, Math.floor(positionMs))}`
    );
    const resolvedCharIndex = this.backend.resolveCharIndexByPositionMs(positionMs);
    if (resolvedCharIndex >= 0) {
      this.seekToCharIndex(resolvedCharIndex, reason);
      return;
    }
    const durationMs = this.totalDurationMs > 0
      ? this.totalDurationMs
      : this.estimateDurationMs(this.context.content.length);
    if (durationMs <= 0) {
      return;
    }
    const safePositionMs = Math.max(0, Math.min(Math.floor(positionMs), durationMs));
    const ratio = safePositionMs / durationMs;
    const targetCharIndex = Math.floor(this.context.content.length * ratio);
    this.seekToCharIndex(targetCharIndex, reason);
  }

  release(): void {
    this.stop('release');
    this.clearBackgroundKeepAliveTimer();
    this.cancelSleepTimer();
    this.runBackendTask(this.backend.release(), `release:${this.settings.engineType}`);
    this.context = null;
    this.backend.updateContext(null);
    this.syncProgressSnapshotFromBackend();
    this.changeState(ReadAloudPlaybackState.IDLE, 'release');
    this.mediaSession.release();
    if (this.readAloudFlowId.length > 0) {
      ReadAloudFlowMonitor.getInstance().endSession(this.readAloudFlowId, 'release');
      this.readAloudFlowId = '';
      this.readAloudFlowBookId = '';
    }
  }

  getSnapshot(): ReadAloudStateSnapshot {
    return {
      playbackState: this.playbackState,
      settings: ReadAloudController.copySettings(this.settings),
      hasContext: this.context !== null,
      chapterIndex: this.context?.chapterIndex ?? -1,
      pageIndex: this.context?.pageIndex ?? -1,
      currentCharIndex: this.currentCharIndex,
      chunkStartCharIndex: this.chunkStartCharIndex,
      chunkEndCharIndex: this.chunkEndCharIndex,
      currentPositionMs: this.currentPositionMs,
      totalDurationMs: this.totalDurationMs
    };
  }

  refreshMediaSession(): void {
    this.syncMediaSession();
  }

  scheduleSleepTimer(durationMs: number): ReadAloudSleepTimerSnapshot {
    const safeDurationMs = Math.max(0, Math.floor(durationMs));
    this.cancelSleepTimer();
    if (safeDurationMs <= 0) {
      logger.info(TAG, '听书定时关闭请求无效，已直接取消');
      return this.getSleepTimerSnapshot();
    }

    this.sleepTimerEndAt = Date.now() + safeDurationMs;
    this.sleepTimerHandle = setTimeout(() => {
      this.handleSleepTimerElapsed();
    }, safeDurationMs) as number;
    logger.info(TAG, `已设置听书定时关闭: 时长毫秒=${safeDurationMs}, 结束时间戳=${this.sleepTimerEndAt}`);
    eventBus.publish(GameEvent.READ_ALOUD_STATE_CHANGED, this.createStatePayload('sleep_timer_scheduled'));
    return this.getSleepTimerSnapshot();
  }

  cancelSleepTimer(): void {
    const hadSleepTimer = this.sleepTimerHandle >= 0 || this.sleepTimerEndAt > 0;
    if (this.sleepTimerHandle >= 0) {
      clearTimeout(this.sleepTimerHandle);
      this.sleepTimerHandle = -1;
    }
    if (this.sleepTimerEndAt > 0) {
      logger.info(TAG, '已取消听书定时关闭');
    }
    this.sleepTimerEndAt = 0;
    if (hadSleepTimer) {
      eventBus.publish(GameEvent.READ_ALOUD_STATE_CHANGED, this.createStatePayload('sleep_timer_canceled'));
    }
  }

  getSleepTimerSnapshot(): ReadAloudSleepTimerSnapshot {
    const remainingMs = this.sleepTimerEndAt > 0
      ? Math.max(0, this.sleepTimerEndAt - Date.now())
      : 0;
    return {
      active: remainingMs > 0,
      endAt: this.sleepTimerEndAt,
      remainingMs: remainingMs
    };
  }

  async listVoices(engineType: ReadAloudEngineType): Promise<ReadAloudVoiceOption[]> {
    const targetEngine = this.normalizeEngineType(engineType);
    if (targetEngine === this.backend.engineType) {
      return await this.backend.listVoices();
    }
    return await ReadAloudVoiceCatalog.listVoices(targetEngine);
  }

  private changeState(nextState: ReadAloudPlaybackState, reason: string): void {
    if (this.playbackState === nextState) {
      return;
    }

    const prevState = this.playbackState;
    this.playbackState = nextState;
    this.syncUiStatusForState(reason);
    logger.info(TAG, `听书状态切换: ${prevState} -> ${nextState}, reason=${reason}`);
    this.recordReadAloudFlowEvent(
      ReadAloudFlowEventType.PLAYBACK_STATE_CHANGED,
      reason,
      0,
      true,
      `${prevState}->${nextState}`
    );
    eventBus.publish(GameEvent.READ_ALOUD_STATE_CHANGED, this.createStatePayload(reason));
    this.updateBackgroundKeepAliveTimer();
    this.syncMediaSession();
  }

  private ensureEngineAvailableForStart(): boolean {
    const currentEngine = this.settings.engineType;
    if (ReadAloudAvailability.isAvailableSync(currentEngine, this.settings)) {
      return true;
    }

    const unavailableReason = currentEngine === ReadAloudEngineType.REMOTE
      ? ReadAloudAvailability.getLastRemoteProbeErrorMessage()
      : (currentEngine === ReadAloudEngineType.SYSTEM || currentEngine === ReadAloudEngineType.LEGADO_COMPAT)
        ? ReadAloudAvailability.getLastSystemProbeErrorMessage()
        : '';
    logger.warn(
      TAG,
      unavailableReason.length > 0
        ? `听书引擎不可用: ${currentEngine}, reason=${unavailableReason}`
        : `听书引擎不可用: ${currentEngine}`
    );
    if (currentEngine !== ReadAloudEngineType.SYSTEM) {
      this.settings.engineType = ReadAloudEngineType.SYSTEM;
      this.switchBackend(ReadAloudEngineType.SYSTEM);
      this.backend.applySettings(this.settings);
      logger.info(
        TAG,
        unavailableReason.length > 0
          ? `听书引擎已自动回退到 SYSTEM: source=${currentEngine}, reason=${unavailableReason}`
          : `听书引擎已自动回退到 SYSTEM: source=${currentEngine}`
      );
      return true;
    }

    logger.warn(TAG, 'SYSTEM engine availability cache unavailable, continue start attempt');
    return true;
  }

  private normalizeEngineType(engineType: ReadAloudEngineType): ReadAloudEngineType {
    if (
      engineType === ReadAloudEngineType.SYSTEM ||
      engineType === ReadAloudEngineType.LEGADO_COMPAT ||
      engineType === ReadAloudEngineType.REMOTE
    ) {
      return engineType;
    }
    return ReadAloudEngineType.SYSTEM;
  }

  private static mergeSettingsWithDefaults(settings?: ReadAloudSettings): ReadAloudSettings {
    return normalizeReadAloudSettings(settings ?? DEFAULT_READ_ALOUD_SETTINGS);
  }

  private static copySettings(settings: ReadAloudSettings): ReadAloudSettings {
    return normalizeReadAloudSettings(settings);
  }

  private switchBackend(engineType: ReadAloudEngineType): void {
    const previous = this.backend;
    this.backend = ReadAloudBackendFactory.create(engineType);
    this.bindBackendProgressListener();
    this.backend.applySettings(this.settings);
    this.backend.updateContext(this.context);
    this.syncProgressSnapshotFromBackend();
    this.runBackendTask(previous.release(), `switch_release:${previous.engineType}`);
    logger.info(TAG, `听书后端切换: ${previous.engineType} -> ${engineType}`);
    this.syncMediaSession();
  }

  private bindBackendProgressListener(): void {
    this.backend.setProgressListener((progress: ReadAloudProgressSnapshot): void => {
      this.onBackendProgressUpdated(progress);
    });
    this.backend.setPlaybackListener((event: ReadAloudPlaybackEvent): void => {
      this.onBackendPlaybackEvent(event);
    });
  }

  private onBackendProgressUpdated(progress: ReadAloudProgressSnapshot): void {
    this.currentCharIndex = progress.currentCharIndex;
    this.chunkStartCharIndex = progress.chunkStartCharIndex;
    this.chunkEndCharIndex = progress.chunkEndCharIndex;
    this.currentPositionMs = progress.currentPositionMs;
    this.totalDurationMs = progress.totalDurationMs;
    if (
      this.playbackState === ReadAloudPlaybackState.PLAYING ||
      this.playbackState === ReadAloudPlaybackState.PAUSED
    ) {
      eventBus.publish(GameEvent.READ_ALOUD_STATE_CHANGED, this.createStatePayload('progress_updated'));
    }
    this.syncMediaSession();
  }

  private onBackendPlaybackEvent(event: ReadAloudPlaybackEvent): void {
    if (event.eventType === 'completed') {
      this.syncProgressSnapshotFromBackend();
      this.syncContextResumeCharFromSnapshot(`backend_${event.reason}`);
      if (this.playbackState === ReadAloudPlaybackState.PLAYING) {
        this.changeState(ReadAloudPlaybackState.STOPPED, `backend_${event.reason}`);
        eventBus.publish(GameEvent.READ_ALOUD_STOPPED, this.createStatePayload(`backend_${event.reason}`));
      } else {
        this.syncMediaSession();
      }
      logger.info(TAG, `听书后端通知完成: reason=${event.reason}, char=${event.currentCharIndex}`);
      this.recordReadAloudFlowEvent(
        ReadAloudFlowEventType.PLAYBACK_STATE_CHANGED,
        `backend_completed_${event.reason}`,
        0,
        true,
        `char=${event.currentCharIndex}`
      );
      return;
    }

    if (event.eventType === 'paused_for_error') {
      this.syncProgressSnapshotFromBackend();
      this.syncContextResumeCharFromSnapshot(`backend_${event.reason}`);
      if (this.playbackState === ReadAloudPlaybackState.PLAYING) {
        this.changeState(ReadAloudPlaybackState.PAUSED, `backend_${event.reason}`);
        eventBus.publish(GameEvent.READ_ALOUD_PAUSED, this.createStatePayload(`backend_${event.reason}`));
      } else {
        this.syncMediaSession();
      }
      this.updateUiStatus('error', '听书已因错误暂停', this.formatReadAloudError(event.reason));
      logger.warn(TAG, `听书后端因错误暂停: reason=${event.reason}, char=${event.currentCharIndex}`);
      this.recordReadAloudFlowEvent(
        ReadAloudFlowEventType.ERROR,
        `backend_paused_for_error_${event.reason}`,
        0,
        false,
        `char=${event.currentCharIndex}`
      );
    }
  }

  private syncProgressSnapshotFromBackend(): void {
    const snapshot = this.backend.getProgressSnapshot();
    this.currentCharIndex = snapshot.currentCharIndex;
    this.chunkStartCharIndex = snapshot.chunkStartCharIndex;
    this.chunkEndCharIndex = snapshot.chunkEndCharIndex;
    this.currentPositionMs = snapshot.currentPositionMs;
    this.totalDurationMs = snapshot.totalDurationMs;
  }

  private applyPauseResumeCompensation(reason: string): void {
    if (!this.shouldApplyPauseResumeCompensation(reason)) {
      return;
    }
    if (this.currentCharIndex < 0) {
      return;
    }
    const adjustedCharIndex = Math.max(0, this.currentCharIndex - PAUSE_RESUME_REWIND_CHARS);
    if (adjustedCharIndex === this.currentCharIndex) {
      return;
    }
    this.currentCharIndex = adjustedCharIndex;
  }

  private shouldApplyPauseResumeCompensation(reason: string): boolean {
    switch (reason) {
      case 'manual':
      case 'user_toggle':
      case 'toolbar_toggle':
      case 'floating_ball_toggle':
      case 'player_toggle':
      case 'media_control_pause':
      case 'read_aloud_page_toggle':
        return true;
      default:
        return false;
    }
  }

  private syncContextResumeCharFromSnapshot(reason: string): void {
    if (!this.context || !this.context.content || this.context.content.length <= 0) {
      return;
    }
    if (this.currentCharIndex < 0) {
      return;
    }
    const maxCharIndex = Math.max(0, this.context.content.length - 1);
    const safeCharIndex = Math.max(0, Math.min(Math.floor(this.currentCharIndex), maxCharIndex));
    if (this.context.resumeCharIndex === safeCharIndex) {
      return;
    }
    this.context.resumeCharIndex = safeCharIndex;
    this.backend.updateContext(this.context);
    logger.debug(TAG, `同步听书恢复点: reason=${reason}, char=${safeCharIndex}`);
  }

  private syncMediaSession(): void {
    this.mediaSession.sync(this.getSnapshot(), this.context, this.settings);
  }

  private updateBackgroundKeepAliveTimer(): void {
    const shouldKeepAlive =
      this.settings.continueInBackground &&
      this.playbackState === ReadAloudPlaybackState.PLAYING &&
      this.context !== null;
    if (!shouldKeepAlive) {
      this.clearBackgroundKeepAliveTimer();
      return;
    }
    if (this.backgroundKeepAliveTimer >= 0) {
      return;
    }
    this.backgroundKeepAliveTimer = setInterval((): void => {
      this.handleBackgroundKeepAliveTick();
    }, BACKGROUND_KEEP_ALIVE_INTERVAL_MS);
    logger.info(TAG, `已启用后台听书定时保活: intervalMs=${BACKGROUND_KEEP_ALIVE_INTERVAL_MS}`);
  }

  private clearBackgroundKeepAliveTimer(): void {
    if (this.backgroundKeepAliveTimer < 0) {
      return;
    }
    clearInterval(this.backgroundKeepAliveTimer);
    this.backgroundKeepAliveTimer = -1;
    logger.info(TAG, '已停止后台听书定时保活');
  }

  private handleBackgroundKeepAliveTick(): void {
    if (
      !this.settings.continueInBackground ||
      this.playbackState !== ReadAloudPlaybackState.PLAYING ||
      !this.context
    ) {
      this.clearBackgroundKeepAliveTimer();
      return;
    }
    this.syncProgressSnapshotFromBackend();
    this.syncContextResumeCharFromSnapshot('background_keep_alive_tick');
    this.syncMediaSession();
    eventBus.publish(GameEvent.READ_ALOUD_STATE_CHANGED, this.createStatePayload('background_keep_alive_tick'));
    logger.debug(TAG, `后台听书保活心跳: char=${this.currentCharIndex}`);
  }

  private handleSleepTimerElapsed(): void {
    this.sleepTimerHandle = -1;
    const snapshot = this.getSleepTimerSnapshot();
    if (!snapshot.active && this.sleepTimerEndAt <= 0) {
      return;
    }
    this.sleepTimerEndAt = 0;
    logger.info(TAG, '听书定时关闭已到期，准备停止播放');
    this.stop('sleep_timer_elapsed');
    this.updateUiStatus('sleep_timer', '定时关闭已执行', '播放已停止');
    eventBus.publish(GameEvent.READ_ALOUD_STATE_CHANGED, this.createStatePayload('sleep_timer_elapsed'));
  }

  private skipByChars(delta: number, reason: string): void {
    const baseIndex = this.currentCharIndex >= 0 ? this.currentCharIndex : (this.context?.resumeCharIndex ?? 0);
    this.seekToCharIndex(baseIndex + delta, reason);
  }

  private seekToCharIndex(targetCharIndex: number, reason: string): void {
    if (!this.context || !this.context.content || this.context.content.length <= 0) {
      return;
    }
    const currentContext = this.context;
    const maxCharIndex = Math.max(0, currentContext.content.length - 1);
    const safeTargetIndex = Math.max(0, Math.min(Math.floor(targetCharIndex), maxCharIndex));
    currentContext.resumeCharIndex = safeTargetIndex;

    if (this.playbackState === ReadAloudPlaybackState.PLAYING) {
      this.runBackendTask(
        (async (): Promise<void> => {
          await this.backend.pause();
          this.backend.updateContext(currentContext);
          await this.backend.start();
        })(),
        `seek:${this.settings.engineType}`,
        () => {
          this.syncProgressSnapshotFromBackend();
          eventBus.publish(GameEvent.READ_ALOUD_STATE_CHANGED, this.createStatePayload(reason));
          this.syncMediaSession();
        }
      );
      return;
    }

    this.backend.updateContext(currentContext);
    this.syncProgressSnapshotFromBackend();
    eventBus.publish(GameEvent.READ_ALOUD_STATE_CHANGED, this.createStatePayload(reason));
    this.syncMediaSession();
  }

  private estimateDurationMs(contentLength: number): number {
    if (contentLength <= 0) {
      return 0;
    }
    const speed = this.clamp(this.settings.speed, 0.5, 2.0);
    const charsPerSecond = Math.max(1, BASE_CHARS_PER_SECOND * speed);
    return Math.max(1, Math.round((contentLength / charsPerSecond) * 1000));
  }

  private clamp(value: number, min: number, max: number): number {
    return Math.max(min, Math.min(max, value));
  }

  private runBackendTask(
    task: Promise<void>,
    taskName: string,
    onSuccess?: () => void,
    onError?: (error: Object | string) => void
  ): void {
    const taskStartedAt = Date.now();
    task.then(() => {
      this.recordReadAloudFlowEvent(
        ReadAloudFlowEventType.BACKEND_TASK_COMPLETED,
        taskName,
        Math.max(0, Date.now() - taskStartedAt),
        true,
        '',
        taskName
      );
      if (onSuccess) {
        onSuccess();
      }
    }).catch((error: Object | string) => {
      const errorText = this.formatReadAloudError(error);
      logger.warn(TAG, `听书后端任务失败: ${taskName}, error=${errorText}`);
      this.recordReadAloudFlowEvent(
        ReadAloudFlowEventType.BACKEND_TASK_FAILED,
        taskName,
        Math.max(0, Date.now() - taskStartedAt),
        false,
        errorText,
        taskName
      );
      if (onError) {
        onError(error);
      }
    });
  }

  private isVoiceSelectionChanged(previous: ReadAloudSettings, next: ReadAloudSettings): boolean {
    const prevLanguage = previous.voiceLanguage ?? '';
    const nextLanguage = next.voiceLanguage ?? '';
    const prevPerson = previous.voicePerson ?? -1;
    const nextPerson = next.voicePerson ?? -1;
    const prevOnline = previous.voiceOnline ?? -1;
    const nextOnline = next.voiceOnline ?? -1;
    return prevLanguage !== nextLanguage || prevPerson !== nextPerson || prevOnline !== nextOnline;
  }

  private isRemoteSettingsChanged(previous: ReadAloudSettings, next: ReadAloudSettings): boolean {
    const previousEngine = this.normalizeEngineType(previous.engineType);
    const nextEngine = this.normalizeEngineType(next.engineType);
    if (previousEngine !== ReadAloudEngineType.REMOTE && nextEngine !== ReadAloudEngineType.REMOTE) {
      return false;
    }
    return !isRemoteReadAloudPresetConfigEqual(previous.remote, next.remote);
  }

  private restartPlaybackForConfigurationChange(reason: string): void {
    if (!this.context) {
      return;
    }
    if (this.currentCharIndex >= 0) {
      this.context.resumeCharIndex = this.currentCharIndex;
      this.backend.updateContext(this.context);
    }
    this.runBackendTask(
      this.backend.start(),
      `configuration_restart:${this.settings.engineType}`,
      () => {
        this.syncProgressSnapshotFromBackend();
        eventBus.publish(GameEvent.READ_ALOUD_STATE_CHANGED, this.createStatePayload(reason));
        this.syncMediaSession();
      }
    );
  }

  private formatReadAloudError(error: Object | string): string {
    if (typeof error === 'string') {
      return error;
    }
    const errorLike = error as ReadAloudControllerErrorLike;
    const errorObj = error as Error;
    const hasCode = typeof errorLike.code === 'number' || typeof errorLike.code === 'string';
    if (errorObj.message && errorObj.message.length > 0) {
      if (hasCode) {
        return `code=${errorLike.code}, message=${errorObj.message}`;
      }
      return errorObj.message;
    }
    try {
      const jsonText = JSON.stringify(error);
      if (jsonText && jsonText.length > 0 && jsonText !== '{}') {
        return jsonText;
      }
    } catch (_ignored) {
    }
    if (hasCode) {
      return `code=${errorLike.code}`;
    }
    return String(error);
  }

  private updateUiStatus(phase: string, text: string, detail: string = ''): void {
    AppStorage.setOrCreate(READ_ALOUD_UI_STATUS_PHASE_KEY, phase);
    AppStorage.setOrCreate(READ_ALOUD_UI_STATUS_TEXT_KEY, text);
    AppStorage.setOrCreate(READ_ALOUD_UI_STATUS_DETAIL_KEY, detail);
    AppStorage.setOrCreate(READ_ALOUD_UI_STATUS_UPDATED_AT_KEY, Date.now());
  }

  private clearUiStatus(): void {
    this.updateUiStatus('', '', '');
  }

  private buildUiProgressDetail(): string {
    if (this.context && this.context.content && this.context.content.length > 0 && this.currentCharIndex >= 0) {
      const safeIndex = Math.max(0, Math.min(this.currentCharIndex, this.context.content.length - 1));
      return `第 ${safeIndex + 1}/${this.context.content.length} 字`;
    }
    if (this.context && this.context.chapterIndex >= 0) {
      return `第 ${this.context.chapterIndex + 1} 章`;
    }
    return '';
  }

  private syncUiStatusForState(reason: string): void {
    switch (this.playbackState) {
      case ReadAloudPlaybackState.PLAYING:
        if (this.settings.engineType !== ReadAloudEngineType.REMOTE) {
          this.updateUiStatus('playing', '正在播放', this.buildUiProgressDetail());
        }
        return;
      case ReadAloudPlaybackState.PAUSED:
        if (!reason.startsWith('backend_')) {
          this.updateUiStatus('paused', '已暂停', this.buildUiProgressDetail());
        }
        return;
      case ReadAloudPlaybackState.STOPPED:
        this.updateUiStatus('stopped', '已停止');
        return;
      case ReadAloudPlaybackState.IDLE:
        this.clearUiStatus();
        return;
      default:
        return;
    }
  }

  private createStatePayload(reason: string): ReadAloudStatePayload {
    const payloadBookId = (
      this.context?.bookId && this.context.bookId.trim().length > 0
    ) ? this.context.bookId : this.lastBookId;

    return new ReadAloudStatePayload(
      this.playbackState,
      reason,
      this.settings.engineType,
      payloadBookId,
      this.context?.chapterIndex ?? -1,
      this.context?.pageIndex ?? -1,
      this.currentCharIndex,
      this.chunkStartCharIndex,
      this.chunkEndCharIndex,
      this.currentPositionMs,
      this.totalDurationMs
    );
  }
}
