import { logger } from '../Utils/Logger';
import type { PerformanceWarning } from './Debug/PerformanceAnalyzer';

// 移除对Game目录的依赖，使用简单的类型定义
export interface GameState {
  isRunning: boolean;
  currentLevel: number;
  score: number;
}

// =================================================================
// 1. 基础接口和类型定义
// =================================================================

/**
 * 所有事件载荷的基础接口，用于类型约束。
 */
export interface IEventPayload {}

/**
 * 封面更新事件的payload
 */
export interface CoverChangedPayload extends IEventPayload {
  bookId: string;
  coverPath: string;
}

/**
 * 定义一个通用的实体ID类型，它就是一个数字。
 */
export type EntityId = number;

// =================================================================
// 2. 事件载荷 (Payload) 定义
//    这里定义了所有模块可能用到的事件数据结构。
// =================================================================

/**
 * C++ 游戏引擎状态更新事件的载荷。
 */
export class GameStateUpdatePayload implements IEventPayload {
  public state: GameState;
  constructor(state: GameState) {
    this.state = state;
  }
}

/**
 * Canvas 渲染画布就绪事件的载荷。
 */
export class CanvasReadyPayload implements IEventPayload {
  public context: CanvasRenderingContext2D;
  public width: number;
  public height: number;
  constructor(context: CanvasRenderingContext2D, width: number, height: number) {
    this.context = context;
    this.width = width;
    this.height = height;
  }
}

/**
 * Canvas 点击事件的载荷。
 */
export class CanvasClickPayload implements IEventPayload {
  public x: number;
  public y: number;
  constructor(x: number, y: number) {
    this.x = x;
    this.y = y;
  }
}

/**
 * [已恢复] 性能警告事件的载荷。
 */
export class PerformanceWarningPayload implements IEventPayload {
  public warning: PerformanceWarning;
  constructor(warning: PerformanceWarning) {
    this.warning = warning;
  }
}

/**
 * Console 面板可见性切换事件的载荷。
 */
export class ConsolePanelTogglePayload implements IEventPayload {
  public visible: boolean;
  constructor(visible: boolean) {
    this.visible = visible;
  }
}

/**
 * 资源加载失败事件的载荷。
 */
export class ResourceLoadFailedPayload implements IEventPayload {
  public resourceId: string;
  public error: Error;
  constructor(resourceId: string, error: Error) {
    this.resourceId = resourceId;
    this.error = error;
  }
}

/**
 * 通用错误事件的载荷
 */
export class ErrorEventPayload implements IEventPayload {
  public error: Error;
  constructor(error: Error) {
    this.error = error;
  }
}

/**
 * 基础事件载荷（用于不需要额外数据的事件）
 */
export class BasePayload implements IEventPayload {
  constructor() {}
}

/**
 * 听书状态事件载荷
 */
export class ReadAloudStatePayload implements IEventPayload {
  public playbackState: string;
  public reason: string;
  public engineType: string;
  public bookId: string;
  public chapterIndex: number;
  public pageIndex: number;
  public currentCharIndex: number;
  public chunkStartCharIndex: number;
  public chunkEndCharIndex: number;
  public currentPositionMs: number;
  public totalDurationMs: number;

  constructor(
    playbackState: string,
    reason: string,
    engineType: string,
    bookId: string,
    chapterIndex: number,
    pageIndex: number,
    currentCharIndex: number,
    chunkStartCharIndex: number,
    chunkEndCharIndex: number,
    currentPositionMs: number,
    totalDurationMs: number
  ) {
    this.playbackState = playbackState;
    this.reason = reason;
    this.engineType = engineType;
    this.bookId = bookId;
    this.chapterIndex = chapterIndex;
    this.pageIndex = pageIndex;
    this.currentCharIndex = currentCharIndex;
    this.chunkStartCharIndex = chunkStartCharIndex;
    this.chunkEndCharIndex = chunkEndCharIndex;
    this.currentPositionMs = currentPositionMs;
    this.totalDurationMs = totalDurationMs;
  }
}

/**
 * 漫画导入完成事件的载荷
 */
export class ReadAloudCacheUpdatedPayload implements IEventPayload {
  public bookId: string;
  public chapterIndex: number;
  public reason: string;
  public remoteDigest: string;

  constructor(bookId: string, chapterIndex: number, reason: string, remoteDigest: string = '') {
    this.bookId = bookId;
    this.chapterIndex = chapterIndex;
    this.reason = reason;
    this.remoteDigest = remoteDigest;
  }
}

/**
 * 漫画缓存更新事件的载荷
 */
export class MangaCacheUpdatedPayload implements IEventPayload {
  public mangaId: string;
  public chapterId: string;
  public sourceId: number;
  public archivePath: string;
  public reason: string;

