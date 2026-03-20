import { logger } from '../../Utils/Logger';
import {
  DEFAULT_READ_ALOUD_SETTINGS,
  DEFAULT_REMOTE_READ_ALOUD_SETTINGS,
  ReadAloudEngineType,
  ReadAloudSettings,
  RemoteReadAloudSettings,
  normalizeReadAloudSettings,
  normalizeRemoteReadAloudSettings
} from '../../Models/TextReaderModels';
import { ReadAloudProgressSnapshot, ReadAloudSessionContext, ReadAloudVoiceOption } from './ReadAloudTypes';
import { ReadAloudRequestIdGenerator } from './ReadAloudRequestIdGenerator';
import { textToSpeech } from '@kit.CoreSpeechKit';
import { http } from '@kit.NetworkKit';
import fs from '@ohos.file.fs';
import { util } from '@kit.ArkTS';
import { media } from '@kit.MediaKit';
import { uiContextManager } from '../Managers/UIContextManager';

const TAG = 'ReadAloudBackends';
const MAX_SPEAK_CHUNK_LENGTH = 240;
const MAX_CANDIDATE_VOICES = 12;
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
const SYSTEM_TTS_CREATE_ENGINE_FAILED_CODE: number = 1002300005;
const SYSTEM_TTS_SERVICE_NOT_INITIALIZED_CODE: number = 1002300007;
const SYSTEM_TTS_INVALID_CHUNK_EMPTY: string = 'SYSTEM_TTS_INVALID_CHUNK_EMPTY';
const SYSTEM_TTS_INVALID_CHUNK_NO_SPEAKABLE_CHAR: string = 'SYSTEM_TTS_INVALID_CHUNK_NO_SPEAKABLE_CHAR';
const REMOTE_TTS_MANIFEST_VERSION: number = 1;
const REMOTE_TTS_DEFAULT_CHARS_PER_SECOND: number = 11;
const REMOTE_TTS_PREFETCH_MIN: number = 1;
const REMOTE_TTS_PREFETCH_MAX: number = 8;
const REMOTE_TTS_FALLBACK_PLAYBACK_GUARD_MS: number = 1600;
const REMOTE_TTS_FALLBACK_SEGMENT_MIN_MS: number = 580;
const REMOTE_TTS_PROGRESS_TIMER_MS: number = 120;

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

interface RemoteTtsSegmentCacheRecord {
  index: number;
  start: number;
  end: number;
  textDigest: string;
  filePath: string;
  bytes: number;
  durationMs: number;
}

interface RemoteTtsManifest {
  version: number;
  updatedAt: number;
  bookId: string;
  chapterIndex: number;
  contentDigest: string;
  remoteDigest: string;
  audioFormat: string;
  segments: RemoteTtsSegmentCacheRecord[];
  mergedFilePath?: string;
}

interface RemoteTtsHttpResult {
  statusCode: number;
  headers: Record<string, string>;
  result: string | ArrayBuffer;
}

interface RemoteTtsSynthesizedSegment {
  bytes: Uint8Array;
  durationMs: number;
}

interface RemoteTtsPlayableSegment extends RemoteTtsSegmentCacheRecord {
  durationMs: number;
}

interface RemoteTtsBase64JsonPayload {
  audio?: string;
  audio_base64?: string;
  base64?: string;
  data?: string | RemoteTtsBase64JsonPayload;
  url?: string;
  audio_url?: string;
  bytes?: string;
  result?: RemoteTtsBase64JsonPayload;
  output?: RemoteTtsBase64JsonPayload;
}

type RemoteJsonValue = string | number | boolean | Object | Array<Object> | null;
type RemoteJsonRecord = Record<string, RemoteJsonValue>;

interface RemoteRequestField {
  key: string;
  value: string | boolean;
}

function parseJsonObject(text: string): Record<string, Object> | null {
  if (!text || text.trim().length <= 0) {
    return null;
  }
  try {
    const data = JSON.parse(text) as Object;
    if (data && typeof data === 'object' && !Array.isArray(data)) {
      return data as Record<string, Object>;
    }
  } catch (_ignored) {
  }
  return null;
}

function sanitizeFileNamePart(raw: string): string {
  if (!raw || raw.length <= 0) {
    return 'unknown';
  }
  return raw.replace(/[^a-zA-Z0-9_.-]/g, '_');
}

function fnv1aHashHex(input: string): string {
  let hash = 0x811c9dc5;
  for (let index = 0; index < input.length; index++) {
    hash ^= input.charCodeAt(index);
    hash += (hash << 1) + (hash << 4) + (hash << 7) + (hash << 8) + (hash << 24);
  }
  const safe = hash >>> 0;
  return safe.toString(16).padStart(8, '0');
}

function ensureDirExists(path: string): void {
  try {
    if (!fs.accessSync(path)) {
      fs.mkdirSync(path);
    }
  } catch (_ignored) {
  }
}

function normalizeAudioExtension(format: string): string {
  const normalized = format.trim().toLowerCase();
  if (normalized === 'mpeg') {
    return 'mp3';
  }
  if (normalized === 'wave') {
    return 'wav';
  }
  if (normalized.length <= 0) {
    return 'mp3';
  }
  return normalized;
}

function isLikelyJsonContentType(contentType: string): boolean {
  const normalized = contentType.toLowerCase();
  return normalized.includes('application/json') || normalized.includes('text/json');
}

function isLikelyTextContentType(contentType: string): boolean {
  const normalized = contentType.toLowerCase();
  return normalized.includes('text/') || normalized.includes('application/json') || normalized.includes('application/x-ndjson');
}

function isLikelyTextBytes(bytes: Uint8Array): boolean {
  if (bytes.length <= 0) {
    return true;
  }
  const sampleSize = Math.min(256, bytes.length);
  let printableCount = 0;
  for (let index = 0; index < sampleSize; index++) {
    const value = bytes[index];
    if (value === 9 || value === 10 || value === 13 || (value >= 32 && value <= 126)) {
      printableCount += 1;
    }
  }
  return printableCount / sampleSize > 0.86;
}

function toUint8Array(data: ArrayBuffer): Uint8Array {
  return new Uint8Array(data);
}

function concatUint8ArrayParts(parts: Uint8Array[]): Uint8Array {
  let totalLength = 0;
  for (const part of parts) {
    totalLength += part.length;
  }
  const merged = new Uint8Array(totalLength);
  let offset = 0;
  for (const part of parts) {
    merged.set(part, offset);
    offset += part.length;
  }
  return merged;
}

function decodeBase64TextToBytes(base64Text: string): Uint8Array {
  const text = base64Text.replace(/\s+/g, '');
  if (text.length <= 0) {
    return new Uint8Array(0);
  }
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  const table: Map<string, number> = new Map<string, number>();
  for (let i = 0; i < alphabet.length; i++) {
    table.set(alphabet.charAt(i), i);
  }

  const bytes: number[] = [];
  let index = 0;
  while (index < text.length) {
    const c1 = text.charAt(index++);
    const c2 = text.charAt(index++);
    const c3 = text.charAt(index++);
    const c4 = text.charAt(index++);

    if (!table.has(c1) || !table.has(c2)) {
      break;
    }
    const b1 = table.get(c1) ?? 0;
    const b2 = table.get(c2) ?? 0;
    const b3 = c3 === '=' ? -1 : (table.get(c3) ?? -1);
    const b4 = c4 === '=' ? -1 : (table.get(c4) ?? -1);

    bytes.push((b1 << 2) | (b2 >> 4));
    if (b3 >= 0) {
      bytes.push(((b2 & 0x0f) << 4) | (b3 >> 2));
      if (b4 >= 0) {
        bytes.push(((b3 & 0x03) << 6) | b4);
      }
    }
  }
  return new Uint8Array(bytes);
}

function estimateDurationMsByCharCount(charCount: number, speed: number): number {
  const safeCharCount = Math.max(1, charCount);
  const safeSpeed = Math.max(0.5, Math.min(2.0, speed));
  const charsPerSecond = Math.max(1, REMOTE_TTS_DEFAULT_CHARS_PER_SECOND * safeSpeed);
  return Math.max(REMOTE_TTS_FALLBACK_SEGMENT_MIN_MS, Math.round((safeCharCount / charsPerSecond) * 1000));
}

function readFileBytes(path: string): Uint8Array {
  const stat = fs.statSync(path);
  const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
  try {
    const buffer = new ArrayBuffer(stat.size);
    fs.readSync(file.fd, buffer);
    return new Uint8Array(buffer);
  } finally {
    fs.closeSync(file);
  }
}

function writeFileBytes(path: string, bytes: Uint8Array): void {
  const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
  try {
    fs.writeSync(file.fd, bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength));
  } finally {
    fs.closeSync(file);
  }
}

function isWavBytes(bytes: Uint8Array): boolean {
  return bytes.length > 12 &&
    bytes[0] === 0x52 && bytes[1] === 0x49 && bytes[2] === 0x46 && bytes[3] === 0x46 &&
    bytes[8] === 0x57 && bytes[9] === 0x41 && bytes[10] === 0x56 && bytes[11] === 0x45;
}

function readLittleEndianInt32(bytes: Uint8Array, offset: number): number {
  return (
    bytes[offset] |
    (bytes[offset + 1] << 8) |
    (bytes[offset + 2] << 16) |
    (bytes[offset + 3] << 24)
  ) >>> 0;
}

