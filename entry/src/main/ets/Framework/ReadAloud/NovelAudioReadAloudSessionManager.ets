import { SafeFileUtils } from 'manxia_core/src/main/ets/Utils/SafeFileUtils';
import { SafeUtils } from 'manxia_core/src/main/ets/Utils/SafeUtils';
import { media } from '@kit.MediaKit';
import { fileIo } from '@kit.CoreFileKit';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { getNovelSourceManager } from '../Novel/NovelSourceManager';
import { getNovelChapterCacheManager } from '../Novel/NovelChapterCacheManager';
import { LegadoBook, LegadoBookSourceType, LegadoChapter } from 'manxia_novel/src/main/ets/Framework/Novel/LegadoSourceTypes';
import { DEFAULT_READ_ALOUD_SETTINGS, ReadAloudSettings } from 'manxia_core/src/main/ets/Models/TextReaderModels';
import { loadGlobalReadAloudSettings } from './ReadAloudSettingsStore';
import { SettingsManager } from 'manxia_core/src/main/ets/Framework/Managers/SettingsManager';
import { ReadAloudMediaCommandListener, ReadAloudMediaSession } from './ReadAloudMediaSession';
import { ReadAloudPlaybackState, ReadAloudSessionContext, ReadAloudStateSnapshot } from './ReadAloudTypes';
import { ReadAloudFlowMonitor } from 'manxia_novel/src/main/ets/Framework/ReadAloud/ReadAloudFlowMonitor';
import {
  ReadAloudFlowEventType,
  ReadAloudFlowMode,
  ReadAloudFlowSessionInfo,
  ReadAloudFlowSeverity
} from 'manxia_novel/src/main/ets/Framework/ReadAloud/ReadAloudFlowTypes';
import { DetailOpenFlowMonitor } from 'manxia_reader_ui/src/main/ets/Framework/Reader/DetailOpenFlowMonitor';
import { LegadoWorkflowOutputKind } from 'manxia_novel/src/main/ets/Framework/Novel/LegadoCompatibilityTypes';
import {
  DetailOpenFlowEventType,
  DetailOpenFlowTargetKind
} from 'manxia_reader_ui/src/main/ets/Framework/Reader/DetailOpenFlowTypes';

const TAG = 'NovelAudioSessionManager';
const CHAPTER_LIST_CACHE_MAX_AGE_HOURS: number = 48;
const WAIT_STATE_TIMEOUT_MS: number = 4600;
const PLAYER_OPERATION_TIMEOUT_MS: number = 5000;
const PLAYER_POST_PLAY_WAIT_TIMEOUT_MS: number = 2600;
const AUDIO_PROGRESS_PERSIST_INTERVAL_MS: number = 1200;
const AUDIO_PROGRESS_KEY_PREFIX: string = 'novel_audio_read_aloud_progress_';

type AudioJsonValue = string | number | boolean | Object | Array<Object> | null;
type AudioJsonRecord = Record<string, AudioJsonValue>;

export interface NovelAudioReadAloudLaunchParams {
  sourceId: string;
  bookUrl: string;
  bookName: string;
  chapterUrl: string;
  chapterTitle: string;
  chapterIndex: number;
  totalChapters: number;
  tocUrl?: string;
  author?: string;
  coverUrl?: string;
  autoStartReadAloud?: boolean;
  readerOpenFlowId?: string;
}

export interface NovelAudioReadAloudSnapshot {
  hasSession: boolean;
  initialized: boolean;
  isLoading: boolean;
  loadErrorMessage: string;
  sourceId: string;
  bookUrl: string;
  bookId: string;
  bookName: string;
  author: string;
  coverUrl: string;
  chapterTitle: string;
  chapterIndex: number;
  totalChapters: number;
  chapterUrl: string;
  audioSourceUrl: string;
  audioDurationMs: number;
  audioPositionMs: number;
  isPlaying: boolean;
  audioChapterCached: boolean;
  isCachingCurrentChapterAudio: boolean;
}

export type NovelAudioReadAloudStateListener = (snapshot: NovelAudioReadAloudSnapshot) => void;

class NovelAudioMediaCommandBridge implements ReadAloudMediaCommandListener {
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

export class NovelAudioReadAloudSessionManager {
  private static instance: NovelAudioReadAloudSessionManager | null = null;

  private readonly sourceManager = getNovelSourceManager();
  private readonly cacheManager = getNovelChapterCacheManager();
  private readonly settingsManager = SettingsManager.getInstance();
  private readonly mediaSession: ReadAloudMediaSession = new ReadAloudMediaSession();

  private listeners: NovelAudioReadAloudStateListener[] = [];

  private readAloudSettings: ReadAloudSettings = DEFAULT_READ_ALOUD_SETTINGS;
  private sourceId: string = '';
  private bookUrl: string = '';
  private bookId: string = '';
  private bookName: string = '';
  private author: string = '';
  private coverUrl: string = '';
  private tocUrl: string = '';
  private chapterUrl: string = '';
  private chapterTitle: string = '';
  private chapterList: LegadoChapter[] = [];
  private totalChapters: number = 0;
  private currentChapterIndex: number = 0;
  private isLoading: boolean = false;
  private initialized: boolean = false;
  private loadErrorMessage: string = '';
  private audioSourceUrl: string = '';
  private audioDurationMs: number = 0;
  private audioPositionMs: number = 0;
  private isPlaying: boolean = false;
  private audioChapterCached: boolean = false;
  private isCachingCurrentChapterAudio: boolean = false;
  private sessionToken: number = 0;
  private autoSwitchingChapter: boolean = false;
  private chapterContent: string = '';
  private pendingResumePositionMs: number = 0;
  private mediaPlaybackState: ReadAloudPlaybackState = ReadAloudPlaybackState.IDLE;
  private lastProgressPersistTime: number = 0;
  private readerOpenFlowId: string = '';
  private readAloudFlowId: string = '';

  private audioPlayer: media.AVPlayer | null = null;
  private audioStateChangeHandler: ((state: media.AVPlayerState, reason: media.StateChangeReason) => void) | null = null;
  private audioTimeUpdateHandler: ((timeMs: number) => void) | null = null;
  private audioErrorHandler: ((error: Object) => void) | null = null;
  private localAudioSourceFile: fileIo.File | null = null;
  private localAudioSourcePath: string = '';

  private constructor() {
    const mediaCommandListener: ReadAloudMediaCommandListener = new NovelAudioMediaCommandBridge(
      (): void => {
        this.handleMediaPlayCommand();
      },
      (): void => {
        this.handleMediaPauseCommand();
      },
      (): void => {
        this.handleMediaStopCommand();
      },
      (): void => {
        this.handleMediaNextCommand();
      },
      (): void => {
        this.handleMediaPreviousCommand();
      },
      (positionMs: number): void => {
        this.handleMediaSeekCommand(positionMs);
      }
    );
    this.mediaSession.setCommandListener(mediaCommandListener);
  }

  static getInstance(): NovelAudioReadAloudSessionManager {
    if (!NovelAudioReadAloudSessionManager.instance) {
      NovelAudioReadAloudSessionManager.instance = new NovelAudioReadAloudSessionManager();
    }
    return NovelAudioReadAloudSessionManager.instance;
  }

  subscribe(listener: NovelAudioReadAloudStateListener): void {
    if (this.listeners.includes(listener)) {
      return;
    }
    this.listeners.push(listener);
  }

  unsubscribe(listener: NovelAudioReadAloudStateListener): void {
    this.listeners = this.listeners.filter((item: NovelAudioReadAloudStateListener) => item !== listener);
  }

  hasActiveSession(): boolean {
    return this.sourceId.length > 0 && this.bookUrl.length > 0 && this.initialized;
  }

  isAudioSource(sourceId: string): boolean {
    if (!sourceId || sourceId.length <= 0) {
      return false;
    }
    const source = this.sourceManager.getSource(sourceId);
    return !!source && source.bookSourceType === LegadoBookSourceType.AUDIO;
  }

  getSnapshot(): NovelAudioReadAloudSnapshot {
    return {
      hasSession: this.sourceId.length > 0 && this.bookUrl.length > 0,
      initialized: this.initialized,
      isLoading: this.isLoading,
      loadErrorMessage: this.loadErrorMessage,
      sourceId: this.sourceId,
      bookUrl: this.bookUrl,
      bookId: this.bookId,
      bookName: this.bookName,
      author: this.author,
      coverUrl: this.coverUrl,
      chapterTitle: this.chapterTitle,
      chapterIndex: this.currentChapterIndex,
      totalChapters: this.totalChapters,
      chapterUrl: this.chapterUrl,
      audioSourceUrl: this.audioSourceUrl,
      audioDurationMs: this.audioDurationMs,
      audioPositionMs: this.audioPositionMs,
      isPlaying: this.isPlaying,
      audioChapterCached: this.audioChapterCached,
      isCachingCurrentChapterAudio: this.isCachingCurrentChapterAudio
    };
  }

  private ensureAudioReadAloudFlowSession(reason: string): void {
    if (this.sourceId.length <= 0 || this.bookUrl.length <= 0) {
      return;
    }
    if (this.readAloudFlowId.length > 0) {
      return;
    }
    const info = new ReadAloudFlowSessionInfo();
    info.readerOpenFlowId = this.readerOpenFlowId;
    info.mode = ReadAloudFlowMode.AUDIO_SOURCE;
    info.sourceId = this.sourceId;
    info.bookId = this.bookId;
    info.bookTitle = this.bookName;
    info.chapterId = this.chapterUrl;
    info.chapterTitle = this.chapterTitle;
    info.chapterIndex = this.currentChapterIndex;
    info.totalChapters = this.totalChapters;
    info.engineType = 'audio_source';
    this.readAloudFlowId = ReadAloudFlowMonitor.getInstance().startSession(info);
    this.recordAudioReadAloudFlowEvent(ReadAloudFlowEventType.AUDIO_SESSION_STARTED, reason, 0, true, '');
  }

