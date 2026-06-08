// 文件路径: src/main/ets/Framework/Debug/ConsolePanel.ets
/**
 * Console面板
 * 一个独立的、集成的调试工具，提供日志查看、性能监控、实体信息和命令执行功能。
 */

import { logger, LogLevel } from '../../Utils/Logger';
import { logCollector, LogEntry, LogFilter } from './LogCollector';
import { performanceAnalyzer, PerformanceMetrics, SystemMetrics } from './PerformanceAnalyzer';
import { HidebugPerformanceCollector, HidebugPerformanceData } from './HidebugPerformanceCollector';
import { PerformanceChart, ChartType, ChartConfig } from '../Components/PerformanceChart';
import { hidebug } from '@kit.PerformanceAnalysisKit';
import { uiContextManager } from '../Managers/UIContextManager';

const CONSOLE_PANEL_TAG = 'ConsolePanel';

/**
 * Console面板标签页枚举
 */
export enum ConsolePanelTab {
  DEBUG = 'debug',
  LOGS = 'logs',
  PERFORMANCE = 'performance',
  SETTINGS = 'settings'
}

/**
 * Console面板设置接口
 */
export interface ConsolePanelSettings {
  autoScroll: boolean;
  maxLogEntries: number;
  showTimestamp: boolean;
  logLevel: LogLevel;
  enableLogCollection: boolean;
  refreshInterval: number;
  entityCount: number;
  activeEntities: number;
}

/**
 * Console面板管理器
 * 一个独立的、集成的调试工具，提供日志查看、性能监控、实体信息和命令执行功能。
 */
export class ConsolePanel {
  private static instance: ConsolePanel;
  private _isVisible: boolean = false;
  private currentTab: ConsolePanelTab = ConsolePanelTab.LOGS;
  private settings: ConsolePanelSettings;
  private logFilter: LogFilter = {};
  private commandHistory: string[] = [];
  private maxCommandHistory: number = 50;
  private refreshTimer: number | null = null;
  private logUpdateListeners: (() => void)[] = [];
  private isDirty: boolean = false;

  private constructor() {
    this.settings = {
      autoScroll: true,
      maxLogEntries: 1000,
      showTimestamp: true,
      logLevel: LogLevel.DEBUG,
      enableLogCollection: true,
      refreshInterval: 1000, // 1秒刷新一次
      entityCount: 0,
      activeEntities: 0
    };
    logCollector.setEnabled(true);
    this.loadSettings();
    this.setupLogListener();
    logger.info(CONSOLE_PANEL_TAG, '✅ ConsolePanel 已独立初始化');
  }

  public static getInstance(): ConsolePanel {
    if (!ConsolePanel.instance) {
      ConsolePanel.instance = new ConsolePanel();
    }
    return ConsolePanel.instance;
  }

  // --- 公共接口 ---

  public toggle(): void {
    this._isVisible = !this._isVisible;
    this.updateTimerState();
    logger.debug(CONSOLE_PANEL_TAG, `Console面板已 ${this._isVisible ? '显示' : '隐藏'}`);
  }

  public show(): void {
    if (!this._isVisible) {
      this._isVisible = true;
      this.updateTimerState();
    }
  }

  public hide(): void {
    if (this._isVisible) {
      this._isVisible = false;
      this.updateTimerState();
    }
  }

  public isVisible(): boolean {
    return this._isVisible;
  }

  public switchTab(tab: ConsolePanelTab): void {
    this.currentTab = tab;
    logger.debug(CONSOLE_PANEL_TAG, `切换到标签页: ${tab}`);
  }

  public getCurrentTab(): ConsolePanelTab {
    return this.currentTab;
  }

  // --- 数据获取方法 (新的数据源) ---

  public getEntityNames(): string[] {
    // 移除对Game目录的依赖，返回空数组
    return [];
  }

  public getPerformanceMetrics(): PerformanceMetrics {
    return performanceAnalyzer.getMetrics();
  }

