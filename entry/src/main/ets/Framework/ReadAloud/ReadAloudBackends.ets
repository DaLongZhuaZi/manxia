import { logger } from '../../Utils/Logger';
import { ReadAloudEngineType, ReadAloudSettings } from '../../Models/TextReaderModels';
import { ReadAloudProgressSnapshot, ReadAloudSessionContext, ReadAloudVoiceOption } from './ReadAloudTypes';
import { ReadAloudRequestIdGenerator } from './ReadAloudRequestIdGenerator';
import { textToSpeech } from '@kit.CoreSpeechKit';

const TAG = 'ReadAloudBackends';
const MAX_SPEAK_CHUNK_LENGTH = 240;
const MAX_CANDIDATE_VOICES = 5;
const BASE_ESTIMATED_CHARS_PER_SECOND = 6.0;
const CHUNK_PROGRESS_TIMER_INTERVAL_MS = 100;
const CHUNK_PROGRESS_MIN_DURATION_MS = 420;
const CHUNK_PROGRESS_GUARD_TAIL_CHARS = 1;
const CHUNK_PROGRESS_SENTENCE_PAUSE_MS = 80;
const CHUNK_PROGRESS_PHRASE_PAUSE_MS = 25;
const SYSTEM_TTS_ONLINE_MODE: number = 0;
const SYSTEM_TTS_OFFLINE_MODE: number = 1;
const SYNTH_COMPLETE_FALLBACK_INTERVAL_MS: number = 420;
const SYNTH_COMPLETE_FALLBACK_MAX_RETRY: number = 80;
const SYSTEM_TTS_SERVICE_NOT_INITIALIZED_CODE: number = 1002300007;

interface ReadAloudErrorLike {
  code?: number | string;
  errorCode?: number | string;
  message?: string;
  errorMessage?: string;
  errMsg?: string;
}

function formatReadAloudError(error: Object | string): string {
  if (typeof error === 'string') {
    return error;
  }
  const errorLike = error as ReadAloudErrorLike;
  const errorObj = error as Error;
  const rawCode: number | string | undefined = (
    typeof errorLike.code === 'number' || typeof errorLike.code === 'string'
  ) ? errorLike.code : errorLike.errorCode;
  const hasCode = typeof rawCode === 'number' || typeof rawCode === 'string';
  const detailMessage = (
    errorObj.message && errorObj.message.length > 0
  ) ? errorObj.message : (
    errorLike.message && errorLike.message.length > 0
  ) ? errorLike.message : (
    errorLike.errorMessage && errorLike.errorMessage.length > 0
  ) ? errorLike.errorMessage : (
    errorLike.errMsg && errorLike.errMsg.length > 0
  ) ? errorLike.errMsg : '';
  if (detailMessage.length > 0) {
    if (hasCode) {
      return `code=${rawCode}, message=${detailMessage}`;
    }
    return detailMessage;
  }
  try {
    const jsonText = JSON.stringify(error);
    if (jsonText && jsonText.length > 0 && jsonText !== '{}') {
      return jsonText;
    }
  } catch (_ignored) {
  }
  if (hasCode) {
    return `code=${rawCode}`;
  }
  return String(error);
}

class QueueCharRange {
  public start: number;
  public end: number;

  constructor(start: number, end: number) {
    this.start = start;
    this.end = end;
  }
}

export type ReadAloudProgressListener = (progress: ReadAloudProgressSnapshot) => void;
export type ReadAloudPlaybackEventType = 'completed' | 'paused_for_error';

export class ReadAloudPlaybackEvent {
  public eventType: ReadAloudPlaybackEventType;
  public reason: string;
  public currentCharIndex: number;

  constructor(eventType: ReadAloudPlaybackEventType, reason: string, currentCharIndex: number) {
    this.eventType = eventType;
    this.reason = reason;
    this.currentCharIndex = currentCharIndex;
  }
}

export type ReadAloudPlaybackListener = (event: ReadAloudPlaybackEvent) => void;

export interface IReadAloudBackend {
  readonly engineType: ReadAloudEngineType;
  applySettings(settings: ReadAloudSettings): void;
  updateContext(context: ReadAloudSessionContext | null): void;
  setProgressListener(listener: ReadAloudProgressListener | null): void;
  setPlaybackListener(listener: ReadAloudPlaybackListener | null): void;
  listVoices(): Promise<ReadAloudVoiceOption[]>;
  getProgressSnapshot(): ReadAloudProgressSnapshot;
  start(): Promise<void>;
  pause(): Promise<void>;
  stop(): Promise<void>;
  release(): Promise<void>;
}

class BaseReadAloudBackend implements IReadAloudBackend {
  readonly engineType: ReadAloudEngineType;
  protected settings: ReadAloudSettings | null = null;
  protected context: ReadAloudSessionContext | null = null;
  protected progressListener: ReadAloudProgressListener | null = null;
  protected playbackListener: ReadAloudPlaybackListener | null = null;
  protected progressSnapshot: ReadAloudProgressSnapshot = new ReadAloudProgressSnapshot(-1, -1, -1);

  constructor(engineType: ReadAloudEngineType) {
    this.engineType = engineType;
  }

  applySettings(settings: ReadAloudSettings): void {
    this.settings = settings;
  }

  updateContext(context: ReadAloudSessionContext | null): void {
    this.context = context;
  }

  setProgressListener(listener: ReadAloudProgressListener | null): void {
    this.progressListener = listener;
  }

  setPlaybackListener(listener: ReadAloudPlaybackListener | null): void {
    this.playbackListener = listener;
  }

  getProgressSnapshot(): ReadAloudProgressSnapshot {
    return new ReadAloudProgressSnapshot(
      this.progressSnapshot.currentCharIndex,
      this.progressSnapshot.chunkStartCharIndex,
      this.progressSnapshot.chunkEndCharIndex
    );
  }

  async listVoices(): Promise<ReadAloudVoiceOption[]> {
    return [];
  }

  protected updateProgressSnapshot(currentCharIndex: number, chunkStartCharIndex: number, chunkEndCharIndex: number): void {
    const unchanged = (
      this.progressSnapshot.currentCharIndex === currentCharIndex &&
      this.progressSnapshot.chunkStartCharIndex === chunkStartCharIndex &&
      this.progressSnapshot.chunkEndCharIndex === chunkEndCharIndex
    );
    if (unchanged) {
      return;
    }
    this.progressSnapshot = new ReadAloudProgressSnapshot(currentCharIndex, chunkStartCharIndex, chunkEndCharIndex);
    if (this.progressListener) {
      this.progressListener(this.getProgressSnapshot());
    }
  }

  protected notifyPlaybackEvent(eventType: ReadAloudPlaybackEventType, reason: string, currentCharIndex: number): void {
    if (!this.playbackListener) {
      return;
    }
    this.playbackListener(new ReadAloudPlaybackEvent(eventType, reason, currentCharIndex));
  }

  async start(): Promise<void> {}

  async pause(): Promise<void> {}

  async stop(): Promise<void> {}

  async release(): Promise<void> {
    this.context = null;
  }
}

