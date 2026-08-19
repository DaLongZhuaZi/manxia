// 文件路径: src/main/ets/Framework/Components/PerformanceChart.ets
/**
 * 性能图表组件
 * 用于绘制性能数据的实时图表，支持传统动画系统
 */
 
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { PerformanceHistory } from '../Debug/HidebugPerformanceCollector';
import { ThemeManager } from '../Managers/ThemeManager';
import { ThemeType } from '../Managers/ThemeManager';
import { ThemeAwareHelper, ThemeAwareState } from '../Components/ThemeAware';


const CHART_TAG = 'PerformanceChart';

/**
 * 图表类型枚举
 */
export enum ChartType {
  MEMORY = 'memory',
  CPU = 'cpu',
  GC_COUNT = 'gc_count',
  HEAP_SIZE = 'heap_size'
}

/**
 * 图表数据点
 */
export interface ChartDataPoint {
  x: number; // 时间戳或索引
  y: number; // 数值
  label?: string; // 可选标签
}

/**
 * 图表配置
 */
export interface ChartConfig {
  type: ChartType;
  title: string;
  unit: string;
  color: ResourceStr;
  warningThreshold?: number;
  errorThreshold?: number;
  maxDataPoints: number;
}

/**
 * 性能图表组件
 * 用于绘制性能数据的实时图表
 */
@Component
export struct PerformanceChart {
  @Prop chartConfig: ChartConfig;
  @Prop performanceHistory: PerformanceHistory;
  @State chartData: ChartDataPoint[] = [];
  @State isVisible: boolean = true;
  @State maxValue: number = 100;
  @State minValue: number = 0;
  
  // 主题相关状态
  @State themeState: ThemeAwareState = new ThemeAwareState();
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private componentId: string = 'PerformanceChart';
  
  private chartWidth: number = 300;
  private chartHeight: number = 120;
  private chartPadding: number = 20;