  private recordAudioReadAloudFlowEvent(
    eventType: ReadAloudFlowEventType,
    reason: string,
    elapsedMs: number,
    success: boolean,
    detail: string,
    playerOperation: string = '',
    cacheKind: string = ''
  ): void {
    this.ensureAudioReadAloudFlowSession(reason);
    if (this.readAloudFlowId.length <= 0) {
      return;
    }
    const event = ReadAloudFlowMonitor.getInstance().createEvent(
      this.readAloudFlowId,
      eventType,
      ReadAloudFlowMode.AUDIO_SOURCE,
      this.bookId,
      this.currentChapterIndex,
      reason
    );
    event.readerOpenFlowId = this.readerOpenFlowId;
    event.sourceId = this.sourceId;
    event.chapterId = this.chapterUrl;
    event.chapterTitle = this.chapterTitle;
    event.totalChapters = this.totalChapters;
    event.positionMs = this.audioPositionMs;
    event.durationMs = this.audioDurationMs;
    event.engineType = 'audio_source';
    event.playerOperation = playerOperation;
    event.cacheKind = cacheKind;
    event.elapsedMs = Math.max(0, elapsedMs);
    event.success = success;
    event.detail = detail;
    if (!success) {
      event.severity = ReadAloudFlowSeverity.ERROR;
      event.errorMessage = detail;
    }
    if (event.elapsedMs > 0) {
      event.metricName = `audio_read_aloud.${eventType}`;
      event.metricValue = event.elapsedMs;
      event.metricUnit = 'ms';
    }
    ReadAloudFlowMonitor.getInstance().record(event);
  }

  private markDetailOpenAudioReady(reason: string, success: boolean, detail: string): void {
    if (this.readerOpenFlowId.length <= 0) {
      return;
    }
    const event = DetailOpenFlowMonitor.getInstance().createEvent(
      this.readerOpenFlowId,
      success ? DetailOpenFlowEventType.READER_READY : DetailOpenFlowEventType.READER_FAILED,
      this.bookId,
      this.chapterUrl,
      this.currentChapterIndex,
      reason
    );
    event.targetKind = DetailOpenFlowTargetKind.READ_ALOUD;
    event.routeName = 'ReadAloudPlayerPage';
    event.chapterTitle = this.chapterTitle;
    event.elapsedMs = DetailOpenFlowMonitor.getInstance().getSessionElapsedMs(this.readerOpenFlowId);
    event.success = success;
    event.detail = detail;
    if (!success) {
      event.errorMessage = detail;
    }
    DetailOpenFlowMonitor.getInstance().record(event);
    DetailOpenFlowMonitor.getInstance().endSession(this.readerOpenFlowId, reason);
  }

  async startSession(params: NovelAudioReadAloudLaunchParams): Promise<boolean> {
    const sessionStartedAt = Date.now();
    if (!params.sourceId || !params.bookUrl) {
      this.loadErrorMessage = '听书会话启动参数缺失';
      this.publishState();
      return false;
    }
    if (!this.isAudioSource(params.sourceId)) {
      logger.debug(TAG, `非听书源，跳过听书会话初始化: 图源=${params.sourceId}`);
      return false;
    }

    this.readAloudSettings = loadGlobalReadAloudSettings(this.settingsManager);
    const sameSession = this.sourceId === params.sourceId && this.bookUrl === params.bookUrl;
    if (!sameSession) {
      this.releasePlayerOnly();
    }

    this.sourceId = params.sourceId;
    this.bookUrl = params.bookUrl;
    this.readerOpenFlowId = params.readerOpenFlowId || '';
    this.bookName = params.bookName || this.bookName;
    this.author = params.author || this.author;
    this.coverUrl = params.coverUrl || this.coverUrl;
    this.tocUrl = params.tocUrl || params.bookUrl;
    this.chapterUrl = params.chapterUrl || this.chapterUrl;
    this.chapterTitle = params.chapterTitle || this.chapterTitle;
    this.totalChapters = Math.max(0, params.totalChapters);
    this.currentChapterIndex = Math.max(0, params.chapterIndex);
    this.bookId = `${params.sourceId}_${encodeURIComponent(params.bookUrl)}`;
    if (!sameSession && this.readAloudFlowId.length > 0) {
      ReadAloudFlowMonitor.getInstance().endSession(this.readAloudFlowId, 'new_audio_session');
      this.readAloudFlowId = '';
    }
    this.ensureAudioReadAloudFlowSession('start_session');
    this.applyPersistedProgressForLaunch(params.chapterIndex, sameSession);
    this.loadErrorMessage = '';
    this.isLoading = true;
    this.initialized = false;
    this.updateMediaPlaybackState(ReadAloudPlaybackState.PAUSED, 'start_session_prepare');
    this.sessionToken += 1;
    const token = this.sessionToken;
    logger.info(TAG, `启动听书小说会话: 图源=${params.sourceId}, 章节索引=${this.currentChapterIndex}, 自动播放=${params.autoStartReadAloud === true}`);
    this.publishState();

    try {
      const chapterListStartedAt = Date.now();
      await this.loadChapterList(token);
      this.recordAudioReadAloudFlowEvent(
        ReadAloudFlowEventType.AUDIO_CONTENT_READY,
        'chapter_list_ready',
        Math.max(0, Date.now() - chapterListStartedAt),
        this.chapterList.length > 0,
        `chapters=${this.chapterList.length}`
      );
      if (!this.isTokenValid(token)) {
        logger.warn(TAG, `听书会话初始化被新会话覆盖（目录阶段）: 请求令牌=${token}, 当前令牌=${this.sessionToken}`);
        return this.hasActiveSession();
      }
      const chapterContentStartedAt = Date.now();
      const loaded = await this.loadChapterContent(this.currentChapterIndex, token);
      this.recordAudioReadAloudFlowEvent(
        ReadAloudFlowEventType.AUDIO_CONTENT_READY,
        loaded ? 'audio_content_ready' : 'audio_content_failed',
        Math.max(0, Date.now() - chapterContentStartedAt),
        loaded,
        `audioSource=${this.audioSourceUrl.length > 0}, cached=${this.audioChapterCached === true}`
      );
      if (!this.isTokenValid(token)) {
        logger.warn(TAG, `听书会话初始化被新会话覆盖（章节阶段）: 请求令牌=${token}, 当前令牌=${this.sessionToken}`);
        return this.hasActiveSession();
      }
      if (!loaded) {
        this.isLoading = false;
        this.initialized = false;
        this.updateMediaPlaybackState(ReadAloudPlaybackState.STOPPED, 'start_session_load_failed');
        logger.warn(
          TAG,
          `听书会话初始化中止: 章节内容加载返回false, 章节索引=${this.currentChapterIndex}, 章节地址=${this.chapterUrl.substring(0, 180)}, 错误=${this.loadErrorMessage}`
        );
        this.publishState();
        this.markDetailOpenAudioReady('audio_content_load_failed', false, this.loadErrorMessage);
        return false;
      }
      this.isLoading = false;
      this.initialized = true;
      if (!this.isPlaying) {
        this.updateMediaPlaybackState(ReadAloudPlaybackState.PAUSED, 'start_session_loaded');
      }
      this.publishState();
      logger.info(TAG, `听书会话初始化完成: 书籍标识=${this.bookId}, 章节索引=${this.currentChapterIndex}, 已解析音频地址=${this.audioSourceUrl.length > 0}`);
      this.recordAudioReadAloudFlowEvent(
        ReadAloudFlowEventType.AUDIO_SESSION_STARTED,
        'start_session_loaded',
        Math.max(0, Date.now() - sessionStartedAt),
        true,
        `autoStart=${params.autoStartReadAloud === true}`
      );
      this.markDetailOpenAudioReady('audio_session_ready', true, '');
      if (params.autoStartReadAloud === true) {
        const started = await this.play();
        logger.info(TAG, `听书会话自动播放结果: 成功=${started}, 章节索引=${this.currentChapterIndex}`);
      }
      return true;
    } catch (error) {
      this.isLoading = false;
      this.initialized = false;
      this.loadErrorMessage = `听书会话初始化失败: ${String(error)}`;
      this.updateMediaPlaybackState(ReadAloudPlaybackState.STOPPED, 'start_session_error');
      logger.error(TAG, this.loadErrorMessage);
      this.recordAudioReadAloudFlowEvent(
        ReadAloudFlowEventType.ERROR,
        'start_session_error',
        Math.max(0, Date.now() - sessionStartedAt),
        false,
        String(error)
      );
      this.markDetailOpenAudioReady('audio_session_failed', false, String(error));
      this.publishState();
      return false;
    }
  }

  async togglePlayPause(): Promise<void> {
    if (this.isPlaying) {
      await this.pause();
    } else {
      await this.play();
    }
  }