function readLittleEndianInt16(bytes: Uint8Array, offset: number): number {
  return bytes[offset] | (bytes[offset + 1] << 8);
}

interface WavPcmPayload {
  sampleRate: number;
  channels: number;
  bitsPerSample: number;
  pcmBytes: Uint8Array;
}

function extractWavPcmPayload(bytes: Uint8Array): WavPcmPayload | null {
  if (!isWavBytes(bytes)) {
    return null;
  }
  let offset = 12;
  let sampleRate = 24000;
  let channels = 1;
  let bitsPerSample = 16;
  let pcm: Uint8Array | null = null;
  while (offset + 8 <= bytes.length) {
    const c1 = String.fromCharCode(bytes[offset]);
    const c2 = String.fromCharCode(bytes[offset + 1]);
    const c3 = String.fromCharCode(bytes[offset + 2]);
    const c4 = String.fromCharCode(bytes[offset + 3]);
    const chunkId = `${c1}${c2}${c3}${c4}`;
    const chunkSize = readLittleEndianInt32(bytes, offset + 4);
    const dataStart = offset + 8;
    const dataEnd = Math.min(bytes.length, dataStart + chunkSize);
    if (chunkId === 'fmt ' && dataEnd - dataStart >= 16) {
      channels = Math.max(1, readLittleEndianInt16(bytes, dataStart + 2));
      sampleRate = Math.max(8000, readLittleEndianInt32(bytes, dataStart + 4));
      bitsPerSample = Math.max(8, readLittleEndianInt16(bytes, dataStart + 14));
    } else if (chunkId === 'data') {
      pcm = bytes.slice(dataStart, dataEnd);
      break;
    }
    offset = dataEnd + (chunkSize % 2);
  }
  if (!pcm) {
    return null;
  }
  return {
    sampleRate,
    channels,
    bitsPerSample,
    pcmBytes: pcm
  };
}