class SystemReadAloudBackend extends BaseReadAloudBackend {
  // TODO(听书): 接入 AudioSession/AudioFocus，中断与抢焦点策略统一到控制器层。
  private ttsEngine: textToSpeech.TextToSpeechEngine | null = null;
  private preferredEngineParams: textToSpeech.CreateEngineParams | null = null;
  private queue: string[] = [];
  private queueStartCharIndex: number[] = [];
  private queueEndCharIndex: number[] = [];
  private queueIndex: number = 0;
  private queueToken: string = '';
  private pendingRequestId: string = '';
  private stopRequested: boolean = false;
  private pauseRequested: boolean = false;
  private requestSerial: number = 0;
  private supportsSpeakExtraParams: boolean = true;
  private currentCharIndex: number = 0;
  private chunkProgressTimer: number = -1;
  private chunkCompleteFallbackTimer: number = -1;
  private chunkCompleteFallbackRetry: number = 0;
  private speakingChunkStartCharIndex: number = -1;
  private speakingChunkEndCharIndex: number = -1;
  private speakingChunkStartTimeMs: number = 0;
  private speakingChunkEstimatedDurationMs: number = 0;
  private chunkFailureRetryCount: number = 0;
  private serviceRecoveryRetryCount: number = 0;
  private serviceRecoveryInProgress: boolean = false;
  private lastVoiceQueryFailed: boolean = false;
  private lastVoiceQueryErrorMessage: string = '';

  private readonly speakListener: textToSpeech.SpeakListener = {
    onStart: (requestId: string, _response: textToSpeech.StartResponse): void => {
      this.chunkFailureRetryCount = 0;
      logger.debug(TAG, `SYSTEM TTS 开始朗读: requestId=${requestId}`);
    },
    onComplete: (requestId: string, response: textToSpeech.CompleteResponse): void => {
      if (requestId !== this.pendingRequestId) {
        return;
      }
      if (response.type === 0) {
        logger.debug(TAG, `SYSTEM TTS 合成已完成，等待播放完成/补偿确认: requestId=${requestId}`);
        this.scheduleChunkCompleteFallback(requestId);
        return;
      }
      if (this.isChunkCompleteSignalTooEarly()) {
        const delayMs = this.getChunkCompleteGuardDelayMs();
        logger.debug(TAG, `SYSTEM TTS 播放完成信号过早，进入保护等待: requestId=${requestId}, delayMs=${delayMs}`);
        this.scheduleChunkCompleteFallback(requestId, delayMs);
        return;
      }
      this.handleChunkPlaybackCompleted(requestId, 'speech_complete');
    },
    onStop: (requestId: string, _response: textToSpeech.StopResponse): void => {
      this.clearChunkCompleteFallback();
      this.stopChunkProgressTimer();
      if (requestId === this.pendingRequestId) {
        this.pendingRequestId = '';
      }
      logger.debug(TAG, `SYSTEM TTS 已停止: requestId=${requestId}, pause=${this.pauseRequested}, stop=${this.stopRequested}`);
    },
    onError: (requestId: string, errorCode: number, errorMessage: string): void => {
      this.clearChunkCompleteFallback();
      this.stopChunkProgressTimer();
      const activeRequestId = this.pendingRequestId;
      if (requestId === activeRequestId) {
        this.pendingRequestId = '';
      }
      if (requestId.length === 0 || activeRequestId.length === 0 || requestId !== activeRequestId) {
        logger.debug(
          TAG,
          `SYSTEM TTS 忽略非活动请求错误: requestId=${requestId}, activeRequestId=${activeRequestId}`
        );
        return;
      }
      logger.warn(TAG, `SYSTEM TTS 出错: requestId=${requestId}, code=${errorCode}, message=${errorMessage}`);
      if (this.stopRequested || this.pauseRequested) {
        return;
      }
      if (this.isServiceNotInitializedError(errorCode, errorMessage)) {
        this.recoverEngineAndReplayCurrentChunkSafely('speak_listener_error');
        return;
      }
      this.skipFailedChunkAndContinue();
    }
  };

  applySettings(settings: ReadAloudSettings): void {
    const previousVoiceIdentity = this.getVoiceIdentityFromSettings(this.settings);
    super.applySettings(settings);
    const nextVoiceIdentity = this.getVoiceIdentityFromSettings(this.settings);
    if (previousVoiceIdentity === nextVoiceIdentity) {
      return;
    }

    const selectedParams = this.buildSelectedEngineParamsFromSettings(this.settings);
    this.preferredEngineParams = selectedParams;
    if (!this.ttsEngine) {
      logger.info(TAG, `SYSTEM TTS 音色参数已更新: ${this.describeVoiceIdentity(nextVoiceIdentity)}`);
      return;
    }

    try {
      this.ttsEngine.stop();
    } catch (stopError) {
      logger.debug(TAG, `SYSTEM TTS 切换音色时停止引擎失败: ${String(stopError)}`);
    }
    try {
      this.ttsEngine.shutdown();
    } catch (shutdownError) {
      logger.debug(TAG, `SYSTEM TTS 切换音色时释放引擎失败: ${String(shutdownError)}`);
    }
    this.ttsEngine = null;
    this.pendingRequestId = '';
    this.supportsSpeakExtraParams = true;
    this.clearChunkCompleteFallback();
    this.stopChunkProgressTimer();
    logger.info(TAG, `SYSTEM TTS 音色已切换: ${this.describeVoiceIdentity(nextVoiceIdentity)}`);
  }

  updateContext(context: ReadAloudSessionContext | null): void {
    super.updateContext(context);
    if (!context) {
      this.currentCharIndex = 0;
      this.updateProgressSnapshot(-1, -1, -1);
      return;
    }

    const resumeCharIndex = this.normalizeResumeCharIndex(context.resumeCharIndex ?? 0, context.content);
    const nextQueueToken = this.createQueueToken();
    const sameQueueToken = this.queueToken === nextQueueToken;
    // 同一章节同一内容下，播放链路中不应被外部 context 回写打断，
    // 否则会在分段切换窗口把 queueIndex 回退/跳跃，导致“跳段”。
    const inPlaybackFlow = sameQueueToken &&
      this.queue.length > 0 &&
      !this.pauseRequested &&
      !this.stopRequested;
    if (inPlaybackFlow) {
      return;
    }

    if (!sameQueueToken) {
      this.currentCharIndex = resumeCharIndex;
      this.updateProgressSnapshot(resumeCharIndex, resumeCharIndex, resumeCharIndex);
      return;
    }

    this.currentCharIndex = resumeCharIndex;
    if (this.queue.length > 0) {
      this.queueIndex = this.findQueueIndexByCharIndex(resumeCharIndex);
      const range = this.getQueueRange(this.queueIndex);
      this.updateProgressSnapshot(resumeCharIndex, range.start, range.end);
    } else {
      this.updateProgressSnapshot(resumeCharIndex, resumeCharIndex, resumeCharIndex);
    }
  }