  constructor(mangaId: string, chapterId: string, sourceId: number, archivePath: string, reason: string) {
    this.mangaId = mangaId;
    this.chapterId = chapterId;
    this.sourceId = sourceId;
    this.archivePath = archivePath;
    this.reason = reason;
  }
}

export class MangaImportCompletedPayload implements IEventPayload {
  public importedCount: number;
  public totalCount: number;
  constructor(importedCount: number, totalCount: number) {
    this.importedCount = importedCount;
    this.totalCount = totalCount;
  }
}

/**
 * 图源运行配置变更事件载荷
 */
export class SourceRuntimeConfigChangedPayload implements IEventPayload {
  public sourceId: number;
  public sourceName: string;
  public baseUrl: string;
  public reason: string;

  constructor(sourceId: number, sourceName: string, baseUrl: string, reason: string) {
    this.sourceId = sourceId;
    this.sourceName = sourceName;
    this.baseUrl = baseUrl;
    this.reason = reason;
  }
}

export function buildSourceRuntimeConfigVersionKey(sourceId: number): string {
  return `source_runtime_config_version_${sourceId}`;
}

export type RemoteLibraryProvider = 'suwayomi' | 'komga';

export class RemoteLibraryConfigChangedPayload implements IEventPayload {
  public provider: RemoteLibraryProvider;
  public reason: string;
  public timestamp: number;

  constructor(provider: RemoteLibraryProvider, reason: string) {
    this.provider = provider;
    this.reason = reason;
    this.timestamp = Date.now();
  }
}

/**
 * 文件导入请求事件的载荷
 */
export class FileImportRequestedPayload implements IEventPayload {
  public fileUri: string;
  public fileType: string;
  constructor(fileUri: string, fileType: string) {
    this.fileUri = fileUri;
    this.fileType = fileType;
  }
}

/**
 * 文件编辑器文档事件载荷
 */
export class FileEditorDocumentPayload implements IEventPayload {
  public sessionId: string;
  public origin: string;
  public targetType: string;
  public targetId: string;
  public targetName: string;
  public filePath: string;
  public fileName: string;
  public language: string;
  public content: string;
  public isDirty: boolean;
  public savedAt: number;
  public linkedApplied: boolean;
  public message: string;

  constructor(
    sessionId: string,
    origin: string,
    targetType: string,
    targetId: string,
    targetName: string,
    filePath: string,
    fileName: string,
    language: string,
    content: string,
    isDirty: boolean,
    savedAt: number,
    linkedApplied: boolean,
    message: string
  ) {
    this.sessionId = sessionId;
    this.origin = origin;
    this.targetType = targetType;
    this.targetId = targetId;
    this.targetName = targetName;
    this.filePath = filePath;
    this.fileName = fileName;
    this.language = language;
    this.content = content;
    this.isDirty = isDirty;
    this.savedAt = savedAt;
    this.linkedApplied = linkedApplied;
    this.message = message;
  }
}

/**
 * 文件编辑器能力检查事件载荷
 */
export class FileEditorCapabilityPayload implements IEventPayload {
  public sessionId: string;
  public readyCount: number;
  public partialCount: number;
  public unavailableCount: number;
  public checkedAt: number;
  public summary: string;

  constructor(
    sessionId: string,
    readyCount: number,
    partialCount: number,
    unavailableCount: number,
    checkedAt: number,
    summary: string
  ) {
    this.sessionId = sessionId;
    this.readyCount = readyCount;
    this.partialCount = partialCount;
    this.unavailableCount = unavailableCount;
    this.checkedAt = checkedAt;
    this.summary = summary;
  }
}

/**
 * 漫画删除事件的载荷
 */
export class MangaDeletedPayload implements IEventPayload {
  public mangaId: string;
  constructor(mangaId: string) {
    this.mangaId = mangaId;
  }
}

/**
 * 漫画收藏状态变化事件的载荷
 */
export class MangaFavoriteChangedPayload implements IEventPayload {
  public comicId: string;
  public externalId: string;
  public sourceId: string;
  public sourceName: string;
  public sourcePkg: string;
  public isFavorite: boolean;

  constructor(
    comicId: string,
    externalId: string,
    sourceId: string,
    sourceName: string,
    sourcePkg: string,
    isFavorite: boolean
  ) {
    this.comicId = comicId;
    this.externalId = externalId;
    this.sourceId = sourceId;
    this.sourceName = sourceName;
    this.sourcePkg = sourcePkg;
    this.isFavorite = isFavorite;
  }
}

/**
 * 封面选择完成事件的载荷
 */
