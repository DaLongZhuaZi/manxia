import { SafeFileUtils } from 'manxia_core/src/main/ets/Utils/SafeFileUtils';
import { SafeUtils } from 'manxia_core/src/main/ets/Utils/SafeUtils';
import fs from '@ohos.file.fs';
import { util } from '@kit.ArkTS';
import { preferences } from '@kit.ArkData';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { uiContextManager } from 'manxia_theme/src/main/ets/Framework/Managers/UIContextManager';
import {
  ChapterOrderCacheRemapResult,
  ChapterOrderIndexRemap,
  UnifiedChapter,
  UnifiedContent,
  UnifiedContentType
} from 'manxia_core/src/main/ets/Models/UnifiedContentModels';
import {
  DEFAULT_REMOTE_READ_ALOUD_SETTINGS,
  DEFAULT_TEXT_READER_SETTINGS,
  ReadAloudEngineType,
  ReadAloudSettings,
  RemoteReadAloudSettings,
  TextReaderSettings,
  mergeRemoteReadAloudSettings,
  normalizeReadAloudSettings
} from 'manxia_core/src/main/ets/Models/TextReaderModels';
import { SettingKeys, SettingsManager } from 'manxia_core/src/main/ets/Framework/Managers/SettingsManager';
import { loadGlobalReadAloudSettings, persistGlobalReadAloudSettings } from './ReadAloudSettingsStore';
import { ReadAloudBackendFactory, ReadAloudPrecacheProgressSnapshot } from './ReadAloudBackends';
import { ReadAloudController } from './ReadAloudController';
import { ReadAloudSessionContext } from './ReadAloudTypes';
import { getNovelSourceManager } from '../Novel/NovelSourceManager';
import { getNovelChapterCacheManager } from '../Novel/NovelChapterCacheManager';
import { getNovelContentProcessor, ContentProcessConfig } from '../Novel/NovelContentProcessor';
import { LegadoChapter } from 'manxia_novel/src/main/ets/Framework/Novel/LegadoSourceTypes';
import { EBook, EBookFormat } from 'manxia_core/src/main/ets/Models/EBookModels';
import { EBookDataManager } from 'manxia_core/src/main/ets/Framework/Data/EBookDataManager';
import { EBookAdapter, NovelAdapter } from '../Adapters/UnifiedContentAdapter';
import { processReadAloudNovelContentByBook } from './ReadAloudTextProcessing';
import {
  buildLocalTextNovelBookId,
  buildNovelReaderParamsFromTxtEBook,
  LOCAL_TXT_NOVEL_SOURCE_ID
} from '../Adapters/LocalTextNovelAdapter';
import { eventBus, GameEvent, ReadAloudCacheUpdatedPayload } from '../EventBus';

const TAG = 'RemoteReadAloudCacheService';
const NOVEL_BOOK_REPLACE_RULE_IDS_PREFIX = 'book_replace_rule_ids_';
const NOVEL_BOOK_RULE_SETTINGS_STORE = 'novel_book_rule_settings';
const REMOTE_READ_ALOUD_CACHE_ROOT_DIR = 'read_aloud_remote';
const REMOTE_TTS_MANIFEST_VERSION = 2;
const REMOTE_TTS_TEXT_PREVIEW_LIMIT = 48;

interface RemoteTtsManifestSegmentSeekAnchorRecord {
  charIndex?: number;
  unitOffset?: number;
  kind?: string;
}

interface RemoteTtsManifestSegmentRecord {
  index?: number;
  start?: number;
  end?: number;
  cacheKey?: string;
  textDigest?: string;
  textLength?: number;
  textPreview?: string;
  filePath: string;
  bytes: number;
  durationMs?: number;
  seekTotalUnits?: number;
  seekAnchors?: RemoteTtsManifestSegmentSeekAnchorRecord[];
  manualMatchedAt?: number;
  manualMatchSourceManifestPath?: string;
  manualMatchSourceCacheKey?: string;
  manualMatchSourceSegmentIndex?: number;
}

interface RemoteTtsManifestRecord {
  version: number;
  updatedAt: number;
  bookId: string;
  chapterIndex: number;
  contentDigest?: string;
  remoteDigest?: string;
  audioFormat?: string;
  mergedFilePath?: string;
  segments: RemoteTtsManifestSegmentRecord[];
}

interface RemoteReadAloudChapterDirMove {
  stableKey: string;
  sourcePath: string;
  tempPath: string;
  targetPath: string;
  newIndex: number;
}

interface RemoteReadAloudBookIdentity {
  supported: boolean;
  isLocalTxtEBook: boolean;
  bookId: string;
  bookTitle: string;
  coverUrl: string;
  sourceId: string;
  bookUrl: string;
  chapterCount: number;
  chapters: UnifiedChapter[];
  localEbookId: string;
}

interface RemoteReadAloudManifestDescriptor {
  path: string;
  chapterIndex: number;
  updatedAt: number;
  contentDigest: string;
  remoteDigest: string;
  audioFormat: string;
  mergedFilePath: string;
  mergedFileBytes: number;
  segmentCount: number;
  segmentPaths: string[];
  manifest: RemoteTtsManifestRecord;
  segments: RemoteReadAloudCacheSegmentSummary[];
  textChars: number;
}

interface RemoteReadAloudAllReferenceSnapshot {
  segmentAudioPaths: Set<string>;
  segmentMetaPaths: Set<string>;
}

interface RemoteReadAloudExpectedSegmentRecord {
  segmentIndex: number;
  startCharIndex: number;
  endCharIndex: number;
  textLength: number;
  textPreview: string;
  cacheKey: string;
  textDigest: string;
}

interface RemoteReadAloudCacheTargetSuggestionCandidate {
  targetSegmentIndex: number;
  score: number;
  reason: RemoteReadAloudCacheTargetMatchReason;
  segmentIndexDistance: number;
  startDistance: number;
}

interface RemoteReadAloudChunkRange {
  start: number;
  end: number;
}

export interface RemoteReadAloudCacheChapterSummary {
  chapterIndex: number;
  chapterTitle: string;
  cached: boolean;
  variantCount: number;
  manifestCount: number;
  segmentCount: number;
  totalBytes: number;
  mergedAudioBytes: number;
  lastUpdatedAt: number;
  currentSegmentCount: number;
  currentTotalBytes: number;
  currentMergedAudioBytes: number;
  currentLastUpdatedAt: number;
  currentTextChars: number;
  currentSegments: RemoteReadAloudCacheSegmentSummary[];
  displayTextChars: number;
  displaySegments: RemoteReadAloudCacheSegmentSummary[];
  displaySegmentsSource: 'current' | 'history' | 'none';
}

export interface RemoteReadAloudCacheSegmentSummary {
  segmentIndex: number;
  startCharIndex: number;
  endCharIndex: number;
  textLength: number;
  textPreview: string;
  bytes: number;
  durationMs: number;
  anchorCount: number;
  cacheKey?: string;
  textDigest?: string;
  filePath?: string;
  metaPath?: string;
  manifestPath?: string;
  contentDigest?: string;
  remoteDigest?: string;
  audioFormat?: string;
  updatedAt?: number;
  isCurrentConfigMatch?: boolean;
  isCurrentTextMatch?: boolean;
  isCurrentManifest?: boolean;
  matchMode?: 'exact' | 'manual' | 'history' | 'current_unmatched';
  manualMatchedAt?: number;
  manualMatchSourceManifestPath?: string;
  manualMatchSourceCacheKey?: string;
  manualMatchSourceSegmentIndex?: number;
}

export type RemoteReadAloudCacheTargetMatchReason =
  'exact_digest' |
  'cache_key' |
  'range_overlap' |
  'preview_similarity' |
  'length_similarity' |
  'segment_index' |
  'weak';

export interface RemoteReadAloudCacheTargetSuggestion {
  targetSegmentIndex: number;
  score: number;
  reason: RemoteReadAloudCacheTargetMatchReason;
}

export interface RemoteReadAloudCacheSegmentDetail extends RemoteReadAloudCacheSegmentSummary {
  suggestedTarget: RemoteReadAloudCacheTargetSuggestion | null;
  suggestedTargets: RemoteReadAloudCacheTargetSuggestion[];
}

export interface RemoteReadAloudCacheTargetSegment {
  segmentIndex: number;
  startCharIndex: number;
  endCharIndex: number;
  textLength: number;
  textPreview: string;
  cacheKey: string;
  textDigest: string;
  matched: boolean;
  attachedSegment: RemoteReadAloudCacheSegmentDetail | null;
}

export interface RemoteReadAloudCacheCoverageSummary {
  totalTextChars: number;
  coveredTextChars: number;
  exactCoveredTextChars: number;
  manualCoveredTextChars: number;
  uncoveredTextChars: number;
  totalTargetCount: number;
  coveredTargetCount: number;
  exactCoveredTargetCount: number;
  manualCoveredTargetCount: number;
  uncoveredTargetCount: number;
}

export interface RemoteReadAloudCacheManifestSummary {
  manifestPath: string;
  chapterIndex: number;
  updatedAt: number;
  contentDigest: string;
  remoteDigest: string;
  audioFormat: string;
  mergedFilePath: string;
  mergedFileBytes: number;
  segmentCount: number;
  textChars: number;
  isCurrentConfigMatch: boolean;
  isCurrentTextMatch: boolean;
  isCurrentManifest: boolean;
  isLatestVariant: boolean;
  segments: RemoteReadAloudCacheSegmentDetail[];
}

export interface RemoteReadAloudCacheChapterDetail {
  chapterIndex: number;
  chapterTitle: string;
  currentContentDigest: string;
  currentRemoteDigest: string;
  currentManifestPath: string;
  currentManifestExists: boolean;
  coverage: RemoteReadAloudCacheCoverageSummary;
  targetSegments: RemoteReadAloudCacheTargetSegment[];
  currentExactMatchedCount: number;
  sourceSegments: RemoteReadAloudCacheSegmentDetail[];
  unmatchedCurrentSegments: RemoteReadAloudCacheSegmentDetail[];
  manifests: RemoteReadAloudCacheManifestSummary[];
}

export interface RemoteReadAloudCurrentCacheSummary {
  cachedChapterCount: number;
  totalSegments: number;
  totalBytes: number;
  mergedAudioCount: number;
  latestUpdatedAt: number;
}

export interface RemoteReadAloudCacheBookSummary {
  supported: boolean;
  bookId: string;
  bookRootPath: string;
  chapterCount: number;
  cachedChapterCount: number;
  historicalCachedChapterCount: number;
  totalSegments: number;
  variantCount: number;
  segmentBytes: number;
  bookDirBytes: number;
  totalBytes: number;
  mergedAudioCount: number;
  latestUpdatedAt: number;
  chapters: RemoteReadAloudCacheChapterSummary[];
  currentSettings: RemoteReadAloudCurrentCacheSummary;
  currentRemoteDigest: string;
  settings: RemoteReadAloudSettings;
  settingsSource: 'active_session' | 'book' | 'global';
  settingsSourceLabel: string;
}

export interface RemoteReadAloudCacheTaskProgress {
  chapterIndex: number;
  chapterTitle: string;
  chapterOrder: number;
  chapterTotal: number;
  totalCachedBytes: number;
  segmentProgress: ReadAloudPrecacheProgressSnapshot;
}

export interface RemoteReadAloudPrecacheOptions {
  remoteOverrides?: Partial<RemoteReadAloudSettings> | null;
  onProgress?: (progress: RemoteReadAloudCacheTaskProgress) => void;
}

interface RemoteReadAloudEffectiveSettingsSnapshot {
  readAloudSettings: ReadAloudSettings;
  remoteSettings: RemoteReadAloudSettings;
  source: 'active_session' | 'book' | 'global';
  sourceLabel: string;
}

function sanitizePathPart(raw: string): string {
  if (!raw || raw.length <= 0) {
    return 'unknown';
  }
  return raw.replace(/[^a-zA-Z0-9_.-]/g, '_');
}

