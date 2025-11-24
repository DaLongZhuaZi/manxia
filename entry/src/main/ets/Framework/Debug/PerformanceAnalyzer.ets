// 文件路径: src/main/ets/Framework/Debug/PerformanceAnalyzer.ets
/**
 * 性能分析器
 * 用于分析和监控游戏运行时的性能指标，提供警告和建议。
 */
 
import { logger } from '../../Utils/Logger';
import { eventBus, GameEvent, IEventPayload } from '../EventBus';
import { HidebugPerformanceCollector } from './HidebugPerformanceCollector';
import { TimeUtils } from '../Utils/TimeUtils';

const PERFORMANCE_ANALYZER_TAG = 'PerformanceAnalyzer';

/**
 * 性能指标接口
 */
interface FrameRateMetrics {
  current: number;
  average: number;
  min: number;
  max: number;
  history: number[];
}

interface FrameTimeMetrics {
  current: number; // 毫秒
  average: number;
  min: number;
  max: number;
  history: number[];
}

interface MemoryMetrics {
  used: number; // MB
  peak: number;
  total: number; // MB - 总内存
  history: number[];
}

export interface PerformanceMetrics {
  frameRate: FrameRateMetrics;
  frameTime: FrameTimeMetrics;
  memory: MemoryMetrics;
  systems: SystemMetrics[];
  rendering: RenderingMetrics;
  cpu: CPUMetrics;
}

/**
 * 系统性能指标
 */
export interface SystemMetrics {
  name: string;
  executionTime: number; // 毫秒
  averageTime: number;
  minTime: number;
  maxTime: number;
  callCount: number;
  cpuUsage: number; // 百分比
}

/**
 * 渲染性能指标
 */
export interface RenderingMetrics {
  drawCalls: number;
  triangles: number;
  vertices: number;
  textureMemory: number; // MB
  shaderSwitches: number;
  renderTargetSwitches: number;
}

/**
 * CPU性能指标
 */
export interface CPUMetrics {
  usage: number; // 百分比
  temperature: number; // 摄氏度
  frequency: number; // MHz
}

/**
 * 性能警告类型
 */
export enum PerformanceWarningType {
  LOW_FPS = 'low_fps',
  HIGH_FRAME_TIME = 'high_frame_time',
  HIGH_MEMORY = 'high_memory',
  SLOW_SYSTEM = 'slow_system',
  HIGH_CPU = 'high_cpu'
}

/**
 * 性能警告
 */
export interface PerformanceWarning {
  type: PerformanceWarningType;
  message: string;
  severity: 'low' | 'medium' | 'high';
  timestamp: number;
  value: number;
  threshold: number;
}

/**
 * 性能警告事件载荷
 */
export class PerformanceWarningPayload implements IEventPayload {
  public warning: PerformanceWarning;

  constructor(warning: PerformanceWarning) {
    this.warning = warning;
  }
}

/**
 * 性能分析器
 * 监控和分析游戏性能，提供性能优化建议
 */
interface PerformanceThresholds {
  minFPS: number;
  maxFrameTime: number;
  maxMemory: number;
  maxSystemTime: number;
  maxCPUUsage: number;
}

interface PerformanceReport {
  timestamp: string;
  metrics: PerformanceMetrics;
  warnings: PerformanceWarning[];
  recommendations: string[];
}

export class PerformanceAnalyzer {
  private static instance: PerformanceAnalyzer;
  private isEnabled: boolean = false;
  private metrics: PerformanceMetrics;
  private systemMetrics: Map<string, SystemMetrics> = new Map();
  private warnings: PerformanceWarning[] = [];
  private maxHistorySize: number = 300; // 5分钟的历史数据（60fps）
  private maxWarningsSize: number = 100;
  private lastUpdateTime: number = 0;
  private sampleInterval: number = 1000; // 采样间隔（毫秒）
  private lastSampleTime: number = 0;
  
  // 性能阈值
  private thresholds: PerformanceThresholds = {
    minFPS: 30,
    maxFrameTime: 33.33, // 毫秒 (30fps)
    maxMemory: 512, // MB
    maxSystemTime: 16.67, // 毫秒 (60fps)
    maxCPUUsage: 80 // 百分比
  };

  private constructor() {
    this.metrics = this.initializeMetrics();
    this.loadThresholds();
  }

  public static getInstance(): PerformanceAnalyzer {
    if (!PerformanceAnalyzer.instance) {
      PerformanceAnalyzer.instance = new PerformanceAnalyzer();
    }
    return PerformanceAnalyzer.instance;
  }

