// 文件路径: src/main/ets/Framework/Debug/HidebugPerformanceCollector.ets
/**
 * Hidebug性能采集器
 * 利用hidebug SDK提供的性能监控功能，采集应用运行时的内存、CPU、GC和调试状态等性能指标。
 */
 
import { hidebug } from '@kit.PerformanceAnalysisKit';
import { logger } from '../../Utils/Logger';

const HIDEBUG_COLLECTOR_TAG = 'HidebugPerformanceCollector';

/**
 * 内存信息接口
 */
export interface HidebugMemoryInfo {
  // 堆内存信息
  nativeHeapSize: number;           // 进程持有的堆内存大小（含分配器元数据）
  nativeHeapAllocatedSize: number;  // 进程业务分配的堆内存大小
  nativeHeapFreeSize: number;       // 内存分配器持有的缓存内存大小
  
  // 物理内存信息
  pss: number;                      // 应用进程实际使用的物理内存大小
  vss: number;                      // 应用进程虚拟耗用内存大小
  sharedDirty: number;              // 进程的共享脏内存大小
  privateDirty: number;             // 进程的私有脏内存大小
  
  // VM内存信息
  vmMemoryInfo: hidebug.VMMemoryInfo | null;
  
  // 应用内存限制
  appMemoryLimit: number;
  
  // 显存信息
  graphicsMemory: number;
  
  // 应用进程内存详细信息
  appNativeMemInfo: hidebug.NativeMemInfo | null;
  
  // 系统内存信息
  systemMemInfo: hidebug.SystemMemInfo | null;
}

/**
 * CPU信息接口
 */
export interface HidebugCpuInfo {
  // 进程CPU使用率
  cpuUsage: number;
  
  // 系统CPU使用情况
  systemCpuUsage: number;
  
  // 应用线程CPU使用情况
  appThreadCpuUsage: hidebug.ThreadCpuUsage[] | null;
}

/**
 * GC统计信息接口
 */
export interface HidebugGcInfo {
  // VM运行时统计信息
  vmRuntimeStats: hidebug.GcStats | null;
  
  // 特定GC统计信息
  gcCount: number;
  gcTime: number;
  gcBytesAllocated: number;
  gcBytesFreed: number;
  fullgcLongtimeCount: number;
}

/**
 * 调试状态信息接口
 */
export interface HidebugDebugInfo {
  // 应用调试状态
  isDebugState: boolean;
  
  // GWP-Asan状态
  gwpAsanState: number;
}

/**
 * 完整的hidebug性能信息
 */
export interface HidebugPerformanceData {
  timestamp: number;
  memory: HidebugMemoryInfo;
  cpu: HidebugCpuInfo;
  gc: HidebugGcInfo;
  debug: HidebugDebugInfo;
  collectDuration: number; // 数据收集耗时（毫秒）
}

/**
 * 性能数据历史记录
 */
export interface PerformanceHistory {
  timestamps: number[];
  memoryUsage: number[];
  cpuUsage: number[];
  gcCount: number[];
  heapSize: number[];
}

/**
 * 内存性能摘要
 */
export interface MemoryPerformanceSummary {
  current: number;
  average: number;
  peak: number;
}

/**
 * CPU性能摘要
 */
export interface CpuPerformanceSummary {
  current: number;
  average: number;
  peak: number;
}

/**
 * GC性能摘要
 */
export interface GcPerformanceSummary {
  totalCount: number;
  averageHeapSize: number;
}

/**
 * 性能摘要接口
 */
export interface PerformanceSummary {
  memory: MemoryPerformanceSummary;
  cpu: CpuPerformanceSummary;
  gc: GcPerformanceSummary;
}

/**
 * Hidebug性能数据收集器
 * 使用HarmonyOS的hidebug API收集详细的系统性能信息
 */
export class HidebugPerformanceCollector {
  private static instance: HidebugPerformanceCollector | undefined;
  private isEnabled: boolean = false;
  private collectInterval: number = 1000; // 收集间隔（毫秒）
  private maxHistorySize: number = 300; // 最大历史记录数量（5分钟）
  private history: PerformanceHistory;
  private lastCollectTime: number = 0;
  private collectTimer: number | null = null;
  private isCollecting: boolean = false;