  async play(): Promise<boolean> {
    if (!this.audioSourceUrl || this.audioSourceUrl.length <= 0) {
      this.loadErrorMessage = '当前章节没有可播放的音频地址';
      this.publishState();
      this.recordAudioReadAloudFlowEvent(ReadAloudFlowEventType.START_REQUESTED, 'play_without_audio_source', 0, false, this.loadErrorMessage);
      return false;
    }
    const playStartedAt = Date.now();
    this.recordAudioReadAloudFlowEvent(ReadAloudFlowEventType.START_REQUESTED, 'play', 0, true, '');
    try {
      const player = await this.ensureAudioPlayer();
      const state = player.state;
      logger.debug(TAG, `请求播放音频: 状态=${state}, 章节索引=${this.currentChapterIndex}, 地址=${this.audioSourceUrl.substring(0, 120)}`);
      if (state === 'playing') {
        this.isPlaying = true;
        this.loadErrorMessage = '';
        this.updateMediaPlaybackState(ReadAloudPlaybackState.PLAYING, 'play_already_playing');
        this.publishState();
        return true;
      }

      if (state === 'paused' || state === 'prepared') {
        await this.restorePendingResumePositionIfNeeded(player, 'play_resume');
        await this.invokeAudioPlayerOperationWithTimeout('play_resume', PLAYER_OPERATION_TIMEOUT_MS, () => player.play());
      } else if (state === 'completed') {
        await this.seekAudioPlayer(player, 0);
        this.pendingResumePositionMs = 0;
        await this.invokeAudioPlayerOperationWithTimeout('play_from_completed', PLAYER_OPERATION_TIMEOUT_MS, () => player.play());
      } else if (state === 'initialized' || state === 'stopped') {
        await this.invokeAudioPlayerOperationWithTimeout('play_prepare', PLAYER_OPERATION_TIMEOUT_MS, () => player.prepare());
        await this.waitForAudioPlayerState(player, ['prepared', 'playing'], WAIT_STATE_TIMEOUT_MS, 'play_prepare');
        await this.restorePendingResumePositionIfNeeded(player, 'play_prepare');
        await this.invokeAudioPlayerOperationWithTimeout('play_after_prepare', PLAYER_OPERATION_TIMEOUT_MS, () => player.play());
      } else {
        await this.prepareAudioPlayerWithUrl(this.audioSourceUrl, true);
      }

      if (player.state !== 'playing') {
        try {
          await this.waitForAudioPlayerState(player, 'playing', PLAYER_POST_PLAY_WAIT_TIMEOUT_MS, 'play_wait_playing');
        } catch (error) {
          logger.warn(TAG, `播放请求后等待playing状态超时: ${String(error)}`);
        }
      }

      if (player.state !== 'playing') {
        logger.warn(TAG, `音频播放器仍未进入playing状态，重试一次prepare+play: 状态=${player.state}`);
        await this.prepareAudioPlayerWithUrl(this.audioSourceUrl, true);
      }

      this.syncAudioProgressFromPlayer();
      this.isPlaying = player.state === 'playing';
      if (!this.isPlaying) {
        this.loadErrorMessage = '音频播放未进入playing状态，请点击播放重试';
        this.updateMediaPlaybackState(ReadAloudPlaybackState.PAUSED, 'play_not_playing');
      } else {
        this.loadErrorMessage = '';
        this.updateMediaPlaybackState(ReadAloudPlaybackState.PLAYING, 'play_success');
      }
      this.publishState();
      this.recordAudioReadAloudFlowEvent(
        ReadAloudFlowEventType.AUDIO_PLAYER_OPERATION,
        'play',
        Math.max(0, Date.now() - playStartedAt),
        this.isPlaying,
        `state=${player.state}`,
        'play'
      );
      return this.isPlaying;
    } catch (error) {
      this.isPlaying = false;
      this.loadErrorMessage = `播放失败: ${String(error)}`;
      this.updateMediaPlaybackState(ReadAloudPlaybackState.PAUSED, 'play_failed');
      logger.warn(TAG, this.loadErrorMessage);
      this.publishState();
      this.recordAudioReadAloudFlowEvent(
        ReadAloudFlowEventType.AUDIO_PLAYER_OPERATION,
        'play_failed',
        Math.max(0, Date.now() - playStartedAt),
        false,
        String(error),
        'play'
      );
      return false;
    }
  }

  async pause(): Promise<void> {
    const pauseStartedAt = Date.now();
    this.recordAudioReadAloudFlowEvent(ReadAloudFlowEventType.PAUSE_REQUESTED, 'pause', 0, true, '');
    if (!this.audioPlayer) {
      this.isPlaying = false;
      this.updateMediaPlaybackState(ReadAloudPlaybackState.PAUSED, 'pause_without_player');
      this.publishState();
      this.recordAudioReadAloudFlowEvent(ReadAloudFlowEventType.AUDIO_PLAYER_OPERATION, 'pause_without_player', 0, true, '', 'pause');
      return;
    }
    if (this.audioPlayer.state === 'playing') {
      await this.audioPlayer.pause();
    }
    this.syncAudioProgressFromPlayer();
    this.isPlaying = false;
    this.updateMediaPlaybackState(ReadAloudPlaybackState.PAUSED, 'pause_success');
    this.publishState();
    this.recordAudioReadAloudFlowEvent(
      ReadAloudFlowEventType.AUDIO_PLAYER_OPERATION,
      'pause_success',
      Math.max(0, Date.now() - pauseStartedAt),
      true,
      '',
      'pause'
    );
  }

  async stop(): Promise<void> {
    const stopStartedAt = Date.now();
    this.recordAudioReadAloudFlowEvent(ReadAloudFlowEventType.STOP_REQUESTED, 'stop', 0, true, '');
    if (!this.audioPlayer) {
      this.isPlaying = false;
      this.audioPositionMs = 0;
      this.pendingResumePositionMs = 0;
      this.updateMediaPlaybackState(ReadAloudPlaybackState.STOPPED, 'stop_without_player');
      this.publishState();
      this.recordAudioReadAloudFlowEvent(ReadAloudFlowEventType.AUDIO_PLAYER_OPERATION, 'stop_without_player', 0, true, '', 'stop');
      return;
    }
    try {
      if (this.audioPlayer.state === 'playing') {
        await this.audioPlayer.pause();
      }
      await this.seekAudioPlayer(this.audioPlayer, 0);
    } catch (_error) {
    }
    this.syncAudioProgressFromPlayer();
    this.isPlaying = false;
    this.pendingResumePositionMs = 0;
    this.updateMediaPlaybackState(ReadAloudPlaybackState.STOPPED, 'stop_success');
    this.publishState();
    this.recordAudioReadAloudFlowEvent(
      ReadAloudFlowEventType.AUDIO_PLAYER_OPERATION,
      'stop_success',
      Math.max(0, Date.now() - stopStartedAt),
      true,
      '',
      'stop'
    );
  }

  handlePageHide(isInBackground: boolean): void {
    if (!isInBackground) {
      return;
    }
    this.readAloudSettings = loadGlobalReadAloudSettings(this.settingsManager);
    if (!this.readAloudSettings.continueInBackground && this.isPlaying) {
      logger.info(TAG, '应用进入后台且未开启后台继续播放，自动暂停听书');
      void this.pause();
    }
  }

  async seekToPosition(positionMs: number, reason: string = 'manual_seek'): Promise<boolean> {
    if (!this.audioPlayer) {
      this.recordAudioReadAloudFlowEvent(ReadAloudFlowEventType.SEEK_REQUESTED, reason, 0, false, 'audio_player_missing');
      return false;
    }
    const seekStartedAt = Date.now();
    this.recordAudioReadAloudFlowEvent(ReadAloudFlowEventType.SEEK_REQUESTED, reason, 0, true, `positionMs=${positionMs}`);
    const safePositionMs = Math.max(0, Math.floor(positionMs));
    await this.seekAudioPlayer(this.audioPlayer, safePositionMs);
    this.syncAudioProgressFromPlayer();
    if (this.mediaPlaybackState === ReadAloudPlaybackState.STOPPED && this.audioPositionMs > 0) {
      this.updateMediaPlaybackState(ReadAloudPlaybackState.PAUSED, `seek_${reason}`);
    }
    logger.info(TAG, `音频定位完成: 原因=${reason}, 位置毫秒=${this.audioPositionMs}, 章节=${this.currentChapterIndex + 1}`);
    this.publishState();
    this.recordAudioReadAloudFlowEvent(
      ReadAloudFlowEventType.AUDIO_PLAYER_OPERATION,
      `seek_${reason}`,
      Math.max(0, Date.now() - seekStartedAt),
      true,
      `positionMs=${this.audioPositionMs}`,
      'seek'
    );
    return true;
  }

  async playNextChapter(forceStart: boolean = false): Promise<boolean> {
    if (this.totalChapters > 0 && this.currentChapterIndex >= this.totalChapters - 1) {
      return false;
    }
    return await this.switchToChapter(this.currentChapterIndex + 1, forceStart);
  }

  async playPreviousChapter(forceStart: boolean = false): Promise<boolean> {
    if (this.currentChapterIndex <= 0) {
      return false;
    }
    return await this.switchToChapter(this.currentChapterIndex - 1, forceStart);
  }
  async cacheCurrentChapterAudio(): Promise<boolean> {
    if (this.isCachingCurrentChapterAudio || !this.sourceId || !this.bookId) {
      return false;
    }
    this.isCachingCurrentChapterAudio = true;
    this.publishState();
    try {
      const alreadyCached = await this.isChapterAudioCachedWithLegacyFallback(this.currentChapterIndex);
      if (alreadyCached) {
        this.audioChapterCached = true;
        this.publishState();
        return true;
      }
      const chapter = this.getCurrentChapterForCache();
      const success = await this.cacheManager.cacheChapter(this.sourceId, this.bookId, chapter);
      if (!success) {
        return false;
      }
      this.audioChapterCached = true;
      const localAudioPath = await this.resolveChapterAudioCachePathWithLegacyFallback(this.currentChapterIndex);
      if (localAudioPath && localAudioPath.length > 0 && !this.isPlaying) {
        this.audioSourceUrl = this.toAudioPlayerSourceUrl(localAudioPath);
        await this.prepareAudioPlayerWithUrl(this.audioSourceUrl, false);
      }
      this.publishState();
      return true;
    } catch (error) {
      logger.error(TAG, `缓存章节音频失败: ${String(error)}`);
      return false;
    } finally {
      this.isCachingCurrentChapterAudio = false;
      this.publishState();
    }
  }