  async start(): Promise<void> {
    const content: string = this.context?.content ?? '';
    if (content.trim().length === 0) {
      throw new Error('SYSTEM_TTS_NO_CONTENT');
    }

    await this.ensureEngineReady();
    if (!this.ttsEngine) {
      throw new Error('SYSTEM_TTS_ENGINE_UNAVAILABLE');
    }

    this.stopRequested = false;
    this.pauseRequested = false;

    const nextQueueToken = this.createQueueToken();
    // 每次显式 start 都重新构建分段队列，避免历史 trim/索引状态污染导致跳段。
    this.rebuildQueue(content);
    this.queueToken = nextQueueToken;

    if (this.queue.length === 0) {
      throw new Error('SYSTEM_TTS_EMPTY_QUEUE');
    }

    const resumeCharIndex = this.normalizeResumeCharIndex(this.context?.resumeCharIndex ?? this.currentCharIndex, content);
    this.currentCharIndex = resumeCharIndex;
    this.queueIndex = this.findQueueIndexByCharIndex(resumeCharIndex);

    if (this.queueIndex < 0 || this.queueIndex >= this.queue.length) {
      this.queueIndex = 0;
    }

    this.chunkFailureRetryCount = 0;
    this.serviceRecoveryRetryCount = 0;
    if (!this.normalizeQueueIndexToSpeakableChunkFromCurrentChar()) {
      // 恢复点之后可能只剩标点，回退到章节首个可读分段，避免“开始后无声秒结束”。
      this.currentCharIndex = 0;
      this.queueIndex = 0;
      if (!this.normalizeQueueIndexToSpeakableChunkFromCurrentChar()) {
        throw new Error('SYSTEM_TTS_NO_SPEAKABLE_CHUNK');
      }
    }
    await this.speakCurrentChunkWithRecovery();
  }

  async pause(): Promise<void> {
    this.pauseRequested = true;
    this.stopRequested = false;
    this.chunkFailureRetryCount = 0;
    this.serviceRecoveryRetryCount = 0;
    this.serviceRecoveryInProgress = false;
    this.clearChunkCompleteFallback();
    this.stopChunkProgressTimer();
    const range = this.getQueueRange(this.queueIndex);
    this.updateProgressSnapshot(this.currentCharIndex, range.start, range.end);
    if (!this.ttsEngine) {
      return;
    }
    try {
      this.ttsEngine.stop();
    } catch (error) {
      logger.warn(TAG, `SYSTEM TTS 暂停失败: ${String(error)}`);
    } finally {
      this.pendingRequestId = '';
    }
  }

  async stop(): Promise<void> {
    this.stopRequested = true;
    this.pauseRequested = false;
    this.chunkFailureRetryCount = 0;
    this.serviceRecoveryRetryCount = 0;
    this.serviceRecoveryInProgress = false;
    this.clearChunkCompleteFallback();
    this.stopChunkProgressTimer();

    if (this.ttsEngine) {
      try {
        this.ttsEngine.stop();
      } catch (error) {
        logger.warn(TAG, `SYSTEM TTS 停止失败: ${String(error)}`);
      }
    }

    this.pendingRequestId = '';
    this.queue = [];
    this.queueStartCharIndex = [];
    this.queueEndCharIndex = [];
    this.queueIndex = 0;
    this.queueToken = '';
    this.updateProgressSnapshot(this.currentCharIndex, this.currentCharIndex, this.currentCharIndex);
  }

  async release(): Promise<void> {
    await this.stop();
    if (this.ttsEngine) {
      try {
        this.ttsEngine.shutdown();
      } catch (error) {
        logger.warn(TAG, `SYSTEM TTS 引擎关闭失败: ${String(error)}`);
      }
    }

    this.ttsEngine = null;
    this.preferredEngineParams = null;
    this.supportsSpeakExtraParams = true;
    this.chunkFailureRetryCount = 0;
    this.clearChunkCompleteFallback();
    this.stopChunkProgressTimer();
    this.currentCharIndex = 0;
    this.updateProgressSnapshot(-1, -1, -1);
    await super.release();
  }

  async listVoices(): Promise<ReadAloudVoiceOption[]> {
    this.lastVoiceQueryFailed = false;
    this.lastVoiceQueryErrorMessage = '';

    const options: ReadAloudVoiceOption[] = [];
    const seenIds: Set<string> = new Set<string>();

    const onlineVoices = this.pickTopVoices(await this.listVoicesSafely(SYSTEM_TTS_ONLINE_MODE));
    const offlineVoices = this.pickTopVoices(await this.listVoicesSafely(SYSTEM_TTS_OFFLINE_MODE));

    this.appendVoiceOptions(options, seenIds, onlineVoices, SYSTEM_TTS_ONLINE_MODE);
    this.appendVoiceOptions(options, seenIds, offlineVoices, SYSTEM_TTS_OFFLINE_MODE);
    if (options.length === 0 && this.lastVoiceQueryFailed) {
      throw new Error(`SYSTEM_TTS_VOICE_QUERY_FAILED: ${this.lastVoiceQueryErrorMessage}`);
    }
    return options;
  }

  private async ensureEngineReady(): Promise<void> {
    if (this.ttsEngine) {
      return;
    }

    const candidates = await this.buildEngineCandidates();
    let lastError: string = 'unknown';

    for (const params of candidates) {
      try {
        const engine = await textToSpeech.createEngine(params);
        engine.setListener(this.speakListener);
        this.ttsEngine = engine;
        this.preferredEngineParams = params;
        logger.info(TAG, `SYSTEM TTS 引擎就绪: language=${params.language}, person=${params.person}, online=${params.online}`);
        return;
      } catch (error) {
        lastError = formatReadAloudError(error);
        logger.warn(TAG, `SYSTEM TTS 候选引擎初始化失败: language=${params.language}, person=${params.person}, online=${params.online}, error=${lastError}`);
      }
    }

    throw new Error(`SYSTEM_TTS_INIT_FAILED: ${lastError}`);
  }

  private async buildEngineCandidates(): Promise<textToSpeech.CreateEngineParams[]> {
    const candidates: textToSpeech.CreateEngineParams[] = [];
    const candidateKeys: Set<string> = new Set<string>();

    const addCandidate = (language: string, person: number, online: number): void => {
      const key = `${language}#${person}#${online}`;
      if (candidateKeys.has(key)) {
        return;
      }
      candidateKeys.add(key);
      candidates.push({ language, person, online });
    };

    const selectedParams = this.buildSelectedEngineParamsFromSettings(this.settings);
    if (selectedParams) {
      addCandidate(selectedParams.language, selectedParams.person, selectedParams.online);
    }

    if (this.preferredEngineParams) {
      addCandidate(
        this.preferredEngineParams.language,
        this.preferredEngineParams.person,
        this.preferredEngineParams.online
      );
    }

    const onlineVoices = await this.listVoicesSafely(SYSTEM_TTS_ONLINE_MODE);
    const offlineVoices = await this.listVoicesSafely(SYSTEM_TTS_OFFLINE_MODE);

    this.pickTopVoices(onlineVoices).forEach((voice: textToSpeech.VoiceInfo) => {
      addCandidate(voice.language, voice.person, SYSTEM_TTS_ONLINE_MODE);
    });
    this.pickTopVoices(offlineVoices).forEach((voice: textToSpeech.VoiceInfo) => {
      addCandidate(voice.language, voice.person, SYSTEM_TTS_OFFLINE_MODE);
    });

    ['zh-CN', 'zh_CN', 'en-US', 'en_US'].forEach((language: string) => {
      addCandidate(language, 0, SYSTEM_TTS_ONLINE_MODE);
      addCandidate(language, 0, SYSTEM_TTS_OFFLINE_MODE);
    });

    return candidates;
  }