  private constructor() {
    this.history = {
      timestamps: [],
      memoryUsage: [],
      cpuUsage: [],
      gcCount: [],
      heapSize: []
    };
  }

  public static getInstance(): HidebugPerformanceCollector {
    if (!HidebugPerformanceCollector.instance) {
      HidebugPerformanceCollector.instance = new HidebugPerformanceCollector();
    }
    return HidebugPerformanceCollector.instance;
  }

  /**
   * 启用性能数据收集
   */
  public enable(): void {
    if (this.isEnabled) {
      return;
    }
    
    this.isEnabled = true;
    this.startAutoCollection();
    logger.info(HIDEBUG_COLLECTOR_TAG, '性能数据收集已启用');
  }

  /**
   * 禁用性能数据收集
   */
  public disable(): void {
    if (!this.isEnabled) {
      return;
    }
    
    this.isEnabled = false;
    this.stopAutoCollection();
    logger.info(HIDEBUG_COLLECTOR_TAG, '性能数据收集已禁用');
  }

  /**
   * 检查是否启用
   */
  public isCollectorEnabled(): boolean {
    return this.isEnabled;
  }

  /**
   * 设置收集间隔
   */
  public setCollectInterval(interval: number): void {
    this.collectInterval = Math.max(500, interval); // 最小500ms
    if (this.isEnabled) {
      this.stopAutoCollection();
      this.startAutoCollection();
    }
    logger.info(HIDEBUG_COLLECTOR_TAG, `收集间隔已设置为 ${this.collectInterval}ms`);
  }

  /**
   * 开始自动收集
   */
  private startAutoCollection(): void {
    if (this.collectTimer !== null) {
      return;
    }
    
    this.collectTimer = setInterval(() => {
      this.collectPerformanceData();
    }, this.collectInterval);
  }

  /**
   * 停止自动收集
   */
  private stopAutoCollection(): void {
    if (this.collectTimer !== null) {
      clearInterval(this.collectTimer);
      this.collectTimer = null;
    }
  }

  /**
   * 收集性能数据
   */
  public async collectPerformanceData(): Promise<HidebugPerformanceData | null> {
    if (this.isCollecting) {
      return null; // 避免重复收集
    }
    
    this.isCollecting = true;
    const startTime = Date.now();
    
    try {
      const data: HidebugPerformanceData = {
        timestamp: startTime,
        memory: await this.collectMemoryInfo(),
        cpu: await this.collectCpuInfo(),
        gc: await this.collectGcInfo(),
        debug: await this.collectDebugInfo(),
        collectDuration: 0
      };
      
      data.collectDuration = Date.now() - startTime;
      
      // 更新历史记录
      this.updateHistory(data);
      
      this.lastCollectTime = startTime;
      return data;
    } catch (error) {
      logger.error(HIDEBUG_COLLECTOR_TAG, `收集性能数据失败: ${(error as Error).message}`);
      return null;
    } finally {
      this.isCollecting = false;
    }
  }