  public getSystemPerformance(): SystemMetrics[] {
    return performanceAnalyzer.getMetrics().systems;
  }

  public getFilteredLogs(): LogEntry[] {
    return logCollector.getFilteredLogs(this.logFilter);
  }

  public getLogStats(): Record<string, number> {
    return logCollector.getLogStats();
  }

  public getSettings(): ConsolePanelSettings {
    return {
      autoScroll: this.settings.autoScroll,
      maxLogEntries: this.settings.maxLogEntries,
      showTimestamp: this.settings.showTimestamp,
      logLevel: this.settings.logLevel,
      enableLogCollection: this.settings.enableLogCollection,
      refreshInterval: this.settings.refreshInterval,
      entityCount: this.settings.entityCount,
      activeEntities: this.settings.activeEntities
    };
  }

  // --- 操作方法 ---

  public setLogFilter(filter: LogFilter): void {
    this.logFilter = filter;
    this.notifyLogUpdate();
  }

  public clearLogs(): void {
    logCollector.clearLogs();
    this.notifyLogUpdate();
    logger.info(CONSOLE_PANEL_TAG, '日志已清空');
  }

  public updateSettings(newSettings: Partial<ConsolePanelSettings>): void {
    // 逐个更新设置属性，避免使用Object.assign
    if (newSettings.autoScroll !== undefined) {
      this.settings.autoScroll = newSettings.autoScroll;
    }
    if (newSettings.maxLogEntries !== undefined) {
      this.settings.maxLogEntries = newSettings.maxLogEntries;
    }
    if (newSettings.showTimestamp !== undefined) {
      this.settings.showTimestamp = newSettings.showTimestamp;
    }
    if (newSettings.logLevel !== undefined) {
      this.settings.logLevel = newSettings.logLevel;
    }
    if (newSettings.enableLogCollection !== undefined) {
      this.settings.enableLogCollection = newSettings.enableLogCollection;
    }
    if (newSettings.refreshInterval !== undefined) {
      this.settings.refreshInterval = newSettings.refreshInterval;
    }
    if (newSettings.entityCount !== undefined) {
      this.settings.entityCount = newSettings.entityCount;
    }
    if (newSettings.activeEntities !== undefined) {
      this.settings.activeEntities = newSettings.activeEntities;
    }
    
    // 应用设置变更
    if (newSettings.enableLogCollection !== undefined) {
      logCollector.setEnabled(newSettings.enableLogCollection);
    }
    
    if (newSettings.maxLogEntries !== undefined) {
      logCollector.setMaxLogCount(newSettings.maxLogEntries);
    }
    
    if (newSettings.refreshInterval !== undefined) {
      this.stopRefreshTimer();
      if (this._isVisible) {
        this.startRefreshTimer();
      }
    }
    
    this.saveSettings();
    this.notifyLogUpdate();
    logger.debug(CONSOLE_PANEL_TAG, '设置已更新');
  }

  public async executeCommand(command: string): Promise<string> {
    if (!command.trim()) return '';
    this.addToCommandHistory(command);
    const parts = command.trim().split(' ');
    const cmd: string = parts[0].toLowerCase();

    try {
      switch (cmd) {
        case 'help':
          return this.getHelpText();
        case 'clear':
          this.clearLogs();
          return '日志已清空';
        case 'entities':
          const names = this.getEntityNames();
          return `实体列表 (${names.length}个):\n${names.join('\n') || '无'}`;
        case 'performance':
          const perf = this.getSystemPerformance();
          if (perf.length === 0) return '暂无性能数据。';
          return `系统性能:\n${perf.map(p => `${p.name}: ${typeof p.averageTime === 'number' ? p.averageTime.toFixed(2) : '未知'}ms`).join('\n')}`;
        case 'config':
          // ... (config 命令逻辑保持不变)
          return 'config 命令待实现';
        default:
          return `未知命令: ${cmd}. 输入 'help' 查看可用命令。`;
      }
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error(CONSOLE_PANEL_TAG, `命令执行错误: ${errorMessage}`);
      return `命令执行错误: ${errorMessage}`;
    }
  }