  private async listVoicesSafely(online: number): Promise<textToSpeech.VoiceInfo[]> {
    const safeOnline = online === SYSTEM_TTS_OFFLINE_MODE ? SYSTEM_TTS_OFFLINE_MODE : SYSTEM_TTS_ONLINE_MODE;
    if (this.ttsEngine) {
      let lastActiveErrorText: string = '';
      for (let attempt = 0; attempt < 2; attempt++) {
        try {
          const requestId = this.createRequestId('voice_active');
          const activeVoices = await this.ttsEngine.listVoices({ requestId, online: safeOnline });
          if (activeVoices.length > 0) {
            return activeVoices;
          }
        } catch (activeError) {
          const activeErrorText = formatReadAloudError(activeError);
          lastActiveErrorText = activeErrorText;
          this.appendVoiceQueryError(activeErrorText);
          logger.warn(
            TAG,
            `SYSTEM TTS 当前引擎查询音色失败: online=${safeOnline}, attempt=${attempt + 1}, error=${activeErrorText}`
          );
        }
      }
      if (this.shouldRetryVoiceQueryWithAlternateOnline(lastActiveErrorText)) {
        const alternateOnline = this.getAlternateOnlineMode(safeOnline);
        try {
          const requestId = this.createRequestId('voice_active_retry');
          const retriedVoices = await this.ttsEngine.listVoices({ requestId, online: alternateOnline });
          if (retriedVoices.length > 0) {
            logger.info(
              TAG,
              `SYSTEM TTS 当前引擎音色查询使用 alternate online 成功: from=${safeOnline}, to=${alternateOnline}, count=${retriedVoices.length}`
            );
            return retriedVoices;
          }
        } catch (retryError) {
          const retryErrorText = formatReadAloudError(retryError);
          this.appendVoiceQueryError(retryErrorText);
          logger.warn(
            TAG,
            `SYSTEM TTS 当前引擎 alternate online 查询失败: from=${safeOnline}, to=${alternateOnline}, error=${retryErrorText}`
          );
        }
      }
      logger.info(TAG, `SYSTEM TTS 当前引擎未返回音色，跳过回退引擎创建: online=${safeOnline}`);
      return [];
    }

    try {
      const fallbackVoices = await this.listVoicesByEngineQuery(safeOnline);
      logger.info(TAG, `SYSTEM TTS 音色查询完成: online=${safeOnline}, count=${fallbackVoices.length}`);
      return fallbackVoices;
    } catch (fallbackError) {
      const fallbackErrorText = formatReadAloudError(fallbackError);
      this.appendVoiceQueryError(fallbackErrorText);
      if (this.shouldRetryVoiceQueryWithAlternateOnline(fallbackErrorText)) {
        const alternateOnline = this.getAlternateOnlineMode(safeOnline);
        try {
          const alternateVoices = await this.listVoicesByEngineQuery(alternateOnline);
          logger.info(
            TAG,
            `SYSTEM TTS 音色查询使用 alternate online 成功: from=${safeOnline}, to=${alternateOnline}, count=${alternateVoices.length}`
          );
          return alternateVoices;
        } catch (alternateError) {
          const alternateErrorText = formatReadAloudError(alternateError);
          this.appendVoiceQueryError(alternateErrorText);
          logger.warn(
            TAG,
            `SYSTEM TTS alternate online 查询失败: from=${safeOnline}, to=${alternateOnline}, error=${alternateErrorText}`
          );
        }
      }
      logger.warn(TAG, `SYSTEM TTS 获取音色列表失败: online=${safeOnline}, error=${fallbackErrorText}`);
      return [];
    }
  }

  private shouldRetryVoiceQueryWithAlternateOnline(errorText: string): boolean {
    if (!errorText || errorText.length <= 0) {
      return false;
    }
    return errorText.toLowerCase().includes('online type error');
  }

  private getAlternateOnlineMode(online: number): number {
    return online === SYSTEM_TTS_ONLINE_MODE ? SYSTEM_TTS_OFFLINE_MODE : SYSTEM_TTS_ONLINE_MODE;
  }

  private appendVoiceQueryError(errorText: string): void {
    this.lastVoiceQueryFailed = true;
    if (this.lastVoiceQueryErrorMessage.length > 0) {
      this.lastVoiceQueryErrorMessage = `${this.lastVoiceQueryErrorMessage}; ${errorText}`;
    } else {
      this.lastVoiceQueryErrorMessage = errorText;
    }
  }

  private async listVoicesByEngineQuery(online: number): Promise<textToSpeech.VoiceInfo[]> {
    const candidates = this.buildVoiceQueryCandidates(online);
    let lastErrorText: string = 'unknown';

    for (const candidate of candidates) {
      let engine: textToSpeech.TextToSpeechEngine | null = null;
      try {
        engine = await textToSpeech.createEngine(candidate);
        const requestId = this.createRequestId('voice_engine');
        const voices = await engine.listVoices({ requestId, online });
        return voices;
      } catch (error) {
        lastErrorText = formatReadAloudError(error);
        logger.debug(
          TAG,
          `SYSTEM TTS 引擎回退查询失败: language=${candidate.language}, person=${candidate.person}, online=${candidate.online}, error=${lastErrorText}`
        );
      } finally {
        if (engine) {
          try {
            engine.shutdown();
          } catch (shutdownError) {
            logger.debug(TAG, `SYSTEM TTS 回退引擎释放失败: ${String(shutdownError)}`);
          }
        }
      }
    }
    throw new Error(lastErrorText);
  }

  private buildVoiceQueryCandidates(online: number): textToSpeech.CreateEngineParams[] {
    const candidates: textToSpeech.CreateEngineParams[] = [];
    const candidateKeys: Set<string> = new Set<string>();

    const addCandidate = (language: string, person: number): void => {
      if (!language || language.length === 0) {
        return;
      }
      const key = `${language}#${person}#${online}`;
      if (candidateKeys.has(key)) {
        return;
      }
      candidateKeys.add(key);
      candidates.push({ language, person, online });
    };

    const selectedParams = this.buildSelectedEngineParamsFromSettings(this.settings);
    if (selectedParams && selectedParams.online === online) {
      addCandidate(selectedParams.language, selectedParams.person);
    }

    if (this.preferredEngineParams) {
      addCandidate(this.preferredEngineParams.language, this.preferredEngineParams.person);
    }
    addCandidate('zh-CN', 0);
    addCandidate('zh_CN', 0);
    addCandidate('en-US', 0);
    addCandidate('en_US', 0);

    return candidates;
  }

  private buildSelectedEngineParamsFromSettings(settings: ReadAloudSettings | null): textToSpeech.CreateEngineParams | null {
    if (!settings) {
      return null;
    }
    const language = settings.voiceLanguage ?? '';
    const personRaw = settings.voicePerson ?? -1;
    const onlineRaw = settings.voiceOnline ?? -1;
    const person = Math.floor(personRaw);
    const online = Math.floor(onlineRaw);
    if (!language || language.length === 0 || person < 0 || (online !== 0 && online !== 1)) {
      return null;
    }
    return { language, person, online };
  }

  private getVoiceIdentityFromSettings(settings: ReadAloudSettings | null): string {
    const params = this.buildSelectedEngineParamsFromSettings(settings);
    if (!params) {
      return '';
    }
    return `${params.language}#${params.person}#${params.online}`;
  }