  releaseSession(reason: string = 'manual_release'): void {
    logger.info(TAG, `释放听书会话: 原因=${reason}, 书籍标识=${this.bookId}, 章节索引=${this.currentChapterIndex}`);
    this.persistPlaybackProgress(true);
    this.releasePlayerOnly();
    this.sourceId = '';
    this.bookUrl = '';
    this.bookId = '';
    this.bookName = '';
    this.author = '';
    this.coverUrl = '';
    this.tocUrl = '';
    this.chapterUrl = '';
    this.chapterTitle = '';
    this.chapterList = [];
    this.totalChapters = 0;
    this.currentChapterIndex = 0;
    this.isLoading = false;
    this.initialized = false;
    this.loadErrorMessage = '';
    this.audioSourceUrl = '';
    this.audioDurationMs = 0;
    this.audioPositionMs = 0;
    this.isPlaying = false;
    this.audioChapterCached = false;
    this.isCachingCurrentChapterAudio = false;
    this.pendingResumePositionMs = 0;
    this.lastProgressPersistTime = 0;
    this.sessionToken += 1;
    this.updateMediaPlaybackState(ReadAloudPlaybackState.IDLE, 'release_session');
    if (this.readAloudFlowId.length > 0) {
      ReadAloudFlowMonitor.getInstance().endSession(this.readAloudFlowId, reason);
      this.readAloudFlowId = '';
    }
    this.readerOpenFlowId = '';
    this.publishState();
    this.mediaSession.release();
  }

  private async switchToChapter(targetIndex: number, forceStart: boolean): Promise<boolean> {
    if (targetIndex < 0 || (this.totalChapters > 0 && targetIndex >= this.totalChapters)) {
      return false;
    }
    const shouldRestart = this.isPlaying || forceStart;
    if (this.isPlaying) {
      await this.pause();
    }
    this.pendingResumePositionMs = 0;
    this.isLoading = true;
    this.publishState();
    const token = this.sessionToken;
    const loaded = await this.loadChapterContent(targetIndex, token);
    this.isLoading = false;
    if (!loaded) {
      this.isPlaying = false;
      this.updateMediaPlaybackState(ReadAloudPlaybackState.STOPPED, 'switch_chapter_failed');
      this.publishState();
      return false;
    }
    if (shouldRestart) {
      await this.play();
    } else {
      this.updateMediaPlaybackState(ReadAloudPlaybackState.PAUSED, 'switch_chapter_loaded');
      this.publishState();
    }
    return true;
  }

  private isTokenValid(token: number): boolean {
    return token === this.sessionToken;
  }

  private publishState(): void {
    const snapshot = this.getSnapshot();
    this.syncMediaSession();
    this.persistPlaybackProgress(false);
    for (let index = 0; index < this.listeners.length; index++) {
      try {
        this.listeners[index](snapshot);
      } catch (error) {
        logger.warn(TAG, `听书状态监听回调失败: ${String(error)}`);
      }
    }
  }

  private getCurrentChapterForCache(): LegadoChapter {
    if (this.chapterList.length > this.currentChapterIndex) {
      const chapter = this.chapterList[this.currentChapterIndex];
      return {
        id: chapter.id || '',
        bookUrl: chapter.bookUrl || this.bookUrl,
        url: chapter.url || this.chapterUrl,
        title: chapter.title || this.chapterTitle,
        index: this.currentChapterIndex
      };
    }
    return {
      id: '',
      bookUrl: this.bookUrl,
      url: this.chapterUrl,
      title: this.chapterTitle,
      index: this.currentChapterIndex
    };
  }

  private applyResolvedChapterList(chapters: LegadoChapter[]): void {
    if (chapters.length <= 0) {
      return;
    }
    this.chapterList = chapters;
    this.totalChapters = chapters.length;
    const safeIndex = Math.max(0, Math.min(this.currentChapterIndex, chapters.length - 1));
    this.currentChapterIndex = safeIndex;
    const currentChapter = chapters[safeIndex];
    if (currentChapter.title && currentChapter.title.length > 0) {
      this.chapterTitle = currentChapter.title;
    }
    if (currentChapter.url && currentChapter.url.length > 0) {
      this.chapterUrl = currentChapter.url;
    }
  }

  private async loadCachedChapterList(): Promise<LegadoChapter[] | null> {
    try {
      const cachedByCompositeBookId = await this.cacheManager.getCachedChapterList(this.bookId, CHAPTER_LIST_CACHE_MAX_AGE_HOURS);
      if (cachedByCompositeBookId && cachedByCompositeBookId.length > 0) {
        return cachedByCompositeBookId;
      }
      const cachedByBookUrl = await this.cacheManager.getCachedChapterList(this.bookUrl, CHAPTER_LIST_CACHE_MAX_AGE_HOURS);
      if (cachedByBookUrl && cachedByBookUrl.length > 0) {
        return cachedByBookUrl;
      }
      return null;
    } catch (error) {
      logger.warn(TAG, `读取章节列表缓存失败: ${String(error)}`);
      return null;
    }
  }

  private async resolveChapterAudioCachePathWithLegacyFallback(chapterIndex: number): Promise<string | null> {
    const pathByBookId = await this.cacheManager.getChapterAudioCachePath(this.bookId, chapterIndex);
    if (pathByBookId && pathByBookId.length > 0) {
      return pathByBookId;
    }
    if (this.bookUrl.length > 0 && this.bookUrl !== this.bookId) {
      const pathByBookUrl = await this.cacheManager.getChapterAudioCachePath(this.bookUrl, chapterIndex);
      if (pathByBookUrl && pathByBookUrl.length > 0) {
        logger.info(TAG, `命中旧版bookUrl音频缓存: 章节=${chapterIndex + 1}, 路径=${pathByBookUrl}`);
        return pathByBookUrl;
      }
    }
    return null;
  }

  private async resolveChapterTextCacheWithLegacyFallback(chapterIndex: number): Promise<string | null> {
    const contentByBookId = await this.cacheManager.getChapterCache(this.bookId, chapterIndex);
    if (contentByBookId && contentByBookId.length > 0) {
      return contentByBookId;
    }
    if (this.bookUrl.length > 0 && this.bookUrl !== this.bookId) {
      const contentByBookUrl = await this.cacheManager.getChapterCache(this.bookUrl, chapterIndex);
      if (contentByBookUrl && contentByBookUrl.length > 0) {
        logger.info(TAG, `命中旧版bookUrl章节缓存: 章节=${chapterIndex + 1}, 内容长度=${contentByBookUrl.length}`);
        return contentByBookUrl;
      }
    }
    return null;
  }

  private async isChapterAudioCachedWithLegacyFallback(chapterIndex: number): Promise<boolean> {
    const cachedByBookId = await this.cacheManager.isAudioChapterCached(this.bookId, chapterIndex);
    if (cachedByBookId) {
      return true;
    }
    if (this.bookUrl.length > 0 && this.bookUrl !== this.bookId) {
      return await this.cacheManager.isAudioChapterCached(this.bookUrl, chapterIndex);
    }
    return false;
  }

  private async loadChapterList(token: number): Promise<void> {
    if (!this.sourceId || !this.bookUrl) {
      return;
    }
    let resolvedBook: LegadoBook | null = null;
    try {
      resolvedBook = await this.sourceManager.getBookInfo(this.sourceId, this.bookUrl);
    } catch (error) {
      logger.warn(TAG, `预加载书籍详情失败，继续按已有信息加载目录: ${String(error)}`);
    }
    if (!this.isTokenValid(token)) {
      return;
    }

    const resolvedTocUrl = resolvedBook && resolvedBook.tocUrl && resolvedBook.tocUrl.length > 0
      ? resolvedBook.tocUrl
      : (this.tocUrl || this.bookUrl);
    const resolvedBookName = resolvedBook && resolvedBook.name && resolvedBook.name.length > 0
      ? resolvedBook.name
      : this.bookName;
    const resolvedAuthor = resolvedBook && resolvedBook.author && resolvedBook.author.length > 0
      ? resolvedBook.author
      : this.author;
    const resolvedCoverUrl = resolvedBook && resolvedBook.coverUrl && resolvedBook.coverUrl.length > 0
      ? resolvedBook.coverUrl
      : this.coverUrl;

    if (resolvedBookName.length > 0) {
      this.bookName = resolvedBookName;
    }
    if (resolvedAuthor.length > 0) {
      this.author = resolvedAuthor;
    }
    if (resolvedCoverUrl.length > 0) {
      this.coverUrl = resolvedCoverUrl;
    }
    this.tocUrl = resolvedTocUrl;

    const cachedChapters = await this.loadCachedChapterList();
    if (!this.isTokenValid(token)) {
      return;
    }
    if (cachedChapters && cachedChapters.length > 0) {
      this.applyResolvedChapterList(cachedChapters);
      this.recordAudioReadAloudFlowEvent(
        ReadAloudFlowEventType.CACHE_HIT,
        'chapter_list_cache_hit',
        0,
        true,
        `chapters=${cachedChapters.length}`,
        '',
        'chapter_list'
      );
      return;
    }
    this.recordAudioReadAloudFlowEvent(
      ReadAloudFlowEventType.CACHE_MISS,
      'chapter_list_cache_miss',
      0,
      true,
      '',
      '',
      'chapter_list'
    );

    const book: LegadoBook = {
      id: resolvedBook ? resolvedBook.id : '',
      type: LegadoBookSourceType.AUDIO,
      bookUrl: this.bookUrl,
      tocUrl: resolvedTocUrl,
      name: this.bookName,
      author: this.author,
      origin: this.sourceId,
      originName: resolvedBook ? resolvedBook.originName : ''
    };
    const chapters = await this.sourceManager.getChapterList(this.sourceId, book);
    if (!this.isTokenValid(token)) {
      return;
    }
    if (chapters && chapters.length > 0) {
      this.applyResolvedChapterList(chapters);
      try {
        await this.cacheManager.saveChapterList(this.bookId, chapters);
        if (this.bookUrl.length > 0 && this.bookUrl !== this.bookId) {
          await this.cacheManager.saveChapterList(this.bookUrl, chapters);
        }
      } catch (error) {
        logger.warn(TAG, `保存章节列表缓存失败: ${String(error)}`);
      }
    }
  }