export class CoverSelectionCompletedPayload implements IEventPayload {
  public mangaId: string;
  public chapterId: string;
  public selectedPath: string;
  constructor(mangaId: string, chapterId: string, selectedPath: string) {
    this.mangaId = mangaId;
    this.chapterId = chapterId;
    this.selectedPath = selectedPath;
  }
}

/**
 * 分布式接续被触发的事件载荷
 */
export class ContinuationTriggeredPayload implements IEventPayload {
  public sessionId: string;
  public bookId: string;
  public chapterIndex: number;
  public pageIndex: number;
  public offset: number;
  public sourceType: string;
  public isLocal: boolean;
  
  constructor(
    sessionId: string,
    bookId: string,
    chapterIndex: number,
    pageIndex: number,
    offset: number,
    sourceType: string,
    isLocal: boolean
  ) {
    this.sessionId = sessionId;
    this.bookId = bookId;
    this.chapterIndex = chapterIndex;
    this.pageIndex = pageIndex;
    this.offset = offset;
    this.sourceType = sourceType;
    this.isLocal = isLocal;
  }
}

// =================================================================
// 3. 全局游戏事件常量
//    使用接口来定义GameEvent对象的结构，确保类型安全。
// =================================================================

/**
 * GameEvent 常量对象的类型接口
 */
interface GameEventConstants {
  // 应用生命周期
  APP_ENTER_FOREGROUND: string;
  APP_ENTER_BACKGROUND: string;
  // 核心游戏循环
  GAME_STATE_UPDATE: string;
  // UI 与渲染
  CANVAS_READY: string;
  CANVAS_CLICKED: string;
  // 调试与性能
  CONSOLE_PANEL_TOGGLED: string;
  PERFORMANCE_WARNING: string;
  // 资源管理
  RESOURCE_LOAD_FAILED: string;
  RESOURCE_INSTANCE_LIFECYCLE: string;
  // 导航
  PAGE_CHANGED: string;
  NAVIGATION_ERROR: string;
  // 导航生命周期
  NAVIGATION_CYCLE_CHANGED: string;
  PAGE_HEALTH_CHANGED: string;
  // 系统集成
  SYSTEM_MODE_CHANGED: string;
  SYSTEM_ERROR: string;
  // 依赖注入
  DEPENDENCY_RESOLVED: string;
  // 通用错误
  ERROR_OCCURRED: string;
  // 漫画数据
  MANGA_IMPORT_COMPLETED: string;
  MANGA_DELETED: string;
  MANGA_FAVORITE_CHANGED: string;
  MANGA_READING_PROGRESS_UPDATED: string;
  MANGA_CACHE_UPDATED: string;
  SOURCE_RUNTIME_CONFIG_CHANGED: string;
  REMOTE_LIBRARY_CONFIG_CHANGED: string;
  // 电子书数据
  EBOOK_UPDATED: string;
  EBOOK_COVER_CHANGED: string;
  EBOOK_LIST_REFRESH_NEEDED: string;
  // 小说数据
  NOVEL_UPDATED: string;
  NOVEL_COVER_CHANGED: string;
  NOVEL_LIST_REFRESH_NEEDED: string;
  // 听书状态
  READ_ALOUD_STARTED: string;
  READ_ALOUD_PAUSED: string;
  READ_ALOUD_STOPPED: string;
  READ_ALOUD_STATE_CHANGED: string;
  READ_ALOUD_CACHE_UPDATED: string;
  // 文件导入
  FILE_IMPORT_REQUESTED: string;
  FILE_EDITOR_SAVED: string;
  FILE_EDITOR_EXPORTED: string;
  FILE_EDITOR_CLOSED: string;
  FILE_EDITOR_CAPABILITY_AUDITED: string;
  // 封面选择
  COVER_SELECTION_COMPLETED: string;
  // 分布式
  CONTINUATION_TRIGGERED: string;
}