  private describeVoiceIdentity(identity: string): string {
    if (!identity || identity.length === 0) {
      return '系统默认';
    }
    return identity;
  }

  private pickTopVoices(voices: textToSpeech.VoiceInfo[]): textToSpeech.VoiceInfo[] {
    // TODO(听书): 将候选音色透出给设置面板，支持用户显式选择音色/离在线策略。
    const sortedVoices = voices.slice();
    sortedVoices.sort((a: textToSpeech.VoiceInfo, b: textToSpeech.VoiceInfo): number => this.voiceScore(b) - this.voiceScore(a));
    return sortedVoices.slice(0, MAX_CANDIDATE_VOICES);
  }

  private appendVoiceOptions(
    target: ReadAloudVoiceOption[],
    seenIds: Set<string>,
    voices: textToSpeech.VoiceInfo[],
    online: number
  ): void {
    for (const voice of voices) {
      const language = voice.language ?? '';
      const person = voice.person ?? 0;
      const status = voice.description ?? '';
      const voiceId = `${language}#${person}#${online}`;
      if (seenIds.has(voiceId)) {
        continue;
      }
      seenIds.add(voiceId);
      target.push(new ReadAloudVoiceOption(voiceId, language, person, online, status));
    }
  }

  private voiceScore(voice: textToSpeech.VoiceInfo): number {
    const language = (voice.language ?? '').toLowerCase();
    const description = (voice.description ?? '').toLowerCase();

    let score = 0;
    if (language.startsWith('zh')) {
      score += 100;
    } else if (language.startsWith('en')) {
      score += 50;
    }
    if (
      description.includes('download') ||
      description.includes('ready') ||
      description.includes('available') ||
      description.includes('本地')
    ) {
      score += 20;
    }
    return score;
  }

  private async speakCurrentChunk(): Promise<void> {
    const rawChunk = this.queue[this.queueIndex] ?? '';
    if (!rawChunk || rawChunk.trim().length === 0) {
      throw new Error('SYSTEM_TTS_INVALID_CHUNK_EMPTY');
    }
    const range = this.getQueueRange(this.queueIndex);
    const clampedCurrent = Math.max(range.start, Math.min(this.currentCharIndex, Math.max(range.start, range.end - 1)));
    const startCharIndex = clampedCurrent;
    const endCharIndex = range.end;
    const localOffset = Math.max(0, startCharIndex - range.start);
    const chunk = localOffset > 0 ? rawChunk.substring(localOffset) : rawChunk;
    if (!this.hasSpeakableChar(chunk)) {
      throw new Error('SYSTEM_TTS_INVALID_CHUNK_NO_SPEAKABLE_CHAR');
    }
    this.currentCharIndex = startCharIndex;
    this.updateProgressSnapshot(this.currentCharIndex, startCharIndex, endCharIndex);
    this.startChunkProgressTimer(startCharIndex, endCharIndex);
    await this.speakChunk(chunk);
  }

  private async speakCurrentChunkWithRecovery(): Promise<void> {
    try {
      await this.speakCurrentChunk();
    } catch (error) {
      const errorText = formatReadAloudError(error);
      if (this.isServiceNotInitializedErrorText(errorText)) {
        await this.recoverEngineAndReplayCurrentChunk(`speak_current_chunk: ${errorText}`);
        return;
      }
      throw error as Error;
    }
  }

  private async speakChunk(chunk: string): Promise<void> {
    if (!this.ttsEngine) {
      throw new Error('SYSTEM_TTS_ENGINE_NOT_READY');
    }

    const requestId = this.createRequestId('speak');
    this.clearChunkCompleteFallback();
    this.pendingRequestId = requestId;

    const speakParams: textToSpeech.SpeakParams = { requestId };
    if (this.supportsSpeakExtraParams) {
      speakParams.extraParams = this.buildSpeakExtraParams();
    }

    try {
      this.ttsEngine.speak(chunk, speakParams);
    } catch (error) {
      if (!this.supportsSpeakExtraParams) {
        this.clearChunkCompleteFallback();
        this.pendingRequestId = '';
        throw new Error(String(error));
      }

      // 对不支持自定义参数的设备，去掉 extraParams 再重试一次。
      this.supportsSpeakExtraParams = false;
      logger.warn(TAG, `SYSTEM TTS 使用 extraParams 朗读失败，改用基础模式重试: ${String(error)}`);
      const fallbackParams: textToSpeech.SpeakParams = { requestId };
      try {
        this.ttsEngine.speak(chunk, fallbackParams);
      } catch (fallbackError) {
        this.clearChunkCompleteFallback();
        this.pendingRequestId = '';
        throw new Error(String(fallbackError));
      }
    }
  }

  private speakCurrentChunkSafely(): void {
    this.speakCurrentChunkWithRecovery().catch((error: Object | string) => {
      logger.warn(TAG, `SYSTEM TTS 继续朗读失败: ${formatReadAloudError(error)}`);
      this.skipFailedChunkAndContinue();
    });
  }

  private handleChunkPlaybackCompleted(requestId: string, source: string): void {
    if (requestId !== this.pendingRequestId) {
      return;
    }
    this.clearChunkCompleteFallback();
    this.stopChunkProgressTimer();
    this.pendingRequestId = '';
    if (this.stopRequested || this.pauseRequested) {
      return;
    }

    const completedRange = this.getQueueRange(this.queueIndex);
    this.currentCharIndex = completedRange.end;
    this.updateProgressSnapshot(this.currentCharIndex, completedRange.start, completedRange.end);

    this.queueIndex += 1;
    this.chunkFailureRetryCount = 0;
    this.serviceRecoveryRetryCount = 0;
    // 仅在启动阶段做“可读分段归一化”，播放中不再跳过分段，避免出现误跳段。
    if (this.queueIndex >= this.queue.length) {
      logger.info(TAG, `SYSTEM TTS 已到达队列末尾: source=${source}`);
      this.queueIndex = 0;
      this.pauseRequested = true;
      this.stopRequested = false;
      this.notifyPlaybackEvent('completed', 'queue_finished', this.currentCharIndex);
      return;
    }
    this.speakCurrentChunkSafely();
  }

  private isServiceNotInitializedError(errorCode: number, errorMessage: string): boolean {
    if (errorCode === SYSTEM_TTS_SERVICE_NOT_INITIALIZED_CODE) {
      return true;
    }
    return this.isServiceNotInitializedErrorText(errorMessage);
  }

  private isServiceNotInitializedErrorText(errorText: string): boolean {
    const normalized = errorText.toLowerCase();
    return normalized.includes(String(SYSTEM_TTS_SERVICE_NOT_INITIALIZED_CODE)) ||
      normalized.includes('service not initialized');
  }

  private recoverEngineAndReplayCurrentChunkSafely(reason: string): void {
    this.recoverEngineAndReplayCurrentChunk(reason).catch((error: Object | string) => {
      logger.warn(TAG, `SYSTEM TTS 引擎恢复失败: reason=${reason}, error=${formatReadAloudError(error)}`);
      this.skipFailedChunkAndContinue();
    });
  }