  /**
   * 收集内存信息
   */
  private async collectMemoryInfo(): Promise<HidebugMemoryInfo> {
    const memoryInfo: HidebugMemoryInfo = {
      nativeHeapSize: 0,
      nativeHeapAllocatedSize: 0,
      nativeHeapFreeSize: 0,
      pss: 0,
      vss: 0,
      sharedDirty: 0,
      privateDirty: 0,
      vmMemoryInfo: null,
      appMemoryLimit: 0,
      graphicsMemory: 0,
      appNativeMemInfo: null,
      systemMemInfo: null
    };

    try {
      // 获取堆内存信息（bigint转number）
      memoryInfo.nativeHeapSize = Number(hidebug.getNativeHeapSize());
      memoryInfo.nativeHeapAllocatedSize = Number(hidebug.getNativeHeapAllocatedSize());
      memoryInfo.nativeHeapFreeSize = Number(hidebug.getNativeHeapFreeSize());
      
      // 获取物理内存信息（bigint转number）
      memoryInfo.pss = Number(hidebug.getPss());
      memoryInfo.vss = Number(hidebug.getVss());
      memoryInfo.sharedDirty = Number(hidebug.getSharedDirty());
      memoryInfo.privateDirty = Number(hidebug.getPrivateDirty());
      
      // 获取VM内存信息
      memoryInfo.vmMemoryInfo = hidebug.getAppVMMemoryInfo();
      
      // 获取应用内存限制（MemoryLimit转number）
      const memoryLimit = hidebug.getAppMemoryLimit();
      memoryInfo.appMemoryLimit = Number(memoryLimit);
      
      // 获取显存信息（同步方式）
      memoryInfo.graphicsMemory = hidebug.getGraphicsMemorySync();
      
      // 获取应用进程内存详细信息
      memoryInfo.appNativeMemInfo = hidebug.getAppNativeMemInfo();
      
      // 获取系统内存信息
      memoryInfo.systemMemInfo = hidebug.getSystemMemInfo();
      
    } catch (error) {
      logger.warn(HIDEBUG_COLLECTOR_TAG, `收集内存信息时出现错误: ${(error as Error).message}`);
    }

    return memoryInfo;
  }

  /**
   * 收集CPU信息
   */
  private async collectCpuInfo(): Promise<HidebugCpuInfo> {
    const cpuInfo: HidebugCpuInfo = {
      cpuUsage: 0,
      systemCpuUsage: 0,
      appThreadCpuUsage: null
    };

    try {
      // 获取进程CPU使用率
      cpuInfo.cpuUsage = hidebug.getCpuUsage();
      
      // 获取系统CPU使用情况
      cpuInfo.systemCpuUsage = hidebug.getSystemCpuUsage();
      
      // 获取应用线程CPU使用情况
      cpuInfo.appThreadCpuUsage = hidebug.getAppThreadCpuUsage();
      
    } catch (error) {
      logger.warn(HIDEBUG_COLLECTOR_TAG, `收集CPU信息时出现错误: ${(error as Error).message}`);
    }

    return cpuInfo;
  }

  /**
   * 收集GC信息
   */
  private async collectGcInfo(): Promise<HidebugGcInfo> {
    const gcInfo: HidebugGcInfo = {
      vmRuntimeStats: null,
      gcCount: 0,
      gcTime: 0,
      gcBytesAllocated: 0,
      gcBytesFreed: 0,
      fullgcLongtimeCount: 0
    };

    try {
      // 获取VM运行时统计信息
      gcInfo.vmRuntimeStats = hidebug.getVMRuntimeStats();
      
      // 从VM统计信息中提取GC相关数据
      if (gcInfo.vmRuntimeStats) {
        // 根据官方文档的GcStats结构提取数据
        gcInfo.gcCount = gcInfo.vmRuntimeStats['ark.gc.gc-count'] || 0;
        gcInfo.gcTime = gcInfo.vmRuntimeStats['ark.gc.gc-time'] || 0;
        gcInfo.gcBytesAllocated = gcInfo.vmRuntimeStats['ark.gc.gc-bytes-allocated'] || 0;
        gcInfo.gcBytesFreed = gcInfo.vmRuntimeStats['ark.gc.gc-bytes-freed'] || 0;
        gcInfo.fullgcLongtimeCount = gcInfo.vmRuntimeStats['ark.gc.fullgc-longtime-count'] || 0;
      }
      
    } catch (error) {
      logger.warn(HIDEBUG_COLLECTOR_TAG, `收集GC信息时出现错误: ${(error as Error).message}`);
    }

    return gcInfo;
  }