  // --- 监听与刷新 ---

  public addLogUpdateListener(listener: () => void): void {
    this.logUpdateListeners.push(listener);
  }

  public removeLogUpdateListener(listener: () => void): void {
    const index = this.logUpdateListeners.indexOf(listener);
    if (index >= 0) {
      this.logUpdateListeners.splice(index, 1);
    }
  }

  // --- 私有方法 ---

  private updateTimerState(): void {
    if (this._isVisible) {
      this.startRefreshTimer();
    } else {
      this.stopRefreshTimer();
    }
  }

  private setupLogListener(): void {
    logCollector.addListener((entry: LogEntry) => {
      this.isDirty = true;
    });
  }

  private notifyLogUpdate(): void {
    this.logUpdateListeners.forEach(listener => {
      try {
        listener();
      } catch (e) {}
    });
  }

  private startRefreshTimer(): void {
    if (this.refreshTimer !== null) return;
    // 使用setTimeout替代setInterval以符合ArkTS限制
    const scheduleNext = (): void => {
      this.refreshTimer = setTimeout(() => {
        if (this.isDirty) {
          this.notifyLogUpdate();
          this.isDirty = false;
        }
        if (this._isVisible && this.refreshTimer !== null) {
          scheduleNext();
        }
      }, this.settings.refreshInterval);
    };
    scheduleNext();
  }

  private stopRefreshTimer(): void {
    if (this.refreshTimer !== null) {
      clearTimeout(this.refreshTimer);
      this.refreshTimer = null;
    }
  }

  private addToCommandHistory(command: string): void {
    if (this.commandHistory.length === 0 || this.commandHistory[this.commandHistory.length - 1] !== command) {
      this.commandHistory.push(command);
      if (this.commandHistory.length > this.maxCommandHistory) {
        this.commandHistory.shift();
      }
    }
  }

  private getHelpText(): string {
    return [
      '=== Console 命令帮助 ===',
      'entities - 显示原生引擎中的实体列表',
      'performance - 显示系统性能数据',
      'clear - 清空日志',
      'help - 显示此帮助信息'
    ].join('\n');
  }

  private loadSettings(): void {
    try {
      // 使用默认设置，不再依赖配置管理器
      logger.debug(CONSOLE_PANEL_TAG, '使用默认设置');
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.warn(CONSOLE_PANEL_TAG, '加载设置失败，使用默认设置', errorMessage);
    }
  }

  private saveSettings(): void {
    try {
      // 设置保存功能已移除，不再依赖配置管理器
      logger.debug(CONSOLE_PANEL_TAG, '设置保存功能已禁用');
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error(CONSOLE_PANEL_TAG, '保存设置失败', errorMessage);
    }
  }
}

export const consolePanel = ConsolePanel.getInstance();

@Component
export struct ConsolePanelComponent {
  @State private isVisible: boolean = false;
  @State private currentTab: string = 'logs';
  @State private logs: LogEntry[] = [];
  @State private filteredLogs: LogEntry[] = [];
  @State private logFilter: LogLevel = LogLevel.DEBUG;
  @State private performanceMetrics: PerformanceMetrics | null = null;
  @State private hidebugData: HidebugPerformanceData | null = null;
  @State private isChartsEnabled: boolean = false;
  @State private chartConfigs: ChartConfig[] = [];
  
  private consolePanel: ConsolePanel = ConsolePanel.getInstance();
  private performanceAnalyzer: PerformanceMetrics | null = null;
  private hidebugCollector: HidebugPerformanceCollector = HidebugPerformanceCollector.getInstance();
  private refreshTimer: number = -1;

  build() {
    // Component build logic here
  }
}