  /**
   * 启用性能分析
   */
  public enable(): void {
    this.isEnabled = true;
    this.lastUpdateTime = Date.now();
    this.lastSampleTime = this.lastUpdateTime;
    logger.info(PERFORMANCE_ANALYZER_TAG, 'Performance analyzer enabled');
  }

  /**
   * 禁用性能分析
   */
  public disable(): void {
    this.isEnabled = false;
    logger.info(PERFORMANCE_ANALYZER_TAG, 'Performance analyzer disabled');
  }

  /**
   * 检查是否启用
   */
  public isAnalyzerEnabled(): boolean {
    return this.isEnabled;
  }

  /**
   * 更新性能分析
   */
  public update(deltaTime: number): void {
    if (!this.isEnabled) {
      return;
    }

    const currentTime = Date.now();
    
    // 更新帧率和帧时间
    this.updateFrameMetrics(deltaTime);
    
    // 定期采样其他指标
    if (currentTime - this.lastSampleTime >= this.sampleInterval) {
      this.sampleMetrics();
      this.checkPerformanceWarnings();
      this.lastSampleTime = currentTime;
    }
    
    this.lastUpdateTime = currentTime;
  }

  /**
   * 记录系统性能
   */
  public recordSystemPerformance(systemName: string, executionTime: number): void {
    if (!this.isEnabled) {
      return;
    }

    let systemMetric = this.systemMetrics.get(systemName);
    
    if (!systemMetric) {
      systemMetric = {
        name: systemName,
        executionTime: executionTime,
        averageTime: executionTime,
        minTime: executionTime,
        maxTime: executionTime,
        callCount: 1,
        cpuUsage: 0
      };
    } else {
      systemMetric.executionTime = executionTime;
      systemMetric.callCount++;
      systemMetric.averageTime = (systemMetric.averageTime * (systemMetric.callCount - 1) + executionTime) / systemMetric.callCount;
      systemMetric.minTime = Math.min(systemMetric.minTime, executionTime);
      systemMetric.maxTime = Math.max(systemMetric.maxTime, executionTime);
    }
    
    this.systemMetrics.set(systemName, systemMetric);
    this.metrics.systems = Array.from(this.systemMetrics.values());
  }

  /**
   * 记录渲染性能
   */
  public recordRenderingMetrics(drawCalls: number, triangles: number, vertices: number): void {
    if (!this.isEnabled) {
      return;
    }

    this.metrics.rendering.drawCalls = drawCalls;
    this.metrics.rendering.triangles = triangles;
    this.metrics.rendering.vertices = vertices;
  }

  /**
   * 获取当前性能指标
   */
  public getMetrics(): PerformanceMetrics {
    return JSON.parse(JSON.stringify(this.metrics));
  }

  /**
   * 获取性能警告
   */
  public getWarnings(): PerformanceWarning[] {
    const result: PerformanceWarning[] = [];
    for (let i = 0; i < this.warnings.length; i++) {
      result.push(this.warnings[i]);
    }
    return result;
  }

  /**
   * 清除性能警告
   */
  public clearWarnings(): void {
    this.warnings = [];
    logger.info(PERFORMANCE_ANALYZER_TAG, 'Performance warnings cleared');
  }

  /**
   * 获取性能报告
   */
  public generateReport(): string {
    const report: PerformanceReport = {
      timestamp: TimeUtils.toISOString(Date.now()),
      metrics: this.metrics,
      warnings: this.warnings,
      recommendations: this.generateRecommendations()
    };
    
    return JSON.stringify(report, null, 2);
  }

  /**
   * 重置性能数据
   */
  public reset(): void {
    this.metrics = this.initializeMetrics();
    this.systemMetrics.clear();
    this.warnings = [];
    logger.info(PERFORMANCE_ANALYZER_TAG, 'Performance data reset');
  }

  /**
   * 设置性能阈值
   */
  public setThresholds(newThresholds: Partial<PerformanceThresholds>): void {
    if (newThresholds.minFPS !== undefined) {
      this.thresholds.minFPS = newThresholds.minFPS;
    }
    if (newThresholds.maxFrameTime !== undefined) {
      this.thresholds.maxFrameTime = newThresholds.maxFrameTime;
    }
    if (newThresholds.maxMemory !== undefined) {
      this.thresholds.maxMemory = newThresholds.maxMemory;
    }
    if (newThresholds.maxSystemTime !== undefined) {
      this.thresholds.maxSystemTime = newThresholds.maxSystemTime;
    }
    if (newThresholds.maxCPUUsage !== undefined) {
      this.thresholds.maxCPUUsage = newThresholds.maxCPUUsage;
    }
    logger.info(PERFORMANCE_ANALYZER_TAG, 'Performance thresholds updated');
  }

