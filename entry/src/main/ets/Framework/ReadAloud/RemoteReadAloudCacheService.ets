import fs from '@ohos.file.fs';
import { util } from '@kit.ArkTS';
import { preferences } from '@kit.ArkData';
import { logger } from '../../Utils/Logger';
import { uiContextManager } from '../Managers/UIContextManager';
import { UnifiedChapter, UnifiedContent, UnifiedContentType } from '../../Models/UnifiedContentModels';
import {
  DEFAULT_REMOTE_READ_ALOUD_SETTINGS,
  DEFAULT_TEXT_READER_SETTINGS,
  ReadAloudEngineType,
  ReadAloudSettings,
  RemoteReadAloudSettings,
  TextReaderSettings,
  mergeRemoteReadAloudSettings,
  normalizeReadAloudSettings
} from '../../Models/TextReaderModels';
import { SettingKeys, SettingsManager } from '../Managers/SettingsManager';
import { loadGlobalReadAloudSettings, persistGlobalReadAloudSettings } from './ReadAloudSettingsStore';
import { ReadAloudBackendFactory, ReadAloudPrecacheProgressSnapshot } from './ReadAloudBackends';
import { ReadAloudController } from './ReadAloudController';
import { ReadAloudSessionContext } from './ReadAloudTypes';
import { getNovelSourceManager } from '../Novel/NovelSourceManager';
import { getNovelChapterCacheManager } from '../Novel/NovelChapterCacheManager';
import { getNovelContentProcessor, ContentProcessConfig } from '../Novel/NovelContentProcessor';
import { LegadoChapter } from '../Novel/LegadoSourceTypes';
import { EBook, EBookFormat } from '../../Models/EBookModels';
import { EBookDataManager } from '../Data/EBookDataManager';
import { EBookAdapter, NovelAdapter } from '../Adapters/UnifiedContentAdapter';
import {
  buildLocalTextNovelBookId,
  buildNovelReaderParamsFromTxtEBook,
  LOCAL_TXT_NOVEL_SOURCE_ID
} from '../Adapters/LocalTextNovelAdapter';

const TAG = 'RemoteReadAloudCacheService';
const NOVEL_BOOK_REPLACE_RULE_IDS_PREFIX = 'book_replace_rule_ids_';
const NOVEL_BOOK_RULE_SETTINGS_STORE = 'novel_book_rule_settings';
const REMOTE_READ_ALOUD_CACHE_ROOT_DIR = 'read_aloud_remote';

interface RemoteTtsManifestSegmentRecord {
  filePath: string;
  bytes: number;
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
}