  private async recoverEngineAndReplayCurrentChunk(reason: string): Promise<void> {
    if (this.pauseRequested || this.stopRequested) {
      return;
    }
    if (this.serviceRecoveryInProgress) {
      logger.debug(TAG, `SYSTEM TTS 正在恢复引擎，忽略重复请求: reason=${reason}`);
      return;
    }
    if (this.serviceRecoveryRetryCount >= 1) {
      throw new Error('SYSTEM_TTS_RECOVERY_RETRY_EXCEEDED');
    }

    this.serviceRecoveryRetryCount += 1;
    this.serviceRecoveryInProgress = true;
    logger.warn(TAG, `SYSTEM TTS 服务未初始化，尝试重建引擎并重试: reason=${reason}, retry=${this.serviceRecoveryRetryCount}`);
    this.pendingRequestId = '';
    this.clearChunkCompleteFallback();
    this.stopChunkProgressTimer();

    try {
      if (this.ttsEngine) {
        try {
          this.ttsEngine.stop();
        } catch (_stopError) {
        }
        try {
          this.ttsEngine.shutdown();
        } catch (_shutdownError) {
        }
      }
      this.ttsEngine = null;
      this.supportsSpeakExtraParams = true;
      await this.ensureEngineReady();
      if (this.pauseRequested || this.stopRequested) {
        return;
      }
      await this.speakCurrentChunk();
    } finally {
      this.serviceRecoveryInProgress = false;
    }
  }

  private skipFailedChunkAndContinue(): void {
    if (this.pauseRequested || this.stopRequested || this.queue.length === 0) {
      return;
    }

    if (this.chunkFailureRetryCount < 1) {
      this.chunkFailureRetryCount += 1;
      logger.warn(TAG, `SYSTEM TTS 当前分段朗读失败，准备重试: queueIndex=${this.queueIndex}, retry=${this.chunkFailureRetryCount}`);
      setTimeout(() => {
        if (this.pauseRequested || this.stopRequested) {
          return;
        }
        this.speakCurrentChunkSafely();
      }, 220);
      return;
    }

    const failedRange = this.getQueueRange(this.queueIndex);
    const stabilizedCharIndex = Math.max(
      failedRange.start,
      Math.min(this.currentCharIndex, failedRange.end)
    );
    this.currentCharIndex = stabilizedCharIndex;
    this.updateProgressSnapshot(this.currentCharIndex, failedRange.start, failedRange.end);
    this.pendingRequestId = '';
    this.pauseRequested = true;
    this.stopRequested = false;
    this.chunkFailureRetryCount = 0;
    this.serviceRecoveryRetryCount = 0;
    this.notifyPlaybackEvent('paused_for_error', 'chunk_retry_failed', this.currentCharIndex);
    logger.warn(TAG, `SYSTEM TTS 当前分段重试失败，已停留在原句等待用户继续: queueIndex=${this.queueIndex}, char=${this.currentCharIndex}`);
  }

  private scheduleChunkCompleteFallback(requestId: string, delayMs: number = SYNTH_COMPLETE_FALLBACK_INTERVAL_MS): void {
    if (requestId !== this.pendingRequestId) {
      return;
    }
    this.clearChunkCompleteFallback();
    const safeDelayMs = Math.max(SYNTH_COMPLETE_FALLBACK_INTERVAL_MS, Math.floor(delayMs));
    this.chunkCompleteFallbackTimer = setTimeout(() => {
      this.checkChunkCompleteFallback(requestId);
    }, safeDelayMs);
  }

  private isChunkCompleteSignalTooEarly(): boolean {
    if (this.speakingChunkEstimatedDurationMs <= 0 || this.speakingChunkStartTimeMs <= 0) {
      return false;
    }
    const elapsedMs = Date.now() - this.speakingChunkStartTimeMs;
    const minExpectedMs = Math.max(420, Math.min(2600, Math.floor(this.speakingChunkEstimatedDurationMs * 0.38)));
    return elapsedMs < minExpectedMs;
  }

  private getChunkCompleteGuardDelayMs(): number {
    if (this.speakingChunkEstimatedDurationMs <= 0 || this.speakingChunkStartTimeMs <= 0) {
      return SYNTH_COMPLETE_FALLBACK_INTERVAL_MS;
    }
    const elapsedMs = Date.now() - this.speakingChunkStartTimeMs;
    const minExpectedMs = Math.max(420, Math.min(2600, Math.floor(this.speakingChunkEstimatedDurationMs * 0.38)));
    return Math.max(SYNTH_COMPLETE_FALLBACK_INTERVAL_MS, minExpectedMs - elapsedMs);
  }

  private checkChunkCompleteFallback(requestId: string): void {
    this.chunkCompleteFallbackTimer = -1;
    if (requestId !== this.pendingRequestId) {
      return;
    }
    if (this.pauseRequested || this.stopRequested) {
      return;
    }

    let busy: boolean = true;
    if (this.ttsEngine) {
      try {
        busy = this.ttsEngine.isBusy();
      } catch (error) {
        logger.debug(TAG, `SYSTEM TTS isBusy 调用失败，继续等待: ${String(error)}`);
      }
    }

    if (busy) {
      this.chunkCompleteFallbackRetry += 1;
      if (this.chunkCompleteFallbackRetry > SYNTH_COMPLETE_FALLBACK_MAX_RETRY) {
        logger.warn(TAG, `SYSTEM TTS 播放完成补偿超时，强制推进分段: requestId=${requestId}`);
        this.handleChunkPlaybackCompleted(requestId, 'fallback_timeout');
        return;
      }
      this.chunkCompleteFallbackTimer = setTimeout(() => {
        this.checkChunkCompleteFallback(requestId);
      }, SYNTH_COMPLETE_FALLBACK_INTERVAL_MS);
      return;
    }

    this.handleChunkPlaybackCompleted(requestId, 'fallback_idle');
  }

  private clearChunkCompleteFallback(): void {
    if (this.chunkCompleteFallbackTimer !== -1) {
      clearTimeout(this.chunkCompleteFallbackTimer);
      this.chunkCompleteFallbackTimer = -1;
    }
    this.chunkCompleteFallbackRetry = 0;
  }

  private buildSpeakExtraParams(): Record<string, Object> {
    const speed = this.clamp(this.settings?.speed ?? 1, 0.5, 2.0);
    const pitch = this.clamp(this.settings?.pitch ?? 1, 0.5, 2.0);
    const volume = this.clamp(this.settings?.volume ?? 1, 0, 1.0);
    const extraParams: Record<string, Object> = new Object() as Record<string, Object>;
    extraParams.speed = new Number(Math.round(speed * 100));
    extraParams.pitch = new Number(Math.round(pitch * 100));
    extraParams.volume = new Number(Math.round(volume * 100));
    return extraParams;
  }

  private normalizeQueueIndexToSpeakableChunkFromCurrentChar(): boolean {
    while (this.queueIndex >= 0 && this.queueIndex < this.queue.length) {
      const range = this.getQueueRange(this.queueIndex);
      const chunk = this.queue[this.queueIndex] ?? '';
      const clampedCurrent = Math.max(range.start, Math.min(this.currentCharIndex, Math.max(range.start, range.end - 1)));
      const localOffset = Math.max(0, clampedCurrent - range.start);
      const candidate = localOffset > 0 ? chunk.substring(localOffset) : chunk;
      if (this.hasSpeakableChar(candidate)) {
        this.currentCharIndex = clampedCurrent;
        return true;
      }
      this.currentCharIndex = Math.max(range.start, range.end);
      this.updateProgressSnapshot(this.currentCharIndex, range.start, range.end);
      this.queueIndex += 1;
    }
    return false;
  }

