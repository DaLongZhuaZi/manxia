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
 * 漫画导入完成事件的载荷
 */
export class MangaImportCompletedPayload implements IEventPayload {
  public importedCount: number;
  public totalCount: number;
  constructor(importedCount: number, totalCount: number) {
    this.importedCount = importedCount;
    this.totalCount = totalCount;
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
 * 漫画删除事件的载荷
 */
export class MangaDeletedPayload implements IEventPayload {
  public mangaId: string;
  constructor(mangaId: string) {
    this.mangaId = mangaId;
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

// =================================================================
// 3. 全局游戏事件常量
//    使用接口来定义GameEvent对象的结构，确保类型安全。
// =================================================================

/**
 * GameEvent 常量对象的类型接口
 */
interface GameEventConstants {
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
  // 文件导入
  FILE_IMPORT_REQUESTED: string;
  // 封面选择
  COVER_SELECTION_COMPLETED: string;
}

export const GameEvent: GameEventConstants = {
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

  // --- 文件导入事件 ---
  FILE_IMPORT_REQUESTED: 'fileImportRequested',
  
  // --- 封面选择事件 ---
  COVER_SELECTION_COMPLETED: 'coverSelectionCompleted',
};

// =================================================================
// 4. EventBus 类实现 (保持不变)
// =================================================================

type EventCallback = (payload: IEventPayload) => void;

class EventBus {
  private static instance: EventBus;
  private listeners: Record<string, Array<EventCallback>> = {};

  private constructor() {}

  public static getInstance(): EventBus {
    if (!EventBus.instance) {
      EventBus.instance = new EventBus();
    }
    return EventBus.instance;
  }

  public subscribe(event: string, callback: EventCallback): void {
    if (!this.listeners[event]) {
      this.listeners[event] = [];
    }
    this.listeners[event].push(callback);
  }

  public unsubscribe(event: string, callback: EventCallback): void {
    const eventListeners: Array<EventCallback> | undefined = this.listeners[event];
    if (eventListeners) {
      this.listeners[event] = eventListeners.filter(cb => cb !== callback);
    }
  }

  public publish(event: string, payload: IEventPayload): void {
    const eventListeners: Array<EventCallback> | undefined = this.listeners[event];
    if (eventListeners && eventListeners.length > 0) {
      for (const callback of eventListeners) {
        try {
          callback(payload);
        } catch (error) {
          logger.error('EventBus', `Event listener for [${event}] failed: ${(error as Error).message}`);
        }
      }
    }
  }

  public emit(event: string, payload: IEventPayload): void {
    this.publish(event, payload);
  }
}

export const eventBus = EventBus.getInstance();