export const GameEvent: GameEventConstants = {
  // --- 应用生命周期事件 ---
  APP_ENTER_FOREGROUND: 'appEnterForeground',
  APP_ENTER_BACKGROUND: 'appEnterBackground',

  // --- 核心游戏循环事件 ---
  GAME_STATE_UPDATE: 'gameStateUpdate',

  // --- UI 与 渲染事件 ---
  CANVAS_READY: 'canvasReady',
  CANVAS_CLICKED: 'canvasClicked',

  // --- 调试与性能事件 [已恢复] ---
  CONSOLE_PANEL_TOGGLED: 'consolePanelToggled',
  PERFORMANCE_WARNING: 'performanceWarning',

  // --- 资源管理事件 ---
  RESOURCE_LOAD_FAILED: 'resourceLoadFailed',
  RESOURCE_INSTANCE_LIFECYCLE: 'resourceInstanceLifecycle',

  // --- 导航事件 ---
  PAGE_CHANGED: 'pageChanged',
  NAVIGATION_ERROR: 'navigationError',

  // --- 导航生命周期事件 ---
  NAVIGATION_CYCLE_CHANGED: 'navigationCycleChanged',
  PAGE_HEALTH_CHANGED: 'pageHealthChanged',

  // --- 系统集成事件 ---
  SYSTEM_MODE_CHANGED: 'systemModeChanged',
  SYSTEM_ERROR: 'systemError',

  // --- 依赖注入事件 ---
  DEPENDENCY_RESOLVED: 'dependencyResolved',

  // --- 通用错误事件 ---
  ERROR_OCCURRED: 'errorOccurred',

  // --- 漫画数据事件 ---
  MANGA_IMPORT_COMPLETED: 'mangaImportCompleted',
  MANGA_DELETED: 'mangaDeleted',
  MANGA_FAVORITE_CHANGED: 'mangaFavoriteChanged',
  MANGA_READING_PROGRESS_UPDATED: 'mangaReadingProgressUpdated',
  MANGA_CACHE_UPDATED: 'mangaCacheUpdated',
  SOURCE_RUNTIME_CONFIG_CHANGED: 'sourceRuntimeConfigChanged',
  REMOTE_LIBRARY_CONFIG_CHANGED: 'remoteLibraryConfigChanged',

  // --- 电子书数据事件 ---
  EBOOK_UPDATED: 'ebookUpdated',
  EBOOK_COVER_CHANGED: 'ebookCoverChanged',
  EBOOK_LIST_REFRESH_NEEDED: 'ebookListRefreshNeeded',

  // --- 小说数据事件 ---
  NOVEL_UPDATED: 'novelUpdated',
  NOVEL_COVER_CHANGED: 'novelCoverChanged',
  NOVEL_LIST_REFRESH_NEEDED: 'novelListRefreshNeeded',
  READ_ALOUD_STARTED: 'readAloudStarted',
  READ_ALOUD_PAUSED: 'readAloudPaused',
  READ_ALOUD_STOPPED: 'readAloudStopped',
  READ_ALOUD_STATE_CHANGED: 'readAloudStateChanged',
  READ_ALOUD_CACHE_UPDATED: 'readAloudCacheUpdated',

  // --- 文件导入事件 ---
  FILE_IMPORT_REQUESTED: 'fileImportRequested',
  FILE_EDITOR_SAVED: 'fileEditorSaved',
  FILE_EDITOR_EXPORTED: 'fileEditorExported',
  FILE_EDITOR_CLOSED: 'fileEditorClosed',
  FILE_EDITOR_CAPABILITY_AUDITED: 'fileEditorCapabilityAudited',
  
  // --- 封面选择事件 ---
  COVER_SELECTION_COMPLETED: 'coverSelectionCompleted',
  
  // --- 分布式协同事件 ---
  CONTINUATION_TRIGGERED: 'continuationTriggered',
};

// =================================================================
// 4. EventBus 类实现 (保持不变)
// =================================================================

type EventCallback = (payload: IEventPayload) => void;

class EventBus {
  private static instance: EventBus;
  private listeners: Map<string, Array<EventCallback>> = new Map<string, Array<EventCallback>>();

  private constructor() {}

  public static getInstance(): EventBus {
    if (!EventBus.instance) {
      EventBus.instance = new EventBus();
    }
    return EventBus.instance;
  }

  public subscribe(event: string, callback: EventCallback): void {
    const eventListeners = this.listeners.get(event);
    if (eventListeners) {
      if (eventListeners.includes(callback)) {
        return;
      }
      eventListeners.push(callback);
    } else {
      const newListeners: Array<EventCallback> = [];
      newListeners.push(callback);
      this.listeners.set(event, newListeners);
    }
  }

  public unsubscribe(event: string, callback: EventCallback): void {
    const eventListeners: Array<EventCallback> | undefined = this.listeners.get(event);
    if (eventListeners) {
      const nextListeners: Array<EventCallback> = eventListeners.filter(cb => cb !== callback);
      if (nextListeners.length > 0) {
        this.listeners.set(event, nextListeners);
      } else {
        this.listeners.delete(event);
      }
    }
  }

  public publish(event: string, payload: IEventPayload): void {
    const eventListeners: Array<EventCallback> | undefined = this.listeners.get(event);
    if (eventListeners && eventListeners.length > 0) {
      const listenerSnapshot: Array<EventCallback> = eventListeners.slice();
      for (const callback of listenerSnapshot) {
        try {
          callback(payload);
        } catch (error) {
          logger.error('EventBus', `Event listener for [${event}] failed: ${String(error)}`);
        }
      }
    }
  }

  public emit(event: string, payload: IEventPayload): void {
    this.publish(event, payload);
  }
}

export const eventBus = EventBus.getInstance();
