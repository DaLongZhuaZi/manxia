import { SafeFileUtils } from 'manxia_core/src/main/ets/Utils/SafeFileUtils';
// 文件路径: src/main/ets/Framework/Components/ConsolePanel.ets
/**
 * 控制台面板组件
 * 提供调试日志、性能分析、系统指标等功能，支持传统动画系统
 */
 
import { consolePanel, ConsolePanelTab, ConsolePanelSettings } from '../Debug/ConsolePanel';
import { logCollector, LogEntry, LogFilter } from 'manxia_core/src/main/ets/Framework/Debug/LogCollector';
import { logger, LogLevel } from 'manxia_core/src/main/ets/Utils/Logger';
import { performanceAnalyzer, PerformanceMetrics, SystemMetrics } from '../Debug/PerformanceAnalyzer';
import { HidebugPerformanceCollector, HidebugPerformanceData } from '../Debug/HidebugPerformanceCollector';
import { PerformanceChart, ChartType, ChartConfig } from './PerformanceChart';
import { hidebug } from '@kit.PerformanceAnalysisKit';
import pasteboard from '@ohos.pasteboard';
import fs from '@ohos.file.fs';
import { common } from '@kit.AbilityKit';
import { ThemeManager } from 'manxia_theme/src/main/ets/Framework/Managers/ThemeManager';
import { ThemeType } from 'manxia_theme/src/main/ets/Framework/Managers/ThemeManager';
import { ThemeAwareHelper, ThemeAwareState } from 'manxia_theme/src/main/ets/Framework/Components/ThemeAware';
import { FontAwareHelper, FontAwareState } from '../Components/FontAware';
import { TimeUtils } from 'manxia_core/src/main/ets/Framework/Utils/TimeUtils';


// 定义UI样式接口
interface ShadowStyle {
  radius: number;
  color: ResourceStr | string;
  offsetX: number;
  offsetY: number;
}

interface PaddingStyle {
  left?: number;
  right?: number;
  top?: number;
  bottom?: number;
}

interface GeneratedTypeLiteralInterface_3 {
  key: ConsolePanelTab;
  label: string;
}

interface GeneratedTypeLiteralInterface_1 {
  key: ConsolePanelTab;
  label: string;
}

interface GeneratedTypeLiteralInterface_2 {
  key: ConsolePanelTab;
  label: string;
}

@Component
export struct ConsolePanelComponent {
  @Link showConsolePanel: boolean;
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @State private isMinimized: boolean = true; // 默认为最小化状态（悬浮按钮）
  @State private currentTab: ConsolePanelTab = ConsolePanelTab.LOGS;
  @State private logs: LogEntry[] = [];
  @State private entityNames: string[] = [];
  @State private performanceMetrics: PerformanceMetrics | null = null;
  @State private hidebugData: HidebugPerformanceData | null = null;
  @State private isChartsEnabled: boolean = false;
  @State private chartConfigs: ChartConfig[] = [];
  @State private settings: ConsolePanelSettings | null = null;
  @State private commandInput: string = '';
  @State private commandOutput: string = '';
  @State private logFilter: LogFilter = {};
  @State private logStats: Record<string, number> = {};
  @State private expandedLogs: Set<number> = new Set<number>();
  @State private tabItems: Array<GeneratedTypeLiteralInterface_1> = [
    { key: ConsolePanelTab.DEBUG, label: '调试' },
    { key: ConsolePanelTab.LOGS, label: '日志' },
    { key: ConsolePanelTab.PERFORMANCE, label: '性能' },
    { key: ConsolePanelTab.SETTINGS, label: '设置' }
  ];

  // [修复] 遵循官方文档，使用offsetX/Y来控制当前偏移，positionX/Y来保存上次拖拽的最终位置
  @State offsetX: number = 300;
  @State offsetY: number = 600;
  @State positionX: number = 300;
  @State positionY: number = 600;

  // 主题相关状态
  @State private themeState: ThemeAwareState = new ThemeAwareState();
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private componentId: string = '';

  private scrollController: Scroller = new Scroller();
  private logUpdateListener: () => void = () => {};
  private hidebugCollector: HidebugPerformanceCollector = HidebugPerformanceCollector.getInstance();

  aboutToAppear() {
    this.settings = consolePanel.getSettings();
    this.logUpdateListener = () => this.loadData();
    consolePanel.addLogUpdateListener(this.logUpdateListener);

    // 初始化图表配置
    this.initializeChartConfigs();

    // 启动hidebug性能收集器
    this.hidebugCollector.enable();
    this.hidebugCollector.setCollectInterval(2000); // 2秒收集一次

    // 初始化主题感知
    this.componentId = `ConsolePanel_${Date.now()}_${Math.random()}`;
    this.themeManager.onThemeChange((theme: ThemeType) => {
      this.themeState.currentTheme = theme;
    });
    this.themeState.currentTheme = this.themeManager.getCurrentTheme();

    this.loadData();
  }

  aboutToDisappear() {
    consolePanel.removeLogUpdateListener(this.logUpdateListener);
    // 停止hidebug性能收集器
    this.hidebugCollector.disable();
    // 注意：由于我们没有保存回调函数的引用，这里无法正确移除
    // 在实际应用中，应该保存回调函数的引用以便正确清理
  }

  loadData(): void {
    switch (this.currentTab) {
      case ConsolePanelTab.DEBUG:
        this.entityNames = consolePanel.getEntityNames();
        break;
      case ConsolePanelTab.LOGS:
        this.logs = consolePanel.getFilteredLogs();
        this.logStats = consolePanel.getLogStats();
        if (this.settings?.autoScroll && this.logs.length > 0) {
          setTimeout((): void => { this.scrollController.scrollToIndex(this.logs.length - 1); }, 100);
        }
        break;
      case ConsolePanelTab.PERFORMANCE:
        this.performanceMetrics = consolePanel.getPerformanceMetrics();
        // 加载hidebug性能数据
        this.hidebugData = this.hidebugCollector.getCurrentData();
        break;
      case ConsolePanelTab.SETTINGS:
        this.settings = consolePanel.getSettings();
        break;
    }
  }

  executeCommand(): void {
    if (!this.commandInput.trim()) return;

    // 处理特殊调试命令
    const command = this.commandInput.trim().toLowerCase();
    switch (command) {
      case 'help':
      case '?':
        this.commandOutput = this.getHelpText();
        break;
      case 'clear':
      case 'cls':
        consolePanel.clearLogs();
        this.commandOutput = '日志已清空';
        break;
      case 'status':
        this.commandOutput = this.getSystemStatus();
        break;
      case 'memory':
        this.commandOutput = this.getMemoryInfo();
        break;
      case 'performance':
      case 'perf':
        this.commandOutput = this.getPerformanceInfo();
        break;
      case 'diagnosis':
      case 'diag':
        this.quickDiagnosis();
        this.commandOutput = '系统诊断已完成，请查看日志';
        break;
      case 'export-errors':
        this.generateErrorLogFile();
        this.commandOutput = '错误日志导出已开始';
        break;
      case 'export-all':
        this.exportAllLogs();
        this.commandOutput = '全部日志导出已开始';
        break;
      case 'copy-errors':
        this.copyErrorLogs();
        this.commandOutput = '错误日志已复制到剪贴板';
        break;
      case 'gc':
        this.clearMemoryCache();
        this.commandOutput = '内存清理已完成';
        break;
      case 'charts':
        this.isChartsEnabled = !this.isChartsEnabled;
        this.commandOutput = `性能图表已${this.isChartsEnabled ? '启用' : '禁用'}`;
        break;
      case 'hidebug':
        this.commandOutput = this.getHidebugInfo();
        break;
      default:
        this.commandOutput = consolePanel.executeCommand(this.commandInput).toString();
        break;
    }

    this.commandInput = '';
    this.loadData(); // 执行命令后刷新数据
  }

  // 初始化图表配置
  private initializeChartConfigs(): void {
    this.chartConfigs = [
      {
        type: ChartType.MEMORY,
        title: '内存使用',
        unit: 'MB',
        color: 'Color.Blue',
        warningThreshold: 512,
        errorThreshold: 1024,
        maxDataPoints: 50
      },
      {
        type: ChartType.CPU,
        title: 'CPU使用率',
        unit: '%',
        color: 'Color.Orange',
        warningThreshold: 70,
        errorThreshold: 90,
        maxDataPoints: 50
      },
      {
        type: ChartType.GC_COUNT,
        title: 'GC次数',
        unit: '次',
        color: 'Color.Green',
        warningThreshold: 10,
        errorThreshold: 20,
        maxDataPoints: 50
      },
      {
        type: ChartType.HEAP_SIZE,
        title: '堆大小',
        unit: 'MB',
        color: 'Color.Purple',
        warningThreshold: 256,
        errorThreshold: 512,
        maxDataPoints: 50
      }
    ];
  }