function readFileBytes(path: string): Uint8Array {
  const stat = SafeFileUtils.statSync(path);
  const file = SafeFileUtils.openSync(path, fs.OpenMode.READ_ONLY);
  try {
    const buffer = new ArrayBuffer(stat.size);
    SafeFileUtils.readSync(file.fd, buffer);
    return new Uint8Array(buffer);
  } finally {
    SafeFileUtils.closeSync(file);
  }
}

function safeReadJson<T>(path: string): T | null {
  if (!path || !SafeFileUtils.accessSync(path)) {
    return null;
  }
  try {
    const text = new util.TextDecoder('utf-8').decodeToString(readFileBytes(path));
    return SafeUtils.parseObj(text) as T;
  } catch (error) {
    logger.warn(TAG, `读取 JSON 失败: path=${path}, error=${String(error)}`);
    return null;
  }
}

function fnv1aHashHex(input: string): string {
  let hash = 0x811c9dc5;
  for (let index = 0; index < input.length; index++) {
    hash ^= input.charCodeAt(index);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash.toString(16).padStart(8, '0');
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
  if (SafeFileUtils.accessSync(path)) {
    const stat = SafeFileUtils.statSync(path);
    if (!stat.isDirectory()) {
      throw new Error(`READ_ALOUD_CACHE_PATH_IS_NOT_DIRECTORY: ${path}`);
    }
    return;
  }
  SafeFileUtils.mkdirSync(path, true);
}

function writeFileBytes(path: string, bytes: Uint8Array): void {
  const parentDir = dirname(path);
  if (parentDir.length > 0) {
    ensureDirExists(parentDir);
  }
  const tempPath = `${path}.tmp_${Date.now()}_${Math.floor(Math.random() * 1000)}`;
  try {
    const file = SafeFileUtils.openSync(tempPath, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
    try {
      const buffer = bytes.byteOffset === 0 && bytes.byteLength === bytes.buffer.byteLength
        ? bytes.buffer
        : bytes.slice().buffer;
      if (bytes.byteLength > 0) {
        SafeFileUtils.writeSync(file.fd, buffer);
      }
    } finally {
      SafeFileUtils.closeSync(file);
    }
    deleteFileIfExists(path);
    SafeFileUtils.renameSync(tempPath, path);
  } catch (error) {
    deleteFileIfExists(tempPath);
    throw error as Error;
  }
}

function writeJsonFile(path: string, value: Object): void {
  const bytes = new util.TextEncoder().encodeInto(JSON.stringify(value));
  writeFileBytes(path, new Uint8Array(bytes));
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

function isRemoteTtsBreakChar(char: string): boolean {
  return char === '\n' ||
    char === '\r' ||
    char === '.' ||
    char === '!' ||
    char === '?' ||
    char === ',' ||
    char === ';' ||
    char === ':' ||
    char === '\u2026' ||
    char === '\u3002' ||
    char === '\u3001' ||
    char === '\uff01' ||
    char === '\uff1f' ||
    char === '\uff0c' ||
    char === '\uff1b' ||
    char === '\uff1a';
}

function buildSegmentMetaPath(filePath: string): string {
  const dotIndex = filePath.lastIndexOf('.');
  return dotIndex > 0 ? `${filePath.substring(0, dotIndex)}.json` : `${filePath}.json`;
}

function safeStatSize(path: string): number {
  try {
    if (!path || !SafeFileUtils.accessSync(path)) {
      return 0;
    }
    const stat = SafeFileUtils.statSync(path);
    return stat.isFile() ? stat.size : 0;
  } catch (_error) {
    return 0;
  }
}

function sumDirectoryBytes(path: string): number {
  try {
    if (!path || !SafeFileUtils.accessSync(path)) {
      return 0;
    }
    const stat = SafeFileUtils.statSync(path);
    if (stat.isFile()) {
      return stat.size;
    }
    let total = 0;
    const children = SafeFileUtils.listFileSync(path);
    for (let index = 0; index < children.length; index++) {
      total += sumDirectoryBytes(`${path}/${children[index]}`);
    }
    return total;
  } catch (_error) {
    return 0;
  }
}

function deleteDirRecursive(path: string): void {
  try {
    if (!path || !SafeFileUtils.accessSync(path)) {
      return;
    }
    const stat = SafeFileUtils.statSync(path);
    if (stat.isFile()) {
      SafeFileUtils.unlinkSync(path);
      return;
    }
    const children = SafeFileUtils.listFileSync(path);
    for (let index = 0; index < children.length; index++) {
      deleteDirRecursive(`${path}/${children[index]}`);
    }
    SafeFileUtils.rmdirSync(path);
  } catch (error) {
    logger.warn(TAG, `删除目录失败: path=${path}, error=${String(error)}`);
  }
}

function deleteFileIfExists(path: string): void {
  try {
    if (path && SafeFileUtils.accessSync(path)) {
      SafeFileUtils.unlinkSync(path);
    }
  } catch (error) {
    logger.warn(TAG, `删除文件失败: path=${path}, error=${String(error)}`);
  }
}

function cleanupEmptyParentDirs(path: string, stopPath: string): void {
  let current = path;
  while (current.length > 0 && current.startsWith(stopPath) && current !== stopPath) {
    try {
      if (!SafeFileUtils.accessSync(current)) {
        const nextSlash = current.lastIndexOf('/');
        if (nextSlash <= 0) {
          return;
        }
        current = current.substring(0, nextSlash);
        continue;
      }
      const stat = SafeFileUtils.statSync(current);
      if (!stat.isDirectory()) {
        return;
      }
      const children = SafeFileUtils.listFileSync(current);
      if (children.length > 0) {
        return;
      }
      SafeFileUtils.rmdirSync(current);
    } catch (_error) {
      return;
    }
    const slashIndex = current.lastIndexOf('/');
    if (slashIndex <= 0) {
      return;
    }
    current = current.substring(0, slashIndex);
  }
}

export class RemoteReadAloudCacheService {
  private static instance: RemoteReadAloudCacheService | null = null;

  private readonly settingsManager: SettingsManager = SettingsManager.getInstance();
  private readonly readAloudController: ReadAloudController = ReadAloudController.getInstance();
  private readonly novelSourceManager = getNovelSourceManager();
  private readonly novelChapterCacheManager = getNovelChapterCacheManager();
  private readonly ebookDataManager = EBookDataManager.getInstance();

  static getInstance(): RemoteReadAloudCacheService {
    if (!RemoteReadAloudCacheService.instance) {
      RemoteReadAloudCacheService.instance = new RemoteReadAloudCacheService();
    }
    return RemoteReadAloudCacheService.instance;
  }

  getCurrentRemoteSettings(): RemoteReadAloudSettings {
    const globalSettings = loadGlobalReadAloudSettings(this.settingsManager);
    return globalSettings.remote ?? DEFAULT_REMOTE_READ_ALOUD_SETTINGS;
  }

  getEffectiveRemoteSettingsForContent(content: UnifiedContent | null): RemoteReadAloudSettings {
    return this.resolveEffectiveReadAloudSettings(content).remoteSettings;
  }

  supportsContent(content: UnifiedContent | null): boolean {
    return this.resolveBookIdentity(content).supported;
  }

  remapChapterIndexCaches(bookIds: string[], remaps: ChapterOrderIndexRemap[]): ChapterOrderCacheRemapResult {
    const result: ChapterOrderCacheRemapResult = {
      textCacheMoved: 0,
      audioCacheMoved: 0,
      remoteReadAloudCacheMoved: 0,
      failedKeys: [],
      warnings: []
    };
    const normalizedBookIds = this.normalizeBookIdList(bookIds);
    for (let index = 0; index < normalizedBookIds.length; index++) {
      this.remapBookChapterCache(normalizedBookIds[index], remaps, result);
    }
    return result;
  }

  private normalizeBookIdList(bookIds: string[]): string[] {
    const result: string[] = [];
    for (let index = 0; index < bookIds.length; index++) {
      const bookId = bookIds[index].trim();
      if (bookId.length <= 0) {
        continue;
      }
      if (!result.includes(bookId)) {
        result.push(bookId);
      }
    }
    return result;
  }

  private remapBookChapterCache(
    bookId: string,
    remaps: ChapterOrderIndexRemap[],
    result: ChapterOrderCacheRemapResult
  ): void {
    const bookRootPath = this.buildBookRootPath(bookId);
    if (!SafeFileUtils.accessSync(bookRootPath)) {
      return;
    }
    const tempMoves: RemoteReadAloudChapterDirMove[] = [];
    const now = Date.now();
    for (let index = 0; index < remaps.length; index++) {
      const remap = remaps[index];
      if (remap.oldIndex === remap.newIndex) {
        continue;
      }
      const sourcePath = `${bookRootPath}/chapter_${remap.oldIndex}`;
      if (!SafeFileUtils.accessSync(sourcePath)) {
        continue;
      }
      const tempPath = `${sourcePath}.order_tmp_${now}_${index}`;
      const targetPath = `${bookRootPath}/chapter_${remap.newIndex}`;
      try {
        SafeFileUtils.renameSyncStrict(sourcePath, tempPath);
        tempMoves.push({
          stableKey: remap.stableKey,
          sourcePath,
          tempPath,
          targetPath,
          newIndex: remap.newIndex
        } as RemoteReadAloudChapterDirMove);
      } catch (error) {
        this.appendUniqueFailure(result, remap.stableKey);
        result.warnings.push(`远程听书缓存临时迁移失败: ${remap.title}, ${String(error)}`);
      }
    }

    for (let index = 0; index < tempMoves.length; index++) {
      const move = tempMoves[index];
      try {
        if (SafeFileUtils.accessSync(move.targetPath)) {
          deleteDirRecursive(move.targetPath);
        }
        SafeFileUtils.renameSyncStrict(move.tempPath, move.targetPath);
        this.rewriteManifestChapterIndex(move.targetPath, move.sourcePath, move.targetPath, move.newIndex, result, move.stableKey);
        result.remoteReadAloudCacheMoved++;
      } catch (error) {
        this.appendUniqueFailure(result, move.stableKey);
        result.warnings.push(`远程听书缓存落位失败: ${move.sourcePath} -> ${move.targetPath}, ${String(error)}`);
      }
    }
  }

  private rewriteManifestChapterIndex(
    path: string,
    oldChapterRoot: string,
    newChapterRoot: string,
    newIndex: number,
    result: ChapterOrderCacheRemapResult,
    stableKey: string
  ): void {
    if (!SafeFileUtils.accessSync(path)) {
      return;
    }
    const stat = SafeFileUtils.statSync(path);
    if (stat.isFile()) {
      if (!path.endsWith('/manifest.json') && !path.endsWith('\\manifest.json')) {
        return;
      }
      const manifest = safeReadJson<RemoteTtsManifestRecord>(path);
      if (!manifest || !Array.isArray(manifest.segments)) {
        this.appendUniqueFailure(result, stableKey);
        result.warnings.push(`远程听书清单损坏，已跳过重写: ${path}`);
        return;
      }
      manifest.chapterIndex = newIndex;
      manifest.updatedAt = Date.now();
      if (manifest.mergedFilePath && manifest.mergedFilePath.length > 0) {
        manifest.mergedFilePath = this.replaceMovedChapterPath(manifest.mergedFilePath, oldChapterRoot, newChapterRoot);
      }
      for (let index = 0; index < manifest.segments.length; index++) {
        const segment = manifest.segments[index];
        if (segment.filePath && segment.filePath.length > 0) {
          segment.filePath = this.replaceMovedChapterPath(segment.filePath, oldChapterRoot, newChapterRoot);
        }
      }
      writeJsonFile(path, manifest as Object);
      return;
    }
    const children = SafeFileUtils.listFileSync(path);
    for (let index = 0; index < children.length; index++) {
      this.rewriteManifestChapterIndex(`${path}/${children[index]}`, oldChapterRoot, newChapterRoot, newIndex, result, stableKey);
    }
  }

  private replaceMovedChapterPath(path: string, oldChapterRoot: string, newChapterRoot: string): string {
    if (path.startsWith(oldChapterRoot)) {
      return `${newChapterRoot}${path.substring(oldChapterRoot.length)}`;
    }
    return path;
  }

  private appendUniqueFailure(result: ChapterOrderCacheRemapResult, stableKey: string): void {
    if (!result.failedKeys.includes(stableKey)) {
      result.failedKeys.push(stableKey);
    }
  }

  async inspectBookCache(content: UnifiedContent | null): Promise<RemoteReadAloudCacheBookSummary> {
    const identity = this.resolveBookIdentity(content);
    const effectiveSettings = this.resolveEffectiveReadAloudSettings(content);
    const settings = effectiveSettings.remoteSettings;
    const currentRemoteDigest = this.buildRemoteDigest(settings);
    const emptyCurrentSettings: RemoteReadAloudCurrentCacheSummary = {
      cachedChapterCount: 0,
      totalSegments: 0,
      totalBytes: 0,
      mergedAudioCount: 0,
      latestUpdatedAt: 0
    };
    if (!identity.supported) {
      return {
        supported: false,
        bookId: '',
        bookRootPath: '',
        chapterCount: 0,
        cachedChapterCount: 0,
        historicalCachedChapterCount: 0,
        totalSegments: 0,
        variantCount: 0,
        segmentBytes: 0,
        bookDirBytes: 0,
        totalBytes: 0,
        mergedAudioCount: 0,
        latestUpdatedAt: 0,
        chapters: [],
        currentSettings: emptyCurrentSettings,
        currentRemoteDigest,
        settings,
        settingsSource: effectiveSettings.source,
        settingsSourceLabel: effectiveSettings.sourceLabel
      };
    }

    const bookRootPath = this.buildBookRootPath(identity.bookId);
    const chapters = this.buildEmptyChapterSummaries(identity.chapters);
    if (!SafeFileUtils.accessSync(bookRootPath)) {
      return {
        supported: true,
        bookId: identity.bookId,
        bookRootPath,
        chapterCount: identity.chapterCount,
        cachedChapterCount: 0,
        historicalCachedChapterCount: 0,
        totalSegments: 0,
        variantCount: 0,
        segmentBytes: 0,
        bookDirBytes: 0,
        totalBytes: 0,
        mergedAudioCount: 0,
        latestUpdatedAt: 0,
        chapters,
        currentSettings: emptyCurrentSettings,
        currentRemoteDigest,
        settings,
        settingsSource: effectiveSettings.source,
        settingsSourceLabel: effectiveSettings.sourceLabel
      };
    }

    const manifestDescriptors = this.collectManifestDescriptors(bookRootPath);
    const latestDescriptorByChapter = this.collectLatestDescriptorsByChapter(manifestDescriptors);
    const bookReferencedSegments = new Map<string, number>();
    const chapterReferencedSegments = new Map<number, Map<string, number>>();
    const chapterReferencedMergedFiles = new Map<number, Set<string>>();
    const chapterMergedAudioBytes = new Map<number, number>();
    let mergedAudioCount = 0;
    let latestUpdatedAt = 0;
    let totalSegments = 0;
    for (let index = 0; index < manifestDescriptors.length; index++) {
      const descriptor = manifestDescriptors[index];
      if (descriptor.chapterIndex < 0 || descriptor.chapterIndex >= chapters.length) {
        continue;
      }
      const chapterSummary = chapters[descriptor.chapterIndex];
      chapterSummary.variantCount += 1;
      chapterSummary.manifestCount += 1;
      chapterSummary.segmentCount = Math.max(chapterSummary.segmentCount, descriptor.segmentCount);
      chapterSummary.lastUpdatedAt = Math.max(chapterSummary.lastUpdatedAt, descriptor.updatedAt);
      latestUpdatedAt = Math.max(latestUpdatedAt, descriptor.updatedAt);
      totalSegments += descriptor.segmentCount;
      if (descriptor.mergedFileBytes > 0) {
        mergedAudioCount += 1;
      }
      let chapterSegments = chapterReferencedSegments.get(descriptor.chapterIndex);
      if (!chapterSegments) {
        chapterSegments = new Map<string, number>();
        chapterReferencedSegments.set(descriptor.chapterIndex, chapterSegments);
      }
      for (let segmentIndex = 0; segmentIndex < descriptor.segmentPaths.length; segmentIndex++) {
        const segmentPath = descriptor.segmentPaths[segmentIndex];
        if (!bookReferencedSegments.has(segmentPath)) {
          bookReferencedSegments.set(segmentPath, safeStatSize(segmentPath));
        }
        if (!chapterSegments.has(segmentPath)) {
          chapterSegments.set(segmentPath, safeStatSize(segmentPath));
        }
      }
      if (descriptor.mergedFilePath && descriptor.mergedFileBytes > 0) {
        let mergedFiles = chapterReferencedMergedFiles.get(descriptor.chapterIndex);
        if (!mergedFiles) {
          mergedFiles = new Set<string>();
          chapterReferencedMergedFiles.set(descriptor.chapterIndex, mergedFiles);
        }
        if (!mergedFiles.has(descriptor.mergedFilePath)) {
          mergedFiles.add(descriptor.mergedFilePath);
          chapterMergedAudioBytes.set(
            descriptor.chapterIndex,
            (chapterMergedAudioBytes.get(descriptor.chapterIndex) ?? 0) + descriptor.mergedFileBytes
          );
        }
      }
    }

    const segmentBytes = Array.from(bookReferencedSegments.values()).reduce((sum, value) => sum + value, 0);
    for (let index = 0; index < chapters.length; index++) {
      const chapterSegmentBytes = Array.from(chapterReferencedSegments.get(index)?.values() ?? [])
        .reduce((sum, value) => sum + value, 0);
      const mergedAudioBytes = chapterMergedAudioBytes.get(index) ?? 0;
      chapters[index].mergedAudioBytes = mergedAudioBytes;
      chapters[index].totalBytes = chapterSegmentBytes + mergedAudioBytes;
    }

    const currentDescriptorByChapter = this.collectCurrentSettingsDescriptors(manifestDescriptors, currentRemoteDigest);
    const currentReferencedSegments = new Map<string, number>();
    let currentTotalSegments = 0;
    let currentMergedAudioCount = 0;
    let currentLatestUpdatedAt = 0;
    let currentMergedAudioBytesTotal = 0;
    currentDescriptorByChapter.forEach((descriptor: RemoteReadAloudManifestDescriptor, chapterIndex: number) => {
      const chapterSummary = chapters[chapterIndex];
      if (!chapterSummary) {
        return;
      }
      let chapterSegmentBytes = 0;
      const seen = new Set<string>();
      for (let segmentIndex = 0; segmentIndex < descriptor.segmentPaths.length; segmentIndex++) {
        const segmentPath = descriptor.segmentPaths[segmentIndex];
        if (seen.has(segmentPath)) {
          continue;
        }
        seen.add(segmentPath);
        const bytes = safeStatSize(segmentPath);
        chapterSegmentBytes += bytes;
        if (!currentReferencedSegments.has(segmentPath)) {
          currentReferencedSegments.set(segmentPath, bytes);
        }
      }
      chapterSummary.cached = true;
      chapterSummary.currentSegmentCount = descriptor.segmentCount;
      chapterSummary.currentTotalBytes = chapterSegmentBytes + descriptor.mergedFileBytes;
      chapterSummary.currentMergedAudioBytes = descriptor.mergedFileBytes;
      chapterSummary.currentLastUpdatedAt = descriptor.updatedAt;
      chapterSummary.currentTextChars = descriptor.textChars;
      chapterSummary.currentSegments = descriptor.segments.slice();
      chapterSummary.displayTextChars = descriptor.textChars;
      chapterSummary.displaySegments = descriptor.segments.slice();
      chapterSummary.displaySegmentsSource = 'current';
      currentTotalSegments += descriptor.segmentCount;
      currentLatestUpdatedAt = Math.max(currentLatestUpdatedAt, descriptor.updatedAt);
      currentMergedAudioBytesTotal += descriptor.mergedFileBytes;
      if (descriptor.mergedFileBytes > 0) {
        currentMergedAudioCount += 1;
      }
    });

    latestDescriptorByChapter.forEach((descriptor: RemoteReadAloudManifestDescriptor, chapterIndex: number) => {
      const chapterSummary = chapters[chapterIndex];
      if (!chapterSummary || chapterSummary.displaySegmentsSource === 'current') {
        return;
      }
      chapterSummary.displayTextChars = descriptor.textChars;
      chapterSummary.displaySegments = descriptor.segments.slice();
      chapterSummary.displaySegmentsSource = descriptor.segments.length > 0 ? 'history' : 'none';
    });

    const currentSegmentBytes = Array.from(currentReferencedSegments.values()).reduce((sum, value) => sum + value, 0);
    const currentSettings: RemoteReadAloudCurrentCacheSummary = {
      cachedChapterCount: currentDescriptorByChapter.size,
      totalSegments: currentTotalSegments,
      totalBytes: currentSegmentBytes + currentMergedAudioBytesTotal,
      mergedAudioCount: currentMergedAudioCount,
      latestUpdatedAt: currentLatestUpdatedAt
    };

    const bookDirBytes = sumDirectoryBytes(bookRootPath);
    return {
      supported: true,
      bookId: identity.bookId,
      bookRootPath,
      chapterCount: identity.chapterCount,
      cachedChapterCount: currentSettings.cachedChapterCount,
      historicalCachedChapterCount: chapters.filter((item: RemoteReadAloudCacheChapterSummary) => item.variantCount > 0).length,
      totalSegments,
      variantCount: manifestDescriptors.length,
      segmentBytes,
      bookDirBytes,
      totalBytes: segmentBytes + bookDirBytes,
      mergedAudioCount,
      latestUpdatedAt,
      chapters,
      currentSettings,
      currentRemoteDigest,
      settings,
      settingsSource: effectiveSettings.source,
      settingsSourceLabel: effectiveSettings.sourceLabel
    };
  }

async clearBookCache(content: UnifiedContent | null): Promise<void> {
    const identity = this.resolveBookIdentity(content);
    if (!identity.supported) {
      return;
    }
    const bookRootPath = this.buildBookRootPath(identity.bookId);
    if (!SafeFileUtils.accessSync(bookRootPath)) {
      return;
    }
    const currentReferences = this.collectSegmentReferencesFromBookRoot(bookRootPath);
    deleteDirRecursive(bookRootPath);
    this.cleanupUnreferencedSharedSegments(currentReferences);
    logger.info(TAG, `已清理当前书籍远程听书缓存: bookId=${identity.bookId}`);
    eventBus.publish(
      GameEvent.READ_ALOUD_CACHE_UPDATED,
      new ReadAloudCacheUpdatedPayload(identity.bookId, -1, 'clear_book')
    );
  }

async clearChapterCache(content: UnifiedContent | null, chapterIndex: number): Promise<void> {
    const identity = this.resolveBookIdentity(content);
    if (!identity.supported) {
      return;
    }
    const chapterRootPath = `${this.buildBookRootPath(identity.bookId)}/chapter_${chapterIndex}`;
    if (!SafeFileUtils.accessSync(chapterRootPath)) {
      return;
    }
    const currentReferences = this.collectSegmentReferencesFromBookRoot(chapterRootPath);
    deleteDirRecursive(chapterRootPath);
    this.cleanupUnreferencedSharedSegments(currentReferences);
    logger.info(TAG, `已清理章节远程听书缓存: bookId=${identity.bookId}, chapterIndex=${chapterIndex}`);
    eventBus.publish(
      GameEvent.READ_ALOUD_CACHE_UPDATED,
      new ReadAloudCacheUpdatedPayload(identity.bookId, chapterIndex, 'clear_chapter')
    );
  }

  async precacheChapters(
    content: UnifiedContent | null,
    chapterIndexes: number[],
    options: RemoteReadAloudPrecacheOptions = {}
  ): Promise<void> {
    const identity = this.resolveBookIdentity(content);
    if (!identity.supported) {
      throw new Error('READ_ALOUD_CACHE_UNSUPPORTED_CONTENT');
    }
    if (chapterIndexes.length <= 0) {
      return;
    }

    const baseSettings = this.resolveEffectiveReadAloudSettings(content).readAloudSettings;
    const mergedRemote = mergeRemoteReadAloudSettings(
      baseSettings.remote ?? DEFAULT_REMOTE_READ_ALOUD_SETTINGS,
      options.remoteOverrides ?? {}
    );
    const effectiveSettings: ReadAloudSettings = normalizeReadAloudSettings({
      enabled: true,
      engineType: ReadAloudEngineType.REMOTE,
      speed: baseSettings.speed,
      pitch: baseSettings.pitch,
      volume: baseSettings.volume,
      continueInBackground: baseSettings.continueInBackground,
      autoPlayNextChapter: baseSettings.autoPlayNextChapter,
      pauseOnManualPageTurn: baseSettings.pauseOnManualPageTurn,
      voiceLanguage: baseSettings.voiceLanguage,
      voicePerson: baseSettings.voicePerson,
      voiceOnline: baseSettings.voiceOnline,
      remote: mergedRemote
    });

    const backend = ReadAloudBackendFactory.create(ReadAloudEngineType.REMOTE);
    backend.applySettings(effectiveSettings);
    let totalCachedBytes = 0;
    try {
      for (let order = 0; order < chapterIndexes.length; order++) {
        const chapterIndex = chapterIndexes[order];
        if (chapterIndex < 0 || chapterIndex >= identity.chapterCount) {
          continue;
        }
        const chapter = identity.chapters[chapterIndex];
        const chapterTitle = chapter?.title || `第 ${chapterIndex + 1} 章`;
        const chapterContent = await this.loadProcessedChapterContent(identity, chapterIndex);
        if (!chapterContent || chapterContent.trim().length <= 0) {
          throw new Error(`READ_ALOUD_CACHE_CHAPTER_EMPTY: chapterIndex=${chapterIndex}`);
        }
        const context: ReadAloudSessionContext = {
          bookId: identity.bookId,
          bookTitle: identity.bookTitle,
          chapterIndex,
          chapterTitle,
          coverUrl: identity.coverUrl,
          content: chapterContent,
          pageIndex: 0,
          resumeCharIndex: 0
        };
        backend.updateContext(context);
        const chapterBaseBytes = totalCachedBytes;
        let chapterCachedBytes = 0;
        await backend.precacheCurrentContext((segmentProgress: ReadAloudPrecacheProgressSnapshot): void => {
          chapterCachedBytes = Math.max(chapterCachedBytes, segmentProgress.totalBytes);
          options.onProgress?.({
            chapterIndex,
            chapterTitle,
            chapterOrder: order + 1,
            chapterTotal: chapterIndexes.length,
            totalCachedBytes: chapterBaseBytes + chapterCachedBytes,
            segmentProgress
          });
        });
        totalCachedBytes = chapterBaseBytes + chapterCachedBytes;
      }
    } finally {
      await backend.release();
    }
  }

  buildEditableRemoteSettings(
    content: UnifiedContent | null,
    overrides?: Partial<RemoteReadAloudSettings> | null
  ): RemoteReadAloudSettings {
    return mergeRemoteReadAloudSettings(this.getEffectiveRemoteSettingsForContent(content), overrides ?? {});
  }

  async inspectChapterCacheDetail(
    content: UnifiedContent | null,
    chapterIndex: number
  ): Promise<RemoteReadAloudCacheChapterDetail> {
    const identity = this.resolveBookIdentity(content);
    const effectiveSettings = this.resolveEffectiveReadAloudSettings(content);
    const remoteSettings = effectiveSettings.remoteSettings;
    const currentRemoteDigest = this.buildRemoteDigest(remoteSettings);
    const chapterTitle = identity.chapters[chapterIndex]?.title || `第 ${chapterIndex + 1} 章`;
    const emptyCoverage: RemoteReadAloudCacheCoverageSummary = this.buildCoverageSummary([]);
    const emptyDetail: RemoteReadAloudCacheChapterDetail = {
      chapterIndex,
      chapterTitle,
      currentContentDigest: '',
      currentRemoteDigest,
      currentManifestPath: '',
      currentManifestExists: false,
      coverage: emptyCoverage,
      targetSegments: [],
      currentExactMatchedCount: 0,
      sourceSegments: [],
      unmatchedCurrentSegments: [],
      manifests: []
    };
    if (!identity.supported || chapterIndex < 0 || chapterIndex >= identity.chapterCount) {
      return emptyDetail;
    }

    const chapterContent = await this.loadProcessedChapterContent(identity, chapterIndex);
    const currentContentDigest = fnv1aHashHex(chapterContent);
    const targetSegmentsRaw = this.buildExpectedSegments(chapterContent, remoteSettings);
    const currentManifestPath = this.buildChapterManifestPath(identity.bookId, chapterIndex, currentContentDigest, currentRemoteDigest);
    const chapterRootPath = `${this.buildBookRootPath(identity.bookId)}/chapter_${chapterIndex}`;
    const descriptors = SafeFileUtils.accessSync(chapterRootPath)
      ? this.collectManifestDescriptors(chapterRootPath)
          .filter((descriptor: RemoteReadAloudManifestDescriptor) => descriptor.chapterIndex === chapterIndex)
      : [];

    const latestUpdatedAt = descriptors.reduce(
      (maxValue: number, descriptor: RemoteReadAloudManifestDescriptor) => Math.max(maxValue, descriptor.updatedAt),
      0
    );
    const currentDescriptor = descriptors.find((descriptor: RemoteReadAloudManifestDescriptor) =>
      descriptor.path === currentManifestPath ||
      (
        descriptor.contentDigest === currentContentDigest &&
        descriptor.remoteDigest === currentRemoteDigest
      )
    ) ?? null;
    const currentSegmentsByIndex = new Map<number, RemoteTtsManifestSegmentRecord>();
    if (currentDescriptor) {
      currentDescriptor.manifest.segments.forEach((segment: RemoteTtsManifestSegmentRecord) => {
        currentSegmentsByIndex.set(Math.max(0, Math.floor(segment.index ?? 0)), segment);
      });
    }

    let currentExactMatchedCount = 0;
    const targetSegments: RemoteReadAloudCacheTargetSegment[] = targetSegmentsRaw.map((target: RemoteReadAloudExpectedSegmentRecord) => {
      const attachedRecord = currentSegmentsByIndex.get(target.segmentIndex) ?? null;
      if (attachedRecord && currentDescriptor && attachedRecord.cacheKey === target.cacheKey && attachedRecord.textDigest === target.textDigest) {
        currentExactMatchedCount += 1;
        const attachedSegment = this.buildSegmentDetailFromRecord(
          attachedRecord,
          currentDescriptor,
          currentRemoteDigest,
          currentContentDigest,
          attachedRecord.manualMatchSourceManifestPath && attachedRecord.manualMatchSourceManifestPath.length > 0 ? 'manual' : 'exact'
        );
        attachedSegment.isCurrentManifest = true;
        const matchedTarget: RemoteReadAloudCacheTargetSegment = {
          segmentIndex: target.segmentIndex,
          startCharIndex: target.startCharIndex,
          endCharIndex: target.endCharIndex,
          textLength: target.textLength,
          textPreview: target.textPreview,
          cacheKey: target.cacheKey,
          textDigest: target.textDigest,
          matched: true,
          attachedSegment
        };
        return matchedTarget;
      }
      const unmatchedTarget: RemoteReadAloudCacheTargetSegment = {
        segmentIndex: target.segmentIndex,
        startCharIndex: target.startCharIndex,
        endCharIndex: target.endCharIndex,
        textLength: target.textLength,
        textPreview: target.textPreview,
        cacheKey: target.cacheKey,
        textDigest: target.textDigest,
        matched: false,
        attachedSegment: null
      };
      return unmatchedTarget;
    });

    const unmatchedCurrentSegments: RemoteReadAloudCacheSegmentDetail[] = [];
    if (currentDescriptor) {
      currentDescriptor.manifest.segments.forEach((segment: RemoteTtsManifestSegmentRecord) => {
        const safeIndex = Math.max(0, Math.floor(segment.index ?? 0));
        const target = targetSegmentsRaw.find((item: RemoteReadAloudExpectedSegmentRecord) => item.segmentIndex === safeIndex);
        if (target && segment.cacheKey === target.cacheKey && segment.textDigest === target.textDigest) {
          return;
        }
        const detail = this.buildSegmentDetailFromRecord(
          segment,
          currentDescriptor,
          currentRemoteDigest,
          currentContentDigest,
          'current_unmatched'
        );
        detail.isCurrentManifest = true;
        unmatchedCurrentSegments.push(detail);
      });
    }

    const manifests = descriptors
      .sort((left: RemoteReadAloudManifestDescriptor, right: RemoteReadAloudManifestDescriptor) => {
        if (left.updatedAt !== right.updatedAt) {
          return right.updatedAt - left.updatedAt;
        }
        return left.path.localeCompare(right.path);
      })
      .map((descriptor: RemoteReadAloudManifestDescriptor) => this.buildManifestSummary(
        descriptor,
        currentRemoteDigest,
        currentContentDigest,
        descriptor.path === currentManifestPath,
        descriptor.updatedAt === latestUpdatedAt
      ));

    const sourceSegments: RemoteReadAloudCacheSegmentDetail[] = unmatchedCurrentSegments.slice();
    manifests.forEach((manifest: RemoteReadAloudCacheManifestSummary) => {
      if (manifest.isCurrentManifest) {
        return;
      }
      manifest.segments.forEach((segment: RemoteReadAloudCacheSegmentDetail) => {
        sourceSegments.push(segment);
      });
    });

    sourceSegments.sort((left: RemoteReadAloudCacheSegmentDetail, right: RemoteReadAloudCacheSegmentDetail) => {
      if ((left.updatedAt ?? 0) !== (right.updatedAt ?? 0)) {
        return (right.updatedAt ?? 0) - (left.updatedAt ?? 0);
      }
      if ((left.remoteDigest ?? '') !== (right.remoteDigest ?? '')) {
        return (left.remoteDigest ?? '').localeCompare(right.remoteDigest ?? '');
      }
      return left.segmentIndex - right.segmentIndex;
    });

    this.attachSuggestedTargetsToSourceSegments(sourceSegments, targetSegments);
    const coverage: RemoteReadAloudCacheCoverageSummary = this.buildCoverageSummary(targetSegments);
    const chapterDetail: RemoteReadAloudCacheChapterDetail = {
      chapterIndex,
      chapterTitle,
      currentContentDigest,
      currentRemoteDigest,
      currentManifestPath,
      currentManifestExists: currentDescriptor !== null,
      coverage,
      targetSegments,
      currentExactMatchedCount,
      sourceSegments,
      unmatchedCurrentSegments,
      manifests
    };
    return chapterDetail;
  }

  private buildCoverageSummary(
    targetSegments: RemoteReadAloudCacheTargetSegment[]
  ): RemoteReadAloudCacheCoverageSummary {
    let totalTextChars = 0;
    let coveredTextChars = 0;
    let exactCoveredTextChars = 0;
    let manualCoveredTextChars = 0;
    let coveredTargetCount = 0;
    let exactCoveredTargetCount = 0;
    let manualCoveredTargetCount = 0;
    for (let index = 0; index < targetSegments.length; index++) {
      const segment = targetSegments[index];
      const safeTextChars = Math.max(0, Math.floor(segment.textLength));
      totalTextChars += safeTextChars;
      if (!segment.attachedSegment) {
        continue;
      }
      coveredTextChars += safeTextChars;
      coveredTargetCount += 1;
      if (segment.attachedSegment.matchMode === 'manual') {
        manualCoveredTextChars += safeTextChars;
        manualCoveredTargetCount += 1;
      } else {
        exactCoveredTextChars += safeTextChars;
        exactCoveredTargetCount += 1;
      }
    }
    const summary: RemoteReadAloudCacheCoverageSummary = {
      totalTextChars,
      coveredTextChars,
      exactCoveredTextChars,
      manualCoveredTextChars,
      uncoveredTextChars: Math.max(0, totalTextChars - coveredTextChars),
      totalTargetCount: targetSegments.length,
      coveredTargetCount,
      exactCoveredTargetCount,
      manualCoveredTargetCount,
      uncoveredTargetCount: Math.max(0, targetSegments.length - coveredTargetCount)
    };
    return summary;
  }

  private attachSuggestedTargetsToSourceSegments(
    sourceSegments: RemoteReadAloudCacheSegmentDetail[],
    targetSegments: RemoteReadAloudCacheTargetSegment[]
  ): void {
    for (let index = 0; index < sourceSegments.length; index++) {
      const segment = sourceSegments[index];
      const suggestions = this.buildTargetMatchSuggestions(segment, targetSegments);
      segment.suggestedTargets = suggestions;
      segment.suggestedTarget = suggestions.length > 0 ? suggestions[0] : null;
    }
  }

  private buildTargetMatchSuggestions(
    sourceSegment: RemoteReadAloudCacheSegmentDetail,
    targetSegments: RemoteReadAloudCacheTargetSegment[]
  ): RemoteReadAloudCacheTargetSuggestion[] {
    const result: RemoteReadAloudCacheTargetSuggestion[] = [];
    if (targetSegments.length <= 0) {
      return result;
    }
    const candidates: RemoteReadAloudCacheTargetSuggestionCandidate[] = [];
    for (let index = 0; index < targetSegments.length; index++) {
      const targetSegment = targetSegments[index];
      candidates.push(this.computeTargetMatchScore(sourceSegment, targetSegment));
    }
    candidates.sort((left: RemoteReadAloudCacheTargetSuggestionCandidate, right: RemoteReadAloudCacheTargetSuggestionCandidate) => {
      if (this.isBetterTargetSuggestionCandidate(left, right)) {
        return -1;
      }
      if (this.isBetterTargetSuggestionCandidate(right, left)) {
        return 1;
      }
      return 0;
    });
    const limit = Math.min(6, candidates.length);
    for (let index = 0; index < limit; index++) {
      const candidate = candidates[index];
      result.push({
        targetSegmentIndex: candidate.targetSegmentIndex,
        score: candidate.score,
        reason: candidate.reason
      });
    }
    return result;
  }

  private buildTargetMatchSuggestion(
    sourceSegment: RemoteReadAloudCacheSegmentDetail,
    targetSegments: RemoteReadAloudCacheTargetSegment[]
  ): RemoteReadAloudCacheTargetSuggestion | null {
    const suggestions = this.buildTargetMatchSuggestions(sourceSegment, targetSegments);
    if (suggestions.length <= 0) {
      return null;
    }
    return suggestions[0];
  }

  private isBetterTargetSuggestionCandidate(
    nextCandidate: RemoteReadAloudCacheTargetSuggestionCandidate,
    currentCandidate: RemoteReadAloudCacheTargetSuggestionCandidate
  ): boolean {
    if (nextCandidate.score !== currentCandidate.score) {
      return nextCandidate.score > currentCandidate.score;
    }
    if (nextCandidate.segmentIndexDistance !== currentCandidate.segmentIndexDistance) {
      return nextCandidate.segmentIndexDistance < currentCandidate.segmentIndexDistance;
    }
    if (nextCandidate.startDistance !== currentCandidate.startDistance) {
      return nextCandidate.startDistance < currentCandidate.startDistance;
    }
    return nextCandidate.targetSegmentIndex < currentCandidate.targetSegmentIndex;
  }

  private computeTargetMatchScore(
    sourceSegment: RemoteReadAloudCacheSegmentDetail,
    targetSegment: RemoteReadAloudCacheTargetSegment
  ): RemoteReadAloudCacheTargetSuggestionCandidate {
    const segmentIndexDistance = Math.abs(sourceSegment.segmentIndex - targetSegment.segmentIndex);
    const startDistance = Math.abs(sourceSegment.startCharIndex - targetSegment.startCharIndex);
    const sourceDigest = sourceSegment.textDigest ?? '';
    const targetDigest = targetSegment.textDigest ?? '';
    if (sourceDigest.length > 0 && targetDigest.length > 0 && sourceDigest === targetDigest) {
      const exactCandidate: RemoteReadAloudCacheTargetSuggestionCandidate = {
        targetSegmentIndex: targetSegment.segmentIndex,
        score: 1,
        reason: 'exact_digest',
        segmentIndexDistance,
        startDistance
      };
      return exactCandidate;
    }

    const sourceCacheKey = sourceSegment.cacheKey ?? '';
    const targetCacheKey = targetSegment.cacheKey ?? '';
    if (sourceCacheKey.length > 0 && targetCacheKey.length > 0 && sourceCacheKey === targetCacheKey) {
      const cacheKeyCandidate: RemoteReadAloudCacheTargetSuggestionCandidate = {
        targetSegmentIndex: targetSegment.segmentIndex,
        score: 0.98,
        reason: 'cache_key',
        segmentIndexDistance,
        startDistance
      };
      return cacheKeyCandidate;
    }

    const rangeOverlap = this.computeRangeOverlapRatio(
      sourceSegment.startCharIndex,
      sourceSegment.endCharIndex,
      targetSegment.startCharIndex,
      targetSegment.endCharIndex
    );
    const previewSimilarity = this.computePreviewSimilarity(sourceSegment.textPreview, targetSegment.textPreview);
    const lengthSimilarity = this.computeLengthSimilarity(sourceSegment.textLength, targetSegment.textLength);
    let score = rangeOverlap * 0.5 + previewSimilarity * 0.35 + lengthSimilarity * 0.15;
    if (previewSimilarity >= 0.95 && lengthSimilarity >= 0.95) {
      score = Math.max(score, 0.92);
    }
    if (sourceSegment.segmentIndex === targetSegment.segmentIndex) {
      score = Math.min(0.99, score + 0.08);
    }

    let reason: RemoteReadAloudCacheTargetMatchReason = 'weak';
    if (rangeOverlap >= 0.72) {
      reason = 'range_overlap';
    } else if (previewSimilarity >= 0.6) {
      reason = 'preview_similarity';
    } else if (lengthSimilarity >= 0.88) {
      reason = 'length_similarity';
    } else if (sourceSegment.segmentIndex === targetSegment.segmentIndex) {
      reason = 'segment_index';
    }

    const candidate: RemoteReadAloudCacheTargetSuggestionCandidate = {
      targetSegmentIndex: targetSegment.segmentIndex,
      score: this.clampReadAloudTargetMatchScore(score),
      reason,
      segmentIndexDistance,
      startDistance
    };
    return candidate;
  }

  private computeRangeOverlapRatio(
    leftStart: number,
    leftEnd: number,
    rightStart: number,
    rightEnd: number
  ): number {
    const safeLeftStart = Math.max(0, Math.floor(leftStart));
    const safeLeftEnd = Math.max(safeLeftStart, Math.floor(leftEnd));
    const safeRightStart = Math.max(0, Math.floor(rightStart));
    const safeRightEnd = Math.max(safeRightStart, Math.floor(rightEnd));
    const overlap = Math.max(0, Math.min(safeLeftEnd, safeRightEnd) - Math.max(safeLeftStart, safeRightStart));
    if (overlap <= 0) {
      return 0;
    }
    const leftLength = Math.max(1, safeLeftEnd - safeLeftStart);
    const rightLength = Math.max(1, safeRightEnd - safeRightStart);
    return this.clampReadAloudTargetMatchScore(overlap / Math.max(leftLength, rightLength));
  }

  private computePreviewSimilarity(leftPreview: string, rightPreview: string): number {
    const left = this.normalizeSimilarityPreview(leftPreview);
    const right = this.normalizeSimilarityPreview(rightPreview);
    if (left.length <= 0 || right.length <= 0) {
      return 0;
    }
    if (left === right) {
      return 1;
    }
    const containsScore = left.indexOf(right) >= 0 || right.indexOf(left) >= 0
      ? this.computeLengthSimilarity(left.length, right.length)
      : 0;
    const edgeSimilarity = this.computePreviewEdgeSimilarity(left, right);
    const leftBigrams = this.buildPreviewSimilarityBigrams(left);
    const rightBigrams = this.buildPreviewSimilarityBigrams(right);
    if (leftBigrams.length <= 0 || rightBigrams.length <= 0) {
      return this.clampReadAloudTargetMatchScore(Math.max(containsScore, edgeSimilarity));
    }
    const rightTokenCounts = new Map<string, number>();
    for (let index = 0; index < rightBigrams.length; index++) {
      const token = rightBigrams[index];
      rightTokenCounts.set(token, (rightTokenCounts.get(token) ?? 0) + 1);
    }
    let overlap = 0;
    for (let index = 0; index < leftBigrams.length; index++) {
      const token = leftBigrams[index];
      const remaining = rightTokenCounts.get(token) ?? 0;
      if (remaining <= 0) {
        continue;
      }
      overlap += 1;
      rightTokenCounts.set(token, remaining - 1);
    }
    const diceScore = (2 * overlap) / (leftBigrams.length + rightBigrams.length);
    return this.clampReadAloudTargetMatchScore(Math.max(diceScore, containsScore, edgeSimilarity));
  }

  private computePreviewEdgeSimilarity(left: string, right: string): number {
    const minLength = Math.min(left.length, right.length);
    const maxLength = Math.max(left.length, right.length);
    if (minLength <= 0 || maxLength <= 0) {
      return 0;
    }
    let prefixMatches = 0;
    while (prefixMatches < minLength && left.charCodeAt(prefixMatches) === right.charCodeAt(prefixMatches)) {
      prefixMatches += 1;
    }
    let suffixMatches = 0;
    while (
      suffixMatches < minLength - prefixMatches &&
      left.charCodeAt(left.length - 1 - suffixMatches) === right.charCodeAt(right.length - 1 - suffixMatches)
    ) {
      suffixMatches += 1;
    }
    return this.clampReadAloudTargetMatchScore((prefixMatches + suffixMatches) / maxLength);
  }

  private buildPreviewSimilarityBigrams(text: string): string[] {
    const result: string[] = [];
    if (text.length <= 0) {
      return result;
    }
    if (text.length === 1) {
      result.push(text);
      return result;
    }
    for (let index = 0; index < text.length - 1; index++) {
      result.push(text.slice(index, index + 2));
    }
    return result;
  }

  private normalizeSimilarityPreview(preview: string): string {
    return normalizeRemoteTtsCacheText(preview)
      .replace(/(\.\.\.|\u2026)$/g, '')
      .replace(/\s+/g, '');
  }

  private computeLengthSimilarity(leftLength: number, rightLength: number): number {
    const safeLeft = Math.max(0, Math.floor(leftLength));
    const safeRight = Math.max(0, Math.floor(rightLength));
    if (safeLeft <= 0 || safeRight <= 0) {
      return 0;
    }
    return this.clampReadAloudTargetMatchScore(Math.min(safeLeft, safeRight) / Math.max(safeLeft, safeRight));
  }

  private clampReadAloudTargetMatchScore(value: number): number {
    if (!Number.isFinite(value)) {
      return 0;
    }
    return Math.max(0, Math.min(1, value));
  }

  async removeSegmentFromManifest(
    content: UnifiedContent | null,
    chapterIndex: number,
    manifestPath: string,
    segmentIndex: number
  ): Promise<void> {
    const identity = this.resolveBookIdentity(content);
    if (!identity.supported || !manifestPath || manifestPath.length <= 0) {
      return;
    }
    const manifest = safeReadJson<RemoteTtsManifestRecord>(manifestPath);
    if (!manifest || !Array.isArray(manifest.segments)) {
      return;
    }
    const safeSegmentIndex = Math.max(0, Math.floor(segmentIndex));
    const segment = manifest.segments.find((item: RemoteTtsManifestSegmentRecord) =>
      Math.max(0, Math.floor(item.index ?? 0)) === safeSegmentIndex
    ) ?? null;
    if (!segment) {
      return;
    }
    const removedReferences: RemoteReadAloudAllReferenceSnapshot = {
      segmentAudioPaths: new Set<string>(),
      segmentMetaPaths: new Set<string>()
    };
    if (segment.filePath && segment.filePath.length > 0) {
      removedReferences.segmentAudioPaths.add(segment.filePath);
      removedReferences.segmentMetaPaths.add(buildSegmentMetaPath(segment.filePath));
    }

    manifest.segments = manifest.segments.filter((item: RemoteTtsManifestSegmentRecord) =>
      Math.max(0, Math.floor(item.index ?? 0)) !== safeSegmentIndex
    );
    this.invalidateManifestMergedAudio(manifest);
    this.persistOrDeleteManifest(manifestPath, manifest);
    this.cleanupUnreferencedSharedSegments(removedReferences);
    eventBus.publish(
      GameEvent.READ_ALOUD_CACHE_UPDATED,
      new ReadAloudCacheUpdatedPayload(identity.bookId, chapterIndex, 'remove_segment', manifest.remoteDigest ?? '')
    );
  }

  async attachSegmentToCurrentSlot(
    content: UnifiedContent | null,
    chapterIndex: number,
    targetSegmentIndex: number,
    sourceManifestPath: string,
    sourceSegmentIndex: number
  ): Promise<void> {
    const identity = this.resolveBookIdentity(content);
    if (!identity.supported || chapterIndex < 0 || chapterIndex >= identity.chapterCount) {
      throw new Error('READ_ALOUD_CACHE_ATTACH_UNSUPPORTED');
    }
    const effectiveSettings = this.resolveEffectiveReadAloudSettings(content);
    const remoteSettings = effectiveSettings.remoteSettings;
    const currentRemoteDigest = this.buildRemoteDigest(remoteSettings);
    const chapterContent = await this.loadProcessedChapterContent(identity, chapterIndex);
    const currentContentDigest = fnv1aHashHex(chapterContent);
    const targets = this.buildExpectedSegments(chapterContent, remoteSettings);
    const target = targets.find((item: RemoteReadAloudExpectedSegmentRecord) => item.segmentIndex === targetSegmentIndex) ?? null;
    if (!target) {
      throw new Error(`READ_ALOUD_CACHE_TARGET_SEGMENT_NOT_FOUND: ${targetSegmentIndex}`);
    }

    const sourceManifest = safeReadJson<RemoteTtsManifestRecord>(sourceManifestPath);
    if (!sourceManifest || !Array.isArray(sourceManifest.segments)) {
      throw new Error('READ_ALOUD_CACHE_SOURCE_MANIFEST_MISSING');
    }
    const sourceSegment = sourceManifest.segments.find((item: RemoteTtsManifestSegmentRecord) =>
      Math.max(0, Math.floor(item.index ?? 0)) === Math.max(0, Math.floor(sourceSegmentIndex))
    ) ?? null;
    if (!sourceSegment || !sourceSegment.filePath || !SafeFileUtils.accessSync(sourceSegment.filePath)) {
      throw new Error('READ_ALOUD_CACHE_SOURCE_SEGMENT_MISSING');
    }

    const currentManifestPath = this.buildChapterManifestPath(identity.bookId, chapterIndex, currentContentDigest, currentRemoteDigest);
    const currentManifest = this.loadOrCreateChapterManifest(
      currentManifestPath,
      identity.bookId,
      chapterIndex,
      currentContentDigest,
      currentRemoteDigest,
      remoteSettings.audioFormat
    );
    currentManifest.segments = currentManifest.segments.filter((item: RemoteTtsManifestSegmentRecord) => {
      const itemIndex = Math.max(0, Math.floor(item.index ?? 0));
      if (itemIndex === target.segmentIndex) {
        return false;
      }
      if (sourceManifestPath === currentManifestPath && itemIndex === Math.max(0, Math.floor(sourceSegmentIndex))) {
        return false;
      }
      return true;
    });
    currentManifest.segments.push({
      index: target.segmentIndex,
      start: target.startCharIndex,
      end: target.endCharIndex,
      cacheKey: target.cacheKey,
      textDigest: target.textDigest,
      textLength: target.textLength,
      textPreview: target.textPreview,
      filePath: sourceSegment.filePath,
      bytes: Math.max(0, safeStatSize(sourceSegment.filePath) || Math.floor(sourceSegment.bytes ?? 0)),
      durationMs: Math.max(0, Math.floor(sourceSegment.durationMs ?? 0)),
      seekTotalUnits: sourceSegment.seekTotalUnits,
      seekAnchors: sourceSegment.seekAnchors,
      manualMatchedAt: Date.now(),
      manualMatchSourceManifestPath: sourceManifestPath,
      manualMatchSourceCacheKey: sourceSegment.cacheKey,
      manualMatchSourceSegmentIndex: Math.max(0, Math.floor(sourceSegment.index ?? sourceSegmentIndex))
    });
    this.sortManifestSegments(currentManifest);
    this.invalidateManifestMergedAudio(currentManifest);
    this.persistOrDeleteManifest(currentManifestPath, currentManifest);
    eventBus.publish(
      GameEvent.READ_ALOUD_CACHE_UPDATED,
      new ReadAloudCacheUpdatedPayload(identity.bookId, chapterIndex, 'attach_segment', currentRemoteDigest)
    );
  }

  private overrideRemoteSettings(
    settings: ReadAloudSettings,
    remoteSettings: RemoteReadAloudSettings
  ): ReadAloudSettings {
    return normalizeReadAloudSettings({
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
      voiceOnline: settings.voiceOnline,
      remote: remoteSettings
    });
  }

  async saveCurrentRemoteSettings(
    content: UnifiedContent | null,
    settings: Partial<RemoteReadAloudSettings> | null
  ): Promise<void> {
    const identity = this.resolveBookIdentity(content);
    const effective = this.resolveEffectiveReadAloudSettings(content);
    const nextRemoteSettings = mergeRemoteReadAloudSettings(effective.remoteSettings, settings ?? {});
    const nextReadAloudSettings = this.overrideRemoteSettings(effective.readAloudSettings, nextRemoteSettings);

    if (identity.supported) {
      const settingsKey = this.buildBookSettingsKey(identity.bookId);
      const hasBookScopedSettings = this.settingsManager.getString(settingsKey, '').length > 0;
      const baseSnapshot = hasBookScopedSettings
        ? this.settingsManager.getJSON<TextReaderSettings>(settingsKey, DEFAULT_TEXT_READER_SETTINGS)
        : this.settingsManager.getJSON<TextReaderSettings>(SettingKeys.NOVEL_READER_SETTINGS, DEFAULT_TEXT_READER_SETTINGS);
      const nextSnapshot = SafeUtils.parseObj(JSON.stringify(baseSnapshot)) as TextReaderSettings;
      const baseReadAloudSettings = normalizeReadAloudSettings(
        nextSnapshot.readAloud ?? nextReadAloudSettings
      );
      nextSnapshot.readAloud = this.overrideRemoteSettings(baseReadAloudSettings, nextRemoteSettings);
      await this.settingsManager.setJSON<TextReaderSettings>(settingsKey, nextSnapshot);
      logger.info(TAG, `已保存当前书籍远程TTS设置: bookId=${identity.bookId}, source=${effective.source}`);
    } else {
      await persistGlobalReadAloudSettings(this.settingsManager, nextReadAloudSettings);
      logger.info(TAG, `已保存全局远程TTS设置: source=${effective.source}`);
    }

    const controllerContext = this.readAloudController.getContextSnapshot();
    if (identity.supported && controllerContext && controllerContext.bookId === identity.bookId) {
      const controllerSnapshot = this.readAloudController.getSnapshot();
      this.readAloudController.updateSettings(
        this.overrideRemoteSettings(controllerSnapshot.settings, nextRemoteSettings)
      );
      logger.info(TAG, `已同步当前会话远程TTS设置: bookId=${identity.bookId}`);
    }
  }

  private resolveBookIdentity(content: UnifiedContent | null): RemoteReadAloudBookIdentity {
    if (!content) {
      return this.buildUnsupportedIdentity();
    }
    if (content.contentType === UnifiedContentType.NOVEL) {
      const sourceId = (content.sourceId || 'local').trim();
      const bookUrl = (content.id || '').trim();
      if (bookUrl.length <= 0) {
        return this.buildUnsupportedIdentity();
      }
      return {
        supported: true,
        isLocalTxtEBook: false,
        bookId: `${sourceId}_${encodeURIComponent(bookUrl)}`,
        bookTitle: content.title,
        coverUrl: content.coverUrl || '',
        sourceId,
        bookUrl,
        chapterCount: content.chapters.length,
        chapters: content.chapters,
        localEbookId: ''
      };
    }

    if (content.contentType === UnifiedContentType.EBOOK) {
      const ebook = EBookAdapter.getOriginalEBook(content);
      if (!ebook || ebook.format !== EBookFormat.TXT) {
        return this.buildUnsupportedIdentity();
      }
      const bookUrl = buildNovelReaderParamsFromTxtEBook(ebook).bookUrl;
      return {
        supported: true,
        isLocalTxtEBook: true,
        bookId: buildLocalTextNovelBookId(ebook.id),
        bookTitle: content.title,
        coverUrl: content.coverUrl || '',
        sourceId: LOCAL_TXT_NOVEL_SOURCE_ID,
        bookUrl,
        chapterCount: content.chapters.length,
        chapters: content.chapters,
        localEbookId: ebook.id
      };
    }

    return this.buildUnsupportedIdentity();
  }

  private buildUnsupportedIdentity(): RemoteReadAloudBookIdentity {
    return {
      supported: false,
      isLocalTxtEBook: false,
      bookId: '',
      bookTitle: '',
      coverUrl: '',
      sourceId: '',
      bookUrl: '',
      chapterCount: 0,
      chapters: [],
      localEbookId: ''
    };
  }

  private buildCacheRootPath(): string {
    const abilityContext = uiContextManager.getAbilityContext();
    const filesDir = abilityContext?.filesDir ?? abilityContext?.cacheDir ?? '';
    return filesDir.length > 0 ? `${filesDir}/${REMOTE_READ_ALOUD_CACHE_ROOT_DIR}` : '';
  }

  private buildBookRootPath(bookId: string): string {
    return `${this.buildCacheRootPath()}/books/${sanitizePathPart(bookId)}`;
  }

  private buildBookSettingsKey(bookId: string): string {
    return `${SettingKeys.NOVEL_READER_SETTINGS}_${bookId}`;
  }

  private buildEmptyChapterSummaries(chapters: UnifiedChapter[]): RemoteReadAloudCacheChapterSummary[] {
    const result: RemoteReadAloudCacheChapterSummary[] = [];
    for (let index = 0; index < chapters.length; index++) {
      result.push({
        chapterIndex: index,
        chapterTitle: chapters[index].title || `第 ${index + 1} 章`,
        cached: false,
        variantCount: 0,
        manifestCount: 0,
        segmentCount: 0,
        totalBytes: 0,
        mergedAudioBytes: 0,
        lastUpdatedAt: 0,
        currentSegmentCount: 0,
        currentTotalBytes: 0,
        currentMergedAudioBytes: 0,
        currentLastUpdatedAt: 0,
        currentTextChars: 0,
        currentSegments: [],
        displayTextChars: 0,
        displaySegments: [],
        displaySegmentsSource: 'none'
      });
    }
    return result;
  }

  private resolveEffectiveReadAloudSettings(content: UnifiedContent | null): RemoteReadAloudEffectiveSettingsSnapshot {
    const identity = this.resolveBookIdentity(content);
    const controllerContext = this.readAloudController.getContextSnapshot();
    if (identity.supported && controllerContext && controllerContext.bookId === identity.bookId) {
      const controllerSnapshot = this.readAloudController.getSnapshot();
      return {
        readAloudSettings: controllerSnapshot.settings,
        remoteSettings: controllerSnapshot.settings.remote ?? DEFAULT_REMOTE_READ_ALOUD_SETTINGS,
        source: 'active_session',
        sourceLabel: '当前播放会话'
      };
    }

    if (identity.supported) {
      const settingsKey = this.buildBookSettingsKey(identity.bookId);
      if (this.settingsManager.getString(settingsKey, '').length > 0) {
        const bookSettings = this.settingsManager.getJSON<TextReaderSettings>(settingsKey, DEFAULT_TEXT_READER_SETTINGS);
        const readAloudSettings = normalizeReadAloudSettings(
          bookSettings.readAloud ?? DEFAULT_TEXT_READER_SETTINGS.readAloud
        );
        return {
          readAloudSettings,
          remoteSettings: readAloudSettings.remote ?? DEFAULT_REMOTE_READ_ALOUD_SETTINGS,
          source: 'book',
          sourceLabel: '当前书籍专属设置'
        };
      }
    }

    const globalSettings = loadGlobalReadAloudSettings(this.settingsManager);
    return {
      readAloudSettings: globalSettings,
      remoteSettings: globalSettings.remote ?? DEFAULT_REMOTE_READ_ALOUD_SETTINGS,
      source: 'global',
      sourceLabel: '全局默认设置'
    };
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

  private buildExpectedSegments(
    content: string,
    settings: RemoteReadAloudSettings
  ): RemoteReadAloudExpectedSegmentRecord[] {
    const result: RemoteReadAloudExpectedSegmentRecord[] = [];
    if (!content || content.trim().length <= 0) {
      return result;
    }

    const hardLimit = Math.max(64, settings.maxInputChars - settings.reservedInputChars);
    const maxChunk = Math.max(64, Math.min(settings.maxChunkChars, hardLimit));
    const targetChunk = Math.max(64, Math.min(settings.targetChunkChars, maxChunk));
    const minChunk = Math.max(32, Math.min(settings.minChunkChars, targetChunk));

    let start = 0;
    let segmentIndex = 0;
    while (start < content.length) {
      const range = this.pickRemoteChunkRange(content, start, minChunk, targetChunk, maxChunk);
      if (range.end <= range.start) {
        break;
      }
      const chunk = content.slice(range.start, range.end);
      if (chunk.trim().length > 0) {
        result.push({
          segmentIndex,
          startCharIndex: range.start,
          endCharIndex: range.end,
          textLength: normalizeRemoteTtsCacheText(chunk).length,
          textPreview: buildRemoteTtsTextPreview(chunk),
          cacheKey: buildRemoteTtsTextCacheKey(chunk),
          textDigest: buildRemoteTtsTextDigest(chunk)
        });
        segmentIndex += 1;
      }
      start = range.end;
    }
    return result;
  }

  private pickRemoteChunkRange(
    content: string,
    start: number,
    minChunk: number,
    targetChunk: number,
    maxChunk: number
  ): RemoteReadAloudChunkRange {
    const maxEnd = Math.min(content.length, start + maxChunk);
    const targetEnd = Math.min(content.length, start + targetChunk);
    const minEnd = Math.min(content.length, start + minChunk);
    if (maxEnd <= minEnd) {
      const maxRange: RemoteReadAloudChunkRange = { start, end: maxEnd };
      return maxRange;
    }
    const backward = this.findRemoteBreakBackward(content, targetEnd, minEnd);
    if (backward > start) {
      const backwardRange: RemoteReadAloudChunkRange = { start, end: backward };
      return backwardRange;
    }
    const forward = this.findRemoteBreakForward(content, targetEnd, maxEnd);
    if (forward > start) {
      const forwardRange: RemoteReadAloudChunkRange = { start, end: forward };
      return forwardRange;
    }
    const fallbackRange: RemoteReadAloudChunkRange = { start, end: maxEnd };
    return fallbackRange;
  }

  private findRemoteBreakBackward(content: string, from: number, minEnd: number): number {
    for (let index = from; index > minEnd; index--) {
      if (isRemoteTtsBreakChar(content.charAt(index - 1))) {
        return index;
      }
    }
    return -1;
  }

  private findRemoteBreakForward(content: string, from: number, maxEnd: number): number {
    for (let index = from; index < maxEnd; index++) {
      if (isRemoteTtsBreakChar(content.charAt(index))) {
        return index + 1;
      }
    }
    return -1;
  }

  private buildChapterManifestPath(
    bookId: string,
    chapterIndex: number,
    contentDigest: string,
    remoteDigest: string
  ): string {
    return `${this.buildBookRootPath(bookId)}/chapter_${chapterIndex}/${contentDigest}/${remoteDigest}/manifest.json`;
  }

  private loadOrCreateChapterManifest(
    manifestPath: string,
    bookId: string,
    chapterIndex: number,
    contentDigest: string,
    remoteDigest: string,
    audioFormat: string
  ): RemoteTtsManifestRecord {
    const existing = safeReadJson<RemoteTtsManifestRecord>(manifestPath);
    if (
      existing &&
      Array.isArray(existing.segments) &&
      existing.bookId === bookId &&
      existing.chapterIndex === chapterIndex &&
      (existing.contentDigest ?? '') === contentDigest &&
      (existing.remoteDigest ?? '') === remoteDigest
    ) {
      return existing;
    }
    ensureDirExists(dirname(manifestPath));
    return {
      version: REMOTE_TTS_MANIFEST_VERSION,
      updatedAt: Date.now(),
      bookId,
      chapterIndex,
      contentDigest,
      remoteDigest,
      audioFormat,
      mergedFilePath: '',
      segments: []
    };
  }

  private sortManifestSegments(manifest: RemoteTtsManifestRecord): void {
    manifest.segments.sort((left: RemoteTtsManifestSegmentRecord, right: RemoteTtsManifestSegmentRecord) => {
      const leftIndex = Math.max(0, Math.floor(left.index ?? 0));
      const rightIndex = Math.max(0, Math.floor(right.index ?? 0));
      if (leftIndex !== rightIndex) {
        return leftIndex - rightIndex;
      }
      return Math.max(0, Math.floor(left.start ?? 0)) - Math.max(0, Math.floor(right.start ?? 0));
    });
  }

  private invalidateManifestMergedAudio(manifest: RemoteTtsManifestRecord): void {
    if (manifest.mergedFilePath && manifest.mergedFilePath.length > 0) {
      deleteFileIfExists(manifest.mergedFilePath);
    }
    manifest.mergedFilePath = '';
  }

  private persistOrDeleteManifest(manifestPath: string, manifest: RemoteTtsManifestRecord): void {
    if (!manifest.segments || manifest.segments.length <= 0) {
      deleteFileIfExists(manifestPath);
      cleanupEmptyParentDirs(dirname(manifestPath), this.buildCacheRootPath());
      return;
    }
    ensureDirExists(dirname(manifestPath));
    manifest.updatedAt = Date.now();
    this.sortManifestSegments(manifest);
    writeJsonFile(manifestPath, manifest as Object);
  }

  private buildSegmentDetailFromRecord(
    segment: RemoteTtsManifestSegmentRecord,
    descriptor: RemoteReadAloudManifestDescriptor,
    currentRemoteDigest: string,
    currentContentDigest: string,
    matchMode: 'exact' | 'manual' | 'history' | 'current_unmatched'
  ): RemoteReadAloudCacheSegmentDetail {
    const startCharIndex = Math.max(0, Math.floor(segment.start ?? 0));
    const endCharIndex = Math.max(startCharIndex, Math.floor(segment.end ?? startCharIndex));
    const textLength = Math.max(0, Math.floor(segment.textLength ?? Math.max(0, endCharIndex - startCharIndex)));
    const rawAnchors = Array.isArray(segment.seekAnchors) ? segment.seekAnchors : [];
    const filePath = segment.filePath || '';
    return {
      segmentIndex: Math.max(0, Math.floor(segment.index ?? 0)),
      startCharIndex,
      endCharIndex,
      textLength,
      textPreview: segment.textPreview || '',
      bytes: Math.max(0, safeStatSize(filePath) || Math.floor(segment.bytes ?? 0)),
      durationMs: Math.max(0, Math.floor(segment.durationMs ?? 0)),
      anchorCount: rawAnchors.length,
      cacheKey: segment.cacheKey || '',
      textDigest: segment.textDigest || '',
      filePath,
      metaPath: filePath.length > 0 ? buildSegmentMetaPath(filePath) : '',
      manifestPath: descriptor.path,
      contentDigest: descriptor.contentDigest,
      remoteDigest: descriptor.remoteDigest,
      audioFormat: descriptor.audioFormat,
      updatedAt: descriptor.updatedAt,
      isCurrentConfigMatch: descriptor.remoteDigest === currentRemoteDigest,
      isCurrentTextMatch: descriptor.contentDigest === currentContentDigest,
      isCurrentManifest: false,
      suggestedTarget: null,
      suggestedTargets: [],
      matchMode,
      manualMatchedAt: Math.max(0, Math.floor(segment.manualMatchedAt ?? 0)),
      manualMatchSourceManifestPath: segment.manualMatchSourceManifestPath || '',
      manualMatchSourceCacheKey: segment.manualMatchSourceCacheKey || '',
      manualMatchSourceSegmentIndex: segment.manualMatchSourceSegmentIndex
    };
  }

  private buildManifestSummary(
    descriptor: RemoteReadAloudManifestDescriptor,
    currentRemoteDigest: string,
    currentContentDigest: string,
    isCurrentManifest: boolean,
    isLatestVariant: boolean
  ): RemoteReadAloudCacheManifestSummary {
    const segments = descriptor.manifest.segments.map((segment: RemoteTtsManifestSegmentRecord) => {
      const mode = isCurrentManifest
        ? (segment.manualMatchSourceManifestPath && segment.manualMatchSourceManifestPath.length > 0 ? 'manual' : 'exact')
        : 'history';
      const detail = this.buildSegmentDetailFromRecord(segment, descriptor, currentRemoteDigest, currentContentDigest, mode);
      detail.isCurrentManifest = isCurrentManifest;
      return detail;
    }).sort((left: RemoteReadAloudCacheSegmentDetail, right: RemoteReadAloudCacheSegmentDetail) => {
      if (left.segmentIndex !== right.segmentIndex) {
        return left.segmentIndex - right.segmentIndex;
      }
      return left.startCharIndex - right.startCharIndex;
    });

    return {
      manifestPath: descriptor.path,
      chapterIndex: descriptor.chapterIndex,
      updatedAt: descriptor.updatedAt,
      contentDigest: descriptor.contentDigest,
      remoteDigest: descriptor.remoteDigest,
      audioFormat: descriptor.audioFormat,
      mergedFilePath: descriptor.mergedFilePath,
      mergedFileBytes: descriptor.mergedFileBytes,
      segmentCount: descriptor.segmentCount,
      textChars: descriptor.textChars,
      isCurrentConfigMatch: descriptor.remoteDigest === currentRemoteDigest,
      isCurrentTextMatch: descriptor.contentDigest === currentContentDigest,
      isCurrentManifest,
      isLatestVariant,
      segments
    };
  }

  private collectCurrentSettingsDescriptors(
    descriptors: RemoteReadAloudManifestDescriptor[],
    remoteDigest: string
  ): Map<number, RemoteReadAloudManifestDescriptor> {
    const result = new Map<number, RemoteReadAloudManifestDescriptor>();
    for (let index = 0; index < descriptors.length; index++) {
      const descriptor = descriptors[index];
      if (!remoteDigest || descriptor.remoteDigest !== remoteDigest) {
        continue;
      }
      const existing = result.get(descriptor.chapterIndex);
      if (!existing || descriptor.updatedAt >= existing.updatedAt) {
        result.set(descriptor.chapterIndex, descriptor);
      }
    }
    return result;
  }

  private collectLatestDescriptorsByChapter(
    descriptors: RemoteReadAloudManifestDescriptor[]
  ): Map<number, RemoteReadAloudManifestDescriptor> {
    const result = new Map<number, RemoteReadAloudManifestDescriptor>();
    for (let index = 0; index < descriptors.length; index++) {
      const descriptor = descriptors[index];
      const existing = result.get(descriptor.chapterIndex);
      if (!existing || descriptor.updatedAt >= existing.updatedAt) {
        result.set(descriptor.chapterIndex, descriptor);
      }
    }
    return result;
  }

  private collectManifestDescriptors(rootPath: string): RemoteReadAloudManifestDescriptor[] {
    const result: RemoteReadAloudManifestDescriptor[] = [];
    this.walkManifests(rootPath, result);
    return result;
  }

  private walkManifests(path: string, output: RemoteReadAloudManifestDescriptor[]): void {
    try {
      if (!path || !SafeFileUtils.accessSync(path)) {
        return;
      }
      const stat = SafeFileUtils.statSync(path);
      if (stat.isFile()) {
        if (!path.endsWith('/manifest.json') && !path.endsWith('\\manifest.json')) {
          return;
        }
        const manifest = safeReadJson<RemoteTtsManifestRecord>(path);
        if (!manifest || !Array.isArray(manifest.segments)) {
          return;
        }
        const mergedFilePath = manifest.mergedFilePath || '';
        const segmentSummaries = this.buildSegmentSummaries(
          path,
          manifest,
          manifest.remoteDigest || '',
          manifest.contentDigest || ''
        );
        output.push({
          path,
          chapterIndex: manifest.chapterIndex,
          updatedAt: manifest.updatedAt || 0,
          contentDigest: manifest.contentDigest || '',
          remoteDigest: manifest.remoteDigest || '',
          audioFormat: manifest.audioFormat || '',
          mergedFilePath,
          mergedFileBytes: safeStatSize(mergedFilePath),
          segmentCount: manifest.segments.length,
          segmentPaths: manifest.segments
            .map((segment: RemoteTtsManifestSegmentRecord) => segment.filePath)
            .filter((segmentPath: string) => !!segmentPath && segmentPath.length > 0),
          manifest,
          segments: segmentSummaries,
          textChars: segmentSummaries.reduce(
            (sum: number, segment: RemoteReadAloudCacheSegmentSummary) => sum + segment.textLength,
            0
          )
        });
        return;
      }
      const children = SafeFileUtils.listFileSync(path);
      for (let index = 0; index < children.length; index++) {
        this.walkManifests(`${path}/${children[index]}`, output);
      }
    } catch (_error) {
    }
  }

  private buildSegmentSummaries(
    manifestPath: string,
    manifest: RemoteTtsManifestRecord,
    remoteDigest: string,
    contentDigest: string
  ): RemoteReadAloudCacheSegmentSummary[] {
    const result: RemoteReadAloudCacheSegmentSummary[] = [];
    const segments = Array.isArray(manifest.segments) ? manifest.segments : [];
    for (let index = 0; index < segments.length; index++) {
      const segment = segments[index];
      const startCharIndex = Math.max(0, Math.floor(segment.start ?? 0));
      const endCharIndex = Math.max(startCharIndex, Math.floor(segment.end ?? startCharIndex));
      const textLength = Math.max(
        0,
        Math.floor(segment.textLength ?? Math.max(0, endCharIndex - startCharIndex))
      );
      const rawAnchors = Array.isArray(segment.seekAnchors) ? segment.seekAnchors : [];
      const filePath = segment.filePath || '';
      result.push({
        segmentIndex: Math.max(0, Math.floor(segment.index ?? index)),
        startCharIndex,
        endCharIndex,
        textLength,
        textPreview: segment.textPreview || '',
        bytes: Math.max(0, safeStatSize(filePath) || Math.floor(segment.bytes ?? 0)),
        durationMs: Math.max(0, Math.floor(segment.durationMs ?? 0)),
        anchorCount: rawAnchors.length,
        cacheKey: segment.cacheKey || '',
        textDigest: segment.textDigest || '',
        filePath,
        metaPath: filePath.length > 0 ? buildSegmentMetaPath(filePath) : '',
        manifestPath,
        contentDigest,
        remoteDigest,
        audioFormat: manifest.audioFormat || '',
        updatedAt: manifest.updatedAt || 0,
        manualMatchedAt: Math.max(0, Math.floor(segment.manualMatchedAt ?? 0)),
        manualMatchSourceManifestPath: segment.manualMatchSourceManifestPath || '',
        manualMatchSourceCacheKey: segment.manualMatchSourceCacheKey || '',
        manualMatchSourceSegmentIndex: segment.manualMatchSourceSegmentIndex
      });
    }
    result.sort((left: RemoteReadAloudCacheSegmentSummary, right: RemoteReadAloudCacheSegmentSummary) => {
      if (left.segmentIndex !== right.segmentIndex) {
        return left.segmentIndex - right.segmentIndex;
      }
      return left.startCharIndex - right.startCharIndex;
    });
    return result;
  }

  private collectSegmentReferencesFromBookRoot(bookRootPath: string): RemoteReadAloudAllReferenceSnapshot {
    const descriptors = this.collectManifestDescriptors(bookRootPath);
    const segmentAudioPaths = new Set<string>();
    const segmentMetaPaths = new Set<string>();
    for (let descriptorIndex = 0; descriptorIndex < descriptors.length; descriptorIndex++) {
      const descriptor = descriptors[descriptorIndex];
      for (let segmentIndex = 0; segmentIndex < descriptor.segmentPaths.length; segmentIndex++) {
        const segmentPath = descriptor.segmentPaths[segmentIndex];
        segmentAudioPaths.add(segmentPath);
        segmentMetaPaths.add(buildSegmentMetaPath(segmentPath));
      }
    }
    return { segmentAudioPaths, segmentMetaPaths };
  }

  private collectAllReferencedSegmentPaths(): RemoteReadAloudAllReferenceSnapshot {
    const booksRootPath = `${this.buildCacheRootPath()}/books`;
    return this.collectSegmentReferencesFromBookRoot(booksRootPath);
  }

  private cleanupUnreferencedSharedSegments(currentReferences: RemoteReadAloudAllReferenceSnapshot): void {
    const allReferences = this.collectAllReferencedSegmentPaths();
    const segmentsRootPath = `${this.buildCacheRootPath()}/segments`;
    currentReferences.segmentAudioPaths.forEach((segmentPath: string) => {
      if (!allReferences.segmentAudioPaths.has(segmentPath)) {
        deleteFileIfExists(segmentPath);
        cleanupEmptyParentDirs(segmentPath.substring(0, segmentPath.lastIndexOf('/')), segmentsRootPath);
      }
    });
    currentReferences.segmentMetaPaths.forEach((metaPath: string) => {
      if (!allReferences.segmentMetaPaths.has(metaPath)) {
        deleteFileIfExists(metaPath);
        cleanupEmptyParentDirs(metaPath.substring(0, metaPath.lastIndexOf('/')), segmentsRootPath);
      }
    });
  }

  private async loadProcessedChapterContent(identity: RemoteReadAloudBookIdentity, chapterIndex: number): Promise<string> {
    if (identity.isLocalTxtEBook) {
      const ebook = await this.ensureLocalTxtEbookLoaded(identity);
      const chapter = ebook?.chapters[chapterIndex];
      const rawContent = chapter?.content || '';
      if (rawContent.length <= 0) {
        return '';
      }
      return await processReadAloudNovelContentByBook(
        rawContent,
        chapter?.title || identity.chapters[chapterIndex]?.title || `第 ${chapterIndex + 1} 章`,
        identity.bookTitle,
        identity.sourceId,
        identity.bookId
      );
    }

    let rawContent = await this.novelChapterCacheManager.getChapterCache(identity.bookId, chapterIndex);
    if (!rawContent || rawContent.length <= 0) {
      const chapter = this.buildNovelChapterRequest(identity, chapterIndex);
      if (!chapter) {
        return '';
      }
      rawContent = await this.novelSourceManager.getContent(identity.sourceId, chapter);
    }
    if (!rawContent || rawContent.length <= 0) {
      return '';
    }
    const chapterTitle = identity.chapters[chapterIndex]?.title || `第 ${chapterIndex + 1} 章`;
    return await processReadAloudNovelContentByBook(
      rawContent,
      chapterTitle,
      identity.bookTitle,
      identity.sourceId,
      identity.bookId
    );
  }

  private async ensureLocalTxtEbookLoaded(identity: RemoteReadAloudBookIdentity): Promise<EBook | null> {
    if (!identity.isLocalTxtEBook || identity.localEbookId.length <= 0) {
      return null;
    }
    try {
      return await this.ebookDataManager.getEBookById(identity.localEbookId);
    } catch (error) {
      logger.warn(TAG, `读取本地 TXT 电子书失败: ebookId=${identity.localEbookId}, error=${String(error)}`);
      return null;
    }
  }

  private buildNovelChapterRequest(identity: RemoteReadAloudBookIdentity, chapterIndex: number): LegadoChapter | null {
    const chapter = identity.chapters[chapterIndex];
    if (!chapter) {
      return null;
    }
    const originalChapter = NovelAdapter.getOriginalChapter(chapter);
    if (originalChapter) {
      return originalChapter;
    }
    return {
      id: chapter.id || `chapter_${chapterIndex}`,
      bookUrl: identity.bookUrl,
      url: chapter.id || '',
      title: chapter.title || `第 ${chapterIndex + 1} 章`,
      index: chapterIndex
    };
  }

  private async loadScopedReplaceRuleIds(bookId: string): Promise<string[] | null> {
    if (!bookId || bookId.length <= 0) {
      return null;
    }
    const abilityContext = uiContextManager.getAbilityContext();
    if (!abilityContext) {
      return null;
    }
    try {
      const store = await preferences.getPreferences(abilityContext, NOVEL_BOOK_RULE_SETTINGS_STORE);
      const raw = await store.get(`${NOVEL_BOOK_REPLACE_RULE_IDS_PREFIX}${bookId}`, '') as string;
      if (!raw || raw.length <= 0) {
        return null;
      }
      const parsed = SafeUtils.parseArr(raw) as Array<string>;
      if (!Array.isArray(parsed)) {
        return null;
      }
      const result: string[] = [];
      for (let index = 0; index < parsed.length; index++) {
        const item = parsed[index];
        if (typeof item === 'string' && item.length > 0) {
          result.push(item);
        }
      }
      return result.length > 0 ? result : null;
    } catch (error) {
      logger.warn(TAG, `读取书籍专属净化规则失败: bookId=${bookId}, error=${String(error)}`);
      return null;
    }
  }

  private async processNovelContent(
    rawContent: string,
    chapterTitle: string,
    bookTitle: string,
    sourceId: string,
    bookId: string
  ): Promise<string> {
    const enabledRuleIds = await this.loadScopedReplaceRuleIds(bookId);
    const processor = getNovelContentProcessor();
    const config: ContentProcessConfig = {
      useReplace: true,
      chineseConvert: 0,
      reSegment: false,
      includeTitle: true,
      paragraphIndent: '',
      sourceId,
      enabledRuleIds: enabledRuleIds ?? undefined
    };
    return processor.processContent(rawContent, chapterTitle, bookTitle, config).content;
  }
}

export function getRemoteReadAloudCacheService(): RemoteReadAloudCacheService {
  return RemoteReadAloudCacheService.getInstance();
}