  private hasSpeakableChar(text: string): boolean {
    if (!text || text.length <= 0) {
      return false;
    }
    for (let index = 0; index < text.length; index++) {
      if (this.isSpeakableChar(text.charAt(index))) {
        return true;
      }
    }
    return false;
  }

  private isSpeakableChar(char: string): boolean {
    if (!char || char.length <= 0) {
      return false;
    }
    const code = char.charCodeAt(0);
    if ((code >= 48 && code <= 57) || (code >= 65 && code <= 90) || (code >= 97 && code <= 122)) {
      return true;
    }
    if ((code >= 0x4E00 && code <= 0x9FFF) || (code >= 0x3400 && code <= 0x4DBF)) {
      return true;
    }
    if (code >= 0x3040 && code <= 0x30FF) {
      return true;
    }
    return code >= 0xAC00 && code <= 0xD7AF;
  }

  private startChunkProgressTimer(startCharIndex: number, endCharIndex: number): void {
    this.stopChunkProgressTimer();
    if (endCharIndex <= startCharIndex) {
      return;
    }

    const speed = this.clamp(this.settings?.speed ?? 1, 0.5, 2.0);
    const chunkLength = endCharIndex - startCharIndex;
    let charsPerSecond = Math.max(1, BASE_ESTIMATED_CHARS_PER_SECOND * speed);
    if (chunkLength >= 180) {
      charsPerSecond *= 0.72;
    } else if (chunkLength >= 120) {
      charsPerSecond *= 0.82;
    } else if (chunkLength >= 80) {
      charsPerSecond *= 0.9;
    }
    const punctuationPauseMs = this.estimateChunkPauseMs(startCharIndex, endCharIndex);
    const estimatedDurationMs = Math.max(
      CHUNK_PROGRESS_MIN_DURATION_MS,
      Math.round((chunkLength / charsPerSecond) * 1000 + punctuationPauseMs)
    );

    this.speakingChunkStartCharIndex = startCharIndex;
    this.speakingChunkEndCharIndex = endCharIndex;
    this.speakingChunkStartTimeMs = Date.now();
    this.speakingChunkEstimatedDurationMs = estimatedDurationMs;

    this.chunkProgressTimer = setInterval(() => {
      this.updateApproximateChunkProgress();
    }, CHUNK_PROGRESS_TIMER_INTERVAL_MS);
  }

  private estimateChunkPauseMs(startCharIndex: number, endCharIndex: number): number {
    const content = this.context?.content ?? '';
    if (content.length <= 0) {
      return 0;
    }
    const safeStart = Math.max(0, Math.min(startCharIndex, content.length));
    const safeEnd = Math.max(safeStart, Math.min(endCharIndex, content.length));
    let sentencePauseCount = 0;
    let phrasePauseCount = 0;
    for (let index = safeStart; index < safeEnd; index++) {
      const char = content.charAt(index);
      if (this.isSentenceBoundaryChar(char)) {
        sentencePauseCount += 1;
        continue;
      }
      if (char === ',' || char === '，' || char === '、' || char === ':' || char === '：') {
        phrasePauseCount += 1;
      }
    }
    const basePauseMs = sentencePauseCount * CHUNK_PROGRESS_SENTENCE_PAUSE_MS +
      phrasePauseCount * CHUNK_PROGRESS_PHRASE_PAUSE_MS;
    const chunkLength = safeEnd - safeStart;
    const naturalBreakCount = sentencePauseCount + phrasePauseCount;
    return basePauseMs + this.estimateLongChunkExtraMs(chunkLength, naturalBreakCount);
  }

  private estimateLongChunkExtraMs(chunkLength: number, naturalBreakCount: number): number {
    if (chunkLength < 80) {
      return 0;
    }
    const lengthFactor = chunkLength - 80;
    const breakPenalty = Math.max(0, 3 - naturalBreakCount);
    return Math.min(1800, Math.round(lengthFactor * 7 + breakPenalty * 140));
  }

  private updateApproximateChunkProgress(): void {
    if (this.speakingChunkStartCharIndex < 0 || this.speakingChunkEndCharIndex <= this.speakingChunkStartCharIndex) {
      return;
    }
    if (this.pauseRequested || this.stopRequested || this.pendingRequestId.length === 0) {
      return;
    }

    const elapsed = Date.now() - this.speakingChunkStartTimeMs;
    const duration = Math.max(1, this.speakingChunkEstimatedDurationMs);
    const ratio = Math.max(0, Math.min(1, elapsed / duration));
    const chunkLength = this.speakingChunkEndCharIndex - this.speakingChunkStartCharIndex;
    const approxCharIndex = this.speakingChunkStartCharIndex + Math.floor(chunkLength * ratio);
    const guardTailChars = chunkLength > 1 ? CHUNK_PROGRESS_GUARD_TAIL_CHARS : 0;
    const maxApproxCharIndex = Math.max(this.speakingChunkStartCharIndex, this.speakingChunkEndCharIndex - guardTailChars);
    const nextCharIndex = Math.max(this.currentCharIndex, Math.min(approxCharIndex, maxApproxCharIndex));
    if (nextCharIndex === this.currentCharIndex) {
      return;
    }

    this.currentCharIndex = nextCharIndex;
    this.updateProgressSnapshot(
      this.currentCharIndex,
      this.speakingChunkStartCharIndex,
      this.speakingChunkEndCharIndex
    );
  }

  private stopChunkProgressTimer(): void {
    if (this.chunkProgressTimer !== -1) {
      clearInterval(this.chunkProgressTimer);
      this.chunkProgressTimer = -1;
    }
    this.speakingChunkStartCharIndex = -1;
    this.speakingChunkEndCharIndex = -1;
    this.speakingChunkStartTimeMs = 0;
    this.speakingChunkEstimatedDurationMs = 0;
  }

  private rebuildQueue(content: string): void {
    this.queue = [];
    this.queueStartCharIndex = [];
    this.queueEndCharIndex = [];

    // 保持与阅读器分页使用同一份原始内容，避免字符索引错位。
    const sourceContent = content;
    if (sourceContent.trim().length === 0) {
      return;
    }

    const sentenceRanges = this.splitContentToSentenceRanges(sourceContent);
    for (const sentenceRange of sentenceRanges) {
      this.appendQueueByRange(sourceContent, sentenceRange.start, sentenceRange.end);
    }
  }

  private splitContentToSentenceRanges(content: string): QueueCharRange[] {
    const ranges: QueueCharRange[] = [];
    let sentenceStart = 0;
    let index = 0;
    while (index < content.length) {
      const char = content.charAt(index);
      if (!this.isSentenceBoundaryChar(char)) {
        index += 1;
        continue;
      }

      let sentenceEnd = index + 1;
      while (sentenceEnd < content.length) {
        const tailChar = content.charAt(sentenceEnd);
        if (!this.isSentenceTailChar(tailChar)) {
          break;
        }
        sentenceEnd += 1;
      }

      if (sentenceEnd > sentenceStart) {
        ranges.push(new QueueCharRange(sentenceStart, sentenceEnd));
      }
      sentenceStart = sentenceEnd;
      index = sentenceEnd;
    }

    if (sentenceStart < content.length) {
      ranges.push(new QueueCharRange(sentenceStart, content.length));
    }
    return ranges;
  }