  private async loadChapterContent(targetChapterIndex: number, token: number): Promise<boolean> {
    const safeIndex = Math.max(0, targetChapterIndex);
    let safeTitle = this.chapterTitle;
    let safeUrl = this.chapterUrl;
    if (this.chapterList.length > safeIndex) {
      safeTitle = this.chapterList[safeIndex].title;
      safeUrl = this.chapterList[safeIndex].url;
    }
    this.currentChapterIndex = safeIndex;
    this.chapterTitle = safeTitle;
    this.chapterUrl = safeUrl;
    this.audioDurationMs = 0;
    this.audioPositionMs = this.pendingResumePositionMs > 0 ? this.pendingResumePositionMs : 0;
    this.loadErrorMessage = '';
    this.publishState();

    try {
      const cachedAudioPath = await this.resolveChapterAudioCachePathWithLegacyFallback(safeIndex);
      if (cachedAudioPath && cachedAudioPath.length > 0) {
        if (!this.isTokenValid(token)) {
          return false;
        }
        this.chapterContent = '';
        this.audioSourceUrl = this.toAudioPlayerSourceUrl(cachedAudioPath);
        this.audioChapterCached = true;
        logger.info(TAG, `章节命中本地音频缓存: 章节=${safeIndex + 1}, 路径=${cachedAudioPath}`);
        this.recordAudioReadAloudFlowEvent(
          ReadAloudFlowEventType.CACHE_HIT,
          'audio_chapter_cache_hit',
          0,
          true,
          `path=${cachedAudioPath}`,
          '',
          'audio_chapter'
        );
        this.syncAudioProgressFromPlayer();
        this.publishState();
        return true;
      }
    } catch (error) {
      logger.warn(TAG, `读取本地音频缓存失败，回退网络解析: 章节=${safeIndex}, 错误=${String(error)}`);
    }
    this.recordAudioReadAloudFlowEvent(
      ReadAloudFlowEventType.CACHE_MISS,
      'audio_chapter_cache_miss',
      0,
      true,
      `chapter=${safeIndex + 1}`,
      '',
      'audio_chapter'
    );

    let rawContent = await this.resolveChapterTextCacheWithLegacyFallback(safeIndex);
    if ((!rawContent || rawContent.length <= 0) && this.sourceId.length > 0 && this.chapterUrl.length > 0) {
      const chapter: LegadoChapter = {
        id: '',
        bookUrl: this.bookUrl,
        url: this.chapterUrl,
        title: this.chapterTitle,
        index: safeIndex
      };
      rawContent = await this.getTypedAudioPayload(chapter);
      if (rawContent && rawContent.length > 0) {
        logger.debug(
          TAG,
          `音频章节网络内容已加载: 章节=${safeIndex + 1}, 内容长度=${rawContent.length}, 预览=${rawContent.substring(0, 180)}`
        );
      } else {
        logger.warn(TAG, `音频章节网络内容为空: 章节=${safeIndex + 1}, 章节地址=${this.chapterUrl.substring(0, 180)}`);
      }
    } else if (rawContent && rawContent.length > 0) {
      logger.debug(TAG, `命中文本章节缓存: 章节=${safeIndex + 1}, 内容长度=${rawContent.length}`);
      this.recordAudioReadAloudFlowEvent(
        ReadAloudFlowEventType.CACHE_HIT,
        'text_chapter_cache_hit',
        0,
        true,
        `contentLength=${rawContent.length}`,
        '',
        'text_chapter'
      );
    }
    if (!this.isTokenValid(token)) {
      return false;
    }
    if (!rawContent || rawContent.length <= 0) {
      this.chapterContent = '';
      this.audioSourceUrl = '';
      this.audioChapterCached = false;
      this.pendingResumePositionMs = 0;
      this.loadErrorMessage = '音频章节内容为空';
      logger.warn(TAG, `音频章节内容为空，无法解析播放地址: 章节=${safeIndex + 1}, 图源=${this.sourceId}`);
      this.publishState();
      return false;
    }

    let resolvedAudioUrl = this.resolveAudioSourceUrl(rawContent, this.chapterUrl);
    if ((!resolvedAudioUrl || resolvedAudioUrl.length <= 0) && this.looksLikeAudioUrlCandidate(this.chapterUrl)) {
      resolvedAudioUrl = this.resolveAudioUrlCandidate(this.chapterUrl, this.chapterUrl);
    }
    if (!resolvedAudioUrl || resolvedAudioUrl.length <= 0) {
      this.chapterContent = rawContent;
      this.audioSourceUrl = '';
      this.audioChapterCached = false;
      this.pendingResumePositionMs = 0;
      this.loadErrorMessage = '无法解析可播放音频地址';
      logger.warn(TAG, `音频章节地址解析失败: 章节=${safeIndex + 1}, 章节地址=${this.chapterUrl.substring(0, 180)}, 原始预览=${rawContent.substring(0, 220)}`);
      this.publishState();
      return false;
    }
    const sanitizedAudioUrl = this.sanitizeAudioUrl(resolvedAudioUrl);
    if (!sanitizedAudioUrl || sanitizedAudioUrl.length <= 0) {
      this.chapterContent = rawContent;
      this.audioSourceUrl = '';
      this.audioChapterCached = false;
      this.pendingResumePositionMs = 0;
      this.loadErrorMessage = '音频地址清洗后无效';
      logger.warn(TAG, `音频章节地址清洗后为空: 章节=${safeIndex + 1}, 解析地址=${resolvedAudioUrl.substring(0, 220)}`);
      this.publishState();
      return false;
    }
    this.chapterContent = rawContent;
    this.audioSourceUrl = this.toAudioPlayerSourceUrl(sanitizedAudioUrl);
    this.audioChapterCached = false;
    const audioUrlLength = this.audioSourceUrl.length;
    const audioUrlPrefix = this.audioSourceUrl.substring(0, 140);
    const audioUrlTail = audioUrlLength > 120 ? this.audioSourceUrl.substring(audioUrlLength - 120, audioUrlLength) : this.audioSourceUrl;
    logger.info(
      TAG,
      `章节音频解析完成: 章节=${safeIndex + 1}, 地址长度=${audioUrlLength}, 地址前缀=${audioUrlPrefix}, 地址后缀=${audioUrlTail}`
    );
    this.syncAudioProgressFromPlayer();
    this.publishState();
    return true;
  }

  private looksLikeAudioUrlCandidate(raw: string): boolean {
    const value = raw.trim();
    if (value.length <= 0) {
      return false;
    }
    if (
      value.startsWith('http://') ||
      value.startsWith('https://') ||
      value.startsWith('file://') ||
      value.startsWith('data:audio/') ||
      value.startsWith('//')
    ) {
      return true;
    }
    if (value.indexOf('://') > 0 && value.indexOf(' ') < 0) {
      return true;
    }
    const lower = value.toLowerCase();
    return lower.indexOf('.mp3') >= 0 ||
      lower.indexOf('.m4a') >= 0 ||
      lower.indexOf('.aac') >= 0 ||
      lower.indexOf('.wav') >= 0 ||
      lower.indexOf('.ogg') >= 0 ||
      lower.indexOf('.flac') >= 0 ||
      lower.indexOf('.m3u8') >= 0;
  }
  private resolveAudioUrlCandidate(raw: string, baseUrl: string): string {
    const trimmed = raw.trim();
    if (trimmed.length <= 0) {
      return '';
    }
    if (
      trimmed.startsWith('http://') ||
      trimmed.startsWith('https://') ||
      trimmed.startsWith('file://') ||
      trimmed.startsWith('data:audio/')
    ) {
      return trimmed;
    }
    const baseMatch = /^(https?:\/\/[^/]+)(\/.*)?$/i.exec(baseUrl);
    if (trimmed.startsWith('//')) {
      const protocol = baseMatch && baseMatch.length > 1 && baseMatch[1].startsWith('http://')
        ? 'http:'
        : 'https:';
      return `${protocol}${trimmed}`;
    }
    if (!baseMatch || baseMatch.length <= 1) {
      return trimmed;
    }
    const host = baseMatch[1];
    const path = baseMatch.length > 2 && baseMatch[2] ? baseMatch[2] : '/';
    if (trimmed.startsWith('/')) {
      return `${host}${trimmed}`;
    }
    const slashIndex = path.lastIndexOf('/');
    const parentPath = slashIndex >= 0 ? path.substring(0, slashIndex + 1) : '/';
    return `${host}${parentPath}${trimmed}`;
  }