  /**
   * 收集调试信息
   */
  private async collectDebugInfo(): Promise<HidebugDebugInfo> {
    const debugInfo: HidebugDebugInfo = {
      isDebugState: false,
      gwpAsanState: 0
    };

    try {
      // 获取调试状态
      debugInfo.isDebugState = hidebug.isDebugState();
      
      // GWP-Asan状态获取
      // TODO: API 20启用后取消注释以下代码
      // try {
      //   // 使用正确的方法名获取GWP-Asan灰度状态
      //   debugInfo.gwpAsanState = hidebug.getGwpAsanGrayscaleState();
      // } catch (gwpError) {
      //   logger.warn(HIDEBUG_COLLECTOR_TAG, `GWP-Asan状态获取失败: ${(gwpError as Error).message}`);
      //   debugInfo.gwpAsanState = 0;
      // }
      
      // 临时返回默认值，等待API 20启用
      debugInfo.gwpAsanState = 0;
      
    } catch (error) {
      logger.warn(HIDEBUG_COLLECTOR_TAG, `收集调试信息时出现错误: ${(error as Error).message}`);
    }

    return debugInfo;
  }

  /**
   * 更新历史记录
   */
  private updateHistory(data: HidebugPerformanceData): void {
    const timestamps = this.history.timestamps;
    const memoryUsage = this.history.memoryUsage;
    const cpuUsage = this.history.cpuUsage;
    const gcCount = this.history.gcCount;
    const heapSize = this.history.heapSize;
    
    // 添加新数据
    timestamps.push(data.timestamp);
    memoryUsage.push(Number(data.memory.pss) / (1024 * 1024)); // 转换为MB
    cpuUsage.push(data.cpu.cpuUsage);
    gcCount.push(data.gc.gcCount);
    // 使用VM内存信息中的堆大小，如果没有则使用0
    const vmHeapSize = data.memory.vmMemoryInfo ? data.memory.vmMemoryInfo.totalHeap : 0;
    // 确保vmHeapSize是number类型后再进行运算
    const vmHeapSizeNumber = typeof vmHeapSize === 'bigint' ? Number(vmHeapSize) : vmHeapSize;
    heapSize.push(vmHeapSizeNumber / (1024 * 1024)); // 转换为MB
    
    // 限制历史记录大小
    if (timestamps.length > this.maxHistorySize) {
      timestamps.shift();
      memoryUsage.shift();
      cpuUsage.shift();
      gcCount.shift();
      heapSize.shift();
    }
  }

  /**
   * 获取当前性能数据
   */
  public getCurrentData(): HidebugPerformanceData | null {
    if (!this.isEnabled) {
      return null;
    }
    
    // 如果正在收集中，返回null避免冲突
    if (this.isCollecting) {
      return null;
    }
    
    // 同步收集当前数据
    return this.collectPerformanceDataSync();
  }

  /**
   * 同步收集性能数据（用于getCurrentData）
   */
  private collectPerformanceDataSync(): HidebugPerformanceData | null {
    const startTime = Date.now();
    
    try {
      const data: HidebugPerformanceData = {
        timestamp: startTime,
        memory: this.collectMemoryInfoSync(),
        cpu: this.collectCpuInfoSync(),
        gc: this.collectGcInfoSync(),
        debug: this.collectDebugInfoSync(),
        collectDuration: 0
      };
      
      data.collectDuration = Date.now() - startTime;
      return data;
    } catch (error) {
      logger.error(HIDEBUG_COLLECTOR_TAG, `同步收集性能数据失败: ${(error as Error).message}`);
      return null;
    }
  }