interface RemoteReadAloudAllReferenceSnapshot {
  segmentAudioPaths: Set<string>;
  segmentMetaPaths: Set<string>;
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

function safeReadJson<T>(path: string): T | null {
  if (!path || !fs.accessSync(path)) {
    return null;
  }
  try {
    const text = new util.TextDecoder('utf-8').decodeToString(readFileBytes(path));
    return JSON.parse(text) as T;
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

function safeStatSize(path: string): number {
  try {
    if (!path || !fs.accessSync(path)) {
      return 0;
    }
    const stat = fs.statSync(path);
    return stat.isFile() ? stat.size : 0;
  } catch (_error) {
    return 0;
  }
}

function sumDirectoryBytes(path: string): number {
  try {
    if (!path || !fs.accessSync(path)) {
      return 0;
    }
    const stat = fs.statSync(path);
    if (stat.isFile()) {
      return stat.size;
    }
    let total = 0;
    const children = fs.listFileSync(path);
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
    if (!path || !fs.accessSync(path)) {
      return;
    }
    const stat = fs.statSync(path);
    if (stat.isFile()) {
      fs.unlinkSync(path);
      return;
    }
    const children = fs.listFileSync(path);
    for (let index = 0; index < children.length; index++) {
      deleteDirRecursive(`${path}/${children[index]}`);
    }
    fs.rmdirSync(path);
  } catch (error) {
    logger.warn(TAG, `删除目录失败: path=${path}, error=${String(error)}`);
  }
}

function deleteFileIfExists(path: string): void {
  try {
    if (path && fs.accessSync(path)) {
      fs.unlinkSync(path);
    }
  } catch (error) {
    logger.warn(TAG, `删除文件失败: path=${path}, error=${String(error)}`);
  }
}

function cleanupEmptyParentDirs(path: string, stopPath: string): void {
  let current = path;
  while (current.length > 0 && current.startsWith(stopPath) && current !== stopPath) {
    try {
      if (!fs.accessSync(current)) {
        const nextSlash = current.lastIndexOf('/');
        if (nextSlash <= 0) {
          return;
        }
        current = current.substring(0, nextSlash);
        continue;
      }
      const stat = fs.statSync(current);
      if (!stat.isDirectory()) {
        return;
      }
      const children = fs.listFileSync(current);
      if (children.length > 0) {
        return;
      }
      fs.rmdirSync(current);
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
    if (!fs.accessSync(bookRootPath)) {
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
      currentTotalSegments += descriptor.segmentCount;
      currentLatestUpdatedAt = Math.max(currentLatestUpdatedAt, descriptor.updatedAt);
      currentMergedAudioBytesTotal += descriptor.mergedFileBytes;
      if (descriptor.mergedFileBytes > 0) {
        currentMergedAudioCount += 1;
      }
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
    if (!fs.accessSync(bookRootPath)) {
      return;
    }
    const currentReferences = this.collectSegmentReferencesFromBookRoot(bookRootPath);
    deleteDirRecursive(bookRootPath);
    this.cleanupUnreferencedSharedSegments(currentReferences);
    logger.info(TAG, `已清理当前书籍远程听书缓存: bookId=${identity.bookId}`);
  }

  async clearChapterCache(content: UnifiedContent | null, chapterIndex: number): Promise<void> {
    const identity = this.resolveBookIdentity(content);
    if (!identity.supported) {
      return;
    }
    const chapterRootPath = `${this.buildBookRootPath(identity.bookId)}/chapter_${chapterIndex}`;
    if (!fs.accessSync(chapterRootPath)) {
      return;
    }
    const currentReferences = this.collectSegmentReferencesFromBookRoot(chapterRootPath);
    deleteDirRecursive(chapterRootPath);
    this.cleanupUnreferencedSharedSegments(currentReferences);
    logger.info(TAG, `已清理章节远程听书缓存: bookId=${identity.bookId}, chapterIndex=${chapterIndex}`);
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

    const baseSettings = loadGlobalReadAloudSettings(this.settingsManager);
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
      const nextSnapshot = JSON.parse(JSON.stringify(baseSnapshot)) as TextReaderSettings;
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
        currentLastUpdatedAt: 0
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

  private collectManifestDescriptors(rootPath: string): RemoteReadAloudManifestDescriptor[] {
    const result: RemoteReadAloudManifestDescriptor[] = [];
    this.walkManifests(rootPath, result);
    return result;
  }

  private walkManifests(path: string, output: RemoteReadAloudManifestDescriptor[]): void {
    try {
      if (!path || !fs.accessSync(path)) {
        return;
      }
      const stat = fs.statSync(path);
      if (stat.isFile()) {
        if (!path.endsWith('/manifest.json') && !path.endsWith('\\manifest.json')) {
          return;
        }
        const manifest = safeReadJson<RemoteTtsManifestRecord>(path);
        if (!manifest || !Array.isArray(manifest.segments)) {
          return;
        }
        const mergedFilePath = manifest.mergedFilePath || '';
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
            .filter((segmentPath: string) => !!segmentPath && segmentPath.length > 0)
        });
        return;
      }
      const children = fs.listFileSync(path);
      for (let index = 0; index < children.length; index++) {
        this.walkManifests(`${path}/${children[index]}`, output);
      }
    } catch (_error) {
    }
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
        const dotIndex = segmentPath.lastIndexOf('.');
        const metaPath = dotIndex > 0 ? `${segmentPath.substring(0, dotIndex)}.json` : `${segmentPath}.json`;
        segmentMetaPaths.add(metaPath);
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
      return this.processNovelContent(
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
    return this.processNovelContent(rawContent, chapterTitle, identity.bookTitle, identity.sourceId, identity.bookId);
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
      const parsed = JSON.parse(raw) as Array<string>;
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
