import { logger } from '../../Utils/Logger';
import { DEFAULT_READ_ALOUD_SETTINGS, ReadAloudEngineType, ReadAloudSettings } from '../../Models/TextReaderModels';
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

const TAG = 'ReadAloudController';
const MEDIA_SKIP_CHARS: number = 420;
const BASE_CHARS_PER_SECOND: number = 11;
const BACKGROUND_KEEP_ALIVE_INTERVAL_MS: number = 15000;

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
  private mediaSession: ReadAloudMediaSession = new ReadAloudMediaSession();
  private backgroundKeepAliveTimer: number = -1;

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

    if (engineChanged) {
      this.switchBackend(nextEngine);
    }
    this.backend.applySettings(this.settings);

    if (!this.settings.enabled && this.playbackState === ReadAloudPlaybackState.PLAYING) {
      this.stop('settings_disabled');
    }
    if (
      (engineChanged || voiceChanged) &&
      this.settings.enabled &&
      this.playbackState === ReadAloudPlaybackState.PLAYING
    ) {
      this.restartPlaybackForVoiceSwitch();
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
      resumeCharIndex: this.context.resumeCharIndex
    };
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
      return;
    }
    if (!this.ensureEngineAvailableForStart()) {
      return;
    }
    if (!this.context || !this.context.content || this.context.content.trim().length === 0) {
      logger.warn(TAG, '听书启动失败：当前没有可朗读内容');
      return;
    }
    if (this.playbackState === ReadAloudPlaybackState.PLAYING) {
      return;
    }
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
      return;
    }
    this.runBackendTask(
      this.backend.pause(),
      `pause:${this.settings.engineType}`,
      () => {
        this.syncProgressSnapshotFromBackend();
        this.syncContextResumeCharFromSnapshot(`pause_after_${reason}`);
      }
    );
    this.syncProgressSnapshotFromBackend();
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
      return;
    }
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
    const durationMs = this.estimateDurationMs(this.context.content.length);
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
    this.runBackendTask(this.backend.release(), `release:${this.settings.engineType}`);
    this.context = null;
    this.backend.updateContext(null);
    this.syncProgressSnapshotFromBackend();
    this.changeState(ReadAloudPlaybackState.IDLE, 'release');
    this.mediaSession.release();
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
      chunkEndCharIndex: this.chunkEndCharIndex
    };
  }

  refreshMediaSession(): void {
    this.syncMediaSession();
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
    logger.info(TAG, `听书状态切换: ${prevState} -> ${nextState}, reason=${reason}`);
    eventBus.publish(GameEvent.READ_ALOUD_STATE_CHANGED, this.createStatePayload(reason));
    this.updateBackgroundKeepAliveTimer();
    this.syncMediaSession();
  }

  private ensureEngineAvailableForStart(): boolean {
    const currentEngine = this.settings.engineType;
    if (ReadAloudAvailability.isAvailableSync(currentEngine)) {
      return true;
    }

    logger.warn(TAG, `听书引擎不可用: ${currentEngine}`);
    if (
      currentEngine !== ReadAloudEngineType.SYSTEM &&
      ReadAloudAvailability.isAvailableSync(ReadAloudEngineType.SYSTEM)
    ) {
      this.settings.engineType = ReadAloudEngineType.SYSTEM;
      this.switchBackend(ReadAloudEngineType.SYSTEM);
      this.backend.applySettings(this.settings);
      logger.info(TAG, '听书引擎已自动回退到 SYSTEM');
      return true;
    }

    logger.warn(TAG, '没有可用听书引擎，忽略启动请求');
    return false;
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
    return {
      enabled: settings?.enabled ?? DEFAULT_READ_ALOUD_SETTINGS.enabled,
      engineType: settings?.engineType ?? DEFAULT_READ_ALOUD_SETTINGS.engineType,
      speed: settings?.speed ?? DEFAULT_READ_ALOUD_SETTINGS.speed,
      pitch: settings?.pitch ?? DEFAULT_READ_ALOUD_SETTINGS.pitch,
      volume: settings?.volume ?? DEFAULT_READ_ALOUD_SETTINGS.volume,
      continueInBackground: settings?.continueInBackground ?? DEFAULT_READ_ALOUD_SETTINGS.continueInBackground,
      autoPlayNextChapter: settings?.autoPlayNextChapter ?? DEFAULT_READ_ALOUD_SETTINGS.autoPlayNextChapter,
      pauseOnManualPageTurn: settings?.pauseOnManualPageTurn ?? DEFAULT_READ_ALOUD_SETTINGS.pauseOnManualPageTurn,
      voiceLanguage: settings?.voiceLanguage ?? DEFAULT_READ_ALOUD_SETTINGS.voiceLanguage,
      voicePerson: settings?.voicePerson ?? DEFAULT_READ_ALOUD_SETTINGS.voicePerson,
      voiceOnline: settings?.voiceOnline ?? DEFAULT_READ_ALOUD_SETTINGS.voiceOnline
    };
  }

  private static copySettings(settings: ReadAloudSettings): ReadAloudSettings {
    return {
      enabled: settings.enabled,
      engineType: settings.engineType,
      speed: settings.speed,
      pitch: settings.pitch,
      volume: settings.volume,
      continueInBackground: settings.continueInBackground,
      autoPlayNextChapter: settings.autoPlayNextChapter,
      pauseOnManualPageTurn: settings.pauseOnManualPageTurn,
      voiceLanguage: settings.voiceLanguage,
      voicePerson: settings.voicePerson,
      voiceOnline: settings.voiceOnline
    };
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
      logger.warn(TAG, `听书后端因错误暂停: reason=${event.reason}, char=${event.currentCharIndex}`);
    }
  }

  private syncProgressSnapshotFromBackend(): void {
    const snapshot = this.backend.getProgressSnapshot();
    this.currentCharIndex = snapshot.currentCharIndex;
    this.chunkStartCharIndex = snapshot.chunkStartCharIndex;
    this.chunkEndCharIndex = snapshot.chunkEndCharIndex;
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
    task.then(() => {
      if (onSuccess) {
        onSuccess();
      }
    }).catch((error: Object | string) => {
      const errorText = this.formatReadAloudError(error);
      logger.warn(TAG, `听书后端任务失败: ${taskName}, error=${errorText}`);
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

  private restartPlaybackForVoiceSwitch(): void {
    if (!this.context) {
      return;
    }
    if (this.currentCharIndex >= 0) {
      this.context.resumeCharIndex = this.currentCharIndex;
      this.backend.updateContext(this.context);
    }
    this.runBackendTask(
      this.backend.start(),
      `voice_switch_restart:${this.settings.engineType}`,
      () => {
        this.syncProgressSnapshotFromBackend();
        eventBus.publish(GameEvent.READ_ALOUD_STATE_CHANGED, this.createStatePayload('voice_changed'));
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
      this.chunkEndCharIndex
    );
  }
}
