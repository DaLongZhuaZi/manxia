import { logger } from '../../Utils/Logger';
import {
  buildXiaomiMimoStyledText,
  DEFAULT_READ_ALOUD_SETTINGS,
  DEFAULT_REMOTE_READ_ALOUD_SETTINGS,
  isXiaomiMimoRemoteReadAloud,
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
import { eventBus, GameEvent, ReadAloudCacheUpdatedPayload } from '../EventBus';

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
const REMOTE_TTS_MANIFEST_VERSION: number = 2;
const REMOTE_TTS_SEGMENT_INDEX_VERSION: number = 1;
const REMOTE_TTS_DEFAULT_CHARS_PER_SECOND: number = 11;
const REMOTE_TTS_PREFETCH_MIN: number = 1;
const REMOTE_TTS_PREFETCH_MAX: number = 8;
const REMOTE_TTS_FALLBACK_PLAYBACK_GUARD_MS: number = 1600;
const REMOTE_TTS_FALLBACK_SEGMENT_MIN_MS: number = 580;
const REMOTE_TTS_PROGRESS_TIMER_MS: number = 120;
const REMOTE_TTS_TEXT_PREVIEW_LIMIT: number = 48;
const REMOTE_TTS_HTTP_MAX_LIMIT_BYTES: number = 32 * 1024 * 1024;
const REMOTE_TTS_PHRASE_PAUSE_UNITS: number = 1.4;
const REMOTE_TTS_SENTENCE_PAUSE_UNITS: number = 3.6;
const REMOTE_TTS_PARAGRAPH_PAUSE_UNITS: number = 6.5;
const READ_ALOUD_UI_STATUS_TEXT_KEY = 'ReadAloudUiStatusText';
const READ_ALOUD_UI_STATUS_DETAIL_KEY = 'ReadAloudUiStatusDetail';
const READ_ALOUD_UI_STATUS_PHASE_KEY = 'ReadAloudUiStatusPhase';
const READ_ALOUD_UI_STATUS_UPDATED_AT_KEY = 'ReadAloudUiStatusUpdatedAt';
const REMOTE_TTS_ARRAY_BUFFER_RETRY_ERROR_CODE = '2300023';

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

function getReadAloudErrorCode(error: Object | string): string {
  if (typeof error === 'string') {
    const match = /code=([^,\s]+)/i.exec(error);
    return match ? match[1] : '';
  }
  const errorLike = error as ReadAloudErrorLike;
  if (typeof errorLike.code === 'number' || typeof errorLike.code === 'string') {
    return String(errorLike.code);
  }
  if (typeof errorLike.errorCode === 'number' || typeof errorLike.errorCode === 'string') {
    return String(errorLike.errorCode);
  }
  return '';
}

function isRemoteArrayBufferRetryableError(error: Object | string): boolean {
  const code = getReadAloudErrorCode(error);
  if (code === REMOTE_TTS_ARRAY_BUFFER_RETRY_ERROR_CODE) {
    return true;
  }
  return formatReadAloudError(error)
    .toLowerCase()
    .includes('failed to write the received data to the disk or application');
}

interface RemoteTtsSegmentCacheRecord {
  index: number;
  start: number;
  end: number;
  cacheKey: string;
  textDigest: string;
  textLength: number;
  textPreview: string;
  filePath: string;
  bytes: number;
  durationMs: number;
  seekTotalUnits?: number;
  seekAnchors?: RemoteTtsSeekAnchorRecord[];
}

interface RemoteTtsSeekAnchorRecord {
  charIndex: number;
  unitOffset: number;
  kind: string;
}

interface RemoteTtsSeekModel {
  totalUnits: number;
  anchors: RemoteTtsSeekAnchorRecord[];
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
  inlineBytes?: Uint8Array;
}

interface RemoteTtsSegmentIndexRecord {
  version: number;
  updatedAt: number;
  cacheKey: string;
  textDigest: string;
  textLength: number;
  textPreview: string;
  remoteDigest: string;
  audioFormat: string;
  filePath: string;
  bytes: number;
  durationMs: number;
  bookId: string;
  chapterIndex: number;
  start: number;
  end: number;
  seekTotalUnits?: number;
  seekAnchors?: RemoteTtsSeekAnchorRecord[];
}

interface RemoteTtsSegmentStoragePaths {
  cacheKey: string;
  textDigest: string;
  textLength: number;
  textPreview: string;
  audioPath: string;
  metaPath: string;
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

interface RemoteChatCompletionMessagePayload {
  role: string;
  content: string;
}

interface RemoteChatCompletionAudioPayload {
  format: string;
  voice: string;
}

type RemoteJsonValue =
  string |
  number |
  boolean |
  Object |
  Array<Object> |
  RemoteChatCompletionMessagePayload[] |
  RemoteChatCompletionAudioPayload |
  null;
type RemoteJsonRecord = Record<string, RemoteJsonValue>;

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

function normalizeRemoteTtsCacheText(text: string): string {
  return text
    .replace(/\r\n/g, '\n')
    .replace(/\r/g, '\n')
    .replace(/\u00a0/g, ' ')
    .trim();
}

function buildRemoteTtsTextDigest(text: string): string {
  return fnv1aHashHex(normalizeRemoteTtsCacheText(text));
}

function buildRemoteTtsTextCacheKey(text: string): string {
  const normalized = normalizeRemoteTtsCacheText(text);
  const preview = normalized.length > REMOTE_TTS_TEXT_PREVIEW_LIMIT
    ? normalized.slice(0, REMOTE_TTS_TEXT_PREVIEW_LIMIT)
    : normalized;
  const tail = normalized.length > REMOTE_TTS_TEXT_PREVIEW_LIMIT
    ? normalized.slice(normalized.length - REMOTE_TTS_TEXT_PREVIEW_LIMIT)
    : normalized;
  return `${normalized.length}_${fnv1aHashHex(normalized)}_${fnv1aHashHex(`${preview}|${tail}`)}`;
}

function buildRemoteTtsTextPreview(text: string): string {
  const normalized = normalizeRemoteTtsCacheText(text).replace(/\s+/g, ' ');
  if (normalized.length <= REMOTE_TTS_TEXT_PREVIEW_LIMIT) {
    return normalized;
  }
  return `${normalized.slice(0, REMOTE_TTS_TEXT_PREVIEW_LIMIT)}...`;
}

function isRemoteTtsParagraphBoundaryChar(char: string): boolean {
  return char === '\n' || char === '\r';
}

function isRemoteTtsSentenceBoundaryChar(char: string): boolean {
  return char === '.' ||
    char === '!' ||
    char === '?' ||
    char === '\u2026' ||
    char === '\u3002' ||
    char === '\uff01' ||
    char === '\uff1f';
}

function isRemoteTtsPhraseBoundaryChar(char: string): boolean {
  return char === ',' ||
    char === ';' ||
    char === ':' ||
    char === '\u3001' ||
    char === '\uff0c' ||
    char === '\uff1b' ||
    char === '\uff1a';
}

function isRemoteTtsWhitespaceChar(char: string): boolean {
  return char === ' ' || char === '\n' || char === '\r' || char === '\t';
}

function computeRemoteTtsCharUnits(char: string): number {
  if (isRemoteTtsWhitespaceChar(char)) {
    return 0.35;
  }
  if (isRemoteTtsParagraphBoundaryChar(char)) {
    return 0.2;
  }
  if (isRemoteTtsSentenceBoundaryChar(char)) {
    return 0.45;
  }
  if (isRemoteTtsPhraseBoundaryChar(char)) {
    return 0.55;
  }
  return 1;
}

function buildRemoteTtsSeekModel(start: number, end: number, text: string): RemoteTtsSeekModel {
  const safeStart = Math.max(0, Math.floor(start));
  const safeEnd = Math.max(safeStart, Math.floor(end));
  const anchors: RemoteTtsSeekAnchorRecord[] = [{
    charIndex: safeStart,
    unitOffset: 0,
    kind: 'start'
  }];

  let totalUnits = 0;
  for (let index = 0; index < text.length; index++) {
    const char = text.charAt(index);
    totalUnits += computeRemoteTtsCharUnits(char);
    let pauseUnits = 0;
    let kind = '';
    if (isRemoteTtsParagraphBoundaryChar(char)) {
      pauseUnits = REMOTE_TTS_PARAGRAPH_PAUSE_UNITS;
      kind = 'paragraph';
    } else if (isRemoteTtsSentenceBoundaryChar(char)) {
      pauseUnits = REMOTE_TTS_SENTENCE_PAUSE_UNITS;
      kind = 'sentence';
    } else if (isRemoteTtsPhraseBoundaryChar(char)) {
      pauseUnits = REMOTE_TTS_PHRASE_PAUSE_UNITS;
      kind = 'phrase';
    }
    if (pauseUnits <= 0) {
      continue;
    }
    totalUnits += pauseUnits;
    const nextCharIndex = Math.min(safeEnd, safeStart + index + 1);
    const lastAnchor = anchors[anchors.length - 1];
    if (lastAnchor && lastAnchor.charIndex === nextCharIndex) {
      lastAnchor.unitOffset = totalUnits;
      lastAnchor.kind = kind;
      continue;
    }
    anchors.push({
      charIndex: nextCharIndex,
      unitOffset: totalUnits,
      kind
    });
  }

  const safeTotalUnits = Math.max(1, totalUnits);
  const lastAnchor = anchors[anchors.length - 1];
  if (lastAnchor && lastAnchor.charIndex === safeEnd) {
    lastAnchor.unitOffset = safeTotalUnits;
    lastAnchor.kind = 'end';
  } else {
    anchors.push({
      charIndex: safeEnd,
      unitOffset: safeTotalUnits,
      kind: 'end'
    });
  }
  return {
    totalUnits: safeTotalUnits,
    anchors
  };
}

function buildRemoteTtsSeekModelFromRecord(
  start: number,
  end: number,
  text: string,
  totalUnits?: number,
  anchors?: RemoteTtsSeekAnchorRecord[]
): RemoteTtsSeekModel {
  const fallback = buildRemoteTtsSeekModel(start, end, text);
  if (!anchors || anchors.length <= 0 || !Number.isFinite(totalUnits) || (totalUnits ?? 0) <= 0) {
    return fallback;
  }

  const safeStart = Math.max(0, Math.floor(start));
  const safeEnd = Math.max(safeStart, Math.floor(end));
  const sanitized: RemoteTtsSeekAnchorRecord[] = [];
  for (let index = 0; index < anchors.length; index++) {
    const item = anchors[index];
    if (!item || !Number.isFinite(item.charIndex) || !Number.isFinite(item.unitOffset)) {
      continue;
    }
    const safeCharIndex = Math.max(safeStart, Math.min(Math.floor(item.charIndex), safeEnd));
    const safeUnitOffset = Math.max(0, item.unitOffset);
    const kind = item.kind && item.kind.length > 0 ? item.kind : 'anchor';
    const existing = sanitized[sanitized.length - 1];
    if (existing && existing.charIndex === safeCharIndex) {
      existing.unitOffset = Math.max(existing.unitOffset, safeUnitOffset);
      existing.kind = kind;
      continue;
    }
    sanitized.push({
      charIndex: safeCharIndex,
      unitOffset: safeUnitOffset,
      kind
    });
  }

  if (sanitized.length <= 0) {
    return fallback;
  }
  sanitized.sort((left: RemoteTtsSeekAnchorRecord, right: RemoteTtsSeekAnchorRecord) => {
    if (left.charIndex !== right.charIndex) {
      return left.charIndex - right.charIndex;
    }
    return left.unitOffset - right.unitOffset;
  });
  if (sanitized[0].charIndex !== safeStart) {
    sanitized.unshift({
      charIndex: safeStart,
      unitOffset: 0,
      kind: 'start'
    });
  } else {
    sanitized[0].unitOffset = 0;
    sanitized[0].kind = 'start';
  }

  const safeTotalUnits = Math.max(1, totalUnits ?? fallback.totalUnits);
  const lastSanitized = sanitized[sanitized.length - 1];
  if (lastSanitized.charIndex !== safeEnd) {
    sanitized.push({
      charIndex: safeEnd,
      unitOffset: safeTotalUnits,
      kind: 'end'
    });
  } else {
    lastSanitized.unitOffset = safeTotalUnits;
    lastSanitized.kind = 'end';
  }
  return {
    totalUnits: safeTotalUnits,
    anchors: sanitized
  };
}

function computeRemoteTtsSeekRatio(
  seekModel: RemoteTtsSeekModel,
  start: number,
  end: number,
  targetCharIndex: number
): number {
  if (end <= start) {
    return 0;
  }
  const safeTarget = Math.max(start, Math.min(Math.floor(targetCharIndex), end));
  if (safeTarget <= start) {
    return 0;
  }
  if (safeTarget >= end) {
    return 1;
  }
  const anchors = seekModel.anchors;
  let left = anchors[0];
  let right = anchors[anchors.length - 1];
  for (let index = 1; index < anchors.length; index++) {
    const current = anchors[index];
    if (safeTarget <= current.charIndex) {
      right = current;
      break;
    }
    left = current;
  }
  const spanChars = Math.max(1, right.charIndex - left.charIndex);
  const spanUnits = Math.max(0, right.unitOffset - left.unitOffset);
  const localRatio = Math.max(0, Math.min(1, (safeTarget - left.charIndex) / spanChars));
  const unitOffset = left.unitOffset + (spanUnits * localRatio);
  return Math.max(0, Math.min(1, unitOffset / Math.max(1, seekModel.totalUnits)));
}

function resolveRemoteTtsCharIndexByRatio(
  seekModel: RemoteTtsSeekModel,
  start: number,
  end: number,
  ratio: number
): number {
  if (end <= start) {
    return Math.max(0, start);
  }
  const safeRatio = Math.max(0, Math.min(1, ratio));
  const targetUnits = safeRatio * Math.max(1, seekModel.totalUnits);
  const anchors = seekModel.anchors;
  let left = anchors[0];
  let right = anchors[anchors.length - 1];
  for (let index = 1; index < anchors.length; index++) {
    const current = anchors[index];
    if (targetUnits <= current.unitOffset) {
      right = current;
      break;
    }
    left = current;
  }
  const spanUnits = Math.max(1, right.unitOffset - left.unitOffset);
  const spanChars = Math.max(1, right.charIndex - left.charIndex);
  const localRatio = Math.max(0, Math.min(1, (targetUnits - left.unitOffset) / spanUnits));
  const mapped = left.charIndex + Math.floor(spanChars * localRatio);
  return Math.max(start, Math.min(mapped, Math.max(start, end - 1)));
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

function dirname(path: string): string {
  if (!path || path.length <= 0) {
    return '';
  }
  const lastSlash = path.lastIndexOf('/');
  if (lastSlash <= 0) {
    return '';
  }
  return path.slice(0, lastSlash);
}

function ensureDirExists(path: string): void {
  if (!path || path.length <= 0) {
    return;
  }
  if (fs.accessSync(path)) {
    const stat = fs.statSync(path);
    if (!stat.isDirectory()) {
      throw new Error(`REMOTE_TTS_PATH_IS_NOT_DIRECTORY: ${path}`);
    }
    return;
  }
  fs.mkdirSync(path, true);
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

function deleteFileIfExists(path: string): void {
  try {
    if (path && path.length > 0 && fs.accessSync(path)) {
      fs.unlinkSync(path);
    }
  } catch (_ignored) {
  }
}

function writeFileBytes(path: string, bytes: Uint8Array): void {
  const parentDir = dirname(path);
  if (parentDir.length > 0) {
    ensureDirExists(parentDir);
  }
  const tempPath = `${path}.tmp_${Date.now()}_${Math.floor(Math.random() * 1000)}`;
  try {
    const file = fs.openSync(tempPath, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
    try {
      const buffer = bytes.byteOffset === 0 && bytes.byteLength === bytes.buffer.byteLength
        ? bytes.buffer
        : bytes.slice().buffer;
      if (bytes.byteLength > 0) {
        fs.writeSync(file.fd, buffer);
      }
    } finally {
      fs.closeSync(file);
    }

    deleteFileIfExists(path);
    fs.renameSync(tempPath, path);

    const stat = fs.statSync(path);
    if (stat.size !== bytes.byteLength) {
      throw new Error(`REMOTE_TTS_WRITE_SIZE_MISMATCH: expected=${bytes.byteLength}, actual=${stat.size}`);
    }
  } catch (error) {
    deleteFileIfExists(tempPath);
    throw error as Error;
  }
}

function writeJsonFile(path: string, value: Object): void {
  const bytes = new util.TextEncoder().encodeInto(JSON.stringify(value));
  writeFileBytes(path, new Uint8Array(bytes));
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
export interface ReadAloudPrecacheProgressSnapshot {
  totalSegments: number;
  completedSegments: number;
  currentSegmentIndex: number;
  currentSegmentChars: number;
  totalBytes: number;
  statusText: string;
  detailText: string;
}
export type ReadAloudPrecacheListener = (snapshot: ReadAloudPrecacheProgressSnapshot) => void;

export interface IReadAloudBackend {
  readonly engineType: ReadAloudEngineType;
  applySettings(settings: ReadAloudSettings): void;
  updateContext(context: ReadAloudSessionContext | null): void;
  setProgressListener(listener: ReadAloudProgressListener | null): void;
  setPlaybackListener(listener: ReadAloudPlaybackListener | null): void;
  listVoices(): Promise<ReadAloudVoiceOption[]>;
  getProgressSnapshot(): ReadAloudProgressSnapshot;
  resolveCharIndexByPositionMs(positionMs: number): number;
  precacheCurrentContext(listener?: ReadAloudPrecacheListener | null): Promise<void>;
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
      this.progressSnapshot.chunkEndCharIndex,
      this.progressSnapshot.currentPositionMs,
      this.progressSnapshot.totalDurationMs
    );
  }

  resolveCharIndexByPositionMs(_positionMs: number): number {
    return -1;
  }

  async precacheCurrentContext(_listener: ReadAloudPrecacheListener | null = null): Promise<void> {}

  async listVoices(): Promise<ReadAloudVoiceOption[]> {
    return [];
  }

  protected updateProgressSnapshot(
    currentCharIndex: number,
    chunkStartCharIndex: number,
    chunkEndCharIndex: number,
    currentPositionMs: number = this.progressSnapshot.currentPositionMs,
    totalDurationMs: number = this.progressSnapshot.totalDurationMs
  ): void {
    const unchanged = (
      this.progressSnapshot.currentCharIndex === currentCharIndex &&
      this.progressSnapshot.chunkStartCharIndex === chunkStartCharIndex &&
      this.progressSnapshot.chunkEndCharIndex === chunkEndCharIndex &&
      this.progressSnapshot.currentPositionMs === currentPositionMs &&
      this.progressSnapshot.totalDurationMs === totalDurationMs
    );
    if (unchanged) {
      return;
    }
    this.progressSnapshot = new ReadAloudProgressSnapshot(
      currentCharIndex,
      chunkStartCharIndex,
      chunkEndCharIndex,
      currentPositionMs,
      totalDurationMs
    );
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
  private activeSegmentPlayer: media.AVPlayer | null = null;
  private activeSegmentFile: fs.File | null = null;
  private activeSegmentPath: string = '';
  private activeSegmentIndex: number = -1;

  private remoteSettings: RemoteReadAloudSettings =
    normalizeRemoteReadAloudSettings(DEFAULT_REMOTE_READ_ALOUD_SETTINGS);
  private pendingSynthesis: Map<number, Promise<RemoteTtsPlayableSegment>> =
    new Map<number, Promise<RemoteTtsPlayableSegment>>();
  private playableSegments: Map<number, RemoteTtsPlayableSegment> =
    new Map<number, RemoteTtsPlayableSegment>();

  private cacheRootDir: string = '';
  private segmentCacheDir: string = '';
  private chapterCacheDir: string = '';
  private manifestPath: string = '';
  private activeManifest: RemoteTtsManifest | null = null;
  private contentDigest: string = '';
  private remoteDigest: string = '';
  private sessionTempDir: string = '';

  private updateRemoteUiStatus(phase: string, text: string, detail: string = ''): void {
    AppStorage.setOrCreate(READ_ALOUD_UI_STATUS_PHASE_KEY, phase);
    AppStorage.setOrCreate(READ_ALOUD_UI_STATUS_TEXT_KEY, text);
    AppStorage.setOrCreate(READ_ALOUD_UI_STATUS_DETAIL_KEY, detail);
    AppStorage.setOrCreate(READ_ALOUD_UI_STATUS_UPDATED_AT_KEY, Date.now());
  }

  private buildSegmentUiDetail(index: number, extra: string = ''): string {
    const total = Math.max(1, this.queue.length);
    const current = Math.max(1, Math.min(index + 1, total));
    return extra.length > 0
      ? `第${current}/${total}段 · ${extra}`
      : `第${current}/${total}段`;
  }

  private buildReadableRemoteErrorText(error: Object | string): string {
    const detail = formatReadAloudError(error).trim();
    if (detail.length <= 0) {
      return '未知错误';
    }
    return detail.length > 72 ? `${detail.slice(0, 72)}...` : detail;
  }

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
      this.segmentCacheDir = '';
      this.chapterCacheDir = '';
      this.manifestPath = '';
      this.sessionTempDir = '';
      this.stopProgressTimer();
      this.updateProgressSnapshot(-1, -1, -1, -1, -1);
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
    if (inPlaybackFlow) {
      return;
    }
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
    this.syncRemoteProgressSnapshot(this.currentCharIndex, range.start, range.end, -1, this.queueIndex);
  }

  async start(): Promise<void> {
    const content = this.context?.content ?? '';
    if (content.trim().length <= 0) {
      throw new Error('REMOTE_TTS_NO_CONTENT');
    }

    await this.stopActiveSegmentPlayer('start_before_new_session');
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

    this.updateRemoteUiStatus('preparing', '正在准备远程听书', `共 ${this.queue.length} 段`);
    await this.prepareCacheAndManifest();
    this.currentCharIndex = this.normalizeResumeCharIndex(this.context?.resumeCharIndex ?? this.currentCharIndex, content);
    this.queueIndex = this.findQueueIndexByChar(this.currentCharIndex);
    this.playbackSessionToken = this.createRequestId('remote_session');

    const range = this.getQueueRange(this.queueIndex);
    this.updateRemoteUiStatus('preparing', '已定位到播放片段', this.buildSegmentUiDetail(this.queueIndex));
    this.syncRemoteProgressSnapshot(this.currentCharIndex, range.start, range.end, -1, this.queueIndex);
    this.playLoopSafely(this.playbackSessionToken);
  }

  async pause(): Promise<void> {
    this.syncActiveSegmentProgressFromPlayer();
    this.pauseRequested = true;
    this.stopRequested = false;
    this.playbackSessionToken = '';
    this.stopProgressTimer();
    await this.stopActiveSegmentPlayer('pause');
    const range = this.getQueueRange(this.queueIndex);
    this.updateRemoteUiStatus('paused', '已暂停听书', this.buildSegmentUiDetail(this.queueIndex));
    this.syncRemoteProgressSnapshot(this.currentCharIndex, range.start, range.end, -1, this.queueIndex);
  }

  async stop(): Promise<void> {
    this.syncActiveSegmentProgressFromPlayer();
    this.stopRequested = true;
    this.pauseRequested = false;
    this.playbackSessionToken = '';
    this.stopProgressTimer();
    this.pendingSynthesis.clear();
    await this.stopActiveSegmentPlayer('stop');
    this.queueIndex = this.findQueueIndexByChar(this.currentCharIndex);
    const range = this.getQueueRange(this.queueIndex);
    this.updateRemoteUiStatus('stopped', '已停止听书');
    this.syncRemoteProgressSnapshot(this.currentCharIndex, range.start, range.end, -1, this.queueIndex);
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
    this.segmentCacheDir = '';
    this.chapterCacheDir = '';
    this.manifestPath = '';
    this.sessionTempDir = '';
    this.updateProgressSnapshot(-1, -1, -1, -1, -1);
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

  resolveCharIndexByPositionMs(positionMs: number): number {
    if (!this.context || !this.context.content || this.context.content.length <= 0 || this.queue.length <= 0) {
      return -1;
    }
    const totalDurationMs = this.getChapterDurationMs();
    if (totalDurationMs <= 0) {
      return -1;
    }
    const safePositionMs = Math.max(0, Math.min(Math.floor(positionMs), totalDurationMs));
    let accumulatedMs = 0;
    for (let index = 0; index < this.queue.length; index++) {
      const durationMs = this.getSegmentDurationMsByIndex(index);
      if (durationMs <= 0) {
        continue;
      }
      const range = this.getQueueRange(index);
      const nextAccumulatedMs = accumulatedMs + durationMs;
      if (safePositionMs < nextAccumulatedMs || index === this.queue.length - 1) {
        return this.resolveCharIndexWithinSegment(
          index,
          range.start,
          range.end,
          durationMs,
          safePositionMs - accumulatedMs
        );
      }
      accumulatedMs = nextAccumulatedMs;
    }
    return Math.max(0, this.context.content.length - 1);
  }

  async precacheCurrentContext(listener: ReadAloudPrecacheListener | null = null): Promise<void> {
    const content = this.context?.content ?? '';
    if (!content || content.trim().length <= 0) {
      throw new Error('REMOTE_TTS_NO_CONTENT');
    }

    await this.stopActiveSegmentPlayer('precache_before_new_session');
    this.remoteSettings = this.resolveRemoteSettings();
    this.validateRemoteSettings(this.remoteSettings);
    this.stopRequested = false;
    this.pauseRequested = false;
    this.pendingSynthesis.clear();
    this.playableSegments.clear();
    this.stopProgressTimer();

    const contentDigest = fnv1aHashHex(content);
    const remoteDigest = this.buildRemoteDigest(this.remoteSettings);
    const queueToken = `${this.context?.bookId ?? ''}#${this.context?.chapterIndex ?? -1}#${contentDigest}#${remoteDigest}`;
    if (this.queueToken !== queueToken) {
      this.rebuildQueue(content);
      this.queueToken = queueToken;
    }
    this.contentDigest = contentDigest;
    this.remoteDigest = remoteDigest;
    if (this.queue.length <= 0) {
      throw new Error('REMOTE_TTS_EMPTY_QUEUE');
    }

    this.queueIndex = 0;
    this.currentCharIndex = 0;
    this.playbackSessionToken = this.createRequestId('remote_precache_session');
    const sessionToken = this.playbackSessionToken;

    this.updateRemoteUiStatus('precache', '正在准备整章听书缓存', `共 ${this.queue.length} 段`);
    await this.prepareCacheAndManifest();

    let totalBytes = 0;
    listener?.({
      totalSegments: this.queue.length,
      completedSegments: 0,
      currentSegmentIndex: 0,
      currentSegmentChars: this.queue[0]?.length ?? 0,
      totalBytes: 0,
      statusText: '正在准备整章听书缓存',
      detailText: `第1/${this.queue.length}段`
    });

    for (let index = 0; index < this.queue.length; index++) {
      if (!this.isSessionActive(sessionToken)) {
        throw new Error('REMOTE_TTS_PRECACHE_ABORTED');
      }
      const range = this.getQueueRange(index);
      this.queueIndex = index;
      this.currentCharIndex = range.start;
      this.updateRemoteUiStatus('precache', '正在缓存听书音频', this.buildSegmentUiDetail(index, `${this.queue[index]?.length ?? 0} 字`));
      this.syncRemoteProgressSnapshot(this.currentCharIndex, range.start, range.end, -1, index);
      const segment = await this.ensureSegment(index, sessionToken);
      totalBytes += Math.max(0, segment.bytes);
      listener?.({
        totalSegments: this.queue.length,
        completedSegments: index + 1,
        currentSegmentIndex: index,
        currentSegmentChars: this.queue[index]?.length ?? 0,
        totalBytes,
        statusText: '正在缓存听书音频',
        detailText: this.buildSegmentUiDetail(index, `${index + 1}/${this.queue.length}`)
      });
    }

    this.tryConcatChapterAudio();
    this.playbackSessionToken = '';
    this.queueIndex = 0;
    this.currentCharIndex = 0;
    this.updateRemoteUiStatus('cached', '当前章节听书缓存已完成', `共 ${this.queue.length} 段，${totalBytes} bytes`);
    logger.info(
      TAG,
      `远程TTS整章预缓存完成: bookId=${this.context?.bookId ?? ''}, chapterIndex=${this.context?.chapterIndex ?? -1}, segments=${this.queue.length}, bytes=${totalBytes}`
    );
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
      settings.stylePrompt.trim(),
      settings.audioFormat.trim(),
      String(settings.streamEnabled),
      String(settings.maxInputChars),
      String(settings.reservedInputChars),
      String(settings.minChunkChars),
      String(settings.targetChunkChars),
      String(settings.maxChunkChars),
      settings.customHeadersJson ?? '',
      settings.extraBodyJson ?? ''
    ].join('|');
    return fnv1aHashHex(digest);
  }

  private buildRemoteInputText(text: string): string {
    if (!isXiaomiMimoRemoteReadAloud(this.remoteSettings)) {
      return text;
    }
    return buildXiaomiMimoStyledText(this.remoteSettings.stylePrompt, text);
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
      char === '。' ||
      char === '！' ||
      char === '？' ||
      char === '，' ||
      char === '、' ||
      char === '；' ||
      char === '：' ||
      char === '…';
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

  private findQueueIndexByRange(start: number, end: number): number {
    if (this.queue.length <= 0) {
      return 0;
    }
    for (let index = 0; index < this.queue.length; index++) {
      if ((this.queueStart[index] ?? -1) === start && (this.queueEnd[index] ?? -1) === end) {
        return index;
      }
    }
    return this.findQueueIndexByChar(start);
  }

  private getSegmentCacheRecordByIndex(index: number): RemoteTtsSegmentCacheRecord | null {
    const playable = this.playableSegments.get(index);
    if (playable) {
      return playable;
    }
    if (!this.activeManifest) {
      return null;
    }
    for (let manifestIndex = 0; manifestIndex < this.activeManifest.segments.length; manifestIndex++) {
      const item = this.activeManifest.segments[manifestIndex];
      if (item.index === index) {
        return item;
      }
    }
    return null;
  }

  private getSegmentSeekModelByIndex(index: number, start: number, end: number): RemoteTtsSeekModel {
    const record = this.getSegmentCacheRecordByIndex(index);
    return buildRemoteTtsSeekModelFromRecord(
      start,
      end,
      this.queue[index] ?? '',
      record?.seekTotalUnits,
      record?.seekAnchors
    );
  }

  private getSegmentDurationMsByIndex(index: number): number {
    if (index < 0 || index >= this.queue.length) {
      return 0;
    }
    const playable = this.playableSegments.get(index);
    if (playable && playable.durationMs > 0) {
      return playable.durationMs;
    }
    if (this.activeManifest) {
      for (const item of this.activeManifest.segments) {
        if (item.index === index && item.durationMs > 0) {
          return item.durationMs;
        }
      }
    }
    return estimateDurationMsByCharCount((this.queue[index] ?? '').length, this.settings?.speed ?? 1);
  }

  private getAccumulatedDurationMsBeforeIndex(index: number): number {
    if (index <= 0 || this.queue.length <= 0) {
      return 0;
    }
    let total = 0;
    for (let current = 0; current < index; current++) {
      total += this.getSegmentDurationMsByIndex(current);
    }
    return total;
  }

  private getChapterDurationMs(): number {
    if (this.queue.length <= 0) {
      return -1;
    }
    let total = 0;
    for (let index = 0; index < this.queue.length; index++) {
      total += this.getSegmentDurationMsByIndex(index);
    }
    return total > 0 ? total : -1;
  }

  private resolveCharIndexWithinSegment(
    segmentIndex: number,
    start: number,
    end: number,
    durationMs: number,
    currentTimeMs: number
  ): number {
    if (end <= start) {
      return Math.max(0, start);
    }
    const safeDurationMs = Math.max(1, durationMs);
    const clampedTimeMs = Math.max(0, Math.min(currentTimeMs, safeDurationMs));
    const ratio = Math.max(0, Math.min(1, clampedTimeMs / safeDurationMs));
    return resolveRemoteTtsCharIndexByRatio(
      this.getSegmentSeekModelByIndex(segmentIndex, start, end),
      start,
      end,
      ratio
    );
  }

  private computeChapterPositionMs(
    currentCharIndex: number,
    chunkStartCharIndex: number,
    chunkEndCharIndex: number,
    currentTimeMsInChunk: number = -1,
    queueIndexOverride: number = -1
  ): number {
    if (this.queue.length <= 0) {
      return -1;
    }
    const queueIndex = queueIndexOverride >= 0
      ? Math.max(0, Math.min(queueIndexOverride, this.queue.length - 1))
      : this.findQueueIndexByRange(chunkStartCharIndex, chunkEndCharIndex);
    const durationMs = this.getSegmentDurationMsByIndex(queueIndex);
    if (durationMs <= 0) {
      return -1;
    }
    let localTimeMs = currentTimeMsInChunk >= 0
      ? Math.max(0, Math.min(Math.floor(currentTimeMsInChunk), durationMs))
      : this.computeSegmentSeekTimeMs(
        queueIndex,
        chunkStartCharIndex,
        chunkEndCharIndex,
        durationMs,
        currentCharIndex
      );
    if (chunkEndCharIndex > chunkStartCharIndex && currentCharIndex >= chunkEndCharIndex) {
      localTimeMs = durationMs;
    }
    return this.getAccumulatedDurationMsBeforeIndex(queueIndex) + localTimeMs;
  }

  private syncRemoteProgressSnapshot(
    currentCharIndex: number,
    chunkStartCharIndex: number,
    chunkEndCharIndex: number,
    currentTimeMsInChunk: number = -1,
    queueIndexOverride: number = -1
  ): void {
    const totalDurationMs = this.getChapterDurationMs();
    const currentPositionMs = currentCharIndex >= 0
      ? this.computeChapterPositionMs(
        currentCharIndex,
        chunkStartCharIndex,
        chunkEndCharIndex,
        currentTimeMsInChunk,
        queueIndexOverride
      )
      : -1;
    this.updateProgressSnapshot(
      currentCharIndex,
      chunkStartCharIndex,
      chunkEndCharIndex,
      currentPositionMs,
      totalDurationMs
    );
  }

  private syncActiveSegmentProgressFromPlayer(): void {
    const player = this.activeSegmentPlayer;
    const segmentIndex = this.activeSegmentIndex;
    if (!player || segmentIndex < 0 || segmentIndex >= this.queue.length) {
      return;
    }
    const range = this.getQueueRange(segmentIndex);
    const durationMs = this.getSegmentDurationMsByIndex(segmentIndex);
    this.updateSegmentProgressByPlayerTime(range.start, range.end, durationMs, player.currentTime);
  }

  private buildSegmentStoragePaths(index: number, useSessionTemp: boolean = false): RemoteTtsSegmentStoragePaths {
    const text = this.queue[index] ?? '';
    const cacheKey = buildRemoteTtsTextCacheKey(text);
    const textDigest = buildRemoteTtsTextDigest(text);
    const textLength = normalizeRemoteTtsCacheText(text).length;
    const textPreview = buildRemoteTtsTextPreview(text);
    const ext = normalizeAudioExtension(this.remoteSettings.audioFormat);
    const baseDir = useSessionTemp ? this.sessionTempDir : this.segmentCacheDir;
    return {
      cacheKey,
      textDigest,
      textLength,
      textPreview,
      audioPath: `${baseDir}/${cacheKey}.${ext}`,
      metaPath: `${baseDir}/${cacheKey}.json`
    };
  }

  private async prepareCacheAndManifest(): Promise<void> {
    const abilityContext = uiContextManager.getAbilityContext();
    const filesDir = abilityContext?.filesDir ?? abilityContext?.cacheDir ?? '';
    if (filesDir.length <= 0) {
      throw new Error('REMOTE_TTS_CONTEXT_FILES_DIR_EMPTY');
    }

    this.cacheRootDir = `${filesDir}/read_aloud_remote`;
    ensureDirExists(this.cacheRootDir);
    this.segmentCacheDir = `${this.cacheRootDir}/segments/${this.remoteDigest}`;
    ensureDirExists(this.segmentCacheDir);
    const safeBookId = sanitizeFileNamePart(this.context?.bookId ?? 'unknown_book');
    const chapterIndex = this.context?.chapterIndex ?? -1;
    this.chapterCacheDir = `${this.cacheRootDir}/books/${safeBookId}/chapter_${chapterIndex}/${this.contentDigest}/${this.remoteDigest}`;
    ensureDirExists(this.chapterCacheDir);
    this.manifestPath = `${this.chapterCacheDir}/manifest.json`;
    this.sessionTempDir = `${this.chapterCacheDir}/session/${Date.now()}`;
    ensureDirExists(this.sessionTempDir);
    logger.debug(
      TAG,
      `远程TTS缓存目录已准备: cacheAudioFiles=${this.remoteSettings.cacheAudioFiles}, segmentCacheDir=${this.segmentCacheDir}, chapterCacheDir=${this.chapterCacheDir}, sessionTempDir=${this.sessionTempDir}`
    );

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
      logger.info(TAG, `远程TTS章节清单已创建: bookId=${this.context?.bookId ?? ''}, chapterIndex=${chapterIndex}, queueSize=${this.queue.length}`);
    } else {
      logger.debug(TAG, `远程TTS章节清单已加载: bookId=${this.activeManifest.bookId}, chapterIndex=${this.activeManifest.chapterIndex}, segments=${this.activeManifest.segments.length}`);
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
    } catch (error) {
      logger.warn(TAG, `远程TTS章节清单读取失败: path=${this.manifestPath}, error=${formatReadAloudError(error)}`);
      return null;
    }
  }

  private persistManifest(): void {
    if (!this.activeManifest || !this.manifestPath) {
      return;
    }
    try {
      this.activeManifest.updatedAt = Date.now();
      writeJsonFile(this.manifestPath, this.activeManifest as Object);
      this.publishReadAloudCacheUpdated('manifest_persisted');
    } catch (error) {
      logger.warn(TAG, `远程TTS章节清单写入失败: path=${this.manifestPath}, error=${formatReadAloudError(error)}`);
    }
  }

  private publishReadAloudCacheUpdated(reason: string): void {
    const bookId = this.context?.bookId ?? '';
    if (bookId.length <= 0) {
      return;
    }
    eventBus.publish(
      GameEvent.READ_ALOUD_CACHE_UPDATED,
      new ReadAloudCacheUpdatedPayload(
        bookId,
        this.context?.chapterIndex ?? -1,
        reason,
        this.remoteDigest
      )
    );
  }

  private loadSegmentIndexRecord(metaPath: string): RemoteTtsSegmentIndexRecord | null {
    if (!metaPath || !fs.accessSync(metaPath)) {
      return null;
    }
    try {
      const text = new util.TextDecoder('utf-8').decodeToString(readFileBytes(metaPath));
      const record = JSON.parse(text) as RemoteTtsSegmentIndexRecord;
      if (!record || record.version !== REMOTE_TTS_SEGMENT_INDEX_VERSION) {
        return null;
      }
      return record;
    } catch (error) {
      logger.warn(TAG, `远程TTS分片索引读取失败: path=${metaPath}, error=${formatReadAloudError(error)}`);
      return null;
    }
  }

  private persistSegmentIndexRecord(segment: RemoteTtsPlayableSegment): void {
    if (!this.remoteSettings.cacheAudioFiles || segment.filePath.length <= 0) {
      return;
    }
    const paths = this.buildSegmentStoragePaths(segment.index);
    if (segment.filePath !== paths.audioPath) {
      return;
    }
    const record: RemoteTtsSegmentIndexRecord = {
      version: REMOTE_TTS_SEGMENT_INDEX_VERSION,
      updatedAt: Date.now(),
      cacheKey: segment.cacheKey,
      textDigest: segment.textDigest,
      textLength: segment.textLength,
      textPreview: segment.textPreview,
      remoteDigest: this.remoteDigest,
      audioFormat: normalizeAudioExtension(this.remoteSettings.audioFormat),
      filePath: segment.filePath,
      bytes: segment.bytes,
      durationMs: segment.durationMs,
      bookId: this.context?.bookId ?? '',
      chapterIndex: this.context?.chapterIndex ?? -1,
      start: segment.start,
      end: segment.end,
      seekTotalUnits: segment.seekTotalUnits,
      seekAnchors: segment.seekAnchors
    };
    try {
      writeJsonFile(paths.metaPath, record as Object);
    } catch (error) {
      logger.warn(TAG, `远程TTS分片索引写入失败: path=${paths.metaPath}, cacheKey=${segment.cacheKey}, error=${formatReadAloudError(error)}`);
    }
  }

  private buildSegmentDurationMs(text: string, synthesized: RemoteTtsSynthesizedSegment): number {
    return Math.max(
      REMOTE_TTS_FALLBACK_SEGMENT_MIN_MS,
      synthesized.durationMs > 0 ? synthesized.durationMs : estimateDurationMsByCharCount(text.length, this.settings?.speed ?? 1)
    );
  }

  private tryLoadNormalizedCachedSegment(index: number, range: QueueCharRange): RemoteTtsPlayableSegment | null {
    if (!this.remoteSettings.cacheAudioFiles || !this.segmentCacheDir) {
      return null;
    }
    const paths = this.buildSegmentStoragePaths(index);
    if (!fs.accessSync(paths.audioPath)) {
      return null;
    }
    const record = this.loadSegmentIndexRecord(paths.metaPath);
    if (record) {
      if (
        record.cacheKey !== paths.cacheKey ||
        record.textDigest !== paths.textDigest ||
        record.remoteDigest !== this.remoteDigest ||
        record.filePath !== paths.audioPath
      ) {
        logger.warn(TAG, `远程TTS分片索引不匹配，已忽略: index=${index}, cacheKey=${paths.cacheKey}, metaPath=${paths.metaPath}`);
        return null;
      }
    }
    try {
      const stat = fs.statSync(paths.audioPath);
      if (stat.size <= 0) {
        logger.warn(TAG, `远程TTS缓存音频文件为空，已忽略: index=${index}, path=${paths.audioPath}`);
        return null;
      }
      const seekModel = buildRemoteTtsSeekModelFromRecord(
        range.start,
        range.end,
        this.queue[index] ?? '',
        record?.seekTotalUnits,
        record?.seekAnchors
      );
      const segment: RemoteTtsPlayableSegment = {
        index,
        start: range.start,
        end: range.end,
        cacheKey: paths.cacheKey,
        textDigest: paths.textDigest,
        textLength: paths.textLength,
        textPreview: paths.textPreview,
        filePath: paths.audioPath,
        bytes: record && record.bytes > 0 ? record.bytes : stat.size,
        durationMs: record && record.durationMs > 0
          ? record.durationMs
          : estimateDurationMsByCharCount((this.queue[index] ?? '').length, this.settings?.speed ?? 1),
        seekTotalUnits: seekModel.totalUnits,
        seekAnchors: seekModel.anchors
      };
      if (!record) {
        this.persistSegmentIndexRecord(segment);
      }
      this.updateManifestSegment(segment);
      logger.debug(TAG, `远程TTS命中规范化缓存: index=${index}, cacheKey=${paths.cacheKey}, bytes=${segment.bytes}, path=${paths.audioPath}`);
      return segment;
    } catch (error) {
      logger.warn(TAG, `远程TTS缓存分片恢复失败: index=${index}, cacheKey=${paths.cacheKey}, error=${formatReadAloudError(error)}`);
      return null;
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
      const expectedPaths = this.buildSegmentStoragePaths(item.index);
      if (item.textDigest !== expectedPaths.textDigest || item.cacheKey !== expectedPaths.cacheKey) {
        continue;
      }
      const durationMs = item.durationMs > 0
        ? item.durationMs
        : estimateDurationMsByCharCount(this.queue[item.index].length, this.settings?.speed ?? 1);
      const seekModel = buildRemoteTtsSeekModelFromRecord(
        item.start,
        item.end,
        this.queue[item.index] ?? '',
        item.seekTotalUnits,
        item.seekAnchors
      );
      this.playableSegments.set(item.index, {
        index: item.index,
        start: item.start,
        end: item.end,
        cacheKey: item.cacheKey,
        textDigest: item.textDigest,
        textLength: item.textLength,
        textPreview: item.textPreview,
        filePath: item.filePath,
        bytes: item.bytes,
        durationMs,
        seekTotalUnits: seekModel.totalUnits,
        seekAnchors: seekModel.anchors
      });
    }
  }

  private updateManifestSegment(segment: RemoteTtsPlayableSegment): void {
    if (!this.activeManifest || segment.filePath.length <= 0) {
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
      cacheKey: segment.cacheKey,
      textDigest: segment.textDigest,
      textLength: segment.textLength,
      textPreview: segment.textPreview,
      filePath: segment.filePath,
      bytes: segment.bytes,
      durationMs: segment.durationMs,
      seekTotalUnits: segment.seekTotalUnits,
      seekAnchors: segment.seekAnchors
    });
    next.sort((a, b) => a.index - b.index);
    this.activeManifest.segments = next;
    this.persistManifest();
  }

  private segmentDigest(index: number): string {
    return buildRemoteTtsTextDigest(this.queue[index] ?? '');
  }

  private prefetchSegments(startIndex: number, sessionToken: string): void {
    if (!this.isSessionActive(sessionToken)) {
      return;
    }
    const count = Math.max(REMOTE_TTS_PREFETCH_MIN, Math.min(REMOTE_TTS_PREFETCH_MAX, this.remoteSettings.prefetchSegments));
    const end = Math.min(this.queue.length - 1, startIndex + count - 1);
    for (let index = startIndex; index <= end; index++) {
      this.ensureSegment(index, sessionToken).catch((error: Object | string) => {
        logger.warn(TAG, `远程TTS预取分片失败: index=${index}, error=${formatReadAloudError(error)}`);
      });
    }
  }

  private prefetchSegmentsSequentially(startIndex: number, sessionToken: string): void {
    if (!this.isSessionActive(sessionToken)) {
      return;
    }
    const count = Math.max(REMOTE_TTS_PREFETCH_MIN, Math.min(REMOTE_TTS_PREFETCH_MAX, this.remoteSettings.prefetchSegments));
    const end = Math.min(this.queue.length - 1, startIndex + count - 1);
    (async (): Promise<void> => {
      for (let index = startIndex; index <= end; index++) {
        if (!this.isSessionActive(sessionToken)) {
          return;
        }
        try {
          await this.ensureSegment(index, sessionToken);
        } catch (error) {
          if (!this.isSessionActive(sessionToken)) {
            return;
          }
          logger.warn(TAG, `远程TTS预取分片失败: index=${index}, error=${formatReadAloudError(error)}`);
          return;
        }
      }
    })();
  }

  private playLoopSafely(sessionToken: string): void {
    this.playLoop(sessionToken).catch((error: Object | string) => {
      if (!this.isSessionActive(sessionToken)) {
        return;
      }
      this.pauseRequested = true;
      this.stopRequested = false;
      this.stopProgressTimer();
      logger.error(TAG, `远程TTS播放循环失败: queueIndex=${this.queueIndex}, currentChar=${this.currentCharIndex}, error=${formatReadAloudError(error)}`);
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
      this.updateRemoteUiStatus('playing', '正在播放远程语音', this.buildSegmentUiDetail(this.queueIndex));
      this.syncRemoteProgressSnapshot(this.currentCharIndex, range.start, range.end, -1, this.queueIndex);
      await this.playSegmentWithPlayer(segment, range, sessionToken);
      if (!this.isSessionActive(sessionToken)) {
        return;
      }
      this.stopProgressTimer();
      this.currentCharIndex = range.end;
      this.syncRemoteProgressSnapshot(this.currentCharIndex, range.start, range.end, segment.durationMs, this.queueIndex);
      this.queueIndex += 1;
      this.prefetchSegmentsSequentially(this.queueIndex, sessionToken);
    }
  }

  private isSessionActive(sessionToken: string): boolean {
    return this.playbackSessionToken.length > 0 &&
      this.playbackSessionToken === sessionToken &&
      !this.pauseRequested &&
      !this.stopRequested;
  }

  private updateSegmentProgressByPlayerTime(start: number, end: number, durationMs: number, currentTimeMs: number): void {
    if (end <= start) {
      return;
    }
    const safeDurationMs = Math.max(1, durationMs);
    const clampedTimeMs = Math.max(0, Math.min(currentTimeMs, safeDurationMs));
    const safeNext = this.resolveCharIndexWithinSegment(
      this.findQueueIndexByRange(start, end),
      start,
      end,
      safeDurationMs,
      clampedTimeMs
    );
    if (safeNext !== this.currentCharIndex) {
      this.currentCharIndex = safeNext;
    }
    this.syncRemoteProgressSnapshot(
      this.currentCharIndex,
      start,
      end,
      clampedTimeMs,
      this.findQueueIndexByRange(start, end)
    );
  }

  private computeSegmentSeekTimeMs(
    segmentIndex: number,
    start: number,
    end: number,
    durationMs: number,
    currentCharIndexOverride?: number
  ): number {
    if (end <= start || durationMs <= 0) {
      return 0;
    }
    const maxPlayableChar = Math.max(start, end - 1);
    const baseCharIndex = typeof currentCharIndexOverride === 'number'
      ? currentCharIndexOverride
      : this.currentCharIndex;
    const safeCurrent = Math.max(start, Math.min(baseCharIndex, maxPlayableChar));
    if (safeCurrent <= start) {
      return 0;
    }
    const ratio = computeRemoteTtsSeekRatio(
      this.getSegmentSeekModelByIndex(segmentIndex, start, end),
      start,
      end,
      safeCurrent
    );
    return Math.max(0, Math.min(durationMs - 1, Math.floor(durationMs * ratio)));
  }

  private applyActualSegmentDuration(segment: RemoteTtsPlayableSegment, durationMs: number): void {
    const safeDurationMs = Math.max(REMOTE_TTS_FALLBACK_SEGMENT_MIN_MS, Math.floor(durationMs));
    if (segment.durationMs === safeDurationMs) {
      return;
    }
    segment.durationMs = safeDurationMs;
    this.updateManifestSegment(segment);
    this.persistSegmentIndexRecord(segment);
  }

  private applyRemotePlayerVolume(player: media.AVPlayer): void {
    const volume = Math.max(0, Math.min(1, this.settings?.volume ?? 1));
    try {
      player.setVolume(volume);
    } catch (error) {
      logger.warn(TAG, `远程TTS播放器设置音量失败: volume=${volume}, error=${formatReadAloudError(error)}`);
    }
  }

  private async seekSegmentPlayer(player: media.AVPlayer, seekMs: number): Promise<void> {
    const safeSeekMs = Math.max(0, Math.floor(seekMs));
    if (safeSeekMs <= 0) {
      return;
    }
    await new Promise<void>((resolve, reject) => {
      let settled = false;
      let timeoutId: number = -1;
      const finish = (error?: Object | string): void => {
        if (settled) {
          return;
        }
        settled = true;
        if (timeoutId >= 0) {
          clearTimeout(timeoutId);
          timeoutId = -1;
        }
        player.off('seekDone', onSeekDone);
        if (error) {
          reject(error as Error);
          return;
        }
        resolve();
      };
      const onSeekDone = (_timeMs: number): void => {
        finish();
      };
      player.on('seekDone', onSeekDone);
      timeoutId = setTimeout(() => {
        logger.warn(TAG, `远程TTS播放器等待 seekDone 超时，继续播放: seekMs=${safeSeekMs}`);
        finish();
      }, 1200);
      try {
        player.seek(safeSeekMs);
      } catch (error) {
        finish(error);
      }
    });
  }

  private isExpectedPlayerState(
    state: media.AVPlayerState,
    expectedStates: media.AVPlayerState[]
  ): boolean {
    for (const expectedState of expectedStates) {
      if (state === expectedState) {
        return true;
      }
    }
    return false;
  }

  private async waitForPlayerState(
    player: media.AVPlayer,
    expectedState: media.AVPlayerState | media.AVPlayerState[],
    timeoutMs: number,
    label: string
  ): Promise<media.AVPlayerState> {
    const expectedStates = expectedState instanceof Array ? expectedState : [expectedState];
    if (this.isExpectedPlayerState(player.state, expectedStates)) {
      return player.state;
    }
    return await new Promise<media.AVPlayerState>((resolve, reject) => {
      let settled = false;
      let timeoutId: number = -1;
      const expectedLabel = expectedStates.join('|');
      const finish = (state: media.AVPlayerState, error?: Object | string): void => {
        if (settled) {
          return;
        }
        settled = true;
        if (timeoutId >= 0) {
          clearTimeout(timeoutId);
          timeoutId = -1;
        }
        player.off('stateChange', onStateChange);
        if (error) {
          reject(error as Error);
          return;
        }
        resolve(state);
      };
      const onStateChange = (state: media.AVPlayerState, reason: media.StateChangeReason): void => {
        if (this.isExpectedPlayerState(state, expectedStates)) {
          finish(state);
          return;
        }
        if (state === 'error' || state === 'released') {
          finish(
            state,
            `REMOTE_TTS_PLAYER_WAIT_STATE_FAILED: label=${label}, expected=${expectedLabel}, state=${state}, reason=${reason}`
          );
        }
      };
      player.on('stateChange', onStateChange);
      if (this.isExpectedPlayerState(player.state, expectedStates)) {
        finish(player.state);
        return;
      }
      timeoutId = setTimeout(() => {
        if (this.isExpectedPlayerState(player.state, expectedStates)) {
          finish(player.state);
          return;
        }
        finish(
          player.state,
          `REMOTE_TTS_PLAYER_WAIT_STATE_TIMEOUT: label=${label}, expected=${expectedLabel}, current=${player.state}`
        );
      }, timeoutMs);
    });
  }

  private async prepareSegmentPlayer(player: media.AVPlayer, segmentIndex: number): Promise<void> {
    const readyState = await this.waitForPlayerState(
      player,
      ['initialized', 'prepared'],
      1800,
      `index=${segmentIndex}_after_fdSrc`
    );
    logger.debug(TAG, `远程TTS播放器数据源就绪: index=${segmentIndex}, state=${readyState}`);
    if (readyState === 'prepared' || player.state === 'prepared') {
      return;
    }
    const stateBeforePrepare = player.state;
    if (stateBeforePrepare !== 'initialized' && stateBeforePrepare !== 'stopped') {
      throw new Error(`REMOTE_TTS_PLAYER_PREPARE_INVALID_STATE: index=${segmentIndex}, state=${stateBeforePrepare}`);
    }
    try {
      await player.prepare();
    } catch (error) {
      const stateAfterPrepareError = String(player.state);
      if (stateAfterPrepareError !== 'prepared') {
        throw error as Error;
      }
      logger.warn(
        TAG,
        `远程TTS播放器prepare返回异常但已进入prepared，按成功处理: index=${segmentIndex}, error=${formatReadAloudError(error)}`
      );
    }
    const preparedState = await this.waitForPlayerState(
      player,
      ['prepared', 'playing', 'paused', 'completed'],
      1800,
      `index=${segmentIndex}_after_prepare`
    );
    logger.debug(TAG, `远程TTS播放器prepare完成: index=${segmentIndex}, state=${preparedState}`);
  }

  private async playSegmentWithPlayer(
    segment: RemoteTtsPlayableSegment,
    range: QueueCharRange,
    sessionToken: string
  ): Promise<void> {
    this.ensureSegmentPlayableFile(segment);
    if (!segment.filePath || segment.filePath.length <= 0 || !fs.accessSync(segment.filePath)) {
      throw new Error(`REMOTE_TTS_SEGMENT_FILE_MISSING: index=${segment.index}, path=${segment.filePath}`);
    }
    const stat = fs.statSync(segment.filePath);
    if (stat.size <= 0) {
      throw new Error(`REMOTE_TTS_SEGMENT_FILE_EMPTY: index=${segment.index}, path=${segment.filePath}`);
    }

    const player = await media.createAVPlayer();
    const file = fs.openSync(segment.filePath, fs.OpenMode.READ_ONLY);
    const resumeCharIndex = this.currentCharIndex;
    let stateChangeHandler: (state: media.AVPlayerState, reason: media.StateChangeReason) => void = () => {};
    let timeUpdateHandler: (timeMs: number) => void = () => {};
    let errorHandler: (error: Object) => void = () => {};
    let playbackSettled = false;
    let allowProgressSync = false;

    const playbackPromise = new Promise<void>((resolve, reject) => {
      const finishResolve = (): void => {
        if (playbackSettled) {
          return;
        }
        playbackSettled = true;
        resolve();
      };
      const finishReject = (error: Object | string): void => {
        if (playbackSettled) {
          return;
        }
        playbackSettled = true;
        reject(error as Error);
      };

      stateChangeHandler = (state: media.AVPlayerState, reason: media.StateChangeReason): void => {
        logger.debug(
          TAG,
          `远程TTS播放器状态变化: index=${segment.index}, state=${state}, reason=${reason}, currentTime=${player.currentTime}, duration=${player.duration}`
        );
        if (!this.isSessionActive(sessionToken)) {
          if (state === 'paused' || state === 'stopped' || state === 'released' || state === 'completed') {
            finishResolve();
          }
          return;
        }
        if (state === 'completed') {
          this.currentCharIndex = range.end;
          this.syncRemoteProgressSnapshot(
            this.currentCharIndex,
            range.start,
            range.end,
            segment.durationMs,
            segment.index
          );
          finishResolve();
          return;
        }
        if (state === 'stopped' || state === 'released') {
          this.updateSegmentProgressByPlayerTime(range.start, range.end, segment.durationMs, player.currentTime);
          finishReject(`REMOTE_TTS_SEGMENT_TERMINATED_UNEXPECTEDLY: index=${segment.index}, state=${state}`);
        }
      };
      timeUpdateHandler = (timeMs: number): void => {
        if (!this.isSessionActive(sessionToken)) {
          return;
        }
        if (!allowProgressSync) {
          return;
        }
        this.updateSegmentProgressByPlayerTime(range.start, range.end, segment.durationMs, timeMs);
      };
      errorHandler = (error: Object): void => {
        logger.error(
          TAG,
          `远程TTS播放器错误: index=${segment.index}, path=${segment.filePath}, error=${formatReadAloudError(error)}`
        );
        finishReject(error);
      };
    });

    player.on('stateChange', stateChangeHandler);
    player.on('timeUpdate', timeUpdateHandler);
    player.on('error', errorHandler);

    this.activeSegmentPlayer = player;
    this.activeSegmentFile = file;
    this.activeSegmentPath = segment.filePath;
    this.activeSegmentIndex = segment.index;

    try {
      player.fdSrc = {
        fd: file.fd,
        offset: 0,
        length: stat.size
      };
      logger.info(
        TAG,
        `远程TTS播放器绑定本地分片: index=${segment.index}, path=${segment.filePath}, bytes=${stat.size}, resumeChar=${this.currentCharIndex}`
      );
      await this.prepareSegmentPlayer(player, segment.index);
      const actualDurationMs = player.duration > 0 ? player.duration : segment.durationMs;
      this.applyActualSegmentDuration(segment, actualDurationMs);
      this.applyRemotePlayerVolume(player);

      const seekMs = this.computeSegmentSeekTimeMs(
        segment.index,
        range.start,
        range.end,
        segment.durationMs,
        resumeCharIndex
      );
      if (seekMs > 0) {
        await this.seekSegmentPlayer(player, seekMs);
        this.updateSegmentProgressByPlayerTime(range.start, range.end, segment.durationMs, seekMs);
      } else {
        this.syncRemoteProgressSnapshot(this.currentCharIndex, range.start, range.end, 0, segment.index);
      }
      allowProgressSync = true;

      if (!this.isSessionActive(sessionToken)) {
        return;
      }

      logger.info(
        TAG,
        `远程TTS播放器开始播放分片: index=${segment.index}, path=${segment.filePath}, durationMs=${segment.durationMs}, seekMs=${seekMs}`
      );
      await player.play();
      const playbackState = await this.waitForPlayerState(
        player,
        ['playing', 'completed'],
        1800,
        `index=${segment.index}_after_play`
      );
      logger.debug(TAG, `远程TTS播放器play完成首帧确认: index=${segment.index}, state=${playbackState}`);
      if (playbackState === 'playing' && this.isSessionActive(sessionToken)) {
        this.prefetchSegmentsSequentially(segment.index + 1, sessionToken);
      }
      await playbackPromise;
    } finally {
      player.off('stateChange', stateChangeHandler);
      player.off('timeUpdate', timeUpdateHandler);
      player.off('error', errorHandler);
      if (this.activeSegmentPlayer === player) {
        this.activeSegmentPlayer = null;
        this.activeSegmentFile = null;
        this.activeSegmentPath = '';
        this.activeSegmentIndex = -1;
      }
      try {
        if (player.state !== 'released') {
          await player.release();
        }
      } catch (_ignored) {
      }
      try {
        fs.closeSync(file);
      } catch (_ignored) {
      }
    }
  }

  private async stopActiveSegmentPlayer(reason: string): Promise<void> {
    const player = this.activeSegmentPlayer;
    const file = this.activeSegmentFile;
    const path = this.activeSegmentPath;
    const index = this.activeSegmentIndex;
    this.activeSegmentPlayer = null;
    this.activeSegmentFile = null;
    this.activeSegmentPath = '';
    this.activeSegmentIndex = -1;

    if (!player && !file) {
      return;
    }
    logger.debug(TAG, `远程TTS播放器停止: reason=${reason}, index=${index}, path=${path}`);
    if (player) {
      try {
        if (player.state !== 'released') {
          await player.release();
        }
      } catch (error) {
        logger.warn(TAG, `远程TTS播放器释放失败: reason=${reason}, index=${index}, error=${formatReadAloudError(error)}`);
      }
    }
    if (file) {
      try {
        fs.closeSync(file);
      } catch (_ignored) {
      }
    }
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

  private persistSessionTempSegment(
    index: number,
    range: QueueCharRange,
    synthesized: RemoteTtsSynthesizedSegment
  ): RemoteTtsPlayableSegment {
    const text = this.queue[index] ?? '';
    const paths = this.buildSegmentStoragePaths(index, true);
    const seekModel = buildRemoteTtsSeekModel(range.start, range.end, text);
    ensureDirExists(this.sessionTempDir);
    writeFileBytes(paths.audioPath, synthesized.bytes);
    const stat = fs.statSync(paths.audioPath);
    const segment: RemoteTtsPlayableSegment = {
      index,
      start: range.start,
      end: range.end,
      cacheKey: paths.cacheKey,
      textDigest: paths.textDigest,
      textLength: paths.textLength,
      textPreview: paths.textPreview,
      filePath: paths.audioPath,
      bytes: stat.size,
      durationMs: this.buildSegmentDurationMs(text, synthesized),
      seekTotalUnits: seekModel.totalUnits,
      seekAnchors: seekModel.anchors
    };
    logger.warn(TAG, `远程TTS已降级保存到会话临时目录: index=${index}, cacheKey=${paths.cacheKey}, path=${paths.audioPath}, bytes=${segment.bytes}`);
    return segment;
  }

  private ensureSegmentPlayableFile(segment: RemoteTtsPlayableSegment): void {
    if (segment.filePath.length > 0 && fs.accessSync(segment.filePath)) {
      return;
    }
    const inlineBytes = segment.inlineBytes;
    if (!inlineBytes || inlineBytes.length <= 0) {
      return;
    }
    const fallbackPaths = this.buildSegmentStoragePaths(segment.index, true);
    ensureDirExists(this.sessionTempDir);
    writeFileBytes(fallbackPaths.audioPath, inlineBytes);
    const stat = fs.statSync(fallbackPaths.audioPath);
    segment.filePath = fallbackPaths.audioPath;
    segment.bytes = stat.size;
    segment.inlineBytes = undefined;
    logger.warn(
      TAG,
      `远程TTS分片已从内存补落盘用于播放: index=${segment.index}, cacheKey=${fallbackPaths.cacheKey}, path=${segment.filePath}, bytes=${segment.bytes}`
    );
  }

  private persistSegmentWithFallback(
    index: number,
    range: QueueCharRange,
    synthesized: RemoteTtsSynthesizedSegment
  ): RemoteTtsPlayableSegment {
    const text = this.queue[index] ?? '';
    const cachePaths = this.buildSegmentStoragePaths(index);
    const seekModel = buildRemoteTtsSeekModel(range.start, range.end, text);
    if (this.remoteSettings.cacheAudioFiles) {
      try {
        ensureDirExists(this.segmentCacheDir);
        writeFileBytes(cachePaths.audioPath, synthesized.bytes);
        const stat = fs.statSync(cachePaths.audioPath);
        const segment: RemoteTtsPlayableSegment = {
          index,
          start: range.start,
          end: range.end,
          cacheKey: cachePaths.cacheKey,
          textDigest: cachePaths.textDigest,
          textLength: cachePaths.textLength,
          textPreview: cachePaths.textPreview,
          filePath: cachePaths.audioPath,
          bytes: stat.size,
          durationMs: this.buildSegmentDurationMs(text, synthesized),
          seekTotalUnits: seekModel.totalUnits,
          seekAnchors: seekModel.anchors
        };
        this.persistSegmentIndexRecord(segment);
        logger.info(TAG, `远程TTS分片已规范化缓存: index=${index}, cacheKey=${cachePaths.cacheKey}, path=${cachePaths.audioPath}, bytes=${segment.bytes}`);
        return segment;
      } catch (error) {
        logger.error(
          TAG,
          `远程TTS规范化缓存写入失败: index=${index}, cacheKey=${cachePaths.cacheKey}, target=${cachePaths.audioPath}, bytes=${synthesized.bytes.byteLength}, error=${formatReadAloudError(error)}`
        );
      }
    }

    try {
      return this.persistSessionTempSegment(index, range, synthesized);
    } catch (error) {
      const fallbackPaths = this.buildSegmentStoragePaths(index, true);
      logger.error(
        TAG,
        `远程TTS会话临时落盘失败，改用内存分片继续播放: index=${index}, cacheKey=${fallbackPaths.cacheKey}, target=${fallbackPaths.audioPath}, bytes=${synthesized.bytes.byteLength}, error=${formatReadAloudError(error)}`
      );
      return {
        index,
        start: range.start,
        end: range.end,
        cacheKey: fallbackPaths.cacheKey,
        textDigest: fallbackPaths.textDigest,
        textLength: fallbackPaths.textLength,
        textPreview: fallbackPaths.textPreview,
        filePath: '',
        bytes: synthesized.bytes.byteLength,
        durationMs: this.buildSegmentDurationMs(text, synthesized),
        seekTotalUnits: seekModel.totalUnits,
        seekAnchors: seekModel.anchors,
        inlineBytes: synthesized.bytes
      };
    }
  }

  private async ensureSegment(index: number, sessionToken: string): Promise<RemoteTtsPlayableSegment> {
    const existing = this.playableSegments.get(index);
    if (
      existing &&
      (
        (existing.filePath.length > 0 && fs.accessSync(existing.filePath)) ||
        (!!existing.inlineBytes && existing.inlineBytes.length > 0)
      )
    ) {
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
    const cachedSegment = this.tryLoadNormalizedCachedSegment(index, range);
    if (cachedSegment) {
      this.updateRemoteUiStatus('buffering', '已命中缓存音频', this.buildSegmentUiDetail(index));
      return cachedSegment;
    }
    const paths = this.buildSegmentStoragePaths(index);
    logger.debug(
      TAG,
      `远程TTS准备合成分片: index=${index}, chars=${text.length}, cacheKey=${paths.cacheKey}, cacheAudioFiles=${this.remoteSettings.cacheAudioFiles}`
    );
    this.updateRemoteUiStatus('requesting', '正在请求远程语音', this.buildSegmentUiDetail(index, `${text.length} 字`));
    const synthesized = await this.requestRemoteAudio(text);
    const segment = this.persistSegmentWithFallback(index, range, synthesized);
    this.updateRemoteUiStatus('buffering', '音频分片已就绪', this.buildSegmentUiDetail(index, `${segment.bytes} bytes`));
    this.updateManifestSegment(segment);
    return segment;
  }

  private async requestRemoteAudio(text: string): Promise<RemoteTtsSynthesizedSegment> {
    const requestUrl = this.buildRemoteRequestUrl();
    const requestHeaders = this.buildRemoteRequestHeaders();
    const payload = this.buildRemoteRequestBody(text);
    const stylePrompt = this.remoteSettings.stylePrompt.trim();
    logger.debug(
      TAG,
      `远程TTS发起请求: url=${requestUrl}, chars=${text.length}, style=${stylePrompt.length > 0 ? stylePrompt : 'none'}, stream=${this.remoteSettings.streamEnabled}, audioFormat=${this.remoteSettings.audioFormat}, cacheAudioFiles=${this.remoteSettings.cacheAudioFiles}`
    );
    try {
      const response = await this.requestRemoteHttp(
        requestUrl,
        http.RequestMethod.POST,
        payload,
        requestHeaders,
        true,
        this.shouldUseChatCompletionsPayload()
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
    } catch (error) {
      this.updateRemoteUiStatus('error', '远程语音请求失败', this.buildReadableRemoteErrorText(error));
      logger.error(TAG, `远程TTS请求失败: url=${requestUrl}, chars=${text.length}, error=${formatReadAloudError(error)}`);
      throw error as Error;
    }
  }

  private buildRemoteRequestUrl(): string {
    const endpoint = this.remoteSettings.endpoint.trim().replace(/\/+$/, '');
    const apiPathRaw = this.remoteSettings.apiPath.trim();
    if (apiPathRaw.startsWith('http://') || apiPathRaw.startsWith('https://')) {
      return apiPathRaw;
    }
    const defaultApiPath = this.shouldUseChatCompletionsPayload() ? '/v1/chat/completions' : '/v1/audio/speech';
    const apiPath = apiPathRaw.length > 0
      ? (apiPathRaw.startsWith('/') ? apiPathRaw : `/${apiPathRaw}`)
      : defaultApiPath;
    return `${endpoint}${apiPath}`;
  }

  private buildRemoteRequestBody(text: string): string {
    const requestText = this.buildRemoteInputText(text);
    const normalizedFormat = normalizeAudioExtension(this.remoteSettings.audioFormat);
    const payload: RemoteJsonRecord = {};
    if (this.shouldUseChatCompletionsPayload()) {
      const messages: RemoteChatCompletionMessagePayload[] = [{
        role: 'assistant',
        content: requestText
      }];
      const audio: RemoteChatCompletionAudioPayload = {
        format: this.remoteSettings.streamEnabled ? 'pcm16' : normalizedFormat,
        voice: this.remoteSettings.voice.trim()
      };
      payload['model'] = this.remoteSettings.model.trim();
      payload['messages'] = messages;
      payload['audio'] = audio;
      payload['stream'] = this.remoteSettings.streamEnabled;
    } else {
      payload['model'] = this.remoteSettings.model.trim();
      payload['voice'] = this.remoteSettings.voice.trim();
      payload['input'] = requestText;
      payload['response_format'] = normalizedFormat;
      payload['stream'] = this.remoteSettings.streamEnabled;
    }

    const extra = this.parseJsonRecord(this.remoteSettings.extraBodyJson);
    if (extra) {
      const keys = Object.keys(extra);
      for (const key of keys) {
        const value = extra[key];
        if (value === undefined || value === null) {
          continue;
        }
        payload[key] = value;
      }
    }
    return JSON.stringify(payload);
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
    if (apiKey.length > 0 && !this.hasAnyHeaderIgnoreCase(headers, ['Authorization', 'api-key'])) {
      const authHeaderName = this.resolveRemoteApiKeyHeaderName();
      headers[authHeaderName] = authHeaderName.toLowerCase() === 'authorization'
        ? `Bearer ${apiKey}`
        : apiKey;
    }
    return headers;
  }

  private shouldUseChatCompletionsPayload(): boolean {
    const apiPath = this.remoteSettings.apiPath.trim().toLowerCase();
    const endpoint = this.remoteSettings.endpoint.trim().toLowerCase();
    const model = this.remoteSettings.model.trim().toLowerCase();
    return apiPath.includes('/chat/completions') ||
      endpoint.includes('xiaomimimo.com') ||
      model === 'mimo-v2-tts';
  }

  private resolveRemoteApiKeyHeaderName(): string {
    const endpoint = this.remoteSettings.endpoint.trim().toLowerCase();
    const model = this.remoteSettings.model.trim().toLowerCase();
    if (endpoint.includes('xiaomimimo.com') || model === 'mimo-v2-tts') {
      return 'api-key';
    }
    return 'Authorization';
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

  private hasAnyHeaderIgnoreCase(headers: Record<string, string>, keys: string[]): boolean {
    for (const key of keys) {
      if (this.hasHeaderIgnoreCase(headers, key)) {
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
    expectArrayBuffer: boolean,
    allowStringRetryOnReceiveError: boolean = false
  ): Promise<RemoteTtsHttpResult> {
    try {
      return await this.performRemoteHttpRequest(url, method, body, headers, expectArrayBuffer);
    } catch (error) {
      const retryableReceiveError = isRemoteArrayBufferRetryableError(error);
      if (
        retryableReceiveError &&
        expectArrayBuffer &&
        allowStringRetryOnReceiveError
      ) {
        this.updateRemoteUiStatus('retrying', '二进制接收失败，正在切换文本响应重试', '兼容 chat/completions JSON 响应');
        logger.warn(
          TAG,
          `远程TTS二进制接收失败，改用文本响应重试: url=${url}, method=${method}, error=${formatReadAloudError(error)}`
        );
        return await this.performRemoteHttpRequest(url, method, body, headers, false);
      }
      throw error as Error;
    }
  }

  private async performRemoteHttpRequest(
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
        maxLimit: REMOTE_TTS_HTTP_MAX_LIMIT_BYTES,
        connectTimeout: this.remoteSettings.connectTimeoutMs,
        readTimeout: this.remoteSettings.readTimeoutMs
      });
      const normalizedHeaders = this.normalizeHeaders(response.header);
      const receivedBytes = typeof response.result === 'string'
        ? response.result.length
        : (response.result as ArrayBuffer).byteLength;
      logger.debug(
        TAG,
        `远程TTS响应接收完成: url=${url}, statusCode=${response.responseCode}, receiveType=${expectArrayBuffer ? 'ARRAY_BUFFER' : 'STRING'}, maxLimit=${REMOTE_TTS_HTTP_MAX_LIMIT_BYTES}, contentLength=${this.getHeaderValue(normalizedHeaders, 'content-length') || 'unknown'}, receivedBytes=${receivedBytes}`
      );
      return {
        statusCode: response.responseCode,
        headers: normalizedHeaders,
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