  private collectAudioUrlHints(payload: AudioJsonValue, urlHints: string[]): void {
    if (payload === null || payload === undefined) {
      return;
    }
    if (Array.isArray(payload)) {
      const payloadArray = payload as Array<Object>;
      for (let index = 0; index < payloadArray.length; index++) {
        this.collectAudioUrlHints(payloadArray[index] as AudioJsonValue, urlHints);
      }
      return;
    }
    if (typeof payload === 'string') {
      const text = payload.trim();
      if (text.length > 0 && this.looksLikeAudioUrlCandidate(text)) {
        urlHints.push(text);
      }
      return;
    }
    if (typeof payload !== 'object') {
      return;
    }
    const record = payload as AudioJsonRecord;
    const keys = Object.keys(record);
    for (let index = 0; index < keys.length; index++) {
      const key = keys[index];
      const value = record[key];
      if (typeof value === 'string') {
        const text = value.trim();
        const lowerKey = key.toLowerCase();
        if (text.length > 0) {
          if (
            lowerKey === 'url' ||
            lowerKey === 'audio' ||
            lowerKey === 'audio_url' ||
            lowerKey === 'playurl' ||
            lowerKey === 'play_url' ||
            lowerKey.endsWith('_url') ||
            lowerKey.indexOf('audio') >= 0 ||
            lowerKey.indexOf('play') >= 0
          ) {
            urlHints.push(text);
          } else if (this.looksLikeAudioUrlCandidate(text)) {
            urlHints.push(text);
          }
        }
      }
      this.collectAudioUrlHints(value, urlHints);
    }
  }

  private tryExtractAudioUrlFromJson(rawContent: string, baseUrl: string): string {
    if (!rawContent || rawContent.trim().length <= 0) {
      return '';
    }
    try {
      const parsed = SafeUtils.parseObj(rawContent) as AudioJsonValue;
      const urlHints: string[] = [];
      this.collectAudioUrlHints(parsed, urlHints);
      for (let index = 0; index < urlHints.length; index++) {
        const resolved = this.resolveAudioUrlCandidate(urlHints[index], baseUrl);
        if (resolved.length > 0) {
          return resolved;
        }
      }
    } catch (_error) {
      return '';
    }
    return '';
  }

  private async getTypedAudioPayload(chapter: LegadoChapter): Promise<string> {
    const result = await this.sourceManager.getContentWithResult(this.sourceId, chapter);
    if (!result.handoff.isReady() || result.handoff.kind !== LegadoWorkflowOutputKind.AUDIO) {
      throw new Error(
        `V2_OUTPUT_HANDOFF_BLOCKED;workflow=audio;kind=${result.handoff.kind};` +
        `status=${result.handoff.status};reason=${result.handoff.reasonCode}`
      );
    }
    return result.handoff.mediaUrl;
  }