  /**
   * 同步收集内存信息
   */
  private collectMemoryInfoSync(): HidebugMemoryInfo {
    const memoryInfo: HidebugMemoryInfo = {
      nativeHeapSize: 0,
      nativeHeapAllocatedSize: 0,
      nativeHeapFreeSize: 0,
      pss: 0,
      vss: 0,
      sharedDirty: 0,
      privateDirty: 0,
      vmMemoryInfo: null,
      appMemoryLimit: 0,
      graphicsMemory: 0,
      appNativeMemInfo: null,
      systemMemInfo: null
    };

    try {
      // 获取堆内存信息（bigint转number）
      memoryInfo.nativeHeapSize = Number(hidebug.getNativeHeapSize());
      memoryInfo.nativeHeapAllocatedSize = Number(hidebug.getNativeHeapAllocatedSize());
      memoryInfo.nativeHeapFreeSize = Number(hidebug.getNativeHeapFreeSize());
      
      // 获取物理内存信息（bigint转number）
      memoryInfo.pss = Number(hidebug.getPss());
      memoryInfo.vss = Number(hidebug.getVss());
      memoryInfo.sharedDirty = Number(hidebug.getSharedDirty());
      memoryInfo.privateDirty = Number(hidebug.getPrivateDirty());
      
      // 获取VM内存信息
      memoryInfo.vmMemoryInfo = hidebug.getAppVMMemoryInfo();
      
      // 获取应用内存限制（MemoryLimit转number）
      const memoryLimit = hidebug.getAppMemoryLimit();
      memoryInfo.appMemoryLimit = Number(memoryLimit);
      
      // 获取显存信息（同步方式）
      memoryInfo.graphicsMemory = hidebug.getGraphicsMemorySync();
      
      // 获取应用进程内存详细信息
      memoryInfo.appNativeMemInfo = hidebug.getAppNativeMemInfo();
      
      // 获取系统内存信息
      memoryInfo.systemMemInfo = hidebug.getSystemMemInfo();
      
    } catch (error) {
      logger.warn(HIDEBUG_COLLECTOR_TAG, `同步收集内存信息时出现错误: ${(error as Error).message}`);
    }

    return memoryInfo;
  }

  /**
   * 同步收集CPU信息
   */
  private collectCpuInfoSync(): HidebugCpuInfo {
    const cpuInfo: HidebugCpuInfo = {
      cpuUsage: 0,
      systemCpuUsage: 0,
      appThreadCpuUsage: null
    };

    try {
      // 获取进程CPU使用率
      cpuInfo.cpuUsage = hidebug.getCpuUsage();
      
      // 获取系统CPU使用情况
      cpuInfo.systemCpuUsage = hidebug.getSystemCpuUsage();
      
      // 获取应用线程CPU使用情况
      cpuInfo.appThreadCpuUsage = hidebug.getAppThreadCpuUsage();
      
    } catch (error) {
      logger.warn(HIDEBUG_COLLECTOR_TAG, `同步收集CPU信息时出现错误: ${(error as Error).message}`);
    }

    return cpuInfo;
  }

  /**
   * 同步收集GC信息
   */
  private collectGcInfoSync(): HidebugGcInfo {
    const gcInfo: HidebugGcInfo = {
      vmRuntimeStats: null,
      gcCount: 0,
      gcTime: 0,
      gcBytesAllocated: 0,
      gcBytesFreed: 0,
      fullgcLongtimeCount: 0
    };

    try {
      // 获取VM运行时统计信息
      gcInfo.vmRuntimeStats = hidebug.getVMRuntimeStats();
      
      // 从VM统计信息中提取GC相关数据
      if (gcInfo.vmRuntimeStats) {
        // 根据官方文档的GcStats结构提取数据
        gcInfo.gcCount = gcInfo.vmRuntimeStats['ark.gc.gc-count'] || 0;
        gcInfo.gcTime = gcInfo.vmRuntimeStats['ark.gc.gc-time'] || 0;
        gcInfo.gcBytesAllocated = gcInfo.vmRuntimeStats['ark.gc.gc-bytes-allocated'] || 0;
        gcInfo.gcBytesFreed = gcInfo.vmRuntimeStats['ark.gc.gc-bytes-freed'] || 0;
        gcInfo.fullgcLongtimeCount = gcInfo.vmRuntimeStats['ark.gc.fullgc-longtime-count'] || 0;
      }
      
    } catch (error) {
      logger.warn(HIDEBUG_COLLECTOR_TAG, `同步收集GC信息时出现错误: ${(error as Error).message}`);
    }

    return gcInfo;
  }

