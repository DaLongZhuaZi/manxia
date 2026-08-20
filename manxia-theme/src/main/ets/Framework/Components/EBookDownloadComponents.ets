/**
 * 电子书下载通用组件
 * 提供下载源选择、文件格式选择、任务进度显示等通用UI组件
 * 设计原则：声明式配置、事件驱动、易于集成
 */

import { ThemeAwareState, ThemeAwareHelper } from 'manxia_theme/src/main/ets/Framework/Components/ThemeAware';
import { ThemeType } from 'manxia_theme/src/main/ets/Framework/Managers/ThemeManager';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { AppColors } from 'manxia_theme/src/main/ets/Framework/Theme/AppColors';

const TAG = 'EBookDownloadComponents';

// ==================== 数据模型 ====================

/**
 * 下载源信息
 */
export interface DownloadSource {
  /** 唯一标识 */
  id: string;
  /** 显示名称 */
  name: string;
  /** 图标URL（可选） */
  icon?: string;
  /** 是否推荐 */
  recommended?: boolean;
  /** 下载URL或跳转URL */
  url: string;
  /** 附加参数 */
  params?: Record<string, string>;
  /** 是否可用 */
  available?: boolean;
  /** 描述信息 */
  description?: string;
}

/**
 * 文件格式信息
 */
export interface FileFormat {
  /** 格式名称（如 epub, mobi, pdf） */
  format: string;
  /** 显示名称 */
  displayName?: string;
  /** 文件大小 */
  size?: string;
  /** 下载URL */
  url?: string;
  /** 是否可用 */
  available?: boolean;
}

/**
 * 任务步骤状态
 */
export enum StepStatus {
  PENDING = 'pending',
  RUNNING = 'running',
  COMPLETED = 'completed',
  FAILED = 'failed',
  WAITING = 'waiting'
}

/**
 * 任务步骤信息
 */
export interface TaskStepInfo {
  /** 步骤ID */
  id: string;
  /** 步骤名称 */
  name: string;
  /** 步骤状态 */
  status: StepStatus;
  /** 进度（0-100） */
  progress?: number;
  /** 错误信息 */
  error?: string;
  /** 是否需要用户交互 */
  requiresInteraction?: boolean;
  /** 交互提示 */
  interactionPrompt?: string;
}

/**
 * 下载任务状态
 */
export interface DownloadTaskState {
  /** 任务ID */
  taskId: string;
  /** 任务名称 */
  taskName: string;
  /** 总体状态 */
  status: StepStatus;
  /** 当前步骤索引 */
  currentStepIndex: number;
  /** 所有步骤 */
  steps: TaskStepInfo[];
  /** 总体进度（0-100） */
  overallProgress: number;
  /** 错误信息 */
  error?: string;
}

// ==================== 下载源选择器组件 ====================

/**
 * 下载源选择器配置
 */
export interface DownloadSourceSelectorConfig {
  /** 标题 */
  title?: string;
  /** 是否显示图标 */
  showIcon?: boolean;
  /** 是否显示推荐标签 */
  showRecommendedBadge?: boolean;
  /** 是否允许多选 */
  multiSelect?: boolean;
  /** 空状态提示 */
  emptyText?: string;
  /** 加载中提示 */
  loadingText?: string;
}

/**
 * 下载源选择器组件
 * 用于显示多个下载源供用户选择
 * 
 * 使用示例：
 * ```
 * DownloadSourceSelector({
 *   sources: this.downloadSources,
 *   isLoading: this.isLoadingSources,
 *   onSelect: (source) => { this.handleSourceSelect(source); },
 *   config: { title: '选择下载源', showRecommendedBadge: true }
 * })
 * ```
 */
@Component
export struct DownloadSourceSelector {
  /** 下载源列表 */
  @Prop sources: DownloadSource[] = [];
  /** 是否加载中 */
  @Prop isLoading: boolean = false;
  /** 当前选中的源ID */
  @Prop selectedId: string = '';
  /** 选择回调 */
  onSelect: (source: DownloadSource) => void = () => {};
  /** 配置 */
  config: DownloadSourceSelectorConfig = {};
  /** 主题状态 */
  @Consume('themeState') themeState: ThemeAwareState;