  private resolveAudioSourceUrl(rawContent: string, baseUrl: string): string {
    const text = rawContent.trim();
    if (text.length <= 0) {
      return '';
    }
    const fromJson = this.tryExtractAudioUrlFromJson(text, baseUrl);
    if (fromJson.length > 0) {
      return fromJson;
    }
    const urlMatch = /(https?:\/\/[^\s"'<>]+)/i.exec(text);
    if (urlMatch && urlMatch.length > 1) {
      return this.resolveAudioUrlCandidate(urlMatch[1], baseUrl);
    }
    const lines = text.split('\n');
    for (let index = 0; index < lines.length; index++) {
      const line = lines[index].trim();
      if (this.looksLikeAudioUrlCandidate(line)) {
        return this.resolveAudioUrlCandidate(line, baseUrl);
      }
    }
    if (this.looksLikeAudioUrlCandidate(text)) {
      return this.resolveAudioUrlCandidate(text, baseUrl);
    }
    return '';
  }

  private sanitizeAudioUrl(rawUrl: string): string {
    let sanitized = rawUrl.trim();
    if (sanitized.length <= 0) {
      return '';
    }
    if (sanitized.indexOf('\\/') >= 0) {
      sanitized = sanitized.replace(/\\\//g, '/');
    }
    if (sanitized.indexOf('\\u0026') >= 0 || sanitized.indexOf('\\U0026') >= 0) {
      sanitized = sanitized.replace(/\\u0026/gi, '&');
    }
    if (sanitized.startsWith('"') && sanitized.endsWith('"') && sanitized.length > 1) {
      sanitized = sanitized.substring(1, sanitized.length - 1).trim();
    }
    if (sanitized.startsWith('\'') && sanitized.endsWith('\'') && sanitized.length > 1) {
      sanitized = sanitized.substring(1, sanitized.length - 1).trim();
    }
    const headersTailPattern = /,\s*\{[\s\S]*"headers"[\s\S]*\}\s*$/i;
    if (headersTailPattern.test(sanitized)) {
      sanitized = sanitized.replace(headersTailPattern, '').trim();
    }
    if (sanitized.indexOf('{{') >= 0 || sanitized.indexOf('}}') >= 0) {
      return '';
    }
    if (sanitized.startsWith('//')) {
      sanitized = `https:${sanitized}`;
    }
    return sanitized;
  }

  private toAudioPlayerSourceUrl(urlOrPath: string): string {
    const normalized = urlOrPath.trim();
    if (normalized.length <= 0) {
      return '';
    }
    if (normalized.startsWith('/') && !normalized.startsWith('//')) {
      return `file://${normalized}`;
    }
    return normalized;
  }

  private isLocalAudioSource(url: string): boolean {
    const normalized = url.trim();
    if (normalized.length <= 0) {
      return false;
    }
    return normalized.startsWith('file://') || (normalized.startsWith('/') && !normalized.startsWith('//'));
  }

  private toLocalAudioFilePath(urlOrPath: string): string {
    let normalized = urlOrPath.trim();
    if (normalized.length <= 0) {
      return '';
    }
    if (normalized.startsWith('file://')) {
      normalized = normalized.substring('file://'.length);
      if (!normalized.startsWith('/')) {
        normalized = `/${normalized}`;
      }
    }
    const queryIndex = normalized.indexOf('?');
    if (queryIndex >= 0) {
      normalized = normalized.substring(0, queryIndex);
    }
    const hashIndex = normalized.indexOf('#');
    if (hashIndex >= 0) {
      normalized = normalized.substring(0, hashIndex);
    }
    if (normalized.indexOf('%') >= 0) {
      try {
        normalized = decodeURIComponent(normalized);
      } catch (_error) {
      }
    }
    return normalized;
  }

  private releaseLocalAudioSourceFile(reason: string): void {
    if (!this.localAudioSourceFile) {
      return;
    }
    const path = this.localAudioSourcePath;
    const fd = this.localAudioSourceFile.fd;
    try {
      SafeFileUtils.closeSync(fd);
    } catch (error) {
      logger.warn(TAG, `关闭本地音频文件句柄失败: 原因=${reason}, 路径=${path}, 错误=${String(error)}`);
    }
    this.localAudioSourceFile = null;
    this.localAudioSourcePath = '';
  }

  private bindLocalFileAudioSource(player: media.AVPlayer, sourceUrl: string): boolean {
    const localPath = this.toLocalAudioFilePath(sourceUrl);
    if (localPath.length <= 0) {
      logger.warn(TAG, `本地音频路径无效，回退URL模式: ${sourceUrl.substring(0, 140)}`);
      return false;
    }
    this.releaseLocalAudioSourceFile('bind_local_audio_source');
    let localFile: fileIo.File | null = null;
    try {
      localFile = SafeFileUtils.openSync(localPath, fileIo.OpenMode.READ_ONLY);
      const stat = SafeFileUtils.statSync(localFile.fd);
      const fileSize = Math.floor(stat.size);
      if (fileSize <= 0) {
        SafeFileUtils.closeSync(localFile.fd);
        logger.warn(TAG, `本地音频文件大小异常，回退URL模式: 路径=${localPath}, 大小=${fileSize}`);
        return false;
      }
      player.fdSrc = {
        fd: localFile.fd,
        offset: 0,
        length: fileSize
      };
      this.localAudioSourceFile = localFile;
      this.localAudioSourcePath = localPath;
      logger.info(TAG, `音频播放器绑定本地缓存音频成功: 路径=${localPath}, 大小=${fileSize}`);
      return true;
    } catch (error) {
      if (localFile) {
        try {
          SafeFileUtils.closeSync(localFile.fd);
        } catch (_closeError) {
        }
      }
      logger.warn(TAG, `本地缓存音频绑定失败，回退URL模式: 路径=${localPath}, 错误=${String(error)}`);
      return false;
    }
  }

  private syncAudioProgressFromPlayer(): void {
    if (!this.audioPlayer) {
      return;
    }
    const rawDuration = Math.floor(this.audioPlayer.duration);
    const rawPosition = Math.floor(this.audioPlayer.currentTime);
    const safeDuration = rawDuration > 0 ? rawDuration : 0;
    const safePosition = safeDuration > 0
      ? Math.max(0, Math.min(rawPosition, safeDuration))
      : Math.max(0, rawPosition);
    this.audioDurationMs = safeDuration;
    this.audioPositionMs = safePosition;
  }

  private async waitForAudioPlayerState(
    player: media.AVPlayer,
    expectedState: media.AVPlayerState | media.AVPlayerState[],
    timeoutMs: number,
    label: string
  ): Promise<media.AVPlayerState> {
    const expectedStates = Array.isArray(expectedState) ? expectedState : [expectedState];
    for (let index = 0; index < expectedStates.length; index++) {
      if (player.state === expectedStates[index]) {
        return player.state;
      }
    }
    return await new Promise<media.AVPlayerState>((resolve, reject) => {
      let settled = false;
      let timerId: number = -1;
      const finish = (state: media.AVPlayerState, error?: Object | string): void => {
        if (settled) {
          return;
        }
        settled = true;
        if (timerId >= 0) {
          clearTimeout(timerId);
          timerId = -1;
        }
        player.off('stateChange', onStateChange);
        if (error) {
          reject(error as Error);
          return;
        }
        resolve(state);
      };
      const onStateChange = (state: media.AVPlayerState, _reason: media.StateChangeReason): void => {
        for (let index = 0; index < expectedStates.length; index++) {
          if (state === expectedStates[index]) {
            finish(state);
            return;
          }
        }
        if (state === 'released' || state === 'error') {
          finish(state, `音频播放器状态等待失败: label=${label}, state=${state}`);
        }
      };
      player.on('stateChange', onStateChange);
      timerId = setTimeout(() => {
        finish(player.state, `音频播放器状态等待超时: label=${label}, state=${player.state}`);
      }, timeoutMs);
    });
  }

  private async invokeAudioPlayerOperationWithTimeout(
    label: string,
    timeoutMs: number,
    operation: () => Promise<void>
  ): Promise<void> {
    const operationStartedAt = Date.now();
    return await new Promise<void>((resolve, reject) => {
      let settled = false;
      let timerId: number = -1;
      const finish = (error?: Object | string): void => {
        if (settled) {
          return;
        }
        settled = true;
        if (timerId >= 0) {
          clearTimeout(timerId);
          timerId = -1;
        }
        if (error) {
          this.recordAudioReadAloudFlowEvent(
            ReadAloudFlowEventType.AUDIO_PLAYER_OPERATION,
            label,
            Math.max(0, Date.now() - operationStartedAt),
            false,
            String(error),
            label
          );
          reject(error as Error);
          return;
        }
        this.recordAudioReadAloudFlowEvent(
          ReadAloudFlowEventType.AUDIO_PLAYER_OPERATION,
          label,
          Math.max(0, Date.now() - operationStartedAt),
          true,
          '',
          label
        );
        resolve();
      };
      timerId = setTimeout(() => {
        const currentState = this.audioPlayer ? this.audioPlayer.state : 'null';
        finish(`音频播放器操作超时: label=${label}, state=${currentState}`);
      }, timeoutMs);
      operation().then(() => {
        finish();
      }).catch((error: Object | string) => {
        finish(`音频播放器操作失败: label=${label}, error=${String(error)}`);
      });
    });
  }

  private async seekAudioPlayer(player: media.AVPlayer, seekMs: number): Promise<void> {
    const safeSeekMs = Math.max(0, Math.floor(seekMs));
    return await new Promise<void>((resolve) => {
      let settled = false;
      let timeoutId: number = -1;
      const finish = (): void => {
        if (settled) {
          return;
        }
        settled = true;
        player.off('seekDone', onSeekDone);
        if (timeoutId >= 0) {
          clearTimeout(timeoutId);
          timeoutId = -1;
        }
        resolve();
      };
      const onSeekDone = (): void => {
        finish();
      };
      player.on('seekDone', onSeekDone);
      timeoutId = setTimeout(() => {
        finish();
      }, 1400);
      try {
        player.seek(safeSeekMs);
      } catch (_error) {
        finish();
      }
    });
  }

  private async ensureAudioPlayer(): Promise<media.AVPlayer> {
    if (this.audioPlayer && this.audioPlayer.state !== 'released') {
      return this.audioPlayer;
    }
    this.releasePlayerOnly();
    const player = await media.createAVPlayer();
    this.audioStateChangeHandler = (state: media.AVPlayerState, reason: media.StateChangeReason): void => {
      logger.debug(TAG, `音频播放器状态变化: 状态=${state}, 原因=${reason}, 章节=${this.currentChapterIndex}`);
      this.syncAudioProgressFromPlayer();
      this.isPlaying = state === 'playing';
      this.updateMediaPlaybackState(this.mapAudioPlayerStateToPlaybackState(state), `player_state_${state}`);
      if (state === 'completed') {
        this.audioPositionMs = this.audioDurationMs;
        this.tryAutoPlayNextChapter();
      }
      this.publishState();
    };
    this.audioTimeUpdateHandler = (_timeMs: number): void => {
      this.syncAudioProgressFromPlayer();
      this.publishState();
    };
    this.audioErrorHandler = (error: Object): void => {
      this.isPlaying = false;
      this.syncAudioProgressFromPlayer();
      this.loadErrorMessage = `音频播放失败: ${String(error)}`;
      this.updateMediaPlaybackState(ReadAloudPlaybackState.PAUSED, 'player_error');
      logger.warn(TAG, `音频播放器错误: ${String(error)}`);
      this.recordAudioReadAloudFlowEvent(
        ReadAloudFlowEventType.ERROR,
        'player_error',
        0,
        false,
        String(error)
      );
      this.publishState();
    };
    player.on('stateChange', this.audioStateChangeHandler);
    player.on('timeUpdate', this.audioTimeUpdateHandler);
    player.on('error', this.audioErrorHandler);
    this.audioPlayer = player;
    return player;
  }
  private async resetAudioPlayerForNewSource(player: media.AVPlayer): Promise<void> {
    if (player.state === 'idle' || player.state === 'released') {
      this.releaseLocalAudioSourceFile('reset_idle_or_released');
      return;
    }
    try {
      await player.reset();
    } catch (error) {
      logger.warn(TAG, `重置音频播放器失败，继续尝试: ${String(error)}`);
    }
    try {
      await this.waitForAudioPlayerState(player, 'idle', 1800, 'reset');
    } catch (_error) {
    }
    this.releaseLocalAudioSourceFile('reset_audio_source');
  }

  private async prepareAudioPlayerWithUrl(url: string, autoStart: boolean): Promise<void> {
    const player = await this.ensureAudioPlayer();
    await this.resetAudioPlayerForNewSource(player);
    this.audioDurationMs = 0;
    this.audioPositionMs = 0;
    const isLocalSource = this.isLocalAudioSource(url);
    let useFdSource = false;
    if (isLocalSource) {
      useFdSource = this.bindLocalFileAudioSource(player, url);
      if (!useFdSource) {
        logger.warn(TAG, `本地音频将回退到URL模式: 地址=${url.substring(0, 140)}`);
      }
    }
    if (!useFdSource) {
      logger.debug(TAG, `准备音频播放器URL: 自动播放=${autoStart}, 地址=${url.substring(0, 140)}`);
      player.url = url;
    }
    let stateAfterUrl: media.AVPlayerState = player.state;
    const sourceLabel = useFdSource ? 'set_fd_src' : 'set_url';
    try {
      stateAfterUrl = await this.waitForAudioPlayerState(
        player,
        ['initialized', 'prepared'],
        WAIT_STATE_TIMEOUT_MS,
        sourceLabel
      );
    } catch (error) {
      logger.warn(TAG, `设置音源后等待状态超时，尝试直接prepare: ${String(error)}`);
      stateAfterUrl = player.state;
    }
    if (stateAfterUrl !== 'prepared' && player.state !== 'prepared' && player.state !== 'playing') {
      const prepareLabel = useFdSource ? 'prepare_after_set_fd_src' : 'prepare_after_set_url';
      await this.invokeAudioPlayerOperationWithTimeout(prepareLabel, PLAYER_OPERATION_TIMEOUT_MS, () => player.prepare());
      await this.waitForAudioPlayerState(player, ['prepared', 'playing'], WAIT_STATE_TIMEOUT_MS, 'prepare');
    }
    await this.restorePendingResumePositionIfNeeded(player, 'prepare_audio_source');
    if (autoStart && player.state !== 'playing') {
      await this.invokeAudioPlayerOperationWithTimeout('play_after_prepare', PLAYER_OPERATION_TIMEOUT_MS, () => player.play());
      try {
        await this.waitForAudioPlayerState(player, 'playing', PLAYER_POST_PLAY_WAIT_TIMEOUT_MS, 'play_after_prepare_wait');
      } catch (error) {
        logger.warn(TAG, `prepare后等待playing状态超时: ${String(error)}`);
      }
    }
    this.syncAudioProgressFromPlayer();
    this.isPlaying = player.state === 'playing';
    logger.info(TAG, `音频播放器就绪: 状态=${player.state}, 自动播放=${autoStart}, 总时长毫秒=${this.audioDurationMs}`);
    this.publishState();
  }

  private releasePlayerOnly(): void {
    if (!this.audioPlayer) {
      this.releaseLocalAudioSourceFile('release_player_without_instance');
      return;
    }
    if (this.audioStateChangeHandler) {
      this.audioPlayer.off('stateChange', this.audioStateChangeHandler);
    }
    if (this.audioTimeUpdateHandler) {
      this.audioPlayer.off('timeUpdate', this.audioTimeUpdateHandler);
    }
    if (this.audioErrorHandler) {
      this.audioPlayer.off('error', this.audioErrorHandler);
    }
    try {
      this.audioPlayer.release();
    } catch (error) {
      logger.warn(TAG, `释放音频播放器失败: ${String(error)}`);
    }
    this.releaseLocalAudioSourceFile('release_player_only');
    this.audioStateChangeHandler = null;
    this.audioTimeUpdateHandler = null;
    this.audioErrorHandler = null;
    this.audioPlayer = null;
    this.isPlaying = false;
    if (this.sourceId.length > 0 && this.bookUrl.length > 0) {
      this.updateMediaPlaybackState(ReadAloudPlaybackState.PAUSED, 'release_player_only');
    } else {
      this.updateMediaPlaybackState(ReadAloudPlaybackState.IDLE, 'release_player_only');
    }
  }

  private tryAutoPlayNextChapter(): void {
    if (!this.readAloudSettings.autoPlayNextChapter || this.autoSwitchingChapter) {
      return;
    }
    if (this.totalChapters <= 0 || this.currentChapterIndex >= this.totalChapters - 1) {
      return;
    }
    this.autoSwitchingChapter = true;
    this.playNextChapter(true).then((): void => {
      this.autoSwitchingChapter = false;
    }).catch((_error: Object | string): void => {
      this.autoSwitchingChapter = false;
    });
  }

  private handleMediaPlayCommand(): void {
    void this.play().then((started: boolean): void => {
      if (!started) {
        logger.warn(TAG, '媒体播放指令未能启动音频播放');
      }
    }).catch((error: Object | string): void => {
      logger.warn(TAG, `处理媒体播放指令失败: ${String(error)}`);
    });
  }

  private handleMediaPauseCommand(): void {
    void this.pause().catch((error: Object | string): void => {
      logger.warn(TAG, `处理媒体暂停指令失败: ${String(error)}`);
    });
  }

  private handleMediaStopCommand(): void {
    void this.stop().catch((error: Object | string): void => {
      logger.warn(TAG, `处理媒体停止指令失败: ${String(error)}`);
    });
  }

  private handleMediaNextCommand(): void {
    const shouldForceStart = this.isPlaying || this.mediaPlaybackState === ReadAloudPlaybackState.PLAYING;
    void this.playNextChapter(shouldForceStart).then((switched: boolean): void => {
      if (!switched) {
        logger.debug(TAG, '媒体下一章指令未切换章节（可能已到最后一章）');
      }
    }).catch((error: Object | string): void => {
      logger.warn(TAG, `处理媒体下一章指令失败: ${String(error)}`);
    });
  }

  private handleMediaPreviousCommand(): void {
    const shouldForceStart = this.isPlaying || this.mediaPlaybackState === ReadAloudPlaybackState.PLAYING;
    void this.playPreviousChapter(shouldForceStart).then((switched: boolean): void => {
      if (!switched) {
        logger.debug(TAG, '媒体上一章指令未切换章节（可能已在第一章）');
      }
    }).catch((error: Object | string): void => {
      logger.warn(TAG, `处理媒体上一章指令失败: ${String(error)}`);
    });
  }

  private handleMediaSeekCommand(positionMs: number): void {
    void this.seekToPosition(positionMs, 'media_control_seek').catch((error: Object | string): void => {
      logger.warn(TAG, `处理媒体定位指令失败: ${String(error)}`);
    });
  }

  private mapAudioPlayerStateToPlaybackState(state: media.AVPlayerState): ReadAloudPlaybackState {
    if (state === 'playing') {
      return ReadAloudPlaybackState.PLAYING;
    }
    if (state === 'completed' || state === 'stopped') {
      return ReadAloudPlaybackState.STOPPED;
    }
    if (state === 'released') {
      return ReadAloudPlaybackState.IDLE;
    }
    return ReadAloudPlaybackState.PAUSED;
  }

  private updateMediaPlaybackState(nextState: ReadAloudPlaybackState, reason: string): void {
    if (this.mediaPlaybackState === nextState) {
      return;
    }
    logger.debug(TAG, `媒体会话播放状态切换: ${this.mediaPlaybackState} -> ${nextState}, 原因=${reason}`);
    this.recordAudioReadAloudFlowEvent(
      ReadAloudFlowEventType.PLAYBACK_STATE_CHANGED,
      reason,
      0,
      true,
      `${this.mediaPlaybackState}->${nextState}`
    );
    this.mediaPlaybackState = nextState;
  }

  private buildMediaStateSnapshot(): ReadAloudStateSnapshot {
    const hasContext = this.sourceId.length > 0 && this.bookUrl.length > 0;
    const mediaContext = this.buildMediaSessionContext();
    const contentLength = mediaContext && mediaContext.content ? mediaContext.content.length : 0;
    const currentCharIndex = contentLength > 0 ? this.resolveMediaCurrentCharIndex(contentLength) : -1;
    return {
      playbackState: hasContext ? this.mediaPlaybackState : ReadAloudPlaybackState.IDLE,
      settings: this.readAloudSettings,
      hasContext: hasContext,
      chapterIndex: hasContext ? this.currentChapterIndex : -1,
      pageIndex: 0,
      currentCharIndex: currentCharIndex,
      chunkStartCharIndex: -1,
      chunkEndCharIndex: -1,
      currentPositionMs: hasContext ? Math.max(0, Math.floor(this.audioPositionMs)) : -1,
      totalDurationMs: hasContext ? Math.max(0, Math.floor(this.audioDurationMs)) : -1
    };
  }

  private buildMediaSessionContext(): ReadAloudSessionContext | null {
    if (this.sourceId.length <= 0 || this.bookUrl.length <= 0) {
      return null;
    }
    const content = this.chapterContent.length > 0 ? this.chapterContent : this.chapterTitle;
    return {
      bookId: this.bookId,
      bookTitle: this.bookName,
      chapterIndex: this.currentChapterIndex,
      chapterTitle: this.chapterTitle.length > 0 ? this.chapterTitle : `第${this.currentChapterIndex + 1}章`,
      coverUrl: this.coverUrl,
      content: content,
      pageIndex: 0,
      resumeCharIndex: content.length > 0 ? this.resolveMediaCurrentCharIndex(content.length) : undefined,
      readerOpenFlowId: this.readerOpenFlowId,
      sourceId: this.sourceId,
      totalChapters: this.totalChapters
    };
  }

  private resolveMediaCurrentCharIndex(contentLength: number): number {
    if (contentLength <= 0) {
      return -1;
    }
    if (this.audioDurationMs <= 0) {
      return this.audioPositionMs > 0 ? 0 : -1;
    }
    const safeDuration = Math.max(1, Math.floor(this.audioDurationMs));
    const safePosition = Math.max(0, Math.min(Math.floor(this.audioPositionMs), safeDuration));
    const maxCharIndex = Math.max(0, contentLength - 1);
    return Math.max(0, Math.min(maxCharIndex, Math.floor((safePosition / safeDuration) * maxCharIndex)));
  }

  private syncMediaSession(): void {
    this.mediaSession.sync(this.buildMediaStateSnapshot(), this.buildMediaSessionContext(), this.readAloudSettings);
  }

  private getAudioProgressChapterIndexKey(bookId: string): string {
    return `${AUDIO_PROGRESS_KEY_PREFIX}${bookId}_chapter_index`;
  }

  private getAudioProgressPositionKey(bookId: string): string {
    return `${AUDIO_PROGRESS_KEY_PREFIX}${bookId}_position_ms`;
  }

  private applyPersistedProgressForLaunch(requestedChapterIndex: number, sameSession: boolean): void {
    this.pendingResumePositionMs = 0;
    if (sameSession || this.bookId.length <= 0) {
      return;
    }
    const persistedChapterIndex = Math.floor(
      this.settingsManager.getNumber(this.getAudioProgressChapterIndexKey(this.bookId), -1)
    );
    const persistedPositionMs = Math.max(
      0,
      Math.floor(this.settingsManager.getNumber(this.getAudioProgressPositionKey(this.bookId), 0))
    );
    if (persistedChapterIndex < 0) {
      return;
    }
    let resolvedChapterIndex = this.currentChapterIndex;
    if (requestedChapterIndex <= 0) {
      resolvedChapterIndex = persistedChapterIndex;
    } else if (persistedChapterIndex === this.currentChapterIndex) {
      resolvedChapterIndex = persistedChapterIndex;
    }
    if (this.totalChapters > 0) {
      resolvedChapterIndex = Math.max(0, Math.min(resolvedChapterIndex, this.totalChapters - 1));
    } else {
      resolvedChapterIndex = Math.max(0, resolvedChapterIndex);
    }
    this.currentChapterIndex = resolvedChapterIndex;
    if (persistedChapterIndex === this.currentChapterIndex && persistedPositionMs > 0) {
      this.pendingResumePositionMs = persistedPositionMs;
      this.audioPositionMs = persistedPositionMs;
      logger.info(TAG, `命中听书进度恢复: 章节=${this.currentChapterIndex + 1}, 位置毫秒=${this.pendingResumePositionMs}`);
    }
  }

  private async restorePendingResumePositionIfNeeded(player: media.AVPlayer, trigger: string): Promise<void> {
    const pendingPositionMs = Math.max(0, Math.floor(this.pendingResumePositionMs));
    if (pendingPositionMs <= 0) {
      return;
    }
    const durationFromPlayer = Math.max(0, Math.floor(player.duration));
    const targetPositionMs = durationFromPlayer > 0
      ? Math.max(0, Math.min(pendingPositionMs, durationFromPlayer))
      : pendingPositionMs;
    await this.seekAudioPlayer(player, targetPositionMs);
    this.pendingResumePositionMs = 0;
    this.syncAudioProgressFromPlayer();
    logger.info(TAG, `恢复听书播放进度: 触发点=${trigger}, 章节=${this.currentChapterIndex + 1}, 位置毫秒=${this.audioPositionMs}`);
  }

  private persistPlaybackProgress(force: boolean): void {
    if (this.bookId.length <= 0) {
      return;
    }
    const now = Date.now();
    if (!force && (now - this.lastProgressPersistTime) < AUDIO_PROGRESS_PERSIST_INTERVAL_MS) {
      return;
    }
    this.lastProgressPersistTime = now;
    const safeChapterIndex = Math.max(0, Math.floor(this.currentChapterIndex));
    const safePositionMs = Math.max(0, Math.floor(this.audioPositionMs));
    const chapterKey = this.getAudioProgressChapterIndexKey(this.bookId);
    const positionKey = this.getAudioProgressPositionKey(this.bookId);
    this.settingsManager.setNumber(chapterKey, safeChapterIndex).catch((error: Object | string): void => {
      logger.warn(TAG, `保存听书章节进度失败: ${String(error)}`);
    });
    this.settingsManager.setNumber(positionKey, safePositionMs).catch((error: Object | string): void => {
      logger.warn(TAG, `保存听书播放毫秒进度失败: ${String(error)}`);
    });
  }
}

export function getNovelAudioReadAloudSessionManager(): NovelAudioReadAloudSessionManager {
  return NovelAudioReadAloudSessionManager.getInstance();
}