  /**
   * 同步收集调试信息
   */
  private collectDebugInfoSync(): HidebugDebugInfo {
    const debugInfo: HidebugDebugInfo = {
      isDebugState: false,
      gwpAsanState: 0
    };

    try {
      // 获取调试状态
      debugInfo.isDebugState = hidebug.isDebugState();
      
      // GWP-Asan状态获取
      // TODO: API 20启用后取消注释以下代码
      // try {
      //   // 使用正确的方法名获取GWP-Asan灰度状态
      //   debugInfo.gwpAsanState = hidebug.getGwpAsanGrayscaleState();
      // } catch (gwpError) {
      //   logger.warn(HIDEBUG_COLLECTOR_TAG, `同步GWP-Asan状态获取失败: ${(gwpError as Error).message}`);
      //   debugInfo.gwpAsanState = 0;
      // }
      
      // 临时返回默认值，等待API 20启用
      debugInfo.gwpAsanState = 0;
      
    } catch (error) {
      logger.warn(HIDEBUG_COLLECTOR_TAG, `同步收集调试信息时出现错误: ${(error as Error).message}`);
    }

    return debugInfo;
  }

  /**
   * 获取历史记录
   */
  public getHistory(): PerformanceHistory {
    return {
      timestamps: this.history.timestamps.slice(),
      memoryUsage: this.history.memoryUsage.slice(),
      cpuUsage: this.history.cpuUsage.slice(),
      gcCount: this.history.gcCount.slice(),
      heapSize: this.history.heapSize.slice()
    };
  }

  /**
   * 清空历史记录
   */
  public clearHistory(): void {
    this.history = {
      timestamps: [],
      memoryUsage: [],
      cpuUsage: [],
      gcCount: [],
      heapSize: []
    };
    logger.info(HIDEBUG_COLLECTOR_TAG, '历史记录已清空');
  }

  /**
   * 获取性能摘要
   */
  public getPerformanceSummary(): PerformanceSummary {
    const memoryUsage = this.history.memoryUsage;
    const cpuUsage = this.history.cpuUsage;
    const gcCount = this.history.gcCount;
    const heapSize = this.history.heapSize;
    
    if (memoryUsage.length === 0) {
      const emptyMemory: MemoryPerformanceSummary = { current: 0, average: 0, peak: 0 };
      const emptyCpu: CpuPerformanceSummary = { current: 0, average: 0, peak: 0 };
      const emptyGc: GcPerformanceSummary = { totalCount: 0, averageHeapSize: 0 };
      const emptySummary: PerformanceSummary = {
        memory: emptyMemory,
        cpu: emptyCpu,
        gc: emptyGc
      };
      return emptySummary;
    }
    
    const memoryAvg = memoryUsage.reduce((sum, val) => sum + val, 0) / memoryUsage.length;
    let memoryPeak = 0;
    for (let i = 0; i < memoryUsage.length; i++) {
      if (memoryUsage[i] > memoryPeak) {
        memoryPeak = memoryUsage[i];
      }
    }
    const memoryCurrent = memoryUsage[memoryUsage.length - 1];
    
    const cpuAvg = cpuUsage.reduce((sum, val) => sum + val, 0) / cpuUsage.length;
    let cpuPeak = 0;
    for (let i = 0; i < cpuUsage.length; i++) {
      if (cpuUsage[i] > cpuPeak) {
        cpuPeak = cpuUsage[i];
      }
    }
    const cpuCurrent = cpuUsage[cpuUsage.length - 1];
    
    const gcTotal = gcCount.length > 0 ? gcCount[gcCount.length - 1] : 0;
    const heapAvg = heapSize.length > 0 ? heapSize.reduce((sum, val) => sum + val, 0) / heapSize.length : 0;
    
    const memorySummary: MemoryPerformanceSummary = { current: memoryCurrent, average: memoryAvg, peak: memoryPeak };
    const cpuSummary: CpuPerformanceSummary = { current: cpuCurrent, average: cpuAvg, peak: cpuPeak };
    const gcSummary: GcPerformanceSummary = { totalCount: gcTotal, averageHeapSize: heapAvg };
    
    const summary: PerformanceSummary = {
      memory: memorySummary,
      cpu: cpuSummary,
      gc: gcSummary
    };
    
    return summary;
  }

  /**
   * 销毁实例
   */
  public destroy(): void {
    this.disable();
    this.clearHistory();
    HidebugPerformanceCollector.instance = undefined;
  }
}

// 导出单例实例
export const hidebugPerformanceCollector = HidebugPerformanceCollector.getInstance();