  private getConfig(): DownloadSourceSelectorConfig {
    return {
      title: this.config.title || '选择下载源',
      showIcon: this.config.showIcon !== false,
      showRecommendedBadge: this.config.showRecommendedBadge !== false,
      multiSelect: this.config.multiSelect || false,
      emptyText: this.config.emptyText || '暂无可用下载源',
      loadingText: this.config.loadingText || '正在搜索下载源...'
    };
  }

  build() {
    Column({ space: 12 }) {
      // 标题
      Text(this.getConfig().title)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .width('100%')

      if (this.isLoading) {
        // 加载状态
        Column({ space: 8 }) {
          LoadingProgress()
            .width(32)
            .height(32)
            .color(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          Text(this.getConfig().loadingText)
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
        .width('100%')
        .padding(24)
        .justifyContent(FlexAlign.Center)
      } else if (this.sources.length === 0) {
        // 空状态
        Text(this.getConfig().emptyText)
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding(24)
      } else {
        // 源列表
        ForEach(this.sources, (source: DownloadSource) => {
          this.buildSourceItem(source)
        }, (source: DownloadSource) => source.id)
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
  }

  @Builder
  buildSourceItem(source: DownloadSource) {
    Row({ space: 12 }) {
      // 图标
      if (this.getConfig().showIcon && source.icon) {
        Image(source.icon)
          .width(32)
          .height(32)
          .borderRadius(6)
          .objectFit(ImageFit.Cover)
      } else if (this.getConfig().showIcon) {
        // 默认图标
        Text(source.name.charAt(0).toUpperCase())
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
          .width(32)
          .height(32)
          .textAlign(TextAlign.Center)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .borderRadius(6)
      }

      // 名称和描述
      Column({ space: 4 }) {
        Row({ space: 8 }) {
          Text(source.name)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          
          // 推荐标签
          if (this.getConfig().showRecommendedBadge && source.recommended) {
            Text('推荐')
              .fontSize(10)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme))
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .borderRadius(4)
          }
        }

        if (source.description) {
          Text(source.description)
            .fontSize(12)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      // 选中指示器
      if (this.selectedId === source.id) {
        Text('✓')
          .fontSize(16)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.selectedId === source.id 
      ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme) + '20'
      : 'transparent')
    .borderRadius(8)
    .opacity(source.available === false ? 0.5 : 1)
    .onClick(() => {
      if (source.available !== false) {
        this.onSelect(source);
      }
    })
  }
}

// ==================== 文件格式选择器组件 ====================

/**
 * 文件格式选择器配置
 */
export interface FileFormatSelectorConfig {
  /** 标题 */
  title?: string;
  /** 布局方式：grid(网格) 或 list(列表) */
  layout?: 'grid' | 'list';
  /** 每行显示数量（grid模式） */
  columnsPerRow?: number;
  /** 是否显示文件大小 */
  showSize?: boolean;
  /** 空状态提示 */
  emptyText?: string;
}

/**
 * 文件格式选择器组件
 * 用于显示可用的文件格式供用户选择
 * 
 * 使用示例：
 * ```
 * FileFormatSelector({
 *   formats: this.availableFormats,
 *   selectedFormat: this.selectedFormat,
 *   onSelect: (format) => { this.handleFormatSelect(format); },
 *   config: { layout: 'grid', showSize: true }
 * })
 * ```
 */
@Component
export struct FileFormatSelector {
  /** 格式列表 */
  @Prop formats: FileFormat[] = [];
  /** 当前选中的格式 */
  @Prop selectedFormat: string = '';
  /** 选择回调 */
  onSelect: (format: FileFormat) => void = () => {};
  /** 配置 */
  config: FileFormatSelectorConfig = {};
  /** 主题状态 */
  @Consume('themeState') themeState: ThemeAwareState;

  private getConfig(): FileFormatSelectorConfig {
    return {
      title: this.config.title || '选择格式',
      layout: this.config.layout || 'grid',
      columnsPerRow: this.config.columnsPerRow || 4,
      showSize: this.config.showSize !== false,
      emptyText: this.config.emptyText || '暂无可用格式'
    };
  }

  private getFormatDisplayName(format: FileFormat): string {
    return format.displayName || format.format.toUpperCase();
  }

  private getFormatColor(format: string): ResourceColor {
    const colorMap: Record<string, string> = {
      'epub': AppColors.success,
      'mobi': AppColors.warning,
      'pdf': AppColors.error,
      'azw3': AppColors.tertiary,
      'txt': AppColors.secondary
    };
    return colorMap[format.toLowerCase()] || AppColors.info;
  }

  build() {
    Column({ space: 12 }) {
      // 标题
      Text(this.getConfig().title)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .width('100%')

      if (this.formats.length === 0) {
        // 空状态
        Text(this.getConfig().emptyText)
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding(24)
      } else if (this.getConfig().layout === 'grid') {
        // 网格布局
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
          ForEach(this.formats, (format: FileFormat) => {
            this.buildFormatChip(format)
          }, (format: FileFormat) => format.format)
        }
        .width('100%')
      } else {
        // 列表布局
        ForEach(this.formats, (format: FileFormat) => {
          this.buildFormatListItem(format)
        }, (format: FileFormat) => format.format)
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
  }

  @Builder
  buildFormatChip(format: FileFormat) {
    Column({ space: 4 }) {
      Text(this.getFormatDisplayName(format))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.selectedFormat === format.format 
          ? ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme)
          : this.getFormatColor(format.format))
      
      if (this.getConfig().showSize && format.size) {
        Text(format.size)
          .fontSize(10)
          .fontColor(this.selectedFormat === format.format 
            ? ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme) + 'CC'
            : ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      }
    }
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .margin({ right: 8, bottom: 8 })
    .backgroundColor(this.selectedFormat === format.format 
      ? this.getFormatColor(format.format)
      : ThemeAwareHelper.getTestManagementThemedColor('background_dark', this.themeState.currentTheme))
    .borderRadius(8)
    .border({
      width: 1,
      color: this.selectedFormat === format.format 
        ? this.getFormatColor(format.format)
        : ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme)
    })
    .opacity(format.available === false ? 0.5 : 1)
    .onClick(() => {
      if (format.available !== false) {
        this.onSelect(format);
      }
    })
  }

  @Builder
  buildFormatListItem(format: FileFormat) {
    Row({ space: 12 }) {
      // 格式标签
      Text(this.getFormatDisplayName(format))
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
        .width(60)
        .height(32)
        .textAlign(TextAlign.Center)
        .backgroundColor(this.getFormatColor(format.format))
        .borderRadius(6)

      // 文件大小
      if (this.getConfig().showSize && format.size) {
        Text(format.size)
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .layoutWeight(1)
      } else {
        Blank().layoutWeight(1)
      }

      // 选中指示器
      if (this.selectedFormat === format.format) {
        Text('✓')
          .fontSize(16)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.selectedFormat === format.format 
      ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme) + '20'
      : 'transparent')
    .borderRadius(8)
    .opacity(format.available === false ? 0.5 : 1)
    .onClick(() => {
      if (format.available !== false) {
        this.onSelect(format);
      }
    })
  }
}

// ==================== 任务进度面板组件 ====================

/**
 * 任务进度面板配置
 */
export interface TaskProgressPanelConfig {
  /** 是否显示步骤详情 */
  showStepDetails?: boolean;
  /** 是否显示进度百分比 */
  showPercentage?: boolean;
  /** 是否可折叠 */
  collapsible?: boolean;
  /** 默认是否展开 */
  defaultExpanded?: boolean;
}

/**
 * 任务进度面板组件
 * 用于显示多步骤任务的执行进度
 * 
 * 使用示例：
 * ```
 * TaskProgressPanel({
 *   taskState: this.downloadTaskState,
 *   onCancel: () => { this.cancelDownload(); },
 *   onRetry: () => { this.retryDownload(); },
 *   config: { showStepDetails: true }
 * })
 * ```
 */
@Component
export struct TaskProgressPanel {
  /** 任务状态 */
  @Prop taskState: DownloadTaskState | null = null;
  /** 取消回调 */
  onCancel: () => void = () => {};
  /** 重试回调 */
  onRetry: () => void = () => {};
  /** 用户交互回调 */
  onInteraction: (stepId: string) => void = () => {};
  /** 配置 */
  config: TaskProgressPanelConfig = {};
  /** 主题状态 */
  @Consume('themeState') themeState: ThemeAwareState;
  /** 是否展开 */
  @State isExpanded: boolean = true;

  aboutToAppear(): void {
    this.isExpanded = this.config.defaultExpanded !== false;
  }

  private getConfig(): TaskProgressPanelConfig {
    return {
      showStepDetails: this.config.showStepDetails !== false,
      showPercentage: this.config.showPercentage !== false,
      collapsible: this.config.collapsible || false,
      defaultExpanded: this.config.defaultExpanded !== false
    };
  }

  private getStatusColor(status: StepStatus): ResourceColor {
    switch (status) {
      case StepStatus.COMPLETED:
        return AppColors.success;
      case StepStatus.RUNNING:
        return AppColors.info;
      case StepStatus.FAILED:
        return AppColors.error;
      case StepStatus.WAITING:
        return AppColors.warning;
      default:
        return AppColors.textTertiary;
    }
  }

  private getStatusIcon(status: StepStatus): string {
    switch (status) {
      case StepStatus.COMPLETED:
        return '✓';
      case StepStatus.RUNNING:
        return '●';
      case StepStatus.FAILED:
        return '✗';
      case StepStatus.WAITING:
        return '⏸';
      default:
        return '○';
    }
  }

  build() {
    if (!this.taskState) {
      Column()
    } else {
      Column({ space: 12 }) {
        // 标题栏
        Row({ space: 8 }) {
          Text(this.taskState.taskName)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .layoutWeight(1)

          if (this.getConfig().showPercentage) {
            Text(`${this.taskState.overallProgress}%`)
              .fontSize(14)
              .fontColor(this.getStatusColor(this.taskState.status))
          }

          if (this.getConfig().collapsible) {
            Text(this.isExpanded ? '▲' : '▼')
              .fontSize(12)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              .onClick(() => {
                this.isExpanded = !this.isExpanded;
              })
          }
        }
        .width('100%')

        // 总体进度条
        Progress({ value: this.taskState.overallProgress, total: 100, type: ProgressType.Linear })
          .width('100%')
          .height(6)
          .color(this.getStatusColor(this.taskState.status))
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_dark', this.themeState.currentTheme))
          .borderRadius(3)

        // 步骤详情
        if (this.getConfig().showStepDetails && this.isExpanded) {
          Column({ space: 8 }) {
            ForEach(this.taskState.steps, (step: TaskStepInfo, index: number) => {
              this.buildStepItem(step, index)
            }, (step: TaskStepInfo) => step.id)
          }
          .width('100%')
        }

        // 错误信息
        if (this.taskState.error) {
          Text(this.taskState.error)
            .fontSize(12)
            .fontColor(AppColors.error)
            .width('100%')
            .padding(8)
            .backgroundColor(AppColors.errorContainer)
            .borderRadius(6)
        }

        // 操作按钮
        if (this.taskState.status === StepStatus.FAILED) {
          Row({ space: 12 }) {
            Button('重试')
              .fontSize(14)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
              .height(36)
              .layoutWeight(1)
              .onClick(() => this.onRetry())

            Button('取消')
              .fontSize(14)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_dark', this.themeState.currentTheme))
              .height(36)
              .layoutWeight(1)
              .onClick(() => this.onCancel())
          }
          .width('100%')
        } else if (this.taskState.status === StepStatus.RUNNING) {
          Button('取消')
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_dark', this.themeState.currentTheme))
            .height(36)
            .width('100%')
            .onClick(() => this.onCancel())
        }
      }
      .width('100%')
      .padding(16)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
      .borderRadius(12)
    }
  }

  @Builder
  buildStepItem(step: TaskStepInfo, index: number) {
    Row({ space: 12 }) {
      // 状态图标
      Text(this.getStatusIcon(step.status))
        .fontSize(14)
        .fontColor(this.getStatusColor(step.status))
        .width(20)
        .textAlign(TextAlign.Center)

      // 步骤名称
      Column({ space: 2 }) {
        Text(step.name)
          .fontSize(14)
          .fontColor(step.status === StepStatus.PENDING 
            ? ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)
            : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

        // 交互提示
        if (step.status === StepStatus.WAITING && step.interactionPrompt) {
          Text(step.interactionPrompt)
            .fontSize(12)
            .fontColor(AppColors.warning)
        }

        // 错误信息
        if (step.status === StepStatus.FAILED && step.error) {
          Text(step.error)
            .fontSize(12)
            .fontColor(AppColors.error)
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      // 交互按钮
      if (step.status === StepStatus.WAITING && step.requiresInteraction) {
        Button('继续')
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
          .backgroundColor(AppColors.warning)
          .height(28)
          .onClick(() => this.onInteraction(step.id))
      }

      // 运行中指示器
      if (step.status === StepStatus.RUNNING) {
        LoadingProgress()
          .width(20)
          .height(20)
          .color(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
      }
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 6, bottom: 6 })
  }
}

// ==================== 下载按钮组件 ====================

/**
 * 下载按钮状态
 */
export enum DownloadButtonState {
  IDLE = 'idle',
  LOADING = 'loading',
  DOWNLOADING = 'downloading',
  COMPLETED = 'completed',
  FAILED = 'failed'
}

/**
 * 下载按钮配置
 */
export interface DownloadButtonConfig {
  /** 空闲状态文本 */
  idleText?: string;
  /** 加载中文本 */
  loadingText?: string;
  /** 下载中文本 */
  downloadingText?: string;
  /** 完成文本 */
  completedText?: string;
  /** 失败文本 */
  failedText?: string;
  /** 是否显示进度 */
  showProgress?: boolean;
}

/**
 * 下载按钮组件
 * 带状态的下载按钮，支持进度显示
 * 
 * 使用示例：
 * ```
 * DownloadButton({
 *   state: this.downloadState,
 *   progress: this.downloadProgress,
 *   onClick: () => { this.startDownload(); },
 *   config: { idleText: '下载电子书' }
 * })
 * ```
 */
@Component
export struct DownloadButton {
  /** 按钮状态 */
  @Prop state: DownloadButtonState = DownloadButtonState.IDLE;
  /** 下载进度（0-100） */
  @Prop progress: number = 0;
  /** 点击回调 */
  onButtonClick: () => void = () => {};
  /** 配置 */
  config: DownloadButtonConfig = {};
  /** 主题状态 */
  @Consume('themeState') themeState: ThemeAwareState;

  private getConfig(): DownloadButtonConfig {
    return {
      idleText: this.config.idleText || '下载',
      loadingText: this.config.loadingText || '准备中...',
      downloadingText: this.config.downloadingText || '下载中',
      completedText: this.config.completedText || '已完成',
      failedText: this.config.failedText || '下载失败',
      showProgress: this.config.showProgress !== false
    };
  }

  private getButtonText(): string {
    const cfg = this.getConfig();
    switch (this.state) {
      case DownloadButtonState.LOADING:
        return cfg.loadingText || '';
      case DownloadButtonState.DOWNLOADING:
        return cfg.showProgress ? `${cfg.downloadingText} ${this.progress}%` : (cfg.downloadingText || '');
      case DownloadButtonState.COMPLETED:
        return cfg.completedText || '';
      case DownloadButtonState.FAILED:
        return cfg.failedText || '';
      default:
        return cfg.idleText || '';
    }
  }

  private getButtonColor(): ResourceColor {
    switch (this.state) {
      case DownloadButtonState.COMPLETED:
        return AppColors.success;
      case DownloadButtonState.FAILED:
        return AppColors.error;
      default:
        return AppColors.primary;
    }
  }

  private isDisabled(): boolean {
    return this.state === DownloadButtonState.LOADING || 
           this.state === DownloadButtonState.DOWNLOADING;
  }

  build() {
    Stack() {
      // 进度背景
      if (this.state === DownloadButtonState.DOWNLOADING && this.getConfig().showProgress) {
        Row()
          .width(`${this.progress}%`)
          .height('100%')
          .backgroundColor(this.getButtonColor() + '40')
          .borderRadius(8)
      }

      // 按钮内容
      Row({ space: 8 }) {
        if (this.state === DownloadButtonState.LOADING || this.state === DownloadButtonState.DOWNLOADING) {
          LoadingProgress()
            .width(20)
            .height(20)
            .color(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
        }

        Text(this.getButtonText())
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
      }
      .justifyContent(FlexAlign.Center)
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height(48)
    .backgroundColor(this.getButtonColor())
    .borderRadius(8)
    .opacity(this.isDisabled() ? 0.7 : 1)
    .onClick(() => {
      if (!this.isDisabled()) {
        this.onButtonClick();
      }
    })
  }
}

// ==================== 工具函数 ====================

/**
 * 创建默认的下载任务状态
 */
export function createDefaultTaskState(taskId: string, taskName: string, stepNames: string[]): DownloadTaskState {
  const steps: TaskStepInfo[] = [];
  for (let i = 0; i < stepNames.length; i++) {
    const step: TaskStepInfo = {
      id: `step_${i}`,
      name: stepNames[i],
      status: StepStatus.PENDING
    };
    steps.push(step);
  }
  const state: DownloadTaskState = {
    taskId: taskId,
    taskName: taskName,
    status: StepStatus.PENDING,
    currentStepIndex: 0,
    steps: steps,
    overallProgress: 0
  };
  return state;
}

/**
 * 更新任务步骤状态
 */
export function updateStepStatus(
  state: DownloadTaskState, 
  stepIndex: number, 
  status: StepStatus, 
  error?: string
): DownloadTaskState {
  // 复制步骤数组
  const newSteps: TaskStepInfo[] = [];
  for (let i = 0; i < state.steps.length; i++) {
    if (i === stepIndex) {
      const updatedStep: TaskStepInfo = {
        id: state.steps[i].id,
        name: state.steps[i].name,
        status: status,
        progress: state.steps[i].progress,
        error: error,
        requiresInteraction: state.steps[i].requiresInteraction,
        interactionPrompt: state.steps[i].interactionPrompt
      };
      newSteps.push(updatedStep);
    } else {
      newSteps.push(state.steps[i]);
    }
  }

  // 计算总体进度
  let completedCount = 0;
  for (let i = 0; i < newSteps.length; i++) {
    if (newSteps[i].status === StepStatus.COMPLETED) {
      completedCount++;
    }
  }
  const overallProgress = Math.round((completedCount / newSteps.length) * 100);

  // 确定总体状态
  let overallStatus = StepStatus.PENDING;
  let hasFailed = false;
  let hasRunning = false;
  let hasWaiting = false;
  let allCompleted = true;
  for (let i = 0; i < newSteps.length; i++) {
    if (newSteps[i].status === StepStatus.FAILED) hasFailed = true;
    if (newSteps[i].status === StepStatus.RUNNING) hasRunning = true;
    if (newSteps[i].status === StepStatus.WAITING) hasWaiting = true;
    if (newSteps[i].status !== StepStatus.COMPLETED) allCompleted = false;
  }
  
  if (hasFailed) {
    overallStatus = StepStatus.FAILED;
  } else if (hasRunning) {
    overallStatus = StepStatus.RUNNING;
  } else if (hasWaiting) {
    overallStatus = StepStatus.WAITING;
  } else if (allCompleted) {
    overallStatus = StepStatus.COMPLETED;
  }

  const newState: DownloadTaskState = {
    taskId: state.taskId,
    taskName: state.taskName,
    status: overallStatus,
    currentStepIndex: stepIndex,
    steps: newSteps,
    overallProgress: overallProgress,
    error: error
  };
  return newState;
}