function createWavFromPcm(parts: Uint8Array[], sampleRate: number, channels: number, bitsPerSample: number): Uint8Array {
  const pcm = concatUint8ArrayParts(parts);
  const byteRate = Math.max(1, sampleRate * channels * (bitsPerSample / 8));
  const blockAlign = Math.max(1, channels * (bitsPerSample / 8));
  const header = new Uint8Array(44);

  // RIFF
  header.set([0x52, 0x49, 0x46, 0x46], 0);
  const fileSize = 36 + pcm.length;
  header[4] = fileSize & 0xff;
  header[5] = (fileSize >> 8) & 0xff;
  header[6] = (fileSize >> 16) & 0xff;
  header[7] = (fileSize >> 24) & 0xff;
  header.set([0x57, 0x41, 0x56, 0x45], 8);

  // fmt
  header.set([0x66, 0x6d, 0x74, 0x20], 12);
  header.set([16, 0, 0, 0], 16); // fmt chunk size
  header.set([1, 0], 20); // PCM
  header[22] = channels & 0xff;
  header[23] = (channels >> 8) & 0xff;
  header[24] = sampleRate & 0xff;
  header[25] = (sampleRate >> 8) & 0xff;
  header[26] = (sampleRate >> 16) & 0xff;
  header[27] = (sampleRate >> 24) & 0xff;
  header[28] = byteRate & 0xff;
  header[29] = (byteRate >> 8) & 0xff;
  header[30] = (byteRate >> 16) & 0xff;
  header[31] = (byteRate >> 24) & 0xff;
  header[32] = blockAlign & 0xff;
  header[33] = (blockAlign >> 8) & 0xff;
  header[34] = bitsPerSample & 0xff;
  header[35] = (bitsPerSample >> 8) & 0xff;

  // data
  header.set([0x64, 0x61, 0x74, 0x61], 36);
  header[40] = pcm.length & 0xff;
  header[41] = (pcm.length >> 8) & 0xff;
  header[42] = (pcm.length >> 16) & 0xff;
  header[43] = (pcm.length >> 24) & 0xff;

  return concatUint8ArrayParts([header, pcm]);
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
  private static sharedBlockedVoiceKeys: Set<string> = new Set<string>();
  private static sharedUnsupportedVoiceOnlineModes: Set<number> = new Set<number>();
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
  private validatedVoiceKeys: Set<string> = new Set<string>();

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
      if (this.isInvalidVoiceErrorText(errorMessage)) {
        this.handleInvalidVoiceAndRecoverSafely('speak_listener_error', `code=${errorCode}, message=${errorMessage}`);
        return;
      }
      if (this.isServiceNotInitializedError(errorCode, errorMessage)) {
        this.recoverEngineAndReplayCurrentChunkSafely('speak_listener_error');
        return;
      }
      this.skipFailedChunkAndContinue(`code=${errorCode}, message=${errorMessage}`);
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
    if (selectedParams) {
      const selectedVoiceKey = this.createVoiceKey(selectedParams.language, selectedParams.person, selectedParams.online);
      if (this.isVoiceKeyBlocked(selectedVoiceKey)) {
        logger.warn(TAG, `SYSTEM TTS 选中音色已被标记不可用，自动忽略: voiceKey=${selectedVoiceKey}`);
        this.preferredEngineParams = null;
      } else {
        this.preferredEngineParams = selectedParams;
      }
    } else {
      this.preferredEngineParams = null;
    }
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
    const filteredOptions = await this.filterUnavailableVoiceOptions(options);
    if (filteredOptions.length > 0) {
      return filteredOptions;
    }

    const safeDefaults = await this.buildSafeDefaultVoiceOptions();
    if (safeDefaults.length > 0) {
      logger.warn(TAG, `SYSTEM TTS 音色列表过滤后为空，已回退稳定音色: count=${safeDefaults.length}`);
      return safeDefaults;
    }

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
      const voiceKey = this.createVoiceKey(params.language, params.person, params.online);
      if (this.isVoiceKeyBlocked(voiceKey)) {
        logger.info(TAG, `SYSTEM TTS 跳过已屏蔽候选音色: ${voiceKey}`);
        continue;
      }
      try {
        const engine = await textToSpeech.createEngine(params);
        engine.setListener(this.speakListener);
        this.ttsEngine = engine;
        this.preferredEngineParams = params;
        this.validatedVoiceKeys.add(voiceKey);
        logger.info(TAG, `SYSTEM TTS 引擎就绪: language=${params.language}, person=${params.person}, online=${params.online}`);
        return;
      } catch (error) {
        lastError = formatReadAloudError(error);
        if (this.isInvalidVoiceErrorText(lastError)) {
          this.blockVoiceKey(voiceKey, lastError);
        }
        logger.warn(TAG, `SYSTEM TTS 候选引擎初始化失败: language=${params.language}, person=${params.person}, online=${params.online}, error=${lastError}`);
      }
    }

    throw new Error(`SYSTEM_TTS_INIT_FAILED: ${lastError}`);
  }

  private async buildEngineCandidates(): Promise<textToSpeech.CreateEngineParams[]> {
    const candidates: textToSpeech.CreateEngineParams[] = [];
    const candidateKeys: Set<string> = new Set<string>();

    const addCandidate = (language: string, person: number, online: number): void => {
      if (!language || language.length <= 0) {
        return;
      }
      if (SystemReadAloudBackend.sharedUnsupportedVoiceOnlineModes.has(online)) {
        return;
      }
      const key = `${language}#${person}#${online}`;
      if (this.isVoiceKeyBlocked(key)) {
        return;
      }
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
    if (SystemReadAloudBackend.sharedUnsupportedVoiceOnlineModes.has(safeOnline)) {
      logger.info(TAG, `SYSTEM TTS 已记录当前设备不支持该online模式，跳过查询: online=${safeOnline}`);
      return [];
    }
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
      this.markOnlineModeUnsupportedIfNeeded(safeOnline, fallbackErrorText);
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
        const voiceKey = this.createVoiceKey(candidate.language, candidate.person, candidate.online);
        if (this.isInvalidVoiceErrorText(lastErrorText)) {
          this.blockVoiceKey(voiceKey, lastErrorText);
        }
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
    if (SystemReadAloudBackend.sharedUnsupportedVoiceOnlineModes.has(online)) {
      return candidates;
    }

    const addCandidate = (language: string, person: number): void => {
      if (!language || language.length === 0) {
        return;
      }
      const key = `${language}#${person}#${online}`;
      if (this.isVoiceKeyBlocked(key)) {
        return;
      }
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
      const style = voice.style ?? '';
      const gender = voice.gender ?? '';
      const voiceId = `${language}#${person}#${online}`;
      if (this.isVoiceKeyBlocked(voiceId)) {
        logger.info(TAG, `SYSTEM TTS 跳过已屏蔽音色: voiceId=${voiceId}`);
        continue;
      }
      if (seenIds.has(voiceId)) {
        continue;
      }
      seenIds.add(voiceId);
      target.push(new ReadAloudVoiceOption(voiceId, language, person, online, status, style, gender));
    }
  }

  private async filterUnavailableVoiceOptions(options: ReadAloudVoiceOption[]): Promise<ReadAloudVoiceOption[]> {
    const filtered: ReadAloudVoiceOption[] = [];
    for (const option of options) {
      const voiceKey = this.createVoiceKey(option.language, option.person, option.online);
      if (this.isVoiceKeyBlocked(voiceKey)) {
        continue;
      }
      if (this.validatedVoiceKeys.has(voiceKey)) {
        filtered.push(option);
        continue;
      }
      const isUsable = await this.validateVoiceOptionByCreateEngine(option.language, option.person, option.online);
      if (!isUsable) {
        continue;
      }
      filtered.push(option);
    }
    return filtered;
  }

  private async buildSafeDefaultVoiceOptions(): Promise<ReadAloudVoiceOption[]> {
    const safeOptions: ReadAloudVoiceOption[] = [];
    const seen: Set<string> = new Set<string>();
    const defaults: textToSpeech.CreateEngineParams[] = [
      { language: 'zh-CN', person: 0, online: SYSTEM_TTS_OFFLINE_MODE },
      { language: 'zh_CN', person: 0, online: SYSTEM_TTS_OFFLINE_MODE },
      { language: 'en-US', person: 0, online: SYSTEM_TTS_OFFLINE_MODE },
      { language: 'en_US', person: 0, online: SYSTEM_TTS_OFFLINE_MODE },
      { language: 'zh-CN', person: 0, online: SYSTEM_TTS_ONLINE_MODE },
      { language: 'zh_CN', person: 0, online: SYSTEM_TTS_ONLINE_MODE },
      { language: 'en-US', person: 0, online: SYSTEM_TTS_ONLINE_MODE },
      { language: 'en_US', person: 0, online: SYSTEM_TTS_ONLINE_MODE }
    ];

    for (const item of defaults) {
      const voiceKey = this.createVoiceKey(item.language, item.person, item.online);
      if (seen.has(voiceKey) || this.isVoiceKeyBlocked(voiceKey)) {
        continue;
      }
      seen.add(voiceKey);
      const isUsable = await this.validateVoiceOptionByCreateEngine(item.language, item.person, item.online);
      if (!isUsable) {
        continue;
      }
      safeOptions.push(new ReadAloudVoiceOption(voiceKey, item.language, item.person, item.online, '默认稳定音色'));
    }
    return safeOptions;
  }

  private createVoiceKey(language: string, person: number, online: number): string {
    return `${language}#${person}#${online}`;
  }

  private isVoiceKeyBlocked(voiceKey: string): boolean {
    return SystemReadAloudBackend.sharedBlockedVoiceKeys.has(voiceKey);
  }

  private blockVoiceKey(voiceKey: string, reason: string): void {
    if (SystemReadAloudBackend.sharedBlockedVoiceKeys.has(voiceKey)) {
      return;
    }
    SystemReadAloudBackend.sharedBlockedVoiceKeys.add(voiceKey);
    this.validatedVoiceKeys.delete(voiceKey);
    logger.warn(TAG, `SYSTEM TTS 标记音色不可用: voiceKey=${voiceKey}, reason=${reason}`);
  }

  private isInvalidVoiceErrorText(errorText: string): boolean {
    const normalized = errorText.toLowerCase();
    if (normalized.includes('invalid relative path')) {
      return true;
    }
    if (normalized.includes(String(SYSTEM_TTS_CREATE_ENGINE_FAILED_CODE))) {
      return true;
    }
    return normalized.includes('create engine error') || normalized.includes('createengine error');
  }

  private markOnlineModeUnsupportedIfNeeded(online: number, errorText: string): void {
    if (SystemReadAloudBackend.sharedUnsupportedVoiceOnlineModes.has(online)) {
      return;
    }
    const normalized = errorText.toLowerCase();
    if (!normalized.includes('online type error')) {
      return;
    }
    SystemReadAloudBackend.sharedUnsupportedVoiceOnlineModes.add(online);
    logger.warn(TAG, `SYSTEM TTS 标记online模式暂不可用: online=${online}, reason=${errorText}`);
  }

  private async validateVoiceOptionByCreateEngine(language: string, person: number, online: number): Promise<boolean> {
    const voiceKey = this.createVoiceKey(language, person, online);
    if (this.isVoiceKeyBlocked(voiceKey)) {
      return false;
    }
    let engine: textToSpeech.TextToSpeechEngine | null = null;
    try {
      engine = await textToSpeech.createEngine({ language, person, online });
      this.validatedVoiceKeys.add(voiceKey);
      return true;
    } catch (error) {
      const errorText = formatReadAloudError(error);
      if (this.isInvalidVoiceErrorText(errorText)) {
        this.blockVoiceKey(voiceKey, errorText);
        return false;
      }
      logger.warn(TAG, `SYSTEM TTS 音色预校验失败但暂不屏蔽: voiceKey=${voiceKey}, error=${errorText}`);
      return true;
    } finally {
      if (engine) {
        try {
          engine.shutdown();
        } catch (shutdownError) {
          logger.debug(TAG, `SYSTEM TTS 音色预校验引擎释放失败: ${String(shutdownError)}`);
        }
      }
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
      throw new Error(SYSTEM_TTS_INVALID_CHUNK_EMPTY);
    }
    const range = this.getQueueRange(this.queueIndex);
    const clampedCurrent = Math.max(range.start, Math.min(this.currentCharIndex, Math.max(range.start, range.end - 1)));
    const startCharIndex = clampedCurrent;
    const endCharIndex = range.end;
    const localOffset = Math.max(0, startCharIndex - range.start);
    const chunk = localOffset > 0 ? rawChunk.substring(localOffset) : rawChunk;
    if (!this.hasSpeakableChar(chunk)) {
      throw new Error(SYSTEM_TTS_INVALID_CHUNK_NO_SPEAKABLE_CHAR);
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
      if (this.isInvalidVoiceErrorText(errorText)) {
        await this.handleInvalidVoiceAndRecover(`speak_current_chunk: ${errorText}`);
        return;
      }
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
      const errorText = formatReadAloudError(error);
      logger.warn(TAG, `SYSTEM TTS 继续朗读失败: ${errorText}`);
      this.skipFailedChunkAndContinue(errorText);
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

  private handleInvalidVoiceAndRecoverSafely(reason: string, errorText: string): void {
    this.handleInvalidVoiceAndRecover(`${reason}: ${errorText}`).catch((error: Object | string) => {
      const finalErrorText = formatReadAloudError(error);
      logger.warn(TAG, `SYSTEM TTS 无效音色回退失败: reason=${reason}, error=${finalErrorText}`);
      this.skipFailedChunkAndContinue(finalErrorText);
    });
  }

  private async handleInvalidVoiceAndRecover(reason: string): Promise<void> {
    if (this.pauseRequested || this.stopRequested) {
      return;
    }
    this.excludeCurrentPreferredVoice(reason);
    await this.recoverEngineAndReplayCurrentChunk(`invalid_voice: ${reason}`);
  }

  private excludeCurrentPreferredVoice(reason: string): void {
    if (!this.preferredEngineParams) {
      return;
    }
    const voiceKey = this.createVoiceKey(
      this.preferredEngineParams.language,
      this.preferredEngineParams.person,
      this.preferredEngineParams.online
    );
    this.blockVoiceKey(voiceKey, `runtime_failure: ${reason}`);
    this.preferredEngineParams = null;

    if (this.ttsEngine) {
      try {
        this.ttsEngine.stop();
      } catch (_stopError) {
      }
      try {
        this.ttsEngine.shutdown();
      } catch (_shutdownError) {
      }
      this.ttsEngine = null;
    }
    this.pendingRequestId = '';
    this.clearChunkCompleteFallback();
    this.stopChunkProgressTimer();
  }

  private recoverEngineAndReplayCurrentChunkSafely(reason: string): void {
    this.recoverEngineAndReplayCurrentChunk(reason).catch((error: Object | string) => {
      const errorText = formatReadAloudError(error);
      logger.warn(TAG, `SYSTEM TTS 引擎恢复失败: reason=${reason}, error=${errorText}`);
      this.skipFailedChunkAndContinue(errorText);
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

  private skipFailedChunkAndContinue(errorText: string = ''): void {
    if (this.pauseRequested || this.stopRequested || this.queue.length === 0) {
      return;
    }

    if (this.trySkipUnspeakableChunkAndContinue(errorText)) {
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

  private isInvalidChunkErrorText(errorText: string): boolean {
    if (!errorText || errorText.length <= 0) {
      return false;
    }
    return errorText.includes(SYSTEM_TTS_INVALID_CHUNK_EMPTY) ||
      errorText.includes(SYSTEM_TTS_INVALID_CHUNK_NO_SPEAKABLE_CHAR);
  }

  private finishQueueAfterUnspeakableSkip(reason: string): void {
    this.queueIndex = 0;
    this.pauseRequested = true;
    this.stopRequested = false;
    this.chunkFailureRetryCount = 0;
    this.serviceRecoveryRetryCount = 0;
    this.notifyPlaybackEvent('completed', reason, this.currentCharIndex);
  }

  private trySkipUnspeakableChunkAndContinue(errorText: string): boolean {
    if (!this.isInvalidChunkErrorText(errorText)) {
      return false;
    }
    if (this.queue.length <= 0) {
      return true;
    }

    const failedRange = this.getQueueRange(this.queueIndex);
    this.currentCharIndex = Math.max(failedRange.start, failedRange.end);
    this.updateProgressSnapshot(this.currentCharIndex, failedRange.start, failedRange.end);
    this.pendingRequestId = '';

    this.queueIndex += 1;
    this.chunkFailureRetryCount = 0;
    this.serviceRecoveryRetryCount = 0;

    if (this.queueIndex >= this.queue.length) {
      logger.info(
        TAG,
        `SYSTEM TTS 不可朗读分段已自动跳过并到达末尾: error=${errorText}, queueIndex=${this.queueIndex}, char=${this.currentCharIndex}`
      );
      this.finishQueueAfterUnspeakableSkip('queue_finished_after_unspeakable_skip');
      return true;
    }

    if (!this.normalizeQueueIndexToSpeakableChunkFromCurrentChar()) {
      logger.info(
        TAG,
        `SYSTEM TTS 后续无可朗读分段，自动结束: error=${errorText}, queueIndex=${this.queueIndex}, char=${this.currentCharIndex}`
      );
      this.finishQueueAfterUnspeakableSkip('queue_finished_after_unspeakable_skip');
      return true;
    }

    const nextRange = this.getQueueRange(this.queueIndex);
    this.updateProgressSnapshot(this.currentCharIndex, nextRange.start, nextRange.end);
    logger.warn(
      TAG,
      `SYSTEM TTS 检测到不可朗读分段，已自动跳过继续: error=${errorText}, nextQueueIndex=${this.queueIndex}, char=${this.currentCharIndex}`
    );
    this.speakCurrentChunkSafely();
    return true;
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
        if (this.hasSpeakableChar(chunk)) {
          this.queue.push(chunk);
          this.queueStartCharIndex.push(chunkStart);
          this.queueEndCharIndex.push(chunkEnd);
        } else {
          logger.debug(TAG, `SYSTEM TTS 忽略不可朗读分段: range=${chunkStart}-${chunkEnd}`);
        }
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

class RemoteReadAloudBackendLegacy extends BaseReadAloudBackend {
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

class RemoteReadAloudBackend extends BaseReadAloudBackend {
  private queue: string[] = [];
  private queueStart: number[] = [];
  private queueEnd: number[] = [];
  private queueToken: string = '';
  private queueIndex: number = 0;
  private currentCharIndex: number = 0;
  private stopRequested: boolean = false;
  private pauseRequested: boolean = false;
  private playbackSessionToken: string = '';
  private requestSerial: number = 0;
  private progressTimer: number = -1;
  private progressStartMs: number = 0;
  private progressDurationMs: number = 0;
  private progressRangeStart: number = -1;
  private progressRangeEnd: number = -1;

  private remoteSettings: RemoteReadAloudSettings =
    normalizeRemoteReadAloudSettings(DEFAULT_REMOTE_READ_ALOUD_SETTINGS);
  private pendingSynthesis: Map<number, Promise<RemoteTtsPlayableSegment>> =
    new Map<number, Promise<RemoteTtsPlayableSegment>>();
  private playableSegments: Map<number, RemoteTtsPlayableSegment> =
    new Map<number, RemoteTtsPlayableSegment>();

  private cacheRootDir: string = '';
  private chapterCacheDir: string = '';
  private manifestPath: string = '';
  private activeManifest: RemoteTtsManifest | null = null;
  private contentDigest: string = '';
  private remoteDigest: string = '';
  private sessionTempDir: string = '';

  applySettings(settings: ReadAloudSettings): void {
    const normalized = normalizeReadAloudSettings(settings);
    super.applySettings(normalized);
    this.remoteSettings = normalizeRemoteReadAloudSettings(normalized.remote);
  }

  updateContext(context: ReadAloudSessionContext | null): void {
    super.updateContext(context);
    if (!context) {
      this.queue = [];
      this.queueStart = [];
      this.queueEnd = [];
      this.queueToken = '';
      this.queueIndex = 0;
      this.currentCharIndex = 0;
      this.pendingSynthesis.clear();
      this.playableSegments.clear();
      this.activeManifest = null;
      this.stopProgressTimer();
      this.updateProgressSnapshot(-1, -1, -1);
      return;
    }
    const resumeChar = this.normalizeResumeCharIndex(context.resumeCharIndex ?? 0, context.content);
    const contentDigest = fnv1aHashHex(context.content);
    const remoteDigest = this.buildRemoteDigest(this.remoteSettings);
    const nextQueueToken = `${context.bookId}#${context.chapterIndex}#${contentDigest}#${remoteDigest}`;
    const inPlaybackFlow = this.queueToken === nextQueueToken &&
      this.queue.length > 0 &&
      this.playbackSessionToken.length > 0 &&
      !this.pauseRequested &&
      !this.stopRequested;
    if (!inPlaybackFlow && this.queueToken !== nextQueueToken) {
      this.rebuildQueue(context.content);
      this.queueToken = nextQueueToken;
      this.contentDigest = contentDigest;
      this.remoteDigest = remoteDigest;
      this.pendingSynthesis.clear();
      this.playableSegments.clear();
      this.activeManifest = null;
    }
    this.currentCharIndex = resumeChar;
    this.queueIndex = this.findQueueIndexByChar(resumeChar);
    const range = this.getQueueRange(this.queueIndex);
    this.updateProgressSnapshot(this.currentCharIndex, range.start, range.end);
  }

  async start(): Promise<void> {
    const content = this.context?.content ?? '';
    if (content.trim().length <= 0) {
      throw new Error('REMOTE_TTS_NO_CONTENT');
    }

    this.remoteSettings = this.resolveRemoteSettings();
    this.validateRemoteSettings(this.remoteSettings);
    this.stopRequested = false;
    this.pauseRequested = false;
    this.stopProgressTimer();

    const contentDigest = fnv1aHashHex(content);
    const remoteDigest = this.buildRemoteDigest(this.remoteSettings);
    const queueToken = `${this.context?.bookId ?? ''}#${this.context?.chapterIndex ?? -1}#${contentDigest}#${remoteDigest}`;
    if (this.queueToken !== queueToken || this.queue.length <= 0) {
      this.rebuildQueue(content);
      this.queueToken = queueToken;
      this.contentDigest = contentDigest;
      this.remoteDigest = remoteDigest;
      this.pendingSynthesis.clear();
      this.playableSegments.clear();
      this.activeManifest = null;
    }
    if (this.queue.length <= 0) {
      throw new Error('REMOTE_TTS_EMPTY_QUEUE');
    }

    await this.prepareCacheAndManifest();
    this.currentCharIndex = this.normalizeResumeCharIndex(this.context?.resumeCharIndex ?? this.currentCharIndex, content);
    this.queueIndex = this.findQueueIndexByChar(this.currentCharIndex);
    this.playbackSessionToken = this.createRequestId('remote_session');

    const range = this.getQueueRange(this.queueIndex);
    this.updateProgressSnapshot(this.currentCharIndex, range.start, range.end);
    this.prefetchSegments(this.queueIndex, this.playbackSessionToken);
    this.playLoopSafely(this.playbackSessionToken);
  }

  async pause(): Promise<void> {
    this.pauseRequested = true;
    this.stopRequested = false;
    this.playbackSessionToken = '';
    this.stopProgressTimer();
    const range = this.getQueueRange(this.queueIndex);
    this.updateProgressSnapshot(this.currentCharIndex, range.start, range.end);
  }

  async stop(): Promise<void> {
    this.stopRequested = true;
    this.pauseRequested = false;
    this.playbackSessionToken = '';
    this.stopProgressTimer();
    this.pendingSynthesis.clear();
    this.queueIndex = this.findQueueIndexByChar(this.currentCharIndex);
    const range = this.getQueueRange(this.queueIndex);
    this.updateProgressSnapshot(this.currentCharIndex, range.start, range.end);
  }

  async release(): Promise<void> {
    await this.stop();
    this.queue = [];
    this.queueStart = [];
    this.queueEnd = [];
    this.queueToken = '';
    this.queueIndex = 0;
    this.currentCharIndex = 0;
    this.playableSegments.clear();
    this.pendingSynthesis.clear();
    this.activeManifest = null;
    this.chapterCacheDir = '';
    this.manifestPath = '';
    this.updateProgressSnapshot(-1, -1, -1);
    await super.release();
  }

  async listVoices(): Promise<ReadAloudVoiceOption[]> {
    const remote = this.resolveRemoteSettings();
    const voice = remote.voice.trim();
    if (voice.length <= 0) {
      return [];
    }
    return [new ReadAloudVoiceOption(`remote#${voice}`, 'REMOTE', 0, 0, remote.model || 'REMOTE')];
  }

  private resolveRemoteSettings(): RemoteReadAloudSettings {
    const merged = normalizeReadAloudSettings(this.settings ?? DEFAULT_READ_ALOUD_SETTINGS);
    return normalizeRemoteReadAloudSettings(merged.remote);
  }

  private validateRemoteSettings(settings: RemoteReadAloudSettings): void {
    if (settings.endpoint.trim().length <= 0) {
      throw new Error('REMOTE_TTS_ENDPOINT_EMPTY');
    }
    if (settings.model.trim().length <= 0) {
      throw new Error('REMOTE_TTS_MODEL_EMPTY');
    }
    if (settings.voice.trim().length <= 0) {
      throw new Error('REMOTE_TTS_VOICE_EMPTY');
    }
  }

  private buildRemoteDigest(settings: RemoteReadAloudSettings): string {
    const digest = [
      settings.endpoint.trim(),
      settings.apiPath.trim(),
      settings.model.trim(),
      settings.voice.trim(),
      settings.audioFormat.trim(),
      String(settings.streamEnabled),
      String(settings.maxInputChars),
      String(settings.reservedInputChars),
      String(settings.minChunkChars),
      String(settings.targetChunkChars),
      String(settings.maxChunkChars),
      settings.extraBodyJson ?? ''
    ].join('|');
    return fnv1aHashHex(digest);
  }

  private normalizeResumeCharIndex(index: number, content: string): number {
    if (content.length <= 0) {
      return 0;
    }
    if (index < 0) {
      return 0;
    }
    if (index >= content.length) {
      return content.length - 1;
    }
    return index;
  }

  private rebuildQueue(content: string): void {
    this.queue = [];
    this.queueStart = [];
    this.queueEnd = [];
    if (!content || content.trim().length <= 0) {
      return;
    }

    const hardLimit = Math.max(64, this.remoteSettings.maxInputChars - this.remoteSettings.reservedInputChars);
    const maxChunk = Math.max(64, Math.min(this.remoteSettings.maxChunkChars, hardLimit));
    const targetChunk = Math.max(64, Math.min(this.remoteSettings.targetChunkChars, maxChunk));
    const minChunk = Math.max(32, Math.min(this.remoteSettings.minChunkChars, targetChunk));

    let start = 0;
    while (start < content.length) {
      const range = this.pickChunkRange(content, start, minChunk, targetChunk, maxChunk);
      if (range.end <= range.start) {
        break;
      }
      const chunk = content.slice(range.start, range.end);
      if (chunk.trim().length > 0) {
        this.queue.push(chunk);
        this.queueStart.push(range.start);
        this.queueEnd.push(range.end);
      }
      start = range.end;
    }
  }

  private pickChunkRange(content: string, start: number, minChunk: number, targetChunk: number, maxChunk: number): QueueCharRange {
    const maxEnd = Math.min(content.length, start + maxChunk);
    const targetEnd = Math.min(content.length, start + targetChunk);
    const minEnd = Math.min(content.length, start + minChunk);
    if (maxEnd <= minEnd) {
      return new QueueCharRange(start, maxEnd);
    }
    const backward = this.findBreakBackward(content, targetEnd, minEnd);
    if (backward > start) {
      return new QueueCharRange(start, backward);
    }
    const forward = this.findBreakForward(content, targetEnd, maxEnd);
    if (forward > start) {
      return new QueueCharRange(start, forward);
    }
    return new QueueCharRange(start, maxEnd);
  }

  private findBreakBackward(content: string, from: number, minEnd: number): number {
    for (let index = from; index > minEnd; index--) {
      const char = content.charAt(index - 1);
      if (this.isBreakChar(char)) {
        return index;
      }
    }
    return -1;
  }

  private findBreakForward(content: string, from: number, maxEnd: number): number {
    for (let index = from; index < maxEnd; index++) {
      if (this.isBreakChar(content.charAt(index))) {
        return index + 1;
      }
    }
    return -1;
  }

  private isBreakChar(char: string): boolean {
    return char === '\n' ||
      char === '\r' ||
      char === '.' ||
      char === '!' ||
      char === '?' ||
      char === ',' ||
      char === ';' ||
      char === ':' ||
      char === '\u3002' ||
      char === '\uff01' ||
      char === '\uff1f' ||
      char === '\uff0c' ||
      char === '\u3001' ||
      char === '\uff1b' ||
      char === '\uff1a' ||
      char === '\u2026';
  }

  private findQueueIndexByChar(index: number): number {
    if (this.queue.length <= 0) {
      return 0;
    }
    if (index <= 0) {
      return 0;
    }
    let matched = 0;
    for (let i = 0; i < this.queue.length; i++) {
      const start = this.queueStart[i] ?? 0;
      const end = this.queueEnd[i] ?? start;
      if (index < start) {
        return matched;
      }
      if (index >= start && index < end) {
        return i;
      }
      matched = i;
    }
    return matched;
  }

  private getQueueRange(index: number): QueueCharRange {
    if (this.queue.length <= 0) {
      return new QueueCharRange(0, 0);
    }
    const safe = Math.max(0, Math.min(index, this.queue.length - 1));
    const start = this.queueStart[safe] ?? 0;
    const end = this.queueEnd[safe] ?? start;
    return new QueueCharRange(start, end);
  }

  private async prepareCacheAndManifest(): Promise<void> {
    const abilityContext = uiContextManager.getAbilityContext();
    const filesDir = abilityContext?.filesDir ?? abilityContext?.cacheDir ?? '';
    if (filesDir.length <= 0) {
      throw new Error('REMOTE_TTS_CONTEXT_FILES_DIR_EMPTY');
    }

    this.cacheRootDir = `${filesDir}/read_aloud_remote`;
    ensureDirExists(this.cacheRootDir);
    const safeBookId = sanitizeFileNamePart(this.context?.bookId ?? 'unknown_book');
    const chapterIndex = this.context?.chapterIndex ?? -1;
    const chapterKey = `${safeBookId}_${chapterIndex}_${this.contentDigest}_${this.remoteDigest}`;
    this.chapterCacheDir = `${this.cacheRootDir}/${chapterKey}`;
    ensureDirExists(this.chapterCacheDir);
    this.manifestPath = `${this.chapterCacheDir}/manifest.json`;
    this.sessionTempDir = `${this.chapterCacheDir}/session_${Date.now()}`;
    ensureDirExists(this.sessionTempDir);

    if (!this.remoteSettings.cacheAudioFiles) {
      this.cleanupChapterCacheWithoutManifest();
    }
    this.activeManifest = this.loadManifestFromDisk();
    if (!this.activeManifest) {
      this.activeManifest = {
        version: REMOTE_TTS_MANIFEST_VERSION,
        updatedAt: Date.now(),
        bookId: this.context?.bookId ?? '',
        chapterIndex: this.context?.chapterIndex ?? -1,
        contentDigest: this.contentDigest,
        remoteDigest: this.remoteDigest,
        audioFormat: normalizeAudioExtension(this.remoteSettings.audioFormat),
        segments: []
      };
      this.persistManifest();
    }
    this.restoreSegmentsFromManifest();
  }

  private cleanupChapterCacheWithoutManifest(): void {
    try {
      if (!this.chapterCacheDir || !fs.accessSync(this.chapterCacheDir)) {
        return;
      }
      const files = fs.listFileSync(this.chapterCacheDir);
      for (const name of files) {
        if (name === 'manifest.json') {
          continue;
        }
        const fullPath = `${this.chapterCacheDir}/${name}`;
        try {
          const stat = fs.statSync(fullPath);
          if (stat.isDirectory()) {
            this.deleteDir(fullPath);
          } else {
            fs.unlinkSync(fullPath);
          }
        } catch (_ignored) {
        }
      }
    } catch (_ignored) {
    }
  }

  private deleteDir(path: string): void {
    try {
      if (!fs.accessSync(path)) {
        return;
      }
      const items = fs.listFileSync(path);
      for (const item of items) {
        const child = `${path}/${item}`;
        const stat = fs.statSync(child);
        if (stat.isDirectory()) {
          this.deleteDir(child);
        } else {
          fs.unlinkSync(child);
        }
      }
      fs.rmdirSync(path);
    } catch (_ignored) {
    }
  }

  private loadManifestFromDisk(): RemoteTtsManifest | null {
    if (!this.manifestPath || !fs.accessSync(this.manifestPath)) {
      return null;
    }
    try {
      const text = new util.TextDecoder('utf-8').decodeToString(readFileBytes(this.manifestPath));
      const manifest = JSON.parse(text) as RemoteTtsManifest;
      if (!manifest || manifest.version !== REMOTE_TTS_MANIFEST_VERSION) {
        return null;
      }
      if (manifest.bookId !== (this.context?.bookId ?? '')) {
        return null;
      }
      if (manifest.chapterIndex !== (this.context?.chapterIndex ?? -1)) {
        return null;
      }
      if (manifest.contentDigest !== this.contentDigest || manifest.remoteDigest !== this.remoteDigest) {
        return null;
      }
      if (!Array.isArray(manifest.segments)) {
        manifest.segments = [];
      }
      return manifest;
    } catch (_ignored) {
      return null;
    }
  }

  private persistManifest(): void {
    if (!this.activeManifest || !this.manifestPath) {
      return;
    }
    try {
      this.activeManifest.updatedAt = Date.now();
      const bytes = new util.TextEncoder().encodeInto(JSON.stringify(this.activeManifest));
      writeFileBytes(this.manifestPath, new Uint8Array(bytes));
    } catch (_ignored) {
    }
  }

  private restoreSegmentsFromManifest(): void {
    this.playableSegments.clear();
    if (!this.activeManifest) {
      return;
    }
    const sorted = this.activeManifest.segments.slice().sort((a, b) => a.index - b.index);
    for (const item of sorted) {
      if (item.index < 0 || item.index >= this.queue.length) {
        continue;
      }
      if (!item.filePath || !fs.accessSync(item.filePath)) {
        continue;
      }
      if (this.segmentDigest(item.index) !== item.textDigest) {
        continue;
      }
      const durationMs = item.durationMs > 0
        ? item.durationMs
        : estimateDurationMsByCharCount(this.queue[item.index].length, this.settings?.speed ?? 1);
      this.playableSegments.set(item.index, {
        index: item.index,
        start: item.start,
        end: item.end,
        textDigest: item.textDigest,
        filePath: item.filePath,
        bytes: item.bytes,
        durationMs
      });
    }
  }

  private updateManifestSegment(segment: RemoteTtsPlayableSegment): void {
    if (!this.activeManifest) {
      return;
    }
    const next: RemoteTtsSegmentCacheRecord[] = [];
    for (const item of this.activeManifest.segments) {
      if (item.index !== segment.index) {
        next.push(item);
      }
    }
    next.push({
      index: segment.index,
      start: segment.start,
      end: segment.end,
      textDigest: segment.textDigest,
      filePath: segment.filePath,
      bytes: segment.bytes,
      durationMs: segment.durationMs
    });
    next.sort((a, b) => a.index - b.index);
    this.activeManifest.segments = next;
    this.persistManifest();
  }

  private segmentDigest(index: number): string {
    return fnv1aHashHex(this.queue[index] ?? '');
  }

  private prefetchSegments(startIndex: number, sessionToken: string): void {
    if (!this.isSessionActive(sessionToken)) {
      return;
    }
    const count = Math.max(REMOTE_TTS_PREFETCH_MIN, Math.min(REMOTE_TTS_PREFETCH_MAX, this.remoteSettings.prefetchSegments));
    const end = Math.min(this.queue.length - 1, startIndex + count - 1);
    for (let index = startIndex; index <= end; index++) {
      this.ensureSegment(index, sessionToken).catch((_error: Object | string) => {});
    }
  }

  private playLoopSafely(sessionToken: string): void {
    this.playLoop(sessionToken).catch((error: Object | string) => {
      if (!this.isSessionActive(sessionToken)) {
        return;
      }
      this.pauseRequested = true;
      this.stopRequested = false;
      this.stopProgressTimer();
      this.notifyPlaybackEvent('paused_for_error', formatReadAloudError(error), this.currentCharIndex);
    });
  }

  private async playLoop(sessionToken: string): Promise<void> {
    while (this.isSessionActive(sessionToken) && !this.pauseRequested && !this.stopRequested) {
      if (this.queueIndex >= this.queue.length) {
        this.pauseRequested = true;
        this.stopRequested = false;
        this.stopProgressTimer();
        this.tryConcatChapterAudio();
        this.notifyPlaybackEvent('completed', 'queue_finished', this.currentCharIndex);
        return;
      }

      const range = this.getQueueRange(this.queueIndex);
      const segment = await this.ensureSegment(this.queueIndex, sessionToken);
      if (!this.isSessionActive(sessionToken)) {
        return;
      }
      this.currentCharIndex = Math.max(range.start, Math.min(this.currentCharIndex, Math.max(range.start, range.end - 1)));
      this.updateProgressSnapshot(this.currentCharIndex, range.start, range.end);
      this.startProgressTimer(range.start, range.end, segment.durationMs, sessionToken);
      await this.waitDuration(segment.durationMs, sessionToken);
      if (!this.isSessionActive(sessionToken)) {
        return;
      }
      this.stopProgressTimer();
      this.currentCharIndex = range.end;
      this.updateProgressSnapshot(this.currentCharIndex, range.start, range.end);
      this.queueIndex += 1;
      this.prefetchSegments(this.queueIndex, sessionToken);
    }
  }

  private isSessionActive(sessionToken: string): boolean {
    return this.playbackSessionToken.length > 0 &&
      this.playbackSessionToken === sessionToken &&
      !this.pauseRequested &&
      !this.stopRequested;
  }

  private async waitDuration(durationMs: number, sessionToken: string): Promise<void> {
    if (!this.isSessionActive(sessionToken)) {
      return;
    }
    const safe = Math.max(REMOTE_TTS_FALLBACK_SEGMENT_MIN_MS, durationMs);
    await new Promise<void>((resolve) => setTimeout(resolve, safe));
  }

  private startProgressTimer(start: number, end: number, durationMs: number, sessionToken: string): void {
    this.stopProgressTimer();
    if (end <= start) {
      return;
    }
    this.progressStartMs = Date.now();
    this.progressDurationMs = Math.max(REMOTE_TTS_FALLBACK_SEGMENT_MIN_MS, durationMs);
    this.progressRangeStart = start;
    this.progressRangeEnd = end;
    this.progressTimer = setInterval(() => {
      if (!this.isSessionActive(sessionToken)) {
        this.stopProgressTimer();
        return;
      }
      const elapsed = Date.now() - this.progressStartMs;
      const ratio = Math.max(0, Math.min(1, elapsed / Math.max(1, this.progressDurationMs)));
      const span = this.progressRangeEnd - this.progressRangeStart;
      const next = this.progressRangeStart + Math.floor(span * ratio);
      const safeNext = Math.max(this.currentCharIndex, Math.min(next, Math.max(this.progressRangeStart, this.progressRangeEnd - 1)));
      if (safeNext === this.currentCharIndex) {
        return;
      }
      this.currentCharIndex = safeNext;
      this.updateProgressSnapshot(this.currentCharIndex, this.progressRangeStart, this.progressRangeEnd);
    }, REMOTE_TTS_PROGRESS_TIMER_MS);
  }

  private stopProgressTimer(): void {
    if (this.progressTimer >= 0) {
      clearInterval(this.progressTimer);
      this.progressTimer = -1;
    }
    this.progressStartMs = 0;
    this.progressDurationMs = 0;
    this.progressRangeStart = -1;
    this.progressRangeEnd = -1;
  }

  private async ensureSegment(index: number, sessionToken: string): Promise<RemoteTtsPlayableSegment> {
    const existing = this.playableSegments.get(index);
    if (existing && existing.filePath.length > 0 && fs.accessSync(existing.filePath)) {
      return existing;
    }
    const pending = this.pendingSynthesis.get(index);
    if (pending) {
      return await pending;
    }
    const task = this.synthesizeSegment(index, sessionToken);
    this.pendingSynthesis.set(index, task);
    try {
      const result = await task;
      this.playableSegments.set(index, result);
      return result;
    } finally {
      this.pendingSynthesis.delete(index);
    }
  }

  private async synthesizeSegment(index: number, sessionToken: string): Promise<RemoteTtsPlayableSegment> {
    if (!this.isSessionActive(sessionToken) && this.playbackSessionToken.length > 0) {
      throw new Error('REMOTE_TTS_SESSION_INTERRUPTED');
    }
    const text = this.queue[index] ?? '';
    if (text.trim().length <= 0) {
      throw new Error(`REMOTE_TTS_EMPTY_SEGMENT: index=${index}`);
    }
    const range = this.getQueueRange(index);
    const synthesized = await this.requestRemoteAudio(text);
    const digest = this.segmentDigest(index);
    const ext = normalizeAudioExtension(this.remoteSettings.audioFormat);
    const dir = this.remoteSettings.cacheAudioFiles ? this.chapterCacheDir : this.sessionTempDir;
    ensureDirExists(dir);
    const filePath = `${dir}/seg_${index}_${digest}.${ext}`;
    writeFileBytes(filePath, synthesized.bytes);
    const durationMs = Math.max(
      REMOTE_TTS_FALLBACK_SEGMENT_MIN_MS,
      synthesized.durationMs > 0 ? synthesized.durationMs : estimateDurationMsByCharCount(text.length, this.settings?.speed ?? 1)
    );
    const segment: RemoteTtsPlayableSegment = {
      index,
      start: range.start,
      end: range.end,
      textDigest: digest,
      filePath,
      bytes: synthesized.bytes.byteLength,
      durationMs
    };
    this.updateManifestSegment(segment);
    return segment;
  }

  private async requestRemoteAudio(text: string): Promise<RemoteTtsSynthesizedSegment> {
    const requestUrl = this.buildRemoteRequestUrl();
    const requestHeaders = this.buildRemoteRequestHeaders();
    const payload = this.buildRemoteRequestBody(text);
    const response = await this.requestRemoteHttp(
      requestUrl,
      http.RequestMethod.POST,
      payload,
      requestHeaders,
      true
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      const detail = typeof response.result === 'string'
        ? response.result.slice(0, 240)
        : '';
      throw new Error(`REMOTE_TTS_HTTP_${response.statusCode}${detail.length > 0 ? `: ${detail}` : ''}`);
    }

    const parsed = await this.parseRemoteAudioResult(response, requestUrl, requestHeaders);
    if (!parsed || parsed.bytes.length <= 0) {
      throw new Error('REMOTE_TTS_EMPTY_AUDIO_BYTES');
    }

    return {
      bytes: parsed.bytes,
      durationMs: Math.max(0, parsed.durationMs)
    };
  }

  private buildRemoteRequestUrl(): string {
    const endpoint = this.remoteSettings.endpoint.trim().replace(/\/+$/, '');
    const apiPathRaw = this.remoteSettings.apiPath.trim();
    if (apiPathRaw.startsWith('http://') || apiPathRaw.startsWith('https://')) {
      return apiPathRaw;
    }
    const apiPath = apiPathRaw.length > 0
      ? (apiPathRaw.startsWith('/') ? apiPathRaw : `/${apiPathRaw}`)
      : '/v1/audio/speech';
    return `${endpoint}${apiPath}`;
  }

  private buildRemoteRequestBody(text: string): string {
    const fields: RemoteRequestField[] = [];
    this.putRemoteRequestField(fields, 'model', this.remoteSettings.model.trim());
    this.putRemoteRequestField(fields, 'voice', this.remoteSettings.voice.trim());
    this.putRemoteRequestField(fields, 'input', text);
    this.putRemoteRequestField(fields, 'response_format', normalizeAudioExtension(this.remoteSettings.audioFormat));
    this.putRemoteRequestField(fields, 'stream', this.remoteSettings.streamEnabled);

    const extra = this.parseJsonRecord(this.remoteSettings.extraBodyJson);
    if (extra) {
      const keys = Object.keys(extra);
      for (const key of keys) {
        const value = extra[key];
        if (value === undefined || value === null) {
          continue;
        }
        if (typeof value === 'boolean') {
          this.putRemoteRequestField(fields, key, value);
        } else {
          this.putRemoteRequestField(fields, key, String(value));
        }
      }
    }
    return this.serializeRemoteRequestFields(fields);
  }

  private putRemoteRequestField(fields: RemoteRequestField[], key: string, value: string | boolean): void {
    for (let i = 0; i < fields.length; i++) {
      if (fields[i].key === key) {
        fields[i].value = value;
        return;
      }
    }
    const field: RemoteRequestField = {
      key,
      value
    };
    fields.push(field);
  }

  private serializeRemoteRequestFields(fields: RemoteRequestField[]): string {
    const parts: string[] = [];
    for (const field of fields) {
      const keyPart = JSON.stringify(field.key);
      const valuePart = typeof field.value === 'boolean'
        ? (field.value ? 'true' : 'false')
        : JSON.stringify(field.value);
      parts.push(`${keyPart}:${valuePart}`);
    }
    return `{${parts.join(',')}}`;
  }

  private buildRemoteRequestHeaders(): Record<string, string> {
    const headers: Record<string, string> = {};
    const customHeaders = this.parseJsonRecord(this.remoteSettings.customHeadersJson);
    if (customHeaders) {
      const keys = Object.keys(customHeaders);
      for (const key of keys) {
        const value = customHeaders[key];
        if (value === undefined || value === null) {
          continue;
        }
        headers[key] = String(value);
      }
    }

    this.setHeaderIfAbsent(headers, 'Content-Type', 'application/json');
    this.setHeaderIfAbsent(headers, 'Accept', 'audio/*,application/octet-stream,application/json,text/event-stream');
    this.setHeaderIfAbsent(headers, 'User-Agent', 'ManXia-ReadAloud/1.0');
    const apiKey = this.remoteSettings.apiKey.trim();
    if (apiKey.length > 0 && !this.hasHeaderIgnoreCase(headers, 'Authorization')) {
      headers.Authorization = `Bearer ${apiKey}`;
    }
    return headers;
  }

  private parseJsonRecord(text: string): RemoteJsonRecord | null {
    if (!text || text.trim().length <= 0) {
      return null;
    }
    try {
      const payload = JSON.parse(text) as Object;
      if (!payload || typeof payload !== 'object' || Array.isArray(payload)) {
        return null;
      }
      return payload as RemoteJsonRecord;
    } catch (_ignored) {
      return null;
    }
  }

  private hasHeaderIgnoreCase(headers: Record<string, string>, key: string): boolean {
    const target = key.toLowerCase();
    const keys = Object.keys(headers);
    for (const item of keys) {
      if (item.toLowerCase() === target) {
        return true;
      }
    }
    return false;
  }

  private setHeaderIfAbsent(headers: Record<string, string>, key: string, value: string): void {
    if (!this.hasHeaderIgnoreCase(headers, key)) {
      headers[key] = value;
    }
  }

  private getHeaderValue(headers: Record<string, string>, key: string): string {
    const target = key.toLowerCase();
    const keys = Object.keys(headers);
    for (const item of keys) {
      if (item.toLowerCase() === target) {
        return headers[item];
      }
    }
    return '';
  }

  private normalizeHeaders(rawHeaders: Object | undefined | null): Record<string, string> {
    const normalized: Record<string, string> = {};
    if (!rawHeaders || typeof rawHeaders !== 'object') {
      return normalized;
    }
    const source = rawHeaders as RemoteJsonRecord;
    const keys = Object.keys(source);
    for (const key of keys) {
      const value = source[key];
      if (value === undefined || value === null) {
        continue;
      }
      normalized[key] = String(value);
    }
    return normalized;
  }

  private async requestRemoteHttp(
    url: string,
    method: http.RequestMethod,
    body: string,
    headers: Record<string, string>,
    expectArrayBuffer: boolean
  ): Promise<RemoteTtsHttpResult> {
    const request = http.createHttp();
    try {
      const response = await request.request(url, {
        method,
        header: headers,
        extraData: body,
        expectDataType: expectArrayBuffer ? http.HttpDataType.ARRAY_BUFFER : http.HttpDataType.STRING,
        connectTimeout: this.remoteSettings.connectTimeoutMs,
        readTimeout: this.remoteSettings.readTimeoutMs
      });
      return {
        statusCode: response.responseCode,
        headers: this.normalizeHeaders(response.header),
        result: response.result as string | ArrayBuffer
      };
    } finally {
      request.destroy();
    }
  }

  private async parseRemoteAudioResult(
    response: RemoteTtsHttpResult,
    requestUrl: string,
    requestHeaders: Record<string, string>
  ): Promise<RemoteTtsSynthesizedSegment> {
    const contentType = this.getHeaderValue(response.headers, 'content-type');
    const result = response.result;
    const rawBytes = typeof result === 'string'
      ? new Uint8Array(new util.TextEncoder().encodeInto(result))
      : toUint8Array(result);
    if (rawBytes.length <= 0) {
      return {
        bytes: new Uint8Array(0),
        durationMs: 0
      };
    }

    const shouldTreatAsBinary = !isLikelyTextContentType(contentType) && !isLikelyTextBytes(rawBytes);
    if (shouldTreatAsBinary) {
      return {
        bytes: rawBytes,
        durationMs: 0
      };
    }

    const textPayload = typeof result === 'string'
      ? result
      : new util.TextDecoder('utf-8').decodeToString(rawBytes);

    const fromSse = await this.extractAudioFromSsePayload(textPayload, contentType, requestUrl, requestHeaders);
    if (fromSse.bytes.length > 0) {
      return fromSse;
    }

    const fromJson = await this.extractAudioFromJsonPayload(textPayload, requestUrl, requestHeaders);
    if (fromJson.bytes.length > 0) {
      return fromJson;
    }

    const decoded = this.decodePossibleBase64Payload(textPayload);
    if (decoded.length > 0) {
      return {
        bytes: decoded,
        durationMs: 0
      };
    }

    if (typeof result !== 'string') {
      return {
        bytes: rawBytes,
        durationMs: 0
      };
    }

    throw new Error('REMOTE_TTS_PARSE_FAILED');
  }

  private async extractAudioFromSsePayload(
    textPayload: string,
    contentType: string,
    requestUrl: string,
    requestHeaders: Record<string, string>
  ): Promise<RemoteTtsSynthesizedSegment> {
    const normalizedContentType = contentType.toLowerCase();
    const maybeSse = normalizedContentType.includes('text/event-stream') ||
      textPayload.includes('\ndata:') ||
      textPayload.startsWith('data:');
    if (!maybeSse) {
      return {
        bytes: new Uint8Array(0),
        durationMs: 0
      };
    }

    const events: string[] = [];
    const lines = textPayload.split(/\r?\n/);
    let dataParts: string[] = [];
    for (const rawLine of lines) {
      const line = rawLine.trim();
      if (line.length <= 0) {
        if (dataParts.length > 0) {
          events.push(dataParts.join('\n'));
          dataParts = [];
        }
        continue;
      }
      if (line.startsWith(':')) {
        continue;
      }
      if (line.startsWith('data:')) {
        dataParts.push(line.slice(5).trim());
      }
    }
    if (dataParts.length > 0) {
      events.push(dataParts.join('\n'));
    }

    const mergedParts: Uint8Array[] = [];
    let durationMs = 0;
    for (const eventItem of events) {
      const chunk = eventItem.trim();
      if (chunk.length <= 0 || chunk === '[DONE]') {
        continue;
      }
      const parsed = await this.extractAudioFromJsonPayload(chunk, requestUrl, requestHeaders);
      if (parsed.bytes.length > 0) {
        mergedParts.push(parsed.bytes);
        if (parsed.durationMs > durationMs) {
          durationMs = parsed.durationMs;
        }
        continue;
      }
      const decoded = this.decodePossibleBase64Payload(chunk);
      if (decoded.length > 0) {
        mergedParts.push(decoded);
      }
    }
    if (mergedParts.length <= 0) {
      return {
        bytes: new Uint8Array(0),
        durationMs: 0
      };
    }
    return {
      bytes: concatUint8ArrayParts(mergedParts),
      durationMs
    };
  }

  private async extractAudioFromJsonPayload(
    payloadText: string,
    requestUrl: string,
    requestHeaders: Record<string, string>
  ): Promise<RemoteTtsSynthesizedSegment> {
    const mergedParts: Uint8Array[] = [];
    let durationMs = 0;

    const tryConsumeRecord = async (record: RemoteJsonRecord): Promise<void> => {
      const base64Hints: string[] = [];
      const urlHints: string[] = [];
      const durationHints: number[] = [];
      this.collectJsonAudioHints(record, base64Hints, urlHints, durationHints);
      for (const value of base64Hints) {
        const decoded = this.decodePossibleBase64Payload(value);
        if (decoded.length > 0) {
          mergedParts.push(decoded);
        }
      }
      if (mergedParts.length <= 0) {
        for (const value of urlHints) {
          const downloaded = await this.downloadAudioByUrl(value, requestUrl, requestHeaders);
          if (downloaded.length > 0) {
            mergedParts.push(downloaded);
            break;
          }
        }
      }
      for (const value of durationHints) {
        if (value > durationMs) {
          durationMs = value;
        }
      }
    };

    const directJson = this.parseJsonRecord(payloadText);
    if (directJson) {
      await tryConsumeRecord(directJson);
    } else {
      const lines = payloadText.split(/\r?\n/);
      for (const lineText of lines) {
        const line = lineText.trim();
        if (line.length <= 0) {
          continue;
        }
        const lineJson = this.parseJsonRecord(line);
        if (!lineJson) {
          continue;
        }
        await tryConsumeRecord(lineJson);
      }
    }

    if (mergedParts.length <= 0) {
      return {
        bytes: new Uint8Array(0),
        durationMs: 0
      };
    }
    return {
      bytes: concatUint8ArrayParts(mergedParts),
      durationMs
    };
  }

  private collectJsonAudioHints(
    payload: RemoteJsonValue,
    base64Hints: string[],
    urlHints: string[],
    durationHints: number[]
  ): void {
    if (payload === null || payload === undefined) {
      return;
    }
    if (Array.isArray(payload)) {
      const payloadArray = payload as Array<Object>;
      for (let index = 0; index < payloadArray.length; index++) {
        const item: Object = payloadArray[index];
        this.collectJsonAudioHints(item as RemoteJsonValue, base64Hints, urlHints, durationHints);
      }
      return;
    }
    if (typeof payload !== 'object') {
      return;
    }

    const record = payload as RemoteJsonRecord;
    const keys = Object.keys(record);
    for (const key of keys) {
      const value = record[key];
      const lowerKey = key.toLowerCase();
      if (typeof value === 'string') {
        const normalized = value.trim();
        if (normalized.length <= 0) {
          continue;
        }
        if (lowerKey.includes('duration')) {
          const parsedNumber = Number(normalized);
          if (Number.isFinite(parsedNumber)) {
            durationHints.push(Math.max(0, Math.floor(parsedNumber)));
          }
        }
        if (
          lowerKey === 'audio' ||
          lowerKey === 'audio_base64' ||
          lowerKey === 'base64' ||
          lowerKey === 'bytes' ||
          lowerKey === 'data' ||
          lowerKey.includes('audio') ||
          lowerKey.includes('base64')
        ) {
          base64Hints.push(normalized);
        }
        if (
          lowerKey === 'url' ||
          lowerKey === 'audio_url' ||
          lowerKey.endsWith('_url')
        ) {
          urlHints.push(normalized);
        }
      } else if (typeof value === 'number') {
        if (lowerKey.includes('duration') && Number.isFinite(value)) {
          durationHints.push(Math.max(0, Math.floor(value)));
        }
      }
      this.collectJsonAudioHints(value, base64Hints, urlHints, durationHints);
    }
  }

  private decodePossibleBase64Payload(rawValue: string): Uint8Array {
    const text = rawValue.trim();
    if (text.length <= 0) {
      return new Uint8Array(0);
    }

    let base64Text = text;
    const dataPrefixMatch = /^data:audio\/[a-zA-Z0-9.+-]+;base64,/i.exec(base64Text);
    if (dataPrefixMatch) {
      base64Text = base64Text.slice(dataPrefixMatch[0].length);
    }

    if (!this.isLikelyBase64String(base64Text)) {
      return new Uint8Array(0);
    }
    return decodeBase64TextToBytes(base64Text);
  }

  private isLikelyBase64String(rawValue: string): boolean {
    const normalized = rawValue.replace(/\s+/g, '');
    if (normalized.length < 16 || normalized.length % 4 !== 0) {
      return false;
    }
    return /^[A-Za-z0-9+/=]+$/.test(normalized);
  }

  private async downloadAudioByUrl(
    audioUrl: string,
    requestUrl: string,
    requestHeaders: Record<string, string>
  ): Promise<Uint8Array> {
    const resolvedUrl = this.resolveAudioUrl(audioUrl, requestUrl);
    if (!resolvedUrl || resolvedUrl.length <= 0) {
      return new Uint8Array(0);
    }
    const headers: Record<string, string> = {};
    const requestHeaderKeys = Object.keys(requestHeaders);
    for (const key of requestHeaderKeys) {
      if (key.toLowerCase() === 'content-type') {
        continue;
      }
      headers[key] = requestHeaders[key];
    }

    const response = await this.requestRemoteHttp(
      resolvedUrl,
      http.RequestMethod.GET,
      '',
      headers,
      true
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return new Uint8Array(0);
    }
    if (typeof response.result === 'string') {
      const decoded = this.decodePossibleBase64Payload(response.result);
      return decoded.length > 0
        ? decoded
        : new Uint8Array(new util.TextEncoder().encodeInto(response.result));
    }
    return toUint8Array(response.result);
  }

  private resolveAudioUrl(rawUrl: string, requestUrl: string): string {
    const trimmed = rawUrl.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    const requestMatch = /^(https?:\/\/[^/]+)(\/.*)?$/i.exec(requestUrl);
    if (!requestMatch) {
      return trimmed;
    }
    const host = requestMatch[1];
    const basePath = requestMatch[2] ?? '/';
    if (trimmed.startsWith('/')) {
      return `${host}${trimmed}`;
    }
    const slashIndex = basePath.lastIndexOf('/');
    const parent = slashIndex >= 0 ? basePath.slice(0, slashIndex + 1) : '/';
    return `${host}${parent}${trimmed}`;
  }

  private tryConcatChapterAudio(): void {
    if (!this.remoteSettings.autoConcatAudio || !this.remoteSettings.cacheAudioFiles) {
      return;
    }
    if (!this.activeManifest || !this.chapterCacheDir) {
      return;
    }
    if (this.activeManifest.segments.length <= 1) {
      return;
    }
    if (this.activeManifest.mergedFilePath && fs.accessSync(this.activeManifest.mergedFilePath)) {
      return;
    }

    const segments = this.activeManifest.segments
      .slice()
      .sort((left, right) => left.index - right.index);
    if (segments.length !== this.queue.length) {
      return;
    }

    const byteParts: Uint8Array[] = [];
    for (const segment of segments) {
      if (segment.index < 0 || segment.index >= this.queue.length) {
        return;
      }
      if (!segment.filePath || !fs.accessSync(segment.filePath)) {
        return;
      }
      if (segment.textDigest !== this.segmentDigest(segment.index)) {
        return;
      }
      byteParts.push(readFileBytes(segment.filePath));
    }
    if (byteParts.length <= 1) {
      return;
    }

    const ext = normalizeAudioExtension(this.activeManifest.audioFormat || this.remoteSettings.audioFormat);
    let mergedBytes: Uint8Array = concatUint8ArrayParts(byteParts);
    if (ext === 'wav') {
      const wavBytes = this.tryConcatWavSegments(byteParts);
      if (wavBytes) {
        mergedBytes = wavBytes;
      }
    }

    const mergedPath = `${this.chapterCacheDir}/chapter_${this.contentDigest}_${this.remoteDigest}.${ext}`;
    writeFileBytes(mergedPath, mergedBytes);
    this.activeManifest.mergedFilePath = mergedPath;
    this.persistManifest();
  }

  private tryConcatWavSegments(parts: Uint8Array[]): Uint8Array | null {
    if (parts.length <= 0) {
      return null;
    }
    const pcmParts: Uint8Array[] = [];
    let sampleRate = 0;
    let channels = 0;
    let bitsPerSample = 0;
    for (const part of parts) {
      const payload = extractWavPcmPayload(part);
      if (!payload) {
        return null;
      }
      if (sampleRate <= 0) {
        sampleRate = payload.sampleRate;
        channels = payload.channels;
        bitsPerSample = payload.bitsPerSample;
      } else if (
        payload.sampleRate !== sampleRate ||
        payload.channels !== channels ||
        payload.bitsPerSample !== bitsPerSample
      ) {
        return null;
      }
      pcmParts.push(payload.pcmBytes);
    }
    if (sampleRate <= 0 || channels <= 0 || bitsPerSample <= 0 || pcmParts.length <= 0) {
      return null;
    }
    return createWavFromPcm(pcmParts, sampleRate, channels, bitsPerSample);
  }

  private createRequestId(prefix: string): string {
    this.requestSerial += 1;
    return ReadAloudRequestIdGenerator.next(`${prefix}_${this.requestSerial}`);
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