  aboutToAppear(): void {
    // 初始化主题感知
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState);
    this.updateChartData();
  }

  aboutToDisappear(): void {
    // 清理主题感知
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
  }

  /**
   * 更新图表数据
   */
  private updateChartData(): void {
    try {
      const timestamps = this.performanceHistory.timestamps;
      let dataArray: number[] = [];
      
      // 根据图表类型获取对应的数据
      switch (this.chartConfig.type) {
        case ChartType.MEMORY:
          dataArray = this.performanceHistory.memoryUsage;
          break;
        case ChartType.CPU:
          dataArray = this.performanceHistory.cpuUsage;
          break;
        case ChartType.GC_COUNT:
          dataArray = this.performanceHistory.gcCount;
          break;
        case ChartType.HEAP_SIZE:
          dataArray = this.performanceHistory.heapSize;
          break;
        default:
          logger.warn(CHART_TAG, `未知的图表类型: ${this.chartConfig.type}`);
          return;
      }
      
      // 转换为图表数据点
      this.chartData = dataArray.map((value, index) => {
        // 确保所有数值都是 number 类型，避免 BigInt 混合问题
        const numericValue = typeof value === 'bigint' ? Number(value) : value;
        const timestamp = timestamps[index];
        const numericTimestamp = typeof timestamp === 'bigint' ? Number(timestamp) : timestamp;
        
        const dataPoint: ChartDataPoint = {
          x: index, // 使用索引作为 x 坐标，确保是 number 类型
          y: numericValue, // 确保 y 值是 number 类型
          label: numericTimestamp ? new Date(numericTimestamp).toLocaleTimeString() : ''
        };
        return dataPoint;
      });
      
      // 计算数值范围
      if (this.chartData.length > 0) {
        const values = this.chartData.map(point => {
          // 确保所有值都是 number 类型
          const numericY = typeof point.y === 'bigint' ? Number(point.y) : point.y;
          return typeof numericY === 'number' && !isNaN(numericY) ? numericY : 0;
        });
        
        // 计算最大值和最小值
        let maxVal = values[0];
        let minVal = values[0];
        for (let i = 1; i < values.length; i++) {
          if (values[i] > maxVal) {
            maxVal = values[i];
          }
          if (values[i] < minVal) {
            minVal = values[i];
          }
        }
        
        this.maxValue = maxVal * 1.1; // 增加10%的上边距
        this.minValue = minVal * 0.9; // 减少10%的下边距
        
        // 确保最小值不小于0
        if (this.minValue < 0) {
          this.minValue = 0;
        }
      }
      
    } catch (error) {
      logger.error(CHART_TAG, `更新图表数据失败: ${(error as Error).message}`);
    }
  }

  /**
   * 获取数据点的Y坐标
   */
  private getYPosition(value: number): number {
    // 确保输入值是有效的 number 类型
    const numericValue = typeof value === 'bigint' ? Number(value) : value;
    if (typeof numericValue !== 'number' || isNaN(numericValue)) {
      return this.chartHeight / 2; // 返回中间位置作为默认值
    }
    
    const range = this.maxValue - this.minValue;
    if (range === 0) return this.chartHeight / 2;
    
    const normalizedValue = (numericValue - this.minValue) / range;
    return this.chartHeight - (normalizedValue * (this.chartHeight - this.chartPadding * 2)) - this.chartPadding;
  }

  /**
   * 获取数据点的X坐标
   */
  private getXPosition(index: number): number {
    if (this.chartData.length <= 1) return this.chartPadding;
    
    const normalizedIndex = index / (this.chartData.length - 1);
    return this.chartPadding + normalizedIndex * (this.chartWidth - this.chartPadding * 2);
  }

  /**
   * 生成SVG路径
   */
  private generatePath(): string {
    if (this.chartData.length === 0) return '';
    
    let path = '';
    
    this.chartData.forEach((point, index) => {
      const x = this.getXPosition(index);
      const y = this.getYPosition(point.y);
      
      if (index === 0) {
        path += `M ${x} ${y}`;
      } else {
        path += ` L ${x} ${y}`;
      }
    });
    
    return path;
  }

  /**
   * 获取阈值线的Y坐标
   */
  private getThresholdY(threshold: number): number {
    return this.getYPosition(threshold);
  }

  /**
   * 格式化数值显示
   */
  private formatValue(value: number): string {
    // 添加参数验证
    if (typeof value !== 'number' || isNaN(value)) {
      return '0.0';
    }
    
    if (value >= 1000) {
      return `${(value / 1000).toFixed(1)}K`;
    }
    return value.toFixed(1);
  }

  build() {
    Column({ space: 8 }) {
      // 图表标题和当前值
      Row({ space: 8 }) {
        Text(this.chartConfig.title)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme))
          .layoutWeight(1);
        
        if (this.chartData.length > 0) {
          Text(`${this.formatValue(this.chartData[this.chartData.length - 1].y)} ${this.chartConfig.unit}`)
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.chartConfig.color);
        }
        
        Button(this.isVisible ? '👁️' : '👁️‍🗨️')
          .fontSize(12)
          .width(24)
          .height(24)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_secondary', this.themeState.currentTheme))
          .borderRadius(4)
          .onClick(() => {
            this.isVisible = !this.isVisible;
          });
      }.width('100%');
      
      // 图表容器
      if (this.isVisible) {
        Column() {
          // Shape 图表
          Shape() {
            // 背景
            Rect()
              .width(this.chartWidth)
              .height(this.chartHeight)
              .fill(ThemeAwareHelper.getTestManagementThemedColor('background_darker', this.themeState.currentTheme))
              .stroke(ThemeAwareHelper.getTestManagementThemedColor('border_subtle', this.themeState.currentTheme))
              .strokeWidth(1);
            
            // 警告阈值线
            if (this.chartConfig.warningThreshold !== undefined) {
              Path()
                .commands(`M ${this.chartPadding} ${this.getThresholdY(this.chartConfig.warningThreshold)} L ${this.chartWidth - this.chartPadding} ${this.getThresholdY(this.chartConfig.warningThreshold)}`)
                .stroke(ThemeAwareHelper.getTestManagementThemedColor('button_warning', this.themeState.currentTheme))
                .strokeWidth(1)
                .strokeDashArray([5, 5])
                .fill(Color.Transparent);
            }
            
            // 错误阈值线
            if (this.chartConfig.errorThreshold !== undefined) {
              Path()
                .commands(`M ${this.chartPadding} ${this.getThresholdY(this.chartConfig.errorThreshold)} L ${this.chartWidth - this.chartPadding} ${this.getThresholdY(this.chartConfig.errorThreshold)}`)
                .stroke(ThemeAwareHelper.getTestManagementThemedColor('button_danger', this.themeState.currentTheme))
                .strokeWidth(1)
                .strokeDashArray([5, 5])
                .fill(Color.Transparent);
            }
            
            // 数据线
            if (this.chartData.length > 1) {
              Path()
                .commands(this.generatePath())
                .stroke(this.chartConfig.color)
                .strokeWidth(2)
                .fill(Color.Transparent);
            }
            
            // 数据点
            ForEach(this.chartData, (point: ChartDataPoint, index: number) => {
              Circle()
                .width(4)
                .height(4)
                .fill(this.chartConfig.color)
                .position({ x: this.getXPosition(index) - 2, y: this.getYPosition(point.y) - 2 });
            });
          }
          .width(this.chartWidth)
          .height(this.chartHeight);
          
          // 图表信息
          Row({ space: 8 }) {
            Text(`最大值: ${this.formatValue(this.maxValue)}`)
              .fontSize(10)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_light', this.themeState.currentTheme));
            
            Text(`|`)
              .fontSize(10)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme));
            
            Text(`最小值: ${this.formatValue(this.minValue)}`)
              .fontSize(10)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_light', this.themeState.currentTheme));
            
            Text(`|`)
              .fontSize(10)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme));
            
            Text(`数据点: ${this.chartData.length}`)
              .fontSize(10)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_light', this.themeState.currentTheme));
            
            Text(`|`)
              .fontSize(10)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme));
          }
          .width('100%')
          .justifyContent(FlexAlign.Start);
          
          // 控制按钮
          Row({ space: 8 }) {
            Button('清空')
              .fontSize(10)
              .width(50)
              .height(24)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_warning', this.themeState.currentTheme));
            
            Button('导出')
              .fontSize(10)
              .width(50)
              .height(24)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_danger', this.themeState.currentTheme));
          }
          .width('100%')
          .justifyContent(FlexAlign.End);
        }
        .width('100%')
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_dark', this.themeState.currentTheme))
        .padding(8)
        .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('border_subtle', this.themeState.currentTheme) })
        .borderRadius(8);
      }
    }
    .width('100%')
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_dark', this.themeState.currentTheme))
    .padding({ left: 8, right: 8, top: 8, bottom: 8 })
    .borderRadius(8)
    .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('border_subtle', this.themeState.currentTheme) })
    .onAppear(() => {
      this.updateChartData();
    });
  }
}