  // 获取帮助文本
  getHelpText(): string {
    return [
      '=== 调试命令帮助 ===',
      'help, ?          - 显示此帮助信息',
      'clear, cls       - 清空日志',
      'status           - 显示系统状态',
      'memory           - 显示内存信息',
      'performance, perf - 显示性能信息',
      'diagnosis, diag  - 执行系统诊断',
      'export-errors    - 导出错误日志到文件',
      'export-all       - 导出所有日志到文件',
      'copy-errors      - 复制错误日志到剪贴板',
      'gc               - 执行内存清理',
      'charts           - 切换性能图表显示',
      'hidebug          - 显示hidebug性能信息',
      '=================='
    ].join('\n');
  }

  // 获取hidebug性能信息
  getHidebugInfo(): string {
    if (!this.hidebugData) {
      return '暂无hidebug性能数据';
    }

    const memory = this.hidebugData.memory;
    const cpu = this.hidebugData.cpu;
    const gc = this.hidebugData.gc;
    const debug = this.hidebugData.debug;
    const summary = this.hidebugCollector.getPerformanceSummary();

    return [
      '=== Hidebug 性能信息 ===',
      `内存信息:`,
      `  PSS内存: ${(Number(memory.pss) / (1024 * 1024)).toFixed(1)} MB`,
      `  VSS内存: ${(Number(memory.vss) / (1024 * 1024)).toFixed(1)} MB`,
      `  堆内存大小: ${(Number(memory.nativeHeapSize) / (1024 * 1024)).toFixed(1)} MB`,
      `  堆已分配: ${(Number(memory.nativeHeapAllocatedSize) / (1024 * 1024)).toFixed(1)} MB`,
      `  堆空闲: ${(Number(memory.nativeHeapFreeSize) / (1024 * 1024)).toFixed(1)} MB`,
      memory.vmMemoryInfo ? `  VM堆总大小: ${(Number(memory.vmMemoryInfo.totalHeap) / (1024 * 1024)).toFixed(1)} MB` : '',
      memory.vmMemoryInfo ? `  VM堆已用: ${(Number(memory.vmMemoryInfo.heapUsed) / (1024 * 1024)).toFixed(1)} MB` : '',
      ``,
      `CPU信息:`,
      `  进程CPU使用率: ${cpu.cpuUsage.toFixed(1)}%`,
      `  系统CPU使用率: ${cpu.systemCpuUsage.toFixed(1)}%`,
      cpu.appThreadCpuUsage && cpu.appThreadCpuUsage.length > 0 ? `  线程数: ${cpu.appThreadCpuUsage.length}` : '',
      ``,
      `GC信息:`,
      `  GC次数: ${gc.gcCount}`,
      `  GC时间: ${gc.gcTime} ms`,
      `  GC分配字节: ${(Number(gc.gcBytesAllocated) / (1024 * 1024)).toFixed(1)} MB`,
      `  GC释放字节: ${(Number(gc.gcBytesFreed) / (1024 * 1024)).toFixed(1)} MB`,
      `  长时间GC次数: ${gc.fullgcLongtimeCount}`,
      ``,
      `调试信息:`,
      `  调试状态: ${debug.isDebugState ? '是' : '否'}`,
      `  GWP-Asan状态: ${debug.gwpAsanState}`,
      ``,
      `性能摘要:`,
      `  当前内存: ${summary.memory.current.toFixed(1)} MB`,
      `  平均内存: ${summary.memory.average.toFixed(1)} MB`,
      `  峰值内存: ${summary.memory.peak.toFixed(1)} MB`,
      `  当前CPU: ${summary.cpu.current.toFixed(1)}%`,
      `  平均CPU: ${summary.cpu.average.toFixed(1)}%`,
      `  峰值CPU: ${summary.cpu.peak.toFixed(1)}%`,
      `  总GC次数: ${summary.gc.totalCount}`,
      `  平均堆大小: ${summary.gc.averageHeapSize.toFixed(1)} MB`,
      '======================='
    ].filter(line => line !== '').join('\n');
  }

  // 获取系统状态
  getSystemStatus(): string {
    const errorCount = this.logs.filter(log => log.level === LogLevel.ERROR).length;
    const warnCount = this.logs.filter(log => log.level === LogLevel.WARN).length;
    const infoCount = this.logs.filter(log => log.level === LogLevel.INFO).length;
    const debugCount = this.logs.filter(log => log.level === LogLevel.DEBUG).length;

    return [
      '=== 系统状态 ===',
      `实体数量: ${this.settings?.entityCount || 0}`,
      `活跃实体: ${this.settings?.activeEntities || 0}`,
      `总日志数: ${this.logs.length}`,
      `错误日志: ${errorCount}`,
      `警告日志: ${warnCount}`,
      `信息日志: ${infoCount}`,
      `调试日志: ${debugCount}`,
      `当前FPS: ${typeof this.performanceMetrics?.frameRate?.current === 'number' ? this.performanceMetrics.frameRate.current.toFixed(1) : '未知'}`,
      `内存使用: ${typeof this.performanceMetrics?.memory?.used === 'number' ? this.performanceMetrics.memory.used.toFixed(1) : '未知'} MB`,
      '==============='
    ].join('\n');
  }

  // 获取内存信息
  getMemoryInfo(): string {
    return [
      '=== 内存信息 ===',
      `当前内存: ${typeof this.performanceMetrics?.memory?.used === 'number' ? this.performanceMetrics.memory.used.toFixed(1) : '未知'} MB`,
      `峰值内存: ${typeof this.performanceMetrics?.memory?.peak === 'number' ? this.performanceMetrics.memory.peak.toFixed(1) : '未知'} MB`,
      `日志缓存: ${this.logs.length} 条`,
      `建议操作: ${this.logs.length > 500 ? '建议清理日志缓存' : '内存使用正常'}`,
      '==============='
    ].join('\n');
  }

  // 获取性能信息
  getPerformanceInfo(): string {
    const systemMetrics = this.performanceMetrics?.systems || [];
    const metricsText = systemMetrics
      .map((metric) => {
        return `${metric.name}: ${metric.averageTime.toFixed(2)} ms`;
      })
      .join('\n');

    return [
      '=== 性能信息 ===',
      `当前FPS: ${typeof this.performanceMetrics?.frameRate?.current === 'number' ? this.performanceMetrics.frameRate.current.toFixed(1) : '未知'}`,
      `平均FPS: ${typeof this.performanceMetrics?.frameRate?.average === 'number' ? this.performanceMetrics.frameRate.average.toFixed(1) : '未知'}`,
      `内存使用: ${typeof this.performanceMetrics?.memory?.used === 'number' ? this.performanceMetrics.memory.used.toFixed(1) : '未知'} MB`,
      '系统指标:',
      metricsText || '暂无数据',
      '==============='
    ].join('\n');
  }