  /**
   * 获取性能阈值
   */
  public getThresholds(): PerformanceThresholds {
    return {
      minFPS: this.thresholds.minFPS,
      maxFrameTime: this.thresholds.maxFrameTime,
      maxMemory: this.thresholds.maxMemory,
      maxSystemTime: this.thresholds.maxSystemTime,
      maxCPUUsage: this.thresholds.maxCPUUsage
    };
  }

  /**
   * 初始化性能指标
   */
  private initializeMetrics(): PerformanceMetrics {
    return {
      frameRate: {
        current: 0,
        average: 0,
        min: Number.MAX_VALUE,
        max: 0,
        history: []
      },
      frameTime: {
        current: 0,
        average: 0,
        min: Number.MAX_VALUE,
        max: 0,
        history: []
      },
      memory: {
        used: 0,
        peak: 0,
        total: 1024, // 默认1GB总内存
        history: []
      },
      systems: [],
      rendering: {
        drawCalls: 0,
        triangles: 0,
        vertices: 0,
        textureMemory: 0,
        shaderSwitches: 0,
        renderTargetSwitches: 0
      },
      cpu: {
        usage: 0,
        temperature: 0,
        frequency: 0
      }
    };
  }

  /**
   * 更新帧率指标
   */
  private updateFrameMetrics(deltaTime: number): void {
    if (deltaTime <= 0) return;

    const frameRate = 1.0 / deltaTime;
    const frameTime = deltaTime * 1000; // 转换为毫秒

    // 更新帧率
    this.metrics.frameRate.current = frameRate;
    this.metrics.frameRate.min = Math.min(this.metrics.frameRate.min, frameRate);
    this.metrics.frameRate.max = Math.max(this.metrics.frameRate.max, frameRate);
    this.metrics.frameRate.history.push(frameRate);

    // 更新帧时间
    this.metrics.frameTime.current = frameTime;
    this.metrics.frameTime.min = Math.min(this.metrics.frameTime.min, frameTime);
    this.metrics.frameTime.max = Math.max(this.metrics.frameTime.max, frameTime);
    this.metrics.frameTime.history.push(frameTime);

    // 限制历史数据大小
    if (this.metrics.frameRate.history.length > this.maxHistorySize) {
      this.metrics.frameRate.history.shift();
    }
    if (this.metrics.frameTime.history.length > this.maxHistorySize) {
      this.metrics.frameTime.history.shift();
    }

    // 计算平均值
    this.metrics.frameRate.average = this.calculateAverage(this.metrics.frameRate.history);
    this.metrics.frameTime.average = this.calculateAverage(this.metrics.frameTime.history);
  }

  /**
   * 采样其他性能指标
   */
  private sampleMetrics(): void {
    // 采样内存使用
    const memoryUsed = this.getMemoryUsage();
    this.metrics.memory.used = memoryUsed;
    this.metrics.memory.peak = Math.max(this.metrics.memory.peak, memoryUsed);
    this.metrics.memory.history.push(memoryUsed);
    
    if (this.metrics.memory.history.length > this.maxHistorySize) {
      this.metrics.memory.history.shift();
    }

    // 采样CPU指标
    this.metrics.cpu = this.getCPUMetrics();
  }