  private appendQueueByRange(content: string, start: number, end: number): void {
    let chunkStart = Math.max(0, start);
    const chunkEndLimit = Math.max(chunkStart, Math.min(end, content.length));
    while (chunkStart < chunkEndLimit) {
      let chunkEnd = Math.min(chunkStart + MAX_SPEAK_CHUNK_LENGTH, chunkEndLimit);
      if (chunkEnd < chunkEndLimit) {
        chunkEnd = this.findChunkSplitPosition(content, chunkStart, chunkEnd);
        if (chunkEnd <= chunkStart) {
          chunkEnd = Math.min(chunkStart + MAX_SPEAK_CHUNK_LENGTH, chunkEndLimit);
        }
      }
      const chunk = content.slice(chunkStart, chunkEnd);
      if (chunk.trim().length > 0) {
        this.queue.push(chunk);
        this.queueStartCharIndex.push(chunkStart);
        this.queueEndCharIndex.push(chunkEnd);
      }
      chunkStart = chunkEnd;
    }
  }

  private isSentenceBoundaryChar(char: string): boolean {
    return char === '\n' ||
      char === '\r' ||
      char === '。' ||
      char === '！' ||
      char === '？' ||
      char === '!' ||
      char === '?' ||
      char === '.' ||
      char === '．' ||
      char === '｡' ||
      char === '…' ||
      char === '؟' ||
      char === '।' ||
      char === '॥' ||
      char === '؛' ||
      char === ';' ||
      char === '；';
  }

  private isSentenceTailChar(char: string): boolean {
    return char === '"' ||
      char === '\'' ||
      char === ')' ||
      char === '）' ||
      char === '】' ||
      char === '》' ||
      char === '」' ||
      char === '』' ||
      char === '”' ||
      char === '’';
  }

  private findChunkSplitPosition(content: string, start: number, end: number): number {
    for (let index = end; index > start; index--) {
      const char = content.charAt(index - 1);
      if (
        this.isSentenceBoundaryChar(char) ||
        char === ',' ||
        char === '，' ||
        char === '、' ||
        char === ':' ||
        char === '：'
      ) {
        return index;
      }
    }
    return end;
  }

  private getQueueRange(queueIndex: number): QueueCharRange {
    const safeIndex = Math.max(0, Math.min(queueIndex, this.queue.length - 1));
    const start = this.queueStartCharIndex[safeIndex] ?? 0;
    const end = this.queueEndCharIndex[safeIndex] ?? start;
    return new QueueCharRange(start, end);
  }

  private findQueueIndexByCharIndex(charIndex: number): number {
    if (this.queue.length === 0) {
      return 0;
    }
    if (charIndex <= 0) {
      return 0;
    }

    let previousMatchedIndex = 0;
    for (let index = 0; index < this.queue.length; index++) {
      const start = this.queueStartCharIndex[index] ?? 0;
      const end = this.queueEndCharIndex[index] ?? start;
      if (charIndex < start) {
        return previousMatchedIndex;
      }
      if (charIndex >= start && charIndex < end) {
        return index;
      }
      previousMatchedIndex = index;
    }
    return previousMatchedIndex;
  }

  private normalizeResumeCharIndex(resumeCharIndex: number, content: string): number {
    if (content.length <= 0) {
      return 0;
    }
    if (resumeCharIndex < 0) {
      return 0;
    }
    if (resumeCharIndex >= content.length) {
      return content.length - 1;
    }
    return resumeCharIndex;
  }

  private createQueueToken(): string {
    if (!this.context) {
      return '';
    }
    return `${this.context.bookId}#${this.context.chapterIndex}#${this.context.content.length}`;
  }

  private createRequestId(prefix: string): string {
    this.requestSerial += 1;
    return ReadAloudRequestIdGenerator.next(`${prefix}_${this.requestSerial}`);
  }

  private clamp(value: number, min: number, max: number): number {
    return Math.max(min, Math.min(max, value));
  }
}

class PlaceholderReadAloudBackend extends BaseReadAloudBackend {
  async start(): Promise<void> {
    // TODO(听书): 对接 Legado 兼容链路（分段策略、回调语义与系统后端保持一致）。
    logger.debug(TAG, `占位后端启动: engine=${this.engineType}, hasContext=${this.context !== null}`);
  }

  async pause(): Promise<void> {
    logger.debug(TAG, `占位后端暂停: engine=${this.engineType}`);
  }

  async stop(): Promise<void> {
    logger.debug(TAG, `占位后端停止: engine=${this.engineType}`);
  }
}

class RemoteReadAloudBackend extends BaseReadAloudBackend {
  async start(): Promise<void> {
    // TODO(听书): 对接远程TTS服务（鉴权、断点续播、缓存与失败重试）。
    logger.info(TAG, '远程听书后端暂未实现');
  }

  async pause(): Promise<void> {
    logger.debug(TAG, '远程听书后端暂停（占位实现）');
  }

  async stop(): Promise<void> {
    logger.debug(TAG, '远程听书后端停止（占位实现）');
  }
}

export class ReadAloudBackendFactory {
  static create(engineType: ReadAloudEngineType): IReadAloudBackend {
    switch (engineType) {
      case ReadAloudEngineType.SYSTEM:
        return new SystemReadAloudBackend(ReadAloudEngineType.SYSTEM);
      case ReadAloudEngineType.LEGADO_COMPAT:
        return new PlaceholderReadAloudBackend(ReadAloudEngineType.LEGADO_COMPAT);
      case ReadAloudEngineType.REMOTE:
        return new RemoteReadAloudBackend(ReadAloudEngineType.REMOTE);
      default:
        return new SystemReadAloudBackend(ReadAloudEngineType.SYSTEM);
    }
  }
}

export class ReadAloudVoiceCatalog {
  private static pendingTasks: Map<ReadAloudEngineType, Promise<ReadAloudVoiceOption[]>> =
    new Map<ReadAloudEngineType, Promise<ReadAloudVoiceOption[]>>();

  static async listVoices(engineType: ReadAloudEngineType): Promise<ReadAloudVoiceOption[]> {
    const pendingTask = ReadAloudVoiceCatalog.pendingTasks.get(engineType);
    if (pendingTask) {
      return await pendingTask;
    }

    const task = ReadAloudVoiceCatalog.queryVoices(engineType);
    ReadAloudVoiceCatalog.pendingTasks.set(engineType, task);
    try {
      return await task;
    } finally {
      ReadAloudVoiceCatalog.pendingTasks.delete(engineType);
    }
  }

  private static async queryVoices(engineType: ReadAloudEngineType): Promise<ReadAloudVoiceOption[]> {
    const backend = ReadAloudBackendFactory.create(engineType);
    try {
      return await backend.listVoices();
    } catch (error) {
      const errorText = formatReadAloudError(error);
      logger.warn(TAG, `拉取音色列表失败: engine=${engineType}, error=${errorText}`);
      throw new Error(errorText);
    } finally {
      await backend.release();
    }
  }
}