  // 一键复制WARN/ERROR日志到剪贴板
  copyErrorLogs(): void {
    const errorLogs = this.logs.filter(log => log.level === LogLevel.WARN || log.level === LogLevel.ERROR);
    if (errorLogs.length === 0) {
      logger.warn('ConsolePanel', '没有找到警告或错误日志');
      return;
    }

    const content = errorLogs.map(log =>
    `[${new Date(log.timestamp).toLocaleString()}] ${LogLevel[log.level]} [${log.tag}] ${log.message}${log.details ? '\n详情: ' + log.details : ''}`
    ).join('\n\n');

    try {
      // 使用HarmonyOS的剪贴板API
      const systemPasteboard = pasteboard.getSystemPasteboard();
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, content);
      systemPasteboard.setData(pasteData);
      logger.info('ConsolePanel', `已复制 ${errorLogs.length} 条错误/警告日志到剪贴板`);
    } catch (error) {
      logger.error('ConsolePanel', '复制日志失败: ' + (error as Error).message);
    }
  }

  // 一键生成错误日志文件
  async generateErrorLogFile(): Promise<void> {
    const errorLogs = this.logs.filter(log => log.level === LogLevel.WARN || log.level === LogLevel.ERROR);
    if (errorLogs.length === 0) {
      logger.warn('ConsolePanel', '没有找到警告或错误日志');
      return;
    }

    try {
      const context = this.getUIContext()?.getHostContext() as common.UIAbilityContext;
      if (!context) {
        logger.error('ConsolePanel', '无法获取UIAbilityContext');
        return;
      }
      const filesDir = context.filesDir;
      const timestamp = TimeUtils.toISOString(Date.now()).replace(/[:.]/g, '-');
      const fileName = `error_logs_${timestamp}.txt`;
      const filePath = `${filesDir}/${fileName}`;

      const content = [
        `错误日志报告`,
        `生成时间: ${TimeUtils.formatDisplay(Date.now(), 'datetime')}`,
        `总计: ${errorLogs.length} 条错误/警告日志`,
        `=`.repeat(50),
        '',
        ...errorLogs.map((log, index) => [
          `${index + 1}. [${new Date(log.timestamp).toLocaleString()}] ${LogLevel[log.level]} [${log.tag}]`,
          `   消息: ${log.message}`,
          log.details ? `   详情: ${log.details}` : '',
          ''
        ].filter(line => line !== '').join('\n'))
      ].join('\n');

      // 使用HarmonyOS的文件写入API
      const file = SafeFileUtils.openSync(filePath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
      SafeFileUtils.writeSync(file.fd, content);
      SafeFileUtils.closeSync(file);
      logger.info('ConsolePanel', `错误日志已保存到: ${fileName}`);
    } catch (error) {
      logger.error('ConsolePanel', '生成日志文件失败: ' + (error as Error).message);
    }
  }

  // 导出所有日志
  async exportAllLogs(): Promise<void> {
    if (this.logs.length === 0) {
      logger.warn('ConsolePanel', '没有日志可导出');
      return;
    }

    try {
      const context = this.getUIContext()?.getHostContext() as common.UIAbilityContext;
      if (!context) {
        logger.error('ConsolePanel', '无法获取UIAbilityContext');
        return;
      }
      const filesDir = context.filesDir;
      const timestamp = TimeUtils.toISOString(Date.now()).replace(/[:.]/g, '-');
      const fileName = `all_logs_${timestamp}.txt`;
      const filePath = `${filesDir}/${fileName}`;

      const content = [
        `完整日志报告`,
        `生成时间: ${TimeUtils.formatDisplay(Date.now(), 'datetime')}`,
        `总计: ${this.logs.length} 条日志`,
        `=`.repeat(50),
        '',
        ...this.logs.map((log, index) => [
          `${index + 1}. [${new Date(log.timestamp).toLocaleString()}] ${LogLevel[log.level]} [${log.tag}]`,
          `   消息: ${log.message}`,
          log.details ? `   详情: ${log.details}` : '',
          ''
        ].filter(line => line !== '').join('\n'))
      ].join('\n');

      // 使用HarmonyOS的文件写入API
      const file = SafeFileUtils.openSync(filePath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
      SafeFileUtils.writeSync(file.fd, content);
      SafeFileUtils.closeSync(file);
      logger.info('ConsolePanel', `完整日志已保存到: ${fileName}`);
    } catch (error) {
      logger.error('ConsolePanel', '导出日志文件失败: ' + (error as Error).message);
    }
  }

  // 清理内存缓存
  clearMemoryCache(): void {
    try {
      // 清理日志缓存
      if (this.logs.length > 100) {
        this.logs = this.logs.slice(-100); // 只保留最新100条
      }

      // 垃圾回收功能已移除（ArkTools模块不可用）
      logger.info('ConsolePanel', '垃圾回收功能不可用');

      logger.info('ConsolePanel', '内存缓存已清理');
      this.loadData();
    } catch (error) {
      logger.error('ConsolePanel', '清理内存缓存失败: ' + (error as Error).message);
    }
  }

  // 生成性能报告
  async generatePerformanceReport(): Promise<void> {
    try {
      const context = this.getUIContext()?.getHostContext() as common.UIAbilityContext;
      if (!context) {
        logger.error('ConsolePanel', '无法获取UIAbilityContext');
        return;
      }
      const filesDir = context.filesDir;
      const timestamp = TimeUtils.toISOString(Date.now()).replace(/[:.]/g, '-');
      const fileName = `performance_report_${timestamp}.txt`;
      const filePath = `${filesDir}/${fileName}`;

      const content = [
        `性能分析报告`,
        `生成时间: ${TimeUtils.formatDisplay(Date.now(), 'datetime')}`,
        `=`.repeat(50),
        '',
        `FPS信息:`,
        `  当前FPS: ${typeof this.performanceMetrics?.frameRate?.current === 'number' ? this.performanceMetrics.frameRate.current.toFixed(1) : '未知'}`,
        `  平均FPS: ${typeof this.performanceMetrics?.frameRate?.average === 'number' ? this.performanceMetrics.frameRate.average.toFixed(1) : '未知'}`,
        '',
        `内存使用:`,
        `  已用内存: ${typeof this.performanceMetrics?.memory?.used === 'number' ? this.performanceMetrics.memory.used.toFixed(1) : '未知'} MB`,
        `  内存峰值: ${typeof this.performanceMetrics?.memory?.peak === 'number' ? this.performanceMetrics.memory.peak.toFixed(1) : '未知'} MB`,
        '',
        `系统性能指标:`,
        ...(this.performanceMetrics?.systems || []).map((metric) => {
          return `  ${metric.name}: ${metric.averageTime.toFixed(2)} ms`;
        }),
        '',
        `日志统计:`,
        `  总日志数: ${this.logs.length}`,
        `  错误日志: ${this.logs.filter(log => log.level === LogLevel.ERROR).length}`,
        `  警告日志: ${this.logs.filter(log => log.level === LogLevel.WARN).length}`,
        `  信息日志: ${this.logs.filter(log => log.level === LogLevel.INFO).length}`,
        `  调试日志: ${this.logs.filter(log => log.level === LogLevel.DEBUG).length}`
      ].join('\n');

      // 使用HarmonyOS的文件写入API
      const file = SafeFileUtils.openSync(filePath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
      SafeFileUtils.writeSync(file.fd, content);
      SafeFileUtils.closeSync(file);
      logger.warn('ConsolePanel', `📊 性能报告已保存到: ${fileName}`);
    } catch (error) {
      logger.error('ConsolePanel', '生成性能报告失败: ' + (error as Error).message);
    }
  }

  // 快速诊断系统状态
  quickDiagnosis(): void {
    const errorCount = this.logs.filter(log => log.level === LogLevel.ERROR).length;
    const warnCount = this.logs.filter(log => log.level === LogLevel.WARN).length;
    const fps = this.performanceMetrics?.frameRate?.current || 0;
    const memory = this.performanceMetrics?.memory?.used || 0;

    let diagnosis: string[] = [];
    let severity: string = 'INFO';

    if (errorCount > 10) {
      diagnosis.push(`⚠️ 检测到 ${errorCount} 个错误，建议检查日志`);
      severity = 'ERROR';
    }

    if (warnCount > 20) {
      diagnosis.push(`⚠️ 检测到 ${warnCount} 个警告，可能影响性能`);
      if (severity !== 'ERROR') severity = 'WARN';
    }

    if (fps < 30) {
      diagnosis.push(`⚠️ FPS过低 (${fps})，可能存在性能问题`);
      if (severity !== 'ERROR') severity = 'WARN';
    }

    if (memory > 500) {
      diagnosis.push(`⚠️ 内存使用过高 (${memory}MB)，建议清理缓存`);
      if (severity !== 'ERROR') severity = 'WARN';
    }

    if (diagnosis.length === 0) {
      diagnosis.push('✅ 系统运行正常，未发现明显问题');
    }

    const message = diagnosis.join('\n');
    const level = severity === 'ERROR' ? LogLevel.ERROR :
      severity === 'WARN' ? LogLevel.WARN : LogLevel.INFO;

    if (level === LogLevel.ERROR) {
      logger.error('SystemDiagnosis', message);
    } else if (level === LogLevel.WARN) {
      logger.warn('SystemDiagnosis', message);
    } else {
      logger.info('SystemDiagnosis', message);
    }
    this.loadData();
  }

  // --- UI 构建方法 ---

  build() {
    // 只有在显示Console面板时才渲染组件
    if (this.showConsolePanel) {
      if (this.isMinimized) {
        // 悬浮按钮模式
        this.FloatingBall();
      } else {
        // 调整了面板的布局和事件处理逻辑
        // 根Stack现在作为背景遮罩，并处理外部点击事件
        Stack() {
          // Console面板内容区域（顶层）
          Column() {
            this.TitleBar();
            this.TabNavigation();
            this.ContentArea();
            if (this.currentTab === ConsolePanelTab.DEBUG || this.currentTab === ConsolePanelTab.LOGS) {
              this.CommandInput();
            }
          }
          .width('95%')
          .height('85%')
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_dark', this.themeState.currentTheme))
          .borderRadius(12)
          .padding(16)
          .shadow({
            radius: 24,
            color: ThemeAwareHelper.getTestManagementThemedColor('shadow_black', this.themeState.currentTheme),
            offsetX: 0,
            offsetY: 4
          } as ShadowStyle)
          .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('border_dark', this.themeState.currentTheme) })
          .alignSelf(ItemAlign.Center)
          .justifyContent(FlexAlign.Start)
          .margin({ top: '7.5%' })
          // 添加一个空的onClick来消费面板背景的点击事件，防止其冒泡到Stack导致面板关闭
          .onClick(() => {})
        }
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0, 0, 0, 0.5)')
        .alignContent(Alignment.Center)
        // 当点击Stack的空白区域（即面板之外）时，最小化面板
        .onClick(() => {
          this.isMinimized = true;
        })
      }
    }
  }

  @Builder FloatingBall() {
    Button() {
      Column({ space: 2 }) {
        Text('�')
          .fontSize(20)
          .fontColor($r('app.color.console_text_white'));
        Text('Console')
          .fontSize(8)
          .fontColor($r('app.color.console_text_white'))
          .opacity(0.8);
      }
    }
    .width(64)
    .height(64)
    .borderRadius(32)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_primary', this.themeState.currentTheme))
    .shadow({
      radius: 12,
      color: ThemeAwareHelper.getTestManagementThemedColor('shadow_black', this.themeState.currentTheme),
      offsetX: 0,
      offsetY: 2
    } as ShadowStyle)
    .border({ width: 2, color: ThemeAwareHelper.getTestManagementThemedColor('brand_blue', this.themeState.currentTheme) })
    // [修复] 使用 .translate 修饰器来改变位置，以遵循官方文档
    .translate({ x: this.offsetX, y: this.offsetY, z: 0 })
    // [修复] 使用PanGesture来实现拖拽和点击的区分，并遵循官方文档的实现逻辑
    .gesture(
      PanGesture()
        .onActionStart((event: GestureEvent) => {
          // 官方文档示例中，此部分为空，因为最终位置已由 positionX/Y 保存
          console.info('Pan start');
        })
        .onActionUpdate((event: GestureEvent) => {
          // 遵循官方文档：新位置 = 上次结束位置 + 本次拖动偏移量
          if (event) {
            this.offsetX = this.positionX + event.offsetX;
            this.offsetY = this.positionY + event.offsetY;
          }
        })
        .onActionEnd((event: GestureEvent) => {
          // 拖动结束，保存当前偏移量作为新的"上次结束位置"
          this.positionX = this.offsetX;
          this.positionY = this.offsetY;

          // 保留点击检测：如果拖动距离很短，则视为点击事件
          // 通过计算最终位置与起始位置的差值来判断是否为点击
          if (event && Math.abs(this.offsetX - this.positionX) < 5 && Math.abs(this.offsetY - this.positionY) < 5) {
            this.isMinimized = false;
          }
        })
    )
    .hitTestBehavior(HitTestMode.Block);
  }

  @Builder TitleBar() {
    Row() {
      Row({ space: 8 }) {
        Text('🎮').fontSize(20);
        Text('Console 面板')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme));
      }

      Blank();

      Row({ space: 8 }) {
        Button('—')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .width(32)
          .height(32)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_secondary', this.themeState.currentTheme))
          .borderRadius(6)
          .onClick(() => { this.isMinimized = true; });

        Button('✕')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .width(32)
          .height(32)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_danger', this.themeState.currentTheme))
          .borderRadius(6)
          .onClick(() => { this.showConsolePanel = false; });
      }
    }
    .width('100%')
    .height(48)
    .padding({ bottom: 12 })
    .justifyContent(FlexAlign.SpaceBetween)
    .alignItems(VerticalAlign.Center);
  }

  @Builder TabNavigation() {
    Row({ space: 4 }) {
      ForEach(this.tabItems, (item: GeneratedTypeLiteralInterface_2) => {
        this.TabButton(item.label, item.key);
      }, (item: GeneratedTypeLiteralInterface_3) => item.key);
    }
    .width('100%')
    .height(40)
    .padding({ bottom: 12 })
    .justifyContent(FlexAlign.SpaceEvenly);
  }

  @Builder TabButton(title: string, tab: ConsolePanelTab) {
    Button(title)
      .fontSize(12)
      .fontWeight(this.currentTab === tab ? FontWeight.Bold : FontWeight.Normal)
      .fontColor(this.currentTab === tab ? ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme) : ThemeAwareHelper.getTestManagementThemedColor('text_light', this.themeState.currentTheme))
      .backgroundColor(this.currentTab === tab ? ThemeAwareHelper.getTestManagementThemedColor('button_primary', this.themeState.currentTheme) : ThemeAwareHelper.getTestManagementThemedColor('border_light', this.themeState.currentTheme))
      .borderRadius(8)
      .height(32)
      .layoutWeight(1)
      .border({
        width: this.currentTab === tab ? 2 : 1,
        color: this.currentTab === tab ? ThemeAwareHelper.getTestManagementThemedColor('button_primary', this.themeState.currentTheme) : ThemeAwareHelper.getTestManagementThemedColor('border_active', this.themeState.currentTheme)
      })
      .onClick(() => {
        this.currentTab = tab;
        consolePanel.switchTab(tab);
        this.loadData();
      });
  }

  @Builder ContentArea() {
    Column() {
      if (this.currentTab === ConsolePanelTab.DEBUG) this.DebugContent();
      else if (this.currentTab === ConsolePanelTab.LOGS) this.LogsContent();
      else if (this.currentTab === ConsolePanelTab.PERFORMANCE) this.PerformanceContent();
      else if (this.currentTab === ConsolePanelTab.SETTINGS) this.SettingsContent();
    }
    .width('100%')
    .layoutWeight(1)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_dark', this.themeState.currentTheme))
    .borderRadius(8)
    .padding({ left: 12, right: 12, top: 12, bottom: 12 } as PaddingStyle)
    .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('border_light', this.themeState.currentTheme) });
  }

  @Builder CommandInput() {
    Column({ space: 8 }) {
      Divider().color(ThemeAwareHelper.getTestManagementThemedColor('button_secondary', this.themeState.currentTheme));
      if (this.commandOutput) {
        Text(this.commandOutput).fontSize(10).fontColor(ThemeAwareHelper.getTestManagementThemedColor('brand', this.themeState.currentTheme)).width('100%').maxLines(5);
      }
      Row({ space: 8 }) {
        Text('>')
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_primary', this.themeState.currentTheme))
          .fontWeight(FontWeight.Bold)
          .width(20);
        TextInput({ text: this.commandInput, placeholder: '输入命令... (输入 help 查看可用命令)' })
          .layoutWeight(1)
          .height(40)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('border_light', this.themeState.currentTheme))
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme))
          .fontSize(14)
          .borderRadius(8)
          .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('border_active', this.themeState.currentTheme) })
          .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_placeholder', this.themeState.currentTheme))
          .onChange((value: string) => { this.commandInput = value; })
          .onSubmit(() => this.executeCommand());

        Button('执行')
          .height(40)
          .width(60)
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_primary', this.themeState.currentTheme))
          .borderRadius(8)
          .onClick(() => this.executeCommand());
      }
      .width('100%')
      .alignItems(VerticalAlign.Center);

      // 快捷命令按钮
      Row({ space: 4 }) {
        Button('help')
          .fontSize(8)
          .height(24)
          .padding({ left: 6, right: 6 } as PaddingStyle)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_info', this.themeState.currentTheme))
          .borderRadius(3)
          .onClick(() => {
            this.commandInput = 'help';
            this.executeCommand();
          });

        Button('status')
          .fontSize(8)
          .height(24)
          .padding({ left: 6, right: 6 } as PaddingStyle)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_primary', this.themeState.currentTheme))
          .borderRadius(3)
          .onClick(() => {
            this.commandInput = 'status';
            this.executeCommand();
          });

        Button('memory')
          .fontSize(8)
          .height(24)
          .padding({ left: 6, right: 6 } as PaddingStyle)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_warning', this.themeState.currentTheme))
          .borderRadius(3)
          .onClick(() => {
            this.commandInput = 'memory';
            this.executeCommand();
          });

        Button('perf')
          .fontSize(8)
          .height(24)
          .padding({ left: 6, right: 6 } as PaddingStyle)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_success', this.themeState.currentTheme))
          .borderRadius(3)
          .onClick(() => {
            this.commandInput = 'performance';
            this.executeCommand();
          });

        Button('diag')
          .fontSize(8)
          .height(24)
          .padding({ left: 6, right: 6 } as PaddingStyle)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_purple', this.themeState.currentTheme))
          .borderRadius(3)
          .onClick(() => {
            this.commandInput = 'diagnosis';
            this.executeCommand();
          });

        Button('clear')
          .fontSize(8)
          .height(24)
          .padding({ left: 6, right: 6 } as PaddingStyle)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_danger', this.themeState.currentTheme))
          .borderRadius(3)
          .onClick(() => {
            this.commandInput = 'clear';
            this.executeCommand();
          });
      }
      .width('100%')
      .justifyContent(FlexAlign.Start);
    }.width('100%').padding({ top: 8 });
  }

  // --- 各个标签页的具体内容 ---

  @Builder DebugContent() {
    Scroll() {
      Column({ space: 12 }) {
        // 调试功能按钮
        Column({ space: 8 }) {
          Row({ space: 8 }) {
            Text('🔧')
              .fontSize(16);
            Text('调试工具')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme));
          }.width('100%');

          Row({ space: 8 }) {
            Button('🔍快速诊断')
              .fontSize(10)
              .height(32)
              .layoutWeight(1)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_primary', this.themeState.currentTheme))
              .borderRadius(6)
              .onClick(() => {
                this.quickDiagnosis();
              });

            Button('🧹清理缓存')
              .fontSize(10)
              .height(32)
              .layoutWeight(1)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_warning', this.themeState.currentTheme))
              .borderRadius(6)
              .onClick(() => {
                this.clearMemoryCache();
              });

            Button('📊性能报告')
              .fontSize(10)
              .height(32)
              .layoutWeight(1)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_success', this.themeState.currentTheme))
              .borderRadius(6)
              .onClick(() => {
                this.generatePerformanceReport();
              });
          }
          .width('100%');
        }
        .width('100%')
        .padding(12)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_dark', this.themeState.currentTheme))
        .borderRadius(8)
        .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('border_subtle', this.themeState.currentTheme) });

        // 实体信息显示
        if (this.entityNames && this.entityNames.length > 0) {
          Column({ space: 8 }) {
            Row({ space: 8 }) {
              Text('🎯')
                .fontSize(16);
              Text('实体信息')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme));
              Blank();
              Text(`共 ${this.entityNames.length} 个实体`)
                .fontSize(11)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_light', this.themeState.currentTheme));
            }.width('100%');

            List({ space: 4 }) {
              ForEach(this.entityNames.slice(0, 10), (entity: string, index: number) => {
                ListItem() {
                  Row({ space: 8 }) {
                    Text(`${index + 1}.`)
                      .fontSize(11)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_placeholder', this.themeState.currentTheme))
                      .width(20);
                    Text(entity)
                      .fontSize(12)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
                      .layoutWeight(1);
                  }
                  .width('100%')
                  .height(28)
                  .padding({ left: 8, right: 8 } as PaddingStyle)
                  .backgroundColor(index % 2 === 0 ? ThemeAwareHelper.getTestManagementThemedColor('row_even', this.themeState.currentTheme) : ThemeAwareHelper.getTestManagementThemedColor('row_odd', this.themeState.currentTheme))
                  .borderRadius(4);
                }
              });
            }
            .height(120)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_darker', this.themeState.currentTheme))
            .borderRadius(6)
            .padding({ left: 4, right: 4, top: 4, bottom: 4 } as PaddingStyle);
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 12, bottom: 12 } as PaddingStyle)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_dark', this.themeState.currentTheme))
          .borderRadius(8)
          .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('border_subtle', this.themeState.currentTheme) });
        }

        // 命令输出显示
        if (this.commandOutput) {
          Column({ space: 8 }) {
            Row({ space: 8 }) {
              Text('📋')
                .fontSize(16);
              Text('命令输出')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme));
            }.width('100%');

            Text(this.commandOutput)
              .fontSize(11)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_success', this.themeState.currentTheme))
              .width('100%')
              .padding({ left: 12, right: 12, top: 12, bottom: 12 } as PaddingStyle)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_darker', this.themeState.currentTheme))
              .borderRadius(6)
              .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('button_success', this.themeState.currentTheme) })
              .maxLines(8)
              .textOverflow({ overflow: TextOverflow.Ellipsis });
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 12, bottom: 12 } as PaddingStyle)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_dark', this.themeState.currentTheme))
          .borderRadius(8)
          .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('border_subtle', this.themeState.currentTheme) });
        }
      }.width('100%').alignItems(HorizontalAlign.Start);
    }.layoutWeight(1);
  }

  @Builder LogsContent() {
    Column({ space: 8 }) {
      // 日志过滤器和工具栏
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          Text('过滤级别:')
            .fontSize(12)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_light', this.themeState.currentTheme))
            .fontWeight(FontWeight.Medium);

          Row({ space: 4 }) {
            Button('全部')
              .fontSize(10)
              .height(24)
              .padding({ left: 8, right: 8 } as PaddingStyle)
              .backgroundColor(this.logFilter.level === undefined ? ThemeAwareHelper.getTestManagementThemedColor('button_primary', this.themeState.currentTheme) : ThemeAwareHelper.getTestManagementThemedColor('button_secondary', this.themeState.currentTheme))
              .borderRadius(4)
              .onClick(() => {
                this.logFilter = {};
                consolePanel.setLogFilter(this.logFilter);
                this.loadData();
              });
            Button('调试')
              .fontSize(10)
              .height(24)
              .padding({ left: 8, right: 8 } as PaddingStyle)
              .backgroundColor(this.logFilter.level === LogLevel.DEBUG ? ThemeAwareHelper.getTestManagementThemedColor('button_purple', this.themeState.currentTheme) : ThemeAwareHelper.getTestManagementThemedColor('button_secondary', this.themeState.currentTheme))
              .borderRadius(4)
              .onClick(() => {
                this.logFilter = { level: LogLevel.DEBUG };
                consolePanel.setLogFilter(this.logFilter);
                this.loadData();
              });
            Button('信息')
              .fontSize(10)
              .height(24)
              .padding({ left: 8, right: 8 } as PaddingStyle)
              .backgroundColor(this.logFilter.level === LogLevel.INFO ? ThemeAwareHelper.getTestManagementThemedColor('button_success', this.themeState.currentTheme) : ThemeAwareHelper.getTestManagementThemedColor('button_secondary', this.themeState.currentTheme))
              .borderRadius(4)
              .onClick(() => {
                this.logFilter = { level: LogLevel.INFO };
                consolePanel.setLogFilter(this.logFilter);
                this.loadData();
              });
            Button('警告')
              .fontSize(10)
              .height(24)
              .padding({ left: 8, right: 8 } as PaddingStyle)
              .backgroundColor(this.logFilter.level === LogLevel.WARN ? ThemeAwareHelper.getTestManagementThemedColor('button_warning', this.themeState.currentTheme) : ThemeAwareHelper.getTestManagementThemedColor('button_secondary', this.themeState.currentTheme))
              .borderRadius(4)
              .onClick(() => {
                this.logFilter = { level: LogLevel.WARN };
                consolePanel.setLogFilter(this.logFilter);
                this.loadData();
              });
            Button('错误')
              .fontSize(10)
              .height(24)
              .padding({ left: 8, right: 8 } as PaddingStyle)
              .backgroundColor(this.logFilter.level === LogLevel.ERROR ? ThemeAwareHelper.getTestManagementThemedColor('button_danger', this.themeState.currentTheme) : ThemeAwareHelper.getTestManagementThemedColor('button_secondary', this.themeState.currentTheme))
              .borderRadius(4)
              .onClick(() => {
                this.logFilter = { level: LogLevel.ERROR };
                consolePanel.setLogFilter(this.logFilter);
                this.loadData();
              });
          }

          Blank();

          // 新增功能按钮
          Row({ space: 4 }) {
            Button('📋复制错误')
              .fontSize(9)
              .height(24)
              .padding({ left: 6, right: 6 } as PaddingStyle)
              .backgroundColor($r('app.color.console_button_danger'))
              .borderRadius(4)
              .onClick(() => {
                this.copyErrorLogs();
              });

            Button('💾生成报告')
              .fontSize(9)
              .height(24)
              .padding({ left: 6, right: 6 } as PaddingStyle)
              .backgroundColor($r('app.color.console_button_purple'))
              .borderRadius(4)
              .onClick(() => {
                this.generateErrorLogFile();
              });

            Button('📤导出全部')
              .fontSize(9)
              .height(24)
              .padding({ left: 6, right: 6 } as PaddingStyle)
              .backgroundColor($r('app.color.console_button_info'))
              .borderRadius(4)
              .onClick(() => {
                this.exportAllLogs();
              });

            Button('🗑️清空')
              .fontSize(9)
              .height(24)
              .padding({ left: 6, right: 6 } as PaddingStyle)
              .backgroundColor($r('app.color.console_button_danger'))
              .borderRadius(4)
              .onClick(() => {
                consolePanel.clearLogs();
                this.loadData();
              });
          }
        }.width('100%');

        // 日志统计
        if (Object.keys(this.logStats).length > 0) {
          Row({ space: 8 }) {
            Text('统计:')
              .fontSize(11)
              .fontColor($r('app.color.console_text_light'))
              .fontWeight(FontWeight.Medium);
            ForEach(Object.entries(this.logStats), (item: [string, number]) => {
              Text(`${item[0]}: ${item[1]}`)
                .fontSize(10)
                .fontColor($r('app.color.console_text_white'))
                .padding({ left: 6, right: 6, top: 2, bottom: 2 } as PaddingStyle)
                .backgroundColor(this.getLogLevelColor(this.stringToLogLevel(item[0])))
                .borderRadius(3);
            });
          }.width('100%');
        }
      }
      .width('100%')
      .padding({ left: 8, right: 8, top: 8, bottom: 8 } as PaddingStyle)
      .backgroundColor($r('app.color.console_row_even'))
      .borderRadius(6);

      // 日志列表
      List({ scroller: this.scrollController, space: 2 }) {
        ForEach(this.logs, (log: LogEntry, index: number) => {
          ListItem() { this.LogItem(log, index); }
        });
      }
      .layoutWeight(1)
      .width('100%')
      .backgroundColor($r('app.color.console_background_darker'))
      .borderRadius(6)
      .padding(4);
    }.width('100%').height('100%');
  }

  @Builder LogItem(log: LogEntry, index: number) {
    Column({ space: 4 }) {
      Row({ space: 8 }) {
        Text(`#${index + 1}`)
          .fontSize(9)
          .fontColor($r('app.color.console_text_placeholder'))
          .width(30);
        if (this.settings?.showTimestamp) {
          Text(new Date(log.timestamp).toLocaleTimeString())
            .fontSize(10)
            .fontColor($r('app.color.console_text_light'))
            .width(80);
        }
        Text(LogLevel[log.level])
          .fontSize(10)
          .fontColor($r('app.color.console_text_white'))
          .fontWeight(FontWeight.Bold)
          .padding({ left: 4, right: 4, top: 1, bottom: 1 } as PaddingStyle)
          .backgroundColor(this.getLogLevelColor(log.level))
          .borderRadius(3)
          .width(60);
        Text(`[${log.tag}]`)
          .fontSize(10)
          .fontColor($r('app.color.console_text_white'))
          .backgroundColor($r('app.color.console_button_secondary'))
          .padding({ left: 4, right: 4, top: 1, bottom: 1 } as PaddingStyle)
          .borderRadius(2)
          .maxLines(1);
        Blank();
        if (log.message.length > 80) {
          Text(this.expandedLogs.has(index) ? '收起' : '展开')
            .fontSize(9)
            .fontColor($r('app.color.console_button_primary'))
            .padding({ left: 4, right: 4 } as PaddingStyle)
            .onClick(() => {
              if (this.expandedLogs.has(index)) {
                this.expandedLogs.delete(index);
              } else {
                this.expandedLogs.add(index);
              }
            });
        }
      }.width('100%').alignItems(VerticalAlign.Center);

      Text(this.expandedLogs.has(index) ? log.message : (log.message.length > 80 ? log.message.substring(0, 80) + '...' : log.message))
        .fontSize(11)
        .fontColor($r('app.color.console_text_white'))
        .width('100%')
        .lineHeight(16)
        .textAlign(TextAlign.Start)
        .padding({ left: 4, right: 0, top: 0, bottom: 0 } as PaddingStyle);

      if (this.expandedLogs.has(index) && log.details) {
        Text(log.details)
          .fontSize(10)
          .fontColor($r('app.color.console_text_light'))
          .width('100%')
          .backgroundColor($r('app.color.console_border_subtle'))
          .padding({ left: 6, right: 6, top: 6, bottom: 6 } as PaddingStyle)
          .borderRadius(4)
          .margin({ top: 4 });
      }
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 8, bottom: 8 } as PaddingStyle)
    .backgroundColor(index % 2 === 0 ? $r('app.color.console_row_even') : $r('app.color.console_row_odd'))
    .borderRadius(4)
    .border({ width: 1, color: $r('app.color.console_border_active'), style: BorderStyle.Solid })
    .borderWidth({ left: 3, top: 0, right: 0, bottom: 0 })
    .borderColor({ left: this.getLogLevelColor(log.level), top: $r('app.color.console_border_active'), right: $r('app.color.console_border_active'), bottom: $r('app.color.console_border_active') })
    .gesture(
      LongPressGesture({ repeat: false })
        .onAction(() => {
          // 复制日志内容到剪贴板
          const content = `[${new Date(log.timestamp).toLocaleTimeString()}] ${LogLevel[log.level]} [${log.tag}] ${log.message}`;
          pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, content);
        })
    );
  }

  @Builder PerformanceContent() {
    Scroll() {
      Column({ space: 12 }) {
        // 性能图表控制
        Row({ space: 8 }) {
          Text('📈 性能监控')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.console_text_white'));

          Blank();

          Button(this.isChartsEnabled ? '隐藏图表' : '显示图表')
            .fontSize(12)
            .height(32)
            .padding({ left: 12, right: 12 } as PaddingStyle)
            .backgroundColor(this.isChartsEnabled ? $r('app.color.console_button_warning') : $r('app.color.console_button_primary'))
            .borderRadius(6)
            .onClick(() => {
              this.isChartsEnabled = !this.isChartsEnabled;
            });
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 8, bottom: 8 } as PaddingStyle)
        .backgroundColor($r('app.color.console_background_darker'))
        .borderRadius(8);

        // 性能图表
        if (this.isChartsEnabled && this.hidebugData) {
          Column({ space: 8 }) {
            ForEach(this.chartConfigs, (config: ChartConfig) => {
              PerformanceChart({
                chartConfig: config,
                performanceHistory: this.hidebugCollector.getHistory()
              })
                .width('100%')
                .height(200)
                .margin({ bottom: 8 });
            });
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 12, bottom: 12 } as PaddingStyle)
          .backgroundColor($r('app.color.console_background_darker'))
          .borderRadius(8)
          .border({ width: 1, color: $r('app.color.console_border_subtle') });
        }

        // Hidebug 性能数据
        if (this.hidebugData) {
          Column({ space: 8 }) {
            Text('🔍 Hidebug 性能数据')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.console_text_white'));

            // 内存信息
            Column({ space: 8 }) {
              Text('💾 内存信息')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.console_text_white'));

              Row({ space: 16 }) {
                Column({ space: 4 }) {
                  Text('PSS内存')
                    .fontSize(12)
                    .fontColor($r('app.color.console_text_light'));
                  Text(`${(Number(this.hidebugData.memory.pss) / (1024 * 1024)).toFixed(1)} MB`)
                    .fontSize(16)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.console_button_info'));
                }
                .alignItems(HorizontalAlign.Center)
                .layoutWeight(1);

                Column({ space: 4 }) {
                  Text('堆已分配')
                    .fontSize(12)
                    .fontColor($r('app.color.console_text_light'));
                  Text(`${(Number(this.hidebugData.memory.nativeHeapAllocatedSize) / (1024 * 1024)).toFixed(1)} MB`)
                    .fontSize(16)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.console_button_warning'));
                }
                .alignItems(HorizontalAlign.Center)
                .layoutWeight(1);

                Column({ space: 4 }) {
                  Text('VM堆使用')
                    .fontSize(12)
                    .fontColor($r('app.color.console_text_light'));
                  Text(this.hidebugData.memory.vmMemoryInfo ?
                    `${(Number(this.hidebugData.memory.vmMemoryInfo.heapUsed) / (1024 * 1024)).toFixed(1)} MB` :
                    '未知')
                    .fontSize(16)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.console_button_success'));
                }
                .alignItems(HorizontalAlign.Center)
                .layoutWeight(1);
              }.width('100%');
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 12, bottom: 12 } as PaddingStyle)
            .backgroundColor($r('app.color.console_row_even'))
            .borderRadius(8);

            // CPU 和 GC 信息
            Row({ space: 12 }) {
              Column({ space: 8 }) {
                Text('⚡ CPU 信息')
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.console_text_white'));

                Column({ space: 4 }) {
                  Text('CPU使用率')
                    .fontSize(12)
                    .fontColor($r('app.color.console_text_light'));
                  Text(`${this.hidebugData.cpu.cpuUsage.toFixed(1)}%`)
                    .fontSize(18)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.hidebugData.cpu.cpuUsage > 80 ? $r('app.color.console_button_danger') :
                      this.hidebugData.cpu.cpuUsage > 60 ? $r('app.color.console_button_warning') : $r('app.color.console_button_success'));
                }
                .alignItems(HorizontalAlign.Center);
              }
              .layoutWeight(1)
              .padding({ left: 12, right: 12, top: 12, bottom: 12 } as PaddingStyle)
              .backgroundColor($r('app.color.console_row_even'))
              .borderRadius(8);

              Column({ space: 8 }) {
                Text('🗑️ GC 信息')
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.console_text_white'));

                Column({ space: 4 }) {
                  Text(`GC次数: ${this.hidebugData.gc.gcCount}`)
                    .fontSize(12)
                    .fontColor($r('app.color.console_text_light'));
                  Text(`GC时间: ${this.hidebugData.gc.gcTime} ms`)
                    .fontSize(12)
                    .fontColor($r('app.color.console_text_light'));
                  Text(`分配: ${(Number(this.hidebugData.gc.gcBytesAllocated) / (1024 * 1024)).toFixed(1)} MB`)
                    .fontSize(12)
                    .fontColor($r('app.color.console_text_light'));
                  Text(`释放: ${(Number(this.hidebugData.gc.gcBytesFreed) / (1024 * 1024)).toFixed(1)} MB`)
                    .fontSize(12)
                    .fontColor($r('app.color.console_text_light'));
                }
                .alignItems(HorizontalAlign.Start);
              }
              .layoutWeight(1)
              .padding({ left: 12, right: 12, top: 12, bottom: 12 } as PaddingStyle)
              .backgroundColor($r('app.color.console_row_even'))
              .borderRadius(8);
            }.width('100%');
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 12, bottom: 12 } as PaddingStyle)
          .backgroundColor($r('app.color.console_background_darker'))
          .borderRadius(8)
          .border({ width: 1, color: $r('app.color.console_border_subtle') });
        }

        if (this.performanceMetrics) {
          // 性能概览卡片
          Column({ space: 8 }) {
            Text('📊 性能概览')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.console_text_white'));

            Row({ space: 16 }) {
              Column({ space: 4 }) {
                Text('FPS')
                  .fontSize(12)
                  .fontColor($r('app.color.console_text_light'));
                Text(typeof this.performanceMetrics?.frameRate?.current === 'number' ? this.performanceMetrics.frameRate.current.toFixed(1) : '未知')
                  .fontSize(20)
                  .fontWeight(FontWeight.Bold)
                  .fontColor((this.performanceMetrics?.frameRate?.current || 0) >= 55 ? $r('app.color.console_button_success') :
                    (this.performanceMetrics?.frameRate?.current || 0) >= 30 ? $r('app.color.console_button_warning') : $r('app.color.console_button_danger'));
              }
              .alignItems(HorizontalAlign.Center)
              .padding({ left: 12, right: 12, top: 12, bottom: 12 } as PaddingStyle)
              .backgroundColor($r('app.color.console_row_even'))
              .borderRadius(8)
              .layoutWeight(1);

              Column({ space: 4 }) {
                Text('内存使用')
                  .fontSize(12)
                  .fontColor($r('app.color.console_text_light'));
                Text(`${typeof this.performanceMetrics?.memory?.used === 'number' ? this.performanceMetrics.memory.used.toFixed(1) : '未知'} MB`)
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.console_button_primary'));
                Text(`/ ${typeof this.performanceMetrics?.memory?.total === 'number' ? this.performanceMetrics.memory.total.toFixed(1) : '未知'} MB`)
                  .fontSize(10)
                  .fontColor($r('app.color.console_text_light'));
              }
              .alignItems(HorizontalAlign.Center)
              .padding({ left: 12, right: 12, top: 12, bottom: 12 } as PaddingStyle)
              .backgroundColor($r('app.color.console_row_even'))
              .borderRadius(8)
              .layoutWeight(1);
            }.width('100%');
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 12, bottom: 12 } as PaddingStyle)
          .backgroundColor($r('app.color.console_background_darker'))
          .borderRadius(8)
          .border({ width: 1, color: $r('app.color.console_border_subtle') });

          // 系统性能详情
          Column({ space: 8 }) {
            Text('⚙️ 系统性能详情')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.console_text_white'))
              .margin({ bottom: 8 });

            ForEach(this.performanceMetrics?.systems || [], (sys: SystemMetrics, index: number) => {
              Row({ space: 12 }) {
                Text(sys.name)
                  .fontSize(12)
                  .fontColor($r('app.color.console_text_white'))
                  .layoutWeight(1);
                Text(`${typeof sys.averageTime === 'number' ? sys.averageTime.toFixed(3) : '未知'} ms`)
                  .fontSize(12)
                  .fontWeight(FontWeight.Bold)
                  .fontColor((sys.averageTime || 0) < 16.67 ? $r('app.color.console_button_success') :
                    (sys.averageTime || 0) < 33.33 ? $r('app.color.console_button_warning') : $r('app.color.console_button_danger'))
                  .padding({ left: 6, right: 6, top: 2, bottom: 2 } as PaddingStyle)
                  .backgroundColor($r('app.color.console_row_even'))
                  .borderRadius(4);
                Text(`${sys.callCount} 次`)
                  .fontSize(10)
                  .fontColor($r('app.color.console_text_light'))
                  .width(50);
              }
              .width('100%')
              .padding({ left: 8, right: 8, top: 8, bottom: 8 } as PaddingStyle)
              .backgroundColor(index % 2 === 0 ? $r('app.color.console_row_even') : $r('app.color.console_row_odd'))
              .borderRadius(4);
            });
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 12, bottom: 12 } as PaddingStyle)
          .backgroundColor($r('app.color.console_background_darker'))
          .borderRadius(8)
          .border({ width: 1, color: $r('app.color.console_border_subtle') });
        } else {
          Column({ space: 8 }) {
            Text('⏳ 性能数据加载中...')
              .fontSize(14)
              .fontColor($r('app.color.console_text_light'))
              .textAlign(TextAlign.Center);
            Text('请稍候片刻')
              .fontSize(12)
              .fontColor($r('app.color.console_text_light'))
              .textAlign(TextAlign.Center);
          }
          .width('100%')
          .height(100)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .backgroundColor($r('app.color.console_background_darker'))
          .borderRadius(8)
          .border({ width: 1, color: $r('app.color.console_border_subtle'), style: BorderStyle.Dashed });
        }
      }.width('100%').alignItems(HorizontalAlign.Start);
    }.layoutWeight(1);
  }

  @Builder SettingsContent() {
    Scroll() {
      Column({ space: 16 }) {
        // 标题
        Row({ space: 8 }) {
          Text('⚙️')
            .fontSize(20);
          Text('Console 面板设置')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.console_text_white'));
        }
        .width('100%')
        .margin({ bottom: 8 });

        if (this.settings) {
          // 显示设置
          Column({ space: 12 }) {
            Row({ space: 8 }) {
              Text('👁️')
                .fontSize(16);
              Text('显示设置')
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.console_text_white'));
            }

            this.SettingsToggle('显示时间戳', this.settings.showTimestamp, (val) => {
              this.settings!.showTimestamp = val;
              consolePanel.updateSettings({ showTimestamp: val });
            });

            this.SettingsToggle('启用日志收集', this.settings.enableLogCollection, (val) => {
              this.settings!.enableLogCollection = val;
              consolePanel.updateSettings({ enableLogCollection: val });
            });

            this.SettingsToggle('自动滚动到底部', this.settings.autoScroll, (val) => {
              this.settings!.autoScroll = val;
              consolePanel.updateSettings({ autoScroll: val });
            });
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 16, bottom: 16 } as PaddingStyle)
          .backgroundColor($r('app.color.console_background_darker'))
          .borderRadius(12)
          .border({ width: 1, color: $r('app.color.console_border_subtle') });

          // 日志级别设置
          Column({ space: 12 }) {
            Row({ space: 8 }) {
              Text('📝')
                .fontSize(16);
              Text('日志级别过滤')
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.console_text_white'));
            }

            Text('选择要显示的最低日志级别')
              .fontSize(12)
              .fontColor($r('app.color.console_text_light'))
              .width('100%');

            Row({ space: 8 }) {
              Button('DEBUG')
                .fontSize(11)
                .height(32)
                .layoutWeight(1)
                .fontWeight(this.settings.logLevel === LogLevel.DEBUG ? FontWeight.Bold : FontWeight.Normal)
                .backgroundColor(this.settings.logLevel === LogLevel.DEBUG ? $r('app.color.console_button_purple') : $r('app.color.console_button_secondary'))
                .borderRadius(8)
                .border({ width: this.settings.logLevel === LogLevel.DEBUG ? 2 : 1, color: this.settings.logLevel === LogLevel.DEBUG ? $r('app.color.console_button_purple') : $r('app.color.console_border_active') })
                .onClick(() => {
                  this.settings!.logLevel = LogLevel.DEBUG;
                  consolePanel.updateSettings({ logLevel: LogLevel.DEBUG });
                });
              Button('INFO')
                .fontSize(11)
                .height(32)
                .layoutWeight(1)
                .fontWeight(this.settings.logLevel === LogLevel.INFO ? FontWeight.Bold : FontWeight.Normal)
                .backgroundColor(this.settings.logLevel === LogLevel.INFO ? $r('app.color.console_button_success') : $r('app.color.console_button_secondary'))
                .borderRadius(8)
                .border({ width: this.settings.logLevel === LogLevel.INFO ? 2 : 1, color: this.settings.logLevel === LogLevel.INFO ? $r('app.color.console_button_success') : $r('app.color.console_border_active') })
                .onClick(() => {
                  this.settings!.logLevel = LogLevel.INFO;
                  consolePanel.updateSettings({ logLevel: LogLevel.INFO });
                });
              Button('WARN')
                .fontSize(11)
                .height(32)
                .layoutWeight(1)
                .fontWeight(this.settings.logLevel === LogLevel.WARN ? FontWeight.Bold : FontWeight.Normal)
                .backgroundColor(this.settings.logLevel === LogLevel.WARN ? $r('app.color.console_button_warning') : $r('app.color.console_button_secondary'))
                .borderRadius(8)
                .border({ width: this.settings.logLevel === LogLevel.WARN ? 2 : 1, color: this.settings.logLevel === LogLevel.WARN ? $r('app.color.console_button_warning') : $r('app.color.console_border_active') })
                .onClick(() => {
                  this.settings!.logLevel = LogLevel.WARN;
                  consolePanel.updateSettings({ logLevel: LogLevel.WARN });
                });
              Button('ERROR')
                .fontSize(11)
                .height(32)
                .layoutWeight(1)
                .fontWeight(this.settings.logLevel === LogLevel.ERROR ? FontWeight.Bold : FontWeight.Normal)
                .backgroundColor(this.settings.logLevel === LogLevel.ERROR ? $r('app.color.console_button_danger') : $r('app.color.console_button_secondary'))
                .borderRadius(8)
                .border({ width: this.settings.logLevel === LogLevel.ERROR ? 2 : 1, color: this.settings.logLevel === LogLevel.ERROR ? $r('app.color.console_button_danger') : $r('app.color.console_border_active') })
                .onClick(() => {
                  this.settings!.logLevel = LogLevel.ERROR;
                  consolePanel.updateSettings({ logLevel: LogLevel.ERROR });
                });
            }.width('100%');
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 16, bottom: 16 } as PaddingStyle)
          .backgroundColor($r('app.color.console_background_darker'))
          .borderRadius(12)
          .border({ width: 1, color: $r('app.color.console_border_subtle') });

          // 性能设置
          Column({ space: 12 }) {
            Row({ space: 8 }) {
              Text('⚡')
                .fontSize(16);
              Text('性能设置')
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.console_text_white'));
            }

            // 最大日志条数
            Column({ space: 8 }) {
              Row({ space: 8 }) {
                Text('最大日志条数:')
                  .fontSize(13)
                  .fontColor($r('app.color.console_text_light'))
                  .layoutWeight(1);
                Text(`当前: ${this.settings.maxLogEntries}`)
                  .fontSize(12)
                  .fontColor($r('app.color.console_button_primary'))
                  .fontWeight(FontWeight.Bold);
              }.width('100%').alignItems(VerticalAlign.Center);

              Row({ space: 6 }) {
                Button('500')
                  .fontSize(10)
                  .height(28)
                  .layoutWeight(1)
                  .backgroundColor(this.settings.maxLogEntries === 500 ? $r('app.color.console_button_primary') : $r('app.color.console_button_secondary'))
                  .borderRadius(6)
                  .onClick(() => {
                    this.settings!.maxLogEntries = 500;
                    consolePanel.updateSettings({ maxLogEntries: 500 });
                  });
                Button('1000')
                  .fontSize(10)
                  .height(28)
                  .layoutWeight(1)
                  .backgroundColor(this.settings.maxLogEntries === 1000 ? $r('app.color.console_button_primary') : $r('app.color.console_button_secondary'))
                  .borderRadius(6)
                  .onClick(() => {
                    this.settings!.maxLogEntries = 1000;
                    consolePanel.updateSettings({ maxLogEntries: 1000 });
                  });
                Button('2000')
                  .fontSize(10)
                  .height(28)
                  .layoutWeight(1)
                  .backgroundColor(this.settings.maxLogEntries === 2000 ? $r('app.color.console_button_primary') : $r('app.color.console_button_secondary'))
                  .borderRadius(6)
                  .onClick(() => {
                    this.settings!.maxLogEntries = 2000;
                    consolePanel.updateSettings({ maxLogEntries: 2000 });
                  });
                Button('5000')
                  .fontSize(10)
                  .height(28)
                  .layoutWeight(1)
                  .backgroundColor(this.settings.maxLogEntries === 5000 ? $r('app.color.console_button_primary') : $r('app.color.console_button_secondary'))
                  .borderRadius(6)
                  .onClick(() => {
                    this.settings!.maxLogEntries = 5000;
                    consolePanel.updateSettings({ maxLogEntries: 5000 });
                  });
              }.width('100%');
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 16, bottom: 16 } as PaddingStyle)
          .backgroundColor($r('app.color.console_background_darker'))
          .borderRadius(12)
          .border({ width: 1, color: $r('app.color.console_border_subtle') });

          // 操作按钮
          Column({ space: 12 }) {
            Row({ space: 8 }) {
              Text('🔧')
                .fontSize(16);
              Text('操作')
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.console_text_white'));
            }

            Row({ space: 12 }) {
              Button() {
                Row({ space: 6 }) {
                  Text('🗑️').fontSize(14);
                  Text('清空日志').fontSize(12).fontColor($r('app.color.console_text_white'));
                }
              }
              .height(40)
              .backgroundColor($r('app.color.console_button_danger'))
              .borderRadius(8)
              .layoutWeight(1)
              .onClick(() => {
                consolePanel.clearLogs();
                this.loadData();
              });

              Button() {
                Row({ space: 6 }) {
                  Text('🔄').fontSize(14);
                  Text('重置设置').fontSize(12).fontColor($r('app.color.console_text_white'));
                }
              }
              .height(40)
              .backgroundColor($r('app.color.console_button_warning'))
              .borderRadius(8)
              .layoutWeight(1)
              .onClick(() => {
                consolePanel.updateSettings({
                  autoScroll: true,
                  maxLogEntries: 1000,
                  showTimestamp: true,
                  logLevel: LogLevel.DEBUG,
                  enableLogCollection: true,
                  refreshInterval: 1000
                });
                this.settings = consolePanel.getSettings();
              });
            }.width('100%');
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 16, bottom: 16 } as PaddingStyle)
          .backgroundColor($r('app.color.console_background_darker'))
          .borderRadius(12)
          .border({ width: 1, color: $r('app.color.console_border_subtle') });

          // 高级调试选项
          Column({ space: 12 }) {
            Row({ space: 8 }) {
              Text('⚙️')
                .fontSize(16);
              Text('高级调试')
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.console_text_white'));
            }

            Row({ space: 8 }) {
              Button() {
                Row({ space: 4 }) {
                  Text('📋').fontSize(12);
                  Text('复制错误').fontSize(10).fontColor($r('app.color.console_text_white'));
                }
              }
              .height(36)
              .backgroundColor($r('app.color.console_button_danger'))
              .borderRadius(6)
              .layoutWeight(1)
              .onClick(() => {
                this.copyErrorLogs();
              });

              Button() {
                Row({ space: 4 }) {
                  Text('💾').fontSize(12);
                  Text('错误报告').fontSize(10).fontColor($r('app.color.console_text_white'));
                }
              }
              .height(36)
              .backgroundColor($r('app.color.console_button_purple'))
              .borderRadius(6)
              .layoutWeight(1)
              .onClick(() => {
                this.generateErrorLogFile();
              });
            }.width('100%');

            Row({ space: 8 }) {
              Button() {
                Row({ space: 4 }) {
                  Text('📤').fontSize(12);
                  Text('导出全部').fontSize(10).fontColor($r('app.color.console_text_white'));
                }
              }
              .height(36)
              .backgroundColor($r('app.color.console_button_info'))
              .borderRadius(6)
              .layoutWeight(1)
              .onClick(() => {
                this.exportAllLogs();
              });

              Button() {
                Row({ space: 4 }) {
                  Text('📊').fontSize(12);
                  Text('性能报告').fontSize(10).fontColor($r('app.color.console_text_white'));
                }
              }
              .height(36)
              .backgroundColor($r('app.color.console_button_success'))
              .borderRadius(6)
              .layoutWeight(1)
              .onClick(() => {
                this.generatePerformanceReport();
              });
            }.width('100%');

            Row({ space: 8 }) {
              Button() {
                Row({ space: 4 }) {
                  Text('🔍').fontSize(12);
                  Text('系统诊断').fontSize(10).fontColor($r('app.color.console_text_white'));
                }
              }
              .height(36)
              .backgroundColor($r('app.color.console_button_primary'))
              .borderRadius(6)
              .layoutWeight(1)
              .onClick(() => {
                this.quickDiagnosis();
              });

              Button() {
                Row({ space: 4 }) {
                  Text('🧹').fontSize(12);
                  Text('清理缓存').fontSize(10).fontColor($r('app.color.console_text_white'));
                }
              }
              .height(36)
              .backgroundColor($r('app.color.console_button_warning'))
              .borderRadius(6)
              .layoutWeight(1)
              .onClick(() => {
                this.clearMemoryCache();
              });
            }.width('100%');
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 16, bottom: 16 } as PaddingStyle)
          .backgroundColor($r('app.color.console_background_darker'))
          .borderRadius(12)
          .border({ width: 1, color: $r('app.color.console_border_subtle') });
        }
      }
      .width('100%')
      .padding({ left: 8, right: 8, top: 8, bottom: 8 } as PaddingStyle);
    }
    .width('100%')
    .height('100%');
  }

  @Builder SettingsToggle(label: string, value: boolean, action: (val: boolean) => void) {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text(label)
          .fontSize(13)
          .fontColor($r('app.color.console_text_white'))
          .fontWeight(FontWeight.Medium);
        Text(value ? '已启用' : '已禁用')
          .fontSize(10)
          .fontColor(value ? $r('app.color.console_button_success') : $r('app.color.console_text_placeholder'));
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1);

      Toggle({ type: ToggleType.Switch, isOn: value })
        .selectedColor($r('app.color.console_button_primary'))
        .switchPointColor($r('app.color.console_text_white'))
        .backgroundColor(value ? $r('app.color.console_button_primary') : $r('app.color.console_button_secondary'))
        .onChange(action);
    }
    .width('100%')
    .height(48)
    .padding(12)
    .backgroundColor($r('app.color.console_panel_dark'))
    .borderRadius(8)
    .justifyContent(FlexAlign.SpaceBetween)
    .alignItems(VerticalAlign.Center);
  }

  // --- 辅助方法 ---
  stringToLogLevel(levelStr: string): LogLevel {
    switch (levelStr.toLowerCase()) {
      case 'debug': return LogLevel.DEBUG;
      case 'info': return LogLevel.INFO;
      case 'warn': return LogLevel.WARN;
      case 'error': return LogLevel.ERROR;
      default: return LogLevel.INFO;
    }
  }

  getLogLevelColor(level: LogLevel): ResourceStr {
    switch (level) {
      case LogLevel.DEBUG: return ThemeAwareHelper.getTestManagementThemedColor('button_secondary', this.themeState.currentTheme);
      case LogLevel.INFO: return ThemeAwareHelper.getTestManagementThemedColor('button_primary', this.themeState.currentTheme);
      case LogLevel.WARN: return ThemeAwareHelper.getTestManagementThemedColor('button_warning', this.themeState.currentTheme);
      case LogLevel.ERROR: return ThemeAwareHelper.getTestManagementThemedColor('button_danger', this.themeState.currentTheme);
      default: return ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme);
    }
  }
}