  /**
   * 检查性能警告
   */
  private checkPerformanceWarnings(): void {
    const currentTime = Date.now();

    // 检查帧率
    if (this.metrics.frameRate.current < this.thresholds.minFPS) {
      this.addWarning({
        type: PerformanceWarningType.LOW_FPS,
        message: `Low frame rate: ${typeof this.metrics.frameRate.current === 'number' ? this.metrics.frameRate.current.toFixed(1) : '未知'} FPS`,
        severity: this.metrics.frameRate.current < 15 ? 'high' : 'medium',
        timestamp: currentTime,
        value: this.metrics.frameRate.current,
        threshold: this.thresholds.minFPS
      });
    }

    // 检查帧时间
    if (this.metrics.frameTime.current > this.thresholds.maxFrameTime) {
      this.addWarning({
        type: PerformanceWarningType.HIGH_FRAME_TIME,
        message: `High frame time: ${typeof this.metrics.frameTime.current === 'number' ? this.metrics.frameTime.current.toFixed(2) : '未知'} ms`,
        severity: this.metrics.frameTime.current > 50 ? 'high' : 'medium',
        timestamp: currentTime,
        value: this.metrics.frameTime.current,
        threshold: this.thresholds.maxFrameTime
      });
    }

    // 检查内存使用
    if (this.metrics.memory.used > this.thresholds.maxMemory) {
      this.addWarning({
        type: PerformanceWarningType.HIGH_MEMORY,
        message: `High memory usage: ${typeof this.metrics.memory.used === 'number' ? this.metrics.memory.used.toFixed(1) : '未知'} MB`,
        severity: this.metrics.memory.used > this.thresholds.maxMemory * 1.5 ? 'high' : 'medium',
        timestamp: currentTime,
        value: this.metrics.memory.used,
        threshold: this.thresholds.maxMemory
      });
    }

    // 检查系统性能
    for (const system of this.metrics.systems) {
      if (system.executionTime > this.thresholds.maxSystemTime) {
        this.addWarning({
          type: PerformanceWarningType.SLOW_SYSTEM,
          message: `Slow system '${system.name}': ${typeof system.executionTime === 'number' ? system.executionTime.toFixed(2) : '未知'} ms`,
          severity: system.executionTime > this.thresholds.maxSystemTime * 2 ? 'high' : 'medium',
          timestamp: currentTime,
          value: system.executionTime,
          threshold: this.thresholds.maxSystemTime
        });
      }
    }

    // 检查CPU使用率
    if (this.metrics.cpu.usage > this.thresholds.maxCPUUsage) {
      this.addWarning({
        type: PerformanceWarningType.HIGH_CPU,
        message: `High CPU usage: ${typeof this.metrics.cpu.usage === 'number' ? this.metrics.cpu.usage.toFixed(1) : '未知'}%`,
        severity: this.metrics.cpu.usage > 95 ? 'high' : 'medium',
        timestamp: currentTime,
        value: this.metrics.cpu.usage,
        threshold: this.thresholds.maxCPUUsage
      });
    }
  }

  /**
   * 添加性能警告
   */
  private addWarning(warning: PerformanceWarning): void {
    this.warnings.push(warning);
    
    // 限制警告数量
    if (this.warnings.length > this.maxWarningsSize) {
      this.warnings.shift();
    }

    // 发布警告事件
    eventBus.publish(GameEvent.PERFORMANCE_WARNING, new PerformanceWarningPayload(warning));
    
    logger.warn(PERFORMANCE_ANALYZER_TAG, warning.message);
  }

  /**
   * 计算平均值
   */
  private calculateAverage(values: number[]): number {
    if (values.length === 0) return 0;
    return values.reduce((sum, value) => sum + value, 0) / values.length;
  }

  /**
   * 获取内存使用量（模拟）
   */
  private getMemoryUsage(): number {
    // HarmonyOS 没有直接的内存API，这里返回模拟值
    return Math.random() * 200 + 100; // 100-300 MB
  }

  /**
   * 获取CPU指标（模拟）
   */
  private getCPUMetrics(): CPUMetrics {
    return {
      usage: Math.random() * 100,
      temperature: Math.random() * 30 + 40, // 40-70°C
      frequency: Math.random() * 1000 + 2000 // 2000-3000 MHz
    };
  }

  /**
   * 生成性能优化建议
   */
  private generateRecommendations(): string[] {
    const recommendations: string[] = [];

    if (this.metrics.frameRate.average < 30) {
      recommendations.push('考虑降低图形质量设置以提高帧率');
      recommendations.push('检查是否有性能瓶颈的系统');
    }

    if (this.metrics.memory.used > 400) {
      recommendations.push('考虑优化内存使用，释放不必要的资源');
      recommendations.push('检查是否存在内存泄漏');
    }

    const slowSystems = this.metrics.systems.filter(s => s.averageTime > 10);
    if (slowSystems.length > 0) {
      recommendations.push(`优化以下系统的性能: ${slowSystems.map(s => s.name).join(', ')}`);
    }

    if (this.metrics.rendering.drawCalls > 1000) {
      recommendations.push('考虑减少绘制调用次数，使用批量渲染');
    }

    return recommendations;
  }

  /**
   * 从配置加载阈值
   */
  private loadThresholds(): void {
    // 使用默认阈值，不再依赖配置管理器
    logger.debug(PERFORMANCE_ANALYZER_TAG, '使用默认性能阈值');
  }
}

// 导出单例实例
export const performanceAnalyzer = PerformanceAnalyzer.getInstance();