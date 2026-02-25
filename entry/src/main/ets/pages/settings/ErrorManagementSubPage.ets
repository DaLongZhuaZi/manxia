// 文件路径: entry/src/main/ets/pages/settings/ErrorManagementSubPage.ets
/**
 * 错误管理子页面
 * 展示所有捕获的错误信息（运行时错误 + 闪退记录），
 * 提供基础分析和手动导出功能（单条/多条合并导出）。
 */

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';
import { picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { ThemeAwareState, ThemeAwareHelper } from '../../Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from '../../Framework/Managers/ThemeManager';
import { FontAwareHelper, FontAwareState } from '../../Framework/Components/FontAware';
import { logger } from '../../Utils/Logger';
import { PageLifecycleManager } from '../../Framework/Lifecycle';
import { DeviceAdaptationManager, DeviceInfo, DeviceChangeListener, Breakpoint } from '../../Framework/Managers/DeviceAdaptationManager';
import { ResponsiveLayoutHelper } from '../../Framework/Utils/ResponsiveLayout';
import { ErrorRecordManager, ErrorRecord, ErrorSource, ErrorSummary, TagCount } from '../../Framework/Debug/ErrorRecordManager';

const TAG = 'ErrorManagementSubPage';
const TITLE_BAR_HEIGHT_MINI: number = 56;

/** 过滤类型 */
type FilterType = 'all' | 'runtime' | 'crash' | 'network';

@Component
export struct ErrorManagementSubPage {
  @State pathStack: NavPathStack = new NavPathStack();
  private scroller: Scroller = new Scroller();
  private uiContext: UIContext | undefined = undefined;

  // 主题
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private componentId: string = 'ErrorManagementSubPage';

  // 响应式
  private deviceManager: DeviceAdaptationManager = DeviceAdaptationManager.getInstance();
  private deviceChangeListener: DeviceChangeListener | null = null;
  @State responsive_contentPadding: number = 16;
  @State responsive_maxContentWidth: number = 1200;
  @State responsive_isLandscape: boolean = false;

  // 数据
  private errorRecordManager: ErrorRecordManager = ErrorRecordManager.getInstance();
  @State allRecords: ErrorRecord[] = [];
  @State filteredRecords: ErrorRecord[] = [];
  @State summary: ErrorSummary = { total: 0, runtimeErrors: 0, crashes: 0, networkErrors: 0, topTags: [], firstTime: 0, lastTime: 0 };
  @State filterType: FilterType = 'all';
  @State searchText: string = '';

  // 多选
  @State isSelectMode: boolean = false;
  @State selectedIds: string[] = [];

  // 导出状态
  @State isExporting: boolean = false;

  // 详情展开
  @State expandedId: string = '';

  onPageShow(): void {
    try {
      const stack = AppStorage.get<NavPathStack>('GlobalNavStack');
      if (stack) {
        this.pathStack = stack;
      }
    } catch (err) {
      logger.error(TAG, 'AppStorage.get 异常', String(err));
    }
  }

  onReady(): void {
    this.uiContext = this.getUIContext();
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (_: ThemeType) => {});
    FontAwareHelper.initializeFontAware(this.componentId, this.fontState, (s: FontAwareState) => { this.fontState = s; });
    this.initializeResponsiveLayout();
    this.loadData();
  }

  private lifecycle = new PageLifecycleManager('ErrorManagementSubPage', { enableDebug: true });

  aboutToDisappear(): void {
    this.lifecycle.destroy();
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    FontAwareHelper.cleanupFontAware(this.componentId);
    if (this.deviceChangeListener) {
      this.deviceManager.removeListener(this.deviceChangeListener);
      this.deviceChangeListener = null;
    }
  }

  private initializeResponsiveLayout(): void {
    try {
      this.updateResponsiveParams();
      this.deviceChangeListener = (_: DeviceInfo) => { this.updateResponsiveParams(); };
      this.deviceManager.addListener(this.deviceChangeListener);
    } catch (error) {
      logger.error(TAG, '响应式布局初始化失败', String(error));
    }
  }

  private updateResponsiveParams(): void {
    const layoutParams = ResponsiveLayoutHelper.getLayoutParams();
    const dInfo = this.deviceManager.getDeviceInfo();
    this.responsive_contentPadding = layoutParams.contentPadding;
    this.responsive_isLandscape = dInfo.isLandscape;
    switch (dInfo.breakpoint) {
      case Breakpoint.XS: this.responsive_maxContentWidth = 600; break;
      case Breakpoint.SM: this.responsive_maxContentWidth = 840; break;
      case Breakpoint.MD: this.responsive_maxContentWidth = 1024; break;
      case Breakpoint.LG: this.responsive_maxContentWidth = 1200; break;
    }
  }

  // ─── 数据 ───

  private loadData(): void {
    this.allRecords = this.errorRecordManager.getAllRecords();
    this.summary = this.errorRecordManager.getSummary();
    this.applyFilter();
  }

  private applyFilter(): void {
    let records = this.allRecords;
    if (this.filterType === 'runtime') {
      records = records.filter((r: ErrorRecord) => r.source === ErrorSource.RUNTIME_ERROR);
    } else if (this.filterType === 'crash') {
      records = records.filter((r: ErrorRecord) => r.source === ErrorSource.CRASH);
    } else if (this.filterType === 'network') {
      records = records.filter((r: ErrorRecord) => r.source === ErrorSource.NETWORK_ERROR);
    }
    if (this.searchText.length > 0) {
      const kw = this.searchText.toLowerCase();
      records = records.filter((r: ErrorRecord) =>
        r.message.toLowerCase().includes(kw) ||
        r.tag.toLowerCase().includes(kw) ||
        r.timeStr.includes(kw)
      );
    }
    this.filteredRecords = records;
  }

  private toggleSelect(id: string): void {
    const idx = this.selectedIds.indexOf(id);
    if (idx >= 0) {
      this.selectedIds = this.selectedIds.filter((s: string) => s !== id);
    } else {
      this.selectedIds = [...this.selectedIds, id];
    }
  }

  private selectAll(): void {
    this.selectedIds = this.filteredRecords.map((r: ErrorRecord) => r.id);
  }

  private clearSelection(): void {
    this.selectedIds = [];
    this.isSelectMode = false;
  }

  private deleteSelected(): void {
    for (let i = 0; i < this.selectedIds.length; i++) {
      this.errorRecordManager.deleteRecord(this.selectedIds[i]);
    }
    this.selectedIds = [];
    this.isSelectMode = false;
    this.loadData();
  }

  private clearAll(): void {
    this.errorRecordManager.clearAll();
    this.loadData();
  }

  // ─── 导出 ───

  private async exportSingle(record: ErrorRecord): Promise<void> {
    this.isExporting = true;
    try {
      const content = this.errorRecordManager.exportSingleRecord(record);
      const safeTime = record.timeStr.replace(/[:/]/g, '-').replace(/\s/g, '_').replace(/\./g, '-');
      const fileName = `error_detail_${safeTime}.txt`;
      await this.saveToFile(content, fileName);
    } catch (error) {
      logger.error(TAG, `导出单条错误失败: ${String(error)}`);
    } finally {
      this.isExporting = false;
    }
  }

  private async exportSelected(): Promise<void> {
    if (this.selectedIds.length === 0) {
      return;
    }
    this.isExporting = true;
    try {
      const records = this.filteredRecords.filter((r: ErrorRecord) => this.selectedIds.indexOf(r.id) >= 0);
      const content = this.errorRecordManager.exportMultipleRecords(records);
      const fileName = `error_report_${records.length}items_${Date.now()}.txt`;
      await this.saveToFile(content, fileName);
    } catch (error) {
      logger.error(TAG, `导出多条错误失败: ${String(error)}`);
    } finally {
      this.isExporting = false;
    }
  }

  private async exportAll(): Promise<void> {
    if (this.filteredRecords.length === 0) {
      return;
    }
    this.isExporting = true;
    try {
      const content = this.errorRecordManager.exportMultipleRecords(this.filteredRecords);
      const fileName = `error_report_all_${Date.now()}.txt`;
      await this.saveToFile(content, fileName);
    } catch (error) {
      logger.error(TAG, `导出全部错误失败: ${String(error)}`);
    } finally {
      this.isExporting = false;
    }
  }

  private async saveToFile(content: string, fileName: string): Promise<void> {
    const context = this.uiContext?.getHostContext() as common.UIAbilityContext;
    if (!context) {
      throw new Error('无法获取应用上下文');
    }
    const tempPath = `${context.cacheDir}/${fileName}`;
    const tmpFile = fs.openSync(tempPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
    fs.writeSync(tmpFile.fd, content);
    fs.closeSync(tmpFile);

    const documentPicker = new picker.DocumentViewPicker(context);
    const opts = new picker.DocumentSaveOptions();
    opts.newFileNames = [fileName];
    const result = await documentPicker.save(opts);
    if (result && result.length > 0) {
      const targetUri = result[0];
      const src = fs.openSync(tempPath, fs.OpenMode.READ_ONLY);
      const dst = fs.openSync(targetUri, fs.OpenMode.WRITE_ONLY);
      const buf = new ArrayBuffer(4096);
      let readLen = 0;
      while ((readLen = fs.readSync(src.fd, buf)) > 0) {
        fs.writeSync(dst.fd, buf, { length: readLen });
      }
      fs.closeSync(src);
      fs.closeSync(dst);
      logger.info(TAG, `错误报告已导出: ${targetUri}`);
    }
    fs.unlinkSync(tempPath);
  }

  // ─── 工具 ───

  private formatShortTime(ts: number): string {
    if (ts === 0) return '-';
    const d = new Date(ts);
    const M = (d.getMonth() + 1).toString().padStart(2, '0');
    const D = d.getDate().toString().padStart(2, '0');
    const h = d.getHours().toString().padStart(2, '0');
    const m = d.getMinutes().toString().padStart(2, '0');
    return `${M}-${D} ${h}:${m}`;
  }

  private getSourceLabel(source: ErrorSource): string {
    if (source === ErrorSource.CRASH) return '闪退';
    if (source === ErrorSource.NETWORK_ERROR) return '网络';
    return '运行时';
  }

  private getSourceColor(source: ErrorSource): ResourceColor {
    if (source === ErrorSource.CRASH) {
      return ThemeAwareHelper.getTestManagementThemedColor('button_danger', this.themeState.currentTheme);
    }
    if (source === ErrorSource.NETWORK_ERROR) {
      return ThemeAwareHelper.getTestManagementThemedColor('button_purple', this.themeState.currentTheme);
    }
    return ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme);
  }

  private themeColor(key: 'background' | 'text_primary' | 'text_secondary' | 'button_background' |
    'panel_background' | 'panel_border' | 'accent_primary' | 'accent_primary_dimmed' |
    'button_primary' | 'button_secondary' | 'button_inactive' | 'divider' | 'text_white' |
    'text_black' | 'text_muted' | 'accent_green' | 'button_danger' | 'brand' |
    'button_success' | 'button_warning' | 'button_purple' | 'button_info' | 'border_light' |
    'border_active' | 'text_placeholder' | 'background_darker' | 'panel_dark' |
    'border_subtle' | 'row_even' | 'row_odd' | 'text_light' | 'background_secondary' |
    'background_dark' | 'background_overlay' | 'comp_background_tertiary' |
    'icon_primary' | 'font_secondary' | 'text_dim' | 'accent_blue' | 'accent_orange' |
    'accent_secondary' | 'color_error' | 'color_success' | 'color_warning' |
    'color_info' | 'color_neutral' | 'text_inverse' | 'background_inverse' |
    'brand_secondary' | 'brand_tertiary' | 'background_primary' | 'shadow_black' |
    'border_dark' | 'brand_blue' | 'button_text_primary' | 'button_text_secondary' |
    'comp_background_primary' | 'comp_background_secondary' | 'success_border' | 'error_border' |
    'comp_border_primary' | 'success_text' | 'error_text' |
    'manga_detail_gradient_start' | 'manga_detail_gradient_mid' | 'manga_detail_gradient_end' |
    'comp_divider' | 'text_tertiary'): ResourceColor {
    return ThemeAwareHelper.getTestManagementThemedColor(key, this.themeState.currentTheme);
  }

  // ─── UI Builders ───

  @Builder
  buildSummaryCard() {
    Column({ space: 10 }) {
      Text('错误统计')
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontFamily(this.appFontFamily)
        .fontColor(this.themeColor('text_primary'))

      Row({ space: 8 }) {
        this.buildStatBadge(`${this.summary.total}`, '总计', 'accent_blue')
        this.buildStatBadge(`${this.summary.runtimeErrors}`, '运行时', 'accent_orange')
        this.buildStatBadge(`${this.summary.networkErrors}`, '网络', 'button_purple')
        this.buildStatBadge(`${this.summary.crashes}`, '闪退', 'button_danger')
      }
      .width('100%')

      if (this.summary.total > 0) {
        Row() {
          Text(`时间跨度: ${this.formatShortTime(this.summary.firstTime)} ~ ${this.formatShortTime(this.summary.lastTime)}`)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(this.themeColor('text_muted'))
        }
        .width('100%')

        if (this.summary.topTags.length > 0) {
          Column({ space: 4 }) {
            Text('高频模块')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontFamily(this.appFontFamily)
              .fontColor(this.themeColor('text_secondary'))
            ForEach(this.summary.topTags.slice(0, 5), (tc: TagCount) => {
              Row({ space: 6 }) {
                Text(tc.tag)
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor(this.themeColor('accent_blue'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                Text(`${tc.count} 次`)
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor(this.themeColor('text_muted'))
              }
              .width('100%')
            }, (tc: TagCount) => tc.tag)
          }
          .width('100%')
          .padding({ top: 4 })
        }
      }
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.themeColor('panel_background'))
    .borderRadius(12)
    .border({ width: 1, color: this.themeColor('panel_border') })
  }

  @Builder
  buildStatBadge(value: string, label: string, colorKey: 'background' | 'text_primary' | 'text_secondary' | 'button_background' |
    'panel_background' | 'panel_border' | 'accent_primary' | 'accent_primary_dimmed' |
    'button_primary' | 'button_secondary' | 'button_inactive' | 'divider' | 'text_white' |
    'text_black' | 'text_muted' | 'accent_green' | 'button_danger' | 'brand' |
    'button_success' | 'button_warning' | 'button_purple' | 'button_info' | 'border_light' |
    'border_active' | 'text_placeholder' | 'background_darker' | 'panel_dark' |
    'border_subtle' | 'row_even' | 'row_odd' | 'text_light' | 'background_secondary' |
    'background_dark' | 'background_overlay' | 'comp_background_tertiary' |
    'icon_primary' | 'font_secondary' | 'text_dim' | 'accent_blue' | 'accent_orange' |
    'accent_secondary' | 'color_error' | 'color_success' | 'color_warning' |
    'color_info' | 'color_neutral' | 'text_inverse' | 'background_inverse' |
    'brand_secondary' | 'brand_tertiary' | 'background_primary' | 'shadow_black' |
    'border_dark' | 'brand_blue' | 'button_text_primary' | 'button_text_secondary' |
    'comp_background_primary' | 'comp_background_secondary' | 'success_border' | 'error_border' |
    'comp_border_primary' | 'success_text' | 'error_text' |
    'manga_detail_gradient_start' | 'manga_detail_gradient_mid' | 'manga_detail_gradient_end' |
    'comp_divider' | 'text_tertiary') {
    Column() {
      Text(value)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontFamily(this.appFontFamily)
        .fontColor(this.themeColor(colorKey))
      Text(label)
        .fontSize(11)
        .fontFamily(this.appFontFamily)
        .fontColor(this.themeColor('text_muted'))
    }
    .layoutWeight(1)
    .padding(10)
    .backgroundColor(this.themeColor('panel_background'))
    .borderRadius(8)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  buildFilterBar() {
    Column({ space: 10 }) {
      // 搜索框
      TextInput({ placeholder: '搜索错误信息...', text: this.searchText })
        .width('100%')
        .height(38)
        .backgroundColor(this.themeColor('panel_background'))
        .borderRadius(8)
        .onChange((v: string) => { this.searchText = v; this.applyFilter(); })

      // 过滤按钮行
      Row({ space: 8 }) {
        this.buildFilterBtn('全部', 'all')
        this.buildFilterBtn('运行时', 'runtime')
        this.buildFilterBtn('网络', 'network')
        this.buildFilterBtn('闪退', 'crash')

        Blank()

        // 多选模式开关
        Button({ stateEffect: true }) {
          Text(this.isSelectMode ? '取消' : '选择')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(this.themeColor('button_text_secondary'))
        }
        .height(28)
        .padding({ left: 10, right: 10 })
        .backgroundColor(this.themeColor('accent_blue'))
        .borderRadius(6)
        .onClick(() => {
          this.isSelectMode = !this.isSelectMode;
          if (!this.isSelectMode) {
            this.selectedIds = [];
          }
        })
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  buildFilterBtn(label: string, type: FilterType) {
    Button({ stateEffect: true }) {
      Text(label)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(this.themeColor('button_text_secondary'))
    }
    .height(28)
    .padding({ left: 10, right: 10 })
    .backgroundColor(
      this.filterType === type
        ? this.themeColor('accent_blue')
        : this.themeColor('button_inactive')
    )
    .borderRadius(6)
    .onClick(() => { this.filterType = type; this.applyFilter(); })
  }

  @Builder
  buildActionButtons() {
    Row({ space: 8 }) {
      if (this.isSelectMode && this.selectedIds.length > 0) {
        Button({ stateEffect: true }) {
          Text(`导出(${this.selectedIds.length})`)
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontColor(this.themeColor('button_text_secondary'))
        }
        .layoutWeight(1)
        .height(34)
        .backgroundColor(this.themeColor('accent_green'))
        .borderRadius(8)
        .onClick(() => { this.exportSelected(); })

        Button({ stateEffect: true }) {
          Text('全选')
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontColor(this.themeColor('button_text_secondary'))
        }
        .layoutWeight(1)
        .height(34)
        .backgroundColor(this.themeColor('accent_blue'))
        .borderRadius(8)
        .onClick(() => { this.selectAll(); })

        Button({ stateEffect: true }) {
          Text('删除')
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontColor(this.themeColor('button_text_secondary'))
        }
        .layoutWeight(1)
        .height(34)
        .backgroundColor(this.themeColor('button_danger'))
        .borderRadius(8)
        .onClick(() => { this.deleteSelected(); })
      } else {
        Button({ stateEffect: true }) {
          Text('刷新')
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontColor(this.themeColor('button_text_secondary'))
        }
        .layoutWeight(1)
        .height(34)
        .backgroundColor(this.themeColor('accent_blue'))
        .borderRadius(8)
        .onClick(() => { this.loadData(); })

        Button({ stateEffect: true }) {
          Text(this.isExporting ? '导出中...' : '导出全部')
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontColor(this.themeColor('button_text_secondary'))
        }
        .layoutWeight(1)
        .height(34)
        .backgroundColor(this.themeColor('accent_green'))
        .borderRadius(8)
        .enabled(!this.isExporting && this.filteredRecords.length > 0)
        .onClick(() => { this.exportAll(); })

        Button({ stateEffect: true }) {
          Text('清空')
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontColor(this.themeColor('button_text_secondary'))
        }
        .layoutWeight(1)
        .height(34)
        .backgroundColor(this.themeColor('button_danger'))
        .borderRadius(8)
        .enabled(this.allRecords.length > 0)
        .onClick(() => { this.clearAll(); })
      }
    }
    .width('100%')
  }

  @Builder
  buildErrorItem(record: ErrorRecord) {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        // 多选复选框
        if (this.isSelectMode) {
          Checkbox()
            .select(this.selectedIds.indexOf(record.id) >= 0)
            .selectedColor(this.themeColor('accent_blue') as ResourceColor)
            .onChange((checked: boolean) => {
              if (checked) {
                if (this.selectedIds.indexOf(record.id) < 0) {
                  this.selectedIds = [...this.selectedIds, record.id];
                }
              } else {
                this.selectedIds = this.selectedIds.filter((s: string) => s !== record.id);
              }
            })
            .width(18)
            .height(18)
        }

        // 来源标签
        Text(this.getSourceLabel(record.source))
          .fontSize(10)
          .fontFamily(this.appFontFamily)
          .fontColor(Color.White)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .backgroundColor(this.getSourceColor(record.source))
          .borderRadius(4)

        // 级别
        Text(record.level)
          .fontSize(10)
          .fontFamily(this.appFontFamily)
          .fontColor(this.themeColor('text_muted'))

        // 模块
        Text(record.tag)
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor(this.themeColor('accent_blue'))
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        // 时间
        Text(this.formatShortTime(record.timestamp))
          .fontSize(10)
          .fontFamily(this.appFontFamily)
          .fontColor(this.themeColor('text_muted'))
      }
      .width('100%')

      // 错误消息
      Text(record.message)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(this.themeColor('text_primary'))
        .maxLines(this.expandedId === record.id ? 20 : 2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      // 展开详情
      if (this.expandedId === record.id) {
        Column({ space: 4 }) {
          if (record.stackTrace) {
            Text('堆栈信息:')
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontFamily(this.appFontFamily)
              .fontColor(this.themeColor('text_secondary'))
            Text(record.stackTrace)
              .fontSize(10)
              .fontFamily(this.appFontFamily)
              .fontColor(this.themeColor('text_muted'))
              .maxLines(15)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
          Row({ space: 6 }) {
            Text(`设备: ${record.deviceModel}`)
              .fontSize(10)
              .fontFamily(this.appFontFamily)
              .fontColor(this.themeColor('text_muted'))
            Text(`系统: ${record.osVersion}`)
              .fontSize(10)
              .fontFamily(this.appFontFamily)
              .fontColor(this.themeColor('text_muted'))
          }
          .width('100%')

          if (record.logFileName) {
            Text(`日志文件: ${record.logFileName}`)
              .fontSize(10)
              .fontFamily(this.appFontFamily)
              .fontColor(this.themeColor('text_muted'))
              .width('100%')
          }

          // 单条导出按钮
          Row({ space: 8 }) {
            Button({ stateEffect: true }) {
              Text('导出此条')
                .fontSize(11)
                .fontFamily(this.appFontFamily)
                .fontColor(this.themeColor('button_text_secondary'))
            }
            .height(26)
            .padding({ left: 10, right: 10 })
            .backgroundColor(this.themeColor('accent_green'))
            .borderRadius(6)
            .onClick(() => { this.exportSingle(record); })

            Button({ stateEffect: true }) {
              Text('删除')
                .fontSize(11)
                .fontFamily(this.appFontFamily)
                .fontColor(this.themeColor('button_text_secondary'))
            }
            .height(26)
            .padding({ left: 10, right: 10 })
            .backgroundColor(this.themeColor('button_danger'))
            .borderRadius(6)
            .onClick(() => {
              this.errorRecordManager.deleteRecord(record.id);
              this.expandedId = '';
              this.loadData();
            })
          }
          .width('100%')
          .margin({ top: 4 })
        }
        .width('100%')
        .padding({ top: 4 })
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.themeColor('panel_background'))
    .borderRadius(10)
    .border({ width: 1, color: this.themeColor('panel_border') })
    .onClick(() => {
      if (!this.isSelectMode) {
        this.expandedId = this.expandedId === record.id ? '' : record.id;
      } else {
        this.toggleSelect(record.id);
      }
    })
  }

  @Builder
  buildEmptyState() {
    Column({ space: 16 }) {
      SymbolGlyph($r('sys.symbol.checkmark_shield'))
        .fontSize(48)
        .fontColor([this.themeColor('accent_green')])
      Text('暂无错误记录')
        .fontSize(16)
        .fontFamily(this.appFontFamily)
        .fontColor(this.themeColor('text_muted'))
      Text('应用运行正常，未捕获到程序性错误')
        .fontSize(13)
        .fontFamily(this.appFontFamily)
        .fontColor(this.themeColor('text_tertiary'))
    }
    .width('100%')
    .padding({ top: 60, bottom: 60 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    HdsNavDestination() {
      Stack() {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(this.themeColor('background_dark'))
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        Scroll(this.scroller) {
          Column({ space: 12 }) {
            Blank().height(TITLE_BAR_HEIGHT_MINI)

            // 统计卡片
            this.buildSummaryCard()

            // 过滤栏
            this.buildFilterBar()

            // 操作按钮
            this.buildActionButtons()

            // 错误列表
            if (this.filteredRecords.length === 0) {
              this.buildEmptyState()
            } else {
              Column({ space: 8 }) {
                Text(`共 ${this.filteredRecords.length} 条`)
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor(this.themeColor('text_muted'))
                  .width('100%')

                ForEach(this.filteredRecords, (record: ErrorRecord) => {
                  this.buildErrorItem(record)
                }, (record: ErrorRecord) => record.id)
              }
              .width('100%')
            }

            Blank().height(40)
          }
          .width('100%')
          .constraintSize({ maxWidth: this.responsive_maxContentWidth })
          .padding({ left: this.responsive_contentPadding, right: this.responsive_contentPadding, bottom: 40 })
        }
        .width('100%')
        .height('100%')
        .align(Alignment.TopStart)
        .edgeEffect(EdgeEffect.Spring)
        .scrollBar(BarState.Auto)
      }
    }
    .titleBar({
      padding: {
        start: LengthMetrics.vp(16),
        end: LengthMetrics.vp(16)
      },
      style: {
        originalStyle: {
          backgroundStyle: { backgroundColor: this.themeColor('panel_background') },
          contentStyle: {
            titleStyle: { mainTitleColor: this.themeColor('text_primary') },
            backIconStyle: { backgroundColor: this.themeColor('comp_background_tertiary'), iconColor: this.themeColor('icon_primary') }
          }
        }
      },
      content: {
        title: { mainTitle: '错误管理' }
      }
    })
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      this.onPageShow();
      this.onReady();
    })
    .backgroundColor(Color.Transparent)
  }
}
